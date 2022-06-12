--
-- PostgreSQL database dump
--

-- Dumped from database version 13.7 (Debian 13.7-0+deb11u1)
-- Dumped by pg_dump version 13.7 (Debian 13.7-0+deb11u1)

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
-- Name: add_constraints_to_account_merges_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_account_merges_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE account_merges_' || partition_suffix || ' '
      'ADD CONSTRAINT account_merges_' || partition_suffix || '_account_merge_request_serial_id_key '
        'UNIQUE (account_merge_request_serial_id) '
  );
END
$$;


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
-- Name: add_constraints_to_contracts_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_contracts_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE contracts_' || partition_suffix || ' '
      'ADD CONSTRAINT contracts_' || partition_suffix || '_contract_serial_id_key '
        'UNIQUE (contract_serial_id) '
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
        'PRIMARY KEY (deposit_serial_id) '
      ',ADD CONSTRAINT deposits_' || partition_suffix || '_coin_pub_merchant_pub_h_contract_terms_key '
        'UNIQUE (coin_pub, merchant_pub, h_contract_terms)'
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
-- Name: add_constraints_to_purse_deposits_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_purse_deposits_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE purse_deposits_' || partition_suffix || ' '
      'ADD CONSTRAINT purse_deposits_' || partition_suffix || '_purse_deposit_serial_id_key '
        'UNIQUE (purse_deposit_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_purse_merges_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_purse_merges_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE purse_merges_' || partition_suffix || ' '
      'ADD CONSTRAINT purse_merges_' || partition_suffix || '_purse_merge_request_serial_id_key '
        'UNIQUE (purse_merge_request_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_purse_requests_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_purse_requests_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE purse_requests_' || partition_suffix || ' '
      'ADD CONSTRAINT purse_requests_' || partition_suffix || '_purse_requests_serial_id_key '
        'UNIQUE (purse_requests_serial_id) '
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
-- Name: add_constraints_to_wad_in_entries_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wad_in_entries_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wad_in_entries_' || partition_suffix || ' '
      'ADD CONSTRAINT wad_in_entries_' || partition_suffix || '_wad_in_entry_serial_id_key '
        'UNIQUE (wad_in_entry_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_wad_out_entries_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wad_out_entries_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wad_out_entries_' || partition_suffix || ' '
      'ADD CONSTRAINT wad_out_entries_' || partition_suffix || '_wad_out_entry_serial_id_key '
        'UNIQUE (wad_out_entry_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_wads_in_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wads_in_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wads_in_' || partition_suffix || ' '
      'ADD CONSTRAINT wads_in_' || partition_suffix || '_wad_in_serial_id_key '
        'UNIQUE (wad_in_serial_id) '
      ',ADD CONSTRAINT wads_in_' || partition_suffix || '_wad_is_origin_exchange_url_key '
        'UNIQUE (wad_id, origin_exchange_url) '
  );
END
$$;


--
-- Name: add_constraints_to_wads_out_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wads_out_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wads_out_' || partition_suffix || ' '
      'ADD CONSTRAINT wads_out_' || partition_suffix || '_wad_out_serial_id_key '
        'UNIQUE (wad_out_serial_id) '
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
-- Name: create_foreign_hash_partition(character varying, integer, character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_foreign_hash_partition(source_table_name character varying, modulus integer, shard_suffix character varying, current_shard_num integer, local_user character varying DEFAULT 'taler-exchange-httpd'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Creating %_% on %', source_table_name, shard_suffix, shard_suffix;

  EXECUTE FORMAT(
    'CREATE FOREIGN TABLE IF NOT EXISTS %I '
      'PARTITION OF %I '
      'FOR VALUES WITH (MODULUS %s, REMAINDER %s) '
      'SERVER %I'
    ,source_table_name || '_' || shard_suffix
    ,source_table_name
    ,modulus
    ,current_shard_num-1
    ,shard_suffix
  );

  EXECUTE FORMAT(
    'ALTER FOREIGN TABLE %I OWNER TO %I'
    ,source_table_name || '_' || shard_suffix
    ,local_user
  );

END
$$;


--
-- Name: create_foreign_range_partition(character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_foreign_range_partition(source_table_name character varying, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
   RAISE NOTICE 'TODO';
END
$$;


--
-- Name: create_foreign_servers(integer, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_foreign_servers(amount integer, domain character varying, remote_user character varying DEFAULT 'taler'::character varying, remote_user_password character varying DEFAULT 'taler'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  PERFORM prepare_sharding();

  FOR i IN 1..amount LOOP
    PERFORM create_shard_server(
      i::varchar
     ,amount
     ,i
     ,'shard-' || i::varchar || '.' || domain
     ,remote_user
     ,remote_user_password
     ,'taler-exchange'
     ,'5432'
     ,'taler-exchange-httpd'
    );
  END LOOP;

  PERFORM drop_default_partitions();

END
$$;


--
-- Name: create_hash_partition(character varying, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_hash_partition(source_table_name character varying, modulus integer, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Creating partition %_%', source_table_name, partition_num;

  EXECUTE FORMAT(
    'CREATE TABLE IF NOT EXISTS %I '
      'PARTITION OF %I '
      'FOR VALUES WITH (MODULUS %s, REMAINDER %s)'
    ,source_table_name || '_' || partition_num
    ,source_table_name
    ,modulus
    ,partition_num-1
  );

END
$$;


--
-- Name: create_partitioned_table(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_partitioned_table(table_definition character varying, table_name character varying, main_table_partition_str character varying, shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  IF shard_suffix IS NOT NULL THEN
    table_name=table_name || '_' || shard_suffix;
    main_table_partition_str = '';
  END IF;

  EXECUTE FORMAT(
    table_definition,
    table_name,
    main_table_partition_str
  );

END
$$;


--
-- Name: create_partitions(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_partitions(num_partitions integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  modulus INTEGER;
BEGIN

  modulus := num_partitions;

  PERFORM detach_default_partitions();

  LOOP

    PERFORM create_hash_partition(
      'wire_targets'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wire_targets_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'reserves'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'reserves_in'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_in_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'reserves_close'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_close_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'reserves_out'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_out_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'reserves_out_by_reserve'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'known_coins'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_known_coins_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'refresh_commitments'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_commitments_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'refresh_revealed_coins'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_revealed_coins_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'refresh_transfer_keys'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_transfer_keys_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'deposits'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_deposits_partition(num_partitions::varchar);

-- TODO: dynamically (!) creating/deleting deposits partitions:
--    create new partitions 'as needed', drop old ones once the aggregator has made
--    them empty; as 'new' deposits will always have deadlines in the future, this
--    would basically guarantee no conflict between aggregator and exchange service!
-- SEE also: https://www.cybertec-postgresql.com/en/automatic-partition-creation-in-postgresql/
-- (article is slightly wrong, as this works:)
--CREATE TABLE tab (
--  id bigint GENERATED ALWAYS AS IDENTITY,
--  ts timestamp NOT NULL,
--  data text
-- PARTITION BY LIST ((ts::date));
-- CREATE TABLE tab_def PARTITION OF tab DEFAULT;
-- BEGIN
-- CREATE TABLE tab_part2 (LIKE tab);
-- insert into tab_part2 (id,ts, data) values (5,'2022-03-21', 'foo');
-- alter table tab attach partition tab_part2 for values in ('2022-03-21');
-- commit;
-- Naturally, to ensure this is actually 100% conflict-free, we'd
-- need to create tables at the granularity of the wire/refund deadlines;
-- that is right now configurable via AGGREGATOR_SHIFT option.

-- FIXME: range partitioning
--    PERFORM create_range_partition(
--      'deposits_by_ready'
--      ,modulus
--      ,num_partitions
--    );
--
--    PERFORM create_range_partition(
--      'deposits_for_matching'
--      ,modulus
--      ,num_partitions
--    );

    PERFORM create_hash_partition(
      'refunds'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refunds_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'wire_out'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wire_out_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'aggregation_transient'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'aggregation_tracking'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_aggregation_tracking_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'recoup'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_recoup_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'recoup_by_reserve'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'recoup_refresh'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_recoup_refresh_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'prewire'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'cs_nonce_locks'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_cs_nonce_locks_partition(num_partitions::varchar);

    ---------------- P2P ----------------------

    PERFORM create_hash_partition(
      'purse_requests'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_requests_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'purse_merges'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_merges_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'account_merges'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_account_merges_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'contracts'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_contracts_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'history_requests'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'close_requests'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'purse_deposits'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_deposits_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'wad_out_entries'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wad_out_entries_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'wads_in'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wads_in_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'wad_in_entries'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wad_in_entries_partition(num_partitions::varchar);

    num_partitions=num_partitions-1;
    EXIT WHEN num_partitions=0;

  END LOOP;

  PERFORM drop_default_partitions();

END
$$;


--
-- Name: create_range_partition(character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_range_partition(source_table_name character varying, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE NOTICE 'TODO';
END
$$;


--
-- Name: create_shard_server(character varying, integer, integer, character varying, character varying, character varying, character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying DEFAULT 'taler-exchange'::character varying, remote_port integer DEFAULT 5432, local_user character varying DEFAULT 'taler-exchange-httpd'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Creating server %', remote_host;

  EXECUTE FORMAT(
    'CREATE SERVER IF NOT EXISTS %I '
      'FOREIGN DATA WRAPPER postgres_fdw '
      'OPTIONS (dbname %L, host %L, port %L)'
    ,shard_suffix
    ,remote_db_name
    ,remote_host
    ,remote_port
  );

  EXECUTE FORMAT(
    'CREATE USER MAPPING IF NOT EXISTS '
      'FOR %I SERVER %I '
      'OPTIONS (user %L, password %L)'
    ,local_user
    ,shard_suffix
    ,remote_user
    ,remote_user_password
  );

  EXECUTE FORMAT(
    'GRANT ALL PRIVILEGES '
      'ON FOREIGN SERVER %I '
      'TO %I;'
    ,shard_suffix
    ,local_user
  );

  PERFORM create_foreign_hash_partition(
    'wire_targets'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves_in'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves_out'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves_out_by_reserve'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves_close'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'known_coins'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'refresh_commitments'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'refresh_revealed_coins'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'refresh_transfer_keys'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'deposits'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
--  PERFORM create_foreign_range_partition(
--    'deposits_by_ready'
--    ,total_num_shards
--    ,shard_suffix
--    ,current_shard_num
--    ,local_user
--  );
--  PERFORM create_foreign_range_partition(
--    'deposits_for_matching'
--    ,total_num_shards
--    ,shard_suffix
--    ,current_shard_num
--    ,local_user
--  );
  PERFORM create_foreign_hash_partition(
    'refunds'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'wire_out'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'aggregation_transient'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'aggregation_tracking'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'recoup'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'recoup_by_reserve'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'recoup_refresh'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'prewire'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'cs_nonce_locks'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );

  ------------------- P2P --------------------

  PERFORM create_foreign_hash_partition(
    'purse_requests'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'purse_merges'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'account_merges'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'contracts'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'history_requests'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'close_requests'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'purse_deposits'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'wad_out_entries'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'wads_in'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'wad_in_entries'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );

END
$$;


--
-- Name: FUNCTION create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying, remote_port integer, local_user character varying); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying, remote_port integer, local_user character varying) IS 'Create a shard server on the master
      node with all foreign tables and user mappings';


--
-- Name: create_table_account_merges(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_account_merges(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'account_merges';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(account_merge_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves (reserve_pub) ON DELETE CASCADE
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)' -- REFERENCES purse_requests (purse_pub)
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by reserve_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );

END
$$;


--
-- Name: create_table_aggregation_tracking(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_aggregation_tracking(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'aggregation_tracking';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(aggregation_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
	    ',deposit_serial_id INT8 PRIMARY KEY' -- REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE' -- FIXME chnage to coint_pub + deposit_serial_id for more efficient depost -- or something else ???
      ',wtid_raw BYTEA NOT NULL' -- CONSTRAINT wire_out_ref REFERENCES wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (deposit_serial_id)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_wtid_raw_index '
    'ON ' || table_name || ' '
    '(wtid_raw);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_wtid_raw_index '
    'IS ' || quote_literal('for lookup_transactions') || ';'
  );

END
$$;


--
-- Name: create_table_aggregation_transient(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_aggregation_transient(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'aggregation_transient';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
      ',exchange_account_section TEXT NOT NULL'
      ',wtid_raw BYTEA NOT NULL CHECK (LENGTH(wtid_raw)=32)'
      ') %s ;'
      ,table_name
      ,'PARTITION BY HASH (wire_target_h_payto)'
      ,shard_suffix
  );

END
$$;


--
-- Name: create_table_close_requests(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_close_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'close_requests';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(close_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE'
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves(reserve_pub) ON DELETE CASCADE
      ',close_timestamp INT8 NOT NULL'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',close_val INT8 NOT NULL'
      ',close_frac INT4 NOT NULL'
      ',PRIMARY KEY (reserve_pub,close_timestamp)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_contracts(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_contracts(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'contracts';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(contract_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',pub_ckey BYTEA NOT NULL CHECK (LENGTH(pub_ckey)=32)'
      ',contract_sig BYTEA NOT NULL CHECK (LENGTH(contract_sig)=64)'
      ',e_contract BYTEA NOT NULL'
      ',purse_expiration INT8 NOT NULL'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_cs_nonce_locks(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_cs_nonce_locks(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(cs_nonce_lock_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',nonce BYTEA PRIMARY KEY CHECK (LENGTH(nonce)=32)'
      ',op_hash BYTEA NOT NULL CHECK (LENGTH(op_hash)=64)'
      ',max_denomination_serial INT8 NOT NULL'
    ') %s ;'
    ,'cs_nonce_locks'
    ,'PARTITION BY HASH (nonce)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_deposits(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_deposits(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(deposit_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- PRIMARY KEY'
      ',shard INT8 NOT NULL'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE
      ',known_coin_id INT8 NOT NULL' -- REFERENCES known_coins (known_coin_id) ON DELETE CASCADE' --- FIXME: column needed???
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',wallet_timestamp INT8 NOT NULL'
      ',exchange_timestamp INT8 NOT NULL'
      ',refund_deadline INT8 NOT NULL'
      ',wire_deadline INT8 NOT NULL'
      ',merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)'
      ',h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)'
      ',coin_sig BYTEA NOT NULL CHECK (LENGTH(coin_sig)=64)'
      ',wire_salt BYTEA NOT NULL CHECK (LENGTH(wire_salt)=16)'
      ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
      ',done BOOLEAN NOT NULL DEFAULT FALSE'
      ',extension_blocked BOOLEAN NOT NULL DEFAULT FALSE'
      ',extension_details_serial_id INT8' -- REFERENCES extension_details (extension_details_serial_id) ON DELETE CASCADE'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub_index '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_deposits_by_ready(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_deposits_by_ready(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits_by_ready';
BEGIN

  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(wire_deadline INT8 NOT NULL'
    ',shard INT8 NOT NULL'
    ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)'
    ',deposit_serial_id INT8'
    ') %s ;'
    ,table_name
    ,'PARTITION BY RANGE (wire_deadline)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_main_index '
    'ON ' || table_name || ' '
    '(wire_deadline ASC, shard ASC, coin_pub);'
  );

END
$$;


--
-- Name: create_table_deposits_for_matching(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_deposits_for_matching(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits_for_matching';
BEGIN

  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(refund_deadline INT8 NOT NULL'
    ',merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)'
    ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE
    ',deposit_serial_id INT8'
    ') %s ;'
    ,table_name
    ,'PARTITION BY RANGE (refund_deadline)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_main_index '
    'ON ' || table_name || ' '
    '(refund_deadline ASC, merchant_pub, coin_pub);'
  );

END
$$;


--
-- Name: create_table_history_requests(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_history_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'history_requests';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(history_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE'
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves(reserve_pub) ON DELETE CASCADE
      ',request_timestamp INT8 NOT NULL'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',history_fee_val INT8 NOT NULL'
      ',history_fee_frac INT4 NOT NULL'
      ',PRIMARY KEY (reserve_pub,request_timestamp)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_known_coins(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_known_coins(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'known_coins';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(known_coin_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',denominations_serial INT8 NOT NULL' -- REFERENCES denominations (denominations_serial) ON DELETE CASCADE'
      ',coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)'
      ',age_commitment_hash BYTEA CHECK (LENGTH(age_commitment_hash)=32)'
      ',denom_sig BYTEA NOT NULL'
      ',remaining_val INT8 NOT NULL DEFAULT(0)'
      ',remaining_frac INT4 NOT NULL DEFAULT(0)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)' -- FIXME: or include denominations_serial? or multi-level partitioning?;
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

END
$$;


--
-- Name: create_table_prewire(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_prewire(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'prewire';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(prewire_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY'
      ',wire_method TEXT NOT NULL'
      ',finished BOOLEAN NOT NULL DEFAULT false'
      ',failed BOOLEAN NOT NULL DEFAULT false'
      ',buf BYTEA NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (prewire_uuid)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_finished_index '
    'ON ' || table_name || ' '
    '(finished);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_finished_index '
    'IS ' || quote_literal('for gc_prewire') || ';'
  );
  -- FIXME: find a way to combine these two indices?
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_failed_finished_index '
    'ON ' || table_name || ' '
    '(failed,finished);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_failed_finished_index '
    'IS ' || quote_literal('for wire_prepare_data_get') || ';'
  );

END
$$;


--
-- Name: create_table_purse_deposits(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_purse_deposits(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_deposits';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_deposit_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE
      ',partner_serial_id INT8' -- REFERENCES partners(partner_serial_id) ON DELETE CASCADE'
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',coin_pub BYTEA NOT NULL' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',PRIMARY KEY (purse_pub,coin_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by coin_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_purse_merges(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_purse_merges(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_merges';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_merge_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY '-- UNIQUE
      ',partner_serial_id INT8' -- REFERENCES partners(partner_serial_id) ON DELETE CASCADE
      ',reserve_pub BYTEA NOT NULL CHECK(length(reserve_pub)=32)'--REFERENCES reserves (reserve_pub) ON DELETE CASCADE
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)' --REFERENCES purse_requests (purse_pub) ON DELETE CASCADE
      ',merge_sig BYTEA NOT NULL CHECK (LENGTH(merge_sig)=64)'
      ',merge_timestamp INT8 NOT NULL'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by reserve_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_reserve_pub '
    'IS ' || quote_literal('needed in reserve history computation') || ';'
  );

END
$$;


--
-- Name: create_table_purse_requests(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_purse_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_requests';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_requests_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',merge_pub BYTEA NOT NULL CHECK (LENGTH(merge_pub)=32)'
      ',purse_creation INT8 NOT NULL'
      ',purse_expiration INT8 NOT NULL'
      ',h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)'
      ',age_limit INT4 NOT NULL'
      ',flags INT4 NOT NULL'
      ',refunded BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',finished BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',in_reserve_quota BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',purse_fee_val INT8 NOT NULL'
      ',purse_fee_frac INT4 NOT NULL'
      ',balance_val INT8 NOT NULL DEFAULT (0)'
      ',balance_frac INT4 NOT NULL DEFAULT (0)'
      ',purse_sig BYTEA NOT NULL CHECK(LENGTH(purse_sig)=64)'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by merge_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_merge_pub '
    'ON ' || table_name || ' '
    '(merge_pub);'
  );

  -- FIXME: drop index on master (crosses shards)?
  -- Or use materialized index? (needed?)
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_purse_expiration '
    'ON ' || table_name || ' '
    '(purse_expiration);'
  );

END
$$;


--
-- Name: create_table_recoup(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_recoup(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(recoup_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub)
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',recoup_timestamp INT8 NOT NULL'
      ',reserve_out_serial_id INT8 NOT NULL' -- REFERENCES reserves_out (reserve_out_serial_id) ON DELETE CASCADE'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub);'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub_index '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_recoup_by_reserve(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_recoup_by_reserve(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup_by_reserve';
BEGIN

  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(reserve_out_serial_id INT8 NOT NULL' -- REFERENCES reserves (reserve_out_serial_id) ON DELETE CASCADE
    ',coin_pub BYTEA CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub)
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_out_serial_id)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_main_index '
    'ON ' || table_name || ' '
    '(reserve_out_serial_id);'
  );

END
$$;


--
-- Name: create_table_recoup_refresh(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_recoup_refresh(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup_refresh';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(recoup_refresh_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub)
      ',known_coin_id BIGINT NOT NULL' -- REFERENCES known_coins (known_coin_id) ON DELETE CASCADE
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',recoup_timestamp INT8 NOT NULL'
      ',rrc_serial INT8 NOT NULL' -- REFERENCES refresh_revealed_coins (rrc_serial) ON DELETE CASCADE -- UNIQUE'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: any query using this index will be slow. Materialize index or change query?
  -- Also: which query uses this index?
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_rrc_serial_index '
    'ON ' || table_name || ' '
    '(rrc_serial);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub_index '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_refresh_commitments(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_refresh_commitments(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_commitments';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(melt_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)'
      ',old_coin_pub BYTEA NOT NULL' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE'
      ',old_coin_sig BYTEA NOT NULL CHECK(LENGTH(old_coin_sig)=64)'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',noreveal_index INT4 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (rc)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- Note: index spans partitions, may need to be materialized.
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_old_coin_pub_index '
    'ON ' || table_name || ' '
    '(old_coin_pub);'
  );

END
$$;


--
-- Name: create_table_refresh_revealed_coins(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_refresh_revealed_coins(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_revealed_coins';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(rrc_serial BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',melt_serial_id INT8 NOT NULL' -- REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE'
      ',freshcoin_index INT4 NOT NULL'
      ',link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)'
      ',denominations_serial INT8 NOT NULL' -- REFERENCES denominations (denominations_serial) ON DELETE CASCADE'
      ',coin_ev BYTEA NOT NULL' -- UNIQUE'
      ',h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64)' -- UNIQUE'
      ',ev_sig BYTEA NOT NULL'
      ',ewv BYTEA NOT NULL'
      --  ,PRIMARY KEY (melt_serial_id, freshcoin_index) -- done per shard
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (melt_serial_id)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_coins_by_melt_serial_id_index '
    'ON ' || table_name || ' '
    '(melt_serial_id);'
  );

END
$$;


--
-- Name: create_table_refresh_transfer_keys(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_refresh_transfer_keys(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_transfer_keys';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(rtc_serial BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',melt_serial_id INT8 PRIMARY KEY' -- REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE'
      ',transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)'
      ',transfer_privs BYTEA NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (melt_serial_id)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_refunds(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_refunds(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refunds';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(refund_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE
      ',deposit_serial_id INT8 NOT NULL' -- REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE'
      ',merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)'
      ',rtransaction_id INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      -- ,PRIMARY KEY (deposit_serial_id, rtransaction_id) -- done per shard!
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub_index '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_reserves(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'reserves';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY'
      ',reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)'
      ',current_balance_val INT8 NOT NULL DEFAULT(0)'
      ',current_balance_frac INT4 NOT NULL DEFAULT(0)'
      ',purses_active INT8 NOT NULL DEFAULT(0)'
      ',purses_allowed INT8 NOT NULL DEFAULT(0)'
      ',kyc_required BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',kyc_passed BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',max_age INT4 NOT NULL DEFAULT(120)'
      ',expiration_date INT8 NOT NULL'
      ',gc_date INT8 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_expiration_index '
    'ON ' || table_name || ' '
    '(expiration_date'
    ',current_balance_val'
    ',current_balance_frac'
    ');'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_expiration_index '
    'IS ' || quote_literal('used in get_expired_reserves') || ';'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_uuid_index '
    'ON ' || table_name || ' '
    '(reserve_uuid);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_gc_date_index '
    'ON ' || table_name || ' '
    '(gc_date);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_gc_date_index '
    'IS ' || quote_literal('for reserve garbage collection') || ';'
  );

END
$$;


--
-- Name: create_table_reserves_close(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves_close(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_close';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(close_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE / PRIMARY KEY'
      ',reserve_pub BYTEA NOT NULL' -- REFERENCES reserves (reserve_pub) ON DELETE CASCADE'
      ',execution_date INT8 NOT NULL'
      ',wtid BYTEA NOT NULL CHECK (LENGTH(wtid)=32)'
      ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',closing_fee_val INT8 NOT NULL'
      ',closing_fee_frac INT4 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_close_uuid_index '
    'ON ' || table_name || ' '
    '(close_uuid);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub_index '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
END
$$;


--
-- Name: create_table_reserves_in(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves_in(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_in';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',reserve_pub BYTEA PRIMARY KEY' -- REFERENCES reserves (reserve_pub) ON DELETE CASCADE'
      ',wire_reference INT8 NOT NULL'
      ',credit_val INT8 NOT NULL'
      ',credit_frac INT4 NOT NULL'
      ',wire_source_h_payto BYTEA CHECK (LENGTH(wire_source_h_payto)=32)'
      ',exchange_account_section TEXT NOT NULL'
      ',execution_date INT8 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_in_serial_id_index '
    'ON ' || table_name || ' '
    '(reserve_in_serial_id);'
  );
  -- FIXME: where do we need this index? Can we do better?
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_exch_accnt_section_execution_date_idx '
    'ON ' || table_name || ' '
    '(exchange_account_section '
    ',execution_date'
    ');'
  );
  -- FIXME: where do we need this index? Can we do better?
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_exch_accnt_reserve_in_serial_id_idx '
    'ON ' || table_name || ' '
    '(exchange_account_section,'
    'reserve_in_serial_id DESC'
    ');'
  );

END
$$;


--
-- Name: create_table_reserves_out(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_out';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',h_blind_ev BYTEA CHECK (LENGTH(h_blind_ev)=64) UNIQUE'
      ',denominations_serial INT8 NOT NULL' -- REFERENCES denominations (denominations_serial)'
      ',denom_sig BYTEA NOT NULL'
      ',reserve_uuid INT8 NOT NULL' -- REFERENCES reserves (reserve_uuid) ON DELETE CASCADE'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',execution_date INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
    ') %s ;'
    ,'reserves_out'
    ,'PARTITION BY HASH (h_blind_ev)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_out_serial_id_index '
    'ON ' || table_name || ' '
    '(reserve_out_serial_id);'
  );
  -- FIXME: change query to use reserves_out_by_reserve instead and materialize execution_date there as well???
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_uuid_and_execution_date_index '
    'ON ' || table_name || ' '
    '(reserve_uuid, execution_date);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_reserve_uuid_and_execution_date_index '
    'IS ' || quote_literal('for get_reserves_out and exchange_do_withdraw_limit_check') || ';'
  );

END
$$;


--
-- Name: create_table_reserves_out_by_reserve(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves_out_by_reserve(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'reserves_out_by_reserve';
BEGIN

  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(reserve_uuid INT8 NOT NULL' -- REFERENCES reserves (reserve_uuid) ON DELETE CASCADE
    ',h_blind_ev BYTEA CHECK (LENGTH(h_blind_ev)=64)'
    ') %s '
    ,table_name
    ,'PARTITION BY HASH (reserve_uuid)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_main_index '
    'ON ' || table_name || ' '
    '(reserve_uuid);'
  );

END
$$;


--
-- Name: create_table_wad_in_entries(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wad_in_entries(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wad_in_entries';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_in_entry_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',wad_in_serial_id INT8' -- REFERENCES wads_in (wad_in_serial_id) ON DELETE CASCADE
      ',reserve_pub BYTEA NOT NULL CHECK(LENGTH(reserve_pub)=32)'
      ',purse_pub BYTEA PRIMARY KEY CHECK(LENGTH(purse_pub)=32)'
      ',h_contract BYTEA NOT NULL CHECK(LENGTH(h_contract)=64)'
      ',purse_expiration INT8 NOT NULL'
      ',merge_timestamp INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',wad_fee_val INT8 NOT NULL'
      ',wad_fee_frac INT4 NOT NULL'
      ',deposit_fees_val INT8 NOT NULL'
      ',deposit_fees_frac INT4 NOT NULL'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',purse_sig BYTEA NOT NULL CHECK (LENGTH(purse_sig)=64)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by reserve_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_reserve_pub '
    'IS ' || quote_literal('needed in reserve history computation') || ';'
  );

END
$$;


--
-- Name: create_table_wad_out_entries(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wad_out_entries(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wad_out_entries';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_out_entry_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',wad_out_serial_id INT8' -- REFERENCES wads_out (wad_out_serial_id) ON DELETE CASCADE
      ',reserve_pub BYTEA NOT NULL CHECK(LENGTH(reserve_pub)=32)'
      ',purse_pub BYTEA PRIMARY KEY CHECK(LENGTH(purse_pub)=32)'
      ',h_contract BYTEA NOT NULL CHECK(LENGTH(h_contract)=64)'
      ',purse_expiration INT8 NOT NULL'
      ',merge_timestamp INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',wad_fee_val INT8 NOT NULL'
      ',wad_fee_frac INT4 NOT NULL'
      ',deposit_fees_val INT8 NOT NULL'
      ',deposit_fees_frac INT4 NOT NULL'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',purse_sig BYTEA NOT NULL CHECK (LENGTH(purse_sig)=64)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by reserve_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );

END
$$;


--
-- Name: create_table_wads_in(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wads_in(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wads_in';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',wad_id BYTEA PRIMARY KEY CHECK (LENGTH(wad_id)=24)'
      ',origin_exchange_url TEXT NOT NULL'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',arrival_time INT8 NOT NULL'
      ',UNIQUE (wad_id, origin_exchange_url)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (wad_id)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_wads_out(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wads_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wads_out';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',wad_id BYTEA PRIMARY KEY CHECK (LENGTH(wad_id)=24)'
      ',partner_serial_id INT8 NOT NULL' -- REFERENCES partners(partner_serial_id) ON DELETE CASCADE
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',execution_time INT8 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (wad_id)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_wire_out(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wire_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wire_out';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(wireout_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' -- PRIMARY KEY'
      ',execution_date INT8 NOT NULL'
      ',wtid_raw BYTEA UNIQUE NOT NULL CHECK (LENGTH(wtid_raw)=32)'
      ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
      ',exchange_account_section TEXT NOT NULL'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (wtid_raw)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_wire_target_h_payto_index '
    'ON ' || table_name || ' '
    '(wire_target_h_payto);'
  );


END
$$;


--
-- Name: create_table_wire_targets(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wire_targets(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(wire_target_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',wire_target_h_payto BYTEA PRIMARY KEY CHECK (LENGTH(wire_target_h_payto)=32)'
      ',payto_uri VARCHAR NOT NULL'
      ',kyc_ok BOOLEAN NOT NULL DEFAULT (FALSE)'
      ',external_id VARCHAR'
    ') %s ;'
    ,'wire_targets'
    ,'PARTITION BY HASH (wire_target_h_payto)'
    ,shard_suffix
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
-- Name: deposits_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_ready BOOLEAN;
BEGIN
  was_ready  = NOT (OLD.done OR OLD.extension_blocked);

  IF (was_ready)
  THEN
    DELETE FROM deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposits_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_delete_trigger() IS 'Replicate deposit deletions into materialized indices.';


--
-- Name: deposits_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_ready BOOLEAN;
BEGIN
  is_ready  = NOT (NEW.done OR NEW.extension_blocked);

  IF (is_ready)
  THEN
    INSERT INTO deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
    INSERT INTO deposits_for_matching
      (refund_deadline
      ,merchant_pub
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.refund_deadline
      ,NEW.merchant_pub
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposits_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_insert_trigger() IS 'Replicate deposit inserts into materialized indices.';


--
-- Name: deposits_update_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_ready BOOLEAN;
DECLARE
  is_ready BOOLEAN;
BEGIN
  was_ready = NOT (OLD.done OR OLD.extension_blocked);
  is_ready  = NOT (NEW.done OR NEW.extension_blocked);
  IF (was_ready AND NOT is_ready)
  THEN
    DELETE FROM deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  IF (is_ready AND NOT was_ready)
  THEN
    INSERT INTO deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
    INSERT INTO deposits_for_matching
      (refund_deadline
      ,merchant_pub
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.refund_deadline
      ,NEW.merchant_pub
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposits_update_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_update_trigger() IS 'Replicate deposits changes into materialized indices.';


--
-- Name: detach_default_partitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.detach_default_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Detaching all default table partitions';

  ALTER TABLE IF EXISTS wire_targets
    DETACH PARTITION wire_targets_default;

  ALTER TABLE IF EXISTS reserves
    DETACH PARTITION reserves_default;

  ALTER TABLE IF EXISTS reserves_in
    DETACH PARTITION reserves_in_default;

  ALTER TABLE IF EXISTS reserves_close
    DETACH PARTITION reserves_close_default;

  ALTER TABLE IF EXISTS reserves_out
    DETACH PARTITION reserves_out_default;

  ALTER TABLE IF EXISTS reserves_out_by_reserve
    DETACH PARTITION reserves_out_by_reserve_default;

  ALTER TABLE IF EXISTS known_coins
    DETACH PARTITION known_coins_default;

  ALTER TABLE IF EXISTS refresh_commitments
    DETACH PARTITION refresh_commitments_default;

  ALTER TABLE IF EXISTS refresh_revealed_coins
    DETACH PARTITION refresh_revealed_coins_default;

  ALTER TABLE IF EXISTS refresh_transfer_keys
    DETACH PARTITION refresh_transfer_keys_default;

  ALTER TABLE IF EXISTS deposits
    DETACH PARTITION deposits_default;

--- TODO range partitioning
--  ALTER TABLE IF EXISTS deposits_by_ready
--    DETACH PARTITION deposits_by_ready_default;
--
--  ALTER TABLE IF EXISTS deposits_for_matching
--    DETACH PARTITION deposits_default_for_matching_default;

  ALTER TABLE IF EXISTS refunds
    DETACH PARTITION refunds_default;

  ALTER TABLE IF EXISTS wire_out
    DETACH PARTITION wire_out_default;

  ALTER TABLE IF EXISTS aggregation_transient
    DETACH PARTITION aggregation_transient_default;

  ALTER TABLE IF EXISTS aggregation_tracking
    DETACH PARTITION aggregation_tracking_default;

  ALTER TABLE IF EXISTS recoup
    DETACH PARTITION recoup_default;

  ALTER TABLE IF EXISTS recoup_by_reserve
    DETACH PARTITION recoup_by_reserve_default;

  ALTER TABLE IF EXISTS recoup_refresh
    DETACH PARTITION recoup_refresh_default;

  ALTER TABLE IF EXISTS prewire
    DETACH PARTITION prewire_default;

  ALTER TABLE IF EXISTS cs_nonce_locks
    DETACH partition cs_nonce_locks_default;

  ALTER TABLE IF EXISTS purse_requests
    DETACH partition purse_requests_default;

  ALTER TABLE IF EXISTS purse_merges
    DETACH partition purse_merges_default;

  ALTER TABLE IF EXISTS account_merges
    DETACH partition account_merges_default;

  ALTER TABLE IF EXISTS contracts
    DETACH partition contracts_default;

  ALTER TABLE IF EXISTS history_requests
    DETACH partition history_requests_default;

  ALTER TABLE IF EXISTS close_requests
    DETACH partition close_requests_default;

  ALTER TABLE IF EXISTS purse_deposits
    DETACH partition purse_deposits_default;

  ALTER TABLE IF EXISTS wad_out_entries
    DETACH partition wad_out_entries_default;

  ALTER TABLE IF EXISTS wads_in
    DETACH partition wads_in_default;

  ALTER TABLE IF EXISTS wad_in_entries
    DETACH partition wad_in_entries_default;
END
$$;


--
-- Name: FUNCTION detach_default_partitions(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.detach_default_partitions() IS 'We need to drop default and create new one before deleting the default partitions
      otherwise constraints get lost too. Might be needed in shardig too';


--
-- Name: drop_default_partitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.drop_default_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Dropping default table partitions';

  DROP TABLE IF EXISTS wire_targets_default;
  DROP TABLE IF EXISTS reserves_default;
  DROP TABLE IF EXISTS reserves_in_default;
  DROP TABLE IF EXISTS reserves_close_default;
  DROP TABLE IF EXISTS reserves_out_default;
  DROP TABLE IF EXISTS reserves_out_by_reserve_default;
  DROP TABLE IF EXISTS known_coins_default;
  DROP TABLE IF EXISTS refresh_commitments_default;
  DROP TABLE IF EXISTS refresh_revealed_coins_default;
  DROP TABLE IF EXISTS refresh_transfer_keys_default;
  DROP TABLE IF EXISTS deposits_default;
--DROP TABLE IF EXISTS deposits_by_ready_default;
--DROP TABLE IF EXISTS deposits_for_matching_default;
  DROP TABLE IF EXISTS refunds_default;
  DROP TABLE IF EXISTS wire_out_default;
  DROP TABLE IF EXISTS aggregation_transient_default;
  DROP TABLE IF EXISTS aggregation_tracking_default;
  DROP TABLE IF EXISTS recoup_default;
  DROP TABLE IF EXISTS recoup_by_reserve_default;
  DROP TABLE IF EXISTS recoup_refresh_default;
  DROP TABLE IF EXISTS prewire_default;
  DROP TABLE IF EXISTS cs_nonce_locks_default;

  DROP TABLE IF EXISTS purse_requests_default;
  DROP TABLE IF EXISTS purse_merges_default;
  DROP TABLE IF EXISTS account_merges_default;
  DROP TABLE IF EXISTS contracts_default;
  DROP TABLE IF EXISTS history_requests_default;
  DROP TABLE IF EXISTS close_requests_default;
  DROP TABLE IF EXISTS purse_deposits_default;
  DROP TABLE IF EXISTS wad_out_entries_default;
  DROP TABLE IF EXISTS wads_in_default;
  DROP TABLE IF EXISTS wad_in_entries_default;

END
$$;


--
-- Name: FUNCTION drop_default_partitions(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.drop_default_partitions() IS 'Drop all default partitions once other partitions are attached.
      Might be needed in sharding too.';


--
-- Name: exchange_do_account_merge(bytea, bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_account_merge(in_purse_pub bytea, in_reserve_pub bytea, in_reserve_sig bytea, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME: function/API is dead! Do DCE?
END $$;


--
-- Name: exchange_do_batch_withdraw(bigint, integer, bytea, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  reserve_gc INT8;
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


-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
-- SELECT
--    kyc_ok
--   ,wire_target_serial_id
--   INTO
--    kycok
--   ,account_uuid
--   FROM reserves_in
--   JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
--  WHERE reserve_pub=rpub
--  LIMIT 1; -- limit 1 should not be required (without p2p transfers)

WITH reserves_in AS materialized (
  SELECT wire_source_h_payto
  FROM reserves_in WHERE
  reserve_pub=rpub
)
SELECT
  kyc_ok
  ,wire_target_serial_id
INTO
  kycok
  ,account_uuid
FROM wire_targets
  WHERE wire_target_h_payto = (
    SELECT wire_source_h_payto
      FROM reserves_in
  );

END $$;


--
-- Name: FUNCTION exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result. Excludes storing the planchets.';


--
-- Name: exchange_do_batch_withdraw_insert(bytea, bigint, integer, bytea, bigint, bytea, bytea, bytea, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  denom_serial INT8;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

out_denom_unknown=TRUE;
out_conflict=TRUE;
out_nonce_reuse=TRUE;

SELECT denominations_serial
  INTO denom_serial
  FROM denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  out_denom_unknown=TRUE;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;
out_denom_unknown=FALSE;

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
  out_conflict=TRUE;
  RETURN;
END IF;
out_conflict=FALSE;

-- Special actions needed for a CS withdraw?
out_nonce_reuse=FALSE;
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
      out_nonce_reuse=TRUE;
      ASSERT false, 'nonce reuse attempted by client';
      RETURN;
    END IF;
  END IF;
END IF;

END $$;


--
-- Name: FUNCTION exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean) IS 'Stores information about a planchet for a batch withdraw operation. Checks if the planchet already exists, and in that case indicates a conflict';


--
-- Name: exchange_do_close_request(bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_close_request(in_reserve_pub bytea, in_reserve_sig bytea, OUT out_final_balance_val bigint, OUT out_final_balance_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME
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
--         INSERT deposits (by coin_pub, shard), ON CONFLICT DO NOTHING;
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
-- Name: exchange_do_expire_purse(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  my_purse_pub BYTEA;
DECLARE
  my_deposit record;
BEGIN

SELECT purse_pub
  INTO my_purse_pub
  FROM purse_requests
 WHERE (purse_expiration >= in_start_time) AND
       (purse_expiration < in_end_time) AND
       (NOT finished) AND
       (NOT refunded)
 ORDER BY purse_expiration ASC
 LIMIT 1;
out_found = FOUND;
IF NOT FOUND
THEN
  RETURN;
END IF;

UPDATE purse_requests
 SET refunded=TRUE,
     finished=TRUE
 WHERE purse_pub=my_purse_pub;

-- restore balance to each coin deposited into the purse
FOR my_deposit IN
  SELECT coin_pub
        ,amount_with_fee_val
        ,amount_with_fee_frac
    FROM purse_deposits
  WHERE purse_pub = my_purse_pub
LOOP
  UPDATE known_coins SET
    remaining_frac=remaining_frac+my_deposit.amount_with_fee_frac
     - CASE
       WHEN remaining_frac+my_deposit.amount_with_fee_frac >= 100000000
       THEN 100000000
       ELSE 0
       END,
    remaining_val=remaining_val+my_deposit.amount_with_fee_val
     + CASE
       WHEN remaining_frac+my_deposit.amount_with_fee_frac >= 100000000
       THEN 1
       ELSE 0
       END
    WHERE coin_pub = my_deposit.coin_pub;
  END LOOP;
END $$;


--
-- Name: FUNCTION exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean) IS 'Finds an expired purse in the given time range and refunds the coins (if any).';


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
-- Name: exchange_do_history_request(bytea, bytea, bigint, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_history_request(in_reserve_pub bytea, in_reserve_sig bytea, in_request_timestamp bigint, in_history_fee_val bigint, in_history_fee_frac integer, OUT out_balance_ok boolean, OUT out_idempotent boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

  -- Insert and check for idempotency.
  INSERT INTO history_requests
  (reserve_pub
  ,request_timestamp
  ,reserve_sig
  ,history_fee_val
  ,history_fee_frac)
  VALUES
  (in_reserve_pub
  ,in_request_timestamp
  ,in_reserve_sig
  ,in_history_fee_val
  ,in_history_fee_frac)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    out_balance_ok=TRUE;
    out_idempotent=TRUE;
    RETURN;
  END IF;

  out_idempotent=FALSE;

  -- Update reserve balance.
  UPDATE reserves
   SET
    current_balance_frac=current_balance_frac-in_history_fee_frac
       + CASE
         WHEN current_balance_frac < in_history_fee_frac
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val-in_history_fee_val
       - CASE
         WHEN current_balance_frac < in_history_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE
    reserve_pub=in_reserve_pub
    AND ( (current_balance_val > in_history_fee_val) OR
          ( (current_balance_frac >= in_history_fee_frac) AND
            (current_balance_val >= in_history_fee_val) ) );

  IF NOT FOUND
  THEN
    -- Either reserve does not exist, or balance insufficient.
    -- Both we treat the same here as balance insufficient.
    out_balance_ok=FALSE;
    RETURN;
  END IF;

  out_balance_ok=TRUE;
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
-- Name: exchange_do_purse_deposit(bigint, bytea, bigint, integer, bytea, bytea, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_deposit(in_partner_id bigint, in_purse_pub bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_coin_pub bytea, in_coin_sig bytea, in_amount_without_fee_val bigint, in_amount_without_fee_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_merged BOOLEAN;
DECLARE
  psi INT8; -- partner's serial ID (set if merged)
DECLARE
  my_amount_val INT8; -- total in purse
DECLARE
  my_amount_frac INT4; -- total in purse
DECLARE
  was_paid BOOLEAN;
DECLARE
  my_reserve_pub BYTEA;
BEGIN

-- Store the deposit request.
INSERT INTO purse_deposits
  (partner_serial_id
  ,purse_pub
  ,coin_pub
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,coin_sig)
  VALUES
  (in_partner_id
  ,in_purse_pub
  ,in_coin_pub
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_coin_sig)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: check if coin_sig is the same,
  -- if so, success, otherwise conflict!
  PERFORM
  FROM purse_deposits
  WHERE coin_pub = in_coin_pub
    AND purse_pub = in_purse_pub
    AND coin_sig = in_cion_sig;
  IF NOT FOUND
  THEN
    -- Deposit exists, but with differences. Not allowed.
    out_balance_ok=FALSE;
    out_conflict=TRUE;
    RETURN;
  END IF;
END IF;


-- Debit the coin
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


-- Credit the purse.
UPDATE purse_requests
  SET
    balance_frac=balance_frac+in_amount_without_fee_frac
       - CASE
         WHEN balance_frac+in_amount_without_fee_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    balance_val=balance_val+in_amount_without_fee_val
       + CASE
         WHEN balance_frac+in_amount_without_fee_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE purse_pub=in_purse_pub;

out_conflict=FALSE;
out_balance_ok=TRUE;

-- See if we can finish the merge or need to update the trigger time and partner.
SELECT partner_serial_id
      ,reserve_pub
  INTO psi
      ,my_reserve_pub
  FROM purse_merges
 WHERE purse_pub=in_purse_pub;

IF NOT FOUND
THEN
  RETURN;
END IF;

SELECT
    amount_with_fee_val
   ,amount_with_fee_frac
  INTO
    my_amount_val
   ,my_amount_frac
  FROM purse_requests
  WHERE (purse_pub=in_purse_pub)
    AND ( ( ( (amount_with_fee_val <= balance_val)
          AND (amount_with_fee_frac <= balance_frac) )
         OR (amount_with_fee_val < balance_val) ) );
IF NOT FOUND
THEN
  RETURN;
END IF;

IF (0 != psi)
THEN
  -- The taler-exchange-router will take care of this.
  UPDATE purse_actions
     SET action_date=0 --- "immediately"
        ,partner_serial_id=psi
   WHERE purse_pub=in_purse_pub;
ELSE
  -- This is a local reserve, update balance immediately.
  UPDATE reserves
  SET
    current_balance_frac=current_balance_frac+my_amount_frac
       - CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+my_amount_val
       + CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE reserve_pub=my_reserve_pub;

  -- ... and mark purse as finished.
  -- FIXME: combine with UPDATE above?
  UPDATE purse_requests
     SET finished=true
  WHERE purse_pub=in_purse_pub;
END IF;


END $$;


--
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  my_amount_val INT8;
DECLARE
  my_amount_frac INT4;
DECLARE
  my_purse_fee_val INT8;
DECLARE
  my_purse_fee_frac INT4;
DECLARE
  my_partner_serial_id INT8;
DECLARE
  my_finished BOOLEAN;
BEGIN

IF in_partner_url IS NULL
THEN
  my_partner_serial_id=0;
ELSE
  SELECT
    partner_serial_id
  INTO
    my_partner_serial_id
  FROM partners
  WHERE partner_base_url=in_partner_url
    AND start_date <= in_merge_timestamp
    AND end_date > in_merge_timestamp;
  IF NOT FOUND
  THEN
    out_no_partner=TRUE;
    out_conflict=FALSE;
    out_no_kyc=FALSE;
    out_no_reserve=FALSE;
    RETURN;
  END IF;
END IF;

out_no_partner=FALSE;


-- Check purse is 'full'.
SELECT amount_with_fee_val
      ,amount_with_fee_frac
      ,purse_fee_val
      ,purse_fee_frac
      ,finished
  INTO my_amount_val
      ,my_amount_frac
      ,my_purse_fee_val
      ,my_purse_fee_frac
      ,my_finished
  FROM purse_requests
  WHERE purse_pub=in_purse_pub
    AND balance_val >= amount_with_fee_val
    AND ( (balance_frac >= amount_with_fee_frac) OR
          (balance_val > amount_with_fee_val) );
IF NOT FOUND
THEN
  out_no_balance=TRUE;
  out_conflict=FALSE;
  out_no_kyc=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_no_balance=FALSE;

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO purse_merges
    (partner_serial_id
    ,reserve_pub
    ,purse_pub
    ,merge_sig
    ,merge_timestamp)
  VALUES
    (my_partner_serial_id
    ,in_reserve_pub
    ,in_purse_pub
    ,in_merge_sig
    ,in_merge_timestamp)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'merge_sig', we implicitly check
  -- identity over everything that the signature covers.
  PERFORM
  FROM purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     out_no_kyc=FALSE;
     out_no_reserve=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_kyc=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

ASSERT NOT my_finished, 'internal invariant failed';

IF ( (in_partner_url IS NULL) AND
     (in_require_kyc) )
THEN
  -- Need to do KYC check.
  SELECT NOT kyc_passed
    INTO out_no_kyc
    FROM reserves
   WHERE reserve_pub=in_reserve_pub;

  IF NOT FOUND
  THEN
    out_no_kyc=TRUE;
    out_no_reserve=TRUE;
    RETURN;
  END IF;
  out_no_reserve=FALSE;

  IF (out_no_kyc)
  THEN
    RETURN;
  END IF;
ELSE
  -- KYC is not our responsibility
  out_no_reserve=FALSE;
  out_no_kyc=FALSE;
END IF;



-- Store account merge signature.
INSERT INTO account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub);

-- If we need a wad transfer, mark purse ready for it.
IF (0 != my_partner_serial_id)
THEN
  -- The taler-exchange-router will take care of this.
  UPDATE purse_actions
     SET action_date=0 --- "immediately"
        ,partner_serial_id=my_partner_serial_id
   WHERE purse_pub=in_purse_pub;
ELSE
  -- This is a local reserve, update reserve balance immediately.

  -- Refund the purse fee, by adding it to the purse value:
  my_amount_val = my_amount_val + my_purse_fee_val;
  my_amount_frac = my_amount_frac + my_purse_fee_frac;
  -- normalize result
  my_amount_val = my_amount_val + my_amount_frac / 100000000;
  my_amount_frac = my_amount_frac % 100000000;

  UPDATE reserves
  SET
    current_balance_frac=current_balance_frac+my_amount_frac
       - CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+my_amount_val
       + CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE reserve_pub=in_reserve_pub;

  -- ... and mark purse as finished.
  UPDATE purse_requests
     SET finished=true
  WHERE purse_pub=in_purse_pub;
END IF;


RETURN;

END $$;


--
-- Name: FUNCTION exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


--
-- Name: exchange_do_recoup_by_reserve(bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_recoup_by_reserve(res_pub bytea) RETURNS TABLE(denom_sig bytea, denominations_serial bigint, coin_pub bytea, coin_sig bytea, coin_blind bytea, amount_val bigint, amount_frac integer, recoup_timestamp bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  res_uuid BIGINT;
  blind_ev BYTEA;
  c_pub    BYTEA;
BEGIN
  SELECT reserve_uuid
  INTO res_uuid
  FROM reserves
  WHERE reserves.reserve_pub = res_pub;

  FOR blind_ev IN
    SELECT h_blind_ev
      FROM reserves_out_by_reserve
    WHERE reserves_out_by_reserve.reserve_uuid = res_uuid
  LOOP
    SELECT robr.coin_pub
      INTO c_pub
      FROM recoup_by_reserve robr
    WHERE robr.reserve_out_serial_id = (
      SELECT reserves_out.reserve_out_serial_id
        FROM reserves_out
      WHERE reserves_out.h_blind_ev = blind_ev
    );
    RETURN QUERY
      SELECT kc.denom_sig,
             kc.denominations_serial,
             rc.coin_pub,
             rc.coin_sig,
             rc.coin_blind,
             rc.amount_val,
             rc.amount_frac,
             rc.recoup_timestamp
      FROM (
        SELECT *
        FROM known_coins
        WHERE known_coins.coin_pub = c_pub
      ) kc
      JOIN (
        SELECT *
        FROM recoup
        WHERE recoup.coin_pub = c_pub
      ) rc USING (coin_pub);
  END LOOP;
END;
$$;


--
-- Name: FUNCTION exchange_do_recoup_by_reserve(res_pub bytea); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_recoup_by_reserve(res_pub bytea) IS 'Recoup by reserve as a function to make sure we hit only the needed partition and not all when joining as joins on distributed tables fetch ALL rows from the shards';


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
-- Shards: SELECT deposits (coin_pub, shard, h_contract_terms, merchant_pub)
--         INSERT refunds (by coin_pub, rtransaction_id) ON CONFLICT DO NOTHING
--         SELECT refunds (by coin_pub)
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
 WHERE coin_pub=in_coin_pub
  AND shard=in_deposit_shard
  AND merchant_pub=in_merchant_pub
  AND h_contract_terms=in_h_contract_terms;

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
  ,coin_pub
  ,merchant_sig
  ,rtransaction_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  )
  VALUES
  (dsi
  ,in_coin_pub
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
   WHERE coin_pub=in_coin_pub
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
  WHERE coin_pub=in_coin_pub
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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, boolean, bigint, integer, bytea, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO purse_merges
    (partner_serial_id
    ,reserve_pub
    ,purse_pub
    ,merge_sig
    ,merge_timestamp)
  VALUES
    (0
    ,in_reserve_pub
    ,in_purse_pub
    ,in_merge_sig
    ,in_merge_timestamp)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'merge_sig', we implicitly check
  -- identity over everything that the signature covers.
  PERFORM
  FROM purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     out_no_kyc=FALSE;
     out_no_reserve=FALSE;
     out_no_funds=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_funds=FALSE;
  out_no_kyc=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

SELECT NOT kyc_passed
  INTO out_no_kyc
  FROM reserves
 WHERE reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  out_no_kyc=TRUE;
  out_no_reserve=TRUE;
  out_no_funds=TRUE;
  RETURN;
END IF;
out_no_reserve=FALSE;

IF (out_no_kyc AND in_require_kyc)
THEN
  out_no_funds=FALSE;
  RETURN;
END IF;

IF (in_reserve_quota)
THEN
  -- Increment active purses per reserve (and check this is allowed)
  UPDATE reserves
     SET purses_active=purses_active+1
        ,kyc_required=TRUE
   WHERE reserve_pub=in_reserve_pub
     AND purses_active < purses_allowed;
  IF NOT FOUND
  THEN
    out_no_funds=TRUE;
    RETURN;
  END IF;
ELSE
  --  UPDATE reserves balance (and check if balance is enough to pay the fee)
  UPDATE reserves
  SET
    current_balance_frac=current_balance_frac-in_purse_fee_frac
       + CASE
         WHEN current_balance_frac < in_purse_fee_frac
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val-in_purse_fee_val
       - CASE
         WHEN current_balance_frac < in_purse_fee_frac
         THEN 1
         ELSE 0
         END
    ,kyc_required=TRUE
  WHERE reserve_pub=in_reserve_pub
    AND ( (current_balance_val > in_purse_fee_val) OR
          ( (current_balance_frac >= in_purse_fee_frac) AND
            (current_balance_val >= in_purse_fee_val) ) );
  IF NOT FOUND
  THEN
    out_no_funds=TRUE;
    RETURN;
  END IF;
END IF;

out_no_funds=FALSE;


-- Store account merge signature.
INSERT INTO account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub);

END $$;


--
-- Name: FUNCTION exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Create a purse for a reserve.';


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
-- SELECT
--    kyc_ok
--   ,wire_target_serial_id
--   INTO
--    kycok
--   ,account_uuid
--   FROM reserves_in
--   JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
--  WHERE reserve_pub=rpub
--  LIMIT 1; -- limit 1 should not be required (without p2p transfers)

WITH reserves_in AS materialized (
  SELECT wire_source_h_payto
  FROM reserves_in WHERE
  reserve_pub=rpub
)
SELECT
  kyc_ok
  ,wire_target_serial_id
INTO
  kycok
  ,account_uuid
FROM wire_targets
  WHERE wire_target_h_payto = (
    SELECT wire_source_h_payto
      FROM reserves_in
  );

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
-- Name: prepare_sharding(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prepare_sharding() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  CREATE EXTENSION IF NOT EXISTS postgres_fdw;

  PERFORM detach_default_partitions();

  ALTER TABLE IF EXISTS wire_targets
    DROP CONSTRAINT IF EXISTS wire_targets_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS reserves
    DROP CONSTRAINT IF EXISTS reserves_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS reserves_in
    DROP CONSTRAINT IF EXISTS reserves_in_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS reserves_close
    DROP CONSTRAINT IF EXISTS reserves_close_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS reserves_out
    DROP CONSTRAINT IF EXISTS reserves_out_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS reserves_out_denominations_serial_fkey
    ,DROP CONSTRAINT IF EXISTS reserves_out_h_blind_ev_key
  ;

  ALTER TABLE IF EXISTS known_coins
    DROP CONSTRAINT IF EXISTS known_coins_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS known_coins_denominations_serial_fkey
  ;

  ALTER TABLE IF EXISTS refresh_commitments
    DROP CONSTRAINT IF EXISTS refresh_commitments_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS refresh_old_coin_pub_fkey
  ;

  ALTER TABLE IF EXISTS refresh_revealed_coins
    DROP CONSTRAINT IF EXISTS refresh_revealed_coins_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS refresh_revealed_coins_denominations_serial_fkey
  ;

  ALTER TABLE IF EXISTS refresh_transfer_keys
    DROP CONSTRAINT IF EXISTS refresh_transfer_keys_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS deposits
    DROP CONSTRAINT IF EXISTS deposits_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS deposits_extension_details_serial_id_fkey
    ,DROP CONSTRAINT IF EXISTS deposits_coin_pub_merchant_pub_h_contract_terms_key CASCADE
  ;

  ALTER TABLE IF EXISTS refunds
    DROP CONSTRAINT IF EXISTS refunds_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS wire_out
    DROP CONSTRAINT IF EXISTS wire_out_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS wire_out_wtid_raw_key CASCADE
  ;

  ALTER TABLE IF EXISTS aggregation_tracking
    DROP CONSTRAINT IF EXISTS aggregation_tracking_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS aggregation_tracking_wtid_raw_fkey
  ;

  ALTER TABLE IF EXISTS recoup
    DROP CONSTRAINT IF EXISTS recoup_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS recoup_refresh
    DROP CONSTRAINT IF EXISTS recoup_refresh_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS prewire
    DROP CONSTRAINT IF EXISTS prewire_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS cs_nonce_locks
    DROP CONSTRAINT IF EXISTS cs_nonce_locks_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS purse_requests
    DROP CONSTRAINT IF EXISTS purse_requests_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS purse_merges
    DROP CONSTRAINT IF EXISTS purse_merges_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS account_merges
    DROP CONSTRAINT IF EXISTS account_merges_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS contracts
    DROP CONSTRAINT IF EXISTS contracts_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS history_requests
    DROP CONSTRAINT IF EXISTS history_requests_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS close_requests
    DROP CONSTRAINT IF EXISTS close_requests_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS purse_deposits
    DROP CONSTRAINT IF EXISTS purse_deposits_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS wads_out
    DROP CONSTRAINT IF EXISTS wads_out_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS wad_out_entries
    DROP CONSTRAINT IF EXISTS wad_out_entries_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS wads_in
    DROP CONSTRAINT IF EXISTS wads_in_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS wads_in_wad_id_origin_exchange_url_key
  ;

  ALTER TABLE IF EXISTS wad_in_entries
    DROP CONSTRAINT IF EXISTS wad_in_entries_pkey CASCADE
  ;

END
$$;


--
-- Name: purse_requests_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purse_requests_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  ASSERT NOT NEW.finished,'Internal invariant violated';
  INSERT INTO
    purse_actions
    (purse_pub
    ,action_date)
  VALUES
    (NEW.purse_pub
    ,NEW.purse_expiration);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION purse_requests_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.purse_requests_insert_trigger() IS 'When a purse is created, insert it into the purse_action table to take action when the purse expires.';


--
-- Name: purse_requests_on_update_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purse_requests_on_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.finished AND NOT OLD.finished)
  THEN
    -- If this purse counted against the reserve's
    -- quota of purses, decrement the reserve accounting.
    IF (NEW.in_reserve_quota)
    THEN
      UPDATE reserves
         SET purses_active=purses_active-1
       WHERE reserve_pub IN
         (SELECT reserve_pub
            FROM purse_merges
           WHERE purse_pub=NEW.purse_pub
           LIMIT 1);
      NEW.in_reserve_quota=FALSE;
    END IF;
    -- Delete from the purse_actions table, we are done
    -- with this purse for good.
    DELETE FROM purse_actions
          WHERE purse_pub=NEW.purse_pub;
    RETURN NEW;
  END IF;

  RETURN NEW;
END $$;


--
-- Name: FUNCTION purse_requests_on_update_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.purse_requests_on_update_trigger() IS 'Trigger the router if the purse is ready. Also removes the entry from the router watchlist once the purse is finished.';


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


--
-- Name: wire_out_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.wire_out_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM aggregation_tracking
   WHERE wtid_raw = OLD.wtid_raw;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION wire_out_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.wire_out_delete_trigger() IS 'Replicate reserve_out deletions into aggregation_tracking. This replaces an earlier use of an ON DELETE CASCADE that required a DEFERRABLE constraint and conflicted with nice partitioning.';


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
-- Name: account_merges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_merges (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT account_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_merges_reserve_sig_check CHECK ((length(reserve_sig) = 64))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE account_merges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.account_merges IS 'Merge requests where a purse- and account-owner requested merging the purse into the account';


--
-- Name: COLUMN account_merges.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_merges.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN account_merges.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_merges.reserve_sig IS 'signature by the reserve private key affirming the merge, of type TALER_SIGNATURE_WALLET_ACCOUNT_MERGE';


--
-- Name: COLUMN account_merges.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_merges.purse_pub IS 'public key of the purse';


--
-- Name: account_merges_account_merge_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.account_merges ALTER COLUMN account_merge_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.account_merges_account_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: account_merges_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_merges_default (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT account_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_merges_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.account_merges ATTACH PARTITION public.account_merges_default FOR VALUES WITH (modulus 1, remainder 0);


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

COMMENT ON COLUMN public.aggregation_tracking.wtid_raw IS 'identifier of the wire transfer';


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
-- Name: aggregation_transient; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_transient (
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT aggregation_transient_wtid_raw_check CHECK ((length(wtid_raw) = 32))
)
PARTITION BY HASH (wire_target_h_payto);


--
-- Name: TABLE aggregation_transient; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aggregation_transient IS 'aggregations currently happening (lacking wire_out, usually because the amount is too low); this table is not replicated';


--
-- Name: COLUMN aggregation_transient.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_transient.amount_val IS 'Sum of all of the aggregated deposits (without deposit fees)';


--
-- Name: COLUMN aggregation_transient.wtid_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_transient.wtid_raw IS 'identifier of the wire transfer';


--
-- Name: aggregation_transient_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_transient_default (
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT aggregation_transient_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);
ALTER TABLE ONLY public.aggregation_transient ATTACH PARTITION public.aggregation_transient_default FOR VALUES WITH (modulus 1, remainder 0);


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
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_deposits_serial_id bigint DEFAULT 0 NOT NULL
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
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_merges_serial_id bigint DEFAULT 0 NOT NULL,
    last_account_merges_serial_id bigint DEFAULT 0 NOT NULL,
    last_history_requests_serial_id bigint DEFAULT 0 NOT NULL,
    last_close_requests_serial_id bigint DEFAULT 0 NOT NULL
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
-- Name: close_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.close_requests (
    close_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    close_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    close_val bigint NOT NULL,
    close_frac integer NOT NULL,
    CONSTRAINT close_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT close_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE close_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.close_requests IS 'Explicit requests by a reserve owner to close a reserve immediately';


--
-- Name: COLUMN close_requests.close_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.close_requests.close_timestamp IS 'When the request was created by the client';


--
-- Name: COLUMN close_requests.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.close_requests.reserve_sig IS 'Signature affirming that the reserve is to be closed';


--
-- Name: COLUMN close_requests.close_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.close_requests.close_val IS 'Balance of the reserve at the time of closing, to be wired to the associated bank account (minus the closing fee)';


--
-- Name: close_requests_close_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.close_requests ALTER COLUMN close_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.close_requests_close_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: close_requests_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.close_requests_default (
    close_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    close_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    close_val bigint NOT NULL,
    close_frac integer NOT NULL,
    CONSTRAINT close_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT close_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.close_requests ATTACH PARTITION public.close_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    contract_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    pub_ckey bytea NOT NULL,
    contract_sig bytea NOT NULL,
    e_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    CONSTRAINT contracts_contract_sig_check CHECK ((length(contract_sig) = 64)),
    CONSTRAINT contracts_pub_ckey_check CHECK ((length(pub_ckey) = 32)),
    CONSTRAINT contracts_purse_pub_check CHECK ((length(purse_pub) = 32))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE contracts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.contracts IS 'encrypted contracts associated with purses';


--
-- Name: COLUMN contracts.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contracts.purse_pub IS 'public key of the purse that the contract is associated with';


--
-- Name: COLUMN contracts.pub_ckey; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contracts.pub_ckey IS 'Public ECDH key used to encrypt the contract, to be used with the purse private key for decryption';


--
-- Name: COLUMN contracts.contract_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contracts.contract_sig IS 'signature over the encrypted contract by the purse contract key';


--
-- Name: COLUMN contracts.e_contract; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contracts.e_contract IS 'AES-GCM encrypted contract terms (contains gzip compressed JSON after decryption)';


--
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.contracts ALTER COLUMN contract_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.contracts_contract_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: contracts_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts_default (
    contract_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    pub_ckey bytea NOT NULL,
    contract_sig bytea NOT NULL,
    e_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    CONSTRAINT contracts_contract_sig_check CHECK ((length(contract_sig) = 64)),
    CONSTRAINT contracts_pub_ckey_check CHECK ((length(pub_ckey) = 32)),
    CONSTRAINT contracts_purse_pub_check CHECK ((length(purse_pub) = 32))
);
ALTER TABLE ONLY public.contracts ATTACH PARTITION public.contracts_default FOR VALUES WITH (modulus 1, remainder 0);


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
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';


--
-- Name: COLUMN deposits.shard; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.shard IS 'Used for load sharding in the materialized indices. Should be set based on merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';


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
-- Name: deposits_by_ready; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_by_ready (
    wire_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_by_ready_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY RANGE (wire_deadline);


--
-- Name: TABLE deposits_by_ready; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits_by_ready IS 'Enables fast lookups for deposits_get_ready, auto-populated via TRIGGER below';


--
-- Name: deposits_by_ready_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_by_ready_default (
    wire_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_by_ready_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.deposits_by_ready ATTACH PARTITION public.deposits_by_ready_default DEFAULT;


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
-- Name: deposits_for_matching; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_for_matching (
    refund_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_for_matching_merchant_pub_check CHECK ((length(merchant_pub) = 32))
)
PARTITION BY RANGE (refund_deadline);


--
-- Name: TABLE deposits_for_matching; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits_for_matching IS 'Enables fast lookups for deposits_iterate_matching, auto-populated via TRIGGER below';


--
-- Name: deposits_for_matching_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_for_matching_default (
    refund_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_for_matching_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);
ALTER TABLE ONLY public.deposits_for_matching ATTACH PARTITION public.deposits_for_matching_default DEFAULT;


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
)
PARTITION BY HASH (extension_details_serial_id);


--
-- Name: TABLE extension_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.extension_details IS 'Extensions that were provided with deposits (not yet used).';


--
-- Name: COLUMN extension_details.extension_options; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extension_details.extension_options IS 'JSON object with options set that the exchange needs to consider when executing a deposit. Supported details depend on the extensions supported by the exchange.';


--
-- Name: extension_details_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extension_details_default (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
);
ALTER TABLE ONLY public.extension_details ATTACH PARTITION public.extension_details_default FOR VALUES WITH (modulus 1, remainder 0);


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
-- Name: history_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.history_requests (
    history_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    request_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    history_fee_val bigint NOT NULL,
    history_fee_frac integer NOT NULL,
    CONSTRAINT history_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT history_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE history_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.history_requests IS 'Paid history requests issued by a client against a reserve';


--
-- Name: COLUMN history_requests.request_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.history_requests.request_timestamp IS 'When was the history request made';


--
-- Name: COLUMN history_requests.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.history_requests.reserve_sig IS 'Signature approving payment for the history request';


--
-- Name: COLUMN history_requests.history_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.history_requests.history_fee_val IS 'History fee approved by the signature';


--
-- Name: history_requests_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.history_requests_default (
    history_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    request_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    history_fee_val bigint NOT NULL,
    history_fee_frac integer NOT NULL,
    CONSTRAINT history_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT history_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.history_requests ATTACH PARTITION public.history_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.history_requests ALTER COLUMN history_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.history_requests_history_request_serial_id_seq
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
    remaining_val bigint DEFAULT 0 NOT NULL,
    remaining_frac integer DEFAULT 0 NOT NULL,
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
    remaining_val bigint DEFAULT 0 NOT NULL,
    remaining_frac integer DEFAULT 0 NOT NULL,
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
    website character varying,
    email character varying,
    logo bytea,
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
-- Name: COLUMN merchant_instances.website; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.website IS 'merchant site URL';


--
-- Name: COLUMN merchant_instances.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.email IS 'email';


--
-- Name: COLUMN merchant_instances.logo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.logo IS 'data image url';


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
-- Name: partner_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partner_accounts (
    payto_uri character varying NOT NULL,
    partner_serial_id bigint,
    partner_master_sig bytea,
    last_seen bigint NOT NULL,
    CONSTRAINT partner_accounts_partner_master_sig_check CHECK ((length(partner_master_sig) = 64))
);


--
-- Name: TABLE partner_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.partner_accounts IS 'Table with bank accounts of the partner exchange. Entries never expire as we need to remember the signature for the auditor.';


--
-- Name: COLUMN partner_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partner_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the partner exchange.';


--
-- Name: COLUMN partner_accounts.partner_master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partner_accounts.partner_master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS by the partner master public key';


--
-- Name: COLUMN partner_accounts.last_seen; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partner_accounts.last_seen IS 'Last time we saw this account as being active at the partner exchange. Used to select the most recent entry, and to detect when we should check again.';


--
-- Name: partners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partners (
    partner_serial_id bigint NOT NULL,
    partner_master_pub bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    next_wad bigint DEFAULT 0 NOT NULL,
    wad_frequency bigint NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    partner_base_url text NOT NULL,
    CONSTRAINT partners_master_sig_check CHECK ((length(master_sig) = 64)),
    CONSTRAINT partners_partner_master_pub_check CHECK ((length(partner_master_pub) = 32))
);


--
-- Name: TABLE partners; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.partners IS 'exchanges we do wad transfers to';


--
-- Name: COLUMN partners.partner_master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.partner_master_pub IS 'offline master public key of the partner';


--
-- Name: COLUMN partners.start_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.start_date IS 'starting date of the partnership';


--
-- Name: COLUMN partners.end_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.end_date IS 'end date of the partnership';


--
-- Name: COLUMN partners.next_wad; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.next_wad IS 'at what time should we do the next wad transfer to this partner (frequently updated); set to forever after the end_date';


--
-- Name: COLUMN partners.wad_frequency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.wad_frequency IS 'how often do we promise to do wad transfers';


--
-- Name: COLUMN partners.wad_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.wad_fee_val IS 'how high is the fee for a wallet to be added to a wad to this partner';


--
-- Name: COLUMN partners.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.master_sig IS 'signature of our master public key affirming the partnership, of purpose TALER_SIGNATURE_MASTER_PARTNER_DETAILS';


--
-- Name: COLUMN partners.partner_base_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.partner_base_url IS 'base URL of the REST API for this partner';


--
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.partners ALTER COLUMN partner_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.partners_partner_serial_id_seq
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
-- Name: purse_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_actions (
    purse_pub bytea NOT NULL,
    action_date bigint NOT NULL,
    partner_serial_id bigint,
    CONSTRAINT purse_actions_purse_pub_check CHECK ((length(purse_pub) = 32))
);


--
-- Name: TABLE purse_actions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_actions IS 'purses awaiting some action by the router';


--
-- Name: COLUMN purse_actions.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_actions.purse_pub IS 'public (contract) key of the purse';


--
-- Name: COLUMN purse_actions.action_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_actions.action_date IS 'when is the purse ready for action';


--
-- Name: COLUMN purse_actions.partner_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_actions.partner_serial_id IS 'wad target of an outgoing wire transfer, 0 for local, NULL if the purse is unmerged and thus the target is still unknown';


--
-- Name: purse_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_deposits (
    purse_deposit_serial_id bigint NOT NULL,
    partner_serial_id bigint,
    purse_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    coin_sig bytea NOT NULL,
    CONSTRAINT purse_deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT purse_deposits_purse_pub_check CHECK ((length(purse_pub) = 32))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE purse_deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_deposits IS 'Requests depositing coins into a purse';


--
-- Name: COLUMN purse_deposits.partner_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.partner_serial_id IS 'identifies the partner exchange, NULL in case the target purse lives at this exchange';


--
-- Name: COLUMN purse_deposits.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN purse_deposits.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.coin_pub IS 'Public key of the coin being deposited';


--
-- Name: COLUMN purse_deposits.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.amount_with_fee_val IS 'Total amount being deposited';


--
-- Name: COLUMN purse_deposits.coin_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.coin_sig IS 'Signature of the coin affirming the deposit into the purse, of type TALER_SIGNATURE_PURSE_DEPOSIT';


--
-- Name: purse_deposits_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_deposits_default (
    purse_deposit_serial_id bigint NOT NULL,
    partner_serial_id bigint,
    purse_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    coin_sig bytea NOT NULL,
    CONSTRAINT purse_deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT purse_deposits_purse_pub_check CHECK ((length(purse_pub) = 32))
);
ALTER TABLE ONLY public.purse_deposits ATTACH PARTITION public.purse_deposits_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.purse_deposits ALTER COLUMN purse_deposit_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purse_deposits_purse_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_merges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_merges (
    purse_merge_request_serial_id bigint NOT NULL,
    partner_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    merge_sig bytea NOT NULL,
    merge_timestamp bigint NOT NULL,
    CONSTRAINT purse_merges_merge_sig_check CHECK ((length(merge_sig) = 64)),
    CONSTRAINT purse_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT purse_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE purse_merges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_merges IS 'Merge requests where a purse-owner requested merging the purse into the account';


--
-- Name: COLUMN purse_merges.partner_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.partner_serial_id IS 'identifies the partner exchange, NULL in case the target reserve lives at this exchange';


--
-- Name: COLUMN purse_merges.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN purse_merges.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.purse_pub IS 'public key of the purse';


--
-- Name: COLUMN purse_merges.merge_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.merge_sig IS 'signature by the purse private key affirming the merge, of type TALER_SIGNATURE_WALLET_PURSE_MERGE';


--
-- Name: COLUMN purse_merges.merge_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.merge_timestamp IS 'when was the merge message signed';


--
-- Name: purse_merges_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_merges_default (
    purse_merge_request_serial_id bigint NOT NULL,
    partner_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    merge_sig bytea NOT NULL,
    merge_timestamp bigint NOT NULL,
    CONSTRAINT purse_merges_merge_sig_check CHECK ((length(merge_sig) = 64)),
    CONSTRAINT purse_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT purse_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);
ALTER TABLE ONLY public.purse_merges ATTACH PARTITION public.purse_merges_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.purse_merges ALTER COLUMN purse_merge_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purse_merges_purse_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_requests (
    purse_requests_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    merge_pub bytea NOT NULL,
    purse_creation bigint NOT NULL,
    purse_expiration bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    age_limit integer NOT NULL,
    flags integer NOT NULL,
    refunded boolean DEFAULT false NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    in_reserve_quota boolean DEFAULT false NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    purse_fee_val bigint NOT NULL,
    purse_fee_frac integer NOT NULL,
    balance_val bigint DEFAULT 0 NOT NULL,
    balance_frac integer DEFAULT 0 NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT purse_requests_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT purse_requests_merge_pub_check CHECK ((length(merge_pub) = 32)),
    CONSTRAINT purse_requests_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT purse_requests_purse_sig_check CHECK ((length(purse_sig) = 64))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE purse_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_requests IS 'Requests establishing purses, associating them with a contract but without a target reserve';


--
-- Name: COLUMN purse_requests.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN purse_requests.purse_creation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_creation IS 'Local time when the purse was created. Determines applicable purse fees.';


--
-- Name: COLUMN purse_requests.purse_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_expiration IS 'When the purse is set to expire';


--
-- Name: COLUMN purse_requests.h_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.h_contract_terms IS 'Hash of the contract the parties are to agree to';


--
-- Name: COLUMN purse_requests.flags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.flags IS 'see the enum TALER_WalletAccountMergeFlags';


--
-- Name: COLUMN purse_requests.refunded; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.refunded IS 'set to TRUE if the purse could not be merged and thus all deposited coins were refunded';


--
-- Name: COLUMN purse_requests.finished; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.finished IS 'set to TRUE once the purse has been merged (into reserve or wad) or the coins were refunded (transfer aborted)';


--
-- Name: COLUMN purse_requests.in_reserve_quota; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.in_reserve_quota IS 'set to TRUE if this purse currently counts against the number of free purses in the respective reserve';


--
-- Name: COLUMN purse_requests.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.amount_with_fee_val IS 'Total amount expected to be in the purse';


--
-- Name: COLUMN purse_requests.purse_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_fee_val IS 'Purse fee the client agreed to pay from the reserve (accepted by the exchange at the time the purse was created). Zero if in_reserve_quota is TRUE.';


--
-- Name: COLUMN purse_requests.balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.balance_val IS 'Total amount actually in the purse';


--
-- Name: COLUMN purse_requests.purse_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_sig IS 'Signature of the purse affirming the purse parameters, of type TALER_SIGNATURE_PURSE_REQUEST';


--
-- Name: purse_requests_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_requests_default (
    purse_requests_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    merge_pub bytea NOT NULL,
    purse_creation bigint NOT NULL,
    purse_expiration bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    age_limit integer NOT NULL,
    flags integer NOT NULL,
    refunded boolean DEFAULT false NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    in_reserve_quota boolean DEFAULT false NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    purse_fee_val bigint NOT NULL,
    purse_fee_frac integer NOT NULL,
    balance_val bigint DEFAULT 0 NOT NULL,
    balance_frac integer DEFAULT 0 NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT purse_requests_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT purse_requests_merge_pub_check CHECK ((length(merge_pub) = 32)),
    CONSTRAINT purse_requests_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT purse_requests_purse_sig_check CHECK ((length(purse_sig) = 64))
);
ALTER TABLE ONLY public.purse_requests ATTACH PARTITION public.purse_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.purse_requests ALTER COLUMN purse_requests_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purse_requests_purse_requests_serial_id_seq
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
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
)
PARTITION BY HASH (coin_pub);


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
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_coin_pub_check CHECK ((length(coin_pub) = 32)),
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
    current_balance_val bigint DEFAULT 0 NOT NULL,
    current_balance_frac integer DEFAULT 0 NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
    max_age integer DEFAULT 120 NOT NULL,
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

COMMENT ON COLUMN public.reserves.current_balance_val IS 'Current balance remaining with the reserve.';


--
-- Name: COLUMN reserves.purses_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.purses_active IS 'Number of purses that were created by this reserve that are not expired and not fully paid.';


--
-- Name: COLUMN reserves.purses_allowed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.purses_allowed IS 'Number of purses that this reserve is allowed to have active at most.';


--
-- Name: COLUMN reserves.kyc_required; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.kyc_required IS 'True if a KYC check must have been passed before withdrawing from this reserve. Set to true once a reserve received a P2P payment.';


--
-- Name: COLUMN reserves.kyc_passed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.kyc_passed IS 'True once KYC was passed for this reserve. The KYC details are then available via the wire_targets table under the key of wire_target_h_payto which is to be derived from the reserve_pub and the base URL of this exchange.';


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
    current_balance_val bigint DEFAULT 0 NOT NULL,
    current_balance_frac integer DEFAULT 0 NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
    max_age integer DEFAULT 120 NOT NULL,
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
-- Name: wad_in_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wad_in_entries (
    wad_in_entry_serial_id bigint NOT NULL,
    wad_in_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    h_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    merge_timestamp bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    deposit_fees_val bigint NOT NULL,
    deposit_fees_frac integer NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT wad_in_entries_h_contract_check CHECK ((length(h_contract) = 64)),
    CONSTRAINT wad_in_entries_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT wad_in_entries_purse_sig_check CHECK ((length(purse_sig) = 64)),
    CONSTRAINT wad_in_entries_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT wad_in_entries_reserve_sig_check CHECK ((length(reserve_sig) = 64))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE wad_in_entries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wad_in_entries IS 'list of purses aggregated in a wad according to the sending exchange';


--
-- Name: COLUMN wad_in_entries.wad_in_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.wad_in_serial_id IS 'wad for which the given purse was included in the aggregation';


--
-- Name: COLUMN wad_in_entries.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.reserve_pub IS 'target account of the purse (must be at the local exchange)';


--
-- Name: COLUMN wad_in_entries.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.purse_pub IS 'public key of the purse that was merged';


--
-- Name: COLUMN wad_in_entries.h_contract; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.h_contract IS 'hash of the contract terms of the purse';


--
-- Name: COLUMN wad_in_entries.purse_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.purse_expiration IS 'Time when the purse was set to expire';


--
-- Name: COLUMN wad_in_entries.merge_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.merge_timestamp IS 'Time when the merge was approved';


--
-- Name: COLUMN wad_in_entries.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.amount_with_fee_val IS 'Total amount in the purse';


--
-- Name: COLUMN wad_in_entries.wad_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.wad_fee_val IS 'Total wad fees paid by the purse';


--
-- Name: COLUMN wad_in_entries.deposit_fees_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.deposit_fees_val IS 'Total deposit fees paid when depositing coins into the purse';


--
-- Name: COLUMN wad_in_entries.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.reserve_sig IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';


--
-- Name: COLUMN wad_in_entries.purse_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.purse_sig IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';


--
-- Name: wad_in_entries_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wad_in_entries_default (
    wad_in_entry_serial_id bigint NOT NULL,
    wad_in_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    h_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    merge_timestamp bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    deposit_fees_val bigint NOT NULL,
    deposit_fees_frac integer NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT wad_in_entries_h_contract_check CHECK ((length(h_contract) = 64)),
    CONSTRAINT wad_in_entries_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT wad_in_entries_purse_sig_check CHECK ((length(purse_sig) = 64)),
    CONSTRAINT wad_in_entries_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT wad_in_entries_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.wad_in_entries ATTACH PARTITION public.wad_in_entries_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wad_in_entries ALTER COLUMN wad_in_entry_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wad_in_entries_wad_in_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wad_out_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wad_out_entries (
    wad_out_entry_serial_id bigint NOT NULL,
    wad_out_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    h_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    merge_timestamp bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    deposit_fees_val bigint NOT NULL,
    deposit_fees_frac integer NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT wad_out_entries_h_contract_check CHECK ((length(h_contract) = 64)),
    CONSTRAINT wad_out_entries_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT wad_out_entries_purse_sig_check CHECK ((length(purse_sig) = 64)),
    CONSTRAINT wad_out_entries_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT wad_out_entries_reserve_sig_check CHECK ((length(reserve_sig) = 64))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE wad_out_entries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wad_out_entries IS 'Purses combined into a wad';


--
-- Name: COLUMN wad_out_entries.wad_out_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.wad_out_serial_id IS 'Wad the purse was part of';


--
-- Name: COLUMN wad_out_entries.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.reserve_pub IS 'Target reserve for the purse';


--
-- Name: COLUMN wad_out_entries.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN wad_out_entries.h_contract; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.h_contract IS 'Hash of the contract associated with the purse';


--
-- Name: COLUMN wad_out_entries.purse_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.purse_expiration IS 'Time when the purse expires';


--
-- Name: COLUMN wad_out_entries.merge_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.merge_timestamp IS 'Time when the merge was approved';


--
-- Name: COLUMN wad_out_entries.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.amount_with_fee_val IS 'Total amount in the purse';


--
-- Name: COLUMN wad_out_entries.wad_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.wad_fee_val IS 'Wat fee charged to the purse';


--
-- Name: COLUMN wad_out_entries.deposit_fees_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.deposit_fees_val IS 'Total deposit fees charged to the purse';


--
-- Name: COLUMN wad_out_entries.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.reserve_sig IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';


--
-- Name: COLUMN wad_out_entries.purse_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.purse_sig IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';


--
-- Name: wad_out_entries_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wad_out_entries_default (
    wad_out_entry_serial_id bigint NOT NULL,
    wad_out_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    h_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    merge_timestamp bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    deposit_fees_val bigint NOT NULL,
    deposit_fees_frac integer NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT wad_out_entries_h_contract_check CHECK ((length(h_contract) = 64)),
    CONSTRAINT wad_out_entries_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT wad_out_entries_purse_sig_check CHECK ((length(purse_sig) = 64)),
    CONSTRAINT wad_out_entries_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT wad_out_entries_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.wad_out_entries ATTACH PARTITION public.wad_out_entries_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wad_out_entries ALTER COLUMN wad_out_entry_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wad_out_entries_wad_out_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wads_in; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wads_in (
    wad_in_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    origin_exchange_url text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    arrival_time bigint NOT NULL,
    CONSTRAINT wads_in_wad_id_check CHECK ((length(wad_id) = 24))
)
PARTITION BY HASH (wad_id);


--
-- Name: TABLE wads_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wads_in IS 'Incoming exchange-to-exchange wad wire transfers';


--
-- Name: COLUMN wads_in.wad_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_in.wad_id IS 'Unique identifier of the wad, part of the wire transfer subject';


--
-- Name: COLUMN wads_in.origin_exchange_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_in.origin_exchange_url IS 'Base URL of the originating URL, also part of the wire transfer subject';


--
-- Name: COLUMN wads_in.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_in.amount_val IS 'Actual amount that was received by our exchange';


--
-- Name: COLUMN wads_in.arrival_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_in.arrival_time IS 'Time when the wad was received';


--
-- Name: wads_in_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wads_in_default (
    wad_in_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    origin_exchange_url text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    arrival_time bigint NOT NULL,
    CONSTRAINT wads_in_wad_id_check CHECK ((length(wad_id) = 24))
);
ALTER TABLE ONLY public.wads_in ATTACH PARTITION public.wads_in_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wads_in ALTER COLUMN wad_in_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wads_in_wad_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wads_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wads_out (
    wad_out_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    partner_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    CONSTRAINT wads_out_wad_id_check CHECK ((length(wad_id) = 24))
)
PARTITION BY HASH (wad_id);


--
-- Name: TABLE wads_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wads_out IS 'Wire transfers made to another exchange to transfer purse funds';


--
-- Name: COLUMN wads_out.wad_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_out.wad_id IS 'Unique identifier of the wad, part of the wire transfer subject';


--
-- Name: COLUMN wads_out.partner_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_out.partner_serial_id IS 'target exchange of the wad';


--
-- Name: COLUMN wads_out.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_out.amount_val IS 'Amount that was wired';


--
-- Name: COLUMN wads_out.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_out.execution_time IS 'Time when the wire transfer was scheduled';


--
-- Name: wads_out_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wads_out_default (
    wad_out_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    partner_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    CONSTRAINT wads_out_wad_id_check CHECK ((length(wad_id) = 24))
);
ALTER TABLE ONLY public.wads_out ATTACH PARTITION public.wads_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wads_out ALTER COLUMN wad_out_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wads_out_wad_out_serial_id_seq
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
exchange-0001	2022-06-12 22:15:38.993122+02	grothoff	{}	{}
merchant-0001	2022-06-12 22:15:39.885287+02	grothoff	{}	{}
merchant-0002	2022-06-12 22:15:40.284047+02	grothoff	{}	{}
auditor-0001	2022-06-12 22:15:40.433184+02	grothoff	{}	{}
\.


--
-- Data for Name: account_merges_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.account_merges_default (account_merge_request_serial_id, reserve_pub, reserve_sig, purse_pub) FROM stdin;
\.


--
-- Data for Name: aggregation_tracking_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_tracking_default (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: aggregation_transient_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_transient_default (amount_val, amount_frac, wire_target_h_payto, exchange_account_section, wtid_raw) FROM stdin;
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
1	TESTKUDOS:100	Joining bonus	2022-06-12 22:15:49.550423+02	f	79e5eaa9-0cb6-44a5-bd40-3700df5b2c45	12	1
2	TESTKUDOS:10	58Y7034B7ND3SD5GKKYWAGP6KQJWTPY4NA9TYGKZRBGWJ6FHAR9G	2022-06-12 22:15:53.100865+02	f	28f968b1-66d3-4e41-9a63-df38bb99ae00	2	12
3	TESTKUDOS:100	Joining bonus	2022-06-12 22:16:00.119654+02	f	872b1cf7-926a-4670-979a-560acc6c0c41	13	1
4	TESTKUDOS:18	9NJTTMEFZH67QKS2XEKFZQD3KCA2ADABDEYW2CPN5E9X9VP476QG	2022-06-12 22:16:00.775082+02	f	16460362-e5e7-4ab8-a15b-289aa09f95aa	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
1f2d6869-c10b-4c80-acbb-0493ffa5a200	TESTKUDOS:10	t	t	f	58Y7034B7ND3SD5GKKYWAGP6KQJWTPY4NA9TYGKZRBGWJ6FHAR9G	2	12
993ae274-edb2-4c64-8d69-cc830712649c	TESTKUDOS:18	t	t	f	9NJTTMEFZH67QKS2XEKFZQD3KCA2ADABDEYW2CPN5E9X9VP476QG	2	13
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
1	1	10	\\xc3e9081666a2fbc4d3ca05db95be35c7d7bc2f60c4ae51c6867143cfba3b77863dbc471febd0431de99dcdfbfdc7a2b8391dba8cd86d4c59a9a6fb201fdfc502
2	1	90	\\x0cde49620bc813aa6461a55af36de10e9abd685da2bbbffbaf4245214540ef77f12831db404e66fac6c8f6626b2898cf65c0d2a280218206e58f82c536a6130f
3	1	112	\\xb5bfff5304bf43c8013aee45cdcbf0be18ab9cad911ec83a76877b1d7224e7882a0b61a6a4796f3e8d3027af66d7857739a13333c9162cd9946607594334150b
4	1	16	\\xbefb9531ead981f5e4811abaff98d619bff6ff9d68c258a835229660ce7432bdbe04f7c16d13a9bdaa6460b78beb9972e1d5b65fc206017bb5d8e642793e080e
5	1	165	\\x2f62afbc8374ac2605f24104bbaf5ea2f99c546477d98a3442af9eb6efed25c50b1081995dcf501f62b9d246e50ef2e488a77b26654cc86ac58b65ff8878980e
6	1	358	\\x47878f0e89224512098732cb0d87e132e24ae0d85bdcabc4d8c85414e6a2fb2d2adebc88a62a58a4cd749c237b8f4237d2c6af86f3057114ff4482c5975f0409
7	1	224	\\x1a13a6f1a776aea96c240ac554f3652c067c25458b7d44570d088412c9d437254db2a0a51b09dea1164db3842af4ed7c57f276e4223160fe93451b5855af0004
8	1	412	\\xfa8ff81a4e3ec328a9d08cfa8e4cb670929719c98323cb103c4d147f4fb6e7d4de17758049b6144b2cc85efd00066fcf156a9d056edfcdafe8e94be130d4840d
9	1	56	\\xa769f57c5ae50fe3e139dd32694b2c43fe1a8ea1695446b74b265bef01ced3fe2896becca91b4dcfdce96a76f5398ce8cb124d61aa141a8ae6347c143d664a0c
10	1	282	\\xa598fd428a18f2e215b0600c69bb4d0e5a6dbb896fc797be741e5de48386342bbb590ecdab74c798a6149a2b4a2de72edd09be36b928a6ba16bd0c8997f13e00
11	1	137	\\xf9daa4cfd9fe2a9227f9119c5f01070ee423dbf2d6014a715c1aecdc69cd332f362b5b181460b22ba547d1ed0ef686dd81f800805d1d56b6b366abb80ebc5f0e
12	1	414	\\x8ec5ae5c178225c7ccafefce5738e920dffee450c7275a87a9dbb253f8ac58ef25e48e7e0ea05301fcf0df9568f0320c6b3298a76760b1af3d43eff7e597b706
13	1	3	\\x7fa86742408e117e6c69a3bf2dc1add1645c81d03f4af4bb30b7e2d694445039144d30520d2b8a7fbc5d9f37e9870eaf8cb596f383615672138dfdb15111160d
14	1	311	\\x36edb0d5eb4d6ed8d3031cc1f10f49f4b73ef9aaa7969505f3cdf4308e60565e377a911d42321a825b470ebb45f2799bd7fac42f522c5d86ece0d1b27d14070d
15	1	53	\\xa4a54a4ad6c66a3eaa1b07b74971213b3d6db23a0b5dbf18bef2a808575a5064f64cd896dff028cf2e9cdf870db98079e16c7b7874380a76a0593288a00b2906
16	1	416	\\x59be110f96fc9fedea55275a8f1e6f2a96b1355b74cde757abc3a198a4e5283a1288f8cc4ace7a5bb26c79ce3c54fc43c39b5bd4db5b6cc9dba8539566cf7e08
17	1	212	\\xdfa6fed9d754ca511765a9abe848d18f0bbbda139d00ee5e5bd730ba54a0ee8e14bb59aab6f96914d91bdb2773bdfc83b945e75986178ba0e76d280ad0938a05
18	1	51	\\x15fe3a263c85ea23f12077df52d2267b1a069260d96c957871a9b4eeb617210e189a24e13bf767f77cc5dec48d43b0b2722ef41443a2dace2ef348636ef78303
19	1	410	\\xdf927d4dd74bf237ba8f691b84fcfec7e56726dac8fe77af4f9c76772b97cba75ae2ef37665cae50a28fe159cf3f2dff994f4710ca4eb7d020e4d4b717c9360f
20	1	55	\\x4f5eefc3a45ea3975ed59f473340432baee63904ad3765ac0792b5c02347042ec3c684248a5e575b44c80dd4566f61003695d7742a4c82b9ddaeb6051a0fd30b
21	1	199	\\x3b3fb14731c6152134c9c28eadee832c74b427c2ecee409b2af1894722fff001867a539434e4c2d658541947ee3e1b74bd83dcf0185678e452a3ba33c737ee00
22	1	188	\\x1d69eb4255cb68a04f5bc958d29158a96624c86b08082c795e30c0bfec4ea4362641352119da1d3a141b8ab8bf8be6129a7ae74f566e236a15a75fb9448eb409
23	1	263	\\x9a5e1562d21f26f0b67a352517ee85a0db1c58c9e65677d64b3f6617f241dc3ee3262f43ac53a6e7e639af35c83ef9413d580584e4d47fa298f6d33f662eb403
24	1	285	\\xcc4e7d99cd0e0708d60cd39a6622637a332351a2d2c3b198b1bfcd507a56cba0552af8f99de80164a095b16b96a861b45b8ca38d86353cb87834acb3db2cd600
25	1	244	\\x7b84f676c7b8cec4bb88bee650ed1020ce4730b3bb8031b32f8fbbcec452feb4673d3fb5af9f0eef332a55933af4e1db86298a3a88a0b8303d39d6f1937e1b09
26	1	93	\\x900e86e889785cccd55627381e820b4d2f05450051b8200a82bfcb9229fb2bb4e70ae4aed1f6189a6c397ea51202aac05ca4cc5d6449c01bf809a22d78322709
27	1	182	\\xe07e2c5520abbddbf34f19aefafdf0e71590b4fcdd0376ee9f36b5c9d5b9470297bb0254fac71fdcf90b05d39a8f85913f6db25d7ef1d858073078aa60e41805
28	1	42	\\x38c2788c857d37efaf7b48adeec60c5555830deb69beafcab2f13debe83a5f03e364916559bb97bcd86c2deab09b69c15f7a300ff45cbc1dd735eaaa1b62a00d
29	1	254	\\x71ec962f35d61fd9e4da87373d9f59ccd370d5285be79ac6ebe6a2b9ad0b4432a8406564073f03ad588d57637d1c0c003c6a0f5dd802b54d5bcecc0740ab8d05
30	1	380	\\x6b7574eec28ae5736b06ef805e5e0f1a311180edb85b8efa344a43781f345c4d89cdf2dcf3570db23d7caff58937e4b1a096f8def1860dbf3d1019af519d2b09
31	1	6	\\x608583475d7c18b7eac9ef933cd717f59cee615d9963b9f0a9fc501c380bec50fe8b1c02db197998aba04552d4aeb89954757e591c7dfe2ba01f865a5cfe580f
32	1	29	\\x0ee743b113854f55e3e4aac2ed8b6815ceb97894c56a8e261c8dc1239d3206bfc3cdb16c3066966df8747ba55a7c0ec43959ba306a3435709155360d710c7409
33	1	49	\\xb7d65dce4a559306395ac6c370e7111134f5028f962a18ab9c9008c74b4ef55121e4bc65ba1728393fcc78b85e56a61a4add002d63cbf25f611082ea10d8d403
34	1	158	\\x33b01e0623c1b06c98d833da729733e8149ac900511182b48f64cd6173b7838d05f5eb598093b773f7e626f1f88dcefed1aea2558ae6af4ec511a98a2578d60a
35	1	34	\\x271fd630d8f8cb49917f31ea2c8fa9fbcb41a3dd64b9cd82963179c53f83b792a1138649faf5acefbfdef5a21fbd79acf50961a571c215711604c1a10714e305
36	1	194	\\xd41f80b2342f6594b17f33028f6ab25fc9c1509594902a91c4ca95d6b5a89375c9e6734cff011ea510130e4c1b1623ba9770e117a438b650494f111aec31de0c
37	1	192	\\x23a3c622bcb0a00abd9c13ac408ba78ad67d8b6044597de571fbc4d0c33382319322a58e83932ddaa56fe7ca311063a82cac5ba8d7b1d659f25da71899806001
38	1	91	\\x895d461747972fb22809968eeada7162f46700f45c0bbcdf2f11530096ab696be12493b6469e0e4d8a65ecd258a2bff339f7e422b35f03d50fdaa0eed0da2207
39	1	265	\\x9c1c56c8ab503903587366aadb4f6634e479340772e7de6b76a26f1f95e5d90d4c6cd03915b6d7a5cbc0ffd2bf204dcb97ca0f14c3af5ee86c383a6d77190e0f
40	1	330	\\x21a20f3cc9b96b7063ee6eaf34b80db71d4cc09fb9772cca5be570ef434e68f6c746b51b9d7df219051f06478f8853a9faf7ed20c5a1e397cf4867d2d674f60a
41	1	114	\\x4377b90b875cba28b8f8fab909a6743ec1b0d6034329309ddd44d4dd0fb5236d6c3ffdd56d9965b1c17b85d044361b18b3f7cab18e41da400d6c647dee2fe40f
42	1	351	\\xb494090fa7e921992796de582e3218231b0533f8f3b620b4d2744cba2fd6a4c925019c45fd75b0d6c2d4f00a0224c5046103276b2e9d1d50030acd647da5e60e
43	1	308	\\xb5f6c22e388e600a769b1d1ae09fd57b653a9c5df868630de4ed38d9f82e34b1210277434138a6a2e3e2757b7604f985f7efdd7e2c3a585cbc0040f688bd1100
44	1	364	\\x85218d0dac7fef37d426dd2f861c9bacfda4bb0fbe0553f1a578466d97afc2a4d9c16f2741cc8b54b37b763907265bb4f33b41a82f021f6c34927c7bc54a390d
45	1	195	\\x49aa5e9d731536a387a8ebe4eaec0ef68297a4eed5dbe46d117744fd53a4894c66a4c1794ad3df552fabf4de1193767c8f74db882a9b07fb49cec164cbb49200
46	1	262	\\xe3a9624828e58075459ba9dd57a973fc7143e0c6ee55f6acfd11b34821f1511c355f38a1b3d54c83f479dfac2440fe03bdddd19d0c9d26a3d3af70e2cac2250e
47	1	65	\\xcf8f2ea92fc634ac29ff9a67619dc95e062eda500503daad07e28df2d8a8194731a205be119fe836576bd6598419b6210d4ce460df8da475481d4048ae526707
48	1	82	\\x0c22d8e0b414d79292a454df528f0c3938c91a6c15b26fdb998c6b37392a955468939412f5758f054afa6f18ac3da089095492c8fd3d81666fa1e6510e8dbb0f
49	1	161	\\x294ba7b63ab28df9b5b1b52915e4db65fce1cf56fee9be5e8794921133019a31850819854bca1a21df42db1d122c9c559e87d3820aa6cac1f13d0fc25ab3610b
50	1	79	\\x567ff943e21e9ac5efaaa470bb79ce97ca4e2ad16f64f241248fd348240b8061c317e07e75a779781a3eea27aea2adc09416e19d16c9d7d46012576bad83b901
51	1	7	\\x80e80adae8a58f97139c5e2fdb4d977e295f03165a4c1caa6a5063168fcca49479d890096e2fbe9de88f1e54494b1808f833735c4f8598690d6512ec9fca3f02
52	1	243	\\x8aed289a3a3bb16c079dc7f0acec0aaba2f5afd9e0b2d16db6976d6e80856cf71f6dcdaf8fea4f09b2d88e2eb02e331a99f43d688c29a5b6ea63ff5a6442f409
53	1	124	\\xc8d9437e6c3b5ccb089695ffab3055924f0c01abb73b8abfba7bf40d5da64f5bf7752dfb872751bf8115d66e876b56b280e216c3c37d0082cc0b0b533dad560a
54	1	319	\\xe8b2f4a057f61547165c92631e92b7785dabc0f6d0d781c5251c66b450772b2ce7635094c28b460ac004fde3508a98907846d140ba32dd0e469e2f9949670f00
55	1	133	\\x8ae18ea9da53b736b3bd7df8b0b0408cff97f3986270ec5bfb3d7e130a34691ba58ee1b2912f631b8d5cd96c0bc0e63450964e2ee9930924f9083d46177e870d
56	1	400	\\x4e158add64b548619390fb0037d6baf93fbdf091c8a10e63c30ffae6892ac95430d39f742365f30417a74fc1f0842d526978e29efa735ae9273733ec10c4de0d
57	1	5	\\x3f848f85756668a43a1ef771f2444ed05aba37ac246d5f83a7579bf4e56d51289c9946456ba5424c2258e927e31465390fe1d230fc30adfd8c278a17e293c201
58	1	404	\\xb9d720c5c29ad52006b59b31612f4a9936fdc3764948ec9b2583b8be617294e3fb0ba95709fb11960aa438497b8aeef9705f9580bca7ffd4fa9dd748575cb30e
59	1	22	\\xb2dcd604aa90149c8e53426e4bca69239829144205114a2618c821bd4ef26b70bc76268d21259db818969029312f4a5219a114558e8554c25824622cf241c302
60	1	248	\\xb30ad6b7f67c211b0e4ebc9d701e4c26ff4282983bdf0fb5653c9b252046814df0ed6db629e86a0e91b52152ccf69b2996ea402e047844a7cda766dadd85f203
61	1	283	\\x0291e6013fd69992d361545f847336f71e7ec5620934aa38561cbeb04d7f572f6d579cb2ca0fed70f2e6731b2e50ca855f6976628dd49bb5e90fc785fd869102
62	1	130	\\x5ad6aaac6588c2780b94fae8ae615e06b9cc6e43190289e1dcf1bf93a46c44572fede73d2568b58c929373f631a733468627ec1d4204eab4967733cb4ed55e08
63	1	203	\\x83ec8769d7b92b76aff16642d6ee350d58bd8f9ae549cf449d82e152ba6e2f2e474838c9dc634a7a984971a73f12070b447f1a445fe40d463845cd30dbbab60e
64	1	229	\\xbc4601cf9732e198e227d89eb2a9e2a43c0a55ac87602f5a57eb5b0d87a5aca567c69e98726bc8ad20e2a47b323576a29814b3b7e1542df14851a329f529c20e
65	1	357	\\xb2ec8bc44d53fae7be07ff0e16fbb616503104775d7a4fcf4ae456e4f4365c2c45cd5fe502d0273f8694a0d121ec7ad004824d2e732747f4786cc1699b8a8502
66	1	417	\\x994fff189d42bac5bc856abf7c4eee91b8dc894746a8f3acb20ba5601a13d80c9770b61fac95006375c68c19417e9536287b53af8c32d3af6a5004ec44b0f404
67	1	172	\\x9951e9dbfe6f0ced75951c771df322b02c5033a217d4d52430e9cba684cfd5217cb86eeaa663c8787e0b4d47224796c0718ce6acab63eda07c98c89977fe7801
68	1	76	\\xb42e050db7cde135678c8fd3ed724fa45839e1397fdb04148d1bbb78fa321727dce931dd7368086562ab63390c1c24e1d27cd709aebe4375e9d784c3282f3001
69	1	241	\\x46d395e2d7609321be2930724d5a914f3819617872ac44c282d6cd50ad761067a30048ed693a72ed3034aeeabdb92048587cae4fe22764d0e8fe7e81bf8aa901
70	1	39	\\x9fcdd9a218f8e9824c81028a8b4e65e3385b2fbc3411cca854593a35aa37f3a0ef9cc33dcc25b29b3a94a6b02d030a558cc9901fde22fbad3db59fde633fa300
71	1	97	\\xd342d891b1a5ac4da9e303f6c6350baef838d7ba99a6195b57df517c434600f9d5d37b586c7e1989d9bda6bdccaf4327997d22621aaa5aa94513dc289a55870e
72	1	88	\\xc93d145ee814f8095e54c081dd4613c7e09b9a7f6fd97d4667a86ed234d7ea37d9e2a9a8cdda0433be060d86c7d1706137d1f8410d25ae186f7c1ebe3c27db06
73	1	64	\\x87e6a0440a1cc4d8d26cd0da56e6d5e37f708db89619bf79c46236f9fbd525cd3c96c59631f4eb2bce8b6fd772eeb7eb66feba0840ff93dae0b580f5a59f0600
74	1	343	\\x4f8297a0979e623db3c984a501df454e2382b1af17278e0d9ffd1be214ea9bda3e8094731ceefcdffa5f895f529ecd0af4ab6a94df10d9d570b54235fc575705
75	1	202	\\x370a51fadc9cbafb7dd089c9259ae2032c58bbf5b5c69ad19e7247afae759ea953aae11d6558db4b31d0b179f8ec87aa3002d891a5d9e74a8550db686f5dcb0b
76	1	71	\\xf518a827b45047056f635f0e2e1159b43c4eff895934e4a37404b647f0f4db660980b263346a372b854cd95cdce0cc8f6c40ea698f206eee97588315e84b2307
77	1	331	\\x4c4c027f44eaec75cd712a50df2547be5dc43e49e8f0b4d2fb745abc8cf40915a1f3cf463c40cfb4fb1395eb40e73933ec43c492e1e0745d3a355a550303f30a
78	1	397	\\x9e83f3bfcce7f01a4c849c45be7b8b3915085505ad535aa756b5cb2ac234d80fe058e89883c7bc59664d784d5a788e401789b813e722b9d9972d50bc4b024f0b
79	1	206	\\xac0ba9e7ee1a6396d952d915af9afe1502d736243c20d4fb622503e81b6735d4668246e6d5c695e34c285f8234840d476b289cb979eb3224aa5ae368bb568408
80	1	73	\\x859ee6426a0b99615e54da2c1ba191cb14c576dd187f3dfedc90db9cc8879ad69e24c927fc1241d3fe5867a3bc1cd810ac8af1aeb12119b56f0f17e964cb6c02
81	1	249	\\x36414620a23a62ac87ff738b36b258a36e56c17d30eacc73ac9158c4d7b6cd25498c30a14d973e2524f020321cd7db50b330f5b7f809d41ac722c2bc90bb370f
82	1	94	\\x2476fea97693ef78b6752d5c49bbbfb31e38623c112ec71b963ba2082f01507c70d851fcba3f58644bafec6a231c3288fded3dcb7c9e01cb609c1689f1471500
83	1	297	\\xc54185e094c733dc956974fd999c0ccc371fc2935f9ab9fd9b7ba73aeed1703da3a179fe835b3a7ce1ee529e935f9b6a427e2a66eafdba935ac986529346a706
84	1	164	\\x71fa226dfba1924e3ce02fc9b191a3c1967975a922d540b3669f209c5fae34b7584cc3d848a41fa2626b51ff7deb5495d00b265824220de7dd79bf6188ef6604
85	1	222	\\xa6934e7cf414f9749c51bdcf5f31c08e4c95f7142d451b98d0d7bf6d70ec268beba21a3350d1e6b4c8e4b8a53f6d14864436cb5de0fec346c110da25769d1406
86	1	150	\\x72a0dc5d4a5894a090541b059908bfbffe37aaff38579fd0797e9f0b324009c75527e73b396c7007a2b09e9c930467383be06b6b124262f127d37cc10a1f4a0b
87	1	286	\\xe73268c14de2082a42a3d3c3dcfed706c0163bd07defd19a5e4be7a2fa7db1b18df9986f98002596e0c8b51c29e79bdc222885c5269ebf8b5fab8ae8bc840400
88	1	157	\\x132eb0c8d613ed4ff927b5ee4b955d9d11dbcdc8c162102eb9891d17ee53b9b780551f2c7c2e50f783fdae6a34beb9be859de8563da9a21ab7d312da426e090d
89	1	376	\\x40b3ee799029eef06814b13ae6e26b01adbdbe139ee56cf929866b9587c5dcfe08e7b8e176c6bae88b78d90cbe1479b353408e9ad5c4222543fab05b97262405
90	1	227	\\x015bd26f7ca88e52c10da6aa50a3a0b8de78c119113a048024ebcacbfba578fef4eeb08d9bc04d0ff43086b2f55add4daf36bebfcd467a91776a761080c1c70c
91	1	420	\\x7f110521054268501bc944d1da55abccc6dc3a8318f4e43cbd6b8c8421a5d03ab89c725c72fd3b6578016d05a5d2fa38f721b59099ae4ae8bd5b23bddddce200
92	1	390	\\xd3bd6ba2a5b054b172fd983f422518ebe59c7563b038f63ebf2c0ca4935446eacf7bdb509c91f368aaf04d5a682560bba53832a2f8d8d2949be81071e406a705
93	1	117	\\x456abede3305a93e577c68055f4458459577137edec3a1183514ec1d9045b9ba9dee011d765ca7c0fbb262ed363f94838590f45401532dd7b2d9651a9e323d07
94	1	385	\\x21b1e5e17d1f01833cb1cf24e289bc28edd6f28753a6f020eed120815847142246dcc80ad548ecf54b9b3bfbfd224cf8ae6c9ef5fb9b1520e8cd61eae8727c0d
95	1	208	\\x7eba33401f66cac91978ba60b9294c289c4d8bfae082cb0ffec2dd5b8aae735f49a2e59f29d2db9ad85da7d89783b75bb35fc097577aadb0965b3d85d40e8504
96	1	266	\\x0379fdc0ab2cedb5668d0efdbc8b48a218414ac81f190c7e4512dc4178444d585515d13a17bc9a42ec8b3e0ca5dedebcb6c7da86d42e6245c6643d36286da700
97	1	306	\\x615daacf6859f9d0c50971a7cd15c8fe86dd7cd6feb25b92a1714ceab4873a10774481e8e52035ad7985b0a11fa83b2e6166062b2dee20a7087ad5333281ba0b
98	1	113	\\x4c89590f6fa3b1bb399852d094b794090a2b8d8b8924b52307f985bc5c7e5e194d253bbd1c9a5168e62428fcdf8a375baa37b24bdbf1fd6ce2af992ac5c2aa0e
99	1	349	\\x0bc5745e23340d17d38a32dce2d3c247f892192dd2bf0d1f55468c1b83cd173ff7954bcf9a54951e5327c54306b529454e08b6c73feddd0dd2a930597794ad0d
100	1	1	\\x30024f0d33c6c8a3dc01ea5ffe862fdbd1f4c50f4fc28fcb9466a92472897ddc80942ac1464461aa931cb14789e99d433c34482a400b89dc4b902ab71621490b
101	1	184	\\x7764d8c60222b682344c8a4d7b5ab8e99854f760cfd286931c66793dede0ca4aae2cfc5c5ae79ce986ce19ef2b9c97284732b27c402f1f1206f46c460952e400
102	1	44	\\xa55fdc2534f29f90e6e7537e3cf99c614a66cba331dfb13549413970861f425bfdc5c06a015449bb13d7f5cc3ac2288871f656d5227a869c6f363cedd2350102
103	1	9	\\x65f664416810df47ec6a7546b73951eae69d12e300353898a08aa85055cfdf2b251521976c97eb74c65a180b1791ad94bba17e323e1edb962418b3b371983307
104	1	374	\\xe7d278d10d2afbb2c868873b2d43174ddd9177ae0ccd38786b12514a3e9b33b51cb50876477d51e6709cc04da640cc6df1e6502888107f6e90bcd7f78c709a0d
105	1	238	\\x6a243d9e83bfa1443f2f1549c9b5a46f1d3a591072896a3af7bd408d26383f1e8a13dcf2b4f86f22b189fe03b58806a1d68d12c234bdeae8a79ea3aad5c88802
106	1	393	\\x8dfef23f542a60ff244dcc4c6c26ee123ce5b1f75a798e528e4d7876bc8e55dcef37a0de3185ec4b648bbe0fef14b0da82d6e875ac1e37b58478668a2cd43b0b
107	1	216	\\x109a14b3c3a02dfd5f5d42b45635dbd6b806877bdde77afd699054cc9f09ef7c568df2c87ba4598d85037036ac63b9ad4ea1149e9de4620c3082c6311162850a
108	1	180	\\x22df26eb4cdc57b8471a2f76f6d44b3559b580b07b396c8aa8ce7321bffc4825a2018b62dd151633f884a96f48f6b85649bbd3ace42f3955155a6f6870dd4c05
109	1	190	\\xcfb06e4692e01e512fc8a14a3dba1a2045080f8166483b21d38b373749ae0dbe397b1f2b57eb07563738fab9ac294d918d686aed5c2f50a5a0c4fcfef5ad2a04
110	1	167	\\x6f8293d188ae3a06d0e2cf287d2868a7faf276780528cf92966ff8dc88cbfa8510cc9966313c0eab67dc1fc6cc22efc8e703448f751d0d639169438945775604
111	1	98	\\xe480004c07df409cc3665db56a8cd4b9eaf315c77bcb05b75a1d137fa7cb960569c312e279aab9d459b0dd8a8e2d24004b254580bff1976c0d8826fab4311c0d
112	1	336	\\x1d4eaff99ef89bc48de80f199551ae922a4e963cfe23a28783120aa00fa62bb6c9458cae3c7ad3517834a83f3bd471b7d88ea52053257754f8d3d0bb53349204
113	1	85	\\x3174d0eab6df561f9d2cfcd567dc383c040b07b85980ad7010ffe21eed93ee42d884681980c296d30fe16ec5022e9e31ff9d86520e49819dd37b62a43a9b960a
114	1	387	\\x557b9b9051376bb0aedcf1398cc94c172ca5b3899834345f8b48adcf348c46efc3cbff4892c1182575c9f483e03fe83d033262da2283173c0b8af1e3e4f5210a
115	1	316	\\xdfdd423349196c137a3e4d60140d4e4a9954ab7b2f678ef88c064d7945f180c60ff7f91698fb29d5ee66acb0ebd93057ea58df59e21223d5e3916ff630d23e03
116	1	341	\\x767f1d57a2c5cedd28310207279e83166f3c455dda93edafa220f19336cc3b0a50c61ee50d36943071d13ae0a14752188132157b71dfc36bcfe07abb8e11d604
117	1	324	\\xc08a2f116d40cae7f60d549c9e7b9a9698604247770b2e3e74a713303797d7bc82e919f3172b6925bf0c537ae99f1243b5dd46fddb01fd1f17cfc53af8029403
118	1	363	\\x5f55faf1654563ac17adb4f70f56f28ebcf86b38c035237b1f38479dd5bd284476a1da0fecd5fe3dad02db3d1d9b53b6031f68c14be233ea0095b956c1fd2a07
119	1	135	\\x2659b889c7d8f92db10fe2d6142a4cd07be765a94cec7c5dffdb7c85e6ae1ec61aa0066d30e9959393b9693ad385c8c8b2b480044b85eca17c289f98c5b3e506
120	1	59	\\xca5c14d72805d1af85d916d57bd7a7e575b3cd982d986e0d301e8962d61f448b6d08c770dbe8d9fde5c258e3b191f4c94640100d57ada108170bfd6564c3730e
121	1	30	\\xe95f235ba00e34e2caed1b145e5f1659e2f7ae069be23a02c8b30aea84122596800e123d499e77a97bf620e5c9e3730a2e3c13fe145ba003ba792f5b003f160d
122	1	423	\\xa149981a614dccee8e1da46ee355d17dfb0cbc21639a02a82276e64e010df13abac3fca60736372db39e2818d726f2d272b2662b40a3ca4374b9cfb80fe42107
123	1	312	\\xcf93784a03e5cac9d0a6375d80957b086a9b302375613628f585a34a7bc41db2954f1cdabf26b9c874b55e4fb1a2ea39fdc990ecbe57bbe778c64b6b24945e03
124	1	252	\\xf340e5a1b93e69e91fddf37421a4b56ea2b7a0e11c3697d9f1b6c22c9eb1417348dc394873e2e45cc159054bab64f2723882ceccb319aa656545cbf475ffd406
125	1	46	\\x0051d694681ade2c45a8f9b45343f0c06652fc7972a754eb328d05865e2a7582c00bf486bfd912f1782e607460eb13244b6015f41307b45dfb5cf269c4a34502
126	1	232	\\x88b043b818d304bd8b12f8b3b44fbfa90a825d63e82eb8c41e853bdc3788c1a66fee7410527495e21a5b13aec818a3d0a04a5751c8ef7dd18e9b914e3b0f3508
127	1	271	\\x819e2a74fc136cde92e686c59e34b9abe36cf987d8283448ef6ad0cc85b8ce9a92dfe65790203a3a4d8b7070d4a1d1783437a24aedc43086a6a4b5183112960c
128	1	17	\\x0cd8f0607089e608af6c438b5cd5b723f3cb17e44b4b59098cb1efb727631b16251df914c7a739abbfab96635e832581e965800a4f5819a43b54fe2e480e0d03
129	1	23	\\xef5eb2deb848603e8896bc6590cf6eab1905af204dd5d6134621f56f78b6de126fbc94f7d5251074174006de448376534f3818797c2b798a7502cdf88092cb01
130	1	146	\\x7aa46cdf955a34de0d495e4d33955e3d34b89ca7bfeb427c246faad515430215b7931c1adedec4c7df3dbd8ec83f44e1244bad01769cc45ef9fe1e04485b4609
131	1	288	\\x6f7e088ccbe38d4106a75b5d02a91fb88b3fad488f5a16ea48874379f87d83ce987a4adfea0adc94716f34314c7b1a797801e4717ceb4cb1e9d851b9add44904
132	1	276	\\x053427a8d7c3a598f00f492f3b8d43a4ecac4630748ae7662829966942c758d13190d8ee12f4ec1a670f04cd52b7ab70af0604480451d13962f7cf9ea91ca70c
133	1	237	\\xb755aeb5829534f7bf55f40107425036ddd846e47ec33c3f8afd8feb1654a9a8ddb603f8110c2dd1fe2e66a74b843ca5d8f657d601b00dc71243c11ba3ce2e01
134	1	230	\\x90f20b5f45e3fbea81197501a2f39d3dd9ccf65cf7b820f0d06fdbf7ca84ddd1bfc634587fb453832a6e3831e9465f0766794d6e894b857df8c579602049d50d
135	1	54	\\xbfd3c67da091f31ca75438ae136008df45c967fe91e278d180d11a13153a76e4ba872d518e64244739c8cdae2d91a9c72974f3ab9de455fe3b5aab5be4c3860c
136	1	411	\\x4ebc565a2074f0a2e387ab760713baf0b78d6daeb292f47cfb07bad0bde88c818f87ad042dfe34f732174f00ff0bd5630e494e287c4d877fa63923cd6a018c0f
137	1	181	\\x88dd3d9c57c52e09251ac3fa8d0379b8abaa6b092f18c72a959ba43338dcafb1e1044ed15f2295c71e865e1e6c54b13d92fe604f9aba3daeb935044a0048a70b
138	1	196	\\x8cb47f8e92d7e0c62c8007c57b87b349382383fed27b2c8de6fe379a919e465e2fc40ef57f7b2729839ea4918f9ffeef88d46f1413d57d9eedece5cafbfb1108
139	1	290	\\x41333d151eb66cc3796fadeef829bcfe21530854f66a860cb10d8f78f186303c5a5e546d8ed7d4e1264de45b79c4c82feab2dd83ef805fe6829f95b82ca4750a
140	1	78	\\x13ecf09eb8f38d27940af7e3d8f109387b46cb9aed12d7860c5ed4fd852c0e6620c7a4f855af768cc5c0d6dfe9c1463ee4745e758d16200da5fe866795d14f06
141	1	299	\\xf8cb55d79679c78522e24f122986dd2e2cb9f8be9c8c66a334f02edc6661f9f02d9c6c3a874789ede0606074b50e90ae343a2926f0e5df9ad2abfbee776b330f
142	1	367	\\x0499a57e77b2d12c43270da6344dabe79214e7d1f825aac75ce47266d345f8befbc5b6238aaacf35ad0942610aa721190c832641bf4efb183d081435397b2e07
143	1	310	\\x9cd59d1b348381df458bdfb265fc1187c174364185bf48a9716c3956cc6d42983eafdee8c6c9c6edcc6aadc0193d248a49823e83f56642636e9bfced761b1f0c
144	1	370	\\xa88af4d741c025feaa696461581c92ce30f9d47e59688c926b01c9933fe713415f02656470edf2df387d5d0a1965abd64be4a12b7675ee6a4bf09c2c7c032a0d
145	1	223	\\xbd545f3bca2046b340d576432dd2e75d4b4496a877dbb5a3042dc98ec633144e1e849967cc4c5dd8eaa09ef569e699490de05bda98b0c15015af2f3bcc011306
146	1	348	\\xe3aa267ef21e2df735688167ba38a5dbaf3e6612c19cfb27aafd9206a09d49405f003604b9b012216cef7b5eaf8b320d95ed5205bb55a2ebf555a88e5486a90c
147	1	162	\\xca1271842e886d5d75d4f34f9aa57aa2a7b4e350ae5d2480a23996c0bcf87d3e9120a85d9dca5b4772145fd237fba922c279c82a7b350c1917f66e316258a50d
148	1	24	\\x516a7e33d4e302b03011558e53680ca7f26762b5b5aac1194306f619150935647d2ad5487412378929ab02d747df7b58210924279bb35ca962e01df2695bbe08
149	1	145	\\x4575393d388297766e0f4f6e44b1b431f6d5a87f6da94893a226b36439685e805fe6bb180642ea1485dd3895bb920296a7218c66d9cf3370a3800b7b99f76b05
150	1	251	\\x51927b94bc2459e540a301a86a7c7873867de387afce7ff0bf6cdaa3b9e3f6862e1a0c2528ee6227a50d98e6f4593618357e2e1df6d232724f6fcce465289705
151	1	179	\\x6ddbb3c397b1dd0068766161a410a7ae20a843a3e9abada7b94eca723aac1ad723482fb15a78a235c42b460918667e222f140344b2de9a45ea9ff837a98cea01
152	1	350	\\xddb229369597230db7f3e1965998fee9ac15c056d89b625d13181484911da9916bc1fc32e6046af1c746d09a3dbeeaa51937e87ce9c2adfa8a80b225687b090d
153	1	142	\\xa8fa66c5459b2840b15f85a075b587dc4d0c17b40e3c9fbb5029fca96015bf6ff939029c61ec1d8ffa72041eaa93775d602290fb7bfc6f9c2299ed731278dd0f
154	1	365	\\x1adc5f788dba5e91ca77417edb2806518c238d959d783c00caed978e31393dea220b34f3aec363107942c3961afd147576dd46e98f1363ea7f801cde22389d0f
155	1	304	\\x91d64742010a0d023eb5e5bb3ce4e68de72300cd845d4f39ab4bf3f0d47292c53a81380b4790c33650f0acf2013e97e4848ea3a0c6cba270f1a9b641d03cb107
156	1	218	\\xe114e5f70cbcca56c493474e67f873a338261a043a96b6ff3c464a92b35fca3fffe3afb89abf5d6d0099840be66cb1f2641cf9f914800db92e3af616db20f404
157	1	405	\\xf37db4e6bd67659801d446a78acfc61af80b2f33e0eda83ee76f70592593fe9145a3d4ae001dab73c1000c724294fdcbd5c0fef4f843dd46c39e5bb5248d9b02
158	1	92	\\x7280b79dc4069cb965b4dbc8a75af7b3afffabca3fe2077562fd7937c952c500504d9068c827c1ccfde4df67d85eb0b9466b0a40d09bdcfce8e97ffcf9faef01
159	1	102	\\xe67b39455eae68effc25d3cbbb9cbee6514b2f8f3ef1d3196a19e6253348e8866b72dfe122b039e52a2fc0f312a5b17b536060dfdf858d4128ed729e26120b00
160	1	99	\\x42dc4c278bff0e1c3249ae23be9d7e29919172f1d5f892c57069ca7f5732bac259b6d38e1a15b8d1157554a8712d54d483e9d26417c1b6054b779258ff024d00
161	1	372	\\x21771c1278629f7e45aab36d6510113e9305c0e28d8b34ac80df0170ef8fd2269d3f7c8f4930c7a8fc661bbdda79368fa23226763c2139b358519a5238e27300
162	1	129	\\xcc8892ff162bacbc61d833c0761995bc65c10e5b962a505a6c97fbdb36b05a15898f26ce85cd4fd68f74867646bc04fda8efccaf84f399647208b3fc8d831402
163	1	217	\\xef068fe9a0aac7c78ddd291839038e929faafb0fc4d462b09741c178b838d830b6a2bf5e02058731e57def2a976dfc36a7cd736e5dc7b5a0b219e0373e3ba608
164	1	87	\\x853851c6f1e2fcc345031adb799dd999b9fb5bea6e88824b28a70afd23e990a60cbb893fdda67f73fd926f4173b671a869d1fd3697fb5b3dc6be0887e1ac030e
165	1	259	\\x70c2cc3decb9606b1c1c10660a0171c7be01bb94d245cee955f063e3dabdab5210eb2919694de5a87bd82de550a21125b4f44617d4ec528fa183d1d2af7aef09
166	1	37	\\x05f51b39a74d7548a94abbb5da6ac9c9184ca1d86008c27f09514b72276d7621c95909cf595b22d703e9fac3f08f42e6eb70c4cfecb76c42b5be7655d018a505
167	1	293	\\xf034f7ab3eb592a3803c08abd87bc16237cd13c0f328f5c4e2e652e6d716ac6b637e20efe36c17d585f06385b1359f4c58bf6e53480d57d41b5a5de0e7da070b
168	1	186	\\xe4bea5e924a466005084f28ad1c290345cc14a4f557766af1c268119b4dd9eca0307387fcca33826114ca3394ba7808aa4c7a2b1ae5fb8d442b22a2902632e05
169	1	70	\\x22ff2dfd88483ab7b440a7c49ef1253832f706f0e36a42beb389cb61f533256b877d12d6e78eb357d787719808bc5517da384f9a7757998541e94196b8b17602
170	1	125	\\x74430a8a3038a5c0eed35a941554f7a5168da6a7a0f32e1ed6670f2154acb1befa091ad06ce645acdecd9f17985ae6019121cd00b4a0d1a34c688bacfd1ca008
171	1	226	\\xc51867002ae4661b44e055aad275c3049d5b78672b38a3b8ac100a785872af008d6e21e4aa81a47883800dc5f3f4497fb2ce909d3c2759445703101c33e90e0f
172	1	323	\\xf610d1b29704ebc3696ca92766f38c18cffff8abb89cc799f667fa18a6420c8b77aad6be758d10b6158ebb1bbee9aaa0c29827b9fc537912c02326bc8b125c00
173	1	415	\\x61f2c5c892b66ff80d8244c0969dbcbde50275fe3c7606c51582c9d73112c00550dd3ae095576c98b39670d1544b369b88161848738076d064baf32c5d7a4704
174	1	413	\\x42eb3e02a0531a1b7b34111f3028581387a658908562b41db2ea6f869ac9ec63bf59db4d44560999e982e6b5849e641b806fb06fb2a6311e5972ddfb7bcc4009
175	1	313	\\x56213bbc705dd2ef197418ec4a5ce6df16f7e25b72f85a7b2ac4c3f9ce0129cb1eae0e41c041e3f797f04a5035b774fee4436025708e3b7e4c1855c95bd8f704
176	1	166	\\x23b3f6b374096f39799286c40f2428f98dc3e54e12ccbfd8148361c69b749f2ba0b36cd4e7d629ed8be9d9cc1457146226a7c89d78f27b2ec641a20195e8d304
177	1	315	\\x5c9e0b7d01d9ae75e3bb603bd7aae694afd5400ee480e0532d3433dc84bc7c5326241f301fec5bf167dd1f83bb8d658309dd04213385882dd234dc34c5dd540b
178	1	131	\\x957527ff6107f6f062bb6bcab1a9261f33cd8224fd31c4c215210532f13cde5dafb596e3c1b1411d3b01873b8216992738bd33bb79489163a3b39ead42ce5908
179	1	215	\\xa66fb1f8ec94a1cfc8d9b13d55ac794c8674e490c594604866d82e019d166cae61afe3690497efbdfe5e27458a42a22ceb8d0b3751bc0935e93e8505ed61320b
180	1	421	\\xf5f1c0303ee60ffa0fbb5cd795da9b720af8cb3c93cc02c4198f9315a552f3a8a91111e5496548519ae1404feef0dd295b43e54070ef4b49c73de1cdbc59340e
181	1	334	\\x80e226099ac5cd9d9f436c644a85132a183b3b88ff71d1ab867d86636642e7706ea5dc517987d3c36af0ffccc6e35b6edaa4269f0e7ee6292204ff36df7d4806
182	1	284	\\x786a6bd19ea08f323494a0cb3c333d5a327ff7f1e93af634e2b7c457f372b80f50f2e260e003c375a90e79e82f7f9a726dad9b4aca9776f0f5bb4d5bbd30c30e
183	1	169	\\xa10a00ba752d28eecac9e7d2fdc4f293e0eef0c69b7d0d79e90e7e2ac97200fbcc6cc84bc9f97f716470f47ef233c63d15542ff578ab6660ca49c99f06079800
184	1	69	\\x3d2ed59b37da9cef8699cd5e4360cbc7fe58bef47d6ffa933375f3d7ff75be8987a357ed8afab7bcc7791dfb4170975c4b4c931c5389c9bc012d750d7b33d805
185	1	96	\\xbafac34916ac4f99c7ca3340e89dc8c1568b06cc4edea3c203358ec19c3c5337d80934347a4cf6449423aad04b252465ec4a4450d127acfb986d6be293738203
186	1	269	\\x17342e1ba898da1ef15f4e4f9401c13fa55f1bc62bc1bfeb7ae3b1faa5b0ed4d7cb1c47c6a745f009630d1fa0285c8d495bee134830bef9bed699988eea02600
187	1	314	\\x5da78f2134eb798fe300c9c621944510e45545eece7ac08e4e1eec04f0fb9307ddd080e11712319b81fb561366c31f400ef30c7f22688728ba1aff1472f83301
188	1	361	\\xfaa62df9789e884c0c877a13d5dd6faa93f5efef102dbd3298412f86d7094eeeca5d8cbd9e3ed4c771e368d9ae99a80adef07000f61393914e80c067ac76c60b
189	1	371	\\x96797f8cdeaf3ccdc8509b8c6de7c930b90dff06a1c364ede4958777a5b199739af30f7a8b4878a036b7aeae25c1ddd64bfb1c774b68185d6aadb8cdb9149704
190	1	106	\\xf8d4fe0d2a1a4b809e991dc1e1ca84e79cf821dcce8a9ac0c84945f7f6627be90a39179e31cbf55f2129f09f1c34684a701a0781e8658e7b76b2318a43dd2e05
191	1	27	\\xb8f36f75f187e436f12d91591a3dc0b5a89900c5d0c78dbcc8b0ea03d4cab663174d6791443a9808a0b2293726d2c00ce7a3af47d1ee987b6003622e9e925d00
192	1	95	\\x4be2df239eae17f77eaaca382a8430b15ad950c5bb9d72d9a897ee75cf5de83e16ab86ca4b951e41b6664c4bf7dc236f33ea75d0ef68e8cb563a5953976d1202
193	1	272	\\xb65f86d018c41dedfa814f97affe70612ed2e1a0d3344ad8567d7bd0463ca3e90fbd5957c658e5801f4eece0ad41115a4c3af08cd4cbf219c1dfba3aa5842106
194	1	50	\\x04bb02fd1920b2714fe45cd57ab82b7960adcfd1094ccb244f66118c4a2867b363e612810d9110d1bbf4c6a2f48858052480a88a439cfc63f79782baf9e9fa09
195	1	100	\\x14d0c21109dc4ba5549c4bf14e945b196d1c61aae9f1a9d368959ba1916d9c4b431c466fdf0223f0d7cb8c250f17810710151f9146b90b782a827a785dbadd08
196	1	108	\\xbf961c115b403c004504ec8bde9484c4439280b2c24054103411c20bc9ae92688220590fe777d074b4c91af93c207582a3da9f36de3c1bbf901016e769db5403
197	1	302	\\xf4c4c96b90f6eb28d5ada7d026d9e7fdc38a80a52b9c50147afd23fbd63bb6401512cd60e51389b14a7ad2efca79f5811b1df7a73b339686632b01323ae4ca09
198	1	134	\\x26b58cf65eace1522935a872d0373247a027e336544bed12f740d033bcf49cd03ffbc2660c60c445f051793fe8d630a8b428e42b4eebf7ced5a6b3284574670c
199	1	247	\\x3dc959fee06933c89135e73213d36529c550525df7a96159e620e93da4b8fa137b9403c5e84c248daac6cd1c2d9ea132f5dc0a2e3e58b844af96fd810f8ffa0b
200	1	140	\\xd1663596cd52ed5f8086f5efaa3270d4826bdac5b301936bf4d4b29e31d4033e8c82369315a9578197e64578009d3e2c37016d2c0183fd58fc94124e37a3a70e
201	1	221	\\x27a5ff87c36d924f3722ad043230c397f9c3e196085bd39c45617968612fcd11af51323282734ea7db771c3ffe458f8df54061ad4efd082d07b9d8edda879b07
202	1	296	\\x0ce4e511831aa27923d18f570ddd9a5257953b44e12eeaa9d0e8785f52237cc30663d5bcdda6a3d69cacd9db51509769a5768175cb5210bd2f8b573f99251c03
203	1	163	\\x38ff78658dde76798c7f822bbe93751820bd209a937e6c338c54b4288a895e05bce58a5c9c7c09e282914b6066cd4ba4e5c7be60d6d30b14ab140b9466c33d0e
204	1	11	\\x534e756f47bd8f12a1bc58c64b666c293d2c2424919b4e323130f1b6cdcfff01e36dea2e103ef2edd2c76438f8ac228a7256389b00fedc9a6b4db47e5a959b02
205	1	253	\\x27ebd6657fbfe20c531b280fe954face25ad0fa1929b5f8cf8ad94c31cc2ca1eda6136f7e043c747ff7a42a649bd0065d09a056d909dba882639c80521a87d08
206	1	178	\\x2c2c64780ce551d72a424d8022c9943a4a26329f7b299e7dbf5ba24ffa0cd285b5dcc226a6b8c38c44d397213cd70d917f3bf915de17d7fcbadf7a82c41f4b05
207	1	152	\\x156b345e95c7ffc2a86b99979b9ee10edbf5d312a1b4063120d661aa6906a724d32ebf82b2a18eaa360bde76b784c1702ad2a92fa67fb7bfae11c2dc8fa4db0e
208	1	109	\\x6420146ac6ca9fd7808e122d9ab79e07a9caf27fd5c2cdc5ebe470d80b529cb9d6574c6bf6734c31b42f0ca91aaa86abbc4c11fa4004459bc03645a7e3428a0c
209	1	388	\\xff4d9db104e72a422d3295d925bdcc63997d9ad85d0fbf2ddbb06b3b93139915bde95e4690d5e2f92fc251f576bab9c24ee4dd698874c42ee18dcd22a66e0300
210	1	326	\\x095c24e103b40323896a8085a18f5722a99db021773d01670b4b4e287ce07901302a1d70fadb0912f1243d127bec399288ece2524a4aaafefb0865633240c605
211	1	121	\\x0badd9947bcc581dec45a8fc82b58d0396d5044d3f7292f50056a35843353758f01f7860bbe3532042c86c3255ae745c11da7d37a8cadadc8aa940d001d4f30e
212	1	354	\\x66db8286eb51e2883196508c6c408d59d09c5459fa1481686c4fdd62f6535ab8a366100b5a34c2b1ec72a001e81142e1c1bcbb12b37b197455b7b51d2c20620e
213	1	148	\\x01e63a12ae8a6f76c950d8a331242fe52df37043fa990e81a5a3947dc1369b3fa5675345359c91060d200b6f50d3e51e864530fd60ce573b661b30061b2cfc07
214	1	303	\\x2271da0370df022bfc37d0939bf65a64c5ae70ddcbe69825271a4b9672071b286bbc9e1ba9b75366bbaebade5c22bad5805e0336bcb1d88401fb6ab3773a6c0f
215	1	347	\\x2958d9a0369133dcca7e3ad3137bd9e5e1a5e0fd090e26bbe644d98fe383d645afae3b2d41ab413b51e05c5d442d737e7f8f1145e415e41235bfbba0c264c703
216	1	25	\\x5bd8bdec90924518fc3de5bb46b0874c7552c039fab5bb6a44fa4864cf9c2b06a62adacb7041b765213210f6fc85dfb2370eee409116570a0dc8530286038900
217	1	210	\\x345f0227a4807277313436652a35045a1a2436a2de1af127fe37e13dcd30fd495b06bc3f90e224eece314fab2871c858d4c018994917b96a8dea2ad80fb17c06
218	1	366	\\x37815f949fa2b179bed83d0794949b83ecdf292154e82aeaa6e39ef2a777c4d28a6cdcc73fb1739eaabf7b6b1e549fc00562d21537fb09f67b3649f478758905
219	1	275	\\xb8a988ef74add8e5e4efca8321d58d554bcaeee4f651d34ac431c3547bb555a631c83bbf661571b6e45d3400b7cc9aa8a0c32ef6347c0d4243690f9a8c04a400
220	1	231	\\x6c16ee343ba79ecd9cd444ceb59a31018553505c44b75b523897aa636049f22db897b51b81ce40e24a77c1cc62a57ab90ccf691bbd68a6d7d5abfe0e50b5790e
221	1	151	\\xa182a1d6f2abcf919a9b3876bd9a8758522c554414b99fadcc2c268e318075301af209ef71e1452d8d526df911559f4d1c7567e8278324260761d6f13b19630c
222	1	193	\\x8c0898d98e2b9687c96624f30b44adbf9dd7642d3a938e1163bdbc9f40d047fbd6809f0ddb4be807b3ecba109b58ace58a66939e3d51b7e2c243411efe31a40b
223	1	35	\\x21eb34d3004a66a918af31f48f0c0eb0c86285d75d9afab5d0ee4fea026e3a4dc84c0a9b6055ea60204d611230141a0dc39b28182bf6e0eae4cdd2591fb0b307
224	1	204	\\x66c324097e4f94a27c2eb41992e535e4eb951dab0e8d52cd8f08461270d4e7d2821b62788711dfcc4a4fd7c47959ca0c698fffb5964f1f2d06bc7970990e3304
225	1	273	\\xbb34fef03279abaeb5074821d4642ebffaeefd6f55e0c6c1b414150e5433faa9179c9f3fa31d26bb3274ec60ce6657eb452f9b26fef1305cf6b102aa8eedf800
226	1	402	\\x0cd6db53fcab3682f362d836011a149210408c1c35a19fab5bf4998444b9dec5a483022998b2d51cd799a5d6a34d04054ffb98caaf5d71dff22db3b68e80b103
227	1	235	\\x383b1dea31174886602332a87d212afcc97d19598a7b9d744df48f05ce329f955012acfa7376aadcfe8126f56df45dc3eba03fcea8f0ea83f5aec92585818c0f
228	1	58	\\x5ac5ca7a4513563ea8db467b1be53365f48628f12dc4405c73e712d220a1a686fb833f8df35de82c035d80ef5eda32ae51059f4813dba707abe859a796d23809
229	1	86	\\x69fbd07034668872499c03836e1438bc55d46bc6844cffb87b303047abfa28987b6c1cbda9226e0f63e94cb9b32815f58070efb7d57669a36f70ca4f1f834300
230	1	378	\\xf329fad5b11bf5d5e4c0440247e19b27a52c48be1f0a30b122e8816db4dc165440bc610c14f37d2da58508e26f83800317b7c5f924432dc2c07601cd3258e503
231	1	15	\\x42cf0e31b27c16dc00e0fb5bf7c1778b5c605f22e750f21b80d442dae8cd51a78b8ab0607dbc96efdde23ace244773bd12824ae50dee7bf14e8cfaac14e67003
232	1	255	\\xb45ce5c7162c64e1aa2e619aafb8253908acfe2e42e3ed6eacdbde2732bdf7ba8b02eab58f3788288ef6a4b5ff184ea99753287bc5c091ac69c95ab806452b0e
233	1	214	\\x12f438791a6d6ea0a388e7934b1a20de808441bdb1ebe8aff975b5aefbc33a4e276c6d0e00f74ccd006061f9cd4f46460ad99e9fe906fbadf379abd000bf0e01
234	1	287	\\xd32c1048871e420d2245bb883bf27dd74464b3389e5d02ff9149b95eaf52b803c22525d0682257c7ee3f2324da6c59b3f1d86634195d77dbccda2665ebde7704
235	1	8	\\x86c15e3d3644c7aaee3e7553d6e3b3876eca464847803554cfa7205627b1c82a90d3c6356ce5501c1959d12ca010fa3d179c97fe17cf4a7e75ed8dca136fc505
236	1	89	\\x9521feabdbfac65b7d941899d93b7298c67a22ecd69d7b23997d1b40c0c6754993b69e76bb16650a66d888be970dee7e3cb6d2975dbc1a3539484736051dbe05
237	1	168	\\xf44cc4d91767ed5fa7a0c3a19099fdb1166ed4186d4b928199d15012de18a993995f7c6c8a07e2cf27e1961b68bf202d2a7ed2cf8742bc946b5f3eab00a76c08
238	1	211	\\xd26eb37b8a8d5391fa5299a0611aa71603eb0fb0a28d74f9aef9459a027954b34470d85f2db788419a6b8800964914e8e83952dff4c0590c8b90dea0f9faee00
239	1	138	\\x7525769cf3281336111daca8d0f3de3a2f5b6c2e55be0950c3b6e47e9664dc168cb01bbb2de2c1df48c9be5a9378bde0f58e0ba5bf11db2a5781c743fa281b0d
240	1	379	\\x858760e085dbee4a6af4b8736458b9be4fd9875f403a58a92fa3d64c83996d17ebdf854c04f51f560d4852d2fe86464aa9768d94cfe5a34437c8652cdb2f6808
241	1	187	\\xd372e1b6b85c6a0dd5eb455be42c9e88bfc96df858abffaeee62bd5f0bda7757bcac8a5350db518ab0d9c5715a532ad2437db149565c341b002b4725a6084f06
242	1	175	\\xac9a09d0e1fd4f7144a3aa88ed89945b73e845d8867b6db6801e8a0ebd501d7605761ef4f43bc111ebef490bec254d307d07a843c8f3517033fd4ee38889d407
243	1	33	\\xb8d6e1b06880e3624cc57600ee50b8720949ba419cf48156e23bea16820fd0cda676fe939fc59b5612dae9ed238460a371da1b55d233395bd153129daa0e0b02
244	1	333	\\x8165d5fd333e292ada3e16ae5150b2fe5ea50bbf1c9c97d731cdfe094098ee71e4eee3c105cea5fcf6f4d0a43868339202e07b2219e0e93f94d4a89a2cf0aa0b
245	1	228	\\x13dd2168b3c1fb4f4e058a7e1a39b358f81803a0e871fce053d7065918a5fd6c839797ae49cf7fc72e4bda4eddb7439f62e8d2013e47f1f9c884b803e5e81102
246	1	375	\\x261d07c541c3fc8cd3053e92de0e2f6de2bdcb640a7bf5f6125b321cb3ce2d37e8f409b21c86497e4e4dbd4cc922d33649d2ad5c52a40c452a67bbd73a7d4704
247	1	342	\\xa8f40f3db0c23990ccd9f6829003ce22bf07df546c9a18264d5d6e18d3dea1ad4e38dfc6e9ca75e6e1608a1c7186c189f76d4cb5fb2cc343dfbbb74f43925203
248	1	422	\\x9622284ed7349990246ed99515954b1b8b9bfeb12a0107e20c6b0eb0d29e44a4df06139813d6487b05ce1fedeb4e77d10a4bd28e7b11665d46fa90f59dd86e0d
249	1	61	\\x8ea599c2125b957ea72d1dba2a0069ee8d1303d2ca93738c1114ab666a2a810650fcc330ec5dd7e061c3f114b08f29c997aa24556365de9ae51dfb7122777a00
250	1	119	\\xf0899e725c026d6587a87d8860c24fb32922e54ffc0f67722b21fea3fef1c34c81437b9514e7b2c339252c87dd9f560c843731541943cba588b5ec8486d96408
251	1	41	\\xf3f8300d5fa2c5d837ceae5aad38b848b724ec476fe7a88c56dbb20d30b124efbad6ee515f4a35b82cc24b5ffff9131074aa28e196266aede5ce726140850105
252	1	120	\\xf954fda1ea0b8b630d2c8099e5c0a8a431223dd6571b2bb72f73d86e38353d48b276532a63e538a21c4fe8e82ae45464ba01b48bd01f9ea6bb41605533fef903
253	1	77	\\xd5749b860776ba3c9c5100b65f14c740f5f983dd9f01326dfdaa537f4f7a3b4d99ff76ef8dc5ac26f859e227a6490cb9919667064409228246d98b084118b100
254	1	48	\\x36401e4bb94d58ceed2a9e03c62eea6779ede299dd5beb26cfc1f32698057c0437f2676e4f19a67d5c1a9d2f1eb9c33e9d8010ce6b35a2ebe8e6b43a63293c0c
255	1	104	\\x91ab99433e3a6d77f0772b9a90944d50d17751cd19295f00ec79b50ef2e1bb9fe19183c8aa2110880ec1170ffceb61d7885be73f79462ae0b4f0cfbdbae8ef05
256	1	368	\\x5e9e296dbb0a18be74f086d43b7ed26b829a5441674976af31ba387ed28e4e463f5797c1aa2715372dbfa844adbae39aacb706833a8425baa4697893fa2e5103
257	1	384	\\x1ce2620c217b019faf238ccae34b1425b1155fe2215b0aaf10fc4be4c9798469d29f9daeae1799477ad6296c5001b871712beac92321055748343d442f70e908
258	1	21	\\xfe803497c0aad699aa221aa075588d9a81a5d5dfd49a1c800585fdbb1f27fbea18ddd5afdc8c6135a8096148ecc1f72f50e528f4d30a14592516a65ec7248302
259	1	321	\\x658a7ef966c23fd358e3ab6bd8797e7e034e6fe8374fca24f8e82d11c7e386e30c4357bcb5efcbe67e7c0a61762cabefcd2a7209b1db1d61363910c98933df0a
260	1	110	\\x2204705d20155a4df4868d0be1f10352f091236ebbf40b8eb60ac9dc28ff3b15bbb6a49adb8e0649f13b26d0fece4e55764f4d76bcee4404cb02ca85d5bc8308
261	1	260	\\x747287abc72976412536140a84b2a46c23e4f15ae044d4116aa4c29ff3447311b265bbf3cf607ec9dbb14d413a7e5a0dbfd521e940e9b53cfcb3ab3f1a9c5e03
262	1	386	\\x81beb1d3c05c152f237ea53bc4a5e01e58fad19eaa6f1d408da1c40b393fc7c074520bfbc582cf2d3837876c60f94a956b64a3c986a8b0385cff112240e6ab0c
263	1	317	\\x84aee4a1e9eea209b1a228915a281d0f0761593d70a2a8029fb4e1640f864ad6d5ee380e2c33eb151a5bdb08f42c8284a3288a4da3bafaef012b3066f36d7005
264	1	268	\\x314fa76debb0c4cf1e26134f8334c45b63fbbc61fc445d4ef2df252d85a5a6367f418cfcf2074bc51ecb13ee6f9637079f74ce1dcde9d9da041277f79df5900f
265	1	20	\\x00f4287f7a93ecbc39039a23c458ad161290b7cde9efd6e2966028ae26dad50ecf1a5a350e44baa118bcb82e3b816f8055648b32125423632c184d484197f10c
266	1	250	\\x71ab77f363bfc026d8c8cd7bfc39df65c48139cddf8ffd0b36481c8e61c8f93aff0369b73feab5f7a2a3ddc1f95bf2535d2cf2f96da60c66d5e52398b1917408
267	1	213	\\xa92ac0701ebe4e300226504a8f410d9ebe52d27aea798612ed68cfec4e6def8dbaa7f80c6d18816a597f0f63482565839f6594a99fedeb2bcc2bb83ffefe5d06
268	1	136	\\x75cb8929bdf594b06ca68167379f9274e18d4a652783726b3fd662d9d2ad416251e210748d1f32581abd1a1877632e13839d654cf7385893a2047f10ba520e08
269	1	200	\\x4dfb0515f9102d02680524d9fef72645b1158bc0da51293c93f786be1262906ad0f25250545d5bad3d92d0e3228cdd9b815f7cc46d8b3b79456746a426ed950b
270	1	403	\\x16cc59cf9c3ec4df5d80c87dd66f5c31a88e08bc0082046a9793a292cd4ae7df050b8663891274660fc103952ed2f2f040f3619a9b3deabcc37c9f3f326e7403
271	1	160	\\x155bf9a04a6eeff5a893f690a6b7624ecfd622eea7ab308ce7a2241021c479cd113ae64ed57bac6995faf604ace3cd6bf3adafdf5f78accc25dea6b5ee3a0600
272	1	36	\\x30e41a9a7214b8a8fbb292fcb042df9a9f79814c367605268161ba262b96a8bda8b7314c29f72050a08d1b4ff0c1cee3b1b619bbcf9f61f6baf94012d7882505
273	1	63	\\x0cec8ae536d70dc8d173dbccdfba4390d765027359e76ee9a4a51ff150e091bbc25ac481b28bf95e11693dbf2356cffa62d6790783931aa2475fcc94369c7102
274	1	345	\\xdcaf72fe861b356982919449df0ba81acdb65768b19e3378c73a8e4c2922ff74b12f7d270202a9118b6391388e060d9c73ba2d5c8bdfd7a642775f8a81207609
275	1	174	\\x153db93f4191536f9c031a1f3817d6107550c7ced224cc077bf2d80799fd7ad931739bc20c085cac64e715c298400724f82850c89888ad09c57af440818b100e
276	1	147	\\x7a8976894e6766b859a985281c8d3757f36022dba3bb172226960359e322f8516394c4bd3a419007a4a0c21b153a3a1123c421c6bacb0a656df7f5334f214b02
277	1	115	\\x854888db53692c54a1430c53182c643f1708b02c015d7bb918db96b740fcc086f4c015be01549244a60441476f9c38d3d923adf3031c8add6163de3ebbb20703
278	1	295	\\x4515740c15a335adede939f7f70e03bedb5b97943bf7a3b4c31c408e2f911800451ab637a169587140cf7eb0112151581d6a42b5ff4fed33bde51f3527096809
279	1	83	\\x46f9f13538ca5c6d0decfa212c76bb81bda8c090f2d3927d5c299078b05b2f36e6487cf015d006cd148249fe9fd3e075a8a8e816aa046aca9e870a53150df402
280	1	270	\\x3b5d042d7c54724ae4b098b2587479ed4e0c13586ce3ab427b3cf0f5a475e2edd9a65b1d75737dc888f0e82b8c348f791b9b9a72f166f2fdeb803cf2932d5406
281	1	75	\\x9dc77465b3b8f9d8a5d35f0d1ba6ae4e3793990e9d5bddefcb9d1d6f6ee73956f59d71a508f77e0ce3ad46f85c0712e523008874eba4845528e309b99ca14c06
282	1	177	\\x75b89ef9e680db09868a17bc2939e97683f700364368d75f5af0e171b271d88d58c785b5ff2fe1384cd531684cab129e1a24fa116a993c84cc50d0a3b5a0a702
283	1	198	\\x290eb73f8663a658b463ba29afa208d8cdfe7d9ef6ef29186cd0c71cabcb4e8e52077fbc113ea37ffd09cbeca5cf4c475964af4c774a38b0519bcf6ba2c70d04
284	1	153	\\x22c4d1d94aaf6ff0f5f4506aeb098163cf725c79c9a9db9615fdd3bff7f71746af533dcce7a3cfd85e2fed4d8931a1bc6ffdf641d028c893811d42438eb7ea07
285	1	57	\\x5419d5a3a65980ad8ab0bafb277c12a56284c3ea898ef15d57b7d2f32c0a9a65a795d195ba7174ff8316ad94f5069e160b22dd67822c1d8e62046e91353d5e09
286	1	256	\\x7e927b517123725d8aeeb236e70fd5cf76a338e32bb6734b702be25b688119348c5c0677ce23ab134f187e14f35f82f5afc3fbbec783e7b8c72c217e791f4b09
287	1	292	\\x5ee70777147719114cbe2b5992fd90077c652e93b4b538ce29662946aed7cc6253cabbe8970f02ed61dbb79a55b41f03c1dc7fbf06417732193d637a96922e03
288	1	309	\\x0f355ed2fc93aa99171b213bb591d0c5650758cbcb18817772945e6603828d2e0913bdbf39dc53cde23b331c6a6ff131d66899ab58a42c7adb0bdd8973cf1304
289	1	399	\\xa0357238bd5c0988e6f4c9cc91c07207e50f72c4c5f833b54c5a3fdd26939af28527b253132be6541cb398a5e7bc8267dc94f7ea5083a3f6bd6f34015ecd2801
290	1	335	\\xdc6275ce95b6fd023f4b31051194e1200a55e0b7efb0cddfde113d88f1d2a644c2adf341219fd35951a1090417327b2f3234e96265807b97e85397a1d44c3a0d
291	1	105	\\xaa284998bf5df044c29a0f57e779040e8026fb9ee7480f396b274e27644522ff6dcee5deb10ecc6fc5f0542e774c428b86fa45746dd03fb7614f7d1bac3d9b04
292	1	156	\\x42fae034e36c11fc2ac31de36bb7c76e3f115bfd381f55ddcddded83ea92449c17248ff15d865cec3729a5c89a9b940627e1e77dc2d6dc4ebb8d8a717fd7f100
293	1	225	\\x23de95d8a2610ad567c0f10585531fa242af23beb09750e50e4b4773aadff7ca234b52ea6841f48b1f9fd66533257c9dc3aa6c46b718f29dc2eb769d58c37c04
294	1	396	\\x6b710a99f1565f3f5fe4bece1c8f37f6f7b837180a25600ad2da2e1943788e0535ab6feb07f072d1396021a64685cc9a67d6efd3a3898efa7e13ab1ac10e730f
295	1	389	\\xeaccfb2cf94f07edffbed9cc839b1d9bed79e838b0638ff33e6fdd12b4234d906acd909a58f3f4de3fdeab55cb0167e6c961777b8ae27be9f096e5fee22f4f0e
296	1	207	\\x86dedccc835f000bb05f62a5ca211f06c5a154d944d5b753b64cee26feeb99e51c9662bbd063befa2889f4026bf2420b00cb8624263ac889a6eede8574654401
297	1	353	\\xc427006ad311ee7a144419035183d63a1cbe76479c97ffc2937f41ba60c719fec2960d917bff5dbd5b23a68d123568b340d7c144e00459655f151173222b8b03
298	1	352	\\xa3368e5b3317bd89cdcc91471286530fcb21015a01ae74c4be38999bf8224ee3ae2b4a0b86356822bd477bf838869ec0d9069f211af5de23caac97cd2f9b4d09
299	1	4	\\xac1aaeb9b0d47d51a4d86caca7dc8e93ffeb751700f577085ab52284cd8835cd576267c9177e29b1975aac293f3ffd1456368984d996eea450afe29a3549ea07
300	1	392	\\x745d368c0cb6dc43b2ea577d2841a1f7ab08743b055554e7b3ead70b404763008055661f8216878f5d5ba1286628750415f33c15ef652293d0ba9cbef3a6ff08
301	1	19	\\x8aecc7de5d1dc9aa14bf89a0c77e416eebafac40601fc7fd616d232be2e7a6a3f585b6fc5a31c11ee75b60ad2afd5436ccd48ce141f414fcd93628a615c31206
302	1	245	\\x05ef47e98d8818b9f5361257f789be8ebe5f3b9fd823282a8ce75408cb6536d6a70101cc676a48b79b31b49ba28ce2e1a23e142d41c11aaf335b98d4697a8b0d
303	1	141	\\xb945774f52a612e073f9d92316d4ff30adb74250a29720dc50495c1ff3d7790ca9900663b8ebb2348046ccae6e8c017da0b8c0015a89cc1aa4d678d7cec7500e
304	1	68	\\x528653051802f7d77ecefd264ee2f8b67c5836727218dd1113d4d956d7ee365b7d578c4eb1f7b2342f7ef337383f854b5c16c75bf14b4e695674c613807df60c
305	1	240	\\x823b96adf60dc4bee4aac8d2a529f4112d048701da94ed2f7920d46f161d010465d6f382715103510edc37a0e96d900d2e655a48a5b539cf6718fae9fa3b1407
306	1	128	\\x6d9a9aba8aa3fe65fef85a8b3abb06348da8ecb19dd862914a222a25a48093f7ad861100114dd255a0a4204d7d33d83e237b0a4edb0460b96a8e6c612726950e
307	1	280	\\x8f58c3fed51605a7e9cf087002c8fcb051a7fb78ae6467138ed61033d5a475d08a3920ba376395a34d60a7854f3ae2b6652d2769ee81ce9bbb07c74070141b05
308	1	267	\\x95138f81422189c71cb4f5df65fd4c474f46002b20f6e4bb058d25703e65da015d4328626b2f53275d3f2c53c2c5cce522813572ef443c5c3b5176f4b8401909
309	1	274	\\x36fe9bcd052ea8c3b3fd63f9f2484db07ce53f309532a87fe8ab3d4d220f683940dd30e859a813a42ae58bfb1b42d8138d2106e82e0dfce1ba1a0ffba6320004
310	1	38	\\xd7e11b8764990516e1639411a53bddbf02072d2965d7d77c4f719df1c606cdb87d6929c5b4cc88be47cca24d38c2b7c0664d52e6b941dcab10a8cae97d9fd30b
311	1	205	\\x90cd7ea59efe11e24ddd5490ce8d6a66bc9e0cb4caa2043e39a44582d3f3ed5c3eb1a367fdc9979af8d2dbe8342e694259adc18f392b1f131813832c462a1d05
312	1	159	\\x4f347e4f07762f7ac1bda6e0ac8690e455ddbb12da1965aec4b8dd9d477639343281ec1be2bcb11986a4a4600c1543800e34e32fccf67f2c30fc8dfa3d2ab80f
313	1	360	\\x439b0123dd2cb1fddaa4af3fbcf59097e5cfe31775c1856a63e198266498c93a5e8cca9552ac24e8010bf371eb2ed289e85d3a75d81f546dc8373634e995520f
314	1	264	\\xf1582c8c415eddc7bbd64d61d82fb353e3cfbedc77a770591b4f752c09b65078f3c74d2288f3aa76e0c126d80b2687cb430ea5af8d8fed3099e7f5ffc6c4c700
315	1	60	\\x6cf713a4f7b8828f3d4b24c9d94cbe5a4c47d8f0ebf2c83136d554fe3cb62b01aaba921a36a79915bb5c3461b3ba22ac9b4c6d10809572b46a12289f45e98a00
316	1	139	\\xcc40db24e202250bc24bd05ed15b2c11c8ff64d0df6c7e83b7f1f172b2ba66fbfcd011be83fe6f7ee2012a32b218d86e0c70b2632ef8721d386a6c53ebd58306
317	1	81	\\xd81c73db41cdbe56b9c2faeda01a7c412973aff72cff3b227acb2587fd6fc1a3987922f13ec2304a83acaae9724628136c34c6e280b4fbe9c7367cd24187580d
318	1	47	\\xaa6d233cd8271858c9fb03014e19dd2ecc30c1f3ad3ceccd6026d762001e8691ecb744f3bb03ce704d52ef9b712fc9de8aef87fe6ba18008766372b9df256f07
319	1	340	\\x51b436dab0969d89a242bdedd12b4f19e70f2c33c75ae7df02b29d0ea3b0e6c35be94da4969cc454585f040c83e4aab078538ddd2f438ad61097dd2e87581e0b
320	1	66	\\xb5611335b7eb70a74ef49d145706a784ed2eb1ad17232da351cf04ad587d419fb71fe5226335b72696454adcdbca0f6cf682278622d834e98c7bff291cc1ba0b
321	1	329	\\xe611dafdf4bf9cc8cdb207a17635d6c37a42885e7324444a9c71f946924587e090f932423aa4111f92a4ff5ff16eeef2981dfd318f4e778949a282770564130a
322	1	346	\\xf14d6920f4770233d9c29f0e3726c2048596e98bf3e945ff293a9c8b8de0c78d35eb896601a075e4d1032e3d7a76381de622f887fc56461265328b81b140a105
323	1	382	\\x9464d548d9d0d2ecd4d645fe4cfdd9d862c26f99346b8795e52312f01d3cec562600d178f088acf67947cba3f5fd309551cf959a85eb9773bb6b7de20f7d0100
324	1	154	\\xc4bfdb6f6ea3c9e3fdebd3f83db7d6c70eaff47aefd4f46cb2671c01ea8c7a57e52b5b8914ea6f69f7cd4477a592036d98218951448122e460d9dc2c858afb07
325	1	279	\\x3792159b043701e45f88d85a9f98e132ef8255c47582457facbb24be28b3eeabe750ea90df620f09361c5a0e9ea2c48286a3ef538d2b99b623a5b9284164270c
326	1	328	\\x700e00d8b5499783a93cdfc11236435e4c82c75ad6356ba6f491f459e6fb8c3644d0b55fd91ecff1c716c104781bffaf240fb7746af0d27283549371dfa28007
327	1	298	\\x2ad9a53f3dcd31ab9b4781c40d72c42d6d8d2ac70fd23431e3644c708a08d7a2617c279e8e4e5b2ad66ed3a2ba389e017c2821f5c9f438e0b0c023ca4542de05
328	1	301	\\xdebecfb65ee2b3e1492b7dc4e39b3f29a6a2846f1bcf3c13d2a1a08d93e81a9cf69980c35b6cfe0aa2fe2b55a0c6536d46db61ae5b558c8392b6c3259831d002
329	1	176	\\x66fd75f9587aba1fbdce86deaeed8d973d9886658494c8816c0bcf828bf748998dd2f4cbc91e30be99bb3fadedce1f7252cefe17a8d348afd8cb720bf651c904
330	1	118	\\xbed3e67868dee08bca20b826c7eefc624723aa0bb1d7f3d45f502e5dcbe7551b8d101a4bcdf978cb368360461e7b15bd8bd107fa944543427cc3444353020105
331	1	327	\\x006561fefa7daa976476bfe62471cdec6095f982bd2c9ae52a1af1bda2abedfe58553af1104f6f46b8242adafa820cbbea1eb5c1f3c283f90cb6795bf461a008
332	1	171	\\x3031dec48298056e9b4781af2824d5f0c46d558d5c9e99ef350e62ad8abe8cb00535b5f34fa497f720aa146d1598110c0d9b6f65d0cd1b097cc36ac02f42fc0b
333	1	26	\\xf1dbf29d997caacf89e7fb300348ebdbffcc0638d2055373c7f109e19b3fe4dedffdcb6ee14582f31150e2048747703b3cd01479dd902eec2420570eabcc6e06
334	1	132	\\xf1ac7a06fe0d64c42c7c6fa4da7db3a3c7fd78a3d50470bda778445fde406e4920876e0bb9fe644e1f608c630ca6683c453db3fd5820d6fee3e4e18fc8d51e09
335	1	395	\\x0b696366fde9b7c0227921d53f6e773262d3632d907a1cade201ec013f56933805f96d30d8ab4b743aff5e606ca391ef9a77e8bae534f0188eee2d18077b3d06
336	1	126	\\xdf3b83580f424d0423400f8d38b6b00f2e26cf3aebb5c807b1e3d1fbe5dfc84166a96448236ad50cefff5a5b127e30bc4f3acbb6c00b1a83fd2550f87c601600
337	1	144	\\xe2cedb93fa101d445eda2a1a2e7ec88177ea66c82bdc45a62b2c6408625f4f87c04ffa94801330501da2d9cfcbe3562fb55ff895a22ec5aa9433d0cb3b787803
338	1	418	\\x3b1478ff9c1d61d442e1ca5972d2715ba06643063b8512c1b4f73994b5e495c6aed5c77db054e8789aa1b603fe9ffe32fff0631eef434d53c196562aca6cb202
339	1	242	\\xa1d7216062e820a3290494b27220a59a521eae6455ebc3f2301675ab75400e17bc2f467b3ff3c73ea160df2f0c08c0fddcf356e9c98f6093102658325a23d50d
340	1	258	\\x8ea4f087aaa2767b3db480e81e0266d3ca6e0b0af53e2328c71cc7adcf875006c9b963caa7ae25b2a484dc4cd5d19733203033258b757a4ac2e44ab3476c5307
341	1	103	\\x15c3ed11d831fc8aca435f05491c6fde3310845d79166c72e0ebfdc8b76533257113013b994fb8a6449b2f475d42aa9d8a28c3f12439cd267fa3a5658e4f5c01
342	1	318	\\x9e93a99adf6264bdbf366677ec1294cf41b31ea3d4fa9e7548dd35ed87c378de21f10e3cb48bb7e329aecdd896f70f11266794c3d84f20c3769d543d3f98560a
343	1	45	\\x9bdb0db11db2e02a51d53a8f547cd58297d8e6b335e477244c646d25f1cf5247ef023c2e649ad2a1a6649dfdc67376e55dee5d2f579d6dd432e95d77b9f2a103
344	1	185	\\x3a5f18dbfe506fb41368fe79d925ad810465d85ce4bd6014e090a58be798606861715c351049d0b21a428e2b161f5c3c26a44a8fe5aa83061b66c2c4b84dfd05
345	1	173	\\x600cf51872ab8e210dbfed70d60559fe3a6af78b0daa00868226a309e0bda6572f25497925164e1c350c692010329353f51ed089e42366d62ba1c3bc33bed508
346	1	300	\\x5301ce9499ebf935540bdc04d8bd9b471541f6666af9be205181ac8a86df2e025b99ee506ed060707bdd50fa9985c507b461de609bff75676e5d1dc19c73910e
347	1	355	\\xa4c97f90957d1cc10ff7d2afc2b6c47d156aa0e8a76d6792ad0843f519bd5907211b07e5e0930cd7891bfae64ac4cc263aabe4d002c392a7fbbe50a599ced104
348	1	127	\\x7ba8d9f0fec70024d900d68f427376d7eff84b852d2abb33f6aef7e64bcd30487f15f2142c6f707bd38cefa5b9f82cf3e57aae1f0219faa22f5e33d01fc72c0f
349	1	407	\\x228ed1eb5cfb22a07b18414942152f16ee1cda8bae643d86697b3605f5c72ea5790ca73bf133e5b2f52bb45c8a75e0c8e3a9a33ed4a6be8313f07926d3806a08
350	1	155	\\x08170629d580e1344d8749fd2321fc2a3746568a32758ed416309267b5e3529408f5ca37115a54d3a026f611cd97eff2650950fa061400e5151a8355493ae506
351	1	123	\\x05d9055d4df9dc9c9fa49016324083221275598df651f36a1211542604c0feefcbbca56e97b0340a0ddc625a7c80a4c467f9e4f8735cdc122d7c8bcc07a37a0d
352	1	362	\\xed37aee1650fb06130ea6f9364bf33972a574093438c1e6fc5df1ef27291469d4a25cc403b1c3b4655fe7b505c4483af51a11fd938264fb102fa39a3ca17150a
353	1	332	\\x05140b1e39b644d68df4c2038111ee909bf5d7ca71a997093722ac09d4e2858de0003940f0436b2ca93de62f1c18e498e70faecb6a31b85f83db9938eebbfe07
354	1	32	\\xe62a2fc64e86aef2abd62fd8caee240eae25ff4e22278f201366a4ab1252368e85b5fe9351897f6c30af97722470ab2956603d2794e5c309fb1326988eed8d0f
355	1	219	\\x8a6c982950a4963a1b9990f5f42679131353227f9c89fa016e50916e2d0414483c43578e2734a81f2d7ef00fb4a36d49ef6760c7428fbc444fdc0c96c2732b0e
356	1	107	\\x59ed8731cdded7c8a7dd3f8f0359dc49235b4b7172e1412941e5f68c6f98971ac3fe2716b7dde29c646d5086237a04c48e2f0c5e78c52e7bc3ef426ddd56b60c
357	1	209	\\xe26d0ca3d11c8cda4c0c6485d8e978ef4ad06c69c96d139c6b0751ed7fbf5a9c15d0e97a501bcdd72e04a09a0ed4a71dd5963c818bcfe1eb0c8d8fd08f288e04
358	1	344	\\x7dc4d008e90815245b2a122ae03b8c65f3c9c8d93d77aa8f48c126b49c47360c62cfa876e241e2b45b6a875ca35ba4de7e129e25289e6e577eb64beb828ccb0a
359	1	325	\\xe5eb8e9c580437ef874050c2dd90f248453e9fb83e03eecfc74f44ee652deb0128cab3cb5bee1a55cd6ab4c534eb831d18a1bf17aeb3b3d3d8a8fc2fda5dcf00
360	1	28	\\x647a274509bdc230bca8fd1d19c1ac6051c6bedadc3929ec00a0b47ceb65c0d583bf4d7076ef2d7ce9c4c8310ab7eab71e8dc240122cefb0152ac2904586240b
361	1	40	\\x376a5ef1d3ab7c8ff2ba3195b52c5a9a6df8d5607f5154c0834034e4b7dce458146e305966014d237a3821a2ac6e5d48fd9a7494a894d63e9f6e2d4e48cce003
362	1	338	\\xc53c47292b0ed9dbb4509adffae1518c37bf4582cadd7677a0e503a35d0e1a061158711af6b6c51245dcea9c695cc2cc57aa62d96a25048af43593a86a2a610e
363	1	191	\\x92f6a0b4319b1caeaffe91072560c192d0c3a455a224f190a0f181cc9ee00659d7c984bb4f5647c13da359b18d687a1a54d667bded10c76c5ff4815e65c0aa01
364	1	278	\\xa3faac9856440fdd421eb15be38b6d66f3c4f3dcbb46e326e4f4b8ae4c1a4897067b6368d5e539feb2e29627535135b7ba1e74c842aeaaa4b34c8e5a3ca12007
365	1	383	\\xfadcb302ace4e856860a57c9f2df029be1fbf509209e7d745a3d3d7085e7be2b61c8afa7bdc7ba25171f9bc6bce5f6855f6c535edf4e5cf7fc7b363346c5ac07
366	1	294	\\xb324ba88ac56fea8ea6a01b3ce2ff5aa0e87362b150d168b8bd273aa56695274a91c5362b15130b0bd005e59b4de4145c8f12c6d5031e988706baa12f392090c
367	1	257	\\xa158e9bb9977ed0fc6ec6ca4507f9b1a81d2f67f0b6a6c8b98677c22f2aaa3a0cee6bc303c3b0f09b00806a7d325533eca8a18780c4a0a6c10bb42362e194e0d
368	1	31	\\x00a735b65f345abb9ce1230bb6600584da8bf5b1249f2b87e407da4afde5f761d21690af63c45150a2460b4c7950fe6feecd5e1165576cc97b38497e9b1b0f0b
369	1	406	\\x35ae5e8e4ff5135db84702483616af247dd8a728ed6eabd2fcde9e786a443f6a2b4647933679f5f18804179982236274829237a0ebefaf4758c94706d7509701
370	1	246	\\xe28ecb55db35b091b5350fff3e0a973d97079455fd028468d895ea139abdafccaaf95aad2b1f2df7ebc29a5fdcbf71db270ac8968c20edd5b4762f4fb2bfca04
371	1	183	\\xc19e9b49e869eb1a7458f95eb509c28fcda03a7ae0d7467d82367d7a8e442ba32e29b67375f84e4c1e0bde951018bd197635c03153b1ae395a42aacabf723f0f
372	1	111	\\x8e1185e10b6e6fdf7883ad77b86b2595f336aa15b704e3e8f6349b4d5f5e3b22f20f311a3a38f2302fb01a54737b66ac9041ea0b0410bacce6ba3c576b1ee30e
373	1	398	\\x8ee5e68efb7b7c971111f756fe923f84925de7f7c60a73572fa3d2e7fccef66fe8eefab3504b9975c1e2fe406fdc34e8623a818c935738330f365036b5a4d90e
374	1	12	\\x84f7188d96146fb3ee39b41d1360bd1fc7778f61bfe93861a8bdda3a320e0eb78298b0615ea1d4e92a529b09d6269f69f1a34ee8559198dc42ec00be561a560d
375	1	409	\\x9da9e0a2a7105e224a7ec37d8a359fe360b47e2d30d44cd1cf41344eaa6bbba1ecec0465ba7faf657ed7c20973ad0e1d6f58ef3c7c6d7d967157fa259459fa0a
376	1	170	\\x59831cc16084d80f8856edfaed08ebb8a7daba6c5d63d1713fb38878a6cae4a13b4257807f0acade453400aae27317985b4581105bd4a42ea46f3b72cee26b04
377	1	322	\\xc34651b0aa9cecd9e6ad6f2b2ae8653e22d44599123dbc05f3adff2d866f2a24a1b3628821d8c4bf72bf9b5bd7c66673d681466b5cbf175e49b4cc517e38ae0c
378	1	18	\\xe58b7df0e2de1f1535a2eccfe5f357e1d0195d632408b73ea5f1753bed905e35beae417c68869c877840ced487bc46828857942031f6ce0f8cbcea1b099e5103
379	1	189	\\x6f3adbdc685328187b40ac523c4c5678902b85579be32ca69e4c14f085932e86a97f39def67bb80e766ec59937bd28214c65e0ef92b1bcb3e3ed5c9959e4f100
380	1	320	\\x9dc2f35b00c3932cff7ff54759502cfa4ccec74dbb73bbcb62c3b9ae3c93f10aa1adfdc77560d8249dabb5c2cf6fde2d4cd99678bd98046409389edd925a1d05
381	1	2	\\xc3619789c441cdb461e768a309d7cecc12d50af48d27f245b6e26a9e3b2e568f1bf0209405078bbb1070bd3da0cf02141462442ecb186cedaecb061ac17fe60c
382	1	337	\\x48aaf9b4763c6fdd4a3d5908c938bef32fa12d43a1420581b5ab693206401bbdb3c89317a8f8c903955395bba3c36d7dd8bb8c36485b6608c3b1d0c8b48d5308
383	1	67	\\x53ed59df65d3c590026905165d7edf142c3cc773b65928a4692b00bc294c00e1133cc3ef0f9d5cd3b058b53314901c3ebb4c501ff76de3d1ef89bc82145e1c00
384	1	307	\\xf0e1fa9123e9fbd89964c4d3e6850fcd8fd4068fff248b7188188d95619370115a5be3f16893504f79b4fb90f9f1e90af9c35515410e898f50bae4d299d9d704
385	1	356	\\x993b67aad799c8091942c927f30f5908a3161e68ffe337b0151d7dcc719cce762057459e38fc86932f09e4ce197038706b2d3ada065774a25e0b0e069a623209
386	1	419	\\x57b7980e4c17cc98a67458afc2272d832195f26867086e4df6ba0d067ee1e38e5e7e7fa4332ff1850ff268b68ee2e5c11115b93f9e7c641b9a1f4ebf0376dd0e
387	1	305	\\x3f3ecbfdf25a8e2671325f11e755b9de518ae58e8337847111192ee35d4a19285e4ac788b4fd09d81f312765ab9ff5f71c749fc3ffe29fc88c29c45b308ead04
388	1	13	\\xff90c8dbc39c87923ce1f060460069f0faae1ee1d166b2164b680e39568c05b1f02f22ea01c7cd7dfd3545705733ad50bdcb03971e82cbf2c92dfe11370f4d09
389	1	239	\\x3dc202655a06bd35c897996a01a0f6cf709a157c45d659b062846c321bc6e732bde4086fc28d575480ca9def8f91b8c41d85ad2a20bfaed8eda5fd4c8277a00b
390	1	233	\\x8e3a2a4738d24e5193a15ef92815650b64ffc490c317c979e82d914e4e8a675af044a4edd16154490433fff6c6186e139cf97bf8a3d49f7813a6ec5368fce903
391	1	122	\\xf613884431062d363d70afa76b7a9302ad85e8ee732618629f0f55eb62f5e763b611b606a6aa92f47105d1cde5824948fe66526993cc1b8944645c09df35b70b
392	1	291	\\xc8822cbd19848ac858b939f4282e6f277ecfe6b3c7ab92839595262980f53e3e70e3214df8a8b809496160cf1aca01662e0c1c221d784e420c73ea37bb6dbf0f
393	1	359	\\x6f680a1e0a5c5ad988fa6428a4e596b96f39fc0a89f97b0576033e98cc689ba02b5d94130b3148b28a5eb34c27505c162db0d3f83cd1862f9adc1548f4322205
394	1	62	\\x4ff40fb428fcb1c33d2a79486b8d11bb9e997193f0d90f035be8a714dbdaec547d8c6a383feb948f95524175fbfe396cba997fbd8bfee09b33450464b8f0660f
395	1	72	\\xda454b6018a6702d6706fcf739bb1c78dab4b121f2e4f1e1dd0ea4e4e3ff7aa4be553491e76ed0ccaf4b880dd8376dd8afb97399e258c272af6ffd90b172f20a
396	1	143	\\xa95c3ceb57823438ac8ba97d4a178864d61981293d46b5c00cabe2d5051ad3d5400a072ad88e3286fa04ec4848caf1b61bc19a997d8e97a407da6fc437362504
397	1	80	\\xdd8694b99f0767146f3d22ffcb44efb700238fd0335e3b2b5100113605d3e764ae1b5defa27d91f4ab66a3158e9dafa1c02b2758444349aa310e2cd45ad80d09
398	1	84	\\x6daf3d1c243635a92de7f54f470a9a80d7d4bc691c4f255264146b9ac7dd46c29a05800082447c2f8362ed42d2c95c26f3de6266f522d3083a06d34eabf42707
399	1	408	\\xbd7631bbd1390c8aad88dae32b9046e6b288adab9f10fa0e959475688c0c1a722d9b288a69dba4d99208b5af827b7592147ed5758f7f7a3953f6f76d10878103
400	1	74	\\x8329609596aa3cc0086b76b1aa59f3908655064415ee2adb7fe6507baf6a9e567b63603fac6b517c7eb15eeb06a88f106ab07cd0f0d8d265e01e85abcf5f560c
401	1	377	\\xbad27d8107ee91ea41cc4f74450547fe59ae5fbcb1ef9451c8cb548a6aeb5d94fde6e88a2872c2d681fa69ef1efe81303717f68d3be256761a5e6f258b0db105
402	1	281	\\xe024b72bb8461044e3df0ebba398bfd19603a1522cd58428600a0ad589b0ff850f08cfd21bdbb1e5276769409d9424a7abb1b993199e172b92bc3418f08e480c
403	1	261	\\x935e1e735b682300a16dac067bc1b137d3c0c751584d05de9d06bcd0a85b783944d3c9dc5af95f584ab066adce53b571be2cc9956224e1ac48aed837beeb6805
404	1	197	\\x28700b0bc1792d5b39c67785097dd5ce2660e55cf7f5867b3e4762bdf2748cefb7f58be4c61d4583b69d937b92f47fd9061792531890088912ecdf85d8a45a0e
405	1	391	\\x0cd998ef71e1a240aaf8b3324a9e9510f1916dd1a16d3682c506a0094a3fc2dc2fbac87be12f8084fa9d6ea9d7c55b469d3611e62e9f87564a9e05a4f1cacd0d
406	1	394	\\x4203000a4896452484c634e2449961b9184afe346468405b8ed5a0244b1bf268b43214756c76b19e8fe66a428ceac2cac085ed9e387d5afb19131d090e974a0c
407	1	289	\\x9f0ab08a97bb51e1eafc424b0868cbec9814d0ae1e393634073f91c6cb4f23d0b66e2efe577e34187c3b357fb40d26e0215df29fe70add3153d4c8351ea6ed05
408	1	277	\\xb09c4e338f3c3effe55f0f88e01e732292272d1be4acad0e7cd821f31fb7a819e538801022a70788b7cd2354f0b01768726188124e6037a258fa57f6369d0f0c
409	1	149	\\x43e9a44bfe71a79af1288e5eb83f599bbc2f75d5c55afceba98affd1474c066e5e2ba757428a658a33b408038b5f8b01280064be86d37f1b0c4cd77f05cac70a
410	1	101	\\x03b8cea5a42cc52267954409e47487a890e6287335de150beb9b51bda9cd6d84c022a410051133fc3ea802000a5d27d1331c8d3b0a0b355369fef19a0f84f209
411	1	234	\\x0a9448d41952de168dd233fb4ee4541056a179f5ec390523a7c3701a929758c7a0357d1a7486d320cf23ae0d9cc26e9b9744469b9a57f45c3309ad8f5143ae06
412	1	236	\\x66f634ea25bf5bf62475aaa9aa267259939e62619995ecdd1ad5e584ecd3de9f4f11a548405ccb517fc337af0984bc6ccc00e80b57ae13f0331a116dbc51ee03
413	1	424	\\xcd16a143396a8a015b2719c2956813623a38da31c894ffd5b87f24c45c11b2c37052e12b253eb328a0961dc5883620f9be37bb43a3570d1e8743806b3eafbd02
414	1	52	\\x1df59b9493103a8ce27aec2fb350336b9c9a0e8b707f9f1123220662c269899a681de80dfe084f3387ed9e1cd372b57c28ebb324246e372b968cb4ec18201c01
415	1	373	\\x672af64f28171626b706bb68721350004e12b7182a207e24e1e1f6cd7e328463457016b1bb820b1dce52681b7db3683b3ce24ff6b3ab515c0956e1e4494da202
416	1	381	\\x665ecdeb8c67d7ff773d80bfbc0880099d2dd00d6e6a22731683109044f3eeae110efea67b6c6fdce804c88c9997cc5b1ec3b9db539254dfc8c59577d063c80b
417	1	369	\\x9d27db6927e74c35f135de93112a60d490344299276c5ece9914741f334f81af3934e0ee4494a3c811126b04e61635c2af6fe2d806756b941f013a03f6aaf102
418	1	201	\\x967e44adb7971aaf786538bb1529b00ddfc12fa5cbd68440394eb0d4152bc9c666cf5618a50bc721f3ce39797f8518ff7597aff49b03ce1b67173251aeb5e50c
419	1	220	\\x2f130fecc1073fdffac85d0769c1601c72449e1f803afcfe688a966bf760ed5c0b1cfcb42bf496730321eebfe02f80a5cce076b6129f7625745c2909e8128803
420	1	116	\\x6a5d2520535f8c80667107f4b084df3a42122d619d7bff6dd4ebe21ada707f912566072c4ab2f6cfd4a6f1a49ed0cf1f9c22fd39213a305e5fce8ba5fa798e09
421	1	43	\\x5d44dde530aa707e373118be3cc481d89f2bc59175be7758c59feedfe7f097e162cbbb79a98a72e8ecf7d668426f2160030802db518064e258cdf4139b943005
422	1	401	\\x874e1a2eac66d3a8b47f51f7a9238bd7adae715c62cab5df7fd2b24fb516db3e969fe1ac40e73d910f84fc727e763ebe907a75b2d5420d10ebc9dc7338fdfa0a
423	1	14	\\x4a96f39bdaf962eac3067fbd11d35d4ee206d8dcb6459e2e56e7d08df4f41642e6730f6a76487088017df7fe7ceee74869059bfc7423f29672a9ac5e962e5a08
424	1	339	\\x84aa7f62453e33d0677883ba3620ee5b0dc33ce7e4848f88afd070d412f3bccb5d1a986c9b7cf4ec16a455fb59b4224ce8631dc5a96ae8f17f73398b00de7c07
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
\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	1655064940000000	1662322540000000	1664741740000000	\\x7b26ca8028c88ef1e347d0991a892e0ee425f93fc78cfe6fd3d838e0f4e0b8af	\\xf708b2fddc2efd29adb3af034c3713f715eaa4599bcf017cf59b93cb22140ab9b849b88345cd647253c9d583cff8e9b465dff651aa1ac97b1c4e0ca16a20ae0d
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	http://localhost:8081/
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

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_recoup_serial_id, last_recoup_refresh_serial_id, last_purse_deposits_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_recoup_serial_id, last_reserve_close_serial_id, last_purse_merges_serial_id, last_account_merges_serial_id, last_history_requests_serial_id, last_close_requests_serial_id) FROM stdin;
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
1	\\xe88ad1f8732665f8d873b5888c0ed44ff3e63b6efcc395f5546635a854ccd8c5	TESTKUDOS Auditor	http://localhost:8083/	t	1655064946000000
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
1	pbkdf2_sha256$260000$nlnS1Lzl0i6KXG6TKyiIL2$IS2QB+vbGW0vcpk28Utu/JUYRKZKA7Lzv3egf+0mHp4=	\N	f	Bank				f	t	2022-06-12 22:15:41.274348+02
3	pbkdf2_sha256$260000$X0z5nKcEUjXjYfcDw0sjRH$RD+nEvLWH5HdE/+ZHleAV+q+dpUq83hVc6RekiNlGO8=	\N	f	blog				f	t	2022-06-12 22:15:41.464536+02
4	pbkdf2_sha256$260000$B5Xy5XH6ARmKpGxOPplE02$xqLuuPkxdNvWhO4D12T+MARfGKlptAcH/zln83eIxFY=	\N	f	Tor				f	t	2022-06-12 22:15:41.55678+02
5	pbkdf2_sha256$260000$1S8xw59761vN5aphJRinxk$pDi6yLv4T5EfelEuCw6s9KSlA5N0EsXwqDKAqthLvWA=	\N	f	GNUnet				f	t	2022-06-12 22:15:41.650218+02
6	pbkdf2_sha256$260000$XnU8rss0BmQ3wBngaeXUgJ$7z7d0qed1qOgTTzY4f6lDnqg3XBzKv3Q8LNGi1iYmOE=	\N	f	Taler				f	t	2022-06-12 22:15:41.743556+02
7	pbkdf2_sha256$260000$wYHOssLattOsd0gnt738ev$unnm0QzvaD1crkL1OLpfIkNn8D1saNqQUcTiIvgHO3U=	\N	f	FSF				f	t	2022-06-12 22:15:41.837023+02
8	pbkdf2_sha256$260000$2dUkZx9oeh1K1CUDrp4QWd$t3sWuUcB0wRw80e+2+WB9CfXOtoVSiGQk2fKmnHrw+E=	\N	f	Tutorial				f	t	2022-06-12 22:15:41.932048+02
9	pbkdf2_sha256$260000$zSsHSklAKqDFvRwRgg6Vaq$dOApsT3I6I6sVJYwG4dg/u3CkmaRNp7boXDSgz2VVlw=	\N	f	Survey				f	t	2022-06-12 22:15:42.025767+02
10	pbkdf2_sha256$260000$ZMH2oLkAlTQF6yaa1YttLn$bbJQZyowEWDkDhxybO9zZwdMH5uJzd7IGaYz0GijxtY=	\N	f	42				f	t	2022-06-12 22:15:42.482013+02
11	pbkdf2_sha256$260000$F9qW6kWD5hcFeYSvALGihm$WQjpNXYeqPISjWbkQYcOAis0VjjZQt9/dagVIWcnK9k=	\N	f	43				f	t	2022-06-12 22:15:42.945806+02
2	pbkdf2_sha256$260000$9TGsVEPKAfCnYpzP5StKN9$wsLS4+Tbh73MSwKLim7Akm3JSbLovTOFyCxjlP8AzUQ=	\N	f	Exchange				f	t	2022-06-12 22:15:41.369597+02
12	pbkdf2_sha256$260000$jRREFhy38e8XDzK170FjsD$6vApMf2rnrxx7/o9m2paxkIn/WQg6XuqF8CPZ62fW40=	\N	f	testuser-2diiewvf				f	t	2022-06-12 22:15:49.457109+02
13	pbkdf2_sha256$260000$OIZyck4UxrBkOu0XtPznoi$Zdhf8HJgkY3OqLtgXJPVPe87+H064naWkb/Mx6Dfzn0=	\N	f	testuser-viok1pqt				f	t	2022-06-12 22:16:00.017645+02
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
-- Data for Name: close_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.close_requests_default (close_request_serial_id, reserve_pub, close_timestamp, reserve_sig, close_val, close_frac) FROM stdin;
\.


--
-- Data for Name: contracts_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contracts_default (contract_serial_id, purse_pub, pub_ckey, contract_sig, e_contract, purse_expiration) FROM stdin;
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
1	\\x01ccdbdc52c5f9c357ae7fb28e8ef0b8523e7c9d3554b72fb34e2b40acfb963792acf23583b726db79c85334241bf53838466eda6182a9bf542cee7605ce0790	1	0	\\x000000010000000000800003c258d4b04f0586d027c37b04669d97f78f19a4f19335333699b7c75fcce394039217a7936f1c267891c5a16d663fb78f823d8c3c182140bdc11ed489682da0cf55040974a4f70afa8a8ce52d02684552fce43729d64cea751c0360b404138ad25b82e6a20d0d3bb63be95338828174f0cdeaddadad867163b5704481728170e9010001	\\x6721bc898b29154cc1116799a50a1250f9f20f259992153b4c5e90c3cb72153d5a6448f067a2b76df5494cadad4dc659e0462ce9a8537ae81d0f3d15dae6750a	1679244940000000	1679849740000000	1742921740000000	1837529740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
2	\\x0404fbe28e2668772df3853c2dfdf781302e576fd38dd5b3f8622b576de7a1f014dd1c05b89de1aa2b7f667dc8f2460488a1090bdee47d5086438027f0b1e4ab	1	0	\\x000000010000000000800003b278bf55c49fa02da0d8d2fcf6e560ec8dfbb3f3975059853a9c551870e8227b9ef0273955aead8d11ea7ce43e5f66590de4110855dd78a1867018648573e15856ae647a33a2239dd7579744b48593fbd3ef36971c8fff486e6736548119bd275634c52bfe3fa003969c5bbeccea9db9f716ec60ca65476c71483f0aba2977bd010001	\\xc08552ddb0b85aea33d3fc1be4825d389c5676bd55b26d8132b97fd96494e558e2ca59b9b553055552655948347c62d1dadc566565f8e4aa5a4c78c66ab01e03	1658087440000000	1658692240000000	1721764240000000	1816372240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x08cc38955141d81073cde58cfcf1043e679a9d69d7d78b63b4e39ded63e6a3b756d41f9bc29eea054a7bbf8bd4bf68602637bc90cffd78add763e0d8aebe7aab	1	0	\\x0000000100000000008000039e91e0e59ab306408b82561ba6e9a7ef22376e6cfeb48b096f6f5507b84344a5adeeb2cf0cb167a7e4291e3f788758389590c2e0727e68b9b5810a31886410e120b2a237e6e30776581184a0baa873b3a11c51f060b204d52843f60c140c31ecfbddbbf8f99e38fe5c19a464632a0129121a3169cf2a2a04f653a43213e30311010001	\\x03cda123cbc617d7c6b60b8c9c195a17dc2f61c8b89b31ae176a03782013ba911bf398584cdf5c8cb77e26d47f68d0477bf8b264e8db6264822b0500e4c2e205	1685894440000000	1686499240000000	1749571240000000	1844179240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x0990ceccf05bd359765d2b95d46290c201ff4e7aef46dd53b22851af7a7141bccd1e9fe773be306ecffcfe6e3a4f53efda038e1046fad8ed3449f052d32825e3	1	0	\\x000000010000000000800003e17c95ff99afd6641d4bb786958a27f107d02c59dbcf4e72ac095c63db651cc21cd34c588c8972bdf421e84f4320d9e3457fcdc2e7c845c7d88922457b8dc79c0f08284690dfb38ca270c4d8bbb2e68f6d1675a176e37a4517720488152124f5b854ea31d5b260e9b19d5e3089f23ceeb54750e7f01c6f80936a027c0052248b010001	\\x621a951b12a5b8d793485f4aea7580aee2d4be35eb51b9dae7f5eb5f87a096f9c2d7062a5ca40c7568390dca07a93ec2912b35fe37db75352b1b963958351706	1664132440000000	1664737240000000	1727809240000000	1822417240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
5	\\x0c80099eb6e80c5c092ea57666ab28d9fd031efb545243673e0c4a629dd225963a484be5c4ff655fa8f6b1acd612365167201ebb0f9de8a772f52c36216feb6e	1	0	\\x000000010000000000800003d1eff924bcfe3492e20e0a706c9d0692b331260dc518d8bbc394781c9abcb0342ee5489fe1c4a5e395e838e6625072852f9cc66b20eacfb177956b5565ed3a5225d05f9fc9d5b54610bb9e8acadd1a80e695eaa37c3ccbb15911ac95412d2ab02074658518a3f128ad1ffbe6e9041198f0e0eff196af542f747309c74603e27f010001	\\x94670f0639b480f74869e1710ffe3e2ca29d03ad06b3aa5a326f01c1952d885c3580a19630764b4de3c632174a261225683a17fa23bdfd5c47810eb8c691ee09	1682267440000000	1682872240000000	1745944240000000	1840552240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
6	\\x1180304d242806602dec51cbd891e94f856bd440956b2583370235a0fcdbd35df8d28808ddf16f69aabbce844085354688f5ebc2cfab1e610432c500511209d3	1	0	\\x000000010000000000800003ce13fc77275be0f80c7502507a6a25265f4aaf631cea23beb6fb7690e6def0ccfd58dac94e37ed052ec36501ea75305d8a6d3332fca2fe7ac88178a6d6177871c86061dcbd4e7a731a1fef854d95a7ee45936be6740ebdd7f7d0ee6fb52e477cb3ec7cdbf9acb97c6a7a736ac0c6907be4f6d2f7a27fe152711a3dc0cac0202f010001	\\x916771423ea4c7481416dcc6e96cd950ebb88ac0498e88c549aeac7f7720b41d39e1e7e6190f284680d8b6eda732a7b235b17dc553aa6ca2fb36e11f5b572809	1684685440000000	1685290240000000	1748362240000000	1842970240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x128060ca3c1e1caa9f8d12c5cc0be1e2ade7efc64fe8fe7f7bf0d781d4442119d3f5841d2da067458d834f73d7812ef937849602fef390252d368e469ea2a38b	1	0	\\x000000010000000000800003e98573aa46d04d42980593bbcc948f9d2fdcd302f958efa12b70ab1264c645d204f495cca2ce8479c7073c30a80dc08eee6399c8e90c1ee1d582c279f79491c93a11cd60bc7b9f5505bca81d7516e5ef7f049bc4dec432b21e39d82e64d6a21b847a08b43eb178bf4cff246e245c98402dc7db5d13a0211e82a41861567fb3a5010001	\\xdd21ceb625463c42118b71a4c6bda190807dab5971a312befb1af990feafa0af8e353a7451a8982e9f8f60972c48ebcdfa714b82d3041772e6597a2336461507	1682871940000000	1683476740000000	1746548740000000	1841156740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x186c0f31c7442ed654e18ad231e611a2474a49bc3f5cf62fdd8946e1e8da48dd8222f1b2f53f6f58fec0e062080452fc59e357cee0e61a6d1449a3027980f35c	1	0	\\x000000010000000000800003c29848bd39fe7c242d95cd8e2dee29d8c3e89cb8e90bc537335cca7e12ca7010342a7929e83ce98a3f6d5f42b6bc03c775ac4c5e57174d88a57cf3da8dcaab4baa77b46b02f0368652b72b6123fe43edcaedcf72aa360dbaec73d8d5d422054745be9941e2c33f244871b3abc1f0177e6ee881145e9c66543505927b6be90de7010001	\\x749b7ae199b0fa1d6da3eb46be90cd5e666ae8ab46445f5d4d6ecd440a8300ee63af986628124f8c0ab5d0d54f4805298e9d18f25e2c6482ec2ba063db566107	1668968440000000	1669573240000000	1732645240000000	1827253240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x19549a240be39f98ef6c7d1f176cbd08b554bfd695074403574cfcc934eaa4c8ea1d99954494ca716a6f75a444e73ffb846ebc7c02dabd2399594a12bf395693	1	0	\\x000000010000000000800003cf91cab40d0f273dbfd6a3ac04465a953335bf96ec9598faeef18a7f920368a4dcae24003be8b07279755d852324212f116b6c7a87ba4d959a4e44a1ed86a2786b712481c9e3b15a49ced4c5fd99e70a9ebe38f98c075344dc2c0030ec6276e0dde5817298f9175971e8ce6bc1094f960f210b6f461fc150043291368cbfce11010001	\\xa79b2c78eb29299719fdb5637e6da2fdc58c8241624e7ada345f48e16d814c67aa0f5618e2179fc659382e32c26d281b67c06df4e7fba0be87a1597432fe1e0d	1679244940000000	1679849740000000	1742921740000000	1837529740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x1a7873a97c7a0c243e1960afe0ac3f7df92f5143d1c6a74485987c48496c4c359283e6282f8405634c962bcefc047b8a5febc6e7fe154a959268e55e3e43f9cd	1	0	\\x000000010000000000800003b5eabd05e831a93129f17f259ceeff32e966d496df9862b0036413820fa871ae99d342e670fe35bc4bd665240c8fa6f990c2ed2f496cc02b40999fd2f08d7e73bf659c563e87dc432ad62441a40e10ecbf42b5d1368cdfcefa7b842e34d8359b96f23a494da4c0b865cf62172ce6a2312ec365c3722e115878a5cd91d30a7583010001	\\x5a09486d7be34027793d5ffce859f06abd95c266f84c36968b99edd7fd1c8e10759a4465abd3e45c95db497c893aab1331dd0ea83a07604cb8caaa41a11f9e09	1686498940000000	1687103740000000	1750175740000000	1844783740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x22083999b465b6dad3f66ac6f6c0a7df85421e61ba6d52f263ef387ae290d02d2ca6c8cd6ed58ace546fdfb09e397c628723cab96e0a657434c29638d3da8b74	1	0	\\x000000010000000000800003e12a9d7624733ddfb6ca679c1ffa7814df31d61ad1ba1fa46bee1583764342faff9d68751b056bd3238c88608479ecd72aa466d02f7ec0cf4a7fcd42afea4e5a69e05e76aaa8987f17d10a2ebe4b868aab92baf0bd812923f9163c78f9509cb1b33a88c1d89f55a5efef4cbb172fa3ae3674dc3aa724e229ca027da802104811010001	\\x6803a102cf2ad66266f18df893f7f2a56fa9a491263b250a8fd0682583246f0020e524d01fb97243b118fc74de9de27d8e407a8b678c80612c12e7b0b8933608	1671386440000000	1671991240000000	1735063240000000	1829671240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
12	\\x233c22eadbfba8c084f405b85e25d0a8be151d727a06bcba5508b60ffc29caa4671df64f1572534c6275a98c91d657fe2280c8d629e4b264067d783a44023e6d	1	0	\\x000000010000000000800003c1df9826a0cf53da26b8832c224f7c48b32b5b6f9c22bbdcb9bea0148acd121acb88af02c282f42aa9521bdea945c6666a03a5998868f519cc60366aed119214cf5f1ac90b7faac5a83b329ce1ef65bf838638897f1b0fcb7ce8e30151f128eb8e963839278f230144a16e97b259ab08599d96f9d18cc50d7bb22b213ba84429010001	\\x94d5853b5d099d8bc522dbd4b67334dd79e96a5025508f83c93af821ccd7fb83f687caac562bdb83f3e5d8f88e809ed131578e8eae1328c192e8d006fee20609	1658691940000000	1659296740000000	1722368740000000	1816976740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x281083418d67ca8f35d386b439b2e1e065f43ba995b040311d803f82e00576187365429eb730f702634ed3fb89a5f0614ffc2e48d5ec416fb4fe997d6da2a0d5	1	0	\\x000000010000000000800003eb0ee345250f0b967eefb254c9e4fb9bc73ab332d87cbb001dd43c92e4a58b7b37e426e601c1efd445c678dfdd27fd5838f361823ad16e4778d520ed3d827602324eaa404f877ad25953a5f2441393eaf0675470b66cef717e10d7e57f32515b3c2e8a1e9b5e71cecddec735880c03afab5ef8fd6c65104ebe33f6c99351b063010001	\\xc16285fe0bdc8f2b83ae0603b1a32365287b5259dd1b05a8f379dcfa3367f98f9c56c65a9869c635a6582c74288c997cad5e86d2e1225406474ee060756b730c	1657482940000000	1658087740000000	1721159740000000	1815767740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
14	\\x2d4c60948cba25837b1a2d77b788bdd59548fa910c2bcf2ff0feb93d118da142bb24312ecaf73a2ec5c99a0a61e6663c2f3de7ff2e3e73a27cd211c07b055280	1	0	\\x000000010000000000800003ce1beb844fd0c12fca5bfb3eda07d11f26d9cb43590cfbdc6917f4932aa2964c0d3ec25c0596988e85446c5f7aa253ae7f5e336fe6334309e7e3fa175f7faf1df10556b0b3967d6b6210e662cdfb8e644414a955938cc46c905c0adef9a2220721af5adc28226a96befa50760d48b1c3583096af5f53a15e3292ee6296100861010001	\\xa6693ec9b8243525563c4962afb6af8cd68d827553210b5ddbfa2c8e045a1f0b2d6b143e9e24edf53084e82ec1b739774171c23a6c320bf9a387ee88b4e4be02	1655064940000000	1655669740000000	1718741740000000	1813349740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x2d3c8cca0f57b41bfb3e195defb6418dfc6759b721fee447ca0e0290901460a6afacdd76fd09ed2d9e94dc0d3155602a4b964ca80a95a80c13dee362ff309a0e	1	0	\\x000000010000000000800003f2493e5f9d13b6827c8f7b7511df425caa931cd9746548e07bda8bf11b16f965f47e4eb89cdf279c0f450d064eeb396c0397d50b1bdcaf63c896fef650e419692762389a512f08fd3446b2aea671678d0985eeb8a8077535efcee8ba34830737c3e3da9644332c8464919719edae7c292b6607a9d5c644bcb93f195731458c01010001	\\xdeab524034c7044f701c12c9a6d4619bfe77e2939bc1fdf69ffb483e1752aa343f19241376a843a337c17d83e4ce2dbf128b316776d8046af60e5e8df416fa03	1669572940000000	1670177740000000	1733249740000000	1827857740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
16	\\x2e0c9f2e05668be41edff4ca16b34af43ddeabf3ef21cb30ef1c5a5d38dbd36bee71ae5623e306f6b15fa820964021eee677671390b4b1c8d80a6ab4754d30e1	1	0	\\x000000010000000000800003c3d87abac2cca946609ddaa1f0b080206665b3c32e209dcd699994e145fcede5c859e650a373f05a28dcf8009f8d17a6a1deeb829d6238bec18fc7f5133da6a1ec91b187d21e6b017d81b13b62a67aa9445179f0306544465efed591b8773ceb395129edc0d9fd7e755e5ad4b94c9e9ea0afe23b97cd6226bcfbd8ccbed1a55b010001	\\xb11e594a030e8a1c849bd8061b396b8353a56eba38113172add8f3f870598efeeee9a1a14da7fde8ef625166fb513c43bd06f5fc73cfaeb798f15cfce3590e0c	1686498940000000	1687103740000000	1750175740000000	1844783740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x3290c962c97d8733b13b7b3db7044f7e783e711e7d2b9aa04f2b62b1ce10d6eea0d0584c9b6179812b4974725ce19be796a483983fbef5889e8a906de76d5136	1	0	\\x000000010000000000800003da6bbc689add61eb97994dd4088a6e86414be12def5fdfd58e261b748f3d9bf63ce6c49d3dc6d47febf2ee4d7bd664709f23b9a56149e72c0a0953e0821ebffb1d4dcc370de9d46c0cbc2127014eeca91c4d76cbe181944d0f97232df1d49d77526b363fce830d31f44eff928546c59d29fed914a3b4d892c1093af5bfc889e9010001	\\x676814f25227f2a1100d6dae059d1f8ed14b37546092e594efe9568dfc3f209d927f406bda56bec875b9fc630209fb819e69e1f4ef101f01b6c7654a68da9d08	1677431440000000	1678036240000000	1741108240000000	1835716240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
18	\\x330cb9a695d86d62ede8560e3896d034d2023e81ad82f49f8cb608efca7fb1858e88d2e035ea988dbadf5cd062d98e9edb2f8da93452e6855ad8e8d4dc8a54b4	1	0	\\x000000010000000000800003b9687d598ba61d18e139720fc299a03fa33de234f8aeca0d33135e02f61b1f90e81afb494d502923807e98257aae316302e4df7a11a02f63eae02f8ca49f40840a1e919db1cf825f3a97cb34c64967ce44083e141a931617e75ccbf94a40ed9098e3efc3f3c07c307136b3a7a193394914cff0ce3d22240bcf1b3b829c3f3fad010001	\\x10fc7a240e24d161d96e2af0044818dc4198e0bd315fba36d994430c29ddf5c03156156187b5f1c9387aef0bbb3346122e18f43ae1fb00bae7f7a8d6b5ca7f00	1658087440000000	1658692240000000	1721764240000000	1816372240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x36b4d3e288848cdd19c1711a39e873a9b80c84115b9404449c4d7d6bfba0121a3a0d532800a16a434b409f3440bdbe928be1050c15e589ca03a6c89bc6d99ef3	1	0	\\x000000010000000000800003b777b19147fbf6b616658ab437a0fbf91fd8c48529430df55965c808990712f64bf7b958db9e719dc9eafdbfe0e11a3d2144ec20fe42277996e281543fd3a4cde347f357b6aa82582a6bd304d8dd993133d1f11f48000b4e6a5f99e496c5e01cec7c78bd3ef55a93116d6f7b51f4b1dcc540b4e2282c582f6bbe29db6721f92b010001	\\x1d575787d3f04b808247447f2a2ba2eec4a887b69cf4af9ca59a12cfc0ccc7d48cd899346c84a9959193ca12815ed22532e42a96501e5e1419b1760c1fcfe701	1664132440000000	1664737240000000	1727809240000000	1822417240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x3a74b63235b34c7ecf64f13df16a87d2f3ff622da9268d0e1722c134bb46f894a306ff631b51a7c59073a0bafee4263fb5efe11c9802e6e311b74cadcf49327e	1	0	\\x000000010000000000800003bc1ff16ed50f7c1cef8920c6bd33e235a61a292c0a3df976f3f76c76d5b7cf784c0e3b4b1fb12d76bfb692280e39b6697a6cf0dafca2977701717d967342289ceee7004e822161a9e7a4b418764226854e9667f7d4915c2d674630f3c935f1e2615001a316ac6e7e95e2fa9435b38b1e505e9c4f26930ac0a2b5d0dce68a7675010001	\\x7a777800c46ee6a87ff307ecf40cda0f298e5e1d9d0a5fe66869cde242e2a8ad37eacbe1e088ff844ffe958cbdb7ef3615d84876c488f7de3537914592af8b0e	1666550440000000	1667155240000000	1730227240000000	1824835240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
21	\\x3b682abfa03758fb70a12de4eabf59a059b54c44d01496a55cc07c47e942df44d302e952d85a4a47384f42b782c963bafc71803bcd5c8a90fe624dd2f8c4cd87	1	0	\\x0000000100000000008000039dc1d6a157afd2250849527dde74956a61a6a5d1d491f3851ba6d91abfc4628758392c1090ca10646adbba16770fbfbfa6c1f37459817fb396621fa0016a4be0238a60a682cb180c7fc3634174549e70c4f59cdda519420efa07cb183117fc8793a79df163da004ae0200934977d91e1234172a658af3b22fe71d06b8df2615d010001	\\x93f070acea89bd9071d7e22ca88c8645765a0a1053bbcb0fcc562d3795b5493e1b8563c9b61ee6d929d1a26af2b0b9cf2793c5408da81e469e0b0cc02e52eb02	1667154940000000	1667759740000000	1730831740000000	1825439740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x3cb0e7b61d0dee72953ee4701c2db6d4296ffa165e03c7ce464fa427829ec8170b36fcfa4e85ac706482849063905fe6a00ef7d31003acee0fbf13e0b14c8f13	1	0	\\x000000010000000000800003caf2c4efd52a2fe6c8c40b341f7517f77e5587f93a7e2ecec6f8f306ca6c5ace3b235fef08ca3d651909045d89e3ae1c2e9581fe6e9d9ccbc6e49d31fe3b689171b4f3e68537bfb3f63b48e104905e4ced18552e9b8a09b9a4b28f05ec02f0ebab64c8925f2702360ace8eb48f49d3ebb1910bdff8755c849e69128f006a0b2d010001	\\xac5e217dd2130fd895c0d5a020525a204f330f01716c822353bea0ddba7e4ee5429800cc495da100017dd64fd3e3052fe21046129f4bc00b05ef13c8b4c8c705	1682267440000000	1682872240000000	1745944240000000	1840552240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
23	\\x3d44dec6253537727c50d96dc6ce07838d687c2bf0fe89eab1091e248365fefe17dd7285339dfb48916eb4d8073e87fc63e73bcb971c21cd8d0d2582091267c5	1	0	\\x000000010000000000800003b90265bcae4bc179feb2800b11d3e29d02cc0686f74e870e8cc456372ea34cc97af6abde0ac2924a4e93986fade26b2b6e5d2e2b2e9739a8d49961cea525b121090bb433e682d98ea0748768277bd8dedca548b3c990a8bffe6fb76ee60b35c3e6a409e9baadd6a60c3c9fa62cd2cc65f936cc1039bbe998ad9c67ee4920cfd1010001	\\xdf127f55f6b173cce029c8fb741ed5ada7e26f1ed5bd2301b8472d576aac2794ee8fe38a4ae0db22248ac8a95717eca9f2ef624f94c6fda04f3c97ff714b220f	1676826940000000	1677431740000000	1740503740000000	1835111740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
24	\\x407c5bdc16e332700c4e3b6e11d8321c55538b2c55dbac5b45a5e61f7d5271bf83ca145248b304491083fcdd12ac28965aeefc255909f170b6a173e569244529	1	0	\\x000000010000000000800003b9d1e2b16114e11d14320ea5709f5fffa94353b92471e776da12d02a11d554aa0051d7f8bf2e25d29e76d3d6244f7ac66ef3b3b109b4a09880fae72bccb253c1a7e732df58ec20fb8a372eba288e30fdf687d6073bb4e8a58f92b21be2bba76e1e7a03c5878f731225bfc82ad154f3a9a4b208d167464dd2f72983ae92ad89b5010001	\\xae0c70edd873b905e4baff8c6f9f82c0041cee42b537fbfa04f99a038c5b1079e6ed5810ba6fc429840cc77ed08b3502c00fce7b3e027ab45579f4a64baad702	1675617940000000	1676222740000000	1739294740000000	1833902740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x47044711868cc0b849d4b4b720992a62bd3d8f64fd16fda8bef056538a7e9fad8692078f450446518d49abaf8ccba4ca5ff51efbac5f96670cf96e462c5b4afd	1	0	\\x000000010000000000800003c6d19aeb13cad0eea77268129ccdd3ec61ae07009260ea9669c4ee7cf6b9cd077e8971bc611cb9fd2c3816a7b820bf3ce904b34fd7ccee4eadd72e961003c423e66db7426ff987f8423616c2604ecba32b9186cdfd77b191d2ac862235027526df81acd0aada33f8b609f86ae33284b7690429fe50af5338867d1a19d28befc5010001	\\x4f040d65a532015dc3aff029da63687cdcaed2384ba573c70eb84945cb88a49590de0fbd0ab9e85078cfe1b57cda014249518ee11bcbac1bba40952ee74a1401	1670781940000000	1671386740000000	1734458740000000	1829066740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x48646da14e7dc69130e5e335a86f2cc45bc5d358b8d761e0c218cabb3cb3eea797e78ab6686b0ae3cb925ea3482492e4386d087ac6ed7d4d7dc4722addb48a8b	1	0	\\x000000010000000000800003db3b8dfd1152406573c4b66943aff5c2fbfc848807f1dfeea58bc8be2ebd52266f48ba078909b7d3c310fde2115acb76fe0ac8dbd84e797aba0bbd0f3aeb8f06306307f0846eaf45e570cd81e8df1f80a4be2a3bebc65846fd13a0b9b98634819d0d421c651c9d9db113c02105acd317ba61b25ced47cd81c4ce1e31b1d682a5010001	\\xe66a50a0532eaf367497cad84936c09242a150969e39a3582fda791015ef8962733e93af56e1c27b627fc233bde8e4f4ae1201cb99eaca9a32c9ca3219d92d09	1661714440000000	1662319240000000	1725391240000000	1819999240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x483c8b4cd79e5d92bd09dfbcf67622c82935dc3f55046b84b724fc2958f7da7048f91eb000620f43022739f1aa110830577daa4564d64b55790730e9fb22ef27	1	0	\\x000000010000000000800003bfb554c7cc13cbd952066617e25455801be41d4c779f2f87319303ce567cc2685e69954f430fcd9e8c53c1c6084b3cac671230c9a2bbf3ae4f64077aa6d2c1a7123152355d267d24165f92cde686a658e836e2e6873a0bbc3779ae85376968b674559b58b7c61caa66a4131dd593e606750710955b5e8d923db982db9013c1bb010001	\\xb3d509ddaaa7070ae9be66a3956c60d06e7db005b2993ce59ebb4b20f5740a94aad6f7cc0cab49422fb0b7247c398dfba9a88b199db1bdf0effea62b67855505	1672595440000000	1673200240000000	1736272240000000	1830880240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x4a1ca290e4301c201aa0e2b6cb016aecdfce31e80eaa7f2110255a6b8c55884adde6c6fe20de9f721bfd1d91fe9ee5a2f01648294223fcea3750748919730bbd	1	0	\\x000000010000000000800003a6b1871cb29d771b7d901b8081e517efe69627e704fd35235f8c430295cb7f22ee48f8c941e5274e05422ebe2b22cb5548184e98fc80db522a0dd387f05bbb309aee66a6ce844c0564565ba173d56e658630b84998e5be02581c9ad71fdd47e2e62e09e14adb5c36e67b885289b8129e045970be328fa6f86d1696b13aa74ce9010001	\\x043078d1dbcadef59d1495be77b42ccf038d9a87214861a4c4cb129d2144c78a65e88a1ae391456ab795edbc6a9deccbddd4f0210f837ed79498304b7fc5210b	1659900940000000	1660505740000000	1723577740000000	1818185740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
29	\\x4c20e17e67d49691ae72be372dbf14368e4e0f79229ff1e51a303ff57435079136bbf8ca3e6fd7578a5bc3821d5c58fcdd00858fca70c788228fb865ec15d4c7	1	0	\\x000000010000000000800003e7efe7c0835e5b934d3950ae0f714a1d479d3df3489ff434fafdaa5c2312f0acc402a05bafd9a4bf7a07d06961557f824cb9a5cc9e1b0572fc94c9e360b4d978e7131bb0adc94702ae0f40dbc3dd30ede3cb23e10ee2fc0e1693a1f301b6d8d173289be3aa2725198f6c65304ff161b4a9918151d2b737f5dd7d669941c00673010001	\\xc5759d6e753e6bf3d5fe8e587a3b96e9a1f7018382bef7725179bbc696962344fed1311e01a23c459926332fdfc8057acf97a2bbeb6655501147b15a8ab64f0d	1684685440000000	1685290240000000	1748362240000000	1842970240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x50687b08f8fd077841baf8dc6b0064bb304986f59925c4ba88171516b094ce177dca911b229fd001754157b3aca088d96ed21d66817c5a4a55686baf114c8bd3	1	0	\\x000000010000000000800003c1e34490be540b8bffeed6eae0b95a9c5867239bd8c747224274df11785b65e4895f9cdb6e91e3fd3df517a0e213c7c31bb6cc24f589f124c90adae11e3ec85aee6802b88e977f55a7b4018016ed28e3dca79715759d800ff2fa81fc40c974df5c516d760855398fc001dd52e45d1abc93b878f91dea215de07ed38375cd4f5f010001	\\x16346b44895eff85572b9e49e220b5773d0adb05b7068a0f4a3a3bffb114ca7f958e783091f88a5c4355c0b06de81ad77dcb97557f9950101356eb9156614908	1677431440000000	1678036240000000	1741108240000000	1835716240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x50fc14b47bb046f13fab49ab8a62efed972f98a0e8399f62e26362065982d557822458146f1fef35352cf7141713957c0bc52a9ef742caeacd3333829048ab82	1	0	\\x000000010000000000800003b944748d0d9e14299095966347860c1abcfeca580a84cd3cd11f5ff19553651b616af98c449b9c8e3c3cc450d69106b55a2e9d45fa2ea53cd52dbfa29d196d519ac78c24048ede58feb01188a6b666ddec24ab736a67ae738f99e4ab546ed1c090f6e6a8129e6f663605dba85e74ba0e2115bbb1a96cef4affc5a5c0f7e44997010001	\\xca5f60300c02004c1f4d4b00f725116923554e127ccb089a89405f9c91a52ab64a0901bccae59776a38d8d4d95c1acf04bce6241a50c1c291b87adb251e7970c	1659296440000000	1659901240000000	1722973240000000	1817581240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x53c48938b534d1dbfc6f937b17d269ae676c85af13c242ff898a77da6214d90a92cb58101fc8c1cc44dec8be114f0705e0bf44dedd509510ee4c971bba00eb34	1	0	\\x000000010000000000800003bd2dbea59bbe6e57bb718027ea9c257eb2747b42f023a48cc14ae42af7d3754b4507027fada9c3e4010cb4b21723d008c5ca750703263599d891bb42672ab56fb5306321ef97a2b3439e353e7ce27313f3d1398dccf6a5a5f8b6d69864f2c569d12fea807425575c110c187ab465dc8a6f5f62141e4a9386abd476e164f7b557010001	\\x6bb33bc6fb36b10eb31553d88124cf6213c0fe0eac1a24baf89114eca305411c19067cdf8bfd3e74fdd3364d69e27b93ee45319674adb9ac9ae40d7cdd0d4b0c	1659900940000000	1660505740000000	1723577740000000	1818185740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x58a813186667a3ece1367e665b68b436e8d71238246c266b52cb4efc8ddc8fa168afcd73b38e61a75a739a8ec68c61382e8072baa5f5becfca2a18cd8bea32a7	1	0	\\x000000010000000000800003cfda9268b4a4b7871be309e5d2f3b14703477873854baef13201003d5561dbaa2174e83a2b0d88894e4114bbc8c3e644130609b333024c6c44c9de056c76c8144733682d4bfa39abdbd754f1550195183efd187b3fecd7047b8f79a22f3462ac881e4c34a5ddc033649265b680606ea080a7854d26e73b5a5ce35323e308b97d010001	\\xb1dc12fe1d4a5f00de6885ae65c48cdad540dda58a1703b3a9e550e1b67ff632894a6c2555fa817bbf5971775b10afba1c8b660ae41287cde03d6f6c8c24de0d	1668363940000000	1668968740000000	1732040740000000	1826648740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x5e00041383868a2f5d9b63859888f1fc52dc418a765b108ff522663e520b572a95e96af5937ad1d36fccb72d23b417cf7ec6bceadd924543fa28ed5a0338b81d	1	0	\\x0000000100000000008000039fc816a979188b0a3449e6022d22438e391e0e6c1ccf4e5f57f9b3eed7b159f679b8e7913ed0bc7b9dad7caa165e2dfed2d6cf447d08dc72d82f55d3dfd06d534eb7b2b93e867da3d1fe93403312ce6a8eba0b55a4714760bb28c27213625341d9fd007d7e7f1b1417a7407173164032ae9c6c40fd5e915bcd08d7d1cdc35645010001	\\xf539accd16455d2d5c56f52bb3051eadb5fee2d9f80d13a1aaaa6669b8ffe852e7e55a825e47790a9436fde7131f1475753baa769eb046a6df72e320660d0e07	1684080940000000	1684685740000000	1747757740000000	1842365740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
35	\\x5fbc0fce31998c7f108253809485eaf5632dc9cc67c7095618ee1220fbe837e89771c1d7177475c4cc98baa72fa3d92d31facf6f9f917cdb5c1d9163101d6a7f	1	0	\\x000000010000000000800003c2533c0a20c5bd1deb9a664c5ee4b317c846e4b0b7ec05c9ee76043500236f28a2c4cc981fcbceb1b146877532b8b8033529a888256ad24510bea763d4612b2bbf65ae264df2ee9eda2f794f594485d96240b99b8eeb2b8029a6bd094df84c0cb83291857faf0387b2b4d0ab603a28809f3979e913923b88dd5fe4a5f111ab7f010001	\\x45f081738367443f8a6ae8584b483f8d833f1b18366b8f10957ebbafc19bbe48452f0e395411a931396c7c5b583ca4d2c87495c6d2620baf299d53768ff7a60f	1670177440000000	1670782240000000	1733854240000000	1828462240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x5f305af22e3d3418194154d7345f30fb7de5cdcf88e149c5d881d62e584cb3689ffadf009bf28f149fed2236e1b6e2c5769210fc60053744cfc4403e4c456335	1	0	\\x000000010000000000800003bed2f52c22b92cf6dcbf0a7f7dd801e16fc75f6c80e720d631ad32ff83d00c186b0612c0700b143744ee5de55995b761da4cc66b92fe754a7e91569f8b47d6b10ff8d4b67be7b8c44b84ec48cddeddada6a4cc268162e38908955841ba181e17b84fc0368b32fd9dbbdb04653b3d656af3d213d02ff315322a01489e4c0fe463010001	\\xddabe1ebc99a20e5f89af32a67e2fc46df1e6d3508c0afa13596ac80cab28a04e75c582f5d7120c44bc1296961164467942a5a9e60bcbf62aba80dd9d7aef306	1666550440000000	1667155240000000	1730227240000000	1824835240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x5fa4e09d4fe727bf0258c002a6b16d5d5b9e9d9e473671f4e8150f455305324be09eca56964f75a8f9c380a645799e08494914e757e9a6b3c6689d9cbed9ab0a	1	0	\\x000000010000000000800003cd006eac6806657636c15ae983edb0b8bf72efdf55314edce47815676a3d3a7f3d9ebcb4bc4f9063691f7bf8cef9f066e2f05b62ca07cb338978a3b0afecf35742fe86f70de0df08f4494bef12c9453069c2a2c23e8738d661b8bff9884b248155045ccc1d433332f74bfc5d138516c2ea0695ab4893b4087c82bbc188bfc1df010001	\\xd8c82fa9244050fc211f5351aa56032247833c07a050d84eec0b6a6bfce72cce5766730ba64dc7c5bb8dec38351d5b669b974f5f166ed6a2b2b50b3dec1bc800	1674408940000000	1675013740000000	1738085740000000	1832693740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x6034864d4c6b67f21041ea21e56d96abeabf212f28552e2d4f876977accf7115bc87b05d916335e8d8dc1a454d2a243583ee1242632a988e539be86e7091f951	1	0	\\x000000010000000000800003d9946d47fe5d097d9e8bdf7016bf50b9aa2a0330d3807f5ecf27992331d64bc8cf9e4ef494e210d7edc5aafbcbcb93217ad3965de5993e48382a1e1bf8eeaf07ecec59b0ad4bf9018674ff5d20b30f5b25a9cd27f6893f355f1f5a5f4729bc438735c99d550041d3f0b6d0afffac9cf038e659c6f16f00ab9e3f0811e57b6f67010001	\\x847678beffccacc79d52a005d0cf168674c609a5327feb54efe37e62396e7383531627ec91beace54331b42fa461037fec48d15f7ae840a63ca510d345f2f205	1663527940000000	1664132740000000	1727204740000000	1821812740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
39	\\x602897f2c565b2c83cf926401c3f381d39bb7259667bad2f1d5d53e6b0fe9bf5781532e7758c90ef9041d573f22b30a22d6a243a61aa9723b21cf4d11de295e2	1	0	\\x000000010000000000800003b11cc05d43ae67ec6710f776a73a476ebc61fd88654ec6a9ccc372088554e293da4cecaf5bad3b005e647999dd505258ce6cbcc13917278c28a040a10823b14fea583c8d26d0699b4730e10d9b8a9e710df328541a2fbdd51ac383adc750cd01e17c8543b364ca0ae74bf795496ea4e81ba57b1338cbdbca669008076572f76b010001	\\x2077611712354b42b6463a6926cc044ceeb08686278a27930250881c91080c8029560ab5c9c21b8c7d4a3486f36358465922edda2d02edc27e04ecf8a36da203	1681662940000000	1682267740000000	1745339740000000	1839947740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x67548f1fb4b4f5bc2ebe82f676ab8cb199484a153ec6e94e9b5b5888af4d3f82ac6c1a35610db77a417a37ec62db472695b9fd644aa7a3cd4203f43c880dbff0	1	0	\\x000000010000000000800003f0151554f9e68bf64f7a388214d8436de2d4c2e9369058e0476ef3cd6e824e33fcd58cbc0cb5f0fbf478421fe34e1e8198a4857dcdb0b88cbf01fa596386c542e6f5bd91189e2f55deea8b87665236e206457243dbbe48e05265e3ce49a9c63cd630c2924ecdbd1c1f4914eb40d84f665a8a97748b8fd2525ff900dd926716bf010001	\\x6ef6fb71c363707c72de55e930dafe58da65df163e0d6e308ae45f8b838eedf41dabba07458c76247ba5254939d0bd441c4e4aac05b72fe429d0820810f3810b	1659296440000000	1659901240000000	1722973240000000	1817581240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
41	\\x6978997e61beb6041d5a8ed83bb5bff9023ffcd2b39dcd4ede0b390d946c8e2bd6915165dcaa6e036408a45286b07db13b6dcd9f2fb87ec6c13a48806fec0326	1	0	\\x000000010000000000800003a78eea0188a052b3420f8ed8c4331d462f8af8b958592ef3d2ce9faec238bd7ed301b25be6fafab97b2bf795f7f04f7c914e2b174f66a4b12a1fbb5026c79fbb79e651e450a5bfffdca33c55cd566126ec781b600b270f1ac89ca93e3bf1894ab29a518d46619c9716059bd226271df3d1387034465bdf5c3af347745a1205d1010001	\\x6db2573788f7b4b7b13a558f15111d527b00137fceb06538f165238bfaa00a913c24b01b6d3b02293e32c9265afab09e2ff1f3cbc424ebe63ef6d6e197ca320f	1667759440000000	1668364240000000	1731436240000000	1826044240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x6a3489734d942126d2372d91722179db8602b1648af328b2873ff584a1d4bc4be4982bdad852c30e360e8ddcd3a3cdcb321c19ebd59b4309088d4fcec26f4f63	1	0	\\x000000010000000000800003be4836ed36f5f552c1c8267388701353df17a8e3c0288245fab7e99839b4f3eae67741fdcde0c5025e2ec6b4125042a4b93f9b74c614ac0b4112334fa432f2cc904182504ed54e0a9600ebc9c50a505c8e226e87bdd944781acf0ca496f7c9c9337b04b17afdfabb799e7e2feb5e7f5c48fa5f7e5e2c4dffdc0942cda05bee55010001	\\x1722b22e056b1eaf2a1392470bdc6f574342217d66bd9335edd0519085537e2c4211a72c28f31b0568a4ea231ce29ba6a597dbc3e90b9a116d755207121f930a	1684685440000000	1685290240000000	1748362240000000	1842970240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
43	\\x6ee4bdf761849a70899d1941088a1206f36b502ebe20c75f99823166dfb811b81af8c1e1642fdbb10da06fedca4cda1859297e4be1d6af1443618906e541926d	1	0	\\x000000010000000000800003b842cab0ea51e498c445637d8ed158f307a7a36bfbb2e46c3ce0c4a7662d4ada8e20d64edba284d900850749419c27405d5d7880d4cd15aa87e4b676aa95d87b425a1ad385c6e6769f5ae2ce0d06397e11854eec27b415b4062bc5b910d73c24c5a6ff65e57a2db17a70c014596ffd80128ffc79efe201eb8163a13a57c3da8f010001	\\x3a0f4c4fc6a93ca45decf02e96dc9a758aed143f4ae2c4b198d5def81043e744488b85065a08cb5376f50777df884db614369b38afa20f40cdbaa7413ac7320d	1655064940000000	1655669740000000	1718741740000000	1813349740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
44	\\x7438c978fd21040c3dc57549b22f423219327d36de731c12476b87fac57399e821b3c9c152a55f2fe3b5491a20ad6d18229bba358e534706e0bf1ee818e17ceb	1	0	\\x000000010000000000800003d4652f15f394e4a7760893001cc4ea0b690b21146925c43acd209871c22f1ebc363c7ef3bdb6ae52472982810202ad580ea78b2a0b57e80fab2199911a13135722c9fa8e2a6892c8ced65fb05574e70ff0b5eae6b98739d4c3259b320a5aa1c8c9ccd2c82da29b630e217d9b39b7613ea5dbd034dc40ba759f7d733d00b77a9b010001	\\x9f54f2cfc46b0c0e5ab71b22544ecbf32ea6bc566751e4987b7cd71765c49caec65555cbf8bb2a13b372fd4e69646fcb80f14b23acec80ba88af733e4ba20e0f	1679244940000000	1679849740000000	1742921740000000	1837529740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
45	\\x775cf6fd0278f3c7610e61a74fbff41352e46a9c3cb623f913e28b6637071b8ce0609b6a33546204af705da9687f89ceae9e6d5063dbea1eb01c7a9217ae22eb	1	0	\\x000000010000000000800003dcfe577014c997454d3c723a13b52d0f96ab26ccc668d5c4f5a801d6402f28f37d254238e16fb05db0804d2f87b14fc1237880c0a1e6ca4214f61c6d25c8d124103b22b9baca35ecca648f7814dc00891782edf238791830a87960fe8005cae166875a5e6f92ca12d8043fb6df4ca6c56301f8a43abca1c6b44aed07f82560f9010001	\\x227ac828999198e5cb1262712562aaf66eeb129102219b7ff886536d2c5849094e4afed8d5e2af4836bc17d80cbd7be1f44171d774a686b239c4f0805f25060e	1661109940000000	1661714740000000	1724786740000000	1819394740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x78cc68595b21aa4e53014ad183201bdb01337d735743b2949e381f238ed7df038e71b0223520f5e347ca209cc2259bb1a8075aa4d33a27f3eea4b4b5f0132cae	1	0	\\x000000010000000000800003d091342da1bba9e2ac320bd60bd53d2cab9c7b767ac195076c16829d32fc8be6d21f3f49f907da5382969ccb34bd281ec82c155867f262ce925b4b004e050a7392c6aac0cb470f9a662b3d0f5f36a14ffc8179a8ce76eba4fe9bf6d8091c1c8f63fa6a3e58c5dc69c3ca742bc2414e5b7d534ffd1e04b8ad6b5415aef8d531b1010001	\\xcd298b5da99632ce4bb78f2f8e83a2904f5e18e8e692c42b54d60f2d707f2d26837de2b6c3dc79559a9914815b00b040d83c28e75abc7eea38a3ef79da9b3202	1677431440000000	1678036240000000	1741108240000000	1835716240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x792c10cc351830912387a117bfc3d2c9ded9d77db758860971cb6942f1a2b2596e02cfa98a3a5f87f8902bcba030af1dc3dc4b1d1cb39e8dd22604093c52c6d4	1	0	\\x000000010000000000800003df939ac32b884ae996dad96eb70419220f2a4b4a346b85992a084745df629dc1da1fbee5486869cf600c8a2c02d4be16d175e7c17f533c9ee5139e501b0e855ae979322911c2a5d25a5781e88989846444d6af05c5780253ef01f52a6113da8563f0fccfb8b813ef484efbbae1a03e5d3356c7adf348e1ab105992fb01ac5623010001	\\x84d8528907ced2229a8f80c174d69741c545ebfd5bffb921ff29db3d7b4b929bf181b3b417ae362b5de6c002b28098f7f9a60b2b4de196b2db9b46ba996d5f02	1662923440000000	1663528240000000	1726600240000000	1821208240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x7cecd9a3a296440b98322d1feb8018d7b464e17fdc833f957ae33dfa93397c7e5278dcece22b0c7111c4f03abc0e825540ffd8371600d91553c85e9c17c24375	1	0	\\x000000010000000000800003b1b09e86fa673737bf1b1bde6d571632a0ded72189a30be62208c615d457416d37f0f522807da4f45aa53c133364f7661255dc53a7682488489ff71f894984b51b5b4079136d1631347e6d8fa92c3b570b09e61319d99e18a5bbccc18d3d945b298eb5b56e7d57e09b691e40479727caa05beb151cd3ad1eea90a4a206e3cf83010001	\\x90bbeccf1402bbcf887ef35c6fcb3d9d0e83cf5f405acde62e03c4076fe0fc2a272d76c375b135767f56b6512e57a2cd319e1414eb245a743430459e661f7604	1667759440000000	1668364240000000	1731436240000000	1826044240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
49	\\x7d102211d21fb08e884c3c5972bc9cc3caf753f640194d7c507219bcaec1239b21a1a9c7d9ac04472bf8941d7fc21bc761c601660090619a233bc2051a58832c	1	0	\\x000000010000000000800003e5c3febf71cfbfa74f7b96167c04215ac47de979e8a658cc28000131b092f46bccf575cf677caa94c8dacc0f37bb1be6c6d2910e88984e1c5e284f085164290f96682643b17b2421baac6c616f5be84b7819ce51764b2fe8e06d8efa9dfa16cf8f5e7e32a4f315914a24ada38171455bb93cdf492b6471c5b9e60d35890312d1010001	\\x7e3fd7a779800f62a9e615fba59f97b66b3b519124589d74c559971a3760f58e20fdb9bda501a8a6778ce750e2e834473db4b1c7df1fa398c96792568ec4740c	1684080940000000	1684685740000000	1747757740000000	1842365740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x7e9cd026ec407440f3e1bf8fb58dd40539cbba2bfd70732b4a0526e66f92d6cb7bcc8077eadaf9baa7bb83e231e293b77f667c8c86038686726fd71ebd4bbfa5	1	0	\\x000000010000000000800003ab5a09f833711b8708c15eac9b4c790a2a34b43eb9e31699271f44a87846ee5ea601496f64ce2a8e98b7545289ce0f5c52e06b537b7fa91c42efed6739915870b7d99fc21f094e37fbada81d258394be0f9bd616454ef7c3e81bc39d928d23461ab0f216ddd72cd858c67113732cd8068f90fc06ba89db2bf53a8850601c2b39010001	\\xe6442712c889ab1d57150dd9a3b1373d1ef1be14b55f543d71cb5f4ccccc515b5af580d6854a5c502a0a4c3bb31c1952fd28dc7c8a4fecac034f154409c2e808	1671990940000000	1672595740000000	1735667740000000	1830275740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x80d85c7510282af6db98978246eb0b67eeae79f541c734cf9b77504dd40fd6d056f02a67270e78116369694e7b837cf631dc0fc95aa63d96e83d5a42a5d9220b	1	0	\\x000000010000000000800003db4e44b7272edf484774d581865b74960bad0edb55b2a7fa70109c7d4dee9829d2e87e8253e6cad4b0310620ea6dc591fba6b2a6fad402852e0a7532810d1144716ef79f11c515f9e1de779c9a14cb6729a38534072b2cac98e2b96924af8f577b25cc31cdcc1b47a565427589403265d822b165ff92b9e218c15c7c74a67ce5010001	\\x3849f9222604e20d2c7a353c2a3851938fc1697f90dbbc6731819b42316516ad2434556c6a761e00e7c6c787fa0976e70e5c0cd44a78fe2d701ab3c182afee01	1685289940000000	1685894740000000	1748966740000000	1843574740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x810cfb99c287746653ba6441254759b1307d3080bc3cfa41d66a2ed6b91311696ca07bf8d23d9c4cfc1f54cd4c4e46c23816b3f11d202032fb741d9043cd4fb7	1	0	\\x000000010000000000800003c231bf00819998129445548b1b83872bb9de4822447fe4f93cdf75d22706031bbf410a87154f1a5a7d2fe78b388589fc23a13d2b744123b9f3fbe7720e13271aac722fd1605a19b91582ffdb9d4a64e570e1dfb598610d8359945dca6ea85e49d211776f0ea2adebd5b4146599c442dbd5c2a363f3dc3115dc40ee78b4e70725010001	\\x8f88835864d9ef87190d572596264405b7217f1368d06bba530085c4a2d1c3c692d397c965e51177c914873e71bddc403c428c62ad51940500d058fbb3150107	1655669440000000	1656274240000000	1719346240000000	1813954240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x82e8be07f430e7929d7e4a587e240e3548c163f56b5589c5ab41ae6918699b8ba47f82090c09215d629f2ee2f46961a70c63f977bf11d869b7538dceac733578	1	0	\\x000000010000000000800003d4c4d4f72dc3cf3a45d0b4fe46d7efb812c56cc4d130037275ccc650ac766ea726b901c00c99f7b89f2ad81f4045503e61230896463692f0d456cf929068cdaf82b210490d5fe0e34dfa96d1c5f69d7b142ebeb475d9c2f1285b33ae3d081ec770dfe82f5c274d17ee845a701e9eb8f70cdcc0a98e255b350b99abb98c27a343010001	\\xbd91c3acba0ccc881cbebc8b4be3bef5774d7f190f720275ea2c259366e53854516d4de8f682d109fab5e523b9cd54c1ad26001731f74c343d42db00dcef4f0c	1685894440000000	1686499240000000	1749571240000000	1844179240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x859c9f18b0cd79b389aa85f9dc57372e1c8213a6adc652fe655e21aeb719976f5be06a900d8dfe58edadf26830fb74315603da4f621284c17f1451dd768b06b4	1	0	\\x000000010000000000800003ecdd16e66e62273f51f7fb3fb10746207bad99a4a9299643b826982250e8527b56987a1f37d3854172eee5e2538a23985089879aafa94e43c3fbdbac6c056640f33c3bf22eb67ea76a3635ca1b4af509c5682adb9d430db8a23784a28c75e97593bdce8ea52275e94fab4f4ef4057aa475116d140f4de3c8667904b5a77764e5010001	\\x2092fc03efe1e124e0273276652a7d253eb040dd845c3dfda676cb7ede1dfe4b2050c97862560263a1427c065b8399083a564db6964ef40370756bd91142b90c	1676826940000000	1677431740000000	1740503740000000	1835111740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
55	\\x8678d64618c974b63d930b9809ced47abe5b0093ef9983018e36f8ad900c7dc21eda04e6c4eea451938d307b94b8782e2aae648d653ab20cc606920ff5c2a94f	1	0	\\x000000010000000000800003c71cf2c67c6e9a4b89f37c93e0d9a0c297ba5814d4e2c6df2579da031572cd28c7744a0730280cf78e5ef8a10007fc155af70716727b1f93ffe8f2330468ea27a6ddd918b9bbddcfb7892bd13d7cc8b01bf174334d5996722e29a30f0f238039207af7eb3b6999e2cbaa532de3e03d680bfa8ac5a0930a8f34d9db4faa535cf3010001	\\x83ebae6c7dc16c560121a99b5888121bee57c0df55caaee14f4cd85d30f8ed87630d16774716fe0c14674e8c2aaca5f5e6d2283edbc0dacb98ca7d343faa0404	1685289940000000	1685894740000000	1748966740000000	1843574740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x8828d6391749c2d8736f275c63a708335d2cc261a91fa061db146aa988d4a33e9989ca9f9b7042262dfc60a5ff20786add452d3b5de071a6364c90a6a1b0d270	1	0	\\x000000010000000000800003e459b906eae9a3f32553461cc1e65b8f91634311fffceb6ff516830b7c7bda8699405781d6f8b28538c78eeba1ba4c86bf2fd2f5c3fffb41dd58fd5fe36b5e400303c2ecd722c74e1f6ace60569c909778d18f32a60b1e644293063be95b6a3466b10f807aa3c8c94899f30ce0fb825aa59a23656eb1a34954e113f23e02c969010001	\\x3048a59402471e8b3f48c772febd5f5e2f160fae6e5ed77248fec6df482ef44af9d1ea8f8fcd8e3f572e410d7f51ecd294ab433efdc51b2d77268901fbf9ba08	1685894440000000	1686499240000000	1749571240000000	1844179240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x8a4cde67a4dafaf3c7e6bfabad4c564c1a7393726b384212f5c37de3c5dd57755661e01d78fa2bcf132a73e6946c3e82a0036f8995777f10088cdf5b42fe402d	1	0	\\x000000010000000000800003b9cdda9ce60559cd0c3c4242f2237c6ee35dd474929c91ff5624cabfc2a60f13b5cf073d5809fffd5beb916e7dbeaa15c227b0315e8cacfbed09307f18695a6fc40febaf024d06f5bd753dd722e6e14f0ded52857cb15708bcb65412f9c1b7f6428b2c0671837869bfd79e16c63557cfc4cc3b4c52e89cb65a5f922bbbb00461010001	\\xa65f06791e609a4bc5a4f95ad5708219f7a09d87c9a5d75ba46e10bc82a2ed05b59c49f9a20aafce0b235f3db62b9998938fa8278034780405bd54e7e724dd03	1665341440000000	1665946240000000	1729018240000000	1823626240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
58	\\x8a08c7f6f5432e1539243fc27c8b4c04b65be8e81b48f8ca37f03160811adb4f2e9d4b42c9d03babeb855547e7113fc46c7c3a689f34f67aa599fc8676338ffc	1	0	\\x000000010000000000800003af96de4c87b3757f67cbf8cfb1af96bab58024daf6fddb7f7d9de606239226c4cd932bc79ed8d0bc405973068933274c259b4380f0102c453353ed0dbe63cb9575a12d8be09cbeffccf2fbc51d8b332c423e21ef9c9324bb54ad0c48998d8977cc3c66cede8ffd95bd48c759fcc812ca7dc4797aaae819c8fd5cb4f1f18468bd010001	\\x8463d3ee609898de487882c52115cd2edd30f75f2cc45ab546a91371674f888f5f5236524501e30ff26427eee6830511e7ce103dc7a894a0449a3af97b41d00c	1669572940000000	1670177740000000	1733249740000000	1827857740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x8f00978a191ee255a258ca0842ba0f86feee91e3d6484a2e6f4aa834afd730d4d1a86bda8293b299f4cb01415c29a848abecc28d5b3a4e112250a596e5d25d1e	1	0	\\x000000010000000000800003c802fa93c8f8d941cfccd0561de3e74348381349ee8e8911baab24148e91aafea702a68a5309b369c786e539cc996789699bc628071a790999dbac45a32c330d248bcb6ea0e99c4fe2a2ed3d89edc8e4bc8ed8e785e6fbef77acd46d53e11f2510b99bf29a5eaf6017571bf1d62bc56e855451fe83a2a671db587daed859e961010001	\\xe258c5a397916036649cddae1b37d443303b3f61f5603abab0d415d1c2d0a4d25e5888291fa92049f622188a2bfb62ba6661a02d978314041ced04340917c10d	1678035940000000	1678640740000000	1741712740000000	1836320740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\x95ec48bf167c0d7a7bf09418946b5de10db29707d22c9134e19feffbc61516df850af9f7194615c989b62e03d00dc4dbf89c4a7c8610215a0111ec9648080285	1	0	\\x000000010000000000800003e6ea47164e421e37f3bcf906d3cc2f58a45da6d77cccda3f5b5845e698d0f1116bf2d4e2ffe88b4969df8f12cb0c84e37a0ff040fabb31ff82eb1acc140a4842bc18f074b7f9f80b26db0a87438246fe72f72308189f6f4019f99ff4417e47ebcea5cf8e8272e5c746c104a4b4a72440d285bc253019d4c387d6674f5d58ee57010001	\\x57fc6d43d19364e912499216397de85cf34511d036e7ad6d3626b080d596e64523a0c026953fe6df8818249429f42b58ec6e0a79f890b10779e2e92090a70a0f	1662923440000000	1663528240000000	1726600240000000	1821208240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x97b0383777e83ef8cbbee11b96c00b490ad372d748094b7db3cadd143ef126a35358d48e2dd8ab9cd90cf401a0c1d5dcc43cd62acb32b7d2a819cdd39412b463	1	0	\\x00000001000000000080000396c7f630c4ee298b1b8b19bff66c0b71cc8befbccc93fefe58eda91d6e3ec743b18b5bf6c8fc106aa221381de2bff6ebcf25aab2ce6cb8a5f7590471e260df481fe767272f162d51886d27d3dbba4679d1fbe79b6a684437e8df0e894334c9e37080ab144816710546c804ef590735858a33f1aa4e56d31c51613061fa779963010001	\\x662f6d43de1989f2a15329780f0a8712e1fdeaa8367c00e5d43f6a59014e97a189d2e47f31ccba682bb8cad1115d0617da9d3682c9139975f6b779ce8e6ab20c	1667759440000000	1668364240000000	1731436240000000	1826044240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x9a6894481c69c99c5389a48fecf69c211e2b7befc40b9ff84e6eece95cefc76f20783f1f8219dec491c994d126a0cbca93fe2932fd84e9677d70bda1aeed9f00	1	0	\\x000000010000000000800003ec5a1b89c1b8cf9da078466fe822743474f83f6cfb39adc13212527f420f12def45ae635cd2ccc9ac2e0c22efac285879b52fbe4d089ccc8877f5cfea60ca30714a770f26b655e5b00d535b7232ebb95da4ca936bbee54771e39c4933bbc272356d390abd610bf2a25f23271d6180495a86abb7d984c659b97ef7b70f37fa889010001	\\x3492b29b4492f05633e02600da44f73e5754046bfa93c909ac71da5ad4ebcc232461917631a68e6c014fb33e4224c20e779650263e71d046e670172169794006	1656878440000000	1657483240000000	1720555240000000	1815163240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x9ff40699461696ef9ef14d8f4875b0d596fdf5be147b8e1ae610853eb0527c0cda22c74d38cf6f5a0b6d76697e4e976e38f3c709ecac92bc25e0b38f6ce56a1f	1	0	\\x000000010000000000800003e05f8058065dbb54a2f7e6e3a30c50c65d66dc5edcf4fbd6ecd4a8e474e432782b0133c9aa171cf1b7396c9cf4f5d283e258cdb4cba5aa0c4cad3f73b463e02a636d5b6a11f9e344222d56786fbe233fb54104fb6c0ff1d706bcc92f8d7c509213d47ec6c60e6c62860c5a909302d4abf54eb38044a57afa2c35da628ef59d2b010001	\\xb6c9c7bd3cbce941bc2843018325aff0d66a66c95a2c8390159b81691887844ca838686857c20a997bdab212f8b72c910935d442ed2d529a2fcf2d676958ac0c	1665945940000000	1666550740000000	1729622740000000	1824230740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x9f58ae501d390d19aff54bfc88ad0b3d7a85a0d3cf773ea944dc22622ada75bf70cf39bc0e2a0a7931da7c2cc95896c2730b4b613ab1a7e3b464d818748a8a5f	1	0	\\x000000010000000000800003cb52921b37cbe4f9c0446413080d2bb0eccf561045435fc26f67e29a0e707a98898b48bd53209b1f95bfd2fa2ad28118d71c2ac799a5e3def8d4bc276a2e4eeac570e6b4c3c27a2d2fa6a3bdde8eaf552dff50b6e057e8db78d1a8ca8f7e581ac89d119af5991d6e1d8fe3b481f45017a402e948ecab26b8bbbaff9d61efbcbb010001	\\x83ae3248b6be738c616a59952c23bf0e85385c22e792c67dea1dc65b33e05a7b8996436e6594382c0b32f0634ab17034b6741b3ee1e3108c966520278c69500c	1681058440000000	1681663240000000	1744735240000000	1839343240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\xa0e87dedea7f4625e8f0292d9d546653763f3f81657be85db2005a55f35d073d51774c1e005463c848ed9ebd2472cbd6a128e58c7411ed2075c120f9bd0ea678	1	0	\\x000000010000000000800003b759aba1687505989a6a0a8fb5588cdee66bf1cbed069c21473a77553653cca08b96a24c3e3ca029d5c6a2ff08f7356d6986ae84549a19104c839d7bfcf76029b8980cd973deb39ac306ca0adebdba57d9d44b90088bf0e467d7a6f7e3d55643d3600e068fc125115a95b67a84de82d18ddf216a319bb64eaceecbe0375a56fb010001	\\xe5b8a40c277bf01d4a8b8cefcde1751326bbffa5080a7aee46704eaf55cb07da73a81ea1e160e535583e22613b4703e99344aa1457c39be5fcaafa4aafac7c0b	1683476440000000	1684081240000000	1747153240000000	1841761240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
66	\\xa4fc38ce8d668f74822647ad284df2c98f1fa185c15d2e0ae51867d6af37912f5d3d1c1436a8564f26eca3b13399ceb63f74c1638752ce7b1c76f66ca17a12d2	1	0	\\x000000010000000000800003eb10e546401f60dd641a58333af3819a2fd9fdee4d1a6230560e41c0ce7509646a926a3f1b0dc7693926992fc82c67887b3f8f7f64f091938a3a57d1a430eaa3ed5db32123c3a65d2d7fe12962aa879da58200d9b02a8db428e59a67524c6094ac0b75ef4f201e44fb46762c11b67b07319bd96f8822ba5bb4fb89ef88346aad010001	\\x5776bc905f11c42ec55c7547effebe84aa38148ffc515db2f40c1feac9c0b3480934611ef64b3d10c992c57e84c3af49c3ad0b34f4f5dc333dc357d4021aa806	1662923440000000	1663528240000000	1726600240000000	1821208240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
67	\\xa4fc5d853d81299b268e54154cd6a72cb5b2954a21049f275b52dc278383474f6d93ed1c8dafaeb8604c4a9a4407c71434644d9f6e85174218a15091694efbd5	1	0	\\x000000010000000000800003cd5474e15033b82ba9d87aaa26a36824453039f64f363890dc3c68dece5a3476c7e450f24cb81bdb6968a392fd4ea51f1449a33066efc7e1c8c855168f2f999524785a576b2da659a4de16ab3ff3017f8f2aad3c97ad7580592ecab2b93422ad9f1b17339de8cfcde8df0c9b3fa7e2afd7d9e73b91db4e3b32e0587498c99341010001	\\x0dd4def263b068ce39c3ad9b1d60a9df75fc1d2890da8b47dbe71a446fb7372bd13621ca2ab54326ac1242a4cd0a20eb0eb8dd20d3f629782fb44d7d74af0a00	1658087440000000	1658692240000000	1721764240000000	1816372240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
68	\\xa65cd9de4d59688507cfe6fb0b6514c7c1734041f9ad7485874057dcf5ace032b9849ae5a38ff005921b139361457f811bb90de23f12126f1413543ee1769f68	1	0	\\x000000010000000000800003d1073989a5273fdff172def0d7461dc644fde5d9e6162a815f48bac974b229f5fa702905d83dbbfb5ee5aabf2fc50709ab863232abdf6b66a7aff90af4c6d9fa1f5aad2da1bdf6dc848812794626bd3db7ff63201a37f2bf1c0069d69ec049141dee17a6917ec1dc8f08fa7f09b597e9fb617d6f60b7549474f4dd20da4371f5010001	\\x8227edc4af89b23aa59f263fe4b596ea48ca0d445c7fa7afa9fd5a3f8d1cad6a9d2e82222921b24de1e633c2af6f2a6cb7c9bfde4342426458ea7add66e24a01	1664132440000000	1664737240000000	1727809240000000	1822417240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\xacf8c2ce4dcb05ba87621d220f02a86c863f4a9e56ad6d770d52161573ce111a4745afed619d7f1ef2c3eecd50d24442239168e7bc30bb673318a45497602ba6	1	0	\\x000000010000000000800003cab5ba99440225c79c1b84891fa626e19e9a2700cbd8fef0bd1573f9bf68d549580bab3dbd0ae0e35884961b37d88945e6bb354c7cf7b75eb0b9d8527b896c3d5e0416be564e8d34907c8ad42bb04920e4ff07b0c986a4f9a9233cde106c708a64360e7c836ec430ee037f4042b0b89be52e9e7af317ff0d488792adc3108e4d010001	\\xf1c5175a08be58a9a924c4bad61764df4b4a4aef3b5e7c3ca5abb50ebb03b8aa48b224bfe6392a1eaff618ded009e19c5b22b05d8c9acb67ce02a402eb131e02	1673199940000000	1673804740000000	1736876740000000	1831484740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
70	\\xb0f818d8c92e8aa22bc16b793904b5abbe717a0f7c6e3b64d2590d11858a89b64760adac4a745feaab52c09cf3089d2b6234044702b1a6d6a80e8cee4394298d	1	0	\\x000000010000000000800003c6746947e7ef397f6d5005a26121adcd5de26f1f0e21b204ad718bceb8bc0535d249cca4ca8b6d372f745094a88a4b12a45135aa6df89d4d469bdfb5be9b73ef8fc819634823e9298a6fa8bc4a5c1e71878ae3a05027aabfab0d7783551f852d48817ce6c7d8939fa31fffa7413add7eb2a0a4cab6b6b41178e619b1ce38a0c1010001	\\x81afd3c332052ef51765b59e5fdc8cc4b045cc9d5163bd524146f2b14a01585f3067c778e515462968fba75886a5063fdfeca790f66ed9c473e677a9184acb07	1673804440000000	1674409240000000	1737481240000000	1832089240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\xb020b3792865a901c9bcd3d095aea5469b57f131bcff1d914fb2fbffa62d20ac3d889afa5b3a91d08751a300151562f60de9b456fb14581ab0de7bcef3246685	1	0	\\x000000010000000000800003b34122185220361a562f8d97d85ed3bfdde7b7fce82fc604d5532da1ef1d7162e9029b39f71b6b9a8f28475cbfcd9c8864aceefac010ca021b8cf8c233b541844a63684545e3b5d4379a7585507bdf0601365ffdc85451645e56b60385f90beb86edd1190b4dcc8528c283c741b298a092482165bd64e682a956092ff77e484b010001	\\x28bb69417dd7bc7aa00dfdfe688c30cf8e4bbe4b95bfebbe2140f2be72a8d027f3abd62a357a2267faece2791134ca399d27a1d4fcb65b7d0c4a5d1553aa8d00	1681058440000000	1681663240000000	1744735240000000	1839343240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xb1a0c6615159e06f90e82baf0a3ef3ee10008aadfc898270bceced023bdb4de0ab56726dc55b5c3aa997aaccc86098f579e9d45dd80610e8a262d1bf0f65fde7	1	0	\\x000000010000000000800003f4a582725f35c9a0e8ea1fbdb48e69d2638f812ac2420c4f580e1359b33d0ac0b644d3e429970ae57a3d39c4dfbf13c6ba79c5c497029290ea2d4a9cbcae983c347128db800992df1d8c69d030e52e2c43ff6020fb2ecd6ed9c243faf1cafd32f36fd24af03c776648625f17ffbe77d16857320ddaf2abf652a6894744a241c1010001	\\x4e8ff976fd26f48a9c76f2bdad5a90bc5693c36b44c7043c66f03cbeda36521bf36f306687cf495ac7734623b1188b70fbc5d139ca5f5022e213c0f62d769803	1656878440000000	1657483240000000	1720555240000000	1815163240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\xb2685672361156542d2f92a4e2b6d76dce4a00cadd9a0069a6e297771608bd326e16c9d2f915fe9daaa43712d0b74d4b50f750453afc7d8bdb8599d65c9f8309	1	0	\\x000000010000000000800003ba17be537d03ad11fe800468414650c86997b7acbf5afa0f5fa19c9b4a3867d56137fbfcb284e2581883cc79d98b7b5ba21795963f40fef7d68e30c91f4a1bc0660e5d5708d7fe348c3063c4a31b030f8c5e0d280f736b6db164d8a67f1c2ad10b8d49279f91a36de70b4a7ef1a6ef5227866e738961a6fe1886d22f6cb64657010001	\\x4b46fd296a7973d5910366046529cdf5fbb0d961dc5bbb09d94fd38676b826cf512025e5cfd87711a621045f766d9094db0e0c69a3e6f2acebc468eaacecce02	1681058440000000	1681663240000000	1744735240000000	1839343240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xb25cff27bcf2f5bc2c6ef17408dcb337bb3712b597b6dd2350cf29673b5fe4862351093511da4fd3827400f5a02acadf5858190fe4e874281d477e0b852ac299	1	0	\\x000000010000000000800003ccd6a7f15dc2c2ef486bd5e00a8ebb55d3c00e661fad07780e1b9b21dcc96df17e9f6a74cd21840abb596f018c4770e65fcb85b8d5ddeb495a296d3ed10a4e86fe8ac312e02ce1e14044c23669997a4dc77668f7736aaccd1e912f6c0de0e1fe0d44408490385e36b4ac18e78348847b8bd2fe3b2de6634ac4ab2ce78719e48f010001	\\xd3f2b3400db5cc7c0c7c0a4fdde0135df25031a9450c3d88867498260484e19c2255ac142f0c52079aba7f77f74cf22b3185760136230c7395396c5859a7a406	1656878440000000	1657483240000000	1720555240000000	1815163240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
75	\\xb410b75e6374a1445719988ce15881e43cce8d1129c09966bebc9b23c467dbe7bc2fa90dacf0d487f28f97a030394700a40482f70a7712a20813490a1e82691f	1	0	\\x000000010000000000800003c967a830662f165008e8a4a5b43cd81a249581523c242948e85f1e4a22330469a95749634c8e52359de65b2b45341ed805c96c1cf8439380a1aaf310489fa1600fcc73d1e333f7127660302d60bfcc064619b6a60614746bdfcdb1ea69045b60673308d855b736f890f042fe16d838b9e1e7b306c83ebc552b93ab11ef14c4ab010001	\\x0f4d90c9084bd4de2e7f78a3940c83e0c28e547410774a089406d183a9681fb30f343913f4dc2bc7a0637c944ea914e7fd70238252062fa0ad8b528cee6d8b0b	1665341440000000	1665946240000000	1729018240000000	1823626240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xb5c4c40ae391ba46f26bb850179c4bfaded38032ec74cad0353321e4d443fcee084cd198fc496b3c4cfce9a1ab1fd2152ff7a678ea2b1f5e3396497017839402	1	0	\\x000000010000000000800003caaddfd199e27593bb538b1936661cf9a97364e674f6433e7aa2ae21b8ad20a23da8fb7dfd9bf88de363813dad4d5195baaa89b361d489f54afa958981badfc8c85421da5a3d8187aae817fbf0a7f38cc338cfa807b17e6ac343a2547648a194498786418afb2b15ea4024402851f75cd158404707e0aa90748aaae282cd0473010001	\\x37cd622939697e9dc36441bb6a4ecb08fc98395894bc5afa566d74235fbc38996d1fe02eb025dfd3fb379f841003e46c1e0b8745d25a46f065d5b10329355108	1681662940000000	1682267740000000	1745339740000000	1839947740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xb5cc3dffcc418ef301c73bb3b01d400f7c4984f475bf101c00fb4f8bc196cd7c70580a8c5221e4e8f8b07de9bbfe56b01635d41c9c228fae11a1ec65dd35355a	1	0	\\x000000010000000000800003aff825e570f4b55876fa05f2ef8ed35575603e0cf2b4a4be4c0e0927ffa6d7dfac50fce810625786ed6bfc0b5139fe305975f9c19b13b42ab75c95a21bcaebe7a25702582f6927f7868fcbf127e94bffa454c5d37e39d20d7074cb9801aa30557540c9885fea268d1a82e9a3e875394b662d3cc9e89b5369fbe2572e500144c7010001	\\x5ed560f7fa4f3bd60b180de16c14965a99b4b91efd72f1aa79b2fd2e76400fc30143cb5133cf63c5078a40fa204952647ebe71c1c6c0f0cbe0b47a21585e670f	1667759440000000	1668364240000000	1731436240000000	1826044240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
78	\\xba08f64de444b5601bffb63a423026d29ca332f8e0f65c08641bcfc3c3be037b6c63e65aef6e2f559ac6565b536b7d9f3943914e3e2d92cc652bae2745f5e0ae	1	0	\\x000000010000000000800003ae4ad2b432291d70f68fb656d3514794669a6e07f6fbbe620d2ae63924d9660ac78e94e27c23c18ce369aafec8fcebb1f7db28df6187199a3ac43730c4d4eef271357147da2cf1369322adbeca6faba4d242a40cb3a96d100ec7e50dd505745ae29d0a4527f345d31a775b5f8e372e78d8664dd431df842a6461c03b154f62b5010001	\\x78dbc26a640f77514327ecbc26cbf78b122ccf5b8531d64356303c3f10da7ca1c8c7b0fbd01a7e8d9f63858ec8a5502719f42e266f8d9c218596a0484dbddf01	1676222440000000	1676827240000000	1739899240000000	1834507240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\xba4cf1034818f879fc8c8e7d7d7e6b009bde04f78d8eddd106d2102906bf01d38f4a6f1714d67177b8a8ef8af45196a1c35168f4ec10c647889ddfd8bd5f8f92	1	0	\\x000000010000000000800003a856a70c8367164005082059f246a7321f1b8c6ee7565f84040ac89026f900bfeba7e1c40bea33df2e27d49757bc9af2fc120788eb391501bc01df99aa246b98ce646bb9342e95a8b65e175e14e9988ca7292961735f37cc3bf779cccb767639bf0f4ca7828737e78d730e6a79c904841738049efb637b30e8d1e7c2463b179b010001	\\x3ad804eb4604ab30dd07434f528bbbc3cf339fca4abfca57c23bb21f30cb7e642c548f0953201a3053368b4cdd3ff60ac2da7d9e18669f43c959babdfefd4f09	1682871940000000	1683476740000000	1746548740000000	1841156740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xbc68f2058ecf8951e4f0eb841aaf5b5f4fc021268054aa374deb3b0e94d719257c4927c4faaeca28c632b732cf24d588270883d4ae653802630af6268367d655	1	0	\\x000000010000000000800003b734870490d0e89ab998433b73130d8e909bb61d17f0a46982e084e2533ce2a7ac9761b6b9237054b6ce225d8613d5ed335eec254299b5ac963d52e1e62984dda643559101fddf8b6ddde07eba32c6645ff0b6959d8faa2a7eae3823f5a07fffdc564129d3a7ee01c8a54477c2de5cb39dce410f7fa0521f5c7b76d2d6e2e83b010001	\\xaed879e57c536f029881315025279a0da8b5cf7d01c77dc643d1189488082fbd397b1522c2ccf23cefcc4c2a7749680c5147fb7ce906e5c459aa234600ced606	1656878440000000	1657483240000000	1720555240000000	1815163240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xbff041f2ae0279984a6ca3ca33049751f13de3ba6d7a07c0217a3fd640f3a001f82ac68064dcb1615e1a3a59509f8b017db40a15faafdbb1dec386dc3cc840bb	1	0	\\x000000010000000000800003df8dce8be84041f19cf1009611e763cc78eedfb30dfed1bd725b6d03fe558501f81fd010348403cd5c63431c065bdee7af7cffa43985afc00d165ee1c1728398ac3bccd8a63f9f5620d173fea96f2954c4d07774709761b654ea56e7c8de5259c575c90a8483eff5f68a7f876073b8ec97a19b81f311a3e2dd4db20b8814c9b7010001	\\x80beb8067e905018d7aa17dd9866159250f7ce7312110949aba78de1181cd8c6bba1c5926d0e52a93bf5aab392bc90d739d889687dfaed3d36008c67c6309e09	1662923440000000	1663528240000000	1726600240000000	1821208240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
82	\\xbf2056920e0e38fc285f85a8ed65ac998b9ffdca2f103e73744c0410756ca854643bfa2d64493c27f153d79d0beb87b88ce3eac3b88dd65323026639ae985e70	1	0	\\x0000000100000000008000039d6c68b9fa357b1ba649ea01ef3a126c66ddbf4498266d2fa95f4a9cc2e66ec9f2f81676f5b4af2a3edc5a047e59145e4527fe45c27fd885b43dc1e667708dc149d9d629c75a2af57b5259d975203259b323b2713f1b2c517364cbba8e5c19aa5229486fb1eaac0d57e1900a12008b80f50862d45a5644977cf9f0441c69a727010001	\\x1df742a1c5489aac2648478c4eb3666a467a24b2f674a477ffbddcb1548defbaf34b44577820429e0640fddc8879c0957fddd5e81e83dc9b7cde3b4ce10f9003	1683476440000000	1684081240000000	1747153240000000	1841761240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xc9e4dac3607f0f5f821ce496154dbc447c7debe8e23b3fec04a650f0c14c2addb05586e39b9dd71096a997761765d372f7a1ce9d68569534226aea61b59f2664	1	0	\\x000000010000000000800003b2fdf09393784d77f59c3d9e5ee82126c1e8681765e2c9a1c0e9af43163d3f91660289006debb9e959550983796b487aec164af9c31c6e42f01a16e20f7071d86798a05b59b80c77e787f6d1a505daae372987295ed6707a5191af083770cf407f0ec9ccf1e1713f20b7adab21db17708df7fcdaf1cdc705f95da1d454e3358d010001	\\x9a3f35abc2d9c3b09bb0e5e9130f81f4afc5d1205866cc00d9161cda4ced6762379c49bbddc78d89212a1da94bbbfd18512c660255e481d07187e6c240b00905	1665945940000000	1666550740000000	1729622740000000	1824230740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xcad8dc4eb155e2f69478ba7e378378bb90db624bc8eab11e1238cd413d4ba1e67e7bb43b57f2f1674355bbd68677f1ee9aaf2d9e3498112a4df18ff7d1e7e76c	1	0	\\x000000010000000000800003d6b95689337d671ea613f1fbb1658259407bb73cf541f44d61bebd230427ee0412ea1d6e4e69729249567eaab1f4f56bffd6d61170630cd89dcac770bb39c80bae414d14b52553e6a0261cd4447424933c38ffceb93df3502d7bd831aa2944b263527cb3542a910a1da7f8972092c746ff8dbf159b9bb7dd8d8ec0a1ae68e4cd010001	\\xd4074839c4d4115e684a0836c5bbefe645d20ff9bb69ec1341abbfd27ec79e498e0775e2c645b660886ceb5275a64315586a164e336f272da5cfc74921b4d50e	1656878440000000	1657483240000000	1720555240000000	1815163240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xcb8849842c1a6338d42e17fe75d78fba72e0ecb28056f3b67abf98f46f99e85145be8dc6fdf0ef2c6a41e7878dc784804a33e2c82504665e3d80f2ce00a46040	1	0	\\x000000010000000000800003c1186783027e8e41e4b0fd994bffee4b512f098ec0281b78403be56000a7ebc6d2046fcbe212a2ad737104a205e33a023231dbc56065af5970df21b6c9eab5f94275ef997869f6e91bc2e320ff2360e76deea96e737714108c27014cd3c80a5eb2652ba39b19325be542b57aa3aec92b3b942f2f3400d0be85324e6e6eb6b763010001	\\xe8da605d2f2cd0622b68b1a75f7861b51b8d7de2fa40dc1d31197a7039c4a3fcf50afe699c275353787d8d746506677d6074de670bb91355bbcc5d6a5095d006	1678035940000000	1678640740000000	1741712740000000	1836320740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
86	\\xd478c1cf9b69810aa74988e387859011fb5b6807062ace628253b02d5e0291371deb3124f7db1751e2ab392c283c9f19bd17f0d240ca7e54eef195d4c86d359f	1	0	\\x000000010000000000800003d02d9309721c1878241730bba8cb354df680144775ba727f1967b93f5c69eb1edd3730e5bfd0ce2ad5d41884f22580206255c2363b3a00e7134c00143710a2722f360d720c5f2dbf949e80feaa16a161d6a2fa8cfb369888edde8dd6e7d01b2a444f4fd69125948afc3357647308422ae3ffcab3ba3baf125c9ac0af17d8b4b5010001	\\xdbb7217f9cb385e7b26b149fcc0dd9be28cbca1ba20de4a43cf221a5488b151b4ef76e3418ef01f9cbe73303d00734128b9d5a4d330aa89caf02c7bf9c088300	1669572940000000	1670177740000000	1733249740000000	1827857740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
87	\\xd6807615fc1d9f4fcd4df03ed30917ae79b4c2e74ec38ae132f38785ae2352c553aa92689ebe5087abb15f45f8ce9717352dbff5cccfb02d12fe42543b577b5b	1	0	\\x000000010000000000800003c951e0e4dd970cccf10a598ec32e579c04265b3a1d215d80e6df29a702ea00acca7db3ef28650c6cf8c2a0f1f3fea9eb129292177c11430dd65a11ce4ea43f8431758bc8bacd8cd72b2393f420214e9c08e89f7945d73992eb72bbbb37fabb3157672e25ce15b57c2997f381e381e388f91eb0e4624696403c5efba410f7d655010001	\\xe17f786ef00a86867725b6fbf3629f4b5971610abfefeb7d8f22df0bcfcba9a318f0a8b6f633c1d76618c718dafd614598dd7fde12728f0c980ad7a5cb4f4304	1674408940000000	1675013740000000	1738085740000000	1832693740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xd7c05fbb7cd579bfce993cf0d81df13aba7ef650e473bd07f106caf031dc4a0db36b225acbc9aefeebef6de05ffaba32b8c81497bf40d977248d03be78b5ebf6	1	0	\\x000000010000000000800003b9b9f4399a996d169eecdd377ca2be67c7ac67fe314b62955aec0ef19cc27d7430afae7ed48dbbdb4ca597591e3ebc6c78399af00842dbd7f7533c807742d3cc7b1d32d5b413f4e16db9618a0e426a943c575fde20dc5e0e8800f8e5ed73c83e8ceababbb91bbf4322e8a55ef16e37bde49c495b0073477c4bfdffd9508ad543010001	\\xf6b3b1ea49e9dc14c1ea7f9bfbfc6ab6056652b5d2d931c290692442f71c852d0eec0972571dc4f9df5b9af0faae694a23750bc10f3b376af6514fb5c95e680f	1681662940000000	1682267740000000	1745339740000000	1839947740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xd8581f13ed28b10d419cf317fda5b32d17e3955d89c26ad8f04625e38ab87b53b002ac566c36e37ce596e7e725b899add896f3dbc6c251168fedf8531f522f6c	1	0	\\x000000010000000000800003a5f82f499f0285b01864f2f77e2c1d38956d776a82878623d11b3e86f4ee081bbd2d5588a3434cec46cfee5c6832187ed059a518bac80cc8f139e44998769997efc8f8ebde837454c475adee7a5b8bf7c9e54723e8a1fe214c4be0e0a77ed767355ed1026ddb392371af43debe7b41b6677983fa447017355a07ace3b6a2135b010001	\\x77e604eda08d9b37c3bc016d69614b217307f93829c2e3823ca47c9baa9211b1f47d35c97da92eb9a344b2bb4c41413d5b44391ec5801b0a1a8f6d4943747d0e	1668968440000000	1669573240000000	1732645240000000	1827253240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xd9641abf8a98fec7a35e9428f446cc1ab9c7bfdf4359d05d9dfdf503470279bd2aa5cb5a8705333500df65e339de29a7f2896e17a2d7931066aeea140efad007	1	0	\\x000000010000000000800003baba705f63de87c733392dbc654f65b6da1b1734086ebc03988394da1b1b834a4a3a564c6e2d8bf9667fca24c9b8db76a2ec10975d021b48a2dfd4372203a743c1e97960b6a149e941c1f416625bd81649b389e0d772373c11f68d60c1b70eeb4f1fc69dd15f1d77e959f48de9d0fda6a999c2eb2912ed6e001d401da2d79a31010001	\\x0dc636be691e26f2e50891050d7be89550dd250df86df09512c124a8fa7d63fbeccbf63ac0ea2d734aa1c41e404d627f68ac3f47c79bd1b6601a253569edc506	1686498940000000	1687103740000000	1750175740000000	1844783740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xd95877aa7fdd55e2ba055e50ee21063e9cbdccddd80fa3afd3bcddf5bc5c867f6ccff378b5352b9b6542386bfc2af22689ef0fd186e64f2986b54ff2e158be5e	1	0	\\x0000000100000000008000039992c9bcedf3cdaece9d98d50ac57d31ad639fbf98c7ecd8ee962a09337e9909a5aa306f9fd3cc05256895f9d399cac45612de01e77e0b94129375b6f9fa1e90877c10c726c6fb8fe7a58397c40b332e2c957f541a7f591cbb458b8f2ba3a7a3c1ed4b994c1648ed309ed7f4cb8e470bc269848bc416b569997997618b01fac1010001	\\xca6a1e1d7f167827c1c3c15466f491681954ab9ca590a249e42186199221410fea35e3d0624ae6f08a7625eb59f52eddc3012aaae8dd9bf973f11635cce0cf0d	1684080940000000	1684685740000000	1747757740000000	1842365740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xdc388c190e4a6b4b837d8b9be86ca55869da0ac0a791d8bb08faab8edb86dad9ff873433620a83e137986d45311e8419fc0939076ea9c2dd2234c698d52cba4b	1	0	\\x000000010000000000800003e0b04f8b082258122033054c15498c634c50401947a1a240037c3c5f133755c4f810d62d0858ebeb9fb05537dd0941b3e8f94d7d5209e6d2bedd050aed94befc91ade87ba63c5d93a9639e32bc8e22749bb7285ec38d88abc8cfe1470fd9cc4e73ca819ea4ca4026c21ebc46a81bac39f358de80770217d26f94bcc7e74dc429010001	\\xa8f0839328dc90df74b34b8ad08cbad4766d3a8e8fdc1fa87c52c421c4240cde888604fa52b3720f77d2f4115d6d6630bd2f596c449d38b35135e8372168c204	1675013440000000	1675618240000000	1738690240000000	1833298240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
93	\\xdc9c19d46d2edaae489e0c34ce36387d4b689c6ccf9cc477cc0de112185eee5ae093d8d22afcfe8f02206cb52d97d51fc7f8ae7cf407a47b9f36ae6917b4db8f	1	0	\\x0000000100000000008000039c4b2178d44f7034fa687bc745b78217301fb6d8ae7cadb86b73e1257d759c14d8748bf94a911a295646dbb974b0972278122eedd6602d4a5707415e9b7050f178340d31905d0f02d34fceefad36fd604b7e2b6f23c4d8602f77a6e92be465bbd17925934294ce136dba94a473e8c1f36d4943984e3d5f84d951423edcf4ef63010001	\\x3fc1ca908c7af84e0e57409bc6976cab8b62b5cd04e209f567e08b1b4ada2d72ddd853e02f23f726dbaee9ab7b9c679bad9ba27e4625fe49d3bee9d3ca075c07	1684685440000000	1685290240000000	1748362240000000	1842970240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xe170a566942d3d8572a6566f2c2d52ddf6be4f54446b8b5aae28ebcc64dbf2bdbda1f5ba7ab768082d356139e9f679aa086a8b8fa4835de030f270f4e315bc8f	1	0	\\x000000010000000000800003ad25ac51a2732419826247b6b2f180f158edf879055447feffff5670465725abef7ac5a121fd18fb67019bba1035380f313f93afa3ae7ce358c10a2dad6cb094b0fb6f82f4da04a9a9103d53cbea998631a54c1d1bf219a6cc58904dad9e22eab35ec6c367d638e99debfdf347404e5e55f46e2ee6efd5894f6fe61dce0a4389010001	\\x9a8fc48731f7122bbfe9ce18cb52f9a956fb58b49e997c858408834aeeac92e5f9fb9a3006401a540f85a4120894ae30868b3d552704b78065a474cb04688e02	1680453940000000	1681058740000000	1744130740000000	1838738740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xe550b3f4a351ece3da7f237d6604edbe557a9f04e9e298f5cc3322e78e413d5c88087fcfa122e27c0fe4801508ac92a99bd917b3e753064ded3084bf4e42aaf7	1	0	\\x000000010000000000800003ad55875f2b8b74b55e27f6bbb6e88e9006df5a793cc88d7bb84129c4a0553901698da0b6fb9e9fa9a0964c8e3fe57b3cd8e19f21330cc53b5a2394f9ff200be4d4846150052a145891401420d7d8fa7842de33d4b94a9c1c28ac76ad5980f7adc373aa288bb5765d28b44454f5a10427912964848c69e6fe9878a8fad9e18b71010001	\\xd326c1318834de81f5c4f5417d640bc88ede0b5a671599bad47f5d6c71f708397e61665883a7266b5fc3960b6e0fac5796592d63aca7ac1591accf7bad9bc703	1672595440000000	1673200240000000	1736272240000000	1830880240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xe9043543747039e7160542bdefb38363e1fe4990db8358ce55e516007704b1a0f50513517ebe0fc2167471df2eb02a69e172b8070c5b2b6788cd833be996fb6c	1	0	\\x000000010000000000800003a2796a496be3495533ace3c6825f533a4854570e7bdf570b806bf4e7b26012e05d51c8ed846fd4820c8139aa86e38865968719d79aecb7286fafb6fdda9c544a4f4a915b65dce1133bb1d6e68bd52c9fc715b360e605bc54438725766dc3029004b5774e4873bb65367c1ffcf496f3e9817146ffe0c8196067709986ed444a37010001	\\x481d3ded648758896441e01131527229447f999b935f0cfbba92312c9a41cabc8383cc7d9570034cf01660d1a422c74b6ab0da9869676929c15568f109be6e03	1672595440000000	1673200240000000	1736272240000000	1830880240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
97	\\xe9e4843bccbab2f33989910fd01f8c7a5fd167dc21c151fc0fab265a0372740f49e9f26f166a713e743c6ca18a37c54531b04f5eac7629d8003b35bdc6b03e42	1	0	\\x000000010000000000800003e460346c9aa180483b76570ee794a6ed2b602eefce59d374fc70bd007f9b4a5c393759294649851b1d6ef07b1f32a2d9dc1d1f3b65e9ad72375c3bad4de506ef75d157cd1bfa2effb3fd6f7d61ef4897bb06febda4bd55b079f3673741cab25d6b5bc1d8297b4bf9eefc0ff36e9a329e6b1de4cb83f9abcb07cfa36d68b9dbd9010001	\\x86be502af9499984c27041f914120b9763e0a743f0253fcb90b18c1e5163b209e5e6323210fbb67f0e56512928879b4b396c2a7c28707662cdf1a854db63480c	1681662940000000	1682267740000000	1745339740000000	1839947740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xed5c054c7cb78b6c843b4d111a47644c1e1d68d0b1efa847c6712b5e6f5b1a40db084f4e724909042d8361a6af72ee07f3b15270d4672fba86480646b76ebd7f	1	0	\\x000000010000000000800003aee3d243f858f2006f6248b49e9649bcbadafbcf700390a0ad44d4b0f5058b2adfa0fe3342fe6d0fd489ddd9d6664697a6dbef2b5b2246030255e2ec707e25db271193a89024f1485ed98f3b4c0432754d273d06d26bf5f860007af7a973d47a58dfd3a2b65d5d9843a8446cfa5dd7f8b43719b90e3c8d0adf9fbfef86ca01a7010001	\\xbed099a7dbe6515b34ca1e3dc50f5e9f7c433e7a64faa230c7a86c0329d359ea378ddcc10d8a3ab32853c208a83f4c87df036e677d4093670d34adbf09902f0d	1678640440000000	1679245240000000	1742317240000000	1836925240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xee84e1f2b79784f1c04f70e437bfd677253182a6bae57fc81549a919817edcafa0853810c886459cab634787d09514a806d515e4c0cbb1aa5bac7014e3d7560f	1	0	\\x000000010000000000800003c268ac0ee542bbf0cbd83fbf54d7017888bb1b98d70e5a55e98fcd6a092829630cb0a405ead0112b4a22ad6392a99298621ef7cf9866674a8bd810f40885dd3df920eceb3beb05f9a2e65b22b6d570bb773cae4f09d2d6777e394a0430a97197e5300f853a10c21d6dc127def13051249fce9cb6870e154005e63e979aa98d71010001	\\xeab842e7ca23ed360b17ad615db8a8cc357693add00d0f48274f1125faedf256fba2418448a25a9670df68bc0a85a3b5a7b1dfb9e104c57033fd92383fdf2109	1675013440000000	1675618240000000	1738690240000000	1833298240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xf4dcfc34b2e278a8018af00801e3355524a300bd80ddb7cc0c46a87b8aacb4f319e023604bfd4b333a93d30524c0ca3e5b2a7dd40e26bbe2e00d045a874f1a74	1	0	\\x0000000100000000008000039b2261adf15b62d99a49a94f667a8888337c29ec7c20c9c87014c04e9f69a610857a94fc4534aea9563e7092f634935a19ff8e0b710a135dac84278f2a56008c1534b5e0d15f4d29e6df6637c141d7d38524c472f923bed4dbe4b12e3be59c1ef089cfa7ecbbcb5e6079cb6a0416f719c4ff437f041aedf2d45140fcd1aed85d010001	\\x8c96e1cc3a80a7db4e890bc0b3ec10c9016bd35e49b213c0a89c6ece325a324a0e3f15bc661d266320992472056e7e31f97aa823075465fb530efdeafbbf5205	1671990940000000	1672595740000000	1735667740000000	1830275740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
101	\\xf614e1c567e42333ba7fdc45b00b90c07d3dfa193e7b76059d9be7a13ba339992cac52123d0d69a2115d87d5342f615a2f42271a1e6dde36c6425cef73ca7609	1	0	\\x000000010000000000800003a4b739a5720ec219f9f0d89fe9e28ee4f8025775d109b8ecd3005e9475ee03e1f52ce74323b1132539762c2a24e289e9ee75b314502ba6558c809996a3f4c31aa3a9287a67e5459b56ac65a73faff92c8c8ecbccbb0f529231f48c04270ccad8f423b5ed202fdaf8d551bf08a062060e4b5a5edabe71c0b0d4b53f178a5d43ff010001	\\x9017605bec9ac465e4a1c639bdaaaf8ba7785f8cd6d13487c99ed1bd45e242949aaf0c46b676972669a116e28219876159b6548ff027479ef5533885dddd4d00	1655669440000000	1656274240000000	1719346240000000	1813954240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xf6246a74e68966d1b5379ca8598de6d7adbc976faece6e30c22574402dc6cbdca7f749553b51c8c4dac97987d5deac6d6fee805107137293ec2ddee01dc2f34f	1	0	\\x000000010000000000800003a8b7719a0534593de2036b9198ec96cecaee3af89593e4cda7100cf29229dbf7c776a70105640cf7fd5d69208251ff5100ede8390fd1e062f6fc09a6eaf0085aaf6d8d27730794068313c43900c4ebb840245f37eb5c22b4eab5667e0e14e8df47c1b7876885b390542f7565b13675d5d11b92a4bccfee479bca3b2bc96b8caf010001	\\xbc6f873d396e27553d56bf9cb40df57cf5b04b1b34c90b93056097fd3565d0ddb3ebbce35bce310ab2f9d514c4e363ea585ce8424a04c101315a3d264e2ccb01	1675013440000000	1675618240000000	1738690240000000	1833298240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xf794ae7cdea9d6e57475b0bf8b73cd7e857317dd90d14887d606257b8e8c44ebcc3ede90ca325ebc226fd137e9676d7b7c93a27f18b9888fc18c85e16232b5fe	1	0	\\x000000010000000000800003b1aada990e472ea6789c3530c0cb19fcf39a4974249474f8ed53652f2933eab7ff2b7475b4deafc4a8823b7570a3428732b4fe700c4864644a7bac940b9a1b962322b2f4a2e89bbf471e79553f56ff6eb520565e2bfe0bba12edaba661bdbcd5164fcbbee9d33291b479fab2bfb9ee878c71bfaddc4afe6e70b1790168ee8aef010001	\\x8ed6516b6290944447720cf78e496d1c683db7867eb2beb2a0958c2114676920e4f944da5ddc8a0619696cf4a4b0b5e755ebcb8074819b764fb7c3a2ed21a503	1661109940000000	1661714740000000	1724786740000000	1819394740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xf994efdf50ac8cc1ba5b60d2fe5370fcef53ce2298f7e959e4b802533db1f150607422ddea8a3b3c5f39c8460ee7b6c8b74cdc1f6bba7f5506a9fc452eea4b0b	1	0	\\x000000010000000000800003dcd3b163caa4a60a442a7e60d4ec8a5c067e2b94a0be45c238f494017f9c83f152d43073401f2589cad401dee03487d0e730d66b5b57985814d28a5ce94f0e3d340905e551770418fe02658d44ff6485e9a1c1bbd721f6e430608a2e82dc5fd26c364b0a277f5cb4b6f3c96ecc6d3dc1e5aabbde713d6d5bcb06ae23dfd57c07010001	\\xbb2b72a27a1a22fc451df6057c2299d7adb64805e284f8901ce7a21d0260590e34ceb485b5b7f8f5bbbeb539db6a2f9f792bdd9fcfd53902d52df4cfb3e3a10b	1667759440000000	1668364240000000	1731436240000000	1826044240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xf968e9bb257f1830906ac40d13313c67e3baf5566765998be6eae2d45bd03f59444f3ba9ff0b8f87fb1e267e8b0e9cacd55dc5ee35e94307f6f523e0312c5c00	1	0	\\x000000010000000000800003cbb730161303b7acf4da99165e8c80301ebcf54b69155846ea06f7de979e10f7c84c5d8b3b21e0fcee6d7736c54c535173bb703aadf016aca4598c4bdfe08fb560b2d769ca8a94d0177cd270276693580ede22860d472d5ceeb65a7f927c39d950ca06658cb2959b01233399cbaecd4e2f06a3fc9728e53fb7f665af90f9e009010001	\\x40e106078c11751b095105a1a44e947347e8ac5ed7275eda79b070cb6d347eeb052f8029bfae375bd506beebe343882a8b86277bb37e550ab38511e5c14c8906	1664736940000000	1665341740000000	1728413740000000	1823021740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
106	\\xfa187b3d39272796c430b661be0d938b22d99da7e9e47990a097239e477171d171c7367a285065040f76a85bb4ef732d7962266fa0d23b67d1b386ae587c3214	1	0	\\x000000010000000000800003d49c9ab0c698b55960c313afbdd253bc6d0926542dc97dadf68f939e39f854a75d83ea9075121aa8e014bff77a545f56a3001750f99da13ae249db556dc9e529116d91355a41ea2f1cf2a660a569dcad3ee92ad2e8701cd9591c7780fc5c9e0d0eca809bb51ba6fb54bd886aa7c3cf4df9969bafa822c3ea8d818c8565304177010001	\\x926466614c3848c5e1e106a8cf3f2e4ddc25bf90a3ca7eb9edd925cd84b46ecaa3814f3205b7df65cc9622282dcf842a70daf23ed8762f718e2acfd54320ca07	1672595440000000	1673200240000000	1736272240000000	1830880240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\xfeb87723a75a68c6fe38c55d7b434544ca23d49fcdc368331d8a9da4c91edaa36aae3341c8059b6ff73e78d9e17214cf9d15791f00785df687cd6b053be68074	1	0	\\x000000010000000000800003d3824fe493982dd843a0b924da3ebdafbf79455e1a7b82a0eb405db96a4f281528da2425e6889235a8d47547b1fdf6b7a637f5f2c10260e5a083bec1c87974e3a78242bb9101cb47177591867954f5d34b831c54fbe580bb67cb274afd091360d2077d9d827a3cfa24a83fe35524225fab8c2fb79a289b4cf71be53446fa1993010001	\\xddd75170e5a8185cd0353f6c7078775442ffad1ec71ed9ed5deb8851201f89481f8724bd0263683619a129249014113ce1d1715febce3a222433530fb3724209	1659900940000000	1660505740000000	1723577740000000	1818185740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\xff083865a88d8196758dee7fa5a2912e0f405a6d480004753708ee7329bba0dda3a18ca150785479b4a58c9a183caace6fb597b0ef9d748b9577059b99e7b5a3	1	0	\\x000000010000000000800003c76ebade6158c4966073b041959adff19a787c4ae2bb7f55113e4bcb15e63a3f80a8dab773a73b25f09431c7d4c69700d77bafebf6acc1127ee4cc442bec3f654a6e662d6036c52eb124bad05cd510571a52f47154d947098468d7630a34abe75bba77c3a052731d2ba292d97f46b169450a0d2f843802e181c18312214c8273010001	\\x76636510cd56424fe17d562191f39d633494979a16ed519ee67ec17fefc81e83d639539a6a6e6cd08b1b531c2997140b1bc3b110d9030d07362219f150df0606	1671990940000000	1672595740000000	1735667740000000	1830275740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x01b9332f16abe313103588ce0ca7b9cede536d7b511a2e4716d12946f3418ad5dfbbee0d7c0102ca0ebf5bcf88f8758b433dadff312e4efea36697552d318a38	1	0	\\x000000010000000000800003a6a8296a8017c589b8906d8ad2a179ad291efd46918c3f36b015f78c0bb451f09b7bfda1dd227071271d1618b0624407cf64c8aeb0f853ce3b5978c2f6a71d83a2f9cfad1ecd12ef3f0442b2d5c9b95474949e841fff33892d931e61650882303d8f5341d56589db84e46f6013453fee7399895663c2171d46db3ea4b929c5fd010001	\\xa8400b7cdd4ac60d6fe76a934c491e988a1635f8709c14f5f74756d67adefe71dab820d64241de185fcbe86a1f4a030441f1d24eefe469a38aa8e7537c8ae50d	1671386440000000	1671991240000000	1735063240000000	1829671240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x03610b03287f1006488f7d7234c1a38823351e2d35c6e4a0e477dde11eb8de8af990d28dd41712a386e8063f77f61f7d4fa23541f255e7aefae792c3fc76697a	1	0	\\x000000010000000000800003ab6af7600d7973a131294d0b39afed95ca90ae6031535c72738b8ea7bc60c649439536eac3bb8c039d2ded81174aeabea067708b707a0161c8b34bc48e0383fb54f2ca84a9fffd7fe64e135e9740aae9f6256e9dd4cbecb37df4f5a700ca815c0e53c7c8c2fe052d0ad79a2520d848fd259eadecb15913532ba27e87607a5959010001	\\x8ca2234de5dc9b62a0a905e09acc46065f97cc045bb8fc956ac79d7320bb00160d7d158903505ef097762f7ab9bdca2a74017b926f0f403106c78882db1bc20c	1667154940000000	1667759740000000	1730831740000000	1825439740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\x04911d7319e8d3121b2297f325cacf21a2b8a6ddc8f2db66dc7efb8e42cf7f731a7b760bdf4bc3b5e4c8e74b4c31e30d6bbf232b7227f01803faa0b48def65e3	1	0	\\x000000010000000000800003c3fb30e11b620d15783b7600604ae8fb7e28783d8d8a1b795b6c307ac0369b95609a35be157c85d4d5e78350cb92349698b46187050601499579311a60c46e8c407933b4f93a507605535ac2436d7c24054d59de635b80a7904ae802180c7160ccf01111601cd234e1a628be2c06566483fedbb5177a7a41c9d504f2c94cafb3010001	\\x9c82ffd623d0ca886159890256470c24ef09b0d930ee8b2fcd8f92c167ab69e1157e8781e1a3150dbfa85ae7a931a584875846645ccbeeffd224bcb8113a7907	1658691940000000	1659296740000000	1722368740000000	1816976740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x0c795a4d9fd513396eddc6b2cf53c2b863d1fdfa4b47339645991d76572baaf7e2c2cbbf842b0be6f9f3553998380e22c947748738055982bd7c98b875ce8567	1	0	\\x000000010000000000800003e505b6c352023409d102d8235f1618c974c22afb2a13451c23706e3d8162116ee043826dba0adc0b8b11583ecd59cf15086138dcb387d466ce597029f3141bd5ad9ae116155cb0facfb94883e30f088b22d2ddac5fa80254342b6e5dd2146e4a3d20d5a0307a8905a74c7bf9b4b2517bb787bd34f67989fc3be82e5ceba8b1c3010001	\\x7a15b58a1d4980db8f14f706957fd0e06cb5867db7ffa33c779ebf82399caf238d97c30f8d6d4dcefe12740b7053e757f3197a285b46ab7cbf73502d1e346307	1686498940000000	1687103740000000	1750175740000000	1844783740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x0cb555159be048686fe1adccb3a962f581dc3bb5e9da174ba237f53812efadf715f30f093ec083780c12aa293c55bec2690e562b5dd0868f6c511a7edee8dead	1	0	\\x000000010000000000800003a8cc864033a0da72763ce58214774d626d6393f81cbe4e0cefa3f1482c83975501a4cf3a9b7770c2ba18cb6dfd311f2ae912a3e89d035499a1b938e2dd3d2ef80823dfa3de05bb6bf1560ad0fd7f3a3e3b30b63240d05836351e1bd23156fcfa6a413e59ab1a9cab55a861b079a7f9cfb554acabff0514fe221304a2a5c2e9d7010001	\\x6a5dabe50f496c43527805a8e09c7d444bc79f61f63043163726bbba07edb2cbd460aa52bcc85e48dbd2f681e39b5bfb883d89e872b5aa2fde1fb17455121b0d	1679244940000000	1679849740000000	1742921740000000	1837529740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x0ed91d7cc212026b22e50319012b7af26397e90ca357f80b3949322c663f66f06bb6f2ef30e38b6272a143b25229d0df6c2e9e87a67a08dd9fc1cd7080311755	1	0	\\x000000010000000000800003d2d4eeccc9c1c4d9295ff051dd033a913fe21eb6a761ba86e6a764341e0aa4a83d04934048015ece26fbc49d7f0636990bafaa9ab7632a6c406a8a79c1b8a2e3b2327ec2a04e1dcdaf80628d75632f40e14bde37d4814fc6275f489b4037ed13f89355f558d90566400f56c3086169732cbe82ee742cc9c2b5941be70407a039010001	\\xcb5ae81148cc5667d357241b2596e6f10fb09d50e1ee5e37477832fd22861adab56375843ca243a6e7bcb682ae8b171964d652986b1fbd0f6f016ab763809000	1683476440000000	1684081240000000	1747153240000000	1841761240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x0f2186afbe1976b88c9205dab5d19e07c48d406f5b06928dbbdb8b90ab56f6d3b272b17029a9e3d0664d70d49d6e0f08950f43d916d708402f298e7e32813ca9	1	0	\\x000000010000000000800003aa4842772db1c42c55a22645152d6ce08e3ce47918a9820568ea85ab3e8d1a1aa6f861cf5b2c29ceaef380f69373f19d4ecdd59bc71e39051c18b15d4eacda59ebb9d6f10109a26030aa6956025bc109cedf3010240c5053948058a23673bd4124d726e7887cbcce59524c56ff558a2f05daed76d27dc76a12f54ee5041d4221010001	\\xe671a8e0be19c7e4f1ca4baae75dba5f55464ae8378be201741d3cc2aef08f0f5a849df567cfc050841bf49c7179094992dcda32ad317483c9b550c186422f02	1665945940000000	1666550740000000	1729622740000000	1824230740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
116	\\x1439e7022cbf5c37fbd60db525b57c1b7d5b54bae710257d5ea4367c19951fe5cb3b716523d9eea89b170c2f33efd72f593cb4effc7911c7182265e1c214c584	1	0	\\x000000010000000000800003e4aa4ea2c3cd350505733cb9247460c69bafa33fb3f383fad1d26e4400a93b45c29019f5732319d2f7b13324746db16250b6ca63b441dccd4cb92cea4ba04a925c4daee2eebcd1c1512f2587de2c1c8d7a6553ac17bdffec5f9633f085a0d032cda9103a32ac88ac89af324bffbd6f1222bc9b45c2082ed368490190c46805af010001	\\xea84287e1d02bf0bc20d0edd3756058e5df7e1778f7977ea0c798983463cd1d683468903f45c19600911c6764e01eaee13326eb92f58709e0c6e8f04ef56ae02	1655064940000000	1655669740000000	1718741740000000	1813349740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x1a2596c2f6b99222abe7aa1dd86a332b6f0dcd8cc22049534f1d02a7575def17adf498f210aeff423865a436a128e2fbcdf906b9c229267647967952daa74ae6	1	0	\\x000000010000000000800003b812a39c5f04333da91df4d85597cbc702a656c11edc5081d6bd61587648d53a24e529adc298e6971c20339f33f4456ea80b0f8b3b6c743c1afe6518371b83c70ad32238192aff5f36865809dc0f4ac68866bcf43403089074ec5cd9f7fb437be911463c78eb156df45b1ad9102f64c4ea4e3d402451584f9b9b92152c266ce1010001	\\x5ee9e46913756ffce24e81c90c86770d2e4e4cdedc62df125db64b050407775c78b1dd7362da4b718dc5c523393f5158670ba013fbd203bd1ba190279d3db002	1679849440000000	1680454240000000	1743526240000000	1838134240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
118	\\x1be9b684864f0dbb7b427aa67885106caced2c7308d4a46fb3b6c191453832c2020e168ba46674d302a68fddda891bf3669b048c8b43605ded79810ecb38ad11	1	0	\\x000000010000000000800003cae64beefc2eb918be00aaa5acd963c03d3f9babf914ab15044d83d0bbaa6789ffa4fc4c7d37dbaa021595aa60413f4292f78eb0b461d8ec01a395e157e868a1d56bf5a36b6410f0a6c67eec6d927c3fa762508e17a3c1b9abfce60d5afa23035c178cac0fa83d8dd936520347a08ae9010eade123e81defce841d449aecb9cd010001	\\xbe078dbfec4b151d7bdc4f20489eb7211cd0016fd1700f542dd605dbd4d8491ce1bbab0356c0d0f9195d84aa5a0185bb992abd6171c11c17eb4096cbb46c3605	1661714440000000	1662319240000000	1725391240000000	1819999240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x1cb9ec288fc8e72a922a342de5e55e9d8cde6da74fa04029a6e2e1cad92914a512111562bbe0e680fbeece6c4b8698148463c52154a6146ff92e5ff9f002d908	1	0	\\x000000010000000000800003bd7667be8b0d67d55394a715b0cbf658bdc10aed97130e393193d0e218a38f19e9353695d90a523dc1a87eaef5f1c49ee2f144b0e561799dd39f500e92f8e16f944385d1d709409330acea63b75d1aa3148ab3dbaa698a71dad5ec4736a7e18fce189e524b18035c69b3df05a3bb3b48f5a22c20426ea7ac44bad04c38152a47010001	\\xca2f43bca782c3ae81692d678faaa9ff6cc9cf52ea2ddc4fe80e54cba03b7a8f5468be4e710c6307fd717729c8eee2eeec90468e267db747a9c9ea979270730f	1667759440000000	1668364240000000	1731436240000000	1826044240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
120	\\x1dc50d5363aadf9bb461b9ebf8efdedc5b2897d3294a2d1466b26f3786afccefd3364ff044f3395f545f574a2a201bbc05aae72b0b5dc815e92c8da706d74163	1	0	\\x000000010000000000800003c0af8b004740bcbb4e32abfb26b972c1c2df5a92a0ff9bb2cf5bf6abc6b9e51c393f8acc23d12aef9983e78aefe463717c842e89542cdf6a5e172194f6fb85c198c5bb269050febcb6dae792d9095b9a9194640558164ac7baf7cde5f1962fde0218c9b671ca3558390913e1e7a435ec3f30f1c6eb7cc0e3efe5cce852228a93010001	\\x0e493364e192b3417ccf5c708df1a05bcef5fbbcd4a36a6524d0b9d5a8a13c103a29d4e7e0c09550360bb4086a38e11f484e40a2b42717805681e332ff631702	1667759440000000	1668364240000000	1731436240000000	1826044240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x1d1106deeb81a48e8b868a92756d1b391c04a508ae10cbbde1697ac825adcba42e247c3503479549943d955988c3f6f611a35f6e3bda4268d8f7ae6d2c84488d	1	0	\\x000000010000000000800003e4ae6c06034b4d268c39548e03bcbfad27bec720846872aea367671b01a10a9df3ebf27be8f7acad430a0a26ab9f5ff7230a33f255ca2bf6236c51e806811aa95f632fe63982c258b442a3b24c1918618d85fb58442adb70b83c615aa00de9050d81a4595ef336934d55bd2d313ef8021d6b4dbf996c8f7c196b56283cc786fb010001	\\x26b36032fef0e3b3935ef76de4d604e7a895ea485c032c458be3fc309ca995d412cdbc21c6f7f3021757231d689d36c5ab0dad79d5b5cf5f72f28b5a1c320d0a	1670781940000000	1671386740000000	1734458740000000	1829066740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x1da5e192368d760893858679c9108aa830abb4793d3ea368f7cf49b8d6a425f203643e16d02d214188caf491ac12984ab0ad6128a8cf2e02d5c3f5d1e3915bd9	1	0	\\x0000000100000000008000039605f1dc072152e8134a86a8358a1141e051fbfb0cda079cafe7b690195785d3dda796f0f9c85cb4cfebc3f321c40ad242482dd5dfd4b67878b5fda5b95f9399674731e38b261a7dbf892a7fb7a8b2af839d8c2bd6a29d24dd9a2d0039472038620b3a29c9b6d2ffce95fa292e19c296077fb68d4ceb06761cb6766265baba21010001	\\x8e24cba23ec786096123a925c7ea545bae0b99015a36ed077c6aa6bb3efd8c60874fafdf2ad5402c443ae014f2242d8752341c6329ce3f1efe56f975545c9504	1657482940000000	1658087740000000	1721159740000000	1815767740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x1e0d520c2ac12c6ff6e543d8eed8c5fd2085f8455fe5db4055b4e1b0c929be035ed8bc9bf0fd90a5956c9f68bb841581aa053ccf9cc8966b6ce7a4a2456e6f00	1	0	\\x000000010000000000800003bd2da00827150a06aca48034492acf74409db96f4bde026d66f9a730dc04ab70fb87ff4773b998cb4214a7d930966998c861aa4e681e7eac1860f89fc5c52f81be777472ba01ebe8a05b1bd514c5e49bc5a7301975c95b6f1a1ff1256a51690c1ec12493c1ea7400093885f8a90bb160cb8736196495ef0ac06e136eff488391010001	\\xa79a6d32cfad64bbdc97bba9c0b2620b55eeb76ed83af28979bd90ea0334c34c498bdc0c75893457a9fa1043457348541bd288c38377bc22f5d55936dc228f07	1660505440000000	1661110240000000	1724182240000000	1818790240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x279dbeb1311b52a68caba7315ea5cfef92e8e223142435b6bc00183fdf52b295dd7b7daed6c49f3097684c2a5ab238670340ca21bedc94c0ed5f711648f43fd5	1	0	\\x000000010000000000800003ecb045ef6b9716750ac799f45c08c8c170bff085122e8427c766efeac4846845e20f52757fcbf023d2de18a2ba15f24854854814d0bfe8f0d9668b5aa9404fb7fbd0c76ef4a1f75e68dfc1d404a159eef2425fbf1e99eb565d7ca0917b84f017b0ede9bba4b19af8caa9ed009cf849c35eae0c019ec521951f92760e73090db3010001	\\xa46ff0ef75c359b1450e2d765d35cdc0849f09c6d0ef2cd62212baad3c4148ec97c2c550a53a276507c62768d49be9e64df4380fe2d6eeff6e51dbe5b6572d04	1682871940000000	1683476740000000	1746548740000000	1841156740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x29759ca60e73b463f059fcc7f228cd6eeb51a3c89397d28483c0e33e6980324d2a745e3a798d6e2f6f89d95e67849a67a15d2b48c5fdeecfc6463015377d554f	1	0	\\x000000010000000000800003c5a020026e58ab0130b72e03bcf27ae223b43a85d02e7a385a078fe4a02ac24c287edcd88bde3a189ffbec5fbaa3a7de7738969abc69b87a39427e24e2cf5e6821329471ec44c3ce8ee3114e069ac1ee7c881dcc5c4fa53f940a0475f1a2c68c7f52cde792c7e62e8ee19a8473b436d866586fe69f371f915829600a1706cd3d010001	\\x93a6f1ac294bfc22e211f703bf6ae513164eac3e3e8a010b3725df7ff1747c905962267ba097333a778ec1ee225337a75dabe9ade0fbef7b4bc49d06375e320d	1673804440000000	1674409240000000	1737481240000000	1832089240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x2c49b8b5cfc7fe220202011138063995aaf8978f86365314f89f9ebd36529f53aba4b7de3ad6fb56b3ad61d35f11091b7d62b62347bf0b45c3a23786f0360f08	1	0	\\x000000010000000000800003b680a823b33f60281383d06ac7605e71e9e7b42c64d2ba319e79cde403f8b8757054bced8cc4be4ef517e7e3f4d41ef357f086b129ff5d61e3887b129224072f30b62f67363c868a82d83ada834b61bba96093cadb797edb041eda3f941d8a72f3ede4d0bac63c49b5488656021b7ad25399b69520bd2a8f428ef268118d5ecf010001	\\xf986799aac226039f924ce70f2b6c479aa55aa6eea383fcd1f6b5c4679e0ecd87ff124951def6a7addcf9c00e49439dba9bc1b395808dbb8bedc99fd8e8aaf01	1661714440000000	1662319240000000	1725391240000000	1819999240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
127	\\x2de51f4b28a479325936d7610cfea553f5d304fb309696921bd9999b5d6b267da8fc30b112b43fd5205b12df0a0c8ef2cf6964ea2ec58a52827ef70091112a7e	1	0	\\x000000010000000000800003e8fc646e3535efaeef2104cd5a1f06887878085dbcd5d04f356ec93d252b2af9460914553f80fb40b40cde774c124f0480ecbf8b78ac9d9fb67670d50cb1b93965069d274bbdb0598274836c0c187161c8aa8136ebffe83666c064e7c85e176d344853ade7d5821fbebe72ec0183013db0cab7716184e8461dab9643b4d458f5010001	\\xc8acd1a6c6eafd0f5be3838adfa8b6dce18fba68472305d4820353561189c11e552f968b365c976330eee2e291a56611fc5fcb862b26e6e1077b7700d4026500	1660505440000000	1661110240000000	1724182240000000	1818790240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x3075e992a5793b284c2ac40fc5dfea6f83d9e399a3db1dfa86d4f20e42b73ed61ac3b1137067e17bf4b8512885b63a623af90986d636a97520fd04465e41b4d7	1	0	\\x000000010000000000800003b43e59ea77a7b2a11b86c065de6fbfef2389a8fe862006637d9a74685d4019a97b4c12c47e1de60b8f0a733c2fbbd48e09c03653f27d593e4e5d8e613b000ff71125de65a82b98c0da2316e36a577bb8934fcfe4fca1e8296f1e01a159cc3619d78e9cf5f4b7bd3357a75bff37c678b8829cc1b7406b9eafe7d57a81095ca1c7010001	\\x9e3b00c367915be411ffa91dd75247bc00221d923a838becfe08eef9037eb5d210e79b8cbbd6a1ed8205afd24bf1edf7f60297a4cd5ae9357f318b2cd41dce09	1663527940000000	1664132740000000	1727204740000000	1821812740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
129	\\x3379eae1dea680fcdae5347b8c55f102c996dffa8b8a4e3daab90a6dce74a0184a0cde609d3321dcb9cd255c8256865006d85011c5b7ea790033ca3c904177e7	1	0	\\x000000010000000000800003a3a29fcbd6942105e0151325c2f81b0d40ee26a8006be2a31bea9f1cb1963bb4ac16d80b52cd9be2e576c0d11cfe1e20277744b6c69f640430ab36777a24e44128931ec74cb2e990b0c92eaf746b312f6a08b3d8473fa78ebc871922c289419c4821ed8a3c2aa23d16cacec045ee22cd6a9c9af89a304177452e63b10ef8526b010001	\\xa2c62294852bd4d6fdcdc1cb1d63c46b105009c612b813541ddbae735d68ec54005e3c23e25f6eb09b964219a2217ec0824bab28462ee2d7b32595210c343f02	1674408940000000	1675013740000000	1738085740000000	1832693740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x3489ad64ff4571ce8a1a90b70ba288bed6562cd4ae2cabec69f24d0ba7788b0e233d30f37e68c3e58c7104b498fcee83f52aa1e1093224d7b6b9dba3e368ab56	1	0	\\x000000010000000000800003bcc267d963c0d9c8de78367e0388239b5424bff2b5070da585bc877f7fa98408f13af170b4c2c97e18c493b57e82d45e735997edd81206d8fb2fc0bb3599126a12fd2e1a80e93f62ec14e02c775dba6df1ba4cb683cd97641c8aeab04d5989631963ff545ba0819c7c2be38fe193a1b851fb42a7de307cdd4c068b0a700cfdbd010001	\\x69647a0326b49e2e3e30a902c9ef79869e18c2cea26ce1ff46c96b74685b1443247c2b0e329e69379d1054cbf4141776e1f68295273308bd38aae7d25475450b	1682267440000000	1682872240000000	1745944240000000	1840552240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x36b5a2acbdd6a2509ee8827173f09e0f240efeaf59084ccc66552368c78aed59c5e6f5214e4db9eb6717311fc81a0c43435a8f81293d9d07a597f02263c8d55e	1	0	\\x000000010000000000800003b1ffaf6ead42e57d6d7bf69d49af934cb47c4307eaf27c80d0cb4508568392fff713d45de36ced1f9caf180363b33faa39c83e7a02f792bd763e52f7f42a4f4a69f4ac71556bf7097126ca35f3e2f4ac5f5a9430caef8c87414a5daa7f003266fd8645f8ef3376636e8fc626727728949f2d7fc46bdd8a70f387b8ae67c84c65010001	\\x2d1ff0828c5eb16ce8703fcffa20d39e7a7015b32e5c5bbfb302305266dea63b771c4aadb3d0f048de95d8e34a54b1575d913b6599b0670f30c336c8214bd101	1673199940000000	1673804740000000	1736876740000000	1831484740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x371dd9e8ee1ce552f1a7f584da1d22687eacceac953cbde0c26f0a4f32516d185dfc16f0920e54a9938d3a4893489ca58b6af02974c14ae534022e9e3b80e914	1	0	\\x000000010000000000800003a32f4f6e505d377b37ca58dee80782d7dbbb754c7f7a8949076a1cf67f72d58b3a74cf8fb1efbf22d31faed3c86b3b5c2bc68aaab5edb53ceec171947907975ac1167ca6cbac3ec2f7d72cb89579fb475ad3d459a180796ff37c1436fc50dd04dde885c4a32887ee830507f4a798580c7cd62d04080fe380d98460715c38298f010001	\\x31c1e0caa951291313e5c3fcde9807d428456bc78df4c2fa9fcf54d616afa6775119daeb57ebeb4d62e4340f35a03cebee058ed7737eec6646721ec7164bf106	1661714440000000	1662319240000000	1725391240000000	1819999240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x3929860375fdcc6aa9b6776c2eb96c6b7a9e28c95f5812945d51038ed1d45533b13189911788e3025741c27eb0c764d46be825d2d2231a5dc6a889cb3fbafbfc	1	0	\\x000000010000000000800003bd7e7405d289d5400feca78b1e6bc0dcf0a324122bd7a67188ab6747f669d3b105d3569559ac8eed1ada934e5396ae0d3d3e26747b12814e416388859654f35bf81045ee351a72db71831d2eb6a0ecd9904b9e8b3dfea8b7911db3f0ead0abf483657f435994bd9d13e77836a561873e9610665b4f160a53f1c857272cd4903b010001	\\x090c94920085f84e9e5892920d8af22add1cdc436cd1ca70681d4dc1a0b134405f9a9a7891855bc60969a765a02727b92dddc6d74dfccf3eedbe4d52b20bbf0c	1682871940000000	1683476740000000	1746548740000000	1841156740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x3bc5b5c219710cd1249005a2c38324187907b973b558c813663a770c77a8020b349b917a136882e2feb44de10e7eb44bfee6ae930cbdfe2c4486bd013976aafe	1	0	\\x000000010000000000800003daf440eec4950cc497a6cdbdc62a2a521e52ce3fd11a830cd80d5c3e429942fb5f7d9561e268f52f2fd8ec13c92faf7368c016a4efe599b581b4f7e1eab2842f29a7437d4853bb27d1fb56f576ad990289d433b0f21a51455d492ee22f13ad7905b329eb7f0b8353a11bd103632ff34b26311ba725dc67f4f74712b6fbfa8a7d010001	\\x5f6f84f9482e6dc87c8e615df3b1621478b20bdb00de66faef7d9c8bc521f2bc2e833edc3ad1286787de1003881faa736592184d68092c0c83d1924fdf72c20e	1671990940000000	1672595740000000	1735667740000000	1830275740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
135	\\x3d65ace740b478430f334ac66b545de3a36501e7733f2d8c8148f7b292cb059e5db4429bde23e72643017105d83a3a0239f1dbadd45fa0afbe3a419451c993b1	1	0	\\x000000010000000000800003e27e639ca0a056373f3b6d82d4b66a5fb91d1bf654af66aaffc1e02b1010ab0648ed672698970809365578ed44502e503db9fc64339a17631f9e6e5f237eb9aa668147452f754d76f64d6e2cf939d578ede84b4ff08813bd6095675707136440890b34e214d7a6e09d2db8d6236926acf1f1898394abd4fe025ea2c4a98ea4b1010001	\\x1ccbd537399a14d3d0de9ded5c64b10138ba8f943346ab4b9a12007d7ceef2037c66c7a71c35cfaf934f688772a699ec7a41107bfaa1876c14cca74c29228306	1678035940000000	1678640740000000	1741712740000000	1836320740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x3f3deca0bb48450b875bdb8e8e6522b38f454f1c1945cd768782029372e46ac709ce0cdb6661938544a7791a3664a554efe714a10b6a43083085d93b5c8ee204	1	0	\\x000000010000000000800003aa7e660c5f7db8483c629c1d30b83236d8b736ce7814a362c026eeb0d3f0b5e10beebafccdb5d86ec878140bd893c26b115f82db7f81822158f4033ed360befb36678642584c5d7f52de59259eae1052b24494e025292675543acd99cab2278f1c5c6781132e74196d73dcffd74cbdf85bc6a00e18ee44cdad75dfaf87677a8f010001	\\x73402ec61b104b8a405d07187d5d957d040a6a67c860e6c3e453fd71a4665ac8300edb9e51a64264a21d22091c564ff675c6008f6b13478942a069d07a664908	1666550440000000	1667155240000000	1730227240000000	1824835240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
137	\\x3fc52ddd9a1e0c7996475c6767b881e6c879981b4aa6dac4b2d9a176636c0a53b53db3f39942426ec8859b194c6af35bf0e63a0ae29af4b14d93a9f0c6381d50	1	0	\\x000000010000000000800003b1e5ad41cf98c036e32961fbb63f25f95a28023e17579733e52f6096c9e1624501acc6bb208dd494a015207d882e57a8cf4b685ca10b24c448f05779fe2ffffbc462594e4f2559055f382c723a2fa5b78d84c18c2e782e2a3ceb8d906ca851176456573888ba95bce8b4032825760f2c530434483419f149fd6ffc1f970153bf010001	\\xad191b4d248f9de60314984bb0afdbc6dd28c6f22b5f9d0af43293f8c2067bb5668826b05bb984e829a5ab1911170b76a5012a2d82298f72121532667a4a090c	1685894440000000	1686499240000000	1749571240000000	1844179240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x42f193245e7ab4f607d8a0ef27f766a4180702ebf066ab78ce29dfc556bfc9aa79b33f81298472ccb49a691a64a19584fe5fbd308d2c2e56f608d0d57e88919c	1	0	\\x000000010000000000800003b8312db5cbd4bde90a5eea45a205e89336adc54c2b4fadabb2bb38a8c46c06592772caf8ce1ef6a1f343ac5bdcdfb64c2ea1659c4cc12642a749eda2041abb3f1548a054e904f13c280ad980df99fe23f070e11e15c3ae607dc4617b28dd3b89004b66e5a84970a19b5cb0aae33e1330601fc57a148caad838bf9e934816f6a3010001	\\x70d7b2fa0a9a9a54eb37ee1ce87d81a607875910993e65be674bb5c9f850c9055bd26daae373199b72bfaede08dfa90506d13b6c66ddb92ed8eb0cd60afdbc0b	1668968440000000	1669573240000000	1732645240000000	1827253240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x43c55a167cd1283a183349c07857c84131afe0c4f5575e113ba6cad955ca9be0346b27ba33738894700aa339ad42b2668ddacf55042fc3f7eded873819cb533e	1	0	\\x000000010000000000800003d80384c95e6eba9a5765aea5384b9e632fa985da5b38f67015948310ccdc679f38ef870a72e5c3e25c72feae2c359821bd8169e997b839ae60363704ecdbc8bae2021b20b079c49353e82b0e1fb60aef0948f8bc099738a6338fb4e5cc9b9f8b605d014c9439c71212b55287bb9aa449b0f991511359d92d5100521bc4715e79010001	\\x062a63339a123d57f07a06633f04f991805eebbc43201ffa065652c71d391f2f57ed871926fbb243e68b2b5294480a0bff8d921d12253ee2ba81eb87c2a27806	1662923440000000	1663528240000000	1726600240000000	1821208240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x45e556e958bc41bfc3d8a9691efe8ca5a891049b285f233622f383a42fc7b40f4724040fdbad9f45f2199392f8f38f0ee79bb93b4ddd89332269a227e67b04e6	1	0	\\x000000010000000000800003b3b530ce13c8f5e023bcd5eb8e5fa23801138866ec93f48d6447867bc0dec9ce36e33d72085899a09f34cdef9e1733614004fd577fac7e49a9f8a9de15429a475261a5268c426636c04ee4e54fcccdd48ec68811f4461151140c2db04ee1f891047ac33bf2a1f97fe9ddb47c77fa21c3a8a33d0b545f23fdd76eb016ca367e33010001	\\xeff92f379eec0b44624b2510488284673067ee50e9d48f3c79f42ab9c2f2ed50c4d38aac4534c756912e0820cef59e79afcf9e849038a1cb505f8ad76b82e001	1671990940000000	1672595740000000	1735667740000000	1830275740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
141	\\x4cbdc05155e09387483cc0ec28815d67a7710858cad5a7950115a12e376a973b1ce8b1d24f3deff790df51d3e9997b30b6da212d926f48f31e600b758a874a1d	1	0	\\x000000010000000000800003be928cd905464db1d8e0c016d8d662ac1d3fb79561411b7664904812e8d07523037f05fdbc40b6391bb4389f075ca1eccbdda7c1a68f9f47830336e3ceb80d1e5a01137571eed9c4de15e6c4e60ab64bc9c5e77dc482cebf3f4157b61305785f2531cb8fa830364a5e14d584d4c40a82a26f685775db9454b62d351d8a785891010001	\\xdb81e88b5ccc3c7287a557773c090458f8f7d347b4fccb7d6076390318ef1222b43a79e8567db05db5c4e3469e71a42729b7db4e6af9bed16db36d892ce54705	1664132440000000	1664737240000000	1727809240000000	1822417240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x4e214b78521707277718744f5a28b6c01acd63213f315e0ddee41d714ea9c9b96d580de395704d4b3e2de6bec19c0adcb3aefec5dadbbf0a4c96d510685887a0	1	0	\\x000000010000000000800003f8c0bd90a85a1a8d46c0b19484c02023ec209411fcb9df0498bc1ae9be25fb0140267efc7acbd1686b09f634c48823415ecd6023d2e3053a6c5085fae5125ab9f47e5c2e9906889fa891699f5ec31d7a2d250121abacad12d70264819a5d41b2207db3f655f2dc0434e18863749559a0faf7ae982fbf7256a325d0f4231ced61010001	\\xeff47c4eb5c78b50c699735d8ed3c45582c316f7878fd2ce921bc7d286e85395b841b0069510e4f5cb53eac1cd8cc1cd26202268a79801515c504176e1c7f905	1675013440000000	1675618240000000	1738690240000000	1833298240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x4f2590e027fe66122a5a833fbd42e0f9b65127581c73c2691583c3d95ab12e6d597ded7666d02e362356274d08b3f5020498f4e3581668ce98ae1f9fc177d720	1	0	\\x000000010000000000800003b97377ab979d11ada18789a2f6e42d21838e5da20a511217aaa5da3306418c599be094c7d9d441fa209bcc6d6078497218662fffa48ac33d6c91fb750d76d1fb2cf16a0d2b848eee898eadb2b40aa28f6a8853544bb38ac9590b2c082525f1cf1abc141029a2170482fcdaa54973597bf67ed9a9e2cdb0ff8f8fbc88e6ae8469010001	\\xeb6051eafa70567121f363ba1b03a91e893124f26c840b0239fc177239698fad7e1d8667f52fe167f4ff7c7bb8aa1d733fcf5af47f0969e725c11ccd1498e008	1656878440000000	1657483240000000	1720555240000000	1815163240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
144	\\x5121a184fd8f549246a11add779534979b29c9b60ce60e776e8aa0fc81cc1e00aba70adb11f72c630a838c54300a46d8b5e674ca4ad4c1665d662d6b1ca79b44	1	0	\\x000000010000000000800003c425cc4ec01c1744ec0b67b16f97e4ee1a9da864c6c94b9206df0e1a79eb35d1c031048cf82b3aebe6e327a7284ed3cdbf52db753f30343231a28be81345df4633706a218dce506c23427a37c6000cebbc2dee7f1077be4249b0b97bc782f0d8a74254d2f7a8ab224d4214ba2a07a46f64741975d23095bc703065fe92ee7741010001	\\xb1ae41618a53c5d10fa9168bc9c694daabb65ae0779ffa42d2f61b7101325ef3e5ccd562cffee3058ca555b15f6b2a28f4a055632165a7190d96e871b2697d00	1661109940000000	1661714740000000	1724786740000000	1819394740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x52356fabb6270da4cd48ab0b4f8daf90cf212c4ecaf509600394128d0eb41c694ceada5dedca8bc2b27a8d22f4a924a267b210db438b9e27b3f840c28b50ba96	1	0	\\x000000010000000000800003912691752d64d10a9f237504ce58516e65fdfd43827b3eeceba52bc87c34f88a5c0e97413126e1bdcb340e51fa5adeb2d17ba67dbfbcbbe8dcb0bae2b44899274d8ac4cd5007d49b10ed7576b802726043172175777a51a517d338f5beb288b0462696b66ac41cac90c0e9d8580313bb09bce4aa0baefc77921658fe760790ab010001	\\x7bb7db4c7c02d9b7b638ce6fcad58f7a08aeb462531170c4327614bc37a5d0d877388f7bf041b0fcdb582abc1abcf70895b9839c7e15dc67968cf2099ad24b01	1675617940000000	1676222740000000	1739294740000000	1833902740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x53e97700c94e17dc298cb29268204755d90bee8e47a8099290cc84f17211b7c3958c9381f945f99f1dd2fd4a81cccee3e223f775c730cedb7966a2c40d8a6dbe	1	0	\\x000000010000000000800003ad9a028df9c539f918b5651f0debb1a3a94cc96e4f0bdd528c4bc601643333e89362f7a5213320d069a87acc3419010ec5c1023c597141c59851b2101a4d70e09830c56c5d0f3b2e63196f4d8736a2f85e9543d9a7c8f37a03c053641b81699df7276833fe6e098c8f568f4d587fe4472a0cc931005c52c8c188c2c35d9d4841010001	\\xf384101c0127680f6a07938f8db6cc2c1569262cf2c9ee35db3dd090413e02f7d5b15f63a6b4ff3a6c2508332d8049c84490615f77b2c7916469f89491ca790c	1676826940000000	1677431740000000	1740503740000000	1835111740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x552121c0bef26bb31fc619b6ca46cd0e3f92494f9b99706ffb346e37c82cfc820ed45acc114866c00b55f1547ffef31f6902102dd92c231a895f3b450dc38d0b	1	0	\\x000000010000000000800003b514f5ef83caafe5cc8b0d07d0ea7a8aa7bce37901447b8f7ee1e43b919d0cfc007113b144045e374defee2a6a54f54d202397df304cdf925a08d367e5a1b6a6b9ac6d0a1f277289890bcaea052a5bb095bd94d0f661403dce5a76c226d3365b0fe43d5bd4e3ad2c28799fcfecf520be6c389bc1bfc25b8ef7730b7fab536a7f010001	\\x021d733e42cfdadac797fb720c12efd5f9cc450c2048187db45615ec245638f785b1552ff484c59b86a9005f6ad8a702decce33b92f706e1e091abf763ab2704	1665945940000000	1666550740000000	1729622740000000	1824230740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x572526baa7f6e367b99922833e28ffcbd06f27e4a525adafa5e16de077fd23173e4d40bc1887a878b42621099bae77fc9f617d5648d1edd093146cc03e02a61c	1	0	\\x000000010000000000800003cbf9483d1affe8951d6299343c672b264b6831d8f50c59a9c459e2ca6fa237c4a650ebc3498425872d20ab0b79e3afc983c5d105cd0a00cb4aac822d85608f9a0e7b95fef6e5df27aae60636ef85b80dd287def525d7161beb76bdb462239dd22b51537278dc5a35fa2980b9ea6ca73beba0ef48fa9d2d8b6255a9d5c39d95f7010001	\\xf96f11bc1453735352a230cea5d922f4e04c6b88d82ceeda59a3cd5e1eb3f6bbe42a3b563444cc6f003ddaa94499215341f6d45208426c555a769a1c5e63b300	1670781940000000	1671386740000000	1734458740000000	1829066740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
149	\\x5a6d99c078f4414f8247adbfc65e44b6a36c25b2fcac857860a390bb74f0d441a669f8c4ed1afeba22d5c44673f35302c362c002baf415db64fb0cda42ea3901	1	0	\\x000000010000000000800003ec6b8cad539edfb630926cece23293fb4f994bdd7c59216f5e72dfd3687f617264873b189b68fbbcb3b53361946d86b69b28aee3d18bdd0b1e5630ca29d6e2410d70262a3d1ca641d88f659cc4c426056faa69485af563133505a9b861128f070feca9629b111e79c81a1de2df6d68c1c7c524897b890a11a14486a88c6ba1bb010001	\\x38cc03f4b1ecf48900fb1cde20ee89b9638a73870e6ba22f4b764617dcaae720b137dd26acb00846f0428dcc9fb045434992b9f2e92ad75110a3e55f5a9aa30a	1655669440000000	1656274240000000	1719346240000000	1813954240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
150	\\x5a81dd7608a5f80fcd9ac9ee30ccf17537b9949ac91c81ef48e5502e1b4ba7ca24a3039450ed2ec5784f6e7877a9e7dcefbecccd419f36e6eac5824e9cbfcd49	1	0	\\x000000010000000000800003af74226c598ff8b21d880773b7091e1fd33232c6efe273df9e23b00b0876acb328ce4610135ca015faa960c41c383e9c4d95730e0b9a59874b355ea0b5d2f8141b87276c443aafbd9172d2c148009f35f91f42756be6a5210783f866fcb671adab1a1be3ae4cdc718c9b94afc029019b3060737c6cae795eea54c275cbb25d9b010001	\\x5b84b0298344a826d8f40de69484f4934452ea6fb46cddd2521abf35dbcda00658376d0434b1dae9344ba6fed1c1681659aca63384a049d37137726d35f36a05	1680453940000000	1681058740000000	1744130740000000	1838738740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x60d5aae407741ea6986f463af79b305a994c8f5c504749339115a6839f973bd20ba43efd5d7959bf14eeb6ef0ddd3ab27e0604cea6572cc9dfdbaf9380d0c848	1	0	\\x000000010000000000800003b369520588db780c49376728496c712e4666bc47618262d89390e265fc093e9983def394b07fb3e8fecdbc124e56d97f245b6248ddb66d57a4e46da4cb92ccdccb16447387ae3d1c45fbef81ea7a75e9c9cf3d921fddc190ffc5842a8166508829d3b28e54bb8c394feccee92cfa82c8fc915c1affdac4d85bca5bbedcec5355010001	\\x1ebba50cec254f5562595c7c2abc62d685007e42b5a7cf96a7069db8848d9ac4968adc4b27c8a0fa373b5287a54dd1505496cedc6c4a35dc65ac9e0c7dfb8d0c	1670177440000000	1670782240000000	1733854240000000	1828462240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
152	\\x61814826990669f1b8023dc09a1fd0e4ab3cc1fdecfaf7720facb3e42044b1be20b88c1a8e55e8c91728f6914a2c683cc54b5a393a55fca25e09f9ce4f2de05a	1	0	\\x000000010000000000800003b954c98b2965d37d422104b72d08ae451b146b662bec51a3d46701b24d121242e468ee93f011b0692d159c13a4fc493dfc0ab4cd9ee7bb84fc2cbc4f4f425b573cad3e9b77e15a27465664371558dbaf211e3ff09bd4fbdd686c38f7db77ce37b5f14a283923fad67a24ab1a75e9d31deeb7aeb86c0ad19139750f2ef3a4218b010001	\\x9117f318eb725dda6894eb96ed367aaaaca300d24d6a27a1c574a620c2d2495ead1669c92d1a3d8ab8c9d77b2810afb6da382ed87d0d54166d44dc972aef1a04	1671386440000000	1671991240000000	1735063240000000	1829671240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
153	\\x657128437e6ec90e5f9dabe1612a0b2257efb5b5182c083d7eb3c5b659f508d8d2f8b903394c32ddd4c7204b46d7b4386edc81328aadf2d913f4e1ed512e2f6c	1	0	\\x000000010000000000800003b57fcd9ddc0e83729fc636c36dd22ff77bd2b6bc258c332c9040d159fbcb71ad4ee3ed438c64e07d2d1e8dcd59d4b3e9e1753071a1474b6af9c18227e675fae4bd0eeb876a667f9ff303cc43af22134715006bb74416027ecc5433668cb4537545b57d4e1620e94a013841ac58aacd901a33832fd335b992b5ee457c65c0ba7f010001	\\x81f2367e988a1b1263199a94fb16aacc89348c50d20ae2480ccbf7fb0a1e075fefd10a960ac05ac2f10ce9b846f1fc484dfe2babf367d0f5b139858c3aaeeb05	1665341440000000	1665946240000000	1729018240000000	1823626240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x69a564a9d7950eb5220a3ccb732feb371fb017e6c52e3c845dd7e30d61d6e8718ce33acc306d57ba125ec80aab453a359e6908686803ec4f2a4b67aef0b0ea07	1	0	\\x000000010000000000800003bc34bda35bb602991524dfb43ac0aa8f2d8edaed900b6d051e9f7fa530b3036daf512c4063ed989005f44aa5c8913e7eef1d29ee8dda37db1df791430c6886b789339ff5d4b582f203ba79025b4dd2dce598a9fb649f94714731aeab834920211dc111918e30b5a94d0cd05bf1fda64e1ff455a4f0416766c82684cc1519634d010001	\\x862bfcf901f5bae5d61a746505652382f93d5f0fc01875d6793531c45f0760d948fe0e02ad1ae686ea40ce840fa9a424eb8062332f8b785763327ac9d4cc1a09	1662318940000000	1662923740000000	1725995740000000	1820603740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
155	\\x6a796593a1ac0d3b7f39b3dd5e3c7c24bb0a57b0dd631ea28fdd0884b1cbc07f554ca2ec3bd365621b3431272117747def72d3ad293c3f8b3d639e6145097347	1	0	\\x000000010000000000800003c8320f4cbe76e71d4d4e062f5dedb7f9bd14b8ddb16f4cd01faa9439810e4b4e8ea38e3a142b6849137397bbfe64c59dccfd87c183a64c5419de7c1ba2750e7c7e2154570488e10e0ba67d0f6a020ae160af84e79ddcba8a320c14730aa52837582ec296592f416118e91c0d6b4bbb4c38cd2eb3cb5d015bc15ff7f29d4c910f010001	\\x2e0991e81ed4b86c4f31213a403bbfde4f34c022f30f6489c9b1858487e3dfe5b775031163afc2f838990919df40093f274790ad31a3b1bcea20d2071452da03	1660505440000000	1661110240000000	1724182240000000	1818790240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
156	\\x6bb5659524566bd108a940c25120f424127f0f47f146a21f53b64cddde088265f98eedc9e3f5bd61ac33dc245e3bef98dd9ae0c85cd42946f5975a4ffbbfde38	1	0	\\x000000010000000000800003befb3018e809b6350c5ec88429bb2d75b390ca89485ef58b1e8ec3408e00b9efba6455cea6dd150abcc8c9840d1d1afa400656a8767e51932c415cf514922c334ebd1066037710370fcc14cce074bc19301e529295d891a2dec1daf1ec5176a12559bc400a91bf06c5732ad415a03f144367c3b7be6da4171054abf003aaa329010001	\\x997879a6c5dc94a63f639c8234a16a0782994eb80c0123c017b076f372c2a502b767d15c794f8ef351182f127906bfbb8946cef9e535a2d2cf52b56745c9c70f	1664736940000000	1665341740000000	1728413740000000	1823021740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x6cf58fde4e010a123ec8c120a227250386bcc28ebe0aea990212395b66cf702e3e7e17e500331b0407901d16c3b576ea78bccc545ce7561aff3748a6cc1a9162	1	0	\\x000000010000000000800003debc4737eb374ceb6c683e3d0ff11bb1dd3b87aeef21e6c101f82adee6292d6c82e5c70f2491026a63c9215b8964e37c45327a806eba5a0d85ba5b182f2b247c4514f21147f4586ad88fd930f2a125ecf4b534487cea555190124240401cf28b3e83d46c1e9c0cc22beb331651899971e03db4adeefb4fb09dd188c4af470449010001	\\x5ab1969fb4e24c11e53f5d2110c5a53c6d9593c5c5131f50c8ad69689aa4ad2ceda69aeaea32bf44d90d12459f7f000013224878f6d3bb9fd316990693a3570c	1680453940000000	1681058740000000	1744130740000000	1838738740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x6cf533be86fa1ed01636d1bc04c230c958711b71f3fc34319ce8ed1d9b6c313d6416b09a7d6af95d076cef8891fa1e471c3099177860862a535ccb162f974547	1	0	\\x000000010000000000800003d4dfc01aa1f6a8c6b2132f05478cbf459dc8bc2fef5b8134ae422d53fac5ea6b24367f0b6aca88873803df967bf00f170dc952138cebde7afd128147eba431683c82fb3b78362c008f2783aeacadc3f9dd131dc498afa9ff9cb7fcaf49bdd47199cca4d709bff1a43e38b051ef89c07b0206e49e6be9936f572b06975542eb25010001	\\x7205e9dacbf5d0cd729db83bfbb1e9e151c8913423edef71b9320a85f69863824416c637559e3d86a63fada71525498c3d357324084c62726aefe3906f723e0a	1684080940000000	1684685740000000	1747757740000000	1842365740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x6d91298177c723601c6d9e62bbdfde8b71f755c24418aa7439180341c0d8e1f75f2bdd31cc7b39fc009e927b41a1e1611449364999b106ba0796221029c7a8f2	1	0	\\x000000010000000000800003afd3ac9eb1c603e2c57b4546cb451239454e166fe5daf866831a2390f8487fe34387d729e7b92aa19c6843533bf8b7badc596e9f45b751cb7f471ce7e7e8f926a8ad85494e1d3b6c72602fffda4aaacaf510be3d8c1183944da0f1e2759975aef409024134ebf16f329a4c88affa9a86618de70f6a5564c4aed4308f1328fc6d010001	\\x7a1c55007d13fd99b971d7cb7115e08abcebcd86b85c96cc9cc443692a8489b2c2921cd3ade13856e0600300626829534e3a051e3f0a4343b4165030578c520e	1663527940000000	1664132740000000	1727204740000000	1821812740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x6da5a0787713b47b3eada75f3bc81398b271da8d64ca97bdebc98bbbb393130a9d0f57fc9510c371769ebab0f454592898009e4260ae66df2638d10db3ed7d0f	1	0	\\x000000010000000000800003c6c8f5cc62c88f7ff6329a7d71d365ea3b56b0cefcdb56fda8e5aa976a42d998ca33e05999bce7810346da3f30df7cb6040e9260340bf97fd3cfed54441ec6581bdd474f0863722a96213f6eddb13076530718415ce8522c2e0edc72bb4ee126c890b3c7fb1c1c823cfa21683c422b93cdc19ab3ff014ba3d0ee6d29181f6ae3010001	\\x0346eb1b465fd0ee43064d276dd896702838a609cba74a873ecea290621a5ed915e886c0241710157cde3c5e4644d7c7f82417709df15c3c54d54cd6b5486e03	1666550440000000	1667155240000000	1730227240000000	1824835240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x7065706a3b306acf09078feba9f0c10af1e1235949ba265b4eca4d670c59a3bd883f9d740fceb38c680964ba6d2ac551b20b6072b16b6767ca280ecca566c3c3	1	0	\\x000000010000000000800003bb337a50aa23267fe4b84374807558dced29e1a51209d9aaff2c9f29fd8f61a0e63921a042438c5fc2d281bd61f728710734848a93da940abfb34e5d077d92302a72b0324f3a7889dc374267b083bb8ca5475787fa189900660dadb22e670d92f216f7934c56818dd1906f575fdd331e183302923b2bf40bbec55fd41cf1f6d7010001	\\x1755237b4f54a95b5275b905ef009a6bda732b496c1e0903f19b82bd442934083333afb83a350492ae819d1af606557be68f79c7b47b18ab4040131fbcb56706	1682871940000000	1683476740000000	1746548740000000	1841156740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
162	\\x720d4c19348a24050bb5f2f6b3bc65dc9a3d9f09431d017bb7f49445ae6cd1bc6145c90a88935f2b54ab122e658362e58d93c80389e0be0483309051e609dd5a	1	0	\\x000000010000000000800003c95f40f43d47728dec75bda80a7f443d1899fd5bf879e0a52eeaf9ffeede1af25d5236265ecec2bde580f5b84fa8567373055ae68346e60c80bebfa273c6adb16a8edfeb990e2f0756e48ad83d3272da52906b2578d28560f0da44271689dc2bc8d461f2ec28451866597c419b3d75da99459e6117eb743de29b1072bcb58cd5010001	\\x89c593203af4338c8153574bccf4e251f5a10ff4981d0620b5cb3a0fc5efe39ff763c22e3ddc4c71bb970e31f9d91fe4912e0d13ef6d25509586adc54939b100	1675617940000000	1676222740000000	1739294740000000	1833902740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x7331ff8f8a9b9937b5ccaae7716eb744de63f6ddce7a779164b625c3be74aef1b10172597d71e2787e203c9f909b9b55ab43f60d96eb3e855f1780dc25c299c1	1	0	\\x000000010000000000800003cf8642a2bdb293cde88a021290d372a8fc915f9d21b37f5a45864600fde575d9ddd1cbd84039a0c07a4445cc11ba464a06bf70e4cefe7d366e3c36c14ada9ae952351cb85f685ffec00dba67a51d8064d36a5d671b225b1e954cea16419d21494643beeaae20a5fe9fd11f8c0a78f5eccc22bcdb85e89325832e57d5b9759a8f010001	\\x4d8ecfde1d47c1ec4a3d695d8e778b70621d3ff017bd325f22ba62c9e853054efc1d90cb24a5ee8eadc7c5443fa46962039bf631cf6fef6255acba6eb85a5909	1671386440000000	1671991240000000	1735063240000000	1829671240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
164	\\x782977d3ef6ac92a99e34bc2321c37e215b79b898f37848dd04a8216a3da3358c1d9110b572a7597be07f1bf4a7c4c0d941eeda572fe5594714da9269a7ff0a6	1	0	\\x000000010000000000800003ad2d67dd45cdec610cb11e94d13fc02b106b1f2298458cbf555931e73d1fec8f084b1f037d7399f1b2ade23a7d1c9d80ea46b6c2a912a062493bfcad432173d708ae2cd5b348f9b8b1a2a44b0e9aa7c376d817c6503eb863ae13216b7e9a97bad1b1a97c03145849501009af4b94f79d16dd9dfbc3ebc95eac1c3ce1e792552d010001	\\xab62411353d03fea8bc0fd69314fe185319790a203f884028b85ebc54de591e6f0b72b94a5779005e43713a9692a78b5bfa0698eeda12233ddbe768b5f499502	1680453940000000	1681058740000000	1744130740000000	1838738740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x7ce1c87ef7fa16cae22f0bf47f0a2a1ac6d9ae852e0262b497a7d812e48107291a40807870739041f6d1e8c06bab33403fb3daaa6f974ce1a536b8b99e6b1dc8	1	0	\\x000000010000000000800003dd46b1bd86ae0c026da430b0ba1bfc498edcb6b8218c93ed030a940c1b8000ccbe527be9a29d2b79df6c0ed976313b9a1678acf6886d91a970b01f147ec91acc49aebcbb08e2ca4e772cecb323fbb6ed3fa42aa657bd11bbe613b3f10977bd1c48809f2fd1a2e8fefd5a29fcf97117f4b6be14f98b4769f2450e85c2d915c711010001	\\x042a7c1eb60470259e6838f5970cac145682ae6f3f9a0c7377e31e3d834e7e0c5ec2e14279978d61638a9531c8959e7b699a43c8226da933b9db18df020fdb05	1686498940000000	1687103740000000	1750175740000000	1844783740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
166	\\x7c91520c83b771dbe7641c27c7e51fbc5a89198f1c873530863d63577a953790ac5583e743cc62c3c7da445955e408de522d812c0d430bd6b936559f42df7194	1	0	\\x000000010000000000800003b4354979cf955b3a77341f033bdf3776756190d0648b6dcea52b481a9f8e16182df75df050a579e81dad2e954a6aeccf20e7a021087bd227c718f918b439611c2435eaee8789b07f28503e7d7fe59417036575218f503d61bb4af0e95f22436de6a7874d04636a8d27ddf864d99149472175ec277aa23f7a0b12fcfa9b14b2bb010001	\\x412906c4a73272bb66343022e3464c3f199ab3fbb19785ff532f8a731b7c46fddb8282655a00823bf7e57de0947bdd6370e14afc301c79aa03e84e42ef5c7208	1673804440000000	1674409240000000	1737481240000000	1832089240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x7dbd190f3a8a66811573b01851ced289e40c1f65adb3749becd2510f409deed9070fc3f56614e0356f55ed59e43d4d4c0a885c317ed4578a5039e93f10d3c81f	1	0	\\x000000010000000000800003cc4291ca422c274e55bed3cc7efca8ed8461f5b5e2f39a1260b11d253c6d03441c9da742896e2f665cb584671dd3a12718865d68e0bcc16a33c28eb83651831a36a50a3f8daf06ee0aa183403018cfdadebb007c595978a6e8a31986f6957ceeded3568fc5b1fb42aa73781d5950a6331076e91c4a126a2b2a25900b2701c8c7010001	\\xcb1451e8e43fb9678f2d44b0a7bec6b7448a1b6106690cb3af4bc6a78f401043be7ced763bf1d0d66ebda201c95973d4851001ebeed294b2bc6c6aca27691d09	1678640440000000	1679245240000000	1742317240000000	1836925240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x7df1ab9be633a4c8ed1a305c34446ac504f80e8b949827e5af49ca20e5f4ac69f202775a7c1300b58a3ff71da6f287aa452184b8c9db10f7308ccf896685d357	1	0	\\x000000010000000000800003b5aeeb9163ce3f8b63c868c6e6357a3edcdce9ccd18e126d18d34a6843f15de8c204639f1a5529c8599936e9d297724c7cd3b1359d40361971e6440f88b56a611fb23c2d4781becf29b7665aa73b0682571292322299f85b331e2da79870ddd3f91f2033202f31b901362cf1300508660a9f3efa8206c374d0414e08e099fc51010001	\\xc191fddc43e9b70faf5f0b425eeea9db9db438f437babb6f78b72359751f148b5658bd5b06b56d42c39cd64b0d4612f5523ebd92de362c0c3b4bebef2a68bd06	1668968440000000	1669573240000000	1732645240000000	1827253240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\x7e5981c878c6aaf04dc3c8c2616eb87344ae3268b041e1b742069915ec8a8bd5ef566b8853a58bd54bedbfcaa2a676fd6e7aba78baabf422a2cdca4920c0d52e	1	0	\\x000000010000000000800003bc7b02844bbc7333c6b22715bc8b02a12039d956fdd69f3a1a178a8a123dde1cd3b02f932f83d63bd5afd6264dd961039e69ed8afcd789b780a0562aadd0980ab578e60321bd87c417e61dbe33a2d54152fd75894398e733735424d804c68add8e748e6b4158bcdbe565e223e611967c73470853ab9344f26b3affc3ef659e13010001	\\x09022229470ad16e99c1c1dc740f07d0370a14c863c0cf34b283f0336d34dc9f6ebbf8be6331043e17513708ac9b9282320607206a6e130e021de20ba55cca0d	1673199940000000	1673804740000000	1736876740000000	1831484740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\x825da1cac05e04c6cc23074194ac979af7d9cbaabab83f27ca921d8707f325fc733252b1c2e2f4f4fe916e42cba529951ff062dfe2d7a0d5cf19b7a47525a8c0	1	0	\\x000000010000000000800003cf6ce7fb94a203905db88c75eb4cb2efc3ff3b8bdd35ec79f520fb0991ef56b3f6c592c3a56f200bfccede551449cab7672ff96e48399e7e0966340d167a228576d72ebfe40a8da9bcf276743f81b81d1664e376b2636e2b7316f8c9186ec4578ce5dadab6f3c387061aa0f46ac6f1246b7a26a2b709289210d59230c2a10813010001	\\x5e417e27fd4aacfda54f16b07233b2f4ae5b8f4274d5053fa0eb642c52c7777c6f72ce5fc3a3e62f9b6f43291da3aa5a97f55be4c8ccbd06deaeada9dad7e808	1658691940000000	1659296740000000	1722368740000000	1816976740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x86153700ae8ddae555e9d953ffb68376b953179c85c14159fb009743d913738a72820af52ef4cdc21742bb99ac4fbb8b46be9eecfba025215c031c1196a94174	1	0	\\x000000010000000000800003d4f0357a5bf97b9d2c9f95a3eeae19f623ee152d1f364f3a9753f52a8af1a26b22b60bb2b872bec30a0c0851a3e534b0915c0b38f76a1b3691571307264fadffa1083953a9500e40670d123e5285f5570e5327a81f8e9cc2f9a596adefc8f7777cc97dc764a179f9a932b740f0a4dbb191a26dd46998d891db0edaf79b7e8731010001	\\x33dfbd36d688c95e2b8e96ff000064f70e203edbd9843e8c18e79a4d47984dea2b1692a71343c022306d622cf33297e08dc08662f0a887ee3d4e5fc08a9e2800	1661714440000000	1662319240000000	1725391240000000	1819999240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\x8939e5dc162e2f53896537967d030a6f8ac334ec076c546752c4e6a03e3c10562aac821117ee5807817c4ea3928c45e80a945921e52319344eaba63a82eaab6e	1	0	\\x000000010000000000800003f1f9b9e9ad528fd9443abf89665b4fa714947e8bc6b46e2c3a046b264f69fb9c8f1dd15f6bed5abebbcd39503d50643a3b7ec88e1ecd8452f428ae4560db763803421ee72c0e877854b19274f1cea08dc799c79c885bdc2f7b9947f10388be04f660be84f1dd4ebb2edfd70fc39b016e7db14cdd2702198fa345428dfbf72937010001	\\xf96ed343b311101955d7dc4ed2bf45e9d2afc398347db6d6ed53622e6905fc49e5bf85b959e50cc2cfced201dc9055274cff5a3ce66b616bbf137328ac0b3a0d	1681662940000000	1682267740000000	1745339740000000	1839947740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
173	\\x8b71ca2d7b1ce0328f4561f3367281f8b7d93432c8fac0573fd283760ada2fc60853b867be5bf76d88359802439a8699a75192feaacf83cdce1b0790e652310c	1	0	\\x0000000100000000008000039b3af26850f520a05ce9289a0621efd9a790add607fd7e302be5fefe4dddac42fb0b1f5fac823cef1f85d0e3b4f38170300c3f22594871c35bf1c3222a70528c290a5c11304de308579f51045afcdd23de4ca5df3681df366999919c0d5fe3104c216aa611ab3af0a627f69d77e25ade497a9acaa6ac056515b5db6f9d60087b010001	\\x4a0744431243fc03fd51bb6380c11f11be3f735d2972937e274e2181db182dce20425a8c1e4ae0373b44293e3241a7d811456c1eea26827c6d2ba1eb5418cc05	1660505440000000	1661110240000000	1724182240000000	1818790240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\x8dd10968dad0c1ca05d5efccd08c7ee66c911b9855fe944f3e4e9465d48b61d9ab9c9096b5769ecde33f694b8a6b5d11d7b1e3c19ff7d7cf4e7d9d7da81a6738	1	0	\\x000000010000000000800003cb0774a09498715f5a552a7e20f0b03e616308d269ebd5e10ca1ac4395fe1d964b14f92f4178abe9bae22341e9a6f0be3ae6c4fe249e6989b304af64f4b30071706a1b2caa514e9cd9cfe5a94ef38805ddd94f0767f9a33f3a5722575b9921ce3474cf71d895b9e9bc0ce85f06b7d6c42ae7cbbbac01fbf4f8ed5f8efca428e3010001	\\xa4639f5ebd204dd4381756c9e32117a69af7c855f60dee4f762adcef38ff13e136b74754cde424e9425e4581a253a2aa5e83b224d14fb8fc9f88a661429cac01	1665945940000000	1666550740000000	1729622740000000	1824230740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x8f293017b1c7df5253e020c85245d0bc37e13dfb366213a9afe88d4b6aa058b3907826a6d9159b359722cd15f7b98c5f7c4c4b4893494850d847e4f035d360a2	1	0	\\x000000010000000000800003a7a76d3968ee7ed0df6fe497c23f8a2d7dd851505e36a29c125292fba2da497de3349b2ded295d07eb361e37e0a317275851163aeac4c8290f4c48c40f92338f87a157c19a9761bbf477bddd75833c4ee70de3ebefd3f11a60653a52cd7555125fe79ae5de53080b496a44617ee965f7cd74958c0ab12e2911dc9e974c520a9f010001	\\x41d8b2e0dd3a60bcd26ef6b45949ca8bc918b2d76b476cd01cb8cdeb007292e6813f86290791d2b08e05ac7b7ccab7f75a75a1baf608a1a6ea5d02e1e2e1220d	1668363940000000	1668968740000000	1732040740000000	1826648740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\x90352f344f44eb74782f4f95047430f9f683e5bd9da57d84801d499393413fda0c96f1fade8480ac6a724f5c9fe315585150cecbff88babec69022140c262452	1	0	\\x000000010000000000800003b7c1a27ff01445582d2e765082b08730e39c535603fe29d48bb9fcd179ace4dc81b110d41fcc93d29f2f82d2e18b0d4ed079ff6909fa2c8e40bb7885ca5112688f374c622b91273d784a690181b97a451282512dfd6265af7a22a95f2ccd77ec49b319a5165272c41e1bd6189bb2d715bd7d05d175fdd9aa32db6e5002effa3d010001	\\xa3dce65bb0871b63fdd07c86eac429e964d3dece32cb599a334037d9b6b02a011b8832b4576b5083d8dc789be02c7c433c13f751f77b6e15ca5d7d3b97155105	1661714440000000	1662319240000000	1725391240000000	1819999240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\x91019a254a77adb721fb7b4e46c4d0b0064b23b87acfe9f1737c09f7eea2a1b62fd2fb59503f914a306063cf9c27cfb87984755342d3dd4519d2a692d963467f	1	0	\\x000000010000000000800003a67e2d0b5fc22d7de8b0f56a7061cc8da5ef59f3db51ec64d79f9f6ca48a1a3b41c7cbd53a039589a541fe67f93e04f389f65738114925bc572dab2c9a6b3ff00054d108d417cef68cd152b627a40352dfa9dece664daf2f845e0c2d981adaa7b539405060ae0c990ccf12a0cf3836a50381a4031d279d4bbeed5abcc8138cf7010001	\\xa90e1f6eed748fb9339219208bc5420a75c9ba53ca45e6faa98d80a9678a0f6d88e90c7a67bdb90b7a2a881dfc3a89adb6a0d7833bc60e0a7105364e0d78b002	1665341440000000	1665946240000000	1729018240000000	1823626240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
178	\\x97c96ba0a896084fc3f893d95e4036e8ee6e8db0e1614471c2d778f3dda0fcd06262415dd189fe7ec881b8cc25eae166b991534f525ba1a3d683568facd22ad6	1	0	\\x000000010000000000800003e8d841a2837006324ef7e569c4aa7579e784b050ff362dce3057772c7738f8ca6adf0b0356db21880f9858fc736be908075dcc56c1cfd771614d3b00cfe8ed66fec88a62b113ac4a058f5f6b097e1c8b9d061079ebf2b95657ac9a5f968db4018a11f16cde4cbb96dc6641fc7002c32f29f1fd351298115dd8a7bf5c503c226d010001	\\x8bdd471d5a246051f7e2e5c3a2a3cd7f8ad3de702a66469d6e14bbd813d78d580a3c0d43432e4f48f962418508a94e6645c57f8c22a16d2da7fb43b6a3f1180f	1671386440000000	1671991240000000	1735063240000000	1829671240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\x989d7fa2367dc912b174ba82cffed416d3490737f11361117c1faf1ce85bed0296dfb56ba3dd6aa2030ae95947ad973dcf93e5e381f83535c736329657ca8152	1	0	\\x000000010000000000800003c60c6abab98b4ad7a73aea4ca14e6cf9c1d974b99dfd6cb9579e37590ac80f66fe6cced0f93f4d31e2132fd587fd770943d51e8137013249e955a312af9644fe5f1c04ec0822f29a7745ad5fb1bd84bcbfdc91d7e9a658a8b6fafd482e1272d3d71fe19b91c64f6a2222b7513e39915b0dc70d6a31b20fe6c91235c1b96e5e29010001	\\xe796cafab4d8a364168c0b9bf5e1a5e5df1cc0da86408c467be9b53b040a9b180891a16b028b8a6b77493926d366122e6f9aa098b7c8ad4865866908adf1780b	1675617940000000	1676222740000000	1739294740000000	1833902740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
180	\\x9af16bf2f85d50090b5a9247a92ac3b126aa02d047ca4248a70685c96a1c6a50018b63c9a62e79c15cf18ea4759df66774d02ee26fee2a02b0b69bb900cc3965	1	0	\\x000000010000000000800003aba9981be3416f1f5209482f5d937314134ef94f350188d58c8db5847eca0fa4ec3122711210f31727c1fed29fc2b08b9d2335c16287ecb3be50928e526a91ad4b41a365837c325b6acafbb147f6d3afdb486cf13828eae97e97c1a9e287a3fc5bb4fef8adc36ddbcf2c83e5fd4c27a557ec5c9e99e25de070178c44691eee4b010001	\\x4b406558370b04054a1c7a8c7b426fd4eacc62ffcf2a7e19e8effc36be0ac34fb0c170fb99622869204889b0dbfc183917da58fb0e48080024b44fdf79245a06	1678640440000000	1679245240000000	1742317240000000	1836925240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
181	\\x9ba5b105456bd453a3f9f8862338e57f2ca6f497d448d6a7f734d478a19fa951c52e7c3060846d6c21585aeae9b27e4ba8f36f5eebd2620ac24573eaf874781e	1	0	\\x000000010000000000800003b906e59446c1abf72fff526e3e80c97c3fa370f4ceb705506dda956baddfa1c61789c3ca4b79c2cb6103618e188c1b1c906e5434fd0234a24b5626aa277b777e122b162d39b84bf5d42901d1ff4409036e8a5955425a9278ef6075da1a9bb4540a05f68343edcbe1aa9d947f50b06bea7465c79ae1387d7a451773a7150d304f010001	\\x4e0400371d379202fed336f46f26412d9c8cba9cc8b689703d01d9b7501213577cf976f2b005b2c64742a93209bb98e0d547c09c3c1a3d35239a7332a2af5204	1676222440000000	1676827240000000	1739899240000000	1834507240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\x9f75b235f2bfcf7f469ce4ef303b85ab4313620ca9a9995a79c27f79a39b3468422c333d4c7e9be2978fadbb86ea1a86bb61e1e7f699926d8404666848506f59	1	0	\\x000000010000000000800003fb5ce3d7a2a08c865d5c8534312430616afe63eac13815ad1f9ac473c5e1414748d7abbec3cbc660554611c80d3c438c0fe5a2f89fd10ea591ecde7ac75a0eba9134854da9fb0599948bc8f2b952ca4222d92a91e5b75b0493c3957ad23c7ae24dc5eb6c279b8fc65c3743b89edeab3ba1411b2773a7c6620baf42e684bc760b010001	\\xd07a819db5752d69fdf163d7139295f8092f611372880aabc413bae893094c4889f40745a5df1663d135d89b682080f63c78b4c2b194c41dd95b00849d9a9602	1684685440000000	1685290240000000	1748362240000000	1842970240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xa04d6fd90823db47d978232b1bead6f6ac7b7f9ed415cba8cd698d051aa86b02d1c3a2763e4b02c436134b0c5ef282e52a1780c85f5f6e8337109e96e5416632	1	0	\\x000000010000000000800003bf92e8d8c0bd0887814cb1abe7091442c6a55db056b7f770cebb9559de1e426e93faa704988562e8cb1ef196faff1688831e96d371cce94e6634cf2c71c0d989ca3e8cac7134eca0a8119ada2eedb05eca8fa788d20ed27de37c2c65afa6f6fbcc9bf660fbf44705817169c0adf92428b79e8ed629d266c1f6d8817ac7fb2b2d010001	\\x639c847e3f141a7b168f579c0a042108b1428070608626390e5d723e1da6e652c3f2d53f964155bcf84e8394e6439b33a5514ee9a3fd603501a0ebbcb00ad504	1658691940000000	1659296740000000	1722368740000000	1816976740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
184	\\xa18d7dc3efb610da24cf70cfaf2b347571c6f6eeea0c78c1d111bb9c4005369042b4fbea518ba8fe836807d53421b8e97446fb01226edd55a6c9b46e8dd7b081	1	0	\\x0000000100000000008000039ec0febff9b2f78d4daf0d64e3d03957abe9743e126034fe7527daf52dbb02368c05bf80bc8df2ff75c5185b0f34018bc0ff63232e1e31eb10e8fc26684b82e350cdcbd495b689e6944e969c2b151d8422148bc31be8b2f5ff975d46f77983888b85b9f95f8b40132ca387092e65eed8529a5c62a73436b093b65a7e36a4efed010001	\\xe1b544ff0e748451a9359ea2596323091bba826d7cb524ff65f4dfd03e7058943b07e1697c420990a165bdb84163e69a904ee0c4cdc81021a779728f8b2b820c	1679244940000000	1679849740000000	1742921740000000	1837529740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xa865f2cf539472b94f3603429b9da9eaf7fd3ca4cf62c04f46ea1a01a47f040f2d93562ea260d16f05eb3b51eea9cbbec30dd04c9c6a3680bce43d1bcd1aa983	1	0	\\x000000010000000000800003ac754b9837ad609e9509aec4052b8df617a46405c886135897b2fd876a9536b110636c464d3c4e096520ae087556503e40dd37857b146b8fe3d25e8cbde5ab17b9de887706aef265298f031cda5cf4fd23105171d0fb75c0163704327bf858e0315e694943fa01f97372d50af8ffc9ef5a0802a6e8e153e9f47f711e9519deaf010001	\\x55e2c036680254f40e68c9e0e2507b8b7bc385e0d1caa1d92cd421170c37dc806c6a0c7b31cda4a372e113327e06e684e1805bad35b798510b0edc4d5db12a04	1661109940000000	1661714740000000	1724786740000000	1819394740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xabdde0cfd3b6011c034553228b313403ecc37be2e10dd1bfbb310846cf4914c87ac18f4e59436d1befa2d58a31913664e860ca49b7ef6e817e50b6e276ab49f5	1	0	\\x000000010000000000800003d0c4e85c64155e546cde6ba58833b20328bf2fbb1fd98e7aca0e159c201784da9c42c117881d08972896ff33a304f3e23c3ebc90af30d5d8a8f6ed9251dcc845cc42b729d69195b90ac6b346f51d654d9ea75b61ef0c02f7b413550f3d596853d6b4dc87b1a6111197bb440ecad0d80ebf6b2a102cff29b210b13bae53f17311010001	\\x6e4d2df3029fef3ff5cec53f13356525ec7c4f92b8a58aaea6847704bf1a6f9898f5e464d827f2300bcad02da3f1fc6f7828ce276814144f37e2ea6a57efcd02	1674408940000000	1675013740000000	1738085740000000	1832693740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xab8df46e844b23da103c49ce9f8d3654367888bb6b1ac7488657aa3a44d9962006af21f9733e91a6b3f648a20bad6e9ca09a9ee720d9fbb7b3eb17b2a4344fd9	1	0	\\x000000010000000000800003bed121175a320ea7b6a7a014e87d76a4b22fa249fe03db186df050b57cd5d138216c6182429b0ef4c5b0a7e54d25ba343ff024852385ca5b1d6e9bc344f613be752a0cf8682ca8e5b765049786814eaada17ef70f236cefacbada777cda0c26e7f7807a3f40502a30b6689e3393c607a8f17c6b726fa41b823f05c303ec8f281010001	\\x0c8668719057884ea35062e854b512d8e0bf57269fe65e87c8e96fcbd054af78c4bbfda669af83423de297723608adad90dd93c47e62805fcb01dcdbc6d46f00	1668363940000000	1668968740000000	1732040740000000	1826648740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xb679c125f0499ea45d0d95f1d01dfb00b828633f0d80e8a93a2d173909528dbc27716cda45464b4de819c8cd01da06825a9a22f30e81ddf29eacdca1c34255c6	1	0	\\x000000010000000000800003b5479ceab1682ba2429872e93920ce7b63d0e162a04bc17430b9ab8102ae4937d4c846b7cd42fb3bf0d4b0e90764dce2587e2f89f91e7ae2b1edd8876db11b3ce9caf40fa45933ba16a76312fe41345c747b11b65b0ff5f20b1996dcfa1ff1d6c7526d24806650f5a133de61157ec66f0ecbb2ba9d4e1040a905e7c02410f455010001	\\x37ec9f1e4b5b5876ef1c5c06b1208d27614319fd2a7226f6b94e931bbbc1be0a511549c9dd7d5a6862c27484c320259187f2cdeca87e4e786dd4a7c3d4450005	1685289940000000	1685894740000000	1748966740000000	1843574740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xbd85a5814dc798bbbc99ff0ebf893a38763cef426142870786ebec574568ceb9a03f7415eae62b2585630c00b664c628edef5c2f63299699a651129a87e48b29	1	0	\\x000000010000000000800003c8858fea97994d121463a90f241e53eacd0daae55d050203256e74fa08b26ff8d7703666293d076a0b8a6d38121c87c6ae995bcb325db9df21fc002b682206a71849e54371d1dfc1af3f474f05ee6cb81ddc7ae68585bae939461c720a8cdf55eb5434ef0f561f0422b40e624161fd7cbbfe283bb86480d589848d84806e0a99010001	\\x68c4b35df1a90d082181d79a4160f66b0971b94aa970805a93898c2b43cd315c2f20364d1e44a73c9df4bb43eb419b56b1648d4c8e4a731511b8488d8195f705	1658087440000000	1658692240000000	1721764240000000	1816372240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
190	\\xc1a1fe845b1cd2c1b3b8e65a938e24aa98a055bd3ab0ccba33d5170696e265ebaff7eec9132140ee719627400323c39a046de88df01e50d707dd61f8e8e42e71	1	0	\\x000000010000000000800003d9cdf9e8a6b709c68fc7dda78035048b90f46f1b9bf3a2a49048b4b2f7a100477c7f2998884535776aa4cf4c2e83b86423addb9962367110c506afede54f741e16af796e4d1ff54aa9ba2117fd35c46238efb97525c1ee73fa00457fc84201002131556c7446080b13515f3ef9a80542f690e081613bd9969885b8a54f0012af010001	\\x14c70454999c8e776f14927ad46f8b1871bb46436d87585e853f3a0067271daaa4ec3930a2aa36032257a107408885811d90767df3fc2c1028dbd4409cf5260a	1678640440000000	1679245240000000	1742317240000000	1836925240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
191	\\xc359b932579afc579415d56bf8dcc9ab64bb9c53a09ec940f060e28ed74150d899737aec0ac028788c740ec5bbf5c40a23a02ec20d1bf0682efd488974b437f0	1	0	\\x000000010000000000800003ba7adca652df376da24b979abddd728358a0552e3fa47faae7240fcc1860388746e00abd82fe0a2f5f482c426d3ab534c086455f14a40674d44e6aa0b5f244b25fa29e496039df3da43f26098c01b3ac425ed3fca08a8dbc56e253764f2000b0254c2df5761d846363eae7263798af1288be9bc912106165ee835d767c5ed76f010001	\\xf872d93a938b126a0974944c42abc41ae2b736a1bacd5c80d55228644281edb94d3d7f4bf77442635e5bbb54ce2b75310b8ab5b1b3b4584a00940cd03ba87301	1659296440000000	1659901240000000	1722973240000000	1817581240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xc6e11f1f09c7b35c208bee274ee123626d3d245e576be18154868f6cf04253a5c8d04078082f1932309ad86cb54bdcaf02b2266835f2ffaf829f41746190b5e5	1	0	\\x000000010000000000800003a84d67cd982e3a67980290f55812665850cc7120ae03edffe58332c0173d6c55d06d15be494b461374f674b4ec0d495269c9a30966cc84625bf87ca4c28ed7b92ab18181574091e9a42111c2d8be174d4eb91067f331981ab1174c3856eebb7d3ee246c2c914f61e8de2bd7338b8fd620e08f362bb1912a6b5d99a9f26ca7bcd010001	\\x441ff6b0103381e478f7ead6d5332ddbb6847b260e0eaf70061e2918482968f43725b2f1938d8ecbde5750fa4ca426a592bc36c3bca708eeeb0a68e43b256f0f	1684080940000000	1684685740000000	1747757740000000	1842365740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xc9c94508844ea9ae6e763e884bbcb15dd99b5ea63c1fbf413132be632715e889d88e49341fa23b293d6dc1759e41b3efd1383a16508fd6891e85ffb1c285f695	1	0	\\x000000010000000000800003ccbb373cffad262adab73fe92510e2af7d697dec09908baa29e7023f9c6268579288a697bb43cc61a4e7c5c33355c3f872c0f94bb74262ba5b314a2b8636109307a7d05686e6901e025cd351d70de4fc48f923318eaec2a06ce2f02b67886962e80c66d28b6ae417e130cc20ccafbd827c645ad3df5d47b55efdf602dedc63cb010001	\\xb621354b93d23fb4d5a99828d9e22ea1def5e71a9b3085b0339dc31ecd6b9a85a3e1a0a0feb244f19ad295d5007068121eaf0ea4131a95ef003012299091d90d	1670177440000000	1670782240000000	1733854240000000	1828462240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xc909166b6d7ab74f35088f3d3cbf078659d67a961f82c1f9969127a9f21d371e48ad49ed2f272cde97f0f2346127ecaf53e5780e7359b6318b11714a01fa159c	1	0	\\x000000010000000000800003be4d08dc729b091fe0bb11fcd1933309c804ced59073a1180eca52fcfd61cdb7f78783713e52e2b750c5b8861bac6ae3c964bc72065e7b7795325237226c1b6cacc454b70fd801516b572b5ee2da628143d4751f74122da2d3212f64d738bc3e531b6e0d36ce9f1553ecc4b451d963d3157e9c515e0c7211037c1f1788b5dbb9010001	\\x75405058a7acbe4ce4aa155fae65b57ed78226c15548247435095b1fed2914ab3b5845cd50b642f709fb30df6d0e09d1c311d439cb325e6bb69dd572863aaa02	1684080940000000	1684685740000000	1747757740000000	1842365740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
195	\\xca298f4c5fcdf1a8fcdee9d19c7b6e26dbc7229f8ba51a1fa477dbb5dca41698f5a964fdab67a3d2420074b9e15466557ba68d4d09df5fd8f14ecb26008a2062	1	0	\\x000000010000000000800003b7bdf1e46d74e836c573ca37b7c19fd3c29fb1c2894eec94730a22be7acae2df629b0c03fee27b57c45fc804081e5470500e8031bcd2e3c58a89c66ec8387c1b152cc8f49c13199472c3be738cfca5a12d314b45468a50f92aeddd5a226b2417eb1df460cc159b669f5f7e5e952e633a977959032cc6b118fe0e2b369774e46b010001	\\x70f98736d9d15872cb319265682f2ec6f0ee7adda2a9b02d98c1008100edc56bd31d9fb02dde94a71630ca2b154e2e94bd7f0261f218b07ad20931b42a21e003	1683476440000000	1684081240000000	1747153240000000	1841761240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
196	\\xcac507331bc364ac4d9a6632a0c350803abffa8164686d5c7ac9727869261926d93c7ae4de465ff094f1c65b080a68241192f20b51c25fce4025622e48fa8f55	1	0	\\x000000010000000000800003d2777eeff775b9c7a82bad2c9716682508addc79c3ba87de503049ba4f6de232075a53efb37c37e2921e2f283f881649d03b20dd51a4daa9e9dada093784752da450cd2999e3686dd14312ee3daa5a55765891580e9f4032abc3efd224fa31048b782cbdae9ec76d8787b83925dfceca07da781f1a781dfa1f544307b59a0e89010001	\\xfbca44735e0fd90894ec4ca794247b5405b5b83fd47c2f179dfb07bee7b4435ee90ebedca3a0b3bb62af9b0275456e43c3f629f47045d84d0a1a24fb0fd5650c	1676222440000000	1676827240000000	1739899240000000	1834507240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
197	\\xcadd583616e500aca338855a5938d154a2b9ac21cdd088ca7e8cbc84696b9952b07a429e4eba50f9bca0c91162f76740adc7024088fa1a131247f8fe77412f5d	1	0	\\x000000010000000000800003e2c4beba1870eb555902952bfc8140bbbbfee861343993c27849d8619cfbf6e2c2d5c5eb8fe28a87fead6152b9fbc40bf2ece4e81ac8ed52bfa750dc86d76015c2eb6db9a492d2d3b4cb02fbc1b9861f3eadea87cc276dca2b74ccd6c4c4edc54de7f234a5f2f75bb5c59a3363a4b708b65109e5c9ec140590bd83b254d64041010001	\\xda320155967044fcd01d687615276def5d0544bd2f177eaf5da32702e959b78667fc97b763f497f08766f2fc30e324cd33a97a7e164711d8cd9060cf48872f09	1656273940000000	1656878740000000	1719950740000000	1814558740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xcf397b4b909a6cfaa3e006aa0ea832e105ee297af3e2342d53955fda0d495c0fe593120189f27cd86dfe456029a8bfc7ce0456dc17ceb4377f4359a26f375601	1	0	\\x000000010000000000800003d979fcda8c17fde5d0aa611033b0c9cab6761889a0610cf3ac736c7a20ffb7bf4e57973ca874a46b3ea9c4aa4b3357f074fb582ef1131df1aeb3096edec0a35550abb5a8bb02c6992af4b410b9534f4b03faecbf5dd7c3da8be8d2eac9582e1e0adbef1f23dc40702ef5538552cb1686e8991bdf693375eebb681eed8edf246d010001	\\x58093f6bb3b191f242479b270b479011c6a3a1627e4ab0c977062a5fa8b4ca5016b1c52af8c5f3fc4e4d5b60681ab0c6f2282955119d1cf965268273b81bef0b	1665341440000000	1665946240000000	1729018240000000	1823626240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xd29507cb446d204b9d14b2f968f19021faeff1c43fdcef4f3809e142a2808e533d23767ea03c4d8bd0d26e2dd0b151a8a8425a1440c08895ec5ac4bded6d9bf3	1	0	\\x000000010000000000800003c34f23f7f4cdb9c2c369137b484bc4da84c3717604c45eb14976d1e4926fca4501997a543cb499564c32e13757f7ef6b4d91b4679d4df8071a3f9bd03607b3b2e737812d154fec1ede05ec2dbdc0305e09f18f8804de1dd5ec3b19d2a4111b608797ab089f64c91d3d85e81c9f7cdb347e50aa33ad703573f2e8d30995c16671010001	\\xcf75ba936b7b8fd55e3ea1e0480de2ee42ca30bab7512a3f818fc88bd2ea8e01e7526345150bb50a1ddc3fa800c0350009b4dedff85b642d4d9c771cdc487909	1685289940000000	1685894740000000	1748966740000000	1843574740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
200	\\xd3d9f5c9f853ba796cb968eb97a6a1786238238fe9325d4de5e7352d6bd0d5e72c55b8f16c7e2d03daef1814d18d17d21730bb4f5f8b9b3c2b55c829eda24e5e	1	0	\\x000000010000000000800003d162f01dfb365b36795871163399925b6312be0854f2f3224d1e702120ebf3cd3c6474f4823f3e6f3fba9140389ceae2d5c043af63440c87045a14366ad6721728ff31267f2dcae60e0cec8be8c3cab8c80f1cd5d6342520f1c10f172e899f9d346eb078905e6075371dd6be0188c2457709d19b44aadf34f87fac4b83653c65010001	\\x14b1dad1c750ae9ab0a9cc33e0f5c564cd933563a9297909cd8892415b7458f0e7d2477b5c6316edb93e411accbf196cf4efbbd4c5ec7fa939c16d6c10390500	1666550440000000	1667155240000000	1730227240000000	1824835240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xd709ab36706d8a57c978b5f95fd1e2c1b8c04287264117823f2fd101100ada604205f39cdd2d4b9bfe9d6ea407a52f60324dfb21b79f3bb43c73f96ab89f7748	1	0	\\x000000010000000000800003ad4c7eae387460993f1c940ba94fa54eee0587815f1023602d04641e66e6c32863f601e926c02c18ca4c8060fab3d464e98ba176cf57a4a8e4c41851f7f100947b963201f20408234b62f73228e26613d7121654c4897d22f16a7695c5f93650f8076e874dbf2c08bcb73e839bd501a9bc61afd05696d70e97c2465f7dc6d381010001	\\x38bb4f4ce597bc36ff50ea1d635c1e1dc59ab6cb3161060f6d8e157b389cff6749b18284ebdf85efede0ba0f0f759d453ebab3e3ca601b9a08917e295c7f6e00	1655064940000000	1655669740000000	1718741740000000	1813349740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xd8d5daed25f92172f01e3dd2334c8ff422546311767e66f31ca41a5be14f1a24accb6e90f2b33cfabddae65f5b95d6d3af4c4bb5720d91c06ee4dbf1f9eacc94	1	0	\\x000000010000000000800003bbf613019251dc1d9e559b6131c709743924d7155687dd1a1551b3753467625db47e8aa98a162a38bcffb912a513162140ce23bc2a25fd5a09670f249f8284fa46eee3c91bdfb18c06f8bb91c9997535e57e0a0b5d782b6f4d374c5e0d274ef7dceff0e2dbb9c4c7ccbd827bc0f82d52b1704b38dc4673a3b853ce38c8e91573010001	\\xa488b4fa34116f5dd28101c4dc2605878cfc36bbbdcaf4782310ab2df668b60022c9194039490dd6ec36bb35513aed5886efddfde48d6e017f10696940ed5d0f	1681058440000000	1681663240000000	1744735240000000	1839343240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
203	\\xd99dcb645a9723ef840615145f8eacbd2c98d298d63241d9fa583b2bede9851cd8d8a9327ca25151388d4a59cb9c11204f020db3536ce4bab10a24ec116c1c18	1	0	\\x000000010000000000800003b0e1ed8c02c574b55aa8791ecc074e436b0fa93771f1e7fc1053cb175a2ab9e5f989329989d3f4730c3c0e4312a73e33c7feaf7eb3f066714f14c7044d18157f690936ddfcb03ec4e32fe439a4dad9320f0b008b26a8540b08d8fe0973788a6c74b58057cd00a0cb5b90b56e621c1dd9aa68c15e885c054fea3f2f01c4dc3317010001	\\xf8268c8a21e0664bac8b6cd56e15d6a7487800ce05bd46fa1405b8a7047a9e1cc260666e76b7f8a1145fbac212d581b89f90351e6afca6a1b900675e478ec902	1682267440000000	1682872240000000	1745944240000000	1840552240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\xd9d1d9d72d5b0f535305663bfd98b5cae65ec68a9eb637cf4f2b2c2d73d51c694f0ccd9e88b33132077cc9600898dbe5cb25f4ff9123060c380e846551d5f55a	1	0	\\x000000010000000000800003cff884cdf49d175a5270b7de017b8dffa3947fd3d07e1c4e589053879f7497c4bff0ee05a3ff6ba648eafcce8b91108427c5f7f33ad231ca8247852ce07186431149025ca2ef87b922ed61f37f26c4cc6c5f5a6a4b476ef951dc8975009184a79684852952ec8026ec74deef14e5fbf67a0c022e16e7dc860f0101c2d6c6c7ab010001	\\x61378af697015778d4f62bfbb53b97c85bf93e2ba11d099725009f9e5410cf4f77f06f84ffa64cf5566664394ea075ab5710ef260af0456ab07171b5cb255e0f	1670177440000000	1670782240000000	1733854240000000	1828462240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xe7dd72f39c152fb118798b9165bb8e51be6cb9fc829792008af1a8f3d648ab35b68a235f55182584c088a4a7a5bf19645ea4c3ff161e2a8610dfef766aba0183	1	0	\\x000000010000000000800003a318cfeb9e03283b75562772a52f2937394c6530fd0063c1a91756234b791a34e93696404aa2d260c6277b92ded2481b5ef6a0a5d3469ae0b9ae24f864be924a507936102116a364e16353e9c0ea2100ea8c7e8e013310816a6538bb7f15845f2aa2a911b93bad8672372888069d27c9c68ed35a1909248a4298b83ec0104743010001	\\x5ee85425e579cae198c77baa648db7731c6572af8864ddba57dedf1aac79799685a6bd99d062956d3ead0a34258f68d9f7e9477ba6759f84a07f65d0f6f30303	1663527940000000	1664132740000000	1727204740000000	1821812740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
206	\\xee6dfb034e5a2dec491202cff56f7a36c8f24994fe8804e92846cfd569a50934df1e9b04f12ea666d6275c6076bde1e3527d2e2da8ec85cc506d7cf15f7b85a4	1	0	\\x000000010000000000800003c5e365a4744255093072fdb60fb1db68aaf1e2e23ee5d87db0ff084571ca1775484121f4b6407d251f432aead3b77832a3da2a92450998c3217fabe5e9b85116ce979c4ea47b37cedbc2ec7021e34cf2adeae12c8471031231e3dc94ae8939683b6b76dc233aab2796a66abe88211deccac0e92291afb287a1c54c21bbd49735010001	\\xe90399decd0b843ffc118dab3bc1494963569dbe09bba3557449e50324bafe079a1ef9fce769418781eb05a42927a5591feaceead79643636248e5c7ee305106	1681058440000000	1681663240000000	1744735240000000	1839343240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xef3d7df1d18ef52b06b9f6f38fd654d9b60edda69c5cfb389c36b6aa94ab8ed828937e8113c13d4de19026adb8eb3e6b0991c73a245ab881b3d2777f76ed60e1	1	0	\\x000000010000000000800003c977cf2635716f1eacb00a1a6104081334da3df3133a46458957baace5f4292d9b5f9e9e3047320625ffc7dcc628d1efa592207e2562190495e51fc768ca96df9487e3b7fd068f18702cecd323bf88fe6186eb1b56698d615fe01d4a085e88e00b46995e487f5386af215b34f122fc6325d58d09a168dc1aac2c5c3b9c51594b010001	\\x49c3a70c139efc7c57ddb2242e18ee33524dee9dfa8c8108bcaf806d44d3e604c67b17f4630ea2527214fdf66c7bdaaa2ce155d4361a3fe901e35db62f3f1106	1664736940000000	1665341740000000	1728413740000000	1823021740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xf3592fed6ad4f7592fa56cdcc8c44eacc12a651e4be53a89dabd011c4cd86e97772483eddc812ed2192d8fd68dd7796a28c8e00ebe564d56170c47cd27ad67fd	1	0	\\x0000000100000000008000039b140919356f99ed8cb3c64114dcad380e02eabb79cd9f35f99ff81f76465b8cf2a6b4ea2af7b0f4591dc550415b9a6fb2f5d61ac283af616c7f5835e321b58d56fb198729669ef69f6b4f9ba5bcbf03b017dd625c50f3d20022a616cafe7a6d1b6f6f363116e75806c45b2c2af4363220bd246981ca19bf43cfccdd60161bcf010001	\\x7698445f3b796dd23f2d2dae5fe258ab9a0145fdc851905144b25d6a8492819a8be97ff9560830406ddb6d2daa246184118e8fc87cb92497be4fae9d30fa6107	1679849440000000	1680454240000000	1743526240000000	1838134240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
209	\\xf7bd0a9b3cee45005bd0c4a5dafe18c7ef11ea4cf73559e1cb721773c7a290481dc7fd76a3ef2212828b049d874c0b5fa4ae49bdf028054bd5bec97d1af75fce	1	0	\\x000000010000000000800003da63d0d129a9f6d2d14d0d8f2a3027abaf96f68b1d290981d6af7c0d852817210ab419e647eb0a4f766b13fe9597cf3d5d11ac3b3b834c98f97dbe153f536c317f785fbc5f17441cc91f5ca39e06c2d38e57deeea3fa540303a4c38fb93ed47c61ffd34fd84c141bd7d0ad8a3b9fea56eb07b4279acd8ca3a2f938c3869ccad3010001	\\xf29806931a5137653a2fc2c0de2d052841efb3f49ac2d8746b060cc4b9e210c51a44687ac25fa5957d45b93d86fd55c6c17415dbe884180dbf7f48bc2e7f6904	1659900940000000	1660505740000000	1723577740000000	1818185740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xf8e5595e4113c83099c9c8029304f99232f4847b6869e53ed85a46aeac264ee860b9b9e619ca60e5a68d7b78ccc9083c33be7870c87b32f5b3b18353cbfaebc4	1	0	\\x000000010000000000800003c4924f8239d70cedebf92a5d5db5fd1f03c7f9f5081e665e3c66c1786018a79413fea6fc24cc2fdccc38c02a7ec9a5a2c087cc0968d0bbf85b7e00c622d8f86a5c9189190bf19a0e43c44602044a7f73b6eba4e8a24942bad1ac76c0586a1d560542c8c2ad76ee84f6be3ee193a40eb5b0946bbe7c380d2cac3268c66d85342b010001	\\xd04826fde2a6023992fe8927dfde607b79713d3b7b2011cbccd6930009d054044ec7ca82801a9495917fa240c910ae0fb2655213351b7236b3e478a525a9af05	1670177440000000	1670782240000000	1733854240000000	1828462240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xfda54627c108a9bb3d5e68f3175c7ff509ac1aed8862a93ec41f47f78db4d016e1fa8ec7e0d16cbb0feb2bdfd119d351c5d6496ea8cac3ac7bfe518b0b1560df	1	0	\\x000000010000000000800003a8bc285d6a1f7bc3aa9c0eff7b8a6bfd3ee1f27ae2ca024a95b02f749a437f085c195a5bb8b1250ced7bee0ba6ee708bd289250f9db3948446987acce977f3a4e032a8e6d69cb61f59b80a3f04e48dde66ded3a6a19bbccdc41f3c4af152d062581d9a9dbd986436c609bdf32760e14d4f7532158bdabcbd25070cb18d694b4b010001	\\x04ec53d06193b42e8733cb598d70193994b72a5d0d991bac98f4ab5c947f330d99623c64e3dc0e36bcfcb72cb1557faf6fc72406697dfbeb985643c10a44ff03	1668968440000000	1669573240000000	1732645240000000	1827253240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
212	\\xfdd1579e38c11b63caa3bc9236102979392de61546347325267a990152ac3507ba3be1a1d8e65f2daaf4b9bf3982755625e7b01826f82d9146b1f8f0746be382	1	0	\\x000000010000000000800003c579abdb61899c50fdec84973fbbe9d32c36f12c961b775a531db20fd7e23d1167def252c1a1f78f8d84780d04a08d3fc7a78ec1807eb3fb0ac39050a5514793181f6d27e220594adffb7b591cd991c0c563da55f0e80830b42df4a275e54c6321dc08ebaad7b4674b2403e2af88f508f9ebc6c7f70eed6e04e58b456f18e10b010001	\\xe2fdfa378015256533ef68f41664079254404b6a601144789cb54d1aa498bf21de02eb2aab75751a839ac389f5e44031cc151fbd628a03ba0203d29773762e0d	1685289940000000	1685894740000000	1748966740000000	1843574740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
213	\\x02be1585f06d3778cfedabd05308968e75dbfdbc128741cd786880a94b0fa458e3b93833f7230185564c58bf58b87b5b177aa3120af16ab61694f2189a62eea0	1	0	\\x000000010000000000800003fda7a762bdc15dfe921ec44b8c8897288897fa4c21bc084ed2d4b8bc3e3fa33e878f86b3f91a892c720d88b5c3013491644ca5b01fdea7230eac5a723585e78fed6dbd0f0dabb39720eb8ac2b24d307aa125e8d50c81155b5259e668984fb701cd2f63c72566e6557d6b202612e1fc2e762f104c8d963cacce5c88fe6c1aa841010001	\\x4d1bbebaa3670863d30b13f80803c982cce25e5726dd579c8496c0f87bea6c30d6f67089b696f866fa35c84f605a3457c66b81683a6a5d1dc83a9387ba9ab106	1666550440000000	1667155240000000	1730227240000000	1824835240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x021ae886636c38e193f395c185036d1e6ca1d5bff9453720ab48898d5025a2731ff6021137ae9f6a294d485a1f6b15636ae8ac0da9ccaee8ba17e429bc5923b1	1	0	\\x000000010000000000800003bd5f0375af69cd5d2c9c420fc8145e6663626d911bfa778bdd5857de19680450e77c23282a10347f917fcb528d762e87255db3b3c335e84583e88db470f1ed572677a8b755a44e933d062d0cf4d798031a4869a0b57cab5077ee6cd6c7b8507d4a231f79d11d321db1ea60fa1076a52704fbdd314009181f21a67fc45c411967010001	\\xe4eb5637e0077a1e5c6dc3c7f0bc631e8f7f11ba309afa137f34c81e1897dd223e57179ee604263c05912416f941651eb18ea655dca619232014ec55309c6a08	1668968440000000	1669573240000000	1732645240000000	1827253240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\x03e26a31c8ddcb45a1fece4a14c62fd7bd967d8d902c922bdfe30f236446150be70da586ff140b0b828c7cfd8315c89250ad311c3697d4244cc2052d545aa1ad	1	0	\\x000000010000000000800003b70681500eb8850db5865f107a1ede48e925cfcc637b43d3c7bcad13435780e525799fde7a376ce197604a3ece6e3306268385006edb3fecfe3fdab8ed07add712ada343750a4adc815d92f450d54307fbe41f46f5dc2bda4b6fedc46c608c9494a4c0a267cd48a07506962420c8e64d50ab832e29974def007af0da9eb04de7010001	\\x297f9250a1db5f4290c0d104c5b78a1f3812e7bb2a2726f6228d49c6e2fb9f7ddb2f9eff79201c26b5f3618d02b14b7cc92dfd7e6d948d3101a48ce956f5d603	1673199940000000	1673804740000000	1736876740000000	1831484740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
216	\\x058216eb4cacc134b434a5eda1f3ecc6b2a8a40df7d9af5edc03113574856cd4c11a158f6622f61dfe241e401e80429584f8130f3285154ab1f107f59598c764	1	0	\\x000000010000000000800003da3b91f3e182ba1a74d7e0062bf315382b3cd57a5f21f79ad0a16d6d4ebecd34dee999f8aab3a75d23ac5ca142363e092b504d56a05037cb6177f6771d7c82438baa0ac7823428bf930c787c03fede85467eb537e893bfb54037f710e78c6c5b9432ae0f5b28c8dca3eaacf86729b026ddfb701899b3a7baeccaa61d48a233c9010001	\\xdc1d52342b044611ca54d8c881b278cc3b89ed01d0fe8707e8c89a7d330fbca2cf19a23f54eeb412f142fd98cc35c691c727188aab0831cdb6fb8b7e1332b903	1678640440000000	1679245240000000	1742317240000000	1836925240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x061233ab97e4b3309fe4713e3e4ea86efd7e34a1a4863f9deac368bb71a928939e19ab95d7a06b1f2eb8d07bc972ad42c3d34ed6263a545e4229b32330065249	1	0	\\x000000010000000000800003bcb27619399147bec0280b51e91de37e3878bcd8e5e8c1d1c1bbbf4686385d4d09a4f15e48ec2eaa1ef760759fc1f641777dcc69012c9b6dbbbbc3f712efcca63a48c54e082e6904f4bfd27300726a58fac071b3d6868c991c87a514008b53f37eebd2d78e6ade9d21463800e65d21329d3cf00dbcce6ad942c0c6fdd1ca7e7b010001	\\x73f97bb91dd43d816be8a95faa0b1efb160b1933cebcf54cdf997baff701d882531832fe2d5c72206b6b8cda1a4f470754614f516dcf3cbdec799b055a62e900	1674408940000000	1675013740000000	1738085740000000	1832693740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
218	\\x0886a5d21309ed879e69c048ed2a29c0b6130b9b4775e7ca9eec7553ec054c465a5fa691208e9690fa1a6a648a790a308a3205b495fde8a75784415c740022d3	1	0	\\x000000010000000000800003bb6fbb51ed5e6fa73d18f4a02f1b483bd6cc9da9f561e6bd50074a966b569aa96f60595111066668d1ef86381eca42ce36028d61d38a8e9c5654a52fb7a69071053e294e2c674dc7203bf938f5e2437cdd3c502c3245be2269e78dde22e1eaba4e99f75df024ca6394cbf026e538bb7720ee175c91711aa1dc973dca8b8cd083010001	\\xc55101cb5355d5917e008ef66382014f7f0385c664cf8b74d9aca8ea86a877ce51f35bd585c327e88f50d41e9a2b99e57d6dd4cf0874004527b8a7e2d6811b0d	1675013440000000	1675618240000000	1738690240000000	1833298240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
219	\\x0dfac91b048e1cd8e1af3cffc3b12e3e92d16a0c0bd68e64be71ef23b66aceb3dcbd29bf86ed58e6272cb013cd2fcb187fc7e70a5cb0b6512bb9843b6ebb5d39	1	0	\\x000000010000000000800003c496a355a22dcdb2b9c45e87c41340e3c1ea2ebda180df17a501a34f7dcfc87c9f755b8c76e941250cb8c33c563032fa6a96ff5fab8cfaf8cd111f1a4c1bde436f780902a835cff2201fe5909d87006408ea57a1e4067e3428a067365a3c638ecd24fec374ab2f1a59212b8f2d245e8380a5ca2901a647cfabcf7ad73e3bb257010001	\\x622c4b1ce1212d3f1c275f4b48ae658a883a47561e8eaee8ae50a79fc7e7be1e2510817e848ddb9501d3d181584b6ff330ec5b79ad9cef4512de3a2718f0a50f	1659900940000000	1660505740000000	1723577740000000	1818185740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\x108afa460f50a26d22cc0cfd6fd4ed9b98889b34aa7bb379eee7b0e58a9ac952df5372b59795766d36be799f16655b76fcc62b877f5ea1b78d21491622dd76ac	1	0	\\x000000010000000000800003e8b2aaa9cb63e8c2f7b54450f2f4b0a785e76a68ea8ffd2afd3648374cbbc51e20feae84110792ddbd2b1fd16c1bf41501539811e0f008fe8ce1418b311a346036d0249b986461489d45edf2e927ff215ab80d3e6fbc06d7284bbdb2376b432c9088ed8939639d88164e53622edab2696931e1f5ff4d3cec23a1b33e26031ef1010001	\\xee07dbe196066059397169c4045409ac1bb61fb2cb4be437ee9619a06146e68740c2265356d8a9293dd649d1193e268923bb2febbe5aaf8038aaa7e8fff1c80f	1655064940000000	1655669740000000	1718741740000000	1813349740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x10f605ffed094e20bff46cf0767457372362f159885899965071557b6c33a7d62f95b95071fa8c0af6e97743b8ac541adb68b959a8cd934b095b19b722d300fd	1	0	\\x000000010000000000800003b18baf3210593615f61ae0afa7dcff987ee00a0eccb1961db23e0cb552c56fc56664d498f713e7d459253a9b34018440e48a6ce0d92d1340a03ae2c01ca59a80fcc11b60d39691bf536caed7530007e1f8ff1802d2b6b8a18415dc662475121719d2b48d724a41a0e544457a695fec40b40dbba79eaef02f6e0276067c9a2a33010001	\\x9b9f005b8ab1abef4cd332e133589ec870d97c4a01353e4d700384e1f9be944fa29ce4d1ce10019be827b3eee73d74ca118e672f4c35b075651dad9213c85007	1671386440000000	1671991240000000	1735063240000000	1829671240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x130e5f4415e649ed2dad8a05e4e80517be97fc9b35936de07f0e5aa21ea506c9bff31ab5e392390536dd0986ffc50e570d12ddabfeb1349b7b8964a1ef18edbc	1	0	\\x000000010000000000800003e8d84d60ca81c4e95a6071f9c93567a7ec3c2db327c7ce7e4a37bd89fa0dfcb06fabe71fad08378840478789b7a62e249f2d380d97055bc486e8e75633f8beffe8e41aee0d388406e0897ee04c8dcd111c9bb59325a4f39532486295b91d9463a07a3c23e7c165eb39c9d71461f7806999c19f6163811f5f47b4944d050c87b9010001	\\xdb173030441275d13d121e07cab1243f255c41352357b1d57dce0f0fe9fdc307ee12834c4f9c62ecc2f2b64bf0a44ae182e191349b200322d9930967a379a10a	1680453940000000	1681058740000000	1744130740000000	1838738740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x186ed35962ad3f008e48f91c66aa27cd13d53ce51ba4f3dc9f7d88c270d847af4b9893d37799aae13e955cee47633d925ec937a8e8bbd8eb347254bef13679fb	1	0	\\x000000010000000000800003c6cd99ce40b54cee8dfd6a1b9bed187b38726f04900a3afdb3f2e4c7e77dde578fd97110c84caa94dd0fdc2247c5b7e4a1e19f571ccd15cc4220b849052260f4163234a0e86e17f34599a7e8bebde699e53fa9a839fc505b5c500df4f6b8ee5fefd8a24944ac7d48eb6e608926ba3b66c12a6b12a980a4121983432b91c84e4d010001	\\x91b54f1b49be152cc781987de97dd2e0beab2f9ad9c189c7ecaaf91bb49513fbfe764ebbf318d885138182a102142526a89ccb1e8062ce126cf10f411b77410d	1675617940000000	1676222740000000	1739294740000000	1833902740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\x19721c1a05224be849e16893812e322f8f42be412365b289a4a75065f481b2a1bef8a75d68d5a7905b210891111139e80d9a15a21c1ec3d576a2182b59e959f0	1	0	\\x000000010000000000800003b8f70af2bd17900fe67ba902eabb09e4081cd90ea4e56edf3bc8d7eae086c87b859c8c4ef2b4f41db98318e002eea0d1940a031cc8a53d074b8e22d5eb66c762bb3ccea0290f7a21233ad173d0b32fe56eafcc1a32c296cadf033056e5c7c66d99684e72a9fb99a31442fbc076df7de07386740912c8b7168d672fe2269ea505010001	\\x757b2f38a1c07c4a56d7ff0a13e188d8218bb95b144334639f81d62a89ab0c880ff49b19340c3dde421be7d9f0c764886aca91ecb4d78a1b2ea8c94af3c7ab0e	1686498940000000	1687103740000000	1750175740000000	1844783740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
225	\\x1c56e6817037cf8992c72e172594131a3a0e1dc1734e5d1a287af15e800f5fba949058e85850657e99a7e8ac24e9de6d9ea6b2d2ca416f069ca4d475b97c9171	1	0	\\x000000010000000000800003cb1cd822a2bdcbadbc751cfc38c579df07e86970fd834ba23483237310cf70040bbd15d40094601fce84a8ba03fe3d5271b4b5a9fc6e745feaef12780841bf4e67fdae156090aab9a4ae51e97ee192b78aa860dce501d5539714c045b94957af5d5b7e6f17433fa40e2c08897202a95f436b283f18c000f981093ddb1addfb53010001	\\x648cd602db528694a660c04dbfffb292bee260b65945b04e9083e1aa0492fcff688a23a89995f4d4b4981d2f8a5ac658834ad59e8297745fe20bf3a3f7e2f701	1664736940000000	1665341740000000	1728413740000000	1823021740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x1f9aa131c8993ede45b9440e3bf728189d3de0e3f9e857b1f1d9500eeca4284d5e8ac1ab8477214bd907c57381e136402e6ec3f6cb81cb9f642e834b4d5bb0c2	1	0	\\x000000010000000000800003ca5917154f3a1a0b01373f3d7da046833f2a019676c8d9d0e6340264538c77cc6d09bc0f3f0a6f5a237e35169337bbff541a57e2d66ab17eb2e3076d61c0454b638924ace623c68dca7cfb706d6649e2b40653570926fa0c96d554db953173f1a2a340de146c6f52060efadf2b33bdb050c33f66908c3533471ccb3eabec990f010001	\\xd47616c1f747798bc8bd60f8c62be1f4c455ab6a3dcc9b63cf4c4439ae2b5a7a7e9f882bef736d9d11c74a4e89d7add403dc236682fbd316d9ad9c0c59dbf70d	1673804440000000	1674409240000000	1737481240000000	1832089240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x1f2e7ca36f9c4af26f132fc9ce49243a10ecd5d11073ae9ada4c89acdb63fec9cf72b7686d5144d78e7819cfa106fa5e38b5855af3c8dc1d58cb1cd1cbd53880	1	0	\\x000000010000000000800003cabc2337e0893c3f1e0c37650341c8a9dc0d9fa0bb10498b736cce061863e96d9334de67bc50c71706c473969a2b20584e0c50c31a9f804aa4b019f8fd4277c0eaf0a570ab1a663ae833e6d3ed9f8ff5b7410ff62b54596f47d90fa8ad5317d6a71e73faf84368a37cfee61a304edd7b923aedc32055acaccc52f883d5c462a5010001	\\x878da81b3fed1689f751b7f5d10cb52a78155c7f64569a2a3b2dfacb9313ce242a4409cdeb054723969b3a77a74648207c758c40b949247ce2f329171205e309	1679849440000000	1680454240000000	1743526240000000	1838134240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x23029654d8995088e55000b063de9c697f2c5d45e69b4dc145011575e1c20266b4b4c0fac2e75c6861da88306ccb78adbf47d137f44715f828be59ea2ce08f7c	1	0	\\x000000010000000000800003b110b5ceacf4715b2f3ccf3ef5407f67788a48b7e11314083a5c92104ffc6b64575177c0a900f5ccde0d611cdea96ac9181673bcdee35912f5540db73a19eb360d3f05df8a6db5c7019167841ec3e68d5e9058b9f26d60cb23b90008c40c662eaac0a9d4fdf65cc17d5c05cbd35295abed2919964d05bb3a269558323c12d259010001	\\x463437ac057f0bb40d6ace69bf492dd720c5b782df91434b9da9920f6830ff6d3c28de44f18a8c5b89ebd68cf87996990c15033d6ab4068d3aab166e8602230d	1668363940000000	1668968740000000	1732040740000000	1826648740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
229	\\x24e6e9f91e1f328114c43f5ea38f1b4a0fde01b73e5b2b67d13838f3c8fd06892275c7f6b52eb5642e71a66bed8439ae85a7cee2d0bc54bf486c929b444ff386	1	0	\\x000000010000000000800003bb47d8184d776a9fafc6184904e52b2eb35fd51dff58f89a03948fc1b63ae04ea4a2a8ca1e28929b6fea70824a23de60013105c3f1031b6cd66bc4797ba4d5963f1293e3b26d5d2a3e2b9ac11ef90ecaa78f9a5c77cb2708efc173275ce39cc1e3c044ec74f1b8ad3a05872734077e76d6df70e52f4af5faa71801b2028d8901010001	\\x1d669d1f09581768a4440f89912d00801fb0b2ca63f55876b75a47b6d9ddee6ac1bbc5267aa0716c8a2bda8a428e1d5e7453e85387ec24517ae27d5fcc3ac106	1682267440000000	1682872240000000	1745944240000000	1840552240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x241e676c5eb85a3eb662b4482ee03cc3c97159a3f2eb64995574f128a6667e2a4b63e91e55bece04e1d24c682b0a9710de58a165e806ba65e7843f402a5b224f	1	0	\\x000000010000000000800003b64a3d1c4c17afc1ac39088fde16ee83c2321cf0aa48295464c3553ed6ca5fcdbaba64ca02bd090b1eaf5710990b9687730291980666e9a8d7f0fc39a24a2c0122cd8997f39ab52835ece6fb7b98e6f56b5128fc1e780d8de13f54d29af8900629e58d9a369f8004006e26a1cb7cb64e3b84a2c989e02d8afcf7ec39bd508457010001	\\x102cf3afe046d43e9432a901dff0bcc4fc33c6beb07aae0617a99d83a14bbf60d3b2e072de7da86f85f97cb587e0a693c541060f6a9a2c2abe96232a9a919b04	1676826940000000	1677431740000000	1740503740000000	1835111740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x25b663109840e4fbb5b641c24bf91e1c00e1b18dcde9b60bb24a6e09ece6ed2372d3e592d60037ca55cabaed6f362ac4ae2fbcc6d40507493f557734efb0d971	1	0	\\x000000010000000000800003adf39f3cd79fc013ce7a41d3af69a8473473efe3741acab9e6082fa583e8a23fe081144ad693f8e24f972d36e55ebf2dc34485a5589526a3e856aba8a1586b9b2a4d664338b64561e65e9370ecf82f449c7ab864c9c23d082754bafe4146b075b6eb444f35031ceb00d7c244396067044c6973374aeac40bcfd893c0a3e4bfcf010001	\\xbce58ea1e17afe0a8da75a3eebfc9b05cf6c73bc3d9d8e8319701a1dc992a34205778f90fb4357d98029564150c8579830e01cb9c388c9fb6ea63804baa5cf0d	1670177440000000	1670782240000000	1733854240000000	1828462240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\x2656fa71757c66af6a078ec3c5f7a4b4f32971f048b61eb9e2a8ba42fcde3a08ecb538a74730207fbc0102a4f19374c4b65e39d5527c833ee6a0d6fde88242b0	1	0	\\x000000010000000000800003b1e75c2e4b3ded859bb3178906f4af1435f189699e02c0abc1a26111b4612ca9bd5aeb1710a9c5e7c1bc9031e92f5b7b95c4bbb5b422dde17f4a642408e4cfbd3a092538ba5e860fd16eb19f0ff32f08789141cb5933b09707cb51aec91e1983a9d9414a2965564473923c0e384724ebe0df3a7dae5196cbcb00f95891fda087010001	\\x72b56e39720889d3401723943e983a0a25e84af2572396d471cb52bdec39b1a3d1169ab7cb08813da0fa1b4285e074dd4f5b3dec37006676a72b89dff0db0806	1677431440000000	1678036240000000	1741108240000000	1835716240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x2c2efa82cecb71a0e00d05f548a51416a6e179c0e253049b15451bb0175f1b926ef2b665b7b51b6d6fdab13c65c4642428c80865115c88fccf6ba3870d77f59a	1	0	\\x000000010000000000800003e4ad355776546a1238fc6cff6795bf8c8d95a36434ec9cb4ca7843839e6bbc32edda71fd6fba0ffc2dfe25c98cbab51446d7c86233f0afa0c2437b6e08bf453b17ffa9612193024d00b5eefa5b5585995cb90e304a64a5f7e388a8f162e5daac1ede2be627a2644761f8da9c5ad9facf47bc2c5a2a37e9b1a6e2f117f8af253b010001	\\xb87009f9342352c662ab9e4f6b776d8eacee31f4fba61122212b1c47ae3e29b22db64710027aea43f4dda9b6c702a3128b2a97a7366d5f5ce80bddecf407dd05	1657482940000000	1658087740000000	1721159740000000	1815767740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x2fd6b6b1745dbb703cb2f959c54445b329934ce16d0cb6c6930ca65ff46864fdab79febf9ff0590cfe912de1f1f2de1d75abb324099a014ff10ead08d1992317	1	0	\\x000000010000000000800003bd8b3f9a7899c00e929fe83c1720379f6f78e55f0658a37c3a30d912955652858d8c10ecf3740b1c45f3f3c243286d9e90fff2b38ef21cf1753e8c5ff633b32cd99669ecf74f06de3ee25b7147472af6c2aea41ba1a1d833109fd1004f189d911a266325d6478dc39adca762f54942ccb2f34e67fc0d8b7dd854ae4583c01935010001	\\xaa48ae180b8a4d892009cfe5a5588acf7d49ab1fe3e5a2d72a95458641b6aeec672f1bd139444b2c6d569c8792aa4a56f81624b8eb1b168844575fbc12863c02	1655669440000000	1656274240000000	1719346240000000	1813954240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
235	\\x30768178a6319712d1e5e0ca3df54be1607475cee2569e461a8d868e758823c1ae0d2ed18a090bd83697ac5b6c69a65e3b2539dc32ea98b591462cf916bd4aba	1	0	\\x000000010000000000800003d37a9c921e069b5f75422b60d262d75fc400ea2b8454376af434a3aa0282cac8bf49723604f589d9012232813803889a2ab146efc0b97f491cea6b2208aa1cfc26630437b4f22dbc1ed39e7fa2062f5e871a4d442c4658dc8f42260271555cc7fddabf38fc3278b02ae909ba7d5944e9efeea0545226729a0f0a0f825c9338c5010001	\\xf12705b97dd9e0c34d4fbd1f229fbda10845eabca9d3ba5095f16e1d9b27a7cb9b8285d0d681bc740516f028a193f0af38774002f20676ee7e47290ba483f50d	1669572940000000	1670177740000000	1733249740000000	1827857740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
236	\\x30c6981d08b08a00349e0e40fad49493b516e6990c75e48f256c8fde30aa119c95f80e105dc9483a792b8757495ae711091519439a164d7f46d42a2dfcbc335a	1	0	\\x000000010000000000800003d8b308e4cfc9741f8d5c070783fdc447ec9c833caff6caadbffefea60a3c9a97745e4101d5ac74e5b73d61ca16862b5a65ac52a1585141e08340f5df186cc078bae37d7302afb0bca199c8ae4b7b16e35a0325e8aeb28fc5d1f2b2821b7060adbdaad817047bdb11dfe693a5eb46ed24312228f898e3a457ab064abad687d189010001	\\x619ab23511589a503cb90a5ba6781c31dde72662f2bf17e95ec3f342a21bb5730b51ddcd9c3f5ffcfe37134e05b1fcd42b658e185ecc223c7e82b2245e6bbe0b	1655669440000000	1656274240000000	1719346240000000	1813954240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x35e296687458ca708a5a39d9b7b2fdcc23b7e8065d7bf15d2e140abdc104b46896a0647ba9b2831dedd87a4fa0036fc25610fa40242089f8d1d15d5ee5455b81	1	0	\\x000000010000000000800003bcd21ab36f72f3160ba7511fc96cde99b419213d91e399363fc1a24ee2bed8b29c98c74b1d27227894274ac8e7c8c7ed297604ccf0e239fcb6182e9ba2661624bd7810f9dfbcc8598af410dfa1c1de0d5a80af8c96593ca307b8bd67586e9767c230cd26b4aa678925ab45c980720cc12e42990cbae8a98c1b1a89a9e212591d010001	\\x4ef8eea0ef714e52f4203acaf1e8548950ce90438f425caa064192055c27fad88f4f04facbf1f97926d5218433ad252575c843b0fd3317f73eead2342ccae108	1676826940000000	1677431740000000	1740503740000000	1835111740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x35663247de0a1ad16cec5ba06af68e0e059052a84444264616089cfa9f93baad2385de746d66692b15f618f79402761199fceae217007f68c46902140d7bb3e2	1	0	\\x000000010000000000800003accb47a86fb831fea43b1d6e9c024d4196ce94285a6e376bff594367f00935bfd02a840999f49add38e340f7819d45ab786c985be6aa061196aa7d9f8738651a5794406c2dcc9535851d5f641d7433e124b025eb47f06ccf04d3909627e7ca8916bb67930c5c2a81eb38d865b87747d8b3ce4a475f185d1a38863654d81bba47010001	\\xd3c144af21e7e78c2501d3abdf6331867ffa0372895b2403f1cd11378d81e7bacee2cec8840ae12fd3f7e7e0867d02259844a4462a0fdc5ad9215960f200980b	1678640440000000	1679245240000000	1742317240000000	1836925240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x378ac4917997b1b864385089e279f3f218b83ab8931bf08e4f70446057f6a0e7bbf9753bff2fa7f187f96450f46cca19a5c62cb74d0a1c895f6459c4159e09a7	1	0	\\x000000010000000000800003e03f3c94ddbfa54189e2ef4c51fef66cd11eefb71b1a9b6e7e06e2f8df90c8c23c7a684bf38c97bd7b892285b7e3392a8491a304bbb6da8b2d861f442f9afe8e3e441fff23750b53ee503a5b9f75febef41386e2f0f76ea83e31f4beed39c8c3331d0543782a77a69e1f003ddac0344093a2e92f9b021eb2c79b376ed7b3ff09010001	\\xab24c49fe068010c9cc465bde60a105a95ea47254d75fcdbde8cf0799e70f0d6f2bc5e7cc8236592a40faf6e88ffde52a4267614b8caa69e9bd4c3d4570fe40c	1657482940000000	1658087740000000	1721159740000000	1815767740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x398a0e073417e8f019a6c63e84f4f6ebfce4cfb9c63d6201b49cdce367374e97cfe8c377b1fe29536d6ed80c2de58c5cfbf9dc58213f041b066711777f2a2339	1	0	\\x000000010000000000800003eda678ea605ede384b8ee25883d51613d3e9501d518d2e594936d23b2b353b58cd3900fab089124fec5329dbe90b63269ac02b017ed3990813f91ecec3a6a7385e8834b86098845aa31f7eb12159c850f09b324f1a3135c5bef6c537bd8633abd07a66759ea7fa31cd17d759b36f972fa307205b6fd914ff70fcfe24a5ea4393010001	\\x1c2b5ac3a42128a02087242ed7294b08f80528547279d9498f06c87cafa854c29f4f12c5472177a13efa5a507077eb6f6ea563894c90ec8063b13e01bf4fc407	1663527940000000	1664132740000000	1727204740000000	1821812740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x3a7ac9cfd7803e2fe4e72ca0f843c0515b191daa216d4b6faaa69f84eecba349e53baaca015585765cdd9ede773689d895f28908613813906ac583b211bce49f	1	0	\\x000000010000000000800003d68675d9bb9b2428622eb7a71a204d305984eb7ff53e9342c792308c71e322e4b90e83e085abd37687484df38b24949561ee6d3fa0800bbd774d9ca7ed75e639e25d41347dfbdfe35612b06edf6ef5152aec72415cc4459900498228fa803d2a78ba1f734bb6ff8ea60faeb2ab8374409853f40d5d8aea676c4291be13907deb010001	\\x821bf326fcdd83844017a064df8993f073947cb367bbb329648c8c7a9f9176a6935ff05df0af27dc18df9ef0181b2bf40e81f1ac07874f11b437a3d524c1150a	1681662940000000	1682267740000000	1745339740000000	1839947740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x3c16967669a3beb15807273eb141c6b220a5ba504426a465c31950679fb27db2265563dbc9e91a800a2f2d13de2cf18fbbc17928cfc9c48d9e2a236c87063b38	1	0	\\x000000010000000000800003bc04feed0d118f8f83e93b1f9b205e525e80f236f8f62fa41abf9a59a75b9fbff34e9a71459f0ac7c0ef99a174de16df87abc1f4a25a87875480ffe595137a025f77649b0ec12d42be24b87c9514a334813a6f32cf50fd9de055c0c0804ba442c6f0f57570c570c2787de3c1ba688b066ae28a077d3d5c025d27817a31ce74a9010001	\\x4e5be6dd71c072053de89c08652805746634dc3ba8b38e4e3c5d830e24a3b4a1bdd6a685d06d933bee412ebe271990777b29bdc044f11a7e9a64a24402015507	1661109940000000	1661714740000000	1724786740000000	1819394740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
243	\\x3dc60ca4cbd41ccf7ac7b7fc61721dc74d4f9dffb80f7b3f883a7326d80598d39bbabe161e2d0a7ab4179c92e6a4f54e2b0a8f14b64203be77b3ecbfaae9468a	1	0	\\x000000010000000000800003c98719dc54590c3ef074e17cccda6cec0f923f638efa65153020f84ef2c962fc5e55a3b4a5c04974a31930b600da269e17134934b219acc44a84af2ffadff006b9065b89d550e645107e0ff8866a374b4c340bdde07125c24dcdf1bcc9eff7a6b364c3590e05c2d61d6b208c1dc2792c1eebf53cdd99c848104b51bb9b9bc601010001	\\x4406e233a31034cc440333bad3f6dae1ee97468f6472d1533802e8e023313be4670ab836c6e4259f8e57379f2d226221d5c798532cc61867a60582e9c0c7a400	1682871940000000	1683476740000000	1746548740000000	1841156740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x3e6e8c9ac1692977972478b28baeba69180672fc3948d0246c3f1b74ea210609640a40558a7d780bb112568963d09a431cf2a62938230d9675c2255a26b6d7fe	1	0	\\x000000010000000000800003cf49d2f543e8ff106b6e42cfd1320d426e5aa05cbefabeab75695a95407c709afff6bfd62d93bd864bc15052a9977e5f8e4fcd3780f5142c5e0186ca98c537a12bea01cc46cbf4c607051ce642d6f5a6f1571833d23c07bcc04d2eb9c789cc22d43ad024685290a4f4e6de24fc0cfe90d0003b21b6f2f1fe9602742f8f40b86b010001	\\x5a748422b4e672dc61755d6d7a7ff37a97cee97bf0a2e3308182376a8021f72cb4032e12cbe962038adbe0d01fc33ef3aec13aae446ef66e39cfec98e2ac8d03	1684685440000000	1685290240000000	1748362240000000	1842970240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
245	\\x3ed2670cc9c298ba1a63f93e70419cc1b0bc0c7f11bd6af3c518dbfdb3459ea183a47af4ec39f12c4e9d2106fb598c30aa3d6a2c792470d1768f50ee018faa1a	1	0	\\x000000010000000000800003c4f0d6d211eab4eb1d12484f0093702bbd791ae857e953293cf0b56409322786244a2ad3096cc9bfed2e10d5c7839253150c18188793c189370e1b40acfb2af5702083ce6182379d69b4ea7a8e3d6ffe45cf1b31b7cc3e2cd7e42607848bc159798aa4d3e6df7c505fa2eb8e993f599b73c55492cac4b2cd792fd70b1c0e2a65010001	\\x79c16ae6a3bba5d57b661e3225cba01ef16b4bf8297dc4ed3ea6e6f2571f6007f708b9d68cac98c21bf449ba78fab569719f8b6bd59b1f0470ab910bd0b2c302	1664132440000000	1664737240000000	1727809240000000	1822417240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x3e02da77055ff9ecfa2ea734e29db1cfc44c40fed43f9d144f4036461929839e626bab22d309aaf0096d15bd2e8d36d3229b4380a4880ec20d1f406824a9f988	1	0	\\x000000010000000000800003de90d83d2f9834bd1d8c360bc49c7a302be85aed6a6dc9248afd8889d9981157c9e3c7bd528100a8ad574ace2a46cada257f9972437e911b6f8bcef010914e4524572f13f320336305ff5129ca182484619e5b65c297879ff26bb050e1582846efd59785b86faff2071cc1fb42e227d780048da16992e444bda952a38adf04b9010001	\\xd920ea2b467896f3208051537b6747c020991cf07c378734cffec5fd4a977d36475114343d54d826a652574c49394a49af09feba1c554ce0a5fbdd94e11d3f04	1658691940000000	1659296740000000	1722368740000000	1816976740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x3ee675519f16b0a61e3fb26503252420ad0c84be56b5d70ee0b5573ecfc3f80c4b7c67f5b6bf8e2ff20847a258a86e16fde3f70047049872b0a51347c33b6018	1	0	\\x000000010000000000800003cbb7a74e486ff5d1b394a58282623cb664eac6ab886d38d437ed133c033f07055dea0e57aa56625b682c59ce31479623a6a2298854d089f47e03f073c600c13fa2603bc8d5492672df81f257e867c49aab53053ba1fc1b467e9558b4c6d0629cae6e5a1cc56f604bbdc8be282bfc8266c9b1a678c3bbb0657ed447810b3f92ed010001	\\x22216a5026ed1281dd4bbd097877f36959e91082c58715550a0437a3547f751da41624fe2b36f77b3da6ca249eb397fb158d5d81cb90ee4eceda667338cd4703	1671990940000000	1672595740000000	1735667740000000	1830275740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x40523101eb25394306803af699ac52c2f90f0538a462b9ca3fe8b555130bf82dcb16b5010ac6bcea2d59c0c519e5da3acd6a9e6bbde2c165a2d982b8fdf339ba	1	0	\\x000000010000000000800003b6d1aee63e4ca86080e71a1ac6865d045771044d16d6dac52bdfb6810da4984d7ada338ade044f7342f79c9530f716215cfd740d950ba634ba33136c809eccaf5cab99e5d2300eae27b0e09e4f17299f7b129defbe9193c81be62eb1ba3ce33dd7850a7cf77d28c63385be2da589d5631ce12d644a80f48305576458ac3aa5e1010001	\\x1c9c64de10644c8a4f533a798e7cd326fd5dc4cc096a9acae356f28dd442f2d326785db2a2c931d8c7e7f50ef49542ed2b7c113274d1d31a65ad25284bcc2d04	1682267440000000	1682872240000000	1745944240000000	1840552240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x444ecb064310a71a206fe9f1cb6e0c625c5ebefcb8748011b830ac77ceb0922eec1b47febd753aca6da0b21376f1a81d42d8af12a8836e7743b9c0e161c0d353	1	0	\\x000000010000000000800003ab6247b3625978120083e7c04d7fa19de1a1a21c26bfb6093e672028f28c8091e99fe6dd5b06eae18b9e598928b3b7bae7742b45a3bd102f5082f51a54141488df6a7300a8248f3bb91482a23e748d52eb3cb3bbe61e2fc5eca087e99b83e45d5179b42a9931a08621695be4290273a9aa37e0b3737509c64afa5cedee141ae7010001	\\x9204d9d0568703c7b8c16ca7a113f9410927f90a6648a565b9463dfb2408fb7beae573ba02a5e8786169a3506c475133b1ba00e4cad6c7404e05839b781a7205	1680453940000000	1681058740000000	1744130740000000	1838738740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
250	\\x4952343820bb3168210e6a4c13c02dd71f79e2045ad0b910ab81f2a31e5ef915cfde524355b61142b5d937b086db245717f5eac2c63dc63221568f7db1883453	1	0	\\x000000010000000000800003ba1bb8b2e9bc9acd08a9f0d2c975c971a0caf455f330d325069c9ad9f7623ecd6b2a4014ddd4b4d1b98ed45d7bce8316229b571aef3878078b2cb64962bde46bb58a3d8023b859a77a784947d1b328f4bdfcceb781f61c2760479d79f3f99e821c086f02240b7fe62e2dabf8d1160797d6fae44bbf4d677073f69072ccdf02d3010001	\\x4340d245b232c297e05ca6038dce26c83d8a8d67e6d2e48307d84ed350eaa3def563aa4454af83f410ab7bdac718daad2b16fa0996edcb9997862723fb339308	1666550440000000	1667155240000000	1730227240000000	1824835240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x4a5e6983707f61badcbe0dbd75d4d60b34157000c2a9d2e633078086dec41b590448e097b481fea08aa2501802525246c2338cbe3f5960005b8d15afe306ade1	1	0	\\x000000010000000000800003a8834433e413fabf9f71a8917a0f9b40cb25848eda4f6d43e118ef6fc82ffda3e3593eb2e8eb7e3bfb3ce9ee2b152f4b01a46d7e02d377953925ec1e9b6efc3446c51ddf6545de55ad10c59f918103d3e35fc02440a682eedb245b0b7a2dd1ca38df56c695520cbd60c1bd5f547b5d348828e3e23207469467110bd6769020dd010001	\\x486c279bb06b58c614654bab241fa86aa219f44fe946b5d5a5601b0049cf2fd7006cba995ff7af15fe011b1ef324069bc054aa73aa9aae0be9db7e8eb3d7ec04	1675617940000000	1676222740000000	1739294740000000	1833902740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x4b863d20054c8c5a7e0ca53b9322e8972112e8e1dd5882c3e19e5f3a3dd5d3271302d7bc4b36e1bd891a950272f5c42be3419a99214b173d4a2e01bc908cb2cd	1	0	\\x000000010000000000800003ae52f290fed25ec898ce1b4a83ee4924974ba53a6d0c452352133a8c4e85d6bfe0669f4cb4059834f39a410e4b0d10695f03b4bc2bb8b645fe8e5fff537f0de482cf4bfb56bcbd94e5dc8c838f137afe6e98c98ecc957a9dba8f3fd15dddced1051221d3a0f0505de3c6d878c636881c9cc6078745128a3937055c6581fc3487010001	\\x963e9d588e7e7dec80ddc0490f5a1268872c6545f73e878db8645247cd6319b83908fc0402279c6a26194c0d003bff5858ee189cacd94fedb2e7a650a7b52805	1677431440000000	1678036240000000	1741108240000000	1835716240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x4baa3fd321dfcce44c65a2d6b25a04da5c34564722660a13b41d8354801b74fd4e7169d89547af63f6e07253249a7fa2b006ea77aad5ff8f2685477de85b5bfd	1	0	\\x000000010000000000800003c3353c8aa3b239fb21be8e9d88ab2b8acb70ed972e67385feae3c20831f56f7a93e31bb53132401d6167910dff3e60a21dc439ff811844091ec2e76c176d2fe7665dc0015dd121881a2b794c49e6909bf2c83ed69a0037275f345fd45c8c453b6fddbf8173bf90112243589a41f231cdb83ffeccf1f716770c7c280843c0a4d7010001	\\xdf5b095f0931d1495265d796a59b26b8a914dc98b17426a0f09723de1ba3a3ac0fb4c0efe262ab12748784813bb47859984c48999856c721f13fef594841df04	1671386440000000	1671991240000000	1735063240000000	1829671240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x4c3630105d16b53e8a82afd4f515473a71c447b195fb71768bf29aa9759df68ab73cc49302861f9f2e0577809b9922a8664457184118d7ec854bbb6ac07fc836	1	0	\\x000000010000000000800003a6220ff4dc32087965b1fef66cc533875d719d95d0967e653c50e298145d27f5ad6dfdc36ee7e6b9c2b09ea9ef2566eed1c10632e9e51c6a9c1a1e93688aab14b6af267953334a81122407ce8e05c26b1be4f6100d7248bf440e1901a2df58bd855fa4f009b7ebb20ebdbb4325af986e014853ba07bd8b46089301c1f804731d010001	\\xb88c4174b808fc0674f5a6efebb4adb0b7bf43dded7c4b4daf8a0389b9d14068d6492c6da5838a061d9622412b4b79eeaec12c67af63c3e25ba556d5df815c0e	1684685440000000	1685290240000000	1748362240000000	1842970240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x50526ee0072b7e23d9531f2a1aaa322837683911ffb31cab76b26c83407901f882857823b9202b3b1df7c1f5f007b5d61e5daa40e6eddbddcab00adafd04a247	1	0	\\x000000010000000000800003ada2a97ba03366fdafdb447a7c7a8ae79cf5af83afa52e2901c7d2bd08b3c1ff4b5216f39bdd10bd60b0dab013a47d2ca1df90faa71b5411d802d217c228c1f7d40c3b7250f337f11d3ddd9c4b7196d8600a371a431e44efc099d9978b911c0ecc46831d3825d4b49ebfaf0d6a183a817ff6e15be6da62d72a6f630a949dbd29010001	\\xe64e6b685e69cb0b0f93b24d7f016022fd378867b3906e1eb115ede213332f50b1e8d3aa831a76bdfa5fe02a00d0f1c7a04d04955628ea416d69147003b25707	1669572940000000	1670177740000000	1733249740000000	1827857740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x56969238924b42697bd8136e0bfe37118e805a705059fe4e020c780709682cb98c9e79e61c32a661cf2ded77c695d077993cf851f00c2b6d2c4e2fbc6449216a	1	0	\\x000000010000000000800003ab1ae5d5ea47fda8797b0163061c30f6b04c531ac7543b0fc019e270989c0d14edfea97012391f0136573af748271d48d4a47766fe4d324c7d152ca34a5262da23224286f71c87673005d44de5209194495a39124b626e34a1e124a7fb8165b024827e6c33dd17163755fccee6bb6539250c9589ea3a366ce4f579ced720b019010001	\\x2864832be528b0a932e4038769b3e5edc1df31eddf4abc9a2dc762f3ce1648cf80fd53c9570d99ad178ae9715ab3564b1002c7af1c0b54ff35c71e625d68f701	1665341440000000	1665946240000000	1729018240000000	1823626240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x5d8ab904d755c33de51c77b66ec24bc60931af66b147d0fc35e636b80a231474f683ea0261e930c1426bbe2de84a9aa5ca1618c8dca285d4e10c6ee5a99210d0	1	0	\\x000000010000000000800003bab0962e8d0ddb628d801fb8898981ab3f7434f4d028ca90e011674e36adb5314f3acb34ba7b3c83f3c15d013bde0da278033e492a553aa41546d052c79c229f318a9d59a9d3bb7b43828b4b0fbf77e87cd54b99b7de10b0fe87e07154be18ab7a48b47fcbd3f9154a8f582763a0dc7296010002cd09fa604607f6620a85e58b010001	\\x0e0d16236b4eae7fd2019252855ec4ae1cb9335c79e1afaac74c4ecf780b2b4f4b9cfffedd8c95d67096f28299d1b44ffda7232fd07d8c34dd8394424db8c806	1659296440000000	1659901240000000	1722973240000000	1817581240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x5f1692b2bd82cadd1378e201171500a020da2fd124b5b8552cf77d725c783d0631eacb3a0434b8a2c4b99dcf9d589358c61c95c218dc9bb704fdf58c4b802819	1	0	\\x0000000100000000008000039f8c3834a85bc442ce98fe022a4fb7caa07955559682a8a40a0965ef79ed752084f6c7b4167ed38c4fe8f826e8f759250f7275e2ae1c0354975d8d07b93292a6a71aca1003612d532790f0274681ed3a60a2b00b9ea9e3416487f3b1ac2a0598d8db5c943d21fad176877a126efc7ccdec829019c53b80dff55e4345a55c9b71010001	\\xe717f750108139141480601cfd544699b450139dbaefa66b21bc14187d895b3ac2601c9ee56eb8959bed62a93373b6e9d5fbe44b87edef6edacd9ba8bcde6201	1661109940000000	1661714740000000	1724786740000000	1819394740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
259	\\x61166dcae67e8e9b30ffe299bef8b5281d8cb1c37f6cbf26356cc0c509784ddb235487d9564085da1358f6c7225890ae5aaa934bf8730efc2c2dc3a31634e3ed	1	0	\\x000000010000000000800003d99008615b01fb006939e9cc12ec22573a7f2215e5d16e4e35373e16b36fbc9f6d9bc3d7559068be8e6a1df1223f5fcdb996e176f375d614cee0ebf2029ba30de1ff3c5ba36b47ccc265a4660cb85c661bc9e80c8ed035449515fa883c0a2a33efac78ce76dfed57cede9a8c7dc665379b2ac5ffce3f3073fcb6a696b0535f5f010001	\\x4343faf093d45aaebc0fba1fdf878ab4eae1f79081695b54995c5ac24317e50b4a4b2151a448dc5cc1f2c531aad3317580ce136c1e6c8cafcb9f82c038989802	1674408940000000	1675013740000000	1738085740000000	1832693740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x61beccf58ff2e7be8781022405907d0323cca3c70bb3b981df05bb683439d1355ba4793ef0ecef7630125c223b10116956a8b2bf6dbf8bd8f5d1afb5bb0b5b98	1	0	\\x000000010000000000800003ed7234e2451ddaf5eec62d29f3ee2472e2a9b25d1ac840c5acf35dc146330f930c75494d59e0ec4baf0bbf8fa1bcbd0b2638f5a0d7b0a4bb11881d716066b76448de84ffb99308dc866e04dc53b2882402dfb02fb21d505432db90d430fdb604fdf1aa1b9a901bd0bb90378870f763c12165b87cccfb2dea960276ddd8e42b3b010001	\\x7e481aa179337623eef45b2279aef6efe3a2c7e19422cdfa63864ecb16bd3f96c20cb9e39303908169e8676c2ce435c092045edc1a2fc4e3f38e0c84f0442105	1667154940000000	1667759740000000	1730831740000000	1825439740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x617ad6a0dff8fb38dfc4669854c07a801a0de25310f161d0dc5dde4ebeb3b5f75152d644b0241c1f33647cadb5bb7edf15730d5d352122f42c546f8d564fce56	1	0	\\x000000010000000000800003f047e6a6a663faa7e8e14b50b38885ef35024a2bb520a1095681de2d0335e964e8f5f1c5a49bd9c831d0024890395ae4400b6280420bfebfb09de195f24c45c2714db9780ff03dcf69b4eaa835ba019cf7b2555a68349350ac4b9a6ee4ff6bf06a6a3b5eb1d043bbca53161fb547ae17cbc7a56d4314eb7a072626ec6f306763010001	\\xc3a5bc22ecfa7ab648d6121a11c38a43d8bfd03179a95c489578ab3bc16dc7c3d7def41c239bbce3c3ffd12f7d2ca832e2c1cf26badde36fcd17c5cce65a8c02	1656273940000000	1656878740000000	1719950740000000	1814558740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x691219674093bbc991b4372dd871eaa50e4997415587e030efb6fc25c17c9966300da4e69f3d9464c0b634fc666a492be293c47db89b01091f50f54cad1aa5b4	1	0	\\x000000010000000000800003e766ab2535989c58f957f7864c9a824fa80bd4f8880b19b9479a593eaa5e47461d2990140cabb517739a40013e7b7173010593d8befed798a2b3d8424b460d675899e6dc53cc7c85eb4c8d68d0994fb0e206cdb0e992974d03ac3018866b781b997029ddf9e7c698ad831edf2818c8d8062661eca14c944979b233e243ab8bcd010001	\\x7c8f66fbb776ef66782174da028cb68cda41e9b943cad0d78e769c418d366fecead5596371ef07719de3ac10efa857a3ba1d1fa6459f456ea5cbd3168eca870f	1683476440000000	1684081240000000	1747153240000000	1841761240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x6ba60428fc5534a480c7ecc448469346061be36fc555680c054bffddfa2de38a7ce8ff661786ea3d4c62bc5db1fda90d78ccdaf6e8cf60379dc5f3bc633745b0	1	0	\\x000000010000000000800003ac609ee4f6f0268ae253b0aba8ac03b6b297c7404e52c97d530070bd455c877a03631621f0fc79d4b57398c2eb60bcc1cb94a772b951df03a6537bd33dc6488801a4c2a953e678ab54aa8d1ab609d10b865598f9158ab585b0648ae6ba2a077d86530b46b0ed70968fa72aba2813a1c604493b2c75155f88862a62d236c0ac59010001	\\x7bae482f8109929e51121e0ba08770ef06c19e917a894913f6276ed3bf21d223feced2697acab64043097edce5b2852cca1ff1029d919ef2c9af715f3815c10d	1685289940000000	1685894740000000	1748966740000000	1843574740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x6ff6968c8befeb1a02cb67db7b2e168750d7ba406eb266ecc9c3f59339a0c4192ca00ddcd86e82550fc7785ba0c51acdee40dc421104a9d49b24d5d8d4095939	1	0	\\x000000010000000000800003beb878904f2ee6c76ab8d67791ad2469651c161f5aeed6769f819d73d8bb958c0fc7f026d3f07e1da45b01a123370d13b15d0b31fa342c877e7f009663b2daeb5d25f72f6251090bc3f34dc105c0e8e7253f23dfe538f14775d582c361976626ecf04855ac7b6656e7149debf5797d7ea44f699f77ba62d55dafe0094a106785010001	\\x3f2743d214956e5073e2e6c1cdc7819992b936ad769f975ee1ab3bb3b2a821e47d3c48c9ac759bc6b63adb6dd454d2e4c969d308b9acb2956ac2a3c4db5ab60a	1662923440000000	1663528240000000	1726600240000000	1821208240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
265	\\x7026a17cc35b6a75baeff63d947dcd4c54bfb1efc32dc1b0b5133491d7a1669f9a3150255ca0695c919a18b5003408ff4aa604c73f06a0033df272f6db4566df	1	0	\\x000000010000000000800003947317a4e219cbe27f2f7cfbabbdc783ae41030884f35e401ad074b9e8d5c6f1841b52997bbc9a3edfeeb10b29c83e00050784623ad0439ef13b62acb608301946f31a6d1e39f29f4d4ea6d3e312b8393f16ae9331a8d0d782af03d3bca56286ab8b610a90a769d1b2e05cdf36e33c1c334e63ed980e2c7f0f921c8ee7ed7153010001	\\x54106b0b1f287086fd1df4203bb18d23540cddf755fed849e1561c1866964316a0dc115df188e912356e8335f62d5b9133dfdb6366e2d9ef486f8ba9b991f008	1684080940000000	1684685740000000	1747757740000000	1842365740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
266	\\x71c64aeeac0347a38900b255195579d459cf770fbab7d1701908805a038a9c171dc4b8383c91f6d9b263d7cba5c95b8bf44d4506a33afc05e064a45ec7d1c34f	1	0	\\x000000010000000000800003a2ab37fd0ef891a4d873f67852a069196875aae7322ed7503d10ead06a5ad154bfc0bf67e8d831136a43b1ec6179326ca617b825712be3a5b5c934cd6dd6838344476588c327cd1ab50182c52e1e1361f92ccfa08147b60bddf2e77b8ca9727c37a5ca6b56b32c7c3a06399f01756d3f5b06f514fef4567639668870f3b82ae7010001	\\x0c473ce219175154c0b15a0196d0f7e66859de63ea62cbb6eb4be5fb82ca3418c8f6383d179c76eee42d0e6c59869eed5e5198da84a1f048790c542d3bbc9207	1679849440000000	1680454240000000	1743526240000000	1838134240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x7152ab7a45deb45eee2a86334b82cd1a25303a2b1d5202bcf35c599b6aaca334730e8cb9d84a33ccca104040d29d7c7b21e31a1f185285ccc881feb02c464520	1	0	\\x000000010000000000800003d797a964a02f4445309a39372761037ed6221cedf86938e80475fcdf2bb4ae73ea976ea19474ab92e85d05350ab509c198bef2794524768efd736db558e579e710ecce77c8ffc3813158276dd700db6caed9be273950eb751e13b1e8883dc01ac554e4fcd9d292477b89633a8d751bdac906c5aa20c749c8afad17f78140f18f010001	\\x456de888a1a0646b696b37f09c44c31b1c2fe3c5ef493c05172c8b9f5fafef97a115f4b2da576bc1afd006296333da4ff85e036f0ada3216eaa1a6ff0a9f7207	1663527940000000	1664132740000000	1727204740000000	1821812740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x720e8fb26a4e6c77020ba0ddfb03795cbaa7d6c6dc9d6d88dc2ea739163b42e6c31d3b90cdbad67f68e1ea58a3d91fc47d11a3578660c566ba7fcf5298633082	1	0	\\x000000010000000000800003ccd8223ad079ec890026909bc482e832c7d0ecf7bea627546852141cdb33fd70db674b15563a0fe1fb5c250471fe8edf7542adc392fc3165d3cbfbc4c613e6f95147798b110285957d1ba9a736e86c228ee812bb2fbd4fc61d8fdacd1674791681781077e7fbeb1527d074ac34cbad339cbcbdc309d85196067ab637fbe6d73f010001	\\x8bb991a236a1d8035b8271f92026ecb4a7257d679c9110f8c407510b6af66614dc7a10eda611c924b9e64376d26f0d78045d366b6195894919d7a0bf724c9c04	1667154940000000	1667759740000000	1730831740000000	1825439740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
269	\\x781247b3fd18ec128d344bbefaf88b79b3bc400b6c8b002b528f9dd91d1c72d5d9a619aa3aab1c6f0bc36d12e182ecd526a0bd173c333b006309848dbcc190f2	1	0	\\x00000001000000000080000397016260f81ee85b4c69fee4f100e50b191c2594b3bba0ba718a1c2cefcc33285df69460b51b40fdc630962e5ffd1b2a7bc0766b51e53849eb4df67efbf80040f41fb4efc47501526cfef7cbf2f90c63ca450664800fcab13d661994ee5d2da941280c217f4e332d96f9a630f4b211db7e090633ef86b804c37fbf29ebb9711b010001	\\xad0080aa793b0232084c8e366df92a3d0416065052f970245e697bdbee574e8a7bc0661cb95933537b7a094e65ad4b6e546f0e010b179761089a92c77f1cdd09	1672595440000000	1673200240000000	1736272240000000	1830880240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x7a3aca6230c045c10e681d91b56b4f739cec9ac8772fdeff4de85d6319dad0c3312ca48de9e539c4eb91fffc7c8d92a0fe48de29b9ec1ad464219df7d8f82ec4	1	0	\\x000000010000000000800003cd736c949dc2989dc724246f5bea20f6090f77b91bfb51349908e67c36ffd29852f28a83b61923283ad4a7ad6ab721908bb82c988417823cbcdf925bcca5a5a69efcdc37d1cb07b2c3187663510ea9d1bc5487107559077b0dd4b382c19fecc5d296beabf6977d028dc8d17f428b83c250b7d63365bd9d2bdba3052806f90f45010001	\\x145fc4d90f97c0646ba7f9b33f9ae84950c6cd61b60ae6f613dee47c9c66396dd6250f3038e20e541c44e7b4a0d0b765511d2b22a23396368b3ee07f13192404	1665945940000000	1666550740000000	1729622740000000	1824230740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
271	\\x7b7e2e3da9ab64c715e45be70564de3522825bacd8ef084582c8b7b5d8294f105c1fc5fce47a476245663c8016f3bb9263750a3116248642aace76de79e43717	1	0	\\x000000010000000000800003b376a4464b62fdd0b9fe3511db9aacfd74df8baef8fefbda025b0ea1db7e8eedba4ae346ae756a23e0237d13b6b878c660d409aef8039a7b3a0b3ca90b21378620440223fce8eaccab07d1053fb2969aefa05bf20267ffc62bd9ad2e2cf0022ed178129ed767acf51ad4f6ee229856720d802a432548cdf419eb8613041c6ec1010001	\\xb6f3dc3794b08739e21b67978fe21ecb3d81de4b737232ba9052571f249e83b2f85839eee471e456d426ba6c3f8c25333b1a4a2b817ad8b5e081d23453c4070c	1677431440000000	1678036240000000	1741108240000000	1835716240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x80ca3719114d10ffa2dbab8847c0be4a6ab38791e396718f2c971d207020d9466dc2dccd91d9d84c25bfa972a35be2920e177e116d2cd836583d84d973fa41bf	1	0	\\x000000010000000000800003c218b2c48d8a36f9d21df28021b24e3111196cf816a560905e272b4a600f89aead342dd620554821a1c6808595ca2e445044ebd80a91b429d45f237fea047446591800ce1c17996a1f56d34f553eaaad7af44d59f3a305c1239da79174c81e0f5b8f6dd7e29e4e1375b998a84f778a39fbfbfaadbabaef263499920b11f55a17010001	\\xaff659d9bf7dc085b0b66a31110a0db3d5c4eb4a922b5fca6c53140644f99bcefbca7da7fae85737f563aca4ff106adc8288897f113dd7c3cd392026c948a903	1671990940000000	1672595740000000	1735667740000000	1830275740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x81ead8d2ad347bfec71df427d298126e3a5be0df1792df4b97ee2b076b7c984b4d2c816a610f38b2d155bc83c60efe2c58df93b60b317e44cb6e7dea1c532ec3	1	0	\\x000000010000000000800003d3158e0a1fe4066e306ec4894253b10d825856367f8aac7fb1d3bf722dfc14c36af7fab9d81f13c28205da75451876531cf274672350541a08e36f430f3c48792eca99be9e83ebce1d2f21ada23304abd5e0815d67cf81f84aee4369feaebcaa39706d58bfe35d2c41f72e3a4d349c9eaa7167c65ea8ab4d96d6c653493f2965010001	\\x3c43e317b1bb70b80571390ebeeb32b4771e844a72fe2620ae5d1dde90333a2cd578712db57efdedba40a7aa35001313b15c2eac58680bc01bfac881524a2401	1669572940000000	1670177740000000	1733249740000000	1827857740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x84fac64f70ed45980084337038b05eae363d0ed31a8e7e7891497c8d2ccabf9e6f18c1e8ceaa03bb447ef2b441459c377984d525726adde5f2f4db3d990c69ed	1	0	\\x000000010000000000800003d387e2cd31d7ff60c930ab9d9504192c4d0d6570b212d89e93b9c76764d60f503bca6436ff5ce3f2c33bf17465d782c391e788d9e5f17345838b75368da0eeee58916490b10c6f0af837931fff2f2bb263eab41dd9f4fe23e6ace16748977f1897edb5dfafc84d55c8c66815e21c7cfe84f93baf77aceb65cb72dc5161b5d0e7010001	\\xc8924b5fd686387d8f787ae64c0a66d3617b5f422b897b7dcee4ee4d6acad843f2ec68c0a788e52fa5f20b852d07c80ab6e1ba470d3348bba6e4284170e27d05	1663527940000000	1664132740000000	1727204740000000	1821812740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x8bd695b4620c61b5931eafae88914bd090a1bbc3f8dd804d9cb3b90f13ab86faa6c869b42a18bc8cf698216147c73d5ee6a22bc5780859f29ef56ece5e7a1212	1	0	\\x000000010000000000800003d18526a3205e6f4d04983f5ed16dbdeb7e6054b72c0761736c2a44d4a881ab55c23d2b854f57b414b0e3b15186e73f24448c947bf056f9704128fbb5fdc603c9d7d0a5ef9bcf0c6bbdb3fae1c9ed5b08521b09ebc2b4bb62ce6e9da0c0876100e51abe0731b0f131a511575cfe59bd748a2a275f24b3232f638cb3bd28679e43010001	\\x071ed7c7e8bcf101c89e3d596feda33dc2d428c5889800fa6fed68bcbd4e6ac2827b5efbfa5b99cb7f646328f03da0fbddb1b7a9ac6ace5c49d5253336a2c507	1670177440000000	1670782240000000	1733854240000000	1828462240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
276	\\x8e0a47224692567a475926e3b97f7c0e837c2de0c6763cadd59e868eb1ee9f4ec7eb070f7d930cdea3f2a5c6c5f057bef8f46615adcf75c24d3cf818f4e62f25	1	0	\\x000000010000000000800003a2732604cc0eda500a7df558b7d6a8bdeb16d13b7ee06509982323828398ac0149584cd31618a1062223dd63acbd9b355fa2972ed5b1c9ee3c7b1dbbf82d9ae28058880e68ea36df104330e748f0f3f5d74f89a5602d653a1f5fd840f5f762b2250b06f642eb90ea7e51375a34c507b0b7280457539b716886a2ab6f720eb19f010001	\\x63d5e94a70bba251606d8075f53a2d128997cb37262a62e044741a471236ed6c3316894367b872a15bb0bcf99f266863f179fd1358286c19a018a74a8df0ad0f	1676826940000000	1677431740000000	1740503740000000	1835111740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\x91aeababa4d1e4fc4dc825dea0af347a8968a3cf25796840d094797138b1a838e053b09a0bf607a3fb6ea54f4b46bd3726e4e9670c5d21520f9813e1ebf7ec60	1	0	\\x000000010000000000800003bba0f9e528a3bef8e38fecb13203d1ee07e72bf0095c44a379c45841a57e4ce8e34109bccdb820830b70b1b071314d528b472d135d5d9db14edd53da34f23950695b354df08d903f9ce833f86c8084bd7c80b9c5484b2e2d083ba4165ca2821d9346de6969543e5932b0f5baea4b3dd5f5d18ea7f4563ce4ea72ca6d95358271010001	\\x2e430080331f05a2a079ec58f99dcfb508d3d0e8f92c3921fb257a5200471316d274ef1c712b623b8998f9bb979b26223e25bccc2c7820768268725e413e770f	1656273940000000	1656878740000000	1719950740000000	1814558740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
278	\\x917a220c98ed3701e91b541cfb41c94c05d89bdd707aa500aa8975b9ba7844e2684da76c68f6b3d4fa5d43f69969c16af1ba035ba18612226ddeba7e06908b7f	1	0	\\x000000010000000000800003b011f43c48438cbb6163ff3f41280a5541fe1df66fa4472c9bffab1edd761e85906117f572685cec6f8de2da13321a4d145de4490ba728128f3e2cad65dde02eca1aeb37bc6fcff673ec0968702e725a8c929834c2309f69603acc802b3435386dbb1c1aa472b82c1eec9c19feafae048dead133a59576a600e723dee9667e5d010001	\\x4edd89f2699136494a4fe0cb48fa2b085a89b14985738cda7b5662e3c9b4e145867da4f4f359d587c6550dd53598ecba3803b39d3ac60b4f53e146d392c8db0b	1659296440000000	1659901240000000	1722973240000000	1817581240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\x929afdbca42335de0159fe1f24a160f44a1431a0cf2235b1b4f62c1c575887d3966fc65aa46ef23f6ff7a2c21400f42e7c7822341d1a5f434d9a8437c0d6256a	1	0	\\x000000010000000000800003bdce1d2439bd3491c5be47da4b003729c26e629bea4ed5350703f93e2b07a495e2a4dadf227090dc88e52636b61ff29101268274be49e0bdb5f8e434b2c94611a91afbd1b56156f6c15e5b9d76514c89595d4968f2332fdfa187bb0e88e7c36e0979ede4d28c343ed7680772cd54d973b18d7a0e14090e5566fc6ef63c00a641010001	\\xd73f452dd2860567343ec9c7bf253b79680329b7ae5fd6bcc1111bbf361ba8d62144dfcd2ee79e4ac7f527c310d588f9619f564690d023a86a8114b33f8b910b	1662318940000000	1662923740000000	1725995740000000	1820603740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
280	\\x92b2902a60387d254d4335fdc28b7b18a33360208ba5e1d2f85468f153d9be174e849170e5009850f3f41e525297324b09104fabf7bcf785b61643b579899f58	1	0	\\x000000010000000000800003dbaa909788d8e4995ad4822c0ad186e715049112aca8ff48c5d0a215586d98ce71366f9fbc0627356d2a9bd816b8023e3ef241a51ce30eadc3b60b03c7d19f0f5d1870757d8c76c7317faf0d4c0444061962843fbdce556834e8173ae959fedd7ad2f92f371c90187040d22485d181563e2cb77fb5a00d923240d4d665cd3f9b010001	\\xfdd5800e574ba59f561f87bff0344aaafa118364b0c6ecf87f568fb5db9fe5dd45975ba9ae4526b4a2cc412a6f96024dcba6d85c52f43547162a229f9e052e03	1663527940000000	1664132740000000	1727204740000000	1821812740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
281	\\x95dac0fd12fc0c42736854581cd43262e5cf6130ebdf8848bb0fb93af701a03a4ac4bbf7baac6c9fb5d21e6f9d268ffa59713fbc1914d0f54518b1334bd2e8f7	1	0	\\x000000010000000000800003eaeca7e58f2ba6c4e4397e4aaa2e90dee9847342a81a0f0aa7f1ac2cfcf1890ad53d3075eda0990873762ae92f8d3288858d45e1cc65d398459ecc9e539d8e507835026aa1a9c8b4420cd9bc1febd15f21151419a72ccec36aa9fc1449b4cd485200f143649e6b91262eba50b453b9b0633079c3e82d60f97671ab91fe22ef1b010001	\\x986cab36eb5e3c05379fd95600c0f656db5997f7d70c33d86823852d26d7fe969b899b4f02d1f9f387c8d667e1cbab3030ec43d138fdbbb6afab4d9f903c6a01	1656273940000000	1656878740000000	1719950740000000	1814558740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x969e2c9a4d055340cd0249d256f21c787c1de974cfd8430619f9bf1fa65603422d41a064db4c1683951aad2695d66af550c1757030831666b720287031fd8f22	1	0	\\x0000000100000000008000039712a9541874e922f1ee36d7c40fd642fc08f62e581a183253c81c6ce0ea828294343ca2b5d69df107f0fcd8bdee5e4f184a5bd89d58d8af3f231f8bd5bd11aff898355bd6015d3e0998bcad4829eb5409c12bac11ed2d75c8e1edf255fc9cbb458beee142ff96d2197b8b82be95c866d44f898a91566fa3d00617efe47b7fc7010001	\\x84d59898592e1b727a5b2e1281b71768aee869e22c525be5aaece1b23f578e7ec8799d76affbe132af39ba2cb00bb560205bd8a48f3e45a07da6d3afc008ee01	1685894440000000	1686499240000000	1749571240000000	1844179240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\xa7ca83b43d25746557d5817fcf5e030977b1031ee19d4443ca8fc878233b12c84f2ea933ebd9868f003d36fc97231235095586985718c2ac16b9b5dc3563667a	1	0	\\x000000010000000000800003e967af5273e1e5cc688198da747805f537a2910d729a1fd49898f3991a9a13c53dba79440e63192c8d3be013c0f7527e77edf63f7a138f6b1db036500d2cccad79250ddd1b455d3fdaa1e367370be33ec1be93c4c9d6b8c5721605408ad82bd559e4b5641acc3a8f19d79c0a1eb9f0a208902731d5c02da5906366f855e4937f010001	\\xf0edfccd08f718963e570078ce59c3aa56aaf0ff2c1b10b4d2b704383e8465002062b716b216142b1b984bbccd2cd048ef9f3e8967d5061ffda84b0128ef6e0b	1682267440000000	1682872240000000	1745944240000000	1840552240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
284	\\xa7ee76f1217b8726c3771fde897c077b0c03df7d9415345324227d37825db52e8600438fdfc94610ddb315edc199e0839c5e2417b290b4f176ac5ec89f11a80e	1	0	\\x000000010000000000800003b8f74023647c759b305d21f8bee4750160f4ddce9b14662402c9dd6fdef8b78dcf7711c8997287785943fec1834da8759201d1fcc0abb4ce45dbb09761b0e7a8ef622ec6d3ce39a7be3a35f0758a15b070f2f595001226268c69ef1f18464df1488b27af1eaf9a154ab4fafb9a202f0b1228d068593385a6a97a21af8fd358fb010001	\\x9b06dcda56a72ee59f77d7ee4f8df213c7d105adf9733378493c6673abc695299550c3ae874a61175cd9197f3e62c1360a9e863853b845a1bb5e1434a3fb0306	1673199940000000	1673804740000000	1736876740000000	1831484740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xab6a280a4a6eeab7c756609518ae8ce0549a637a3ebffbfd91d2c1aecd98faaa19afa2306cdefcdd4ad273a7b29f51fd4283b42290f387f282401a7963f9babd	1	0	\\x000000010000000000800003b9ec08a1db0cdff05d33e66c7c04839ccb4ed6b98c095e0ab0f2d71c79b7f1e024dee1d99feeaa3d9c6338b5a4e538875985f3685cafe0c47dd6713d5eac0522b210e4190e1cf790ddfc3bc47e652b5b598818c5abd3e057a10fa830bafa46504eb887867d87534193a6a7b3b05b9379173391b4196d1d5abcc3cee5b3886ceb010001	\\xd1e224273b4a6e72c0bf77735b09e8df32303d8b6fbaaee19afbc087bad5c1dfdee1e73671875dbe5b69cb9008806c3e1f577184587371e043aac76666bd2b08	1685289940000000	1685894740000000	1748966740000000	1843574740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\xaca664e75c31b85ab24f519186ce6b82a92b155d5b498c0c60e851c40642eb95f7311d33a6e9c87bedcdfaba875e74a263e673457409cc08657acd3c35ef60d2	1	0	\\x000000010000000000800003c0a5508a6430063b89033bb4cb2270f373df270d361bcfa75bedfc35db0a4158a2b8186117602cb123382ee17e4192c95f2f5e32c359b531adfa9e0e1b9623b82bafbb0543b10769380483c75ee04ae7deaf96ef6bd28a7b6f3254f57239f089a38ec7087eed9d6d54f61f69085cd82f894b966d76811bab4954537e6a26adcf010001	\\x8597cf72ccce6b79a4893ca7bc484ed632f917998f6f84a361521c08712fe1709d33e8436a50db29441a776d6fdab466c699d6e78b307825a7e1690e8efd120d	1680453940000000	1681058740000000	1744130740000000	1838738740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
287	\\xacfa6e4754da94d742aa0e347ba24a59b72eaa3a278cf580d0074e13a7abe176dd3d335b4d10a8b800b7e46c99620b4bc80ce5304cbd56d8171e9e7b83970cfb	1	0	\\x000000010000000000800003b3e4f57b5465c005bcd7088fb5b0be477c3d2670e0070a2a3dc910dd4f1d07dc120bad37c0bccbddccd6b2e3a647434047ef7eff7fb3adfaa888bd6383f155a81d1564e100d9b9c06addef5d9f4cbff3da8f456a3f80fa023fa4d5b5838aae63605f2a61798489324c2d585656c3734c79e7b0ae38d5c8a3f7cf285bf6b543c7010001	\\xe07bbf895aa5d7ea8bda46d763b18b0e8cdcfc69b0409b0a921c7f72e59da864387cdcc37de928dc10005d4c51266da16847f33a7459f7e9ac7ec2379696160c	1668968440000000	1669573240000000	1732645240000000	1827253240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
288	\\xaeaee09e5fcec1d34af9a406d18fb01d13044feb408e7eeac1e58865656d405a3a7372c9b4cfbb1793b176ebcf91caa1c423bd0c9a40f87299f8ea6f5db78df0	1	0	\\x000000010000000000800003a57cb86969e5b7017a10069e963b37c99cbcd543b5969b41a2d14188d373f79b5338421e7d33048fe07c1b80339f32be13f2994c8eb874b5596b3c779aa321283a0adf782b05053815c1986625dfd888c7b9a059dfcdad95960996262540a7eafd35834270c74e3930952b5852027c4f1f78535550976648cb5057851973fa7f010001	\\xe19398881f1d7a0ebc7a8ac68bb426321d668a2d141dbd9974a1b0781cf4093216672fb3a8ac0535cbd087f600d650837855f903f65517ca029603e45ae7b202	1676826940000000	1677431740000000	1740503740000000	1835111740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\xb1a64876630e75da53d36bfaa6980dd42f6452d44b9b42b494a213ce249890f78a8433ad117c796a925243556461bbc9a9a773cf81561a2c4d9cfebbe55172ab	1	0	\\x000000010000000000800003f4ec3fdc839d3aa73b7232f9d75154909e1a875ef2dff754beaa5f8c63c131e082893ec31ef737742573e68b7b645a3f817122bc829943fdf0e455dc8895507e68b22472d36e0f970be9d03eaaa163a75e2d0cdbd6396e22b139bcc38edc91e0b27f053d72f08d04a8e6c1890c8f35b7e0e481b7391a466e782ee93b98dd262f010001	\\x949d89d042697803540c62536e6a6a6d14da57fc8be3b9759ec5eedd41de3e373b9301d17fb0ee9f15adec935821f418635c1fd661f1db44c100c706e158ae07	1656273940000000	1656878740000000	1719950740000000	1814558740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xb28aca2d5fbcb6d6d06bbab14124c5100363f6651fb429ace034de3b30e086f51c841f42e35f6b70ccc0836337432aea3fdc85248ab726eb2d8f55195ec30ab4	1	0	\\x000000010000000000800003d6a36e591ed3acb250fd0da90279a1ceeb415f540fab223ae7287e1845932c9ac3f1160a07e36f422ccb7759ba9bc4f719a6006928c1ff33534e33a10731eac8d10cbb61ec71dd2543d7e8b58a17012f7fbfdf949b570f2d9f301cf1e6f9d6ab64977162e65df872dffdecf2c1e33ce2efd504c023a4cc00ee65b27c42893a5b010001	\\x77b4d7a2b602df65592b199b6e93f9a73f6b4625f2e0735b6834eb0ebe94774aa49a93d47b49c057bd269b466ae7430c078fadcdd68cdb18d2beadea76592805	1676222440000000	1676827240000000	1739899240000000	1834507240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
291	\\xb6c654dc341314f2dd9eb615e2cc6f7a85d8169b0b0b532896db28315773f0991c706b6848f0c17dbbbad37153f372aa01c4033224ff1588a55ccc859eb08384	1	0	\\x000000010000000000800003c2181c479364472a39586b0ac16a2630f1973f6808b3518cc1b3dc8553dadd7099049b2eb6a84caf69d0c248c96d71aca316169c9bb5cd26c388cf3a17920c591f4dcae6196f2ca99e90e4d4885c7f5faa1cd3be7bb99c683d1472baebe7de3f1c900f2796ecc456bce69c5e8db931c74cbbffa7ceb7aeb4526979870ae7156d010001	\\x2fd4e4a85861d0e65c436aa9af0380efd0e36753b12872d07e87d27d366d05f782f7546b8250a565fdef730048dc6a601fe3fb6c57a1110cf2b24c6aed2a1701	1657482940000000	1658087740000000	1721159740000000	1815767740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
292	\\xb772394b0e2b6b75b74a9d57e7be3f2001b88c5ca838210bae21e0eb3b44ad0f9cc226d5a690fd32203002b9c0df3698017bfe0f787bc823e3f3fa3a9bf6fd16	1	0	\\x000000010000000000800003ecdd78eb6dad8c2b73a70df386c485fc2d27508c916fe94b4e74f8a3f761bf2006f94bf9e679111ab29912eb2107d90f34c0f64f1b72fd19cea816715774d94e9cc84c13e94c1df3ba2094a111f3e408e44361bc91ed9270efcc207d6943e90f14c27ffc7eb9334a1ce2a996ea7be00251e0e8c13552bb12e59f362d18f3af31010001	\\x31a3784432a0ae618146637d75f4ded2c5d063cbe6ff79c516252346ad27333a9708eb2b194c0208015c82cc5fbd19261d3cf2a047046bd3df85b4d1c0f2210b	1665341440000000	1665946240000000	1729018240000000	1823626240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xbce6ee8b451b3cd4784abfbd65c910a1e3938363fbdb2bb290439eb18fb26b5adb50999c9784ccac7c77c1b353fe536426c16c9a95f5f8ff6bb81c7619e98282	1	0	\\x000000010000000000800003b39dc2f9d43a44fc2683a56cab362963a84ce76d199d89b0f92465be5fe3ae341bb3dfb0a7dc6741afcf4e20850cb4d1686ed2cee6e453df99832039e385c347aaab9afd5c46c5198dc281fb15175bc0388df1e8fb4bb0cea9f2d1dc8fac434c25b9b8393e37fb1a302ae6059e64389c6b65f7847295ad91735e4c104d5c80cb010001	\\xa1b06deec05e05906a61ce95c4c07c594851c7f42b63fa9b215096c29d939be036eaa4f7d649f97c1a747c0a82114e348b0774531194b0a7d6807660ccfd3b0b	1674408940000000	1675013740000000	1738085740000000	1832693740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xc1d2173103a1e4ee3fa6c7f647c1cd276f86abf99fef7cd36f1b387c4070c97daa43cb409061a8d508f0f3af7c3d4e9dbeab85d73d12e8ea51b09e7dd4061181	1	0	\\x000000010000000000800003efc43e74a9952c993ae8572ee929990534f11118b66e8c09958e89ce806b2fb185fc554beda4b0d5584fd30ea32ee726f7a58ba6149ce7755f54a241fe00d669e768b745aa5472cf94102972f29f2149796380cb13918e3a30579e270b0055c226ed6a146b4645b63ac11f9f342379232a453ea69b459f4330649132998c4217010001	\\x4f4478b666064b39f963554b7fca05e765c8a7b15da55cfd0c6806fc29cd7601c5a20fe02c0858ba000129538057b8c23f98b8c596e9298672af7af19b053a05	1659296440000000	1659901240000000	1722973240000000	1817581240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xc1c2a35fc7d2a7f6c3965f569f9a577470a5d08bc0b2598c940043b128fb08cecd58893d37786a180eba83f7e1899cd395eb23f99e903ecf63a93fbae238eda9	1	0	\\x000000010000000000800003cd59879cc1f77d46464b8a2fd4e96989eac4a87910fd0c5dba9978b8c37ba9edd1538983ac9c642b15a2962b0b73c4501ec033a3cf3dbfc1b051a6ba544df5ab7ab7a7392b3ac0fdb762cabd2ad60bc933a5eead725d5866d8f81fbe88caf366597c927f1e02eb5bd055b99f21ce2ae229cf38b01fcabcb556544b6cefb96bf1010001	\\x57ed0d51befec5d28ee9c200a7fabbe3631a141c4898383a1c5ad0b84d7f437a9d6243ba1424a93b34991beff71e78d20d080e8a8c7d93ca8c870be244f74d0e	1665945940000000	1666550740000000	1729622740000000	1824230740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
296	\\xc312e487a8bf88b27437737f142e5076d43f508d2edb453205f58906cd66a0968f9d645347cd053652ad5591142dbdf8d35d132afbbba921a6da4be30fef2bbc	1	0	\\x000000010000000000800003caab4da2f0fc65d2bdaed47b50204ef7bb62427976e27e0f69575a80a52f26012e94ff5f89ed57ea2bf600b714c66249a068bbc1b00e296f22724d456daf06a71b146bbcf388317f41be180a5d0875abb822c5e251e5bc978be55348cfddd9c816d3fcdf314b72a280009f79132eeec0288f8b3dd7a572422adaa881d261e1b5010001	\\xb866654236f22330a350bb2527935eba92b18d491727b1e8ade10365e2a75d58490b5a13363538dd3c76e0be191e0da82b0e4d7e538f3bf7c834cc5ad266af09	1671386440000000	1671991240000000	1735063240000000	1829671240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xc366cd29e06fe4254cfbc6500aaefe7ff600c0e4a23019dddec0368385eece15b4ad90a58f285b4eacb90edb4eb5c0d12c4df480ad3a546682ea0a5607c0010c	1	0	\\x000000010000000000800003e3cf28738aa8ead9614ad886dcc348f1c088c35c77de027d4da3cf2ce4a470b9ab40f565900337a391ba049159f1720536aa7ddc52d35bc7c39ea0822081a8bbb64b3a47ac0f59ffbac5e2999647e77d27bb6bc9a9698cc61867f01fde2dea50dc4a273ecd11b7e6c26c36526ba99206508e4c5bf3b78d54395812d22fa39019010001	\\xb5e21f1120317266416e5a194803fa06157bfefae76845176c8388972d0034d31d274e1d5b77a53a08a3db71f9c8b2ef3c6e33c465554123c303c1503caf0a04	1680453940000000	1681058740000000	1744130740000000	1838738740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
298	\\xcde64d96506b8e92784db3657d3f3737ad94113bdf849cad349d133d218b488d072251b5d9661dae35f5fd353b34978c34eaaaecd83a3594e7ec89c9049c9725	1	0	\\x00000001000000000080000395853c278e343186fca5176d20ba4d845bd1466027d38d4a94bb64356ac9798d5e7b2783163a3c3eec4ed238083184c7838418fbe97f5f21a6a7d2ddd4ef59831260c069b9c7ef0fe917350a55b1e2790088d5541d021af23cb606a7098c229cc9aa864d23fb6fa520fbffe4e3adbfe2df168cd25bf5c58cf6f1c368d6094c59010001	\\x9f4ebcf9628b55f6cc7aac557034257de6cb5d5c95de44fb4c5988fad8495441a44d3d5b7ac330becf27c9a02bb32024bdc70a35ac201a52f69287b92a880605	1662318940000000	1662923740000000	1725995740000000	1820603740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xd25ed6f5ffb46f34c472ce568aaf88b0b86a682b73b2a2f0e3b7c87640cfa59c1869b570aa4704e5ace559901ac7eef08b63691ac0d7175507cd29e2275d802e	1	0	\\x0000000100000000008000039d155c31ddd62faa029a60886e1092ee90ccdbda33e00da6b702fad795321d38e7382ed2cb7db35cd8fcb4e7c8db9bcb819858b862a671b448f4c7f88397f35ca590a8af1bb5a8fffbefaaba60bbda893c68a5386c6666cdf96c445ecadea50cd6ae7c9808d86f22a8c4330c77262a421ffc314d11bc499d7cc57dbef9dae847010001	\\x73083ecdc23c55f5c727fc22d4bc07dcde5c58cdfd3cf675ac86ade18f88886017508051ad7c3dbab7d5d3dae20614c2506ac18ed501d3934839b44ec760f001	1676222440000000	1676827240000000	1739899240000000	1834507240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
300	\\xd49280f4fda71c0158c0cb5390c9bca81e6eb41f4ee67e47d53e45219db718ab72b4c02330d693a4773d2639d5be8ee885a527a0395557f6f01a72f50c1b942b	1	0	\\x000000010000000000800003f4bd39aa4f06a1e8b77a839142b3672e057a3f5574766907df23f6b74920a6a962c8a07d23f284f97803d0b4d325b12d854aa42b4f7ee2e56e80e87cd340ded83883f209b59aabde8de9d4ccf19f0bda4837f2ea24b64c37e389f94090c124df42e699a6ee292a846d85b391ab9e7fd268c9897afded6b2647d219f0b2ef00af010001	\\x2d8c2aab304968aa9c8facfacb660214f066a411876f7ee7378622a084192c8d853ed536d14a625ff38a9025050f7868f487cd59fcc39793d3c58f480c1e9905	1660505440000000	1661110240000000	1724182240000000	1818790240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
301	\\xdc7ad14bb2fd57bd3cd44966d8774ea5be3d4704882fed91e1ede56cfd495a5cdac1d19d2de586fe9404fd92e34d8c10a86b0c27606d05ddfa1ca0b8abc568b5	1	0	\\x000000010000000000800003aa2bfef3b490d7f6799d6aefd2a0843ea164dadd08585b619d05bc8ced564d3b958c0c68ecc92560765fec9e58b7ba03203e22ddbd56fa2d3f6992a6acad3163e5dc826acf40606bfd43cce2e721f2b8c14dc4f6719192509e9f920a5f62333141891729393bd49d5b5169db18eced3b11e3428a5af348d8f3f714ae93dad0d5010001	\\xe83633645dcc131b86ca15a564420f8d2050bd2cff637ffc3c12164f7229c2a18c34b5df18d345f08494c1a776bc78465f146388fb821024a264a544785cd200	1662318940000000	1662923740000000	1725995740000000	1820603740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xdd02bef0c669560f4ae5b9389b652e668e7730c158c7fa691104c514c0c82d6d474ba58421600b91516001a6bf26ba49291926be06c0ec742f8196b01f2bd512	1	0	\\x000000010000000000800003f94fc2fa59fe3b63f9d33970238f23608ad0d872a50846493185ddcd338416b7d58efa4eab4f1e65ed8f3eb03804efd2194551d004d6c0c63f4201a64ac7ae45955114190a50199eacf08865051de5e0ffeb964200139a80ce32bd5f6e10caee692d83a1d6c6db9e25ed13cd2f57b6e28d3698123949ac70778a0b97f7b026f3010001	\\x4ce18943f1ed8169974285245f9601d4b3be2a5fec4f6891decdc493b54b4d1a161c9b9a39423f3b2f9f3989fcbf7a7afbfee7eef2cf6cd73f10760e6ec9ae0d	1671990940000000	1672595740000000	1735667740000000	1830275740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xde8ad8631ecf7c6229682768be1677b0076169f1d201c0f93f6546c8437b60627d73bdd6d1df7c416e49ee6d9e5d386ed67d41b3f8ca915b8d9e537482770d10	1	0	\\x000000010000000000800003d7b9d015b359aef80dd1bea34e298c98eb61483f96b4f1fd14ca47b70a73ab8f431384d1c4d7f2074c2147b25645bdf132506d84c548898066a19ae36957304ca66999d1bddb7939b4036dcc9c220562c749f1df341875852523e346ba061b3a45c0ae7949539359cec74a94c1834720fc65e6f403138cf310da8c1626ded59d010001	\\xb47e9403b29f8eee0c13dfe4dbc00a11186dc42741cbc2004175b6e26b11111031e43bf915d4a443f2b98b978fc1f19f3920393444fce17c6278357db7fad900	1670781940000000	1671386740000000	1734458740000000	1829066740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xe3eafe7dc704942ec4642e7453bd7ca33503185270a8da1bec92963b8436bc4485e28daa484ef80c43a6eee2d359e5ac55fbb78381ccf639147ef024bfb871df	1	0	\\x000000010000000000800003d2dbc977604a6867573a17422528105c12054f77204e912863104d2355652e5b280fe2684b696050a6549361f96ab025b71c501b1f77bba2995d2d097979bba401994ccc577cc460cab13248abda7e3890f31b2ee12f569c711cc98034c13fd30ca8d5de7024c90dbec94bd284b09bc894373cfaf6412cc854d25643db4375cb010001	\\x060c73c7d07e3455f07c9c1fcd84d31d0cac4fcd4e8f41a3602f61ba78942ea8e1a440877514ec7b415d031127affaf5b948680f80133c326bd4566ce9f02909	1675013440000000	1675618240000000	1738690240000000	1833298240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xe42a292017d4c400bbe04622603c701fdf39b2ca00eccc8c40b9368fdf6dbd29fa5f5019c072ed72d005dade4904727afbcd45aa491e98f2acead2ae6b79d9e4	1	0	\\x000000010000000000800003a1f1324b497d3eda4df8764b20178ae00ec1a4fcb37b42f610515ad748408dba0ed5ec896da483f88494c30c78c53b4f9613754661f1cd0525dde70a0fcc5f98ccd546ae96a3c7dff488f0379ec0160c520db96d3f73222fbe41eecaf683e0f09f368e134b78ca3232b1a08a92f1bd5aca5ed0da96afa55adcb5800a4fd26d65010001	\\xb0348ce2b4479fe1719e9e6badcd1d83ff96779c700560c8959a38d8346f1878e1de4ec669b09841eab2c6638820a6962f84632656b7a749ec9ff971ae34ba01	1657482940000000	1658087740000000	1721159740000000	1815767740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
306	\\xe48e36bd07759b4582c34d46a4c9eb5b0c68f07f3810eb1e18dc5f1de5af49028ddc981a92b3389aa0a3bf8e346bccb78b2b0c80340fcd334218b8f36f47e750	1	0	\\x000000010000000000800003ce9cfb94f9c9145d69e1f5321005a4a660a0c307793ec5d395add2cc1e8b04b56a6e16b01fec96f00904545437efbe621651faec59495fb9ef1462d61acf3ee5fbbc780bf569af414c58533d46f755e6fc338436124a6900b2430b27e6a99a8d4063aeccfae4a8375a2229cc96af49c4363596c05cb0653885117c5548c8643b010001	\\x5744053ca873c4033f30d9da63f51ae01603825c455439d38cab7b3e997cb626134872e6d1947dce9baca57fef226b2eacd46386f9d82f484c6bfedd87897b0d	1679244940000000	1679849740000000	1742921740000000	1837529740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xe496c91aede09fa69620e38216e57e50d025f80535902ec135a3d6d864cd99d7e3af78e7c6cf346372693681b109c13ca5840d6e870bb5e96c6081798fb15d7c	1	0	\\x000000010000000000800003c3d9b731654e5d6b583ea6f6ef487b1176a03a4e447c90ae1d04bef8073dc63ba48b54f898538a8832b646842208d3673799da9537e16f6dfa77b9f771842f9ec64754954d6d88a307ca329f4fb1917458666179ccaa00c5223c071409c415ade1c02c123df098de9e36f1ea03f6bc9365f9fc9b56871528ca49454b0a558577010001	\\xabb7cafcc8743a8b974436928bddcb04e0f73d1845538c55dc135e1a3746cad928a69a201f6ab05f1f20a7e4d7cbc2b12939cee0017fdbc8ee1865b3a0d10900	1658087440000000	1658692240000000	1721764240000000	1816372240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xe72a99bb522a5f13fbf590db41e418fdf04dc286734e34718413f02c5a681ef382752d431d2ef1a71626f6cec2618e102727ed0ca26f8aa77d119f06bc03f298	1	0	\\x000000010000000000800003d97fde446d00e11219189d0689dad703fe8b6059bfeca7eb7086157b3ef6f0340cf648fa21f5db10a82b4402c17132c1ffb5e8b99dae5e85905bbc5083132ac64809ea085ff4af9e7d539b7679b87c27b5f8f6eb1178875be487750188101788aaa5a631d462287b72edd682f8b6c974640386ad15d6867363212aff269a3f5b010001	\\x6b4e03b2a46344be9dc2a11fdeaf5278966db2fff3eed88160ec0e28dcfff5cb3892e5b5e58b0f5280d8c5306abf00f6327fb269f49e6fd55a143a9f8f7f9907	1683476440000000	1684081240000000	1747153240000000	1841761240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xe9fa65730d7749effacc7e624e2de152d5c5da02f87513b050ee66abdc689c5f4ed7df4174a7abb19fb1d1e181e88af3cc10b4436766795add19388447dff8b4	1	0	\\x000000010000000000800003d88d60b3f42627d8665044e23b61f32e4cb0c4884665550714b62e9f10c91570cfd943d2e9e17b75884855f46d5624f94bbed113d4e58b3c72558bf7cfd87c1bd1c4392368ed968163085da826f85c6af491fe797405da5ec2fcc1bd17ce20be0a237294bed0301e79d16508b0222d7afb939052f2715a56f8e26f379b38aadb010001	\\x6d65d6e75d3117732e7486f4f7c79ce44a104c5afe28f5f1add7ba3c12be841e56e32ec1c2eb90ba39522a55ef8c4062cfa23feb3573ad0633c97f9cd8bcdd04	1665341440000000	1665946240000000	1729018240000000	1823626240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
310	\\xe9dab6279a0f038fd21c8f0b7aff08f2a165054b2e803a8ab0f06997ec25a8e2f2dd6a307b368fd1af150ee780fdb864c2f06e40a2a92645e06a57ef71a8f813	1	0	\\x000000010000000000800003a5022a5d989df47aae1de2ec5fbbde1f2747bcac3917029d3cd7d92879eeafb9ba2ce51d6da78e26305f9b816f66ed15348dda9fd95d220a57f96374eb434edb5c54251483d62ee172183292e6a3971cf25f38df4ca432384c834bedcf1cf63b73ffcfadb03e7f878c28b1417df9f1478e09230c47200a1bd0817f96645c8103010001	\\x9f5aec057846b9f43f34831bc9a210aa581fb498bf3861d1ae3c21efbc23ce289219cd64f5a7dec0f243b3da8dcb1f6a9001c5058faa69886c71ff2af99c8001	1676222440000000	1676827240000000	1739899240000000	1834507240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xee521e07bfb0dcb2d0533671c323996bf9a51439c327f22d1640031fb44cf173fcf894208042dc42792ee6dc7c955cf5980e3f82417d3e022e50ccfab124d124	1	0	\\x000000010000000000800003d03d54470d2807c379d237768d2a2ff5fdbc15323063920c71302a0c6a51502c32803d9651909e5a908251dd199aa2f4bdbb659fb748d048643af9b9eccf13804bbd4f50e38f9f8fc12e027f7efb64bc6f8e9f24419c5306c258911c2699649c64483be00270c74ba3f44be16d98d10164a01e92bc5322c1b34dfadd33a5f161010001	\\x1dd597087d84aec90a9eb8489ce40ed69a42651f936e4fb376dcb2f0e66899ae080c5cd1b5b051dc959ddb8f0f28cc78a1ac20b77f41c7c2eb59c081af3cc60f	1685894440000000	1686499240000000	1749571240000000	1844179240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
312	\\xf12e703f495c2df0c96fac32b3c828c1ebb067ffe67095c5661287337e8e11943be0afec23652211b2d547fe536f5abe17153057164509f6e165878179d0d341	1	0	\\x000000010000000000800003d034a9d58854dd9fb37811a4b8710becbafdea2ce3654089ef217eedeba8ada924c404759e20e8be17d33b6a3d90ed2b82b173f48ea2688c306e13d8bfa902fc828616d3e1241556fb2444748368cf0ada98ddb73a4a22f62aee3313963bd61f033edf766555e5ff26ca73024b7f5b6cadfffc336bb7df797278e7f338f8261d010001	\\x7c5038775f9018da47acdca12a0209d5f50347aa9acdb8fde09e3a56edb07664678fef1f43db444e57972ccacaa4827dda8fc61c8baaae607fe05960a11e5201	1677431440000000	1678036240000000	1741108240000000	1835716240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xf106c40b73f25430654d99da1150305947024b17352db644c8e12ff14c060552aa2c0b42a068d236c9f00ef1001d81a7a26d2ae08cd21e91387103c8b7fdac91	1	0	\\x000000010000000000800003c8f20c57d07b41a02950bca8faae8142e5e55afd10a3537cf4f8e03ec290de5c3cec605c7ceb071ba5c2ec3bec24a7a24b7349484fa8b3e45b0520bb4527cf30799860e77dd99577389960ba58e63d0cffc8786c318f73dbf4d12309febd04195090964beb3c98befb1fa4bd37bda383e0b2025cb731cc5e2457a89bf018ab11010001	\\xa68c27a62291116ebf58d7742559dc5f3fade352b49db64435c45d6729f8365750e80dc03f2f8e895e76648263ae46b8e8253f8730f55fb46792a70c00944706	1673804440000000	1674409240000000	1737481240000000	1832089240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
314	\\xf1924deb4a70491fe9b84c13b362048a14d2dc360c2cf28c26f9b77716b2f3f372c647c2925dff9fbc1e6ec011a20e8981ec0a4dc2fba96905ea03a651d989f8	1	0	\\x000000010000000000800003e6def65711dde50313f98a7c2e6ccd4c0c8b07226650c84cc384f91d0756840397503880398233e87fb7b3853fb524d8d036d0f241b3e6a05b26ca260745daa1248d89051e88c5c18fc98ab6ac0c3909571d32205f7cf9427816b5f5a0705a596cf6d6770a9fde19a1d408de2dd7654aad9d166e63b7538ebb670abe4d6048bf010001	\\x19946852d00d282bd7f59fde43a5b9ff22899a4e8161a1d6bb9b6a7250c4485107d1289710dcab63584cf1125ae30dd089a64ee1725ead01cd580fce3e19420b	1672595440000000	1673200240000000	1736272240000000	1830880240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xf4eef8a68ac305fe76a0746416bd277e7195661f7ecc11f8b43b73ab23aea83ec672919488cdd11edc2d3417ce1473d11b4115d076c56768e272cc5303f21bf2	1	0	\\x000000010000000000800003cebe64f575cbcca88c049a554e87275927655e8b5c7cb5a49b442539c5787989e03f5e4ff5b73aca6d2c2828fb20b2f1ec8f8104d27d49211e135b0175cfedd1bba803c19ff6a714908efea62c782884099ece8d877a8fa96677aa76c3e6419de98f9151642c6b9a1e8f2349f72bf522635a41f249bdb1ca653c9074d7720701010001	\\x178a6c0b37fdbc84d1eb605f44c62220e081d667b0f0efe40cd022af87d9e517885879bc396a7d426634d0984cbb981685aebd7ddcff91323b3f142351485607	1673199940000000	1673804740000000	1736876740000000	1831484740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
316	\\xf70eabc97a67e11bde4b14c8c4fdf5fc2e2961060fe870e00ccbae7825678c92807a2a6b06a34cba8b0940611956044020898a3345ce746eca86ea6cb7b55b87	1	0	\\x000000010000000000800003a1cfab6d2d47a51274fbaa59b97a43e54ad22aa4e132fe4d03b356c7b31f66058660a7fdcc57787a1fcd9a47677227352d883dae17971678aa9635b452fc88e8d45bf7128c183630138c85392b5598cd5044052e3558cecf821561c13361326f0212bc75d3aee29437a4b4aff9958fab0b4d1bc0257307cb01915d31f8be0955010001	\\xa74c0b6c1fd7031c55980b43e31daa0c57ff245ee27df7fffa5dd7f3b4f2811e0e3e43ed4977f4a166c46f15cb11ac40cdcf7ee6ad5cccddcf80de0ae64df70c	1678035940000000	1678640740000000	1741712740000000	1836320740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
317	\\xfb0a2a82269ab1284c11d64f43e28523bf8776e107c2772068682c73b51642d5ed658b597ee99d3cabf999d7ec700a079cfbffd3b50b4222f626cc86fb638071	1	0	\\x000000010000000000800003b50b210fcf3c8d42c6cdaeb9ee39b71038024522aa8c1aebe453ef9c19743aab2c2a8bc065d138a81e9a39a764c14b85b3380e16e7f3fc7cabf0b843a2160878afe20ebd37db3391a48df8abfa8171cbde4f41d9e7b7d5e35acd926376144b24095251ca0ebbf337cab96c29485e8fa9d00dad4fc543f54c71485812722cb6db010001	\\xde10f315e4120236a855c380b22eef210533a6675f14a58b6c84665d31c156c21c313a56aa32895c17ff50abe26217d8c85b5816841fcf26c0025bbca4d9ab0b	1667154940000000	1667759740000000	1730831740000000	1825439740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\xff6e3dbf05ea910a49de55b5a713aafb7dcc36e3004faa41ab0d55214da360b062187bd488480b96d19409f30e6553c0af9f748ec32ca53d73748d6da6e8b5ca	1	0	\\x000000010000000000800003b1b40075811bba025d43e4d7d90e0411b6e9f99e421b4a04c418f78b71b9a5fe54bb4a42e9415c4b3b8b5ecce9ba25fd7654680b127732c71c7fff49a8301959cef0951f32603b9cae54f3a8f991914f3910d456555a4eae381737bb640f9acf4741e3f1854df00f3700d9df206f6bd64b9c0e2e57915d4d0e1e5e30664bf5f5010001	\\xfd4701b5dadb991ade26f39d0c06bf0bbe31b5bce898d13062147609f80035c06c86de542b9f9fd5b7922507f1ebf687afbfb9ea2f7294509749b332e1a1c20c	1661109940000000	1661714740000000	1724786740000000	1819394740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\xff3271ab9ca36b40951bf9ca688d6a0f0355fb0ddcc3aaeeaea6a91dceaad3ae7919e84c79d4351d7c96523f33ef7fafc30131a9195dcb6ecd3371240ac65976	1	0	\\x000000010000000000800003b4f04972e341dfaf3765e7a465ec3ff607d462ab7d2e38faed535baa928f71a784c06ec3e03d277d59091c591127e5795b5c575d43ad776a0e9f05c67a017299fae997d4003c50014ad57b3ea45ba9cc2e65ebf00064bd61837283c16f5f8829cabd0c2072604767ff2b885b5984225887d85a151ea14cf6e7ad2041c256319d010001	\\x1c8169c14c20d8ec0b15daa75888d1fd42b72145e32c901da8f635963f7521880193c4efb807b08e6b6459ef9aeddc912353ee8a7031dd9391848667311f9e0b	1682871940000000	1683476740000000	1746548740000000	1841156740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\x00cb0fc7a93314577a8823d5d1606a74df3ee795ae07607d5d907bb43bfd56604d06d62ee477d23929904157744fd63a8989ecee5f4a7733f1357b1ebe489681	1	0	\\x000000010000000000800003dd1923fc57609bbcf20aacdf66c076d2b9b4d87e8ca9e7c41075c51fe1a3144a3117d5e73f5825ad6428fc0294e4792d680a4802768dd74bb431a438654a5a62c591e8cacf264f2532a9e2f8ba55cb695c6de8edebf6d8761d45f99e32e2bfe668111a5d95fdb542099f78d25f887621a981237d474237fcd754d505cecc6f15010001	\\x36f5e16c25d442a5d6816cd0081d294d88721c9e63e55543e2ede3d089272cfeabd626926a9055e5886cffa03a8047515cff3e2a97767627f7886e3741b1b90f	1658087440000000	1658692240000000	1721764240000000	1816372240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x03371ead6fb461f3fca6e32dfcb46cb0beed21aeb61be00b0b918afe01d9f5d1c43135ece6f824de509ce15648d6ef91b96311c77cea650bd56488ed6dcfa0e9	1	0	\\x000000010000000000800003e05d05a6293b494513302c1dc7eb4849568b8d94a6de950366b1c02864b2d2e03b96a5dcea34ca6550b9985be08faa9647b179893aabc04ee7aac9fc871f25cc507fa3a0f932fc510152640ec64b5906fd3bc40e1107832be2590989932a6b07baefbce83f6b3297711f33f5e41007a011fc5ecd5f3623fcd2361075049ac415010001	\\xad1d25eb5558d3d886a88536678bfcbf1adb84454f103fa3484146d78e563b1514288347cbdc4eae2e78a5d67996acb685377981904d1a5436e2872a56809605	1667154940000000	1667759740000000	1730831740000000	1825439740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\x0567be438482fadb199f74b352ed15b5458b044ed01a489ff82998473be40f62fc69cac6e6752347dbb18e7b7a267928fcc90f2d2c7c8aeda60cb34979901b01	1	0	\\x000000010000000000800003bce6191fbab1cbf616ecc684deb832db3518f8f43f4e89d1d6540aa4c9c9dbac451c212132e7636f18c984b63790df0b1601f475fa4ed6661257923f75ae6217fb420ff9017fb324253781630113430b9f2a40e190f2abdc85b37516a4d07e98556823c20569652b8e99bf38931ba2c033d6eb87de41b916130ea3b171393573010001	\\xd3bd20611aefbd884bf4e25179ba3b0aff41f6e4e62f39fd13295f392691187ef02e49b55220570bfbce03a2b8205cdc28952734c6c4ea228ca56565b13f3e09	1658087440000000	1658692240000000	1721764240000000	1816372240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\x075fac4733b153b698c463d90988159163cb120a74795e7594248642143f5ed4676aacd5485bc73640d4ce7eb5987e973ec898a9812d016b510ac2e76e2974f6	1	0	\\x000000010000000000800003c3fa49deb2049b54d5b6ce5c2e0a173f5cee0f5fc296e8fea4496ba31da1e3ab98c06ae75f1a5e16b5b7c3b5cad506db0f350c15814f5337295fb8958e6d421f765865306771ff6d6f028c59779a14b53a778c1c34f80679bbf284973d37a0c0ff8facd51b291335ff4c6e61222f1a4eca2c6b5b039958a038a6c424b2da7525010001	\\xdc77aeeff358cc6d073b5dfbde59cc17235326e25590209f333c18adfd511278b1113a08d4f7c751811605663404ae33a5c1d7e36462e12015e28f62bd98be0c	1673804440000000	1674409240000000	1737481240000000	1832089240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
324	\\x0d331308558314dec66aadbf827fb8e31e7647d67f103b41c4d2c0d717602312a1282718cc9cb0f1c943c98a2ce21d6affa4ac7900d6f46bb7959354f0d8dda8	1	0	\\x000000010000000000800003b1442839934c9842681ab169496534ff79a4f136d499a4de92525ea746a75b2ba06e78407fecec4673b69b91d8cfbd016dff171dde3234280f92ca896ed35696da35ac0e0653eb6b03c9b95155fcb8baca2ea0d94acff70568e33bb9d1dde45da72746a80ce123b4c73a328a6ba439cb25ec3505e75aad7f421a83b986cd0159010001	\\xf1b81d60ec030a3187d4f994b0761cea3e7a76e98304f5f8c3fd80afdac2e4de3834ee11f1153af7aa21c2d06f7930d912f761e40a78ba2b2352f6e25979f40e	1678035940000000	1678640740000000	1741712740000000	1836320740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
325	\\x0d7fa282c1ad7bc58795a04d3d3fdb57d341e1bc5cc3e706621e7e9a52305727d1b703b2476c23a9654e013332d7c7237e114768128878db96b714de206b0323	1	0	\\x000000010000000000800003d107c1a5b55ee25d62c5695c099a5a92c6c0dcec640ea1a473203d94a2f503c5584f422f3ca5c0bf4836507506924e0f31c10ea1473260f9ea478aff1fc32bd20b1b6fd6a3e6e134bf5055a46d89d43a05571bf608f567a8dda1b88525d64b16e241932182f6d9538f8e2898d4e12cdf0032a785cd95bbab8e83c12b9161860f010001	\\x2ae4f5754f202c3082e0cd11b877dc0323583b261db8196b50a6cdbfa837edcc4adf3fb57c502f1d04393997919a5a048e179fcd7e0c0577850e40138d10470d	1659900940000000	1660505740000000	1723577740000000	1818185740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x0f2b9b544f60321454718b80fdf31ccaf884c66ac3f72cf48043a3a7db6e4c34cb4d477676b47f4f73ec0aa01208c390c6f5b9fbfbc91350b942c40a5fae047b	1	0	\\x000000010000000000800003c9dcdfa620d6cd840673a53eca6eb4211006ff3d98c555c7a55c571431bde3bdafed933345cdf012c41dac6eeef9fc79531d3e57e01f0825f0084759465752ba4d741eeed0f3d99f9bacb7f1175b1ccd4e430886c2987d5592f5572d77341b2f9a37a0d7401f19a04901aee55854df6e8bdae614f1ceac5e16bc3d36c51f452d010001	\\x69ef7aecdc0f8819e843138d0566f8aaab9989055a3838953299075b9fd89eb077ade8e0d245f6c89768ec7c2b70290565984a799e469a0fb20c5abcf5400908	1670781940000000	1671386740000000	1734458740000000	1829066740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\x103beb416e77aa1a9b3e3c3c25b1a293cf3e598e25be7c647f9cbd8cc6716ff604e3385d5278033d4a8c06bb16706d4ad841e2fb6c2d91aed84de94cc78951cc	1	0	\\x000000010000000000800003d732880db9d604d468ec743108b33f39534ad145149d186576b905c98e1c5b914ea536aeaa6f82fa418fb3b0540f08f9228a009bcb4b918da35595348c5f3905f050fda4451bf97506d90f16e5e556a08a7bceef8a5278833b046a64a223f56723a290c1cdd90faacd20339ac4ca7cf16f5393e28d1208a4cc8cefcf6a580843010001	\\x0fe629bf25df904437ac469a89d238ff550613845a60aab047fe181c4495677ad33148568f8c0393c29929f28b70a8199064bd583f58d4163c3c012eb0c4f408	1661714440000000	1662319240000000	1725391240000000	1819999240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x10f7e43aaf02904fd76f8c5061b3b34a607680ff46441db19ef7ef13081361a5fb9600cbf38e5605b5d09d024aab89efbe751b5abd72c6e5d51a199a34ccb951	1	0	\\x000000010000000000800003db43e25e1bfed26b95c2c56d9f28928fd14e2f558da35e5127a8c757130e5a4fa6327c8a876c7d02e14752c44018eb94e98e76746e2f22f2a756694f0c47fda2928e765b3c7fbfb9b18cc3114119ea4403ba0aa731418e31db553365f3e92fabffb2c19f0286189216ebad70763a7d85ca24d56edd860b0143006f4de1f9f229010001	\\xcd2051fc8791db8cf80a4766f99efc7eb20769c802837bca89163b5ea1c27eedac36cd8f033a1951288928ae07d8f0dc5057c5393db571f554b6e9a93088ff03	1662318940000000	1662923740000000	1725995740000000	1820603740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x13d3023cefe340138f56ea50b3333c1520322251ddaf179f48878c54abb040173d735e6b1e4df26f1856ceff2fc017110b5627fe2c22252474e616980854e2ff	1	0	\\x000000010000000000800003d10886d227fdbe4d227bcceb4f3b3f76d29e357f3669f0d120beb80ec519f56e1fa3abd6e671897cb6f79c2d6f8ee3c8a4604339627390e0234e672f5bb6fd9293d5bd93f0b7cb84e4ea37ec67ddbd37983debe458af76b1e7ec60a0df4ffeb7acddafd8f9628162268832c644ba8ae42f20454ccc9d6faeb1f51585cda1ac99010001	\\x73ccb81e011e83afe4d97a00f0ef5c1be11e780dbf25fc7f30889cabe8a1fea0ebc0f796a9b603e66d1fb9c3267d45ab6593e5160fbe95e894447eff8d4f6d09	1662318940000000	1662923740000000	1725995740000000	1820603740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
330	\\x133354a61a9e8bb98653858cccd9bdbb3fe2735b83c5b4aef38aef1979c4fea7b19e78e277b1529271e98f54ee8b797ec0e786e08e0d40444ce8ddaa3f9603bf	1	0	\\x000000010000000000800003b14613681a0c3820e56a7eaacd0f269ca5fb0e95d2da295fe2d772b9c499b9deb0c0ffdac63ae78b78b80c73dd300b8ee1860d4f5993165d8f5448856a551c3ffc4d5185ddcdf29e5cd1c2a30e705addd7ac95b58e94c026e8d643eabaa5fd9608eefa12c74b006b06e8f9d22dcee14d576725625578b7a7f7ab00f239238b9f010001	\\x7f23c71d0220fb5b1391ab9ad07d5dff2a0491c1bb2a508ff7454a846a5edde80ddad70cc35db7013057ee8b3533c588c5ebc5f1e1778cd63bf4342cae89db0f	1684080940000000	1684685740000000	1747757740000000	1842365740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
331	\\x15138f5e2c30778e5832429553e92a059f037f46252f473fc47c8f20ea7e47ad4b351c758d73a0a2e004ec101dc817feeef0471224b7ea5302cd88c6132f869d	1	0	\\x000000010000000000800003ba0df12c051db59fdbf63d17ea6552b746afa16f8bd8a6477ef02eda3376aa73f3f8dceb71967c3e8acac19d311097a11a7c4e0ab1fbe9afecd7c37eeda5901c34a6790f1f84b5f9d6e01f58507d8d9ccb291e1cec7105b4dc9b13cd9ba87415f5538522b43c4200dffe76c894b60c792411ff1ecbfb1bcb70b4582b79615abb010001	\\xb9079b6fd0067b824cd3a67a378663f01e3149adcd78d0ccf1a98b1a21afad45cab0fba7a336c26475dc8c0f3d265085da1d38fa0816d39b32a10bed187e2e0b	1681058440000000	1681663240000000	1744735240000000	1839343240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
332	\\x15479e9c07df674aff72e37176dd1449bbbf44d751861cfe58ae82559cb93c380f5bb35a9d318e71ff46882f506a265bc90bfa83dbf960cd3a6a2fccdb050c36	1	0	\\x000000010000000000800003c342ef395c2ceebdbb8ee99b60e72f07f066dbdda5ce032e6518ef8b04d23518845f81a46c931c13097a3dc9372d11691c35665a4c2c8f5633164ffe9ca9915b5c5b392e82dc999fcd75aa1ae81e1a01e08342e524f0110127c991ee4fd367705574663aa90083871be689810dd008b08b1e88a8739ebf2cdabdafd4275be049010001	\\x032dc646ab6939d456e08d9747a7a5b165cf7f5d507e20227baf9f78cfb28ca51296fbf5952625d175f6bbb87940eb7e205a5eb50d520bf58cc7db94a31f8906	1659900940000000	1660505740000000	1723577740000000	1818185740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x1aa3832b9730482c1581cc99b3b27d68269debd0d36239316c0f721df10e14bda1705be64c9463fc90141a3ec99259ffbbee992099721f63e5bf53e9066ce5f3	1	0	\\x000000010000000000800003eda87e42c06f627adb8f6c2362f49aed1dac284a20e5b075bf8f24e744876d790b1981fa25d0f24660b6a57da65c3a48d6e40494bb98e99761fb3f2dbb85042ead8e69abca36c818a7941a14356cecd290b08af8492fd3c2b8404737212ddcf18357d315eddc393946844b39fb57fe716a99c2d50f9c4da860bff93937771e17010001	\\xc423eb7c4c2bb6337f9a647b6a627bbbcaad11b486fd264d35ed5e65948c42068720e3c0d8600d74ebc52425d66c08c0f80653ff7083920c39a177d0beda3304	1668363940000000	1668968740000000	1732040740000000	1826648740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x1b3ffdb5c4eb625cca50a9b066be616656fe31cc6afd926595aca7badd1db8ce201509b4047758e30ea354281a8faf2520ea8db9372408445a973e7eeb8b09f3	1	0	\\x000000010000000000800003ca7309a751890179829de1f3738e37302db7303dbe4a0fba74e9545c25fb941d0c7225a51dfafc2324efabb994daece2b7d3c349c332ba32cb1369c3593ae837be83d3f643b3141dc62fcfb8f163d5b21d78b71f42f308656f5230a707890d22f21c26b66dd73dce3b313cdf864b98cc2833bc001ac48b1fe96daa143375735d010001	\\xe9eed7766e114e63e96f3a8addee2a0ac482b7fc27e9b59f0ad91251673959642a53242e780d0c1df8fd6742287b4ca2c183a442c28caa4fa502bbbf0acd4b01	1673199940000000	1673804740000000	1736876740000000	1831484740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x1b03ae0fe3773ff2947e33b134d2f35a7b1392b187d9ef55c757a564479030c366a1271cd474f733770fb6c7cf5a814664c61ded20aa002fbc2fad6f25334898	1	0	\\x000000010000000000800003d03168203984480b19536797cb88b7d79d7c9adeb012c91959199bdf1068fff42607521b7b9f9577adada7227d181c36505ac88e484a9f0e5e3c281edb6817acba3ea3dbac7e2c44652a2d3daaf39985231ddf1cb07a28a3538feaf4c7c29b6eddd4a06ffc4acd29363aa43d871514bd44b5e581de9a5dd80dc4c91d04d6e4e5010001	\\x18f27f1ab0800be686693e680030c2dbfeee923901b60660f7158db6f9fd24030de90184ec43ba6373829b0c0a4b68cbf92cb72bd168c21cacb43c878322400c	1664736940000000	1665341740000000	1728413740000000	1823021740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x202b3086790ba94aec142b327bdfedec21a01e4d3e239607f68a5b449cee0c40eb1093277a6159dc3ffad9341c45d312ed45e4a21a8283e54c50b5eaf4d80a5c	1	0	\\x000000010000000000800003cfa51051500c45392ee0c8a3a91ed0732eb21adb9a94c4656b5b26547f9f1ce5337f506b9a6ca0adacb9290ed06f8fd9654809b83887d17424e4ca2ded2d0d3f5e8dbcfbbd2816da75d918ebde3d74303a4b8417ab17e9efef945d7962cb8202344861a3b33a28e735d937c78b8a956ee2d5348a443a19d4b2372d65142506b3010001	\\xc36f0aaab7e6846396bc7fa0ae72926eb0ecbb5b47f64f224a07d0d6acb879bc729f933b9399ab0d59337446e5ea5a46134ec4753f8e4ce4b967100d8ce7af09	1678640440000000	1679245240000000	1742317240000000	1836925240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
337	\\x207bf58870f17e853b449d23f3720e35a984ae5cecd8d0b3cee6b32ff6d796118e3a873d62115b98692cb44ca840104d7bcab67c56eaba292ebfa56125adf748	1	0	\\x000000010000000000800003adcbed6faaf51e32f5cb7c7f371c80dd7223fa5e045c05eac3d45fb3c4aa624ffccf8debdff12a71dc90321362027dfc51914395e82fff2c0ad90e9ec8935c242ef2e270c1bd0f37f0724b8deee520233f065a1168165629ef6f1ba7ef85c78b8d464d8c1eab87f073a831373080b0fbc9196e9d667506298ee057713146f2a1010001	\\xfb3f7d15d85230786bfc0ffdd254c6ad4c71ff25b5fc6ad273d6e9745a61ad9ecbd3759df33d8d7133f9381d273a751881297aa9e0fd71971f8a88d2d120d903	1658087440000000	1658692240000000	1721764240000000	1816372240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
338	\\x262b675ffd24327fa0c3e8aaa3f63b2269203082beb30253d8931f507b742375a5c000de5460b6a1e544759b7b7addd2e163981e4773ea126f8a0bee6d7acb28	1	0	\\x000000010000000000800003eb985285cbf5cc9cb85dd1f7aecbac8923fcf756d2792ffd47db90875cd2035ab3df1e106aa56c2d7d7cf5975b18935c2c5f3db1441490604f8e46cd341808e33f58b3927a6098c153e96f548586946a030c5588c9cb6440e1b0faaaf8ca87b1c7572ce9296bd0708082b3f6f2f35461062976f27e811e18aa3086f9860bfd2f010001	\\x3ae307a0b493f1ae3a6c58969569c91ccc6386319c853cd104b81b273c0fe6eac545c9ef3a7500cf4e85879581f1d9a0305d60670be697bc22e0ef29d57ec50b	1659296440000000	1659901240000000	1722973240000000	1817581240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
339	\\x28f3268ca4c54d37c9190cac776207f8a10b1d8444f7b292d2fad31d91e7e7cbf57fc66c8e8d588e46022fa4c964566f7862108b5b4e27140b1fad7830eccbfb	1	0	\\x000000010000000000800003e1ae4997a4adbc0c0f4ef50f9059ad7dce0da3bc1b66cc4172360af8e436c5c1de79c2a82ab02484755d9ab23396f4e303f90f7410207503934156948a27d67e94cd67aa052dfc628993d0556b48563e35924616543a75d15d3003e9229a77753a8ca76a55a87d410910b51c569868d1bf2a5db95aed5087332799ed26495399010001	\\xb7ea16dd943eaefe88f0e77f4c7f45248a829559e1730200d7cca2a7421bc593ffadeb1c0df402107e0ab3a558b1a91dc267145d13c66697969dc75ec3345107	1655064940000000	1655669740000000	1718741740000000	1813349740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x2eaf0666f4cdcf2b33a22481845cd55e1bee44fd3b6529c4b69c3457f1bf26d8255bd4135e0b9c4d39c2047862355927194e3d5a5b76bb3bc6d7e9ae75cd06b5	1	0	\\x000000010000000000800003dffba7e4202a920bfca8f63a1aea792952c5a7615603519f54c2a0e3b481e4348585a4f6ada3854516a7edb2b3bb431039e1ac2d9c19340b4f17cad0028a41188ce2454f85aac1cc8db63e796e9ca68fab75b1247d3490e0266908efdfa3ba0f167bd7350c642602f6b2b4cfd300bdf2c3736e8fc744f7b1fea1ebf373a6df9d010001	\\x35c660d6bacb78f6998e60268a7ded6388ec7fb334b8e25581b4168d3f327d97970d44b4ec15e82b105c4aab0daa299048933b70c7453bac0c48cf42d3c6d304	1662923440000000	1663528240000000	1726600240000000	1821208240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x2ed70245ea6c2751ff78b17db205031b8f0239f0b50eef0926ddb9cc6fa9b651737ead6d402e9e6430e161d9285421f12799a7732fe290ae87bcb5c3b21ce525	1	0	\\x000000010000000000800003b56b15be147d4d1227ee4672cc8529dbe47f99810eefa6841f95b0b43f074bbdb745825f29a0a09ddaa5487cc4cd45214866d2437c982f3a2070239c594dd920e05521e989dbf27e0a7c8466de81e44f967c0c80cf0f61b6915dc287be4b9c376cae82e6d05fe67b3850af6aecfd24fd0c0140914da07c4871591552089e6155010001	\\xc3db94b868b690b9998f3d7ef8be3df6edfe4b266d29d42102f24f548ba1aef2418943f2fa0f3ad7dd92d6482979b3ce3e4d0ba545ca248a4accfbad983aad08	1678035940000000	1678640740000000	1741712740000000	1836320740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x3147db00f073d0ff42958eca0dac8dd1f488b6fee2acd52185c9cbd172c2c2e02056098a9d7c873a280a0eef9b2e2affb0863e88dd9433444d155a751a7d4d2c	1	0	\\x000000010000000000800003c8abe6dab034de959f831a060b3e5c105ae7cede8e5121ee13f398bdbbbce6e225533cdc6afe747ea63ce1863ce9b18fd93cc3b17ff8cf1961112b053c037663fed108f55e8d73e7507a8268296b90666a60675ca5d99563b8d6c8d5a32bb980ce3158f68a6961acdb0e5f42494f89d6275a59e563768f9d5c2bbf938264dc89010001	\\xfd52712c14d98f1065b81ba7bbc96172181a7a1bd75f3d8da6467e09e3677e8fd05ed907d5607a5e1782e9a1d445e49059bb72ecc8becde37c0dff3b393a1507	1668363940000000	1668968740000000	1732040740000000	1826648740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x33d33fe65fd1834eb99d5950f09b7b3d26ad8126b88a232d97e32224de9f1b5d531f6af0d43e29907867f639017515c23715688c5284adb7cf030e87b4d3c8ae	1	0	\\x000000010000000000800003a511ce03ea049af63b4585d8b1b03cd233e3ea11721ff90af493d45761b09438b1828035e2c9265d6c662aa636af8d2054a52f54d5ce27e6a89c47fffcad6a8a317873a8a13529c62396ce3e5fb27f581a0e88a43b5c0937e1527f556f733558742c2eda33b37330cc512b606afbf0e809702f1eff364222434bfeb766e7566d010001	\\xcb864e48c256740fd9a3878bd65d42793dfa7ecb2a8b2d6a30fed3aaf69d9ec34f8e5fa653ac0d6ab38bc1f232e15d9d535a123052c7432fbb9a4ea6da22f902	1681058440000000	1681663240000000	1744735240000000	1839343240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x35274922a54b1dacbb516f416009e145dbe7493f3035ca27b851f82ee5a8f52d86d86e0c0d5eed06fe065dcaafe6a8c19474807c58e7ed4612b5cc8b80f42510	1	0	\\x000000010000000000800003b83e687c8615ed8740f2f0796ad54453571d93a213e4d775089c04f8bd0f522ef97c68a7fd752b0fcdbcc31a0ec2418de018c335d565eeff716a1c6a33c10313aeb62f7e4c94a035c29b2d38e4098cef17d5244b02742aee22ddc0372865503e9fb91fea5f5a8e79e29cac1215b0a173727592587112098754130097daf60535010001	\\x2ae10f9a5ab45525a2cd78b409c9c18d1b9cdf6c6f99bdfe0127801762c152245cfa0cc0149b8365806b2f9b8045cd78ada28112f5680fc8a684b0f8d00a1609	1659900940000000	1660505740000000	1723577740000000	1818185740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x360bd673d989b96c0313383ddb9beeef81535fc135ffb7c908fefc92645ed38f1a5914705597c041585b466f7b2f52d9a4e59ec4ed04faaec7359a901afe59e9	1	0	\\x000000010000000000800003c5207c56c5917bd841261add4fa74926b48158dba40565608e4208447eb718a856904706b17906ab9a6b01453f286575d373ae2b26d52a7176f491297a51bfb629dfb183a502ab42a695a4f3ca713fe73c8e5073a6592fb64f521b26eb88afe160d393a5e63abecb47d6ee0a222ec56c5fdd5b6a813a2d2f7ebb26b1037f9aad010001	\\x2d7cafa07a06db316f5aa19448f4b1b3f5ad68610025a2285339c1b03303b67dd91796cc88d6f0f39ff31765cd46361c6277b2ff18b1287ea85ac99f6dca7a0a	1665945940000000	1666550740000000	1729622740000000	1824230740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x3cfb6063f2bc6219e852355088bd69424df5a296cf75377a54ff7d9afc71b247d3fc1bb122169e4b2e4498dd328e287c9d4cff2d013891b45e825ae2721778bf	1	0	\\x000000010000000000800003bd830b2c64515e8579f6725cda086242f073b83171d73fd93d0e586517ed1f035d946fcd7bafca83474585aa52f3a8a6c011a21453669e4e41125b5f641fbef52750543c4443f4b5ea64960609aed627e5f01fe12ad9b755e8a606a5186193f63384e197518abffafc167a284654a6868a10e34e623c6f8f93600841f694c0e1010001	\\x04a30db31bd5588e7220b188bcb003983f61283125ab90314ce8b6cca7ce7ff3cea17f674b1a2236a4547f6997a6d08338333ab7f574a08aa95174acf28f4909	1662318940000000	1662923740000000	1725995740000000	1820603740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x419fe27e6076ebea5e9614733b305d3c479b543d114347369e37032c336654841ad7ca648d5d68bf27482891d45e908a0111423addca62db6687c8bec27cedb5	1	0	\\x000000010000000000800003b26b9696bb7dbdbb05a033b89b614f3b80818e79aef542e54f6fc909018ff0089a6eeff0fea2b0b4f1d858f85344183fb72af0bf18434bd2131f0583caad3ed4b312ec242d3776acafdf9da5430f44b32a07c31a726f6785fb9641dd3e84ac41c3feed8eb7b1447ecac518bc411353aa388246ff837f4a2f57e8b1a2f7e7d8e1010001	\\x614bad54c13a9bb7d658d39940e22a852f0afd0fb4fe5b304fd19404f3f62d9416eacdbd8f0e6f845c8875c3a685dfc935ea1bcfde1d1ae0eb15bf956568760e	1670781940000000	1671386740000000	1734458740000000	1829066740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x4173e57f5b3deceb7edd89d26c18fa1166ba02996c10b83902630acf6875aeea1b2a689fd5076dfd99e335d3b88f8c4ec463493b53c522ec8e981454895ae145	1	0	\\x000000010000000000800003d1aa72c1ea17040a3ec9fdfe5e129e296588ce772350f90d8c96c9ae8f1b44b5168f1a5c640d3147c4d419f34d51d192acad31318b748f4a9935e3b6e648814b1aa602005e6d58f23aebc5acee9f85c53863fbea9ed6ba63a532492bd0837746ecc63183cba951b5e92564eabff0c182cf1890ac70fa9934128aa95b0fa1294b010001	\\xddbf6606acd889278d0db7b64151f153422bd6f4dad816bc6d8a0a666669db17ed48a961e3cd94ed8ee818ad7eb5b33b3670e7c60d2f553b1156c5f71f8dc400	1675617940000000	1676222740000000	1739294740000000	1833902740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x4987db31c7d8bc9e2614c08c98a84d35f6eaa284c3c70446760ec6c74951fb5acd2c611d680356d2c9746568bf7edd3e375068931e5e2b3e58ac27368017a2c2	1	0	\\x000000010000000000800003d7d4163bec9ee43c0f9aa39bfbac5313e1bc3c74a83f47c0789197b92498d864e50558465a53cd9b9ed373b56c31818811b5414ff6a27066230085df2fbcd366e842974b09f9a5cabf0a86bcbb3c807c68f76d54256365855f68b3a349adaf599bb59c8c8e19c913ed1cb4de901936df207eaaf4158ab2051773537176070e3b010001	\\x0e255a205d3db73dad60e2c9daee476605447d271836dbaf4da5d362563117db89243a552a03a09738a3cbe8bc1ab43425e08586e3f65b5833c15a72609a4302	1679244940000000	1679849740000000	1742921740000000	1837529740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x4bb7cc520e747c9e120635f6053fbea1dc124154312721673472e76e3fd76a3e0bf52533b1985f3758ddeb69484a093bc204ade99076ff66e7a905bd654f32cb	1	0	\\x000000010000000000800003c47086fcf911cfda8c3caaceb5ee41b62a02a539ae93a7295f911c752d392544da07cd1892f9bb6b86b6bab046ea0fe0bbe720837c6a6207197a8b0776f7c9dd36d3ffda3eee9fa98148639e8e7ea5333dbd4a84b872508ef8cfd4a8ec056660491e411acd915513647bc685cedb43baae38672f7e2bbb5ed4f56cd4c606e57f010001	\\xaaf89c60cbc01a6267beb4ed2dbd5289ce2d3984b804a2820038d296d48228b1386729709620a5c6a9a294bc5fc54fe4fca56c17e8674c22e3545357f6059d08	1675617940000000	1676222740000000	1739294740000000	1833902740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x4cc71879f03eda06ba18fe9896c3aa3559f663e4f05e51a3fd285a7aaa7b85e94d614194549bfa050eec6d43ed27a72113ebbaf1682cb7ffc87252508c6b738a	1	0	\\x000000010000000000800003e773b95b3b4e3247240551753f3ea35324e034df27352db02652148b644f0c2c0fb9981b054fe5d8a706600f4784dccc471a88616284e6d85893482d7d0345e17ab46018e0558f1daa6d4729caa4a6eb7bd9abc2a8bd9ac95baded9f3d4cf8d22f12e3b1ebda957227c66705aceab7a5c45287f083790d778bd96410230e2ab7010001	\\x46c0dee5d7d3dd21e90d6ef859a759b91d19b4a3f990ea448394f7d8d352e6d182f077d0f84a4c98a461719fc22c6a7ca63d8045ace05283d3b50315060e6507	1683476440000000	1684081240000000	1747153240000000	1841761240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
352	\\x4f9795987f60f52e9a7a8dec169528cc49e88c380321d9dcc188b0ca179c614a11e9d1723d8382d7c6c119c47669a32539ecc96768daeffde99ff019850bb705	1	0	\\x000000010000000000800003dae807907157ea22db07a4a9eb5f4dae0e716be252b6591d8ceb7ad3fcf2bb294160109b8086e9428b957555627b1440533b6b37da343e89f002a831eb97829bac098de946f70f6e068100d34ff4065d7bc15c0e127056b840c8ee7b3798978003e9acd95f11bfb7898b0b317b360bd2be23c1f4bab99ef705ab6ec98c055841010001	\\xb129c70dcac0c6529edbd6ecca802ce624f96d3addf2c5285ba903595717a3e0ad5ff83973e09135e6da08ce181b6d8d56cde3dc555d070b48d1107c84141005	1664132440000000	1664737240000000	1727809240000000	1822417240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x512be445fed8dffe99e8842f689729de8749264dfc45b72b7fce4d6408d32ca8245052ac00f3e5e3640eaa8d0af2f0b9e3cf8868c84ec4b6008292c321f623fe	1	0	\\x000000010000000000800003a4c0fe1aa7c56b230b8c646cc0b4cadce28812158e96858ce89fc390d186d8b3ecea3badd8aa435f3923a906eed4a425fe72d8f6bb393a7bac343b4a8a0972fc2d2ed0726d0358f4b7649109c14208a6586373a55dbed9a83706d7381f70818ff1b2e0afa94d77ff5491ad3b15c106a257e5d6b9495c329df078f7f0e901aae9010001	\\x07d7a5901c125f92e6d85468cbd4d1efd5d78a757baab7405f6c1d11c3a49a7d90e15362b09f03fb0bbd8eaeffc78170b298c1c5393915d7e427acfc9d9a2e0d	1664132440000000	1664737240000000	1727809240000000	1822417240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
354	\\x53cbcc1f5da2008448452cf3ffc7c725fdf2ad029de328c42cba9a1a1fcd5565d6a3353c04cc51e1fb66884e887908162c4ecbe291f25c6a9533e019825216d0	1	0	\\x000000010000000000800003cc0fd250d7063ac2ba27fd5c81fa8758937d5bec43e34b58139ae0aae1268e2bd79b6b59a75ffbfdfc5f4763822d1134c6f7d0e671fd8742ea5515b35b2ed3c884e6146c6560e4f929ccfe19b92bcf8105266818b9bf901c368c31f820122e2095f5e820562eb62ceee37689121f420c745fa9601a65782c50756162381c3d6d010001	\\xb4b502e1d1556e1faad4df2cfe33eff0d24d8dcfa1e392971f9729df506b43b6423860a7ca1cb30e6336553ab685fb2acab8a34c49b02be76d7f4386a514280f	1670781940000000	1671386740000000	1734458740000000	1829066740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x57e77b6752b2357d358e16149a1ee015ad3a4cfbb75969b1452418abac3a647d57d673e91e2b408d235a5b81914d07742c573cd2c12bb06288b4f44e152b63a9	1	0	\\x000000010000000000800003c0c2ca285f50e720880e1c19939d88e5a57dde70a21cd24add64ac9b8218aa9ece3534b876f89e88c1ccd3bc3b2d5db2f96f8e954c10cf659cb3c7574d389efae5739ef1e33e93e24c9482da500046a989a77229ec8f5eecba7a2f6ee0bb1e89cab9b8b83e7b11d122a68300e18c0e525af4c3242aec536af61746f9d2ffe5d1010001	\\xd0f2190643b9990464ba1f703df67f4a949309262fa5a7450c0fe96b6f93fb50bbb2829999466ac92a25fa845711e41b209d357e4e00e028ce8cc9ac3e363308	1660505440000000	1661110240000000	1724182240000000	1818790240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x5817e6ab34b26f0ee32af9c3ec477e50ff3727f94e9a216f1b88dd24c5e533b5b6b6f713cba4c9a969559526f91f1bf92eb8589a4818316cb1cb9b15baf584dc	1	0	\\x0000000100000000008000039f5c53478788c637fcfb50e03f8f79b28bb1e2c85937d8c11478d9153ddd1f9b14885c84e6f45ecd4a47fba4ed6b2f84b03e30857d521ca1d7650160c096db1057956ba78c72d4357464e5ca44fb5c80885a92db1cb0fef0c6cd74bc9649052a3d6677e7b9b046af41bddb0dada3641aa6d1c7abbef7519605755aa4a51ade7b010001	\\xe0524722dc9613fa82f2e47974e3aaf088605679cfeaf4c2f1e64cfed6903069023f7998169bb48347e3e1fd3573b5e4b03ad4478a5b531e044a8253ff8b5904	1657482940000000	1658087740000000	1721159740000000	1815767740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x58b317776f9fb23f9131795e5234b18250fa77354c4371719413fdbdd5d4429698ed0bdc18ad1042f98523b0e8edb9a8ee7424183e0e598935e0fc65ececc4e7	1	0	\\x000000010000000000800003e3f1faf5bd06fb9181ad49e64c106bc1b73e46710bf1ccb832c41e4e53508d55330a48270b382880f9e50298a8a1d4b454b94b2d006d8cf7c9a12d0cbf24c8c74026e3d758048e48ff0b6916ad8dfaec2e4d3076d8898342a7f5a4d147e60a12e547654ded0175c11bcb473aa62469073a35f00b9fae74ed5bc670dece65452f010001	\\x63607e2d740af763c2c4a6e3a8c7635cf99ff19a6f5f446163144c740b4014d747449b2db1052ccbee0cc9ccbc5aa8b8a7745aa66f346372f4c4f39edfa6870e	1681662940000000	1682267740000000	1745339740000000	1839947740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
358	\\x590f57627d694f630b2d0a260f16ecb7e7dbc9e1c130788b3a5d9924fa1b2a3747f47f54dfe3565204fc6249325c1e458a882253b4be4923b836efdf5bb487b5	1	0	\\x000000010000000000800003dd0371ce51e6cd8dd81218ab3270af96fddf67e6b146e09aabe9d9198eb13cf9f6691ba3d3d1d0188577a4db0c558d0ddd35b8e3b2914f72e795025881dba4a9bb1b70e4de531ee85142b22622359f21e031d7b8ad02dafb9a11bdbeb8695e95c3d5f7120ed4a4d69447a80aa587be6846191a5183806b829435eb731f17f5b5010001	\\x9e6672c28325f750d2f1e510d1599d659fdbc3c0d1acb0a30495c7d4979efb8d9990786d076f13acfb95de047607a21bcd4316aea6a99fa2c11354e7ec8c9703	1686498940000000	1687103740000000	1750175740000000	1844783740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x5bd31166c781c73c65ef01fa66e27fce40da5168b3a524fa6bf193a91bab9ab129689006eee099b47e2c6bfa4b91e1b5da2de56f451b1fa408c0d4c6c12df85e	1	0	\\x000000010000000000800003e734f71398ffd3d8696443ac33e5762e907b180981e57e914214a3e80524d3ab33b7ca561a725ecb10903bb5e30876e9ff759d0c2082e796c38d8e60b1821219cbf7f7132fae368d30c6027f854bf1a6c3a1edd2d19c9a6d7223676f920650ee38626cc259faac105d0af1b57e948167b7a526da60b467538418066fbcc0fda9010001	\\x47ffe70a696b143cc3eedf831666f4b41616a1f505f37245829c00bf5318fe1daf09f3237b07edafbe31affa0b0fd19040e49d84ff3bcdd46dc45d3011288101	1656878440000000	1657483240000000	1720555240000000	1815163240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
360	\\x5b4fa13e62028559185e4bc966d83bb5604f59f8e9ebd771c9a2be113064e6c7e9d3f1fb29d8331cbb1bff00a0f1a7c68db1983f059d91492aaf635aabd32a4b	1	0	\\x000000010000000000800003bbb7a213a7076a084b168fb88d9002cbbdc1768684b2cbc73f5c6b0586c1a35b546c91ad78afe7a121eebb8520174451500af6b12eb1eaa509ecb7410377d7ac2969481058c0f891240c2bcd0af472001d3fbc6efbeff0d259354bc5315b3dcd3676ecac3a4b6b75c9964bbe6e907729699e05fde1159cf219807a06d6f84c63010001	\\x29495e5cf414d2c3565d67a8db5558b29d9e6ec644de0e0083f3ba6c387008b098ce0cf74b76712db5f2c63b07c0780f825a9e6611ddefc9dc00c8d09390f502	1662923440000000	1663528240000000	1726600240000000	1821208240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x6003e5685f2b3c464d475928b1eddb91287a25561542c780cba2dfd6796623c319cc2afdfe3d8981d2525f99825b203b259f99dd1d394937c289a3857142b7f3	1	0	\\x000000010000000000800003cc04f9e0de64a1ad4f80906c4e3115a99dd800c04c95668d1ddacdafaa1a7a8db2f53cdcbabab21b8c64e24d25d81f6589ccae9bd0ed6d0e2ecd9f09c1480e0cd83a013d9c853697a87066b302071a2a19f5f6d2ecc5a7e757deba62d3efd9eeffaae4b612e63bec1478281e14b585a5aca6538652aaba21513cc67938bb3423010001	\\x2234e78fa747c69c7e01aebc206b5b6c892661d4a2dcf4de94bd632eb171547ad23a118bea9bad7a749b52a7c60de163003485c68880398645412b91663c6204	1672595440000000	1673200240000000	1736272240000000	1830880240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
362	\\x606f403f43e01fbe7698ebf81ae6f0dee36c396943e795dc7011497cca9e13c17ba28b525713bb99ccc5cb60cea74bfc575a8b4733b873bcb39420c792068e7c	1	0	\\x000000010000000000800003f0c440786b1b589ed17df7a22edc90ae787d3104da3ab07cad47fd171abba6335ea27f630857b1c7c10075d32d16caa068677478135db110f6150c989d380fe6c0db4eab37ce093a870f94a6cf0318adc2db56df8a382b5b96464aacc7c9a4939f9407fc9955de776292754903579c1710cd81844d943e1cfc8e744a8fed908f010001	\\x5e0b6d445113d7491c12a87593e1a43513dc5dbd8da416dc24612d4c7e62cb15ab2edbf5f4907e416b271631b23dc41643d85ca19f299c2aac27c747f6956e03	1660505440000000	1661110240000000	1724182240000000	1818790240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x61e347a5a72e7bfb696dd1dc5ebfdb7625c26800b54034142b502999e69c08d035922630b35bd48d621fd5fc19f58bfcc05fbd5f06ed7bf192c0e2a27a4f21e7	1	0	\\x000000010000000000800003b8037c93ec58170a6c345d8d91ebf995c313fdc1ad7f9881c9264b6c313b29d74d3c54a253f820cb864deec4e2b03c95a23d38dbd7d08f9b0c48e18532c69663b86306ca6a2e991ca1be24e3ae3b9d59d0ad582bb079817165d9fa2d2c9cf13ae520aafe612118044d46a892306652f0d3525543216c20c3f410cea2887c55c3010001	\\xd7c741e455a6e82f531d1c6769108423a9fa8e58f785b0a225823830f1ca8477d6b58e3a6964c7bd7501a7dcef98dedc290b33403c8431dae2e17abab0530c0a	1678035940000000	1678640740000000	1741712740000000	1836320740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x63bb598c2812e62a5e7681891c3dc2eb302a17cecdd31e4993b64e9fe6b0c8928ac475c3d44560bbdeac27586f5b2a2ec31469753c1b32780036ce795b8fe66f	1	0	\\x000000010000000000800003d113ef3e9ca9653d5d96d5afc019f53bfdd0bd8bf07c6d69f1758bf57214060bbae58fe1f70080ab74b0f1cd7f9124f5ecd87bb212de9e44efd0939242fbf6a59b74c5b70214b25b6576531de302d1bfb1f9e7e3815b6ab2c013c8d1d7d19ae9e045a09acf51fc720567dced499adcbae4e9e3643b3749e65ca08bae6b47151d010001	\\xc9e6097d64c68115b76c434f0a7918c7396e95f783b0142c5db468b6f151e75d7fab15f951060da30c0f0f29d093a488cd8f0f52eaa3da50e390ec20755a0904	1683476440000000	1684081240000000	1747153240000000	1841761240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x645f250b5f93443d08a6be0ada672dcdc60d06fbbf35e586db491908eb68ad79b456f99860379961ff91e904b6235b10660c2a91d68dbf14b19396566e84f084	1	0	\\x000000010000000000800003e273b560562cb3297ff5b0914b3eae0a5f5662e42d685eccf76de8b162f6869de09f3842b4114d12f5a8cf7db246946050bb74a4ce78bc2c30dff256ec1c8606c6d660b5a8460abca94959588805454c192f6268938205bf3e442d91d8c5fea3f8359b0b0741de53e2e27cd4152be47c6e1099c975cc129fe2d5998df9d1832d010001	\\x67b85426c943ab16be4644331f86f843d317749cf967d492e47665f3a4dea71d7fb7b27e4de50ed1eb2ed9560495001e1a2581a0d35f3b56a1db1fd2ddfeda0b	1675013440000000	1675618240000000	1738690240000000	1833298240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
366	\\x65bb4ffea5b52aaf52375a99bc355e3b2331886335f612cfbb1089e67effeaac29a4cab97f164a66f0f0a94fee5a27af7a18c5b42aeff9a92c30f4d7b1363190	1	0	\\x000000010000000000800003b61ee18929fe8b0039a665c7fdd2c1d2bfb08ade972390419c658575ee896686db10ede5aea5d75fd026bbf1374acb5419aa9a4761d82802d070a4e3bbf1633db182a23e52dda105a7758e32708a67e0b52beb13116d93d008f11c2c4443b7bc04c404c98516a54eef60aad093d37a1d14de751f731ea41dd5fbda3335d52e17010001	\\xb49a237dda9dadcda99c513cbc14115d6246b9cb510e0be4f332cc0ec77d72952fd15f086ba62822592deebecd7f72a555a47f0082db1042ca9908e250668607	1670177440000000	1670782240000000	1733854240000000	1828462240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
367	\\x65c3a8aaf1f66613328eb20347094184fd3a0fae4fc17278f21ddf8ebe116cdfa9335bb862b3105a5076d0c86cac7b37ccf441e6e5d593bc7ce8038e3cca5782	1	0	\\x000000010000000000800003a812cbe279a49312206ddc6cf167f24c6d5f71fc69396523c71244bb6dd345a21ebbcac77f8e233d756c5ccabbb3ebc4e0214a5a8aeb691aa8ea783aee33e26d1e684a9edf909b88d5410ae0be7b6a93778e0daea474611bc65f722371fe95dd3a024ac9d963c5d9b8e55f26a5d166484a29b7ecbe169838ab4f3ade5816eea3010001	\\x2f510845779567fb823861ef5e615bd79484e7c2e41db0992880a698f882506c078e81260b0da186e17b6424d347b8b35a53903c4bc7ff3636b4d21df1bf3307	1676222440000000	1676827240000000	1739899240000000	1834507240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x6aab2729f64fa027b5bf27d22f5094d4611a3af389ff1fcd84088aa0918711f2785649011b294b0562a1c7523ab748ca212cb7831d1c3ead529ede0e30fdc8cc	1	0	\\x000000010000000000800003bf3b62b58091212c42185c248c8a0273ea7a33a3b75a9ba59506d3d4561de3c9dee8fd5dacc65f981e48bff6fccd0ac5eba67960bdb1cb550e4c712f15ae5c45427a02d6fb3d1958c064a6ffbc5012a164c0d30d51bcacaf69a2b0a3c03246dbbd3658efe7afa4aa633de5acc04f378a7914c71b845e8b46bfdc2504027584bb010001	\\x6f79f2ad22e675401fb19a1f15a94110d9ca9ebb229dd7fbb34a1ebbbc70ff1a900387ebe4730c9d73dba21611fbd908b16ff94426730e852d29a36fce01f204	1667759440000000	1668364240000000	1731436240000000	1826044240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x6c9bb7fae8c2db272543678f9d8344e95abdbc376b14dcec80f036ca57360eecdfce1b27b667e68eb670a2129f3f7ebe39437e6a876200fda9b3af53ffac4dbd	1	0	\\x000000010000000000800003bde02507f899770dfec1d552d44ee49d215ae551ca91387ec3b1772fa7a990ab1a79f21d585c50e4333a21484f43352acc3ef349329c2a4b33bc55749bbcb2e705a8d4e2f2bc240e6e853c681ec2ef726ea84ed445cc3377d05d4010f28f727f40a95d1f3d18b551a7871b1572a2490378386d6dde0cf34595878d0ca26f254f010001	\\xb5b2e6b0f858fc0e00d3e75002eb149b957b3627a1a703dd4575b617601ece69c789b4670113e6ca0a7319c1417b1e74ac04a3267c9c836f893f1f79550bf20d	1655064940000000	1655669740000000	1718741740000000	1813349740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
370	\\x6eebe79db9660b73bf513856c771a811629107299ba7e35d88613caad177994c2710206a8131d21dbb0f5a5dde9d92813e521bc7eae79f0a37872fe777feb77e	1	0	\\x000000010000000000800003a13ffbdfdc9bad336b3453a09b77d16a5db600fc31f1a24e32e37b7d1ea2cf5a320f38c0bba45a71b756ec2f9f63d03a4ea2c8f2ea6fb9fdfb1d61445e01ce306edc0b51c6611f9505092af99d3b4405b3dd5b2acc45d64ced021ac29c6bc3e44db5f3d0f59eac2154932d725dfcc4ff2a5231c8dc6a33b30bac9524d6139ba7010001	\\xc57262dba566b789fde0d9bbded11deb62dda62c6fb98b1bda534c9f38bf2ea4d25f0b43a39caa3dc04797bf610d334c51884a974c3afff0bcf9435900dfac00	1676222440000000	1676827240000000	1739899240000000	1834507240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x6e677ca8afb5260b6ff3434814edbf9a65594eef66c873a34126674d8ed7472b5f51b5481b682fece132c2e695071c0ccd5921fef68f9777478e2736f793d947	1	0	\\x000000010000000000800003b0f3dd137c76b9742bae19fb33ab314ffd1f297c5bfe92b14976bdd5a067aabf79699faaf3b892553f621f8295c5632caa82900e9621d9f4f1d0c3a8587962829a9f74ab5af15780b12a2d63bfb4c83b028275813522c10f57a08baeda1d6fdbdf75d26d79226b55862572c455db6f10a75e00fad409da88d1929c6c5d5d0b21010001	\\x37ef7d9a6dc8455bc03ea337dec46c25ca0d552434eb93d250227bf5bd73a31b677b0444cdc24834610e07f9b9eb71efd51bb7a5cbc94adc29033ae93472430b	1672595440000000	1673200240000000	1736272240000000	1830880240000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x6fcb0af3524aa264957004611c3e6e4a3e5901fce6b85c18816f6744d69250e50969ff56506e44562b2b60511a56381ca7e44b7fe8fd267d4f53d6aba127a409	1	0	\\x000000010000000000800003f63bdc92ff5d1e9a8880d656f4906003db8a1d57e7b73b9275985e53463e9ebccd6d918a64fb1a79cbed5fa939733c4841a02608117a8dd4d0ac8bddaddf6e960185711eae701a1bfa06be7b196f13ae734fa7e45ec803f986acd3677f0975cb6aac8b424d485f4b09d3715988c1af5d5d38348ac6a3d0ba30c45623ac05fcc5010001	\\x218d6f4f49b9e035f1bf31d75600849a90a5a10683849a9a15c61c44f5cd4cd022df376dcb67c3312ded972dd0b1137e768ac5847a431d3b952fbb282900bf04	1674408940000000	1675013740000000	1738085740000000	1832693740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x70c3c430e84deae3979e7ec82960b54bf4025f8a4ae0c9f8b1b08fa2a07cb5ae32ca0ffa3a4a08d13d9e982af1560458b8e73961e2385bf9c21bdc952e740366	1	0	\\x000000010000000000800003a97cfae953a993417a85c2f074e1db19ff63484492f986b5028fc89b171b219bca97853be7aedae5de88b500929955ca6574278b38b27e7286b4756f28fcf187eb67ff2aef7f4ef63fcdfedc7462b6777ea7851bc8b7d0b4a484c05b68fe5862909c8bb1c71d1ae22ae134726faf5e4fe79fb1e4a376c74309b88644a09582b3010001	\\x37e89167384b3d1c15c63ec160034a3290664ae28e4408dbe51a9e6426b6b7b92182644cd7d48064b854684c15edbc8c1e22094cc417581f7aaa509dd460ac01	1655669440000000	1656274240000000	1719346240000000	1813954240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x726315adf30d2ad30b3c5861e3b9c5dbe12e4160d19d588c9efcb9de83bfb839decb6d8110aca36dd45b11299d18a0a30f7eb41f70a4f12fbbff2f186b80bcb6	1	0	\\x000000010000000000800003d174a4c1bce83b02beebb189c8103ce0d2c81def031fcd0df64a61153cc47f72726988f19fb59482bbf78a0b009822c59304eb1f148852920e4d97d9ba3d3847257b5fba5076949e0cb4f840687fda0b973a24d7904c1b7bbfd50cf770fd74d06f7da148c789246f6f499b62d5f2a99e05f8a41a0c714799fb4c7aacb2d2621d010001	\\x0f94d9a00e4c54b441c4c8d7f7138b9e7ca0bc0d06e29bfce5a998206d42a43dc1d08dae72c229918e5bd76d4fb60e2c818dee248814de15ab752f5f41df4500	1679244940000000	1679849740000000	1742921740000000	1837529740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x75b3886744a4bcd4070820023357020259a700d9fb93296bc0d13e95c1f93f4dd0fdb4581abee377bd14641aee208135a06675bf2646ec09d9dfc94df0f14b37	1	0	\\x000000010000000000800003c13965026e314db78caf9a3dd9150ab4851a909c1f77680c029759921a00ddc5624a9f24d935021427b8684c5b440a7a121991b62fb0611422925f3aac0d75ee0712bc3c9de47216d568e3aac800b49fac779e5a68b92878d8d48c2606b9cf89590166bdbc5aac8628655b67e568ac72cbaed23edbd6eb0002f73726c8d80ccf010001	\\xe6ebc5f08cb410c2457ca90bcbc59438ee8b16aa06ed744cec004b8b3b66cac45681870aaaf7a3d20f7af23f02708aaeddcb3d8500224beb4b1dca35a53d060d	1668363940000000	1668968740000000	1732040740000000	1826648740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
376	\\x7953eae1267205b545f5ffb96497b6e7c4832e67f0bd67ffe9260f38d8e873e7b97aae1aad6347abaa5d5e9cd3065aa0dd45a4c4c18c17c650fab8bd16e8b210	1	0	\\x000000010000000000800003fd16057650c7d05827ac8345c5ffa283e5c315876b5739ef52353057f7b6c25b2df196327db0f59dedb6789c31e16efd72999805a38ba7a5cc460165ea857c1a0334a716ed150624d6bbbbb75c86bace3553bcd2186f3562240b9fdb18ecc387cd23e9b88de5049a7ac8f5a85644d2e7044b6a2b85f38168db923bc43a193669010001	\\xc2b70cce54ec3b5f18a37028b3c7f4d487b0ea4bb96ebb998246653572137f8e35bbc0ec24ae33a638fa56d201c47342f4a3ded7a79c22a60c089fe99c9cfa0e	1679849440000000	1680454240000000	1743526240000000	1838134240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x79cf782b19397951dbda869a473ea5fc50003a4007d98928d1a5ba789362aaba1826745edb79aa97bced5c69b0627f51d58319fbc93ac1792a33fa78bd7681fd	1	0	\\x000000010000000000800003e412892a7c93c08d60fca702ad3212959d0d8d9d3866d70e615fc6a9597d22ab7d3d49fcc66733d41be0b5a53ecabbc8cc0102e90b1a17a46c3f0a2b8e24599674ba4f7bd271d6ae7d042cf7572e0900342e8cf4146905c9e4d7997b12fef1814ff3f3b3d669ebc235ad622098d6dda640879831b8e6eab5c2cdb23f5f6c0fb7010001	\\xb1f03818a01696987fe17a2cec230b0fd9a37c9de04e19544f33b58190ce44e6fb0838dc3e142b2f2a9aea4fb22952b5a460790d1e0629af7e443ec560b21f00	1656273940000000	1656878740000000	1719950740000000	1814558740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x7a33435b5aa1305727b1365c0f8d2a605400163dc5ba4112a2e00597cb435b93aa1fe8419ced7a9544e261a807bd0e9cc04e8c71432ce814f0f7f47a8df09486	1	0	\\x000000010000000000800003af7ce2861b506339e35ebd5fe5f64ff92a7ce5a43530ab83ea1e33ed3322b657ab22855c8237e914df61e41e6220820fbbc414922595c60319c1d304963d013d0c51a511d9441f57a7f7fde40e5c5e42dce46956348bf06bb0f32f2720a4f517be3ce8f258a676f5c3a267bb22dfc56349b07953218cbdb31909e2d921753bf9010001	\\xa2949a071da4bb7f2b91a98240bb5a8ddd9cf92b73325ca3ab194d1eceadafd68b8e03219ed775b94025743d1289d8ce018a6affd034695b583a50e8c7f82a03	1669572940000000	1670177740000000	1733249740000000	1827857740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x7dc73826d504a59f6832e3a2f71a0622342d1793aa1761e4eb71d508307559ccbc4c9ab1b606eb85ccf269d17d288aaf9a6afa6b91ff1fae7d1fdc3913557114	1	0	\\x000000010000000000800003d9dacbe4a5704f45007584bfff5d635c3b63d1f89be22ca45d55ccc3de1631286541e214f74bd81ae9dab7efa2c576c2e3589257c99b9559cea37d037afaa0594da0ac0fcfcbf7dd85192dca4105fed784015d74d662c501d5f3e237e940e6763bfbd75470bdf9710006343f7a5c260cd124532af8776d3519ba326575dfe22d010001	\\x915334ccc8afd88a08e81f207a27935594c7314749e3cd324724b202d3d6950e47fe212e88db4ddc8bd58a0720747e752360f59e5225de64ca97bc1e6e102f0a	1668968440000000	1669573240000000	1732645240000000	1827253240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
380	\\x7e1bb1ea258f7bda1ce44184bff6d17e9fb72c92ba1eb6887f175127b332b444f4b05ff8d9ad94d73956f034ab80e9940cc00cec460cb11166ba68867bcf7d74	1	0	\\x000000010000000000800003e590ffd49576c91555449ffe06c6080201173d4bf1908e277c59e5b2c4cfc5959c8c7193dcb119fa95b30dd44856b4375a8e225b8a3da968aeaed111964b174fd5cf7dc8e3c600e6415e00fb2dd093424586b0c9d9bab0d75c23a126c68e757ffde83ab7e9cc9ec55f76d32c7688fe568e19a8e6960daadeb15b63bfce4a806d010001	\\xba349ec55982721289f6b6491da44275e365c4823d87a80e5c4276440d401348f9ed289a687fb766919929100cfc0b2fee87476bc3041267778415bfcaf10d0c	1684685440000000	1685290240000000	1748362240000000	1842970240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x7f03c7d4feb01bed72614d89b6dfa554a380ae8a251089bdc2e0aa94ee3f7de1b1702e56307940e62d4a6d45805d9568020a0a90584c8bc5b6be3045d29f208c	1	0	\\x000000010000000000800003bd8120e2d49b544ddbc9585384102f3eeec94fd0d253a12f4ea06a24d4bd8f969db9e2b84f0a2a06fa9c71de2732cb2723bb6217469b14e7b5a41646e2a997633f5bdee32320b8f2f404ab652149189fd5df62efb639bb772e18fc904e99b7e98f4d8ea51ef32963f394a0b812483a0999c64d3d89218c7f848282712b701adf010001	\\x578f73abe673d94d6abd9fe39affa23a06d8ad8fc5d079e4eec139d5454db1492fd5f5665007f66259074ccc8a8feef2476ec1330afcb02395c9ce2e2dc29000	1655669440000000	1656274240000000	1719346240000000	1813954240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
382	\\x81fbd59550a66b0fded00df385f6ac876e910de063cb6af8651750f5ffa7768dcb0d8667713359abd51ad991a57e82a3eeb64f186d8ce2de06eb399760987972	1	0	\\x000000010000000000800003cefe2db3c6c783da73e0467be9140fa5787d9341986892f287e86ec4eec20b52cbff7ff88a56da811f0a5623efc6c5bff2186fb50276040fa5e776f30249a747cffae740518a15853a2403fc69f9296403bbab31bdcdc079147e454486c1381bdae6e40f4e9c35871c086f13b0ae82f1a9bfd3e781b886c884b0315545c62c05010001	\\x91fddfe1f68ed23bb758363b928775ad4c064b495c569404ac13ea92ff8caaef62581dda91f59748af1a4c209c276d57e495550711b96c434ed65c7cdf81820d	1662318940000000	1662923740000000	1725995740000000	1820603740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\x849f549605f00be9a99d45d7144f7f40147b9afa64b8f9ddc0aef186cb7352e32ea2d3dcf664600818f8be4a9ef6d1c9904dbe739a6dee1947796cf300bf2d7b	1	0	\\x000000010000000000800003b0bb74093cafe04d4b65cdc60512fa6dc49e567627f9d053fe58fc7de5bc2cb9555951f085366204bcaae9e047f535398f85baf3476040997f24b3709abc244a1dc36cc48406a8b7ff4447d27596cd7856770b4a7e97d23f022f747ba3cdde475e58968d3fb468628bfbfe7e7d6c9976d98efff122e4764cdee081e2004d5ca7010001	\\x2e76a56f0a810167a077bc471adcddeebd015fe787635a4c379d15e14b4b42d70be0c74df8198add2149f4e59b5f42a2fe90b364fc88ca54814a32043e615107	1659296440000000	1659901240000000	1722973240000000	1817581240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
384	\\x89574d00b7b75332f07458a5825c2cafe27bd1fa86235eca5a3a554f69e5a3302d2441cebce7354ba43b11dd1d7d2b6de69b876f517dc1bdeb9043a29c5b9e6f	1	0	\\x000000010000000000800003e0cd47bf0902d14b4f9ed06ce6ce3b364c88f7d2d082186df66656128f9210a0ad7d2ba39f2beb041315823206fe96ec675e3497bb41b6a0f75171b3a8ff4d5e5bf30dc0379b0943f335fec2e438e9844d058c83161f1a082c715251258d327f552c24d8fcf746889883050498e633b4f9df73150cea8b65088bc7c33f83b493010001	\\xd39679492b1fb403a6dfbc543ed91812ff288bf996a8d39a66176be4250b055af4a6a6a2c681288b8222ca459d509781e23a7aa4cfceef96ea240d9426a90609	1667154940000000	1667759740000000	1730831740000000	1825439740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
385	\\x8d03454a4b165fe0c5abac0890e1c888615a334b577d58e5679370a485eb581c6d2806cb7b88df6eb3671f88f4ebc9cb0f549ca7e697d20963a28e5a37219d3c	1	0	\\x000000010000000000800003cddc1ec5004f386736c3708866c5df299f80ca608effbb627fefe9d3ca522998c4ff8c488a4ea8ebb91149b53427fd0e7915ea189e2e4aef3106e1175366af7d343b4424f5a08e123574b77a3dee105eed0377e20ef1c7295d48a0307cb3fef3d33da627b92000dfeec10c15fa5024df9ddee0acd57d4d9d596e739cdc67f23d010001	\\xa04d0580589842093695ee511bfb028c474f8b85bd3ff11e5fbcbbb7af5fe5d6b96e2701f4da6f1dfb78e9ce90e06aaa3a664a291076524cd86bfb54e33e2900	1679849440000000	1680454240000000	1743526240000000	1838134240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\x8dbfa301ba0edf8133f84694f6a22a5eba70111b345fd003a087630249f295ddeba53375de6848c0bfe9d207c27ae79d578229a5b8fd41d0f3c87cfe6b1fc8e1	1	0	\\x000000010000000000800003e84d013e2a8011b49acb68a260e661bc26612149233a3564dc990cf5623280e248878723c1daee073dc0996cf138b4dbff647b0b850b0fedbd46360cb0d16233946f0d0ea26438d77c71c00b09c5a4abac467f74fb5fa9ab3c1f040b1817579008daee493ea24a7851abd0a06e95bb03a6ae72e0db16d52c1aa0ac8d36c6d175010001	\\x8a5f707a18bfcfc4b0e891d1f4470eae9b87cc4746ad70f263be4e3ba138f051ad3a1e648362dcf29a65a493dcc7af06694a935e6739c05ce1cc9da8e5e5ca03	1667154940000000	1667759740000000	1730831740000000	1825439740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x90371d13264ef2ffd6fb3b9d19e01056bc5670733947557e589bbfcabb334a1d6426bc1f320f060a2128fc7b5f2ee3861b2fc060d44416c016266e8770bb00ea	1	0	\\x000000010000000000800003d21a760e41fa608a2f7923731a2615a068eed73ac15bd1e9ce305ad64c7fd493b6a972e0e2529abb8aacbe0e1295053e1ff890fe4abd5c45f0e4867e3f15b1558e637f9ad5428964fea9aab06cad563b2fd1af46e76b427ed84b35699e78f25ba7a1201fd80d5e08a440ec0b4e7aee019a9577bbb0502b96521ada322fa869ab010001	\\x1c99c53e9c46a37b0ef4e8c3e7c6c779f5d778fda1808b53a4be7ba377027c6633d8ebbf717beef5936f103cd7d1179d039dfad031732f8bebe0e4d6a07bf00b	1678035940000000	1678640740000000	1741712740000000	1836320740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
388	\\x968b216a0752076ff6208f294c242c1285f10a3305267420090b217148621b952196f58f526e5f7288ebec4d44ef38ae6bba1fa8da272a2bfb68aa53e3372bae	1	0	\\x000000010000000000800003dcb4ab220b43ea18f985898f9fa7d161c8ab8f972234a6d12d1fbe609e5a659636db59a0094c4bddb828f61b0e69c43bebffad55025afb77ce54106cfa617bdccc61f4a8d0f85932e02358373351ef8b1e73abc1e1663fbcb12c1a68b4f8532b8cd117e79d0a07235f11e5d697f31adf7dbd045c8e7a7cdd2d1b47d52dc2f493010001	\\x2a4850c2bccab93eb08d09038874f8b249ad88ff7bc7f3f0fd2e7ae35c79ac4890433ae87187577a36c03cac7d29dcd3e20adbbfe260724eab885a7fc298b400	1670781940000000	1671386740000000	1734458740000000	1829066740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
389	\\x99ff2a1274b8195717f9e7375856ef905ad4a226fe974f58304064438dc027bb8d6f6471c7cc4a89e5245edbde3325827d9c7961ae4485bd036eccb6ce1dce5d	1	0	\\x000000010000000000800003aa9d3ad245fe06c244a12335e2fc35e5fcd1d751981ed9c07c53713619d66a2b2d291e803cc84eeeb87335179e97fef74c246022ef793dabe227429a2ce807c1971e4bbd392ecbe0c6ce17fd8c303ce86990729cb7e3bbc6a6fc071dd3dd148e58e6c0efb1eb674269522a45df7ab01c82c264ebbcba5926f250fb1dbe60923f010001	\\x4b7b76741650cbefd826a38b1c9d29232335ed1107255ebda0daca140440c09e17b3306b581ffbc65213aa9c53b6f7e089b3d2190b206dfc02f90cfdc9ff0800	1664736940000000	1665341740000000	1728413740000000	1823021740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
390	\\x99a74b294b92fa3cc7a2b0ebf628cc0907c8c852c58d12e8ebb2fd36a9b5934330fdf1b847c6d370f5f133bab718f6ddd5e09dec467e9e040593f97badeafa19	1	0	\\x000000010000000000800003cee6da9af5d66636631b84aa6d6ef17291cef2025c13a63265db7889bbdd775617f376b283da7a1c3bfb3f77e9f752f8d72aa5ea223a7b90815f8f86debe92dff362940dfa65d1d69f773e67681c53d89d05dc7082dade6eac0af3e986260e1ce7143fdb06f35e635237406321f770b4cb32b8ce8bee9a79b322f3b6dd2b1f53010001	\\xdce38f25ddcb39917160ac3fc705019e46fb400a051b129f7c09ac0f62a96f065cae23b4aacc2c2d6817a716daf2c9e8b84bf33ac0fcc2383ba0a6c33eb98908	1679849440000000	1680454240000000	1743526240000000	1838134240000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
391	\\x9aff71226c30fdaa1a8e3583484cbf1a2fb2595f8ad8bc87747022572d3e43b524a9224b7bb5db855955905ada3c2c4a79057d94258565a19ac141bfd50e33fe	1	0	\\x000000010000000000800003c4ab2767d94f19935124c119372bb39e9384a05ff17f878dea66fb8d13320ee8691a75bbd60cfce9b27b4688e9e9aabb630332526c38d589ca716f19890b71b4b5f8798ca1362c9ff16f1adc00c7c02c033fdb4a8570531526af7bf526c172e8ff7ab052072a7209ac71db8cd34bff579ada76f71cebe5c8cfee251fee97860b010001	\\x15d0f47aeaf2c392fa77106a16156fa5ba295b1a89ac7c87d6b21e455f5474ff458017fc8ce5c975a3c970d2932f9c49529e4dcb55053079f9f4238737612302	1656273940000000	1656878740000000	1719950740000000	1814558740000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\x9bcbc083660bf12070fc87eb738d61ff3f7e728fcd8595320edf789cc77bf2d612e2b93935c7dfc89e954fe92272ffdb50a01e28445fa581091204fd0d4e7bd1	1	0	\\x000000010000000000800003a3db67d77d8197ae6967a1fafc9c8c6b39178978b249743745bcdfa1f4f083cc1bc0715f344f12d0e53a628f73b3346bcf338c3e076a6b169a5156e1a0b493e5124f6371c564b11ca0f4dd59657a31cbab4fd66e01ce513c606e75f9bc6e0ad81e5bc04067b1afcd62f65dc3f7078df835baf4b7b079d867af7c189358539add010001	\\x236308dddb3b910cadcae04ee2f9d4855f8205ef445d77d4c11d2d19b48f4d53a0354ebb53ab57bd8c71f3d8c0b687a2aa88ff0442a67424f00a93fd37d4b80f	1664132440000000	1664737240000000	1727809240000000	1822417240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
393	\\x9f8bd4d87104556aef0a78fcfca4529335708d08d14068159ed288144e66d460ef0858ab1e0aff99936e1c39206dd75e7f5869a1a5ebf730dcb37f4f5acc82cf	1	0	\\x000000010000000000800003e0468dedc04f39c141fe5a7b890c00c55b386f0ea67eb8f45580418fbb2fab7ccdc42578a09fe8b9ab90abbb4f030563eb898e8dd5b9b8ee89cb76f266054e2248d67c1ebee2022902fcb0b2d099395b968cd8e0d2c9642af33bb173959f4a7a1505c053ff494fddd7611788a0ffffedd906d4f455561c3d96f5a3814a7d4887010001	\\xc679942351809a2e3b8916943405e1374172ffe08baaf521ddc24ca810fb995a881373f868b7a1eca5ac85757a5c3994a7b4937a9f91b6d659b64099cdf6a507	1678640440000000	1679245240000000	1742317240000000	1836925240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xa2f338442b09ca1fdda5d8c9881118a2fd5716492caa9f5d37ccf4641841c6d11851dd1c5246fc3df5eae9f82c1a14601406a65126ee3a11b8ebddd4bb50fda4	1	0	\\x000000010000000000800003b915c7d7f3bbd6cfce0f04839a9af1c1e97f7ecf69865afd7ed0404b04b269ac282a87766cff58cc75b6909a306e46ec8a2d61e676ebed296ba660701c202823c8098b65d111ca939d8fb27786c1ae6fed116f78b3e9190c4c7306963b1d0399df3ca70a6d909f3331df4170cb94d19c8e7753ffa9970ceba6e8d81f9340587b010001	\\x24d8b501ded3bd8218dbe4cefc07b7cee98056094a26924a0de38b4e089ace2bedce97dc83d003e518910c83f6ebcd61d384b85b6b30671f2c924ea960432c0f	1656273940000000	1656878740000000	1719950740000000	1814558740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
395	\\xa4034a87acbe34e7a4e960a02a7e9cd0e137394726c8138497089c3f037bba607b280da1a4bfe2c05bc4a6f12a04423fc63e1e46795984ba6c0bfdb002e0451b	1	0	\\x000000010000000000800003a9cb13918ad78f8034ccc8536b42b40587a82d6c97f5bfb30142c70fb5021e6d1d6ec2d7f7a64edb1062a51e0cf74b57120b9d0785c0a3d7df2ed0a28e52b45dfd57b08107d7fe58a334a58182aac0af69812ed7d4e848bb5a380a073aca50aea8655546bd96457e4f1b3bd0067839771e23c543556520b6ee7fda1d5ed74cd5010001	\\x8dadc74b0d015ed14101d0db49453ca6b765f1511953a36140fe9ecdade80df926cda148038a4a3cb002db094a13021927b3a6aec4924db677ebf25f0041f007	1661714440000000	1662319240000000	1725391240000000	1819999240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
396	\\xa6f7bd0937c2099689b3d7cc373cdb09df558dc666d4f00ddac39a2505bdbfd0222671506eefb359b3213a0b9ddb0042232427b4e131e007092328c609791ed9	1	0	\\x000000010000000000800003c5381f654c06a08fd179d4fed9e55b33d5410bb76a07a893efbb92a76ca92dbf438c9b1eac52a0ae7230228c24b47322104719a38a0c44a0508a1420a5fc5f73187f52f4e8cc2087d31e7f60f02fe6d9f9c5df013d4de5b3b27007f0e3411ec94da39aa3356e931d88f124f3ed98a3f7746f890f54ef9bbed124b9b9b2224949010001	\\xbacf35ce55e73d4e4c27fd68ff634f03770f84b9db9f706d444becaa6e89c4ce2cb9fd442fb5cc67fa38aaf498a445c955accd9795deea893d34767f44efcb05	1664736940000000	1665341740000000	1728413740000000	1823021740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xa8abf912d6fbac0107855f80e7818581463f9d9b3eedc4004379b97135b2ae39389d7704cd67ad694e1ad491741d6aa6fd80c28feb266ba57711f3cfd85449e7	1	0	\\x000000010000000000800003cc8e0c319e97c58edaefbb3183e811ef8f5ba4d2a4559b4ba7dd1a79005dc7393112c702763ef8bcd16ee0abfc80f88c8f5ac2facdb1db7f04c4622fe0fd65cc76439c8547ae52ca3d69ee30a1898cbcc3eade94884216620f58bd98bebe15fed78fe0bb550d4868f45573850ab9ceab1e07136c752293a6489e0c4b1c21a4eb010001	\\xb8b1ff76036828d0326186dc9d8430602472e1d005b9b4d77c266498e87b041f4f48ddc9da03c4fca8059f031702b98cf6f96184c864bdeaadb9c2ad420b1b00	1681058440000000	1681663240000000	1744735240000000	1839343240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
398	\\xa9ffa18d3cd42fcb19593c948a30c93124df9ab75c30cfdc3b5947ceec233c259cb1b7faf2bd85d5b06a8bc917ac7f4c8997c1e26d575c514dc82c5ebb2834cf	1	0	\\x000000010000000000800003a7848628208bf5ee4ac95b827b3d9dfc0a42be81da33f095187d4970ce3bb7a18a9c5b542a754ad628d032125502c49284c8dd5579cb34805b73a559fecd4de8ce064122495b0b63bdc19c2c17ee5d546089aae4ee2ed7eb65da1e3aeec22c1aa035a70c35fa113633729f2639dae3404997ab5ce6e9cd42dfc43656e29257a7010001	\\xf3c5b9b490d591d85227ffbbd15de9363f47b460fea9bf4cf60732703b084b0c0a098d54ece3cca3e580ff47befc768204d55dd00c2490c283d6437d5806b806	1658691940000000	1659296740000000	1722368740000000	1816976740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xaa8369e2fcef79110935780a33da7cf2d61b2bdb1972415012d4bfb67f74617f402ec74fd958958bbd03300f7d1b5316549b97f71f47c6bc3b0b0e99a225c3fc	1	0	\\x00000001000000000080000396918f3246873d78fdd7a891c5945ee706da725cc0f502c1ed66a249b93933153f843fd04abb37b68aa78a4584217a25f5a919f0333e541ae348c75e171b037678bbccc4489f1bb43293f0a12db68ed978cc0bcb60ac3be9b47a29b518c6c22862d3c1f928832cdb491cfd0cb635d0eb0c76d446785e7104f10601faabcb5677010001	\\xcb709d0f599f1857a8c72dd11007ebbedd5c63e66208d100cc851162b11b0a0250a7377c723249c6a4fcec326792ea2aef666e8123e278c9ae0c380c506d5607	1664736940000000	1665341740000000	1728413740000000	1823021740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xaddf3c889f778004cb021b16a1092dc4df625359221bb34f36c0dba764f53f62e3838a9cbc218832c9211e20d010fcaa1349040f7f3fe4b5fc3f255c82faa1c8	1	0	\\x000000010000000000800003ba4e0a12fc2a4db8146dd5429ab33b5852e28133444c5b89c2d53188a5a673f17010fa348afa0f8653c9e004b13f8597537b16d68d50058992691d3731706496bbf4c89e86f877b8d0138a70ce642db0508fdbfb49275a0f119470369fb683e5c4dd7d80c5f2e7aed41b2212d379ede549474451cc0169656dbe554ba1b60bad010001	\\x6859afd17e45360734e1afdf0831c4e64fc4599521383a738f44cf312116c44d29209fdadb120685f851aaa2cb900da56dc8e075b1ebdaa7b0d54f3bbcbdad05	1682871940000000	1683476740000000	1746548740000000	1841156740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
401	\\xb2cfdb82c53beac1af287d0efa17fc3b901a2ccb5f2043f6df2190036c797da1717f2a2b0b8c1f2d11589f2d60628d9b33ee91979025f3e8b12ce09395a71a2b	1	0	\\x000000010000000000800003b67f3fc7cc0b25708d24a03ae5273d06c28ce3cb325913a220ad2b0aac39e862bc48c63b7c6927e56962120a68f20604c31bd601ab013b8b7db554de0c2926072af82ce829183142a074fb6e214a644e52fb8165e5ea106a6b0e76ec9dbc0c7eecaac1f01e77e77a9450f9bf9f2d2742c41a4cf51481471317fa215335db6cf9010001	\\x020bc69dceb9b02a1f5836b9fd455de7ebb5be0e3c5deb5b60db8e245e666ecb5c5db3c39689aa8732346826620c9268083ffcc4ef0d64b42aa34faa8559be02	1655064940000000	1655669740000000	1718741740000000	1813349740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xb30f9bae4a2f90419025c84df8dbedbe0860b2708dc77b23fdc3e5af46454d8430c5a9586eeeddcde3221928c23a4f89bc6d8bb70c2b62e3272262f3cf6aa23c	1	0	\\x000000010000000000800003c3dca3f009ee48039d2ec575024b2ba830f09869fdd37f1263633c0402fb22ab25c3bb09648a1e24e02ec69a7cb4e323fc08829408eaa7b2dd33aa3e795c10a22396e5e9b54f64bf505b52869f932949713dd9d4b7abcc144b04fb8d36b0ce00bc73ebd507f264a0ec860f907a637421a813053761b32b7541786c371e18a319010001	\\x1448fa6421b15bb5c5096453fe8a3145d14e415d88f7756f9db60811ce7a32e7dda91fdaec311ecbb1b60d4d2275a49d95d8d1bd99115e580b6977e60a4f3f0f	1669572940000000	1670177740000000	1733249740000000	1827857740000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xb3b38b5bd1359f700b9bc10de74726664a8f4f9b2d14881ec2065062d26927fd5fb8d8dfeb817726d41247e23f6450d218684fb2303e5ea5388abccf6fc62ce0	1	0	\\x000000010000000000800003bfb05071a2bda6477cc01d121e46d7cd5026b1f30b256e282fda306bf6f7ca3c2efcb5ddc61ebc71de62371f84a6f0143725fd2189d08265c07e49579c643d17085e014371e03dfeaccfdd34989e5dc4de382cbf6924b40aa3d19af055a9544d52579f796b14ab0623e300cace8793adefe772f6be24d79c14cf75ed8ab40de5010001	\\x51513121aa410b9c1637096353171870639771583e31e9dcc6c03a8567b1500cdf0ecd0b5b70567966b6dbb68763cc52ec1c1990cb9e88ad7c03e4ee3fad0909	1666550440000000	1667155240000000	1730227240000000	1824835240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xb5a76f703fc96f6956264014641857984938d8ae4d16754e49fe2f3a720b94f451588411c3d1a8150dbeb682682e3d4bdfe3df96a69b82335ab47698a3eae948	1	0	\\x000000010000000000800003d834079f2134e6ecfb61840eb751d40f26bad5d42be93d296c5ddf61527b45781c45f967dc0d9266c3b57bf6f996be2fdad610c840dcfccef562ffcf61ffd7eae9a69f5bd298baa3b7255a49b6ba431deb29ea92902e0474c07b29c2cc1b4662ac0122dddfa91d9cf6bb86f13c19320313235958927cc519c3a07c66336d5ad3010001	\\xa3096f6b78a1dbfd4c9ca61cdfd8d012a087fc263cc83ca52f9e2f8cd1ff946059801a178a0595840adf46340f683ca325b13e2ea4aaf3c248d4af4237bdee02	1682267440000000	1682872240000000	1745944240000000	1840552240000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
405	\\xb6dbcde88b049a1a42e0ae44203c83d0592dea9eaee3050233ac39bc269caeedd3bca7f5890e56275596e3b87fe6f7650803b083e3e0eaebce3e60313e5c7962	1	0	\\x000000010000000000800003c071a77d193b21de8452b4fd25ec23e7c460b98e93309a0515256d7db4e11ec433a05215decf410669a4d300d85b8b0c5dfc9864adf7f2048827d998e19cb20fe1071ee8698c1098fc45e5561bf5fc9acd7cc082afe921b1102de07345ec5fa9f8c0ae3fcf478e5d311c4b3df7fcb97f7bde269bc231415d81848aa7b5889615010001	\\x1b83f22e8b7d51c125c568be6f2acb09a714be3027336cdbb87f6928361aa7699acebe2087bacf6748227414d1466e21cfefad6dd2ab4d1c01058d1f230f9e06	1675013440000000	1675618240000000	1738690240000000	1833298240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xc483a3c3533f62ad4bc45826f7f84c3a3d80e662095d4b37b02526c55a4af5058f2fcd967493011c00acfb12700a4ec471ccdbf1316941f8d3f9ff4af8f0ddff	1	0	\\x000000010000000000800003f4f540bbb243afcc853847d47649bc9e4b2e9e2581acfc99a1d5c25388d049a959b211964e33e98446c9c06973029a85eece0283dac0cb12eec9a7d1512bfb034ffbd750772e1fc658d5dbbe85857f6c01e2feebc75c7589a2ae37aaaceb41844ec358e9457b2ad4bb3b6e55c45e6492ffb6b45f95e048549c06c9305dd24daf010001	\\xed51a0d40a1284c1bc20483fcdb61123d4ead88ff3acb200176bcbf5d31c71ae6d6cb684404762a87ee913595cf32e34b051636e710785e036a984c18619b508	1658691940000000	1659296740000000	1722368740000000	1816976740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
407	\\xc6ff225c5f065837c6bf3b5ac41cb6146aa19aa8ddf1517a8d1c8504a43cca40dc76dc3e3ad1bc7c6d09c9566e20edf0e4434b7b23e81f0ca8201ca64665cfed	1	0	\\x0000000100000000008000039c988371aab9aeaa527c97db96af041adf29fbd8ee4f29f317cf040aabbef9ba55d07727e605074c486a0bcd8c427dfbaf3ca233a86b7fb38801e20f77e4f152ce4096aff1e3569c9b73c0944a8406c55cc8806eaa58cacbf8f6744deecff46e5d9d43ec5686a121470cfd7a95aa214629d7974e3ddcdfc27719c8aba839199b010001	\\xc8d21d10b0d9e49fbaf809de41ef91a9e192c38a9128fab878cd8d2c8a99ca49fb28ec3de1a54248f12d1ae6743de768b5e1faa3ba1b57e89d7c92ac2514a306	1660505440000000	1661110240000000	1724182240000000	1818790240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xcb5bdd3a68d92c9df96e5a657d7df29e65dc3a121849c2a06fe709d85fcffdc21a59a6c50335b5e6dc8b22774e197e106a20848a9207d037a76188959d018e25	1	0	\\x000000010000000000800003a8d184da98732c81c960a0b6e7c041c80fafd26263250a54cebbf1a6bfd5e977bba43f38c032493958288047b97b85cc746c89b992bf93abd78d52b033ef7ce3b112df8b6711276af42bfcefdc8338343bcea26265597bae54a670269f6f7bf0689881facd5ee8bf691bc5e0fd4985e3b6c1d9010e2cc24c282da8114e3ad037010001	\\x6ed66604fca45f2785aade9c858f2641fe87ebc9a586866c38a1d6d75e54b04835c03ce1bb61877443f30167ea5527ebf14ee4f2eb30f73a1a6884eb8c48400b	1656878440000000	1657483240000000	1720555240000000	1815163240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xcc9f2ebb0770b1d1e0e956ecf55eb47b1a7fc7e5cb9468d2e25cd60a2a45b87df5b6fcc315a4825b5a19df435c3cfb80826205ed01af6da79384c2f48b146631	1	0	\\x000000010000000000800003c0561c77de690f5e3ff4429c75fb0e3764cc75fdcbbbd6db7b2573fe1277b722a61925b52636a29188a91d103a5e0aa912e3577b4a13aac8b9f8f2e461f3956cbac5792c9a6d77986ab7e546d18253b3da2b1b21dd24d50dbeff2ed127212a4dfc23d09cb3478d0a3ec070a32d264bfabb5beada8011abb7192fd74e366c25c3010001	\\x87a9bbb4e80fc7c52de6569fd7fcf46c509107f1304a052954e74a461c6ab8e60df3a2f0e0b6e16b8de21b417be6e3d33de264eea9d4e0ccccb0dbc52d052a07	1658691940000000	1659296740000000	1722368740000000	1816976740000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
410	\\xd4576fa90fc861b7dbbaeac8c971dbcb9d0d8cfc7ec9541403334535ebd1c1bf72359c4313eeb09b073f3a2e1c24f4d886a06abd8e137f2990d5b091001b25c3	1	0	\\x000000010000000000800003ed0f57a7c4af0aa4f1a598fd0c35822b3a2c64f7115419a8ce2637e98a753503b375247a5026e5390a548b66d5f556ea261e4349628c65a1ae0d6891e09051d572a34c5fae1287aceef2f797c58b9c2b26e7c3ccd1717eb4a9f9be8dfc8d518fa384457e3a78b298a073ca809b4803258d276398bef91a53789288b2e44ee429010001	\\x284fcb2d2f73e64beca0cf595078149ada4ca1bff792a49430adb629ac9de1c4e1874f475f1235681e16ba2983f9f50ff496fa293c92c191b9559b31edd49d08	1685289940000000	1685894740000000	1748966740000000	1843574740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
411	\\xd67fedd011a376eec07987bacbd4eed539abee28585020bfbefe8aab58ea2d703c23f080da50158200a9b3b9f3470740b8041002ae21f655e98830a7b8a4c3e6	1	0	\\x000000010000000000800003a9b2857e50c5f7d1bb737779cd698c51696295c3408727f6e44fcc05eb98e4e03e3308c68b25e73acaad37a409c5a327c43fcc53946c6fad01e34cd4787b1712af730507d32eb3be5c6e6cb12e4504387dc2c7b01a2ebd59db29e08a712b5ba798c7d926c49651645b0286456d214e309d1b7b20116b11aab2617e28248a7591010001	\\xb70258dd6c6dba1d943b429e48c021fa3d844c3653b90efa327d549c63c9e3215a93fad4e68656dcecbccc8588844daeec7b1c186f96c3ca5c9d53c35c9bde01	1676826940000000	1677431740000000	1740503740000000	1835111740000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
412	\\xd7e7fc6c57afc896394c033ec55cd882ad1b778a86f2bdf8a3af9e8c36a5ba8b47299231e9b28bbd5fb7fbcca5b1a794ffe0d1dfae77bc96684039a7e8ec1565	1	0	\\x000000010000000000800003fe42b6941b98de5c8c9d1959f881dfedc18ab3475eb87d9f5e65fdfd3129351f1562296734326fd578ac2fab8ccedd0ad47b10dc6190c48e25b8c795b0f2c9daf9b5262bbbadcb61772c610f42b27fcc404300ea15c0e9a46a4a07b4d8f891aa2a72b4af828712aed43c39d64cf738c60bd37dd599440e9aecd7412b3e886f67010001	\\x9e64f704197666d671ecd37e90ec8cd93dd1a555471ed24cafc2b81d932607123c43762a515571d27b1467e43ab39edc23f703c6a07866dd14d89fb2ec35090c	1686498940000000	1687103740000000	1750175740000000	1844783740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
413	\\xd9d3b3daaa17f8942be6b286e06f9f99ff3859bd23a6b6b32651e3def347e115bf12c95139822b36539313f350bc0f57c26fe2dc9b1ac3bcf24e29dfe5428900	1	0	\\x000000010000000000800003da0231663a899cabb695c594359c0170801bfb2d2978cd44007b491f6f2347989f5a425c3e10d8c2476ea7f4d55786954dff2a3a7dbd7a75899f87affc952cb9b77d59a61008a0794eed8ad2bd41360ce358cfcfbb556aaf5da32c840e2e625c13c23f6aedf8ec5d71cb9a4d3235c95a2b65a647ed4376b80553a3a4449b83f5010001	\\x1400d22e2a9d672b119a3db443838a8ec43eb7404b272f4e7fdd2e95738e75f2a7870455bed5308ec161f5d4e48e26ff363e2a88afe89d3aa361868fcb134509	1673804440000000	1674409240000000	1737481240000000	1832089240000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
414	\\xdea37111eef3dee11111eebc601fcefdaca51834fe5cc33ae2391a75b4c768ab67f2a398ba6a071a9c06ffc73b69e459ba48916841b60663d9f06d4ef7f6685f	1	0	\\x000000010000000000800003cdc70067b3f90a43681043e800bcbbc5acd1a00d678f1316cc953a8dff4287631b4a315ed6eb02b15ade9b17f526e0c444be31aee4a2f9f67ff7ec8aff5408f0cc1683ff1c99286e219988029befbc7127256de4ae7643edbd4a8c2d33b303f3a22aabec5f3554e42cc9a6ace85027a93d3d1fb76a65eddedc66e897fad61d2b010001	\\xd64aa0cdfd066647c80cf154b9098d90b4a9af34a2e1bcc9887b8ac0e234411368ea01cc2994c18b3435a8a9a316fc9d282d5dd841d2618d33cf807566791206	1685894440000000	1686499240000000	1749571240000000	1844179240000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xe3c3e52b31946267f8cf883871f5e717e47961418fd213f80fc3ef2d1d8fbc4bfe84bdcf655cd764639d9ceebe4cb11236fc0d50b1aff7ba417c9045930860a5	1	0	\\x00000001000000000080000393e3465bc3cc0e3dbb00eb054e7715dc5627885652d98733bddffbd960681e66f179f0ddc56d8ff5e8cd12a38e0459935c0a71f29158bb821e8e300d265a468e1543835ae66fe06417bc551ce015b7a2b1477c159b5b2d1407038abb674706c22cb8a0c595bb8d71655e3c8b2902a5f2f20d7d320a04544d262822d2cb38c42f010001	\\xe8eb113e82bc48d3775e942a648712d4cf3b3afc2c3e507a08bfb0c31019ab9e8938b6c8c421ebf0ce915c003fe11a5d88c6055c36de3116d98e803a320abe07	1673804440000000	1674409240000000	1737481240000000	1832089240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
416	\\xe3173fcb58e5cda44b52ee6227480e2c8dbc3363a8823f3c1e077d7280fa2d5b7428ea493757c89ea1159538a564f94a5e05efc5399352dbd65702ff9a7ab813	1	0	\\x000000010000000000800003d1065edbdcb43baf4a308d7110389fe7bedd2607fa55c0b2c0d40caf8e9c34f380764b95e1253f8c6cf758fe6eb27a50add71707af99d61c71205aab6fab8730039ade4c8f2003577833c54062bb19f7154e0c4ee37708dbbdb41cfd9221037f1ae5ce108296db7c0064b599ed4cadb5b691fce58485818fa187f1caeb4cbcf1010001	\\x37a18a3715f438b3221557b59924702be73e9acf0d28b0d84d9e1e40bd167e8b08652a9af45b56d76070fbde47047b3183337d624683c398283165c02c7da80f	1685894440000000	1686499240000000	1749571240000000	1844179240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xeb9331c38b0a03047ad51ed6f0e3e965eb62120343b01c9dd7e5cffd13130eaebfaf050fba380fb96d476b0e6b1cb49a251d092f04c7df41328cb1af388680f1	1	0	\\x000000010000000000800003b1b901b9bf0f000a4da196fd523ce1a68d5081526083a2b3e792ea8daea9599d890f7657712353fabd7b89abd2a8340f17fde55856f12fec5aeb98f40409b39fe470b2d7d6feddcde4df72b8917478e83cf2dc0235768abf5a4b53791aeb207e5c3884b4a9f42eceb7b8d489cfafa9ab4cc9a384a37415f91a9797e123331029010001	\\x00e46ac18a8bbea7d2b79a3bc28bcee2c1784940ef371aaeabee5bae9c37a67be8f91124e4311361e2ef5ad449ab112914833664a04d47057100986ff48ab309	1681662940000000	1682267740000000	1745339740000000	1839947740000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xecab2b74f636c86622aaeba120b97d0092590a5255dd1aefed8424e326dd24d5feec53ce19266246dc2b343bb2a56aa4dbae15f0f9ba5f9390990b7cacdf690b	1	0	\\x000000010000000000800003c14a29e1741fae923e3e58829f2d50de1ba7043efe48f4b47501ec159d71a8535e6eba1df80e64b9b94615d3a69a825f8cd347a2f614d69613002b88fdb88d04a0bf86760b41dccfe5446d60ad4adf722a734e0ae145e69515362b17bc553bfec8a8d69b7d5fef18bdc193283d0d7d4b3cc0964a1eccbe48152d3575c57ca38f010001	\\x3c8c5b7e2c58d4469319a01ebaaf502d87daf4bff8d490cf59efac9208f5ebdc6761f6218150927a2bb761207ace84f28b9e1a278bdabd5a8fa273b88e8c6309	1661109940000000	1661714740000000	1724786740000000	1819394740000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
419	\\xef13e53504479886812f002eee6ce60f4dff18c4a7b0a334d690c1c81898899629702b2b81df0572de2b7f8c843be673c3036f1cb1e76d32ca1e8e3e259c713e	1	0	\\x000000010000000000800003df641bd45b2237e5ecc5b8356e64440a049093d70654eccfe1201b070811ae83f67710ba7b365ae00a3d64b3c99e3ead502b4e14415342a2607a7995e9f083559007fcd9267183c925a01ec94b27ec865e97e94080e9bcee66e35b6b7edd06772d212b50852f7817272d6bbc0098c07d294d2d92af9763a3a766b234522e8acd010001	\\xf8026a5de8850663cd8cd0697772b4a260e91fa8b67161178f7aecfbe1a26d4a58dd57f2d21ae30d1d426bdf15cf626c5cce8e953f88440cfe18ecf6f556300c	1657482940000000	1658087740000000	1721159740000000	1815767740000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf17ba4f9dc211f0e068d969bf7081ff409bdfcb498bbe4149c12d88974af21237e0aa8c23134d9de9bfde6a63bb5a719b1893c4ef68e48c5620efd0ef6d64ddf	1	0	\\x000000010000000000800003db47ebec6833d81572922ace01d495f6fcbbca3cafdfa2d91201ea52c030f00d9312fe84077b8af03cb810e38e4d7d8edeac960cdfca84b47d51eadeecbcc046fde4be9cd7cea44a86c51391f7df3040ccc83c56a1399288e3c112a344105c8d759e19eba5bbeafb58a82882452d3e35c2b4adbd9f7c0e7ba49a894ba1f3ef25010001	\\x2a2bdba540b94d81a95ba5e7c1f3dcdfa9e4feb96b92a3fe97280453df12f860a6854b24bd82af6296e688dac5c1504fc074e5a00e17e843becd69f9d2a7db08	1679849440000000	1680454240000000	1743526240000000	1838134240000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
421	\\xf133f06963f4cb5f39d97c8ba1fa9f420d07da7862607ff26c537b00459af862566a9302c126431856e4f78494ee82895aa774e284406057e13f174335fcdbd0	1	0	\\x000000010000000000800003aff71f25a3405f14883d9af75d1673ec5fdfe109065e338a0c565da37cb54eb4bcd0ff72319d346f7eb3a31bb4fe38a5f63bfd37f157659f5632eb2ab89d63a1ddac210778e1aeb6e7561b496b7e63dc4a7c0ab69a8bcc58e24dcba54f5b0487b8cc7435170b918dab41d17a0565e7b50c62d50d2b17328f8e915f62ba821ef7010001	\\xb44f57de369d743cceeb9cae89637bd580f7aab38d5976b664d6cc2321ccabf6a0f1bca3afdda5bb1d3e88e6b11ab34d2c297651781e4c565fe22f0f5033600d	1673199940000000	1673804740000000	1736876740000000	1831484740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf2c30436111200512154684154ab6e435dbbd04771c904fc5a508e41fa44b9c7605be81eadece8eb3e259719adfc04e6ed00ce60766cdc836c4c1032f03a4869	1	0	\\x000000010000000000800003d56646f10ac25428f4c08e84fc2564eb608994768f6cfcf85a92309c13fe6115fd201a2d768368a726dd29925938bec8feb312a3e4047cc3020c726506feb1053e9bd972f1d332a9ac1cc47eafacb420a3332c3253e4742bc46bd04ef95e609b5f65c259009eeec50657a662233301223a011a3a28a06e7b3b9b8b5b3f63a88d010001	\\x739294c724742ef91df19a2c91d91f020dd8b435a5c20aa9834caf98cc0b9575ac46c55174ae6324da494bcf006ef5b8c5386ebb9b75e3578b73d3288419a50e	1668363940000000	1668968740000000	1732040740000000	1826648740000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xf8778c950442eef8da5035b4cda323659367d1d09d847272310a9eb5eaa31da05f096980717f618af9312199222679c9853415c05e8e2128d5526ccd6e52f9fa	1	0	\\x000000010000000000800003c4e6c48e45e0d5ea0cfa26bc3569da63a61da01b3e4d2aba88fc729bdf4c6b473dc3f7e98375029eee538e5c343e12af2e7d36e7751163a9693d80b55ff4ae332ec4e738056f7c73572737a13e45a72b60d3b5c7bcb5a9eb368f5146cfa951f1b7597d4762f3115294beb656adeefc6b3a57112f3bf80400676d1f163b5ae0d7010001	\\x21b880721a9a82cd7ddca97043772afd1e4c172a58dc7df0f934f67a118c411d1354baa41e81474a6cca590c3403e3b7d203cf01a414806c8b37c4b0450dd20f	1677431440000000	1678036240000000	1741108240000000	1835716240000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xfa87d2ccac7f2ea27abdd3d5b5ab647e7885c5da97ff6a3106b7f42bb719fd18f299f1d0d9571a1ba9eae809a05d5a25c8fc1230c0eeed959dc21bee90a36849	1	0	\\x000000010000000000800003a99e11d3a5627c23c4d01da7204bdfaae4c2542eb6a1bdb6d17f20793490014c2529a06d94de6f27a247a3178fbdd5f2818a87a04dc545becade0c9dc89f9e20eeb947b144324d7ab5a8b39fdb678011e2793613131017d138466fd0e7f36170c14aaabcd53bea5fe67cc8727aaef8cb31e7c513e920ac8b2c46a31cc064f1eb010001	\\x63fc20d030452d444d0482785844a215a8ef1667be92352039fca3bc8022f3bdd54d117aa57d743bac60901d18d951288d5cb0eefb971cec578251ebe27db008	1655669440000000	1656274240000000	1719346240000000	1813954240000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	1	\\x749f73a8d4e47333154e062d54af7145a261a236f12adc6f0cd1b4ae80e259fc41655fcd244cb0f8b540e19a2e8145cf9c04e4b7d93913186d19c1f58d5e4d23	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x96ad0ed376d39a43823a5af00599afe118f13477bc1a29ccce34eb3e8c437fefc8f05335ab4f8e9157a267ff252f073ee0c586962722fef28a43c2023a4f1b6b	1655064958000000	1655065856000000	1655065856000000	3	98000000	\\x981a86309366e8106ffdf1065fa3381a2e45621a71ceeb9c4afab5fc65257d37	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\xdc1604382c668d6f0f1c19fbc36833dba6057fc787da4f7447d4037fa68f9cacf7b697addeb343de36ee66236c8579862ce81faa65d57df873b5146800123a09	\\x7b26ca8028c88ef1e347d0991a892e0ee425f93fc78cfe6fd3d838e0f4e0b8af	\\xd09b5c76fe7f00001df972ff915500000dfc5c01925500006afb5c019255000050fb5c019255000054fb5c0192550000407f5c01925500000000000000000000
\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	2	\\xed6a00c1a8c0d49b4528de3075575eeb2a2a22795f1ad64d08ea4fcafa855e358fafd681c7074eb66198313563d1114752e0d9d6e8fc19315c522926fd0235eb	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x96ad0ed376d39a43823a5af00599afe118f13477bc1a29ccce34eb3e8c437fefc8f05335ab4f8e9157a267ff252f073ee0c586962722fef28a43c2023a4f1b6b	1655064965000000	1655065863000000	1655065863000000	6	99000000	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\x183f9206f9927dc6adc6e39ccf6b2b512a66e9e6392eb289224189ad88b0dbeb658f6cde7308c3eb009ad22f5f1c4df9df17112a5340ea2ca1e1feb75d43cd0e	\\x7b26ca8028c88ef1e347d0991a892e0ee425f93fc78cfe6fd3d838e0f4e0b8af	\\xd09b5c76fe7f00001df972ff915500002dbc5d01925500008abb5d019255000070bb5d019255000074bb5d0192550000e0df5c01925500000000000000000000
\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	3	\\x1476339963899c7ff99bd3bb9dd1d55d5113a685cc5042fa490d72173c8f3e45457c4b9c93429ad40c688d177897ad44074490cd9fd3b0d8c8f5beeab7d674b7	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x96ad0ed376d39a43823a5af00599afe118f13477bc1a29ccce34eb3e8c437fefc8f05335ab4f8e9157a267ff252f073ee0c586962722fef28a43c2023a4f1b6b	1655064971000000	1655065868000000	1655065868000000	2	99000000	\\x06071528090cd913040b1390b5ad4a7e9ce738543b74e848f4a81a9934949df8	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\xf1c40bbe984edc157ecc8aeb8099f9689b9ae658c1990351eb271ca5f3338e174ef527d8ef5c5e48535fece63e959a1f29ccda3791a2db22a1bed92f2580a202	\\x7b26ca8028c88ef1e347d0991a892e0ee425f93fc78cfe6fd3d838e0f4e0b8af	\\xd09b5c76fe7f00001df972ff915500000dfc5c01925500006afb5c019255000050fb5c019255000054fb5c019255000040e75c01925500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1655065856000000	1248558872	\\x981a86309366e8106ffdf1065fa3381a2e45621a71ceeb9c4afab5fc65257d37	1
1655065863000000	1248558872	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	2
1655065868000000	1248558872	\\x06071528090cd913040b1390b5ad4a7e9ce738543b74e848f4a81a9934949df8	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1248558872	\\x981a86309366e8106ffdf1065fa3381a2e45621a71ceeb9c4afab5fc65257d37	1	4	0	1655064956000000	1655064958000000	1655065856000000	1655065856000000	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\x749f73a8d4e47333154e062d54af7145a261a236f12adc6f0cd1b4ae80e259fc41655fcd244cb0f8b540e19a2e8145cf9c04e4b7d93913186d19c1f58d5e4d23	\\x88ae10a4983a8c6644c5f441768f706da0323085994913e328e398c14e9792edb19125a964282bda3d73b9adf4ca47aee63edb467c567b1309e6f01cf6d1d300	\\x1ecfa4a08a391dd5c88d1e2093d66a89	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	1248558872	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	3	7	0	1655064963000000	1655064965000000	1655065863000000	1655065863000000	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\xed6a00c1a8c0d49b4528de3075575eeb2a2a22795f1ad64d08ea4fcafa855e358fafd681c7074eb66198313563d1114752e0d9d6e8fc19315c522926fd0235eb	\\x9f3dc438827cd7085bb804248fed8b8154d80901685ca775b148fc6b5fcaa8b2cd7db9219013bc8699f49b15e6537a5a38ba208e77b7c0d83eb020cb1372f807	\\x1ecfa4a08a391dd5c88d1e2093d66a89	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	1248558872	\\x06071528090cd913040b1390b5ad4a7e9ce738543b74e848f4a81a9934949df8	6	3	0	1655064968000000	1655064971000000	1655065868000000	1655065868000000	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\x1476339963899c7ff99bd3bb9dd1d55d5113a685cc5042fa490d72173c8f3e45457c4b9c93429ad40c688d177897ad44074490cd9fd3b0d8c8f5beeab7d674b7	\\xc19a0ec5c3f08625597e3062f8e60c9a7455f1760225f09eda7a8b57d49389780dfafae8af9c2271948b7fb31a61ed878427822b6e1c9975cb99e3d9467a100b	\\x1ecfa4a08a391dd5c88d1e2093d66a89	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1655065856000000	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\x981a86309366e8106ffdf1065fa3381a2e45621a71ceeb9c4afab5fc65257d37	1
1655065863000000	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	2
1655065868000000	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\x06071528090cd913040b1390b5ad4a7e9ce738543b74e848f4a81a9934949df8	3
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
1	contenttypes	0001_initial	2022-06-12 22:15:40.854111+02
2	auth	0001_initial	2022-06-12 22:15:40.982137+02
3	app	0001_initial	2022-06-12 22:15:41.073203+02
4	contenttypes	0002_remove_content_type_name	2022-06-12 22:15:41.08508+02
5	auth	0002_alter_permission_name_max_length	2022-06-12 22:15:41.092913+02
6	auth	0003_alter_user_email_max_length	2022-06-12 22:15:41.101007+02
7	auth	0004_alter_user_username_opts	2022-06-12 22:15:41.107472+02
8	auth	0005_alter_user_last_login_null	2022-06-12 22:15:41.113942+02
9	auth	0006_require_contenttypes_0002	2022-06-12 22:15:41.11632+02
10	auth	0007_alter_validators_add_error_messages	2022-06-12 22:15:41.122496+02
11	auth	0008_alter_user_username_max_length	2022-06-12 22:15:41.134892+02
12	auth	0009_alter_user_last_name_max_length	2022-06-12 22:15:41.142158+02
13	auth	0010_alter_group_name_max_length	2022-06-12 22:15:41.154758+02
14	auth	0011_update_proxy_permissions	2022-06-12 22:15:41.16811+02
15	auth	0012_alter_user_first_name_max_length	2022-06-12 22:15:41.17862+02
16	sessions	0001_initial	2022-06-12 22:15:41.200194+02
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
1	\\x939c1bf50e69c3209e0e8db97dfe9c42e55454dd44e33710e5c4155b90449469	\\x96c20d1311fd3917b02d6b49bc8135e34bd0b24d76ef5da959f4f9aa89e95bc60ab0b1f891da674a22a0d2012fc0236a15c145781154dda2f4e16bc41ce09807	1684094140000000	1691351740000000	1693770940000000
2	\\x733e29cc7786d29d7d9059bd4975fa647fd739a57f3063d1a9cf052fd7d5f2d3	\\x80b53a5f909b927324e770e82a64a546e47273089f7a6d3eb0407c17d536df49b4f8d534392b498d31aa9757cb53b815456d563f040271e8c1ef2edbd9491702	1662322240000000	1669579840000000	1671999040000000
3	\\xb4ba4fb12212bc172ad3bf541b6ddde387b6b20e53fe04795189bc14c559adbf	\\x6dbd825c8080a38015323156fecd1c9f1bfdd820d73505e9803db6da7a796fa62240a8670991d1e10207becf9478b11f1b303068bc84a3e315cfd543a3df730f	1676836840000000	1684094440000000	1686513640000000
4	\\xfa2e1be77151fc96cab549bfde47691fed575d0d0aceb1aef857e8b811093a0a	\\xbf1a04b36f759223eca538c207ae83b78c956c181b5126b3f861a4174e313d60249d01815d7fb9a5e7af3c54b126d85de764524597de8c99ebd2ae59e7047c0d	1669579540000000	1676837140000000	1679256340000000
5	\\x7b26ca8028c88ef1e347d0991a892e0ee425f93fc78cfe6fd3d838e0f4e0b8af	\\xf708b2fddc2efd29adb3af034c3713f715eaa4599bcf017cf59b93cb22140ab9b849b88345cd647253c9d583cff8e9b465dff651aa1ac97b1c4e0ca16a20ae0d	1655064940000000	1662322540000000	1664741740000000
\.


--
-- Data for Name: extension_details_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.extension_details_default (extension_details_serial_id, extension_options) FROM stdin;
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x7bcbec23ac7db11a8004ebcaa58301aaffe63e84295af3d6323f1d8a7ce71a581df870e927254723f21c74313b24222edc0a7d34d3bf87715e53f033abf27406
\.


--
-- Data for Name: history_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.history_requests_default (history_request_serial_id, reserve_pub, request_timestamp, reserve_sig, history_fee_val, history_fee_frac) FROM stdin;
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	43	\\x981a86309366e8106ffdf1065fa3381a2e45621a71ceeb9c4afab5fc65257d37	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000880a87c3bff955099f54e0cafb5ac436a1b3d6b8ff9675966f0c562dbb8a597ee0fc8c4a89f94caec34a9399738d5b96b2c61be72ff5908465297d93fc9b5bed1f9b7a335af5cc11ebe493ced7da94b04949251ef026b0671ed19f9d1619e3c5ce61b92dbb62f590b95e2fd20e4c5eade65f0262e61ba2e43124697113f0f46d	0	0
3	116	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004218c79c3c88e410bc1f4e9021ccc7bb477179a247676f44e687c05692582b4a66d7f776b6698a26ee595d7d774df1306bf57a3830a911e681ee2b5489e87337ef784f57da04aef87bdab0e242908717d2a9ff7d0a89a02177bcf88f3ead05c2633352c2611329e467f2790e941b28a744df30d0e0f829332518e8910e86c4eb	0	1000000
6	220	\\x06071528090cd913040b1390b5ad4a7e9ce738543b74e848f4a81a9934949df8	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000d30def37819dc64c51b0ee38196e19b0aae7101f0cd5f7ed8467eb09adeb012f768f89670db9df00a7ca0f546f7e961bec0ccb9889c71bb426626acc5f289e42d311045da68d66648e8ec235cb74177752df823199d37be23a4bc1469644909562e7f1eb7511906c861ac990c97b1497d069c7114f8b17b6de78610808b164a7	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x96ad0ed376d39a43823a5af00599afe118f13477bc1a29ccce34eb3e8c437fefc8f05335ab4f8e9157a267ff252f073ee0c586962722fef28a43c2023a4f1b6b	\\x1ecfa4a08a391dd5c88d1e2093d66a89	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.163-014D31WYMKM46	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353036353835367d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353036353835367d2c2270726f6475637473223a5b5d2c22685f77697265223a224a545047584d5650544544343730485442425230423644465734434632443351514744324b4b3645364b4e4b58333233465a51574857324b36504e4d5a334d4841594836465a53353557334b585236354754423245385159594135343747473237393748505452222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136332d30313444333157594d4b4d3436222c2274696d657374616d70223a7b22745f73223a313635353036343935362c22745f6d73223a313635353036343935363030307d2c227061795f646561646c696e65223a7b22745f73223a313635353036383535362c22745f6d73223a313635353036383535363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2251525a464e324832433146414e474856373646424e31314553544b37325646434733425653525a413650484a4e54395747335347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d524143545342484252354e383853593248544647534b5241344a44353547544b44454a595a5251455736463856425752444a47222c226e6f6e6365223a2251584459334d563035313339474530313034544354584a45534d45374b5352434b52534b4259515a423257365350443857393230227d	\\x749f73a8d4e47333154e062d54af7145a261a236f12adc6f0cd1b4ae80e259fc41655fcd244cb0f8b540e19a2e8145cf9c04e4b7d93913186d19c1f58d5e4d23	1655064956000000	1655068556000000	1655065856000000	t	f	taler://fulfillment-success/thx		\\xa016d8ad2724e40270b3950ecaedf437
2	1	2022.163-03C0GJHDDM2AA	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353036353836337d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353036353836337d2c2270726f6475637473223a5b5d2c22685f77697265223a224a545047584d5650544544343730485442425230423644465734434632443351514744324b4b3645364b4e4b58333233465a51574857324b36504e4d5a334d4841594836465a53353557334b585236354754423245385159594135343747473237393748505452222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136332d30334330474a4844444d324141222c2274696d657374616d70223a7b22745f73223a313635353036343936332c22745f6d73223a313635353036343936333030307d2c227061795f646561646c696e65223a7b22745f73223a313635353036383536332c22745f6d73223a313635353036383536333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2251525a464e324832433146414e474856373646424e31314553544b37325646434733425653525a413650484a4e54395747335347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d524143545342484252354e383853593248544647534b5241344a44353547544b44454a595a5251455736463856425752444a47222c226e6f6e6365223a22514530335731423646504e33513434425342313247594852575a4d5931355442445a3556424837505848474b3334535944314230227d	\\xed6a00c1a8c0d49b4528de3075575eeb2a2a22795f1ad64d08ea4fcafa855e358fafd681c7074eb66198313563d1114752e0d9d6e8fc19315c522926fd0235eb	1655064963000000	1655068563000000	1655065863000000	t	f	taler://fulfillment-success/thx		\\x32a076b98e65b16d45f033f08f8e1b75
3	1	2022.163-0382BRD7WT9F0	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353036353836387d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353036353836387d2c2270726f6475637473223a5b5d2c22685f77697265223a224a545047584d5650544544343730485442425230423644465734434632443351514744324b4b3645364b4e4b58333233465a51574857324b36504e4d5a334d4841594836465a53353557334b585236354754423245385159594135343747473237393748505452222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136332d30333832425244375754394630222c2274696d657374616d70223a7b22745f73223a313635353036343936382c22745f6d73223a313635353036343936383030307d2c227061795f646561646c696e65223a7b22745f73223a313635353036383536382c22745f6d73223a313635353036383536383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2251525a464e324832433146414e474856373646424e31314553544b37325646434733425653525a413650484a4e54395747335347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d524143545342484252354e383853593248544647534b5241344a44353547544b44454a595a5251455736463856425752444a47222c226e6f6e6365223a22545645394b3938534b414d504d594a52473043345a5631384356304e48514d31373653324a5459305a3656465831364334354d47227d	\\x1476339963899c7ff99bd3bb9dd1d55d5113a685cc5042fa490d72173c8f3e45457c4b9c93429ad40c688d177897ad44074490cd9fd3b0d8c8f5beeab7d674b7	1655064968000000	1655068568000000	1655065868000000	t	f	taler://fulfillment-success/thx		\\x5767cae9f62058417c9dd104cfffeb96
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
1	1	1655064958000000	\\x981a86309366e8106ffdf1065fa3381a2e45621a71ceeb9c4afab5fc65257d37	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	5	\\xdc1604382c668d6f0f1c19fbc36833dba6057fc787da4f7447d4037fa68f9cacf7b697addeb343de36ee66236c8579862ce81faa65d57df873b5146800123a09	1
2	2	1655064965000000	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	5	\\x183f9206f9927dc6adc6e39ccf6b2b512a66e9e6392eb289224189ad88b0dbeb658f6cde7308c3eb009ad22f5f1c4df9df17112a5340ea2ca1e1feb75d43cd0e	1
3	3	1655064971000000	\\x06071528090cd913040b1390b5ad4a7e9ce738543b74e848f4a81a9934949df8	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	5	\\xf1c40bbe984edc157ecc8aeb8099f9689b9ae658c1990351eb271ca5f3338e174ef527d8ef5c5e48535fece63e959a1f29ccda3791a2db22a1bed92f2580a202	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	\\x733e29cc7786d29d7d9059bd4975fa647fd739a57f3063d1a9cf052fd7d5f2d3	1662322240000000	1669579840000000	1671999040000000	\\x80b53a5f909b927324e770e82a64a546e47273089f7a6d3eb0407c17d536df49b4f8d534392b498d31aa9757cb53b815456d563f040271e8c1ef2edbd9491702
2	\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	\\x939c1bf50e69c3209e0e8db97dfe9c42e55454dd44e33710e5c4155b90449469	1684094140000000	1691351740000000	1693770940000000	\\x96c20d1311fd3917b02d6b49bc8135e34bd0b24d76ef5da959f4f9aa89e95bc60ab0b1f891da674a22a0d2012fc0236a15c145781154dda2f4e16bc41ce09807
3	\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	\\xb4ba4fb12212bc172ad3bf541b6ddde387b6b20e53fe04795189bc14c559adbf	1676836840000000	1684094440000000	1686513640000000	\\x6dbd825c8080a38015323156fecd1c9f1bfdd820d73505e9803db6da7a796fa62240a8670991d1e10207becf9478b11f1b303068bc84a3e315cfd543a3df730f
4	\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	\\xfa2e1be77151fc96cab549bfde47691fed575d0d0aceb1aef857e8b811093a0a	1669579540000000	1676837140000000	1679256340000000	\\xbf1a04b36f759223eca538c207ae83b78c956c181b5126b3f861a4174e313d60249d01815d7fb9a5e7af3c54b126d85de764524597de8c99ebd2ae59e7047c0d
5	\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	\\x7b26ca8028c88ef1e347d0991a892e0ee425f93fc78cfe6fd3d838e0f4e0b8af	1655064940000000	1662322540000000	1664741740000000	\\xf708b2fddc2efd29adb3af034c3713f715eaa4599bcf017cf59b93cb22140ab9b849b88345cd647253c9d583cff8e9b465dff651aa1ac97b1c4e0ca16a20ae0d
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xbe3efa8a22605eaac23b399eba842ecea6716dec80d7bce3ea35a32ae93c80f3	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x5ab06e2760ae2e217e23473004dc84e8bc3933693ad6b0000aa7be73a02b0d2bcea1bd98ffdd53b9cbffb988c745af0fe2d6cea1bf73cc9912f40673460fac05
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\xa614cd65715e0b54233e1474f866785124d2961a9b5d2f7f17770cf46d7cc365	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x6558300cb83f2d4715459ce6230d92030f9b92a2f1cf81e6dbb18a0d34699b02	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1655064958000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\xb2a758ffc1244088de7bf3cb1177246c1e98d768410700d2b089e2c4a99c272476bbccf6380dc1bc8514abf4aa7f31396c95330cbb9df698b9dd9d6c406ba30e	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1655064965000000	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	test refund	6	0
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
-- Data for Name: partner_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.partner_accounts (payto_uri, partner_serial_id, partner_master_sig, last_seen) FROM stdin;
\.


--
-- Data for Name: partners; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.partners (partner_serial_id, partner_master_pub, start_date, end_date, next_wad, wad_frequency, wad_fee_val, wad_fee_frac, master_sig, partner_base_url) FROM stdin;
\.


--
-- Data for Name: prewire_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire_default (prewire_uuid, wire_method, finished, failed, buf) FROM stdin;
\.


--
-- Data for Name: purse_actions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_actions (purse_pub, action_date, partner_serial_id) FROM stdin;
\.


--
-- Data for Name: purse_deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_deposits_default (purse_deposit_serial_id, partner_serial_id, purse_pub, coin_pub, amount_with_fee_val, amount_with_fee_frac, coin_sig) FROM stdin;
\.


--
-- Data for Name: purse_merges_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_merges_default (purse_merge_request_serial_id, partner_serial_id, reserve_pub, purse_pub, merge_sig, merge_timestamp) FROM stdin;
\.


--
-- Data for Name: purse_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_requests_default (purse_requests_serial_id, purse_pub, merge_pub, purse_creation, purse_expiration, h_contract_terms, age_limit, flags, refunded, finished, in_reserve_quota, amount_with_fee_val, amount_with_fee_frac, purse_fee_val, purse_fee_frac, balance_val, balance_frac, purse_sig) FROM stdin;
\.


--
-- Data for Name: recoup_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_by_reserve_default (reserve_out_serial_id, coin_pub) FROM stdin;
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
1	\\xa15070457c9bb5e2a310a9d6ea21ba1b75d56c604396f98f578f8ed3986a81f94358f869dbf4cfacf83500403e9f4452a049bcfb732999bf6e2e5c690c9a8132	\\x981a86309366e8106ffdf1065fa3381a2e45621a71ceeb9c4afab5fc65257d37	\\xf9618eb94ce3ceaa3e791ffea3e733961dc9611e32fa3e201eb6a117b02b585aef20e9b895fbfad1a1eec22b55f98e3bd8bf954e95930e0373ea1fd25fdc2b00	4	0	0
2	\\x0eeafbb209c0db60e3157c17f3e19377978b0e55536038129a557485ea6bb1d2aa28b99d5b3895b7fc3740e5d883cff6f9af0a06b47c5149c64a49766bd086ce	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	\\x28ff73f81f2a99a15b6bdee6265945c5dbe6edf4d42cd991def1991ddcd03bf24f01a9898662bbc731f5a0b6853c9867e05793b65c335eb9d2bb21d506292805	3	0	0
3	\\x9320a9cce7e5be0d0cef615dd3b44ae4847f8bb4396f399955301f53b6849d02116d08335062f4e85ea97b21855895e9757caad547e0d3b81b0b56e7389f94ba	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	\\x73b28780bc4175302b65399f2affe4900f3e645e0117ae718406b8195edf2c27ab85f526c8fdf5e98974ffc5873f6d4277dfa8607d5020f6ede1dba273b13402	5	98000000	2
4	\\x9765502c35f07dae5d817ffc7a3ccdfc1779e92bc7d1f9c9eb1885c848c84014fed4a7ee23f5c9cc1e5e518e1e569a54a3f949c4986e703d7f81b84810f4bff1	\\x06071528090cd913040b1390b5ad4a7e9ce738543b74e848f4a81a9934949df8	\\xddf29efa90387bdbd08a5809a4e1a29cc57b14b284f6295153be6f6827d4448e2b74da258ca68330855a710fcb44198a511df44d28f7697da3602cc2e46cc706	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x1b2a44aa0f55ca790dac1b0da17f043c1865d3d9d51ddcd56f553505ea6e132b5ff434ae7bc36fecf4ce0b4a075bc5226bed7944677067ce7d210d61fe07040a	201	\\x000000010000010060f072aa713166ccf0ef8b403d1f1df11db450e765f9dbaf73e4131d12760aa952fa229214ceedb4deea7b6dbc18b6d75947784bf44b29065a4509e95a716367df638ef4de640765c18e3f0fcfc557b84328500a04a1913184e3343a1d8494a840835a13f628b53edb21d6b0b65a908d223f42135e30040c730e828ff55970f3	\\x9142c7c9243d89dcb020bbb3491b79e2978d1db7b3fd3c0b573472d1875a4150a6d62ec0842f7840cfa8113f5ff9da901ec6db57ad0935266a7ceb55db55c32c	\\x00000001000000016e257e13717e7ea420bf50841733d82a26346aa8df8d7ac32f5af240657cb2683b8139bded3ffc54e7ac855fc2c2a5b8fed6d1d4f40a1d39b8d73a8a5ab2e373742c0dc93abdfc3487fdaae5a020c44ad84a80e8a86021ea7d4aa26713bb6e8f35ee654486a5dfc4d66e401e31edf968a9d76dc7fc334deb8f90f801be1c9a5a	\\x0000000100010000
2	1	1	\\x54c20ef59cc95f474963491eeb6bc4a6239782407a77124a9277d2d125aec08c085225465c8a9b4a3f4ecc0a70f520f83c90abd1ac5a677b342b6d680b721b08	369	\\x000000010000010023af67a10121759cdee5321d968368b01459677398623a0f5bb2146f637094fe26f8afa21d71a012e949ebee5c18c6a180ec4e27e0a12deac98743c9e415eb1e5a89360a13a12031c98dbc6432ab2b374fc7bcd9a20cc17b850d2de280770b40717009205e30097b030a511b147f22cc212d5863834d93c8ceb18a3dbdc93da6	\\x3130affb2f7c2211ada9d26f837d93c74e2bf647e5e4a46e560a5bd2b82a9ae7a467c6e7db55f9949bba12733ad446a4cdbfc801136f96ac24a60a0eaf762101	\\x000000010000000165b20aec03a0d507f88ebd6b02e7c411401e179f7188be9428877787f83c733f6f09da75d886aceefb0d154aa64169808754d028fcdc3d14959f977d2134daaee946fe3f424173590657283ad09ef1076bfe20c1e79b81b3fca2521e8d1f2dbdec1af9bc1153ccc1f7bfde3e0827ebec69f039f67533c81159e8ae5267d3674c	\\x0000000100010000
3	1	2	\\x21ba9e4ba18548b45d9f79a2f4de05b98acaa718d35cf977e755194c67614eeebab81ad3ccb5c96291eee131a0cb92dc750f6ecf9195d9419aa892a7de23620f	14	\\x00000001000001006bbc854535f2874e9f53cde8ad03f228d03dec833fdcb4e42b49621fa7fcdfb03791bbc6ab68662b75b6a7b6739fc532925d8f56c9d94e0b119919ad26d485fda3a113423c8b33fae5faa12c5501cc8cb95168fad100509d1617c8e11074bc9ceb25431e429f51dffc4e0109549818d7db5b33342e8efde609998a8cfb799f24	\\xed23497abc6feccc46063c2f4151d6b23c3dacae2995ebb97070610cd25d1c65a2a1f3fb7683baae3c47b88b34b8460495065f923a3b44ebc5387ff04459c12b	\\x000000010000000149aee1b6a127c71d209631c4a70636fb55341f1f2ccefa1dd5c6ebbdaac58dd3f1f5817f1ed7278517f7cba65b6bb2b16c20861599ea15dca8bb6c20566b969cb7358af7c8345bbb6cb788017365c3e0b4d5b01d1d9844a6e5b4e3298f7a4a2285e30feca0787bf4e02598952ff32a7aa9b144510728acf6434f1d0d200c9521	\\x0000000100010000
4	1	3	\\xcdbabff60e77431385eadfb2b569e96be1686f0ad130b0718e895022783174c8fcd7477823d7adfa1757bd18c5d03555d6a4fcfaaf4a99d7d12b3661e04f4706	14	\\x000000010000010028bbf1d72ed6f758d226e1c81c09d58b6f44c40c46364b7cb12d5b91755e8cf567d6fc604f8b690c2b548c6fd17236263deebd5541b69ab7d4258b1b443138c3881c0a57302936ca32dce5f057f0631dad15805d65f3d42ecf3c1239b2c195ef6d540e21ea237cddb003c8d76662171ddcca8bf8293007d49750df0c749c5ccb	\\xc6c2a360bc0bfea35c6d64ba99d8d79d266048a12e5277d02eb520448c96185f48eb52a3bcd90261241cc818189881157d4a0b347a50015a2295096b0842c742	\\x0000000100000001762328cf45dcc372b480ffbd4629179ba3262d2df0a53d8e07c734ae311073354396ac7b4dfbf215dadb807cfc1af2d5b6b53fe54282352b5f60d367a003eb2c4b53320845ffc73e292ca8edc2a9353b69d7a25d9cd99255c56071ed2f3f0ca673ed0f32d8a5b4deecbed33a2fa0a46aefcace98e0126b55837331794a127f07	\\x0000000100010000
5	1	4	\\x29f7b8800451af33727d7d23edecae4075d3eab92d8995b40a8318685863f8815cf7810a65c510d7cb9a6c490ade3297543e36bdfb4a7beb7301f1f5546b8108	14	\\x00000001000001005d4b719bc38cbb5a9ebbeb3fb3872fde7a16cc6a6a065e4ae6d5d58a2fed7eb97fbfb136c6b27c28427043b0a0c478d599eb45bb355a0240df52dff8bb08fc06ab58bdc3313d82b93cd26fd425747b72e3e35976cde3ff08b250b4185cb30612fa33f7399f37af1b1e0e32a0849f9e1bffd0539ed18fca63ff9ad2d548c48eb6	\\x974940a476249ab1fec6cbdd1a10d3dad4123d9d9a623c4ddfb451cb5a1837aa46772f2390480ad2cc6b7af4e64a660512eac4a6f69142165f67b20969b9ec85	\\x00000001000000019615602f59574cf8a215b293642b03e8ab7724182bcae014bdd1f5729313be8782872d74f2a5f9bcd0e2bcc0804eda10993662ff108f7f98c50c1024afd305d8975148e8b9d76fbe1ef67b876e336e928e91691f7c096ac904213e298898da3b6ce2f2a168b9d710bce4ddf2cb38a4d059c24f2d5289d987d8f4286ddc22375d	\\x0000000100010000
6	1	5	\\xc10fcf82911847c01042fac5692c64acc2a9e68ccf277bfc76a913bd5334159d91abafb71d56c9373dd22b157ceccb5eca8031b33b43181325752905ed16be06	14	\\x000000010000010052d407a8ee286bc8d2e49c227b5fc16f080fe051f3b064542d1924e52097deed640028250f03c3d692a189a14209efc7b01f86a37c6575beb4579349981fad292fe31369599f793ba627101cb8ea21bc1af95da58d76911d322bec3b521499a7d1837f833fb112e310d37e41be5479c24666257fd7d24374b48c10d52d4bcedb	\\x7080dfb3e5a604433b26d7cdd6f3d82d83c879dfbc947fbb5fdfeea162b471afa0fa0d49d8857a0b9979577f2b154ac4675fb9d8c2409ca4db92018811e33f0c	\\x0000000100000001861c0b410067063d5bf6b89279bd9da5e7b93c35f9cdae90513f33b94933e0c1c762e5880abd6cd6a0f733571e38a3695b8f17ca8103cd615cc5d2ea8370eee4f657f1be2550bd150dbf1cc05c89cf00144e8a9878a0d285cc7cf817e6640a5821e65ab179c4c1bd0fdaff6c1eae05ab16ff2012808539ce748c7fd2115141f2	\\x0000000100010000
7	1	6	\\x9a3be452fb5d2c4f049b213f1afd2946206c54f6ec08eb5fefba236c91e9ffb383554475cf5fa9af979404a4ac5e8108871f703ce04db06b1d2219e527474c04	14	\\x00000001000001002be365f3245ab592f064a263dc1542ba567658ba975fbcb9de759cd8323675c1c0097db4dd9e49a67ee437118b36b127a1d64cd9df86110ac54d62aaf3475d267cee7cc374c8bb0e39b9b05778a0b110c3bc704a7d0ad85b7b88ff4295d697272b36e0fdb35f25573b90c6d8d1327afb2915f6ad64fe43381797fba52cff9d60	\\x6ac742f8b9e8dc15452429c4f7d5f762afea5310aeb7cc7a34ef3eb110465f7513d0790d2321c0acd1b7869c8b9bdf314463711508cd015212c5dddbddd5426a	\\x000000010000000165ac91515ae201bcd2e1e36a1ced0b39652638dd04f87e513d228e51e74ef95859ddb960f134993f093dba18612fbf508c9c0c01b01fecc9462f583f82ca27a363e22aadb81f5e2883e3ae8752273da36461ca5d75331e6eb50b8bcd336b3169b8ad6d0f10ff72d3ed9bcac37a3a72282b7614af8034efbabf3ee5870de34ef7	\\x0000000100010000
8	1	7	\\xf93c0ba77e2152df9f7235ea7d8dcbaa9a274ebaa4dbfa4aa6766e265dc9d2a0f9b7955296c0dd3f3d983c59f198f1c5d05e509e9b02e4632822c992dfc96601	14	\\x0000000100000100108e03d86d84bd3d9e3f128346dd2a865ccc5387fecb51ff5b574dbf28b6ad4bc30b56be3731a87cafc7261fa64ee2ad2787a66db3532c627a59a3516a5869d528ad87ddcf93bff6e95adbfc02cf231edf7b4b94817729e511db22dee36b20141bdfe2df19407205848b8e76275594583cd2c0110b74e4e77e791b5de518670c	\\x48ea9c34dc0b8eb5f01a501dc4144452fde4eff88947316d7f77cf9f1d957afdbf023b6909838edcd0f317a6a59a0baa960fb39fb7ddadcb62c7686a8517e8d9	\\x0000000100000001212c6778625a3f717ac7dd3ee042ba6c2e46f058cb8cdc374d1d45e10cd8031056964ac4b69fce111dfdd17d6f2a37908806f0a3958cbf839538a680a95d619922462df6cb750a75627e3db2f5b7d5306f3494cfc45b457ffeec422f0074bf2d3e0583e5d2a2c5defc90ad0d1cbe4f2142ed2cca5617c02f6b300daa82550150	\\x0000000100010000
9	1	8	\\x5811e079183c2ab72f8206620dd10154e485094cee7b8a10ee30ef56bf27eb5f63f3c8061b7a8843806eae8ef6925c4eabfea4a430951513209b9a1171e37908	14	\\x000000010000010085445f5af02318aa17ea18a99b8d6a79a6a998b1ed1b24a154bcb6bc7ba3371e02c4830521fd14a8a37802b356319308ac0dc82c43ef3c9da41f7a395e77a212c773412ab4a0409e56d196d3b690539c1a12f3eb4412c83a689695024d8f8404d9fb3de74b0ea761737e0c354e63ef80dec8ced714a1f2e3a57e65ec6fbdbea3	\\x1461f68ed2ee0b01cb5ffa44f959c037578c97926b9e1c76cd47940642f0a345fe96a2698ce8c319551edeb4e1a0b8055666e17d955ee13889dfa17ec7b6a016	\\x0000000100000001be6e01620a6b45ab76ebc29b9a7120f06de1ad59d7c07d60a7b6c9a5185167be4b59d810f90d922695a95c229950dfadbac529e51a530c44cb96a74ad8a464930b27bab4a17013ce02d56c9bfb9de571fc1808bf3b755d22095061f76624422a80b7be7bba1ca57009d8867e5cb1be874da8b6bcbeb17ecb53ab8a12ab12d0f9	\\x0000000100010000
10	1	9	\\x858c8c1ef776c4d714fd9828cf55cef9d126cf85f7489e7191db93113cca91126caff581b1e3851f56adde26af6b42688b1e9312048ea4fd82ba6f6635a4d806	14	\\x000000010000010087eb626f4fe294d9b1d0e39ba179a6d800d4d3c4487591e2a6ba2312913ce777c3f26d44c13936844789e9dd045a89df400c577693b1f9ccbf3291d3851fbc7beaf682d38d269d53229148d6980046688a9046e92571daa3e86039b121ef303825b0e07d27fb7b1f33f73978bdd094c48f1faaddc166a08521031e1d4214a6ce	\\xa117432b1e7734bda41196f24240afff817e8a16079c89819f97ba61eaa488dd08db5fddb588befa584631570dbd0bd866c42153825e6fb6dcb3427a6d4f339c	\\x000000010000000105f89c091d6293fb9a587482d6bcec46e3daf9a1ae8fcb5bcca47a044f62eca6d1292c14b36f7a65c5622cb6380439b82e49d44428ec45f0bd3a4fddfad1278ad34cca8b6cd0c1349c37feac4b862d3dca2154db962926164308b1db5ff572163991d880db41721c9e8474f22be32f895ec5484f7c1bf190ae114eb3a51f697a	\\x0000000100010000
11	1	10	\\xd732c332e53f2ff1a5fd3a6f553326af341809c6e94d394c8ff1859f3ec02cad22399298bd1c6115eb503ecb96afe9e38efb6ad5b8188a3ab32320a13e37b707	401	\\x0000000100000100051869239aa855507692817595330f3939566a29b7b76ea70dfb9c1d3ddd202042c3a3c6831eed89799a7993b8fbc4c7c4cd90c9f994d15ebecfe58a0dce74b27d7b21c2f89fb31e0d608d6f4fd7f3ef217cd2b58cd7070bf5f402c77941cfbf0159bc152bbc4336b0743da634e29718a62a949d5659c8f964060db75dde5a43	\\x1e0ddf817da610eaae4a0915dd65f1336b30c94da679f89c9a4ef3201a9a7a23c5811e45a6932ff1ad3af6dd433bbfc060e1468e8486bc13e0fa364a76539b17	\\x00000001000000015dd2a8e3a133586360cac43e599ca4ba91dd2eb5441b643a7ea653d3afb33e824067664e6788858996966222bcdf6b47cb43f582eaaa747c51a32e3d27d5effac0a791506349e27e1f5b207b828675282b20ba7e41177d0b2916c76b74fd8ab5492fb44a54a715adf4a1edb87e8a991fb78fe00a135af87b3808cd048faba5e7	\\x0000000100010000
12	1	11	\\xe9c479ce930e6395d2c184f4367d7a04105569a406db17f9c7ee6926a1fba89f91a122fb70b1c3b3728ef4af66a427775e14992a898e525d57048e3fd8cd2205	401	\\x00000001000001009edac7259b7c645b43452c92279f4d57407a04e4caf47287127d025480e9f2e41bbdea88eb3dd2c877bc89fb9be9c22f453f7863a815f57d2cd5d620f6fdca85dca092f48c7ecb4ef937891fc6756bc2fc80580a5c6c309034e40316cdb294902ea40e123da4eae32056a0528a1f9dea9897232ece8e0402d1720cba7f81b651	\\x02acb19d45bdb60d4bb3a1cd4b4890b408021c612dbd8e9539b1556143e2fffe2649da3ce822f5402a2d8c1758c52e0e4d86d72efe346e1d5396b1321a2e0c1b	\\x0000000100000001486cef469a292e162c537f8bb819edfb040c70124166826154a52a55b72e5e77db15ee9615feef4d6b0a49d7db6099d9ba25d0e5cde1b0451f9cf9bb41442f462a8f30ff2fdae4adf044015a83288f693708440257d990b1a6f313515e0ce28845b8250db1586ff2c21b6894aeb94559a02936f7f12a7e01402fb3c467654937	\\x0000000100010000
13	2	0	\\x46b33d0ee8628d3603b76a46e6e7314a47e4347a953db7167f2d410cec9d37bbef1be8089a10382e3f9d8c9d9f33b8641561f6e340d31209e73ae7369a139403	201	\\x00000001000001008732a01965d02fba2f99f3ed83e212ca77f0c5fddffae1dbbddd8a29c49ac4ce677a47ace066ba896923f487a440ce6da47a0d952197f4890a8758c488dc82e28611e4da8dd6d28a81d8b6c8b46f899bd5f51c253ce435e5ddd212a615fd0b15cd896936704b3702c70d1cda687270f6ddedb85be288f8afc680364481eea47e	\\x6a7f34caea61f4909720e826ba735d6061fe4db2a3bb47591cd3ad5c603fb4f316fc15b990aea6c16b70d9966da72794e13611f3c184bd3f072a7a780c9909df	\\x000000010000000154345171beb1946b6625fee2072fa12135c10b83d04da93754ab7d47e2343d5b2f1fe93ccb8123ea6b7349773bf7a2599afd2d3ac4469c37d26799191f0b50ced21c2216c3966c72ba8cb9ef9d59214e324b5c981ff4bc4c0b5483bcd0e02a2f480f83c8e660da2f0b668d3177bd024f72fd4166ba2061c4e59662d06b9667ea	\\x0000000100010000
14	2	1	\\x434ca01b8d0204f0425d4373228d7d8cc0a98febcbb8c0e99e70b2b56f167fb99da5248d9961ca59e94025f7c36fa70250480dc450932ef578e96c6b2f44c60f	14	\\x000000010000010049f5c91ee8208495677f6e5d59ab6ec7a5d155d68a23ebc1ad63bb9251ff0d5f27c03b2cabf19229f53a47299e27eb9148bcebd1dc45440dd258c0c8c2bcc473d78ac525b0442d0b87705584733b95c29a0531be00c96912733e9801a0ed1064ecf2acb0ef562b783c24390db77b57c9f744e00d90d332b7d116612611e2926c	\\xc4e2e805450f9e5ee6a0478119c7d47ee303a9b0fba2084f892211fc87967069ed116b5188c96ac013b3a1e60b71aa8ec104ce78314e8af7b6fd3a52742d26b6	\\x00000001000000017d65656e1d564e005ff94f4e48f2f73e94ac8541abc0458ecabc3050d173b7a817dbf0eb924ac890e22251b53978cbf6f26029ca840f7d7b7d749642a06b8013cab5d72fe9f86e1908552dd54271557a0005ec863448917fb3609edf9fdf6068e1560ef0b2f9c4ab9a76ee82952c61068699f710d2917e5dc0d79f2968797d5f	\\x0000000100010000
15	2	2	\\x2864fb1930501d772182ad4a82a977fb7a01565e4ca0053e1545416032ffb55e8f9f6484b8780340d63e4d3a81bab0309d8d6da72bee3f622635fbf3eb93400f	14	\\x0000000100000100c7a50df51cbc612a9dc52aafc10a5212900516191908e988477b1daaf80a25435438db0e1cd9a9e9d2e80cad2dd802e99ba6d7418f289354ff62e99b4c058103d6d0b596a9ba66ca19f8cc6a1ce0d024a07d19cc13f2765a1c353aec4f8303a5842a49345431f859f3f4b5d74f15c2f6f75fd6b03d18b82fdcfcc046031b8830	\\x671737613220a8a02d1e204d73f77ee3434c59b783f9e3ae6c56f0dadd4fa808e5a084e3331737a6d373cbef0128d36a21c6d39a1f4629313b36d50fe4f6ef14	\\x000000010000000178c2d101f58c7964583b81e689a075716b565582e3daa480c890f66f2cd4cb9d6a0b54670b615c4b2d41ee4398c5988ef1d192e024bbb64c5a997adddde7b9dd811ffb8ea9db75989cc3f3320fc6a3cbde21ffface8b0f7039c22137d7e9e74900b4d7dee316354ca388dc34ab086feed19c76e8a3d7a9f8c74895400c394616	\\x0000000100010000
16	2	3	\\x987c94c24579cab28ce18db212ea15982d5d959465b32cda0827da551155839ea7c5411366b3f13bdc89c61e706a40c120e67b4535ccf03ebe45f73c6eb21802	14	\\x0000000100000100d1d189737c1485789ffaa1c37846bb8af418c262f1203f03989cc43169abb8ed124353ce11775e9b70a4344ad0f90382bf8b9e8ae42a9c99048efbfd00eeb4a6348e99a9af2462d639847129df62b3e8727d32b1f88a889271bb489b610b8d4ec2b03d011b21a7b6076b1c0ef1dc7b267da47a0e60dd8c2711b0b15c466477	\\xfc338be15d4df53962ddfbd219e3821be5616ea6188ddca9ed239a03eb97daadf68697cfc0e6178da5edeea1b219ef7d1c2df887e33de347e4191c534cffe415	\\x0000000100000001c7369003f0fd63714b0f8334df2b076883134ed35062bcbde5aa5aac7e2f79edf467ce10cc8b357e2abea9c9cf11f99423aedf7c14cd6d360ea9a71a637663f3be15fcd2971d17cb7ba0ae45e7a41dc169852cf2fc5143b52d06da983e89e06cbe132fbe7d37ef5c5870fe48d9242f46b956182c17164c49af8b7ec59bcacff1	\\x0000000100010000
17	2	4	\\xbdb9f00b7f02836fddb1b4108ba7b620202eba175257c726946515de8825c8026dfbe47d160a4b61bf9aab032839cfc8c4fbfc645a2f203ea15533b5ac696401	14	\\x000000010000010076d222f5c2e9499da394c6e0aceb3e7ab980b916a56708f0ada89abc29264939f473be8437c482e776e11d28559c51931a26e8cc7de70e18438550adeb2e6268049b7d965b5945f9de2d03f849e0e8d0b5cad655f994fc81d0ada016ebf2d280d24b154be04728599bb2885ca28d7aac1da416c3a8258c1da7059ab9f508f0a0	\\xc3bfada660b635af7294de798755b16656982aaf639cc4324e3fc71a15b246b16ac543cef137cdb14e028c31f91b3bd042c446808af70550095ff01f6d0acee5	\\x0000000100000001cc2206b1574eb00de3f8ec418e020b3eadd6e6b4304bf5843deb2eeea7e0e2f0d1d149fcb543f678221418646c8e9afe8073ca3bb02f11197a3ab626e6aeaf27da2ef06eb43038a19bfaea794be1153012e4574b51c3c385f3c51764400904e8ee090cceccd53243a8e850e8e44d9d0f1cd70dc5f2c398ae60478f885ad4d250	\\x0000000100010000
18	2	5	\\x3d224dcee51374ffc47811acdd0473dd48040153b69fdac2497843b6c67e589ec1d0da1551f44cb4e17e5e8c247e2b5f2245e324e2289a9869f93b48cbb5710a	14	\\x00000001000001009ad53a12df4a378d0bbfef7e05331f9ce063f73e47e185b07f85cc65bba4e6949e7e8d7ed38045d07e5276cc0ba31315a2db9e6d2aacc89cff5dbfd8d9451ed02777e877f65a5dc60193b21381fda296aa26d282e865f5858f0350364466026049a4b1743684bc13488d3380fe53bd5b3abfb999908127166f1adad4cd33a506	\\x3ca112ac415b1edaae7bd6cd7cfcbcb3869a65571cf5af1e2fcc3a7682832f931704e21be0fde2eef9366b8dc67840eff47e5f7b4ba7f1b91345736b36d7cc9b	\\x0000000100000001bbd7f797c4c1723dcb9a0a5cc4d9595e43e8260ffb9b0eba66be040c8d5e5777304d5a45a8f861239b396e6addc85692ff4962828243de34c4f289882461bc545ae2459525b3451a6d6668b3e65d1a7caddd279f3e6ec8be97f671a045c7e0e97fa11c753f8361d5d88840300bfb5d22b950014994ebff667ddf547251c762a2	\\x0000000100010000
19	2	6	\\xcd0083b0cef1c712a1b278725abe3bc3ce57723bcd77ec0e6cc1280833310887b989ba133afaaf62b1cf4ce0383562ce209e053d7cc07e69b1eeeadcbdd4aa05	14	\\x0000000100000100a6a7721d085337403e3a7b251d658a64a83910dca25ac98ff54ae72ad1254f37c4558db8de2e9853b9d1d88692cee88e0aa4f0a00b68bd6e1390dd1d65a214d37eca4957cf369f002de31099961d35243ecd027fa8a475b93062e5358ecce0622b27ddcc21462e9941310bfc3bcb9ddf482b7ec7a10ed4e4fcc328cae399c2e9	\\x7aed414a6a7af2d379a9393a3ce96bac719ec8a284364139b725ce792d65d246c8c0a0263714a83559c78c6f246dfc71d404b9da0cdc54e78648ba7b9fbdf4a6	\\x00000001000000018ce46ccd071187d8311bd0ed71ee83837d49d46e0e8a5825617a89a8be45d77c62fef025e384039abaf1c8040711bb45d6901c5a645e0cac206c58f85d687b4b144aae1755f70638196a2ade7d93cdec5be132784fb7b4c9e6c1494c871a5178a628e0c0600f55569b3ee2039f3a687c61874039370ec307123d94ee9916ca1a	\\x0000000100010000
20	2	7	\\x697f1a68691729a72c6e45933f83cf3d5cae377e84201e091afc4faa41eb8dfe4c67f67e8023f94378dcee501c695c7ba5e7830f26dad8f7ae8d991147893b0e	14	\\x0000000100000100478c7cf4dfac8e9b1ad734f83ed9b0d98997a0e80cfcf7e6ddeb8768f79eb0ccf33b4c6f0b5fdc2677f38f1ed4101cbe328947e0abfc51b7ba2cf9e3114081273bd353468a20ff5ea750009a0754fa27ad04948f7515eb3998a25b5c71361046279a628d09743f1ed40b60ceb43399ce36f2e82efe3e05499c2e2fe2c6555266	\\x1aab09366b8c869eac6ea3e81948d21ec4f46184b3859a44cc4f166b7fc42957e8dc45a136f69ddea58f5b29c47130a75b535b46d51996db35019c80982fc088	\\x00000001000000018a5bba16eafbceca86bce5699369d988d60b739d96a47feaefd5fa3ba97c59ac874fb7f6694156012c4280d55d17d5e9090b184d9773d01c6361cd2f69f7baf14a33e2c6ff3ee84ac6fbe67ad18c258716fc997de5c5bffa8ec9abaf47e6e58974720c3db0273d3fefa4f52a122fe22b0010bf7fe1f785cc614d2ba8b03c3510	\\x0000000100010000
21	2	8	\\xa6908a77f69fd9613f7237d9c7631d7e149b441913c4ca87b256613f08e4bb0360fa268d84501a0e7bcfeef7ad030f3bafb859dbc85fa7acae248aad28401904	14	\\x000000010000010098454e1774b121aac6e3319e3dc828b4ab5668210c06fa181aaadca193aef97c31162234f6e23c4e9a61c5a999e792c1cd963f64e67f2a34844063ea637c1e1c24f7a988198fad4bb6c42ef23be796f7312e073057e079df7b88565de101179cc1f2713e0a72384cf1d380bd26d43ac10900b7db881a6d4daa6ce4412b753bae	\\x83f7daf5efd754e19dd1c5e5f263f5b1398885b632fb5556e3358ce4deed6df3b0c1403344d6666030154a6bea9c181d03ddf90e6a83ba6fcafe23baf6bc05a7	\\x00000001000000014215fe13fb74d7bfdf7b34a3094bda3c59e2acc3baab90c3ad9dc887698e8d75a5a1fcd072ac01e3fe820a352f2ad95ef4ae03ddcc44d8c2d2b9c42a9a1ef0c7a1fd54ad82726a1ed232ca2bc87a2ac5ef14eecb91733ded30f9587f4d8e1272c4e74e9235f2fe63d4d50c0e266565da22379653b68be9a99565458fec7d25ee	\\x0000000100010000
22	2	9	\\x46b2c678fd830fa524b6618182d059865eaa710effb981528f33ada5921a3cf83ca3cb3c1c5637472901bc68e8f10dbb883828c3accad04fb69dd59c6ca8d309	401	\\x000000010000010004f1e75c3e897133c64f2cfb165e0757f5ff0cb825f68aafbfea5358f5fc4cc8b8f3a087cc8db4fb1116de001299113a8dcda661565c611b3c0a33c5e2d8c103cbb6752612f5f1161e1c6c1aa666e996f077ed9f165b7e6f4ac1e604ee350dccd4fe58041677072f13fea03b136e2b38ddf6a173da4acb777c20c4b432bb92a9	\\xccd9cf55b7d66ada4b4ba4b059c22efd2e9749afb08931738ef5368d6f644bd140ff96c4c1c13f0d0fde36b1ec0dabdc8235c9518e49fa7bf9d41d6adfdbfa0d	\\x0000000100000001843728b837c6a4460451dedc9f4c5a564cadde2093ed3e7deac3b06435a47609f36c09694aa5e15530fed2c36f60dedbebdc99aded93d8583c7f2b2720167638d0c3886500c7419517c41e4edf931136d535f09ff60e028c4699f91d360b2a375988d75d877b904b2bae6e3ef24d2232addfe5d4b1be0d92f2b48b2d22a1c68a	\\x0000000100010000
23	2	10	\\x547647188d98a03819f7ef88443946b4e41e737e4f73263e8f5caaee5c76ae84e25aff462693e98d174e24c23d23147918e2b120ce74bbecf376868061cfc703	401	\\x0000000100000100201dbae9130e9e9b35c6406f6474f04aefdfb9ab5cf4c156b4fbe8edf6188949e0bf6a8610fb5db00262cb513d32680f8a1b667d4a09914d07acc0f3de27d6fd60ae7aad54d1983f3110f4876830b688ba85a27f6b67936fada766b93c2c714889a07ce5deeace9b676b3690e976aae0736bd1850d2e79aa70ebc033b82b1dbd	\\x8a1098dc28a72d7e5ca197671830c00e22c22caa8dc86da4f58cdedfb45372abbb72907feabb432ba2298694bbca3ecbaad4b4490cfba51643ba073bdd867c71	\\x0000000100000001924a9cd2abb83bde2bc1ab95dd10bd7c957e914db9b0e3283ff63d20a442ec0f6f9a3aca98aae8a1902a7e259e6732feb99122574a6000bef89c4d899695c8f1cbb2ddba7688ed9ea35d61ad171b7e3e0ae7da13dc6af7a258469e933fd198d69289d1ffdf57e2c234e595dc9aec1a769dfb6379688e8117b2215333e09ee427	\\x0000000100010000
24	2	11	\\x7f1cbfeb552da6a26b27c5270a25225d655701b11c6decf6eb93cbd915da4b6b9c8a157aef392d892c916dfaf96d2cc0ee0eaa6091553310f7d02cbf78811b0e	401	\\x00000001000001006736349ebfb63512e8ecae6d7e63e4f010d5eaf99f64e7c49dd84c3fa5f9aa54578e451edea9ffe5166fb7ec8907d1beaf897d74d6edf4b734958bb69a09791c43a3959df055815983712a8a1044c2540fc9d1df237e1134b06d2bcc84ca248028bab2c73049ecdc44702643ce87f5ffa2005aa0d28068827a35578c0135e4a3	\\x977ce325688c9f06a3feb4689987e64bd60289d794e64fb99582ffc669f81e04013120a8db94fac470a8aa53084a8c3cd9e7d52927fd3148bb6cb194ca0392ae	\\x00000001000000016d3d84fc0e39e68d4a02514ba52a8f81164b6e79b662c4376459a9bbc6c0d38afe13f0f8071d0eb3e6e6fe98b502a254ccc4aa800c6163b626adee988cb4b07ee5dd6f60e976ff52aec18768885d223bd053bf650015f054d8212c1a2e2ee229e1350622207607b3c8d6b9a872b2e5588c5f5587ef9bb124897cc2d210dbc3a4	\\x0000000100010000
25	3	0	\\x77039cb67c09cb7f3a246bf13d31f46fcf1d4afabc5ddc5afb2ae8a343ae3cfb7e699cc5a863a474db7fa310e0ff68df2513bfd4b35e07da970584f53b72be08	220	\\x0000000100000100cf1c3b0afa4d48c7edec3039febb88e4fb5afdc20c88e4af41bd1b9ec0c27ca6c0fffeb81dbe552bf5e0e15f928e6173ddcde167d34c189f142c3672c1203e0a6b33a17751ed800242c363738b3a2ea196d4e5eeb6c520b21478bab7fd8ba9863cfcd8dd3425c7bdef39968826cd72b2ebd209bf9e48549e1062f73b1caf669c	\\x329eb20d689773d8609bc7bf011dbfcb9b20ff409c0ab0d45db5892ec6d4fc5340d300f6e58f252f366a7e7ca690efef961e0d83e75f0fcc55fed654546aa32b	\\x00000001000000010cf5fda4866bce9d0b9848e90abbec29c04868c188125d58b2c8925db05b86f6b3a15ecb78581302ad4f95bdb06da4a365ea0512e311f204bd01164c0f74ff24b45607271093d3871d90023c3ad94983b08ec06ce2f9db054f00212b161f516bfbe5f1d64f8d5cd1b3d1c029a75b55b4fe6e6044fd10dcddafdb0aebf780315b	\\x0000000100010000
26	3	1	\\x50332325b607abcfe8667b2cd13ac78c847d920ca1333c2ebfc064667ab69f73dadf33e62e88f6ec01bff1797eb6034a210be767ef904ccee5886b74fd350106	14	\\x0000000100000100c9b52fb9e39b1b3d6f1709cbffdb550550cc48c20ce84f5ad56c9cb1808268b8d04815da853080329aabdc9ea5d455a24f1e6258d15edc8592471db6453777406b8f50083b63795fa0549c0ec6e69994fbfdd39bc5cdb6d37598d23748e9b419a7964fa9f92d67bf54e45ac74015ceb4d23f31cb6b4e1446610be87ff4b48008	\\x07fd49a695db39f7e8ed4539af81b6a7a99167237d70c551790f60fbbba56dbebd56d6fac7c23a5cbc90f6c5ccbd051e0cd5df04fc756f2e383cfa6433722b80	\\x0000000100000001c1129f88984dd029f24a3782d0b0e2af9be9fe36f475e3c7ae55fb18657d06eadb86cd3d768cedaa4d8cbe9bcd5c431619d91e216e95210efc28bd3db5baf90653d7e965a6fe162ddcdfbd3237bd6b2fad772f60d424b22ae4281984bff0b099fa02d1f771896a97347e72df18684d26c45b463446a287f5d54e8b6d8d40e52a	\\x0000000100010000
27	3	2	\\x820b5fc50a87c43000f16808a085578381b31d40d96b9c979372ef13f52d87ec36bc8e5fdf41165c364319f829be46916219534b815fdc35cabd5c94a86cbd00	14	\\x0000000100000100323c607928f6c373640822ebb3a778202a22ba96ab1aa2cbccc2b3f2fafe07008b942d3e3ff6f4815ca062bc179dfda42d2b9d5022e36705d50f0000403f54b6035ecd23d5a50bc75939915fc11fdee0ab5d430138f51a3e169429133e84ea6ad6b98ee4f48e96bf84ef6e357daca1768405bced6ffbeebf32511832294d10b7	\\xe9c260548252322322ff235d55c1fa4840e9c7b13139cc1369adb5113773727aabd1eafea089d149cf209556dd7cffbe7134e3c0a974359a1bba39eaf4aedb1d	\\x00000001000000010b8bd14fd77e04637b923515006814a7a3b8818ffe869820cf73c89843431e05bf42914d0135687b8e43bdf5955f33c6434b9c49ebccb0b2198b96ba9154b9fc56d8f7f5261a2ec9385477f086ec9f6cf1087f3d6ade1cbccd0e46e7e48ba758c83e121222bee2f53750435a32f4698c9d56a720d295365efbf0bf56aedc045c	\\x0000000100010000
28	3	3	\\x767fde20dac6c33cca1036f54e2682090d93cecec83eb70f6b3af1d0d30cdaf3381539e07695755634d04a245751368ac4f4daed8a3d48acc8d3ee4cb3e96f04	14	\\x00000001000001004439cab77145c5cb425b0402739bd8d3ee3f86082a2755c97c0a6ade68fc78c19b1f74e2193b8644ce1ad348a279830442eb48fe2a941bbee49b9ace8863bc854cef77b214d655c44ce28ad56f9d4a98a89ef9980a063656ba67c83173fd0b98ef12564574c654d6af132d7af0fd8a3a87445487d8d1ea10b2094012f66f8440	\\xa1b409f557086aee2a2fd7eacf8f5a46083130151def2343ffbc98fa652aaee94369da277c96b6ffeaaa3c5817232758ba10741b5821403c27050927882495df	\\x00000001000000012f52dbfdbbdae6d8ea330476a2ad64c5a912e12a78347dd3ec30037d786e9bb3145b1f8d11988609e9537cc24b99e8a75299c01bd34877b34cf3fe08dbd423351f5d799b29755016494fcba61951743e994299e33cfe3559551fb87bef6675ca0f68ca4b2eec386439e5b1bd7a2010b73d698b5afa520559a7ef8dcaee36cf81	\\x0000000100010000
29	3	4	\\x7fc542c00c2b5ff29773059e4d1a5c45b295d52a93922823173349a028e0fb8c0d44459d96a79198414595e8ae067acabade1dac51187694b2a21cccaf988b03	14	\\x00000001000001007b45b4fc76c8feecc90970daf6d974751853e9e77cf006d78e8815aba8e5b5823dca918f6fe50b64b47674e88748d6928a7d13a296d39933d336697a90cf8bd516265cd6e2216e15a6cc022f0dab45847dab32d94b2bff4fd63047b4ff1b05e872265304925c2f586fa4d9fcc8674941b2a94ac80c1fa6f4dabd8e5de1e55151	\\xdd564107f65cbde57082192154aa46f0ab226049d9b02c4560323d2df6cf9c5015f7d4c43b9b7a47924cdd14c5715e1cbda0276e1562cd67dc1ed68f3d223e00	\\x000000010000000155a830065c1fd9ef5950d84039c0d50c4daa88d00bbc6a461621c9419a1e8b27f07f0a5a36b577e30bb01475984cdb1ef6f02b8b7af61e0c377b80677e9801c711855c77d6c4a77caec67829df85e415d67442f211751ec93e6c61a0eff8c9d95722f90f9d58e2845dbcba957c857c772977920540c202b94a1d7d589a61c427	\\x0000000100010000
30	3	5	\\xc6b6695d87e620390b6ec1abed99a79ba105ae396a02b5233750fbb31b5add4f69f78fb35a2e79be68f97e68b18d07d437c13477ca7cf755ce6ce0d924db500d	14	\\x00000001000001009ecfc2ddf2f3f7acc93c7175f85894a5718a7098d42fe7e31d12b4aa8b70ee881da1adb75ca20e3db7d508d1b9bbe1fc8a05d95f7930f907f9d927facbbb7d774dc30991b96ba536e96039fd9eed828b559d4d67c4b47d023e682d0c2e74873ba02a1f631219bcee1ea07bb3e380724263b4e8acf1d9e2adf3dd6e1a5fda989f	\\x232c8e7aff40688be6d6dabc956d37e504f6bd66469c03079a5a766624be18fe3523b9fb9acdf25d25c65fd2de2612b407ff4c46e87543a7f97ee48d35879f74	\\x00000001000000016912b7055fedd12d3c4db0a4ba45216cba5dea91c9505d68aeb85e2e9e63a1902f65a85445e42fbcfe72cda74b038ce4a107248d1dbf71665adb3d21956e3e46410f616d60a8bfbc859de7d86db22b55d20595bc46a78860de53809ffe075b1e4ec873c2afc3b4956a66dfc8979a531126a379d4b3e59366719a2b82b63e508f	\\x0000000100010000
31	3	6	\\x38fac70d7356fc376ab5c1981e9314b0a69decace28ffa04b5896e1f8f492926d71cb31bdcf81dbb037f43c548dbdbc647a5003ea1a15d970fc7a9c1049e3601	14	\\x0000000100000100a4a227f80efa62be59aeecc8739e9a0eec084bb5aa2c1f2a4ba18c57b13c7fa8a7ad18b37b1588f656189a835e69d4df2b3f44943ca673aedc38c65807df3066b174592fd266d599c46c29d4aea9d76af2298a3a40f2e694acf28bef36017893293af272f154b6169ffc542bcac5afce802812f3fda30e858f0c53545244f77e	\\xf97653f5aa1fce2dc47cd3dcbd90e879ab3f02894b6f03ee3028d0dabfea55fb1899610b9894fc626f968a789b85d9b259022c29b37fe22200a966362090185e	\\x000000010000000147933f82c6faafc70223e3e0b9e3b1eabdfccff073c8244aabce321df5e47a8fb57fbe28699fb53e2aed7496ebed98ccb2c47b7d15c006a9a0d775a00384226529a90d3335970579366cc8d74ca87b43ea81dc6391733e63c68617fc716e20901aa33e26d568f21ebc4f9fe9e9db7c4eb6b21bb6ca0e58adf9bc4efcef973b49	\\x0000000100010000
32	3	7	\\x641329ed105c2c3513c0a5f75c90e7ed1633ba41d808b6966abcd293137e0bdd252e34df7fc8c9b1c5295976a2d7ddf5215fc9790f5d96b12304914f2b501400	14	\\x000000010000010046120cb9e73d2ef3213dc8f7fead83fc385823f7682f3054262b1e9b57fc27da5765977a229ab838a9f32a6b66c894effc695f60a72839c77491825eb2a41823235aaff4c8277d82aa33d04133a5182491634154bdb87b3a66696f37d422475d9660c93165615e87773572de288bdf056427007156ae01bc51681df1a2ee6848	\\xdc8e35a12cc9625b3fb4a8ee674d91a1dc976d788e33749d9cf63a9de11ed6adf1b9a7efb8d7f54b08a6cc5ccf294cbd24a47982eadf5f05a2344e5a311bf825	\\x00000001000000014e14dae93b91626c3d10acdda2a32af51782b3f823f1c10692e9ac8ea990a07d7778a1d455758d1109bed42790416f1ba48d004bd697f72649dc76ab0045ea26c258718b234a019fe66da960ced2062461c83dfd8e7b207effa3add65a0bc9f274742f82bbd55c6b8b97324f6df8308babdcc5f71bcefc27d2e4178fc865190d	\\x0000000100010000
33	3	8	\\x6fed5856ee9d8603c2424ce1c5e7f63d2ecf3a5741d6ba669bfc9558f6b98b920a7b26f0b75f66afe0ad236bba255fedb9d486962e1e2d69acda7c1335b1f50f	14	\\x00000001000001008507bfdbe2bdb7ae560b819f360db1e977dc64d183f804610b0bcc95dea31db506a91af859d4c248935290a0c89e1d9d6d8bf56a99ea6310620c05b064e3da45fd5ba7da7e75559c2d10d30c78b808fea3a84506eb81dcfdc589d6c49bdeff46f93c9c1556c748e22cd12236bdab039d0a8e17d786274b6c6a339886e5a6963d	\\x1dc88cb835f347d04015eeb54ebd07874640fda70b2e9af9a68a302dd0d7de2076242411837bf199a6f54851ebf0b4b01439117a5eaa67358271b87c990358c7	\\x0000000100000001acc1cd2b14324332ca2ee6d648ef06c92fec4b3bdfebc5ebf753914e86d69ed7335b7004d882f1815ad243c475866b4056c58a1989c89bc5ba6f5bbab6b5d769d50a4f04ae35c50945dcbb8ce1a7fa8c80d45fbc28103156aa9ff4ecdc6f7fe019fb5cfd76e287824d53d22b3cfa7eff6e17cc9abacaaa48675cf54c23275fb5	\\x0000000100010000
34	3	9	\\x86f46b22130b973f02050f211a8bb8f0a84b5134afbae83f7dbf6bea13a297cff594a9d9341e219531ae04344562fafaae84524c4038f05f9d57e61357560801	401	\\x00000001000001009aef75b6c4f5fbc9a8c15959e33358ccf5523082886a625354e19b964a1ff2f8c5a9c71ac29739473589d8102903dcbf67b23bb788bc5686d4cba705094b4dd81706f4b5051ec2d328fce4f998ad394c48b19827262bedad1a52525f85ccac2b4c6c08c84db3f1900f6b28ad18bb87a817afd8af7456b613436a7e8393f6618c	\\xac85c75f1b752d9cf6f1ad211075c65383c9c664a1321132b557a591ead984a5d9eb1509828c525af3a6153ee125f01ac4d83917eae840fec51bc3dba7abe5da	\\x000000010000000184ce3da47f13d4b2684ea749694d9621fd02e9d9af46fef70643b28da321a3926c5b00732f05e7f756f307c645f244dcb8c6151ffef25894aa52b1877ad155f29a413d29c7e11014ff93049aab0bef6db0fbf84c65ff75d4870781df603c8202e721c241c394e225e8f8ab499b11044b75523132ff419efe38fbaf3db9f99788	\\x0000000100010000
35	3	10	\\x4c4ab9af9ab87469fa5847bf89ff185a0f6618357d0fde52fc7d21f8cca0523e76ed06e3b77da2c72972addd08d50afb36a09563aafa711bd6a0d0ebec119b07	401	\\x00000001000001008b230567ab024f3d057408ae5a9654ac34920e379a1cdf492aa4eec5da15a8c231da9ea6410b2c853a47c80c70877d3d162ac4bc71d1dc55e892932083255093b1ae3ae35226f2c88c5eb63f9add36ed5c7449c5c855b9931f733aac8849b08409aee659814707fc9a91efed97624d8e4cb2beee7f0e89e68d4674365b289ce6	\\xa0097b1ab426052d64d8e870c38dde67758f5c7ca12afad51e64b6458b82a8aaecdb0268b541438e6c6025ee150625bdf1df980a8ffd0dff425dd3b127a9fbbb	\\x0000000100000001674f5da9a91115d59182aa769c9ed804c02bb5df3d0914d53c99f50a5de37757ec8de8e0b6258d79704d46dbfe2bdbdfb816303b14c573bc4a4db20bbf86a564af02a6c668c981ad2863e21d2bd4d7c71ec031356ef73f01e061630637cf1efd5a791be76003ba78dd841e02aba0240a3712e17ef500c6ab83fdc8413a5f47e5	\\x0000000100010000
36	3	11	\\xdb5ee5296664d7b47b3ab4dcc04a8b2fa8a025cd0394af94176dc70934c9acaf2a89100a6eccb152980dfc8ad54ba6e92003a1ab6e428cdb7687574541a1940f	401	\\x0000000100000100225c5423b9cd81b62b1d6fbfac33552ba1cb17b812cade0f3f225e463ba1ca5f4ba79c79f12a37c4ef522bdb47c43edd96fe00aaa2e8fa19d1cd61721633fd0aba4341bbce9f1a0bbbfaecc1794e2f033d167a8dbd23920bdc4bbc4a16e2d84fbfb45cef452384e4a1eece547d7859f00027a01b61961887d45649be84846c1e	\\xeeb1c709467ad033b53e26ac16af4ebbb1c5cf3a19c2949581280442a1e24755a789b6ab82630aaddafc27dd5c0c4db7e38e08ae6ac71676b01e9b787db9aa8a	\\x00000001000000014865bd0d8f0d292a093718f5dfb079c909d10b10239e7db58b297f6cbbb6a2fc6913a04eb7c71188ca6253b4c1068e6b9718d68942dab77c304974ac803d6723ecc912ce98abb20177e031b80027e40045c766c3bcda3504be5c68afaddd188be25d076aacbf09c9e5cd8d9af1d4fda8b3bb5f81ddddb3b0713c1919b543e40e	\\x0000000100010000
37	4	0	\\x9e90a98796502866a64274d7bfb1138bd8c202db542925842e28d0e8b198762a0dd04c9f26fb2ec763824816cf230fe114290e2f6389797730159b18385ba201	369	\\x00000001000001002d31731c0cb9b721fd3226b802a82fd877bfdbd9e32f8f27c358bfabbef2a6303b3971432974742909887c2e82cb2d56ff703b7f80fbe2a2b4232520f0a9729feb63a002c6e66f2f125cdfb379e56b89f67b484290c299b8444825fca8f74fa0320fb07e530b123d817cb51f17758070b9f1b0a2e084e20705b50b2dae1d3aaf	\\x08a7aea40418420b23ce98cc0843caf4781163f3aeaffb7c8e8b3d05ee9fc11dcde625a7a331c792a2d7abbe027119c99e6dcfd791a6d8a98330c8b762b840dc	\\x00000001000000018996501c18df9f21d0c9d2b234431ac49e806f9713920bccd2183176e22e6643eb295e8b25869d33d37e3f260e5814c10bc4b646185358f462e6f547e2e20f400236b269b4a19948e1e1af43e98c37e2ff8838f774d2756ee3037237fb3afa5ab69ba56d74215ea9b0192ae270faa5b44518859ab3722e9e1c8ad9af79588a10	\\x0000000100010000
38	4	1	\\xa94e18a3d3822fa206ad716a5b7c1f17f2cd8f512d6330c9f8642536ea6bdcc872e6bfa3ccfd86d6fac0caedc604f25dbe513605d878f7a544b275d8366b6c0b	14	\\x00000001000001007c892b3b60172c1351b44b2e20be07b3daafd1cb7534043fdbac3067b5fd47948ce925a3a0b0d18265eb0518ab4346ce5622f9df8a16c7c07fc87715fbd5747f31c4a48111456bbd5c5ad7f49cc09563603ab48165b50c11a54c7f97ac4e2e6d9be47ea3f4f653663456ddbdde2c76129ac1d46073c59ce8e9c586258895ceca	\\x1d9251995305e544b9f65fd8838041de78bf6f8ba2594ef1faf7aab3ff7177c57634d167471560ba7ce0a0104780c3777ed02f36d50278cbe417cbac887bcd5d	\\x0000000100000001a99e51b15f7631c3bac063911f2120e20b1c80586937b3b4228568ca09ddfb93cdcf127e169b9d903bc2059cf3ea5b46735a813672cdb7dd8b4f7ac8481c60e8a840f206fe9bfd8ac3692e4c0704a487350c8d899be9e676e012daa82611cdfb1868dbdaceae5072fa283e74d634bba857eb5dc9d8262965150817e0754260b6	\\x0000000100010000
39	4	2	\\xd66097af25a84f31be8bc27e650255d92e3d07d0827341ed9b161dd87840dfc04809802d63785461a77a9a7f5b2e51836951744fa0a5f6230c43b266e3eead01	14	\\x00000001000001004eab366d6aa5fccee5ef1bb213dc481ae9df65f759df98483ab46af226a203a7814a1a272a469df522addfb696c0f060a724bc518926bf6b97838a1acdd6f56166b3a89d71de17c1695737bdb3bbe898e033c8c0f3891efb43bd315179c1e91c687b0a293a7584cb2dccd746a54d6a9d4d35fc97e896f8594f99ef275d797c58	\\xeb05d243da085c2cc85c7f9ad6e0d4557843821dff79a5c8421dbab90f703066a3705aaf8ecd01afb3fe29d5116600ce8cbf0a45e5237d9ab622ae8cf7a3447f	\\x0000000100000001c83fb2b3c035ab8d5de432a4e405ca40d56299a813cdee2075911ed1e88659a7ae94956843aa7fe59e5fb882c8a1a6500279312c7fdc0c3d67e523e16a7491096706ccad300a04a554aedd0eebc71bfe959116555b6feb16cd4223fd684cf2499cbdfc894a3be5c89ad10c41d7c34e7bad8061cdc782fe5c592ea5500fddd761	\\x0000000100010000
40	4	3	\\x9d3a5d964f9441c23089ed0aeba96a405eaebf1a39bfc43b513149e349f708f273b99416afb5b5b6b4e860e70ae7108751c90e722d11b9c3db1dd32fdc929708	14	\\x00000001000001002dc91518c7a4f23876f2f36b4897ac0b30f26deb88d164dd04774a4976c889ae6bad365c23080f6d106df54d7014fa67c81ed6156aea2eebd8a940ea0315900d2cc70a53fe0e24e3960d51595b8f63a32dfd043a2de7e9eae0a7bdeb63ebd3cb5602334e6a15d1cec2475caeba30003558b0100cd1e68f9912bf59d49f1f9bae	\\xfa20a450f890b9a86533d39a2163fe7927811e2add0b815aaf726054afb5c5b84bbc21dda18a2638e80a756a0f1622fa054874e89dae9e6fa0b8110dfbfa60d6	\\x0000000100000001a51df4e547cd119bda56fd386f14faa87d6c0ab78381734c31b7379ade256b546a69e888675d529b50e1693e214c5f03a0c537510c4e3b50a5946f1b7df3c9efbf84cd0322e1a0f4310706369687dd2bf04810ced3413cf5bab91f1fc0a0a9763ce96a20e8e8cc151fc6af42ef5999c36a369326e2566eb3fc712b1b59bbb2db	\\x0000000100010000
41	4	4	\\xb7c1ec206e60e84d3aa46dbfa70efea18a3feb2434b4abf4ac8662ae830b98885490579d0d1b79e8c6e3aa11767e2ef2130648b89bb723dcf238d7e1b8b3e800	14	\\x00000001000001009d75c3ff8a82a29ff6ee7ff98f914ce851e12674b7625492391c899a4daa400d5f931ff628f59dc01593a8d3b5a53ca62f5b74e04cf9ccab7f856901c66401416219257f199d15a17777d5395556e0b5f1793b29bfc80c67c22a899e7301f5edfe8adb180c23c9104c1d46dc136bc79b6dbdf06714ecc1f22eb981b914e853cc	\\xba832c7897ddb1948f127f797b78cb19c002d4fc85e34af1bd1d56426c02821d9849cebf4e9324aaf2aea4afb0b702626ce873b6f9dc27af9bfd3cc5dde487ef	\\x00000001000000011251fb8aa0fad9fa44ec59526063aaa22552a6de5439beab9343b77891a1d7d8238cf75bc8552c0df86508618822f2d940a33ad10dd3592ffdba179fc2905c6caf8027a4d3eaaf4afb78dd7c590280d94ff5a05132da3698b8a6bf9f350d9bb405fd92edfc0a3925deabab4b95d688b3513e40f92df656704d89742d1533784b	\\x0000000100010000
42	4	5	\\xe3806d180f9f3d7060e7ed6820e8a9a9e11e38eeed4fe08184b741cc2b0473b95cd7e12bfac7ad5c7b420a3ad4621ee1eb416158be1fed8ef4c1699a2839e600	14	\\x0000000100000100aac7cf4abd161621ef9874768d74b85519a61e1c742aae5072eaab3642db74c1bb2797382989713d58b31ed28dcab83cec8c825ba6bf1cd48e390bf588a59ac4c4d84b6b1d2083901885ce51317e24ce4058ec46ce662218352de1b9315af8ce4f761a706906a6d984703a192ceb6d4d59948406ca4fe345c265542cb099655c	\\x373fa75c72973bdf985d59cbe901e2bdd2a3f16086d1032c467d599e291fe9896519bb058e6ca63fb58e1de58c74671bae831578460f385305a3801d95cc5de0	\\x000000010000000173d5e97f2c58f5bae2ece15ffa469943a10bd4806033e530506d43bc450a3946adb071f9c509a4ae0c657957776ca0d25853d2ec4398d1efff231418b2e6a2cb8c4a9b660223f837354ae731b8b42d1a2e959f7a10ce7b5fd260e9ff9ee055588d4aff0ec07bb008dc8078dc9a1975ea61879ed45b69ad96d184a83959b65688	\\x0000000100010000
43	4	6	\\x4e75c835d6c117356d0832c6e3e8d3bc212d55c76acbd6ea4ee233b076f51e3e3260d5f55bf300e9565d27e82f557aa89de527759541a15e3bffb33cbf09b003	14	\\x000000010000010067fad54dfb597bd44eaf8de360e876b0002096010f8f3664facf301002651ce3296703d865283758c3a91a07710a890dac4d7b189cc6b499db16c438b5c3a7dc23b19e389aa335c6693228d41c76f954f3420324b1a710e0e7010baa85a781e9f2a461cada9e2f96d6452003e630a6fad6eccd0f794925a473ac2ddca7f421e7	\\xac6b7c5a3590e5cef8b0bc5d1474ffa43130d1abbd81a79fd94db0d1d1b726c9fec25a265944800c995d0d629e6bcadc597e842ca38cb1069b83be50d8c9055b	\\x00000001000000013ded3e2df4f6600b18b3bb9902df11be5d5e288c9b77bfddbb24e69ff478a28181771e747590074ade3181797c5fddb1c129368a56c961a565f30bd6ec83adbdf099303610474c560ca6e4663e0b3e33644b1c7758d9c4300ab86bf985e2e86c7391ad7510c6757eb04f6a42fad1afeffa5d32c815023f809b2aeab79bdbfbfd	\\x0000000100010000
44	4	7	\\x2e17cd6a4cf85a4436738e259b747830613d91f079c7669a0df0b21893a623fbed2f1d1b364cff176e4d5de19cff5d3d444c446f0a22f62d3e4dc9ec692d350c	14	\\x0000000100000100aa5a2b7a9325b8187f576c6a7dfadcffbc3c2f8472dc48453332137c626979e45e7ea016746620756f691225bb8df073c2eb2dc33a82bd316de034cb992b5d4b4adbcbfe185c16caad50d310d3c4e1424b0b8f0467d764e820007ad2fd12b0b675a22f1b830a063a56328c8298465dc9f7c274420966a0e749c54e100c543397	\\xd96f79d9aba5738016b5b51c15bc6c93b20b6f6dc87c214cc89b75db3c6a0ffbd74cba180982181e46fdb90f6ad796e0767ee04b4a6675dd4022aef413a795ed	\\x0000000100000001a192afe12d34aac2c633dbb9c905031262500cee07db65a482611f9ca759e18d49df0eed1abfb4bda8bc383fcc8fad5e702272ca15b3f9ffb8eb27a5af8d4aa58b83c4ec7b8a43466bcbaa1c0a64797acbfef57c65832a5c0c2ddc0f4799560906595bbc337bdf74650ddc7ac9aee7eac7a14e9fbd009babbef66cb21bbdd1ee	\\x0000000100010000
45	4	8	\\xf8931e156d41a87ab41fe4b284028caf9536442fb48a544cd971f1335d60b769e8c8a3f9ff256924d10efbe07483371e99c3a6b7e2eed47ee3c69de024921804	14	\\x0000000100000100686c0e29323754ad0941f3c447bd6ebdb9a70b97fc99553fd7fe73e8c114008e9a404073e908c4a2d282ca41e1e7cd289f770bb36a96d6e5c69e979a201f294705a5aac3a250da9c9d7a53e9d84d1270891a3800573d54577f80b96d32b9610c7179e535afc693fb00d203e4732d233b95abfb65c6817a5e64c810f11c6264a9	\\x3b5304ad8cc76a2be148dbda263ea5f2cdbf85020a3cb7340c74ad6093f41d501f742f2e1b117e7c31db5248c9f5bf8ae9c1bc51309ce683b5b24629e1f97ad6	\\x000000010000000107c2b6c53c13f2aac8dd09f463ec59408ffcff196817b4ac8a1aad6c5804ca05b48218a2993931ac88566261186351546ce8626348c62b4f6fdf41c6d7641aced3de2997fddc9c547a45cf2bd5773078f0a95f071e0b421b1a2ea85dbddb7a852c226fd6a2f294a15256436d3bf60b68e2c08caabf887ab27898db1a90563b5a	\\x0000000100010000
46	4	9	\\x238c5269159e134ed1d41074b1c256933c7356d636999400bd245ecbf5ea60e5dca9238bc02350c1aa2918a4888abc4597c54418161287100be663ccca0b9f00	401	\\x000000010000010043683423c0c3117350025d4ccad2465ce8924c6ee91abf56510e2b0cf265d68324515b0d0878742c9aad4eb6c98a8554f51d5c0cfd6c46f893897067f3cb3f5bb864abdd62a15946078c28c7847bc2d3296d469d1b6230053c139bd894cecf028165256a53644e68834dd1bd0445199fad1fd14a07bff2d8fc3b1061505916d1	\\x4f629000f63ff04281c0128fbf070cef50e213ab03372dd61ce95d56722b8faa51411bd2edeb8be80c1a5020fdfca4db6f155eff64d2ca588b76bb2769b78dd1	\\x0000000100000001ae647605cfa6bd3ac515b1efc056437845a15f6bcfb5877c9a58773b8bb63d8c201257171e3c3256b2ee15780c9702267237189dce4633eb09ecfd7b3ca7c49029c6dc2e203e9b89d70975904804bdb8bdf43e260fec45c178269faec035fbd052366ca287dde42678ab3d73cda3943bafd2ac47e6ad96d5542bf850c57ebd92	\\x0000000100010000
47	4	10	\\xb7bc4d095e6266cc3ce4eb3de296ac14f872d69df2c24ccf14efc0fc6dc43293efdb18de484e0bd3b5604ab9a97b01aa9a3e4da654619778e5638732e073090e	401	\\x0000000100000100785d3000b16d26988dba904a0f6fde95140364252cff66fde4ff5102a1ebe783dcdfb8626df9b60e7d1ebb14cb94af8ccd7cf0a4f015195f9a0ab5ad2df4ec69251c711f6207a19fcde1dc80d309d5363edffc357b7fa1b2df437f75950c05941a31c37f89499daf05dd0f86d1178688f3c6ea724f291cc8fa4e075daf63941a	\\x507df1de2bea2e7baa5704ac13fb6aae8bce6ec5b6e723f5e692995c6bf3127ffdc30887981e8b66315bb52c43f7056774a57109424251ff35da45d87c2be3fa	\\x00000001000000018a55afdcb7d9696fd28ca6595986487ee708f3c4515f69fc382c602de6ee6151e2b511f976729d5a152da7d61cc86565ac5291e87d2c95c4cff8e29dc48daabb327ec5028527533102a308045bf50163301b755df0fd46e946768bae5deeae9d7c97b5dce10759fbcb0ab38780033a976064cb0b2626e13affb2f276d65d1148	\\x0000000100010000
48	4	11	\\x8998979077ae5c3f1c58ce823b453c371f0e0c2dc06683e043379d58f3fee048920c49450ecc4f47d378df0abdcc26cb908fb77f91b6225327452c22f5386304	401	\\x0000000100000100597d11ad2efc9fd182f6eb1689a92ae86242ad9c99e545f59fe3f899db1e5d984fe027dd6c901250e6be85f5715a6d858909e0e9b452dc85ebea8cab1c7237fb526a1ca0df714ee5680cd03c26e4eb6785e5f5befb3e1c7f362078eef42d4af2d4a68c3275877eb9b213481ca4cc9c64ec03df4aec6ea673628a467bde2ede2f	\\x538d850867747b77e49cf2148d9371a280ff0479a8ffae25c4cd9d14d6ca2bc46a60331dbd3f0b3536fcbf537362539858047306834ef649b8f50960908136df	\\x0000000100000001a34241a1accaf0ef6c05ed3bab85392c3164f650f0cd31e66f70053605500b0043fc039d05facc45608c82e1bf36dda50ff9a82c4c6d7c095d5c04023065911095c87068798610aeb335777fe5e4420c5808e159a6ed10ca3efb6c7328b384aafcc905ed74e2b61193e8e87cfc4fe0c0a6ddb2b9dad722b6e36ea9891d01e13a	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xb972f186a74cd1eaebc3f2580d2d4d5c9da2bf95fde6449d587be5368595bb16	\\x555874b7692b2305499b5e0fe8098b437e9ebe48be65c3058bc0f19eff44bd7af26b0fe3e97be479a729b6881894fb363da491291c2b2ab898852ec37e99c0d0
2	2	\\x6dc7aa218cd85c863bc1b63446a6561432b637a8242dc630951306f45c60f424	\\x5532c33477fb818830829c58d9fc4235e5c06db256feddf7ad0e160a9d720e2a5e274756df40e44f26515c621be97c6cc7bcb02866e6d2b6642074c184fff49b
3	3	\\x3a8eacb44748a5aa97e26fd8e15add624115267b16e7b5603bbb41971a71f82a	\\x9f09679720346df1360f0fc34bbdc31fe7005105fc08de39e146cee0566840f3fc3faa04fa9c61151de8070b60e06ed9b6b7fd14294a4788c2d52125ab356a55
4	4	\\x27e783516dc89ba284f7ae63e0dd859b1ae2713bec1c2b73fbeb64a3deb5da20	\\xe591b37f52189c914161643c4b3d58d627eb36afcbb1dbcf271e01436b9a415bd0fbafcf542889831a51d13037918e735316513b09f0db2fd381831654ace150
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x54390cff7d19b6e1f4038d7a7fe67fb6833aec34797411beac3e733bc7aa73ea	2	\\x272684322bc0e77fcfae950b8eca0ed1e23d4170d5934ba0b3215266ecc0c55f53bb091bdea26acb8586ff2da4e06b0357836a2788456a849bce8d742f9b6400	1	6	0
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, kyc_required, kyc_passed, max_age, expiration_date, gc_date) FROM stdin;
1	\\x2a3c700c8b3d5a3cb4b09cfdc542c69de5cd5bc4aa93af427fc2e1c919f15613	0	1000000	0	0	f	f	120	1657484153000000	1875816955000000
5	\\x4d65ad51cffc4c7bcf22eba6ffdda39b1425354b6bbdc132d52b93d4eec439af	0	1000000	0	0	f	f	120	1657484160000000	1875816962000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x2a3c700c8b3d5a3cb4b09cfdc542c69de5cd5bc4aa93af427fc2e1c919f15613	2	10	0	\\x7ae90b82b8513bd202b46339418159ec03bb9a49991e79eae09d64227bfd867b	exchange-account-1	1655064953000000
5	\\x4d65ad51cffc4c7bcf22eba6ffdda39b1425354b6bbdc132d52b93d4eec439af	4	18	0	\\x997e14222bb8f8a0eb20daae1787ac97c0003f44ea3741d0fa7f275e65b9a0ab	exchange-account-1	1655064960000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x5e6d69e1af8049377e58a84b53d6803ac1a3b07c9ff4f81489c46ab921033f588b4d047c46580e895bc2ac25a03bf4ef74f4ea5a95554529e1036357470d7189
1	\\xbb603fd35f074a1606c02bae3b2f8ae775a40f6bca83488ae15b33944c8cffa38880064e8fc272d2083783ce8146875b7074a92a415e11ef55f43d71d0a31539
1	\\x6c5faac784216769dab5e2de58bb00f3db5da49a6ff27e4bb2403a519f5d3b13f134a2df4eb4a9a8bf08463b4a142c9d93560eb2a42f49c3ffeaac4116e1f45c
1	\\x9b9b75d6d7e26a3425c4a2a8dd93a731032d8539d5eacb6fc961e0ce04fe7458f8bb65a1531dd94390ef5b8b56a32248a966c0bd4667a3cdf8646f5d620b941b
1	\\xd0583867871195a15675fa88494a427198c957e63d588801f2c29e6d7b117b7e9576c829370b292a5c39def68a1380c5fa64cec7c39ab53ac855ae16b4aaa34e
1	\\x3629b69da08401144105c5d5272ac31953364a33d97f84989b06df4f10ee842aa99efb93f27e1655d8b3d128dda5dbc050b423a93a4f76220ab0dd5050e20393
1	\\xa8688717f4993c83c219682e2501a815cd2dd3ab0e2b573f93a85c406a1a2e9dd617c3aa124312517ff8f084e69babecaf2e601e537d20d1aada595a06d21282
1	\\xdb1bbe99e1ead16cf9f176776acb1d4e5420b8cc990ee05a598de6ecbb91cc32a72bcc0e296afc91fd620ec90beeb95e373e26ec08a2356c6393f1d53c535166
1	\\x3371a6d4f99811118a6166329bdf7f4ab40f4ea44920b191efee91c5c8483b4ff0a60a5ed98a3bf812a944e3767912e83fa87411876568919572e99e9d2e8529
1	\\x191e5c25fcd9effd8fdca47b6f0b93d57a25be09572dc5102608ad37baffdf4727d028fc1f2346ba8a0672e54bac46fd3d0fa33e3ac7ccc37eb3332edcb1d048
1	\\x345b3be970c02c8110cf97d2a3eb78888eea233915f497234f30334a9629db8007ad41ebd7ce4c108cdae3c4a930ed1dc76476beab7e9accc58aea9f92d29e79
1	\\x6e4f0f5c424a55533a5e87e33247680727cb03ce27a9717fd634c7ca3464729b68291535ddecf6f71f62315ff7d4a507525f50a03e73d95661b8fbf5ba96a709
5	\\x4b9426ef75d28224642f5c81e3bf7428a513f33a067a7f194e88ea4640dee97dd1b579deaac251fcae5497377f622f0d9332f75e098ec0a2a69a32187b3a1c32
5	\\x9431e0a7aaf982415b486a86d0e70098af4c4ae42ef0c7649b0de1752c4c828df91ece4d27789156dadbc7fdc7b11980c2dad038b4b5ff37c7044b2b2fd6906a
5	\\x74b3322aae61ee4f61e6622d955169c896bca8fb69c091e4bf11bb4a99f3873c98945a93e9362d4811ba139b17b0a220a50644ba62d789c58c269fdb4813a7d0
5	\\x46106f0f7582626982fabdb623648d6ea8dcb65ee367120d81b1bc02e2ab4db3e561b594b1a30abb9f9badf7512cb6f3d0d6e7a05880f267cd45ee7a269436fd
5	\\x996ae8641093821abe833b05826e64e905e5fe52542963492b97920c5a9ba0ac88c00387b6c6058d7b54d14d583bf5ffb4cacf1cde93e788a550aec6b59c02e2
5	\\x251c8eda4ef28ab9a4cbeecde0e614f6c5a24a835e6977fd231009efe75588e38d87315c5226b6d539f29a9c9f2df046675373ef70984c6adecf7b17c66a3c2e
5	\\xc89a7ee9b0ce031288df0887562297853e76437924b59c9181ddbe4b1b8be5e84e76fa4e4722d6cb9d6a613f7baa961173443627e4f9c1d765b496b8f8da9daf
5	\\x06cc860127e7e5227ca380da2de7dbbad2a4d05406fa53db4909f4c1ee98a5b163f089900744815cbae259c94a00a2489811c650e63b8c44934b331f47191d9f
5	\\xbbc241637d24a3e71edd2880b9ce05fc95f3488d857e319c807483849cf06e16a2295acab9345b6829f713e08acbd4725fe433f2f957f46ded657e05dc3389f6
5	\\x470940eede4d655336132b3df9d023c730df0a8645276c7bfb9b9574d214c5eb84467277f492361979c9af8e8540f6d69cd60884e15953faf1f84d8ac01e8342
5	\\x1aedcc36af3aba1bb308bb3d66e7513419da16d90ec4e0db495e4bf7c35fc505757a46069c6dda8e893ff529249b48f711ff3f4313740d65c4dd1c844d8a52c3
5	\\x203933a6cc24d9b25a151631df543435b0f4979855192f23f8413261f291e025621641999032312963e9665200bdc8046b6375bb0b293f18b002f7466e7bde3b
5	\\x6e957c111c413b16b1ac6babb58d5984625886f3a1c18a296bfaf8d6153e76d148e6c36d03038bca864e09758245ba6ff18305eada994adae354a5487efaa02b
5	\\x35e4acc78ec6469c939c5778d117c454b9f31018105b8bf65941822b48f26d1e4cb5a1edef0476ff2363b6fdcb17ebd56fa8ccbd1d9ca8b7cf04d4470c0497ab
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x5e6d69e1af8049377e58a84b53d6803ac1a3b07c9ff4f81489c46ab921033f588b4d047c46580e895bc2ac25a03bf4ef74f4ea5a95554529e1036357470d7189	43	\\x000000010000000124f014aa1e9e91ddca3282e895129dd2b614b528413bf2af8217b0f5091d8f4e842c20e3d2cede721255eaf0b0220fc4caabec86ca5cb19518cff14cd098e4e29ed940fed885004d15337d0c63d30a4d62d09ea8062960da515e38ad835a7c5901989f46bf0163b23c192a6b610ddf3d3e1f8071b649a5ed85bb633f6b62d536	1	\\xc6d4276ed508a49562b7ee4cc3111c1ab6e1bac0eb7b446a9f832149065baf1106486914e79e01f2207072a4de7fe7c85b1318bf6b6c7b84fc530b807beb280e	1655064955000000	8	5000000
2	\\xbb603fd35f074a1606c02bae3b2f8ae775a40f6bca83488ae15b33944c8cffa38880064e8fc272d2083783ce8146875b7074a92a415e11ef55f43d71d0a31539	369	\\x0000000100000001425d5fc5eab292ffa40894680284b3b4f9ef9a1310e29d513e684a7257dd18afc20912097ca7f9c5e3eeab4ef2671ccc02c1cf84a7e94b731ff56b89b84ba829ab846f65bfc2c251b505c9bb2c40d5e6415c38f3be786e16578b0d9cc6ed7e922456638eecebb3ddb996dec1361c9f9223e4ae653161afdb2fb7d42ba6e8e9ce	1	\\xa5f1e49dc98e9294e242c66329c0ed0a642966735ee994d58cf65a2eb0e182ce47402104baafe29a0d08bf15ae782f2052f373867739ba1ddac85fe3a2ec180c	1655064955000000	1	2000000
3	\\x6c5faac784216769dab5e2de58bb00f3db5da49a6ff27e4bb2403a519f5d3b13f134a2df4eb4a9a8bf08463b4a142c9d93560eb2a42f49c3ffeaac4116e1f45c	14	\\x00000001000000012f055e5a1c6eb67da4391c5e2aa509943bb25d0ec1b0321feb820c58d1c52687f212416578885d295080603d6c06db417acc627d9bb3c3227b7678d4d8397d0f42bfa30142729fc42d0c0f3f681ea180a9e2f8cb11f25888d3b931169030bb01fbf6f767ec8115efac6ff0a638cf6c00f641eff4050e65b363311a3fdedfa09d	1	\\x23ab90b02f22006c7559933339fe01a997aaeebd784e33c445f0e8386894e785457df85413f69a77548bdae435c3b286f26a38cd3e1c4910b6d3bceb9d6a4c0f	1655064955000000	0	11000000
4	\\x9b9b75d6d7e26a3425c4a2a8dd93a731032d8539d5eacb6fc961e0ce04fe7458f8bb65a1531dd94390ef5b8b56a32248a966c0bd4667a3cdf8646f5d620b941b	14	\\x0000000100000001a9606997ceb971a4ca3916da2d5ab48ffb97d40a3fa2aa137622897a2c40d33115c2a6e354d1289cc50a9d3fcc4553a646dfdb1e6ee17768917edc0a87891e7b8aa7e0f7b9354a795238484c292a97e61484ef3d0c13be8ac0c6afdd8537d407c9e3d41436a38c1de67add153a49a6fae66005f5b309c1d39d920ed95ff5fcf6	1	\\xd18a5e92ee9c9bdf3ec9921c6cf7725df082e921b4c66beec235902cbf08f1cc7d0c2f338b45ecb063a21ade985796ad137ec9a364ee3403d2ec5d8216f3a808	1655064955000000	0	11000000
5	\\xd0583867871195a15675fa88494a427198c957e63d588801f2c29e6d7b117b7e9576c829370b292a5c39def68a1380c5fa64cec7c39ab53ac855ae16b4aaa34e	14	\\x000000010000000181bd3650c853fe6e4342c9bcd754d467dcc69109851b9fe1eaa486cba3d97593224a972a3cc96a676e8ce77fe749fbd4abfde7401bb985ac768e10bfafb42f33afbe84bb16eb706d372fd6f3122f831905abafe6055032faabb950fa6c23d96f37c0d4fb8274b3a1f46d1e3e8ec885277eac47629c8a82fdb9ff4a3208339154	1	\\xdfe83f8c416e3151e8877d53f7d7c3014ea522390fdcc9d77be70b3890e3a5fc60cb84b85cfc02e52373dadf10e5e6303e0b02477a3aeec5ccb20f169f982000	1655064955000000	0	11000000
6	\\x3629b69da08401144105c5d5272ac31953364a33d97f84989b06df4f10ee842aa99efb93f27e1655d8b3d128dda5dbc050b423a93a4f76220ab0dd5050e20393	14	\\x000000010000000143f822bac73d9e97e35d168b582fd13e18364906377f1e8a7940de73eadfb16dbd5203ecc86333be08d2747cf7567712be07837da0ceae1c8b18655afd345e211ae3947fa2028721781b1c00c67c8c56441f76a923452a95b6043cfbd39c975d2e00521a71d3632aacd064a26ab5294e96aaff3c7ccc212a0e584cdd1f029fd2	1	\\x861053626af5837b6e869bdb5822cdb675dd1ff2575c3f19f64e0e5171670b9870a1a9c73191ceabdf1f124677bcef3b5d14adaa86b76f8b99c702e0a56d8e03	1655064955000000	0	11000000
7	\\xa8688717f4993c83c219682e2501a815cd2dd3ab0e2b573f93a85c406a1a2e9dd617c3aa124312517ff8f084e69babecaf2e601e537d20d1aada595a06d21282	14	\\x0000000100000001b5ef0e2a8cf96f65e9b3a74aac3b2d530992cf1b634df11de9124300f7b656b0cd896be34530e50ce0637b2b6fcaef03f5e596e3b70320eea38153790eff54b430dfaf83e683683f291204ae3cea318a720cffee8aac7c36f285b2c83483d18489be2a1edbb3d199e260b714a06ceb9cbba96783850e2e024780e93bbec34e70	1	\\x7f611ff6a49221c896ac6d95a4a3cf5eb460aaa93be7d9d278cdccf239badc461cb1f32b8b3fdf47480603ab474fb4030bffa4ba4ce9c1ed8ded996d07a1140d	1655064955000000	0	11000000
8	\\xdb1bbe99e1ead16cf9f176776acb1d4e5420b8cc990ee05a598de6ecbb91cc32a72bcc0e296afc91fd620ec90beeb95e373e26ec08a2356c6393f1d53c535166	14	\\x0000000100000001354ce851bd69e63a21511f1daea913e3340467a309cd16eb79701b9435ec07487aeed770427e0bbd912e3ae11fa2d6d2ab4bf618d3f3d893bcfbe7d6b2e73a484da727385fc8be1344098290cf434a8f8e5198ba17d952c6f3594f6cddddc5adda104d8cccb004447023eadbbe0de1ab26f8f1f292ee4af3d0e0b3a9cd46fec0	1	\\x6cbad1e04bb7e88d2ca48678de98c4c09642b3efdf6c173fd2c48caae7b1f1c47662659662cb49b91f4d686a2a7efcf17cfd9282c89136e712df129dc94e390d	1655064955000000	0	11000000
9	\\x3371a6d4f99811118a6166329bdf7f4ab40f4ea44920b191efee91c5c8483b4ff0a60a5ed98a3bf812a944e3767912e83fa87411876568919572e99e9d2e8529	14	\\x00000001000000015f81d9705782339c5a511f62b01a091367703109e80e6b953441752da8a9336da7c2bbf534ddd200d6def1db0a93a14effddadc992a39e2f957d660849387e4d3aa9f1148bfceb2c48382665874ad8fedd01fd073ddef306ecaf8e258216a41f989f46383abcebc8603dd35da516b3024be6c2760ca53993640d4c415b14bd71	1	\\x2ba8f1451bb559a2d3d1aec7c4e6976780a00a04a7ad2e99278368d03cd518f9371fca7385e40b9458dc5d2b7dba70f379a8cbc7461eff51ecb70e6eabbe400a	1655064955000000	0	11000000
10	\\x191e5c25fcd9effd8fdca47b6f0b93d57a25be09572dc5102608ad37baffdf4727d028fc1f2346ba8a0672e54bac46fd3d0fa33e3ac7ccc37eb3332edcb1d048	14	\\x00000001000000012e0b75f0ac4ba1468bcf3243c349f1b9477b8b17252267b45e2b4ea397a453712aa1cc719344df50f44ae341dd98eb281cbab8d1b5ebd762903acb23e8a63fdd0e2b96b8dadc5925a175a0f626057f573aa05e61d764779860e07dce90371c77500afad0aa0a768c7fc593afd7604901ca72904533edcfc6e1b480bf7904ba8e	1	\\x3e89882136c0b2eb44c5698b822b1b01f29aa1a012cb3ef5fc3ebe0a0337096b288cc85dba46b5b1aa8d796f6576ef92639c3a114c21d604b7513470aeff7d02	1655064955000000	0	11000000
11	\\x345b3be970c02c8110cf97d2a3eb78888eea233915f497234f30334a9629db8007ad41ebd7ce4c108cdae3c4a930ed1dc76476beab7e9accc58aea9f92d29e79	401	\\x00000001000000011fdeb5f8bb5e94f2ed047e1de5d5ec6af6730a71a857e991342cc789bf547963471119ca37ddc75895f21a11bd72b22be0f9a5829e9ca89b3c696510324bd05339ebac058c1e1d79ecfeb9b43ad4dfd150401f45d67b957cd7d55601e3c21162857efc1a51affe9994b16584a5560859fe1a568992d9dc21616921831df33a02	1	\\x93b9a1594adcf6709099d098be94710b44709e56df854238cf95fa49e2f6d0d8d036a4851c5420a364e74644be16b51486d0fc7f813db88f9e19d37827536f07	1655064955000000	0	2000000
12	\\x6e4f0f5c424a55533a5e87e33247680727cb03ce27a9717fd634c7ca3464729b68291535ddecf6f71f62315ff7d4a507525f50a03e73d95661b8fbf5ba96a709	401	\\x000000010000000132317e8972b64a05a8aba725eb2656b3a5bfb6c4a8535f392ed0e90ddfd44dcd37d06466e5ee014fe40b623e93b6c077c4d0c5e794c77b936ad940ac498164d018da6515878eb8d37432b67bb83f42cc541424ef8714c1c3576de0371d090fb900562c8561db7b1777f2a7fab57492bd34e76617738d26c17492c31093711b75	1	\\x5c9dc60b4f5c242db9fdab0caed6301c1f0f8903883bb8fb4424950199907d8bbaaec614715b5336085a77a70d53798053383434691cbba51866677ea7596002	1655064955000000	0	2000000
13	\\x4b9426ef75d28224642f5c81e3bf7428a513f33a067a7f194e88ea4640dee97dd1b579deaac251fcae5497377f622f0d9332f75e098ec0a2a69a32187b3a1c32	116	\\x0000000100000001c4bf3ce5347de64905d7f2ebb068e21ff9563c05b9ec95dc0d562c9e18c49eb36de56c0c22f1d3567094c4cfb633f85ad92fbace512662cc60c2cbc8d7d11b96dc7d01b03c87d8a430934793837d1dbb630f9e1cb60abdb96b26d148337952a621959fa451e1a27f734b18c7375babed4b81b8de927da3e656c67d3221a2d424	5	\\xfa56aa5e2d327f9ec4ee4bd8a6e8ef53a3f6ac4553f22fa2f6b800d06f56f72c0a64ebad096134023c0841fe5aafdc629efbb4e642f9c845e324d3100d2c4400	1655064962000000	10	1000000
14	\\x9431e0a7aaf982415b486a86d0e70098af4c4ae42ef0c7649b0de1752c4c828df91ece4d27789156dadbc7fdc7b11980c2dad038b4b5ff37c7044b2b2fd6906a	220	\\x000000010000000165e96c392f13ac1cd15e334177693573f052ec4fcfe566ee1eaa16396a1d0030d4b9ff78a49550db35853a1602d1c864b7bce6d06021cb58d6e7fcca85b3c9d55cf522bc65f48458f85d8b2fe8d8e7819467c5afadf5b12a69e43e9b59f823e8051e3b2b84c01ccd96f32a4afe98c601b1009a33dd3b7b2845b656eac7a248a3	5	\\xb246876b8d825cb539aaa7c53b07bde5bdac58679197af220639726956d544397e994330d6966c7004bc213c142790ddfa26a93cbc1c5e45080c1bca699d8b08	1655064962000000	5	1000000
15	\\x74b3322aae61ee4f61e6622d955169c896bca8fb69c091e4bf11bb4a99f3873c98945a93e9362d4811ba139b17b0a220a50644ba62d789c58c269fdb4813a7d0	201	\\x000000010000000174269b84ce63168932275b9981369fc1df90063cfa04d5afd3cb14ef0b73177009197993a986aecd8c2f72b0845673519de7f8d1cf0582853662a503c9029c5f494eb4e4f83cebbfd9d8629209653e08b28eef8fe694f68482c9ff868c026aeee7e7718d3f2930c4b86b19c3b19f24021d59156ae3a72fcc6643e7417860d706	5	\\x6356aa0f06350e3ef7e800cdd782b22d231a3e74842be39a31e3b14d993b2a016ae8b1bd5ae5895f0a8e0b88ef314010d3ab0b3eb460d560d61b6c5451ca0800	1655064962000000	2	3000000
16	\\x46106f0f7582626982fabdb623648d6ea8dcb65ee367120d81b1bc02e2ab4db3e561b594b1a30abb9f9badf7512cb6f3d0d6e7a05880f267cd45ee7a269436fd	14	\\x0000000100000001ac1ae9e63bd1eb04e858eb5b9f903c59c84de4faf66cfdce042ad8e616ba44d462a4f5255ea4f549ee5dce8129160dc3ae09551af902459ab21aeeebd40bd04b014e6dc6f4ccb6be22f8f39881c19958e74e2eb6b1e571f849ac8f83edea4db5af8a087947c88e4282eba8e441fedafa6985311f25adb89276fca623bf0fb1be	5	\\x32a78866529864920e77913ea16e4b3a080a7aac79bf88c05daa9e1e7fdf03befb20e86909a4a64ea9ef148f6601c0234edb4483456119583914f200dd3a8706	1655064962000000	0	11000000
17	\\x996ae8641093821abe833b05826e64e905e5fe52542963492b97920c5a9ba0ac88c00387b6c6058d7b54d14d583bf5ffb4cacf1cde93e788a550aec6b59c02e2	14	\\x000000010000000192872622ed8a9e97b997ebc589285e99d4bc7bb6a493509d9878e4d74efedf7ae570fce0c527f8059bbd20a9fb5fbcb9c147e34ed5d8b134970488db0ccd5a1e54cebc4323621fad850050b599d427b581010021a1cf620485f5c6be654e3633edb7fcf5ac64d4983aa68c8408cfbc1748c4743e2a7de0958b9d6db9706bf878	5	\\xcf90303d92e7bc47fb646e73bb24a88fa9a1d7e0d59d235d87e15380cebadd0e2f199c9a9257b89b8d1d9f8fb1e67119e2a60bbe91724875def22bbf6f2bd10b	1655064962000000	0	11000000
18	\\x251c8eda4ef28ab9a4cbeecde0e614f6c5a24a835e6977fd231009efe75588e38d87315c5226b6d539f29a9c9f2df046675373ef70984c6adecf7b17c66a3c2e	14	\\x000000010000000175aaf5fb088ffada247bc7af1997341bd7c4a6254b260207973836464f17d2985d8fc9c7089ac6e34c86b4d9ce19207ba0619a45a90faca576dd825e10223577876b34a6260c4310156cf4afbea2e8981cb89fd6f8345a12d197cd7ab1113447c8d7b41aec0a6b2f7a5c41fef27c1fd8fce0353b61cc030f370831c98728c017	5	\\xe0b017fe519327138642b26b290e7eaa0110827e7322ae6190af2fdee38a4e2567dcd0c3b2122ff35e1226ae91b6366ed34fcce0884dd4d25a688bda0e9ad30c	1655064962000000	0	11000000
19	\\xc89a7ee9b0ce031288df0887562297853e76437924b59c9181ddbe4b1b8be5e84e76fa4e4722d6cb9d6a613f7baa961173443627e4f9c1d765b496b8f8da9daf	14	\\x0000000100000001208f08c0057630daa65fc19ebfee1a599434ec7ea5327c0fcd7c479309e242b79f48c1329229fa1022c960540e0e7e05facb32046afa97014ae4402640e82e86ef5673c38241a9e1677b5a4ac1fdee909ca51f7badc561733d557a4fd7967f252fc89865e1cee2bd33c7a9a74234b433b792db3dc8855efff1dce980841aa091	5	\\x10c1894d7b08711c9f616727a68467813c3112d7ae899460283fb566e8aa98ec2969fd1fc77923c1a2193e649178fa50dbb43662b9d72052b81751c6be4c7c0d	1655064962000000	0	11000000
20	\\x06cc860127e7e5227ca380da2de7dbbad2a4d05406fa53db4909f4c1ee98a5b163f089900744815cbae259c94a00a2489811c650e63b8c44934b331f47191d9f	14	\\x00000001000000018fcfdb4cb918571054166cb10b4a88bb25561da23d6a2898a2b42c62958d34d0a478b0b9d5b66466dee1209a8917411d53f2a3711808f8f5e06f7ed614aeae5c9791e2d281d713ccb049a4fa48ad183999af24368c0c0278f1950d95b2de637094a4206470462a3812025bea68b9c8efa57da1625674ad6de34af3bee9895e5f	5	\\x0438434e2a214c6e3360ef2488275c6a3deb910cf75d27c82b2fe84615ae8f69d8d40112763553583894ac3f2aa242eedf93fe82e7ed3c0de972805483cfa10d	1655064962000000	0	11000000
21	\\xbbc241637d24a3e71edd2880b9ce05fc95f3488d857e319c807483849cf06e16a2295acab9345b6829f713e08acbd4725fe433f2f957f46ded657e05dc3389f6	14	\\x00000001000000016c17d6d8690a4c5dbe3346eacf89ac0f483928dcaaffe13e508cf75bc96c2e00a186645aec92c7aa2800eb2636dad9a53889e17226894e38d568a62d90eaaf9e97f43522ac7c98782b846655380d51cfbace87614f76840a8856f6e5a18d2bc586756281f4f6ef341459543ecc58258710f7432a54d5a7c27e259ab97c7c4476	5	\\x63bbfe643b8f540c8f39dde4643a043fffe6c2de2bf576a5559456db01fdb8473db3e25d629227967a2ca99970fefcfea42354c4de46c8572139e869a035270b	1655064962000000	0	11000000
22	\\x470940eede4d655336132b3df9d023c730df0a8645276c7bfb9b9574d214c5eb84467277f492361979c9af8e8540f6d69cd60884e15953faf1f84d8ac01e8342	14	\\x000000010000000186e51845cafe6249ba8ad3ca25490fdd4c20f8056e3b880036b7c8c5e974d35ba51e837d9b127bca41c51676ca1410f37d19eda2c63c36e0f21c09c3904228d3d1439527aa0abfe7a65f179148a173be90509185b0109cae8a8974aba25995877a5bcf664108bd192fb38595f74ee0de3fbc4187799e6cb029396ed4d102fcf3	5	\\x09710efba15fad400131c6897b0291902eedfe84573ea484669bb2c766e6df088f26aeed21f8d17330905a0f5dc108122e9c0da17981d41a643fe65257663f05	1655064962000000	0	11000000
23	\\x1aedcc36af3aba1bb308bb3d66e7513419da16d90ec4e0db495e4bf7c35fc505757a46069c6dda8e893ff529249b48f711ff3f4313740d65c4dd1c844d8a52c3	14	\\x0000000100000001b2ac9ed8c9d264854fc6b0e7007a9c1030806664318fdace7208691c29adc3c97fceedd8402940da7231cf3c754e7bfd3706fe8b92e6b5645a43504c6f37a236308cf6782dd32b089e3641865d25aea8614121c008b14353aed651b340732471634d8ea37c5942809c9b0543fee3f4f8c4cfb2197d616eca63cac476d07f4bef	5	\\x0731706dbd16f487393fd8e31d59688d671c6fdf0352fd780efba691c0eb90f2b907623fa40824102f4a261865e7be0d2f523b1e9f8b9b67d2efdf0e3dfe430b	1655064962000000	0	11000000
24	\\x203933a6cc24d9b25a151631df543435b0f4979855192f23f8413261f291e025621641999032312963e9665200bdc8046b6375bb0b293f18b002f7466e7bde3b	401	\\x000000010000000132bbef96304f782d6a2d078aee85c1778e3228450dae96b07c8638b17da4545e4912fbac68b1657f708f549e3bb818bf2ad273a2d118644fab3137e1ee564ba8b3dabffc6138f72141ed4b1da796729ac269d0ab182c5a293c4370b638c7b441c31151dfcd9058689bb8203c3f0d55b39ad515636a28641b0203cd01f2c09db1	5	\\xdfe85e26e12da935a9f2c1bac02cd8fbfa3d773f9a9c7d1669b19dce5cc837503c2bea90e50187ab94423c4bce53bedfda5e575e3b83c5666e241ee331beca01	1655064962000000	0	2000000
25	\\x6e957c111c413b16b1ac6babb58d5984625886f3a1c18a296bfaf8d6153e76d148e6c36d03038bca864e09758245ba6ff18305eada994adae354a5487efaa02b	401	\\x0000000100000001910c80ee058d2dd687ff330cfb6ae45efcc0ac66e27557f8e9ec805961453ec17a341e00ec1c44f50138e87ef09baca439864d8bffcd209f279286a5d9dab0b90e184e0223187d8f6d78b3d08e6ff9483d177815a685629ff45d13cb0415a16b2c5b596b425abd31f730f007f73406871425fdb353c57ccb53d2543e7f0be9cc	5	\\xbc24b9d4aa526e06bab72c3e007f0c1f35f5ed4befc2ac0c026300b4c606f3336ee3c4fe56b8c3785d807b37c3abf231e6018470c5786d49f71d8f1d70009002	1655064962000000	0	2000000
26	\\x35e4acc78ec6469c939c5778d117c454b9f31018105b8bf65941822b48f26d1e4cb5a1edef0476ff2363b6fdcb17ebd56fa8ccbd1d9ca8b7cf04d4470c0497ab	401	\\x0000000100000001a01b94d60144a1f626de884d2ddd798d68cd2004a1b144b35a476dfb9fb19c25fcaa40666a937a829ea047641567f60da63ee9f3396c4f304693885e6ae079ca965edaad27689a3ebbc0c7be80d72b7aaf2a58cf202cf017ff5f68cebe8e287346b51d7bdc65d7630cb5a98e65a1facabd4c93cbfcbd3c2df7714d3249a13a70	5	\\xcc08b1c0bc3d9b8a405858cd4c008243edb0dc6e30c02235918cef66cc2607582c123d35b839d1328690b56a0252ae680a14e35deb511881f33f95a4699a5a0b	1655064962000000	0	2000000
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
-- Data for Name: wad_in_entries_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wad_in_entries_default (wad_in_entry_serial_id, wad_in_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wad_out_entries_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wad_out_entries_default (wad_out_entry_serial_id, wad_out_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wads_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wads_in_default (wad_in_serial_id, wad_id, origin_exchange_url, amount_val, amount_frac, arrival_time) FROM stdin;
\.


--
-- Data for Name: wads_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wads_out_default (wad_out_serial_id, wad_id, partner_serial_id, amount_val, amount_frac, execution_time) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\x35ca00584e3f434573e044936d9119d73a9373279b4ddd7ddefe063046711c408634055a367fe525a219e8f86aa91cc38f0746759dd23753adcb64f2dffc5d0f	t	1655064946000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x5ab06e2760ae2e217e23473004dc84e8bc3933693ad6b0000aa7be73a02b0d2bcea1bd98ffdd53b9cbffb988c745af0fe2d6cea1bf73cc9912f40673460fac05
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
1	\\x7ae90b82b8513bd202b46339418159ec03bb9a49991e79eae09d64227bfd867b	payto://x-taler-bank/localhost/testuser-2diiewvf	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x997e14222bb8f8a0eb20daae1787ac97c0003f44ea3741d0fa7f275e65b9a0ab	payto://x-taler-bank/localhost/testuser-viok1pqt	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	0	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Name: account_merges_account_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.account_merges_account_merge_request_serial_id_seq', 1, false);


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
-- Name: close_requests_close_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.close_requests_close_request_serial_id_seq', 1, false);


--
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.contracts_contract_serial_id_seq', 1, false);


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
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.history_requests_history_request_serial_id_seq', 1, false);


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
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.partners_partner_serial_id_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_deposits_purse_deposit_serial_id_seq', 1, false);


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_merges_purse_merge_request_serial_id_seq', 1, false);


--
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_requests_purse_requests_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 17, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 17, true);


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.revolving_work_shards_shard_serial_id_seq', 1, false);


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wad_in_entries_wad_in_entry_serial_id_seq', 1, false);


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wad_out_entries_wad_out_entry_serial_id_seq', 1, false);


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wads_in_wad_in_serial_id_seq', 1, false);


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wads_out_wad_out_serial_id_seq', 1, false);


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
-- Name: account_merges_default account_merges_default_account_merge_request_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_merges_default
    ADD CONSTRAINT account_merges_default_account_merge_request_serial_id_key UNIQUE (account_merge_request_serial_id);


--
-- Name: account_merges account_merges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_merges
    ADD CONSTRAINT account_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: account_merges_default account_merges_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_merges_default
    ADD CONSTRAINT account_merges_default_pkey PRIMARY KEY (purse_pub);


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
-- Name: close_requests close_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.close_requests
    ADD CONSTRAINT close_requests_pkey PRIMARY KEY (reserve_pub, close_timestamp);


--
-- Name: close_requests_default close_requests_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.close_requests_default
    ADD CONSTRAINT close_requests_default_pkey PRIMARY KEY (reserve_pub, close_timestamp);


--
-- Name: contracts_default contracts_default_contract_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts_default
    ADD CONSTRAINT contracts_default_contract_serial_id_key UNIQUE (contract_serial_id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (purse_pub);


--
-- Name: contracts_default contracts_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts_default
    ADD CONSTRAINT contracts_default_pkey PRIMARY KEY (purse_pub);


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
-- Name: deposits_default deposits_default_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_default deposits_default_deposit_serial_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_deposit_serial_id_pkey PRIMARY KEY (deposit_serial_id);


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
-- Name: extension_details_default extension_details_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extension_details_default
    ADD CONSTRAINT extension_details_default_pkey PRIMARY KEY (extension_details_serial_id);


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
-- Name: history_requests history_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.history_requests
    ADD CONSTRAINT history_requests_pkey PRIMARY KEY (reserve_pub, request_timestamp);


--
-- Name: history_requests_default history_requests_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.history_requests_default
    ADD CONSTRAINT history_requests_default_pkey PRIMARY KEY (reserve_pub, request_timestamp);


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
-- Name: partner_accounts partner_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_accounts
    ADD CONSTRAINT partner_accounts_pkey PRIMARY KEY (payto_uri);


--
-- Name: partners partners_partner_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partners
    ADD CONSTRAINT partners_partner_serial_id_key UNIQUE (partner_serial_id);


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
-- Name: purse_actions purse_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_actions
    ADD CONSTRAINT purse_actions_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_deposits purse_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits
    ADD CONSTRAINT purse_deposits_pkey PRIMARY KEY (purse_pub, coin_pub);


--
-- Name: purse_deposits_default purse_deposits_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits_default
    ADD CONSTRAINT purse_deposits_default_pkey PRIMARY KEY (purse_pub, coin_pub);


--
-- Name: purse_deposits_default purse_deposits_default_purse_deposit_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits_default
    ADD CONSTRAINT purse_deposits_default_purse_deposit_serial_id_key UNIQUE (purse_deposit_serial_id);


--
-- Name: purse_merges purse_merges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges
    ADD CONSTRAINT purse_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_merges_default purse_merges_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges_default
    ADD CONSTRAINT purse_merges_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_merges_default purse_merges_default_purse_merge_request_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges_default
    ADD CONSTRAINT purse_merges_default_purse_merge_request_serial_id_key UNIQUE (purse_merge_request_serial_id);


--
-- Name: purse_requests purse_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests
    ADD CONSTRAINT purse_requests_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests_default purse_requests_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests_default
    ADD CONSTRAINT purse_requests_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests_default purse_requests_default_purse_requests_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests_default
    ADD CONSTRAINT purse_requests_default_purse_requests_serial_id_key UNIQUE (purse_requests_serial_id);


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
-- Name: wad_in_entries wad_in_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries
    ADD CONSTRAINT wad_in_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_in_entries_default wad_in_entries_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries_default
    ADD CONSTRAINT wad_in_entries_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_in_entries_default wad_in_entries_default_wad_in_entry_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries_default
    ADD CONSTRAINT wad_in_entries_default_wad_in_entry_serial_id_key UNIQUE (wad_in_entry_serial_id);


--
-- Name: wad_out_entries wad_out_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries
    ADD CONSTRAINT wad_out_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries_default wad_out_entries_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries_default
    ADD CONSTRAINT wad_out_entries_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries_default wad_out_entries_default_wad_out_entry_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries_default
    ADD CONSTRAINT wad_out_entries_default_wad_out_entry_serial_id_key UNIQUE (wad_out_entry_serial_id);


--
-- Name: wads_in wads_in_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in
    ADD CONSTRAINT wads_in_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in_default wads_in_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in_default
    ADD CONSTRAINT wads_in_default_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in wads_in_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in
    ADD CONSTRAINT wads_in_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in_default wads_in_default_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in_default wads_in_default_wad_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_in_serial_id_key UNIQUE (wad_in_serial_id);


--
-- Name: wads_in_default wads_in_default_wad_is_origin_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_is_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_out wads_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out
    ADD CONSTRAINT wads_out_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out_default wads_out_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out_default
    ADD CONSTRAINT wads_out_default_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out_default wads_out_default_wad_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out_default
    ADD CONSTRAINT wads_out_default_wad_out_serial_id_key UNIQUE (wad_out_serial_id);


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
-- Name: account_merges_by_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_merges_by_reserve_pub ON ONLY public.account_merges USING btree (reserve_pub);


--
-- Name: account_merges_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_merges_default_reserve_pub_idx ON public.account_merges_default USING btree (reserve_pub);


--
-- Name: aggregation_tracking_by_wtid_raw_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_by_wtid_raw_index ON ONLY public.aggregation_tracking USING btree (wtid_raw);


--
-- Name: INDEX aggregation_tracking_by_wtid_raw_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.aggregation_tracking_by_wtid_raw_index IS 'for lookup_transactions';


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
-- Name: deposits_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_coin_pub_index ON ONLY public.deposits USING btree (coin_pub);


--
-- Name: deposits_by_ready_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_ready_main_index ON ONLY public.deposits_by_ready USING btree (wire_deadline, shard, coin_pub);


--
-- Name: deposits_by_ready_default_wire_deadline_shard_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_ready_default_wire_deadline_shard_coin_pub_idx ON public.deposits_by_ready_default USING btree (wire_deadline, shard, coin_pub);


--
-- Name: deposits_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_coin_pub_idx ON public.deposits_default USING btree (coin_pub);


--
-- Name: deposits_for_matching_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_matching_main_index ON ONLY public.deposits_for_matching USING btree (refund_deadline, merchant_pub, coin_pub);


--
-- Name: deposits_for_matching_default_refund_deadline_merchant_pub__idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_matching_default_refund_deadline_merchant_pub__idx ON public.deposits_for_matching_default USING btree (refund_deadline, merchant_pub, coin_pub);


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
-- Name: partner_accounts_index_by_partner_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX partner_accounts_index_by_partner_and_time ON public.partner_accounts USING btree (partner_serial_id, last_seen);


--
-- Name: partner_by_wad_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX partner_by_wad_time ON public.partners USING btree (next_wad);


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
-- Name: purse_action_by_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_action_by_target ON public.purse_actions USING btree (partner_serial_id, action_date);


--
-- Name: purse_deposits_by_coin_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_deposits_by_coin_pub ON ONLY public.purse_deposits USING btree (coin_pub);


--
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_deposits_default_coin_pub_idx ON public.purse_deposits_default USING btree (coin_pub);


--
-- Name: purse_merges_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_merges_reserve_pub ON ONLY public.purse_merges USING btree (reserve_pub);


--
-- Name: INDEX purse_merges_reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.purse_merges_reserve_pub IS 'needed in reserve history computation';


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_merges_default_reserve_pub_idx ON public.purse_merges_default USING btree (reserve_pub);


--
-- Name: purse_requests_merge_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_requests_merge_pub ON ONLY public.purse_requests USING btree (merge_pub);


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_requests_default_merge_pub_idx ON public.purse_requests_default USING btree (merge_pub);


--
-- Name: purse_requests_purse_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_requests_purse_expiration ON ONLY public.purse_requests USING btree (purse_expiration);


--
-- Name: purse_requests_default_purse_expiration_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_requests_default_purse_expiration_idx ON public.purse_requests_default USING btree (purse_expiration);


--
-- Name: recoup_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_coin_pub_index ON ONLY public.recoup USING btree (coin_pub);


--
-- Name: recoup_by_reserve_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_main_index ON ONLY public.recoup_by_reserve USING btree (reserve_out_serial_id);


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_default_reserve_out_serial_id_idx ON public.recoup_by_reserve_default USING btree (reserve_out_serial_id);


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_coin_pub_idx ON public.recoup_default USING btree (coin_pub);


--
-- Name: recoup_refresh_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_coin_pub_index ON ONLY public.recoup_refresh USING btree (coin_pub);


--
-- Name: recoup_refresh_by_rrc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_rrc_serial_index ON ONLY public.recoup_refresh USING btree (rrc_serial);


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_coin_pub_idx ON public.recoup_refresh_default USING btree (coin_pub);


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_rrc_serial_idx ON public.recoup_refresh_default USING btree (rrc_serial);


--
-- Name: refresh_commitments_by_old_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_by_old_coin_pub_index ON ONLY public.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_default_old_coin_pub_idx ON public.refresh_commitments_default USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_coins_by_melt_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_coins_by_melt_serial_id_index ON ONLY public.refresh_revealed_coins USING btree (melt_serial_id);


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_default_melt_serial_id_idx ON public.refresh_revealed_coins_default USING btree (melt_serial_id);


--
-- Name: refunds_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_by_coin_pub_index ON ONLY public.refunds USING btree (coin_pub);


--
-- Name: refunds_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_default_coin_pub_idx ON public.refunds_default USING btree (coin_pub);


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
-- Name: reserves_in_by_exch_accnt_reserve_in_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_exch_accnt_reserve_in_serial_id_idx ON ONLY public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_by_exch_accnt_section_execution_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_exch_accnt_section_execution_date_idx ON ONLY public.reserves_in USING btree (exchange_account_section, execution_date);


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
-- Name: wad_in_entries_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_in_entries_reserve_pub ON ONLY public.wad_in_entries USING btree (reserve_pub);


--
-- Name: INDEX wad_in_entries_reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.wad_in_entries_reserve_pub IS 'needed in reserve history computation';


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_in_entries_default_reserve_pub_idx ON public.wad_in_entries_default USING btree (reserve_pub);


--
-- Name: wad_out_entries_by_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_out_entries_by_reserve_pub ON ONLY public.wad_out_entries USING btree (reserve_pub);


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_out_entries_default_reserve_pub_idx ON public.wad_out_entries_default USING btree (reserve_pub);


--
-- Name: wire_fee_by_end_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_fee_by_end_date_index ON public.wire_fee USING btree (end_date);


--
-- Name: wire_out_by_wire_target_h_payto_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_by_wire_target_h_payto_index ON ONLY public.wire_out USING btree (wire_target_h_payto);


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_default_wire_target_h_payto_idx ON public.wire_out_default USING btree (wire_target_h_payto);


--
-- Name: work_shards_by_job_name_completed_last_attempt_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX work_shards_by_job_name_completed_last_attempt_index ON public.work_shards USING btree (job_name, completed, last_attempt);


--
-- Name: account_merges_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.account_merges_pkey ATTACH PARTITION public.account_merges_default_pkey;


--
-- Name: account_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.account_merges_by_reserve_pub ATTACH PARTITION public.account_merges_default_reserve_pub_idx;


--
-- Name: aggregation_tracking_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_pkey ATTACH PARTITION public.aggregation_tracking_default_pkey;


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_by_wtid_raw_index ATTACH PARTITION public.aggregation_tracking_default_wtid_raw_idx;


--
-- Name: close_requests_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.close_requests_pkey ATTACH PARTITION public.close_requests_default_pkey;


--
-- Name: contracts_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.contracts_pkey ATTACH PARTITION public.contracts_default_pkey;


--
-- Name: cs_nonce_locks_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.cs_nonce_locks_pkey ATTACH PARTITION public.cs_nonce_locks_default_pkey;


--
-- Name: deposits_by_ready_default_wire_deadline_shard_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_by_ready_main_index ATTACH PARTITION public.deposits_by_ready_default_wire_deadline_shard_coin_pub_idx;


--
-- Name: deposits_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_by_coin_pub_index ATTACH PARTITION public.deposits_default_coin_pub_idx;


--
-- Name: deposits_for_matching_default_refund_deadline_merchant_pub__idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_matching_main_index ATTACH PARTITION public.deposits_for_matching_default_refund_deadline_merchant_pub__idx;


--
-- Name: extension_details_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.extension_details_pkey ATTACH PARTITION public.extension_details_default_pkey;


--
-- Name: history_requests_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.history_requests_pkey ATTACH PARTITION public.history_requests_default_pkey;


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
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_deposits_by_coin_pub ATTACH PARTITION public.purse_deposits_default_coin_pub_idx;


--
-- Name: purse_deposits_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_deposits_pkey ATTACH PARTITION public.purse_deposits_default_pkey;


--
-- Name: purse_merges_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_merges_pkey ATTACH PARTITION public.purse_merges_default_pkey;


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_merges_reserve_pub ATTACH PARTITION public.purse_merges_default_reserve_pub_idx;


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_requests_merge_pub ATTACH PARTITION public.purse_requests_default_merge_pub_idx;


--
-- Name: purse_requests_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_requests_pkey ATTACH PARTITION public.purse_requests_default_pkey;


--
-- Name: purse_requests_default_purse_expiration_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_requests_purse_expiration ATTACH PARTITION public.purse_requests_default_purse_expiration_idx;


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_reserve_main_index ATTACH PARTITION public.recoup_by_reserve_default_reserve_out_serial_id_idx;


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_coin_pub_index ATTACH PARTITION public.recoup_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_coin_pub_index ATTACH PARTITION public.recoup_refresh_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_rrc_serial_index ATTACH PARTITION public.recoup_refresh_default_rrc_serial_idx;


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

ALTER INDEX public.refresh_revealed_coins_coins_by_melt_serial_id_index ATTACH PARTITION public.refresh_revealed_coins_default_melt_serial_id_idx;


--
-- Name: refresh_transfer_keys_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_transfer_keys_pkey ATTACH PARTITION public.refresh_transfer_keys_default_pkey;


--
-- Name: refunds_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refunds_by_coin_pub_index ATTACH PARTITION public.refunds_default_coin_pub_idx;


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

ALTER INDEX public.reserves_in_by_exch_accnt_section_execution_date_idx ATTACH PARTITION public.reserves_in_default_exchange_account_section_execution_date_idx;


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_by_exch_accnt_reserve_in_serial_id_idx ATTACH PARTITION public.reserves_in_default_exchange_account_section_reserve_in_ser_idx;


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
-- Name: wad_in_entries_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wad_in_entries_pkey ATTACH PARTITION public.wad_in_entries_default_pkey;


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wad_in_entries_reserve_pub ATTACH PARTITION public.wad_in_entries_default_reserve_pub_idx;


--
-- Name: wad_out_entries_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wad_out_entries_pkey ATTACH PARTITION public.wad_out_entries_default_pkey;


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wad_out_entries_by_reserve_pub ATTACH PARTITION public.wad_out_entries_default_reserve_pub_idx;


--
-- Name: wads_in_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wads_in_pkey ATTACH PARTITION public.wads_in_default_pkey;


--
-- Name: wads_in_default_wad_id_origin_exchange_url_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wads_in_wad_id_origin_exchange_url_key ATTACH PARTITION public.wads_in_default_wad_id_origin_exchange_url_key;


--
-- Name: wads_out_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wads_out_pkey ATTACH PARTITION public.wads_out_default_pkey;


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_by_wire_target_h_payto_index ATTACH PARTITION public.wire_out_default_wire_target_h_payto_idx;


--
-- Name: wire_out_default_wtid_raw_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_wtid_raw_key ATTACH PARTITION public.wire_out_default_wtid_raw_key;


--
-- Name: wire_targets_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_targets_pkey ATTACH PARTITION public.wire_targets_default_pkey;


--
-- Name: deposits deposits_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_delete AFTER DELETE ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_delete_trigger();


--
-- Name: deposits deposits_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_insert AFTER INSERT ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_insert_trigger();


--
-- Name: deposits deposits_on_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_update AFTER UPDATE ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_update_trigger();


--
-- Name: purse_requests purse_requests_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purse_requests_on_insert AFTER INSERT ON public.purse_requests FOR EACH ROW EXECUTE FUNCTION public.purse_requests_insert_trigger();


--
-- Name: TRIGGER purse_requests_on_insert ON purse_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER purse_requests_on_insert ON public.purse_requests IS 'Here we install an entry for the purse expiration.';


--
-- Name: purse_requests purse_requests_on_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purse_requests_on_update BEFORE UPDATE ON public.purse_requests FOR EACH ROW EXECUTE FUNCTION public.purse_requests_on_update_trigger();


--
-- Name: TRIGGER purse_requests_on_update ON purse_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER purse_requests_on_update ON public.purse_requests IS 'This covers the case where a deposit is made into a purse, which inherently then changes the purse balance via an UPDATE. If the merge is already present and the balance matches the total, we trigger the router. Once the router sets the purse to finished, the trigger will remove the purse from the watchlist of the router.';


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
-- Name: wire_out wire_out_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER wire_out_on_delete AFTER DELETE ON public.wire_out FOR EACH ROW EXECUTE FUNCTION public.wire_out_delete_trigger();


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
-- Name: partner_accounts partner_accounts_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_accounts
    ADD CONSTRAINT partner_accounts_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES public.partners(partner_serial_id) ON DELETE CASCADE;


--
-- Name: signkey_revocations signkey_revocations_esk_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_esk_serial_fkey FOREIGN KEY (esk_serial) REFERENCES public.exchange_sign_keys(esk_serial) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

