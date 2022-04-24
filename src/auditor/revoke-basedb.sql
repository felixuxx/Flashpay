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
-- Name: create_foreign_servers(integer, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_foreign_servers(amount integer, domain character varying DEFAULT 'perf.taler'::character varying) RETURNS void
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
     ,'taler'
     ,'taler'
     ,'taler-exchange'
     ,'5432'
     ,'taler-exchange-httpd'
    );
  END LOOP;

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
      '(reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves(reserve_pub) ON DELETE CASCADE
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
      '(reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves(reserve_pub) ON DELETE CASCADE
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
      ',remaining_val INT8 NOT NULL'
      ',remaining_frac INT4 NOT NULL'
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
      ',purse_expiration INT8 NOT NULL'
      ',h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)'
      ',age_limit INT4 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
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

  -- FIXME: change to materialized index by marge_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_merge_pub '
    'ON ' || table_name || ' '
    '(merge_pub);'
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
      ',current_balance_val INT8 NOT NULL'
      ',current_balance_frac INT4 NOT NULL'
      ',purses_active INT8 NOT NULL DEFAULT(0)'
      ',purses_allowed INT8 NOT NULL DEFAULT(0)'
      ',kyc_required BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',kyc_passed BOOLEAN NOT NULL DEFAULT(FALSE)'
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
  -- FIXME
END $$;


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

CREATE FUNCTION public.exchange_do_history_request(in_reserve_pub bytea, in_reserve_sig bytea, in_request_timestamp bigint, in_history_fee_val bigint, in_history_fee_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME
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
  SELECT
    1
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

END $$;


--
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  my_partner_serial_id INT8;
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
    RETURN;
  END IF;
END IF;

out_no_partner=FALSE;


-- Check purse is 'full'.
PERFORM
  FROM purse_requests
  WHERE purse_pub=in_purse_pub
    AND balance_val >= amount_with_fee_val
    AND ( (balance_frac >= amount_with_fee_frac) OR
          (balance_val > amount_with_fee_val) );
IF NOT FOUND
THEN
  out_no_balance=TRUE;
  out_conflict=FALSE;
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
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

-- Store account merge signature.
INSERT INTO account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub);


RETURN;

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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, bigint, bigint, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_purse_fee_val bigint, in_purse_fee_frac bigint, in_reserve_pub bytea, OUT out_no_funds boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME: implement!
  out_conflict=TRUE;
  out_no_funds=TRUE;

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
-- Name: close_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.close_requests (
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
-- Name: close_requests_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.close_requests_default (
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
    purse_expiration bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    age_limit integer NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
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
-- Name: COLUMN purse_requests.purse_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_expiration IS 'When the purse is set to expire';


--
-- Name: COLUMN purse_requests.h_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.h_contract_terms IS 'Hash of the contract the parties are to agree to';


--
-- Name: COLUMN purse_requests.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.amount_with_fee_val IS 'Total amount expected to be in the purse';


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
    purse_expiration bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    age_limit integer NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
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
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
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
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
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
exchange-0001	2022-04-24 20:35:42.36018+02	grothoff	{}	{}
merchant-0001	2022-04-24 20:35:43.235584+02	grothoff	{}	{}
auditor-0001	2022-04-24 20:35:43.77308+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-04-24 20:35:53.644737+02	f	fc6cea13-e583-4dee-87a2-f59bd830d418	12	1
2	TESTKUDOS:8	EC6J0WG1SVY9X2P1NWA1NWCWZVM9XD7B2XQR88EPS578X4G8RVHG	2022-04-24 20:35:57.110514+02	f	9d61f8f2-2aa9-4373-b3b6-f7eb29c5b5e5	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
e7de51d2-5115-4e37-8943-0d75f51885e5	TESTKUDOS:8	t	t	f	EC6J0WG1SVY9X2P1NWA1NWCWZVM9XD7B2XQR88EPS578X4G8RVHG	2	12
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
1	1	11	\\x905521992d3e122f09deca36d25f8884ec125af71fba39c8d1743539483b76799e50dda905c862ca40914817fd300e4efdddc31972814946c080ffeb37017708
2	1	101	\\xfb09c927d2339674c846a6c49118a79a3e61bc4c16d47f6c9e7989e1706a4d81678f5dd8182a57600e0e7bfa513d85931bb9ebb1f7ab3a69b372d934c1571a02
3	1	211	\\xccb3b30e73b3ba6bb4be16215b00a9977562036f959ecafa88e272ca64f55110c16d858a18733973603bbc06897b7539f0069dd85f7f5b29a622f37d03de7d0a
4	1	225	\\x4635e967b6c0d92685eb9b2a26978e90cea12f9ac7ec3025c76437094f482270725fb1bf08790ff57cdc44a46c7f31eccf6056bcc9f0991f773031b207aac802
5	1	15	\\xf24fa6b4740d3417864303a2192a44caa4986089fe83cc4baa11a802341d254ebbfbe02544b09727120bc185f1e341e7d1a04c22d831efedfa87e67b45679400
6	1	181	\\x7b18e29f661af75647bba7937c0050e22edbd50011fbdf70f3f37af236716c3f48f95546afab7f0d027fb7d41720a61ebbe7177b5b3215903da772fed3bd4005
7	1	96	\\x70c78d6c71e04f31304769c4908a2578be316874c7bda8be546f15a8e6c314aa9a00d5edf1e22612d80ce805a9508084983c4944aa6f04cc95b39a13fa70660b
8	1	288	\\x41cd3b0e229b81b96f9b38199dc74eaa1e39b72bdcd0a8dada46fb8609bdc58c9b08b220f5d3578457e0997a8d5b7debde5c2fe695699fd575bef604fc2bd80d
9	1	180	\\x7e9ddd37c0f4a309c73b6b82728455d26c47c314f3696832959d23ef22417bb0795e5635d6f5a2629103c6b66b8cd9c49a8646475ca5d97475d2a55c52480300
10	1	122	\\x53934cc2cc2beeacf20465439f7dfeaa24d3ed70ce3a7edf6831e8ee4871a9ed2ef56217a9bafa4341faa1b4fbd4e39d0be375f16a94a5cd284410b54d213109
11	1	44	\\xb2cde6bc19d3b256b1d5e4a3b400239dece5664e4afac374a662298810720fa7f65b1233d3470336f49085b94c48a5c4224970b56ac5ab98c41d2425ab052a08
12	1	284	\\x010abca935fb54496e9be1d4d2f72a6e9a9282a04a95e8f6530168180b351d835c722f3b2c3284d936608a3676a15218a349de49ae5b79cfcb4c7adfac811e05
13	1	312	\\x985ce1fad8d90d7948117c23fdaf47d2b095c995f4338cb6820f3f1471b9a302adcebf258775a585f480790a94eb9c6855be96d29a923765a7f0d7a6cad65402
14	1	176	\\x15f6280464bc43f80cf003eac47329142135320004de1391087e2805d612f012030051c78910a50034b68b5fdc8c19741f81c6d4bca2d76b9a1d76b2c593620a
15	1	55	\\xaf5f168ea6aad46bc6cfe8cf26ef19f7c87586cb75ae6bf68c57540d319cbc7c64f4aa129e7891650fadc12051784ec2321cde0a113cdcd5103b7411b276db05
16	1	84	\\x35881fae75f3f5048cdf283ff4c2d6b715b3e68e46bc713cd607e28c3407936a35e60d9499bba76f2b7329158353fbaeb4dd82c45c5e523d9204c934f0b17c00
17	1	347	\\x89247a526301277fb770cf4d1820a704667de3284e346086f624f7cf938bc06ed23bb16fe4a5160bfa6d3ce8b195d6ca63005717fbc34455b3538930b4e15c08
18	1	123	\\x79c331bd7a1ace5716bcfe6bcfae78646e196fe94bd196052037cd2c8ca15550a9190dd8540c211de6d21851d82b8841fbef2bf17699eebce6299ba5b7ad1e0b
19	1	153	\\xf0088de338997d0af0b1f27b8148351f96ae8cb2d6233299efbfbf28edeed353436061a1adba5802cece840b58899ad6e66b0bac82789f6091af672e54dc9e09
20	1	126	\\xa0de1bfd15d23a7ace90a6c2c76eac7dc4f1bb25104b5fed98cc77b6468cdd195503460c55773e23d9f972c5aa2a0247f6cd2196a8cb5b669f1ca23ebc4de602
21	1	30	\\x672c0c0f4dd2b0a069fcb6159a9210571832e6b6d914e2955a828c3694dea1776cc461fcab23f0ad46db44ae9b930a835b2214f6dfa7bdbd924d0b8b7709a50d
22	1	356	\\x66df4217695ab142f0fcdb13197f5326761e2e8786883a9fc134791133713549fba8b933818fb437d85c88409f9e2da25e9ce7c8b1734ce14e0b917e23fe6504
23	1	210	\\x65afddc2f11438ca3b726ab5587e71f0e4a801ec93309087ebeb61af02c48ea553b4946bf5b9883895b3b549ba45ad930b67b31a7c984d2195b073c06bf46908
24	1	261	\\x084347ffbafc4d5e2f0db29fe453753c884d5823bcf0fdcbd8beb35d6213e74ae4780a0dc607e232206537e7d99c81967628a6213d85cc48e338a78a80107204
25	1	336	\\x84523c6c17bc5a7bc8fa45ebe5c51f0e209a009e0fa129c7a8026b1bf472252eff9bb3203b96e01d745124da614fff733ddf9abf861fd73fe5ba5f77682dbc00
26	1	154	\\x93169a6c13f2ef7f22da456a4af787eaa119e0c0ce01ad4407a4072ca314b1c4d277d226fcbc4a1936e5bd4a27db90b1086212fde4479fac298e0e937242c708
27	1	242	\\x336c15ed07b2d611daaffd3545393af85fa579fc9dccda65124decadc88ae6ef0fb735df98fdd7c3e2c7ecb11b3aa5b6a53ba1cab83cfb915c9337603ccb3202
28	1	243	\\x7465e8f442b4fce372462a4e820063c46a31f87814950769af39b26a71dc153506817451f2083cd42a21329e3603cabd0f7d03db142379cbae23ba6dad37f201
29	1	333	\\x9b1de38cb2f565b56837fd1dcffb44b64a1e56ee78d3c013f0c008dc0bf21236e085c3813c6e52d8ae3390487074ee917321b1f8953e2368df291024440f540b
30	1	278	\\x2e9d2d65e15275ad77d6fe7e73342f29503b23b435a7804d9f0dac22278904efe473d59b04eafca7c8be6b848afac88644bff10b15c343156b930103b6f1ac0d
31	1	57	\\xda510e6d4a4d33cd0f35aebbcce66d48aa939dba07b6d780d29febda654d6cdf1d1adda013334a627b460c1e549e64f9e7c22297054055b0a8a6544ca4309505
32	1	60	\\xf966466d76a686e7579306f9361a6346051bc85ea04da3e451d789f29359a79be403e9bfcd2e166b2f143ca2824611ce5c6c7ef3c8db80e98940825202480206
33	1	14	\\x46a9ee329fbc377ceb8a174c2b9a71d2a7677b0cf6c1c93c8a7285dd7a1ee14cd9a3f0d9937835b5e337028efe9fce708c029ed125294de62ea585168a25be00
34	1	108	\\x05406cf72d8b1405b2240fa95a35407314685b67d3e8dbef921bfb4a51399638858f49a79ba5983de5d700450b8df8ee63cb1c6a624b3785bbd0b674c8ed730f
35	1	393	\\xafed254640571617e0ca0c7465984b8b973d58b24b290204f6813fb1c7d1a6772509fc4711268424c21f3c3194fa5de4296950837cfd38bebdab5a669859d10b
36	1	307	\\x31cb96d12c0358c6ce83c2309409513b886551dc4ea5ad674741969bb5cb93d5b53debe68fae38dc017a953a9a209768fd031de28e56a34d67463149d2cd2f02
37	1	390	\\x6b3f48263873d84e940134b17bfc65dced6ed6046b64ccd41e0359e5fa28c08d105bc9bdccb66fff70ab93c62aa609d5f20ad842a3a9396e8e23944c58b34802
38	1	419	\\xd13d4a4845257482757db9dafda1146d00956238d6644960e53a800ba21945f88b9fb7223405bb465c83c131ce86256be79221aba9ca790935d40d5d213e0405
39	1	408	\\xfd47b656fefbc85884ff18f47c290f2a50fb99f9a629cd627304ffdff4d29f3308ce2edfbd4b3e8b6a4e43ee8239e868974b2882195eb7bf068ddf28150e9006
40	1	220	\\xe34d2bdd4e195b888539598e237b0d9e8e7551ecc5843cd3a217206aa79b8092fa563b426e322e3cea3d244597a6b6ef38f5e1ace5565aba4c1a3e61aee6cb0e
41	1	133	\\xd60132e805679ac5e989f053815978ff85d3482793783464ad46cf2c2c2a6dd8a06f0365f563f9fdffc5ae1a974a6d31448b8c5f33a24a50f03a1aa27083a309
42	1	18	\\x0f49b5bfc7182591ada3a73abf66fdc970ec06e11ef7104b2e68ab02018869f326cdc44cb8b19486bf1baa5cfd07fc87031fbfc418a8c0acf6d103084c9d9406
43	1	247	\\xcbba0da1a33ee107a8e7fc61279af48fb87027fa0a5818bbbcb36720030f33d20cc3395a05a7827726a78b069cdee43520669e7516f4859062dda76f61743a04
44	1	34	\\xe15c8b6390d5d0f77991eb4028d3f216c3bad578dd9f88e0c425a4ed19d437d95be41628ad1a3ed4279295d2ecaee15e55585d0006b6d8794be68492d66ee207
45	1	369	\\x95fd6d074c39c4a1335fdeb9ceda76ba1c172b0c126c55a38b30dfde9b5f83397086194a23071e986090d9de2b4661dd4eb6acc98e09525f4b650c03ab87030f
46	1	385	\\x22b96e123c733a2f9f077403bf51a6593423856103d897b17ce919f922df0dd40267f05a3bdc57897c4b84f6e50fa16fb19134361415d38941ec629f5c6f0409
47	1	131	\\x175daf66860736bcc1103822281b320bdaf7607c06d9bfd8973db95750424dcd5f89d7bde742c6eb1b8e8f75909ec61a935c1b0796d23d826efbae391d4fc60c
48	1	46	\\x2273fa1fda85c895a9c2f2b4fd4b1f7d92a20ca7f3f8e78a9143ed3c81b0d26ca8acbc0c22d723f603225fb5a1180fe10f5694b3ce672f7b0c74f2c909738708
49	1	22	\\x30796656f3138397709fe4097c11d2885685e38ee685b5a45fa0ef427210e31af0f9c0700a763a6c861726b636dbeb6682c95d2c323d9bfd6344b2c9812f1c0b
50	1	259	\\x8b98f817a34e44032198468eb993a36f79055a8ebb20cbbef36f72e41bccbe029edb2825dced9fdfa7b0ba90ccbc6403e6ede96def6f86a8efedd67ffe6edc04
51	1	5	\\x9c1ea5259ba123dff3f50f31b33ccbda9ba808d0af9c235ba89dae10a08bc243f68b1256cb38719829b4d6337586eea3e53ca1a57e4ac71109a91a3c01d49106
52	1	134	\\xe2910bf240846e731f8ddcd59db06933d678d7712099983cf995bb3476158a4e02d5dd52e9e81ccc23360b578a8f0b7ac54e291445d3967038ca17e9b425980d
53	1	237	\\x60ef3781af190a8292bf3dd9647b7a335de807b1929c9eab08794b88a3787ea8058bf75b0fb214d1b668da7f84b55a486638c334db245eeb835f9eb891e5aa08
54	1	271	\\xda6061cae435a36f51a9989ba06e759a9b0c79c5e6cd60e9573ed9d455107c6038ba04287091b855493f4dbe2607f28e70b1decea6201d115188564b52f11f06
55	1	167	\\x33287327e579792ff9f0e4c674b1b76eb61e6e064e91bcbdf11c073d11efc6fa69f9ddc108b04c5b7bc76d720c5fc8a9e8f457c56fb5bd3da32ca2f742fa1a0e
56	1	105	\\xdedd57d16a71e734f9a5f9c04a76653a6800f09d22b114359307f2fa60caa2195d0ccf7e592bf5148e0dfac04c61f78d701472da527584c4366db3538c2dbd0f
57	1	318	\\x13f575cfcdf36a7293d3a776e1e259f1213d48d3eaea7991cfc76653976107980a1bdf95991c205baaff345fe3aa24f34d596bb0a88b73a6dde2f2a2c3f33d06
58	1	58	\\xb5f58d38cb8bc25ec7c1aa4eb8f5cff334facd5442065d59274c52fccac19048c937185bf85ffa24b6a0f2adaa779b9e79ce5dc2759a94931f8663af980f6301
59	1	231	\\x4c2adb043edf75ffe276cce7dd39baf88db6f25a1087d7c0ed6ab641baecf156c375c990c52f85acfa50402d6d1be7020e9eb6e02eb5e64936790a5e29110809
60	1	136	\\x0e6a91df35db035a77504ab4ee2378d36d2f424a2965ab2eeb792b7c5857ea20bdb7265338b8631b1db2c2880a789f6b234038b8463fe8bc63198dad79c0590c
61	1	398	\\x3ba3dca17eafbb3cb3826131673870d4bff582924442e69f18047d58249a0fa0b5f5ff635bb861521f52b5169efd576a10f3bb462289c633b4effc2ae2eb710d
62	1	82	\\xff80b9418f7774d20144d144c271a21d18669d92af660e53aa3eb18fc93c4d795b9f49659fa0d1f46e6f25c35fc77bf624fc15b813dc941daec0a72425aede07
63	1	189	\\x9a1fc0f4b5e0135ef3fdfc6431b4bd19a94368fd70bebad5e37b63a1db2444b13ef74c9edbb5e9c5596f76bb36d9c39bb8fb8d87810369a7d81ffadadc535a0e
64	1	218	\\xcadc5daf9c1a79e70bfcce960852b5546eda64affe82e22f800f4ba5fa305db767eb12450b4ed7823b11a1f1d93149846c39d5529dc8cbfb1b12deecaeb97201
65	1	89	\\x1736ef35c483e706e70f1bdb77df4c50e72803d8e143da00d7d46102742caaca3b489d0de4261c1c862ff6b232353f2e1119b10d9daeb870e59446f58b4ded05
66	1	174	\\x063dc663e8e4dac232d137db1a6cf2ee66e63fc939d62b13845cec579cdd35cdeab95bfdb403ddc5e5130ce8b65ec4a2232827fd97f469422804fc0bc1360c03
67	1	93	\\x1927e09aa2fb4b575187ccb964556946d6713130e7909485b948c04afba91763cdc98908cd77abdfa3130014bc96f922af275d888d9b02a7de2545f0f5e51f01
68	1	173	\\x7c9c641cdb4c0c82c343ade4dfd4b9f7a9b6cdebb7a4cf3ffe829d5d2eb75c69042938a2aaa1b810d7a0da9d32e41f4041216e9e45f30d3cc89ba86ea904070f
69	1	124	\\x7589f771d1d44f99fd673c43d7e69d93f3e4361864e74574eb5696e0d0d30e2d0977fe2df540617c86601d500e07ffb892108eef2dc288e719ad64f642a1c10c
70	1	183	\\xb34b06134868117c718402eee16d76860fcccd8a145d1ecfb9141fcda2e19c75735d669ac705c6543143fd79e2fc87373ef158bcbef3d9ded35b34536d378207
71	1	329	\\xb849e8c101406decad96c8c9d6ef39cd499385be23e7aa60e82195fb556d8cec105095a7e79c4a3f6571a9102d742b58ed18aa6de1bd31b1c96e4979ccccee01
72	1	219	\\xdd5fe3a484c081199046350ad43749286f5c98dc2e2b55b7d41b07ca82f3bf308fd06320a0e74a60251f5f5a6509093ff575632ef0bf8476d7b0adbad874c403
73	1	182	\\x4dcabaeb800387d0ecc65f210a9c94fb3e1aadbd68646508f35e763d7716f31adedae4d882bdd801efb2f826ca2d872ff8f0880eea66803e219f28c89b13c105
74	1	165	\\xfc4a3678dbd21dcb7237ca0dc74573bd8625e7a7e799e45ead020875d170bdfdca31f0112130800168b0843ab2ce6477e6967dfd47a7a45482050a278ecb9204
75	1	330	\\x0509d4c645e595b630706fdd7ec3bd4010698b533b02a739617ec0fc240e9b34e01416bd196bab9f2a3a9e048914c8736fa62ed7582f1bfda4da631aee0cd104
76	1	97	\\xe56f8214258b1e9e2a5bb1fcb278335df499dadf993117a54d4aa0372ccb83b8769dd51795c442f627cb369d7be2192c69bfcc8200f2f17b32f424c373a44f01
77	1	80	\\x7e9106fde1705523ebdb626afaa6845b1342597f34ca99d59d21bcfbc405e86ec5ef71be26d3cbb8392345451d48642a8f674460a4b1db6d1e2fdd9668210606
78	1	301	\\xef014a0019e191fe03f6ade89bfcbbfbcc6e7197f2ced131ffaf9120141009770b60e5600dd8923f87525390ba0b64b8e0036f6faba8e04825642e0aa7a6fd05
79	1	32	\\xad3674c95884d5c31c407363fe4accd49e5bde5558fa5f0d4b8969180e222d2ba7c43c19e93d45c041b08149622618aae418898a35a313d5331393bdc1bd2906
80	1	238	\\xc2b0aeffe6385a28a4fd660d5093dd3d87c54a858d9e0b8f6f6d19bf8c1ae0f082124dd8abd00b94714c99260f729fa20bbb5e8a1e3253a941ab1c2efee3ce0d
81	1	214	\\x9606b2acac516f61d2ef17dc6fd112ba84b406ea2610a9c46a9e1ba88b6dcc77ca23c40f9abdd575b1cea2cc099ac54aae73a4ba9a601644a2124c6a35e0d203
82	1	402	\\xcd99ddd3cfc424a880132e861614b85f23932835ada6f07ca3b2f957b424e3e7566d241e7d3376d9a0805d2b1bca833d5ad1b7281c8ad04cae6ccb612b379f03
83	1	276	\\x1171f545aacdb13589d0ef99ab177ba9fb9d8765363473ad812542d4a29656a125bc15f8bea137842be01ed2f19cd9c2bae3d9bdf9bfa2ef28b9fd1d2bffb106
84	1	12	\\x5a2f306775610104b564de04ecc69a41a961969fc6ea1a7045570f935a4cabc5fcc50005408c67df610c9dac1febde8ea6a7a95b17b795dfc94d463f6d0e6c02
85	1	190	\\xc226de2c75b7b84940b0281954ab004f3c499acb90cee04122c6e14862e50e9a719991c9b9be77a3b300462e25e5505401dd5e7d0ea761ad07c5942eb2a1a50b
86	1	383	\\x8a97f95ded17ed63e76e1d1d913a59ff79580fd18fbdd9aaa059fdc5071f7d4b5adf76706540a4953c9f42500db08d914d70923a89c00fe9651689aa58c80b07
87	1	341	\\x4cbbba04c2322e99f9427ba36c509ada68d9bfb26ce5b3405347744b45b28db292174ab92d35623f6db194138ba8e355e9eb7c64bca5ca10c1946e93dff9f805
88	1	380	\\xea58bdf05250f0fa91f69893b2843b2fe6411b6e8d93ac18b8ca94c8ca16fd57087cc442e53aadc7bf8aafff347eb855b55394b230b22f38a195caf97e423f03
89	1	372	\\x6233ccfcf3f816baad49eae201a71bae848a0e6a7694d5ffcf016abe84fce99460d51ccfe6cc72ab7f894da8172ee2d38a5dcf2fe59fdcb94adcf0bf50243901
90	1	332	\\xbb474fd5f0ea6c9e9869fdc776457e7c8736242d4c1bc04110b72701b3a138a023d0021da2220965d0563c31880a3e6a0da8031b51243d91d96824e265b84103
91	1	216	\\x6b8f1bd9775c2c38cebb8f989d850034a92b69c8542ee1a65382b9838cbecf35361716be1ec0bff79be27f4f74b4ed96903819adb21f3012dbe6e998165b1f01
92	1	28	\\x594c79523951a80aefd94660b5bea0d98adcee9dc2d0a93ffc5097c5e9352cf2d2717b318dfcc2d2efb927b25412d2264f5c7a1b647a052ab917dd35f8449c0f
93	1	226	\\xf76f5bc34acf337d260c2a0dc155b010df9f24d1141d772faa5156941b377da8697434e17e3b08ed21f2f7659b8df6fe38f851b568af0418c83852c9b40ceb07
94	1	338	\\xab5e16faa586ddd88fff196b19331339d4cb929b51bcbf6ac7e5f6572517745a6289cc42ccaeb12bcab65934cf02b78c2cb0f36ed62bdeec2e5a277fcb35de09
95	1	404	\\xadbaf4d720ce301fe06213794bd69044b8b93527ee72c2a818712ed48b2922dafa3856e5cac619e27aa7e153061018cd9bd79560098819a6eeeef1c83ec3390e
96	1	172	\\x4e95e371f0d5f748a98b88ba416357f7146e776d21a7144024c767a2b57f511ce062231de5a7e3d50afe60cdb19f4a1ff9174fabb06cb0d191b30be2ac02490f
97	1	354	\\x20d3fd83715d17b27d79160e3a1b2a5d532c45d6d26c9a78da29b288ad4f97c91714377b6bba012a4554595b456bddedd757929326ecf677ad30ba7fc9cac10a
98	1	397	\\xa49f788a672803f6d0d84e2bf10e53b2f21c35f1fdbfcd02c1f0ea353bd79024fd6eb9be389f1589462281c1080436f699ad244e8dc41f8762a27d8d8f8a4e0f
99	1	262	\\x7c55e02150813ca45f13b018a1653b4b2054f6e394561c0270a5a34bf42e23f2d8194155994706accc2daa380d26f6ea126ac7c286ffdbd3581ad60793293606
100	1	56	\\xb8b3713099e479e06322cdb24ff1298fa567c5be8ef32183575ab25073cb47a1f409376f8391cc42c6d175bb72dcd951f124b9d5ce9c42d5d29f4dbe55569009
101	1	416	\\x6efe9948c281748f6922a8e3753316eec794b63aba5cb9225510b11255c64f04d0091c614215a1b10767d124b5eb98b8af8f51abdb8efa817c79a44f85b7ed02
102	1	171	\\x36ccd399513e841960ab1e56f04d1fe1e16f786cc22239ff232b8dce416cb3dee5181459ac272a82bc8f6ace4698b4e0b2fd1704231f9bf8e190c4dd11034c09
103	1	297	\\x64dff11bd5875137c854c14e6ea4190dc9a55bf2f2d528b9ed4dd92c788e575fb1b8f6ce83af223040352e6faf74ddc805257287ae828a6006ec60353fa92907
104	1	234	\\x2b30db29749b48074b45b8e9b4b0a3adfa49def9478a2974afa3c057e152b597d86ca4924add6e183dc99183789a496c4d1bc8bfcf74c7e73ba07505aac8400e
105	1	257	\\xde5c83b868ff8b1f9026a019f953ee8af8c7e7c0fb7a1f8d2499254196b2d06aca5d544aa91f6ff5952c7355ac0b739c80c0276c17f887072e35148c3df99f03
106	1	212	\\x7617c2c648aa225f14b208d510ff91a90c74e59335d75229023692b466325df78223bb1c95c390a7a689a58a86d27d2a9390f22bd1f6d2faed7b3a4f59df1304
107	1	160	\\xbaffc1e6aaa0c363488a252dd3c835ba8c36e21d81e94c816358d80f944cbbe2c9e4a67c178c539ba06e67c121aac8c49e0f2bc8c3531ea62472b72276af750b
108	1	199	\\xe547e80f92ae5be109926d408993bf0817ddd4d94cc06a9e021137a03b176407931c9457ca51b11cc816a86e13afda021fa0676eecdcb96c007f08cf829bfc0c
109	1	228	\\xb38860d18710edffefe9a4ac4058f83c9b620bb7fc6277605181d498457f23aed948dd336509c011a7144cc0890a0fa0bb2c5d57917670c18b43179704f0650e
110	1	141	\\x78046f142423880a09ce4af74f89bb8e9d7175fcf8920c91bc56b502099f171e27ff62441747886e8b1f737ddd82a3dbae96445064e88759cd425db05f65dd0d
111	1	147	\\x5af5e6dc9c3a6e291cfd0175be3a9cfcfc088b46be26fc25ac94c2854325c8d46e8da506fb19fec4d319c8d76b6467995f83637e6359fa5e227a707f5b275c08
112	1	163	\\x23d23bc2bdf15a7e3f39b66c10166d18ec3eaab0be1263b27be48f7fe6173d007ccb2534c5efbccf5fcb96d02955ba6786f2abffb2c4853e1fc0dcddbbbfb001
113	1	74	\\x5919155a37ab8a3e62eda642f83942fc4f9f7b567a84a01087f1071585d3a2013bf4b7ec3dbba37a9ab151635c9f75ca7964a99ce815c510ac917fa1d9497704
114	1	229	\\xfb8ca184d8cd39408f305300d9be9212310c4cd3886293c12aa529f64379f2633a078c59882072ac49d4cd22442416e6aafa5f0d665ad700bbc56fc7ba56d705
115	1	308	\\xe45c14ff2c35f9d8c7f22dfd7486e49f1568f75d1d3ac79e06b30ca49521bfb4b520bc21cd85abc2010a9318c2bfbfb7ad4ec4fc31b91b6e049b62941975960a
116	1	52	\\xbe94a226e6a0b477cf5e8fa3a9385698e7989de7cd868740230a610f2fa1f8ab84963dbdb4e417b17033acdaa0f398264d4fdc33c7e1c29b41fa7efd1582b802
117	1	394	\\x85a6fe023c769ac43b6a78da67b72e82a50a9cc5303eafe90109dd576c4cafd60c37e2e8e27a8d11f4db073695b68f6a923b3291534f56d38de797fa2471ee00
118	1	361	\\x8da3385540601f7d8089513033c15ee999e1b7aa06b5ed058d74267a3e8d710f4d1c8c31604eb5528bef0e9f42cc09b33c2c5455851148e3083b98c5d5bbbb0b
119	1	193	\\x7b0e52ea6e11a41f94fbca0eed839b3173254ae28a08e6edb5e1d2a6e982104afe6645975c53a6643d08fd0e72d1a7d30c6e13095c6e81d3b3364efdd351a306
120	1	144	\\x84bff27427490d56374e58af07491db9c88b04d602f39ce87288ffa5a06f9eacb4eac23d886145b39ff3db4d3b897efa1b9caca699b83fe17cb5cf6ca2beae08
121	1	112	\\xb4ca492c0834dc2cf43d0831fab327d392eb3a251aac26a72b2bf593ee0395745b3f7ff4a90fe4ba2e4ba7d05d83201f0b69a943d9263740f06dacf07d15fd08
122	1	345	\\x8e0bf637b98029fc98c4498df34140fc1c3447519623139dc54cadf31ae640690410c9d68378415a5b31be631a1c4d556ca00fcbb5d12a7a6112c472adf23a01
123	1	249	\\xeaa1ff8b6a9443ae0f7fd9c50f3c0496c8d56deaf70bb0b2da513d573af21e7cee8ae88d572099e0c8c472f45827d64cc5a49b690d3ab472ce6594285448460f
124	1	200	\\xacd82efa6545dc827e9fd616a58907cda4872821712567d50ebcd33f7f26a389dd01253198bb9c06ae56604c6906cb52131adb039cc44c2a3f4d1ac76b775d01
125	1	381	\\xc21d1378be10e2a5e3600894be3e51196dc42093dbdacf934c6a47c72e806ce8e78d40f2ecfb7eb7e3b0f01b5c34712f7fde5027d9ad2aac788426bc7de9b50a
126	1	164	\\x5e6b179e9f41f79b450fc3871c129f2cd08bf2b5a2f1684149b5d29fd32c079cad1052d2538070122a37356e9cdd1d4d4112441b520a2d2e9b5d6668d938e20a
127	1	217	\\xae2f91804f87444c16519c793468bcbd66887ad4e2a642b55640fe5e3d71bb73d82faa6f74024aaad5c05e0af4efb305e089b53c56893f2c2f1e72f56ce9580e
128	1	270	\\xd24cc30f2bef42032fda65debc6d8e31173b9a7e5c733549212e7c2e2a176d3ba30f1d9e224bd2f078597f80dc2d264f378e3e73c4ad28b997e91015fa96b805
129	1	403	\\x4a856e1d7a6cbe7a1dd4d53571842ca6a1606ac853b94b4c5f9bf41fa76eb31bc0d42f6f62c8b12c9e1cdcf20c135845ebc82ca5a6962f36b855609112f10908
130	1	110	\\x41d6533053e2bc7460be4dcc4b13b6fd03881afe121af420b56a502ec97edb174b99f5d9aa5c8852236cbb328e5c9c5f166a23acf0decd58c994252daf6b190a
131	1	233	\\xdcf02a5e4ebf34beb3a17b245bdfa61e078531b1b3e5fde0337e0d1a62bfb9200a0be9d46c0523f54f07df03202573ba2bec8f2b8de5d20d2267cf12e5d28c0e
132	1	8	\\xdf7ea372340a4a2c266186863fd9386df5252814aed3c3e81f278b530afdb071b3b5d306d3a6b1a31c50fff1cab6d99a5d5cb556229a3238343f749b073ba605
133	1	191	\\xb43b4dd29de55a2778aafe9a23afc86dd454eb8642a9ff845da18d8925234a15ec9633b4f683a567f15fdab31b2fbfe88d831cdbab52924fade56f80a6cb7503
134	1	13	\\xbf7b9827e0bb43426ac7e886ee9b35dd1af2a923824827478cbf4eb6e151c75157de6cb82fdbdd448bc1bcd6238c4dbf87fb60cf86cf32a94b9e91c59712490c
135	1	377	\\xcea90cb5a930433fcb10e369d6650c6009bd3bd58655de8c1f4b43107b71824e562fbe7ddf91c9c80767d6b0bc8bd7fc265da5b2891c17fd07923a23680d070b
136	1	149	\\x44ad48e273f7716c6b9e4caaa8511216c977130378d4a59f94563ac60243a683ba20db0031764dd89f5b5ea423d9147caa89524d2db54fb3de6d3d0a79564509
137	1	367	\\xc530d9160297b5acf44404215aef13e1524399b4c33c91511de96e59780d9d172cec44f7f626ac559bb44698fdc2af0a477229380383be5f7b833e55e67eb306
138	1	314	\\x0931a4b7fce32305c593ce0361cbca2fa2587d9da86e97bb481182f37c0ad00f2158b207dfdb7f3320f46001304d7fe71db665aa31fe129dbf4081f76998ef07
139	1	85	\\xe0536def7b51ed4d06476a73a9647453001f996623c6781b5ad8433e471b479068cd689ae79762bf3a80c300ac3ac3d2b0679f4ca88edbff3a266adfd268d50e
140	1	340	\\x16280971cc3a78e0cc2f1db24ae4a3b4ab1862723b4fa2735111084dad40933c28848a57fe1b91cbb530c3b98a9f910b89ce7a540d7b58aa3535267335a52001
141	1	48	\\xf7ce6f739f4b26c805bbb8c80259063be48fc43259da7c1fde59f8b1d643eac4f3ca78a1868877ac595d1c2c01ea1f91683d9ef6d8de8c37ccf085db04ff1900
142	1	279	\\x46e4442c9d59d9762535468f5d649566d00c74c9773a609ab019c02372364116aaf742058b977effa74802bc3ec90a820bc98c3b8243516bff0e1d4c60f28201
143	1	298	\\x9c4305675825c03361755e405253d7c48456a2c5c300346d6d0fe260b383922e5ad7d1a837fa19df73921eb827ee8c219cf613b7b698bd632a89d15e8d6f7408
144	1	286	\\x04160106554f4796db69da525c3b133bba4765e4ddc89d96c2630256fc64d4228fd541a5bb22c035598c82c717bcd47e7e2554de300fdfcaae7fd752a0cfdd0e
145	1	159	\\x09d286f213c6c745ffefd8710942a5ccf65d1cd8b2bb216278002ab90c25f583568a02604666d12a6c1f1217bba4c1001bbe1f28abf65a94e045bc115c4fb400
146	1	348	\\x62297aaae982233f22de8b7cc0cfbf61f3d16ee8fe8a7be565e784f62eea762f403a517a1f1f230b8a60485454349750e8fc575f709663989908b1a3b4357f0a
147	1	146	\\x84e6fce4f90a3936bd4adc34ed00b9ed50bc94751e96e3a9091ccd00cc081970065ad8811aacc45f5a6cc15010c847e11260d2c109415b16041cf3b8437cae0c
148	1	107	\\x3b9c54351491b46da5ad9e8ff64bcf2dd261bffdef3742855ee613eee06e40f5ccc688035b855b427b8d68d1badd02d53b47a910e781f355a72559c0f2dcce0c
149	1	303	\\xfed9c9aeb3af17f03f51375cf0bfbf5fa23600d988471545101b9ad0c8bbe70bd83f539b95022ca1fba31f8abb67b728024b8373a03f7e8df2df0569179a940d
150	1	10	\\x06ead18f7538f2d95228b0e0f99cdf2919b0f8efdad86b2aacdb6ec886452d9c26ec51ba1c0900d326e7b5a94ed89be0139af2e9d01ddb3b8d4ce3beba371407
151	1	326	\\x694d3d655072192a3774c4e334e8a028e10313c34a324da757c294bb84cdaa80c9db4e6bf151aa435210d041c4937a3c0a209bdbb6f62db95c009c2c4d0f8105
152	1	359	\\x82fba74f2dacf7051d778a29eed187990a0764189fd602d67d8bf15adf079f9619b9d1c71ecb8bf071d45a4a0a24fb46c8f90b2932588aada6f7a62f5eb4e203
153	1	157	\\x7a8dcec0910829e8aa6c6ff9a870c65014e4a7948ebbc292dde3d302a2dca7e02544ce961d56daacc8ae428e1ab90bd0ac1160daed929f09ff6c5e75030df409
154	1	25	\\xfa136b108b92d13fa47243ff92897a1308aab4d0bec966b57b98e2216541ae700428cd23edf6c7b4ef4767b21f3df7596a709814aabadb5dd35812eeaad60700
155	1	187	\\xe3b080bb1227cf39358b198ec62d70d2fd2f563c24dcc63928b0891c1085202d87cde037449b3dea7b33a7c8fad1d29b27594c947fc81e74864d0b6326206f02
156	1	235	\\x56522fdd9ae2c8b02f6f173ea80531955fbdf7076e5b3c104015c03cf42d4d50bcab823744074fcd7a8b74a527e2bb0e98729ee25c152125af0375607688460c
157	1	280	\\x51863031f527dfd66ed97a382854e35d9e6e85c6fc6ec60b07f231ce991234784a74532c463e721cf977abf4363e402c978d21e4681a1d40ba949f498b1f420f
158	1	370	\\x83f71e8b5c694585ca571c2b441d2b7aa4bc8fd380284a3b7bb6e0775dd218d1f15a8b9d62c02dad69a0b01a87807c967dcd578a18f827b0a27d18a4bd7fcb04
159	1	327	\\x4a275527f16a48d11ae3a63d37e22703b3ee08f6b88db32f8b782731215cd92a64ea2372fb6f3ccc18042ec0dc3c678b706c89d10948257cdecd2ca8b1e8360e
160	1	392	\\x83a46b3cb5fec150660c13cb5c5942effb017db8a35ca6e7e14fe4b901b12c83593a6f9dc15fbcd9e401478b87a03057c3c8b17b40efb4ba322dfef2e90e5604
161	1	156	\\x8f78288b42088ad0e872b39c2ab8e91c74a822216f005e6a55b6000f1f7b1e90ef8e6cbc59b1b5beedb27044adee7e6b26aebb6549a9accdbbd4b2a76fbbbc01
162	1	349	\\x00ff493aa81b539ab5225a814816736d38c5921f2e846afdc80381ab275ec4a58d331694094b780430e355d5dac2013a9309e17c1b80433f6a56fa141ac91804
163	1	128	\\x3bdd73018b5f38140d5663c8408f5fdd42db905f1a6e7941af9f08b69dd826b35c286e6bc84dd0e18be7341d0d37cc0fd72fe445153caac1ab5da8c35d117402
164	1	94	\\x1fd2d1f015577bafa1f01b6d367aa99c1d75599835beaa8f74b31367281b84da3e6c2cf4082ffa670039b0c0d413db73d018d66327f2ef0ef7c7e54e9bc85d0b
165	1	7	\\xed2937cfecc540e6b18d7586349fb22be96cc6f44b99e2a37d07dd321d7a8788b8466fa750e42f38d4241264abe75b9b2f188bfe6a05fdb072da06bbab5f860e
166	1	150	\\x9928cbe249a69c91c91afe197ae90fb2e5ecf66db7b7421f5b317330cdb04d33693c501aa00432e656ac9222610d17939d97ca169f18016e9294e29fa5b57d0d
167	1	138	\\xd717ba4b088481be1184565283557d1b1fc5145657b343b0a2baa46d2d8dbac63cdcd96e936a8eae4e69c7a6c0a371e5e1ba35234b5455f904ebce7a7391ea0d
168	1	246	\\x9d7b6284862acd4aca2bf15817f49561f5e4c11460b02e5b25ac82bd80e5f7e6741be07f4dd646e063ad7b76f721aba8bc5c1c910ecebfb0cadf2d77f978b407
169	1	151	\\x22e2a53b9d81712571b654980c3ad51f3f67d0445076fe52ff395a8bd7a6e18d309965b13a2ee3c72b451e5c73da7e3bb4c41ea27b1cc007de2415b2e927e40a
170	1	384	\\x9bdb9d3ea1977cc68f14a72811a85d7f7a839b645b8a8f9b46ac9f91e0a38affd03b056ac8b27fb1dfed9aeb4b76f086be0a8d398d2c1ac109767b372a336e06
171	1	73	\\xf4945657e7b979fb5a4cbe54c150c24fd5afcf0d44efd7f1cf4aed559f2a48fbc663aadea65314919b6bff58abc28c29ed6caa0e07b218e8896a7668ffdcd104
172	1	409	\\x309d183a5c6031348b8c9072fa4776c9317042b7c8e12fdf422c24cedf4fcbcb458653e51bd5285725c288f8348b53fee21d4358d15f0d8823c73bd876d2190d
173	1	41	\\x2e5e366da7139ca3777be44bee33b94bcd6cebd258ae688a8eb7770b2d8cbeae7697c205bd5edbc4a79b2626047ef726c6569372fe72595109f1d5d5e7795300
174	1	250	\\xcc8483534b42c8e997b615f72cff9876159fc2aa79cf8addf9625faf195bc413a92fbabcc09f1685ae409400b37d95e0d783a932bcba44233bc884dc7582840c
175	1	285	\\x44f4a4f34e98897e7f23d53b1a642079c98b05965b9e09a59ac11306136641afbafe2dfce6506df96e87fe15d2d6fb90fc024c7f55d2f8a95ab1eb6a153c870b
176	1	339	\\x00de7dff429e85db3b63cdf4bd46fab588847ae400d5d2b46b6b5ca3f427f9f5bb439b3785f285c1f4ce988a4f7bc8f08089846adaa2e01aee7c3df81d5b1909
177	1	245	\\xa51d3d7e01a6be12306831fa1a1504e1f31fc8b7b295f00e6df126dc01b94b91c2a595ba34b75144563005cbccbd366968a9aa5622e5f470dcbaf29ecf2c6800
178	1	290	\\xaa9fdd7d29deaed9f01f2e31b663b814d34ac878826219140a4232c19d4e7058fc69918ea7b02151c7441213bcab38a9993ea83bf920ea0ef2e675c36fa00805
179	1	251	\\xcba9df4a706aa0a12297a2b90f3ff18aaf2f8218a1bb4ee3bbbe153fb0068002252aa9e8d4597b6edb6ad8f6c8f8f6ae38fcaf8d818178e80d6164656951a304
180	1	412	\\x64915e9d940ce47e5d94ce3f96d9559aa37d6687b4dcce4e8f5942873e061e5cda13beb56e63f5394ac5293ea6a2b2ac376293e88748201558567fc7178fc808
181	1	118	\\xc207d75b0273386af4081feaf17f95b71ba2dad119bb19b4bd9cccb2b82cc5d3f477d92a6687cc127d896aa365110273539dd5175412c6f4d7a0db7846fb4d03
182	1	405	\\xe2b6c4dc4c761e249ce7bdb053b6896a4342f8c0257d6d6d0dad1bb8992551dab729f762677299733ced175b658b24650c225c2a2bd2cab641c9d70faba8c706
183	1	158	\\x02932149641fc07ddfff0cb248181b443ede577189d05449b865f035b08718ba74944d1dc4eb120f3dafbd44ad583d40185f15929acdb48a197dde8bfab6c403
184	1	399	\\xb219fe08b831d4c935f1c2ee76c3dc057eec3e84e8b47049aaa6a3561d8350741eaa56460980e456467a22bff986e8371365b35cc9725dea2f54be424bd99800
185	1	169	\\x71ffad7dcb19228d2f7e5670428421cf60ef0abd1a9009a444cd1ceb2bf48b3ec0aced76d2893c4d226048888b04f202cb00f36d566f749343c796206de19806
186	1	208	\\x07848cac3b7f527dec1606e9873f245c26758a3b41fe51c9088e0349bcc43b8537cb292f17b91b5bd8eb900190fff3d18e7b7a4d328131935e7d00ad91452d02
187	1	100	\\x7dfe3f49eab215a771b7512a7be91e7187387415146bf53b952df3c91be0f4ae7e172bc5a25e07f39ee7b15b1587fa479b0e68d2f3c904c84e1d2aefb4ff150e
188	1	104	\\x97ce0914cbd663d7596bb94f4cd22fc855f04d0abe4cbe18961e66bb0f93888bc9e4874f53e244f155ae0fe8b8e24a9cf62e2465cb0e0eb158b5cd8b57172803
189	1	324	\\xe8df0a6f467b26b5dd9f35b59fad12ad51a6fcb63720ec266cc967dc37b895db60f572a1c3a3d1c8cac13acd157bf01175501c7d53daaacf5a66625db355100d
190	1	140	\\x2e8e81641d32e3a9be6e312116e426d6c48966dfaae38715b9cf1061a7e545c0eb8160210642035a417b1dcf505e74401e423e3338f180e0c255055b9bbc9d0d
191	1	42	\\xc3beb19ef15a1f8731b5caad672e6216bbfa8b1591bd6e13ec91ab19da94faf355e9343cebaf38948c543dfbcfbe1929e4ef0d041c1d410ff57e77368f172906
192	1	355	\\x5b8a53aceed1a49d0ceab6db1c8e627b86495a828a9bf6e45e71d4895a2dd0180d6f37ab43e93a986ba5f051daa65a731a95298f9b2dc31c46770009f865930d
193	1	194	\\x509c4e10e344108ee1fe518a04a200d31abaf488ab7164d370bc8d6b7af8c75c0a99d59a3a7136d60f882edd481a3bc1a485c8f36d0e1d5188dcf938beaa880e
194	1	207	\\xadeaded628240e647a326cdb3c01b23be9f8e0458b96e940db1f64f4efcd02fe3395932fdbd3b1ecd95381abf734472f65d57d8f0186d6ff4589c56af4ce6a00
195	1	152	\\x6f13cdfb5e07e8904f51b298cb915a0332fce93aa84cf789c4b28f911fe216d635a387576a393b8262de6b2a2cd766111b4648fd4a1a42d7b32d8772338f3f0d
196	1	117	\\x949eec3bbc01ce1103e811c436bbe6a86b0c8c27a832cdb57c7585c9ddc6995ca0b410d657434d00dc149b01c7ef5ade167034ccaa63e4de9411d553e973d109
197	1	273	\\x8603895e043408a0ee55edfd8d2f1c69936a36b528b90fea5ad0b4972255507bc2ff024a8811101ab294c80dfc9996bcc37343443777e08d9863ed38d90b8706
198	1	4	\\xfd5df9e9fb1ffd7ce64144afaa8d48260559094b98b647d9ca1546fad28489d1f3077cfeccc2a0b35ab305a9f5eb32110b284e02d61aad20b449bc0e7dfe2308
199	1	268	\\x1eb330c504459d11782838f87a2a7102b8d345c69b15ec651072599c777d29af1eb1f418a5d3596b2a18ddf8826724473231b741affeb853d1ed11457454c207
200	1	115	\\x1ae9a928a64d6b534e6bc93cbbb74e17be5af49b2bf9630e9c2faa3db5680177617af3fe4668803e049a061ce158a8c2d3630a0c4e1fe5f6d83954080d479008
201	1	252	\\x1ebbbf58e49e964ba4802c196c109112d571bdbacf4d88399056ee21d23476a7983208ef358dc2c706c0235123aa627b8391f8eb6c252e1ac2d7d90b4b353702
202	1	230	\\xf296198d3ed3d2f66a94ac0567ed47448e5b3b3cfc05e08ebb206a19ee885c0ed96ba84377f8b0a5db77d20956068ef8aa92ad801957013ec5187e0f0dccee0d
203	1	116	\\xe7d1ee1fa68f219caf982709ebc4d421c399b85bd6210b32b375d1da48bc82d8d6749205242ddfb60210750b5fdbbad206633b9c918a05952708f02e9bb6d703
204	1	70	\\x16fecb923d1746c023c3973c05e3484c8d5d076f3750ce32b5d401587e4e43c14e7f0fa2c58fc571a46ecd726b8556cb5195beeb5ca054745483627c879ac102
205	1	305	\\xae7c4179913eb03d1180b8676238f6fb9abe7f30bccfb440b8a3eff183e18ccd6d4a119d7e924b968423cca2fe73c52a5f9419009c795f6f9607320f0d62ea09
206	1	155	\\x82e71629db53aa9a5f6cbac7b2e870fcad67825d651ffb99a8cc980f1de172bca87f221963f36350060f0d2d927bc1c262fa062909b218149601fd8c8a1bf50c
207	1	323	\\xea1a7f9bbdd989f39052bc74f1c9312ceb6be2bb0dd7973849b00f050abc76b0d37fdc33e4072c7e7accd3b634fa81868651216199d6bd9637a898bf9b068206
208	1	417	\\xeb0c52cc217ccb8632cb009f04d8cf8ce2d237da71246fd0e5ee1790984654674d39933c81c19b0c9162af140e5a74b557b570d0213c9822a958e6c98cb7ee06
209	1	401	\\xe3c69a11b79ec85dea12376ab102c74b064e025212792bc9b5400fdd3d1bfece77db0b42f2cdea75c3ba8655bd07d06a33ca122f9f9655adcb17dccf4fb09503
210	1	422	\\x7b1fd82341fd538604d35d0d3aa4ab1e72f753faa0af5a315d39a9af512b986e374fcc2324f35e353e1a7a5def7d8a24ae4664cffcfe71de836ef9431895ce02
211	1	299	\\x1402dceb372c4ea4aa8fb0863c1a704c9a320be6654d79f2c902eb585405c4240d6be9d5cfb434e305df8c6149725d0fe0bdf577f6cb48dd3af7008777a33103
212	1	302	\\xd402aa6a9ae70004b0e2daa50c431db7ff1d513162bbf4c43d43257ca7d61dc96f74a263802a4c9d9ceecccee4d00be0d8779ef23479d553731e9ddad99f3801
213	1	27	\\xc549d20fdb360e0230f512ba61d491428cf514205c8fcd98807577b7d30c6be4115821eddd4227ef684bde1990e03b20f123568d36fc797a1976550cd2c8a80f
214	1	26	\\x3cd590834a706f9425b5716d1a714c3cb7393337311cdf3c5ce1ee15d09c3364377449c1a2acc1c1bac469a797e89f23d1674a51b83fbc43058b13672a526f07
215	1	162	\\x9699a4ab38225339e5c229dd92e2597fd326b36376fbbd8c235e871d21fa933b19ed20b48aa87169cc9ca76f861ec491bcae6767d4932f60c1b36c4eee92fd0d
216	1	306	\\xedc570c04f0bafe82b14ac28a069776cdccc0fbbc76e84d618977efb00b0fd3245c5e0d753e65db6b300157c3e5794f0f9cc68a75cd748720eb74f2218c92903
217	1	40	\\x48606fb2128a68afdf3f81820ef29186eccb56ba598bd7188a3b7820335f98ff40b9baf988ace01a3f51365f5ea5c813246e63fb3178224bcfa39e51a667250b
218	1	414	\\xd783b2f4ceb53c52649f3903e5ae171502e78c9887d4fb95d2e224c8eeb90e6887623916235cdcbb6bf5a434e4c30382353b418411ba21eb1683437dc469510d
219	1	161	\\xd707aa8519e9da8093b910f2b3c4bbb6b26ba461f28559b4e32d45babd6b7a517329da57e119fe0046f9a3cb12181657c0217370be816bbc7d46f10ebd39e205
220	1	363	\\x42199a25084df5594f507a8057d2c02b493ee43b889abdf15d8ec66f4926b0888f92e75a5052614b6495bbb7fc981046188351926891c4da192244cdf0668906
221	1	421	\\x0988ea286926537cca7a213742714cacde9ec99f74fe3670b2f26155093d4b7e7295feaba9bf1de6d7ddf3823dcb5eea27ca1b1ca0194e17d0278a00cad64201
222	1	78	\\xc0dd89dcf08e584f99c5826704b46cc7c0ef05b2a2e4843c99ab2318ab10490a76cc2ce6cf4503a1d3d4ce5f301c7ef6cdc22f7ea8f8e37ea19e279251a10c07
223	1	248	\\xaba526a6e0560d9e93f25e862f257e29d9acfa14dd18ea894d81504f275263a4000e99562421e2523895ed46dd0e30842751f1b7156fa0facfa0390eff22cb05
224	1	309	\\x0c7def45281ffc730c3a50a85a81acbaf444a2fcd69266dc87f4694ceb473653ea7ac9f96f854501a3d6ebb3f9f0992315e3236955f520f24bcc813983db5605
225	1	260	\\x5d0fcb2749b00499265a28433756919f4d53872070e4de32f053407f389ece5cb5cc63d4a7b351792ca5619ab98c97f54d45575c5bd094ba7de8cd3dfdee440a
226	1	61	\\x793ace3ffce404343919fa450510d562b649b8d3402297a2855996518e06dead896e70e8f6e7f44505292086db44ab1f99e1464dd7c0e86da05b66c0d44c460d
227	1	92	\\x8d8f3aeadf25cf14e3308c38ce9466a8dedbe508b07a917b3d763c4bb2561e39898d8dc386a0720a89efb103a3e48026e1232e41b9db5c3e30f774ceed0d4b0b
228	1	310	\\x7bd91bdb01d76d569a2758e5c2f623f5d9cf4e78364c0d0588f8c63c0bab14dd0b1228ec55782e2e5d174844d375c773c5c4e86ca0fc22acb327108687bbff03
229	1	90	\\x2e5f19d6345f43fd2e745b1f4cf70de5bb1f1ff82ce57f7634edbba2aaec20a7c47870cb49eec53f8d467aa0a03d2e3a40d55e3b75949c805869b65327b6ce02
230	1	59	\\x73f42b7082e7de48a5876d1302ee5c33217eb6a068d6f20e327290a055b13db9babe785bfb0d960984bc4c21e90fe89ec8bfe0d19d43b922ee8ad0a2e6da430a
231	1	195	\\x0692d771357dbe9b1b9ea37fd8143b78d90a43041eba5b318689cd83f52c0f17e0e09c3197d7249ed253e3aae375bc4da3d540171de96fa313cd9aba3160ea05
232	1	23	\\x7ee956659e17e0fa5f35a05e7d7fefb0b6bc91303849bb0fac5c4257cc217ad3161ec30bd51fd1b3d8cafbe4dd946c4d86be5ec906567f592c0c1b24df62f20d
233	1	35	\\x88a634533660f2464ae40d3d747f21dc5f8417f0a9b8fd606cdb2551a868e13a0755ee17304fc1f4008dbd2f4a145b08fb0c330fa82fe63800b6a522a75aa60e
234	1	16	\\x89f0b02e1731a0cc3448dbb5d7798aa20e76ddeb6bfe6c8c1c4621275b830c364e313f5164534cfe6e6e8ab527d0784d0626399feb7824cc40b66f2c2a70d908
235	1	121	\\x4ae40be3b42e89b16bda12063a12a2e751aff045b7879594cfa6e88da28ebe3e776950185a0dedfea79a1a34d763192a3c5bea49d10d271efb381fd4ac31a108
236	1	317	\\x9df0b2232d36eb07274292e7003da8180fcb0967f8d03822f905680333a30e3e5090ee46b5b8d9d793599b4bc6d5c943f55548326717e78ed83667af5ffc620f
237	1	265	\\x9ccf5becc4e226502d0e61ad66d84e104fd2fbd2bb45cfe692e20bb446efea71cc02616fb83231e7a858b09ed64d5b1a961613de81617e70f313fffa6fe2170a
238	1	281	\\xbd01de1e96b58bc18393c33e4b3069b4d5f4fcd97adf5496a56f0b4a0c50d4627028ce022d81c2a31d829a8cf8aeed47388d6110e373901ea6cc0a5bdc664e08
239	1	86	\\x2a7001689463b3858a8b425d9a976f55af15d8d9458dee71537a50b59bdfd0c56bc2afd24719619f9bdcd46a34e8f59c54a843af12d96f3d4edeb2e766e2c50a
240	1	411	\\x38377d85f4980bba251d0e757f3a9e87ce3c67d5376b00ab33e5126cd5f9b23859980045b700c881ce29bb217ed17c564a51c6cf2844dac94bf508f82434b407
241	1	223	\\x60453ab8087714328807be00a117f6fb5f693ea55c9e4f04b43da85ed9a5c5ca513bbb3f7a50b94b6d4180250529e231a109471622c99596d5efb6e96061c008
242	1	71	\\xffec6d577be7efe9c7b18a57573f4f86838a3246cc51f00eb73eb82fd6dda5b9df4742e3fac3be8e2e9d7e91884f788cd53c39ec76ba11dfa02a2e78e8b0170c
243	1	357	\\xf769e55a5f5c26c3e0025e6c7156a744adbe1d9bf5c15bef11594a36863ae069e1e5f1557d6171914233dd310e35b99304937833c137154e4df2e79aa664a405
244	1	269	\\xba865674b9b0c31cc6599c609df25f269c74bc32d50f5c40de6de383ce6b7f85fc53ae49e65ec143d26fe6458e8de33e953cd3d815c5276012965e0e7ddd9c0b
245	1	386	\\xfe9666451aa1408693e91308d176ba9dbc5a2fc18d4a2595f7724f533e7dc4c2ef14c1ffdde974108cc5f502cc0be1ff7ec7b2b35752f2025aaf724bc6fb2602
246	1	75	\\x49ba5d1cb5bdc1a2da205c3ad879b1e01e18b30b49dc63b87ee4a351f03c378d5bc78d2fd28481cd1877c0af383e3807654c9db51eb82247e66b0833b988e30d
247	1	400	\\x0804bd7d84fa700bf7661d9f0e557d02480fc44eb23cd02123801e16a20bfc9d981280dac8385b4c667261c95f9da0cc9e02d831647fa4303d724c7ddeeeb503
248	1	139	\\xdc6b5ad332163e7b9d68ab1ccffb246d348446456b5309a76239b688302c4e8bd841c03a64715a240cdf8e78e7517b32ef5ddadc257572d8817d9a2d01480902
249	1	395	\\x8451b625008bc18cfcfaff25ad6a653b33e63d0fd2d84a1879eebcac3176c6f9a544b831f7011fc8afe82526729ca7fcf8d593412c2d612f47f8dfcc01d59b0f
250	1	184	\\x07e26944fa26af0ca6e6fa4d9aa368c20943d4f46b05809974f82bd8011a559439d87e0e4f95f9c643fa1d264e13b74094c1a423e78100b6ab8c2d410334eb04
251	1	37	\\x3db234cf9d0a432e94906b89d8640983fd9ec9a8a18ea59b8b57b39365559a8d1c6d90bf5c08dcf84aff120fda75dae94dd451a6b7fc26571f726f055f8aff0e
252	1	6	\\x6d814cea5248a0f6f6c3c43a0ef589a009e993450603b83f29fb64b6c506cea50c2f928ee02bb0ad865e712c6a52cc0450afd05aa4cbbb0311541910fd64110f
253	1	264	\\x81ded2a200e211e6381760e0df179df978f8a8d2d07671776dddf7ca28b8c480116eb949275fe2970365f12d078661319e09c135cb9c2b4a67128a01b6039700
254	1	316	\\x89733638530df21f44853f8f963d663934c7c6555389546c8c7957359e99344c011a3bc1db927c431ccf28b529ed531a8ade20e12a54ebec3eae97caa29fcc02
255	1	239	\\x1267510ce91e91a0ba3e18c2fde2ee4f38a78ec7ebe1e84ceeac6e959fb707067e8b56d61a7c4ef83664d844e7b9190e4de52b867ed6e4c8ec20ebe82db2ec05
256	1	51	\\x523c9f1a7842f9d277c1f9a531658ac2477aa9f8b0bb16e89b9d853f550287b0b0738cc70782925128573b71739de514f0b7abdaf25fe0447562bd8a7765a508
257	1	227	\\xa667a072e2256ba3328ed5979dc785ec744ebd68176eef6a2e44c6c485934636f7b51061730f98bc7473821c2854b4f0b73a57b98f842792b6c966b987b4860c
258	1	282	\\xe7d142b3710c8768327a70b46ff9b78576e6afb980b077ecf06dfa729d760df65060c0f355ff900d7dcf30432b2ca3cc17bc3b7ba8340e24ac209c3cb8dfeb0a
259	1	365	\\x7258e24dfdfe2ab9b1a88b78ab8f31992b2fa5e079e5f64d4294ee3916f525a5b5e2cb3c4b8484ae880ddc246473111215759594d8f9d5bf9f6f246d56e6f10c
260	1	322	\\xee189de36a263e534ad730b568cb8f79d6db5aac33a167c2267d255e1b5979a3ca8ddbfd7367e83668880397e8915286d5839d76aaa91225a1fdac1a41952601
261	1	69	\\xce7aac268fb0497e2770205dbc1d4d56109c4a13ad8d35174bf37a17c60afec295a2525f4d621277d9f111972b6bcc7580952bc666bc1fa4ae8455c84021b301
262	1	120	\\xfc9b54cc5548f65ad3be6a667519be3b88854f2687c95c5102160b790b591e74da5af1cea3b6c741aae7b378175419ba8378e3c3a9ee0b6034ae6cd425dd1f01
263	1	127	\\xda6978501b3d0a2ad926b0c98a7a98c29e4532b820bf2909cab880fb373d837ca02556c6f3201c8c17c4072f78122c86162807113e1647a5d43e6f5e68e76d08
264	1	300	\\x47f30ad7f7358ae0b5b42698b92432254c441a38215ca03a4ec834e5ea966bcbd74de062f3105354e82fd4cdbd8339164afaa3ad2b7b468cc081d1dc47073505
265	1	170	\\x15575e2e173ae789651df7acc6b6e40569c1fe35134f5ac2ece19edab1a9853ba1f1962073e009f758f1dbe1d490a9cd9320aff8d7a53ba1e4c0d707babcee0a
266	1	143	\\x235b673c6dcd6cba5dc7d4cd56e2934f4e869f9d63f23800e4476a6408c89ec2a9267c9258527eeeb447f5e11e99e1e44b95d381a9b2c816f34bb162c816da0f
267	1	67	\\xc16a65d4ccbd6195bb4bfc3c948c500d19d8472c94c285da574234df5b46d4987e3b501377fc25bbc05b2c5dcf0c3291ce90a8a1637646c50c5e4e8dfdff0209
268	1	186	\\x045a47a1ee78bd91c4bded90edda055ff6d49280abb6393fc1ed8cba5307acf440d7a6051f6fe5d037848903bf3a9e4f20698932f8cc453ee0e48ec78546ef00
269	1	77	\\xf1ebc3f3e2a64b577f1c8eccea81cc313d29e87cae752167969da79ec6ba77ec360811f4eadde296d57d19b08f2f0dfdb58429d4a8973962a2007fbdcb6b720e
270	1	135	\\xc89c77433189daef6e8cc9903d64b017c850e64575955bc7aa3f00aedd241eee96aa3cd3fcb1e16870667fbefb050c9b6b5011430b96c50f1e627fcf787adf08
271	1	119	\\x7ca9f6ff07ce3ecf149614d4516a6e2c9ed2762451b0bd145342f6aee079085cb5e1685bb3b92cf23f4ceace65f9fb55e96637e278a94b22304e49244749b805
272	1	376	\\x4f5cd3b82043d998dc28b40307d53f8a7b035b336d11a3c217243d0fb42dfab749d523008c11d0381f4ac29bf18c0e62f39344f0c2eb5859ca04cf70391bbd03
273	1	241	\\x605d4f78d536b87853ceacd07055634ca27c1d6dae9c1624f8c042aedd15189191fe648b223cc6d63a67cc272a0fdc546ffe4d58d79aaed44e38d5d1cc02c906
274	1	360	\\x781ebb26a4b85a3cd6878913c70a08b41a12a88aac4e9d528fdee8c601ec3a46a970f328d340b215a66fc82599d72353edb3d78513fc3cc207ef4a6d05f81303
275	1	256	\\xf582d1242eb608eec2044e9ae1e0fb98d06cd0f258781effe5cda9d00bfef77594dabc5a6f5725cbf1f321a5a271aca013d86cdbf428a6d6a648786941e9d404
276	1	371	\\xed3c173221cfb8a19e0e076ae06440fd37c88496e2df1837a020f31d92cbea71b53044a5d321802b3cb9f58b3a92d6bf7beaef0ee9d60d3a48435f9b4016b00a
277	1	54	\\xc8b53ce8bb19f6acee40b7c3ae64e0fd4c26de7d3104a79b4fba9216cc4e0c3130a383ebfd2d6f9e9dd82fcd15187790dfad6480559760f4c639af409087a90b
278	1	275	\\x16665f53c00e796ab13d7649478a6ee5482bf05e58c90d9ab7e65bea9601c9de863d5d0a274fb3b4db6d6264fcba0547eb7cd8cf21042f1dc44dd32fe26f1e02
279	1	374	\\xf2628258ebeda002178df16fef6b4f0d1434b1f7b4201beda44f97250329b7aff9c72d8d045edb3ab92b8d87c602134d2b36d825dc52c8ecbd897499dac0e101
280	1	9	\\xd38b5ffb3c65d48cc8ac6ddac8b5d8333dc3a7ad677da63d44aabd2630faa7912c5e4c9c01058025c819973039a50e4b04fee021062c06672341b4b237455309
281	1	353	\\xba3c7ccdc39419a740fd077d4db90efcda472d5bd9215274b1c84000c5a0ba7ef6077bc28db2d5cd8a0f819938bc2895931bbccd26b83aafdfa55d03908a4d07
282	1	202	\\x8c70c45fe7d903c37c9a030eeeec1f5d9f10108f896794fc279fe6bc4c494ef38a3967626ebc7407fbdb3c7112e55e9aeef19d1b69ea45c6d8f8c4c78af1ae0d
283	1	81	\\xaab4c8dd4f944fb7bf32d140dadcf3a1068363f6c6d4fa8b382f3e7b70433de482d669be037895d7d55eda45355edf90eeac3b277d075bc64a870030fb12740a
284	1	64	\\x197660f635c17918450b2d0d315452648c5b70ad7a22c9fa9b34f4e5dd27b4a70fef713d08f71c36217299983358d16ed57c3c9ab5eaec94f6a590cd14977100
285	1	389	\\xe549ff96290ce8cca1c00114c78fb1091b0a27f62c65949fbdf45e80a16b2f1221b64929c71aeed66ae09678d5f367b3aabdde569edaa728c382d37e898ef906
286	1	346	\\x818eeca7995352c794c3238eaf0f7548788cd3c44160c43f408b3c6d33545603acca66228259b71651792ccf813c384e612952cd1fbda8789e3a248978fa7404
287	1	294	\\xd52c1d4833270ce4a114b6b83b6518cc927687ddae2a001160bf4685073e9e9b68461ce8ea983f54dbe736aea9e58e407ce0aecd18282ed7bb266d9d3649090d
288	1	263	\\x3ac28a659f6c167087caa13d2499a1614080d55dc07a41a02319da2e33bcaf8049a33a9d2e9fb3f075877c5436e162d802f9da8417663e47289263283202c306
289	1	368	\\x6b43ca2f5d6411818d6bcfaea656f136013854142d8caad40fbabb6643ac2d037e72107b9da95ba3b718cbcd46b99f4212b6e130142702eb15810f1e374a480d
290	1	382	\\xbfd87080991a04dcdb3af5addd4746ac33dffc63cc7cfaff048b56d0ff541446816107b8bb0e247d55f018bd6c40a4dfa41e1a8e7ff4b2257c7c6fc40c17020d
291	1	240	\\x774ba9f07769e7a9d72eeba782bbf8e84d87fe23c0dfafb1cb2ea8dbb5371b7acb95c83249b50ddcb22b7cdfcac10538a3f6fc9dbe41cbd0bdf57570181f8605
292	1	1	\\xfbcddafb4a7d2d6c04633451ebcc33d954bc5481ec92750816129f4ee3bcd8295885ea3037b9362d1dacc05ee99e7d42deef0e437a5496f30079e23cfb787f06
293	1	267	\\x9a7b80f8161ec7e3b9701df042dbbe0ae86005c8d72cf1c1f97e93ef249cc084e4abd1253dc7a120d89f75f466117b752dbbf1e17ed59e34ddb26fdb2423d10e
294	1	289	\\x4a69c99512a03b35a4c6ccf9e5584485ce77fbc9c25479cd9609f39551c4c05a270071a4e41ce75b9f152d36a2a4648d78972a26da0718af044e771a3fad8804
295	1	415	\\x1e12a211f183ea4a3b16e50bde8607246a31152963498d5a1bdb1ebae8dab3d32880e976a7f3a863c0a9d3004072df230689f081a3a9d4be1cc1ccf58e96af0b
296	1	232	\\x7f8a32464a8ac0bed66a0d045638a21a1add6ddb8be6c2af30c8e5338bbebf50420d9c0024d9c058d758942c84d7e348a0e942f9e98412ece7654c77ac845202
297	1	178	\\xce56fc2daf6b1966b0cec2864c089d36d26f4f86c39e22c0f098827686f6b2553dfe47de81f3e15b54af3cf703a0770dd5d1633cc48584df065b45d83c0c7001
298	1	65	\\xa17e31364268977d131db406d45e4d34e33f914e7cab6429764dc94def6d89d3d923dbb9ada82590828432bf8ed5ae0ad795037012eb222dbb9b167a698ecd01
299	1	413	\\xbe072564ee3e3abdd95c3f951b3392e3131324e317cfca7461595a4d505859aa47df29beef6542955dc46d033c655d46d317268d8721cbab7319a681d9907404
300	1	148	\\xef1cb4948292e8be47a6992eeb9d0c8f3172ffa7fcb5278128f61b02e84a50a6a6471d7e72a4af270282d7957fa716c1b29be33d4c448cd8ed77380d32014206
301	1	91	\\x10b96bc885cd674c46726fc8b897f54dac154f589c8954c81f30e4556ef166e5047d283bf745de86c6c26309a9cda674f1735f79b414c84c55d06eb09e9cc703
302	1	72	\\xee7b586542a9d55abebaa0814c36391a0ff1ba3b2c18e2fca4a533fc6da8c1c6a8de4a49144e8c22a19dcf2914b939eaa55835312e505816e130a3be314b2409
303	1	344	\\x12c04d5ff7b87e1dbccadc690202aa0fcfccd387d68bd4ff4c1db843bfb4ca3d02067db1985ee0d593797ad0ed1536ab6c191e95801ab7cdc2b6de88e632cd0d
304	1	253	\\x50b6746820105600e576f8b727443754f3412006206e021dff27e91d95eb1dfdc9435d122dfeda9995a16c249aeb064fa902d83f7d18483f6809384d81676d07
305	1	88	\\x29e08aecc23cf9dd53bfc151111df878defe42ae6951e70c95d445b2d3a3ecb6ba9ebc166146d1d88b55b762a038fca28263cb86435593f0fb63b6a9c8ffb30a
306	1	352	\\x1574fbfec57f20ade05eada037d26c39e3742e1c31d3ca886c6b5e97ba22364e008d486c7062d5d25b2e5b3b57949841bf190ad0a3037016e2123841fb50b807
307	1	335	\\x331c1ed53a81d0e78604430ede68f9d0e6236b427b6dd198c215f413c3721cc5dd10b89833688fa57dff6b2c65b27828dab99f6c007e1890902dcb4cf6501b03
308	1	236	\\x7518526d9e9723ecfe6449ed4468eb499805303125615509e8702c0b8c8c9ad88b33857758e16b2cadeced85465321d214b60fb7d185e406d64793f2011a160a
309	1	342	\\xf8dc80f308d1075465afe8c11e573fcf2258913e370aedb0803bcd7a85ca142391e3c5bf4930002fb5582499341fd7d4de592cff94139220b78225b260552701
310	1	201	\\x00bbb7b464387438f67412cbee9447672ed17b7b6ae38b7018979fade0f261fd86ffbb4982517869095f2991addd58031f157cd1b97528136a041ea815c3a30d
311	1	188	\\xa11556b08fa617c06b6c66190c84721c6bb5f5f37b3825644c2e1819248106d8d2463429809b6b411cdbb0a4dc9bbda302f088f9d7fcb9190cc69efafd256509
312	1	213	\\x2a1ff25d66ee266c1dca0766a04fd1f246e8e1cb870cc575218a7d07b002d4def073836b6fffd1af40f6b3e64263223ba3a740e740c6c3d32d45e6be30b47c0d
313	1	391	\\xf9ae81eb7fdf5d87c8d93b6b0e6952e77b4bfb5f1152da0276c479cc8dc6a1452b2ca0f5ae08643c76a435eaea9026b36cc1cb9578a1a765ab06d203355dea0b
314	1	177	\\xfb5e8b6d16d84d16ed45ede9b1f7b45eff7c2d39d3986b4849fdd4099074d8dff170f01d6160636a4edfcecb9ac5e21c87813ed423a82ae6152d056b418f9c02
315	1	2	\\xf82073aa3fe3c01f16a2ab003a181dc82488df04f5082da593fc483ef7ada7a23ac260bbf2922a7e6d11e67436a2d22aefbb94f4103c64dc00eb134d918a2805
316	1	378	\\xabf87cb156509135eb798da08c191789fae55aa72c000cd3d9d3577cbe8361e1b60cda9ae9b6afd0a7afac67e223d5d89c9564f50744d71bb2a85dcdb199a305
317	1	109	\\x1e52492b2bf49303b64da8b627d97fbf7716f8dc8f157e168e237dfbd2abb0c6eff9b18f6c99528880f32cf0ec4a760b8dbc840df3f6de60bd4d267ed0727f06
318	1	43	\\x8aa115e57c0df0d9cb11d3abc2340abab307f0b2f0c44634bb11fdb5597499442c16ee694d4e9316de2cf21c9bc5a821e26a7b1b15fb85df1587a982795c5809
319	1	396	\\xf1dda4ba1e71d2805fe8a3453a53cdc3055f114929d7b1f0096eb7f674124ed919cb34b43139305ec04e5ad516eb96f3411c80043e20201805b7c4dbf635ad0f
320	1	24	\\x0ce45252852d43cdd918e21e9bba6546a150eedfa9607c5e18fce47a9f59ac059136a9c85ab7c749bab11799615245e6036649e10727ebfa9484d83c91ccf406
321	1	47	\\xdaf14739e72656ee92ddce2f31a9c46fd5a1bd1cd1000bd83f67aa1c90fa5b2205b2daad60c5bb3ce7d35c128346e13612e4452aaae5141459677fe519703d0a
322	1	407	\\x3edfa88b3852c95a338d90a9ff5d59647c733f2c8d6051ba0feb0b6fa544831e24b8f88fb57dcc3147f692de8567bd7e9b32d4f695ca7b5417a82db92b2faf08
323	1	319	\\x97474038fe0b8b70b8ec0cde6dfec3c178a11eb0ad8c8a029eae4a34c76d50fc1f38313af9ce9162d21094215642f53a6fb8573167babcb4fdefebbb1db97d0a
324	1	337	\\x0859bdde99840e0c2c551a011904cfeea5e25c733b2181b4ba16f91a6f2c405025d08618ae1a8c9d406d0859efefd71038405287fa1a28ffa973f8231b92c201
325	1	103	\\x9346d8da2f91c37120b831808f48489a19db7800faa4a0fadab7f02ec4c6ab4e5716dc173c0d24d506c75ca22ecd48f16e66b6ebe511f461f45d1421c32c1505
326	1	38	\\x7d0eb6a7b3295750ce89362ec7b50ecdd8cfb42735865e83773fbb7d58ddcd26eae7af15177d446a820c5b208b9147f25f74fce1c27274ff38e9b7b0a7476f03
327	1	224	\\x1fab3647ee70013999f31350b67743a8a477f2554bee70953a1a822759c5d5851a630625810e78b7937ac8aec538a8750643c1e88528cceec79114083d593b04
328	1	362	\\x563a812b1c8fcaf4b05da7d79988635b24cb58a03bf7579c8c041bdeda2a2c31288772dbc8cee64848acc978fb352b62f45e12dc215c2c679e69db6673c37a09
329	1	99	\\x0fb139cd53d68f6108e15cfc527ae548fc28b2243f7350eb7dc83abf369f2b7a554ef33110ef9b853e3b0c20cecf91073993d0bacac0399e78c771bf8a944c02
330	1	95	\\x922c045cedf11244e82a9f2980a10d5fe4a4342b0ea606840ea697aee7a276b06607acd6bb14cdbd2a5547c3ff9e832a6e1dd3a7ab8906fcb784293abdb99a07
331	1	145	\\xabf415ff34677c6b2b97f522a11ffab9bb09dca43e797af64af6a5f8f395431717510e150cef6158c658c7aaa91c5398e4abe4db7d517c6a3a3c1ef121c43c03
332	1	258	\\x7b7e19c27fa45123ae0648eb5491f7944b7c9f7f5df5223a0e2e6ccfeff41af73a9bd7fbb5a597a17db51e415adc3522713781350e0f0ab14daa4998c73d4c0f
333	1	79	\\x12d550637463a52339cfdf968ef9aeda86695b2e3b805b8a5c9d397708a34c44156b35bba704f5fb3b8ff80251dcb1799e10f09e685891edbab204e702f0f800
334	1	266	\\xc4a2c74cc17c5c196ea0c9f4887e5e9eb6775fcd6b2b6347feefea7d106ad1cb9e40389e1ecc152514a36504aa642b1d45fec2e85beb2f77de1c6be74cc27b05
335	1	331	\\xe8b7f4bb8347349e3379e69c60248d92099ab3eddf030f25e8f97b881a238ca822c7a77d9605181411552433522b79e30d60868324fd6f693dc8f3a825bffc0a
336	1	420	\\x6c9e75f08a1c95f6a1ef1d3d03ac79a53ee21aa650606ef8268af060e25d50083cb7885948a78ed99ad711a5833667bba1fcf420179163f107174867bfe8c70d
337	1	311	\\x431a87fff44dde37bd23e731348716e2ae29a0c1995711d1a5594115dbb7daf9b0c7a70d09b6b92e257afe5768809a666b524c03603bc3702f6aaadff5938004
338	1	295	\\x0a47fc42975506c07f7112093eb6f8c0c6c49a027777caae53ece5741d307e0cc801fc083a3db473cfb5d9bf5f5b4f0f79913eba966bff364771bd94c1a0a706
339	1	102	\\x974cf74ce055390933ec3142ca2acb3f4801fd7c83449fe77256da868eacbd3ffa01945bf31eb0983e20789558854bfad14291e50f24adc4cbfd5b6df5549401
340	1	351	\\xbd2241895a3d0305c7c298ea6056cb395fc96cc74174dd4204abe68fa2c1fbfa47f9414bf04949f838bb81d8c88d0455d1fd8243b2bb37c73da5e506b1aa2f0a
341	1	410	\\xa3d906cac9c89df4e9920e195edf29958660476f579323e461819a73899004bffb975a27b671523661dc44549466b2d9aeacadf55ea6e7b03522977745cec907
342	1	291	\\x732815f76e15c00e48b14adbf9654b77d4ce93473fb18d5b4a7bf296b122d198f6a8161bd1d93d19de311b49698c0d5328a80c13f5e72b425261325582f95c00
343	1	125	\\x3afc3808d6ff0dd2fc6d53a7a60e3f544c697b318e7fe0dfd4e6193a86c9c51c2559b753d05ef786c5af6b0d6f1891ba029692be3d55f30c58ae483f1d7e4a06
344	1	221	\\x778662cc87436b5f74ccca453335364b6ab3af65bd882bc6cc837a1a9a20c9e505797ace80d7b57db934424f9ce7fb4c2b3308fbfa550b2c79d076afb849b30b
345	1	113	\\x4d2fa5252dafa8af8e4c04259191027937b3dc56b970ebdb2d98ab4d72d109f0ebb0b5a0ab9ef052a5f47e07f2355ca9eef01771891d19658c010a99cafa4807
346	1	142	\\xc499d60c7b377b1d9609f153cb6f74c603ea4a611010775ad5f0efd03e1937bdd0d7171e6760f59cfe12509b916c6c46918a42cebaeffd0799a16c9d68adbe08
347	1	17	\\x7ffc16c5d39c82ee354042f63dafa868ba39414759a9ad94fc943dcb4a497747395b6a78372aca75f5b4bd96daefbe48bc1d2ae924366c3221c11dae6a7d1505
348	1	373	\\x316749132808ad12cb5335f04c0bc4d605053cd6a84040e23089db026077253bbf5756adee787795e88c6d139843d154446ae068c6a1db29441ebd71db2a0d09
349	1	292	\\x2986b2fa833ec515010f32d716a49cc27ce2d725b4b80decd6972e04a03090a2ad4092c926c17f5c0c14f0bcff37da8d46ec7b1659938fd815fc5766d64b4306
350	1	293	\\x662dc63447b843c88a6d5f7cf2d4e25165c2c082e3e6c745d53c94f0521593145d07e85622375260c5feb645a6466988cef75cfb3c89fb63ac53f59ef2a3070e
351	1	283	\\xf3ef80b1fa10d7536c3bf0126dd89472fd618c445ab71f61ad5489d46b67c7d60361c32f675109a1403079a79d1ecf3a4af5c13d197c8a30fca42437d773b400
352	1	106	\\x3b0fa113282ba31f87b3a11fe0c24327a1b2d68b66be70abab537b153674f88d12f767006f2f3b4d4e0afa1f9c9cd1ad5f047cc05c9f5584700aefa848bc0901
353	1	334	\\xb12f1ccf1b4a18859ff36caae88375c04224f7ec98d62b908d0b505ac1ff9bf819f6e5a3c5ed38866ef6d7e566fa0947ac91d800f1d8e01ad0f5942cab470202
354	1	168	\\x3ed9392c03459507e3acea2651a5765a675365ecd9564f07a3cb29b2f0986694943856938b628f90875f497e58820d6c746c52f3d16aeb584edeb38b1aeddc00
355	1	45	\\x8fa72ad608aac852d783b86b66972729884317bca0f3b0264d8603f93678b4addaa043476f0aa3293abaf6935938c04d8505d631aacee36c6ca5bbefe7cf1c0c
356	1	418	\\x70aac088ada2d85d7da8135c11c98063e3389594fda910dce3718a0c610345ddf659dd162cb972e7bb25377b14790dec72536866f8ed118e676e9af3852b0104
357	1	387	\\x0ad524d75ff23ae94e8c0f8008e4188da998d9a91779d0d9da7bb761bbc38c64d8408137a18d03d0ab8fde28d8991418169d22f3f3cb8416b827883f5170a90d
358	1	33	\\x4b368064538b86aaeb69b721477b740272456c255c6ddfb09e45c7ffc6425480fcb5fc6df408afe96c2a7f227195be448fb0a2ae629e2a98b74c6a9704d2f103
359	1	198	\\x632accf0117d4477334fd7717580acce9e379fc887d6b82192e37ddc8495487aed1b14b9e308722ab8316bddcfd6cb58e9e2b429d6bbcde58e982c3bde2ac204
360	1	137	\\x0253c14c830aa43ae8f0f5e0c9d1148ec0dd596081fbec820d0b466a7c3d6d42e325527d4be7c8e9e8b0cb72950bf9f895d1bea38e5d6ea5d0455e5bee5c8108
361	1	424	\\xada810f94d928bf0603bd362227207506d755548e14c6011c1805c6fdad20c074d30d8c09fc0f4d48bae85abd6d1188dbb53c5dcd840eefb92f967256113d50c
362	1	215	\\xe100c66645af0f9d7f50e8f16e67c229bfa455130e3118dffe6272c96c4dfcc3c96ab90ff2f461784545d4e8d2b377fc364acbdc83c59ed879b7e3638c5ab201
363	1	166	\\xb25b837e6b1528506320bc4a6f073c627422290dfc76fb2bc3529dfe47f4b461e533f1b796a988aae6123972f04ec4dddcc94251b550267e36ff1eb973bc2f06
364	1	287	\\x34887df411fdf8fc36edaf5a31e2317a2ced548d71d48cf59d25e07be7d57f35912852b1d8c40cfdf6a3baaa633325600bdd511d2234bd7260bc9f96e847db0b
365	1	50	\\xb0de615ee8d8374fe3197bd95ad911f276eeacd5e8f98d805e45dbaa5f2e7bf233f384a2592bc50b84b838c82b51c346a9ff73833f813e3e09574e0072843c0a
366	1	209	\\x800458b9e1f20b43d79f9ca74ad6bb0772dcef887aad1016e7d0ae9dc9a86e76e5b5d02814471576b4f57583ee1881009b4e73a41cce8e4b904c29773ba28c06
367	1	205	\\x6dadb30a88d8ae4343d094fec30aff647a043f7c4cbc0f5468b8118e969e1eb63758863e05d31c4f76439ea2a4518778016617af63d19886437294e3cd6ef206
368	1	98	\\x5becbd8e4c9b47ea5bb204762c491a8467766cc3b4b89c0866cb431907e65c1c1deec3970083c05b0f5adf6f281e0de117cd31d33e464937e2ca198db5c61301
369	1	255	\\xc051e894a9535aff8d4aaf30924574030fb5e86e423f2eb68a4c4a8211f279db1e9d462b62ca610123938e448a740616fddc76bc0974f0056854f7ef4f026c0b
370	1	206	\\x3529fcf35d9ef0dbbf887b3e5867e3c5f79764c292e5390e73b67465d81e24446177ed18f03f35670e6e1c76361b7aa500e920fb22dc667cc6c70bc0fcb2870e
371	1	175	\\xabad0ea0e10cf662077048b7d9766298cf84c903a42c9cc292d67ee4a31bad14da2cc7c8e60d59f240a54fe7908c4fa84d024ba20724ff344f2ae0db0de20c07
372	1	379	\\x5d1e31b0177d924bb98b23f257af1a5e2e39eda89c4d7c5a80aa6a32652efecad17c91cc9afa2ea48764f4e6bf1f0fcf63029a0a2d312e040967cd5aeb06960b
373	1	313	\\x832c6c41048301d85201370ab4e5a63106e74eee415bdb80f1eb2edac9bb7518a7bf1cd11ec03d143724748b852e6aae85565d9b1215806bd696d18a756cc203
374	1	254	\\x15e03dd9aebcaa229ac878683bbfe7ffea773c488e3529aa1b2d6f435197ec9ffeb0690673e6c736600e39ad5b60defee2ff4655387f274b40c106a5fbecfa0f
375	1	196	\\xe0e9f812cec76d0ac6a6c9f066509f579167ec32b29c9648d7ca4fdc31a05f8d978a86b85f184af31bc6dd90c82bc131d30cfc5494ec7e390638d3d2212de10c
376	1	63	\\x8b5f66af3d962209396b41976d90d8d1161c9f88c0b6c848ecb2f1080a2a5b6b5df60d4562bddabc435792d95edaa27bc9b50c92efd634930a9b8aa8060a3b0f
377	1	204	\\x43ffbcb1fc019a15de29727e860b6cc21cb62881e66da7fec68398042a63448ec55944f7bb39c3c33d53f5bf41ea25ba3ea15d97bb1d4b5b3a6338c39c212507
378	1	36	\\x967e0181511de3770c7602eb8993288089a038af84cd8f6ea3159e92502adc7b77e2f09b2de899801e76f1eae7b4020cba4b171d980b3b8d579e0148c68c3a0b
379	1	179	\\xb2e549f1a597e6ed88797986a1f18bf74a3982bfe3a3b3f2e93f3e347ed1e5ff7b8809d33282c76cd97ec0a5ac2d236f579648cec7d2c7cf1be5bb1d7a9dbb03
380	1	114	\\x2b2d2559005d47b087bdca26b2d15a6d3c7a70a060d36b4735eccf8b6eec0505ad9245e655f1a3926d2c06bf22e5e6015ea7dacc9b14ed4e13e0d7863ca5aa00
381	1	423	\\x0b6b7c56f89090abc696fa14310ca7c592b243713ac871c29d17aa13068386d47af2ef5578e32721487195a8edcfbf7806279c90999f16ad1ebb9f40fb1f300d
382	1	3	\\x6bed12ed1d0e935808128c25091f63411163e2c5dd6761d381f0849365f045b498ac16681662f293c17272065860750f4fc0cbd9f14e386dcc7874311aa7520c
383	1	68	\\x3034357630d78aa3bb713f9ec5a6a8396fc318ce4ccf7a13a3da62fe2cc61aef09ac7a363befdefde546ec63e7bdd2a36ba2bb1ac08584067b71da8f60d5a401
384	1	185	\\xbbd1806d3d308deb48c5ee0d255ff3f25213935bc5efd2fff0092612318f43404bdc6678ccc93d4d1089a996b98104948080d2b68e8517749d479299e02a9102
385	1	53	\\x0082b370749f2029fcd9859874edbdecce2676180c3bfacc04b582a7885f6dc4cfd43624d55134f571a153cdc139b945b9f00a10685cb6d6843e7e5b7dc47a07
386	1	388	\\x4604aac87a4ce0f31db4868748badd5aa6d9846860544e5efc32bc7231cd7068d6bd5d85e5e71fbd0a0d31361c210881a2e2efdc117065e06989cbc7a5b91f05
387	1	406	\\xe9d4def7258bed05db651c1a8600985459798df2693f962b543de941a30bd24b53496617744dcc929bf8ba7401f18b8c7fdbf7cc5cb515092851a9ff2c355308
388	1	304	\\xc417f4907094482e52a59feae7e785115d6dc992d8c7e3be54d9d3030d5f6a95bae3c0b83e8352e2433ca4eb67518fb29625728e34e033e499206e5783e6af0c
389	1	29	\\xfd2509a911d0e83489b3b2b0f18e72e2316adb1520fff2c1b78da2d90779b0eacb5f82bf6c434ab88d319f57c036e6807e2c36ab18951f477b1592a232bd7d09
390	1	277	\\xb3244779e828da67de44dd68e6b9f9d05cb42618cf07cee3b04bf49858021b31be8b01bca672ff4e339ec46ca47154d0628adf7a88431945d10878d09aad580f
391	1	272	\\x3a9159e1173c95b68d3f0c69ca1106638dae0376291f954c7832aa91c374aa643c419eb02058d4ef1932435e53fcfe7ec637760b688817d2a1d9cb9bcc569b00
392	1	132	\\xec3579a045a4823e536b9e3dfd5e9d7804f1978f94b092e2e8771e6bce3f35d9e49c65ff9e91651849149bdc51a115948a9d646e8e69dfa0b6da2b5147d28a03
393	1	31	\\x79c951ba7221f6b366a5c0da82e6712fd2f9b2fa4e6758141c391f8c1b5a2d958bfaeb8533767acc6792db709df7d9c1d7626f28e10290b5a55570746970a20d
394	1	87	\\x889a801038faf241fef8340e906236cc46967d72171520d2e3e4cad8e6a8d5bbd58cd0fe62c1c45766e061791575b9ffebf536be4bbf30ddc1fa7138d2cae60a
395	1	321	\\x29880e56597e5e3c2659022977c8c796aee91284a65b96414eeb047615affd7dda8eab4a71840f45f9ba46e10c0aedf1563cc21c2d34175b4cba8aeba54d410c
396	1	21	\\x9f5393f0ad6248a403e4526fdbe670e8c68baec78d40432009e6d73b1e52ebc176a3fd940ff2500bb534d22704ad95d13c68419eb2017cb9778f4ad0c231f806
397	1	328	\\x5ed8c0a21e9cbf50f055359e557738938c27f64f622fc9c24687255ae10fdc01c3d1ef5e402b9528a8183dcaa9be45e0b066d201e925636bd7b168bd969f8a09
398	1	39	\\x52ab422d7d91897f34574a14eec50f33335919a05b1c706e458e3bbfbc15b0160b84d2bd2b7009c8d28e931a00c56a3c4198a753d5f4b87757fc25c08273e805
399	1	343	\\xe6b6db56ed3fe521ede48440ea1c72f23fdaea1f5e33783df28d52799fbe1fb9acb9d5e1e2183fb79a386a948f4cdc370d2a0f3ae0cc4657c8334d64f6052b0e
400	1	244	\\xdf2a9dfe8290c3c646ed1e5148d3600dc9a751087d66eabb3d533e987fdc9a7d77c2d42635fcc5d79b611c1a9f95578aeaae0e44fd8570284822ff9dd423da0d
401	1	192	\\x2c66a96ea1fd3d339ccfc1495ca304f3471e168b97df4300cb78645e0670d62b67862c466fa993931d17e168ea08a8437a45d27b5ab0bcce5db4970e4c04590b
402	1	49	\\xc8efb79250b4fae5e88e2f1bffac730623b388225750d74812ce9712e66da29771b10fc65f4218a6d661fcd2e03a03a2b21b41c01b77e4c381fc6fc278e30302
403	1	19	\\xc5a383a97a51f58b304923c78b223cf41317d2f2dfbf1bfa5be890325442c5b1fd125cb055805f2b4b12784de8ea21018b876fe5b7ffb3135d78c667ff29a80d
404	1	366	\\x86cfedcda5d63f15d684ba4cf696eed4d52a786d8db25e7977fde477fa9c2436ddf94df68bc830dc3a5b945e981229327ed652ef249666c0c08b42efe8a8e909
405	1	20	\\x443ecfe2f112aaf3870094f20ad4403fbee4ed57581e7c87582c1c1976d78f785466c3436bd079b7b07d02a26d6f9a330a65541134f968a46f5322f43fbe7b09
406	1	274	\\xd6b9f387ddbf47c241c782fd34218e363847a140ed154f331dbb0a3444f034fb756e26f2ef68661b525a4fadf547eda97c9b956f802f5149eecde6c12c534f08
407	1	62	\\x3601264b08b3c6477104272ec8f166bf0b15235eecd2b2231299b5b75447cbc8feb7ccc4bb4c5004a68220e74381e133d7139d6cd05899fe8eb1a3f21009190d
408	1	364	\\x07bf4db3614e76d0619edddf96d39f5ee6260399151f11f590a04218cae9187f8b51af78694f3e33bb62f686cda463961ed8260782d4f99d460db7c153857807
409	1	375	\\xd9a154326fb49e46603ace4574dc0bbdcb5c9b136a2d09a35fbbf71e85d029d9846dd9c18851ac27bd38c17d16560d8014750d2f371eb2a70fe71cf8b5e5fa0f
410	1	129	\\xdb6a5d66cf66d310d1816c95a4acccc62e70d2770fd7c7f84205dad1ffc78e05e7cb8a86cc472ad1f519a15e8a9f49e80556964c1f3f5a3f8086ff9afff02a00
411	1	320	\\xc90c85aab40c77895ccefafadd631a5c25eb3bb71b3a3e51f036e5e8d2e6f8e2e2037ab612b62255de6c5ee803c74c2b8e5f7b479ca9b2c619cedddd782a2503
412	1	222	\\xb8d6d16ab4bc929a42311cc163238d6043d12622cc3a7d9df1dca700fa02da9d90ba41536fd74a1a0cba50a26164bb76b2deb4fad47c24699832e6e90f9adc0e
413	1	66	\\xd9649f8481cbf1f2ddf4a4671f4195252871567567f02b5876ec034c6cee9cfd41b08e15cc4c57e091b2ef15e12d5be3efe87454982b7b8d48721adc75ae1e06
414	1	296	\\x8d143196b3e2e1a02995909a0666aae5e6938a1e37af847de67a88d64b83264139fe6ce9918a41e08b0f851ccdf2dbb98e6d8b3ebc283884e27c24a663aa2f0e
415	1	83	\\x56ac5306e3e2f13fbf23c0526183b75a17ddd5a5215e9245014b88a521c5aefb649e8cd863f3922a4e179f5934753ff320eb5aa19287236c702df56fedf0d00a
416	1	130	\\xb21157df841724814228276e8e1f115b096c1785373a71ae0854e0c21e8c76687f83337087a5f9e88d5848d99db5a7aea3e05a7cc09bda2aeef3b6b56e1e930d
417	1	111	\\x6b1478db4bc22983c96507cd00155637c5fa11fe5e59a2c4824725ac57c5e28a81a4c9aa4fdb8d93b51c28eae45b5a25574d75a94bffb7184cd83d9bdf28a904
418	1	350	\\xe39cd463fa6b007ae500574f94b2c3ff6b9121c046759ede978ef55b411df403ee65fa260790f245942594ffb65352e31beda53e97c1777fee42b0198a4f4107
419	1	315	\\x181f5198be4cf4bbc8a3847ae359a41732d5565264c98afb5a20ad6aa8a1fc03063884a7445dcbbfc766b5a4760792aba8136b1608959eabd1de6293dad4c60c
420	1	203	\\x53cd43113966baea7bc0f62a411d816dec0ead7912e2dcf16656e1a620ba09b5de8dd2865665ebb9493a22c3beb975493affbb3229018d0625516952051b6807
421	1	76	\\x49f53981a417e1a991189b8c9dfff548c5023f9a870f243cfd0bef31c0ac6892d13347543c4abdd0004cddb1823f01bf1fbb44e592e72e51ee033b77ea7e3902
422	1	197	\\x05e672e51cef930927063f5c537047412424f9d5d24e1645f628f240bd5d832206aaeff7408d23f0c910e90c76a59f2688c962efabf8ab6ffd035e66b3a33405
423	1	325	\\x0af2ed087329b0024b8c709e5827dbfc4b5790490cd89b269534ac49cc6a5f0b58e8fc2095626b1d79c7f8d6fa334d3c4a19dd1166bb70b3750e33ece409ea0c
424	1	358	\\xaff960603f9e286b3a67d05b3cffbfc879a8f4a23c0190ad8cb198b78d5a8686b8529424eb80ccba6e48ed814241be5e7a815ff2a63c7242a851d7d3d0f6cb0e
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
\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	1650825343000000	1658082943000000	1660502143000000	\\x43b80c8d574a98e097cf0bd54059bde453f269b7a7c1f33000b998b3142aa6e9	\\xaf4368c65d3a5c21adee6466d5e82e8ebe3c414776cf840cd45d1390b97db17abe16a8d6b9936e324234ef0c00a3bfbb55422c721ccd1e61817de752ef012a03
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	http://localhost:8081/
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
1	\\x18ea13dca67424ac5bd9e63e25c9b902a94fd52015e4782d9abb84e545ac8c44	TESTKUDOS Auditor	http://localhost:8083/	t	1650825350000000
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
1	pbkdf2_sha256$260000$lU7chnXfxiGJlARbY3iyfQ$KOQ2DBCjieZ0yneZIH3k8K5xW7zbpHS+fJaVOV7Pa4k=	\N	f	Bank				f	t	2022-04-24 20:35:44.660272+02
3	pbkdf2_sha256$260000$6wo1cwsA8LsQu0js8vhAMR$wVOOTgQEX/L8E+D5HHMGlrWKDIBFbdRIXP/WX6WGLDM=	\N	f	blog				f	t	2022-04-24 20:35:44.85421+02
4	pbkdf2_sha256$260000$6edL2mhkQ7P7i6S8yrcM1A$vnteu2J2LQtin7FZ75aFTap+5SpRM/ZmqKLUREVg0rM=	\N	f	Tor				f	t	2022-04-24 20:35:44.949915+02
5	pbkdf2_sha256$260000$qhTl6KgSyv0SgRXthMpfof$htgtJ4p5ZPi80UqME6TE03jG9tbLrnC4Grriwhx+1Dk=	\N	f	GNUnet				f	t	2022-04-24 20:35:45.046435+02
6	pbkdf2_sha256$260000$kWaZDl0hnmp1T9UBxDZYcv$d7JWwOggq/JHBW7bJd8sgBjTLKn+6Gcp23BwlUzEl8M=	\N	f	Taler				f	t	2022-04-24 20:35:45.140473+02
7	pbkdf2_sha256$260000$QiSvBI8Hdzz0jREShI4ieP$m9ghBxe8zdViDgW24/dNQjpoKnzQM5ih5YrJAANfpCs=	\N	f	FSF				f	t	2022-04-24 20:35:45.235139+02
8	pbkdf2_sha256$260000$kqEhg5yP6sEPrtA36IqLlC$jhX2ALpV0BrUvdgTnn98x6BPJmWDBqGpO+cemM27S/g=	\N	f	Tutorial				f	t	2022-04-24 20:35:45.332204+02
9	pbkdf2_sha256$260000$PBjMC21KsRJ2AsYzGcyTqi$k3Swr/brd4GgAZgajwPr93VowlbGexzJzw6/psKE9hI=	\N	f	Survey				f	t	2022-04-24 20:35:45.426846+02
10	pbkdf2_sha256$260000$eWNq0nmjmS5jSssvMrDoOn$SnQUxYo4423/L/W+rPyWz4PkSWG6DYYd9edCFHqLkmE=	\N	f	42				f	t	2022-04-24 20:35:45.904362+02
11	pbkdf2_sha256$260000$W42ypFJanzyvEf0rmViVkH$b0fsvNwZ+CxAT1Mwa4d8BP9f5x7dxdS57g1xdgucuOM=	\N	f	43				f	t	2022-04-24 20:35:46.356108+02
2	pbkdf2_sha256$260000$DqzuhctwTLtVdMgNxYRvC3$yl8Y6PJZ/4yuvjnEyzOtF6zG+gzUB80EaWciAhWga2g=	\N	f	Exchange				f	t	2022-04-24 20:35:44.756882+02
12	pbkdf2_sha256$260000$JMoIIukOuX7Ef6EzAK7jWx$WgozLajkQ5xdLxyMcDIHvnlCW5N2i00BTQnZ6uAYBnU=	\N	f	testuser-vjaacpjw				f	t	2022-04-24 20:35:53.516948+02
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

COPY public.close_requests_default (reserve_pub, close_timestamp, reserve_sig, close_val, close_frac) FROM stdin;
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
1	325	\\x52bba67009af6402915443d822498f388731ad652b9b15a232e31908ff23dadc70473bfa18767cfa15d8de12c42f4b1c7aa2d5eaf55329fca1e6a2f6c5e88105
2	66	\\x70331758c014c15b2150c7197324f37ead6e91c4071ecb12a03e85234445ef3b95c8cf93329bab073d7e19a8d28c244249eb09f45653266a1e808fe56a81b900
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x0048550fc27e873a71cb660fcb64e35cb17e74acde282e82f502645b8a6735323ed08a7199b5eb8786e1888d8a87178c110a5c16194b747fa3a14733026c8151	1	0	\\x000000010000000000800003c1077e2a47893c7c3eee277f2100690b7362d58317ed649f2e9477fbf6bcbc51a79ee005a74c019e6c48b55ab0bcd4d5bc58bd005f9ed83072f261d349e3dd0f9716f1a5bb3cf35f3a5167e759386a68d4d4a6804553fb4c86fbbf4eb6bb998fa4233ac5cf7a89ccf397c3ae852477b24a4171fdeb5f22687f2eb22507e18c2b010001	\\xda926cfecef25c7e1b2b3533b9ea60da5d65dad01c535d697796e31bd375c5f799783000f2c73f99740f1d630ebb900ce575859421aa0a1b3984eb2211bea504	1660497343000000	1661102143000000	1724174143000000	1818782143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x014871c6bb03137f499717bb662a3c7820989eb622ca72dc927e14f8e1e3d24e262d6b811740bbf162bbaf94d6f40015dfc1bdd3f8631579ae4bcd981f611fe5	1	0	\\x000000010000000000800003db92a472cfb891580464a31fb57778d7305452229972ff220e5aebf3e7a3d59f0c62c39c653692e97356a6d5ec4ee1c80afaa73d3a80c3316f5ea55f3a74718bf3fc29dc31551d8bee89bdc1ef4b9f98f877e808f18879c4abdf458cd9b1cea35895df5ddf603c99612d104fb82aacb875bff1f64c727a960efd0b8b44285d71010001	\\x345cef5638cd0d8fab340daabfdb0795649c1a11120abe04d8b3b6bd37a38c01f9b3b265bbdc83daa0a1ad718ccfd1f45d9b7f0d0dcc7a6a76fa8f7eb1c0590b	1658683843000000	1659288643000000	1722360643000000	1816968643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
3	\\x0464ee8d0cdf8ccbb57032f7871bb5eedd55c6389327fefb4a9f339aac3b100074e2def915622ecc82ced08f48c523f3887ac83056e6ff3450c3d4d0d9543508	1	0	\\x000000010000000000800003b48e5c1cec42daee9792b78b8a2ca6403f28352a4a6f31a2d5875b0fff8e04b681be1633a350587544af849693ce6a8bc34b7b03c7b3020ad53903420d5f7dba45d4b62a2723f31202d223c3995aeccc9d1d596d9b7ed5711fb7ca584a82e20cb162994d4542f4acbd5f4bf53e2dffcde3c2a595782ac0265d88f61449ba627d010001	\\x4d9ac91838c298844904eba360459a9cfa23da2ebd194f5049ee0bcef93aa82261ecfe9355129988247397e91d1046b91055d1148cf3a6989e1bcc148d690203	1653847843000000	1654452643000000	1717524643000000	1812132643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x05341e4597ee72f05e2a37719a951595aad49d83b78fbd73d7e74eea5516e63842525515572a20bc3146ed23d5152b601f59916656d4442de406b77123bfb239	1	0	\\x000000010000000000800003b494b90cc463de79806ffa100667fd3b16115ca3fcfd9ced09d321678281f8e1fa968b688b005ac610a508d0bcc3102bb1082af6e1a77f6319b0c12f12a9026ead7293b657692a7aa2d983c0a70879903c5fca1adf3f0b6e3cb00920b97864b20ff00ab9179e8a5efa868287d95f7c02285fcbd632ee2c6dc9b3c3d8d4f00467010001	\\x84a81bb63adb0d8682e1da01e41fe4e40739fe44770cfacadc16b09310bf7b05cc05c06d858129631962a1c36d9de549ed75f9b074047d0a0b581275f2914107	1667751343000000	1668356143000000	1731428143000000	1826036143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
5	\\x0858ad343ba9f1fd642769259e918e5144f2ffade1b5c911d0dd4cbca253abf87df31acc177597345b5fc929c302cc4221c66306ea712d9fd1016aed3de2f504	1	0	\\x000000010000000000800003d0a7edd8c8a48240082b80f10b84ea10f62eb12ff9ca28e08a22da24638b057da2b86c5356e9fe470007dad6ddfecd8413f830b029289370d4c4307f8b2f34dfc86cc72a9713ff001f41f3bb90be5c45b71d52189fce7520a1e2831a4755fb7125ce2d54b8f1c23fe22f442a84a03765dc5f8ea7d646f07d318091e27bff26cf010001	\\xdd46795791d752fbf749899112b104200a504198d5ada8608c3c37ee58b69b55d8cdda46d090001a22c0197154f54de70bc8c54f9dd814e5bea4a316b40a6c02	1678632343000000	1679237143000000	1742309143000000	1836917143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
6	\\x09a4ee52a5485f388c12cca293aef28dfe71eab2c5abd41d1157951f66e962fe104408cd180f4c15d86be218f933314512098a341ee8ab6546def234ee5a7428	1	0	\\x000000010000000000800003f96ee351e29230bc7872273dd07c8aca2669942d790d35a5363c9f0e4d86f2e5bd4e3b67fee50567f1658ad530f01805fdc44024b22643095f8138908001d21d3a568c782255b39e42e70df2041954e9131ff6bb4de9fb4c6b084836a3ce9921598c24729e55d68aa40f3897aa22b2a85cec43b139f15ae0d55ec1b7ff72b5e3010001	\\xb5430b3962efee82d45a6d24e2c793ab24cd29f6dff3e5c3c3c7e727d8ef7f1a7604d8502b3f24ecfbc2fad750cd05a036f6c2eb1b2508886a30962b07768e00	1663519843000000	1664124643000000	1727196643000000	1821804643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x0ab890235bab8636755a743cfc47a40ceb7df11da77d938aeb87acf307c9b4f586731b56c3a0c84709318a6feae7f77e145ebf8f1f756f6cf8a5c1bbf537deae	1	0	\\x000000010000000000800003c4e85150234db0e7809443be013f770a84fe2cf6c707a1b94d9ee1249d2b81c31c4001b645860638b5d08a291b782b0cedef5a1c50469f7f8e4cad4913b577dfce9c8cbc04d221cada66c6b0a308a991ec39a9a361b2e9a9ef961cb5286856280c849d5b5924230608ac7a0fc45d624b3d4a73736c8db0261b3c4dfc93b4ca21010001	\\xeb65c71ac38f66fac43ae504604839c331f940486ad58586678e693f071df6494ecd1d649f8df8578d18433da17d745bdae62f0de0c2b5bd58da43d6c4e9d50a	1670169343000000	1670774143000000	1733846143000000	1828454143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x0c54eb8f81d6ed224b17575f63205d1dbafbdbf78bf4116ee0cc3c4a607a1159c1ba41548ccf872f6a110e1127c10124e60d6d264aa5d05b720e10e591541528	1	0	\\x000000010000000000800003d56ced5cef9c7e05bb643b1659d5b9b96deeca6c77ef620a0b21b8b84527ed114218b7a73e0a739b33c063917ddb35e0a54bbf3674f76f3a292ccaefa24255856de48854a17744b8f487d8aae1bfaa6b268b80a72a35244480043fbda39e0368ff456f0b48f0bb03c31254734e42e3d2d4328ce03578c306015c87dca3074c47010001	\\xa7faa1073a7010fefa2266ec5f56a160d4d27dae2e859e9b914c2eb236c7a1917af5ddb8ea6a82799f434e9f8c0998eb4dedf6e43e7a8d032fad92c49f97990f	1672587343000000	1673192143000000	1736264143000000	1830872143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
9	\\x0f488bce85796e468c8ccb430c0553f654ddcb4d1d54a3d1b29cd3fd2a8566903377fa476c7088e03f4423ef77d34c5b8126223fee0e43b0b2642e5a67f5079f	1	0	\\x000000010000000000800003e73c4b4b2ba8cdc12fabc5fe261d4d68e39e330a4b2f427d2c679dc06c9b2093f6ebc88995b0c18038601a61d656f39970ea6009c74da39b4cb148fe0de13d4af720d52e6f5a62e697fc672b0fb116ba87023892a23d1da63949553d412fc562120cc9cb542dd90471e9ed43c8b65ae35b1f28a21c8ecf4b5426a1d72bc51c39010001	\\xe1b82752e5d61e6dce1cda904673dbcc6b4176c933a73df8ca7dd96895c050af1c412a33f9cafcbc0d4abe57cebb2e4f7b3ad09dadf5a715004a7ed0f43f680d	1661706343000000	1662311143000000	1725383143000000	1819991143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
10	\\x10609eec57d1f82243971050d18e3d0e010cb7607966632aae472031d365b88e46d6e6bda6aeb76f8cfc68996172d62caa705ea6a33080dfa0d17fa59ebc8d09	1	0	\\x000000010000000000800003ba2a0b74d57ee5cb57feae4938eb2338f8bc8a15798cce28f1ac0ee4cdf6eca88d5a4d2274fdc57b30af6768c30a6d1f51c0cff61266b923bc4bc6d8c7c5757bf07e843d4c43b1bddf1fa0da46aaa10a2c78bc59a5c949f6f1ce10e24f16578de518f046cfd2167085a9051cf69ba5383ea18491783e0a09d966a2892e8b0517010001	\\x010826df389ca05d9f9369383dcc903f05dfdf3cbc89f20c59483da12d8862e2d433e683d5e4648f769d00066aa7eac7817d2bb51d609b8d9b7113e98b97db01	1671378343000000	1671983143000000	1735055143000000	1829663143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x13f4381b0a00c18bcc7174a6fcf5915970e9ae701c4adebea24d459ca85cc6cf0683147dcabbe65b5ba5b0926589961e9ffe04d16063b15df8d2c7708f3bdbdb	1	0	\\x000000010000000000800003d0487caefda12a266cb72060101c792a550e5f8b7faa61f7dc7a34a3a3214518a3302ef65a4d281557396813ca7a6c7c735bdabf34c9bb05ba93f22a22f09632c09ebadef2a5318a09b8da9473bec913840c2328fe318780f00ff26d35109e26890a561d0662cb0f09377e1834ece69df0a18be0b1c80d592077741162212097010001	\\x14cc469c8ee5f770d42a93281c3fe1cf88a95792dcb3db4292de7bf15e5d345c85479bdd5c37da613d9d0a7fb06a8cbdf488bb368a18f4186034d537843a3002	1682259343000000	1682864143000000	1745936143000000	1840544143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x15fc62efcbae1f71c5beff36d06c65f3aa462678820b25daa5756acf5f6faebb890e03b7efdf5e2a8fd1db3ad97f06b97ff6df5bbe7b846bed91e06293525d56	1	0	\\x000000010000000000800003b5400b28b436e01d82daab68121442dec0e81a43462eaef051e2ff0ca4cd75c830a2138a41210b1507a1035f265bbaf2a79d1ad01b6cae433a4932c0a18a1c21914729d8b4eb2aeec3abadb4799d6b1c9732a3d9299ad0e24742c49689811ca8e14dbf93a6d1a60b14113ea6bb812c3301239cca786b93a81f4b13f65dc65ca3010001	\\xb56e777c149b49b29f0ea60a3140b842b450fb200ce939bdc0ee30a37a33db7806efea0ffe3dfdbaa529ff42315eeffb4928a8f7214a90750450fd699ce8100a	1676214343000000	1676819143000000	1739891143000000	1834499143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x1b2ce4435894107d0e762393c2286f372743cbf9a30dcb0ddd3a239922f78700fc7c95a46ece54a5949977a1d23e5e3bb16916cb8eb01884b962d955c24b1a0e	1	0	\\x000000010000000000800003c4cd5859ac478831e1be39ad2b36482997f917a7d8bb73f4a04a1cbf88fea7065992b3495446d7d66c881f9f8f2d2d6b7aac465f9b161dbf418122e19e789a89422357aca3f4cd868b5c5e701083a589b44e8e814da2d3a1ba8e3f88974fd2275f31a5d384c9b48f5fbb8ab9b8926cd4dadfe0c81cebc4863795592d7a61490d010001	\\x973b6e77b6a229de2fa18ca3220cc68f3fca60d7694b6f2ec1d8505b034f6051f2a7496f33f647e9823fdba4bd8ac8ea261fc1048306a43c24e374e4bbbfa00e	1672587343000000	1673192143000000	1736264143000000	1830872143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x1e942bffeca2f3e464a4e625fcf1cc5e4c7b7bf0e10f844224721f2aea70bdc1b0e79f0593213a41f2df4337ca1f98ff37e3bdcfc838124a2dc36739648f075b	1	0	\\x000000010000000000800003d34dbe8eb94926ba50a789aa6aa3dc55a0f503d9e361323c47ab394121c0cb4aa8298f9520001fefbd0e41faec6e38eb3acd069b8efee48dd08a5a8d7f5965225d1a7998cba74656d132bee6e481cc64a024bb7a8a9b3e8eb7c895f3bc2c5f0179041b73803a15ba441f7f9eb69eaabb0110a18738bb0ee947d47b0e9e6ee531010001	\\x0d84bf470aff5571fa25b8691e4aaa4fbd28752533d02515c2eaeee2e4171e58ba9d8f637a19d9517229df7cd369be30aa143f8a5f942fd0a61f7c15afad6902	1679841343000000	1680446143000000	1743518143000000	1838126143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
15	\\x21e8df6f36c332de6f5f40710bd49bbca63203b22202e0f2e8bd843b2d3c40a14d4c4316538c9f6b0ed7fe895d13606edd556666c834e1a565be1307cfc834b5	1	0	\\x000000010000000000800003dcea4f63929ddad99fd2e3ceabff42868a5236100a85629beb250a5eb7ee49860423e8329fba5b910e9333ae1665a3d46d807ead818242e5225fa5f04b466a4a7a9907fd10000fead127e60fa442459ca5c96c6304e6ac354e14653be8e3de7b5bf534f81b040d8605fd1db541f95b5a68bdf082e1c5a4f82228e97d5cebe047010001	\\xa4d7c09d0221ea54fa7113d2b08b0b92a67dd8d4876c9f0a127794983311dd579940d2b4c2fda9e988f487a64fb069ee9a2134a4e2485b458da2c0d88195200e	1682259343000000	1682864143000000	1745936143000000	1840544143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x231c3559fa50cf9404c48d0297a28604a475845f87acf4a3e29a4cd279379d0b2e80620d50d7ba922c7184b89880fac47046d96f64111ffbe9d9a8f75e272f1c	1	0	\\x000000010000000000800003de3c9ebf8497c587e411f8d1ebf4af05e39efd491de7fd419c8de205fba4ef4a649d32ec5bfeb019297285fe96a8372d3e836f11cdebded8996f3d46b2484d002c16e23790d725218f1c05ea57ecfd4a54bbc51bfefa0f6676143f711507773ed6fdbd3db3f1a06e260309cd8f145cfa2ae1e93782f47c462b0022396d1c7039010001	\\xda2f0f89bb7ae0302172edea95e812c8733035848779242fbd87178ecf2c03c46838e64399b19ed1012f37a2afdffb607df60a5064ab036110733f9e7c8eef02	1664728843000000	1665333643000000	1728405643000000	1823013643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
17	\\x2458b6758ae71ebfd405ee1a5afae1460e92bc61f95039c3ea28df6b286ad426b793af77244f4619afc48b75f18cb2d94c15b2b0eb808d544c8f09d250cc6577	1	0	\\x000000010000000000800003d02da66a783f30882e411eaa727a9a62c53d83dca5939064c028d0fd3772feb00a1c33e66f27d1ad0caa77aad47d4b58c4903f691292d86c889b1c4fe24c0f97cebbf59d0331e4480f929344160f055b7aecf391e5f28c55ed26bfb535e8f238a3f851201ed7259e92b380af4f073445de603a0bc0268430a802292a1b90d475010001	\\x879c0b6cb1254164ee23f72a5f8a748bc02ba665684191de358ab8a8cd19b0b0fb6e6156bca5cef00fcd0fbb7575a33a5ee82b38cd0974ba613c98444908c80d	1656265843000000	1656870643000000	1719942643000000	1814550643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x260890d5b72c3ad49bdf7e92528fef9f3398339fb55798a0feb0491d9a1eafd5dea491932d191dbac60eca8f40908420298cdfb3c6ea524f71d996b81ea2a28d	1	0	\\x000000010000000000800003eeefdf434417b93f71bfc8d226d9e31e043caf50b6ccc7e2848f782106ecfd61f8a1af061e00b228d405caf5175d019ae6ecf561824527de9d8dbab55971c113edaedef59775080fe2dd50bf3540b15ae3953c83d64f0d363bc3588a54ca781404eccd7692823f946d5bf2ae03edb3a9afc577c210fa0e0ecd55032632768a2d010001	\\x7a513dba6a46b2f3886853c9493cde55f0d5e5b37301ee4b26e39b30e40176da1b7ac24bafee667ae81013cc6d8a647443b206b2d6c65ef0cebd1ac21e1b150e	1679236843000000	1679841643000000	1742913643000000	1837521643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
19	\\x2848f57c8026f9f9dcad1f0af55919debf769a5c840f4ccfc2be241aa4973e77d8e1888f971723569a0872f315ce569909b30be43c26b993059d04c71364164b	1	0	\\x000000010000000000800003a35620b4f555836dd4f21548ea1ae7c3748f4db579fcd5f38a28ff66bc20a916e87adb5ec46ff208dd02d154e903b12f8d9e201919a7a8ff0837aa8fa258e9a8a623f1320d204f5af6c70fbd6e7a3c94e4aed86a7891edad9c8aef518b1b025d98fd8836cec6b65809425487b811f55b7377fa0636e65c4a61ef76eec2391895010001	\\xe0a5c57cdab42ef8d32ea051b6f0b8c650488dbecef97cede1e96742f85f2e37cd28a32be61b2f54a6440576c83ed18c5b058740274b7183f23020315e94eb0c	1652034343000000	1652639143000000	1715711143000000	1810319143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
20	\\x2b10f02f83597a817d93847c1dc347bd35887371c5a7532be45dfec8e4ab5ad7a74339774b684396a6c9dd09952c5332a3d1a0ef35e3c7709a264070638ac03d	1	0	\\x000000010000000000800003e8a2e44d665f6ca64b8ab020cfca0e72438876504c3fe956246bbd433f93d0a62dc1ab931e7ba7147fd0d94737107939fc6c309a9030b5e8ffc86fa7cd1d04ab958badb90950ba37d538feded32e5bfed980c565ca88f628abc6c941c579bb0e3e6ffdf7ec376466b1cb521b69c4d4a09fc26b444b342ee01ab0fbaf2c426d69010001	\\x4c40658cd3bcf9dab00097a5008b433ed948766e4393640a397bcda69ec227e23688cc0447f34749b948b2a6bc100dc3c1a6da4d69c942866a3c1d914ac79c09	1652034343000000	1652639143000000	1715711143000000	1810319143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x2c446794bee6e169136c5f0de8c4fc4d9153272fc76e5941f53625f1226aae6135274ac1559e0344a88909bb296526a425b14032cfc21170849ff7ceb701b3e4	1	0	\\x000000010000000000800003ed690d5d1277e77423b32a6c6a5bd03d9f505a1b8e8b658bf0290dc174c79adc085cca75850af4c4218f81d9302fa2bf7db385f0ca29373782000972bd7110b9e7206c52169de535096f8b88a48281cf682a60c5f42f26f144f00b25b0ea53579eb3b8b76c0ac17ac336452400787b0032182b8468dcae0736b367e12ac1ab1d010001	\\xaade483dd7d8982bd7293355296bbe7cd8efb0210be511b86d86894e45ecabb55dcb95579d7165fcd6e5a59884f598a0a563855be8a655969e9eaa8af469f309	1652638843000000	1653243643000000	1716315643000000	1810923643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x2c08f27966c2f5cef1e676affea6023546e2f64e6f32aea3f4beca28998031fb999da3cd6f1a48e43a79acde58288dae69da40ce0131a760729211be186e8b90	1	0	\\x000000010000000000800003b60876c046afd3f8982a97fa01882db7398af7c1b7cdb2d733acad25170f6996901fe1033e3a15a2048418f909087a068a0654407a26d82f9a8a5a7061d63e3fc8bf9574dd063d269d54d1e7964473fe096b65b91961565f1ae9e110ed4b259c98b97b144e070b208b75f9c0ece8b107478a5b3f73a84be493d400d3f79ec1b3010001	\\x17d0f3f5161b825d3de3f4b0a267c74c1c4834795791e96d424a3d8b0fc7ea4b924db588c8227e85cd1801f010e70e2fe20ddabc19ba4a1c50f266f1598e090c	1678632343000000	1679237143000000	1742309143000000	1836917143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x302c0f4e3995d515704b1e59c9889241d71f1cb8edbb53427845925c4d0b1e7348e318c1d6e350cad4b51978d2efbcb68f9f45213dcdf758d1f2a1d1cf2729c3	1	0	\\x000000010000000000800003b3b49e504ca84d801b5974e83fe1710d970b2d420d6b939c3b1e47866ccfb72eb7519d4a76afd8b97ef4f4cfad474ce4f63c103bd3413cd942ce67c2ba0b9e3e6a25e4ba68d26d0d7ec8dd6ef18412550c444740b81c0c7b2790b260f8992caf04a8aa3a304532896881318aceaeae17abac5484969727896bfb8e9983db3611010001	\\x4fabc322a791235e5d92d8debcafb88eea4b1b24f15d45d30d49a42b7459f993b08c232f7d13c2a193453ad70c453cd66019ae4dfbdb0bb0107b80cf6bb75f02	1665333343000000	1665938143000000	1729010143000000	1823618143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x38e4d2c4a561aaac1d69ec0cdac87cbabd7471d72bd774fa9f05b54310d92050e5fb984c3a187f1bb868d8014683a224644bb80fc9dd12212b20f95928fb70c0	1	0	\\x000000010000000000800003bb92a42af778297e41e2cd567ac2eca8e23bb56f657130e5d8446f67f12da4849d12ba612970d01dbae29f5451a0a3c9459a9ebd18e484c14f2a43abac7e68ff0b454fc8094a8ea2a42bc89ca23f294326a905b4cb6ae7d36d17e5d3bc12bc20a4dfd8a7efb2b141b7ba6d603d4ab083bd010c263e7e7806514ea86369ec8bd3010001	\\x7304f2175c8b175664b6f900f0693e850a86b1dd119d1c3380fc3edc3069e60142164c71b9b3f4a219ee51cdd5dda617ed0b84516a37b219d237b26889eb4309	1658683843000000	1659288643000000	1722360643000000	1816968643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
25	\\x3e88274c56fe81049bd1fc364153764e024ff57bbb60c142c0ae61cfe620d09b9e3dfb7eba26bd5b1d9cc081d32e983e0c0995ee1949e7afca093fb7feea5b65	1	0	\\x000000010000000000800003a6e9e98fe043ef39257c51f52359ee2f969d606638f044714e68b29d03aa06d767d5dc2c0861b296b2c183fb0f1b517bd64ed0893ddb6e0449bf21f1dcf9cd74a29e37b6d7327819b1a8269655c3d4b3d3283dbc56db0a8205b11a6b6ccfb2bd54fd6b0f79b438ab45fd424a861b98f9a2a159a4f33c10de44076f86fcd8ba23010001	\\x6f85dd4f219f82fd17f81b6c661021ff740885ad0cc1ea6ede121b0c7dd1cda6ce0f161a83b190bc1b90d05ef97255960a71708020b06f036d2039e87296a70e	1670773843000000	1671378643000000	1734450643000000	1829058643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
26	\\x40fc6aece5ec306d6a810a825e60e68b38aecf3b1dc8911f4b6844752f3e8f4a3180900c6a6dadb86a7d37bf356f37893b99d1529bb70bf391dda21a0de17997	1	0	\\x000000010000000000800003e5db7dac20e4d7da9f8249c830542c90c6e9c4ba3d80569225b042a86a6a83a2b2b15b9499445fd470f7d52e27080afb928e0a749096a36a8fb07926810275db28c350c038a347924d95dd108ef48872cc20ba305c95d6c5b45ee9ed6ea856bd4136bff533c9d671b4dcb6c7b69cf2255a679a8756c0d640713c7d8c9b50bcc7010001	\\x3629c514154ec59b2871e783bbdcaf86b9a1263b166b174dbc97fa9931062e89103d7debb767818cedf6b5ed16ed8001a62b2a1df0e4d7f373cfd902a7f6b805	1666542343000000	1667147143000000	1730219143000000	1824827143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x413c407de29d145eb051fe3dcbc7116d52fd6133cd3c80e663d2a46405bd1744ff8bcfb8e8f68646e2f10eacf7fed6469fcacc66cc983d4affc272d44f1b39b8	1	0	\\x000000010000000000800003e5d5798fd8e4510d2384bab6b0a5a9b52be7d305f5a09c895c910e931229e66524a1d56dffd8c5e89366958bc4dca1973f672a4edfc44aba5824a69b3e4cd2dcf658b6d46ed8936efb9c0af88bfde89ef231212e814751d39ecbf036fb7408ad7c4b310fa07ffadfc8f2e17f3143a6147b420add0d2802bb588be5903b9ba805010001	\\xe08512db31c6251f4b26830f76c0c723f9fa4b34142ca5029b025860b90577911b7e90950122b078e1468218a986f168b3ac746a0eb734af292b01de0eb92c0a	1666542343000000	1667147143000000	1730219143000000	1824827143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
28	\\x45146976cc68038b3a2ad96bb5490b4aa8e21b39ac8ab912a87f00bc5bac0fcfe18b6817ed593b63799c6081bef81749d644f4454b0b7141cb25add799e8a387	1	0	\\x000000010000000000800003b5a159bcf7234a1c901c39361227171e2be63f68dfdcbf4cf3fddfb1bc147c7f1c557ba624d4bc2130a8373e43e08a671289b19888f4b0475a4d4b5aee66f2feaaebca3b29935fa00622c0fc866e8373385a64709659b057fcfc80deedd0c487f9e40c76ee97aca6ec1446083a3caef53fb9e4783e8d55bc63e21daaa1c18abf010001	\\xae69ac7a28e975d7151557de50bcbbc168e7eb9f98eab995c613d3f9e34d335e1839c83d682592dc85a1208c545e929bc8debe9fb4fa3fb5de68eec1bf6c2f05	1675609843000000	1676214643000000	1739286643000000	1833894643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x47b81bd166a9c4ae734fe906c0f03144948618c36ec02b6b7e92940778d6e646da911971695bc79725a56672f7290c54c1d604e28e014c4197cc155328ffb343	1	0	\\x000000010000000000800003fba95b94fbd485923a2c7def4471859c37965ec139312a469e151619cd3d390bab993179c0a10cfe81d7e5393c7467b090af1b8113e55b197e00a238f18178ac805e05697ccb27e0deffb417c67dedc79edcd64f2b29e1f2f18ceb34791a2614e126141c61546cae343e06229229fdc3486a7854bd55bd706b403a334daf86f1010001	\\x8d69636be170543dc8642f906ec3545af7031298ad728fc1d2e75938949c32dbb6037f854ffb66d1d56da253ac557fe7ab8421ba2fd6b9a38a513d1bf566db0d	1653243343000000	1653848143000000	1716920143000000	1811528143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
30	\\x47ec48b2164588ccb81e9ccc62d087f4d3be9e2d41ef22772d2af05356ea4f40191b5ad3e0416ef730bd48dd30a90006d9c7f878c65178717d2909261bd7e599	1	0	\\x000000010000000000800003c44d95794df94ccab6ad40fb6ce0bf0813a4b7aeb859359db6d736aedba40982f66be7010e677cc67d36fd905db9ddbc29634285db11351b114e4095501a848bea461eb2d59e4290bf7943f00634c2a4447031387bb183180a416ab11030a236e7a328b2cbcf52c70cf7021f59924d031a906eae238a3a215c0bc49bbd737161010001	\\x11f05d9f609326e7f26fbceb65b6e559939d005b92640e02ee0f398ad7429184c1e6b039f2e6c130a9c2f4c9ae9dc474610206ce15d468e07158710cf8eacb05	1681050343000000	1681655143000000	1744727143000000	1839335143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x4a6401848aa6af9cf2b7044f8052b61f9030425e2bb5845b0fa2cc537c85ebbd7210f585585e2295d5602e1b53c2c525f60d028644856acece625edefad04dbd	1	0	\\x000000010000000000800003f48a33ed6fec2f52942ad61e45fd77b3887f70ab7659a7255034fdcb5a355fece3553762d24e961c439be1e7306c2101e486861a492a42bbd7213ac941bf6cc178ced0353e03d0fb4abfede5a87d07099f3b9a185040a8d3a49716d007fb0b92239d99d9a26d8d990af6e27cff32c5f8a70afea4f508dbd8b3ee90727a965231010001	\\x6f24db61af6850e1a4779a4d61560cecc6cf15a753c29ecead150bd64ebb5b81fa813d49beff8b4e2d28f0f300dbd78a9535f7609aea58dfef12db2cd741c605	1652638843000000	1653243643000000	1716315643000000	1810923643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x4c9855f896ab0fe33b5be07523188a141de2b373ed6a84e67431d8949ff83ff16a1d80b037ba29f87f31bb621e7c39ef16b816ba10df30622ddc4bb20284b134	1	0	\\x000000010000000000800003b962c6d292245b9a300582753e990d0924ef0f0b2b30dba92fc638753a357b8923d4e926692f98ba8b26e1f620058fb68a6114f5fcdfb63650b28845777b58151d9f1f43416d5a1c72215858b579ed591944f372f5c76da8ae46d4f0d8741b54fa8ab89f5fe27a1aefdb0f9c2e0033ff22b536af0b0b5382489856f03e7e0bcb010001	\\xd0e82cb095e3d25f8856b5bdbd8bc21be7f306934aa75ca8b925dba8edc2a87b5089c220765d200797297d2b3141a983c4af716130a8ed0b1122847755eb2e06	1676818843000000	1677423643000000	1740495643000000	1835103643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
33	\\x4ce0b6c412e5f1000be4cac35355e3121cfc613f4580b3a52ec6cb0c8d623384985c69a84a7a9e3b7abb243f5fc5aab2d089e2aa3a1ae60f040f43f7292882a5	1	0	\\x000000010000000000800003b29d90471cc3944f6d9efe92d727f1fbaa3facece9795451649dc2b04264a039ae7212c337a1771072eb0584e5d1c9267ddf9b8d11fc3a04cbdd6aba6cb719e04b5ebcd8840cd9f78ee42f057d13b68ee90bd5dacbc49dc5c606e4a695358b1da66bcf09bfc77db03078d243a114754eb5577c0220e768c8404fb34258a00487010001	\\x3b35e1a172772e303eb887af43251a9ff5e324285f895642442ed48ad9ac81afb03a3c03875effe1bbac7f3946227ca3067d9d0534a345408dc0df258b7bbd0e	1655661343000000	1656266143000000	1719338143000000	1813946143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x50d8b9afa54cae9655f2475eaeaf805561080db5439ee7e978c5d762cfe2a203696bedab162720e8f282a47eaf3ebbe0fe940c6b1033f6bb9d31245d36b499c3	1	0	\\x000000010000000000800003c5677acb7b680ba71c6c7e5ea8311432274ca2664c1263c43bf96d4c69c8fa3d691fcad875c94cf14447c9ca5cbd45ac4318e43bde9d655250fa4408558aa5fe35a2c5eea51aadbe3af2469ecffec769089c66b271fdb54cb4d972de283d2ded0841777852de9150a5e14cc8cbd77e7d5e2bcc4540522b9f40710e575009330d010001	\\x6a4ff3f0c1dcaa73387066310f45d6f309656aae4b7ef2315e076f996508ec4389a2f8677e89f9d898389558a0dd41347e5a369bf4e3fd3e430b7cbdc30f1603	1679236843000000	1679841643000000	1742913643000000	1837521643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x50302a1d318653128aa03c5d10f611c50c3a8aa48cc5e7e7aacc3afea276d7a72cea0fff697fcfa05fd03e26a5d89e28d012ece7ea4c4870fa1bbddf83a7b86f	1	0	\\x000000010000000000800003c6ecaef3e5b50d788c44a49acd4793bb373ebc720275b7b240cb048abb082a3e0fcfd102523526bdff5e70a8191194a298988b0039dfd3a4ad47e723038a13f78e7880016f36c5e948660128e5cf7c4485f6962cb6fca67ca3e57dd46b69ea65fc77c66270d3227e6773941f52757399239f2886c51ecce746a928d442414de9010001	\\x773d918ff6bb8589f05a438f181a8bc0de24934d4c5beb6ebe6173ecab34378fdfe2a16fa9981c0403c547b004c752b5bc0419183ccd546294b83b8e755f1808	1664728843000000	1665333643000000	1728405643000000	1823013643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
36	\\x515436f0a578a8f218e2543acf9ad42de47596180a9f8cc2b2d5dd28222785d32f1d801da359bd873f30cdf88605587ce755416a380ce24fdfe4fc56cb37c524	1	0	\\x000000010000000000800003ccb238cd6b40203422cacf478592e5d3d247d752d14a2d3e3897bd680d9e46254d7ca3804ccf1faaa784d1fda53217badd47841fdf1fe9a1859993a2fbba0f35046dbb26a0807e7718e8c8de99309f6d175a25aed35a1cc6097f66552595c34bf358a7d8a131b38a36aacd79ce8dc764e61159ece82fb2098269377fcfbfed1f010001	\\xf5891929dec0a4fa464e2a61f4f725cb7166c825f4eb34e794c55d698ddd6322157bf7ce8ec38035435681b3833278c59d29de6d478b69cf89e5064f9f8e1803	1653847843000000	1654452643000000	1717524643000000	1812132643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
37	\\x524c2374334b3b19919350f1283a5c74a3e490a8134e45b3c93010808d15e4e7829d37c3e2c070a942b5c4aba42d14feac4ef76b78ef3cd33105bc24d2d70955	1	0	\\x000000010000000000800003ca78de8ebff10c5f1aad76ef803db47720d88526a7f0a4c9edc8656305ce293a18a2ba3ffea233cebac0e1937414a9e5f11ea7562f34d563203868a991dd78111e532bd177a510318d84b8cc7cef0690d22e216838ac3c4d48717b184b7153f381e72ce5a98874dd132b9ecdbd974bdc4b64beb05b2dc7e383029e5cbf0267e1010001	\\x3bcaa0a12db0cd8054bacbb3b6264f2df3e38b7f14dd3e601b41021421425ea0ff3487dc77e7afcc5dd9ee5046cf97a09a141420c51928833b1c28e50f127b0e	1663519843000000	1664124643000000	1727196643000000	1821804643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x54980285e3818b39139573465f07be64c0357ac8f8d245967ba671b3140beb1dd58fe4193891d10d255e2c0361b62fde4d5d9d09a164612b86160ffe789e66d1	1	0	\\x000000010000000000800003d356d485936a26f028564b2463489639ffb61b0a9231f2421aec031231710d6b8741d6bc950c8b4ddb35750be120321c265aaf753a2066e8c52f1397aace207b75f9bd112571aa27d9bc425e4e04cce8fa2ce22f867a6954749422a3e445409ba9ff4765cb1457680e20b3a6c839af2934d72c4db258d85ad34223286f71fcb9010001	\\x41653c415952658cbc2d46c4cf0bbae5fce58a3190cfaaf72046ac1bf1d9d20cf9e6a2e866fe675f081fd4a8617975601764bb61315d287c3d566fd2f0e7460f	1658079343000000	1658684143000000	1721756143000000	1816364143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x56a4a3ab12879cb46e2aa91e9a1e0d7abb58ed37389ac2a5b5c33212fb70aeecc51b1a41f1f60573fb10b25edfcf625486e9d4581386de132354a491daa6fac9	1	0	\\x000000010000000000800003a6bb0b8c549cc1bb62394b38ff113901de9d0f9ea37e366720d599a48ce8ff44523b7b35b7e54d01f87541edeb430e3e75819e071113d92a8fa76704e48cedc007df9efec9be5ed08386bb6a2a6f0dc2f66c72be6ea55dac5593f9237dbd6b0cdccb6642ea1b1f940294771f1cdf5b97b00910f3d8d1910a53c2c6db07e467f5010001	\\x0acf7e4380824b96fd2cd2822eac1b7691d8d9f26f4e8ceaa4528b4d2e5dc4435f8912874f00e1c1d9e4b35633531cc3009f0c1b57fd152f2b58f0182f5fb701	1652638843000000	1653243643000000	1716315643000000	1810923643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x59bc8929bec380507c52e852e11274b0bd55b8b2a899b7fa464e8d1abc06d332a3219c8e45cbd91caab70b02f7f9eade947bc598037dce86759f23616764431e	1	0	\\x000000010000000000800003c70969bd1cd97e61f7016508a8b4810ca05f25b7327f02c898bef5f1dab6af008410a963321c67fec9927b26e77c0db7e8387d7a9d089d4f0532cdda6d35459f6cba9ac018f4b514ca8f733b7c5b050c62327adce10e83af2c72b1d57c13baae62ae0a2be7c506425dbce1f94bf57498055335534e0f2940419f17da884d43f3010001	\\x1a26f2a7ef211f54bf8a3055504966d8bec487bf4997b2500cc36d9e48be4c875e2d2d23b7177a854b7b305f7287fad48be595547e6d094c0acf64a3bf037a07	1665937843000000	1666542643000000	1729614643000000	1824222643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x5a8c3bb035fbd5b6be9ea89ca46302673aa5210782c5ad563996f920e1bc5e3f443dc62b4e720fa4d998de31909ced9aee2a075b9b29240f7bb9f6dd237eaa78	1	0	\\x000000010000000000800003c1c79fff8ef30e0d80de1c92fc75d1091b65ef5fa380d8dd4b2fa742dbf96b60a6c510d7401ed3ca2daf37e512053f92ff5af9cb83f1cbe15c7a3d003d1a160ffc5eeb040f5402d5d3c779e04fa730547ac8fa82b2380196b33b9b70be3a77289d36a2620b0ae80beb1d7cc9fa44b890bc707fe8062cdf2834081975b114939d010001	\\xf74a49c43d22a3b1f37ccebb480738261e6d8fc9af72d71a066033e79dcf88cd9838991ce768f005799f4470d2cc6ef50bb12702604c988d3104d96b0031d703	1669564843000000	1670169643000000	1733241643000000	1827849643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x60a868f436ef89d00d2d6ea8a6e39c695be84a0c579ebfcb62caf1c70b2a4e6625cc48d915da1977aa29a2fad3ad1e94f9ff14b4255743fdf5347121e05e9e5b	1	0	\\x000000010000000000800003aee5083c9b287e2f4fe55d68eee261ac2bac82c4c05f6479ffea8bf87ce4decadb10789e23b696181fe262c36a55f2a398f12d5790739c29835fc56a09c793f5855566152fbed064afdb1f5ab5a2cd20e585ed3f495f720dade399f5489f7ee8890409298d1b6e8d5d8176caa6f9c1b198dbae2350ed6ae450d0b5fd6894cd2f010001	\\xf0dbe46611f19666a17869a2b42e69d4d74f24da9d1e309de1dcb8090b1ea143754b37ea0424074d1b37bcb2ce717dd281c9c734c4c549deb27a17103a445f07	1668355843000000	1668960643000000	1732032643000000	1826640643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x605cb89df1048f5ec5b645a434c9a311436c26276cf9c3cd8664a1ec374d112cbaabaa28e99d2dca834a908dd8481415b8a8e630a27705ca548745e789e622ba	1	0	\\x000000010000000000800003f10d024e8643130413d477679d61e6555e70fa16808a991f9b015f58925ab90e6baf2e8346fe127e6ef1c91a073c98a7abe72771cfc0e2573f589ca799206a5b35d30b548a011636aca78ea7fce0701942fb572b0302fab4ba9528cfd302093138c01905e6e8ba4efe8f918444287e114547701329b7629f747f4ca67210dd5f010001	\\x4b1bae794eaaf2c07aab974bb2b7037ff0f4b1e1e2060589051ba5ee1273a5480a13334708ea0181cfd3be7bdfe17b7bda98d31304f4193a35ae85250ae0fb0b	1658683843000000	1659288643000000	1722360643000000	1816968643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x63fceaeecbbbc2dc4f08dabd41181047b4be393bf769910879a1f3a33c99ea8bd21b1a892f09d9767700381df3ebfcf90a4053e50aef219fa39e18a31df89f2e	1	0	\\x000000010000000000800003aeee20660d323d2241d1f7c08295367b215da26fdc251ecee6d5c91e7c27ea210cf566183acbc5b2ce1d698907e88fe0546f40705c03fb4577c5dbac10c227b58fcb42e47b32c261d6981ab9554f6de75a72b29517487934ffb401ef524d36ca72d9753a7fd87a0c5b1ccd5d9cd50a4aa7b41504a05786306f262de2a4b87579010001	\\x33fd38777095c1679acc898c536d2a5f12dc2a16296f886c1fa73505a0064aed15dcec833034c9a569776aa111702c2153e870d7cbba5b30b9d97da9d0ce0d01	1681654843000000	1682259643000000	1745331643000000	1839939643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
45	\\x69d84377b2e628bebd6cdb7a3768d62bac1c2d362b25081179bc2d7085ce5e7c96086e30f381bc45b804a4b4e03bb0eac8f9129ecea5dcea2b01e26e71bfa047	1	0	\\x000000010000000000800003c518c20ce1dcfda75da905089df104bcd4c7d3e3904d323ec5036beb62c4105fe722b67390125604276d3915f03928b3cdd52e18dd1ab1bb35a44701ef94741e02b18bee196a87c85157a6d942986dd0a0c0a6895b12383dcc75a07fc559e7ce97646b246751e4f1d61a3f5c4221fedf805869749f0dfba6e51a18be09744575010001	\\x0a63797c8d32512e5af6f3554e397ff1cd076234ed351a681a15833d7c7f21e01bc43f117d5ea5fddaac50922a90aa403372720c16515fc2e45f5ce8d57e3308	1655661343000000	1656266143000000	1719338143000000	1813946143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
46	\\x6f8c3b44f99f8ae706463da972f5a5bfde31ea1f140a646feecd56833a7fce9be80eb05a7d6ddb1c75c57a25239dc75fbc3117840af22b529aa6d9c4194eaac9	1	0	\\x000000010000000000800003e64ca5a3e29139f222da3876b3ef15cac35261f03b09e06196ce9730fb32f3fd63bbe9c55879b7675907b7f15ed3a0edeecbc40d34b02eb36a98373a58782a29b45780fd738eb185020efe8a3c61c24aa0d7e2b73f836a19f9d60cb56fd90d26bf64d59c9dcb60e5ba6f3a6c19f9e034c96152c83aaf32845130a8f797d751fd010001	\\x6b568c565ec3f2a00f036f1935e43b4c2b43c9c89ec79a76f599e0b0971b70db8d1702727af4774c77b57f7e76fabcfb768db47f9991c39bcf1f3111b7b5930f	1679236843000000	1679841643000000	1742913643000000	1837521643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
47	\\x7488ed58e4e0b35a6f7b28f57b9913dc4afc69e1f254d528e43d627024882480c0da904a4bc8623146da25baa95196b7ace9e3449e9cbb21f8232bcc80c4eae6	1	0	\\x000000010000000000800003ab9a1d6b70245f40fed2bc69cdf77ca425413127b3ce72274c74155b662aa74f05d2bfb15bcb2cabfb2c007ace4d03b706504e2eab3e210ee74428a73a92ff2a9ee7daa35e98be713a5936c33a013c82be5c25b2a89a5adf9102d10aea2b68db6bdee3c21e559beeec2edf78eab0452668c4236c466ccc66fd73d8832636e1c9010001	\\x6aa76819e85688f9792afe4a5b3536a321853ea4bd55795b8c233bc8ddd43fae4ac8858b0e7cd088e4f6aa9053a601f481018c79bf6c3291edff34bd116fc00e	1658079343000000	1658684143000000	1721756143000000	1816364143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x7460fcfb343ddcd99c24ebcb02919de1cec9cbc21e413f3952253fbaa183ec2e23e3e43b3e07d027d521a2968cbf15c17133d618d69506a4113a32f8fbe950e7	1	0	\\x000000010000000000800003ce217af19f2730c21715f10a86a98a1e91ad4f01c1365be2ca02c2db51a6ecd5d97abe7aa76090fd696fca706c48c21633dcfc32f9d9a2af9e8cf2fc59b5c5dc0c129bee07c4f809dd89df5329a7c578116724b46622f3dc6dd05db16d9b5ba633f02740b3c8a294ef450a938f04a1b78f16bdb8d9f41f3d04eb66b56f08b1f5010001	\\xee8cfb042c15245476dfaca8bb274c35e1a41edd853171d1b4d298ec03c2eba03431201642f605332b02ae205243f23bb29803cb4d52949b4afc2bdd3c09f404	1671982843000000	1672587643000000	1735659643000000	1830267643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
49	\\x74189437af57b970ecf93f55e6a42a3bedc6a0e7c1daf0d5dd7e5423c33b6c420af97ab28419e4d2c062c4711ca0c9efe1421aa42be2b0051ae4f0785c2aa3a0	1	0	\\x000000010000000000800003cab2c4b0fbd4591c33e434355251196f269e6b21164db9a156b00215f899fd26f04b25305b325053a54b308bda87131c9b5b703731fa543eede138a712b8dfb95090ec98340907ffd3b2ba0a1fa8d8e5d06a693be4f3f83ffa03166da058d84f2beb5e39896e4bf2b6e80df76047ca5451280ac5f41f129203cdae282fa40dff010001	\\x941700b2fcf6e86d69944e1d2bad915e4e6fefae4ca3a349c2e27fa107bc6581209c1d57b6a0a176e651bec2c0070f0bdd7a12942512c3993e313f4f3e4a8909	1652034343000000	1652639143000000	1715711143000000	1810319143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x74bc63c7275f8d7bda885eeb5c40a13c9d7dc81c957c2d92dd5dd9b7425f979e788d98929288405a04063b09ad64bbee23d204474550c1886d3fe65f50686f81	1	0	\\x000000010000000000800003ab76d297cbab5a627a8fe8800581cf471662130df8e4fd49d418a343247b9c0f79e1b425d1adc4a7e8747da0aab7258b165e83d6c63711ccefa9ee48312980d2f43c82afa4c092195a725cd1c1a9eab359359255fd281ec99e55eb0a38bbb11f568609c43cb273061e6a2d8767c9f5ad03edf5ef6e784895df9af37af6b7d2a1010001	\\xdf4be6eeae3e1801bef296e36cf19ec36a2df839c6089099d70879748191574651404cf6be8b04a67253740886db7c854fd7a937c6f8123c96977ccee419000c	1655056843000000	1655661643000000	1718733643000000	1813341643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x75ccf7ba1aff3d3da963460c86fdc68a042ffff6118a2bc17bea6d07c75f5d331da4e8f631e2dc4f96ca550119497ba41a5705174c628d6a0cf9f8dc788b632d	1	0	\\x0000000100000000008000039ceddbde11f3e3043dc6f7223ffe77aa9893f541fe7b906bdac5b858662b2af70254d2fba34036c91bb940716c6232d60817bec91a7446fa2c3c524884cab92c91148d69ad8995a82ae798b7520c5fac9d54f2c63ef6d359a32c35c926cca927c46b386e08cec7910551c0348d36d207c684c58ebe2af925dc7bd9d3b0033bed010001	\\x8730644635f75d32fa14310170fe93bc29fd52c1c3270845e9bf0c48b1793093ba059c3f58e5be0293fa84e7c9e9b2ce94431f18da2c06383338da073aa3a709	1663519843000000	1664124643000000	1727196643000000	1821804643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
52	\\x77809728f56cd6143101b8079c9657c3f164af238039b778e6e795bbd8974d55143414fb3d19f5f9b62bf8429bf757a015c7d3c4ff8b8675f8c32d77417ad710	1	0	\\x000000010000000000800003ec9b928e64110f8a49596b04f8a46a986d8841f9cdc12cb2ea1836e17821dd680a4e0b5eee6fa228549aa7ceae20d46333f4a5a2f4e997815fe715db6d807c8f5e40af2f9c18507deeba51c99dbbabef717a3797da8c75ab952b6e7f530abbc804ee4aaaac1e582cd19b7492430a892979b4bacf649d612db658e77176e62a93010001	\\xa4b3ef51ea958fff6a55f33a34e50367753e1c57fb4d043fefa84fdf153ed32d243bd0911ee2922e2c73a928a361a06ed5513796fc036e212257ae35eeb0870c	1673796343000000	1674401143000000	1737473143000000	1832081143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
53	\\x7a98650d730b0cb8df24f0e33054f01178c7d7311cf3b4896626449ef921053b43ab1dc6a35806eaf30c394a14e2f73d27b728e8aa4ad028a717ca1564b2e471	1	0	\\x000000010000000000800003c27ecc5b51fcffc379fdf38d48c8842cc962932a10e8240300d37d7dd888083beedcb292ed00c6ab600c6571af4f5a0ca5610e4ada5d9a70c1dbc86e9120926a396f71f178fa71a575105abf53a001264d64f375934326860971191ca0458aa3b629f02c3d84c069708b5f4131e30a03bffff44cf5f0158f780f3cc830f351f5010001	\\x4b9cdf82ce5b8cea66a248c11cdc4f7a56e5696cf1915d66c6734f2fdc42d16026dd056c5200be93983765b827470f85cfc19158ab7c07309157b68c3234f408	1653243343000000	1653848143000000	1716920143000000	1811528143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
54	\\x7b5844bbe66ff7e47463a5bcb328d2bd6f8df406f968b0634e4b4a372353a36d1835bb38ad50535b35328cf2e05cd2c2f2b73dbbd608d1982bb4e37cfde0d096	1	0	\\x000000010000000000800003c51aef927b599696a31e6b400fdc0965f8f561d0bd3053acc82d1bb7cb4091fdc9348392d2b81330afeee93c7f1c7141753d968104778d07afe06aa7974b81ad868832e89311a88495ab3b9444044ff8d534f730946fc999bb4d81d0de0655041648c64142f740b2ad46b62cb72af5be6ac99ee3f5f9eb037e3994bc2d609ec9010001	\\xb815a926f3aceefe3bf25bceab6a8778dff84ce3d6d096e61335d8d0af61b0b05fd5af20ad812d214273c1a111c90fca6d34e145bc3599177ef6efbd906dd008	1661706343000000	1662311143000000	1725383143000000	1819991143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
55	\\x7c5072d48fb2109d424c5c7974b78700a2a3e652eeb21a01b95b04f3e3224bb436b7c89b042a201a64dfbf7adae27a4181a31783d2fe0d6cdea5991558b60603	1	0	\\x000000010000000000800003d8c301bbf9638904e8ad87be5bc5376274efab9d50ead0fff242d2a4d5c7156adf9ea1ed1422252ce7ca2eee1324b449a4480a09d839083d00617f174580acd78bdd91b3b048f0ff106da8e7e802986546165ee05605deaed136b88bbe10891451393d492b7406c7de5fa1e3b1f90d7a377b3fbd0b4024a9b961e94b10f605e7010001	\\x29944272540ec8233c0bc925bc81beccf2b29bc871dad2ef3ac79e280147603a3cb551508e7d12a502e3ba2b11e832d38ad5d3e9553987a09fc4fbdbefe25a02	1681654843000000	1682259643000000	1745331643000000	1839939643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
56	\\x7fc4bec0ae15da8ff0f15b350310557fb910cab4ecdcf336556de1336e8858c96d2b8dd552a61989cd416a3502b545bd41bd9e2f5711b74ec7ab1b78ce35f05e	1	0	\\x000000010000000000800003a930a45983377892050fea12d8bfd33a71c2944580c56842feebf663341e07541d36781b1500e35b6329422c7601c7ec7b3293e7a955639ba69a5527ae12258d53ce9785b89d8ed202c2af75c1d52c17e8d3a024044949804ac82ffe3f394a736907ffd615ea12fe2a6c6d5b1432bfb77853eb9d53b54d29db121dc4672af5f5010001	\\xe48f6ae387a3bf682d54781e5639025908a014a29356d2025f5aa934dc8a6e66fe9b11a1e8c10dbcefdfb539931aa51d14bd336e92bef44146405882b613a307	1675005343000000	1675610143000000	1738682143000000	1833290143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x80b007f095ffe6e8835408b271a7551d486b9827c4f55baffe98104da1ce18bc135cbceaf7351a70db138961eb73d2dd42dd7100bb3a4ca7268e4d1f236fd8ec	1	0	\\x000000010000000000800003f0be25e9712782924280098d7761a7dce8c97637cbd18d7c1d6588a06868f9423f5c85f8132a14ad5b885b8f307972d7c7859addd1789946b886ba896af18acb01e7633fdce9a403af9691d1480a58044f2e1d170174be6686fb8dd1ddf39eece92de17ec3ec08de500ab77d8a49b6e83a9ae0ef7ff18dc4541905477f643b41010001	\\x42eea87fe2ed6014c72d170720b6d0f6b02de4c5f613b914fe6fdb8c57bb4d13290c8e80f86632edd5c8e32c9e4776cb037611b989e0c3e798ee0ae9b9faee0d	1680445843000000	1681050643000000	1744122643000000	1838730643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
58	\\x8610367bd47b664343d3f1d44479a922cf812c99d84800d8812cd754f5ec281a123b3d117e5af4fb061feb910970d2bbd4a2c11513d0479dda5afc01a2aca89c	1	0	\\x000000010000000000800003d4cc0cbefb8af053f72ebd0ecd52cca5e099b29b308874cb6142e0bee1be082079ae4a5e171f5628c90b6d77f09a7298414cb53c6e4a966da5dadb144eae8ae9801278ad9d7e407fd251e2259c2f380e36a2c342de4a5cbdd29650fa1b2e1029e123cca9e7f2d8aba95df3dd37b4ae3ef676bc0cfe2dbec6dca06b0056d20d49010001	\\x94a571023c6dc5ae685997d03f44c340f703e5ba357723203afe6c301d4d4d19ecc09f9d1e1ab7bef6c33ce3b52c139438c41fa9f5de16a44ca2e7d63027760a	1678027843000000	1678632643000000	1741704643000000	1836312643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
59	\\x87801cbdd5cf5aed0591324a113441f39a2b3a560a46b5243e506602ac1b6fb69fab979da95c0d315c6bc720bccb262dbc349712253d52c81c47cd81d4cbac51	1	0	\\x000000010000000000800003b5d3590cfc514f6016ecd5a35435dbd7a4e76b923fe1d2b1d7f6014d9a891366bbe73e2140c7ce447ffe9996af3a6d7ae0fb230d39649fe1b4a657cb115e2b7510a41a63e6659f445f507cf3976b03e3975f862579285a145562775abc114b1ed0e64e4533fbb05daab97e61f52557e8af537411a61fb3a60084b46c6984f9d7010001	\\xba335d828d255500eed958d7862719ae341b9c15d4a341c9b10aa6dbea2f9364247b4d53ddd40b15710f47c3ad00cf43e53cf778b509dec41131d641fa48520e	1665333343000000	1665938143000000	1729010143000000	1823618143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\x8b683c64ea0f0b7cc059897ba697cf2f7284869229687b46182c860ecc5c341cf203995d74ebe78a4e29d643e2cb79b1b2c4c689de4f6b1a216b43b8706c47c1	1	0	\\x000000010000000000800003b71fc62c38b47c36a6260e6d9d34f041e1ae62e0dfc0ef14840f5f5c24c41893a73b3a9415af3245f7fdda9313b1b2bdc6bcaef52da55567c1079419f973ede387159198eb16b01452b9cf30d16541c0503a16d092eb3fbe89bb1af21c584b9d621df844f39acda5dbe3de3172512e0b30ece85d1d891d84cc5338c5624947e7010001	\\x612004c702d3b74e5717cde4112d1d07c99d378e7b4356abf47f3d500a71eb5b12093774399ca8f959e3b47647779be0abda32e0945a24dd2fedf0998da34406	1680445843000000	1681050643000000	1744122643000000	1838730643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
61	\\x8b9cc7e598e3415d185680950a1e75c5dc82c0a1831c8271d5980c58535c7cdff293eaaa8d828f98deddf873065e74299868d068df7fb39efda3447f926b1b9e	1	0	\\x000000010000000000800003c27e03b5388fb2fcaa5a201f71318432b51d5685bf0e40b069557b3eef10cb96945dfea9b926c18b7c64eef0dd37b4bbb52fc3aab20458493fcc0ddc9f58608aaaa62ef2bbd0d4d838ef97427a3f588f2891733d51632f5f2f5f1668a708876ea9b121a8d71a859ea9bf53a77a531ac2e251110dcee83d033c703703ca28a7e7010001	\\xbd91e318d390fdbedfe8a52e16d8c7a10becb9d1bd380b95749a3fae6880a1aa9c4c1f3b3d4d851418ec80cc5ee37da4dd081a602645186d22e5e01b5101f907	1665333343000000	1665938143000000	1729010143000000	1823618143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x8cdcee3797bbc0edf32403ebc10020a0ccf250063cba5736d9245a0d1b6fb67bf0535d9624f04ca50fb9e8e4f4c54128bafcf9c94898427dc37d4f24b33cc073	1	0	\\x000000010000000000800003b0182d9542129ae25e8049266f508513ec29a8aabf562fa8c8176b8b017b5edee469e02e1858a57b4ce20a16fdead01ae6c5173a18d3a7bb3ebe8b62d08ce06e45bbf797d05b73d7b65262f59527ee99a0d0a79054761d9f37dad66077443ebaaca38da1598bb833f432642551ad59af0bbcf4347ceeef3a07b7f4f215f6f721010001	\\xf4ecd5d63243b99c2300ca1e460949fd28b35d0ae3d6fd1bacf879367fdfffbddf9b68bba5916d912157122029a5c2bbd35a7246b4d3087e6ecf569498cbe10d	1652034343000000	1652639143000000	1715711143000000	1810319143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x907c23f6ebcd61104879e64d35de87d18e0b3641415a6519391ec9af0c132b7fbf86bdf059f5aa5ee6c8a1ff45c1f90a70891651c7e86b25aacbec2bbcb70858	1	0	\\x000000010000000000800003adf7666694b35d5dfb740e7c74ca4e60c67c630ad183cc222d515c2881794c4752111e104e0a7edf8aeaf066c286595757ea8b55b335d87f3f8ddd8874e3d3c9c05079b2b33989d6e763e868c5df2e7541f9d6f5cc1fff3b3fe6ab5805bef702192defb2f620b895db2d13bf7508c9d5e173bb995006a117faddb922b20d8621010001	\\x11dbdbdca4aed48d674560e59daffdd6327c01c0ddb374b2755eed2d4bf5db4ca6dc918c2830e5c95d23f84acd2791a6aee726abe67ffb5e3f50deda2ae3320c	1654452343000000	1655057143000000	1718129143000000	1812737143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
64	\\x902001056958733d5583e4ced4d5f9fd54681291a37fc37f3e92821691429d05e035dba4d6c33fa9b3c68b09d5e74bc8c515b503931d7aac9bfd6e415beb9a2f	1	0	\\x000000010000000000800003b229d1f3e43e980b6a6ba3b943b4dd1d81dd057750e5efe1253655e324ee022f9cf9ed2e5acb53f902648e1ed793d23ca52a877db2852b76bd498da3dfc689ee548cdb9b938b1265536df48253eaacc8bad2c13340bdff0fe8efa22be325ba40a8e6706ba913726dc72f64a61542d2f2596f567e3e51d4cd8aab809e88aa416f010001	\\x7b0384a2e47578f47f66bafc68f161d2df4f7f9f3100b179177798ecae1f82f4b000d0e3ebf23296e457d66c0c6f1fbcc81e5a8c8976b6bedbfa59c1e374e800	1661101843000000	1661706643000000	1724778643000000	1819386643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x9450d861fc2f3a9f44942b3b668589bce3fae30575fb9a9298348e2e1c82d4aff6985d2bc9bbcd8aa3784560c7bee668efe1327956bdf14c6ddc1376a1e07bf8	1	0	\\x000000010000000000800003cbc02ed5d550eea036721367436f1d59ae635007f99d7cefc6e3455e200054edd0b148d8be62ca4d5bc8654826360e899b8d50fb2849c9148c6bd5f9f0ad08a8f7899e5bb3253fd5476992471625aea5d38a6b9f4b7cdbca7f373e4779b0ab78e863e5a6512b0b2c961a399656e50f32ec2e0ebb7d6fba6c1cf5a3fbbb3d9265010001	\\x321fbf6161aa2fbef0ceb612a456eb3d070c9899ae36b2be8d7fcb58ccf5b97223471b41e293b31cc699d693b18a17f0e7c4c6b7f249c8c15ddf0804c84a250f	1659892843000000	1660497643000000	1723569643000000	1818177643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x94684ed1fcee3a148affa7b7f60edc736b4c75667b06a9d1592f4582ddce126410a0739e5a0e40bf429bde1b2d7c28fe69fabd799ec35cdc56eaf646260cdb2b	1	0	\\x000000010000000000800003e31d99eda96ba9d85ab63774276455f3575e6b22220f1629f11e1d04ec065da6c8af0228c6bef6e51eba6ff1cc935a1616a15f0cd6f42c26ddbc0a881ddb3cb819aad50f72041c1d84bd5d700833125e14f50bc623ea7b549eac70eb27e5feae63188316baa41224270de42c784e1062ebf2c278e91d6e9868aa82d02b0c0c0f010001	\\x88e0b71753fa382b3d8420c807b2c2c79c5e76211eef9e918a71da4b1ac85d6d9cbf02ffe800f82542843fd6cda09489c53686fd2f27015b70df0926bfcd9f0a	1651429843000000	1652034643000000	1715106643000000	1809714643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x95a4a9aaeb9cbed84458065deefed8b15fec8998397062675244b9b18341cae65397d1fdf1ca2aa307c1f96c529aaa4d7bb57ea189a8e56501a43b276fea359c	1	0	\\x000000010000000000800003b1b3b58de0b5addf9650c970ae36968d172a032e708db6fcc5d0f34df061e781b1622e5e8c9c7b70a0d139fe1c088897f8debb0349e2393ecdd50d6d0fa8444f0a1cc65ecc12271d38151e1dec11d449904449b1d2edc0f7313f4ba16971556bd727b80f6f5ffdfdeae888bea6bbc7ffaa6ab336982b2785d32fbb8640332677010001	\\x96336a25003ce1142684887766867dbdd1c6a2acbdcba9177a5f8e848265afe4881cfc4aa27472278acc20c5308e6c989e20fd3fb8938a91d2100992c8cce100	1662310843000000	1662915643000000	1725987643000000	1820595643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x97c474e6504d01d0917446a4e33962597651653255fed26fd219a228d6cba82d9c33ed75e2dc2e54f2b3591303861c6bf8ee367df267a96f261e8c4dfe345560	1	0	\\x000000010000000000800003d1ad8b14c1b759443834d30ed01d3f720a8aa18be0827883f58f492198dec7afd4a8532333c918435e5563389e07a3ec3cb568ee6e5b1c2665988625939cba7ce610222fc26f5def83a70915f1fe77e36405f66817f85244f694aa8371511e78bb0912c63a61e5a16761adcc2a6e5c1819ac9574ec8dc686c8f7a7bc1555d12b010001	\\xfe47bf48f210ec6b121ad7e461a12edc071cc05062230013f059d790c9e09db7c452be115f94c67f679bfb26e66a8244ce05333e020d9bbb012df3c236bd2103	1653847843000000	1654452643000000	1717524643000000	1812132643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
69	\\xa15cabf36bea71334f9c74f3d3a46016a91a84c42be77fbe377b5464344040caae518e1577518c2640f32a48b667cf36fa26e6ebc245c77d644d96ed2ba94ebc	1	0	\\x000000010000000000800003b1075d2fea182374c24241a546fc894ffdc25129f533f3a6c1356d6c51d328b3306ca36587d596aa4c0891496d1cfa0a7b9e1fa7f42befcb1730d1b77f58a1f5b69727ac6f0a40a5455af7d02a1daba757fed8a556e373b2fdfec792004255ac7ea109e29babe9b03d7cf5345a0ea114238f6259179f22aa2a201434ec145f71010001	\\xab485ef23c7cbd218e8f0b0a96b604cf884863b860116e6f7c927e507784ae81f0fd7322dd81a4732f3e402ee2625886f83d8b4a813030711dc3fae9fceaa00e	1662915343000000	1663520143000000	1726592143000000	1821200143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
70	\\xaf58782bbc2d57f841fc643dde5a84bd5912ef49b9c825e1d9d3d72b098742c7d63134546d32dc8547bd06f232e2b264e4f9df519ec513aa980dc13ac0d9e788	1	0	\\x000000010000000000800003cf77b78a6b333e7403354b6a04abc9d41182d3e00fe0e45dd5922afdcb66a9ddbad5babf4e3d10cf4709d5f02f407e1dcab33751a07c31745fa77d30cc6cedfd105b273bbee9abd0aba33299da9ced17a4c7559237db696a345eb01e7378146716c85ceb091319243f12036a75638f698fd1392cf58d6e80d0412f8eb8a2de9f010001	\\xdfa06dd5c559eb4b598a4018e5f545cbd909516340bdb6fac71b9e32504172c5fa3f65a2a92948735fee79494df6bacf1ec8dcb115dd04a96b70600fd46cc301	1667146843000000	1667751643000000	1730823643000000	1825431643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xb018d01b53b4b5b3a6344d192ad4267a6884583d36bb9453e6677fdd90c56eb47341d0ea6d06f5b638110f886f19de5f93b5d0dc3d3eb9f846be3dbfb9d12657	1	0	\\x000000010000000000800003d5017c763f5f502926cfc141b7a584e126efd37328a0bfef4cf89bf71a984c3bb1717a71c21adf2d8d81743a4142c18d5752b9d87f1d66a6e962e029fea9aedec6b29d067b316323d97690f12b6f97bceb640c2c5d910e8eb162a0fab6addc25a04e85820d6af256469876adcbd19835d0965406a376ade2179414932e883a0b010001	\\xa811cd1ec36891799339b6016a67877a81fed8a8c5e3b5ef124b54c6b213a41d03f96c9501a0f358a00c85122a616d1806ba83c4493925f4854f85e3a0ad250e	1664124343000000	1664729143000000	1727801143000000	1822409143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
72	\\xb3ace945fecdf274f4755cce33bf7e1e6247d0b0d59d015932998d3369110adb3f7165261e9182e243ca0455d7a5ffaa62d01a81552fc823cdcc6875b68d3b36	1	0	\\x000000010000000000800003ac1b59cb2c99e2c01e25f8d6197116bd5645940cd8bba7064acb4dfb19119a222424d369e555c327d9b089145a9cc0f6907440317c4fa1fc0669f4fd61009f641e4707ef55b0cf30fa9caf9269e3aba7bb7c0fd7816700a85a95f20c8425c49855e8ec371dfb8f7bbdcca14a932d5c6b6eb09aa4c9544c7a3c15588ab421acf5010001	\\x4d21cf86ca8a9758a9b7ef856378b7a275c7bcb455ecca6617d737cbe2ad4ac7e2534a6e92d9fb558db909e7185f5ac5c419b242301f9932ee54d73c04edd40f	1659892843000000	1660497643000000	1723569643000000	1818177643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xb3e4f3048340d062ab86a4275017b7b7e59b5063d2511921fabc4c4473c9e63705da1f40662fdcd4d42da998d7f3677fbda3a4fc6d570fc0cb68513dba0845b9	1	0	\\x000000010000000000800003a5f982ef644e16613765749edd76255993ff043de90250bb7fda0f35c0c7b2f41df66d4acfa1c8fa9099d15077926ffe49a8e9199aadd768ec92e8836a03be5c49f69acf9ed2bb01413658955bc991ed2cf700e1ff9eb921d7671c437a5f8a94bac9b2d911514345a8ab64dff1e421d55c0ed52e534425d1bed579cc599e7685010001	\\x8f4889f6d981f3428f3189c8fc794ef4ac4e9221168330bd4be557296735257b7caccfd442fc252979140f6ea0434bd0e304a4fef3c29bf4a174ea988c596202	1669564843000000	1670169643000000	1733241643000000	1827849643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xb6a8459dec521c4e6b71081edb9d28274f0ee853637e3064429bfe269e422b67dac8175f565ba7a03e6b7cc150402021d38a506713881a65ed4fb59235d1e2d5	1	0	\\x000000010000000000800003c48758f9a24167011b4ec929bb34dbedd871854d882cd7dc7d65034a7789cd2b056da22f4d8aeb181d078733421d4fb37b0993291e6e3bb89784786d94d3b780247fbaff72e5375b6687e4074ba7bc30d0d14bd9453a0c8c2e218a9cf6a8bf49e0f66154e7ccc551154971da0e667beec1b5206d2e25a1afe4e83c8845b41df7010001	\\x78ac6f8124c91cd5fed06b00c18a44d18c24fd86a3eeea6366c331237ec5f4ba2b6b8eed8ecdddf586911669aad8672200466521b460daee92207ebfbd77fe03	1673796343000000	1674401143000000	1737473143000000	1832081143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xb7009561fcd449fa77c687361351b59d6a8d0050977fb5af7eae4090c6549d1381c514ff38657f60e7b672c3bacbe4ef7e8b5612046a4db604bf5976634981df	1	0	\\x000000010000000000800003c90570e9081ac575a043075f2c2a2b339d21caf096744d7590c2622f89301df6ba92bd98e0cf1a9903a045ecd8c7a05df722b733726ae7bcdf142af007b46a6382ffa45f5d02f509981e5611946684ef58ec98723d05d6066953d748db2268c36accf20b1d2e6b9ec4dd8f212d450d8a859f1f4f14ab800828fe976c4716b839010001	\\xd6663625072f945762df33c1d744b631b5fdc3b1ccb08a2d72ff1613a9837ec2a1114139837a7d3703c405297095842901261599e1215631836397a1f32ec002	1664124343000000	1664729143000000	1727801143000000	1822409143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
76	\\xbffc2d38355813f609103348a7c2a1ac19ba4c64cbc8d9c58c2c1e7cc43d000bff58df26764dc1dcda4737c46eea6d40ee8b73e1857d623ff0d8e9ba63c7905b	1	0	\\x000000010000000000800003c5ff8f33dfc882e07f939f6c2eba4d3b4618a477f2e4b03555e96b309334307b0acb53dd5fdfee9753f18e8ee9122ccef4ae66e18045cba59b1659bccdeb5d98b3578e6ded9b3f050b790c1d5d54595f3743108574eff5ba5ef83e6d8a216ea4858c55dc1b8408d96fcc95b9de849208e0bc82b599fcd36bcc86926fe992340b010001	\\x2ab2fd7e7db9682669057aeedc636d0838526d88c7c84d17db0470ada886c1f2f86d286987240067e95364128b61082c91f3bb1227f25d3e4e2a375ca869e90b	1650825343000000	1651430143000000	1714502143000000	1809110143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xc2a87812009db9d4c6faefa559a356f4a8c545df92730cda3363ffc13f81940c4928d09c4c746b9eff714ef6d8c303765c8d924d2f27359f595536f38086a9f5	1	0	\\x000000010000000000800003c3fd1771fc4408ed4bd622eb96a129e200251dd93a2c109337fb002eabd319a179849600066db81e39bfdb624e7fe58e7dddda44229f923c1e3f79aa30cb6e3fcab03660d546a22ce6cf0c62c5c2ea4d677781cdcfefcc95e8265b23a122411f77dbd86db37a1d3c457ea475b57d367365816e5bdbedcf2b801a26479b84633b010001	\\xb094acec61aea950645cdb742eac3b8deb9cb796f599fdcdbc167c2a12c5d0e6346e513f4179b66a117abd1e69d76be0799720726be93c09ce959c3ec1fe0e01	1662310843000000	1662915643000000	1725987643000000	1820595643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xc6e0ea36de5ff4d26f62249fee524d0d2a0c21a646d2fae34bff2baf8694a67c8808bb40da135925cecddddcfb7f5cdc6bd4ae2048db138e1cf421ee64c10a30	1	0	\\x000000010000000000800003991cb108b4f55bc3dba0680fa0bbf08ac0e361de0a8a48d55f0741dbcb6e84e76511027cefd61c57715d36e25bc4d01ddda63b6acaf10cea03eade272f6217f241ed31981ebff273329a53de0b131e98fafa91e941262fc9e1061a8cb823a43762f24d7522b3f34f9d2c5be6d2ae76f6721da07550a7250ff8e80bc90fe1eac1010001	\\x6ede1625270d7b3ae367733f1ab4c8e59304aef11eb3106777f98bd3e145663421e9c46a0989943b92b1126b7525c16eef019d95def4857e0193974967f71e08	1665937843000000	1666542643000000	1729614643000000	1824222643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\xcc9888e3f400f399ef37fa90d6ce3b10b06e0d86f124827a64bd85bae32b1f3088e0e795309180e442423e1e98848cce37de21de336097d61fcbf1de175cb7b0	1	0	\\x000000010000000000800003a3d1c90f2e592743d335c1cdc5c02be146156c0dd259291716bd5b358373b8f7424e78e8bbe19259470b12cfc6667e30b57da37751ac997bf11628772e17f06299e826dcecf684e41b845e3d6ae266201b9dbae1a0f921a12817d96f643556d1744fc65cef8d02f8af020ae5e002eaf649dc2812ddaa7c0784a173dfdd463ae3010001	\\xf7c2d830f32d58e5a3207b506527dcf8798f451b6782ad17586b0067f9103890ddbe87f9ded4cd2c7ad481fc8814ada143382c084ef740d8a0ac83cdc59a800b	1657474843000000	1658079643000000	1721151643000000	1815759643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xcc74aa9f3dc89a2f661f68d52f96b7c5fe74295a49d11c5b33b716c6bb17607fe6df90a6dccd2741ed1d2119dc296be6f1de92e02771b502cca197deaf37704b	1	0	\\x000000010000000000800003f3bf5bccd3f6d4587365761a20f7c26617eaa0bb4908d5cf8292d4c85f6cb804f2839b3c260025c3baef3c443a6d76cfab9ba4d1b0abde57237322319972b51462a93897b23ba110cda175e4daf2138ec1073e5c0120aa517c37281ce21756bb41f962ae7d658f7ba47d489e274dfc056321df66693d99ff19266e5071fb7311010001	\\x3b28429dfcec3b137c3aa02275d85521e80c3df6bf21c3415e084737fbc20f3fa47cd32cb1a7718bf1aa57c5249b5a38eec1f6a23d5f1d37f314012862fa3809	1676818843000000	1677423643000000	1740495643000000	1835103643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xcf0014366b6f08e520c1ac67a8bb78274dc6685b27f5884b030ea3d900791fd370008abae783616ac8fd86479e9356d6e094acd0fe8d5ff694ad334eb9e971b4	1	0	\\x000000010000000000800003ccf8a4a37ebc8a954bc1738cb2577d487692b19efbe3e0b4f6f34bb2dbac5300b7bc9affb8908ff7591e8f6ae8b0f610657230f76b751414b3092a402ab8ff5b744c7ad2acbf6fb9f3ac95156ec57e2bf96918dff5230ead5083b10782b2c41f009141f66034c6463eef91e597ce32ec7fdbe00d33074273c886fd7c4935c55f010001	\\xb150d6a148484bd9cd8911d7452a6b2fb83e273ece0ab600eb7ad2caa9961b01ef88912b62eb8f46280e0b93a9219204b04dc8d83c3c31d567ad3049c097300c	1661101843000000	1661706643000000	1724778643000000	1819386643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
82	\\xd178a5c2c610d1e19beb2e58728aa9c1233d0d9de2a0b140c22340aafaa0914c83400257325049e0b23ddcd977194a73cefe550ebeed629dcc9aca03129f9fdb	1	0	\\x000000010000000000800003d0817529c9b9321c196a9abe2c4e72a2bba7bf2a51d70964dfcf3165958ff630d165ae29cc72435081c4758b0335bee879ccaad54cebaff07a2a3f302e9c43762531a4699f2d9ee950a0dece27656374814337eb7c017b10c45f826dc05dfa1caedc79b4e7487df847580a05847838ab54129db99aafec1f0295f9325ec885a5010001	\\x1b87ecb3d642d0d6ee6974116f6e69d977870a89a1e73dbbca68ccfab8ee2dc90b2e99c720614fec2b87938148a0048ebcc8441e7990cba4684830dc36f4960a	1678027843000000	1678632643000000	1741704643000000	1836312643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xd23c55819cc720df8d5ea9730f4166ddba3c51c208fd72ac97b74dad0ba9e5d85bc2ab09898c13a872bf46b44125b9f6f1a9019ec443f54f76870e7491f984d0	1	0	\\x000000010000000000800003cf7a1ac267427d84626aa858aa83b10418a983f9c8f5e40b47e078fee443d104fffe16ae7612135931e21fa6c02d2985f7d085b0dac6e5106469c48960d284ef68a9aba6ce7baabf958e00b965738b084c488c88c9d1cb4ee424382cec9f37efc6a507b20371a008ae93695dc1105ae04dbaa5fa0b535dfbd5dd5079259858e7010001	\\xcf065de1847ea83684960faf26759b7fafd18d345a6037cae9f60637526e3a7a664c660ce6cad3be864f28631ed75d919fe79fe919282bf134999cafadd5990f	1651429843000000	1652034643000000	1715106643000000	1809714643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xd4f845162ea21810398127bbeaa0e3aacc671e9510f26a1387435e7bb547dcc35524e8739b2902b92c89e4bc66016063951cff3b2d873b5c4fb9bb638bc36daf	1	0	\\x000000010000000000800003ac5b1c2bd1210c46e0feca9de26188e597d5fd7ffb237d9ec774aae1791402183d639553e08b68f0ef0e59b7162e5134b7b0e118ce9f81eb0de65552b8de7a1307a4e6e82175324f08a44c921ec79617ebe1fa6dfc0b1380962f4e7c567696aadb590f7054f95f557c046f9b795fd494f451ddf3e3533261d0834b826e1fed27010001	\\xf1c8d2c09cae0df0781d850df8f30cb881d4dfc94f34fd04bc85076e5686572422b9264cb80e956a54da93c96ca875e22adc6a494d979b55c954be7054a5ca0f	1681654843000000	1682259643000000	1745331643000000	1839939643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xd4501a7910525134db57e1fdfd37dc173de7ed9002c94d44be73771a48bf85915d96f3b9ec3f1eb2e49ca32022a9d4890433b5eeeada703160e5ea7a6c9eb0eb	1	0	\\x000000010000000000800003b827ead9aa96b39e9b7f8447a2a060210b783871c75eaf1ac29d9499b638cd145f79b1248faa4364f24238a07b278886869c96f63b7868e986d9126ac7eb2e84cb25e71a168d7a4fe4a00ff2077a931015450003eb64736ba9d8499b55524ba9445f2c8a51102c361ef0b4b2f2633cdb34a9eacf568341d5540a810a594a88cb010001	\\x71dbe5e9c76bf5443e39b7fde4f0584a2aa4117a8d12eb80846b0a818d680d482a7b582f5b1a52d2727d24c74c69e11412885f29c7fa7dddfbe723b2aaea6a08	1671982843000000	1672587643000000	1735659643000000	1830267643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xd8641db41d21bf7f1386fe13ada505e3ac1d00cc932043a3e0d8d133c977de7fd4514ed5eb5496bda89158359e3bffcd086f2d20d6070de47c5a830ab6e624af	1	0	\\x000000010000000000800003c2996c9444c782920dfd2fb1764df6b72bded164577841686f3f4b862e989a5b5685f1da1f8d60cf32338da0a41046347c4d953550b654d1bab514eaff7672fa7ebb94874b77fa22e9278696d5b21f38eb27bd2237bd70c5468ebd05dc85b6a05c6761049235f87a7c42b9a0edc32b16ba6899c293810e0222940edeb4f9f505010001	\\xee623950b2256e5e18e446ea3c2021d18bf04969d8da4e3d8a22df2b2a59ee33ffce3b56902d800cc08e022e42b9ee622d2bc79dba29e21bd3c9feee0bb71307	1664728843000000	1665333643000000	1728405643000000	1823013643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xdf0044429c157b50823e2a2f2dc578c2398302c71ade18de1ba3f54e41b1f20bb7e9c6603c61779fcc372d9da9c48c30e99814216b2f443da2cc1fa53fa39f2b	1	0	\\x000000010000000000800003ba1ef869b46eb94c47a3248341443b87f7243f94537941ef3c526c05a0dab545e4582f12668a8a681b9e3bdefcbbd101d9b95666dad2852a4c5b8657d1f77aca75a7e85c920377e29dc915621efb7205a25496e30ad13665d8a160b241f34c9d3b59f032fbd8b50cf7c508e9d3ddc8e69baa806766dd77bcf56f556d8fd67dc7010001	\\xfb1ad618a704a447e6c1e64f686a1bb1eb4ec4ad61b628cfc405bc9471932b08a41928e34f1aaf364aca9572aeee0d8ed19c98f76c8397c37a415236c465e905	1652638843000000	1653243643000000	1716315643000000	1810923643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
88	\\xe4880ecbee1eeda5d58763f10a878f74b69e3ec26569030ff6069314efbce9cfc6793954819ef4702d6867971f244d7e61110bff7ac6549d2d6a9bdb0dad2c08	1	0	\\x000000010000000000800003da8f2bcf279d6c8b8fe6cfb81872df7c168e735eaccc6da78b25922fa21a9bcbaa0c71e9134b5790f3d2086ddbdc6eaecb9535e9ab86902e9ccdebef097ee5857e65acac9c371a9c1e79d99a5a632ed748e47ecc22836d93e56876f24bbcae03bf7ec1ae33beb4dbfed714893ccfcbac0e450d4392768100c194b3e5e0394e33010001	\\x308c4abcf93e78110b9b5dfabd5d77c97ea0084a5c766190efd26335cfeb1f22bbadfb60bc93dc22702f90eb420d0f5c59b5736b8f462c64ab83dc7a91207703	1659288343000000	1659893143000000	1722965143000000	1817573143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xe49ce91971e6c455c8dfae4a0e02f708e599d0f365b6d75291077f713cdb33c1d362896ddc1c0fd680fc571b6fc4b304d4c45bc73a91bad4f3cefc5180b0f868	1	0	\\x000000010000000000800003f27e5a7e1afbb5ce9372c8b468fdd347dce38e1f95e1952468dec6e8e62ca8021f28568fead8521dc3c65f033d36ca8516f093401280fb46b772b0c70b089a72aea2dfd6acd4b341b67a5c34a5096fcc7dfd16271c83cae75c8489a3bd7a5972431e6904bb66e0b908f1f511df3d2b95e440b4886d2f2991d76896a9f8c78ddd010001	\\x57ca61a132cc3fe5b4193e15e9d786b3cf5444c64436ef0430738f87aec293efcdce8db3ae851c578b7bcf654290245281e1c6e085ad1215d7d2ed0d1ebada03	1677423343000000	1678028143000000	1741100143000000	1835708143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xe5bcc2db26aea11b42cf217b3fe4b262757ad0448b6bd9597d475912cd0f7924d2d85a6bb1338c9aa197176a7a8403c6e101573250b72eb6c47d6be31c6cca44	1	0	\\x000000010000000000800003bf05e3c4f3eeb4238b5b68e3cd9cb3b6731c36c478ba6002f75885cf28c092f5db7713f0bb88b1b6109dfd8e60c73a2ee055d2d61d8ac5e7f75fafd83932c2b13c3c7db8dc9e8702d8f9d49e57d685a060e587b48487450d315e5dae347ffeecb79adb0635f2662871e12ee0aeef75d52baaa29206ee3d7a863ac60f53bb70bb010001	\\x499221751b7b3e9148052251b4c0a2fac998247334d2b994a11ea3961b7eb42936c7fd0b109eaa0c4ffa7d1ed9cc93e92b59d0f8059077bf698ba30c08bce106	1665333343000000	1665938143000000	1729010143000000	1823618143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xe79c1463b2268a4db724e0ef6aea33e9b1f4b511a83c45112d3ee73e680dd819045c7d32d8e205b2e8e97b09d82cd4f9350a3fdf05558f41995415a0d791dae4	1	0	\\x000000010000000000800003af6603544a3eed63f7cd633f076d4f3247b1f0ba59e8cb3d99ff687db837d640e4fa4b32c889fb64944ef4fd4a0603faf9a36a36929eeadb24d8e88108efac42ad1e4aae7104282adebde0863a329820847eed4a95f833f3513607ef02d4a4ea764fcd6c5956627a546be94dd6bea51287a448736dda99d9daae249d0dd85e9d010001	\\xb404f5e39b478230e32c620abad758f3de9a00de3b96585ed4dc17564c73ac9238444ad1d8285913b7e46ccc3feda2ab738ce018144d27124a15d720d154380e	1659892843000000	1660497643000000	1723569643000000	1818177643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
92	\\xeaf85dfd3cc53d74c6a91f0e2f8973eb675e36fac2a0766a443e03325d399d69667111519213e8f9692cb2ea72f71d9f98597f731ead87e3dbdd7dfd3fbb6be4	1	0	\\x000000010000000000800003cb1e743d13d4c884949e757b6c7eea8b33fd062ea48ae341e8ae5bb6f4d5eb807e0f53966f110e4a687647fd322bbcb85a248c3db96710bf72fbe05fa3d9be4e5ad76e50ef07aa7c833273c5c7c4c4109a7b51cd56692da073499ad3c32dfd17dbe5de4dfb5a1a6df6d959455c6221dd6d06f81648ac1893b9ce519519099293010001	\\x008e80139143a901621addcc18def993f4b5846cf92f8e6a9e6d2cd905fda52e82b61fc3f3aacf424d7901f6b9791d0817d1968d3132923b0e81519e80967908	1665333343000000	1665938143000000	1729010143000000	1823618143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xec50e0874be5fba48617c3cd10ac60a6264fa9d85928595fe286af6b5e40bf8254637b6aba89749f452c190a0765986779f6db0da0913019938915089919ad0f	1	0	\\x000000010000000000800003c18bcde83f7378035da0a7a4c7726b9278f2bf35d3f7e11e7bc2d2c14eb64493028bd3597090894f7a3992bb0e7de3176685fc6752048f3c60288cce6fcee474ba3fee59edd1bc9114f973d28167cbf0f7d529c61407f98cd76d147dba7c2d3c796a5cd0ceb1929f7fcd9afc8b175a5471c3e4335e0fb1806e69db86e18825f9010001	\\x1eccd5bf88d1b1038eb02144a23c5465e9820dad857754595a0178753e1cc2b8f926b5ac777d2dd164888fee41ba2e746c48cacbaf0edb90c9923d762793e306	1677423343000000	1678028143000000	1741100143000000	1835708143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
94	\\xeee099f6b7deaca103f0f5fe1a28f80513a1eeec49984a034289e5b7e25b256d7e426f1dc1a83c158b9ed67f33cd16fafd5daa83b74a63f200217e104f00ce58	1	0	\\x000000010000000000800003e1576f0670dbb1dcd18e4ff2758181469fbf9f7a9d17c54d1c06c9dbdd5f0be77b9e47105b570478e255c375ab0b984c5b36546a3df2a15386929d5c266e16bdd231b9e3f49ef31ef2c9d740e5bfba78f4a7a4b5a5808171f1743558d71575b9d9008bb24747db6439b1c4d06b46687eac553402aecd55901619dd429f292789010001	\\xe0088458c6cf88daa8e43f8c195b7bc4200995fe4c33a66d84bc95071865d26421d3c36721709f77d2603831895ba7e19e8c118fe9d861367bcbdbb88470c00c	1670169343000000	1670774143000000	1733846143000000	1828454143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xeeb86d3cab24a6fc8a3d064c3c20f685dade85e9a12cd8813a47d276fcee541e41dc7e5532c63363cb8f8353284a67df6233bbd53d9a582c02595b0404905b5f	1	0	\\x000000010000000000800003b7bde34ccbc7569bb85531af1b13bc58a4592c764ca24b67bb6ce786d303c63d58b4869364f4b74620ad068390909d0628d54ebb53d4055a49c512f616f1d5ab0f2f239d0a01bf692cc312b58bef45b32f6ee6f2f43cc0f1733c4fba5979aeca8b4496251fe804c93ea340d867f78f46547bcdd2047d7f12138068434578a6b7010001	\\x9cecda77180ebdfeab9739764b4355e08df652333946409f9aa599c3d8f518b3c2d855e268f9fede9f44b75f7a233a42fce883406cb4b94807a3d701f79f440e	1657474843000000	1658079643000000	1721151643000000	1815759643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xf2f86f296e2876037aeb75a441cc9bbd55f99b667cdaadfb14415b210f695d3fa87f8342e5dede3a742b25aff1187f9194be3715a814c28a4b524dcebca2c521	1	0	\\x000000010000000000800003b8cefa151bca6d63eb25ddac7047a5fb2d3c0d6457c0d2e53c64641c951e7841024efece382fca3cdefb19d76cbe8e47cb10518dc43bce8a6010d84e5fd3ffaf953c369d9ed5379c1f4a60e1390232eff03bda8e945dac27fd09905c2fc33dd7d97071eb67ee30a461e5d3aa22707f114a2267e3951647c6cfad5481f5a10315010001	\\x5ae5288a4efb7dc24fc610454e8090fecd1c3e7d27f4d74e0db0c4856ed7eb6acd99fa52a9a34f74aa213cbfc0dad7a90a4e90dfcf2925d9c9c217e442ac6e0f	1682259343000000	1682864143000000	1745936143000000	1840544143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
97	\\xf5f4b9a5a3eb924bd4026d4a025efe8186303859d18b4d2e15a89152934e455460e33324bd96897013c6ab2d95be5b145456d36ad3847d88f2520eaf44f2b92d	1	0	\\x000000010000000000800003e7b742f01ba7d42a0c8de22a6d4726b36301f5de14ef60746c775c1b7fae8c39037dbb2c2aaf3fd45cc3fb8efc4c5a867269ddabd51a25586f0212f15a0ca6b4c64f3cc13b06e176c2e92de6f69016816ec48d0f880b70f686b7bbd9131024263321cd9e951f883febdef481878fba547560fbb3ffcc00b76dc039e5f23c2799010001	\\xb5afc9658bad9b55a50cc7d04ff83bf231919e54e3479c59524a6e48e226438fed92b4c2b38f8e5273fb464d1e99ce9c359c6895d6f5ac29703d812a93ab650d	1676818843000000	1677423643000000	1740495643000000	1835103643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
98	\\xf7bce04358df1ff510485ed71c609ad75d52be7fffebfbd2900270c2898f8e8253912a2c86b466173bfb5e2d2048537e045a0891de5b1486184d8c96119f5590	1	0	\\x000000010000000000800003b0c4391be0f09ecdfa892083108814ca9a23329a918a9d9c21714db1109bb0377ca2cdf1e1036b4ec9bded59e7c991e77a7c3681c439e59283087f037f821e3eff1879743f96163a11693099ee96b5bb7d69812e8cf273680b597f622418607ad0d2f449182d8ffc779dc2c116057f33c9426b7ce36fa2d8b7dd86724dcbb625010001	\\x2f0fca0d0d2d57036b3f79df998465e3ee29fcd08f8d688791bb67d0f6e7cf108af13a6d9424863059d6fd53e32eef72b7c9ef0b142cc73ae26181eaecac8602	1655056843000000	1655661643000000	1718733643000000	1813341643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xf804eaf1aa2ec6e32036c9106e0a271bbe286f7f4d196ef63b5430d76509e46aef0681b21ddf207ff9a632ee93834cd047c128d22700aa44ad8c60762943df7d	1	0	\\x000000010000000000800003b7c7aab8c2cc691dcdcd276f37464402102bfd42644a8ddcb29ab2e3709e7c868293a0dd3fe4b3f001fa91fa2325368a5e3b3e97b2cee867f2d4e5506e38d6e148b46324f794aef4280824bb2f825da5bbbfa5840eab1699044061dc8da54ffc66e9037f1df3cd9b58c1a065100a3fccd69d5995a7f1b33f304e914d8f67a471010001	\\x031f57c52d5ae692f225ad1f8fc4865855be9a81bc2caa436f6f37d0ab721a69356005695da0803efef523836f739480c9e6da4295c6a6f6ca4ea09b4f80a304	1657474843000000	1658079643000000	1721151643000000	1815759643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
100	\\xf8f0c76bbbccd72f50e0f14bc862916ba2a93559e3494492112db8d4b9e6ce1d54ff61c413943715bee58620750395655a8009d9e2801ad18e999a2cc5ff640b	1	0	\\x000000010000000000800003bf5461107668c37cf3aee5d2a86d6e823e0f1dbca10688c0da856d66be2f21e91e95945a6866876b47c73ac693d10db93bf00599b488fed1842c22530140b0b8804c488c55e873c671be40fb526315016903fe0e08b47245ba6abd7d1b23ea4bb87b68f08e39d5893e0cfa390ff60fb6335afb0b037a906227f6c444bd47f09d010001	\\xbf86600b5ea0bdc3d7684dd895232fe4ca61eeae4ae69076e9050e20bee20e8b09b2a0b22a99a9b28258c378593a32f019882cf2369cc2e1bd2a634ddbcdd70f	1668355843000000	1668960643000000	1732032643000000	1826640643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
101	\\xf854bd5d40bc04611738e0b7beda15df027c6b5bdf90fb56df2b39c43637cd774345be9e685793d00639179c01752b373d948e878f66ce2db7f7c53dea6a71a6	1	0	\\x000000010000000000800003e1308098b8d40a2ebb79c83d3b8f1a22046ba92748817606f5e6f204c035fdbeb3496e6114f770640a7e78e609589810c985ca580deb16186282f6b138bfa3e1d5e06776a540850963d569b7d2e727c1050756630fc53d9610ac43dc904b1d9af1775d483c04718e645cf5ce8395620eb5ec1e584e396912346a406d8e38901b010001	\\x51b746e57a83eb83cffaee46fd6aef1cb987f297791bd38ea3adf53fae0160570146386fc67f45f1c89a0b6328470e43ee2b8f042c68453e560e08a18c756a0b	1682259343000000	1682864143000000	1745936143000000	1840544143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
102	\\xfb88e6ffea258825e0bf75735dee0a420631f25d6e1c18751d1924e4d9c9c7240a062f3dedee6715382ed793246ff034fb8a97c85a8306b08e649810828ad92c	1	0	\\x000000010000000000800003bb98f52629c93d262755c44c2c34d38dd4ed5ac0ec0380300a8642191b14ed6c28b74e106b4bccaff6aa5c55f6a6b06625f056c69dffa95649d156d335ff8019515df8fa24af228c45ed47fa80654bdffef2d0f568f7a65eef88fc341b1a086629d258b0f42c1457f303a24b57aff144d18d4bd47de035589c88a4bde1ef082f010001	\\x066305db91bdeaf1914f2630db308c0c8f81013458f5bfb41a9229923430fb025d68b607d26af9dd348bf568bc8663c66dab1a8c8581f910315dabbc12fd180f	1656870343000000	1657475143000000	1720547143000000	1815155143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xfdc8bfb300c51203df222b2388134d6fe9661568dea901971f6ab0f03f3a28aa4a1bc3d2c262424b5b7941219c6951d27a8f62f72bf6a9c68a4011c8c4efedb0	1	0	\\x000000010000000000800003b451da0744023547c6bf9b61268be0ea9f958c8c4a3830a46dc8098114e04c3d7bdf6e69a5fec271b33497b5859bcd015505d00f6b061afb142b95fbeceedb0bffa43266a85ea7e576f29466e1a3074c84ba6b8dc059bddbfd298d488affc830d924702fc4aea9363ed5795d0272a9a0830ad33fbfe4d66ea464fdb87f57d9c9010001	\\x594cf297d9e53ad531d4719c20140517ac25fa257b2d85438bd86204084a5b7de5745a8b187c51100e215c35d57e37f622e4160e2554177a480ae4610554d601	1658079343000000	1658684143000000	1721756143000000	1816364143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\x00553c670696d7f9d10aa5a6340f4bd5d1af4abe9ddb8fbb45dd9089894d33b5e40da60a1ca848a9b482bcaaa4713bd3e6be3a7ca4f440c328e13289e4960486	1	0	\\x000000010000000000800003eb346b8b0fa0161e546340df5fa99b840ecddaa9ddeba9e7893e1b1a3b77f69ff7f41cea93c162eaa4f93e0cedc813f2d09d3f6326062ac9e326d8e84478adbca9a5be6532672a5a4888f7eb8bc65a34804258643e94128e9b8dee0606711dec8af18b48e05e8e2e83ad370d6a07b76a083f134154412ad4ac48ee46d3301ca3010001	\\xe655625e1092e51e8117643759a1aa62a2f7aca06971ed4e3c33b194a1aecab074dd0742e08df232dfdd73301c339394bd90c6ae57d5586a8b32f29528ab730d	1668355843000000	1668960643000000	1732032643000000	1826640643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
105	\\x0121f1f16a0e0dc57da1157a11a8130207138af1cf6ef3e65978ca680f999bd3f30c3d5df72f9f447321e17def13c664e6f542c157dd4d93ee3114b568666b84	1	0	\\x000000010000000000800003fd3b51706f5b8900f18b729c5741a06f5785d73c72a895728ae03e7413e8421a8c3cd792af70e14e9de16a60f44e7553c202650c0c2324253debfc06c514c883f24b66a2b60e533439bcb9534b92603b1304edd007be605ad60b36376f063e4d5e8a5eb7c4db9e5a29ed4084a6d5db470ff10da37b2b662726e0bffb3eb65dd9010001	\\xe407c89c00f7a1235d9a6513f17cd5f3e578553046e167669f68779820e6fd6b37a1eb92e6052398886b1ec54e251cf21c892497374078e50cea5139c194b20a	1678632343000000	1679237143000000	1742309143000000	1836917143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\x03e13253a43b5d6de1eb99ec7a4fc79958e60b84ab45b1156787b5fa603215f00b4b3e2a6e9b377de0bd73c6a36361b38b15a88248fec8ac92952a3fa6388d55	1	0	\\x000000010000000000800003bb70c55c17b0cf60ae3efee901645cc032c1ec0ca6b7bcfa1c0774b23126347ecfde5cc32e0c7da35a7abf4825967a5fe9cddf165eab8f872d726b333bf1ef57e7a138a21d8fcf3443cea4262ea59cdb2e41fa85ecb068f7e135a05718229a8ad08cef3dcd401a733ffcd945508def583913a832d7597061bd91d61232ad270b010001	\\xfdd5db04abdc7cec2a00d2d466418b0e1fb053872d7f7eb4ee612948b22345330e46b1aac0d05a423df621540e90c5b1690b728bfbf772c079720b5492001307	1656265843000000	1656870643000000	1719942643000000	1814550643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\x080937298e24769c2ae47a809f25d9aa5785d2579566f5a2c022e7b15f8742164ddb25753dcc69ed607205c63a4ad0854e5889f9d71b534b0dfbdd61eff2cabd	1	0	\\x000000010000000000800003ccd352259d5fd5e5aa1d0c9d8d8745836a0435b1764b45b1358dc842df044eae25363e12082b7c5dc6f26ffe15a8310ce8a4cae45bd7ec500b93e9b49abfe385d6ff4c6a0e64839aa3a8a4eda7fa01671acd2c1e1430552f950ffe480a5ba084caf3e5e036f8f0d6a6571dc382bd3aa1721e4620dde0d6213cf4bc5ef3f21ad7010001	\\xe55f08caf4917f6b286b28c00123e03c9f11090ee1891ca6dff97aad79496529c0734b09ce94c1d25de73585e73f345073870cf894c27ab1a152372eb76be002	1671378343000000	1671983143000000	1735055143000000	1829663143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x0b09d07f9cec3639e6c4e507392ce9679f6c588d8cf9b629147dc450c92aa51722031e924f39649eb988a057ba6826f19910bbedc5fd4e7e7c5c8ecba6a8ef36	1	0	\\x00000001000000000080000397e80ef1e9688198bf6c2767dbdf259626e7a461a54748bfb660c93e94f79ec838fa70244c93230f53ae5c40bc5e7e01d215c418c5c78058bb513610a8e2e0288b2282940722de177a7756044289fc059fef7be86995b12a28e0b1bdfaf92505ffb52511834d233395fa4499224f1140e6b00e4f7a5e460146f216c9cc33777b010001	\\x314a980e09cc98e33482db18dd74e3dd4f1597fc012fc4100abf41212787de0db9e580ceeb34478bb257b8708b86b8ed7cd736ad9aac180ca2648417ff62a802	1679841343000000	1680446143000000	1743518143000000	1838126143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
109	\\x14b5ca9ccccd86dc0454b96efcc48b87a81898661ad5cd68a2aa215b9e548a5e5484082e16205410a98672ec1773c04d098a586d189b07909e1c9529fbde835b	1	0	\\x000000010000000000800003d599280372b75f65a2f3408295918b8095416c7e6a986d538334befae15eec4e2eada14c1e11a7480a78e7f8623670375daf73a38ce6a597021c7d96bbacf534a6e458b36230d69b69644caf98c25408e493d09fb918c6f5c813ea74b248b18aa5e36ab55fafe1e6b3bcab59dcf24d4a382d438462badf0c6c5b291572a5e117010001	\\x44b9d44f473ce2c9388411cffc5b726cb8f1c9e162e5dda1cf2a5ad8da4d34a85fb7caa4353cb05aaf57ef4c6d8ed57a8b88bbb8cafdc9e0e94c4f489829e108	1658683843000000	1659288643000000	1722360643000000	1816968643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x1509076af4a590c394b7bc5f9d3c7777e3dacb9fa7861fc0f29316eabc1f105e38acbac8f3d288693187a0482dd6e988ac8515fc7853710d2b820913a9ea9a0f	1	0	\\x000000010000000000800003d2beb8637179e2f37150687a2c862ad6dd7fed3c7214d1680f0a304af1f2406e5f77dc29ca8bec7f4394a690b041a743ffe16541dab65aba44c669ba4e2007aa1e50a0cdad42dfcde05ca969874b12b6ba237440fb723d6b7cafb6f278310dff917cf37f743709c65466423a9b0312ac1429b596ea6e80dd2b872e0e88a272c1010001	\\x05fa13fe4f4a87feebbf0c469e9bab5e0522d933f0057c38edc32e2f535c22143f085523c9b8f10bbeac2ab20ff4d779a61ef6fffc55477e4edcf11aeb1da40f	1672587343000000	1673192143000000	1736264143000000	1830872143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\x16993045207649391b18307d09ab03e7044922862582b230ea03064729e418f99240e9c49c6b18e90149efe36a12c02c087cb4b96b8312a4c3443136e1bf3e75	1	0	\\x000000010000000000800003ca6fdeec193029ee0431e38c207eff7ed8bca934f07ff76b69aeebda3e062a4efac6420a74b3b57855be62e87ad271706ce730a9c703605ff5dbeae4b9eb826d65bdaeab85cd4652a31f57274d26b76685a5338798f9b4e51b398f622b54043d92437469d00b0e725a855165adf10200570853e2a70bd7550a4fe3e13c824efb010001	\\xdcafe8ed6952e6b42bedb21c055efe82d3a7e2345cc6f5996469814aaef86b2acb57ab840410882533620ba0d267c268a5ca6bcf0ff6cb9066f5b327afa33803	1650825343000000	1651430143000000	1714502143000000	1809110143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x1751d947fadc83b05b77cc3b771547f6af3038eecd353594133fcbe82376038ee59ec50f133724c94c5249202ad4383017e5d2c1df3af486a19b81ee0b44a377	1	0	\\x000000010000000000800003d3cd6f8a2153602b0602f59d27a5668ff1b977e55c2797f58f59fca5c3adcff3c3eb18477f9ee5a4f970ec93160871ff9e3b4420ba405898e841847b3aba037a4dc8c6f373257ac9c20f1bc270552aab0785e295fc186232f22e45917ea49523ab03c300aced4e55693c913446643ee61c52cde875da2831b0ae7c003e8dee67010001	\\x8c1cef522312fe57b789b715bb6c2d6109e734efc7c6d664b166bd5374aaed3231ad1a717cda030483f04c45d8f01b11cf9095dd1e3ccf8662e0a0600b98df0c	1673191843000000	1673796643000000	1736868643000000	1831476643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x1a298a11d2b0f4fd497c2d48a120977552d94902349232224946917d3a62f212e8c5311894ff3c770b32fac7196ebbdd02c978bef153ae68450683a4d7628abb	1	0	\\x000000010000000000800003b8f2ddcc28854888e0408315f831f2de5c9e50d87be0c95c63107c85f721adeebbb4b4153eaf2f39cdda5e3b6a8ef70411c7b7741f579295db8ed90ffd702fe218af82ed18ffb3988ec187f9648174e9e02096de13b4ad8c0c77987ca2ae81f96df839cf29ddb2a44ea3cc77176e8515e9cc435a407cd9b01f56ac8ae069d9db010001	\\x29d7cf576a8b17983e3956798053908efd99093eae8d7111081e00237ffd9659daa48a5067900c8fdb18aec20e69aeaa44d0f1575058b35c31a2c1655638f300	1656265843000000	1656870643000000	1719942643000000	1814550643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x1b5d2a87e8ec4c90f968af4cd94427c37b134bd6750e244d58425e73b01d0dee8ff5377cca7939dd55de0161b3405da68c4a9c632fb709df1895a7323bb0f608	1	0	\\x000000010000000000800003ca2156e1268000ce6a7f9fca381b2972aaca5204ff772c75c448db2fcbb39f8451211ae694d98e011a5cd029322c62defa87e9eb3e65de1a7858f2dba27b1f36f504a45b3d726a13c9c742865bd980cc95b65c29e668c5392b0b899edb9bee4abd2f8d7fa19c91d1cf2943696ca1b03ea0e0ae5cd8f3aed65de2a66370095dd3010001	\\x3407f0bda64a4236a6c580455d32cb0b78559750aae1b3c5affabc9a3802298393f728965d730a23b8f65dd2bf187dea92c8f9711c0671aa09f7a9e71984790b	1653847843000000	1654452643000000	1717524643000000	1812132643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x1e05f96a77efc8731ef18099be4ba2002e4153af285050ec963a6a5b43ed66c2d3921e4f8e5df90f43cc38f8421c92f57989ed3c94958e7ad483fb4295117a85	1	0	\\x000000010000000000800003e23aa961f6efdad27632e0e54c86f11591cac7aed42f75a4f2b2c7f2ac96c1aa5e308b50d1b67fcfd3bc43e6c79b59bfeb9aa2bce05a6144698d4b6b7f8a842ee68c63252e07cbf25f6da5811c95cb77e9b2a8bb056ac4c1e469059293cf6c491f9f7c67fb10ac74273d83cab4709403c674fa0d3779b43031c3ad202e2e9c59010001	\\xbd3a3d7246be66d1014defbfa2c1a91bca9b7ec95329933a9438473d96de199bb4bf39edac44b9c6931329e66bc3d20e6428eceaec11a680e0fcb729ef052b06	1667751343000000	1668356143000000	1731428143000000	1826036143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x1ed51f1db93fac38ac7b5a49e5075aa4e12977a66469f00f591120eb919482167c00fe09cc7e5bd9e2a1dc7a24829fb5b1a5d1d84b1efa4275ebc59a3c6f45ed	1	0	\\x000000010000000000800003c5ceebe8173846399f77a2dfcfcf255fdc83c4501e135571ec1ce666a909fb3274929356cc4886ca0e3c94894f8ced509ab2c0efb2da0049f36d68216348e2ed6532f08592c2535ef9aeec730807f36b8d62d05eff5564127a5dfcb702fd7336152eadea6b6d465c14bba1b3ff520bcd5d4bd8b3202db1d05fce4cd32995b171010001	\\xebc217e714f1cc6c891742f49b6c0f65b7790a2fe7bd47431a22ac9fddddf2763cf7abe29e3ce213e0c5c130313717fb5560ba08f9a597c72753f5aedd70f50c	1667146843000000	1667751643000000	1730823643000000	1825431643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
117	\\x2141dd7465f44be9a75d198040b7f787e23d1cc3a25f8b4fabb1cafb5ec8987a4f14cd1b6e0647cecb3b88b9af320d9ca238a56ef02f2e620e55a8112c20a4c9	1	0	\\x000000010000000000800003ec8b6a60fd042473e7c7377dd94f204b66b7ca740a613c0d6edbad0ce91719452e84cbbf644886c5f5f1da14c41b0a22d875746d0378bc5655a132fff7e3b6cb3409c28556667b9fe9b6d7490fed6facd57d99f0179cfff72226ee6902d74f1657c1ad11652fd34919c76fe52ce8f10b33c2a3fea069a05ac99b98ea3575c9ed010001	\\x7b4665819dadab6d17358e00eeee0266651784b6b74985fd31064be8411900dec75b3234f7da228e050afe152016b233373fe59bbafd7a4bf8f135251c586809	1667751343000000	1668356143000000	1731428143000000	1826036143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x243db9d9751a99c3c9254be404f4bcdc5e4deefc4125bbc29b6245532d18a0bc09bebe0fb1d5d98543628b6d71a7a426baaeb247298d9966727727ec6c5d64d3	1	0	\\x000000010000000000800003ba2fcf021859ca99a97c9d58cc5141fee8be29267f54d6afb3511f1f6acb9dada6f4049376fef834b1d69913b98c57e6168140cd18431488f596c5602310ace00715707229cb3deedd68e00820256c715983064c3eb248d73a15fc21b7c3686359d09e2d2b616fd7f4d1d9bb78d0664ba9dde2dae4fc0efff7a4c7b45c3b7ddf010001	\\xc579dcb261c03455adfd0311ab12eb0e6f90fd5498dddcb09b7c26b9198157f8d4b5222d074a5cf02edd35d95ad2ac2354a277cc6155f19772f11fa8efc6e600	1668960343000000	1669565143000000	1732637143000000	1827245143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
119	\\x24dd08a16a09d4b493489f36179de517f7bfafdb84af515584dbdb51276efca77f91704b92aa438f7be459774ec9cf76f74c28257bef454753d27578e9341560	1	0	\\x000000010000000000800003c6cce03ec0e096f8b5cc851ae1a7145669540b56f59b29657d3f0795e055f3a2014ce88b25e7498a5bd4f7b0703d4e7c8cefaf39f229acf4606851333183d61acbfd898e044e59ea15f7228477dfa0b5f9d122f01816031f11d94fa44173493b3a04deea862db2fc4b803181dfd9a7f433a28dcbe04adb5d614d7ad2acb83fd1010001	\\xe2880ae47519a47f58a89a0349874a418b91794830a8aeedf33446ef479ccca35bd391b33495d5bc7f097a50feaa2393f380e55e901fed4d67d8a483153ae206	1662310843000000	1662915643000000	1725987643000000	1820595643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
120	\\x2581696a82485d9313801ee4dc2a024122979d3274ddfa5ceded1a9f88d8c6336ac8ad35f5ff9f3ad12bef5e435a7770ff13dfcf4b8e5c858271e3157052928b	1	0	\\x000000010000000000800003bc71fb49bf7018fa5a879ebef8b4bb46d16bbcafec911c7a4909a171dc41b76e40b62a4c200c71011f9ab5a3dc75a720091d7260da2c01c13edf8d19482c4facd82cce5c1b4f21b5c221bb85cece39b9961bb6c83ec8c0e2cf02b32b0546981fa492b13894b5e9646b5f8437427f6f5e7884b6a05145495a4b13cef46df360fb010001	\\x7fa95754c31d0aa89dd7669d309b93a3208e11d0bfcbbcd059c6be2baf09f2fecbaa83e788d71c2e4ca583b27a0066104e29c9090df9d652895b66057fdda30e	1662915343000000	1663520143000000	1726592143000000	1821200143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
121	\\x26e999f1d6a130313946fc01eb26aaff1ce16c9d93509a058995549f4290f823beb61b6c705864f96b8266a102f156e4dcc5bb1325e8ef03c001515dc61e7d7a	1	0	\\x000000010000000000800003966e483af5d4d2d000fb10c14a83c7e9c40e7b7e2b1dff0e6b5ba03902ca921b6ee0c090e60fbe1dc8fae463b0a6b5e0832fe7b980cb5f4a723fab6c4116ce77b67a104f0051f1109d932674016b97736a0b7ea9c278c4c31740804e98301180da3775b70c8db395499c54bd2d4afd3196663a9f7ad9b96d8687e2742533a731010001	\\xc76f81461e8fc9a175d9e1f9787f7773a4bbe43e3fc3234af7880f017cd696a85953903ed5bead51e6c3eec427ed5daa985deed910ab14793027713746a55402	1664728843000000	1665333643000000	1728405643000000	1823013643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
122	\\x284d00cef200e171fad346832418becea9ef63b32eb79349853e7cbe1549cf31cf8bc854f49b5b219d87893e1362b32744b584450c68651690fee458e5888064	1	0	\\x000000010000000000800003c989aa4ad7acc5fdf656c3d7c8156dd620bb5dd931687557d47953b02fc1c516567cd7c11143c926c37164019338ac67fe73e7eb8bda6f314fd6bf7bd178b2e13a6241bdc29122ccef806b0f6fa82fe2186acfd3e09d2bbb824cf79f095ac65802cd41a277f730428c4f98378cd0ce540e3fb8b1da9a632d20a59fe6e40c6319010001	\\x14b91ae5e2f5b44ad5978d5d8ced44f4c26c7066795f643ced8a02d20fbc2878055c7ea1bce6414db2800ccd86474327eed9fa7dddb14919a3e266833622400e	1681654843000000	1682259643000000	1745331643000000	1839939643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x295ddb0fdec2f91489901e0ba77c804363a0076738a25f53979653005c53fa7c80e04a9690813890a472dfd7d75d77710d5dfc3da9b8d0c0efba19b89b4c26d3	1	0	\\x000000010000000000800003e86068f8c65874b83a29bde120ac9725b3e6eb0c24085df41a0080d0e721858c4ec40d2229f72c35e7d1a2078b3b573b2943caf72b5d0d53e7091a5fb7b5789ae0012c5d12348bf9afa256fc5ddccd739ae18020ccad7491fdf7a62908e6f40e306b415f08b4d7e1c55001132e54d56dc211443ee022dd04e3fdc90e4ed8c427010001	\\x2ca9063f77eae96b5746f26b138098511c925783f151da44bd02e7d9a0a389a306e8717427792a74e0da5ee4558bcd04e7724789d4c3a52c718bc7bd1c4ed703	1681050343000000	1681655143000000	1744727143000000	1839335143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
124	\\x2b71a0e617051ee31c7bd489b68f4b65e841a0b2467a2fc50aa1431773a18e0575bbaabcda5bceb53b2ce45c42b72e55558ffe3d4f32bf72f71011af952a6929	1	0	\\x000000010000000000800003d76fa105fbcbc65369db1e28d0882ddaab46777f0ae46c9e78af47bdbf0e0a99793f49e7c29ab4ab9a466a7739002f44649e71b50513dd24a880f4d90e57a304e225949e672f18ceafbd732eb988a6e81eb302b2abcb51232ebb288f85ba359d1413fa5a0615b247e7714cd566acb71f3635395ea58a3a488cff45113c3d8133010001	\\x2ee808b1bd0dec66166d99fd46aa265a0b3c4674134ad2bc312dc41b6041f03a8cb9112dbae17239de4f6ccf129dfc0798519ca20f742c7b5229c4086579450f	1677423343000000	1678028143000000	1741100143000000	1835708143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x2fa9122590950aaf41fb50ac0b1c43ff33ea00828a4709c6a6fe09137f6e269fc18dcd44adca8b25add13aad8b44bccdbb78a4e8d002e5caddec272000ba43b5	1	0	\\x000000010000000000800003e66923c2a842b6d02e64751f48af912c007787a5e61b7b7ff123d4fcfd02396e38327f44139d0e5c6ade1e79fe3b577ef4b48ec2deb15b9ccfc7de12d0646c0d79d9ca6d77f3c6605ed1d052631963c7191b71981bd2260cbee5d85821dd6892191c0380c97df44192e5a8d8e5117cfbbb219a1c7fb7ae3cb75c599be773406f010001	\\x861e7542e4e324761af5dc8d37536e249e5fd8cd5e57899d2f2c02c6036d13584bebeb680a7ac00253b135939b21d8dfd015c8494a5a50f54d85405b301d8809	1656870343000000	1657475143000000	1720547143000000	1815155143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x30a172bc9985dbd9ad9fe038b1fa874fc12ec86f2c7f5ff5d06118127fb9e37fcb4466df2ba4c755c8febaf83447df06fb10e5f57df2fd9a986af930115351a9	1	0	\\x000000010000000000800003c22dbfe34d9eaedc081ee176d5689273d995f304c9db586aabb5fa7a29ba046dfd959b5bb91b991eaa1413720c59a3ce8f2df0d041a263e2824524cc72bb0cf8dfe1461e92d754214c6bec15c34bed4a105c6863e9f839538bcbe09079b4f853b57cd13e68a48bb866bea3f870177c39c3e996bf9618f88a8a6e4a6071b70e7d010001	\\x6538b3fbbf05c77874cfd0c97f35484cf1962adab6ebd9ac2dcb85a1889b14d454a21d7735ef3b6e978dbce3a05b1be46b3ac47b96d453889f64d2a2baa7c90a	1681050343000000	1681655143000000	1744727143000000	1839335143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x31a598fbf2defea0730f4669d10f469ec3b552cb58216a160931b4b0bcf2af0ecee9c9fb1ffdad357d5718a61138a665d2a71524bf058cf1f067c5e67307ba00	1	0	\\x000000010000000000800003cc20da3b7a9073e7d321c5b382796441c6fd39df6ab56226ce47689bcecb4b9fbe7394b4da907e000962780ea57cabe3aadb91736ef719badd7045ec419e2b68109df4858c249b006a5b9b8a6f5d6ba4a300d11729394d35d0e7d9bf7522e039c7f8a3e7f208ac2d759190eea7c79694b5757adff7e6a42c9dfab896a2d02f53010001	\\x727f2c696b641fce08a6d256ba1368ba81e2bffd8b026988742a3cf83ff6d796dac66e0176c41b5f2966dd2eb23e31e9f58530223888227190bc12fe4e53610c	1662915343000000	1663520143000000	1726592143000000	1821200143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
128	\\x3179cfebf734492083dcdad91c6291e514e71c87d8086a05707acb00d26b76d145facb5406a6d5ea546405a2d2b093518915eb70a85ccbbf7291b5769c128a2f	1	0	\\x000000010000000000800003aa6526781d5a0802579e12fa7f6551589e0e80b6c9419edd269abd989ee17258e0302d84c3062636c01268c508301aac4fc878a24bd61662c84225da2f556161238cea442a81ba688797fe5a765ffa1748785263048ae445b488d39d6e8591e97351e241059dd3c31e17597d6200af74f10f5bb178a0e420d3618800ec251da5010001	\\x152d92a54f85ef7140e689971d10bed90cc16fae326d12cdd7341778e73254be96d4a9317aac66653f21739d31ca34034fb8645b19b24cf7cc931e9a1b72ec0a	1670169343000000	1670774143000000	1733846143000000	1828454143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
129	\\x36352bb79b5c10b8d76fbf50ff360280b098763b572eafd339137d407d3bf9c2b24bf8b8d148910d42d78722e0a05e065fb7648b125149159b2b44197644eb1a	1	0	\\x000000010000000000800003e7e97bfefbe1206ed7a3a712508e02d3cd855687038ab98d9e3f69446522a3647b828a4bc212ed5b3cb7427f8d15201652ac9816ced52e2f806f04059b1853d8945f7e573433c1e53598e749aaca238623edf073f5b538a355209a6407c1d5ead21c50859b26d30501a47839afb07e0651d2b911b50b0deb040d3ee44e48da1d010001	\\xde3e09224418fde52f8283d97d88dfad7300801addc2c1a3080988ee01540acabe1b69bb1d03aa041d4c3b001e081b1ce1393f50cf3a0485e59b45fafb3bf702	1651429843000000	1652034643000000	1715106643000000	1809714643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
130	\\x370de59e19696c521c493877e1663942775b8814066c1c41f3983ecc1ffad86ad88b190e2fb6fa63592d23b52701468ad2918df9293c94869d9c2748d8f9bfaa	1	0	\\x000000010000000000800003c71ef2d2eea14f6ead8c2e1dc8d74d14f241875c304b72b49d75a5375b456a9d4a80b1dbc73e1705c7be4d9f8d52bebd65e1f87988804be54411e35cf2cb211032a0f27fe43e9052f66bc6da59c6396a18b02542554497abce3a520088f333882821cc03bba532b6d349339595b08ae9ce5f8d59e3420d36b71b845160a08ccf010001	\\x1b7c3288091a33cd28a0333234bbc94ac166c76cb8139f9b98923fd6634efbec8c4b668000830962744e5e609e117f56a7708a80cdb2bb345667225225d7c006	1651429843000000	1652034643000000	1715106643000000	1809714643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
131	\\x38a1589f5e63ff65fcb7ccfddd49b4e8f42f98856fcae79bdb4b8f598024383baf88fc626bef7dd8f64f9490bcee785ff726df91512de24014ddfa68b259fcc2	1	0	\\x000000010000000000800003ba78a01ba6673b24422de7090b33f342608ba2ccccdc2a2b45e4bf7f7ba0481cdb77af5ca18844dead290757f4cfcb386314ad648527c3faff9f681f19e1f29e952445bac8e47702285f2f4580ca3f2155de8ef2728a6d9e9cba7533635a520b8aeb6ec20d95eb2b91376480069f8e7228acb1d77382822110d282d360958e4f010001	\\xdd5e2999a7b2c84c5182e482d1948eea0c62925eec156e2e3a4d971f8e258bd7aa7677cb33c2d236bf5df854f0aee721e5386ebf38733d1c021d491d015a350b	1679236843000000	1679841643000000	1742913643000000	1837521643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x385dd0745c6aca3bdc63402c5b99ff13b1f9a4226735c6dc27ef0b615a3a02a74d31be2ef4a55cedc4b0f90e7ecb49c2d16cbda238de3274ccfd378743498ce0	1	0	\\x0000000100000000008000039f6e0f859fc2caee73a1e823816ba4e05761510098f4535a418f98adbab21a8b88670a659b3aca36abdbeebecb48fd4e291a92ec31e8dd79c2d5c06c202160aa172f4ad9b171741873e87f3e5cfa0d6884d047949b004f39cd735bb1a50b7a3300c3ea79fc582280272757464b9396c0ae1abde4bde0f46c1459acfb8bbb55f9010001	\\x2d3af7bbf33cd655bb23a19f82504f2609ed790e7162d666851f57870902ccaba2e20f346a96fbe6d31be8e3bb4a6e909137ff0f9470940b4f9c3c0630f9550d	1653243343000000	1653848143000000	1716920143000000	1811528143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x3d598280ed93ea255755e776600a2705912cf108c64297931b2c72117e2891be5590a9db69c7e87fc34ba63674ffc228a3fad356f5c3bc210374b057008dd626	1	0	\\x000000010000000000800003b36332e00c98f23aa3fb5fb0d6a0f5ba93ad9dd076e4e06cc8b38a26f3a1c86a95422c0a059f8f218f659a137cda51d32310c92c6d7bbd4a319a8df895b5ca7fff311424ae3e1fb3bb07c106caff24f7cef1503e649ff466cc399891b50028cf46a9b660008ce52f19061cbbebdf0322bffbba32cf24565995da66366e13aca3010001	\\xee72f6e95c928d7016a1340a24c69b8842de30f87d0b96f70be5be5c5977ae3565adbc43e0f693397c3e1ed4f1f520f773664a45e4a55c3c5672237d30132f03	1679236843000000	1679841643000000	1742913643000000	1837521643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x3fe928962e4e1448a12fa95f88ce2a1755ebbe9972fa073c7188baadb0b90bbb4dd46f4ce5daa3483e470ff0bb386714e2f667a8d613b73179e2276b5557a652	1	0	\\x000000010000000000800003d8ae6ddf501c4d03bb1f86717c74555b736f05649a5126fe23c486e88917a495be4bf105878a0ac1a93600573ac44bb6ae8912fcfdfc97cea95b2b7d63a6a48c227bb0c535f895ee7ad992657d472c7c4dbb688b6c1915d37deac4df11c888d6c1339e47f9412ba6134698a23b0a3082e2a135a340a03be07328b2c9869ec41d010001	\\x99a93359ce3fce0770475e051cbe1c3f18b9680280efc8983f8da4649a23c752b0bca9d573b6a0ed1388a1755c78675b6ef243a4a8def3c9db8c0dc20f2f2907	1678632343000000	1679237143000000	1742309143000000	1836917143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x424921200b70dce4672ccf965d805749edc03a4f0fd7afb5a24e0da55ad7259ecc4b277784050f9e8c5b2a449a0f136d4585064d9a58617b16c13fdf405812dd	1	0	\\x000000010000000000800003ea911fd9713800d0b61efe9dff15d2e41c84d6341bb8d16f17001e3baa6f3e545b20583b9c7f116f6eb8402ef18e6c3f91dc7d2f2543fac2ac6f88d6b8a3e28ca30b044e8720ba1a7ee21b35eb686259abe2cc8cb5113e9dd71bdfe0a96142132db9e2dae6e2c179e5f834f620c04e3319cbb72dbd99c2e28983c34058084baf010001	\\x59a96bc67f3ea1056dacdb8ca9cac6916292a38b847fb029a4169a7636b370f85fdc30473d8fec0777ece98758a8ab0f78d5130339c97732ccb6c48ffa94d206	1662310843000000	1662915643000000	1725987643000000	1820595643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
136	\\x43e1529d7d104bf7d6da53bdb60f23b99944250b22603af36edd0fa8b95fe144bebfebb67a5d73946a6459fb03f02621ebd8b06f97c0e1e94e3f50500601fedd	1	0	\\x000000010000000000800003df93f974782922d47410d500764fd7d416050e7925ccd5a9ed1da58d93bd009067091154bceab69c3684430080a1a6388bf87225377abe465cf998e20653fd62193e4e954556252c49f5b8374dc89ca1d2889a3820648835817e11a60e685f9be4eca55cf4aca7fee122d5bf50faed93a40d2e299038250e26fe4deb9bc482c7010001	\\x1d48e0ec043188fca8b2d82079e0b0e2818d8dd0ca5a2e8e849382182f62a72f62f2853c32b98dddd6b93cc03c0419fe17a34afc6f53562c6a80e47106965805	1678027843000000	1678632643000000	1741704643000000	1836312643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x434565d28368f260980b5a90c08a1ec8882b4c05fe2fe34f4fb6890d7e11afd3480f995bd9d9b5343c5542d4f8508a846b290a8a9a26b1856bda7501a529d6f1	1	0	\\x000000010000000000800003ae1aed0b58f2990051398fbbcdca3dc8f44a80a72f326d74197f09a175dc4ca03134831246c3faa863e0f71dfa20e453aeaa8f356967e3ffa53508dd32070a8fbb9b8c8e3b14fc62a1cf4ea3e9efa3c1424983213afb133412a2db27f9feef25af8200670f1b6f183d4c0697e949159654a740ca7d25b7c809bcec3397358c27010001	\\xe497f57c632f02ba5eee1baa96b4cd6a199c21bb0da27f6cd1c49038ed94dcdf49d0f7586445d9e815097ef96a0102008a3c54132d2df9c122536cb011296c04	1655661343000000	1656266143000000	1719338143000000	1813946143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x43417498c1d6c80bff08994ad61d56d2917256c1aa4cbbaa2be16378b76b1aa31114aff58feeabe5b09b8fcb39a0c2a46fd3e82be5b5afa24cae87227975520f	1	0	\\x000000010000000000800003b8c862357b7da2b3f05ad3de3e4c692ca7d4da393ad910fc764cb64fb3eb469427c15245c3eb87f1b2b386cacce3b9cc7e06ddc95f523339858b7b0e6315e83c7c46bf8fe3241992fa8e93b4593df2f65d397e1943ad51ec4ee3486ed70ffb02219aa6d3af02272d9d64fdffe9704603cb8fff06b0d4fad1805b27db96712863010001	\\x17c7ecb5395d2c6866c1f68033d48548924f23de8488ec10a82abb2b76ea9e66c7c8dfefac8f22e0b0d1e55bb9f723f8aac20c191f612514501ec04862d53906	1670169343000000	1670774143000000	1733846143000000	1828454143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x4895f79869cd1118c88d4b9a907abec6dfb4e913c473a82514232ae019a0b2b533be240a3727e10912b7915c8bf7aff52bc4c934a7dbca401c73123392904f85	1	0	\\x000000010000000000800003a3da6b62531bc4ea8f371c5b894bac22e3d01396c34098caaf479bc9be97e939d3f7285353bcc14603d6a0bfe62cfb0136a6487c809e770e046ca1424706481b33c7c83819bf082b18e169e901333eaf151b78371b49dd0ce7df64aeb267cf57dad1331769bf98d265bc9dbedc5e61056cdeb26643f4a1693e4630d3b7040377010001	\\x32683ffd91ed7ffa5f1547b07c6364dd98f8d7e4fdca9d698a8eb058d2a55cd0a5d94aa50cc3261a52b0fcf078b2be058352cd2d31546a5b5c250db648c8ff05	1664124343000000	1664729143000000	1727801143000000	1822409143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x4c194d3a33b28b0800f1c88c88bbdc880bd22a43a0e7fea2ef3f4505cd179e886ae56d24232e2a1e385352e502f39324081ee89a20b02a0826373ea62e743b37	1	0	\\x000000010000000000800003c56d4e692536fca783167b0e2330328da3dd99536e6ca4947aed3abe2a1dad79fceebd1c18c366a97561584969280a14dc3988864f9b024ac9768e314686bb13adfef09bda90e2fd2f1d3f976fe616423a1cedcf11e45364e18bb2705eb2023c1d387130922b7e38448e119fd5e3267815ee6a70f5075c657b732ec4681c45c9010001	\\x3d38ae385be44f81b7efb2767f6e9f037a3d0c7d9b0386e4df1f226b1efca3a80a607749838b7e93d1c6d6256432e9046458ff27190ab157451deafd2b18d704	1668355843000000	1668960643000000	1732032643000000	1826640643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x4ead378661daa9400a3b84b9ef927a9626283a22e2553aad677405e0d680adb9840a94fbe057e34292163e48a8839fbc26adb43f1bbd4837423deaa7262bd0ee	1	0	\\x000000010000000000800003b4968c17a1c0b0d7abd041805c1e5364ce1adb2a01433bcb0760f2ba6418a736746324f1a2453adea793f978c9805f46d9ffbd148c92fb55055a83dddef5ddfa8bca6be73c1dd00e66f95a4cb6af58c1b4c8a34262a8f9338051658294b4b0a965afb493c3d1bf61e203bf04b4b235d0053c25ab2ef21e6337ab39d08a2c6d0f010001	\\xd7e41f4141dcbd8ebdb3bc10b4c971a01b68c37d67025e1776e0e15815a198eccaea9cabbf280213aaad3e7c528ec249e1015df6ac8231bf48dfcfc0b5a3150a	1674400843000000	1675005643000000	1738077643000000	1832685643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
142	\\x4fadd689467f3d0421ffcbaf1203a0378052147aa03fc513c640f9c1f6ab27c09e8757ed57123ee023eac2ac94d3b5c57ecc192fcdc139e37d62cbcbc07e6ffb	1	0	\\x000000010000000000800003d8c1a811a914d891a2b62269742aedf9af900385521a96b242c3f95579ff4fe9be7a0d4f009e7adf664c0d78191468eab541303e3dc5ff5d11b2b7e4eb707bc8de20081a8b9d771f177a5db8470e8818045493e773b7e67065ad59b8f375c5a94ab38ae57687d7f38f8e77b4917fd051e9270f90854da09e71c74bc751109151010001	\\x85512b4a1ef590a66386c3066a320cef480cd3c4e6756e0b9c157fe6526b5b6992db0200bc1e4c9f764623300cd17adc95f923b47fe401407babf9818cb4e30c	1656265843000000	1656870643000000	1719942643000000	1814550643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x4ff5b3325882c3b70ce3737351439c8209e3ecbf8f024043b7b37ffd940a46bda31e465517aba00d3373b84777c5a8098789de2a2a62d8c71d721d3c39b2a254	1	0	\\x000000010000000000800003e0c1cf22340feff6bc9eaca8cb4af645d204d1bf8888735e04ffcbd6bee71c9c307eac269b6ff4657dccbf1d58d9312b939a27c32a4daf749a0703d3fb70bff0dc0363f19f17c084bfebd741e7180c31f4cd02d8d50f145003aa0a9001ee4e59c5710d7a73baad43ca1b580069fbad7d730eee30883ae222d6aeb231cf2e0e9d010001	\\x4d2142975052807d7b830df2623bd4b0bea0b16c787d64b069c1243188d591159dedd3cf4a4853f3f3601b0569970a2f6353578bc3a0699b523f1f913082300f	1662310843000000	1662915643000000	1725987643000000	1820595643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
144	\\x50e95a60e8f7d4dc2c3b4e9b5522d897b43f9780b688b989f8c8c983c15d8c0919725367a95ab5651b2b9a25de2a8e6c18f29e42ead615a5d2768bf8e7e72d0b	1	0	\\x000000010000000000800003bc32b9a8009bbe453597479b9d38ba501c7bcf872ca73d259a5b318092394fd4ee0de40e56a0aad84ef6396f5ed4c2b0083b2a70166bb696b855a490ff2f6d6e2f173b31e5c12288a8c35c1dc8ad1d3fbb27ea54f8c9fdfc16761b388d4a1825e5e650ba5d989bfbcfb61c57311da2613dfde122461c875bfbb0cab12e05eb55010001	\\x2573a2b03a28c4c0cebff8386b445837d55b4de464515835de07e63f31177103a4ecc0113ff65a1ff4fcce30a55a0839b167c9430395688e03ba22c250db3005	1673796343000000	1674401143000000	1737473143000000	1832081143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x5149caad004b51f53e00ed4e6a2142ff2b087da5d5eece4f41095c81544e771a3927da2683331274956919758d09237a74915db8312ae99bbf62177a3205d130	1	0	\\x000000010000000000800003bbfc0bb863ffc0ddc24e1d3601ce344abd9e29e4b6eee4d9c945574a7f7ba63f4e9dd734b6d2621b9b6fb2d65e19dc1050f348e9c877abd13ebc8a598c636015acca1dc3722a0bae538bb8343f7fe115022681b1455418b4f01a036e66bab87c22aa9f8d26a2dfbc0d12dfcbb18a91e8ae06463d426e47efc8af35df0d1fbcb9010001	\\xfb45679a07587ea7186d47794d89caaa1ef76bd63b2792beafb1f25a25f06eb354bd89165e205e68675f287a657ae53fa465a97af5abb24402072024c5da9a02	1657474843000000	1658079643000000	1721151643000000	1815759643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x57b52906b313b19a4a48db3cb57393b665037307ddc45790fcdf4fb27124808039058065fa969452cbf72db8a2d3d072cdf57477f03fbfb1b7619e26c4f80ef0	1	0	\\x000000010000000000800003a9f9052de22e9a2b63b5d04f91f67d553ecbd63c0c74ca06b79bdf605785ea37e9fd54df0558cbfb44972836e0c22ca09f4cd0643a25231bbeccee4fe439064621171d2ed21d5800f2fefa7ffba483e250a93d9fd9402d98efa6ffc13b5ef1c5d35056e73dffb4326eeaf92d817065914b3fa43611bbf3c5bc6edb6eafa00027010001	\\x7f46ce2ed5ba8b1d2f8f127731d12733c1f4f9ed05ec0d00d7d4a6d98e486d937487a290a92e758a1447c2c2be56bb3cf62575a169026ad800bad94985acf404	1671378343000000	1671983143000000	1735055143000000	1829663143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x5b452018432a441a7618c02201f10d9c853224c4a578ebb4c0013c6bb8170154e38996e829584752794618f67539f75d794622dba8da7e63f2a5d6957635dcab	1	0	\\x000000010000000000800003be0b5c3b9eaddf12d734052e554c72af8e369826c51e2204b81e160d0a7f92051ddc2bef00f469ede9b3b6788b7b9f3a445b8ea251f3a8f255281f27c783ee29fe77a9474c48699ab5140303d9b6d68264ce870e2a418f59d4fafb05cfccfbc0a4aa3426ffae57582e682d9792f9515aa4526c807812df870dbdde16e213f165010001	\\x034f714223558f3f2554444404cf360196d72a16b4db5ab08e5cd24ea64aa9ef67be532b345cf89998251ddc307f1ecea6487d145bb15d372dddaee520605901	1674400843000000	1675005643000000	1738077643000000	1832685643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x62f94afd6c7ee4a04d1d918415debf4354a3027e93f1a3f2b771203976e0d99bafcafcad36bc136ba20d2830f843211eb89a4bccd3ad02c3ff86dcfeef66cb5f	1	0	\\x000000010000000000800003be2a684e8e797f863a26928b4037aafca8665b8e833d44b7c26cdec90d06a0f460d6e11b41f0706ab93803e79c53541b00713db275e3afb0194e3ecaaaf1b0938ed44953c6a573ed6f0395035dc0bc4dc8e59de892adf3686d910bc16ce0edc42e646d609ea9dc743fddcbf50db2bf38a964a3a3830672123d0f1f1ef9e4d121010001	\\xe12463eecbe2c6123b2e6a33094c725a8eac4836f33f41427854c1b29835c47bfddf165825397f08c9a8f621c3737a2a611663799f69b95b2c5b5814b797270b	1659892843000000	1660497643000000	1723569643000000	1818177643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x636128b25e1b7b958aa3fe639c836000e58b5dca8668aec11f361f8f4d1cde145776acc02444df3a99e503a1b2ec9a6b0253919cfc44edd44069a4fa7ff8cc47	1	0	\\x000000010000000000800003ae5988919a4a97ef824b5df47852e7874f4e12f3153fffa1604ce65accea0635fe3500a03181c833cf5cdd67f0e9ea7cd455216350b6880b42160dc93f3645228fb37a2cc99c212fa33edab1fd7a3eec85e1dd77fe460d3663b3f07740aa2ed969a839174c3f0d699db9d6e3d041cdf8b88ab00f0c86c157e39117c48dffe10d010001	\\x6fc7f23590ed83902d01ffc987c12727d82981502f7334e3a1dc7e4fb5e3878f294eea19b735ba34194d20a222771ae0681d2a80edd46bdae5e22fabeb6ffd07	1672587343000000	1673192143000000	1736264143000000	1830872143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
150	\\x635d9d2b5aab11b17f49527d16753d68ba9889ce4612b6b51d16e5c99f10f0538e68c336ef8d6f46a6df43c9b23d85bf378e3e7d77262169179977fbacc1c3d9	1	0	\\x000000010000000000800003af65b959f655940e071a25df832d0a4ad1a2050ad389ffac62eb5f9acacd2a695162c6f5c8e01aa672835f6a2cc011c38dd912523ca22fe73aa3e51558eb57292c8fc8df0f5cf3278050f08c479365f2007d6e24f6b3ffe590b8e670d211eec7a41314d90241a405d91a9d02c90d17bd8386e1734bfc0b1f66eae9751242db13010001	\\x3cd0411530d329b6c848250f6e2c69e884a2e973f959490b8f0f9b040e06036af6a1eb5673a16ea96f5cab43474047379f3554e702cb22c2bb942516f6f6890e	1670169343000000	1670774143000000	1733846143000000	1828454143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x644ddb65bef37726a99fa0f09501087d9c94c8b2ab9f85ae8bae822ed22f39288dd928fe4edfda378a5828ec8070f17674b20a441cb1df5ed716a1d1a62ea969	1	0	\\x000000010000000000800003c40ad316fac938afca43b2e91998d18d6e4a65b9e6de1159f88f92d232bcaa1d56f54a93359942d2a9f7b5212902897896bb9515269a306ad6353a8dc8456fb2f09149674599de164c87187010cbfc8c01572e72775dfb6e12e07e8e4e5ab0664dfd7a1456d92f1c30e4f33c70dcf2efc55e6a4ba7f1cac10311ccd3018092db010001	\\x28dc6c9375413b0b25f86b752a886c22a9cd630e967444d78bdfb511649663e0b085dda67c9cb141056649f602265b08fe0e0d88d4f6f7ea5dca482890278e0b	1669564843000000	1670169643000000	1733241643000000	1827849643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x65590056c431e4b3206e88cc4a37d1a189609031d559c34a6959f1bb49beb7064603101948bb36ce785e6ef1a774f6d4f0454c89f2fca48f81f39ac13a96ed60	1	0	\\x000000010000000000800003d46b46d47301f797d6916fda1168a09f6260b99bc8cf2574c6fb461d68ec02e74d774908e9259ce19b0e80bc90ba0351303d5ce9edfc6d732c4e37a825e2d440dba588b649f5fcf99b266e9bc852d914524c509756bd930dfedd6fa9ba2d8031b17c9a26773ac3340075c40ab74208c610537cc00939fbdd40dc70f29cadfd87010001	\\xd4169dff2ef8d60569ed70b23d08b163db82efa1922a68a67d661c21bc8aa674ab13ffcd28937a19981bb72842281fc15de02499d1c721364f6b18344d745102	1667751343000000	1668356143000000	1731428143000000	1826036143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
153	\\x677556326a6a2e06c3026594cfd4be37b1d7c9684c6d66588d5724b8c8dfbdb50d07539a80d0f7dd49d3ce6eebc157871ce86d9bda119458851af9f997fe414d	1	0	\\x000000010000000000800003c57245da1b1091463dec23f02ca93708f8309332164b1977d2188b0f8a602c977f286d0dea6ee0f3014cba85d79daf7d0f071ab4ee784723387190449827f0be89b5b5ee8f5e7802249ffcc77b98f10d26631dffed3238ae52296875da39535fcc957d29a69ea9673ad1ef47fc3f7e2daee59f02289fd5fd6153dcbea6cd8e71010001	\\xd870b21682290c5f84afb9be348033f7948cb902f6d26d69ca9baf477124d3ddc5a5b96432486a91bda664b2a0df78193b35e854a27f36e1f085a0e4b081640f	1681050343000000	1681655143000000	1744727143000000	1839335143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x6a3d35ec3b3f1f722e98a1c1c75906a3014643647113535e47a865ac33230c0d306598d0b3afc3b224609c08c12538770be0f7e4926890441c0f4cc50fe2642a	1	0	\\x000000010000000000800003d8cf54fb1fea784487e28aa55f67ffe539c887e9d3f3c964353f915e0a437faf24308eb3daebfb8310f7b376889e1ff280017caaba0691b1d2c4146fd949c171e8c99b831f756ad06e28e3b568d5ce7c2aa062e4e55ad3dfd54a13458c64ec873877c8c68ab53f9364cdecf469694d326b3b425ca8a8b38130b50e8a7d639eff010001	\\x41b672fbf53397fb80c0eaa85c9e27c374469b92d8a6a2ac83e671ff1e18d8da24591fecdda0419a403cd82a33dfe9989e9599361f535af8bbe6d7da1577170b	1680445843000000	1681050643000000	1744122643000000	1838730643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x6efd4439e2f8a8f5e67f28b471c0981e035507f357b9c6e32d2b7b92afa49e46fa777209a99bd84de4030c4ad5a8c241b03954df0d9190684bdc02b5c4bd52a5	1	0	\\x000000010000000000800003a1128cb6422efa206cc888e9607c11f622e1479460ff8063efbef8858f19f52dcb45d2930f10f5dc3701645fe3785a3444803228dea33e7680aaa142737cc368111d3af827711a5669c24f4ea26714c62efce7edc8967470a3d4cbd8670404b2d22c1cd0c4d0287850711b35b7f33931b943d2a43d57046951b95f158fa9875b010001	\\x6c6b64124ff1e1dff3218544b1f5c973091e28786a30b5e5ac6f50340a1606591220b5e294e16b0c2031878906425c6e8089049d561ecdc5b7fe93c51fe9660e	1667146843000000	1667751643000000	1730823643000000	1825431643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x6e255e1d1e8fa7f6a22d0b97b2d693232cbbc93190d955a807d1ff2df22079e937d94ac6a22c9ff345a8eb3bf55d42b417c1efce4f840967e6a4d6ef2cb0ec32	1	0	\\x000000010000000000800003ce9f2a478020c44a69dbf997bff3462bbad1d67a8fa19e481f2de9e97db141c7eab189c3ebdcf0a958b681ffec5f5377e413fd7b16fedd7f4892eaee108a5a17c3fc646ac86762d3da401fd6207359890fc5facca99b3647bd192f832465d73fa24b56f7964fddffbb443d7f5fb5aa3bc1ff0b08e275591e8f39349eb0a47957010001	\\xe57c50ea3b53d325bc04c2ed19a35cd43659c494c1e1b96ab7f76a42d1790cf2231d7b8735f0fc324b517e0ab6075414ffb5406e04331d79c36660f67edf2e0b	1670169343000000	1670774143000000	1733846143000000	1828454143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
157	\\x7241298933dd729cdf528206cd43d16659000438e0b2b11a539e6f2af7ef77da7e5445e26f96e16203d191e37974ada62e53d57cafc3750a3d6cbb51ff13cce4	1	0	\\x000000010000000000800003a8031700645831f8266fa24b8cb98e4db23281c8397ebff4e2de58f1960ebf4e2a7585695feb7e1ddf70226fef296fb67e4b17291ef3bed340bb21e471c91564838b65404f57b612ce6e182115b21186e2afd0096fa1823907808ab07e1d94b9c6413590d01dc98b618acdb382e7c4b7af7f5735008561494ca69116552740b1010001	\\x37398274a2fb22f09eb276b893dc4494b91780d1a1e5455d3fc63f274b74326dd95e18b99bddf1d9b5517988310511049f1823ba8ac6c7b60cc08b895496440c	1670773843000000	1671378643000000	1734450643000000	1829058643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x771d29fc6e9ab73d063b26b85b79f8b21b64dce255717fb5f639f02f1eab2990f6ba7b4a8bc11d6d8e36521205fc5cd7f063c6a0dc8beb13d5c72db8cb126554	1	0	\\x000000010000000000800003eb015f6276d5f3b36d794af43c525bfe7d710bd42ce4babb27b52d2d7392d51c31644add504a780a29ffb723cbdf4aebc9586cdd9c1486ad590d6bf6fcf958185ecf7f65ab29f65a2140de00acaa95a2b3ddc96254db11c034bd447f45f46ce7c273ff82f1cdfca58b1bd4e93f84856b19625773790de5d79dc9686625d7ec65010001	\\x9e530d5634a5849f2b6a808077d9d6fe6fe0df84b83a5c51d8c57786d029b66f9380e7a7c6a6646bd5802b7d43761c33f14c72dd4e76ab153c1aa71ec2589202	1668960343000000	1669565143000000	1732637143000000	1827245143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x77f5f2709bf6e69fce331df0fd3f90298eb3b49416af37da8a96e537138e3bcd1e40af4033400ebb65654507f07cb3158ca8c1a65e5975905127831fa03657b1	1	0	\\x000000010000000000800003b6696b669b2a9ab9829c0948699033a28a9ec8d04882a2ada8ed7cb46806e3c779e3e2cc893ddd63dbd5d868a9a57e4b9677233d97756c50c3e5056bd2d2d228bb66870051e6b606316ea47c95ad282bbb874df381382dd2d964b26f745714422444e60f163ea06aa593ec9c4cf319b13aa1f2b3888310602c85393228099997010001	\\xd3e6865aab06d04a306b28d2ff31f5d02d150f5155ec6a42a65c3bfb3fbb7d4ea19d7a8e37ccd269c1558e118c8d8bc6be401447c78f348465b86619ddb0e90f	1671378343000000	1671983143000000	1735055143000000	1829663143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x77e1452997485b4a0eeb0f8597f28481724f817db8e2dcb7aea85d526888365edb1dab90fac93ada57a634232f43f58665a5b7066feff2e8d103521137a01e80	1	0	\\x000000010000000000800003c49ecd8e81cccee23f1874810e59a3c74b7eb670acec191ec26b272899eaff1bb8f5907f7d6f80d00d2eb60af7af4c66ff7f9596ee88163385034b19ff5e1e2c0e6ce1d455740482e8c73a455933c5001b0bb390683e9655754bcab44999db37a8b70ec386ff98b7ff8f19d89b419bf1cd0ea90d0401eccdc1f126f355ed8a57010001	\\xad18a534a098fba3b5b1139ac7a0a4989a32537d28b328bd07b8635dac7243cfe573f0342bd9ca76a4c65b5bbb00b3dbe775f20d31d639d3829338c1b4a7a80b	1674400843000000	1675005643000000	1738077643000000	1832685643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
161	\\x793116017ab74d8dc4b1d943e64a89bea19deeb04e91f52c8c3f432485b51eb8b3d16defaba0a973fae6ae6afecba0f11cfb2f23a6b840dddd06e383326f84ee	1	0	\\x000000010000000000800003b07f8116c851058fc81c92d554762bf6823aaddb0ef04a0113915766c65281b33e98ff62e59b8003ee8c0dea05860eec860634f8dbc141750f654dda82fbb06d7f7acd9e70e74adf36d60889d68222c5aa046a14c036582ebb3085ee74c16cc1350cd540f82147e6fac20539813223601264da180b5fe129da1148c09fc91511010001	\\xad64720d2f2555dda1a9f6338ff5c03aef14d21e3dcdaa30ff6a18e051248c7cdb5b74a82d34ebf5344310a8432072f8d2e508c904ee7383e49c4c00a0fab709	1665937843000000	1666542643000000	1729614643000000	1824222643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x797588340b4b069258433aefa4983f4adf869842b1972ed362e1dc84d7858f896e20c38582a75bf2810b29684f0797840bdb53348e79f33e824b191c386b69f9	1	0	\\x000000010000000000800003d119b18deed18cf4dac5259782c5a4165045684809efc50555691e778dd74bbc01c9e2b92f045dae4cc2d182d179997b1d0fcd3f0818e920881ca65544c4f035a350b18fb9b02415cbdcb0e7e4fb376e23c197460fbc24ce26d5e3da4e85a138b510d0b9a100dffa0d361de74dd4e0600f42bc0fdc3f1b73ea0499e06546991f010001	\\x358e2ccc149a45f34c8539c360c36237909f0c6f07f58f1ccce325cd1b331070a2f79c93a0f4a4449eac30324b3339ed63ada04ec1d79ee6cb3b071dc40a250a	1666542343000000	1667147143000000	1730219143000000	1824827143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
163	\\x7af532116c8f4b81d15a72f179e416cc45698d0479b939f1de0778c34f420aeb376bd0e064aa7b13e1d554d203161d42b926702e77cdcebd372a6cfa5dea5ab5	1	0	\\x000000010000000000800003c6cc54aa5ea3c777f8524c220e48908b9c67a61fbb523cd2b5687e1bb8f4103a09b3cb3aaf8835e63156a2e3b081384d84d3d00d6d0ed65c42330b12137b25179cddeaac1cdb6eb27059eb79741a249715ccf625279292204b66d683ed58885192240b04b68ef0dd528d0c0ec461c942a4e896ad4de116eeb247223916ec5e71010001	\\x7ed3cd9c9b9ffd4e3a2f81a01fcefd5a0fe8ee235bdc082e2472194edb04353839ad8eb410453cbbf87217030b9bd92c2ac101cff6001d1fac0e01d810d84b03	1674400843000000	1675005643000000	1738077643000000	1832685643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x7e39aeb06d2a4bfa420827e8c86e267d4d0f6470a8b6c711d6a411e25d5bf7d6bcd317e237adcf97360414c56a9eaba1df56327b463072827f19a03f5a79480b	1	0	\\x000000010000000000800003c7dfd7f3f39f4b0058536382c8a83ec6c41c42c905f20b9b124175b64cbddc9bc6b5f64ce4b9ada0665815175a853be27ccfee7a21bbd34ab19c3fdf379120b9f1a3b9138339e24e27c4786da1c631482aca4944e0e48476e345cfa34f240563be15cc21de9eed14aa80b5a14c26d8f2408368b4fdfbf5de7f863c6f122ddd97010001	\\xce034869125b83d9f484307451c90b82009950583cbf2e1c2d1b0ecc58fda5c72122ba508b633ce15e02b28c94c7593445596ca94dcb0ad4eb4e6604cb71380f	1673191843000000	1673796643000000	1736868643000000	1831476643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x83c1596f29f13aaf451900e8e7443a88f648230d4384d6021b5bae9b16a3e0e4718fe8f5a1ebf95681f82c73d2f834f746375a6a992914ec228c21c9169a41f4	1	0	\\x0000000100000000008000039c2e228e2ddf1e60bcc5d93620c109e015806966d58aec509b3e8d4979af44b6a78c2d1fad1e4035acb883486be2d14fe7af90a70b458169df431e2550f28041cba7661454c622e53cdb80adfe5341a671d57f359f52076c74e3429af8236d7f92e187ce6e43211e7d3bed0853edb30a8a7d11bcf2544cd02dc2fd0935dd838b010001	\\x3cfb469a883c198a3bb3e5d7ebfcd015a6b490c08f4754815eb1b72e46627b2372ac36162f7236afd6f0dabc063f593dd7851e19f56aed294420c18f76146f09	1676818843000000	1677423643000000	1740495643000000	1835103643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x860de5931dc8ab42e0e8cb32aa3e523c490c4b4231580a1f5395d2efc3060528a3359b8b49d571a8f0fd0c32e4f1992b74e66da56ba62cafd65136125b6d68fe	1	0	\\x000000010000000000800003eeed28ad3a756d3154723f4db376060f1621dfb8313de144a46e6e5a80dd6b368deece80141e5ebc0b1b084518824b53bcc6eb3179217ac031594e8f87e5dfe9a08363710666e84d3acff91546827977aff31811eab38cd79b59e5d41b9a960a3fb8f08e69e4aefe557b6d37dd2d3a72dce7990c9cd4bcb30482f16175abf0e3010001	\\x090bee07843c8e459695c9125b608e3bff35470ab97aad5e04557ba8d3aadeebea2139eac432ad1f27b6a304788200c792aabb1267825f513b00134f2c29d00e	1655056843000000	1655661643000000	1718733643000000	1813341643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x86c5ae00f76682e148f53a896962154f9a0c00a220c5e01f1fee74fa74cb10a40c7b897724aa5bcda9ccabe4d284ecbe606b3dc58902e2ae500de4bc093db9a4	1	0	\\x000000010000000000800003e63fdc788014f95b375e2eade9524d4769b9e21de044a3e03716d3bce15378e2bed5da17c8d680c83a07583b82abae4ebf69d9b47d32257b101ba95bc32c9765a65f860f9fe1f08f7020f4805a4442b0834088fc8ac4289672ff1edded69f7f9e4b08dd6d6f97c877313263bf1cbaa3dd9d6825ec1b56e65458284e1c321e513010001	\\x0bcae50d3853d7de31dcb2aa12b7e3635143ccb37ad9bec783f3f063f49de6b9e5f1344c0e9ea5ffd928cf1ba2257fcc9a11ea1167000cee32ef7349e8904b05	1678632343000000	1679237143000000	1742309143000000	1836917143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x86759efee041eec4a70ce636783beb8136ae6a8d4ed3e52f6bf637523686ec843e7b0c0a138c8fd7bfa081e6690934c1582e575f298478cfd6baaef33c1b6d65	1	0	\\x0000000100000000008000039f19ee2386cbad782c6e0be70f7b95d9d4ca976379a53265c5bb8b3ab22aa2bdc265f626ca92ab4c227618a7e9557eb2c6878f5f5715aafc46105cf769f85b791e3ccdff7b5975b2aaf3cd52db4bebfcc28232e4a1eda5c2af4232cb97a62b0ee9bd5c75d6ce3078b776ef63c4523034b059dc4a821d0790ca8bf2c8140f73d1010001	\\x1f4f69748504dee78219a2d6b9e4fb5575ea9a5c5fea4365de1b6ed4999185a2b51dbe102610a96138aad49b3c370bd56cbd5b6f4c505369f6c273aa2fb44f04	1655661343000000	1656266143000000	1719338143000000	1813946143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
169	\\x899df1c5c6d553dc0ec4314e0808837e41b97e17dce187af62f653c4cae0b92af72e3bcaa17b14117ad0d5b4d742734d096ab203ddb734e1365dc3da7d1dd302	1	0	\\x000000010000000000800003a42a9897873e217e04533741ca7cae6ced0144df261a65551aa1cb6a6f50634604e9d35be0bccd994a937542c7b831afc9f3c3c4a72a70a474e3d5fa88405229574b25bd598c9760359ba74ae7283c1a3ed142ff42c8a8801e4a8cd474c83affe21a3652bbf4ca54b554db3366233dd124b157a87b67d9ef3f183144060a0bf1010001	\\xd11f3c8783822ae34450d0e597b70578b3c0098aebc7e22e3d85f1baa9effad952e9c1cf54148c0b196268a08a867e8659841fbc4452565864d1a72ff7c91c0e	1668355843000000	1668960643000000	1732032643000000	1826640643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
170	\\x8ab91e8c47987f08e72f09b5957476683b89b346995adaedae108b55a181b2a4ecd52e381599721dc0e978c39875f6db5cc5c4975a5efadad329bd1e2936d236	1	0	\\x000000010000000000800003c8ee04cfb45f29399ba8930eaea8d8be10b0fa62692a86dd932e5d7608c18d6d016980c020af01786f62ee494dcc1eb3eb142b5ebb88b9579aa1894d9ee9600e814840b7f585afe17060c25ea28c4e13633bc212b2da34bc43b52e1ae0733faa2991886446da6bff7cebcfedece093ae40e8669511d916b67843ab429082ac81010001	\\x1f7c5d6c4cd9cf8f76d80d0f48507a447f90e1946dcb7b530ba6d53ce2b156b7d8a2b87d54994c1d7ddd678b2883202ff70ce9d99e4834ca2e6acc71953f1e07	1662310843000000	1662915643000000	1725987643000000	1820595643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x8a81d5bdc845c3b5a896d693f462348d11334662608adaeedfa27f5fd35e2a8e7848eb518dc9032c6928012fc9103ea49b345bf9c8afba3b42b8f218978ed7aa	1	0	\\x000000010000000000800003d4970c9440a244f29cea2093f01be8c2d2668cb0789f258c7e8d0a078c8f2efa9493799eef8a8d2ca492dd66ed0cc9d534931fa18c85712007b8f74f9031dbba0fa536fdf4c1c3a0cb2c60e6946c29c042e6459d2067b4ea833f8283dadff0795de70eff4d78042a32ae558d26e4d7ea0200d873f87a49570ce6aaf83ee82405010001	\\x6f15ea5a46b62eeacb1544ff8e905812fa70f6def9fde778595a9c32ebeb05cc5afef4a97510ead457d2399bd8c77a755aab91f0ce38c07ae31cdab9c4cad80b	1675005343000000	1675610143000000	1738682143000000	1833290143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\x8c1971106bc9bd24675f0f42a27ddb7f3c45a497f3b32f1e05c4d40e98f0326f05a4c724f49cb271caaedf494893297f62b5c8ae6f66066a7515863e73f4d7d1	1	0	\\x000000010000000000800003a5fd1dfe32209124e13c22a883a4742f81ec4de7dee400b801acb76726db006f5d895070818d2c63f5321f0b1eea8c406aa7096ae745dedccfd62a59ccf6195527ae0ab577d7695837e717c31178142230a049a9eb784eab5842aeb8e28baec74bc1b981ca0f22673d1ba971e967631c1f7383df5b1f9ca0584acda6ca7b4115010001	\\xfcadf22bd071d7d46d6ef2541c1fa8910ffa9e9bb400e0a671342b3d977aa40f64189d989719d67bca0be882e89260d129dd85ebadc90126882a88aa5715b502	1675609843000000	1676214643000000	1739286643000000	1833894643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x8d61995a6309fac525b17c614e698fd2b738729b8a71628d15a241e1c988592ef6f350aef6f363f73acb9825b21cdc5af3420a3d5142d325814447a3796b257a	1	0	\\x000000010000000000800003bbf338fac24bcfbba51854038cd597fc3b149789627329866936dca2d88d4c1431e9e6945e46ae2d5c08408fe5e30241096b25abaf2d05d97a99db5d04d4b480be8f33a75d7c27dcbde3b7bdeb5f6e8d217e9bdd3ca8b627c493a4b87d8aabca6c9848c260f22fbb0ca00cf4285e3f999b36bfe0fe7d1abdaf61f8349deaefab010001	\\x81d57bdb2630bdf1e20453fdb48c95385426827f62a779a0c117221c43c1ad290bd4125154a0fb304d180da5d6db9e0d06cbea065a377b53bba2f925f6cf8208	1677423343000000	1678028143000000	1741100143000000	1835708143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x8e89998467c9f70b7be9779d87f63340a5abe3324554d7e65164f92df4d4154f16f466f464712161c1af87562c37cbbef8caa8da04fd4fe0646fb433862d5797	1	0	\\x000000010000000000800003a8f9df1d7f06012c38a22b92755bcb49d9f8bb664b8e8d53c10af683f806d927e812042a6ea8a5f62a3d1e15ef81fe5e0a7a5deee362455724557ad3db806de394d215086dbfbb2ff428f9d439bb73f46f1cdbc9486d7771d20ca1de3dd6997d7397974448c1d775740100094c27690b6471c3efc98588d618f86a4e01d83c65010001	\\x753a9f31eab27a2730c92dd1eaf5fb15684462d85936e74e4da2cf16ae989de9528b6c6eadcd3fc192ed2ee7079b99851da70653bc6d0e846b3fc45754b4910b	1677423343000000	1678028143000000	1741100143000000	1835708143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
175	\\x8f913b8635d0abc279a1d2dc7e8770df4ae9be8f305443c066e87add7e1630d7a1999dd8d36bf7827fd657402a8a9018cc6429705bd0eaa743f8b17cd73fb16c	1	0	\\x000000010000000000800003e7165f69b3ce7e5cdf562c6b7dbb729e5e5861b551bcd34db308ba1bd075c01e6ec752b3a999294e91cf7222993217ed2e8796b17b470bb4ef08fd64d921b9bcb4d33c59ae5833d6db7d498c1e1e55203aa2c36932e1ae8b3d915597371efbeb8568d17b77fbbf83466db9ff7d5b168362fdeeee16991bd321d701f66c0fd557010001	\\xf43e25be3fc6910712ee9f57e602c4be4263d02e51a5c399f3441df485c215246ef4f9413625abbf7c2bb3af4a7dc260d8e396085a3be1d40de3633f53da290e	1654452343000000	1655057143000000	1718129143000000	1812737143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\x8fbd5d37e0968090a8535026b878a8fa354cb30aef0f8275c7eef535adc8f95b45c22596ee84ff6e23aeb59826e58a749bb835c23c8f0d04b45799882b7b5160	1	0	\\x000000010000000000800003cbc2d685380bb484d848939367e66a7249500d6c8314aeb9e0bfe2e321b6880d42a57511e2866f701fd119559e4e8aded7d3a273d34fc73b8d40fb1c62ddc4ce8aae4fdc03b178a8d1464abe551d0fb8d5a6db5518f0c27c0a8b55fd2d836219fb4ecc3911e9140096c1a791caf9aa41407736ab6bb42bd100ab8e12eba424eb010001	\\xcd71c6d277314eacb55869d12f0f91ce78b6b7aa958ebd86b923828553a1de051f39fb965230b9b36a66906d2a63b15622b28d102a0b8524b6a527159147d408	1681654843000000	1682259643000000	1745331643000000	1839939643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x93a1d908e0e48ec9ce66e46b12ad41c48e93f6c81dd7faa079c7f88443f47750fe93eae8df7e788af7fefa98f56b25c8582dc2de050396c1a6e1b560abca445a	1	0	\\x000000010000000000800003c988e0e1a520d8cc5c5e50550673075743290178db60e871944471eecd40b1d36b101a5ce2b90953fcf6c4f63489d8bcd93808dbd9bf86fa0db9b86f244f00f5a9a25c9db35839705f87db5b6823dd6c4737cec06a63ef7a7d87513036f613fd3ce888ddcbda5d542315c667c04a2f637b8d594c7dfef30b97efe987a7d07fe3010001	\\x20399b348cb1b1e15dbc8e8b1a4e973cae3f97e6bab517de81f12f26b4f6b73b954cc6906c517f5f187247132595ffe0f5af7d66afbb28436a29f1c213ffe80c	1658683843000000	1659288643000000	1722360643000000	1816968643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\x94a107962f4a867900dbe7d0824fa99b46b55a0e6f0afa032e1bb8daed8218fad4ae62523437a350be574d206fdd60208f9e6effe13894e52feee58d8da40df3	1	0	\\x000000010000000000800003cc1fe7d22fee74c1fed604508682dfc2cc8eb77a2f8ccff45dd92c05ba45b13708b3f9d752c9abdf46e0bbf6033491ca37e3d27c1c02835ee3e0fb9069eed217ad654ffff9a3c47133aa8f6b3ebfa5a3485ea0a587e83067593e7316d35d437f77589bd57211c2842fe159f60df0cec4cd0e5f2f22b06d681a488606eedc5b5f010001	\\xbe8c43dda4514e84f643cea9c1ef8a5a3cc2d68d1f0d291c4c758060f1908e0e4cc77eb105446b042bc6e0a64b75b484f2a4725d14cc008022115fbd5ea5de0c	1659892843000000	1660497643000000	1723569643000000	1818177643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
179	\\x989dd2bb13780aeac900542af15c4305f4fc96f9a3e54951c287fa4411096767502a6b36bbadf282a773289aad2f9f2cf35d55b6f636abe97b00b4be35804055	1	0	\\x000000010000000000800003ba58356b83feeb07aa015b444e558a8794c73ea7b0aae374967813ff3a6b2348a106b08ef32c9834b077fb7f44dd453698595fdde5153555916048c7a65e49e666deadb8ce35381b0aa85b6ed0799fd0994fea692e2f1fe469d08b5bea0913c69139bc1bfa595fce349db3e21f6b1f5b75aad735235a18ee10fd65c2b1e29ccd010001	\\xa5651022b2428abfa53a49ff007d71227bd128931a8b19b241a53d301c846f761442e044a529d98381e4a1611d9296747abf5a3533b5b71c376e8c6958f47406	1653847843000000	1654452643000000	1717524643000000	1812132643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
180	\\x9a65bf914f371d831e3f939f40d7db917a4f8da4de6023115b9bbdcee349ffb781cbf8b03332c9bad9f2bc6c1d8535cae9ca669411e912b8bebd8aa8a086d284	1	0	\\x000000010000000000800003a5844c30610f7dbf64bdc3f4b395a8a0830c30d1085428922c3a7855c42056fb2d5baa5d08fd84ec00a46c21c33ab18ef317090e9bd2c5d1146e3366691dc28b90672fd8dda3c2e7685e892d5159cd3aaeb8c3b697061fe82b3691af90e937d4cd330ec48347737dea26990ca05e3c46137920c3974fac6c1c00b3b472cffd8f010001	\\xdb99f671a5f0860d75da017a3ba1b5e8f04c83309d68b46e2548e4209d0b40ca04d6fcd521d98cea7656da113007eabdcf6e14b6eede4c7afcaf105093470603	1681654843000000	1682259643000000	1745331643000000	1839939643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\x9bbdcbbceb92a786829bfd164a7ec52a8261fec68a16c9a8d56764aee991fa9a6f4f366cef4a0dddcd6217eea07bfbeb3f3fbd304eeccec1ac6552952bb4ccea	1	0	\\x000000010000000000800003ac93b108b58c6a149bc5f0e2422c53f7fd1456f26d61f1fac959d2a0eea0b8d5278d4da9ebe8a902b707d9225285809c9844ba4a7f70778f1cd48b8104f78a3bb146facce17f817946e743d6f221117696b138656855e507d5699392032d5e61d6691b9d042657a0a1e4445caa6eb802dd0900fc1cd5fdb8fd07f1fe5c01d3d7010001	\\x26f264b03ec360067278fc81c091a61632b0d6258329933ae6f065a406d03772778a6ea27ccbe5c8d6cd14fce02bcd02ec44094d60ca3db3bd99511a370d4b0b	1682259343000000	1682864143000000	1745936143000000	1840544143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
182	\\x9badc148f79b8d9044eed04543a3bb012db1d47f2cba8b6d87ba74a84322791276c97552aae02dc1b6ee8be6168e3bfdb83776bd1673449eae53a8b59b68c823	1	0	\\x000000010000000000800003daf2c14ec53c84d5ddd9efc3a7d07e9d87d39adff20578b4ec03130c95a775ff40583524dcd07ff82203c5bfabc573f472b7d34721fa0e4806a974dc50fc87c4aef54e8ed1c23b27f3b8262020b6c9583d09add786f2ab19c2d1e4bfd3ed502ad869ac78588d8fbbec034d6b6e447b6437935a48d24d9036f58dafd2578bd84b010001	\\x3501d0424db4db00ea9cf94e54b8812374df0b02e1ed47d9e3ddc843a406e0f5a0c1988686ecd3726a0acb442fab6ddb5acc3592ad7c09acf8600e7ddb183e0b	1676818843000000	1677423643000000	1740495643000000	1835103643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
183	\\x9e4d250e9584a369f819f9896e77e725f161c52c656b66be21ad0bdc30fe3d25147ff2e2bd2335b4520ca4467af38ee366c36f3a7355fe72afb42c7b3fd44f9b	1	0	\\x000000010000000000800003d4a2fbcc4269c4b402c6fe6f0843b0ae2090546570ff34e4991de0ad9102c7d11fae811df41220bffaec6ee11f97d2dfcfbab10f1e8178b319a999af875f462ccae3e0c725de7b5304882f01b5d615866384e8ae98e25c0bc05c556ac756b3ec2614cfd8f08e78db18facc64eb54df0e2fe186eb38618b15764689076da1c99b010001	\\xf6a0779deb14899a5aa6da74c63c90f85c93f0b66894833f5fd99efb0294a73f42103363ef1bbc6284ed0749bf8594896faa800a3624887d48620c545652670b	1677423343000000	1678028143000000	1741100143000000	1835708143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xa199e655e5764fe93620ad5f291704b553fc227e94f1c9db1a3293966df27455373c95432472f75718642df5fee48d0aebe6453b212aa2010dc17ce4c1b29422	1	0	\\x000000010000000000800003b10b2a879894ce5b31ee7c6da4aed6f09d3b61f1c637d491bd7e1b8f9f5dece86d2a1d58fb900c5373f456b60d9f665885a5d86a42164c387a85e8a77f7ce0c83c0d078012c3233ba082c931e0d43ddbf337019d31ac2d5aaeee6983b1b84ebf513061819e959f2ab0fd653ec834bb7d9e18f51150636615c8423d39b2c3073f010001	\\x66bfadcba22fee19aebc321c2f5a6b3e918dc4cf78ab6cfb47eb5dba299806bc9a8ada782e56e86a843088d807e3f3a46325944fc4813d2c642005e70f535101	1663519843000000	1664124643000000	1727196643000000	1821804643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\xa95500cbad4564a0c07fd137b6aacb95b13ea7607cad5ace5ba05f8847ea807e3aeb735bd919a6730057c6b6b6766ff29b12a9af139189a9619fb60c3834aaf8	1	0	\\x000000010000000000800003c8fa593d9427acf5a3b03abeaf8aef2c7bf0ed879895800db95e3472380947ef3812d9b691b7311b34785906c5e0cf3d936db70e3ec999a2eed779f791f8eadbbf4102ee217cd13935d661d6878aa2339c983aa49ebbc7d41091b50e5af476f83ffad956394d69c71a67857e0c0083df40ee940c5265376b9d209b8ed73f75ed010001	\\x35389e5c9ca7a9f2657342df885675baa644b4b181a3b4ccb77532d18821ac3d269ae9b1b57a3b4fdb9254941a71c6735490e04540de556c8ae7e9fe5897a20b	1653847843000000	1654452643000000	1717524643000000	1812132643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xad8ddfe74eaeb59c925ff546f3dd73938d498b99876868f2c435368d7a22b6a6d019619981c7b40952f2b94f0147a6fd315eb716433abdd9bfabcd626e378353	1	0	\\x000000010000000000800003b8d75a424aeda27281aa9a8820521c580ed065c0d43a8dc67c68b3abd07e1cd3836a3c12a8e7af7c8e3bfbe8b298ff8b0658f6c3171adb29a5b4d5772186b31d8573947ac74b5c2dc2a22cab5261fb281a433ba35b79f388fb9e664b9417c4d0b3cf135d9554408c98de7e306ce76f806b2d803b74588ae2406963eb56dcf33f010001	\\x2e479cb7819ffdd3663440b1b8b173849b0ad1df096e41fdfc73fef637b5426995f922b2a9a3b6ea821c6ba572c5aa443b58395466649bad879f35fbcd67d609	1662310843000000	1662915643000000	1725987643000000	1820595643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xad19e25830fba5eb4c5c3b957ab60946c4a7f20717ab5de1a91c76a0f47f50fb8ef91963a7dd27e1fd6affe621e405b50b4e36bf2f1305d84aaf8af0cc1b460a	1	0	\\x000000010000000000800003d9ef08d0b790e00c1349d4d24e2974574ed575c1b6382ce47af35dadc985084f07e3860652a1530a188cad0e284bb758f2dca34a79b4131f2600ac3f96e56eef2cf604db7715514dd3792ee90ea8e986c98ae0c67ab9f27cf155baa61f46c3b5d7dbaf18394aa1565006ff11099c8b6b86f5953e128763bfc8139d6caf915935010001	\\x12b52a45034c23dec814e3e32e1ede01d8f296ebe40b982da22e69006ea200e385ff8f4ffb3ae2fb72b42dc004c86f879b3f7c09f350a8224d3baf6bc892900f	1670773843000000	1671378643000000	1734450643000000	1829058643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
188	\\xafedfb8e8fc890818f9e07d115024e477dd2161a467c102e86846818eef37a63f959b40435c625b02d605a0ce4c59582df9e8cc7323f457986fe00fb3a7bc45a	1	0	\\x000000010000000000800003dce94dc9d85949f4585b4005b4101179cbf04a96cbdb4e029d1d3fcdbf781fbd48b35e5bf69c167827c6c217603135d17947709d58fb294d29c7919581f402ab6c783288eff2e4d4a4e77a352b292b7fa76e7e3393fca588c272f78e30359c5448d4880e775768f293be1f0c51d5a5cf119523d483bce98054fa57dc29eb8ecb010001	\\xa2a361c55093d24880f1289198895907fa5e114feb0f6cf31c4922483822a1d5e48a6a024703a0e081746f6a4afc558ee6a83c92e545cfcee25e302c427e8301	1659288343000000	1659893143000000	1722965143000000	1817573143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xb395cb4b2804cbe26ff92f2863e83e18d78b211e3a159f81bf946223f6497946cb34d7210873064fbe233f564285f032242fab9effb2d141f9c9dabb5b67a721	1	0	\\x0000000100000000008000039a4875b69ad54e5f77d9554266a7b145a42a8a6520060cc5ee9bd2914aa5ebbe6fe59e9d70d908bc777466f20306914e29558e31e89926f8d91aa25c64ef525ca18f6b575184967a09e45bf07a89564c91387d17aef0a33e025b4465ee1e2f6663704b707b148b9eab0f91de67eea2a6b2d55556c7c644a0b80d0dafa5c91f55010001	\\xbfd1531b00dac3b96e00a07c758abe2a1f8d849ac5b8a72e35cebd56018a801165cb24f6bd4f34f03522ed73549a4a3e8fd9022de095ded7e05c9ed9bc470900	1678027843000000	1678632643000000	1741704643000000	1836312643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xbba915f64a34cbd51754103c07cd7db5c56c5f0dbc3ef1bbd6f676e727148f055d4b6cbc6b87003cc003dd7ea985bac901b3b2b67fbaeabf4b82e6abcdd410ec	1	0	\\x000000010000000000800003e4447a2ecf69c04e5c053dc7427940de037e01f74d9b690ce332e3b11f1b1d35c6bc3c2fd4119e64e8bcf8f01786e53cd46f04c6f79a944369e755bd30b797983839ca15acfe02e9ed16f87cd49e669a937cb3c0982b499683c3246856a026a3974b8652f8d4f2be786833ed4353491809f03ee4e3e553faec0b617a321248ad010001	\\x9dc0007005e9e8834d04f4cabd7855a25184797c1b4e128ea4f716936c11aa139f3ecbbb23e093e106b4a26186e6998d62340f35db6e8b64dafe9a5b39703205	1676214343000000	1676819143000000	1739891143000000	1834499143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xbdfdc43b1afc6c7ef622a43744a178ff4f783c55198a6ba66e071b0b2abf90577d95c959900f1e383bc0fcd58ff75dc6f04d76199f55ea53ea34de8d55e75c4a	1	0	\\x000000010000000000800003a690f63d9febf13e964f1fc3da50810494d0a71a7b5109798ebafb309d808070f104d5285a216fb094b7dac901eba7d607e86d4d011ddd0a24230fad6428472724ec8818c6f0611defbcace90a59d0982b3c4144ec045eb292e4bd4e87b7b802787a5d0485b7fead3573c927d0059ed15d7474f4a406a7899a2a8f0850614321010001	\\x9f273dab80ac5b7d9b65dbce99170ad5bb5bde5611cce8c35257a35bb9a2aeced64f5734eee09bd6a8b87dbf6bd3ada6a3e478f3c5c4bdfdcaf2db808b636705	1672587343000000	1673192143000000	1736264143000000	1830872143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xbd8d96415d41940065552932883364fb47e505bd335df860e84fc6017d36291df7cb12227c953c2e9e91fa55f2620af6a85e726edbcf1d06dc478ae9e0f23128	1	0	\\x000000010000000000800003a48889ca72db042f00ccc6c4d343ebd983fa149e64ee0c61634f25541f68bb94cd9ba831d1fca853c5b9ba3347d9400ca187a7f2a6028db101eb2fae3ace48e705091d6229be116dd689a850a7601cd3b05c35c797c0c52197300d642cb00276716a1a4ad37832c422a9a1e077e1065a32ff0abd3dd69adb45271a429b2bf407010001	\\x3a90d5a46282f30d166be1609d7a5770f49b92a110b946952af600f1580e65cc48f7bcd1d41e8570aa0dea11f4b099a2e470cd1d20f91f0b1603418af183260b	1652034343000000	1652639143000000	1715711143000000	1810319143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xbf6d785e4b98792fe821894f8dcef5a6e04fcf5e087cdba9240d156c2dd8ade2e2ddcf00af4096c0d5b043415727e36832ab2d0abdbc658262b297034854f197	1	0	\\x000000010000000000800003a57442b0118056cb548e21bbb5e26dcd5ea44629d542614355ce7fc070d07ce8db378a78095dee2daeb94888e80697faafddde8473b4cc28f6a690faf7a0c961268f8152dc854695118f4489dc30559aaaed6fbe5e20030a9f16be3ee94dae408264630b3762ff8e68332263888b8aee3deb8eff3e384246bc76db35b9e4f3bd010001	\\xec83f6485b6ba876fd64554a098f962e2b03de0f508c5509079b1a5076e76f97f687c816d4c2232e5983e9df5b01f3f3d3ff13278426cdada2e02748b043c300	1673796343000000	1674401143000000	1737473143000000	1832081143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
194	\\xc19d53427e4a8eb321385de76b064475a19e38d0be7244c059e6b7bba32745f7f573a55b300ee0f9486b1431b1ecff57be338a4492babf135b428beacc126714	1	0	\\x000000010000000000800003e70a0f121949abf8cbeb2dcebe43b010c448d9d551d248c38ff402483d3bd8631903bfba9fc531b0cd0351422d34e752d0864efd94ff0ed4ce2e15a5b044c7e1aea586122dddbee69508509aa562746c04fa3531cf393c85058c2ac1237437435c42e0552d3f67f1039cfc86824f5855cbce47b0d6fc76ac675ddf6e07f01fa3010001	\\x44e0c736d02abb459118b93ad583b232851af36adcd71e1d6954e3f589e5d9bccdc554494a2dd2ff581178b084a482a754a671a4ccfff5b2f99cd82fbf14620c	1667751343000000	1668356143000000	1731428143000000	1826036143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xc2f1d21340dd9f3faca762fb5d7373f8ff6b91ab505525603e9b742821afb0ec8047355abe4d502bee5b8c6efb346c065471f3078da0409188df1057b081db71	1	0	\\x000000010000000000800003a194def6fa6a3fe4eb63f1bb915e072ceb474942ab7f4e5dba84624e74108c4085cffbbe3d612d3b0d9c97196b17e84c915c6b95a78c0272479dc13c60b4f67002ad3da4cef67e8cbf01cf6e15018daf6e7491447c964a029fc8050cc0e7b99b49151205a2a8c13b175374ef9e9bda78d08a2d3f2c1d3be2ff401a978f1e9d1b010001	\\xf600892cca64f9d8ddb5e80679ae59a43a103eceb303fc2c7b0f93ca5977c5d75b502bba09124bbaefb9d6bc5c1953cedaed7fe07068822a2571289323921902	1665333343000000	1665938143000000	1729010143000000	1823618143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
196	\\xcc0574cff01a14804517cae297b66ab76c80b3a782e360b9bdab81ef598b51f5cbfc0408b893a45d9138e200c3cbf243c79584fa9696fe90c586175c87c75be4	1	0	\\x000000010000000000800003e840654b84101ffa7c6fdaedcdcf20a7203df3da1c065d420bddbd960bb5e8ca3e469552c06d5b3557ae61ede97099836af0c292521bc36a4e05df08c6c715d072a1bff13989d05bb360b0169239689eac35f26e6844389d2ae648e386ab200fb4e3e8dce56d9bc9d477eddd0f1fb873bb49799465a493f909a26d04560563f9010001	\\x8943c9412ca9291ee1a11b6908d346ec30cdfb3b5412b98d1980807c51176bdb2ace849eb2050b513030b1019164224221dfdd4c6e1953346cbbff68580ac600	1654452343000000	1655057143000000	1718129143000000	1812737143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xcd096b337758e103f19766c22df8e97c05132eee3c3ba3866310475eb2751695d414b3bfd659e0d34ec9b81cbd7084d8d90ea900c043fc55e5f95c042eafd9c8	1	0	\\x000000010000000000800003ce4005fee97d1bf59e414ee614dc7c0fbfc796c4fcde69d0bdbdd959d520bdeff9c5d6ef4577b33c8c8dddb681a5f75901a4efb5ffc736e954f2ace3b5d1b57f6389a6ae339f99210b129519d433f24f4f656e62a49cefd9bd0c925d3cd5e7eab125471c276c3bcf52602d1b1853e4a7a63f536cb3298dd0765572e566edfb7d010001	\\xe7eea4be5fd16566c0a502007bdc48052f870164f6de1dc9587035da46eeefbd2fee74430873ee3e41539ede1124e1efff380ced8899184e84d50ec017a65c01	1650825343000000	1651430143000000	1714502143000000	1809110143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xd3e9edc712785f8b1c337dcd498485554232cec21a71e78baab75a7b2ca4ab1e5db8dac9f41df277ecd9dc8da3d52514e83472a587240ea41b1dd8c1ee3ad5ee	1	0	\\x000000010000000000800003e4b2208989c516a19970e115da96ab16221467b52babca44db3f431f2d8abd9945dd8d8cc3111a2e8815cb131dbdecd4972522ac760a14d4072e5d773016864ad717bb90f364e0bb454aeb87cf18c4af2d1433a300daea4a58fc98d07ac41fd49d87a740995482d581ee6946b9aad0d7d997b683420aac30d97cd395dcc080a3010001	\\x45521b65d620e5789a07d5b00cc532ef631a07e4aae44546ab06cadbed65301efd46ea6e800522cfcfe4e035ad259d26ff13b04187512568881944d70f08970e	1655661343000000	1656266143000000	1719338143000000	1813946143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
199	\\xd529627e70f932b3682219c03eb5ac0810e294925cc77e870d0cdfac879b332efe98e13b0871a5624ff8cbf0b35c6d655b90ee752793f09b21cf1fdc7c1c927b	1	0	\\x000000010000000000800003b525b058a73426c3e148317f05a32b076a87dd17c417c796ddbec0dfc7392478c0a3115ef840e2090e97d9efd39e4166b139f0b28a594e3accd8aef6367c55765f59617c8d02eb852f6afa8aba70c9351186967855fbd7787fc8624472bdaf9a19e4425fccf659f8eaf3576dfef877140f4351b8463f48a6606bd7ce6fe72433010001	\\xcf027fcd4b6a5bab86d0f3f39b79434280fbdad0c7e00c042b517d8325058365ab7382c71b365df9670d359dd367e69566bc164d04420c7d50defc5a38879e07	1674400843000000	1675005643000000	1738077643000000	1832685643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xd55184e614fab11e8397a8dbcba719f7713c7474a453d7db0b769849ff9f06ad1cf63e29126ea089a2118a5ac3a1d35f0e3e85d74cdfebda4de8a53f6aaa97cc	1	0	\\x000000010000000000800003c5870843cfe4af45352e7a5bfa80c4d16d910dc2b1d3755853fca0030c630019efe00d2028b7e7c43db3ab7b17f002a99d5da280cec71f01a2021e56e9d250aabba28aa494b82d90a3d8eeea2af42e6cf8ad0e7fe0572c1feb9689b9e4fa985f32acfe538e3f2d3ce276be5d900aa4be32e71a05a4d5768893c01b115be4668b010001	\\x3d8640c8b2a88ba766d61cb0d4606074ee8ff15a5af257aecd56fa3cd34f3a51093d5a9079979c89682ceeee176d94a770f656a3c8c89a52ae318f05ff367d05	1673191843000000	1673796643000000	1736868643000000	1831476643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xd9c98f4712e956638e9248efe88c58cd0d087899a019ce2197d04f172355ef454f221e27f58afbfc39bebf1f7b6bef7b4b85acc29f4ae2d7b303d69bbcc678b5	1	0	\\x000000010000000000800003d2e619205dc59442ad2f80914482f8b111b859c3b0dea3b5263bb4ca216ef1615cfeb98100bd05fb6816e355ddfc844f38d50cf9670934b924c2ed2fc67a301369201109a9947937ea4f07583949f9289ad67d423b1b90447990c0e60b381794bf4e79d85828ffff03f2fd3fac2c684f6d84ce9d5c96db23ac38f14c0812e8ff010001	\\x4786ec834cfeffa749883fd14deb45bf7ce3485a3f089bc46c6ec99fcddd1cbf624e77a0d46e0aa592f318ac21e644b9b321a04dc9691fe652363138de82880a	1659288343000000	1659893143000000	1722965143000000	1817573143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
202	\\xdef1061569c944eb286c94fde9563d615511538841eb10db986f9e692a1c76bd497f7a3e4863d739ec00c755713f802ecddcb0ef2d5a6a5cd1caedd01094f9f5	1	0	\\x000000010000000000800003b4289a75c921a67006d756dfb76a2744b406f1409edaafb52c0173e0938ab2caf6047c920a9957401498615914475c39682666b6c46e8f224a1c917c6c6b66c8dd33d36e7aba826139fe84646ee8639075d9c23ba655131752a3304b1038eec8ab5d68d6c6b35be785a29b0574d7daf7ae0e4d2a8576b68fbbf92485e45c0bfb010001	\\xa5c23e40db832d4cb455ef772d14ecea341e85df05c935b427a875fda315dc20aff31c78fb97edeeaa7eb14103bec680068690cb4a9cf77af16c7e7ac3f9e206	1661101843000000	1661706643000000	1724778643000000	1819386643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xe0e9943cecff65bf1b148da720a868de8afd03f5e30a2caa375a1abb6b07a5d919f0de83ef0f30abe86242f8998be736455eb5ae5f17d8555b52930977d14c3d	1	0	\\x000000010000000000800003c84d4057c12c648fb73a82cc8e4f4381ae3bd56294d694daca153181cae27fe0c176a0bef747cc90cfb3c6d73261675e457f22395f49a04858528b8182472d23a8a85c88ae69bafb588df76938e251f5b4ceb3d1b1575b0986b9d76f3a0ae2a276af81033121ce79a728ffb463c6513d6d8f72333292b71e50bed610acdc44f9010001	\\x9d92b843aa3cfad14e66791d33b00db688bfba013d7a0f8b5f9bb4a546bbf5e4a11cf3456cfa425028cb2ea2c658de60d854534bac02100871ba07ff0b100f00	1650825343000000	1651430143000000	1714502143000000	1809110143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
204	\\xe0193ff2660d1c58bb43441c21518957e6b8a23ce13edc1d3b887e7a47c3012c7e4f733ee4cb5752d13e0450150951ef30411d45be28f0c589e29a8e712d062e	1	0	\\x000000010000000000800003c8d4ad358dc9fdbde7351113b26881ecf4019718ad883f9c25cbb89ae5d9d63f5059982a052a163e9d7c3ecb26323fb99fabf6920f4033351484844aa727c85932f8c757301841db552b57bc5fdabfadc37380c4c68cc86d8fdf0937b93624467b69e44d9dcd8c4686bac543c59f32dcbb3d1de64b2b8c343aecf31003c7adf9010001	\\x38b6a03a44c35b954f1928d6b24181ff595dd247149ae3c32373216b866494dd1d04b0325a9c15bdec023143889f4080edb504ba5560632fd833b7513360790b	1653847843000000	1654452643000000	1717524643000000	1812132643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xe35591e3e30b9591e71092cd4207c118790fc30491073845a6e61803ecd2fca9ba29177c6494652396f41cc9f915747baf90a95fb3d816b8ae6020941a0bf6f8	1	0	\\x000000010000000000800003b428b74d05e46331b64cd1e89db718a378b526ff5acdaea6e2e3c0b2d9674ec52f1abd0f0df72245cdb043c40839e8394dc12ffa502f83e68c2c4a92637860e86e35219804071573025fe7df81eb570c58c991cea8c718e1d37fecfdc4466526d0d351e44235b92e169243bc8005d26d9b61827d15fc3fe03ad56c77ce683bcf010001	\\x9b5ec77283239bc6104c319c17f3031933a9d5f04ad268ec7d3bf48f0aa8c5ec2c304ebdf196898170cf8cfbd0f2a75831265baa5b7b3410be638879b8c47808	1655056843000000	1655661643000000	1718733643000000	1813341643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\xeeb573f393776bfd1af7e8f350b8fd2f54ce50307cc7c404b9d92a797a121400e4ab56c5bff56a79caa64458870bdec8af9615c8ddda9ae9a82cc5dc1fac251d	1	0	\\x000000010000000000800003b7ce956d44592cb7e6e88e9dc631aa985fc96e89afbacbb46a9aaa284b98951c9dd7738530c557f9eebd74400fc5037853f3a9691db7ae66076195b22c84ba537f2fc7d4be4dc0f8be8b133622f16903791c52430f000b082564ac453303cfbb0a3ce3050c05f0bafdee56a7f28eeda5d295cdb119858b53315dd67310b088f5010001	\\x1d815fd1e8ccbedfea710052c0e6be18696b7f19c6dc04e50bce94065a8b75eae02b7a424d499bf81bba528819c75142fe5c961f61d54d591628ddd0cf8d890a	1654452343000000	1655057143000000	1718129143000000	1812737143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xf00de39a96a393640b522d0bfb0803a0d44addeadfd6cedfd80d7e9cf801681db9399ad394626849b776340fe297943e97284a42a2a0e3e9ecf51593f86be8a9	1	0	\\x000000010000000000800003b5ea0c6f6c63195b2ba09acfdbc570f49fa758f737316e880c7f65fb985da9523a0c67f0fc875535c3350be66ff662f80ad3d366bcbe5b83bf1b3492fa45076ea8476edda7dcbe490e096aaf8b24980552c2f325974200a40fa58467fdb661c0a3f3685fe2c8d142dbb56e519c0743e02845f3dedb21aa9d38d1c03b0f3a3921010001	\\x125169df53a2534a218bd60f15a3d475d5a3175fd2edc9fd080aac9d9212e42205c8be6ed22fd32c4039486a50d27fd8049cd99725ee38cabcdf315604f7a908	1667751343000000	1668356143000000	1731428143000000	1826036143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xf3e9633b5455fbf0f1a1f577630d4c01f791dffd6fa137344494d37cfb07dd0f7079609a1ff401657c028025db47d513c446ac25032a47b0e65febb331fe9ef9	1	0	\\x000000010000000000800003ccfaf897e9e36304124c4e555e3308983c784a1f16ef93a08ef697d4e0eb6c3fdefdff63acd81e26f1847ff4cb98fb9370065e8a80b7b3d93b237409e6839efba20240d7da45774a67c0034ed0d0c639a20c8dce4277d9b3d040414fb564d7a639034e1ad38b202d6c6231b7148c8b462723327a77199780d32062ae4774982b010001	\\x5ee508e9ba74211c2394a431d169d6328b11bb3d5339495f6322f473fd7df8b890e4f74f50e05268584f5b9df7ed9a81e040f48f99516f0f67b0e0643811700d	1668355843000000	1668960643000000	1732032643000000	1826640643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xf43dd94a305351d7fdfa491a12f23cf00617d7e6344752c94b1ab38f1d7898c8de7dbed6d36b18c856a91eecce8670653544563e17f9ded848f95844eff11ac9	1	0	\\x0000000100000000008000039e53dd7c9a746226215d62111451d02065d0dea84681f39dba44c72dea18f84eab866b240c845ad1141fe48f7d031af831fa973460e87e3e8dbb26bd13ab1fe27a6315257b847aa32252be18bcbb2bb0f0eca085c47d755c1c781004abfccfabd9362492ac67ab5b077abd4527096025211bc10fe4cb0f1a540be11e50bd83af010001	\\xfd2ad8905e520e22a9287b93665a66b09bc87b1e2b7f82f7a3a47b55435a2b87e3fbc223a6143564aa44f508f02c6378c9b82f4594903c8a65c5a01e96a40606	1655056843000000	1655661643000000	1718733643000000	1813341643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xf66577208ba573b90566803ef567dbc8ae79b73de3fad13321a1b01f3220a13e637f5d0e47aa9d0482670ca4e18b98f73bd52a600d6a6efcde035784b2c8ef25	1	0	\\x000000010000000000800003c95b8905a3a92bfe7ba59a670dc498452ce521598ef3351d2fb74b6c9439e82ad5ac4a651ff56b2ce2f6d59b47a9dd7e3ad0f8d0905a9507d0222ee4a123886eb0cd46ffaca2d7a152667d62b9983383780fc7d74a98513aa5b8ea19612fc65d0422684aa56a75f54877d0e5fb158dd3756cf4b1b9bd1903452f921f004727ef010001	\\xd3b46360671b23feb1a3a1b846a85d7c2df7db7841cdaede4ccca41aa57b27b2a4303a55d3284215ee09feb00f3334ea4341e590a79c224b6164719e9ddf4c05	1681050343000000	1681655143000000	1744727143000000	1839335143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xfaad964eda187b41696601ac1b5e8f768081f002bc41400497edaf9011001b29ec59d562d3dbba29ca6d4d2e6d1cf34799a0240037f037134b4aa21c462d292e	1	0	\\x000000010000000000800003c0668d3578b6c55b8a1e2dfa1b29e1f2f0bbd12f92cae23a1e4435841f3d85790d4cae27d0159c63be4f00ffb8558289d3bf77596ab790e48d22a613ae18a937f4cf326b850e25ad63a59016d48929ae589c8b0f02fa561d522634b2fb67467d7f7967c5f6335319277c8a4e11c42c83e764d611eaa938ade08f0b91543a313f010001	\\x17db6b39d1f0eaa56eb76bd0c2f79983f16550d41e44583d1d4852722ee6f6f160a31e98d6e9bad77e41158973cf2a98018831f2320fc858179aa020d33e330f	1682259343000000	1682864143000000	1745936143000000	1840544143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\xfc8593bca0eb6db757cfa9b46aae6701c1470d0945f26fc1e7a8e70229b296d4b17e52bc447cc9ba0b621a3d1c43559bd739ea1d2e9a79d361dbf029decb8d81	1	0	\\x000000010000000000800003e1bf6e302b8600f36642cb936eddf18c129d39c50f2ec9c1aa42b032e9a1d1311423dcdc40e0d88566c51214e8b0f67b722cd7f70ebf402a25533e70badb3e0892e133bc37f605ecb884660d8dcd6dd3082ee9fc4299a952935cc9665730637f501669f67a1af17bbb3265c049b6a330bd9942387ac7b057c7990c501446e771010001	\\x1fee8077ca1aa66b0a3957e47ae9f9f4e90fd38c9e38d5d2896f876fde5a4b15875fe7ad091f29742be9fea84b8ddd4f21cd5597f1adaefc94a082894790bd01	1674400843000000	1675005643000000	1738077643000000	1832685643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
213	\\x01368fddd17ae9c1b06cc047db288669f5482987d16dd2a679d32fd3a48d4e2fe4cdd13f099ca0f695e7e6be5c58f12d385ab6409ee913146b3b5c9c8e1e688e	1	0	\\x000000010000000000800003e2f88ab4c51edd780173a8012edf3b4d30fcc59826f3cf416c5d636b0d205c7e4cd6718b14e2e50a4d743db9c3b842d48e16439536d41927cd21f0bcd747702a25af1f8aa9ba63ad97a74f6a8de728aecae326159e1fbfa705a4bc45c67e18c718f046f5b299c9e740ffe9199b628d365493b917fe3c2b364a4382741c5c94bd010001	\\xe32af2cb2df7f546712f68e2721df21c7bef68d44add0f2b14aaf12238d929974414d6bf2f5fe86f4c3929e59fcd1338bacd1024fbbb18ef4ea202d1e103090a	1659288343000000	1659893143000000	1722965143000000	1817573143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
214	\\x02f2e86b2ef2057279d1a5ee08ff94ea5db3f1599bbdf53ff8c7205aa4e3bcc6b1425abf5cdbe18039a2133ffb6564a06eb70375d8e481432a6bbc3512500360	1	0	\\x000000010000000000800003b1dcaf0d205a1507aab680f374c8c090466e8d62d2f840d4ea461bdb81730ac6efbb3175d8140f37815d66e8f84e85339f51f2bd964378c469c364e9c4d4c4b1567be2a61a9c2fef8c23433d6f514a6ea0dab68ef12fb6f1ae76bd3371fd7f0901a48deb32c56a807e0286829368dd0ea60f3f838e6fa3cd1717741f777f5333010001	\\x128a727925054a4c13657616307b6e1d9b7c58949d9f460d33132df8d6809e817727e9d9ae089aee35f52a1463c895690975452ca28b2f85c1b81d5a309f2a0d	1676214343000000	1676819143000000	1739891143000000	1834499143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\x04b67d3b12687171f3b3201e1c6288ba7b93e414da171611a178f60f43da6cf2ec8abfd7279c51065cd92c40ec8b7c5d966bbd6a4e27a2b091cf168e759f0f17	1	0	\\x000000010000000000800003d543f6f012f1f761cfe9e364c3ff1dbd3f42b90a672862d6ba44ef48fb8913a981ba6f0f261e87ce0aba097c65435e121aced08149f21874442a4d0bccf022a6123df401be2712efebdc8a930ff3a14ed2a310cb825c1a09fbd1026cda5498fc1d952f1cd0d6cd0d1e0e9f1903e8da77f70a450f6aaa15b65f5518733206ba81010001	\\xfd899666aa78d7eb0b5116e8cc89eb7a7645e38f8d73f7cf0b1d44f14a783dff20f59cd6381de5f2dacee16d69dad7d4612b62df90444e3cbcc25361a976de06	1655056843000000	1655661643000000	1718733643000000	1813341643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
216	\\x06f6d92c0dd8c7302748462a2eab8dab8cff8505be989f447b709c6325ce62c5191fcb93a7dd14d79453c4374597ae52328021f4a535ba3a088874c535441047	1	0	\\x000000010000000000800003c97115c94a543cbb85dab4f1f29404f70abeb766c0735e802971581bdcf679b0d26b2c37cc0a075d38891d0a793d3a215ad7fe897804ab75955abf06a416b3daaf5022f86d5d9bb1cd3fb3ecbe704e097578fdfbc645575b74dfb3ff60f00eb1cb505fe627ef149841cd358b392110b9aa6fd099530780b606d5e119ab8041a7010001	\\x18b94f6e77cb8424dc5de7ac46cf9ea55de60e2228ab18552e7827e5de57b8d0596d90141f5a2af9c58e5c4e16295dda9cbd41f6bec77b6dbf47998cb57c3d01	1675609843000000	1676214643000000	1739286643000000	1833894643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x084acff6b6168b10d7a47e32367f5a77aa51d94c279042332cec1e3bb7257e9ac651382993da0739a6c4216285baa4121883334304383d4b2f5efbc043e3ea29	1	0	\\x000000010000000000800003b9930cda0313cb99f50837d8285e945e6ff496f5fdc547f4310308a7532a6de59fdec473b057d0548c57cb9bb7f8bcb417c013c08929ab2e996f3a2ddfa4be15d865651e131369bcc6242f1e6c58c1d34243c62496b59ab4b1b7f6558d79d6f945ec731632ea93410de6f121b35ab384864bd47563c7992e5672ed8a10bef15f010001	\\x9f0a7d7fde888e2351dbfe5688546b0f9ca040974061ec660a2af12c8c6ab2d6ef02f59d0901bc1e828d6eb8c68d1baf60853f3a2d6ad557fbe787bf30e3a60b	1673191843000000	1673796643000000	1736868643000000	1831476643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
218	\\x08061749c1757575b448966ff2b8412c0551a1fe8099d088b977233854565e2c27a251b1c85a0d2e0b0dda5bdeb5872fcc9d34bc7046d84086672e325da1504d	1	0	\\x000000010000000000800003eeac60ba5c6edd5c4ec71ade634f04bccbad2a5f372d8890570adc965ad1264cf71ce21ad9395146336c96329c4881f7b0a54b6d9aa3f6451a68f3e5d2211e48729a4976dab26e3ee0b1aa1c51694a2b7eeafae5db5eb1d668a1e3b49eb769b6328de79e8f0ef564af9039993602a3a271cab967d02c32b34e56671e890fdb95010001	\\xc129f0e49144869c74bae288257e3cdeab72225b82f3757e4c7341ba8ba5451b91b9b97f6c215abd8e9233819868f0d2bd21ede7a59d8d3a953c147f82c44d0a	1678027843000000	1678632643000000	1741704643000000	1836312643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
219	\\x09fe382da04e5529a76581cab97987d57848be7c9a1855660f6ed5c05c148c25f450ac90327ef75f382444dbdfada00dc0b13a9d49a19ecd177ec3b6234b25b0	1	0	\\x000000010000000000800003b14722838a808061d8e69c70f1ec648919dbe764c668a4e20071c60f888bd134c806b093b24e4e8582ed80b27188d1a08cbca0a1151d770a35bd35707d2b8d412ed9ad1b2bda6acd36e6d57fda836c43d99dcc31944190907e744f0b79ed49d05435ab20d84fafbd09fe74f89fe664981b26b300898b68d103b2dbce0857e3cf010001	\\xe2353458e2fa158ecf7e85ef7fd7b364fafe229deb86d95e8539819cd67a746886c7949a356d0094ac2c8ad86a156828c572dce5335aac1dafae72631bf4d805	1677423343000000	1678028143000000	1741100143000000	1835708143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x09a226029fbc199cfd0661295e5b71b3cced01d439800270d7c08426f182b20fe206bd8ee14250e4ed54fd3e41424daee4e6cf665b172c57e7c3abd1b968d7e6	1	0	\\x000000010000000000800003a170192953c6eb30192bc9e9670c4f2d9267d0a7b2a839d9c22e098c315fcda7caece78ed8f879f81730cacda6e2cee8e6a48a8844e95a5feb68984a69a51515b028fa87edaf1bf4749591adedaf971cdd4019c7d98f7d1f2c1b5458313ff23855c1a3f8714e73ed185e1fcc0da58b6ebb5712913c011f29b5983e2083cf1829010001	\\x240ca443c4c3012e809e9e18ff6d1f48d36465af9186862812346dae7531b36c7cf14545a56c4a9a470de60ba046761b5811a50996f6f4da7f0527bff2f7840f	1679841343000000	1680446143000000	1743518143000000	1838126143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x0b260a54e97186646ee8830e9fb2a09e45320b9d5d7c172e6de1193718dbfaf33391d39710076dc611457296b7319e8fab7cf5fa8d1c30e3f6f2558ce18f5cb1	1	0	\\x000000010000000000800003b77e2f4d3b9a7085f4abe88b531d92ae3ff06d75801561190c617d312b3ca485a947221e11ec3ae126469891766ec6a7f6c6558d93515e66757fc542252af35bdea6f52a80d291088619d78bd820843a072ac4a8020cb84173e27f4bb7709596d187c5c93eb97c4ba6811e3ece0e3b799304fe0668f40b314aa8386c149419b1010001	\\x77886e4d93f8cbcca34526a4d41c3f82ac10f63bc2ec7304beeb7cb45e51069ead1e12114a15c78c989d6acaf288c388f864efddee95c23651bdc3f1bdf53b02	1656870343000000	1657475143000000	1720547143000000	1815155143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
222	\\x0e46ada97b2e9104579bb5af23735202d2f5bb21598b8ac0e4ab51833d4afc294476a2911af1c52b2b22af3322fefa3ca82210cfdec752b166ebd12b218aee49	1	0	\\x000000010000000000800003c408fa226cbd4cd22ac92ae6c2023c9d1729170a17a69b6c7a050d89c849c6aed697ae214ec16bf4d62677501ff2048b4343177a17f82c8737c96ab8bd38b487ce2f6d55c46d591017774bc9506ae920d1732a1fde7410029e959abf85bca42e05b04c577462320262a1a6086db50ee197230a23ce98303d70fa4071c62ec087010001	\\x16bd52290623f50e16d941aece752423dbcb7710900ac5b32b3c022aed371015cd32c0fa6bcd35d729cb1e795eb58e9ea3e9523698396f004216d98beee3120c	1651429843000000	1652034643000000	1715106643000000	1809714643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x0f26f94e39e8d6424a921c70fc4ed8cc629be586b20f212105bd413ae6f4b811bae2a04fe1b9800dece1379999bf59f9384f697d81e5394923588b3f35634dea	1	0	\\x0000000100000000008000039bd61a5ce4732f5cd6ca1857d302ab09b1b97d3a3a3777b6cb3a236118627210d2a18df27a777d5cc071b11c5a293eccc084f62101e68eae8d60665f35eb07942f2591a64c4f2ade239d07c199cd3912ac04c1334e3626ee0c7bff8b631fd891a955f9ba123c6ff9029da73f71fe21669aebeea1bbf0047f5901c1bf9b7e2849010001	\\x7ef65f490c3ce870dc5a839fcb254f15d396fff7508ca7d26bec257829e482ac5f12e86dfca89be0659a94c6b3a11dcb627e3afddc3a7218592579b009fa3704	1664124343000000	1664729143000000	1727801143000000	1822409143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x0fc651a83ad04a2e1508c2785f3f73d3ab40e576cf7505a8a0222deee5d1908a30ede53eec70728b3959c433d6d1bcf483e1c527a5b2712ddb78465d3c49e517	1	0	\\x000000010000000000800003d975023177dda2a8f10f43df861baa74bb2e4cedfac6c4342d522d30227c9e8abb90b4f7bfdd977e01555993c266456c85ff91f4d40bfe57d32c4f7844b21a7007a805010bda5a28afbe010a0b52f9de055d5afdc269c44c7d81caafa887ef6b0d0407d210cf52c961539040cb2bf624656d7ea0a2d8a63a6f205e7a1a116997010001	\\xec0a53b0286783cc112be4f0f248193c73e8415be4e28c69a8ba92ea4621430f161213f1a1361aace51faf804c7f64697cdd1a4f200f650af6f2fa71498f3108	1658079343000000	1658684143000000	1721756143000000	1816364143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x1ba252c134e47a256969ada36ae623110972c555b626f3b8ba1d50be9e0636708d8e1bdcb7238efb2a35a3ec8c4fd4ffa450970fdc827c1ae6cb283064ffa425	1	0	\\x000000010000000000800003bc0c5b0df467e506f61473621fc0429d84c56146a05cc8b9e00a2a39466616750e0d8cbd5c68ce8b534cb3e7a21257285055d82cd889ed7952c4c31a682f1fb5280ec0e4dc416b9725d38d571eb32dacaf5d5ca2b350bad6f55b544493e487748fbd4cc1fd60a38d95c54b1a040ef2afbbc04171e7a203a4eb161ad26bc3e07b010001	\\xf3bdfe653d0dfa31fca068b8d32143a657a86be6b64d114d748669440acdd6a0b7bd12e4854525759a7db6c41aba5b62ea2973e8abe2fb5948897fb4900cb504	1682259343000000	1682864143000000	1745936143000000	1840544143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\x1d8e85c0c5ba59d0c9206d25ff423c0e461b0a0cc1951490e3480f244768e276fd3f54dd0812d31f7d73c15d154b785f7d2f173975402971620fef5b7acaa67d	1	0	\\x000000010000000000800003f239c9f624c85d01e68f76e8b6cd65c9455fb4c80481089583fcc8a4c3dc40943ac97494b219aad538ed5e653f879db67e7df1b92755bbdb3617dcba53e7a8e0b69b032b855c3cbdd4623dbe1059cd6e90417841353b5a7351ef8a4168884bbe3d7ef1890734df565336053ed209fa67cf18e3c6db1b16ee1a504decd34e54ed010001	\\x2daf743837c9ffbe85efbf364ea6c4ec75b79b6dd3ae7f484a6d20b482ff053f97a9a8d9e9211ca8f540c5788e71d6c9644928b4ce49a8ce104f144c2abdb803	1675609843000000	1676214643000000	1739286643000000	1833894643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
227	\\x1d1204c580a2f454ad2654a4a7c471dc4e1f994241049ad0e4c308925171fd580bce6dde2268beb2eac85ea92ca56fb6bd5d2869a6ef873db5f624d2585f8c27	1	0	\\x000000010000000000800003d3c33e1c00a93e90a7dec3182ff53803951c0e3c06a457e41b94e4d44960b51b796b2c21168a028711f1bd320038d352063066258d7112a08ab1a5416c0acea677a3ec4a01155efee9f4c1c3db8290f0b6a9c8f4dc7246084c885e7fe64d72d137a03275a7d6c6254569b12f50e9345c8a45978342887ebbce82629ae57f59e7010001	\\x35b79b4dbcdd4f8f5a4e07dc24895794c2b48f66ba819319fb706a21a93b283d9cd9d9870e6088082381203fbd9e3a2d2601418325addbc2527643f209dd020b	1662915343000000	1663520143000000	1726592143000000	1821200143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x1e26d8183cce132cfe48e9a06c3dd6c9aba89a5f9c9d47dfcaa58f9ee123e0438f3295c8e2c9ca4cf5a415281edb66b24f98a7afea27838a78201dc657247d0f	1	0	\\x0000000100000000008000039fe9d8d2fa63fa6086c8b1f75ad2bb97a19ea87ffb518adafe5c2decdc599bbc3f8acb47346699bc91f611c33c53c8b43e95ffc1641655919ad1d04f27a21a20507fdbaa0dd6b62276b83bf925d91dfb3fed20ba790ad813dfcbcb365bca476b90a460cea959026f51293e5c92023e177f90ed7cf9ed9c18202a956c03a57f4b010001	\\x3f773d8aa9a540af44c30320c0d89891b00f9cb2df36710f76467705c778d814aef39507964ba19e4b04af429109f1c83fe7bb77286335334fe6047a6fbab607	1674400843000000	1675005643000000	1738077643000000	1832685643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x23624f4ffdb5bbdb25852eb6d4136da52df846329a13dd143cacf21828acc3496b8f7ce3f51ae56504785af698ca4c95e0e823490b9a3d878cee6d49885dcf47	1	0	\\x000000010000000000800003bff647130462fd34101906acbed0da403ded7c1e01d1c9236c8902d8193c49e2dc3d6903edf733eba4791813f5e72eb4bb1937d9d7bc424ea5740ab7a10fa6b9318daa3f9d480fb70cdc009040d8be265285c905f453f023c042e6f5f7b3f7587d0e1c918e10003e4aba0495eb0010c544aef51ec81333163bf2592cac25a6ed010001	\\x9df36b06cd424998d38b746042aa037c478992677f74d1188a55f288bfc46726178ffcd1b27aca2882dd94722faa1ec3d2899ebe393176c234dab3eaf3c4b904	1673796343000000	1674401143000000	1737473143000000	1832081143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
230	\\x27f2c41e7829a87f07e2a3d07bd2a5eec96b61191831adc9ea48169f99def5ce30da1b7ca48dee11eece861287e1df4696ec9e8db00f4773e5baf395ac1cc6ec	1	0	\\x000000010000000000800003d17e6fe7e648140f0e88e95c496115a3fafe5df58f731073f53476b7c50d80c26db3d17a31550b184d854f6c87ae27fc2c00bc783b140debc5e79815d2a79e0bc385b280b1c10dc4cba2be8005f463d5ac033228d158f352cf259501858756a17f235fbbbf1839bbd47e456871df7db8434e640d58665d80a21edcc377b0d1db010001	\\xe04c350f9e34e77b7b33de9547c27fe82eb0339ee28abc93d3df3bd0132876e6a4d295a336afff4b213e41ba139369cc1d8f066fe721a6527e263dcc0c484101	1667146843000000	1667751643000000	1730823643000000	1825431643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x2bea43b04327effdb3f3cb387f6373adde001b966b91e201e86d4c14c0d162c30df0df1220f9cd575cb57505ffc6f4b7fbf4b005990ec95f77f465bc0bfb4e93	1	0	\\x000000010000000000800003de424c27803dfe60137253407cdeb5a9933248fc7e1df93722235d3a2d99d8cc812dbf85dde155cb0afa51e5126e688143f58422321624e7a7d13e45809628a014eb8ae0c30b5549c9f0dc22431c947c386e7315ed539ef7a235f8f97d433bf5bd7181e7a565ffc55003ff7bcb7d1e1aa4f63c85790b7434b4005e942cbfb9db010001	\\xcc49c290c76ce6b22809c7d38c5d3eff1485d2b846b2c61fbebcec19393db98e8363b5dee289f3260f57b33e6ca796828d3525703a28d9b4ad906fd48c454200	1678027843000000	1678632643000000	1741704643000000	1836312643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x2f7637d6286c4ff7da7b459fed7cd4153d503b63bf7e13d1b9f11b53a82e97fe690f19ccfb0b38ff2356d621b43bb2186b183c5e21960b0f557e661000f64e25	1	0	\\x000000010000000000800003dc418e3349d48a35f5fb0ba661261ba622ddfc2da87fd10bb8447119c7ee2e0d62b47804aec2eb2f99798cb83bdc002a1df170c975eb56b69647f14369461133d776096bcd4806f3c459d0a9e7123d680970f5b857e3a3915b0f298e54f404a23380aec4a2f1f32b602446c2c32b6ca6e581e4e7ec8e43e5cf6cb50a8d3192c1010001	\\x9dfeceaf0f37a60086a34367ab43b0f1a3eb723d697dbb1f47e45e3f785ecb0f23e980992483a83ef51e4694ef32bcf40c055903c4be5fc5da7092bed56cca0e	1660497343000000	1661102143000000	1724174143000000	1818782143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
233	\\x31a261dd830fd77f9138aa1e44301861c6cf6ac96b22a2c73a3cae7cf7cb29ac61206e2fda2391bb373d91063b27bd340676cc89b67ca2bcb4b3b384543aa32c	1	0	\\x000000010000000000800003a65104fe88706267ece7a9cb1f1d9275fcf4e92398228fa399a11b695902aa62142a86adeb4fbf7d26b9c9711c6506241e2a58dc6e2bb24664a22419cb734914638384bfac34cbfb9f16c427d68bae86c2529440c0197ff802f4f55ec9e5a7618076d6343a277420cceba87d386f312e201e78adefca18aedab57112b3be77eb010001	\\xf197394acb2203206216acf03e7ae2fd1a7ef11bb8666334fdb8642e32993f8628517286abcef1f748ea71d873ea295b4495dbc3ba8f367febc82443a7af6302	1672587343000000	1673192143000000	1736264143000000	1830872143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x38a2f508d74b6a58f268aa1a164fe290916ca25adeb0aac08a69a8d2855734e41e9ae0f61a6c7a7ca760d31ce20e9a0f86da05148caf4cef48a9d026a9a2f554	1	0	\\x000000010000000000800003cc240714bfa7e00c23cce164e88fd308dbb9499d0e3f256164f05f0554919424aee71c9fcc99e7ff5dfac1b1bac60f3c0ba7063359d90f1c81bfc17808204cb3c49bfafbf61bdf3f560c9c504b08abfd2fffa8e0e695845b43cbdf4948ea20a181c586fb75951888a5937dc83f5e3d35dc29ac47ba7e617c1010548215cb6d4f010001	\\x16149fa3b254746f44e8f544b1089e71878fab8f0437e4ff844828b814255d3673270989ebc82152dbd69c1f15f2e073e2a51c21b8fc65645f6d1775a8b22c0d	1675005343000000	1675610143000000	1738682143000000	1833290143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x39cacbb9237a56e50de1393daef8e912cd71a4c709023a27c6b648bffcef38e0e00af3baed1880aef3bcb89932ff6e05a5377a19bd04465810cdaebcc4a64a74	1	0	\\x000000010000000000800003b6b97f4a3b00a8320205acecdffd95ebd6e45c9c5304ab9a776dc5e60941738094fa30bfd504e4a5379f3071f6db9c5e180d7c32445b9e1203391274ff40455b18e2052ffc13cb6075c18ad93928524062df68621df03836aa4cffda6de80bcf15b2d4726b6bb2f8eb7b324c38c14338f35e99af5d3c57d715b2b4d187d12ec7010001	\\x2a6323005cf460520db8103b87ec5cec939599d09a4eff4d4985df411bf8496af186db69b3c1ef09a08ac288364400b2555bd98c954f150896e52f6b69346e09	1670773843000000	1671378643000000	1734450643000000	1829058643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x3b5e08520d62576b57fb8ab82eeb74d5e869c108d8035e27b9cf934bd7f275b1e32ca522fb080b9e8bb109b4b5459fa60cc4d55823d1246b5c3fa9b984137162	1	0	\\x000000010000000000800003c602a6ba1710837f2693acaca95d22d8c7fa7a2613f2582ba70db9ac0320dbb7acd343a330e96db6fa6bcc1224ac47c9d336c3d987fada9e13f5e94e73f7e365bffa60d903c19cf53c06825546fe8e26b4b9f301d77688d830fd36cf64e9d53e0bf2c9b3a74a341a00826eb886f589fd9cdd7a98876a01fa89ce6af884ebb833010001	\\x44f3398eb796f5f7bc5122ce87890255015f64e67b109df3a70b8e75e321ebe4424b962eeb3d7678c8a9dd6076681ddd92242894260a2f9085e7fc6453885806	1659288343000000	1659893143000000	1722965143000000	1817573143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
237	\\x40b2f49f558c76fe66d37c1692a9216ba4731ba449310fb4738f26a735e0ab5d5ae68dd8d35a35cdda8a84c569c273baa1b05a7759900625c4b11861a6dfe42e	1	0	\\x000000010000000000800003dd29dc93efa1f6f52ce9d3f0b3cb3c7e4e37a3af5bd0ec5cb55eb4fa5aee3797742086ebb7c7fddce2e367274b3c03a2f012320252f914d318911b0b4e66bdaa3186764d426dc93a82ebe4b2f64c631bce3c6d1154acf94e695e26e45467c9bc73aa13f00435fc58a88797e11ccf1adacaf28d568fc02b3d3de88e78483f544b010001	\\xb6fb385b46f70ac7a98e9abdce61fb87dc2cf2b64583ac416e2fe3771584906c0c45634c202f2518fd75ac12507a47a71e27a28506c39fda402652a1ed77aa0b	1678632343000000	1679237143000000	1742309143000000	1836917143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
238	\\x42aa8c2f50801226c887d9a1eb157b51389eafe3e0e56ab54d903a3644f00e8662c6a1eb5d2f1e0b673f764b8c9f9e67e54da1cb9bb01ae40c314d9988d49633	1	0	\\x000000010000000000800003b6a5f397897d0597b2ad0fffe56531472095cb5f0cbe4359378dbcca8489fbf531e17ab842ff16057c7763435c8e5016681255452c0d38cbc463c615832d2b749ad400e16c5ae8f78955f67a3c8299c764714a9d33ebef3ac977aad3a382ccc84e055bd590c091525397561ca06fdc10015824e66a6ecfb2bc9534b33d715a83010001	\\x77f42f22cde124a1c52ec2f958b5dff1db0fb952572931f098fcc994faabf9a33d030458a12f9e6ad20817f30535be23e32eff09180e5698cc28e8affe4d1a05	1676818843000000	1677423643000000	1740495643000000	1835103643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
239	\\x474a6325e7ce885067343bc284d656946fb6a07952cdbabc939e4bb469af5d91307f95601136a25916539ae91221cc89c08fb44cc2597f004aba1ed12cad97ad	1	0	\\x000000010000000000800003ccb20e3954caab1892ac2addcaced788de0c745d810a6a4661fdb31700199f6ee5460778b4b15b93cfaa64436a6dd4d40b7f559369ea0984d9c0913f3bf69ae40376aecea2e2ec7b4c04323c9c5814614ad108284d05a52336b115a90e8c637590e3426251c99c6225e382c00f5ca2b137dc68ada982b36bccea8c8009dacd4b010001	\\xca3d5fc7ae99e19d2acbd32d2e95c8ea75d3663774895cd717d73002533a09c307ade5fc3274ee6f65c52161595ea0c25c54fa583f7697a062ca4d409c305002	1663519843000000	1664124643000000	1727196643000000	1821804643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x49eaeb1f6e1607136ffb5610fcfe305829f3e3240c429272db440fbfbb54d403ba96af89635c46b1a32e273b28f08b6c1f792bd4e4ae0266c86cd623519247a6	1	0	\\x000000010000000000800003e375862c6a5948c643d729dc0e10ca057be539f369d0b18a12e97a1addd1ca00808eb7d0b97c31898de8204d5c350caa17a8f25db4896e2eb30a1ff74993b589a507d9fcda05ff20782c0d9a69f888a71b6f1e78904f537bf8bedff59fb0b5b52242b963c45a011add84e2e14e872a225fc6b869db71c13013f196a7d514f99d010001	\\xda3fa7ede45b25c6084206032ba5b01e13385e66a9bc27a7b18ee9f47118a54cb2d357fe38880989fd16c930e887132dcd040b74469ba502b0d66bcb0135b602	1660497343000000	1661102143000000	1724174143000000	1818782143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x4bfaa7fc1d18de6323efd46ff2ffbbf8dd34b4ce6ebaf65874786e7c8f349b0b3303d8e1ba73d12b02d37486c189f62d9bc3ffe297f78f58c3d0d7839f682a2d	1	0	\\x000000010000000000800003c97910a54a27a0722a4c0e2779f41f13501101f02b9c62eee81ef2e80de4ce6c5a508886359b51c07eef122419fb3caf4b445b8431ffef4e7f1aa4908e036536580bff15cea0619c4de8228580788aab50a88477f8c0bb6bed9c57d48282c66b110218b1065f3f2fbe2f3549d202d3b9cf2c54e287673f19ca75d26fc5a7b457010001	\\x63bdf51a3b9d20233c881b330180b641a5614e4b372f88d60042bb4bcb62bb2e0d866e79f488536970634ea63517ab3d1d6f75a817428eed95fbb4f905487308	1661706343000000	1662311143000000	1725383143000000	1819991143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x506a5434b381f8fe3d4de1f8bd30b250818da4226aa967d5071f180b080ea62c7626106279b6a42bbbde1ff0e683ff68bfe9cbdce64700d8c827b24e8738db0c	1	0	\\x000000010000000000800003f15eb1efdcd43f3e297de2b34d1188e28f4fa6c63907f1316567d1339d36788fda1fe80b3dfa3e3c19d2a231809f9cab2ca57bcfac2c43757d343fa9e1521038d7534eccb4e0804e9c2c4cca8045ff0a6d6de3047f9f1e7da788143f56d1b6f9cf20c10467fd69e40cecd7eb687b4ad8a64603a8b69a4728a6efb7351f2758bb010001	\\x4b8ace1f1113ba0d4d4a2670ae55886e24b07c3b742a210670834d812c08e6aaa4e0c5dc6da6eb13a3f700fd8ab9122d172b57d1863ab41498bf9393f7abfb05	1680445843000000	1681050643000000	1744122643000000	1838730643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x51ca3e9c9af8a822d711c1636dc0f3c507de342ff1055037c50f1b206958817aacf59424993df6e7b483925e0307f6f344e9b0ed77c93e5b6a13b391747a3d9b	1	0	\\x000000010000000000800003bd6956247341e7a4e540c63db7e78d506fc41143fa3080ca71dd558c96ee90f0c256cb0688c6d2f1be665c884e0a30dbd77b470ef9d56e0b7567d53af7a201a287fa7ad2a4346117a12639e58762457fe15be5ac868969b663820ad75830a6c958ca1d6690fa447f82d830559719a366fdff612e258320e3a8d77bb320e1381b010001	\\x6b3793100cc0de9a3274a599ef82d11a65bdaa4847a34583880e347904131fc62523488b20c0f6b4e3aca278c87a0220fa08a1a5f0cceefafd8fd5d57ae4d805	1680445843000000	1681050643000000	1744122643000000	1838730643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x52be8e3748fe562c194219874a106e370677f1dbce20573e3678c9cebdd6fff117a328be028d3f99337a67b31babcdef2eba0104bca89132c7500a65486fe4cf	1	0	\\x000000010000000000800003c312bcbb0fc98d5395c0a39820cb4974c88f0676db5cedce04fd892a70fbbb4b5b347ea77eb45e713070564a23f3f7afbbd8d03538ed49c7a176a67324babfbda7db0ee262fcf42833b5e6089271b3d38d800af947a57d083d4a6f0aed00aed8770cd9a08f5958931ce8b971e82e10deff48fec4675e0411f24bc0214464d885010001	\\xc437c0e07905d4132d2083c29ed2005f52add671142ff7f08995cbb0c7d3b44d034452035b13243de41fa5f328e954bc15adc0b80c0848bb55ecb405fc8af202	1652638843000000	1653243643000000	1716315643000000	1810923643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x53c2e072131470e9cca890942dab8f23a4c56e6c2a737cd024b2cee12e95b8788915492fed103a9d302ead41299f72bd3559f7a3d7eea6a303e585529b47e8ee	1	0	\\x000000010000000000800003effd416bc0ea5dfd8be44db5228565f07c57852c08114d91a60b1dd28d0ed43a1aeb441dd7ac7ee129005c2e3ab41eb6e964f7d9fa8550703b578dd73ba82ee66f867407ded2f5761e0d91dc779b1fb8ce70484168484ca417f84b9f577f2a1d43ef498201f04d2fafedfc668072cfb7235a794e10e7137be41a190a86704ced010001	\\x22820a3336884d4bd6bdc2829ae3a67e74783aaa84df581f6bfeb5b2f8b2f1314643ca7a96b83b5fb668c46a25bbef7fd05052aff491d23a77e161ffc11ed307	1668960343000000	1669565143000000	1732637143000000	1827245143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
246	\\x547ad797cfd5a96bcdafb97956d0ad6908abb8f0b56e46a28f50ef9d7bc2c524dd438ae92616709ac6b39a8f02249f0bbdc249adf936fdafe38a8319ff453775	1	0	\\x000000010000000000800003d0afaffed265c7c59db36d1a10b905064a0ab083a9e4282ed883aff470074daac5cae3236ea4d41c0a252a9b9572cade318a8328c7271ef56108d1855a432aa2a73d320139b2e0c19dd8d1c939a38598c2d41792db807f1b9ad07580844c4f40a275cb3a941630d3ddfaa91903a9b43fe6d349aa4b66cbad25a964ec57c04e37010001	\\xb5bed0dc5ec75616ab0dcfe162ae82b75f4a75f5c157ac49cc8b095fc86954783dfc092a8569993a6e51dee9b23e90a702eb755fb81e3b88a37c5e480fbba907	1670169343000000	1670774143000000	1733846143000000	1828454143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x58aecc447a229ebac2756321f1cd4ab264a08c546d675801458933ff95f2a12ec1fd0df123b108f74a41cca661ad2b9ca59e15f4de90bca2629bd1c024340b63	1	0	\\x000000010000000000800003fcf59f43015c2aab7f7ec8d2fbf08abbc6c34a076502e6ff43593c0c690c0ca5ebb8fcbf59c25bf02f669dcbf01302499693408412056b9a959a5d5e58f5d0c587e93fe324adad76d2b381a68471f7a1f998bda35d47d35406a891ff8fde0f42b88fedb9e95066cebff06cd23d3eaa7a1931cc8536ae75883735f94b874b41ab010001	\\x9f4b34f632200866933d8204d30ca5821d44ee8b3f1ee1ba19ef7bf2e44e2c0ffbfce0d46b91f2a816a65acfe55ae7ecabe0d43c6233a3a3605404a520794802	1679236843000000	1679841643000000	1742913643000000	1837521643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x5b66c31b2cc7dba30955e0cb9effcd0de5f4188706b314ae1b27e2e236327632b5886c9ce89d6c18733bcffd648ea90212261239635fb90b9aa4d0a4536e4a8f	1	0	\\x000000010000000000800003cf2f1d73b5108fab16821fa0487de4bcf555de8d5933e934bd202c8fdcf64157724ae5fbd2055c91c728ad20a151bdb59b11a5f37472511d359ca9b99f80129dcb0410540a19103771c3ea45ebb9ed424a2b61b31abd25c561c7f08ef1a4141c4d4421d19acf97f3011cbe52b74a07c8d8829f10284890c980aeae5095d2a8db010001	\\xc27df4cfd6f5cde41a66fba7792c905d7e215b6d49616109f9aa69f56c24b792c654eca1cad3e7570ddc7348ce7a0bc74e09f124bd82d41797e8d71a6c081c07	1665937843000000	1666542643000000	1729614643000000	1824222643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x5e1eb3be18cb8f80459df9c7b15963719e4080770b404af53fb73fa59f03a1ae2fe1609c26c479525d1f5771156d282fb36b000c3eb33857ca199e5c01ee3fd7	1	0	\\x000000010000000000800003d29c1923a4cb359547ddb4a08602c135d3e279dc65d30749c562cd7085d4287b0c336decc2370f43cbfff0e5e9c28f4dd68bc310c2aeec04b9bb09d2e0adf48abf5a482b97cf1a6a3dba29443a871cb4fe64e717ea536b3d70eb530ee3477c41ed0131752ad82975d41484644069881f81a6e5cb8fd713d4d015c6adaecebdc5010001	\\xd94489739bcb3082f5f26b7b6407f23d00c15087f3922d805dfdc88ecee3dd4e9220e4fe6a4ac7e4909b8719b0edc9cf9bd3bb6c3ef200aa480f0465eda82009	1673191843000000	1673796643000000	1736868643000000	1831476643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x5ebe47b355e871998e37d2ace253beb1b11428eec991c932cfce7830483d41016b404e91fda3e5d46cd4d7d4d31e34fa3bf499de5f7d68d70224b413797181ff	1	0	\\x000000010000000000800003d86725e3b5be3d1461862b48f996631119439885d8654af351eac4f3fcf8507c23f90a7d7d8b69b54a55b0b6e852139792752055e2c624e65005f856d8b20d1c8a8cfa18067e8a3521dd783b9b67a0ad22d5d6b7e7039c34a486d6fa0275583f7af2237e6f87e1bf5a3bdbfdc92aaa2b0bd131d4f106eae5c97733608611a9e5010001	\\x8d8d772d87d0e1fd82f8b93420fa9a19f4d6bb0c9d1898ff7bb4e2d5c3f5c89c2e611a0d03eb02e1fd64adea3cca5c7e94573b22f294a532dd66cb38fc5e870d	1669564843000000	1670169643000000	1733241643000000	1827849643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x5e76f699346a0fbb5a20cbae0d28f0369fa5f5de939b72297e57cc930529b3d36420e9336cd45c6f124bf1a885f2bff039eee7964b25a0e68ad7cddc64c8a1fe	1	0	\\x0000000100000000008000039d870259c74a833d87a0434978c2021e4fde0a37b02784fada848628c204e80e9351ac3f8e90a98cd18c9e7df7a1d3ebffc77c36564d469a31f26f2367284705222081cabc8c080534e3b6d6ae12c9019bbc9a2c914e9c8492f3af8812a340e5b7f7904e597891aa23b7254afc2f2fcc128b909dcdadb7b00540d2e8577646bf010001	\\xb9a99c7f55b06048513579129ec06dc8ea230fc3329b80affc7418ee5f83ef1c10dad44b30f1052488b4627604f015c79fc67e2c8a939f3a2535ec414063d702	1668960343000000	1669565143000000	1732637143000000	1827245143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x5fe23c4b211b25a22771c3a50e1aff3ab17033bea0800ad59f4a1b79bbfe9b7661b5561ecb97e90f0c6b78f0aee8910c0256803970c4bab2306af9ec36c583f8	1	0	\\x000000010000000000800003dc69bee7852d878e0f373ee44716adc4bed1154af6cf5ed0d371b3fdd44c5b06065dce6130d8f3bde38bd0e7f61f39ee4d0636c35acca99f1dba4d2be3aac2ec3a99940f34443e66a4ab8e4cef55c87edc7f91ebddde3ba648c268fb653d4ddb577729c78f8f278bd6d3d6e174e114cef38f98e30f2ce2a4034b410cc7006e0b010001	\\xb83f580f5ba6250d9c22ef4f9f7ee71d7424651f03837b6876b7de4430ca8cabf1bf53f84a80f9d3102008414cc2953689492ce1270aee19e7aa50cc7219150e	1667146843000000	1667751643000000	1730823643000000	1825431643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x62c601918744b850f0b11a58a248f0abd8fba3df8204beab92a3af73b4fe6d1a4f26e53f4268296a2f37df10d1195729702cfac9a24bc1e0080023f1bff5fb87	1	0	\\x000000010000000000800003c8e34bb995f7f60a51edd95f3c015cc9182e54bbc55164bcdee9fa7a4e3833cf13f962c400e37dae3a56bdff8203577f465fe0aade22b33b1ade521b1996e806c0a7a86645055c87bc3b07e36353fad9d129dec81e6657028714fe9a2cab36a11985692172d633ebc52dcccebfccd072991ac54c5430ef1f82df7aab3e693633010001	\\x4b49ba2f421d1edfc0a66d1c5db27c69806338d967b902e5a2e30e714d68781bb10b3e690102e59a0cad1fbc4743a4a740261a1375f42fb7e40823487218120e	1659892843000000	1660497643000000	1723569643000000	1818177643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x63d2c4754d81dc054a1427819256a1bca2c36975c7e23e8ec61c75826ca8d82d48199d8e4c487e989d5735cffc8cbeb0206e4de14369e6c98cf6f38ff617c968	1	0	\\x000000010000000000800003c6e98983d1be7201409f536bf158d6c83dce5ea996ebed5109e2db038c02790660a8bc183d4a10045a1237102afe8889b64e08bec4e49ca38860e8d90746d61ab98a4b11c93c0c424ec709abc968a1ccca0729c04a6b3efa48e0a670b227c5615c4f2d9c90b777a9affccd529b0e52d1b51ef97329dd69ec5bc4dca4ab983acd010001	\\x6b5ea7d57e8fae28903ca8bee4387b81a4fdba538abe46684994432e1193d13e0ff536949ac897c687020c94aa1871ed60d138239ceaf23ac0b5b7f4cd99b207	1654452343000000	1655057143000000	1718129143000000	1812737143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
255	\\x644e656e62e02be3262280d232efe1ca84db5d57177c04366af1e5595fa223bb75d184ec444260a67946557f8b791c52f7669f7854b06274bbff8a3b599b4771	1	0	\\x000000010000000000800003d87c78e78eb5f1ccc919e760d25184f5fa8d6f3fc6ef3f4914b05ff244f19ed56395a6753281f15b67b4574291bf64d28054257edc3a3485929f00e8ce0645f2f82b51939e5e07709e4a86cac9a1d9782301f823d586c52d3ac053c6ec53d4cdbf7f60263e59dd2b134ffb7987ca056e617861ae23b1065ad7f0af722d0c97bf010001	\\x1e0fcfc740caf0d37e5eedb3943717c069090bd1b8d06ce49a030b4cfae1a95a82d1545b666e6b43233f1e697fdd475fc000fb17a29afb2562238d013f3e1d06	1654452343000000	1655057143000000	1718129143000000	1812737143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x68baa5125882a6291662076972a786217aff9da39be7f7c534185f4f7015969bb62c118be383d7db02eb53add2228306e1b4ee0d420e9c9be7538433faf5fdca	1	0	\\x000000010000000000800003bd76f9118a78252ec62e51dc3af2e9e746c1f672aca57eaf1fa9eef8f5f32b59afe9041e833a83ee33668c9c243e2093fa24cf358853b681f43d8e1377e623652e3bfd60be2c7d861ea48cdb9b4236d104315387b09b27cccd3799185398e53e7903ef59f7c4ee5cbe990731b05a762abb0df5d06176737be056e3858b8f0a31010001	\\xe6da4484ffa15cd9377812ebf1e4367a8240208d16b117f5d41998ceab07173177f8368dc6371f5351aa7a1a9778cb01c238bdc0ec10c4ce473b69cd7ee74c06	1661706343000000	1662311143000000	1725383143000000	1819991143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x6fba391327bb34256c8b879d58705012445ed5235b67d9f90475e67c22344b3fff1dfbcc96a7ac43f88c320570e9837877b85082e186beb9ccd9b31e42a53776	1	0	\\x000000010000000000800003ab585b02ace1de61c9a261b80e795f9a7095115a6d101b5d0c14d7412c1adbff0c8e96498cbf88a7728c93784d6cda569a2eadd05c7bd0421cce7949a7d5d89acdaedfd5c6b397b05a995c2e7588e2cacb6fca2499f26fcdab9a3ac09fe3fdb110a7cf342f80b2f97bc81eb162a5003ebec9c5d96991b7073f20a88052441085010001	\\x69e08f24916ffa03400ebabc59a3f611cbb5b7e2f0e345ad2d67c55fc496317154bbff4a9715e5abb7328b64ae0d373daefaf24f274e9370895a2e0624ca1d06	1674400843000000	1675005643000000	1738077643000000	1832685643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x70fef8f51234ef4278b57631904a9289664fa66101ab0936c5612cf4adbfd72430bcf32e92618755987b269640c7ba5f7980e5aa4090feb89e49eb2fa971873f	1	0	\\x000000010000000000800003c5cc5f8e74b8b4da88b7b443a2d04cf36a623e9d0c558a2d683e94d3ae5551d818792e0b1967c13b8b049e2d3524fdbd2d533331996f3b3b15732ced63a4d2dde4cdbe8d4c782f778e68cf4ec32240e1dfcc32188a96dd79a040de98f6123c6118c93128fb3c543b91c8574db981efe918d26bdc0daa03f0a2c4a5dd856a01f5010001	\\x0efab73394ae49cdffa6e0a577a9c2535b25c1142c215d3d1ba8ad03faef9f266360eef46593980521ea4e886eb9a402c125ff319d6afb97fde82da447df9e09	1657474843000000	1658079643000000	1721151643000000	1815759643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
259	\\x70e61ed9b83a4f0421c07989d87c20a8edf04a71cc86ace7d10d06dbc07a5aba078e9160c111a57a6e79740dbe1aa5c1af1cd2031b2da4bf75be27c1a7a467d0	1	0	\\x000000010000000000800003d8ce1d4811e8ba45297f35363cab4b77c067ca2c8e6a545532ecc2021eae62193dad9c294ce2b9b207c42fdc8038c343d094a1dd06da6aae974fd31b2ce5e9dff28c441973f06772cc204da5c3a5fa8387fe1e8a0e96b9661cd059d51853d3ef75af688fcb0d50614e04ca2116a55922c457c3e75d1d7d8e3b4573fa38e65003010001	\\x3e1b4efd8cd658447b395157b8b1c2be38cfae6950514bf2a505210e6acb0314bb28a8f1a66ce3eaa33bccd8ed441d11fdb10559569d6ee89013f340c91e1905	1678632343000000	1679237143000000	1742309143000000	1836917143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
260	\\x71c6640c4aaf01547aff840073fba3227f586f1d71a3bc609d431a7dd1b802161cc82fce1484a843731357c4d32cb548747dfa54791c38054bc3a56621a8f34c	1	0	\\x000000010000000000800003c5e0578892b6acc6b11528d706b652f6a593bf8667f242312cb9a7030a4fb91acba7ab801658a35434c0a2b017df3eb2cfb8f910410fa9c1e9493ae7504029131461eacf1d8bc12a70951f5fbb9344e2f9f876becaa0b6082586968edd446034a7b1938ebeb0c48e2ab3fd83d6e02960e31af8da8f3fcab070d49e2456b577c5010001	\\x24a288307e4badd9943e18499703e7d93f57f2cd3e5c2c17c45fd0514e70ee34efa3dc463d914ecd90f90d8eed26e3a3df219c0c9d867b4428db0b9eabf3bc0b	1665333343000000	1665938143000000	1729010143000000	1823618143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x71928971c4fbfdcff9db3cc9d3e49195fb8b83b340c6df9770376de766283c16142924ccb3e6459e9848b1af44a757a2457f35f8c5f7f1b28627d44c94a6b182	1	0	\\x000000010000000000800003d3edab36681c2867bcacd9236e07e370c070627bd3cb63391439b45d5ff0c50391416fb10c1139a2fa83734f9708ae03a942609d15ceab2dbcdd7af12e53ef6a04eb6aafe131a6916ed9e6fb798a37a7c38209d84206d7d322d944cd7a7d82d40718d14c9750de4aa4a09d8fc5385f70eb5118819e45ce9ba773bacb641848c5010001	\\xd488306ce639072858370774eeb913801e0e75c7aaf1f999ed9a3f51299ff440714297a9e78dcd2a63451dacea8d46e1f3dc44863246d6a8f8047e07a6985c08	1681050343000000	1681655143000000	1744727143000000	1839335143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x7976aa748bcb45410548a39bdc208812107af5397eddd410cb618cff92185e16f5f406d0c4fe312f9887a1aaeb8dffa2dbce8208edb4fc9e5aaffc33e37fd365	1	0	\\x000000010000000000800003ec6b7a7053a7f4d9193ced62b99e4a0a595cb008a94d0acb2ab75fcccdce6dba0aedb03a23b6514a08c22f3d5781f1feb652b230825c8f9db1c13ec4a49a1c834a9a3c8d113520d0107d2c903b2d387fefca58d33b7c218cdda59e49beff6790d2c01f9db90470896cbb1f26e55c8a5324923669edc27a297cb144f56f17702b010001	\\x614e857c9a155596ce8cc4ade81b668d9aacfbc6cad172b48d93b83a842e2c23ceb801fc12822f61053f1f24aacd5e593cb9e801dc8a46c636dfb1edb05cd004	1675005343000000	1675610143000000	1738682143000000	1833290143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x797693f68222280966b46f7e304894d66c9f88bc650e5256f3b0ebe8a8aef793595c29a87c13973f3d43b10b3d1f3becad317589bee5d58ad9414d8c4ea9c781	1	0	\\x000000010000000000800003e5012816da0c644116fad1d6a5cc2f290f82a4898e379e9e79004d9b2526c707585955ac43f61723cf0c9bd28017f9beb5e28a30a60492cb0721778c36c18518ae1a00572145c2aa25299e0d70bbb271201104ac5079deae542f263626d221ec573c956cb82f521dc341b168bbc255b3a1d12a8de4c0031bc99e9aa25258fa13010001	\\x2a9b1f8197eada2efc9dd0b98273de7a7284036e821988d7d9483fcd2ce91457b6cdbff4f5b25f35f799a563dc4d7aa0d931d565531f1757925ff1271bf88d0c	1661101843000000	1661706643000000	1724778643000000	1819386643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x7fceca565b4806f04de73b8faf5b72f59229b72afbad6fa722a0102491783925011a50b696fce1c3d8310420e7d815e218b9735d6c7510b9c3e839f95f5d4086	1	0	\\x0000000100000000008000039bbbcf0739b1a404a003d66e06f3f40316d93a057fb045b82cc2765536973d57d9cd4c4b97e473b425360ceeb265d2a6b0199d6d7bebdce58fe2b686b87fe1704cbffdde3ed8b3d72e04839192b32f238235b3f322d23805471daf5df3a49922ea39bf72186395bde2f2ecd48d0618ee2503d72278877adbb91f6753930317e1010001	\\x99eac0c2c2e85b57f883cde142b989d39241480986c216a29539a67769b556c8dcf54b428975de02aff8d5dc7b2ec859cfb8e63f6bf88c19b057709ba5573208	1663519843000000	1664124643000000	1727196643000000	1821804643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
265	\\x80dedb2de2b88e82aedb05df02129f0e58a5ca089dd78a14c25b812052062fb56655353bcd0ce730bab106584d8cda45ab201117c3308bb3362a6ad4a5683ca4	1	0	\\x000000010000000000800003cc7a01dd0c7ea1f39dafc56064b8dd1d97ab71d586b2712fbd8995ae38b0c1e980b07441d0c78ad858549c9ca78407f2899236ad812476990dc6e73feaad771962c629712b5074217d5a8b9c2fad9c26321f971e43e07d38d332f76ce58e27f05b3d3e910ecb08d840f6822a89e3ade4213df46959f232aa96a8aaa4deef7111010001	\\x5886a5d6830cfc6508e1b3a588567d943a63159623d4a1e9b9e08790fdfb2e13571dc6da87bb23f3138314337af53a5c44e87392df5b852254a61191bb693305	1664728843000000	1665333643000000	1728405643000000	1823013643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
266	\\x804a991db40e4ab60d1637e538de21b36542b112a2665f1ef94692ad55db96452b9715da5f323a590786908eb0c232a4666e63cec78fa87ec6131f2586e9322b	1	0	\\x000000010000000000800003bfcc3f781314f8d06cbb1f22148a4540e5c8bf88707a127d2786c5b3813c17d03053c6269c0286c838bbfe7a49296750c58b8771238e455f7e21aeb285ffa90e3362d5929af7bd3baad83500ee2833c5a48656967ba8656412b5767bdefff5d5277d428d6e6500d281e2e500ff6c302fd8d030913435fcb6e6be8e0df05f5331010001	\\x033579de38c3670fcbe2744f3923647ad4ea5435f1cd9d7c6e59c5825bf8d95ec471ef824cf9ee7c59ea52a8c8cd08231c603d5640b09fc360cd0032a553140b	1657474843000000	1658079643000000	1721151643000000	1815759643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x813e73fc4b8ce67ea71abc39fec966e4476f0147bf9475996cd5409b0b65b266e739f4548aff7f3ab74699bf01d0875c9a8014faabf901ae950bac3934f80754	1	0	\\x000000010000000000800003aec393888f511a071a259270758a3b1eb0a96119d0c4ec0dcd1c9b1350d8d6453bb25c05b3bbf375aa56e70f4c057bc0dd7d43b5254d1b3a0defca67aa856a9a765e56ec1041a00844200f86e4d8045a72fde233f869b31a8373f2bcc6f8c1b37831f05cecc15108a815175853f85c226c84d6562fdf9621d05ffd4265a60adb010001	\\x32970c0ff1460b3b668b84250cad3016cdb87a0b9c97f1c792655dd53b0e6f9b9c7e60a976173cfe9f84717ce1ea3a831015f0d620d4e89da1a1d359b965af0f	1660497343000000	1661102143000000	1724174143000000	1818782143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
268	\\x858aeb235dec825041459af95059ebb337e8da974f1e70435d6c6572e086eaf430d4b412c9408f58e76b4b52200170e301910749cfccb88bee2d76b2bdcfa69b	1	0	\\x000000010000000000800003b89131d86b25434b1d9e5b0659fee3f848e00768c1ce145e848aea0ac9d5dfd062a2f99262c955e063e577825f2cef3b992cc5e67e96bedd629089f693788a2ac9281dee44bf44a20bfd79a75b00ed67b275c617170e6a087b3e9b051861b828c6929e75d44874695b59797d42666c29c238ab72026e4a607a8ba12bf24f27e3010001	\\xe52bbebb1795ddb110c062988203abe37b5d7fce6a952cf470196ead49d83b17c23d4e901e446eda938460876072e99797316604f2cdf471777e9682ecf77e0c	1667751343000000	1668356143000000	1731428143000000	1826036143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x85b6aa056d1f59a6e2000dd87cef481ebb9cad601e01a7f00ca78d429497d8d289942c3cf0dc26b4fcc84ca1dd7715a4b365b13bf3429c4b02634800c93105a3	1	0	\\x000000010000000000800003af94d74594f0a03b926befe8f5ec05dc0f86fbca840e4d421ebd7cc0c3eb79031d5efc34ed6215a126e557e0560e0e5280eec1984d154ecbf48525b0cae9f9eadb9800b0a969a42507f947e6447091d1b9de093e544aac35cc8f186d65bd9b5982c0b2f1036e2c6f0e94d0399181b7de247399fe87f9c2bd007f6b1b3d6b0275010001	\\x7d69c07fea47ecb470d05cb7e73933aa270858d37cf7554128236fbd90348b878cec9787e5aa6af739706c8e4739bd0b15fb34dc6b12e3667c6ecafc0a356607	1664124343000000	1664729143000000	1727801143000000	1822409143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\x86320328c2ffa801c95c51b4474ea53b5c5f79067518b72d02d30c0af7f34f59c50f6cf3ec49388c9f08a7adbd84a9107c5c254ffd7296900372c03a66352cbd	1	0	\\x000000010000000000800003c413e22b4d817efc606dec74bbd27d830e9c634f62b36d0f52a66777e465adee2d5e221501199fd322e2dc68e8504dbe02fec2b437fc54f6252a028cbd2ce787a9ce743a89a707e750018c367754f0f8ea3bf22c7f3e0ef8a7adc37884ecddd7825c4467f641d0e95841312c401d0604720f922697d9a0e2bf0cc0793d6a3d6d010001	\\x43e3bc1d11328e08a56011d75370eb4b312bba391df767384cd81ae955e85e878026024897cd77fbfeda6939518680db3c66efecf8222139d9c85d26258b980e	1673191843000000	1673796643000000	1736868643000000	1831476643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x870a46e16edd576432f6ae9ddd70a056fa9309bd4caf66a9dadb7fdbcb27adae2d1ed8593527efb9dd46597cee6aa79b814f67b5f85cc30f240a32b4eacbf338	1	0	\\x000000010000000000800003c145701a6f922b844be04b3c083d31ca0a521382717b4cba74af7df5c6fcd669e7e199c8cabceb6245975b489d60f910ad57e64fef33f2e980ea66a372f1b31728d679e71ec7974dbc7efa0cc4a8775eff8a1265280c0b0df43c24765a7c783243910099f7b0258c8d99107d929b8396d903a8ef7c5e2d080d2c0a96c2899ea5010001	\\xec20848965f91f5ef6eafddf6db64c4b09e9a3adfe18d23fb0138ff3e8bdf20b6a43383d3b9fa4361010e98be4b80d047d899bf0bc577e9a82df99d7494e480b	1678632343000000	1679237143000000	1742309143000000	1836917143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x87be27c679387130edb2eac4a51cc25f4fecc6a8ea757bbdaa09cd703f4e9d4a47abbf5746ca1f449a39376d256a42ee7ebcd6056940b5785adbb59dc14ce3a5	1	0	\\x000000010000000000800003ab5081cde1352d1390d8fe6f9c0543d81438a176f8aa1a495c63cce04ea2f28b3f24f77cf06dd167dfb26170d4b38f96a78a63eccb6ca90136025c3cb71536f09711b0dda4fdc66645ce76b5711fa8e8b895f663640e4f717f0b6a924c42b8f87e09301eca09dd1df7323e41caf27759680f41dfb7d1bcfc008edef551a7bbf5010001	\\x7539773b6052fce89e6949021412d0054c366e9874233d925f50baa85fe87a5fa5964fcd9dd98b145b7c24aef404d94180454e919950e4ac15361e0db2f46102	1653243343000000	1653848143000000	1716920143000000	1811528143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x8dce4919aab802441e9d829a294812a9b4408c74a0f34f92f8fbe4f7160be572bca41a884999f56040fae54167cfa852d5d065f91079ef20ebd3e2928785687b	1	0	\\x000000010000000000800003b2325e3bbcc78578248f7a5962a68a17f7bc1cae110520d9a17ab426ddcb0894b1f717dc9d432c547858a873cea1e72142f48d30127f5b8ca52afd1bf12eb053362bacbde81a2f812877d0376cb8ed33d0231e0efe05dff48783e708feb8e323e3324571e3e40eb19c60b4f41721fd8f90b9eabc570f0d30db79ca51ec758b95010001	\\xe5f0a14aa1c509293cb202cfa6a240ca1b8e6dd544f5fd997009ef25282d8caa690bb46105099c660b9200e60e1253dafb6b00ac7c7ff6a4810e810ce48bb608	1667751343000000	1668356143000000	1731428143000000	1826036143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
274	\\x8fce13c61a2834b6ea80e1a6dc47ef371771f7168396d404fd20bd44e2d0a985432e446ea2318431e80239729be9d40306000cfbadbf784e5970fe8483dcc405	1	0	\\x0000000100000000008000039d7e0b42fce725de7c3f9e0dff9c9b0eb52da8f99eccafbb6ebd441141ca15f5a5335d8c9fa486ae5c7098d1b5c74bbc7bd71b4c74043bce779d6a9562e9fc9771aef477f046e19e10db5910aad3f3a72675e35c32e1b7014839042bef4b8cb9a6431d1ecbdba7f4bc2e300a5f6414dbbf3c9f6d99f1e38a8236585c21c5c5fb010001	\\x436a25f42e426c0ddbafc305b694ad26b81ae024f94224636d46fbe6792daaf8858ee0811dd6ce39cd3e42776693cc4b2e39e6f4be9147f6aaa8d03f48e5f703	1652034343000000	1652639143000000	1715711143000000	1810319143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x8f061740c41980aa2777b6ae41acb6c08fb28a0db8fec2ef79442d88d672468041f8d58679661bd864350bc97f3124d1a0ffe97e36cfc3de11cfbd471e982546	1	0	\\x000000010000000000800003be032e5e363cc08056efa3bc0fc71c6284011326b9765d534e09a23ad7a52993e117a0129b1511f72e35e779f65c643251fd2eba70413b6a823764807557cea5c8d1de18c3431eb706b030e707db90f225cd002192749e5edae06dc5d4d18acd49adff7917eadfab43679a1c65f9ebfacaa8746b9ea843bd7b01da32ee259157010001	\\xadb7e6533dc2cbe790921ac7f34aece059decd3f4f9aa1e691412658f6c07f3900adfb6b70472dbd4be658e3e53cfe2c5c2ab18ffb065223b28b0413f092b201	1661706343000000	1662311143000000	1725383143000000	1819991143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x91d69a0248d30dc53995fc4115478bb54d501b0fb6d2ff83dd8710867453d8543efa9311bd76d4ddf1c303223ede2bc873fa6c00b8c55d86023eb82598909fcd	1	0	\\x000000010000000000800003bd483a9a769bd8998e2a65e10b76fc5c8d3f9c1fc6cffa96cebde8919ccafcd483477890f66684f4f73f209d4d45c713298ae9bfd4e7c5f3f8e6245afc18177f07179fd4ac1248126d22353c4c948d012018e6307f84cf17d5d42c50889fc2934420302a51a20cb2ae82eba6ebdb950c3193574fc497185fcfc1a6864d18b219010001	\\xeb8c78f97b1c62b0546488c9cc2f7423e2d58f637a461d14d5ba72fdc8276f43c4f232443d33055dfdef3b41f335427421f34bfd1b9c70279f1e8440237de100	1676214343000000	1676819143000000	1739891143000000	1834499143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\x9706493af294dde31159cd5bc6d295e6fffd961f8f70a2f583bd886fc954e52a7ecfc881cd013397553507e8e3ae6f7466fc2a462c883c34b39f9a080e7e0e03	1	0	\\x000000010000000000800003bd2c809bd853a3de25718c714c8fa36b8cf4e7d8a52150485a5da9f2240c405692da9daefbc25fdec4664dd4d57263a49ea9fb8f053e84d39cb5ab35c525a46616f7f12e2ee15b24b3eed0374f2f84965525d3ae72332f72337b348bcbef3314f4dd50e3728f417a55c9e4ccdc94f726e9918fa7e3b9ec4b2d653a866f63632b010001	\\x0e6fcbb8a055c7ff504450eab55d542414c01530687ecfde0f262352e151eba6cd5db49bc5128ee32a96b120ad3edb93bfe01d71ed5db897d7466e77144df805	1653243343000000	1653848143000000	1716920143000000	1811528143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\x980e9002c12d7dd38c9863c8ff63c7eab2331284ec99bd935ccf81c5cb28a85a044b49528e969d1db9040b356d9adec92aac4b708e2c2fab09e0edb4af1a004b	1	0	\\x000000010000000000800003cb1531cd6d582149c16a78b26fe672a0367cb67eadf2df33581d06cdd0e6fe85bc3dfe6c7d00d7d60a88e14424ccfdb978e4674baecd8f169531c27be2889b4a6dcaeca85226239903883c392177daeb9ddb5bf6564a68a028377cead7263c8909e457e8d250c44d4542759298fb27873e5f0fbb07f9eb6b8f61034d7267a4f1010001	\\x72492154ba3b03a2448af016f1fe3dac792acef2d0dd958444aa52afe7fda1b0d4eb9e5c40d62c9e10a87b0777bb32211b114181f66393017d0762e2796fbd06	1680445843000000	1681050643000000	1744122643000000	1838730643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x9a96647d44457c4298b6c913ba0c770a4785ba9c7caa0f8e9e29f80a81b02ee070c88927aeededf5f2b2b85b405613f7d0a75cca17b0143a4f83cc8f843f134a	1	0	\\x000000010000000000800003c674006c3d05acb49594998284f49fe95f23ea7ed54214dab9cc1f17529b339adb5401d96b70a18400068169087cc75e61b3a0f5f84d5ee4029d61b10c9c9e3e5b541a0d48e410efeccba25a83ea64705a4a2eac22132791fc809dd7c9699d464021d7a03dcd5321f2e95fedac607c923ad5cbcaedf2bbf78e84b0ef4db33041010001	\\x333937412ef71e0b3481d1948fdc2abcb64d113171d5f5bdec8f7c6df2d773a2600d045fcf8c74e25a4e08a5515c551446745e4cd306eca0e462ca2757cb3801	1671982843000000	1672587643000000	1735659643000000	1830267643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x9abad0d38533616c09da4886901e26eea39e0d1dc92853d69544c58721b0d0934c4acb62a563c79ae0c97a856ac066cc0244b6f1e4d4f2bfffb84121407b49f9	1	0	\\x000000010000000000800003baec762f36ed30dbf8ec67bffc5267296b85853b9cbe3141540d6d0e50d6589843c8c8a86aff6b54c0a2d4e50b4c3c08256b2ce348521171773b8d4266f81e40512cf9af396c01daae35a1c5eae545bc45fa60f9156d6fdc1c29469f7027e41c26047f4875250a51087eb6296177666a3ca7a8b65d408f7fdcbfc998ea6ce317010001	\\x904777c0caf36c52c11744de395f87a711fce7e0cd8112b0b5db239687fa62e4517edd6232e18c75cb0c4cc199fcf5fde1b87a18d2d26805703749aba81d880b	1670773843000000	1671378643000000	1734450643000000	1829058643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x9c260f787d8d9668a9afff690ea1bf3b12ce199311d4271a1e630f25d0d6fd172de55f7e80eca299a94b467bb61da887e9b5c7de8ac86ebf2893a779c017de1a	1	0	\\x000000010000000000800003ce7da575b8ccd5db50494908ba6e979ec941cb0af23aeab270b1362f7d101007a8e5a449b083a2b62296bef19681d7a3eb5d0660e4082442c59d99fc72f7cd4b1e90a3782c1ca70ab7a947eb55869252e1d6f3cda4f89971bc411efd49d37140ed366eaf1da764dec9d754a401ab64d0dd36daa49bba60065e2fbbb35738f0a9010001	\\x07ab02c3c11e5c6a24866655b604b7261591d9eb4b49d12c3b1e6fe0ed6102336f8f849a9afad75ace3a07b0ed961be5b7e15a188f32a1204e9ec1dbf76d9d0c	1664728843000000	1665333643000000	1728405643000000	1823013643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xa3265acd221269e53419ce65d84262325a096ae4eda415f1fa209f2b542b2ae219370176b9951c97db2f9ca275aeb905afe0012072385aaa18c1cb786b3161ff	1	0	\\x000000010000000000800003bd9b9107ea42ece6d4a35e2a650f4afbf4380f2ea70e8675a2a96e9febdadf0290274b74b0527f806b818ea9caf491faf369366cedfbacaab49ea9c1cd3c3e0089dcf42f2799998ead32ffad34b9cc61982e5d810ad6837b9ea08f4603bdebb3dcd41d7d0f83fbbd4b18cbd2bbd0b62c47cb712f7bd8880cf1a03583b6585803010001	\\xdcb37283bc5d92092496d404772a09eb26e965df5a526b685bded7ac15275ae6789230a86ff200d3647a1db0dd70a6814720b8c458ebeee2ea500c4fb3935501	1662915343000000	1663520143000000	1726592143000000	1821200143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\xa42e8b5503f31dc2fb2c5f4617e499efea24b01eedefc168bde75df3e0c5555430b2de540f15c3d9a78051e0548400b66a6b0dd3bfd9793fac525aa3b0ba7002	1	0	\\x000000010000000000800003e1b2319e0ef48a9757732ca6a10bacfae164e2a6c978946fd29c3039daead922d48d875cd6ace19104eb2d02cf968c00123de3191f781475d19367d85adeb9063dc49ac162afba6f9021a1357e944a8b908ee62b5e625ff0b56e0e2403f013b6c78a613fdb820758c9fddffe73cdd830931e14b2b818ce6cf214fcdff513721f010001	\\x7a0c13266272ec77bc02ca4ffcc03a0d3808854fcc423b46e61507c7405d9606a77131aae9b4bfcb4c40a37dbdbe055f2c7904edbdac8c0a14f9198ec416d501	1656265843000000	1656870643000000	1719942643000000	1814550643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\xa6d6a6df6127069cd117e55a9dd33365a4c0443607d250f2264d1305cbcff4b7630820f8ad89383facd14dff338a66e66a4f7e73e2cda1eb1fb627248d5ca69f	1	0	\\x000000010000000000800003c4b221342c43cb155d2f5e54105373346d154261b4211387b0876627885b3714500be7604120089a47df7a821085e9feab8dec0ab38c9277426391f5f00fbcae7040e4cda187bae54b570c5006a51513d87141deec8c6e28b05ad71c537bde0fea980bb41ea843674f120adcd22f7ef40368afde4d71359e388f4f8171094b95010001	\\xb389c41b0164d88f977383c9666b6ebb74b9e9767fe2923c5eebf143384f667261cc1152b2475aca9b99f1c656da2c6d1c1d112065ef41259485ab353cd1aa00	1681654843000000	1682259643000000	1745331643000000	1839939643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xae5a710da7b7b791221e0e6bbe69d1bca254020eeee534cec3a60d29627aea4d8a56bfc2e4087b655c9248bd34cb54dc976bc4ea56d6c8436739613f7911692b	1	0	\\x000000010000000000800003bd581322d7799fccdb836aac3e2a33a87738228334900a9dd431473850d60f8548969063995ab0a8b7ef726c58946bb77692dec3f56a5f1eec3f2cbb264c7f8e06f5bd0ced0811e8d374e91faf794f1cbc837df4f24ae9a4b6f25fee9dc7af7d4fcd2bd50e2394704ca781f5daaf465032fd42e31fc3306159ba8f1599d844f7010001	\\xb1a30b6260a89363717add8ba52c4a00353c1382fd1b8fc16e3889bcb35f09b22c1659a820885e4175af5c31d7fbfe937f8f12c4fd075bccd6cff129002e040c	1669564843000000	1670169643000000	1733241643000000	1827849643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\xafa61a02eb7a25a09ba7e1f4d1f14e5e8112861a3e6f9f9f7153bc68567959f9785b269da3d35a79619702859e4b7d376e9d31aaf200dc3a3c3b85c5241715dc	1	0	\\x000000010000000000800003a01c0935829b428b3b7ed8485653e62de860aaa7257a5f54aa1c9b294256a4b8bedf93b4258701a8794e381c8f27ad92e37e6f2646afe878fc2fb107542281e4d4c5ee5be672122dae4ae5018fb863cff04a39d145739fa9d4bc945dd0ecc6c868b19f3a3f167c3733091c9b8fea1f94349e26f91b329670efacc8706567806b010001	\\x2c9c047dca44be876d27781814d792bdfba44f58586b69ce437459b91234e33676a09a5385fd73d377ff5083d2bae7f499dad2e246e61853fe41c40853daff0f	1671982843000000	1672587643000000	1735659643000000	1830267643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\xb1ba21f08b2cb6e36dd73c5a5800a82cff3977496427fc96d049b63144af807688e9cbca2220b381e23e6ca549e4031785557c6a82dfd5bc72e86f21c26f051f	1	0	\\x000000010000000000800003b92070c857d8e8d20494684cb70508a08e0fb14865a80c7334515ef8955e4edbfc43e4cfea98c07a68095115969206ae9db7965efd83af85762d75d9b7097c07279703cc197b7cb9d0c9711dc659070848df875a96c50954ee93f1ed239b01c1db777693f35464a110a01054e16ec6c2085f08c3f93ee7cb66b8c656b593fb0f010001	\\x991cdc55aaaa8825dba4fc7a8bc20b24c7aa95569900a6ffb67c8975070cd5b56bcd5a15dc94ec767826654a1896494278f389d3b7be59e1cc2c39570faaa503	1655056843000000	1655661643000000	1718733643000000	1813341643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
288	\\xb232e85197f802692035c617350916b1f03dc93ec5cc8b8b9f46b3959ef5c41553d6e3634bc42a84c4ae6a75ad0563b1d03cbf6e586cfddea8789b782c84a768	1	0	\\x000000010000000000800003dadace095f5f1c0f3f9f32b834e3f9ca8351db6f1a687bd3b05d3c034560abb26ca39843a4947f30e6d8e6aab3b43eae9b8290c9397787128c083161b5d24a015cabdd4db8732b2ffb70d9bf4bcd1d77aeac3ccce9eb30944c578e713bfe3f184b0dea7c3df1fa463525d074054dc7ce3ff449d81047f153b3b8f5f72837ac55010001	\\xe7cc2e187db2ac970c0b0ad31289570e68416773a9a21a69247a0c1fa6096b26509edbefce9161357e6fb4670ef85dc5fae52a140653339e58a91ad710cdaa05	1682259343000000	1682864143000000	1745936143000000	1840544143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xb716c5015668f0fd87f24f2f2d6058b00710ceedc4d433d92b3836e1adc5d9eb34f1a2e199e87f1d269a56f84abb2fb230195d810978e2d1d4a3d3b845ca94b8	1	0	\\x000000010000000000800003bc714a6f6a881989022a0b4c2d550d5a458637d498b7e02abed9dbd238f3b0bc85a73f672d9cdf6869f81aead6a7ae96a7008fe1cd6d8767a86fcc38d3c549c51317a01783b0551f84f78e511d31cc7462f2e4e8efd0a4393412910eb6c3def3426b967ce25fc9071dde617704592903e77730a20809d29c3e75f8cbd4ca4dcb010001	\\x44583c5c2108dfc325b51c79b02976f457c8ba658cff9c309b17ba062c14c8cdf377dd39f8cf43cc4c13715eb69af4bc7f5d7b90f2a391c3b28dfb3f4e963c08	1660497343000000	1661102143000000	1724174143000000	1818782143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xb73e7302b647caf725a5cc89f8cb5836e0e9835a1fa0b4e4d854b1bb98751287d0c8811dbfee50c30ddbbc321aada13316eee05e9afae759bc03e05043c7ecc0	1	0	\\x000000010000000000800003a2af451fa397f8d1bab9a18666aad63dd606ac267d9030e82a863e8b273f445d5880d3b0e9f879c7de5219a06bae86ba03791307ca05a59e68a63139a0f51c2fb7a368eb650b00609974b3e20ed98e9b5d9e3a0f973388605b347d46aad339efe161a6614b4d73135b3c9a3937a50745c4a844cebabdf22e984b4fee33c2842f010001	\\xdbb1e52c07e7ce21959a12b24a2b62851e68658ce3c16745291214ba672411c22c1b4625010283cd44faedcf27895fea0d030865c35dec8e74c903e08e731003	1668960343000000	1669565143000000	1732637143000000	1827245143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xb7bac0c03f1031887abc216bddd4f681f9194ad6ff7b29f93d97d18262c61fbe855961814573b91356898e3364ef38bb44e8e56dca2c493cab5f20ffde112a24	1	0	\\x000000010000000000800003faec68714956ceca29123debb2880daec13b440b3402fbc25fc1dbd23d2224094d2b2232931b3cdd90390f74331ce277948b9a37623c76f9e15b08572fbfef3a9272d4da346a53357dc5d78f6fae6c85ff12c19f6ad7cdc47077ae9c1a7f1afe6a9c38b4ed8a07edf0cfd457f921b231a02a20ebdf84ef1ac1a4e02d2a5fa863010001	\\x413397a788ad0824ce4afc21f1ed9cf1685ea6c9a0afafadd5e9fd1ec05b3e423e1e6c2749fe2b4b1bc5164aad330f9cd21ecd77195800bde18ebccc60f9a004	1656870343000000	1657475143000000	1720547143000000	1815155143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xb8ee45fda0d99f4694d1e72818df855834071cef64c4f20636af134f911ca7c727de438fda766d55bad00bbe886290ca3476e386b246aaea1c4b70ce214037db	1	0	\\x000000010000000000800003a8d235609ad9825266c5008c9c732852da402cc33373760486afe6761ce751cee49aacdcc75e3d69117bf1eabfee54103bfdcb0ca3a6d9a0e9fc380c784f79f086d54593da8d0bc8cdda27a276db92fad1a9154bc364e2a3b4f4fa038f736574d5e063fc722b8d15009dd9196848f0c2bffef08f04d3cb001cf979d8f870f34d010001	\\xc003b59014d4960e5c9d941b7aa714dd5221b937079021ea6b4cb6d72546f5cd07d723a3c33d839882c45e4a18bba5e6e2a679e51f94a45218a5adebfb25ff04	1656265843000000	1656870643000000	1719942643000000	1814550643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
293	\\xb98a98af89a3a70a49703972cf93fbd24e69fca1e0823ea553403494d28a742528d28849f227ba6753df90415989d3c4b4eb3728824b1e8b8269424856ab8d60	1	0	\\x000000010000000000800003c14755d163ab35d75a453497b00191b1bf17791c53264af78d2f5628322f59eda29faeb989fea03838099a4f01b32b6cba87475f4b6df186ed5cf240bab442f0d10e193fe98f56ad2e5381d3440af5b98d52ad49d2e9890c1de22108c01f6c222056054a25c5d6a6337cd96c7915439a70acdc3a58841eed9a52177ed0be8ac7010001	\\x09d7386c14dac115534b065d75f150cf68d4a49d2593a8b4dc30203a6f0fc955e4211ab5ff3d1e855d2b620671e92756ae683f98846064ceea734b680a4c8d08	1656265843000000	1656870643000000	1719942643000000	1814550643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
294	\\xbb2a954a707fc036ffb6f49864e2574cef757ac8abe060244d60a251fdec0ce78d283a4cc5491d8d70091c2049fde87a89b065a18cc76b1cd091d3b74f9f8210	1	0	\\x000000010000000000800003bc9d1bb6a031ff422a9820faee6bc04c40219840aabbd9608988e6c42f6f0dc710a8c492e6ffc39731c75e85feecc6216158c51230d5570c1184c2b0e56b30e334ea3b7a23921c1484ec4a10f4f3c09f3573da8c1cebbfd7eec0773a2e97abf14435a8d4d46686d8355975d7a0287abb86ce5c6ed539fdaba8f2f3eb84294f8f010001	\\x53109bf5d6af5a3c9079aeda65ff0a98295d66108188357463e7d2564c0424093ba5f7be32bcc5a8823a63bbc90a4bccb2fab0cbde8f916a6bf7873acedac70e	1661101843000000	1661706643000000	1724778643000000	1819386643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\xbbf2d1f964e2d47b07a2eb95b10701a8107d19b9b73162f6ad1369d64ee6971ca0c7219a5a038cbb6df50114a2123e546622283a3f75598e950c52814776a82a	1	0	\\x000000010000000000800003d7a82f3c66c21c02373ed8af70409a2c45c3c28108626a8c2a2e1cdd26c141c05b113ed33b3fe8cb6b279045d073f7dce07449d094f02a218dcbed73268cfee402ee5ed14647e1f60117fc9c7f9b65d042f598fb389da12e720f5d74ed5af75cf49a37e27ea1e29b6fda1bfa09ed8b0d4a0fd91252eac03f37202944988346e7010001	\\x2a4dfab5223c802d6b888ec8390f37bee372dd10baa483f75b6418a1eb71c929a157c0255abb617fe24baa01883b944f8625fc2a5efb176600cce0456c6a480f	1656870343000000	1657475143000000	1720547143000000	1815155143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
296	\\xbd7a2403df0adc76c2ab20a32ce25f7ec4eba13d9f545760f0db034eeb212388f53713556054e630f850ccf78daab1af981e9a440b5af8c37158c3fcc8924a84	1	0	\\x000000010000000000800003c16d52b0bcd79c403b1c14eb2bab9ab840cee05404ef1037b88a3b8431951b93c7e4312c26bcf763629390af087c5ea5d714def375ab5c53a1b4711f71ae0e45012d77401af7737f6d4b4c445f9ee11b6ed429df99e920495566cacf09a8aa5a3db59ef12acd2947b6ebe747ceea8735a297361f3e648bf776d309f058e41aa9010001	\\x3ce829bc8ee03aeac4d3bd198943fd2f9cdd80e90b8969705d5d797bee6b74f084f9ea0c483a1c67b31fd8f9152e40d4e50b03f68b4e6779dcc428da7000230e	1651429843000000	1652034643000000	1715106643000000	1809714643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xc3426d9b68df07f047225c2e78797d36704f19a71297da73cab8277b5df2d4aca40c7fcd695566235c47adee6df29e7da2407e1a466b483fadc695696c70e6dd	1	0	\\x000000010000000000800003b33bf75beceeb15b04063f063ed9a895a43e9bdd85b4e9f4475b54972ecdb17070e2ebe254c83128bde948a5cdcb54873c69d98403e15c893a1990db7ddac2fd75853fad346dd5b3124d5ceaa04fe452dc18c13fb9098f01b2d32a0af6d185c8df30a444ec8a8630f0bb27f6acf7ee257ab667505b2b64b546efafb47f35958d010001	\\x3ad5382bd912476b07e6819026646544a916f802faed7e3903bc8a2d1a9d61b04c8521594d627644c8129a2f4f2593614baede50a262486c123427d9f2555c0f	1675005343000000	1675610143000000	1738682143000000	1833290143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\xc31a6fa19344b82454b522f92c0a02a9decac30b818b3ecb59a2cc3626377d3104602c5d40b0d1f81aa6777018f82e931dedfa990b9471c013dd15daf65ac3dd	1	0	\\x000000010000000000800003aa802b672637862fb33b4eb849935e6a154674f6b1ed4922125661858c7fb2583983a6453584ca497ce8c94f1a9b3e53270b9aba11a4de5ea0dda6525dc811bc7ab9dfa5447e0a7e43485be085ff676649aad00bc08f69cf8688193469071c8141192bca147a2411f29cb0d7149a8474b162fbc670b08e049ca736244a969633010001	\\x364b637a3105f3a51ca6cf2669cd8cab1e109a366027cdfb644e3b803c6ba841ac51f7eb5c719acc8e16416c5bad8a2b089ab8e0b7c421af97a667251001da01	1671982843000000	1672587643000000	1735659643000000	1830267643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xc73ebb2f50b81ca7971b17cc7d6c02d2a734dc29a1de40f9486d0649bb45ca268f37e7b9a1557321b0e7ac5fff79709c64dd3afe24104de476bd8f202e483651	1	0	\\x000000010000000000800003add8a7eedae2fdcd5b3decb8f4f2af11bf4e935c586b39339fac81d8557ad35f13f9e3975d313fbfd1defcc44dc194e6c35696e7494a466c4be9b24618caf9eace67ed523bdb30e525b1af2ad56cdeb81b2dc8ba8ff4eeda9540caf727e6f77a3d153a44ebe18b053824589cb7ba0e54ecb339c57ef3818323f0b70b61c42d13010001	\\x3ccbfdbc99519bff6622b2fc0c1ee8323b29384230a4c4a14b4aba84b333e0c4a6b45565cd8c5d8ad8b0880dabc84b33ed3f87c884b826441f68e242ff51b60d	1666542343000000	1667147143000000	1730219143000000	1824827143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
300	\\xcc42a2008b3058cdf4349c97c09cc45c8b4d84c6bd6fb3599f71b01a34a7f813836d407f95d5a02a731a52d97cf7d9ea3003886c06b6e1d35309218972de4b0f	1	0	\\x0000000100000000008000039bb9e37ac0bcfeb93099d06561cf6f4ceaf77c1819d88f48d9099c18a250bd80df6c4466eaba4b2925b807a19152b05b437c717f0c70cb8cd28bd4d3faf723c96bd5aab5eda6c1ab13dcecc7182d4a7b086a8157f1198d6cab4dc9345e38366a9138ec3be3fbe5a9ab094935dc4fd30d1a41d0782f254423b1101fb15a502353010001	\\x34e8555e0bb45340ffce652f743b129060cf5c91f40b0a721e1f25dcbd003628c737083e4740ac4d7010429710b97867dfcb968a0c4a6673c8ae540478335d0c	1662915343000000	1663520143000000	1726592143000000	1821200143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
301	\\xcf6a8ad16bf27b7ce702f3b46e01fda05cbcc5b2f2bb10a0da1559f4efff5c059c6c493af30a4d184bb50dce75707ab218af80cc433b90f4696b42d56641b4ca	1	0	\\x000000010000000000800003c5a747864b739543f08a472a385afb0bf3130297bb757bb458f47d335075d5dec531fe7a8cf305f3821b89e5919f7bd3514520869a3b2db43d2815a24a36cf2ef23f239481a69c86a6dfcf4bf76c0afea3ee5548f5e5513971c3120892917b7f502def00068033b19297a784fd0411030dc997ef0aa1d7fac173f29c52bf9d1b010001	\\xda2f9bdcb4db7411006eaab98d3880c392b8b8c76b11dba4cb1ada9c860375ade339d14f97675671056b8ac62b5d92bf31b0af0977ca41d8896e8ba38e61420e	1676818843000000	1677423643000000	1740495643000000	1835103643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xd0ca3efff3c5c623d4661d829f990bee4d1b541270be0948a2087814f8e1fe5a3eadc8557ec0d79d765296dcec78560df7330ff4cfd721614b7d49501da937dc	1	0	\\x000000010000000000800003ec35adc6da2b664b85fb0e53f688a61a2153e74d33b09d46b5e93c8aae642d792567330143d5499f82bbbc097529da832f637859ecf96e4877b2b37d162ef6a2fcd2b28f428056cf41baa405588ff81a4323a2a5e3e4650468641500ae5929d03009b05b1dad5642fd19581f2efc553db3052149e6c24a7863eb0cc120d0decf010001	\\xd8e2263dab8e86a9fa024aff6e75dae870fbdf0a62a3c8a873869967c9f3ea627f68a524a3360dd2acfaa48596d7add7e08f2bb0a8200e0a5f213c74bdbeb903	1666542343000000	1667147143000000	1730219143000000	1824827143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
303	\\xdc66bee083fe5de118add3379fe4e73ed1c0f49d5ef1f2b4afab72b3eab72ddb9ae3c4241c1559c9ec43539b1b7a141017f1682f0cbdbd2503c7d94b153c1243	1	0	\\x000000010000000000800003b7a658a9a091c5b9fe047f7abc26d8665f647a104c0c3333fd53ad22ded8a8fbbdeaabacb08e4bec0263e14db312dcf96ca26479dd11b847b61e6e6375e819e9c3df8f0f43424a4cd2a9841fdcddc273f0e0a28cdc53c7cdb2db23df7a12c4c083aa8bea8507a58077e598b57d6ae435cba25fe294ff26f185f84a2def4f2323010001	\\xb84a8c3270595e7d759b0eb9122b122633cfe53b95453e545ed5c443bf8ca60bf938c6e8bc52181963b1041982821c68a561ee8542b9c7fe44e2c3b9e6512805	1671378343000000	1671983143000000	1735055143000000	1829663143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xe246f4124129e071aee7f53ef980a8eb763c6b5ae5700ed3043e61192c97cb2c5389c6305828eee03ab29bb630bf5cc147f0f8cd8f16191b3d86879ce7a69ac3	1	0	\\x000000010000000000800003b2ae97a60ede83298d2b9b0adb78071ec217901bf80a0d9e973c37c794b2572e1d45edd1681e611a22daa9c828a041c79c3247c8b9e33860b014f01528bad8f488a95231d1e36827fb938d0d43273aa8cb1d69fd9b1c0566613ae871e0814ad80484dccd1845a3985082ab3d27a5910f19f3754717f635ea9e39fa6cb092f531010001	\\x39fa9aa3b834ec015b9fb8dac2fc2c86b725ff8a0cb6dd529fa8eddced1878c30a67164e13227602af25fc4ab8e9de2da2cacafb42c481cf294fd4fd2e9f0504	1653243343000000	1653848143000000	1716920143000000	1811528143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xe79ea214e024da96f871d64b41089a956f4c82622c93d3599d7d6d8e1227aef6269fd874d83e2a4fb2b637eeb546595bdac83aed5f89f1975af83980c62ac89d	1	0	\\x000000010000000000800003af45017d787fdc528eb5641cb8df77ac0704c4a1e46c8921c5aaee1ec0030fe2014d39648826cd212c4b512a9750adc0ff0373a6cf524db14c300cb57826f2890639a0ed97815d5db34b108dda2591031fa063b679f1bbe230e6423e96606496c105d9b0495bb7f3f24b349c17eb2c43d792531a3c24d17d845f218f26462913010001	\\x767a106a18833d469a53218b3bfcd64f70c319af2c7e762aa73e6f6d2a3c5eeed6fae914d4a4bb09068b15fbef2778afd4d30870467a2993a9662c305af4b50d	1667146843000000	1667751643000000	1730823643000000	1825431643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
306	\\xeab25a111acddb97814669cc1ca646103c04278078060200cf092f5ff0bd18a3a0d1255c125eb4f354878b76d61ea250824fcf8eb48f8f319a8869d64479f3ad	1	0	\\x000000010000000000800003a18a27cee16dc03509375d4082d064b8ae59c20ca35c5caf8b55c0fc15b1d286fbb141f9c956e6acc3ddd90c723722d13340a7471977513aaa8bd15e8cb440c2be3dfa85cfab1bef3db1da1d3e6eac09a10087c38fa7280fd8366fc0c3ddfe1032116e645134de4e1e95a909de1c83c535fa26481d269a6af10fb4569ac15e25010001	\\x50aa92ab721da5e5008b210f8cae6050b7fea769c7df263d42cdc12dfbc589010e966b15cbaf558764413bfa734a8513aee931e4a6261934c4cdc451e46aac02	1666542343000000	1667147143000000	1730219143000000	1824827143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xf78a529a2d91341ce5fafab87394c2e3900b6ae4f3fe20cc855cafb340ff8e60d2b9ccf18a9aab11bb2fe1f080770bf8cc1d58379590c9a98b525407f67c25fc	1	0	\\x000000010000000000800003d772625cc2534b24c42641cf86a119f074d23461d891f6fd3be32d7f9ca906c2769caff7a07145b18e16835d3ad856571208ac3a5bc76bf292718812ee9c4e7746553834f14c8bed1a01f95bead92cb7fd6d58f72561850296c10f090b669c6c5e9edcb7125da2ac763f7ff1671e400d125297e04ffea2d9bc1a6a2a03650429010001	\\x014ee1a4ad493925cfae7c76640e43cbc2264618c64077e511a3c83a733dd73f1ebe246402a0fd88154709b40e7b55ffc68bcbd039f65b226f3dbfadc2ed670b	1679841343000000	1680446143000000	1743518143000000	1838126143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xfb3ae8f7dc43c648abcbb3cbabdde9bf51e7b5d3ec40532a810179ef19b53762f175fc750120e7e33eba68e40fa80acda1cca7b8ece8f7e11a8dd8c3290c0604	1	0	\\x000000010000000000800003d0a95219fdc80dd405a73c8cc76ba067b805f0cd954cdee6705b1fbc7150dc5831499124f6d559fcaed9cc8c6e1a88dbf1249fd4889693d40918f287f166efafef781c92e0c02251ec9a6e8932ceedaf60754bf734a8294b0f415e332b04b5f8773a137fd6c1b466398c3eda61eb4f219211ee44dfd8d6bc08b38277da342d23010001	\\xd238befc6ed486d75f09bb63ec3a48352c8ee07a7d398b01f58039b9422fea58f93134807001f43e39bcb224994524869179d5a95f4d64e26a7e8dddd69b4e0d	1673796343000000	1674401143000000	1737473143000000	1832081143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
309	\\xfd9e0d9fcc3a3b7112a32f39705fc33e6bea507440d72a25d8f11c2fa9f0009b3c0b6c947c76403c6a3afb362eea0d8fd588d780d5dd0f531c53b5a5a32b5787	1	0	\\x000000010000000000800003ec1e4ce0cf8e0164a5e5d2a15edb6e1da9076a6a827edb3b0d7f4d01e57def006d96c089b433af32f3ee3d5ec660bc1b962b3bed8921051d0bc727b921ba5e18f72347bb9366f7c83de9589a8d87b851d94e5dfc125a8c699c9acb0da341680f86e0ef98119e27015f7e4d0725f9eb9ab382c87e00fef36311459facf4957247010001	\\x1806795cc0b08127a642a2470860f49d8d521208cb6fd5813d526da450703f0f4e46aa63fbdbd11061f53e49cc9c4b54a8016c9892bf95e262902f4ebb2f1504	1665937843000000	1666542643000000	1729614643000000	1824222643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xfdea549dff073f0284058349ccf36a295157912149aa216b344977e04932e1d283a8adf7d57572bd9773d4b6bfb1fcea4d18d9391fa35967ba5a72c0b117b7a3	1	0	\\x000000010000000000800003a7c2f35ede1c034bf3c69e7b47fc69a1db08335f69f661eb86b0d4f4a0c5b3a5bd863253d8f27462af5e66b5149c31b3f69311821db9332b871dfa8bf54916afd7cce062806df234145dc189bae71e3dd42c7604a1cd50f0176466cec2e93946da8140b0d43fc14bbee3a075cf5f63a36a33482836696a79c60fdb46b6d412a3010001	\\xb8b4c910ea79b63b06770d1fb90f504557368bff46186c52acff4ec625598ba35d1d972e4aa887292fcf0e1b4e7a1bf9cb395301518a88360c503c090ac0690f	1665333343000000	1665938143000000	1729010143000000	1823618143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
311	\\x007b785abc711be5ee02fc3a54b829a41b429148363a7e650acfe8b536d91b790c8851048aa77724038ad0f636e22632a281a72f77007e176a7c029dfccbae28	1	0	\\x000000010000000000800003a929a716847b7cdb2bf511dbeebc0043c7e1f72441c1d95ff1f8f476a8948d76e9d3b668050b107e04402b7a14dcd2907ba892c17f47209e1a339a1bb297f0eb3b824cc23b8d68437f6703fb48dccf3a62b5465693626a4381d419ad9429656aab02b6e81f3c3dee981998dd4a249d1a671bce92bb18cf10db5c2be0fd5aacf3010001	\\xe367c9c79ca9ba45920ca361bfe48f1698e3506abad9817d7816747f0f05dfd467f02cb5c22ca5c42300b066473072bb9cbecd75fcc910641bf444782130490d	1656870343000000	1657475143000000	1720547143000000	1815155143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\x02af83744cb9b0bde81e3385b8f9cf61304ddedc4b364d6e9f93f272341c645ba63220e5ae999660159748acef026280d21595bb8c46f1df4f3e04e32aadb22e	1	0	\\x000000010000000000800003a47f6311351549b9991bcac0a409d7e3d52a42522c683e9436e1102e3559a6fb8813c9b37ad323749a7fb2323af3bd655985094951ec938b4628f23703afc36eff434dea42e024a22033e33025ec2fc8efbd74b9c23880c59e1923f5bfc600cebdd964e253857313c4209610c4e378ced317a7f47c51e61d5565270b7ee4e115010001	\\xd398d7ae5238b469209736a076650a388460ccbe6a0e8c90ad6ae89a3f3dc03476e143cc18202f3cd6249cfe96805695f4921357f2f5e4e23378ed299abaa60f	1681654843000000	1682259643000000	1745331643000000	1839939643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
313	\\x023b1f409034fcc1e10e70072e4cf13cc2970734f6e38c4adda71749270e93cda7b8c3bc2b5ad87a55dc82323153447fa43e7416131db9ddfb04319d7910c406	1	0	\\x000000010000000000800003d3a6636abf0b4b2b1e01f41205db641223312f75b415e157a42a8325b0617940515f602a3f2d1b43c54288699698130e2545e7bb2284569c6b2d53a87f27c3458631267a0133b9b3ba28268a74cf26170e6f51d5dd20dbb40a78b40dd8b8082c199a1897a027efade1486a7d5e02cc429f709ea1249b8279900052ea40572efd010001	\\x5fed9b2bd9565d54b903bb5fa2d5d97eab5a3bde05a87dbd5fc50ddfc063a2fef6b7add0888f7fef692d6cbb9d164f33e756284f77b7ba3fe438cf2c6e1e1408	1654452343000000	1655057143000000	1718129143000000	1812737143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\x0527665c73c975a8dc9a815d8f1f749970b06e0d9b711a91790e6e5102d792069a2c77b639bd5003170ee4c66d85b2aa057d66ba9db2d0d246ccba294641a82c	1	0	\\x000000010000000000800003d23f6747adaf6bc25e9b19b33439d49ce3890b8accf041961e16028356d25373d48219ed2105515778140b48d2bb3467b7067eaec0bb3a7bcf15f1a4026dd8a26e0c001f7b243d4fc636cce2e23041116753cda15f4bcb077e6dbcf1c569f4fd6fcd8dbc93f5d878c36fd51bb86f745eb2da1a2d986a471ebac475af37f66161010001	\\x9bd43b186cdd4e32aff86c6779a4fee7d40a2e4086d2b05869df0317a701b1a22335889c2d0ae3995c1d5e3291c2d71b1a49ba1a15f2deb8200f2cde48057a01	1671982843000000	1672587643000000	1735659643000000	1830267643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
315	\\x081b277eed21262d761fe5c3bd2be7902892eb7904e3ed0d798091b820348426ec8d5ff400acfaf027ac612760026a5ae0d464866784f561523ca8aea2fd1517	1	0	\\x000000010000000000800003c09b99441738c5316556cec109e5ce838d9b7c7aa45210bdb98eddb581e1e99ba99a84da8f4d636fffc51dce34b4fb131f0b281c1fc9ddce5d35f4090413a6a5fb9d3a961ab297dc3217f5bbe6cca05c4bc7009997d513267fc0d855e928774c7cd47a1f3548b3a69ac53ae32638b459645752ebb94f9cb4eec59d3f591db19b010001	\\xf15029eaec78689ef6c804fe1859c7cf33d5b963354078526671a877788c73ac38fcc6017d2abcf123272fc9938aea9d92539895193e94b738a9474584af2608	1650825343000000	1651430143000000	1714502143000000	1809110143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
316	\\x084f851d808c66f98946a988df61ef0c2b575a3daf03a5f88163f41e0142c24de92fb70514bef6eb54becc2fc2840e287d5e2437d09fc72a12de7b0e4427cdf1	1	0	\\x000000010000000000800003b27025856f402a0276be8afa510c4f2ef67344be04ade10c4c531d84e89c3893651200d72d3d6217fe78b8398e6a8d6853191f9511e25bdedf426f1728971a5e0c8fa45f0b3aa07f70e74be01140e86ea450e6f7c319fdbeb5d0db2ae1abdb5b1f4ced31b89d407bb0444524def92da3cbab9f143fe313854162340c3d26cf97010001	\\xa94388863529c95a14e95b42e55af8e8c98d4ed28ad81f5c6a668efec429bddef02d28b64eec263c792c161a23a90cd747b65e8682352a5187adc0321831f90b	1663519843000000	1664124643000000	1727196643000000	1821804643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
317	\\x0a6b1fc300ebce1198f2d0712b8d95216d85b7f96e139d4ec41a8a5c2f6d0ae5da5500b0076584ac744dd979a0ec00f1f26f6fbc0d5f73b3dcf1808e03e1f433	1	0	\\x000000010000000000800003af2104a8e2b456cb86cecef952524356624dfb75433bc85b7726b7bbb2c750293a12d3b286576fd6944202ee48109723c86174927ba0ca00e6ab6663e007249976fa6e992cea24dcd1c43ddcd1bdcc397b1889307350b6f98b57cedeaa3cdc169b3702c290a157a9c5f976ba9979443184bad35d3fd5e94c24f9f16331713fc5010001	\\x0f7d96b0ea4f9f2395d5780441b8bba23c798e1a86d791499bb9d5f3a29e2ceb98b2c953d83cc23d4d6c8d2ca0f045c9df3624cdd85c5584bd8a0a405dd71103	1664728843000000	1665333643000000	1728405643000000	1823013643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\x0b337ccb69198dc54a4e4106034fa7548a3bca56571365a933f5d4612be54cc352ab7ca4c661d0e107aa01cdeb1dea46d4c00a0d4d8f5f84e372edc3766cb511	1	0	\\x000000010000000000800003b91b97d4461153ba0ceb20e3d67e090c2a58d6788456710a2752ccf296febc4b7790ad74aa3e1ea8eee7d6b5172a39573b5f46c90c8c6b91f8cffc5c47829705c748e923c13b6123766fa155be3593af5e84d9297c661c02df85960078685c817705104baec9f222c25777b5821621bce013323b66517967fa4b0a7f484e892b010001	\\xb46fdb6eef980a98fb0ba1f110e6d0ba20547b198971f02d935e5c50d6d0b924a6f5f62b6482cb511f85683f270e23b6c529fb764672f5f9268d2115d1a1070e	1678027843000000	1678632643000000	1741704643000000	1836312643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
319	\\x12f3b6cde35075210aefadc8f48053464d052fb7a4420c76090236539c2626f928605d290aabff02e3051bac8ed53b57817f53e4bdfda70fe8662edf0425319d	1	0	\\x000000010000000000800003d3c39594790d2884384163b17ec8967d56ad6394e61774e9764f6e1b63bef4abf9bd22a5eb427e8576fca23460a9f2ea2cca21cc00fb1ee38bd1c62d404d91359834e903fcab3fec78afc6cf7ddbe62284c631f34427ca0d4cb32eb3a972e1ddadda28945f3456cfd190bae413b04415b3c08aa18e7de7a35df0c2fb348eb83f010001	\\xc9398a55f99a98d3a8a3b22a679e23c201b9406ae8e1bc9c6eb40e20800093ccb91d8e9b0fc4c729fb8ac5259e8179ba48b03dc3e19ddc14a9867879bb200209	1658079343000000	1658684143000000	1721756143000000	1816364143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
320	\\x127b6cf6c0407a6c1476fb01edffc7ee58f2d58e71b7f9fae19486a90e6269a69fef8f944806a9ddbe7c7b8a53fe69a2490c65099d79b438a1c127143cf08906	1	0	\\x000000010000000000800003bb2cf0c480e77434e129b7600a47094fdb00b289b6c82ac882f6959b5d8b80d573652cd6a7645d747473fecdd3adbf897733eb324ffbb7b992d779cbadac5aab8ffd17e7ed74261891fd6fdeead9e25e56dfd64f870859e8d2d2373947de1ac52478ca6b3091c5dc3839b2f74fe5b4cd0973c594208341d6813f8f77e3da1d7f010001	\\x8986440d4dc5d48d3ba5447cd35a8718939bb7552ef4c8473b5d9bcc603136f76d17ba6ef27574f6de9b8cd3546bd20e8d57dc59132cea9288cfb4b7a1f4c309	1651429843000000	1652034643000000	1715106643000000	1809714643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x130f58f6ad79ee270e897312d675e7fd5e8cfe649fdf45400ae97bd957d433c2e35dd4168c5bbdceb475354902c90d2006cf6ddddc2f9fa147b69ad09e2a6652	1	0	\\x0000000100000000008000039db0416e37ea1580fb38bb0cc1b353288d3976db62e255c5dbfe58b57fa64e6d372ddcd2983449cedca048f582e012e147820ddaebed95ec041f7c17cb000b488dd935a912660d1dff770a26352374ea1148f8acaa6538e74314de07e8317a5900ddf2f7490fda933ed4c6ea78dab0feed9a878ceaefcfe755e8dca0ff6d16a9010001	\\x8ea97b9dceec6a6b656876beffb0a80f720c7de29e5c0a54e24539951e60881a4a5cec3c38a66328458d6be04980a4490ecf8043fa8052e4ec9fd38d5e9f1809	1652638843000000	1653243643000000	1716315643000000	1810923643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\x1547897467592c40d5bf60c77af367bf2e5b1497a9278d0481cfc9f1b4c54ab2a16004a5c70c0afeb0e4c4310d98223682c689fdc5ca93cae7258c678ab22bea	1	0	\\x000000010000000000800003cac173000902d702736986cda589e294fcf4d02e7c2143c4c1acb1fdec4a24535e90af5308cf278c5d5bedcd1b726ab93c856297961061d979a7131e0b097b0009b4c37057ba4df6c0d680b205fdc09d8e1de8fe56b0b1a143317495452286366b867ac6780f1337b3c3c13b90f0358be76e9c9cdeeccf588b8c7affb6093565010001	\\x3e0926b3a0aeceddeabb4704dadafd1cac3259f4348c7278f096c24a02c9bcdffd1db5b7c21c146adbc89cad01afc675ee02ad8a4180439813a97e01ad8c0603	1662915343000000	1663520143000000	1726592143000000	1821200143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\x176b0b617d2a8f89368a4f2bf11eee517e625067166376e14af3c4716b6f69bf7c2b48591d0463a9f3d197540ecf867cfff72ebb92b5784ee062a70bd843816e	1	0	\\x000000010000000000800003cc76f1186ae2b6cf72473501612fea7ade95c7731868ce89852544d99ed9ea28241880be3972ebd3a941993fa8b47a0570df5d145480e2964ce24bfa9c47acafd20b3f5b8c16afaee61071db8a02020eabf8064918e85cdb2b773867603134aec6710ec54f2940876b8853a7801fc616422213fc6062862dd31ff5ae3c7dcd0d010001	\\xf4456d493802ef7158cb69e27ebadfa97387bcda7c3067b9511e8de529947531de4d7a9d320ce3706080e4adb6bb628b637d89acf3f67d71bcef1fdae5c75605	1667146843000000	1667751643000000	1730823643000000	1825431643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\x18a793fb2e0769132fb97e85394c7c78bb72dcad45d36a1d7edd107692f1f912b83f73ad3d07b942fd52845ab7fd886a15498ac91954defad89c32614b4726ce	1	0	\\x000000010000000000800003c0e5d2d8d6ad016562fab820b2d8dcde592b66e205feb967c6863a9532c9278620ab227b3b1ad21e3f3cda3292a049a1b2fd8172c00f425e166806b92766aba3387ba9f51c31a27d6022c9da7a8d9dd74932e93c613b271083b59f82b0119f1403c5d01885d95925287100f208613b3f38488345fa37f90bb24d34da39b8e64d010001	\\xdc7c9b8ce055a41124c1f2980239974e3a61e15fc85b5c319b4a201068d6d28ecc7c080397a619bfb9a2567ac729b67f2eedd5dd7a7c7e756c7049261cba350e	1668355843000000	1668960643000000	1732032643000000	1826640643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
325	\\x1beb95f7d786a65a2ae62f3c69c19e31f361bfe83c7948a3a04d816fb177b0c470f9e35b91d6cb0b455ee524ec8df6fa6e3a40ed2001dd6074b87fd3f1dd4061	1	0	\\x000000010000000000800003b12dc60e627b85fd7185e633542742a59752c8c9b58f66a5e0729a680ad615bc63233164cc5fbc375f2d4a093f4f7dea2232232897a12ac644b5e4eac2e7e268c32233def6460a2c3110637a7e975402a11d9868e64d19db98849e3aad524bd3f5306fb11d93490014d1ab4121b0db222fd9cca7e4f4cf2a1b0f92600d4e6881010001	\\x7e049b609b53abc61cb6a267fdde7ee98d2b00616c464702ce75cd1b8bc1983e954ae3ba5340fc5377248e3f2867b76be8a6997129eaf2bb4fb780440d7a5503	1650825343000000	1651430143000000	1714502143000000	1809110143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x1f37ed50d45b6161d0b9e98dd6b87579ee4703762ffc6c29c8e8e968bfbc92832062824c316ff91b72bda9f63839ff5972b495a191d187895193e611a3948760	1	0	\\x000000010000000000800003d2f7e3a98acadeee999f532e244b405231b83d53c4c6a7789946cd6b0eec21a2a3f73b9e576cd83b9ee3e76a73e61b0fe67c133253579b45f43bc9f593195dd4a85db0781a2ef5415f601dbd6e8f679a8c805f1eeb223a9af1466a32b296d212c5e5201b38d54c4a812a5eab064d37282e8f2ed889e89f570e6e431a4ff86cb1010001	\\x41512a40395d652bf7242dde48411d31d335e44bff2aed1e31d72ded4b058d790617d65e09283dfabc4af9ee67f0d8d65a8e79476018ed01408c1c6013ead004	1671378343000000	1671983143000000	1735055143000000	1829663143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
327	\\x2057d3d60c6626a7df23af7a624b6d5e72d7ebbc69c3864bd09d15d9a23a1c364c8b9b8e5e7bfcbfb89f1bcd25a54a855aac68df73affac04889c22920178ebb	1	0	\\x000000010000000000800003e9dbda20636d55017f6924db2d9dd55dae0c13186985b5bdfede40a4de4565bfcf5949bb39c24627632163bb183572e065cf02de3a4cd0881f694bb5cdfd95fb947c47609ac290742cec869c58d1ad80f68f00847df63e9f0334fd98b9897b17ede3b8d07e8140dd1970351d5e0021b5ee4431b488f7b1e6b423d15d4c76bd8d010001	\\xb7b9d3faf258b6873226960f1acf75fd273b25c545ae635c0d78e155406be008951949fa3bb6e46184ab71a408809e8665240f083f2d00c2c347803bff529f0c	1670773843000000	1671378643000000	1734450643000000	1829058643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x2543df3e9dbf7cd4ea69a651245130da95bb243621d360c1ca65f5b934e6ec0b0dd3ff4b4c892aa9eaeb45c6c30ed89c8f57bfa5ef734462ba00cc356719dd16	1	0	\\x000000010000000000800003d5e2de7bd5c166c2466dd8a4b0e52648844e9a5bfeef763aefb7b6a1906a61e940e5cb4dc0c3280890a5ab6832f9aaaf39f30d114c6937b9933ad85e6a7a9d2e2b3621d552318eea70e0b7b275a0f15677754a65d53f6daa6f7e2f3df625800e162610dc2708201de19cd47befa5e5de1fb57902275e43e8fd1f8777fb92422d010001	\\x163a5d07780006552283fde463b8f745d01e788bcebc33010247ccdeb0cbfd732081cf3a2ba618ff7d3060c16f1c94feeba2304782603c00b4b69ba84dd22703	1652638843000000	1653243643000000	1716315643000000	1810923643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x27474ecf82956425ced1bb130af34a32f3cd4b1f63381ae99455363c25ee2fda9a9d31f34e7fd3d127e2214748be75c281e54574053164602b6b13e25620647e	1	0	\\x000000010000000000800003d77f371b135ac932abe864265ed9c9680739509800ff44dbbe42af93e3338ce7a59cf3bc1f783190c15276d8e38c2548db388c96e84743d9da965fcca48c4123fd67e69c06e6fbc79c90dcf8113beab0fe291e1a3f395bb8c0469d396e359c4e710bdf8fb84d0191dc2eaaabd40ab754c8a46fcc4e2486530e4a6b9d848573dd010001	\\xdcaf0ccee64d45a7949622814e176b736c0066c7cb615cb36b8e65c16b528609ef49477da3726e583b557569a101006f6830b2de33e4f832f297f99df79f7a03	1677423343000000	1678028143000000	1741100143000000	1835708143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\x2ef763dd97b3d42eba5bd4d5f311a694f756025cb3d64e459da85f50b71908d90055d27e8046b61f07ed3e325056bb4faf0bf778b33c485eb37b2bcc2ba047b1	1	0	\\x000000010000000000800003d4269637a66f5515ec466821086c738256bf0f00bf4a82319261b0e9fb9473886445c9bbfe9bbea3808a77a15d834ee24f79d35da80ae130ed33a879f04b0c89b2a0e1e80f4bc3594e441952e66f4c4542d061006b82e08f07cf256b09ea299b6c45aec09bc93dc03c3528c3b412f41d365d2bbd84aaf0a1f81fcd9b888d9807010001	\\x6d805ea4b2bd716370bca6e0b4494817be10728e0deadf7656fae8c9b355e63d25e9cd611a3cf6f942d0c75f230dad92e0424e0a77bff4241dd73e0e550d480e	1676818843000000	1677423643000000	1740495643000000	1835103643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x32c78002d5a0d52724863651f2f72b0f51f9c1c64bd900a03ca14ca4f0aecba956cc2a9b8f3bb93266891bd18b2628e173e4f378e76f3e5368032e52f842416b	1	0	\\x000000010000000000800003bc022e02f0c2ed6f2a0ee9a87ff0c0a7cd8f946b2d1a793b9f9e09509dd6da1f60516a99fa42e3564f36717c78ef6109d6c83daf7e5f8098fa42704d4afee0e662824a80dc0ed74563f1f64291d478f86b33010bc383e4b0ff05a575cea2329bc0f981bcc350ff94eaecf5857f742a95ba8ff8d4384e5f7cc08c6ae5a5974a45010001	\\xefcf14d28686d9afdce16c0060cb790d5e1c59a8b5c0769c88335895492bf6592af0e47cebebed2ccc234be89af9b164b2ccccc619be9496a9c065d71daafa0f	1657474843000000	1658079643000000	1721151643000000	1815759643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x34f3331275e5ae18f4ac27b07ff98cdd1b14c49043c1866ee144cc1ce0dd275e91dc51b98a6215fcec37ca4276c67fdc72934ed8dd4ae907c942fea3601fd182	1	0	\\x000000010000000000800003a44bb93d15a47e02b3dae38ed976200d98855364102184a4f8b3432fdcbb28e97ec30ca901e89e9f42ff70f326ac28f1c2616686a6610ecb374939eb21da4a53e29da01ec8ccde28f9e93c79828ddff2ab07fdb1ae8e4424f70450e4f5104f53a16e346e48c631262e879f4c1c80d6a737948b5800b862af2595f2d14ca0f4c5010001	\\x1e6b1a7cbbbdc038acba010013ff41ab1918b4fffc25fad2b654d6956c8b6e1430e71744ca3028b6bcad5d91cb1a5add82a6e1cc8d6dc718068e0e2a46db2004	1675609843000000	1676214643000000	1739286643000000	1833894643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x3547affe2cc793dabc474359adfadafa32a58d5e747deccacd805ecf9309ba56ab9a7833fbbc5a20d3f3a3bb074f01acec4c31a54c77c16393f4224c8228dc7a	1	0	\\x000000010000000000800003d2264f9446fb0126373434ed8bc53b7a46a060ad0f9956aee1bb6662169defb197936e029c339ba5b2c3e6a118e62d2d79f7fb2272188a7a929178c3f02d2a16b7a6bf73c9a384e45dbee98c1774c2b425a3913e58e1c89e50bbdf52379107f05dbbe1141245c7d22002776e636ce649e12bcd81e0bebc3989f5c2518846df61010001	\\x50eba6f9a08ba62e0aa9f8f2bbcb59005083d5e3a49e4156fdbbb9f20c36ab0888e6fc58d4d05344cb4f6c9117b3418081f97e86125920cb88eb8fa4db42370f	1680445843000000	1681050643000000	1744122643000000	1838730643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
334	\\x362b1f67887fb7bcbbbe05e93ff6eedc55aa67e9ec38fd924235a8345438dcdeffe0155424d803b5168e1655f84f1229ba5333703e2c4f5ddc11a19504279a8c	1	0	\\x000000010000000000800003baefc530d7dd00d8b903cc35c6de99751d3e90f28f9008c5327ea32fefba56417bdbd7a3c3e3386a9883c923f85887a07c699afa865c46925c3d27aa9a63f839b134e809ffa27cb2f0552eb8e26880a44c13687cff60c33cc7eec7cca1f2d7562d544784c2903a48d8763d386c13d1ea35b49c326efb1d0229fcf9ca7412d1b5010001	\\xdc2353a49dc6a82a7db97e7077a79cd3e8255f75eb08d3b8626904bc01ec63c517b084152eb1eecf9831af1cb0bf51f9c64641879f3a7b2e0ce6557154f6c00d	1655661343000000	1656266143000000	1719338143000000	1813946143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x39eb6caee9ce9da8b29b3c7b84c4b38c03dd46cc2669fa4c405a9c02a112a57560add09c4ab2d0e74cc514e14fc610f53e8771c16fb0c9a5e788d081b418003b	1	0	\\x000000010000000000800003dc3cb6825d94d43ab7966cc61af4f30baf9894337f730e9367c711949b36b0dc5e43fc2ac6e0455a41dfcecf87de6ce8ae3a521512fc5189536b7c0e0aed37aee8a2f15420d2af926c2fc5c12be8f12d7507ea41ca15a5f1de7b0f15293435f36bf9878c42066c382b1c1a647cddd34e43bebd4177d4701f198054d3c9b3e783010001	\\x8ac81c15abf0cf4c8f464d60de0da8bc395931ca41ab7e8e8dc1913bbe91b86b4a1ec1e2b362b6c8b3c3aafaab396cddad62f8a477d7e5b27f185506adcbf009	1659288343000000	1659893143000000	1722965143000000	1817573143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
336	\\x3c5b986c458a55d42da51542342548a45847e3fc95e85ee603400308162e2b3563890c3d446c176fd42dd443d90e0ae668e7577e0f3685cd09437d8ca02d85de	1	0	\\x000000010000000000800003dbcc7d8cb5c15cd2aded23b644982cc5ae8c831acfac8d74d9a8be9f9ba5a0276557280a2380917b1e167286c4df4e6b3dd4a52fc0b3ebafba6f200dbbc44eedee7e2b7798eaf445f1bb22a7250cb4518c45c26afc305e0dfa43fd9720beb3b1d67a047032105ca252f0704cccd818066434d49e75eacafaaa76504b2c242f95010001	\\x4f17b8d323f0d4d1e09a534eefdb43634f04f0692857b616662c40eef6a5283299d31cc2fa9db492a6046c4b6a41133860a2e8080ca4e9f1aa555fe301cab407	1680445843000000	1681050643000000	1744122643000000	1838730643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x425b6128dd4e3072d1aac5bac4122b8cf13e970d4d66ade23306410465098980055853f5402794272aef48aabff40c8034d4267a16167cd5f5dd059b9c830520	1	0	\\x000000010000000000800003d501edb949d67f112895c8d2c7759db129a8ae8257f74319123762917647d51b482099cc43f86d5c93eddfdc431540f2099766ad390b4753be7d2c476dfa170a612c2745f4a524577b32c51c713f5df3f28f9c322fabbaac18eb979ca11ff7487a2c848eca9752faa2a75b8149039289403b50881fa2c85e4570c6f4989ff995010001	\\xa77d32ba7bcf80cb67ae8f5a7a2128ba5668a19990db927dcdca0aad14ffa403bb11efd81a2899ddf63cb75e92f94172606f27675a68ff916a8f72919e35ad0a	1658079343000000	1658684143000000	1721756143000000	1816364143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x448be0679638f24cf2d3f3a1de1d6f30dc8bf589b9b03186d9b53befa7932be5d0e667cd33b545ded84a875a763986a5a8958b752e5770bc3972a429cb3e4905	1	0	\\x000000010000000000800003b9d45ffecddd22971286a2ef216975e929cd97988c839d58e916bf439ff57b6ba29eccc76f2e00eeff97b999837fdaf8945da2b474358d61741fa6136657bc55a24466db0e68596eddc69bdf2b7dbd604262e2129c1dd329a3d30c4d1d3570a63d08ed94512c3c21bdd967c055be78f3cfdd9fffd2ccea7f86e479e5dec4781b010001	\\xdbb55f33fd1b85d0c63b2c8b3eda4aeacb6b2564c5a74b65d71154885b9a4db1180232ea27cb5e0dc4303d4de5daa5505a3a1e58bda78d9a58b6eb3265c6e00e	1675609843000000	1676214643000000	1739286643000000	1833894643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x44abd8c0f5ba5a419d17d0ef7401af491f84d723b8b2a62070dddb08dd92372a43e69a63c5c13f59db305cf91b86b4a6b0b1c60917703cdb9445d45376eb1665	1	0	\\x000000010000000000800003c55dda598b85aa0614f39d3542e82d3c07a1ed6ab6909568f2d0f8635f2d407979c0854bf470b19fc1d88049ac3f671c4979cd9baefcf176cdd44ea3b0c13ff56f58b98430b23c12ebf6f5ab6f0ef5f21164af7ec24472626f3ef0f9455bb7d5e0afda98edaaeaa6283ca675ee9fc5f16ddaf76bcd3cbee89a5696c6a94565d5010001	\\xb997c75b53d1773f83dfdae263e89fb75c775c94e018cdcb5f730379599084718504a31d09faf8b128aa12edcb6aa8bc9ccaa252f6593fb0f021dd5aa7e5c90f	1669564843000000	1670169643000000	1733241643000000	1827849643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
340	\\x464fc452fb8e476fd2c78fb98b7710b12478d377cab374c9cf2a380d9689f64e56dcd38f265926da4b8887168f15bd785dd5ca185592d836eaf68b71688bb0fe	1	0	\\x000000010000000000800003dc9c30e52392cb8bc16cac6630ce9254287be3992110d04e813cfb27bd267d01077d17bec82b00416aad7765d7586aa2fa6ede3ac185ef9ea9e1813802b46324ecfe87b2bf6d1b99a03bba779ae8a5427d23e637566335bdb533ddcc257f0192d35ab08bd0951711d3acd7eb5ef1dd5922b5df0d6cbbdbd9a6e666eb565b30eb010001	\\xec29ad35fd4d1a1b6174fd7764956df9cc4b37c16cee6937a0fca181f69159d6d811f0adda374d6aee516789b7b658e5c6a6779d6f5f505a14bd25749242370d	1671982843000000	1672587643000000	1735659643000000	1830267643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x471b3907306837e8bab2ec6cd6996c28d137428e81be5cc993f0543d45b0eac98a551d5a0e383472d2539ebde579b14fa8498b82495e308860e9ee8ea689eab9	1	0	\\x000000010000000000800003ce25f4b705002587644e6c0f1dc29ce62ae17777bbd63242db0541d7074d4060075046eeebe11dd2d46b643ba8a8abb9c8fac61ac10e2a602e38c36389f50d14ff0aba5967b6ac847222ade88a434e5fe37f9b7f0bf137d2cbf844e4845a37681ee5bae4f92caeb65284ff8c344a86d300a0b7690e611f896587a1191b7ac485010001	\\xb9349fb3f37ad9f4d22d0e9c65bcf76f56b35645741efd23e6a230607a7f9504679797f1289f852e78af542e4d2d933b09297b94171c4062c16d5edd7c4d510f	1676214343000000	1676819143000000	1739891143000000	1834499143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x490bce17545926702ec220d18852ae075804f1aff8daf2c85ace96f5b2ecf55e4fecbf400544f06193479e291f9882114e3551f4f8f7c08e04596a78fa35253e	1	0	\\x000000010000000000800003a3f048b309b8cd43c3b01e6b92e776967fd138abdc5f51448ceae41d617eb8c775d6b0be9d78aa63166befcf4517968321f44ab99c9544777e9c1de05a06e635b3b4e5a19885bcec0f41ba563aa9d44f5e105308b872f6910fddc6fd91317fe6ef5288610b463f9f8afd249fe60397e708b837ce5549287971c9643fa32f27d5010001	\\x1184c95ee7e15d800d42f7c7d25aab733f823f5c24db3e39b364a4bd6b06ee026b1892133df122dbb33ff7dc0bb127e9bbe8a7d57ae7b5df97b46525530ffe0f	1659288343000000	1659893143000000	1722965143000000	1817573143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x49ff49af3c105e7ae45900b0fad074165cd8ef71e1bcb0381014357532e2c9f653e1947c21fabf4eb7f501d9605dafcc9918af9486025309a8a5f53a9ee2c457	1	0	\\x000000010000000000800003df941df533c0e569d70c9bcb5faa5a24cb71b757322242ec1a6fdd675e0386ddef9153974734e47be66de22e5488f0cf509bfc7e725c6f7f941ddedb31dde8d7d6da445b18510b9d06e8ab0d853a21e2e9d787491a7e6f4d9bc5f39bd3f6b44d5899ad0a2e45a09fbd40aef2df61cbbe5037eb423fe9dd32ee8bc0cec5bcb60f010001	\\xacf592baae55d246849bdb7fbda2f028895e35ebaa9fb900b2ca3b2624b1e3a1b7afc444a8b534f3f31a90a37eb548bab16a0543e6dd880a93eb19126e14c701	1652638843000000	1653243643000000	1716315643000000	1810923643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
344	\\x4b8b5151911fe858d68b7ebcaac9a4b5d49f3bb604ec91cd8e6dae4ec5679ff8d094866130e47101e4e3168161008bb4f3e07ce21ea0f354fb5d53977876ac40	1	0	\\x000000010000000000800003c6e06fc367c40348966189bed62ff80b6a9c10fe48f22b6ec4988f26ef4c89e6fec569883e7a2d3bd59ae85cd1a211bd04e23a913e00e5d7e7bd8ad1a0492cd62fea6c7c6662b2bbfe5f106d5ce7c0bd5236b7def3ad2e34c9d8d217bc9653453346418879bfbab299ea3e95a834927276bbc4af7902428522819185e50a0891010001	\\xae00990461dea227382e1a42ee14f8c8e55437ff2c15eea415e447392ef4d0f6dc0682bc7d13f96e10f10bd41c08b1f5a6817fcc574d8370890e64a7baf9a709	1659892843000000	1660497643000000	1723569643000000	1818177643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
345	\\x4f4bbd27286eff7a3e149fbd7f6cfedfa3734e5b5c313d4a5a1188f809aeea33e223f67078a85161e0defd08a7ef4cba6e94f7bd5f5b6e7bd487e75ad463f695	1	0	\\x000000010000000000800003a1d42d7c1333a4c01b875feb42fa006118bfb86c816f590dfa396c976d8b78b010dc6680572a8910b9f61bac7d75b77a5e086e55c35d91d70ce1a3b52b9ea779766010825b8afa7906d8bbd097c77ff3af61ca5281bda60f5e4593e6fd4bd3b661c0edcf76c5fe4602698d323091daac40a71eff9d098a6e12f65e4a748a3241010001	\\x5844a230d77176809b1124fd5068eba699e104918c2ea1e4ab9aeb16575c907fe44d7cc225af6ee98f1db04b8d2417b6c34a5edfd9f1d7139d714c3279a98e0c	1673191843000000	1673796643000000	1736868643000000	1831476643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
346	\\x54c3f2ce6ff5b9ddcc4d8555029e51e2dde8b7ae2242b1829a91087545d69cdfc3f36d46198032c7ec6f7e75aac9515c454b37bf1c51f898452b15d1accdf9fc	1	0	\\x000000010000000000800003c643be6bb63d3b04daeffe829e9136a1b45df0ff98c6ad00f3f2fb1a0e76d01d4c80fe8c98014c25069fadc5ff48a82ccc0c766a89047605ae62b42fe30ef13aa44f7e7d3b1252a66f4bddf98bf8fbcbece06f4281ca8c063105df6ef87bf80c3f4b1444871365ae7e4a680379ca3e1938860f1a1ea64b36afc31c8764cd8937010001	\\x6b2e3d4429108970fe2c0eb25293724f981a340e6f4c3ba93b5f3ffdffd802f2746ab7745cd5ff5df7e56358a29ba951b71ecd711997b69e26ddd02de013a602	1661101843000000	1661706643000000	1724778643000000	1819386643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x567f8c3774d03263890cf3af01278b89fa1eed1eee1de8be12345c2b08df335f193dc6f0f05f33ed528919571800b97624aca1d4066772d3057072e0e32d871c	1	0	\\x000000010000000000800003e531b49505f5502915c95d7f4df9c4d431f5b0892375ec24ef9ff785a89c89d816c4ca4eee460decbdf9f920733cc7e8787a4f275229afd706e26c6ae2441c6767d1b1ff0934834f17de53313059b79810e176833992c9eb5e38ccf00b35949fbfd24ee5f5a74881cfe8f9b87782d23b38fc18f0891bd212bd344d948720f7b9010001	\\x41a9335bff5bcca0256611ba223a6378e8df690778245335b8e7b1c228df5fb0a54d9fcea5bf5ed00b18dcfae1cab54cce43ffc39a7f12c687200461e852ea0e	1681050343000000	1681655143000000	1744727143000000	1839335143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
348	\\x566750889d3137b10c2ccf03bfc69f705212a4d142ce2287cd1cec3b6c872296e35dc19942ebf709ffbf7077b7dce7552e58738c0454fcc5658ec48e41b56fbb	1	0	\\x000000010000000000800003af2a68465e05dd77921fc3744ddae475ca328a79f8af9ade0c6ddf38613fba3cb58dd96714bb0c78e349011cf54622b0bc25ac39ae886d0693a5d659fce02667ba0396113008dd76ec0fc76fd3f2fda6fe45431b2e99413156e945361a65777eba58775ced94f25b451a8655bb96e819f2722ab3322a75908ee5551f7c3ac189010001	\\x0b10746602b43b98b4dfb3db0e6da326b504173d87e4e745f48ec192f2261b042d4cbf5a27e267ad76eb03740819d4cde8feb408179d51e652afcd37d5511000	1671378343000000	1671983143000000	1735055143000000	1829663143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x58cf66613a9674c9e3f670b4ec0f6939e615e152047b85fb2010a479eda470d735a848d4286c6e05d9308337c867a912c7e532e8aea778c87529a1f2720869a9	1	0	\\x000000010000000000800003c5055f9703f2efbdf5a101019ff53f8155055cc2391837a2c63af27408049221ea3792c184e117f9cbdb14d729ab8247c6650ffb36cb63199ddae44ba537194079bbfd40a70ae94e7704dcc0e1aa3561298aed4f9041bb9ac28f944829fbab5f9f25528414d23ed69a0222ea53dc7a7cb354adb98f144854979b1697fb1eef2b010001	\\xaf398743afea1d5b434005c2b3f43acc4988bdfca1479bd43fc397b7fa33fda18c01d6fad5307872e6d9a7b14cf9c35dfdf9d5dd1957310ec8ffdb1cd60f2a05	1670169343000000	1670774143000000	1733846143000000	1828454143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x594bed069add9fd230dd438b077fa524e6a100e116f610b94842762140e14790220444a4246fefc038504fb6e70155db8f55d83c18484db07fd21ff662ca544d	1	0	\\x000000010000000000800003e433a3e613398406e417eaad0be535c2795233c18775f811b62519f957451a3cce3a9428a380df79eda356a9ac3848532f7ea8c3150afd5dd3c2cd3f1d128f01818fb3f29bdc76609cb21b11a3dd52432212acb7d74ec0101cd31747fb1353004acd90ddb3b6cdfc6cec67dc96416b436f44604342f2b720123dc8fa952889e3010001	\\xeba90985f4f3868a35d52191b0d4f76fb14c051b92f94b765cbedd2d8c21c593222c1605d1e854d87607ee9e38d322db4b8596c527c8110cb52b7235482d690c	1650825343000000	1651430143000000	1714502143000000	1809110143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x59e3a5e158d96c9cfa551dbd56d48bbbfdc461f5bbfc05eccd9ec6a2d0767a2c3c8840f50277ed4482ff60f575753c7545b6f7252937e7c891c5d3e85b78c6eb	1	0	\\x000000010000000000800003c71d820423127b10821ac7ef528a1049cee3618e8f9c703d0c5037aa1a0fe609b757917a04595e264e63e52f0c5d0cfe7f7eab0c0ef9a46476d5b6eca8e3b315fbde80394f8dcb43e3944e8c5a99b0a5abae3e1c79e816e81dc8f6779a69359561b461755b27c34e8efa6e3b7259f680df945cf0ac932bf45cab2914d6a52f3f010001	\\x5f18edc11914c3366b40ff7aad9785216c5cad090c55ed510c61ca698870e53a33e665b47e650b982e7aa2557633e2fea2571c665980f959c731baee5d10d100	1656870343000000	1657475143000000	1720547143000000	1815155143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x5adf68370d8f2dcf5f7b2e372f582d7da5e80e3d71fdfc3c621923791d269a9d6c99cde369d5f549ab90f39064056c03f6be444048daedf07472f134a57deed0	1	0	\\x000000010000000000800003fb2efca3de19fd16c2b4287827e7286d2253fb5b15c16d00627de60daecd4a15a227fa11d433d321800e05167140b2a177c8a90a50ce0805b92565f9452386397a721f67e3c83f398333cab05bb57c05075b0b195cc96cad4ae1659bc309b02eecc968de31c394b83a0fd22279476a9eee7974d7cf56e9364af73d5742961e95010001	\\x01d921abae2ad26767018899724a9e9083d70135d30705f8010cc7dbfcfdfb66e1bdd193c520850e0dfaed3d2d2e30382da49150b99573cef68015b6c05fee07	1659288343000000	1659893143000000	1722965143000000	1817573143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x5ad7509da6c6deb6f65e570dd4d0cebf4f9fcda9c6e9201747fc777b667eb0827a8156bed48ad437fd00a52415331bfb844a66ad38872cdc49c21a27ae0c0002	1	0	\\x000000010000000000800003bbf36f1de334eed7348c13a66eec47b34c15019832c4828f9d7c1b046d8110ecb99a4656cfcf5446e1c0796d67c6fb29260f233faf3a14cbb2520b53a763c4df87a17f00a9906e6e58427c390c002b9216987970536dd956ff6f5398ee427a2b9a61d2edcc00cdff5426943a25179956e8f7373cf3693eb327578ebe39cadc41010001	\\x83a4cec6a60921900f2efe2be5270a9e25749b5ea9340eb55ac682d717dd77135591e4ac0157cb4208eaeb33a58b4390e0612494ea3bb554b7876e965cc9f10e	1661101843000000	1661706643000000	1724778643000000	1819386643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x5d4bdfe94d888f9e1172048f1e76f298ead76d42308725c5f5ceca3e4cc298d85e8817e1b5229d2b23bebc6bdf00a65a6954ad63bbfc5fff06d138abf484ae12	1	0	\\x000000010000000000800003c9b32bdd246eb7dde5e4ce025ae5df873887406e204ec1af31aa45cef9afe14195131c46f2dee3152885aec9e4216ec1d5c2d92ba7ddfae5022c991d651a6976b9f3407a4e97221e507d1efc88b3c973e3bf692acd19a0e2723767e0b55043e5a06413e7a33180dd4a96cd1a3384647e4efc29199f7aa7ffa4596835131c208d010001	\\xa71d9b713ab532cbad4172a9ea7bf0f1ac9b823fe055b430224afef7750e1f6de4e5d5959340244019dce76b7511740931454cace4760f4d8370b90e5f5c540a	1675005343000000	1675610143000000	1738682143000000	1833290143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
355	\\x5d8f7f061bfe7a17cd606fca278c82957bfe6f3fdbecb348cf3b4294f581dad71af7b906e699f1b8a4b5c1a41193e58d1f5ee5e75372cede01d19dbad1754a84	1	0	\\x0000000100000000008000039d53a48fe63770f969b99a99ca7cf04483f874d60c8fd61debac0b634a1cf5ca35f434eb25f6f61594efbf3b90655dc7f06c41450147ac99812861007ff7b4f82dd199e00c71fb72111e7edf39f0d14ad0932ed2fec9478ee88625744cc4c3ffe56a368540458bbb99ffca57dbb48c0eaadaad90d9a29f58037941a4564ed8eb010001	\\xf99606b48419a04662a31a7715e6bc733e03ac2c25f7edff020a86ef0c076776c15e46453d20cddf0611825b7b4871f27e984574073c02cb542af3f6db087d09	1668355843000000	1668960643000000	1732032643000000	1826640643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x5ffb738f85c334faa3a987e1b976d87c844a5eb9d471076365c8962b5407a6232835c2a100bce8268bcd7b9fb6cca6812447478fd51439c8b7205c25efd76018	1	0	\\x000000010000000000800003d254127d17e14254b9213ae669b30068c89b4a8e088bb668f322fea5e2f7713f8d26c6893260c18a41c5083802b30966e287b5efa4ad56fc77d9d61b17e0437b023ba15e5d6ea9b87216b2a762b62f6d4937f838db2850be6cbac0c3f437789575c6f2c86f651016c87caa665dffad9ca13bc053b844d2eeaeb4c12dcf936891010001	\\xb68bc2eed7e7464dfefcf18d50b16dd37cb7bc5750108fef7e04ba4265e9832d5fdefbe70d6dd4ce342c0bc7c08fe0947f3ebf4eedb7a4fe70f5f2dd4bc99001	1681050343000000	1681655143000000	1744727143000000	1839335143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x5f3be4d4495ace9c8098281d7b0200dff4f3d299b32facb44ba8e4bce6407b5452766f31a7cd9931ccdd4c06e6a051d928fdbefdf220c6d2674836ac121c325e	1	0	\\x000000010000000000800003a0f81098ea8b4c0b0b3e8399f7b82dc4cc7e9d291e134fb223ab391fa94718865c4b8c1d47c13aa9b3f8ac8e5c0739d2557e1b48d3ad13ecd10cd48c0eb35d15da63d5fa6ed15db86ba340a12e49dbeb08b5be12f7bfc47710271443518b881b1dff132975c6feb2afab483222eaa2cdc87022f91a157ce244acfe9031244459010001	\\x1c394a390b26f71527f5ed6556b6f72d595f60a71acfcda578463f2403dd150a675766c9edc9d2d725a37c2fbd809e1d28c79ffbd22459eed505063a26e6a803	1664124343000000	1664729143000000	1727801143000000	1822409143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x61a71542293ada0932502cf2565c4f7f07dd6ac622126c8d22e4a7bdbd2e436b9dde5f17cf3689600c739b0e2a9cd7be30f606dad2995a36664599289949289c	1	0	\\x0000000100000000008000039eeb339a8f0c2202acaf2da2c6c2137b527198ac3f0836d2ab938ac8dd239b08262bb4f5564e73bc327378a4068347e5ce60f51ec40d9f3d6a23d0295337ed014dfb4c0fe907d6677129f18f9b0870ac30dea1314146580fedb5746c6fcdf60fe9fa95a616f100d6d5ca8d6d2a913c61138f8dea6ea59a450b28dfef3385e123010001	\\xab15d32f3a4635f351f20756f34f2bb2efd8ccf288f964adf12a93d4bd83141899c5742f715ebd2e9ed8d0552fb8b14a10e9e3a1700bcf603c56af637641fa0a	1650825343000000	1651430143000000	1714502143000000	1809110143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
359	\\x621790e4952239da6678ae43afba69a0edd6a10132b4186d81e011c9613ab8fc40c3ec3278ad68dfaaeb54a4f26177fe101b52ece5679a0618652c6c43cef2a8	1	0	\\x000000010000000000800003bde06dc890e471edfcff2f9ded2f678e3028e1c288616a35a077fc3dc07be4589b8220f29ffec9dc1d2c3e8b3a9f2fadd30755fdf52bb3500c8f1683558ef61f89bd70d4ba5ed20b395b8119584673606520fac1f6b5ce2943fe5a15ebec7453474724a390ef0f557c809d7c5e9d87194aa6943bd915be06c952574bcdb540a5010001	\\xe75c5762cbf46c86c5f82d4ff3c8bb264d42743b4fa39d7327aa5d041dc798238f8a4208e354ae608352a39e990ef0cf01a52966521837c469e3296615360900	1671378343000000	1671983143000000	1735055143000000	1829663143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
360	\\x625b285c3453206a007692097d8abcd4924ef593868b9e3d33418d2288f396f76b7087fd0235445543bfbbc5f426748bf43a39e42561ee028259e4b7727dddc6	1	0	\\x000000010000000000800003bc9ebfab2a26daeed754f0ac5318c47f5620fb3c3e11508ccbeb5877558b376662d32b9eb08ba7d14047daf86ab5ba50ef1c9420bc4000d34d005a9855b09aeefdfacf382a1970967d60fea5a668ebbb99a5d9337cc3b5f8117545f20b7b1126822c87dc81ce7892aed3cbca2fc85d1d7a7d878209f36b70e0daf149785bad1d010001	\\x6fee05aa808e0ff55bba4bb0db963004fd6c54d48ff483f652a2bc70f045e3b0f5d879fcad691b50ceb5dc91887980c362660516ef2a29c406d774f36b6dac04	1661706343000000	1662311143000000	1725383143000000	1819991143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
361	\\x642fc66d8bbadcb7a3e1cf56e6ed9450f4986e7dd550950f2cac06ef6dc77ef21da09fbc434180ee7fe7bb75c8f36ff2551a3a7f5b211706130363cd1f53e802	1	0	\\x000000010000000000800003cf9f84aeca32aeb3f0a941f1944c9cf5da03ce3d43becf4fedded4dadd992cb9ad6ed9c0e95c9f2babf7b46be443721ead6fe4c36940589466b738622fadd586b3a86416d9ffa6fc986669e7efb4b29ef987e5ad49f0a11ad8856960569be20a254b9f170acaa52e2fa8c2601a8f9acf32473f1bdf47ac5e0e3574af2700b693010001	\\xdb1930ad14c7b3bd869e1e180a66b79464e1f89c026880912229f94267bb792c5b6f1f1965701a37099af7904af8c0d5bae48e7be44733edc0f872035bce5402	1673796343000000	1674401143000000	1737473143000000	1832081143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x66bbbf16e38eb4138cac13fe8257a762e8ea8a9b02474b3c556d22ebcfcea0cd6a9ce6702b9d4e22da409512a7cbd5291b157f78e75f9ed22ccb6f707f02b1e1	1	0	\\x000000010000000000800003c6f65e1472f4f995256a019c17a6742de6f0c435f27643717841b2d2c4807a85b655d61e16a204e910f295d400ae113cf75ce90b8bd806ab8fb45afc3a0260c885bf33c8687ee44589225739adc4617987796ff5e909c9bf0d56380bbb67c0e36833f58a83a008e2f54c2ee112c188fa220b96799bcd1005deb4d1753be6f59f010001	\\x07baac20dbbcb996b0044b39c99a5e979e3fd66843a2d4931e57f629b9cc9e4f59060597d65312c85a64a6cf6d774ae8549acd4b8132ab3ab1b5ee34a1e4f40c	1658079343000000	1658684143000000	1721756143000000	1816364143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x6a3baf2cecafaf37267bf2b9d038f42b7ede7281477558caa5616da94027251ed75fd6675efedad40a857022cf98234cab4bbb21d0a01ef2911e0009bb26b5dc	1	0	\\x000000010000000000800003dc9493536bbe02256153de4b0dcfd9eec3d9f27966ae5dd80b298f7320621a34933ec6267973f39f4551e15d5ac5f401db10fb09cc1e4f15169890ba6c904dd516722811c8d21d83372eb54ecf4952104a71aa29cd14d29ca890297b69f8931ef504c112fba57cf464bd729ff80e42407a1dee549f0678190e7a0bf6c5394b55010001	\\xadccb3e1b021d368dfb7fc811df7e88c4992d48e80238e1ea1b32065f6c62d490a5130aeca07a1ed6b24838a2a4c932ec0cae5a033538ee49ee70c733c36e80d	1665937843000000	1666542643000000	1729614643000000	1824222643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
364	\\x6af736aa043b651f9fa1baacbaa44a908da87a5fcdb788396439071fd805fe89933f4f6eb181b0561c6dffdf6e65f3611224d799600165d39626116cff3e0048	1	0	\\x000000010000000000800003c43f885ff041915e8e3649964e02c88067051e8e721a3864c5ee49fd7913113796f4822092ccbb6c55ba497fe1b56b7d1ae17f98e1ab2027250ea7420442405d8d1a231b970d78e8d7f6a9981ae009a05606f4e7bfd88b6c867d37a277671eb61dca1f66320b4b3dbc2519bbadab1314d5f462779926f200add343f21ea034e7010001	\\xce16227fc6f3c311f637e2c96235c35e04c8263e36d2410c6b61c9e728e3879e913a2db16c33ad1789715344b818796e038c5ed3ec8d69964db97b6bbe562d0e	1652034343000000	1652639143000000	1715711143000000	1810319143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
365	\\x6d83b796deccffdbb50f086c126681e27b753485ce3888fba63a577c923b3fccbebd69cca98ce3a66867e1864a4a3bb8a690b13b968fe558b684d66192c1f872	1	0	\\x000000010000000000800003ad5584f0cdcad8e49488bb7c9820c36956e84ea147a6cdf11e6aeb6c3b17a7a8ed46cbe658ba92e441e447a1fea5d11d2eced4b6a69faf6064733f1a62f79bad5e9e5ee78f26503e669d6c9071d89d273e0ba8fb767c11a143e145eee367995087550b6e62c152b92e5a9391f835a1359e014aac7552ae93337067c24ddeb697010001	\\x22100ed35e68b9454e04872ab0760566cd8f5a50aac08493c96b3045697131024a6ad4372bf0b47b7c33db8bacf4bf251c19bbc4a703c88711d288b470a2370c	1662915343000000	1663520143000000	1726592143000000	1821200143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x6fcff0435beba46e0faeac34731950475edb69cf379b06cf18f61cbfa384370c78622a4b15e686adc5e6e3c892b29d68476a40aa53a2977b3c29ba41de720c7f	1	0	\\x000000010000000000800003be9dbd598b5f8e75b1df2e6c5323f1a96065e7e16fbcc56fb8ad6963ccd28bd571057b9dec35ca73b2651a4ee2e914d9b9fa8f8d149895bc042f4962275ca251914179b803ac641f5d566e4e75cb4fd2b834bed50638d3a4dbd83c83caed9ec1bf3782dde4ae51aaed1d1a21e6f7807c060e81dc3a06d1dd73bd8facdab00d85010001	\\xc7753d883d727a51c1400513abe5ab7ef3fa0775a6e7777d2af360216a1519eca10db6fc6a4fdcff9854428079388dbce29751e57fda057cbf23ac6b9c857307	1652034343000000	1652639143000000	1715711143000000	1810319143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x739f2f3a37572603586118aea380d20fe996e2fb78ccc9bef479351e6e2919a5dc5e92641c3851d93025d48c3e81a9386727f028b7ae447692e0e3a2cbd3fab6	1	0	\\x000000010000000000800003ab1ac6a39e2fc8c9d453e8959bbbc1959511e5b0a8b7aeb7101233f874d88e173430a8107f09fc15e65e32161a6d2e5693b98633a89e20275877b1958dee2879b3b25d9f79c8422e02fac564395950d1320262340ddf445244dd4ec3dac7b7011a8096898bdd44e8d1fc9f7aa61505d21aff5067375bbc5baf60715eb127bfab010001	\\x9a3a448c5e96e1b3652e883c9f6c3fefd4817cea79f382756cb30594586af8f5393025277fbb2ec22a91ca6596c447e7597db28ad85d83c983cc072a275fc509	1671982843000000	1672587643000000	1735659643000000	1830267643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x7743d9ff061d50bda78f0170dd7a00c49ec977bebab956fe830a5a2190b758f1f75eb395e8bb1d3b999079149c2491458bb7023eef212166ead3226dfcbeb365	1	0	\\x000000010000000000800003c8941192a4e59ae55b71d83b466edd6523427710f1d51c60e58589be360734a28d9a6aa240fdc7240a295277e197c5b1e6330f5118ed951b501d4afb99642235d786637df68896295b1345a828abd051ef95e96b1104aac815eec53a1ee4381de69fc6479f09b88e74b59cecf3b6fe9a7917d53f06f0c72cafbf82dfe2afed7b010001	\\x38d6e23d9f17080fe32d3d261a191b1b1b9bb21fff9c099e73bf1003de1e187837d617c3230fb8eeb2a687612d6ed13c551b1ac452765d38ffbbcd0bb67e6208	1660497343000000	1661102143000000	1724174143000000	1818782143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
369	\\x78537f242f4fe823424ae7f30128e244476bb341741e728ae8aa9c18b49038d44c2b057413f709b8e468e1b27c5e9fbf56bea85b579d1bc3d3d71a8560e874d9	1	0	\\x000000010000000000800003acad6b5671d36e77ed4265f4c30e3f51094f1fba0bc9edb9d1249beb4e3e336723b99baee53d3f28e4a73ac3ebeaefaa4bc26039b304e8b74719997d49a112dab20492f4fe27084a8478d87a1871846abe618feef7cf4cbe65a1e7e36d1515afa5c78d3282437c369e95968585636624d3981842fb2bd97d96d528d021190803010001	\\x769339524051d24d6f664982856628caa4b6fec69c4643e18f3e1853bd4688f820bc500c070f7b0aa8e38702b663829aef8d4450fde2def3c5ea10b3470acb0a	1679236843000000	1679841643000000	1742913643000000	1837521643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
370	\\x7c8fb00144e9335b4d73866488ba5a3902872f1e387c876bdabac2bbe1309e425c50785a9c49c9818d6d4d82010611c19cd0a5355635abaf2a86963fb8ff462c	1	0	\\x000000010000000000800003b7e7c54dadb4cc9bcb1f775f91d12032eb3124a243d3ff184d902673abc43131c3bf7f0c6318b610fc4adad2235e611e77ce4310c2a4fb469a0d2e939254f5cdc4d8dab72ed3e07d6a9619e1a683be62bb546b0deeb17236919d6e4ee781f1d23c68d4f8fb1c9e3d8ab950de449bade0f4b7a9d13c829286406cf7fba1e6f33f010001	\\x8be29f32078cc344ac3d550c1789400ea6fd63e60b0e1ab838365a8534c44963b441ee245992077ea89d20aaf14ad9bbb4e648d133e8e3a9c7c0caad31d6a504	1670773843000000	1671378643000000	1734450643000000	1829058643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x7c1f80c79aab99058e7b296c934f09f5d2db5cd2d690400355e26f6f596dd562a0d519d88fb88ef07234c736b4e14fdefa026c7cd8a29f73c9a127c73857993b	1	0	\\x000000010000000000800003b4039753019c5072a56b7580f286945c96928001e230c5e634cefac7a5639333076c67ab8ed40158251c651a5d7a5c92e1fd966f3a95ab9bcaad9e008b8c108694caec7c389172fef328c1d8d737beebd32e25490544db3639e173f78f4c28f8f3df263d03da6131f4c7a0584bc90877558a379314a546464bcfe1d681f40b3d010001	\\xd5015412e6c3c11e1f9372ae3dd1f6a64aa851c3807618c5923aa805ab6a7f5b250dcd8028758a5c2551e66067cbfbc13729b9817074a39e45df532477fd160a	1661706343000000	1662311143000000	1725383143000000	1819991143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x7cbb7c4295a1cdde329b5cf7a1f8431d122a078908eacae10124c59a115d82c9d7b910f3687f938b7d77af960b3d0832eaf72a9172104a7b11083a609150c1f1	1	0	\\x000000010000000000800003cb428d91d1e4633efd7d6da5e59926d88d0ad2e43019e429ae22f435fa17c83694aa531b8b218a0cb352ae7fdc68f134d7fbf5bb8e5e16459f94ff6a6e38fd5f77b0a6cd74b4fb65e3d208cb0b11983677fe397f240a540fbd4180613737520ae21119ae3cd783a4d1c01a11567a4064580fe34be61ac11c495cf515da2b25fb010001	\\xd180440bf39c127980f35ca281531c7307a7a4ff0de6bbd68ab375f65da3a3e3e0d5d911ffb71be1445e9ff71ea93b389130670c04c88ad5ab83c0ff900ea70f	1675609843000000	1676214643000000	1739286643000000	1833894643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
373	\\x7feb2fd36ba0e4f462a2c9b1add378a37ac36b4d249ec2f07152328cfc5c69cef49d1e39d9de64bdaef5c8342c61513b2c5f51874b155aaac550fa05fc350df9	1	0	\\x000000010000000000800003b839e758abf2b4dabd39c34ca3827fc770b83f4568a9caa524e6de3054ab937277ca00cd82d084756b05da1ecc71b2c034311a40a897cf2dd39e0761b3294e280646e97bc6bcfcb40fc988813d7a659d6bcac3802bbe39453242aa46cb3c3cde73ed5157feba55de91d45e53d7488a13e7e7d32ea1a2d74a645c6db2eb785055010001	\\x4877f9d23eca4d044026086931d25fe47f1e1da2d6f2c2e6b3f1b6f7489f45243dd11a56751431ee5e8248898bd4d1a5f621e481fa05ca9f4f76f96ad8bdd501	1656265843000000	1656870643000000	1719942643000000	1814550643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x7f5f8bbdaaad7c4d79eb2b45c9082cec3c36c545397529af34cbf78125027125ce3f4def5fb6727d52a3edfddac643983fadb75aab2e30f5061fb49f34b0d66f	1	0	\\x000000010000000000800003cd620c9f52f6edbab26db2eaa5d5264d5496b220b57cd717d364c18101f0253e8b14fbad6eb93c45910e7d984f59760f7821bb0339a61cae0f94f41dce730f3c291be1c00ded2b83a295d550342bbe0032243c7e5e0f4ba9eb2077d8a93ad98223f22c2d22c1832f82d4a157cb0a1f971c7efe57bd8203fd2949a73ed4a81cbf010001	\\xe87c98b92e7820d57e1d1aa4bb1184f4f5c61d8ad211ad21d68269a987ad14172c73b715b56739c6323d729e6af34cb1966e3c741a515d70c0c0815c9a608a0b	1661706343000000	1662311143000000	1725383143000000	1819991143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
375	\\x82cfbf7fb69b9a6c4ad5c615b4ef1c90aa1f22aec100c894cbadb9949f51bbb1da0d9ddceb0b10e282fd27a352e45f89a080ce10799c663f40d7e4211606e051	1	0	\\x000000010000000000800003db6fa1470d025e4d2928325b2c948cb9e803e41d71aad347b56315adfa79f67e70b72e4f618bbad3f3872ac4a486c4099b8d1a4eca86a03579fb5578429de89e8b4862d9188bc21b933ef1d74e1952091aedb934b2972df0ac741ecc0650e3a2cbe97bdd49ab15f3eda9a461d98a5da27337e88e2e1f811ee8a5bb644b595c09010001	\\xbc9479afe5910a56a0212ce01c3b8cc965b3c7cf65e6a900e6f6dff114a2b04491aa98d98b8a1083d0337ce4534e99e4259d5b861c53abc6f6f830e983a12403	1651429843000000	1652034643000000	1715106643000000	1809714643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
376	\\x86271e5badfa02065b47d18e9e4d3d8cb5b40b1fb85edc90a4a5801ee6b6dc43361fceb9222fabe06eacd6570aac845c5be8e700f5a62e03c006a4e7454fd006	1	0	\\x0000000100000000008000039df4223bbd0e78fff6575fa059d9817f2fa416fd27b5919965f4d2bf58ebae294685bee36458f8ab2fe1352410a716ef53da890da7d9dc2707910172de92568e50fb7c1f1c9f0434a512b0c2dc5290ed3a6fb55b678e6f161ae8fd2b8c39e8463fb569a06521b2e3556dfb9f8c9328026c3c90888d3e83a3d8a999a8ddbac2eb010001	\\x9daa74a440481fcfd10e2129da081f268cdfc472a754fbf7cceea5c9cc33922e1390ce91ea949718f9f15ef91dfd6395bfc6c7823875b3ddc0f68b086e0ad40a	1662310843000000	1662915643000000	1725987643000000	1820595643000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x872f95ac053e72f744249110a421dda4abab988ad0f63fbd9f851b882d3184ad448f27d9f6b7f23a148401b3aa23e1605f708c554660e430995165eeeae2e648	1	0	\\x000000010000000000800003ea49afef762c7b64aba7056921f99c1356deea368eba5b1d2443bdc0a14353ae93e715a1e3a1901f055f3b7af281e33c632d476dfcfa268f15545fc81fc33e92321c732ddf12074492ea43de8c6c5c34fec42f9fe0991eb469b7bf5fae93b2a9d261d1cb0da0d73e893a1c4da3a43854ef2224378558f2adf7c40d5c69a38cbb010001	\\x6489de5f5ac4f32f3be45688434f72a436fa9042cc4fe82518f2b7a9bec235cd122f223862f76dfa215929575ced57b619eb5b526b2c2988e06df073d1743e0f	1672587343000000	1673192143000000	1736264143000000	1830872143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x899787ef612ed95aa18ea01ad580b9954269b466bbad1249abd9424bec2212c927fc38697402a97271e0b2974ccb8ce058d032ce700555bbace70864dab166bb	1	0	\\x000000010000000000800003ba98ab625698153579953e309a5654edf6b4687ee22918392a8e91028be60ddfce9a83f01e152533a6d51a4db3cee6691afa59ae869b5f5b0e9984d10e4c90e094a9de073d05f28d3e9047a47d23b27ecb79fffcfd7f4aa1f1bf545f983671b54636f61ba324e3bd8c81681cb4f1c792d869043feead6d1f7c38818372e6c20d010001	\\x12b4fb3f473d9ed3d4a6a312cdf41b89f48376cc52fd9cc93ef03e86537565e7e9b1220a6b76b1aa4006e9dfa415882674ffc843281d51c17af3a77fc8645a05	1658683843000000	1659288643000000	1722360643000000	1816968643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
379	\\x8cd33da119f302f7bd24e0f1052f4183975a760f8ce084fa1334c2d2449816540da238f64a7e3063ea96cd629f3e468afe52a3b80bd49ff853e0d3de2c338063	1	0	\\x000000010000000000800003db6b9f16459e0fdb337faa5f57ed6a0622a3e4bdaa6d394b1411cfbfe2203aec4c120eecd4549b2a1deafb6de90d9871ffc941754e7cc55ad74669528b0c9c5df3411054b040288d8816491c10b72a302e8e035408567989a57f67955b0b068bec877cbe36c27153de311f6558e675a86b2b478a2a2b0ef1a006a2e190983125010001	\\x8aa7d4536a64bb8cf8e76d17e9ccdae1d1dacb435f2212a2221daa0337043a65750fe99b7961f0738ef6773b18892967fd9fef1c8d8d4e159a87e92990d7ea07	1654452343000000	1655057143000000	1718129143000000	1812737143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\x8ef7013714f85136a1aa306cc7cfd6310eae4769c04bf2fc4384df3b85612c32c4cf7ed26bd77c3a8c10ccab218bb6182a242858e369a80ea9d784e338f916fa	1	0	\\x000000010000000000800003ce411a9f9ce66d5269af892ec78701300e1fccf0f1157f0a8f7b1495b72df6c6f86c217936feb9707656352451cfac26251d6670bf84d234895fd13943a95c4196f6e147e41b4f6af49b96ef63c52f3cb4ac44a31fae27314458596e5eba0d508b2ed65a44009ee53494d49e5d31a344b2cf3a307582801164b4896f0352a6d9010001	\\x730c4d27359bf521861d4e35992bbb86fec0b96162cc55ba9eed140cafef08e461f810caf8aec29f14e0b0b74d26323e478709bea3255f35f98a374a416b3505	1676214343000000	1676819143000000	1739891143000000	1834499143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x91d3fcbd4b6f61643651c3e7de78330917a40172a4bce382d5348a5f3d96f53ed365c36e044a6a1b02914b9b6f56d4dd5e1a26d56f4a017203d854b904de81d3	1	0	\\x000000010000000000800003d42dc988ca4fd96efe6114e92c5174db28a1c7afe19568db8556e1d438391c86982de3cd1097045fb6982470efbb653bc69215934a0c46839dae9b04c7278a67c89ac959e1993e11f0cb9003591548394775175610d7308e8e43131ecddce122c793043671d195b3c9b8650406f012939b61d41b5de02e631f4078145c7db857010001	\\xb0fbe6798cdb4074f92fe7bd1f77feeb37f142390ab0dfe960782000a32e2cc8f6044f80ac9076f9ede35a86fcdb912afc9221b34ce45dd3a36305749aaf7906	1673191843000000	1673796643000000	1736868643000000	1831476643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\x950fd165822554920d8f7375fe6988c9cd0c17fa03243b1bb46795e6187028cc2c43a22716246d05e0438a27155190bf4dbe5b72a81411b7e2bba037035af88c	1	0	\\x000000010000000000800003d5392751481793dd8d87a8df290ba2a0d49246b8620728049e281fc3ab3cb3d05f255fedacb6763b883df5939c4be07ae9d770ce8cb386a2a339f93b096081c1fcfc4a3160f63234e9f3511535e3210e4db4fbe64f256d979517953ced85fdec785c57ccbb3556bec2f73080dc7dce44499782e78a9ac6a4f7161331562f3245010001	\\x598be836063f9283849aea6ea03ed2c7e9e57786b4992ea8ec9a65c48aa35048d44490e4509a7ba59e3958f56e3221a8620fc0e67097db0a1770191d32589d0c	1660497343000000	1661102143000000	1724174143000000	1818782143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\x96c7a1653e90d2023300e067e276e9c48e70c4f230d8c43cd450e2c24dccf1c3684d20555988409e80b72721463106de9f49f68c83c0379478eaa80cd12013cd	1	0	\\x000000010000000000800003cf51bf7074fcc500a74e3e60f980d5373e2b191ac393008e9227b4dac4de47a4bce61ceff55de504527b8c33bf65758fc0774953813d8de9feb619e00bf7fc25aff36600faf51de8602ab92920cbe12db47d28ad4b91f4ff724fe596c53f2f6d952ab193c2414c29251aac30401872c57cbc19a47ce1d68c6e51a13b8fec6845010001	\\x68a5f8b84cf24083683d4ab71303b1e1fc731f0a4ddaaaea1141cdba0f406680088cdb82636f9db2e042daf80b67d068fa8c56ef0faffd8c3bb039796fbad203	1676214343000000	1676819143000000	1739891143000000	1834499143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x9753b49c5e37cc7ae85a7ebce0d1ba5fd31e6975e2b74a8a12edb6f0a71b1e54d43d56a094cd5d15b217d269cd2344deebf44e2ebd653debd91a99b0f16d6c0d	1	0	\\x000000010000000000800003bc641b29dbf68fe1eb0a0419fac4f66170688b266fdee4dd41aaede2df4065b092a29d2defd355fd7472650c7c1f956ec3e868a776afc70d3a84c8af24e071c2a1982036a8a4cfc417ddb2b3c4e55a11051673de26bfee80a7a0cd95c8f4aa80695bda61075ba417a3cf45f3477c7c925dfdb437efa47e6105c88d241cf148d9010001	\\x30b8170c6f13b08d995ccf808652994cc1369ab7355052673fe9dbbe59a41da59ffc3c09f74208a5c5ddd73a0ee8166686ced9fc63faf7a04498295bba851007	1669564843000000	1670169643000000	1733241643000000	1827849643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
385	\\x97ef9e5792d6361db756c8b05abf919b2431d7ba0473d627e997f4b65cbd3e04c25f16c5f7601835817bcff4d40e0e2f477b92938a5b151b760ece7acc50ec4d	1	0	\\x000000010000000000800003a70f7d490d48cdac5944016e07dfd92a52b7aada1ffc83ec351e334fbf662a0fe7ad5cfab8d58205c1c17ebb3dd04e449b923c9358da2ec9c96c4da3537f71b6ed9b8513e3d1059f288e9540eceb335d3e42c8bda6b2681812fe96067f01ea2fee9f84f0e0a5771dc5cae83c5faae08e90d869ee45cf27283346788a2f410fe1010001	\\xa1b0156d4a8505df0b9e222d3939984cba4b1844c0edf48816bd8da93ee0028955e81c5f8059b0e77fa05155503c3238fcdd8f827ccc639cac15ec5ecc496b09	1679236843000000	1679841643000000	1742913643000000	1837521643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\x9c6f0912fc8610bfbb3fad7a8ec05189fa8872226ad06e7d96b172308b4a7669c382157a025bdebce09d1dc8bab7e6ff43ab5ce7bfca7c1a7c578bfe878e16ba	1	0	\\x000000010000000000800003de4e421c6026c76b0b076acffe09461f259c4f1d7d06c5934c753089fae47f8b81cfa1a4c14e155edda2b4286b2f7c3f7d19fdf372613fbac10cda936240f5796863092d11046f7793446b80c1b671c6e78886aa7241e36da0078b7fe94f6a0d288493b392841933115a9b9332aa723fcdfae84b1aa52e7f354f46eefb28fb57010001	\\xea640cb3e026836aab5dba2e6cc994a5ca6a48a548531b04f1dbb864ff8b3010e5325c53ca017e458a4e4be4a29fe13a47782fd68326c2a8c1ab30eb4d08750e	1664124343000000	1664729143000000	1727801143000000	1822409143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
387	\\xa1b755f742815ec5da73c52c674fb9520e5f3512c5294d2f6df8e5953771b8e05c0dde8e5d85aa0ba4725c74a355dcf8d85fa77ac058472963723b9846aeb842	1	0	\\x000000010000000000800003ab66038d5782679a17060b8aedf8d709dea1cd8c51c330002f25e6c32376859c85e2a4c2d158214b728f5161dcaa5724d93ec480cf0f92ab904852c5771f6af1c3c134c8dd9465a3f44d0b486f03a85e42cf6c15e09003d94d3aca6594ce60096be109a12ad77e023a6ed9aa571b22714bb42127b92f9222bd42e81bf81bdc39010001	\\x5433d774570535e48f0bdc73fd1cd49a31c54aae25e36303d58554d4ce3053ffe0cd0e1bd25528659167b70ce8bf7976d0426d9385ac5cedfc5233a82af7550e	1655661343000000	1656266143000000	1719338143000000	1813946143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\xa4170ff5229561fdc6bcc65cac1015fec26e4412a953bde4b797eb2723d7680df94863b431da46db9a052d3dd8be2fc717c110644fca5ac0ce9ed71c28a01edb	1	0	\\x000000010000000000800003c07e02e269440fd1f1d5c635498c06d5d74936cb910960b1e640c25ca399fbbfdbf164f87c8f9ac44d38388b395cb4cf7fb9f78b21481df94ece1aed233042bb83744b1776f42779e0bb423e835cf58396a1e9c0b4ec94f81d30c8af86c1b2d45938910a65cc3787a4f3d794d8dba4bbf53ed9d5919be8c62c69e3e17829537b010001	\\xc69c4c50cef86a21ea60c4f9154da85d7db399b7fcbe9d1f4baa25cfe5db3163dc6383448aa30f4cddf7bde75fd63ce4f8ccdc95d8fce7cb03ea61eee480b606	1653243343000000	1653848143000000	1716920143000000	1811528143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xa4b7097dcad4cc05d2993e122b0afeec04a9bbda7cbe2b5c22f11a716033c10d06a3f365276c3c1f5815344d931cc8a1fbb88a3536342e7ab4ebbed0c61cae6b	1	0	\\x000000010000000000800003e10257c60dfd983fe9a687e6178f319620f5ef879de581d525a2ffa1356824c4e46bf61898aa08fcecbe9b8c231351cd525232ba9dd303aedf27901a6774527e2bc0cbb17ca57bc3f43c927c8e77f3dd7324d35897bd8071d4f554a1d3529423efa9c4a9c4a27553fff19975f66e5d14a79c3efab7402db7fef9ab268b0375d9010001	\\xf17cfeddb02423bd174736142727edec446bcaff419a1eaf781493dd1f89f704302b7e3e083ef431fff62e458a4538a903b97342913028e630ad27fe1d6f2f05	1661101843000000	1661706643000000	1724778643000000	1819386643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
390	\\xa72f358db1502dc7801aa06f5c40bdecf21df403805ef66352d5225ff8d53d216cc3f148b040260decd3bb67ab3a3e63096bc204925c03eac8db9a4b5febc465	1	0	\\x000000010000000000800003d63be4125a6a89a4ca6209400c6a86ca4b9874dcb0b24a75ffd7635a35fddaad7a2d52022ebf1e06af82880588efe2feda570a40183981ae1e96c68925edcbeb83ce00fdd6ba6938b42fa1d8984b121e83c81301fc6d71682ddcb645cebfc91d11c8891ed98ca852f72f14d1a3d3eeba7fe88ccdee4bbdc1c8bf294cf721f1d1010001	\\xea09ba24700469ca7cc681a5866bf7547bbc412225672ef334f75a8b601b23a8af83b8b747ae890f6733065776d7db55411309fdc0e8f172a7a60fb55dad5504	1679841343000000	1680446143000000	1743518143000000	1838126143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xa9433dc216eec41a654ca0bd0b4ffb6ccf195ec3199f73c344a0d2a5fee6bf6705bcf3efb11975b6feea847f003eb1afba8954d6f63432c50e8a35c28af0af96	1	0	\\x000000010000000000800003a5b379c56b984952534d0b18776160be638073e5b54a2205b5dde3d1f6cd78ca6ac38a2c3760296743042d51b50cd303c10adeec32b74374e74f93deb5aeb9a9abf057e4c90342d4f59fe8a283d9d08e3103950a6a8ad083a1b26b9a3bf19813344de1b144889ab5e53b9a6aa985c4afffe597235b4d168756ac5d0dddebab93010001	\\xeb9d45dbfb887fe560016d6fe2d1ebfc67a699f97c92857beb81a377b53bc9a11f940d287277912b7c289eec15ae020f83946900afaa98a2229c14b2fa2ffd09	1658683843000000	1659288643000000	1722360643000000	1816968643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xa9637fc1ac9a4347235072617af937b9e0525caf2ba7029a68cd0d07b243b3370c2a8b233686f769d8fe5ea3235f8d3433a9c394bbed617427ed70c6f62475dd	1	0	\\x000000010000000000800003b6964fa5ba448315b796d313e955d61356d7b2ccd80dfa035037dfbe85e824077a511c964e5904b58ea169f6378feea2d8c5dddf60bcefd985d3d27713a5cb0e914e63820ecaf0335c5090aa2dfc88de531bb1d586cb35d8b15a00d9134de371166af0cb1c27a62f8e3184c50454e6fb3aeae04af040d611e8da838ebc0e8ff5010001	\\x76d49c50284e2292d869ce46c767edea6612c70ecac128ec998f6200c41c66186cf19ef75d54bf57312728a6ad710a150038c82435c1545d293ec1f7c4743a05	1670773843000000	1671378643000000	1734450643000000	1829058643000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
393	\\xae0b17dfc2e4742c3a1763cf215eb567d97c4d77159a78877c05490533e27e7e26e7e6524ba5ce11e4b16ff85bb5864e2da5c10a42f0cc7fdf5575cc78ddb80c	1	0	\\x000000010000000000800003e38302e8f5252f916f7b9b9d0681d1b6240a503a12c95d66dae103850f705e285217a15d45b7e76510d2514d1424cd18ea1084badbfa7c309a30e1972ae48bae1e07e90e89f08de9de9c1349652235c1bf123e031c35c0bb9faa1e07ae1f8b0ce4276b6a905d9db433d2d7e84336dce49ad39f85d386a123cf5dd0d62520e5d1010001	\\x46b22a04d7517c93b151a8988b234648b4c59932000970d69908e841b30b376d40218e9b22c20937ff35539b0afd449ac61a72deb5d4ded6ccd86bac3961760f	1679841343000000	1680446143000000	1743518143000000	1838126143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
394	\\xb32717a1baf2a3f33614752b2e8aff54edf730628182d5637ae22f1007ba1e2b6a389d6b16e9ceff8f278ffcfc2fbc8588800b8513d84984f087849dbfa5eee6	1	0	\\x000000010000000000800003b8f50365c7dee6067d992b4d5da84820aa443f6b0468cf97664877bb30c9029b77b3353d2dd982154854f2d0ab1526e3a0a24608a136bac1788c7aba0724a8e6f258557340e95b4e61169a6be7ba5008a673c0be418bb0c9a808084e20ee71d88164430789d6f131ab889af8e050f14489e5b7aa75179305ca1894d1365446cd010001	\\xee8f8f1499830dae55ab3752bc40e31597dab64e8f12c5f4151dd7607f32effd7786d0f0e246b5ae0d024cd8124d7464e15021507a301ccfe90c5240b8725803	1673796343000000	1674401143000000	1737473143000000	1832081143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xb54f5486e1d40c676c0b915dbb55fd3dc10f522c7a4849ba2ae0337a16fd1bd67f9ccc031ac4add9fafc6b453020ec3692de761209083ac8f236c0a6dc9008c7	1	0	\\x000000010000000000800003ac801e90b8d8bfdc4e55e37a5ee5e56a5dee5b5216c7c626ef87bb3df19427cbcb98a61a84014f2e0143d7bcbd3f7b55ba66d31bae83666a6f9a2edff246333ae475e16759f6e6097a6e5d64ecbdd3d8c64b86d989bd1218ec16a7bc33042d4a3aab3820d2b150fad35b0f03f10a0ef712440379e76efda6f97a846cea603eab010001	\\x3443e59261c2a63c698bc4a13e95ae94dc943cd8d83afb17d10517a0282f399e0a78452b77d0071ec4463dd9c92a3076f363df4e6a20c28d4323c35748367c07	1663519843000000	1664124643000000	1727196643000000	1821804643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xb5972bc1640167cc85bc5e4768f939d07ee2b55c313bf33f9260c16ca30e04708332ba7ce7f2db488d593439b3010a6d66a262e0941a0d0f278cf4cbcd849a81	1	0	\\x000000010000000000800003bfc20c27aa80e3566e6b497056ccd6b97f73210b084a87fb01c2f148e2bd7cfb2ed8775207c45407a3168dac1c7788f6e9b55acd5b5f52884dc271e734f928a42090fda8f0c85233861908fb2467b4b8b6892f1de89a50a0e7022a44a2dc73b49797b995eee3e5594c02434a825c2021480e7825205213f6f8c69da8e99f13a1010001	\\x8d4a30834d17a0312e42c8fbf3b296b88e63fd7e55415157fe2ba7ef00327bec25bf025f5314bbee4ef20a71c9a2df76ff164bede247bff5758a969ea2449102	1658683843000000	1659288643000000	1722360643000000	1816968643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xb51f619edc3d45b21b8a7dc1edfdcffa448b542b3d6c6e53d6012f65db394e9217104a4887aa815874d3433920f8b31947cd4a6237b8b1d7b84f776741b62da9	1	0	\\x000000010000000000800003b24c590dc884501225eb156f477e23c57b486f5349fc721c2777f4d89ec87c3ff58877bfa53a56db0885ea473f01cd34694565544ec2e40e1b6cebf1426e68788befb68b55d67a9de9dbb8d921b4b25d4b9613690191d68064a9a30ee2fba7aed96c393f622c2fe3b2949f3129ea4b4fb228e642a4f47e9b55a6f2f9c74f0b53010001	\\x6e1f9c2d2ea1583a734502f5efe7954709335ec02a7763d52e8dc3aebb538cea43233c55b80184244079747f406129c3ee3315cf47c98e892cd1d479ced8700c	1675005343000000	1675610143000000	1738682143000000	1833290143000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
398	\\xb7b36a94c462d15f2c4b9e1c7ecc4282e71883ff798932c26b0d839d21559d4ddf31cabb835ff32a3c565f9dfb6820f1d9378f4393464550ba9fcc8b10e0b2d0	1	0	\\x000000010000000000800003a30f78a1a27cd13403c9543b766dce092c5eec63e7d747e522cc1cebb5f30021d50fd88c88211b294f7bf17e9c3e7459a9071edf6c4d74d23ef105a2510fded2f5364b96fd489eb01448e4f7350d773ae857d8610fadf778ad97ffcac582bdadb566ee4357e90e095f36120fb8826862061660ea8bb34c70c1a81e674a2241e7010001	\\x33eaa3018affb8b99744bb8e0773d56a1b4043ed6672cc58f98edb5ba59cde59ef8c6f4b45725d5ef483e10ca461d02d88b1c25aca2ace6aad071efce777d60b	1678027843000000	1678632643000000	1741704643000000	1836312643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xbf6b2763be8e77a9a626a6b9ee601075b5614d6c8efae2fb7aa7186372670435ae761f854dc60c81ef9d3daac5309693e259275afb1f5d99682896cf57adc075	1	0	\\x000000010000000000800003b23ecde2be161057abb8b928bd955afde5d235b27ce2d7dbe9b9de0261a2ec48e4304c396011f1fd262106e28cda2781578e3d87e24e7afbd44f66b1e2439348a6ae266d01a6eeea3cf391d89a6f441486598a11b8b21db1cd6d563730def805214c4cac87ee9db0e8fe0b5c26d879fc6618f113d18a6a73ff72a2224832dea9010001	\\xf994fdba69fa19d4daead7dd5eb51e4872d96e82bd288f6fa0c1ac2813106847313f9f8b5f65f66ac207682516458bb289b8ab2e655ef63a75225886e4e4ce04	1668960343000000	1669565143000000	1732637143000000	1827245143000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xc1a753db3f5d1a90c894363f120440fee46aa9c871090736a56d17015b97136f02185969c986001c131fa59887e3495bd2b7b934cfc792f0830e0ab4f32a1e4b	1	0	\\x000000010000000000800003d0a12d40410f07408683dac92b1af443659ece0f5dfaaaef4fc673dd07ecc56ade8da8c52d41c8594cdbd6a6be47e2933244283ee2d4e055f4913483703e41d0107b430a9eeb6dc732a40e8d2c7e3c17045cfa286a658eaec5d6265467329010528cbc745355a4fbd0327c1f031997ef215e9b2045871d96935e1d4af734f291010001	\\x14f1d564051e42a09cffecbb4388d4e4af35efd5c5eb15c500684c8772870640c06278023de734be2968b9719ce4500a859ac81e65f22fa51595cf8735892c08	1664124343000000	1664729143000000	1727801143000000	1822409143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xc4778d1c46f55c78b88559d89c38c9be0f819358824265e7ac01410fda3f5e86f1a9b9baacace4e16e238e5cf13f90b605fe01751d3419214edf62babeadd362	1	0	\\x000000010000000000800003bd9644dc8519f94fee78df6abaab969ad9ea0f9b7b6477de8c43d6970b7c479a17c03e11fed2a7655ee658cd5a4279e6a0f3db0b146161c58746ead29e51a87b96d514192bd2ade48915adae03dfdf2fbdb7bfefd44a9aa568f6c51b246699aab3b15e7dd57c63ee0f7549b91d8621864ee4d0b7a22a09ab2c68eed7cf298fdb010001	\\x49fc77c6b2b54289a36ba96a5d58a16b9b111e50c534bfec3e8aeafcac984c437b6075681cc8742b1b992951362ba40286d22a896b570fad341058f1c7a2fe0a	1666542343000000	1667147143000000	1730219143000000	1824827143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xc567b6200707e7ec260e89db39ff09b0263d0bcd245486ca483398df76028cc4f9ea17b6c9a6f27948f1383d6307ca1c69592c8b0be8526397780c309803ab39	1	0	\\x000000010000000000800003ceb32fb852e6395f9c6fa014eaa3375b09ced147430e980660784c84ad0ab2bf036e4fcf8b75b25ab3ca87106859aa5896cd3d9c018816ed8c2a4ad306291e72e72529249d9cff0d5c901157128dec99934be5bcfd22e51a0a7750f7f94b887e9beedc45410fa41c01ac918c5d0f22af5ae56ba5742e77a3048a3450fb4659eb010001	\\xbe8996550d96f6c19582402e566162ada3550af32e09cf25678aa04929f5e44b31d1a73dcbde7b30a674e35f9aacefd66828bc00d09315b8c45c02747bff1a09	1676214343000000	1676819143000000	1739891143000000	1834499143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xca9752c3472334dcb27aec5bec9617d2d48c17541953eb80c0bf0adc7cfb17bf92d5c791e419d2840ea00be5c3d385d971dd161cd9768a9beeb3aff0bff41ad7	1	0	\\x000000010000000000800003c9edd29e949890e34a2f4136212d4e586458a574c60e19f75cf5fa09b4ab9b598b3e2323d583c737d96d5f72b795af05cadcbc0f1a7addef1b45557a4a863f459891abe79154d0964163570b0c914999a6aad160d26815b5daef635cd04caa6314b55084f34aa6a13c78377028d8cc7cad7eee559a2eee4e244a1c51663c2b67010001	\\xf98462048622ae460e4fa8cd6c6c29dd74e42295c4bc067a016206b568c740e9507de4055efa096ed5dd1ca92d68da30cf65cb8604ce5aa3ad87a273afd61402	1672587343000000	1673192143000000	1736264143000000	1830872143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xcaa7fdafd43416fdec1678b4cd2f73e8c75a7847df862bed6b015bbfefd9ac0474e881bfee5eedf948c22526ddf10eff73f6164044cf5f74ff38429414f9b0e7	1	0	\\x000000010000000000800003b9718f3d8d116de8ce4142972c9bfed8514ade25ab76063a396174882772da14cd21b6f1342f650cfc68bae1793044004205856f3fac48673c92a041f2083f4c8f51bb13c66a9f5a8082cd41458770ba100786ca74dd1d8dad0d61aa351699074725f5ddc17313ae49ae2ffd5c3790dabaef1f89b75d42317dedc484ba303297010001	\\xb07296bef15ebcaabea3c8061dd10f6dbfedaaf1a214c18ee7d670724e073f147e214d677cd703c056ed3c9ab3a2ee5da36e8a0d392d3ac6bfe2416b42bee30d	1675609843000000	1676214643000000	1739286643000000	1833894643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
405	\\xcebbfc2e9ecc2f250d7370e5ce19221cebd1d67d279383abae56e8219b23825e52948bd9a07f6f5293a3d960fa9d09436bdb76b791b6c59f6c0b03255b03d858	1	0	\\x000000010000000000800003e6a47dea0a196c24a29a525559bbffde1d5269d7b6991911855fd5cc72c28c32ad0c3d540ad6697c773748ae7150db4f071e39f0fa9508c99dc2235ff23d8f9a393b36b85d53c4210e7bcfb78734b01bede3c12fe36d94fa1be01ad400de241d543412f99a513a54508e15ab9f10547b5a7bbe93cd0807eddc01b43319c8c7ef010001	\\x52f226b5509975fa0dbd460a6e5af650f7a502bd06d2fc17e81a6f8d820d2251f10a4cb2f964bc1e794ffff16232f3dc77cc7a6f5a19ace763f8dd5a2cff3107	1668960343000000	1669565143000000	1732637143000000	1827245143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
406	\\xd5e34f3a660b038a8edbcfca17fed9bfee519b2ba7c3930de892b75a4206ad2ad19ff3c6da891246c6c09c68c3e29f97fc0e6eb30e05a118a7b7a887ad5ae411	1	0	\\x000000010000000000800003c007ff9b64589ba1f76d6768aee172f8fc6aeb1a49a73ddbcd3c0c1b72c7e5a1292e833aeb6330f344cb8a7ef6d704757191492aa81178d20bc12d21cc73b922499b6343226782a1f1a52665693cc1341ad1ff14c4eb9eae275a267d25509ec983b34204204e056e6e6757a369db446c21a95ff22c81f8b8c951c861a448d27f010001	\\x433d2a92895ac9eb5b121b7ac489222024012ef365dddc188ff700a335a0bfec9acd003e0e62e35d2cd2adde07280dae8ee377b12497e9669a3d73819f7efa09	1653243343000000	1653848143000000	1716920143000000	1811528143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xd57b8a572f79a3a55866df8f9bcbdd0983d50eaab640132c91d3ee41bd5c1782e15393ecf1f70f5d88eb838bbad20f80a38a69845484b8d9962fbb0efe52eb83	1	0	\\x000000010000000000800003bfa504f75560da351709d02fc4b70bd1d764223271decec8f0bec5d69311e3468275ae8bd12f56b7132d99bf1fb8091a101321efb49414d349b898ec7d29d12a05998fb637c917d90db5315d213f0bb1f0dd2053b467a750cb5227f3f239848b7c6c357379e428b0853ffd06dd2cf0040dbbe5295fbc13635a0ec939ba682517010001	\\xa11766bd912fed2dfc5f7e6b6ec592080e8b72bf4d60cbcfdce47946fe0f0613a9a5d858d737715f98970466374d21ee8fd814a988c943ebb5bba79631ff7106	1658079343000000	1658684143000000	1721756143000000	1816364143000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
408	\\xd7b36bc554ef0713ac1d3e9a5aa71e63fe705dff7e62a7b9f50bece6b6feae7d89d21ae2d6adc2e10db69be76f3165458aba370cd7605e6b832e4bba13de1280	1	0	\\x000000010000000000800003b786b1bc5ae15ac7f8d33ec3856411a4c8c895892e14b9c3e97f7299e061750f7db9482336a61c0e8dce5196f43c4357e167a4be45a6c5466686fc11796b90ce94f07d7dbfad8d2a5a40cb02357690f44bfbaac8a2dc1169ccf35e56ea0b8c0c8769557109dc79b7d7d9ab2c7a3c5ef11c532a54e76c24d19e04c539f4eb17a7010001	\\xa0e5a550e9f19852ea14ed206cc0f2463e22a34dc8bb66e3d6f74c72f53cb23a8ccd3bc7647446a44a388a44fa1f971503afaa9d5ef084cea8fd349aa1d88f0d	1679841343000000	1680446143000000	1743518143000000	1838126143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xd7e3b6568875c0ea16e0d3eb27d242c209420c129f87a9e4dd2a7ed26b6da018f02f1144e9392e6720cbc1f226bf71fc397354f2076b5172a1ccd11063fc68b8	1	0	\\x000000010000000000800003b21c96e11997be26eaaa56062218830bff171de8c5332d6ad9ec3b7a8e8ea77f9b0eaa38efccf45aaf3e449db5462b338032db4d6c00fd1a12a9aa4b28b380149b96a9667616dc066450b723782df04e916dbee551f38256c14a0fac082b0fb62a37542f0688c6145c3dc7cc369018765553512507897e34bec935e5c409b387010001	\\x8bcb232a9156a775693f4a56dbd3cffe525d15b9391728072da9a5158b653c4dafa08991ac12d8270b24140a689b20aa8556f89f0eeddc05237c0783fbcc3a0c	1669564843000000	1670169643000000	1733241643000000	1827849643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
410	\\xdaef45a933caf74551916db1626419c6ec5b99a4fc04947e7692641a15cba4e6ddb864c10c19f720f0d0c1644233e2fd18a3420e0f66037b7d913340472bdbe5	1	0	\\x000000010000000000800003978f16338fc359a1d5e733ffc9e40da688624596b6f59beb5cbd9ca1e9ee463b992f7e56361e9f07e06f6df77435654af404d356f655996fcae0dd530d3219d2edf235a9459a7ef85828fadbdc779c18492008ca41237284e58fb5495065a5ec439162aab299077a5f129af800013995c2f8a69f7489f88f39e635f59e638483010001	\\x6bfdb171f513dda8b6e10089aaa4edbade135259c1a74faf786d31ba0464193718af424c1ba7a4ba89da9833177dd457641c17e24212f29d2398447a6020d20e	1656870343000000	1657475143000000	1720547143000000	1815155143000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
411	\\xdf574d0243a6de153c80c48a74a0d56b530a42b82bc727cf429ef1489a63d7e9e22a92851448515772fe13b5c6a16058a0da43370bdce68aea462153d9a06125	1	0	\\x000000010000000000800003e6822df2d65873a496585a1c2f4a013854c449a42197987a950473ad7409db7a379cd44fa47ddfc2267e237865bac4966c1a6503195a870796d6df254e081c81604567237d4f40d95b7d2487bfe7c115707b15a773362860ca47a301e154ee211908102d3e7bb2787d5da95ea14900e52fdfd13d454fab3c368405de0977244b010001	\\xcdab9a17f91e7293bb2d03d5221c143dc58430473baa6679e7dc67998c404c4513c73cc74ab2e3aefaa3effd477a525fd418b47891c945f8c424d2a8d4467502	1664728843000000	1665333643000000	1728405643000000	1823013643000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xe0af89bf9f716bc305e62683aaa7df865273e000f426f5b48f53e093c09869386aecdee4f8fa18462bf20c60c51b5323480432b9b8fc512a2ea0bd93dadfcb08	1	0	\\x000000010000000000800003b9891dde796e36e2afa4ecf2d5d7d5e0fc4b138ddf0b438d902b9e779b88857c6bae3ba716eb429100ffc7381ec9c7dc2143824331667987244b1391969622925e3548d1af913e70c861b7ee4b594f0ad1115104ef29a27c92d2b992d92bb28dbff5a73a0830d74657063468ee082139afef133ee72a7b1ba5396c6357ea7c4b010001	\\x152f23b5901bc09478ad9c49ac72c48ce94790bcde07d4b6300a96fb25a91ab2b62351f49890b74de6962d28366d7512ea81f9f0b16ef039ab963f2c0425f602	1668960343000000	1669565143000000	1732637143000000	1827245143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xe51b5204a2dd0f57693ba09e9e7098125e741c889da7d48514ccbd0a59ccfa3b73615df21f2736340272af9f33aed6abeb5493ef7cb45ffd49367b57974f9bfb	1	0	\\x000000010000000000800003ca8204ef1c61926e7f228f97b2ca22c77680fe3eeb8d5b4b590f040b4de28f82188d57b098e6584f669b912d1a1d439cb4d3e0703b39e19418d6a9c40dbbf92661506f300c20e9fd06f597b3ea96451bd33d0d9118501a04993ee961f5d4e5f888f8009cc17e0ffc2809f94af6df1094c0876077c4afc9fcfb7ba79fd44e163f010001	\\x0fcb78575dc43a43444960b7f90f8f5cdfa45b1ae552fef88fc9f3fa8a9b1f018d58f148b912ee95048fd023ab62e72e7d49c4a240669ef9e38b1d70b71b3108	1659892843000000	1660497643000000	1723569643000000	1818177643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xeadb3ba8cad1b5f8457ae165b3e5fb3a9ad44e2f8f398333002d9c7e6b13070f6a7cd8d5e5e932586bd3f35a906ae96632efa3dbf09803e2e178e5ff7a349bcb	1	0	\\x000000010000000000800003c26414f4d23bb32c575e24f47136d26c676a73399164da865849cf77894919a746a2e4c5c5f5f62320fbfe9e48462b4abd5108dc402c52d8d5530cc109b157abbab847fc860c0d66860c8a6f316aafafe16bdb25b58b7b45adbc4eb2bf606347d26585cd6d45c0a8d6707d1c72aa0d539b856f47601717f00ad675641e11f385010001	\\x374b23b313d0b6774512a2c96f6de2f21050c03165e450cae15d848aba255111f4dc92042d1d2953a353adac63a6b7f4235f7b4f1633b3c9bc3780cd6f2ecd0b	1665937843000000	1666542643000000	1729614643000000	1824222643000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
415	\\xef675d2fc7a1a6b4f75eebe3b5c30cbb2d361aaf4dd6a242ab5e6e48e93536f4d3a93035b729ed40291c29215afc319d7ec6665752b2dfc04db6c648a65abdbd	1	0	\\x000000010000000000800003bd84be78d63927e637d13f3e0e086dd7841ba42664b296d6741cdf5f355112d4f064f3f5d5d070f4e4ac710624040b43e812d2a3fa3616623075ce7df4e46a5ed09e03217ba1226d1746deed61b190165071004616846ebe816edc19f7d714f70731b466e6912f2f3fccbb8f5702dd844326a9fc12b3cfa5f38bb0df332a0f2d010001	\\x0e03da3bfbad59c642285d523af4e1ca2728f50b5fbb414c17174ccb57c250dd7e17f4aa764232d6e8ca6ca7d1e2eb61364f8690ea05acad960199fe5fbd7f0e	1660497343000000	1661102143000000	1724174143000000	1818782143000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xf0eb0ce2c8663d73e4b3a2c925515c2c9723c0f59c9dcc2c59bf3a01a3147e9e50c77495bc2f6ddcf33a6a14efcaae0d1e8002e91deb8f51153273e55b976ef8	1	0	\\x000000010000000000800003c0797c0ddfa3c2b546925eb874ef7c2b66c984e81ef2b4029ffece89454b29cd35ed346955963034f4517ffcb6aec83ef0a3c251d4895b5ebfcb833567bf17394ef7ea8da771f3cbfff1efdd1a20840161451cfe6b67a031bc1e5559a2a0d02c2ba683e7b38073ec4c60a8c0c8fc63202d867e2c56d31dc31eb6e63b7a029181010001	\\x4ade9ddd619dc9f42f1e523ba51b910e0a34476529bcc637833e36ebc40dbd9ae15b1a38d43bd8c122e684784062c35855c41061a7fe8b159de7fc990c57cf05	1675005343000000	1675610143000000	1738682143000000	1833290143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xf26347b69786818c8a116f07a2ddac67bbbf0c13e78e337cc40bac24d0e95aaee1cfa88c4e3d511a907ad1cb1692e44198924b7dd0a5fdac24dfbd6df944273f	1	0	\\x000000010000000000800003b7a1912c5c73450e6eb8de9bd32119d68d8e9a5a1d24bafd660a1699d8d36cb3d8abce972d7c271e0614dbe89d27cafcd9d9ec0a1931f004cd678716646d26043c62aff52f43506562fd435dcfae29bc72f95643b2be392dd2e777b4a55524dd84e7f04cae0ed57e29d8b441d5a1b033b4da04302187ec3eb83c21d78d97a991010001	\\x59920ac79403269eab1a59723550af68011b9aa6bc662afd9afd5fc764aa276a8a470a43a136cf11dbf08fabd82483589cf828db155b585e3345cedbc0927106	1667146843000000	1667751643000000	1730823643000000	1825431643000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf38388d6e23848e1e9a4fba2a7073056d9153b3cab73954fa9fb633f4c5eacbbbd45d2040a7c910866310d0c0c1c299e1f8abe3e5959ab8787976b317a959d8a	1	0	\\x000000010000000000800003ed8e103403fb55897ab57d2cd3316abfcfcfc1a4b4ce1790ce97a231de3d553b960602f3210d0385eaaa9aa8df44c23ec8e7baa43fbad8cc1fa9539d06f0d57afb0d816e2d17d0aad7e2123f703946d3b91cebef75961b9b34bf12245f9e79b2f194a5607a1a1ef1280917026916a81cd0687a7bde3cbe1d3653609dbebcbe03010001	\\x3d741f0d1b631bf2d6e103f85750cce4ab83969815ecc847c26a72f75000f72149dafa7c0c2923a6b9ec0e9ad6b6a289b1915dccd8392b56184e49c04885a509	1655661343000000	1656266143000000	1719338143000000	1813946143000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf5a31abd7faa335ab18cc3382b4bd90b3262746c6c17f5b392277e26d52af43f3decc411e4fa17f0d823a6a54f450c838883a38f239f89ff54eeffd422430a13	1	0	\\x000000010000000000800003987021834a66809f261fadb1dcb3120eab66bf6598c4fa39e99a94d44b4e5e2920cf967596ce5eff487cdec67b7ab8be7446425bbd50603687865c070d370f98b0481bf79ff487014428b741b32c8695cc874e6a5f90f668b3bf83032aa05d0560f331cb08a44a98ac282e682f9114c3cfbec7593d4aaafbedf7e5924bc97f43010001	\\x43a46b0a4f9409c0b134ee0528ea93abe52329a86515af0930ed8c208e6fcd1686cc3b7f245701a2b5bcd1c8aed0df5746092fbddcd1ea4121e96c883bb80901	1679841343000000	1680446143000000	1743518143000000	1838126143000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf7c7b46d3b12637e093752d54ef0c0f7e0866173f1e2f717a20d4f44a627ef79b24d77db5f4cd867705120cdf1484eb294cdad8a0659577bb2cbdb340c4155ce	1	0	\\x000000010000000000800003cd76e77a546918cdfc6ca0ba9436c23880cd431425eb9b9aeaf9f585bb9c3cb249b62f530f45e6158fc18c78c21c95488a50b0d3e06ee787eb3f10f49c3838724083f89bdae8535feda828b0fa75c31a39feb934a9bf2aa45637153da1458c78569b3ae116f3fa52c6eb4dd4184bc4258bae54325a89814c22a73ab4a288796d010001	\\x557e601a1c9757f515280da11aa458cd9f16ca6f105888ccb6a34f53c0b645016d6a0a078ea5a2c956e3bb568b23d1688bb406d016ef8353cce409a9d294650b	1657474843000000	1658079643000000	1721151643000000	1815759643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
421	\\xf87f7010c845108a8cc7ab1c6c2611fe78a8b2df174c0cc6f2d792e24f0b394c4beb7e1b9c7ab85b3bd0cb274bcd1c013217d0fbd210778c0f5f7582ee38b5c5	1	0	\\x000000010000000000800003c093e55662499b165909e3a9e0d85f2ac1738fdc663bd72d85d37015c4b364813929347c5892e589341c2b92ba227f9f925d5f392c6302b55d867f8abb9cdd93ba9210cc5c12610c5239dbe1089ae9410c976468e036ac81c8ef30da2b8c76ae55825c931e3b5e96b71fd4edf8423c1734e7534e2078154d4e4635457edaa7ab010001	\\xffe9973ca936aad39e8833a16a6b1b5c31aa3bd2037260eea8b1c3678866469ceac809b57822f4c5e67a6f003b7c3e680db1df5de452c5f9b123a0552438b202	1665937843000000	1666542643000000	1729614643000000	1824222643000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
422	\\xfb53188bb3b8a4a571e98f8bd6d842fd4f12245402602529bff347c2bc2eca2d6411243b1a358d73830fbd3df3e8be7f3df80fb13647b2461e4809179caf008d	1	0	\\x0000000100000000008000039b88f53e186814f201ee2e5adb9a8358c0911fa32a263cc0964d2f4088f907c6ecfbabbceebb6e4ed2fbbe014a743b03ef10394d2b3374eb3c0a7f7bf931432eee66ab7f183d0a78a002fc4f4a52791f07a8df9c8eee65afc2c15dae2f783b3ae135532e3120ac14be1546c51fe7766f91a263075c025758c0700b30f08ba089010001	\\xfccd3839693f5530681def391578b3bef81982435d3c7e5cd1a4f930dd8f87c72d3c9baa07a852d14e2adca8904f67707ce21aaceabe477aae42095f52c8f90e	1666542343000000	1667147143000000	1730219143000000	1824827143000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xfd2b511303f43f2457f25263e8bef5b7a26564f62c5e97772c528e35171175133c2f3bcdcba8a0add323a60b7734ae6209e148dc000cf1068181dca81882d2f5	1	0	\\x000000010000000000800003bee7300e4a49f4e1b51799c601372bd9f33ed1968f7c96e5c2940d2bcaf148155c2074d023b645a65e62e2f9845d7deca5a528856a986761d2af0f2b43fa3fb6a4836e3d53937a800ad4a2a2b8eca32ad4b2afe6734dfe75108abd6e43654f532255f25b2e9ede7f60f72f7a9ad9841554fcf98e2235d05faea40c4096a617c9010001	\\x32e6e3ea6b351de3b8c474f0cc877046699c9f983f59f85e2d9990f4a356114bea9e09109f3225158effd6a10b419b22d7b37511bea969827a06ec116051d103	1653847843000000	1654452643000000	1717524643000000	1812132643000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xfedf274bf89d1ad1daa8800002bb3967af0ff660503a4bc0577099704f597bdc3ccf319a0b09572c33744ff6df7a2279ddb4a8d93e0983e5752b2bfa4254421a	1	0	\\x0000000100000000008000039d3369bb891e3d40b617c855d8e3219c6f5c74f88e4bea8964c191ee11af3cd7e36775a555f6a2b8265e4cd1d2260fed78ea9fa1c8437d3399534d6c1f25ff97901ef741bf919773e088af682377a5a529be3fc8d59e4ea4c9bb0e39a429ef3338cccd1fc10b46bcecd26cc7a681a8c4bbab83d983310ebca6be19d9643b1bef010001	\\xea58d35e5ab1700227782c88799224ceb925d1335865f6b689c8e63db3eb04f3c9de01faee0e67f031830d100a705622e787abba1355f2c84d8656139f8baa0c	1655056843000000	1655661643000000	1718733643000000	1813341643000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	1	\\xe438526ad979a98737609edb1e928199a3930bcf0510ca3ae63e15e46c87b415ffbc83a0131bc0a5f33b8be48aae0d92778faf8ca6fd09fe9ade05efa18b4388	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xfac02a5e87ae01f85fec43e5340be2b1eca8b55de695faee43cfe05284ded4c203cfb6a64a55af40eedb257662b1802ff8b4bf552b641b2e76ebc0de84c7109c	1650825375000000	1650826272000000	1650826272000000	0	98000000	\\x5d7e949f79bd91fe140f4c8db76f7055bf1c2c45e5285ca802dba0ba0fd74af7	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\x35c6d730c6c6c9071ac08757865dd3101327594d80da2a75a14a25ce71735acf6fa0edf641ef6726e834e39c04fab1c782edf4b2f4185597e01bb95d262be20d	\\x43b80c8d574a98e097cf0bd54059bde453f269b7a7c1f33000b998b3142aa6e9	\\x50869661fe7f00001d499b0294550000ad243903945500000a24390394550000f023390394550000f423390394550000d0ac3903945500000000000000000000
\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	2	\\xc940d9de12b440404af86fea8aab6d17eb08f05c98bbeda43fbae085415df484e27722b3e0dce986d70e7e83eac34756ab424179ca0c880fe9005e938833f24a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xfac02a5e87ae01f85fec43e5340be2b1eca8b55de695faee43cfe05284ded4c203cfb6a64a55af40eedb257662b1802ff8b4bf552b641b2e76ebc0de84c7109c	1651430210000000	1650826306000000	1650826306000000	0	0	\\x0b6ac6650ecac0546cff3a1831c72a2e6672c3b171d6ac312197f17ba79cc344	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\x626771417901c5c64ee78e293e0aae32a26f177d62fdbabb652882fd25f95c1bf04e11463c64b1ec557a6e8bc8181bb36ebd9f774d391db3508456a1e3c4d20f	\\x43b80c8d574a98e097cf0bd54059bde453f269b7a7c1f33000b998b3142aa6e9	\\x50869661fe7f00001d499b0294550000ad503a03945500000a503a0394550000f04f3a0394550000f44f3a0394550000c0263903945500000000000000000000
\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	3	\\xc940d9de12b440404af86fea8aab6d17eb08f05c98bbeda43fbae085415df484e27722b3e0dce986d70e7e83eac34756ab424179ca0c880fe9005e938833f24a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xfac02a5e87ae01f85fec43e5340be2b1eca8b55de695faee43cfe05284ded4c203cfb6a64a55af40eedb257662b1802ff8b4bf552b641b2e76ebc0de84c7109c	1651430210000000	1650826306000000	1650826306000000	0	0	\\x0cb85f70118519c10b9528791d2926c10a542b05cb54697e240c14c47c6f8a74	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\x96efc9f5dfa1b7ac826406cf1655701f9ad765cd90785c2dedf8a539808d01d48af07f6d8508f0732033489eff9531a526f882004299d3d1958e0d7c6896790b	\\x43b80c8d574a98e097cf0bd54059bde453f269b7a7c1f33000b998b3142aa6e9	\\x50869661fe7f00001d499b0294550000bdd03a03945500001ad03a039455000000d03a039455000004d03a0394550000202d3903945500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1650826272000000	1750954084	\\x5d7e949f79bd91fe140f4c8db76f7055bf1c2c45e5285ca802dba0ba0fd74af7	1
1650826306000000	1750954084	\\x0b6ac6650ecac0546cff3a1831c72a2e6672c3b171d6ac312197f17ba79cc344	2
1650826306000000	1750954084	\\x0cb85f70118519c10b9528791d2926c10a542b05cb54697e240c14c47c6f8a74	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1750954084	\\x5d7e949f79bd91fe140f4c8db76f7055bf1c2c45e5285ca802dba0ba0fd74af7	2	1	0	1650825372000000	1650825375000000	1650826272000000	1650826272000000	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\xe438526ad979a98737609edb1e928199a3930bcf0510ca3ae63e15e46c87b415ffbc83a0131bc0a5f33b8be48aae0d92778faf8ca6fd09fe9ade05efa18b4388	\\x6f2fdeaef16e1a6e1c2a777eb3a568499555537bffca989dfbbab32b5b6f320c2e60db47fc109bafabfc53ad41b10597b9bd11fb2d98ef724cf46735b593d601	\\x033966582f073c3bec627970e0900d02	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	1750954084	\\x0b6ac6650ecac0546cff3a1831c72a2e6672c3b171d6ac312197f17ba79cc344	13	0	1000000	1650825406000000	1651430210000000	1650826306000000	1650826306000000	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\xc940d9de12b440404af86fea8aab6d17eb08f05c98bbeda43fbae085415df484e27722b3e0dce986d70e7e83eac34756ab424179ca0c880fe9005e938833f24a	\\xf21eca538f6e621ba89d41f019fb002c088b79b5778a4b84b4c6fdf3bfe2a0f23b0dac0949abe0c21a9212d03f3a4c5a49d276657fb8f82807b43fc122fce500	\\x033966582f073c3bec627970e0900d02	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	1750954084	\\x0cb85f70118519c10b9528791d2926c10a542b05cb54697e240c14c47c6f8a74	14	0	1000000	1650825406000000	1651430210000000	1650826306000000	1650826306000000	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\xc940d9de12b440404af86fea8aab6d17eb08f05c98bbeda43fbae085415df484e27722b3e0dce986d70e7e83eac34756ab424179ca0c880fe9005e938833f24a	\\x4ad57b638e955191d85d6b2c599790d0c7ca467b4b2de13b468ebc4debf275418075290a54be8875fb113e7b1f82cbfdb382cea1ae310ceaceeaa0372cf1e504	\\x033966582f073c3bec627970e0900d02	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1650826272000000	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\x5d7e949f79bd91fe140f4c8db76f7055bf1c2c45e5285ca802dba0ba0fd74af7	1
1650826306000000	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\x0b6ac6650ecac0546cff3a1831c72a2e6672c3b171d6ac312197f17ba79cc344	2
1650826306000000	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\x0cb85f70118519c10b9528791d2926c10a542b05cb54697e240c14c47c6f8a74	3
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
1	contenttypes	0001_initial	2022-04-24 20:35:44.183682+02
2	auth	0001_initial	2022-04-24 20:35:44.308715+02
3	app	0001_initial	2022-04-24 20:35:44.407401+02
4	contenttypes	0002_remove_content_type_name	2022-04-24 20:35:44.425457+02
5	auth	0002_alter_permission_name_max_length	2022-04-24 20:35:44.436106+02
6	auth	0003_alter_user_email_max_length	2022-04-24 20:35:44.447728+02
7	auth	0004_alter_user_username_opts	2022-04-24 20:35:44.457458+02
8	auth	0005_alter_user_last_login_null	2022-04-24 20:35:44.467422+02
9	auth	0006_require_contenttypes_0002	2022-04-24 20:35:44.470533+02
10	auth	0007_alter_validators_add_error_messages	2022-04-24 20:35:44.480233+02
11	auth	0008_alter_user_username_max_length	2022-04-24 20:35:44.495284+02
12	auth	0009_alter_user_last_name_max_length	2022-04-24 20:35:44.503567+02
13	auth	0010_alter_group_name_max_length	2022-04-24 20:35:44.516279+02
14	auth	0011_update_proxy_permissions	2022-04-24 20:35:44.525803+02
15	auth	0012_alter_user_first_name_max_length	2022-04-24 20:35:44.535941+02
16	sessions	0001_initial	2022-04-24 20:35:44.558344+02
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
1	\\x41a9e374c8b314ebe6d0ca048196bdb8ef0e734df90d7cc0f5e47903a81268b8	\\x3f3ce5391b93597f9ecf0d6efce683c0d315c7f938c10188808e2b007d81092f021adf2f3ff81dff328fb9c9448b715c7371ebff5b874fcae66a5a1e81765a0f	1679854543000000	1687112143000000	1689531343000000
2	\\x43b80c8d574a98e097cf0bd54059bde453f269b7a7c1f33000b998b3142aa6e9	\\xaf4368c65d3a5c21adee6466d5e82e8ebe3c414776cf840cd45d1390b97db17abe16a8d6b9936e324234ef0c00a3bfbb55422c721ccd1e61817de752ef012a03	1650825343000000	1658082943000000	1660502143000000
3	\\x956cf23acd791b6f28eb29b8709373be41d26f6977a72cf9918bf4222a193642	\\xeb5af21dad680471b54291a7b141e13f853ef6f3f18dcaf62a720a776193003f889dd472439168609457fad4c439f4d6fc4457e1d15e691ce899d1a30da3b308	1672597243000000	1679854843000000	1682274043000000
4	\\x9d288d4ea6d5193569cd536ad1a74c5335ff3218bc9fa90b31c94a3e875cb819	\\x20cc69c0220c1435379493f5c84f00b10cd07c2b69d38aed61c99f28d066808d90d20c5d5f685124ec19c3f6255abfcc8c8a1a6565122a6fe82898b65a76e201	1665339943000000	1672597543000000	1675016743000000
5	\\xdf19d39b51fe031ae9b11284afa8f4c18d80bd3a1c360447b4d05ae3bd245ec4	\\x73de70aad51652c15030033c941cf0e24880e5f7b2d7bcee9cc140ec6d986fdfee39bff7736b3d9922fc562879a2535cec68b1da2bb464c5fbe68fdb1c0a5a0c	1658082643000000	1665340243000000	1667759443000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x5bb43c058868c71bad6faf4a9b66d34400e7f2dcb82144140b77a70f17ce2ecf147a0365b160a6a7d837477ee4d998255c0e0384a5f77b280e942fd5d3eae40a
\.


--
-- Data for Name: history_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.history_requests_default (reserve_pub, request_timestamp, reserve_sig, history_fee_val, history_fee_frac) FROM stdin;
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	325	\\x1b9c99cd5073fe3168a2ac41106362c5f6378589b9506f871c80bebf02dfb15d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000066f4855ecca51bc5946cdc2f29b4c6f255e9247f7bbfc7843ec2951915af83b9a472185d8d0a0194a52094e35358bb55ada031f08e796b399f3ccadea17f2b6ffc5e70d32ee802a7e78761681483be9c7157db57a3bacb00b5772ba4b75f9ff7ce07e0415bfaf37b0417db83274918d75aedc7333eb811c1447df4e8ccf5cb75	0	0
2	315	\\x5d7e949f79bd91fe140f4c8db76f7055bf1c2c45e5285ca802dba0ba0fd74af7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000328a5e19a3320dd8fb3e70b1bc04282bbf10cbb870979855fc82a780483b4f2451b3d00cc980d4b136d567bafe757963c67f0c431f11894e52ffe84a07fe6d1a6806465eaeb415d085e7ad4b350671bbe487f34962b76586c1a513831e31fed72e1f3fe207d597cea75554a6a3f8a779a0904cea8621ce2d6376d2e07ac5aaee	0	0
11	66	\\xff31a9296bb7e865ebd9e68f35ce49313ab904ed345591e66a458a18161ed533	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004cecade8c43e95cc7d01ccd6acf03d5f2482b3c73255fb5544c6fba2aaf14ec3c3cddcda5fe9836ef44af0d1a9a8f20c884c2e49a4f1d9a65d171f28c882c93e17154e150401d63ae134b12cec5eb7febf0daaf3f6319f7512a1db9e75ee1e49dc18d2fd6e598580bd28b36905e3f43028a5a7dc324b50d3002d88cb9d5a37aa	0	0
4	66	\\x19fcf350c224eb64c9bb026d5a532cc100a0be5d8af7aac441b6633eaa284d3d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008a12906c7224527537d30b06aceb6f2bc7f5fc5267e7012addaae83a8fd593ee9a4805aaf4f32c26887d292ec73dd0cc9f742bda023e51fb182c59d2b3a03cf12c987e34f13a6d05a534326b3621694503a726b29c240a851f066d8947c72e4bc27f882e128dbeb38f9c0f2b8f2387ed860d00ef01df1b31d7310c220fbabe21	0	0
5	66	\\x933d8a09680cbff70133c04fd2c6bd05d893fe5edf3be46147304b39274a9555	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000144507dbd68621417e74cf34211a5e7f61f1178e2db4b467914aacfb025860d7ff3cf147fe010be99fa4b465a8f3afd22386459357ca70323dcb4914e8036c1709684e33f2c23aa83566efd80f857d8bc4ec56a08b9279eedae272791a87bd159c2bbb27823be98b82f5f8346388082d4681893cca6b1aacf09f8c52e30a1cf3	0	0
3	350	\\xb09a2f656719c9f96df3d5c19bdb2b6d8167c8e1e1b8444612848a8dcd0f8f89	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005c989e6e89b65b9b1ca541eadde813ca47e23d61cf94f8bce902bc24266009707dab821499b86e3a46b408d1ca417257d7d561a525ed23b2f8bd12ddf701bd26b5e8be5fbc9f5559faa436bf523c84505199a31847e9522bf775732f2789ee6b24fb4ea450a0698e3a3ddde5a17bca8117c58fe25f4bbaac110d14ff8b8ad510	0	1000000
6	66	\\x8211325358a4bac66262eb92199ed4902b1d72ec418a7a16a7ea4fbd10813045	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000ab983d0d9a443607bbef321b1ca806e56cb060559dd8f76719692078536d7c641280409bab6b2e0248515d325fbb9aab1c491141d267a887cff05bc612bf688400e00cf08b4335568874913d7388fbfeff4f277fbbc38ddd1c2e1bbd03a442d2d927e2682df83c6da0cc21ed3b15a7562ab679fb10c5c97c81563cf6fc84fbb9	0	0
7	66	\\xc3fc946f36f4d0c1622e936cac347950071e4f376cd3137c35ce921d598c66f5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000909cc1435a858184b8c04dab1ca43e59efbcd9c0eec9ffa1e83cb304cee35c06bad3b2bc07db12cf07fad8c251385a0b208c793d33609802851355142eae32718156cff9ebeb48cd0f9f4f0908136c9d0e9954b63a6c864da74ab0ad031a5cac4582c7e849ce19053bdc9e0f67966b3bec6d878f93c770121ec28980b5348567	0	0
13	375	\\x0b6ac6650ecac0546cff3a1831c72a2e6672c3b171d6ac312197f17ba79cc344	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006fa4dca507b0bfd8c32ba248dc3fafa0c182c580d8e1b9c3b28675d3d464848ebccceca879fdc0a0ce42bcf6dd0f41af6990273ca2136ba49282ea8dbbb1969bb454ca11f5aa329af4103328cafb824bbbec77f109fe2d6b3717bd566c154d6420e1015016bf42f97c6dd59a5b302c6664d8cd8672f9eee41948e1ce6cd72966	0	0
8	66	\\x9155bfc74ab1064520b2429a37296f48d99eb3e0a0cae62646469a9a8cac007f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c93b488e55bdaa568c3de4d8144fb17b0aa7fe16eb2acc28658ff0dc7a7d3eb7457f77efcffdcdc967c84810317a021a297c4c1d877315cff262ac40b40007faea858f14fea3ffb6530a3a95aeb99207c01ad9aae8ade519ae999e41cf7a698c5d1c1c204cca7e8bed1591793037979c1c0511efa4ef6ca1ae539bbca2e63e8d	0	0
9	66	\\xbc3b96581e50ff991160eb68aef1be2dd5a245012c04f2ce3076de1b6c193fb6	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000080a8f0e0163c23880f96533b276d2608a2cb66b906432f2f6c1c087970b9467ba138f264f70e5dd57110ae35b6f7c555dd98b98adfae593a3a84761a749c7aca85e4fc2924259fb5261f59bccb26e36675e0947cc69836b68225529314b29d53f71e7f5b9cce7a9de8f023011a1d083505f36ea08a8e6fe7daa52d54e8d26a09	0	0
14	375	\\x0cb85f70118519c10b9528791d2926c10a542b05cb54697e240c14c47c6f8a74	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002dfbdbe779c43d94542eb7c5184b82b692a5f0387bdb0b30995df9e6feb3e12665f79d2925117dbbece20bf85b9978026b0d124560c6987c570744f72494f305a7c4be78b6c8d569abc6ede3e27909c8f1fd27e2b42019912075b5fb0abcaf3cd814cea118396ff7652018ea19be941925e8c1c0a0e57d5c0a3ace7359e1a515	0	0
10	66	\\xc62eacbf6e25c4f7ec561f036a518d230295338d362f31946c895dc1b40d3aab	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000bfabceb1e2cbb603fbbf23f09fa0727d5d3896835b5075ffe7e41ddf480d3c2490a58c43e7f4df5a010f797d9d29c14c0e3215d056ef69b3b4607f07771a3d6faaa43b08038448c291f41e047cfbcd8ffd88ccc091a76bb034633bdf714cde050b346e85b0e467366f47d83b4794648cb2ffb234cac13cddb84482721d183718	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xfac02a5e87ae01f85fec43e5340be2b1eca8b55de695faee43cfe05284ded4c203cfb6a64a55af40eedb257662b1802ff8b4bf552b641b2e76ebc0de84c7109c	\\x033966582f073c3bec627970e0900d02	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.114-01R342T36TCRA	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635303832363237327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303832363237327d2c2270726f6475637473223a5b5d2c22685f77697265223a225a4230324d514d374e52305a47515a4338464a4b38325a3250375041484441585754415a4e564a33535a473535313659544b3130374b58504d533535424254305856444a41584b32503630325a59354d5158414a505330563553564551473659474b3348313730222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3131342d30315233343254333654435241222c2274696d657374616d70223a7b22745f73223a313635303832353337322c22745f6d73223a313635303832353337323030307d2c227061795f646561646c696e65223a7b22745f73223a313635303832383937322c22745f6d73223a313635303832383937323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223035544438543439443841394e58513132364d524257354b5141523733524442423451433351483134545a305439503857344347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2230523253513835463531334a5351384252425833464e5a524d54485247545747325a5638373951335a5253383441474645384d47222c226e6f6e6365223a224434384d4141435a304e593832574438475a484d58355039514d4844444645463854315241373047593541363636443253324b30227d	\\xe438526ad979a98737609edb1e928199a3930bcf0510ca3ae63e15e46c87b415ffbc83a0131bc0a5f33b8be48aae0d92778faf8ca6fd09fe9ade05efa18b4388	1650825372000000	1650828972000000	1650826272000000	t	f	taler://fulfillment-success/thank+you		\\x648c0cce7b57afc5f7cef865a37ac7d1
2	1	2022.114-02AAJKCRS7A2C	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635303832363330367d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303832363330367d2c2270726f6475637473223a5b5d2c22685f77697265223a225a4230324d514d374e52305a47515a4338464a4b38325a3250375041484441585754415a4e564a33535a473535313659544b3130374b58504d533535424254305856444a41584b32503630325a59354d5158414a505330563553564551473659474b3348313730222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3131342d303241414a4b43525337413243222c2274696d657374616d70223a7b22745f73223a313635303832353430362c22745f6d73223a313635303832353430363030307d2c227061795f646561646c696e65223a7b22745f73223a313635303832393030362c22745f6d73223a313635303832393030363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223035544438543439443841394e58513132364d524257354b5141523733524442423451433351483134545a305439503857344347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2230523253513835463531334a5351384252425833464e5a524d54485247545747325a5638373951335a5253383441474645384d47222c226e6f6e6365223a2233475135304e4b5a543148484b4d4458525348374548465238434e4345585a5730434d5a31393850434e3152384a335752353730227d	\\xc940d9de12b440404af86fea8aab6d17eb08f05c98bbeda43fbae085415df484e27722b3e0dce986d70e7e83eac34756ab424179ca0c880fe9005e938833f24a	1650825406000000	1650829006000000	1650826306000000	t	f	taler://fulfillment-success/thank+you		\\x57872bab4f49bf02e188407aa9c47bb8
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
1	1	1650825375000000	\\x5d7e949f79bd91fe140f4c8db76f7055bf1c2c45e5285ca802dba0ba0fd74af7	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	2	\\x35c6d730c6c6c9071ac08757865dd3101327594d80da2a75a14a25ce71735acf6fa0edf641ef6726e834e39c04fab1c782edf4b2f4185597e01bb95d262be20d	1
2	2	1651430210000000	\\x0b6ac6650ecac0546cff3a1831c72a2e6672c3b171d6ac312197f17ba79cc344	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	2	\\x626771417901c5c64ee78e293e0aae32a26f177d62fdbabb652882fd25f95c1bf04e11463c64b1ec557a6e8bc8181bb36ebd9f774d391db3508456a1e3c4d20f	1
3	2	1651430210000000	\\x0cb85f70118519c10b9528791d2926c10a542b05cb54697e240c14c47c6f8a74	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	2	\\x96efc9f5dfa1b7ac826406cf1655701f9ad765cd90785c2dedf8a539808d01d48af07f6d8508f0732033489eff9531a526f882004299d3d1958e0d7c6896790b	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	\\x41a9e374c8b314ebe6d0ca048196bdb8ef0e734df90d7cc0f5e47903a81268b8	1679854543000000	1687112143000000	1689531343000000	\\x3f3ce5391b93597f9ecf0d6efce683c0d315c7f938c10188808e2b007d81092f021adf2f3ff81dff328fb9c9448b715c7371ebff5b874fcae66a5a1e81765a0f
2	\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	\\x43b80c8d574a98e097cf0bd54059bde453f269b7a7c1f33000b998b3142aa6e9	1650825343000000	1658082943000000	1660502143000000	\\xaf4368c65d3a5c21adee6466d5e82e8ebe3c414776cf840cd45d1390b97db17abe16a8d6b9936e324234ef0c00a3bfbb55422c721ccd1e61817de752ef012a03
3	\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	\\x956cf23acd791b6f28eb29b8709373be41d26f6977a72cf9918bf4222a193642	1672597243000000	1679854843000000	1682274043000000	\\xeb5af21dad680471b54291a7b141e13f853ef6f3f18dcaf62a720a776193003f889dd472439168609457fad4c439f4d6fc4457e1d15e691ce899d1a30da3b308
4	\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	\\x9d288d4ea6d5193569cd536ad1a74c5335ff3218bc9fa90b31c94a3e875cb819	1665339943000000	1672597543000000	1675016743000000	\\x20cc69c0220c1435379493f5c84f00b10cd07c2b69d38aed61c99f28d066808d90d20c5d5f685124ec19c3f6255abfcc8c8a1a6565122a6fe82898b65a76e201
5	\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	\\xdf19d39b51fe031ae9b11284afa8f4c18d80bd3a1c360447b4d05ae3bd245ec4	1658082643000000	1665340243000000	1667759443000000	\\x73de70aad51652c15030033c941cf0e24880e5f7b2d7bcee9cc140ec6d986fdfee39bff7736b3d9922fc562879a2535cec68b1da2bb464c5fbe68fdb1c0a5a0c
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x0174d468896a149af6e111a985f0b3bab071e1ab592ec1de2126be0d26c8e119	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xf1cfa217b8bb0bbc2c542bea0287fdc09a04957b027445853794c7cf688e733f2830f43ba43a841a4d83b78aaf0f9a94f69a8c20abf0d4014469dbd80d86b904
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x06059ba0af28472cdd0bc2fa37d7f8a6a3886b9017f683a6e3fe32822a0f7229	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x783df51cae78e55aa0137e8fd0d0d68f292bb8f9b046654041e5957108e73d06	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1650825375000000	f	\N	\N	2	1	http://localhost:8081/
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

COPY public.partners (partner_serial_id, partner_master_pub, start_date, end_date, wad_frequency, wad_fee_val, wad_fee_frac, master_sig, partner_base_url) FROM stdin;
\.


--
-- Data for Name: prewire_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire_default (prewire_uuid, wire_method, finished, failed, buf) FROM stdin;
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

COPY public.purse_requests_default (purse_requests_serial_id, purse_pub, merge_pub, purse_expiration, h_contract_terms, age_limit, amount_with_fee_val, amount_with_fee_frac, balance_val, balance_frac, purse_sig) FROM stdin;
\.


--
-- Data for Name: recoup_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_by_reserve_default (reserve_out_serial_id, coin_pub) FROM stdin;
2	\\x1b9c99cd5073fe3168a2ac41106362c5f6378589b9506f871c80bebf02dfb15d
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x1b9c99cd5073fe3168a2ac41106362c5f6378589b9506f871c80bebf02dfb15d	\\x39864aadbd1fbbf9c7a9c1978d8fe71e86b5fce13bbdc3cc96869b337d9718286b4af76d9514adddca79e571748f32f66c6285a43c9da2743567fe0f2144ee0f	\\xbf9f096bb35513b7c1249978bf1c655d376218b44ff89a0807a7ab631f5fa010	2	0	1650825370000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x19fcf350c224eb64c9bb026d5a532cc100a0be5d8af7aac441b6633eaa284d3d	4	\\x3de23f0f5e311d9a7fbe77acedc9a055632b0585a3cc6a0522515b2cbdbe52aef290a07d7e10fc7de6baf61109bc1d8c2fcb48c059ac9938cd3099c97269460d	\\x32957457ac3fc1695d522555c832e9b0af6d855b19a413135b1cee3be4ee9c88	0	10000000	1651430196000000	3
2	\\x933d8a09680cbff70133c04fd2c6bd05d893fe5edf3be46147304b39274a9555	5	\\x2e7f3503f4fdd84998ece2635296d69168f8c7094331ea06f37df2057ec77e4c9e3960d0b301d3f0a1c188223a6117583a9848434ca237b256c98946d3ddc201	\\xa00d9d18ff55d95a62ea7e48313a561fd1a6b615b78ce275698e117a157f19e5	0	10000000	1651430196000000	5
3	\\x8211325358a4bac66262eb92199ed4902b1d72ec418a7a16a7ea4fbd10813045	6	\\x51f0a39f7a9b9add46115e308f0dc4c205cc105e543c1fcbe78e8bb9fe52cbab3ab7681379f8990229780c776219da9643ae47514980b8bf910e99ebc7922103	\\x1f9b9621696f6090c819e4e76c71a5ad63c609f47e77411f21ba3601c6c565bf	0	10000000	1651430196000000	6
4	\\xc3fc946f36f4d0c1622e936cac347950071e4f376cd3137c35ce921d598c66f5	7	\\xc26a522f54b322c7b1f0957b2c967334bd2b4252dbd4bac9eb3b632d5faa13958b8ef0ebf482d4aae38e00e588aead00f6ee5f937e6de1c9629aa5f5b2423c0f	\\x4228727522ce1107da947659de19b378de509804e1889aa18977bb4ae141d5c3	0	10000000	1651430196000000	7
5	\\x9155bfc74ab1064520b2429a37296f48d99eb3e0a0cae62646469a9a8cac007f	8	\\xb3131e224d0195d463298584d3b1f72c96488a64d3fbb868502a40094541f87544c12c6f1fc3803b563051d567eb8a130e22d41e051c4e817e738aae17aa000f	\\x8844898e4e333d10b7504aad3816eb49000d40d5d8d01a261cb796e48d72c93d	0	10000000	1651430196000000	4
6	\\xbc3b96581e50ff991160eb68aef1be2dd5a245012c04f2ce3076de1b6c193fb6	9	\\xd8d5e16a38a4abb5f981efebf535c704dc69c5600bd53f7cae2f4cf6d7854ce21a86d329bf074b67a8fab71473ea5243543b752ad350c41b3331a442be6c3101	\\xaa62b7ffb99bd6b25ed1759800925373effcbe878ceb0fff2797e9d543b23cec	0	10000000	1651430196000000	8
7	\\xc62eacbf6e25c4f7ec561f036a518d230295338d362f31946c895dc1b40d3aab	10	\\x2d2edba9d50b0b0da41fe81b8dec3e898973e7a4daf62e7835dec579c1689871fc61cc9207b47987d928b3dbf9c5492450d35b25deb279270a763e6a05367f00	\\xa1971047e1854c1d9288497d6a3973739c3bcfc59ee5cdc6d973dd0ec0bc69b2	0	10000000	1651430196000000	2
8	\\xff31a9296bb7e865ebd9e68f35ce49313ab904ed345591e66a458a18161ed533	11	\\xc90c0dadb280acf3e2ae25d238a61f7e3c145abd4fdbba0629f1524bfea401540fd58ac7ecf429eada411fa8a96ed713aa9391ff116fcee81a765e750f34a60b	\\xa9fd392681eacb3b32dd2b518593d91b52f06538d7a0c8da8bc11aa0811eed23	0	10000000	1651430196000000	9
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xe5ba860e09e64a65ed3478fbb79e2ead9499bc3ca8ccb319f7e93299831afff3e9cf9aaa47d18d18b4206e4a685cac0aea178fe937a70a419e8a6b02df72985e	\\xb09a2f656719c9f96df3d5c19bdb2b6d8167c8e1e1b8444612848a8dcd0f8f89	\\x4fed5c239c9f18312feb2e7c2ce20f80c4570fbdba71e68a48a60670830699ea2000316bfad1e7005126307d936ecdd8b95e23f68aa1fae82178b4ff500c7e03	5	0	0
2	\\xca6c446494361cf1dbcdf514b270fed4aee67a5f1e0f877501f566cae55d531d2d08f0b352fce1c075212318cabc7f2974a0932eabfa8495abd22ab0aca8c0e6	\\xb09a2f656719c9f96df3d5c19bdb2b6d8167c8e1e1b8444612848a8dcd0f8f89	\\x67b44f479355f42da642774497a24402b9315d3c74a5d50c830693e4c37c35a31117dd5f1aa1c15a356d4c2a18fa9e7af9bfa699802fb977326954212a9a040d	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xd8213a56c94d18fffa3e87481be5d91d6f468e2a4294b060d279455b194c4533b7b7653c2238f86c687d2c380222c06830b381c9657a904fc208c84533a27e00	222	\\x00000001000001009e9353fb66af30f96c87109aa2d539c22c3d88d98d466586f60c01103f7963c611ec095037f9c36996443f36994a1549c578548deafd00aee60460f9399aed21162811183aa85f6bc0b279750931ced54253ba140ad1dcb7875b84b8ed900ab5f76dabcd12af39ba0dbffe8d2e91c907d7985cf2e8b3b304e698bdbd2590b903	\\xdee1aef85c93cc5e76a30adec70e70096fc5d2635b4d5890101ba460f1f2436743ae8c37cf7556d7746fb48ae4e1266cc30b7ed2310ec7c7b671c09b336b43e2	\\x00000001000000010b4806c9ec949ebd6465bcc325885bed3c2f33ee24cff1bca3722193952f0988fb1812f42df97d3c8d331c08ac18742043311fc55eea785cf7ca7700cba76d16d5747fffdafea649959cb89a7947165198fa92016cff99ceaff33436e34145ada4cb81704c307772d5e209af69dc9ea3ac41ef93b7f67e9607505156c3369a3e	\\x0000000100010000
2	1	1	\\x5511279070e57baf4e95ce2641d2d7e24b60a91804400d12cd7c2b968383808995f68a4b3db4ee422a0a71626e1c695abc3fb0ee5459348393508d5e6a02db05	66	\\x00000001000001009e71082b4995848e710e047334cbd033ca8c75d582181cd8a0f4f898a7160ebe03ff8f769dbaba0cf95c1165144be0844cd7de5f2226c1d645d331fde7abf7b9df3920b335400393a0d0aa3c0d5a5a83d7ef534d8258c2ccdeb37eb70d40fab2bf9e7041dc6b65b59b270cbf69741f974ee66a03a3f383b2b3b77f2ff6c60db9	\\x6dc1e2563effaac5aa855bb02a9009dec1c74c829d3fa786ee73825ed45c9c0a0be77ec0520d032efc1c13b3d229efbaa030923957aadaab39ac778f549e8ef4	\\x0000000100000001066a9cb90f0dfa12be2aecb510a1cede0e71d93e3952842de42e3af6a6df12dd870a79553f157ab4111de25a75153bc7a4c9925458c6bee6471694fa68a6f2aee468a6bd48fd1f7c1b9b9a2a98d414b409feabbb29c2edf656e02cac693410edf9a95e490dd1a0d5069e95bdf357f37afc4892882d5254e2b28f8e5306169610	\\x0000000100010000
3	1	2	\\x0b885b2fe2c4a1ec12cae74e9c34ee425412ef3e0950791f043bc67882fcec84ac448d7cea4f22386adb50276ae466ecb133fe8b235a98e428db3fa1aede4500	66	\\x0000000100000100cd4700cc7174d01e028ada92597580c797a872d1100fe2a42c22855424349a72b98a17308571b57301a118764d432e92b93f2eae32958790cfc78a50436d33985b8f2cee28585ed214080562bbdf81c6c527bf6e7d2d0bffbbbc9af66c0996692832827acdf60cbd2a20ef5338714ab2ba9e81853477b99b0f041891389bbf1c	\\x6a2c3463d55973a46134feb30f380e198bcd053ce3d3c21919c79d37cf547b5bbca63cd2799a44f2e5d216a228093da342c1f97db0b34c0eaf67e062a56d969c	\\x000000010000000173591848bb6d534ec1a482e16db7cc1c75ad03e61453b346b424c2160160968317de1b0d59449247374c8bfd87d1f3634ed45c46381be91bf090112929334b80ef2af47ef97135d88cca4ba26832f36e09108e4ae3fb414f1354473f6ad07d802b68cce34840ae23ef33b5dc8a5963c0858cca87bf656a25d8cf5c8b90e4e657	\\x0000000100010000
4	1	3	\\x18168f664cd8a6c850f455cae31c19e5fac84443bda4c75f761ee26dc389eb030a901661dc036238fcce27651ade2da871dc585062f597f0370a89d3be3cc105	66	\\x0000000100000100b53f06021a98fe3b3cefbfe43afd970d094eeca0dbd7eab9fb377780e5527e270eaf2779bc200c333a5f6b2d11fa74dfc14e3d83a8a589bec3cae8c680b2bac9e2599395c1226f47d9cf78b105badf3bb85b16544540669b7721aab23bb9e1766435327a681c42b68fd577ff69510761e7876302618afa4b7841efa40f26d54f	\\xc67be1c6ea74914e8c3ccd07aa907c0be5414f4b4d01a539f1c474b7031a7502c47f46f7b4209dd6b7c0900d8eaefaf294c6fd2b3970ebbb19255e89d8f7b19c	\\x0000000100000001cef2b45bdb3b8d62d124045d30a6672bc5a6519bcbcac1d5e8aa8ee2a6aa0d0439c6f8842cbd123a878a5ecd726cda6687777995cc80724cc66bc6b1095aee56f38e51a5b0a50c4cbe9975e1a221eeb731fadfc8b626a93db633b045de60a2ee97f5d9fe8b5a0cb9e5c5868bb74ea5396d0c1fb646ccd8c1a0c68a0c94b971cc	\\x0000000100010000
5	1	4	\\x84c712c3cfa12d97207b98fd17ef633d60734e1998c6e6269497056b531ae43af20e120aebbf91177e74406677d55d1aa75c2f270f314e86ff183cd956647b0f	66	\\x00000001000001002937ef59a4324b622fcac8dc21dc3a91593f298d635517d8ef3e67fc6a4590f3f0c1d789111dd5c989fa36b18ceb2db6b4bbd82111a568bb022cf8d8024cc3fe088026c8d1bf7f9d3d89c9ebe0908ebf6c3a2d71d95877bf867f6663afc9a525d07b5e63756667abf4fbc98a93c7d0e70b056723589532b01eeacdba425b2646	\\x9fe77b1d04c4fbeae6a7f320f49543d589195c578831d868ab286651c4df84e7e90db71a44347fbf6433dbb5e0bb8b4c344a66bad56c628382b5b3e3a4863bea	\\x0000000100000001def55e8c9f6103d65b5bd81fa3e9197ae0d349cc139e83e5ff629544bc2500521175bb9cd8d97dbbaeb16eadc10da634557456761de3c9d9db704cb940f511abd8d639cc9b7bbb70af71eaa0de73164a2bd67b46f87409336422c4a5fc72463cc4ddd60f5a2c9a5646960748721e04a9693792f281e99cf5886cd7ab63647507	\\x0000000100010000
6	1	5	\\x35b1944c733f104a14eed7eac91fd5d09f7c2218608bb8a2fa256267801dcfb9abe856074138fd01fe327aed0abe9904282813a7511c747457717ddbce6b9e0e	66	\\x0000000100000100211bbbd0fcc62acab7c7f5a6c2a4faa03c35f2af6ff9676dac38b0935562ed9a410e98261ba23f36e3a3a0f2c639165a9ac75e4756b70152406e29bae1a1a683977d0f3279229c0db1cc8fb2ff5ccb6c951adef713e5fb1fff3b7effb6c99e735458f91e90bdd4d07786667a5e96f61bcaefb95fbfc28e8e51cf38eb1b13ad88	\\xc8844c61220667548a22ab26eae1c6f0b90e7730a3d88ed5c671b52cfde7409232d485e62fa8908bd2d66585a71b07cee9bf754a1b0bb93561e9f5fcd7151d71	\\x0000000100000001a9491a16a4432cdf492736a71f8b036a840c9306d229adae7e9d9356e9963930180360285a7e6937151bd48d897a5566e1579baede4f90e35c17a8e565cb18ebde9e6ae49d54e0eb1031f0ad061511d52cd7463f759c4d71e1a9e4ff5a6bced1e2abafd5a2f74e84dfdf9856187273cef8b0cba0e810cdf694d24e6753c6b83a	\\x0000000100010000
7	1	6	\\xd54b94cfc02f4f6a840269868cd2b795699565831040a76ba8f6786d62b8666e4541be4eb27d59608cf37901c215ab2f7dd6b9832a994a6ae7b0758a8c8dcc09	66	\\x0000000100000100aab110d3ced675b62f9f63ab8130a80068a410fffbeacaf163770369d68251df29758653a69d305124301314e450b0fc078b42087615dd1d4f8824d9b1d692a3400f2e1a3a9839a18e644afbbabae9c8582a2a7309d2f9a55e98a17944e93da868b8e07c2f0911412a1fbc8dd078988a0b8f9dae94881dbaf3711651f9419d7d	\\x53a0bd489c96e640e78c2a194636a1984bcd25ceaee668a38d59bc51b76069e55d677754cba4f01ce153230c57ddff63397bf7cafeeef136eeba4db2ee433627	\\x00000001000000012aab55633a0d3621464956e1a24228f96c19eaf93cf1e5f8a7dd45685a774f7cc7b79522bac8fff60cf9c9b601520de8e68fdf160689283888c8f2dcb0faf687d349a4a350fd94771b1affa73086f83e985ccc7a6ea64f52d089ce3f79117ed63811936e5c7a2941bc7db2fcdcc64c8a3235af420f21fd0f7f9a73da1a764560	\\x0000000100010000
8	1	7	\\xb8d5afd1ce8fc5fcb32d8ae34527330250b9ead1d5441d05c2b84d8a75f44913c7465a953138a6f5d29f8309885e6f05b71cd8e4194f006261b14e8fc4e93908	66	\\x00000001000001002ec02b680658e51cdfa215bb38488b2672c540814a11b7957bf7fdc70bfd58ed670e543ca54a1465d0d1ad59f8a5894ca86f4417c675205a67b95d05666d96ff7da7407c5e28a6f2d27f5236ea8077006be0e4407ba7e788d587f810c5b242d808a1a2a9a0403f0e5433ea74b4959af0811d0ab8b5a58640e1933e519407ab79	\\x449b5fae438a02013a8eb0c6c9871f7a3f0472ca4b138ab8e615d523af65c4cbecfa8bc449bb8375b1b5ffcdce9aa26b2ab9f4f1ed6dc799e86b5c8e3acf9dc8	\\x00000001000000011de7667ba8907c7444d90c0129ee16ebf15c198038c6a1d8760aca41fcf91210c0eff6a3fd041d77622ba1966605cd2098f8fe6f1a3c09222cb4f3a36cd515b89530f2b5efa6ff234edec27d654003e980b564e2369c62f9aa6c9a0fcf978ba85907b6ae9192c6f21d31e775538b6aaf407abf6226d3db5e9d49f50c39d31bd4	\\x0000000100010000
9	1	8	\\xcf4565515068baaeb64a5945f1b0911c6b09fbdba4d555c58b63164ad8c5b46d6304eedea47373e9c2f76c18783f1df994b595bb8ba6f99714cae793f34ff401	66	\\x0000000100000100dc79c196058c02c4fb42f93167ec009901004b1916eb0e37a153187e8c5214d2ef0e5ce98a19942710e10e56730952346af042fd30d23d4f6913c62d475d8e5bc86fbf7dedc6e9da1287b4fd2d4d3d838171fd8089e29769f62338c0de6631a2f323a265fef638aaf44bc0c955939073693459b04d6d265cac9cdb6928be4026	\\xfaf15fa7305bd13cb024136f726331e2bb7df8d71c09b4949a206229d7332415034d04e50ce2243ebc6e097e7e6b8d8f91ea83fc2a89c4d66c0f84beb012735b	\\x00000001000000018d969ae7d9bcb60a29a4b5474ab74f8e30bb1520ac6d74060de94fa8ec9b860d241ca8f8ca10b6a51b2e330991c83e413c97ab8fbb3db53e3d9f0e05a4edb1d982ee18e9e25cdb149b602900f684663fa58d3ba899f672bea0a9e29035d92838051142dba1c63e33b0d0025c07483c58505697a401e181ff25dd9db4ce8534fe	\\x0000000100010000
10	1	9	\\xf2ff7764532b7aa150cfb803c13c9b7aea1fd238e2cb1369c897dc37e389411bff6dc58cc8a50807ad8bc4cc82c326516f1565c3ad573c8f45dc76e0dea68401	375	\\x0000000100000100110226cff76c88d8a9487c764309102926ca88e43d52095b1a643e7403bb5ce44e70db993bed747a9feb1b595d5817d3ef7e7a3f0868d92d6c00b9a858559638ed2582f5813bf8c27004e048fb40ad50a868f98515d275e2b3cd00e8a80786203ea160be447721336a442e75373c9b13bb788382b289860fa4048cd616dc26fa	\\x9bb7b4e2bfa5f9a5227c512e6c6fcb613bf786e765981846509e858a2b35fa9f4f61c46f5169ddece31cff5893cda349931be63355f776384131cd7f4be5d39c	\\x00000001000000013846f01ac0e8525728377924198add0003dfd4705380cc6839095ab6cfb68782991b9df15f39cb64f96512936851fc10086f822a28da6f9dbb86c748794904dc41df89bf8b2e4fa2e62cb8ba15121fc9f6c3030618b733b67677d0c265886a539abae46bc39166c7f11c3a917c4af2579277f036cd9763b8cd030e2908f6b1d0	\\x0000000100010000
11	1	10	\\x123d3d71b0969cd77179d689445b7310b4480b3be872d249df78d22beb1b0a4d4251cb083c8b73fccbecd324f6dbd5e7b360b243b57ab552e362164fdd2ca80d	375	\\x0000000100000100c20bf89b192385ef52cca7a7703e709866fd2e5ce409dc9d847a309da7516c444a8e06e454a83826b86aba5e80788da4884f1c17b23aeff0eff49a3123381e7f3e60059ad7db7ab35b25408c5501b098df57bf7dba1c9ba778456ac93e6a7497465f45b8c80b5a9236ed89c133c5b93de6b375761331ac0393d48ef8fdb00ac9	\\xb5311511fa61da8a6e4895df9cb3366639afeba9edf95facaf130184566ae29ab16bd2f734bb65ca74f41cfcd2697d0e3ca7586d265339fe77280f5261224c0f	\\x000000010000000111edd04c3fd05aff10fbd9277681ea7f58a7df6b4033c6993530fff4e12925c3573fe51de7080e21e89b7f46feba0545f84a46b9a62b07829d74cd62dd67bb1fb1e5e156cd42f8dc040ee9c4c8a63e4d1f2e7d42084b85c79b3d28da55ff57a4584ae6d059bfe8b86b51d925b7f9e35306ef1974a6ccba8cf114980207477604	\\x0000000100010000
12	1	11	\\xf2ee881aaa5bde6b62699e59bb86631aa14662da6a2cbe903b589e30b0d1d541f47d876a87d31f5b88a21c85a756608ee6abaebcfeb3e0899e3d8341592ae909	375	\\x000000010000010046ba33490755286677b8dedc21d821692e3054525622816171e7d143386a02411a7efcbd61451b5ce6b02cd94ae20afc9201dd7537f2573b483626909d95ca53be5c3c697ab59240546d17f021a679b96376b14fd837f12f4d25a2c2570c4ccd49dc117cfc6c198a62d92b9f9945e44d33b720e1b2c04c441830cda21d2e4610	\\x1c2d5997f6a3e0153e4118c0af617b3061db7425aba476b3a1cab578e81ba5e715865a2836bfe05bcc5df8ac1549b2c7aaedd52c2646f248c88acf61e1eeb6c6	\\x0000000100000001bc0e46ce4655d32002e3ad874d0a930ecc743f4caa1db9a23a064037fb7b3d30df2db637647bfcdf14530804ea6a397cf054ab0de22ffb7e9b56cc36867750ce7f7b4ce85e6794ba1648899a803d7a47c0df6d8daec8a7d23a145506d3535d390578d81a5ae66d53f81b1937c979292168aaf8991b6dba207be61e8246af2491	\\x0000000100010000
13	2	0	\\x633f7bbf42facf4432d19729710cfb1f0644a6ed2036739542cd02a040820b6f2e7541038a1045fb2dc5ef4cc75aff7eec99ee8eb7a28c3754e2a610b280fa02	375	\\x0000000100000100857ec90f9498a72c65ebc713a0dfc9463d28feb392603b249072ddd67ff073026bf6670f61917f2c83969156065e8f39229b19da56528f67f28aea226081d253b39d808fb0a70b7edca19e56266eb67b5e0eabb798bd79c4f13989315bb03dd32b50304df6c9472d7e901c29e1fa275550c752ec593fd27d8f7d7a874e8b53e4	\\x21614a38e99016dab946dfba76caf57cc57a9e0ffed17026b62168548296876c4de37489dc38b2f7ebd90f32892541bf199cf326d847c92aaf2cd7edf2ed8912	\\x0000000100000001784753cccdde47c66c95b83fc39231c7141b9ba4feea6a7515d1d240f7734054b43f18ef668444c43c4d115a5023573f1eb0437bc0b26445a99e78e088b0ffbbcab332ad82bd711966a2cd4bc962128be0246e3faae72b658f9fbe3a332d0cf103f8e4d6178d32886ea35df2861829d623a7e7c47b37add5dc9044bcf0a47ca6	\\x0000000100010000
14	2	1	\\xaf2e7cdfb05d71d78a2938c43faa639400a76d0b3e032950bb6e626c07d15a1ef5b65d0af727ba1ec385a44544ec0d0dd603cb871bc88781ac0564916872e00a	375	\\x0000000100000100a53a391d9115bcc51fd5cea8c4d60535a2d9497b40b6939880ae42ca8afcafaee4fd563f494e16d0ae96194bb6a376e7f99f0e44c9cb0fab7c8c753208369708b13ba50e1984ff45c9a46aa48b59d50097cf30983d5291fd5f7cf55e0ed6cf44af3f34333e28ed82c971f0a9ccd92b024829b973bf90987f6bc9c3ebed4f45b0	\\x464740efa61ffd4d6d1fd9f46b146585d52ab8ee0ec1a21dfbc78f431424c759c748ee0bfba02adfc7bfbc800bdbee1fed276bbc5c273e5fecf4abe1ac83b7b5	\\x0000000100000001899b1bfa205e6d5ad54fdf8ed0f0539532332ec7534e6897f59454b70ca9ec7fa34e8cd46cc45d1b7c427f4ac5a8819e719e156e2938d8af5cf469a9e6036413dfc79354a323e4b253e9a20f30dba598e2aaf8bd7d781bfcf1bf39ef5c780089c9a6b2195bc2efdcdd9041f6d33584c31637b3ee4714ea0ef389e239152c895c	\\x0000000100010000
15	2	2	\\xa0af675acfdac508ee118999f2084c68d386bf2dceb9b280bcf999e011f0a5c45b48c785d900db8772a6f336366ef32f7e4c09bbc3d8dfab79bbc5b3919b3a09	375	\\x0000000100000100116e52071c42cc6bde2bf9464f0aa98f663e31478305a1945d0d4608177dcd779ee29c8f649c884407d87627bef5463e8eb9f5f1ad74e5e5c6a5a17b2dd38e036e601a776f6cc971f87f6ef38eb5d94d7684cad0a4b72abdc7e2e3d564e98c8af132159505cc66c6b5b94e8723a7ad1c279369acf7d10067260ee00aa82dba35	\\xf1f364acced67e4d4746d15ffb6547b27ce88f168578319a24b1116ab33828466b5c9ed74b8160192d0c7d1dd4f368c070e62551730db31d8f7066eb0d329901	\\x00000001000000019a8bacc4186a81e109143b86e4d86c4ae638f8601f6ce55c6ef0ba2cdfc261886ea549d1ed81701e279a69ccaf6b98afa8544d917e1723d46c8f5edba233ef19790cfe2cf82b8fe28b814c78cd5c3836f77f42284e9451f2aa7865042caf8b50e8b66534b1611c74ca45bd5caae3dc238107abb163c903c8c6f0547bcac40b14	\\x0000000100010000
16	2	3	\\x1a6557a915df80ff1c3c6f3044fbf05e5471a6b082b3c69c0ebd16b894cd6ae6887190498793b7f83bbb15581b8e994d64cef4d982d86e8cd3b9783e9545e30f	375	\\x00000001000001003a3e599b309b051604f33738c2673759c467d2cb26cf1d15643f7d995ea2451a5ed931bff47ef4a7e990392f938a4d7938c0f58f2ae467b820288413e1e101070ad3f508ebe88ed5841c13b76477eede7fd1c0a1d99423766bf5758e20090a4901d691521e6c190dcaaa56dd7e92da51ec6b53eef7335897b14ab21667d60f11	\\xecf040f25326977b170513900e973740b1bf6a5b8c9dbb2e3ddf56e94563f66727a8f808b47ceded975d32d73213a5dbd3d976de40b4eb9475b6cab82f6acdd4	\\x000000010000000187de9d8e2a3f6479b17f337949acea5d4c890bb95b22e4f7436eb2de1d8cc2bc96e2af623861360b1df49e296ab6f84e0adc1ae9db2f02cf950ff7fc5443f818a7986e5e61861713376d4aab0ac4ef2cf7b6dc4218a85d4b1ff0a7e2d48b5add1edb7029485a1270e3bcf957e4cabb4336c88a56a4e82117d285a5b9cb0cb4be	\\x0000000100010000
17	2	4	\\xe1d690a9c8ca9e53b9b5b5e4152483e5234dcc511225b211f5660fafdb099e5b120e638c8133f7c23fb56eda3cb275b54773274bd2ab025e9b43ef29743d6b01	375	\\x00000001000001006e8e17ba3a3ad4e0e9c2f4d947ed34f566b3e3d14eb1aa3a37c84a925f5d0b056b4b370ea0ec4c7e534a70fafef46ee5f3a7d49f10cc1e95aa22345f4953cc42697b03e03b2ba240a250db6ba0c62e21691f4fbd8287fc18ad5d699937c73b434f7019672dab9f810d472d208dd9f58cb145e49053b0648860f78f597b435832	\\x4cfa943c5007e218f13e248c3558476d41c03c85cd48d51226bffd4dc2c5148df48521537711924b59243d420cf2ca84dcab3a8306f7d2615b930d524f37c59f	\\x000000010000000108a9dffa7b0f7e062d643e70dcb61dcdea6c61ef67ae9e1850a0eb99265b971a230143243652225a3509f9483076fc0edaef48022b9c629adeffa4d77e7eb7984a77fd03f4ada179b8e9ac07f23c124a3d71a83c4585f5752805363e363c590b55bb14bbd3f8677ab414e290ebffb1c9e42e22b7479a2a94cb576d29a8220648	\\x0000000100010000
18	2	5	\\x77fafcbcade8a3f4ea01daf50b600fb46318b56650a513aa983626d45d3a358a76d68b8dc4a3db2f4df95ce8d2dab679b359ebbc872c37db3fce65956290e004	375	\\x0000000100000100cfc54ba6d1fd4a3401a768698a2c7fa7225198ca9e06ffb614ef02f6f5d25c65fecc7bb7c6e85e31bd3cb872214e4fdd0af617f2230011b6c2283cc4b9f7e34563a0cb0ae279886e1e5f8f7ccf93edd04c6405f18d11d99640959291d7afafeaf411c6b136780e995bc62ea25ab41eed5d17c593972ee5a217758fc0ed0c3149	\\xfc55a708776ba3d3bd8e9bb29f62606ade9940a54c524e9458d0df36921f96b4da7ed2d91feff25693d7ed28467180469154b961b9a45a6336b7ea2fc592f8ea	\\x00000001000000010a7fc6461a3677b5852b1f324cb8cd991e6242d839e5837c21f60479549842fcf4b424dc468cf12a31136b75fbd42619a319ec44e9f02eff7d0ab328535415a4a336c439a105d8afa6993affd5a7c70b08ad301da1c955a21d3489ff6dbb45cacf0e767c96d24042b28d49766ba65e65fcce21b9ddce10ce2db3f38a36e1e835	\\x0000000100010000
19	2	6	\\x81fab1d7a9c3a58f237213f1a5aae2a51c1dcc978d74c2523d8a1a3313565f7e9d7475283b89cbdfecd6e39334e6c69c0bdcbdbf9e2f851aea071e8d86168908	375	\\x00000001000001007287158634aca698e62d656d005f023f2875b991478b70d3a483545cf14a893292537c2f44034d8f922a09d1ded1bc9ff2994fbee62660f0bb79887c448d19cc0043f9d05f5424ab864f8b32bbf552dd057a6468f081cdbe9fe3603d543fd6682906c70aa0f6c7a9a52dc5fb3db8a9eb948ba2c57c04b5a040cf6bb3854bd792	\\xae0f5364095de11a84fe229bf3dc0fcbff357d3d9abf4ca4663deb93cb5dd7b6f3d9976951ca41d9f018bb9016397b26809c9fbf72a7a3291afe04f85a6ebe59	\\x000000010000000187bffa413a8b12f69c4fb64450873efa5ce476c998d8b08ff93b32cb8118bdc06605938528e5c15667900629eedb9b8bc229ed7726121f4b41de8ea419ce93d7d71496275be6815186c7e05e08e12bea765a5ae0203b84d6ef03d8ac8274b3a531899a9f9068b8ed727d4ecff5f5ebfa6fcd20612f90ab0315e0b615b52a803f	\\x0000000100010000
20	2	7	\\xb539d62f2db955b4fed9dec8bb9ba7f8dfc3a17bc050611baf08c24a60bd698e2c1da5a53d465ab94c87a83e1d9813a1b1fd493144d2e4a29515a6ee0d69fe04	375	\\x00000001000001004db9e0614de4f368d613b6dab023a36b07c4edc11021bb19c4982f89710db47d6e4638e865a04153239ef231b85c58740b86962be8c70f4904c9ba447b9b3c2783e71b9faeb763578b003223984a7d0e055e3e73ed75fb8b8d0efdd95948659e23c2eea272aafc42fb36cfe92b695b04cfcc36688d471a15fb2f74f98013ca6c	\\xcd7623d06de790abd09dc3c3d7c32a8b73738639b300a0c121f082ff6cde7bcd2e06677e7cb206238624d152541f809ad123b7df3139801ac096d3d4740785a7	\\x0000000100000001d88f1fdc4ed097d1c3e8a484cf0cedd2e5d9d7b2f1e405a78ff4813d57617d485c397a23473ea7989ae74780847af408071588c0ac869b981c12d6df5f34fda8bddff0bdbb6458428fcae5969b343e85c2b6a68ff9d5f25a68a5534de1178f8a1bcb1fa4c53e7b49f459c2afef82ea401552b79b9a8c3167d8bd5dc1173786b1	\\x0000000100010000
21	2	8	\\x415587d9f13c41a74a82610247673337f1b74199ad78b35d3b353182f77988b2dd0fd5a3ca9b4bd6440e92e629fcb457f203b918fbb0293492becf43f6d4d708	375	\\x0000000100000100870aa0f7f10b34666391ee174ae4047ded2b685757dae11de5ca3fe6964c83fb9f889eab2697dcfcde2b13e9c0b5a1c920abdcdc060ab4b6b46068bb3bb0b541d60ea76497bcca52b38866f2dcec4b400d6c63fc3dbba2867eb64f168837765597f349eb0b0fa5eb3b226e2d08cf515d9df9aa56ce7ab3835b9bc5cf286715d5	\\xdb3d3655025b33e18ba90f9d7badb539fde8cc565580230dd1c3b38fbb23d08b2a1bdbd9fc2b894d4a60eb7ac75faf9321215ac29dcd5a49fb6e9f6ffbca4e05	\\x0000000100000001cb33cd2b74d5b1bafd092e23ee745eb39576ea3d96b147de9130e4f6a91ddbb5ef3216e5705416db4ea6225a48636b376c5a22a8e7926115fa54c626223cdadc816b32014840a52109f1de7b8637cbc2b95c8aa43fa14e6e93326de80eb0a6b7fb5adf9801d895e3449b88fd695c95ef116aa34fad06b698125323434ea5658e	\\x0000000100010000
22	2	9	\\x900c8b5170873eea36d7f06acea1ad34b8b056cbbd44b320fd118ea71c4be6bbae3e992ead6945796018b2c5161283776517d0a3c6c66c9512eb01f41092ad0b	375	\\x0000000100000100caaf03b2677a96089fd716fc1f2793f5583382b742da204cfa22b86a4e7e32dbc0c62ca6cc39f781c5872cd8645f9370219ba0adc5a8e804e287b4e800c6c2df8f9a6dee9310d13d71d1b7ff43cbb35a8f0b033d3b3cd3e008e79aec3150ebee763eadbdd35348fbac2be0a11a9b7ee1be824b79eabfbd1800d5782b91110936	\\xaf45b5a74880600b26f518bffe5663e47fab28b31fc12b5e275373971f8db34b79067976604695536b8e4b012e39d57b2960c9285b13fce433c9f83858b5a3ac	\\x00000001000000012f907111b7dba080c3b85ca575ea5329f7392230e6a0e879f7408fea19bc2bf3685dc427e54d8c33b860412fdf5c4c779422004f02baccc434bd365c1983a2b45a65dd691d2cf63a6e61b80ff3e3cd75d13e3f2768903cce64abf7d130e857dcb9b9cc223c854c0cbb3b22ed7ebf5d898553e3ae964388818c548ea6a3daa5d4	\\x0000000100010000
23	2	10	\\xcfd0f0adae1a8aca91c3137bb2edb1e87121a4c35b79156bfb7565bfdc5ac4814b7f610b1159d69232d473d03a07c9795bb746012cd00574fff19927774b2700	375	\\x0000000100000100827af0c1f279ec117f796aa81354539658380878e17d4a9090dd4fdf0558abeee5874d499b3cc86f84ae1fe0971865250ddfd2b248578bcbaf98fd89c4c6250c6f29e981ac06946a3793c0adbfa1bcb616ae0a39800a5d699c7047fe4375199a3cf231a472f725fd7cbc15d57214ce5dbf9b5dbb5887ed20866856758286b669	\\x7edb26cdf0dcd60aff80a3b925a34557a90955640a465b3b2365163dd674511008e37719e57c9fb2cc5a09b8f79da38bb192829da20fb81a6b709d8cb5958fa7	\\x00000001000000018fbb51a4af09213f350ab06f4d8887f11325702a91025f6664f09f8ff34d9cc5971b0f118244de7e8dae5565aa27b1ea6efcab3b186effda5b8e093692625120fcdd1e47df595d70cd83a54f634d67ec8417a1f0056848fa69ff847ed095876b1ef25864bc4ed60bfe5fc7c10eba0b274b0535c521b52df25569f47716c789ab	\\x0000000100010000
24	2	11	\\x4aeb3abfa2e6b6a9957bf3f49d348130763f2010a812532ac45c9fbe3cf1169ba8c9eb3370ad91ff8e14e147acb0d44a91182977d580df018cb0356dbebbd207	375	\\x0000000100000100cb4495404034fac8a125bd13032cd5821f0f0fe20ccffd5313345fff4a39683ace0f5f8bfa057dddd2434c2d754fb1002f8c312b3bddb0e5f2284746f9d82f758b2193b15ea70ac6c3e9171e47f667e6bec8e35674623f802714765a1e81c1903e31237f421083be18e4b39eaa510962bb8121568eb4039abcbd9ba1c2212442	\\x6eb96f92a938c8dc2baf7bae563e31b98072adc9d95912e68f4ed028d2081f6a4f401c842515dfee057b3ed18917774acf35dbc4697511e8c40f50e82b7c28f3	\\x0000000100000001599dbb6f7752c26bf6e7bfc06f962a220f0e22303b645663fd858558b4743a5d860dafb60556574fd8b8d399f661207c2f85d926cec7f67aeb42fe8a7ae6f7f3aa468060a9d6f31e1ea2e9a889d8e7cdc40f7c1205e28ecaf8fae76f82627ed52903f7ca2381a9ac49444265d238c25510eaf66631776eb516c02164d6350ce1	\\x0000000100010000
25	2	12	\\x1ae5520d6dfc1b1569e8a77c89b64cccc9ec4eea2d31a9e2e042adeecea32bed860e5399bc3e7ead41598f5ce6699e77aa13f89df430e0882b4822ede5f5d002	375	\\x000000010000010038c573a336ad05d8bee99637d6122b34ebec0efd6ba678536316ec20443ae23a491973eaa622f9beefb63ac875e7e86f524905c4adecbcd1198990deaf1467864207da0dfa99238de660d855e30f70b2c48a642557a7c607485816248a9c4817fbb3ded62795a600bb01313133e8704d2021213159913f971d942c9b2a2b620b	\\xc28d2462f8e23b1d2d88ecd5d430959f62614a8042a4efcbd75de9a023fbac05e69b4351a1eeff46f7c56a1e3e8041225d18ed4779a9b71a49f20cf6e6bd4858	\\x0000000100000001913fb5314c9caa9632909f3fc05dd3984b548c2cd66cfafb6402775fe67806a3e9bd0576894409af9d4fe2989cec372da543fad15a958651955b30cf0a2c27ac3e71cec3c044f8f5ee32534db409f382d19f34fd270963c50c3158fa23eee875da1b2287850bfc86b9e9f76926bd7071f085bc4f9eb4edb427a3160cde80ad0f	\\x0000000100010000
26	2	13	\\x435298a3ddbcddaa5f1d4197beda3dc23733e4d444045ce1c1267112027866c66d80bf8d41dbba08058a4ff77d8b8728428d455b704b8f2911dc864c00cd3c09	375	\\x0000000100000100b302b902c8a4e2474fde769fce0ffa15d628e3fe9003f519fe9d2a78fb8ed54b71cf363b656041aba967e6d7080a198669fca34117dd1a0e4ff6cc969f01c184ad769a8c6f066751665af3be84a83b0b9e1cf24ffecdb57919b6fde04988190f4eec279a9eb96d9145ef7035704f6ffe8770c4b4ded8a4b005e25622c6c79fa9	\\x07e73411b2e211d2f813b7e5def9374a24c460597f71e96e753a1278e6b6f78d991741cda4b1a8ba17a9d21966a85c332b004b07b197dc39ab97ce8360bd33a6	\\x00000001000000015a8d7af70dcb6eca0ba6e0ce0f97a810f6bd8ca56faf51535d018a9bc37ad28f79f2fb440391db0df572742d6fe10301f78f25ed1f6957fa920a610ab8963af037ec6abe391bb7af0f7565c5df72a15a928ae6bc49a2c03e89fc32434730963d1763a42506e40f1cf778e7ce065a1c1008e1b1f71419d6d07879fb0553af2ce4	\\x0000000100010000
27	2	14	\\x76558cf62a387bf2de07ab03925e849198b9d63f6f57a99b20caddebd12519785eb0f7a6e314fd42ba27bcf97b0444e697544d48321f5ea75544379a4d2d490b	375	\\x000000010000010070d5775bab4d75d36ca8d562951a2f7ebceaea5b352b101b8524443d11d3b43a7e14e15d1056bbe4d26cf67495077b73550aa49d6b1a6f8bf7326e32be353bb7c894fe83c51ace3d91da120ae8934f6fba980b4643826c5b907ccaf741880ca6cef048dc04a7c6c334c2115c654be052c78ec01f8e077d6c8952427ec342e3b7	\\x0c1adf57fa51149a768d9e49d4a93d5e0e86d4a7f190ffb247373efa75359860a4a8281ab3f33712bd4b05b14754f41b1dbe25554653f5ff17e9e8a7baccbc43	\\x00000001000000017aabebf47296e7cd0160d5ddb4cc93a510a66a41645477455c7ed16454ce72022f8382f42fa3db30750437788c73965cbd317bc239371699d1e553920c5bea72c3e702051335abeb8a337465126152d1a3c07b0f05bc8804184bbc8de06e4802d9ef38b23079aa0ce06804ad6f2182876bef30bfcbdb33333a77898d591d6193	\\x0000000100010000
28	2	15	\\x947c8d16cee151ec05717513d45c97c334fae3226d3b9c1c494915350a866db0408c2336104b34182df0b6b315618d97794dcdf8125508c3ab146a043a0f8f09	375	\\x0000000100000100666c70896834431ecf34ccf964ee5b9284f36d54065fef2fbb371e8406442b27ef8b9b80121831c174c021cd16d2bf43af8606a01496c335d0c17297b1a6bab7ffc68954639edf82892515c7881c0163a926ef591dc16914f90008217db19b330fe78011ebc5d157451a389a823469df254b70980a57344c46199e164772c746	\\xd123ed2b6dc126eb4bc48c82afce7a07a1159c20009c7671292c2d74c6ecd835c29aa49efb902a05591b6b83347cd5e7a3faa187bf4067e1929683b440236c73	\\x000000010000000149f468c2a78dec81b1c896534de4d6a50466917eaa478940f45e8647b76e5df77f86586fa7b4066b63b63f5febc1010c33fab6b859c2f3a80c7f5ba4cf3ae1542fe4ae5603ec2638ecc9e108f22973d2fa2cb798ac90fe8df82f8241d487715fb92f900e0bf3c85828902de0b7c4a7ff7f61ded24753346e70d565ba88a3bd89	\\x0000000100010000
29	2	16	\\x35c100ac15ed86a151fea4bfac7d72a0c0c8a5a3c38eb886d8ea6c03682b5396eb9a6c74971c0eeadf7fd1ba4e40e5c45346da5c24270e9e64294c8bec32210c	375	\\x000000010000010008471e51679ffbd12bcabb49c57f0cc45a70acc32ef874992442469ca420cc2374b820f7d993ce3896806b4e0f90a5edaebdd47b7bcd4a7fc9df2388e35086592b467a6c869752b86d6aa678cd8768d8d83d01c3a1c6032239e9871b8b1fdeb98ef5383275031fba13e411b544a74d0829befdfc58bb250d59c68128d1370a93	\\x14577b308703f39d4a380d7b00fcce3cae9db839f834d95c0329265d0d25683f533e29b1c03d3cbe4ae564bba6b6a8c8ddc12120c3ea201900d51df858ad5d11	\\x0000000100000001ba9e3b65e9dc17aeafbed85086e51e922353f16a2301a2c30aa8816aa0dab7a29738dff748090bb84b24cbec609b2aa614a25d23ad5ed0b07b8265fc591473a1d18328d4b08998d2fb042206a3840c3f8a96fc7de0053c9112a43f51f1e668b0c590541ebfed216dd0f342164bfdcd3f2f5cdc4bc3c0714f23e2f2c773227b74	\\x0000000100010000
30	2	17	\\x4394af18e765f0e04346c27d1a3e15ed3e490c18c7eda9b8173d564023e46460f0d709a9f5e02d2b287eaee3ddc2ca1855a905ba54e3ebe662a5783452c31f05	375	\\x0000000100000100b264594bd5c3a76c6b560f74a63d7657c6b5db5f1bbadce2794d26b7659065f481942c3355d2d5f2c86154fedc854258510cea84e2f5c4f00b97a607fab3ef8291d2be06c79ffb62db319ec56da0fa1a0bcc3650f0eca9b6d255a9e7ea8ccf4768360b32091b2092621eff175d7d3e3f3e57215c8fddbcdce9f22c4a8f40677d	\\x77bb8e83d5c319a2a44a55100f1aab4c45b4f23b65726066cfe33e48d46184137458c1f30bbef8236e7e8818c68b9581132a0da21725a414a7635c40a8903275	\\x00000001000000010d83a02c5838434f04cc1874d94755846b75ebaa2325713b1fa527773b0fd2ece1774fe8168cf38345f028aa42f7241fcf704fd8dc3ce614e2dc165817fa5bcefd40892df1bacef270d49703ad52b2799285b811a9b758ec2bb4a8c705b8b6d616b7c553385705cd7211e236ab0a49dbd0b0a6573539addfd558a810008a3b27	\\x0000000100010000
31	2	18	\\x88277df7238b7b8d6454f767c388117b2ceceabe7bdfa2529797c1aee94e4ef916b65a39e78ba5451d4c10e9b7346ba2f5a9ca9fbfa8c49ca54a170470bf1b0d	375	\\x00000001000001000cca37a1e12e38729528cc3b90583f49a7d29fdf77261b4fe9025ad772c086492fba3573875ff87d6ae46210a97f0104c4f05e93e053b1eeeb1c86768c226751dff8687d83f56d7012440b40596fe9ee17fcd07f86d8295a59a82a0c051fb9f6042d39d293429342e7410fc4e910e306dfbabd75a5663d387d0f75a9f1a2aa6e	\\xd988e542917d0ba738d992813c06036e2476706b629116d0c2194b2dadf6d0ac9f7623f4aa4f1ddc8bb6a4e8f9644891bdb850c476059e86005fae4b50516844	\\x00000001000000015ef97f5fd84cf4686e1e138f3090cdce46bd2281fe8476ecb8dd1b1ebacfcf36010fb55f6e6d61c857c1c71e4ea787659716db2305e0c0764813853ce84c7b06bb39812d6fce264bfa6718ecf4d3f1c736c3a5d44cde02d62652f0fbc67ee1cac95f8713b411d6546ae72e52b5f3f6cf440a538debda41bc15e28d8540edafd2	\\x0000000100010000
32	2	19	\\x922f59eb41481be7478131d1261f0ce9751706982740cd2b3b235c5c13c8548a8fea97cc95421bf877be268fd4d9d2eda10862abd626507fe7051f4e12dec003	375	\\x000000010000010021c63291e16b1e1059ce920ac31c29533d3520c245f5ec10ea376b7f100b40f4c8af43751936703ead5277d5a6b8153842979a792ad2974ebc6fd7db5017f6a61d6fa5e756346746416c569f86a7949dab35c047cd1c5693e353dc1f7b63d014f61925e037de24a82c60e6f9b45cf0b33cf6b3340d33844929d977593b0b5885	\\x3ed5b3763a3940725dbd0d69fd6d5ff5f4a4420bc3d42e12e6bae6d50a89e8cbff3f67285f059ea57136531b5b525f4f3312c02cc6346417a567b027a1f41d1e	\\x0000000100000001903620edd4d099266c178d67e652d84d4ef7dc41176d9c93a341e01b79d1d7e740b2d7506603063f435c15f12f7f3ab79b34f8bdc8a0f0ecabcc5a0bd36ab93595f2c46bd47bb1e1342825afa800fd9b330dde6fb1fc95670524e7b038aabc9207c939164204da786ce4142cf2a0947d9d55db572e2897cc7b52aa9cf35366f9	\\x0000000100010000
33	2	20	\\xd2b8cdf4123121fbbdd87b1e204000f70d84a718693e911de951befae35a10efff28bf9808f75bb31de7838c4cf10e4d1adb8dbec6584f2342bd77c3adab0a04	375	\\x0000000100000100bd4a2054b98614d5770d0bdab9110e011af46ad8edfed16b781f60c232f8b9f58817788a34020ea70edc7373eff6ff933a265236bae9cf619b195caa98d87886309916d272cd13ab6672863af86e194d492452354339465b51c674f6588eaceeada2b4b93354ece822b2875607241fc4813f9777459d1cc08787971685224baa	\\xaf3bc6aafdcac2fb98d32d78d5c374cf5b4628958210bc1910c276284ebda36431ea2e613ed9b39d6d2c48425bb7e35175991a93a7a903b1836971b0e824ccb1	\\x000000010000000193bc7f9c4e15a74941ebf0a4e1b1749f5f24d489ea81658dc4a8544396f8203049725c2e7243e42d0d6d93496e00cfde13d1e6abcde2e2bb4c0f8ca054bc5c740c76c6921ec4ee26c19284b464f8054ea4b4350ec0bbdc8a83edcd607b06d710be2b0c52c2be9f83a3adda58d47f4dfa6415de88cd637712e35fb977afea0dd6	\\x0000000100010000
34	2	21	\\xf56a55303c4aeb387302ef27e3ca6958165333d841d013318d8601f30a0f4bb8606179b2c4833f15ffbb44119b20ee16725b6861918d84baaf8d6c4ad1a6920f	375	\\x000000010000010096f57e7cc00cdc52b6a819cebe09757f1e9e8d8e79d946d0d83e0ce18123e7696d64aef2ec980ba9730f7018865974a879032b5aea5789b40d33859627ac62db63137dbbe1bda5ec988416a78d634f722690d0220c1af9eef3023bbfc9fd9d8b4f3d84eb3c5c620e4e7b036ce7e1d2e6d02fc7608cbcc6b194ab6472797a514b	\\x5e3b7ace70f2329fc644811edff76b5bec59ecafb73461cf29014da89e7cf581756af24caefb7e5e0e3090b099934c47883db4ad9df64f01444eb6814db7439d	\\x000000010000000163d10563ab8b90d6827b6dda1d5b051b3c14b4fb077c8bf1b786b48536f4d1ec2d301fb4eaf084faf55c0cb9819035f7cc3a2fe37261d81c5949777ee129133bd469fdd45c22fac7b9429f1953eea113d376f808df333a8d321831db9b9ae8d7b294de543e10df31af3279cc31585d5ec44e61b8d27653f82e9d97ff787ea96c	\\x0000000100010000
35	2	22	\\x4baf17a815e8b42c85af549e10c18e4d01828bfa83b9d01b65e1a8107c1d074ed43f25194a778f76105f006d2bde5e61d213e340d64314de70854ca7e0556508	375	\\x00000001000001009e578c18db2c67e7a550ba82267585e0a90cece565f32deb71a38e78e97c7beac147c7f8809ab9ee49364d8c60b174805193b41fe5fe053c7ebca01c9d988474f8a2a620dad3c34db953523b0aa7d9c28a258e44a69d6d6890bde3e4fb2600bacf9f26ecb38ceb8dbbf5f5f20baabf747a1aea3426f2d1aa62112a5ea63bd1fd	\\xeadc0c0f45b7e48873fcaddd508032e0d16db38a14dc3ee7b330a1815b1943a6217b16681692c1ca6798e4290b9fdaf75938a616f96d85376ceeb4fc8a062ec7	\\x0000000100000001b235711591c9227fc261dcd23e7974c2e343bfe23fa54c982d626ebecd053d4971c0e942c9e2c20431511996da8f8a535157178bce9da70d6e90eac8999ed73183374de3f7072b6d21653989d6a89b37367615110a5edbf3cd8b754dc85e24aa354fb2ac40c18f4f5f34bb991d95a66ed5b040776fc95755821925a5fe0d3c6e	\\x0000000100010000
36	2	23	\\x50bc692e33ab2010c3badc05da7fed8dd4650df1d4e14862f99c25c2f7b8a84279ada873770f59d738163d53ef91bf3d9a34ddebf027f7b1d79803a86a326f0a	375	\\x00000001000001004fb79f8f1382d4159113351cc0056e18f4b49c6b9a31ea22a3ccc9b26bf6ab688743933a88743bcb3f0f14a6ff2a46b798595a039b326456f8f03d2c64e72869ccdedf37b602aced1749c4b633b50cc8ed45f0dea30c1eaa5ab086af9c4d110bbd4bd3c61e4055e1c55da5ffeecfd7f6f7796ee4ab3058dfd765ec77542dc557	\\xc68201a43eceaf8581235d093dff0ca53bc2126f4e5e457dd84698249372402a54e3625df1ce1c608ccdfd45e6f9373a6383a1e0cd9708d5c90da0e3cf8966a6	\\x0000000100000001666afd3c9f5110718a9431d628e7d3cace88a2f0c9ade68cf43d2cf9149bc9fe9a9ebb7e835c71d880de50b2f55243be1f04ff26989c4a182faf1beaa63b78d5cd7f4c6ad38142b8822ef112854e0e18555beb1635df2c172d921f3d8ad2a8e2f0535da6084a6e7311ceabfe66148fcb0d44595bd11014a81fcdf9b1a1172c61	\\x0000000100010000
37	2	24	\\x925ee460f3c1393ccda344d00d93b07d6c7f4e614de045e826089cddaea53d059b997cd9157b18e4154ff0e50b73292c9ba9e20672e3d190089887f19e69ae0d	375	\\x000000010000010017f884bfed6e4b423ceba2b5b3898c3c03bd31d66bd512f28c9736e3cfc33250011957d21bc7a30f1963c741a2972a18de1f79cb6eb6acea65857a8dc32fd6d8caf8ae71f8dcdc8487e03aab1a8bbfe842eef90134a206e699c729ef17a7ee7b1fb6c4e4d63d468c5bcf039dec56a2de16da28d8d0c5067e7234b46721fcd1d1	\\x3a11fa1fc083247da97a5b850a548cf5c3ca3228f5f9085def38c50d35e7b3caea8704ae846822d9712bf1ea76f950dc68768eeca7ef8764048da804f52bc708	\\x0000000100000001c889fe087dd8e1a7bb6a8545c0e67feeb7de450ce9ebdc4b956ec03adfc1d3dbb365c0161c15f727af89630093fd7cfe5fda2548517fa9272044d804d9a210729b37fe541f846bb74e92a7c9614b50138408d288a24ad0e0deb1a82758f617a7af9c450f80fc7060f2e2aac534be5cbaf57a081b56d8e9bb6f0f98ba364b52dc	\\x0000000100010000
38	2	25	\\xb75b0da1eb7708c60955e98b0c47653728fead65df3cb3fc8244c87f8192da263a9506e0d04baa8f024227494f9253a514b0a5a8200cdea4e9a88e83f19b050a	375	\\x0000000100000100cf614b98e3891ddad823353cc87b63c1708446f65430b3c5d9f0c0aebd5961244ab637bbb4be5bc2a731ec6dd0da3cdfb62e2e17a6baf21bb397007e71449db1c6f137f9633b13ee2d8e923af36f5fd694549bf47d7b7abae854e8e4817ace5a29066c12d70345ab444e75c881566c22641b05c8af253792b1afa619b8a0b518	\\x65cc4128b788d07411517bb3d9cbb3bdd6add5a0a357da33c67e29e7ffa620b85fd443bdf8918dc98b59c67c8fcae5472d22b6bb38d91f4e00734a2306b84674	\\x00000001000000016b6d2c2f42516b6094921f36a9124b4c39f22ef99d6928d1a9d77d9012226e02b7867b2c5b316e582d8b79834681285ab167c379137ab3a5b44119a631fab9f9e53ef64590a7f1382144c3f63af11d678c7ab164dbd8e6d2a54cf43d1e7f3f133e16f8a2de52d59eae2a45b864f7b0eaf57eec86ffebd863d4ade7ba16e92727	\\x0000000100010000
39	2	26	\\xde92277506c2cc686508b71eb7a72f96ab60f87d193844b84d9dfadc998053516064a04ae05109d623966f06fc10884a260c81a8a116076b4e76b546d2bef106	375	\\x0000000100000100c7c5d46117cd177e7390d5d08cdebe4d8adb1b6aaa80c013114883565a5c1c2577668dc41927f7ced628d9c1d151fb16447bf83ab30f727c95759a6c002da210f2c665efba4c31c141061120adfd9077e4673f317c621c68126e98ac3fd748f0105100bba0b684d325c6b2abeea1e97ebe0b71e3e4e85255e8fa02fc425986dc	\\xb787c9ec822cf1d777602483436699e827ffc0dd693b18cc47b6914d1f1d4270f912fdd287e87be3c61d3f439787af422fed809feb3459213c4c9e580a12ed85	\\x0000000100000001208a8096cb427c634acf72b49e40f63dc3fa515d52ed6bc4e93fc8ca2665b47162d6dc5594c954f63d8ee96d478f0d3b824e51557c6cbf2dcafe1cbaeb02f50114ef0747e4b3f6999400a9331fa0b8d9a01d23f8c30bb9b372917f29ac16426ad4478419900f859acf624741c212de2d0cef62c27424792421af7a5a071b08ab	\\x0000000100010000
40	2	27	\\x4440b3a4a869a75c6c5c984b810dcb3c5ea3b5f0b49adf57ff6612f64b1ebddfcd4601fe311c0306aaeb37b1ef4c170cec43a1975fdfb319498cb848ab908b06	375	\\x0000000100000100a4fbea74e8512cdf71c0a50fc6a5ae4347223b328f2bef744d42d6e67e8a7d0b096f4e0dc0115861ac74fbe97a87a289eee25ecc63b65c8fee60e0b4655d5257a47a3877cd1eab9f8b3ac50493699d32e083ecf94a1a93953b04197dd8908d4e4cf88ae071efbbef4a40c80b68d7c310e0ba6fd096a82c35e84a6fe927381ac6	\\x8f21d9d012efc04c2689d79f2f28c1d7e0956c5cdbc56e31dff8bed5878104d425c756bea662b5349e8e8af4408e176818f8c8f295b8a5899f34f3ac2b2bf262	\\x000000010000000170924edc802d08c55437e0671e28224486971985e5c22ff1728ef4d8a41def541c012ef191b8b06d3d6f383c957afa936d382d2abd098b25b1b454672fe703fc8bd78d676a980e8e189187fcc6edfc015f95201be51b0ee2d46d95db002c8d960790cf6ab13aec0e349fae259272d1e7a2e3062a941e93ca5b1b75bc950d6792	\\x0000000100010000
41	2	28	\\x62b5a50f6ed1436396504f9af27f908911ef899b9b3720aa785acc3e1c1864e0b164fb25c8e3adf86d72135e9b9eb32a95187084a973314c3d8cea8a33dc6401	375	\\x00000001000001005f8ac44ae8cf8b546e14f70fa229cfa1c5d8fb5013ad0ac69b3211651f139f1a06df0b218b4cac76e8d224da01c6db6d2299cb898b2770a5d4d8b578c6ea4b72ec1d419dd7f68ccc11484aa21890266d9f1b5834d0c3ca011aebe59b723b4b76968a4a2b0edea4235c16d2398727b5ae6f26b3ec2de0e55f94bf6d5775f7328b	\\xf178b5d537f7b1603dba5b648e5a4827ab060de073eedebde78f24bcf6d6dd13a65e3c6d716dfb7ddb7ed7f57ab919f32582d87012795c49e403f21b37f68edd	\\x00000001000000019bef28dd0115d05629c47f582b502e4e3ead2a62cc6b733977cad61df72c2b53f0d3e80819cabffeddb8ce792599b0dd1d4ad4fd8ac06f45ecfc6e29be644c7db2b075a3db605c96d15e37f745689148345ae1ed249346ec0e3866200401b60acf0ae7fcfe298f82afab8d9266bc00b7bb8a52b4199a44c803efa9d467ab16d8	\\x0000000100010000
42	2	29	\\xd3321e3fffff6ce089c0df994e3a33889f73bcff5bfa8f64269c6808f9b2794a2ab3443c33bf8f42806f26340addacb9eabeb9d66278c651e367794b8507930e	375	\\x00000001000001002f1f660846ddb2630ab3b62cca2c9ca1abef42b24b9be0f9fa7b577e45b9aed9175b9e0b854a650c4b047a617453bd4d62f3ba165a230309bc21f493c414da74a741ea12a4ac37c62c76bff39b471a684399d5eb11c7fbb36fede6f683eb4f00b30d325bd112e5712e12c23cfb7765aa10ad617a6dd2e5c326ae1513bf005ecb	\\x10bc63fed1bd005d6195c6b7908935f7b0e80420fc3532438c3163856f00810192562dad8c821e1c389d418d2aa1bac79fbc35122ab9b32c9bf9da133a296adf	\\x000000010000000199f4115b0264f0bda95be67d5539cec20bbc2134ef253f42fca42c932016276485cc7383dcb99c1d0ea34e970489a3f4aabcc89497f0d061a4c08ff9b7b266be19c070cee8f3d0985618689aa0090e6346edea01a7ded3057d683ede37226ed5a09ef2f13aa75a80a7f22e0139e4e6f2cc5ea360e1e9561044697d288f6a9d0c	\\x0000000100010000
43	2	30	\\xebac112e79c84a4d0ca4386013f669c52872d1ae855872eccc3af48093e21f805232c9e11b36ad9c2ec10edf08d5617fbec315c4139bda5952d8d1c87988920e	375	\\x00000001000001007859c1133bae186750336a91275f5476041b59a8464604dfc3091b9fbf5feee3f6bd0dc93673e9869465a8bb807fce4bb28455ad8baf16f6dd30668cbeded0e9e3d834d0bd9b50d249cf46a3747086bdbb6d819b64ff68b3dacaf48f9435ef150460e80fb8a40f510b9692f79998be45a619a2b9067e32b07848b9bc058543bf	\\x26f6e3ca859708f3006d12894ed841f68bc43bb9d8b059322c3d8558de2ad86ab84a91e72983a84ffa8a9e34ee2060106fd5c48398865e47e8c49cc01f94532d	\\x00000001000000013abaed82834fed40709494afe2288b4c50e337c0f60ebd8c70918aba1cc7f2267ba6e1bce49654ca422d5ccc0f9a39c0570eb60f62115d71935f62ca7578aba669d1ac12625c18598f1ba7850e357a7a596a50834469a605d92bd33906ea69f987190169e3423fb3aa17c7b6aae80c1392cfb0ba48b2098066c3e303a5409939	\\x0000000100010000
44	2	31	\\xd58235cb69bf3891f40c3d7523c3f215f28227ff765378cea7762ff27ec2462374cfcef38aa2bbdfb8e3b6f9009620a1b150ca22a730ebdbc4eed4bd3c04bf0f	375	\\x00000001000001000a8b71ad1af19a853e65d9335735e30c2b73882d7c08128d1f9fbab1113505e90bd876d5182c36de6bedfba343cca5a12e6b5daf89ef412a60923fae1c53b3d1fc72af3d3325bab6d132a54aa344fffe4945e634a134ee5f0d115c4eba6cbf321b0e826345e61d367baf693eb0ea6c1346aabe0862faf81547f427ee04a9c300	\\xb5eb1454baf90ac50994dd45fe610c17824138ed1fe0d9d744edb76a0d1831c78d035ab60dbea140af9fbeceaf49f334c15ec0095d6c2ddd2e24d7b6659aabe9	\\x0000000100000001c8a07ed8c845fd75ba14244bb6d3226f1d00df8c8a4c8efdc0a20635f00c174de21bd3a5805101dcefcd999efb6476ec423cd33d95c59b7a4a825d312c0f04e8001905f69a8bc668ce0ac4b2f4993f57da8a121f5d5a77b2ae9b48ff48a79523725d09afef9ea4b757a61c467fcda21eb452c51277bca6e9b92e58b5f87ecdbb	\\x0000000100010000
45	2	32	\\xbab301b79baa7e91faeb07d930dcb3514eed14c632c75cbf1d87bdefa6564e89767c7f332b56202506bfbb3d512e27cd25d4f4fbfaf33f7a6e2950fe61bf730c	375	\\x00000001000001000e2f1f79ac7203caeb351037169ad2bf68a0a53eeefbd70ec418baf97e5c4cd39f95168ea5fd27031614bd28d37a8934720218d64d0b28b7144694bdb8aefe2403ae516b119086acdcb9882377db1ad83a870ac799b4fa45dd677ef94a30c5683c137a5c1a5d28e044985c68ffab48a35272fd80e63599b0e9cc84d84217f300	\\xf04612c437fbf9a0d9f385f57283eceab756a8c1f24d9696e17ce85bb263f10c5593f42e022b4fc0d1fcb3a85d30367cede4c26a3c1516e6f18c549c7a7dd9e9	\\x000000010000000101d6d0f02e649da87f569ade6a9cb7481926f80bd0901cd4f6594dfd4f2b48c8846bc75808de59b53b0bec10b7b2a4e74b6a3cbc15f750cce46f7d2f684bcfa25cfd1961c05de758b74c12bbc954b1f4ad59caf4205a86f3a819c27b4ae1adb38b574154dc8f061d489b153473124f524a315c09a3cc3f388b4077cc46dd2e74	\\x0000000100010000
46	2	33	\\x316dc4871ac6ff0361e28fe139b5ac6f8101bccdcc5d5a6b785ec124de6ec467d4c4081b1b99ebc49fc378c78493a56e4dee949d75601a26d1b8837041cfd008	375	\\x00000001000001000cab4fb0b93d98c5a1242bb1c9efd3aed222c67e78bcac590b9faee544dd22ad817efa718778987081753deb288b85f54be65ae8b8178374e9396bc2015d3202fdf64c4ba8a3814e7c8ce170411e4f2941f18614aa8b08a36ceae193e0927982d604f01393f636e4d7275ad59d43428f06d64edd498d180c0b56a25594b68277	\\x5df1e42f8230c0867177507e10a662bd381cf2c88ac6f0651f65995dea2d9233442a245a69708858243fa78acd896b6f382cef52ffa97da3ab4b28c136daf574	\\x0000000100000001137ecd02087e108eb08d5bf18ed753bac27d82a2a01159bdbcb56b8fdd51f25e24eba68f38b004a6a92893c8f0ba56a05890c1a9a7739e36653e4d6f5e5cc99b71433c4156548eacd04f9ba7edce761859484bf9e047a792a6087e8b1ddb517c6f2546a306554d44603d790565615780ca81720fd88686f9994630eab7b5b31b	\\x0000000100010000
47	2	34	\\x123628fe0380cb22bb9403cccc9e68fc41283a62b552672a0babdde2886bc91393a76dd96d858bdb0817b195fce12f5d626d5d2e81660e1acb4d0791368c8c07	375	\\x0000000100000100cd316924c422b6d71978e087b588201efedc3e50287c1b33f2b26e865298f4e01fecb0c77a4215a8bd2fbce734e59d91a3d27299701d25b7f871cdcc7c403db15e8dde8b1dcaa3053e4402e99c892cdfeb39aee8f91e8487ab802667c2744e35fdad25c2548d341ff1142c74c345fb286287a793912685d913e73ea107e5af53	\\x04ad9f7b2408a3b2f1248efa22518c205aec3cded794a56dbde276d667b45aa70650ffbbffba1f265819abbbb9dc1dcf4fa75f7b87e0271346d47f241c190f8c	\\x00000001000000018f774f0946eb508c1da32f4955638d94583b1c7103faad4937ae4b65f46a37fb75e1c17a813465a6e7867a4894dff9ae3418cc58768625890d93448f71bca8de9760c3ab4871b498485980e7aede63cce9feb1d01785dbc45968af8f49e4333323fb9dadec3772c82a94b51e636c274bfe11d4e73ded167bc1f2747049d8f8cd	\\x0000000100010000
48	2	35	\\x28cb6e63aeb71a5f38b26416d862cbd2bbdef0c31c7be0ae9786c121e5f83a1c57ec6f9e432f2f3a287aae479b470306859c732139fa68d214071eee655ec001	375	\\x00000001000001007725a89aaa5378379157c8ba715808dc6d87c5e798e58d593120e816a968c75e9a138a720292d8e781689b26b09331818100b85d685f5f2c52e2aa56a00b705ec143f6fa4f3293b2907b707d73ef0cb7589c1548fd3aae7bfd55fdcf26ef6bf01ceccf7d9940c8de03c3287ba70f3c62b5eb77269be1f4f95f9481c556ba953b	\\x386ea96437a8c67dd50ec95abcfd77da43a31523a95c5e8bf03114976a1feca7b2ed458fb0192b3da2d0467130a7d6fa15a6578ef412aeefaaabb7cd67250959	\\x0000000100000001ba3e2530ac6f532b75d6ab743571d65e0eade9de8425d9897c06db2077408671fe7817691e961fd55a1181d1e510aced65a08319a803bb63cd4721c8b7c4d3d2281f273342be257620865a7cce93fe5d0bb314c3c4244e6b35b46cf4a228c6095b9c1e6ebed1906e7c5333078bc5d83f76cd6bbed3b58cb87233f7452c9b4e50	\\x0000000100010000
49	2	36	\\x178847cfef4067fc1adea1b044019cdd7505f35d0678491fcb2a4958c449b2c029e9698fd38bdb9622aed91798b65dc06f3cb838ba4ba91ff271134ddfef4507	375	\\x000000010000010074abc72935c724b36111c349fc9d58370c742e8766c6bcc8ffa102973a31ed42fd1e1a498cfda9e275c5f6db04174dc23518a25bdf370067ba8efa2a04f0f8b9366c01daf49401a53fd296dcab1a572dc91d2868710087ed660d9471035100d17f80d6fc328bddaab9581c11b778b92c21daedfd0fc5453166c76cf9b827bb5b	\\x96682085274cebd8343919bc2c7ecaebd6f7a442ba48a71ed11000b9ea6b85f18fb88eba72b5657bd80791453e5a4bd88c393f2d67a1bf421c2b882be0be46e5	\\x000000010000000187fd26b5ff174e3b23e20b5b9cb123439c603bee8bcccd11ebf41f82676b7a09e72d827184f3e89e978764acc6a038622155ef07a99e86731bfa8fe6209948e04d16d657e31b440cb03532570bb64dec8f9e36a5f62981337a2406aaf76366d40a461c3941d4fabbfe7fe6a3e832b66030c04890941aaec11c87802f2640f03c	\\x0000000100010000
50	2	37	\\x1c5d38ea4ffa592c69031680e46763f5eb76c0a338c5ff425b929c8bf88216740775f9d0c21ad4bc4baa8655d52e5fd714293ce381a0c25656a773dade926604	375	\\x000000010000010036faee8b09f146ed0829dd64f2a63718acae7f5ed6bb00fdccbd8b91456981f308315d3f5ad0ce31bfae232a893fb7e90d5bceca89e1042ed324aa84871dad98ff8aeebeec9202a37f3f1d58cd1c9269a2905acebf6019df4a886e9f18a1313e5d8b90d7b08e1543c6a0df6328f066e3a458cbb6be45b08925fca4a511e8db86	\\xc1d0f8358575c2ade14e4dc68a660216ba74070942e989063dbb42bc6a2f2a54af8dd8b0513ea89a725bd7c0a74f89939ddf6ab2c6063e0e87fa07592c1ef466	\\x000000010000000159aee4206c2445d4a8c015e35cfcd0b66d11a73b21b9e51fe7c2e918ba591484e765fdedef6219b18fcbb4613d143c6a54b995b2f54abb284f230d1fb6485562dee639be5b419667810d05bbac9ba9f5ab6f2be8a0eac3882ae19eb96859bf019c499f4416071ca04d52c8a8bff974f77d5989a1e204f89d8eae2329b2675db8	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xa3d1cdc2928831869c992e31192389554d95bc85e74ee887174c1d2c837c5655	\\x84c90e5ca21a93f0307ddf0625b4edc4dd84fa4bea6364f4c045c678c8c91637ce868750a5cf7bcff95fe0219e6357778f6796c7bde8e5e6dcf8f87ec53f3228
2	2	\\x1049a916f9b925c43574bff656573bf742a59b64b0f8aa309d3c5eeec9563662	\\xa6818beab833386e93222ca11bfe8ae66c479ac6e3b2da03d98d2355083493d6c8fe50b93a5913a74920566815bf962e453a43b68cf7ae959965ea08419d39bd
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

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, kyc_required, kyc_passed, expiration_date, gc_date) FROM stdin;
1	\\x730d207201cefc9e8ac1af141af19cfee89eb4eb176f8421d6c94e8e9208c6e3	0	0	0	0	f	f	1653244570000000	1871577371000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x730d207201cefc9e8ac1af141af19cfee89eb4eb176f8421d6c94e8e9208c6e3	2	8	0	\\x54e9c6c598d4ddc28169000003d713b23893ae867e83b804943d712abe0843c2	exchange-account-1	1650825357000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x2c693c537105ae291a253f1c8fee54f00113ce040b4eb9b2ea586d47605cb8aa4516b634f6aaacade48f38e7f83975c92566b8450eb506be19f732980383f47e
1	\\x4d385218f42c01073994047227dcaa6afc78c5c345c5d5801d79415ee62261bc1a2f2c68477a8f1bdc50e66eab8e073061be58dfb979f9462eeff1c5d0d7749a
1	\\xf34db4912473682a103b437c57db0184cc251ec901c0686b5f19314363c622a97a450131109cdeb12ad427637d1615c42b2ea7d83a617f3f1a8181630809a020
1	\\xe917187ce388a5a0255501a1e2d7b4022719e9a607f6bc242026a8fdc438c677676d218ad8d7f137a6614512a2b460365ffcf3daa073dc54de7438e1aabd2ef9
1	\\x8d86f37d8cd2275da0279d0a303509f13edff29554721566ec874bea2bdda2ebeaa222d110846d39eb49d0e89d889e8e51598140802420399445e4fd6db0c30e
1	\\x83555f217ca3d0cab92c637f7246127a9c69ad0c9d6d18546241ddb5704489239813df6c9c48a103c7993e1dae92da143d056a42acb9e7b51e9a1d082db49681
1	\\x74c99aae30c49b37ca6f99ff1ff9ff3d263d63a27e70ab629d70591ad7d6fdb3e357bb356bfd1d663166957ae6597d00e18685e546696b765d634d8074053afb
1	\\xe307899aaacbb75527d7b1991fd83b0878bb12392e4a1335eb3137ba7f08a4c28863abece180212ccde48cd166ab58321ba6507c9b2d31870e902316caeecfb7
1	\\xbfceed456f9f94b9cd2982cdc50ee34c86665b81cf30a3a32f01995db941a64d93109446a8c17bc83007e862557319d95b7638143cd596444b08160099fba891
1	\\x92236d68018ca3336ff342dc6df663f98fc44843590047e3a204194dfa9812bc00eacd1a7381d6cf8d77f0824083e6494cd66e844882e497cb61c30709ad469b
1	\\xb5c6006d65d0c27ba2ac0ec9ccdd3a6397f1391ecca2d2df3f28cc42dcd33ce9d4f582815feacf9283c5460990ae37604ccd197ff1d1df619f7e1aeeeb31e62c
1	\\xceb054f90cf71d5748392505bb58e99211bf78c6cf7f367710d576e1ad8ccaf316bc1c75983ce602e8477334baa6a1642ed1a3cbcd336574fd66467ffcb12e47
1	\\x2293c74dfb2973bf1a2cb2d725c6c07064be2855aa6441386b9bd6c04b9cf2d9cb202e56e81a5d860e218fafd51b0eb48f3fa625b4549eb0badd9d1cfd81904d
1	\\x3011c607c3cd71da35b835121d75cafc32efc761783b90f2e5c951878bbb306557f925ebf736a875c311f3ef9d96e5bed0f1f69daac3521ff7b36180399f93a0
1	\\x9695dc85620039ea7b0295b9ae264f203232efdf42cf49d98afb4f97d17536efa6861e5493afd3ea34466d03fa41d118065146db82e795af69eb17c08650e722
1	\\xab8e9ed79ad852fe0afa868a82134e209171ae40e16b21b806af60cf375d7c7c6f898506a3087ed04b0f5d5678cd3f3d4aeaf0acde1411d79821eb35e455338b
1	\\x8bced979438f1279733be6c305163380a429c996287c77f47512adc4592f743d2f0cbe3dddfdab8224eaf5b307d3dba2e8964abf6191fbd6ccf0b494ac7da45a
1	\\x0d938ef48db558130f56edf92d418436426e6c3d330f2a97944084c2a09db7eb86da333c316f42726fa93864805eb8448f25d74fcc720a6635a7d34a4d51368c
1	\\x4f234119b617d92f744d55ba78efffbdf39bd4f23091e158c37ca2722b46fe389e260256f7b6b1d3c62744f19a65d050707f3a26a299077636e213f38816108f
1	\\x84c14e88388c84aa0bff1a491b4ad29f77b9c4e59daefc5762127dccdf3135eb4cff8b55459c520262a0a9a5dd50ba898cc24f86cc6775961c576e76181c1ed4
1	\\x84b552e93fb3a333b9a04b864bec24115098b0b155600740abd9739909b29d861a9fcc51bdec018109c4ff0349189aa356cb0436d8beca398e12fa8ab61da5f4
1	\\x5cdb435098c697be576313f5f877c4e9650e5359bbf1e3a9d5eccb22a02dd957d3f9d6a2406a5a258cb153246c6640ecaa3e65db59d378abf3dbb10337d3ac23
1	\\x4948b0f020c3233aef2306cda3101a317e49b5a7eda7af3e48dabf7e953707672d898d71baf6bca9581b1f5c9133c574e93760fd7567cab9d4afe9bddce36e31
1	\\xdc43f6d55df236a65fa7d9f4b6075907c2d72b552da677bb4f25893e8023e6d63c132bbcd07160090e6b758bc15e4dd46d72cda4750085b12b658e9b8345dec4
1	\\xf5bf35c10066d2f898bc56b9344ab9a929a8733f1f6b3f37560b9088cfe309935d399e66460b8e49342054a6c3a45d3d5b5f7bbba1bac0a003e1f8bd44152cd7
1	\\xc9362691d7787d3c6159511631b5ae7fa42fed3c07a85c77fc9ad2d185c48473cb6d6b2194c60bbc582a8076706b708beff1777bac59fda8ff54cc14cd5118de
1	\\x43264d52f5fcce58f701d51ea49d1ea5acfc639fd26a8feb6435cc0cab76aad917a2f59c458283f0a02c8ea31d978fadab8a20479aa05b34ca9dea66f44fd984
1	\\xd97ff18d6cb11136c90a7c4ac9886d09bc806686a811532e705a3c8185746db8cd6f26299c1e5a95acfa7b74f5a0bbaaf59a623dc0da0e82872d16054d9eeeb9
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x2c693c537105ae291a253f1c8fee54f00113ce040b4eb9b2ea586d47605cb8aa4516b634f6aaacade48f38e7f83975c92566b8450eb506be19f732980383f47e	350	\\x0000000100000001c87ef95a9f9f510ee584c5a98551638e8c00fc69c2724873644560756845e69052263aad41421054ac498dc1462006f361da5011cf35528df17cb033fa2e47f77aa468c4af2f3163909d39d36a6a72b9ec079d9717cfd6a4079c38980b39e8df50d05e61333e92842d67f907dd7d218613f8a6509e6509e2cbb592c29bdce06a	1	\\xcf9d6f166b9d2736c2caa6705325742139afef14ff1a0b4f70c1d44176b0fbe0cb9a653a1f79f7d481293ce69c098e9960db311e924dd9c4b3deb5ecd8bfc105	1650825360000000	5	1000000
2	\\x4d385218f42c01073994047227dcaa6afc78c5c345c5d5801d79415ee62261bc1a2f2c68477a8f1bdc50e66eab8e073061be58dfb979f9462eeff1c5d0d7749a	325	\\x00000001000000011ace36f49a2291b739793ff2129de8c8fa27e7e0c14d720a1a0a599ef2442402eabdc37c9fedda146a1aa72755908a37f5e183c9cb77d66a0753dcf9818306ee4d85292802d3ef0a9beac4c9c036279ee9d35b28062de1e892ad25bc1e5db7783622a3e6b167193b9b9a047df0920b48b64b1347051f9063ac8ec48c1aa6bc09	1	\\xa4230d53719734a1529eaf24dcec10700296576275fb1f63f922d84338b62d40adb58d8d955d58c46d3fd79c7b5c6c166fafe07d4f8239baade371ad6871b206	1650825360000000	2	3000000
3	\\xf34db4912473682a103b437c57db0184cc251ec901c0686b5f19314363c622a97a450131109cdeb12ad427637d1615c42b2ea7d83a617f3f1a8181630809a020	197	\\x000000010000000135e25e2cb42526697ee248e2fa6bca7393891f8c945cf1aae42e8014552029f3a93c1e494e81837d6948ee88d5127c2723900bf7bfcabbe25d3a057a3836e10b7a5fde2aafcd782e8ae1978c2025b2dac150fbcd30486c9ea19f7793faa59ee5dd2b79f54befe94b4a3f418cb253743301690c21a92798b713712b3f3e9bf2fe	1	\\x09569acb402defdcd5415709e1e58e7f6b2b77f4467f07482e5d737c1330b19a1381677b5dc512864da880dee97523078a8bcc19bf0e643f20e2e375ef72840d	1650825360000000	0	11000000
4	\\xe917187ce388a5a0255501a1e2d7b4022719e9a607f6bc242026a8fdc438c677676d218ad8d7f137a6614512a2b460365ffcf3daa073dc54de7438e1aabd2ef9	197	\\x00000001000000013fd2bfe445095f119746faa581cb93222a5d0bc2db8480977f3c596810b7b3ff42aa9e5a1c8122507bc7e59689b41e792f0c57e336299ea498e40ce191555aa0fcc94a6f3aa521af6c113064c773ff2a00696d5a5ca93941e577f9b2dd81cd37a6c5162599a51c0859b31c5eb1c006557337c3a466221e580928075536fc0b54	1	\\x0f2eecac052c87d2e3e75a70d24e78defe5706ee38ab2c20c6324c9a05b401620e2c7c399791c8b62f6a0358625f96bce4636f0b500143f8e8aa597bdf7a1e03	1650825360000000	0	11000000
5	\\x8d86f37d8cd2275da0279d0a303509f13edff29554721566ec874bea2bdda2ebeaa222d110846d39eb49d0e89d889e8e51598140802420399445e4fd6db0c30e	197	\\x00000001000000014dbf56ed6488bcd838aba31c180bc450446726453e423eee36e4e802eee4916c3f0a1f5d991ed23b50c73aa06f1aeb61d3be5df202e3f9c6dc272c5e98a5790a97c342636f8028209b5a34b9339b279ee3441d6459b56b92fde48ca57b855d03c4634c21d820c59f0260f6ddaa1db977009e149d0907946f05023eee4baac04d	1	\\x31d24fb0d8b85b722ece17cc9b2bda41e8e79f694dbc7aab29bc2093316762ab8e9dba90bca16315ebd719df412c7f57b2d34d519d627b2ee4ff031ea54d2403	1650825360000000	0	11000000
6	\\x83555f217ca3d0cab92c637f7246127a9c69ad0c9d6d18546241ddb5704489239813df6c9c48a103c7993e1dae92da143d056a42acb9e7b51e9a1d082db49681	197	\\x000000010000000177b8d781d75229e4e1baa26982830b34b83a7cb28fd9f1b5f2228efcaf0f899559c02325860cf47e13ee96b9506f9a96c188b30522d83da31d3407455472932878ea7cd449157ce8a992ec74b620927ecd4ad4cab0d1fafd2b3feeca735a981ea69fca69a270070cb6e5c0a93fe2f92eb6920a3dd6ba5b715877844388e0c0bb	1	\\x8686a5bf36d2df8130aeeb58829513db02f32b9a1cc1d48dcd6b470abd2fe5fedb12e0c4159f5d1fe73b9613b1da435e52a72943af5adbf6b37cb52666e01508	1650825360000000	0	11000000
7	\\x74c99aae30c49b37ca6f99ff1ff9ff3d263d63a27e70ab629d70591ad7d6fdb3e357bb356bfd1d663166957ae6597d00e18685e546696b765d634d8074053afb	197	\\x00000001000000013e78c394be2f61b486538af51ec53f4055d0029a5479c77cb6d8fc2f625164cf7e2bde678f419d5d2916f954e6739c7e954ab8833d4ad331569f498c143a73d7893e54324637b34e7f1bd9e62d18d9b9405a41255dcc2c3fba3b48491b10a37cca9cf569011cdd91f7d764a31ee9b78faa9ab98f4ae9ef26761e801b43ab340e	1	\\x795dd5f7e38249a01320169de5d0f377de9100eb8a112ac883799ad2665a28cc207223b066c3c29ab9efa62459c51fc5b624150727c8bd962d32fbdbd77a6806	1650825360000000	0	11000000
8	\\xe307899aaacbb75527d7b1991fd83b0878bb12392e4a1335eb3137ba7f08a4c28863abece180212ccde48cd166ab58321ba6507c9b2d31870e902316caeecfb7	197	\\x000000010000000138c642f3ff79b35b1e81469559f05c5ae984ad5b6a708952ac79486edccff7700a1bd5cfdd6859902d59033f8c74afaa596dcf49f5ce413e120a7e65513443057a825db30c5135dc1e512f937889838304cef88a2c336d840ff9dd2fcb459bc43acf9633b1373fbfd981ccfcaeaaad2a7da87dd9065e7bdd85a019a8830383bc	1	\\x79593f011fe2bba8b5ef9c08bc75df964045ffba8b94022d2167a10814a8c29046f5cceddd743358892fb095e4213a69768fc44f205da623fe80e50914309808	1650825360000000	0	11000000
9	\\xbfceed456f9f94b9cd2982cdc50ee34c86665b81cf30a3a32f01995db941a64d93109446a8c17bc83007e862557319d95b7638143cd596444b08160099fba891	197	\\x0000000100000001b364187faec02ca75d784a973a5df98290396eeccd1fcf52a2c203d69a682ad6f372166032033cdcb9f492533fa08d2f613c5ea333a4c894a247cd6b57e9ab74812c0f47ef634ad21dac15b6660b125459f21b9f5e39709cf87184af53f5d3e9b98295629dffeb200d8a4739d9212304d82542b2a16404f697cb3ce8ed223361	1	\\xc7b258277b9010e1a01d1b4e7d7e7e9b156d2a8ac543556e9691956b95dbf11dbdc02473099ee0c8bd87d128b088f7290dd0a75e34cb8048f48a6616618a6c04	1650825360000000	0	11000000
10	\\x92236d68018ca3336ff342dc6df663f98fc44843590047e3a204194dfa9812bc00eacd1a7381d6cf8d77f0824083e6494cd66e844882e497cb61c30709ad469b	197	\\x00000001000000013529957575bf4e199cd1223c97611d7e82602be7a38741df25308769d83794b402f91002c5990460a62cf1429a03587978dc04a802e59d50c37126dd799c504fada890df10b65320c4c40d01e9b75ef7536528079a0c6dcb7424e42b73c86c8fc52ffbd182ed80c7e4abb66e8f81497662bfe0690cd162e10502e5bdaa0fbc1e	1	\\x2e8379963d6a3b7a7f1865ac5f9aa7b4184f6c088ba4491d79dc53bded46d5a314767000a9a3b893fb7a491ec449c55e11b69d0b31806820e457822d48c1710d	1650825360000000	0	11000000
11	\\xb5c6006d65d0c27ba2ac0ec9ccdd3a6397f1391ecca2d2df3f28cc42dcd33ce9d4f582815feacf9283c5460990ae37604ccd197ff1d1df619f7e1aeeeb31e62c	358	\\x00000001000000010f23546c4263227931abad91de19b4c5711883fa6400f9017f1209b34b885e9aa99713de965aa3aed497e4aca46f701f424ce6032e342de4dc2ad310f82d82b5f1486b9c9d4109f08edfa2c28710c7a8fb4883f2240fe20e22c496fa48a6602f751cc4e2da464c4b80f7682737f35944ea662d7a6a7cb0941f6342879af84441	1	\\xa80750087a430ee97e2b0e84ffe69a76a35d9af29aadfb59a30a2e7c0f1d3716dfd074455e8cacc02a5d5786ba50e62b7b8ea5b88737258343bf0e90a981c00e	1650825360000000	0	2000000
12	\\xceb054f90cf71d5748392505bb58e99211bf78c6cf7f367710d576e1ad8ccaf316bc1c75983ce602e8477334baa6a1642ed1a3cbcd336574fd66467ffcb12e47	358	\\x0000000100000001894b4349d4f0d5be5fe8a61cb7e831d5807b3286ab6ce86b782f34007c9e6428d19f9e7b0499a4db508ea01d66012a6e01ff53f5d28950736c676f3256b9add9336572d875e2e27811e8da98e93fae67da56661341bd2a531ee314a70770623432b201c4c1a69735ad533ee1bf102ff2e3a1773ab4f9d2c5e4798c0b70d3cad3	1	\\xd3469b027196cebeb3d926cec24b71bf7a76aa42992380f674074feaa408c08d3c840d0ebac77bcafae4cacd7f4e8e0d8f85196046eee8d39821378d40d6fa09	1650825360000000	0	2000000
13	\\x2293c74dfb2973bf1a2cb2d725c6c07064be2855aa6441386b9bd6c04b9cf2d9cb202e56e81a5d860e218fafd51b0eb48f3fa625b4549eb0badd9d1cfd81904d	358	\\x000000010000000130170e7b8dc0a038abe5b5041bf4e58d0821fae2fe4d3c8095fb15bfea67be4775d4f9335632bedb9f7b920d148b4d7ba6609e8a1a5a3adaeef32daf3d15d33e2629af43e3521e33e4644ff4b2096707f9a1663482f0ac6ea0788dca038ed2ff86efad266b311bf94a5808cc04735d8571dc2d39e7bf47f838bd5d3284d2aee6	1	\\xd04a11e6d4d11e356487eca3da0a17cb57ed412d341fa861e995806d838b1cd55f5f2b3a23a70377989e0862b1bcfac2c59a3e5a77b1fddfed0006e546640c0a	1650825360000000	0	2000000
14	\\x3011c607c3cd71da35b835121d75cafc32efc761783b90f2e5c951878bbb306557f925ebf736a875c311f3ef9d96e5bed0f1f69daac3521ff7b36180399f93a0	358	\\x00000001000000018de9f747c7fe1a949eebc30611c0581b0f8e659cfb844a30a1aba0516970e2089f8ebedff59dcca75da3060e0718283d7044819070d52772bd81a6b18c771afeb069fb3dfe1515d67618728e342e22274fc3a932092f43ed21bc5c8f195707ae83892f657ba592f7849f9cbf871d96747554ce0e5f5cb4f1dedb3e9d2ac15152	1	\\x2cc383598c8e05f409725119a8eecaa6dd5b317f8dc0cd9f2bcf92335756a708e0e861844fb0bb2a39984b0bba5ba61747f3322e6e547a5ee572141261074605	1650825360000000	0	2000000
15	\\x9695dc85620039ea7b0295b9ae264f203232efdf42cf49d98afb4f97d17536efa6861e5493afd3ea34466d03fa41d118065146db82e795af69eb17c08650e722	315	\\x00000001000000013072a9a59be9703450a75c0964a0b462adc1f5114affca0eff462c8e7c76ee1a98ed54f8168277b0321c4e7e7959b0f2a8dd5e7ba8417a9c255194cfb737a550d1042c4facdea7efa2337941966addcf46c8c448aedea6795ea7d37fd05a3f33167d94220a6d5956612ddfa43b56004aa73b2ee0ff372f5698f2c599f9d40d4b	1	\\x6081dc418b3821da7671dfcaacb649841d06b2f77b1596d726529915bffe864a4ad7878a9e47bdb3760d807b8ce58fdfe517d2d5df5689aa4e7ff5fb1599420d	1650825371000000	1	2000000
16	\\xab8e9ed79ad852fe0afa868a82134e209171ae40e16b21b806af60cf375d7c7c6f898506a3087ed04b0f5d5678cd3f3d4aeaf0acde1411d79821eb35e455338b	197	\\x0000000100000001bd9a449d12962e796c6d0d86ab351e05a90c885606ff112d55e960980fe619782718f8b08d375e7046736216eb9f945879320b46e94371b6b959f8c00e592d9c85d23d5837160a90867f011cb571c922554351f95271501f6d9b7730c3589c544ae2d9ee7040afe084a92e1f3c3e6e51c2383a6e4dcb6848e06d7e6d9ce617b8	1	\\x6054ee8871f2ee45eda669e8f154a715660c7fc0b7968453481b0c35757ac39a32cb2091b544f970112cb01b6dd5632f4e192dd18fd3597515bcf262fd488900	1650825371000000	0	11000000
18	\\x8bced979438f1279733be6c305163380a429c996287c77f47512adc4592f743d2f0cbe3dddfdab8224eaf5b307d3dba2e8964abf6191fbd6ccf0b494ac7da45a	197	\\x00000001000000016408f942d1c6a49b953c86fc70f031859ecd4c9bc24a8443d28294844bec79ec5a984cff34513506227dec8020aa7cdddb20bbf309124f35352c278432de10514f3ae01ebac72d6745d9c2af33d35d2d1d54fc6939d4890754a3bace7d3f4703acee85965f8711fdade663b7dd929fb06be576bd897191f40e05deb6ffeffea9	1	\\x91975b3c9b6855b824dc3a5c86507a76621917a7c1e27806c37e46d710f3dcab43ed046b674b40309f49b9fd6ed755965c552db3c490329de446dfced97c8401	1650825371000000	0	11000000
20	\\x0d938ef48db558130f56edf92d418436426e6c3d330f2a97944084c2a09db7eb86da333c316f42726fa93864805eb8448f25d74fcc720a6635a7d34a4d51368c	197	\\x000000010000000144a127b591bf0fb4dc8ea869d3f87f0178bc9ff00a644fdcceec971b52eabf13c5ee5a8b61420969efcd1508729486d7b014a02bbfcff767e45d02e4012daac040f03709bd8b3450f4d55344f8ace2ada15eb89652198756a9b00ba14c2595f25b65ba204c4619275cf7dcb4a45a9fa3dc4ad050f5809e72f772c473cfafcd17	1	\\x0a6a1a07c9ff6493352c0790041d1571b73c0e0248b411e2a3946917695b8bfb2f76d3007992034ff680d1a5d6edce1d03f212fa096de132587d4d4959bb5c09	1650825371000000	0	11000000
22	\\x4f234119b617d92f744d55ba78efffbdf39bd4f23091e158c37ca2722b46fe389e260256f7b6b1d3c62744f19a65d050707f3a26a299077636e213f38816108f	197	\\x000000010000000113c40bb913f0c829bcbe04c0786275b8f1375c6ee748ba625a5174fa742630d1b36a6f84a46e37db818127feee8a92570c6e79ddb187913d556eb12b986632192c635e235031f808bc9d2f042f8c62f4bc61f3b37079452d78b1710833d8c58b896059ca509b02fecb8595b9436443f284e50f96606048034bdb8e413ddbc6ec	1	\\x050f6735736da6bb1f61a2c29408ee1a5c771f9cbf4661a18c0002db9c14b8ded14a2dde4182fec01a4c86ec891262476174bf364dab4071c34f5ad483e13404	1650825371000000	0	11000000
24	\\x84c14e88388c84aa0bff1a491b4ad29f77b9c4e59daefc5762127dccdf3135eb4cff8b55459c520262a0a9a5dd50ba898cc24f86cc6775961c576e76181c1ed4	197	\\x00000001000000019b9fc480a581eec97fe6eb3006412bdfb75a9a6f2f03708d411c94077d0f5046e614b1af50513190c05051638956a060be43e9c33664438ab0efd61b3c0b93d3f1edd4a613a71f113a79a00eb6929526cea0c7fa445b3f97bbcf52321796397f29fd2d916c63b4ba0683c000dfb162326d91e02f0a9c7d0e7dcbd010219482d4	1	\\x603de53e434e4ef1878dc8e7beb426f7beab50d376e97029c1c02de73cd6c545c828ab16522d3ca992ba630e817fbf5e377157e895df67d6239a2596162aab01	1650825371000000	0	11000000
26	\\x84b552e93fb3a333b9a04b864bec24115098b0b155600740abd9739909b29d861a9fcc51bdec018109c4ff0349189aa356cb0436d8beca398e12fa8ab61da5f4	197	\\x0000000100000001a13580c3cc137126336bb6ca344416da7f4942531f672790d164d545868650b2e6a6f93af69e76e12ef8e7c4559ff7fe136d43236b0b1da9953d3e716f257e30e541764fa827eae50f46e0322e2204133d970918a168451ee82123302101b842feeb4b35d88ebc953573099052c9a23de6867504cf193e31698fd684a4f4c447	1	\\x237336b8cf7137222df005aca6945325fd6312da1669d851c7d79a1e574ff14b9871b7d9fb2240d539cf5da56c76727c4c3641d5ba58a4e924766d7ef586d307	1650825371000000	0	11000000
28	\\x5cdb435098c697be576313f5f877c4e9650e5359bbf1e3a9d5eccb22a02dd957d3f9d6a2406a5a258cb153246c6640ecaa3e65db59d378abf3dbb10337d3ac23	197	\\x0000000100000001673920b98e43db708e193b10287dba3a259b05e40fd5a01cd00eb779844e0474d0cd3e080ca2bf73cf7b1a2beda6af857e5539854b814bc9e4a3eeb904cbd9f1bafb8a54bb131519025e6cd60c3b6d1404107b12c4082ae14ac3346ad56b62b274b5187e549707dd7933cb8ca667c3372ab73833d7a73ecac97ac82290ed3db2	1	\\xe12350bd6060f04d44919106cc78bf383c25f447529569bd8532f0781f0ed4f194f99922d556084c3cbcc5ab9bef91a5ac507d600c112620a6dbc871edb4a10f	1650825371000000	0	11000000
30	\\x4948b0f020c3233aef2306cda3101a317e49b5a7eda7af3e48dabf7e953707672d898d71baf6bca9581b1f5c9133c574e93760fd7567cab9d4afe9bddce36e31	197	\\x000000010000000190ebf23272af68c12e8e01cfc02edcc333b61192a1da37964daa2db7040f679063fb11f60c15e808942e6bb181b8281f7b688094717476228831136df9be6ef692246678c3b07b6833c3779da1def1814f6c419d6366881af932a0dbfeab609e75def9718361aa9aadfbed8e6e86202f210fb5c7c6cebbcd6c016fee3d6b0b38	1	\\xfd6bb63f2762f6a9607240b4e17f0160dbc2fb19e067fe76c35f566dd79366fe6321effc1420c84d4c4a3cc6eb5ead78b50ffbb6a4c097dc0fe9c6797eed2b0f	1650825371000000	0	11000000
32	\\xdc43f6d55df236a65fa7d9f4b6075907c2d72b552da677bb4f25893e8023e6d63c132bbcd07160090e6b758bc15e4dd46d72cda4750085b12b658e9b8345dec4	358	\\x000000010000000115c6ab61e284455b932b748dbd9e37b8d091e4512013bc980c65cbde69537a04f163c98e947a2d76f42ee18215849c3bea23501c3d4bda81e47e739c589d113ba23116a86a4e129bd1e7f52818ba8a504e1b676688d280021109013ae916a288d183059f674e211d0dde9fc1be112c1ef5404035fe782d5f4bf427f42de9b2f1	1	\\x7c27087e9c821a249a82abd9344bebccdeafc75a2ec54ed8de1ebfc0e3622e6fc3e7d3ec72110beb86645303dabdc76562fb3227a9542ee052e9b30da3b79200	1650825371000000	0	2000000
34	\\xf5bf35c10066d2f898bc56b9344ab9a929a8733f1f6b3f37560b9088cfe309935d399e66460b8e49342054a6c3a45d3d5b5f7bbba1bac0a003e1f8bd44152cd7	358	\\x000000010000000121e2870f04c9d94735f5ac5c66ff6728f5beb39899a6873a44d8b24bc3914188b2746977711fc478bbb1cc7202db4de2ddc48fcabfa8589fbe51f576e826ebb1b94d47607a53dee2715b3742afc21282c71ec5fe0d832f871472ad1b21b8ff6222b88487b0c6bb89cdad450c1a22195b13df4ec5c1d3be56b0d0f516cfc799e4	1	\\x2e041edac5426aaee4ea6c1073400dc95741ea1ca0932c80c3d51b721bebcae2173ce7f2b90f72ea602f8743aa0ca30ac6cab1dc60d357c533751d3b84286c0d	1650825371000000	0	2000000
36	\\xc9362691d7787d3c6159511631b5ae7fa42fed3c07a85c77fc9ad2d185c48473cb6d6b2194c60bbc582a8076706b708beff1777bac59fda8ff54cc14cd5118de	358	\\x000000010000000125228cb02c0b2c7242405d75e7086f73deaa12aa4467c31bdeb36354b0ffd5743c66925743e5a744943a6eb0829c55e32c470f20291708aa86bdc544c51f26363f358386fc3cfa77af03120e0d275c3a980cc9a9630dfd410c6d317088c70095a5a6068ba3f2f4bb931084c3c3aaa48297413bdcfeca941d9b365815859afdcd	1	\\x22445382e20e82316ad90c0237c4dc22f1516c6be0c0e67b7bdbe8e5d891cf56ad56a7663ed9a34117881fa4c812bb2dee7739d60966143c59fd77df1c643902	1650825371000000	0	2000000
38	\\x43264d52f5fcce58f701d51ea49d1ea5acfc639fd26a8feb6435cc0cab76aad917a2f59c458283f0a02c8ea31d978fadab8a20479aa05b34ca9dea66f44fd984	358	\\x00000001000000014f7cffc5a160009126b279d0dab23e50ddd83f0dac0dcf0463f3480d973dec668ad5e3d6b3d62b7d569f337c33edc395e91c93fa4d4d4d9bf1455427c74e861021a9bd8285abd1ab53c12177a87d7de26a90185a957d30416a894cabcd9024e6692a39ea8bbca75847b67c220aec2decb7c03150e2c20e48eca20c6e79b25f96	1	\\x07d5dd226132eaf7635496449ed087fc1b56d36bd83bf1842208ccb756dff8bdd8a45573ce4c43d4d348a70ee88661939135d365411a9857ee8663d6220c8b07	1650825371000000	0	2000000
40	\\xd97ff18d6cb11136c90a7c4ac9886d09bc806686a811532e705a3c8185746db8cd6f26299c1e5a95acfa7b74f5a0bbaaf59a623dc0da0e82872d16054d9eeeb9	358	\\x00000001000000016109537f827538255e7c3256c7222b80b36c287a54956d64539bb53f797c0b97ef88bf6aaa86a15e9681916bb6340dd8335b87e06a033f353c062a2c7e65c581c00541442780baaafa2d08d03e3a0c926e4d5df553549c9cc6b5b1a49e0251234c99ef9bc061175e71f01fcdffc2a339dd4ead9286e30948894378e228bc4eaa	1	\\x6d3cc8235e8be0b891690449f0bdaa2d4fb407e08c80f1f2f53af305bb6e5ee6b3c5aef523c69efefa564f1cb74f065c79b5cc68851c8264fc59f9c939a37101	1650825371000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x9bc04e17b9b7825bd07ced7384a56831ee1fcd54b8c480864eeb8ac814d1fed7d6b5efdfac72faa2a3f150e355bd51b68b803ef9eea4121b8473af742e9b3004	t	1650825350000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xf1cfa217b8bb0bbc2c542bea0287fdc09a04957b027445853794c7cf688e733f2830f43ba43a841a4d83b78aaf0f9a94f69a8c20abf0d4014469dbd80d86b904
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
1	\\x54e9c6c598d4ddc28169000003d713b23893ae867e83b804943d712abe0843c2	payto://x-taler-bank/localhost/testuser-vjaacpjw	f	\N
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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 42, true);


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

