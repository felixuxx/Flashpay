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
exchange-0001	2022-06-12 22:34:29.776871+02	grothoff	{}	{}
merchant-0001	2022-06-12 22:34:30.679081+02	grothoff	{}	{}
merchant-0002	2022-06-12 22:34:31.105456+02	grothoff	{}	{}
auditor-0001	2022-06-12 22:34:31.251902+02	grothoff	{}	{}
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
t	1	-TESTKUDOS:100	1
f	12	+TESTKUDOS:92	12
t	2	+TESTKUDOS:8	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2022-06-12 22:34:40.555711+02	f	18c82572-77f4-45a8-9991-5490f2d135b8	12	1
2	TESTKUDOS:8	VQWC78DM6PKS3007ZDWNRMT1PPMC5XKGVYDJKSZ5AHT1N1VCZ560	2022-06-12 22:34:44.118273+02	f	b8468194-1515-4f33-9893-1c159ffff8b3	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
ed55a420-78d5-40c9-bb62-f93ac3a26b5d	TESTKUDOS:8	t	t	f	VQWC78DM6PKS3007ZDWNRMT1PPMC5XKGVYDJKSZ5AHT1N1VCZ560	2	12
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
1	1	40	\\x0ad34bbd9f434001a84def3ff81db3fa380e9822c79acf3710861ee8865239b4f59afcca0672bab1ea976dbd6c0f14368ceb06544a36e55cb0d6d51e9d8c9c08
2	1	198	\\xa1648e6fc8d8c01f1b707460210f4a97e2a2fb35359f862ab3dffb9843a517a5c237bb1ab300347f23acec34ea6ccbf43f6733424e340254e9ef63a7c3e79c0f
3	1	205	\\xe8a0f44843586bf7e666e94b81fd92d4834b2eea2d1fb71b389fa05e585956cb3240d8f244203db58c392acf0af4f567f22b481b0cae5bc50eab53ec96a92403
4	1	349	\\x9c76a5d80fba6a11b3b7cea148dbafe7a475d50539c592ce3fd554bf72243ca5f50d826e19b4973b4b67a10a08fdd02a81f454a8d2c8ddb40f1484113969440f
5	1	56	\\x85328533ca61287748d0cac9820513ca80078640e9cf324730ea58ac144e97fe311bfbd5537376965216a7087a454e63bfd38a61b0c8c820e89c2b70d7f9f80f
6	1	294	\\x28fef5bb495b9b67570416c1cf13a0d0dbb462ed7b027800f90a6abbb41dd725f3614e07daeb801942f05803e70bc30ac87cdc0a76857f94a5e812016f119505
7	1	216	\\x4eff7ea73654e5c63fec8d9e4a206929f6af9261ae2f6e3e5fd5c7c43a23ccb036f428a404d2363348d9906f38552db6c80cf1270dd1be10c6c135e9fd41e307
8	1	266	\\x58f78f45afeb1b5f26aa972346e6001b06e3d31a940b7ddb2488fab901eb7bdb89b1cbecbb1be17c687bfb4a975b74420bf73645a61eea778f32ec9da5792b0a
9	1	245	\\x5b7b148021fcb08980fdbef4657d765d11b8ec3c0bf6ca939d43426fe9e832fc2e7803148898dc7039e81faa2215c64efedeee68624475cc3d1203e76c95e007
10	1	301	\\xe8039649a6e11c58cfa1382708dd00d2fbcfcdbfc83f5edfe3ab133eeac376e8d1cd5a765be29d8da2f6c816961b1a56b9cc550dc0bf5a1310f22ea8088de90c
11	1	71	\\x87a2e6893ef80debd60105c4861bc3cb5279bec041a87ce9778d9db40f50ea10f96d907448a1cc789b2c128caeee7e568e720400f35efe8475d61229f65b3f05
12	1	285	\\x5b7e87e8dad4aa06fdb611377b32267625c4b394bb4014db9b5c769ee1e1329e4daaecf4c2aa8e939b7ac8d8c33ba8428827de7cdc747dfe8ab48f7121d8c307
13	1	146	\\x20a8a4ba2b1a647fe0a8ec70caf0739247ee69d25f0b11238695d546dd1b70a50963cef6960d7151fca8e7b4dd130de96f8b82b629f5a86a8ab762462514b003
14	1	17	\\x8c008bc45c8d0bb701e6376dac9c64509fcc4e6fcc447ce73e20b3f7a5d22050f06f8ef6fddfafce1a4032ddfcbfa531f1ac7dbe0ab07fe9d4bd22da6a8d2c05
15	1	110	\\x6a2f88b4aa60ef933f561fac97e3af4689aa4cc102c40e5d5c0483604366ac125eff055a9322fa7e92c8d9794f56e6b495c5c528b0385d5c54c1bad96b67b60f
16	1	284	\\x493fe88dc77b30ee7868adf45bf8d3c58f73118e6f897674115b00f65f8eb4e5daa73e5b06c143a1110e83901f5dde174005d69b2baed4d3a07acfcaf2b94f04
17	1	278	\\xa424269517d3c880fb0cbaae39157e0877c43ac9d35cc1f4643b5254d09e640cfb1bfcdbdde63554585b2eef2d9ef8f70ceea7cbb81d079cb4e114e028437101
18	1	229	\\x36d7199987bc0689b6cea5cced7c2372ccfccafc4491b110b54109ee783a1f22b6f826201472f900d565be687c9cf7fa73036ab3f46963b0c80b08a3eda72908
19	1	334	\\x144fb9673771c6d2152c3dfaccf5578a311c3b7d40739f714d7bda96474046e9e5cd73f2ca646b854056ad87e2550ab289a59392223ca07f79a90a446b7da70d
20	1	331	\\x1f5a3e4d452ece1c02727cba836936487342d31bab3a71bcab16691d5ee84582fb14de824c93a725483f5f738e5e69cdcaa0dff8fb57dd2b1449225244611c06
21	1	241	\\x10d3677c2e6d2692da256ae4da3531f211a2dce64c514dafd3138eb417c27dfd70a19cb17675b5d559fc343efa0b49e61691fd30c687a71bd8f5b1823bc46203
22	1	39	\\x713dabdce0c79c6e144ba1fabcf3a1897045f55ce8c60c4d1983761d2ca742b04190b09a40a9bc74d977bfa6a14157b981aa0b6dc3ccaed6f62d185a8f756f08
23	1	87	\\x115b067d1192a97467d2d0782a115d7fd2123bf9711610961204567fa30e803331c83660e4196023d6ac263a9939bca94cad55562ae7fadfce62438274de2a00
24	1	64	\\x78abecf55e0d2cb938ccfe13d02705c1a4d6b05d77ddf4af356deb9b20c1ee15449f844f5cf97f05982f1e86d36ac9eb3ee84eacb743d466416480f7a24d6c03
25	1	195	\\x678721ceba006228ddb704018804106a8c576e6d65fffe9ba5270c5f377b4a5062230bf4993b4389b2d3aa88087b3f4dd8b77143cedfedb39d849f7f2726d506
26	1	6	\\xef42a83f743b3da910ff66152278957857540d290c6650b389b225105d8cc12a0954f1025c688742da18819cb1b1982f776e58397b7846ab9f8ca0ec4dcb300f
27	1	209	\\x0de1ad07d201519b345be5fb4f808809517499e9a3fd12ef8c80f4378b9025529742f9a077383a5b26a28c5d5f06b3fe91a9ff24d4ac3618a7479850eec6200f
28	1	306	\\x570afecbf041d89fff9925d0849eac829d0035d9b55a38059e9968717796521cc71b824b025c1cd18ae851e2947b7f136ad22a3db6743be401ab11ccc3803905
29	1	325	\\x5626806d13be26f35a95ee7a29f98546d94ecf640c789cd1d0c1e21764d38ed44c7da1f4e2f8d2e7f4aeb76222d61d48b3cf3ba6f34cf2a626d72040b66ed309
30	1	353	\\x8ae5370a4884e029fc1cd4bd89fa9fa45156e73d019c595873db3ab15f2cc84155f4ba34bece9b8b0170aba4b93ad7f688606252525ef9273db642293bfa6c0f
31	1	227	\\x5e6430f54de4267b3c3b7da6f702ee927971fa5b38befc148f68ac914925f7e0969f1b356bf125d62b310747fadc758be6bbc415cb29a237a87b0f1c44315501
32	1	365	\\xea42bf144e668f2a1d505f26c12c0e1688d5fe3ba6c7d4582d7f220397c9953def6eb8321fbdc75c10b4c7307cfdc61f8229bfb570c749eac668bf3d2ceb1900
33	1	42	\\xa900ede15a7b7a86c0d7ed485c4ba6467d56a052211a328396f6a518a49ea84e6620f6ff594fbba48bcc84a6d0cef8e8f49ee809dc909b210a50a7c3b2a8830b
34	1	129	\\x4c32bb8fc507691d7cd45864f2af12ae8114a8e2fbe0998473b1e886151403c6ccce0f43f2939e5ce3d35e7c7a5e925c58babd5a23a658de669b5a5877a61200
35	1	386	\\xc402673e35e58ac7c962ae2041c3c3f98251e234951253e2267f3bde43b9d229f0ec0b82965be54568d2e8e23cfe46c998b62ca8009ce8dde12597d048d5600c
36	1	83	\\xe28371e55381524bc4d02449914d757eb90bcb466af5dbc79a0a592c112a6001234b2cdb6a5565a242d9e9c55eabc770800d5cd85320b62ce21ca8de86079709
37	1	295	\\x90ee5d375140910f2868b92f505714a37b4c5446259a203b9244fce029b2ce98ff5c85ff8a4b1ccf429a24ccc82b491d00de7d3f82668c5c6815340873505f01
38	1	327	\\x19f9c8233efcf8537f8d8fe8a5b93fd23b92557d9431ada1d762c23b6a77c9e0aabca6fddba207b5becc49f1916783fd2d337301f40a6043acd38a39956f1f02
39	1	91	\\xbf2b6d78f35a9005bc57ba91ab01a943b37b6ceee97e68523a4eb8975c46c5bb0b303b08244e823b61b859f483808e7b5426b330b9780d722d40f255f44fc707
40	1	98	\\xb47c4438e04d4206d90e8dea05e1066ca95dd26261c9c4ae9760ceaf0a41208801694489134a42f636079116a6784c07ab419528adaae3cc49d1c3ef8b15fd08
41	1	159	\\x5348325ef275de136a24c12b44b48c791c5d083c2e28dff00081a2bde8f1e4da47a5ca838a549019773c0fe49bb14925a91a226dad710c5ce772cb3d95cb6b08
42	1	141	\\x395224872272240e634cdce800fa8c5dbc5060676c075e511c22ec7153ab38caf0c0b49b9cf6486ccc95f4144895cedab79938dadeeb7a40dfa793ba27b25104
43	1	164	\\x646a58b533d3a0904a3fe548649ad5ad5fb8ab228ae993168cf1773f2d6bf2df8235f75c1f1218b978364c66236ce05f72628354e711c077dd259021b87f8b01
44	1	357	\\x3e8d8084d1282dff8ba3099c6e303e26d0315c61ba70762037985e92eff0e4d8230b471a2a3e6347d14d7613b86ef348244748d03952ce293cf9dd550b380408
45	1	189	\\xe245e6cd80e3b7023b15bfcc06e13530bef2b5965a2411f5bf16bb5023d457e9215da3c66c95f317820af54d93e93f8f684b0badfe18c8c47daf4b5ca8eb3f0f
46	1	68	\\xd474551b3673532ae53d2b087eede21fa6b59c65343b220116cd829bd26bc4d47b240e2063e438b2d1e68194938d88078e1e43dfb197c1286482db4fdfd7b503
47	1	16	\\x919022b0d3062b46e4458b29a8fbe3e3021988026dfdea063c01e40f32dcfe2c49d771c15da4471e2ed9fa1b4a6fbc4ee67bc11e2c405b8a97ad2817beaafe0d
48	1	175	\\x8d62c33fb5c5b661069b0474684761f2028ded34cd31ae6cc6ef1712e3fa1aea605ae8fed7cc62eda19181c2af09f8b43316a33a98624119b7574120e36fb90d
49	1	69	\\x5516e643669d52816526f76e6015dc6d7e653c07e17ced478b8e53bfabf342572f52db35de899d3ed9d5bf074c268def15ac8c11795f2162b37ab3c478b5ae0a
50	1	379	\\xb5b2882f3e414e3aa450feb2418018fadc8a20f1189985a39c7f33f0e479b63c77594ae31f0675e9c8af1ed746527ccdada3c7a1aadaca0c2163761546d28001
51	1	401	\\xd90635101d335038438c0f9b34c8ebd883bdd473e26a91c08e25f07169246f1e692504e4f7daea58b70218af19c1d4a89661c976d00f1e465bb6c551b99f880c
52	1	92	\\x9b66f180d4d404a188845e093e4fc7432b02740d2d42e5b0b447e1ff30d34686a4b2f02c674a3a936a5109f6e774b1c0cd8a56d5c52a5f2d275841f596df630b
53	1	408	\\xee45546f3671f95e5b2e6ee9012653415b9e9032549ea3bf843005454aea2f088e2c7eb770c76dd9116246ac9060c7e2657d79e5aedce43e79a3fb4643325c0f
54	1	390	\\x4b2e35505aeed618e34956b353e76aac26892759943792322ef8f8133c636f06085d80dede56fd4cb756f1c91a5495fa1412a7beb8c617072cfc3704d2ffb709
55	1	314	\\x5a6c988a7a151fa45efdd0bc9be7158a0804b986269d0455eebc8a5f3eaff219134cbbc89d4f2dea403831a2a5852b2d8fb4f4c4ad6230dbc4b8e2fc4ac99700
56	1	400	\\x321e15b4821524b6889fb7b4f9bdb3889f9a822260922584d562c776bad17ae6aec8fa20d840d0639dc168f5f45454196b6a14d613abc56aa543ba12d3ff8f0c
57	1	27	\\x180568f714908ebdb7bdfa3021efccec06a0b6b09fd551547b7a40a200f831a5567504837bf4f90fd84a6af61a8428ef7484fde9c9567bbf56179a1526cce90b
58	1	14	\\xce4ba109ab52d2ea7cb794f7f2135f3e2da1f448af41fa58f7c1c3e1375f016199f0787449504dbb16f8534a96ccd3a4fa33640cf431f0571a32d1a792b7880e
59	1	35	\\x0b502e2c63ca1adaa5225c9fa331fdca024dcff8d41bb66ca9b1bf6367aee874f68d79e684404d3f67cd0695918c261c3a850cdd09c95a34a34d251244879c01
60	1	283	\\x177c372de0de2a57cbf50aee9726a647e9966e011e096882f22052491adc1552047b3607d986b1802aab7b0e70329601bdb0f939d2983d162deae7ec9efb9301
61	1	210	\\x29787efedf3170fe8494e8b0065b832d79d4b9a6d7749a75921c2c4f94e880468ebaf2a0308ff050018a04b44e6809b7c9d2e741f3cab0e804b8705286af5806
62	1	138	\\x2b9691ef0a0d446cd82483d8c00efe96d268df8f5aca9739e183af6a8ddc46e53582aaa985f13f2b696c98b9f560fa7193771a544a5db0c49762b39812f83309
63	1	269	\\xddf358f2d0ada40bf1f577b2a8d5f5782503cd530c8c8e33ed7d4b6376ad8a737a713e4faab6568e45d1538c5600958995610f7569c988b2c206ee97c6515b0f
64	1	268	\\x2065018ab4b2a317936a72cff6adbc8f61f3b3dbcc97d35488955a4e42594c2eac8d3f34273de8837b7c9f40574ce3da88941989a844acbf79b7f4cfc03c3500
65	1	220	\\xfcdb23412ad3d253925a65fa5dffbe120dbb2d9a9bcdd452fc6f8227b7002be444ab7ba15ac17d8f836e759e0ce8accb7c5d9b8121a0e854e02cdc573c231f0c
66	1	240	\\xa45ad271f2951d8450f299faa9a14ed7cbb3c511f1a976e4e3cf0cdfd8c0c4221fa58ebbe7cde691b762091fe5d90deaec3efd3eb8683a8ea78ee1ec74ad6e04
67	1	254	\\x0ae43d20cb5b072a95a73abca689edf0e50237c46e09d2172b2cb202e2dc1824372d9e81c41558902e817771d3da367029314c0e58a134f38d6deca24598640d
68	1	72	\\x74eaca31e732fc7738da9aac932c5d3d3dfb6dfe9a921cd6d4d2ad7fe5516af65d3442818d21abe1233c6314e9c42c9f3457b6ae183269b3978689c007e95d0b
69	1	97	\\xe7d4cd4357215faefb26ed731b0ec3e2024a73fd62614904ef23d548a7870e2271556efb1649e32f1e65e325b94d285b0a89e509b7c91a47f0b63c3ef8d5a907
70	1	355	\\x8c8656336b584acb047ee8a7d1a8aa83ca304e670be253a6faf49a8dd60197881574d963a86524740099d3714317fe429be43c848136942e63d952b932374a06
71	1	99	\\x187e7a79940de8841ceaa5d918fc28a818cb7b025172ed1c7a2820ce82728403e7a23e9a695a2aff9d999f7a652909c14b5aac77f1c6a9967635eecd4d69b803
72	1	102	\\x5ee7d7693374decf57ad943143aa8abbe0c5eaf9cedc9edc88deb6acd393a43e9357f2fc9da8eb4cce0b941144be1443271222ff7591a5f43829037549eab800
73	1	263	\\xe62cba4b75608b8e9e01afb5620b506dcd78669a5c8419f697eefaec8b202584229a061c118bc3f7a54245d45f364f698ff4e8a825618d3dc0b4436e895aae0f
74	1	162	\\x894d7399609c28fddacc7c4f33d6af7d90d83f947f007f302b4d21f3dae258c958550107ce4b28dcee1539f025c07841997f481960e1b8e88f37386a11d2ad0a
75	1	199	\\x74c7b0afd87480f0ee5e8de309e1875fc0d60a8a564980bb74b34372a9899090bb7fb7a8aaaa1f18794e117830858ce362ba8a59980ff5662b417b86f7bf7c06
76	1	79	\\xaa02d15c3e0fdebd95c30cec98da15b92c3ffaf3e51f04de3b9d8f68c5b9efc5f31cab09698f5e2f5fb571fd5c70d3ce6fbbc6ad869ffa5e04e66afce0e95d03
77	1	178	\\x43f55aeeaf249b896e548ba1677a3fde8531146a9c454c07fb7093322fb9af8593f6db043a192d490fa6cf2ea0faab7bf05277ca1f949cd69a2aa101d91a3902
78	1	304	\\x732da33a58d3547790928b6c8424c2297418d940575c74ea6c3bb4c6b4cda23645d12a58d7c9f8a2fec8b6806880d7494e002832a83eead1ed88ebc2dfce7e0a
79	1	340	\\xfe5951d70fc9454ea95a2fd70ff07b94e8190b24237cd2af8be2d8f3876189a7a74bfa15417609ff69e57de099d2d26e12e04d86540f705d76b9c5bf58ff8207
80	1	1	\\x51493dc2fff0a1aea00dcdfa50bf6650cac1d6df28b43638586bee9010ff0ac59c803ed89d1983a0f89bb63a9b2fc01ea95cd215dba8e6312508bd2e1659d806
81	1	117	\\x9a5e3e2ea4efd8cfc97da2d9b5c0956895f8679660b5d3293d17c2354667fb10de0c9eaef3a5a074a0bd8a882655b1644840f13f3b6aa9979932d7d297990e0e
82	1	404	\\xae9a328de2ff64a3c5d9b0d84ce879de980c78f1187e598ce9b1ae82abfb42a7bb7049a1a0c3f017fb500fa8595f5dc0f93970f7d0d5e9fe94c448dde8ddaf06
83	1	60	\\xead9470f55b6470571cc65130736b8abcc58169817a56227ba34c898a64e5ffaa5773a176e451b18dd6fcc0602bceb4414b442f357788db83cc6de25da06580c
84	1	183	\\x643ae34d49cd7320e7294c92614ce9a4b91940abd81888fa88a05da5cb133889abfdd410c8ecf8247f9c5f7cd97af9e967ebe0ba34f13db71d57318f6277380c
85	1	48	\\xccaba0c59a0a9fb5de6e2a6f9398fa3442d3c83532487121167beeb103b5fc70036c2caa30c955ec99332b8991743493b0144efa0e6d21445350ecfe7e3a1d04
86	1	145	\\x577d18ce2079b88ae2ab6712852986fdafedf7f5e8c590d3ffa07c457aa2fdc92c39019f53ad26d6d75c8c1c83c43fad5cf9aa7a76664282268c100f0f68f901
87	1	362	\\xda3ebbe81344ab0cec5517fa5ef1b409c6ecd20a23b9a2d21f8e2aadbf961fda44e055aa9a1ba379c95de1cd27125f48afc0e970fd0fcdb03b377bcfde527705
88	1	361	\\x4faccb327246236737e937843e6b544c0045c0b1f3f7650c3eb62402561b3219486693b34a606066a43869a4fd5c5252dd83bd63b07ac5765b5a69be8a92500f
89	1	132	\\xdb9bfe6952ec44b52631911e5857f3d7ac9c3012c1351781789ba860e270622fc582c6f35ef8e92f9d35c41991e8bdf096601fb18e68e85e12a754c39f7f4c0e
90	1	255	\\x6003de39633e75635e91158fba9c09930ef346f293c6bafa1af5eadd5b19c53bfe99f19d1c8894ac2f6ab38bbfa10d04215f17170e60bd5b1480b19bd1ca6709
91	1	393	\\xb41b4648e6f17025dc5b482f47ffc65bd809495ac137fb1b3e5eebecd0cfc4bfbfc2f3073168ba3303472059b4cdf1c9a0c3ba156b9ee5d4ff814f37b853fb02
92	1	179	\\x81745395d83114547f47eaf1d4e8eb4b9fbdbcc0a22eef84fb807f015e1c4ab72278c772624a8453147cd67b2e93aff2fb23db4ee335d1ad68db57052cdb130f
93	1	67	\\x4763000f9a72df883cfe85444ce600eb176d35c8eb61b2dbfe3c273046bcc4cd06ebba4c79588341f53b17a327318f84fca3ed901587a31299c4999140f2d403
94	1	330	\\xe8ccc79efab9094b69b408a7ae9cb8cb2bbb82acce973df99e60e4525e1bbb6dec9940acc2df6d804d2982dd7a58aeed40d4b9925c14bcce043ffc391c4cff04
95	1	76	\\x00913e186f3f2e88b931b053159b036f052ae53db2aba4bc41d82eecf0d1c189503befeeeb25e49b4f32bdfabab67447084fe3a163c2031664c3508de74fa207
96	1	310	\\xd47a6e9bdc713ae4d73c8e79df0297840b554d66de79ab24716397de0c7518806520f0b614eb8cc14bf53dbbbb4dba86bdfd0cce71c0a8e10d6437debbf89d06
97	1	77	\\xc6a76fb574c9c0156d0015ed1ba5e25b5eab95e81fb5fccba8b8a16a1d567f8204e22fc51d5246e087407fe4a2da7114d9f79148ffefcbd9684c4ee7a3691d00
98	1	70	\\xc7a0204b2fd61b8dad5314b260c150556d8f398b3a2b61da261c53ee85bfdb799a7d350879d55c1cd06a98d00125cfa8c66aef9416f043b636e13f8f90c0a10a
99	1	94	\\x4e75a44ddcf10ae52b9a533b6894e936a379dba6db74b7a6806d61fce3a2aa22403ecbe0c5172bd033ad8f5064404674b5d337ed99d6b7a5e068911e6a79d008
100	1	96	\\xa7da2dee11f365b20e0143052a1170b0a192961ef00a65c79fb85b5f074a27fbbe1ec5f5aededc7f8d5c546275a5a9ba90fe0cf45dc93100c2e1d188b4d93605
101	1	387	\\xa95e469473b5735f03dd1fa03f3d7ecfb1d66ab8c817bb00dd8c91830b2a0689620c11b1e38e966e3bfe6eeb0c4bdae628d255fd1abc0b0377530b2571eb2f03
102	1	225	\\x0601634dc26a2acea1e13ddf7132f4a3327ab36138fe5a965b4b161dac2df8c25a44fb1199ca66d1e3fde05bf818620ba7fc6093fe38ebf8cc7eb572bfb8810b
103	1	78	\\x6f8c3b99f9a36f49fc268f75adf53ca18109155469079b08e7acbefe3c07dce776c8a92b5e7b896a6f5fcf502625c815bd903d989037010ec150c24817022509
104	1	359	\\x3cceab3de1cd9da42e049fa11bc5e6ba0ce6be4e4bab37ae3d54e7885b1bb837a232a5943e82c4531f3b4d01c8a62596a33e485e40da81aed2cb6e4575461509
105	1	61	\\x1a79d5245f6448affa79ad4943a02c77e309983a9da5fdfff03fe0731c60acc25343d133d5905c4d72bcb94fbf924c5c6572fffb8db013218e205841af74d10b
106	1	250	\\x5ee624695fd0ad16ea6f2f67ce68ae11b7a8fbff647c952ecc54eb096f46f7407f194fccbc8209fa38c3038d593fddb2531119a88d07a23dc7afe6afd9a85709
107	1	81	\\x3ace5a7dc32286c1429b4033172ee404a56af84780ab1d65a790c8f83eb0185c4a1ccd19ed3d34caa838683fa36f171c06ec947a3e8bb4af20b0e22dfe5c230e
108	1	136	\\x73e12344187cfe29aeb3d9d56694f16c7c53600af1bc51ec5d0bbc13f7fec6091f8a509ddd7be729b215c0d20e1f5f1b10beee20b36d63d45a918c2e64d19300
109	1	237	\\xb347196e8fed56b2e8c93c3972fdd89ed625ab9856cf38ea703181be04a93f8ddccd529acba88f3b4f08230a6bc419eee9d73b7352276caf7442007286e6f001
110	1	307	\\x70321f96fab5da840920d737bcca3f6696956e8879c163081496fa169ac8fb8b42106d97ad4e419106e1a4d301443aeae4d88444286895b80646dc8c650c5808
111	1	282	\\xf2948b76cbddb7a4581321c653f71914d67b141df6c792a83476325a762a6f78e2b5172591416be46120034583a2a377fdc41b6e65226a6903fc5a913ad2ba0c
112	1	333	\\x81e4abec7561e23f8f58ed2c38652d5f841b9b3c82f3e6b02de055d24ec7c214c41312d9e6927e86432f956be1ccb624f9573d8ac2d50b6a5172934247b8b70a
113	1	292	\\x192fc206a19c8f83d73742d243db447777388ebb205494f2ebdb798cc23c78362022fc11863c744efe170f8ce110e2a6913e6faff66f3469c138eb40cffe6805
114	1	347	\\xb60d600e13100e3cb1ae24cf25ffb1d7e460dd781c53cd3df3385315599196aaeb346eab5537d1144f9362e098f6df8c489aacc24045ac6a28472d9f4fd9260c
115	1	375	\\x3eb68c25f203373e2a30b1b9b626ee8feffd9a4b7e8c6b49cb75ce7dd1e891cb3e678bb6312fdc7338f822b0c3fdc45b0c9d8f051802fdd23fc22c1dec746704
116	1	37	\\x1922a00baf1e6acc69a8e15606eae7078e329cbd6b9f3ee1d47c80396ae679e5a58540e0958ffe6c8eaf3af2fe5ae8795a515268fd56219bea919b03d6d63b05
117	1	123	\\xbfb752cc26fc471c11cb3267a2ae5edb7ac6359b15cc52bf390e847495341ae9b2aa05d9512c88811969d1f071bfaef4953a763501a0d79b0f17f90dc124fd04
118	1	103	\\xb7c0c4daa4f967090fbf5b15262c96acb272c99806aabd341969f8c569472a0793a60d85a1c8f0c0dc319c2d598da5595938b3abb8770bd2bed919869e73430b
119	1	89	\\x245cf92f4e9030573033a0dea13cc2430ed13a746a1a39ac65fde69efa91bcb8dbed80d92ac7b3f151710ac44d842507947a4075cb0aff85e40f3b6bae4a630e
120	1	128	\\xa9785a56a6b98826d777d91730c51f539580d9807f61cb3ab07e668a5ce0decbc5a332b1f534d165ea55b17cf7fbec214c3094346d246af32f7060b3e0999f06
121	1	120	\\x4768456204e21e61ba96baf96f0f14f6fcb2176dd054972152cb970202d4fc8bd95307da04bd9542935ce61cf263a2b05c82c05d34cb6c308bd5dbc269089501
122	1	90	\\xe5c5aa1624e726155a92f1cd9ef9889bc1ebbbcb07da44e45c7eb8716c13153f4648b6c8e8d966496cf76e20afeceb458aa1fbd8c234e34bd90b1ea92b046b01
123	1	34	\\x88db25df6c853440a6f284762a3f3cb87fd3f35f8113a1aa576b9d5b2404e31a9efe45187c749b842488acdef916c5db8c1e5c3e7c597329e95adcbb61d70901
124	1	251	\\x2cbedf07303978a7aced94df06490d795ebd037d6efb645a741faabdb44c11d2cf18101cf73d856db9451c78b4ab4f530d082982d462104407efff81349e3d0d
125	1	74	\\xc7db82f77d1918a0edf570106fc4efc0f321f61e39e982fad115397a4af3177782e5d34e1d40fcd62b22a317a099e0a28cbb1ecb7ba51ecdb1caebc6eaa1000b
126	1	154	\\xd2e8d6aaffe6a197a2104551bdb830aaaa3f4fd718f271c623ed77c0fe5b7363a5228d5d6a111ba1b2c1919b2628261b0eb19f285d644a62247ec24760c46108
127	1	417	\\x30c28d8d383de8c798c30c1e85286a0f7e4a9d5330ece9f831c7c462ff3788bf0f1080f2cd2b2a975a3ebdc4b0534c9637d25357ee9c758b83210cd9d7d06506
128	1	309	\\x2f201f515d36187cb52f0e46ddf6eb214313065bfb05a24422fd7e6821b80eb7f0b59024fc09d4071905e836aa668f6bb84ea08c01f515f1d3950ef96942770a
129	1	169	\\x1ac35314e9ed98889cb2f87491a1e3e5d5bdacd2840d6b5acc63959958e2bc7e0c5c38eef62bc67f446a2c859a4ed55902fc32d729df78b82ea652c06fd48800
130	1	214	\\x047d8ca7e22be0891a7025d283e3ccfd2414d58ebd872d026cfd0190545e1069f36e39db11084b5c11e3a58d50358751af65cc617462af15fdb7fef13d521307
131	1	397	\\x7e11d8457bdc983fd7c253ed9d94f0a85996c00b7ac8af41eb121b24dd2d51e57204896b3aeaa4fa423c4c19b175e0b5cb1dfb50fa4092079e7bff59fe3ac406
132	1	140	\\x65f155cadd4a9404869081f8fc9ff78c446de46ed5ca0cf86fb35de8d244836d817c31cbc0d8ab2dcf43a471b9d76c7f2dda1208465e5666a78e10729af5a50d
133	1	155	\\x35fbef61bb56377f13a3014feecbc090aab425e08680ffeb1f9d7af90bdf69a1b865be86a689f2dcdd6f17a9803195f95443ec167370cfa27d7f143f23941f0e
134	1	5	\\x853ae3e8b6adebdea77ba789a7c10f6e2207982b091f8296ae50c8122bdd85233cfe4b2ac48d458dba1a2c54a906aa7f925680ea3802aacd4f1f42919110b60f
135	1	315	\\x0ffe36c87178a2215c0c11cf48c7424ebb0c8b870a29bd9aba31b6faf0567a3cf89d8d614ef2557d4776cfcfefdc77ef1de02062caf562ed55cf2cf26567640a
136	1	222	\\xfe3c45875f1307ca4e49131cde2a0eae3058befe2a3493ef5a9b1c42d4608d93584dfb24abcf7c9a0cd136ea8d8652e5a9c6a474707a58046cd2ea790888de0e
137	1	22	\\x9eb95a803dfe136be9e11329e2da0f3c32947ab1d59708e08d42d4cb63ca9ffe696d06cc1d9521ad34b92a7d52cb3932df9bc27357d454ac06b4f84c8f74060e
138	1	243	\\xa5b4a7421aa336c7ee8b2d78f9476c43969d0d4eec7c014bf8bcd4807d23821af767569f089b51e3f8df6a89dd64a4d359fb9bb112f6565e8888a1ae8042da0c
139	1	211	\\xf3a6a3ea2c7eb7c2098b4fa153abfef5c0c7bcacf4179a986b4c2f3fc809d06210e071359a613135d964e2247130b9dd7d1bf3156f6c8afd6e5fd5ac8b7e9e08
140	1	419	\\x30932e3842e5f6f082df0a49ae307d433f7e4db85a4a22da6f00cb85f4aada5bcf87d70646648655e0384074c9dae10ea5552973e04468bfa40a2af7bdc06a09
141	1	228	\\x3bc8553e6c733d93e5d192983a5b63b54f50c969b66bf1fd7501f037db0bc09770b9258456d06cd67a44f0dce1ce2811752f22c52ad35a7c17b5313acf9fae02
142	1	382	\\x4c51ddc573b42c124aa005d7de69c3bb8ee1e3e1cc4d422cdfb24d15c738735f04362bd28faaac5c41de84a5285d33ace7b53e32d5633efd1490d45438c92e0f
143	1	297	\\xab43fc54bb56231d58ac4a3f9e459d485f72dd17bb031e0d9967f30aa806e39020a6b170af961bcbd3b5037daeebf0f0fa9c6f47b35d303404384f7a9167b008
144	1	204	\\xf6123d6b3016354e6e0686e0b4201c16dc6ef263f4e4ee60ec89189b12c9e779809eaca9d4e3f7808b32769cdcc1e9926f61cb6c12865930e34e44ec2d136204
145	1	144	\\x91c6959a29477e9b242aee7b3f02f949d5a97b21e5c1b13e2f97501ca523ee2cc5dbbbd3d453baaedb0d9e9f998f3479c926521c80648a9bb8e70b69f43ee507
146	1	168	\\x39a3890ded0975ea7d3850289db2464e2289df24cf002be156eb3cb3a995fe0832afffe819cf8c9e4258c13d5c5a69206aa18484baeb3b0f595a942285b9a40e
147	1	101	\\x9347790e2d961bb558d4c4637a4b3aa7e1b9610594048a4f1420cdc048572fd7dc267f07376273c8ffa129d19dcbb5e1a03ece14f3f43f8a749468f963084107
148	1	300	\\x6ea0295944b894e187f0dc9977c524c190d70810d1a2193d2ab9efa50903b98d1e3a0d3a71a7277493dc0a429a24cc08e3a95ab733f5b3c805025ba4ed737409
149	1	235	\\xa692f62d2ddbc01193e655ce0d32c5588a4d80c3cced4dae30c282ae36be97ae3a230ae1860c5611d757e19ad576761badcf6d49de5708918012adbae7446301
150	1	411	\\x4eae8edd18ba678fa9110dab377b10f71b362ce04d2af488dea9eacb8c593828aa0f963885a981f21fe7e5c8caecdaaa539bd9ce7b8b974f69e5da54f7e77904
151	1	12	\\x32a512585d01b4ca51d03006b002f3c255ed0f9171f43de1910f4e6f33c1307c69d2443c69f69ce38b8ebd8666ea9d7aa2ad9c3f97380bb51c9f24039d25fe0e
152	1	396	\\x47e37afbd0bad736fedafeae65bf78fe1ab8e807f3620eb31e1183842001541459de645b1e7d83d81e85abe37b9a12fcc0d7703a94125ee8e7a4b723a7b22f03
153	1	121	\\x5cbef60e7943c5da329d307ce6e131ac1985e48e2cfc48d6bc3fb82d9931f0c49659cd01b4144079de690987d98d3b312737cfc979324daff21402739e7aaa04
154	1	165	\\x2d142e398a6efe549d756f60a846105ff8b86066d1ff36f4a7442cd8b75a0926b7c24a9bb72cf1122ac61cc73408ceba530861fa8df90160f6bf88ef6539070d
155	1	131	\\x0fcd43832d269dce58640788c638803a54eed481f9c2825c61ac2f1351795998f50ac2911a6c2d881e386aaf54299eef8527ba38c7b2f4257230cc71ba29040c
156	1	256	\\x41588451ee67421782cd825480eb0954ddb453f1fdb3c945a58af7842fe2685c5110d974b23184517b223cd2c55330f91acd0b701a08cb396c5ae0fd2c78ef0e
157	1	308	\\x0911829507121a8fe2c6810dc7891a5cf540c7dda6f8d36e3b2d66933406f49806a9661acc78379307f16b06cd846626d4bf950a890b1edbd4e13f823a716c01
158	1	388	\\x2b6897af5551c622a882e2bfeaeb32d1a0b6e4c71aa8905f2f46f521d8bd4b196d0f543c2cbafd1fa75cbbb3519f35111a9b9de8359761b85eb9c7b78397bd09
159	1	221	\\xf7235bf0b0101ae0cfc63101b7dcd6907b1fe9964e6182176126e917f5946aa22e7b44074a624cc83dfc413fb9e1f56fe46599e25e8abfa3ae5bbfaba2553d00
160	1	118	\\x5b752d668c5630958ddbd27e19889e9601fbebebb4b2e0cc6d7e8f7ba78ebf45533d3a5f1e1c5504f1383873ef2e233541b8706f8301ba87f4a0697c38769a09
161	1	377	\\xa1a755d906ac437447e504c8b269aa3440b0f944b5807f8ec309e5b63c353de77b4f88bb695fb802cdd6ee51a30da232c4b4800df8d9df86a8f491afaa027d0a
162	1	106	\\x0bb6ccc8ba72d7793c18377f7e38f2ac5b8f0a7b58005bad43ab909628cd0c38d128aaf3d137859ebc58a6dd079be3a4fc73fb33d9bdd038e2bd92074f9c8d00
163	1	54	\\xa5f6086216578eae154e1dfca849e068db5ce9f4c342b03f6ade0d5f97b27a71358d9eb4f508015158793c39e33522e7693aafdf739220a72cf40464dd95f303
164	1	261	\\xd85a3a548e576e26d4d525f8d262d8751f0fceabc035db59137dcf6fd537f81c3b3374b2a5e68e23829128ebacf2315c0a991764d85d625d9c7eb954903f2e03
165	1	239	\\xec541065e2993a28f2f65dfe37847f7669141e37ca20fb2502749615eb51579455f906c8e4df1a5d872f6911107300934feac5516d8f95fd00905f1df6fabd00
166	1	298	\\xb6f802a02fb0ebb9350dcc71578fc58073466ed9f95070d1c88ba86cc7a02bf34cc13377dce6c85716ea6fb8aed5fd63af12e7a3a17aac34a62b57c984d9d909
167	1	158	\\xd40ee6f600393b09999eb33829eeeb114830fdea8bc7b03c8bdfdd9b13a9265571b95c3e3b2b2791bc655d1bfed5f28def66e6557cf447eec2c2cd8dccebee0e
168	1	157	\\xfe779688d54803cab125e74b382d703e33a5707d19a06542dcb0d440d6f35b852ff5c480508a54a31f7231d6da593e2cc75b4005565045ba609c49f46b332a02
169	1	174	\\x6a445044b7dd16758b5fa80da834c82d1ef93c2925840f513984f499f7d2587a94664b540fcfc9d1d9a8521fa1d8644c93f632597ab02d132ab018c623921609
170	1	376	\\x58468997af66cd3a8574a696c4c4715c9d9f966068790dad76e506107328b84c5cf9a90e478f0ca79470001460a18e009d65a1dc6dbb2f62fd66cf7e46207a0d
171	1	421	\\xe7fd2ffc46bf5138d36d876824f7d1780d3da61b02977fdad0c8b72d193f482e8d914b3ceedaa249a54c26366117419883e49cf6398e4c6429c8e7b57fcfa20c
172	1	409	\\xb08d44e38b44d0621656db6926651dced188d51843dd9fb03cb82c4197fe6b587243462768a5fe34fb789471ade99d246530c84c3f5b35de52b9e796fca02006
173	1	423	\\x2407b8300c947366f35377a9183154d20428691eb1511096c679fc8ca0959f9f0808f03072cb04f43965c771b286bc0327853c00ad8a260c3b87354c2d9a9701
174	1	150	\\x8aa026f382a16520baafecd2089f0bcdbda0c946a528f623c3e5bd92b68edf8f743d363c7c6ee536f7ac8ca2ce355a81cee30390d874bde00b85ac92e9862105
175	1	149	\\x7d044f1fd61bb8f6bdb9b0241f1eb47d8f213ac59593e2384ac941812b4f3e0e464ea838b3ecee738bacf604f2e0e6294c4feecdaf8d0058040c42f92da8ad05
176	1	116	\\x8b9f62d8f0a5c828ceeddcc8ae662fb578ecb5b88c77bc4bda4a59dbf1193c2f343ac446a98e05123f46e4c3740f55eaa4f40ed8371bb2e975a9cf365ae6a607
177	1	108	\\x4a6a19460ad4602e0e742cca92607557ee01283029e6e7afe951fc485ef9a292abbd8b8574f4aec0349e9cebb17fe2b146af7e762dcea1131df96be196f9950f
178	1	226	\\xe612f205092d9739db9e7b9c2eb5093a66b060a40a7472a41f5e81a0640ddfcbde97d0c47e3c4e71259e4b0915f5773243cf5e5ba31157e43b7cd64839df1001
179	1	358	\\xeae2620a8368355c07efee1e61ba087c3d4cbd424c3a108dcae1763077c8864379783a19017075befbe9eb0717d603fdc8a24ddbe0d8f9e43d9b4a1cac5fea01
180	1	238	\\x98de2e9c9824aedf75f5a3b6064bb2806fba21cded228574394eba76b6cc8e4fb55023d27ef24a8f1745dba58486bce7b6585873f9b2d6dc0f700c9fec28ef00
181	1	126	\\xe94bb6199e48f8c11c0ca6d4627b309df1e73e453c456cb1c183d35708e2601a4e0fbb3be0c14d331f582b1ee57e855382340030cf792f5c935a72f3cdac1a09
182	1	224	\\x04f4ffbe3790ede90871ffefe0b1ce7eb1add8ac5c9a13aced46a39560ab34d8e6daa8dd53c36f4934c7e30a4e4272c2612305b11990801c3f7c0a0ccf4e160a
183	1	93	\\x37a6e279fee86f7d083c6dc7f3fea37f8f61c4c0886547c765a122a07b6cb0815dafcf70fea9876fb99b1fce79a06a8e7a2a2a45c47cdd5d1bb14f7f9f5e5d0d
184	1	259	\\xccd1eea080891e2a086e9335756a54e6ba6b7e11f20dfec94c228b42cd9c0a00ac73a1a20042d8fe7bceda045c7fa8e8c453aaa56610561b6a6b6df90c1f6c07
185	1	374	\\x9a0b4df636d99bd45b5e1fe5b3878b577368464688d9cd700119bc54f7e810e1b334fa97232571aeaf50e99640d7019447edd4b3ffdff8da760cd46111a5f10a
186	1	416	\\x031a611aaae4fece80a352559d735709e3e66fd969cbb77f81bf2385ae7ed23b69bf5810f3b578672d47d235b9a057e2d49e1a5f92b0e384d9bef553ef07a401
187	1	344	\\xe3152cdb763fdbc9e80d9c14abca7e48e61598511522b8054b50f0c82b7e2ac31e064a688173f18f7c1d830559fc1c8dae1e6f0d165122d34859100352de8106
188	1	177	\\xc28ec15da8643a72ca7fc4485dc805a9219de339972b487c7afa53fd9500d0c4ce89dc1d4f478bf47ea5aa877b4b350d08a675e717f412b425a218365e842803
189	1	180	\\xb8c9cf792199929ae87d965204822f90942881a00869cd48712bf4d04c6f17aa3e860711782e457112a8fd89358296d40f79b6b92bff7f891ce7956f99ae0c0a
190	1	223	\\xd0ae608fa2c229c3f2dc010e9fca0b88de5791b8d84cb4705ed83b2209d50acbd37b596eba3ad577d116c5f92aa986e41301c58cdd5290a01362bbd189971208
191	1	80	\\xa88ebd7e774eab2c1b1b091cd4f4c15ef85f006ffa3e9365ad906cbc7a0d86a02e09303f316e46a5112f744c124ffc6a8081568a751f9be02126a793e44aa00d
192	1	85	\\x7cdd7750ed84824a5e125fb5a1a2ceb04874adca8a0d6e364064f1d2b142a566098c7b2e9b3a3cea565db941809db6128650eab09b07241c6059f3dc6153b106
193	1	86	\\x3934e12dabbe136c5dee2b6601c77ce10d3bbc593ba86e08a6c4c82696926577179edcc0f92aee871d5758160f6eb8b28d31f174c6e6595e8365dc289c5d720f
194	1	352	\\x01d48e695f208a9b195c76de732fe0be2a18d2ead0b0073d7648b3660ab86c1dcd9513fcdd7dc6a12fb2ccb4d6e8798f6d8c4006e39472414ddcde26c122c208
195	1	65	\\x69c2e0a854b4a1ccbe585f2b4a0cd4ecb75953a81ae4cfb31e1f3b51a5da6c659ba766ec2b711abca52367de4b9432c3b0cc8f1a95ede318f9c85ec5203e0c0d
196	1	25	\\x23b128e62ac6885f3e4e5381f985d5cac1276083a00cba505991c721befed35946c86e6f37ff065967387575fad2f28771356bff596c7b68f3ed26602d261c08
197	1	346	\\xdc777fae8b2392867ee8ace9803346148845da692fff651a7f665b8d23b0a754ff2e5d01a04e63c7a89d142da0b4cee5314b2ae05c606e17b873edc86aada708
198	1	276	\\xe1e9643a22e1df98a29d818bcbd07a2d7d6bbca70c229d06b25a7d9d255d7033b443560c6b13ae5a810987214309468dc9cc5380f85b654e692e4114c9cd700d
199	1	170	\\xfa69d19c9a24ad6a26fec612bd27a03ac213e1e70554be77916dd995f1a61432d514599991c10f32614736c3d8aabc323dda447e94fba175c9804a4a9376f30a
200	1	302	\\xc064e21dbfbff3fb656e3e3b7f4db6ba4a818aca5eb52be6edaa6a254cb6bd1565c3606cbe5cac2a31447f57258e3838182535045c638c379288047149474300
201	1	413	\\x4781050e0cd58f48314703407abdc4323bc88be929e4937f0dc087286eac5a83814542ac777c46c8a4ef59652e427ff7ade5d71e2beec275c964fc057655bc0e
202	1	321	\\x0b070def154b317c7a743c345d24fa35bb24c1c0b0f64a109e47c2d51f3ad3a66154249e972e7e4804a3cf62c9460f08f60291938b6dd8816e8c54f9fba8420a
203	1	418	\\x488f80f8d040c3653d3b988ca4ff796786c1c4ead55ba7bfb05f3ac55a9d9866c6b70ca998d0aeb58cf39cb1fa8487544554dc5e92c8e0af674ac8c680574f09
204	1	143	\\xe817c08c74623f2f880845b09a252c2df0f68555f76129965baf3e76004a8ae7c15022bc82729f257c5d1d9e8a86764fb80b88584001afc18d41ae6a00c21d0e
205	1	402	\\x415cd66c0f920fb845327a505e023771e36e15945cf239fcbddad2707c089cc6956e7c7dfe4692f7bec9faae043de2074788ec66685a4fc0de5d1cfa5db28a0f
206	1	233	\\x885d27a1f2e099edcc3dbcfc4f63a2a4bd3802e1f8c68cb25608774692f3a113e2ddabbb20d9e20b0ff69944f8200a9241392e259a8636703db14b7495150c0b
207	1	104	\\xa1281f0b7a51d10958070e70cb8952e08d393757cff5acc366fc858542e59b872cfc8890c65c04974ad5b2d511c74989f2659032e188f3e20f076073cdb54c0e
208	1	290	\\xf03d3bf6b5705af5d440d8b62a583ec5d53aad1cd2c7aa86e7c2c1680c9d8cef1696ef8373738655d229bf2191c13f8da76e18e1e3c211854393c46d5fcf5206
209	1	208	\\x0a4fc828bf497b9ad2bd2ea1a36e519a251082874d86d83f6c46f44ee3de94e2d14ad1dac0824a7aa90083277167ba3571884b1bd6e03af367d0e802b41f950b
210	1	219	\\x23044b66279ac5c5912c1275261e1576176b4b6f2d89352fae4eee2720c6fc7bf010fcb3e8298e6a7203d7089d2ba8f883405cd55796bc0b3812c14df9483b0e
211	1	13	\\x993940e47d2f83eb908fb0034542354ccf122fa3ca540537f67f24d75c16aef265faef2930092af48f9e583b46b9312ddc2676b70b9359843d7bde50f6b07808
212	1	383	\\xebfd968511487881662ad63fdfed756707a02a7aac95378e21dc455744f72aab176c025f3a78cc3f7c0a94f19ad63f60cc67aa3b989fcdb87b13b7f53c695d09
213	1	176	\\x4ef11a5d05f4d22fe6eaf86fb06b8961adc4eb822903c29025acc1048c722a91fa0c4ed400716529d3878fdbe19c43f741b1d7fcbeebc7b853b10c8244d51700
214	1	338	\\xadeaf1cc2f2ee1d6097f813720e4e24c949ce1c185e535ce29eccac2c9a4b86df5dd3833f05ef0a5ee058d74b200f025f5006bece05ae3f2394e44c2dc20d908
215	1	407	\\x1b4c42425cb96fae2580b7181db15d113a7b713f45592ad1e3880d91407d2d32fdecd4932df25b966300ee232199a69d0c8039211545da34f00493735463800f
216	1	137	\\xf7fdab20387179b507f0b4de17a8ee15bf0036e41e6d832f78a473a90c6aba279b2876fb525f2103fdd45848fa57b6202380c9b52290fac6cbd7cbe1428d0a01
217	1	422	\\xc107e5556851c4eb4bd702dd111a2a82a9a5062b4b6195ac983327f9ed911bd9cc4f81e0321c57bc334452119bfd0d2f7b5fe61450297af09b1567258de25e0e
218	1	46	\\x6682afc823a9be21f7427f11fbb8d5f150958bea411f91a670fb159bee6d3a2a5cdf7e249dcfddad4fca8763ed82dad8424fe617d997c6eddd510b8926bd7d06
219	1	356	\\x480f980dbedebb19b27e8b7ee5006462db13a3aebfdb2ec3850ca91dd0dcdae72f8073bd37d4aa27bc2ba99315dc7b62eff6f4a75131d3108233bf1f49aa2704
220	1	293	\\xcf4a8d96b427585f3d89696b42e60613916cf8bf39245bfc30f9d942ed5a6b58177431b08794ced8f39b1fa3018c7216ade67e722ad658849009b3e71766d10c
221	1	305	\\xf57ae173fd21ff0d3bf1d01e94af6e6fd00fcfaca48cea441a1ce588e6a46cd954e7bc3aa6867def9824fc0e3a197829d7d536b7f290fed800f32d42a7a78606
222	1	342	\\xe66a85b20e08f2646dfeb13b7e10e9d8bac25ada629654c5af085a207c7fa51c791ceca3e4519bf4175a6824174d2ce75e3e4714fcfce62d1b912a9e469c6902
223	1	246	\\xcd7ef4d318dc85229ef3c206d5d572abda99448184ab946d2faa7e0bad03d6435c497a296c644bac4c8da2e0be90c2ec0764782a4d9a479cfcb174f886618a05
224	1	262	\\x3183394402f828d524caee34aa5fffb855a02bb43a3ddb125abf91a5a385c1b459fb6587adbfe98d4e0d272a0f2f94e819cbfc91ba0bad7af0b08f3f3db9480c
225	1	312	\\xdb751282fd3c7c5b88fe4f61d22c217f9699a9550e0a05aab3de9ade3c7e7d9f43ca488f15c4ce302e233a2288aec937b7ae87f468b0805241e1b37e0d64ae09
226	1	38	\\xaaf41123dcb02c010e9150973426df7b48422455ebc2e203c124768585376ce5018eec041c54f0dd197ca9be3429f4e7d4d7e33f978528b0a1e2ca5a0064fe0a
227	1	320	\\xd7fb904de6dfa9ae24a9f1d25c1f04135341d1419a22675074dc20da5dfac732f1bab15275ea7b8c54edf1194def4943c6ad85ce185f032a3e70971c8522730f
228	1	272	\\x1c2b6a92ee26fb6c65a5ce22728ed1b8c140bf0e67e084716abadb180aa6450703d19de398b376165bc6771acadd53bb175223270e41316743ba1a8fc3a96401
229	1	281	\\xbac1b40b9e300237be859e3ffd64ad5549a35b7b1933d51e7500a724930f69e0181a8f583070f499693f2b56b8fc6f696b33e7287f0c697dcdf5e232e0a3450c
230	1	336	\\x20c72632e0f7ad7fd77834c5a5ad362b3ceb8ac0398f6defb93ed13f8b61b99efe2d80d83d047821e053af502ff1c144e2064113dc26486bd1cbbb60cbf22802
231	1	173	\\xb87ef0741361a6e4da21923a4706ef6c176db0d6a685bdcfcf4677bafaa4a476839daf76407a34548967755a569a7e4bfc26df8af792ea06d3c31e9cb213d609
232	1	167	\\xebc25f038fb46a7f81533fde511a7b2f318d5e815394354c972a7443e26ac1c43dcff026cf3fa7cdc54ab100ea6ba5797d3754279f4f55b8075ea0f03897d20f
233	1	232	\\x321da0c5744aee0b5015f740aba6da3ec0da90b4477150e994571b8d0073183e6bffeeefc82ea4ea6b90b92edd7bb7aaaac857ac9224e6b4769eb933af99ba03
234	1	55	\\x361bc5b43a3807f7d0fd3ae30b1fdbe3e1c14c4e1bf591ab049a66f19443cfc5bba8911bfe2c25a3d88281044879caec6523321593cb8e15de68c2f1f7c6eb09
235	1	107	\\xd6ffe61b0ba3734b9a5f85173bf65cc222cf73ec80c224cf50dd4596c349a221695ab560bf6620b635dd3884c45ed9d2aa49e23391ba307b611db5c9c610c304
236	1	212	\\x13a693261571c8609b1444326e33acb966fb6539a36d346ab4b9e59bd0582963d9ce99c68b28fb9823a1102fde7f82a520af6d9cf8696ecb29bc381a5d52b800
237	1	247	\\xebc7d8f2367a88278668050370ba6e76dc2bfbacb25488e696e12766ffdf185c666c1813788c73e079d1778d5d9012f8619d24799ed0493b9c5f82695ef1de06
238	1	58	\\x85e0f04dfb08c753ce568f85a38d25e8427467bf8a563b56ce0cf248dd1dfd87a19a86f7e1c49dd726eeef907c638149736a072187e81bd8de18eb08a702190f
239	1	360	\\x723d8f14880500f797754cd0a4da65d9f32e0a1d352602577ed40013d9b3a3e886b3044b7b707796d50158ba0a4cff536ac9faaf8d022472981d44045c09850f
240	1	18	\\x4c627d9546159cfe5c39702afc6be25d1e193c23eb42deffe421fd71b864b77544b5644a93cc3868260937da87371f1addc498ffacb4bbd39282c02b6ab78e0d
241	1	303	\\x53c6584061eb763ab0c938d4e9f75f2433901fdfa18df88b89bdccdc6e0544f30c012d269bc87be61291598566e8681f3aa54be06acfeed0629a138d4b42e209
242	1	194	\\x7afb7c1b0bb71b0e3e575091df5a5a2d7dbecf5b1020b0a04d7a775a772a96ad44cecac7a1a90a3f8784f5ccc85495c26d1a0dd8e5322a34748e184c852f9f0b
243	1	28	\\x6c7c540ecde68fd44182b2fa6f2027c03dcee644bdd81d65685c44b008d9af578ea20a00cf3dadbd45b40b3e7fff468a15234b60cc64427630678d0c09569708
244	1	277	\\x5c2e748a111430d67c640ed21796ef9cd73b21b8afa4a18bba8ecddcef35214c59850b4903a6cf97dd9e05f0a00dac61566a010f5058077b21d3b3db234f9e0b
245	1	152	\\xdc20bf45bea58e7718d690c6f4a81957a35297a598fa5ff92350149b00824de7d059ab5b5df37c43e925a2cd5f61e4bc46d3589b44ae4a4b3d73ca959ed03808
246	1	389	\\x476c8c247e1ac9ec76618f0bfa511159352149e5156335255997d8e690f30a0144aad039e80364825f2e774e7ffb69d3b45a98f1862655c5fe546bd4e68e670d
247	1	363	\\x721b8223c8790652556207becb28d467cb100fec643cd43de5f8170909933695140a444a454826ff58334748b00f10668a96dbfbf62bb2b9e57e20aa19911706
248	1	119	\\x38d7e558d1c48ee055ccf2cacfdef0e2548a5087758dfbb65b17bfb0202ee7346c8575381d2bcbaa7622d0395ac08db2af4665d6945ab5cc9fd0362ceb24a608
249	1	317	\\x02c4e7c3309a59cdcffe66f0923939a95657a19ed63d6bcc6573946554c3097c2cab1047f0fb8a44a597988a6f7c590ab824fd013c209e163a2a45dabc92500a
250	1	134	\\x541ea7257189a460d06848f71b40fb5567f584d5fb7fa056452117644d34e9f66e4c0ab6a39ed16ed8ea460564d1c1629f1b38806c37519e22cd63dbc00fc10d
251	1	31	\\xdcb523ab6fc5be0c53e64994840de83d435d3e7982df88795b47bd6786d1838be5d18ea33636a72fb07fcd7849dc50381483217cb773d9f37f604cff3fcf9607
252	1	378	\\xdfbe34570f82f63b808229ecc28ff7a60fe8ca74ab8641ae7beef716876896cee677f882c01f6772afc371fe8da6b0882d7be5572c40bbdb7afff1d05ecdb400
253	1	367	\\x38ac805dd773e114a8635822df0c299ff6393ce523c6055ec4345da10edb00acb6df70c3fe657e0c37c4e8ef56fcf98ba72df32fc6d61d4107e95235b0d8cf0b
254	1	3	\\x0d0845fee97cc599d6d6c1e9d26a6c38e1b77a3eb19b5ef502624a57da8206781b2c00abfb3196644c6cefe855dbda54345220508e42312124bc428da63e700e
255	1	7	\\xdb8577e0916ffbd64bd3e7c890ddf88cd36556b24fecdbcfdd45176063ed5504ab8a929c2e34b84db5531f9e1a091fe93fdd85b5d46ffed3a26db4a53a646e00
256	1	20	\\x4b6130438d65912a3d5cb25d2fe59ea184fe6947b738e354e0bf52ad2a2ca702266e7787089de03bdcb8976611c1fb62eacb51b17e1b7514fc53cbc6cc59bc07
257	1	43	\\xdf9ef046b78f3d5f701abde8b927f45bdcf5c458678d942bffafb23b1711c61dad1739ebd2554ed95735c4b040156e90cf7548f766aa37977c6e0bf3b3b91a0f
258	1	192	\\x78d4fde7537ec29ea38cd1f7cdba633af8933e310707b0238a23dd9857b46d78750ff373f38d2e86f39b6a95cb6905beecad7ba2f117172fe8aa84bbee886902
259	1	242	\\xc719289b21e5bb71b4219fd8d87a6d2b56207bfb6a67985fdde05c1d0d2325df680f0b438bf0b4383ad988e3d63d76a466be829dab2de68b436dca5091bd160f
260	1	351	\\x0d966e050875ee919e7e36f22aa134259a119b56eb1f01d15c95694fea27445be64a2fb73b35e524a188ea7a176a39f2d4b818a48502449a4be8bd21a994d201
261	1	113	\\xd80227c4b0946d5578dd8dc4b831d35c0ff8243a23a3db19fba1602aceef40e00ebda9b6f7f654afa3a0392ed3273fd453af7351f0df22c07744f326b89d110b
262	1	114	\\x433c7dee52e9fcd4f273a354ad395c83f2fe46ce9605eb0239a41a56f15db9e77d5784490efa862b67d6630045a296202b78e4a82caa2230eec97c68f943d40c
263	1	332	\\x7ef4cc42f064a9669fdc7606cc7e6ffd933d3dd2e17a9bd436e9471d0b33374aea14c6c83264a8735c7d0b63c2b13956a71481810c330d36e63782ac90b8400b
264	1	88	\\xb8986f6014afa4f6a6113fde86bb7df20b5227722178b5040cbe823629ea2277dfe8feb7210dc4d51332812d0e416d66b12ee20b4542e3993e38888410e2a40d
265	1	299	\\xad6bf8552cdd429807d913a9dbc7e68aade910e2f8cdd696069c1e3fb899f8f2b486b6635919561768018b4ca70298dc20e66838d1f7a3a23e9cf9d7ca2ffd0c
266	1	23	\\x0ddf19b4a0985352ce3ed778c5ab81c17b3a1cc5ba4ddd4851f8c582ab846c5ccbb07c787c59f144b3d1e73a563182a3b7a16ee192014ae4eaa61ba0f95e4004
267	1	181	\\xe47c9960c8b7032302306ee38c72dd5a078431734ae854d6bf878681da13c249b673091679697677ccce37feecc1ea97cfcf00c022cdfb464348ab16e038ea04
268	1	185	\\xbfaa51081bb0d4d83667027d9013f3382224298169f0672840ab1d36cef210ae5c6ba45215c7ff80f56fdae000c8d5480fb477a2447ab222ca1812eb76331004
269	1	287	\\x860dcb7f8bc7480ae50eff3f31bb3b01ebe1f86161042d000053adccb3327115e48d84821e56b031ede2a1072bc3c0a6c8bfb37e2d3b87a7c474f6d06d93980a
270	1	66	\\x629eea41ba35aeab197964ede5763367b60a47a9e92f0271ee9b21d5f190e8df104a5e81f4269507bc8d6e60099177781442fcaaae81d7972bfbb06080570007
271	1	236	\\xcaea930e3788045c7578f2311d470ef8d825a5ce5c22fd5eb7942c87f725e84aa0e4e12bf8c4da0aaf2cdfcc5f4b83560913e29d22784db810099541c65bb500
272	1	394	\\xe069fb21cbd876396d46e63f612046de56c4a9953c9b38f330eb53975e25d32b41167b9d65b988e9f7fc07fec7a9bf36fd364641342797a31bfae1923b67850f
273	1	186	\\x10399a9fb11fd61c33bcf5ef718f618052f0300724909d600e338147ee082c9cd842da092a73ae60a17a1599f15314a9c75fe7f5a2743c5273deb1c6d8b1bd05
274	1	230	\\x8c6871a61bbb8ff393b4a7ed7fc35d26e96546d2623ec23d8050866420040050d34f148ef3bd3f2977be4457d9c9da7d643e01538ac91d301339d330732bbb08
275	1	329	\\x913595567167850365b8aaa42973c8ff71f93fc92b84888bad94731fb4be5dfca9111e12585a29122c39066df54d7edaf1394b7192c6a1f5ccb9b45bd88bf303
276	1	373	\\xf99a5705d2d8211bf8fbaf27e556d265ac95cb27b0eef962cf05038e8164d6627830be57071a960b34f0faa3026735785d7750075262779b008f7ad415f0480d
277	1	50	\\xe57294c4693256a0f7bf4a664356fdb00688930e750ac7f1a10598e481792f9dc9a2abc31d98f8e83a1aabe6d221fb114fcddc636eca5b366a88a7294dfa0b06
278	1	47	\\x575ae60f6d1f250027ff6f49a98d48b9787a6241fc12c2ece1966be638bfdc14ef39f3bf14c778f27a15019045c57353f272cdec2ee01eaadc7f33293fef900f
279	1	323	\\x1ab691c3fb6b22c5e44a69b6b67b23d2e796ba9439997824ef15fa3bec07b830135c2e53a4dfd7cf02c82a67f3ecdea578c9e27962ec01f652d75ad502c6540d
280	1	318	\\xfac0d4f9f121a4421da0e0b5a11c9a1af1defbbf72810ddd838da29afdb7314dcf2047800c29fe948ab125090aea4edfd51224fad6b826c0517864474d360e06
281	1	203	\\x4515deb6908155f889079c1af891c589acc934e96c6439138e11384421f37acee477324b5f4cf41a58d29d5c2dab7bd5af64f20eb1abdd535130a88017824a0e
282	1	122	\\xd42762d242c414ef80cfb61938f09f5f6c734d85485be648d3ac3ecf34045ec4520f17957ac8866d44a80fed91709fc88c498caa6109215556b65f6437b30b01
283	1	26	\\xa1c1eaa0362ac0749e51d09393f89646f5321474fa9baa12e01c55a590915c43fc2b8e66305a1779a3105b21553253f701c4ad75ade1bde0e2f9818a1971390f
284	1	366	\\x90b5b3a1a5a3d18aea63b4225f131cfd4e4887bac0b041f1adaa44cdef3196e1f9a5b7ba6dfc5122f19f2c831a8752a6ab216bcaac8cc0788689a426d303550a
285	1	381	\\xfd1ba11cf3497f55195ed74a708b6080f0f70223683637cdd189aa7d9d7c2cc64eb177c7efb38e2d87cbdbeb358dc66c16d28075632ac3ba6b4d4f29b2b90d07
286	1	153	\\x533e0e40c8cce9067e34edd1edacc981cd2351c3d5bfc68e163c8b50e257a07bfb2404cf0158d4092af8690431b4a63e2c1e5ea47a13f992f34b08c6e6904402
287	1	11	\\x1451d132e955979b70b4c26a0ee2737db0266647605128cae773649e1646ed008b2b7021be7f7158d8af29a9ca19e1953769947bf765c6f53f8aae754f59c30b
288	1	405	\\x5ef13948eb30a997e3365c82abb40be506303e8bf813c9532aa6d5c0a3dd7014c457d5225495818fc8f2a89b264065918a7688fe57247babd834a63a872dae03
289	1	288	\\x278a22156f2d7293a0bf5a37ae50100bd140043b584016514b36fbd128be148b4bdaeae6e9dffed542636ea21756c51f3feae2868659c4b76a424111258ea603
290	1	324	\\x3e6d6653f12f080db9b4fed5098f043a98f5c1f0bfc2bcdaf58014b946bd645db2fd13aa7b94491e56f0d327cd8cc9aecad8d4d8fc538ce24d06f1d9fb5c0e0d
291	1	84	\\x9a61ed8a5a774c12413b5150fc3acf15645e84efb388b28679e8ec939f6ae3799e76bb8c4fe8f3bddb643e329d8dc0f23e9aa80143b0b967e5070c688e73b403
292	1	213	\\x893b82204764e36c36e1a1bd035fd50e6dfc9729c4aa1c6df1ef761065647d19139794a86e046b5487af6c5e83cc96d0eb92d1fd851bb8b7fb81e4e6c120e409
293	1	33	\\xff7decf86d223397965c0bba2828b3e4003cba26d6ea08adaa751bddb7a92d5ca0a748f7ac892e098fe9631de06f188966d0d03c47f7a1b488644d68eaacd000
294	1	291	\\xb8adce5aa3805eb0110415e318b21a65f8410f4a74630963562875b96bfe87a11ee0b07af1abba4149eed936619b6e380ce09e0ba0e1ae766e75eb5a2fef6305
295	1	274	\\x8bcb958d89ca2fe3e6b66a9f7cabbfc8fe82d9d9cdc8a8e5a6b1b9225d912eecbdfbe9b8739eb5e9968bfdf394361aff0d4387edcd8b2a8459eb52bd3759d306
296	1	8	\\x7cf5ab7ac48803a9e1d035db0c871dae3bd8033c2b9c38563cec14a359a66eca000d0dcfc596dcd739191dbb31eeb863dad06dd665a7a0c5af073a47da6e1a01
297	1	265	\\xcb939c15855d0f23f21f9fc16a3923c3fe827613c138440ab3e228ca331139144be809cc458b48e60d6a6f466350e1ef4a11cedb9697d8704be0655dcd041900
298	1	30	\\xebf972ab7f17426d9ee12b667ff38c5f207074e3db1ca56308a33cca6d3430e2c3b02b4d8064626569ce28f73ce9daaa4e67ef1c50612ea47f2bf3d1d6dcaf0d
299	1	399	\\x1080e1f2412a05c1e04b900c467824565c35b13abd3e5e9d8dda1c01312a08b2831eaf4517226f215eb64a6d68f3f74f01c1321734f0585e469197bc76472205
300	1	45	\\xcec1fcea64f46a4056124fb38912167efd345b87ffb1c30d65ed66425d8573344ebd2d4164abb6a942abaa8c421f2db51f79a0ab39e188c0c1b98019522b7e07
301	1	270	\\x716ae26b7437df6d269287eb2514632ada30dd8201645986da83277eac04a22282e8a3b3c98f273b01fb50fb3fdd119b7b13c5664dcdfb526483c866181b4a0f
302	1	75	\\x9f057da074de288d367cd89fab7bbfda90b7895e59856f6be2441b318642eb78e067fc44e784f25b02aec8d8cfe60e082d798a2826d452808754ae5a0a8f320a
303	1	248	\\xc373c5b1f08eb4850cd7599bd24981d49c842b20fd35bf8247aed9c649b7a567c4894f78a4c99247c083846963311f17343dcf5e611f12f158e200472fdb7e08
304	1	133	\\xac96cc2d3910733df5f319f01d1bacf0e8ca99df84099e6dda5f8ac9a3a7c666f2959b8f65e05f67dc2ab0f572f80c5b83c8c1d885c52051558a2a2f14e2f105
305	1	19	\\x6c94e9acd5f00468db38270f18fd7bbb5ce58a783ded7281e04541bbb69c1281320314ddef83931dc7e5e331883bc35741134d9d666bba79b5abae2cf0f7b600
306	1	369	\\xeba840e2116e4599df44e75c157c444930994af8aa570b3434c7e33157a4fe819115ad79713cde820a9dbce0080b11e65593697fac9b3cce25d665e6c459c803
307	1	385	\\xd069cd35940371ccb541ae1d721bae3192884a9d1b7851a41014a91b9816b715f43027202ab62b1967f99755e6c01e9c13f921259a5076f3e8300930502d6006
308	1	29	\\xf3e2b78169aad4fb305351c03cf0aa26e779954414de47ae95a99a9095fba4f348c992f9ced51a7c3890b3c555986f4dabdfad13e546530078a92ca8b94ae200
309	1	4	\\xdd47af7dbd1bf1290dddea1f28f29e0fb2afb2a17dd63fd5b75d6a6007dc5a9f5fee7c41609e2de0322dff44093dd66d328bce7a3f3f5166b64608c60ee5a806
310	1	109	\\x2f88384c9b6338309696a62ce1232dfa02c6663a35e504325785d0774d03a5bb0f6272d59057648e50c98006023b792ea9929da8bcce58fd0c84ea5c617b0002
311	1	139	\\xd814887cb941ea18c7737b2e30ecfb93de60a46fe2b34cd05afba0a529065da16957fad82c62d5103499a4be253e6ea82f9e18302bf4d5a97587baeeb298b60b
312	1	147	\\x81221d4956fb9d028be02b07850006ac83f42a3a08e632b5d1b63289beb2fd0cd432ba561dc7f95eae6ac293365732e8ff619b464813aaa634afe3c70812d905
313	1	249	\\xe2cb0d5ab6a0b09a1ea43e0a5490b468ad76ecc27fc78f5bfd6b041e8a7dcfd2d61e6e7c10608f74282969bed33c4eb6bcb74e448b6b9cd8a3d25ef66ca0790c
314	1	57	\\x6dc94f523e846144a3b569422d9b8205bee5fc1b550e6c9993d75896b64bf51521905d9b9eb1eb67de933082d99ed887550c16e9770ad6aa783f100fdc0c370e
315	1	112	\\x9fdc0ee9428c7679471952244c68387ce72b8dd036534dd4ea68b13005a2408f0de52e45c8693e653275c1ecaa484d5627100bd58034ddcc3103cd244590dc0f
316	1	252	\\x26a740ae240f0ee7fc979e020bc7bc7262622581d57d5be031f134ede4d8d697b59b0df4fc3cde4fa0d9204e389b2e728168a64d8b81105dd1fbf6a28a126e0e
317	1	73	\\x9e711a0ba13a55f4f83223c11ac835e79bf24e7e11f61707ccc6c5688becb54c4afb28157e18793c71d351e3f429d22d014e44a31d0e2c9a2e9e87af01c05e01
318	1	403	\\xef61c469f344eca0b9a3989980793d7dac49fd15f67260401aefcda1dacaf9d5db66c3dfb3e9ba69112740a333ec97037f7898571c31c139a19de34052b5f30a
319	1	206	\\x11cede0050f78b0cb1049b857193fe75f3f096f109bd148f6ba96413ef836cbee8932335d8d2492e6fd204c4a7f4ad9da65659fb413114900f19df759b207c0b
320	1	395	\\xcc7b70e13bd49c59628b3b9b1107d011877f12ee55d589dd7f823c5484e06bb43f7d35b3221cfdacd35e15f8206f901834997a1c20b941f04435cae6dd0d470c
321	1	319	\\xa8c2c997f4c38a072944fcbd48a204d325e8edca96f0e33461b686f63aeb1cec83609187f71c5b507089399f90ca48b6f5f89a0a82285116b64ceafa57fcde08
322	1	171	\\xc2b0d05e4884c4afdd422f7e03b403f31d164505acb0fafebb00756fa070e4d89d1a9bfad99f73e3a34d62aa7380cfd868d525c49ef5548c66cfd743c278c803
323	1	125	\\x07762663259ff1c63305e17014386124ff586940dbbae4b380d1ae2fbddd7df276280d1b2821d18e48799397b3fad2918e0e85db6699cc9b00ca7d11c819900f
324	1	201	\\x0d7db83588bab1c38699a7ed0b55d8db2a41516223ac7346205756dfd270f6e90e263ef7681669bbcce192604d446e5c64dddd4f418481a75d0a5d4c99ea3104
325	1	296	\\x0295f7bbfe8db067eae8d21f5a531fec667a44b2f972094e23407720db3eb749650ff75f297aa43202bdc08eba3d77e0d5c706fb4564f7e05c6f15aa93f71508
326	1	313	\\xc161c89dcee19d748c3d28bdcb94f90488beff7ef8b1fa7d84258d802490fbaabfe07d1dd4669c8c424b7be1b14437691cd68d13493e8a9b388591803a31a901
327	1	184	\\x81840f457da74fa4861b86ba7c4381f3073ee2e62dc553f9b2da4cc4ee3a84a4cd038cff0a067a49f7f08354c7a0a24f8a7bfc2100362be33a650bc2ec14b307
328	1	244	\\xcf0bf9b4d9016b63521a05db35a73a99da78d7012f4e5acf8485443df9266a400aaf014f58be42d714e9e6875bcc285c1eda9ba61099430c6300c29533659302
329	1	163	\\x944ea22c10543c554af6cb068a4e0f77fb76c9d112733e7f8a0cb7bd1d9bdd81a93aa0b16015c3660fb2e13a796cbefe9ec13ffcbabd2f47ec073d888080b30b
330	1	15	\\xa1acc3180ace38142477d0a7f159c50979e6aa29288d3f7f317b5d3fee870be028ff8c76430329adf0ef53dc99a6e4de9e0a1adb13a739b9faf09ffd5d9efa02
331	1	191	\\x1e2e69a84d832ca41078d99d39b12d39e5c70d41686807b35d4d49db2b13058d1b37677dfb172c8a28bac4c7d3d3f710d85ba54c3bd7aa62af13c5ae3d617d0b
332	1	335	\\x54f5b48222233a3005f6c2149df4d5f209d929163adad74be075bf56deb1b239b5489f695634febde1d0076375b5095774ae32b50fe290af4cc99e389d95d90b
333	1	182	\\xcf68ed37912db6e3694974f58d3bb1535867d97b081e1677464abc633474a8b0c0c4c7a8073c1955783369ecd4055a2e12ac5f3c943e3f23ccfbc8f4b24a2c0d
334	1	148	\\xbe36f7dc9de69a29b95f6bd161acfe2985f5a941de9394f604375bd1ca133748aa3054f1f044ce70617eb8e05668dbb08ecb46372592277429591c258185a50d
335	1	391	\\x51fac930865a5aed20cd58c42e333a57511326e7be0bab309bae1a5ec3a65f8cd0ae9bcaa7cfd02f8491ff76f3b7b5f808b962755ba944f508e7d271cbcefb01
336	1	160	\\x9803261de7158c0f3ce3bbfd3da6ba871bb191c043df0f0ffe1bbeca305a8b08c644e23f01f7d87327aa5835ab6225fff8a3e88b15ba60d82f5d1a0515db9b08
337	1	364	\\x00ad668c7e1adee0b6450fd73baf33c380470e13cacb85f2af361e10c61c0d7eff683521dbe3d5ba02af92fb8dad0b5b8467cd6115798099bcd47cefc2644b05
338	1	41	\\x2e86e4840098e94f4cbe6ed4c2e3bb650a95ff8c5781d69a99618f5b86d499d00f1bd0951a2bde97f0224f73779e614939369a05a65eb18ee2eeed7572c61c09
339	1	124	\\x975bafba17aea33c9ba0667adb22832a5fdee8652f2385a8f0afec68931fa38515c7b9480f65742dd74dcdcfafcbe9cf7b5494ad979ed0b955ad0f789f39c106
340	1	200	\\x80f6db976dc92e7bd96322ff1017afb2f7b8061453a251733f8fae0ee228601f5c510421d5fbf9345147181436280c29477f3910dc8eddc5e64e56e0be9cf902
341	1	130	\\x1367c845a8c562a9244021a2d05937a128943417bb6b3ed59499537d669d341089ff4eba492da1e1f329ce2a3b70e2193690e4e97eb65fbc04307471b0b23f05
342	1	111	\\x9a737c5f4d33df4cd932681c09b3112dcdfbd06e18f4cfb63180cccf614cd32e1cb375b573662f023811f6d9048bca97787fe90b79dd2913255dbb56eb73050e
343	1	337	\\xbfed46b037a0e4a8d5ed1e3f57b0ee5236d1ce023e973052f2f90c3ece65c02c30b91cc58d9e17d4e2526c6b9f8a6d9ff1009b31a9258b6b890d6b372cdf3707
344	1	202	\\x635555cc44e4a831a8ad17842931ae073bef3e94ac32cdb92f18082948fd41834c91a0ebaa24994729d47b4d0cc735de89048f55ce15de38248412da68470608
345	1	350	\\x82b36ba89ca9c64d161ae92c42febec3acd497fc1e8ba5fd1f6b0116becd013f48694fc540b98f12cb946410d7a541441263df68f6567b46f10c38b545bf8c05
346	1	188	\\xec616477e3b4c93beeb043fd8a79c0f2f39ec552b5b27f5d3d6c581d83a3b1146a71621d2aa6995394d9a87a9517956bacee899568e006354760169bb331e101
347	1	392	\\x41b3470f7879455e28a6dc5025c265f6a48dabbf892bae9908e378ad58006568544e44da0d2535391b28abb5dd9b5d94858596e663d1193693750ed4e4a0b809
348	1	328	\\xbbb0000d5eb33de712fcc9c1eab92e266ea16aeff9d2641abe7f3b4bf90fcd420ee9662f6a6f5ac232563af9ba02f91482a92015601cbeda5f760ff678df7205
349	1	286	\\x4c2097852aeeddf5c602bb86b8e7443dd60012144cecbc1313ff595ee24b47206c499fa6f57dec799ed0a7945eba028e3b9944bc5f1859906836ba815d86f800
350	1	161	\\xfa721a9750257ba2c76968bfad5d02c38450280a05e15567609b0114edb3f964eca5cd48d6a5af2d6e3df279da3cb8e59fee179e88c66398b6096b804cfeb204
351	1	414	\\x4f647dbadece1f53b90fc934932005b1ac3d88829276d679db9128f0d7cd31054e4b85ee826e537d4b481d7cc64ef726a0af035a82a73d2171589476c8b19a00
352	1	257	\\xb96d1594173f88919758da8bf484f28db5290043c103f5adf0a1f634e8b6787143e5072ceccd5568d051f41c409fffee63bec554002a196108c957659e17b90b
353	1	339	\\x5729c51f281a51317b6dac061de48b103824e84b79fd526412f9f7525e059eabd68eb9ad9b31ac67de6488d2ab9abe2cd2e7619b0d733654c27376d95bcf2508
354	1	341	\\x5e5ad84a941338ab36fffcf895598d75cf4261769f2107c32cb0bd4ef53b7fefafe3818f998591698025847397d6b27127b31bcda9fb9a11aecf91a21c22fc0e
355	1	190	\\x79ab22177867489c589e7d6c70ada42256b546b4f78e83fc701725ebb6b36aee835653cb4745131dcbf34c38e96dc999bc89456a8ae896fa3b81e823361b2903
356	1	115	\\x9c4b2aea0b96432597fa93fa67fd4dc75ff0548c2f0010115e5869d075d2f86cee528656154741dcde27a5502e7851c9e27672f9797b065f029c27b074230d08
357	1	151	\\xe0077ed0879d2e9c0cf8faaf97159270a7124509874193c6705f5e8939a822b9b541389552a820fbd030d14ef490db40a98d9107bff0980f562ad107e8f2a001
358	1	345	\\x22979e96f6374d583698bef02200eadd32755cf9096f9dd757462362e1767b48f82d3fb7d3038d701d4b5e4de7c2ac07c81e6c15de850b2b6354bd731be1e908
359	1	207	\\x15c238e46f5dacfc8c5365c7668b3b901cfb6248a5e2725636c6632a941633847316e79d4a428bbb4354c57d29400882c6efd0cbed171298283eeab74237b801
360	1	197	\\x2ea5b787f0cdba9bd516e192517ee48592850e4159a628b389cd6432f3a8dfba7d091f11837a3b65198bf44140c7785f8a0ead594a7d0dd667f5adc1b9dec800
361	1	271	\\xcbd044509b9a3d28cf0ac7fbe876456542beca4cddd7277dbd1066dbd83261d4d504f268bee344449e72cadded4f518d8fcc3e9dd3f7a0503d9717d596760f08
362	1	53	\\xfd77c9835572b08b82b2821554d1c69087197ef5d676c42289d41661039a7d6851fde75ff26f183f38bf6034ce9ecf43e35280ec07dba574769c35dcbad51a0a
363	1	368	\\x86805d2f3f58be02bd19689c1151c5a4f43c8df91102e26dd8eca560d1e629c4ec2f0a45c5e93da36c9723eb56f59ec1ac2b56d0d07c067d72c7e30001713a0e
364	1	348	\\x984d11ac9bc1081f70acaf24d9c3eccc60d01f6b89be375164c863386db3070cf7166b0c7bc468980722b0868933e3e5cc0c36f01b3bb39039cb31aa7230240d
365	1	59	\\xb2d4ae54d61a994cbc78d3dc12aed5e95c03959d61a9069530f6d69bdc60400fe57a8789e8b199d71bfb54d8521234448677675e0d68ed16b462fc1894409208
366	1	193	\\xeed17f1488314c9d002df3b4fb5341148054f050cae48fb2a7cf330b1c378bed5a286883f657fc10c4107042e43d9b03c368e396ab0684c8dcca8e8eca39a10f
367	1	273	\\xe4c410371f6809d507700c691e6beac0a54811a8c4fd4698838b38c9194c70dc6b24280ea956ffc81a8d190dfcbb58e88cd9f1f7102eaec1ca53e10a9b9a5401
368	1	62	\\xdfcf0771a0302d5af173ed15f40aecd128fe7995b925b82e5550d14b10668ccdf6647f6c77ab8b03fd4e71c67c9f5bb8e11bcdb9a1044a2557cc5208eab21804
369	1	231	\\x78c4cb758b79d40c97021b5a35085484fa429d2a96951c02095b16638bbe3721a351ac101dd3024a750905f0857e01cc5ef84b27cb95dd4cb61b63e60db5c70a
370	1	127	\\x1c3d8c146be897fd991d9e22d1a3656686511a2f8594026be30bac5ce84d3e4ff7ea36acd8b36caa96bd34e04a3ad4552ca9028bbe98d2ca73c79906b285b606
371	1	2	\\x24f4e23684235ae8c8223d59b67341aa7ad8b6d15f10f71d7dcf410f45fb45fe7d6d3a5455d29b349778a1281de762e14859815ab1e2009c51a93c3862f47a0f
372	1	424	\\x5d589fa87868f87e7662c00b9fddef1ff9e34e3bd19b241f8c7bc7f34091b0d854f7a4116dda26eaf67221a018c8bab5a672d44247c9c18741fa47ac36a22f0b
373	1	398	\\x8a9cda9df3f5ea3465db5bc08a2616ed5eb1f7db43288310b0ced703e428bda72f45e4e0e3213957b32248b4da860812af186db139f4adc39b406a5d82e14d0e
374	1	32	\\xc4268d2ff062f1d853e9a9ad651b1ebe78a5807785a0a050d8cffdf453ad1fce573eed88b2817371322569e83df79682bbd01392cabf12d2e4c28694af139a0f
375	1	24	\\x397381989761071071bfa3d5ba0fc1b798df7471037e7febf5e0da52964026b61f4a7119bfc573df3ca0411acc1831644d8d466e62ab985d23a660588ca9ca0e
376	1	343	\\x1aeb8c02fc8def062c841b692a904376e8bf1386733680d88df12da2880c985d53501dfdc49a276cdb4c4462a154bfdaff31451e77d2c48f479e6421b7cb6f0b
377	1	384	\\x233db73fddf0e3b9a5aac2ca4ee7f3703a539c8f4da9b66a6d9319b41cc65e05ba8cf9f4d2c81e726f43d1055b8f9e04701421b5f754bcb7957b29d404b92803
378	1	156	\\x5ba4af856a3f2d40fa44e69f0d58f333cb3597ecb4407ffe31bfe1183d73baf4276e8cc9b41742da64ab4be59e9813e815a008ed6448a3fd63930e03cce82900
379	1	234	\\xa7cd3e048c1731cf8292dfdeb951312ff542247a2e98bea4ca2fb90846c1f508bf1326ef58506ade4169875221a4e471d7057f0888d45b478a72acc98397570c
380	1	9	\\xf281adad5170352b847a40ec0ab644e65e05d9b068758cc27d588bd048299e0ac72aad87d21c74fb97fe8cfc1d14255ed19fd371616f851ef1e375262b5c5e02
381	1	420	\\x40691c31e49c8f4a6fd543d004668f327c87c7b69e96661b8647d8864c35aff9a1b3b41d372fdc9d740d135c92e1804abbc4f47a774266cc9ef832ef4d4e6600
382	1	217	\\x533bb5e8e2991e3a5873de0c5d6f442f8e1afd6bf1c77f6301845270cbb042e167b0184e7cbbbb50e0b687290d015b3df2464777e0f6706d77a71ae226d30904
383	1	142	\\x16b862b26d70e17f6d8d83041ba20a96d7f3d52c61655c488388cbe081a505ce59118ff89b0e73b31d80b0765c19e21450f0b932764bf1f15ae9a6d2dafa6d0f
384	1	135	\\x8a2cb93c77e18a30fc2faa65dfcb744da9acd24dc3d32b7e8e384474e09d54a74b5e65dc4094747c72cc416f66131044d38a4e98bb7dc98a1bf4d9f39e229204
385	1	260	\\x6a55c0b771dd68eedcc50227d04d6fce59990450c2e13ba267179b3b80e992a65a042dc7a1e663d25da901d15d1e34e03e5e481ad0bdc2d4a262460699790502
386	1	258	\\x7232c903214d50d44a365046ddd495f8efce8dfaecc4f285658ad0ed53d31795afd77b3f85c6b2214bbc4c4d613dc9f42afb503c4bb57186670451a2556fec0b
387	1	279	\\xaa6f632122052566f37c8c7510ed40974e07bfa177bf1ad077329d687a5d35bc9463186e730130cde2c8ea0580809eb9721519852ee481ffa2f713e8b248c908
388	1	49	\\x3e7f85cb8e59437ccb12b499a5fb1754531362fbaa89b1e6841917ddf9ba94ab464c503642bf019a3919bd6cb2a34ae2ec3c8af1a7a841bd4591c37fc385130a
389	1	275	\\x85270dae31a24c1bfc39ac1a7d53e56899ef6ccb1704efeb0070aaaf443e521b2d8a28f01ea41c02e9b2b698f1b47d3ddfbe2f4100b9d36e5fb8b1af1e7b460b
390	1	172	\\x4133fd53c6906e5c43a6ac11aca28149720862364188aef116a999959cdc076dbce50d2b751ea9eaede2f87e2a7cb07487b3a372df967e2c62dbabcc22df4303
391	1	415	\\x0740b94f12acaa9279a0dc50bc3e7aa176a0117f830e1cedff5fbb286f888deafa2ca4ba9ec50c1e686a2d58ba7783b90919a92f73a37399fc58181f5d51780c
392	1	218	\\x2c2444b7b32592333a5e2574075bab5d56d35b8beaf80ba91d2de570f499416fec7b91d654f5aafa2b3442d5484eb9369aa4229ff7d4a9c2ec8905e605471a0a
393	1	372	\\x0787800ce6bdd0e4afbdc9d614b30012bc3c656f9484e06def91bccb4e7268da2af4ea746d283a5d7aa0619bb5aabe99b3544c50788210d70d1bd941ac96990c
394	1	322	\\x8a6aca86552786d1f171c75a5048d8d4b26db59569c2877ac6dcf2169b1c57335c8af894fa9b8bdd3d1cd30ec43b13b271b22b2d74a6af2a9c71445b72f3e00d
395	1	215	\\x0b62caa995c55086d273fd701cfed60593cfb771eebd69f6addea1273b7973616f7df8e3dabecca42679d4b31f4dd36812f044acfbb386cc28a463075f81ea07
396	1	289	\\x7846f1c7a363129f921837230f5caa4b42c925bf1835f3683f82b8dbb7b0a52884acff53e9f787d3afd304de8aa4b5222f19f87631938889ca3bfb95627fa606
397	1	380	\\x169767c0d05cf5b0a7f1918199f4757dc9153a7a7cc1775e9066a96d33943ab6fe6cb7872739df6ba271e6734a44488af810055e33d4ea3760d3d499bd171505
398	1	44	\\xd3c39bdc39dca5eb0c30a218eed5de36955cf16f6dc96c08e42ddc183ffb7574829f0b8893c695cfdbca9cc6727454619742f8f592dad654966eeb7d85869907
399	1	253	\\x88f59cca56063adcea1085975bc7358968b4f8f4c92a966b3a0201c8cdcd791cca1261dbd65946fdb7b3b25ff6d8c7c3a60eca0a1683df1a43ee7c72e8a6580d
400	1	63	\\x92403e0ab9b08d748c5e6fa96360d65072eca751647e58b3069572167084e9f8a8aad25b61588844d09147c49a98816a2b0853f00e3fc2f8b243b3ab665ac405
401	1	196	\\x3681f7a6fb289f9dfdd73be533614e8c421f998c89e02af8304114cdcdcbbc77212a630d7418c429cd6ca55163c17fdd764ee61d06c4d569e56daef3f9d93f04
402	1	166	\\xfb99c41716c65abeaaff8f81fab372d4fd05e6a8d2f6b2512a8376caa20f43b3316d26344381e71c0359bd54c7fce794ad362ef79f5e8a44193da21d485f0209
403	1	10	\\x3f1e0e64bfbb93fac4cf8c067d2e236ce3093647c9cf2a960dba43ff1128ef91014e87cd1c8e4ebe650c737fd1bc7de2131b504e1a122f525156d6b44cd98c09
404	1	280	\\x51b411820c8665d1b23f2b546f5c1a7165ea05b4d9aeabc16afd811d15757612f6d6f57cf342c935f6d3cb555e070995f2ad92d52176acc88e0db4681bbae901
405	1	316	\\xac56a8971af310e1854b607252ee77f60816d009d45f4aac14bf75cb4c0f9c59a535c98aff7eaaf2372e31287bea34eb40e1fd0379069d77cc65f732550ee70d
406	1	105	\\x2bd17ca2b47df196706800576b3635e5a8fb85430240ac1c0bfff7caf4b49e9d5c22ecb0238f56910d1638c9b987dd17c9034716e2b2e7cdd77a6facea819f0b
407	1	370	\\x88b27a7f2270c98a76d8b4b98757f10afc4f37724f4aebe1471fd77e15b78e54ccce8c32b3ed89ab26e667439d7e0ab8ded91402ffd5c8fb6481bad57abfe602
408	1	354	\\x3cb7596c34d20801c8d538048c3ebc54b64386cce78310220df5e174ec895956d717c2a62f29eb10894bc6f17871c12d4f18faa75b4575b71c8addb66b0ee00a
409	1	21	\\x099dcce26a284c4de73a1a6f30b42641bbc1b47045fcd4f7f7768565c7c091498532d6ab8128286547444453ea12595bc4d681fc53509852b96e89216f772105
410	1	100	\\xbd8b9d32015d18a0762ec0152faff1b3049a084fbfa60271e121995e1686c1ff18704c7c2d446904dc7f3a5a56edf22f9216bdacb178a21e60845f9b3ab3f806
411	1	410	\\x9b8296248c02ce33c677fe17816b8570ff4e0e55d90a68b1792da9f83e88e1500851557e4665415b967fb13bb93249a0072011e959b5134cad6ade3aac29b909
412	1	412	\\x9e48973ab3f1b63c208bf16b9ab76db068ac0fdfa6aa25530dfcfb431e58512cdec869077dddd410718def831d494f25aeb16dad22743b82ff6c9adacbf10907
413	1	326	\\x9bf1188b895202bbb382a01f498c1c8db7c22086e9c0c8239d9ccd21c1c0098e3518edea0f0e84021d036592ad1ce6f46b1c3b7b2cb484c3a45f8e4d1911740e
414	1	51	\\x1e27547feb0146436a32408828f4ef4eb45bce5c29c6597b91ae92c7bfbb515479e83632114a38f8c61016cd4562a9ab40794d13eb8fa7ccdad743c768efb205
415	1	311	\\x661d21f763234e060234915bad64d7b391952a4f11618cce2cc4c38c64025580e1d070e2462ae3b77f77cf51d68c47e02a31d4e040a1c87afaf061692b1a0d08
416	1	52	\\x5683ad18baa7b6b38ddfd1136082127b8649f4a8280f72641214e167b57b27a28e3a1b953e4e3d0acb6a9efe9141c0ef228cb82224168d84ca58c65f4f4c9d0c
417	1	95	\\x4f96d4fc1a836c09552ec81cb5d0978da4b39a8da3f9fcddc75ea672e93b7cf97a93d74206ee3d3b834126e5b9f9ea11d817632d6363f497549e21a4a49bbe07
418	1	187	\\x0bf97555bfebcb06707202a714f9fbc68e5d5d344807fe7de8c7467ba977323f6868581eee60a4885a7a6c44c5b5c6ce7d0faa2764a50e79f86de5b9b42e080c
419	1	267	\\xc2adb595844a2ec175c2bd2e36b1ff450b701e85a140c5d967e277a2f23195d0782f559cdaab00bc4eb5ad8034001f181ca8b0a5d53d2aac58d3004c6d2c8e04
420	1	82	\\xd32917ed3363180cc512cb2dcfc6aa9ee23433b5969fdb821db8a233b1bf932f7d79d0ad7c16a6ff4ed1b16a386d54950a313fa2b67eb640396cbef241ad2905
421	1	406	\\x5051435a5535070fc166fb065f4300a5842e6845a14a0fbaba1e98781bdad8094a471dae18ab61d0ef24e8105c6a12eaeca82bd47b8a91ebe79aa23e9fb7c50b
422	1	371	\\xcef97e1adec9bcb653e59c543253a46a90394e5222687dcc3aa77c4705fe70b0a3a0b2f2c5d1cdc99a55a003dada97d4bed8eac500f55630d7a6b67853fc580c
423	1	264	\\x82e19a767e3786c65932a4c7fec133b5b0128a788c8dfbbae7c3e3c038d44f8c603f1a201d5401bb7afaba0786ca5bedea6a4c44723394d8ee4cba63b1256a0b
424	1	36	\\x2c86337877e3f89e6028ad886d2175afb779861e770fb11fd4849a6b3e4b7a96de5d000b55d7f9779e380fa70e32adc1d84ab1f4f0421ba2f1f636d8e183970d
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
\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	1655066071000000	1662323671000000	1664742871000000	\\x21f6ed33827b0d34297757aa43b6372e5662863b18c6cc41021c5b4bf463b640	\\x193ba040f32eed4366be0f75a69da2a66fb4d13a0b83b6f4c121b33fc61698a90b5f0e3a3a97e0f21cc614a7f06a2c613a7990c3cb69dd7823fc70034154450d
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	http://localhost:8081/
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
1	\\x371b97745f682d0348225f5efdd3c92a2349018859a8d1e01477741fb9c65faa	TESTKUDOS Auditor	http://localhost:8083/	t	1655066077000000
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
1	pbkdf2_sha256$260000$pyYFrLEOfZZ9L2FGTPeCYh$UfBUWj/f95JXPS7qFw8kbyeVoLK6xwSyhMFvbgghUHI=	\N	f	Bank				f	t	2022-06-12 22:34:32.119468+02
3	pbkdf2_sha256$260000$AQWLM0tsMoAejc6Z2Joa8U$Fu9/OjwyIOcIIgdlXlciQwvmZl7zTLxzOa5w2HKXyEc=	\N	f	blog				f	t	2022-06-12 22:34:32.311271+02
4	pbkdf2_sha256$260000$hjKryqvYNHbyDOq5xCuwR1$YclSWbrr5NZsGf9OLHLrc3wESGkT4UplGpPTdUXv6ec=	\N	f	Tor				f	t	2022-06-12 22:34:32.404724+02
5	pbkdf2_sha256$260000$2e6wl6zcjuMQigeLLpMzRJ$+Xjg6WqzGdwnqGHdRVAnuwXo7Fwvf66zyQtl+O2CzMM=	\N	f	GNUnet				f	t	2022-06-12 22:34:32.502006+02
6	pbkdf2_sha256$260000$22nbZgn8tgxiTVNfD2YT8q$z4cpbuuSDuFmsJH2QZffgWbWicv3L/j+XsbG9rG1RdE=	\N	f	Taler				f	t	2022-06-12 22:34:32.59433+02
7	pbkdf2_sha256$260000$Np63IRFMVZpGXa4apBwtic$Ed5GXzfa54awmwdrdMNHoMbutb+BJ1H2REFLfbyafoA=	\N	f	FSF				f	t	2022-06-12 22:34:32.690478+02
8	pbkdf2_sha256$260000$FlrQkY5itBJKqOoHaApzg8$0MYK++Qfzf4MC+2RToXrdyGDsfRZt98taepttNvzDHo=	\N	f	Tutorial				f	t	2022-06-12 22:34:32.784277+02
9	pbkdf2_sha256$260000$cYowJYUmKeGZZ3SYfhjn2C$icRHp/SsQ7OYMGU0n7ldNIBn+o/2v5GA+aG01aGNyes=	\N	f	Survey				f	t	2022-06-12 22:34:32.881838+02
10	pbkdf2_sha256$260000$eXSXytZYkcuBmH6eF7QM3B$Ujaeww6o+ut3YWR20lWJc6rv7zNxr3OB0pppLUSpeQY=	\N	f	42				f	t	2022-06-12 22:34:33.340519+02
11	pbkdf2_sha256$260000$i7df9fLQAzC95ixgCTz9Yk$+9Noz8FX6PeYJ5K3+U8ioeFuU+T1Mnd4vBgvyC/dyzg=	\N	f	43				f	t	2022-06-12 22:34:33.804591+02
2	pbkdf2_sha256$260000$SISyzUiOvXxGrPZDGus2hG$U9qJ6Z4d53jVjFEptwUgBIAC4xHZscvMkyEa/jhWZI8=	\N	f	Exchange				f	t	2022-06-12 22:34:32.215725+02
12	pbkdf2_sha256$260000$EGpyh7ap7EVuRgmVCOYdyJ$Nmc1KbMnFhTBAP7i4v0Voab8xqZDEOetwuEHz6xJ2sI=	\N	f	testuser-ua7dydxm				f	t	2022-06-12 22:34:40.438474+02
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
1	264	\\x32ccc9aabaed97c83986fc9e7e2279a2eabddf1f35c01080e203116f539e4836a05c4f3b7571ec3adeb725a9a237679667ecae70e487c9d114e5ff4dbafe5a02
2	410	\\x185034b8e6f29528093751da4c5745ebaf98cf44be93a374930e276ef39da8047a7bccc4fea42e486a129b01cc0849d890f835136c80a36c628fbbc19937170b
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x04480dde79f8cf14577cb1b6883fc65f481b5df024f336272d3bb82285a37265840d997ba423672ee997fc6a657e191d2576470d89e1a47540a3c742f46408ae	1	0	\\x000000010000000000800003e0f9d662285b4b0d6dbc0b83acf4c20c96090b2b762bd881bd5779b73994ccca8d2cc7a298aa428b9d6f6f689e52d694f4a8e5e94ae700ac0d6ac446c9dd9783570f6741eb1159ea8c6f27b8042580fb10399b3f94803eac46c0043311297a678031f1162def521e3c8e318b80839971f5e85a83c1a6a902364d0e4d2445ee1b010001	\\x92ddc4c147ed39618c4fb47edd5d705c1b3f88429d5b9a46e0699b26afa257dbe19284af326bb8fd875abab789403149ae77e0e2333db1a1637d6c3e97420606	1681059571000000	1681664371000000	1744736371000000	1839344371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
2	\\x06f4a625b2d6fef169206fa680be2df377b1cf7a35451066eae6276af0abe54ecc103504c5dd28a413a67d56dc2396f345f4b415d56172a20a78fd971d1faa04	1	0	\\x000000010000000000800003c1204d75e0b5f299a866d082b7a14f3c7b873bab45b855b28dd7e60a03006e2b4b04050f76a7fd47f959387ff832020fc8aa1ac45507bfb08d5dcadfb26e91c26ce6be6c113cff9c6b8d35b37c77d39f4e0b48802509c95477743cfc57aa9a79790831292ec7993bbe0d992815577701381585b911635148e1e48ede31c5c093010001	\\x7f58c8a4dc9007577ba1aa4493e2f380d2b71522a2ebccd611733b9cf519c6ba444921cbf894fa66da88cef8a20897316e389f1c15852d0c16f8ee07efd3320b	1658693071000000	1659297871000000	1722369871000000	1816977871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
3	\\x0adcddfcbc6d9a40e898ca14109196f7bb2f9ec0079e9dbf9778262bc377f231b4212c4fcbb5cbe4ecec1b1a7f425d438b0721a4940b3a4d915f5377084eacce	1	0	\\x000000010000000000800003a82e7670a667d7e0e1e794bb46bbfbc4943a3fe8f427c70cc589b27592f6acffa285772ebda05e7f5e95b797ee10d0db00e62d7318b1b5fb624e0049d6ee716fd12df0993647d2784a67603afe917324abf64a840aeb845679acff5003675dc40cf75f776ad7677c4968fa02c53a859e9f37fb6ff4dcff718a548982cdba96c5010001	\\x8767d27e7e2b0ae79bbd551361936a0f725337a454addfd4bf812fc6754b7ead28ddb88d665b8e9cea554c88f425dafb96e28eb84e7fb7c84d44114f98bf3703	1667760571000000	1668365371000000	1731437371000000	1826045371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
4	\\x0bec49f97676ee81a6a0256494d39d50287bf98f13684273589b7ef06137c61949c0ebfc79ae663eea2e4d46133434fde4725e60df0e637a1822f779efb5e7b0	1	0	\\x000000010000000000800003c6b699b6a44a15ea3bb44edbedbf443e41eeeec043a2165dcbe75ab0499d00fbaef3834c74f28caf283b4cef767cf9652e29f551610170302fc9703f0acab1da03dd468eb7c454b1c5fbaf8993ce35c8282752f16505d3403c8fc9c5e72c5a4dbfa2c24213a515ac127199311df4d8329c792512bf1f05ef0704870c57b7a9b3010001	\\x972bf0e16b6f271d7c62d4faf872cb60d255f58b71895795b1fc93ff519a199b0f708ff7b6b466c6f9ab6e8e5b8dd9301f31c959e3236dbd10257afcca21e40a	1663529071000000	1664133871000000	1727205871000000	1821813871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0dd44246572f697187884fc58b483fd9b72fb4baa3991140bee67d5d21f6d5469936b5bb247ae630eec7f72c5fb80c9646d08234d75d6beaeb5c01747a754491	1	0	\\x000000010000000000800003c134d9585cfac1aff22438326a1036ecbd595a7d2184e347b59f16e8eb4c18d22ea4dc6341aed47a2fbab4184deb5931916ede6564d6b166b2d0f60a97d83a469044f0d15b04556d5ea1a900378b3acd64de6d4d9961820353831fc62d30601ae8ad7aba6c8679f684a8dc6c62091d954266ec640d2592a9d775e6acd9107f17010001	\\x150c0490296afd4f306f78ad56a43459b0431919b1cb7daa2d9deb5295adaec69fda9d59cb43a8ab5418deb398b45329f07a7a5560d8342849738c5130304b03	1676828071000000	1677432871000000	1740504871000000	1835112871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0f780e6fac4ac75164c77395db2b4763a7834a4445bdcc814dd08aee48faacd1ae7a170664736eb57a84a24b2ba273334c90fab4cc40f4847603bc18d4ab7f16	1	0	\\x000000010000000000800003bb569816a21b0ced4ed4d3beee1fef489974ebdc82576e9988c3bd006eb221fc0744bcdd2957467ee3a6e8497dddd41997a60f8e3547029908812760fec8b67a2c61076fc43e95010b901b90ab661fbd96cf2ef610fca4b6e69c3db85049ec47483edcf860232d0df4fef511f31d417d11f2157dc4a6e3de0f8f71b46977e4c7010001	\\xfff71466d5ac4fdfdfeced9941f699e30903a45ffabc00cae8414d116081352a570effdf162b3e2d0e9f43f7c516ff3a46c82f07808d09e39d8c27746402bc08	1684686571000000	1685291371000000	1748363371000000	1842971371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x16a0213c93340c66e81d518867eed48370f5cc39740b69f4a4226f4dbfd52badf541038ea7ffc6f2320ca9a52e84c1923d7de332a9762108ad34922669df0839	1	0	\\x000000010000000000800003b22adb85f84da4217a43f184ce21a9fbfea5ac2aa7f53380fa796dcd0dd58df02fc7ace9870f17453688a3047afda65e0eda0aa72245e5733cddfbdf929a1a140657bdbb2e99c45466c7065406d7d2c1bca0aff28f309783d77d26463a737c502727a192f3792c718c6f243a4fba0e7bb7a5fbbc9b9a4f15f389c0881871dc6f010001	\\x999d042164a0cd1f528bf89ee3e2e376078902cb72f57fe31a75ab8f005a9e8a1d7fc0e8061aff3ea3f84315804e3a5d95f5eb6ed059554b539aa5df75d4cc0d	1667760571000000	1668365371000000	1731437371000000	1826045371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
8	\\x1760a48d41e181ce107b61727ff2f0eb35737a5fad2938aaf35f94e7d001b44bc93341837634ddd1b38b1c4c72c61131719bb632ad2081df4f994caf1ec77e7c	1	0	\\x000000010000000000800003be5cf7416017bc8bfa4ade5bacf411ce2b1f44d385345e8175d2b78c1e83ac5480933b9687a16351b75bee4cc1ec9b2b328e28ff1998f6d43f29e507a6f07d30d7b18bfc8f8a53a43b7d625d02c02b3175a0bc38fba86f4ed4313f172a0b166b6e77d3787e3f4f3cfff3a21095f02bc4c98d53c82c7addcede7c70fb42f361fd010001	\\x8a9342448fc6723b228ccdbf5b8ec2159c6524ee49ff9cb43b460693112bd81371961b36c48ce37af56030b69ff25ab660b44b99ad7a2f5117afdea196dad901	1664738071000000	1665342871000000	1728414871000000	1823022871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
9	\\x1adcc5d78390f37400efa274ebc1c3890afcf384f3ff7d9886e648c2473d2cfa455e73defc4f2742eaf22e2c4929e6d2c25f2dd4672c398a74f85c873b9371ec	1	0	\\x000000010000000000800003b51e7a7ad17d9a1b9b3f430f9fdfb4ca07b9522acdd9307018544150b9e71b1f2754fc67aa513a43ca595b159c34a5519dd8c93d6e391fb89cebe5097604c972d728f579a21341fbcaab5897524512d24c44985d41c8b1693f18de12fde88d34d2476550f1863f20eb20cd80ae27b135b425138bb2b257a30da84b29f41a52c1010001	\\x67624187da60a3bb8e932c8366baaa9587ed712f881a9daebf9f0521957c7c09d5d6d234eb735b3b204e32edab4b8f58d5354696faf61de0e6bfbfb6ed382e08	1658088571000000	1658693371000000	1721765371000000	1816373371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x1a64a692d636b9d4c0a49ed32097ec5177e2f8d77e23d60ccb4d36c3a1a16c95647e6d1bdf944b25ba3d5d1e5bf8e4ff6101fea23cd30c10e97b6d70c3b936e6	1	0	\\x000000010000000000800003ac29a5f803728aa5853254898dfb6bca5ab8e0216c67846c1566ec5c8748447c7598d729e7c4a276789fb3e9180cbc15942bcf3c3eb231b3215cad39c47c7fe34d23914dfd9fa5743e259ddd886dd9d6ac6c7d3b8a0d5e0594e15475b1eb6b99f3180ba6b537ea1e86cd3c1463975098aabbf24155cd6c9d662fb61de3eb773d010001	\\xd6c9c9108a760b756b65dc770140f41703b52a2ad38586aefc90ff13f692afc4335601f4ae7e4fa2e0a1738dab9ff17026b30a44ad17dd1aebc6b3911a54440c	1656275071000000	1656879871000000	1719951871000000	1814559871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x1e0046f85606639c720c37c11073f7211c62b2e4666ade7490354a70362ad10818bdb30c6a965e6c2be6dfb8de019bdfd5a4032e255078f6016fd5e98b33d6f2	1	0	\\x000000010000000000800003b90ad22f6ddda097ad0079a2c8d668a46e7d440fafeaf15cb7c6a31123d19bf759bcef22585ad4d22035f8026408e0c0a57faaaf2349fb7625e142486e1b5141bd868d6ea0da327f893498361008321b050e73cbbbe3c7967ca8aa8c1ae9f4b76d99aaa1257d727bec01e1cb89e69c6cb29604735d5e9285dc2a2ccd9e0f91e5010001	\\xae25c2dcb1b15eab71a717825816e791c7e0a81fa0cd01193570b358458480ac1527450fb6a780e5ef902eaf34ffb329ec43cde5c9d97eb01411407b990cef0e	1665342571000000	1665947371000000	1729019371000000	1823627371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
12	\\x21d8ecfdda099f20bc2c4f5a03739882a75ea1285a0334c1fdb5580d09975bafa4bf9a0d45663bc6a432584226d18272a688cf58d6180f0b32e3a2d97ecf8414	1	0	\\x000000010000000000800003b2405597831fce1cd75410b40297d8cf97e1aee0a4f04afa6ee71a8fc902bf91dce7d794a72c624d17e911103f4db2341801e10c3bc4171b2c4b4adf7b869782643e99cbc507e49b57c81253e8669b99bf12f4b7dca7529413979f6c6951c269cc853eb8dd78dc6900bf4c0ed66528a434061d557ff1549b3d80c0964ca116c5010001	\\x4f5aa4839420872cfa8649a884dd215d84be523772f7e9635351aa85fa803619aa2fd0a20c42f8d8ff1700f98118694cc66643ceeb5dccf545e1789d28c3d908	1675619071000000	1676223871000000	1739295871000000	1833903871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x2460022e2d37ba443700598b9dadc51074010ba01e89b67c54ed1c0b15a3eca2ba396cb6c220fbff3c21ceaa0529b53b00e55418746efb72c058f68b9042f91b	1	0	\\x000000010000000000800003b4f03fcee4551ea052b7d33f8bcc203cbbc4e0d0cb505f5b17f05f87846554e2127f012daa84ee823a25cda1c2386a70376872a5b9913138686762b4433f1b5585f8cb004aecf3f3f7fbf433f617a6f05eb3e14ab671d77296d0778b1a2a3f9e5666e70bcc300d7c0990cf406487a67a1a6cebef7055a90a9a18b5d12f3dc4eb010001	\\xe2ade88d7c047bca744c17a7be67eb93589f3f00abb9664a2929122ac5975dfad456c45f844872702898dc345d25aea069e162cb6250948946247cc8d3b59802	1670783071000000	1671387871000000	1734459871000000	1829067871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x26d0f746d9c2f31a6a88a2a594b77392e99eeafde826d2608eda96745075a2330b3087f3d78919477f29cf13489354544c0683573004c068d13b211489e0f610	1	0	\\x000000010000000000800003ec53b2e587c7874e1becee9c0067d4068da0be7589133d34113cf13c5679b63ed5d9e6f4f7ff8d4684bb03c03a6ed187b4f7175819ba5f21b264426aa322f0ff380f3fa3b6b0afdea3b1ca50cf0b310504d1ad276436a00f2ce67f71b8c0e88f0cfd40eacd1b929640ddc272e3491483245721da209dc548bb51fa5bb2bc6b55010001	\\x27b6cfaa7b77b782847c92cd7f3c750747b582f1a713a3f37d175f8a76938a428cdc0b769460fab5b98417d4fea0bf384fa7dee08370c1b54a0e3059ba7c9008	1682268571000000	1682873371000000	1745945371000000	1840553371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x26c0a29e466860d425d13122b613462cbbb46323385d12b297b0e85fa4d4a72739f74c7222ff368bfe053e6077af6770594b81c6c919fa7494117934ddf90db4	1	0	\\x000000010000000000800003ea0c5b440697a3f3722c45918fdf83e68d284983402d1fe98d3a77e395819e4dec5c5c7919acc69ac3c7b4aedec1c3ad72419320c99db38e1fc51a303ab509ed035c5bb12b30520c7cac3a4eb4bbc69fd3a40017ae012ec9816f0ab03a3b43a84110a6562777adb4e9136fb0b682f8cc0975387fbd0b4ced9861bb175ecf27a5010001	\\x49ce8c57ea35e6e3a65682eb3ea42e55464b25c5aba0e54164d5296b4739473f9382feccbc60a138bc5b61d52d458c2d20c3327a814f269f50903aadf7790f09	1661715571000000	1662320371000000	1725392371000000	1820000371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
16	\\x2814992e32f0ea67ec4662e39b43459b56e05922d56ac6c88d09e8962f9198d9a34fd6ee28581f56f66f2388be30da7418de7a268e8ea6aace8bbff5ab61e30d	1	0	\\x000000010000000000800003a90ff8b36619f62f292c0eccff83d54506eb1e33dd0dd785337418159eb0c99ff302f8595d3f6d4009aea24b5ae84d0d5edd2e7447a3e7aaf5f008f5959db68cde100e9ea28fc573e8668e190b550934cabd2f2d96ae1fcd0257dc964898814e27ffa641b4090ada513a23557ccc1967f44a683248a09909397df94e61c784cd010001	\\x31adac5fdcaef2211eb0f91089993fc9a8902ff41afc140a8069862500ca79fbc055dddef9260363bd7fecce3608ee5c829e7bde3e2ccb35883ea58865e7d70b	1683477571000000	1684082371000000	1747154371000000	1841762371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
17	\\x2908f4f5d7f113669e138c3becd5d040e3eef0d18a913cbda36194e5690de6176de402246b5352cd19b266318ebc541749df46fed3b7c42a0415c3b7d650e98d	1	0	\\x0000000100000000008000039d5dc8d0834ec0c67c99d6b4900dad86f574cc6c4325401610a99409bd3e653afbf997e3b2e61d6541a87f5787aaedc4d6061230ec97755254867f533a446029da2c581492d3c6c99a7e85edcf74f225ce0252a2e6a54e0a57c23cf6a6f1d20a4162daeaf36794bd53fbbe073c8ff56e7ac79044d32a82011780b7a72f63fa95010001	\\xdb410f648f8ddd2e74124b96828fa342336d4efd923383f03ad09dc4061882b647ead416dbecf269a47f5abd2a30d65c29635da484896800975a75a51e6a0e0b	1685895571000000	1686500371000000	1749572371000000	1844180371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
18	\\x296c46f6e09d3a25ff9a205319bcfba679bcaf4ae11e1401abf6f0391da3272dff04195beff62149c0ad93974681f491a17973643b57bc528c378acd713b75ae	1	0	\\x000000010000000000800003d6afb0c926cfca92c038df615f032e9dd10740c96e51207a3c2d6aa3c9b42941fc35bc79d9eabf09aeda01a7931f1ef3e90b13a6194eed222e80a00498a48c5237ce88b223addd8b72bcbd102677d5a673faee87f582f5a151222fa600c0747fe1db6ad6c78af8c11eeb442d2187a48e467a404eb4fd246259884f0b2f344b7d010001	\\xf7a40de3536680272d633217ca4fea759039b2a4e440212c40b6360e7d583b39b2a948633a76848ad85aabee2039128f3cbad1f3e8a19a1f1daa98b35b3fc100	1668969571000000	1669574371000000	1732646371000000	1827254371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x2bf81421a3fb0e43600ba0242bed4bd9c07d9c62b19a14b281ac56da861eb0d15c252185fe2c93c4872ad9577bb261dabbce8cefe4cce6a69f151d77d9ca6f0f	1	0	\\x000000010000000000800003b155236a35ec2360d097930d073e0b4710cc6e2c7db81e77b6a9eaeeef98e0f4754fa7409a69d0465dd7ea97480511bf96e1f3ca01457f765d825ea8ab145f4a617ba0e23946d66d0a4faaf3fa155577471b4cafa20a0e3a6030c92452545e8d47818f9fd2b80418fb9c23f6f31f011a548e1f58ba7f9fdf03421c1741adac17010001	\\x136821fce65af0dbe56d749ee8b6408607ea7195bc04e36bf1afa1b3be11ee60a848e83b99326036c5659ab82c64ed0937c4560e7368cc5eaf629559f7128908	1663529071000000	1664133871000000	1727205871000000	1821813871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x2e38d2b0ac1a24c8b164fbc99900958d4c086be583ffe96180c0a7f41926911392c5fd5ec32544158955e8bdba2edf475da43e97eaf6694be725ae0d72a47975	1	0	\\x000000010000000000800003c02e22ee6285d590ba6fa5c84d8a9e63372c9307c6c0d749b2fff7141436d7d4a1b574cc29cea1589fd77e06cb50ed8954061253140457405d9beefefb4f100476eb37f3972fbee22e2474b2a7ba1a61405537cfc4eeac95c9c5fe8022c60c2734455aca5f93108a97d361f61bce2150c84af804faa1db8e7bdbbe028e815881010001	\\x481120a39d8aa288e08684ad5d5ddbcefdded3887a9f49baab02961774986438ef7cba185532d7ad7c23e148781160eb9dd305e150e47a4a72d4d63ee5306406	1667760571000000	1668365371000000	1731437371000000	1826045371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x3080106760e56ea84a0bd162a0fc9839c4a3a64dbcb759a7f7033112b9f5bd33a2c69e6e7f85008df295e173d01a6ce3abf45cc5deab67c260958657c879ef67	1	0	\\x000000010000000000800003b163f6447fe598c723c1d94af284d95d8297d4d5b6cd29631517f410e196712ff5f56893b7bc8d0371f828e7c7517759046816735185b41d0359b83769f5e3f4fe01fb67bbd053ab39ef570534fb21371ba36ef7f4ed0cf662e182593409e1ef5f9d0dc6a89f9e1c565237d12b51574937dc95e717df9826e24a4eaff21e4985010001	\\x73fbaf2b3199c4974e61e13bd1a6e9e7ec4fa2ccf691fc013f3d7f28b76f7bc3f322a3110aed350521007ef3a8510762ea54788655be3871ec51010da8bf9a05	1655670571000000	1656275371000000	1719347371000000	1813955371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
22	\\x33747034a618335085bdea182bbe25a6c466816038a725a5ecc8692ea9db05f5515689c4542c97cd1dc82eaf455854310d2ec9b777fea20fe01bad04093fd060	1	0	\\x000000010000000000800003bc98eb7cc08812ed7134b6b926ed67918ad407628295013c8d2f80458cbfa2b742c1f8d7cb952f44086bc8a320a098ef8098425d82b38b27861a156f864e20066ea5c8d0a8c5205ebbf5dde6e3d2658c57d4acc1f36cc1935c04cae2d3ff264eebb6ea735456c93d09cbd034b9d2dc2b2b28b121b31121b4d22dde5475e3e6b5010001	\\x02e480742ec20c1ef0737c0964b10e4d86ba1bbed927e7c6299bf97db6c95122870e331cc08ae15f160d38d9e0e149085f48439099052442f6d5709be5b1b50c	1676223571000000	1676828371000000	1739900371000000	1834508371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x333cb312a6859128a8db90a3e387b785581d96de765d7ca356f7c074bc6401a8c315a7bd173ef239f0e41cc110c7942c67c285c6145ce9119344f46d3ece7304	1	0	\\x0000000100000000008000039d906da9be80e4eb0d403b5d66ae8b26316ad591117ac44078e6a2dce182abed8adb18165de5837e021819b7b440646339aa6ce952e83aacf824d9df00e65ab83a2e2deb6ae78380ae1b22ea28977214bae506b6eba83d860a1bf70100684057e22a11dee7ce65e37e4a204b17e67027b5a08719974e37d0ec705484da60220b010001	\\xeb422e95be6400e4236ef9bbf97c044366668b197c9aa7721218fadb32005ee38715617063e2b76a9f19d0d66a6e56f7080fe6fd728c46107609185d100d1804	1666551571000000	1667156371000000	1730228371000000	1824836371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x38508dd032f6ee2afcbe944cec3f2dbc3033940b57eb8c3ee21dd606a1988c992de3d30de3f9ca2202b1fd42f5e9fa0ee95241cd099090bcc61a754ece462cb7	1	0	\\x000000010000000000800003ceb5b4f9d374cbe9c7c505e0f82a93518516ce0ecaf3cce2d115248dfd7b07fb1337ff0678c77276d9ee1d6a9b4959a78dd8121f11f2105783fb12b29fbcf830a694bb286f802ba1d4eab936e79786774a973f4640175a9d0eb4b32fa895185b3023520c49929593e124ab7dfb61978fd8c83f67bbba3a54e841b98c58fcd367010001	\\x2edf6f043b7249865feebfa1a6a9c971214053eb5c8ce99507c0cd55bd611fb9d7563853de409c569bca6525a95ab7ac9afcff187900534c7722d4747d701104	1658693071000000	1659297871000000	1722369871000000	1816977871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x3988583e4eaf7d4c6da5ea38cb18cac61aec574d85d9437ba7de4077c854887037619bf455757865f8c2a7a8d0baf886902955dda08da707cfa4b7a857b941ed	1	0	\\x000000010000000000800003f76c6e17657ec0c58f10265cc36db27e56b409dd23321d7fe2c6d52097432ba1af2fb67876501bcc90410970bc5064fc0fd3b8f539b0b491be4f94c8e4776a43aad32ea29b10802f8163bcdf281c70e73e59e5272143fd9d217153d7cd634bfdb7195ef8139c4eb06e4a748db59c3ec021f2b1caed89615a32d1cefa7adad56b010001	\\xbbb69161baad8c1a2c6c177b77b1fdc177629782e13aaedd53d5c45d6a6be81d8bf64cfaea10e38ab0ccd690b3746f0c79755bf2aa919988271096f4ae97d009	1671992071000000	1672596871000000	1735668871000000	1830276871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
26	\\x3e209dd98e6e28c229eb8749cefea540716ecb3a6e7ee8c52b9b561dbe4e65d0838424eae089116af3d2d74c591f045f4ac2cbf50de4bc50b65a395566aa7da7	1	0	\\x000000010000000000800003c5a6986128740a2dbd53a107ca15b4c7d9434a1caa6bf27e0919d530e199e4bc9da5719c1223d406139ba09f9112a571658768b7f8907bc8f40916ada273a3ed208591c0a7d474f744226f31bc6f8bfbe9e7c6bf5bedbca10718d30ef329d67889a0905a1ddef2b245ffb0dc717a81368e9dd736f10c185c6b6547ca14c14c27010001	\\x3fee9557525b56354dea0fa34c2e58dc7c05ab19cb7dd6651e8c8e2f36254c3268e78c35d546933eb975c3028a0deee1c8dc21a4698a5bba9f3e845babba8e03	1665342571000000	1665947371000000	1729019371000000	1823627371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x3e28ed46747ef6343a643f70d05eb28053247a742deb33136e40f9e6043288eb9b4f982072cae0523d1ae34120ef5fb7fe57bc17f65a277a6049890e2eace972	1	0	\\x000000010000000000800003a81fa790faf0cdfc832123eb9053864be555cb90adf1c756e7f999702390478c42743850a133ef98259895f71bb9d8b155163eaf9b6d9880f9cecca1a9aed4038df41d5bbdcca9eb4584adb93ff1f43b9c8a1aebd903a371ed71337fcc59ce071d88964ca62bd18d6652c3615fd4190805d9eb43a94ae5a46a08cccb9047d97d010001	\\x568572b0a105b308ad8debcbdb3855cfc839f082c7ea211fc08c1bad4aa95d8bc69f942bfa422b6c18fbaf9adc76f5d54a86f5ed5f1b4e53dc8ac9f26124e203	1682268571000000	1682873371000000	1745945371000000	1840553371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x428c80dd5556d39df105431f942647d2dec96aae8298562fb75d37dd0dd6c20bd24ac0a484e6e10c41b4e96ea70732a0648c9d556104d3393002da399cdace51	1	0	\\x000000010000000000800003e3d6f95eaeefe0e7be66bbb67dfde2c5277037d72e1c70866d3a1013428ad7f4d4c672030c7d7a05322a2832a0529fdf6bfd8e077a1e75f951c2b338abdf3967d3b563cedb572b26f22a34135df6ced6752c9839b9fb37f97c4b0f68225a116bb5c198cd4aa14e20630abe9f9fd1778b8d1de4fe2938c54dcc54bde1e5a61977010001	\\x1344e94df93964540897bdc1d5af66ad78cfd36ca4e96964b4fc34e5f7c58bdabc920bd3958ad1fbc4ea41795cb3d0390dbd88e4cd5f3d20b96c3df1c1c77102	1668365071000000	1668969871000000	1732041871000000	1826649871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
29	\\x46fc5c7f63e0cdab2c43c3e2e0c7e486861b10080a56b76dc58c4b27cd8c6ad86ab52a12daed37d89431824ebecc6353db7d012f99460443c834506549be5357	1	0	\\x000000010000000000800003d804f1a9a54d02523b3ea148a5eb62abccb01fbe9b9f1e93e565d6762d67f15df82943a91962edb6003dedbea15a953e9bb79f0def7680d3e70b8e211cbce5fed174e4c662b7e57f87687a0e3b9c0b9e5148c2485e47614777f95b7979fadcb860546b9c8cdf5116390276600eb4927ae3f84206f86749048a177d3933d1deb1010001	\\x280ca6a6199b4ac000c2104079478bebe7c39e2aa87653e54cafcdb5909ac4dfdad6dc719f7c0109d2d6cb28b327ae5320983f70737b91db6d8b5b06f5519c0e	1663529071000000	1664133871000000	1727205871000000	1821813871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x4814817a9059c41650fddce09793ec347711065ca41ff4f118eff88da4e1aa889b58c7f6e2cfd3728bdd1fc6ed7fd4ac5441259ab4e7226adf15a7c0c35f7e29	1	0	\\x000000010000000000800003da9e2a0c7fc1e5a9adb98882ec06b03988879bb710362d888ec55266161145173d3c7857049f4cbf4636ba7c6788860fddb75acf8dcf648c7099bd959ee09af06561f4ea3ff605446d681c1beb243bf3959b76070f873ac1fbac6195d8c894ad729c3d330bbade540da2a18b2b4d7ae5f74a2dcf0093da7cb1c261490c28eb7f010001	\\x187ead0d1c01089447da2f59a740a855e35fcde61de58c2c4833d4c2351e50eb80daea682c16a18c7d59b5b0f2ebe673d8b0130fb758015ed078df8517d11906	1664133571000000	1664738371000000	1727810371000000	1822418371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
31	\\x49e8f19c0bbbcf4e1ab4805eb51f4b74ff52c395408b797b856823ecbcb03d8b5bb12d16965a52642bf124533fc03a514a76b36e8ecab3bd814c6446485ed972	1	0	\\x000000010000000000800003c8ada9b66444e4fa5a038572cb2d81b8d797d98c9f03cb0d585a9295969b1162f61bf95f5dc3376c13ca9741688c4312a58f68af04c544d9a16ba96539608c1795e4bcb9daafa3783a557bb48970bac740f9615f8388009b3ca5616a521943e047a891005eca0b411677c95ceddc76bb142d5179bb7029d21a3f23a6dc2950f1010001	\\xd987ba7444e363829e90a07ecdba69511f4eccb294ae8501259662cd1e0119f32235baaa64a9964870273e0b36515d61316671c985b1fc3ced5bdcac2ee59300	1667760571000000	1668365371000000	1731437371000000	1826045371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
32	\\x4930fe44da87de59a14d811a99f8893481ea60357867c45a8d967eb99dadbe345007f14684a86db663e78529f120f76de1ebf7ea6454b95951acfb8e020f8663	1	0	\\x000000010000000000800003ae550e5d3cbe52eeffecc38be49550d85f12f78db3bd663a81a35f304434cc48bb3595544436d8bf2e114cbd59dfaf5bdb7b55fd38e1218cbc8673456d331d437c5f811b12c4f509d057247e7cce95d56f77302781d159f1387e3ffef29434e5413482dd88965de71d930c9770f00303ff74d3af2d0f54d6f8e321343b4523d3010001	\\x37d8631920696787e6867aa482ab6c35bdb992494c26d53bd8c9d2f9cb5a872746c4268f3c314c8f188149c3c228f9be8a4334b058aea6936883088b383e7101	1658693071000000	1659297871000000	1722369871000000	1816977871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
33	\\x4dec3a19504a428f8aca0c3a762f13b7e60769312f29f19cb78458403bb799288080fb6ea3f033d7d74ca82fc8cf3d8b7615b6d7e2689a4a1634bd574759a434	1	0	\\x000000010000000000800003c44b739d7ebcefeccef4c6f44b0ab80f9e1e4b6644a252f5e1323f5d46dac7894223ddba51c41ac90de77218c2e8ba4bbb454f692113d1d8e876db4949777cfe47de90265b0d1fde05046837aa3eb41ff0c38789603d0dc770cc0dc471b9dc13fb288d81a6a0b2872a9734f4422dc3bc3e121f6cdb5d6c888ec7909a1ce8262b010001	\\x6995eca104414240b1c02d1dc867ba69360d60524645fa1076f1ae35d3daea77b4d2db0792a7e3ce4eaa78e24bf971abc3a032c1d1258713a208526a3204e30b	1664738071000000	1665342871000000	1728414871000000	1823022871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x4e6c81b54356aab7217a0be2b3b016d798ece87b62c35ec5a1d1fd702186cc4a1f1d4a5796c21165a3831fce8f0d870d05721a835d00d2fd0d6b88632b23203b	1	0	\\x000000010000000000800003c3d688a51b2c9bad6e9d6140045a95ecba032237ba56f9824acdeda91455474371948187ab0b150cd17128d68e548276df077bff2623e0d0639cbf1fcd0ec45de154cf0c4c296a2f682d779159eb8c0487846f2a4844e3908160e4bfa5cb5e4c0239c6b66b598581e46db6e7542e414620518a95b927f8558db258fa124cd6f5010001	\\x32ec03da7a4d18094105fa436d1df3f3453f3aa6b08b4d76b630d162c504578e306fd76850ca310a64571eca3263ef186d2a290ceb21a36e2103f1336ebeaf0d	1677432571000000	1678037371000000	1741109371000000	1835717371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
35	\\x4e58ff4b83d41bd4603a3654aa172db405bfe6513b4323d60fea8fa41c8166676b2899a7a1d4cce7d22b7611fcce9ceaf40bfc15e2aa43d9a12159cbe9e87567	1	0	\\x0000000100000000008000039fbe31745f6523f93f192c09024621974f83bcc7c3d84041b257f07e9b025f798226791426cfb207759053ba7ede12a09a68935f703587350c0179a242cab03cebf48cf3e2953a52cee801a733e97714fdd857ff7537e768933f56a5c82c02cffa415c1540f36e9a7bccb9d5a1d83c3fa4c3e5fb6d45804dee7f292936bc08b7010001	\\x937a1df7e7870e21f0f7a8db2bea52a791f2b34a6c24967f94b542d140b814e9816f62cfeebed7ef90fc8525c48298ace2a871d8ec36e0dc1f4efb2df5784c05	1682268571000000	1682873371000000	1745945371000000	1840553371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x4f90e3ab76f746fe8cf02a66bc04f93bcc6ae3514a214471aa254f61e582ef1bd657126096d8d2eb2905213ae61d7437f2d4eb6542536a1cc1b43b78e4a8b44a	1	0	\\x000000010000000000800003b802eac3079c5a32cc89af3aa8040959742a0d147a8e81fb0624ba38ee8a76aed173fb3ae1d7e58dafa28448f1ec1df23b6ade65040672d54b81da3d3ee3d8474bb2fd4806440d345c2861cb5a92c674be4e9e0e38c0bcca3bfe6d042c2fb71ecadb0a2403cbccddfd523d4068a61cb438d0316803330d976f768c3516e3fe4b010001	\\x65af71bed5d1f14e7f0424621161661c654919cd5641938ca46b5ed02a11b7e1aa266dbfb63228fb3e025e44aeb36590ad7c35da55d32d3dd8edb9ac83a17708	1655066071000000	1655670871000000	1718742871000000	1813350871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x4ff4165648c1f79531c182bc17067b6aa5484986da94d5e9c6dac8029ae360677e59282ef24de69ca650a4dcbdef6815f68ec120ee4923d6e903e12d2b13f69e	1	0	\\x000000010000000000800003e4104adc1fad57cc0273e3ab5ad666c56ae96186829320ec2affcba1c9ad655fe06866462540370caad0c62ca4d8a3bad38bc717ce4f1346689258549a0542494752731fc0bf7aa37e1f4daad1f1192fda7fda9f2397fce70f5672191ace2ea618186d23320752477685355fb28e3e59128c6c411a4023909c53d4d01b40c1f5010001	\\xdde6088621ad138fbfe28f54ff27355c709136dacdd5448e89d8e65de2f231f345853dc6a6aea2b8acf83b5e2ab677f37d8460b122e2e64d9d14cf26c01e2e0d	1678037071000000	1678641871000000	1741713871000000	1836321871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x54305d139cfc661c9dc9a1a8045d0ee9fa2fbf6b1ef87d0e21c412d3584a606e3dc1861c5d2fb6d432f45602c36a87ae4bfef1ec953969929bfaeba836ee1ba5	1	0	\\x000000010000000000800003cb70135ac5ba1b7d0ba18b4acff3280ff22cce4269c3333f64f1449a668c46f4cf8b00a98e8becd2d2dbfaff06c9b9e5b66eedcfdbe10043ced6a1caccb72777ab2ff2dedc61d42dcbca2bc7fc83c57c27333e55e94b90809d9b4b6715f7a9a36b5ce0d6f69eb2fd05c3a5b0920b802e810859671b9eeec3d0954bb99777c297010001	\\x25fd9df881cd91e8081f91ff7fa3b16ba005c594b5d5565c1eaedcfae5b6dc3503d8e926ae3c4a4383240c0572ca8c3f99e28c537d0740902cdf48fdf2bf380b	1669574071000000	1670178871000000	1733250871000000	1827858871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x548ca713a7dd6925cedbe29967d65623c40234168460da29cc871e89340d8288aa5fe525ba538a31d33d945504f5fa70bba4a29f5189cf92c24bf5a2c2fc7f7d	1	0	\\x000000010000000000800003d53abbcf21b74e964d344cbf99e1cac7411f9717ee1a62538ce84836a924854da75cee09f44182be2419bfa6eb2a28b38f32b9c5cc05bfeff5e1e4cb8ca719d376c53bc799a8568f13ccc21b6fdb631a02e63b02afc7463f70814050b19c9a0a4e9ae14485faf1c28ac437259ac4f1e6565ba86a7d3c378bb297df11b5e2e459010001	\\x6e10601060dafbae3d89e6dfe72ead23dfabd32d7857a6fc6adb778cb931b29d709b51d5a2d40a2d6f42fb200fe6ab12c9394407215759d8a71c2bd690a52b01	1685291071000000	1685895871000000	1748967871000000	1843575871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
40	\\x566410a1d2f6dcdf82081ea8ef5ea388bc36e576f302876790380ff86f06d9673cf4514bee88c3f327b9d50f89a6cd7753dc86dc5e22d1414b3f9de938911eaf	1	0	\\x000000010000000000800003deba0e11faa4b285ac1d3429c49422780bf358a80cdb8b21eb607fc2beac21352f4073bbb1a04d6a8b257764d9c98f8f8059364a359787ec6a06fa415904bceaf699978ac9efceeba8ce68ab879d198661b870105b2aadcf2722c418f82aef297f6be8f8fb4f6e28f24b7c322f8bd6da2542503222300de14da95f77accf5e93010001	\\xcb0ef17eb31688f537d3719a4c50dd361f02b36d1445db4ccc4917af1422e1fbed3baaf8e767f66477ee73434c09a91a5986d5907e6de27631ed64babc6cd405	1686500071000000	1687104871000000	1750176871000000	1844784871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x57986579dd16d524c6bc1a8794996e20c30cf64ceeb9c052bf7b26a2c60fa22d0d7680a556b8c38fcc76075eb816746b16fc8d5f47b91261e992d07d621b6db5	1	0	\\x000000010000000000800003d783a557654779954d5a11bc7c9a04ce834a0c25c3f8479b7495cb0559d6262a9076e4fc2f0f828f04120dfbe67c63f3ba143be4465628f86bb992554d7a34ca0eaf0a81f5b577226c23bb0df6f1c97c1c36bc399f570ef92ba6cc245edec1150dc8b349b4590e144cb3ceaed0006049bbb194c352611c695ecea0f6f4e9b53f010001	\\x24726367712869ad96d368907e7d8772e6353172a883a05acf6bc23f2ebf8cf3d2c942ffc33b3926f4d6d403980645bd68c61a0d877f30dc74681c8c7c79da09	1661111071000000	1661715871000000	1724787871000000	1819395871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
42	\\x57303999c4586ff47cbb93ad17d52a8cb4137fd6944fb3813c6aa0d456d97a30ad3625ee3985d979ef4a22d2829185fb5857d15b46d1457bdcd2b7360622c7c1	1	0	\\x000000010000000000800003ba72966210308c0156906a58afdec1c126779d6815ea43daa52f736cb9a81bf443c3ed7b79ce39e384e77b04f268b948a3458e9405f116506b33a0016a151b59ac8b794c21f41554704048d463ef641ed0c6c503e8b6ef4ace604b88f3d2c305849aae8363a06c2c6c862422ff3e750c24a08ab71617c0a0e8a51b6aea7fc7c1010001	\\x84b2838c8f54ac0c926198c635f502ba330b135094d4229673c663f0852f80749529bacc05cdd134b428c554ad3fdc8e85735bf7911fa0fa433d93277190d404	1684082071000000	1684686871000000	1747758871000000	1842366871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
43	\\x57343def27472c4a92eb6416ac3a60bbde64126853f8ba453004ad279d8108377cdcd9f5eb9a9ee3eea4f1730ec972e26731a327c7bf64d0d89cbe9ef5e29530	1	0	\\x000000010000000000800003f070023516aba1b04512fc5f064bfe72974cd0b54ac0dcfd346d0964bbbe519fcec4c251df562f3941f33f576636372c97f36fe3bbd03bd5aec22cde986b985d314ddccbb355ebaefc8de187693ac028426ddd65bd9746added3fb293113d4529bbb8dcadebbc5ce42389c7a05851b206d93b7d4a8334f300532f2be7ee92bff010001	\\xde004441046673c92e721a166af451177973dfd062402d8031ad14ceb01287a2ca752aaa7a74914e115d31271adfa83fc57fb9642d586ba66c32d61e5b9fc00c	1667156071000000	1667760871000000	1730832871000000	1825440871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x5824721c95d1f18d7da7548ed1cd6899c38a22929d3cb8e21e9baefe8acdfca7b0f796359d2591968bf7446f1e682e50768f43f9970cfddb89d0fd19bcaa4353	1	0	\\x000000010000000000800003dba6782fdf975b65d80919ac6ead53bf7dc6b174289511ecd19f37660b493e580ead4c10af6f7f15b6798e066b80ab49dd27a5684840d67a5d807031f9c6cef9f4f029455088a3d30d7971140b7c0deb2b866c651f1861c7600e272af466bd340eea5653c14b4b44c73cae1fe9bc34caf095a511f5ac41dfbc3d5829bb4270fb010001	\\x83ff865eb6a41aa25ccc7dc5460009c01f81d8ed686d8774ff28d69f4e6c181cde53ca309a309b0325420197d5a8f708b49c9d114ab38bf8989efb1d3a7a450e	1656879571000000	1657484371000000	1720556371000000	1815164371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x58b49fb5d54b9bbaa2e76428c241a6a566067e02108157e4bb79d40151a7d9c13e020e80bbdbc2a899314090e35472e07d4a3e7a843650ce85b67e2ae065ea33	1	0	\\x000000010000000000800003b75258daf03663d2d8fd3f4d5016716579cbf1e083680bcf147052e002abd45c8a3cc15f4463937e68bfa3a23bdb4ccd89596633a94d641ad930eb84f5d3b09bb9861ecf3025086b27e0c8df68cdb7187d51b459f053e57ebe4f836cea003efdc0230e405db864f601163011361a83895728dd435340034d9bb498777361241b010001	\\x1fd7a3b8201e31e94f4d39d45182f8fdfe3f68c9730400860a0c382b215096981ad70364a6f557a621b212275b7d8bf8a4dcc4367b41ad0a31be22546eb1a805	1664133571000000	1664738371000000	1727810371000000	1822418371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
46	\\x59a0da977af7c2b2163a143347fce79ea5cd82f2807dad3b444e8a9a2ab799b2132d735f1bc965a8f647cdc3cd41393ba9c0bb2c85614941397bc04858156061	1	0	\\x000000010000000000800003d9e8f442a64d28c0da9ac9fa19835f4c0d9517ec49b031a3783030d0cd8b90a90bb0f6b4e121672088951b6d05418c34738ed258eb73d41532df97c29ea07ee46b41cc9eee30b7cf34fae3b93b8dff4cbb5d6933bff33614c079c33dd2c66b90caec936319abefd960fe0dd9b1a9a6224525407abec2544baf4ae8fb8d77b9c1010001	\\x0e28c40e2ca6cd7d6a933effc72d0c5d7ac1fae7b5f827ba6e260f5f8c16335eb2c1de392298426c63cb8d7973367ccf526df47b598da37fc7128be23cc6d608	1670178571000000	1670783371000000	1733855371000000	1828463371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x5b14ae3325657a05a33963585eec40f7255a5c9f2b602e6b2ba6f5b1ccd408da498b50ed33e2756f32f3fb97a45fda9bb824d57cefc59ff92c70f7fafde1e641	1	0	\\x00000001000000000080000396bb1f73ea62032e6b9d50406af03335c1d618ccd6073aaf40c6bc99a8061d053782e4f12fa6543b0513120694263666696e33184f793adde87bb1e8e002099f7bab1c86a139f036b8785c0a4f58ced854baa7ebe763d3ad7d1ffa40b35fb1b6225ffa3c0e37a99c679a210207028270b968e5080832cb1cb4a610ab64992bdf010001	\\x922955e6e021cdfd527ef7b3f0fc7f2b535e4be23718a6ed18a5be741d10e79e0fd2b138488401a377fc99150eeb21d5c172e6a14ee3e9702417c49d27cb610c	1665947071000000	1666551871000000	1729623871000000	1824231871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x5dfcddb0a6c18d199f83cb35505e76ecf16dd137fcc6b6c15857e2666ef18fec604e557f78e13d38948064bd53e14fde197773dee1c7bf0454673298c6e8e1f7	1	0	\\x000000010000000000800003c243f5ef29edd178c0615fcc6943af4c08d514b3da9f375d95f40c0263d9c9900000e6d5c04960eb3c8f9ef11bb0fd0b50ce980cb2c0c55f0703e2e41b90a6a67a37c09ef9f83e4b0e4a48d4ff0f9cdc1845d1b66826e1cbcf5f722ef888aae92eef3a1ad3b4fa62b6b66b14a6eb671ace5cd82c27b385a6c9687f494d01267b010001	\\xfe24ab671714bd0e205e5d2aeba12c45d31b796e1bd3c69e85975206aaed32fa05a464bcb28baaabb533f6d1d21f6f8dd8b929e329e6e0a9b8875e4c8c6c1b08	1680455071000000	1681059871000000	1744131871000000	1838739871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
49	\\x615c8b0db81bccddf8a48425ebb358728010126c22266af66138e5ef7ca7f280a1bb7a616963f48c65e9f32a38ed810ee424c4598defba15b8e475d9b3104d4a	1	0	\\x000000010000000000800003a46750c64e82da968f462557d260eccbf03fbe48cf2f606c55359018135dcf4a08f1409bec738aa3e7b83765f6e19f62798c8adeee9a4de9e34eabfe37d36cf29758e711aef66b78a6780032f845c8284db29450514810302aef99bb70889cc7b7447de5f29ed3557e852884e439d22b5308e2e2d0fae1be47f5659d962fe97d010001	\\x845308541ff49cfdcf6f191bc437eb8d37f53f4480c95964aa783cc135d4b273154c05741c0abf98000472c09536031bfc1a2d0d077ee09ff430be2c4694770b	1657484071000000	1658088871000000	1721160871000000	1815768871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x71689bad7798b603935b37d0007e5c062997eca8200375b6497290fc9f8c44f9e21ee69105505195a73f78c3b24406f10ebaf3121c65e634a2e39932ce6da438	1	0	\\x000000010000000000800003afe84b9b5abdd8bb716a29e28f9a78f70e4aa1b21dc4f2023d9d626b1cecea84c475868956d89412cb88e4537ce3a89da3e881c1de8fc446fb99d6d4cb0aad5b9051e714b09d0586e44ba8c21fd89ed82b021db8ea27020dc9c8aed4e69b3266bd07b74850c2f4b21f0649ab1bc6a9a84b7f4dca2525d00dcb482514fa4cb7d7010001	\\x4c3552ef2f826bf3ec1c5d7a95368d44b37b05bfcc22cf91eee36963b5876aa310c9b5653e3ffd110744fc5e7eeb32a47d8e41103e52b84db0b78d6f23845400	1665947071000000	1666551871000000	1729623871000000	1824231871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x74dcecf5022081678b53a964dc7483a946e4000ad1b2f42e22968fb40f966ab6259e03020809e7412b0782ac7d88e64907a337bb70cbd5a414a3389037f355cf	1	0	\\x000000010000000000800003e37d57d8eb42c4ee16bda46303d3a54a076c58e94466c86b90993f377692ad0894f919e4b81a5fdd9f0723dda5658862763ff809876afee6805bfa155acdc350b2e9395209349e919616fc63393b04f3aee7b59024cbbc6229f34d536335069195dae34a17379a501258951e911bf49e7ee594264c2ce8e27965baa96bd47e09010001	\\xbf3fc8c9a6dc004a84d3b6b2f2fafbde177a499fde818dae7fa13d56e04c0d07e5ada390bd7eae24ef765d444f9a45dd4e46fe466f03f8b4de96d638671b0205	1655670571000000	1656275371000000	1719347371000000	1813955371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x754059890a00f0fe39a242d5d0368d1db3f36591c4897de58755f58b14bf1340fd5ee5cfc39129c74941d29aa541f7a58dffd7809742695a555ce150351c6c38	1	0	\\x000000010000000000800003e2b4bd1c20b77a5601024f2e05450e4362a1b5ffe0417857393aa2186ce3fca3621701d317e744f3a61ee37611757474930ab92061f09e888a558563f63a155a4a072374a7b3974dd369f9caf24c225a2658a624edbdd5708d2a40533987fc84ca11a369c292e21d81ec04b3dfde8ca0720f1648c7dcd95ff2f5ea00be111567010001	\\x4d781023b851d8f44b001cd8879c1e69921fe02a4dd0fd469c448fbcce393de9553084119a972779b34dfc9e65aeb26897bc53840dc28303cbe78a46cddc3107	1655670571000000	1656275371000000	1719347371000000	1813955371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x75f00ec42b9f90a170870170984a0867eac7385cc63406c80b3bfda817335c2a0044616b9eba8b5e497eae431798f8d1ecb182d3dd1d6c4a6718bb2795094705	1	0	\\x000000010000000000800003ba9aca4cfc7955d4c60fdadb0fa18ac4ac299e97e6df21b32abe2beeace50b48aeaadb76115048cf9f12a978d38bcf3132a8718d05ea80552d6fa634e4f3dd29d70a60873c5e8dd78e0c333d7f1e7c543480e4dc8f7396abdd777e6e9ac108b09a130127baa935b91cde387d23d6a3eada6ad60c3ecc2d4837876d4ac280ccad010001	\\xec4f8f46b926e2e386f15a89f8677002efc2eb024a8af33bcb845a1096ae10b3e458b31ecf575fbd9e3886d2476299062168f6aed782e32b9dcf61b67595270b	1659297571000000	1659902371000000	1722974371000000	1817582371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x7688feb087fbaed2302595749f04a05ab565020bcfca1e3ecfc1dbca13182aa7a82ac59e4caf08068dbe0b4815af1a7a267df4bf0885643f2a9d6a93891e737c	1	0	\\x000000010000000000800003acf99f40e10722d17be28e63ea01f34919b0168693a8e5a69ee6dd47a226ced0b2df08d5c4c7245aca09de5dec4a9454bc624aec17290bee3c9565581a613bea20ad153de8b9801f9c519b4dacb614f8e517ce52a0e92ea8676a0f69c569970156ab621d513e62701046ee20cfc5d2e5d9e07aabafdf7eae4ea22e4f8e43d0b3010001	\\xcdaa03c8aa7007fb1f3e8468533577fae0ff5d797bc2d1f3ce98527368fb447723ff5c9cece2da799986a3cd7f851efbaea3d9b30838ead845743586131d5007	1674410071000000	1675014871000000	1738086871000000	1832694871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
55	\\x7760ad4e034092145f35a59f3fb7994c535bf2e6c62530ef94c70e416c9490b1e04fc8e37e2b2aae65e8a3968f8a40f5f9179655a8ae6ae49ea170830914356e	1	0	\\x000000010000000000800003c6e7eb5679cbb8b1c0f4377220a47e21d4eb08505ecc6a23108c1084cd40cdefe0a39add164b05fc759f93541b06c369ec42f1f05ff0d8c06f3cff48b708132f10b4250545959dace2c3aa4901c869dab5c372434c31c8544fcec847076aab104cb535a526b63b1d8669a346f1cda162d8a6e68242ff104fe1cd0850d61e2961010001	\\x3e266c60cc1c543c963ab72e1c42ae6b905d0d926d3a1e67e360d9251a403a7c7d0cdcd8e52ca14b4a72d7b3f0e83bf14af5fbbeb7c274ea3b72561ea5bcc00f	1668969571000000	1669574371000000	1732646371000000	1827254371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
56	\\x77e4a43b90fa4a6d363d4e1f6c06f6b1680585bc0c88f0cc9870f42f6593d6111863d1bb38bf552358c4c57be4ed3d17ada1189fd4060862be85593bef194950	1	0	\\x000000010000000000800003af654be2967ad85051dc72caf6ea9c621544c4ad53ad53d2bb105c1e22b0ea8d93812f7432b2a05cd2d0d9e3fe82e2afdfc6fdee8a3175e19b581ca223feba25a97a483113b946d5abb1de6acee32235aecac71042e3e50037a12dd28976e16800c1426fdef68919c30920313be698e154270db48281c945c000aa2678a87b2f010001	\\x63f51098e57c19035c89998a2c62426648254e016daebedfb487786f2e77aa12989f2406ccbc839b57549c9c9ef659499975b074be5d59a7e987a7d958f6780f	1686500071000000	1687104871000000	1750176871000000	1844784871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x7ab8dde220b35352b4edda5244f1d4fb8a22ab93988aa9831e89ffc5081cc7bad3416f7762a269c1db0ced202f75c775fde1868f3fe4a1239474ab3e0e7021dc	1	0	\\x000000010000000000800003a4399fa603c60c171d712b81ab7a5c5b417d318bcaa5c75147174d9799a7b5ee86081ed3c04842ce2d4cce84a33f8a494a1a415456454df808781394e0f2769dc70226a15d4807f23b44d6983bb899c56cedda525307cb031b4aa42135a4328a50f32803b41118e641eba8f00ab4d462d16f3adcb5db8356b5cae9bfd68aade9010001	\\x5a910ab78f9e66d77a18e7ae9c0d79cc76df20ea2b0703da89716eb33e8b107ae1a83fa45426943df47f5c366c3d4a0548abdab4a95090522743f5598123f00b	1662924571000000	1663529371000000	1726601371000000	1821209371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
58	\\x7b94076757fa4c1b232b3346dac9d60fef39cdb8251dbdea467c4367b423c3722038fd10e226acd3d0a7fbf7a12f93424ee013635135577f307faa75117f9d5f	1	0	\\x000000010000000000800003b2ce35a126651a175e9190daa3f03c4fded9754a4505af71f7606659f82cd5fe634a818e6d3a5c0a23eb4f9304662ad1979dbd87b01ff036e4f95dae57b6b2f21e416ec3069389b498e41a4f010ab2f99cc699a0b6bb8810439827919b188f452424e0cbc71cd1b0e94f0834117fc81d4fb6c599e7097dde77da086107c00e17010001	\\x652244accec1ebea2fce4d1418fb02c11605f22d2a2ef7a6ece5a2dd97cff875d203dfa648cbdd2a868d6d8310eae54eb53d8861b0bdc1a2e7a7a4dbd39e6308	1668969571000000	1669574371000000	1732646371000000	1827254371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x7c64546fc0a979355daad46edfe974cc6eca0266809d2be3bff241ba46a318215afaad9d3f4ea27b7118927596cf0756420334e980d3c7da02b1dac1f992c45c	1	0	\\x000000010000000000800003e0d2de09c6c78eb7dd788135554fc0767fe5980cb91fb2d95ed100568211af76f00c2cc0543e836585f98ea1835cfb523cca4e1f82ecea0e51137bbc9db3e83b23989074820f31dd8b23790480b6151d93fa7b6cf81f2a2a055889ff7d31c91f138c3358862781f4b81c43981aec40902ba8e874d1dc6e75f38c8cfcb454a771010001	\\xe7697e95f9be283d71786b484dc2a5846a4e29f2c4dec309aa4301fa488554bbc137ffe01d1c4372e54331a22c677daac7012b10439c36197ce88bb60ac83f0a	1659297571000000	1659902371000000	1722974371000000	1817582371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
60	\\x7d04419049f7f837f4c9eabf598307e55eec5d3a4a5f543e684793e42a5dbd506feebe45fbd01b1a8db032be681ce8147ce32b90fb18ed150ee196ed9d6bcacc	1	0	\\x000000010000000000800003bd9e8906a90ac1022d539ab7ae4be5a522084fcfbb1be1e867ad04bf7e6e05dfca5595f401b0acb1c4e4ec22fe368721a3d661862e899c9abc2f32f3b914ebf908e7219fbf89df23eca91224e99cb5d4f563e23cf92833aee767b307c90ecf6d2dd533bfe78a6a12f66d9c0e2e603987e783cd6b69353e4a9954a850891b9ac3010001	\\xdc9e9e0722c8854548cdc231454f61f5d03e15bf5c724439562bda871104e1e4470f047e302fdfb0ce5384207ce9bbe249a5f5d34825834a8f474a041bafc10c	1680455071000000	1681059871000000	1744131871000000	1838739871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x852812b54c0913a7ef47951f6e254d0f5203ca5d22168ea486567ce17d0887e9597600df6ceca0a7ede9169c293dbb976c3f6f80d193f96ec89cc2d8c381b73e	1	0	\\x000000010000000000800003c91d165a93f2ccf1fcf3500f3691244bf69cdede8e3c9cd03a8f31efb290ad2f94f8c789fdb9a33dee4065184595639ccdc47aa9e997229560483815b4ae7718729a1b7b99c98bc74965df799966990a77b9db18c78a72ebe2e856fbccd725edecde9565331aae10dc057ea62e1a3bd7a1f21b6e2d47dfa188f05883563ab8ef010001	\\xab410c0ef7fe8059be8c629f20ef4c61dc49a2149cad0303b59ca75a0cd7784eb7e960c5ea20910576dc09ebb0ca0977f9f1f184a4d730298086d3bc353b6f0f	1678641571000000	1679246371000000	1742318371000000	1836926371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x856461a30dcefb5bf10a4e3155719122373643260657c0a9c7d8cd3f635dc2acaed8762fba9ede6f7a4db62e798bc9bc458c277ca1b57d0b99a3a5c54cf50ac2	1	0	\\x000000010000000000800003ceac09e9bf49ae32f5a7781bc17b39883f0f5bab7d7240cdfc0b9a2cffa9af6b964e15e98e0663713954b5f27497461a9d17c4843024d9ed4e61b5d73daf5a92cd7384844592215eff827609e054ca889891ff7e2dbf3c8d4084bc9c736d9722a140dbd638a0b6d2310d0fad23962e0bcdab6083ce1f845b9491be9ec58525d7010001	\\xc4550ce634650da10f80c1b8b86fc9343dc15ceee56ed597df9c28626be9f2a02cd5ae50a5eb6fa21780b1d31fa42189731a5c5f05f0ee56d86bf6340ada000a	1659297571000000	1659902371000000	1722974371000000	1817582371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x86fcdf7b401c72f8c49f44949856edbe584253d36f07d3fbab3eec1c5b2d2403675f27dd84e7a7dfca874a26369de98492e9581df23c53a31ca1cf0d8492508e	1	0	\\x000000010000000000800003c56d5b79b75195074ea3525b21f5a80f85a0864bcc5d3b26f61b2b127e9ffb77292f32cbc7cec2d8e8e12e755d4b90d133d3dfaeb2172c4213aa69b12c15c4a11a00b757abf42383f55956622ebbfedeca3d5f22931358f7f614b49309e6a55fe3e1303341db767833f73131030261c63492c2f68e0ce8476445402a154791e1010001	\\x321b98a2de10e9cb8b97d7e9f60555c92edd81ddc3813c2e3daf7bb42df3d87ed60c9f3ff20122d58582b02ad618ba1a6a212b99bffd093c0b41f20050cc620e	1656879571000000	1657484371000000	1720556371000000	1815164371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x89302a6fab985cf6c090bd85ccb808e1bc77e0a910da77ab1a81c2fc9e5f1d51f5d3a2be902d7eeccfd29e744cd03cb1f486327a7230512d9357f8b8be810afa	1	0	\\x000000010000000000800003a68d2f713195742cfb48e4c56aa0116c986c4f4ff0d5c4cd3d63bffcd79a4c0ef8f5eb93aae687952e5341bbf92986f20a5b7e3524aab9e292b187d3eda16ff0f6d1f10b09b176a51ab10087e743180e83df81734356a49d4ba17b9c5be7e99af7a0100e7955a0158452e513a5e51f1186f78633a3e0a7efed01efae6088ce35010001	\\xf984496f64f249dab624bfddeee1bb6ccc9cdeaeb8947fc48d796c6375b6c3f0ad2853b2f1cafae24b7298ca24c7b19816f3b8b7acb9f5dd01d5cef6c91dcb05	1685291071000000	1685895871000000	1748967871000000	1843575871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\x8b584fb0f3655888e26da5faf2d8d72373f55d10e4ce7256453c88cb1b2ab17c0d93dfe4dc3ddbc72352d8e90ac41aff38a988a9984b75b4fc91552429fa85df	1	0	\\x000000010000000000800003a2bc4527079ff1e3eb82cd045f9318303f6bc9e6ab5886f62a59e4adf2d935d2a8c85d7d21a74245c358bd5d33748f15ab30f7bfec22dd43b4decaeead9cd63489c47e0200e025f97c80c7afeae84b5ffd23cec7ff77713b4e2cc77b86247022eb4db9fcfc6645d212d57d8f4cfe6697bdecc1e3f02bf65e60650f11f0306a17010001	\\x4a7b8eefc9bc8560e115021c739a19932129d7254cf98b9de416fc123d5fa982153ef87c0563dbb600c21219a5ce48c2bba2696754d194c03083748f4e709d03	1671992071000000	1672596871000000	1735668871000000	1830276871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\x8e106b6a475cd218c63b63f950f46463119ed0ed8a510066bee61c52071f67d3936592636116375876e61097f71ec9f1547cbed86db86ffc5994030cafb21432	1	0	\\x000000010000000000800003f4745a474b207a65b7b940caa2047d0ff411963c05961b90b7a12387091ba27ea8890117cbf18b213eb5434d7450000530318bb01202a06b1be835da5c463be4c217767768b0d48e96d3b37306ed226203b30d116564e965accb1fd0f9d643f8f8c2aefaecf47a7d18d568f2753bae7863728e7e65aa84aa857440eb2d79a4d3010001	\\x4290f8c092c9b2006c3bff1181c3d9811b5957d4e877af61d037a4f4e478cc7d70284b45f0a85491dd6a8132be5aa7d20421e7a33856f239b779353a980b1c0b	1666551571000000	1667156371000000	1730228371000000	1824836371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\x8ebc6e0a7dfbf9a4dc7bcb491fc4476d8b0f700773be99273539cb5a98b54b076cadef7991c77be398c2259d6c12cb9395074ff49aecc5a9835cbf2d8d090d42	1	0	\\x000000010000000000800003b6aa4efe81ff78f38ef3d7ebc2d7b1c1fe8591cb9ace3833f04290f38860b75acae290a1deece5c73a51c9e6e809fcd5f612ef2e8b0468b2a028f9afdd016a49170892b3ec8985663387287d29a49050f12ba8bba979665f2f82bb4fd00c1cf9de6cc33d6369653e0be69073b08309c8a4b5bf0a6f700cc03b79e709a6417705010001	\\xf57732adf54843300d46194b8aecb621e5eddd1fd78967de4309a4403eaed2523f50a10287f9a88bd80411195a052c8c1d3f97e01b4496e6c4031b0f01e92a06	1679850571000000	1680455371000000	1743527371000000	1838135371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
68	\\x91bc9f5a3294210d11e6fe156efa7123557da299a3e1d667fef73099b72d814b237db2aa3d5e1301547c01293affd4a1d74feb92e095e8b9cea69c98f0b7726d	1	0	\\x000000010000000000800003c17c8aa2e8c93f1d12b556f01ce4f604de432b5c8ffc97a545ec2a89865ce1d6a5c7d4ef1353d3dc5c6d5010237626809f676fef515dab53b332ce156928d0a670c680aa11848318768f6575f459192868269c17f1b573336dd71b6bfa14bd0c331adf34c9d19a6c693739f817ac85fb11269eaf782eb25c46e76fc59e788e8b010001	\\x3fbaebdfeb99a6f5aa5547249a2d73d29163bbf8c72439275a62573fe3f6eabaa3c89eb4b97578649c33ec0aab09ac4e76ea56858206c44143fc6a20141d5e07	1683477571000000	1684082371000000	1747154371000000	1841762371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
69	\\x94d4efb8a4e39898d575361a5be5a2894de6f98f612f65354adab2c0e8637746f617420447507def1cd65ddd1c1d7d7bd245d084afd3f03a2407c773c38f3fd2	1	0	\\x000000010000000000800003bfa832c9c3413bb0f288a4d64869b0bfdd8ab9f99e8c4a5e0979a5e99fa893063951b8e06bd2b87552c20f6034d382c79227430af5071cb494e54be37f7502494a20d424d5a310e685823f1f72e921f105d659a31c5dfe59d077e3f3055cafc907a9318e10094a448c0847e4f91ce67b92b8d71d0539d256393980995caef6a3010001	\\x2c4c6e38bb9c4dff35ab86821e087497e8f75af1ca7b5a981ab61c20c37e25a984aea06c408872a15ecd69c53d006e9c6967486baa7e7bb354261ecec76a720f	1682873071000000	1683477871000000	1746549871000000	1841157871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
70	\\x9614f6606f42d7e198f347a99770d71f7641ad90688ff672888ab2e55672841b22c2e96155e4235a7866dff72fca02379d91cc648f254c6c3896f91a5e1d88b0	1	0	\\x000000010000000000800003c70456bd38472b22fe45e5fe9f43cc7d6858a5304e1201756b02830f28f7eba602d92ec189858e797ce52aceca70bcd0c537868140fea86ee2664c2db595d79bf4e0351cff807f47395dbb3a937f8fa5b60f001846ec5ad4c3c9ad855dbeedc5a52e643a1fad352b4f6e8867df5b7f4149d49d3b720b246c7e9570f4de3bb7a3010001	\\x883fda168ca17434ee8fd20596fc3c098f175e9c581f1da0bce51fb365559e25c2e1d535be5bb4ad2058076640e6079a528aadf35cbc856c480e00d2d8cf370f	1679246071000000	1679850871000000	1742922871000000	1837530871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\x9cbcf24f19d431488b58267e950fd605bf32bed4321694dab952fa19a4e8758c562ca2f0871842d4da7bea55e294202009ff7185ed8fdc79de5ecb3546a15452	1	0	\\x000000010000000000800003c36c78ac4f009fd424a0a412e7811420e4d7d36b285cdecf3df2d1906b44644538f94a4a63d00ed89a7fc66a1065f43b1754b8543848b153d8e1e506ed445e915c89dea01fa33342114bf27662971b5b0f4b97ad0e55eb0a227e8d6a8028c18fdb9aa7353885da633c18d67871d5f44325f5b3f0dc806ef0109a1dbbfd859905010001	\\xa7f550cd1f708e0fbe9de0f7eb81186524182fe292dd2e85298dc6c81718283ae4d4745254beb71b67e1a28faca8402945241c22dfa3998a7b78212e7f25d808	1685895571000000	1686500371000000	1749572371000000	1844180371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
72	\\x9e44672ef37ec0bbd068ef045b23fc071882b0e9581fa6731987d7a58e8bfe4bbec00fad3cf0bbd05825312c191299e0618e98fa19cab9c9b2c052ad31223634	1	0	\\x000000010000000000800003e224b5fe4952348ca85d19b8e444500969fd56f19e42f1806319ffe8a05ef3196a9ca9220645599377b2cfbd0c36dad73bcd2bff883e8ee4c69de12c5c26f5a3c976c67dbb5fe1b8559bf7bc106da83102eb2631f5cac85270e957c6d0d070fc33d20fb770dbb5e3f089e6783dd7a1cc4300dace342c9c53bae8850c5aef67c9010001	\\x9a5c1401eabf3379a3db732365f274f36240db6e06ec9da313782d1a2da07a973322fdfc9fae119348373f4c1972f5584622f1b14f318dbd746dd106466b0a08	1681664071000000	1682268871000000	1745340871000000	1839948871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xa1b0e326a5a92631083aa33c6674f5e05beafee604af9393aaedf00eb0ed7615df18c782ca4f1b7866229fa88dc779d77ff8522498f1c2a743cfb3608e0fe5d9	1	0	\\x000000010000000000800003ddd1a36c575e945d04a786460927bdc22585568e2cf357923d79fe6cb420ed9a96a91fc90b96fd85d2e00e01928f48701cb010034f6dacf85c70e74e4d72a6c169d55fbf6b25cb9cd0c9aa3a88fc9ec2464fc3da7a08b8c0e06ec38137f0fcfcab32c98ac8ef328d689c50927aa6a04ce0044fb12c3249a6136e51838aa422eb010001	\\x59ddd784519bba73de1a061de0bccfeb41fca7a76ee12b532d0dd03f8f217511e8c70f1a2edb2ae2438037b7cbc309ea81bb51d68cb426f0e393a05a809d3d09	1662924571000000	1663529371000000	1726601371000000	1821209371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
74	\\xa3f44052f38b37cb70205eb20d7a9cd4cfd01f685d9f0393437d090cad32f4413e88c844381f5f0ff8c12fc0680588d2074578b62e5d4cc181bac235a994b6ec	1	0	\\x000000010000000000800003da928b8bfe6b567d90dfc8c7ff5cad1b41b90365df0c1407f72039071807994649fb03acfd66138e602e39e675c654ec12ec06fc64a38456854154a9878110a82947166bb27d477bdc887894b9be2832efad2e1c99629af5c65bc73cfb0bd2d5f355e6a7f661dde47f376e83e5c1241acdc4a7a8ce53677f934644b364737f29010001	\\x789954ab7adcf0ffb5a8921a316d63070d53a1d6d2d1e60a65e875cbc38502ba4d0b6c1d23f6fb894c6e1edc66d1d25be128c9e69d5eedcff0c61e8405ad150c	1677432571000000	1678037371000000	1741109371000000	1835717371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xa4f05a7173234c6bcb7fd246aab2a95b036ab11f270afbf46f76919885bbbdaad9a16e4ea6170037dd1629940ad397caf1a546b6a41db735a20385f4c42cce40	1	0	\\x000000010000000000800003cfd443e75756d7c9f9c39aad49a66e011e700d0b6370168e74c73b00e0485bb2f22133ef469c23731362bd8dc6ce76c458fc23f0e8769656cbe784d5abe796d8754c6a4912f5891d601cd0a1f645f6cf51032e41a243a933dd32828aaa88e7d4803edf441b03bf1c0da5770c313f861734326cfc435f6514e1bb81d3206f6967010001	\\x250075f624c5a012625d9ae5895469e0d5f285cf2e3172cf611ba0d82d7fec5e6e6dc2baafa5aa31b6f07a614a148ef7d2714c044a04b77821c1bdaedd6c540c	1664133571000000	1664738371000000	1727810371000000	1822418371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xa7b0b01b2248c377dbf6518b9db5b1efd2401e93f24ccc7185564d0d44292536d8c4846127bf582bcd7bac5deacf1bf8f41c56204b29eeb576242232fd9c7a2e	1	0	\\x000000010000000000800003baa143ad3b2baae1915d67dbd912ecf482540104fca6cfa8b3f1f32ff37b530cd7c54d18284b402774b54a8786a48a1ce82e2fb3e341c99634888e2f393fbbc9ce8ae030ad9444af5859d2b7121d8354957ca8a36dff2fb9444ed8cd491e63c7d4fb35a44b336fd46599f9c136caf3c8e6569b8eec3acdfbb4960941849a4f0b010001	\\xfccaa3671c78c1030b857b5fbc9b9fd8b4616a2ddcf558809f6b4aebf9b8fc55731fed2b346caebe104ac2fef485d7f310a40379ad97d983ff06eea97901020a	1679850571000000	1680455371000000	1743527371000000	1838135371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xad282dbb204b5e54b7ed5f3ebbb122db8d1cc503716ac8be518205d42573d9ff3ef8e9bbfeff5d9bb65543f67b9b1911c4ff10047830c9bb714c98f171cbf947	1	0	\\x000000010000000000800003add585be853769a415a8e0e5126b1b2b7404fa53359bcc95261893426cb56194bdc50fe586329cfe6f90e210299e9d7b738d5178ecfdfb76dcdb9977ac9b545cb88484d5c23323cd2b229e2a5753a27a71a5265c84df6c74e26daaa01d35c6584a49ee381519d1e0ed83192f87e6558ba4dbe80f508cc0729243c8b1ed772603010001	\\x06de978d3257dcf81e76a0d830541028f6365658959ba2fc60e7d4e314f6d184124cd730dc6590532cdb9dccfcaf172606d4d322d5c780c8cc40886660f2ce03	1679246071000000	1679850871000000	1742922871000000	1837530871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
78	\\xb46c1bece447a2f1366ae0f2ba2f42e7d996ea243e03bab29ced759ccda437ba9077af6f1ef8bb28e502cc1932243c62678731d41a2e56d320b72a88d4a4cab7	1	0	\\x000000010000000000800003c0461515b94719230e5443d029f771de45fddd68c6b0fd312efa5735098598a066c0ca58e4dba6c80d67cf31537055128c5c4e24193fbf8a48a581ad7d06f3d10c6a83e05136ce54eeeaad057566239ccf2b67b362a251da21d06a9875f0497f9e1ea5cef4ef3322efbf0ce4f37fb39cb7a1311a0465949145a0c321d21d59a9010001	\\x3d344305ba6ff994b82e8472832ee20e6b5d1d2843a8961c6d12975d288da7f33af3c992f52c76a8acbd3e798f9d88358b6df008610651d5fb90b6a74c896a0d	1679246071000000	1679850871000000	1742922871000000	1837530871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
79	\\xb6dc48a4cc8e056f6a33946d4dd9c9dc0cb31057b93017ec66361342da3a534fea3943a5cf90ea69c5af826ac8c60f64640f295c5ffe11205f779aa692545247	1	0	\\x000000010000000000800003bee736837795cf3f47a6425e24c565a541744e4aa9ea0d05025acc06d39184bb8570f2787639838304f462cd03def4c76b3ebdcdd420ddc37dd29ccf7e0df961675a3c1925096ff7e0d953ba9aee03a7c97b69e70b75e13d6aed6edd216a32e7400b57793ecc60fc5e23f4fe0624829dd6085764c66bcc4d3257d54d48bfc72f010001	\\xe405f7a7aec42bd4023a37f52f49d693fc43d07d6a21805e754a4bfc0410be602c9065011c36f29540a8786bd50057025cdbfe573c8343e75b730f7ba3dcf105	1681059571000000	1681664371000000	1744736371000000	1839344371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xb67007e7c3bd3f1370df3ddf9e4054c1912a870b04c33cb5d44abffe4f5b793fc92fa395bf76838514aa6498ff0322cb754190bb8ba316404cf52a0c97bf24b7	1	0	\\x000000010000000000800003c75f2d375ebefe4c39893ee443fa2021ee371f7274307c319432643fc86e06aa409484d16db6c81ed961b54642a65089fa743413dd38c5b887aaf5e1f591db2393c763fe59ef2fdf1645b89aae531c02160e322ad0db8fb66e68e5175ad31ab53ad0e133e54befc041632175d34e5ced1c78691caf1b5347b943de8fdf622457010001	\\x9b4061987c81bedef208c44258f2aacf42ba0f4b36577a8821b64c600ed653a6d6eae715722fafd5cc0fd50d2187e6caf624975495eca668bd601dbbc2acac0f	1672596571000000	1673201371000000	1736273371000000	1830881371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xb86453a53f4a9fa6d80f1de4d048526f07c3ae75bfdfa659493f15a2ba01c63876440ca309e58f1c2ea1abbaaa6974a8d6dac7612b495cff49b8a830140b1d2f	1	0	\\x000000010000000000800003d2c89a0465599f5756969486d31ba8450b49b986598fe749bb28051225e08352a288268bc378f6f47a4cab483a1b8aaa26e93d04bea33d85fabf86e5a2a39acd34f7261da41ebebb4402465ce4297a80aa04ba1ed485e3e98c4fe425faca9736653ddb04968e9f6f59f0f7a4b6144665b4e0d7aeb8f3427b29d75f2917feb40f010001	\\x71e23a1e17e8cfc73d102c05931a8c12a29d40e3a7d6c217d00c2c5c1158ca43394274ce3748b10fe588e48b5f4213005d566b8b41275d8c2b783c998e275100	1678641571000000	1679246371000000	1742318371000000	1836926371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xbcd0a47cc70a895e137240e1af3de9d3226f7ed3fa1378517f226de09eeb595190bb18c1f3a0381219691fca770833ecbb16baea7642b1c5e909ca35f672b020	1	0	\\x000000010000000000800003aa54ec3adbc532095b36db47a7b3c526af1aa7ac4a3b820866f05454185fd501f2ef500f93a3dd197c167551bdc9b06ab7c4866fadb467d0ac70e9f6ecb4d2075d610397bd2a080f60c79faa7a4fb3d1a757caf48560355d4a369428d04030a73ca4ae6f1bbac35e2de30a297ef6260ecf18cc4d1ada8cb49a570dac3e137c37010001	\\x3aca9c0b93e160766bc27c18c6cc882b71ebc82cc833aee2b7fda088f93d9407f9091ff3e2bb901391ed39e2151dcf4997c7a85674034f5abeadfd37e2ea5e03	1655066071000000	1655670871000000	1718742871000000	1813350871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xbed4bec9c52864a8429327499ea5c9e1e1ef82e3278ab83949a40f2b98bc53d5de634ef4b1e6aa88162fe2bd7406b52457151f55b1366e59f7743b76dd917882	1	0	\\x000000010000000000800003b8ecbf94dbfc4c3fb1425531ad30b406dd47f4bf6297285321d3f276402bd867728a5da6604e4e25619fe5313dc5e9195fecacc4e5e490e307226938f7ac4eee8451457e5d45a0fefaa7d1cd5322fa10637547afca082b5bd275deeaf6ce992ac9ced775680344fad62d160083d27fa081b1ebf6d2f2d94b7b511e85d68de0dd010001	\\x1fa9b18983674c250fd9d9afc30b6d8879da08abef665d40faef2bd529b38f61db86cefd9d0a63e2f2be99b044de666692f3c95cff34aa02f946254f6bbac409	1684082071000000	1684686871000000	1747758871000000	1842366871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xbfc86f3009e93bf4e7bb2e3c77aabe3e3feb4023e15c7d291b0b1de2d4ff7e472dbfb5d500bf336baa110d1ca0aff55d12954b3d6e47ad54a9e0be278ee3ea54	1	0	\\x000000010000000000800003b25fbda1ba76dfe9545d8f11fecc21ffd373873978fcbf615575e550861ea2084bd0d355c905f2437aa69e4827008386b698d6aa286c3af61a2f8f757ca051b45e7d54e66d58222951ca60f3f86f3927610158aab8404eb7876a926874a5b1afaab2ed7ff84bbd15097c1bc1649fd7e9cc431b8a10fd35210c46cbbdc29fe523010001	\\x7a0654cbdf211d147e102377225f3ac44187516dbaf31ba5af0b646d28ffc86287204c41fe60e1a95f026bed99cf6ba42f47ea90a4507d441f0d09c610e67c0d	1664738071000000	1665342871000000	1728414871000000	1823022871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
85	\\xc1e0c063e26e9c02ea142169a86ef8a4e00d163f6ad58a3e74fb0bf33f0127c6c48c8edcbf2f6a9e9e4bca26061c9e2c09eca393f901d36296b3ef2025e35028	1	0	\\x000000010000000000800003a6d10c5b5a1ebb07e14f22c40b27aad68076615123e65d73e50619ed407c8b34001bb6312b3005b1f5e91d8c94f3f0c72b1b1e9bea4d8ae3a1c4eb9a7aa5be8876876b79a13824709f35b5274488a7f92308bbc1879dab80d6557ac6bacb932fea269878b13628814faf16d795e5d6d05a9ac8bb0cf4a77804ae84b85461c2dd010001	\\xe54fc81ab26187ef8b8e1c6c2d9a8b353d51af4448d2bf77905db5c6f5503fcb35abc8c473aa9c58bee5361a1578460a2e7485a78cc32d56136eaa64561bfa05	1672596571000000	1673201371000000	1736273371000000	1830881371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xc4c43a57fdfeac7e2b3694002522b718a53b25e251ef3fdfd4fd6b3d1ec4b5f852eca4e0c0cc7a68bb07e10c5cfbb2ec6a81843808f791a771b9effbabd5fe82	1	0	\\x000000010000000000800003aa0c87afc17acb4f1cf4def27f7b1a0a6895cff57cc8c53fd9e73cad46933a358cbde78f92abf4ecacabd6dd0884ef8685444009ad8836c848d90074b83c0c08b9f5cfccbadd4ef1317585845f82a6c388c8508ac761b978ed16aa716b22761d765c36c11c3f80ccf8a229371e0e74801f10e8262511ef1de63924c63d034a6f010001	\\x4590218d71699849112ccfa86a2f3891f6e992ad35d0ed2940a88cbb059b6ffe5639bb014a1451d9e63e65eccdca2c663d1a6ea7a48b05e9dfde2738a84bb901	1671992071000000	1672596871000000	1735668871000000	1830276871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xc794fa089009bb97d2c65765d0a20f5c0630dd181c12a3b235baaf5075b2f1483a3c0ca35b9855e47cd2201453f2161b5e710efed45e452edaeaeba89e64a0e5	1	0	\\x000000010000000000800003c6d65921599e5d9f022110361e6ea8ff5917bd02e946bcac16af7fc99d9e03f62d01e79fc360414e376ea36b142d3f4d555aeb5f40fc0885f2826c56872da1d8bef79aefe4ca932ff0e5536fb0440fe38b9fc105af8a6742e9a3082855a1b72e601e18cef1f587d75910112886d16396611343e4b7be2b6bbe8ba5bc87dbfe85010001	\\xc9069e02f51f5b0374df102cda922da40edf6b5932757dd8c0792566468392670f87c3d1a8b5bef7e125ab03b8834c67129bd051e8d0801911721def7afaad09	1685291071000000	1685895871000000	1748967871000000	1843575871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
88	\\xc94c9e95aa726c71e2d69f798fc6c17eaf96815ea24fbdcd9fee9f1877b56c3004e2386e418690d2b0ad2e2d1980e373630ee973cb7bc7c652f844a0ad616f13	1	0	\\x000000010000000000800003b728ac2c8b2182d8ebaa0f3a9b5a7ea76b2ca0929ad5d7702520332ce59ca3a27ac71fbab79d7b6d770fe556f4d10b6cfae5f44cb5dbee7d1f5c8d36825867e752611c230f9b46837c697124eba61ed181cfa0daf693b3f25a02b3127116cc975702f4ed634d728b8317b294eac9d3e8ab68cb83f01e44a019820be19836821b010001	\\xf9b252b364a18db02b9361237d0b840250176a57f0dd2b3228b1ffc8467974178e3f0c726ceeb53c4b26d319d5730299e02e6d722aff3823b6b6b23ea3334b00	1667156071000000	1667760871000000	1730832871000000	1825440871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
89	\\xcd485afe228db79cb1ffccc0fa46db0993e1aae1052793eaeb0b2e8eb25d37b186744b39453a852bc993ea6fa937f518c56554e1e6a31387bd5eeff2eaf0c8b6	1	0	\\x000000010000000000800003bc6904c5af655de40d0471aac9eb4c69bd56ae614dd3c5896a39b1e90572815f1e32bfd6836a5680b7089802b795e7aaaf1707e3d43a8d4546f702c076febc4827b5cfe067af6b8d950e81dc80076b7fa575791d65408ad130bb0eafba2c68757707df1bd70d29bf17dd8e2928949c12b2f533b1319ede6d4cc537c773570bcf010001	\\xe4c17b0cd9dedb1dbbd3838db63e6646253a22ce098d25ba8b38d7882b4f51e85a34480d1e4aa11a7a2f722de8ccb42984fe5628733b1a1b15576d68f535f507	1678037071000000	1678641871000000	1741713871000000	1836321871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xd0b8f0da815545cbc26784f0fbeb32712b3d811b95153b3a4b233799c91d03ccfa7ffc801f3d8e9ea169a55099cf9789a47c28c89fc5f63ae63e00b8fae3684f	1	0	\\x000000010000000000800003bb1b192ed2ef6bd28534d6457f9f482e34f8f0597104c2f921d8a3449ae9807549a83ccb2e274d647a08f04c683dee887bbbb86c4313421cc2fc120c422c9661cd5adf1b13cc9742dd46fcaf2960eab0ba8510c8f680a42c78e2484d28853909752f83f933b130eaf4383188db837f6befe42f6b1b85738a2d77b4da67d46fb7010001	\\xb3163d55bf5676bdb4fc4343704ca85cde65ede5c5701d87fd13f391203a92602282cd9bac8a9aca34024ea6c56adc081493030de061ff010e656b279357700a	1677432571000000	1678037371000000	1741109371000000	1835717371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xd3a4ee81894f6640597905fd9964dbc16329fbdf656923dd2835ed605adae949af1589920b3efb5893e6e546829ba68d54a8f7b188ea22e0fa37f174df7e3098	1	0	\\x000000010000000000800003a51873b0b520424afd287ed348818813b8299b1d965d5a675569d8aceae47569686873f162230a7dda42502d9b15567db39df9e563d9954f61b6b3eb5c4651f60124164fdb6688c804c9d329af8d649dbdc11744670f55e7a75a35a9e5c9b0eaa1b98ff9c5428fcc2c21897fe1d39be95331b6b24e6d2309db75fa8e5474bfe5010001	\\x0ea2b3a7aa6539d87833e1b782887d11121ddf1ea87649dedba5e6f450f115bb5b57bae36839c45b110bbb3f6f8d2b42e5ff2843f402cf045f007021740e5807	1684082071000000	1684686871000000	1747758871000000	1842366871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xd7786179705dffbdc85a8035ae182a0ab6a42de92528471571ccc1e3b174a6356cef4d80ea285c39d19310e17a577dc5b9bf1f560e1f8f0f82f4c5d011706c58	1	0	\\x000000010000000000800003d8a0cd635cc31b35f9fcc4786373404aa536cb6df3a5eee80f6312a200637af689917541c22bbdc3cc15bc8d5b0c41bc393edc9e6bd7f3fc41db6d451416d9509e8eed87a9074734b4c9924af635c3cdd58e302aa38ee647bfe00a1060bcfd2e34d2b651b6255f36e3de8eed641df8bc3cd6b820a190e3fd62bfde1740b6d2e7010001	\\x518fe1d1c5383ba6f1f29a0058a4a3cbc9e37b779d5cc773cc8be39f5038854c9f39a6a72d0c168a150158b4b675cac539f8cb6d115e7729fa62e2cba7cc6508	1682873071000000	1683477871000000	1746549871000000	1841157871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xd8d02c9a42e39bbc28f465bc34b8f3393883c6dc80e89a1a3033f8baac7e2db8ad122fbf1aa073f34dae2618c72eb4e338982e39411ef01dc21a533f1468a18a	1	0	\\x000000010000000000800003b926882499b55be2674dc6373098e8d261e65c64c924ea1b23dd999d1f6f0c2bd647a3bca3d3de4085576d8e69d91c70f5b0901b604861eed2e3f5ea872d7c9375f8f1d8d0887c2c6f888d5b6d3f8c1cbd305ed052131fa60a07d4e47d485a8fba87fd2ef504ba9a2039dc30255d036271729d94d77a69f32f09fb8adf883265010001	\\x69d12a371a2057433d0180e01d6c014cb56e82a28280dcbadf2a63fde3e42d279a662cd3b1830135165100f61108f8d1af259b02925e5c43b6a774a5c315820d	1673201071000000	1673805871000000	1736877871000000	1831485871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xdc086be50249f9470e80f66b27685e1f1a5832c079c515951e5439f62c6dff652af987d5208da641a07ecc102a3d01fb5b9a6cb4f25cebdae74d8b43125b1c5b	1	0	\\x000000010000000000800003c348331d940466dc5c27fc3e559925084196e91ba9e7a0c3d582e92e2d03f58d38992e8dc1c006c898cb8dcbc1e0d94a109f5b0915b4b8983bd9458a50dd55697d73674d80fa4bc4139a290a688bbc10536b77a2527c826ab5ad518c4a80b90ab59e9837c217476304ec34f3d4d320f57c7a6e8bb964473bcf53d1ff6d7d9db7010001	\\xe0ff6d9b5e50d3360a8efe02e872950649696e4c17b549ebb352f13a5343ecd5248bfb0b8e2d80e1f5ba195edb3e40e4db987fdc4b2678f29ffc47a9b47fb000	1679246071000000	1679850871000000	1742922871000000	1837530871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xdd04b29bb928d998e6e5d85e121488e1361843b0a433db950b7215115e03586693589ef5283d11d6bf4dea6fe1eb1b2e9b66ae98af70b5fcf5a2e10c2a76845e	1	0	\\x000000010000000000800003ddf5d6a9b4e347e0bca738de385fcaa9735e835a584f7bdf4c4b8da5c02dd7303c4fe0a3324e904a1bc53ef576c10a6e6a6700d93f1277810fdc2cd176be3cc2e0f7fa73c304e0c6e8c5b552e3c326f1a3f8dd784e534b6a4a2daadb76a03d89ff49c4e421dcc8fd6d0353c3e5d48d9568c2139336b854a8e7a8c06a3fef2e4d010001	\\xa0a0e7e8085ed8c76fbe789105dcb578e6e2919b4fc89a904b23efe1a4b904be1f8de4e2b803330a7c406da073a93b74d62e515859044ebb09bb1c5327675402	1655066071000000	1655670871000000	1718742871000000	1813350871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
96	\\xe4f007880eda6161f7956d9b723ff6560186b19afd4660095034ac8bacfcbb20eec0120d55e1cb6a5f11e53289597e3f569e07f6f181788a1afc660f70a49d26	1	0	\\x000000010000000000800003d9698422d00702138edc64bcd198d873ba6e671c6e691e4843a7a8e835e85a86ee901baa15c057acaabff8f7bb0c68dd59143ba85f12b7debf0f50fedb544795ae4c704ad7215de4797583c8ab730663688c45b5bbba7d53ba564aea6341179086b6b1033fb76903648efbbba04590c2d2e2a951032d43b87b77ea6be1e3d4c1010001	\\xbbe369b541b5c2d02a4393b7150a532954594cca3cce854d7ce698376184e32d641e1cf171b4519efdea6a83aade6423927b4a40d967c2b620549c5146dd0407	1679246071000000	1679850871000000	1742922871000000	1837530871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xe868c535560e7b6fdf452079d0ee9041c9a28c08e4b50e8bd9f8a441d2858689f40bba07f34e51a8fcba298fc5fe2125846c5cb6f93ce4211517b51c13a414f3	1	0	\\x0000000100000000008000039c75dc90383dd8545c81abd99b441b9800b0e470e247daaf32331d3f991051f5913a7aeb5ccbdfeab8e5a32ae5d5e04cde72b59799a4b0aabceb64054695c60bfb10e729437449a5b81727424f03776772915089eeddf193b0dd49270fe4af083ff69b46c20f65561cfe72f3adb5869efe58ab46e1d6f3d51de919984e8dd619010001	\\x35d43b133a69af91a89f6301426f45b9c00aac9ad464c6798ad75b9a11a2cd44300b6bf0890228e75450c1984b6acbb01bd303e2250061bf83c2c5ae87111b09	1681664071000000	1682268871000000	1745340871000000	1839948871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xeb2490e831d63ee5c9b3b6a3b9efa7285e18e96a0e7acabd72dd57c6b2ee819d7e274e30365d7a1922d91390f3d02e81f40b9a0f3ab571f895752fbc2b90d137	1	0	\\x000000010000000000800003bb51cf4f63d12156daa3af02f6da601e005e228ecc52f2791481a5068dc891ad478291cb0e58d33f08abef0c0c763337eb47843ee6455f574d98511beb936b8d6de4ffaa0f37821933d90058df3abd5698739ecc220f379fedf394be3022126eb35beb48187a153b68859f6731bbb5f9a13d297b4c20527ff4f0aeaa065559ed010001	\\xd0a2efe040927c062239542c4bbcf930f6e6091380932daedec4fc7d545f0397204c73f1c344319b25e25ae3febca0a7cefb6eab3d54d7aedb6b74e12e35bf09	1684082071000000	1684686871000000	1747758871000000	1842366871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xeba420afcc6b7ea32fe10ef794ac8a2dfad7088ef199b60fa11dc9f49c745601a4ff8ed870ed3639c0f433fe4f8a399f1e07f4c01b026680b2bdb62b718ea2e0	1	0	\\x000000010000000000800003c953963c0126eeddd6b868b55601209297a6061f6cbb5edd6129c0260f6a3627dedcf8c782f5059fe1b38b3a385944a32d19b576ddd3c87470127512de8517e19964b13d4d78cc762ebf537701e9e183434aa02e120bde27cfe607d0d1cb80dc71a99dbf73dbb4ee90054a6f4db99d77f95c14d24e2708082ab81b68b119d833010001	\\x08c9806927200c621fd96ee658884192e51799427836557e526cf0e685df54662487ada4d35f07f8ca112a580fc09fb7a476397cb0d30c88baa91d98ae50d205	1681664071000000	1682268871000000	1745340871000000	1839948871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xf1b0892a58895417b3556fdc638dc535617bec031700e15694f6b39452145f7f952bdf0a25f35377c66f0034a1721c74fdcabd17543cdfcbbc8d832e097f7e2c	1	0	\\x000000010000000000800003e5388bd9ec3e233070d548e91a54cba17c8e911171b6fefb0bbcc1020c9a9ae3f24ba1c34139a85d69db04650452c95041ecb9db6348764a445f55382fce41100546fff09f8b384936c7edb1efe98ebe8af6c9ee667d8c0f34fe6e3b4d9d5bc93d7dae9eb97c25a3cf2f9f82a12b970686831787e077d96c4cc0f4833faa3c89010001	\\x388e3dc5db1a5519cb16342c8ef25354299301bef3d82657ece8a1b26f0183119871f944a59914c3b7529e78f0d98c1e6f076e82b85c79083bf71c324a577a04	1655670571000000	1656275371000000	1719347371000000	1813955371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xf2409269b4fde1d3b1dde455ac4b9c545e912b6b6416c7722a3677b2dff04abcebf8f74b9e22ecf981deaac00ba43cdcea4f2e201ba34b10f8359e4b52e02c97	1	0	\\x000000010000000000800003cf96669ec72724f7547c5cf2a66346494d657010207462722ab66c35c5cc71cf1db365ae266fcde27fbe37cde6d375f8cc5334bf382e16f9e0addde6a7aeac5a0f1653d208cebe21f2b4c5deacd767111dc746f1db0820b72a12ead321c608a953a4a133179b35e976c714f9ac903629c65cccd4d9804dbeb0bfcef301d236d5010001	\\x000688d352af45bbb662d930eeefc57a99e90b7582cb8d5ac495d4a2fe739fb3c0e622f557e39f929980668d08e5e08a37042937c9945942ad923dd55ca7e90a	1675619071000000	1676223871000000	1739295871000000	1833903871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xf3d0e43041f343e2c46f47ebe872a08d49efeaade5cbf03c725d09356074354e720e566e7c56ad486e2d2192f03b4520338fdaa635543f2b24fc4392a80d59e8	1	0	\\x0000000100000000008000039cf3e6b747778245492586736f0d561d7185bf10c4eafadc5797531251d7a325b44a5c6bae8c54b40c2b46a1fc5532021ebb1fcb93d0f718506c8b290104567337d9157dfa4dca2ae9abd7ee224bb5941dc355517c30328a164be97183d141c884da11be69790270c036f09324fdb21d28d8377d0793249c9e78366916920e5f010001	\\xcf7d5fff48050bbf57a7e5dc785d0bcf113aed0971345d742db7eff520055302a1722d7c6f0e83cf9716b55f7555bd423647314a52f9e4561e8cebbb6edfad06	1681664071000000	1682268871000000	1745340871000000	1839948871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
103	\\xf6b0348a9b2e51b962b08ed3506d91e9a3c1effe8b00121d6a5785790534de352c7893cc98fa7686d0ee38b236d9cab584bace224f1bf63da34f7f59b7ca4a2f	1	0	\\x000000010000000000800003c791bbd4b7a6679bab9c81e00d27e45a5e6969e749a9a8fc544b094fabf63f69a02a15f75386e11fc552725cd9e0036c481d461a4007665b1fc69b918c9cdc5f97f5001632831d388a7ecafbf05a178e9e385b344f62f65a8ac43494d26fd5efd29fff7c438578e6cf8828e8bbc3131f55c0ae350ce0da80e60a4365bf614c1b010001	\\x65a9116686a5fc38a64acf034522f9bf6ca18cf21599ec3e44056dc2f8df6b29699e189569d5858ce9f927cd9944bf7010eb0ec01b384f69bc40ef4b77caa406	1678037071000000	1678641871000000	1741713871000000	1836321871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xf8202ccc31309add98381f2ec2326bb95545c5378d14815c3248b0123b4ea31849317ba1d12fb6c8942873ec85f65a44177b4e6147ee90f51fafc86f1e7ebc99	1	0	\\x000000010000000000800003bba01a4c07cc1c63823ad2af484a002be098ff2e1bac126c24c96cd82d8957eb09b9cd1776f8648180384584d9c9f6a6dec0a0b15553905af12491d2565d3dc1d0bc111744654f0ea0c1615ae97cbcb0989c59f4ffa3e68495164c35af46a3a30b2548420c20c1ffcf46137897b3c1dff2217f9af20dc971c8168b504a3747c3010001	\\x6aad6c93ca8473475aa9c0c125d49d732ea482ab99da02d5ea11db2288c9a4d14cffa3fa836256270932c7e5d1ef469fae046a279c078c53e617bc0d0096dd0b	1671387571000000	1671992371000000	1735064371000000	1829672371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xf88cad61246fd8191da5379d1b77e3bd07bbd15220289594097e6dcd42c75b39fd646315c00ca8c79289ca5ee4387d9fd7f898335eed1aa590a4cb55fc67fea4	1	0	\\x000000010000000000800003e5f16fefd037a57358e9f6ceba08e6daa6eb2a05c6b46cc74940c1c0fc5f9509fabc0a9a7acd739599b65c06c6544b026ff7bfbd259421a1d08c96a66daa584bff256b6209bb244e3b0638d4f4a92bdce069fc29a4718f321d92934833e58b974f838538eaeb4ad96bb7b79e16c450abdb03038120a0fa2c6eeaa8822bdcbb8b010001	\\x4623e315d9910de5f8e975af3540498a94a353693ac4d3557a0d347e6b500fb2e24c8f5adf9e4133f79eb090063a3462c0110752a66b760e42041028ba565f0c	1656275071000000	1656879871000000	1719951871000000	1814559871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\xfd60f2c0c9afe5203b0042adad0a35537ff39fd99c96113d3d08d03bdca0e0059f5b587919bd18ece7b30afbdec68a74b2540d7de5e0a2f15cad888536880cbb	1	0	\\x000000010000000000800003b74bb8bb4cd0d99856793ada2e35548acbb3f21cb47bae39ae4978c890c1b18334a72474086a7be59ff4452b18308aaf15a7985c845db942fd35f746dc597b69bcf2a9e1344bcf5c0090f97d6d25c703ecd8f4a79e58b4cbe68060c232b839016294d7e9560169383198cf3f01c236eed0817d7d515f0a6e7a6a7b4562c2d0c9010001	\\x071843177ec42b9f4dcf720f047a96c500b1024af0c905ada293888fcb2ea074efd1250591b0cfbfdf1c75184d6b73bc6be5b1a2623e83ebe0fef31905240e05	1674410071000000	1675014871000000	1738086871000000	1832694871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\xfd140e48bd5771f76f6e895323f03c64ff1f5c91ad9dfa5f667d11301447df9f1ba9de4f7417df2495f3b9f5f60c2b1be834956ca7be1a1001c58fff3e49615a	1	0	\\x000000010000000000800003b3a8bd6c919eb18a69307ff316f6802a9cf306e65dcd568bf081d0a071242319a1fc95c9d396a4f8867d44525ec22a648ce0d639160255cfdc48efa3028ddb4e48e01019e2cdbd135d7fdd43e0fac4298407acae6d79001f9836b8b49fec3d43812a4437c96e57c50826c89869aed99f44ccb4bc1e35b98d7a2209b63233e5e1010001	\\x3477f32f6e628a2873a69fdaa64412546ff7c95202717415b9797d0a77974dbed2600704086460bf318c2d10d6c73e308eab517cf5692855cbab7058593a590d	1668969571000000	1669574371000000	1732646371000000	1827254371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
108	\\xff8062baf9fd8cec5230b73d551cafed4da94e24d76917b43197aee670e4919bddf6dafd4a669df3cdcee3009c8132a55e9297c190c7e054b79bf1f87b227acb	1	0	\\x000000010000000000800003b08f72ab3218f8941c37692ef3a9bcc05c32263d8d547ca619db3f2c830f8433897640237129177b38a14e0b5427207389ec143feacf288f8e9097bb84fc749ea10c2dac605af2e3d207c86b5c90c95c6ccf0ff764227babb15714d9952e7b14c7e49859cc1700433be2def1a3c80154bb5dad8001af571d358181bb03f432f7010001	\\xbaa284a901f81f029c4e49ced45d0ccd354d56c7d8f668027979deb3a9390ba49e3f0e7eec4aef357603eeb86ff170a5bb6e1d6f2a702dbf76da4d446ea8c70c	1673201071000000	1673805871000000	1736877871000000	1831485871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x04c97c80f8522317a836c3b902990ec974fb23b8be17c26a79dacc0606f2a3130f5dfb7cdc956c4aeb74395c188c9f7309a8e5df51785c530097dd052bc908e1	1	0	\\x000000010000000000800003c978757664beb508964ce80d1aa5ac7f290f9fb22b29a2997713e338813e8b9ed28150179ec3870ce0bfbe123fccbda67824cb64bea3427cd14f1944b2434763487c97434b1153e4b6a83f681a0a2ef9fee9b8a655aa1abc1086da19cc2acbfa70938194376a3fdcc04b583d17da096c311470900d41f4fb751ca76a04fd43ed010001	\\xb2627d378e0f99feb3cf55b6bace2e19a5a154de575221d9aa6e4ce9c29d4b60919c184fb57ff2e2ab886d878d94b80ffab0d9a5f069fad6f69bfbf1c39c080b	1663529071000000	1664133871000000	1727205871000000	1821813871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
110	\\x04358610f7aea36481dabd232cfde4949139f1536c275f5eb336bbcff68e7e26bc1674d234cd9781868b4add51001f56483bb96917c58bde1f2404c2270afe46	1	0	\\x000000010000000000800003af08fae5c2a2f70a669409c62930e3c2b51e0eb597f887f20eeea85ca026bbb8d760c6d256c27a814679b7effa3ba6108a2785cd4019ab024471bb29df20a1f5d223ad358bde3a7f8e68056c57a2a3dc9c078cd6d5ccd04065dee72c925aee71f121bd7062f7274b70f77703fc6faf8ade2d16d4f8806e4fd4b9af7b94733069010001	\\x1b57611e30181f4a3ad48621ff9144821b8f8b80026bb64025f2597d4e67e7b20f736e19157fa38fbb6eb39f87dbb82f1b71209f431fe91af2370e527ca3a903	1685895571000000	1686500371000000	1749572371000000	1844180371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
111	\\x07459b24b0b2ba557deca591f55a34a240ca8a8555787aae48b4a21110bb14548f1aa36b880252d6d15e1db591b99b60f29b296511d027e27f40ae1dd6451bfd	1	0	\\x000000010000000000800003cdf653540062d25175b89ad7024ab32ae021d789b0fa62e9fdb9aab354ad2e7fba686befbf3c471d1286a7f7679a0f132add26df455e1f13b48c74fa03df163a2c189c736767c567547c2a5e9f512b263f61635db167acf909eb26c6df65211d338f2e53f50383d81ea4a3049cc09ac7d5ec1e2ac58a305f31d4d8502dc484d3010001	\\xfe0595be308cf313a68f53c743e1a99bbc403fed4c264674b95f9f758194215e01a0e8ca823111c407b2e288d5388d2fbfd11217e3407539108877f2db88c907	1661111071000000	1661715871000000	1724787871000000	1819395871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x08190416b873c2d59b53bec250f8cf04b3cdd7723d1270368bdea7dc4008c63a5dbedc2bbbca172d2d2db5b889854bd33c94526352f78725d38a47a21bf0b7e6	1	0	\\x000000010000000000800003c1004a3bb9a8f68d7cd25b60f399429ba368ae15c49f0c1d5e6b56bff68bd66cbbf5b23ad2b5a2247c86fd987dbae309fe226b806282b63d009b691ff7ed3b37ea34a263d3a5327082879f9cbc287c33d4638cc6c09fcc7e66c6ee26d53cfd3a6299950a4061a1d042ea2bd1f604ba05fcfba13c66cb68ee28d272af4567fddd010001	\\xccafe476f83e73b3d3603dba81dce3e34ed63c746fd1b90b0dc5b691afbd284d532aa5159e9fc57da4b5a043161731a8ba23f2abc40c302d6964de84f49f0406	1662924571000000	1663529371000000	1726601371000000	1821209371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x0bb5fde48582052dbac724108b9da1e72381dff2665b46c41409e31be665380e564760923609156f1026c9ee7c89bdef162a3c350ae532740b02213de91db565	1	0	\\x000000010000000000800003d501f9037ae248c3bdf52c27d4e708cd99f08b406a3cca33f1ba3f37bfe2bfebd6a1d42211aa0d067237d9680dd893af8b1510b506c2deaa4dd57f964688a8920ac5a1b6ab1421e86b2738259017cf1dacaa3415005e17e1c0fb27c41d551f9f70c310f4e534bc0e696f30867b991a3da9aea9cda149850c1907975463ad39cd010001	\\x5f80d446ddc4d1864cba78e0c4fd3575f24ecaad05b373022b144e07a9909315a7d4bd2fb140ac45250248964766c5f49e7c1c51d72cc753329394d0433f4205	1667156071000000	1667760871000000	1730832871000000	1825440871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x0c19b07521eb22a4a0ba46bbd4b52ad90da77f800a3697e91f2982e2055eb9349cc06a2335e09a2da376fe8e8df66b3d856a0a705d3b39c4e9896aae09258a36	1	0	\\x000000010000000000800003b36655053257f041c45d9530f60aa4e4b53c4ac4369d86444e791be3782e54d2455323e48a3b95dac25cb48333b560f84ee796164c55a6cbeaff0094f79b95d540b0101ec64b491fe8ece61c892fa85ade66157b7ba0379192389493ba8e273d9df8f3c9828e20a74dd5515f6279cd7c36ec79c27dec76b1e158ab4a0374f1ad010001	\\xeb83352ce8ff0d5ac02dba4b507ba48fbdafa6b57db43b80b877131c39e803aadc152edccb88bdb525c72cb4e29d02639ed4ea72d9ddf922afe51ca6e73bb20d	1667156071000000	1667760871000000	1730832871000000	1825440871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x127501f0df86e30472dcd6505882cb154154ef7c91a81d8dafddba3adfaec1fde566edb058a90796b6a885eed305efb5b047a8a9f453d9eb29a3a359a850172d	1	0	\\x000000010000000000800003c38bb30bcabf1aaf3f0ddf8412c4fab82770fd1e5b1e5e42c9ea696312b6fce4f260c04cc02b800952fabc302faf7b33a7511e7127f0ecd9db29f0dce8169a4b53ac97b28163d183d5fb6ba926f7e63e17bbe501530b0236f52e22f6b6cc3df3b62bdb06b11ba91960cf9d5b3e65e4eda07933492fa4c515a664d7e57383323d010001	\\x801ebe1af12a668bd6fb9c5984649c7f1e6a173598930345a3931d58b83008f1c17426a7694734beb2f0476bcca348cd2bfa1cfb8f7801126c0d0853cccc5d00	1659902071000000	1660506871000000	1723578871000000	1818186871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x13197410283a451c358836d9d065347d2f7a1289eb1ae2164ae9e82ff242da7a8e4c0d6b8b6f96419f2733c84ed343876d10efd8d10100daa7494fca8e8e3f02	1	0	\\x000000010000000000800003b7b28b5cd655badfb61a2f66c8868df9f400f1b46b8a49b6eab36937574eb5dc9cdd2af51828de995d568a709b719c0703dadabe302364978963430d5f81a44c33b89dfe969cdf01fcf4d9f45188774b55c36a5a524f47f8c4f92e4483f4ef45a015f081f7e26c5637348e05f2922d0a1134a5ca6f5a9cba1e25754cabd98449010001	\\x3e3b55af7aa14cf6e2f5d57edb8e5fc9829726501fcc7a81a11f555f82407e790f8bb8e8dce25c08314fb0e9df14f357e2973b36cf81778667867fe1f9f4e706	1673805571000000	1674410371000000	1737482371000000	1832090371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x14cd4a476d2bd8a4bd2479adc1c696dd7809535fb6e384b0a47a7b89698434a1d64e79c4242ec40f81f6a6db7078953582b21f77449191b39db3c30856415d52	1	0	\\x000000010000000000800003b2ea27ebde2a1e661efdba61449fb4f5b2617c05df794ae5c487799861defa9f6e3f26033345f911a61a4225d5d5e13833fe0801312afb6aeba97c8a01cd668ae0d9f87c4c82550df6488106c265b11cef3c4e3e5f355a759dbacd9ade18a2005f961c1a0c6bd71644adff8779dd3c2795227ca82c6706f98257129e7843e86b010001	\\x074996b205637987025379a62bd25530b5acfc1a482a4c86e74f65cc2e22a93c83250456d5cc3ff61dcea1c099403d690aca4dc989c62360b2ec0db3198ee701	1680455071000000	1681059871000000	1744131871000000	1838739871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
118	\\x19c5b17ecb3c27305bc0a3b3df2415c2ea1e54ac91b35e0895324c1c58ae04da99677b0f08cad731c1f6411a0f2a4964b4c418b85ce07a0f41601b1905e77ffb	1	0	\\x000000010000000000800003c78c0d5cb55dd0e93f3ebb7af0432631a7d2c3e633ebcb68f607fd121fa382e79d3e9b9457cb647506e2ddc1e853208c48295cd4e21b1eb53bc361501c219346d05c5f21c315490076bef1d55c56c72b846221a3c772a5c8e68f9ed62350a5a778668ceabd50cfee66c878a2b283879335ed67292bd4261730997054d247ea97010001	\\xc6b5185f73d51f6d2e95674b85616b7715e13c5c55e2b66b774e9295955b7a52097b651cb1d7a60e5b216f0ad9ed7f7b7c79be8cc43c79ba0c027431bed18e0f	1675014571000000	1675619371000000	1738691371000000	1833299371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
119	\\x1d0de369e1cedfaf99385cbdea7af9ec9475f76920f6ef0d0d0f952b366161e98458971e0d71b8c0505f1a933710f8d021c4821b928d65655c8284e1f846cf59	1	0	\\x000000010000000000800003b0b27d47b85f045eeb62549d642f02ce75b0fb3c9a92ff15fbadb779f15261806de44ee7b87ba3183a98fc4874b25eb8b524595c9120655c6e07ac374cbb27904d93670ed72901f8209c81654c0e20422a931d0c41607823a2d5d677da39ade7dea281e2a5efb586f87c5e4a726328a93e1e332fbe72f8a666acba8bde59cce7010001	\\xf697cbbf83053e06418b90da5db2ef29d370e72978364ef609b294143138ae8966ce8511587f61239f0ce9c97ebf337f5b16ec8111c0fdd134148f09145ca40d	1668365071000000	1668969871000000	1732041871000000	1826649871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\x1e49352fdf24818cdf0111ecc5606b23893a61bced1d506d6423aa3ae851036b0ec63afb854e6bf2d757ee80e7bee63df169b81f1d49f6fd7f6dd4364360e33c	1	0	\\x000000010000000000800003de5aa667e5c91d5a5e723b551f3d16093327dbf233233f882d350eaea94941d8de33919110b1f8eab9bee98e5a15e726e303d811678497724b681acc3b7ee732b432660bb011dc991a3e2c1b98b1788dd8049e49aa6e84a762ab6b8714fa46d233389e574747bcb6f5268ada23c28afd4d09ab1da6c26a948074ff9fcc4eeaf5010001	\\x584a2757c09005b3c5c3e32dc468961ded29df75f546024593ff4ee8f2142aabee24724c25f775c19b1393098c036dac66915bb0c0b0b55494179c3d2e457402	1677432571000000	1678037371000000	1741109371000000	1835717371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x1ff14ab3aa7c2df7ac6ddc90faf9fd48b0e93a43a3a645c09e8e1168c0f20756436eb004bcd638233a902f685d57ac8415585694d41d63ca9fb22265befed52c	1	0	\\x000000010000000000800003d24a20db3a2d7254c34606eda85e096c238ffe0e40440fc4e165ce3c5bf2a1b72594f79dd72b14f0f427383f6dba1e460f4628418e7d0749d439b61690774423ce20aa1e1c202c4531ff00e2d642e7bfd9e9b4e17b9f2f31b1369a926210cb237a9c21ab129b1f146882e6018ba457139354c88ceaf6bb259c1c4a090c4e71ed010001	\\x6cd40ee61d25ac3c1d0e5fd78de2888a71ec0b92e3d5a59dabbc2acd256fa83b708e8d7634b420dfbe38f1accbd084a4b8b185667b0a52affc60608f001e0d08	1675014571000000	1675619371000000	1738691371000000	1833299371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x21c5bbe9c4c694181887aceabd3fd95227d7218ce4a2ea00b65f39d09a6d2340cfc947d3e47e01915f9baa2d0cee1803e00f2b364461db5480f8748bfb6cc540	1	0	\\x000000010000000000800003b69a599a151f41ae4af8817b30068681dff2baf57af7a21807f802321b4a648b0a26b6443214cfce0e9f3b115f5b0156080bf2b2aae3110546cd83bf990144e70991940c00d1c49d8a120ae437bc38ba896c6624aead6b8165e2dbdbd2e3ca6d73d154f9fad088d9d48593623500cedc497e5e8f63b99bdb048c219201fe09eb010001	\\xc0fde5f7886626e17c3a505aed4ca37fff93326244bb51eb6d33dc089f12f9084cf2802afb73bb8b93fb35e5201fff1d748285dee0fe3b7988c4a82baf5f3100	1665342571000000	1665947371000000	1729019371000000	1823627371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x290ddeb3233c7e64e1ac951639a01fba282741665e6773515294a631f9edf60ee8c84b95ae2fec55c61596010253d24c9b33537064d12d4c0f5f7f8e89a7f01b	1	0	\\x000000010000000000800003c9c697b951355e0dc84a36f00ef0f6341f23efc671eb915f9b4ac1ae2ef998d3cbca7965524f6fa058123f816bff425ac463e3623d5fa4d144f80f7a06aa136663081af156b024ba0bb480f19cb6b286fa630c54d6cf150699f19b72cbc0d9a219b6fe54767de3ba30b1d7a6ccdc64e605946c30ba42f5b7857cff891d487125010001	\\x6975b076d6d7898fcaf36de661b39c3da4a3ca007f928720633b61fd0f071028fd004836b4ad08424edd89d14d795f3d8770a25c0cdb8b3dd0330ff3e7c6c40e	1678037071000000	1678641871000000	1741713871000000	1836321871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x2969297bbe5aaa641d097d65fb3fc2c608de18531c6ab975d9435366ac4319c4b8db44a1f53b02a06015841580c3744f742aac13113f5be5b8debfadac068595	1	0	\\x000000010000000000800003b2521132a49cc5f2798a67903685042b7a000a4682a3ddb649115d68ae83297f67364c5b69cd8aa00a35f55cda3dcd1f3fa028cd6597295e1fd26da8919d1c38a5ee6815a3dba7351d30577e390f68c9cc2ad152d853420c3e65cfed469b8b4e93083d0425f3846ce2bbe69912b7160ab169f3ae0c0279fd7703380072069b4d010001	\\xfe68fae1c86fb1e13070d2439f499c36bf52af5973ef3cc9a521b0c51e0139f7334c3d2ecba4616ac5cbcc11c4743ade5e017c3b5160d988999041162b93b900	1661111071000000	1661715871000000	1724787871000000	1819395871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x2dc9f1c2b4bffa5ab339530b498fad8da836648063605a501e8ff7077f33cbd952bf69426edf4ee325d576d740be2a45e9bceb7768faf4d303f0f31faf32a9f2	1	0	\\x000000010000000000800003f1227324aa194eb58266a99bf5f54e90e11a2de51d37a3a0b1e1ac60ac874d8cb97c891b4d1f2cfeaa1e15da0b6de06be3fba5cf11348e87ba62971379d5f6a80994e047a6e1c1decb30b9cf9ac8be0ce08d82c204f7cfc5c0dab0fa77f510154d8db1c3dcfe6a643383653106cad5aa19698cec57285295516f9b0e74b41a81010001	\\xc91483a74db1b1f9c7f33d980f28f915776fb8d7ff81bd083834286022e6b96196c1063727a2f5aba6233df2897672647a7ada1d5cd460ce23b826862b37780b	1662320071000000	1662924871000000	1725996871000000	1820604871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x31ad748e8ed3e7af5a5b3459cf454efb7492a61263c069a23fc1dd5c31e39546b29bcfb6a28d95184ddb74df4ecd992f2238c39ca03e9a5ee3c71a28c23cc729	1	0	\\x000000010000000000800003ac337dab7554fcb5c9a566451e7e9a02e2d6a01c7be41daadcb15bc7464797f43c005480154d0214bfdf42a802fcd694573d0cd099725091a4d4a569ceaf4d5342741f099e8cd3afd65ac1b23aad643252c9c14819c5ffd04a99ede486ad59346a36fe86f55577616f0e30aa9a918c846d1dea18ab6c1aacb8c22d90b631a5e7010001	\\x7d5be7aeb4a90512976cab83a2488221781fe7e444aea9f0561ca36f0d8f9bd2be7a527c2a20a199105f9e111f0331d170c94620631f7cdc5fce18e0d6ec4505	1673201071000000	1673805871000000	1736877871000000	1831485871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x32f5dd4bd72daf7e938c9990959c0fbf05ef094b299aa98a69deb81ba2302bb407594c6a2fd30b637688dffc772f5e8c6247c10c96c33d364d144aba905884ad	1	0	\\x000000010000000000800003b79e1e2d8a763f9b2cf5e1c529291ed7c170adfd410c2d0df64fed220115641f9484b144d30e8100a1314241673b5d20c9f60e09f8940095834c190c69baaabb9920b5a69a54caf8eca682524f07bbea57786fe0a649b3e0f7c567bb00ba8896e3d13c63c2f8aeb4eae04a7cd54de9bbaff581b83250cccabc3b5254a400eb6b010001	\\x9ce84db1c13398491bb3294a23c7f2d9e11a5d2fec5f10f7cc6940a2e2ef06051cf7ef0c37866e5ac5df501710834737945a38636482b40e37b4fc8275460e0a	1658693071000000	1659297871000000	1722369871000000	1816977871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x39f15e779ba9ead00b8dc79843fdbc4637f1cf2a5e5fbfafe727c8a738c5b21681cc8c8db0fcdcbaeb10a3f875e04d1e3f58dda57c86291e52bd4b9ad68ca521	1	0	\\x000000010000000000800003d7117c7dbe35444f15f771c840e4ca50869c845c039efdef2c0f3b875f8cb139b472ee8caf0f8661e89c4a246f15e31c3487f3cde314fd92e722fdc6f4b9c2dac7418fc7d2bbf6869329059a1151b1f7ca2d35f14a85cb4760d4a9d788065ce647b7969efe8a10e590db6b6226a9e6e10db4b7030609d24ca1ecfe5626528063010001	\\x6643025114ebf872b94eb793b0bd3c9264af26b3dd3d8d05eb8c81206c83b4f7e1b1db16b384b34e7a1682bf1d7a20c3824a1f154400cc94bab7ac568b03cc0b	1678037071000000	1678641871000000	1741713871000000	1836321871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x3c357d7d281a4971f7a07603f3cc7cc973f4fadbed8157d5d8966ed86fd3e800616700830b28df7e3389b3e6141fd5f0b814c75141fb813242310fda88f9da25	1	0	\\x000000010000000000800003d9132e5e1e770c7369609346da78198c86167fd4b3a6c982d99947a4faa2a9ad08b00eaa765ecbe559751eddc72a3c1db2753c7afa49615c5732c420faae2eecb9d3f610aec9b636df87eeab938dfc4a21ddb85ce145db330aeb53d249e07903e2fc5a7ddc40294ff47bdccf9c4834f2206e19e249192dea6a123c5520ea787d010001	\\x1697fb23d99e63f11f688fa88c69019214fea576e0b2216bb9a9b97ca06c12582e6d6b670d22978cbef3424cb3f8d64ee5a41edf07656df6bad6fe30e75dfd03	1684082071000000	1684686871000000	1747758871000000	1842366871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
130	\\x42b1a84bd10d4c0a44cf64471b8412fbca337f792bc859683864397bbcd918fd111c1321053ca64df9cf4c1d60bff6a2ec8fa2b54d343ac4b67fd840767beda4	1	0	\\x000000010000000000800003b916f78cf402c635c36dafb606fb71fca7c3611ba7b575433961c2302beb1cb992d872e25abb56195657c66d61152e9a6a8893a917127ff61b4bc25cd89d08d6558aaea0f782caf076db626dbbc1988db3336a190193b8f471898c42615edb75ee6ca004383aef430722c01698522a7ff40e4466da564eb295cf5c04d044f719010001	\\x951017a514444935cf1e1e8aeb06a65b71720ac793bc6234db74f034428afdbbe1e425a8bcd5536642832cc858d3f13a19912426b4629166d0b754fcfcaa7509	1661111071000000	1661715871000000	1724787871000000	1819395871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x431d8d1c922e3c1979ae2da5dc69e3940942ddd905d53420b547c40168290cd3577811c9269b211f0bda295e93a4e74e847b9e43cc44f4eb2c312b174fc9a219	1	0	\\x000000010000000000800003d8547ac9c2bc5a70f81b66ef3e938cab2b43900e885cb09098a27f36fe013f97956b61429a99828ae20b8d07c85033af4e5d80a1ea27ea357734c3709ff6acfcd1feee09b25bea26cfccc9c296026a463934903223aff7343614ef339595d6ce680f512023e9d39afffd1c3a94381670667b5615a5c006c2c452aa12c99dd499010001	\\x0daa6dffc473600cf37a66ec22afa08086bbb00498e1fb1ed5105f6818784e08336410ec12dca43d41026de1857b44284e9f0c8c2944819202313c486dbc5c09	1675014571000000	1675619371000000	1738691371000000	1833299371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
132	\\x44996ebd53b15f38825dfe3da15579494c8ee2d787b2704c1b2107d639ac2c9a930076fb0b33eb4001d7bacc3d86184142e706415f45a9837e7d4bbe2002c202	1	0	\\x000000010000000000800003b3e49cb4ff4c04096b69dfb76474e251b418024c75e9032110be04495c4ef872766303ebbd579532464f808efd5421f20dc1ad00919c32eb702b73f8edd9d96cf0e9c293d29fbbe3864330f9ce5ff2ab466327d3c349db49dd949d4a6ac0997e03d4e5c1629818cc4bb12b59326777e85b763b16bdbe8e45831ef0e69ff00ee3010001	\\x25b0606404df6e9ea0bc4df97a8052126b7019e81db8aae26f332dd5fbaa19ee89ae44cf4a57ed26a31fa2527bb6b20bef8872308afc432aa480a7629d568908	1679850571000000	1680455371000000	1743527371000000	1838135371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x4575c1f43f9fc311a288ad0b44b7cc9e194333a8bb46585d00bdac135a7f39cd44710df5edceb3593525aa2b0014b3d3a04ee08c34396584363c71cb4cc375a2	1	0	\\x0000000100000000008000039e2c84409f31fffe07445b43f8d268ba1e3221a88941c80bc5c843b74f2495e2fac3f0095134ed91b2fe44899128cda50d7d7e8410a6562fa9a912be567fb899d2fd8a6950267ecf6a7d3a90f3688da242717cf2356d8dd973ff40a01df077c0db6f3f11b1a08a60a9ca2aab9dc4129e92de12185cb7b2f8796f94e4fa964a93010001	\\x9eec3f4d433fdb75f4a6d4908a8630e2130e487e51dec08bd7a4fc0516167381992d5375fa576b0c7cd2820185074704de21f169acab20b1040efd46544f7a04	1664133571000000	1664738371000000	1727810371000000	1822418371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x47c5602607689950164705129c031d5446b69e41d1a1f5f44081791863aa2fb3eaf9e8cabaa75da5c0a7882f53d6fd37522eae38ed108f01e58aa63d84f6c9ae	1	0	\\x000000010000000000800003a8b9001abf901b26f648927df46c3f4a7dbddb34bbc151629f250a9d58e1f34de224228d0652d5d71ae53b5009d25295392a07dc4381987c08125e399e8b0a6bf00b8f89eb2f591193b1f56bc85f91162b8743f387c29f6b8081d9cbe86c74f3a90a5e482c950740beb4736e0242207de2b5e2053ab2d2d14d82331ec32cfa13010001	\\x11d1e81f4eff9664eab64cb7edab9b19622e83429d20d2f93eb6f0dd333804cb67db1b833fd39f6892da918800b7bcaa92c61cb3da91f1890c4eb5e9c086710e	1667760571000000	1668365371000000	1731437371000000	1826045371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x4d0120b4b3148a9894960309b77239d6628db248886407a1fd1a4020bd1089a72c5672517958b197cd651e61669d2ac32093a62caf2afb6a7ff667e72d8e10a7	1	0	\\x00000001000000000080000399ad297ab181454804c3363d4a48d30372b806f63ad1e5ac1090952f5575ac9c701a8333e1e7f429e73426c15970a1d7db27513e45065136c29163b2e811688dd71b7f18d2743287745535b9283404d177255a56cd96cbd1bd07cd375cb55ae4b9756ef8e1ed6e6e0d76f32f1f3f4a69d1fea3045a2c7028877e9500824c54a3010001	\\x3425b5f8c820aff6b6c249341f1f0cf2e553a6dc27feded597123dfa32836a7b214eae7c9c12c229e9b02e6042f5a05c63b82ee4d6db1a54ff51591128c39008	1658088571000000	1658693371000000	1721765371000000	1816373371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x50f107e594a2390def79d4ccd9feb5642c9478b61afe974527f67bbdb854ce4928bfaf0c99304f49a6b0cf37c499952f7a2d70df3257ea45ec38336eb5180941	1	0	\\x000000010000000000800003c75dc89bfd7b31546722e4c77347707ccb2ef7592de12d25cf85aacfc94f56d3e921cd4f72337e97564cd07d94b8999c565aada5f38285e0b155d7440fca8be03ad24e0062301ac04343b0b2fa21c4525a0fce46661bc58cda712c0f071ee56b03eb8f9fe446efea6d54f1bec34f6d18c82bfae10517f72c6f4680fbfa2b7a59010001	\\x3ae7d6afde7ef43cab5cd4cbbbb4e29580c99d3d5b1aec554430c6abf770acc5e3097055993c82b9a01291e7962e5e667cfd08a12968f099ac9d839cbee12b0e	1678641571000000	1679246371000000	1742318371000000	1836926371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x50917c13a862a2405de57e443b90a628ee135a47b502258f827e31b80647daf85ea5b806830c55f72575b6918ff20b76f154a954d8bc6c9ec27f8b3ac4782ac3	1	0	\\x000000010000000000800003c2145b44ac1c89393ee67055650126c9fb0db0685c4e1f2c75892a3ba263f8fbec019a26cccc60bbad457785bb0360e4ebe9f403e215cf282d2c54d4ef712a1880ff32f90f6861b9199d948b039dacc18f8cdd23f3398f4e52c52112b1bdb04454d70d3559198d2e24227989425f3f9a533c77fa25edaa5243f1d6b588fc1e35010001	\\xc1d31eb91a110b8b7e0c2809bd23990e6f74a7d59dbb2f0152c854dda907f5ce19781b30a8f81df792fb45027b2b7255d9368b4e7b7a3b81d08ee11708025505	1670783071000000	1671387871000000	1734459871000000	1829067871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x5169893b6649dc906bc8930808d42e9a7194fcfa4a19048d799b62e66ac78ef20ae5c89f010aa4af9731f77dd0423ce1e6531c65b1ae27438adbb312825e1186	1	0	\\x000000010000000000800003bc994c01037d99026f1b1fc91a04ea2f0289acd2547fba99342f4622e48385d44fe4cf58784168835752081d791ba19ec0a010e442d1e5ab8178df5f62df6bab257fca861405da2accb9ac76563cb6d9a7937be3f9da7b5aaaf33375f2a295fd74da411cf21e5405e7da4c7235973c183f8fc0e6206956f2286b3c69a7b43a19010001	\\x2824a4ea2e6c5a9203d6b9b6736b4386ecc606d5b56d3040a075a4a7693252dbb0dba44583e5aefb6b18ac80ee37e48a683c3a88e3b49ee20fb735c966f70008	1682268571000000	1682873371000000	1745945371000000	1840553371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
139	\\x54712eaadbb7bd21581cbf1f4dbab9d13883ea8619ed85c835ad9648a203fbe5061462296879a73168622cf7132e28709e1f14e172d894a12dfac8e446c63204	1	0	\\x000000010000000000800003b9dcb9beeba332a3ce78331a10e0c7bd07f624889dedec43e53a402ef8fc237c28f2389aa7776aafcdb0c64cb5bc489eaaeeba99984e5dfc5b84a0166be214cc0958df301e1cbbfe97ad96aba9d32e23e622d15e35093768e4a6cedf359896ae903eed483ae0d333d293fb093114f84af1d038bd0b279a42fda91ddf1276bc11010001	\\x0e725f5a046a27b5fbe5e558260d86fbab4b842fdd7e0244b0ad688f15247602a7b6014b1e311dfac8556c4f2415b4c7d005bc23bea292cb83ac59e0b294c107	1663529071000000	1664133871000000	1727205871000000	1821813871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
140	\\x550d467ba3930cfe3c94a7aa9076c44b315d18b719d1edfda2c8610cecf58cffdf8542c91bb9a8e6f069059cb93625cae96e1aad30a2aa5df493cc193dc747b8	1	0	\\x000000010000000000800003ccd5e9bfc5a3f9a157e6d1cdba0323a414b01e9b4e982c2d798026b361aa5c23382a08c2b0fe8c0b59772f11eb17bfc9f194dbfe4caf0de727d0102f56879e1fa000f217b167bc50b2d57adc3534b391537724eee56ec7bc916964a91b79e45303a40cd19e2640ac534b9398f99eb0be56b7ea10f425dfc3ffa7e99707b5b4e7010001	\\x961332659c652d5832de01a67862c1846bd6380407e244a04184dc273933b7795db7e556765a49ba373fe1ca968a077c973d076ff167b507cb26169c7070450d	1676828071000000	1677432871000000	1740504871000000	1835112871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
141	\\x5895fdeaae5da1e9f1ec7abdd3481afc9c42b8646648ecd967434150dc91b015995d135c1dda4857d990f18beccd60176992faa2648d5a461feabafead0ee85e	1	0	\\x000000010000000000800003dcda87984c045cbff5a4127dc74ff8682c24a92e78cc9e4210d6d9382813682571d0bebc2f30b07cd3dee1caaf1cb797669e25a6f57172007de4968c75b16dbc99c1ef0b66786dee7f202c581a2e4c89fb9d6be16cf9f20f77010685c037d36ae773c406e69fb42ad5ed9ab2359655b69f0b5aa62d1456ccc3bc952bb20a3333010001	\\xc9ac590d2513e1a857d9100515c611906bd527b5de91460f30ccb249aaed58b0bac5759466c35b361a061ef582d35d891be3892be9ad29fd7b76820ee95f020d	1683477571000000	1684082371000000	1747154371000000	1841762371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x5965cc79c908e0d76184a1c10ec49f0609ece7f1e6adf70bd56247b8cfe512ed21579f9be26d1d9cf76e8e9d80e3f499073ce889b195b7a7979e678bcc699a14	1	0	\\x000000010000000000800003e36cc4208ea7906e4367276579587a10be95087037568d2b6f9074d1f7c48fac079cb9b207f9e2451e176b23b76dd64fa1952686d3ecc89728284e86669a3979441130d099968d099f939a2c618924200bef70072e5d5647d8df677bb0d22aff9e7b41fe4463bc81a87a07d2e6944acd60c09d1af7d6f0c7b03b4d38d36fdb85010001	\\x315b414bb7de51b66e713456817ee7b0edd290ac41725387b1088ffd196b6eafa68650008d098dd08d3225034bc9b620b711ad14dae47b8fb2f39ef1c7f3410e	1658088571000000	1658693371000000	1721765371000000	1816373371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x5eb148f205acd743026c35aca9fc88bdcaa3f9135973a5c9e01b79ed3ab719a1a28a4b01e161e6617f8601405f8fff7f86ae1f57f3e2af357a6eca83e7c5f690	1	0	\\x000000010000000000800003ca5756961f2aef2ad526e7c2a03e8948e66413356c4e8be5765b3f8953c7f944daa1f83a8a4ee4563c9063b9c29ce735883e4b6ee831730f2b4e92699fecf669f528f27b2dcc666dcf145a2bde6154f0a02b2d055b4d411a595f5c8f6613152f4be979abea5c814a6004a55c3969f2a3cba076eced4731804d77a6828421297b010001	\\x3984d16c4dd9ff50ed2c4af8475dc739bf31404e78271dce9e1af3507cb57becefcecc30b859c0d1468d1c1b88fb451029316f6dc96c00b6218eaf869cb7380f	1671387571000000	1671992371000000	1735064371000000	1829672371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x5ed142fe5c8d6d78784b35320a9888a706d78e35707fab8faa4545e6546ae2254eef03f9ff9706b8fb095fd75149fe9974768a8c2f5acc5f974f8bef23da73b4	1	0	\\x000000010000000000800003a7683f426c89fe59adf01a02a5a6196ba3b3b71bac3e5bec2d8487576b8c81c4291ef8b4ffd7dc75a21d8bd3847830232fadc0d652826fa5ad572c3d0701fbbb147f50be18129ca57e940a26f51ca50c9c36be10e4451fa995c5072ac776997c92500e0f23e3708828de42919c19ce5b6e942bfba25d9b8c59bc3d0f91505f97010001	\\xdaac127b29b5d382ff9ffebbfc3b68bbcaaf09a8c54701d86796ed2b03a56d00357069ede33dc7cbde3b45b3dc52c8a74ef300d7fa7d7211cee89069da87360e	1675619071000000	1676223871000000	1739295871000000	1833903871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
145	\\x5f89efac548fa00db81b8cc8e5cc7368a33748f35007e23c628cd2d84ad510ca2928ab073fb2594591e2b20903c01a1641e12888b9bb1af251fde8c98032034a	1	0	\\x000000010000000000800003cbb6124cba71daabd7f3fa0da6d11afd8a672f31100bfff1999400382a179be6daf3a3bce01b0a0015b6188b56bb65eeb7b4afbd5b3071543a9ecca117e9358b25e6b4798fb968efabdd046dbcd274578a86ffcc766b95b28231035f21276f6dac72642f9ec90bb130e2e55d28eaa814500f9d26ccec2f1457c509d03b9d9277010001	\\x819eeb50ad8722ec968bbc53d8a1183b6ba666f2c2b6323726f57457fb548451d7c396dde23a2fef153a5beb1df5cec2b207b874292b6f42200bb8c21f4e920d	1680455071000000	1681059871000000	1744131871000000	1838739871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x61752458bc2a9055a071b98872d701be75021ccb9e95abd1f459ddf9c967ba007f374ea9324dbf2c8b15eca66a3e676de5e389854d12483a112785e30dd96759	1	0	\\x000000010000000000800003d1cd90679dac79253a0f5a7e3e6c8a62c7a617b1d37e9f463c7b0619544d78270fcf65c82ca4a77e305f34ed6401ae157975966ba5c1e9a1ee0a26aa66cf6aed2eb37ae0bd8e852b6744802bc5004dc5263ca48e1593707f685e27f2bd3927ad45899252a0026a754c62e5eaa764e1975d14483fe070e59ea27a195902d29725010001	\\x8835b0a6eaa22854573a1a6911892ca0105d9911b248a25acf8932346ffbfedc52d79cbcfbf3f664ff427a909ab256591daa85ba70442b3f3b51d241259a7e02	1685895571000000	1686500371000000	1749572371000000	1844180371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x632973e16e7e27c09c33cde743395e8888477a462d5b1e029436f94466b0cf31535c31d66c30315bca1a91bad6f4f8fd4cbdba3a28723a1b6eaa590a7ff378aa	1	0	\\x000000010000000000800003f600845d82c8554f9d072143db767e8f212040425c694bce1d041cfc602515de1e88d09601fc0ebe8b82b940dc66bf04398ada834d8aeef68be9c50eff0bf14fa2e8ea427c060c186163feeb4ac62e72be74272a49e244c21af7fcceb58c4634acf510211b6df77134709fa3797dcc1d915cf9cf6ea75edcc5cbfdcac6057427010001	\\x4f8e4149736287c4083c3876a787c51ba350d45bc261cd77a9112b7a4cb8017f4af4d4f43e01e684558775396b8c20611c7ef972ab5d9bb0baf905656bc46e06	1663529071000000	1664133871000000	1727205871000000	1821813871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
148	\\x65753b58e4d15c4d5f3e53a3cd662aa9c9a8c83050a5581ad53c9b525b9ac83048b722c91ad79d36110d29be157c6a9bd4e7c75d3971ff394ea2b7272b429c8e	1	0	\\x000000010000000000800003a392584422e85e41b7eaac69e13e89f651d6c57574581c4f6f4e26eac29faa21dcf929aa8683be27915b92979a8dc8f08ec422b4a247abad4fa3c56e69816b8164f9ddab34060c0b2a590581af572d7221d960e18f53a97c581b2ddf31ad7e6ac766e0bafd3fb3b818558e28c20447cefd918077273d4450718c4c588e100e21010001	\\xd24919f85feb00934c809fddba9ad68847e9fcbf6f739e4437008ac8ac5ea42d86356997192b91ede6c5bad88eb10a1ffd71102a42678d8e62e59949275edf0a	1661715571000000	1662320371000000	1725392371000000	1820000371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x662982bb7b3379768ee767d3767accc7d0fec089e1e5afc37e49810d2e3818fc1a07f08dc55722e5c23b96f5209eddbde4f5dd10e7d426a4044e2274a101ad6e	1	0	\\x000000010000000000800003a754c7bbcc162fb4db10b7d64576f1412e849d9c20d96637465efc54d4d5bd457de44eaebc18418d7f89d92c046eb36262f4b627822b684c473dd4dbcc2324543cfb4509bff46effb04f49c24cb114cf42ffb6e32f53ac9c0cb21c4419ac74b7ed453b40adf6fb13fad7b65f50a347845449aaa61800dfa68708ee906deb9bed010001	\\x50ecd39828ca05c420e45ff60c83316ca8854ea2053d9efa99d74ff3d2cc45c4ffdea0f8412cf9a8cbbd7f86cfbbab7a06dbf619366713f9b213389181841204	1673805571000000	1674410371000000	1737482371000000	1832090371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
150	\\x67292e343adfe5b37d3bd562bf461e21c6c66748a001c429f8628afc74566fb7cc655ec9f2ab231e82f8c7d21d41d856520dc91f8fb79c45aa148045c80053b4	1	0	\\x000000010000000000800003ba7c8827eb2a95453adf95e2d773e808edcdba04fdd3e112362f24314a591d3790e030713b9386f1c390ea46259eccbc2c9e239f3fd4b2be360b683d8e579851fd06fb1fdbfdeaf32f1659a068949b8d6d25de5b8eff8553d375ebbe4b45f920d64fdf21302a622072819631b4d8afef05a04b320ab7fc1540cc72a11ef64649010001	\\xa7546640c1088fe934a2c4bd817ccab4dfe52671fc63a2ff93de0181bba92d3cda2f470422156bf4584db943e1215b3c75fa29140d812b6da4b8994d6ebb570b	1673805571000000	1674410371000000	1737482371000000	1832090371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x693136ab8c25b83aacb9da0bb420fdcedfc9e63abc830f94019932d48cf544c900f1e38410a25919854adb8060db95f69649e2e8cad20042bc0440f45ef07c6b	1	0	\\x000000010000000000800003b7f020fc98e95c7a56fabeff415689c25d299ca45cae7ee7c44f41c3fdc4de7cc4806941acdde5e302c82758dd08e0a241303714efea4801317b33884e5812d89da4908895bebe3323c724b8792c049f9e07b6de54b06192a5034867b4b810d5a516306f84bcacc19c2e6064f0e5ecc6c221fc4b00dfe3dea8219a3e1616d651010001	\\x841f3e69a9b405ba3eef5e2c56a73b79ff8bef182c73c59a49e58e656c03a1369bbd81b43ee75be888460ded9b3c7e2dd5a6fb91b9a5e3ddeadbad2e18252507	1659902071000000	1660506871000000	1723578871000000	1818186871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x69b1e58479127a72644b4048522cb6ab1a118f19c01f4c68bc8aea0a92c16361c42f19ed65ca81ccb1d3a1e8204db347666106ec8eda766d431a73c78ead601c	1	0	\\x000000010000000000800003deea666ea5472632e85a191998fe927bf7d3a2cd1b880e892e455ef715ea25fb1b939c73cb094eeb73b43144a6e8790f9e72d02ad6843de0a05f67f89271dce2f53e22afbc9f12c4126f5eac0d2b97149a6ffe77d125d3bf8c44e490344fea13285daac85a372b1144b927d24e19fc480e36cdb5d5792d3f88bbd3303defde95010001	\\x925f0e1188556a75360cebe64f0e95acd86a306fcdfdc4e977e17de640f1c1231b6984c3432cb8f42e07d6cc8bb689ae1cd9b9b06c394e1a46ea4b8cff5b5607	1668365071000000	1668969871000000	1732041871000000	1826649871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x69ed506929d94bb4bb1973e6d6d6a3660576d7d49316f94eed1cd192f4fda32abea1304759813f91b26abe0090e6cf091002b0d425cb4541989f4ef452dd87f4	1	0	\\x000000010000000000800003d1c4fb9a847c5ae0e0441313744ba08987d1a1bd005a082f3f6a9bed93d985c8f3018ee2ecbb3c8bf4958225d8022fd52bb602228f7fe2272e2e5001645155702350497b58827adcd046479348373df184c27046fe3ece195bf427ddafca6b428029ee3177ca0030c8128251a9a83c711238403b228caefefae3ff4d8a6597a9010001	\\x98e5e92553e0e9e5c9e4f5c5d45bda344a9f1b56b4e48f7d1e2116b100412588809cbabca25b966f7ff1f7bbb206ba932c66f3166acef69ebec5b341357d1b07	1665342571000000	1665947371000000	1729019371000000	1823627371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
154	\\x6ae1dd9f17f1cca52885ee53c1885dc729117a06766eee4f5d4c7be5210095d1bf22468e7d11d388f17c1247789bb9d8fc9fa98f853cccf20b12baeba3bb8730	1	0	\\x000000010000000000800003d5ab287f01abb8ee2ed9f0f072ff663bbbbccaf99ffbe307c985170d5a7e5141f0ddb3f14b4065d67558bb5731209777a167ed11dc59323fac388b5b8aae4660ebcdd145f33caeb58e674bebdf3fc3df5ca01a8fd52b884aaa60ff809b3807ed73ea1133b585990cc5895ecac2d7556b7d64c3c24a5bae3f4fac103e1dd22c65010001	\\x9d4ff855c7ef8d63d172cbf273ef3b47c2736caca570adcdd0ec137e35f9838b8ea182c6f9f37ad3f32076291be529ddefb21cb724cadd4772d1266659f06b00	1677432571000000	1678037371000000	1741109371000000	1835717371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x708145f1ea0808ba320aeeb0c1eb80ab5d733ef7616df581190d3f199523ec307dd4885b9243632ba3fec2e41392bd6430dd76e1d57bfef1fcb724f14c533964	1	0	\\x000000010000000000800003c1a4634fac807ea101df39d2e682b751b4dc6b7b40531371b51d92ff8f043818e4f393a71c63fae517baaf031318481c9c8cfe4597204676611d0b0d7b8e0c0b55805d060c759c4f8fc5e26d63d81203292766bb2d33f3894e8083beb332b7fbabd03e8e79d80144a40f31a808547c9ce7eaace0efa810ee000722df338ae6db010001	\\xfca85e28301cc242187d027ed4aa42ea44f18f43f43167243ea237d57f3054aaf952b3fc1f7655ff230a1834cf48f62af099977c9bb2d6bee30ed9c39df6e207	1676828071000000	1677432871000000	1740504871000000	1835112871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x70591ed2ce183475222831ef356a471769c889840f7f6784634de22ef50ebc5f69d4caeaf018b18858ada41f9dbc3177ec704638138763d5a91ac4f4d48db85b	1	0	\\x000000010000000000800003aa321a135c11f90093e5c140f41ac22c44370ae650d7495bc5f72880fc01108c921319a3dd267052a0d6e9c63fd7a67a33ab160d415dd2f3a8cca4afc8eac36f0166c0322118392528f34affce3189ab8dfa67c7638d193d3fecf15368cf58f8dc5af1ef43ef58eed9c0c3bc11fa5f4cbb72e1521284c5bbe653e96d963af61b010001	\\x632459b20c07016b8186f7f1bc1f9e66061e785c21fa61f68ef44d3f86acbfc54379d74514b6fa7b3a5dc787912c7f5d7471eacdfccaf4bc47cf9afbdbee190a	1658088571000000	1658693371000000	1721765371000000	1816373371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
157	\\x716d9e1184246f500d31e9a3a9d5c541d43b57b33c82234b5070f644915d38bcfea7f203df2f3e40a920c7f73bdf19294877b8e62975ce28495dc206f15c6447	1	0	\\x000000010000000000800003d0fc06f92c581f25dc5f04f0654c9e305e820945df95234be15e85afa149a10584fab72ae283801066fd3b28924acfad60f4340f16a720b6f6d083dd32fe9f970c688fb755daa0b5f90908a3ad73fd24a8029a163cbc280b7765f831a94c9039180a386c2985d78ee797d7845a6af94aab12743328b777279b5dc84b61daa321010001	\\xdd79e6f9b87bdea546d5e8cfa74f1f1c98918f3139472199261875417457c375d03359c53d25a799f4d5801766884352ffd5cd2ac160a90b0fb5e0b29052360a	1674410071000000	1675014871000000	1738086871000000	1832694871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
158	\\x74c5e4ad712e0f2e8505a806e7a1ca2dac70048da417d4f9e2e7c354b1134db620956c6a1b3fad30b7322af715072c8931be6742491c8e16384cbd0701912602	1	0	\\x000000010000000000800003cbfd500ac9c94d1c284e785d940da279e589891520a90ee1f28fdbcffad7a85bc05ee2ce026108deceda8f27b146d20a63174ef7706022f24fe04e6cb2a2306c2f0de8739d66562652ac142c522074cf4f05aab748f76d8942e43d7e913491506c54a0140e7b04e06df18f45da7b73d3b449470a9334669c36f1734251f3c27d010001	\\x794599fd3374edbb2ced61da420b22a2bcf1012aac3610c95c3c31d09c7a9cc6721565016bb90b505f4e826810509b41e87e528955d0ec5df8f470719d74930f	1674410071000000	1675014871000000	1738086871000000	1832694871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x76a99fd8bec5989db4fd5e253c6fdd7281177bf552a2a49415aec2df76d0fe9e663f3acaacc57b3de277bde29749b8645c4d258bd70c56296747f99071f43abb	1	0	\\x000000010000000000800003cde120250227900afbeee85243afe09637629918efbe8a817ffcbf8678189c0856dbf95e08cda420c8d7e83404c595742f0b0f526c4881bdd8a1f5f897b9f4b2a143b8c6b38ab38faaee935adb790b9ada848a6c7391fef8aac7510e146a42cc03d4dbf2adc101a7b1819f53dc66284faff96c97dd7218f6b1c55f9cd1c24bb1010001	\\x3f95ca38214946ec78fa7221b15dab0cc8d81fc64c4c039118fffb06d09c9d2763a58b7a20791ff241381996a1b0cffd7a46a2e249935132d6b17b15ead12b09	1683477571000000	1684082371000000	1747154371000000	1841762371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x79e5e274601bf098fddb2480f1ee4d27a1df4d787ada792fefa88e31e50aa3f6c6cb3318a94b78493d6e1fcd3bca01ed7559d2659537e739d600ef36aec57b95	1	0	\\x000000010000000000800003bf39139cbacc8cf9343e212396a31338e1f8776d8994973ea686ee488b70d38b62b85d8ac29e309159993bafda220ac35d3538834fe3cbd0014186447a5f4f65b7331d8fef0319061cbc0909d215d4f79a2e88b2f3314d166d35cc6552ad68e0defeff9a8d4eb50c482195cfa71db3d4ac81b3fc0d86036e539ada1ee39270af010001	\\x46f2a6afcef2fc03d3ed97dc358e7e5eaf27888d5655a16c079988fedc0756724213997a8d671c45f864f878cd404861694ae292f006f7faa38baab361393b0c	1661715571000000	1662320371000000	1725392371000000	1820000371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x7d19880f0018862a40f04dedcbbdbd4891526afacedeb300432adcdbd47fb16e6eedc1e2ae5ef3b91c8ea24c1861a3b11f9a9388f3de3e2b6d11ef0f71e33ed9	1	0	\\x0000000100000000008000039b22f055d40b59252b83ec6045dc5aae0f1a1e1a7f9281955caf3de89d8e84e28f4d1221e2fff0bd57952a527b25e9829418f55e53efc55248ca9e3557672b72fa554c3f94518739bcbfbe6a4a6c19036d5868c9262cf4a15a4faf014282426408ee497eff5f10f30c6abe6f0da2e96fa3b18f405e680a864a29e9be8c32ba79010001	\\xee152c23e20011553684e30e183c2284f86528de50b143912f25871251534e8ae7188af03ae862f8e5985a0f4eb1447a08ddf938adcd9287a6b77511753e2908	1660506571000000	1661111371000000	1724183371000000	1818791371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
162	\\x823970868a92f1e288f7b2c20ed195d0a7df8aa8779a5219f00b1156da0928ac84db5f82321cb4414545052a7803283c8ce2e7b2275de0a040cb6a17aee94a7b	1	0	\\x000000010000000000800003bca71a30756c192a3cde1a794ec49cb41ed19f44acd230bcc7e9e07b606ce5a01a2a385569e1b38396dfc2524c03e3e56546b9401c2769236361e497b54ff2b57baffc8d10a9570083855bf86d8ffc96e8745dcbdc58ccb2b83d381d4b4b1ab35af97c5eca06ffdfc9bbe0d96c0de3af91f47a8bca602617cbc5afff7b723a4b010001	\\xc5e02c7a70b455a97ecd123addbd5f349bb251a8e67d3e9f17a8d443c21009ead1870f9a1480b9f4fc0e0a98260630ef306d571270944280257b2c905a017f0c	1681059571000000	1681664371000000	1744736371000000	1839344371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
163	\\x8639b42569abb19eed07452ee9042e1289097db9060e8cc64633b96e9338c3dc84f77bf24a28b1fe00d0ebbe8f9410583891c249afb18bef150caa79d988b20a	1	0	\\x000000010000000000800003bedbd55c1b95b257e75336862d036b4325792d0cb3bdc4e770ef613960e20e5d853564b5980c4e313275bf9705f9429d524161ed825071e2dd2118afcbe44e2aeb14d7248a955fc27957a24ae3c0223363a0d4727d837892c6433f0024be97fe4f9b54b56c18a444d6571ba4ad6ee1026cfa789fd2bf7baf418aec389e5d95cd010001	\\x3e7eeed8104a5338a6983a8cc7f6c69423d2f6e41298c10a0120c67cd7810e262eb8978bc97c92856c3be29becffadb97976a6e6d724df390d5f1411c8a56b02	1661715571000000	1662320371000000	1725392371000000	1820000371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
164	\\x872536880818edddcc23e8c9e91508d1ed814e43b1f32dec03788ffb2bee12fab56509358f6af16810a78045d96d87dfb30084621ed7f63f8bba68c5ed497680	1	0	\\x000000010000000000800003e2c33623b63edab9bccfcf87ad7231dbdbb75f2fbfcc82fffdfa3cdf741c1b52a989f69c5dd9789ba193e9a83ec1ad0859e7755b1169a7744994cf7749859e0c5253da0d491f81fc3831abcd67f9c7c821f5c27ec975eb41dcc40a407cf7cf84009d4ad0409d627b4e39688df84ca3578c6949c8a8af18b1df5d02f74534e7b7010001	\\x3c15b8ab8097d3d6493ce93e5e66540cbe35cc392bdc688eb38c662f975d8c8c546f3643d49da95e652c264200a78808cc6e3d5ba4550df23a36210ccdc74c00	1683477571000000	1684082371000000	1747154371000000	1841762371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x8731903619f650582152346522c6aea21e962dbb660f6ceabb273446e491d60993a77fd053dc7029aaa4d736b7bb2ed2606d94347680c1074193af03c14dce84	1	0	\\x000000010000000000800003c6f8b516f9393d142bec18eadcd34d2d417dc115d1952a2f3d0eed75465cd05f142f425f33e2d6874094772a6248c5e715f71740627c5c50ac2322f1e45a24641a80a801447e69458adc17614f8cd03e85b6fc8f0dc59d28db42da8bf3cba6e74a117be8faca4a2353ee515fd21940d48f6601255c5e645bc3b8418f0f32a92f010001	\\x7fabb2354aa068f067f932b70496d05e8298f3920d4de98a0cec7a991095343ebabd81290a75af15b123ed4a8fa8d2d087bb30408e246349854bf2207935190e	1675014571000000	1675619371000000	1738691371000000	1833299371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x880504e5cba4c8b61e763a6670bb95c36a40c0651121549ab1fd66c95a794a4eaa79c618886aba00d2b1fec3ccc3be3ff2dacc030a4410d7a33eb85ed72a9fba	1	0	\\x000000010000000000800003e6855b99457796eca82966506efe66b897259a0e34628c0ee106aa8fd0494a96eb1f694148f7fe23d8dd9517731a08dd524d23c1a2e29dae50b047163f79d1dd36314240f95789e4ebcde89d8c06d135a18644cd2107bb7ab66f506557bbb3c096610886fa0807760b3afff07dc567547860dc9e2f18c1fca70600ffd6af848b010001	\\x1b8b4ee31535394a223c866365f23e6100097dcd2703436e4b980f27859cd948f50171026063973f36feecee17a2d08cc8f2750165aabc679031dac1fe56a00a	1656275071000000	1656879871000000	1719951871000000	1814559871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x8c85a2e33dbd7d19c6ca54b7e1637d94d9db752c83a03e5951c5be3bc9e72a175a9fe694c6599bec1cce9695abd03746f07c0c5dfa437d3c0873f8f3f51bd604	1	0	\\x000000010000000000800003cef2f7a8606ad125a3395ec0aa39f025d46d7d457616616ceb27ef04a572e453dfb40136dfd508ba21005a4e84531e05c16614c3813b01ce4be3b32d5f23a9011444c501670bb8a0608bbc7261fdc8b5458b3b2d8f8dfabfc03e631cc48dd6be203ec53499e96ce8b23dfe9b8c28f3143e05196abe9e41b28da5e2db4bedb875010001	\\x0a541f11c4c3970417524564d20fc1d381095e30ffbd1de1b056e7dc672d3887df30851e5554934c94b0579f9cba25123f02d6174052527145586835d0f7a609	1669574071000000	1670178871000000	1733250871000000	1827858871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x92cd3583c164379da3f861437a3c73221096f5ef4b87ba533d915e52fa1829fa209b94108b29fedae6fc174cc909c68454174a9e85fb50cc85d96012c1bbf88a	1	0	\\x000000010000000000800003f0a2d0b692e4b1038d2f4ef83a7546babf336889369099240fb5292e1628e48e6c66d5d4ceabc7cecf17bf126444f6d95081d254938a05041833cc27ad5bb99e877df22216b5921261cdbd012e0c9609cbce3a9b7ddaef66676355f0749c254ecff6afc0571f0d421554a1a3ba134665cb1ac1283b9f853acd63a16bcee837a1010001	\\x1641570b5d6714a680e0eaeb1c962db7fdeb11f77f80f55eb27be002f6f044f99c5f6bcddb1c3be7c1e0a183d36804e7dfad22c720b84a67c91eef24c234d107	1675619071000000	1676223871000000	1739295871000000	1833903871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x9865fe5c3e8452e11ad89e810e9ae24ba47e08000d88cf5bad3b76d29a4cccdfe9027a50164ffa41fb60bc01fee5ff1b5689bebce4e532f7bb86493c12cc25f1	1	0	\\x000000010000000000800003e541f3d6578d2bf53f86e040187cf1dac12e5f4e0ca09a2d81b6a9aa1c7a82df403849573077fd566bb0cec8bee1af68fce7b86d3793fc3b0dd968ca38859312c083859ed59011d3e723952550481da1a9092a2fd4be99ae04e89bd4a566603b26b020bf1eb0c66455211ba638413baeec087cbb82517b5cd32236f3c71d1a0b010001	\\xa548367400117236d478cdb55849f95f1bb95faf32e4ca78d29bb1805da13e333598e2007da392ea69622d184ce327fb6da8578b2a138a42f310cf7118bdc700	1676828071000000	1677432871000000	1740504871000000	1835112871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
170	\\x9c41f21c0edf49d53bbbe3b5fc2165aea267b4de8cb9551574bc646894cba1303622549dbdc0677b7b3a29994929afd7431430afa74dfdbe3066b08df5146c8b	1	0	\\x0000000100000000008000039e616aa4a452280b3448de9bff7aef6ff6978bc52d741422b1da889618889661f2e3477554565f66251172016c47bb398c74e6b5336309e19b9119d5ff5755c5cadf0d6d8edebdfa8e767fba749db933982c0f56b8e6187d696da4a6774fb6b8c29b548ea45965ec8642a5f8633a8aa01ef9cc038e770f5bf2845f2d7763157b010001	\\x35a9b6cabc0bfe6f4f1700d1e168e156ffc17e91774f9ea16fb05a7b064d83a488e38b9f7f77dfef397704b5fe2d5241534cdfaf7eafd2d4e7d4b296e9641f00	1671992071000000	1672596871000000	1735668871000000	1830276871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
171	\\xa7297e842499b46c75b020c168a4d1b3ceec3612747f83679a4c2f985192cb6d86c02f8a1724a1b9c4ee537dbd85af54823c60554851b3b56b0b7dc7137bc25e	1	0	\\x000000010000000000800003dc59ad52b4a68b39aa39a1522eb43643964e240684be36f7faa6d79500e074cf4692d91e30c43df85887c401f04a8be592ada5eb628eecc9b0452a57057bb7f21b92682f1b63f307c6e200dad6088887560f83db479288f294aea233fa772469b3ab4574effc2f4e6993919cccf8f635c0d83010e85d5a110651e056cccc8399010001	\\x56f9d9767afca94ffa5de8cfa0c164d2ebfc72059543d99ca8dd05b563d4b0d2fee048efbcf3da18ee14d2de3aa1d99890f720308b390db0edc5392ba9a7180e	1662320071000000	1662924871000000	1725996871000000	1820604871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\xa7fda7c5359109c1eecd31e903ebd5d091b6f8c55f2c7bb8710576732dd7fb17e22c5202d79e0b73bdb66c4d72ec3f95783ef7b989cab73b2e1fe2b06793e8c5	1	0	\\x000000010000000000800003c81dbfb71b8ce9c3f9a8e30c0489429799c7c01648020fe39748c569b6c82a4407c57fbb24123f005f9f365c67896487ec0fc04c6bb78b7a2fac2f48065b9fcbb65102b71fb617a62ff76385d9d25a2a80f616799c61094b9d19c274e77cf5cb7e1b4872a6c5e736f48e942781aed3ff877ca597be38c54228a6885977708b05010001	\\x164ecfe089e406da92de757ad3da494b86acb7107bdf6b140a70376a1c16733760100167a39d3a038bb74352e1338b78c50a8fbdf139f94c4fdb41083e487001	1657484071000000	1658088871000000	1721160871000000	1815768871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\xab09e6e856f8ec1b86f8e06bcc2093c5f8ef3e8dc35936796c8ae983b44c9e8fcfcd16124bd3dc7bbc5f271774ebfe06f7236e7aab6a53d8b130efb7d4f2b67e	1	0	\\x000000010000000000800003cc5b7c89a2dd5cd3997faa040640cbf7dea2c92282fbc77729f00eca700b768dcbd271548fafbea399e529b20be827b07c00812290107e238342fbf9d0e00e687a94c5d9ab489aceeaeb2c89f7cb3b53e34caa8ec604345e9de95d2178ac3443bd728399ca0abebbdbee09a42c4d34bf0d1ffdf6205d6b9257e61a8240957fe3010001	\\x57271bd324570bdc1a7e47189f84ca2b6fc8af798a6bbe4eed6f2ab90be1574c63559a3902861be6760a17b61c3bf36a1f4bd858ed08d2e25aa923ab145a7303	1669574071000000	1670178871000000	1733250871000000	1827858871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\xab716d0284f6449c93f843efa57bcee70fac40db0975a928a91c9a98aee10e3497daeee9140a3495a7193c1a37e055e67f39927201b04f136f30446698d4d154	1	0	\\x000000010000000000800003b22fcd5b8ea3abc780618d6060bf42db69a8b95896696cdefdff17e2518bd033c7509d75ee698bb2acdc85e0ec6dc7533013272d844342d2242fae5bd5c30998dc19c4be9398d20a7408920e259ed2dea380cc9b508f5f2ac95e7c9c84014e505eb7e406d2784dfce0473f7dbaf8e7d64cde122e2c9bb8ed1ec901a95f565e15010001	\\x95f2c93f5e428b777805a74b38f636fc09c9afcada62b705df5321b797629a0f3de09a29183042a0d88c6909bb01c72fdeb16610e8ef4345f5d9056349b7280e	1673805571000000	1674410371000000	1737482371000000	1832090371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\xad59adedf6c339627dd8a81945dcec269ca6edafc07526f4c01c83c6b47a48a070cf5624d2ca49522f955b9797815fd8d62ef10753b60bff7b6189e2f4079cf4	1	0	\\x000000010000000000800003cdc0b9e9cdc7cbbf84f15bc2e6e172906bbb3d1d4b51e2a9d1bc6c3e6edfbcbc3636efbd9b991250e008769817cbc6ee8335d7981ff253f7b65c67ddd294dc2012c499c085d56030edc722f29855661e74a0e715dea46313d766dfb1ac4e460e35d9d4b0af050b7c417283121c9ab09e6d4736b1ae63cf2e1a37dc64ca5e088b010001	\\x4f8983a957890bbaf29d1896d8c3ff3ef95e70773797d7af0dd4cdb2951c98c2cd1a784650e9968a954416bf98cd5fa6c8fa32ce0f65ffb2fb7e21a9c726ba09	1683477571000000	1684082371000000	1747154371000000	1841762371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\xadb525f8c986a7094baee10780764da09175b71425e68c396bb42ddf4190ba3b1fe48756ccecc5e75fe87d061be5e3b600794606c606e3c133d6462f562bc5d3	1	0	\\x000000010000000000800003c884db0e97435fb6329f28021f1233fe035cc9990d29904ba49ece09947b3e6c9275f842053844d8c8e2a17380355441ebcd37c32e2176fd19784914650524ab01d0e27773a12bab1fd4153806490d94c9c0b1b4645d1611ea65fc790edf91d3a941ef7c4699e2f6da31ab8f4ca26fd72c0d0dda21ef177f119204944c681b37010001	\\x571b355dada0079edd99d4277012e1387ae5ec029973b83cd0ba71edd6f3169d4f7c4be459e79cce7f6c109bfe3303eee4f91d3b5bb44a634ebb09f8faed6609	1670783071000000	1671387871000000	1734459871000000	1829067871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
177	\\xae1911e2420e285c4b60ea51d5746da029e7bdae56017e9a3ed7960f4c582a9bc50f8e8347b1eaf725dc21a40c50adcb0dcb2ceb08cdcfc02c99c8fdbf4eb746	1	0	\\x000000010000000000800003dd32bd0cf823a29a52468574f6be12e544cf0199388a9cae909125ba0f91b1b3740c191f3cf7db856b40babcaf6e11f6547cd9fd97371d54061fbc358a2372c1e7c3ab2269290d6e9f068eb7cb07a4d2aec022d7e5a87b130640e950c53e201c587361e663d9e062f9af8c3eef70ff884a987bbde7a65c1210321dcca3535867010001	\\xdb002c77790db31dd44da1454b9f04980e9297acfcd67bf981645361f5785eb9e05d110faf1f38eed7cd1536e945f1ef586f156f6e2fce03936f6bfdd4af5205	1672596571000000	1673201371000000	1736273371000000	1830881371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xb469c373b51b25a3204335a6b1b56644d9934efcfd95acb964ee8eada02c5242851cc183413771d2273a7e3dcd4b94454af7fb5ace28f44b161e8b0c6f6ab334	1	0	\\x000000010000000000800003c8fdb1bce112f5a1980c0d21b21a258ff1ca769e495c5818ad77257e2e856f1a452a0e42ceb3a8d3b2c5dda2c0bbe0b3135947f7c04216013ee22ab3349293b1e74f17fff714a17ce47eaf436ec613fa3d2e3b2f76ad434480fe6915a2a9d41cb99adf2cef132b0f2a1172ef724dc95f27ddbd3e99bb6e1f7c1b892e588c4373010001	\\x256094c82ad512b6552fc5e5f9a3535ae07ec1107cdf2f9cf93cc28d9c854b787c6683acd5c00640820641e546d39443dd152b33c406a7ac983c3b3e5090df03	1681059571000000	1681664371000000	1744736371000000	1839344371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xb5958c1f16926f5c6ca385cc9c16bcd35aee10dc1f6c6bb8af924b59763202655e0284a9cf604a095c19b71783c6136ab6b727b4575e017d2dff79130a691c98	1	0	\\x000000010000000000800003a2e6c6a89af6a0a127edb1524701e7a14cde54fe7b89357c4ba97a7c39d3f9a3f1f7f6e6606e75e2b3f971edbd26f3b0b116ffcd4f077979b3a9f7897a958f59d4d7237f76dc0a10ec6a1a39774c1f93501a2cb1b90c762fd62dd50779158fa0ea32d0d35efe1caea8f027a560db4cd9f3eec442d649b5c1b1812f83c480510d010001	\\x55addf78e949ff8e8d862743561d021dabce78e4cd8ad70f836b5da12cb1c3cb109c0c9a4274d75e4e1ac33418e45db1369d8f3d49f11a7c416404df43f4700f	1679850571000000	1680455371000000	1743527371000000	1838135371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
180	\\xb951f29d257d94260c7267bc9b4073b668a28c57881920885ff83ebc33c6da0665c7cc937a247a1610f588c492d43d515e747c80a59d17e69e682529290a4f42	1	0	\\x000000010000000000800003e14943d7f9f195c82497e4f85e1ba1d73fffa37cdae3b98c822e59a3c1a9634a1e8069db717008c3e51b2f086fedbb0b6739d089bf05c19b9400f04aba4defd04b95b9420d5c3e25bfa0f3d0a4f6fdbb3091aeea380e40a9f11e03bae97b873cf21b0f9bae2b1f02eaaf86da6322dde2b9b90f9f85ee522bd0f372c4586fbdbb010001	\\x982d0789447f2a230d7ca246311f5dbfca061b58b3bbd4733c561ea26d7cc32ee433ff40a981d0b3d8bcf46dcc3f6df9aaa524ebaf749dab2c5716b8bd6b390d	1672596571000000	1673201371000000	1736273371000000	1830881371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\xc239bf2af94da6a5f93b33b7ace569c874337bc813e018babe8c22d68ccd92f3d68b7d9503beee0d18fc192fb809eaa06bc19b058d5859ac67439dfdc946a273	1	0	\\x000000010000000000800003bff8659be44b05b665f0a5ef5e77f5e768ae5f18fce0318ada638ccdf12ff5f5f9200a79573381b5e505dc9300a8ee9789f208e495d53d9e66a1a61a3a7b2d21fa360c829d54d824792b15c13dd44ac955aa2d1d56009d8e4c057b32889f9916ea452e271ae15d21cf6a1265fe250e9aac1d7a185434eb755e94fbf6a461c639010001	\\x0d1df0d77b5ab93b69efd5329d688ff9e5bb3c5de2545a24a634f30271ec7126c95e79219ad6c5a12ebcf1bbcd4c76cbdd68a8e8b19a7d205bd911ae7f887301	1666551571000000	1667156371000000	1730228371000000	1824836371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xc561a0d11ae36c6aab265738419ecbfa2c37180395dd149f03386bf1a73eaa055f7323591f52881308a91935580e0d5d1580291fff7396b5229a5b233e30a2e4	1	0	\\x000000010000000000800003ad93f965428ab156ba96354f4905265f012302c433aa54197471c255dd5c8524b5989faac43a5e79c4760ec5fe61fef5d43777b70f3923463a2bf95806cfa82fbb694d29eea72dfaf9fb02f4c4ede7a96d75d844f39fbe57a05b10588c9945cf7e9a167aa7e38dd28dd821660811dca804eede33facae968ab91fb877eedcecf010001	\\x87714e83e774c8a0b1ba7475d8185f511a1cd7e51978a80fe7150935547291405bd8bb38abbb58ab57a89b3df55f794f9f47b3653553d989174437a4c2390200	1661715571000000	1662320371000000	1725392371000000	1820000371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
183	\\xc525deff27dbf8cf6e49c80fdd483d9d8956d23d21352e376a6356c8dc68191470a9e401daf7d99648f6afced80522524599c53a6c6184d413fa75194a13b538	1	0	\\x000000010000000000800003b26bde9a82129b21b11c413089cb57e749a96374c07bfa5631bfd01fd5cbd53cdd0312a9bf9d28d244ce377f8deb85081f23ced4fdaff527322c7191bff486dbc04c2d9528178b8175c4a445691d94fe3966e26630cf40ab3c2ef80a5e77de8c4d01b6e5c87a1694993f6fe8ed8bde69b0ef3db93688bb09b62949ae731ca965010001	\\x1afdfaf22c00cfac0a23d2ebbae08f73e4dd41145408f9e80ebf62e84808a58ed89c768518845c1a5de01e7fd6dc7ecc1a7e33a1b45ed879ce16808a6dff6d0d	1680455071000000	1681059871000000	1744131871000000	1838739871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xc5a5422f9ed7cb294a2ea8974a7f5b22b7a2bbcc8e44478902fba063a9944b3d133ac7a1988d62f3b0f71c72f70710703e42c12102a26c5f8cfe99940207e04e	1	0	\\x000000010000000000800003c984db725332be4dad1c784ff0f775d90da49283e12669a7cfc534e0a05b55c20a44e39efe15f518f027de6055a8a74caee253523dccb16d1fb11e358853b7084bb5f35094bcf19f84e9b13dae8a107e4aee186cf5310967d509ae048751e0280e1e7cc17301f5529e99d0453be1b23fdc6b001a2144d7f713634f824fcdde3d010001	\\xcee8577c22d135a92ca606c12ce92847072bd99aa49c52c3adfdb548fd9f25de85297f3baa8a77e67291a05b2f7471f0b605b37d4600be0f9b945fb8f42c0405	1662320071000000	1662924871000000	1725996871000000	1820604871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\xc5891fc004d9d45477728d3c7e834864a4dc2905216c00489c8aaa131f2401014f5473472c25531bbf12903a814677b549a396bf9edd200f7f8a36992abbdbfa	1	0	\\x000000010000000000800003e02b24a505bd9eefb7307d46341fae53c105a2369eff0926b978df7ae22ef9eb6e14c9decfa09bb367d790b9ca864e0c8df0077e8401cc4f4bb62cd3bb122b75199a69f04b12c791034ede6aa98fa855ee3d5af382c0fe345f15f61b53cfa5d3d1519d2c933b523771b4a83d514b863538e5cc81d49403561ccbd8c649f95895010001	\\x9626ee024d5f301f98619d2148c93374e463a846bf2fbb61cc066b8869d2b6be0284669605e067434cd5827c7abf61f459fc4b0f5fc87b130f5112caed185e0a	1666551571000000	1667156371000000	1730228371000000	1824836371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
186	\\xc7313984c021b3de441319c9483714bd8c295ef9d69bb2d01f5b552f0d763ad0677f9f0d613b30e3f71f82fb88feb303c6ff129216fcdfb93080f6b9e573ab77	1	0	\\x000000010000000000800003b97bf5ce858e2bf3940bd6e4e57edcbdbbabc857a6341bc5e98b315894d3ab18c963ad35887b14fcad534516f59ead6794a063d707c2bebc49110830bb08ea6a35016965205387686bf1731994f2b9168553190b20ce13b2c7e11007c4c1068dae254b6d48e288567ba1aa5136a22fb375bc5e146046c489456f1e928f26efad010001	\\xe058b49566b64ddb5c55993acadd1c59df3ddf2311dac675fb53d0ecbbe70e888e4698510a428616d2cf59c397cf88c17bfadc7daae97930477850b26564fc03	1665947071000000	1666551871000000	1729623871000000	1824231871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xc9712d5126eb91cb8e7e63359132ce73327029e5cb55a6bde9752cfae9a46f1770a00b0918f164316af43b53b2f4f8a534a6e9a178390fe736f3c006f34b50b4	1	0	\\x000000010000000000800003ae4db9e6fea421416b736a8ac93e808b7327e5f40716a92cefda5c14048490faabb1ed97df53e6b04fdd0651f1eb87553c8c9699096b4249d794efd07a7e084332ef6e3e8b957553779042e518e29e0926f73006694a03344683b4878382c8b7ccce1a3ac517984cc5fbf70f60b2fb4b5e63b84411a6010587f33ae2a4774d47010001	\\x7775839ca576808fe87c260af691ed0821bf321e95f71e7143931747a14aa40b42952988ccd159a485e03f15c74c1f02cd6d352ecc5bd7bc13c795390a6f830b	1655066071000000	1655670871000000	1718742871000000	1813350871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xceddc4b63951e0d945d8e889cc295bf6f29d84fa8c69e4a88afa7aa1fa04cb598956ee54cf32154f93af08ad545def3900d919951628b212b08a767c257f2981	1	0	\\x000000010000000000800003b4d2156308e2f4018549b93a3e677070a825218d852817eb952294f569c09b493e7a7993069f4b5bce1d80b04d743628f0c61d409a1cce61c970cb77d2b7781c54124e76857b8f1104d962b39223511063dc870d4ea43975168dc13a87ba08d41d3f0d3345eff8f61a5161ac38041ba5291b197d205f82fbe8b0e427ab0c7189010001	\\x2a683da78641be4f6eaa329a93ebf2aa83281db3729d139699c81bdeda817dbe3e9073a691a972ceb808e6f6f16fffc3a64f8fa2bb833ad02d4f2771f9f18f0d	1660506571000000	1661111371000000	1724183371000000	1818791371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
189	\\xd955415e9022ef8a34ba7cfb05f4e705b0c23c98e82243f72b5530d77b6827c6fd1ec46219efa44cf513ac8a3c2292ad8b59addabd3f1eff18f3a5237d8c88b6	1	0	\\x000000010000000000800003b9174076b4e9de457c6684ec2e533980b584b8c6bb2085b666c6d4eaae72e7cadbc205db24fef64e30a4db326969e46ac007c41f27daa0eba95a2fa41c0b2dc385987bed3fd1ea82dc54ca379c4b1dbd8e7387ce07913d3c044b0943f71811885c1cc020d99acf22e5d3c005ec1534f753cc858ebc2f17a3f5ebe58ea4747965010001	\\x73d19c244570e5a9c79002092285a613c750c9d5b862f388fc221cc449921f79752c103e406ba4ca48d9fa5770d663aedeaa1da77b19c4e6b63eedd32d13e204	1683477571000000	1684082371000000	1747154371000000	1841762371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
190	\\xdc65e71a0378c2134783413477052eebd55f517e685f2e76a13b869601e6491438daa251934335731dfd2ae31af97e3933d9575d83523f00f71235f660905646	1	0	\\x000000010000000000800003b284d3a9d2def2448128af0005a8e588c999f2263f533f1fe361756f34e24a09b97d50574b3f21995fbba473cf5fc5b65a999590cbd02ceb49bc5bdcdf206229186e7d233bc831b0a0b2c9381e72f3ae44a19341ac3f0af9552ff9d1d2be4ef9e0722aa1f9fd0effef580be9cc902d90d4034276743dcc153908a29a81661eed010001	\\xde3f2fea0f3725afe876e96743f16006d7f1adc34bc75b927753abfb2861785d6482cd96cbc6371731ecf1f898ea847f931cfb14a336afcee662231b277c9701	1659902071000000	1660506871000000	1723578871000000	1818186871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xe10969c7148f7320f835446f1516b9f91b7ebb576ca55a2294b89a8462341668bd51a1aec930908b0074fa4266451f13156aa413d07e772f535b93a91437edef	1	0	\\x000000010000000000800003e058266d957bb0eee2dbfaeb08728ffa3ed3a3a9fc0fda1771c0f68710e56dcd2f0b63a1e933c926d0b8eadbde801454efff3e2107536184eca4c845fa2df4f62a4497faf96634f10b604dcba8e13bd6dd15d5fa4a287a0cae272f9eac7d7c368424ccc753638e49304941a883a64aa628a04752441142b9a9c9a6ad8cfa0a55010001	\\x500626a1485233cdb2bea4aed6f98cb7e6324589797e64a6baeb5c03515115b7598fa5d1b0e1d0111653f582586d90b9c226162ae64ec68aae5da424f6380508	1661715571000000	1662320371000000	1725392371000000	1820000371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xe1015fe84ba4f9f020dad1ec0bd9fac61aa90af5d98063ca66f7a3d93f36b2e6155aebd4563f9aa09b8abc13b95aa173d7836019fcc5aa9155cb3bd9eb3d541c	1	0	\\x000000010000000000800003a94219d278e46890b0dad0395cd8bbf5f7ec4dc7c816acee9de15e05da3b74a5085b21621df7d5aaee84a9fb6a62ab2cf58c417a6fc45461218a8b735afec2a6f50ed17388fdaaf418fcdd9a73aa6d491b89801c1c17ba75c5840417325a4f664f0ddb4aa289210183fed6be15ff5fb3a33d9f9db9db4289d72bbe1160c96f5f010001	\\xb46b6b87d5c4aab51c34adc9ba9e69259dd452c52b59892d97f859252bf6de4231059cf604a2af5a364a07bb5b7a9fba58a9719d2ec55beb8861f0b051e5e207	1667156071000000	1667760871000000	1730832871000000	1825440871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xe1b97b4bd448c9c43b258bc81c7d3fe8dd225202acd6d4b3c2780fede786249bec8f8bb827e545d7f1a997a4b795de62ac74981ca7580551d74c08043b82c0e2	1	0	\\x0000000100000000008000039d272983dc54a0996ec1c9bfcde63ad0d543a4b38c62e9d70e9beb1e57feecdac8bb35104da7a553e0dd2a3fd8fc2de67cf2a8df350516cacae56982fbb8a371bd39651d82c757e600690e2f508c28539ebdc61d6ae06fe4c3b2dd62ef0fa2d3bbd17950a2b274644a2f1b6fc9671d43b7e7b3c71541c07f07746e708d838af5010001	\\xa8857a199f63efb1cbf926944ae66d7201a9df3d48d97b50b5ca8b748bcd708f3fc083afa252683caadee9d7e122dc93c7ee92e08dcdb93767e2f5e26c61fa08	1659297571000000	1659902371000000	1722974371000000	1817582371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xe3fd750a029a6ef9f6bdd4bb4f56815250e9e36ce6edb67953833ffdc259c563aea48d06a4f9e06e89d3bc39a78e0a8e9a9be2eb0130c7837af2177539059232	1	0	\\x000000010000000000800003a5876658b4a05fee4cd54b05c3c1b259af559073794c4f79b7c911ff77115823565c6aaf9d18a7d187be89f21a281ca98eba5e1ed2df9536078e32f0eb3392cb4fcaf4b18ab258012c7814137e079e7f3c4e2fa759ce05318f4c93d83d695a9fe68ba75e1245640afbd4157fb5bde61ba679077986fa248aea4dcbf635989783010001	\\x50bfaf1bfca2ae2c25efb62d9bc93ee0ef78ec247514e3c30e0682eb69dd1816ed233341498fe85680b743b2f8e8ea521bdf9385fa5a67c59691341e18a1c601	1668365071000000	1668969871000000	1732041871000000	1826649871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xe49d4345795c17fe3ac7b05c1d592ec0a5ff52f1a9204edc27bef41b4c4ec5497c453b19171d39d328cdedf7ba9bce2051ed2e9c24e3bf56347a0d6d2eb5a764	1	0	\\x000000010000000000800003ba5a9fd7a940e65b846a33b864205b090e6a67c8d677cf25f4fbf7c3f046d924ea8224641d43f03ed0c8193c8980de05dbd8ba703aa893262a66fc75bbb99dea542ade00b703eb949373897b91c8d94a7f44dc81389332ffecfaf854484d361cec6fbf12593b04a1f8bcbb33cd5ec438dffc29f2c63c9ba01c7715baef646be5010001	\\x600f9a530bdcab40783841df56e68189484bcfc826bac64f973a929ca098f8a26ae5a96c7c3410cfac613fe14f8665b964d61d1ad100ff0852cc22003a933901	1684686571000000	1685291371000000	1748363371000000	1842971371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xe515a1717ed6e889d26e5a022d515ab406a0371c2b009329b97b63ef046c50b8dfa50b7543067be84afb59ea6c437f87e7106c1cab123b75c94f908bad323aa4	1	0	\\x000000010000000000800003b2cb9ae1e2c1f14b04f67886fe5114d7227d91a760629e971ce4dbbd6ac540b09965c3c4c0944190aebf5826628ad1db015ed0d61bf338984c779bba79ed9bfb088453f2eea4a4070f03b84decaba868b3c0ae642f1324c5ce6106aa171ff8505cbdbc6585bc21cd145d7026cc9381cfa42a7aff2a8b73c27733ea3d0c84cbbd010001	\\x1d46839b55c3b3a7c8b544afd412ed1d99b153416f0eebe6f167430d9d08f8323603cb3c5968774dc2717cef272253e2c1fa80ef036e05fe60f1c82f6938f50f	1656275071000000	1656879871000000	1719951871000000	1814559871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xe53526c0dc644b802252fd9a666d61f41bf6c70fe7ddf33c53f678c3bb7e0fc245a78b05de165174ce7bc387e492b3132ca18face45710cd433c60f0f3aca6dc	1	0	\\x000000010000000000800003e905369222bcc751084f2a6785211b639cc7522b664d89e4dbf433de44e03aec50c1b78ecad500bc32ee399436d85f37a46ff7b6029b42ce3c58d5de12520bb4a0a133490675b5fa295ec70261d36ff99dc6c608b9a4b5cb361a8733521382df90264f525d3d0c7b4ff01b610986a23573ed81fdce1d4bb7dfcc5cd966e3ff63010001	\\xb564bf2977d815037603d8ff0d66b5531a5c650e1cc45fb0bc1244280acbfd914edd2661149a4387d20ccaae6c32bd5a1ab320c0f7ca87973d3ce076146cc30b	1659902071000000	1660506871000000	1723578871000000	1818186871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
198	\\xea5daefe7df4585a9e92cb7b606a0c6f4c12c06db883b50120d0828188eb09564a658119be8195770ff6a0981131fa8893003b0ede2ea2f1ddd9120941915565	1	0	\\x000000010000000000800003c64f9c0ddc94fb9e9efcaa956d6dbe553e32edb0fcbe8549ea0334094cdd3963b572d3a2fe15d484fd26a1f0351835ffb7d3d33d833b0100fe5111c0935fa3a8028d648a67226334cb4b23d81a3f6b66ac109e02079930ded03f08592a624111dff35cbbf96e796c14bab029474afced2b2d80324dfdeb297b40dc681839251d010001	\\xd40538c3e5b9d3f300fa822b7506d7897ddb1436a7e01dec5f0355246a5777182803c87247cf5415a14bd7c2eaca59286b29e60208c7971e27103ab15eb51106	1686500071000000	1687104871000000	1750176871000000	1844784871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
199	\\xeacdef55cb7f631f7f18d883b53d7c430fd5ec3ec25db99f3dc6dc11c3e88dd4c4378363bee67e87766261f48df9852da602f704ab7b770cd3095ce1f22bea6e	1	0	\\x000000010000000000800003e644998873e7f0da222a549b8deef1ddc9ebcba9a4db561e903ef694472c6f8edce811c91286387cd9f48660f43395aa3b64a2d7f1b6164186302e9aafded849178822884471caeef565c86840faa4bc974851e29e536821a62f09a4f2247a522b007b1b72a81a4415c1e1c0cb84bf4c8594007b63cfc48d322c61a78388c9bd010001	\\x861e128360393e0ff21946b66dc135b1b231656ce778f7d66601d624d397c5684b2f2ad9f6221c2c5b2c6a5520432f1e42906e63e7a4abb1d512f224b57a1406	1681059571000000	1681664371000000	1744736371000000	1839344371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xeb950f33467bb84712653e85cda96b537e7e8fe2f66815c398f6f529e8aea4956d95f2178d3cd3a115185cc4a1d921d5ea62e01596a74a86601a054d9f55666f	1	0	\\x000000010000000000800003dfe43218d419910fc16e8a1adec8e1d3b868f6e0ba2207fca63bf626f4878519fa1d07200b88b3f8cae2d950208bfd7a8728ba31754996d275e66f9e3af8e9b947df88a841a40c0fd18e895abbd9cf52b152d4cdccdaa03a440e3b5fc05422136c471ca4d3d3932074c355e1adf8bc95ef406fd40668788a7fbdea31acab502f010001	\\xbb1d056f76e523b42ffc7336365b6e8732bcbba33bbead49630a629b46745d44d49cb2db9a599b7ca19088aafe8532dd41daa9701d67d2e9131cdcc349936a09	1661111071000000	1661715871000000	1724787871000000	1819395871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
201	\\xed294ade65e41e0dcd3a069f7e3cbe3bac4a741f707c11e439c90bebef49d8cb8f92abdaaef6ca9246670f5ad81bb3744b9c54290f9df12451dfbaef3c142399	1	0	\\x000000010000000000800003b61149a879f5d0528da713ecade3f3b9ed8c1029c68342bee5ed85f804ef853ad3fba4bccb3a5ba900cceb4ab3e84c106db0ad0a1acf70e7065debd0ed1814e4e5c9196bdcdc56cb6fbe3b692b729e86b8b5ea4e41485df26d9316e36cde9ce8d954d0ea4cc06136899f5dc2dcf94b62dee74a53229c8e529f326cd7192e2a55010001	\\xcf913d0144456730113ae8d41642833219a1ca9fbc5d500aa212410ec96e4946ada7555a609ed5ab5050e521d86bd73e5f9235d6c76aee65b749a115a006820b	1662320071000000	1662924871000000	1725996871000000	1820604871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xed6517f50074b74988031b86f100c135674f9928f511d7d98a54ea97d1200d37872be33e3123c66372c9c2faf86eb442d4836e3aaf253c6908379a7dfe70f45b	1	0	\\x000000010000000000800003c7cc74b3505aa64c9f2a5ce4c2f9382921fbbf927348e7a44b8b822904385047c435dc9cbea1cac4b082243846695abb4d6931f0479d9ef46c9aa3bfd73139b9fb64f328b42a5e406f4d2af62aefd8f9a2dbb409425a8f2d98d513c43b53335289a7d9197f5c4cdb36d36b96235b836ab50797ed3f77716cad538d2228e24f91010001	\\x17ff1723110e05d580215f365532f05e30e4722d88af1143ac44a6b3740cab7dc2a15e74cb58d79c00dd8ad36939999c14cb216c3b29abffdb5f1772d8f6810f	1661111071000000	1661715871000000	1724787871000000	1819395871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
203	\\xf341c077e2a7c6b2e105ff40dfa5d4db3fbbf797382b5025f9e8a2e209946737d87bc0f69e834fad6fd50e564c979ac31adf6c127f10f1eb3cb1615bd69fa3f0	1	0	\\x000000010000000000800003caa681ece9409b776937a97d8456d4026b838dd275c6eb59f6c1d2faec5571ac7e57da13d1a85eb3d19fbbcb208b53d467f1b9931265f24b62eecc628984dd3b05d1655cf872b2b74f68d6f69b1b6c8dcda94aecb1a24ce6057e7240615aa9e1423cd93180773e23338aca84ff04a497b1eafad10714d67bcf5e2eb942096979010001	\\xde3c9455f23e7086064ef3b034ce40559c932226ae4b91cd65aa86cce7d22afa55990d184bbc114359f680af7f711d42d1562b84028defa312420369ef210302	1665342571000000	1665947371000000	1729019371000000	1823627371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xf5857bcd824238ae1a6fb57ee066a2ff098ea14fcaa0bd7f65fe4f7897cf076f9c811bd67ae65ae99d5f4cd3f5e38ff6681783d01640ca34023652fd50340014	1	0	\\x000000010000000000800003c29b79c504e1fd4c052e42323ddb27dd314781046a9dfec5bec8b11cd4a67190b2c67a6c4066f43944551f3a8bd58c0f2b7cb3dba3f8e5bb7657069a30abd5e87e8fde7012f463b6289a4ccfa1b5e3567d157b49f325847eb59bec59b005d4e9187000fd9ba8d06941c075903a9fda85ebd76c9b0f69527437e01967c47151eb010001	\\x21b3182f6285964bda9ba077120332ada5ed2c35007c33cd64634809507d5ad08914a72e43b84cfb465f45e67d5f408fa8861ea70100a99dc6e8c8e861b4f20d	1676223571000000	1676828371000000	1739900371000000	1834508371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\xf605ce4da28ea48f4c456bb8e86a4562d53b0510bf5735d920daca7962d5eff12caf8ab2b91f2b658f5d679a40c93186994f2466e61f56571bd19d13527a36ed	1	0	\\x000000010000000000800003e3214c58d3dedfb8b5ffd02ea3fa60f692836d45e06d8f518f93881008de0589d38d75871e0ab13135ba3cd61a2a7a5d8eb71436d4edddbe8d6034181966cbad5e7e1d95ab7b84378428d5f3bc7343fd2cdf062ffbfac16c2f8b1a90885bffb9b63fb06e0fb562209a7dc0258e39539f4008a1ef0ef7fdde14bb83c4e6008633010001	\\xa13389c8a1d96d5e41a5a66755d2f524d9cb1ab908d1f594799b593a9ef9af1fbce3a8b000dbcd6a3e2e727d7830f71041f58863463e45ef638031733f649100	1686500071000000	1687104871000000	1750176871000000	1844784871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\xf73d1849a63adef3cc8f82f6518e19c213e596c182319a1ba51c6a37ca1b0e051844846a7e07c82f04373dfc541c03f5c7c3c50bc2e16611bb4bc3904c692907	1	0	\\x000000010000000000800003ab1d20cc4ef92ec11bbb24e78ff6383d52a21216d3f8cf6a250e2e6ceaed4b33443d7aa29e2b166a473ea0b1298b1470e858ea6f60fdcab59a0d1ba02adcd8eed13a0d8eb7d4b5b2088f38e655d798a51e3e4bdfc08c216482f0589f9c2af8da6294ddc944fa0d53ea77694d86e8bbc8ae0ada845dbbf52c7c9772fed3fa1adb010001	\\xd490d68367ff75b2c0018f1700180afe852d90e6c6753649b4cd77ca81b31265b616755dbe80e6b13afea2c56f041b112e8606995eba13bc852a6cc8dc5f5a05	1662924571000000	1663529371000000	1726601371000000	1821209371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\xf94d3a696b22dbd98addb9e7aea5ffe35b626547d1cbe18acd4ffa05d0837094578c0209cff5722b8dd91e652718c7976e0ec79ed19516b2a9313396cdaad648	1	0	\\x000000010000000000800003c8a3390ae674a49d6c4ea609e3bd08d21c23a90dd622532b33a55fc5b0452c707bcb70018f5ffb6545a09d30f53b9825ae679dc12f78d03e2263c2b4d3cae0023f267967f9f072a4ad6b8173170a4b3ea5eda104023102ee22a423991fbc9fdae7638065d115487bf5ceadd7b853b56ba4a6f6fd2235bb1e3834b78f1576f82f010001	\\x62732c1a559d4bd3d50471683087b2a90667f038916de59081e4eb34d453aa8886c2d4b82de65c37a7ad18c86b01e607c308d64613930768c814adf4ca601b07	1659902071000000	1660506871000000	1723578871000000	1818186871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xfbb957a5484d01765f43895e90020e6cf0fa00ea118de7f196fa82e5cd85c332a0e4c87a34bf473824a1f8594f0b4b7a65f44645c598bf81e13598c41794d209	1	0	\\x000000010000000000800003b785200fdf987c62e20a5f63da135388cdeffafa6b1e70293aa99f5fd6941ad46d6b6cce9c65e3e0ee8b70fadf0fd096abd29ccfcfb44bb7d54700ec258794d5f204cb06d31f5b494d25a63a346d3a0ba4820ff041d8d41dfd38c8f5a03ff879695ede32868b6085fe7575990a47ac9ab6ecf17feefbf95610b4b261cde8c3e7010001	\\x6167b44249ade708c7454091fa6026f1fa938ac5f6c0760906ea9ffa3670ff19a37dd64c979d32dc4b1a6501e3656e61d1fce9d712dbd4f7e8a2642121d85802	1670783071000000	1671387871000000	1734459871000000	1829067871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
209	\\xfdb5395cec4e5a8ef37938eda87d4f29252d631bc7352442159e5acfd429a3f05fbde3629874dd98e4a2b10072985008c5d437b89117d0e606c5ea479e94fd25	1	0	\\x000000010000000000800003cc92655ea107a6afdec2a425d87b1d0f9c1bd9ed3b6acacd13b085c46946750d5b36064153ec4dbaea07db0d8d4e99f041eb723b0d8279823ff65110c21fee946b86ef419e6ec193af9a382dee6ccc030dfaa2d6daa5151d30ba3d25ce2828e6fa4d6acdbab2eac78586da2fc20663914f8a56b8edf5b54404e68d004bb4132d010001	\\x11239b0de32b9bcf72679150064327258ed059db405acb656777f344a965f3aa363bc64f39b7628c5f7c812e2edb8622a63e25f0c4981f201f997081b48b4a0b	1684686571000000	1685291371000000	1748363371000000	1842971371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
210	\\x0292728ec6ca4295a1d34239f5740195eeb543da7e1406ffacdfa54bf3c070c3a515062943bbd1f5ec16cf8d746b655ace91f8cda7a340af116dfd5d635483fb	1	0	\\x000000010000000000800003d4ff94f73a180ab757bc4b5872b385f87dfc63aee9e0e3c3b4199928f1873dedba3c1e8e10833fa2fe479b7f209d367d80ab71feb08b8c006bdff5b4677b038d90bac54f8c3874fe78a4f93b17ee8496afb8cba90ccd221bade92fe26615f0700af79a88e8d5b656c9ecfbe64e66b707757c53c06d8b261e5a31842f4b22f8b7010001	\\x22b7519f19a6077d845aba889341435c3ef40a24cfc730ad1498fdcb225fc9d8aa9c8f7318f093d3b54d5bf32320ebe9e5ef9d577373353234cd26a93f8e4c08	1682268571000000	1682873371000000	1745945371000000	1840553371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
211	\\x021a4862c4104759f42cb5b3f1ca7206c7e20736744f81578a744f2aab49cf074304693dbac2ff6d0e1649cb4610b5ecc5992535b071fdebb6a2af89d2763325	1	0	\\x000000010000000000800003c1752594edcdd94a1481b827f70b8fbb7f7b4056b4e7f1cd1d210bcb729e105377c4e56bc6c5bd19abec25d643fea9f3d0bbbe0ad03e42504ed0e7d95cbb5c066a4c9785f74b7b35670290b142f66b8f83cf49d3152e042bfc416517ec8b7f28467ac4f2aafe5b35f689bf87e1a9b5aa4c2e54eec67a59d4f228b01e3fe87443010001	\\xada4ede2792b8a787fa0957914b983b8a1aedba2343bbf3fe3b99912122339ce6c1f4926974fa5482e9556f17cc4c6c627f2deb0cb4db7f251f7e9f6a3f2260f	1676223571000000	1676828371000000	1739900371000000	1834508371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\x06262bc38d251724ad096cf342eafbbe2880f5074f14074167f73d18a7a7de197a4eccec4652f8caeab76fd58eb342b345eb3d4e939db485c2e89c303bed8d5d	1	0	\\x000000010000000000800003bfcebf72605295d21770b49a64d3280bbe4b5a35551b142c41e87324e420bae2a98abc8c9ba52e40e210c6007be030812cfe878bb59dc466345aa39a984b86612260e91ba905dd30594d790501f13919e231330df35b29bdf447f2f06b876a0bcd0f2e504756f93d2d3d465db0f78d7722b8c91489870b281eae0013ab289e53010001	\\xa917391c899e158b4780e3374c718a3c43cd5be42cd1be2a9920ee40e481911db75015c8d5c4a18434ea5cc228266d5a427cf094877ee1a802566c64e5ee4f09	1668969571000000	1669574371000000	1732646371000000	1827254371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
213	\\x0c5e2b6e994153dff8af78f0641747cf5b507aad5f27b1537793641049552eab2ebc75a732478ef5d6475b3e737a3f52d1384339973c28ca61ea83f73e666520	1	0	\\x000000010000000000800003cb430eb6b3d05645b872991986c7140ecc1a28d6744a2765a6c6b5a988956c7733da80064cd6f6ce8e8211947b0354de45bf73bb421d7376cdf608e58d2e706d9da026b9ca06fb9b4d035f9cb1e4bf4bdd8bd9ebdbbd3af4664bb1dd777855d9fd13f2a5012d16edb314c1948871f47aa73588635fb96ee0850e0f8def06004b010001	\\x3677952a19586656d659c920053b8964a1e7cd829de2fed6f0c9cbf515fe78238a3cdfed6ce5601f1c6b88ad7c10f26d03a4908d6bd4d0f0f940e1c8296ba10e	1664738071000000	1665342871000000	1728414871000000	1823022871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\x0c16f4b89f641db4075e0732056bf56f650a3d7a175259b11831c59081bba3cf1c4fcc3ff0ee21168599d5ea6a956dc4299b2b43a863f3f3195503dc5b681593	1	0	\\x000000010000000000800003af792ac40dbe47d51c2f4a95adcb9040b237ba141b126b2fd60da9a83eaf0666f19f038f2f8abb17057c4c73ba24d8b8684263f9f5175e73ff783c395a9705dc61477779c1c283bf960d79ae861f475e1cab08ca54f69d736e008e681e4700b632b602b0b7fa72a00038e5e0ef0aa940f4eca83e5a2048a25dcf548907cfcda1010001	\\xf1677404e4cd8efbb1897d243cfb20e5fcb3d07a298c30b887d918320385381da0da7d8206ed15f8476d444ac74f46eb4191d65c4a24bd049413f388867bf700	1676828071000000	1677432871000000	1740504871000000	1835112871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
215	\\x0d1a74a95540296cabce212916e23c2d28bc570c2793ed923271e8092232e32ace97aef6a785da3e40f85eaa020badb044eb961f1514cd805e05879272963d13	1	0	\\x000000010000000000800003ca1556d0386ce2ab0a2dd172d70aab35136a1e174a40cae6884952fb99a00e6f2b95069cc3c36c286fef5f82550d9fc5a250d722cca568429f4d710933c53e930ae996c706465cefabf1713da89300e80bff68ada9579b16176d66d18b76271d209a5a3007defd80ab44c09f4093f1f4c86e903e2c77f97973ca6bc71f3a1767010001	\\x5717af374ba7293e43738912a979c3c42c4ebbe2b4d6e7ac27671e5176b607f35446f468080f869dbb261176ee23c829d140204adbc5a632e2b8b18c4addc708	1656879571000000	1657484371000000	1720556371000000	1815164371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x1176e1d01b5aea166699506fca7a9ab5f98021ff2f441fc93ec79be56115cdcc04e88565defebef711296eb7842896e5767086aabca1b95dc0be68cbcffd4931	1	0	\\x0000000100000000008000039d514261d17dd0e380c3ee1e3b1e337bf7734a0c6d3b7c077b222da23060fc576deceb2c76de0b1a41fd6f070ec7c910f0e14a8aaa1cd3171069e219f91171521c3c3bc00970a5d419cbf9d9a97969a2a59c6b5ac363dbafe7a18e5558471d33c7635fb35e7407c3311033f638cb57e13c1d1a268bd07fa0aff1d6eb4d91dcc5010001	\\x4d6f58b8ce0881131de34f03b1dc8187ae209d39c223ae59f1735403dc0a41d132880305a1ec666b721bb4e87fcdcb8cd5f75d138aff111ac0dbc8ba0e223505	1686500071000000	1687104871000000	1750176871000000	1844784871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x1266677a14f695d64b7d7afb7bde63e2b459b107a23f75639301b4b4cc8ed737e6b96b1877d2934ce94f71444a1231b891694aa3f6b2b9cd2b6205a62145ff46	1	0	\\x000000010000000000800003b484f13fa7a32d5cca62496dcb653b95a193309e81b0d503076c588ff108411cac6232d8900da2ca6b673e20d5aaebb8f7fabcf7471fe037823cda16ad49ca128f8ff8b5d5902275facb67d255ddb4724b7016cc707d5125762bc12e1f13b99357b284bf44d14c0e3b51b49bc9dcd2fff6e2dbd1c7e4fc6a853d6614db58227f010001	\\x387e7ec3699a5fc9f72b794fd0d67f3ae692763da8abc606a8c88555660026f4a05a2649455c18826f297ba1aecf4f1a7791b01bb0e1a97cb9712ebb36948907	1658088571000000	1658693371000000	1721765371000000	1816373371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x12324ff250d45d740ca158b9b54238d2c83cf3bed32570c153bd482be5d351678101eed80c033fce821e88db1ecab2a312916ca6d7149ef08957010c10bc2c02	1	0	\\x000000010000000000800003da5c7f47e54199546406b60b726a1dfc041cfa9987e16c40e7282a50e7ad74ba1e66b4ffe622bf157dd20f99316aa8771f03b7d038fbbedf52343f2835b159c7bc2acae3703f9faae9bf476f410b467a1adc3bece605633c6117bc8a91f6e937c4542c1afa075752c252e2ebc857e8bd5027e260177dc3b133e38967fc188c3f010001	\\xf7d2db1e40203f67fcea3bd61c11315256accb2775f10642b9241d28b9fc3013737db51b0f7e4f750230c8a0feec9e0c613518b69218bfb7b5985d44f180dc0f	1657484071000000	1658088871000000	1721160871000000	1815768871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\x13fa8be512bea326720980282a75378123a0ede3e8300aae6399f21255ddad98b67121093de682c1876275a74f13e524947a3e784c64df73bb1e7bcd51b01360	1	0	\\x000000010000000000800003bd4242bee0e5d246dffabc74361f88a8654578bad30e13210e541f83007ae531424c850af0bd1c03c63d7e005095062f526a2788d0c1fbfab8e331c6e7c822e15c8fad5ae6c781e6b9b418d95dab49b8955acaa024f2526c2c1e99d8d691fdc31119efc5f39c768eb647a6a1d77da1d40fbc4e4984037d51574004fe4a33c4a3010001	\\x785ccaa18958c067f07221cfec6d585837737286b7cde3b9252dd91bbec17682ce1f8bf4f2ebf64d87c272eedc669748fc9d54c47203eff600ce2c08fae5b00e	1670783071000000	1671387871000000	1734459871000000	1829067871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
220	\\x146a81d1fd634886efc2b9e41f0aa3516a9a9399b8d07cf3281e444c747d36a7c6b88fb717a69a9f843dc5e1f2a3016f57d0c9922be0959d0441048130cd7929	1	0	\\x000000010000000000800003ad408e91f6fc31e1ed94bf425fad031997d7bb1860b3d5b5638c27cedef2d887f570cddc81c048ddd7bf6fc6062327a9c3e77d3b437a143856483912934710e66e80ca9ba567f35be48f5bcce871b88b15caa3fdc1f2c94c89705697afa74a5d5726a37c5fea5702f25446a661436b57cec6c3b1171759040728237f20a7fffb010001	\\x9b995164e0c0a405d8183c569eb65532ef3af913b13b95b214d85567f123c51bc92c8424ee9e6616b30f47673c27fe5cd52b7412c36bd57e951a8e8ffacb970f	1681664071000000	1682268871000000	1745340871000000	1839948871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x15a29caaa79f429f32fedfc6f07b684204ff38e812f03e2ebdbdb7c1fe9b9c81c6e55c726edf7a5d1c85c2b97627e71d65eedb9f90abcb5a220657b91524ad1b	1	0	\\x000000010000000000800003b90d98b936be1735fb378f15ef9ac87eff53969e9d380f885dbf13ff767ad9bc06e349dda29cbd8e1de057235c82f9205faf3b9c45c37e8577c076e865bbf5181567d4f4fd0342b098f0926ceed43e98d511b2ce8439359c3d02ed601cafd667a3a1b349e3cc8a22a525540dc4e69b0985627ba71fdad2953077048ab931078d010001	\\xc50bedbe166c2dae0bd6e4a9ac120ec1b2b74445e8d083b78039f6824268e34b68c0af74b2b38e8ed3922e3ae8bcfac2d14a1e76cae5bc3ea8011804c2ba8104	1675014571000000	1675619371000000	1738691371000000	1833299371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x175e06d72d2cd2bfe1d5c8d0d406a955749f080e05e8ff02f27a49f9769852e82ffdda208c9f9f9ff1a0a0c5ff93df7ddc6970dd89d57ac81ec68c295b3adafc	1	0	\\x000000010000000000800003c70ef0df6020f5b9f31b6b2b2a849ee62c7e8299aa838398f36b5eee0b73196cb7688e801764d22a1e7fe23d85c9e2a1ccaa7b3aa9deced977c298d131732e554f9b7e7c08709850d2d409af1ac59fc1fdf08a35f94dce0982c27f663afa851a9c70d4bebe7ca5e943bd2b4a1ef2307d09389fb040898b7ecb982c7452ca5c71010001	\\x620de9dbf460496f13bf3b8862199d1fe7c92470b7731a7108ccf5874776da7e3b7fd263358b535bbfb5d3e19d6a024bec335266f8c5a3f52b07f84efc94b707	1676828071000000	1677432871000000	1740504871000000	1835112871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x1986e6d2ee84a41191be5c2d63b6797075e2f2584f045f7fd877fc1a4f54a553d6723a356374452fdf99fdfb370c9013ccc42f1b3d0303af7eadf387961d43e8	1	0	\\x000000010000000000800003e01b184c261a3661101e88589b7529e05a4e4fd9c2decd5ae67750ec0734582e60b21ae53c86d3b0005c6e398db2f896c7695ca8a3b7cf2d1ee8a0ee9049ec4a886b59121005cd49093334f48f44f15c66c8c86ced42f0c5c397b09882ee26794e801e9eae744b95e401e7a935b866298a6937732ef729deb7fbcc7875301d87010001	\\xbeed021f3e16337922ed93b5d382029e952f4d2d89ad79efdf922cbad3bc151a345c65b6e059b20af896d7ae1119993bc7c2fb4630fd002a46139de7a001b90b	1672596571000000	1673201371000000	1736273371000000	1830881371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x1d12f9808ea3fad8a6689d39abb2a5187d42c7911c35d50c08e62b0937e5be3d1dad53a2076f6a27c84a6ffef8cf1c904984740e3625730f9effe5fca2f9e9e5	1	0	\\x000000010000000000800003d46eda4be983895a92244c61f892778219d02d4341c22797225e621609881953ffde63ad6415b68ea6967b5856252736a3f99bc472a315406a3aa327ab779ec8d46d835cc8950d6126c6df3088a0e596b743dd96b1d4da7bab10a5a1907839f5d3bdbc86547a3216ad8a18984ce2d6adaf68ce4fc53c3af36d8b518fb3bc7c53010001	\\xc5ff78eebb4021e084b14ed6e007e7dc7f42d871eff00f74634cf0cf5d8db94836f86599a4bcd95e603e58da15ceebeffa07a36b731697eb8781899de669240b	1673201071000000	1673805871000000	1736877871000000	1831485871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x1dbeb19f17ded267c53a23111210d6c743f40f7ebf461e65b0b5b167ab327f60512c7396aa81e0a70b85a4cac0c43fb4bec5bf7a58383d998f9ebafe1fc4811a	1	0	\\x000000010000000000800003c5dd2fe5d0a37274512c398deac3f7ae7a2a5e616307e17348b8d7f1d01d46db32aa10d232c20a2052bc5088e9a4dff565fa25df7a900b346cb2aed70ac7ef5c96c7577b0fdb69896f0fd8e7991425a4d61ce84581a13af095669a99fd55696802de1ef420e668f870f9cb1dcbcd823e5d8e1d2166f1154740b8d42a0f07023f010001	\\x3549d0f836eef7d634523a68a31f9256cda39f78708f5a1079744bc9d26fe5ab101d4db8f7fbb43c8d4f7cc86770909d5f3db1878221dd50822e2dfcca22b309	1679246071000000	1679850871000000	1742922871000000	1837530871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x1e8a537843c9ea6599bf3c5ae6925a51ec939cb4fa82c317d13f1ec0f8375a0b3c070947a9ddab9a6dde8b5c0dc450f1cc96cb505a953eb3bef292b69a53e0bc	1	0	\\x000000010000000000800003c54367067e4af74aaff29e19d1f830a9e57157aaff07b57757897a8d62a517848180b7d53c4d2aebf38f4906babd878e6ef399003436798edd91bcdbed7eb7ded4340a09f4c5b109b23ba3ac33885f68ee388b0c17dd0bdb72e774c7b9a5e5d28aa7a9483e9351dfeb55dac5ee2ac1c6e90aadb27149ac13ac0f7e85baff82eb010001	\\xfa2030401dbe3ff0a33a1ac83251a6de464b3ff0d958e649fc033b3b9d38087c4e985ef3afdb1fcb657ad10dd26ccadaed51366e248755f6b87c7208a451690f	1673201071000000	1673805871000000	1736877871000000	1831485871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
227	\\x1e025f0b4657ff65cbed47b8a95e624a5977514490c6b6bb16061b5bdce3bb3328f8c5919a71095169c00959f1b7b88bcf0cd2201867b1d3f2909dd6ad218283	1	0	\\x000000010000000000800003c2de88335ce40d0a8ebda045c93195d576cefe0e96a969ec2cf4f29909162049213cdbbf356421f7db75c6706325dff77d5065806a6a4fc974bb6e20bb0d6279f9d443d561ddef27f165d46c13969cd7323e9bfc56c2b60e926f80c88fc11ead8dec1c36c3f5934379afa75dc91173ee21115718be7e47cd3730e93ef62340fd010001	\\xec824f040c5ec89ea306c7055e4f4d30f153a291b17b6b7541264bca10ebda3b48427753f3203895245661847c17a0b6dc868023692a3d63f4e82ad6826eef04	1684686571000000	1685291371000000	1748363371000000	1842971371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x1fba8b4db2bcb611d4aacbaab6a43ed010097f47cb24cbdb30531e1b0b8a42d9c9f3c4ddfa2b83ead30781fb10d808539e4666604ca438e5867ab4f513f1f4c2	1	0	\\x000000010000000000800003a17070602f89bb4ca4f58ed3fc150f91dd46b264f1ced51669ce162aa018e2d4b1f7bce37eb39c15409cd5704a3ba040ec798145d2d7fa007d74570d90f1c24100edbc83a9c08fae087e3ce2fe0f48546596436c69d2245df82c2e2f46ab0af90f12a3e64c90f6c00a5b8c357d31d5f0dc027007f06c8bc57c226bced8517491010001	\\x30756e09dd9b5577320a7708cebc7ca07f1f84e8dc98d3e44968ab6a3f62a1ee21b5466e90e895c0f49867e9c104fb0aba021753da63656a41ff71344681070f	1676223571000000	1676828371000000	1739900371000000	1834508371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
229	\\x22465e4f16a4e33d677c521acd7ac08fbccbd82f7765ca57da67bb283bf3a0446861de0ed741216219f907647de1a1c5717f26441b3070012e07a24253f1f8cc	1	0	\\x000000010000000000800003d0791242506832d2001e4219da6d77dad30a77b2fac3c0a68a553662855f1f7110057bbe165553f704e8215ad5a2e2dac2da0bf2f5d932d551d62ea59b6c9a09426c728c8176ea38164140dc3e31ff815933ff68db93753c642f49fcd3cb46866a4ad3989cf88cab8eb338d849286b713bfcef4adc4aacb5457c4800864996cf010001	\\xa20f610e43011578655154092fa19f72a37f870e4050fde1fc77d768971ec2cecec83dd33705d0d95cce8cd2bce5514482f6971995144e6d6c718174c87e2c07	1685291071000000	1685895871000000	1748967871000000	1843575871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x247632399d4524c8b8cdce510e719d3eefc9dfe12c124fa1c0df1998efc69cedf0351080e2f77b311beba52ff155206436772b78a331b6ae159fcdd9b6dfb8bc	1	0	\\x000000010000000000800003b48414e1da18610fcdfa4287028f6d1e28695c96c6778488069a061bd21606abd341ede175a0bf04000b80debb4c61f2cc5998da9a1020cc037f058c1cca3a5662b8d6ca44e4854819b184506b45a820f63ba5b735bfdcd38bbbcd084f1377a8bd416502cfd3793ffe5962385714d29a2af9f48383815bfd905f617d1fbfd5c9010001	\\xa94235288a757ac17015fb2a162aa68691909efd4898f1341669a44466c3afcf2eb2bf3c2cf1616c5de8370715e0a051a9774a0336ede69968518e14aace380f	1665947071000000	1666551871000000	1729623871000000	1824231871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x248aa332a31d183d13b2107e2905ffd84d3af54585a62c8007a558989a5a370f5b3a5868c32316f3c53395d0835855eea36ca79ecfd15c46d81ee79c22b28124	1	0	\\x000000010000000000800003a4703eef80f996695587d9dd859228de62ea3b0adcf866a7db187f76753e536afa5bd69ea9e907207892b7cebf75f7e0bd357d8af3e8b57c31a99f315ffd1b0e714df486673f8965e1f3030fc1bc0499954e215cda233f2f0ecad8cd01b11264c9f0d27eb5942f675ee80831ed5b73464566c10cb6b8deaad5d4467c914ba517010001	\\x474ca746cd6d8a068ad0e5917d20b3ed1caf477aab01bfb6c95b00b81e13d341e1f67f8e2c542d361393794b3c8eca5bff4b1e458dfe34f6f7ad62a73ce38604	1658693071000000	1659297871000000	1722369871000000	1816977871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x2882fd9afa0454c2c213cd6937f13819dd437626fd6c281a6c8167249ce3b95690b67e7c46d573d46affc1a7d899fe9cb42a0023bfa3e809b243953591cabab8	1	0	\\x000000010000000000800003da738047114c473d4f451e7877671a348052626e3786e16c3d856bc532c488ce84c4ac52c23e5c8fa139e5e334f648f9d20df14a7f847bce0dc4ad62cdaefd8b4424d2f29e93420f342e306a90cf6312fedd8826807ddce95de383ca0ac57757d82a4dcb79cd3359c3f714388fb33ee2ce8041d16bb299f0eb52560414564f83010001	\\xe4b74927bf06be4bce99ed74f5621e97775915d69f50e15d9c3a09e78f0d4d00d8951df1fd21954539a1d0fe7449646a72a87c49487918fa023e12d5c9c0b80e	1668969571000000	1669574371000000	1732646371000000	1827254371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x2ab6f29acc2b0b3a4102f06ac1b7c616ac0643472955e6ae03c6ca113f5afee3b18d148b53f3a5676798fa3fee6708fa55d7b2e5b3adcae82ae60f406a623098	1	0	\\x000000010000000000800003b9d375c832cb5cd56ff9b6f2c8ca7105a6adfaa7de6c61cc68c8f83ea0a34823977dd22b3a7f34e20c22159eb4fe0fd1968d981cfa37209a531dbb1efc652481a34aa42dfa6377701c30971eb188ade904320eeba9021da6a050d79bc7f3e121ce888275b0bb1434dd927f9080d65729bdd94741edd56a8bc9c3175b8de04639010001	\\x0c1e0fddd98be2a4a1d0d496972c04ab04920ab4920faf230f0a50bc0c7f6911a527f2567bbf9cff3f5aa07d2ad3f7c6c172b4a42c59ecd71f0e709b84bb6405	1671387571000000	1671992371000000	1735064371000000	1829672371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
234	\\x2beaae330340cd185dc6778e8b9a4e3a43bb5a5843ec6dd33d540f88e89af4ea87185aeae017d5eb6a41de89d15a5002c23cfec2cf7f24e777660916a1bda842	1	0	\\x000000010000000000800003ca6747f5f8b164c3affbb247e11893b9188551d1b74786d5949fea426ce57ebcd68ce94a9699adb02f5af5175c37ccd2ee08d7e8f0c03896f03caac99ee4c391639eb6292cbcc7f577470fdc1514448361ae97a75c7413da6cfede4cf2464de21644f191345882f1b267fdfe76ef35dd10b3735b89744b6a94529d8e767f50bb010001	\\xb335b73a1c793c174c46263ea50278a636a17aed0eab818c04cc19bd4aabd0c1dbc0591220e4920285a0ba9a3ab950d0fa880c031d24a393e48a6e721c9d820e	1658088571000000	1658693371000000	1721765371000000	1816373371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x2cde9af91b1c4ae2c3184af8ea4c1d4379f43329c73347bc5534cebb35e4eecf68fb9ecf3c5ba263bfd7e9d47d3107baaa0ff8724318f6640e65e4a45b873760	1	0	\\x000000010000000000800003c2d5e2c04095ab8d5368bd5bc6d2245d79ce0cf636bebb7d368f6a2a5ca58b9d7918e7410a23147c70339f138054b815896ab353030bd47fd198e702d5efd449ce1e16a979798b7c8f35d5d69370fc2b551ff9a848b19590eda5214fe2d82dbd0eb74a0651857358dca888b8b72e7b020243b01bdb55c1561ede8ad55f1926bf010001	\\x81938325d68076a87fe89b2dd81f912b4efdfd5a1c48ef81b111c3f21d6cebe98794ebd58bb4539afa7c4d8b73f4c77bb00426a2c93541227daadec5be071e0d	1675619071000000	1676223871000000	1739295871000000	1833903871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x2db2efc1b12d17c3a069e7a3ccf2b53218b2f6f61139fe20dc9f9cb3b4f4f23567c74ed6a21edf3e62aa6320e2140982bb5b6411f2ba60fb9740110bfad47fed	1	0	\\x000000010000000000800003ceea81318633d9ec83cefafba897d04abcf700ef45be8392a7547d204cfb50f110554e5054d671a5b553221b71ab999d325da86f77a3d29a45952fdfaa4a3c8dda943378faa3ca1d0d35ecb2e7af48dc7d63f53aa677f93cd4e878525e252d59e45ff0303f61bd67892f93e215db1ca9ac3762a915467a9edefa377d300d4d07010001	\\x8f51549daf36b9f738e110272660f80d60f4cf9e75fd2c03d7a1ac45bed33d8572a581e3b2674e660a3e8aa5bc64b2448eb767ffd45d3dc3aafe44962e6e2107	1666551571000000	1667156371000000	1730228371000000	1824836371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x2efe16cb0e4aa2efecfa64eb789399fb0aeeebc41bb464eacf627f90d458106e59174010747a81d539805063b34ab5999b5a9afe959260bfbaed95b833c6b7f2	1	0	\\x000000010000000000800003cad29395abaf175821dd546d3c36668f866253043684ea9fe02323cc494736c22eea9d89f2b333bfdc6b650a30229b40957430307b00cc5bb6a8ed09a4bf880faa84da5e28871e18de79062227a81aa7957753bfb07043c32e80cd0a6befca419306353d4efe7fe89af7f4dbcaf48e089defc63490b1a7e5af0b15cf523b30c5010001	\\x4d8e086d940c08808300634671198527a170eeb7f0aff728bfea779a3b2b75faddbe32faea73eae70e2737c236ac955ba0d1e16b7ecd5e541a4d90036af55e03	1678641571000000	1679246371000000	1742318371000000	1836926371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x2f9a3415866c0c0b8af8ba1877b121b2fa8519db0b37023d639fc26647beec87223b831eb202595f3400c1d4e39a54e3e25468a15d7620fb8d365258cc716019	1	0	\\x000000010000000000800003b69abcad15419250287baf971818acd454e449567e1cfc3a07e70ee4f993cf004819c01250687d7cbb65119db905fcb5bac28b0ee16570fd37c97491d195732c90ce3353f0afa5d95b81ae6391ea2d518372ba137581d91acebbaf61b0d2e39f26759368ded68c99cc95c9ba300419f6189345eb40b7070b4fa11ee793a36beb010001	\\x76fcb18fd1e214d67e593c1d206df4b543e7c36aa94efb663b30d048255994e0463077afc639fe1ed11e22209097bb76e99db4b7bc5ce4650f4846a99a0d5d0d	1673201071000000	1673805871000000	1736877871000000	1831485871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
239	\\x30d68a3617a196adc6f1f7c8acf0346817d2530e95afb24453f058201f2aab0a1e4544ddcdf063366e33c42964caba1a703a567ec697490f6a3d9e30675e884f	1	0	\\x000000010000000000800003c2265e5328c2313dcec722618f1290ef217c82ca1305bf8fdb32c4a2f9aa856c7590e95a09b365622b6468ef6c5f608b6f962849ed05134cd873ec6c29e930c3fb735ea6213b584c1ec1fb341e8a02e0896531431c932ab136ff218dab11099c71aaf1b01fac2a5857de5beff68a65edc5ca89addd033550661b496bf59b7db7010001	\\xcb3a46ead65f6fae2952968c16b9028e512bbd0ebaeea7329f47d971831dad0519a63bd172c5d999b9e4200fd4ef67025ea1e1ec455d4aadb43e415159985409	1674410071000000	1675014871000000	1738086871000000	1832694871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
240	\\x328a3c02f264c5dbb2d0d8e9f16451d89e29fa025a5c126bea63b84e7d02746c40aea41fcdbb1c25160f2a90048f6858cf74d5fec1d0d7bdbfe233bbaa9ca5bf	1	0	\\x000000010000000000800003d0129875780555b7c625b5e745ca112548f8ffa6d932997c237fb3355d075b083f66199e543f54955ba9431a7ec563f50b98b04698643535de641fb6de11e32e1f41f3d55f6b7371984a1689131f1327ea5c024f5a8fe2f0817f70441549a3d2fb9b4a7e8626a26e0213567d25fb6fc02dc93465eeef096c4efa0c7698ed5ac9010001	\\x2ed9a44668bc6aaa7cb7e5d8b51ea7e7e5cd0f416f964de38c8e6cc2174d335282cab9dd7fb3208ec4ec2c7a65757b3d38f3469fdbc807efc6185a0441433303	1681664071000000	1682268871000000	1745340871000000	1839948871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x331e2c873e12056dba571edd92a4156ec03de2a4bc8b4ea0420fc7cb758be89a12f11bc632892fd4bf506713b21d8b6126e94e48b4fa44b7305947e3cd6b7ee8	1	0	\\x000000010000000000800003b45db9adc4887f98039d3cd834929a7f63af1d7d6ca4032c61ffa3f0a97fabd3db587cbe6e6ed77efb0a75cd92f5dfa36d6ff9aaa45478d744c2a7069d6c93522ee7eb38ced0458659e0ddfdc42f9e9b14f8d5cdcd81af53b26dfd5b27ce3bd712763460c25f27422f6e450d21da7a13a97e47fa850e02cfa5f711afe076da61010001	\\x79c36df677deb75236bd48ffff6f522eaf72716b5fda12584565b029f67f4bdac8e33b9383dcc5cdeef3f1d616a7e597f305b61f45f8035146262182d4d14c07	1685291071000000	1685895871000000	1748967871000000	1843575871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x34e660bdc6ed89266c7aed3fd3ec8f2cc0ad084daf70576fc15580a8bf6e383dde2b4f6cf08788b5fc99d7cf6f4e9cce75f6ee337f7a0bea20cb0d837ddf7a0d	1	0	\\x000000010000000000800003a9e9aef6a96a71825026827a9fc3a02098f4fd4717cef5bccb1c41fc545aedede5dbecc65af8d00c7e02e57641726f487107ee3d7238adfd62cd1440bfe5331ac283b41753e895e903310183ad8ba06d8ccb638a337b74d62ab528a4a565c6d5a12ebb84861b0b7aefb8bc3ec49590cb734afb592ae08bd2b5adc95b09be7b01010001	\\x8ab03872a670ed185737a65f1c83fe2d4a6424837c027a34afe749c7a524399e61d3315e2a4b600b2e03f7ca15c2cdfc8fcb45ef5476772ce5b88eb750c5e00e	1667156071000000	1667760871000000	1730832871000000	1825440871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
243	\\x351e3c8c1a66997148dd0c6ad228c332bf4ad480f2a23ea2fe7329c7a1a207c17075b8097c5022361a35d0260d54f787b241a1228705042816d476935eb49a53	1	0	\\x000000010000000000800003c864f97b24526dd7de19ec86e58c254a6456232bc85b60c9300f8c0e7e6a9569882ad46306353a89ebe88ce7c6163397e19f12f8a2b60cd96b1b4e2423ddf02b0e049f0886d3950a138e31b947f0d14ef6a8e965647d59ca0518c2ec70b41da898e03ffe44fc44bf692db1ee2761bc746b2845cea80628fb6c763da17af18155010001	\\x0471a0d0bbc80d37e99fb3698c7e7e43d4bb94ac4cde9e586d5ead6875fef3abe8da8ae59af9f9aab2fe75505b79fc59ae8a6aa9fe54c36dcab83bc79887b609	1676223571000000	1676828371000000	1739900371000000	1834508371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x356a16f5582bebeda61c2b7e39bc6d32db0ba0a01490eb15dbabccc685a2e56bb088b258e6b0529cce70643ce379dca85d3075805f09b8bf2472d226ee409f96	1	0	\\x000000010000000000800003b4cc2ba0f1132efd3b75ead95c417928430759502fbfdd82e53de78116dddbb7a2707eb8d00b3cc04232a24d92f5d7e3de8c1b4d8a91ebeddff2deb02d5854f23957241ab133142947935ce71fbfacafd319d758b105e29b3e55c88aba70dbfb909dbe89857e1206ca2f8fa0b17c0af435d13d7ca00575b62acae17a484ec767010001	\\xa58c075f450e67d891b1bbb926a2b259a269cdd28181b530dada365c35755ec6201da53416371521aa288f5974b78372efb91340902aa3c27a9a3e1eaf45550c	1662320071000000	1662924871000000	1725996871000000	1820604871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
245	\\x36360cc2f11f3a2ae2afc0b9cdc12f90fb8a99b3133668a1d8e98351e2e83664ceeaad39b2b2630023a2561ef66f5ddababcabef8dba44ef5f34bb80f5ab3dfb	1	0	\\x000000010000000000800003b918c06ae38e67a0bd757dc162e557bf3214a9ab4a6c06de99d056327752f832c19824dc72dea5d26679025e67d2964d133867c1f293ecb69f72fad53577ebfbfe80b66d2a642bf8c28c59cd23da9ad6deca42954ca76ce4432043feb1e6ecda76b0b0d85c39126155ec52c5c63996b9acd8757c52137e146e0919d8a72d38b7010001	\\x4322d1e7688188c7ac2e25880148c39218e4bab6bf48c872755274380c6b7f8f133b0b78f6727dedf3b8cf562c859ae13653b8e601f0ea4435434c3f050b5707	1685895571000000	1686500371000000	1749572371000000	1844180371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x373654eb511d58255155e878717c9faf038b6dc77e83b413a0f635b1316f26d5b1bcbb1e972d7d0beec006cae2b2f96a6021a3866ccc9c9de8079bdd136f9f50	1	0	\\x000000010000000000800003a991c87739f1d37507f50f8ecb6dbf863e7bc59b5935491464deb2058ff125d11ef2f1180e21803be0609e2475a629d73309681dbd993bb888a20fb9de95e166cb044f448b3b226468bee83c6ab2ba06261733653bd15451bca5193b97622af76a2f263c36028d0a99fa0006bcf2ec522fa5ebeaac62dfe64ad90b8e8b4250eb010001	\\x97eaa1fd6fbaa1aa68f7217b8477779a8f40a778d5b9d25d1208601268bfe4dcbc6dbffe173f825bc9397b114629f800ebc3d9327f52349728f63263c13ce60a	1670178571000000	1670783371000000	1733855371000000	1828463371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x386e818809fd9057584169c10e48c3830bf9f6a858212e319dc1935d39aa73f2c66296d8b50d7fe2331633d6b51dc2e88defd054a186c5cfebb7237f36dd93e4	1	0	\\x000000010000000000800003e7d82ac9ff978aac16841fe4fcb70835ab17c534497b811f96a3a71149fb3835346fb848a55e75d50eda32b8c750f8d2e8fcff4c9687032677c37f8f48b115c60eeb673f70d4887d440e749c4fbe888f936a2daddbef182467c2f6feafe2fb387f703e7c660929df11936de1c10e5b9806267f3f44b6cb5a62760fa8d9d44823010001	\\xa1fd3481367371e17129a722a5df62bdf4352431318841ee8c0a75d0d1dfa15fe665702b224841e95edaf55819a47520f7061c82f996a6ddab9db1ec00ff940f	1668969571000000	1669574371000000	1732646371000000	1827254371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
248	\\x390a41d1f40a0b3de894b4b54d1ee60a40b5d97cf4db97142b6a87b7f8ba845657d6dd85ad24b9bac5eb743bda05a9cb6761f19987bb0a4cbc2d052dc5304ab0	1	0	\\x000000010000000000800003ea17a13a85fdbd840b508e4cf4595bc936c4fafe014042284bfbe471b15a3c19c6922fde8913c07e1e1be0c7907b55e297d9d5f35963fe413b3a76b649f72cb98477fb1ba4f363455951ea15ea2e5f30247cf83ecaabc34752ba12b4beac2358ac56f21b526807409a30e3dc33e379bbc829f964c493102ea37e69c30e9a3ce7010001	\\x11d1e0a247f797e16faf30665d9e6a45b7a302d870be3f122a2f08a4981c8cc758450ee77167f8291b20361d259394a48f87d8f5850ca7650ce49c254819e707	1664133571000000	1664738371000000	1727810371000000	1822418371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x3dce0f15e6e4217d92b01526d03d12d085d3a276208163056cf8e6f3b71af771e314d5742628d8377ce3f154efad258ad8e59e196ccf9085ae78d32880cba238	1	0	\\x000000010000000000800003d5757c68e6e65cbc6c9f2742ba2bca15129982f8ad0595c7d544c6a997b6cfb974ac7430deba1a6bbd2db2f047a9feb88ead66f400becedbcc5c6a3398d60e2857391c668f8e9fb28722db3bfe29473da3e571f617e641be0e2bffffad57735af2de4a2f487551e00c63798a23e3bc80ec4f01eb8a53e10de8b69a55b0d56267010001	\\xbcaaca6ac148e6232e8168fd263b4bb58fc5b37ec5a97d51fadb5aa6702810a141df2601ebeade8af6d3de24730c01f0a3966f462ece6af11aa46106a2feb50b	1662924571000000	1663529371000000	1726601371000000	1821209371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x3dae14a18c9e89800cc7cfd9769c3342e680465686c0f6b94bc7d4d7f71f54fada97cc5e22409ce3923585bac8944fa1d1e794243ca32ce4b310c70d18dc3dad	1	0	\\x0000000100000000008000039c6ba2b840d57df60a71351baa05e9135587f604e1309aacd5ca5803c36609def0f0368f8c711e70579029f1f348e10a8c27d9a2cdc72b5bceadd61e0be40a85132e747a79eac4ed1c5f5cd0763c1b25a5e096ba63c1c13ae2f75dcc269a1f93748668e27797300586c840a6b5bf45a83930f1e38060680f32fd31946813e9f3010001	\\x65381e2187fbbe429726a028eca4d3dc7b2be92da668b8fa32e4000b6d9739954f973d46c498ab1ff162679958ee95816e1291c5b96d511607b6b3c6afa3bd04	1678641571000000	1679246371000000	1742318371000000	1836926371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x415a26d1fb08054964a098450346d69eda92ff61023dca4750730adb8a1355ca22ff06094b4e75fe5f51cf1eed11fdd1f32448ae8994bfde707b779499e71e60	1	0	\\x000000010000000000800003bfd55347091e079022742130fd479e69dcb1727a05c493f78be063814b07c9d1bf98340929b9e6ca8bd891b359e12bcaa83af9c110db59779fdab07b3f61707ba1863d17c6756ee77f5a8dcdad00f5bc523276f522b0a9d12127b668626ad54b02ba1c86848272dcd310024a9e74f8e89230d2e54aaf48fe0845f4b50bbd5fa5010001	\\x5a8a4aef7c04ab1b9deb60f89af8d7a7c4d9e403a83393161f591e4b90ab31cad09e2e7ee0aa73b8225fb1b2285c44d9a7fdecbc6fa13db6fbc0c4c6738df507	1677432571000000	1678037371000000	1741109371000000	1835717371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x4466dd86d76a5440c4ee12bc664bbe66486f95f4aab4d1749c0039832b47cac2d4d9dc19c6dd8cf300bd768eb8f2dbc5cd9b8d9694261c719e93792776b83cf4	1	0	\\x000000010000000000800003cbbf3191597431ae9a7bc035d9259898c174e885c71ab546c3d0a5d7b258fc134a79a57022810e74f5048d66002469d6ddc215b0560832d6e8a4ea69799537dce1703cc49f4f1b4e46c64977afeb329f9b8488bd9709b446250b0a510ce14de4f3e71a5b632ba0e12e2f644bbfdd39e053e98b2ed29c61572363b0d2dca5906b010001	\\x4d8bba2c55673fc1a7c953b359f1c4bffc90a058d0fb82c32acdc1bd18409228bfc7549062bb5691fe9fc9dd62018bc9e1755b5e05ba2c4bfd20c3332a1e7c08	1662924571000000	1663529371000000	1726601371000000	1821209371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x451eef26926f4959e2af353acab446d7aa040434ce05508d066ae4e59e00b788b28161b1009866b84e0d381df7670407a8c61204cce623914ad0c8069c0601b0	1	0	\\x000000010000000000800003c26cc17bef88530aebfcf15a76489b3f11c04cec7ab4326537c0b93fe447fbcd4218819b364e074972ec1d3a4ffd5b816103f1c05533828e1387fcd4b5e3b5476a71e889ca75d2c2f88ee7f427984d6fa86b4833c2e556a23e861dad1c0a4d30f08b1885f259c7bf98f8a9a02b73aaec99dd41b74ffa93046c2504b2aa80754b010001	\\xa89830e11b18587b95c55ea766a573753c6ff719f1bc0423066e2b36a05f61cd99bf6b080bfa0ff01e2f7a64ac27aa338f650476338d3ef69ce9d399c2992c01	1656879571000000	1657484371000000	1720556371000000	1815164371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x46a684ef0df595dca14abfcda334f79ff7df9a6705d62a0cb15bdcc97fbccf72c8aa8169071bb433ad66dfae90307662bb0e096a81deb586603f839f44eee30e	1	0	\\x000000010000000000800003d21b65d8ea3040269c28c8823e7b979e4637f61a0075b4d6ca419c86971ef0cfe99708e7937fc9ba3130a8484854622208302b0eecdbf2441ec5054b57ebcce9a772683e34b849810fb6d5a6ee31d0c33a9d878e8c95be36f923c1a1f8aac5ff5bfea039382fc93f1fa49dbb1c9150363a0c0a268be0a37e65e5e8ac24c3844d010001	\\xfb01be94fd4fb61d2598b86caf1596f32d191244fe0927f902b21f614576b8e4e8e7a4a88955b9250c4c25951a767affefa451189e4bd5d1d11c4b2975bdcc05	1681664071000000	1682268871000000	1745340871000000	1839948871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
255	\\x4f5eea10214e8ec43a4a1c9fb36f844672670757a741eb89d18a5dffad5871cf4768471da4a402829fec35503671a06717a982c4b4f86ce8ab96c11feb47bfee	1	0	\\x000000010000000000800003a7fbdf100d7aae1baa36f902e8139f2f48856a93e4a24fd411803f6bd2606acd306736f597807459525128e1e85fb51313db6166e9be255d463211c633ac917afe90e07a9bd3899938fac391ed0aace46df022302c23b4e216bba4d39d360120dd34538eb3c1510f4c98eb36a3b43400dc01b998a8344f0aca13b457aff4c521010001	\\x4f0a7a0e7d642447c3e4083b9ede7e87e1c603cc4c37f3228429ade4650fc13b532c4a4d9320ee9e98e43c1fe6de6717c121b75e388c1228a6e54fc4411dc705	1679850571000000	1680455371000000	1743527371000000	1838135371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x4fdab40ab95fb0f040fdf3f2d7ef5c32d3b40a4cb1e5c7bcef5c5039801e188fa4419362c2f5a7cda572ffb078af805ee73d57cfe17ddc21f9fd41ea7f01ddaf	1	0	\\x000000010000000000800003ca97062108da556ca0c5463b72e38d3c84010136c59ab1c87517f6fd49a9cf7276d047933837d5946c86946dfebb53b43541f03368c1b249221904ab6baa5648e43aaef6fa9b73ceca3e724a22c33f38e4f00f729b8cf5fbb19c1e3caa0f6578f7e79e606ea2bf1ebf38293878bd1ac6d70506886f5372cad2ad031bbaef0f87010001	\\x6093af2a58ff110706473f692786b23be8f65df62723c65868d998b1e6f77645f24578b1580b1cb6d221b5ccd1782f83b6ce6ad5443b27487c00725cca76da0c	1675014571000000	1675619371000000	1738691371000000	1833299371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
257	\\x500ebacf27f6adc7104fc4e7582eb92f22af19d3ee3a746cf816c836b9088a570ccf137c7504147a65af7d10fce69b8aed21981c6714f0c0be4c2cf361af06df	1	0	\\x000000010000000000800003cef72e0bad084c2af733b36266e87fadd3046f94fafe2da66f35e9256b00a2f9b5c56e67b8cb0b20caea9d6dbba6beb8cac867f5cf21f5d7ef1d3616dbf44d302a12a1399a595774ac785b983a495a04d731297529b8faa898b97968b0b17b59fe29b87bf7e2eb592cfb841b1a3a097f62d4b391eb8dbf6503f27990911e3c63010001	\\xeaa0365bb41e2460382ae9e865389f1f6f334bb633005daa6fc4b46b81e328cfd1f647928aef0c2db4ca7877482d2ec116fe1e420e66717e5a07563769857b0c	1660506571000000	1661111371000000	1724183371000000	1818791371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x502effc3d7b54446690565060af57c8958fc6773142ec5e43e4baeb83fd0f13f5d133ad52f73c210d252f2c7e48bf2aea5e9e5b83bb2d3de135691eb20473d74	1	0	\\x000000010000000000800003bbd7d3ba288d62d7b7582a3ccf1b0ebb4f03a6e5b79ce959e70e71ce7addc73a9b9843fb322454a0813dc4b47c31608c11e8749610774fdc0b51526b00941c4159d6241a82bfc606957639b1e62c1644240ce437c2b49ee843a7612ea118cc43e89c1ae91198e5f393a0b124b44ef01cd7cd307045f5e995823aad49ca810e6b010001	\\xa8056e571e267d4ba31156e8980c50cadd038599d59f0c5f24d4058912c3a18c2460b8cc574d4da99cdf5f8ad42dc7758607e8b4c34f9eab89b4f3781a7b9407	1657484071000000	1658088871000000	1721160871000000	1815768871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
259	\\x563e3d626dd366a1c86a3e0a0758d598818aeaeda05696dea417e2307596274c4d12ac76fd30e6482e38081eeac459ec3df344b67ebadd92501cbca5b49d71c8	1	0	\\x000000010000000000800003b0b1967c055c6693a15c8198745204c18894145745c113f1e17416046fe4fb583a69a14bb3c30f4a1cd30ca08bead906a598c7b9bccccb12c8627ae2815ab4ce7520d86f20d8c900858b50648183cb3c6d6d077aa3ad049a789d267eed74811e7a111a9967e87188b63511e77275ecf459648c00bd6a3f49a9d8178501ffcbd5010001	\\xd147629a556dc6ce81f78b2a362862db2be47400adff62f72b7944d6450eb0ced69a8c447850cca2a5378ed31d23ba2aea2a584cce66991bd4f9a5ceea62f30b	1673201071000000	1673805871000000	1736877871000000	1831485871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
260	\\x5dbaadb81e7dd92592736d4277dbd0015c8408297fb20f1460b0801ab0e4331d6d855e95d18e329a91b7a351406fe0fefe7c86e1df4ccd187deaaf09c105969f	1	0	\\x000000010000000000800003a670828664bf6fe9aa879bc9a5a1dee0efb01630c8d34089fceaabaac8f65e29c5859a4bc8d6d2c8db21708313830023e1f3f9a96ba541c88c95428e3ddca00dc2ff3c6b99e0ddacb2e5f163212ed0d4a139cacf45cb9565a583af0517af7d53c12cd6a226c518f29efec3e5e3484235c0a48c702c98e018c35527d08c1406e5010001	\\x59c7a48b7fb49fee208d8b7f58ec7aa0313e4eee607eb7d944077a4f281e60e39413f44e4a309d892b4cb380b5aff68dcf97d96d1bf157dd239ab02a9cd5ba07	1657484071000000	1658088871000000	1721160871000000	1815768871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x5e767ae160119ee2730149a40a54217e972750a4032251a3ea28fd71194b98457d3096e67aa3c88402fca57b7cffb1a4fb42711445e1c2dcb3dea8cd770c9cfc	1	0	\\x000000010000000000800003b52c39f25975be9db0a7a647e960fc812656aa8f3e41b76ce9ae0932ce481c5b9b30518bd49a425ec90b73e8ba391c8bab54f5889b88f8536425b1ab67d17e94f0bc5240bb07cff087378d0601f8c18803ee5c6266e5bb429c4fb9c0e11521b23b566cddaa2404f8e73be83473e579520a75d64418c7b58ff06172d091d3cb29010001	\\x4bf11e320833c9100ad5669f45f923c338c20b596374d13364162c4952581552c289f53194c498bd1b16f00e0d5b2ceb8105604dfda79e47904b8b331da0a401	1674410071000000	1675014871000000	1738086871000000	1832694871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x5fba04337044e993fc45a67b1a0c6225a09d29f3f03553772cc8218bb35df2313c9b4b2f796eda115dd9b6b0f68e8eb5acb0be19d9df8d4afc44f66c0598c2de	1	0	\\x000000010000000000800003d06a2738c5c8d4c1e3db9410d40e74eab97a1d9ddd5e9c7f09925be94acc12a743cdb4ff4e0129370e1a2e83836a786af1ccc2f48aefd19ac2965b4c1baeec52f37d7494b2d6c9d35ca3ae7a081113d79e3da1f69dbd6effbf5be8ec3c2350914fcf6ff161f2b1188a55bdbeda948a73a8e91f395cc8bd2faef6b28e6ce37fd9010001	\\xe525fae582f4c118dac7621c92e90b6ca6b00f8df0a87dcd20f2e72b5678bb260c936294cc6e938e8143bc8f4948fa9dd86069266f78c717a0e15dc4cf6d310e	1670178571000000	1670783371000000	1733855371000000	1828463371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
263	\\x60a6d3dababa45528517d3ba9a1275e29f517ff0956e69a57e91f396055365c444d7f45c24bb608509d605deb6fbb40477aeba9cbd3e75976150dc982d7efb21	1	0	\\x000000010000000000800003d011f66187c936d81733e82b8fb4dd0f95388288d60990c65bab0cc2cddb8e1287576143896f743b3be3dd1aa5551ba55cb8ce01abc09b83a944a2f11c6864edbda364810096914791effb479ff3ab480afa2e326c667a721cc1dcbc4bf536071e38983c291e71bc2b9a35585d054313ff2d79ca416ddf20ab9106991ff74313010001	\\x7b7714ff8c4e8334b7751cb6486733119c862c2d5f6fbdbae3fab640952dfe3dcbc1e9a45647104823689f553920c0a82b9ee593f0178dbd3471929b030f1c08	1681059571000000	1681664371000000	1744736371000000	1839344371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x61ba99e5ff6618fac39d62f79431a973b728dc3db38e26414e23de0421029669e86adc0236c4f28bd4afaba8241eae1f2884a0390c27fec8258cf64af50a5b3c	1	0	\\x000000010000000000800003a10819e256ad84765e3eec8dbae33e86661b99642b555fafd73e8366627c2fd778504d33cf6f4a5c2233ed21f7fdc389f85c55af29c5a166b99008730c01fdfd3c041bed9603303d744760105a44d49c254d992e878922e4e1656d7ee7b030eb4a2b4a6b4337f2bf5c4aabb4eef5ae8bf968ab42ebe2d28d7503dd2b99bc4d55010001	\\x32d1db7342986b43b8f5b59404d1779411759eae1344817be4e05eee4ae7fbbf23d816580742cfce94ebc64f9ba1d6066e88c006cff5c96c22ebd9ea3312da01	1655066071000000	1655670871000000	1718742871000000	1813350871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
265	\\x645278def72b91c0db5e712344b4d317601c90e8317fd26921a61bfee04ec9ab2847728cc21b48ed8542ada4c05aa51a560aa7033779d35c2906726d21416c1f	1	0	\\x000000010000000000800003a3c8adf746a25daddd90d411a69d0aa5dd85282a282d206b0946d54da42b52444632ed82d4ba23892bc915cc1080bc8b6728d724b29892175d7c3ed05b91754977016a11eef9f929a90d1b614ced2b10b904c4be8d81d9e49a114303c5b939bc58587d0e93b48fb83c753acecd497fcb99405015ec0fd70c77c85cb61dc6cb01010001	\\x8cd3899ae9e2bad18d013706685d6c1e949f1b02afbd9ebf163483a8cb9e5c9cfe11a567b8088b26082f7e8a5f3f0b7a11b791b99d63fb2370a5a0af6502bf03	1664133571000000	1664738371000000	1727810371000000	1822418371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x65fec49067c21807756fbcf79963476e4095eb519a9b5c371d26ea2e4ec33414467e6757a9543ce98a4c8a1999c3c832a997b5a51734c5d8575764a526390c2b	1	0	\\x0000000100000000008000039df3a1778821218219e407bbe519e626ea00d0f5ada9eb8c2d3f84cf77fb105ef7ca752c29602bf3b0d3e1ac5762079ff9976f9957b5adf60deb1c042926295ff7b9abb00aec704d38d1063392e0c2b46ce094d1aff2320b5dac380fdfdfe711d453b59460c7cb27f193313d9868d080dc495704e166d4e7cfe6cecf96527a47010001	\\x1d934e2c59f5fd04e5009129f77f9140b2920fc038ce0c997c2040902cdaa2c6488a4b65afa7bfd7c96acd3ea8cf435f2946e866c876425cbe7f0b1c8f06640d	1686500071000000	1687104871000000	1750176871000000	1844784871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
267	\\x658af6eb2729741616f0538735cb158e536f9d86382e3eef24cf98ac59af724d915cf469505fcd9fd8ca1ba4bdc9249632227d9cee01674512f31dde4b4c91ae	1	0	\\x000000010000000000800003d503a84e80a63885a833044e957d13f916dc2e09707454f2c8c07a81a702800db5634b3a4cb8dccd2ee17bac19b07e352b41a27aa3ba9f3015d8124c285b50b0a99776bf2f756046924946394f4544952bed88e2954ce61607137f1af1ca33f738d2706b93d467c9859ab03e2b8e7179bcf0de0d63e46fb24bb34d9dce7384b3010001	\\x2a93d3210118723c3dab26774f4fed8f9f387ae27f8b2e43aca639b00fa1c759b1105a7e5ee56704485f9008769eac27533e23acb8ddbd5ed31c2704537b0c00	1655066071000000	1655670871000000	1718742871000000	1813350871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x657ea321c962cbe96676bbc79938305a1508948676b21f0f3513abadd67b05ff21f228af55b4890e45a13cf69589b4a0de56f5681f065d0ca021210972ca098b	1	0	\\x000000010000000000800003b577d5a83948c3d5fd16138290f23d5bb95423dc9e2694bd09683a8b7ef500d82863fced0137fb7af5ca65ead993158f0efb4c38b8134f432332a608950db32617a75a0cec2b1125f23ab6a7329da8fff59f039d30e39634793a508d373df632a86a9eb407aa0eb80214b17f70f4b4ce1cf0cdd1b1e3927f9ce1aefb99d9795b010001	\\x97802ecf9586190795bd8f6caf573b96456c9b1e58c31ce450aeda64e95160bd880740fa6cf76009e15e15fbbf75bde6e7416a73c691035519d0ac61c4e2d30f	1682268571000000	1682873371000000	1745945371000000	1840553371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
269	\\x67eef9f79293c62395b0f52ff1c075086c35c4defbcc90c21128c9564a51dbcc1c1e19056386585ce9131aa77f0763b1aff6a04ff4d5bca50ca069ebbc200969	1	0	\\x000000010000000000800003b3fca17118980be6918788244692b1948a33f8b28d90961c674ab1a903396aad07ed0d64d244f31de3dc6b1e92de90410cf211f2f1a3550afabe7fdaa93442181018458de8a4b668277053da2308bb304bdc14fb2d7ab2e7ea0623203ba536b7ed592094f60324f0b1dd572ffbee7839adec62e35cabc546ddd2293986eb1715010001	\\xab406cf216534e22ba7b10c56e810c275d803d3af14bf405198d2e1eb5f3abbb3882ffac0b1095808c989c6cd6726a03c778ee1f3b476c9b1cb3a3318f898708	1682268571000000	1682873371000000	1745945371000000	1840553371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\x6b063ac53d5e5c06d962af2d1d5c790b128ea731c533193ab3b36e077e5c860f331af26f8b07597bac4f24ca8186128cdcefe1aef0641fc4adefcb2946780d11	1	0	\\x000000010000000000800003f46de7bbda178f0442186f27c4379a57ff121e5b6c3e1f80d6b12eef6dc89d566ac088b90cc526e05072cd8add713a55614c742a9597a0d707b090958ed5516e26b7008d835d74c69fd410c2fe618b3b017183c0345c460e9b2ef3e3de5f0533103ae14afe29e0af38c0bed6395ee84315735985974aef6786428d46893e752f010001	\\x97940f11b26da939aaf2d07067012b2315c049580196e9dc9cdf0ddb7ecac65b294a0e979d37d72f51cc8deb84b0ff41042038464395795cacd86635ed6c4601	1664133571000000	1664738371000000	1727810371000000	1822418371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\x6cfa6860e81d972ac04ff47aa6d92e023ac655297d9135825b77345ff868e4be97ce6b2b9e2194e92e2fe587542fdcf2309316804c6b5cf2c3977fbc2fb30b96	1	0	\\x000000010000000000800003b22b3a0b88ff4fee57e6f090fb227cb51c7c52bdf67ddbc26a70f7a19be017b1a60e262d67f0012e1378e7c9bfcff8f7329cb0ac9ec87a7a9fefae1f4af815ad489c42dff6e4542842c63199790859f5db1232c506b89cfb82f77a3df9f5d7cf1f23fef0cd54ee3c51406557a4778e381d05fd97bcc7e4c84faf724eba3d2e1b010001	\\xbbdbed0100207a6debb501d1c7b7c2aff65fea8edb8537fca25716d58b2a48d5a3dcad0ac712c698c15e126cdfe1b96310b54c12b51278b889055c0573962501	1659297571000000	1659902371000000	1722974371000000	1817582371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x6dda9a5f322e9a06a749b93a2772e3b6e28933a92a80b9ede90026da5a48a2674734021ffee503fa575e328866691d6bea076d97baa48520cff3be8dc82cc89e	1	0	\\x000000010000000000800003d968a38d0fb3008dd89ca7b28a25371d39bbf1da52a177a109bc7936b4ee2206785ea6b0a2a557fceb3f0c6653283b8f010952b9a6f5a87164130fba306252a6d89d4ea837a397583b9f8996bd164539194fc7c5c5d1c183cc41cd12f22e0cd016957e5e4a73e00d06d12b9985d07719b8282af1c98efc2dd4f03552b42a5f07010001	\\x158b26de30a075f6fc82b8b1c4fbece643e51dfbe2241ef89302af1e3fbb435bba5237e21979626de7b1940bacdaba23df0abe72a658c612d3a243125fd66905	1669574071000000	1670178871000000	1733250871000000	1827858871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
273	\\x7002d982f13aa1b644f4f008b533eb52f812a434199ccfd4a0abc4ae6138848b2c2ae5a5b07ced61bb03f389764cc2d6230f4a15f784c665821e89709c8a2f7c	1	0	\\x000000010000000000800003e8f886428564e42bd281320d004cb86957158cd7276837e4fe8511039fb65673359f645fa4302014579a76ea240bdfa0f048cc52e333d9de3a3fb08e7870e023069a7a9f61084bca109d9ae28c9bdda33be6b1c00b94b36e7c40641707403dc9bfe634a2c3fd150454810c2d82a7763481e22aa037f21e4d8631fa5bd53d8a81010001	\\xe2cc5b87c79df0bae8997bbe5622487fe617cc667ee17b2680f4d926e54f754caafd63c36849ff1b13cc037acd83b1801f2f45287fd3447940d4f2929feeec09	1659297571000000	1659902371000000	1722974371000000	1817582371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x700a9b1d3d61966b1ac16c8c4dc8a7e9aeb44d7931f3c43154e7167de8323e86a2139e225e1c03e84a5c798581b03ab316da3270b1ca4d88c90700cd334270bf	1	0	\\x000000010000000000800003baabfd5b372a7368b24c104c44d39c8c926f1bfe81c66382d9eb2496661c47be306b378ba64a92de50cd1ebe12517ac780eebdc05f1db0810f74f7f2d99d4ac1371eba8cde8b54023dfa481949d2a3000dbfb96b86d768d35a9ccbece21cc11f2cfc431a4ec03b291f7153b7f163685830ff3c0504a5a1417b50d7a2b83abd15010001	\\xa6f00503b215354b5a03798422f10b9e135527cd8d8aef6eafb2094e24a1a7fe6cea8a34104cc5f1eba8a4d579c73b2aff4e4c8fc378e71ceefca09fcab92c0a	1664738071000000	1665342871000000	1728414871000000	1823022871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x719af789575412505f784aa4b9930013fdff6e882312f59487d1714b2a09b9bb72d163c346cabdb479119c46b9b918e919c245d94a03aaab02190a8b436fd834	1	0	\\x000000010000000000800003d1da253fa489bb696d6fb3074069c6ff7e5fe9c2dc3877323fcc6a28763e56bb370befc607a9a4ada88b191fefcd7cf042d5fe62e950736dc3a8e3a6e07a8718233cc674785e8d40833d23835d522993e0bdcdf9620388a08432befbac9ad2cedc00831726794a968f59bf88b4050b6fec94a8001d35be13ccdcd5849c6dee0d010001	\\xd49070d8ccb55120c18a28193ba54f49541393cd6f1efdb41176735e5a434fc0a7db295162fcb223f1bcc5cb4ec25fff3c55669454372ca45e7401397dfd9c07	1657484071000000	1658088871000000	1721160871000000	1815768871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x7796e75a380bb5c555c8fba2e6a4a4092471d199947894cef7f8d9246b13ea04ad46eedfb6c1c2d2d6da3a555170f9a9d7583761f6d26231e9979a5bb8b38ec1	1	0	\\x000000010000000000800003d4818b45f461c64118c7655418010a616f9ec3ba5c46f4a3af0de92b5e77f266f19113812c8439e13aa7807e983c7bff78af3d4af31f2e7e551b68007efbb4465a59b7c88ceb3ed900ca9fd47464788281625387b216eff8b4a412cf170ab325d0ae96910bc4c562fbd30cc85802962d2400b1a846d8aab415d63e09513273a3010001	\\x24c446ea4d9cde584d0adce3d5cf5ced105eae94d8a0f38140c2a6ea2d1eb8f9508e24e99c8bc31032bf36e53fa188b4c01b3f6bc3ccdf1d2f192925d1d07502	1671992071000000	1672596871000000	1735668871000000	1830276871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\x7c6e2ee1281ec11ac2c2910e2d43b5dccd828b9fe3814264fcfb6c1dda6899b318af2f7028004abf040706d4ce066849f3492b406015884ba93819264abbec8a	1	0	\\x00000001000000000080000397d52aea2b4e8c8ee1ffb2e7eb193931717d022f0bf385cbe2a4993d604c26049b5c1b2ebebed4b03d3f389c6bff0a8587c2fc6ad7f0536a0339d9254e2025417c1d5c1ab80f8504886dd7432b355440a34625c7e1fd986c4395c04aa98c10703edf12266152c43eb9743354f72bded6edfa2dfac9d30f9f40dfaa7c40e83aaf010001	\\x9b354c022212d7b1beda075e35a6f6bd90a6c4f95f0e7432291e8afd116df8ec2d6a9469e1e6e6fd4807809c8645b984a31fa5fc97b49c2c3099e927d9c5d802	1668365071000000	1668969871000000	1732041871000000	1826649871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
278	\\x7dfe237e6ecec262979409820b31bcaaa2c8e45f425e927a4e62d1f30f2fd4d95225fa21e96a57f92ff2abf4c516d5bf1279acd3b0704f18aabe61f2b5242ef9	1	0	\\x000000010000000000800003a68533757866dd18b21fbdcb31aa250d8c7f6f7c8d7561c3db1fbfdb87ac5d6728921e3931863736c00f3b2d4d444d9e1a8a329a9326357d0c034275b9dd0d7b40c604898d73447cf08c0b7a9979cbb165e693cfb741cdc37c667a33b8e4cde2a02473b4c0a8ea86d8cedc5c0246be1c80acdab73b152a2f43e2b3e3a16d21a5010001	\\xf24be5eebfce2485817042facc4ca4130932f1b9edb8cae90fdd8e867a7289a2e0aaa8bcb084afb4d21c05c2df170e3f4b25eb7249c3a58eb2abafad92aa7e08	1685291071000000	1685895871000000	1748967871000000	1843575871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x7f42fefc04a1d4ea6e4b44ca4a3addf8f8307eef59d63a340fa82558ba690571672b10667bfba26094e17185c53443b784761b000820e3074f6e3dcf797e81e6	1	0	\\x000000010000000000800003a843ebb66fe81c56462cec271b011317456c2e3546bc6f1a8562e21a7d108df979f1278d1411c074e8abe6ef0f6b6709f70455b5bd198320f239df77c55e3637cfaf63cd6127f0ce3c7b947d97e0ba5a1d760784d6caf7556d43b67b99b983645e3fe168a669badfe8a56f95ed7bc992d157cfa2486180fefa050ae73e6feffd010001	\\xdfdaef117aafdfa2d3bdfa4898e322fbb2457ff77b87fbc71761b627d8dfe285e7760d998e8941ab805f2740f4e13cd70c4df4318e7a3d44c8d7cfb1c8471b0e	1657484071000000	1658088871000000	1721160871000000	1815768871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\x7fdab87f13fdd41d524c03ac263de97493bd619f769359a12b7d5333142d0ca6086efb030cad3eeaebffc414772e2cda5df886021b84ec27bc00a30bad488d7a	1	0	\\x000000010000000000800003d86b7a006ab892c753e80453bf0169a1deda7f291669f84dd54f95b64f7475e539afbf81a0319badc9033c42eb9708f588a1678f986edc8df89eb697a091a7d1874d11af14c24f5290fa138d1466fbfc1ddf8c43dc9331e0e9eb6420c8574d7d8b5cb8b79648f3bf6cb8c2fa6e2e66877ec1eaffdc5a557085709f188bb1ed99010001	\\xc594d10d1af392a18f5692e2525e38f0445d3d673ddccfd48e289a59f6ade737a7ce41621c3cd704359e991be964dc75009e6b1997782de15d7f6afa0cd3cc0b	1656275071000000	1656879871000000	1719951871000000	1814559871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
281	\\x841628f61f3a2b70f014914d627e8954407a28690d3764e4bb91647bf3e48c1147a00fe006a4cb59e13fe53d5c7d3e0aa516e3e6d61654c73fed2a4212956833	1	0	\\x000000010000000000800003db1eaafc05534fc9b9a81d8dfabcb8507f4b2d192fc6797e6c2b7c821b8e3b184a601c3d722da619343c1a91b06b25ce60bfbc9d93df9964dc2fe6eb1cfaed5dd25c7e8c35325add385c8777bf31f87b5edbbf3df4f54de78b0ab357a9779a6c3cbbd3c97a777e3b65e3c16f2d083003bd727e0139a5d1e7ae2dd6567ed9c335010001	\\xc56649f29dee30af61b907a8ad20788e4408140708e3d798433cbc2d76716a2549c79bb76c5b3a781c5a5905dc92ef24a8cb35329b9f5bd8c537dcb6fea6e800	1669574071000000	1670178871000000	1733250871000000	1827858871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x85ae7b1c91388747d7e5cad25c5022a98e42329c9708bc65f638da01a00970e213b1aa5ca5387f81e0d1dc661fbd6b0b7c9a6fc1abbf730c3bd30f5d60ca3757	1	0	\\x000000010000000000800003b75468e798c4878d60c02d06dc27cf5440ac1dc178a1a385f39b101824728c775f834c7166e11b6e8ef42ab8da0b04df15d1a6e03f0eb1f5252021ed80bd1b6e51da65a1250c79ff1a76b1d0e18febc9ce52ea4b1025bc40e93e00d5757e9664612fd8efff0fd6a7d96ac5bb860a9773c1bf37323204ff98159d6cca990d09e9010001	\\xf85325874a3960e3b2255bcfe258b5c6fd06736d85f77f02854c18e447790c0547b51daede8ce815568b0b26c0ad35b597addf0efad02fe4524d92c8091ea00c	1678641571000000	1679246371000000	1742318371000000	1836926371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x8552c55490529b2f8649f15d940402160a83f5f89ce9da2edb34b1b48af93adab672467e6a49fcc33c6ef3eeba5edae36ea9eca2387f88996e092f2649950fae	1	0	\\x000000010000000000800003bd7d60ac0bd973e50172532d4b16234c04d68f231a1ae8daba76d1e06327ae294a2c12296189041391bc69ff312dfe57f70c11ca521a556136c77cf744c5704d339bca5dbef6ce98b2943e68ea09a890acc14480e98e846fc5b14356d34a76e16fd5eafaec8c6d5574ee8a489ac0cb3dc93a8c2c1b97d1337359442528c8d01f010001	\\xca5e6c3e8c27ef48ac3a12678ac52cc7d020cc3e5d5dad24fd30f248e1d7c2db213a44875c6b50c8a876e2d97c614725a4636e53c11e015edaa983a724409e0f	1682268571000000	1682873371000000	1745945371000000	1840553371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\x85e2857b2f58f7011ba174d37fedd05aab771f2cd3bac9a43f2b080f2e15d7cb6567b3642d66ee8917ff1a6407e50b2b7e7726badf5856661b117501571085fa	1	0	\\x0000000100000000008000039a8db8c08f5a6265775f97a150059235d322967bb52ddc1a9f19387181a16809ad372fcabb92fc8e0676d0e64e65f4c9f4d6843c7bbb406da9cfa2071f22ce0a89411227dd13f67e5dca1f82ee5dcfc6d284d09740bfb96056dea729255a2082e9627ddb7801a5d083e94ff82e4bdfae5f8bbaf1c3574ebc9c6f835649eeaced010001	\\x690940d71ab12641c06049ba43b75845f24812a281b63d060af2d47315d248a781c975f7aea77d231e23e70ad74f95b6d235883d3a07f7cce56fd6f78726c007	1685895571000000	1686500371000000	1749572371000000	1844180371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\x874af35c7d3d9c591b7eacc8827d663c5eca2152d27a6c0fea8c58aac44fd688b5f825f6ce4fc5a485cfb50383d4be2ac8db7d6f23c320acdb470cc9220ece65	1	0	\\x000000010000000000800003a0e94b5db66732e56728cfcf4db833b3b1961438dc9328b67b3aa9702ef44af16b0bbc17430e8fefdbb1370b36859b0f4e52135fe60d8b4785c22214ee67eed27355a3327d45e045ec1cb5bacec4b17cbf5369c1b3258b7f3d2f530cc226c0690e9b076d4c444dbbfb46845b8f8c72190e5881c72e1c0202b50515c490018c3f010001	\\xd0f82256e6b249893b0725bee0c81f6c5f453370b384b70b209291fc4464b559aec55991ca06725d51f3549a9588970b87cf69da66b35ab54ccf74af344b8605	1685895571000000	1686500371000000	1749572371000000	1844180371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x874afa572dc6b7686e142d4ef408262ae5154fd45127d7cba67d26c3c4d96db572b98db854ce0de8b1dd3865e647f92f0b4a487013dd93254a623bd525f61be4	1	0	\\x000000010000000000800003bef6360d92253d7e31019c24aaf1266f162f7c0310299571afb83814e95e0e0faec4a15c9a53262039a3363b45bd9583f2cd32396d1e45b3a6baf79d7b26564811ebf50cc6ddebd71087b08075dadc20f2782668d46488cd909ea108078e495d922cd4c0f93f7bafe7db9b23718e32f2e2ff0c13b36f3cca150230d197e38857010001	\\x4ab3d6580003c19837847dbdaa2a9e1a64f0f25d022f06a6d52a3cf1e60d52c164f81f536a2a8c727fda00505982b2f6bd5853900ac1f1b665e9b233a7501100	1660506571000000	1661111371000000	1724183371000000	1818791371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
287	\\x8bd61888f7a389902fd3b97b115c5bd05d3c34499648cb99a594fac61eb3f8dde74e4329fdec41bd7c12e55c068fc878b05e63c5c7dd4b2fed1e36d97c430023	1	0	\\x000000010000000000800003c512eb637d6160c3b1546dd301d78fcf62ee48472d5ca83b53f65f655b4cd0784798d0652d36e8e00b188d47033db23ccef440f71ec6e6682097dd6cf3509465a341aa506955971d4e33447b1b256b16e3c52909fd632b373bb5cf444c0b69c27f215e22f6292781350f0f3e485951d445105f4af069a784f11f189a17fb0fb3010001	\\x41b625ba4e915d5972a2e244ba10e7d2e9f54cdc143e76d4b8a2d3b31b5b8b862bd784e2f467c40061301e38ced3a0562fb4337bbc145a7f9067f9cba6b1ae0d	1666551571000000	1667156371000000	1730228371000000	1824836371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\x8bf2fbfe91d44d4c5aa951db1f23f675860577085eb8eafda43c89d7e25bec19936cf0e2fda414ae9e2f18a5f30c9052bdb524b8dd4836d7d5112c9bc309a867	1	0	\\x000000010000000000800003a531ce746e8bf7c38f263d5b705c752bcdacd8b2acb83fd7b93e3224272c574f26f0c7f2d80b8f185f7354fd4c8a1daeea0f390eb41a2b42f233b5bda4521305cd6b711305539e94ed1157696fc1ef1935c7bbc08f7b121d417b522f9a6c1a99a7a28b80448adc3a8a4f6d1563eda2bbe8640a03443dcc43549518a5b4fe06b3010001	\\x1079adb5852f1fd0514138beae4bb793bc0328e982a1409889138b0b6c834aea2a81bbfd61b11e6c389e81133e27fed85b74c58e19e93299f09df6bced9c7200	1664738071000000	1665342871000000	1728414871000000	1823022871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
289	\\x91fa2fdd5a3f8728e396bfcbc4eba6c5a85d4a1e620b9bd39726ca32cb81a956cd5b3843f06f614f89fc4fc5338d589150e48c96bb901895ab8a81cbe052b800	1	0	\\x000000010000000000800003f8a2cb872fd57a7ca88e3166f8ebc36212d47acf2cdda2451d17de7344acc8c6e290f453fca511edf8eb8bdaedcbefea574d43053faaa4ac64f33497aa6e81b8d87e87d9c8b5200a4517f3b616003c3306c165539f4cadcedda3738e1a6c68910f4eaf2913e1d82d531d18798796d93f7b6dcd41576582b2fba026eb59397429010001	\\x4449f33c0d0e062feb9f72ae24413b3be894f0aeb221f3babf7edcb2f01f204ab48c3092a1677b1b6afe6c2d326c536b4932d0abdddd6ecbf3091ea04c6bb400	1656879571000000	1657484371000000	1720556371000000	1815164371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
290	\\x91c2e59f886a6d25ac7f8498e4190ee45ab4b39ba1ab6f1cdfb0ce080f05b0ac3e7b829ea0d6e3c46b6a6ff96ae863a6c7e0aae21c3795174d5a707c316d3b8f	1	0	\\x000000010000000000800003aea2b86bd7de08def44f95d3ccb7b669915432d6a9706eb5a412354e35cd9a096593ca492086ed64040007f8ad75b60102bfeda01826b586ed1ef2de5167701466e23fd811f0cc9d5201c640b2ad64cdf3f207f3849dc6ed97e7c4837f619118b43f0bedfed6910e0c80432fc7e5d8898bf7ba605668e7ce2c311f9d7267897f010001	\\x44d37e67d6ada178fcc99f3c438d06e83b241e2a8dbdb6bd3fdd5ea9d105470c19e400aff5a762208ee93e3b69e906975ea7c9301638c5b0ba4af36d98d27a01	1671387571000000	1671992371000000	1735064371000000	1829672371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\x9322f719690cf6a06059cf4aa2576e671bf4c2ebda2048219347ae9b0c1b5b200b08f97af8329d991ebe51aa5bf2894df5ae8ba624a05e01a6a0ffa08e1573e5	1	0	\\x000000010000000000800003df807575ec9576f9c8fae52579413723da4734aa0840c93ea1aecc84e9f075ac8481e3147995307420cdba6acb97f20669d4387b788b15b79be1fd5dd3eabcf88fb0118b23672de1f2c20b8177dbb42819c8d3e7d79943fe41964b53092a4b454a423dea5529335ff14ce00cb6460da5ae4640f745e61f65d0d0100758297167010001	\\x0933dbb7b1bb337dd109dced2da2622200bcf2930ae43cdb3ea66e5a0ae4608088010b18efaf7cd0d4e09da7660e828e93fcb585485d68132942cefa778d910d	1664738071000000	1665342871000000	1728414871000000	1823022871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
292	\\x96c638de0e984aa71c11626ed51a413ccb56ad9323558e88ca8da4f605ebcc145f2e4cd4a9a7b13190538dfb41e7cdc548a31852a97629b01f0245fe283b586a	1	0	\\x000000010000000000800003c5b4add3c4c3e54a82b9fcdf610cf31f583d765e4295c520ddf60b14c93479e46118cbe436d3cc67b186d731de484a88ea5c2720ab326779be6ab49a3f309777facd6c578f45a961095a973930b2b3fda229308de6565edbd6edeb621873583aa708b0ae9b6ff0eb21b831445404dff7a4a4fa08e62dcd8788a5ade91b302bb5010001	\\x1e52f5edc2f1e52563b63fdb3858a00635cb0201f83c1405c357007b8f4d781c27a8de22aa7221f916f24f04616efcc1a3c202604d13b49c1047e9df0148810a	1678037071000000	1678641871000000	1741713871000000	1836321871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
293	\\x9a86475faf802976be73de6cf3c0d00df7f1dc82f7d242f1ce60ad00f96ea2f32c4f523546fe559f624b01458082f130121b180f53fcdc813da87981d7ca4eab	1	0	\\x000000010000000000800003d99b52f38261a4b8913ea4247aaaea6d2c4e1c4d7e41784fe6c962779ec98ac621a65e8b1240264b069c73994eebe7114c3ac8c196d46c629238e8530295e248154c455a4c1da72f2c0e3d7366977f4370f98227a827771520ab01de8c91ef35d2e38d67adfd9282e7b6a3c618d3e411bb8c05f3d99adf0b4bbb730b7281ebd9010001	\\x482bf20dafb482fa335807d5869b01fbe898b00ea1e263193e4987d1f9d0661b3b2bf7293d5cde342c8ad7a4d195a2088700a358e9ceea36c7cf28aa3569ea0d	1670178571000000	1670783371000000	1733855371000000	1828463371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\x9bce276f576c41853701b730929d7c9595fb2af7e821e94e491f6696b80320a9c90f9a10986f5f9e70957f42b1745b9722539b477c03d4e1e9d4645147a5573f	1	0	\\x000000010000000000800003a87ff788e8f41d9c795dbb2307ed1fcb803c4958afdc3fa02df0525c4060f0a4612b0f16d6557de8c3f6b4a4df3955eca6be7b0d8aeda38a6726e38cf6d7b504cd446849fe424ddb797c5274b18f2e0f188affe496d4a709c5b19c0538a65f45f83b522f06bf47f8ef5f62a00642942177cdc9f4ef969b6b0b1f3f7d4773c811010001	\\x62fb2db36f50ca25ad05959a469fe84651c075a3e60934723a1f6bcf76c19556e415fab649b7ea07e0040149ecdc35eb981110670cd160bafdaeb85a0192780c	1686500071000000	1687104871000000	1750176871000000	1844784871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\x9cba9c7bb811d199b33d42b80294b90156b40799245ede6adc4e64196858c42a22936b0c0b863dd363423e2845f53912f9e560203ef70d2102e1e40a7ea5d387	1	0	\\x000000010000000000800003cfe840f99f38d3d978b521a60768f285639074d9a48624560bcd905c0c8337fb5b6b7c71951a0960a43552daf6427e333506b51db1a71f952f33b1c737db3aecd25fc720c193a3b8a87a659a68b237d131237d5dc3766249afc17e2ac7f4efb1b3291fae865c0b77de47a8140e9601f32d14662aee3a2e5ae640156c6a7f5c0d010001	\\x0563ffe0adee03a1ac6f7fd4425af1ce16feb2c9074f43aa4612d21bd6166c4f7d76487b90847246b6827a52dc9abe954a6e76b9ad56e9c597fcb54625798a01	1684082071000000	1684686871000000	1747758871000000	1842366871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
296	\\x9dfe791dcea5044b06166534cbdb97feb2662ed52ae9202f693a788c6376a6abc5cd5d81c4c8c55e88f0a275e9e5f94820d05c1ed51a14998d7540df120e7954	1	0	\\x000000010000000000800003ec6411072b7735fd2b3d4c465a7aa2d41e37ed3ea9774a22a6c942287849c4ccd071282791c34098fe71b2cc362abc15c109fd89e48de67bba8148853d9ba294ab1ffed2c7261dcae804e4a0cbe3dea18219c4d109b7225244e6c132c07609aae0306e2aae2304aa81e9cc3709d80c0efa352f228157c11e922ee69283b3147b010001	\\x826a120d032a7b956aed217437e5586e92b644e525c72d6b3bedbaf2abeed0395c4408fcc45120cc28acbbb99662b3a82147fbb767a042707f685d22291cc105	1662320071000000	1662924871000000	1725996871000000	1820604871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\x9d36082156cd34d153ce5be68c2cd14b7244a39361ab53b976a6bff377e6585fe61d1063a7696399f7dd2a7a310d85322e8eb597ae8fd6a674a6ec475aeffe64	1	0	\\x000000010000000000800003a343a126f64ecc5cb7642116120ca0f04910abcbddbfec161e032f666d8a91fe436ab6b16dcb320fc1e996d1a849ad212458ee11ce1130ecb60ed39a4361ad1e12ca8a1a8bd01a7beaa5327af3c6f8d24f07ded3f36e0c46b71e2eeb917a95f640852226ce69c55ce196e3bee0c51f9766f02fc4c46ce5b828e6291110bd694d010001	\\xaab92035fe2e505887461cfd98429a404cbe7cdfea99d65f603ad8a468febe5ccb98beb103bbe124190f3394d91dcb708b506642918a9be7ecdcb4235c1c8000	1676223571000000	1676828371000000	1739900371000000	1834508371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
298	\\xabf6a3d0f5034ae68e779c7de2fee2da6eb1bd7898b374839632a5beb0002cb47dee5cf684c562ab4611006b73863e6d18e1a64ee037631aef4a9bee0753317d	1	0	\\x000000010000000000800003c824ae4200a5e3699f9440933c9aab4e1a36c6af5b7cf771b037936cb58d35079efe2c9124b9d0e15cafd49135492e0fbfd1a796b2dbacbe309dcd7637d032fc7b8f59ad211cd5e2e2c274c84c7534871f788699b112f82b83da5aaccba2f6d754b991d7db25d1b98e9cf4d7ed2cf0f8571a1c5e799ee7d9412a10bccae59989010001	\\x64c09cde5a9196774b10401990581a3853f11deda71db2db930568ab3fdf30000cb5f47153eea0c0d051b3d3909640c42407b37747f2380ed6a7c12b3f4bc70a	1674410071000000	1675014871000000	1738086871000000	1832694871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xb456e57eeb68e0d952f65960e126a00aed8e41dcec7bdc8ed909ede5ab5cca8708507f8fd2f1371b4d1ae35515f00d4d18d24de097357356dfb4959bbc11221c	1	0	\\x000000010000000000800003b32466869278ba0a993e41a138308e66b5c51c192632e99f1562e2d2ddda5527c1edc5d6687bc94df0929027ad8b6e27841a8d91b008e44379aa40e4ad145868ac64da3cfe7b1bf73209d64e6c9dcf6ef008b25184bd83d4aee600f2b050b0e531ea8007897975b2a5bf134dbf07cb0a7f41f4ec4c82aa2ef88961815a98e5f7010001	\\x4d6c6e8347b4d4872521d558d86ccbe54c69d2110381d2a73434b08af63a031e9155ce2a1ca7d498af47594758946472fe124899435e9770cfe709bc043fe60b	1666551571000000	1667156371000000	1730228371000000	1824836371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xb55632fa7e9fc9aaa30573a5641e5d49f5e3f096576fad7de9f9dc9a9baf51717a936e729d4f6d0d0853327d9dee0fc96ab89e1ac43f2155d812d5ede8a87b9b	1	0	\\x000000010000000000800003cabb1a7688e19ae480baec3627c615d0a8fb9d58cd39de23a02d4edc898175226ef58f86eb8dfc2df538e304e2d72986b5652d732fb8516b61f50a0bf39e64f16ef5761b017f23f73e586e96f5927a506d06342893c3a8503716245385c0826b8fdcb6e4bfedbbfb3ee639493035263b7e44d9999937fde5770844372bcc514b010001	\\xfb0413ae1d93c46c3206e01b4158968a3c7e42dc74db29b12343e5bdf5d9f6e6272abf427064c0836033d4dcf47afbaf57bb425988082ad5dca829a7cf40250b	1675619071000000	1676223871000000	1739295871000000	1833903871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
301	\\xb6a223fa02d4fc2faac27af16c1a3b574252019c424f52bab32fafe260eaecc091762e994e6b81f0256363c5f6e65f0030b83f6b23c62c6986162b0770f0b5dc	1	0	\\x000000010000000000800003dd1941e0a46bd69f85b009d7b6ef8a8f6e563ca59350c7aff99d651771e8f6074ffe23f786992ba49f2510620e29ef9750fb705143979aef9de58a1067c3790d44035f8532449cf14d38eb3c8664a60dd3fff31a7b893c4f984989a00f994b91c92e043f2a99a168457148cfb2577379ee043dc40837fe24188229d03eb7d869010001	\\xf7d71293e219b4e2558b36e4ac2b411006c0d0cc7b020cb7b74087a06b3fc790f8b5050dd809e6c061f640eac6e88b61cc516deab31c27d7362c5549eb9b8003	1685895571000000	1686500371000000	1749572371000000	1844180371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
302	\\xb78a553555faaabc9622fe74f7d36df32e7f1dc8b9389558ff8aa127f01f56041ccc6f14a5ce7164944ffe8ba6ab4d3291dc125271a43b3cb188e813888347c0	1	0	\\x000000010000000000800003ddff407bef72082eeeff7ffbffb2fb9b847da84f1708899aface0dd16a4f7020e08ca3bfb0d7e9e1423606f1dc6d16e8085e504e8814b778a9d261ed667b99fd0011737895ae779f5ba64678e34c14d45bec37969c76380bfaab52f03564a92b40fef8bc47adc827dc00bc1530c1fb6105653f606558b2060228840a19bb14a5010001	\\xff7e310a1784c38daa09499272adf243926462158edb0329f59a8245a2f8daa5747f64d7b7169f9dbd431f7f4dedec9f67691512e8c69d5d1a2832f6ff45900e	1671992071000000	1672596871000000	1735668871000000	1830276871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xbc3a3cf1fc5e6058b799e9feb67d4641e498ec3d8db8b345d39fb106802944f5105fe1ea76c8dc689b590e8c9a722802944ebf91175284d5a97158be729e0b3c	1	0	\\x000000010000000000800003ad288dec97b594cc8e2d266984465b519fffa1422513e1cb3fe484ebe7f3dd34c6199a4bb5820f50fe59f8a49c66876afeed5f5c38d8b9e32d1a732da8089af950f68f118caaa5084b3079ba70de5ed5584ef6423c180c562765dc3220e611a5e73370e32449047abb98bdea47de41ac58e889aa5915e00b639f7816035305d1010001	\\x116740148cc094a4da678bc01241e1c82262fcc21f0f85cd230b7c603d7a907cc3f93d6e4ff08bc7ef922b7f63fe21bfd120002628a3da48db96b39fc01a1903	1668365071000000	1668969871000000	1732041871000000	1826649871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xbd7e3c702fb9223047bd145d92c9c6d65080e4658acaa70140f3ca9e9b56d014d3931a52ace4e94d2d48305923de375fa6499f68229007f7609775a8106583f6	1	0	\\x000000010000000000800003bc264f516a8e1ff9b8c74fcc62d3a43632d65c408649c5ae02b429e3d94d1e4ae217e38c3ccef0c67dcfd953dc4bd843d7123cd00209768036dbf510caef2a3ec7ec0b25ef71cb0a99d6241128f78a7b45e985d190c6f80c4662910cb209754e65a7d1bbdd832583009608ba7b45b52c0543dc42e90df8bedb29d9a84194e677010001	\\x1594e33e56f9bd17f5e5ed6e6edb72025e2c025443d11bcdf215919ac05cc87a6587eb98d0001f58d31f4ab86d45b92b8b6f8bcdeec314b3a7fe78112b04ac02	1681059571000000	1681664371000000	1744736371000000	1839344371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xbe428c729d8aa4f8e1c699921bfbe7996d689829bd9409da21d71ffd0eaace93e77140f510223fa863fde22c090ce4dbf3fa876062456066ac980a842607f671	1	0	\\x000000010000000000800003b3fcd462d8a71464381448bc0d0e98bd1c529638dcc9bed26bbb2b996c4842ae20cfd714df68b7b2ab488a48456580c2905002e5514d9a592102867ee98eb7fad715e4f13e07b702523ef31c2b735cb4acfe3d8177df63010fcfcf836be26f850aaed06f31d01f483c425dfc6098b00f8074648d20e367609231cb4884fcb84f010001	\\x02c92d8ec10116be666b99c759bbc870c1a2f05cb14f710a5bb64fbc47962e79cda8c84529af94583acb6a6ee1fad7beb3426bb294c1f2d55106a9de2140160d	1670178571000000	1670783371000000	1733855371000000	1828463371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
306	\\xbf9ec73118ed5a0bfe1746c69396fd74cdca235ae7fe8f167c7dbcb007fa4211d2bfcb9ef86bc1494d8bdfc7fcb69c462ba1571d56e7af12ac5707c666411b4a	1	0	\\x000000010000000000800003b4309a519902a1629819e2774232768caa6333fdeed062b6cfe404042bf2ae41e6a125a74db6686e5e367bb76d7848d905fb625cd0357c146f901eb38c0161ba4e471c18cad96bd9ef0102a44a2c9e38ba1ce32883c09b366fe25ef21638dfb062c896c1c5676127511182835a30a30fb1e7b8c4854ff69f1ae1ebd318947899010001	\\x4740bbd366ea294bfec293124f450c81be16d72acb5de612372cd53b7aef50f4541e40d3b706fd6b8886390259209cffbd91e9368e1ef3eca760cb13fb10460f	1684686571000000	1685291371000000	1748363371000000	1842971371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\xc2daf1ef24f01cdde1d2eda76ef8fa1bf94c8beae798cdb9c0f87405587d865d139cbd0bb1ef69107e89c23ee76aa2170d42c7348d4b5824dca03393a5e71409	1	0	\\x000000010000000000800003a7025d7b682694f178663bf03199a0ec228ceb19956bc175ff208dba52ed0e462ad78c27456737f381813e365935edc6137226591bcc43314b22e41cf39a69b1a120c81a829469f4fe27ab1a09850bbf45d80d33c155f7210d7e4625c9ec81ac9fde8e422ecbddaa0b65969490eb344b55c786c9dbbfdefec1ff6b7f7e9708b5010001	\\xb0bbb004e47ddca09c1578eff04b0d4b1ece21bfde2119052b851ffb40c4877cd7eaca41436f85a65cc6c116d5abb0b9e83bbc8a9d32123daa8778b1aebcc20b	1678641571000000	1679246371000000	1742318371000000	1836926371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
308	\\xc4426a188ba935246ff97b8022b22a17506cd39012059231c2466e2f71933aba9c72118a60cface014ac85cbb14436c4705c1ac882edcda528d95c8de4394f3b	1	0	\\x000000010000000000800003f351e5e9a1b77f646e803d188003d8248f605ea26fadfea1d1031ef07e02f2651267c690bcf370f27f8d8d6dfe558e6c4accdf1b19d01bd178290f853fb5c3532348b3ed39a38f3cb4815a68d54d5ecf60d6ca84e0530f73131dd00a131f91bad9668370961eacb5ceef9459df9409a979fc6f9d16d3d7796b3a45091d830077010001	\\xd816f76e0c8706e9092b37aa9e462edc48fa0e10dac68a85248fb23ab6dfa1a0a80341a6ec52190765686876999269ca78aae4a619abd6ffbdeba1f98a5bab07	1675014571000000	1675619371000000	1738691371000000	1833299371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
309	\\xcb3640860990f5467c5b3716285a6dc06bf44ae040d4323d0d662c7cd075be26b2b8386557a4863cd5740bc5d4b17e513817274de53a01c201e60b8fee520e7d	1	0	\\x000000010000000000800003d8c642d449bcb49766dc2a02fb101bafe0c2984331270d99dfbf921cc97fc2e63c25c97877a5f69f3838d15ac699a065ddd65cd19f8a009cc407078071ce1f9c7d89ad84caa8cafb26e2cff70b3c874d4a4cfeb1315f4065f6290baadc7b19ab52c530bce13030299068ed01370c9222ddbc6a527ade3c8d13e8b61d09917b11010001	\\xd9f03b06207ede0fc9c8b73315f84ec080bae345af2eeffc061d0494cf2d3b0e73019069b1d93184296bff527cf01fc778a39f5a1525f6a235eda73cb737c001	1677432571000000	1678037371000000	1741109371000000	1835717371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xcf4647b308929bb70b4e8dc19cd81de2e0a79490d654702f81f2f1a1373d0efe1442dc46a7957335881c960ce7e16481850da30c1a97abd7894bed222445f92b	1	0	\\x000000010000000000800003b4d77e2bb6df3d31d224c4b4879c540351434e4dfa2bdb777099fd8600d42e845175df04bc1792da9c2ad5a823e0506ca008abeafe988c7b8f5af81ddaacb177aad4bc192e6d5ab19f36b76576141d776784d6dc4c1e7d94319c075b6c1dfc59945e868abcdd15088a2fd90eafdc6b252517b0b7925ed8c7f76a7b887294cdbd010001	\\x643477846cb730bb040e3f6c2cbf02cc42c2e962bb7e33deb835dd6a0924a84d65c7598f94ec30424f09e388f6b96e9690f706efaf3e294fb730f8bcb7f47d08	1679850571000000	1680455371000000	1743527371000000	1838135371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xd0e2ca54e89a4c7b1911f3018694e5e3fe08f26e0f94de586ff6b418c0d129e85dace309f7f7226852b8583b1c6f506a16bb81b37104141c3a64c458ef22a1ca	1	0	\\x000000010000000000800003a981ea9fa5611360bfecd478aab915ddf891d2e93d3155f25868b97c21f05e250bd6c6a5b5663c77b76f11fb62c0c0f27d9d5522813bbf7246e05efe5605892b4f1dc188db5f2f59c9c1640f7f1bda8587757fb017796f4d1ce9579dbda04eecd26e3471b8e893896411e54128f2801bc8b878cee0c2898c6ba581951cd02511010001	\\x35f53fb86472467b20eb7ad9e34981c3ca87d8ec99f28a970ba0c290386eb1b78fb2e4a1e7439e3a1767ea3c5b2bede44fc32841d46d8cca355f1a3f7458d400	1655670571000000	1656275371000000	1719347371000000	1813955371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
312	\\xd0fad3f6b94ed07ee013ea57bccc6880ed80017ace1924375810bc3f7577bcdd2bafd1652f8fd12ec33cfe2a8c065110f5e5d77d57feb18e95b27080078724a6	1	0	\\x000000010000000000800003d36fe1a73107a63218bc29b64c63c1d1e61e081294e56bc614acea5b4277df379798ca099f6e838298a861d9b5790bd8bd66c9efe395c4c1df029eea8f14118b5eb8b092a706ccf6219c6e5a92e27f2130dcfac84990de0b1f362b434c862d6232e9f3b8148e6b40f4a04cee9d9947aeb9d634ffad60f66e529f1433259a0491010001	\\x8206fa99539f3da6d5b6cba3a4c7ea5e1440e448a91ac8741f90d9afef96c0bcff1182579e268acfc17f44b2db81bc8072cbd7bb6cb6e36e4d859ffd8192b90a	1669574071000000	1670178871000000	1733250871000000	1827858871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xd4ae546e2e7051cd306036488b84310a271c1b468cde59c9a6aac8e27d7e77ca083e4e65e82639bc0fb6b4eba28fcbe0296b8a392e1ea2c0afee124be826083d	1	0	\\x000000010000000000800003be2e22f4549f09d538110cbd0ae38e161fb51ec4820499d9dcc4fba98abf70851954f4980f26e779e9033f92da04de966ce3b98c270dafcef177b4db10b0a00c67d531b40c9ac67d303e6852fe27f746e8b708dd68a4b9fa407fd3ef6b09dd160cd6d6a91ca217b3f225a0a79bfb9b8290d1afa220eea235a11e04af055f0e9f010001	\\x4b7961bfaaa61853b6df61918277d2f5403a4ce22ee51d0d7d03785159f1e1ac08e27ea9fff21531c000e6d5e765735373bf45b9f9941742dec7f72c93cec902	1662320071000000	1662924871000000	1725996871000000	1820604871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
314	\\xd9c6e2b3d8bdf78e08588fe429fd7b605460dcc4b6608b5613228b65ac2c9ffea126e6e5e0245c33b9bc26015098d8227f6780219fc9bfb24eda99404bd7fe44	1	0	\\x000000010000000000800003aae6ce6999254de84ff7a80566cc9587265203094d8b193444469a4a49cac10b3de726ed3ef316d9cb90429430e7479fe0277459b37eca9f193645122e52b085e83dbcc6b8e75eaf58f720bd1092a2914fde296f01d3e287d616d30d5e119009ec0dac44fb4ebb7a4c724de0d59d124f4654f869673ecbe78897242e39361ef5010001	\\x2fd236f8590707f05a2d044878c315a86591271c1ce6e111f364354dea8afb446afd9625ec0ab1183320357a1714ad30e9e8a695368ce815a7f923831326450c	1682873071000000	1683477871000000	1746549871000000	1841157871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xdab6b63d81bced3bf056e596ebaadf20ba0f5e81da1e5a65ea5dcb5b768692f422563dcbdea2487913e7c2d617afdc9e88ba42480c401ac1f192bb353ecb0753	1	0	\\x000000010000000000800003fba5a4d7b9c2cfec52e3372e89617a6cdd608777b2c60c78682e3f3f69b0b9502be195c4365020295648b8dffd8a849a639160840c97f5fb33f4323089a916d3c3793695f67b8296dcde83e19e661d9f46662fcd4cd68d88923ddc89af0dabb93d6c91e85a5da4895219d65e1ff0c44f68dcbe004011d5a4220232f771a4aeeb010001	\\x5e7bbdafdd979807218881cd5619e8173b54a2d2e9d51f1166212ec5e713127cd0325a10b3b8bfdb272ebbc02ebe11a98b83234dc3ce611da3d8ec30cc80ad0f	1676828071000000	1677432871000000	1740504871000000	1835112871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xdc3279b3c7357f3fef0676cee7d65a4604903da857f21d35f90a4346a21f98dcc72eb23fc221aa737d985b0b625a655e45d47236be32b47a1f14c4724636f830	1	0	\\x000000010000000000800003c6d936d0ec1d5b02b9a47853c34877704e26970ed9e5bac99f40914ec4b2aea7155dbd994549968aaf2ee55e270fe6867a28c1e00da7bbc1b93eae2a849e12c3f1a81d14283b35bebfb653cc00c83215e218e75efb7209d8c57a6b2c66a9803f45208030a37c47e2e313a9cdf8630bdae2a675ebc1db4deb273a55b480464fdd010001	\\xc1c537ed8509788710d47e787e20853ec543eda097f256aa192b0e4919d7054c687c3811f4ffadea7772fdda1cf6e4b05e9fa2bf71c28f0c417c11323bc1600b	1656275071000000	1656879871000000	1719951871000000	1814559871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xdf9a02240611930fac50c6e6e9b9bd398c861957c19316f2cec80aa8cf9677cb4a68a65927de1f0b867db8f411862647b474456b591b736a644ba263bcc6f941	1	0	\\x000000010000000000800003a7affa26cb16213b05bfda6a1867a3b6710ea22056c926300fba536e3f0ae7c2313ed72403f9ddbac68d03bfd1668dbd5a50b0d4588a0dbfa40a39851fdb58065979ef12f4dfa89e16ad1f1d4091e093771a94c30438206fd1564aac0111d51cc90c5172c7c01ea8928d787f63e8b5a8e3acdc00d060d3e9825b15d8176c535b010001	\\xc83622df5cc2c3d0818577e1d542d7fffd84939cd3a2a0f5e55b066b8bc79ce9a6073d339fb45c1e17fb10f846dd69e041965c2d6b414787116403688c31150c	1667760571000000	1668365371000000	1731437371000000	1826045371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xdf5a69c22e54f053b1882a373bb8c9489d653b4da0cacb201dec79b82a5fa3d1f7373215bd5b96975e7d7a2fd173d5aba6d5985142207bed45a9b5d34b426655	1	0	\\x000000010000000000800003bb5b58c89196b39be1fc99c7ba544d3a680a98badfcd6f429113a4abf9a481bef9ab48322d246e7eff080f8a00020966ccca5434c8ff9d4d2e48bc65501877de3ce14e39ca1660b16f63ca7023d91354abefdfb6738555216462c3cabec442ff043392111044ceb6bed54e0e58d9fdc451a34f07e25a7486ea844db02c4001a3010001	\\xe3a99435c122cd8bd54932decd6494c5d608d31f879605b7d5d7c54f6dd43cc93274a7ae12734fdf0d33037e1504b748b786cbf03d280f9c0e15c47df760460b	1665947071000000	1666551871000000	1729623871000000	1824231871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
319	\\xe07234bb9879c5eed5e1c8ae65915dc98c538cfd73687400392caa78ee2d5b1b54d72c0706763570348217e810812f5812e00b0499ee910b04884052a942b87e	1	0	\\x000000010000000000800003c04f12757f4bc09eae8bd5d52e9821655c028e78eca7b1523391d946bbbefff5a486131a2e3d1572dfb8ffe1843b2f10961381d9146c94bf25e084b9f3ad031c69552e0b012d84f527c9f5199d6cc014b9688939a65b41a82d3dd1f2f8791688bcd14f17f88b9e5cba44f9032075b3a5291181fc7f3cf02bbef69e86e747dc81010001	\\x4fc50fa94622454162a962628120a857cb18aa5ad38a73782d4bfa97a6a3738a4b35f11c6cef7686f251094b335fcaa707357e7d1c7c2869a63ed1308f81340a	1662320071000000	1662924871000000	1725996871000000	1820604871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
320	\\xe36a87f820105412cf7a7d53d997d6e425c191f647d8a656df2cf965a996dd79175e8bf10e7393fb6f4e2fa6a347aa010b7a2a9e46efc7d73a865998c24fa973	1	0	\\x0000000100000000008000039c836c86f7fc6f8b3082640c54f90f2917b07dd789131d1c137f70fb120d201a4508aa13af36467cad7a9305e747018f4fbdc30955a829e6f320db73b168b0582ad22bffd7f4a82166f6bcbf8ea8dc4767ae47300168b501712f5086fe3cd1d3c43cbda3a14a52e992dd7119e5a7ffa31c58bfd37ce893dd9bf0d74147368f15010001	\\x690c7b95fd484ddd4cd1af11929c40946b720b974972209b14714000d0420f7c4304ae01b71f79969be0ace46e5c12053a55920bdc46d6003474cabf97880c0a	1669574071000000	1670178871000000	1733250871000000	1827858871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\xebc68f6826b31b4611fc50dbaaf07bb0c7beb0b9c30ba405049812097f94b3e53ac0b853900bf251833c5abb32d83b8a8fb33e76af058e7fa6ca92f36893fccc	1	0	\\x000000010000000000800003ce116ee0c00f1a29f44ffb6e6230d944db4af8a5d823687405ced0163bfa65c01f9260f1c1d4de0455cb6f071512587012f367992410aa5a1a73b7b0cb4bad7e9e712a544b9435fab2700bad865d28249425f33b45b87615f21b9a75c3aba1cfb1133679d0f5ecfae8fda58a019a53c9cba2163d84f8966d6feb9cb7fc7fd36b010001	\\xf1f39a3939e44b8c66540e49b067a2ce60a5ee2439157de16a771b793ebcda150f65532a0d74d98e1cb1befac39e354a883560ab60fee0ba40100b3c169fd80e	1671387571000000	1671992371000000	1735064371000000	1829672371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xec82ef66f1d96322494cd48967ebe2f1ed99835a6080041d85cccc39983fdd751735c07b46a127728c0457f48511c95ec6e1ffb23d9207ada5d3dae1043ac3ee	1	0	\\x000000010000000000800003c442f12d10ea9983b4519ac5cd9ac487e62c2c403b95bcd7908eef445422bfdc503e36b5f27fbd2591119278c36bfac85f46ce1940e1fde5233d82590a2b438522fbc501af995b2e49c90e8f82ed6a1344ea256d87e181c298f6a984b7cf6396025686f57297a0be5fa946025311bea2f54ebf9ff9cc988b867835d53b6bb40f010001	\\x30ad09d591d8c066413e12488c99aba1080169c4d51577f1b1c9c8f47ead715b05d7f1c0ce8b8a47c288f2905494abe0f7a7756999a1f6bbef6da181fb142d08	1656879571000000	1657484371000000	1720556371000000	1815164371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
323	\\xede6c306364cc8ecd6a12b0b7432842875bf8ac52590fde6d39da2f89b2477ab31bd9408a4d0d643207fcae712b326e6ab5e34bf355f8c4de218c57627d8efdf	1	0	\\x000000010000000000800003d33f1c9710d3e0b0ba9407f9eca2b10ec7220d79caec52cdeca5cac07a6383c7c2d4246459bfbf97aef0c82f663f5f9dde2b9fad2a286efdda916857df55ad348fadf79a7c2c7f8fcc68edeced4aeb11f498f884f372a9ed978be62219a9437cc9c261559d061dc57f064c3d57360731aab5ec470eef8a336b46a36b47a793ab010001	\\x8ee587419053d950bc67b6d6ae8ba85c568f15a914a5f0cee1def8f48bffa1c09dc5fe07ea8fb9ba6f096e20849d7ee03743bce5cfc703b3a2cbf66b62f08e06	1665947071000000	1666551871000000	1729623871000000	1824231871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
324	\\xedf2088ca927fb69d2e57be09a8db563e98a16e85fa02ef7ffc77cd9a07cf488cd42fc5bea0f110f4cef6681fd5f0b3810308f55ae95eb2ac727f19292fbf63c	1	0	\\x000000010000000000800003ac1bb6b40de94f6686fd9f4a13886da20ce3d4a5927066883402bb6a7911f9fcdbe3605688e0150b1235a07e4e1d3404bdbec33fca5b802960cebf0bd964882455448ec392106bd6c232d140703e41ad0dc60aa2f4e74066b1d975ef800fec94b57321c7a1062e7d2b3205b3f95278f4fcd12f10be70bbe1b6db97dd4a185d0f010001	\\xb2b8cfdce84e5b920eb5b83c5229374b9ae4edb0e41f4548335b4d9a8403e58e56d9d3f1a92975ace4635a0cece0a979c80e7258ca13211988bc4ab866a98604	1664738071000000	1665342871000000	1728414871000000	1823022871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
325	\\xf0fab7690490f9ebe497cdb767f737994354ddab0ea094be482676809bd67c09df89f75847a2c622a9b47af69a4e885dd1c3a2f5aa89ded1e0f083d51435f82f	1	0	\\x000000010000000000800003e60ef68363dc2db2b11f4ee22dcb2d3f1e462335e66766e5c24cb6ad1a76d82df69a790c76ee3e29fbcc5f45b9fe88e2468d2b7c499ba7a3f957b27e12c853259fdb5f2e22a732cb3cae2613fa4078fe3e2a5c781b4536b686a02013831802d8e51c55c3e5698a2954fd792351e9f8dcbf80622e48d97979aaadadb773f973b7010001	\\xf0c411e7897b55216a628bc754f9cea738caee30ada65dc29e6eb94166422a27d8c4d0d51b92d491e82be641401ada1775e06114f55db6c8b29366a023e80e0b	1684686571000000	1685291371000000	1748363371000000	1842971371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\xf91ea3318006d65b6577ce6f41355d4841ce0f344e2a3d044bfa36285fdd1f7b5e94d7217aa31d5d79362d23d1d5e18cc199e0abcea422770ea17280aad1d331	1	0	\\x000000010000000000800003c6830d9463f034e06e0082e6357759db3bacf6a213dc295de9dad48a4e8e3258e4f484b0d11d537e142e0a8324335ce669b0c6637307854a031bcd78cf7697a8449d995dfbc2d9f7e098b0e5d8fc47017b0522ba67535280eb854d66a9531d7531b607f3556d278cd77aac37d7a59e1389d6718b5915b028932f99c9c6bb2733010001	\\x31515ea80657e7ace262d986152796d0f1681ad982e5b4441db5f88358dd25bc8888a31ec9b77f69d4565d247652601a4c480e7df0c9dd676831c986f12acb03	1655670571000000	1656275371000000	1719347371000000	1813955371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
327	\\xfaa2e2960a1cf3825b1a15af42e3865cce1048d1e7552d17b57ccf538c8a6cc638cc03372eba1a9b2bf0f85b484f314153bd297c12edcf5134cc4609ba0c5b81	1	0	\\x000000010000000000800003b346916fa9690ff44fc47440fcdb3c5553b448cab2eb281950c5d30bf24491ead78fd19f5e1a84ae9eea385421f7a5668bc53fb7a7477dd28f406d1869ff4b97c30334093d1b8806ef468cc5a693ec2246a8ec03356e8f219b1dae4ccb8a2895e6d4dcc5c85b4c95e5ef03d5de5a0b30a5306958e22c49718aa1b0b99de6d4fb010001	\\xadd08753de13369334a4f12523ec51881b0f805649ac446eb2becc67663b2b15d77647b558d928f1b736b86cd51f746196f356a75a66c5f6269111d5fc020d0c	1684082071000000	1684686871000000	1747758871000000	1842366871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\xff6eeb918c5323f65ba3aa11b0d742431699aec529ef3aa9421f0d737b73ea7701dbe6c67795df8a9665c724b953409ba6c219564a8e2fe99f863189e8d62656	1	0	\\x000000010000000000800003b7655f359a467f606bb43d06e12bd66ea3502d2337cc02940cc4d247f769032c1215d080813b55fe917499677bf4537ffedc55efd30bfbf4288378490b8a5a639bc1bd6904d694dd236e749f91ea1f20e90745f674f9813fd84373dbb982927d93b5dc98613974662c2fb963e082e3ee2ac22e4d17cdc009604fa88f0e3439c3010001	\\xb8c04bdfe796bd5e66516fe5348fe38b3b7d8b05843e4fccdae4780695c416565fdf58ad7975ea63be14178535d860a10a85b02dedcd722155663c7209247b08	1660506571000000	1661111371000000	1724183371000000	1818791371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\xff16926466885d0919d061dce906ea11a5f1ee78e117072916cbddbebb31cb106e5342f03d82c0aeb4a1c64a75240959f42a775188b207df42530779757e6e0c	1	0	\\x000000010000000000800003c54550603ab2a1420912883bb2beec40891d1935ea2529f443cd9b701e98178a7d304b24b7125a25e6936eb5e08e5dfd496c9152a202271e4af502b2d82b79ec6afeb45c98ddf87af3e882c3abfe5beb3fe9b4bde929840644067da8d86b09e1e71277b67db137584d272c6f6cd8e59e1769cd6eaf0a4a6f495e1ea2a6aa3ec5010001	\\x8accc3db838ec5ae1071290e92d290b32f37bdab5dc602ed65ff824bdc93175973957933502176b3f3f929e5b126793289ee8f6cd6281c4a03dcd7ce18e16206	1665947071000000	1666551871000000	1729623871000000	1824231871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x027f80a9a17826baa05b0e53fb745ebdca805b77f35505c0c0b637f70f47d34b6fa52402ca1a1a896b6cb88de53080e353b2c3bc6db47ed573fea4b0e0553c7b	1	0	\\x000000010000000000800003d468e230d28a3398bc15bac25a7248480e5c1e0acf87430330841972122a38a11b85466a208786a6d19d4eb083d0fc417964082c2503553f34557931e3ac64bfab8d035292ff8e34b1eefa8cdca0e7961b2e3e421fc6bb5efb9a4a03857876a583a1679d682319626f47a5fbe055107e01410fba40a59b15caeaa4d16b536a6b010001	\\xaeb57e1916d927b99e0e4ca346ca1022c0214200944f4e6054511187077748ce184d234ffccc5d5c158d3feb0fcb28728b485df959b77a69de8785e853bb0604	1679850571000000	1680455371000000	1743527371000000	1838135371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x06c7faf74e618fbb5bdfb1f96fc66842eb5e0db26f9a1a0d4d85d72bdd73becd48cf981b4a4bb61f4d3f88e3b5f97c8fcb9dc0a580a07fcc61d5e0aefa2c73ee	1	0	\\x000000010000000000800003d9f5ffc21ef9144ee7903039bd8aefc2bbd133d9bcd60a263c4b54408e6b3e9eadda76f3043ed3e7194296f7fc1b584526ae27a08712efd69388c5e3bafe4633771b1f39dfae6486983fdb6fc8bb8bb3c79b43d02316b76eb97bea04a89efd1d28ae10a2d43709fa67e42b8127473433809c58fdc5508700878747ac85137a2b010001	\\x58c13734156f501a0380b1039538ed17d5ca319e401965132e439dd6d8c92b437091dcd57370dc35c9e44028c495629f51a65a13ee91d436d4b9f81e1ff7f00c	1685291071000000	1685895871000000	1748967871000000	1843575871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x09fbbcf77920a6aa77a3a1c8d5c1d744c3b55897b288946c56cd82435a0a4daede9b869622f2eb83e6f471e02226543d0eb8edae1a2b96aab4777624d08eb032	1	0	\\x000000010000000000800003d61fa439f32fa1f4a794d4219dd0b65bde602c832e0f619e37517705a0b6a85272e52add3fd167fab0170860a341116ed945fdcfe733309b6a1757399fe0ade8539ee518afb493de84ef3f732c658efb7000abec4ea6eea200b3da8ce78513a3dc81288166c54a33897366b5efffaf4cdbcea2a722a7edf2713a42f843b35eb7010001	\\xaaa8e968593b523714b7e41ee67bb6ee2ed6407b9db53d7e3f879712c67acb8f710042c97150e87703354a8bd1de53df679cdde696ef6b0f91c210f7bae8520e	1667156071000000	1667760871000000	1730832871000000	1825440871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x0a8f156357079970cfe09123114952adfb4b3b68f856ccde9bb74ae83601334bc3c06aaa0e89b4a0c05743ca41c112d173ebe3b09a301a3806621e29b91dc212	1	0	\\x000000010000000000800003be387d276b997a36bcf8b33f40735a5f4c0778865cecba1c3721facfe8631cf6cbba27c10823b559dd137ea416efcfb526ea84a601346f3c2b0df1a9cc60bb07a2528918b70961f86521d30aa5b7c521653741bf3e4382f31d9ff9fdf552c4a0e3585ca920cd67dce0efff8df94685854ff64cff2531c9c237752caa5b55ff33010001	\\x20c64e11567212b2ba41dc6c67d7c08980df856b9e943142ea88d98e23b2929707ef6c65524d63e0b8c3df6a7d2c4ad7af60cc8c0836bdead9f58316ed641801	1678641571000000	1679246371000000	1742318371000000	1836926371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
334	\\x0b1f2f2599e50b6a709188a5f7019de7f3292924d9f1ccfdb0c81ac7f25777eef34d90847d5cc9bd10a621f8f9752014de76ce0028c361e4e197f39ad1d5c30f	1	0	\\x000000010000000000800003aceebc21364f4ee2cd28914bd10ae059f069992f82d3ef03cb58087bf8d9685a8705c4743fe5aeada52c5c3df2409c00117735f5b92474075c8c0c88353d67e8d71c2f6ed6289feb1f1d9f580735ab040fbee8eb682a8e9e32d816ef1cb2bc2ba8905de1c512d046961ffda4cb7921e4938dff3e36868cb3ec2bfee01add3e0f010001	\\x8592e470b2c62c4c9995fa49e49c67257b7f6840638998dccd55d0ce38cbb7ea396b1270c4b834cb14f8837e5a40419abc98d6bc192cacbb240db28fe39bf700	1685291071000000	1685895871000000	1748967871000000	1843575871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x0cb3309cf2aa3def3cea86bec01c676708382305a926582c05085846cfddc77a3b2742f4d2fa77336904f8d4cdbc4151f84160fe035c533b3226da880ece182a	1	0	\\x000000010000000000800003aa5d366af86892761b87fa980b6f2b67b62440687cd570eb9385960fbac1ebf68291793e2e7ec41e49d2195698096c0804280a9946c7a295da3a48870bc8cb3695d844dea8267d08009cc13c0b8f879c98c8e016aa031f95602ad912ecebdcac74a39ff18d4f4b374ef4265981378283154f2b8b2aaf0c1f10d4f3293cd92397010001	\\x85009f7477f46e1e221a0e5f2bff82a687805bce89f6d56bb73a38c82af44312f2d7f0bfcfed1ca1b3d61ef230662de504959dfb38667f20daef206e6ba55d0c	1661715571000000	1662320371000000	1725392371000000	1820000371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x0ebb99754ebc377aa38571fd1ab2118bba3f7e292bb32787c3695f8aecc4a25882df78a39fd0de87da1ba0c64d11827f502e05168950f3468ac3f13a4e4ca7f2	1	0	\\x000000010000000000800003d9734bf9749fc7590e0835b255e34ca13c9cb83cef36f740b1ce41762dc812c29cdae5d890ae085ff87bea03b87f6464ac6f930ab98276afc6a779001415376233757567840586a45a3eeb4d6a049fe3cb343a4509f63ac3d39bbf6e13650a8ce7a563c90f24264ddac40629fc9c709335f0ea2051a16fc794a2397a49299a73010001	\\x5cbb0dfb917a8757bccd6320bb93a3c34760f04085da3e649b021912cfe860a5840f884a642d44af019510629333edde7a19a87664e9560699b60507aadcbd07	1669574071000000	1670178871000000	1733250871000000	1827858871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
337	\\x15df3af1ddc0900a686c7254991e0afbe97e3b0eeede77369686339a0f7716aa5284d3f3299780b245278a96cbbb25fcd2da0130f8c3e31d58db5fadddbdfd0a	1	0	\\x000000010000000000800003aa6e25d5d819268fd299c25162ca7e62a1b7357082c87d26f6713f6ffb8ee616141f5de81add842df9add32b9cdecda381ccfd5f00922c6ac19c8e05b473efea2e3acc89ea609171d16b37abf6efda623b35e02ff2f5ce48c4c2afcb9781baf78fc1d44c5da5c74d175ae0bdaff2689b681ed73425998d91e25b11d7f13bf411010001	\\x502bd70e78a285415f27f18a3b1e18d63b268b1ff46778384952544e0a48be888cca57496f393c53d518bf0cc02a17485f8c23d665546f793910ed17be400b0a	1661111071000000	1661715871000000	1724787871000000	1819395871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x1637250feee35752e4708fb43c0b32cdd16666fe4291597aae7bd8c66e7a314505bbdffbd57e06153ad441cb1c57dc819e07897d807859fcf26f0b27b3a5ba06	1	0	\\x000000010000000000800003e94dfb1dcf2306d3bdcca26597250d2718ceaed65a915b1d702f0d54b744bb75f1c4368263b8945d6311dfd0d2964bfe3cad06b7d3a7ec101c2251afd7d9ee7106b96ae8125c54389b8eedd81590837da8fd3a3cf3cbcc429f371c90eb6f9bcc5ef7393d049d8a97485e29ab8dcb815f8a3649fb788e03671854d48fbf137da3010001	\\x7d348e3e8dd36c47163a38b97a8c47efeb8e25d8874fb010eb0b27e303caad17615bf66e8d1bf4656d15a3048a572f7d9ee317ab98de8d2e535236e60c404c0d	1670783071000000	1671387871000000	1734459871000000	1829067871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x1993e37e06ce10a377a0e1e61334d20fc3350d9af5d366873d812f803c8c6c92ceca32b0ec57f8efeeb32e761a23f561bdfc6960d2f11ea7a765dad01bc185bf	1	0	\\x000000010000000000800003ea9350324f287330369508749c5c8e27f81a18aec8eccdad43e4fddaf0f9fcd469d7fe1750e3edff4506bee98e69cc06e8c6ee093a95094ada7c13e1c74a8f4df3df9b52f5ee8bd8583a63e2af13dd3b3f5154ea054d83c1fb291c9ca7b672b759c9d1734da68f5848b3bb36279b90c4037cc9060e72760765faf78c3886716d010001	\\x937c13982c42e56c5526202f3613ced07e1bfb5afd917f07f36756f8f1d6534e5721f34412898696b797d5b6ad1a0132080ca0907d684a40a7916bcb73c8780b	1659902071000000	1660506871000000	1723578871000000	1818186871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
340	\\x1e53886a3cbb36d0ff2e7692af7f8439fa5b397ddf93210a50235bbb5bea33b37bbe6df074509e569fbe66badf237c3282c65699cfa034e7281c8ede947514ab	1	0	\\x000000010000000000800003b6eaca8270d006495621796eedbfe145f89b1e95455a3ed73b55fdbc9b74e0829e6646a93a903dddea55ce5ef420aad298fadbd255c56c4a008bc9134695456d3ff6a1153253b31eeae3fbf8f3013437b403f77197e3137074aab2407a38b9b49ef4298c079a855137e2030643581ce628d12bd139d4eebb29f6198e69b6c631010001	\\xfeb5dca1300b663f984d6b0d0ab015be1e624af95c1aec8d04347cbb4324d94c8b66d12a4c692614d7a9036533303db82d25fa9d000c3d2859bca2b49c56e105	1681059571000000	1681664371000000	1744736371000000	1839344371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
341	\\x2063b0cdd60cc7803f51b90603e4a64421486935cecb28b31e9a4bdab3b6d336353c756938c1d26cff552e32b63d626ca3633139ac3d3aae7b6867b0db1def06	1	0	\\x000000010000000000800003c61c21eb47a5a7e384947845f74003d958a53aa81f3fd55e9f159026e11817d0182fd9dc890b0876db74f912b2b00860f65fe582bb8656808e738662a132bc92ecb34f354b793b65ad580cabe510c633732c59332c63ee3ada387458d8a8c503a4fde8886d66e0c643d48e6812ae1781d24e955c562422a81d0ca41192c8e3b3010001	\\xd7f33c382ffdd8bfcf10030ed0a32305aed22a362a2a10942cbd85e608749ec3634168ef8914ac24d0615f782bf90789c723a5140deb5ee421b4a09f63760b0d	1659902071000000	1660506871000000	1723578871000000	1818186871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
342	\\x22df9872f0197a7e4ba351690c1c6d089b7b87846b37b2499b5de83bd87dee9b51179b00347dede93cc144c64131889776790973ae98ceeed27188034623c366	1	0	\\x000000010000000000800003ab8fb3860d471d1dac46c40c031a753b0065df4e85d9ee2fa05fe3037d8f81c18f446d8feb698fae6c2b7474ed6fdd25ae59f09335e7162c37be55525cd6cd8e96ada1737c3579a870baaf42b23a775679d19a862586f303f757b8fef3c53733bf94cd0768ac412164759ab83d72f4dbacd8893a4c6337cff8207ae2e2fa97b7010001	\\xbb829a2ef5039f1760d4b61b3091c9f89532dfa6815b52d864018808f595c2ab7497e3e35c19a87e9f9588830a405730cfc33aedd2022c41b39964fce7266501	1670178571000000	1670783371000000	1733855371000000	1828463371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x258f3d0f13ae57168316d47cbff2f68b57718a0ad6396ada4c6c1659e66aab7efac4721ad18cca0acf1b6e76bc055c03fbefe97dd77392f37ebe3b7463ad25fa	1	0	\\x000000010000000000800003c8963e593d4a2414feb82e99df72ad902873bd35c0bc5661290e3dc6f06d09b24af134fae8f9f4cd1c021f82e36fa5dabfe5aaed4b41ce48011c0a20f7197003112cf5a1c576c3797a0aafc0a215caf77eaad553a2c4ce032d9a5beb5f15bb160e08dd6f118cce807415004e7c08e63e5ae902b5c355d0b6660e25fae4d99165010001	\\xbc564d2343287ca917ffd2dddc5bb051144277cc8abad0ae2b11d3a7c68bab60be124e7c2cd3735c6efec9b78f7f9e08dba920cd3eb58ef8b5d7d63106fc6a05	1658693071000000	1659297871000000	1722369871000000	1816977871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x2c4f211d595219d421914797e7e168e673a0b68d950ff99bb1d1a9a56da6584284383f68aab358f6f38548bdcf89c40f4a3dd91df6c4202e58e9ff431529e901	1	0	\\x000000010000000000800003b4f094ee1a795ccb1413589ca75d94790b79ae6f18475cb1afa1f00324e4e6949b4a0ca72199be74fe09aea294baa4ef592c701527e0999640bfafb6d9d807c714c490201923a6f57627636fa1e008cd5ffc2841113c5991e015ecadc9fa62c3bb3bcff71ab5554a7a3008011b22e976f34e99535c11e699bf3301ddce38c279010001	\\x8d6580dde2adf1e665f056c20425470de793dbdbfa4f91b8b8c57fbfdd8393777d6a00eede0933c909fc3529fef4ed5a0ddf063299695812a80691fa47ca1704	1672596571000000	1673201371000000	1736273371000000	1830881371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
345	\\x2c7327f1bfa09b9ff5c7789f2f6629836f34ae180607bf4731db5aedc78bb28321368c23aa5dcf63ed77d26490d91e5bdeeb8849e28cc5546b10b2efc5b007f8	1	0	\\x000000010000000000800003b7e53b38d7770dded790253e35179a5c28a8675b9cff4e2cca49db280d811be0b9bc269a5cb4b38d8e081e19a95f1b5e67902f66e1c449f95ac09d9e36c10bc7638d2027b89672b2b2749c0ffa32dcb31abae365307f4d339c54094a12d0803019c45d628b62fae1dd8fe91f1308cd38829b4ccd8b60060df8b9f6524886865f010001	\\xb1f592e5fbba21a6fe95509ad9edefd28a13e535b6470d6e96463bc3851b7f932e7f8b39d8e3e72984a91a009679a82f7c80d01badd6586a0a26a335f3ef300f	1659902071000000	1660506871000000	1723578871000000	1818186871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x2d3b2a15e9e49566373012f0a3cff1ee56664b4cca8cc94558dd6b6f64d277c60978ed9e6fcd911ba376467196cbd42c7e5ab2141b5b7efa357e2ba21274454d	1	0	\\x000000010000000000800003b43fbbad6075e6ed1edc2645ed0cafb2187db83e1f1083e77eabfa3766420e8bcef4ba7f6b4e8ac6442b502cb10e84408c522b21709fa29ded83300124c2712c3deb856187262435a4a2c0b2196870c3dcf4c0ae899c7fa36d0edfb5b764a84ba0563e09a5bd394deb2091dbb94012f46718069461359201fc1c9e4b99ab8d0b010001	\\x679cac381ff6954ff5ecb35decf2d3be5de44e6a66e3cbc87d3d3bff91749e2324f440745b68771f8be6614719098a943b27bf9371a1d2bd61c1bcde7cea800d	1671992071000000	1672596871000000	1735668871000000	1830276871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x2ec708d626e9b59d32e0bbf8dc0d3686a27ff632ff00205cbc43533f4d7f9f7a56bde8106f4d7f7ed944591185264088d2f5c588bcb0861851c298703163fd48	1	0	\\x000000010000000000800003b7ba02d0720eca538125435e0eeeb20ece17c0ab06b8bb67e4f18b531ec3bfcd092bd99a06f4ac43aafbc3bbd7751e4268f2b2def2d975aa490487ee0d1272ff7e9f38d7c55f3cec034aed13390489ce8a50f075fa458dd65630f824b83a43b1d688b766b07bbb3152c76cbef44f8ae94060abb8d6f5eed7eb25b7c764273223010001	\\x7c8786cc923c68040a3713a5df81d5b4bf5bf0563b2e5ab76fc8dcc1317c1aa761d0cb1b58c3b16f44865021534736bb5efe167d102aa89e06f799bde0a6ba0e	1678037071000000	1678641871000000	1741713871000000	1836321871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x2f774237db28e88962aba8bdccd5b560fcaa3ad80e33d0f71c7416eaf3480d3cbe5fbea6749330f9a79c6ba0a98d4a02dc2b870909491a129f54381c4243968f	1	0	\\x000000010000000000800003bc63985ce8607278134d21490f0f7c34e2fd3f02134cfa064a29f12bc35aa4357f0359e1dc634a7b1496f316737053fb2adb2e269dc6046187b6d849e099a0498092614405fd0c95048aa7a50dd00022ed75f6f3886a25ce27075ab31fe42012031c1794e6709a42ef6249feb7c1d601a1f8f2d1323cbe7331c011e3d1e707b1010001	\\x475bd4ec65c9788fc9ed2b7a6534e42bc4770ac95499cf2c673cb9d4afbce89257a13458e4fcdd9713659c3dd37954ce14df177381008d605776e2e73e885b0e	1659297571000000	1659902371000000	1722974371000000	1817582371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x30571cdacf9671ff1deac2d80faaee6e548d5481984d62a0d1a99d08fc0fb3d366f490c977c6ae2c7d1d660da8228e935b93855660941eed1744d8363e5354b3	1	0	\\x000000010000000000800003b198ac2b4b22d675b96f822f424f44dba30729a48dc6f84303ccb0e5896a8fcd5a481dce781d3c8b25a1973a6e81b74e24541d4802f6b7bc342d3009708c1338c7ed25fc7e0cfe8c25d03df5f6e49c65fbc1d1a7baf9eddd49b5eaa171020c97efb71154896b63fb8de647b65101b19f333382e916c08291d750ed11e2e0df83010001	\\x3ff9861d8d576442909514294eaff04483a3a6dc0f684ff12f377ba1cbc58f3aeba55e8e8fe60a066d7aaa88b5eb24b37338abe11a52c47db1dc4bf0b4a86905	1686500071000000	1687104871000000	1750176871000000	1844784871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
350	\\x3627f353a023502a35e82d2136e82d20a39fe50feef19891bdb5348681f57ddc06e59fd10e27d26245e25982bc65ae91ab88c5688df689ed64aca5698e8a4ba1	1	0	\\x000000010000000000800003ad1c911236d5ab74ed2913b84dbb32dc226ac5c6a90b55b1d7a692efc55ffe7f86752a8ebc085e474464d27e9160abc3cc9c882236a5f9901adf9d90e16e52a98ea6d507c68d9ef8034c9b9061557f67d8c8d37e23f85592bbb25b4ee8a0257248bcd0e66e3d46f60ea216dc804796b5bfe53137d36279f1f85dfa349ae5e089010001	\\x92e651912eb30c0ed1e6771064dca1f41b7da82f9ec565590fdeec3436c389391498058b40912cc63d9c8013534d883038cac414abbf6f6fed4620a022f8450c	1660506571000000	1661111371000000	1724183371000000	1818791371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
351	\\x37d38e03b994de1faa8690abfc3c453414f4f775830f881c8e7309eedc04e89baee4b088617a5aebae8c60d8c8e516ed272e5043f00e6dae98b1adcebdb14488	1	0	\\x000000010000000000800003d3dda4f0adf6a8a9bb0ae5a18529765bf3c320b34a7faafc931a66062ae08286bb07e4e77f0187431c196d8e6f19451effe865a5fef780b467f44ebd01cbe533159e16e039efb9d90dfe7e70773c395f630744bae715cb22dd3583185c0aeeebac5f4160dd8f50a09ad33485dedc3e0989525306440b2b479a21f11f603c58ef010001	\\xad533115b999df40e78a491a53e4fc8895a2aea75534f1ec9911119e3cb67b5250e7e1a8609b773a2d952d6bff2bf2bcbe5ba9ffa91cac84d3cf54518f210602	1667156071000000	1667760871000000	1730832871000000	1825440871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x3b5b936d98025c16b9c7e3f70bc6d586a2dae1b875b050e9e17ffb3da11771411b73873edbb53c733860160e9e12d2b0b5a0e909b755002edc3709f0cbe4e5f2	1	0	\\x000000010000000000800003bf604a0d40299c8ed0498f2bfe3b3dfff00fcd329c1a3faba69f5a6d7e391dbc7c0a4df06f69fd035fdf46b92306e7d5a1fc5abc16fd022b50351736bc9c9fe34b6fc556fceee047031ccb61fd8ca299f9231fd747176fb2a8e8be849884978f4ef09d3e287c03dfe9a00fe88568cc35a59e151e7f6a28d61b5f72b4453fb365010001	\\xc54b2e5c5d9c3c46ebb1721a94959e3e2a5897d2d508e7a91c05c1c05710628ad731d5b2537753a06a22d4a3261ae06b317ce7d0631e3ba27e0f3fda116e590e	1671992071000000	1672596871000000	1735668871000000	1830276871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x49e70005ea92a1821be425f38c695d0b0b70738e59d75a00ee916aa86061072052825b1cf0ebf72cf4bd02e7ae7d5c25b8ee7890f51e42b1ed315ae24e8e07a4	1	0	\\x000000010000000000800003bd5e60602141cb042d75c29833f99b2210cdb09c06abf7cc8a9666f3252b404bf75ec9b7568085e93584dafc5f59929bdcb33bd5137331106585e6acb8f16d3e90e75386184f0892bd288852d2de11abb8b608fdb7362ab9de7e5e60d7f0714fb1a3c3cfbb8ecc412684324832f3e477f9d5a2d5b0db2803fa96a6a26bdaee3b010001	\\x37f35d24a05912e99c535de298056ead0cac51d1c08df527903e5f1e323672536bc573d30a0e3934afa7e436529ef71599ae00d66d8ff1e0b8eb0d9cc867df05	1684686571000000	1685291371000000	1748363371000000	1842971371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
354	\\x4c1b80b03edfdbf6f70f1059992f5a0d2a26dd828962f602f9e588b263b1384f959fde973482fef1c787f42528aa5eb676f267e265083ac80d1e4cbb9cda012c	1	0	\\x000000010000000000800003d34c6071c613a51dfc4df5b0abb837846e41eac060d4431b28863d889d0dc273e87211fbb7071bd6b6aa711e60ffee134f263d4dbd7e35385b07dc344c146370182a6c0d674fa5543143223fc6063ee6c76d6616a0ae2d0293445c430c34f29d4e9fd7acbed790b732a99c6801778d6120cf5631475a0b3f4a3a2bd3ddfc18f1010001	\\x36785e7e6df59f5e0748ab52c82e6e792d0d68248ce4963f507cad0085fe546290472aafad4462fd9f8cf770789a9028ed713bef3f5a627a4b4f085400ae510f	1656275071000000	1656879871000000	1719951871000000	1814559871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
355	\\x4c87d86f2f2e61dd6e0480e766612d261cb81de588c32cf2127f4ea950e7fb79196212a9c12a8c31b287791ab8472d2d07a52b9de33af5bc73d309a447523666	1	0	\\x000000010000000000800003f1269a1dc66a691ac096c4400c15145e3000e8076f91440570b1f30598c6aead39c2ff36e94aff6ee42aa7d6b589e93ecbc344b76edf6d2ac8818818920d06d3646203691d0ab1130c50cbda16a5783e5122ec85ad17fd656a1403fac969dd5a72bd90eab1785109a3d9d6ea3ebc59a4b9575421985ec822aa6fb9412cde7699010001	\\x56414a2a8d7e271c5976c44ed0080706cc80399f0b9744c657ef5aaf22d763e0fd55a43df520702b9d3b34eeac8d7643182e22d4b655499d7b222286baba4d0d	1681664071000000	1682268871000000	1745340871000000	1839948871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
356	\\x4d1358458f4a756851c6378b75cf07ce0192881642b81b2c6c29e48e4cb9f799a2ceb4ccbc813ef30c4b1a19878e8b90ea51670d143af7bdded97379332d03b8	1	0	\\x000000010000000000800003ba55b5564a705f3a99872aefa8716d5f69ebd4063125869a958a68bb3125f89b129e3ce9a6e471f3d6fbd8e8347bdd731354b859f7964f99f094c17861c85fa5b02c9d6503aa31199f04872f5c0eed853aa9a0a2edec8dd77c88bd2939d090fd4ab6e7a7fac7f97a683a47120ebe97fb039460763146f63521bc2d962ab739d1010001	\\x283bed1f16b21dc148be0a7ac8e67bec4804dc97e76757bcae120ca6c84a0478d5a5638b89b187e150f3a951189f566c4c5d2049fbe983e78be149d7ea163d06	1670178571000000	1670783371000000	1733855371000000	1828463371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x4fcfbad3f6d55068149fd1f6187247f7d1f1e5c558d19b1cb00ba6b7fdfba3ca9299a96397a39e232b045e9dda8c5062ee51493bf01117e0d635bb756b1b9e90	1	0	\\x000000010000000000800003be8346aa10c440151bb6dc45c13e36d41c95f7b76c1464602b95d522e88473e02c140b41850311113eb52994d6c6d148ea48da28d5459e6ad72bc689d64b5e6f7be5d34d790b16e40f184d72dae7b54b2970989352b3525c728bf1ec22109306a3c40da47576ff857c502ed242cb66f30fa41a157b53b06afb657d271f063a1b010001	\\xa40a415e820f02832028f03195da98edcf15ed7994a396429ee7f77fbfd8fe06d4b7e2cc30d1c2a3c6acc3b9f702a172000c5da886c986a14f33dddb02c3760b	1683477571000000	1684082371000000	1747154371000000	1841762371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x514fc8c82be481514515ff4c17054af6a5507fdc2d3b99b739652ee728109dba16802bfc4359a3d718ffb651341aad235ff5a5c57470c0114483886f33677807	1	0	\\x000000010000000000800003f41468228ee2d6b338eda5e7206e7ef0f52a7f0ef1a06cd5789b6462e944420b995862fa87ade13c4ed7ef5a2be9f99e3960a7aa1ac12d3bbc34e755eba2296b1a5058a8b30529ffec01ed2025c9d31bdc4e74c444db1d15c7fdc86f720855735b1ce1f71ca13b629391dddf6e9723139e37b1431fb3f83bd2d398c7c79cc445010001	\\x93979f1c3df6d8aab3383e9aa720dcb54534e573783542b3352e40e8af5309cd1c75de55994c2e20680974463efc228867f1b15319ad3f09a651afe159de0d0b	1673201071000000	1673805871000000	1736877871000000	1831485871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x599f5a1517fafa5bebec05a576e42172b3944d3ef727b8b1c83426b67c2e23c2f21e5aa0a692815cd2d12882b7825e506c52d12d73c8cb1d3fe3d517dde93ca7	1	0	\\x000000010000000000800003d87587dc06512c2989f817f6d0863c698b83f9dbeb139272d2015341f21ef7ba78afd200248b2512c899d910d691f2520e621c34ddc4865da5c305225a5aeefd32bdd8940c43ca7ac59c6f11a587bbbc1f2fbcc7d9e18fa657b36dad0688f92fb18b3c730a7c0d2a65fddb6d6fe624d67908340ff307197f4781075cb99adb27010001	\\x851e7c60ed30a18a58f80d3a6ce03a1b96f92d6bb9fbc51f58605c67f779c2763cbcc9b33b8d46ccca2abf9fe351f86ba58ca4de906b2eb0b949657978804b0b	1679246071000000	1679850871000000	1742922871000000	1837530871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x5c2b6c24255bf9db0da6cb061acd892219566c41c85b14531190ce7dda54c39b33e5d9b60bbc3ba897df56f0d5c3713773150a13d7a351ae46cc8cb807b5cd94	1	0	\\x000000010000000000800003ddce49cf62ef6dfe78bd2b08af8e0f02447b2f7dfe4aefcb41c647f4e3cc57ada56effde9f8b067b34a1bbf2a9bd9158fb709c000f40775a72f8eba90af80180dcbdeafd6947de80955c1eee422e2702d53be325fd88371341204c0348d4f83e33fc9e2dd47e2a27ec7256977943487f2bda2aec3643f014d81222b44d862fa1010001	\\x877d24f0a7690ba5be784a70eb885d51bdd8164acac63befe4b2d36d4d75844fa227c7b0933f4c9012cd69d9f25a41c4e0a5bb7648dc217f2397f22a10e61d09	1668969571000000	1669574371000000	1732646371000000	1827254371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x60b70506257a19d4003ef305a18524868318ca19a56d4e67c147aa788eadd7d4576af483993c80d0f4941405fc5885190db977c1bb2c5d33f7a9b103f2d64187	1	0	\\x000000010000000000800003a7e2de245877dd4537e8e20143970eb5fb13f613f6f69859d0b4ae303ff41783ab0df9265cf5171754ae2aca6cf2855a0c5c2cf754eaaf5e19102e0f43ff5b310114077e7d799548a8e88e97fc60cd67d95a0cc5b86f25aba43302cac1b269229de0469d24a296c237788e6d8745ff0bbff7af2c3a2a51ee6a971a74607c5f91010001	\\x03456cdee996760f53e47f10c85cbdd50c42e09e66abfee27e81f27e0a817572375d0d3f9ab0ea69aea45df45acb0ef34fefb5bd59d8c3a72d6e44486b67790f	1680455071000000	1681059871000000	1744131871000000	1838739871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x65473be045e0f6eb1cd8c66000dd0aad79574d9db374967ebda5d30bc707eab3a40b258acae11159b3bee5cc5075b8a2379201eb59f1c29e3e91137f99534f44	1	0	\\x000000010000000000800003bc195bd1db32e9a11f752200359ad401116fd425ccb95dc6f8f9e3bdfdabf354483f937d4fabfd8dd6c17ed2b02ddadb38d00bc23fbac5da763fd23d5da72d97fd42b6a08beaf51f94f6d36152bb1e56b4ede58cd5be6ce24df485e8820c069db5fdd58865803b445d658365f6f4222d48951a20ee86febb3361a6d62c8f5e09010001	\\xda495fce5057b4efbd3acf7d943ef8c15ea38050fdb6071be265eac675e0543db4230dee3e8213352422c44e8727784505f55f51bd81e70483516897ee230008	1680455071000000	1681059871000000	1744131871000000	1838739871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
363	\\x66576a917c8aba5957dbf8f6ecc0cd5a910fb075ca5e0ea400fa47a6415313568b4dbad55f5ab7cb05617806a5601a692ab8072192a662f4411d51714f447663	1	0	\\x000000010000000000800003c1c545bae77f4b2f5be65728b91c55f3d2141b0574090188b7ea54f6414c1f0cca1f53d31887b71258772df1a5947f82d6439692b7473fd28e0ffdc58a1c48964791511befe871e440c057ca8e336c1d82c813c9cea7e54da0acf3534c6240c4ddf885f5025843263c994ebb2efb5f9fdd802c23967cbbaf79e85c7cf3de440f010001	\\xacabb3b5376d2f4eb9ac68829f10f945c713090ba32f7f6e1d9d503c6b03a8912ddcd290eec5c5244a877a395ffd98e433e24fa52f96506faad8b0c7c9131106	1668365071000000	1668969871000000	1732041871000000	1826649871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x68c7d7160b8f40bbfd49a7685330941c6a7d1d42fdfa91dfd4591b89c0df1938edd2e2b6897e993ec3b5d11a81043bc560d37d48c2281d5a7b578b533f42843b	1	0	\\x000000010000000000800003d0cab2f849a9102ebe60e23ac5fc775df3b5741d1a9095998f64265e987fc704ce56b0b3663959c216bd9dc7f672db9950d67f6d9bfcd888adbf74c57cba391bc564f20aaa421eb16dccf4362f70582e8ea588dad5892a6738173cc0dbe3ec5b544ec82be2e5d63e5c337fb79a73692f3db3246226e37cde8f8889e221ac5c8d010001	\\xdfd8256fee5b9dfca93380e7ebdc3c8ec94b3b40f46c7178a779c8e6d6b0e9e6884595a73b258cb1302de4d961f73363c99457104d40778b9122308081472b06	1661111071000000	1661715871000000	1724787871000000	1819395871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x69cf52b484eb154798e087108264b8c29cca4c8fd42ff5d0c22e3108008ebc50a9c2208818344a49993e2ce16ae3191584f29d0509b968c46165c0ec67b4cce5	1	0	\\x000000010000000000800003a86e932c7f8254a9ffe8904b20dc890e2029f2181a9cd0956e94d9e4606f3fade3dea2fc30060494e5cc0d9828f8b81dd5e424f2c57d6cfee38e1ca1d5a3d9584ffbbe8077fdb03dd8bc403467088e35e6a406c81f222cf109b0b84a89557ad08e88908b432d79089803ef441f1bdb31aab4de26b598da0eabd10c1e0f6cf01d010001	\\x5a30ea42c44f19d4ea3975cbb84c159f68f2af3d1751efde10c0508d6d87d3034472de9c7740152c9e77ecf4f401d42ed7bdfb93ae5e964a79d52fffd472e80f	1684686571000000	1685291371000000	1748363371000000	1842971371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x6bebeb870e0692ee88b4c2a1251a4fb12a6a7cbf5f9d70a5b8fcddd8345abce27ff0f5cda517d2de943ff101d1dee83a5e40bb6592aa67863ea4deef12a40f25	1	0	\\x000000010000000000800003c98165e9168ddd7fc1dee497b819ecea71fcae6670f998e0ba817e65b67276b848cb2067cb70ebbd3bf4cbf5e245c7f2013939ced59c2e0a5aae343f0acd087229ddc83ee68afb630fd935cb02052af24c31c20a0af8ed0ea440c8f60920ffa902b172ed48615cbd6a4d53921e2814a5d690e4133ea58d0758fa577321510717010001	\\x23cd6b4ad5ddde0e212ec8c375269dc81dc9924a0268a4f0d70ab7af1f7dc596fda3eb32b67b1beba441f9b5e6c11ec634c2b5e4da97a318c31b214a1e65ae0a	1665342571000000	1665947371000000	1729019371000000	1823627371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x728b04203d68e02903d03a8c3cdd00bdae3f2b95bcd69fa53ddb8caa70fd7b86bd43d83e09706bf081733649426b4303d138782fc09ec6ad60d972a0cf7a5eab	1	0	\\x0000000100000000008000039d911e5351e5be692226e96956825b1c5d106260304ea711a5ec1a5a123ba9787bfe65c3bfdb518f93c8522bb633b5dfa2c82ae6018cfe1b3e00d6efc2f659422a7c85f010cfb07e46d2e7283f711dc2849e13e78b91a55691c7fe3936e70db7f23b24a6b47570ace3e2884f94dc94b1768d607781fc4e62f537703d5498fe43010001	\\x3cf1f31c57a054dc9ee37c32e87c3d575e885b80366c208d6bca620f990cd9d42b4b454c539a4636decf8621bd02fe80f95eb2a1d039a7370f4c36f24e39ad09	1667760571000000	1668365371000000	1731437371000000	1826045371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x799304072d19d5e3f969ca008bc5f2bf7ba4cfb4e052fc1e2974f0c2fc1a227b9b41820099d1cf6f3f18b75a899c58df4bbea22b561fcd7625acf092ff25af8c	1	0	\\x000000010000000000800003a1788436e4eb89079e26d73224fa92e6a95e44f8ef1cbdbf229b685ab188cd10e6e137c8e9115b30362933057d726a7431ee8a477e8c3a708db821a47133c1dd4b1774591b2380bf4d3cd81b808966562701dde3618725e2c6bf243dbcbfffad0e6b238122ea1d7252a036dbda433fb1f91190799496bccddd73b1c26f51a8d5010001	\\x1d6ac3036f409aa7dde7376f982b16b5b5d08031f3c045cd34b6d9eb1558c303cede11a9b5b48cc4409c313cb594cc320adcb97d0c7d67bfcb4b6f0fc3d79000	1659297571000000	1659902371000000	1722974371000000	1817582371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
369	\\x7e53d1882b1e0800684120948b0a9d3005cb4a557cae22404c94dd9889a033dd5fac4e99d9a73954f5373c1c06da08bbdd2756f4e485ea94d8a1d5553cdd8a2e	1	0	\\x000000010000000000800003c0fdbec117218950052457552b5f7c17f79a13fe5c22491ff02cd988b9bc420ac90f083e32ab44440eec70e7bea86a023786099c465dd8adddfcf1db9b821c23216576ac312e32c63aa2cb1ad100d0be44d6dfa4e6d0aa498d313dadb08ce9fad9a4eaad0a7e75ee02a62765052ab562266c411593f795c4beb7849070eca0d1010001	\\x2f49f4c6293fc1a3d14249e1a5f26ed3bd0b604faebe6b248a429fd51897085c0bab2490e562245554a130e4e8ec8ca78443967a210f3834e7658a8550b44009	1663529071000000	1664133871000000	1727205871000000	1821813871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x7f6fed0dc0275862bfeb9d562836cf96cc203196847997a4e086f91985b3948949c39e1021241ab22d72a64d2b09aa87a066e48eb4ed72ee4099331ec71745b4	1	0	\\x000000010000000000800003a1b07b625d68900b1b66e8b1b5f65ed0e870e5c0214cbe17d7ac0546c40df8aa529b29af282bfce5c38a072dd0963e63bb3542197c2d42b14b759ef1c5f4c7ad91a323a4e2b99ce5a0c1d431df763583aa522a284289bac252f41193c07a806fad9ec0a98453b29ad31da222965181f702104922cc2de07e9be1d6afd9d08fa7010001	\\xa64f8a3d463af186985741d0e6b1a38bc8217b431f5b435d75a589dccfd236f4c78ba0be2a2341d02425b153024d7d66820922614d347a629cd982543a9a910f	1656275071000000	1656879871000000	1719951871000000	1814559871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
371	\\x7fff56d978ab4b43f21576edfdea5a9ed3e9c4440c9b73cb3f80a920b938c1f205dece8f41e1db218cc0279250aa0230f83642506ecfc70918c303fd6b01d686	1	0	\\x000000010000000000800003a4e352a283dc0bf2f59fbed3f5990558e8e2d0bc572f122c9d25f5961dcd19d8609f9a61a51281d8ea5081f0efeeced7a80782334341637f0bec30a68d45f0f31b618c1eea5222b91dcc3f70aa56a1bb1d5da25f296a24ea6265f5abcc44ad950de28b3c34b5b247987925e116a0c94cf46f6cdac955d56dcf41574f01a94cfb010001	\\xe01e54c2994014387ae1506713813810a02b80b142860f497df6716734984c5c66d853e8bd9504dfe0c3d8cd33118e03a89811c8535fa2410a6805b21b77d10d	1655066071000000	1655670871000000	1718742871000000	1813350871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
372	\\x849f256fb40cf1b5b7dac691520b50dfc36da5d7607cb7b4eedebc1c9f98bfaffe1dd400438f0d81b2494dacc6e78ab4b1a0e95306721e6067f52573d6b0dc44	1	0	\\x000000010000000000800003defa3c5180eaa738cd845cf2090d01f3e1f7d1fa023c59ef810840a88d38a94db386a6cee0fa1449f8c49505380c079cd05ab0288bc041209240fb91401880b84508683eabd7d4778f904419b1a6d2403179aa6b7d3938c4793a835d3a2a6ddeaaa4cbaaf176c94b4160e2663ef1688f56abb76041669f13a239f802244a8e3d010001	\\xf7d22a397004a4133ad1ad3f67d2d29a3bf7babc78ec5670e3998fe91b800c9a495fd39ef688f0f0b4d2deab4b36bda87914e5661d8726849848731eafae7801	1656879571000000	1657484371000000	1720556371000000	1815164371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x84534c524497f37fb151d572ae4317112c0089bcd9cb03bbd9b3922e2a8104f041cd669e07fee383c216c951d3c4edf2d0b10353f2b4546074ec2179bbcf4260	1	0	\\x000000010000000000800003f76ad4816a2d402de03a9a017df44c24e20f6f2d76839f14e6f501cb1d7bb0fcfc8206f889c20ba22111971a99d6bb1402151085d5b94e6fb19cb1c92e332085a842719938c3f11caea00ab30ae83cc41f77b45a97eb732ad26fd077bfbbcbeff69a6566aa5848ecb68254726dec3c9d9a8f2f550d964a264f187a442d2c52d9010001	\\xeed1554b4d6abb43da54f4b82226004387b71685769e3e2bf7ea7b8cd7782e17f890975ca6abe15d247c1dfcd02826717acd3d32c5745865924afa53be470a03	1665947071000000	1666551871000000	1729623871000000	1824231871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
374	\\x847f4e2af95699848046908f8f5f67f70ff66efa4bb883c521fa134efec5900fcf74ab8ea66742871beb7dc3e8a90ce462b3c79e0970503515dbe1bc4fe1541d	1	0	\\x000000010000000000800003a9f58665d2b1d8b492c2200d0d0163aef61d1d0f5d6f2cff00cb8f69f1b9aece072b7aa3da27d169550a36261c665ab01c14d53799f9f77e7b16da5fc2357982b13fd512402787d563fad8376bdddfa3c4a7dc60bca617a0cd3070f56f912c5ad997f359c387aa666f880315f6386aa6de80a84d16f5d591c3b0fc2409fa207d010001	\\x07ab4315512cf8a781a6447dc9c0e849aca1933d57fd1e4d06727dfc994012404e28ea13f2cff326592f4ebde519388a7b0a8120fe4822ea0a49735662870d01	1672596571000000	1673201371000000	1736273371000000	1830881371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x86e363a2a502fc087691bad9faf39f8bfb93a85ed9453723b1bc444ba2cc3aea3dbe72634582d9b8cbb1099a974e977053211ad2fb26264433f0d05df035dbfe	1	0	\\x000000010000000000800003affa7438cbb6ec2024beae0d0787e7260cd5c089de901de17e40290b1a2adf9cb984c907b0e6c40f985586b4f511676e75d04abc13c4a6e8983cedf24c192ec6041364e365c27fdcb1ab186346f122f3d2a8d5e9a8998f79eff73f5be338b117ed8e9841f836c00ade6218d6cc81adfd71c65685392614c006086727fd92b811010001	\\xabc094e225009a2f5e717725c16be0896ef00c27e6370af14a56a524049f74d83759e64c9b236a422e9866df24a4b5fbe1fb967b25a5e333091939b06c744a0a	1678037071000000	1678641871000000	1741713871000000	1836321871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x87831b02b3ed57e9eb5f3109e47fe2ac9eb2dce6e705cf72c158ee27b0dd16d835c6cde721370686eea27e7800d2fb69d91c58ba022f7d450a9210fa9acf2a7f	1	0	\\x000000010000000000800003dae639e5166b030177a3380584d77e17558398a89f8dbaf0d8781d3e0ec8e898e07791df4e1fbc237eefc9051363d2ff213182d5184d05c1442257402b8a7267fe8db939774e4f900c91a3ba2199f62a25cafa1b08c4750c8c5b3fa2b9784f4c4523b36dc07da07a65167b3716db9e1d725969a22a6382be98702facd609a337010001	\\xcac6f5b8570576723fcf4fc8f9718b7eab4d45da9513282a860d86c5c284c4d33f777a1d25bc9ed358e3b52367babb23090b3e866654941a724acbe6ef985d0d	1673805571000000	1674410371000000	1737482371000000	1832090371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x8b2f2559e3c0fefbe9270c70e69776e1ea06ba68d26af221e4f6d586a45c5556da295cdae3fdc9da68c7ef796d1a77829d0673d2797f60fa4f427ab8b1be6430	1	0	\\x000000010000000000800003a45b1f92176ca68e85c8d3778209043e83da109e34b041eeeaa8e25f9c68fcc6c2709967c34b9f43cfe0c186fb7e3a468fb9820942a3a8f1fc8206501ed55d209aede6225935770870e33c5e2d98422205d2145b99777ce4c7650f0e7b1e92588894a4008c79c72d6f49be157af59a2edbd2f1cfe6552479d97299ec21f1ab79010001	\\x8adce122185a0da361a9e3a3a7f1f835718bd5085aeca370b9621e36e5314c1715067120fcd5a4b220cda878599122f37f47e7f4a4c5883d7587affbc3ca9d03	1674410071000000	1675014871000000	1738086871000000	1832694871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x8c0f1fe110bce04121c7781e2cc78ced44839df49f5f05131efd3cb957213029de5e2a97bf865a66a1c1605ddd6d7473f7b5fd6d24409df324b3e7f658cbde42	1	0	\\x000000010000000000800003ad9796d1d67d3d2736cf787d1bc27541328429d7f245ee9e1ff262cf57b8182e78579c7a09800469935e41bfbf34c662c2537b7562ed0002cf08a4b9dbbaa027c47066173a467ad75b08b1612320b7c65cb9106d3718157f22221e0e46c94a129ee214cf4c1f059357d13818caa10c0009d1a429de304ba4c81f3d38a19a0b35010001	\\xbf2b1e9dbbf23356ce6b2f6a15f8641b2222dadb66bbcb580dbd32a25dc8dde7018168c91531b13f12d8b63670b0e6fc8883b12921a5aa1d6a47779c95d24a05	1667760571000000	1668365371000000	1731437371000000	1826045371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
379	\\x8db71a4bfaf6136a7a0b60c71103960d7c69b3f47d3b0cade2c7c56aa1953845a34719fb2368589196777f361680e595904106bfcfc58e1e2ba482937f531c12	1	0	\\x000000010000000000800003a40ce4056fcdf08af5cad9c88823ecec36625f1a0ba01f3a1092646362dc8be81753ad46c36733ae70d13902217707a6d14e755d9db66065b8886b347a4203b989c6971dc5d2e653d0bd0c94024da2aacf6ef02e52daae67e680749f489037e5114a0c41217e4c9d8cdfe654571f01602ae3f519e5069709855f2d22d5e77353010001	\\x0832eaa6a02a8527b363efccf1f0374b383ea2dfe23c1d26f1aa91f5a8d3fc21ad99eaa3259de928582332442289743cf7272805d78893a97935bfe03707100a	1682873071000000	1683477871000000	1746549871000000	1841157871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
380	\\x8f43b5c96ea11e8736f05802e35b08c0c6dc12b52a9538465e8b3c1b0ee7cf94caf045884c5b11b5e53279de0adcc4aed51e3f839aea9d894111fbb283c40b9f	1	0	\\x000000010000000000800003b524781f293591d61d79e6b591a1f7e65c00ab8e430abab36d6ec1af756a9c550caff0ff220821625d3a08a967d7e84112096b5825008c4bc87422e0fa5edb29fa911cb70ba1106dcf682d21e206ccc2cde3c7a14a374ef86de271e4a79ea5d68fbace48ebfa42ac430697eb8f0d0a6e1b61e1ef1310a2e58203702d63112011010001	\\xdfef7131d72cb69735006470595f9936ca6b5977865c4f9ed4c1d42de399df49554ce6b74e4f63343b1573060180b1087f7df828c815600810d89c8f00192a07	1656879571000000	1657484371000000	1720556371000000	1815164371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
381	\\x93ab5aa72098f9175601473f1a5c8d7407895e968a56d0ca4e4f223d2b76affbf21cafd3af0501d184b8eac7d01a171e8ae7f64e94dbc63dff1114948fba36fb	1	0	\\x000000010000000000800003a404942c93be4390fc5a360ec1395f70b45846099b8e8e2e0e7daf6b5b5e5143a2c5d90f2f06be65e0234e77dd6d2eb8936692a7acb1d43f712720d1dc965929f2aceec346854cf40ec133f7a9ccf68ebd70163caff8b71319114ec7db4b8d242ef2b45a142378f1c490331472108fb0fd51a7f17f59f8b34f7ecd9675f6817f010001	\\x1204bd71127d22c6b890ac8a13648dc7e82fea66298b6ca0641904ee74ca5dce97aa8497eacdf1c8a2a2e7972b9295aa5eda10c5a0c1654b18edd7323255ed04	1665342571000000	1665947371000000	1729019371000000	1823627371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\x98bb865030703bcc013f8cb506686a896e7bfd50f916cbdd1de5ebd5c0f54cf19d0fd283c642d27e1b265bff2b329373de66f374213766f26fefb8c89f38f9ec	1	0	\\x000000010000000000800003c3f837f0aa0198f24312289f5855147d4ac0e36ffab7a17d78f5a38ccdc86a5dc47568dadbd524e38adc1f22060b9928f5d4e6463bb8fc488b7e77c6968397c668086ef52d3d5f142756f9b87d774c8d93185fb4e0c2a19d56efca68ff4fc5e00445d6038795996b62781d204f8f1613b40e67680a7ba71a0a14037ea9e7af33010001	\\x1a5ba5ce058a6b9fffb4036243e28e576200d94cf7f70c8820686ccc10d2eac86fa9b43a691a7c78dc57a118cd2a541dd2dcbd46f685f77cd617240a1acd2400	1676223571000000	1676828371000000	1739900371000000	1834508371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
383	\\x9a7f8a631f99d4b29def9b7c702ad1c95d841322882d3e84242c95e49e1f5258c3c5c287c041851e3d3255ea02d8e14fdce5b8315271332ae1045202cd2c253d	1	0	\\x000000010000000000800003edc32cd0aaf234c496eb8e6a5a0bd78156c7e09781ccc82dec050b9dc4f3fcfa1f1ef47af6985a34da1ecd81f85c921c829a783a6220028e43076da03700c25b5cc9cd2ac661125de79d18941c9a404b28e8fe23cd75d09b61a4ace0a658abce0b1afc113acaffa00caffb68655e75c9ecd651ca86c8973c3e720741ae81017f010001	\\x8a2d4d65a8222e785c6d45238409880b4707b72419223ba7af2f7c1286819a7f2b39b27ea4bbe2935e5d61ac4f940b4c134098506232b3bdadad4447106cd000	1670783071000000	1671387871000000	1734459871000000	1829067871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\x9bcfe473ce32e303f4777736906761b8182f3cb38fadcea97c1f3ab45a71dd596b4d567af1d35dde413727d92b2d82aabd7a0eb698b0e95d9fa82ba2eeeaff51	1	0	\\x000000010000000000800003ba7d3e14859bd29875d6140c5c2b9f6f6228b00d4b3b727fac255832f2aa43999279758d48a4308e1b14151dc71455680718509d2b17181048853d6fa5fb940d0c18961ece2e09a41576ee5e382919769eb85acbbfc75c960e62eb5f63e08ac74e7085597f37eb3c25769a4acbc022ce3064acd349662ebcb3f89dbcf9dca651010001	\\xde8d45f46f8e5db703115a1c55b2b7193f8382b8465b7cd94485a6b99602b9ed62749b9544832b3082f9c406b06042ff0c236f8de877674468723853552ef30d	1658088571000000	1658693371000000	1721765371000000	1816373371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\xa7730f621e41c8f2f8b0f9e625aeff2d01c6aecd7e418f874159827c3eae95a781cc128e9fcb1b72cf5fef72fc0252174feca2209e6c95118c5783b8c8d82325	1	0	\\x000000010000000000800003c4e239824c0d289b03dbcfa1852b4c0124c6d0606123bad8032487c08f851fa9ab5e7b458eec8458e7432510fc5957002167e502d95f00ae9f2226ce43d898e6bd1db1d592c7331c3131baf6ecc00d7177adf8c3c70ff070887831f51226e22e7f5337133a624d87e7cb984cd72b1e9508ab45cfe37acfed055be8884d7443e5010001	\\x0499738cd5ccf8b00ca26341eba3e7080179f1493caa3864f808e8ea114eb901c6a37f404e327041d1b40031f4ce0f21cc948ce7360492efb2cf86c5cf56df0e	1663529071000000	1664133871000000	1727205871000000	1821813871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
386	\\xa8ff7dd4ef958d1d5d27e0a8a9f3e05881d89dfa021925ecb370d3d6cf1db7e352664b3b8045b025029cf69c7fe1fe0c29b63a6e504e27e30343dffc6dbe7062	1	0	\\x000000010000000000800003a7a29a7d2852292a737ac2fcb3d5da46c9cb8ec541c0d999d378507272b542bba6428691bc6db16b495aaef48df4322aee49030ddbb70e28e56ae0333fdd8cbdcb569e0789b773c3f9b9aa734fc0a28f688866197ac19267380621231b0af3074c0c0ca1e2b14382cdcd61ef22e62a67bfa6a700157d3a1142ca3d69fae9c0b1010001	\\x5bbba70d8a7f89eb91cf9ae2e0b27173c718febed15e319c6f7d8ca1278c3aa9007d5f09bb330cba6d597005d06fa4a9f54ca09471b752350e2d473f55bdc602	1684082071000000	1684686871000000	1747758871000000	1842366871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
387	\\xa8ff8d579fb67b9c097250bed1a83526e569338a3dc42ae547d58d804fbe89fe87e00a639d1975c38b9c0636f9086a02db147adf7b0f9ada6ee30c385ace5bcb	1	0	\\x000000010000000000800003da97c7c6de38028ce1fc3ba4d82a6719774eb51a8f795a6d6eef2ba23260ff2c53eb72dac7d922321094b97bf614b0132018246de0828875e7bece4499ed04322a8e53bc3a165ca3d188bc30b8ee9a8c3a0375588ee970df30c25f19f35ac167544ae408f2386bb40ef24d1ac9c93d58a766d843d0d3e5e2b7f5bfe3a97fb687010001	\\x4b7d075c6d10187e3c8b4ebf72b894bb9a3a0176253de9e5a2d1a4a8ca4c986a8129f64544b5cd931a2adc8eb62c1f84ce1ca04e1f082cfe8ac1ada0e78c3b0b	1679246071000000	1679850871000000	1742922871000000	1837530871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
388	\\xaa276f385bc28366b8f3ce44be66db37aaf32d4d08e962634764afa655873fa80c95bb0549801e391c86ff69f93926da20920b771dc8de6cb360afbfaeff6e15	1	0	\\x000000010000000000800003bb412d845aa7ff70a916e47c892e6c91eb3b2af9a0f5848cd9520940685c8bf57b1b408ac4f0d248617a203e6fea845dc941ef05ffc0cba9b27e5e568106ee57290c304161d17f96e13ed0d990eb2627af498ee629eaa7574b57832c07112e0f3cb54e339e08217661b29aff9f78662c31a657ae402d7de91ac087551a1a2939010001	\\x7c001fd09be9cbbb7655e6d91d62710198c6f8001963d7eb3914668df98db507de32f9beacb176f3aa3884582dced05f7ad00a3aa0ecacc5090f52d1c83d8f0b	1675014571000000	1675619371000000	1738691371000000	1833299371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xac6f55b21c2eb2d44d08649c1a72865c78e59a58343335b5f7fd9f029fbfac41b94e17f93f95cb2909296ba4a14a01106387da171790f62dd0327b3877c29036	1	0	\\x000000010000000000800003a53477e879f8fdeae6f5b0c752f5d383960c931738f261dedbd21cb8416ef06a82cf3299e34eb6ee4c25380e5ab33aa85444dd731ef0a9917365baa0ddebbb07f5229b952e7aedceef45afd05ae5e0e9da603aff2e46b4070588d75fada145c0a9ec44e47e8e1518dd266a31cecf7bb6d12533b7df8f2f978049258bc7ec72c3010001	\\x418230f433268f8160040665543d2659f9c1b1f5ee41fcf4f2a6ce935ee851a918bb925b397ce9cd373071fb3e7613e886eeed85ae8e37b666c7216a9d04cc03	1668365071000000	1668969871000000	1732041871000000	1826649871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
390	\\xaea3a32529063798d31a35dcbb703816194762cf7f3d1ec9f62a3cda32af519353ec19827588d2a3db6d81db5d20045ecb536bcb8de3712fc26bbf465960de4c	1	0	\\x000000010000000000800003cbdd35ac716d39c60ac4c37a7cc1c6c0f084d0b35c8455edfd2f95e46bf4fb4f4bcd481d54a752a1baf7d648208b3897bfa5caec898605a80a24b5d4aca411e6e7b03040159e611f0eab6972a5526125d444ed32b0acd96acbd2512ceb30009665ced93bb03262a4384b0e8a78e46c2711c861436adb8641b57f2413de616c39010001	\\x38328907c9d943b45b749fae71215e19ab26d5de37a851c381625a2786d387cf5822b84b9004cfd9650a8956fd1739d65c30d3bf1c7f46738848568d9191410c	1682873071000000	1683477871000000	1746549871000000	1841157871000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xaf236d19132ca4c9b3b3637d27447b7cd9e4cdee44fbc6ea68ce7ff4a61c329b124483302dc0a71ec5bb3e3d45e5c9cfb065d66aa816969d9b40ae8e9ca44d66	1	0	\\x000000010000000000800003c91aae85c3e00d900ec507cfd3ca47760963a622629fd32e2330994f2356ca4d5cf3b7b7da28448d7fa68b4a411b9bedbc0add62a819363714ed4943ce2006edb4e36216c0af282eb34a9142ea5d122d9f863f9cc3bfa915ecfc47371c806b9e368208b872c2e08bc8fe689b69ee731d8315911af3d58f4d35b07d70de7be6e7010001	\\x16593b8024c81ee32e7b4ab4a2749d4df7ac9cee796fe1f1807242383e33b96ad73494898bff762f7c7e2a56369642801ac29f8849ef3d7a8af561b906499a07	1661715571000000	1662320371000000	1725392371000000	1820000371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xb137bd8418338de9e90de1b826cec4710f6de64bacf8263c82eddc3ee0fef2c696873a4129fbadaabf115edfa51779ab66546b99805c4b8dc4beba1c833644e6	1	0	\\x000000010000000000800003c4a2bcf95e21353bb75ccc9da4661df2fd92c14505e311332fcfab3160a834ccef68ef4866908fd0260f75406697e6cb008b09239610096421c3bcf657453ecc21037da7b03b84840f5bddbf1bf3503ac4d82ab0f52d525c8dd5a581358f87540845007444a8f0139c01297b638b34d96f6e69a6177eff145493eb7b0ce34931010001	\\x808196091620afb12b53e3ebc43bcc602af8a703f6ad2c978b6536b13b366f5cf9e0e07fb4a90355f6556145fa92fe6a8006b05f56e092b2fef9f14bcd8b3803	1660506571000000	1661111371000000	1724183371000000	1818791371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xb53b5e31d4eb6a957b31a71f00d94ac8d8870fb8c8b81d4bfa49d2cf2d7dbaa8bf5d551e6255ab81ba392853e55027bde28a5062eb125661c81bd18b89a04c11	1	0	\\x000000010000000000800003d9121bb6c049391b8e8f17c24238d03e74c21ab728877501acd1677a6e9152da249b8958b15f6673b25e202ce8de66fd72634654e8ac91e739b2a35d09dfd9e5b12632d9ba1d0123c72dc65e733eb4b6c7c9fac8ea9a560d21ba657d75e44afec7cb5fcdcfbb40922110487c916e5d8f8867dd7cda673a8b642b58b08d618f83010001	\\xf553ce4d968993edc3634a07510e26495103c8932880b0cd43807299f6195256dcecb3e3501f0e7f8eac44f1ebd46276afca98f738f2a25d46e57523b551d20d	1679850571000000	1680455371000000	1743527371000000	1838135371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xb7fbfc00173790df10d6cbd39bde1a288641b20770b6b53cd754ba7cbb3eeaed9ac7e0e02aa567d4a637204946f4c2478e128f66595995c2264fde24b85e00a1	1	0	\\x000000010000000000800003cde458f840a9172cf9e0346639eb54fb230840ba62c053f17a4b8796972d8149539630d3741d0836fe2666858d29b02b02416841d114f6bcd8a3415ccaf0af02dd9d6a3c091eec4c848bb954ba57bdec6a097d3e17a267fbd6bb69c5824de88edffbb409c461b4a265d315809c9af4715f6508cf423a4f4ad89f8a5e772efe09010001	\\x23ae1cd6c97766e402adbd32898da2ff5f5919e9c931be81fd8e1a77936f240c03899c591c3cb00cae33fc3f12632d294538183aeccb55d01f9c1d827a7ae30a	1666551571000000	1667156371000000	1730228371000000	1824836371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
395	\\xb7af794dfb735147d66f7a359f2ff339e6583fb9423f8bbcce6dd4481893526d49fa8a922a4304d430bb51b834ec9c290b3d4b207a51e00cae1017d583ffa0eb	1	0	\\x000000010000000000800003ac66f442fc32dee7d19d88e7aebee8c24a8f96834656a27244a7a7d372757825e1e03e5866b733c713c7ab3551041607a8d419429829f2503f0a988448c6b8947aef330f8ba2bdb4c97125fae13401f554d4acd9ead6b368a2bbaf32816c7f35a977c2e435d5de487fd47af55695212381947628629138a05a79f8c7f3b77009010001	\\x3966a032b7b7d54ddfca9011b4c849fb66db4a7dcd6df01afa9037cb3bb4261817cb91768e99c0b07916c6b3fe77cd2135ab149b3da2936f09def4790a7be501	1662924571000000	1663529371000000	1726601371000000	1821209371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xb77b5e303f79a4e47529a5b5c23e7e5b34e645955b61bc6aaa30fe086db0aaaf870d6314a9c56ee53c42100cb3f726663887ebcf1f480634080a076d3ee583bc	1	0	\\x000000010000000000800003d936f1bda5007d8eea27e74dee76fdf0d039d07d2857a9b75bd95e62c8936a982025cb4b454ce2f69e60754b06965137e7bdee48d2298bf5e833d7a2874a1f13f11bf069bfb67d8c99a531f16ffcbc30c5c1ed8c97080377e30547853d84b30f890b12359d89fcf953369fa621922fae672856a79d806a48409c52bbb6b76f99010001	\\x0662d38e98bbc795fa561981ad93b44b92416ad73f12e716b4b372d7ff3e2484f2627ea1aba7ee040a8ff5e8f460592464a8d396da0175fcf2b9f31ac2c60509	1675619071000000	1676223871000000	1739295871000000	1833903871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
397	\\xb89f54c7c34cc06078ee958f48064dd7e46a548c1c875f78d8f691dacb164df9cdc5a8fbe37c0a0bda5b9cf6ec298cf9914b00a9305078d100fc00f857f8e639	1	0	\\x000000010000000000800003b8b35aab58717bcdf1123e7aeb407927c811acf4b727fa0f1c5cb20c9bed12662a112e90515ecd5c2bd92a53b96f9ed71a261775d6b641523789429e37d4acdac78d21a92b6e59d53cd7d14bf9b832aa71d8bb32d9bc30c7cdac74d920278631f8be4625b9fa1ae057e906fe5b2fc6e5af4c5eb24cb3616570f56ff3840955cb010001	\\x1ca35baf28a15401a7c03eb7c721184a84e340af7bccdae40bfc64386ed19fdf65bba974f0bc04129a550cbf7e0a448fb04ef7eef615530b81eb02914c75ca05	1676828071000000	1677432871000000	1740504871000000	1835112871000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
398	\\xba6b2427f376f264496900089c598eef0e39773f343160269a39b63aef0aabb800111d7e76c6465ac0e376f6142f548d98d60ca8070ddfbcefa7df2d489840d7	1	0	\\x000000010000000000800003c2017b8100973a57c0c6b1db1cc6b10b33c99ea428aeb779cb06630326d94f7e8ca7f6b92790bfb789555bb5300dce4e2c6d11c0bd51296bbf115b33140d1d44ebde329fc1273b9c409543eb77c15d9f66f56725290630eaf1293e9fdd93d5a992aae5bbfb2569145506e24039ff0b07894ef2b8a1a4f25c860ee67ad04c4f11010001	\\xd6d445d1ac48583dd93f6ff3da0d45651b27a912e298433c886bb8f0bff70c132e9a72f42789ca32d9ec6ba997ecd711060f0d7e2f2f87fac52ce6c5969feb08	1658693071000000	1659297871000000	1722369871000000	1816977871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xbbf32358b2ddcd23fcc9b49caacea86b5b55625e5ecde554686ea8523b7bec9673e0abb920c24d117543b13d63812edd8755af3baf31cae301837608913f1d2d	1	0	\\x000000010000000000800003a3fb8ab0f574f83216f45a1c866bb0fb284a79358a2874b4700a68bdfeff0feb841b787c45a1270e8014c0fd2c9b4bed4182c7271851544639ceb9207f3d0782f52dcaa860294e7176ea2454a62aafd046c49632a63e8ac3cd11092dcf6110bdaa0b0f06c712e27db8359438a097fe7b4a98c092bebc208179e1aff2b2ed0995010001	\\xec29675a2a938f5f63988fe99cfc1fb89747638c792de70842bff45f108c626baf11bdd710a216119c1beb08bd452943162fe8485a26d0b9660fdcf96c016100	1664133571000000	1664738371000000	1727810371000000	1822418371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
400	\\xbfdf476db26431f897ea9b08b790c8ef1f45e4b86b92ee733b5cb7f9f097f2e4491a4de581a3332b64675ac9be73c6ef12bf2b363eafa7ad69108a3032824500	1	0	\\x000000010000000000800003cf8ec40529cdfab9c4381e26ce58bacad0e5d673cb7ed51c00d51f607de1e18fb634f3ee7d47b4db88f76ca475fdabebc7764de5e5df72e24bbcd1f4efb51b9cc37ce7a4de5d07b5628f9e53596d20a88bac985444fb7ce589c93465e2ec9068a9f57910a4813aa4b84130d28eb473cd3e4ecd24b6e849de18c7a41e88eeb2f5010001	\\x2c672c0763237b09e16dcb7a78fa647aa3405e6002b85b6d6c030b5b2e05906604bd7eaa9940fceb0f6483d17fe034e4d43a4667f2ae0cddd1ca83572ac8320b	1682873071000000	1683477871000000	1746549871000000	1841157871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
401	\\xc41f0061052f1141b93627709be2bb0ef3afd5ed3b1b0d6b9d7f4d2d08577b42867c5bde1458c9ea540094bf965756c720b0a6f47addc195f9d17cb52ff02103	1	0	\\x000000010000000000800003aba13f9ea3ca05f0445f94fdcf3e00c57579b3ae5946298735cd6c65e00a9318829b08d91fc1d94a627ffaf7fd7b512c059a95cb7e0e2b84e7818f6190c2d432dd1d957f4559412d356e1b6d4b980ceb9a6f29c8702b7df7809a21b7d89eee9ca9e69ffa6aa97aa518bf8c3b16fc951f5f83ecffa7bedbd082b228ee07f84d8b010001	\\x1530427fdb9d429bf65e21249218ebb4f49dde0fce6a8e0a7439d80056beadfd2debc474981ccb4ff8fcf92bf35fc6752601e4f12a4b8c915154273f9ead0b05	1682873071000000	1683477871000000	1746549871000000	1841157871000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
402	\\xc54b96850b7c6799af20a86eb3a71933c0b2a078687def700606cee77471d2a18f48517fb6bc5fd7bc07f3e9db8945617ad45352a55bad7600241159f305c68d	1	0	\\x000000010000000000800003d4df5efb9ce0263aca262ac06807bafce09d405b0bf442aa3caae7c70c30e99e6594f5e9b35039a064d45b474fa2faa4e278ac7a5c81374d27603c7c0afbb89457652e8c2d0921cf91d03189b26af89f2fedfd00ab04c623247b2f8843bbdb35b2bbb4c6b5f73c5cd92f1ad455ac4f9807f909fab8169b021910be782904d47f010001	\\x6cf13555ddbc03ecd96390794e221f0a9e67d878c21ff243e40be12460dddeec8b2c7f680f7ad990c9b0ef0f746de89776c3460aef9994da5ac6eb26023ef804	1671387571000000	1671992371000000	1735064371000000	1829672371000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
403	\\xcb3b6f9be100b720fc1233d0d14e7b8df8b1b2ee0814a050f8831993c6ae7d83a619c1fd6d559a72e2585999efe6e644fe38a65e2430bc7ee1b934def58be88a	1	0	\\x000000010000000000800003b2430588328011e2058d0142c24d2108e85bba036f038dacf53caca89b46d129d0a3ab210cfb18cf98931f3e857ab6321f8bcb46885106fc7ca6622ceb3ac87e67f44d762605a5bed3a327b88ec33ff3b17ae2a8f6612c4019711d95e28d3842fc020145e46005c92bdf3174f74fdc20256fda40ea6c95f1e91d3c4168ecbce7010001	\\xaa691024eebb5e689e6bbe7de95337aa288f2e9de59cefa7640a3c8f42b8c9230a320576f22af1c8ccb8865349a3a658cf10133a916290096fd964e0a86ffa0c	1662924571000000	1663529371000000	1726601371000000	1821209371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
404	\\xcd97e7cec5b08cb80638568ea22473d164ab29d8c779df2c5cd4a983424d17ab00256de0194039d61ac4877f075c57ebcd8b91ed403698a73f06ad8c32430477	1	0	\\x000000010000000000800003b47b5c101040bc951ae47bac6590c19d16ec5e335172df83635d7cfaf5410f2ae3ce5885ae32ff486b6454a7cd7cdbe17168084728986ee8c01ca6d7aa5ba396e90b11472f2effb3ec5023561bac8ea447f7e49e2f50ac8eac035254fc14d35ed0e16797e2936c941636927a372c810feb0bc9592d548ca7cb97c2ba4478f237010001	\\xc1b1b2b3844772a31535808bdd92b476a5970bf1ccedb255a7bde2aa7bf2817245b2f5e0644ca287c1836bccb78db57c4c23e9bc89faa3b4e8c57b925187dd07	1680455071000000	1681059871000000	1744131871000000	1838739871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xce07c59ba27d2a168ead5de34a4dacdd374f54adbaa8902b08e991094499b61d3d164082f69e77cd58087fc52953674bebf90dc1170278e2ab062bb27947d0b9	1	0	\\x000000010000000000800003ca26b8892ec981c3faab366abf502305f43aa0b8b4feb35cd332d07ea147efbccbb2b160cdca8e59714dafecf888fb04e33c2585a66f195e2b9babae1bd93fb032a847861a55d166a41486b620158a70e70b7652cc612ba6070850b5e6cfbe4fe8ceac80ae535eba8dfd0f1580fdc98f1fa223da32d5d33f2d381898929a04c9010001	\\x3d7b9fb3e71b3defba061228d4946c11135e0ff8e77f0a623f2b908a83fe70b63c7f1610791f81807d07d7e2f1a547dbf7cfdfc6be278a6e7a71f9b40dca3506	1665342571000000	1665947371000000	1729019371000000	1823627371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xceff87990093147fb20061f052a78b52dd8a06e872f6cd90f883d076a5a0ef1149238d3f5be7584befafa83582dc9c7bf054f4b7174bffe7af67ebe0d44f7a60	1	0	\\x000000010000000000800003db237d514de6aa63dfa8c205aad6ef3cdfe5f787406891f57acb709a0f2399e1d8a76b69d70d0ad625ac620e0bf0979fdc9beed4bc16dc81ca9b089d75ebb1dd7eb30cbc3f5573f7ae094681361f111e475b43cac354ed6ee21377d394fc50dc25ea5abaaa0e78b252bb5327b6114bdcac3225678097d7b327d5d92877fbaeb3010001	\\x7aa6ad0d3ec16dd466b9d8b7a64bf019e4114b3c5f52eca014859a4c8d6fae3692754b45c9e37c3de9c2fabbb3026f75ebc5456a73ac181f3316938431e04e01	1655066071000000	1655670871000000	1718742871000000	1813350871000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
407	\\xd2c333a065c4398db65b6342b310baf7a86356aefc20a2f540e6c4a9af8fb91238c8a7538c226567527da47e638149ed5d9a36336635178a2381257d5d7c2b32	1	0	\\x000000010000000000800003f3fb44a8cf10052cf8bd67c6726a22826c52772f40d025d4bd8c5d82351a91bed9e9d96dcf68cd7a07ef2d6eb596101df562a51c234ae2791242dcb1b09f88a14a6607351f923582e83605022cb069a540915df4bee37fb3dc84fc584f9dc111439de6c76bcd9e9f215521ce90136b2991a7e53e5461abf29f9662fd2ac07c39010001	\\x7038bcca685c8af4871f3989936798d8716b115c80a9c3fc611522b0968f152806b278e1388bd14fdea458a771e778e3ef75a69f1b24e072ad3e2a3209116f04	1670783071000000	1671387871000000	1734459871000000	1829067871000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xd7cf140d8710f0195179cadf9515816f0ccbdcbcc2e2edb8dc74a5862a0e18e594f9c6bf3a51019b5f74ce62bcde35e7008bd553440e61aafff66be0023bfda1	1	0	\\x000000010000000000800003b13a9272c1e379034b066d18bdf4093d7223dd56e9e605b198e26e7ebcdbce940af758c6f9fe2e9138b04e0c69d11e97c803dce7e4d1669110d0cdd4f7580e7d31cb6e92741ef8cf6542b1c1bc3b9016d2e7d1797d49841aba83bcad4f52eba363ac9cd9f10068b85e88e9b35ca10201715439c9b2780609d2e5b59250f9ac8f010001	\\x9a3345d0cc96c583b7b3ff25299995d2f8fe8db8c039fbebd0224228a18c1c57025bab2c8473ebb01421f3dfe066493e5c603bb24236f4cc815d7bbaf9e6980c	1682873071000000	1683477871000000	1746549871000000	1841157871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xd7d3178744a9269d64faf46cb7c597428f9a7e9f7597a7d7141277d969ea06e5a790c0882914d10744498a085d5bd530a47045295b84389077c40f7a6d243628	1	0	\\x000000010000000000800003e64dee11ff13ea4d3aba5e8fc00463b12fdf03fd28a41b033650a97eef23d094262d097220c7a6f177cb6dd090bfed02e94b491de51b8f615a3350168d9cd6fc6b942a4d3965f61838bef5fed08a8384404b916d879851a052dfccdf084b40892a548e8f382def06bd3f7fe117ba10ef2ef837d84ac5d53595008dd4e7d70465010001	\\x6b6c07858d16276b1467e08f7087213ad6b34e2718b3d7bda5bdf81d27e8bcefc31bf1751d710abb8a949dc53f668a792928fdd3b1f07641301a586c86daf602	1673805571000000	1674410371000000	1737482371000000	1832090371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
410	\\xd847a793c5d29ac83f09ee76c9147695ff10e907b2443ed027e004dabdd5e4fec89db750e4d5b549b9d91ff6747eac0ad84c348fc44ea8d913bc276fd40048bb	1	0	\\x000000010000000000800003c7977099c071b436e18a5f510895a22a99da408475ac8ac00dfa9638d1b1ac66f27a9e52e342a9dbc938594f88468ad5c31dcf3e9ca97e8eb5014babe44bdb14f9194ed5599f3ed1635acc6bc5307375d7c1d64d3355007f18c7193f31347bfcef03cd8ce519f3344b8892189c8cf5b7a32ece57915bcda84fc249c33163467d010001	\\xb43aa82df2c54aa82a51f30f8319e5099078a55374afac0f337a79e8e84a17159eb1c699803557a10fad8e37b15fe02d39158df2e6aec4d85a23dd902479a106	1655670571000000	1656275371000000	1719347371000000	1813955371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xe0179fcb456bf9eee2bc96c04f3656153a7b38c835a0cf41d0b1143cba9424855150455124796f7c62fbc9c7249282f20bd8609f6f9d2309b01aac2ee92b65db	1	0	\\x000000010000000000800003d78ea1fa013a2bfac70a99d7205c070b47574f5f51bc9567cf90fbe859f59e217691cc8a829799507b448b0165ee890cb2a5ee0e9b6bc00b38711d70237494f4ade11f5bd8fd7c38b7e2b7994cff8ec0faf1a279a6a8c8415ed42fc655b10063a5cf587ba34d0d6cd6501deab7272b1fd8ff94e7936e05825c0fc01e2bdee893010001	\\xd8ade372b428a2cf2cca1fe4670586fd6e867cb00475389919a8d4433ad34d94b52e2ef68decaec7ab49febaa1961af5842e7638836c8da20627957e4923ea01	1675619071000000	1676223871000000	1739295871000000	1833903871000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe44326b4da0c71425d4ed778f8a4d07e1f62bc626b919e6d9c71a7d48bf85b23477508d7c07cd1fc68945f3989a40087ad69ac3d30298bd4d997304f94100d39	1	0	\\x000000010000000000800003a30b2af1525ec7d701a1908849097b4e065ef4372a39863f10757e7c1ec41c254ec0f4167213079c84f4485c571e5f3d7e8eed94b610767f975ee88b287173f14f4ae69db72bb2dd79b1429293d29bf6151d9094b6344397d8444bfeb92195879ecbba2d9159098724f499e5e1adaea948037b5f827fe69c3bd9b37878bae4e7010001	\\xec14f4247d660c0ce4329d51e28501309ceb71775e7c11cac8b3eaff740534582ed9246fb9872e77ac49edc8725441a17b4bf1d04aea715ea174bb5718aa7e05	1655670571000000	1656275371000000	1719347371000000	1813955371000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xe51beb539800d62ee661879e9b0b8c66406c29b9f8a8a503bf975b7426950ef33cd56c936d175bd6e5a93350511cdc0721e68e43a4a43cc1d59e364af2e03bee	1	0	\\x000000010000000000800003b695db13ff042a8c6e98eb0066cd9f3d36cfce2370585aa37ac1d6a5ef9b3ccac44e9f441b2076043b6faf3668ae07eff0479d0508c6dc91c0ae835cb7a1762f1aeef2c23c413886640d9e83ed983caba0eb9c9d5363f14c3eb91e280cfe872e47a96876bacbf1ff367479bdc43478dfd2668678d9b9763b0c15867a057f4c7b010001	\\x5ec6a814ae9fecf90bc8e43388abd65d8708f12962a0f5c5ebda562356926f4279c98b0d81dd73a5495b24cd44332157b2c838dc3dedb006b03c04c0dc11a30b	1671387571000000	1671992371000000	1735064371000000	1829672371000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
414	\\xede72512f697b18c1dfcdbe73c19df70859cde7abb2f4c2cd8c040595783a26d1654a959d06fd1925073b602e75f7650859a5aa9ca9a4d16749c013739882d15	1	0	\\x000000010000000000800003d0c4e66eb7bb0a957909ebe78e36e0c875a967dcd1c0c05074afc342753798ef1f2b9cdf45f8eff044adce59593f77551aa38a1ad522acc63c4c2ffe8d1ecce157357568830ed91d1f477816fe01b937055b64ec4e8278464a2c133acb840f3a211dc25528071f11c063e070be571dbec0f7bd207e9b6c023986ffc5d152c5af010001	\\x027b158e08c6aa44fb3e5b59329d15c07920bfbfd32888f25bcd7d990b8cb2fe5b425ef044dc0c8e0b2fb69495dc684c8d22daa5d6df412469e638dce485070e	1660506571000000	1661111371000000	1724183371000000	1818791371000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xedef03d890b8d2fcdee82f83e74f72827883b4700a5ad1abc51399371edcaa5f24829ecac55ea808ae83a7842af5a0514e97de19f00237f9b8d527407cee8f53	1	0	\\x000000010000000000800003cc0157d0a43e2ae5d37a3ad56f294aebc9c1baa858061f78a1a85052cfe36ea89d39ab96046c7c32eccf341c38d3efbffd79e6897dc6a20a162886bbc7281bee3a07ffcfce89acba4a5fb38b883d9a2d98fda086984955415567454f6e084720282c1299db469df01065a2c26272b8653e913f78742867493b1c8c2f46dc726d010001	\\x82b7e54cbf8faa62406da5159c6c88174e191bc54196d2b871c7dc226a04653b4b7d715c1d97979f65017a16cc04591dfdab675b3eb4288a0924f75fe90e4004	1657484071000000	1658088871000000	1721160871000000	1815768871000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xee43716b00bcac4561999c44df22dd6c1b562dc45f38b19b1dd164518d3636c0ccfa39d43a5abfff55e70e8e58f8b0f06e7396d2fa66e34b8ff0413083f3f684	1	0	\\x000000010000000000800003d34fd303812f93fb9c82adebd698a4744cd5cd0428b0499b5354e63fab0f69a77f7bed8b13fa56d28352434019cca9c2375f3120789cb010be90aaa50d832c96d035f08a416cee6c3782e24bd68858ceacaebf408a8eb8860104c92ec9d44f0870bb38a338699a5accc06aabc6cff85ffc0c7aff59fc390e3a57c72c11246217010001	\\x18e504d1f9796a3d7df1ab3681840bea61a0c27ad138032cd5e8c2c0e795843e4ff65224cca3e2634748a62cc9f84263ab24ed318f1d04a56b1c0512613e9305	1672596571000000	1673201371000000	1736273371000000	1830881371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
417	\\xefa3f4d57d210bfdccedfea2d787d63a781b16c6179cbc279995e7d2c7ae52981ea8975fa6a631c6282457c4f0f7888bcfeebcf69e49ee73c261456ab5409e9d	1	0	\\x000000010000000000800003d0ef776443aab7df9a259ff566e74c00db1ebfe313c4575d29ae75688496e7d0820c6f343d4c062ce3529f299e09debbfdba6121a584debca3ae7ff001765666c6bd7b0631beb64d76e5eebbbfc8301ba4d424f7f716013ab19263fa63368f489194cce614ead6f639105a0951e12081aa8a9ec66aa046c05f23a84e4abd758d010001	\\xa7cf2821968cdd72bd9e30cfcecfa7bc76eba5f4de36eb480690e025ee54a3a05f30a875019c7fef5cf548f3d020305223f465d0f0a1a2cd50aa2e1a8e75a50c	1677432571000000	1678037371000000	1741109371000000	1835717371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf0e3f502bb26f2590237248e03c9d99cc32c58ae019ec594e2406b16b8e3528ab520e5de3bf58398de2368e1a53a415dcdb1e77dbaab55cddf095e48ff4b9813	1	0	\\x000000010000000000800003b947ba48b8569dd600ce89408c35920620fdc5d6b5c34245bef9f23eb82a911020a383d923cf8779dae4a48139b4737d9c63ef1ed0ec18ba85ac6eeef6353dab610775f08c366bbd4555ee1a878c075b4801089492b01b1656fb3badabd27075faef577ca0ba8e7f2312a185caad846e0af8190f2a01683b63a280ace3adcf0b010001	\\xee10052c1a80f77f0f06c7a31de1eafa875d669af8a6487110e78aab21fc685fbaa1f782ec81c9e72ec11c3755f78366f3415d5f7114b78e79d725a641dc3409	1671387571000000	1671992371000000	1735064371000000	1829672371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
419	\\xf49308c2fdaf691c1568a5998a52c4ba5ab4537d3fc698d2164526fef3f051bc0e485bd9616c5d50f08b5f8fb1cdd71977ae394fcd0948cd33bc0fcbfc63c8a8	1	0	\\x000000010000000000800003e616c264bcbe4ee1472bc782718f4803fc9bc43fbcad7f3ecad0be234522100efe8a4fe9484e4da054a941f49c60dbbfcaf1e342782ad4ce1da6fbaf47cbad10ca57a38e9c694d4885947f169236f1e8e31dbe0f4f1c83fdf5535ef204863920ccf60d3a2c7a036fb6ce8a5c1fc93f00683a8a692ffa7a523dcc63d9b9d720d7010001	\\x6d2ba7dd3a201eaf58c63d87e397c4021c73955663353a7c1a9a3181ad7a4567f037169b36789259c43791749380bc40156aa890110be2105b517f337104330b	1676223571000000	1676828371000000	1739900371000000	1834508371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf45bba071ea5c0e9778dd5febf59cf9f9ca36001fc9cc19d40a90e00fdda62f7ed0f7f44464c49cae5ecf57400f190a776dc32f7050e8ab117ec74d4575d395c	1	0	\\x000000010000000000800003f6969319cdeca0877f8c5ae77acf980897e6e9f292954090d4e1057b0df60d7f2fde6cd4572024f9983542369464017fbf06a4428a3e987e1f93608a81381e0d6a033415fd8da6dda21a0d0a01c9757a868081ad241d0e8430ff2fa0b689f00f8894a86ec4f7765400164591944cdca0e457e641238617d4c5907748ac8c9aff010001	\\x1711ff396090f3cefad8087c8926ef96e22837cd20dbd23e3b553edbd8cc34113a29ee8263b4000e5d256dee4fbdc8d8043d18654781f426e109dd1d025d5a02	1658088571000000	1658693371000000	1721765371000000	1816373371000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xfd5b1365ea12a2d1e8b30c89d4e488dcd015c786b302898490aaa0e6a54994f17d26220544346571d85ca81a2b5c19107aef2f86884abb5a249493276d816737	1	0	\\x000000010000000000800003bbdd2df7bf9246f53db1d6fe70dc2a581aed9983351d4d20a05fbc786954179f1007f78e0060241da42b62bbe1c12a56f2de459be9962516fcd7e63c77cc13362fc08b414ed199b26b2024a72fc5f8beabee19de8dab2ff672f98e352f35a08f9cc6749f885e9cb2f35840a1f98043a3075ca6510337de2a2530c7f6512026eb010001	\\xcdd06ed7756af3677078001372f48ceed28a0d8e5191e9f6017dea65903b59c631eb5b11d8b11e11bbb268f30adf5dac4d893d3051d473a2f48f105fb4e39f0b	1673805571000000	1674410371000000	1737482371000000	1832090371000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfd375476a3fb3bd4b6239638d985b62f3bd144209d465e8901a9614ac0878ff8046ba09baa4bb7ed77a21bed0beef7a940ee366ee1e35213950fbbf0b36724d6	1	0	\\x000000010000000000800003cb78817118ec728aeb55aa7d7a52426bb43a66d14e5abdf4626691e48f4e5b44f845c7794d64f0658a611122ad3dd0ddc96d732ad25aba367f57fea079a20389b25e328d1fd387e5336f573f5bdd2af6378692e3007fb24f509a89d712e721cd7d61392519f5390aa7514305b6adc433a7dd46653d28420e97bb32c6dd6a8e99010001	\\xc23bf2eed6d56779dc9269c4dc0729b35d825176dacd395ec3ae147e2317f80f7a167c2c805f99b6e47caa4607190dc41a545fa3e9bc33987d008b88a0886106	1670178571000000	1670783371000000	1733855371000000	1828463371000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
423	\\xfff7058834ac97e55c9b0c274c1c2aa8e81c279a1ec411ac86e750eafa0a45a15432ef648e2e9ffb0e072764e739198ede1d3e585c1e7105e9c39050e12da4e3	1	0	\\x000000010000000000800003f6d83372d91d7ff4ed4929079e74e62f3c314a92150f475d3aa64c9f47ed81f28c56f7699120e5e7a35a4c44e3cf4643d0192ccb6d7ffd661379957f4b8444a335e89d4fbd99a50922b2ecd66909d5a6a68c1edd60863afed04ff06c8c149ed136dadf0ceb8071a7b7a24d25d30f097ad08da8bef5b0265e1e114b0f6b714b39010001	\\xb1ba32d2d52d339cb14353bf0c9ea99079b2d93d682d7ff2c1eb6591343b8ef15b5e43ff9205221ed9b43e564eab9479935b050172d9772d38e7b521661b1805	1673805571000000	1674410371000000	1737482371000000	1832090371000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
424	\\xffb3a4721d76840d8e5eaec9b2841c7d7e89b5088aeae34a423d9585fffce337178b437a977e5d94e95f4d6823059a1e33b0cf3c9d236fd07d35095566a2fa11	1	0	\\x000000010000000000800003e3dda107514cd68bd4ded2296f43331b26963b44b2ef420e6b34948f565ff19e05b8252c5c2cb1f194b42642d5b88a2b6a828c7710847c9d7ee84e70817c20a8afc5a6cc9e170a909c0210f1a55a3fff0ee3eb4ada1dcee0032e884d1c63283d1ff952723d99e7849793062dc1ea45477ed98322a0ce45320f208b14e88acc83010001	\\x5df7cb2d480e68aad21f6065ee0f753771ac89c80f8ad63c3d220b908ce43d0ccf801d0530ede0915f1656e0f9d82742ec7f202387e07873868ce1c30f640407	1658693071000000	1659297871000000	1722369871000000	1816977871000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	1	\\x192e97d4743b593f2f1292a4009bcf40925b2f577a369ea44db5f76c6740c16e24902f0944a7bf5a9e1cd8f9810072c22dd3a4356d3b243e46ca90282cd684b1	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3ff13d611d30a9d550135f664ae2a048d9a9e0cd1342587cb20c66cf0b2d3943afdd614cb8752f4cf64f6a12644c8ac841a3d471653affecc27adc9a7045a62e	1655066102000000	1655066999000000	1655066999000000	0	98000000	\\x19ebf2d603b80a6de27ca7b068239cb2d1f3aa0dd70b536e6f4ac5e17096b1e5	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\xfd30207a694a28ccd6f958a03b434d9bac72d0de3cf48631b3dcfdc7a0d6cdfdc5a57f5e5eda1b5d45d65ebcc2784cf0a30e6726d05380e47052d75ca48ff104	\\x21f6ed33827b0d34297757aa43b6372e5662863b18c6cc41021c5b4bf463b640	\\x3086c531fe7f00001db9dcc3da5500005d65dac4da550000ba64dac4da550000a064dac4da550000a464dac4da550000e0eddac4da5500000000000000000000
\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	2	\\x1004a7fc06dea41ef71f47592ff498724de8190083a1d7b6309b30af31623a9199440fcd4c7bbd728befa004758360c988c8613d16f1d779210e5d7a0ea49df9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3ff13d611d30a9d550135f664ae2a048d9a9e0cd1342587cb20c66cf0b2d3943afdd614cb8752f4cf64f6a12644c8ac841a3d471653affecc27adc9a7045a62e	1655670935000000	1655067031000000	1655067031000000	0	0	\\x00b749ffac015eb1f0e1ba19fa403156bb262c098209202f161db01c05e9c9b7	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x31ac26512a0f068a7bbe5b8238742e15253a767d72938badfeec7f65fc56c0051d6d6d8075b5b690bb41bcb9d72d923e80a2cd57dd335f572167d80b155c0900	\\x21f6ed33827b0d34297757aa43b6372e5662863b18c6cc41021c5b4bf463b640	\\x3086c531fe7f00001db9dcc3da550000ed92dbc4da5500004a92dbc4da5500003092dbc4da5500003492dbc4da5500007067dac4da5500000000000000000000
\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	3	\\x1004a7fc06dea41ef71f47592ff498724de8190083a1d7b6309b30af31623a9199440fcd4c7bbd728befa004758360c988c8613d16f1d779210e5d7a0ea49df9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3ff13d611d30a9d550135f664ae2a048d9a9e0cd1342587cb20c66cf0b2d3943afdd614cb8752f4cf64f6a12644c8ac841a3d471653affecc27adc9a7045a62e	1655670935000000	1655067031000000	1655067031000000	0	0	\\x037afa253679c663bd04f7bd1d0cd38569e28954bcd5f57fa6ce100db655b182	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x4bc8d33c21dafa5c2b73e1d4b9c9a81530bd74b266cef7f65d404de1e242015a29899eb9be9eaeed5b70d15d30d0d0823318a939680c487126a3fe7af625cd06	\\x21f6ed33827b0d34297757aa43b6372e5662863b18c6cc41021c5b4bf463b640	\\x3086c531fe7f00001db9dcc3da550000fd12dcc4da5500005a12dcc4da5500004012dcc4da5500004412dcc4da550000306edac4da5500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1655066999000000	361318039	\\x19ebf2d603b80a6de27ca7b068239cb2d1f3aa0dd70b536e6f4ac5e17096b1e5	1
1655067031000000	361318039	\\x00b749ffac015eb1f0e1ba19fa403156bb262c098209202f161db01c05e9c9b7	2
1655067031000000	361318039	\\x037afa253679c663bd04f7bd1d0cd38569e28954bcd5f57fa6ce100db655b182	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	361318039	\\x19ebf2d603b80a6de27ca7b068239cb2d1f3aa0dd70b536e6f4ac5e17096b1e5	2	1	0	1655066099000000	1655066102000000	1655066999000000	1655066999000000	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x192e97d4743b593f2f1292a4009bcf40925b2f577a369ea44db5f76c6740c16e24902f0944a7bf5a9e1cd8f9810072c22dd3a4356d3b243e46ca90282cd684b1	\\xb96dfc98db39162636763c885be6e8767e816f01c10dca557b1f6e6f2ef27125c6ceb232fd38021e44c550ca041459c681eb86bccb70a62ccd23ce48333eff02	\\xb10d0ac3c619e20dab55c23d1541ef7c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	361318039	\\x00b749ffac015eb1f0e1ba19fa403156bb262c098209202f161db01c05e9c9b7	13	0	1000000	1655066131000000	1655670935000000	1655067031000000	1655067031000000	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x1004a7fc06dea41ef71f47592ff498724de8190083a1d7b6309b30af31623a9199440fcd4c7bbd728befa004758360c988c8613d16f1d779210e5d7a0ea49df9	\\x8a6a1b568792373df9c23d603bca277bf33df77ac40da664d79be9fc2479f87f99d7314ff58cfabb5001e159b6f1bcb7b0a030069ce6dcc033534e91f180e100	\\xb10d0ac3c619e20dab55c23d1541ef7c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	361318039	\\x037afa253679c663bd04f7bd1d0cd38569e28954bcd5f57fa6ce100db655b182	14	0	1000000	1655066131000000	1655670935000000	1655067031000000	1655067031000000	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x1004a7fc06dea41ef71f47592ff498724de8190083a1d7b6309b30af31623a9199440fcd4c7bbd728befa004758360c988c8613d16f1d779210e5d7a0ea49df9	\\xf36ab92f21d590f4e454af3e56870332fffd49e4e2282b7210009585beb5b50e63d586a4ad89502e4c9dde591a5e3bdbe32fa350fe74ed0622ec491d4ffd4a05	\\xb10d0ac3c619e20dab55c23d1541ef7c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1655066999000000	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x19ebf2d603b80a6de27ca7b068239cb2d1f3aa0dd70b536e6f4ac5e17096b1e5	1
1655067031000000	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x00b749ffac015eb1f0e1ba19fa403156bb262c098209202f161db01c05e9c9b7	2
1655067031000000	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x037afa253679c663bd04f7bd1d0cd38569e28954bcd5f57fa6ce100db655b182	3
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
1	contenttypes	0001_initial	2022-06-12 22:34:31.646129+02
2	auth	0001_initial	2022-06-12 22:34:31.78137+02
3	app	0001_initial	2022-06-12 22:34:31.871402+02
4	contenttypes	0002_remove_content_type_name	2022-06-12 22:34:31.882508+02
5	auth	0002_alter_permission_name_max_length	2022-06-12 22:34:31.894292+02
6	auth	0003_alter_user_email_max_length	2022-06-12 22:34:31.906259+02
7	auth	0004_alter_user_username_opts	2022-06-12 22:34:31.916248+02
8	auth	0005_alter_user_last_login_null	2022-06-12 22:34:31.926916+02
9	auth	0006_require_contenttypes_0002	2022-06-12 22:34:31.929914+02
10	auth	0007_alter_validators_add_error_messages	2022-06-12 22:34:31.939574+02
11	auth	0008_alter_user_username_max_length	2022-06-12 22:34:31.95594+02
12	auth	0009_alter_user_last_name_max_length	2022-06-12 22:34:31.966611+02
13	auth	0010_alter_group_name_max_length	2022-06-12 22:34:31.982021+02
14	auth	0011_update_proxy_permissions	2022-06-12 22:34:31.993695+02
15	auth	0012_alter_user_first_name_max_length	2022-06-12 22:34:32.005795+02
16	sessions	0001_initial	2022-06-12 22:34:32.027494+02
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
1	\\x814e98f4e464b9bc018129534fc6d7e703207ad62402ba4c518cee2bf28c19c6	\\x8f29dd31216d8d1bde0cd963271ef4aa4f977ccd49613437c907aebfb64943bb77fbea97d553a722d504892531406fce5a7443b59f9184053564e7af62ede301	1669580671000000	1676838271000000	1679257471000000
2	\\x21f6ed33827b0d34297757aa43b6372e5662863b18c6cc41021c5b4bf463b640	\\x193ba040f32eed4366be0f75a69da2a66fb4d13a0b83b6f4c121b33fc61698a90b5f0e3a3a97e0f21cc614a7f06a2c613a7990c3cb69dd7823fc70034154450d	1655066071000000	1662323671000000	1664742871000000
3	\\x23eff2e805018280e53ae04305e19d407688a68da098a6c077b1315bbba78b1e	\\xf59f69ffbea987cefde2755da442c8114ff9d3250d371284f03910bcf40b8a81a1d6bddfd72fd3cbd97e31baa31d750b50ed47e78fbdfe27a61edca35c273903	1684095271000000	1691352871000000	1693772071000000
4	\\xb05cbb8344d9a10f08fa10026dee54364fe3d32296c5524f01c90f8bb7c58919	\\x5047f494c403095ff0f51a801761a7722d1c92a771c5e7dbaf7d1d5f2af0f4f7fcdd17a641bf71687bad841fdd98206d01634c50727a2427593b4f7b20a1d20f	1662323371000000	1669580971000000	1672000171000000
5	\\x17b11c4379f0a4695f99ffdbe30d2f0bc23beb3338c2d04766df62c4c5858a18	\\x676571787025a741bf85e9f24ebd577e62e53c9cb22484453b96a434efaf0dfb455fce3bede808902c4fcef47f55a5d256850e2552f026b2aa19a9bc74492803	1676837971000000	1684095571000000	1686514771000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x19d4ba0995a462256f6868533efe20d7015e7673603a4900acb33359da5a31c167d650fcb14aba9e516cc8b63e127b7e531da298eed4161fbbfcfeba4e05c708
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
1	264	\\xeada365013ad84023e09c7e0bcbc428f0a18cec7d82801c2ba402dca21346636	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006488383fcd928d7a303e43d36cea6ccb9164b8a867e84cbe5972a81ea87a4de0670da3b8402a4e6cf8c99a74be5e3c60e0af17694d9a4921ec4311679d406a6f4f7b04d4192442b85400618c0c2e8e2692c82d5f69a765d4046ba40a54bfbc034434e3191c4c175ac3b36a39529ddd07688c3ef5d02a59ed58bcc8e9e50b2a24	0	0
2	406	\\x19ebf2d603b80a6de27ca7b068239cb2d1f3aa0dd70b536e6f4ac5e17096b1e5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a459b068c738a32b8aee82f2376b13b8360233985b53884c3a09637808ddf3cce7bf52f4fe7bafb406a70dbd949d27d8671efdc1719aecb3683b9c7486d19f4a725ef0b42e27280fdf52093386b112aba2ec55964d708cced5c84e5bf8d0660efb8b3ff2a360971fe90fb5ae0884351943de59aa404a45aff891fb234a7cf36b	0	0
4	410	\\x0b3813af89801ebcdb199affc986799c8e6342fa61b8fb46b4e828fa0bda266b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b11a38ee9284aef4febae583a01aa877d1d29728e140cd5c3fd162db7564f9c4cf979780948d0d28902413532ec9dda18ea5b4143f11165ae086d8afd41ff1b79c6eda8909e7d7854939d2eacbcaf12cbcad69cfb25a0e0701f94d185646dea320a097cbb8c52dfa6ec972cfb2c3be10fc93d1d8bbd50c48d72443703b20f3ec	0	0
13	326	\\x00b749ffac015eb1f0e1ba19fa403156bb262c098209202f161db01c05e9c9b7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003a226d2b3f949a078f79074993eaf3d97e080b488155ab9e87315c02d70b4955894c06a144dc7149f12463d8be39e5a044e456c96bba1e4010317503bb9662feee6e5ce6efe92ad936dbcfa41852c3ece719f2d771bf868ab3495213d9775a0f25bd315f4c8cd183d73c5e04a12ae2a7d60449890d892329294a7c81abb152d2	0	0
5	410	\\x0d6e1fb3d79268d88d6f822373e560f9bec1059a1c033723abbe8a76fcb92528	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000047520daa09f5b5c4c148310c4ba436c7eb599a39dafab3b02b2299731e7935e71e51e90454a88e70b547336294bc6cafaeb2fd6ac69b406eba2288bbcc20beafde8f7f64d5105e7aa0ff4f44eed5308400af8e9c52c8637e2ec0923a9b7249d16447563184aa63fb34191f57df9bc6757f540658dbaf38db74207cf9585367ae	0	0
6	410	\\x4a81f66736752eee46fd5e61756e5d1c54f2dad69f8d4e8448f441b8e0082f80	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004d37879ff2914e6a74e195cd6dd5385e744e85f1a49c58abfe3383b2f01bd0a2d5cfb742b726c5e72be452995af00d344c067a6a35f3b39b2eab6edbf19307d43f6c4cad0ce37777d2280ee60ab63b5322f69536aef503c31acf808763b9c4375d9d7c3cd609f433d54e36e4d942bb62217b8bfef6b5a3b5e9353308f74b1dfa	0	0
14	326	\\x037afa253679c663bd04f7bd1d0cd38569e28954bcd5f57fa6ce100db655b182	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000a87721696ee25e859da3c235185ec9ed967ec626a9cf5699e0a7d6bd1a98e190dedac6a497b8a63d821a49f419d71b91a073f2dc97625873962034c83864b9134a6f0052a6e2bd77920260fe84a5a4b1764ed8f0bc8a9bf02ad96147861088aa1d35a83ae774a833a0d983fb6989fd7b4febce93acf38e74672ba4a88cf01e2	0	0
7	410	\\x2a1372f7b21369aa4452946a2d02c151b819d40aed90469e0d99e85c0027e19c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000933410987f168e34a0f863697c48d526a9b8dfc84a739dd772427986558528569905fcf51d91d1b0f53af3eef929b8166a9e4e0f5fe79d68ee78dbadf17b966552f75f5ff3b0624a9496eb30f506dd8bf196c8923e34cea543bcda722e1dc1c356158a4534cb27f9c2af2c8cee5818ad45eaa985582d150e029e30e1870520e6	0	0
8	410	\\x2f6a401ce8b4dc2a45c02a425a034b9050127522439d3c04bbbb28c17d95084c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000001a7dffa69451f0be6a6b47921a8cd79973f7f5870c0efc25c918c6a5193cdcca92d59db2f2d7e5bb1f5645cbc016bbcbdeca37f5379a03ae4b083e9a4d0ac9cf18c8865e7c5db35de6af30ab5aae22b261d2023c2b41b26587de73b38ae10880f0625d03cb533203b52194eaa2908e6e1b4c557e6460d1687356407bc2d8e775	0	0
9	410	\\xa39185764deb5acb1eb3767b5becaf45e5e96a307941557daaebfde6deb220f4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004914a04f723389e210f56368625aac1ac880535efabe375ece6441bac56dd420b1232483a0913328366348c40d1248b8b17bc3733928d1a6d5ce30265a1a26efdd940a887ef21385d2109af70cb86556deff8b660ffd9be15b5d79a7d134703c98831d1657ac94bd59429fc639293a797aac3bc79932e34d10a71e47b6c790b1	0	0
10	410	\\xc19e2d221fbc6fee2eb0a1c05550b58d189954cdabf3349be2085e0320cb13d5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000ba2e2b0b2d454ed05b1f05056eeb2c287169d81591ee9818973ab2cf03203f17945480394b12442eb5555d9beb8479154e0070e874f44f5a087bc6e61d09e3c2ec96189b15a79363cc95c7ade943698b7be2d726794a83131c7d626b4c4f84d8f3d9432926f279681362b8e8151f57ab67bbc7f9f93b537699b30c085b9b658b	0	0
11	410	\\xd2fb5f59bc391a4a15b505b9b37d9eab1d29c6dc79af9a4108b7f8472148d3eb	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000067e00d043d356601b1678c19a9daca7f092e8968d01dce3f5a4769e635552e63441f0395dfc6cb6bb4bf90da41c230d7f0c7915aa5dd14179a105b1045e6bb58435014c90502038fabbcb98e0c239b266e41bb2036a84b34997856d33346d803dc32e60f839b5604d07560d1b7c60a01569c3cc36d44bcb56ae0ddaa80cf7438	0	0
3	36	\\x325813d2bfb8e6f3507c4ecfc7fc9c36ecae60ffbd02bc92525dd1ff6dbbbf91	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009ae96037824c3678526d0abc3f98dc858fe4039503b7ec1e27b7fd5b7850888e23878378abe5987db710e755a2343859ad07766c5a039cff344ae1f52e3c0dd21ffcd9efd8e3f1cea7e1e8ec17565fe7ec94d1151135e33cc7247e8c7c692ee6f78d33fb0372b091da0a7b608b3700966018b1abc26ea9101a99972663409dcc	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x3ff13d611d30a9d550135f664ae2a048d9a9e0cd1342587cb20c66cf0b2d3943afdd614cb8752f4cf64f6a12644c8ac841a3d471653affecc27adc9a7045a62e	\\xb10d0ac3c619e20dab55c23d1541ef7c	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.163-00W76Z9CKJWKW	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635353036363939397d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353036363939397d2c2270726f6475637473223a5b5d2c22685f77697265223a22375a524b5452385836324d58414d304b42584b344e524e30393343544b52364432443135475a354a31484b4359325344373531545a514231394a573741425443595337504d344b34394a354347474433544852504145515a584b31374e51345445313254434247222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136332d30305737365a39434b4a574b57222c2274696d657374616d70223a7b22745f73223a313635353036363039392c22745f6d73223a313635353036363039393030307d2c227061795f646561646c696e65223a7b22745f73223a313635353036393639392c22745f6d73223a313635353036393639393030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22524a4434473345524157445a5248385734504d4e4b42395837354842334e3141334d464b4d484248344654414144373147413930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22385a4335454a32544b44523030445932575253534a364e483946384639323151364b514a4e464656593838465636385451303847222c226e6f6e6365223a22514a345138344b434d37534e58384635564a324136434854355a43335039524a425447473033355a514b4d5247354a3538533330227d	\\x192e97d4743b593f2f1292a4009bcf40925b2f577a369ea44db5f76c6740c16e24902f0944a7bf5a9e1cd8f9810072c22dd3a4356d3b243e46ca90282cd684b1	1655066099000000	1655069699000000	1655066999000000	t	f	taler://fulfillment-success/thank+you		\\x2de0c6ab801a998103b6663c977ea8b8
2	1	2022.163-0103HJ4M3WE68	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635353036373033317d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353036373033317d2c2270726f6475637473223a5b5d2c22685f77697265223a22375a524b5452385836324d58414d304b42584b344e524e30393343544b52364432443135475a354a31484b4359325344373531545a514231394a573741425443595337504d344b34394a354347474433544852504145515a584b31374e51345445313254434247222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136332d30313033484a344d3357453638222c2274696d657374616d70223a7b22745f73223a313635353036363133312c22745f6d73223a313635353036363133313030307d2c227061795f646561646c696e65223a7b22745f73223a313635353036393733312c22745f6d73223a313635353036393733313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22524a4434473345524157445a5248385734504d4e4b42395837354842334e3141334d464b4d484248344654414144373147413930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22385a4335454a32544b44523030445932575253534a364e483946384639323151364b514a4e464656593838465636385451303847222c226e6f6e6365223a225a333457544a365a3556585430584e304353424d434b4e3935434d4d4d4135384b53314a43573254483759304254323444364230227d	\\x1004a7fc06dea41ef71f47592ff498724de8190083a1d7b6309b30af31623a9199440fcd4c7bbd728befa004758360c988c8613d16f1d779210e5d7a0ea49df9	1655066131000000	1655069731000000	1655067031000000	t	f	taler://fulfillment-success/thank+you		\\x7bf169da80fb449b0d30eebc332c5dec
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
1	1	1655066102000000	\\x19ebf2d603b80a6de27ca7b068239cb2d1f3aa0dd70b536e6f4ac5e17096b1e5	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	1	\\xfd30207a694a28ccd6f958a03b434d9bac72d0de3cf48631b3dcfdc7a0d6cdfdc5a57f5e5eda1b5d45d65ebcc2784cf0a30e6726d05380e47052d75ca48ff104	1
2	2	1655670935000000	\\x00b749ffac015eb1f0e1ba19fa403156bb262c098209202f161db01c05e9c9b7	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x31ac26512a0f068a7bbe5b8238742e15253a767d72938badfeec7f65fc56c0051d6d6d8075b5b690bb41bcb9d72d923e80a2cd57dd335f572167d80b155c0900	1
3	2	1655670935000000	\\x037afa253679c663bd04f7bd1d0cd38569e28954bcd5f57fa6ce100db655b182	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x4bc8d33c21dafa5c2b73e1d4b9c9a81530bd74b266cef7f65d404de1e242015a29899eb9be9eaeed5b70d15d30d0d0823318a939680c487126a3fe7af625cd06	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	\\x21f6ed33827b0d34297757aa43b6372e5662863b18c6cc41021c5b4bf463b640	1655066071000000	1662323671000000	1664742871000000	\\x193ba040f32eed4366be0f75a69da2a66fb4d13a0b83b6f4c121b33fc61698a90b5f0e3a3a97e0f21cc614a7f06a2c613a7990c3cb69dd7823fc70034154450d
2	\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	\\x814e98f4e464b9bc018129534fc6d7e703207ad62402ba4c518cee2bf28c19c6	1669580671000000	1676838271000000	1679257471000000	\\x8f29dd31216d8d1bde0cd963271ef4aa4f977ccd49613437c907aebfb64943bb77fbea97d553a722d504892531406fce5a7443b59f9184053564e7af62ede301
3	\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	\\x23eff2e805018280e53ae04305e19d407688a68da098a6c077b1315bbba78b1e	1684095271000000	1691352871000000	1693772071000000	\\xf59f69ffbea987cefde2755da442c8114ff9d3250d371284f03910bcf40b8a81a1d6bddfd72fd3cbd97e31baa31d750b50ed47e78fbdfe27a61edca35c273903
4	\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	\\xb05cbb8344d9a10f08fa10026dee54364fe3d32296c5524f01c90f8bb7c58919	1662323371000000	1669580971000000	1672000171000000	\\x5047f494c403095ff0f51a801761a7722d1c92a771c5e7dbaf7d1d5f2af0f4f7fcdd17a641bf71687bad841fdd98206d01634c50727a2427593b4f7b20a1d20f
5	\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	\\x17b11c4379f0a4695f99ffdbe30d2f0bc23beb3338c2d04766df62c4c5858a18	1676837971000000	1684095571000000	1686514771000000	\\x676571787025a741bf85e9f24ebd577e62e53c9cb22484453b96a434efaf0dfb455fce3bede808902c4fcef47f55a5d256850e2552f026b2aa19a9bc74492803
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xc49a480dd8571bfc451c25a959ad3d3962b1d42a1d1f3a457123f4a534e18292	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x7d69fa6dfe7be1a84ae35e5d6b3cae9d69ae63a6ab47d843e78592b780f5221f047c0dfbea4add6fc6590a1992a3f16cf324bbd931b60858b4934b0e90896f0e
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x47d857485a9b700037c2e633991ab14bd0f4883734ef2abdfbf210fd991ab811	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x7edb47b8a1499bd9996b772edbfd761148fe20ff6537cd78a1152591cfeba61c	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1655066102000000	f	\N	\N	2	1	http://localhost:8081/
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
2	\\xeada365013ad84023e09c7e0bcbc428f0a18cec7d82801c2ba402dca21346636
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\xeada365013ad84023e09c7e0bcbc428f0a18cec7d82801c2ba402dca21346636	\\x933e5c928ef7c7fd2b4c4d276894c3b1446d28b633f558ee7afe7c5e7c611bdfba87e06e9a633b5df40ecbc750f61699335b00b1ec79f76e89f3c0c396e44608	\\xd9139296e686251487a031029e835dbe7bb1a73ad591d98bdfa7ae68d8ac5ce9	2	0	1655066097000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x0b3813af89801ebcdb199affc986799c8e6342fa61b8fb46b4e828fa0bda266b	4	\\xece4626b374ba2fb56a38c2b41d85af6e842aaead463c72ecb579103e09cf7dbe6a5ef2ed2b2e70475e3bf7b795fb5215a49736ea8b118d2c49b1f7dcad6e007	\\x759cd6eff11f06b67b4fad18a26d3fcf7a6cbc94bb8818a08dbdaf528ff06d96	0	10000000	1655670921000000	5
2	\\x0d6e1fb3d79268d88d6f822373e560f9bec1059a1c033723abbe8a76fcb92528	5	\\x0d80615a090318eb74c64d6b449b41552a1b83d6fdfc81986a6eb50481fe946fefd371837f06da7d89aaf726e9d70f44c8b7db70d6be758b0a3699240b821f02	\\x45418be6fad2469c7527359d0f99531f7de5d7d8daca96423907e32a78d50348	0	10000000	1655670921000000	8
3	\\x4a81f66736752eee46fd5e61756e5d1c54f2dad69f8d4e8448f441b8e0082f80	6	\\xb67a4ee6cbbdc58330bdf3f94c4a4015b8159f475e57be4610ccdde02a9f5323898690811d8dd53012e92198eff7b51140aec4a2c06dd1309bded9320884c50d	\\xb26571cdb76e0ec3b5be04975a65af2d6a59405caff094ffb851a75207b80849	0	10000000	1655670921000000	2
4	\\x2a1372f7b21369aa4452946a2d02c151b819d40aed90469e0d99e85c0027e19c	7	\\x682211d7aee1881df27c22d40dfbde91db42f4d79b2c74bdee1b21c91f993e0cf2597bd4072c673df166b9b45774415ef2295aecc18f144dfea23bf1d4715907	\\x698c40ab939be1a532df23b3ba8f8d422b42bf4fc542c1b3f85a02877e0a119b	0	10000000	1655670921000000	3
5	\\x2f6a401ce8b4dc2a45c02a425a034b9050127522439d3c04bbbb28c17d95084c	8	\\xf273f740277dc537b9d3345338f084d7db7dee53191e16d20d3ae396326fefa96b72de02aa60c5f415e4989bb84ad27c5000e2a0767d25985b6f27aa9a006406	\\x16aad31446c2360d4fab14f775f215d0e96ba47cf49fb9fc0bbf59e9068c40e6	0	10000000	1655670921000000	9
6	\\xa39185764deb5acb1eb3767b5becaf45e5e96a307941557daaebfde6deb220f4	9	\\x52be295a6e5aea448e67b5623e466165ea0e1d73628c73dee1922588402b3d293080e623b329ceef01483010da706e0892f9122a59eb6d7d04eacb70a377b40e	\\x668faee3cb32e24c5a87003cfdc63715aee94fa29e48e3916e1dfb7caa9e15fd	0	10000000	1655670921000000	7
7	\\xc19e2d221fbc6fee2eb0a1c05550b58d189954cdabf3349be2085e0320cb13d5	10	\\xa2fd91a403d04043f75800addb94cc4f3df6346dd647a732a47226878e1814167a566a2a40c5666a92854642565843f20d7b088db965d528b67fac42fc40eb08	\\x5ac36f4f1264db4dc0ead9b82d9a8e486ef9a01375d19a2f3b36a2202a9ee27c	0	10000000	1655670921000000	6
8	\\xd2fb5f59bc391a4a15b505b9b37d9eab1d29c6dc79af9a4108b7f8472148d3eb	11	\\x4aee2c1b08a4037299258b049f7ba1949dc3a16eed86b5fe2539b8542da5cde5b72904758bdbe64fb5b2ab05bd715e87911d874692c01c5b58809327a3428709	\\xc9b3c06e0d09158159052f12f3cc35d8df77aa3f79e5ed4459cde71678f62be6	0	10000000	1655670921000000	4
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xf99b4ebff3792e9a4a7889c40294d82ce212196d7ab9ca4739d6d7bde899e3524f0325fe45f106d5cd25ebbcb9f191f42b1b636bbcb78b27e5b3062314b8982e	\\x325813d2bfb8e6f3507c4ecfc7fc9c36ecae60ffbd02bc92525dd1ff6dbbbf91	\\xee599276d2afeb8aec2737bb8a6f2ae532e2fd7c25a7416fbec5789e2e924bf6f678fadda27710ee6fb784d6db26ae4d8882227ff5a0d75569bbf5dd9eb43004	5	0	1
2	\\x3adcaacefa683183b3afb0cf25ec66dd33b4d1072425e8b65fbb19cffe8e4b4e1fb3982e2c8fb18930ca9a4b5343a214acd503d82b1f0250e923460fc27f81c1	\\x325813d2bfb8e6f3507c4ecfc7fc9c36ecae60ffbd02bc92525dd1ff6dbbbf91	\\x330a4afc6b8c621e8f1ff9d47da2863c10c31e3325e46c170a63caba35be0ce0b5a1a497a238898d82d37b77725e62c610d475fb3099d5f7faf93c0254271f05	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x7eda8905487ceb48e7c3eca4540bac0edba14d90382068d0668b1dee4fd2302d233508993fd2301a9cf532ab67530ea22344660fad94d9908391eae74229db05	100	\\x00000001000001004ca403ca86a43895003edaaad32a418de221d24a55301deac3fe6297b251e1603a8de8b2437b14dc96226f12921855fd0d7ee0b61320fb9605a294fdf4c7a646f5c25903a9a3f6bee905c564dd1385761bf1a3f46f7d5517d22e44e739b9eb7f06452af74f8d85cd17ebfd379dbb7a2f3950e580d28d620fe54b38eb0dc3242e	\\x9ec989d089d898367b7b1857dd933610e7e4ecc4434fd1df65aff1b8ce5d79b53c5d40bf23565090aeee23fed690937eb26f24ef17d5240f03d761f5db7303c9	\\x00000001000000011570e5f18708a4b423305eabcee06e1d6c49adbc4d01874abaf2e7418dedebed44c892e3a5f71f76b5f733b9bcca8348d04547e2a4439aff5ffb67b2339f0a22809e6ce743adc19451394ca256df2b564c922e7f2024708f2564c4d5c22842a0c34d7d83fc48c8178b5f61bf9c7dcbc38c253418d05da39729515175fd965846	\\x0000000100010000
2	1	1	\\xc8a7ca74694c7cb12768c3399e76257cc555fd2c5f9dca7e70065e6cf2a80335b28af58b0471fda4566f93c66a37ed30854320676284cf05dc825899e007a606	410	\\x000000010000010031b9c5b1717f05e721afef1d5f38fc042288306d822ee858147b73754bcf8fc27a564aac7e859f53e7bd11e71aa247db8d7d8d3a52bb3a79ae275e267f3504f688571a72fa24a13d75638ff1f0b23f4b4715a52472008299be86b9cda9335f915ae818ace4d532a2fa43666678bdd59bbb364c9dbe7b55611f1df064a278c1fa	\\x6419cc0cea596a70dadc9e8bec965de8e990b43d3be0517f5478ad181960dac249092ecf349527b8e10fb2ec2a7aa96079eecc4e7bd292ae826e3253436e6814	\\x0000000100000001087c200696d2a5eed26abc7c6522dd79b2ea159d738107e4685ada1aaab6ebf4362144da50f09d6874aa166795f5f2c5997422075745091efff0fe8e0f94d44d57dd4416a36fe666176519ef842f4c9ce5c933f73edde43822f5a9ddc388060e442561f43aa0d4d151b13149f50a9899095b9443ffccfdd64d63766a95b901ff	\\x0000000100010000
3	1	2	\\xb9fd66ee9d28346e21cebcf88f36adb65c5b25f8322252419ca5bc7f3c2b46f720092453578c5bb992a9babb968796999c36f2c86a7f1f54c512d821bd5a8c0c	410	\\x000000010000010052c2cf846b8e6ce924fe1e72642c63bafa20b2e682703526dfadec5cbb8d9feae31d0a12eefab4f0a37aca8d7b7cf8acc3005f00c72c7c9e983da68899be4b627da2df2079729ba3c3d50cbef84137de9e7e510f07f48b4ff7b0d29d7600d7c1d97735e6a07eeb50a21062aaf72c59599525848107aba7c8b9f4075085d1ab89	\\x36114dcc7aa7797d38fa0c7bbf35ea8dc08cb074cc0790cae943fc746d5e886af29ce6156f28814fd8bc4ca4912be77f72c2f5300b1da054bb721b0ed945a0f5	\\x0000000100000001a5a8bbf55d6bee7e24dc0c5d4819f142723ebcec08080050755ba87d1c07d5fd18cd4ca2df5bf06cc0a175bb2a6850e2598d9e54ad2d89c3a38b5a20b83b85dfb30e5690d2ab060dd7b7d3c83cbe805300df86b1f344bf447df21061b96fedf8bec42657468100ac6d12be703af9284b426d4901981d40a069f99dbcf4cea9fe	\\x0000000100010000
4	1	3	\\xa610b7b93bdbebe60d4639a2a84d1bc620291d045d6d201c70fc13db2e6763b1287565b155d712e61584187160e3b114152d24d8b6bc52c1414be1d233f7e40f	410	\\x00000001000001003716ca0d60ebf8494a30177409f7a21a968357fb24bfa8677c389ae0641bc303dc08b1a626e6f2d500d56b8476d5bf204e48ca75914dbef32a496fd0fc8e9feff0f96d7922aba0b652cd277808089cebaa443faa72727953c954f305612bfd0179a6dc765f5dda7bc4f8870b4be258d94e44c616fec4a897f3bc02c0da477879	\\x3d90fe48ca84068a770dc994d0eef751dc099233938f8de01283a13633cc10afa01f083773bb7ff541205344ac808f88d96d32f90431d47ddeac9946533ce63d	\\x00000001000000016b45273b32dc61e19df5c05ade150657ed06fe15c71ba05ae5295672b1cbd5e8d13b2873f35ab2630b638ce51bcaa8e640a844250840d3b272068009cb56f9e0c085555f9742882483e4d61a343a44e5ea37cab2e32afa8c05ced84a6b11894117f04d33d26918326fe3ff75036b7cad9deab1de83dd08dc1172855acb8b6cbb	\\x0000000100010000
5	1	4	\\x834d0ae83413546d70ef7a5b5e1df22c3d08b394bd7d16cd526961dca9c24a56f0817afd64985a48cbd6da21c91c98a0fbf1b39a95f98c6a939a1b091a65e203	410	\\x0000000100000100a9f1df411716a6156d0ff24670af723d26dfd7d18db5258416578a8b73eeeba2ce5141cf90d6cafb9f29a63020996c95e13cedbdfd9a3297999843abb7c31059cde587e6673a4ed4eddddcbab1a573d4782216bb78ce9c2d357cc880a722ee250995242132747038a19fe5f0ff41a14642a69b4cf93ebe5fbed7f5ea16c66f89	\\x67c5204a20dfab76cfd54914e5ef6ee3fbd347a2c2394e728409b05699c5c4d9be2e25e2da9185368a2df4b083be2f8e3a1f984e4ee2b5667953827105a13d56	\\x00000001000000013450e79ba848033e97aff9cc583325a911157fdfbbd5c616869ac0ab93a1215defff1212e480df7fb00dec43b2b9a82ab3261a2bd1effc7c949b2952d5be1ea474994073ec5cafa6b48f2a6f21286b833e45658e7fcb8c68fe01f2f36856e4e3d585c7b4edcf5f582a7127e1ee91b9d13fb16cec252b816f23f8aaa3e473ff18	\\x0000000100010000
6	1	5	\\xff8b819fb9cc6b69676e8caa942e88be4e68443048b3ea74471e6cedfc24440d4e2c0547b7a9932d413c4326e782c3a1487a836c18f4789b0b60fbc3b1adcb0e	410	\\x000000010000010051b7fd4de1aac0faa5c7ba0cea749c6e379b324877c247c4d715352ad578ef1d6df7e84f13f0f53279630e571b1df67e2cb74c87ffd7adea047f5bcbb7e68b6aa669a787f2983eed035a82bf4fc255e024a55fb8ab42e3e52414113916ee8bcbb18ad9ef2ec5c09209e152b3a6ac68754ae3076d091a833136f3aec996de4956	\\x2d8dd890283c702c3502fa286c43fe67cb273b6ba8357226961d5ad39af66a45864a885f41ffc593ecdb27dda7697704fbb3b37545df34aeeb560845172cc096	\\x0000000100000001901bbcd1a2023d5bdefd4b4e43773e35bc78d3ae51bf4d774eb59ea692c9f8d7fb9bec9d3d11ff187112ab822df21465463555380014fa42be408d2d516d9953f454e9a7c0b6b4d4e677604d5851b2182f20d05cc9f7e4e4106f458584e3356389b26ea72c2eba2c16e50b6b1b5957db8c34b4cbc4e1b2b5e23486cbc5b99697	\\x0000000100010000
7	1	6	\\xc4d676519d47de781f8d9931601d0cb53369e12fd5c7a28c7a1ed1ecf2d41e2cc231b91ebd5a0e193a9dca499cdfc9c5a5d15aedc5033a1eb09f68632c3a3407	410	\\x0000000100000100bc15250bc592c10f3b04d62de172c8567d8cce0b4d8a6bd54d4017a062edc6b5089eadaed61d4115a1007c10c4e18b42d515e5706062db588b7552be5cc998b302ff1cff6f0ea9fa8cfdee8269cec80caf0daee14ae112b57222e51321521103c22f6e1a9bcad18b6271db80ebf278e8bc301665daa66f61eafac3becf6de781	\\x36f3ef487bb1cc316c7c46827b81f2e21c70d14cb707d93cb40be35b113f376face407e077e5288d027be2df34f2c84465ce2babb52c2952ab1e381f6a64a430	\\x00000001000000014f5d091ae341efb5631552d3a3df0af61ace666014136999726399dc5948ea9062eedba0c233e535c8fd636acc763058dc7957e1297ada20b63b292fca6a4f918687690b8c124971bd4d9bcd2f48b4a3dfc5097130f069e9199dc848f84482577685bd29bc236dd3f606a7a56a23b8db63bddb55fb7b9e8fc25d1a89d4f0445c	\\x0000000100010000
8	1	7	\\xf495e0466fbef519f67254534f3018d83bb0bf7087efe9899ab87096af9e9a5b51ebe576990b9d013f9ddf99f702b992b183a147c6447b46ef78d2abd821f90d	410	\\x0000000100000100482e220b8fa62a849e4238d569d46bfbdd544ef57ddf35ba97cb9ceaaf504716be170e3570deaf4c581b3567ac79b580202f88bfdb882d810284fa406d3dfce14ae6e6b71333d009a5395f063d83d22f2bea22a36c0a364e5f0c26d676e9dd8404d3179d8fcbd532e7857c11c6079c88fb38236f7b494a492fbf7f3955b58572	\\x18aa45b710af4138b261c17e2884986d93a8e3ce4aa6172ca01c311f2b8fbb84bdf6115c232222c0ac6968642e892af9c8d90ff3c26bf55630e4fc6959aff262	\\x0000000100000001282a3c98b6874c902c4ee28b85128f05cb1956d2acdc6b37c7ad7e7cfb38fc5b59e5a4e4b4edb7ef4646eeac01bb6879d696f33cb38536b4df91907562ec585511bef4e7f1c0a91c43454414885e4805dc2f8c0863de9583895a88ddf916b9d9e2bf849b7de6ebcadd15c0984f18b9a8c27344fd9e24b7025fe16d79d1bb3a1e	\\x0000000100010000
9	1	8	\\xab0552034b0ce7ff549b84f0bd3a37c0b16c1bdfe18c5f9423a017ba7a71e6f0bcce3ab58c1283644d198bf66d6985b99e23219ce91912369bdc7cdf48b3c106	410	\\x00000001000001004739a6b02c1c441fa99bae79ea044cd09dff0a5901b0f84978c0df905668536172690ce3fc71713333681ae9d71cc8d7777138c7ac2a7fb2685c960b7a7a68835ff3a129958a42f4262dc048b9e1014bc598343002360ecf3748e7be73f7aa6c2257fa3cc3cdd24237a83ee69879bff823550f6c4d4f441d8a075ce5cb558bc5	\\x3ad11e56391fd93a5ab0fffd9a86b3ef26765695ff55eb665c923cf3836a307f880ac1f08282b258879a1e47ba17e8112956917504d292c5a3c1c65ce7cf085b	\\x00000001000000015939057827d66f993b5b76c520a219b4ea25acea004aec18f57439adbf9f78ee6de12922de7f8ac0b07d2c33a1f7e86081a261163be055ebbe274511b51ff7c7734c4797ac1e1d7f525d3f3467c161826941018afb4aa18457abf04c8cd58f3efcf01cbb8b40ac1da9a382cdb8fc7a1c7854333ce86225300c441e49d1a909c4	\\x0000000100010000
10	1	9	\\x2ab16ee374ca647fc84063c1107b3d8f3d7c947ce99303f8d9677a8c28ef5b93c40adbed9a6be6320a06f4d066389d6f201f76bda1264f980ef6f739618c270a	326	\\x000000010000010080fbd5ec7bcd78c5861b3bb842348acb32eb00bf9e1f03db315982ad2f3ec75b902ee159cbd15bf90f9da93fdb761ffa063c7a1d232dccc76544791d2d91dff3e615ac961f2669499c636f54ca56371c53a0429b0196d2a2c3b593fce98de1fb38ab1ca550cf1ad77e7bc49639b32b49d5722571b4b052f8913595633e4c4ce9	\\xf9a525b44e9e27e1b403a89fe11d8beeac1e11d3f0cba6abec87e518db83a51eac303f1570b674a071a7f6ade5dd6f9b16dc21921479732c8ca8580bbe768486	\\x00000001000000017f6c58107ecf13e2ef8ec174094c45a4d0ddeb04f75d23b01c661d66281ba36adda6ad062a180be7306247902e98613895ca6a3bd1f3b336c4b9db98a55cd4bd9c34f48bf9bc0714e8d3829bced662d986359154e0ed74798320951d07d140dda4ca95b4504ca71325cb1c5c20d1f8b64b2c4d1382b6f916404d7c32cc01a0e7	\\x0000000100010000
11	1	10	\\xf63c6f01c0fbbf21e79412647a2ce8af19bf684be57df6b3c27f284b56d5c0f53c7818a20b3aee5a9c078863dc9e24236a2537b4f4d3e1e0742a0e47ff392c07	326	\\x00000001000001004f7ad1afbca2c6e96cf067af143b6a0a98bad7c86dcfc32096a56608192e72591606a95884c549b3fe0c6b3d7662635be2665063dd15706cfb4d0f2ef8b7e71ef12be29660eaad1fc1f6f76798c34192f072bd9e5cb0e079a5d5a9eb133ad95e51a1d28048a52e31969c33b2aae5c900eeb933eef8d6787fbed2b67424cce10b	\\x21be3be24c39df96bb4f52eeef350b579831da7107dff04e481e64701348c3e1e654088c94c8a396dd236e4aad66cfd320eac5c03b52ed9b47b12b6fa5fa5865	\\x00000001000000011d97e6950b1fe326583e74b35abc3bbd2a59834dc6c7c0d12e97178b15a34e68ca74c5d7ac534245bab1ee40a115f6f086718282341be75b77f3b3d598ecd1c19bf7e899d624a7022d27aa135af43b6a41f423965b6a093bfc6246efc85de4b3f3ee88ebd876bd99e04f4a5580a7634783753c76bb1749010af6b2f226fccf89	\\x0000000100010000
12	1	11	\\x68b1978136e68e99249bd90142b89a7648ba254499a0dfaceb440b6e114c672006b1a05b4128d89f4234b0c6b4b40eaf8c6a331d39f2e69d95da809de81ca307	326	\\x000000010000010092ab23f4b5b6cd734154fd6f6e09796020f8a49b5f527c79fd05c45bd749ab00d00f195d78ed7475b1874a6295a203e4529ac465835d4da4ca4a710de4dfca1dd78abc425606be209ccc80ac4e6500a95956b1e52c8ea58000137e992e1ed621bf23ed38de38d2d80426ee8c993c625c1aac3d8c0721c900689fc7ca735f8856	\\x2195eef82ccd0a4412df94869589cb2d8864d500f26c111bd2013c1e91e9e627af2acda98203608958fabbd519001919b8c745e165fcebafa392e59f86f2f4b8	\\x0000000100000001717f8463cfaed1fc8541d5d95866bce91a5a050244399119a07b2886c358c9e28e9fb853159798979ee60e7e6d1461a0edb6428a6134cb1ac7a1df2f09363cd6d75565ff506d6818ed14a50b20494417c31e346d73394706fb438eccf76758ece6e4b58407a429514713e5b0547cb2157a5187a99a3bb10eb5cf0c5781b8eafa	\\x0000000100010000
13	2	0	\\x1433024a6206fabbd9b2a7761e96e08b0d23677ba3d406fc520d3543344bffcefb47b4d70f028e3b0052bf3e2514d9529d30d1f6cb5db345a464220004a01004	326	\\x00000001000001004b1622ad56ec52cb2b634b14d0486fc0c3ab2d815933312a2071d8c3bf03d04c6bb8502e54b042e4cf4ba082cbfbd597ffa3ee0900e1ed1e1b20e6d03c68d3e530ed93923fef680059a797df020c582e203287e3c211f6708adf0f9790cb3261dacdf5ac0eff6ec7cda92a2768935db0e9a174b4ec9563f5b3283db125fb98a5	\\xfd437aef26baab344527a9e0e0c69c8d1be7e68c3eccbe0d7bd04085299b3e782bea2044e5b3de8762a63406bf46de1fcb6f848c081bcc960d986e31be98f1a2	\\x000000010000000165145a1e1d7ad428ac092db58c34b3f1bc414e551e92c5eb9dc4814c1da9ebe50d872909435d7a09f87d49cb3383203bccef42b91107a33f256bd44e09a20c2930856a7c50c8fdebed1eaced8f3d81e80aeec9567e7bd622c137c779fde143fc047d06b6024af7194b6fbfe43ddb815d4f899febbd103c29ee4f7fc9a730d8eb	\\x0000000100010000
14	2	1	\\x26c75ef72aee80a428bed6a405d0bf164c52b4078ea21910132dc3172ec388562c4ab5549fca7de1cd1b821e580122dbe321cdc02215114b80ca384b74326d0e	326	\\x00000001000001007b453c4101d5472912a26693557ec1f0715a81e3d5f45aed7352078f473084e7384c768cd52a646a41f21af0f9737eb1deadc186b54022a4ade5c93410e8bf74c59607fa03e6f414d6e9a9db6116d67664cf341ad90c72f07771eeeb9b7814822c8215b832cfcfe8c7449c340eefca210cd054ad4b91b130983ab758119ffc8a	\\xeb620252941f0c2ffd447bd3b327b3b5be7aba7392bb1593bd77da88491caab2d3cd5e55c35ae3dc273d52950b197c303cabc9d9d61ad195eefff49079d3040d	\\x0000000100000001962b5a1f52e6b783acb72ab4a6f84dc53843b445878c2f9dab9130b0d025850a8ddb7d8ce787db0031c4e4e1c91c56a47b61d5bbca494cce7d4b9d0655224612a44a145e2142d6645636038b8cea13b18212bd8fe3738ba68938e31e6ab2d4cec62d7d7a31c7135c9c8cc7ced56a631daabdc6c7951c5aa6baa78fe9c95021e4	\\x0000000100010000
15	2	2	\\xd2bf3a2cc76da2aea99eeca9caaf11afbd917724210297fbb8b2a6c1f2ecbc832fbf63dc055590e835ac53bba42859ccd6cf33d63eda4e7005efe9fef222d906	326	\\x000000010000010096a4ec0a354288f00bb17c3654eb16c7e683978758802c2169208e9f9f159bc3342803247a87c3cf4343c3d4fae8faf398e500b6fdee11f410b167696e92e8cf5e8b97e12bc5e6897c92695fff576dd86701787d2a6f88577d382220c19402ac2adaa2f53a3cadca0d2b88fc6bc714a14386a30b6f4d91516a9c7833b2654cef	\\xd411e759d5ab4adba4c0f0313f7fa9b056296ba42eb58df55a1c04e2e8121acb5e2d09f773c26cfd16a7ef79120897a83288f434ab228c9ac2890c2373e4786e	\\x0000000100000001901ef9997ad77acf022fd2d9efc96ee995ee382806a283424099b95e416196e4c6a56f5fc9a00568de5c3c572377705db5ad510fdb8ee7264108fde6303068dad800d0e4b4d0fb79f768d912b114c71073bad88f702f49458b136e1abf7eb2a0da0731e832fd153725f5b7976b8b4c7a547713f41011b7dc96b8074c59cbbfe8	\\x0000000100010000
16	2	3	\\xe0ea395a0f615751f00e043fb6fafcb3545d930bcf31b5874ab98504bcf923ccee9aa7a151c6b0cea48178c386959b0bf9912902cba0a7dadec2cab1b34c620f	326	\\x000000010000010077049c134dbf03764957d5a13165a2432465ce17452e91b3b3e1e6e6402e8ca873bfac7e559e2bf3aa49fe096cba69b434990d984e536104cc7840c3a9bdc7e78012899cef2f5ffcd050cf122cd04a83cc47d7f5dd8087a3e9c46b675d19f57a737f37e9cf340acda3da6cf9e78db81e46d89a7cc0e9573cf8087b6d74303a37	\\xfbf4351fbc9772465b920eb02990a211d4d80bc58367dda243df823c2bce36c698c1e76a497a6ecdc8e6e6494f28d92f6fb435b59d803ec60aa120dc6ca30a7f	\\x00000001000000017fe885827ac447f99a70a477d59900007a2a812c7ed0d798a66849fb22b59e4d24cb16561f3cce07179fc657ef9de73011feb0dcfa925a858d3f055b01d5f0dd59864d6c3b4344635b30cd6e30f1e533803e861ccc6cf7e2f9ae5f9d767ad9f430c166990ce9c73c6a68208331c6d6de4ea110ac2a5b187cda2115674b04d1f1	\\x0000000100010000
17	2	4	\\x618e451e11376edf961239b423d4bb9fb5e4ce38f0fbd6d14e68884ecef5015686dbe338c6727c4e84e704cdde45bf6312e511b8894395237db0863413fc8a0a	326	\\x0000000100000100a94f862e7ab57dad4779376247eeb575f40a593c8b13ec20b1b3f4bd4bbcc8386f9553e35db47bf760b73c6c5c175c72f4b07c8511eb9e741c39027f98cabe6c08b85eafb4acb2acbeb780fcb4e158ef9f4b791e53207431cc334ce6781da77e3a67b50edb2bcf800aed75650a75c930c332aec7d79adbe6fbaa8b9218af3c37	\\xb9d736f9c8ff918545a1d1bf8a07d4e64ffa59d330b8f2c8450a6bbb8d053e30b328698b07d7575f385c85ad77d5f9990d74ff62632cc432ac17e3c89124bf57	\\x000000010000000190bfa39cffad15464839d81973a173d567ebb1232ea0af0a48d6eb65662f86ec788c7f656afed8d320ffb9a50697c114c3e6f5e37de234f2ae8a7d64490b5d31ce8daab1be6b3c09ecf80974cf4f79433512f4120c8d49049ccd7a12eb52071ef6412c920916517b4802c46452b18117939ccd220cd8ecc3f75b254c4f820ee1	\\x0000000100010000
18	2	5	\\xa0949770e2a3d0a0d1fe3c903a540bc2076586c618c2cca788de75db1b58a33b740d78b679565fecdb6cef19ba51cb1b0065ffc79bfe8f89794c046377bb2e01	326	\\x00000001000001000a8693591fabb65ee16cf60d1a4b71bb2f50cb04b1de84e28082001ecc918f3b49ece7dff34b9b44eaaf1765290ea51dbc705ba93cb66bc6e4ec959d72770538ecd5672d49b9e4153c420088d50b7a36d1f345d0b03d8eca0e4373fdb6e25b7f5708d0203dd2cf936bffe92b595437c29e3f4320521055bb546834159bb412e7	\\x82d586789f73c680223ef1a54affb780b2231df21585801656d5da206dce1d300d37014b254f288c578bd0e4a6c46f8e3d4b60fa605f56380eafb5afc02785c0	\\x00000001000000016c30da74dd7c93e44a7778f1c83c715ed860cfb49b1c87193ae106187fd35087ee6f8bbe3ccdfd15c3a0ec75175ef07d382a2e7f6341cf20978bbe1183d95c096319db6eb4281ff892141a80d50767f9df27c5e6513b2c6d764288d851f85e46242ebb2537a7fd362342e9d83778fac681ffc274d4b08e533ad945dc09b5898e	\\x0000000100010000
19	2	6	\\x097d7cdfddbb9c9aeacaa708617aa40c4ab9070bf7c337efc8fc2fe56a08061fb62650fa41ee11df367162415d147c295dc5030c0834f283faf2a21403826b00	326	\\x00000001000001008d9df069c174b37ee77a1ffb5c78d129a88da7e7e18dba83af24cd06b8c053507078f84774ec985357509eba598c4445b8524879140db14f3fca56a8a335e4e7d03ac01785c3f48b569654b94b564d98b76d043c5535f611482e2d4504316df168964953c8776a35c73a2483e66c181f5086e95094d52905d674ba9ba770823c	\\x29970ba5781b75e1e2ef2e46d7186a748fe44b92d28fe1ede8484094371f85dd5bc94799e95be3e652f251eafe34bc24fe027635270b5ad7d06785a581a1a6cd	\\x0000000100000001202937851d044297712ed5ff90c0307853632dd453492c7d16c2c4f0b35bb5373d2a5020d14c0992aa085b9082d56b08f99a53e45516153d3b9224aae1244dfee21f632a6062205fdc9889071f0c01d2e68aa2f28d808f7dabcd332e1c5ecb16b035c8f02ed1796333f5ab6b8c2a0a967bfcc60c4dd50a93c4fdff25e5f5f080	\\x0000000100010000
20	2	7	\\x639ad60fb577d60a5eeea8c5bdc70c05b14a876e40bdbae5e4b8acbafa4e62e62fec5c3588f173269a7108bb37e9c6a225c22c1b891eb24c38f51b0dd8be0909	326	\\x0000000100000100313a088a3ce8ee5f20db1fbd24e802c0225cf7a6537246b3e948a5403888281cd17f120dc90bda867df855dad24cb1e8aff698ef1730e60311822767800c0e102ff7335569052c09ac9ff30609c763bab4228cfaa073ca93b236cbe0be3486d1335c98c65e7b11b3e5ecaf78c2276f41f136044f745148dc521a95e19199fc01	\\x4e84c0399505ffde561402da4461b3e0ffd3971c0c2be6f7536827f6e162669692c786ba9fd7f6efbcbbac26cc8fb454aa01f3004d2bbe23467d7336e3539cb7	\\x00000001000000019f9ea8fd7eb52e0a42755174ddfd369ba74cedd05a2efb4763839662a80ada1f4cd0b95997ddcae3533ee233e7f4f30fb2a6fc546df49ecc38d78cb89cd27856e75c181efa2842b086a849b10092a4e3bd770b57196e231d913667e30937cfedc28b187c9b19f5e883136640cae82e260837597c54f73794459e79a0a01c553f	\\x0000000100010000
21	2	8	\\x3d002046a6ae39ddd28f77c63844566591195a43ce16403b18c2f4786c3688c9ba886466bf3befd01eadb11daefeba45c4c26d5f03be9dc28479b1866eab1801	326	\\x000000010000010005b1f3a48f92d12f43acf95483a2f76a951de6dd15a80daca758ee2d28dd24e44e35d5b5fe89a72bfa29064f4ca1e42d49e56211bf3a3c2fd074ca30e4807cb4b21821323fbeaf607b19f26cb959419867f4ff7aaa69206d52de7f891d473eed89da19b8f3e941fb3321b331b6f62139c5b6925c44834f2d7685c5b68786ce09	\\x1d7f42fc9637696c5f614ee1cdd9f5a8ba6025e3cde6c1925cefc3876e9289294cc3195677314a7d8942fb4e2a298f08a0b42b58c9526003950761c9f99f20c1	\\x00000001000000013a4972fb6235c614dc5fd3aad01e89e91e02f12cc12620feba76b237171a5c8bb06d226c9270e1a3fc656a590f2be8bbd6658bf7ab31cd11eb2967333268e2acb669c3eb55a23e6dce8abfafecaab52241be54a88fc0690660f7f6f7fae354f20330b71e1380494aad730a0ef6de489349c8b6ebe75ba133839507f1ab64d97d	\\x0000000100010000
22	2	9	\\x40f42e3cb201b79ccea58cba831ce4503bbf877d7f6cfe83ab7cce0f12f32781a1355cfb4ab4d17e7d6b7f7508df66fb0e584a2d9df28b2ae7d289610af2fe0e	326	\\x000000010000010099e56e4748b2a19809fc5c224ce265963b7f70a315a8d88fd0bd7915663cb0b171509e0a378477fcb6079c27cc11487a31dd88ac7266aba7d27f93f06c3dacdc921132b51eae45d9336854204f4098c546d186e3932e42d9428ce2ce443c9ecb2974fd46d69450aba0fffdb6354be5343ca0d95a4fff5ceff0a96a078e7277d4	\\xa3e4c72a9161f45bad44ec27b13192b518cc9bd13025a07cf6c1de1f12c738db466a6f1f743f049de577b6b065fde21a5ea2750525b824d3cdec6813d32bbe3d	\\x00000001000000016b493acd0fb822fb5ac8fb488d93706bdbcbadbc4976b50a8159b394436af79dc47bd2fc6b0e039c94ccdfe0642ed3c1fcb89b738e188771b89b495c991f27b20e6ba54980d8c83a50bd16f3b5bc9086f9c35edd673ede9b4d8a582e2bdcb8e7f9621112f48be2d7af8d6b502b3f142d413e6e0a93a6cbb38eaf3f794d03efca	\\x0000000100010000
23	2	10	\\xbc71a24b0d54dfc160bb6724d47da43731e77a9314c47f973d63c081145a3f35bd62debafd7c9948092a5028ba951976fc66961b327687249d9496df7d177f0f	326	\\x000000010000010011640345fc98a70b043c91e90ac8ff308e907c9774cfa6fbd5d132818b406f5b425d4e3805ef628af81f847735fa458cc3d20cff7d4a139e1c203d5342839b7e80f2c62135cc29f41c546b00eeda3ef728652ee964fae2577bcbc66d6699633b0733312faa9d52da6c3f61b2f5f627147ce94e1ff3251243dfe0e088f35b3597	\\x5492baccc66099e0898cdaf9eebbd2236145d4bba628a353ca3106bc09b0668bb5bb364f524991288c4762dd6ebd01550b172e0d3a7bdd5f6ff1980d34fe48fb	\\x00000001000000012931870c5a4c0b7819c43d9440b034c206c55a1476d0ccdb2ed56b18b095c80114fe81012ca1154cc73813e3623460912f0a69f43ae33587cf2799c831462c28253576e4919792b6469963d69c0dbeded1494cbcd7ac7cfcb9f37b49a4f1af5d65ed2c616eeb4028aa3677d70e0d9505c5fcd4cf3efa129826d1a4242615eaa7	\\x0000000100010000
24	2	11	\\x56b07ff5678d983494c3c6df40fd6a02b54098e691b57d5ab9f551548c7924f6e5d77212eaf7ba6456f7f8092e631d9fde1100c56ccd3a8c76d49ca58df08808	326	\\x00000001000001002823d07ae5ea573fd7d1d8c7b81fa7b966dc90d9fae98604f2cb2b8a6087efefa7583af81b267efcfc6f84756ab4329b705c3462bcaa096a2a2d9e4695b427d63643d796a1126329a348f8d9925a14922fb3d07e80497e7704c7fbc47bd54d58154c98c96c6826b15a88adccab68cc6deaf30dced22e6b8d717da60274a97037	\\xfe957f3b9f9d4810aa096f2c9ae52d87f2731bdf440af9f8ebc976b94961802eb12a690049e021c75f7a716e064469ed677bc7e797e8cc9efcf284dd990d108f	\\x00000001000000016a68d83e893ab9d6279c5a0ed513eefa2db832249b5404d45f87e5e030298cb8689a46fb55499d7643dd373e93cdd64d650d43ce1675aafe331de353460df2aff7cbf4a7e553a59c3d739448026360c9ea73788de7b0f9d6d858e119108dc857e7aef8710e39df954568294ad4e20eb23f3f85b28b42a899f3f13de9514970a0	\\x0000000100010000
25	2	12	\\xa81f0e3b41bcf7965ec27cad40ef52b0a97c5f0f972b13b143eb4e82f72742dd0d4fd58c3fe62005d45839d6134ecfceb22f05190005d51e6294186a0ca59203	326	\\x0000000100000100a333bae90e8e91194f95ae7336c5b102057728e58d79079a79e69bd07cc81f434790c981bb05cf330d45bf871f1f9bce87af279ac7e41b88497ddec59127efd6a9bf7fa07f837babcb8b821a9df494f43f590fbff527e45a11cd37044ca1dbfe59a7ab6dff90c05b92bd833c5950a24d1a6eff2b0a73be094dd4ee26ee450b7e	\\x51305695c934654aad71d002221179e8f7e834913be64c2b21326cb4870d43c0238ac69bb425a4e73ac6ec1b754a60b314bee4a7e8a41cb3ec84df75c190dff9	\\x000000010000000179da711439d4059c450bcf776f972348fafe17f5c7d8bf143f13909cac37848ce154620305989034f76e9cd6a43ffaacc46546eb7f0e1c56f74ebea00e507a229f277ebd996e50332d7ab293161242f9f1cc411cf9ace3555085db57e4ff996f82a7f1b5e8ca1c20e01361dbb6b1e530962d3c62a1157b6ea179384030d185e8	\\x0000000100010000
26	2	13	\\xd6860e877fc4e9dbced6837c2d07d0dd34753952ae6faf1930c5577128f69b974718a93bdf4b233bc3bbd8bdca6d608e994fdedb1f1f83f0a0270f3b78ee4e04	326	\\x0000000100000100bf2a48672730a846aa64b7ed2a6650d3ab48499981d4c859c10b995579572311bc46a4f047c1fffeb8d3675e3283741a55263b05364fa0b89eb4e429054f1b1b4b121334a658d8f91376ecf9e2c1b9b0dd9ec107e4bfb22ad12c57a1746096d1ad2941115598a9ef41142f3d8086c65a6bfaca8b85964cb7a2f99511ba59dec1	\\xdc0301f475c137fff232e512e9cb72f7676d7b239c6942ceb80353857ff638e34967cb3a0ef9c4b9783be5e47c3d1d6b5719d026c57b96fc2d1c8427cca20031	\\x0000000100000001608a0e26466408ccabf1fa8698fb5303dda6f2a8b425a32c8f33cd472e111d1e2e83bb4d7b2fdda20f08ed0d1990f65ce21e620b02796c779173505d98e0f508fb36e8668cbd9a3d7498cbfa5149c72e89daa0654be9206fd99e1e6e2dafce979b23a3c8966844c0e805ec806baea8ad309bf54dbfac26ce689a221df816f174	\\x0000000100010000
27	2	14	\\xb83aab3aaf501b2357116c023ea07a7ade4eedf72bf818571c0e4092f14ea7211866c07fb0ef051b8b16a6264981f3c252a45fc71b7bf9414fd459a6de6b200f	326	\\x00000001000001005b97b9eb5b5ef2e283967ed6f649883f870d0eb7f8a3b254d308ba27158ae48662df958bc8d84903e3cd3f2e862e5b707b0c67508ef441643708893d33102d04e9572e0e948a72ebdcff89e760a867c96ffc535432f5897f73a25b39b01f894b61bab1e939faa16a68fd7f7acace1d01df726d56a39b3c5f677b325756d830fd	\\x0f276e7f703b82910fe0b973c1d5dcb3dea13bd6764049028e5adbac8f214505a0f67783de5ba0b56e8e47d3a9dd9c10a07a7417884a8e4a39efaf54d38877db	\\x00000001000000011780c47a5211c66a5945bb83d16082f8fc1cd2b2a11a7e0e56505ed12557a46667fc6a2a22751b2d0be6dd780b0c6fc0f1b90541dcfa4a7d1ce9737ddd5377fcc6f886e1eccc01e84bca9ddbbec02088209c2d7aa4ea51e5c5e296e45ecc26197ee3c0a2cc9483f486da6f7dd6fb09b4021683b3a300f2a6c91b9d30d8bb06be	\\x0000000100010000
28	2	15	\\x86140d35ca327630662c57dc19294751921e092a7a36678c36107fb40fcf938b77ba8a9d491e81e24435924e493928e37a03b4459f7095ecb8c4ed18bfd32a0a	326	\\x0000000100000100a271827dc9c673fa06b63794a7c516eb74d8ae16de6d3adfe7a678ad7a5250248d288d448baeb2d7ab39912307b64aca3328883acabf4fbbea32bcae0b8047cc83f5b536506d197a2b9293db4ef8cf4b6d360f78b259e1938b42adcb45b383d02bb618f44ea3fcd8f7b436c9b95ce33122a11c4186ca1aa82644075eeec3a0bc	\\x995c46b1304dd786352a6e2703e986e115846a83813412f04366d5526b1aa4c28195a4ca4b58dc9e70630d9f1038206c5c0aaf240200a3caa60d7ccccc3180e5	\\x0000000100000001130a394a017338456061e47898f7292dc7215b9468c8d4b9d5d27722380d6d98d47f973169d233b1cb6293cfeb1762a52fa1c9c8fac6753ebc24a371cc680d2f25cb19d7bc597a0a56606c4cb2583de6bb02736a0c551209e4d7b71085894037ee8c16fc056577cbf883054d2d8ff8d87550787197a4ef1c689bae653797cd	\\x0000000100010000
29	2	16	\\x82160f79d4e3ca3c14e87a1da04df09376f3e02230f16e0fb8e0e6fbdd2355f1c9f9d1bd128a34d4e6e85119e02d4eed6a8bc74014b26fffbea03e13cac03800	326	\\x0000000100000100a4f950fe49b00eb78718ebbc83a800751d984fae87e40cc6f3413aa1d66f8f3fcec078ccef8e80d2c3103e446c343e306cf15b1e3bb75b92404f2264a2f7366044f86326707416bc6d021387d1ae1659935d116302881f63b2daaf79aa650f7560175a1fe88782681823e53c9b79d953888745a81bc833a56c4fe71b8eac8a0a	\\x6561e0a9e51986aa8d12528efee140956ece31971269707a432c9f9787378cba8892cebf042e3839b7c84e846fb9484a7ecac1f2322b95d3006646fab6bb576a	\\x00000001000000012b0d9f3f2e0f8cffda0273b05ed5ad29cb216a5db14642a8d683273c2ad370bc2f69f7812153013049a34173d2f62f0ad2bdf74ad1d6d241a30d6501f33073befafbf219bbe21d46462500971678d5d128d179d853de502ea105abdc5eb23542646715605bdb20f851a9283bc1c4193bbc93c62cbc10b4968367d441b048f7	\\x0000000100010000
30	2	17	\\x226a077801576ef6c1c2ae4c56619986c4f551771735a9dad36380da93036ad4c22948af420b3509c39459263e36892307cacc853b4d7b0270db004fb403a70e	326	\\x0000000100000100b1ca89fd80e7c9133e4d275ab1dceed27819a8cee996810c6101dc7cbd356600eb106dab57544c77f216d499ebcb6952995b0cf182fcf1d741993624176f9c6e45ee34e0b3dcb2bb7e599002d4e6e3074bf86b7d3a67a972b7f814b769724e0d8d065c4ebfe9482e848e1bca0303645a76d33da88167258392231b79c870bdb6	\\x43540c8612b86948460eede818389c078d4fecd3d5aa93137d6bff06e922692138befeb493735f1a4847fe55e7823a65d49e4bba7adbf0686fb77e1a9ef227f2	\\x00000001000000016e0c4d82b2f5781de4419603a77e6fabf830324a95d54c42ca255ec6fef944483c7cc2f25e066f611424ccff24889e0f91cde249de0bf8ab08942d30fd7359b5b00cd6d430a28b560d0d25b3f2e19557543a50b7a41d202ba9ee3b27d87174b55601bb0ac8f08ca09b10e4907a83416dbbf3fda5fdc501b136012b06e1c966bb	\\x0000000100010000
31	2	18	\\xb69e891e6d00f33cdfc8e949eb35b9986446f015a530bbad6facc14ff6631f41f2ed120530a637256debcfcf5ed1b9376115b5f6885433098a5e5105f633c306	326	\\x0000000100000100c667bd4ec08b2570b1425f67cd216d3bf8f1940d8ec81de1e72ba54e0e8fed9a084c8734295ece127e4fd0106db3f785122b8f1a4784c2d5c59e0232978dfebfd19cb76751f78101f5eb72b28754bf623a70f3463bd99c70e0885cfc1b60c1a593f7cba626f3c56205149db3b04f4c450dbe0421ec6e3665d97afe2fa582f228	\\x2fade71c57a8190f5f833fe67a2e10d844c9082e2ca41d42ff475efd26cdf99e309197db54edebf4e99c4a3f24de34441245ad7a05823f087579247ffeba77c5	\\x000000010000000194acfa5a1f1db6ff256cbe9f03966895ac626b308345b10ab301857c78311071ac49fd3890eb5e0875d92e09d1510e533720b305b5619bbeb5082fb9e8a375a9ecef8035caed224ac8cd6ad54df49f329369bece52233fb8bc6b4584d016678137abab6b683b5e9d6657ac356b767433680e1245f666cd381bef9f0060d0b14b	\\x0000000100010000
32	2	19	\\x20441350928e7ab69e74599a68b2d86a164d0775e7a5dde00293dfd24687996049cb8c170468c02d4094d48011f33c49bed86bc3bd99a63de9ca2f83e48a5f07	326	\\x00000001000001007060200ed087483653a8a8ef4ab351f1c71124ba7574a4ecd65f86ae78b14f133cf3dbe578809d5aa0fde91107ff83a5fe1705b718312f2f378dd244ec288b5f1e9c69ca7e880ec1eaeeb070e80a4b3362aa78c4c3958c95def94dfc8658a724f9c0415a2ca26034d4e66614274683305377e7f3ddceaac2fbb33dffd467e89f	\\x6ab2fc17bcc4db56f7349672bd20bed3ad9b0c78cde02e9a363f5aa3295af50fc596c882211d5c07f6bd6659ab932009badaf1e7411d96435cb7816e3b6c9b0d	\\x00000001000000010a22aace716e886b54eb577f71bc79f58dcc9ed565fb1520835907a073ed130775352e9ee68f7c76cfab5207416b72bbc38c5d0e555cbd55a3824b4762553107a26c584e46e4e4c1bce6dea7751a618849d25a7d454dc5535ec22d6ec83084387936d6b2982705afd322b7509585ba5cde13cd5353b5fbce9200ac5d1457b391	\\x0000000100010000
33	2	20	\\xd4e7dd78c64115b8159e6876ccbf2e4f849de2e7beede9c1ef26c5ca9d231bfc38c7e9154e546708d16f3695ea4c6a781e9e3ddb8211d8fa698691aad7369d08	326	\\x00000001000001001f7c71dd6c3f26703c2ca3e041e5b47542b8a122a5cb24bda50feb62f7477dd381773e1bc339dd80b79ff24f5ec98a5fa7d9fa24274ba686396a0e190f974f965ea0c26f2c3df7bc91f0a8220da0142f65e2f8c6b6c806822edc16319b56c3545e9ac35e6e511001d599bb94b7cdbdd5c5aa3a83320633481048ab27c2d52bd6	\\x1f1b636b1cbfd99f149ee780419c237797211b1e2f6bf6d26dc29484cc8b4f050eccf34b6f9fec974160c3309fa0c0872d44bac113e7c493ec547357d52d669e	\\x0000000100000001c0c84c32e11520e039333f186ce70e1289766ca1e80bec9e78baf8003f3cf205c266abe42b34097612cbf1b651c4d86b79de24ff8ae3072f0b408baa3d1a6ff2c740e4f6a1a8517564563202337a51d0651bdadeb113a95e6012bfcd5c5d9505fc311b57e1456523a46d8558d34e4b07e7fec1acd18430191fba96e21364c18c	\\x0000000100010000
34	2	21	\\x147084e7be457799790e10ce342d219b942e240e99bcfe239e98599c7d33ae51146ae30efbfc742c5ee87bac1d9fd047d275a42b4abba5c66263cf626cbabd00	326	\\x000000010000010047d2e78d6d0e5d4421896fae38285f775652cbbfd59bbdd8f9b76def560dcc28e4da2b089a3e1777466885bedee1f75e2ee893bbdbb4c6cc97b985e8743dc63a448154ff5c6844c4092290a5f5932d1794978684cc2a265ef4d87272c74d93b125906eea5280519e90cffb5aa854cdc3ac25f1776ea8de78cf90a74929752b7b	\\xe05aed36d8f20ed0ef5e665198651c0d96362fe0df14ff09e0e5e9c4eff455c2e977a57b77cffe649f62138a51491fcc8ec13c900fffc0e27537c3eca930990e	\\x0000000100000001a712a1606dc37b581ba68f3e06435b7e29b5fa0daaf9cd37921588528541a9ce330b0377e822304cfdef82befa7ed3f8a7cde4e697a6822a132c5067964a846c5ef0388d2f00165f99a20e1e2ede8ee158c1f5ee0440756624d95364b484304c99e5a7cd2414448f25bfb01186c6406de9c76b9376151f1182e816c71f68e62a	\\x0000000100010000
35	2	22	\\x3d591d2a7dce86f2302673c0e6dcf3c89c06381a58b47c5478e961bd8e7fdff376b1b7f1ef73fa46317ef34977570a865094ad3c1ee20c6f8a224dfea23c0908	326	\\x0000000100000100438ae507aef147b92f0128c8e2c48c70d9701e94cbaa33726f14ca66db003463684579ba0789796649587c3a807993c78366276ee6d934b3165cedf7f66c586b47670192af11439ff0dbfa00d7f259a469b42f754baea3e96dfa20b214bd8e7ed2671f2a895a62d6718127c79354ec933884a88a373b43890315e1f0cd19d275	\\x84e361b9405dc079eac06ae6119d851100606f52abd6868bfa6a6cc6fc0290bfc8efb5f85eb6b7121bbe8767694f3762429014ffc2c5cb642d9924cb50f33c46	\\x00000001000000018f2689d38d179d2ce6e49e93585b3b69f10c31e3287f2b440f00d9d85b139c4348b84a6658d480c7fdce6ca055b5c76f422e8d153b579743c32646dc99420d63458f7e428d76c1a2262119c1269dd5748bdc4a55281bc47a98606a65f09929e72fda539e7dc7953c6eed3a4c9cb87e30119702ca391e9b97d697d840a27295b0	\\x0000000100010000
36	2	23	\\xd310eb54e24603c9537c2ce14abb8e78fa6d2862307cefbf14b44ef8dbcf3def106d45545257ebb3ec546f1cb87f0b27999fe345dba5ae3ecaac0a09bbf2ae0b	326	\\x00000001000001000e1ffbbc7e5669a7f1f74615d480306d232d74e07a93298a1a81147338aa9ccd7c637b7b681eebcbc68f772b0d9b4675bd169d34864057cb905395077dda664c4c990ebe00aacb54f03e165f8b80e0e24177495dd2bb0ba3e208e18c29fe41b2de3b0fa16b5f1abdf37be6becd143a76cc18077ddbbdd4afe8ac00d2f53a2966	\\x75a4bd3403628e65d6c3254df62d593c12827264064f4d13723c80d3df1bd84b5dd8a93757af5ae88a028b04b1660e74c33ee1b9024d1330da4d1c415c1e8b8f	\\x00000001000000017a94d60c2ec5ca5854fa040cf9106e6f4fbc5a2f84249fee196e25e8c97e4e1c7d93a571f47f00ed96f9b602a03902d27d36f32af76dbb43358f2d9d6efb3c00e68120c0c3394354675af796b2343076435f489b8b9b962a2fabd200aaf4a10c225a545cf6833776a3fdb276f1cb3450215db64b0745cc81a5c3126f4ea94ec6	\\x0000000100010000
37	2	24	\\x581a61ad7fe8cac143d16aceaed7e8af845ba3981bb6f404c99f12e8543a302ba213416afef801b175edc6386b80d67d3d5856b768c0682642d43661e5750a09	326	\\x000000010000010026abb679ad120a2fd79937114bd9722eb13f69e8397694189a660b3f512b16b4eaeb6485ed73b9239bec0f0923df83e0aedd13cf394d574ed35b52fc50391b151fb698c8814b1a2d5cd4689af3e2ad14e18b3fd370133881b5884855876bec503c7daa7a4dc2fd7e75467c608146aa7a4528bcfd5dee5048603b3ae56c19aa2b	\\x5546c3206fd84e26e7463810940e30c58908cd292d72fe40dfc3e393043186850e50bbbb0d76344f7d56afdd0eb6d11911bad26b419d377ab663cd4e45181915	\\x0000000100000001c30871919908b6c0ec4d49e75f761f36c5e59c5292c1520e07479b354ce7fe6ab02cb37b1004bbb4fab61f28db1608e5ba2c488c286822ea2070c26c9c2b9020c16a084d8689b9ec3dbedbc376fbcaac623f05d65b9c633766987111ecc4e31c1d06146c7cae77e1c600efdfa867fd69e9de0a97d3376eb2ba8f06196f1b4cef	\\x0000000100010000
38	2	25	\\x9cc18d88861bcb280cc4f06c074ed53384bf2154ba971ecde15718ba9f2ecdd25b584ce87f98267b92654f161cd102ca63a71d250bfe84a14c601966f181cd03	326	\\x00000001000001007fa2b87f311c6f468038fcd2acce5311fe73e7938b505ca56adcd2223f2428f1df620a9cf8f54b9bac55549c4bb152797f532c6308b3f2780a3398102ced3084d3f6da754eb098aad9f33c423537b7611393013e3f833a575c1711eeb713c828d696aaca323561414c7ba59d9ee842785c8ffe765cfd610d1d4d0363c9fcbe50	\\xd7f291ba920a37370908727a38a70af346ac674f29f4e80bd55bf96beb17f30e1abc8a9252e05734df34bd59f5d0264524acbf7cc610ee6848e04df5dd3ffaa4	\\x00000001000000015a10c5d3badade516809d632c4327eeef03bcc8edd6949ed5ae27154d9451b6c1aa6e9aaa789408b773f2325c9f029343423d7c3a1c272ee206250ae86cd3f2fee34a9ac35cb39be221264ece1924b1af81dd8201e237681756fddf3802e9205b1247249ae96f72dbf2e0fca04fa82f5f37724ad1b130bbe6e0da9eb74cf45bd	\\x0000000100010000
39	2	26	\\x4dc2aa243d504a44afcffd1231144aac122ea90f31447fbfe8700da0253ebc408a5f97a0313fb721569f82901edba9daeb331e78e8c5a3a865fee322b810b501	326	\\x0000000100000100b3a1ef7e991fc629e33dd902e5146b69989cb2da323d8d228ef4813ada02d274923a2c74d2c06494cf531f7a57b0d5276359c53019b38dbee8cfc05cdc9b0382332236cd0bc5f5450632ea55171ea87cf727bf999670c780d2c4358c9138d83d0a55ce05e2d0b9c4bee62f7ae2d3fec52f0cd9c1990124437154f5ee264aa384	\\x3696cf0276d97828ae0f45fe254179ddc1a67f9cc7944638c29ff862697fb9dde02585f58e8a7a63a567dd747e4840f312c5765a35d8397b1cb5ed97b89cf833	\\x0000000100000001bf58ec05786716534a1d5f2f567bfef05bd3e9ce64d143e74698e7a81270c5b7c33f87114ba436e5a15827fe2c24ef7e404fc694bf64e6e1702812031efd3a637f5deb417029fd7f9ccd1ca18b13c322f1a45366a7196f08ccc947af07970ed9754f2f3de2a0acbf35b4e0e98360013492efaa0699adb9398cfbafec1d846fea	\\x0000000100010000
40	2	27	\\x3a64b78f38eace35d070bbea8865f667a4f0ddc38245b6fe99600c1534b48de59ee8d6a79c5a062f406ce2ab19597b381cf70252b220b24e370bb8a8a74e3100	326	\\x00000001000001008f532764961cd656fb2d0a0e6a0aa01b51b823df2f1e9b27e67ea2c401d6a2233193edb1ad700c5f66cd29c0ca47c8bf92d16919315fb4f9ae258236e33aa522d777a9a0bcef6e037438b41031e31bd0c0efc0bb2dda3f5187321c980973e8144cdc6dbded24281c0aac3847589b0d320b52b75613614ee82a3ab6ac1c56b12c	\\x61c3a53d6ee2b3fbbdcdb4e2cd7d2bb9d982dee60d3372fbf29dcaeaea98440cab07a8fb9748b065eaf3f1b9b71cf1719fc17e0cd78e0ef3a684efe48c6c45b1	\\x00000001000000013f5b55ebfff99b1d1ad2a1059d268cf6aa61be9aab486470e8d54eec095ada4b6bb133031f71b84e1ddf3300cfd038d4fe1fd0bbdeb3234de4e6fcbfbd2ababd2f51f3eb4c4a7b6dfdace8f7e114ebf2b96df144c29c90d89faaaea58e0268c69a5c1b4b6e2d96d91edb2a8e31a390b5018f5d54585bba5447af4868ccc7e6f1	\\x0000000100010000
41	2	28	\\x82a3dbe669fe708d8372910d1ca51da5932348fc82060378ca2ffc5cbf99f8dfbc9f29b8f2bc6ea4983870f94fa084ebf28738077642bb44f492073825c34d05	326	\\x000000010000010057b01bd342062ff8b6c4119ce34fdb8c0a23b8b4dc521c83ef41a7869355c7b8824cf1338f2784887a439a6ff223dfaf7ecfa1bde94816e0762224f1e4dcc56fde41d2abec99ea807ffb9797cdf65160daf3d181ec7a95aa8a472a0ea36dfd11e7a2ba830a715f979e4a78aac85a5ff21a6066dd2c00fbdbf0c08d8762f421ab	\\xda36933bd9b1b7d52e2e20077e8a68aecb373db87341b2d7a9a0afedfadd6bf22cd1de1d7ef46c1f60bcaeba0c0c2f45b80555d465b5ca533df2570c66d31f6a	\\x000000010000000104156571c7a8731d87b591c3a9f9ecc41ff2460edd4cdc7935299492e64505c9b0b7c104efe500356619affb9f864dae06342a994347bd51235fe3eedddbac79307a1f36973cebdc79655e14531d426e7593c2719a5712f0004040156f86115e624f54e15e78617991fed4fa62bbd90a90c10d40d92770f23e1bbbe665f55101	\\x0000000100010000
42	2	29	\\x06d2d0da585f7fefce3713849a170b15db524724a29061b29757ce36e399f443b7a005da04cadb995c2d67e856d64e5a6b6f6cdc9c84a77aa9214e7f14463204	326	\\x0000000100000100aaf35686f8df63adaac01d92d2744439551837174a22266b4f50d0ceb7a7166e818eb14b2a496ce842f18551a10c76ab1bc9bb21a9c1eff710764398a97b6426733b9735dc2cbd86a9450aa72ae624b9a87c63fcba9b4e71c90e93f8d22b861318dc9b30b4cd4ad51ae061fee94a2cdf25ef85924d265c7504ce4f0066f8d828	\\xe6ac95ffa20671d6f8e4d6257a0f9c42ff6fe608da7cc359ee463311c8e6d27b32319912df58e8d5d25265e2c23b5e712ff747d326ddc41caea24b36f862278d	\\x00000001000000016bec38b73b4d869620105c4d0252cce14838d837c6c0edfb067867a912d783207668946be4d150a428e0a90f3b14085039fe4fbb4851d869251a0f88ba6f45741e4eb03bc0c9b828491714f5e5c343d8f139c6edf03970ac3922e1aa8ca1a46fdfab4fd30ed9c035e5d1e5ff10875103fb476b333e2cc3867b625d5672f81eaa	\\x0000000100010000
43	2	30	\\xff3e09955c2761c9c808083290457e96bf743c6e88f44e4db9a9db4a213be8ec5d8b968b7a58096c2297ac4b1a4419a8c03d695bdda30e6d343c0d9858790c0c	326	\\x0000000100000100c20a87426f85dc40b464599fb11fdfd822e15e438f266c212077f3d51b2a42d5e81e931aba6b9b975e08ba6a4d24cce14f4eb5e751ed38cba008cbeb85a2308f8827c3a28aed266e07b699a9287a4a81eb97c491d18aa7ac08605d9c5edeef32a6da6495dc43104e4be9ad859c5f7e038e3f6552c4a14d177d68f2c78d24164a	\\xb0ee04f42043af88928031cf0d75a7f70b0f501154764617fd7d7d9fd6920c37d0079f043925373143e81a3bce1cbd8e07f6058cf3f19860427d64ed498fdce8	\\x00000001000000017437a710f4d9cbc61f7fbaacda1e45feebe32d190825374d6043c31d9492d442c8b7fcd86d7759d335ebb602805042db0d9416712da950f670dec0392c5e6d5c4407e15664d486456a61ba295f2c5145f99cfbbacf47807d0121a4025ba9a9f391c271acda7b3426a8f9af9d6ec425713b0cfa84e44d269d90c78d6ba4988924	\\x0000000100010000
44	2	31	\\xb91008e6eb4645b22b5667c77c66f1406e018f39819b9583ead4deaf03e79db5e20b0464f92c716d0fce265bd0109ac279f1808d3d5b43896e07e8ce26b2a10a	326	\\x000000010000010030386088c4051e70446fb18055652002b0cb62257c4d6f3563bb8e4e375212f4ca7a42763052799be070c92478ed82479fdd738e9c943424ef986b6a2f9bb1d5460e2d7c542c10d9a4d28eb6749026c39a425c237a64fc896062de46d29cefee22dc8e69f65db3cc686bbe2ec89c0e1d00c311b498e77330e37c873e2fb691ce	\\x7e4450a260385e128d0ddc100d68c729a73714d7721db5197ba4c4083aaf30083c1d1b5ace471debbf0749f5febbb4f81766e4d2060a5a6e2afb0daf0df91e40	\\x000000010000000189d36857a039de96fdbc474322943951d4bec53cf5690dda84d0e14f5056d60d8a0111ba63ba731c9654f117cb7af07e8187732f48dc8474aa32a53e32a2c46476401c00b4cd6f715edf5f62f07583bb1e4fd48904fb0107d8dc7eff20882414927da7ac0e9df28f42a78c23a772ed43b195864c0f912559718c461f52031120	\\x0000000100010000
45	2	32	\\xf9eb86b92044bc612822a39cf77b0b4ccf8a61dbb5ffedc89f6c6abe81bc459200a4b7bbe4eaecaaf51b4d7724e48ba1d3fac7f8125f068f1e847209dd361a02	326	\\x0000000100000100343ac98197862197d751a0e3b3b5abf80aef15fdbea1cf813292ad738a6de5f764d79dce87c6dffd669d38b30a378b42504db47ebff38c7ceca566583eeb5f4376640906df4cf9e206cdac8d53fc49b604476e6121304ffcff8e474bdbc60a5bde7a68903e6ada05ba90c74165fa38b6d708010ec24328ec412eb61ba8e4d66d	\\x77eac0de97305a7c0973e0249e4a40625e0b9e22c6242d3ad1d669ec05952dc59185816b7c3b498b6db3d48c519d10ac1a4aae628c02625d0077ab21970cb89e	\\x00000001000000011c95ce5f499191ecea8b22938455d729dc06815018e105699a4ea63433bd3b380da830f261cb40df25f0085c2a71bc81af02e6a4f3b10a5970a28b4be8e637de0964808bb56c741c661b413a194807b52e344d0337a87d938e6939b1ac88b99f3f6d668e6145cb4d813c88b99576d154a9f735bec4ada6383af57912d4e557eb	\\x0000000100010000
46	2	33	\\x679a09f9fb448c296b727bae3a7f079b5fa50c41b7ceb3241b120bb0413101faba422e38f51361c25bb374abf649459c8574a8f5c6598f3fc5322985f42e7f07	326	\\x00000001000001001a89fd776b22321ce84dbd490bf7c3ef7f71689597e8f834d7090cf2145104fef006869fe8b6e0ad0d83e9c21cb4a39b19332da8c9807a83608d2ed5f6fa980bdc3abfcb01319aba476b144f5fe81377368005b7e31d5387a42c6a072aa6f39f5b9c86b7a19f67ab8ed70693b3158f757613afb099004ff4b5cb908bbea9eff3	\\x3d0477b04f1f0f5a161c95f2238ab341e533883eff7946d6d7cd2ac3330323b7e8c0b352837107169af8310dd9a46e6bdbefd7e5c509307988f971e57f9a258f	\\x00000001000000012f0b8a4c26246aa92dab93b036a5b79252af679cbe6a46913ed72a348b1f5b3be7fe4e3636eca706523e77f7adb72528f2be7f12876588766ba8f5f73df4d9aab3248dd02534e005bbbf19dda755ff026e8413501b1ddd92f46645157c76131da05ce6c3e59dc39213262cf778998d0397b473cf1db9c5ecb025e0582e747aac	\\x0000000100010000
47	2	34	\\x2590c1467a39a4177e6b92c14d33aafb87278517ce4eecae3885d3bca602fdd9e216dba064d7b8b68e59aa6c24eff659b1e1492a0aec00bb0a5333d270e8bc02	326	\\x000000010000010042cb8b6f86e7f01851c465c6e9e1a51799b8951e68759ade49b4a8f1eb6c2d91dea0fb68e0d3dc6f721167271d952896a0c112f9472fff0b96bfe9dafc569e0e2c21f41cd9b38f6d391b1fbfcd027bcd18b1b6faa16aa9c462fe2bd40a80fe04919c90a833ec4fc563bb32f7191f920be70274b96917e7703068d7d1b7cf091b	\\x387d23af4b059ce2506e1124e3e32dee2e62881376bf64d4ff9cce545d138398c0dc2f8ab87febad9fb5e98166fe2ceab981a184986db7e80df5e12dd3a3488d	\\x0000000100000001562772accbca32c5eb28e86849844d0a51259901ba28c55ce17a49117c6da6414433747e4f101ec3c352beea4482f213ed0ca3e103c26e239445a71996c72f4eee2b06a84f4a68ec4f8ab3911cc4336e37d64026dbdb637260df0a3325507e046aa72504e826d1f86f1da7b21de3b63be25f2a7cc373a5b055df2cc6157b105a	\\x0000000100010000
48	2	35	\\x443e5309deb46a4e82081bd4eedc863a06af1869413c2f8f24e5982e232f9aea947d91f877e89eaa0984053726f2a2a1e4e5e44e7458a7f9301a2a4b116a5503	326	\\x000000010000010022dd90f2f7659a6321ee4c93ce608acec0cca4979cf3efa9110a6a43d319f38b0a95a1ec8620a2968c778732cc3bcaef0715cea6390f6ca381ee1d42380b2a090b7a5b4e8f4ab8a90501dff593429094835b3fcd474e96c39d6caf8bf21573c25e5068a2022d7c58a5688aec57b0709bdb7d787f8406db377c8d34f03583b13d	\\x7fd749c60ef57350dce3113c993f4e0c0272d04c90403596c969f83db771e0f1c90513a7f655d328bdd5288a943cdfe66e5ebceabdbcaff84ce4387e8fafdc30	\\x0000000100000001557770c9ccebe0b4ca3ca57abff16b61e41d19053bfe38e03d7661f10b38084b71e9293c4d70a5b5f06bf7d2593eaee9d0ed45fa524309b8948f2e14238628690e01f5303c9be9700d1975edb1e0bcfbe46bb7b85863ce96a59d487ee89c22c0f84d83d24bbc217634e31719d31a13c2a17604fb98bfad76e63dafd262a9d314	\\x0000000100010000
49	2	36	\\x64a60a00fc5e014ebd72af365eb8fe234de7c48bc8c0a0634dc0a133b707deb6d1bf78e5465629899051f1eb0283d5004991ee4822fa0dead2835228f8572b0a	326	\\x00000001000001003428c31c6ed22ba27104ca1fd1032105953efe53d6415face56ca25f378b69245360ead9d0d6213eba9e9711a16477b0ee499a25f2d4206c055291cec588ff2a5f674091e83d3282345d7a425d6dea2c99d7de3f6398f639e0b9efebf9d10bdffe27d07c440a7721b06e82909540301205994e6dcaf05476b4637a63aa90d757	\\x816d0ced80b1f32827ecae864a7d42fde49d025ad2ed58442040b1bb1bd1bd4c227d2cdbc7af10e65190afe6db05236bf35e9f207bebbfb9578be3bb2d4f7a0b	\\x00000001000000011ff94e1cd62157334bfdaf0a1759847d4568d70213ceaa7e7e3b440989724cdaf4209e8c0a0d4a358f3b843d246cd9012ee00a98560b245a5b88e892999f06dcf004790efee623fe5920d050ec0cacbc157a54220b6831f3ff4d4636a68164168807315aef869b13068d57e99baa0e1197c2ff402ac7a48a1cb4176b98140b27	\\x0000000100010000
50	2	37	\\x5e77462f5a5856d37d12ee4e1b290680c4c9f93999f9b90f4eb9ee5dd92e84fed2685a660b9eab937494f72b6787349f6b6a0a5cdbe0b374273c7d322d840501	326	\\x0000000100000100103dafc09eaaf3eb7da3c33af9932649be90452cbada7f58369cb4ba94dba1c0e8817f21d40a3cc45c0159828e546c8a4d8cc17c5203ad2e69d968c2fca227d94926bdf6676ee09673d8d368e4ed2b802fe889cbb7a5c4aac46152f640ca7e932ea011c6647328c9db85c648e37c31c912aab548a505000511905ed4f9b46d65	\\x40ebeac9accac3fbe852b97b2e1321bf036d57d7280f7def7674932d9d13037ff6f894b274467cf8362d505d632d02743aa5acaeec191ecdc4ec5b28e2c4d5b3	\\x0000000100000001967e68db0d85ba010c09f996e588e82c409069ae536f472e468fef8e0ae56188906ea61625f0631b8b754c0a2e9a5c51191f2ddd64005951c1bc3495542e1ee6f9e48aa74acf8621844c2d857e38763adc79e6af1f1e22707ab79b60c0df97d925edcafc0f8d1f831fc5dcee0d8c9cc4c7ded14647ed7629bdd5e687ab5a8d10	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xfb35b7001fbc1810f3074b60d1763b1f5f69933f1d4632299375a0d34ab58d5d	\\x7d758d924e8bde6436820c1b0ff3ce01fa53f64fb21a0af8163ff9bb9de1de44d0a8e4cf79a1f8e5200d4ea7ea4cea5863911735393ddc6a5b71287f06fdb953
2	2	\\x42879c26b3be9fc47a58eefe0b3caa5e7df9167e69e6ac0d7fffc9e2a04c1d71	\\x45477963d3e711c89774448c96969e00e590ed03359a8c5dd9ab8c66cb3cb86386cc95c4e1e4041a4e569b890124b7a9a5525d9417ccd027937efd846d3d3e0f
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
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
1	\\xddf8c3a1b435a7918007fb795c5341b5a8c2f670df9b29e7e554741a876cf94c	0	0	0	0	f	f	120	1657485297000000	1875818099000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xddf8c3a1b435a7918007fb795c5341b5a8c2f670df9b29e7e554741a876cf94c	2	8	0	\\xc0f7f4ecaffbc0b70775391e1eb5704890f73686b550a32c1e319377f1a91ce3	exchange-account-1	1655066084000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x6ccfdf1631189f8c1d826e34853142348f69c8798fc42f3b2f370bcfb7c50c54666bf831a291cbe0f1c13a1f0251213767c9339422a62a4c027d13d68d5f2daf
1	\\xca114cac9b7e252cc9190ad3088e4834c1bd957d0019079a0dea36d5256a87b7c908ac802254973b7ed97e0ef151b2bd92af2e889e53ad194951178080c07851
1	\\xdb0af7a6a2570c972437d76085eb5e86723939807f3eda8dfdaf81766869698fa054184809ff14a9d4202829ea8bf1668ec023a98daaf6429a669929f408380d
1	\\xe7933541d7b1a50f383e394d9ac79aa89332213c2e50201c6f918f5c6ad7eed50a18030c2e440d17a442e702515daced3242e2e7feea393e7f58cbc8e9268c24
1	\\x04a56deb118b3e14ebb11c2b73ffd9572ca4c1b905999e8d4f293c3687d3d69427d3e89df0a2b89449bf8aec4f842d860da4e8ff2ab425b1f0dbc8f7525a8813
1	\\x1f14db6258949765b9e2b0caa631f2de44ca055a03042472d74def76db7b6a74edc53f31f81d152e4d231d652abd439b86cff85a97cef09e2515582ac996a1f2
1	\\x9640bfa78fa504493d85b9e16aa931649dc523bab23bb5cd00a782aee5268aa5b31cf1ddd8360ec28eda115272e382dcb15ff4af7c8757930eddd46df16d809b
1	\\x2af8b9796d3e9fbb0b3a535e0983ac00599dd43d8435ac896aeff98cb2891dd883dbb9bf834ea2361065feb6f635d4f9ab8b6ab71dcb0ad51209ac670b6cd16b
1	\\xcfff83a8cd5e4e5afc663c1e4131d057a6878a014e271b832e40bc628ceef47bd309b654b425832557ada97fa52b3e10214aa823bcd1e3cfd4301fa9e772979d
1	\\xeecd0d6965cb8148a212bf5e4066486d50fbfb19b52c8dc3731385d719ac337f8497a03bac324e95dbbdaed264fa05ec64cdfcb96ea1c5b495b0441222c3ccb6
1	\\x32c9a3da3ea2fccff4a3d59a667376202f2518fba535fd33984b8df0327fb51e84a0b4328602a1021ea85190383f38a667637224918a3694f4dab186f1a561db
1	\\x896bd735e6192c0f504b4a4ddd15671dee2562e6b3e33cfee9d6e42e234429f1f77b85c4cc68ec9e7d02c9c0e0d3d5ea42dd6eb11a27d914748a2840ac0cf714
1	\\x4b14258967feadb7b98fe34a88300e2459b827a7b8f54a48ea886087f416af841131241fc94d25f039673ade85fc481002592a4c06d6d7c8661217f82296bd19
1	\\x007cfafbcfaea2317afbba206e9187eafd1d04438c58668fcae28dd9630f9cbe7d037c129c47149a3dcfd19fd3801d4a10dddfc528fd23abc9d2a55f589fa30b
1	\\x0d699d461f56aa19c6b9b79500e9e7bab361c311fe03bae4a8569bd7fbbd2840bf5d6dfff665f0a3eb45b29ed1fc642da911b50bef4cd034af8d870b20bb3ae7
1	\\xddf430a25c9ff66b7b12c38431fe462cb4abfe46fac4e4de91756dfe9ec1799cd67814a866aabb395bacb1630a3c920ca84e1420100a43cc61050c9a4c517272
1	\\x4900efc57a38bbfb515047e956418765741c2453b4ff0a7d63ab4d7b8e66547394cf8249b2cdb841d77692f194dc2f4d4ca777b91825fecfa44ee8b0eb7ce656
1	\\xf04336dee0fa7b349541253025f463c2cc91da2c0b1571d462ba42aff75d758e3e11e6aaa2f5710ecfe7475326b48dfe1238d5f754f2bd41c295fddea7a111e4
1	\\xb64574b77eb771ef68fa5cb0ffef315896eca2eae5f59cd0e6138c981f263b7ca8dd697a97b6b5df10e885fdd490e1ef4e3193e7b0a0bd80032b695f9aeb0f5d
1	\\x469819575ae33b8a3407218b99c6b4df91bc191756df71321c62c9d2126aeafd1efa4bae830fac942ea34d9a7a91f50dc97e9e1db298e9b616a253bbb3c9be4b
1	\\x732fb1a9185641bc43f1abf8d4869cfe13d583cc9ac85b0b7e21c026f2c5dbc45f6167c4a3c8ab3100a9a97988218056ccece2a10edaeacdd4a649bad599b8ac
1	\\xde5c3613d1f934e131387eabbeb1a2c78f217bc9151a82c849048f8c11c66adfcfddfb8ac40fc4e4ab2d1393ed083a4bc4f36d8bd6d830350468157e46212130
1	\\x8dc8dca32941c69cff69a01bcd6cd5d549c59541721780bdb4b5b5b94f33f2de40284c7f3c6ae2fd31888e3f4f7642af78d8e9871dd77126784e5271807251dc
1	\\x34bcd29cb6ef0e38137093fe6bb2b525a5d4ca12eb49129a511c1636cdaac6a8ac463e5a417286215ddc12ad44bbc3b1a48c5d663026ff6096c48c40d360964d
1	\\x9184a7defd42cca3acf1cb158c6f2d77ed02601b3203afb276bdc51e7d12a6c782848d109b8feeadcf78f6f674b533a7678b998b5483748716d73ecf4fad439f
1	\\x453e60ff4b0fc00154870d8ea13cfcf0d54f876ae6b623c61399912ec72ca74627459db27c61e8b20039d3d832d519a976310ee0a9a0b4cd9dae18647c277b1f
1	\\xafb2aaa7695ff82dfb88acdd1de2e6ffe22efab728cc25b93bd6ab9d460292fa54a3d56321888476af3ec9a0a2ce91e3fa7c7ca85790578093abe7499347ff37
1	\\xf5efe89961d02cf9406089f56c88634602741686b32db22cf386802b17f3f6e797534393534d4b3c87ae9ff5e6811ae75ee40cbed11f0c500d1446ca7888075e
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x6ccfdf1631189f8c1d826e34853142348f69c8798fc42f3b2f370bcfb7c50c54666bf831a291cbe0f1c13a1f0251213767c9339422a62a4c027d13d68d5f2daf	36	\\x00000001000000019ddde6243bb7536a2e195f8f53b7cc167429c9c7d6c04be21e7dc74f5799746dc875819df6988c254dc65d5e37f299358ad84ad7ee410759d1734e6f2bb4bc52019aefec0da0a98807795d4710844b3937980e9ac1afd660ed5810a72af042156583083d5be843bfea54bb691cdfa2bafa82ed1ba97c3a28a01a734a0630a628	1	\\x2503fefc3399d964ed02c955ec1da6500b659ad33f2dda182cdcc329b7e0acc1b30948190f3674c1200bf1a01a7770660eee4a466ccf9187f8d2e7e188a18a06	1655066087000000	5	1000000
2	\\xca114cac9b7e252cc9190ad3088e4834c1bd957d0019079a0dea36d5256a87b7c908ac802254973b7ed97e0ef151b2bd92af2e889e53ad194951178080c07851	264	\\x00000001000000012164e269d3e7717accac92b13b291a1d41b572f4c8906bd7e7545604c8e22c6df1b9d4262cf5338fe2df135b4931f28bd53a3468ce90a5ad60f692fbd78f2693d719908a2e8d8f0bb0985f162a3a6897ef1c5302bf04de8947be4f7c6e17d747f8ea35473db37a56077d3b2e7eae1fb6f7acf2b1b0a6353232ea2a41c44df00e	1	\\x531dd41775238aeca9a2c98b50e5faa12f6529b2c2eca165daaaab1c8d8e608d88e83bd617f841a18d859ff3088efdcc7bcdc080433294d583253f6e66278100	1655066087000000	2	3000000
3	\\xdb0af7a6a2570c972437d76085eb5e86723939807f3eda8dfdaf81766869698fa054184809ff14a9d4202829ea8bf1668ec023a98daaf6429a669929f408380d	82	\\x00000001000000015b608a3a9bc472a4bed3c76080c00af9b00c4f68d493cc31fc49237eb2629390348ebc43bbee27ca8bb81af1299e8f00ba0f61b535f80cf1cbd9d3ce59dedada8ae357cf719a4f6ffd27a6c1bd7204f241b99720249caae4bc0480cec1b17bfc682c130f4aa8eaabc251895deba882d1a6d0c47e44cb4ecf8182769b3859b48e	1	\\x6c167333c126b542c0a56f9b513774c113f2452aa7d98619526d7711b2f7825e6242ea04afffe1f124d437098b3fd6febf12b18888a6b3c47187ba255a412a0e	1655066087000000	0	11000000
4	\\xe7933541d7b1a50f383e394d9ac79aa89332213c2e50201c6f918f5c6ad7eed50a18030c2e440d17a442e702515daced3242e2e7feea393e7f58cbc8e9268c24	82	\\x000000010000000160d7aeea9ea8cdb932a0b778a9b27a0a6011017f874bb490e59cad718a9c027dfb71117c7127f68b797ba1e4b0922211a445db39fce68c281a6f78b1c328f6202acf56396cf3d2bfed30a0401e119721578103d75655cbb0539bbef3ae492b8ef0fa409fbadec385b7ffc110a81617eaac3a184f071526ed81785333f698dee9	1	\\x9eaa67c8006e1f0c230443f1ca5110009b93dd52b03aaed06e5a55554a8a973e212db1a6f6702a148c70e6da8e6925536ae8266975290c1472de0c274e1a2a0e	1655066087000000	0	11000000
5	\\x04a56deb118b3e14ebb11c2b73ffd9572ca4c1b905999e8d4f293c3687d3d69427d3e89df0a2b89449bf8aec4f842d860da4e8ff2ab425b1f0dbc8f7525a8813	82	\\x00000001000000015d12a39cc11c3066769f093bcda8fcc4339cd0a8c9c301b8d3562f1a2d61e1953b2acf3e43630b61419e825a6fb01d9fe76b75aeea0c0484ea31cb501d276c2b7d3a91be1999c4f3d7770ac37fa101b947a8d4c5000661d70d563992aca5ded6f8c22910630965e8caa3d45a3744fc8df7dc62a18f69e09d21fcffc99323142e	1	\\xfc7fc960dc8dc34b2208cec16e9603be533ea18addc42b2d77792283735ebe44de53fe2ba9657790d427149d3d43fd314d1ece3aa6b96f3c47af6c5fb061560a	1655066087000000	0	11000000
6	\\x1f14db6258949765b9e2b0caa631f2de44ca055a03042472d74def76db7b6a74edc53f31f81d152e4d231d652abd439b86cff85a97cef09e2515582ac996a1f2	82	\\x00000001000000016065d3e7c491272e954d84702ab02b4f416877596f3cbcc0c42cc5f51d3109289011bcd2e5148d6c2d2933edfa9f8925fdc6d7f854c643aa21c993f54aad6080f84c00d6403a113c14feebad2eebfbf8ec4b3c3e8bbf479f3793eba6960cf3a307e176374717aaa7788ad71640dc70edc2ef1bd1b836a636462c9c0d4484f709	1	\\x03dd7bfc7f6e4ce98e139fcc35d9d783597898a3229c086fc06594208f2bf4c7be207438212dfc9452ae2a1b44f552f776e9b7cb2ee291a8828889b25a1aa90f	1655066087000000	0	11000000
7	\\x9640bfa78fa504493d85b9e16aa931649dc523bab23bb5cd00a782aee5268aa5b31cf1ddd8360ec28eda115272e382dcb15ff4af7c8757930eddd46df16d809b	82	\\x000000010000000173436c2e6d550dbb1376cad185a27b094ee8fced57857477e7b2e6fcab948aef34a690726096f243b824b654ffb1dd4adede7507a4f1210ae78681edbc471b829520a2d2ebcd4a16632e215403f2c5255138cfad2cbb07a30c83bdd7024be6e011d66515d993af13c731318b0731f264f5ec4b2a0c4405dc686466d70e62aff4	1	\\x2e63de2b6c431d3a206af2f3f40bb001f71203593439b2b828fcc59624bd132eca468ce3c2fba7a9f93626ebccc19830fb9b70ace5b45c0dff74c5b7d41f4b06	1655066087000000	0	11000000
8	\\x2af8b9796d3e9fbb0b3a535e0983ac00599dd43d8435ac896aeff98cb2891dd883dbb9bf834ea2361065feb6f635d4f9ab8b6ab71dcb0ad51209ac670b6cd16b	82	\\x00000001000000018ca0dbae9776ba58e1da3974565e28dcbb589a6af0d400f6bdbd744d176408fdb52a7d89896295d28fb3f4369e082b8a3834f5e07765aa29833004fa9f2de1062ce854d52c447787ca6c9dbda7c014e6e25254830ca0eeca9e6becdac672692831b566912f1870e7857bbdf2bad9e3f345cd10a6287171dc41dac3bcad83b70e	1	\\xe2dbe3b5f7ea514570bc162e721d0434aabcbcf9bf2ee4495808e8e0ef48c95586b0c59056dcd8ae9c482cc45e795374c0576d0c39af05780219e3bd4d098903	1655066087000000	0	11000000
9	\\xcfff83a8cd5e4e5afc663c1e4131d057a6878a014e271b832e40bc628ceef47bd309b654b425832557ada97fa52b3e10214aa823bcd1e3cfd4301fa9e772979d	82	\\x00000001000000012ae0df962b019dc4854d416b0d86ebccc4656ebc353a2711f476d01004baba4cc9c06bf4ae92c0dfc1e370174c09103287f7a701ad8056366262a07752090185c6a64f029967402b955f4dfc5ba02f4b6acd77c04e365ac8e350e64f8fc091be415aa6b148b13838b27224404a2424872386ead3e67efffd381cb51508350f2e	1	\\xb4c6bce98f0d8d66dbe4281d6ce4bef7bd7d77006d86e1a0ea1842ba0e9e8070f808ec0a0d71b25d1459ad4bb2d91d5c708c60ee12a0ea6536c337f12139b305	1655066087000000	0	11000000
10	\\xeecd0d6965cb8148a212bf5e4066486d50fbfb19b52c8dc3731385d719ac337f8497a03bac324e95dbbdaed264fa05ec64cdfcb96ea1c5b495b0441222c3ccb6	82	\\x00000001000000013b07845fe834d59709bc3e3b02dbbe11abb97285f6913dadf7a8eb40b4bed615d427fa6528e607c6a09f2f0ac3f3b7f9586e18f1c94de2395f436459282ab3b00c8f13d17e90d8b6c9dde2ccf179adc13f897604da285dd4d27eb447b6662b50b6c94dbddedc8aed98316e245cc8ecd08b2a9ddce233c0865ecc3b1cdb106737	1	\\xb4fc77bb0e168d24c47dbb5d1bc9248d34a7e383152a44570d5c6e1a6af70450b662cdf4553c54d0a36eeae514b0fa656841fed97ed9df4450eb47b508d7df00	1655066087000000	0	11000000
11	\\x32c9a3da3ea2fccff4a3d59a667376202f2518fba535fd33984b8df0327fb51e84a0b4328602a1021ea85190383f38a667637224918a3694f4dab186f1a561db	371	\\x0000000100000001a476ff070e13121eb3d10812bc44e98fb4fad5657431994807b430b99eeaede1fc405025c52e00a22a344c2e934ddbba9387be99fe5bd110f5343bc47da0b89486dad69e294a7cbc6347f790d777ba43c8ae742589a8432f3d4f1aac0b39caad326f6547594675bbd3b51b7c8b46e3283513d5082a6fdf57284a5de297a875ea	1	\\xb35d8230eb7e65913d53671b82b173f5f6e21aa62137825c5292d82f9524bfb09a2682b6644b13eb9f17b1fd8c34a865b7ccbdf399dac64b0cadbd2ebfc6f204	1655066087000000	0	2000000
12	\\x896bd735e6192c0f504b4a4ddd15671dee2562e6b3e33cfee9d6e42e234429f1f77b85c4cc68ec9e7d02c9c0e0d3d5ea42dd6eb11a27d914748a2840ac0cf714	371	\\x00000001000000016735821b90c230925951456f103c4b16ae9e1373dbeca1f9fcf8502bd26e20e70ab72c4802c77510d78553b0e0b9752e7cbeece443c121ae7c9f2b39f4b2725c8c1c8fee012c58839504d88c17f1a6efc61e1df3476e23456ca6b465953add320ec4bd01f546b1429a564eac7b7155cf4e40084ada1233a568548b105310eb48	1	\\xa4467cefc767f57d26ce1e90f9a4641d1a99b834e7597cbbff7d261d59d40b948b90c616141a1b9145a4edf1bb18dfaececaa369a4a2953656ce3cfe96ffa102	1655066087000000	0	2000000
13	\\x4b14258967feadb7b98fe34a88300e2459b827a7b8f54a48ea886087f416af841131241fc94d25f039673ade85fc481002592a4c06d6d7c8661217f82296bd19	371	\\x000000010000000174ec9a8b5f0ba776a25be83a6647a48f6ec3d0c0ec22ebecd63db18d45c44d9daf1bc5fc01e3f5b838291fac92de3d4d631b44992c4c013bc0fc573d6b1022e27dd549c622d6b1e287f9b4d736d56addf6c039d9d9df623ed86527dfebe8eb4a5fab10a1e45f88cf2dda12b9a826bed3f6fcdec1909e0a20275181896cdd8b45	1	\\x9a0cbe97dd94afba5eccafaffd2c736c62b7c78e045435d67cd1c39ca1a9492b83c3be858512477fc51fd1dfe554ec5597a3c6aec2417e72e471dd87fa2fe604	1655066087000000	0	2000000
14	\\x007cfafbcfaea2317afbba206e9187eafd1d04438c58668fcae28dd9630f9cbe7d037c129c47149a3dcfd19fd3801d4a10dddfc528fd23abc9d2a55f589fa30b	371	\\x0000000100000001613ff1e1be4f2d8eec1906ad14b533cd25eb2775a0e2aa50164230bcb583516f6bb2837d654b502fdef400a0a4c540ad863486aa39eca82dbbe5af6aa55ae2d67931e7cb1de5fb6391cc3ef206cc0646f1d61b044339d2d93c9d3c0c4e40cc9db912be169cccfbc3abcdf96910c9c5d8e2dd982d33ca9bdf3160dc8ed2be2aa9	1	\\x156347ffff9e705df7a3f4626e3d03d8acba6900079ae14173817f6bda09e9ad5f9d28d912613fdcd1dc30c8404ad21a3690f4beb7b77e9c97ceb737c7f45802	1655066087000000	0	2000000
15	\\x0d699d461f56aa19c6b9b79500e9e7bab361c311fe03bae4a8569bd7fbbd2840bf5d6dfff665f0a3eb45b29ed1fc642da911b50bef4cd034af8d870b20bb3ae7	406	\\x0000000100000001503e86020b6326ffcd031f4afd946557e4e85ce67bae835f2a9bf3c80ee6b6a5168fb9d8b9c253530cbc73190570e55747250f8eac130276b02c12757b67a4be403d15641052deca21b8101afba4b578c4ed5212aac6c90a224d2731d38a8bed6ae2c11f326f6deec8e3e65ad139049e2149c7ec318c55de182d11c9ef51cd19	1	\\xfa59755b7305be1758bf11e74f6e91868aadb45da3caa96dd7f370be98bd693fa0bfc4ab2e862ca5167b94a0d2a53897cfc013803ff5d6b1c002ee017e9f790a	1655066098000000	1	2000000
16	\\xddf430a25c9ff66b7b12c38431fe462cb4abfe46fac4e4de91756dfe9ec1799cd67814a866aabb395bacb1630a3c920ca84e1420100a43cc61050c9a4c517272	82	\\x00000001000000011b6df7d7774144e6c0fc6ee881ea629bdf8e785aea23c86d984768ad8a095c9bb9d78b2984c8ef5ed7f9c56cc640d32104ced02473cd6bb35b29961469eff5d8a76df5dac17781cb047adcb9777426b9b3188fd837c577963c72bfb2032353e695c7e417a31dac1e5b67ee46515ff0c9ef5fd4cf01a118daba8117b686b69fa2	1	\\xaced90bcae7a9480e9c3f373c31596da7f7b1516358149f2f09ab78e83816efec7756655e420161455d403b4d1f7604fab1e2ead2358d55b1b860a225ab34701	1655066098000000	0	11000000
17	\\x4900efc57a38bbfb515047e956418765741c2453b4ff0a7d63ab4d7b8e66547394cf8249b2cdb841d77692f194dc2f4d4ca777b91825fecfa44ee8b0eb7ce656	82	\\x000000010000000138b5ba7c58866eccdf908ed050896dce68123f9433ae962028ec7e5da6191145e591b27a50bb3cb5f9cf5fe8f77d7700ebc400056d5f4ca4e6cadb4bbd35f06f7fd0b2b8d4e8b22fe5c91ebb0e3cda5fe4466e5f3a8d20a67d0204d432c90f372d60da25b9c0e92ed131dd83117e1dc86f37c229f548baf1568199a27eed9d9e	1	\\xfb69454f61874e1615531228cbebebb428137e8d7a227587fc82dde17108bded63ef0c3d6f149c01d3c151060abd55e11794ff8a1fad5970e479b0c4e96e0307	1655066098000000	0	11000000
18	\\xf04336dee0fa7b349541253025f463c2cc91da2c0b1571d462ba42aff75d758e3e11e6aaa2f5710ecfe7475326b48dfe1238d5f754f2bd41c295fddea7a111e4	82	\\x0000000100000001a22994a6bd2e9576e8a672886147c1b3b62be87d0d2dd67a92b313699d28383bc28793b445b5eba871bf36e6a22216e347700441d734daac136666d023ff91e68ca6352a2deabf789c73fe6b41f05d9136fa7796d1bc339fa59cd821b230104e91f395e063e6235ef96cc145f225e98c4efc999a29ce5bf415e444a0a7225b83	1	\\x13502a1d4e8a20739a61ac4d1c10185719f5ac28d1b9c819ff00b8cc6d870d3697414372dcf11ee4ce8bb10f6602954be3254651a0cb5138c58ef1877394df07	1655066098000000	0	11000000
19	\\xb64574b77eb771ef68fa5cb0ffef315896eca2eae5f59cd0e6138c981f263b7ca8dd697a97b6b5df10e885fdd490e1ef4e3193e7b0a0bd80032b695f9aeb0f5d	82	\\x00000001000000014b0289828012e576030a4aebed7b3843bf581af4febc99597f14414817dbaf5bdd2c5608b6857ffe588db8d0d4b370895acde248afe0f3fac6eb566e5896427e2e24d2ba9c970b2081716de37bbd9e3992ff5cc64d003ade16b762d2b89d348e63368bc2765cf86caf03326d8a7e8dc499573dc0649b0d3b136074e1243e7f71	1	\\x7257dbd5e5256f75935f3f75903654f5581358b8778ed0e445f4e3925fd3c37e04b9af079b9813a0138fd1e42cf05cc7f7edc29a1f8c3e026083d004afa1f60a	1655066098000000	0	11000000
20	\\x469819575ae33b8a3407218b99c6b4df91bc191756df71321c62c9d2126aeafd1efa4bae830fac942ea34d9a7a91f50dc97e9e1db298e9b616a253bbb3c9be4b	82	\\x00000001000000010e9e8881f8253ecb97227ea7fc930b09bab642b445766b497ce039184748b347ca50d194cdbcc948587cc2a9b0a1776731e241e1fc97f3724753b3909fe4b028f5985807c0584d68773dc41e0edce83be10ffa31b4259ed9a9b5810e6dd2150fa1149d4edb08652b1fae392011de74cd4e4df1c8d0990912a2f762bf6dc0f6b4	1	\\xc408f39f3aa0bab293b131d37e1a593309c3e9a079172fc93161079265e1b10401466db0b105d065a9aa3e4fbaadbb1add564d8b92976f7f64899f207a55a30a	1655066098000000	0	11000000
21	\\x732fb1a9185641bc43f1abf8d4869cfe13d583cc9ac85b0b7e21c026f2c5dbc45f6167c4a3c8ab3100a9a97988218056ccece2a10edaeacdd4a649bad599b8ac	82	\\x000000010000000143abdbcd98082bd61b58a7d698b6c3341406fb0e3c4b64f4f5ff41874d561143ae40e095a97e7a019367339b0cdab13b542eb1035e14fbbd7808d27a4e842278907abcec6e7bc332d549373421826030646d80ef072a808a1b044ec54c718292ef8e5e775b6eb8610791fc43c61e3b4d592c560934d760e5880248b9aa046797	1	\\xfbaec29a742c0e145e8e48480d4a5bf6c53535927902eaacf298b54536d5332a376a84185eda8e3241b09b28f073f769ea18a8c73279d2f2ccd007c8ee1f1a0b	1655066098000000	0	11000000
22	\\xde5c3613d1f934e131387eabbeb1a2c78f217bc9151a82c849048f8c11c66adfcfddfb8ac40fc4e4ab2d1393ed083a4bc4f36d8bd6d830350468157e46212130	82	\\x00000001000000010a3b4c15ae5a40f9ebea41ee70bde740a2a9e92f2cd0d22d0517c7c677208746389554a7944ddc6687d716e0d8401cbee94a76fb4c36881b897e30b397f05171c838f69c8a0e8c0974918f5dbaa49702ef8fde419e7191046c4731da156fd38117d92dd01cc60bebdd9577ee7d48bc3acf22e367180eb2e7d4c7ffcbd4418c60	1	\\x7877d7361c40306e125c6fd6960960e10e80cff4ca904a7ac28e23df9ffccdc6ae9fc2dfeea302af11cb44894f0a1d5971673557a8226358423bfdc973347503	1655066098000000	0	11000000
23	\\x8dc8dca32941c69cff69a01bcd6cd5d549c59541721780bdb4b5b5b94f33f2de40284c7f3c6ae2fd31888e3f4f7642af78d8e9871dd77126784e5271807251dc	82	\\x0000000100000001258caf46257c0ee860733b6e1b348b4f33b4e0448cfd2453595dcd0346367d1aeab9bc889aa1333f9162d786d9bd543c31967da89431070e5efe55d628c4f4d735a808de99a9a638f380b35f800b96583c6954a5b21cb40bee25a6a3c9310c66a727a54fbfaf8073c8684233cd82524e0597420154c3af04ef869ca953c3920e	1	\\xe0a723422ca40d96770b17e97938a1f2866e09cf40beee299ca3b1c46625596d318dfe2689ea6e36ca9f77c782a616129d519e813a898469b0d6566dbcdd8e02	1655066098000000	0	11000000
24	\\x34bcd29cb6ef0e38137093fe6bb2b525a5d4ca12eb49129a511c1636cdaac6a8ac463e5a417286215ddc12ad44bbc3b1a48c5d663026ff6096c48c40d360964d	371	\\x000000010000000169925ebe5df5499176d5dfdf1065dbb9998e6fb44f246b7df7b4696916b7904b38dfc8a1f59c1c06ff4fc5e75310782c90ea5985ed99bb7100d61a2e9cc631357c7a751994a63e974e652b9d7b9bc57cd0f1d05510c28e2c2c6db1615bb0a73a8607ea3d2cb725b790b2467933178b8922f8c06990825f05838b1fa1b10312cf	1	\\x10a5b60a96878621fc2a5468409da808ad6afac9557b6f0f66a638251e5023ee076d61752f0aa8549792f0ca378c9f0082e8db5fe8d5cbd3ec5967e55d23570c	1655066098000000	0	2000000
25	\\x9184a7defd42cca3acf1cb158c6f2d77ed02601b3203afb276bdc51e7d12a6c782848d109b8feeadcf78f6f674b533a7678b998b5483748716d73ecf4fad439f	371	\\x000000010000000183c76a65d358fbbc0c4d67ff1990ebd84275ee848fcb09808bac8718de62f58d859ade8fe075d4cf3a939594bcfb81cd3ee8987d6518ce99f08a55a46c66aad1f219eb703495c7bb0458d3a095c67547b58e36093ddf8d22453c92bf6978a93cee643a9e2d626a96aed8f7117f2ac6368ff7693e102f71e59580fe327dfd8923	1	\\x00835980166319d4796b7a62e16c9547cf965a14e447fe4cd1f4e21210ad07341a5c0c942582a95e9c3c603b625d1288bd79f579ae5edde1102f9a98ee99ba0c	1655066098000000	0	2000000
26	\\x453e60ff4b0fc00154870d8ea13cfcf0d54f876ae6b623c61399912ec72ca74627459db27c61e8b20039d3d832d519a976310ee0a9a0b4cd9dae18647c277b1f	371	\\x000000010000000190dcdabb2ebb79356dbf0c5ecd40a67f522aae5b685bc8b23c2783848b64676edc96114f7902ac3e1a6c9e94c7d6842dd65b319e33db676108375cf6e570e3288c80e79145b8bf1582bf38ff1c6b3a82fe0b6022b1f2b8873cfaf11296495de3dc349eefa8537c7d370364c5dcee13126da98bb421e3ad3948c0a89bcbc72570	1	\\x85142c30fe0bb006c10b92fb0f369731ecb85f152b8b27850102f88f5274d9852002be1e4f8b1238a4e893292e042d3806bb89a50e3b186e98d122a07eb45808	1655066099000000	0	2000000
27	\\xafb2aaa7695ff82dfb88acdd1de2e6ffe22efab728cc25b93bd6ab9d460292fa54a3d56321888476af3ec9a0a2ce91e3fa7c7ca85790578093abe7499347ff37	371	\\x00000001000000019490dc75b3f6c8d5bc52d11a9986cbb5dece4a668c141e9969d7d2a6112ccbee4fb45420fd926d1a01f916196820f34a867b620f724f42b72b7da5d9385f9ebaa6d757848d16c50b4d38debe8c9a0e28e91846e8134e0d2bbb6adee1a45f6b1810d3151c695416ec0188466018bd894a521a6a0220c3af4ef5068e9b67be2d69	1	\\x23db88e49f9d64e1df833108495f8c3350dc71ab15412c0d83ab262c0d04295d3ffecd01a20415f6c964f30806ece271814d5a88954144832523f004446a1000	1655066099000000	0	2000000
28	\\xf5efe89961d02cf9406089f56c88634602741686b32db22cf386802b17f3f6e797534393534d4b3c87ae9ff5e6811ae75ee40cbed11f0c500d1446ca7888075e	371	\\x00000001000000015c86449493fe6e0a4b4fcd0ab7cf2da94bd0a28936671b8a24aec6eda7db0cb9d55934e3f9b95d2c96a9008910b0dc847524963b9ff73d4b029f43fcb138e70a24fa9266d8cc3add5c6029354c24703c0c6179cd988c441366fed07a0960a640cca09ff90e210486819cfe581a6877bb1667177ba839cfc0143df3ca4165d9b1	1	\\x3cb5f58e85c210e337db8c0b74a44f10629f021628dbab17cd10756f3b0d6f4d96fc04fc981a965023f21cebf577105cd2754b76a02d3fafdb0691c663309207	1655066099000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x0358b3bca47ecb66db18e79e16312823f6850771efd69249e5b949ea87049ae1862aed869881c5716bc4c7ba78da23d65f06d65ea27c20c83a25c4fcbb674f03	t	1655066077000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x7d69fa6dfe7be1a84ae35e5d6b3cae9d69ae63a6ab47d843e78592b780f5221f047c0dfbea4add6fc6590a1992a3f16cf324bbd931b60858b4934b0e90896f0e
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
1	\\xc0f7f4ecaffbc0b70775391e1eb5704890f73686b550a32c1e319377f1a91ce3	payto://x-taler-bank/localhost/testuser-ua7dydxm	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
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
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.history_requests_history_request_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 22, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 22, true);


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

