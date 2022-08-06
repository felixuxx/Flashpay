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
-- Name: auditor; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auditor;


--
-- Name: SCHEMA auditor; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA auditor IS 'taler-auditor data';


--
-- Name: exchange; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA exchange;


--
-- Name: SCHEMA exchange; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA exchange IS 'taler-exchange data';


--
-- Name: merchant; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA merchant;


--
-- Name: SCHEMA merchant; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA merchant IS 'taler-merchant data';


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
-- Name: add_constraints_to_account_merges_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_account_merges_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_aggregation_tracking_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_aggregation_tracking_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_contracts_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_contracts_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_cs_nonce_locks_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_cs_nonce_locks_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_deposits_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_deposits_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_known_coins_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_known_coins_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_legitimizations_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_legitimizations_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  partition_name VARCHAR;
BEGIN
  partition_name = concat_ws('_', 'legitimizations', partition_suffix);
  EXECUTE FORMAT (
    'ALTER TABLE ' || partition_name
    || ' '
      'ADD CONSTRAINT ' || partition_name || '_legitimization_serial_id_key '
        'UNIQUE (legitimization_serial_id)');
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || partition_name || '_by_provider_and_legi_index '
        'ON '|| partition_name || ' '
        '(provider_section,provider_legitimization_id)'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || partition_name || '_by_provider_and_legi_index '
    'IS ' || quote_literal('used (rarely) in kyc_provider_account_lookup') || ';'
  );
END
$$;


--
-- Name: add_constraints_to_purse_deposits_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_purse_deposits_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_purse_merges_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_purse_merges_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_purse_refunds_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_purse_refunds_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE purse_refunds_' || partition_suffix || ' '
      'ADD CONSTRAINT purse_refunds_' || partition_suffix || '_purse_refunds_serial_id_key '
        'UNIQUE (purse_refunds_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_purse_requests_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_purse_requests_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_recoup_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_recoup_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_recoup_refresh_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_recoup_refresh_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_refresh_commitments_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_refresh_commitments_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_refresh_revealed_coins_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_refresh_revealed_coins_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_refresh_transfer_keys_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_refresh_transfer_keys_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_refunds_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_refunds_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_reserves_close_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_reserves_close_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_reserves_in_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_reserves_in_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_reserves_out_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_reserves_out_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wad_in_entries_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wad_in_entries_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wad_out_entries_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wad_out_entries_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wads_in_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wads_in_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wads_out_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wads_out_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wire_out_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wire_out_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wire_targets_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wire_targets_partition(partition_suffix character varying) RETURNS void
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
-- Name: create_foreign_hash_partition(character varying, integer, character varying, integer, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_foreign_hash_partition(source_table_name character varying, modulus integer, shard_suffix character varying, current_shard_num integer, local_user character varying DEFAULT 'taler-exchange-httpd'::character varying) RETURNS void
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
-- Name: create_foreign_range_partition(character varying, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_foreign_range_partition(source_table_name character varying, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
   RAISE NOTICE 'TODO';
END
$$;


--
-- Name: create_foreign_servers(integer, character varying, character varying, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_foreign_servers(amount integer, domain character varying, remote_user character varying DEFAULT 'taler'::character varying, remote_user_password character varying DEFAULT 'taler'::character varying) RETURNS void
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
-- Name: create_hash_partition(character varying, integer, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_hash_partition(source_table_name character varying, modulus integer, partition_num integer) RETURNS void
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
-- Name: create_partitioned_table(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_partitioned_table(table_definition character varying, table_name character varying, main_table_partition_str character varying, shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_partitions(integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_partitions(num_partitions integer) RETURNS void
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
    PERFORM create_hash_partition(
      'purse_requests'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_requests_partition(num_partitions::varchar);
    PERFORM create_hash_partition(
      'purse_refunds'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_refunds_partition(num_partitions::varchar);
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
-- Name: create_range_partition(character varying, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_range_partition(source_table_name character varying, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE NOTICE 'TODO';
END
$$;


--
-- Name: create_shard_server(character varying, integer, integer, character varying, character varying, character varying, character varying, integer, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying DEFAULT 'taler-exchange'::character varying, remote_port integer DEFAULT 5432, local_user character varying DEFAULT 'taler-exchange-httpd'::character varying) RETURNS void
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
  PERFORM create_foreign_hash_partition(
    'purse_requests'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'purse_refunds'
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
-- Name: FUNCTION create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying, remote_port integer, local_user character varying); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying, remote_port integer, local_user character varying) IS 'Create a shard server on the master
      node with all foreign tables and user mappings';


--
-- Name: create_table_account_merges(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_account_merges(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'account_merges';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(account_merge_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' 
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)' 
      ',wallet_h_payto BYTEA NOT NULL CHECK (LENGTH(wallet_h_payto)=32)'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
END
$$;


--
-- Name: create_table_aggregation_tracking(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_aggregation_tracking(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'aggregation_tracking';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(aggregation_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
     ',deposit_serial_id INT8 PRIMARY KEY' 
      ',wtid_raw BYTEA NOT NULL' 
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
-- Name: create_table_aggregation_transient(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_aggregation_transient(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_table_close_requests(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_close_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'close_requests';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(close_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' 
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
-- Name: create_table_contracts(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_contracts(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'contracts';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(contract_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_cs_nonce_locks(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_cs_nonce_locks(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(cs_nonce_lock_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_deposits(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_deposits(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(deposit_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',shard INT8 NOT NULL'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
      ',known_coin_id INT8 NOT NULL' 
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
      ',extension_details_serial_id INT8' 
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
-- Name: create_table_deposits_by_ready(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_deposits_by_ready(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_table_deposits_for_matching(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_deposits_for_matching(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits_for_matching';
BEGIN
  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(refund_deadline INT8 NOT NULL'
    ',merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)'
    ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
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
-- Name: create_table_history_requests(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_history_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'history_requests';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(history_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' 
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
-- Name: create_table_known_coins(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_known_coins(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'known_coins';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(known_coin_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',denominations_serial INT8 NOT NULL' 
      ',coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)'
      ',age_commitment_hash BYTEA CHECK (LENGTH(age_commitment_hash)=32)'
      ',denom_sig BYTEA NOT NULL'
      ',remaining_val INT8 NOT NULL DEFAULT(0)'
      ',remaining_frac INT4 NOT NULL DEFAULT(0)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)' 
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
END
$$;


--
-- Name: create_table_legitimizations(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_legitimizations(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(legitimization_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',h_payto BYTEA NOT NULL CHECK (LENGTH(h_payto)=64)'
      ',expiration_time INT8 NOT NULL DEFAULT (0)'
      ',provider_section VARCHAR NOT NULL'
      ',provider_user_id VARCHAR DEFAULT NULL'
      ',provider_legitimization_id VARCHAR DEFAULT NULL'
    ') %s ;'
    ,'legitimizations'
    ,'PARTITION BY HASH (h_payto)'
    ,shard_suffix
  );
END
$$;


--
-- Name: create_table_prewire(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_prewire(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_table_purse_deposits(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_purse_deposits(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_deposits';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_deposit_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',partner_serial_id INT8' 
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',coin_pub BYTEA NOT NULL' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );
END
$$;


--
-- Name: create_table_purse_merges(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_purse_merges(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_merges';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_merge_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY '
      ',partner_serial_id INT8' 
      ',reserve_pub BYTEA NOT NULL CHECK(length(reserve_pub)=32)'
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)' 
      ',merge_sig BYTEA NOT NULL CHECK (LENGTH(merge_sig)=64)'
      ',merge_timestamp INT8 NOT NULL'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
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
-- Name: create_table_purse_refunds(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_purse_refunds(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_refunds';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_refunds_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
END
$$;


--
-- Name: create_table_purse_requests(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_purse_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_requests';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_requests_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_merge_pub '
    'ON ' || table_name || ' '
    '(merge_pub);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_purse_expiration '
    'ON ' || table_name || ' '
    '(purse_expiration);'
  );
END
$$;


--
-- Name: create_table_recoup(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_recoup(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(recoup_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',recoup_timestamp INT8 NOT NULL'
      ',reserve_out_serial_id INT8 NOT NULL' 
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
-- Name: create_table_recoup_by_reserve(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_recoup_by_reserve(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup_by_reserve';
BEGIN
  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(reserve_out_serial_id INT8 NOT NULL' 
    ',coin_pub BYTEA CHECK (LENGTH(coin_pub)=32)' 
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
-- Name: create_table_recoup_refresh(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_recoup_refresh(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup_refresh';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(recoup_refresh_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
      ',known_coin_id BIGINT NOT NULL' 
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',recoup_timestamp INT8 NOT NULL'
      ',rrc_serial INT8 NOT NULL' 
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)'
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
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
-- Name: create_table_refresh_commitments(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_refresh_commitments(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_commitments';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(melt_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)'
      ',old_coin_pub BYTEA NOT NULL' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_old_coin_pub_index '
    'ON ' || table_name || ' '
    '(old_coin_pub);'
  );
END
$$;


--
-- Name: create_table_refresh_revealed_coins(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_refresh_revealed_coins(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_revealed_coins';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(rrc_serial BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',melt_serial_id INT8 NOT NULL' 
      ',freshcoin_index INT4 NOT NULL'
      ',link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)'
      ',denominations_serial INT8 NOT NULL' 
      ',coin_ev BYTEA NOT NULL' 
      ',h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64)' 
      ',ev_sig BYTEA NOT NULL'
      ',ewv BYTEA NOT NULL'
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
-- Name: create_table_refresh_transfer_keys(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_refresh_transfer_keys(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_transfer_keys';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(rtc_serial BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',melt_serial_id INT8 PRIMARY KEY' 
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
-- Name: create_table_refunds(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_refunds(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refunds';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(refund_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
      ',deposit_serial_id INT8 NOT NULL' 
      ',merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)'
      ',rtransaction_id INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
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
-- Name: create_table_reserves(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_table_reserves_close(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves_close(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_close';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(close_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA NOT NULL' 
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
-- Name: create_table_reserves_in(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves_in(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_in';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA PRIMARY KEY' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_exch_accnt_section_execution_date_idx '
    'ON ' || table_name || ' '
    '(exchange_account_section '
    ',execution_date'
    ');'
  );
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
-- Name: create_table_reserves_out(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_out';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',h_blind_ev BYTEA CHECK (LENGTH(h_blind_ev)=64) UNIQUE'
      ',denominations_serial INT8 NOT NULL' 
      ',denom_sig BYTEA NOT NULL'
      ',reserve_uuid INT8 NOT NULL' 
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
-- Name: create_table_reserves_out_by_reserve(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves_out_by_reserve(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'reserves_out_by_reserve';
BEGIN
  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(reserve_uuid INT8 NOT NULL' 
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
-- Name: create_table_wad_in_entries(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wad_in_entries(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wad_in_entries';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_in_entry_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',wad_in_serial_id INT8' 
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
-- Name: create_table_wad_out_entries(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wad_out_entries(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wad_out_entries';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_out_entry_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',wad_out_serial_id INT8' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
END
$$;


--
-- Name: create_table_wads_in(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wads_in(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wads_in';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_wads_out(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wads_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wads_out';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',wad_id BYTEA PRIMARY KEY CHECK (LENGTH(wad_id)=24)'
      ',partner_serial_id INT8 NOT NULL' 
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
-- Name: create_table_wire_out(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wire_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wire_out';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(wireout_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_wire_targets(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wire_targets(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(wire_target_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: defer_wire_out(); Type: PROCEDURE; Schema: exchange; Owner: -
--

CREATE PROCEDURE exchange.defer_wire_out()
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
-- Name: deposits_delete_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.deposits_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_ready BOOLEAN;
BEGIN
  was_ready = NOT (OLD.done OR OLD.extension_blocked);
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
-- Name: FUNCTION deposits_delete_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.deposits_delete_trigger() IS 'Replicate deposit deletions into materialized indices.';


--
-- Name: deposits_insert_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.deposits_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_ready BOOLEAN;
BEGIN
  is_ready = NOT (NEW.done OR NEW.extension_blocked);
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
-- Name: FUNCTION deposits_insert_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.deposits_insert_trigger() IS 'Replicate deposit inserts into materialized indices.';


--
-- Name: deposits_update_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.deposits_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_ready BOOLEAN;
DECLARE
  is_ready BOOLEAN;
BEGIN
  was_ready = NOT (OLD.done OR OLD.extension_blocked);
  is_ready = NOT (NEW.done OR NEW.extension_blocked);
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
-- Name: FUNCTION deposits_update_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.deposits_update_trigger() IS 'Replicate deposits changes into materialized indices.';


--
-- Name: detach_default_partitions(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.detach_default_partitions() RETURNS void
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
  ALTER TABLE IF EXISTS purse_refunds
    DETACH partition purse_refunds_default;
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
-- Name: FUNCTION detach_default_partitions(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.detach_default_partitions() IS 'We need to drop default and create new one before deleting the default partitions
      otherwise constraints get lost too. Might be needed in shardig too';


--
-- Name: drop_default_partitions(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.drop_default_partitions() RETURNS void
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
  DROP TABLE IF EXISTS purse_refunds_default;
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
-- Name: FUNCTION drop_default_partitions(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.drop_default_partitions() IS 'Drop all default partitions once other partitions are attached.
      Might be needed in sharding too.';


--
-- Name: exchange_do_account_merge(bytea, bytea, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_account_merge(in_purse_pub bytea, in_reserve_pub bytea, in_reserve_sig bytea, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME: function/API is dead! Do DCE?
END $$;


--
-- Name: exchange_do_batch_withdraw(bigint, integer, bytea, bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) RETURNS record
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
-- Name: FUNCTION exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result. Excludes storing the planchets.';


--
-- Name: exchange_do_batch_withdraw_insert(bytea, bigint, integer, bytea, bigint, bytea, bytea, bytea, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean) RETURNS record
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
-- Name: FUNCTION exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean) IS 'Stores information about a planchet for a batch withdraw operation. Checks if the planchet already exists, and in that case indicates a conflict';


--
-- Name: exchange_do_close_request(bytea, bigint, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_close_request(in_reserve_pub bytea, in_close_timestamp bigint, in_reserve_sig bytea, OUT out_final_balance_val bigint, OUT out_final_balance_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

  SELECT
    current_balance_val
   ,current_balance_frac
  INTO
    out_final_balance_val
   ,out_final_balance_frac
  FROM reserves
  WHERE reserve_pub=in_reserve_pub;

  IF NOT FOUND
  THEN
    out_final_balance_val=0;
    out_final_balance_frac=0;
    out_balance_ok = FALSE;
    out_conflict = FALSE;
  END IF;

  INSERT INTO close_requests
    (reserve_pub
    ,close_timestamp
    ,reserve_sig
    ,close_val
    ,close_frac)
    VALUES
    (in_reserve_pub
    ,in_close_timestamp
    ,in_reserve_sig
    ,out_final_balance_val
    ,out_final_balance_frac)
  ON CONFLICT DO NOTHING;
  out_conflict = NOT FOUND;

  UPDATE reserves SET
    current_balance_val=0
   ,current_balance_frac=0
  WHERE reserve_pub=in_reserve_pub;
  out_balance_ok = TRUE;

END $$;


--
-- Name: exchange_do_deposit(bigint, integer, bytea, bytea, bigint, bigint, bigint, bigint, bytea, character varying, bytea, bigint, bytea, bytea, bigint, boolean, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_deposit(in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_h_contract_terms bytea, in_wire_salt bytea, in_wallet_timestamp bigint, in_exchange_timestamp bigint, in_refund_deadline bigint, in_wire_deadline bigint, in_merchant_pub bytea, in_receiver_wire_account character varying, in_h_payto bytea, in_known_coin_id bigint, in_coin_pub bytea, in_coin_sig bytea, in_shard bigint, in_extension_blocked boolean, in_extension_details character varying, OUT out_exchange_timestamp bigint, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
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
-- Name: exchange_do_expire_purse(bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean) RETURNS boolean
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

INSERT INTO purse_refunds
 (purse_pub)
 VALUES
 (my_purse_pub);

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
-- Name: FUNCTION exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean) IS 'Finds an expired purse in the given time range and refunds the coins (if any).';


--
-- Name: exchange_do_gc(bigint, bigint); Type: PROCEDURE; Schema: exchange; Owner: -
--

CREATE PROCEDURE exchange.exchange_do_gc(in_ancient_date bigint, in_now bigint)
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
-- Name: exchange_do_history_request(bytea, bytea, bigint, bigint, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_history_request(in_reserve_pub bytea, in_reserve_sig bytea, in_request_timestamp bigint, in_history_fee_val bigint, in_history_fee_frac integer, OUT out_balance_ok boolean, OUT out_idempotent boolean) RETURNS record
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
-- Name: exchange_do_melt(bytea, bigint, integer, bytea, bytea, bytea, bigint, integer, boolean); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_melt(in_cs_rms bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_rc bytea, in_old_coin_pub bytea, in_old_coin_sig bytea, in_known_coin_id bigint, in_noreveal_index integer, in_zombie_required boolean, OUT out_balance_ok boolean, OUT out_zombie_bad boolean, OUT out_noreveal_index integer) RETURNS record
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
-- Name: exchange_do_purse_deposit(bigint, bytea, bigint, integer, bytea, bytea, bigint, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_purse_deposit(in_partner_id bigint, in_purse_pub bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_coin_pub bytea, in_coin_sig bytea, in_amount_without_fee_val bigint, in_amount_without_fee_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
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
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea, bytea, boolean); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
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
  ,purse_pub
  ,wallet_h_payto)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub
  ,in_wallet_h_payto);

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
-- Name: FUNCTION exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


--
-- Name: exchange_do_recoup_by_reserve(bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_recoup_by_reserve(res_pub bytea) RETURNS TABLE(denom_sig bytea, denominations_serial bigint, coin_pub bytea, coin_sig bytea, coin_blind bytea, amount_val bigint, amount_frac integer, recoup_timestamp bigint)
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
-- Name: FUNCTION exchange_do_recoup_by_reserve(res_pub bytea); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_recoup_by_reserve(res_pub bytea) IS 'Recoup by reserve as a function to make sure we hit only the needed partition and not all when joining as joins on distributed tables fetch ALL rows from the shards';


--
-- Name: exchange_do_recoup_to_coin(bytea, bigint, bytea, bytea, bigint, bytea, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_recoup_to_coin(in_old_coin_pub bytea, in_rrc_serial bigint, in_coin_blind bytea, in_coin_pub bytea, in_known_coin_id bigint, in_coin_sig bytea, in_recoup_timestamp bigint, OUT out_recoup_ok boolean, OUT out_internal_failure boolean, OUT out_recoup_timestamp bigint) RETURNS record
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
-- Name: exchange_do_recoup_to_reserve(bytea, bigint, bytea, bytea, bigint, bytea, bigint, bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_recoup_to_reserve(in_reserve_pub bytea, in_reserve_out_serial_id bigint, in_coin_blind bytea, in_coin_pub bytea, in_known_coin_id bigint, in_coin_sig bytea, in_reserve_gc bigint, in_reserve_expiration bigint, in_recoup_timestamp bigint, OUT out_recoup_ok boolean, OUT out_internal_failure boolean, OUT out_recoup_timestamp bigint) RETURNS record
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
-- Name: exchange_do_refund(bigint, integer, bigint, integer, bigint, integer, bytea, bigint, bigint, bigint, bytea, bytea, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_refund(in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_amount_val bigint, in_amount_frac integer, in_deposit_fee_val bigint, in_deposit_fee_frac integer, in_h_contract_terms bytea, in_rtransaction_id bigint, in_deposit_shard bigint, in_known_coin_id bigint, in_coin_pub bytea, in_merchant_pub bytea, in_merchant_sig bytea, OUT out_not_found boolean, OUT out_refund_ok boolean, OUT out_gone boolean, OUT out_conflict boolean) RETURNS record
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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, boolean, bigint, integer, bytea, bytea, boolean); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
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
  ,purse_pub
  ,wallet_h_payto)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub
  ,in_wallet_h_payto);

END $$;


--
-- Name: FUNCTION exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Create a purse for a reserve.';


--
-- Name: exchange_do_withdraw(bytea, bigint, integer, bytea, bytea, bytea, bytea, bytea, bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) RETURNS record
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
  nonce_ok=TRUE;
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
  nonce_ok=TRUE;
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
    nonce_ok=TRUE; -- we do not really know
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
      nonce_ok=FALSE;
      RETURN;
    END IF;
  END IF;
ELSE
  nonce_ok=TRUE; -- no nonce, hence OK!
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
-- Name: FUNCTION exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';


--
-- Name: exchange_do_withdraw_limit_check(bigint, bigint, bigint, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean) RETURNS boolean
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
-- Name: FUNCTION exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean) IS 'Check whether the withdrawals from the given reserve since the given time are below the given threshold';


--
-- Name: prepare_sharding(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.prepare_sharding() RETURNS void
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
  ALTER TABLE IF EXISTS purse_refunds
    DROP CONSTRAINT IF EXISTS purse_refunds_pkey CASCADE
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
-- Name: purse_requests_insert_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.purse_requests_insert_trigger() RETURNS trigger
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
-- Name: FUNCTION purse_requests_insert_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.purse_requests_insert_trigger() IS 'When a purse is created, insert it into the purse_action table to take action when the purse expires.';


--
-- Name: purse_requests_on_update_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.purse_requests_on_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.finished AND NOT OLD.finished)
  THEN
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
    DELETE FROM purse_actions
          WHERE purse_pub=NEW.purse_pub;
    RETURN NEW;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION purse_requests_on_update_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.purse_requests_on_update_trigger() IS 'Trigger the router if the purse is ready. Also removes the entry from the router watchlist once the purse is finished.';


--
-- Name: recoup_delete_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.recoup_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM recoup_by_reserve
   WHERE reserve_out_serial_id = OLD.reserve_out_serial_id
     AND coin_pub = OLD.coin_pub;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION recoup_delete_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.recoup_delete_trigger() IS 'Replicate recoup deletions into recoup_by_reserve table.';


--
-- Name: recoup_insert_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.recoup_insert_trigger() RETURNS trigger
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
-- Name: FUNCTION recoup_insert_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.recoup_insert_trigger() IS 'Replicate recoup inserts into recoup_by_reserve table.';


--
-- Name: reserves_out_by_reserve_delete_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.reserves_out_by_reserve_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM reserves_out_by_reserve
   WHERE reserve_uuid = OLD.reserve_uuid;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION reserves_out_by_reserve_delete_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.reserves_out_by_reserve_delete_trigger() IS 'Replicate reserve_out deletions into reserve_out_by_reserve table.';


--
-- Name: reserves_out_by_reserve_insert_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.reserves_out_by_reserve_insert_trigger() RETURNS trigger
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
-- Name: FUNCTION reserves_out_by_reserve_insert_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.reserves_out_by_reserve_insert_trigger() IS 'Replicate reserve_out inserts into reserve_out_by_reserve table.';


--
-- Name: wire_out_delete_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.wire_out_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM aggregation_tracking
   WHERE wtid_raw = OLD.wtid_raw;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION wire_out_delete_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.wire_out_delete_trigger() IS 'Replicate reserve_out deletions into aggregation_tracking. This replaces an earlier use of an ON DELETE CASCADE that required a DEFERRABLE constraint and conflicted with nice partitioning.';


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
-- Name: auditor_balance_summary; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_balance_summary (
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
-- Name: TABLE auditor_balance_summary; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_balance_summary IS 'the sum of the outstanding coins from auditor_denomination_pending (denom_pubs must belong to the respectives exchange master public key); it represents the auditor_balance_summary of the exchange at this point (modulo unexpected historic_loss-style events where denomination keys are compromised)';


--
-- Name: auditor_denomination_pending; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_denomination_pending (
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
-- Name: TABLE auditor_denomination_pending; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_denomination_pending IS 'outstanding denomination coins that the exchange is aware of and what the respective balances are (outstanding as well as issued overall which implies the maximum value at risk).';


--
-- Name: COLUMN auditor_denomination_pending.num_issued; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON COLUMN auditor.auditor_denomination_pending.num_issued IS 'counts the number of coins issued (withdraw, refresh) of this denomination';


--
-- Name: COLUMN auditor_denomination_pending.denom_risk_val; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON COLUMN auditor.auditor_denomination_pending.denom_risk_val IS 'amount that could theoretically be lost in the future due to recoup operations';


--
-- Name: COLUMN auditor_denomination_pending.recoup_loss_val; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON COLUMN auditor.auditor_denomination_pending.recoup_loss_val IS 'amount actually lost due to recoup operations past revocation';


--
-- Name: auditor_exchange_signkeys; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_exchange_signkeys (
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
-- Name: TABLE auditor_exchange_signkeys; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_exchange_signkeys IS 'list of the online signing keys of exchanges we are auditing';


--
-- Name: auditor_exchanges; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


--
-- Name: TABLE auditor_exchanges; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_exchanges IS 'list of the exchanges we are auditing';


--
-- Name: auditor_historic_denomination_revenue; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_historic_denomination_revenue (
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
-- Name: TABLE auditor_historic_denomination_revenue; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_historic_denomination_revenue IS 'Table with historic profits; basically, when a denom_pub has expired and everything associated with it is garbage collected, the final profits end up in here; note that the denom_pub here is not a foreign key, we just keep it as a reference point.';


--
-- Name: COLUMN auditor_historic_denomination_revenue.revenue_balance_val; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON COLUMN auditor.auditor_historic_denomination_revenue.revenue_balance_val IS 'the sum of all of the profits we made on the coin except for withdraw fees (which are in historic_reserve_revenue); so this includes the deposit, melt and refund fees';


--
-- Name: auditor_historic_reserve_summary; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_historic_reserve_summary (
    master_pub bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    reserve_profits_val bigint NOT NULL,
    reserve_profits_frac integer NOT NULL
);


--
-- Name: TABLE auditor_historic_reserve_summary; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_historic_reserve_summary IS 'historic profits from reserves; we eventually GC auditor_historic_reserve_revenue, and then store the totals in here (by time intervals).';


--
-- Name: auditor_predicted_result; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_predicted_result (
    master_pub bytea NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL,
    drained_val bigint NOT NULL,
    drained_frac integer NOT NULL
);


--
-- Name: TABLE auditor_predicted_result; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_predicted_result IS 'Table with the sum of the ledger, auditor_historic_revenue and the auditor_reserve_balance and the drained profits.  This is the final amount that the exchange should have in its bank account right now (and the total amount drained as profits to non-escrow accounts).';


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_progress_aggregation (
    master_pub bytea NOT NULL,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_aggregation; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_progress_aggregation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_progress_coin (
    master_pub bytea NOT NULL,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_deposits_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_refunds_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_coin; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_progress_coin IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_progress_deposit_confirmation (
    master_pub bytea NOT NULL,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_deposit_confirmation; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_progress_deposit_confirmation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_progress_reserve (
    master_pub bytea NOT NULL,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_merges_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_deposits_serial_id bigint DEFAULT 0 NOT NULL,
    last_account_merges_serial_id bigint DEFAULT 0 NOT NULL,
    last_history_requests_serial_id bigint DEFAULT 0 NOT NULL,
    last_close_requests_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_reserve; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_progress_reserve IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_reserve_balance; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_reserve_balance (
    master_pub bytea NOT NULL,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL,
    purse_fee_balance_val bigint NOT NULL,
    purse_fee_balance_frac integer NOT NULL,
    history_fee_balance_val bigint NOT NULL,
    history_fee_balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_reserve_balance; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_reserve_balance IS 'sum of the balances of all customer reserves (by exchange master public key)';


--
-- Name: auditor_reserves; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_reserves (
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
-- Name: TABLE auditor_reserves; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_reserves IS 'all of the customer reserves and their respective balances that the auditor is aware of';


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE; Schema: auditor; Owner: -
--

CREATE SEQUENCE auditor.auditor_reserves_auditor_reserves_rowid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE OWNED BY; Schema: auditor; Owner: -
--

ALTER SEQUENCE auditor.auditor_reserves_auditor_reserves_rowid_seq OWNED BY auditor.auditor_reserves.auditor_reserves_rowid;


--
-- Name: auditor_wire_fee_balance; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_wire_fee_balance (
    master_pub bytea NOT NULL,
    wire_fee_balance_val bigint NOT NULL,
    wire_fee_balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_wire_fee_balance; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_wire_fee_balance IS 'sum of the balances of all wire fees (by exchange master public key)';


--
-- Name: deposit_confirmations; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.deposit_confirmations (
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
-- Name: TABLE deposit_confirmations; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.deposit_confirmations IS 'deposit confirmation sent to us by merchants; we must check that the exchange reported these properly.';


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE; Schema: auditor; Owner: -
--

CREATE SEQUENCE auditor.deposit_confirmations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: auditor; Owner: -
--

ALTER SEQUENCE auditor.deposit_confirmations_serial_id_seq OWNED BY auditor.deposit_confirmations.serial_id;


--
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.wire_auditor_account_progress (
    master_pub bytea NOT NULL,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bigint NOT NULL,
    wire_out_off bigint NOT NULL
);


--
-- Name: TABLE wire_auditor_account_progress; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.wire_auditor_account_progress IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.wire_auditor_progress (
    master_pub bytea NOT NULL,
    last_timestamp bigint NOT NULL,
    last_reserve_close_uuid bigint NOT NULL
);


--
-- Name: account_merges; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.account_merges (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    wallet_h_payto bytea NOT NULL,
    CONSTRAINT account_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_merges_reserve_sig_check CHECK ((length(reserve_sig) = 64)),
    CONSTRAINT account_merges_wallet_h_payto_check CHECK ((length(wallet_h_payto) = 32))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE account_merges; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.account_merges IS 'Merge requests where a purse- and account-owner requested merging the purse into the account';


--
-- Name: COLUMN account_merges.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.account_merges.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN account_merges.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.account_merges.reserve_sig IS 'signature by the reserve private key affirming the merge, of type TALER_SIGNATURE_WALLET_ACCOUNT_MERGE';


--
-- Name: COLUMN account_merges.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.account_merges.purse_pub IS 'public key of the purse';


--
-- Name: account_merges_account_merge_request_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.account_merges ALTER COLUMN account_merge_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.account_merges_account_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: account_merges_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.account_merges_default (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    wallet_h_payto bytea NOT NULL,
    CONSTRAINT account_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_merges_reserve_sig_check CHECK ((length(reserve_sig) = 64)),
    CONSTRAINT account_merges_wallet_h_payto_check CHECK ((length(wallet_h_payto) = 32))
);
ALTER TABLE ONLY exchange.account_merges ATTACH PARTITION exchange.account_merges_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: aggregation_tracking; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL
)
PARTITION BY HASH (deposit_serial_id);


--
-- Name: TABLE aggregation_tracking; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.aggregation_tracking IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';


--
-- Name: COLUMN aggregation_tracking.wtid_raw; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.aggregation_tracking.wtid_raw IS 'identifier of the wire transfer';


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.aggregation_tracking ALTER COLUMN aggregation_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.aggregation_tracking_aggregation_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aggregation_tracking_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.aggregation_tracking_default (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL
);
ALTER TABLE ONLY exchange.aggregation_tracking ATTACH PARTITION exchange.aggregation_tracking_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: aggregation_transient; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.aggregation_transient (
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
-- Name: TABLE aggregation_transient; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.aggregation_transient IS 'aggregations currently happening (lacking wire_out, usually because the amount is too low); this table is not replicated';


--
-- Name: COLUMN aggregation_transient.amount_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.aggregation_transient.amount_val IS 'Sum of all of the aggregated deposits (without deposit fees)';


--
-- Name: COLUMN aggregation_transient.wtid_raw; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.aggregation_transient.wtid_raw IS 'identifier of the wire transfer';


--
-- Name: aggregation_transient_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.aggregation_transient_default (
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT aggregation_transient_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);
ALTER TABLE ONLY exchange.aggregation_transient ATTACH PARTITION exchange.aggregation_transient_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: auditor_denom_sigs; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.auditor_denom_sigs (
    auditor_denom_serial bigint NOT NULL,
    auditor_uuid bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    auditor_sig bytea,
    CONSTRAINT auditor_denom_sigs_auditor_sig_check CHECK ((length(auditor_sig) = 64))
);


--
-- Name: TABLE auditor_denom_sigs; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.auditor_denom_sigs IS 'Table with auditor signatures on exchange denomination keys.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_uuid; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditor_denom_sigs.auditor_uuid IS 'Identifies the auditor.';


--
-- Name: COLUMN auditor_denom_sigs.denominations_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditor_denom_sigs.denominations_serial IS 'Denomination the signature is for.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditor_denom_sigs.auditor_sig IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.auditor_denom_sigs ALTER COLUMN auditor_denom_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.auditor_denom_sigs_auditor_denom_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auditors; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.auditors (
    auditor_uuid bigint NOT NULL,
    auditor_pub bytea NOT NULL,
    auditor_name character varying NOT NULL,
    auditor_url character varying NOT NULL,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT auditors_auditor_pub_check CHECK ((length(auditor_pub) = 32))
);


--
-- Name: TABLE auditors; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.auditors IS 'Table with auditors the exchange uses or has used in the past. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN auditors.auditor_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditors.auditor_pub IS 'Public key of the auditor.';


--
-- Name: COLUMN auditors.auditor_url; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditors.auditor_url IS 'The base URL of the auditor.';


--
-- Name: COLUMN auditors.is_active; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditors.is_active IS 'true if we are currently supporting the use of this auditor.';


--
-- Name: COLUMN auditors.last_change; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditors.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.auditors ALTER COLUMN auditor_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.auditors_auditor_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: close_requests; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.close_requests (
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
-- Name: TABLE close_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.close_requests IS 'Explicit requests by a reserve owner to close a reserve immediately';


--
-- Name: COLUMN close_requests.close_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.close_requests.close_timestamp IS 'When the request was created by the client';


--
-- Name: COLUMN close_requests.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.close_requests.reserve_sig IS 'Signature affirming that the reserve is to be closed';


--
-- Name: COLUMN close_requests.close_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.close_requests.close_val IS 'Balance of the reserve at the time of closing, to be wired to the associated bank account (minus the closing fee)';


--
-- Name: close_requests_close_request_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.close_requests ALTER COLUMN close_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.close_requests_close_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: close_requests_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.close_requests_default (
    close_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    close_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    close_val bigint NOT NULL,
    close_frac integer NOT NULL,
    CONSTRAINT close_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT close_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY exchange.close_requests ATTACH PARTITION exchange.close_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: contracts; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.contracts (
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
-- Name: TABLE contracts; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.contracts IS 'encrypted contracts associated with purses';


--
-- Name: COLUMN contracts.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.contracts.purse_pub IS 'public key of the purse that the contract is associated with';


--
-- Name: COLUMN contracts.pub_ckey; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.contracts.pub_ckey IS 'Public ECDH key used to encrypt the contract, to be used with the purse private key for decryption';


--
-- Name: COLUMN contracts.contract_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.contracts.contract_sig IS 'signature over the encrypted contract by the purse contract key';


--
-- Name: COLUMN contracts.e_contract; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.contracts.e_contract IS 'AES-GCM encrypted contract terms (contains gzip compressed JSON after decryption)';


--
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.contracts ALTER COLUMN contract_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.contracts_contract_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: contracts_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.contracts_default (
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
ALTER TABLE ONLY exchange.contracts ATTACH PARTITION exchange.contracts_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: cs_nonce_locks; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.cs_nonce_locks (
    cs_nonce_lock_serial_id bigint NOT NULL,
    nonce bytea NOT NULL,
    op_hash bytea NOT NULL,
    max_denomination_serial bigint NOT NULL,
    CONSTRAINT cs_nonce_locks_nonce_check CHECK ((length(nonce) = 32)),
    CONSTRAINT cs_nonce_locks_op_hash_check CHECK ((length(op_hash) = 64))
)
PARTITION BY HASH (nonce);


--
-- Name: TABLE cs_nonce_locks; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.cs_nonce_locks IS 'ensures a Clause Schnorr client nonce is locked for use with an operation identified by a hash';


--
-- Name: COLUMN cs_nonce_locks.nonce; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.cs_nonce_locks.nonce IS 'actual nonce submitted by the client';


--
-- Name: COLUMN cs_nonce_locks.op_hash; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.cs_nonce_locks.op_hash IS 'hash (RC for refresh, blind coin hash for withdraw) the nonce may be used with';


--
-- Name: COLUMN cs_nonce_locks.max_denomination_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.cs_nonce_locks.max_denomination_serial IS 'Maximum number of a CS denomination serial the nonce could be used with, for GC';


--
-- Name: cs_nonce_locks_cs_nonce_lock_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.cs_nonce_locks ALTER COLUMN cs_nonce_lock_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.cs_nonce_locks_cs_nonce_lock_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cs_nonce_locks_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.cs_nonce_locks_default (
    cs_nonce_lock_serial_id bigint NOT NULL,
    nonce bytea NOT NULL,
    op_hash bytea NOT NULL,
    max_denomination_serial bigint NOT NULL,
    CONSTRAINT cs_nonce_locks_nonce_check CHECK ((length(nonce) = 32)),
    CONSTRAINT cs_nonce_locks_op_hash_check CHECK ((length(op_hash) = 64))
);
ALTER TABLE ONLY exchange.cs_nonce_locks ATTACH PARTITION exchange.cs_nonce_locks_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: denomination_revocations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.denomination_revocations (
    denom_revocations_serial_id bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT denomination_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE denomination_revocations; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.denomination_revocations IS 'remembering which denomination keys have been revoked';


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.denomination_revocations ALTER COLUMN denom_revocations_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.denomination_revocations_denom_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: denominations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.denominations (
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
-- Name: TABLE denominations; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.denominations IS 'Main denominations table. All the valid denominations the exchange knows about.';


--
-- Name: COLUMN denominations.denominations_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.denominations.denominations_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN denominations.denom_type; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.denominations.denom_type IS 'determines cipher type for blind signatures used with this denomination; 0 is for RSA';


--
-- Name: COLUMN denominations.age_mask; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.denominations.age_mask IS 'bitmask with the age restrictions that are being used for this denomination; 0 if denomination does not support the use of age restrictions';


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.denominations ALTER COLUMN denominations_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.denominations_denominations_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: deposits; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits (
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
-- Name: TABLE deposits; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.deposits IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';


--
-- Name: COLUMN deposits.shard; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.shard IS 'Used for load sharding in the materialized indices. Should be set based on merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';


--
-- Name: COLUMN deposits.known_coin_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.known_coin_id IS 'Used for garbage collection';


--
-- Name: COLUMN deposits.wire_salt; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.wire_salt IS 'Salt used when hashing the payto://-URI to get the h_wire';


--
-- Name: COLUMN deposits.wire_target_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.wire_target_h_payto IS 'Identifies the target bank account and KYC status';


--
-- Name: COLUMN deposits.done; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.done IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';


--
-- Name: COLUMN deposits.extension_blocked; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.extension_blocked IS 'True if the aggregation of the deposit is currently blocked by some extension mechanism. Used to filter out deposits that must not be processed by the canonical deposit logic.';


--
-- Name: COLUMN deposits.extension_details_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.extension_details_serial_id IS 'References extensions table, NULL if extensions are not used';


--
-- Name: deposits_by_ready; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_by_ready (
    wire_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_by_ready_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY RANGE (wire_deadline);


--
-- Name: TABLE deposits_by_ready; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.deposits_by_ready IS 'Enables fast lookups for deposits_get_ready, auto-populated via TRIGGER below';


--
-- Name: deposits_by_ready_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_by_ready_default (
    wire_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_by_ready_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY exchange.deposits_by_ready ATTACH PARTITION exchange.deposits_by_ready_default DEFAULT;


--
-- Name: deposits_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_default (
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
ALTER TABLE ONLY exchange.deposits ATTACH PARTITION exchange.deposits_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.deposits ALTER COLUMN deposit_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.deposits_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: deposits_for_matching; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_for_matching (
    refund_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_for_matching_merchant_pub_check CHECK ((length(merchant_pub) = 32))
)
PARTITION BY RANGE (refund_deadline);


--
-- Name: TABLE deposits_for_matching; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.deposits_for_matching IS 'Enables fast lookups for deposits_iterate_matching, auto-populated via TRIGGER below';


--
-- Name: deposits_for_matching_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_for_matching_default (
    refund_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_for_matching_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);
ALTER TABLE ONLY exchange.deposits_for_matching ATTACH PARTITION exchange.deposits_for_matching_default DEFAULT;


--
-- Name: exchange_sign_keys; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.exchange_sign_keys (
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
-- Name: TABLE exchange_sign_keys; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.exchange_sign_keys IS 'Table with master public key signatures on exchange online signing keys.';


--
-- Name: COLUMN exchange_sign_keys.exchange_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.exchange_pub IS 'Public online signing key of the exchange.';


--
-- Name: COLUMN exchange_sign_keys.master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.master_sig IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';


--
-- Name: COLUMN exchange_sign_keys.valid_from; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.valid_from IS 'Time when this online signing key will first be used to sign messages.';


--
-- Name: COLUMN exchange_sign_keys.expire_sign; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.expire_sign IS 'Time when this online signing key will no longer be used to sign.';


--
-- Name: COLUMN exchange_sign_keys.expire_legal; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.expire_legal IS 'Time when this online signing key legally expires.';


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.exchange_sign_keys ALTER COLUMN esk_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.exchange_sign_keys_esk_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extension_details; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.extension_details (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
)
PARTITION BY HASH (extension_details_serial_id);


--
-- Name: TABLE extension_details; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.extension_details IS 'Extensions that were provided with deposits (not yet used).';


--
-- Name: COLUMN extension_details.extension_options; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.extension_details.extension_options IS 'JSON object with options set that the exchange needs to consider when executing a deposit. Supported details depend on the extensions supported by the exchange.';


--
-- Name: extension_details_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.extension_details_default (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
);
ALTER TABLE ONLY exchange.extension_details ATTACH PARTITION exchange.extension_details_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.extension_details ALTER COLUMN extension_details_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.extension_details_extension_details_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extensions; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.extensions (
    extension_id bigint NOT NULL,
    name character varying NOT NULL,
    config bytea
);


--
-- Name: TABLE extensions; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.extensions IS 'Configurations of the activated extensions';


--
-- Name: COLUMN extensions.name; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.extensions.name IS 'Name of the extension';


--
-- Name: COLUMN extensions.config; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.extensions.config IS 'Configuration of the extension as JSON-blob, maybe NULL';


--
-- Name: extensions_extension_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.extensions ALTER COLUMN extension_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.extensions_extension_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: global_fee; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.global_fee (
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
-- Name: TABLE global_fee; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.global_fee IS 'list of the global fees of this exchange, by date';


--
-- Name: COLUMN global_fee.global_fee_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.global_fee.global_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: global_fee_global_fee_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.global_fee ALTER COLUMN global_fee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.global_fee_global_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: history_requests; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.history_requests (
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
-- Name: TABLE history_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.history_requests IS 'Paid history requests issued by a client against a reserve';


--
-- Name: COLUMN history_requests.request_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.history_requests.request_timestamp IS 'When was the history request made';


--
-- Name: COLUMN history_requests.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.history_requests.reserve_sig IS 'Signature approving payment for the history request';


--
-- Name: COLUMN history_requests.history_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.history_requests.history_fee_val IS 'History fee approved by the signature';


--
-- Name: history_requests_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.history_requests_default (
    history_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    request_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    history_fee_val bigint NOT NULL,
    history_fee_frac integer NOT NULL,
    CONSTRAINT history_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT history_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY exchange.history_requests ATTACH PARTITION exchange.history_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.history_requests ALTER COLUMN history_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.history_requests_history_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: known_coins; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.known_coins (
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
-- Name: TABLE known_coins; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


--
-- Name: COLUMN known_coins.denominations_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.denominations_serial IS 'Denomination of the coin, determines the value of the original coin and applicable fees for coin-specific operations.';


--
-- Name: COLUMN known_coins.coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.coin_pub IS 'EdDSA public key of the coin';


--
-- Name: COLUMN known_coins.age_commitment_hash; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.age_commitment_hash IS 'Optional hash of the age commitment for age restrictions as per DD 24 (active if denom_type has the respective bit set)';


--
-- Name: COLUMN known_coins.denom_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.denom_sig IS 'This is the signature of the exchange that affirms that the coin is a valid coin. The specific signature type depends on denom_type of the denomination.';


--
-- Name: COLUMN known_coins.remaining_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.remaining_val IS 'Value of the coin that remains to be spent';


--
-- Name: known_coins_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.known_coins_default (
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
ALTER TABLE ONLY exchange.known_coins ATTACH PARTITION exchange.known_coins_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.known_coins ALTER COLUMN known_coin_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.known_coins_known_coin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: legitimizations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimizations (
    legitimization_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    expiration_time bigint DEFAULT 0 NOT NULL,
    provider_section character varying NOT NULL,
    provider_user_id character varying,
    provider_legitimization_id character varying,
    CONSTRAINT legitimizations_h_payto_check CHECK ((length(h_payto) = 64))
)
PARTITION BY HASH (h_payto);


--
-- Name: TABLE legitimizations; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.legitimizations IS 'List of legitimizations (required and completed) by account and provider';


--
-- Name: COLUMN legitimizations.legitimization_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.legitimization_serial_id IS 'unique ID for this legitimization process at the exchange';


--
-- Name: COLUMN legitimizations.h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.h_payto IS 'foreign key linking the entry to the wire_targets table, NOT a primary key (multiple legitimizations are possible per wire target)';


--
-- Name: COLUMN legitimizations.expiration_time; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.expiration_time IS 'in the future if the respective KYC check was passed successfully';


--
-- Name: COLUMN legitimizations.provider_section; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.provider_section IS 'Configuration file section with details about this provider';


--
-- Name: COLUMN legitimizations.provider_user_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.provider_user_id IS 'Identifier for the user at the provider that was used for the legitimization. NULL if provider is unaware.';


--
-- Name: COLUMN legitimizations.provider_legitimization_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.provider_legitimization_id IS 'Identifier for the specific legitimization process at the provider. NULL if legitimization was not started.';


--
-- Name: legitimizations_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimizations_default (
    legitimization_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    expiration_time bigint DEFAULT 0 NOT NULL,
    provider_section character varying NOT NULL,
    provider_user_id character varying,
    provider_legitimization_id character varying,
    CONSTRAINT legitimizations_h_payto_check CHECK ((length(h_payto) = 64))
);
ALTER TABLE ONLY exchange.legitimizations ATTACH PARTITION exchange.legitimizations_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: legitimizations_legitimization_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.legitimizations ALTER COLUMN legitimization_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.legitimizations_legitimization_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: partner_accounts; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.partner_accounts (
    payto_uri character varying NOT NULL,
    partner_serial_id bigint,
    partner_master_sig bytea,
    last_seen bigint NOT NULL,
    CONSTRAINT partner_accounts_partner_master_sig_check CHECK ((length(partner_master_sig) = 64))
);


--
-- Name: TABLE partner_accounts; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.partner_accounts IS 'Table with bank accounts of the partner exchange. Entries never expire as we need to remember the signature for the auditor.';


--
-- Name: COLUMN partner_accounts.payto_uri; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partner_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the partner exchange.';


--
-- Name: COLUMN partner_accounts.partner_master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partner_accounts.partner_master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS by the partner master public key';


--
-- Name: COLUMN partner_accounts.last_seen; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partner_accounts.last_seen IS 'Last time we saw this account as being active at the partner exchange. Used to select the most recent entry, and to detect when we should check again.';


--
-- Name: partners; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.partners (
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
-- Name: TABLE partners; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.partners IS 'exchanges we do wad transfers to';


--
-- Name: COLUMN partners.partner_master_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.partner_master_pub IS 'offline master public key of the partner';


--
-- Name: COLUMN partners.start_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.start_date IS 'starting date of the partnership';


--
-- Name: COLUMN partners.end_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.end_date IS 'end date of the partnership';


--
-- Name: COLUMN partners.next_wad; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.next_wad IS 'at what time should we do the next wad transfer to this partner (frequently updated); set to forever after the end_date';


--
-- Name: COLUMN partners.wad_frequency; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.wad_frequency IS 'how often do we promise to do wad transfers';


--
-- Name: COLUMN partners.wad_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.wad_fee_val IS 'how high is the fee for a wallet to be added to a wad to this partner';


--
-- Name: COLUMN partners.master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.master_sig IS 'signature of our master public key affirming the partnership, of purpose TALER_SIGNATURE_MASTER_PARTNER_DETAILS';


--
-- Name: COLUMN partners.partner_base_url; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.partner_base_url IS 'base URL of the REST API for this partner';


--
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.partners ALTER COLUMN partner_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.partners_partner_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prewire; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.prewire (
    prewire_uuid bigint NOT NULL,
    wire_method text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
)
PARTITION BY HASH (prewire_uuid);


--
-- Name: TABLE prewire; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.prewire IS 'pre-commit data for wire transfers we are about to execute';


--
-- Name: COLUMN prewire.finished; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.prewire.finished IS 'set to TRUE once bank confirmed receiving the wire transfer request';


--
-- Name: COLUMN prewire.failed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.prewire.failed IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';


--
-- Name: COLUMN prewire.buf; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.prewire.buf IS 'serialized data to send to the bank to execute the wire transfer';


--
-- Name: prewire_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.prewire_default (
    prewire_uuid bigint NOT NULL,
    wire_method text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);
ALTER TABLE ONLY exchange.prewire ATTACH PARTITION exchange.prewire_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.prewire ALTER COLUMN prewire_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.prewire_prewire_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: profit_drains; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.profit_drains (
    profit_drain_serial_id bigint NOT NULL,
    wtid bytea NOT NULL,
    account_section character varying NOT NULL,
    payto_uri character varying NOT NULL,
    trigger_date bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac bigint NOT NULL,
    master_sig bytea NOT NULL,
    executed boolean DEFAULT false NOT NULL,
    CONSTRAINT profit_drains_master_sig_check CHECK ((length(master_sig) = 64)),
    CONSTRAINT profit_drains_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: TABLE profit_drains; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.profit_drains IS 'transactions to be performed to move profits from the escrow account of the exchange to a regular account';


--
-- Name: COLUMN profit_drains.wtid; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.wtid IS 'randomly chosen nonce, unique to prevent double-submission';


--
-- Name: COLUMN profit_drains.account_section; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.account_section IS 'specifies the configuration section in the taler-exchange-drain configuration with the wire account to drain';


--
-- Name: COLUMN profit_drains.payto_uri; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.payto_uri IS 'specifies the account to be credited';


--
-- Name: COLUMN profit_drains.trigger_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.trigger_date IS 'set by taler-exchange-offline at the time of making the signature; not necessarily the exact date of execution of the wire transfer, just for orientation';


--
-- Name: COLUMN profit_drains.amount_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.amount_val IS 'amount to be transferred';


--
-- Name: COLUMN profit_drains.master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.master_sig IS 'EdDSA signature of type TALER_SIGNATURE_MASTER_DRAIN_PROFIT';


--
-- Name: COLUMN profit_drains.executed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.executed IS 'set to TRUE by taler-exchange-drain on execution of the transaction, not replicated to auditor';


--
-- Name: profit_drains_profit_drain_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.profit_drains ALTER COLUMN profit_drain_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.profit_drains_profit_drain_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_actions; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_actions (
    purse_pub bytea NOT NULL,
    action_date bigint NOT NULL,
    partner_serial_id bigint,
    CONSTRAINT purse_actions_purse_pub_check CHECK ((length(purse_pub) = 32))
);


--
-- Name: TABLE purse_actions; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_actions IS 'purses awaiting some action by the router';


--
-- Name: COLUMN purse_actions.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_actions.purse_pub IS 'public (contract) key of the purse';


--
-- Name: COLUMN purse_actions.action_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_actions.action_date IS 'when is the purse ready for action';


--
-- Name: COLUMN purse_actions.partner_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_actions.partner_serial_id IS 'wad target of an outgoing wire transfer, 0 for local, NULL if the purse is unmerged and thus the target is still unknown';


--
-- Name: purse_deposits; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_deposits (
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
-- Name: TABLE purse_deposits; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_deposits IS 'Requests depositing coins into a purse';


--
-- Name: COLUMN purse_deposits.partner_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.partner_serial_id IS 'identifies the partner exchange, NULL in case the target purse lives at this exchange';


--
-- Name: COLUMN purse_deposits.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN purse_deposits.coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.coin_pub IS 'Public key of the coin being deposited';


--
-- Name: COLUMN purse_deposits.amount_with_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.amount_with_fee_val IS 'Total amount being deposited';


--
-- Name: COLUMN purse_deposits.coin_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.coin_sig IS 'Signature of the coin affirming the deposit into the purse, of type TALER_SIGNATURE_PURSE_DEPOSIT';


--
-- Name: purse_deposits_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_deposits_default (
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
ALTER TABLE ONLY exchange.purse_deposits ATTACH PARTITION exchange.purse_deposits_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.purse_deposits ALTER COLUMN purse_deposit_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.purse_deposits_purse_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_merges; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_merges (
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
-- Name: TABLE purse_merges; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_merges IS 'Merge requests where a purse-owner requested merging the purse into the account';


--
-- Name: COLUMN purse_merges.partner_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.partner_serial_id IS 'identifies the partner exchange, NULL in case the target reserve lives at this exchange';


--
-- Name: COLUMN purse_merges.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN purse_merges.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.purse_pub IS 'public key of the purse';


--
-- Name: COLUMN purse_merges.merge_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.merge_sig IS 'signature by the purse private key affirming the merge, of type TALER_SIGNATURE_WALLET_PURSE_MERGE';


--
-- Name: COLUMN purse_merges.merge_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.merge_timestamp IS 'when was the merge message signed';


--
-- Name: purse_merges_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_merges_default (
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
ALTER TABLE ONLY exchange.purse_merges ATTACH PARTITION exchange.purse_merges_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.purse_merges ALTER COLUMN purse_merge_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.purse_merges_purse_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_refunds; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_refunds (
    purse_refunds_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT purse_refunds_purse_pub_check CHECK ((length(purse_pub) = 32))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE purse_refunds; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_refunds IS 'Purses that were refunded due to expiration';


--
-- Name: COLUMN purse_refunds.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_refunds.purse_pub IS 'Public key of the purse';


--
-- Name: purse_refunds_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_refunds_default (
    purse_refunds_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT purse_refunds_purse_pub_check CHECK ((length(purse_pub) = 32))
);
ALTER TABLE ONLY exchange.purse_refunds ATTACH PARTITION exchange.purse_refunds_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_refunds_purse_refunds_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.purse_refunds ALTER COLUMN purse_refunds_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.purse_refunds_purse_refunds_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_requests; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_requests (
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
-- Name: TABLE purse_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_requests IS 'Requests establishing purses, associating them with a contract but without a target reserve';


--
-- Name: COLUMN purse_requests.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN purse_requests.purse_creation; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_creation IS 'Local time when the purse was created. Determines applicable purse fees.';


--
-- Name: COLUMN purse_requests.purse_expiration; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_expiration IS 'When the purse is set to expire';


--
-- Name: COLUMN purse_requests.h_contract_terms; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.h_contract_terms IS 'Hash of the contract the parties are to agree to';


--
-- Name: COLUMN purse_requests.flags; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.flags IS 'see the enum TALER_WalletAccountMergeFlags';


--
-- Name: COLUMN purse_requests.refunded; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.refunded IS 'set to TRUE if the purse could not be merged and thus all deposited coins were refunded';


--
-- Name: COLUMN purse_requests.finished; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.finished IS 'set to TRUE once the purse has been merged (into reserve or wad) or the coins were refunded (transfer aborted)';


--
-- Name: COLUMN purse_requests.in_reserve_quota; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.in_reserve_quota IS 'set to TRUE if this purse currently counts against the number of free purses in the respective reserve';


--
-- Name: COLUMN purse_requests.amount_with_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.amount_with_fee_val IS 'Total amount expected to be in the purse';


--
-- Name: COLUMN purse_requests.purse_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_fee_val IS 'Purse fee the client agreed to pay from the reserve (accepted by the exchange at the time the purse was created). Zero if in_reserve_quota is TRUE.';


--
-- Name: COLUMN purse_requests.balance_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.balance_val IS 'Total amount actually in the purse';


--
-- Name: COLUMN purse_requests.purse_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_sig IS 'Signature of the purse affirming the purse parameters, of type TALER_SIGNATURE_PURSE_REQUEST';


--
-- Name: purse_requests_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_requests_default (
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
ALTER TABLE ONLY exchange.purse_requests ATTACH PARTITION exchange.purse_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.purse_requests ALTER COLUMN purse_requests_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.purse_requests_purse_requests_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recoup; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup (
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
-- Name: TABLE recoup; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.recoup IS 'Information about recoups that were executed between a coin and a reserve. In this type of recoup, the amount is credited back to the reserve from which the coin originated.';


--
-- Name: COLUMN recoup.coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup.coin_pub IS 'Coin that is being debited in the recoup. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


--
-- Name: COLUMN recoup.coin_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup.coin_sig IS 'Signature by the coin affirming the recoup, of type TALER_SIGNATURE_WALLET_COIN_RECOUP';


--
-- Name: COLUMN recoup.coin_blind; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup.coin_blind IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the withdraw operation.';


--
-- Name: COLUMN recoup.reserve_out_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup.reserve_out_serial_id IS 'Identifies the h_blind_ev of the recouped coin and provides the link to the credited reserve.';


--
-- Name: recoup_by_reserve; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_by_reserve (
    reserve_out_serial_id bigint NOT NULL,
    coin_pub bytea,
    CONSTRAINT recoup_by_reserve_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY HASH (reserve_out_serial_id);


--
-- Name: TABLE recoup_by_reserve; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.recoup_by_reserve IS 'Information in this table is strictly redundant with that of recoup, but saved by a different primary key for fast lookups by reserve_out_serial_id.';


--
-- Name: recoup_by_reserve_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_by_reserve_default (
    reserve_out_serial_id bigint NOT NULL,
    coin_pub bytea,
    CONSTRAINT recoup_by_reserve_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY exchange.recoup_by_reserve ATTACH PARTITION exchange.recoup_by_reserve_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_default (
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
ALTER TABLE ONLY exchange.recoup ATTACH PARTITION exchange.recoup_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.recoup ALTER COLUMN recoup_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.recoup_recoup_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recoup_refresh; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_refresh (
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
-- Name: TABLE recoup_refresh; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.recoup_refresh IS 'Table of coins that originated from a refresh operation and that were recouped. Links the (fresh) coin to the melted operation (and thus the old coin). A recoup on a refreshed coin credits the old coin and debits the fresh coin.';


--
-- Name: COLUMN recoup_refresh.coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup_refresh.coin_pub IS 'Refreshed coin of a revoked denomination where the residual value is credited to the old coin. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


--
-- Name: COLUMN recoup_refresh.known_coin_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup_refresh.known_coin_id IS 'FIXME: (To be) used for garbage collection (in the future)';


--
-- Name: COLUMN recoup_refresh.coin_blind; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup_refresh.coin_blind IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the refresh operation.';


--
-- Name: COLUMN recoup_refresh.rrc_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup_refresh.rrc_serial IS 'Link to the refresh operation. Also identifies the h_blind_ev of the recouped coin (as h_coin_ev).';


--
-- Name: recoup_refresh_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_refresh_default (
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
ALTER TABLE ONLY exchange.recoup_refresh ATTACH PARTITION exchange.recoup_refresh_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.recoup_refresh ALTER COLUMN recoup_refresh_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.recoup_refresh_recoup_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_commitments; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_commitments (
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
-- Name: TABLE refresh_commitments; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.refresh_commitments IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';


--
-- Name: COLUMN refresh_commitments.rc; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_commitments.rc IS 'Commitment made by the client, hash over the various client inputs in the cut-and-choose protocol';


--
-- Name: COLUMN refresh_commitments.old_coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_commitments.old_coin_pub IS 'Coin being melted in the refresh process.';


--
-- Name: COLUMN refresh_commitments.noreveal_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_commitments.noreveal_index IS 'The gamma value chosen by the exchange in the cut-and-choose protocol';


--
-- Name: refresh_commitments_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_commitments_default (
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
ALTER TABLE ONLY exchange.refresh_commitments ATTACH PARTITION exchange.refresh_commitments_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.refresh_commitments ALTER COLUMN melt_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.refresh_commitments_melt_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_revealed_coins; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_revealed_coins (
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
-- Name: TABLE refresh_revealed_coins; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.refresh_revealed_coins IS 'Revelations about the new coins that are to be created during a melting session.';


--
-- Name: COLUMN refresh_revealed_coins.rrc_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.rrc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_revealed_coins.melt_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.melt_serial_id IS 'Identifies the refresh commitment (rc) of the melt operation.';


--
-- Name: COLUMN refresh_revealed_coins.freshcoin_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.freshcoin_index IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';


--
-- Name: COLUMN refresh_revealed_coins.coin_ev; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.coin_ev IS 'envelope of the new coin to be signed';


--
-- Name: COLUMN refresh_revealed_coins.h_coin_ev; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.h_coin_ev IS 'hash of the envelope of the new coin to be signed (for lookups)';


--
-- Name: COLUMN refresh_revealed_coins.ev_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.ev_sig IS 'exchange signature over the envelope';


--
-- Name: COLUMN refresh_revealed_coins.ewv; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.ewv IS 'exchange contributed values in the creation of the fresh coin (see /csr)';


--
-- Name: refresh_revealed_coins_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_revealed_coins_default (
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
ALTER TABLE ONLY exchange.refresh_revealed_coins ATTACH PARTITION exchange.refresh_revealed_coins_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.refresh_revealed_coins ALTER COLUMN rrc_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.refresh_revealed_coins_rrc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_transfer_keys (
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
)
PARTITION BY HASH (melt_serial_id);


--
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


--
-- Name: COLUMN refresh_transfer_keys.rtc_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_transfer_keys.rtc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_transfer_keys.melt_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_transfer_keys.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


--
-- Name: COLUMN refresh_transfer_keys.transfer_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_transfer_keys.transfer_pub IS 'transfer public key for the gamma index';


--
-- Name: COLUMN refresh_transfer_keys.transfer_privs; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_transfer_keys.transfer_privs IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';


--
-- Name: refresh_transfer_keys_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_transfer_keys_default (
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);
ALTER TABLE ONLY exchange.refresh_transfer_keys ATTACH PARTITION exchange.refresh_transfer_keys_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.refresh_transfer_keys ALTER COLUMN rtc_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.refresh_transfer_keys_rtc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refunds; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refunds (
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
-- Name: TABLE refunds; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.refunds IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';


--
-- Name: COLUMN refunds.deposit_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refunds.deposit_serial_id IS 'Identifies ONLY the merchant_pub, h_contract_terms and coin_pub. Multiple deposits may match a refund, this only identifies one of them.';


--
-- Name: COLUMN refunds.rtransaction_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refunds.rtransaction_id IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';


--
-- Name: refunds_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refunds_default (
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
ALTER TABLE ONLY exchange.refunds ATTACH PARTITION exchange.refunds_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.refunds ALTER COLUMN refund_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.refunds_refund_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves (
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
-- Name: TABLE reserves; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';


--
-- Name: COLUMN reserves.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.reserve_pub IS 'EdDSA public key of the reserve. Knowledge of the private key implies ownership over the balance.';


--
-- Name: COLUMN reserves.current_balance_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.current_balance_val IS 'Current balance remaining with the reserve.';


--
-- Name: COLUMN reserves.purses_active; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.purses_active IS 'Number of purses that were created by this reserve that are not expired and not fully paid.';


--
-- Name: COLUMN reserves.purses_allowed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.purses_allowed IS 'Number of purses that this reserve is allowed to have active at most.';


--
-- Name: COLUMN reserves.kyc_required; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.kyc_required IS 'True if a KYC check must have been passed before withdrawing from this reserve. Set to true once a reserve received a P2P payment.';


--
-- Name: COLUMN reserves.kyc_passed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.kyc_passed IS 'True once KYC was passed for this reserve. The KYC details are then available via the wire_targets table under the key of wire_target_h_payto which is to be derived from the reserve_pub and the base URL of this exchange.';


--
-- Name: COLUMN reserves.expiration_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.expiration_date IS 'Used to trigger closing of reserves that have not been drained after some time';


--
-- Name: COLUMN reserves.gc_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.gc_date IS 'Used to forget all information about a reserve during garbage collection';


--
-- Name: reserves_close; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_close (
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
-- Name: TABLE reserves_close; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves_close IS 'wire transfers executed by the reserve to close reserves';


--
-- Name: COLUMN reserves_close.wire_target_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_close.wire_target_h_payto IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.reserves_close ALTER COLUMN close_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.reserves_close_close_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_close_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_close_default (
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
ALTER TABLE ONLY exchange.reserves_close ATTACH PARTITION exchange.reserves_close_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_default (
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
ALTER TABLE ONLY exchange.reserves ATTACH PARTITION exchange.reserves_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_in; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_in (
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
-- Name: TABLE reserves_in; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves_in IS 'list of transfers of funds into the reserves, one per incoming wire transfer';


--
-- Name: COLUMN reserves_in.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_in.reserve_pub IS 'Public key of the reserve. Private key signifies ownership of the remaining balance.';


--
-- Name: COLUMN reserves_in.credit_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_in.credit_val IS 'Amount that was transferred into the reserve';


--
-- Name: COLUMN reserves_in.wire_source_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_in.wire_source_h_payto IS 'Identifies the debited bank account and KYC status';


--
-- Name: reserves_in_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_in_default (
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
ALTER TABLE ONLY exchange.reserves_in ATTACH PARTITION exchange.reserves_in_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.reserves_in ALTER COLUMN reserve_in_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.reserves_in_reserve_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_out; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_out (
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
-- Name: TABLE reserves_out; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves_out IS 'Withdraw operations performed on reserves.';


--
-- Name: COLUMN reserves_out.h_blind_ev; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_out.h_blind_ev IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';


--
-- Name: COLUMN reserves_out.denominations_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_out.denominations_serial IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';


--
-- Name: reserves_out_by_reserve; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_out_by_reserve (
    reserve_uuid bigint NOT NULL,
    h_blind_ev bytea,
    CONSTRAINT reserves_out_by_reserve_h_blind_ev_check CHECK ((length(h_blind_ev) = 64))
)
PARTITION BY HASH (reserve_uuid);


--
-- Name: TABLE reserves_out_by_reserve; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves_out_by_reserve IS 'Information in this table is strictly redundant with that of reserves_out, but saved by a different primary key for fast lookups by reserve public key/uuid.';


--
-- Name: reserves_out_by_reserve_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_out_by_reserve_default (
    reserve_uuid bigint NOT NULL,
    h_blind_ev bytea,
    CONSTRAINT reserves_out_by_reserve_h_blind_ev_check CHECK ((length(h_blind_ev) = 64))
);
ALTER TABLE ONLY exchange.reserves_out_by_reserve ATTACH PARTITION exchange.reserves_out_by_reserve_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_out_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_out_default (
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
ALTER TABLE ONLY exchange.reserves_out ATTACH PARTITION exchange.reserves_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.reserves_out ALTER COLUMN reserve_out_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.reserves_out_reserve_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.reserves ALTER COLUMN reserve_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.reserves_reserve_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: revolving_work_shards; Type: TABLE; Schema: exchange; Owner: -
--

CREATE UNLOGGED TABLE exchange.revolving_work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row integer NOT NULL,
    end_row integer NOT NULL,
    active boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE revolving_work_shards; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.revolving_work_shards IS 'coordinates work between multiple processes working on the same job with partitions that need to be repeatedly processed; unlogged because on system crashes the locks represented by this table will have to be cleared anyway, typically using "taler-exchange-dbinit -s"';


--
-- Name: COLUMN revolving_work_shards.shard_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN revolving_work_shards.last_attempt; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN revolving_work_shards.start_row; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN revolving_work_shards.end_row; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN revolving_work_shards.active; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.active IS 'set to TRUE when a worker is active on the shard';


--
-- Name: COLUMN revolving_work_shards.job_name; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.revolving_work_shards ALTER COLUMN shard_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.revolving_work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: signkey_revocations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.signkey_revocations (
    signkey_revocations_serial_id bigint NOT NULL,
    esk_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT signkey_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE signkey_revocations; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.signkey_revocations IS 'Table storing which online signing keys have been revoked';


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.signkey_revocations ALTER COLUMN signkey_revocations_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.signkey_revocations_signkey_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wad_in_entries; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wad_in_entries (
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
-- Name: TABLE wad_in_entries; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wad_in_entries IS 'list of purses aggregated in a wad according to the sending exchange';


--
-- Name: COLUMN wad_in_entries.wad_in_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.wad_in_serial_id IS 'wad for which the given purse was included in the aggregation';


--
-- Name: COLUMN wad_in_entries.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.reserve_pub IS 'target account of the purse (must be at the local exchange)';


--
-- Name: COLUMN wad_in_entries.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.purse_pub IS 'public key of the purse that was merged';


--
-- Name: COLUMN wad_in_entries.h_contract; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.h_contract IS 'hash of the contract terms of the purse';


--
-- Name: COLUMN wad_in_entries.purse_expiration; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.purse_expiration IS 'Time when the purse was set to expire';


--
-- Name: COLUMN wad_in_entries.merge_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.merge_timestamp IS 'Time when the merge was approved';


--
-- Name: COLUMN wad_in_entries.amount_with_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.amount_with_fee_val IS 'Total amount in the purse';


--
-- Name: COLUMN wad_in_entries.wad_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.wad_fee_val IS 'Total wad fees paid by the purse';


--
-- Name: COLUMN wad_in_entries.deposit_fees_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.deposit_fees_val IS 'Total deposit fees paid when depositing coins into the purse';


--
-- Name: COLUMN wad_in_entries.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.reserve_sig IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';


--
-- Name: COLUMN wad_in_entries.purse_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.purse_sig IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';


--
-- Name: wad_in_entries_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wad_in_entries_default (
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
ALTER TABLE ONLY exchange.wad_in_entries ATTACH PARTITION exchange.wad_in_entries_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wad_in_entries ALTER COLUMN wad_in_entry_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wad_in_entries_wad_in_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wad_out_entries; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wad_out_entries (
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
-- Name: TABLE wad_out_entries; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wad_out_entries IS 'Purses combined into a wad';


--
-- Name: COLUMN wad_out_entries.wad_out_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.wad_out_serial_id IS 'Wad the purse was part of';


--
-- Name: COLUMN wad_out_entries.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.reserve_pub IS 'Target reserve for the purse';


--
-- Name: COLUMN wad_out_entries.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN wad_out_entries.h_contract; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.h_contract IS 'Hash of the contract associated with the purse';


--
-- Name: COLUMN wad_out_entries.purse_expiration; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.purse_expiration IS 'Time when the purse expires';


--
-- Name: COLUMN wad_out_entries.merge_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.merge_timestamp IS 'Time when the merge was approved';


--
-- Name: COLUMN wad_out_entries.amount_with_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.amount_with_fee_val IS 'Total amount in the purse';


--
-- Name: COLUMN wad_out_entries.wad_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.wad_fee_val IS 'Wat fee charged to the purse';


--
-- Name: COLUMN wad_out_entries.deposit_fees_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.deposit_fees_val IS 'Total deposit fees charged to the purse';


--
-- Name: COLUMN wad_out_entries.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.reserve_sig IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';


--
-- Name: COLUMN wad_out_entries.purse_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.purse_sig IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';


--
-- Name: wad_out_entries_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wad_out_entries_default (
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
ALTER TABLE ONLY exchange.wad_out_entries ATTACH PARTITION exchange.wad_out_entries_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wad_out_entries ALTER COLUMN wad_out_entry_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wad_out_entries_wad_out_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wads_in; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wads_in (
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
-- Name: TABLE wads_in; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wads_in IS 'Incoming exchange-to-exchange wad wire transfers';


--
-- Name: COLUMN wads_in.wad_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_in.wad_id IS 'Unique identifier of the wad, part of the wire transfer subject';


--
-- Name: COLUMN wads_in.origin_exchange_url; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_in.origin_exchange_url IS 'Base URL of the originating URL, also part of the wire transfer subject';


--
-- Name: COLUMN wads_in.amount_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_in.amount_val IS 'Actual amount that was received by our exchange';


--
-- Name: COLUMN wads_in.arrival_time; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_in.arrival_time IS 'Time when the wad was received';


--
-- Name: wads_in_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wads_in_default (
    wad_in_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    origin_exchange_url text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    arrival_time bigint NOT NULL,
    CONSTRAINT wads_in_wad_id_check CHECK ((length(wad_id) = 24))
);
ALTER TABLE ONLY exchange.wads_in ATTACH PARTITION exchange.wads_in_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wads_in ALTER COLUMN wad_in_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wads_in_wad_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wads_out; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wads_out (
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
-- Name: TABLE wads_out; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wads_out IS 'Wire transfers made to another exchange to transfer purse funds';


--
-- Name: COLUMN wads_out.wad_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_out.wad_id IS 'Unique identifier of the wad, part of the wire transfer subject';


--
-- Name: COLUMN wads_out.partner_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_out.partner_serial_id IS 'target exchange of the wad';


--
-- Name: COLUMN wads_out.amount_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_out.amount_val IS 'Amount that was wired';


--
-- Name: COLUMN wads_out.execution_time; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_out.execution_time IS 'Time when the wire transfer was scheduled';


--
-- Name: wads_out_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wads_out_default (
    wad_out_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    partner_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    CONSTRAINT wads_out_wad_id_check CHECK ((length(wad_id) = 24))
);
ALTER TABLE ONLY exchange.wads_out ATTACH PARTITION exchange.wads_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wads_out ALTER COLUMN wad_out_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wads_out_wad_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_accounts; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_accounts (
    payto_uri character varying NOT NULL,
    master_sig bytea,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT wire_accounts_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_accounts; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wire_accounts IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN wire_accounts.payto_uri; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the exchange.';


--
-- Name: COLUMN wire_accounts.master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_accounts.master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';


--
-- Name: COLUMN wire_accounts.is_active; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_accounts.is_active IS 'true if we are currently supporting the use of this account.';


--
-- Name: COLUMN wire_accounts.last_change; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_accounts.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: wire_fee; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_fee (
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
-- Name: TABLE wire_fee; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wire_fee IS 'list of the wire fees of this exchange, by date';


--
-- Name: COLUMN wire_fee.wire_fee_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_fee.wire_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wire_fee ALTER COLUMN wire_fee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wire_fee_wire_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_out; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_out (
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
-- Name: TABLE wire_out; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wire_out IS 'wire transfers the exchange has executed';


--
-- Name: COLUMN wire_out.wire_target_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_out.wire_target_h_payto IS 'Identifies the credited bank account and KYC status';


--
-- Name: COLUMN wire_out.exchange_account_section; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_out.exchange_account_section IS 'identifies the configuration section with the debit account of this payment';


--
-- Name: wire_out_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_out_default (
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
ALTER TABLE ONLY exchange.wire_out ATTACH PARTITION exchange.wire_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wire_out ALTER COLUMN wireout_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wire_out_wireout_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_targets; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_targets (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
)
PARTITION BY HASH (wire_target_h_payto);


--
-- Name: TABLE wire_targets; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wire_targets IS 'All senders and recipients of money via the exchange';


--
-- Name: COLUMN wire_targets.wire_target_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_targets.wire_target_h_payto IS 'Unsalted hash of payto_uri';


--
-- Name: COLUMN wire_targets.payto_uri; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_targets.payto_uri IS 'Can be a regular bank account, or also be a URI identifying a reserve-account (for P2P payments)';


--
-- Name: COLUMN wire_targets.kyc_ok; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_targets.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN wire_targets.external_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_targets.external_id IS 'Name of the user that was used for OAuth 2.0-based legitimization';


--
-- Name: wire_targets_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_targets_default (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
);
ALTER TABLE ONLY exchange.wire_targets ATTACH PARTITION exchange.wire_targets_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wire_targets ALTER COLUMN wire_target_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wire_targets_wire_target_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: work_shards; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row bigint NOT NULL,
    end_row bigint NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE work_shards; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.work_shards IS 'coordinates work between multiple processes working on the same job';


--
-- Name: COLUMN work_shards.shard_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN work_shards.last_attempt; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN work_shards.start_row; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN work_shards.end_row; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN work_shards.completed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.completed IS 'set to TRUE once the shard is finished by a worker';


--
-- Name: COLUMN work_shards.job_name; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.work_shards ALTER COLUMN shard_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_accounts; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_accounts (
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
-- Name: TABLE merchant_accounts; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_accounts IS 'bank accounts of the instances';


--
-- Name: COLUMN merchant_accounts.h_wire; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_accounts.h_wire IS 'salted hash of payto_uri';


--
-- Name: COLUMN merchant_accounts.salt; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_accounts.salt IS 'salt used when hashing payto_uri into h_wire';


--
-- Name: COLUMN merchant_accounts.payto_uri; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_accounts.payto_uri IS 'payto URI of a merchant bank account';


--
-- Name: COLUMN merchant_accounts.active; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_accounts.active IS 'true if we actively use this bank account, false if it is just kept around for older contracts to refer to';


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_accounts ALTER COLUMN account_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_accounts_account_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_contract_terms (
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
-- Name: TABLE merchant_contract_terms; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_contract_terms IS 'Contracts are orders that have been claimed by a wallet';


--
-- Name: COLUMN merchant_contract_terms.merchant_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_contract_terms.order_id; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.order_id IS 'Not a foreign key into merchant_orders because paid contracts persist after expiration';


--
-- Name: COLUMN merchant_contract_terms.contract_terms; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.contract_terms IS 'These contract terms include the wallet nonce';


--
-- Name: COLUMN merchant_contract_terms.h_contract_terms; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.h_contract_terms IS 'Hash over contract_terms';


--
-- Name: COLUMN merchant_contract_terms.pay_deadline; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_contract_terms.refund_deadline; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.refund_deadline IS 'By what times do refunds have to be approved (useful to reject refund requests)';


--
-- Name: COLUMN merchant_contract_terms.paid; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.paid IS 'true implies the customer paid for this contract; order should be DELETEd from merchant_orders once paid is set to release merchant_order_locks; paid remains true even if the payment was later refunded';


--
-- Name: COLUMN merchant_contract_terms.wired; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.wired IS 'true implies the exchange wired us the full amount for all non-refunded payments under this contract';


--
-- Name: COLUMN merchant_contract_terms.fulfillment_url; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.fulfillment_url IS 'also included in contract_terms, but we need it here to SELECT on it during repurchase detection; can be NULL if the contract has no fulfillment URL';


--
-- Name: COLUMN merchant_contract_terms.session_id; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.session_id IS 'last session_id from we confirmed the paying client to use, empty string for none';


--
-- Name: COLUMN merchant_contract_terms.claim_token; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.claim_token IS 'Token optionally used to access the status of the order. All zeros (not NULL) if not used';


--
-- Name: merchant_deposit_to_transfer; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_deposit_to_transfer (
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
-- Name: TABLE merchant_deposit_to_transfer; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_deposit_to_transfer IS 'Mapping of deposits to (possibly unconfirmed) wire transfers; NOTE: not used yet';


--
-- Name: COLUMN merchant_deposit_to_transfer.execution_time; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposit_to_transfer.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_deposits; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_deposits (
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
-- Name: TABLE merchant_deposits; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_deposits IS 'Refunds approved by the merchant (backoffice) logic, excludes abort refunds';


--
-- Name: COLUMN merchant_deposits.deposit_timestamp; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposits.deposit_timestamp IS 'Time when the exchange generated the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.wire_fee_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposits.wire_fee_val IS 'We MAY want to see if we should try to get this via merchant_exchange_wire_fees (not sure, may be too complicated with the date range, etc.)';


--
-- Name: COLUMN merchant_deposits.signkey_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposits.signkey_serial IS 'Online signing key of the exchange on the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.exchange_sig; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposits.exchange_sig IS 'Signature of the exchange over the deposit confirmation';


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_deposits ALTER COLUMN deposit_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_deposits_deposit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_exchange_signing_keys; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_exchange_signing_keys (
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
-- Name: TABLE merchant_exchange_signing_keys; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_exchange_signing_keys IS 'Here we store proofs of the exchange online signing keys being signed by the exchange master key';


--
-- Name: COLUMN merchant_exchange_signing_keys.master_pub; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_exchange_signing_keys.master_pub IS 'Master public key of the exchange with these online signing keys';


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_exchange_signing_keys ALTER COLUMN signkey_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_exchange_signing_keys_signkey_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_exchange_wire_fees; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_exchange_wire_fees (
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
-- Name: TABLE merchant_exchange_wire_fees; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_exchange_wire_fees IS 'Here we store proofs of the wire fee structure of the various exchanges';


--
-- Name: COLUMN merchant_exchange_wire_fees.master_pub; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_exchange_wire_fees.master_pub IS 'Master public key of the exchange with these wire fees';


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_exchange_wire_fees ALTER COLUMN wirefee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_exchange_wire_fees_wirefee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_instances; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_instances (
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
-- Name: TABLE merchant_instances; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_instances IS 'all the instances supported by this backend';


--
-- Name: COLUMN merchant_instances.auth_hash; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.auth_hash IS 'hash used for merchant back office Authorization, NULL for no check';


--
-- Name: COLUMN merchant_instances.auth_salt; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.auth_salt IS 'salt to use when hashing Authorization header before comparing with auth_hash';


--
-- Name: COLUMN merchant_instances.merchant_id; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.merchant_id IS 'identifier of the merchant as used in the base URL (required)';


--
-- Name: COLUMN merchant_instances.merchant_name; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.merchant_name IS 'legal name of the merchant as a simple string (required)';


--
-- Name: COLUMN merchant_instances.address; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.address IS 'physical address of the merchant as a Location in JSON format (required)';


--
-- Name: COLUMN merchant_instances.jurisdiction; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.jurisdiction IS 'jurisdiction of the merchant as a Location in JSON format (required)';


--
-- Name: COLUMN merchant_instances.website; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.website IS 'merchant site URL';


--
-- Name: COLUMN merchant_instances.email; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.email IS 'email';


--
-- Name: COLUMN merchant_instances.logo; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.logo IS 'data image url';


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_instances ALTER COLUMN merchant_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_instances_merchant_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_inventory; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_inventory (
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
-- Name: TABLE merchant_inventory; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_inventory IS 'products offered by the merchant (may be incomplete, frontend can override)';


--
-- Name: COLUMN merchant_inventory.description; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.description IS 'Human-readable product description';


--
-- Name: COLUMN merchant_inventory.description_i18n; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.description_i18n IS 'JSON map from IETF BCP 47 language tags to localized descriptions';


--
-- Name: COLUMN merchant_inventory.unit; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.unit IS 'Unit of sale for the product (liters, kilograms, packages)';


--
-- Name: COLUMN merchant_inventory.image; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.image IS 'NOT NULL, but can be 0 bytes; must contain an ImageDataUrl';


--
-- Name: COLUMN merchant_inventory.taxes; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.taxes IS 'JSON array containing taxes the merchant pays, must be JSON, but can be just "[]"';


--
-- Name: COLUMN merchant_inventory.price_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.price_val IS 'Current price of one unit of the product';


--
-- Name: COLUMN merchant_inventory.total_stock; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.total_stock IS 'A value of -1 is used for unlimited (electronic good), may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_sold; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.total_sold IS 'Number of products sold, must be below total_stock, non-negative, may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_lost; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.total_lost IS 'Number of products that used to be in stock but were lost (spoiled, damaged), may never be lowered; total_stock >= total_sold + total_lost must always hold';


--
-- Name: COLUMN merchant_inventory.address; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.address IS 'JSON formatted Location of where the product is stocked';


--
-- Name: COLUMN merchant_inventory.next_restock; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.next_restock IS 'GNUnet absolute time indicating when the next restock is expected. 0 for unknown.';


--
-- Name: COLUMN merchant_inventory.minimum_age; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.minimum_age IS 'Minimum age of the customer in years, to be used if an exchange supports the age restriction extension.';


--
-- Name: merchant_inventory_locks; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_inventory_locks (
    product_serial bigint NOT NULL,
    lock_uuid bytea NOT NULL,
    total_locked bigint NOT NULL,
    expiration bigint NOT NULL,
    CONSTRAINT merchant_inventory_locks_lock_uuid_check CHECK ((length(lock_uuid) = 16))
);


--
-- Name: TABLE merchant_inventory_locks; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_inventory_locks IS 'locks on inventory helt by shopping carts; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_inventory_locks.total_locked; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: COLUMN merchant_inventory_locks.expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory_locks.expiration IS 'when does this lock automatically expire (if no order is created)';


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_inventory ALTER COLUMN product_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_inventory_product_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_keys; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_keys (
    merchant_priv bytea NOT NULL,
    merchant_serial bigint NOT NULL,
    CONSTRAINT merchant_keys_merchant_priv_check CHECK ((length(merchant_priv) = 32))
);


--
-- Name: TABLE merchant_keys; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_keys IS 'private keys of instances that have not been deleted';


--
-- Name: merchant_kyc; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_kyc (
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
-- Name: TABLE merchant_kyc; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_kyc IS 'Status of the KYC process of a merchant account at an exchange';


--
-- Name: COLUMN merchant_kyc.kyc_timestamp; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.kyc_timestamp IS 'Last time we checked our KYC status at the exchange. Useful to re-check if the status is very stale. Also the timestamp used for the exchange signature (if present).';


--
-- Name: COLUMN merchant_kyc.kyc_ok; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN merchant_kyc.exchange_sig; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.exchange_sig IS 'signature of the exchange affirming the KYC passed (or NULL if exchange does not require KYC or not kyc_ok)';


--
-- Name: COLUMN merchant_kyc.exchange_pub; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.exchange_pub IS 'public key used with exchange_sig (or NULL if exchange_sig is NULL)';


--
-- Name: COLUMN merchant_kyc.exchange_kyc_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.exchange_kyc_serial IS 'Number to use in the KYC-endpoints of the exchange to check the KYC status or begin the KYC process. 0 if we do not know it yet.';


--
-- Name: COLUMN merchant_kyc.account_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.account_serial IS 'Which bank account of the merchant is the KYC status for';


--
-- Name: COLUMN merchant_kyc.exchange_url; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.exchange_url IS 'Which exchange base URL is this KYC status valid for';


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_kyc ALTER COLUMN kyc_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_kyc_kyc_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_order_locks; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_order_locks (
    product_serial bigint NOT NULL,
    total_locked bigint NOT NULL,
    order_serial bigint NOT NULL
);


--
-- Name: TABLE merchant_order_locks; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_order_locks IS 'locks on orders awaiting claim and payment; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_order_locks.total_locked; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_order_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: merchant_orders; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_orders (
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
-- Name: TABLE merchant_orders; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_orders IS 'Orders we offered to a customer, but that have not yet been claimed';


--
-- Name: COLUMN merchant_orders.merchant_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_orders.claim_token; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.claim_token IS 'Token optionally used to authorize the wallet to claim the order. All zeros (not NULL) if not used';


--
-- Name: COLUMN merchant_orders.h_post_data; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.h_post_data IS 'Hash of the POST request that created this order, for idempotency checks';


--
-- Name: COLUMN merchant_orders.pay_deadline; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_orders.contract_terms; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.contract_terms IS 'Claiming changes the contract_terms, hence we have no hash of the terms in this table';


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_orders ALTER COLUMN order_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_orders_order_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_refund_proofs; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_refund_proofs (
    refund_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    signkey_serial bigint NOT NULL,
    CONSTRAINT merchant_refund_proofs_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_refund_proofs; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_refund_proofs IS 'Refunds confirmed by the exchange (not all approved refunds are grabbed by the wallet)';


--
-- Name: merchant_refunds; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_refunds (
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
-- Name: COLUMN merchant_refunds.rtransaction_id; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_refunds.rtransaction_id IS 'Needed for uniqueness in case a refund is increased for the same order';


--
-- Name: COLUMN merchant_refunds.refund_timestamp; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_refunds.refund_timestamp IS 'Needed for grouping of refunds in the wallet UI; has no semantics in the protocol (only for UX), but should be from the time when the merchant internally approved the refund';


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_refunds ALTER COLUMN refund_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_refunds_refund_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tip_pickup_signatures; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tip_pickup_signatures (
    pickup_serial bigint NOT NULL,
    coin_offset integer NOT NULL,
    blind_sig bytea NOT NULL
);


--
-- Name: TABLE merchant_tip_pickup_signatures; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_tip_pickup_signatures IS 'blind signatures we got from the exchange during the tip pickup';


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tip_pickups (
    pickup_serial bigint NOT NULL,
    tip_serial bigint NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: TABLE merchant_tip_pickups; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_tip_pickups IS 'tips that have been picked up';


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_tip_pickups ALTER COLUMN pickup_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_tip_pickups_pickup_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tip_reserve_keys; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tip_reserve_keys (
    reserve_serial bigint NOT NULL,
    reserve_priv bytea NOT NULL,
    exchange_url character varying NOT NULL,
    payto_uri character varying,
    CONSTRAINT merchant_tip_reserve_keys_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: COLUMN merchant_tip_reserve_keys.payto_uri; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserve_keys.payto_uri IS 'payto:// URI used to fund the reserve, may be NULL once reserve is funded';


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tip_reserves (
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
-- Name: TABLE merchant_tip_reserves; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_tip_reserves IS 'private keys of reserves that have not been deleted';


--
-- Name: COLUMN merchant_tip_reserves.expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.expiration IS 'FIXME: EXCHANGE API needs to tell us when reserves close if we are to compute this';


--
-- Name: COLUMN merchant_tip_reserves.merchant_initial_balance_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.merchant_initial_balance_val IS 'Set to the initial balance the merchant told us when creating the reserve';


--
-- Name: COLUMN merchant_tip_reserves.exchange_initial_balance_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.exchange_initial_balance_val IS 'Set to the initial balance the exchange told us when we queried the reserve status';


--
-- Name: COLUMN merchant_tip_reserves.tips_committed_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.tips_committed_val IS 'Amount of outstanding approved tips that have not been picked up';


--
-- Name: COLUMN merchant_tip_reserves.tips_picked_up_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.tips_picked_up_val IS 'Total amount tips that have been picked up from this reserve';


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_tip_reserves ALTER COLUMN reserve_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_tip_reserves_reserve_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tips; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tips (
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
-- Name: TABLE merchant_tips; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_tips IS 'tips that have been authorized';


--
-- Name: COLUMN merchant_tips.reserve_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tips.reserve_serial IS 'Reserve from which this tip is funded';


--
-- Name: COLUMN merchant_tips.expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tips.expiration IS 'by when does the client have to pick up the tip';


--
-- Name: COLUMN merchant_tips.amount_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tips.amount_val IS 'total transaction cost for all coins including withdraw fees';


--
-- Name: COLUMN merchant_tips.picked_up_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tips.picked_up_val IS 'Tip amount left to be picked up';


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_tips ALTER COLUMN tip_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_tips_tip_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_transfer_signatures; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_transfer_signatures (
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
-- Name: TABLE merchant_transfer_signatures; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_transfer_signatures IS 'table represents the main information returned from the /transfer request to the exchange.';


--
-- Name: COLUMN merchant_transfer_signatures.credit_amount_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfer_signatures.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the exchange';


--
-- Name: COLUMN merchant_transfer_signatures.execution_time; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfer_signatures.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_transfer_to_coin; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_transfer_to_coin (
    deposit_serial bigint NOT NULL,
    credit_serial bigint NOT NULL,
    offset_in_exchange_list bigint NOT NULL,
    exchange_deposit_value_val bigint NOT NULL,
    exchange_deposit_value_frac integer NOT NULL,
    exchange_deposit_fee_val bigint NOT NULL,
    exchange_deposit_fee_frac integer NOT NULL
);


--
-- Name: TABLE merchant_transfer_to_coin; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_transfer_to_coin IS 'Mapping of (credit) transfers to (deposited) coins';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_value_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfer_to_coin.exchange_deposit_value_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits minus refunds';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_fee_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfer_to_coin.exchange_deposit_fee_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits';


--
-- Name: merchant_transfers; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_transfers (
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
-- Name: TABLE merchant_transfers; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_transfers IS 'table represents the information provided by the (trusted) merchant about incoming wire transfers';


--
-- Name: COLUMN merchant_transfers.credit_amount_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfers.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the merchant';


--
-- Name: COLUMN merchant_transfers.verified; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfers.verified IS 'true once we got an acceptable response from the exchange for this transfer';


--
-- Name: COLUMN merchant_transfers.confirmed; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfers.confirmed IS 'true once the merchant confirmed that this transfer was received';


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_transfers ALTER COLUMN credit_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_transfers_credit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('auditor.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


--
-- Name: deposit_confirmations serial_id; Type: DEFAULT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.deposit_confirmations ALTER COLUMN serial_id SET DEFAULT nextval('auditor.deposit_confirmations_serial_id_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2022-08-06 13:53:02.356476+02	grothoff	{}	{}
merchant-0001	2022-08-06 13:53:03.407062+02	grothoff	{}	{}
merchant-0002	2022-08-06 13:53:03.826458+02	grothoff	{}	{}
auditor-0001	2022-08-06 13:53:03.97191+02	grothoff	{}	{}
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, recoup_loss_val, recoup_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xf92b224dea582e45d57706744a56716807e961590753461b4ae720fe036ebf4f	http://localhost:8081/
\.


--
-- Data for Name: auditor_historic_denomination_revenue; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_historic_denomination_revenue (master_pub, denom_pub_hash, revenue_timestamp, revenue_balance_val, revenue_balance_frac, loss_balance_val, loss_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_reserve_summary; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_historic_reserve_summary (master_pub, start_date, end_date, reserve_profits_val, reserve_profits_frac) FROM stdin;
\.


--
-- Data for Name: auditor_predicted_result; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_predicted_result (master_pub, balance_val, balance_frac, drained_val, drained_frac) FROM stdin;
\.


--
-- Data for Name: auditor_progress_aggregation; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_progress_aggregation (master_pub, last_wire_out_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_coin; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_recoup_serial_id, last_recoup_refresh_serial_id, last_purse_deposits_serial_id, last_purse_refunds_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_recoup_serial_id, last_reserve_close_serial_id, last_purse_merges_serial_id, last_purse_deposits_serial_id, last_account_merges_serial_id, last_history_requests_serial_id, last_close_requests_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_reserve_balance; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_reserve_balance (master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, purse_fee_balance_val, purse_fee_balance_frac, history_fee_balance_val, history_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_reserves; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_reserves (reserve_pub, master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, expiration_date, auditor_reserves_rowid, origin_account) FROM stdin;
\.


--
-- Data for Name: auditor_wire_fee_balance; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_wire_fee_balance (master_pub, wire_fee_balance_val, wire_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_auditor_account_progress; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.wire_auditor_account_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, wire_in_off, wire_out_off) FROM stdin;
\.


--
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.wire_auditor_progress (master_pub, last_timestamp, last_reserve_close_uuid) FROM stdin;
\.


--
-- Data for Name: account_merges_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.account_merges_default (account_merge_request_serial_id, reserve_pub, reserve_sig, purse_pub, wallet_h_payto) FROM stdin;
\.


--
-- Data for Name: aggregation_tracking_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.aggregation_tracking_default (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: aggregation_transient_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.aggregation_transient_default (amount_val, amount_frac, wire_target_h_payto, exchange_account_section, wtid_raw) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	51	\\xf3100aceccf667c306aa838a009b144dc3203364b671f646a90b0c1f5f1a2609c0ffae74932fb4343c72c57d92308d559125d4d7eae5b35b2c7b32e2f9951f0d
2	1	131	\\xbf852d268dfd5736337fe623e0a1d16e405a625946b73bc2c10dcfeb16b4a23b31d7977341799458f0c2807956e2a2583b4256bc24aef34ed2e61e68dd766a0a
3	1	250	\\xeec25812982a9031b6735686cc9c84a071be448ddf84a00e62692fc791174bc572bcf766d5cc78536dc0e43f7e67ab7433dddfbfad6140ec0094d0f000953f0a
4	1	251	\\x4b5095759a3e022e22239caee0541c45fc441881a26d9156914c3df7ff7117d5dee123727dca2510ba26e667090401663b222863a707f2edbad82893f81b6405
5	1	73	\\xdc26084f759653dc01ec9fb683166c3d30327cbcbc0d2d10ac422618b99adfb2680f575ea5c9b60823e204ad3d20741ff43121f574f2e6b7c9dc9b87935d6d0b
6	1	169	\\xaafc63d2cf8718d3481754b98777422f70a0de89e9c713243df3bd094c2185a47d4bb4bccaef6fd15b475a62e168d9c67b0a075eeb8b165dc45f335c8d533b00
7	1	350	\\xcee7b331c1429e1b7713b2395e87eaeb0e8eb4ee95b11302218ef06865d7869f7a168a1f0b9019cfa07bbf6fdba290091264fbffb87f93cfeee2d78187b2ca04
8	1	334	\\xd58e1e6cf9cb63f46f06a39d63bf3a6025e794e7c3bc8a98cb5176432a2c11320ea27a5ab119c24e0a40fa8a6b0683d1c469e01e453375b0bdf555ac99b30b03
9	1	180	\\xa53107d81d9124bc44d6115fbf50945b2f23ac6638fec6a5f241d47360051cc12d6a231427471892660227a0a2f85113b49a2e2c9dde03f8118d2e2bf1914602
10	1	40	\\xd544cd40d08b1e51c2bd8493a9666c67be37f78b11faa30dd17ec1ae05e57ef456d598d604713a04ea0f076d2f8ae12079a0171485f46bf6f87b5f8ebea7170b
11	1	367	\\x5b726c326d1c79b7e81180283ae62707262f691ef6a0199bae8a7e6d6e16c073b6ae6ea4a93dece9a60b6edb7f48df361b6c62e0ca4d239c4c4c1de3fa90c302
12	1	299	\\x956d898326e2b0523e638417fb432bb18d04ea635c4ea1e1501d98863da1a956bca75f69777538c1aef8f19f5c12377a49f337a6183e4f5e8a5f20e46f5d5502
13	1	56	\\xfc3ef367a6eafa01c0ace8e39472c48b8b5bc31cd5bb99d4c9cd5d90dbb5b3a888af4188b37da23b5ad16a74af9480db37356715445380289edaa5accc7d4001
14	1	69	\\xcf4dbfa1a953827e1723dbb74e7b9eb5eabf480f13cfb04b0f18ee405df08086df37e45a73a4f2314788889a4bb38d0d86bedfcc17efd521d926b5daf9406406
15	1	304	\\x8b550f1715f57cc4b0256ad38a368d3df86afe2fc0fd619759f1169a2a9a56a08434ec6ba0413c6c75f6e9f8efb3461432de3c03e1d05b1590f2d785cbd8400a
16	1	324	\\x84270560fa92d4fb98e9c8ee1690675bf4971610807ec4fd990436bdb5cae8a23ea24e11b359866b2ce97484baaeee7c6e1ee17ce388be99b6f15662942a3808
17	1	346	\\x9c941fc138ad23325438ca936fb29f47ef6a4d40da94ce58969431695988376cad358fd293abf4c0f1011eaa626c549e40dfe79c1c9d78257f5de689e5d8ad05
18	1	187	\\x6c70eafd2adae5b37743ba73d787c5f3fa79e677820fd73d5ecd89616181ae661e0bc1845eeca4ac7bb342b22b3359988478c278f2eebe54ba43acef70a8ca00
19	1	335	\\x1869a7b224cf0471b7a50f7d093effe8d31fa940e34e8df46b5673741d0222ea6d5d967ffed89b73d644e43b8bc89d0d3c7d01d43daea20fd531fcca9163b70b
20	1	124	\\xfbdfd7debc6abcc4316ae2a87025e3d207fbf512ef78ff7be64052b51dd249a032b377af3822d0e450fc81543dafacc15286683b36779a006a9765979a30a005
21	1	197	\\x417287d0ecfb2a5c09a761551e4623292d97f84765a82528e1aafbc99869f4e7890146dafdc6b64cb01a63db15a1dd431141a3b4e8eb0571ca87e7033d42c80d
22	1	312	\\xa69c695248f35b5b1e3bb8c351c2624d2814992f6bd970b3d2ad75ea066e9bdeec6cdae0dcc111deb73301084027da53d7267076a800e3cec925c01ccb919209
23	1	260	\\xb5c6efe0935230c0ed9ff596e8bf8d7063492fac9b65a347a9986ba0278a7d3fe5c095a4e4b0b8d9d65df404637d276ee21e0d8c64c3b175090b033b435c6a06
24	1	115	\\xb4bea6e9851b20ae4933f53ff1331a76d02849d98deb459969975af7a819796ff7abd4389da221dff62a1316dd97c8469bdd5f580d92ecfef2ddec645e128a02
25	1	9	\\x64fea4220256bc2f69687a64742bb73b553d567736150a384f5fc5215f133bfe300ed7716226ff5ec9ccb5f8f7b264ada014b1713f58ef848bd4dfbc7aee770f
26	1	385	\\x52649d6c575a674508dc11e849d63a4af71fbc700788b035e33f1987deacbe1827d354533cf0a1d304180290f2fa44b0847164d47adc6e8dc2b714b07d0c8309
27	1	200	\\xc690d6b8f2f484fa4e9dcaec083d1db18a0a5bef05315ff5c5a83afee0dbeb2c5c3498d2d9a6009e5f5e9f8760b44091e71c79a88d1f93ecdbceab433f77660b
28	1	297	\\xc9ffe730299ed0512b91792a6a1a3083da3118a1183b284f143e1c7a5b272829429468d86d7c03f9090d8c88a61c6390db8b47add0788d03bfd6a3b4cdb44809
29	1	147	\\xf438428ead92add9720ac083b30b1ea052e7ef64d79b170a65c99ce1e30475975ec6a02f405d46a3b24ba2101dcc59278157aeebfdeb2717a01cac0a51c9660b
30	1	23	\\x1f0e803c36550e0339fac34fd95ec1b733b26de7b9266492460cfc88f2ed25786990bed5216e1c20e15099c52de3430508f748eb88f9071c4f3709bd0bc0a70b
31	1	161	\\x0b08625fc1e7bddc92c762fa8403b9fdf161168c695f8569ec812c182621bf12045ea3f5fd7ed0a6f736e6cbfe42cf8c51b1ca32089211586ba822010bd92600
32	1	38	\\xaf528ad51b4e2fd656e83356f3d8a75edc8e221fb67e1a4eac15cb1d303797cb3edd8ee788f23f363ceb80421de57c0c0ccc4c52f965e2dab516e0d7b20c8207
33	1	210	\\xac7d260f3adf67b5dcda373e2b2ab52e097e3e203e0d4d711f1ef4f5cf5ed0327b553ff0c12b1e0ff293b8080bfd11a7cee24949b6a493375ceaed2c478fdf0d
34	1	90	\\x7731fff08e6417c3894ce318d1b97648b0e41b70dde0afc0bed375ab00ca4156f06a8ff8ee9573f24669e2d7beefaaa9eaf3ae3207a5cc02f2923e9b51213706
35	1	281	\\xc5875a50fc7ef3174197ee3bf48bfc7a5859842a478a53d4e48dfc03fda1a6f45127d52b1778acbb00feeed5740c1b3bd51ca9836cc188c3f2bbe0bed14c1905
36	1	184	\\x0cdf7f9540bd9708d249e366312f1b79843e72f1cfcc4a8c844550ef5910204251570328547835cb103514eb632dbc85907f14e8ffd8a62df39b27522ef07800
37	1	160	\\xb50a5b48ba180d95e4e7a4017aefd84632a2484d61fae3c478b9754d7ed18483d5b8a86ab32deaa571576975731e0abddd336d82227e57f6d11ded871dc6e80b
38	1	295	\\x90e1bdb5cbb869d90cad134d13cbf97579f38ad06fd315086cd49544450bdce0820c73048a1d896a4618d94487599a517b9f2c39cf1e4e7fdaba025df3d4330b
39	1	5	\\xeee9bcd072dc968a8b68fbf344b10b7dd46e9a0ee42a4bc4e19227890500632fe5452677aa93adb81d8d6c0ba25f112fc1ac35af0bf033a57c56029c76821903
40	1	19	\\x880b9a67bed4e18c6c38d581b89ed92d8c85666e6a9d95601a0ebed695806df877318fe5f447ec74db052d3e48bd561c83e90f48add8a6dda7e246ba4202b20a
41	1	53	\\x755bdb412cca8e44ef1d78b4d587373d868b0214f0dc843a1704607539fa868703360dd93d3cf1439918bf62b6974ab4b7e66400a712549d733095a2d21ac70c
42	1	34	\\xd9e9bf90eabf0967f90a6c14916c28d909923b906d9d89b766fe10ae42d38a6788dba1de054509b022014fbf5d54d38fb4c9ff9be14f3f3d4be3cc12c9a48d06
43	1	275	\\xe7882948ce8a3bd581bd3e7fcb044f85185ee8f0ff977e9ae70f731b32e2937397c9cbcbe7a3390fa59c9c2648a08fe551cacd974fae74ce9ed29d774b8a0e09
44	1	288	\\x90577bc85d7db85c2611a0ac844c5dd6f07974c4e70d36df19dc50da55f9b476505b9aaf4a00c38580952627823866cd9363cecea95cfafd88095fac6c08a003
45	1	349	\\x879945a7965671cf9f780b51c25ec9cb0f59b03937648a7944c4475d0f8a64294fe740d42705c8af81e1298b872a635e5c4d6e3ce06fa8bf0453da5041458103
46	1	357	\\x892e94c466de858547fe4091788386f1e50df4004c8b3a6db75262b71bdd59bef1f9e7b74d5e696fe480bc613ae71fa7b4662ff9b25dbbad5154e3091fe8e001
47	1	399	\\xa65561cec11b0c8211eb1ea77db6a6600ac9e8764b1a623fc2a82165c7e3ecbb710e368db1734da06aa22ef31be111e7f48d0d15a518997783113d46e90a6405
48	1	75	\\x7dbeef7a5c6605d285d810520c1985837f6b191fc3aab7536f1547ff58529f2acd7e0832862f4add5f14c0d33eea8842075dc59e8507ffdc881edc7681fc6100
49	1	423	\\x0f7bca8b5c37d14b72484b80677a7f0a5eb9049a6fe747bdb203fdb7c882bebba8cc08dc6fac2b8fcfec23c0bd43e793ade1aa66e49649821fad76ef8b3e0402
50	1	152	\\xcd3900bc027d32f1857cd4c919bad8c0e99cf8c87056788dff763ebee5219b446acff644b279a5aa671017359a9dd20ab9f298d4580790b4caf9dc7265998b05
51	1	424	\\x9ee9635dd943f2ea57e6c68c99ef14ec22b43fdfa4d7a3feae8d258c4112ceba3f8fb7721993b691e63302ad5b31eefae54665be451bc14cc3b5f83ebee4190a
52	1	289	\\xd4c9be423640fa5f2a3be8c06fa31cfa7464373ed574711e737b8296990915bb3cd7160661dcc9dcd04e8882766cf00cf9a07b85128da8b02f1515db12771302
53	1	60	\\x1b7f461aa6c1c19932091da2f9bf18db3413a65e7e5c3552e125aad327a0d95ab2f82de45c203ce3b8ae6d97e358bb37ac407f68ddb5b8998a4393f978b66f0f
54	1	140	\\x28f73676a65cac738e34a6f8968b410e5a09dcb394b506e5d26917bd8bb6a834d612afbb864b4f30e57a397949db7ab75ca7c6df625ca5d8f6963dc210846a02
55	1	421	\\x88972a576ea07fb0cf88d6a47aeb907b212d5bfad5bb803bdc2040b72781e13c33ee3512712b45c72ee446e6eb3111eda48adb3ebbd094785e2dd9740c0d8601
56	1	198	\\x7a370b825a066320c9a85bb60731e62b97fce47f7aa37d9c2a7161a98818ae3c6a9aaa7e0f1f3e272403a75268e49255bd32e4eadecda55b6534ebd40b22dc07
57	1	249	\\x8a3086de946522dc87d34c4c6e0b83a459f37f97578a7070b76e541af7327a6b41a2fc9cd6f4f37d52e3eef5fd481c290b9973579790739271d87fd7d5c3e206
58	1	241	\\x72b7297f92ed03cbd58cc8d7f2f5369c6b7d7b8ee6ec672941e10eca672de0f9e492f83d553e96ea0fb6f06824f0bf199594076a015ef51aaf30482341f1370f
59	1	88	\\xf27983ddd0b37243430a6bbeaa42284a52b338edf54ebea7af7c790824bb0bebc2a3411319e0ac7473cc8ded0aa4b740009177f5d9c8ab55cbf3a77e685d660a
60	1	381	\\x3629f8bcbe6515e09a29836a52802a555289d513896187187fcc2dfc1c093d229f16aed4a7a10d5eb53fd86ab0ba8f9f9b905eaa2c54a24948b24426f333de04
61	1	146	\\x15d76bebf0b7dded653e3b6b4b20f8b4f718ae0970f498559479e78202e06c9c0352a03b608d1042bcd4b993a989ec31053cc857726ad9dd89c109996058cb0f
62	1	4	\\x7b9f284ac9c165ea416682e2010f40cd466d544c9b72ab14a48ee38ae31e4cc0252f61d17dce2cf039c80cdc460d0f7fa683b7f5abb1262998ffd8d7bf74dd0e
63	1	72	\\xed335225295cf15c0d9283a32efc041a9ce1bd125ed060b2551b01cfd60ce7b57a5683c62563072b80736b0c15d849beca5338e1cbddb961e3ce36fc11631704
64	1	415	\\xdddc228fd7a1359e322d64857b7e33bc682c527b97c53cdc586ebe117da2d62f8cfebb9afb90fb1ff5530dae1ff147b86535b6f880e5e4afc91accf15ebbec09
65	1	86	\\xda463f577df9ba61ce7bb263d87043bfa84fc76143c17107d9325e9862d5b1752306850a5582456dc382dbbba9557483b0eb058e81f332e6c9d5eb113840920e
66	1	39	\\x07cef6d10abfb9d0bf9fbe656d8e032df78ae8300ab9b87c4f00c9defed1d433d57b26f3f863da218c0bd84cb8bb1b8b73dc94396736d7b5d74c56a4155a0605
67	1	328	\\xa70060cd09fe45162f49e4976aeb1bcad2f953b4607484f26a68027b90e226fd11832631c98f0b1c07e2383cd659a2b786df262aa698fe10af798cfa502ec301
68	1	50	\\x2e0a2ec663be3383201b3d195006fbee78015ce51459c12963b65d008a575147a83314b469f5dd534ffbdc3936a123d45876876002e9fd7bbae9656c9723ac03
69	1	235	\\xcafe5cdf6d2a9734ec0c54b684ce8064b9747285b204db00ac12dce9754b79ffef174e9b6a0c696d3b215f759b6cf8e7c4d71b82b35a67fc30cb7878b6719708
70	1	190	\\x6b852827da035de5956716c6e1301ec0ffe9ac15456c2edd9e359e4412994a155c903871393ec1125f4f6ae2cbb4cd836dd40444b1c3cfbe8306973843b4650f
71	1	117	\\x85fb8b5af10fbc9a9592c86e6d8cab3346acd05d37ba8df556476805ebb3dcb276e457ae788c84071ddaa3621fe794283acddaf7dcbbecfb57ef5280ff2e8f0b
72	1	62	\\x4a2f6f475801c49dd1fd33fa3045a0b1222e8a384e7b47e23fa9ac8ddca3a229604db51867ee8cbcbd504c94524a9f5963bbac144620c0bac26daa69a761cd00
73	1	163	\\x740de0edf8b9cbe551d722e977f19093cf8a432b236a195e3ed9f8cba4c82c20736a1947d12dba45772893ea75fcfaaa2225602389ac1091ae5e0b515d942a0b
74	1	402	\\xfe8cf7980ce660eb6b06a007f082fff39008acbb1782bd32bdcdafc38081175adaa15faeac1ca79978f80de56465c115df335264e4ca6f48f8fb05eb8d07a301
75	1	373	\\x3c7f9211272e03a676d03b3c7627c7aeb9c8f99a98a2f11fef7f86dec1366146e199febf333337d9cf264ee184dad8a3ec45886f256c2fad78ae2bfe8c0e970f
76	1	74	\\xda4d3ad936e292d8b8f55ee096391aaff85449dd1cf3b5ffe745634f07291ed1b938317ee8a598198dfc6e871615d4014c912a1a4283319f9e2373674e5cd20a
77	1	119	\\x619e0df4c0e7742e61473cb9a705917ab1a2b2651effc931a57c4edd010770a36e06f5a7b1ac57d47bf61ff0060c5da2db16932bae0e8299b87a36dcfea6ad00
78	1	168	\\x5c0a468a82776f4e3d7d613917e863ebca57cd799beff48591756e3dcf1c1a0892508c4d2151937f80bd3f0bb873e5a60d1c89c33e4118cc2c9a1b5039c39908
79	1	313	\\x60a921e2aaf75112e586f278075dd22afb2ac7faaa995b69016229e73e0f791f581a11a231cdb0b25b3a55b723bee820de0febfc2a4754d619dff45a1016a40f
80	1	268	\\x8073fe4e81e01033529b4b094129c0f30452f632d15691bab4ba50700102acb346f4fa1d329f3d958c6db8509df921de694673f00ed24530489089c2bdc45807
81	1	7	\\x4a913b06a93d846c0f444de1ebcb25823429b4a190caa71a6cf72744f0d3b924b7fb8d9c439ed07b1e5f2e828f758d5e0c98f84faf357022bb64d05dde9d7004
82	1	323	\\x7db2ebc12c13f2341197c92077fd1cf76e32af7911ddbd2ceca412604316e4088c333094a6c97a66bc45d4ba225bebadd07165ea23ec795dfaa6b923e9754107
83	1	205	\\xa18d5abcdc8ec256f682f1a0a53b778f67ad9e57ace659c250ca62d892f821a26e60dc2d284c3d51339e871b80deba1f77055d989f9548aa42eb3bbe1e36b807
84	1	126	\\xae154d20bf2e01abfb85e932abd618038331707a5196f512cae3601e712a534b4cec085b1f6a3e8e6b3e521d09235b7203a2a43b9b9797635869b39a12740207
85	1	67	\\x62f30e8fca2e7c6c17476a81ca63d17ae5e091851400c4edea5c8030b92994270b4afaa76fa33305c2133756ac891c481642ca1cd6267eeb0b56e8079817010d
86	1	43	\\xdca49f182caa5793f775b11786329b18095c88cf7d569bef9b2972a6ed5e5d7bebefc3344d23191f0b25e322383b88f71c41b34b745d2b48b9d505e5c1da0c00
87	1	409	\\x8e9b2f38a72fffa0243213e2b8d535f3798f20db95e19516a36c037cbe09ebc89828c871802f373cca2ef6e0cffe709f3f10a3d6f5a06e3ef3941266107f0504
88	1	111	\\xfcf9e110e94e7160963c143d841434413466a37b767a4cb223bd1151ea02dbbaa1f8f18118ce07de39cfb57306451d67ef5b505a3544911bb127c615a497150c
89	1	176	\\xf6850f3f921ca72d7aaf683c03476f40aae9a2a2198c27ac36b8561091abc26c78bc654b28c87bc71577c4908c35eabc411a341551af05c9f2744fe1d43b1802
90	1	414	\\x0c8b2147c92bb3119f533ac2416f6ca7962a5e19b68e81fe6ea8e44d64d2f11b00a6a72292758073fb50b22ba8142596e420bdf98ccf156e59fb024032d4b202
91	1	195	\\xe83ab07af38947de4a6c357bec1f30de13f1f8fceecefce8238cc9e021a4624097d5e760e6a97740bbb83efd1c64aae37eed96bd93ff6189848528fff55b670c
92	1	174	\\x84920fe476565297a004eba63781d8654631e6096abea5e07b13a2a5373a62bc84a7e120172c4b4d3d170054d5710e62b85cab63b58877685596153d1ea56500
93	1	317	\\x49f7252947dacdb6b5b9eacd54269443facf04e58c1e9584f8ecdaa4683f1a5936c5f89b28ba263ca5442271190a8d54fb77532793a1d1cae675444ea871b307
94	1	403	\\x07789e00e035d9507073b4ac68dd33d3f51cda4bc2b7020ea2d370f34b2901a3963abd0f38c235234a515737d4ec85ba9e7f10624666f9dfa0ebee7245eaef05
95	1	137	\\x409a360c406f116a3eba9d33386627e6d161f4a4053f7a4858b074a8810c8bf874b612195af26505a3346a960b55ae66dc4d50c23717f0e434a36d86f9c3160f
96	1	181	\\xdfd1417bf78bc1667f4d25578ec1b58180a9bfc2fc87df0d804d069763e9a6ca35475a99365bedd613ac135aa1120ec1a069e9561357c6e3f0d7ce91fe4f4c01
97	1	177	\\x7b979582df67f2d9219ff71c35be432f90afa4f3db9aee4762786ab93df8e47c2e155dc71880fe9e145c159894607030b6d90d77c9940fc74c208de647070408
98	1	282	\\x1da0a347e752d47d837a2e1902bd7c3029349ade478cc9975fa9d28233a467aca6992f8133efa7b8db6e05f0a802e95b26aed79cc935875f7a78daef48b10e07
99	1	262	\\xfed82848d08b468f780cdb7364213e443de16179a913cbeaec4708b070c45447eb0a43fa3a9843b278abc936550af6abaedb33c12779ff3bf9958edbb0a9210d
100	1	87	\\x711dd3fbeb936fcac9a7d911430eef859e397d111227c46694f129a19f169091dc9b08151a9573c4dd4b8f827ad4f163fdaa5062d21fb50eb6e4d4f6687f4504
101	1	64	\\x5871483a181574572a35299496352b5ea4de1bbc79a6e76bdd5855d3ebe7fdc159d61db96d01dc9faffa7b3c80e4f00a8f6c54be0bc442da997f0b7f986b100d
102	1	366	\\x7486801f03ac222b47c7cdd16d5c31a1e1f276992bca8eb15e93c3e94192dcf01fe504343188aa9ad61dbe2c4ef5c9d0de7cebb5f6f541945157befcf13e9802
103	1	92	\\x60c9f468d91938b11936d38fddc33ed7ac3d69df956c7d99b53903706c1376552fe2c06fb4950c44a4a4847389375114d20d4653606e2bc1b505775661b62d0c
104	1	228	\\x7d6549a10f387267625c001dc16ee595cc901b4e921becf1f2739371e178718b1859a5c40b4ba571167aae798ef5e934dfe58c0af841652eef901be811598b07
105	1	316	\\x52936bc0b2c109ad6e7e3bbcbb3612bda3c24636cbc31d6436736e31ec176b32b8bdb8b9b2eadf4e86564981222eba04eeafd65e11641e73c0d190a628b70106
106	1	30	\\x89ecd5770f19ec0bc238106f24fac2ed8eecf96e6cc019d4c396e7a16b7898d1c9bd679a546ffd94bb160da529d7e43ad9c6b2a518ec47abc317bb7980bde60d
107	1	236	\\x6d14c5d373317ee3a5069749a2b999e2d1c5978e0b2ffe8ca1113d26d7c4a0544aaca3762d1cf1379c1b5f9d9ae995d10a84f2aedfff3a4c08a359eab9471904
108	1	110	\\x0fee6abd8a94afcaab86992eab14e42edb311381c02744d02e13c9df354e4ef24d6ec109e3c1df28f322a52fa3fef9261ba51043cbc7ebecb61b9fbdc3921008
109	1	269	\\xa1ac991358774acab3fddfaf3cb777324b471d160b8e9bb1499daddeb652589bb899142e0238390e2e9d7f63cda7ab1266ffae4577e0e77db8b619c06159430b
110	1	141	\\x86a2ac4f47cbad6f9ef1438422a09601599869bd9a13550398174f42e193b6f0f51d88fedb219f1957adc894ad3df23d3a96681ea360c0f2e4a70581e6d5e408
111	1	20	\\x2ba1d838987d802051064d9cbab23a624e72d5e44ca2bb2da8d76aec5dfa60bc97690f635975e2e0b04278f67394948564266503d6f821fe001f6bd4e53c4501
112	1	284	\\xfc3d677520b329cef0e1c47f1c2b3ccc8b55a5c04694967205547ee07b97c20e9f228c575f8a7f109c995944e1d69da22fb1358c5a4213dc05d4be724a6d9504
113	1	42	\\xa7f922c3a399b643925170d8a86f07bbd222e8ca82e888addae0d236ca308875c62313046af6567c08e2a01ba32f9578077ff4527edbb271268378c5cafb3909
114	1	290	\\xcfb359110fe09f3aa1f82794a900cb1cebc514ea5e83d6da325becda7449ed920923b332c47351414c94fac6c800a692785bebd28006ff5eaa61e060f9c6520f
115	1	48	\\x750359cdad7863b1db610f02247d6c954c2cba9efc9b9cdbcea096dde9e5f7bb2d77b343e1c8978b8892712b46b0b5fc3c6ce1e451a2c436ce212161aec01908
116	1	405	\\x8d6e286d68e2e6c4ac50abcbd6db52bb437338a2675fee49e2146c02680ca37a6ac1ae9d17a8a5521ae0fa8f4742172cce8453bde3fd35c17fffc2435fb4e403
117	1	191	\\x4e9ed663b538b3d9210a1b9b24f7c933c9bd6587a75d049c45e3db196a1a74b4c40745d83a272fd56330105bde31583194cd101869791203effb3611dfb7e508
118	1	279	\\xd0f211d042c8074bc503b50694606792a8fe13104401e41fc3c5b1cd3966ab0c03998b820734b50b5cd50ef31449eb9d810e1c5807b43f3f42918f8283069a08
119	1	360	\\x64404c1ca4c4c1189fdb5ef25f5c4fd51c75dbaed4d56004d0b852f0bdc8a15c77592843543fd5b91163f1eb897415e9f523511cc15c674c8c1ca3eef71c4307
120	1	380	\\xa1b85dd6d0a8b01bc505571ab7b60827b012369e87bcbedc610c4bdffebd363eecc2428cffbc7dfc0d2b5fc3ebcd8edb3b5088500d5736038f1d7d554baa960d
121	1	234	\\xf85f59bd57b2561bc4abeecd761f3b7a104f0390a53b2e479effa84ab2eea56c920c92aa01c582b7ef06de5a6b67b03b23a5c93c1b190eaf72b3a8ebfe851600
122	1	100	\\x97a77cf9ce6d0998424979bbcfcaf3c1bc354bd982013788c06cd8e7d0289bc4c1d8a0c1d44abc0d5b2d59125cab287f40714762642025f19fe895a229d1ac06
123	1	358	\\xe2833705abe7916c45fcb82dbf7705880aff27ca2fc74cd1d1ed02e7d58e74dd72b2468f891124da9f52a4c78e76b88f8b02d76f587961af581357f5ea889c0f
124	1	398	\\xbb4f7c31d797c4fec920a418ee3eb8cd46dbf0679dbdcd4fefc985f0b7cc08e66c2f302cf507ec13ee69106770687188d7a0a69fc32718c2d630f072c0700004
125	1	287	\\xead147e6d659e931d8ebc36689486fe5954194e41e9db5c669a8a9c70e3477e3932d21e2431c3e55011dc7928c53bb3bd80ca9819aa3b1ef17857620923e5a01
126	1	81	\\x5c8da3b2a1382fa31230325e910551c4ca2ce0c7a368aa011fd40d316f6a1e3e48a9ad0ed9f2feeb47377e65a6db6836b58231396fc1e77f50468b5d375c480e
127	1	113	\\x6121d71dc2d96a39f07733d66b5d3f9e2839ab1f452b3b8c196f0b5d2c1d921a0d6e440116b6f7f554b77038c8ed9b12ba820072b5e50d21b8f38260fb397b04
128	1	145	\\x5a700e0bb9b859b10423547ea1c9bb3a9f0539f9abf0732e43b9c153e936766b9797838efe98374c54fc798878fd80d443f47ed6a8286f37ae0f8eb7cf328002
129	1	301	\\xffe45ea5f6fe6054a0f253d4b6598d6b5a75c186c9914ef540d7372b420b11781798a6e3732cdc572897c6730ec76bc95a20b708e2d505830a772b5e37b92003
130	1	361	\\x56afd64bcb6c7d334d8bb48436ee01d4ca9eabfb7d6a48541ef9bdbf1d79e91ffd857518ab080e50ce07ff47f76405ee936a120bdd258087287386c9c33c7807
131	1	11	\\x6ec97b1e5e02fc27f066a031cc8d57d0912c41dc91e9cbb7aff07b545d94e67032feeea4b54e6d042fb19c99379e3c64bdb2449ab2015e98ba13064ebc82b202
132	1	272	\\x01d234da50fc4a93a6f5db70a7847d27e026f7b1a9cae5502df823eafc3ba02a1d05f41c2dab257a3a97650ee9509e6bfa28a853ee0dffad1f7a0467b0563c0b
133	1	326	\\x5bd91bf19ee003e374ca3973bb35bdd6d855cb552aebb186f407c445215187f1cfc7ceda0c5ae09c6f4070914474876e95c459f6a08018a4e513fe43747a1502
134	1	233	\\x8299b0e89a3eceea8139f15a7937bfe41b2d4aac4fbbf3394d18baa89b06c57183152b99c7ec18bf0081ff8430bf4e2228e8d2f87eff295613a06e59de49100e
135	1	31	\\x05d78dfd2965d6826d32b1d40dc912b91ec5c17d62e4d66633342b459d45a19b546ad9b95455f015b7116541f4c57b11a9ca86a963dfd48bbfbda4c21c829404
136	1	389	\\xa3df461c5c66c9f0de000901701a7084a1ddd6e772a8d66e38f81ca5ce283a87e2a9f87d43c1bf79ed68ac9ca3a5a1508ab45b5678821007f4e18c25135bc605
137	1	248	\\xc1ed0368a93b24d94290eef937cbb38dec20dc07d36c51da9ed8bbfb7b7396df6e9c56d48456953ff3a1c4ce9fc665a900863a816e47b23b82850ea3c3546f09
138	1	143	\\xb5f6e69f33407a72c05d4ab230f3bf0f6bc61d4125901dff4561047756bf0957ebb3255e5f004edc0b3f111e1ecf0534bcd8058ebb878f4429a168409549ef0a
139	1	407	\\xd36553f739c12c4672a466d31dad9ab7d90814e3733c26786d458e804fab6d3401494fa4b9b4909b4a1de4406564e3db70facfce08ee0f0a833ea772ee6b5c00
140	1	257	\\x0e144a9f5c157e257f995f2e1693df2a2e5ee098c9dae1fb82c9e1c6a9d684c37e63c837c853f99d7f6473a1f5d4b505fbf0dbebf0dc4daf169ba4813240ca0a
141	1	240	\\x5d24f67268c66619d3ca7728826d841a8fbefcc30a75521c2b789307944e8e443baff3ab571335a480bba741a28bfd5b19a8c849764e1ef60c25f26c4f29dd0e
142	1	61	\\x8a51454f2feb3e269aff2226429bb779f1aadec7e072e39df9bae3a6fb9fe51435070861256cc96f403a895b7e2977cfe4491ea58a4c1ea069238739f7f75e06
143	1	410	\\x78fb2667de261ff30a12acec6c4bf99eba8b9af7b415156cf0fd169bed56199e674067cdf7410e5c5c393927b5d6aca759e7e933018450de8aa564356d134d0f
144	1	194	\\xc8d018393661f1cf50e9d53ecf6f692b5d369a575308ceae6d2abf946e8b725bf5f19fc020c04e66feb122d5b77ee6656ecd70c38bd25558c56d899d3103b308
145	1	391	\\xb21c4f16a3093d3f80754c29efcbe324e65d138ac3bdd1cc3e11a95195a7bc489074754ca2c407f5f86a057ebfeb2bb43b78a28495e4c1290de7e3f01da4f90f
146	1	178	\\xb343febe9f8cb5f7ebf1ff50b699bf6b7762cbff5c8cad25ab6c1ea5e4bd19fc6a0e459f7da4298ddf733ba56f3bd76b48de7dc8b1957a919de2fee3924e8d0c
147	1	132	\\x04236d019fb13a62d783a969b45444daf751535a3938f510cf53d2129e30c39c3101aff95256236dcd6de393af10da13d7372275c9e45640f6884e1236dc0e06
148	1	12	\\xdffd38fb67d0e3ebbb745f245be361fbeb0d9d3b66f98033901839a132793cc40e3f202eb9e2f998cc10e3eea4f0057d298d673a281e76700ca491a8601b2600
149	1	355	\\xd62a5e57f4347a4e7e4e9829298efd2c3bbf5580855470132bbb0d9291bc21d2555f896bff5e770306aae1050163a883e73936f17075965f036c065c23c42d0e
150	1	395	\\x14f294c57848734160f2c16587ddf9c5c9f248fa18564d301cfd185514121f62addce970c295621a7a598e1989386a645f1d75d1c4bf248f6b63c49498b5c300
151	1	243	\\xfb9b79d3a713849994e5284922b7a8d5f4e71d71a0f65026f34e651ecf4a1226caccbcf37e02e8abf54c8611c1611fa12385e18841da366892102a840ee3a004
152	1	149	\\x86f58c886ed7ff79d635f99a49c4f4d924f0cd10f88346f1130a08c6eb95bbfa0e4f3ae018761b560aa1c3ff5b9f217aa2b5235ed50be6450bebe6c451592b05
153	1	157	\\x932ceebf084ed32d75ad54156666a5f39887631e0a15616d00754c6e34774b462b6deaa30a3a6cca7647080124bfcef7aba8fdec179480ff604610394311540a
154	1	57	\\xa7b38c6e97e2b14aa12f2c443c6b9f7382346dc2e5b4d3a98d25244f5669dc13f1eb18eeff050676d5effd74abfae607d5e81976ca1952604fd218202eb5460d
155	1	340	\\xfab22fd30037ce8af1981b3077c23fa357b3a69bcf813633e88ef8bfd62c49222cf17386acf6102c1e8d9bfc42434b8ad9fb067b4df854695aa6e91b69322208
156	1	400	\\x8bc65367d22be9d3f7a46ceb1a1a951172fe9e0bdef487cbce0ade1dfea19f48ac45f53e34f6825199119c712c5bec78052186c767cb93e200792a314a7da500
157	1	94	\\xc0c6ad00825ce4c5cab7c221c6cf40f34230a760d59cf1be5ed2a18160956e5f1ad917d52a1691062c1d0b88d16716d050c73352df7c54b95a5b2d38c6212e03
158	1	25	\\xe954f892bbf198d469af06eb5ff23f6b160a64191a9bd3c0eb2773e01267cfaeaa3df8cb614c6611b53fbabc589213f939a8db65431b703abd5022f48b4de004
159	1	310	\\xbb80c9c781728ed5aea592673590de7d1b99759621b6c1a44822a4f40a63e8c7eab94ecc239a39fa09f9ce0024aa6b5a1ccd5222c78ef2c20b989744e0738b02
160	1	201	\\xd372b2970ebdb73f82f19321c2a31b54fb30fa9f3db82366d3b0648fdb57defdbfa9d2cb44fd3bf2991120e2b6bebb4d4092d5682928839c4a37426e34aad605
161	1	265	\\xe8ebe529e32f53bc8e332e0969e896241da2f4b5e8890c617c43fc2d5253b9d306e0c917dbf9211bd2260092b8813a8296767565f0d8ad606129378c0f70b401
162	1	139	\\x245c51802c6e84cf6707853c79496e3c0ec08ae2ee47ff5d49e5dffea6897959d1a09aa5513844478a18bc3ec8339cf23f4b4bea1d9371425a4fc977f4f65406
163	1	3	\\x8fdb66f866491d55dbb8094a4ea774ce12571b923a3fffea08c19902defcaf11d8cab175dd5cfab53137e7f3a88958d2cca9ae8f8df4d35e5ab3be0297f07e0b
164	1	231	\\xc575a430a86c2dadf23b2ba99e02baae222d4914b1efd818017c61b35179e49e43189fe9e948a0b2b5622dfc4383d939d526d95d9292c8a8920b911ede2d1908
165	1	327	\\xd8e1bf8ebf799c7e794e28dbce18579cea4a5fffbc3c22b4ee2b30087bfa35867945088db75020017e4cf9669c8eb3bedb1d00126fd239dc0527fa2752bd8905
166	1	318	\\xd79be35832759a5b153ed57041ed723df466333ce5966e6d1f6a3dbc5ca53e1de3b4a9b25d7758ef2005c65a89c7f79d0212818ec02ebab88a21955922068b0c
167	1	245	\\xff25fdf6296a0aa89f2c5a5482870e21a8bc1095d4b7a6e7d71420377f8227151cac493f79e77b460df1f862a1b0301afe00fad80127d7c669f7faaf80f1550e
168	1	280	\\x0957d8df15bfcdef6c8e47ce92f37c1ffe7aaedd007981520df04dab0e6b644039118fd7562fc12f53433f1646c6dbe508553fd2f3c8e358bd2324b69f2ffd04
169	1	45	\\x9b5c1e928a2bd04818d1a25673f7151dabe8f4b8c649f7b22d2fa43e09d8343cc5c40949aeeba204531303fe3cefe0e6f001f194c12aba04235710ecbc334404
170	1	106	\\xebada0e091a6d4437e2fcf9689d55b05ac1e0f8cb17f9cfcba778fd31250ced7b351060225d6ed70151bd8d7f0567bddc446daae62d7c028a78978860366ea0a
171	1	10	\\x4c55d3faf0e0a81ddb986cf32ad572b7efd978d16bd7260803db144176d010584254156aca0b179e238e0f42390991762adcb3d10a5ac74e513d65bf687e3905
172	1	41	\\x0673351891c1850cedfee5fa5032a06c1822d942c80fd93e70f085ef56170a1579debb285053bd7b7b50ac1278c0d294a8c5aa5533db6cae285c2e262a8bbc0f
173	1	91	\\x49daacc8a6f56feaf371b59665c119ce1e37708e5227fa0743f4d9790563503b1e9971d42a92a5e90dc85aa3549765a636cf07881fad3144bd6edc221a481b0b
174	1	365	\\xc1f1e80f819cb6546824b8bfc2b0253a3bbe078c2b26adb080f23ef7087c657f13e9c31f252b70a6220108a69b1709aa87fa293427ad6c39df7bc3dc0974a40d
175	1	325	\\xa1951f3789d4fa5a35b447beedb2f7396acbb43fec7e27d451a9ebbee932afefd44f1bae0916490f1e633e6ca2af1a5692a429b6a29bc9877d6c93e5ba3a5702
176	1	419	\\x35018798f71debcceb424a75c0441b74c0a3afa971fe6c76741c31cb78f48c7482bdab54cb3af8f6815ef77a5ab9645bab95f4852f81789b7d1e78394543af0a
177	1	133	\\xfc3fbb0f7f88706c13dd250ef63b8fc54356cbe2a914921bf3c386b0613f384a5d805c2a67af4a4cb913ebf3a7127100dab787e1a3bfdd342ef21e0fdb062f04
178	1	224	\\xac6abb81b7ac88b7eb3902c6e9e139ef539caf5de0f5783e91c91859e5eb58cd0445932859f237be6784bf8355f04627f920115e6bdee10b066182df91529d0f
179	1	222	\\xc2bc5c2ce499a03d8715f2a5fb4532e687a6dfe6dce7af695e8d5fb11cc160d2e8f233ca72f61da9fb0ca9d1aac7e0967d094866afecd7184f2aef0970ee5902
180	1	99	\\xc7b8b74925b94a1d92c6c96d23959064f4e870499eab4ec9693ffb42bb51f21f37825753c9150b10fa5bbfd76000f20f97744ac27dfbda5a6d102347ccb28908
181	1	16	\\x7e8198e930ecc9f69c4a5dc543f05ac00f462a06e8e956307e5697c0fc2b62c582889102275f1cc58f1fea6e7ba8eb62dc9351bd0b6f62796d589b50e470d00a
182	1	376	\\xa0656d56a1c58a23decefdaeac66cc93a23ab77badf111732410323c281e00423dbc09552f25427f742e747438dcab095b529b46e6880c4155c3e9285052650e
183	1	362	\\x9be12f0278ab46b1211b17594f71e583008a31aae547ecc94054346ca1b6f1f2d089afaa6791c8be3226a32860282233cbe0d9b0beaa31b5e6370c809ebc2401
184	1	298	\\x927bf43f287dd5635f7c6a425c53ca069a3ce1e7bda3b05e07e0c6ce90d820acd7dd10f226fb55c8f716af69375843d04e91b58d58f7f734c5c224afd4a6ba03
185	1	364	\\xd869437bfc8ae97d7a00b76d8c6cbc957a80c274fc52aeaef0dbe8e10e465309bc38abee50c42be005c9dc5ac26e155733bf6438ec49108a0d0ad25936868f0b
186	1	209	\\x8675189c4b914b2be8733811457d59ec953834e15f9473df0b49c5c3e47b31201f3c52adde6da39225e91138a2153c825a3a62db6ee7d0b6423769586f406e00
187	1	320	\\x0ddedcf9384a3fa0ab90016adb36b88d4ffd6759e91320313aa130e64c0e168ac2b1bca07289390a89c6fd841685e73759f8348b53930065497cd479979c2408
188	1	179	\\x0652301697cccaea6cf6bf116ddad1ec582d3f424b79dd3fa1792aae5d91b15cea449d8075970b8af5c9a6466369cb428fae5eb4ef7b86bd7e24fe0d27723a06
189	1	292	\\xcda7d7cce3d8a91169b298128b3efaa0b60eea9b17dbd54e7d535f1bc9dd7eb24540b06b1c9f5cacb40026f84dd8a541c45637d209d3149a53ef06f79abb3f00
190	1	371	\\x07b8a0360529df3fde4b9f43e9a8d52deceab5ea8b665454beeca9fab80640a6c46c461954768ef57a8f0fd69948f9332fb8c2e2c00e1709495e9a529b195c03
191	1	189	\\x97b34892bbc968f8f49b5bc2b58ffe43c5da5d0915173ce5efa0f233b8619cfe568d83007d841e34d88e4509544d8061d088aa8f30ad84213eea2e392285c608
192	1	193	\\xf0270b085370dd4a6ebbd0f2824b95b0a7cc77cc6ec93f6078ec1ecb9f3db805ecd27ade510762b345966dce30a7173fce46d373922e03e70ad030033bb56c04
193	1	379	\\xcef3241dbddd65807e85841d8947a3dcae07b233d077a1305d59e91b0b8dfde0af350d75e621ff3ea8de5fee8250e9df8a160fa0e36d5512816099ed8d947a08
194	1	192	\\xa021f4e430f2889bd2f493c7312746068e6871b7a93a6a47c001fddddadef2beeefb4518e55038663407f134e747eff8192fb767f26f82d97bb64f8d64c7d90e
195	1	229	\\xa415b83a250ed4a3fa67a83b8abda7b74e26c1265feda2bfa986e065bf44fd4980f5a725521fb1b4ad08919268001a88fe5b610fc2efddb930e2e4c3ae756d00
196	1	239	\\x5303f04692a1d7ad4930e807969690529a161e5d2625033368661ddcfcefa9aeb4306c2b26d310cf5ce4aa22589fe0a3ee6467c2219b496dadf9e61d96bfd80e
197	1	309	\\x1e5bc160226fda7a9d09a178159fb80dacabcffe9e5b849db36c8c3693f7fa706ff2bb010cb41efe035b2dbf9593636280e3511fcadd9d076a2586f0c435030a
198	1	71	\\xaa2d7003425c3aea6c5c1a5135bab4bc168e4d4977292fab969c7861132c69bf9e4260645e1b437e2e97af5c22c4197bd4bdd14914a1d320d5a900a273c10a0f
199	1	332	\\x7e52c8f18f4842b3ea08b5c4596be333d7c3eee812a057d6168ed4d87bfe1ea18519ec0ff4a0ec5d606b7bb1cc14310f261381d233dfb0e325c8054b22ddf60b
200	1	263	\\x7727edba9479a1db5497f255fa38eee547f15e248a3263a1302c6f9f88a1026ce417cc88ad904da9529fa6fa55a065ac0319f01f12b283f63ba59ad5274aca0c
201	1	294	\\xc4b223bf5ea104fb1ba5a7ddc5d9457e461536e44f0f7c02e6d2a767bd8e3794ecee83f57fdd322167904a37bc029991f7e2d3a173dd6708ece38d43648ec10f
202	1	13	\\xb698e62250cad190f7dd9fb96d24d18378edb69a4199df1cc19c9e78ede7dfbb31333464789297e40fa64bd04ca7cd4319098fb3cd5f9cf9bcf50f79a4e7b40e
203	1	417	\\xf2d5442c25007c21989bba1aba9cecaa964ec8e5c6a3cbcaaa60f43243ec2dc23904dbd2cf6edf6e60ad3b5b116a577f000a715da3b049f6125d7b3a116e330b
204	1	35	\\x93259dfb7911f6b2f8ac88dbe12d16e4b8eeea5e938652fd6f5b4d478b6445d1dfe98e3dcffe51ec04691137f945d682c267308763e373d2427763845baeb306
205	1	394	\\xc164712c78961ade2f516bc0a0f1d3ac64b1ea89d2a68dd8e9ff7e0f2b9e8c4896dd0cbda1fd2ed90669ecf9229bfa165ded0c8ba5c782e46b1f214e5bbf2202
206	1	185	\\x313e14ec48d74ec5a37a4493ae79577143d633aa50c8b9c21e233a17d1a11b70bb7027059afdeecdcb38c4c993a3f9660887913de9be195538e90ab20a14de0e
207	1	285	\\xbb5f3be875252f2cfa13a9a6bd570e00629afc80a9d67f2054985969923ef0754f6dbb355d03a02e04cdb07d9a230e4bc3ac2fbc79f652bd4b82164762d69a03
208	1	293	\\xe675db4e6ce24bb790aa64f6ae1951d63db6e0c7157014327e7159e48f33b533a2511cc182147222a5b3d638403562821e4c6737bf965d1ef4b4952d6db3500e
209	1	369	\\xc1f15b91a406869914f908c270d7c8b254c389c920eaa4606afdd6e01c55d54e99d5db88159e689926802ed8e9e828d1a043324832ff5b90079bccaff2cd5b07
210	1	154	\\x6de7b0811a2b5b0d1d67de401d8181b9319a918f1044643c9c4078b19e1f6906443ae9a051f7db5360e3360b923bb74fe3bc46f8f4be3e645f1584311f8a8705
211	1	308	\\x7d4a5416f8f6abfd0c31a5cccd0263d8036a29ead98c637cfd4b21ce43f6e6956bfdf13da0d2452f8a47fb879f224fd4757bed43d81425d12e6977defb4e0a07
212	1	188	\\xa956c9e9c7f5f8b7c031f2e12d1cf05f153eb4125f63bb2d344d9be95d9d22d9bd42b53c3ec3ffce13af6c229c3a2635f70f9c0f2917d238ab2f262c417b5505
213	1	98	\\xc51dc83037195b6c79f3891386a523374c771851cf87c268194391f7a3d45ac5d0853a0dc8c33f8a917a34feef37d357626d79a33d89c3b0ea765316d449e608
214	1	396	\\x50a2991f2f4d128b32a23dc81d18b7e31ac00d3a87ce31860797e04d5f742a0a9fffbec8f6964b24c9771f3ad9d3d2e6c9d9b24f47c4eeec3afd2217a0a52a04
215	1	144	\\x7eead391ec5662aca5c13aa02a1302d3cfe68ac693c090f7ee4bed1b6daf7ed9716d5aa6a360b883523d457739dcee10e067d2c001bde8299e89ae27aa39cc01
216	1	418	\\x6cf298fafbf84ac70ecc4e098874b19138f974f72951bc939c963cbaac69bafb9e8f9ccc122045c55788a7c4b973064f6d678b95b2d236be16c2642fed9ff50d
217	1	118	\\x3a6f7d86c7d8f0f937c0337a00404bdae128bc7a4b79f02c1fc76cd85f928e4daf6525ddee5c0169f224741b9c8def88c0bce8c2b71f1036765a0ae00ea0d60c
218	1	336	\\x3c62d63396929a4b5197c560188a467c534b6904c62161ae691d3c1c4e8ee1bb8b3d303ec158ed770392c6c8abc89057b7e8be9dc58d267ce91c1cc9d97eea00
219	1	412	\\x1845cbc40188b56204f0e7fad19074a2f1d2540196f02006967a2e7b4808a132dbb96604a1851b180888f2c5f5b6bdb40cdd3d127e162566dedc330771f5bf08
220	1	122	\\x510b85dabd48b9d5b0620d90e8537940243edc9d8321e30f30e88881d11e3bd6f85e3a50817976797891cff737d8ae742dd0d102538380f90d69534b4ddd6601
221	1	127	\\x77b2b3394c9bc72cb51a4540f97ff7787244f0f1ac2f5a2634a51e70351e87eb8cbba86675105bdfdad855a739f18a2a38e69f4614129bbc394e06a2e0eec40a
222	1	230	\\xd37158d915933fbacde9cbfea44abff6da92b23a7cddc0a9ef2c7f2c46483028b78c1a45ee403c55aa7b71b7643a6bad05fee7e32565c7c58de746e4ecc23b0c
223	1	80	\\x144157fbcc98eeeb1dbbfed6641ff0ddf2ebf7fb02bddd1cedbe28855f436e78bd2b4b54b976fa856321b2b0389d3dda2c3ddbdbaa69fb38b7fa0b7959167508
224	1	59	\\xff26c610d363d9c19ef9d898defdec9b72d0ff036cc94b300158fb62f4c1855959ec2a2bb4e352d781def760aed548c8c1a47a90dd30fea4196eaab96922ad02
225	1	212	\\x899115a34c3cf8b9fba971a39e63dc5c4676fa71a36965eacaa112964c70fd4fd715430b49ee638e532eaf7413a3966a3cdbd6cafed6795d166a67839b91d30b
226	1	223	\\x0f59603063b3ab6618902e488ceab3b20e6f0870924d0b422e38040c8e3e5fa57794541b2c904c5a1f6ab6c8e59245cafeadbe2cd6bb3bb4dbef2a873153a104
227	1	104	\\xd2de151cf8463a09e3f00fdab5af48ea84c00260ac194aeba7b5950ef40bdbd654d220c5c05b8c241b7262f3c902ddf2d2b07c0397deb28751a7ef9ae174700e
228	1	17	\\x435530fa4ea29d9c525f647b535da7c2414eb2e8c1757e6cfae68244463f27446778c33917f6b3efa94defad1f2b33cba8707692e6334443e5656ba74681a804
229	1	107	\\xdb0725e40ff1b3d0c423de6a13b72ee6d41c5e2599ee4ca74b49d9497f898ecbf53ab019d89c8cd692e16291fb35f7f2550e79f12b5ff0389e34021e025b5b07
230	1	164	\\x3eb2d695417518799cf718c256b701b9013710663784011de8d221133c53b9eab124fb1e867d10760bd5c976245b245dbcfb9a0fec73f45cad3bb9bbfe47ce07
231	1	165	\\x10d0e45b42f0753b0a70bd6eeb5ba8aa29cf2a7d495579003ab02737b934d2a41269d14f4eff33c1633926b48798675386d2b755949ff85b36bfa7a354626402
232	1	112	\\x7a04a2c8c8ef1a50ff14342b736c4b5ba0a3d452d649be0231822c5f3e1858cd86cb1724677c0ad9d7282afa22fd934c75a9a194a11642e7c509a9c1f27e7e06
233	1	95	\\xe077e1589ae329c328b85d8c72b0ec97e3360d7a78e0242e690a90c9336a45cd921bd74a1e9a1a10563a9df5dd18535db73af2de4bab7e6343a79b2c4e37d906
234	1	271	\\xebc26763a293a7534e644fe7f775de974ca61eb4e686fe18ba414c73e53274d78249c5dfdc82c1f1aa1890c9719bcbd67bafc0b9219279cdb433ab9f1c418f0f
235	1	232	\\x395ced24d4d4c47209cb83a4920d3af13e05ce7c07368c0c78bd6cd3be621602b5dfba97e629e28c7d9a24d8aa240889e7a852c64b1028b57ebf943d662ada02
236	1	319	\\x41f0e78e7053cae46a0ab71eda127833d5759072c7cfd05112e64895f28b20b0d619a25ea23325b587eeaaeb5bef91cf635784b6a213b2c3372a1598823e880e
237	1	264	\\xaa65083e1b6dba87dec9032037d42a26ba83a98e4dd691f2ca1e110bafdf46d4806c2ce8888d20b76270f3025d95bf3f297c3a4fa01a5dd7e693b7e51049de00
238	1	54	\\x8c0e70778eeb36e6151df845541d80fbe6bbe18ae351200bed49e666d124db78ac018390f3fdcafeea3e554b2302e03bc64f3e25882daa7eb165ff77f7a4e209
239	1	15	\\x123bf4d9676cd22a3c773a03e474b9dc086a73ad02ed6847000f701fe6560df4ee2d1bce47bb2c32e3cd0aa7ebd3920f523c158729224e90a609c93c621a1e03
240	1	158	\\x0b3c9b56a65d81da5b07f4ab475fc0a73af5bd1d1b342c8dd530bcd3a90369ea9af3372446971f9b8b74920571bc658b0d669c8aff13fa3b10f992055c46a909
241	1	175	\\x8cfcf6b618415bd7d4742be368ccdf42b4c82d7e0faedae0748b644f1f5db2ca8c513eaec09d1dde4ae72be3cbcdeacfd5eebcb99eac06d8c758b2c49e3a3f02
242	1	406	\\xcfaea458b3a34cb78f0924ab764c7085f0090ce716bf765e2280a15f7116735781bbf59d5df112d5de365a1bc549d43a0e3c7ddb13640b114c8802d270a23a06
243	1	105	\\x68616008470cf0ec9038e5f1208106a89c9042e3f3cba6b04e669713354133104c99f039654b02278298c1c21ca0cb9c256d391848b0fe14524cfa2503940609
244	1	252	\\xef92782e11b81d4ce2c1a1fb3830179dec9387f13be42c7ac8792ff1a240ef75477542adada9f70a33dbae04b08bb44a788e2e90d2f63e06d9df3d86393d490d
245	1	342	\\x15a7d7d9bcd9fab1f1a22cfef78285516c934fa9daf12f6646ef9d7f8009e7f88116b592eb3cee8f4bf1afbf6d0054febef1e931be33f773ee9bddbfaec00c03
246	1	321	\\x83a44ceade16b97f37b844419afa8f95e668ccbee5bda78f75b1a0720e7d04be49c3dbf83116f7fbed808fd644f71931cc19446c99532f5a771bee42e237b20a
247	1	196	\\x04d9f7a0d578871adadea0e213b913594f252312ce470215940aed0eb84eefb64fac79278e4cab54715040c3b5a7b006b4681ca00850a77ae7d8dc3549d65700
248	1	70	\\x4cf1c7b4f7949aa1079af1eb316490a1013edfd9542142be3896ceda7a9723c36bdd0a58fc7e8d5e5d57c07f6642e301e7353ecdbeea967d2754deea20a04d0c
249	1	77	\\x0854f9be191ed22dc9000e48894caa9f8518866b58a04e0419091d22fd032f0ce32059f685ff17ae0a53467898d0d6cb54c236af14cbc5c93f7b164dd793d30d
250	1	82	\\x3a8d313ef825ef695fe082c2d8f7c88e9b76e81eb4ca80c1a66ce79e92eeb1bda8728896505565f6f704c266562fa10504249e35a98ce22e08a0894c66c14508
251	1	266	\\x674ab6d4cb8606081f4c9f5aa51a15587c8452d6d9e393b2fcc19f4841a40bed4ffd2ffbf74a123fc3e65d5a7667097cde962ecdd893fd0abdd191361ed0c804
252	1	101	\\x90eb7eeb1ce6ea0a11d3a0efd6893c29d859b746f6ce2b98527d2a8325e28fa04ab5379d8f87642c997ad6c86b4774097cb4ddaa9de151c7882dfc84fae5fd0f
253	1	134	\\x569a8dd8d3eec04717b9d85e36a34456fb7f3f88318add16c1e282216aaa38e00efe53ff65eb9eba7ff3568cd5991bf1050593799e7289aa287b072f9023fa00
254	1	85	\\x723ca8e39464f497c0b9e27821fea08ae20e7fb9b572fe27918b95755a7731a7264a7c251dd694066c3875eacecbc8af46d57c47b125e5557c4a31fce594af0a
255	1	33	\\x84dc31a331892ee950deab64ccd3ef3ee026d1670c3f71e5fb785772b8d437cb9bc1abc39d580d33082ca8febd97fb5327afcb38c3ff684a0b7d421b99c5b101
256	1	18	\\xa71a5f23e0ee5423fdeaaabd9bccb7c7e8f1b886eddb42d94847468155ac3b526bef7976305ba03ac53a97a52ab6792977f7ed12c10aa46d6c756c37973b200b
257	1	347	\\x865af3206470546b0ba38358436c621b1c716f99c95e740a4b8a0b85790bfe53bef8b6128ba6d03b1440ac0588e61e8d19bf9202420933def0d9451b6a121301
258	1	130	\\x39cc893fb478e925c21294dc67877cc76a8158bbeb6ab2a51e7042746a6fbdb31f9807abd5370786ce4d7e4a7ebb92b718583ea0fde11776e338e7af05bc620c
259	1	351	\\xb5c8899d5961ff18e0ca7cad36966a8b74a2fffefe377eb68077b1587549ba208ea6d8808495504750bec3c361d5c01656b20b72256a0a2f246a25096f327d0a
260	1	227	\\x2a3bf38368920d3e122aed3aeadfe30ecd9953535465fdd29d083611fd1304a51fd24be7888198c4f008924285b77cf9bc8c170ec5e3f409cd63a76a214e4a0a
261	1	305	\\x897fd40e652f5d1e7cc544d3fcb5a79f07dfbac3e4dffbf5c86b1586db6e1827aaa71ba32207eb027dc35eacb930cd95f253c0c92d859d8d57aa5b24f7aada02
262	1	216	\\x121c947a04ff6d862599873fd3db527443c0cacb1a1cefb8397a2775f3ee8da913a1c68103afd1a0515fc6ab546d5afb74a01257ae57c041cdb4f68b1ec7ce06
263	1	244	\\x9187c11868f8d74e9907c8fc39f595f5e1e0bb99fd5b2dfffe3b05220d610f5e272863a35bba1d0fc00a2fbb5d0fc9ec868d72a8054f6449f9c757e87d58d303
264	1	6	\\x35beb2ce5a1a4195ee7176acede3cca076d5a7fc3e8ed9dbd4f8ff4a1f80521399560ea4d8c3700572e3e76ea3f6106b89f4ba77b5d308fa4727729225cd630f
265	1	136	\\x9b1e437a5867a75624fab6278dc86b45c1c30d3b458ad99600d17b0a16f82a814441aeb38e4d640df6d5c6a2c7778232d80ba9bf95c001ae8af457f2bb09ea08
266	1	171	\\x12cb1fd51847a2d12b9b6e71477d661d5aaac8b5ace8b1379e9972dd499c3bc89ef47d7e3bad22a4351e489efe75199b8ff30d2f8ca88da71cea24dee0f6d70c
267	1	76	\\x56227487fd504fbea45d98d219ab5bc33f338ac467dda6eb0bdee55875c7f4a506883d5a0e1186fde9a49178b42c84c14907017aa840e4d7395d51a06bf6db03
268	1	49	\\x6eeac50ee2538a9f107b76a6de27d224eb4e05990d545998f33fb42a64d0e3f397165baaa16c489889c2750d99080cdc8f17f097366d613138ead38753429309
269	1	150	\\x16e6ddcbd45abc7435452d72967dae1d2bbe1589264d8e845bbeb1e1cd015461b8d1f514d4b12f4202f076ba69fc566ac885d27a5f244b812d14bc1c0238ec08
270	1	377	\\x51ced08e8add8c9f41e1cd7ffbccd21220aa6b2db3bf47964a74859fa1881d2476281db9a249ac3bcddf78b78a5090334323ba7d54010d61e473ebfd5b71fb0f
271	1	259	\\x9051748d8ac3439d7876b5dd82ae25f500c0b19243a4ce76603a769edab779d629df5935009570b3a1da69b02546f643883dac29c57731ee85b4e21c761c4002
272	1	52	\\xccb62f4b939a9cb8606335ee6ec2bf3c91d8721d2505d443380f20c90c70ec1534336fba7e2d23ad023d607b7c9f10837ffb5b429c317961d801ae111465d002
273	1	277	\\x7f27cfe4b4af641dd049c34b12898e6da34ed80a291ecf669dfc6cfa92f7610800833fb9fff7792e7eb9b2a57d2c36b026fd864cc93d7835ca4f1c699d00f10b
274	1	58	\\x6e8e2d8fdf70701c3464f518e2758ac108550c11e40c2d6836be958641509bb48199a822db6c3ca85aebf93473237505293ff84699060768a7794fac01614009
275	1	331	\\xbdfa3c08fd0a469ee53b7444133018925536b2f533c7d77e45ebc4ce8439916a45a873630d3b01a44293f376d45bfb6aa01f3f692ffa938c91f1dccd2b8b930d
276	1	386	\\x14bb98ac55f794bc1cbfc80e3e921c833bf2a4a80bd8c8e59be2e0ff7d79e5ee4c05260501169c688d7828eba3d02de0086e3989af3c9a2523e26adc467c2c03
277	1	206	\\xe724ba0cf3ba9ad9b17790e7765f2f638df0656d355871c9fe9aabd44d804eb28557389b6ce76cd86f7f993277c77ebc311c2d1a2280734ecba9db7997f44d02
278	1	153	\\xed584fe2584a10272f54b2dd845a5011b38ea85110423fdf35857ee2056ff267a9955b74c427877bf1432f26041ea832015435e6df37e30868ce461210cb0103
279	1	422	\\x6d8d7dba18d67bb0d4ae0141d7b3f92d4dfc830cec838d395ec73d5ef2c5cc3965faf485dca392ff6eb098e9100b637e71c7a0319a9ca05f0d5380c444d51a0a
280	1	274	\\xc7969c72cf85aa0a8082ab042a8787ddcd979332addd58e20b1028f24de31bedd130680ca58cd78299339f32823ce565047a000b322c779df79bfbcc1c83b005
281	1	283	\\x932573eb43faf58235b211d5b080f98e80c20f3b1baad29aff0c00efa9e4e22543bae11c2a610b307a556fa9297eaad2bf3252ba07b13937e4a41d36f8efe903
282	1	296	\\x035e4d2a88466f9d4eadf96ea2929f6dc09ec18473121ee15f8e86933bb7bbdb8bde6e36d7fa69b54ee1b6364e762233d58e7b00bb0847dca5eb71d6dab5ab06
283	1	27	\\x265657fa054099b69636c660c48f0a3ad942b510ce8fef0d0242ab61aa80920c641b648803cff9ba2bd29d5bf95c472e3a00464f614ad72109d90d628dd8f702
284	1	368	\\x66ffa59df7829e771fe4082b736c88fd68a2f1d9f0b4ff634a276b3938514946b7c0cb15eb34b8ddae211326fe253cc481b7841e2f5dd152c9b6106138aa130c
285	1	339	\\xc42133ba74a0ef6fd7427bbd2a7940697318b7f108f56045ff44d19686b582d4ce88ce2f9ac7ec29c2a0f981aa973d55eef7425c9fb213621923a037c0511b0a
286	1	300	\\xe12d1597e1a2ca5214edbb85e58e7d46243b639f0479ff7f47574ca0c211dd85be364fdc3368fba6d5f5424cd8122fe8c2f7d124cdfbb4276e77f7e223b18c08
287	1	370	\\xddba265937c35f6ded94b034ce8cce7ec8cee16b2267bfb0747d3ae8fbd2a45519967a58e119eb117909bc02726cbc43f1287a203652003224bb4fc9e5a9a90c
288	1	408	\\x2b1b37f5c9578d631222a53b09b320d3f80344797bbe8516bbf8a6e02ebb6c2e07deb054d33cb68aebec237987d73cf77c2c5507535330e2312c4c8c2f440f0b
289	1	138	\\xf82e29f76d8a682a4fd9fdd7eab23ffa45e637d2e51a005f16a0c9617f2554b840eb3e81d2988a5d81137650a2466a1ecba09d06e7569702da2aa4fb0b2b630f
290	1	89	\\x8ed5fa43c93d5c21307b14971ac7ce1855794d53d4598bb3ed8420e8d828bcb5b933a7c24fb9dc192975f81cea566c5749ab2cf5f82fd88b96d5c6aafea88c01
291	1	151	\\x46de2f5f9b4a587b128bca86ed5641a68c6893fe45fee8d6cf55a4db907d71b0e088ee9c0528b15676dd605ea195b52748906fae718d28f8f1b778e99614c00d
292	1	116	\\xfa74e2fb39b34aaa10c1762507aac9da13ba282101f32c1cea17beeac6cc8de03a1a509f02bec5865c022e9983cad1c671aedd5de0b6040dc90c2ade908f930e
293	1	242	\\xead339dd0575e218498c4e988982f325f92a1022e33cc8ce05465857ee7d8c710e8cf31bc7665094b9e392c461ac080ad72c944f24b5fe2f40a20fd037a3480d
294	1	356	\\xe633beec3445bac5bc59e57d7bfe8381b77adabe451ed9b2d3f609854ff917721b7c8c74dcd2947a79f38e3a03fbec33ecfba9ab2f59a564ed9702a4751eae0c
295	1	374	\\xfbce2a00517de6285c7adbe55edec7b56bd9ff4548b90bb75c2c45bff4d0d173890164ecb3b4ea735467bca990f9574b5bc2ce264eb18ed6535651e4ca491002
296	1	125	\\xb357c0146590e5708fa123acd99ade0ab664a97f544b56440efbc71dcfd10e7653992579b6cde7daa0adf5308fd7971bf552862e1f518a6f5c0d491f66604501
297	1	108	\\x0adfaadce10749dbc390487cecf88eccb643fda34c060e51921ef99db24fb0e389b4dc2d6ac1db9d27b6b824aedcd6edc3fba1e56b862a5f4945d33d74b05306
298	1	306	\\xc2d5a4f13ce77d2ec8ab0891f742fdc34d77cadf60ba4827df51f0e07e868920c11a4f8224e7e3f2a1ee25f25bddf82b6d1ad87ad0945cb3766a39b51d36ac06
299	1	267	\\x95fcc749a66b367a20e60a0342f4cf4f44f3be165227751f5b003ed92bd2fa18745620a13c738384e90961f090e7838d515d5034dbf8a8c3a563cf0b1a6f7e0e
300	1	36	\\x3ba087c19ac4cff7acb76f4d451238057c0ed7afca2626d71757937e9ec23590c364642797d1882c5b4efc8488d4c0906e0310da42ed485783b727e6eaac7203
301	1	22	\\x661ca76b76ade3a100bb5d611854a78ef92b4859c081f6fbf3a245bdb2eb0d17a5bd01a568d87f79327a18d52645cef23b3fc67276a9fdd25ee9c37074721c04
302	1	254	\\xf5280492a1cc0ef716de566c5ce5cdcd52b52eba59f6d2ff25c48cebc9a6cf23cdd94cef19ddc1e042869eb067f2bda42ba5bbe4e38ec56719c52be1d7e43c0b
303	1	246	\\x6b316934e39b4c1bec4ce9c3bccad53c886beb1d8046fbfb6ef12e3f9cd5125809d5f5e3551d5a1696b9bb1e6201e6e09cc98d9ecf9818b9fb2df0cd8c54260b
304	1	78	\\xe33f91531ba381aef3ced6ec2df06f9fd779011fe4e8fe1dc1275b618c1ffa1929b4f001fdeec3ecec0c8724696cdbd9ebfe50a1a10fd3c97d9c8b85ff2abb07
305	1	142	\\x9d32acb61661a0effda225ece4bde5f6178f1f70f09f1f05a679abe3c326d0787c33b67d231957e1d3acc1c594c70c7bd0c3ca471d455101b5f55b371caf1709
306	1	238	\\xde2579d399a5fab6058a3ba051e2470802501dee3d0b43283f21fdafa60d6e635c34fa1a297b3fd29b6eff82b430db70216af7179bff07791665ef1d434fdf07
307	1	420	\\x74689b717ec0963de6464accfc00a1637c6b1ee62b353cb2454d379dd15c396ed94b3c54f8970d8f1d4b3efd2cd63c88e093562c0c56459a38646dc21a8b0400
308	1	207	\\x714f3c65dddf331f9f38323cf3a81c6e307ca387a207fd45ecaefdcde2d0dfd255c4bde2779d47b63e4835cac6c6af357bada441f115ac8c65526e6c66ad6801
309	1	182	\\x502d169ce6cde5735a2d99f3f8ad53847fa676d59d5b3e9cc3b2c4d20bbd90e4443aa728fe5b403614e5e68d0ca89a99e4e5ab98073afb41df5c3e6323b60d0b
310	1	261	\\x49b1b42473b4985b1d5af982608387a76045caf114df207a4aff1d164e2979ae6c24bbcea5628556da90e99bc163d1679460105cf98ff369083e4b0550776b07
311	1	383	\\x41a1c4145b0a7988412ad3b5e3421e8caa2851e0c2dc1427456c535b31cc01a651fa276beff4f0119170c5c18cbc36df2c4b11ca8165f70e8f6e0f5c646b960a
312	1	123	\\xecb705611b4e034ba337332c04a95f3deee21fa8649b50507f8c4cd28379cde3ac61b447572173dec659a6e8410ef1b1385a1f5eb6a13890aa78b84d2dbe260b
313	1	273	\\x4d4adeb34ae06d78ab6f84cecf1abafe6c74091c3f53a7e0d5fa78220b3b3479a85f0860d5fbd7dfbc4a2717df22695634df63d36804152dfbfeb1e40106fe01
314	1	221	\\x6752c3209c8b6b88ff402e5a0deff4cd092e2d7486e6ed59ac25f4a667bfb4e104b73d0b0eee1dab680334b6a6aad8aeab4170dbea33bfefc3144f5f9d8b6c0f
315	1	214	\\x7fa31ec075224cf889a2ceb7b10204ab9cc2d149f3ac0e27b6ad85aba5ab05f4b665680a3fa8ce356a5f34b4285157e2469e27e513002f0b3e21b02496a82409
316	1	392	\\x48d6c3bc4eb886cd83b748f306d13f88b4ad9290c07d47640400e725365a5ed36a70a29acb8610d91a4544de5b6654b26f57991c3b5fe77adc864ec1bfc16901
317	1	255	\\x91210245212efb2dc0b710a9b3db2d99ccc9c70adf5bf8213437a749d47ab6100642ba88ec7c0f3b1a7e99964c0a9649ed0c27488938bbeeaf6436f9d253330b
318	1	353	\\x5f22b158372a915f7bbc8cbb7642cb4fb66b977d793172f709e2ec32573885b40784748d00f189da21765a843a270751bfc3df12f7fb06f4f5c5bb844b76570f
319	1	29	\\x0b0b6dba30328089adf05f23e28b541894650b3bdf1839f8570ada038d5a1c657a54af717738745ec29491ebc9dbbe325cd9eeead66a80a5da412b4def735500
320	1	359	\\x8d3f55d265a8d21d7bd7edc28c7b4ceee9acf6ee144ef35f54784e29709a48b94e1ddf32e5187bc1b76bed36e3fccc4a1be43a39b8c39d0c1e59b9598e432703
321	1	202	\\x0d7ac26acf9eadf65945357d6bb26cd744c218db989b8383332357c622e9a1cefb82e5b187a58ff9f539ad15419f83fe97e990e9a6988688315a7fed5c854b08
322	1	203	\\x7f1de1a4b3251de47a9308c46ec497e0fdec0652e7689293f2d83f1ab95ca3b4a24ee6c6ca467ad0820182d26e850aebd6996f0a01f4ae67c1915ddefd67790f
323	1	44	\\xab5dd42bf5b06c69d41c0bbf88fbafe0667bf609cad5dcdca6024da6aa5ce338e9ada1271183c85f66a61a597d6994e77460bec41d568b5e54d9ebf7f10a770f
324	1	302	\\x453e96b0b97300b92a9f3b9f4f4b1bc2d923a933be05557ed90a2454bb376138cf3a6b4b0c6f5ab4a4e4dfbaa3e67e9a447d63c856878020d5574d1423d89a02
325	1	1	\\x28fd6c282de262ca3cba11096c8131531205426c34dc99375674b888585f4da33cb2f2b8ee9949d6994eaff245b641adeb00528ea1fa4ad922546704bf27dd00
326	1	166	\\xc8327cf43c3a866b95b7b5c315392229b3d5bcab0db152ff4c5a1d64fc9e4f86a9d207c7d132e7bec81b5f8a7d5bd57e27fa331060e564fa4be12b9e36e79d0e
327	1	219	\\xe5dee0f77431ae04ae7f89c7aaeef69af57054079456f4a1fc295eb5091be3520ef73c67d46601b67b8d6084c2bf497c7eb44ee0570c88ec2a798abe6fd35c08
328	1	352	\\x46e193c27997de6f8b10dca69d4f4e2b5f1908602c1b89bb95f748f4470928168b76590ce36fb3b318ebf8055843cc29f16274fb38687e7c4b3579999b5ee30b
329	1	341	\\xbbbe3a63220462ae84b0bae74d84b07284d4a5c8a5ee00963912736c15257096bc84e37c0bee7125a66ad9edcdc3f7759d06b1d83039c1e97871357d836c630f
330	1	338	\\xba755583c4250df7c68bdef0a3e9c5ab65e881fd6ff3a2146f62ac0610465b9301d79a1214a086db4b1cb8457611a982633cf21ff4ad907fad88157bd16d6d08
331	1	382	\\x551550eb6a9b99b41481a0836fb3a6bc26c6d270bb93b62925e1577c640ff6a2d98be4a8cb4666f25bc24f29e1b375edef4edef786c8ffcaa194d6b22bb03a0b
332	1	129	\\x1504d6f59c5267365ea783f96c95fca0811b395accdda3a0d3d204b7dd7f84ff83cc124eed82226bb828a8ff359e3660d66232122ba75e7fda66372205b3300c
333	1	307	\\x8bdafd72c376922f240ecfa6a51780cd10ec2ec22b71513a029c628ea4c34b5bf7434c79bd696893134f4f1c8c5228a8fa31cf9d27c355e9cc22588e0ff08e05
334	1	311	\\xeb1d7ad794c2edb1a8113d10a6c49ffcce5d7785aeb49e6a78e2294980b0c8cdb32254fba8f178f2c9fe48a8512277f1f03780305a4ef5c243bdc64586e0230c
335	1	315	\\x5cf1d34c8a2ecb5d0a6f0fb7292730eaa40420b5980429d0645db12a380bb427c166ef5222af08bb67cefc7ce590056a73a4c30bb13ffa4f15af557eaddd490d
336	1	199	\\xcc1b0a004a52ea4c768f8a595738cec03f48a32c68110757e8df989ec81f2bb298393ca00a2681642fd0b8fc86a0bd8e4ea4a9eef6ca6a3990f7e16a68027305
337	1	26	\\xca3880667919deaca46930812ab952af1c5f0df334f7cf2ea0f356bfcc14004d32b2d67761b65220083240dffa9ea6a252142dfeff1c1c3eae9caff403e62002
338	1	343	\\xc88465b3d263c845478399b03374e5daa65fd043a710199503ccb820b082e3260d659ccd17f6925f30c2358531413314fe043055802e2015e24a84c58b058f0b
339	1	384	\\x24482398f09bfaa773f49c1abb510d553e4a46c4220eb1b85f77d6f039048ce9eaba973a5943d6ae9f32861f054d288c9403947c0260ce1e30f3fe72f9f4c806
340	1	84	\\xf44a71247e37299b95aa43266b48321e624035aa9c5424e0b396fe1f40291ecee59e139d959c6fd386a712680daba4a144ff8dcf5dbc18aa2b597100aec46c0b
341	1	372	\\xf5e0c4e0fe675dea62a34fc91ddd363378c98c3c909e0946e91579ce8cc3e1c2d9260ae4fde080f1c612f8e891a0b2c607efb17937af01bc3360cfb559b09b0a
342	1	217	\\xdf599757fd06394c002fe9fd7f838eb98091ec8435883dbb8133976e76a6998e408e0945747de80a6c7a9c7b9a0d63c0136dc6a9f0309f23ba8e1c7d510f120b
343	1	114	\\xaaf0234531620acdbe42a2b93751ca3e4a3bf8cb86cea39b0d191010d5602a287ebe5532620864e1c7e41e9a0380a55f2fd98e1b59f119fcee3fb8f2a541990b
344	1	46	\\xeb3411870684969ff3022b219ca709a20f9af15f08dcdb8726fa438dec794cc7a324b150dc7216d000f436a483c0d46d7892dcbcabf2cee4036a3ce5cda51900
345	1	155	\\x18feaa58be2a42fc2d1558b24f5448116793a89108d38f07723cf27b456a0246fdd14fd09feccb914f5dba605359a6bf307c511c05ea6efba8b35d28e64fb50b
346	1	388	\\xa31f9b4353bf53655d3e58b7712a0f5312cd7f0a98b6e8517e56a2f6f7e5bd7f60c4c29091d519d5eb1f16884aa251619c33e74fde59e00708d303b39abd8f0a
347	1	24	\\xd82b4090487a16b52b59b9425b22d5f034037fc637d4b55417901a1f0ab6c33b2881079f9ad061a103ef9ec5a2c496abc6d7b461d1cee8c1048f99882c06cc08
348	1	397	\\xf4ba60dafd70fcd6472208f88b58fc52db6fac0b96f89033f965388ba3fc8376c30e5b5dc13a9c6725e865f2713ab4e930d5500e3b0b0263c742c66a3e38700e
349	1	393	\\x294ec8ca29b2f8b84e081e6634e48ca3275db77893f2f810e16546c3e2c71da248fde31bfff1d11b458892d1fa7eb877860a784639e1b6eeb2be493ccbfc310c
350	1	226	\\x51be33850ac87564cb08faa1b6344ddc97e60ff8fe537441614a6f7f64cbb1f70c29fb54263e2f4e9658ce37a0826eff6fae38cecdc6b1ae91693cb4f5085a0c
351	1	363	\\x2331fe86e3773919cff9f46b15b534edb8e4737fa013ae38e36f7d0cda7680425afc3c13bf3ef7d8ef1fca8549d2e2164561caeb83a2756fc96bea7e592e1105
352	1	21	\\x715ffb18ffe724b711f008e624cb0631751c77b26fec6c96dd5092f8404d54c9b109c60673819a8f18ebad2d171048e2e985953a50084e0009b08a765bdc0a01
353	1	413	\\xc1e994275dcbd6b6ed87e53bcdb248d0175f94796b0062470c0266cc190db7c7a06d1ad5a47643d273c02455b54e9eb3a4764d3a4f2aa34f2942e6948cea4a0e
354	1	159	\\x9da0674d38d377877aa937c856b3b46c99573dff4e4b900ccb61ef4c10f12846d0955d79ed07a14c3ab5538cbb5c67a2122cb0fddcf39b9d7b9ef595cd6b3107
355	1	83	\\x1e1bf97d5ece7fbb96d696f46102bfb83ea1fe35f3289174fbb94435999e1e4a866aa1a84d9514376ecca18a18ed90b4d41ea9c22bea2b0ed55265ee5addb307
356	1	270	\\x775ccf86eca158ae9c4d0a66176fa31feb5bef02162998bb7535a0c9e51c2a528bd6fdcf795279f802200b157483638b75b6ecf120fe36c3ab006a5484d4fa05
357	1	276	\\xc3a9f77a65de6c866e97bc15d9a11af1063a513bcfcec4c3afefa35d58461761c86b7ea244b9b6338c06114ab69320efeb992446991b892585fe3abab9021204
358	1	354	\\x29744005506e929e428c8a39dbc1dcf6c796487bf9010cb8e8091f5a760cc98b3d134d8516719c95d6fc832011125d17bf954159a6bec6446626b6e48bf90600
359	1	102	\\x9a28690d43c395cc13387382a96008a3d168bba2cfda2c927f22fe45d37527343bbc1a4d4d9a704de59fd87b7262da4ee26f33b907318517272e6ee60b1b3308
360	1	37	\\x90693aefee9e0b1faa19990593cc91b5b820ad30bddc6e7bc4e1571fd84e8f546c1a1ff033734510198110f5b8eb1ceae48992ea840d5a05fb1d9e67f470a00d
361	1	387	\\x997b3c0d87aa9cf7820e9993319174f5a1f1389b54d0cc150b2b87b90d08b7bd5a03cb2e1a9fe0c8a1dbbb73786127606d4998fd375b362986d3b14d1eab080b
362	1	68	\\x6c70b929429350cffcc474d406b2a3aa9baebf8ca56000de0219022fb1e8c2b2f5e624fd913e0c2f565577a4d06df2e5b8872786ff297adb0f08519336b8f30f
363	1	167	\\x624bf91189ead3e84bbf66d33949d56a2ddff0b52d2bc4fddf4e2da1d8ff5739c574f7ba32cb481f1777658b0c021fa54be29d0b053f502a787068083073990c
364	1	215	\\x671e2b001abba8b0cc29cf385c164a4f580dbbd20061fc06e3b34231689419b8057d8f0746a5a388681d5190facabe762fb02acf155315b281b175944df89007
365	1	183	\\xce5ef085b6e0633e12706ea79c972c0a5ddbef92722d5753e650d1541b1cf2b8e62467ed9f27835ecd83e0f4c59090760ea04b41fa00fe956a56bed2eaf47508
366	1	303	\\xee0e2f1687d5783d1ea34ebb8d0207acc3efb4483fc9d48e79a89439cff9dfe86e3d7c4194224d2db2dda14e103b62e2da96eba1d296ec61356a4fd815cdc10c
367	1	173	\\x36ab7f98971c28b9d3d67453915ad425a80d4d64c6e1905c3d70b565f568dee7e855d0b03535f22f74bd0f62247e9ecb42cc776a3e2fe0fd6336d55f4cb0e20a
368	1	208	\\x427eb88c06e5b6cda267f567fa4dfb2a4be0d681bbe0606c83f6fd2c9117b8c3039b6886d8658e0c60a12615b75ae3d3f230591a2462c6d4c21a6593a225f602
369	1	186	\\xe45ef8cf377059d6fc90a2f1f484bcb04cdc2d2620a48e5294bf2c787b05d64848a8545e2afe32a5650c9f1dcecfc545bfffe610341d8eb44235aca77cf6bf07
370	1	156	\\xb3b7ad10713516e5269efba47718d81f783cf332977b1860672dc07eb2abb8b091ce31033f8aba7e408ac83063310b0c5c57f4e7c76d050641a1634a08a44a03
371	1	55	\\x1e32120472f7123ce05dc8fc4e5591fcc066c8c3b63d1c39627abf6510bb58f1b080716b85c81eaccbaed737b75f141d5c1d37f3aa4e8e596026d1410ef6f901
372	1	14	\\x64b30bbec850fcf3716fc1bd06c6766cea83e29ec16877058d43cbe213707cb431105a1c96252ee919c307b63ff8490e4591e6e524764d3154e0b9fd4175bf0c
373	1	286	\\x91cf3f9ac8131cf64c66dbd2efaff3d8f08364eafdf1aa25d3db129122a563e4c9170b276ea7941ce7ded7c5490ff715ae2952b2ec28aec4f1abeedaacc11302
374	1	79	\\x7c7ef78900b758433621f359a35e9a1b15383631e6ad64916053c4f87f897725eb55397700de8e59ff4743d4caac6a7218b05cfc38baf0b8f1c502b09e752700
375	1	128	\\x49f87bde33a1b93e3e978e92a7ac7a57d3b4c379f0e0845e1a3805c554f259786dbeb99337c882ba9b7530b7fcadea846993c613ba62c8cd3bf55d71d94f2909
376	1	65	\\x659f24312927c75936fa40705276594b82e4f9b29457ebdb093b680e5c3ca67791e8ca54383c8dcc0efab2e316dd2d7180f94e0ec642083c83fb616b465dfb03
377	1	162	\\xd8c2a6a26f12ad947c9ec7c5e96f3c6dbeaf376a0146598c92a1f96983c3a30331fa074fa8f86027cef5cb0abd07cde25b6600e9f348da33432f2d946e3f9209
378	1	211	\\x7848ce7822a028061e59c2a650462560c712d80759deb4bbea5390d13e7b2f3f15c5f0057d3db41e81dc636905ddf0181fe435cb3797a194cc78579661b9b10e
379	1	322	\\x4137ec8ff23bba3a2ec9ff3227bccfc4ac4d9572d7e8d3be20464d675ca851a77bc12648b9ec451c645b503b2ac728ef52b1e3a8ba8cc352c710f58d661b1807
380	1	330	\\x9d07c9adb6f4e9b3bf201b0e0234d76ca175d2bdd40485206d1c7753112ef6d1c26dc609deb17297e424e08dfe05cbefc8fde238ee8430a913004d0d7267f203
381	1	314	\\x068c33672b041ecceffae247a999e7f01f4a281ddd1cce3f8160e7c7cec346114873cff6e971db9fc35f6d64e5eb29f9d175659e6d2d20ca15cc5e8f77ff7f04
382	1	204	\\xb86fcdb66f268e102b231b1becd2dbfd68a02a3f0bf66369900eefdf0792fd8af669267b44bc444723b2cb3b6c339909b7dbbe64494be46c8ac2ec5ba1765a08
383	1	378	\\xcd76d16bfd38ac0747142c318ed427c66c54b40f912024877b23709d114ad7dd7b480686b04e2cb423068963c60bd0e15a7c6457b14d6fe65a7152eaecdacc0d
384	1	258	\\xdc70e3243bb53ec7edc70b1f13a0ea8b749cf008ac188ccd5e4f95bc69692883d3c5f9ba38fcd062b3cd94cd63eb6dcee9362180e00293f1a82b0ce56859560e
385	1	8	\\x579e3997051ea0ed14f86488d8e18cd0a507babb120a1bc3af47405fedc34788b5925cce0282a3943df54621972de67ea0cc3ccb83a2c7a6b75d7c2e4a15d90a
386	1	253	\\x37f9cd7996bd1bebff7c75bb3de3ca10ccb1c6299ce0c63dd4c0933516b91ba67d90606a26a50a49e5d64461ac44cd8ebe5b109b30926ebe3d2511f250a73e0a
387	1	344	\\xf28db766b3c788f7cab5879d54bc1a9d7d31e555066cddadc4e165c94d1622ce44cffe2947320314f42a8ab50839cc2f58495d271a304b320b0e862df6f49f01
388	1	329	\\x6e6d1eb75198178c34c8fc5f12d9c687baf010c40b549cf93ce73dab9a20424344efeb95d3205383536a3f613ccf0e91e719c3eaf3dccef032663c6b83592308
389	1	103	\\x32ae5758d59008399af8eb1a02b207ee992be276d7a158c02ab2ce9bbdcc9b74225fa591ab354cfdc5adcf8de0f56fe3339d085997cdabc25258dba923533c0f
390	1	148	\\x839affbe55179374f0e418484798b3fbea31d75e5662c356e26ded69c5b0d573530054d830d0eb82d2d3e270d85b49f3b19752c5c2d9488befbd39e073824905
391	1	256	\\xfa69b6ee17ad75ac790eba7ed372a0db8761106a8158984f8507751de7bdb1c7d21fbb8061d70dbb89b7c934b8131d84f9ce01bc5f61f56ad2431ed7d955fa04
392	1	390	\\xbf49dab8b561de995f412f21b9cbead30aef90c474144ab1836b77468cc7457060a86a8eaad3eeb5890292689aca2dd7b2f3e68187e54a2318d2c42dda725f0e
393	1	135	\\xfcd939ae1c394601794a6440181aef425ba01e4552bb17763ff7531f0b78b3f757c1b3f03936d9c832d8bb42a7b32e5d7c5bf585a5ec81e46c3a5702922f5c08
394	1	333	\\x3d0267865bc98919e090f8e489a3d182da8733b6b2e86e8f776f325df5e491748c729b72a9a83de94c36397d4ebf3f710da12fb9cce65f00721eef42bf6f9408
395	1	348	\\xe5b603f46cdb92fe1f31171cc6e574681a4f926a9ef4cc732bf04f557698a79a38b83094e21fbe099f8a80d23043805833c6de4a2fcbc3c29091a48aaad90706
396	1	93	\\x04650ba9623a2241d2da8730e3e8fe941ccc7d0a4086b4e04b045160667e298f44ca166881e25b940d878141eeeccff3cdbc72ee15e61488980c9d6e155c7002
397	1	170	\\xa8b1098bcc8e738b9a1d2a503b338201be6891045708a8cfd4621f046e645622359ff38aaf0829cc0bdbe9ada9319929270b0817f97766d4abb71472d5d09603
398	1	63	\\xf52320f369b5bdec1ef50eec733143bd1b477e29114ad925b2a01e9dfe4c9187a0d49671b366dbc63fa6568b6912053f9b6f05162b76b0afd639624510b56108
399	1	66	\\xbc7c9c3b993cc8b499d58dd0a9bb1266ede481fc4011e37a1ae1935947a82f40e5c01663da126da89892c5be62a8245d68265c20a73bca97d9120bef2172f308
400	1	109	\\xb702d04c8550d77892dcc17921472dd44efa45b562af37df0998fff5c372b8184e8b316d16aa753ea458bed5269d77ae3764e118fb64b1ace20ed5801f07020f
401	1	416	\\x44f6a2aac01673e68d883aac4da12b6212635a9b01ab7efacb7784e4e8fb9fe88f27bff960c15dee7c7ec5acda4693f760cf1f815c9526e390faa2d58a4ac40f
402	1	291	\\x827011287ce769a25d78accb76a0194e569e0e2313b358f8c6cfe0b1fa72b7a28affb2e64188291247a1be93ed05cf2e77fc797dfa6ad71590b61d85a471600e
403	1	28	\\x6f61f7bae91cd102c5734d94601f3c9f616d787e00d09be1c06453b2ea8bbf5c309211940e66e5850c9aedb01797b0ec5e2fea649dae538e908b646a6ebab302
404	1	172	\\xdafa78d260dc4b10de390cd482f28369be24d0f7ee642bc04fe90ac7e01bd8f1159227cd1028c4f4ec0b30e432756ef703fcb869a371ae2fb4986124c4532c04
405	1	237	\\xff460d6a042108de5b785b522d61686b5cbda412c980c19827c9b14cbd50de6b5de1659393d75cf585cfb28aac9731760071305546ecae12012e2aba3cc85d09
406	1	220	\\xa523db90860c5e2ac98a3018f7898e832c00ba3dc88d0645de47251ce6912ed1c6c1712cc5cdde3c765d14aeb11894f952afe45f5490375dd0b89eeb51826f08
407	1	375	\\xaf2803c96650d2cd12110b72d93b88cb5c3697fe456d7afe81be6d2cb8b6da695645170bc26908b15fee20c0241439c2695db09bd5a25e8ee4f6e0df84909607
408	1	97	\\xb5c4d2e8ebd91d243ae32b078435ff00291be134b4c0efc9283138a0ffdf294b5b11a36e4616f61c3431ea34c14d76c295a87450de49ddf6006dec8f4553190b
409	1	247	\\xcd784a2bf01953642783110225e50c4fb298d857ca4dbb92b0a6d29d7da1385fe974f3d5af696f479a99978b5e3efef27dc5ea8f77ddf9e981be4f8b2ae7550c
410	1	401	\\xc0adf9583a4216300ae91e4c5bcf4980439fb4ad355141d87068929f6364e97dd77f9456c27766c68265b0a682c76eb94f3208ebad50da030cd79e45bd2f8608
411	1	120	\\x85e9c59c185f8cfd3c7b6858a9dd4ca8b444725033d4de8989f4717764316291fdc6e4e260aed507a24771635ba2e7b5f070374726c08162853a2f82e8e28d0c
412	1	337	\\xece683ace487b64d7b9068b7ce8def2c1836e68aee279cd20c91b7d289a170f17be4e74bfa1973ac96acb5acd4308f40c068f54cf60cf7a91ba8bf2979f25702
413	1	213	\\x1b2118e05c333d71922bdfb5bd6c2828a9f9b331298571f46b00de57caa30c825ee904933a0527ab898129c4e48e128dffec128ab062b58a26cdef4bf6a6600c
414	1	225	\\x27b6190a85cb14255c9fd503e8ac3e61be6eaf94431ab16f186b6557126581bdbb54026c73d22559c3b78eabb393538f5f9f31deecca1f5736c31a79c77b270a
415	1	121	\\x72ea674c66c1d9d673c931c8e310b36944cf3ce3bcae9fba9f35ed2eb76f8dc3de6f7ecf6af564a6252192698bb7c05d05743d3a33772004925a839cf8e77503
416	1	96	\\x9c3cc44bf48d7bd91c23c426ef05381f76054ef80291bf5a76364b26d7315dc45daaf16a549d147e1e8a95ba714270cec6f0a72e471e3e65e53108b98c3b1309
417	1	278	\\x39b0ed8af9ed6096035db6b4835a713e1bc5ba912f31fbc1c149facb6c2ac8f34b7c4b499225d1a001e4e5993cbc783ff7d449a6819ff3fdf9b4db0ace667d00
418	1	32	\\x59c33b4cc355f47d5352aaefd424692dc1e4d0b5cdb860ffdf8eaecc9230ad3924995852303f7d3f96bf534516afa86210a7cb9b4c868dbf9e1cf9362cfeec0c
419	1	345	\\x04de8bc905b236d99d2f1d3d714a43bb54414f2746262f7dd9d7d42f63f23597aae7de54502e5ebecff583b0f53e60fd779bdd189ae5a1993f9d1fccaf5e5207
420	1	404	\\x78695ae5ed74b426c889c9df2ca2ba65f216c2c2066dd5bab51b7318ab4263bdb21d52fbb8f6ef0445542e0fc2b5584d71509c1a65b2eaa49099714457e7c505
421	1	47	\\xf6d07fe5dbcc68873543ec16e18181f2c784327a51b439a4879dbf1a9e584d655969033e13de9ec78b79fd0edbb3c4754c6c8222a41969f40c00a1d2ded27c0a
422	1	2	\\xe68dfac492d942f287fdce15f5d2276a963fe7d63eb16741fa6d6ed37dcd2396194e775b05e440686acc4f8396518358150db6bce85c532af84988f52fa7fc00
423	1	218	\\x3358bf673911324844f7fd7b50a3a19978eb7fbd2263fbd75766b93e7e677dcab2741a054da436c43364de1b8874c33e47bfadacaedbf2bbce9934323565d203
424	1	411	\\x097d7ee34acd31c18fee3aa8a4acf191d7a34c6bb54295d970b3decf442c5585c4f8a09db4fd1c1f301f368d251ae61d17efcb6e286a4e8cbd6a0c92bcadba0b
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x6655c1bdd869e0e4d62eb112c4c3420697386e9be3df3afe5c416e7a8b262785	TESTKUDOS Auditor	http://localhost:8083/	t	1659786803000000
\.


--
-- Data for Name: close_requests_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.close_requests_default (close_request_serial_id, reserve_pub, close_timestamp, reserve_sig, close_val, close_frac) FROM stdin;
\.


--
-- Data for Name: contracts_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.contracts_default (contract_serial_id, purse_pub, pub_ckey, contract_sig, e_contract, purse_expiration) FROM stdin;
\.


--
-- Data for Name: cs_nonce_locks_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.cs_nonce_locks_default (cs_nonce_lock_serial_id, nonce, op_hash, max_denomination_serial) FROM stdin;
\.


--
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denomination_revocations (denom_revocations_serial_id, denominations_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x0070b35ec8439a0ea5606703ac5850d19d2da3d85484f197a6f0716a901ed3a0dbe09fe0ceca7291064dcc1c5ef49e180d37314de312341fca1f6df85659fa3a	1	0	\\x000000010000000000800003e389f906eed763581c56b79c64f44e2d62e656ef798849c06ed33feea30da49119fead37240c728cf8150814988a41ce2a3608c30130427e4559dbadcd4da5b998a7514674bd693ca0981a82781c3e818a5f81f3805d9fe4cdef89b5188820cd10157b451bcc574c3c09bc5e0c7200819fa639b41e6b1c271049a261b72a683f010001	\\x6fba4c3244666bd5741582626ef270f659a8275d12cf093386a2f6577248572acd5a6c429ecc46f7f8ccf6e32c790dfae5efa1f2ba4493148bec336c1f66b700	1667040797000000	1667645597000000	1730717597000000	1825325597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x022087dfa2daa767b4056a90e69ab2d338a6b154e9d1c010dc2218c8156bc5f461f10662326852ad27ec8205cd49b57bda4cde33ca6c4f132d020af1d69662c2	1	0	\\x000000010000000000800003bd034b283d98834f0f9c86358999965d42234dcc92cf001cc110c80b90763822e6975b43b05c92472e6ae4adbe84d184f389947e2da31857ce2a3c02aa757779e0f36fa642dab1f5f1c970589d1be33ae174670f7a0ca3ccccb6f18b49b49cfbca11d7e3402b82d6955a843a4c13fc79144e8a3c58c856c1212a8619ecea3889010001	\\x354b654b77d977d92a2a5c24be5a21be422ed5f574b082008c304e5bc0c80ca5152cc1f60c1f9181a23ca452b95ab709cf1252dedb5b10fe1b20058c81422e0e	1659786797000000	1660391597000000	1723463597000000	1818071597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x084cf8992a59652429adbf0daa9d659e4ce12bc19ef414d36d1caa34a241a2f583d0ace2ac2286acd791603d72556291cd39165eecdeb5e1ff761cd8978648d9	1	0	\\x000000010000000000800003c1021cb6f0ace8b45636c5535b88ca7a515df00edcd48d016d73a768bd581c949d48fc3ae99f0dfea5571fce7cae7e891caf75ee48ae060b1d3cd6401bd53bda768f4f693586d5d875e807cbe9b059c533804dc5af5ac410c0acf4c885ff8d5bc44e5136079064978bc774534dab24a8c669ef7c7fb35f87fbceea807fce1f29010001	\\x06f33afe8208be4faa1fb10b938a0d563a221005b059c3bf7326dce5087f2417004380cf5929f0b65105f1f4a343cbed9695d1ce563533983e47cc513cb0a107	1679130797000000	1679735597000000	1742807597000000	1837415597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x0c9c686300686f6c124561249155cf43681bd1ceda501961db8a1495e8a37a791a00d4adb0e5eba79e1e4e2f20834d47dc2a156a6c9bca22e3c737722027047d	1	0	\\x000000010000000000800003f2a642b0715c67789368a3934bdc9af3bce70e92ec2c228b5358d925c7124799486a9166e7330b56ec5802191b3017c7a05b6a47b97eb212e1f8d1ce2511a333c37ba08b27ab26cee24898c00183e620395c979488c79b8cb206f522a00034419e2df770769a7ee9fdaeecdea0a19a929fd82cc43532489446ed71928c1c9ee7010001	\\xd806380c35bf6b178252c28c04078ea7369c10b08a7987e8a1972fdf1b5a182c0b0065a57c43ea3cee445048ff4d4c736e31c2aa6f23b3a390803a66482f0c0c	1686989297000000	1687594097000000	1750666097000000	1845274097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x10440d7fafcb04f0c70413e4f0acbbde0b53af931c81dfe208579424861d0576d38eea9c078f138936925814a1e98937ba1f21ec4c976d18accaef86e1fcb62e	1	0	\\x000000010000000000800003c610d888150ed8301a5e1f2650b078474e5309c0d3cb7756e370d0e751c93fdbcc349b21dc11a0df99d77a5009afd24ddd5a42444be78b886db8b82e42f036955a02fdd9be6c87ad81bb884eb8d69fa00eed9e55c0b2e39ce08d21dd371afd001dbe47f3cc6dc93e4012141529a9aebe9216e63d37d93be2b95abdf60d219495010001	\\x00cfc58f04eabd72efa399eec86f7edd956697d63ed521fb5e654a5f6401a4e9edf3c3c096b78b53a0968bc23245dadea046f454ce97ba60cffe9ab88f32cb0f	1688802797000000	1689407597000000	1752479597000000	1847087597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
6	\\x118005ab7ef9782cc6ee4626a9fed4045e1205031071534188b0c50c21947b484b840f69d56c4ed3e376f846357b0810af6d5aae1ddcb924d98c0f8303eb0936	1	0	\\x000000010000000000800003e051ae3d3513e942929d294776cbfdeaa4acb96670b2da2291800746ab435fc5bb97e70f0a9f98cb60e41333d24c2ac78d890d05cda05cf717d8d154e03ceecc4ea0f5448658201a28092574821640ca51c223f47b96cbd2444de1ce1b17b4e843f576c7ef48733f7b01ac60fbeea20620b1c796aad18608d8e2eacd36a7672f010001	\\x665ac0fe5c4c23fe1d3d6402cc66327892337de6d52bfa086b7cae6c3b9f6c4cb0dc200172a5bc5bfb049fdc15cf85ed884b1ef7bb28ea6f29a227fa1b2cef03	1671876797000000	1672481597000000	1735553597000000	1830161597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x13c057cfc0aa962ae6240118e67b854d5aac81cbb68e08570f635108d2b9535aef6e88529aca8298b8e5591ffc6939323e9676c0702c624611b472103ec25ca1	1	0	\\x000000010000000000800003b6ac9f6864cca2356bb747c5985dc2c4bcb77abfb5b91354ab6d87921b909c442fafd2975b368a763cbb1a167f9d6ded931b5b4ceb37b5c64a9d3f178406f6030912d27827f1cf2bdab52a3b6f23b2186391dd2603917eaaad2d13afacad2e33f8c4ecbdc8dfbbd6fa39786fe1f533c32e11f4b1affb8edcf6d5a400f6c1d3c1010001	\\x3df915e42af4b56232fbcebe201a4e839b35e0ad99544724aec1a2497a383ac27f84eb8a5039793e75a28b3940e73d6f043070d4cab58524ff60f855d0f9860b	1685175797000000	1685780597000000	1748852597000000	1843460597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x138408a39e4bc9df7bb1fe23011dc8835db8fbc4754779d87b5c4a21c018164f88ff8b81d57dd56d7abbd0b1ecd27f5c93abc0e8093bf75cebc2afb5838ac66b	1	0	\\x000000010000000000800003bf978a7275d6089c9db7a2b784cd54e96919ab3694d867f53d5c9b3ea0d4c8d22ca60ca38324aaebd7e8b06ed49182020b302e1fd3e7eb4b9d25b38e89edb8b254887f13dfeaf1f07e0abb1423e3fabd5d7ee31de030cad5fe3e74c38fbd88a4fe8add3eab56156ab197be99fb8d675547a2bccd3d45e291455f29fdd0d61ced010001	\\x16f84d0ab750ffc24bc0b7d574af1073b7d0af46ca65e3ca895bb7e0492273dbab736807705ec3ee41ab0407894662e130ced3b9e42e5709897c159bff3f3b00	1662204797000000	1662809597000000	1725881597000000	1820489597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
9	\\x17142ea0de590e73c3b963922473583ce98517b55ccedbe4a388be97ba39ff6cd07ff60f5b5dc24df3a210efd8234303fa3af3e9819356ddfbef64550a84600e	1	0	\\x000000010000000000800003d84b9e22622262f5c25f4111c342731f1ed60c83a819b525925e95d29a80af9ec2e6c20a7356570817bfc31990d786d8542287280b8e2b9b56db3ab1f27b7dfdf06a99156c6c72b243e1907303b0fdca5c2ab2f0a47afc0020ee5ad8f2ae26a2253e013c721d81cc612d7848139edf03d93f0bf3238bfe32a6fe86aa910d0bc9010001	\\x6df3c5c9a6852136bac3357edbbcf0403e6979dcf9d5b5116aede79f2662bbe1113743d7fb6751440a99befabcfa7bafee085e1ddad65f9dbd4fe79aad6f5c03	1689407297000000	1690012097000000	1753084097000000	1847692097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
10	\\x1938737ad23b94dc867b1ba52955b91a72e4efbd684cd70297ff300a15c655e0067eaca8ef31d4160fc586231019bf63f3ed60354c5a6ab342748974f193646b	1	0	\\x000000010000000000800003af276ea5386582c8717395bd6b0af1404ef8c8c62775ee8a41ba5bd28e8c72d297e6da6c3c35f67e858918e5da2b2fb4c6438672183a4b5a20c7d259328230f9cd8a36e52f609f24f4a95992117c505935d72c2bf423c217870bff4486aa703b67d94351ab81628b4d60e5b0b20ff1ed5c1866b4c92dc8a2dbf46b4946ce7571010001	\\x6eb116a3c532cad58a5bcafc5b1033a3041cada0ecba1b299b06a80a0a4a1bf0d4d381fce2ad127e43ae96fb52db8e069d38cdccd657d5acc8a5101967c65103	1678526297000000	1679131097000000	1742203097000000	1836811097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x191818f06afd4bc2be2e00069015a545f7f0545c2eb169d7fa61e8381010aa26460560d1b4c0215061f15926af7ec89154b03b4e49d893006dde31cee4a85f67	1	0	\\x000000010000000000800003ae9547ff6070ebce94b90933ed5db76cb504df141d77f606bd0c6312a56e7f7ac70d5a089c043826f05747757b8038c2b1b8c9a11c9f204882aa40448d8d88a88d13e9b8dc22327a9dd6e3438e0f37b84c490d1efe38083238bedb81070004eda9c6ab88af7cbc378800d2c0d6e9de5062c8ab2adb8e33412f9518741581f82f010001	\\x5490805e57e2ed30fb4020cdedb92f9e5bdd45f9efb3fc1e4cb1238efb4b3a4afd2d2f61ef1e29589e43106b81f7e5eba28150a65ca46ef54eb9bee6647f9502	1681548797000000	1682153597000000	1745225597000000	1839833597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x1ab498145a571c583e8ab5d5e0bf2c0924becf0a402595efeec9c0bc89805d844634dab838be69828b06bfe256e8d804015953a2363505ae3972b0e97e519279	1	0	\\x000000010000000000800003c31cffd92766445c30aa917a628208b6e016051596e8c5ce2516bd64f57d94639d1a6bb3f7e05b2d551d501c4b06b48a42cf4f0ae1725a5dba1c5082005d4ea8d9e5ab4735594a36e0385b8dd46588d1dc1286534b2908692df8e435eed47f0359c29b4667c22c9c07ea306cd63caafbc6118af856e6b1ed7bee1a76cbe09be7010001	\\x4fe0bf3fa75422cb72f3ab091d348e6fae05325457601d171df77ba09a961f13fc2e8dd919b23376d06742da95f8d9bf5ac4db11bc9383448cc5e52c40bd2b0a	1680339797000000	1680944597000000	1744016597000000	1838624597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x1a049508891745efbf2968931dcf7b7c50d11afd5f8e2a6c32385e9b7bdb4ca2023f130d09f35fc5e504a79b3aedb6f59856932b035714157a634abb3ce7ae3a	1	0	\\x000000010000000000800003e2f083b86fa1f1af73270e9aad9032fb0cab553b2db19b0a61661daeacb944dc8210235199f16b676a16de0b94b2b06866d51c5547072c8de977905e851d9a79fa0439d7045e023c00eae25164378d92b2f0321aa6b6b77f99fddfcdadf3857ef3fd9357414cf617e5c33bd5d566384df2d1a42617b859403d242ca5a7ac24ef010001	\\x4e1790eb3266304a2bb51e107a3577592d61303f174fc2ac64a9d836f626992b8feabb71d1ee439fd534ac127440ca518c9a4108990b0f275d5fc96d57240700	1676108297000000	1676713097000000	1739785097000000	1834393097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x1c60c98a50808a84a5a50b713d8cb4b5f9e77464203dbb78cda894ba4a11bd38ad65b02ca92b01da1d292138f23d2f8e277607765be7b295a8baf4ae5b39af16	1	0	\\x000000010000000000800003c2610990cfc00d8f53985aa0502b68ee4e5fbf1c17d0ef66f766d979d3aa6244881574a921e418be5e07286b198d42fbf15a7302926fd1634b0fae43dc7fe7dacd853fe99ddca9e2bfea6d6d431e2d8153bbe605860d70cab9fa0dc7fffb7bfd393de8133dd85e0a878c7f08a21cf4ee1883842a0cc7a76a467c3aecde4663f3010001	\\x69a4a167677ec5ed128e5f5e035c2b1b48a28a6885eaee413e2fdc86f1a3ed1551711e638d8b5656a0bde9bfb04d8f6d34c48b206b9755fc73d18efda4108704	1663413797000000	1664018597000000	1727090597000000	1821698597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
15	\\x1e58eb0a996f40b07a42eb8b1fa10469cfc642fcd68208a2a037a6b1988793f2d8d7d399dd1dc9a981252c94c3b8502c4f54e58a9ceae7d13a9f2fd2d74df9f0	1	0	\\x000000010000000000800003d336ae9448659f3b4aa62ed13430f0b260ef975390478c5f888ac0056d98d33e63f4ff5972bd479b7a31e9d8cfb4331f34b1d1d03826e2bbf9593794a40482021f099387310515e84b5d99d9a80d869adee987eb99c7ac4a7ce72803f167d322944fab9e6b63bd07a1c9eab0c73ae8ab68d5871f7f42919aa3b4b210596cd051010001	\\x7dd1a5fd736475fb32f32d39c9cd0d19414da048bb7a0e0dc3b8d19ba096e3dcc29e5be3716e0409f875bcbccc548f7a96582cdea0f9dfeb9418b8a7541bbb0e	1673690297000000	1674295097000000	1737367097000000	1831975097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x20cc90b035221dcc132496d610aa7114d24e42cbf6dc0863e597b6cd1b0a3379c3a5c23e91ce3f74a6096cd291119d822bf4bf5fc38a9a559c288873432530b4	1	0	\\x000000010000000000800003c2ca71a453c75347d9989e47391f90149acd0d0d30fd1b5a9408904cc119c81abba1bc9db2fc706e39eeef9bdd2a399fb23303c21681ce4e3a437428203d3eb19c411ccf33323f9880a0bcf961308b03e605602ed6a9c26f802e6931a44f8f0bc7af25f5dccc3c902e80a152983c2589a3732c203890aa19888cbdb5a3b655f7010001	\\x170221686c991f1067299243a1d5f24afbfaf9db1587af4558df0d367e5065eedc8df7e9eee20309765e115c12104f8389812c21e0837175454e6b2af20b1203	1677921797000000	1678526597000000	1741598597000000	1836206597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x2050a2c282857837e3edb936b8947ded137336a3a7edfd61aebe1dff2f944e9fd1a7093faf02b852bf6ee145e82f9d97d904d3a3a3d1920903f88d9d117008c9	1	0	\\x000000010000000000800003dd1ce61454657e9c7f8816a9f5e8b5ea4b4faddc86d93e36b82c81081f2d350c5cb6364829ae1a1600a3850cf3902974c91533301ffc903f565f5eaba774ae83c0aa931f1d86295659f4ee4db3fd69c972fe0cb4e4e802d40606af4a21efb90459813f5bf92236bbdd08c7322a8727b4e5dbfaceadb7d94a9cf1ab9d52e8008b010001	\\x5da21c74edb88619ed227bdbe6500851210cb9c44db665f9d9a15d55adc2362520bd7e6f626b4e8765b0b7f5127a15fc660466a4b1c3685318dc1e7b9619bf07	1674294797000000	1674899597000000	1737971597000000	1832579597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x2b0405c6b2a3afd4de375c3dd5f5cbd347ff6a6f1fbcea5560fc9e9f3fc651200a7aa50416dceb5adf201fdcbc704261c8ba7b0a4c84722c2100d93c2a80520d	1	0	\\x000000010000000000800003c449f9c7961dc3e559b5534e558a23da06bd7f1206abeaafd63748a4ff0d0fc5838ba7c655c91dfd90e151f53086e8cca27081883e2e0294eb428386c69cfc442eea8d3bb1d6ccb8c1dc25028d68249235d12573c2a270e6f257c93013f3eff151a4308315a1b9700026c52354d781212cde96a8c353c9712d447cd3f3578575010001	\\x1b27eeedfa089e0ae256c23884f9aa13a5dea544099389219add91d8c532ebf8362f293e1115e02db83b5c5703aa776d307c22f5d9f3c5e4afbd09a6f272b306	1672481297000000	1673086097000000	1736158097000000	1830766097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x2e7866882b0072c64a361a766e5140b07defd04c3ee6f57acc22e7e1269edf685881393659f4834c9d7ef084cdac872638b3c01d2b8bed37b08f75f0f21bab0b	1	0	\\x00000001000000000080000393d02d4711d360692261ea7ee963c12f27bb95c07d4648ead14262b0a985b293a2fdaf4ae16f89f3318da9fe3ac060ea94deec85e2ea60f9453d357e803a921018b0dafc93595e519f1f06b18ab97dab42349dd1d0dc61887ce62dd5b322443ee2147c946ed04daef39eed7b0580f1fe6f9244078795d504bde7972ade344423010001	\\x9f63118d1596fad996e93935d4e9c0ebbba6dfea9b8c4dae5024d819fb6d17f401324b293cebc499cf77f204d7b997a9cc1668c1bf6c07e8fe9459bf038b320e	1688802797000000	1689407597000000	1752479597000000	1847087597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x3208de23685c5acf95bc1ba4ed7bd09b04c14b1c9590778698b5a12dc972889e58bf92a0f34f384014e6e37f5b1ec1b64efa0bc98aaa648ea0647e593691f5b3	1	0	\\x000000010000000000800003a752db83e65498a5b5198ecce29aa0735e78b885caab4261391fe875b258d8409923adb7000f3771be20a4f51c6a1acd397ddcd188de0c576fcb305b197cec8090dd89ffcb21d6362f294925a2a290df62783b6c5a5c725eb8cbad0a5a67c90d3614473af26e72bc25a47906b44d10ab24acd6f55d76e68702512c1f018b0b5f010001	\\xe01bca547c9c451e3afdc60b557e0bbfe699d346908f92914bd05658193dcd79dea71cb1e74eb6c5a407cbbc2523f35c8389228599d8e2ea5fa402cd4bd8f408	1683362297000000	1683967097000000	1747039097000000	1841647097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x324881fbc9fc6fb88740db9d992c58e97002d2e7a2c366339904ede0efa207f8d179e86e2aa93fe893c19104c1c6cd7368a3be20120fec0a095220ee3bd90be5	1	0	\\x000000010000000000800003cd9d0e9d293a56b7c9f23fc3620b1596e0523327cb1046b58fc87e57de188f8c49c16c1cb82a22e6efa4119b86b90d0abd84d7068f9adcb82f164992102666d70ba6b7877342e8e2c294277cc7139f842d3a4607cb1e8fe30ed9404f6d81dbf1a25189b9703764b77ab826f5cfe381c34e222172325db5617c475d78d836bc59010001	\\xb721f36925ae7de825e9a85caab9b878d8a1519666f9b68a31a61f631a2837888b8a5c597f45f43a30026aaa04381b646589646e3b0c591ec18623d582800e04	1665227297000000	1665832097000000	1728904097000000	1823512097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x3410a01dfebf2be30e4b89c2392bae9acbb1480be58bfb243e1d7ab00cd72003a526500f2ec03e7ff184fd3cacdce3e28d8f61a59cb96faef2c393f5251d444e	1	0	\\x000000010000000000800003bb0ae4fc0039ddc7ada34808677ffd4cd5cc5ad63ad557376c9a83fbc06c8f5e71be31aa86f9994fddea06b3ad13c6f9c6c97ae80247d46c60604c8666ed4c1f99cb3ecfd41236e92b513aa19494d313738a620ea068a1ef79ae7fef2e8892dacb1b2b434c6caab5112d43bb5f4f5f013576a6ba03fdd27b4df25f598ebf93f9010001	\\xc0f004fa01891801b21128bb6381ee2938d6ab5873aeced1462b1893a0f9bd59d452a8e6316bc1ca0c333ec9ac27f96bd2b2fc3ce918f67d4739315522dfe001	1668854297000000	1669459097000000	1732531097000000	1827139097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x398454a9565170bbc19d23c8897704800e2ef82996ebcdf75b3c9fde1c857c483e8dd54a0eba4a5e84ed4c0b2ff251f7dfdf98b87ef9155dea7913f06b6a2f0b	1	0	\\x000000010000000000800003bfd5d366ce20a5ae6e996db2055fa7e8a585edc81c35aa0c088dfba92d37c2e6ff0b3a9ebf52a6012f68055501ed1b930a5a81334ffcc849ad6ab7586b387f16a4b81d1e5ef86d5626ae37007af42ecd6d3d13ad8785379f8534f4934062570d27e41485e200e0a6e5f96476170cbdf1968ff30336bf4521d959cc0f12c9bde7010001	\\x1f91537c2474cbcaeeecae8310011970c591bd76d617da4da36c119152aa418bc779d2ec82599195e65c28c9935ea87a76bd5ce5315f061b4e559e931da04d08	1689407297000000	1690012097000000	1753084097000000	1847692097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x396cbb34f8396171a8e181875d0f5e25b063d390613a60ca8f43df4e428f7b768bbf7ae02c57f73a67f76aac8b965607ea4a4292812873b30bdf6a815436f0b8	1	0	\\x000000010000000000800003c0cf2e41ba1b1a126a59a4442dc8bbcaf03e0afc92ac4550939919a78ce19149a04a9cbf3874061d25957280a45a70946ddb5c4e374abc66f4143f775558ef11444ada8493d80ad4f9540331e6c55124eecf8a19ea83063695208facf3833f0d8539f86d7daecf2b461164b3ccaa97467c615efb32026125127145d6b8cbf92f010001	\\x738a5aa7ade1a5935470486feba455f9c9bfaac3cfff900db79e91f3954b391ca5e162f61f111ace5432b31dbb0206825b1e98ccc9c873bca70db3c459b2e70e	1665227297000000	1665832097000000	1728904097000000	1823512097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x3a485445ba3362080bd055ee11709a1d9d1df35d15643eb7964b478ef3fbad8189031ded5d64cc66e73dbcd9b0ceff0ebc170a522421989223e5103cca7b0b32	1	0	\\x000000010000000000800003cda37e4ffb098085c76c99a0f3e676274fc6d81b2feae5cb30961a8fa6747fbf043fea18914cd5a788d9b762101637e2ee2124b162362bf14fad80dce8eb02f1df1b49f509be1796c7e3187b6bb5cf5e37d7345c00a3eefcd8f4b16e4798fe195f29fdffca267dadca738e763250cb7fbfa94c7b92f2aad226168779f8e305c3010001	\\x42a7a1c74b55b931349617b7b50a03363cf8fee90b802d78a3e09031cf455bad0ca227f796270a314536e535b22f03b7bd9c85236d77ff701289a211b200c80d	1679735297000000	1680340097000000	1743412097000000	1838020097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
26	\\x3ce8578a4d5c710a3dd319afe324f105a38254d3d2cc02ce1e87c6fba604218856bc872d50478337741469fda0417405938dbbc611885f5202e4dbad6b081cd5	1	0	\\x000000010000000000800003bd62d5b27104c5d090bd2db5af481e6dc21f0f114c4f88ad022ece22f099f5843550db178937b01401e9a474ca271f69aa2dc527b1de28807da196fb6f0bac4a1069aec2c23dcde05d6b26474fafe7a8908ccf23b0af8797cf5c195759f372912f6f97295b9b31a09f80fc1ba2fd8def0454279e8b0a0fc1ae5d9f1cdb2f4cef010001	\\x140ef0d0bec16b42690ba8e637974786671c0e9ccad18999f01d7e5b9a4a960a604c5be44c6de1fac2492cade331a63b3814dac1cce3b7c878611bd9610b1d02	1665831797000000	1666436597000000	1729508597000000	1824116597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x3d9cb96024ec4c69e183f76b1b7ef48b0e60bcead282100d4f651fb070d8e800ab0b0bb2642cf3253dde630a6c94adfd59cfdcd8ff72ef1b3d4122bb8436cc53	1	0	\\x000000010000000000800003b9d0e731b1a9e9a5ad1dbdeb673ee3f1ddb000cd052e2f3d04d302822f5483a49e73600a8d83e47e950fec9c4974e6a19f1412b53e64175d9fa7c7292ace4d7e22f6474373dcdb846b17448b3beb6421129b1a949a5e7a9045382027f19594449db0c134e57768255fe876c70c7d1817a5b9e1f82c5b65bee9ce853121a4e6c5010001	\\x87d5c3d7adcbb4804a46ee9bfb90a6f936465ce567def328df0d348c5e941f3f7966aa2d25b5bd8f01cbaccb5f8ce0771f1b7753fa8c358fc8ceaaa944c23e09	1670063297000000	1670668097000000	1733740097000000	1828348097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x3f746748f30e2a920afe4c1e1f69cd21fc741b46c3acaa6115dbf2af89373c5a0254577c6e010cb997d54b5b46f23088c1478eadcf08d317c6e4a5f8c33b3fdb	1	0	\\x000000010000000000800003b5873f34f9ff5b4e83d152f28cd7721cc51a45fab2db1366d48cae2da9080ff46976949d4eea6672da86d56c328a1305bd3efc22c0835ef624afb4d6b859563fccc21e42d4bdf6a910356955cdf32e14ff5fc0b1c94ab9d6eae92b64b434567369d8f5ffa0efd7b7f3695da597631ccfe965f525dfc4b6613bda60936116ec69010001	\\xceb17e31775d90f5b32d00186787134e7f0d22d413bee0ebb535bea5544eba0c697ed9ba2a7d4dd6c50062522fd3478243908a2f23a81d746c9bb5910e19c600	1660995797000000	1661600597000000	1724672597000000	1819280597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x419868d4b8ce64d7fc5e4629422c3a6a86674bd0cafe0fb59ee5737be08e7fe8ef5dad90d25ad9f2a84b1940f45da85b96f3c30d1acad3f8ddf88b0bf4bad302	1	0	\\x000000010000000000800003c04280941960d33cac0e4b99628dddb32a2a7c3c2d9a161b0179e5fb69e3e5772b909293ae498952a38c1746fd67fa3219f3b8efa10c5a0042eed605e0df3a64ffa04d5eb4a8630e78e131d21659c2010031c38119eabf41eba3e5e03f23658e8e41eda5b610dfe1eede2dc89fa56165f1249d05eaee014fefe582e2785d1cb5010001	\\xa3dcb3e554faf793d7ac8f5a3d57395db2df7eeda775554720f52c307e878629ac934d5fd65d103a2d70d78440f12a0af42fef64c9b9a91a7af84bc92483260a	1667645297000000	1668250097000000	1731322097000000	1825930097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x4334e8f0ffe62b699cc64d438296f377037ed5904931369e2f68302bc8cf643761d3641df944e34ad1b69d87f9b66a02bc66e5a5e11c02de27848eb2d1ab8287	1	0	\\x000000010000000000800003bf45d44688c6bf023a0f5c392cdc09866c4a3c6e106eb6e65095e7a85ff6eea12805ee582dd41e1b1a9c2b7f0a2b18faf98048cf535d7cac34f93abcbae240bb480971aa6c36f252d1e7f3477b2b7a1cf468c9158f42ce0d1c7b652172469815ae8c8f8fad095db03b485811e5e01d56cdc8140106dab265b8a7d1b6a0589915010001	\\x4dd7e1b2e4045b8513800364c17150154f86b930573dc126f2e2307451d91cc97af763d7e959e5ff15c1240628cb65f0d6e624df04029e2f74cfa49e9dd7c90a	1683362297000000	1683967097000000	1747039097000000	1841647097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
31	\\x469c97ed92a685bc07c9db105114bcc6909d7a6984151f13b2695fe78c2da603646479bc628319c6a851f05481a09975367181e0c0af61a3bdd8bc419c350e37	1	0	\\x000000010000000000800003b8376bda9536bb12eb2af038ee14d929d9e774396f4875445ead4f4d14796a012350dd8a82d03f2da84dc9d19344973d3871e1014f79a51189779e3b00ba56519235082217b394963ccff443dd6caca3bc1442737add14fc67f60cc3b897b19119870ff58c205c62bf7dffdee7d72b29efb1e551c9a7269f52c1a34ed70f02ab010001	\\xdcbc8850b10c9d72e957500203718f966a8d5a52c56d76a638a25e84550bdd858a5706715ee979abc8e2bb10b4d26a3f95404d28cc6362c78b6f2593bf94bc07	1681548797000000	1682153597000000	1745225597000000	1839833597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x46cca18fa5e27bf58527fc1d39fef9f2b92298ed7c62be8be7b61495bd8044a15f10a249788af3dc3300987fab0fdcb1d6df495d703e9e57ddcb34868c1ec18d	1	0	\\x000000010000000000800003d7a2385c0b44658128a48179900c546514f70adc0b7ad74d2179644420f1d4e15840e2b0d6054fc94f69590c8c443271043e9f64e4699dd3e257ba21be102eb2a491ccad6c959f8677fbae96b5459cc1288093e7a8836a1f3b36bd2302512865914745d77c5fbfecbd558260c5e196890bdd33f447e4680b44a095284ecefc85010001	\\x708b85609d3089207fb68a06f8fdcd28820a0ff5fe7a529b455fa0e2692a8e0481624a038f083912039df06f75828526179dbedd90874c3abc832b9f5c39ff05	1659786797000000	1660391597000000	1723463597000000	1818071597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
33	\\x46f4d62a7f7b7650f53fe7349927208e943aaeb408ca172734c649eeea3a4352f781eda50b92df6ce0f03378a4d91fbf8c211e04abf3c9eb98fffdf09f72e3b3	1	0	\\x000000010000000000800003ebd188a61099938984e81b06d30a8af51824e45790324ad198bc9d8fb1040705b7da0f7dd3ca03938ed3b246c6174dbf613beb8acf8e2291eefbf93e2fa534f9e57f7dd0ebce19de7af3e0be91b80bdeae567c2e38a630438345fbc3bb19393c1ab2bd21937aa5ad401a1ae5508695c9fb93326b10a53dc942dc83bac5bb3139010001	\\xd9b9c8aed2262778802c22934070e83cc6452d3d64c9f8c01f61de530041393781303a0e7f86666d4d4a743f80e7b39dfb975dced6a33f0add03e76ae47bdd0e	1672481297000000	1673086097000000	1736158097000000	1830766097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x4a68ed9ba04909b822de6610d760cadf2088d3525eca62e8b6f49568b06efceb5d9f84abb4c6c640d84268b340647b1c5d8c5c4e195ac3907b360a33fe858229	1	0	\\x000000010000000000800003e58bc4177c99b147d21df410ff4c397813fee45011c25c88e80a79afd15ba26598f979a435c26fc58dbb04799e5c2a6dc0459ed72c63bf3eccd50e784c4f0dacb22c9970793462e598f3a80b529c14225e9d4d434584ad63c86ec9e99496942c2b094970046e00b18348473c5cce4d8995ee991fc5375440b42d827ceb9853b1010001	\\xfa71e07ae7feec629a6e329629aabea15cdf1d135d69b2d366f71473284e5197609bb8dd3b48481249628b1dcfb3da1978b829b350b16413beedc7109ed4ad08	1688198297000000	1688803097000000	1751875097000000	1846483097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
35	\\x4c4c1e2a93e616b32f80b47de3852dfaa29d56774ca8f4a887f54e6f0f7fb8fa1e6e8a3ca3bc1e5df4b61d09a6202063827e8807afef27d81e55a3abf51d580e	1	0	\\x000000010000000000800003cdd50bd2c50e0eb9446fc7067eef43045f80e1d5a610377b0238995b4706f363a9203c53aa2ed66259c0bab6e9867218b75901d83fc773dc48c32977345c788fc2defddc015e54fd279ebe6bbc3abb4197f4210c8c5637c5e3d89e21e46a6b0cac4256b5d023422db5dff6aaebd03e66ec31fe28b600b3ffb89f7302ac13b939010001	\\xba4406d733affaf46682dbd4748e97a35d2ed6effdffd1a2cfa003ce037b8c87158dcf4d36f3cba6c564c2510feeedf5f5ddf77c38030d020d0395527959b10b	1676108297000000	1676713097000000	1739785097000000	1834393097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x4c1059085447b9ffd672e6144904580d85fec95d2c9d91f313b01444e2dde6bd2a22e5385249b9256fd0aa52cd7267273ef4f397a27879e8ecd59303033835ea	1	0	\\x000000010000000000800003aa2e92c3cfb58efe77b6e73aa8d79572b3053dbf954b9a5fbbc36905d8406e56cf17be2198c8b26ab65f78207f93c4e6f8ba6305442e6d78750806b4be1e3ab8cee12c3b3cf545a5ff2d9cb2151a562e70bb9b7c65aaf46560b61e40f9546d11ff566d89bbbb5cd2937de2c9c95b33bb17a062065ac61bef15fcdffb9538e7e1010001	\\x0945999b2e3737a7f511d3bfc1153d1af113229bf37cbbf39fdbb971eea4e42d30d1776eaad56acfc34a2af980d2889b4ad9613db3cb6952055cfbb2d888970d	1668854297000000	1669459097000000	1732531097000000	1827139097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
37	\\x4db87b6939091048e91f2c1fc4657e468883c6a1f2d31c23bddc5666abca8092322b700ba9214eae41bfdd1320096d799d533b5abd90c6fac6d27fbd0c4b8534	1	0	\\x0000000100000000008000039a393305235076d219f02e4fbbff763c76df37f6246c9092eecb5c5783019ee187bfbe3b1c3d23fdc7add04b162fe28661a61d64d405d37500f49944245fea2e1a84642260af803a264851e5c7aad3d26435d3c7216bdfb68a0db597672fdc1c93f15b992a0f3a49923cc2dbdbff6f4c82d054eceff846f9cf68c249477219f7010001	\\x69b3a9fbbd66444303658bdaf23bc450bbc6ab6926078432e1536cacdae127a0aba8c972e67e6fd1726edfde2306b4c4f213b66a8287f33659f5f1a341e5a707	1664622797000000	1665227597000000	1728299597000000	1822907597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x4f1c770740fde63f8cd89c9f010b3403322ce6ee8b1c2ff7555c4d8ef719a2cdb92f7a40643ce30b08b627238eb2c70694861f0283e6264464d3da660ba2f595	1	0	\\x000000010000000000800003ed13a747b11938775d83a5b3ed1e2cd8c8ec75313b135713bf53e81590fd363c0fadf554a8d48d122beca207b63a5aecdf0dc3e4854ce463293d6860e9b64a238206c1d770e06672efba1931d4e72d75267e49bc001fdb8fdb82750bc8bd53200fd20f437bdbd4fc24f1bd0c8e7cb310f632166eae229a49585efe3325b13b47010001	\\x3079cd3737b461fb51728724fce7156135561a11adec4b9dc4c59a56a0f3535bab8f2b364c43bb8a405418973fc467146df228f4712fed631ce5325088713803	1689407297000000	1690012097000000	1753084097000000	1847692097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x5224d47aafff8ea2706e3be1e30089f6e89e8b4798256ece5dee8f9ff16d557f5ac2d43302c16f09dff5fe65366ce4b89f8c840b06a626f1c584e72f4a6118c6	1	0	\\x000000010000000000800003c60d55edb403c0ec5ca08a803da67e148288d2f8e2178dee556823c67ca6b1363a2fd8efef884a24608cfd2a4e4604673dc6399a3a50fc511ddc2634131013f1bd021a37db839b57b77f4fe0fceb3331fac845aaec90afc5cd71db1c435dedcc849b90d50b7c3a8bb4026238eab5c5bfe35433c6161cf904a7f9f10525999189010001	\\xb9260d8c3c4870bbc5e350b893ddd23a26f9606da5c8c0afa3f4522b1742fa0453ba7dd86a2256cbad28de078ad50ca89f4b29795511c59f973e1e6601d8790f	1686384797000000	1686989597000000	1750061597000000	1844669597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x573870d6dd214f6ab4d8be8a39e3be27298037578d17b84c3555c4c734c8a154178b21915b1f2a5cedc6e03d75213e138283e283ba77b8ad491d675dd48bac27	1	0	\\x000000010000000000800003bd81d31cc10bdf27668929c2010db2f322a815521de988fbcb708d3a055bbe8c0d1553d0057e4302eaf2ac068cb3dffe8793a17e22c0c7cc3b980e3caa9bbc7aeb793f29a926fceff9ede0ddada8bd0da7c0b4de5dabc7d9db9e2a66c100236661fd5e447efe32ac940585aa788fcd3b10a3f360626a5ca0b27cfeeea2ec3359010001	\\x8d93b435b7fafc2aac0e2a530536381eeaf3f5e4c3b0ae5ad71f590e220e561867ee06cbd007a94bed9ee93de7d9e1ca297f16d42de0086df06554664525480c	1690616297000000	1691221097000000	1754293097000000	1848901097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
41	\\x573487d270fb588475dce1f0ca4b48004182faec501aaa542f37b7df7c9306e095c464dbdfecdf28935831133b0b8e76451e9f8e20838af1182edadacb5e41b6	1	0	\\x000000010000000000800003c5ab1864b638100f70c0a1cf428caab0de5c74db076155fa25aedc1132b99abfe085cf9c8423ddb33fa85720ddc81647eecf844aff7edd0eb409ba27c4336d45127be045a09c1376ceb7601438e90effb16fbc42bb523cc4191d6b450817ee24a66f4d602d5d2c2c61c7e243b7605d151dca8645390d5c0cfb8c1d0c29a1bb95010001	\\xb21575be125491095539ca37001ac8a9fb12eeb287d0a2b214c01d490cbeebba9deb4f32a939af2b4a9a745e8c60760f899a8c9a91c7c3d2ee405b48930b3a0e	1678526297000000	1679131097000000	1742203097000000	1836811097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x5900c7e9f36d662bcf8173354d7f5b23f61628c6de52f2ec2b3a41db85a5cf31575ebdbd3a28262608b8e16249b118a72ce8c69ba0603bc68e692a5d09dd9157	1	0	\\x000000010000000000800003ebf43eb9c81524676b66fddd32ad5754f7fa98ac19ba346c214f054598622580e9f3ea584b8e57812efa08d3ab43960aa243db5d3fa9ca9941c4bcfd5de61ad57a276f58093b78e58c12885f6411d3c736949efac3a1d349c1fd333d5f9540cc76f24fe004abd97aa36f7576b0d18496d20bbdefb277723933ada014df3b3fbd010001	\\x41e0a682b757eb33c6249fe8b42b073fde23f409bf51ceb16eba731c39d7e6d1fcf186098cd636faf74387ca2c0d2c94c7bb8c817f42e7dcc80827a72cd37101	1682757797000000	1683362597000000	1746434597000000	1841042597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x59242386f3a5e07e33043d37369473ce53f01cca64b11ede9944dfa01f6d337752148be98aab3cfdb5e477bf5c8161ee093a0a61f00e835a5bc08d41552795a2	1	0	\\x000000010000000000800003d772d62bb2465fec6c752ec507fe99318a3a7d26e0254d8c68eea002dd29fa6f506b53e1ac47ced33da8ddded0670c32ff96cca1deb50ed8f8226d02fbc430e5aea02d805af368f6b888c749033d290e7374ea7ae966557e195812e066fee85b42b685c933c590d971d5c6d8f4b42ff1558ad97fab8f008b0128f9c9a9a81851010001	\\xd92d2650aea80982b1902110a3c2137b538d6a164844a27339ebeb10329dea8adc5809886ccac9101288b12e7d90840efc20700a9831a2f0ab3fd9e4f6f23c03	1685175797000000	1685780597000000	1748852597000000	1843460597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x5c387589e7214f56b64d8445a439bad09f0334067fe5ef774919d811708a653c1001e3b43f71293c31d3666acdce071a60f4ee0ecd4478e6d305c44ddef630d1	1	0	\\x000000010000000000800003c3ade88068a3a6353df6af82c43b208b84c3e50eb001c4570a805933ac8f3bab754eecf373450a750e71679c0485bb00248bb779a4f7d8d4d54d32ceb95f2db1c253e3227142ebac0e6d014c0118513aa05df2103d4d9dc8177fc7557a908245b88769112666b81de4469e1422a01782280b6359b8654a5decc9eb752ad156dd010001	\\x83ec25c962f0e5894acc7195e1f1a71dafc958849addf995311267fbdf5ae4143b7b14d933dda7f22bd47ecd3d8bc5c6cde4eff733676367be011d0236fc8405	1667040797000000	1667645597000000	1730717597000000	1825325597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x5d44751b4ae64c7700cb43e8379b18f55018ad391b8b62f61d90a560fe501fa85b5725fcfee8f71b4c0c042edd59883a4664c4040ba9b1c597989e2ae70a85ed	1	0	\\x000000010000000000800003e5948d133bc1f67cdd5bf4f15aa10bc28f250ab46460dadf7a648ef1c04ddf2a80fc9f210e16acbdd86953b32825591898db6b4b1a9195d48eaed5432d8846e924948bff63f1cf97d65bf3abdccab99b0e296b968a7da7ac6cd91017b8d55a99e7a9135d925034a4e563640b3326accc110e967958d92f110b0166509c7549bb010001	\\x252626d9751bf561b5e23637e7f70c0bc00b0202cb742529a9a992ed9a17bccd0abb2fb9f6e7a351fe942f7a554488ac463a4e2fceb7268caf164ed0ac05c404	1678526297000000	1679131097000000	1742203097000000	1836811097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x5e20cfb72690480be85c53ffb3b0e76532c9a354f066b13d24cb6dce398e153a94d68f59233fceb667603a335cd458070d284093133437f592a49d4d525bdf0a	1	0	\\x000000010000000000800003b6024820f37d92435bb314e45f6039e19d4d66ec049a351eb8789b65827705ef37d4b526e7e0ec4b0c340af9217f55aa088199065504d1f005fa575d00349c3707ed552b9cd0e666a0c81fc5ce861620532bc88e13bd155dc153a02d802db24edbfdcbd77d220505c12966e1c832c0478abbec4d5493a8f580b5df9de3f02fff010001	\\xcbf48590ef13539c2bbd14472540c714acde26fa70c341f636a955b7d94910a43e21d76ed5c3d473a76a45ebd4fa4df8e75e28666d6c274726477a27483adb05	1665831797000000	1666436597000000	1729508597000000	1824116597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x6030eb38732c4c6d2a8c9864ea335c7cb1b7c66cbf2b8c4d1ea45cff34530a8298ebb469188abc8686f69b2def4334be6f75ed65d2c7c52f6a3f696531a61ee4	1	0	\\x000000010000000000800003b371bd72b0d00b3f90a69de9719f9d334149c90614c33d559736cfd64b845f0d2179eb4cf5d049ac5da84d319810e865947dafd7ea517371c2931e012b8d6a1b857c91f27c75a72916dd1768949c7e3236b69dc9fd379fcfea485f41013f6a8e3a23531df54305564fb54d6e8d8174adf205a3b75c27f194bc354063a9489f51010001	\\x77657579b861dcbcb7bd43cf8f6745f5bbfe0a9f145a21328ab09f78cfb0f1f20b663c43b3e423bf8eb113ee71c65ca7fa543dcf61cfe345b91a9e7ff9808b08	1659786797000000	1660391597000000	1723463597000000	1818071597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
48	\\x63e8feeb93b6dd9580ff56d1fd7827062d1a32b08006005013ce8d2baea3a91a2662c4df4a5d1c1702be88e7ab91452f8a13da517085dc07b99c753d57a31a66	1	0	\\x000000010000000000800003e2255ec232adb3da51a3a046febb0a85c091ec802176e3a888d3a0ba4837d63f02eb22bbc7b9b7405f445f401ff82d3f25a9ea73bbdf42d3ad4917f769d5417f12283a2d62ba9d366b92ecea4559fa946765473f7b80a158b56a5c250d5c67f1f352d498d045519c24ea2f9b6c219361d8be5441c2429179d771a2c57ef1f1d3010001	\\xf5370b1225ceed20c68d702faf6b9d45597861499ce196ee0b820f3a59fb0607f95b58c0f15aa8cb89ba00874c6178067fd539d97a05706e5ba6e8a85d492004	1682757797000000	1683362597000000	1746434597000000	1841042597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
49	\\x6748375c4707d254ed1b9458205eb4f4befaee6142063f172e4c33a0cd2608c448a48242a1173e491c6f042753d1f43ae1a5369c6ba288445575e5461ba2b57c	1	0	\\x000000010000000000800003a03f239093e39126d545021e3067e4ba417e86a0c26e39b5e94e7abb059d1d6c1c9c2fb897b3522598321b70b39e6365b428a73cda025e8677c87252a542824340b949b7926159e1680e6f2675f07b05d13945fb71d7a7815ca028681d17251357e0d12b1ecadce422298cadfa219b49b37d635814f680ffcbedf07d3a7767df010001	\\xcef6e0acffc6e325b4ce990144bb2c619ca0e631bb82871e40edf08d0e14de7bc0663349016f133edcae9f87ccc3eb6bf26307cab49c0efdea377879138a1906	1671272297000000	1671877097000000	1734949097000000	1829557097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
50	\\x6840f2ca36c0047cb7a2c145c84a890c60861ef2ec32542c7f5a0d735fdbbf6f213ff4df2a3f07c32b55daafdfd700a0bc2ef15eab051ef31f0a4360ac05b880	1	0	\\x000000010000000000800003dd38f7c42d5e14b14508bfeb3bc896d074aa147f4c9ec74e9b354b81aa88eb1b003106b0899d67c26fe51bf0cc064c5c7a9ba06345c41b0e4efd01b68844a2cefad9c731700f8d199204c88704471008d978c6363bc70f9068e118a14d9f69d647eb36b4926fb7e31bc98046222911c14d43a7862406fa533d077046cf25eaf9010001	\\xda5aec0015f9760b0361ce4184a493b031f612248bb206504695ddb55eb47f5ca422f83a8df79f7db7054cb4e37d4b054f1cc95eda3ccd54001b0b85cede5e03	1686384797000000	1686989597000000	1750061597000000	1844669597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
51	\\x699c59653718ae15183c33272958f095926e8108902449400080056f8ee59cefbb8b40c4191139e7386a3ed0e6c8aaa1bf0b1cedc7b0184944610bda4ac4bab9	1	0	\\x000000010000000000800003dd2e1e00d4ecd8068ab6694ded66c95523d7f819c57316093b2537359a40b331f7de469842f36b3e6b9ddef20823efbd00e66f682128bf58d74c00d71a6aa3b35151a6fcc6b85a8e5473fbf34841147b3fd2f2816fe79214af646dad4a637b03165240f4d8330708b8b2f83e2b34f39802acbdcebad2cd887f26a699aa0c7cbf010001	\\x4f6540164e2904d7b3f61b88c07f2767a34a441549e91d53af8fb251f12fba26f4db131716c9a31578f1b7c9a6a0629618923e1bb687304d52b61cd1b0dfe702	1691220797000000	1691825597000000	1754897597000000	1849505597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
52	\\x6990e43bf2996df934370ef20824bcfc548dca07e45d07ed5d50bccd34b8e2609c68ce19da892aff26bd3edc296f663cc3135718af605802b46567e170918fc3	1	0	\\x000000010000000000800003b13b002b141aca1e4d884485987cb7ff7f3de4ebd47a9769b16398d68690e19aa75ae264d6572e7a3813f9d92ea779cff5be97e242d07e20174a216a41ab53b0c250952efe3f11766d66aba29d99ef1d38301b9477bfbef6d39c22faad35e5ed4521f5c4e50dcd733329949683eec35c77c33a6dbf69601c8835454d74f6f19f010001	\\x1da0916a294f60b02e77776c0f89e435bf18ee186d28154107bd9a269ca153aca6cc5ceb0fa48f0f28ad99c446bb9c7f542f235860e44d7e61a09a204cfc0f02	1671272297000000	1671877097000000	1734949097000000	1829557097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
53	\\x6be423a9a388fee462008dc5df1dafa0a2393a198c2dadec116a6074ad14574d95d4974b540adcfbe9f7ef8c900a94668fb2538ba6d140131013c464adf65da9	1	0	\\x000000010000000000800003bd2d7111ee82a8bdf8861fe4ada74543ba3e3c6a8752ae7312267d75d6a86703f4051dabde33ce7bd5ec47999ceeb7f795fab76775e0e469b46dfce726f0bca91831b3c39264c7a8c3ce127109b2d617b32eda11b1a8b510092cb03e94087c1ff5e289d7174414bad1bd020efcb15765f0149e904d8a2797c8001178299c5107010001	\\x54c2a748678caca5dbfcc661cc7fdfcfbe1ae4e00da22c34561d605faac504ddaae49e5f987a98c32f36d79c6d6d35627493b1d96ef553528d722b2858dc360d	1688198297000000	1688803097000000	1751875097000000	1846483097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
54	\\x6e784459a4bbecfddc78040cd455fd4307c133e924dd3a9a81d138978002a1ba3013a5fd67210e44a78b56ee5593cb09ed1ad817114e816bc9f3e403ee3b53b0	1	0	\\x000000010000000000800003ad4b21422598b2967a9af45976c88151361239c762f2888073547bfdfcc0ce9ee81af528e818a5300506b486e1e1706d4d29c47e420069f6d438e54bf299e2a3b07b56c74303b9f14bac309acc1bc8d8c63cc4d9f721416c174959ce933fdb1faf0871c588c3f5b21c63411a654eee908b20d553cbfc6975b54a467957c6f5eb010001	\\x07432c4e44c5802ff7f4c86c1de1e8c80ced8b2b53198f28ee69e864948318995d47f068c2ef4a75f1a01475d4e8c0c30624bb5c078b7da6ffeb8c55d594fd08	1673690297000000	1674295097000000	1737367097000000	1831975097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
55	\\x6fc8ef0c6646cfe115fec74e0ad09973890dd07d5168efde279deeec2e365bfc4763b58fdec79384467575d83aff12e4800db6b82c5e18db609c7313794ab9ec	1	0	\\x000000010000000000800003c87105b784a67985552e2ca91de9cab44ed15b025a6a2163b3a45c7c2d211bd6da53b96cab2ede5902157cddcc0044706286dc1b8db360933da3390b387870bc786755bdb0f6be056fa429b47df0676e89300419d63bb6538d680e4c6220b11dd17aa5d35caac78ba35587235de47a48b9de78f36f7fedc948074704cc9e74c7010001	\\xf3f5f635fafd48ff116c0238d0b1c721d6c0e085247d8007f826477acdf9b552fca65f3cf680cb4e6cb76319ec6c9e08c5ff65cf46147851444c86ac1edd0300	1663413797000000	1664018597000000	1727090597000000	1821698597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
56	\\x6f5c12dd302eb661d6d3834f8e6e40d641b19346779459c2121a46d5dfa00995fa176e2021c343c7c9236bf406ca6b1a4f6c325204e3f6c81a300357d55ac6a9	1	0	\\x000000010000000000800003b0676c748144e5d4b06d3a02ceadfe8d8071b834c4e1d3beac73f3d4630beb7a3000155748687ff93f981c59f8eac1df329b010756a519a67fe1023df671b533b609853ea1aa65b08df1b855008c56be349540a8d81ed8ec6b57d6163f5bcbe89270aa25f743266571a3a4d558d330318dcbfd4414c8a4ffca9582958f584f9f010001	\\x573cdf6c3bd8b926d3d2e6083466736be508e91fa4fdf44f5b7cad3558c4e2c7546b4748c20548b0507374f3791a16c631969c64fc6c672f0f81e05b735fe506	1690616297000000	1691221097000000	1754293097000000	1848901097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
57	\\x71bc8de979b8ccc83e12ce33553873bf6d477079f6819c722f29a54a739756c571f4d43a987c78d43a5b7c6c3b2d78e46826f531d2bd50abb5d729892e8368a7	1	0	\\x000000010000000000800003e06e08dd59c0ada934536fff75e3ae2710f75c7f70d855d4b6bc5c430e31ab054c8ea313b963eb4cf02e7bf22902ef84f0a95ecff400cd19f27dbfef8042d6db10c04c0674e7fefb4932f8b8ab839056a9831b6a16b2a6468d23e04e3eff49b2cb291a9f53b58cafa94688b45b193778c0d6392e71ca92a2dcfe2e319502a1cd010001	\\x5145a8327b8507dce87f4df83e8ddfdd8fb63f5a455181648131eef0f016f5bdc1dcf785cbbeb69f5144fa8d04a3bb2e2a607bbca5afc7abb5e2453dc556e70f	1679735297000000	1680340097000000	1743412097000000	1838020097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x726c04db6c63853ff479c1c64d7ef340bf31a3b33b3c42959bbd00d3c770177b01a3b573abf92fd5507947a0361bf66b21be5ca350d6b30804aab445922e137d	1	0	\\x000000010000000000800003d995140d734bf04a188ee7b5394d09663ca9c15a9a10d78004f591d9a3972ba484f7f07485b03db53eca0fd9ba3193107c260b5f42f5db5082b246bc8b8b3b36b84ba882c1b16ac9137e9d2ce2a214d89d2ddac9d4d73d0bf94ea26f9161a9e1fc0c0e08654a3fa449e44980ed6e9abc5824f40388bebf0d3eba615a37f5ee99010001	\\x7f43cfdaca5a98a1bd776b51e82ea9379258a7a7cdf989254625828221b8127421577e728026403204ef49d04457102babe11c9283687938c763e45e58deac04	1670667797000000	1671272597000000	1734344597000000	1828952597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
59	\\x7724e4332bad5dd166a66c6e47ede73d642cec446fc4627cb1fe115099850c0bd0001d638912a03fd7c0f90ee658b18e8243007f7831500f2c2188d6dcfedb6d	1	0	\\x000000010000000000800003bffe175233f5a3d8f9e8b7854c96820cf13e74868d15f5919b91dfc8614441af796e4302e8710e696b2b96a1c793914716c5778915a47c249cbc27d2016bbf8e151ab1a1252994af28a30f1ba6ccd618df75dfc235e5bb720bb7fc9959c014d56a325d0be649b23e21ce381d149c31c051b26c957240779640c4ae5cb12872d3010001	\\x7720fa5f22dbadb926c477ce6d562966c73c9fcc45937902bb9e0d105501050b4abc83850f432c4c64548b6ccf01613085adea92ad781046e877581090f6830a	1674899297000000	1675504097000000	1738576097000000	1833184097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x7b70c523fdb28ef29d9d0ca4d68052633a0a679de30390951c2a4ef12a30a24f317a6fc459519c9e98d9c1e6938005e35d23094b16ce52c1ac67d6bb171d86b2	1	0	\\x000000010000000000800003fbdc6bcfc03d5aedcbd0235e10ea7ccbc0afa4e8746a2f9b44b3fcbc3ad282ce3c15ae73204db73b03f9ef4d175c1ce62163edc728ca8b465a89d5bfe64a93542eb058d5d27e8bb8f2e6a7965880d9b65c2605c9d0a249b2b9b4a5fc349f537d54aace4ae287f4b94b344d85aa98f294ca3927d74b08df9d69b262ba4dca6ce1010001	\\xa9e696a68c9309a11fe66ae06361489bd5b8e5f359e5fc70a8faa0783e9456566107cdad5843dc18859c414c9cf2077677c39fb9fed2d8090d79ad551a225d0b	1687593797000000	1688198597000000	1751270597000000	1845878597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x7d2cff79314a377d16e038130e5da27f4845e74c3859f4b9f4fb8d984e78fa2caca0c093628e3081c6238b026a158333c8c2343fa41a43e3d1640198ea0409a7	1	0	\\x000000010000000000800003cada2da5467af4b1558f08c483703ccbfbcfb4a9f79977ab5d888614dbb01b9f1fa4ed7e14a721f0aa5e6aba0ff4fd0e5ddf7b760a771ce7852d48729c16116de4ed78b4cbc66d2bf5dbfb9255c0d235f41f556c8b7c284045596870758b4c78395e555e84ac31605cdfd359fd45fb276c4536f5b737b58a2a106161c152e769010001	\\xdd28fb09a7e0f6bd12b6ce1e6c7874e6e50b101ae1cb0e982de216098e741f56efe6cb3bfbe5e49a73df7509968563364c4f1f8927e106134c704bada2c8d70b	1680944297000000	1681549097000000	1744621097000000	1839229097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x7dcc277d9a44be29a1570391102055350fb89f51bff5d40f4e8690ff7514a07624ac2ca0478e0b35957b7c13dc835ed8d316a60c128fa0b86d5639b785010ab5	1	0	\\x000000010000000000800003b5d781158cbf2edb96eb8797d1f00f3668ff548b8a6a2717eae2fcd97188afda02c5c5d71e4a2308c2d697ee758882300cea697d2064936fa4d927e429cb7e5ce0ffc02e58fc345127697ad9408791a65dd030dfecf97f0ceb76ebb792ad4ff36f1020f6819e7434298ba0a7bb8d6638c60bac71080337012c5b5e111802990b010001	\\x12d21eebcb60e66c55538b6c37a87c8d82ddb910760b157440dc478ab187f07aee0d8673e54eff3f1d153b8a0c6ef15a2f1db5d720dd2d101e95f8d98dca6d0a	1686384797000000	1686989597000000	1750061597000000	1844669597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
63	\\x81f8047b2536a331c84f5361da4932856893ebb2b86fa6f3b190e9a73cea55067d58655704aedae769c6d0101b7ee39a8e53119037eb688a2d452e33d4494872	1	0	\\x000000010000000000800003be71f287f79937fb050dc401b04ab87dda611f90bdc91e8c6ef000325c44ae21d3f07cc55fc2eab335a374d7dd4d551cc98b97bdb703ca61b623123b0ad74d3cf9a39565dc66416ba0b9dc7e51896b70d3a2c340dbcb5287e04652ab454cec1e35726f880da41b6a756b4f90022ef5125176af6260d6d16df1736d30c8e9e261010001	\\xedb178c7f00cf2a400fdb43cfa7e823f929816a303290d047af746b6c83abd971a362e7b18db8f78628353b8f3711cabd820f1589c7fbf5f48dadf1db5626105	1661600297000000	1662205097000000	1725277097000000	1819885097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
64	\\x831cc9d83b32b1078f5bad73dd4ea507a75ad75f5b2fa1ed66ae5986bc1440f70f9c012c128c442bb3786b5b1f9acc5ba46b9be6af90ab9c2c9bc5dab1e7116d	1	0	\\x000000010000000000800003e8541ef5df568bef529cde4a746f1eeb1aa9c50e88cea15b137a913f1a074ed8e7e69a5fe7f1dda1bec9b2d463d6b20263d5140b9c5cc7a1231f1ae46fbef68a7ff22c3d0c0aeb2e6162c9282e0ac88697297e237853765adb3fcfd78e61ec56f8d725146a9dc823f29ee2cf1b0489ae9f0a15d3886bcdff5d1e0f9580c9abfb010001	\\xeeaffb03be70586f7c8437b2a7a389277ce2769aadc35bf642a1073feb5afef0f0e4d41c1ed345487e791173d7d80163c3ce7d20e028d6a6d6c01b523e042c0f	1683966797000000	1684571597000000	1747643597000000	1842251597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\x8588326614bebd10a21880b30a2fcc7349e9753070e6ab604e41c9ed67d59c3b40d8e32a62f16c216cfafba7060e4febc58422e6ea09021e60308f01e57227cf	1	0	\\x000000010000000000800003b9416655e18ca7ec5782615473e86e65b362392387763aa9c44c00cf620bfb4f2cc876bce43b5cd19bc55005c5052e2a74b254102012c7012cc6dcae415539cb349c4e86fff37c6febd48862c0c17402b4acae433a637a16bffdb59cbe74c05882f39b5c03508ff43596ae926c4f96c8d2f308280283c14f6e0870fd0afca3b7010001	\\x9de0b3f5d4a7c5d10198d20580594e2b4e6cb4fa70f877d6fc2a080bd38b8f7175563cdef57b42c69a4ec64a6187bd0c7455180cd39af18073a1728d5ee80501	1663413797000000	1664018597000000	1727090597000000	1821698597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x8a98059d1603aceb0d18302ba303141bc51b40f641c3f270de5df773470f6357320fcbc35ab2b454b07c1d43d2873ffcfde77b44a8f4d7701c4da95ff11d6aa1	1	0	\\x000000010000000000800003eb8532e5169b592ff59866f1f4a0eeb68bc366aa4bbb971153ea609769fdc57e5b28778778a2fa776c7c21ae083fe20a7f728d39af42ddc8df3267cfc7dcf13d8a8e6d461f258b6cbe3d8f2997e99b243c806752697048f167e02829b3aeb18e15883900955c415d1a0a64b8717fd960b7e8aac281127f0d8fb76ad66ddebe4b010001	\\x07fbdd2f1a68d2d65730b888dbbce25c29ae9e8f354b5fe7a22bdad748ee2cfa1c709744a5ce6dbf2dd6848f27abf7608d8eb12a27a279ae8637779539c76501	1661600297000000	1662205097000000	1725277097000000	1819885097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\x91a024b8b39accebdf604703c49f3fdbc5a5860ba6f1c95ec468e2990265c7fc71dc5ea4f3ce78b587075e12b84250e60f9f08abe6918468616447ffce7422ed	1	0	\\x000000010000000000800003bb5714bce01e47d0d0de95bbacf6ea7f234dbbc1f3dce3f913f02606d6b194ff05fbd02fa01a52f2558b077803f573b9cd9dc80ef1cedd42e26939b39ba1060597acf59f9de8bc626e6289a83c43505c63f0f7b0776070b74bdb58032bfde11eabb58805ab0eac706b32f6ae09549c2d48023d924d5c0c60d6c85c2436ebe10b010001	\\x39c2888b3aec784a811697fc9589f8a05cba0cd77f40564307aad7d93dca9480b921e551c000e790af7d84dfd775145a325f30cca689845578ba3bcaaa019e0e	1685175797000000	1685780597000000	1748852597000000	1843460597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x91ec5a700081f27403805098f548685f308d6d59b789a7e36f991c690261a95162e6f985beba35d681dbaa36928de2e80fbb72d0bee003ad9f50a7b3c725dc10	1	0	\\x000000010000000000800003d4dd857642ad2bc17d624521f33c95e50d03b40bed4fc124029df6ba775ba96556def5c369e9e3179eb77c99d23c41d616ed125e0d49a43d334f157a8e589362a77d25178b0878c393d70bd83a888e1d2cdd861bd7eba7d595ecc230f86f5a0664ee2ce6f941d1c9ae24a8ef806785f9427db17b7f2b83e42f4f763035cbd4c3010001	\\xa843aece4c2141d8d17756c4b1e5bf8c8efd2508a7a20ac37c515567d1fcab8b3d4fd8fba82e8499971c7cf0562c5e230cec3c8b9a96d02611ff0809583c9b06	1664018297000000	1664623097000000	1727695097000000	1822303097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
69	\\x922869724418103e0052f577ab2a92e5e19a2329a8766ce1c53f3551070ef65d7bb44d690a48534d26d43898b3b859e6cca245c1b5b88aedd10ce6cd001c234c	1	0	\\x000000010000000000800003bcb899ba33e2c12c936208bfbab1e22ee1824b001648b8856fcbd73d2e4544de07dc405f59e9d9232a17fb5a9862c565ef3df900aa413aac41aa95e676d7ccc1547b0c4ddc7ef3803b7fb785d73704fc92bd725c8b87de2fb1c083da655c5b85b4240156f9ef3fe4a07d34a77e2b67437407c91f3eae7aec4ff2d62922796df1010001	\\x71f4284093df38648642409fd4f4aec37db78ff483a6bd3846e2fc72e3c15d03125de79af8147443d6272521d876b9b2ba4f709c3ca3a2438f2bfacc6aab3a03	1690616297000000	1691221097000000	1754293097000000	1848901097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\x9450e34a7d571422a393bbac5ec08be2b380e7a2f7149cb8b9966c15c2e684e70c00150923c8211a26d25a3155c4f72be701568e016e329de510cb03bf8fcead	1	0	\\x000000010000000000800003a3ff009e0f8ec3ed64017b91f2ee9bb5b41ac256818e792a6b47dc906a41bfac18d183c521f2f4e31d6c5c0d659d69c422ade4ca734c3b50812a7fecbc08fcc6b577c0bc5f996378c7408e99527e9bf23a6d6abc4b264b80f5fc745c5e2e5eed7d0e4f1d1a08851e7650a0e1005aa3a4c7539487c99f7b02c505e1586a06112f010001	\\x38f4b856d008198b71c40d7a25c6bc1f20f20f72599e5a65b13468c2c096688bad837db2c4777c7fd6601f7baf9ae7043c5665a7ade6f031335b224772c22901	1673085797000000	1673690597000000	1736762597000000	1831370597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
71	\\x9644e4807e1649e786e632d36686733673bc8f2f3db34ab7108e3c163a2a53c9e64026d543130f6e3820864d04565c39e5d21c83acee654ead005d31219a9695	1	0	\\x000000010000000000800003d16854ac5b9b569a9120419f4bdf8c30f6902274ce9a81433d5dfc75182e31a2ca94ab07e9f2fe7593c930ef1571b6c758ad01642503c6a7830de9f62e580df5752785c4c557848df12b470a0d29e568937d3f927af71a10fa6228dc44b68a353763f410ffd9d3e560b7f44b36ea53234c0ccffe2cdd3418b84fec63eb3b0999010001	\\xbb38ac9a00103760a5c8df77265854d46f4897b5479646412b0024c6589600b925211083e7cb9fe28d91e602869abc50760f6eb3e04840212cbe5804bffef504	1676712797000000	1677317597000000	1740389597000000	1834997597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\x9790323e87b2b682071adbd6260c125171f9e094dfbd9a16f0944cdf8317d385d487d4a0d9e029486ebc654457f2dcacf11d094c11e131c0196564796dca8622	1	0	\\x000000010000000000800003afea9cff6388960d41a7fac49525813d2fb22d7355c9ebababff33f53dfc14f57bc59e36b801df58734d733fa2aadbc76637801855d3a41c511d3d47d35096f7160abb3ff68f86171dd4a18c2260e12ed8eefeb0308a6328a11401f032f7d9b8482a03edb732645c0af18f176e2f3ff1c488c51fd69a6e910067d05e7b945f45010001	\\x0c44907610d7196811a0b6be99c40b4b9df991450ab262c07390a72ba24e79dd250074c834303670ad9e2a9d550920359a9c07886fc51f44973eb70fc6ac770d	1686989297000000	1687594097000000	1750666097000000	1845274097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\x9a2c87ebc54b0e3905df0241f90bc15569ac31694b8059d89cfa0a598ec66ee5910e9eced58fee9193430eb32ad52717ef28d99299f5191464ffa6272eb8fb12	1	0	\\x000000010000000000800003b78f3753990048070bef4c665760f835161cd31e49e0a464c679630776098ae4563c84bc3102862f001756fef68926c60214bd652aaac327dad459e6e4f5b64492d4b57e0afe3c1e20ec8420a0b28a5319dc1f835a16a3a68b88d9fe00c3a7f854545ea0744da0393d51f56162c8ba47f916990e694d8dc9bab7173d0dff869f010001	\\x3673a439d71903b84d6ba0f73d50e5be2ef327ac02ba61aa0393778e8ea49d452a530d11373ea19d7d60faab2b839bcd583eb99da06506c2cad47b7dc2bd0d00	1691220797000000	1691825597000000	1754897597000000	1849505597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xa0d8cd266b375a42ef97a010de093cc88eddc42e90de5ba5456b0bc4fc1f49da9d7f460bf5ede535854c19016d45c71422fd49b9b5ef5782093974196fa73233	1	0	\\x000000010000000000800003bdba984935c868e9b3ab626ee85d7aab9b19f516655a37b21f40a8938005b7fd8dd3abd7e7bdc47063c82c52fde5a3d33a6f0cffcef3b863eb6304a7299611f9acc2ba04ae4e37d368fd4c063daa0ca333ec52234c40c348ec4ed8d071e6e4a74c0059da9b74b2fdeeda16e5de8a3a01c71a555bfc9c07f9cd433c61a316ddbb010001	\\x919255642969dafab1a44c9546558a06af0ff47c7746ccb0a34f3c304ff896897ce3555c62111bd8d0515ce1c71dfcf9709857ed899ae9607577a03b60444508	1685780297000000	1686385097000000	1749457097000000	1844065097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xaaac4efb9e3cf21c8588e3ee4248f53ed4af024c6c9ea9f3afb0425032f0c9704dd3442a57ef14e3c6b3ad6e89e140ff852ba3cf480a0140c4b90ac7d96e3e2f	1	0	\\x000000010000000000800003cdd394d8c0831aac08f13d7ba62b19921e21cb83c0f6336f9e2ff85e06422262a97932e77534da4cab4933747d3e2d8efa1fa1d42920d46cc0e72f5ff1e6748f7f538a5f34bfaf1c6aed274c7cbce79835ebfb18c03af5094c9e59300acf69c23931200f02b5b1fcb296f259f9da0668bb7fed6fa657e88c7487f9b4ae2488f1010001	\\x85fe82fc8124552ce984076bd467d3c9802163695077ce778141761be1fa02e626a9ef434cc99d5319778607082d5ac94edbb3477e5429e02a8b5db3ef7a7a01	1688198297000000	1688803097000000	1751875097000000	1846483097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xabd0a01b87a0c7e5265d3a0cd865c0a6d72ea1c20a5a29f84afc01797501262ba0eccb3d8dad00027e03bb2117df275405ff6d0bb1ac211fbaaad8bd12d6b435	1	0	\\x000000010000000000800003b27832d74b70fe6c184e1ebb01ce2d046a0bdbce698f7822a4a8c439e052884b2222fc845d1814065925785849eb8065c041b8d394b3942dbfdf3fa116e754f68caf7f3c3388e8924b3486a85942bd03f5bfceee75571464e5c52c948c210467374a2c30530ed8f17d6c07eae9045f3323ad29cebd8769d664e99b0319a97729010001	\\x44ed40661b8ee0549fd2c3e5e50864b249f5d93b7f2b5e29b3a6e637b86a3cfdca88e63a2f0d129f7ee5df76e9cf1e6b6598bd5dff7bbf764fafee3151f78d0d	1671272297000000	1671877097000000	1734949097000000	1829557097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xad8c5890b8a49dfceb51553759de493e85175197bd4fe3a11ecb818a06f60c1869c03bcdd75d21516d71f69500b575aa419a57d3a85879ba537be9a2ac2f1b07	1	0	\\x000000010000000000800003ce4717f034ca6ddcb3be6c69c38df8578f35f872980962fabf8748ce02f9c60344d91d91670f8fec944d4acb46e04837b745dae5d5935a4b87163722924f92ce3cbc77ba7faa40de3c11cafc55b7366e6873fd0086d0fc6b9cde0c10dd344f73acce8a6efce505945018609e65f4d186096961d0f78fffcbdc24df4d579efa85010001	\\xd66d5e68127c697d8a0a39f40ccd2c73dbbf2d8b5a0fcfbf27c85e9fb494f0b5b4e9e6af8014ae0e3739b923964a7308f0c2d6c1c578dd88aea5ed1b93af2908	1672481297000000	1673086097000000	1736158097000000	1830766097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xae94e2699889aa75b45bd5aa883bc406acbf24e44f82bf395b9420d1d0513b9abc805e2d634056ef9573f2c4c2e4be58c35eaca3e7049c91b9948f982800d791	1	0	\\x000000010000000000800003ef3844d2c573edded28a881ae8fe7b2fc8d61f43151a6d9b1fca9fdd4a85fb0d021530f695f382a146c65977c26ac78ef18a60f3de00b3a12dfa0180d92214b7216f40ff586208498a46ce4e85b997d19ba22e3ce25af1d845a1b2a10303b1ab47755c8f538c38918689dcf5dc8507324547be6a79ecc9cba71ec7da915a453f010001	\\x5b11bbd4b201a31a7e79901097227b24472cb1d26a5425725296049408f512457197da0abcee59a0062e216b5975b08d2fc416af2a72654901609d197b21f906	1668854297000000	1669459097000000	1732531097000000	1827139097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
79	\\xae043eed75eee65536f2a88b9c040e6c5ea4ab23270e706f6b91a2f28137d734edcea043bf6315909bba565959f870a19513047eeaf7ad4b7cc63f81fdde3986	1	0	\\x000000010000000000800003ba3ae3ee19e892ee587832377245b436ff357cb0c7bdfd0cd25e794c9670e7508452b8a48dafdb2f894df993d0b6bbf01c3e919dea7273659d5c60078cc3ec49bfce86b9506e79a842fb2cdd8c5b139fb1faba96ee9b92e36cab2a89bdad684d168e0e6cac635b1335b487d1fc6e47b56f80a0558997574fa9513abd8c1927ad010001	\\xa79b07702d82a09b0908b212a4ecc1cc92355b723438c5ed64b7b5c3a424e15689e71b04e66b34c98c9ceb1e46e0bc8ccf5307ece51898190d79e00eb187ad07	1663413797000000	1664018597000000	1727090597000000	1821698597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xb3c07f33a02953fcfb5f25c94bbb84015fe58caf1c3f8c55fcd0a28ab32b689217a6272d3563607ee40ce16398d2703fa891f41edb6be34099fa8950c1fd5961	1	0	\\x000000010000000000800003b2a80c42b331724bd56157f86ad37b3267c10933f06aa1056a1ab371b57d3b17b46679c7d12b686611b575d910cc906d7bb91b98579e66eea712cc37fa86c5ba468a70352b1763ce68eebe3aa0546f6d9145883ff6ad283664111fc088778f50219287e8638d98dc1a69aa937bd0054aa4ba97817e0adfd1d5c70455f8278733010001	\\xf681b4f2be188d134d11008c82b629e3f3152a3db84f6feb473d9de9126cfaaced173c3246c0fc2ae38109c62ff12df5b004013cb1879a9eb3561058f9c8670c	1674899297000000	1675504097000000	1738576097000000	1833184097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xb5c88e6409b66c54f9db7a0f1d7a9c4a1fa96d893b6cf0a2a8eab9766ec5cc02dc864aaf12c2537f06b4a8770e0c3b047afe824d8cc7d6956faf0afbf8bf1e87	1	0	\\x000000010000000000800003a9b2075af569f0cb89d21e7149087773c566c7ecbc878dee63aea3b4ac30c738870c37623acb833caef55ebbef2bb7e4b385222489e0e1460dce0cdecbaa8c2287894a67ea9d729a04f4d27223171c316952301c25b9c7d81c3e64ffc851ee7c558085ca0adff1e15be0493d63c385ca7dddae2749cbae28cd18e228cb6cae43010001	\\xd92ef0c6ef0c5d1ae501f8a4aca5d4b98dfe516adf90ceb5045eee350a6fc9cc7b8411ca358697b270ea700c288be34dc75e00a64f610dcc5636eb0e28702309	1682153297000000	1682758097000000	1745830097000000	1840438097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
82	\\xb7102632131b5289effd5900fb4b6b108ebee839c99980ef436f935f122a33136b0c22bd9177f61318b9e3d3c9619720f168c43f0ee9d848250755d6fd666916	1	0	\\x000000010000000000800003ea7a469cfed3182d6aa168a25f281d3f352eb4ee5f45e8a5bb4d9d20adc8153cd0f9f7dcda52869a03c33ad17faf2fbf916f3bb1cc824f70ab64856cba0d29c8519b8f2c3494f9778e63e47759261c0e3474833138bea5f5021b427a18bed39da564b043a94a0b6159e146cb0f95dec5035406bcb919085d949b8e1e641cce27010001	\\x4f29a38d11314cc82d397f477159366835b28086b9b431e12ce84d1ddb0cb9d9d374c663af0f223b4d6be9b4c65e132443dc184dec6936f9ba64f5def6971b02	1672481297000000	1673086097000000	1736158097000000	1830766097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xba6cd75a801219e3810d9fa7cee9046129eb562b6ecdea594ddefa6403fd92bb18f379afbeffd0a5d0927c3ea55a035187298b6e85be4cd0724ac48e0824e005	1	0	\\x000000010000000000800003b722229c1ea1b17db6ae8a03c9376b742c0bcfcc2179012e5d49ea588a3f6077d8986859167068c6603a07381b6076edc6cc3fc10db1f4e7793506758cdd67ed4033e7541f27da9044a4ea5d2e8024d674b1b43fcadc0ac9b7ecdef88cec1189b42d9dd453e75d308201e986674d3067a1912b2b024e874dffeec0fba6d1efe9010001	\\x912449fed92e40fbf165ae04e038876a20642e32bba7b95c17a5efe4d7f1d5f5b8aa0ee0cb1b59473a2ae918a4e763ec593dac772b57090c511a9fea20a6270f	1664622797000000	1665227597000000	1728299597000000	1822907597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xbb6c7e0b4d621594811e69fe7d222dee9988826f22497891a8119c174d70723b1d7322ed1bf86d52fd6ba441a64ceaee80ccf792b05442b1e19fec47599eacd7	1	0	\\x000000010000000000800003cec6af5cd750f95284efa5229fb314cfb3c23071078db2faa3652d99156b0e7b75cbd52cbc5b7274297bb8613a5f4846ff2e3c23bd50f22181f5c10446e550df68d378f0e286f0ebb0c8239b1c98a82e546955284d5969fd05e6d153efb091357837f34f051941a5aea82133a3da68ada86e1f968e7e93e2b71276df88ad8085010001	\\x3aeb3fad3bd824f3fca71073a1d7af3a1d46364c1352abbdd097ec902be69aa760de55e69dc74c04fc5524647c37a87f35dcc9674e224023303663d3df3b1e0a	1665831797000000	1666436597000000	1729508597000000	1824116597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xc174ba10e923d66dd815fb880b7858589062442d8ca634222b1012746233abb698a1ae03c8d26fd1b092caa1d3c3916e0109e51f9c979c69b8627997d10a9b3d	1	0	\\x000000010000000000800003ce713180700f96ea5085cfbc0c7eb630a6f7b557b344002d0b348820793d1ac6e8cefbe8c6c0256623da993f05108edcc5499ee61c0778541a04d2e42ea4ab60d72f35425b1ab6741346c046d788a836b3f164bb814de94bc0f3cde840cb200459ac214fd37d8d28943dfd6ae538ee9bc440456578c828cecf0c2b99d244b1fd010001	\\x49c7cf6b6f0269d49b99de9f68c9483beeeb4aa8405b8467d5b6fe9f2768ef8cf83c29d5632f7ad73564e663791bcef844a1ff17a9a8d4210d2dc6de2c20990e	1672481297000000	1673086097000000	1736158097000000	1830766097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xc234913da930e5c5935b3bceeb1c0a472f2ebe8cda6fb00294234aea0a1b870ca32acbed5aba29eed6d3a38739d9cc86c60d7c40d6c909834347395e7a794f41	1	0	\\x000000010000000000800003e20a1c960f9ea5ec1f4d5c700411ee4c52c727b5319f5bdf27a8d59e555ac4c8c83f98eb4b6635811514b669876c1ef0a0967102dfa13d5db43a92390874e15380e9b30f40d207033f5d98e6f0d1741b34123aba90e71817f1232dde303eb1052e9d6f2311425412282295b59e44f886b748929db6319ae602a5effc74f0b01d010001	\\x1c871ecf827a54a8e5fd6289c0851f3e7cc5e32944f98094f60f924b9ff28e8d7903fafccf7c9e5ed20b6a934b26dbf80b597f4f8cf8b789f4849c95dd93d50b	1686384797000000	1686989597000000	1750061597000000	1844669597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xc6c0d5b4a71529f3fb474bebb589720731f4a85dce2ab0b3fb5a453a1f37519d710a856a0df05c10b9f1dba3a09e20bce04786f80288ffcd78c55c6839464716	1	0	\\x0000000100000000008000039cf74656080c93fd4595c2de5f2b74606339720e60fa5badc430bef96886a1aa481d71d797be7a44fb5c90fbf2443f225b4c7ce2f4a2f54afa8fd0195f0f5c8d898838d002fca634d836477ef19243aa7c7a1b8372b04ebe2f7a99766e49bf5e2494b4557af2414ffae42a1ef427e4e564a4aeee09f4ee4d8498d9900eac0f33010001	\\x59da33d26e017cfe86291d6d977566fc2b17b2f1313e1eb5cc0e21c5b71364f9e51e60753e495f4ab2f30b0b632ac4ab77b7e458c1c9af4a38b05c103027d80a	1683966797000000	1684571597000000	1747643597000000	1842251597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xc64c5830baf9bc688e6c44bf65a7c6df150d08b33f19cb0caed19a48cc3b8bbe2ab9e7ab1b54e94bd3b179a7d86195f2c8a531346644b409a0d84913720b1416	1	0	\\x000000010000000000800003ce5389371ae6a4ff03fa63e01c33b55830d5b2dc650286d20fa3e63a6312ef68dcf4042923dbc1bf95e5b4abc379b6b565fc3fa347df7d1662be1df75b559d518ec41a6ae99d9169668153fdc1785498ccb2b334f27dc9d36306c0935f76a3382fbd9e0b278943b966dc1b59aa0d2956c8bdb4d0d5d2e3bf72c4aa91c7d192a5010001	\\xc26ec91d169499764576f217266027d1515fc8fbc5af0febcc3149635227b5ebb1a21d827e5a396a522e502bd19aaa310c6f1fcf7201fb067ac5f2cd80187e0e	1686989297000000	1687594097000000	1750666097000000	1845274097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
89	\\xc9cc979670dc61278d89d9b58c0eb85351f3d474e1cf6ddc9308eeba7e45eae0e8e2ebf1a22ca5f40ac73fe9467da43d521d0740b9004d264409ec5b0904be44	1	0	\\x000000010000000000800003b198de80e43b68062001adea9e71ff0749c31adda8ddc8802ea917e35dd3c13d074b338579fb5dacaabbabb2a3a29d9c440fc16deb6cb75d722b8bc5c54c7486e7d4d76d525b4e5fc6b9a87dd57fc92a051781cf8f17f87e7ae6c1694492dcb3d8dddcd02feda1f57f0db088f094bd56bcfc8c681f60d24e63cb7be8fef37ab3010001	\\x908e853bd93aad4c9ed68c15b45145843ac22673d11e9c1f55f5564a252317a482f63ff5f152a0de833704805af4e7a10f41df1a57c1e9bd72a8f532decf3c07	1669458797000000	1670063597000000	1733135597000000	1827743597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xcce4c13e3f74663124b589093549f4726be8c470f65a6a8e3c687880326fd8e73d2f9ac076af1a869b08ef9fe698cdb2a303c4b1f73e175ed9d8fc5f9022810a	1	0	\\x000000010000000000800003a4a08bcb9e5360e4cb2f27e50d45bcc4543a4f30c737a29058fcf721edcf2d900dedc4bae125c2cf2b10c9690f69e10fdb432495e3ee939df1cd6a7a0f2f412dbac26cfa68c248a76d95f67a88d39182385aa236580669f7c5b718910d279e6974f28e253be19bd1f8e67ff187425875c64e9783233dc5e7220e7fffcb6eb713010001	\\x41c7a66f6fa4f33656867229cbcd06682f5c18936cf746fa4ac6cbcf06b9419e63f359ee036dec75a634631fd94ae5873da93c24514cb9893ba165a98ebe8501	1688802797000000	1689407597000000	1752479597000000	1847087597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xd40c27b6f794e32310e31bdcd84f9aac6a7f5afaf5db45925a5f6da57e89f20507c75754b0b16a3784c053eb4fe371ec8308783a18263ba2b12512084bdcf4dd	1	0	\\x000000010000000000800003cbc7e81eb32b07c8ba8144be8a5543308a8a197a5bc2cab980491c439c465fece68af10f1e544ffb3880ea08dd71b96c2a98d138104b2bdda5819e952a6257a54c62e6c99e5dcf6de2162e569551683150e2253abcd50f836151699de8492c59cdcfd12efca9f27e57844f9e2142b602af15025f6250fd5b16bdddf14c0cce85010001	\\xa63a0c7e1a5b4f5e324ff93dcf0f92267544370356b05ed095ea1416913af6882a1ac6daaa8a0713e56a99c12c7e51286d53ca0b2b575ccfe3b57ae8931d310f	1678526297000000	1679131097000000	1742203097000000	1836811097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xd790b270b103a1b3eefe9dccbe863579595d7bcff16102adb2fb889fbb7a9cb6de1a7272c0105b281079a0911ff9ecc6dd17c68317cb730b77a01f4a9fa8a14e	1	0	\\x000000010000000000800003befa9b681cee20e7c123615d6a822dc2a51724efc62d726d3f077a184f59046f8acd99af35d0a67e10acc498cc10420da4f052808a8308e4fd39b9788459239018aab6d06bc1e4eb856b443ccf344028d3af76ffb8a468cf71f0d0364237af6964a361650b44d20fa0639c20f704d04b955ccdce5a883109dafadf69977329ff010001	\\x9030bb5fcfd272b94e1a44bfb760973a8cc7abdd28b4e1fd931cebcf420a20e66879a0d38fc07253760101329ac801442ac684e4d6bf9e61d6d13e9413346f00	1683966797000000	1684571597000000	1747643597000000	1842251597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
93	\\xd97c64c8188ec45a8f8cfc9c7a7490de5ea59a8988776bf2073190715a61bfcc9a8a07991416160d52770d374bc7ed986b2e6e420ef094d8d08080c257673acc	1	0	\\x000000010000000000800003ac69aab9c07900b49c017ba0ed396454297be867e7e11f78638a7d7f25660fc831e9d91dc9b16b23b9889196424bc11ba8d0c75eaebc37311e8d6cd4148e99744ed08a819cb6a32c6649155fe6922dde33c9a263ef1b9dd7715644e7f365f40828cfa728be664c43febb791e586065b09106d8744d1d0845b559ab267b20cb5d010001	\\x98d1959cd452d79a3084577d8879c56232f9baff32ab3c2a00921dc902d627683022ca30114cfb3b99a22c3432b2303b2bee86a719376af8082508abbc33050a	1661600297000000	1662205097000000	1725277097000000	1819885097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xd9d8134781c3ff160f619f75737273349c28c296d9c8a67330e5f5a1ffc2c8be9775b705dafa501a3df6f7515efdc7cf27bec73749ec5081a96b31844ee78461	1	0	\\x000000010000000000800003e663e9cf5bbe8c24c8f29bca186d5f51d2882d70dcc0386d3184f7b8a1b8b2d7b00577c312dfb5047dbd62468ee606cd5e90a0301bc8283c0eb8aa6605b75ce56f438f3d7cc5269f726bc2f23bb4251c051fff64564f8d55d3cf958e76b258ba110813a56b6f89ca7f07094eee0ebd53f6a1218f4b006319040045b6d54aaab9010001	\\xa672ed61c93bf0b5efa6da5f1c34ba332a1202d3afff1a3b8c256361bcf2e23203bf2aa1324761c4e4d9c9175cd7ac4a0192c0ae4ede0dfa4865d494870cf70c	1679735297000000	1680340097000000	1743412097000000	1838020097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xdbb8f103689effa537bb9747c6a2595e8b32530c42c1a61563a8ffd8502bd207c6a9646f87240fc5543233153f26d9f9153a1a55b671b28f32f3a8bafc7d9563	1	0	\\x000000010000000000800003a8b1b87695b6477f2b1cc805ff47d10bbf16b9d532ad7af58c9f0810f08b6dc6deb4993dccca4b277e3da479b2ad2d2f0d0cb35df8786f94a600912a1858902821cbe7c240be6e7369749cc3791a3cf0bb2c7088393f9b0ed2997333988d929fb728840c934aeaa8f56f44d6894a74d57051221d90de4d83f890ce71d16b4727010001	\\x216ae2abcb620cea1c820872c97d9087a52bba937744a50d0c460b62ee24bf21deaabc4fc802b4f829549a2244a2c68e7d21562483d535f39ea7c1db9a6c6504	1673690297000000	1674295097000000	1737367097000000	1831975097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
96	\\xdc5002f49d5a65c87535fa8750f644d3fb3f6c267445f3f68f751f6b8ffd9a58e1aba747328c2ec9f9ba08740ae2ac08341f7cc1913b23ffb1d478a1fbae354f	1	0	\\x000000010000000000800003ecee2f9df3140769902642f2282d0202858ed6fd7c4ec9c75a346ce5fee5c57834d4482ba3ad6db242cca34c6a9684b7f64a56938d0f0349d6c5dca865299333c5c526bc52f59db6f0ddf6f3137f208564cdabbaaaa167ac64b0507743a1e55bc6319ef6b9f4327444c85d3a6f49d6f73aaced51a3b49e6b38005a069bb7ef8f010001	\\x106e41d20523033cb792cdc39beb43fc3dad6cf3aa98014e0d3745948b1bc61c6b7a4d3bd0760cea53df00368b330502c9e51720967e2c59e759fff61f46220f	1660391297000000	1660996097000000	1724068097000000	1818676097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
97	\\xdf7865b9b1096b638ee8d453b81d77e03ade67b62971bd7d51b6ab7d08c17891a77eebf23610a67d266d8d4c454686396641c6b6572339c6bc0ce5eafc32cb6f	1	0	\\x000000010000000000800003b705a5e220f1c149be99d6975fd96274dbdc1020a7d1b0f9a27b6f05f341d2c9dac081583ce3a01e913a025b8b86b2219eeba4159d1e2762f14c17420dcbb9da5bdabced0ca323dd95acd70bcf13a814e9958cea122ed8fd5020f163858203b22550c9ee74d68cecc9daa1a2ea8858d3ea9906e6947fb0ae81c5c27a42f3c3c7010001	\\xdd160cbc5535b046e39a8bb2fc394be6753bf3238db13656563da635ad18ee18610d1a2cfa801eb2efde01dbe21905ce55541398c3a5972f8fdab9305a6be406	1660995797000000	1661600597000000	1724672597000000	1819280597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
98	\\xe6a81f23924813532d5cc7718639a20aa2864c742582fd79f839b3b9072337283ba6e5583c2d900a8a2b1427b0e495c0b4f649573e1a31f79210b4c8c1d44bce	1	0	\\x000000010000000000800003e8a522c53d62f46fe57d57722f0dd1440e1e4919ceb4f9c33828e06141eb853f9c361ce0c4b580dd14bf3eeb110ce697829f9eb6dfadeac4bc0ab78a0edc1a163ded6efd754956709a59e0a8f818f9e497ede9e883e1960ec921d88e653425052f2f40c1b4751dacf64c44001dd126c9ba8af5077fc705904d40a9275e98e993010001	\\x688cba2713fa3933306a383a0e2dbcd469cd27f3daa5542bc80512ea67c2f76c9113a1e94dd0501ec28911719bb510d3f19fdcacd1b2d9e2e3f6aee64e618407	1675503797000000	1676108597000000	1739180597000000	1833788597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
99	\\xe7d02608753d3edc0ce8d30685d6b6f56067532a6689740d875e8542197ed669211dc4cc6d4d2dca551adf27ed5e11a89622b10eb99ebee107c2b5833ab9bc3a	1	0	\\x000000010000000000800003c0dee29c649e8d08f2130c532e4ffbdf1a4389fe562d645d4436dbc7dd000c9351bda2d82f553b725c72d2f255ac28934a231349cf09a7db7c0b191e4b39efea478a93756e54e4eb6a58007bf4249dfcd3a3b79c2a9bf1ec17d1b5b04e33a0dac0e9f34a1f8140bf382dfa09b730722e99a38ff57ef79ed904514563a648f477010001	\\xf73b9e6854aee66b04fc357ff16d2763465e2f1e58f2df398536e514eb2f6116344c1ef4529d5e904932e6e6a67648400b211eff056b6a339d85ba17fb6a100d	1677921797000000	1678526597000000	1741598597000000	1836206597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
100	\\xe980ed3b1b097d9268e44e4c5e08d9a0d1819e164c554eb688aed9878d27004b0ea9875102a3d30946a374801dd3dec6479fb32f074c81d7b2ca0fb43cc98528	1	0	\\x000000010000000000800003c8797e35781e4fff013110617292312d8671c1986a83ea79f5da96b031b4bf64d98fbd42e398d192e584fe1d238b20ac5f8f61e1ad1ab019841ff26c3a835271f254058610add2b091970d5a012de9abe5e85a3456e293ffcec2b298b070a1109618947af7255debeab527cb0f01434105ee07d964e76e222407e7a9d88379a1010001	\\x1a06abb282128f20802ac2cbf2e8079aff5d42c8141b7b9c58d1b824f60be0df805f6a1225fd5c1dcb9a3f6ea43aa4b440e24c6ecd81bff43b361eacd18d8803	1682153297000000	1682758097000000	1745830097000000	1840438097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xeb9894a9a493a571ecae60b52db0396e5da8ccfa91240d1f7424eba6de38b4da4cd370336237424ea49c47a9772efcf1bff221acbdf8acc3026e56b6f005a6e3	1	0	\\x000000010000000000800003c7da873fa6c76a1657b5d62f490c5a44b9a85e3f8c6f97c9bb2d6e636cc26dc5ec8e49a1de077918fe95f2719b334f8313a159ce4456f61c9ba57c53b0181839c6dffc1cd72f85884f03032684554990c5f80033ed155a6c71cdff2611d09024ac90485f290b90ac01fbe589cbeffd9401a01e9bad91330f796dd0b11c67f16d010001	\\xa5bf6dfdc9acdd062d3f731205a128dcc8063459bf580e559d593238101b46ae2b124cadd536905fb1842d69f61d7eec259e8e1bcb7b578daf488e2649c55303	1672481297000000	1673086097000000	1736158097000000	1830766097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
102	\\xf0507668eb82922a1a2eb25c6a9ee03b1b1d695f369fb028866581736dd31f80fa27bd3cc6f51ec750abe53306b8fa7fe1444a927b3d2bac9300399bd9487876	1	0	\\x000000010000000000800003a503bac662e80fbbe0b70fc612e485634068c5082f6f19c96bc86adfbd660e3fc33beb586a649c43e0be3732a5434fd7ef214eb7ebb63ab6d70cb3c694c9974a82c5e3a192385a654e42f6386fda2c4512ebd6d3b7426c355739294f5bba32dd9145612695d1338a9e31de7cc6a78ce98742ca488fe7b247e61db52a296d93ef010001	\\x708883f4637f4b7678155d9b5588e15f220a5e9863787120fe977b7fdbf1a25b63e0d994a7b516afa2254d2ef9eba620e6771e1a61bc1d8f5c04e650ff276c08	1664622797000000	1665227597000000	1728299597000000	1822907597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xf0d4c41e85442ac69f69b93f644dd5e9b962e9d22c07026c09dfdf352a89b93d700cfc840c9a3858d87b75bea49bbd0249ddff59c1db166fc3693140d70070fb	1	0	\\x000000010000000000800003cfd97c5d861bad1e909ce0b20d2b66adb710cb5ee6421143ee177c68579afef3cb23ac78eca521d6fdea1f0468e43db7cfaf062a15a944893a8de68592614fed1dfc7afb360a060de4ee50fda20fda3c82f4628c323420ed85c8f277d54881bee123323ff44fcfe64c886f5e138db8b27bfb42192c093614c3eb10b178884d6f010001	\\xe1138b77bcbae774ddfd45d9d2eb477d0f1ac9f1eeb61effc5af2561e5069e3ab21952c7fcb2acb184845d239137a18d83325a63e8378e45e7cd29ee9d3d6201	1662204797000000	1662809597000000	1725881597000000	1820489597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xf008401793bee237859ba87905df236ccc0d0bac2dcd620e67343e713c97b7db51aab773a5a226d1fa2871c52b1c969a1e68a04bdacbdf3b7d830e5363ecbe2e	1	0	\\x000000010000000000800003eb2b345e2d53822e82d7d28d1193351bd521d4bd5f8ebf47dd8da62af7230081849e43c17cd3cf97cb5b817ba9e350f0c9024d6fdde4c6f74d5226eb5e282459a3314b11326ca8713d8d1c4be677e916a6cccef6c3591e39976dbcbccb24c074d25992822121ac9d6321ba96851804995ca40e0bfabe951c17ef6c49bff87413010001	\\x649f4b889f1b0ac8a3a49e46428f78f0bbaf7646da17f2a7c9e2fecbf87083aa0b3a102e9a2f121e7290da2eb25bc53bae98a07a739b69d0a0c37a10d4aaa60a	1674294797000000	1674899597000000	1737971597000000	1832579597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\xf4489e1f580f7c8bbb56235dca7d10f8ac88a43c6e5334e1eec99182c4607d9c3ff36492312c336e8e66ab4683c2841fba326220a357fc253a310ef587c27fda	1	0	\\x000000010000000000800003b3024de327aefd6d14146fc932f05c40c56ef853e355ecca6d602a7f031d5ae9a4fc2d19c1ad8c259787908de8d67a76cafa7f7783ff6ec8c99dea131b5f307bf76563fb318bbcb43963acc014dd98191f664f9adb153834f6ba2722fbd034a64f338c1e816fedef86b3f1beca2677e4f4cc6c190819741ebc2fc611ab0e430d010001	\\xde42abde52a1c9455835ee2636be2d1028d16e99b48babaf48e8c0d58cdeb85a95f48540a6b908541115db11879c84a50e8d0bbbcb5ff85ea33380681200ea09	1673085797000000	1673690597000000	1736762597000000	1831370597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
106	\\xf538eee9a31c5459c49a11e5a7036928eb2ce84dbf1aaeea9205961efd95839f15a4b5087f386433a6aa52d498ad187486d9c2bfa314a30595905634843addd0	1	0	\\x00000001000000000080000398b247b0e0a0e270a48fdeb36ffe185e8e8a3b5b977e29136808b00beccb5f3fcb8d6947694292fa88010c5779dedd6e83dd30d4e94ade8e8ae30ff9efb24afc478915e9ba3650b6324dbd50aa60188845a0a8c0f06e10b78a5fdf1de514e500d29fccd37c68cf7484d6891e70f8db7a898e763b675ca29d9f0a0565e9ed0413010001	\\xa9961ffa3835ca35f09b577d20b7fc4a101fea8b75096bfef95961e9470e21dff0a3ef0b3b0c161d73e189a25686106922c04167563fdde392f855d37cc88f04	1678526297000000	1679131097000000	1742203097000000	1836811097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\xfb847b11151fa9e7697db6b074d965b678ff10ca3f4ec5030317b2672ef653898f0d4e318f01f58d57175dc538544b6dcaa56ce207bb9c242d0841992a07c7f4	1	0	\\x000000010000000000800003dafad14b64f664ba84635ebbda39a094cb6de817392b1edefa86cec86aa9afe3acda8e03fc10644a663193eac82e279fcaa7c573b7cbd25a506ec2ab5c2817a70eb98537c542c9f3dab4f634dc944d4ec2870001d70ad44ba5dd69b896011d0114e13d42f0f5129ab2902812c73de7ad6e41dea1ec72e7513669ba979110e95b010001	\\xf46e1a91a67258c8e27083934c48f4d56bc9fa8809a2773d1d27196f320f4549850caf4f6350ae39a2b6f9c8336a1a538b3f59321448cbb29f2b254a06779001	1674294797000000	1674899597000000	1737971597000000	1832579597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
108	\\xffbc9f641b3a8ac7078d2fb32851c23a2a4fa311f5a1fbd163de4edc311733dff52bad05b9e931dadaf1e6026d8e453ff90f234dd4d6848e1976da2ae799fd2f	1	0	\\x000000010000000000800003f5bff3aec782dfbfc0f95e909d32dba1588335c8a4b7d3d48c1ca7c8dc5d8e96c5caae33462fd83a4cda0b2d14ab2041615ada3eae8957847fd58bc53dc72c4355c72fa72b31c498817d3a72b4e2e9f8cf5d2c596dee76f0f543096be34e1750837d66fba154eaecb493fb720626f28a2e3aeeba959a1b8adb60f8d76f41b303010001	\\x629245ae90c79fa048f6425d7037ab294bae28b6e9ba0f0be4db766e00f7f5916227c81ca92a753de6ab3117e31ba39f6cdd86630680fa98df5b23c69be38804	1668854297000000	1669459097000000	1732531097000000	1827139097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x02d108aea697b329f4e2a3a227bc8d50d0f1b16596da868622983dfc07dbf87b3c19fd45c5f5fc5a05d3703a328d863f247070aa22fb60e62b723b990eaf6cab	1	0	\\x000000010000000000800003beb7de4eb6b2109c8f36a11a8bb51be3e565b28adef1b710c247afb8a339aa33302792ecbefbf6371aea3d810e43c16fef195a8f5ad5c762ca7c493d1c92c1ea3c8a0e5364b69bd6ccb862a8018887fa835b7efa1a739d6e20dda29e9d10ace7c6bde2a9faf1e65b0f54202d1ddcee611c6a165a94703f65c3072bac0f7ab163010001	\\x48cdc46fc947f1cee4802cd8503078691cdf2c20768b4e1184e3840393dda3b09410ebce45eee22ae52dfd57c97c9945650f07e76020f67358c59f9b3dd8010d	1661600297000000	1662205097000000	1725277097000000	1819885097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x05d5471eb8b67dea5674e0af32dff080e22effd8aeb34c9d257cb6d71074c0190518cb22bb7009245af0c2e01c8c4b43045a48e7be4ef7c1aa4bf15dfa090549	1	0	\\x000000010000000000800003c396ff529ead095b3031334e413a52f767f8719c0396f6d768e956eab61ec073cd308a480854832f0a148d6f97c7995dd5d9e7d4e15aecd29f4ff5e26ef8b265508a37ce41cba37f0ea4c13b5b88d15a028f0490d6b6196564ec54444fc67d8a9a758eb82d38988b050765f4d40343c3999453960b854a091ca3e801e352b92f010001	\\x19f4812fdfde9b4d3c8849345b3e69c1fb9a0b5bfc068997f9644d61c17f480a62d8d7749150a067635df20957811e005dc6e6309b3dcbb52bc8a48c46508702	1683362297000000	1683967097000000	1747039097000000	1841647097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\x0c29ff3466f94650d221cc4c8a8e082223df5b10bed3ff3671c0a6df32bb4e1dea9d70b9ec0fdca107594b891d6eef92123412f1f419bc48f0ed614a29729bf0	1	0	\\x000000010000000000800003c64827c4986638c4b5dc99e194a7e4082f4eeb79cc2eabe32f4725a09535b1ad777fd6f2a343f9f01eb1b6b1bbba6f11699feac8b1464a1766aa54833b202b85b4adfccdf2643cab127dd6dc6d0cb782c9ad0b8e342b3b64d89ba515135062d3dbbc5feaa256ed2bf0a2db315327ada8c3bd7b08a51cd78e4c80e49fa250b72b010001	\\x28ee2de71ce2506fef183c0989c77b522eb1fe3490e612362aea33540b37f30ba061b3cdd6d60f68c7ccab15dfd5139bffecfd67390f2b1d12428cced3c04c0b	1685175797000000	1685780597000000	1748852597000000	1843460597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x14d94e3e984d3c3bb431f755fc42e0149b5b14f249e22213bfcd5a920bb4bce90b274ee03cf2131b8c4d1aa02d3d5550e253f2b2b0295ccdffb317b1c760f1de	1	0	\\x000000010000000000800003c9891517d55db8e892e9aa6b5985fd4d18f90124a71317932ae4dfe87077cfef280790ebaa6009eb4ad41992c9d9a55e166556c80eba77857da9181b6f6742ce9be4ba86fcc8ef19bba73283b4c8ce5eed0f6c77194ba69ea61411c7656b043b5a3e915bfca7f050c7fb8b7018c22492e4666a4f70e114f968e29da014c8cb43010001	\\x6adfe4e7a4d8bd8a398001a9f62db1e1963f07584c1cc3e186c03d8231fa6278fcc3b4e4f2ac876c8350e1aeed5069c795633b1177cf319e31bff0de8214120a	1674294797000000	1674899597000000	1737971597000000	1832579597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x1521db2a38e1b49cba6622d8db15c41e8e53e552d5b9537b82e51cc10a980c6353aaaeff0ec2ffbae498b44f6f1c962ad18bded68d1e593edd3fe76205637dd6	1	0	\\x000000010000000000800003b3ff2f863a8e928e2e80ae6ac9ec75564e9b6d01d7794a463346f8e12f7e5e1a7d2f4b05c52304f0e447957097b0aa2093bdf4831111f212e06aafc004a1d1e7f3734a896d9f99cfbe09f17eafeb2884ffc651ad51874d4e6d0888e60bc884e0b79f2e48edb66583e4a5020b7ec5071173be2ce953113c85e390bdb65b26e64d010001	\\xfb3789bba3848d942bf311ac6a2d28d165e43545002a628dbf5d69c1c45438a827a399881ca6d536c7bf20bcb74f330c65d24ec9caf2d93c018691a9cb5a3006	1682153297000000	1682758097000000	1745830097000000	1840438097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x17e5a621aff6748f786ea82e3a507a5aef770133e066ccc711f408c148b5837a5424ae38caafa5ae1671b145acd3a5ce5560a4c5e6ec5e75eac0a1410e248bda	1	0	\\x000000010000000000800003c0598cef4568d30845ea6dd1c2045df896fca764f171416406e39f8838389f7d6272f149d7d0039d5847f0b81b867f144e2dec2c2abea9386b2972bc08dfd19192e2ad6eae83f92fe9e57f0aed6fe12b3eb7215a04145107df23ad7a74242e37e32d66df6bd2b5f771b18d8892fa89cb08f97104f9e55ce66b5bd21b7d9fd001010001	\\xb6b1cf9f56c95a0c27fda23469b6694e142362d1f9a60c1187f99b78b22e537917393c3a3abfc2a077ae4d9c3d048547350236abcd4e4bc4753ff67ac2a66f0c	1665831797000000	1666436597000000	1729508597000000	1824116597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x172109920f400d4403707c671c661f1f3ddc1e5a95bf1ecf184247a1dda4864813d906801bba2f235b1cfa7ed5f620d684221169b67646089bdfd6fe2bd613be	1	0	\\x000000010000000000800003becf9f4d1a2c5050cdd638d2ce7ab3a3132956206bb9dd0b37aaeebf9a01321f5aa04253900800046927f81f86d6b3499219c4a6bc746aa7d179dcb7b20f907005886861082ba8c555b4fe4d46466ab501f283748ab22c58cdf677ed3e687465442a3adb07582da1635164554e87ada3981520e8d20db345d201435b80aa9655010001	\\x0395730b523b9296cee5aaf4a61da524e5f69986c5936dc151497081f55f774ae27930734f2a6b5e0976dfb381f558d8e77f60d7126c216900b9b6852305560c	1690011797000000	1690616597000000	1753688597000000	1848296597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x1785ed740b70a77c2cc5c472876e8d21943baacce812588db920fd55b6a297ff3cc6733e5ec4faa3ff913b6ca14a980a9247ee76262002b6fb0758b97163b684	1	0	\\x000000010000000000800003d5f66c138a46b7287edab84c4fd7dbdd9935ed9b40c2c714382d92d775ce5c7d2dbb3de1ad2191a02c8c207cc4a8fdd47f1f4c47f55aaeb0bfab639e02e29ba9f425e0296a12798978564341d478da21af5f63792b5fe9cb6a2fb2a546920946158aeb13961f5a927054bd7eb88c0eca5afc5f4da69d1b6b38bdde96179a0069010001	\\x5284c7d8c69f6874f689b2b5af2bf37ae5bd11593af85981f9d2b41a16f1e19d9f81863abbb7c110478623702f5ca52b818cb0937dc7945bec96aff82f053a02	1669458797000000	1670063597000000	1733135597000000	1827743597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
117	\\x1989b35c95344c00c8258cc99ca300186d0a9a718e9965d1fafbce0f6c3733375e183ed75695c6016a29230fdf73277ecf02b9d49bd1c5c38c2d7fd1299dc827	1	0	\\x000000010000000000800003c766f52610a3a4fd28cd7241fa623701ef6dfd3afc229fbec51c71e580ca066ff9f061f1c5c8f026f233b263a824d18c3d5f118de5ddf0c5cb3e759b81721d84a358e931d95f740f52f455a08723078accaede40fee83a673cbc4d704287e020507c879518b8cc1e45931ba6354334b8265717923f0706e831e072fa36a60e67010001	\\x360846ce0f9b9373f9828b9e57915494c56f3ce34d6edbe2f2b00ead95ee2efe08bba561ff9439705dc206264703c4bf0a34d8154e4142aad672996931ba780a	1686384797000000	1686989597000000	1750061597000000	1844669597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\x1a1da2e1a018d02e13acd6db874dee9e3bfe0724ee1f2a5967f6c5d817cd55b5d296b23c6764ece95b3494635b1289f2d4ede40c27e5fc54d8f89fd0dc45acdb	1	0	\\x000000010000000000800003a4511cbb3e61c8cd4b66db8aca820a2a0eb34b4ee7a544155710c4a26d82a62a0596b4833122983bed5bc0d1dc9a64173d207d07f722fce3314f12fead17c11853cc4ae4485d411041ce4c1ab264532a0e4d1e9cb2cd921723500a25b0d14c6ce8f620fbc6456dcf3e6806b40d7155cd9e5f2bca331d8623e264e55013f71671010001	\\x3951b9d66d3faa93ab319072acbe56187a7a11024b15e7f95d4e358b807fe031793c50249f7b1cad60cea42b6dcdc42c74a666528fc0b5376bbabb17c29ba50a	1674899297000000	1675504097000000	1738576097000000	1833184097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x1b2dffd48e2d2378ecc4ea93041a3a9d60bce33a134a2b1ed7450434e000107363c8b89f6e3e971dd08305d2aae7a4afa0df7e6f634d5900a6e171b2aa317905	1	0	\\x000000010000000000800003eb98621a1eb34ce06848a301de29adc8c33ae9a72821e077cda62dcf6e730d05bbe788c6288b988af291c0520b8c559eb67c90bbcbd0385455a2872910ddaf7e92eaa1291568388101ac191209b2f82b24a92c86d148904124d33abbf9b5c9dc8f5ab9154084c09a05717ece7543a1640a87eb9c777bd5e6abb7a1917da1a765010001	\\x894c7bf287e2710deb7affb6198101b4ff0684271180d768d287eb591f9a38517ff9ef08ac2319caa297774a0e830989cad1802462619d3d143855d43a87b707	1685780297000000	1686385097000000	1749457097000000	1844065097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x1be1d2635538f96eee4cf5e2f2ebac4037e0e1a77424b55f35f43b67e98a85e2bd3aa827eb17a9885724824b11b661e307f66632a9126479c4a5c1806b4372dc	1	0	\\x000000010000000000800003d88774bd487a4a34e1d587caa4b47a142c5a1c2ffe57e3a532bf4d49ecc67492db1cb2079561597cd3ac39254a52abdf18b5f39f9a77d1880dcbf2f0a380bc376db0724d2490c36c8d145071c86815f3c572e7cdbf62b20c2f8d0c0b552ecc3a0403a52b8c02ce5dd9af723aa35865befc6227941d61951fccd6dba5242478df010001	\\xbfaf516eee8bab4eccd2f44bfa7753591953e1e524ffbc25db8aed26fdad8192ebafa70c2c900f4f361ecb3b82ff26c693016610e11eb47582b7a5be3939ef04	1660391297000000	1660996097000000	1724068097000000	1818676097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
121	\\x2011d9d78f5cb9f67e0e55144d6d9415ba38db74cebe3533d6942b3546dd105ed18472179529ff76acc394775d80f31bf007766dc4b1375d803be51ffc77afe9	1	0	\\x000000010000000000800003d59b6432336c9072af59bbf3c76b703b60f13ff584bc90bdc92c3911792fcab96c0c8a2b02a2ff5187c219231677f70d64bac09f5a729be3b2a2d91411806548cba76823c93d807708226c9e471789469895989a91ab490415e03603290fbd76a927e2dcbcccc672e670b00e7358c4bf39564e09831b28b1b2f5b029152afc63010001	\\x50d774f405028a295147fc9e048d99a11f58ebcb7dbd84af1a569249ba6a320084fb7a44eaa04a2c219b633c6434dbfb62bc6e8925439079b92d076cf1d19c01	1660391297000000	1660996097000000	1724068097000000	1818676097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x26092e6b3b3e10bbcbe23f49c01ff2c63e44b5c39cc6b919270d1c20b9fb81f90e7e4c46e64234660f95f267ed58b512900e1edb744ca94b3e90de888df1190a	1	0	\\x000000010000000000800003ce27d24adefdf53f384ebcbc7c9dec074b30b6443c9c51a793e7c63f646c6b1d7b2496a87e11a5a10a3b3f5d8b890e3e4129194c17e6b867757c9b465409053fef150579df7bf53a5fcd79d95ee62e5193b13ec3837c594b6b3f925038d726b10234d1392a54875bd1ab94551b29093088c2b248d67488f3fed9ccdec63bd7a7010001	\\xafa8accb30379cb4e10da166d69fddb28163499b4c65444e4a8d4654063e9fd388a8a6e1369956bc67a81038829f60df4ef93079776d96b5b485c4b9d727fe0d	1674899297000000	1675504097000000	1738576097000000	1833184097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x27592af6399970c3c9c1c0b8a7b6e8d2fbafe29537229dcac2e8b1903ce56793eac9342a5125ce53d0cdbc8b193fc1a9a496faeba456eb4c6a966bfa99187c7f	1	0	\\x0000000100000000008000039f31bd089e689ac406b96f671955e90acf6e18385a74863df472861ed000c323f6962611a9638f6ad58c930a7e4bbc809ef6adbefc980ef0cfa44ad4683670dd5e924eebbfab55f34b497aa445bf669f9429eafad181118450adeaff271bab87cb5fb614f05204802ba23f68e08cf9ab9c11614afe275ca7fdb738fdd517d3a5010001	\\x7c87a29628172502253a5bf145a065e7b8eb08c23abdc1ef50c4ad7f83f5824b4147556d2f1a564bb364cf8f431c302f0d45fe9b9b0b6a76b9df696f0f4f3f07	1668249797000000	1668854597000000	1731926597000000	1826534597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x2b612aa9ef67c6dd6eeb5b164a442916a2eb2fabb27663dfe949de0655f2dfb075094384d14748285891a3e91239c9d9e5bea3b5f1898c0ac89933e6701623dc	1	0	\\x000000010000000000800003c05326bfb88ca729f1d06690928ecad06351ec119fdb8f612044d0d00154c78276e9fce633b74ae54fff73ced262403c7e333a40e09a90accfbeea0afa89be501fe6ec19e145bc3487cbdee308af65207905e59583282ba90d7d76c433a0db8e037f6c320c4d905df554b48fb85c84de0a9192ad57ad7c6e3199daa51e873559010001	\\xdb5228c4d3ed60177db28f7a8241c318d4b1f1ad747c27c39e13ba6eac3ecba9be171a0d15e4469c883a062029b9fadfedd7cd14f08f9ff404564b4cfeddb70c	1690011797000000	1690616597000000	1753688597000000	1848296597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
125	\\x2da149a0b987c8c29bbfef9bee820bc76132bd622e2e8d3e7c5d5befdef1e5ce16a2c75954107643ecea68302f160d762028f5d64a34738c425b75c314aef291	1	0	\\x0000000100000000008000039f3ef2cb53f9e1c6aded25387bf44d213a4d6a2f33a0834843977a9ef048b8d975404d945298dd4b09d30db0ed9046103aa9b95521ecb607605b9231c553bc38eac369c1c2b9818cc1d1d2cda10bf16d388ecbf3631a4140f4fba1a483bf053c41812e38ed5374d06a815abeac75e70a65c9a0dcb680eddc1aa6ffc870336de1010001	\\x7999da92aed8df7c3d219304fb7d6fb201e0e145d375e992bd98ea5c56411654f9e2885da498d52cd8e0649e8effd507f031b3372ae7c1da635f62fd869a7f00	1669458797000000	1670063597000000	1733135597000000	1827743597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
126	\\x32891339d290d08bdbca484b8c69d24e66429516ce588e3ffe0b18846757a087167933355844f94e63f5fda6ec2cb2008ba6fdfdf7690b793021fd1bd8fa3d63	1	0	\\x000000010000000000800003bddd279d8231d81ed46f9ec55db804cb61a2f3d7d7eaf96291f38946f27fd768e0a3ec290011deb2eb545752201455cc131a27b7f74f46e4db3a12365a3c5880aae382c4f9dc65ecb514ea53142753fec8215024cdf208aa5f1b2c68681cd42ea0e81a8e103d1f4bdafdb73325056cd58ad715237c0f5fb60d325bafc81b7db9010001	\\x3dc368ea8e6e2f840bbd91184467173de9392ce69fa259b47288f896377ced8ab5e6bd102a186126654531bae0c0f2bf264955c02624c4e2c762126c275ff303	1685175797000000	1685780597000000	1748852597000000	1843460597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x39b1398e6cd85de49a1f17da14a74887874cf06085639a63092185c0aa156feb265831ad87999e8021804ebd5cd86c19a0cb0eed4d61795328fef8d482222bef	1	0	\\x000000010000000000800003b23eb4651aa60fe5519edd86b3cf427eaeea7a8db5da7837dd27a9a331d495466b3f19135dfc2454ae93f279efe6cb5623a104da01ef62aeffa3119a604fdf72f91a0d25c560c57a3fad42129febd86df27f62d69a911701ebfb53139954bc50eabb9e187d1b432179ca9be6041cdd0aff7c70e4c1fa869c18659a60ed99c41d010001	\\x2170590d38d934664b1fad5e478345bc1fdd4f1c85fbffd9fcfb3a8b386761fd40adb9145cd2d56394a4389a2c0d5b5944427775a408f65fb904cc52d5835a03	1674899297000000	1675504097000000	1738576097000000	1833184097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x3a39a47bc141d99360dcaea592d5538f8d848c589df05a389fd13820aa5cb18787a84c98286bcc1f01119b651b3e9e5f0d5c6c86f6d0ae36048b2fa8d2324ac3	1	0	\\x000000010000000000800003cebffe3f64794abfdd737e951fa563206c3e6a44c122b143e2383256b3795eb6de09ae980d1d6675c3ac58a9fd3f4433c4740529091833479d1ea8ab5957a0bd6c56104833f63296c8e786ad603a60379dfa60dd7935518230e9aa2d6302c01ebfc126d6cdf1892042ef836f29ec9c933e068e3d5f2797948336b393220ec7ad010001	\\xfbd3c867cc465f076a71bef913c0bae9253292fab05b37c45c4431843ee321e2de37d6e8025bce3fbd0f298a9c6a1f227119fb16e25faacb40d64a59ed120703	1663413797000000	1664018597000000	1727090597000000	1821698597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x3af549ec3ab77c3f33fbe14eac7c15017be6921eab18b7709dd1a28169e72df10bd0b432141e8e021669827bdc78681e6da4da91b04333af6989ff003313ee41	1	0	\\x000000010000000000800003bced30b163815d97828b50814a246aa277145ea97c32baef4afa7197406a7bfe7ad605b7b120c437e260fb44c42bf076b958ffec8c6f7bf4eab8043084d4cfa633d0b23b94cf48a0537e7eaa727bc287f8c2d3ea26b626326813f944e132a593e541dd6042200b61fdfdd3a9823db660ebdd1bd7f4145bb2510a37967cca99e1010001	\\x235dbac3df7ba61626f4f9867c7e86ab164524b8c9c2f91f2ddfce29a95d0ccee5355743c9b35bffa34ca7e83df9d6080e9e0fa2b792d0af7ad17d55c9ff2508	1666436297000000	1667041097000000	1730113097000000	1824721097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x3f1d7f49af113f10eb04fbe05fa51463ea0a95f1e14c01930add1b5d19499327a6a41e8c2bae7ce1f3f59432bc805c024d0c38d40fa1cbbf3cfa53943b946522	1	0	\\x000000010000000000800003ada74bbe9328fbd545e982790c00083924bfd4e3775f13887f306a3a8ecf79691ffdce4d0b363908db8d4c58a3470cc8290ac1b599b3ee4511374c66bc4dc7f4eb9042ee3f42286fd062c4a9bb3e728bdb4abc6585fd81e8b722fa539bfbe2246529f4ba7ae4eaad00924fd8a8d9169ae11d3cfafbc4611b7a38ee1f6d90a457010001	\\x358fec0487e6ffeb85bc6c2013bd907dabb7b7bbbc06707ab4c94ad8d9b94abc752dd807b305ef551e4cd906bc9dc77e11d0ddfc711a708afc50d7abf7670609	1671876797000000	1672481597000000	1735553597000000	1830161597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x429904928e4397f45158acbf4341b11206d20b7937e5df3209b66119b5b400db11c4eb2eec0d75a93269013eedc1e251c132bd012e44b5ebf6e1ef2201c8417e	1	0	\\x000000010000000000800003a8f960c076a31ae2198161188e2df195356163274947b8acc12a1f63d9de9a694ee28d9a1d7f69e6a20457a69b10c15a5c1dbf51a97f1e97648e792a4f52091927d1dac0be8cb7e47d3bf7d2efbf37065ada10d3cd693541240693aee48e923e632d10958f50d662b67c26fd1b48da929dee32bd6cd1c1e7f2f56b7bfa2a586b010001	\\x60fae1f1519b5eff841ddfa95ff19115a5eb305bb78dffe7a3309bbb75a443e94d8f98e7de98247cad41da57d2476e7b1694ab8fb060fefc506843d32b3bea08	1691220797000000	1691825597000000	1754897597000000	1849505597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
132	\\x43015ed8513adff9d581920df1c3228e4cc28a6813c24dd69a6372e7d452cad13e06232ebe401c39584507df9e9c9dc483d7e6b260db50540fe650621b824eef	1	0	\\x000000010000000000800003c53f0b06fda660781974dce32e96f53568774205a5ffe038e3511884f2fd4f011049c3d5adcf32d43e786ab041616a19ebfaf8ee5a8be0c8da4a5947c9233f57a6a2a8379e71f8dcff196be00b571ba52fc094a1e6380c17ceccb2750dd699876e6b237f551b9a91d2c3b83d8bda61c3669158beccf63d18f15829d661c4b813010001	\\x535b189470d0401a15c08f3d23203c9ecd9769f29e85bc44d96fd419f324900087481225f9609859e1cfa074f783f4ff7d328baf4e0ff41f0dda46e355704303	1680339797000000	1680944597000000	1744016597000000	1838624597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x444df69d4bda5bbb7eaf28de0583d2ab741a9818700ea089c71e5e793eb2a91031f227426c996c4a05ae5108ce7caba65213d336e5e2527ea54a89294d42607f	1	0	\\x000000010000000000800003dd043f2a49afe755d30802a7a3019cf729f79fe546b33757832f8ad9e5b66b262a95cbdc4ac1929a749ce54a38e1969b2aa9a974c2ad95a61905c9fafe12027dcde0854b59e58dcb773067b160f5e6f2030c5b84e0c874d346f79e887d1d69425b48e01e7e2c98198a82a1cfd9902b36c9ef8feb3e424966fe2575e1dd3a6e67010001	\\x903288710f768ea10557b0955e2fb03b3aaff4d6760b9f468cb6989bef22f5b2320c7ce2e2f7dffde7cfae6a8c55caa55e71caf047400ece627e72611ecab006	1677921797000000	1678526597000000	1741598597000000	1836206597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x447944159702b8eacb523b5df228a19a35904be4b1e62567bebfec7c1eeb7be9cf83bbdd882c8abcd0e8849cb5643ab383822e5217ac0449a6211db58a131e3f	1	0	\\x000000010000000000800003f9eca6b5b57e98573fefc3c619f6d449d7b62dcc6f6639f2f038d28f15b51657d6535a1a20904d2fd49365544c73222e4fdaad68d4ff2f225cc97c86a69f6f7fef28f97088bedffec954d914e8e7d33ff5151e66d34ba88c0a3bdf035fa2a12eedf4160181e2c6efac10290b0b9f535a44b8872d5aae7ea255fa89a18bbc98e5010001	\\x75ef318f4c6b38f9f585b09475cdfa46268aac976bfda47ff7bec0131b02164f246bb23bfb947c70e67e6118310f08837760f85afbe72b3f0315df13f73acc0a	1672481297000000	1673086097000000	1736158097000000	1830766097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
135	\\x4a213beeb5e1d0426f62424c10138aca18a8fe9ce05838e1e64dfa6070741b5e1ff834c9ac5ceaa74068fbbb26eeab442c4e90cd5dd1e604da7bd6c7c301bd45	1	0	\\x000000010000000000800003b2c0a61d81317cea0c05ff48488ab8a127dc48aaaa57c5dda4319d099786dd64003599eb1a790784b214ea4ecd50c7f41acd5087afd9685534ffea88f62cb1dadc8c9d17b930c8c45c82104244b7b8a9386c0788103a72905facd2c9f12cb531ea95b3d9c2f048da16c64c22301ba084cca26f71e6f6aefde1a91a138aa792e5010001	\\xc146c6065c388ff2d5378f5dfaf4f9ca340efbe6e35374cbfbc99b55768cfbe8aa5ca4b283a44c404b634266f06a635c3c374d5c4961bbd4e3cade15280e9905	1661600297000000	1662205097000000	1725277097000000	1819885097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
136	\\x4c555a026afe19a92dd843676e02fc665bbc4f31736a1f52cf52a86b98ec41b1b2e214498799f63c06ac617fec358c75a8655b354eba239280e28ee46a52a527	1	0	\\x000000010000000000800003cff3223ffcb9556d1f1878f2f51d7d4982660e15c438b7260e5af63c556a4bf951ee244d3c271c5328eb777dd6bd32deec304ddf49a39b04250f206eeac832810bb1ae0b414eef6f012036a736a92d83fb02f41f56e929222f83d18938c436511a3f9f88c4b3ab276459c57c6feb9fb7d9304115d2d3e997f3a976ceadc14e1d010001	\\x0d4b39969cc1b113d89129aec1c34afa731f25735f7f3cf3274c6cc9b7a69d0de2355d4834189f63dce633f86459d2fe049faf04e02c1752e011596118555607	1671272297000000	1671877097000000	1734949097000000	1829557097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
137	\\x4df1541d397a15294fbef07682d5e098edfe39b4b0118e790c96c74a4d1e0bd6ae6eab423fe15610182e3bf83ca1fd576913b92378e82d850255674a40f7a988	1	0	\\x000000010000000000800003f99f6c4160a15c1fe033617b7735604907341b638a391e8c69f41b58cb11acacac01fe5490b70970b9849a4c9e85a7c4e8eac719cafc39dc67fe6d398b39b9797680a26f45e6590eea066c07212987fd0a775202f06ef7b1781b38b34485cc74e449b425266c6214ecc5cd2155f06ab0728d98f04d4c36f6d836555a1c009d1d010001	\\x02fcb183d6c725cfc36c0dbfb3f2ed176f058b4866fa0bbc5a727fd9bd9799c20c8dca429c8b02106b4d2ab4bda5c22d50e2e81f12e9f5aa3664d9725496620f	1684571297000000	1685176097000000	1748248097000000	1842856097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
138	\\x4f6d6e2c3a28c73408d64a694771ea71d9cb8bbd2d06a37ed6975d7392a8e84be4c684a5f2bb1d08be52d05f24079067bb9ff0004681055a1b8be456083f1506	1	0	\\x000000010000000000800003c192e413c0f20062dbcd108c48b0e33598d9f31680bbb0525b871a179050289a53a388a435c12905b7f91c4cef4a07079d2fa36d13932493b841c19163fdb74f78e0012af005aef02ecbe3bee28a9d014f53730caca84fbd1819b06ba4780c38bd4a3c3a7c75913aae2f9d0c7abee342fbca8c819afeb511f82d2473061fe85d010001	\\xac9cea87e0ab8785ffa7418bc2d1c213165345ec41a7ba47b0551ded9e8077eaf805ef3b957dd98427ac06b2652bf25f3968dc17d4d2146363616806cc2d7605	1669458797000000	1670063597000000	1733135597000000	1827743597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x4fc9a01848a3261fe22daf141871a45cab05cac92567daecef336aa811a0d8ef34674c54d3f86db175201fcefb5b755c2fc33c1254bc3fd5862f3b7dd657c256	1	0	\\x000000010000000000800003bc6708789b6e1a2a1d11056f1eb95c55c5b03896c00a431729354a77e124dd0cbe7768bff7e37f2a4cf5e2a4c2de74512785288ef48d1f467c19b7da8f96cbe2d1b57e279d986f60d2f166e05f8da16006d545c2067edaf6298d0355cf3adb18100012c729c23e9ba6695276c36067fed2070afe724dfd14adf120218afd2e63010001	\\x722a66359ed1ec7a5dcaae31fd487a3a8b057414615c2336f06ee19e24aa9099059772089250790406fe0a38457cbb164b83fb385eb82b70d6a15ff04ba6a209	1679130797000000	1679735597000000	1742807597000000	1837415597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x5199abc63b4c13bdc8033ea77be2d8a45f7383940c0f2253498c29a99ccb20e85a6b0a7dcbf4bdc6ed854590d43d48bce5c4c9d062486e954da8004f30df2269	1	0	\\x000000010000000000800003c9bf2ac04753f9643115108d838ce9cdbc383059182351bfef9a30a54faa06bad9895909094d01663a59cf17f1753bca30fe8b799f4e60f15c424e60c1a6a51732193f1f0b49d7e2597190cf5c91aa7b3e630a0f4c4e6dc5eb7785d0d918c5df5696dafc51de43518e52238e1e437875ce54c6b7a642a8084ea8fe1d16ba6945010001	\\xf989917aee5c28a63a50fa06af5dea2998ab45a2e03020acc0af917a814afbb6dd819e5e990094e00c450efa20d540c7527004b09c1629fb4e1819e26ff5f70b	1687593797000000	1688198597000000	1751270597000000	1845878597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
141	\\x524163d0c46fc3a533ecd396d33332acc33f1c931c58802fde8ddd4006b3d8338bc4139b22cef0a065fc1e252ef10abe111472d385f049aab8478685a118ba19	1	0	\\x000000010000000000800003dc1557e49aa78906e841f6b704c1109710192232d837a369d2b34d7fd9f3b80caa32b4656b3f53dffc035ce7389d2a954da6478ad78c95b6300673934753010aa7b53c4879c22ba853d92c9502261137f393462ffc215b6972170265eb8179babe027efb489f668001933671d6a2d5999225fde7849588b9c59842611db396e7010001	\\xbd11fb4abad3720f06499253dba05480b8ed1e0575df3e5bdcd095836aef6cf89d2ba988d85ee60f92afb8bf763a18a0d7703cfeb6da3d1f5ec1748efcb9b607	1683362297000000	1683967097000000	1747039097000000	1841647097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x57a14b2722e15616ec96a69efb66a77886e95e22905cc99350cd4995cb4cca1720d8787e80b022dddfdfeab08e4ee31aa5b3bb2923004bbc392a300077ab54b9	1	0	\\x000000010000000000800003cfa649a94f9dc4775aecdcdf7f09ad6cb070c90737a9cf122cf99027d7f01853d7f44b5f1e412e72f2420b9421ada8604dafdec0f22dac084bca5a4334bb8d486fbcd12e83c4750b2579f2042ee60e994cf222337e1a2cbf9148ad58928c942f586eed1855fe873be2a0f9bcb4f1c4dde0d672126f40ed182bef766ca1fc70a1010001	\\xd6404f88b5598bf59ae95e46b38a40c1826f3be4a65036ed8781097c5888e27d8a0f8dec272588c239f0095759e8b083af1e39c8122e6830b9e254f4603eb50c	1668249797000000	1668854597000000	1731926597000000	1826534597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x575dc397a94de70972b9e9ec69f3dc6c3b54b1580493b9be0427ac740f207e71f55be4d151987ac7ae6210c29adc4259e83b2b82cbf0ab3909b0913675b25fc2	1	0	\\x000000010000000000800003c406fb5499e2867a03c8b90c389441043e730b06108e3be7e46068484e12e20bf919d9411ec4443167bbbbceb5a1516504208330feea6c094fa8f5d67acb57887180bdd90944bd7d8441b3e9c0ded6812122da0d0654a63a6595b2e636538724d450f4d4f4d6b13c0d7680ffb72b40838009c5554cda2b6f187a84c1511e0179010001	\\x21ccb768a047d2466decb365796334a6c6dc4bb82c79b40565ab3874c1b99fc3ece056b51442429eea1c771d5ec815d666cfefbdf408fac1368f52ac420f120d	1680944297000000	1681549097000000	1744621097000000	1839229097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
144	\\x5b59825853ed64810690300d9fcb387cec38bc870f8dda842340f3e918d9c1484205c0f7148b465e35fc6f8426e1dfd3d93895d6623898cb9e5e47287ed35096	1	0	\\x000000010000000000800003cde72cedf1a1c9a285cf7cd3c819584c08c769527d3901ba3f1efaa1bea348464560368b3e21a2b3b6e7cc238b285f995971425bf9db525fd9294db0c0fa0bdb6a8411efacb601716bbdc46b06e226e52fe47b22ae922e6c056d765a4a6cb80c9c31e1cd60b09f8c5954d418a929cad11dea7904e9557b6fe71d6ebd9a5e3853010001	\\xa3fe77b972745c1cd77740c651bfa2383a47186837a46950fd7afa997c0d473436aa7f07d82bd68db13371d7ae5814290c4255ac15214aea149f4f727ca36d0e	1675503797000000	1676108597000000	1739180597000000	1833788597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x5ce158b1d218cb3ca5d95199454566ec169e47635956ce3d555eef77fc878a65bc65aa900ef9c81a9e360c458d67ef290a29b312720c8258e74bd8c77fea45cc	1	0	\\x000000010000000000800003f37eeb566b951576ead8d65f12f809036d0f9d7064249e03fc533720df96aad94f66f1c46188de7ddd0bdf1fbd2bd2dfe236a35314fc78b5ca8c6dd005bc43c312327a04509165d5d9f602696a4b05fe499b97b227442bfbb8d8d91e8388429cc9265a09a94e7ad66d9049aa96ff0f976c3c5efd6aad1269ba57cb298c836467010001	\\x77173860bd0787835e54d4f455e91debb2fd09503c123bef0fc5a4caa52f4085ab147e5b0ae06726da16c0bce38c615e2337573574c9becb10b921164e72a302	1682153297000000	1682758097000000	1745830097000000	1840438097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x5c8dd7c89808ef9f6408c03072ad520c7508197045a7537e3f2951f72c1f4983763612ecb5a2acce29c32c358eb9fa2804c6be5b9a0548e5a6fd4c3168bc5514	1	0	\\x000000010000000000800003bdc9db151a8a725575cac1da8afc970d682eaa8eb7ee829a64e080154a769c812b014ca851e390a80417fd09626a8f9af91c08a50e32faf41021044b761533079bd5157c1ec46842d56a84816ea8f10e84bcbdfbcf6de073974c54922741f2c3b5abcf6b020baf60d29430db1c8d584b0a4dec5d7f049f63c7c3fdb529e60b25010001	\\x09f86592875b04c42b57d86a2b4a54f45708fdd2acf827be87d7785ead6f72e9072d567ff812c2e068e740d60dc9c7bfcdcb4f86146afc800fd170c199bd6606	1686989297000000	1687594097000000	1750666097000000	1845274097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
147	\\x64a599f2003b338cd4a428758f9035e0bb790caec050c8694ce25d86c65ff39d891fd3faa651a8bc8c9aef63185d50b2ec230492e2ce90115de7ac968ca8643a	1	0	\\x000000010000000000800003a09b3037394f83ecf5f4bf9acb06bf50cb4b1b2101d74d81e1441bd0331517c900fd55c73cedb6b9768afd1c06ec19ca675a74d39b7204c29f2b669db639ad9de846f1b33020dad5c3938cf68e9b59fbc9a89b90eef992e39c81a8753331154fcec77bd310faa0a71547d379ccac3020034cb271a436a67b6530b01cc807af1d010001	\\xb53ca41b6ede95634f4a577406aba391bde24138eef676ec1d32bc86a4671bfaf7dfdca83ed35aeede3fcb18190f3a772619d9d542d868f5af974e3f7624cf0c	1689407297000000	1690012097000000	1753084097000000	1847692097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x683d6af173fa2b68c0c35d4955ab24ce1af8f57330f3f14e424e3d5dd1b461421bb95633adc8ff78e16cd661a7f6403ea964f894cc29f296790d75e71b68daf5	1	0	\\x000000010000000000800003dbc0313ab42e04ac675737282aaa57c412ad5d625b71a43a9ce436f04cd06ac9b676bf3b5f2fb95a7e05f1b4321a9d8a3de5b504459a6498389e3609f435df99a830085afbc5068d1ade48ae488f2b4cddaa5a5c348962ae44ecd5002c5df620f5c96be2be75e62098bf551f86aafc8d60c77eb171663ffb2769b20976e1a5d1010001	\\x1d726aabb0a74a766608123ef387ce107b5e12a4e26e028488634c5a01f6a43618c2ec378c270b3cac0b40ecf2b2c772cc579c7535f340ca8ed9e9aeb7003c0e	1662204797000000	1662809597000000	1725881597000000	1820489597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x6a11f503cd776fa372177272e6af03cae0769cf09dbf9b315a3b9830ce9144d43b6e12fade2ec77fbba3ac3f496a82fa0bf94e80b536b9ff7a6db5cb8a1f5a27	1	0	\\x000000010000000000800003c80ec989cb126de9994ae65db68234308bfa4596e79d65099966d0d974f07fac5e2da40c75ed0ce7b6a48cfc95fead4965101a0860172200b3be60c5c8309b0d9072a09fc0b6fc1c345349eef5662a78473169fdae63ce825a6073aa023f2d3d17d54d8a95cd7188d05324abf007ab0f11d81fe775d1a490c538576188b8369f010001	\\x0b6980444c5d96a1a86edad08a721794536721a265d217dff836c90b5a98ed8ce28456cab263e23dfdb1501db2527cb944a762658ebc2df0b7118fd14fab0409	1680339797000000	1680944597000000	1744016597000000	1838624597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
150	\\x6a81c9b96098b827609ad1c4fffbe30d562b9b6027da8c49d29794cc7806767f8c0f54775d48cb7fa21fce2e99c37f541d5933714350d8b1a5798df292e4b66b	1	0	\\x000000010000000000800003e4f1b67c115d866822ddc3ca64871259fbed73270f4fb6fde06ad7779ab1a139de32146e50ad0502d15f5478a848a03e1f58d8732d861b3a35d9a433e60526e032865b3c6d693ac9e7e45fe1522df7a609cf4853cc5efed1a6694e0e1e115e0a3e4db150787f319767e8638a8ec245fff9676e318697ad9132c587a0149313ad010001	\\xc78aa1f4098bc7a8c39fe9d7a9d0f059890094781525d27b053836607e46009e62f2744587a8bdfa088a1a6f0384558616721fc641a0120a08e40640565d6d06	1671272297000000	1671877097000000	1734949097000000	1829557097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x6b6531dfc778ece725a6486738b1387ce354946ab9ede1f2dd5e918d7ea985e7f9dbb7076c4b8b7c17e147724bd0a68725049f1a971b553302aa3f3e63771a56	1	0	\\x000000010000000000800003dc2265efabd0c210d51b02a27eabd60bb4de781c5e5c87c3faf8548042d7f04a35b1e69972843e0b1412ed839dc251767207365f9b5db09cafea7da410cf12ae0968865091c8165797bde72f8b0945566035e97dc2f681de4367cb06bffa569af4b71c4a00c5e71cb2492d502bff9c7ae7802c93c660513cc23e92c5310fcddd010001	\\x71850ccd2fae4cbdbf25471da4beeb1b892ae234712a87806675a2a7f67f95a54dffa827f5907f7c9826267c9d88b3be33ddd5637018c02c2baabdb6a1d41508	1669458797000000	1670063597000000	1733135597000000	1827743597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
152	\\x6b190893a78c833aca7c44bf49f93541f096cab888173553a56de146fee55fd34b1f7389cfb88b3c863bd7fa37bba30a210e703c7c38537bad1568cbf271c1f2	1	0	\\x000000010000000000800003c7c1fee6c210fbfcf68cde8ba2b35b2ef7aa22baf36377b055b5d973f1a27f975f40dce5080f9fd6990a0e4fc6c1b1b7112fab5f66c2e054dc09347fb4d347ccc917dd3d627f5ffe72871a1d395b3a787511604fdfe521caa0ba70c8bc86253ecbf9a88642b2f35bdfcab7cc73cbd3aa6d47bb7d0de7572b8b902ac9dfd95c6d010001	\\x9ccb0a510025d79cdca7642585bd9a1c6abb4973f53c33fd2274c9b6e3a495e00c0798788fa357927f89ad8775eccbe9f238cb4795c683b81d0791b4c520b802	1687593797000000	1688198597000000	1751270597000000	1845878597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
153	\\x6da1d42fe2a26b0605d4f16bc65ea24d4684ba867845d59b84dc4b0c95b01950037e2655ce3c58e60082b0ad9c8aa50463d6a73d0bd8a3209507175ee1a76c58	1	0	\\x000000010000000000800003edba3001280ea9135266784a08b51f09f40ea0d9537926d55b385ada6460ff9e0ba035f82889b3efcf8cecf9d9726a547f590e10ed4c1ddf4ac915fa44c3af2983aca838f435634e7a758cc7f67e7c2430b0ebeaffacac49cbce704c562eebb524c370fcb47712a372074ff9be9fa1ca0ca86824a3f1d09e6758fdff5622bec7010001	\\x9d8dbf9a7f3b60ea2a2896c61019f27d388676022f4e75beb60344c4b9457fe181d9f37649828b9fdb9692ef918668e32fb50da06f17142a0ce404fecc9efa08	1670667797000000	1671272597000000	1734344597000000	1828952597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x6ecde52e80f02b5c0d60ca22a3b96bb423a35112b4c8183967db5745e4dac50c41d10cc4ea3ba5751718f23c958d29464be2c811547975d13a1802fbfd95dbb8	1	0	\\x000000010000000000800003c63b7815ca85f9983d8d7a2307c29a6cf7c6066bf139fdef897088afd80a7c7478cf82c8784ca33c193455bedac8bcbd26524e02aaf7f6a21c251e9ed99620f8e81b1a100dda3ef6666dfd335fec5e39af6d2eac7ea6ddd4846f5059a9ff24a7e28cc3933f5f2f662a55664d8fcb558c879589e3f969f77e9efe0bb6ffd27c75010001	\\x214845b063bb0bb3b5f03609e343674a31e2139b9c58d47132c0a3bd2b82bb2d66001fab2957c90ad6107c25e460f940680d35d223729080e3591cb920abb608	1675503797000000	1676108597000000	1739180597000000	1833788597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x737dac02c88894d4981bb5cf88212961fe34b88a84adf53a967225a877afc925583cb774e902d2604b8344c1ecee61e5c63ca9275093f6a4a9586a2f469f2f1c	1	0	\\x000000010000000000800003998bba34b6069582ad87459ece2742e3b13e879b35d59287c29f21a4bb3aea03777472f046e7dbfddc0c2a572f52608ca63b51f4592094c08ee0e2e8e636672589c063d817c5aec2ac3d5bcd97d62fc5d99ebb95fbadf9e9fcc8601e8d65c543ab124e7cf013564ae6885a0b4acaeda042b07ce023050fe2e4a25c8884782fb3010001	\\x779f3f54eb3bbc492cb3b6b78eeb875984ec7693bae8321ff8673247b991ea2c10c7d343c4ca5db3ac226c4c218a275f2d026105da4dfae56276058fa872bb05	1665227297000000	1665832097000000	1728904097000000	1823512097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
156	\\x75b15cb835f5612c342a2800e968aabfcff59ae5b85560866dc818527cdde6b9462020827ecaa4791e6a33ed8c14fa9283c7c3de67ac8c1d2f9ddca02dc2981b	1	0	\\x000000010000000000800003d93e5cacfc8b7195e2080491a2cc6b70001d2228415f10b1a161e76e16c54ecb324d83d3db99b25cbf8f542c61f7ca556c2b4a6551a5ed6957b93623db3571b91405e7e1cbf270c1835a6670735fcc35b251249410b4e2283976e3f73e8f4b12be697661a803f2f3ceadc8ad783ee0260e532d3161b22d0515348e5a05bae019010001	\\xca3b4029e60c15fffb34066aed879f00df4cbfd469ff6fb29f7767d29446c4cb5b6b537b46c12a56dc238d74870187a280b00ee53eb01c01a6d861c4f1d3fb0b	1663413797000000	1664018597000000	1727090597000000	1821698597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x76155cf618d24b3fcdb390d08f03917f45e076878124e2c80bf09bf2b023197b1814c561e66467bc496c31489667502a617111477b9411c62ee8d32c2e1d7ce4	1	0	\\x000000010000000000800003be434cce2a062a4bc4675897ce4a63e835cc949b06feaf87b7ba3c1b142c13bc9db60eafb9fc186fdcc920d751f876760987bf83a9276a3b2e1b4cf05be1580c60308717d6ea9a68094367990a51f0e2da44b51a26421796c0c223826a29476d89a76a553c39c2e2dfb350020ed8a7ba0660b3e6a95a1912bd2bd4d705684787010001	\\xbbb6a5368b9561dca80c5b890379cf25f67292ed35369ab82ef8f045a76a571f510c3cebaec8b0c564389aed114eecc1c8c61c0d7010d1bf9fe3c6df43920b02	1679735297000000	1680340097000000	1743412097000000	1838020097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x77192e48f6d44aaba7da5040224afbe35a0e740b2f6094cff5e347ecf8c9e50dac33e7809eda5e7295c03b605328d7cdb29711007b35d69b969cf9521945a4dd	1	0	\\x000000010000000000800003b53b601e6ba8f5d29a38fd98ed724c0f4f56d0590528131e976b1acb40bad6a5154619d03cfb60520787db6ad7f8330a81ca233afb69b6a65d6debdd00891a6e7a64286fffc4fc481a1c1de6508d41d59ee0213822af77715019389cf59f348e39c143943ddfa7c68cd3ef726c0ce9246592342bc4db610698ad8ce1350b84c9010001	\\x1337214ad454ec538367889881960de0e994219a2e9d6d545dc2feb6b31f171100c85c9fcab59d034fa845241a9b1eb1a8a8602547d00ed5fd3fe282c96f8004	1673690297000000	1674295097000000	1737367097000000	1831975097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x7a8d92da4c36d61cc234c2799a3ba6b996b6440257815b092f8b4c1f51fb14f75eb4feb307afca2ea4c9b533ae18021a3da0003e85dabd817c64968d94038568	1	0	\\x000000010000000000800003bc5abd70980aa3ec303574479dbef178d50323f79f8111e44a95dea0cf678f997b734ead85ecb146d96550058d02b2666fc300bf2c17a8f97e2a313afc2f40d13c0982e9a1a256cf24199ed4ea2fb16ed31ab1261c8ec7e11c25d31592aa41740eace63dc1882a6454d5e2fbfab39c9483ad271cc390f1b71758fb2b502d5801010001	\\xb8203ff64dc0d0a50531b1321d79e34b7e745aad495de2f4af590c5d102c19e64266e2ca9046c9abe8172bc585871b48f33329d397e930c7303bd39045d91802	1664622797000000	1665227597000000	1728299597000000	1822907597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
160	\\x7a290ab175d8c01f510497b8817c5750a926c5e369d0bc87abb244d86b504276519990d80a853b66f24e8f264f92cab390222185c5d8432b2691f84d36409bc1	1	0	\\x000000010000000000800003b867cb828dceac931a9d7d07a6dcace423bc2ef712c70fde1296d6d0ad073297726e0ecd311c3f986049c5c82ac25d94509a1394aefa867fd2c776d8a9f678491b5760658d2eb6c6c768c23c267a0df5635b138867ccdb4d127b70934dd2cc5ed4fa1a2906ce4b66126ea261aaffc306c725305028215fe748b23e290a33dbc9010001	\\x5c15f7a9cb2ca1fecf4be1d1ac06bf4bc4fd0accd6145bf85c9ae7ee887b6775f5095836b17d15839b593b7bb2ca8eed4757689c7efebe882d5862d52d116f05	1688802797000000	1689407597000000	1752479597000000	1847087597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x7e119f00c0402dfba79caf19e84e17c24b07c7d1ae72ca6438dab19d2dda4ee062ad437222b95d32c60ac888227e7c47297f627f2922dfe08275278271eaf7c8	1	0	\\x000000010000000000800003a99357e7b05a9b3ae5f4281b79c7fdd69c9a78a7d214d1e412e138b534ca7fb8161347bd9532b562d720e18decdfc8e41d79b15a56db2c060c449b1084bdc5c425ab459840a992b09f275988e8dc14c8ed37fbc5190abb488a1b544e24f9a1879b511cfae9e5e0704a856408be5b77b5f2f44dbe6da39350e00ade489117ae79010001	\\x3809bcc21a2716d50401403147d28db19e954dd50c321cf0ef6ef532257d5c9df4ce6e5d9f11d55dc613e7d1d8ec988c5c25ee5a66275582479ccf772237c100	1689407297000000	1690012097000000	1753084097000000	1847692097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
162	\\x7fc95a087dbd1a0f67fd59eb5d0e5d775bfd70ed0359311641bb22fdcc2c8086e8b1c2c65d9ef5348ad65a86858a8d2070d431fa392fe3761d9abda5e7ea2be7	1	0	\\x000000010000000000800003b348f7a2808180428ce5ad538ba426edd2de7f9f12326dbedd1788ccbf45dca5a6b61ffedfba387221c870edf041df9036ea32925db2b0c507825e1949ac834631bceffded04ee89facc29ed3fc5ede8ee55f80200e06e361a386fe5765d52b2d99e7579f1959904834566b2fecec2efef8022d5dc7b56372e4659126f5ba7bd010001	\\x4014dfb7f86aa41ea4684b58d7587d2aeba5342a08e1c41fcc40f3d3156769e641543e0a779f24d5eedfc243dd5127e5757fe096ae226f08c3e247c6c9f1910d	1662809297000000	1663414097000000	1726486097000000	1821094097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x86fded7ff52086a53d6f927fb1193880f307aea50f879ad5aef51f99856a9d62052fc60a16036a8f4d158398f953887539a6ad88ba4b90efe0c0d780947fe3b4	1	0	\\x00000001000000000080000397eab9796f28d38a9a48f2749c876ae81ef825526e90cc174faf36eb8121ec58ff5ac7a30dc2d5e370ec853e227da59407d7d81aadb220f177f4c85e960960f144c03e46d590f4803fffd54087efd2b18f22e00806d40d20ea54e549bd33ea2b217686786d5ecbf726c5b09769f7ef794e7c81b58e4e1f52f23b8e61f429b00b010001	\\x1ec0114d0284c3cd1e28ff1671eb7a555623e9b050f5d2d23244d37a420412693717ab20048341c2960965cb4eb03524149604795e33186538d500f51528f003	1685780297000000	1686385097000000	1749457097000000	1844065097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x86510c3d7b0ac6945d51db4359cc334a5c12939706d2756740e187a7819e1da49a343fb6651653e354a2b92e91ed8e32f2e4f1955f51123f077384e4b6a4347b	1	0	\\x000000010000000000800003e700fba08692cbc926486e2151eed8b60150cbcce1604493d4476eb356903686fe73c8da5f0c7f9a3eddff67104161485c44a8c544edc3d8a1a698a90d48431152e8fe5a00c95fda4ea06ad4869c033e526f78a2f0ee662585bfcbdac925b34d3b52acab09122928f366cd602c0c6098500728726a917446c83bd92ba4dbe66d010001	\\x9343358e9ac755dbf265c4905db6753724a21bc57d167839a6995eb9572de078de8088fd715d319f1ce0fa19ff1df4991b4205f8212c7ae34e4995e97b3c5a0f	1674294797000000	1674899597000000	1737971597000000	1832579597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x87a1fdd702cf3c92b5090b5eced420b3dc22e6d0404bceae80f8973f8c2be39615e0d8221282290d358df1cb738dad0b42d78ebc9510716ab326f983a17270b8	1	0	\\x000000010000000000800003d18ad682393f939e1c89517d7747dd7fbbe2f827a46fc8d72b62e6f3a97bfdc40d0a6c06c7c6669aa8c017cce44f970f992865b57d32e1e151925f66140b836e767cfcbf15623b6e84f309fa319bd7a7e7f6486899ec5fa9c0354beaeffb2b6ae094692bda6fa8ebf686668c6c461474fe009977dfaa2b4b84ae199e47b4bc21010001	\\xdc95ba84e3424cfb59fd101e587b64c87c2a685e397f7631da4dfaf3e33177b0958f8c0525539ff2e968a3eb7d17a66c2277b9f5cb5c5c4e308d0a04dc2eac0f	1674294797000000	1674899597000000	1737971597000000	1832579597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
166	\\x89a171f95917d30d2679502c365ccb07b7ec77b2accf4a8562441b4a0dcb48e8eef1ffe0262aa345e9a06fd67f72490940152defb38d1c94089064a2f9332817	1	0	\\x000000010000000000800003b10fe594bd05d5b64cbd74ce6d193e96b6cb18f4c70263576f0b957bd766442629f680081a5cd35b18fe800c7ccb0893f09aad3051d8e0a33fe1df965d767c008662c236eae8e5a56847ca137a3e31df4e7f32cf29d2376c474d8bc87ba28f97cc7ccf49779340db82061bc72832b4ec72dfc20a510eaef20807544322994c0f010001	\\xbf117b005c2d6679eed316016e213396007aca2546b39a0dd85346136c13d41665ad438106496fe96ec0ca2f1e1ff10e1e62c1370ca56d10107603a78a82b40c	1667040797000000	1667645597000000	1730717597000000	1825325597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x897d2dd02013afe6f6f1696910372a30a733663503cf455bb1399e91509221a0445e5986a6b4ee23ab7e1a2c84812e35486d53dc6c7eaaa433e058f14c14bf63	1	0	\\x000000010000000000800003bf79ed27bf300c1042a7bffcd392145799feaf7cedc571f8048a11cca0ab3e0b24a4be0a9b4071a24e1e948d6e811c8a93bfb3566c4bae840bb17ace35e30045b8e551c5fd1ab9578725151416781e701deba08ed8736eac9a919d57f6f744082ba8fd5e002823193e9379f16e0e21447ca51a0a1e1804fa33ed80128f54a87f010001	\\x012c51b5a57f3783b52df7f831663db199b6c50d0d2b7e1d5478a509aaf85abeed0fb7466219a8dbfa8f34cc71e03e68e25eced67794f7888195efd3defd5607	1664018297000000	1664623097000000	1727695097000000	1822303097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
168	\\x8a61d1ff2cf5ec57102d7a812f8eb910b8eb1a7f3391c89e8ad551b7250c5ac02c25c7c23df7cd50a6d2a62f8da2449b4179c6372b4082c794838aa5919fa5c1	1	0	\\x000000010000000000800003a31a7489fe0770d017cfb784a972bab7ed786dc11c63ce6813e78ee4ee9cb0bb3eff573b166b6574ba39d2a41852e0b10c88f56265e63a46fec2d357021aac9234e7118e60c24ba8b2243a62f76cdf63fb1f9c1f82fe39b5ac218ac30b6ebb5aef7b59c354921ea017e007fe22c07b52177884d11ab2683920203fa160a70719010001	\\x11924efd6d62cea1e876d842391ddbf2b04ce247b12cb41be7b7d2ebe4c58d1395cd2f4a5d8309820b65d2b5437757e1b541f3c62ba6270d32499a803b1d0007	1685780297000000	1686385097000000	1749457097000000	1844065097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x8b1d0ccaecb0c1b35c0ec361023259d3b0bf6e04d62e3bc2218421fae8d79fab59bded51c1599e996c869049b991a3521cf74f9ff023e9da04b1ba2584d38ae2	1	0	\\x000000010000000000800003d75eb21141e079eb572c8b43e808b6d0fbcdb60d62c036fe6d5eff0164869a379e4b76debd5010d83aca03d61b735c7ee5a2c35827c9206e34569532cbde4af488d8888eb6506924328e2377dfb2ae2df4cbaf8d6b1b335c5b702409f6bfbf41ba5f45a03d0bc5e49bdbfa5e09da39b853ee637fa4e45355302e424f387b0ee3010001	\\xae11890dd60a00e07e8950860e275d94d477c2a8117b417171ddece9f854f2cf5e9f380685faed560198f4f6e91f8b9a97a6aa85467c7c7efd81311f730c5101	1691220797000000	1691825597000000	1754897597000000	1849505597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x8bd5d5a5ea71ca5f77859a4e7d1d4df03f672a142408a8cb65ce91f893c30a4697ffe3825eb6c57814010d2fd25b9087dacb4b4c3fbe61e4ab3cbf96ba8a7485	1	0	\\x000000010000000000800003b415bd720e4e7987bf79cfb0476c4d00db1939344f4440e145318cc7a4e4c3ed74bc634ffdc1ea63a8ead5ed93f0c82e45fc1dbf27b4893e7a81b274d3a490cba2a53846fce7e9440df50f4e42af3dc9ead87623313aa69031ae328b347c7e846b3da400e0ab7e3a4ef8effa4a3ef1e8cd22f828dc7a5ff228d1820ef5b74437010001	\\xa33359bb6bf683af89b1c67fe659282fd035afc30c7764f4dc74c1ab53d2825e3e8410a59a33cca0b0b61a55d50355bf88772a58c7f1753f9f149e73fdb82a02	1661600297000000	1662205097000000	1725277097000000	1819885097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
171	\\x8f893a2f012b860d373f5bb6a4b9259a49e28fc1dffeabcf4e31098464b23b722af97606dbc8dcf203ad38dfe84fd7024ba036d86c86a3a9bf22a36d2792c5ce	1	0	\\x000000010000000000800003c840aa84c9df29dec90560ed5abb421dc308a8dbe03a0d516edbaa9d655fe3c35afb7d64143077782e31ed6a4ecf89c096d0cb5c9df2e87abe2f410066a7f6371430d6fff23373314b6d74737d70b6de3464bbdf0f1bda55f814fc3ac53c0437323b757cf03fc2664b17744c5a7b141e176f95a0458c7efeea7971103fa4fea1010001	\\x12a02ed1d150db7196bc6e1791cb4e19398015344259586ed1f5bdd2a714458c07a403b50d5128d369d0da8a57b1ef70227780e3243830da31798ccf3091770c	1671272297000000	1671877097000000	1734949097000000	1829557097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\x9065dbfe301e9736f68dd4658223eec822861bddbb7f73dae41ce74bf1831086cfafd4d6cf7e09a5d63d1939a969f84aeefdbefa24bcf5b1034240c6da6ce44c	1	0	\\x00000001000000000080000394602c7ab8635c573f767742d5e94d15326a02aaa944df15e8bde7a02a428e66c0ade46ba9db5bd350c8db0ea4fa343288500c8f176a43e98f98bc5079851cf91888b9b05aca581c3883ea85172bbdf4dc622e0a7c6d1f7e03cd9c580c7e3f66d04f336ea4bcec320af5db603848579e42b7f8f74ee8a71b5b8bc5f1ec6b8c8d010001	\\xe69f40021e976113177e991cf8e25837eff7bded83a7dfdc0a11f5ff0514f06458b9082994bfa360e919aa92137d396ef471785bdd9fbc43cef1b3e064a8cb05	1660995797000000	1661600597000000	1724672597000000	1819280597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x9125ffbf8e2d075510579ca9df54e01f0caff4f501e4c0e9e6d417344fbb2bce1bee6c4cae1eea2908f9b1424d70afdee99b6e7535138f32617d37ec8eba24dc	1	0	\\x000000010000000000800003bef9da6645e0caaed401af731ab9651a98c7e11b26b5e9d6715cacd745db30685a3ad7e236fc3c4cebbc1847c03f1225c6ec7912ee28be821297e6b818494e1248054a6cfadbc79dcc5f919552953cf4dd8dd6c6f5baf8f923ab3a4bf9246f1c8588d4dd7801efd74a41ad6ca2b448bb2a01b5efaee3a96b252a9d65ccd730cb010001	\\xc3c2e4402b405828241554dfd3f08d614b0bf26183446d1222e1c51cdd4f9f3261765c12ebf26c3255f6f4e3c8339a4560639a8fe0ea958cfb0eb22d3410bb09	1664018297000000	1664623097000000	1727695097000000	1822303097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x937966b90554265a3e278fc925cb20e3155935934ed0004c81cff46f388336a78e5cc9fe8dad61055b0e3a6204a9fb254ff1ce9aab418d876df4a921cb57c113	1	0	\\x000000010000000000800003c870c694f6f594ccc71dd9f48ba691b4d297c1af0867ed9431ece1db2012ea893bc7c2d74d689d63fcd9bc79d95f96a075d6ac8d0d18a0270fdbc0dd1937979fc53be5376ff0c9806aeb9c95d153d5fedcf87a3b156b9ad00bf24e4017a6f5e84bfa17e21a5090328ac85e22e68d0c8fa335f01511a98793a0207b0ecc50e04d010001	\\xedb1a56a733b4944ef56229db4044f8461b47ae06bc46a22e556971d1cbf276ace641e1b6cde1acf3b0fb4fc5eb89755c512be9af4c9180ade4069148d924004	1684571297000000	1685176097000000	1748248097000000	1842856097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\x9669d04b1fa32dc5fdf1cf8015213f467f3f76604a35baeb12c929ad26f902783ab23564f800d745333c55ecbe3d071bb3871a1f485029ac20a46918cd66b715	1	0	\\x000000010000000000800003ac985b5c1301f678165ae4d821ed9defa62e71b3c5f0a185277e99843f42b67c0ced6b6837c7025a0cdd1ef02e7d74b5266c574f6f2569623ee00962e0c26fc8064da2c3ab90e8afff257a6a79a755281f2f0611f494bbb9d7ee26812680026d8be63e2fe7f93a83f8047b7deb500ccd1b78ea13bf0103da00408338f913c037010001	\\x2d22695199acb5c26614e5982dfde4116501ee2166ace463cfd4181b0caff82f0db9bb252bc30034c1886d00237766e1591edca4e7975e72162a5d6f5d689400	1673085797000000	1673690597000000	1736762597000000	1831370597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x9d4d881fd2699d1915f44f05b745d57aa4ddf3723e6b6ab9374430e5ba1c8637475fde5616218480fdce450b296dc1499734168e748caeb40cc986502a3dc9a6	1	0	\\x000000010000000000800003b601986e01b64a8c8e41bda6f5d3db09af5b2ce1da27e83438a02b3c12d0cfc70efa01c7bad1a1e62d8fdec71b7b62b6566c35b12ec2ab428327758016bacc2b2d0929b8e596d01871f61d6e39dedc4ac28eea866e1541460c1018ef5baa5b1531dda3b273dee335d5522612764dc21f095269287e89c4388e90e411b734f52b010001	\\x83114df553ebcc3ed2f4af62482f2465387255a4cc40b301154b18534d135e68c1a2e870c3832e8b280c305305ed2726f631b2916c5f495233b135debd4b1104	1684571297000000	1685176097000000	1748248097000000	1842856097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\xa529e0d4dc9cb2feee1c4da3c95dce317354ea0aa06a23c5487276706f514c0023f4465c36acd401f3e68a02786dcb157a611a4b770dd83b06c7b0eb8dd1857a	1	0	\\x000000010000000000800003a3f86ac6264b70a9b852b73c02e5d7c6cbb935e5c8600a262499b9a97385d22b2238cbe2ee849009eb6607933aa12db09bcdb6f9b158feb5f5f4994c95f88a1598bd4759f2ee8438e4b14abb4db1dcefb3d1b0201d506d2522ccfdcd657488aa04b70d0eca80a114fe8b1e3b2e2d76cb9dc7271f2c7a0991aa1e44f69996e9dd010001	\\x2aa6a58f233a7486d1643afd067556dffa1b88ff3b4d4d1bd6b3840467f069d3b013ba485e146f157b05d813ab94bbf86bc269ba49d030ba8800e76b35b3f906	1683966797000000	1684571597000000	1747643597000000	1842251597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\xa6d52e342fd174319dd2d78f953b301340d1e9a29b2fd2e84b71a1eababea587e6c79cfd5803d799dd6702f8af7748add43002cbd2040ff6eaf5e06f95bdaeb9	1	0	\\x000000010000000000800003c49b7e7d354ab435786411126b2e07b33810b089992c818f59bd917e1b8ef6497e5ce880f73132d3d4d18e7d7a0fd3f47a8ab4026105488b166d09bd840edd8a6f79ccd332e307ff6220e09b230698b0b9c47b259628f281a8810ef1915164f9b41fb6c42947a285fe22a884f3b8dcc8bc2f5ad71f09d5c5a80e247131048b01010001	\\x5ec04a349f99ef78a83501c6a6f0430c7e93add4ccf132f1136edca4fea895b4b80636c58172577eabbdb593099d08292a653308e6a3f229106e3bf4ea2bae0a	1680339797000000	1680944597000000	1744016597000000	1838624597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
179	\\xafb1de934defa7834b820aa9fd221dd529f1b4a94d8ad490e5ab3ec7911f5d30950c0c4e038d2b7229973cedd4a53ab63c74e5fe234eb48613e91524c6ca7308	1	0	\\x000000010000000000800003b82dd2576ada264d009ec44e57dad29632779f4bb296151dfbfc6e8b49249d83fdc04c8018fae6078355262765b003258afbc1cb2495b8f4ab1e67982a196dde93a2cba4e90d77d827454a1b9c863762d7b8bc64550d247bcbfac019d7204cc73eb35e417ef72d2e14578c8aadc7cc56e84d019d191a72fd3c4bf9d77874783d010001	\\x3c9c2e9d4abcdbb2f7ed98071a8fec6f3f5c48097c96584b606cf5e097994e3957c719c1ce3443cbd47a832d8fb1e244783dde586df5a34e841dbb9592f6020f	1677317297000000	1677922097000000	1740994097000000	1835602097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xb505f64ad353d318e70f51f9496bd20887467c3f0c51d87ac60f91baf9ae0c37c9a1ae6ccd493ae0c81044972a701609d11c65db3fb8898a7bb1b2bca3364b68	1	0	\\x000000010000000000800003a0efbfd982125063465caa454507722f4ae271ff1ffbfd5710747b8ede657fcf1c0e22f62513b24d7ff119075bdd5af7693383e96fa6a8bd8f89cf6c10250e34bdefaf93b75afa057c946ca6c55b2d4e4b97ed21df254ab6ad5872e2936feb8c950d9bd291bac02f42782eb2c3398ad7fcc13bae873c34d6c47908046f938491010001	\\x3515a4f5771202a17f98e56887ce49fd4c8fa984ee76155b0acb57625ef438d16d2c5e84be81bff2c4478b77624e35c8b9b6d3b15becdd5140838e953b2f7609	1690616297000000	1691221097000000	1754293097000000	1848901097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
181	\\xb7a98b89a0abc7abda745122c7bc82bfb9857ce5fe9386a6d2b7f4c13b00f0954e3eb4a52f242fda5a1cd7a9aa68e2dec986a24ad43f08fe10a993a71e8034b7	1	0	\\x000000010000000000800003b65137a10d1dae4b76bfa57db4dfd124507d9f84f2315d0bda8834509812cfa168b68f67d62b397d974928170d0216d45b7fc809788b19077ac5c01f2d19a382051c9c4fdbe3e09d6b5e6f5d2a6b1e58065722cd1c8ca7155a12143c33ec5c2499ecb13d1b22c0ca776492d50954a9446e10d76f1706d7bfb18fa2090b4b2327010001	\\x7bc498a62b64c6023206a20cb06202cf3c2a7f27f0628234fbb9c84e1e48fcaf70f55cd38aaa0662de6f75435a90cebe2f7509e356cf37296e97764a551f3302	1684571297000000	1685176097000000	1748248097000000	1842856097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
182	\\xb879a83aa653859bed78bf7f5d7966930463f6292783dd0ca475645ba2d1a5b34cbba2a6dceed879ad441bf65b411c639666745b980f83f57bf7a78bb04b0df1	1	0	\\x000000010000000000800003bbdb570330c5f0a891cc847e4db0a8a6996db4e3018dc233adfb73a90782ae6e25ad1c440b06135296d8fd1e95ade203b800d7b8534a45e4e0dd2f5a87578002ed384549c943dd71af9283336d9af5b152c723df8e3f1d88edb6b807c1a04416f8c5e42df9aa02b4a3d60874fb5766813ad4a7ac3913b9ae8684c3f2f79aa69b010001	\\x932935794f9819b880b106ca2ed7654b01163476fd1bd81acf1ee79ceb6030f9cf6668bae09ba8c44a56a0dd8f654b25d141028658b5145a88c0cba1b72ec90c	1668249797000000	1668854597000000	1731926597000000	1826534597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
183	\\xb9c505dec89c7fcdb4c291da1df203f290570d880a03f15aa1da037616dd270e2868bd29d5d6a8e4c545fc88998f8014fb65ae6af5bd9aa5e60f5b4750cfdeb3	1	0	\\x000000010000000000800003d0b9558b3fb1ddc27360fdce3cf4e9e8d8c73f53040e59b34fdd334ac642ddbde0b1178eaaddfec2b24715600afd63896a693be09d30474aa3d77a0775cccfb8e89467af2567da8be794d6e496f488bc03d7f1300db51b65e45c77e5c1c32526e8eff05dd156ee5c3138752fda70af7ca3eadb4d1e2e379121e133dfd6a59471010001	\\xe53a9ebfd44bf229809ea23eb131be79ed49227d70caeaf98937fad0b036b47bb6810d149839f0f9e22c6e370dd42a05d36d3cda29cbe9bfadbb6d2ff466100c	1664018297000000	1664623097000000	1727695097000000	1822303097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xbbb11d095cba97c943cee3ae89b23ec956417186324b67ad7d0b076ddda06cf1a8f8869439ba5c5d64357b0377c2513e3ba14411ede2f386668cea34a9087304	1	0	\\x000000010000000000800003c087f56a8b9178c61706d1bc9863a7e9a437ebf2b8a964ec072e2674bcbc8fe2e97623a375881116adf6c76778897e2777d93d422389a458f0e052aa33bcfd54e69c6b49e4bb01827ebbf2cfbd57436c53b13a9be2afa191ad7c399aaa912ab0aaba5a5297969a946b6114b1738928264e7beb3643f8357160014413134e3cf5010001	\\xd9bc1da25a2d7b262f110a06858bc40990f8bf0c092ec4d6c3db8cb28f53c4c70ab841f3c621bd3d4f65c6668e44abb072277cba8ffb58a031a3578bcb0c450f	1688802797000000	1689407597000000	1752479597000000	1847087597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\xbca1eca1393a0d27ca9fd2b88004ff9aa41ea1f4718be7bb0a8f005cb3bdd54fbada01f6201dc21c5de90527feed7e154d536fa58d9436c3b11484d27e3c0901	1	0	\\x000000010000000000800003aea6b623b163f20b9d035c59dda135af82904751340cdb8094dba4196ecf1b4d600ecf74e0a264383506a6078c5d85bb9d0b2e8b1461d9fa1657d131a4a74e29059ff0ab9495e09041478bfb6ba27eb9916970f5a154fd82c600bda4a4a844482d017497c9e1c65ca6c3a70891cf11bf5b3c193b6e5aef2a922f1e5ee9c05f27010001	\\x861d6cb295f36de06ded834aa671854a974d4aab7e657c3fcb1cdc4c8aea107ce4df807aea6e3706a8ff0dba2de85fa6ea23995647e666f820ebfa9ccb5cd401	1676108297000000	1676713097000000	1739785097000000	1834393097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xbf096bab5a8243f906dd8008b2440b423fd75116bb455cbf702cc441f035c88d98df2960449976691f9bb9941219daa4b327c946117dd97c589797ab565588f8	1	0	\\x000000010000000000800003e59731e01929110c65652da2748e1a482bb2aebc862fd777c83b9d4a5bc85e0a022a492e31f58667f572f1e8df75d3c488e9d723496c397fec696b19ad741438a29d790eb1bac5535ce7ecd0a133025dcc99315e1f6996556c3f2465a5bda759ba6754ceedd8403cfb1898f81acdc016485c9084d9dfc1524e444e0580dd63bd010001	\\x28d4037d98b5ee50bcf3dc89ad6963b96c909e1c7d4f42c3cc2d07ba2cd9fb8803447f35ba1f9459076fd988a0b9f78cfaee0a942a8b49742abad4a724de4507	1663413797000000	1664018597000000	1727090597000000	1821698597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
187	\\xc90ddcf157a2902209b2be10da8e876c916f8aefd413760e4cb279b7cbbf383bab57bd55b57675abf0e02311b74fb951aed4c675ff6d4ccd1185c99a37caafda	1	0	\\x000000010000000000800003be480b8a1a3676199e9ff51f53ff0f5806c19e9be0497627100745a1775e682bc3568117dd5caf9a1f4c1c4671ce1e5016d174f9ff0790891d46626859378879073b9b01a7f18cc282af4b35eb60dcb83cece895a80de7232de74fdaa4265dac61d16a25bfb1be4d824c2f290919ab69a07369887e8d4c86894d7881f261113f010001	\\xb9fbff2457fb27202a9d4afd220605098325af394e66db8113030d45dccdd6ba655035ec2150892276c3345c46b9c418fcffebf6405915ae68bca9fd6cc92005	1690011797000000	1690616597000000	1753688597000000	1848296597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xcef1e790661887fa939c55e86e1ffa6d806936234306e1e7a92365cf378cf9f8cf7811bef4ddaf43de878e5418efdea237eed400ab7c057bd0fa7a0b64a21b11	1	0	\\x000000010000000000800003c6ff9d60d07e7ca23461f3995c07074a2e81334e6d02ae27f392baf90fac5a2f2c9e5a74e9d0df4ec313f9f97a7ec7ebf381385a866e12d1613f5aac7660842149102eb189ca517c96ed9ab4e2ab912cbc33474b17cabda7f70b277af8f8b6472511dccad41da781c068738970ba20749fa82cfa460521f9b183230a066a189f010001	\\x9c7818665028e34a53391335721c38254d444966ad97238710ef6c380289c0b2648e6c9119d220862aad4aa4c7974804f5ee0ada1ce1c17d941f2e903004a906	1675503797000000	1676108597000000	1739180597000000	1833788597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
189	\\xdac1e373daf2c1eea02bf902d130327e2543d3bd1e4699236aef715c980d984ea8684eefc88f0d2bc9e2084d244f2f59a162c647fdd9ac2ff8cb3d44ef803e18	1	0	\\x000000010000000000800003af9a93ab339c19d5b8d5b2bd5429b1523273f5f64072e72d435dbb57e6aa6930520506fe8f5d7d1e38b75215a1f3567e89494f5b1caa3eebb24332d4db16c185de929d185130e0845c3cff98b5209e28c734574480e397dae25084c640331afce6759e35baa5287e0c888855b88a957d3ad4272dead912701cfffbd5fe517c19010001	\\x003544e921c77e786ebff1789762ebb6dabdbc5e73c32e28cafd8fffdb54db936c882f569eece807dbacd13e7be240a367c40aaa4ab7a40e512e9b4e311f3900	1677317297000000	1677922097000000	1740994097000000	1835602097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
190	\\xdcf513ca1ecacdbe00d9cb2900af4cc9976e24efa320ea48a5fb5e947e85e30271787ba131b06876b6ed785f6507aea1c29170d661d1fc5f93a1376b042eb40f	1	0	\\x000000010000000000800003c2a25de2614880061ff2680c5a8d65f4646cb83b81eb86d8c2a1ab1f2e5e39bf51f4c34db1a1784ac526ceed398be8b774d5b033fd9cb7849bd0f9e73cf169959a1acab8bd9ab422c77018bd8d84a077476598489a03a78f858d0c6f6262149a9a1c1a3423864fcb4da85baeb20d4e93ae6c176e6b5cb243f7cefcab407f190d010001	\\x52185d4ae418a9106aa9a1f917b933ef51d507c2c002d8c01669be586c5e4174b82520eef36feca5cd964763f644ca8350c88d7a76bb053f26d0542408e2a309	1686384797000000	1686989597000000	1750061597000000	1844669597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xdd01cb104b67c8e9cdd26c3142f9b5c819c5ed6409cea65d5dffeac9de0aa60c955276dfa2010cf44ac31c0839d7de3c38bbddd1f011d27cedde361d183a53ad	1	0	\\x000000010000000000800003dbbeecb6b48249d1f2da4c7d0dc236d47082b6f9f97a2bcc957462d355fde47cf677789bfb8c5e28d9a566249d2bdd209c83aa11b4ce302657c7600a7a291bc8e12a880701fd844ca6b48aa8e26701bb702a0e6b58dd43c48fe29642c67ed479dac852ae517a29d1d838c4ee51a6b6a595de1279292cb20cee730cadb6e91a61010001	\\x0a5f1407c83e369bda277b65369d6c81e7b5cd2dcd63695d3d49d4c477d6abc31077b16eaaa775abf1212ec2a2f82a9e027e729670656b84bac3079665244507	1682757797000000	1683362597000000	1746434597000000	1841042597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
192	\\xe1b91f9aeb3ab8d641a19e9343192374fe9c610cfeeeba6753ad525a21f3e3abca3a3963a298d68f78f35edafacbcc4911038c7e64c0c4325bce63a491767fdf	1	0	\\x000000010000000000800003e2e79ea404b2d508c96fcd0ca6b6343c02c505ba3a7f55bf16e267ff5fb3d9a4b503f05a63da15495ab7f0773c66f087f08c25c0375b8b11f853e3a88abe2735ed4db1ad6c8a7350fa1e8032413d20a155a8aea239ece35fa3cd7ab12ff653815d4298ad08a18ea876443d39bd22313705c72e91844cc491332c68a1bcc6a15f010001	\\xdb03a14d68e7dce94d4633531d7ecd4ed7947d6775b44a54519e3e17fc7b0d660e93a431df16cda0f6b6c6377d3739c39872d0f80aa65c7347c4f626afdc6f0f	1676712797000000	1677317597000000	1740389597000000	1834997597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xe2ed178108a9d2e78406f30fe1e08d24a1a94f55665f567ef4ede826f29281475420654a2b18c7c9e80209ef7894c65d86ae3d769765b3fa2e983965c3c211a8	1	0	\\x000000010000000000800003cd0761481a31dca2b26452b61896a8f99b668c2d82df0f39ebf6cab6b6a2be0553464ac29833893d959601a571f8dd570c12216d674e20f8f1d016aea7a1abdb239f8f0c78a338f1b45f7add0f4d22bc3f0b2eccb881ba868bf721f37ed1e0407161e1dd36377f9237c8dd99d1b4404575c31de380161d8eeb74715a34f05c47010001	\\xc6789c2f8340d980e436ead255c77b044536eb8f29ac612c5cb9aa92c3fdb347a310375594dcfaa9b132912949485a3220cf8e287cbd1f474f0a612f17d9440d	1677317297000000	1677922097000000	1740994097000000	1835602097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xee3948a93768c07766d1902cab68e67034e81d109bbb63761799e349bb22e5966855369f896cfe5bb3d92b6d0d75e1f47953ea0a452def4c9dc5b2909947b84f	1	0	\\x000000010000000000800003a65d55c5b13b89f6339bacbb4e6ade8019d691514235479fdb0362c340c75fac9642e5d8eded71a1c2227a805298dfd4f394d72168368f295bc7bcc37c4f7be715d120e475f58328c458e0c7a545828bd6cc5861941663dae49da55884ea96c0584edb3e72864e0dcf4fb4ecc65f6bd2fd28cd105ce55ae553e2acb510b0c1b5010001	\\x90a996eca60b0e6e85d57ba3c6c3d7784d1c9f1b0042f7761540c0aa2a7b2f5c723587a6ec65e2eb5b747da4f7e1ba81df8faf2025a072735071764ac08a800e	1680944297000000	1681549097000000	1744621097000000	1839229097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xef7989342db0ef7e276d1500a5bd86920178ba2186615f1bf5c02a286235d0cd3875e1e922ccfba2df8f8e88149190768670d0dc57323e2ade9fae6c6268a82e	1	0	\\x000000010000000000800003e104785e71b688538c6dfdb2c1e6221e6e12b70a1653cf3a77042b5bdd59d6ddd49d1516f313d73b004c2ed51f656e19183be2a67618ec28d7fd92241d857af1c76162cfe2ed598567b48b80468e56898557e9620161363c6adaaf6a74d1a813994e86e70ab8dd43fe5c432fa6f3d15fb5e5b9e2b4e9604f52aef8f8dab65ca1010001	\\x9119ec73e125cfc3d81de23d5e278bb08b268878ebb85d73370d439d5e52edafce628b7d61e11c5dd01bb47969ab70e106a214e840cccee872b30d2054809b0f	1684571297000000	1685176097000000	1748248097000000	1842856097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
196	\\xf2815a26bfe56f7e3aa8496819254f4ccccf46fabb0f4a4029bf2a18c3ff2dc441a912e608c9ac1d1cf73e083a8878042013720f4bc94e5ae2898f9afa00f772	1	0	\\x000000010000000000800003bdb6de06872fc868c99514a4c81add910342a9e9b922a8aa75d3992fa5a979d0a901b02df1fd6cd6275412ae0f88a2fdf4342b25b012a146285af7363ab93eb13cbecd98d99e25b50a0130500481faddb3118fbb8b20b2ec3736d9c69b9002a81da04586df8d7279eafb18e6c53e0c6deab399d6b76e204fe507efd53a1589ab010001	\\xb7f9a588de355062f0b729835a0de0a538946c0d6efb240cd42b1e088754868a8c10d842f43015cac015ab273ad392f7d529df853addabc71d9101a76b2d6207	1673085797000000	1673690597000000	1736762597000000	1831370597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xf26951aa42e18087461873313b3ee86a5ceb51239e39a50729493c9bdbb26b5cba571f8ead63b8bc574320b4ff218b20ea1a9924bea62c2337ecf0f1bcd1a03d	1	0	\\x000000010000000000800003a56b5befaa511996a8702aca5a9dfa54f63b69d67d97b334ed36719eaf660a5738dbde3df0cd56a44fdd2c60e4cbee95f63de0a56d66de33561aa672f6d1b139048937e00b99aba54d435fbbadbbf245a55f46d5f9924794b923bd2e10a49ca8d1ac35e5018f2fdcb1ba313099fcf3da63823deb54b3efc425d2d259da7f90ef010001	\\x58f4d26bd986ed53b4a217750346d5fa31617f5458ea2a2fdf539ed78b07116de4c74f87194f293b8784942dce666af4f048139748e83c6ce2928a9dc1f76f09	1690011797000000	1690616597000000	1753688597000000	1848296597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xf3dd86df43fb1bfde84da8ac9b9ed5e959198f7a62923a5d073a9035e2452f6f8883df41a34c9e0b3db46e7fea10baa844d20d6aa5a6b9cafcc819bb8eae39ab	1	0	\\x000000010000000000800003ac6547ea2a8941397347982adc98c07f84fc439ff0eafbb8ae5d05e9b346bee8f9872ef946f9b0c92720e6c88f23d682ce6ed57ada57cc2ff90a3ae980f253ba81a6caf25d8446e3819e6f571cb8995fd254b455d6a5ce5e7cddb6ec046260d2398216a4c0b6b33e19bf5739ca6392aa2000aa235634f330979772645b2657e7010001	\\xe39385026a232dc253cbd5c5c8c80f5e971a526eb09e025d53ad30ac8dd2a3644921db30151a8aed20ab434c15d8a61a648fe8017997162343959f537000b704	1687593797000000	1688198597000000	1751270597000000	1845878597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xf4a903f38f9a69e76d47009244674b47bbece955fea82c0599cb1a39e687edf444a18c7c9eda7882d32823ccd85b00818a1c3da40238d412259d1153e7f46714	1	0	\\x000000010000000000800003b0b7cac512293d235849991bd469e6d10c2d1935faf35c53494998d7372367ba50ddd01a6258ddd93c9fc28856b7b841d873edba1e81d03c8293e06ffb48dd2e797cb25a10e0106f570988c4638484f55b85303f70ade0a5c578b812911f3e641217b4c469f143a519b1a575f7b3134b11c12911ac0634d1df9b91c05b5f6f4f010001	\\xb5c1453412002dec92ccfd8a3a19c31a7bbf6e11fe52a7e6b3a0b8896da1237ad65a78a0fade5dc66bb516acd951df2ebd103bedb4789e00018b2799f6df3b07	1666436297000000	1667041097000000	1730113097000000	1824721097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
200	\\xf44568b7c48d66def2fb3640bb24a4a6c03c443b902ee329bfee6a7bc8fb82a97f3fc0198307ddca9096aa9790ecc3d73a577d338a8b435dfc26eb0bcd5f88b3	1	0	\\x000000010000000000800003cfadd995c517f05d13c3e9455b4696d013d4e5be62a83e09359a499ba287e177cede6a4c689e514c963ff102584e22b1aba21aa9e463bbf80fe16b5fc3352b432658d5ea8b2d4ffd6e3661aea03a2d616fe6e127dee93c49083204c01c86212a3b7400245b8cac70128b5b99ad41eaf716803a666808ee2dc2325fe56dd52461010001	\\x78bee852ba23eb2d8793210b66e8899f9cae8131672eaabece6d8c9ffb738b89db9f677596e34d5471857f0380b596d4bdc8dc829899adf742f36bf2d772300f	1689407297000000	1690012097000000	1753084097000000	1847692097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xf5d9f8d5f34776077550b7f565653cfe36221f0099362f8c52be70c996505f86aafce39eaabfbe10093555beae24b34cb89347e405e88d1e4ab45243a881ee9d	1	0	\\x000000010000000000800003d6c64e497c5fb0722cb73c2dda0ba0433dde4bbe613a90e480542f45cfece3a3e9d95d103202356667e4fce40b7f8b132532eab4bf9bbd539a82ea98c9c9ee805398b35e6aa2016d23329f08c6e5590eab3f2f2b923113a27ff824f061c7ed202f8815dfe81668bc0a3cee08f898d0d8a24d6bd129a29699d9fa4a88743d2239010001	\\x5b87100d7ae3a8d3fe40b60ce83e07470f7c9729072ba8fd36bf3b7d306c7915fb7033b74717c0f12aa7ef3b16911f1cab93db083ab510fce2e218a26ddac408	1679735297000000	1680340097000000	1743412097000000	1838020097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
202	\\xf8a90c65faf6e4b47598ac3c3b1fd7b93154a852dd173fc4007a75eff43c6c0ac6868af524ea60178e62a583577161d5d9cb2ae730c9213b40825debb771273c	1	0	\\x000000010000000000800003b1884861e1decdbb0d1068115e398033987a970012067fee856a8735fda8c90f9d573cffdcfc55b7b9de3f2a0cfdf130cf576a37b212cf003c7a092c1ef724ace06a699f0b923787fa7f3fe4656514d5ff20bebee3d4d92349be49aa82f281f6a44cda38d61d0c6f27a189c75a88bbbf2b254b374a471e5eda8fd93d26e07e9b010001	\\x5a1dc39158cab777530d6c12ccfff817411443ca96b8ad9663679363eddefe8a532895f2a701e44e05570608d6090af1988cf1343e540db2ae7337786b9ca509	1667040797000000	1667645597000000	1730717597000000	1825325597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xf931ffb899207d84bcb63dafc9a9a5920eb629b62b1bc37ba3c490fd452c5172e00c5c1ddce334ace7b932d7e1c58ca13ccdae0c13df66f07d35b419ec363b26	1	0	\\x000000010000000000800003e455083074468b399c2941d3edf7215336a6b7c2f0d382555bba41c02949bc05e607739a6ecb8453bd994f49d24290dcc8afe2bf21464bb7f7215f625995fb55a3d097463e5707942b8c61d4c0e4912ddd8cb836b7dee7697e6cca3afce0a25eb7a2b9ac5dfcb69ee8a85a1b85d1be00b9f0b2331e5d67774f4f02085366c0f7010001	\\x42d6a32d632e1f65b23b7cc49d0061b5de213da324ecb779d7d0a92fb2d8119d4c02fe9adb8de6b5cc2bf67b7e237cbcc8954b3cdb9920af1e181e452c346d0f	1667040797000000	1667645597000000	1730717597000000	1825325597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\xf98d253ceb4fc776ea134318aa5a7ccb12ecb50548c2e7a4bf587b26531bdc61329da5cb46a82cb426bf9ac0bd7a265853de0bb7c7fa8d7cec9bdc5a1a43f392	1	0	\\x000000010000000000800003c778e384c12d89c6e0b7a3fa3752b7dd24869cd1253b1e1072a39a7466ec12f6d634aa7592d06f2fb488a86737f4a2101040f2d1bcf48d7badbf75610578b107bd03f3c3908da5df5255e425052b8f6f3def5c96fd4bceb9351320fc6f2f046ddd0392699a4fd9da090e671f47a85029c41eec6bf4942096e4830b08bf4bc2ff010001	\\xe48f3bbcc0d876764f6a5c6c81e66f688beb2da9616033cea6e049e8de2256122d88d5f39ddd75c780b2dc1e385a2ecca5b8995af619b3c0818a02052385e605	1662809297000000	1663414097000000	1726486097000000	1821094097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\xf9dda5e8b9845a6b8b47ef31a015a8555c30d3e00291e511e0de8d0c6d1cd2cc84ccee5bc887dc5f9efff7b1d74688b1b523e3c50cdb92d6eb47bbf2040af736	1	0	\\x000000010000000000800003d336a8ed33343798a7d62c8bf908bc15509ee573f68fdc54236a831d233aae43e9d7e5d0ebfad4a9115b56b2919b2b79ec4d4c7f750722a64fdf713fe0ce65904b0cf0e61b2e84905139600012353f9f847ab6da27aa19b9c5e46526af170c099f30628c07d5595f9fdcb007aa0b374af18303b020e0b92d414b6d5b28de3a4d010001	\\x9b8aff5c2866f8482ba6a98aed243c07fdb855b62831d4a3a3e33cf33d4405326bf087e0187699f3fc7d89341fde844eda1909ea189116164bf5d26666e01908	1685175797000000	1685780597000000	1748852597000000	1843460597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
206	\\x015622def317fce979037b29ac1ddb9b323db22ba38ebc97d5495482848ac027327a60493a5130fb6c837c8882a0884dcbf28a6576bdde674fddd3df147fc912	1	0	\\x000000010000000000800003c11d884ced203359939706c9bd55e72ddb3440123a07c1bf0c2817893fcb3a588dbf03d79c262a65c211384f5a2d6c60ff94cff08ec72fd70b903533da37170b20b3f702fb25787601249f231840eb4361b7d3ac7e19de084a814b9019c2ba629a84a09c2cf4e769fdc34217e6dce5eb927b985ed9a6b8c1c1a73ffd40f05429010001	\\xf6073cb66d5597094718b3ce7229c13135672c862245c757427d9c53fa7d9394412c4ef4e72ad3dfe42e7b2e28d805b167d35eb598588680cfd536f2611a3604	1670667797000000	1671272597000000	1734344597000000	1828952597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
207	\\x0496867e13f65fc93fce4152c7a98f3dba1d1fcf164addbd0f3d3f8eb91bd5b1cb76b1ce67e410754cbdc41eb6c0944ef514af615bc2e47ad3193570c1a28d3e	1	0	\\x000000010000000000800003ab507f574505e39af9537e05590219b86add40a7928f351b8907e0168840e5e3e16537817bba75e8e4631f5d05fd1df1b0bb18d5e354f039f7d178219dcb40ba2aff24f3a18c3857eab7accf90ccbcf1be81e0cdfe9c56c9caa4e4b0d951280429d367aeb738fe3ef9c772c7837e0c95179bd04a87d574b002744c2f190ba509010001	\\x881acaacaf78e7a9078b1a0f212156da63e999e610ceabae36ff526c6991fa9926f5c0d2dab207f861b91ce500951ee22b6a8e22d9657b0d61e8fa09cdcfd402	1668249797000000	1668854597000000	1731926597000000	1826534597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
208	\\x0526f22ce521e7dfde0746a82e40b3d7ad64f2568d4f1bfaf1bdf3a4bb9f24563294fc9b72ca1c4dcd6f05b99247de56b399970ccdc54959cd082936be09cc40	1	0	\\x000000010000000000800003cb7ba75b9a672270db5df6e5df2ec5fbd128058c9a0c54ec2c061de208dc3ca4be103511e8d6d8b4cd2c3dec79c65b702fcf076abf779f40ea527f95dfbe3f2bf0f816d167633f7968d2ec318d9ab1a5f7c953bcecc833726f773983922b3da19f2ed94e8cec91173a84e1aa7dd1015078d91f6919e38c8dd305654845674f93010001	\\x78c4148441b7b7de2dc9bd6b2d2493e4170b68d6ed4ae7a0c1e23087d6543ce3167e36418bcb95571a67a7843cde13b1759ba5bfc3ddc76099df790039260b09	1664018297000000	1664623097000000	1727695097000000	1822303097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
209	\\x07a24ab7350138d1962c090d911cee62309203ebd04dc2ed4c34bc6b536e4f8223191520b1fa9a54f4bc0e0e5cefbf4ee782a4a324f502df49f5355681239362	1	0	\\x000000010000000000800003edbb7bcf7c11865fb370dc349e14eea3c36f3c0b86b7a0aafcb10f8fb5d3faed3fea4d6714919e1b09b49db669caf9f656367e78de9c08a47639d3607035604accdbd1f9485cd3009629ef1d3164ed066e4894c70943b6975b1c0877e234c82bac4477d3a976bbd15a9eb602bfde3b731ced932e23745319d1b13ee4a37fce67010001	\\x756f0cfd782c172e00c3cd3a615cf73f8725968ae57c2581c523bbffa0874b84679aae9bd83cb4791b9925f8e5ee6192219cd6d9059e499406ebd4e42b25300e	1677317297000000	1677922097000000	1740994097000000	1835602097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\x076aa1eaa7c7fe3d4f88a50cfcfe64455643827a474f3cd76eda6934bdfe94305df92deba27a75fe3669cbda9fe06a8527a89dd561601a90944cea6ef83fd542	1	0	\\x000000010000000000800003b06e9b8c5c434c3e14c18ed580fead997199db46f4e1346d1dc8f2e92a101ae33ae356264a312e75b461d3d9e38ece89781ddc67f2770f12360be23917960aba51c77f98a42feb2524bce294f1975d4ba464b837f8b28a163729421b6e0583ef44b9db4ad3c7d239d77ad4f7235db5ae847ddab8291b99bff972c02846bae36d010001	\\xfcf6e2544207cc4489c754a3c459317854e04180d8479a861c294d05ea7940f41bc15d6817d5cf6a9d0dd27110315519e80286aaa608660a5ca8c26840753408	1688802797000000	1689407597000000	1752479597000000	1847087597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
211	\\x0d0ac0fd1e2bfebddfbc637145c92f89f5f56a1d7bdd5ad200bd278c6406cb2be52b58713c40e2bfe7dd66bb016a24568db8113fbceb131dfb725643718ad7fc	1	0	\\x000000010000000000800003ca6633ec2591164c1c2399eb99f40aabb9cc585434ca1df379e71eaaeb57546d3cd77ade4618f97a350ce3eb54b5437259ba7c664589cbca1db2b74e34d2f7ee7c504d80ce78dfc77de5f01f4bd6c494f048c871688065b1748974a1971de0713667f8dc48236bb68df64ce774b486d6ab8fe96e46edc9aaa30d060cead34165010001	\\x1fee72d74c2cffedcef6baf92ec0d29233766822f7a71359b680359fdda9d8d49ee02c870cb87ebbfea6e274de90da48868d8903345b50c2836292d739c3760a	1662809297000000	1663414097000000	1726486097000000	1821094097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
212	\\x11c299d2d6f1369d6de33269cefccd5cc52a55cee9b7693f7fd3f0e5324be5e249908405b4d305fa3680d2b2dc97378a53758353558179d6cdfcc8c071bbac1b	1	0	\\x000000010000000000800003e125286b40e6d0d664aa06e82a906e63b6594180d730a217d96a283fb1560724da92c42d923cfe075355d082ab80a9709784a85a038ee4f4236f5cbcc2b5ee4b54425fb8e45c68bc6abb8ca55b6f764e29f1388610c0bf9a6588034d3af0504635d41ab6f05f6bad579a490f6f914fba86b41f5687cf8f9750abab2900a072c3010001	\\x21afe42a95a02e5dcf74caf371a94d6391797ff5b412a2c46df38c4f02a2523811687e5248c63d6cab161c3c198894f7b809c523373d48d657cc3979a26e4804	1674294797000000	1674899597000000	1737971597000000	1832579597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x16f691c93934018f84fc05c50ff0eae987a0e203aeb8608634c931cf335e0ac1b1794fd10b4e6e97bab284fb378ea87845703daa693ed8a03d975a498b3a3a09	1	0	\\x000000010000000000800003da446f3405cf7515a45566187de3b2f0ad17797bc3daeda02a046eb4e97d69c07eef7f37a6e03061998ba8ffcf2a6768d68324ffea3149f33dbd1c94b4d375028e48bb79ad9c1f6ab64f9806fedda0a7a547d6d25f6ba11d66b59fd991bcde4572edb22233396fd968762eda609e361beedcb57bc1ea746af5805477ae4467cf010001	\\x5dfc698446b71a7b9e7417105663693385d0744f1e97d99b0edc18f2e457bac0c7396f6307bb93765bc63d6a70f0ab6008f4ada52124232a56aa154aa476eb0e	1660391297000000	1660996097000000	1724068097000000	1818676097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x17baf4feec5533e0627abe69ffd1447157a77844e35cf305fb4611bb5a37ffba097d17a2486c5648ec00910249f000ede1427157076ae12c8f877d711c6d520f	1	0	\\x000000010000000000800003c1e549aa235d16df98f7abd3f7f48c1d40a5891a24a411e036ec362c4c190b8fcb7ffec2437a86f94bd41898f6b8f60eb4abdf5727bd362af87c99bebf24aa126eddb18bdb45da511ca0e7fd1a573283c5f7c8143f472b0ac629adbe56fab4e88e4ce5c5fd3752a0c1bb9441b6ac5ef9f7d56a5ccc1be271ef9a20a12bd4be69010001	\\xda00c4d989d725ba9d8c0df97ace366f1dd3e3c063bf707802a5b250a07451b66d39534edf9370668fe2dae9d2a35f1618f58fef6ad64972b7ee43d309224208	1667645297000000	1668250097000000	1731322097000000	1825930097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\x1ebe5336c426313148a436cf256ef16ea07dce8034d95624f05f39015c5f861e2cecf7e2c24dfc71849ac4a5a536ffb9be2adbb816bf75114ffbea0a89eea6eb	1	0	\\x000000010000000000800003ef227e300da68027cc383bfbc7a7f1e643bf78c50d56dd6598772c32ef29d656475854aef4c1bb04380b06f3f1388d87e371b1399c94e36b602bbb3701ae43f72a28d2921f6b49116c070bc92d2e0ca9122ec81ac00e7906764411c96704807777b19a72aa5f323393021ed9498ebc397ce4f5dad745b12004ef652adf1dc8d1010001	\\x69ba752bd10b0384fa15902ad3628204435265b24070be9665bd93767e96f34ea4563b5b044f56ae2b84f667d7aa27f1d6df8a2b7dbc903f01a0b8863dcc2601	1664018297000000	1664623097000000	1727695097000000	1822303097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x206e7f91949b5796e34b1a9b04c8d6f0baf971184405f3d0365c6f89314d21eda53570d212c07bde2af10b5b0905f456e26d1db8efb83782f146174936905af8	1	0	\\x000000010000000000800003b0886b611b19d1f607effa3d62b3dd14fa7b001b6b4975cb02745a2fa66bb553755a5217293b0015a3b8b9b76fc8cc8661ba03e8e7fbe0f41fb7bea426af9dc9a69d472c2b59392ecd361d368941e7a12f25093da78b39c18b8dc817803d102bed4aac018907aa726cc244bf3bc41ac5a09c5bbfe609ee16ccceb74f0a00ccc1010001	\\xcac35df5d8937bd0e10acc204b1b97f8d04c22adab2a8c959b7922157b63e49b8c42437e2f7cd255dd091c748d157f8de46342bcee496eabac3c40020639850c	1671876797000000	1672481597000000	1735553597000000	1830161597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
217	\\x22c6b8a6e481ca9dfece234f366e65d25f798f624366072e595f93846086cdc43c775f57d9ed4fe354a0ccb6a49c5c22314ae74a1253ed17e87f8da4ab384c69	1	0	\\x000000010000000000800003bd8ff23a70512001f5fffd9407b2dcfff34a4bb9149686c5fec204ecbec0122f8279e941d741cae95d54309045ddb83dde157c8ffe83dcac13aea56589a4db6fd3003535c290b43cc61c9c4e8fde04b88a619300cba35af53c4c8375cd1452a95f871423a089aa2270421c1d8082aa55d67a182754520800ba13f5322c6a33f3010001	\\xb36d1c1afda1c44ab880f14c9ac853d510e484dd2a5626999da02870a7617aa0c7291637af9ae5daa9ccd1d9459c20594153183147bedd1f5062806e93482904	1665831797000000	1666436597000000	1729508597000000	1824116597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x260e2e6ff9f9317e1f0a5be4a4ce5a631f255797c5bb5065d514de7c25a0c94e50f83c860ff46d44fcb6cea1d5304c498a664627995f59b6cd6196ed75a78960	1	0	\\x000000010000000000800003950a2de75fe739cd7fb180abcb53280e442b0f2130cd1736bd3f41b0e09c6577fe6cfc6a80004b0e335bf2a259d84002449a9037cd5471d932f5f12e18c74eda45495d56c5f5d6720a5fef3b5f5cd98e7dc538fa3645a5940559fd1b10d1d1c4f1d6d9b00cca51d67133459ee217837dc95fc669a65dd10722b86aab52b33669010001	\\x91e2ba0999bbb7bf6bbcdb90a245d9e64d001efc82399d5045dc20299e6fcb96455abbc8d717ad44644cb6bf320346a67247561d74afefb0d7bb7a80ca0ca30a	1659786797000000	1660391597000000	1723463597000000	1818071597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x2bd2471b385e4e0282cdbfe7d70e393f942cccc47f3a3e62c176e45a8a0907856146d24c0427d7d8a8b8e216db14ae108b090a0d5b6f631b7b05a9e0230a9885	1	0	\\x0000000100000000008000039e12b102c3fccfea743affc0c517776ffcf371579f3d0050263d5ac2ec773d1db0578e4fb71b64195bb8cd3b1f0bc912f99de273c52aff0688cb1aefa0ddf1d85e96263747e53bfe4c0c63d5f563b3a4a673ea157f7b374bd3cf214a01737e2ea73754c007bb16b91c12a25ec4a146bd7794f40ce360d24ddcd6b310e3972ecf010001	\\xe973f1f7e0cb6496714cd09d0b36d66349b4110197a3d40d936ab01778b00a5ec4236ebaf98759717f3cb76687e5c3415a71b0bf1c53ecf4b487aa83ef1c9303	1667040797000000	1667645597000000	1730717597000000	1825325597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\x315e9b96eaee8274889ed8e94e1f19ccf17366be3385c24674b86b730eef8ada74adb34638138b46587b211310cc5074817949d9b206feca884ee4366b41dc38	1	0	\\x000000010000000000800003ea51bce9ba254f62646ea10171cee766b6628d37de6555af50c2c9b5587d692edfda87648d65561cc270aaddfa54db7d5f343a7462b8e57ee83102044a935e26b8c28575aeaf5067ae21650ed18d86739fa7a75b75c47d69af7bac446815e61ed0a26a0184cedfac958db85470c83609be7b575ad7fad9ae6838c57d32428e41010001	\\xe7fb3b0ec42e4fb5890183a35e6546cb36fc38d73c8e728b4a1fac7d5f53fd68fe903379caa7b2d5ae6d338c76b2e4bc462e6e771a05bfd5bce77f4eb4ca4406	1660995797000000	1661600597000000	1724672597000000	1819280597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x32962e7fc8ce94388a90216265ac439aa892d6715f9bd372637e5eaff377b1488f79dccf42030028a9d592e9ac1f357303e626467adbc31773d4aeb96542de68	1	0	\\x000000010000000000800003aa34660537d200dc95c57cba00008597d648656838480892868dd91b7ae1ae4f1f981552b46178385a6328f7195a236b9345164da35a5c1a0eca1a11fe75ff86417262b7147611c8cdf709be1611c0798b596f036bc26c470fe365368caa1a22409af59f3d6bfd92d591f32288acdbea4979741a1ef40c62efbfc2c079a25e09010001	\\x6b17af8294172080730da5081903217473550177b2f5cd5ed313c3ef480104631c8d481d8b94f1ec221be44f8f85eb6190008973d34a319542c15d77840fe400	1667645297000000	1668250097000000	1731322097000000	1825930097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
222	\\x3362b71eb0cf9ccd5329f70b13c6de8b93c9fff2b306949c318ebfb0c7206ce4fc566eeba4f7127c1981c1d37a55b07288fe1adb2d06d613a4acf35efd8fe303	1	0	\\x000000010000000000800003c22a9d7afb7cc6f81e5c83e2b10cf1a699da5e0ae4262a414d4979b72caf8cdb3a65028d08703782ac47ab01fb27ad05d109b92ebb50b97167edc7ae42a340b0a67ab96f44c4cb0705530ecaaba1191ea985f81bafb18c99157f4150d43ff4cf977631cdafa05a8d00cb0d955eed3e78fdbb84a7e7f126435537a01b5697e6c1010001	\\x2bf3acb6f55f9f8451d04d64d58b8a08e5a1c9bde307d04cc4b9c0e4b98e458523957fd140079246413ce8447e4d8d05a6aaca1004f9e605158296409365090f	1677921797000000	1678526597000000	1741598597000000	1836206597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x337653792ddee588f3b1815de481d491a1b603a332ad534db7ccd93fd406997f02cf9edac85ce88af721a4e0e6a01b0f379ff78a0d70923b3c2eedd8188e9e1a	1	0	\\x000000010000000000800003c54f1df3bc60c0936ce4729ad6930c33d9e9e35b3a2690b2eb19f1db29fe8867374ee290cb39b9cb051dcdc08072d298c1664288bc0efa892b5433396b537243b0ff6b652e68cb51b24f7396c79e2efaa73b74b17ea4acb8d3dc5285fd986df8ccbba90456e584d5aabb0545d12a52ac54ba897bfd8aae1ceb56ac6c21aafd45010001	\\xbcadf1257c8ff41b8e0aa6292449ddc546646d8d99be8a12222c2281c69f41538b64dad11594c7e0e8a10a2bb47a24755ec3d8305d063a8b13d1b3eb57d2b602	1674294797000000	1674899597000000	1737971597000000	1832579597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x376a3673b0af3d17318c9b9fe24ea1a7ca1d5f465a93fad204c0ae279c0e527292848fa658c8be5f8a505b2675f1f227d7687ea0e2b93f45586dff63c1b0ffed	1	0	\\x000000010000000000800003bada73f98c03f6f9d48b1a1c02f67beeb8d28532a2d77928737c4ce5bcc3a34deb64aa27ee48843c832202738d962b01d4440d1847529eadc3e54b99d203639321a6d06dd1dad5da38bb617a8d5b6716fc1974021d563947447520a45d7af437b4c9eae275b091645ea4fdc8e59a634035cbccadc29c8bcd69ad7433ec25c6e5010001	\\xf5a7c07ca05f1eaa7519b94fc828775f7cabce167d74b3632dacb3f31c8fee07cec00550c831f95e5476ed82461b16f8a06538f179db0baf6f17c50dbe3bd105	1677921797000000	1678526597000000	1741598597000000	1836206597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x3726ec2feb1c3737721786e867dd654f8512155a1287ec040b0b11aa3addb294720657ef3dba3d013ff2cf7b5dc0265e18da2c4e765b8c4cf0f2de31f62699c5	1	0	\\x000000010000000000800003bb286c6771507bbb3ebf4aab2c2d1fada019cabaa3db92ef5d33dddb611ad5e29c346eb11d30a9f53d2bd9c7290c5fe0d08967f94ab1d8998de7de8f03199cf8df5c62c453a001dc13b6468991e598772eec1b1f7795b718f65da20e4cf2dd29b3ef27256370587de912edfdc8118bcb1a795336491a71b41575f3b4273263f7010001	\\x11beffda6b904bd230c27868881f4bbcc763058aeca52c9be8a34fbfa6faa1959eac8073776bcb480b1b2f7f3395f7f1ce7ec9bd83d64421aa634294f1d19c0b	1660391297000000	1660996097000000	1724068097000000	1818676097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x395232ddaa853bb1b47b05ab3041b10f5e5450a959a0e4fa07b688bf32d9eb9d10f8d19c8054c4ff6024f009478627e233b44bdb15a20054375b4049858dd624	1	0	\\x000000010000000000800003b72a0dbd2fc33e9a2ad6261a3ca639a7a90b7cf265d3e495f50023bfef22b4315e584cf9965972f1f45581d2eeda67623255fb999f3fb6b8cfd08c1a9cf404c05370cc062b054295a528317d26dc5bbe783a169bb87a20f01a40c6954ab4084c5941965126c46196f41748791805b9966f8b5dcf52fa206687afce102cd74be5010001	\\xe30fb0bc7272b2ac2265b91806b519d5f4180ecc0000680ca038e06af7f34e306a325f62e42dcca2dfa008dc668b6538773abc4eafd1c5aedb5fcd870af4ee0b	1665227297000000	1665832097000000	1728904097000000	1823512097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x3e1a655de918a703f63a890a814c9240d73fca3828c772df265047fdd11d7fd9c44ed20f592b1c67a36bdec59c8c96b7e979f12e9a1dc192ec4107d8c10d941e	1	0	\\x000000010000000000800003c1f5f40c9d3ff89f4d61f81ae713deb1ca0b28238aa1cfae809926932b8e01220bfd0cda04a1b55d251bbdf716b76f82bd3302a1db66d591963a70794e2b5f90547bc3274f9ecae7c797490dd05a9bc1bf4c830023253a2c95a5dada7a9f5141ba7324086e62992d474d735867ba0eedcb3ab36d27b321ae75b57b9f51d5061b010001	\\x95a0ca1c6d0253aa0a3fcee704401869dc3744c92022942fd8e8a79643dad9ec28176adc4f983d0cda28612023b09b58c2fe16a541822e4d5de739a8732da607	1671876797000000	1672481597000000	1735553597000000	1830161597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
228	\\x3fc6ba4fc63f65eb473d1fa2d70436f9c228173f763178167a26eea301972dde3516a027c28b53f31069d830a0167d3ddda4d535369ac2a5811f7f82623bfedd	1	0	\\x000000010000000000800003dc2de8470bfd01ead1fe8f220cf0003b0db418c09f91933deca9126031e6eacb736c4dd5b3177a4eabb2da07113325586009d6cfac76a1e85309547c04d4e360c17ebf1a7e34d5104c54ee292a364171508b4d0b15ac4b731c7b31dd9ffc1337cc39a41ce09059812ff29b54332288362a554381da3bb5f72cf2b46d45f9154d010001	\\xae6d549f5a5482c95367090b974865179812220d1e9aaf1a46eabbfc1abc497f045c69d9485732e644cbdc75c9f4aef52843c1a5f3dfd26318b6e17de6e0ec06	1683966797000000	1684571597000000	1747643597000000	1842251597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x3f126221fe428dbd43bd94b9030cf17f48fec3ecba137465aaea476df689f4f39a19c5933c2b9c33a884bb1ce2b203a7a1597ee5eb46ab5052079ee45671843b	1	0	\\x000000010000000000800003f80fb5ead61168759f314c55992fc8ff17e47a9e69156a53e89a3bde802ad9e8ab737e3882a6cf745cb925d894d83b8b7d69485bf9b590418d420e7d4c4d2ce450a79364fbd230be1a59b388063cfcf835d44ee2e3de7e9a76bdf2fa7667a43dadf7d53c0b2550f6c36f7bb05188872a84abba513cba5b5b7caf9b1cc261ecd1010001	\\x6e0e7713ed245cd8b30e4d8e41fa54820d6d19dfa2e451516b043103c4ab883de1280bbc3e45180c4c9828ad288ba7ea66c1a09585e97bca572171af6fa20608	1676712797000000	1677317597000000	1740389597000000	1834997597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x3fb61e053cce6de81096727f2dd14482d6d351564187a8cebb3eea6cf215a8f4e116f7bd1f3e3ddfa5d8bc14ab7c1b15e43fc8e9285726f6d080cf27c4712c17	1	0	\\x000000010000000000800003ca7d5d012d60695dacc85c3025af3d5b1e0bc20d0b6b93ccbd3946435c9da0a7a1e7328c5f3406d72cc76e3bcefed6e8e23e1df0020ad4bccb437ae461f52e13f3d043aef04b5617b5c4355bccde246adb09f7476046205d9aaa3cf0631477c79d4e3969b29a8e759e5c9b01d8698be74ea99cfe57bbb5c041c22d5600c647f7010001	\\xbf47eebd7fa20322791e8019a0c3bc420e30c497667f2b3ada93f62e6e7b13390bcff45baa6650b6284b271c1fb2c4af03c3da9cf54e91c78e1204ea31408d0f	1674899297000000	1675504097000000	1738576097000000	1833184097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x455669c94c3fbcf3f87dd67e44b5d64df0da968ef53e2ebb32fcd9d2b783db3f3b105609acdf4fd6fbcff4ab4385642ee4f9438a0b7f8b62bcd0660ea360dc85	1	0	\\x000000010000000000800003cbc08d2007eb4b012057ed26cf2102d945684bf7229b6a31a38fb31a5b7932c832d8aba10c3874746d1dc84b5e82ff130604d7c512f0a055e43308ee016c8a4b8181e04749ce25cefe36ac7e26fc87eb7ee240df9ce2cf05fde3e9e0d71130a3d49956310a6857b2ec44239c3a0d3e988463412609806e1fd5eedde217c7d969010001	\\x1cba0be51956672ae5fbdf38533ae32510cd25364ec02c650c4568a988439f172ad3263cf3027eb973cba3da0287d239b15741c893fd8c8f7ec0ced7464ff601	1679130797000000	1679735597000000	1742807597000000	1837415597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\x458a9f517820828c09529ad06d555db93d1020058b97ebb0aa7f96351c0166524ef9ab2f6b32db56f882fa13d4e3163b20a2de035a8f9b67b77b94ab6c086f3d	1	0	\\x000000010000000000800003d45079001dcee40239b87c1994611789d54a9bf510f4c7b2365e5eb6bbabcf6fceb1804266ec8fca0a6765f8c009908225a67c9146038906a37a39cf8cb56d2807ceafbf52289693a325501198d19142374ea5468c24a8adcd16eb0704bf5f948d88f0564dc8c7d242f0bc14ffbbcd85495e500d47e18c2dec09b4f3acd60029010001	\\x7b5ed391bc9ea5cbf2a6d18ced6d8c4b6c4a4c634880d1018c858294c09b7105659c5250f55e987153eb60986555d8a446b0a091809406d4dcd368541a938b07	1673690297000000	1674295097000000	1737367097000000	1831975097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x47f609f0434ea1329f5e997ebb045e5d8c869bd28621849888b62f4e63832d1d437a4516bcada7cdf17c9c0503993e6a7bc58458e3bf41a4e23f06aa5e80a8c6	1	0	\\x000000010000000000800003eb9c3e2763e4d1c7b75f7b1e5484bce3b0ead1e6284297a24fa7ea437aa6a654749d6c665b48748120b6dda43eeaabb21c4d6ec7c3a8eeca06018dae892ef069ace43dc6dd5a7d63a16f932463305479310d6ddc360a74bc240a0934c2ac6d460e7fe19a4934640f7f56c375c3557ca7c85ac040b98355c821858ebeb6b34dc9010001	\\x22c45bc3b5e2de9ba03b493a3bc15bd0c16f9519232f7da40bbefcdeaafc724988a81fd2728504082c36e0792d329ed6f431ed411012a9e65704004b47984404	1681548797000000	1682153597000000	1745225597000000	1839833597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x599ecbdb0a414cff25b3dbee74daa0d441a204e1529f3240f7b06e9835f25ce00690753a1e0eddda99081b650bb97e65fc772f296f3cf475390b28526ad5273e	1	0	\\x000000010000000000800003b0b1d80e3559619a8431b822b4107c5ef050b35ef897d3a11ea2a38112e2f63520d28efcc4953862ef0536de6bfa2a18aab6018b5adf878f3dd27ab8f28997400b79b443979ddcc3a0f61470cff1a8152ebbf2651996d2c769c10369e229b7ec896f18609909f8f7b58ed976f2d4ffc83145ac7b99da3ec68565f0f3fc7756e7010001	\\xeeeae520247b50e8de31a550eae71182af37e584d4f8202216dcdeb38251dfedcc2ade652e9e9ba2d75195837868edb443c7ba221da523ad3af0a338fdf0ca0e	1682153297000000	1682758097000000	1745830097000000	1840438097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x5a967b7d316688ef57c91cdf9dd89670692961e467e1f78da9f7751394368b3b0f3f3deac0e1427a935ac0f37da203ef84b24b2b7d1d5937f0bc82e441ae8a09	1	0	\\x000000010000000000800003a48430a891901feb538947772b2cda5b6a1b2348e992a966db6f427b743527449b638a174842ec3aa8576d4fa5259e6df71eaec01b12111ef85906c6f2e9145ce10a3f5232599e453975bdb938de33b06180ccde9fcea1f5f166c3fa9672010879eed9c6250caa2ef6cfd02d3d5f3105655b2832baaae36d61c211b35d6c6705010001	\\xa7cc092702415068a801a55293f7d8ee709b5528eb6e8db36d45c16128dda9e9e89328fe53dc1419e5c54b8b4ed50d0fe06da54957bfac0304417844234b4505	1686384797000000	1686989597000000	1750061597000000	1844669597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x5a6634491cb124935b6b1dcc38dda3bc439a92dbbb3eee4843b6baab6f9c230695ada862720b5eb4c5044e9d4d907c7354d874c059e10c5a20b767e777341d2c	1	0	\\x000000010000000000800003d4934464abf8c8426560836742fd14b4528aa440a2bcef79bed1668a05f3271bf34c5c60517569a1d354e78f20829ee9954fa739c54bca1b0dc63531fc4a084618d2d03b078bfd24c10a7b969e6466442eb00113b7fd9164ff46af81d472f01157652c1441f5ad2043a21adbb85a85d55f506bed0a14b697edde58a5e88c6d13010001	\\x27c63afdd585ca5c65f8400b34829f39c2a58696d6ed950c97b43fc8da69a4d77e1503d6de99c086df546a13d2b6bae8e0d8db0a18011407f3d8490c53cb7707	1683362297000000	1683967097000000	1747039097000000	1841647097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x5cca485863132176152bd16b916967aaabd5d3ecb8dcc077daf70fea0d26dd5594735dc721dedabedfea4c539b528b557d88bcf0602d52248c3e7bb99e000429	1	0	\\x000000010000000000800003c0f62a78c3e1c8e091f907e3b7fe12fb98d1d8114e57c3de71acccd03f3dccfe234022d32bbe741bd4ef4293d5b18d65adfc38cb7715acbdc40b9aef7fdc387bcefc119f2f74b2d95b7f8931b009be87adc94009cdc14d3e98363551648c6a5fd90d643d3cbca1d34886120807b4b80ecff990f4f3ba39c8cb2ee470cb144dad010001	\\x20ca2fc486d660b9fa64627efc01b0fbf757686cafae7b53a10d8e8644820e4c519e7a83205fd88b567b2b784a0c214b4fdb48cdc7e466dca270b8407d7f1b08	1660995797000000	1661600597000000	1724672597000000	1819280597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
238	\\x5d1e883583ef9f695198e4f02f72231a167aadfeb89cd9dd369302a55d49e9d88415a912b8e3af8b38de329f298b07af7289cc1f358ace3dea835b2747b75b8d	1	0	\\x000000010000000000800003d69070b42231f5ae9acd5c9264dedb527109f92a8ba365ceb4c1bc28f15fb93f9ebcdd944217e0be3d138564907f1369e96439f0cac544e2eca22b09211bf274059ef28777004105f1cf402a4a8ccb95075bba93172214e4741ca420c89e0717c9ad42551a6c5ae2deef453a312dccfbda1a472707526619d72a774abdbbe313010001	\\x80e5448545d5c99aad3d8977ac63c5a0b3066e47e963af8de1f989013fce246f123ae8010602732142266c6214073267748569a66f651a2eaa784f5d39f41906	1668249797000000	1668854597000000	1731926597000000	1826534597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x5e6ea77ab748b5e882c30710bd96755f4fc1daf4d496158211a466b4b8bc829560e850bf2d952c6cce7592ef91c20ce02b15ff650db2780f709e62ac5512baef	1	0	\\x0000000100000000008000039c0876d135580424aac93408f147a3e08fae537fce039be50fecf9f579ebb8f76cfec50b12c4364e7f4fec4e2cf93ae263b3b537e212b184878a4a22d0dd77ebff5627a8baf1efa6a81c8e33ff0e3df86c4e398cb101f6d5177c982febb6a38359a3daf7157df503e709cd253a791ddc36afe31141720ce13414d73b13c0477b010001	\\x930e8200546e6944e28aeb11b3736ea9083aa69048539126c6e866993270887de45d2f1d8aba3ec9ef7c08b7ba9dd951fe416075983bb251151e30ebeb728002	1676712797000000	1677317597000000	1740389597000000	1834997597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
240	\\x5e8a7819489d9bcda156f51c180f14d1c2e4330947316e8937eb460d0c852b9d1a8ad354e11fd4a9411dea7b1dc69d1fb46b7bcd977fbfb72ed162b21c7fae6f	1	0	\\x000000010000000000800003bce98ec1d6f94d4d313e5ef1385d360017774a5916df8822bccf3fd6752bbc3bd6812c947380d18440637b22c14f5517a3cc400f502f999c77585093d39987a8fd5a84fc393a2e06e443e4bdc1707295c74e5e2787000f7df84e95b4b690860c1f79d760df5927a7cc168c1eea265dc74ab1ac353edda617fe2af142a40d0989010001	\\x01b5b61a2b2af86fc9f4de705a6915a7b44216694a93509e2d496d10f081245113300735096db9aa37884ca1197624640eefb36b4386047bf57467fa4b2f8009	1680944297000000	1681549097000000	1744621097000000	1839229097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
241	\\x5fea37f21b4061df566d5d80a8d677c3a1b04b9ba4e2d0646db4f783433553bad8d2810e0455178506d7b1fc45f113b2f4e3310184ea1b5622489edc74cc2cb5	1	0	\\x000000010000000000800003d9f80ef426fa5725ee32b89e9780a7fa95dc006281e3f9b943576fe7b72a717c7ad4b351c5529ae3f7e613953a45b9d054505ad5391de1eaadcc01a0b637694312871807b5766ac346c01bb07a3ba0f117854c3be99f320c21cdb130a4976c81ab3d0e8729aa72bbd61d5af32cbae2116e295d14e403593e220a01c8f841f1b9010001	\\x8131dbe0740701285ce67288fc905a3ca6d8abf075449403dea8a9678da51e668ac9d6d3d02da5a470f7a676cf4a4ae1d4b95e65ffa2fdf73027e93706fdb80e	1686989297000000	1687594097000000	1750666097000000	1845274097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x64d642412f2228dd8f939eae6c97b2483b8fa41663ab6cd8efa89db85e3ef64cbe3d4e31177a4531787df243e2ea03b00f5b393cb8ad7b56f5adfe7f086b8e64	1	0	\\x000000010000000000800003d9af16a1daa108b6f57d5361643b57f95d309b114bf8d0d63733a8f24c6da2cd76bf1b7aa9d2f855a88c6ddc6cef63de77fb0e399f322e5da57549082babd4f68d822141bca7ed5fa9ce5dba63660848fb0cf9e770b37faecc4572e743177453cb7b162c262d6ef04ddf129bcffd02e589211d3aba6554ed1fc68540d10fb1e7010001	\\xdbec6bd5f946862a34403b74674937f98026e809d7014deb6dc02a8b0c2647ba1bbcbf5064df434efc4ffd0a748e3a158e3144d99ace645a9eeb8d8c70e09404	1669458797000000	1670063597000000	1733135597000000	1827743597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x65b6363fe3075e77a990f96cc2552e696bf46273208a5d4fdb9f6e2d68d80b86a2239a6a7a9c6b8396884ef2ea1c480a09d132e06af68f6fda2c87570fbe4597	1	0	\\x000000010000000000800003ddf7bbe3cf85a934cb4d3486774289b6e16202a03392d40965b47c23e1c83d46eec9367d90a237183c6c90fc9ea0d1d2cd80dbf33ad542a208f23a53cc6f75f220c864a4db02c1fa8e2298bf6193ee707fc854d7d3423d2c43bb3ee9b51e850ea88c68e2bcabc3caa937e65db66ce3aefab9eb62d29336efabc9e61b5763aabf010001	\\x9c9882782e0817747010ff78e04b4e34a2de625365fb2dc8b5cd3f2bf79db4015bcaba60a1eb7187409182375c67d7bbaa1c943d0aaaff128d1851f7f166b90b	1680339797000000	1680944597000000	1744016597000000	1838624597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x66ae7a54e1a0ea54792b6961a624bfe79e71b432e676f25a09b43c69dcc91c540cec329b21ca5504652a53a26de33450cf907b3ca45bd079c2342245478e10f1	1	0	\\x000000010000000000800003b0a182c5064d5a23be0a583ff6d154d61b88bf65d5a982db35ae0c8dbb27934d9e186d4d435e3a73752dedc782ea51d38c6769c45a81ec498733dbf15e12902c31055d9f38cceb40a6d8034af1ee2f7a459e42c4428cadad20958f1c562ca60eb6f25c6be487de5507474acc2c1cea746879c7fcdc4f00cc712698758f4e1815010001	\\x08a1a550b3b5c307f49290eb37948e95c474d6e34c2fa62e07989e519c27ce6cbc740a1160acd1619e98218c07f335f222d67cb04b2b5ff1debdbcf4826c560e	1671876797000000	1672481597000000	1735553597000000	1830161597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x6cf689ffe7e7baa629de8d4b0341245be0b502a23e4d508b2f9aa81a27eb177705e4b0f5543fbafe37887a137ec0a4ca1c1036ce8cc0697a543bcb7819d34a50	1	0	\\x000000010000000000800003af31ececcb8a4112272fe267184b78fce42bcb893e200ef3726903567f79dc7e1a9b14bb9609fc053cacf5f79345627cd7864bfaf5e575eefd54d052fd8893adf80ddc7f9838f974577ae6d38268a49a4b806e58244a98c908629c9d109d8745f3aad831f91a2b4b218b7e6af3fb5c5c8e084f7b3fe41f19aeb1b5a2ed427b43010001	\\xf9ce1eeb97e3d8a6b669379ff7c5cfe13adc07eeb54b074b10f78893fbbefb3a2e9d6746ab7d688d64f97cfd1bf7edb5c9b338405f59e0dcd7257b44a6ed1a0b	1679130797000000	1679735597000000	1742807597000000	1837415597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
246	\\x6d76632da09eeedbea69a7616424b4d35084b9ca6262c56a6e1e57140b6b08dfa7bc2e0dc02ca7adbd6559b726e286566ba06aca65b3b6d869641decd289b0cc	1	0	\\x000000010000000000800003dbdefd737e96a58557da4ecd47fb15eafb2a018a77d176980249b23bff4c227ebc75d6bb3de18037e46abcb6612be49c69ffdf35d97b01c39aab54995239353e0bb0637e17887d669d67f9fb0bc61bd98cdf3c81e41d27f9e4f000be461e2bf4e4cc6fdb31bcb1ebdc8a11f4c3c11dc322968d3a491da6996c097a5e37e0d889010001	\\xe5d7ef58fd0d801524f41e9ec8956b6798900c630b4bbb009fc176be60f69449d7f2d218817df53d119b1c55a0b46c6a4cecb3d5db015c37996a867403437e04	1668854297000000	1669459097000000	1732531097000000	1827139097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x71a6952ccb07690b8e5dacbe4e42139c93f58d52ac8f8cb6fa65aca58698de6a68f1885f1897951b7a1a22a833f5e42010bd4a59bef48b4a1305c29d3862bfb0	1	0	\\x000000010000000000800003e7ce1cb3b103ee8f188b8093f45855096de7ea4a7cf806cc531e082333777739c86646bd6a642779044f57b04607435cfd8afbeb635bf5361717fb718b4071ca7aa717aa676d5d91ef4e781403fa7cecfc75440d72118f50e6f22fc8352bd85f2657206792c24c387e9da82d42235d5b72a9c2a09625a24561fceb65d5fd0e89010001	\\x762678fd714749947a1e0fe3265c4bb560d1a470a0612e08851d174b704984ef3b138604eb32e8cd39d4df8b1987c9d9bbe0a2d541cb92ef15281b6cc39ac809	1660391297000000	1660996097000000	1724068097000000	1818676097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x71c2da5fe41ce3aaa7b296c1a8765738035000ac7024b7105319c9bb263bef3daecbd4d3dea8c2c98d362f1e30fcc57632119d6e46c541912e916018b171e142	1	0	\\x000000010000000000800003aa5ec023beceeedbcf7fa30978bd04c211fd26c5dd5ebdc7c7baf2010556a8765b9fee515725cae6a93396795af1cdedc6425257fe02c55479205141517fca3682dbb7470e23a42a7a971d16e50ff73d661ad6ed4fea034d520e1d150f354db18e77f8c5cfb1a87a630f2a27679d543f4d03c4f5a53703238b2e6f28923d583d010001	\\xbc20c9dd083fcfcbe06c6d31fb20510d854ce5cc1b4a1225e94c9174dae5aec938c281554b8f0990ec872939748ab758983f336ec5ecc5ed413eb94e2f8b0801	1680944297000000	1681549097000000	1744621097000000	1839229097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x74de714de1a8a9a8b310dff4b2f23b88a7ab80cc94c4cffdfb5f08522b4b7188d42c37006e7565838599339eddfd46a6c4b88decc3c2c743a7d636af496535d8	1	0	\\x000000010000000000800003cda4c68b9d7eca7076b990eda9ba9495b3e0afc59a6346b3f10faa0c494b7e1c56ddd95e5e99f62e3e1207102ad4c71b4732a5364ce33106659e7b4563518e38e467107169b1c7490051cc40cbe1f233dc50784b126425bc3cc0a9a6955dffcd936da12e3ec1a2cbac70d1de6ca7a6aa3580a8898846a91b6d1cd542bcee05c1010001	\\x50baf7ebfdf3add71e9d0a4519ae2e2fc14f42fae009b128409fc387f92cfc57e7835c2fae8f886bf37b3fe2a66207cd007e10f643e8671412051e6ef3734f0c	1686989297000000	1687594097000000	1750666097000000	1845274097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x74ee0044892a26d3d011f4f8dbf44c663a14c0f0cc0268eed2a7334cee783632047297ec7acc8286e40d22035a72bfcf169bfcf0726ae5d33cbdeff724d9b23e	1	0	\\x000000010000000000800003b1eb9916599715d1befccdb49192f7073cdd2cf0cb2d748e96657819a711c887ca582a5be7bae96fe1181d6fdb3c22ad8230cc8bbd67eb5faff5a06433e0ac0ede034c256a4a875d25f67081b857a897977e935828210e0a51f754b671fd1efd9fcc85e898c22b2408e8e3ecf99f3c736677c08cb6935c50c744fa99544bc555010001	\\x3fad09b08b3fda79e4a5534fd3df25bd9d1184bed8ab91e69d048c4f402894d819733685d389d8842bac08dc4106ba71e252d36d6492ecce5dc1313c68dcff02	1691220797000000	1691825597000000	1754897597000000	1849505597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x76fa7ae3e9d53c5a283dd262425174d3d217b82bfc89d9f37a8716343f840d23ab8abf641ed88603b3a17c060e23efe5e5409f699853022014375e7e2bcfd18a	1	0	\\x000000010000000000800003a61f95ea5026c86470dd3412d18e119250f9fc3de7a1b030375161277f24b7395f902c402ff2ec352f6704c2f76d23f6c19b6607d2c58a7336f525ebcd489ee6d4d52a4e842e21e2dc67ab0d34c26e30756dcb2da374fec8ac4d18a41fd7349927edf352ce081e74cc18759b4c7b34d76171c8c3723d9bd66497203ee12becc3010001	\\xf34b7ef207bc238c0d1110578b7a335d1965411e4d42a61a8d8e2c2ca4a9d9590bacd61eae0705a5cae4869b3b615546e646c7d3f8d2e2cc955db80cafd67e08	1691220797000000	1691825597000000	1754897597000000	1849505597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x786a5f7e3c5551ec3cc0c7711d03996abe298f82e6a1c187f2a20cfac802d009379188bd564e6f1af6a142035bcc625c50e86b78624968a70077f8f4e51f1674	1	0	\\x000000010000000000800003ec58bbffba7c637917e59e76e2f1893fd95108de433d07e8565ec17b6813af70d7e18dc6974e11541245e731400c574770b7afaed4c9d7d5e0b943906e38acab8c0741f52fceb483687a2125ba84b82e35e562c0a71f479cc8624f31c21f4839edb875622ed9fb85535465c88461ed44d1c6d2fb429b19f27a828428624cebd3010001	\\x900b6f088bb84dfe79f61ef1ccb289921edf062396787cc40facfebca6ce63c5e85d321249c4539fb8cf6c7f0a3365cad567d324447f98a72298224c2f98b204	1673085797000000	1673690597000000	1736762597000000	1831370597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x7852f1539322c9c39e691deee6ff70364d44ae0bf5f111701599c3069bcf01925da800747d02e6e29130fe4fb0fc3da3301241c2608218760dfdf920fa33a9ca	1	0	\\x000000010000000000800003b9f68b3d7a0d5d60b00967d8d8b8ccdbd9f0468736ec30808127b9a08419c0ae6f32eee540abd6412992fc7159fccc5bd660da48cc36689384cba32502857dca0aa4a6d58eba4fe2f0f24448329cf8ca991ec257747f66f2b2db5845a14d3108238a3d90c9ae26f31046f5bc4d11c05fb87fa819979b35e26fb3ce869bcacfd7010001	\\x01f0f971143450d5d7a20cbca6eca2876482011dca32f389cd7208acfed6acbe45754794ac74377c32517760be6eef3a3870b633660133c8f90b85fded414f00	1662204797000000	1662809597000000	1725881597000000	1820489597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
254	\\x7ac2ab2e425448bcd07e3c8819ad0463b8aee72c4fbd7f166313651930c5981ccea013a64c06a5305fcdd3fe823d0dc9bbc904eddf17a6a7128a023ffe829d2e	1	0	\\x000000010000000000800003a923a3d65a3d879fd70a092659da340f66ca1f067440304eb2817847e40bdbb573408b13164a23208f46d72eece33fe47fdf36805bc0f3c28e1156f433d9ac171e3eef04414635f5a8a91613c6b7930acca76eb4aadd4426d1808ea92222add1149cdafbeb8ece8e8e4dbb82b3bb5e94cce167d55e7e251471c99d63dddbe0a1010001	\\x2ca4415679c9f4dbef564de2f0964dd0e826903d155adc7caefc9367924bc6ac26e95eda6c5191c6f1ee3df3f7b224ddf84bcc02f4faf3dbdc636b5dba36fc01	1668854297000000	1669459097000000	1732531097000000	1827139097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x7a5ec124ec64f44f16a263302cc502f2c463261e94abe4e9f90493bd9083c9d57a993ecf3856b27861909702287123970e4ef4ee370f7c04e3f1bcb717566e44	1	0	\\x000000010000000000800003c39df89a33ce9ddfe0981109e666097b969ca7d27683e32105098ed621ba2fd52892da1aea5539253e24c73e380d6760a027a7c0de12f86c3505dc225db58cecc90fd9045fc80592c3b7865732bb364514acd1dc853df4045107771c2cac09e58e473e1a6510b3e7304f5a775a55e36da469a5d3b95da7b44aa49d5ea818204b010001	\\x4a4734250e08f545a121f3d02fb37093dfa857f9b1ce46456127d0f9e5ca831b3d9c7299398a61f683cb6650ce9d00a400dc727c22d9c16e18874e044a8aac06	1667645297000000	1668250097000000	1731322097000000	1825930097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
256	\\x7f367d523a9f88ce00a4ef8677a532461fe36e82c5f1b18be7cf8ea73efd0d37cc9d9fba80f2aab9974100328c262223bceb9d81863132573de052b852425e8a	1	0	\\x000000010000000000800003c9afc717d0f7d90265d2e1ee6e969dac8f53ee30fb80dc6bb714ea265424c9e2ec73dfc3d99fdae3b0546efcd042d09796eb172766ccf9c114df43cc6e1588c9660dc7bb7541faa3c402146e362ee0acf2bf5a1f49909da4c7cabed6e862845f3a6c25fa9ad43d63fe3e32898498ac9dac596ff0ba31cbfc2db77c9571341599010001	\\x49686a7bb80ff65aa5cc5576a937a43839819063df9691e79523ccc8f1f103e24b3bce1133a704452d1b0853e579a28416d4828e7b4f2619fa6f2de1c6972f0a	1662204797000000	1662809597000000	1725881597000000	1820489597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x82f695639e91e2dec0075ca927bfec57bae7fb2517fb783667566ec79847dd75669597901c011f6436c6c782f94aa583d1715796b3b1ad435d4e65efbef62bc7	1	0	\\x000000010000000000800003aa05e0174890a5f246eb910bd0d224f4e56b666a879550d555b1e297f714326aa698bc451c6264f7ab0611032bc706c73c0af06e509baa957ba7d00985af505b29eea0a03e49c36a456d38b295c3368cb049d23cf801ab19256d01247510d0ed34e03509d1615342e38058947d661e51c7dba183602d86b2f3098f0300085829010001	\\xded0ad1d2eb090f05ec122abfd905dee5b0b840eedc6682560148f71f7ca58dc81aaf54c13c70913e88c6b1c27039d072c10e6d8a1ae1d67ba369828930ee403	1680944297000000	1681549097000000	1744621097000000	1839229097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
258	\\x853e2d1b3b2fad4014717e1713df4eac13a76d70ff2dfcc262b1c8a1fd5e59f22cfc7f4ec7e10ce480e739eee16eb1490bc32f486f750f73c157226f83f79db0	1	0	\\x000000010000000000800003b9525281631168fff95ee051e6bca4687ecb9f1b7b8e1ce4cee15c8ba9a3dbfdcf788d4b817385a90f5c589c401e44cc3b315d7e549ce52c1ed450518c356a57ae9e0e5c8e0d8af4f07497dffeef1bd61d324ef81181fbe212849f5391354fc9b699bad89d060e2aa242365777e9cec1ce2eb326691c2639cd9b5e5b751cb083010001	\\x8fa7cdb8a77fa8530a18e9685e4ec024c1e50a1d5850de1582b7d69943711bd4c0216146fdf81210dd87c9e8638269db4da7f5378f6e43eff2d0d081a68de305	1662809297000000	1663414097000000	1726486097000000	1821094097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
259	\\x8646a6c3c2b799c60c01a81e08e34b483af1c1fc45c8cccdef9e4652815876d19c2616854d61949636d54ec48584e9758c4004d18ea11d4ef0a41c00b509d772	1	0	\\x000000010000000000800003b4d651b63df287018e7cdfcf2837f99172f3d10f8f590b46b9dbf685ffbf7c925f21d264cc8eb29df319e442a79836054a088624640fa3a6312f45203970d9fe96f7523ee8d66427784731e9a7710fe128c567004c5e81254f599fff206e654d4222f6f08877b8ea65e2df9e1d5b71cafe1de3450478c7d642eda6aeaf2f8efd010001	\\xeaafce5ac0a106a0679fa198402547e30999e4614531fc6f65102b1c1233ee86bfcfd22b4d0c5c5f5703881f5c79ad956465b6e6571a8c97a3fdf96b872b9308	1671272297000000	1671877097000000	1734949097000000	1829557097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x884273a0049fc890ed70ca2e9cbec2241b7154c363e25418d7c1b3c4502f3c1e1cb1237d19bed0cc9abd42acd999719e79418f8405829ee193f3bc8d38261620	1	0	\\x000000010000000000800003e0ccd2bd8706fbfdab571080049150a5d1a788932fb9a05f72a934150f43146f29fe661e145e48e301e1d52ccd9f3ae4909f5cc8333b86dc6388b7edaa564f546b7844d153bd91bef823104acb33675fc319b12632d989c698699650bdf66f47078bf124921b4a5756457e843c5b2bd9daaac8b1363606bd2e032b24fdc9b4cd010001	\\x1efcb6112498abd9571d58c3c8addaac72337e6883557009a2ebde277be0bcb75f385818d180b0cd60dd27de51b5ebffe4dde224c8a92dd21afdb1b551a54002	1690011797000000	1690616597000000	1753688597000000	1848296597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x8a52d98822a3ac9be524ff8ce2fac9ac20275a3cb842ed92291a0ba12cdf6519d22e8b09505f545954c9e4fda5fbad33520d910808f2e3663d08f87a30c46a4e	1	0	\\x000000010000000000800003c6578f0caa3a6340751585c66b746978d8d2a499d4f22570c0c5e4be6ce5bf9129f118fe62fe9e1917ed8128cbb3df530b6fb0f0c558d1b4554640089ec37d103b789ae9c61cf9453c43b7f7dcdca4b6640f605a068bf42f4d14cc611a47687a23155a4fbca6297e8ace3f621ecfc4645ff2bd106aacf558523369f6e4f26115010001	\\x835665c67bed5a7e4966ec78cbdb2ad4a0d94978b0659b970f6f305f833bb750654d68881c8eed3e7cbf0ad9921930a88e406d6fef6f23158ea7a9ba60429804	1668249797000000	1668854597000000	1731926597000000	1826534597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x8c0ec8a389bf9bff2f5573f5b13e3dd405ebe849491ada7eb746073aa807e500e3110aa1620a392b6c3311085cd72550d9830331eba44f3d8ef50ef49b7f17b5	1	0	\\x000000010000000000800003aad5601163b91e2b4b5da6ed3a2a06a243975e33f8dfd18825282fb66f7cfc62e56522d81a5839f3ed60aa3e0638749c5f3268a2d16d6bc67481c88d4f1756356ac7c2d4480ee6bbf183e0339aa7e83888fba5398928df231c987aa160d07563c89b56130374a4488754642ec73d2ada178b7936bc8b019ebb50ec147081b609010001	\\x3d12f13d86751d03fbcca68158d48e79ff01b0333cb3e77aad9a2d757a9a96d5338bd760452a3d83c0eef3315ae56aceb7e6555f6b836b92b8356461e75fdd05	1683966797000000	1684571597000000	1747643597000000	1842251597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
263	\\x907e9a4bd91837d2e264748afbb3faa82f167f0d58cf1fe4d3231ef42740b45bca1ae5c915ca5e7643360d19d1fb3283e4d03c1bdf1e0bccbe3b8e1f8772125e	1	0	\\x000000010000000000800003d2af3dca743c7f31e8792e66c9ee1f3d2fdf9195efb816eefff91180f1ad279aedb944c837972addb6499569f3241a357f023e0595131fee3390677be44ee3a7d587bab24b1886375491d670d4c87d5f78f3a19d33a36ac23f2c21713174c73f7e4f6107fa0b9286519f4e6f57f3e56298a37a6332ff3f4741273b1a5ca89413010001	\\xa760df6f5249e632a92dc836ee87f97f9599e14e9d810337c0093950ff9c28f72550fc4e4467b0b1be1559ade4f13039a9ea6271d05100eef89ddd426c89e401	1676712797000000	1677317597000000	1740389597000000	1834997597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
264	\\x905a344df7423f78b4b10148f0222a74aed5df620c66eea9356d1e89a8a274158128a80db834dd15acf9c5f77839efdf38203cd4bdef74ceafab9877db4b5fcb	1	0	\\x000000010000000000800003aa6af4d499c1469e8c90bc2db5a7fb715b1713421b62cdb73d37b9d9ef2619195de32f7f2c932b93e8c6bff57bb21d6e5822a90092620ccf1834139f8bfa8eda2b03fdd2e2b64a5a9f41ab30fa9a602370e1752440e068d7e8bcabc99d05228bda5892fa95e4dc7507c8c1283102937d3abbe92e53c61acda0756e12d45a64a7010001	\\x1a83a4d83ff5a71ccc4e42ffc90036384d37bac84192d2eaa9d3c4c755daddc9b0651003e043d24840edd1e13848b6577e97416522b9d1dfdb35eb6c9072a60e	1673690297000000	1674295097000000	1737367097000000	1831975097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
265	\\x948aff00057b57add2070591d0fe468b878ceae74a80082df96437ec20d825a14ea7cff31e2af2dd56e795ba7abbe87fa13934eddac1790d85d9776e859c78c4	1	0	\\x000000010000000000800003957a6da969fd38679490294f10f5fb8e9bf15a2465505333ea7d2e3a7e13ca3a7a78c981f6341aa6643d390649bf7da98b09aaeb03bb5301d3f23fc08ef60d66c0e1c4764cd4eaba0183dfa65df431828a9fc59c41b1988a4849b478724514cbcd84daad2d32436ec336d9bd9289305dfef5842474acb2132b1cc25e2b73d0bd010001	\\x8d435c2bb86f7b9e705f23227f3f4cc71595143c4cf71efed7e1e6b7878b0b2dbe65c978c141ddb8e35162b359c3f5caba25861256af7ce77743bba4e3a80009	1679130797000000	1679735597000000	1742807597000000	1837415597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x96663f75f9c21e5a2dc89125b926c5952581dfd744b3025b5ef9159e7af6643275680f99a3ab556493aa8b1304f23d8eb5fa407b421d60952b9982d713358b91	1	0	\\x000000010000000000800003b748a135ccdd8beef97fb54f0180588124a319f43d6bc2a8557d1a51387a410b483e181aa6aaa6260ab052279958cd7cef72680065eae8e21582df4062edf0a75fcee4f9e76d37fba5cdf9c83402418622d2f23771694d12e09174a90e2e39b1f3a15bc0668293b19bce5460cdcc3ee899f88d78d4a728c0ac107c4bed18bb55010001	\\xb6a5be506dde532a70da4d7c8870f838e35e83e1b491a0e754c0edbc7f2f21d544a94719d9ff9e64e35efe0737f31127b48e658f1986eedca85ed075801d560a	1672481297000000	1673086097000000	1736158097000000	1830766097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x9716e5f88d82fdbb1198ccb32be47d0b2b2beca527bfcec9f54252f73238faad2f8033d630640bec93cbaedb0cd3c20749808b028dde3e5fc4e14d3163db06bb	1	0	\\x000000010000000000800003da26ad2d4f095a8446f5cd75eb7f469289bf636ee319b87932fdbca2563b12afdc9e4a0ceadb78bea1058de02452d16e40e06d775d63f669ecb39df7df079a91119d4c622fa3ee642635fc5ab8bbb9b94c83a3870585ffaae5645fb86d279b2363daf6fd8e197b02662cbd27a4543abfbc5057cf5876ce85784540bd87b7199d010001	\\x0d2a6d92ee47a0ca82b75521639068d5d480124b0bad5bd4c651420c2f4da5ac26a413ee2cae184254739a8dec373d0b8f03ff279c1ff24c1d04ea8f025c5404	1668854297000000	1669459097000000	1732531097000000	1827139097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x998a7741378e8920012aad7ff674f0c8889ac80ca96aba94aa32f65c0fb1d17bc154fd4d31b4a8eae7419c93ae136f0860c65c7f9e6e63400f0d3d6989a7130c	1	0	\\x000000010000000000800003dc5aaa9e2f61f1e28735d553ab51ae722918621fb835d2ac263823a1392246ed4ab6be05f0230277c758fdea3dc2cb007c61eb6e8534a644bec52d870d1fedc79ae7103f77d4c2e4c86259b377f70e822527d29b2b9b5ed1fef569f645986a1e54d0656cfb3678cdcca3c88d67db7ab77927511ba7fbee30029d330d14e7ea83010001	\\xdaa13862dc70dcd2678f587c7fdd48f84bd30c39a322c2b8a5879479454b9808ef2b9bfc5c8a9dc179f2961a78e184bd7cc9d5537a4ef22033161dfb61044b09	1685780297000000	1686385097000000	1749457097000000	1844065097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
269	\\x9b8e91b50771f581f5259d6d0eb4d83e2b37b287c13800beeff8fc23cd49acdc92fc8d394018353034b0b4d534c8379d176879937d4f659f899e5be838eb0f30	1	0	\\x000000010000000000800003981c6ea53fd7e41ffbdc0d7da912128dcfd0209ac5442322789bfad0e29009b7a58b642a27b58135471c1b7ee1f3b3b18424df2fef168db160c37a3cf1d03334de42b7ed8aa741ca0ecb516eca910151a174a8f4103a92e44d842cadbc4366c943ea1cf49f86a0e1d296a5de3779b5cb672006b3b45c3b941f73353759f5d225010001	\\x00783089c6f992f5425876032d0baaaffb1fe0d33d823b2daa9b43ec38e917caefd36e50d7bb045e2ffbe8635b27ebecda375963a009830002ea7ae4ca716503	1683362297000000	1683967097000000	1747039097000000	1841647097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x9c0a7788d895e24602f47e8ffaca1a6f63ca08a689354fe4c7a9e48897295e0816e306f07689364520b9312c8fd348d8ac333e8c430b893d78cdd58b0beb7317	1	0	\\x000000010000000000800003ba80f244e7facd81ffa81a57c5a49cd2e1593ccee681506eec0ef8615a63c8199de0a4eb81770489166f80a4a5d5b8c6010d2a212966b889d2fb7c0a2a13a518cbb7f3f7cd98c31da625aaca32ddfaddf3824f3ae41f410397896997ca7cf4ce62f8e8031d2808bfe21b1be2858b81a771d53d988218f518ea838a8c27f754dd010001	\\x7c63f612e0895669c8cfd458dc3125a8c231d031fab2ea146cfd6612d535561562263f7c1a5fab5cb14420fc7e784ffe49d9831586567ffdc5e5f19cb36f9c05	1664622797000000	1665227597000000	1728299597000000	1822907597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x9c5abb3a0fb98f892a5d2381015974c1a9364923e72ea19d8685eaa7e230c99b1c5b392253164ca8c178a34897d0eee35d7af6597e2340405f51da30872bf51d	1	0	\\x000000010000000000800003b6718287047a18c10adc932e1ba4de138262247a8b6bdd68ed5ab7ce9d56444d8e589879497ab157177f70aa93a9c950da422e6fbcf5075b1376355e2c18dc358e768740f705bf1779e2d792317f727ece759d3ba31e98c2abf68866139330174aef4df1e820ef3329eda6929a22a53aff97e7e1e6b48087bfecbb371e3c27df010001	\\x5f4945378896fb972c39fef0b048589ff4a245e7d7979b17fe907986cc9766df082db6626c5f929b8a3e3678e6fd4bdf5900f4d861304628bb2209a56ae56809	1673690297000000	1674295097000000	1737367097000000	1831975097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\xa0f656eb8ddc254e114ef02cec0e128ca9d90d86c125795166e25860e41804c2e5ef2c81b2ed4af0630716948a69c926e3374a001553e6c7324b881c47a92d13	1	0	\\x000000010000000000800003dc4e35d779dfa3271e06f9fe162771e10ec6a7b8d89bc96e735f7a598613d6c7a0753fb2d0f2a565fb2338d1f580c7f5bc736da708f05a0c52a15528878c241cca55e25a08adbedf6e7159adacfb3cfec3e4d3c36102ab2d7182ffc0665db91df97f291287e41b1568d304536818902648635a3a0fa99c8eee305adf1904ca1f010001	\\xc6139e0cf9719fde763c48006e9886924a9ef14a4d4224e63783f54cb6a928ea5eb8163a06b7339971dfa3ce838466fbc2da185da73cf92fa84696033ede9805	1681548797000000	1682153597000000	1745225597000000	1839833597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
273	\\xa22284ef418036ca70501212d9d659f7675948f128aa7544646580cf23831ba8692dcf42c040345d2cf04fa61831f3525d9cd1eba323727a6b66b0eb0547d673	1	0	\\x000000010000000000800003a63d1f4a6ebd5bd4c4c1e96609dd27a66caa7af6db93408d6a86838a20d061b7f47e96c7ec37a5c8933587cfa907c49a5576fcf1a9dee0c2eea58217a78f1e1bc003de54cbd06f6744f44b355e502cb158c62e99e201a1c273ba473cfe16c9c688c144204d4e2365935dbed420b71811f458308578ed96fb20aff443844496c9010001	\\x2f1844a67910bdb5d1263f1853a40ca534ad5fae82d63c5f1b24f12c2249a7a0ce479ee42763f1e89ce0304e8ae62ef5dfe7513cc436bb8407e9cf7b1f0a7402	1667645297000000	1668250097000000	1731322097000000	1825930097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\xa4d27828285c36951b90da9bd90022ffd240e41ce2a71527145868567eceb683ec5a38942f18ea97bc121599cf41352f60c282be78237ce3718a2216125cf5fd	1	0	\\x000000010000000000800003b07f5a9712b4b06039ae94c3acb7462f305ec733aba50b85467975f7ad3451280f6ddd11c8ab7b5d1d273ba9fa3173c7b9af5e8a541afee4a0bfde12e09eeacdac8d00f60d6ff5522ccb5444204f206b912958f4d7f1bfc04ac46174a297de6da2240b25dfb06a5a4acb1a66964ce4f0c45e1ed365f8f6cc1eb6170582602181010001	\\x82b1b8b0db77114af137f5400d28701c2e1f62a55c07c3e6bfc85c678c63607d426785047ff07dee1267754708a4abc6e877107a79cd14cd578670da3c7de002	1670667797000000	1671272597000000	1734344597000000	1828952597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\xa57291a077edcac8a5a1e7372d878057b48ddeed859417358280135c36eaa12c86f0b98a5df25d1bf944c6ecb11eef5b912133210f3b6809ad7cb6120c3f3baf	1	0	\\x000000010000000000800003af7b1ba8911177a2e4a7dc456b144c188dc96a958e8818b28eea5f92c3bd3b3736c5634675eac7114fcbcc15655f604a768e3597187b0e1860f2228cd3a4463849103a6a5e7b5357a8886687ac9e02165937d294c2210b66b283d8cde8e15730d70886ee5630a30e5978295ae5e6aa535dd07f7374dc9ec49d823027235ceedb010001	\\xfeab42376a4c246bfe6cd5685cf2606c1c2086298c97758e11d2541af323486e5a78c739b00cec228518ed0e588737efae53b29f0b152dedabdeafe348a86804	1688198297000000	1688803097000000	1751875097000000	1846483097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
276	\\xa7c64bbb3938368a04d81eb5c546763e5be26369593a1a873ab3040ffea14967722f47861ca874c34d37f684bb319eb5ee236ed32e7fe58f3588175d2fb6a2ab	1	0	\\x000000010000000000800003b0712f95e15359ea92ef9a302dba392929e14e993249f91b947d6ceea64c91a06b43b6ee33f726246e3fbac13a32f00bab196700d1a0a8932ac119e432b47d241568e5f604db1b72fd4ef05a4fab8872af7b2057958cf7ac2d371ae28a7cac3954492a7564113ff8c2812d0c5958cc8cc2e97ce1fddafde21feab66b8289eea1010001	\\x0125740f6df5f179711ba71b3d0b78ad157630fb00cf5c75d9c4f074f27968eba65fe18aec61d080b1bd63615bf9e3f8c013d14998c5f2fb5c409e6a35264d03	1664622797000000	1665227597000000	1728299597000000	1822907597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\xa912106b100f4d632bd8e453f9e881c06c08b44c07f9e5546d2a611687d4860ca9eaa387b79f2979190352ec799599af722671256a3938fe9c19522b8a93345b	1	0	\\x000000010000000000800003ba09c302ff9ecef79fc25992f70f6a52d7f2844812e85c7b86f5d429606018f3d8ab558ec2434ddb50720005846c2b02d1826ee2abfcefc0e7ff4de421a8bf9ac2fb858cbf9d0b0441b3a037653d449b1c51c445ea7512bde8b6f9bb40e629b0533d78dba0a88fc26c5e16dfe30b517e4c82b2e151b6b4549f396789ed62b513010001	\\x33610915ca9359a9bd6f258a36abf1a2927db0607f2bd7401be3c5c0d4b311fd096d7e7bc4e7e0bf0d697373dacdc5caa54537172cc74649c0db728b19f7d70e	1670667797000000	1671272597000000	1734344597000000	1828952597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\xaa8e8d01432b93c47b3a6bdd87210161dc913e5c2621268ab36073e7a05092d9dd2adee07b78362294fd6df782a65d39142398861d1b5b3742ce585dd1af558c	1	0	\\x000000010000000000800003d7e275b10530385a8ade21828679a85311b435c4f2c4bc7d04ef74541dfce62f43648f0bf8fa291eb3cf9732fbac5ea4efe36820d32559efe2536a9ec1aa35fd10eada865f094220987f83d5a9fd3f9c7527d64694f602ede88ede471be7088d0a92997df84ed6914f6614c0d03143680ca1f4934ffb88bcdc4e6f5672236ac3010001	\\x2524ee4da9ee0cd64209f0a657c09b8615d4db5e12b9821739af345ed350e4143930d29d3962ca98fe58cdd66245b1b5702c14575a7c987c721756e9feef230a	1659786797000000	1660391597000000	1723463597000000	1818071597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
279	\\xaf86d3b0d5ea77b83091af185fd9f17deba489d459801aeab4d5d2217fad680961f820f7338d3c82666346fd81a7bd076d636285980a0574af91dad0f8d1b5d8	1	0	\\x000000010000000000800003ce7877e723eb53c4e2445d7771050db3fc796998c9701c81c46d82f0934561bd36146521420c58885a32871f138685456b03223c5c4d4298e6a01ffe7eabd491dcd7c36e81f160dff6dbe44c78c2e230fc5b69d46945a4ed964f5a73b636059deba757e06441ef4c428d3a58420a1156d7c16cf29d337b9befb64430c6c255c1010001	\\xb407b300923fdb204035e8028986c93a37026c97dd6da9a83e22cf07dea59459ac4cea5a16a3bac749d8956a4b45f7cf7346dfe2534ff72671db66250f481804	1682757797000000	1683362597000000	1746434597000000	1841042597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xb2aacbe7f021be6f9f467e0ce6289f52757cb272766a379d3a8e0a88c30454eb641e4b11051c2e569bfbe7f3b149d0d50949b186426010519c0b204cd29c5b3e	1	0	\\x000000010000000000800003ce3bc4eb9d4056e731455aba9e0c929b48ecc29d0284346c4ee7802a883f0b036c11c3d05fe3d37df3e9e99f0e5ac5c566c750428a8801a3382726c27e95ccbda64fb1ba038ca6abf86fa8d8a3298ecc8053da0f11f2ecf97960cd9752701a1a07ee7e98840752fa33e19423344733d7c7238217a7c86ecec18528626450f8d7010001	\\xe08d924d08e4475fd4bf197a1a10df1b793d8ae37fc5b7da461cc2ba51529ddf16e225dc9da509572d3dd7b82bf581b747501e251d16f4c0b3d4d8e0a1b15005	1679130797000000	1679735597000000	1742807597000000	1837415597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\xb37a9a529ef0680c6aff783af748329e56ee34d11deb33639ec8bfa1cd3a0fb6f40cf2cee639b530c82cd81a3a102a16b1f1e0e1cf2ba2e04a1dd3c15754b80a	1	0	\\x000000010000000000800003c0079f319ef2e7661ada484b860731c93d99246293ffefeb9c7016c63ce574b41da297630ab08135476fdfac9fa00ecf7bd2a8d7eed0e8d8e6476f6e9018aaf63a7511e11508deee112ada692df24721ea24d07cb62289a8135e890c360d6e7b016a823b843e7d35d947253b6635ec1797f3c2e1354cc86c2ca9553f752c0457010001	\\x8686aada3842a899f62f1db38fdaba4f710998e477254087322bc3ce8f8107ebbc9e1219ceff192e54bc0d81bb002d701fa42779c2bd6f8fa33a599bd503e80c	1688802797000000	1689407597000000	1752479597000000	1847087597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
282	\\xb43290a7d9e5bab353a32bdb8e91b810a8ed70e9bcdce8c8125524dab79b2012f4b1b1e9ad4ef7b77f4a69f72aea75b6b6f6a68f433aba29973e466914ea8ee0	1	0	\\x000000010000000000800003b0000d72069d8b98b086d25e18939a3f46db936d6b6177c2a565e7c97f950ec7b4a5f4f4e5cd90a36ef75de51ac9e720ca271e4e4d148fc7f8b32c33aed0171f5a9031dca047a3217b25a909b24b3240b4db4e193c0d576a55f09500ec1494a1068a5c34ca2d9e33d2093958e3555a04ad9ccc0c8da29d61d0f6b28b5959eae9010001	\\x7e58758024028d00808fdc41dfdce432400377dfe79daf795c45413275bc0be9797dd9a5f0cdcfbff74ef75584c0d452d5af885b8f7080009ed47b90a326b50b	1683966797000000	1684571597000000	1747643597000000	1842251597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
283	\\xb46a9818a9ce95973943039cefcde63e0337f277c1eb42afa4049e42689906a8bfd139ec01d2471218deba57051aaa37bf144514ebf3f8c1e7c4fda3d6f173e4	1	0	\\x000000010000000000800003d0706bf3f5124a1e33e3916d2ac74f806050a0d84eeea0cbef6d4706897518427ad170ddc9e9e2b2bdca227878d75e5dd2fd77ada09e510892b483d002a6745899a45ef788f2f8e295de9f9bd2e7a440cbb46906fcfd6182003ff5956058cf7820565d042dbd76cb54ae0462941c07acb09bf75c21967c834db071152c77f223010001	\\xdf6b3685647e88d5043d01aa2f1a9891eaec91af0f5d2ecee246ee39d38b87f6c4e19f774b6628ec24aa1fc192d5cefb9afcfe8774955c8eefc9745248a33b0a	1670063297000000	1670668097000000	1733740097000000	1828348097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\xb9ae0ccd38644fa13a72819f916689d85e636b401c31ae1febdc6ebb76ece48e39e8a5ee311997147363f83f7a22369f093cbc665ff7974273391fd4e4be1e64	1	0	\\x000000010000000000800003c49ffcaa3a9395f8ae3f051b3c24bfe2688f6ca6bb5ced92a3ae14ffbc84de90f5688e84679c710b2e5a1b209165ea8d7cca40025a5a6d6c3d83c6d1c29afdc8940d9f09b9254a639bb8acfb90760a6d9db806c5c0483e2cb63893ed34602b68509ec978b592e66ec02120e5c2f504c2117c3e17ea99ec3964bf769b33bec9ff010001	\\x8d1bed321f1ae7fc0ba73a77b77fe7ff3941f1aab76caf5de906beeaa0e44d5dd047ad87291c98c5a1c678536e64c9159c0f290cb245ec947bde0b870d0a8c00	1683362297000000	1683967097000000	1747039097000000	1841647097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xbbc694de54753ea6070864c556510303ff7dd9524241504a6c2090c74d8ef70bf8b15d194a31035e00821244545ace07223312f604e16f02af72f231ac10f78e	1	0	\\x000000010000000000800003b959bf10f83ab6916f6acac7a237b847ba8dfc8dadc4d8da85f0690c3c7897efccbb99ec79a5ebcfab75f52efe23a25da9c6bdb41faf3b44214e61999c73c9fd56b1432016af270fe808736b162fafd93afb5f6b958d2c2477849f210cf9574bfc4242ebafd4bdebb79ea26ba8668336f89be7a0d33c7874582686e190685aad010001	\\x90d90368b655a83b91922bde4200611fc9fd75b2e17a43d885b57d191bce181e255b1c7379dda550201e47a73a3aeaffca53fc7079d7c6d0a2b704643d737109	1676108297000000	1676713097000000	1739785097000000	1834393097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
286	\\xbd56d025289fe8f23472207908ae10e2c2e4e232e9e12a08506d56d98d46e2e892b10342a9afb000a33e8d72c8b855df40d15695768d9fee147217a87a944e03	1	0	\\x000000010000000000800003c3b3c00dfcee9599b956bd5441125157eb4ec5fcce1b104da78e19faa0b3597cf0c7acd7d966bdce0d3e6296db0f28b8ec7b925a8dbdf6fb84255fe999044228b17c7257a22c0f3337de96503e613ed34ea56ae2a9cf842a9821709b026ae7f1e45ab153025de76fc3cb9a77d1415d61188c3f1a21ade5b5e502efeb34ec2edd010001	\\x0ac41a7d54d31e2b1eb0bdf4046f5592f40ef4b407a981056b2bfb21ae8f3019df0228547d24b41e4c9e456166a66620d152c78cfe87a1cc955ea75a4e7c9d04	1663413797000000	1664018597000000	1727090597000000	1821698597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xbdaa3f38cb96523dcf351d4b32a0e5cdcda4eff16fc8ea218626fadffd8a907f564e970281af744e28d6452e9df1ee87ff85ac347582e032ad6309bff87a9d3b	1	0	\\x000000010000000000800003bfb53ebe2b9cc2d241c2a490c02e4d9ff50f9b2fedd928c4a3b3e71fada362b03d8253dc5b717c101b255f8c950ffc90c40bf0ebbaa336172053f646c881028398baee4089479beabbb4a567ea9ac44fac1b19b7e75c82355785e4081a2faaa2d7a99e2c363cfef406e61df5baeb8ad05df6dc3d5841f0af5e3f8fbbd3342771010001	\\x98f429eba53abbf8e3b9da38458d7a1d9c6d9457db1418559e3ce1a9e9e30e98704ba98e04aa4fba6adde52e3499badafd958c3341543e913a1f2cc46325180e	1682153297000000	1682758097000000	1745830097000000	1840438097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
288	\\xbf6aa134f18c12ac71e2048d0ccfffc2aa22ac3a2a04798e82c47046bcc52b049652ec2982bcaffa96c12314d569573e212a725b5feb8d92f94efc0f2d73ac16	1	0	\\x000000010000000000800003b109361cf161c729d268b60253bba419029ff67a09b441e8b2a90f36ec7b1aee71cf75effbb8c3db9c3d7b2facf8b83bf75e628b5b2926991965220eb046ba2bd32dd0359bc7b4789912c0630844f912abdfc304f30b470d32abcef31579f6fac62f0d4b219bb743c3d94bfc9a1cda65063e1ed55d1c234d0ee71e566caafee5010001	\\x24050be0445a2f27bd19e9c18fad5c4770a958fd6c3032e97537c2332f8dd17c8cc0ee19625027c5384cd7793653801205a5084b56edaffd02c453824f716102	1688198297000000	1688803097000000	1751875097000000	1846483097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xc2fee84029c677ae0f1f6544ce16c642df899682c52a6e440eb84ee43012f08906048de1904ce3480a6e8c8e6084f1d246b24e17e42bfd9bedb8daeb25931fa7	1	0	\\x000000010000000000800003c723705ebd55a4d94ef40c1288f6c7982a679879ffd906fdac482236a7bdb373e3fcf866f4690c367515f1604cae67ffc5548e5d8553293093d291a49e942834e2b8098c04f1aee11f461a3eeb18e530c7aaf67678b8849f1410a3d822e5b6b190cfdac79675e2e078bdc1253a71b4c82b894734094ad0cd800174fdbaeba9eb010001	\\xf63af26a3ecc272ec20c54684de6774a45dca277bfdfddf3425d2b1417c912ae8af04145537e30530715bb96641affe27a90ef85f0f3449dfb0ca4545eacc60f	1687593797000000	1688198597000000	1751270597000000	1845878597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xc572a17ee3aa654172b72f5121e24f1f231d8f030ca11f6d2259e5cf965472312f08989bc44dd7bf6d8070e575643c000f488665add9c7900d8b66263bfdffb5	1	0	\\x000000010000000000800003da0eaab967b4dced764b5a1c42a9425f0cc49d6022049c9d9ef8bc881f0e5c24f1f3066bd375b99d1a368c569299879f183675a0a9ec48496c82880890916d2a2abb7748802ff05c9b566dd55e2d1788af9c0fc7c7ebf16c3b2b2eeab713fff6082c0a31a8b75dbbff630264a4c3fe9d53af344800be668b351a8845b20cb247010001	\\x60bb1082bd0103a5e568fa92dc0bd00a6888ab56cb2e44c377a5749a48fd215cabd22618bc54685556a945dd7fa2b772843bfcd94d626bb0d8b80d217b5a1903	1682757797000000	1683362597000000	1746434597000000	1841042597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xc7e6b7672f39d5762093169816437bf4464b0f5eb86a87913101d323d93fd4920303b539016e4c136460e31afad2ffd651a3ee604947e0a7a95b701b46cfe1ac	1	0	\\x000000010000000000800003c4d465723f1e66ea07de6821ff3732a3b5131c5dc2a53f6ef96fadf4fa8614b5f267d9b680a40189ee1e889a919bf50e66b872da255829819a51bb365740c286da942feaef690aa43330c53d2f7d0f5aeeb6a0dda9bf92069e4da9b839c3bf83e1d04f58acc8325cbf94d82dd810cbf573073b20de914f73f5e6cdd62caa6cf9010001	\\x226b59ae37f82fd33cf5579628385b5dba8721a6a5b310f6c71e2dffcaea13af2944b762a3a256a8fa68ad9b6e961a403eecf665d6d64dae802c2d571b069100	1660995797000000	1661600597000000	1724672597000000	1819280597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\xcb1edd56b385d106cd9a4e05a58298bf7e8a01d1d7926bc5d3d1dc3837adf813d1faac3959cd3ca5b7c0ff7f643557221adc77a4dbd2804473c8364e6fc0f7ef	1	0	\\x0000000100000000008000039df620cd01e7ff831a6109c663f29004110d079ac77a222d86e2bfb22665b693208707cfec603f8b4aff6e3cc8302dde1f9ad682b5f304fa74a8bdc1f35b1982b92fa56d989b5cb405284343a00eea7518c7e4e6af06500ca493b46f2bffa76284451a8d6d2c742e677fca503621bb2f514d619c4737bb953d171468e49fadbf010001	\\x75a250b524350762212ad5cde5c6683a4a68e1428109c5abed07f08e88f5d53a6c47c3bade4d3c8b8a39d8a1146feff9770fbac8b3e42f0dcc2e2af85627780f	1677317297000000	1677922097000000	1740994097000000	1835602097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xd25e12c7c0771f8293b4b6ea6b0b82d54a54adda8e10af8eb65e70b0b5f60aa8c8ca55750363d58d55e39437aff81ff2d6efa2b9f97b002a02ece358a565b7c4	1	0	\\x000000010000000000800003949bc477cd261858ca2e7f6be5d1bc793c1131a33f46bca476024835a898bf84de02177e6c54256914ffdcc7808a0da7aea8239efe8a1b66f4e73ab87da1540e935e0b13e3eb1b45d5906ac5d2a3fdfc1df1d6a27e6323c5cc922344b49989e83703c6b35999f56ce68a50339b8bd3391402b39c94ba71a3132d9ad57d5677f9010001	\\x93418d012935aa5d6451f998d17cba5685693b48262ba894fa9c499b67ece7735da3f87361bdeb4ba61eb1464b89a2f0a69506463f7185af23aafd529562f708	1676108297000000	1676713097000000	1739785097000000	1834393097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
294	\\xd3de12526e4fc21b9bf926e47dfcd5187d346cf63d2a2115a3c8e1f6f5b5d2f436a1cc2f12bb86ad7868218ce2846d08ad23d0c1c7cb78cb10a8021f00fcf133	1	0	\\x000000010000000000800003dc315c6ae5cfbd6439d48b8fc36efcb8fb84b9ed7196c61507db3e46480a31a04ed0e759a658898cead2fbbbccf952a1d86ca31f39dbe3fae65898802ea73aac48a3b790fa98f54d49b9937a09a00650f50daf408c75a662200cf4043d961a705b45b7a8d047495eb45cc9edefed9d7921ff7549aebb62f82a6fe4b2296f4b3d010001	\\xe70f9fc1022bf847810a5606a36fb047e30a76ae8c51d4107936d742ddf6f437391521874912a946f9543142fb55c05a5bfe066a70204a901481550bf5d37b0c	1676108297000000	1676713097000000	1739785097000000	1834393097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xd5129646638325789bc1564dec6cc225998818edbab4f53fc3310c873f952a936422f839783094cefc02eda967fe9e729145f551ed6eb528a86e552bd40e9bdd	1	0	\\x000000010000000000800003a7369e6e9227c0d8e8accd2dcf8f3e4ecd416dfad0ffdaf2999c3513abec9578563763ad40eda09507bcab5a4639ee853e13304873a375a6bfb08202a907e2710afddad29f3399cd6cb26e7f11d2b15be168f125d00e0bd814bc4331e727e78eec885f1237e20ac8e6885b8d75ae7ac83024a6d882555d56a139e56e48d74549010001	\\xeae1f0dd2b54abddcf8d300bf44838191c8d467ff4e61e87171548240f8d6bbbe6c24eed5c5c6f16ef6137d66f22fd2085a9a9d54dafb57f408a8a0e948ca501	1688802797000000	1689407597000000	1752479597000000	1847087597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xd53af58ab9b15d53908c72a05d23a10b943cc3295a4cae35db0f5a023192e82fd0151615f60f64b38d7ba172f4dca2d70872b4edb044389c6cae89f661413ece	1	0	\\x000000010000000000800003c8b1200595618b0ffb50e98768ee06dacf12fbb180458f8c63d5f55909339cc575db7655a0641dc355da6dfb813e2a5063120c09b457b3fbc247a3e8c8090b9b0df8ab1b4e27af42fc5649678ceb3bfd61acec5cdd1ab6752b4701a856a104b18718e41f354a054492986efe437837bf08ae37cfcb54959076a1d53123cd2a63010001	\\x0650c72520872d771ea608188567ab22a91bfd55910d63d8292f3b8ca5c277b8ea3cb27a57f9c44ab48422c64998f4085f18cb0722622db33808f4a9155b6c09	1670063297000000	1670668097000000	1733740097000000	1828348097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
297	\\xd7ce9f26b8f360eb71f300cb0847aadc051a4414a2c4390068ed2dfec00c98fd62a648d971ee35828abb75a9bc4970f09556e57cdac964332d6e401a48ea2135	1	0	\\x000000010000000000800003c144ed83ac41b19a9de4ba27841fd6b8f68e2aef9f5ac78690bba8340bb86324238c902c8af640dcb13de914dfe60df8e593505ed10fcd425a815e3238b64cdf689199824dde19b3d8519fa7ec12a200df09c3e6b032742f152ab8a652f39337021ce516c8f9495b54f8b2718a9cea842c08923c1b2cfc769e19884978920137010001	\\x25cf10a41244f753f9163c138ab86371645f6738cdb5fe9de7c4e8bc1f839a996f6bbfe0195101d5205bc149d65db6cc4625f9b254cc85c88f38c590b99fe509	1689407297000000	1690012097000000	1753084097000000	1847692097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
298	\\xdc2a1e1b5ce338b2f9f710d36b9d1bed0e2afc296ae3e71c952f875e9a5d50c3cf5c129f899143f8243284fddb77322d5fbbcdb995a5833dc4e65eb95e22ca8d	1	0	\\x000000010000000000800003d5c1bb9b1c0c35e7cea491f2c87c885f1ecd72341d9e025dbd28678285d8741a8fe0e1b5ad713f8b9d5ff808d9e6a657551d72bc69635741f091b99dc814fe42b3293e1a2215c2b75a4fa04e19d83ba31b3e983f82eaf01099c7fd0a6546b33f0a9fb3eac3751977885f825d7190f06c8840e09728f7a04447f533477323d4bf010001	\\xab2b18fa034efef7663f7ff08663d7ce04b9fd11d7d1d58caff27a990dadab5b3a87315048b0b4c75c4c0d4213614c47b8187b31b5dda000f1e138a435e32f0b	1677921797000000	1678526597000000	1741598597000000	1836206597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xdd3e4e453564a751346f869fe9fcbcaeb633df1a64a3be7dee0195c87ca1aa268ed9381033776236b17e622f9de03887893a7116abf685ae07882cc7aa0d0f82	1	0	\\x000000010000000000800003ab8f57e3022e7aaed4d1c267aaac12c682fed0092b195be43b69004c25e43284054fb04a70127e8ad17392f6a45e94693ef0c2e4cef020344b5d6184fe4967ec7a03691b8afe88dc35b7e63e2017d5252f4838f67cbbfbea12e3b6044f25ae902adb3afda528e979939fcbecac4934e1b1425c2516138bda836ec8eba6ddf5df010001	\\xbb511bd8b4e92bb1102b35b124da1172d7bbe4fc20e37208257abdaf05c62216713ec56105c99e212da36d7fef09312b73e6e56c8e376599e07efd0e8e0f9e0c	1690616297000000	1691221097000000	1754293097000000	1848901097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xe2d6dadc117136023e4406c06d9700fa219d0c7442a8f51e6240180a6310484cfff22ab6e672992e46324c18e9bfd3070cd77af5da7dbf84037e1b97122eb633	1	0	\\x000000010000000000800003a5aa0ed4805f720ec78b4c7befc0a1cb1860929288eb32cf2b795a1edcda4d1842f1a082e3813db884c713b8e11d9501964bdb3c04878a38a331c9f8de9142146af74bba6d71427a45a3c6e7da76ea854930448b81420a2066c6014a4ba9145646732c498d838c1b1e021793ca8c304d42b8ac880c22993e46c947178b3ce007010001	\\x5988683e29bdaa4a96ef36dda03c9ec41f1a4b062b1fda56234e22d18aa26a9a2783b87bbf507c30ffddce41340cb8aa73dc231e708417ccbc0818f9b218ea00	1670063297000000	1670668097000000	1733740097000000	1828348097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
301	\\xe3a215928aec52e399e9daa8ef3d1937a70120d8c4264544f75f8bba7ca3318a20ae184626d14695bb875d86a1cb2710e8143545e27cc2aae7ff656c70f3fd19	1	0	\\x000000010000000000800003a8c3994dd8fcef43665d7dd394b0e3ab2bfac97e051e935264f3fda0ca8b50f9747eced5a297c641a87e70c3b974dd35bce9dbeda0b18c8b94f75c2032f45be01d95bd5c3953f444b1edeee0a31e214c4d01e021cb02d7119e5dd08fe086a8ebeb02a2f80b6339b1aa8eb08ea5160e3aba3b38158d5f9e409dd67d8749d23e55010001	\\x86873ad9621b38ebfb2291aa4d46aa812259d2ea1e306dac4f66ecc5718129d1cd785b4c3d71850d2fffa6882f520637abc44bb47efd977deb76a93858d4e60a	1681548797000000	1682153597000000	1745225597000000	1839833597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xe3327a1dac13a11a5677150b553090f499887eb41e1c34896be1dfa19043b03758ab394ea940e1e3b9ea596e391b025a93a09e4f76d38b7d458791cb31e988ad	1	0	\\x000000010000000000800003de56b3ad2dbfb4a87fe6ef91f24d5851e98fb8eee7a875cf38700119e8796ee2040e4a3b81744f20a9674be2c579c4e486255a8d6af1d937ed0fe1e3a8b07de0c44d5793fc9e5735a001c6119d17f5e047505edaa779f5a4c59409c6abe03ec9bb2c716d127c9e41763add55c60a52afd45bdf3a6f4acaa8733acc356501ad95010001	\\x72bf4ba9e85f1a7b0e12eb0bca9ddcdab54abe455a0bda04ebe77dbb64d8d8136a5e7c6d792a9ad39d7895c461af4246723f343c1f42d273cda4f264859c890c	1667040797000000	1667645597000000	1730717597000000	1825325597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
303	\\xe6ce82192048a1225191e071472d728cbfa424eb60a090e752475863d3dcdaf87436ed396470445fb15510a29b405443e3c643ad6742d4656fb25a03a93e5e75	1	0	\\x000000010000000000800003b3fdb8068da750b0aea7e9a30a9bd85e0ea13f9406d8f495d32f669f4d46dab8f499d8a415a82e6dbf2a1fd645ae5ac401ba5c97afca24df9512eee5972710b719064a5dbc633684be5dbe3ef423325dc7ff59447e59ce4a4ebe7572ee79fa9e6f202e877a1bfe373b1332aa504194d57bb3b701fda0802926c702251aebfc0b010001	\\x287e99514328974b81b2325ad7e14abe2622a2e2d1bcea988775573540baac5590f10f1288aca3cdc09515f4579bd4c3510f2684a0eb5546152eef8f6239f40a	1664018297000000	1664623097000000	1727695097000000	1822303097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xe6de4bc068a12fff7f75e8304c19898c0c815b233063dad4cdd150d09022cac9dea521ce536792e3328970ac8d706dd93572502fab9d1096ea3ea24cdd6f185d	1	0	\\x000000010000000000800003f2f9bdbec298de22e2a04e1b6fa41aab839ea0a0c8b4b80bba02ec343935ef921bf6b4622b40f1316471d47eeab90885e2b275f54e981e9f77032149defc4318558d2975c6667757e7a797d5a72a2e8951b78c1f4f3b6c53eb40197d2659acb6b7d58a6734429e6921d6ef0043bcc125444a88d5b9f2589309bcf797dd3df283010001	\\x0bdaa61745c788e0dc30ee83febeff9b8e6649281e7b2535627c5d4777eced8580c19dfe66e7b8019b566edbe478e73964f1728a09d45d1d8f5e4a73ed73f80a	1690616297000000	1691221097000000	1754293097000000	1848901097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
305	\\xea5a78bdd48de4075a7a86ce11d6ed488e5bd17634af7c1d6ae323c6160c4b7948373f39fc252b9b24018078e2662e85a99d867464001054bc460a8e14f1183f	1	0	\\x000000010000000000800003ce47d560f731f4edbacadbbb99d78752d9e1262771c31767054a41f83f13eba02068140893c2fc9a0cd569f3ad2c7533701c4f2d5f4bbcaa984904ab2ff20d46474a0599a2abd62400dd8920c2c8ca76165c5677b906e8eca1a4e52f83b686f9c6171fa8719cf52fe02d7992efbecdc7324d42f1dbe2a21a094e59266a09b3bf010001	\\x8326eeb2bf76d60100740a9ed68b51cbc70e7bb30716897663bbf1fc01c93b79c6bc37c670367e4b69ada52de1ff9afa543cf44e1e6227f05e03781c05b9050b	1671876797000000	1672481597000000	1735553597000000	1830161597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xeb06a36caff484bf5b6ef8ff28eb9febde9cbfdf4d618c4ffd736c777d0c39996134b1c4803069c7ddb6bc67642486f8d7b6bd55314205a5c2eff37f4d4819b0	1	0	\\x000000010000000000800003bb0c384216a8d12fb90a01ba884ff2ab2217de04a6da8382246cc4697a318ec82970d58b7607b09ada9c6898dc21171aa2a3bd6485e4428f7676e7301f5c4f59a75b6e4f3046878b3408551466ef473d34b4bbccaa51226bd28ab8ede62099936cbd80271245f3d729b68e7f99e3f780e4d8e07cedd4dfef2998103725c25d97010001	\\x7ed53f4ce48b956cd317346e4fec6d3385ce3c689dcbd39353a27bdda4d3a305cbc893b6be8fcfdb6a44d230c1647dd3c6a22cc88edd92e760d5802ecdb1430d	1668854297000000	1669459097000000	1732531097000000	1827139097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xec7a9840bb922006bef8f3d64150c23869e0cd396c6b48ab280fd1cf8aa12a4561d85de21bbd7917f2dbc79607e7561f3db2822c450b518435522f7ebfc31e8f	1	0	\\x000000010000000000800003e3dfc9573d142a9933e80f2fcd125ec46cb3d200197279c1fcebeff37064201243b0edab0d5c8f8b216ebd1d54c493054e22d9c7c9ae39e64a02d64b978a3d205058bdaa28651952dbaf9384dad6d740c4044102bedd98babe21737b91b67fac957dcf9b8b5cd9b5759efcc6bebcba8056752e745395eee4cca3d9581229476f010001	\\xf6c870c8f9790bef807ddc1bd71beb65740259d6d98ded9aa0d3d06338932772419475e7a5d8a763bbe1b1a152209bb8ecaf82c68619d1d85b22dfacfd4a8e0a	1666436297000000	1667041097000000	1730113097000000	1824721097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xef0e62d56b6f486c2283a4573e752acc246136373d66a7e74327ca84e7eee07c6c7e9916c159447bb24c4bb1eb60a700fc2af7862cf1473b8312936fb1e729eb	1	0	\\x000000010000000000800003bab29b535e89a560c9f8bab9c5309fc069be6a06c3274b54f27bd5397e4cda43eacda7e67da18cca6bb84a7c4b9116424469e3c0ac6e4cff58f29e2d1bdd716d037e4b7d7bcad21c145c3fe352b910e7ab46ea8c81f00ceddf865bc4d61c03b201feb1e722c3d72e9bf2a91bedba7cacdd7c21c3bb9ce4a178f5c9212baaf723010001	\\x7b0a83b20f2d8b5d254c0cea7741ae03b3dccd9bee47862b892b95f606d59ebad3fc82df7670aef8fce4c944ac3a5840c25b103de79240c60011fc3f8bc21c0a	1675503797000000	1676108597000000	1739180597000000	1833788597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
309	\\xf0ae270ff8818bb710e1c039401647490f37484571f6c5a86f339fe316ac1adc5218449b2cb6b92eebd9fac20057f7616209cc1c8122d8211b6980ddfabafaf8	1	0	\\x000000010000000000800003c9fc7ca04153d9b737d4fe41c06f6f2b58621fc5a2c99cb8f27bcbfe101abb059ac81a5450a64fbc03dd24ca68a9a0cef6bd223be36d7e78e4b6c10f9b673c78f106c26d9bd4ede69e1725bf980222c07386f074c9b3b2c9fd3cd207125a6fabc6df7e456a5c639387c2adf3bad0dd02b1d380af02c5d845e607d0229c234e7f010001	\\xf4b728d9cdd22651d10991a1f0da63a29d895b2a420f554a522ee525cf85494d8dca8e45b683719f224979ae0f29a322ed2f8cc9dd6d0aecae7f9a2a8f374c05	1676712797000000	1677317597000000	1740389597000000	1834997597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xf106abbe05d1a1d406634c5529e70daf6ff18b4bcaad0d82e767a7c7924f75a5e55a91d43f49b80cd87e8f681dbee77b1f443f8b35c31c7ef78e51590fb780fb	1	0	\\x000000010000000000800003c9359779cf0fc239d861f602c392e08b3c13aa91eb110248c8bb063e0dac982e4d7f88fcee87d5c55ddeef11285bc6a26338d85febc50fa7fc2b767a9fe8336d479250cad2ffb58462070e72f3110bf410dbb59c9d730c0334442e9834364beddf349d198f1f2d92667edc79f22735324ce66d67a88de034fae7cacd7f30b6ab010001	\\xf914f9fd9ff989c534c2abd44a620e3569fdf2d001f028b7377132cd184e383c279f0e510076cdd28f746206a450fe1d550b5cec4a73121adc859ac6e0a1cc0e	1679735297000000	1680340097000000	1743412097000000	1838020097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\xf22e075a473af6d52af8d021f1ead0eac8a785ffb31911779d375c52fff2145929684ea93f9c8c41bd1266cad22cfc19f8fd40af267b530baca97f6329aba172	1	0	\\x000000010000000000800003afe7b592055f39e9d7a40088fa15b40d779b244dd08f00952dded11c51c4437c6f5ed35f8cd71214e2993864e72b1526782e971dbda0ad33c0643686561ff1fcad8380a41ce119418857cea6ed2c93569961560fd88381c1d51531f840d073dc58cfd1c4af3ac3cd1edcb0ad30c022b893ae93b03a23c6e040e2340a2311a03f010001	\\xc60bb4756bd800d4864d6defbbbc1ad223e45546794993e46b3a9e08c406f9cb865f468bc4a1f97acc67b090b5dd96eb7e3d19a1579592bd5ae28a9e605a6601	1666436297000000	1667041097000000	1730113097000000	1824721097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
312	\\xf3e27ce1ac62fd182b1d1739eda0468023affd269729c1f5f68154fc3dbf22c4e438785c9131fc6329f5ac23dd79f7cc8f66483e3a0e96c52fd99953e2ef0b03	1	0	\\x000000010000000000800003a0659e732cb294d6b2aafbc217ed12f299459296d07e31249a22a387e1da009b8148cf513497df093499e52c4a52ea64d664ba8874d6de6cce223e1d004d6fbd69e1ce6a07b7cb55a2305b43396b7281ba4a4134e4037e08871a8a7111ae627e8fa80be5771454b17b40ff5edd73f790110dc01cd595733eaee8037b701bd903010001	\\xeddb2c98cf61f5b8fa0bb24f7453e0ecef5ddf767ada72ce4901ae1154f75e48d17dc47601ca850afc313fc2d9b0558d3ae700893c17ef44571fdb762e729c08	1690011797000000	1690616597000000	1753688597000000	1848296597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
313	\\x08276b1b180968c0f03053798c96b2438e9cf9138f9d7e328e040f301929446e005ac623c84c24523ca02cbbe12a4675363601c3056014ccb78c5c794edd9f9a	1	0	\\x000000010000000000800003a4ba1688bb1a80d7597d05b9e3058fb6904bece8f6f3821598d787fbdaf48b04263fadf9537cbf1d40f0fc0f727a3558979ec6ef6c64f0aa027376b790e257ed403b5acb36342bef580b83c84ff6f031c2dc1e89f5f678aec6aa3149f4a1b6019f143b9140c1c1107682d5b7ce2ab004712466408e53e538fc6a18d524b0ff41010001	\\x0ed0f542290dcb00c6f8f1c1a84c9bba17a8faba25df1fb1a7a74fbd46de20de0731439f177c36b133fb8250c500ac75f6791419eca882c64891bd3f504b1201	1685780297000000	1686385097000000	1749457097000000	1844065097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
314	\\x08fff21f4298f612815e4dfe6051f62af26078256a6afbf3565971e5f3f903c24725043a179ab7787056b43f24d7169d70a13146b51c93940d91b086926c8a9a	1	0	\\x000000010000000000800003d645dc8b89c5b6aa6387edbd317e547413f392705e2a03c111d1b639edf70fbe09f82c0a4643286e77578f20e0d6798677179e14edad95e3b64157aa7dd6463b8b31cadd4315cc14ff0074ea1cb19f2403730c0512d711fb10109568beefc8fdd7836b07bea91db64efc49d4bb403f9d37187be12d7b34cb554f15808e1cf05d010001	\\x72a97a0b0e8d08ad315a96a94d47d20538cc0aaa2db9eadb38f4b1fff5ace13b78a8dc3900622cbb5edf7f723f7af358c80638e281aef88ca9ddd514fef50906	1662809297000000	1663414097000000	1726486097000000	1821094097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
315	\\x0913b5dc612d405d70b53e58bc1346424ca78d7df49fb36920421541f3ca015df9b660063713b314ee76ba2b60999c542bf33b307cc512c7c7ee5235da22e9e3	1	0	\\x000000010000000000800003d7ba1775c2b630e3245809217b24b8581947ceecaea6dd570ec4d1ff6b35919317f520e7a1bf9b70af37e8ebb27d2ba5606d7f094a1c8f113852a7276a7fcb41b117d9210781aed3c54686b8fc8e7a8c620b50b5e3867fabb57cd4a4c2aab920f7eab0ff509ed9730ef9c07086937c3f7211dd5fa3ca3899471cc4e595bd157f010001	\\xf15b772d159cc47f868c3187b57a28eb61c0bc4f9ddc8ebc8577c9ef95f93e446a432df6e60cb2bfae7c3aeda75d94b03094038add02297624bc287841ab430c	1666436297000000	1667041097000000	1730113097000000	1824721097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\x112fbe7d407ef0d12a0f535e494aa89f721e31f649b2b7bcb626ccd19c88cb1f6c09631b913a76e2944a3fca3de6845a01bd5c3a1db8558448c9ea097ae73414	1	0	\\x000000010000000000800003b27182c9cf20628edb789ad081db22e9f10fb7174c5823831b53fb28714c6d4bec560f20f7c4593a64626b483419f016f884cd9b0749892a6017827b37404d60a126320f1f8558d55abca3a4d837edcd783b925d13c86114ff66ba1f9f6ead7658ef1f80f2cc1dd77521e5b4984daefb96ab2f30f0dc9d7eea4081ae0c887c47010001	\\xec6f791888585fa23770502dc511011b01ed174b5dff18ddee0d34384ccef4f65125bf6504963f2894899dc68c93e4f7550f246aa332b5e3b248d538acbcef0a	1683362297000000	1683967097000000	1747039097000000	1841647097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
317	\\x15a74bf143f3c725b72919b9a1badff563f19afc065d602180917f9b91c59737208bf31a2e7fc0d7b62c35857ed226769319f0b9988cbfa9c7ce52bc786705ae	1	0	\\x000000010000000000800003ef924ea27a960f98c4f0c741234d6ce4da8f8b5b8f1e3eabc5922530c42e3f83560f4c83760ae01dcd2fb6b5d1c2761037163dc7e5e7603eedca8b97b7815e49b6290fc3e36f2c54fb6c7e99c756808532ef01650c677c7b671bd28539b5b745a0488d073a2c370b25a2cd04bab125508aa9621691b4948d205d294671d2a083010001	\\x35d0ef3645258ab24ccf4f8596c940211a29f4e83b29acb495fab7fa0632bfa147098664e15eabe720fb5ea5e2bd466c19f9ace82e200d3b478bda6a984b300b	1684571297000000	1685176097000000	1748248097000000	1842856097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\x1a2373ecbbc8ee5dd78d6b9e1cdc5d484e9ccf831fd55306c0dd5cc1cffd5e9bba7bba86990d3f87580c05b8ddf174d44f5b579d1c04722ed39e05cfee15afc5	1	0	\\x00000001000000000080000399dad2410927f695bf6a2dccc103e87514e5e75138e84968309b25c6fd3dc5a7de72ff3e70930a2c4d52ed9a3cb0c528e57797d3a2f27c0df805714be65e8419366cfef8b7cc32b83ee5de25f4add506e54fe0b70223abcd4fe47aa35a00fdcf44bfb4acfd08e4e0af864ecc09fbe0f8afad0677bf8e3ba5de804c8c1fcf11b9010001	\\xfaad5429d2d69adc6e007d1f81daea093afd2e04ba6b4006adac1b083b9d50a6fedf067a5ab6fac71c9f7597d2b3c1aa2227bfa7d99e1552fd1c7d20a8bf0f06	1679130797000000	1679735597000000	1742807597000000	1837415597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
319	\\x1be76256bbeff1b1ff63efb4fd9d72d3df7a9c1de770fb78ce1e0212a5aebfe1069e956a6a966edaa68a25c7e990dd50157379b20ec1ec9824368913e2b138f5	1	0	\\x000000010000000000800003bfa47738eb7e784c83f6403d8d34004ec111be1e1222d1428ad16085ff4b3a1dcd81182d99d23360916c1ba1f3994394cdeae5cc1d9f1c700e037ee88af7f75b9d5e63144addad66fafc1c34c2212c07e46865a35892daea18da648af3a3a4e4961061da291474825e63da2367bcf8962b29f2225cd356c7df2cbdb7728dd23f010001	\\x440cbb305409fa747f78caa121003e9cfe3d02e2ffc209fb62e2ec08712c115965a9d504ccd64e6aa7c154ff62711fa0b21a60e8ab4c224b4902faa439b75d09	1673690297000000	1674295097000000	1737367097000000	1831975097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\x1b835cfe18a99ebfbb86f25a6cde2ab6602765a0a68eaebdc72d75a066aa85d5d385c6118b37b851cf2ca0fae15d12c537608e412d5d3f0e905e2dff908ade63	1	0	\\x000000010000000000800003a78f6df137b5675fff8d2331f4a2343c9676332cfb220d8cb96621f3c5413070807a078e54481df970cdadad0652a2978ec802c56acb235f3a1f3a795c5a95b66d5d0e66c9e92b28d1b4ea1aa96464db44048c3a7c18b8ebdce29ba4a2c989ac8f16a6e4868868b63013b2f18e112b49da5050fa01a6fdf62da3ed8141631639010001	\\x9cbc501e5ed37553ba9f444cde32777abb57702427520e9f6e6a806db53bff633e050ce594d356a7cc8e5bc028363db6c11be3db6db83df47281c26823855604	1677317297000000	1677922097000000	1740994097000000	1835602097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\x1c772002d61aa4a30126d7306add343afbfa7efcba874d343db964f34c89a916431e3404cc76aa626b56d5e26f1bfa4f95db2ea599440627dc7c2b989ea0f83b	1	0	\\x000000010000000000800003be25e75a7743ea80153f77094e2cd1faba8fb4ff1f2c607548c6c69ef0103c121d1ad82d777333c9d32e79bf7e58fb079c640add1f5da731f6581d0fa776afdcb85b26bf334f786d4433485d7eeddd51226d7cd27b8eefd220ad7340d6f4cf50cbd495a612fc44fe349f5b611e93748a45d12dcc9e3d3ff6c9207c67b5cad1e9010001	\\xe5c19cba950ee37c22cecb2d093bcb40030fd64c365fea6996df2036b983ae2fa4d160507d1c71b9be1220bf19f9fe433034cf80164335b1b63d769cb6b3180d	1673085797000000	1673690597000000	1736762597000000	1831370597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x21333824d24e7cdc92b99da7bd5e184b8d25ebba93b3439594a1dc6732521142ac3d6b316ecd3db9917152b46106ef34f6b509bf67e049901fced4fd53a3742e	1	0	\\x000000010000000000800003cdc5b90d2e54ed4f8e14dde09c6f5e991a2e851b0b2a2d436827c62bd1d0170acf93a2315ef2cce5d2510d0ffec18b7120a5ae0a00b44b7656d03089d52a40ef6bb88442bae09b651e1697d324992b28e2c804319b778e550165f1259553875f3f8ff5e7e170217d80e43d221e9471c0e55e9c0f34fee0b210c16615b2130165010001	\\xfefc0375446b2c9ed4e5c61eb32f7b4bd4a853a07cefb03f3c162786e9b604ea08df0321565ab81e81ece0d7ed338dc040dba2d4a2baca5dbcb793813157620a	1662809297000000	1663414097000000	1726486097000000	1821094097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\x22b353ff16438cd4a7bfd980ca7b51a184ad4a5924bd438df575d95dc4ff362c7aabfea1c116627e2e2bd02d0b20a3623099267c402c5829dadf5ac42d2dc0ce	1	0	\\x000000010000000000800003d9f8928b0429ed174b2dee3ada5b8ee0059410b1d95ce823e30b5099fad21a4df71725fef598f5e0c96ce745d1cc4d544a7a89fc37bd82e489c0583f31a835d1c6c6117d71a2a9d762b268290820429573e4bab5b98d9f633c7a9745f2a34b68aa514514413d2cb7a7135ee2ca9455330152fbc8ed157b8d2c216948514ef5a9010001	\\x93844831f6c0510bb0b066d5bea2ed0cfdee2e9f1d64b1311d39dcb7db751a095cb721b765fee944017e42b7b6d0509dfc35a85622df2143840c3d69f2a81d03	1685175797000000	1685780597000000	1748852597000000	1843460597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
324	\\x229f34c603494c1671591cab722fc45cdfee482e2341ae86dd8bdea6a3e82977f6299aa74515c20265767afa62bb5461b561d00572532d0fbc42613947ff392c	1	0	\\x000000010000000000800003e1d74d9846906ea33e9f44f82697b6135165e2d56972424268664ad20c2d42c8cc4f9f364d407fb824e1fba9c6a3c34f7dfd6f7b81532c4ca052e0990563d89c266f1cc6e58e2529da7cbddf98d0613fa70d189ff6bb7d4b307e8189ad895c7d6b44c3f32d827bb7b2e6b7f0f8453fe1d92247b007e5954c94c78a92b35650e3010001	\\x87ec125e2d84902bd1fd7f9fac643cd314df3aa36ae14e017a940dc99600698a596bc18ab2cb7dd3d14f16b4875d03551ab7f669e510a89f0eb1da06ccac560f	1690616297000000	1691221097000000	1754293097000000	1848901097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x2467d5bd2c12aa594cd06c15eb5a30f65c47d80bf91418efabac742f2a325bbbb4fb896c2dcc1bb45ddfdae6e94c1cd3407aa052897dc33d0d208f02db711f22	1	0	\\x000000010000000000800003ed7a6fdb2cc0d9c4dccfb311e45383b445594549c921a223785bb208b5e714a62bbabe624c16382692e2c1cc63309c7e503a0301614b7b51cac5d166de7c40277b4cbb29f4d22b718b2fb0876235b2177d643b48ce9af64743ec675b446705fce9db0a6fecab7e16b3c843ab334e9195a39eb7d65d2a82fefd3da69133c12c59010001	\\xbc850813295d01b93a31d65fc03ae80263000f1eea57bdaebfb1f3cf4d8cd8ddd566efcd30e64ca1f77f4e2f2af60b37f851ce2c5c38e6b46ce5fd1e46354c05	1678526297000000	1679131097000000	1742203097000000	1836811097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x253b029f1d3a677d8f8d476f0c14f4345e5a54e037a143716f1693f48ccb4c4f54c6203c7e71931ad1f66a52b2ec2a365dd40534708b618c573c958facfd90ce	1	0	\\x000000010000000000800003c0ee6de857243c91a5f46e03c828d4fcb385fcc18c7881b307e3d5cfde137501d1afe789e572e3c65e5afe9dd31c9060b9bf6bb0840a97fc37d1485720ec48fda370866360d912fcf82406d2c60ea2388f63e66c2752583c568d2032b11bd7fb2e79a875c5279a72b4a85674f2b0d8b724d32cdddf2f8a65d6139fc4aa707f6b010001	\\x292cda8ce806dc2198f6ce0b01d7c127bdcf06e14a6cd0d6f08ca1a61d8f1c3c23633e95ccb7e680192d4b00f5c06d90286b6c1fdd9cac76dc2c928ca994340f	1681548797000000	1682153597000000	1745225597000000	1839833597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x26cb0812cdfffd78cceb8d7c8c9c6112e4d83b14c8d8e832e9e98e5d2ecf121d9983abf322cfd8425009c5c526e06d9ec3dfd7720f70617ce83087c433602945	1	0	\\x000000010000000000800003a6e5f415777c346c64528b29133ae3a429fec7e4a4edbfccbe1d96c90a435ca425768d63b2a4fd61f8c6fc9f14a94940442ef09cbadec290341c584670c3ee14ba952b91a5680ade4cda97d7cc6f4e081fec44fc00e5fffb56e8a9765a125b118803eda3922f44dc5fdbdb1bfc93a54cbfba7b69b09b97dec93f02b9ee3d8a5f010001	\\x4ace74dc7ae6a776914bb991ac14cef4b259a75e87ed31157679647d32d81f2ed63ae311c99d6dc519df57061746dc80ce870545e8d819e9df724d2a86d92b01	1679130797000000	1679735597000000	1742807597000000	1837415597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
328	\\x275f39f123b0102e296020e7a59c23bcbba7e333d6cf126158c33cce9f9da49466c6c900809d8fada46dc765173036c17275d678ebce0cf3bf3b0b2062312268	1	0	\\x000000010000000000800003b26984986414bc9bc30f5db0f88a39e8506002b4591d352de2f5d0d91c3ef2c3b9c6747a14b28fb31bb84bdc7e560a806e08b49fb03582d14e610c5645a143de05732e6403bb47b8875d8179ae6789c52121689ae2928494cde8b57362585e7cb987c8f67be476d35e8ba345b07b9f574059abb044d2a61fa75e1d65235307dd010001	\\xae23f70de50d7ee7ca7ad67769c7ab64bfdee094647ecf5c9d7053468635fcf83ba96cb2422f0b01b57b19bd735cea83701b5e1ed5f688f4e6f71acb7702fe0a	1686384797000000	1686989597000000	1750061597000000	1844669597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x282b25323d7b5a0f6984e8478d2171bc3704501fa53e000d600c5acef2a017f1e0cd9b4284c33f9b616da43d3a4bea9ea981ee54126da5197bac16e2852aca38	1	0	\\x000000010000000000800003b5e5c20ab7f72f4ec97e0bf86c5288b7fd707ceac9b328734c607b57fd83bb07bcef4ff798bace0bee21de0199fb51d845ecfa55837714f1eb09281951c437461cb33734c59212d57e86bf4c171ad5225f48ae6dba99aa99d8e0dd8916b4e888c7792f15b81aa96a733d52148f92ae5bb532ee79c3a96d1857266c6c6c36cffd010001	\\x33fd5158ad1f2ebf1bfaf7cd2f64f518878d1688b3a25ee5f3c4ba9654736375d3149621222a29871c99ca5058600f4ac46ace20c60974bbc65e552de9de1f02	1662204797000000	1662809597000000	1725881597000000	1820489597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x285b1d5e18643d8c42a64ec4868d1ca7e273c730156ff8392a4e42decb5230a76e6688afe9fcdb1a2865b4a35714f4be6992360a2946b6dce6ee256c4a0f89ee	1	0	\\x000000010000000000800003d63355c7135b3a63babc03556f6ab37208ef433293d88b41ecd4f94b0b24531aaae4dcddfa057236009c2fbe058cbee8de31b73bd42629ddffd36c489eb649c8c224062850c0d31144bcb7b949e67e2853780b92081aee4a3512ee417c62a601280a1a7e9cc442fd3a21c34eac105d708ac8e2e9a187bd54304d85a0f9a26915010001	\\x2c327cb0aacebc1836b88e049e65f68ac6857226c72823ca12600121f10509223d52347df1f9856f9f526300a2e8f093b17b40b0797ed8eae66f81e75ff8920d	1662809297000000	1663414097000000	1726486097000000	1821094097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x2a3f8e5d79b65dfd333f8505f1c52058333c66caf8124cbfd79079e80dd591726d1d462c35f506f161b05c958236a5bee804747b2e3fa80e12e9e5774c484e51	1	0	\\x000000010000000000800003ba5e63a1359ba769b0275359ad05dc0d7a314be527889b6046bb472efedb86a6eaf81b73da8b8c561cad755607561d9b152c2ade8e6c9f14f2a8afe154900dd0683e9fc632028f85e136205ca94d1c223d20c330bba2bbee8224e583aa44e2e5116288067122582c9d182321a9c04393946c125bbe14375666a92595d713aa85010001	\\x63f8a0b149436bf99724b2e827cb5aa457632769cfb8fd47b546d3fe7f30020d0604507550514331ae11af4178b1f371e8a26c5ebf8e8585aa2c3770aa0e7304	1670667797000000	1671272597000000	1734344597000000	1828952597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x2a1b33f789ee779d64b9e44be7374be9187b3b7ce72903bd9295207ac42dc9bb6e8f3a973e78be44689433cc9abf7c3aa86d1970b62c39c85095949de84ca732	1	0	\\x000000010000000000800003cabcb8d69f8fe969d29e42466a4ceba7696cce0788d392b0ffb4984130d3d667d17ade4d281bf5d8cdf87c75c60eea242c9f83b334478d38101b1c60ca8cd78ab06daad95aced776321a8cf7d927e2e501db649ae0e1577da7d7993356d26e27a86cb10caba21e580713fb763b8f95e850c56d3bfa25321042d1fdfa7c73d1eb010001	\\x1ead74557305af3e9e60feea7c99b362361d4386e27ccb2bda433b529f8db703a2135c29e738e41406f78aecb20a967e624b649548280ac79afe3a6f3e552805	1676712797000000	1677317597000000	1740389597000000	1834997597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x2c7f4d365cbe4569895ec56b72e4d999d38ed368092f6960a39e6907d23109ac058afe133871a79b080c382d20c0a368e3d203859191af5b338d9d0837866e35	1	0	\\x000000010000000000800003d910844c8e7c5198b2f1c7a49899e637682549c25564cc21f755827a57acbbf49570922f75b65339365ba66fdda3de28a8f80d2ee39f0920dce912399f9b3a04d3d7154a5d563ff59d0f9868115e21f2244a4479f209f83370dc3c771ef16f8408c422666b62fac676ef8208d9ffd762b5099e1155b107ec85d4723899d671a1010001	\\x66abb77b56e7c6043c3744ecaa1575ac190230d199b69bc4004f498d075c1cf37fde837e6243c5641f54f6993d72221640bad57269bdff9c3c9dce490880bc07	1661600297000000	1662205097000000	1725277097000000	1819885097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x2cb7b56194caa5ee5438689232a2567f379bc391ee83085b100f641ef37f345cc4f11dfe905de0e76e0f184597a71afdaaf5d02380c47ceeb3232f36c8534b16	1	0	\\x000000010000000000800003ac0e49803b54a61330d8b430dbe9e36ff4dba17a199c41c568d49297816fe19764323ad532c73e3c28e047c36b7166eaa54e4433c60775a88f2ab03feeb1c2285e002f0ae3e615c33977e8e0d5ad5f41b9e54dda6f7c12c75a5e3159536cc869897c26b884b2b25c1581c020ae75b115d3db7be3397e9898b4e6b7bc2d995f5f010001	\\x09da4bd54d6f2ac3d4f5bf1eeeabd6db40ab67b208eb809255e7bc137faa1e3ce642090bf2a6a14cbd8515364f8bdeb93f57ac0127f99660126f885130f4320a	1691220797000000	1691825597000000	1754897597000000	1849505597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x2fb3aab7983e174ef807a6c88f21e834d2865c903e6e85c33cfcba26ed9e522a07f8a5bbcf4e2386519bb23a8e60ad334158014d1c50ae3f9ecee6450af019d9	1	0	\\x000000010000000000800003e38649961177d541400f5399fd74217d872d9d645d47debd7a45a9ee34783e75eb9c0706c30e4b57dd2b1173f2a101d4b259f678345124d1b78bc0a6a4da0137d981df29926976b824d95d1d11268a252c6b497af4df97dd481e93a737877ec99e867cd883926787417b2bcef3f2829c92ffac2d617f7d4c8b9dc117b14acb81010001	\\x02be4fe04b3d4f2556729575f43f5bf940388cd17bc1715c1ec26d6e7b083c065f1099ce68d213bc34c1b7b2ed68c8e66e8e6452895ac22df8bef50173aeb607	1690011797000000	1690616597000000	1753688597000000	1848296597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
336	\\x2ffbf22e0440d7d556ce90b0842516c1f72bb943b0fb4a5058c42f09ae2d971797a9de51813e76d45ef95f16c07bd9e2ce040400b6ee32f0192cb7506f8ac411	1	0	\\x000000010000000000800003dd3f86672567d907c8b2ca8672fc5475861fb37bc83844ec13d02dfbf3c96b4f415bfb3dc4d1ff5281cb8ce81d486fd0b861ae5498c5b2f0e53a1788f571dbb3e4a9951ec4216c4e72c14bae8364f7cf6057ad989f9135478b0f13aeb983ad6e4df01c1bf51fb1cd5eead844d3f82de676101546ab0cbd447f04fa4b48b1bc91010001	\\x297fca07b38d62306f1f2ef999ee3e2db5c6c7e570c559acd3a754337ddbbff54d46cd9929be787a86305bdad06cc6689816ec98d8a818ffa85ac125e196130e	1674899297000000	1675504097000000	1738576097000000	1833184097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
337	\\x2f5b0205464b0f0ade911d5c1e11bed4b80e5f258ed3f03e1dac423808ccf4340bdef2820b60e447f62a6eaad40ad3053678af43cf2fe0a584e005d50c2a4fca	1	0	\\x000000010000000000800003d52f9daf865d7e32fbff5f387c7550c24b589f3bfaaaaf5b2f8c577953eb41ca88ee40d75bb8f8d75b280de651f69ab994f9f67ba4d2fe19fe04dfde130e6b2f5b88147a9c0bf2e85b05b101ce973e8c308929ece241b90488779fe6ff1697ed85411b83168a807712c311d0ce238494a24737d0d79182a528222b35fcddd785010001	\\x13eb8ff85635af2410edebac5a64105ae31051f6c3985ceabb7e6e973d47a0e9f907f2ec01adfb7cbf62326a45cc04612de70073312b7adc173e6e577920070a	1660391297000000	1660996097000000	1724068097000000	1818676097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
338	\\x324f2841376f0ed69c1dbdfa3f9d5ba5abf36c75066a437d72a78efc69c16c3d613534f8d632c3677550fdf61e31a4a153f6c73c3bf092d7a0c048993b37bcd8	1	0	\\x000000010000000000800003c63372ace7843652ffbe210a105ca183f91c217548b66fabd196eeb0215fe9347a637c38a6601100c17e1dd1dd24db4be695725823be31f54e9084beea4d5914f0720e87f21230bf90201836c8b45899cb188e07ef8bcc04814103c093749e7377d248eb285723bdb68f49886ee055cb2b3308d75656731b91577f3cc7a2691b010001	\\x0d6e2b6c11d7256124a35c1754d3a480cb018c37e6917f63cf9289e3595c27605064f33bb96d2714ad4e6a7f98b19434ec4bc7062c54154718ef3394575b0007	1666436297000000	1667041097000000	1730113097000000	1824721097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
339	\\x36e7b39ce64ea52f2ea516624fa8e471dddb39a31c8dd506b55eaf762862f5bfd52daee40852fcc5a82f3b4f7f5d00e5926d4d6ba43ad6f90a794a0ee1adf5b0	1	0	\\x000000010000000000800003dcd2c686f7c18f76af3fb6d071addd5d7ef94c9374f8716d2f4dd1a21539f56465dc0d1260d0f7f87d38de11eb668a5f300a4ab0d0a282a775e310b86729f1772f7f936909f5d76994075edf571c03c2066c3903ed91c808611d17970bbf10285f14f54a59b8f4e1214ca708e2f696da7cb411d9c3e51756f3a863dbde5cff27010001	\\x574e38d89793a190a9a8e74e573daa30d9b127028d84cb5b70919ab937dae989ff79dfedcaea959eef2e85c6a999c525513ad0b2a229a86289a3da18b2a95506	1670063297000000	1670668097000000	1733740097000000	1828348097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x366bea11e1e3a65e6b2a64cd94074f49fbb5ccc465429c39c3d573fea6ef28c78911ebeed1df98cdf50538e9125b09a5ada492c9022608229ae0f6f2b3674bcc	1	0	\\x000000010000000000800003c102422d18ca2af5c91e8e6a932a0a0f51b3b5f751f9935a762a842a59d2a3650d7c7d0a71cbeea98e8c7a0a52c70877bde1c3c8a7dd03549de49e226f1f05b0378e4c88b6bb963841176a72021f5ca8f72680518af36694382595fe857c8440cc97a5c4212ded56794c56588445d13aa76ad8e4f7f1a146ef127ecd4ebd0823010001	\\x32059b9c43d2ba177919a57f44c4087e0caa7108b69382d87ea3dfed90323bbeb328bba5a3178c5c320b7a1e2d6d9abcd8bfccb46154006c9aa1652ee50dcd09	1679735297000000	1680340097000000	1743412097000000	1838020097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
341	\\x40236b838a3982a21042123ef54442c5ade33a82d73cea7b0dee819bade23f4736b19634c5359aa16e74feadd161cc9d4c0cb1cbdab1a10e49c87cdec8aa348c	1	0	\\x000000010000000000800003aaaa69b106394a2b8d393069219a54df66c9e44760eaef50a900eaac389c4f5fbadb2a8bfe25e0d6d4330db2c14d6c92cba2ac0e64ea2c027f3070a1438640dddd4e735dc9d32f3232fe330685aabe8b8df520078abca34330622529e4e67e404711029e01eadbbca2fb6f12c8948b55a8f9fb0b04d23ac67ab72c14ea88d2f5010001	\\x4b835f65a79ae854cbab6c4b7a633297e1b961bc0b5e3cea3af9566a222ef7b262ef000ee1e514eac972796247d454eab02d5e84ca97fc963bebed9e8dea6603	1666436297000000	1667041097000000	1730113097000000	1824721097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x43f705c0b01815ee39a5f8312de9847a7c184bb5c5845c3c0cbfff3d8e8f2aee7b17fd894e4ce5955b512e9759f98da5d18d00350ba487220ce3a21861cb577d	1	0	\\x000000010000000000800003d75ba3a144b2726cebff2ccda44858fb1dd1b034ac7dec4a014902bec9ab9b9b61cb298f4887243ebde5e7229a28ae52ab2437095cbed1b2f88e6d45918b69d0ea9e4b8f45dd261b341f1f6d3b2aa19f70a788db5ac96f5d5d3443676ce0a2ac86ca3c48a314d40e4d2d9156d8f8ff43b9bd75816b2d522a140ba78bca845351010001	\\x530931e4eb4b29ef83a09089b83b3970d19302663b3975d5c4ae591ec6abd58f845a03cf9e0bf2554041e57d8fa9fde81ff3cd68c7cdb339ca71d2c6af485e03	1673085797000000	1673690597000000	1736762597000000	1831370597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
343	\\x43678592b7034bfe01fdab1447b866157132ecddf241dd64c87d5edb22771145ce78426ce88c670b33e765a572ada593eaf43561f1f1669a0a9a78a829610f55	1	0	\\x000000010000000000800003b73a2f4cbd7da2ed3f8038f77e22764a7313baee650f63623f1d367fe9924653e8e0468e1cd501a1b4f1f32f70405fd7c96b0af37b50a25efa218d3f28353292fa8b448c1c27bdfe2fba8a096505a5b908ec7d61372e9fd6dbe8fc13a5575dd8cb29bcdc012b86bac7bd422d8f9fcf9db8c851786ca87edf23faa7cc3e5e321d010001	\\x44ff83b80de23346f1787a472a38ea581ce20bd8e58eb5cebcf8fb8b8262cfe3d7f72bae12e150c79382a8d8db981a44d742ea81fc500469a6e33e7788b6290d	1665831797000000	1666436597000000	1729508597000000	1824116597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
344	\\x4abb4010c48c6251ca696a200d0c77c0971c9f4643a8d71dab93d36e6cfee620c75d80ac214a17ac6ba826636ec1c923ae95d43f57c40e4274c3ef09afa081a3	1	0	\\x000000010000000000800003b9c2d9de7d0fa37c46f717ed5eb973b1a51b7a4aaa45dafa7c1e1f337b577777e51b5d0b644450e6e943610e6cc4902a354a77e6fed65e0ba0b5e877b23ba595a13f21047ba08542f6595068be8c02781e7afa3aa8e69ba1c509f8f83a091451610b084f9be6579084ef33211274cd15cca3f5f61d21ca851476d91c2000a84d010001	\\x5fe47c1d262afbab73aff95028c7c64e3363bf34496fcddc7281f68b9141370f18455e2ee018ff76fa057a99beeb4a62d7f1d9d1563201ccdbf26b25221a7209	1662204797000000	1662809597000000	1725881597000000	1820489597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
345	\\x4cbb4a8cc73697922c8d2de5917617e4a332f994822c81b7780d9d38025b578fb19158294c3caf455fb780a79f92f490e7d6ef849d96bb0c0183e0b07d8d8722	1	0	\\x000000010000000000800003c76691b8f110cbd016393b10e0c064688c39eddcbe2462fd086d2cc77260c3dd6d949250e674fbd861a26a5de48700d91ca2e48621dba4c8009e3b259e41978a1c76e1788b5712daa44ad2487792ac6e278380ec8d43e6f9cef96668cdb1bcb1bc93ca6c5d708953eee75164d27ae85dbee556e9d7a569882818078dc81a8fa3010001	\\xf6deb99448da35c1ac2a0ffc55bbc3407bb1a730132e0f085ae0560242ccb8b1e4b0b9b1db962b0177b7af8f59012f61175cac137b1f21f4323c35896ddc1e0a	1659786797000000	1660391597000000	1723463597000000	1818071597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x4d8b49e00aaccd8ae10a5e281dd41e64af4e4ee9309ea26401ac16af61f1dc6805f56d06fec6beced96ca01455d5b4d7fff9795ef27aae3897643992405c47d9	1	0	\\x000000010000000000800003cacd8dbf77bf1f07dec0baf6385bb52733ecd40fdd20b98d97471bd2eb3e48a063f76621e9bbc027480e80675133cec1972d9792ebb90e11f6546349c9cde49e34266bf456ecfcf68a0fd7a5df020440ebe47f88918e193e0423f4ba49d929c92088465bc15cce7eb41006d588d6d0f67a8d3f8502b901eadafafad9d792a3bf010001	\\x59f95a489f3cf3ffc8006b6b466edb8d3c27fba973396fcb9f3a9d2059da226dfbff1ae7972d914f4595760095c40676af2d5938a79e5c28744278582d66be0f	1690011797000000	1690616597000000	1753688597000000	1848296597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x4ecf3f16d92e7c11fb9cf9a52b8e0ee7f3b507b4f59dbad0b8df58dbc275c4767cfaa68d591d58be94cc07bfda3a2047b6ca90dfa5141ab36cf85653aa50b750	1	0	\\x000000010000000000800003ef6d3faebe7e411a7ee3f9d3f7d17d9823b89f19bc6d1becaf8cc994ec180270567a38ec0c222a194c3d75c519ee02f03b4c8395324c986742c2062516556878e000d5d549945a962734a7dbc48e1ae0ce6865e2b83ef6867898918992803a41a28ab068f47a88d0270f61f0b0dc8f7a7326df6dcc7fb10bc3fad1cb53a3139d010001	\\x34028696748888d48b827162bc0cfec3ef7f2e2d00da5d4d97c44a106cf2460ea81c9531f0acbb91eb2e17a4327ee1fed10e1ce0ce653df2153f166008b7530e	1671876797000000	1672481597000000	1735553597000000	1830161597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
348	\\x5017a9fa1237035abde87f796983190a18d26d6c86984c3b7f5d910aca373829d20a6cbec459e6614b7a4166d5b376acab26ccadbcb4c7043b0da56ac3da9e6b	1	0	\\x000000010000000000800003be318717178f165db10e9edf489db6516099a1a3a0f9307015a2355c3343c9b2483ba8b36dba5c4829617c3e66f4303eeeefa49651ce72d884e7b37c027dffa2e77bae4148451531929120096f67d50ba8f3e6687cb1bf654cea20a09dfc036a5e876111c304c6900072b184c34cccd1e32eeb4756f1d9f38a8ccf2d72905783010001	\\x5cfbb04e9edc030d46b7101ec6897fdba3c1f779984981e35cdfb6730009fca2c1d2c4784d84199d6005da9eb9e54413393dc4f656537df0b7aeab5d988aa300	1661600297000000	1662205097000000	1725277097000000	1819885097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x52efce26b923ec8284f256010631a8ce4fa1718a0ac0714314996b6df43bf04195e5107c697bc4b834801879a296ebf7ad6c22247bd879f06d4431d4edf551f0	1	0	\\x000000010000000000800003d1e3fd530e08d2b6638aa889090aa9751f225a257facf483f5d4f70ea69d2a6aaab5b60990d65255706b0b8d29f2037bb0b100b5f16a4d2c49094ee86d8c916eb1f695b7c7be3fa72e95d745a584526477a62dd2a51e4ba4daa997107ff1a5678c053fbbeb09190436cf92dbb6fd36505a560aaf6df7e89fca08d290e1432761010001	\\xa44466b0f56e137e5b46c41007d86c8dcfd7fa2851f51ffe038253ae75b14459f39b787ba81308d7e730e695a4a3f5f0479cab58d44d97e6b17f7c74d106c206	1688198297000000	1688803097000000	1751875097000000	1846483097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x5a23fc4db119aa27d5c67dcb85532d2a0338549312e4bb0c83f58ec53d4d48efe922c0aba700938bb6082ea38ea9bd738a38a22c5ab70cf56941bffc442725f9	1	0	\\x000000010000000000800003c63504f4bce81e692edbb0ee0e7b8ac0ef108f240b95fb92883394d1121a7ba6ae39255d38c65d78fbff7d43b2801bddcb636d554a32143ae96cdc3b336039316f464bc2118ccfed3e839fcb2a16b80bdbf5715b39a4cc306241cb5ed665172c25b5484806ffe5f737cf6c7f6618e5425972bb73ac7fc8002cb45f6a99ff603d010001	\\x9f16a0d0c58b1ad3fb9c903bc39c14412c2edff598b82167e2af0857cb812624d1464ec2f1a002b535c09ce702d640d67db0d8af5c1e991bc5e008c79318a708	1691220797000000	1691825597000000	1754897597000000	1849505597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x607374b4a061ec82a9f8cb7e4c0c7036556ab5db49d20a6c4047c17d5c588cf66fdcdbf4ec1beb2caca2a28d137f7186fd1316482915c9e34892f5ca3ceddb04	1	0	\\x000000010000000000800003d1b5660c18d4ea68a6a7ed1eb1ba992893a291c3ddaec174685c377458f08dddff3248e69b2ef9b528096d6f435236d25c733ba89436a83615374a3c3fa6b2f276ae684f0631df64b55fe616997be3cbd7f68c0f6aecbdab4ad144df8db288c17398e58fbf4feea64f24997aa580282c7201eb34ccb9656f07cc9f3eef3eb6d3010001	\\xa5fbfe5dff36dad1611738a370ced52446b869629ea50e076589fc8f96a0e97decbb57dd64d90ea0cafc88366e1d9b1d2f7d418eeb5e9eb2c65e6f0a83ed9401	1671876797000000	1672481597000000	1735553597000000	1830161597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x601304d32bcd689e1425fe2f319d3e41c35096f42c8087dc27eb259e94aa48ea0d2511e41eafd65e960b88b04533a869b940b8a9c9f357ae844886b69dc3147f	1	0	\\x000000010000000000800003ac45ac25f48dae612d55c023fb2949fe14ce35f4ccab8787e615535b475934dcbf148ed5d9aa637935ba48acbe2b34f6cc9c9f874df501cb68e8a5c605ae383415a32b2c19b27cdf3201c1d72c17e91b6d9819bdd7ce621030893fb25ea0776b8c91389c64f4693611c1f4cb5515477dd851818d94b966944c630924d25b80fd010001	\\x8745bbfa9462cf0d462ec95f6f7c40a68255a7243609ae5e7263358d33c97894a74ba74293dc57d1f3628d3eef99185b679d55067b252df3b10660bd18fc270c	1667040797000000	1667645597000000	1730717597000000	1825325597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
353	\\x64db50aef2488575fae13292b791b318f3355952c304ce4c8f0f01faeb37428aad9221e235f8551f8bf08d046f1e0f551c3447b0cff369e0a45a5d0350d0832e	1	0	\\x000000010000000000800003d421e786c7afd9426dc41f536cb96e97473dc9b89ec4e5b4e187b720c7434742c1dc967f2030f913711f66f3adee6bf5c8fdf34e5d0f8337f9e7bde7fa9e51f99342c6f433d01c4ebd9fc5075f2e67dd81cc41b2f7b48353b944790f167885e27b897ad43c1fcc1a18ace1a9e0e7e716ab71e3aea65b1186016e1cc77d6385ff010001	\\x7dd98b0423ab3e08eeb4234f7d8ebf46d6a0edb66442d1008eb1ed5fdea9abad6063b01dcc741cf25daafee194d400387aa60da2f97f6eeb648664ac7f95b804	1667645297000000	1668250097000000	1731322097000000	1825930097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x659baec497ebe0a33d933423b4f957e410bdf1fe6087e53602aa0b39cfd2b7e3723a63bbc4496a3783ce5e012474be82c4a04f981437481e298f9d707445049f	1	0	\\x000000010000000000800003b82a0b76fae42d8b208123780db5168a8e61b4dd2fe5e174653f14fe9e0551e1ff41aef8c22f1977c596ba2639c27340cf92c87d39d7b5d1bb8360f74b789006cb2d99783471eb2a6101fecd5c59148f7514ea885f2e25289fc1d88600336ebacc5df5a4ec6ee377ae293c32f3ce1a2bb195aa081e9b1a26aa25dc533b538681010001	\\xbc1bc602df0ec96a90f566a2e1b6c9320197e01d34c56e2976d782edda84f347d944fccb20db21de8b5a3cb9bda87d6f72f069b9c1be827e81c7fef0dbfc460a	1664622797000000	1665227597000000	1728299597000000	1822907597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x6b67826f4403495796c0d00b89723ae00518bc7c79310578e7ead5e9ad6041ec353a4b00a9d0511011f74a8d7c2e61100339498fbba8cb65c26f98ff23e6620c	1	0	\\x000000010000000000800003b8110c31422c4e29724919d0ec4b5092216a25b922f9a00b5b14c6e26735097d73d60b4f122d79f9246fb3b3fee0a32f2411d3e7d061aa008e9e49ddb051fc8fa3557712c55846e2e8c5e1d30d60a8f38ccdd212fc5733e7dae7e07b8a1cf3efd208e449a096022262f603441c2d7df7cd371f5bd620ee6363c0ef3d9427435b010001	\\x9aeea82bba52b1cbec410db4c9e3fedd52fdef3549158e3666fd8b440cf6aba201b3304f18ca1813c5b59137192478677a587578f8ced1d24781ab34af4df40d	1680339797000000	1680944597000000	1744016597000000	1838624597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x6b7bab52606d3b8a6de7730753d69fb4724b86d8aa2d4bbee717c7d7ccb8c19d153f1f6f1a43a5edd66caaf0f7692ea7a616937360b11ed98b4233bcbdb30c00	1	0	\\x000000010000000000800003bf2c219833f50c687c486f93c392aa91dc4c6fe43ce56d073eea18806af703c14dbe5499fcc697527e9c0812feaba864da7acad8cf115f0680b0080f007fbd3ce8db7d3c232d7bd1bb8fa5119184febe8f24142d9a00062495c17ced8e135318579a794557e3ee7bbf2d52818b5c09f9a2f4e857c7956d1c2eb157f7d01e0cd7010001	\\x8298d6d1959ef339ea7e653c5a83eba5ed8c53e93ccd74caa5d5728c1ed70b60834b71e2085dda55d8a70b3e2f991f5bd4f962cae4da289b60107ff48e0ce80f	1669458797000000	1670063597000000	1733135597000000	1827743597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
357	\\x6d2bfe16e6078d6609c67b9b8e3abd182aecb2020fea0fedfdd84eb5050445b571fcde05ed431f59bd642807c10e61e6fb22218fc3ce83455b95657379b688ec	1	0	\\x000000010000000000800003a9938a75c49d6102140a8fbade6031a27077c9b0ffb535b2538bab3b67fa45e8cc5ad2ddafdcfe64f769440eb8f264b6d344faaf13c2d3e124e0ad9cdb34ab4d0ad88163ea7044be13bc48bb34154d83069420298c2aef07306ed35ff79fae7f4ffdd1b42b7be04d550366591f2c7a82c2df5de3289f2d664a24b2276361a403010001	\\x83b90852c3513ee19f8f224209e0430a9d5525f8bda675a27954a50230ccb89446dae6fc7da49e007938f65b4574206221177da720e6749322eb4058a2100608	1688198297000000	1688803097000000	1751875097000000	1846483097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x702f73184e80a70fe08592a321fb1fd924c341922f5d4414bced5219d8f7d10d1af0cb77b6cda5984548848a4de90744f08d3b012bcb648f36b466fac8c62a83	1	0	\\x000000010000000000800003b4f54708a3323ef66c0d76db46b14547bddc06897f770302638d75b18250849ad8b2873ee7578315e2ba50ef67d59cfbd3dc8f59e85937f7ff5f37857afde5aa066dda398f82e004088c17348d2b8a7a65f13e8a8cff71f8887fbcbface647ad59e729fbcdd94a0cd0642d0c7443f941da1fe09aad4547fc421dd3c8d4b23ce3010001	\\x51419bc2d8ed2dd559a6bb193037041d7fd3a852cf5f0c1668c61dd1cafa468a56229d143e2da3990562e9da15c3a7fd9586e97fccdc9f1fc680616cb20be30b	1682153297000000	1682758097000000	1745830097000000	1840438097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
359	\\x759f97c1245829c6a02a931504942f98861ac593650c9687d1105880f7c65399c2fcb75c583675fc44011d94295eb0dd051058335ab2e5f97357c608d1b46ab1	1	0	\\x000000010000000000800003c8c3771faeb349ee961b5e22982fff8272ebcd8571bdb79abe26b010c5d38b2df944baa502d297d07cde67b381c0ff0cecebf15448ede1018e69be79dab8dfa785b833145a599cfb259aa8b719f8e71a03c5aa343f72a0d2d5f3d6ff19fed1948ff5f3a109608e510857974bf8ebd1f65e2f4543f17996db3a27a3764f0b5de9010001	\\x752dd655da5d5c50aba3c5a8714f4f87903215bf1cdd2c51edc5e0375c2a90bf1285709fcf39b8a1b10ae48e1a53d2be88b4e521f938e559a50372e78a096c01	1667645297000000	1668250097000000	1731322097000000	1825930097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x786b02f2be407e30bd893fbe9867fd0541f0d4f83216bc29a04e9685332ac04b9d04b5be9558b5d4c80e56807de6882246fc95c93e3fd433ee325738b05b68c6	1	0	\\x000000010000000000800003950b48ec256c1db39742c44ca8c97d2402b1d94c14536a1a1e48542a5d91a3051e7bc54c5aedb29d1c98fed2f696ab8e6f3f9463f0ec521d5429efdc5b0de4c6e2612b49a171063e63edaa7f1bef91f5920891633f18f9baba477fee87371619890743c8f19b926e66fcfe4b5cfedafdf4439bfcd285e4c036ec01fccb239c7d010001	\\x6820c846f78c1c3c353fe41f1bc221b32f88c4e348a18bf97ce23e272bf4040eccc0a59093a70bf5c34c3e08dd0cef9c34660bd450c0e723ebc19cc40a3f6005	1682757797000000	1683362597000000	1746434597000000	1841042597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
361	\\x797379ec0af8611fc5ba04430eba229b5e3234b3ddf9d590610bbdb62ca6fe80f4876b3e2917fa0e71fa486826e133f1d92f38516d15bc37c3d2700d7efd8891	1	0	\\x000000010000000000800003ce95c3e460559b2fdc56931e9cf33d4b49da3d2475229b23712c7f9bd3f1c4d1e1576dc4224e73a821a783652e9fc6e1d30a42593922e2bb9c5acce8747f6b3a0aa8b6afc941047fa292f3d25f6aea53abd35a2b38f3a8977bcfdd3978c42aecb8f91cf09443747b0834d5114e65c48b5e802b97d62e4f4a814dc20705f8ac75010001	\\x97885ab9bc25b41f80019e675d1754663e48efd0c2e2cf3cbc455ae8c2ac93abcff2e55fad511fb2a560110b0cb4d99037da750d184c4cabf051b1bad8162500	1681548797000000	1682153597000000	1745225597000000	1839833597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
362	\\x790f61a3eed70c8dc7cd0a4a5326818d91e0d1773c645d510584190b73b07bb48e3011acf887d80cb1d498fe0bab6eeca85d60dedd9b642941ada29149c8d3cc	1	0	\\x000000010000000000800003f032375bf0319ef0101fa3e926184b2c18b96ab7fb99d8548215be0505cdb635bc431d1f7fc35fee65e349d63ea6bf7f71e8d590eef06e5b605192b179ec53bade16f8fdef1af2ed6749482ab5faa8013e2460dfcd523d372055249f09e44502cae837ddd11078507fa604b0d514a2d68c2abcd3cc53b0494b3fd67505324a2b010001	\\x3732a04d35151c31811ff839068a7c7df918a89bf889caebb2303e23a010d43aee951bf2bd5bdf81787bfea816cd4a4a8f0bb58a4fc38348ab4cc9a490712d06	1677921797000000	1678526597000000	1741598597000000	1836206597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
363	\\x7927dbb78a49f9fea509b7faafea9e36787eb06d372264f6b0ddb85c7e5d35b4120af4a1c2e74a53dc0da464dd1f7a4726f2671891c0b30b4b56a4ea8b1f918c	1	0	\\x000000010000000000800003cf2ba083a2eecfa348d1340ad0cc9941e68355b5b03c1852d4ab50207623ebec0704a7d485038d1bdff1c36633b4b42d3645923f76193da69e7e7d610a2ea86d0f67bce85216c8dc8983dd3010660601ed823a66dd54c6876ccc00dc8fb54a1ee65ba2e9fd27d2a8a72f26acb8476ad184105473d025b8039579e8698b444f89010001	\\x813427697828f19ac6e6e332bd89de286c24d7de709acf753b2082d00a1b49aae258bab87f67b443e866094867b36e3a37a444751f6bf74749cf55466db87d0e	1665227297000000	1665832097000000	1728904097000000	1823512097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
364	\\x7dc70d02739fb58c085bd2ed2ef749c30d59a21868a8d282ed07a0df37ee26ee3bfafc3a5568aa1039983fb54fcb83f8d6caea05a1a8209f43fbb163511395f8	1	0	\\x000000010000000000800003ae84d773ed7b0922ac5b80fd9aaf830888cf9e8e19651b799faceafe75aa6ddf861fbef842b7b830ea46f331552f6ed59f7da81124793fd9a8b4ad206b5a078dc5644c1d2bc3501fda74e3e041d060d3f929834409bcd7c16cceae6b91ede0484fc3646f3eb44f6804b8f49248dba0ad855646bc0181c987bd8d64c0d2516a45010001	\\x838ec554651b9f6872401114cc42d732f2f78a61cb05a22f674af9bfed7bd065c72413a9af4c55b7e92565b976d25b29db23d7923f0406accc0bdc147261a608	1677317297000000	1677922097000000	1740994097000000	1835602097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x81036f26476968c5c313f5f5cbec008c6fc555776b6ea130efee68062dc790bca15a6f9cffaf262771c2049530375a79c873481d4e9b5f4b8a33d79936a308f0	1	0	\\x000000010000000000800003e7b41d12ff76dcfe7c7b8f0c30c7b07df51823c87905f7f5c337b71444c3ffe22fd6db9e188dbdc0592bbc16914b7daf170308a54a9831ae973489235828d7a243847afccda15fb770dccfbbc44819d04c104bc02e1ddd6ee1a5c38c8776a8db1023016d27e1cf30e6f4e37a8ed280cfa98a00f7b380f7092f69c84fa7f00757010001	\\xf86df379eb0870c4c177d2ab5986baec91adc1e3d8f9aa06e855b5a3f7e5553bc2a5667cdcf61251620feb8b22d055a2b89aa47bb335277c856bfe81ecbca801	1678526297000000	1679131097000000	1742203097000000	1836811097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x86179add7b9c814804cba110bfb03a4de86a01c731e6d5957f7de3c04db258f9d48ca5f5cc0102e8b3bac3dd26cc281e15bb202ae84a63bb8a0df3ffd0ac24b3	1	0	\\x000000010000000000800003a994ee71f15d3d7ea01da7d67c08ba3ac74a33d38e24c0c95f053175bd955663daf26ebdbc536b274ebd52a99159be8b582054813ca8b6fb8fcd79251f526d463c82da5f5a0035d3908aa7d69bbc8dcde17ab950e0501a17fd64eb18233d3f6930274b87ed1402b1c3921cd13818fdabee749046525ad97bc1f92517f0d3b019010001	\\x1e2198525cede3cd439da02802462058b2b410a91d8a6cc6bdf3a4f4f4b1a124e44d8551b4775d10d3f56f5cd1ac4e7fed7ef79b876d37961c267b3d062bcc01	1683966797000000	1684571597000000	1747643597000000	1842251597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x89dfaacdd46e8ed3abf9d1957ad7d2d3a112ec31db870171011121f673755ca80ba815e03536f0dc5ee2ba4ba0f44e70bf79921869890f6b246376110b351472	1	0	\\x000000010000000000800003e97728c8f9749e8ffcaab1aabea7ed49be6e7a56ded6f09c67e5acdedec0d320e0dd2e5ed2a68a79df96b8e6f2a5db2e6b0b2b01205a59547f57bc2b67112f151ffd32ba27b7f57f11e792f3a48613b776da3509ce9998f5d33ad05360c9ba2527101238c3c58bff099d80c7a0dadb48b04b72739fb224080b0d54424e3b624b010001	\\x09ca5e9643fc3a3de075f322d2df10b5c0210b0bf541914b7794e7a60e7bfd3ba5641b7d5f147fa0a29cfc9972be57793e83f00fe26eb7591ad35dc21c714d01	1690616297000000	1691221097000000	1754293097000000	1848901097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
368	\\x8c23ea5d8f0003c9bee5b67e5b69908b54ef5466658ea46a71b5042754cf008a7d84051e51b193f0c1211440ea5e3e94e40237a4657f1421ac91cc5ffc8e2354	1	0	\\x000000010000000000800003be424cde1d4f6ba9ea6340351ce11e633ac1301f7000945db87c82321584dac45a6654dcb5c5b358f75abe1080ba42bfedcf0806bd5b472546deea420e133a054f29c9415e3ca1c793b6022cdadb164df4b6e075e1819eb3a11106bbd61084a8ef5475a657cdb5c36f7046f94b167a20437e038dcb64beb246d478f90b7b1097010001	\\x9f748104edaf85a49398162ff31f5ec87641526fd49040812df9b2a3ce09b03d8be434c74659e3901d9d39c4a211fb79fb40929cb450edd3a62a90856cfa9403	1670063297000000	1670668097000000	1733740097000000	1828348097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x8d4f7518842161813228a3d2a17b21bad10b52d950be7b6e733b6315ea9e5a8ad734f6156cb6e91b71079ecba6350851d22227a6c6496dfc9b70ef7c3e1763ee	1	0	\\x000000010000000000800003e531851136c43e7bd8422897e36041019203065999b2e79f8afd12b20e779c4301298f70ac2053a03ff1ebbac3c1491bb88db737c7d06731942bbe8970494d0b2d5b106ad9349b871a5c644195a3d0a7d57c26f598fe1b3a8b1aca8569b385d0dda373ce221e7ad5621a7fd1832c4c18342626dd8df8cb715ac9bc739f14e857010001	\\xfcca48476c5dd2d6add3a021e5bf5c5f4d9ff466c8cc4fac160f61ed9207909945b532d9df2214ad3b5c502b67eb9f607e86dd37af5bd4b2ddaa208414019c0d	1675503797000000	1676108597000000	1739180597000000	1833788597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
370	\\x918b0cc4ad33cada219916772f810fb8e44a6c5d9727d1ef9e0c4c58431cdd68810cdb34e695e8f562a44387aabeec2cd3b70ea74c6978e2b6c96db5e948feff	1	0	\\x000000010000000000800003ae47a45ce7a55df3c4ec8ee1aeb97848c3278c53c554069b7f81806e0d27504920834a21cf869d8ce90aea764cad86aed71d6efa89eb6a22e6f5818b3006888ee3e0f23aeca99bd653358c1b99a318d58384c4c14ff5c702767c28e49060de32d7ee026d193d2a96242d3df7cfa1b25f96cf4c3f2e7481101af7b47f7193795b010001	\\xc600ac0a794cec299056ddcdcccd1c8d3eb0bfbc1c48399adb5a50fe460527f1db61d3502cd224770131cd12b40e188459a62a60412af8e320770fa052e7c404	1670063297000000	1670668097000000	1733740097000000	1828348097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
371	\\x921bb3292343334a9f98b01186a0bef5f465ef758fe44c5f6fa501b0ca592a413fe0d7d40fb15daf54c39c89724eb12c36229b47b19619074450a6d9cf876450	1	0	\\x000000010000000000800003e215a9f26ae338fc328c2462ed86721925af80f45d5a39111d54898da335c92931c21cd3772bd86ecc8f2be53b57bb5b0ff032e4e1620365ad87560dce438f5b561df9e1276b1d2edaff7da897eecbc3616b5870987fa36c76b735c3048b68bcdd77c874a465536c3587172d0229768f313c24d124653cee8ac8ee4525c7fe09010001	\\x224fc63b7efc8683d6c8f72aa3669e30f637675690e359d310b2e8d20c35e7efc5c7b00fddf93c0faf58dae98341cb59f34514466385ea6cdaf6031cb20f7206	1677317297000000	1677922097000000	1740994097000000	1835602097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
372	\\x924fb7cde7565f982c1d1fc36379e035b04c7a8e013a3241079413cb7c3c66b55ff77050bb0010e3a2facce5d4f8baec2ebc6ac6c1d24673acbfc22b77138a63	1	0	\\x000000010000000000800003c721c14f49f43e33fe8b44d16bc494cacc0f19b597e0d00c5bf0e35ec5f99b3ebf9a3494f276dc83355ab65c08d6898887a9b72e7d58b411666dffbad1579d12d6da1c9bba550f35c6bc8f000a3a260599f048b5a5b03b726409b540884935f167b0a3fe404de573359c93fae3eeaef4ef7af76623ad4544b6e1e4092226ea9d010001	\\xeb53eda73fde7e373d1b6731155cb18064b1b1188f6722edc7ee7f96711430425152314dec668b0f703c6448f17ca030d4eec88d17ba79b59fb9738b95138600	1665831797000000	1666436597000000	1729508597000000	1824116597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x94b717e7509f2dffaa2c85202b6b12d36608e5f88b32b16993e613f64bf7c0040425100b81281a18ef1d6017dd93d95f1792d7a1734d2ba3793b48b3f1089dfe	1	0	\\x000000010000000000800003b985b608b4bf87a8f8eaf1ce65fbdf14e918f3ea84e3df881e54e9aa823eaaeca44f8fe5db8263d669d61669796588e5d5e2eb705b62a2d76d2e6dd85023a08e292deea38d92906568a69600040abdfc4e6b5fb292a105ceb5c416d7a41807f756e0af683b6d01bf3f8a3924ee1e21a70f3d7927ea5903c3beea38d8fedcfb01010001	\\xc9540fa17aa871040bec28c320a8dca9ca9282a1599e0efd43d8d9c58aab410e0aefc60bffce1eb75bd0d19fad6d0d6d4bd64450954dd349339beafe8a2f4703	1685780297000000	1686385097000000	1749457097000000	1844065097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x953f272feb244a896241be0eef74214071a86c78e9f4dbd7bdec5e04839266e69e0e106834c27e1eba9caa0e07377a1b4dec5bc04bea6d7a71deec3a3bfb7fa0	1	0	\\x000000010000000000800003d62c9194874175c7e9de90885b60611db1e190581ecb55890a2b53c0482f10c24ee89974b3ed927bbe23ff2850648f7fbdf51922b5341c81af1a0645995b4dcb4d7cbdce23e4b7f233f0a0df093f219964c07eb81ba263449e558c80d443d479708a170be16b54b65a7cbb16ea73c0b8cf682772eadfec39f7732b848eee9529010001	\\x05c1dc84b18dac95f1f82ebe256588dfdc924a172b9df652e6dfe1a74e2b14af352eaf48926c1f9d4aaec27eec11a31930ce21d1e69df548185381d0b6131406	1669458797000000	1670063597000000	1733135597000000	1827743597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x98932a7508151b628effa1d1d16fed66fae50b42c946d24e50ea0df48a93873df8975f714abdd0f803e3ef5cdc73cda75f08610ce8f1bd4da29c7337d0fe7470	1	0	\\x000000010000000000800003df98ac40b0ae1f2f0aa728848c97eb47a339eb40d7d6818905ef22e9fce862d11df92bf5b06ed9a9d10ee733ba8c87c7f6552635b8bd0a8e45d0d190aaff86b7b2eea29a91a972a1742145b7a789e45b175758a242b18b01c3f07366a1b05289db1a81fe5322b53be34f2e285c37ec9f4077afdd4f392ebb0e149d598cdcf925010001	\\x88dbf2e42f25401128e0a0d44b28aa80b54c5dcc1eeceebed5e2f0b83cf137814e29b5b14b115fc15ab37c08f0e458e09849e72ac7ed79c42ff4a49e4566f306	1660995797000000	1661600597000000	1724672597000000	1819280597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
376	\\x997701f088e4288cb3cca1cfc38b2ca5bafe6df1d8acf24c00bef28ebeaa3066ca9f1f63b36e6f83e6d6bf95236e2817df959304c4fd42fd8e35c55418be8de5	1	0	\\x000000010000000000800003a1302e57c97bb5d72dbaf45cea82ba3bb6e967ecc71d9296ecb8cd014574c0be22277a4eb3aa471624e160af8f10b4a6dff0d2dd3dea27feb143b074e95f40cf35f64dcb9669bb296447547de23b4993199d0a1c034fd46ee11f53647a520f870ae75365977156458aed351399e6b2f6026f2822946744d5c811e55e759f04ed010001	\\xc6bbbf4b453d21ce02a4bf1b7aaba437f338886fd9f563c2e24a87ad1bf1e834557b31677e6dccab31266eec8e9c7fb715197e6ddbe7a633b25b49253a48b40f	1677921797000000	1678526597000000	1741598597000000	1836206597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x9de7c9d341d9b8482aff44003ac1c4ce4b16e62c2ea153f7b09077639f78d91c22dc511609bd573d6234808d744632165d8ec862d62a6910d50fc652c1f90993	1	0	\\x000000010000000000800003d790aff6d63af2baecb7a340bcfc30f4ae255c161bb4de891cb63f0c48cae4b6f7c9b1fb8deb3251ca067a72e47a9fac18b9495477b59b9ed385b1983bfd9cba61e0ee0d1639c26510e3185c463171a9e9c6a356a437a3de4792e87a1adac76b0d5e684115fb93aed6f4a78f4f3fd9bceeb4a8709783b0528f3f3210d14a8419010001	\\x7df661b04640ebba1d847e587bbc73368b2ca77669f0f10fb3128af0a359552ff665731a9d31fab0e279f98e9cd28eb05b6a6cafde36d6c98580879f54f17509	1671272297000000	1671877097000000	1734949097000000	1829557097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x9d1f9ce3e5d19a249e576091a38fe2b1ca84239f511927a01f446fc81dc77f6623d8e35f2321e962e9925b463b0517726947e1837b4ae617899db5b0f1d74079	1	0	\\x000000010000000000800003e9b5155d8aa16e793d54eb816bac8a7d3f96ed28d403df3472265aaccf4e46499bf8ddc861c6f3d19e9fb5c2f720e90b3b276bd640f4963400a7fbff2c181b8521bca6314abc4d4ae5e7c248a8952399f0d55fc3777f3f41f18a3ee05afb275139f52237fa140a81a13edf0a7626c5f916a292231684aaeca82428ac1e2faacf010001	\\xd3b36012adbe8c46501d0f5c1169b0142ac2c5018426d3bfbc3f90f6d6147509e1be96d4cf93d0a8e8ff5801b4dd8118911a5b7a47937e338b88c73aa48d5c09	1662809297000000	1663414097000000	1726486097000000	1821094097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x9dcbadf92708db7ec8da5efa2b607bcb9ad15197949b637eee821625a45a368c864065a330446ffb2446610b103dd6c823f11296dbff3a02ca2152344f94cfa8	1	0	\\x000000010000000000800003e47d516e6cb8c5b23114fbd75c16ed1c0f48d4e09c25a95f3c9bc11f12f245a036b13c3c48b2dabcb213a0cbe5db400951a6a1744f5046c85a7d8c1d7919f4d0ea378a5affdc1805ebcca34fd6bdf9ea68089a69d4369f21834916258b1998a99f2509f28f9bf5426095e98ead6d318af0d3c53e61fb9298d83e9fd30a58c5fb010001	\\xd9f60c34e6af7920338878d40dffab5542931b3ab3616fe950ab19e5abb064bce61f16c3dc71a9fc83b7e7fd0689163b289d834ded93f6e9f7f08e41ff168200	1676712797000000	1677317597000000	1740389597000000	1834997597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
380	\\x9e1fe8fcbdaf662661851b28932007cae1f4437b911378cd71cb3bc5680e2dc5db01a35c6fc36e05f00f3fe04942faa0d22db3a6ff60d093349706c7b814b8db	1	0	\\x000000010000000000800003e07dd11e2b239553b6b58441f28f122934157d1957d7464c1d541a003015585699dd2b53f6437a9969bd524038b2f4707f6e6def1a28bb6d1a230058a20eb50368a6467049cb4ebebe7f01c737ba4549fc898500456de2633df5cdd685262c0197e148363c60fc2cf3f6a57514c3af7ce47952be7960c4a5986cade7025f3bfd010001	\\xe93c7ebee20252e2c0bc682944f78ce29aa3a03d631170fd41fdd7247e19db035578fe3e158f2ad952653f752c2affd909bed2d2c91532d6259d17cd52c68909	1682757797000000	1683362597000000	1746434597000000	1841042597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x9f7b5a6450ace1602b1720bd735e4022291b0b4f5bf644c5a8e7fabd60d98e7109a9bb866abe14467227cf6d6ddd93daef1b9b921bd7c740bb095c95630aa271	1	0	\\x000000010000000000800003c113e982ddf32e359c78dde77bd8365ac9767b7e5a81bd3fa2e6cc4da87b858a31021ea947907994cc93223a8fea90ce598fddbabdc9ac366a9d8fba36c26dc3abe413f7b35a87156bac19d41583ae38df63ad78ed55f524ebe22a144f41c114e8c1203773fe41856d778e7de528b9882bab7ed748cc9624ae598d5a3098658d010001	\\x54475916168cca7d4abf3558a92a2b881565e8983beba9a0f5a9988dbed144c667482f43fda3471b3a24e556e0f33e86710f1892127309f9cc45c49c3c3cad0a	1686989297000000	1687594097000000	1750666097000000	1845274097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xa24f0503d9b968eb3541bee68ad669c73990fa5348cfd3640dbd60f88e8d40cd4d311e1f9031383633ff39cb142c8f29408a8fab900a8ab9a52c434c6e9755cf	1	0	\\x000000010000000000800003b45403f7bd430a471fdd93a2fdddc0a939126d3cf5b98eb1dfee6181ba83f57af4f6ba4b8a4e5ddb6e76876cbcce06ddd61590733cf59543aa7456da905e6277cac1a81abfe2938b2564db887d180362d6569c02b2b250b17d3812799a05ef4d43197d7313729b57d8d5572ffdf876bd043d7644e2998978c59ec863a97db9a1010001	\\x4c4f52747c6d6b91329690c69e3acfaa2f03c18e31a556a4c568751b6b8eb55717fa7113862e44ea6685377e18e707bcd0ecc49d1d10f87fa8b5489751f1600d	1666436297000000	1667041097000000	1730113097000000	1824721097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\xa4a38e35fbd6d5135f46105ac2eb7b59614970036259555315047f23c008e994b5cc08e7d9bc4518fdb0d8b3cb34f0fc382b881198c977d26125891fefb9f7ed	1	0	\\x000000010000000000800003d549e2d138b96ea8ca208eab26c2e5b447ff561caa60d7509ea6a326e336a6485565205b70a119376aa8ac71620e3b2c4ed86895c600b6bbe4ecc4defd7cdfa3db3b34809f8ec1415690b12c6bed214b2ee9e92fa205dd28de6c5e0e6e32ffa5240639d082193a9452f656db5f3dd63f120baa6b2cdfb6f7ce7cf7e4c1edd29f010001	\\x4e354b7f28c9885c9a92f248c1c721340fb07284e05a45d1d091334c3b7855d5159d97abc9e42f8a5674bad604b257c2d1943f89f0a4300cd4606d54e4b0ca0e	1668249797000000	1668854597000000	1731926597000000	1826534597000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\xa6d38234f31eb5233e171149f8812da10815db42dedbc54b8587196a34a41e27b1da86c96e133ea46043fc1a9643a32be31d6c087b4786fac0b2ad0f3aae0323	1	0	\\x000000010000000000800003adc8c663d61bf390e27ad245c449614e3e836aa3ff449173a7b9cee9e0d7cebbd817513a8f3d12c5702d4a80365688cf0b4a29f2969a32523ca56bd79735de76ccb4db5f94fcd06a8d82e4bdd263c15fb0083a97ae36cf1e745835d26ddb761f3347512662c3a6b8acbc4ac5196bf3eeb38c75ddcf0bc39600816813ba4f6e2f010001	\\x39ddde94a235df88f0dc767b11c9978df7f10a952685f82a5ea6281d3205402240586db6c4cf5994f48a830f78aa082eb0d191730d5b2d685b6cf913aaaab30f	1665831797000000	1666436597000000	1729508597000000	1824116597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
385	\\xa81f72994dfd7ba2bd9da0ca3fa84cbc1283daf5c7baedb64829e9a04db4e6fa75b6f8dd9aa30fd7c6d6f9f0288253511b1c9b5388ceedc3122760f5410b4a32	1	0	\\x000000010000000000800003d2caf89839ef0eb08c764fd4b77656d3f11d324ce5a31ae186895878498bb072b53fe91ff15e752fd1ab606e309b467f2cb3042a92744ab0275112920c742eff7456ec6a7fe49241acb3d732102db28bcd460988b53fea934c9b5c6019cc1633c378d39e8e7d0603d34c8c7ac91c9f7cf803494b036e33f34e77e87eb3017e3b010001	\\xcc5d4f6de5393f10f7dd76ba06ab63b99786d252f24d4320d2bbae51a90cfe62bdda1ba942bfe19c210cadbf8230998bc8e6065f2bd5a3f6e4edd90e9dd7060b	1689407297000000	1690012097000000	1753084097000000	1847692097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xa9db0848a99c2c2fc3aad41add648880794225721c5c2bcfe69844bdf3611c9b6eb80b48b57404d175cfefded6c287cda8dbfd863b39c4166dad5aa6ed46e041	1	0	\\x000000010000000000800003c6cba804637a886f469da35153c42c0f2502738114ef76fe5f6d95fc53bd7b63fe0dce6604f81b0beb281acb91d2926a0adeb2913472422acf078103a60c79e61ea370986148727a4db0f26a7123ad7a0dd0be971feefcef6ca6cfecf7dd24ac22095f2045cb7d2028dd86f97aacacd8e13cc585a7e2d61c55d5fb5bda125aa1010001	\\xcaddc85bcd1312c4b55fb51bd4022f2843c133acb1603a3475a0257da9654e94c610050aead1e2aa8e85a7c1ded776b363b9896da84f983c33652c9eb9d0db01	1670667797000000	1671272597000000	1734344597000000	1828952597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
387	\\xac93451967ddfb850f17cf3853d9ce384273f988e1dc1863a553ca05bd7504b4743437efe7d2a017f6206240dfc213bf4478722cc93e726f8518cef6ad8353eb	1	0	\\x000000010000000000800003d282d7569abb51dcbc54a6a37815641d636a6211a71e859816766ef835f484d58289e615a95ef659d168bb70f9643a93271ac3a4758fe0eaa0b2f67bf48b1288a96b119084fc5fe65f73f9294711f5f63fe76c9757c2c70864e80207735585ca73f81102dafefc302e2e68d90f31b536fca92de6685bc89d77af5cd5e488575b010001	\\x2f3056dcec7fd827e848b78444b3c2e8e3c88963861b1598880a00ef9197ab257f6ac6587e8f4cf1b63a3edf687dc5ddc776f33af3610db3e3876fb1db40320f	1664018297000000	1664623097000000	1727695097000000	1822303097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
388	\\xad73910c231ec91787590c1f41c323d6ae8443492110f1b6389f8ee561b5bca7b5d4e89b47a7960cc0f77e39ca1ff33b673254d62a5a795ba1ae5ba8bf7cfd24	1	0	\\x000000010000000000800003d700fabbb986e7318fee45df52ced9427e957b28ab253f6f737079825552c9ce831ab79a44b9974fe61fbe7d8380c52443966a9946306bfec025d18e19b5d3359c57f87fcfaef72fd2ba5bd9378326fd9c90c2a9b7f68a2281fa54571fed4cd5fecdfd4f96de368731b882ac33f1f399733ca3fb8caf1b9cf2810bfa7326eab5010001	\\x53f1dc71b3d0d963cd71fccd709833d33cbef66d42146855aa9e6a97cb63cd07cc9337272a70c2f8c77178721b389e7a4014d3c5a96b6cf1ccc3615b0ba0db0b	1665227297000000	1665832097000000	1728904097000000	1823512097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xb11743da9ecc3d4cc64ff826420564fa27f7229e64b38903575867477fb0c6c20b7cbd3fc2ae9f8faebf225a180f1753c311effdd78a4bb397015fe992f413fa	1	0	\\x000000010000000000800003f6d6147c55d4d437307474dc5b3128a1155bdf3c3b9f16bf0b32429b0309ffc0569e6403b0e97bcf0959f3837ed122571c8ebaff840752fb5804f3bc902f4f949dc4cc306c6a196a3fc28f7e06ecd4b0de2db87f7a2d5d6ff7849b2f2c25cd92f293d6e0d743c2f79ce172e2b5313b68bff566a6e0cfd17fff33668801e26e79010001	\\xecac0d77fd3ca558e7cadd1dc580752ccfa7faa1bd24edf0053a7872ad43f1adea96ca60c07f4e435e8dfa7ec483e55c517eccc89dcd60689122b21458fd0d05	1681548797000000	1682153597000000	1745225597000000	1839833597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
390	\\xb673ea26ab14fca8859b6ef8d57243641eb8dec4fd246e1d04b8e48eb0e52429ef078757a3504d88149bf33b12b6dd076152f51425e6636584375c22552d4be0	1	0	\\x000000010000000000800003d5868a2f9f7a826c024cc10276b8fbfcc2096df97d74132fbe83579027f3a7862eb0b9909983fec18b9bcc56350be217e127d7d7711792317fb75d7385da9a304713e42e5d4793f10517d51d5155c1375582b56f56ab4f98d739e18f9ff14b6a8550ded6ba2b3a30352701ea73542ec6f39e422cc2fba2ada722b7e1d18fd911010001	\\x802025b935a8aa38b15dcf80e3de3a90ea447cac8f75205144c4fd81b6344a8c2fbbb355d878c9d2a581ad7b6bb52b8b5df867a893bd61089cf3827cca77670d	1662204797000000	1662809597000000	1725881597000000	1820489597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
391	\\xb7f7b7d22b3179bd68d72706adaad8a19d5a88116dcf0a5768be6b5ad38606fa5912f3f34bbd2da29729a9cbebddf02ba759fa57eb1d2796e04a7ce91725a7f8	1	0	\\x0000000100000000008000039d988c54f978d45c4b50d935febc42df972644e448d2635434882880682fb83f7fc2da0f047e21803fe42df249c602617ce040307b343bc567f282ece40ddfb2faeb3ef9a512f072944dbf5cd8a5f70b6c4edb08efa5b28c6a9aae55c209525656c9c8253fba276fdf489f02e0e9ebb537e497ec34518dff4066fc0ca48cd8e9010001	\\x89e919bc9ef663865fdf6abd38f721497f4aaeec038c169427bb3397e523f9a4bdceb70efa4025e8fc6ead48939b84aa68868407e84f09c7bacde1ca5a2da001	1680339797000000	1680944597000000	1744016597000000	1838624597000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xba6fbc1483703bc68dfc3f0fb19f758e16f0ceb3d9d5d7fe0dba663fbf84f07c1701c01c7dc235509556f5a23c06ac1caf03a6dc7ff76f2fa43cd307ab005d61	1	0	\\x00000001000000000080000397b98538e4a9bc1ca2286c5014743ab36a53a52019e4d33017d1471240ced2d423971bf7d0688aca7b56ce1d3fceda62cf7cd76cc18e57b57056094f4ad18e2e6d79125660ff9d0f257cba56576b9469cca5726a0af5eb611ae6af8cd6124d4b28427d5a452d2d66ffc3df483279b132405ae6983d387988f156b67a38e68cb3010001	\\x5d05cb0af92ebbf626a93f93c5d1c9c326aac0b98b989472ad5fe7fe22653edd7ed2174b8d0d775ec75597c8d834a5f80b7c30e4119765920f3bb08a79411e08	1667645297000000	1668250097000000	1731322097000000	1825930097000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
393	\\xbba7926ed3d4ba7568e071877f75cc0c6d78079fc812c17527f619899040d80cbc23fc4ba009615b2a507830d91f52b292923aef5224e3ffb59c3bb6c451d4bd	1	0	\\x000000010000000000800003a773ea5d0c139f72998b49ec2c7ae1159c408f38a5d5c6fed7f595ae8574702c4072c82659ce6d34885f9c24a312ecd3078569acf90d457944313b53186058dd5eb69389e7ec4cd7452a711b68e47f444b73b5debcf04e2ac7e9f1b858f37eacd218f74e19853851854baf8d5dd2df05cdb2656a8494f5b79c983fb87caff2c5010001	\\x5fec1af9b77a48b870a2600af378779267ea37539613bc33f7f91a3d7bd6794ae8f91ae90b2e9e18963150a59ff0ef6dfd6c7568c0cd147be267911266acfe07	1665227297000000	1665832097000000	1728904097000000	1823512097000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xbecb163a30c4a387eda15adc193f2243d771cde038d16336a3c86d7a2452c437c1788bcd79d45645ffdb9c8aef376654fe2720111f203e346e3156ec287e400e	1	0	\\x000000010000000000800003fe368774777fde40f800905ea3e7e1529f22f588d55808cfcff58a81f3c17be299e019406034f0d9d2063808f1b8a905cc4607f1f6959b3776eb53b0c5938be0c2eaf2f459611f00c72d614b754766d9ee56f9b9da808780f760695b90675188016eb1abf8fd553bf9b69e86d49528a55097c92acc5fea3ef6403e21bacfa80d010001	\\x1ec42a84b8b0b9670aa9d76a478a62b7e4fbd3b8ed90e35bbc8112f58c6e757ca14c6d09fe9107ba86f818f7c749874a70b60822a7f124194a5f29d5ad489f06	1676108297000000	1676713097000000	1739785097000000	1834393097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\xbe179b0536fed603e1fefcffa7dc857f0f20e4070e9bd9bc6c3d1eebe8599ad8fd2bec78741c63993e13ea213dfd33b3f9e03b977060ab6d8715702a753d4e13	1	0	\\x000000010000000000800003b2bb5bdb418997ef98f8b6c0a105cbd1299e5c7bad2f9c2cb7d6c0be9796f0cba3ff5a0358421aa74ebf71df97a3c193bc35c6e8353f232684b8bd40439e3c3cabe0a778d0172e22ff49da7c22f7bb36b522d36a9851267f9b471a70f79650f061609b9ffffde5d7bff7adf6c5866287a940ae95c8e4a9213699616953681497010001	\\x542accd0e134240b76f4f6c518be107bc919051e8b515cc31c5df14d205f1e45f18f0a57154e7ff45a8d3dbf4d5bad27aec534b3f8c6317d2029651075e3f20f	1680339797000000	1680944597000000	1744016597000000	1838624597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xc31b8ea6f6b8ed8de69d76d649b2fcd4e468d36bb5be3797fe6d70e5037b2540fc380fa39080a97d99be7529a2529c481efa1273c7c5c7490ef89005f20de65d	1	0	\\x000000010000000000800003b7e043789c3d713f5a4a6f212fa25a906bdd203e04dd2030901a91d7c3e24d907b98001967b9b3f8f32dacf0dff2230709cc16607c642eede383503be9ff648be7c92168f6db1fe6d329ce11600054fa0ebddfc878ddaab66b587eea5aae97feb75a8bf7f4d58b343f8a428bad23ffaae72d38155783f7e3580b128588faa137010001	\\xa5ad565912fc3dc6f33ad192835bcee70f4d21c27604ff67421f35fc8d6268868bc2a58502c19964d91fa622fcc89798c735906f61d70ffb27f857a1d96a2702	1675503797000000	1676108597000000	1739180597000000	1833788597000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xc457159c1309199e76ce66bcdf04f96bfa5ad454a3fd96fc29dfe1470b30bbf4a4481af678f1cfd42c36e83e6340be54581dd3f49f7b851d41c9b90847f90847	1	0	\\x000000010000000000800003f97749da0b2700ea25ee78aa4064545f319d317261af45a5b9f06088bc547e9f991fe09696487c17a9ba07127902ff536873def30f19b9bd0156aaee26fcee1203bcf6a83617faa4a98f641a8b005cd27aedf79890aa87040debd56c967e752220101896e7e1d4130836cb65cc426ae25530a8d5d63a834e7938bb488c0350b1010001	\\x038a07edb254e959384b3049b27e5d3b7a7681d910286a85df47f0b614e40914b295da2b04047c2ff3cdc12e88fe4b103c164e104b78a16d3894664bcfab170e	1665227297000000	1665832097000000	1728904097000000	1823512097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xc9c305c0b67434b0d38f31bc6cc3a62e78dae9a3e391d345f4ac228706d5b3995c9dff25a8c9568aba2b8e5b37326a53483f361f6bddfa127d4a92df4fc1b0a0	1	0	\\x000000010000000000800003b4b7a34b3b527f6355e9c33373833a112d85b012cdbb70b9d0667b1e8ed52260571141079e9bd47f3a9f15995e7396d519ad24c22c8aa3246d9f95a82f6fb230869a376e2d947ca265321857274c28b60289c3c600808424108885bd92dddd6421f0ef2959cedd574a586cc60184b330a218218e8f32ef4f03e0a824f2ccd8d3010001	\\x4dbd69d246e9d3ec977ac042f1728d98176b8cb62dfed51b9661dee3706ed6f2c385a00e9405afa2951f26540a800036a2fa09f4e791d1552ee882851474300e	1682153297000000	1682758097000000	1745830097000000	1840438097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xc9772aa9f5a888b06e817543caff856083e82e3cde054271c55b79ce12581b0e2185f221594aea621eb5a1a8ef7da78302401d3fdc9ae8366f09234234e3a41c	1	0	\\x000000010000000000800003c5f64b2512b34c544b86b482056154cf07ab9965ee2a3ba0f0f4e7356a9f4d03551ae491ad5ee4d7fbd7f1afc3ea72fd6209b0f59e89b853517d171f921e98ef4ed9f3249c6ddfcf7fd9d9ce75820b3e5926b8282dfc586ff95f8b334bcca23ce252c7c3e05de1246aed83ae73cee3c9f345cae26ef489886ebad9cc9e5498dd010001	\\x84493fff7affe0e52682dc7a778cc90fad1ae648205a180145f4b037419a92f5ec2d3e25bb36ed749dabafffd5e970a561146d9975826a405a0964268350150d	1688198297000000	1688803097000000	1751875097000000	1846483097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
400	\\xcc1fd9723a349cf2a866c40583445792fe86d2be2e63fd5786e759d9c44d6113545e22d6fe21bb3e6b255f1ec030148e476c81b5525ed6b9caf13a024831f4e2	1	0	\\x000000010000000000800003eb78ebe04026a340d917328625057d4c2cc50bdf16e30d532ff8ff88be944935bc9394f660e7f52af9f0fd4af84c5d46332da1cce49690912e1f73297818a3715e10f30485f0567fb76aa9a19e249371ac1ac7ee034bd0d0e05b3ef10a825d4a7173fa95f869e8e4d1ed93112f0fdacf3b58b9293c2c43d3e428dab9cc9e67b7010001	\\x956efb58b064d2261d10ea57031756a8cc2e22ac646c3e40af3c526bf97cc2b04421fd31f2da3b183490afe8ebf33db0f36d986f0efb44bc3345b90cbaf9320d	1679735297000000	1680340097000000	1743412097000000	1838020097000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xcd53fd4aa0b9bc76d075a7ed86988a09f169ae712cebfd8ba316faf2b9eaf32b674fb9870d41699c15d85cddbe88e9c7a59cbd93e75bc999273652da87d981f4	1	0	\\x000000010000000000800003b26356782f4dcdd81233e88d76998ec0679324e7273e487de4d4d62a019d467f218fef50da75337d2166b1cad18824094a3767ccb4391ef34d54e205d795e7bcc073ca3b571912de52fefd1b7c74cfc6a362614608eaff25ec9e4d9df9de810087e8922fe07341a422d106e7d9401af9c8afd8aacc162ef1e2110f2bf5b260b9010001	\\xec48792aa2a4175d0d35992f673aa8124c49a36eafec71a39cdfd0a7c9cf4c1d7741709f61f8cba9740676fd04df9fc284bc5ef23d37323c4d2759dae311d400	1660391297000000	1660996097000000	1724068097000000	1818676097000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xd003dc972c23718dec67ad1023b9d6ddf5f3e950a88d8375da6d244a6f5a2067f9c6040eb8808ad0b4044e41d84c39bc45e6d9e78b90af0ec3001d058e294fca	1	0	\\x000000010000000000800003d3d3bcef6c78792b722bb8d719b1618aaa69204a7f9f2c0da588c879f1912a3e50cc7bff2927fb99614e35a697a30f88c17b4db065380458b68b867414a5b91ab1791fc87217329e723e0045edf8363c58be7589663a1b931944a6cecb663389c6fb0bf36986b8487b3d3a9c14af43ae50d566dc9b7d5a93edb32b3aa7b17813010001	\\x95bf16e9a57a7c23e58f064f0993cfcd2bf325dd510fc8aa2b3d8c2018fccfa1b8537aaba2cb662bfe6f9857c7817ef3c0ba244f5a5e13ce1f662e438fcf6704	1685780297000000	1686385097000000	1749457097000000	1844065097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xd04f09f78051913c0fbec246be272f1339aabc18561b3d2ce114a2e10f162a8624ae0682c67cb6217ed4926cb1e2e93a2ddda8a275dee77e2b6c4718ac70c30a	1	0	\\x000000010000000000800003edb09881bbc3b69769bb263774ee1aae3d695ad4c350f63b059dc4f534778f5b18f98be84c462808ce293c7aa672b6e6f271b22c824a12bf0e767f40c782e3643f4a85862f529c457400a87837ba021ccbf69244f209a7b85b3fcf09da98cf928a875965caafbed70d91166011e4f6b99bfb1ca909d9ddf651d948ebc27e7a2b010001	\\xe39735a95287929b94cf5a1ec0e3ea67a70a489bc6963465432b378a49c144186112b4c46683d9d43fc21cbf3d108952ec549bc27fdb542c2d82e8908b98d40f	1684571297000000	1685176097000000	1748248097000000	1842856097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
404	\\xd35f988dd1df92a7e13ee19ab4ebee16f463b5d083c0b217ee42706f730286d99ed424c5b907221bf16590e5016c5c92c3bd32ac6476bb11e15bcc4fac65e435	1	0	\\x000000010000000000800003aa485def1a90f959aa3e2e8690fcd5208190581b4d9933bb624b2b3df72c6749b65d2370744e4a3b7dc61518649ea6e05b7d61cbbab6969ba07cca0d2430f9dd2f81a85a6409bff35a412f4783bccfa38c030c1b1e97e794de51ca4c32285c6fc6ec66c68a21ef36136b32052e30542eb6f47fe032bd80dec7e6f476fb1dc253010001	\\xdc8f780942e061b255cd9f6eb6e9de2335bac0f8c6e2d90c7491b1ba59b030f76a1869e29296c22ac6f122a302fad141d96f046b2536a9d14329bdc7ed365003	1659786797000000	1660391597000000	1723463597000000	1818071597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xd8274d3b9e3f5be6d99ba43a251528b962bc27bca0411def783e9ea9e38694a2987d262a95a3ef6a71a284e3ea564e54ffaf487b6bb087bf69a3e67210ff322e	1	0	\\x000000010000000000800003d1c43f37ad114ba023d647dc68fa7c11d28aa6f2c908f31d7fb967e4a0d4a0a8a813112f731558dd2f5e1bad471901e5d8190fa32ffa4e01c1d37451cf156d7592d99bb2ebaad851ef42b3f1abd5cd606dd88b608842e692c8331f352c27f4b2e2a6f0f0365419eb81c2068d4c613eeaea6fa1a5d6840998be430d41f447feb7010001	\\x6e1fd4e4d285218d058276a92c9c7b33eaa1e7cf2b7553ae003971816026f454dc78912bcaacce613fb882c371f4e8146da8cb3296bf39ac3b6326613f1fff06	1682757797000000	1683362597000000	1746434597000000	1841042597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xd8572dc40c3049f29144905d51a47a4fa1cd8d8880ee0a983d88c1aad38134ec77434fa2e9795e33784383d07fb7c1e5d2da8efed9e600a9b7fba8ed1eae53db	1	0	\\x000000010000000000800003cbb3c95a894ad99c588e2ad27b85110323e1acf1e63f2031419b2f6080b30137d9d7dee664135e1f40e9e2c7282b112c90fde9ccd6b8e653a9ca303e9cfcc47ee349c43e6af8b786db446989c6000bf55ec2f824bb01227b6d0977c6f035727247d932876ac55bad5239c2d6f14c83226bbae3a7924d83ff436ab405e5456a97010001	\\xa5736c6bf9c7ae6724d3eb376df8089e72f1b87043b3eeeeb05bee4e14a2647d17c5daf781e3f78b5b71318f71ecc2955f8a5f4d5c1bbfab7b06415c3e0d3e01	1673085797000000	1673690597000000	1736762597000000	1831370597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xda1f71c2aa2a4f9d6aa811369a6a78dd4ba3b4d9b6e7c8008b8acf5d5ca73bda55b3d29fdeabc2b3e7c48c73e3e0001bba259583f02eb9cb59a1f2ca7c348fb2	1	0	\\x000000010000000000800003e2dc4ab7fcf3199874303edf51de8fdf37713a5aa3dca37d0f8805ba0cf8b823d98277b9a57b4ff09551cfa553c9bda387add7f00a9967c33b21180871493e15fae4691763d0ae574fac1a9b58d4eb4f3117e7bb2a44c3a36b95bf870a472c877b9e618a8fe9c41bb27686fd5032c386ddd2596e725707f115c6e05e0f81309f010001	\\x7ef6d465a14f075709e9223381eb705eab39ecffafcbbf990defde9f247258324ef48ac64c9bb87fd36f8fc2d4d6ae358bdebd28c38ee86f63663d44f3e05c03	1680944297000000	1681549097000000	1744621097000000	1839229097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xda7f2e273ffc23163fce3a244feb2750d0f6ddc680f7efa26a39bf52771c2f5c6379fb7ff25c2ff89207182dd79438173d531e894c0ccd089e157ba88fbf8a5e	1	0	\\x000000010000000000800003c37a945c8b8eee436c8084fc85d874668d35eeabb536519e585b33efac963dbdcc51adaa633a9be287aab05c3e2aaed25e8e1157eb4e529d1052558971fcbaea266a8e369dc423625634fd40f72f2ebde682155cb43b289eb2bad5cb3ce3cfb2dc2b36a1c9b777269559d9c0d45ec85169096757f9487ad610040130f3b15141010001	\\xcd9ed4f8b97fe9520620bc3b388e617b03592638eea00a594ff320f5c94238c4ac054516b9b1c68728dde8dd35e54bd9f234bf1a5aae79723178d98c57dd3e0d	1670063297000000	1670668097000000	1733740097000000	1828348097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xdbe748507d8d120fc80d9774414cecf8caab5d332096f992d4a9af88d95dc5a79d14c5d1803889101c70a94619d70be35bc97f50f8f3b066b07ea1ab96d85243	1	0	\\x000000010000000000800003ae05322ed9a509c6a5d0d69dde58168a14fe17fed0cfaddd4875591206ba7ddd0ac5d42873220ac656de81c487798c53cec1cce44484ff7011e62a35d0c13fd39e55ed1d9c1914587582f83ae3db947d157d699110439fdd9f00935593fa84f9ee1ed0338402cebb3a84fe98390911b9111f685a3bdd17b25d23ffcd6f2990e1010001	\\x22ff1dac3179bb13786977c2ad1fdb867162dcd6858822901c68bdefa85b4808759c852fb34357d55ff5f894da1704c15e3f70de4f7fc4145c7e8fc2c1de1a04	1685175797000000	1685780597000000	1748852597000000	1843460597000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
410	\\xde1bd32e756536a3dbe6943f0bfbbeae7676db01094624049f67e905c4e2436ca46a193a8e5bf778c6158226bc502da9181e0eaed0c05eb8072560f7fb7fdece	1	0	\\x000000010000000000800003a71ce42e693251a470eea3a71b1e8952b3f0d9c947587e214d8c05d0a7fe90636f8403b37f7673d9fe0c11e50598322fd5badaa1173f7a1e675ea5bf6b4915960b667a6d7b2ade20bddf1a6b326a4d5040d83290a2c8bba3981e7e5730dfcf489dbadab57d8a7460578f4389bdeacc7db14df2d8e0c2aad7cf7370ab84fa209b010001	\\x1bda395a59972d79067868800208946d89c6e304941704820cd240f30e5ad9b335c51ae89fe7dcf6cfaa9df628af8d16c66ab191912421932274423bea8d5807	1680944297000000	1681549097000000	1744621097000000	1839229097000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xe077d862569dd7679ce30ef3f379e0ced6a058100533a6596438bb21c7ea6e2e23a085678a9989dbfb9f103968720d4c642b9bdabfcab7af55ddcbb7973e8d2e	1	0	\\x000000010000000000800003a55540f799aa70a755672e89031b1d0039effe94072ef12e99554060c9bb1c8a6874e1b2c5bd617d3852c5f45687063864ac61702ef615a144e8cfd132df0428363cddb9954f0b8a75efb5a87b247e9252988218d3616f5988ba678727429e5920a0413c453610d17f421641138d5516259ae71d10e859f8a5ef6d99c75e4363010001	\\xf0e761508a0b07a0cad6ed6adc377151acf654b41453ed662e3d0a9a2bec3ab76e30aa751f9fee37d40eb87c6cd0e867ab93fb59cf6a33504b0cf02ddd802808	1659786797000000	1660391597000000	1723463597000000	1818071597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xe9cb28c59e360445d98ca17a95df52da3cfefdb7d2992ed4e1f3584475bb427ca16463a80a4ab5475923768503a1223642183db4557421a05c95da803b9e3029	1	0	\\x000000010000000000800003e28aae1f3a95bd2a93c92d5745988e2bbd5e92934907c786736bcf0043effb6b760fb322b3d3d05287fb1c0afb46017f537fb6db61d75fd89a4c04579dd79e2b9ab090f1b7ca826ae33d80276132d55cc203f11e8ae2e0ea525c6b69cae7445be759c3e730346ce7b13bd9a8c5e64c8c03b0b4d962da1b8f8163c22869c7378f010001	\\x4f687744f8269f96cecd81512034f8985a0ce065421d69fa650a746932c7f1251a4ac0d89afb8e531b044f80b472749d2e4a13c04cafeaa88143ba328b6cef01	1674899297000000	1675504097000000	1738576097000000	1833184097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
413	\\xea2fdb17ba792671b97f34860b4fee4ce71aaf606550bb379767bb280935dba1783ff2a59d7d5a4907c4fd998383ba3c8f0cb8eda027ebb5ab759910f8958855	1	0	\\x000000010000000000800003b3eea633de488e7ce275f3d3cf734f6865b1841dcf213e5405bc51187463c7db00b98a206ebfe2a78f85b5fd7d0f17587bfc85feb6cbe509da2275c210b178f52ec4cb410f3ab8dfc3440e23be445b8a09e64b546cf9d8b916a468b669c504c80a981603b8679938144ffed6ed48fb84e246b02adc14592379088ea515151379010001	\\xc80c146be8e885434d32696b1ae2a365e376a9c1ed98c350b9b07e8688823053863b85c494d78c2355eb30c45f744eb9fda29d4d6724968d69028c7ff2c6c702	1664622797000000	1665227597000000	1728299597000000	1822907597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xeb7776d4d0670f6e83dcc81446c6d4173e9ab1d55eeef29285bb0248e7805e74e96ed4bdcb46b948a8318861a54f02580d1804d02d32431fc2b4921c79fe4db5	1	0	\\x000000010000000000800003c0cedee68c52fa8a350de323fe2957df6d81e19849b7f839b4a2524d627bfc48c95f3656bd17bd6031da1a0f8d13ed069b2b61db0408ae4d324fb7ed377dc21751667fe39933484e0e6c3c7fc45a758d99100ccf2200ffe2ffc2cb1d953707d5a9254cbb1158902fa836db12418fe2544d4765705010cf64f82226c0e7068c37010001	\\x0d3686df3369a880ad54e9087bd816fff3b67d761ecf49694d729a7c96d9ab6738678b852732f4701965ba37cb7c4f106f79ca089dd5c55d4b19de3fa1ef3100	1684571297000000	1685176097000000	1748248097000000	1842856097000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xec7365550612bd344d8e3e3a2c4e03cde705329a56d45074c75e9f5d8d8449541dafa72c3629762f8149517aea55684446481233a06ad7d08f6ac5db0cca7e87	1	0	\\x000000010000000000800003bb3ec23023769dc7605d6cc62bb6a2f6a9555b16c3a9f8deb15286f4a7ca3894eda8c012da91eaf5a16191ac6a3c162860d0929a457be495d810d6acc471a9c6fb1e6e11841ccd278a1c9a56baa5ebf1ef305a1bbf6c2155c45f7f9fbb77e50435e220a4850ef1c367be80f71b3e17858143a5bcbd362de2ed8dcecc2a358f87010001	\\x57a44f4aab12ba4e4087388b0be57499bf8157e5d1310425a79e7fd011b5e96daf57eee328e4b355e22cdd2a40af3ff209805ceb118e823f3b2ee04d64e8ed04	1686989297000000	1687594097000000	1750666097000000	1845274097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xeceb0e4c8e270b48e345b77530acb8136d226efb29e9f6a398cfa92ff175886c277ad5c3c069fd720d6ea593307daaf5351f88ec9269d94608291faa3b36aea5	1	0	\\x000000010000000000800003d98d63795682fbc1f1d0452a605a31038d1e24b2c0434ae7bd77f1b0d7901b76e097e9533eb892dc9a0accff2081a9fdd79ebed3c32f3c1c2d045b6f32a455ee1a9be80e7a25b4630cfa965d4d3d7a3a40a232343ebe40647d73efe70ece661d3bdf00737bd22d243a146cfa336ec1788988e559ea9140fde457a0529c154d29010001	\\x1765e7e8fd58c78518b83132616b0f00efa8903a7d0d961b1c8d26ff620bcc0e853119018e05025bb39a8ba62268c03530c8492003b31ac108a7ed9514eda60f	1660995797000000	1661600597000000	1724672597000000	1819280597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xeeef075cc57001dacec4646a1fe3f2997bde979a5fa77c79384cd20e47380a1e21acc0105c838750accf99802a32ba0ef787a6a9d09ced13a9b477d9a6991828	1	0	\\x000000010000000000800003e0c6488202b0b36fe2389b79e16fd541375a2c30f4276486ea95c93ab2519b7200e67cc675c153fdfb355c1daa7eea1e7173d8f09db840fdd3184b04b281e934ed3a2a864e17f6940e329cca16eb8e3511bb56e09dab4cef268e9fb06d74fe5eff13e42c420b1435c0d0d7e2af312d6b2e02665a45151476dfba0dd4e34b01ed010001	\\x16d4d7b70b9f987381c3b8af50c43faa43f09ea01c149869f374fa40bda016041fcaea40fced479d44723af7666764a32cbe496c2a2c0cf3175de10b7ec19b0d	1676108297000000	1676713097000000	1739785097000000	1834393097000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
418	\\xf2ab8486a8aaed7217717e7a5b67a8e4b2e3647833516ae2d0f9045d9c35da60dea18403bcb4ec7a322d660057ca31cc7cd84dab57e0404dc423aa4ea099368f	1	0	\\x000000010000000000800003dd2e1b9b62863933bc1ca7e53b24056958aa23d90df2faeaa52fd687d2deaa0cde9d97f2c704c47823ff9e0e7fa82654d8b764d44f923ef62e3c3f23c615e96f52e031e53373352fc2568ee30d625e6c727bb1db3ed492bfcd24ce037edc1b820608c3b594ca0e9b1caed0c582ef9815b71f8487d1ab44281642f3f659fb0857010001	\\x4fe096e70b90f5bae316c9b472ac69705991cef43ae62bac04a80ed1b906b6330500e0a45dba3a9f6a8a694940f5da2c168f27bd96fff7a15a537debcd4ab906	1675503797000000	1676108597000000	1739180597000000	1833788597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf433ad02a2d42c5cfb34567220fd7a2fd9cc297698e262334f16f173a72135c303d98f2a0fabfd5beae6d78d7efd757869c865538160a9cd08f628827c34f942	1	0	\\x000000010000000000800003e75392a97057853827ebd887e4a52da3d0c61128b1df48a951d41222a37079082619fa13cf5b7d8c558f9012024b4225a1d0f5231a1bd5b7aea4e58b447e4bddcf7a04245f4c31cd31a6127d61051db3cba28fdb6de5bdf13cfe22c07277216cec09b6eba6d3e1616f02adb519803323b88cd63567bff63c6756d3b15037a0c1010001	\\x70e5114438f16947cdad0ce02d0f75cc83dce08b7fdd796009fbf8e2c96ae6d24d28c90c6b7f73d3cd9e656df62ee461bee2c3b3d2d81eca8a62582b44c6c407	1678526297000000	1679131097000000	1742203097000000	1836811097000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
420	\\xf6436a6ea861d2ba7352e388a8b1247d27cd94b38e18dc3562b9d18f35ef58880f4e8422e9f5960ca6c8e712dc56732a35d722a978e7d4998201721cf1d30cea	1	0	\\x000000010000000000800003dbf4cee78d94913eedcec5c3ec6e1e9e609933417388079292cd79446f33a331cc2515fdb8cedade56e2677cc4c03c80b8970e679330eddbad0ff653c8a2a1f65987412cbc657852221f458df06467f4b8d43b2a968a1c925dbdec77d9df8b224b22d4264868648012a78990752b1b2dbce301b41848ad36d4002ce1a91610e7010001	\\x8591309df242c69eeb633f1ebbb508c18bfc03f82bb8860a201e1772733ef77330a5cacc0eb98f2f2dfd8e9f1267f46dbee67a344480fd6dd6fe7b8413462a0e	1668249797000000	1668854597000000	1731926597000000	1826534597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf873453d32ad4328cae8bba1cd776846c6f82995f8169b5a96d602f4d4cebaa8569be0a67d094a46a0bcc3bd7ce3536be6707942edbc4828181aaa33ed3ff0f1	1	0	\\x000000010000000000800003ac2233be9b3c508f6b57b357440f257c712a3d98a57ec1057a02b762f7f2103ee403af1142b95d81b079b22b86d70664ac7787147ecfba38f0ffa37a1ab49aeeda0433853b113874ea8d51b23b13bf425c3e9535a88ea787d04051b8991db9ad47a96e1398165763f0e0e2ad5579b086bdf7f6702dca9f32b7c23b148cbd5f09010001	\\x9722ede28144e1c3c7516e944d7f8c4b3839c85f22612813293b54d69896586775a95a5644b57b498fb47d463019dda48f68a30b28ac4d3312382dad245d9f04	1687593797000000	1688198597000000	1751270597000000	1845878597000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
422	\\xf88f5f25deee85b049e35e502848d29170c36e781459230a06969d0d3b1cf4531801722b8461d42cf68a5babc2cf4158e4e6f84fb89620bc02133d516d85efdd	1	0	\\x000000010000000000800003be6a936c591e461c3caca66dce3d0e85d63b0be6edbec4ff90d9fa196712e5426a2ad555a226f86e30767eb610f0f8cc44da9ea8af39e4f00f91283285d4d9c4a4ed0d9992a123f56656c2493f8233fbabe9f181d91a40c5a09f47019dda2ece49f1453a345c36cc7a2d6112a4736519c263e2b75b017a108e0511801b556657010001	\\x2d5d1eb734d46952266d67f8249bce403502a00dc6bc936cc8be7c154d86872730c12be36a9bfac792bfa4df43e11ea3bedf0a685f5fb05f64293303ca956a01	1670667797000000	1671272597000000	1734344597000000	1828952597000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xfc57cb52db5eb3dd357a8fb57f0d8364be6be6ed63ea42929cd01cbf53041329db3da42422fd0feb6ae493628e77948755003cfd7c2a97e4198b9fdd5783f4bf	1	0	\\x000000010000000000800003b23b8ab11df81eebe22ca60fbc1a893fc4e97b49c9171c36813d34347a3369b7a0a8fc80b54f91983b35324885fdbf872a378ce270ace1d841bd6215621cdcac56b17ad1aa07dd7faf89f3cd20ec44f041ebe96f11db7f34fc129737822ab6b9a3ce93bfaa51ae83902225288e6cc8732cf1d9a095f5c0017bc02c3c3a408af3010001	\\xa7075afc70e8ead64b901bacfde5badf53ba89ba7db7cc3e55659725e3b817c202553aade32cb9dcca145e488cd73a2532820cc1602b5306ab203d8dddbcb60f	1687593797000000	1688198597000000	1751270597000000	1845878597000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
424	\\xffa7f947a1b9b1eccbf16dd3e9e682a45c5a2863a0b8a20db6210a7f9b22cff441b47a0e30044ce4cb9a5655f26f13537d06c7b22c9f3d4c8418c37b48e0e063	1	0	\\x000000010000000000800003ca6abc84d74d54fae473090b8a1e241e3558e64540b2208d65ed705ed359a31e9f59a904eb81b6e90920cb651d7a5f9135c65752757401a9cf5d363f5c5fed3bea04fde0d3e389c8d7bdbed0e663141db7f974ba64a7a15390066e282fa804bafc530ba922853a7d6e6f90ecf6a8bcc3ae376731b7c1d1c3ac1a44b9c5b6d1bb010001	\\x4191dd6e3451324336e660cdc502fdd46e9a3e169c31dca222e59db0d9d947991db3f5fb7554d4d95282c7ce3be1a70bcb7332ba478d49b9af8771ff16307100	1687593797000000	1688198597000000	1751270597000000	1845878597000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x821fa346052714eca04b705ea8fa9eea41db709841df8575080fc32fc4c188ed	\\xf7e2d41938ddcc00dd85e8d35d05356a98f3b3f0dcaadd1862298aa1cd28ff04baab82a6152c0c25c468dc26cb50c713b01f33c2cdb6f838831cdf8d2144240c	1659786797000000	1667044397000000	1669463597000000
2	\\x69b6b240e1a5856c683c17e68e3fbcdbf705b7d04e6fc767741e3b0115840226	\\x9d5bd7b820423b4a7d942ea95c46aad888b1e5df55907f629a3131c96c04809f7b88f63dfc17462dbe342c0c7a6e39a1c21f779bb616bc35828c8743a2da200b	1674301397000000	1681558997000000	1683978197000000
3	\\xae578c32ab6524455d2b204b0ec0482af8da43a67ad400ea8dc084b67f3d685b	\\xae572dbd4552635e1f04ad517a51d45797455379ec85efd4fc5c69039eb0d6e343db7d619c34eec89a89abb15e40737ad11189fb3e2ae8eb0179580a0d7b7b00	1681558697000000	1688816297000000	1691235497000000
4	\\x10860682a96c1784a0ab96b565b017f7ecfd5a13d28bdaed6fec0f81cfdcd89c	\\xcb005db9721bcc0d6ca2ac53917411c81da3c9a14ee8c0554442b50fd2e675261cff1a21fe29b6b5379e59b4a70d1c57ae08c41ff8709b0dddd4d30455312105	1688815997000000	1696073597000000	1698492797000000
5	\\x102351f752d3e4922c31ed3ce0f85a47f642b5be7094a32281632583e4153584	\\xedcb45499eed761eb40dd96c1c26ce8c7facbef4f878fb965fe10081bcb3271ea2ad8a6bdcc324e28ba51bb854211c576f5bbb14d684008322f0edf3b9d4d807	1667044097000000	1674301697000000	1676720897000000
\.


--
-- Data for Name: extension_details_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.extension_details_default (extension_details_serial_id, extension_options) FROM stdin;
\.


--
-- Data for Name: extensions; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.extensions (extension_id, name, config) FROM stdin;
\.


--
-- Data for Name: global_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.global_fee (global_fee_serial, start_date, end_date, history_fee_val, history_fee_frac, kyc_fee_val, kyc_fee_frac, account_fee_val, account_fee_frac, purse_fee_val, purse_fee_frac, purse_timeout, kyc_timeout, history_expiration, purse_account_limit, master_sig) FROM stdin;
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x6200f95b1ffb2b2a0bd8eac43c09a182c45d7c6def4db9d9da33742c61087878fec467bc645569ad2d028f11b5c5d1e979602ef74dc718754c74fd5b80cb410f
\.


--
-- Data for Name: history_requests_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.history_requests_default (history_request_serial_id, reserve_pub, request_timestamp, reserve_sig, history_fee_val, history_fee_frac) FROM stdin;
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	32	\\xdbc7d9a86638bf4ff964a5876f8c29537bb1392cc2d11fc8e23ac1f4074db0aa	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002bcc36265494b9764c9e566658021ac058c6f3fcb6b3a21f73edf6411c052ccc075fa4075d571a2fab6894751ebc326752e7f2109f19be74da34c7c982b509d4db7151ff3768704db9d2782baef2aa7b3cb496d0d74359d94dece92858047b796835cc2d97d0d0c19060ca4514a612298dd607b982c36c892c6738519f077c2b	4	0
\.


--
-- Data for Name: legitimizations_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.legitimizations_default (legitimization_serial_id, h_payto, expiration_time, provider_section, provider_user_id, provider_legitimization_id) FROM stdin;
\.


--
-- Data for Name: partner_accounts; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.partner_accounts (payto_uri, partner_serial_id, partner_master_sig, last_seen) FROM stdin;
\.


--
-- Data for Name: partners; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.partners (partner_serial_id, partner_master_pub, start_date, end_date, next_wad, wad_frequency, wad_fee_val, wad_fee_frac, master_sig, partner_base_url) FROM stdin;
\.


--
-- Data for Name: prewire_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.prewire_default (prewire_uuid, wire_method, finished, failed, buf) FROM stdin;
\.


--
-- Data for Name: profit_drains; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.profit_drains (profit_drain_serial_id, wtid, account_section, payto_uri, trigger_date, amount_val, amount_frac, master_sig, executed) FROM stdin;
\.


--
-- Data for Name: purse_actions; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_actions (purse_pub, action_date, partner_serial_id) FROM stdin;
\.


--
-- Data for Name: purse_deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_deposits_default (purse_deposit_serial_id, partner_serial_id, purse_pub, coin_pub, amount_with_fee_val, amount_with_fee_frac, coin_sig) FROM stdin;
\.


--
-- Data for Name: purse_merges_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_merges_default (purse_merge_request_serial_id, partner_serial_id, reserve_pub, purse_pub, merge_sig, merge_timestamp) FROM stdin;
\.


--
-- Data for Name: purse_refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_refunds_default (purse_refunds_serial_id, purse_pub) FROM stdin;
\.


--
-- Data for Name: purse_requests_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_requests_default (purse_requests_serial_id, purse_pub, merge_pub, purse_creation, purse_expiration, h_contract_terms, age_limit, flags, refunded, finished, in_reserve_quota, amount_with_fee_val, amount_with_fee_frac, purse_fee_val, purse_fee_frac, balance_val, balance_frac, purse_sig) FROM stdin;
\.


--
-- Data for Name: recoup_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_by_reserve_default (reserve_out_serial_id, coin_pub) FROM stdin;
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x613f50d1291d4e70b049d69cc0619ba53329b07f8080c4b01372b507587bfed9ce5458b77103dc8fe99728a4a0fe7b4b2ecc1eb15c9345f1389331e07777e95d	\\xdbc7d9a86638bf4ff964a5876f8c29537bb1392cc2d11fc8e23ac1f4074db0aa	\\x6957b76e617375a2e69655638d5dd71eac1d43cd88535da8359debb99a97c7b6fe6e30c319657af31c27ac529edf24bd73a62863975a4953baa4736ec3b1d806	4	0	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, kyc_required, kyc_passed, max_age, expiration_date, gc_date) FROM stdin;
1	\\xef00febd63a5cac806bd02662fbac584088d79b5c52782e55aecd1190581d296	0	1000000	0	0	f	f	120	1662206010000000	1880538812000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xef00febd63a5cac806bd02662fbac584088d79b5c52782e55aecd1190581d296	1	10	0	\\x53e61429a16fc975a3a287c55c3aeb585230db75302b674fd4a4b6075f715f9c	exchange-account-1	1659786810000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x0dc81f5983bd4321c8507009468456f80e36be337d26864f48ae210b7318dfb79daeb7247291d798b421314a112deb050cdb15dff6c95265763abd56a093db8b
1	\\x9daf288f7dd0dff12992a940c3438d49c813ff8467d24a82bbdb7b504f5349322a2784975a4ef2d184dd38702bcdde0c8a8b3f35d32d3d28019f50822dde1a0a
1	\\x61d93a3b8bea95eb6714d1a1fa2737ef59d2d98b21b3545f245b4cd62a4f13e68b5fa30249b583ebaabc95664bc1eb3855e99728bfe17e0782b8b4bf24e26849
1	\\x6f4096b8e17e338bf3fab8d26ec08b96d149ebe8cedf0e82ca94777e2b9dc55cd2def008028a1c933bc293518af7fee87fd31db6ba24943311069c6a9b097ef1
1	\\xf6f38c2e82dd38bd00f20ad34bb54bb27a4a45c5705b9ac59e0d5e0d007ae735e003f3fa18cff3740591890791044dec91913a5fa1087d6b34d1cc52cd2cd69d
1	\\x1ae7b9417d74d555e4ba900d7cb3796a291ada11059cf098d504d814cf698ea1839dd8f6103734fb9465ee263acf6ba6b06c1184a3b26a017b92dc0cb9029092
1	\\xa615b0c8b44959658a25021779309ec40bacdee7b34ca942a79bdde25bc4ed0578e900acce695e8b09ccbda43f2835d3fa87d4e8e2e8914287b94b16caf68a0c
1	\\x0c073d84b67daf561aeb079e85ae3ee34bdab2b6c1fad8c66025f5b03066e537f297c1dae8cea7b999365abe41717dad4e194f0ae3b05aaa1f6ec0823a97ccb0
1	\\x1396730dda970a15ad47222bcc6c2ed99ff6358649c3f0ca4780a940b782c9aa13741eb6d312451e32ee4129489ef059954279cf4fcf95f5bc65677e1b5a022d
1	\\x1d4ee759d72a9b169a571fc68e254e9008aecb2f69517ae327674b824f2d5e64a8e9e065394ec902729dd19d3c6414fec382d9e1d00325654a667e6e157f5b1b
1	\\xfd5ad1cf963f265092bd87c1eb483122338294ce357134cfeba35ab6d3a070bc1e5f58101ceba518e9c38fbabd378133468df31c1fe7ff0b18f4f5dc545d95fc
1	\\x1ac1bf84d53c2947e17c3a0932dc376c46a1f45dcd68965d2d1a0e00fb1a53799d75be4b954e4add5a1445723e49a340330ad0d4ff8bb362be70007c0b05b070
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x0dc81f5983bd4321c8507009468456f80e36be337d26864f48ae210b7318dfb79daeb7247291d798b421314a112deb050cdb15dff6c95265763abd56a093db8b	32	\\x00000001000000015a1bd2c5c4a5757ba0e049776714dd20dcde898e7c527942d601379dd0ae94da843eb9f58b075302ae057d66f202efcab4ac9f3c2222856fe64db380041d554c6eb75185f42eb6e79adf73575c0b516a61262bf23fd4846aa6d751d6d1c671a7bbbdece18dca97bd4523e03d7e6a202988caecaf5954edec0aed36e4b444a543	1	\\x731cfb2e5656f33677e2140e6b393b36f33f8016bd6873fc7922274b94eaddbca7b02b1c749912dc74bee977adf05044144e51725b4a72b21429a36948e3f809	1659786812000000	8	5000000
2	\\x9daf288f7dd0dff12992a940c3438d49c813ff8467d24a82bbdb7b504f5349322a2784975a4ef2d184dd38702bcdde0c8a8b3f35d32d3d28019f50822dde1a0a	47	\\x00000001000000019830d4a274657108e8574bb41003280d1a5053cf2d1ec763f230eda440d698ade85557f110ca5184600fd4b5d2c8c75edd00dbd63d261a1353572ca243c0677be03bf5a31d3276ba77b92fd879c9586eb2856d420da27ff2011171e9dfce1544cc78eca33dafe824ab9bd031fbc00484918bee19ff37d62b6128a0436fb04b12	1	\\xde49627cb0f5125cc7a96ff4f9d2b77cb8e6f1a27bce2eaac5425a490e7c32e256eeca383f1b435a172643bc2f7aeec50643ddbe15623b5923577f8fd76d3902	1659786812000000	1	2000000
3	\\x61d93a3b8bea95eb6714d1a1fa2737ef59d2d98b21b3545f245b4cd62a4f13e68b5fa30249b583ebaabc95664bc1eb3855e99728bfe17e0782b8b4bf24e26849	218	\\x000000010000000117861585b2c265e93b88d0e3fd9a0a5da0a3442fa0e163bd7079d4349da8a8dc3f8dec2362308e53b914b870c2f651446525da225af4dc8e72c51f3ac2d4011ad687b1b34699ad91257788ff6b02c3de19c74d9245def0cf78eecb21d8f1c0badb74e3ad0db8a2693f0279fe46efe555aad023bee69c94466e675137d79a85ed	1	\\xff0d81bbb84e5110f8377ee9b008bae5d0e1801ff80d32369753974581b0f6d424a395e6a17fcfb0891cbf19916f0d811698dca5625d3994409133e275bd920e	1659786812000000	0	11000000
4	\\x6f4096b8e17e338bf3fab8d26ec08b96d149ebe8cedf0e82ca94777e2b9dc55cd2def008028a1c933bc293518af7fee87fd31db6ba24943311069c6a9b097ef1	218	\\x00000001000000014cb975f1b9ffd021824729dbaeb9415ede49957369a9761313517324b22712841742c2317fc43486d8612f368ec5af0d881db0773a4b5b5e0b274af97f9a4b538baab6a356169c9e6d8f402f9b0947d56d0bf1d70529a663e2b5c94794f8305ff761e81b7e161d33e0aaf92c2ffb0f40c6b30be9c20ba9632fc4017faa773b52	1	\\x3a2d07f3fd354d9947b77c6c4ae56bfc9e7b97f882bbbfa9de4dd61c1096ffafbcf5374e18f49e26aa37e3ddeb3c9c9a10b667ad96dc1d3112a2a21b37fd330e	1659786812000000	0	11000000
5	\\xf6f38c2e82dd38bd00f20ad34bb54bb27a4a45c5705b9ac59e0d5e0d007ae735e003f3fa18cff3740591890791044dec91913a5fa1087d6b34d1cc52cd2cd69d	218	\\x00000001000000018263c36dcee147ec59e36570a92d4acb6b2bfe5e9f1774fa0ffeb479987ea9e1414a3dc837a622237d19b41fea6717b8bdbc8e653f0ff4558a583f8bf75677bef3cd29fe9b0896193c41393a2c0c852f2293320b06edffa4c28998b3356a691e571d2f521a6b6aa1de1230b8548fae887636653b9ac88a1999b5248feb9a849d	1	\\x5542cbf7b9ff15f1fb1010a0c1258682b8c4aeff1e59e38a3d89d80fb154f817a03058784a1930db2b21cda7a8079471382be42143388bd23cf6ab2f6bf93c08	1659786812000000	0	11000000
6	\\x1ae7b9417d74d555e4ba900d7cb3796a291ada11059cf098d504d814cf698ea1839dd8f6103734fb9465ee263acf6ba6b06c1184a3b26a017b92dc0cb9029092	218	\\x00000001000000010ed57cbb1af080a38b7ce48dbf4a541a2256fd3f5ba3bb7eecd46a3d9b06850ac06937c762227596e726bf310d53d089d63bea6ed4d890df53432d3ab737400aede92b30ca0cd104e2b7fbacc62eb77d0f661388b5c852c0d0ccbbde8ce7549303391b25c0668b2d5545d886c993cd83f69ddb8701a04f3d76729bbc091fe055	1	\\x50f57d4baab08b375ec2c9c00591cd2f36455f63c815768807e70db254c852394f931e8c23826535f8ceaabe6249b12e193283773455170a2644dd842f006504	1659786812000000	0	11000000
7	\\xa615b0c8b44959658a25021779309ec40bacdee7b34ca942a79bdde25bc4ed0578e900acce695e8b09ccbda43f2835d3fa87d4e8e2e8914287b94b16caf68a0c	218	\\x000000010000000103bff8d6bc066791b6909517c36a4ebb31f8a159763c793e302e7f4c880afca33c2e25e167d25720562a95b1238d7e1a3592294c69463f1bd5eb002f88c5bccc866edfb20cec08a6b5c921978a0f98c691265190cc372664601ce9d8b95dba36363649599f54ccba0fd7a2e827c05fb4ed3f740f5813d94b837046defa85cc75	1	\\x5d281888ba7055a299ca0ac89f4b412b3c35689d768359e30c97d12996f29d46b4e29935f57b7e2065ab1b5593f266ff4310b99f7c00efe0364cab867b210e0c	1659786812000000	0	11000000
8	\\x0c073d84b67daf561aeb079e85ae3ee34bdab2b6c1fad8c66025f5b03066e537f297c1dae8cea7b999365abe41717dad4e194f0ae3b05aaa1f6ec0823a97ccb0	218	\\x00000001000000017ba15bcb3e94c6f14368c10158ac9167e7ea8c0879b8a7c0fb3d180be1844a73584d96b9803a5bf9888008409a9f0fa4746b5677ef5357ae279189de25449f7e398d7eb881fab986458d5b839f4eaf149bff519d0f664a85ab5cc5390049da098cd413b933ad592cebcac719a4ea48299f69f93b31ca38bea377addd3d187b46	1	\\x351c56bb94cd42e116186f2ea584b076fdae7af2e19c7362da25777b3dfee42e3cd4b267cdc732f39edc2bfd5cb389aca10ca32a95231c467a10f653a4e55304	1659786812000000	0	11000000
9	\\x1396730dda970a15ad47222bcc6c2ed99ff6358649c3f0ca4780a940b782c9aa13741eb6d312451e32ee4129489ef059954279cf4fcf95f5bc65677e1b5a022d	218	\\x0000000100000001228d3b9a86eba86a0c97313a258aae25fac9fc41e4fe73f3c10c17ab0cad9dc338eb6c6f3d2ef5978e62f15e7d6f321dafbe7349a2f35a0b7924a99fbacc278bf9080cb001ca1b1a7f531fed1190820932ff3a472e7ee02dee6f3d95860b7f8743b54e029202b276c68a5ccb93cfc07d0a6e353a03c705d3457f27aaee2d081e	1	\\xfe4ae1a25e584da0c775b9a38b6304f67ad47069eca19952dc1501e73ad104aed0be46d0659cd6af9bec3383e5cdebf7f7df5ac11cfe23aec85215e9b0321e04	1659786812000000	0	11000000
10	\\x1d4ee759d72a9b169a571fc68e254e9008aecb2f69517ae327674b824f2d5e64a8e9e065394ec902729dd19d3c6414fec382d9e1d00325654a667e6e157f5b1b	218	\\x00000001000000017cc685ed9b101770a111784980968ca42d33b80df0d00f6e39ec0ce7b5d0b9e2e48e670c6ed148bb2504046fca8d9cf196ff507382973395b44e8e4a186c328ae9784b2a28fc2ad4cc16b7ad5eeb6c13592cb520cee742d687293a6baa3b6ee5bf702278eb665f10cc683d91f6444fc036d7b2542678c53f61095d3589b0afd8	1	\\xa578d91dc0460507c88527381e870dbd76c730898971c5c99fd107e3f8e73fd6c1d5be1257169b6f3ed5c6722ac7e4c05a31a32df19c5e1a428fe52159471b0b	1659786812000000	0	11000000
11	\\xfd5ad1cf963f265092bd87c1eb483122338294ce357134cfeba35ab6d3a070bc1e5f58101ceba518e9c38fbabd378133468df31c1fe7ff0b18f4f5dc545d95fc	278	\\x00000001000000015941000d4f9ac6288cda7af50d8f331c1699dd95fcbb9b0fde66cdb1c33463744b24bdc94b4f1a83d2c37a7346cc34f080ba86d090246e9d54c6f68849b28ddb2cf5d920f38b79c3d80576b3d12d1039ac7ef736925af7cd6ac65a8f57a3928ffe6bba978f6f5ecb783c1d471b7bc13e5fde2cf0b1edb54d7477b18d5cb698a1	1	\\x0ba893021e39e983257cfd82ab03a7dac3ff9b3b7369ecff551bf9ffd849ea52fa2ce68bd041873775f92efb372823c4ac2973f36f0ab91e0105b6418a24fb0d	1659786812000000	0	2000000
12	\\x1ac1bf84d53c2947e17c3a0932dc376c46a1f45dcd68965d2d1a0e00fb1a53799d75be4b954e4add5a1445723e49a340330ad0d4ff8bb362be70007c0b05b070	278	\\x0000000100000001ab52582ca125840d7c09594e71a3af0f85ba88915331c350fd26fbdadd085e9d3d06cdfb9633da9f407ef7af160742cc57c2f652fc6d310f446b1756552a2d67874bb3231e00a901c40af6b5cd14b4ce4e6a770b62a753b835fe0a7a989c508b5a87dbf5489468828a70313c6716e2cf5bd1cab6a275e3de43f581a1f0514497	1	\\xa8d5f0300d887d180d6ad446885f8b640eba496ecb1fe2a81cdaa06e1d71d087d3a13ed6e48c1cf22406765d7de4fc16a2c64016eb4f3a2c864687d3d280a707	1659786812000000	0	2000000
\.


--
-- Data for Name: revolving_work_shards; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.revolving_work_shards (shard_serial_id, last_attempt, start_row, end_row, active, job_name) FROM stdin;
\.


--
-- Data for Name: signkey_revocations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.signkey_revocations (signkey_revocations_serial_id, esk_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: wad_in_entries_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wad_in_entries_default (wad_in_entry_serial_id, wad_in_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wad_out_entries_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wad_out_entries_default (wad_out_entry_serial_id, wad_out_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wads_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wads_in_default (wad_in_serial_id, wad_id, origin_exchange_url, amount_val, amount_frac, arrival_time) FROM stdin;
\.


--
-- Data for Name: wads_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wads_out_default (wad_out_serial_id, wad_id, partner_serial_id, amount_val, amount_frac, execution_time) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://iban/SANDBOXX/DE343625?receiver-name=Exchange+Company	\\x8b6fb0d4860491dbed00509ab3330fdf95fbf06b60f05b59da577b3e016157de465d4ad91f82c710e32ffb4d546cae2752d37711b6c325f92ca9efbccec2bb0c	t	1659786803000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x0cc3303f624b822434fdbf95eb1dd1daf894a9e6065ff8d40d91627e6629028a31845c48480ce5562ae7f1ac84a27addeb1e9c213f9662cecb719d972e05ff09
\.


--
-- Data for Name: wire_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_out_default (wireout_uuid, execution_date, wtid_raw, wire_target_h_payto, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: wire_targets_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_targets_default (wire_target_serial_id, wire_target_h_payto, payto_uri, kyc_ok, external_id) FROM stdin;
1	\\x53e61429a16fc975a3a287c55c3aeb585230db75302b674fd4a4b6075f715f9c	payto://iban/SANDBOXX/DE474361?receiver-name=Name+unknown	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	0	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x9241ffa2ee2416b53da751cf12d7887784048ace0af7fd9829a3145566a2520a92580bdd593f2eba572bb086b69f78f8558bcebe51eaf63459bc615c269226a1	\\x5e84e9c9572b887bfe754f7ec1633af2	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.218-0089HXK70X6FP	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635393738373731327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393738373731327d2c2270726f6475637473223a5b5d2c22685f77697265223a224a39305a5a385145344742424146443741373748354e573845593230393250453142565a563631394d43413541534e324138353934503042564e434b59424e5441574e5631314e504b585746474e434253545a3533545150364843565252415734543932443838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3231382d3030383948584b373058364650222c2274696d657374616d70223a7b22745f73223a313635393738363831327d2c227061795f646561646c696e65223a7b22745f73223a313635393739303431327d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225a344e4a344b464142305134424e4251305354344d4e4b48443033594a5241533058394d43365441575747465730564551583747227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22325141544d575830484d4e335737465237354b36314339463054415a3550504a3545355443584337415858335450445252335347222c226e6f6e6365223a2237544539485939433232395a57374552544b3556313334565859325356515430354a543633364b54545752334152485a42413130227d	\\xd65a3d3facdd5529f439fcb89ca25faca0e44d7cb0c3abab8164b9514cda5f1742f1697e8c515a0d89b9c18513e435314f9a5126f26ca28e90dcdc08dc84ca3c	1659786812000000	1659790412000000	1659787712000000	f	f	taler://fulfillment-success/thx		\\x714d8adb6782b40eb2aa9fef38170922
\.


--
-- Data for Name: merchant_deposit_to_transfer; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_deposit_to_transfer (deposit_serial, coin_contribution_value_val, coin_contribution_value_frac, credit_serial, execution_time, signkey_serial, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_deposits (deposit_serial, order_serial, deposit_timestamp, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_serial, exchange_sig, account_serial) FROM stdin;
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xf92b224dea582e45d57706744a56716807e961590753461b4ae720fe036ebf4f	\\x821fa346052714eca04b705ea8fa9eea41db709841df8575080fc32fc4c188ed	1659786797000000	1667044397000000	1669463597000000	\\xf7e2d41938ddcc00dd85e8d35d05356a98f3b3f0dcaadd1862298aa1cd28ff04baab82a6152c0c25c468dc26cb50c713b01f33c2cdb6f838831cdf8d2144240c
2	\\xf92b224dea582e45d57706744a56716807e961590753461b4ae720fe036ebf4f	\\x69b6b240e1a5856c683c17e68e3fbcdbf705b7d04e6fc767741e3b0115840226	1674301397000000	1681558997000000	1683978197000000	\\x9d5bd7b820423b4a7d942ea95c46aad888b1e5df55907f629a3131c96c04809f7b88f63dfc17462dbe342c0c7a6e39a1c21f779bb616bc35828c8743a2da200b
3	\\xf92b224dea582e45d57706744a56716807e961590753461b4ae720fe036ebf4f	\\xae578c32ab6524455d2b204b0ec0482af8da43a67ad400ea8dc084b67f3d685b	1681558697000000	1688816297000000	1691235497000000	\\xae572dbd4552635e1f04ad517a51d45797455379ec85efd4fc5c69039eb0d6e343db7d619c34eec89a89abb15e40737ad11189fb3e2ae8eb0179580a0d7b7b00
4	\\xf92b224dea582e45d57706744a56716807e961590753461b4ae720fe036ebf4f	\\x102351f752d3e4922c31ed3ce0f85a47f642b5be7094a32281632583e4153584	1667044097000000	1674301697000000	1676720897000000	\\xedcb45499eed761eb40dd96c1c26ce8c7facbef4f878fb965fe10081bcb3271ea2ad8a6bdcc324e28ba51bb854211c576f5bbb14d684008322f0edf3b9d4d807
5	\\xf92b224dea582e45d57706744a56716807e961590753461b4ae720fe036ebf4f	\\x10860682a96c1784a0ab96b565b017f7ecfd5a13d28bdaed6fec0f81cfdcd89c	1688815997000000	1696073597000000	1698492797000000	\\xcb005db9721bcc0d6ca2ac53917411c81da3c9a14ee8c0554442b50fd2e675261cff1a21fe29b6b5379e59b4a70d1c57ae08c41ff8709b0dddd4d30455312105
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xf92b224dea582e45d57706744a56716807e961590753461b4ae720fe036ebf4f	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x0cc3303f624b822434fdbf95eb1dd1daf894a9e6065ff8d40d91627e6629028a31845c48480ce5562ae7f1ac84a27addeb1e9c213f9662cecb719d972e05ff09
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x15d5aa73a08d2a3e1df8396660b12f0695f2dad22b8ba67587577a3d59b8c0f3	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
\.


--
-- Data for Name: merchant_inventory; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_inventory (product_serial, merchant_serial, product_id, description, description_i18n, unit, image, taxes, price_val, price_frac, total_stock, total_sold, total_lost, address, next_restock, minimum_age) FROM stdin;
\.


--
-- Data for Name: merchant_inventory_locks; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_inventory_locks (product_serial, lock_uuid, total_locked, expiration) FROM stdin;
\.


--
-- Data for Name: merchant_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_keys (merchant_priv, merchant_serial) FROM stdin;
\\x3635a412b8f1c0089373439122c7faa976a96d2bc11012446668311337048cc5	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
\.


--
-- Data for Name: merchant_order_locks; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_order_locks (product_serial, total_locked, order_serial) FROM stdin;
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_orders (order_serial, merchant_serial, order_id, claim_token, h_post_data, pay_deadline, creation_time, contract_terms) FROM stdin;
1	1	2022.218-0089HXK70X6FP	\\x714d8adb6782b40eb2aa9fef38170922	\\xe5b0ce9da086605a900e46678adcbe4bd0d8af8a33ead721cba8dd640ca51eeb6f4639cc0d5699a8ff20e3412b2bed05721e2ba85ef02e3f0162860fb0306cad	1659790412000000	1659786812000000	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635393738373731327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393738373731327d2c2270726f6475637473223a5b5d2c22685f77697265223a224a39305a5a385145344742424146443741373748354e573845593230393250453142565a563631394d43413541534e324138353934503042564e434b59424e5441574e5631314e504b585746474e434253545a3533545150364843565252415734543932443838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3231382d3030383948584b373058364650222c2274696d657374616d70223a7b22745f73223a313635393738363831327d2c227061795f646561646c696e65223a7b22745f73223a313635393739303431327d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225a344e4a344b464142305134424e4251305354344d4e4b48443033594a5241533058394d43365441575747465730564551583747227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22325141544d575830484d4e335737465237354b36314339463054415a3550504a3545355443584337415858335450445252335347227d
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickup_signatures; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tip_pickup_signatures (pickup_serial, coin_offset, blind_sig) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tip_pickups (pickup_serial, tip_serial, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tip_reserve_keys (reserve_serial, reserve_priv, exchange_url, payto_uri) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tip_reserves (reserve_serial, reserve_pub, merchant_serial, creation_time, expiration, merchant_initial_balance_val, merchant_initial_balance_frac, exchange_initial_balance_val, exchange_initial_balance_frac, tips_committed_val, tips_committed_frac, tips_picked_up_val, tips_picked_up_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tips (tip_serial, reserve_serial, tip_id, justification, next_url, expiration, amount_val, amount_frac, picked_up_val, picked_up_frac, was_picked_up) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_signatures; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_transfer_signatures (credit_serial, signkey_serial, wire_fee_val, wire_fee_frac, credit_amount_val, credit_amount_frac, execution_time, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_to_coin; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_transfer_to_coin (deposit_serial, credit_serial, offset_in_exchange_list, exchange_deposit_value_val, exchange_deposit_value_frac, exchange_deposit_fee_val, exchange_deposit_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_transfers (credit_serial, exchange_url, wtid, credit_amount_val, credit_amount_frac, account_serial, verified, confirmed) FROM stdin;
\.


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: auditor; Owner: -
--

SELECT pg_catalog.setval('auditor.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: auditor; Owner: -
--

SELECT pg_catalog.setval('auditor.deposit_confirmations_serial_id_seq', 1, false);


--
-- Name: account_merges_account_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.account_merges_account_merge_request_serial_id_seq', 1, false);


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.aggregation_tracking_aggregation_serial_id_seq', 1, false);


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.auditor_denom_sigs_auditor_denom_serial_seq', 424, true);


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.auditors_auditor_uuid_seq', 1, true);


--
-- Name: close_requests_close_request_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.close_requests_close_request_serial_id_seq', 1, false);


--
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.contracts_contract_serial_id_seq', 1, false);


--
-- Name: cs_nonce_locks_cs_nonce_lock_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.cs_nonce_locks_cs_nonce_lock_serial_id_seq', 1, false);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.denominations_denominations_serial_seq', 424, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.deposits_deposit_serial_id_seq', 1, false);


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.exchange_sign_keys_esk_serial_seq', 5, true);


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.extension_details_extension_details_serial_id_seq', 1, false);


--
-- Name: extensions_extension_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.extensions_extension_id_seq', 1, false);


--
-- Name: global_fee_global_fee_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.global_fee_global_fee_serial_seq', 1, true);


--
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.history_requests_history_request_serial_id_seq', 1, false);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.known_coins_known_coin_id_seq', 1, true);


--
-- Name: legitimizations_legitimization_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.legitimizations_legitimization_serial_id_seq', 1, false);


--
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.partners_partner_serial_id_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.prewire_prewire_uuid_seq', 1, false);


--
-- Name: profit_drains_profit_drain_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.profit_drains_profit_drain_serial_id_seq', 1, false);


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.purse_deposits_purse_deposit_serial_id_seq', 1, false);


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.purse_merges_purse_merge_request_serial_id_seq', 1, false);


--
-- Name: purse_refunds_purse_refunds_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.purse_refunds_purse_refunds_serial_id_seq', 1, false);


--
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.purse_requests_purse_requests_serial_id_seq', 1, false);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.recoup_recoup_uuid_seq', 1, false);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.recoup_refresh_recoup_refresh_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_commitments_melt_serial_id_seq', 1, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_revealed_coins_rrc_serial_seq', 1, false);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_transfer_keys_rtc_serial_seq', 1, false);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refunds_refund_serial_id_seq', 1, false);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 9, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 12, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 9, true);


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.revolving_work_shards_shard_serial_id_seq', 1, false);


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wad_in_entries_wad_in_entry_serial_id_seq', 1, false);


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wad_out_entries_wad_out_entry_serial_id_seq', 1, false);


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wads_in_wad_in_serial_id_seq', 1, false);


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wads_out_wad_out_serial_id_seq', 1, false);


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wire_fee_wire_fee_serial_seq', 1, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wire_out_wireout_uuid_seq', 1, false);


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 1, true);


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.work_shards_shard_serial_id_seq', 1, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_deposits_deposit_serial_seq', 1, false);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_exchange_signing_keys_signkey_serial_seq', 5, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_exchange_wire_fees_wirefee_serial_seq', 1, true);


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_instances_merchant_serial_seq', 1, true);


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_inventory_product_serial_seq', 1, false);


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_kyc_kyc_serial_id_seq', 1, false);


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_orders_order_serial_seq', 1, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_refunds_refund_serial_seq', 1, false);


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_tip_pickups_pickup_serial_seq', 1, false);


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_tip_reserves_reserve_serial_seq', 1, false);


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_tips_tip_serial_seq', 1, false);


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_transfers_credit_serial_seq', 1, false);


--
-- Name: patches patches_pkey; Type: CONSTRAINT; Schema: _v; Owner: -
--

ALTER TABLE ONLY _v.patches
    ADD CONSTRAINT patches_pkey PRIMARY KEY (patch_name);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_exchanges auditor_exchanges_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_exchanges
    ADD CONSTRAINT auditor_exchanges_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_historic_denomination_revenue auditor_historic_denomination_revenue_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_historic_denomination_revenue
    ADD CONSTRAINT auditor_historic_denomination_revenue_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_progress_aggregation auditor_progress_aggregation_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_aggregation
    ADD CONSTRAINT auditor_progress_aggregation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_coin auditor_progress_coin_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_coin
    ADD CONSTRAINT auditor_progress_coin_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_deposit_confirmation auditor_progress_deposit_confirmation_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_deposit_confirmation
    ADD CONSTRAINT auditor_progress_deposit_confirmation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_reserve auditor_progress_reserve_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_reserve
    ADD CONSTRAINT auditor_progress_reserve_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


--
-- Name: deposit_confirmations deposit_confirmations_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_pkey PRIMARY KEY (h_contract_terms, h_wire, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig);


--
-- Name: deposit_confirmations deposit_confirmations_serial_id_key; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_serial_id_key UNIQUE (serial_id);


--
-- Name: wire_auditor_account_progress wire_auditor_account_progress_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.wire_auditor_account_progress
    ADD CONSTRAINT wire_auditor_account_progress_pkey PRIMARY KEY (master_pub, account_name);


--
-- Name: wire_auditor_progress wire_auditor_progress_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.wire_auditor_progress
    ADD CONSTRAINT wire_auditor_progress_pkey PRIMARY KEY (master_pub);


--
-- Name: account_merges_default account_merges_default_account_merge_request_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.account_merges_default
    ADD CONSTRAINT account_merges_default_account_merge_request_serial_id_key UNIQUE (account_merge_request_serial_id);


--
-- Name: account_merges account_merges_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.account_merges
    ADD CONSTRAINT account_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: account_merges_default account_merges_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.account_merges_default
    ADD CONSTRAINT account_merges_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: aggregation_tracking_default aggregation_tracking_default_aggregation_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.aggregation_tracking_default
    ADD CONSTRAINT aggregation_tracking_default_aggregation_serial_id_key UNIQUE (aggregation_serial_id);


--
-- Name: aggregation_tracking aggregation_tracking_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: aggregation_tracking_default aggregation_tracking_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.aggregation_tracking_default
    ADD CONSTRAINT aggregation_tracking_default_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_denom_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_denom_serial_key UNIQUE (auditor_denom_serial);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denominations_serial, auditor_uuid);


--
-- Name: auditors auditors_auditor_uuid_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditors
    ADD CONSTRAINT auditors_auditor_uuid_key UNIQUE (auditor_uuid);


--
-- Name: auditors auditors_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditors
    ADD CONSTRAINT auditors_pkey PRIMARY KEY (auditor_pub);


--
-- Name: close_requests close_requests_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.close_requests
    ADD CONSTRAINT close_requests_pkey PRIMARY KEY (reserve_pub, close_timestamp);


--
-- Name: close_requests_default close_requests_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.close_requests_default
    ADD CONSTRAINT close_requests_default_pkey PRIMARY KEY (reserve_pub, close_timestamp);


--
-- Name: contracts_default contracts_default_contract_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.contracts_default
    ADD CONSTRAINT contracts_default_contract_serial_id_key UNIQUE (contract_serial_id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (purse_pub);


--
-- Name: contracts_default contracts_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.contracts_default
    ADD CONSTRAINT contracts_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: cs_nonce_locks_default cs_nonce_locks_default_cs_nonce_lock_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.cs_nonce_locks_default
    ADD CONSTRAINT cs_nonce_locks_default_cs_nonce_lock_serial_id_key UNIQUE (cs_nonce_lock_serial_id);


--
-- Name: cs_nonce_locks cs_nonce_locks_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.cs_nonce_locks
    ADD CONSTRAINT cs_nonce_locks_pkey PRIMARY KEY (nonce);


--
-- Name: cs_nonce_locks_default cs_nonce_locks_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.cs_nonce_locks_default
    ADD CONSTRAINT cs_nonce_locks_default_pkey PRIMARY KEY (nonce);


--
-- Name: denomination_revocations denomination_revocations_denom_revocations_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_revocations_serial_id_key UNIQUE (denom_revocations_serial_id);


--
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denominations_serial);


--
-- Name: denominations denominations_denominations_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denominations
    ADD CONSTRAINT denominations_denominations_serial_key UNIQUE (denominations_serial);


--
-- Name: denominations denominations_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denominations
    ADD CONSTRAINT denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: deposits_default deposits_default_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.deposits_default
    ADD CONSTRAINT deposits_default_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_default deposits_default_deposit_serial_id_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.deposits_default
    ADD CONSTRAINT deposits_default_deposit_serial_id_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: exchange_sign_keys exchange_sign_keys_esk_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_esk_serial_key UNIQUE (esk_serial);


--
-- Name: exchange_sign_keys exchange_sign_keys_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_pkey PRIMARY KEY (exchange_pub);


--
-- Name: extension_details extension_details_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.extension_details
    ADD CONSTRAINT extension_details_pkey PRIMARY KEY (extension_details_serial_id);


--
-- Name: extension_details_default extension_details_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.extension_details_default
    ADD CONSTRAINT extension_details_default_pkey PRIMARY KEY (extension_details_serial_id);


--
-- Name: extensions extensions_extension_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.extensions
    ADD CONSTRAINT extensions_extension_id_key UNIQUE (extension_id);


--
-- Name: extensions extensions_name_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.extensions
    ADD CONSTRAINT extensions_name_key UNIQUE (name);


--
-- Name: global_fee global_fee_global_fee_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.global_fee
    ADD CONSTRAINT global_fee_global_fee_serial_key UNIQUE (global_fee_serial);


--
-- Name: global_fee global_fee_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.global_fee
    ADD CONSTRAINT global_fee_pkey PRIMARY KEY (start_date);


--
-- Name: history_requests history_requests_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.history_requests
    ADD CONSTRAINT history_requests_pkey PRIMARY KEY (reserve_pub, request_timestamp);


--
-- Name: history_requests_default history_requests_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.history_requests_default
    ADD CONSTRAINT history_requests_default_pkey PRIMARY KEY (reserve_pub, request_timestamp);


--
-- Name: known_coins_default known_coins_default_known_coin_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.known_coins_default
    ADD CONSTRAINT known_coins_default_known_coin_id_key UNIQUE (known_coin_id);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: known_coins_default known_coins_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.known_coins_default
    ADD CONSTRAINT known_coins_default_pkey PRIMARY KEY (coin_pub);


--
-- Name: legitimizations_default legitimizations_default_legitimization_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimizations_default
    ADD CONSTRAINT legitimizations_default_legitimization_serial_id_key UNIQUE (legitimization_serial_id);


--
-- Name: partner_accounts partner_accounts_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.partner_accounts
    ADD CONSTRAINT partner_accounts_pkey PRIMARY KEY (payto_uri);


--
-- Name: partners partners_partner_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.partners
    ADD CONSTRAINT partners_partner_serial_id_key UNIQUE (partner_serial_id);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: prewire_default prewire_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.prewire_default
    ADD CONSTRAINT prewire_default_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: profit_drains profit_drains_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.profit_drains
    ADD CONSTRAINT profit_drains_pkey PRIMARY KEY (wtid);


--
-- Name: profit_drains profit_drains_profit_drain_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.profit_drains
    ADD CONSTRAINT profit_drains_profit_drain_serial_id_key UNIQUE (profit_drain_serial_id);


--
-- Name: purse_actions purse_actions_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_actions
    ADD CONSTRAINT purse_actions_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_deposits purse_deposits_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_deposits
    ADD CONSTRAINT purse_deposits_pkey PRIMARY KEY (purse_pub, coin_pub);


--
-- Name: purse_deposits_default purse_deposits_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_deposits_default
    ADD CONSTRAINT purse_deposits_default_pkey PRIMARY KEY (purse_pub, coin_pub);


--
-- Name: purse_deposits_default purse_deposits_default_purse_deposit_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_deposits_default
    ADD CONSTRAINT purse_deposits_default_purse_deposit_serial_id_key UNIQUE (purse_deposit_serial_id);


--
-- Name: purse_merges purse_merges_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_merges
    ADD CONSTRAINT purse_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_merges_default purse_merges_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_merges_default
    ADD CONSTRAINT purse_merges_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_merges_default purse_merges_default_purse_merge_request_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_merges_default
    ADD CONSTRAINT purse_merges_default_purse_merge_request_serial_id_key UNIQUE (purse_merge_request_serial_id);


--
-- Name: purse_refunds purse_refunds_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_refunds
    ADD CONSTRAINT purse_refunds_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_refunds_default purse_refunds_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_refunds_default
    ADD CONSTRAINT purse_refunds_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_refunds_default purse_refunds_default_purse_refunds_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_refunds_default
    ADD CONSTRAINT purse_refunds_default_purse_refunds_serial_id_key UNIQUE (purse_refunds_serial_id);


--
-- Name: purse_requests purse_requests_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_requests
    ADD CONSTRAINT purse_requests_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests_default purse_requests_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_requests_default
    ADD CONSTRAINT purse_requests_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests_default purse_requests_default_purse_requests_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_requests_default
    ADD CONSTRAINT purse_requests_default_purse_requests_serial_id_key UNIQUE (purse_requests_serial_id);


--
-- Name: recoup_default recoup_default_recoup_uuid_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.recoup_default
    ADD CONSTRAINT recoup_default_recoup_uuid_key UNIQUE (recoup_uuid);


--
-- Name: recoup_refresh_default recoup_refresh_default_recoup_refresh_uuid_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.recoup_refresh_default
    ADD CONSTRAINT recoup_refresh_default_recoup_refresh_uuid_key UNIQUE (recoup_refresh_uuid);


--
-- Name: refresh_commitments_default refresh_commitments_default_melt_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_commitments_default
    ADD CONSTRAINT refresh_commitments_default_melt_serial_id_key UNIQUE (melt_serial_id);


--
-- Name: refresh_commitments refresh_commitments_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_commitments
    ADD CONSTRAINT refresh_commitments_pkey PRIMARY KEY (rc);


--
-- Name: refresh_commitments_default refresh_commitments_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_commitments_default
    ADD CONSTRAINT refresh_commitments_default_pkey PRIMARY KEY (rc);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_coin_ev_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_coin_ev_key UNIQUE (coin_ev);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_h_coin_ev_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_h_coin_ev_key UNIQUE (h_coin_ev);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_pkey PRIMARY KEY (melt_serial_id, freshcoin_index);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_rrc_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys_default refresh_transfer_keys_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_transfer_keys_default
    ADD CONSTRAINT refresh_transfer_keys_default_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys_default refresh_transfer_keys_default_rtc_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_transfer_keys_default
    ADD CONSTRAINT refresh_transfer_keys_default_rtc_serial_key UNIQUE (rtc_serial);


--
-- Name: refunds_default refunds_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refunds_default
    ADD CONSTRAINT refunds_default_pkey PRIMARY KEY (deposit_serial_id, rtransaction_id);


--
-- Name: refunds_default refunds_default_refund_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refunds_default
    ADD CONSTRAINT refunds_default_refund_serial_id_key UNIQUE (refund_serial_id);


--
-- Name: reserves_close_default reserves_close_default_close_uuid_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_close_default
    ADD CONSTRAINT reserves_close_default_close_uuid_pkey PRIMARY KEY (close_uuid);


--
-- Name: reserves reserves_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves
    ADD CONSTRAINT reserves_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_default reserves_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_default
    ADD CONSTRAINT reserves_default_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in_default reserves_in_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_in_default
    ADD CONSTRAINT reserves_in_default_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in_default reserves_in_default_reserve_in_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_in_default
    ADD CONSTRAINT reserves_in_default_reserve_in_serial_id_key UNIQUE (reserve_in_serial_id);


--
-- Name: reserves_out reserves_out_h_blind_ev_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_out
    ADD CONSTRAINT reserves_out_h_blind_ev_key UNIQUE (h_blind_ev);


--
-- Name: reserves_out_default reserves_out_default_h_blind_ev_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_out_default
    ADD CONSTRAINT reserves_out_default_h_blind_ev_key UNIQUE (h_blind_ev);


--
-- Name: reserves_out_default reserves_out_default_reserve_out_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_out_default
    ADD CONSTRAINT reserves_out_default_reserve_out_serial_id_key UNIQUE (reserve_out_serial_id);


--
-- Name: revolving_work_shards revolving_work_shards_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: revolving_work_shards revolving_work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


--
-- Name: signkey_revocations signkey_revocations_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.signkey_revocations
    ADD CONSTRAINT signkey_revocations_pkey PRIMARY KEY (esk_serial);


--
-- Name: signkey_revocations signkey_revocations_signkey_revocations_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.signkey_revocations
    ADD CONSTRAINT signkey_revocations_signkey_revocations_serial_id_key UNIQUE (signkey_revocations_serial_id);


--
-- Name: wad_in_entries wad_in_entries_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_in_entries
    ADD CONSTRAINT wad_in_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_in_entries_default wad_in_entries_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_in_entries_default
    ADD CONSTRAINT wad_in_entries_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_in_entries_default wad_in_entries_default_wad_in_entry_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_in_entries_default
    ADD CONSTRAINT wad_in_entries_default_wad_in_entry_serial_id_key UNIQUE (wad_in_entry_serial_id);


--
-- Name: wad_out_entries wad_out_entries_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_out_entries
    ADD CONSTRAINT wad_out_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries_default wad_out_entries_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_out_entries_default
    ADD CONSTRAINT wad_out_entries_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries_default wad_out_entries_default_wad_out_entry_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_out_entries_default
    ADD CONSTRAINT wad_out_entries_default_wad_out_entry_serial_id_key UNIQUE (wad_out_entry_serial_id);


--
-- Name: wads_in wads_in_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in
    ADD CONSTRAINT wads_in_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in_default wads_in_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in_default
    ADD CONSTRAINT wads_in_default_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in wads_in_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in
    ADD CONSTRAINT wads_in_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in_default wads_in_default_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in_default wads_in_default_wad_in_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_in_serial_id_key UNIQUE (wad_in_serial_id);


--
-- Name: wads_in_default wads_in_default_wad_is_origin_exchange_url_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_is_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_out wads_out_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_out
    ADD CONSTRAINT wads_out_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out_default wads_out_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_out_default
    ADD CONSTRAINT wads_out_default_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out_default wads_out_default_wad_out_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_out_default
    ADD CONSTRAINT wads_out_default_wad_out_serial_id_key UNIQUE (wad_out_serial_id);


--
-- Name: wire_accounts wire_accounts_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_accounts
    ADD CONSTRAINT wire_accounts_pkey PRIMARY KEY (payto_uri);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


--
-- Name: wire_fee wire_fee_wire_fee_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_fee
    ADD CONSTRAINT wire_fee_wire_fee_serial_key UNIQUE (wire_fee_serial);


--
-- Name: wire_out_default wire_out_default_wireout_uuid_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_out_default
    ADD CONSTRAINT wire_out_default_wireout_uuid_pkey PRIMARY KEY (wireout_uuid);


--
-- Name: wire_out wire_out_wtid_raw_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_out
    ADD CONSTRAINT wire_out_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: wire_out_default wire_out_default_wtid_raw_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_out_default
    ADD CONSTRAINT wire_out_default_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: wire_targets wire_targets_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_targets
    ADD CONSTRAINT wire_targets_pkey PRIMARY KEY (wire_target_h_payto);


--
-- Name: wire_targets_default wire_targets_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_targets_default
    ADD CONSTRAINT wire_targets_default_pkey PRIMARY KEY (wire_target_h_payto);


--
-- Name: wire_targets_default wire_targets_default_wire_target_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_targets_default
    ADD CONSTRAINT wire_targets_default_wire_target_serial_id_key UNIQUE (wire_target_serial_id);


--
-- Name: work_shards work_shards_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.work_shards
    ADD CONSTRAINT work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: work_shards work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.work_shards
    ADD CONSTRAINT work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


--
-- Name: merchant_accounts merchant_accounts_h_wire_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_accounts
    ADD CONSTRAINT merchant_accounts_h_wire_key UNIQUE (h_wire);


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_payto_uri_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_payto_uri_key UNIQUE (merchant_serial, payto_uri);


--
-- Name: merchant_accounts merchant_accounts_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_accounts
    ADD CONSTRAINT merchant_accounts_pkey PRIMARY KEY (account_serial);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_h_contract_terms_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_h_contract_terms_key UNIQUE (merchant_serial, h_contract_terms);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_credit_serial_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_credit_serial_key UNIQUE (deposit_serial, credit_serial);


--
-- Name: merchant_deposits merchant_deposits_order_serial_coin_pub_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_coin_pub_key UNIQUE (order_serial, coin_pub);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (deposit_serial);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_key_exchange_pub_start_date_maste_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_key_exchange_pub_start_date_maste_key UNIQUE (exchange_pub, start_date, master_pub);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_keys_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_keys_pkey PRIMARY KEY (signkey_serial);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_master_pub_h_wire_method_start__key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_master_pub_h_wire_method_start__key UNIQUE (master_pub, h_wire_method, start_date);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_pkey PRIMARY KEY (wirefee_serial);


--
-- Name: merchant_instances merchant_instances_merchant_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_id_key UNIQUE (merchant_id);


--
-- Name: merchant_instances merchant_instances_merchant_pub_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_pub_key UNIQUE (merchant_pub);


--
-- Name: merchant_instances merchant_instances_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_instances
    ADD CONSTRAINT merchant_instances_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_product_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_product_id_key UNIQUE (merchant_serial, product_id);


--
-- Name: merchant_inventory merchant_inventory_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_inventory
    ADD CONSTRAINT merchant_inventory_pkey PRIMARY KEY (product_serial);


--
-- Name: merchant_keys merchant_keys_merchant_priv_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_priv_key UNIQUE (merchant_priv);


--
-- Name: merchant_keys merchant_keys_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_keys
    ADD CONSTRAINT merchant_keys_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_kyc merchant_kyc_kyc_serial_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_kyc
    ADD CONSTRAINT merchant_kyc_kyc_serial_id_key UNIQUE (kyc_serial_id);


--
-- Name: merchant_kyc merchant_kyc_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_kyc
    ADD CONSTRAINT merchant_kyc_pkey PRIMARY KEY (account_serial, exchange_url);


--
-- Name: merchant_orders merchant_orders_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_refund_proofs merchant_refund_proofs_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_refunds merchant_refunds_order_serial_coin_pub_rtransaction_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_coin_pub_rtransaction_id_key UNIQUE (order_serial, coin_pub, rtransaction_id);


--
-- Name: merchant_refunds merchant_refunds_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refunds
    ADD CONSTRAINT merchant_refunds_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pkey PRIMARY KEY (pickup_serial, coin_offset);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pickup_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pickup_id_key UNIQUE (pickup_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_serial);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_priv_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_priv_key UNIQUE (reserve_priv);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_key UNIQUE (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_reserve_pub_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_reserve_pub_key UNIQUE (reserve_pub);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_serial);


--
-- Name: merchant_tips merchant_tips_tip_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tips
    ADD CONSTRAINT merchant_tips_tip_id_key UNIQUE (tip_id);


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_key UNIQUE (deposit_serial);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfers merchant_transfers_wtid_exchange_url_account_serial_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfers
    ADD CONSTRAINT merchant_transfers_wtid_exchange_url_account_serial_key UNIQUE (wtid, exchange_url, account_serial);


--
-- Name: auditor_historic_reserve_summary_by_master_pub_start_date; Type: INDEX; Schema: auditor; Owner: -
--

CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date ON auditor.auditor_historic_reserve_summary USING btree (master_pub, start_date);


--
-- Name: auditor_reserves_by_reserve_pub; Type: INDEX; Schema: auditor; Owner: -
--

CREATE INDEX auditor_reserves_by_reserve_pub ON auditor.auditor_reserves USING btree (reserve_pub);


--
-- Name: account_merges_by_reserve_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX account_merges_by_reserve_pub ON ONLY exchange.account_merges USING btree (reserve_pub);


--
-- Name: account_merges_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX account_merges_default_reserve_pub_idx ON exchange.account_merges_default USING btree (reserve_pub);


--
-- Name: aggregation_tracking_by_wtid_raw_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX aggregation_tracking_by_wtid_raw_index ON ONLY exchange.aggregation_tracking USING btree (wtid_raw);


--
-- Name: INDEX aggregation_tracking_by_wtid_raw_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.aggregation_tracking_by_wtid_raw_index IS 'for lookup_transactions';


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX aggregation_tracking_default_wtid_raw_idx ON exchange.aggregation_tracking_default USING btree (wtid_raw);


--
-- Name: denominations_by_expire_legal_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX denominations_by_expire_legal_index ON exchange.denominations USING btree (expire_legal);


--
-- Name: deposits_by_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_by_coin_pub_index ON ONLY exchange.deposits USING btree (coin_pub);


--
-- Name: deposits_by_ready_main_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_by_ready_main_index ON ONLY exchange.deposits_by_ready USING btree (wire_deadline, shard, coin_pub);


--
-- Name: deposits_by_ready_default_wire_deadline_shard_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_by_ready_default_wire_deadline_shard_coin_pub_idx ON exchange.deposits_by_ready_default USING btree (wire_deadline, shard, coin_pub);


--
-- Name: deposits_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_default_coin_pub_idx ON exchange.deposits_default USING btree (coin_pub);


--
-- Name: deposits_for_matching_main_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_for_matching_main_index ON ONLY exchange.deposits_for_matching USING btree (refund_deadline, merchant_pub, coin_pub);


--
-- Name: deposits_for_matching_default_refund_deadline_merchant_pub__idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_for_matching_default_refund_deadline_merchant_pub__idx ON exchange.deposits_for_matching_default USING btree (refund_deadline, merchant_pub, coin_pub);


--
-- Name: global_fee_by_end_date_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX global_fee_by_end_date_index ON exchange.global_fee USING btree (end_date);


--
-- Name: legitimizations_default_by_provider_and_legi_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX legitimizations_default_by_provider_and_legi_index ON exchange.legitimizations_default USING btree (provider_section, provider_legitimization_id);


--
-- Name: INDEX legitimizations_default_by_provider_and_legi_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.legitimizations_default_by_provider_and_legi_index IS 'used (rarely) in kyc_provider_account_lookup';


--
-- Name: partner_accounts_index_by_partner_and_time; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX partner_accounts_index_by_partner_and_time ON exchange.partner_accounts USING btree (partner_serial_id, last_seen);


--
-- Name: partner_by_wad_time; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX partner_by_wad_time ON exchange.partners USING btree (next_wad);


--
-- Name: prewire_by_failed_finished_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX prewire_by_failed_finished_index ON ONLY exchange.prewire USING btree (failed, finished);


--
-- Name: INDEX prewire_by_failed_finished_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.prewire_by_failed_finished_index IS 'for wire_prepare_data_get';


--
-- Name: prewire_by_finished_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX prewire_by_finished_index ON ONLY exchange.prewire USING btree (finished);


--
-- Name: INDEX prewire_by_finished_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.prewire_by_finished_index IS 'for gc_prewire';


--
-- Name: prewire_default_failed_finished_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX prewire_default_failed_finished_idx ON exchange.prewire_default USING btree (failed, finished);


--
-- Name: prewire_default_finished_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX prewire_default_finished_idx ON exchange.prewire_default USING btree (finished);


--
-- Name: purse_action_by_target; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_action_by_target ON exchange.purse_actions USING btree (partner_serial_id, action_date);


--
-- Name: purse_deposits_by_coin_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_deposits_by_coin_pub ON ONLY exchange.purse_deposits USING btree (coin_pub);


--
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_deposits_default_coin_pub_idx ON exchange.purse_deposits_default USING btree (coin_pub);


--
-- Name: purse_merges_reserve_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_merges_reserve_pub ON ONLY exchange.purse_merges USING btree (reserve_pub);


--
-- Name: INDEX purse_merges_reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.purse_merges_reserve_pub IS 'needed in reserve history computation';


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_merges_default_reserve_pub_idx ON exchange.purse_merges_default USING btree (reserve_pub);


--
-- Name: purse_requests_merge_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_requests_merge_pub ON ONLY exchange.purse_requests USING btree (merge_pub);


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_requests_default_merge_pub_idx ON exchange.purse_requests_default USING btree (merge_pub);


--
-- Name: purse_requests_purse_expiration; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_requests_purse_expiration ON ONLY exchange.purse_requests USING btree (purse_expiration);


--
-- Name: purse_requests_default_purse_expiration_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_requests_default_purse_expiration_idx ON exchange.purse_requests_default USING btree (purse_expiration);


--
-- Name: recoup_by_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_by_coin_pub_index ON ONLY exchange.recoup USING btree (coin_pub);


--
-- Name: recoup_by_reserve_main_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_by_reserve_main_index ON ONLY exchange.recoup_by_reserve USING btree (reserve_out_serial_id);


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_by_reserve_default_reserve_out_serial_id_idx ON exchange.recoup_by_reserve_default USING btree (reserve_out_serial_id);


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_default_coin_pub_idx ON exchange.recoup_default USING btree (coin_pub);


--
-- Name: recoup_refresh_by_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_refresh_by_coin_pub_index ON ONLY exchange.recoup_refresh USING btree (coin_pub);


--
-- Name: recoup_refresh_by_rrc_serial_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_refresh_by_rrc_serial_index ON ONLY exchange.recoup_refresh USING btree (rrc_serial);


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_refresh_default_coin_pub_idx ON exchange.recoup_refresh_default USING btree (coin_pub);


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_refresh_default_rrc_serial_idx ON exchange.recoup_refresh_default USING btree (rrc_serial);


--
-- Name: refresh_commitments_by_old_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refresh_commitments_by_old_coin_pub_index ON ONLY exchange.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refresh_commitments_default_old_coin_pub_idx ON exchange.refresh_commitments_default USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_coins_by_melt_serial_id_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refresh_revealed_coins_coins_by_melt_serial_id_index ON ONLY exchange.refresh_revealed_coins USING btree (melt_serial_id);


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refresh_revealed_coins_default_melt_serial_id_idx ON exchange.refresh_revealed_coins_default USING btree (melt_serial_id);


--
-- Name: refunds_by_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refunds_by_coin_pub_index ON ONLY exchange.refunds USING btree (coin_pub);


--
-- Name: refunds_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refunds_default_coin_pub_idx ON exchange.refunds_default USING btree (coin_pub);


--
-- Name: reserves_by_expiration_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_by_expiration_index ON ONLY exchange.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: INDEX reserves_by_expiration_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.reserves_by_expiration_index IS 'used in get_expired_reserves';


--
-- Name: reserves_by_gc_date_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_by_gc_date_index ON ONLY exchange.reserves USING btree (gc_date);


--
-- Name: INDEX reserves_by_gc_date_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.reserves_by_gc_date_index IS 'for reserve garbage collection';


--
-- Name: reserves_by_reserve_uuid_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_by_reserve_uuid_index ON ONLY exchange.reserves USING btree (reserve_uuid);


--
-- Name: reserves_close_by_close_uuid_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_close_by_close_uuid_index ON ONLY exchange.reserves_close USING btree (close_uuid);


--
-- Name: reserves_close_by_reserve_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_close_by_reserve_pub_index ON ONLY exchange.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_close_default_close_uuid_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_close_default_close_uuid_idx ON exchange.reserves_close_default USING btree (close_uuid);


--
-- Name: reserves_close_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_close_default_reserve_pub_idx ON exchange.reserves_close_default USING btree (reserve_pub);


--
-- Name: reserves_default_expiration_date_current_balance_val_curren_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_default_expiration_date_current_balance_val_curren_idx ON exchange.reserves_default USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_default_gc_date_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_default_gc_date_idx ON exchange.reserves_default USING btree (gc_date);


--
-- Name: reserves_default_reserve_uuid_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_default_reserve_uuid_idx ON exchange.reserves_default USING btree (reserve_uuid);


--
-- Name: reserves_in_by_exch_accnt_reserve_in_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_by_exch_accnt_reserve_in_serial_id_idx ON ONLY exchange.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_by_exch_accnt_section_execution_date_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_by_exch_accnt_section_execution_date_idx ON ONLY exchange.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_by_reserve_in_serial_id_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_by_reserve_in_serial_id_index ON ONLY exchange.reserves_in USING btree (reserve_in_serial_id);


--
-- Name: reserves_in_default_exchange_account_section_execution_date_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_default_exchange_account_section_execution_date_idx ON exchange.reserves_in_default USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_default_exchange_account_section_reserve_in_ser_idx ON exchange.reserves_in_default USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_default_reserve_in_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_default_reserve_in_serial_id_idx ON exchange.reserves_in_default USING btree (reserve_in_serial_id);


--
-- Name: reserves_out_by_reserve_main_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_by_reserve_main_index ON ONLY exchange.reserves_out_by_reserve USING btree (reserve_uuid);


--
-- Name: reserves_out_by_reserve_default_reserve_uuid_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_by_reserve_default_reserve_uuid_idx ON exchange.reserves_out_by_reserve_default USING btree (reserve_uuid);


--
-- Name: reserves_out_by_reserve_out_serial_id_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_by_reserve_out_serial_id_index ON ONLY exchange.reserves_out USING btree (reserve_out_serial_id);


--
-- Name: reserves_out_by_reserve_uuid_and_execution_date_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_by_reserve_uuid_and_execution_date_index ON ONLY exchange.reserves_out USING btree (reserve_uuid, execution_date);


--
-- Name: INDEX reserves_out_by_reserve_uuid_and_execution_date_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.reserves_out_by_reserve_uuid_and_execution_date_index IS 'for get_reserves_out and exchange_do_withdraw_limit_check';


--
-- Name: reserves_out_default_reserve_out_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_default_reserve_out_serial_id_idx ON exchange.reserves_out_default USING btree (reserve_out_serial_id);


--
-- Name: reserves_out_default_reserve_uuid_execution_date_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_default_reserve_uuid_execution_date_idx ON exchange.reserves_out_default USING btree (reserve_uuid, execution_date);


--
-- Name: revolving_work_shards_by_job_name_active_last_attempt_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX revolving_work_shards_by_job_name_active_last_attempt_index ON exchange.revolving_work_shards USING btree (job_name, active, last_attempt);


--
-- Name: wad_in_entries_reserve_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wad_in_entries_reserve_pub ON ONLY exchange.wad_in_entries USING btree (reserve_pub);


--
-- Name: INDEX wad_in_entries_reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.wad_in_entries_reserve_pub IS 'needed in reserve history computation';


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wad_in_entries_default_reserve_pub_idx ON exchange.wad_in_entries_default USING btree (reserve_pub);


--
-- Name: wad_out_entries_by_reserve_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wad_out_entries_by_reserve_pub ON ONLY exchange.wad_out_entries USING btree (reserve_pub);


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wad_out_entries_default_reserve_pub_idx ON exchange.wad_out_entries_default USING btree (reserve_pub);


--
-- Name: wire_fee_by_end_date_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wire_fee_by_end_date_index ON exchange.wire_fee USING btree (end_date);


--
-- Name: wire_out_by_wire_target_h_payto_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wire_out_by_wire_target_h_payto_index ON ONLY exchange.wire_out USING btree (wire_target_h_payto);


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wire_out_default_wire_target_h_payto_idx ON exchange.wire_out_default USING btree (wire_target_h_payto);


--
-- Name: work_shards_by_job_name_completed_last_attempt_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX work_shards_by_job_name_completed_last_attempt_index ON exchange.work_shards USING btree (job_name, completed, last_attempt);


--
-- Name: merchant_contract_terms_by_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_contract_terms_by_expiration ON merchant.merchant_contract_terms USING btree (paid, pay_deadline);


--
-- Name: INDEX merchant_contract_terms_by_expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON INDEX merchant.merchant_contract_terms_by_expiration IS 'for unlock_contracts';


--
-- Name: merchant_contract_terms_by_merchant_and_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_expiration ON merchant.merchant_contract_terms USING btree (merchant_serial, pay_deadline);


--
-- Name: INDEX merchant_contract_terms_by_merchant_and_expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON INDEX merchant.merchant_contract_terms_by_merchant_and_expiration IS 'for delete_contract_terms';


--
-- Name: merchant_contract_terms_by_merchant_and_payment; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_payment ON merchant.merchant_contract_terms USING btree (merchant_serial, paid);


--
-- Name: merchant_contract_terms_by_merchant_session_and_fulfillment; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_session_and_fulfillment ON merchant.merchant_contract_terms USING btree (merchant_serial, fulfillment_url, session_id);


--
-- Name: merchant_inventory_locks_by_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_expiration ON merchant.merchant_inventory_locks USING btree (expiration);


--
-- Name: merchant_inventory_locks_by_uuid; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_uuid ON merchant.merchant_inventory_locks USING btree (lock_uuid);


--
-- Name: merchant_orders_by_creation_time; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_orders_by_creation_time ON merchant.merchant_orders USING btree (creation_time);


--
-- Name: merchant_orders_by_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_orders_by_expiration ON merchant.merchant_orders USING btree (pay_deadline);


--
-- Name: merchant_orders_locks_by_order_and_product; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_orders_locks_by_order_and_product ON merchant.merchant_order_locks USING btree (order_serial, product_serial);


--
-- Name: merchant_refunds_by_coin_and_order; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_refunds_by_coin_and_order ON merchant.merchant_refunds USING btree (coin_pub, order_serial);


--
-- Name: merchant_tip_reserves_by_exchange_balance; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_exchange_balance ON merchant.merchant_tip_reserves USING btree (exchange_initial_balance_val, exchange_initial_balance_frac);


--
-- Name: merchant_tip_reserves_by_merchant_serial_and_creation_time; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_merchant_serial_and_creation_time ON merchant.merchant_tip_reserves USING btree (merchant_serial, creation_time);


--
-- Name: merchant_tip_reserves_by_reserve_pub_and_merchant_serial; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_reserve_pub_and_merchant_serial ON merchant.merchant_tip_reserves USING btree (reserve_pub, merchant_serial, creation_time);


--
-- Name: merchant_tips_by_pickup_and_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_tips_by_pickup_and_expiration ON merchant.merchant_tips USING btree (was_picked_up, expiration);


--
-- Name: merchant_transfers_by_credit; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_transfers_by_credit ON merchant.merchant_transfer_to_coin USING btree (credit_serial);


--
-- Name: account_merges_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.account_merges_pkey ATTACH PARTITION exchange.account_merges_default_pkey;


--
-- Name: account_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.account_merges_by_reserve_pub ATTACH PARTITION exchange.account_merges_default_reserve_pub_idx;


--
-- Name: aggregation_tracking_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.aggregation_tracking_pkey ATTACH PARTITION exchange.aggregation_tracking_default_pkey;


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.aggregation_tracking_by_wtid_raw_index ATTACH PARTITION exchange.aggregation_tracking_default_wtid_raw_idx;


--
-- Name: close_requests_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.close_requests_pkey ATTACH PARTITION exchange.close_requests_default_pkey;


--
-- Name: contracts_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.contracts_pkey ATTACH PARTITION exchange.contracts_default_pkey;


--
-- Name: cs_nonce_locks_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.cs_nonce_locks_pkey ATTACH PARTITION exchange.cs_nonce_locks_default_pkey;


--
-- Name: deposits_by_ready_default_wire_deadline_shard_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.deposits_by_ready_main_index ATTACH PARTITION exchange.deposits_by_ready_default_wire_deadline_shard_coin_pub_idx;


--
-- Name: deposits_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.deposits_by_coin_pub_index ATTACH PARTITION exchange.deposits_default_coin_pub_idx;


--
-- Name: deposits_for_matching_default_refund_deadline_merchant_pub__idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.deposits_for_matching_main_index ATTACH PARTITION exchange.deposits_for_matching_default_refund_deadline_merchant_pub__idx;


--
-- Name: extension_details_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.extension_details_pkey ATTACH PARTITION exchange.extension_details_default_pkey;


--
-- Name: history_requests_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.history_requests_pkey ATTACH PARTITION exchange.history_requests_default_pkey;


--
-- Name: known_coins_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.known_coins_pkey ATTACH PARTITION exchange.known_coins_default_pkey;


--
-- Name: prewire_default_failed_finished_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.prewire_by_failed_finished_index ATTACH PARTITION exchange.prewire_default_failed_finished_idx;


--
-- Name: prewire_default_finished_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.prewire_by_finished_index ATTACH PARTITION exchange.prewire_default_finished_idx;


--
-- Name: prewire_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.prewire_pkey ATTACH PARTITION exchange.prewire_default_pkey;


--
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_deposits_by_coin_pub ATTACH PARTITION exchange.purse_deposits_default_coin_pub_idx;


--
-- Name: purse_deposits_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_deposits_pkey ATTACH PARTITION exchange.purse_deposits_default_pkey;


--
-- Name: purse_merges_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_merges_pkey ATTACH PARTITION exchange.purse_merges_default_pkey;


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_merges_reserve_pub ATTACH PARTITION exchange.purse_merges_default_reserve_pub_idx;


--
-- Name: purse_refunds_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_refunds_pkey ATTACH PARTITION exchange.purse_refunds_default_pkey;


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_requests_merge_pub ATTACH PARTITION exchange.purse_requests_default_merge_pub_idx;


--
-- Name: purse_requests_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_requests_pkey ATTACH PARTITION exchange.purse_requests_default_pkey;


--
-- Name: purse_requests_default_purse_expiration_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_requests_purse_expiration ATTACH PARTITION exchange.purse_requests_default_purse_expiration_idx;


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.recoup_by_reserve_main_index ATTACH PARTITION exchange.recoup_by_reserve_default_reserve_out_serial_id_idx;


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.recoup_by_coin_pub_index ATTACH PARTITION exchange.recoup_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.recoup_refresh_by_coin_pub_index ATTACH PARTITION exchange.recoup_refresh_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.recoup_refresh_by_rrc_serial_index ATTACH PARTITION exchange.recoup_refresh_default_rrc_serial_idx;


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refresh_commitments_by_old_coin_pub_index ATTACH PARTITION exchange.refresh_commitments_default_old_coin_pub_idx;


--
-- Name: refresh_commitments_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refresh_commitments_pkey ATTACH PARTITION exchange.refresh_commitments_default_pkey;


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refresh_revealed_coins_coins_by_melt_serial_id_index ATTACH PARTITION exchange.refresh_revealed_coins_default_melt_serial_id_idx;


--
-- Name: refresh_transfer_keys_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refresh_transfer_keys_pkey ATTACH PARTITION exchange.refresh_transfer_keys_default_pkey;


--
-- Name: refunds_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refunds_by_coin_pub_index ATTACH PARTITION exchange.refunds_default_coin_pub_idx;


--
-- Name: reserves_close_default_close_uuid_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_close_by_close_uuid_index ATTACH PARTITION exchange.reserves_close_default_close_uuid_idx;


--
-- Name: reserves_close_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_close_by_reserve_pub_index ATTACH PARTITION exchange.reserves_close_default_reserve_pub_idx;


--
-- Name: reserves_default_expiration_date_current_balance_val_curren_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_by_expiration_index ATTACH PARTITION exchange.reserves_default_expiration_date_current_balance_val_curren_idx;


--
-- Name: reserves_default_gc_date_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_by_gc_date_index ATTACH PARTITION exchange.reserves_default_gc_date_idx;


--
-- Name: reserves_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_pkey ATTACH PARTITION exchange.reserves_default_pkey;


--
-- Name: reserves_default_reserve_uuid_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_by_reserve_uuid_index ATTACH PARTITION exchange.reserves_default_reserve_uuid_idx;


--
-- Name: reserves_in_default_exchange_account_section_execution_date_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_in_by_exch_accnt_section_execution_date_idx ATTACH PARTITION exchange.reserves_in_default_exchange_account_section_execution_date_idx;


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_in_by_exch_accnt_reserve_in_serial_id_idx ATTACH PARTITION exchange.reserves_in_default_exchange_account_section_reserve_in_ser_idx;


--
-- Name: reserves_in_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_in_pkey ATTACH PARTITION exchange.reserves_in_default_pkey;


--
-- Name: reserves_in_default_reserve_in_serial_id_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_in_by_reserve_in_serial_id_index ATTACH PARTITION exchange.reserves_in_default_reserve_in_serial_id_idx;


--
-- Name: reserves_out_by_reserve_default_reserve_uuid_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_out_by_reserve_main_index ATTACH PARTITION exchange.reserves_out_by_reserve_default_reserve_uuid_idx;


--
-- Name: reserves_out_default_h_blind_ev_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_out_h_blind_ev_key ATTACH PARTITION exchange.reserves_out_default_h_blind_ev_key;


--
-- Name: reserves_out_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_out_by_reserve_out_serial_id_index ATTACH PARTITION exchange.reserves_out_default_reserve_out_serial_id_idx;


--
-- Name: reserves_out_default_reserve_uuid_execution_date_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_out_by_reserve_uuid_and_execution_date_index ATTACH PARTITION exchange.reserves_out_default_reserve_uuid_execution_date_idx;


--
-- Name: wad_in_entries_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wad_in_entries_pkey ATTACH PARTITION exchange.wad_in_entries_default_pkey;


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wad_in_entries_reserve_pub ATTACH PARTITION exchange.wad_in_entries_default_reserve_pub_idx;


--
-- Name: wad_out_entries_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wad_out_entries_pkey ATTACH PARTITION exchange.wad_out_entries_default_pkey;


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wad_out_entries_by_reserve_pub ATTACH PARTITION exchange.wad_out_entries_default_reserve_pub_idx;


--
-- Name: wads_in_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wads_in_pkey ATTACH PARTITION exchange.wads_in_default_pkey;


--
-- Name: wads_in_default_wad_id_origin_exchange_url_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wads_in_wad_id_origin_exchange_url_key ATTACH PARTITION exchange.wads_in_default_wad_id_origin_exchange_url_key;


--
-- Name: wads_out_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wads_out_pkey ATTACH PARTITION exchange.wads_out_default_pkey;


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wire_out_by_wire_target_h_payto_index ATTACH PARTITION exchange.wire_out_default_wire_target_h_payto_idx;


--
-- Name: wire_out_default_wtid_raw_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wire_out_wtid_raw_key ATTACH PARTITION exchange.wire_out_default_wtid_raw_key;


--
-- Name: wire_targets_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wire_targets_pkey ATTACH PARTITION exchange.wire_targets_default_pkey;


--
-- Name: deposits deposits_on_delete; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER deposits_on_delete AFTER DELETE ON exchange.deposits FOR EACH ROW EXECUTE FUNCTION exchange.deposits_delete_trigger();


--
-- Name: deposits deposits_on_insert; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER deposits_on_insert AFTER INSERT ON exchange.deposits FOR EACH ROW EXECUTE FUNCTION exchange.deposits_insert_trigger();


--
-- Name: deposits deposits_on_update; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER deposits_on_update AFTER UPDATE ON exchange.deposits FOR EACH ROW EXECUTE FUNCTION exchange.deposits_update_trigger();


--
-- Name: purse_requests purse_requests_on_insert; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER purse_requests_on_insert AFTER INSERT ON exchange.purse_requests FOR EACH ROW EXECUTE FUNCTION exchange.purse_requests_insert_trigger();


--
-- Name: TRIGGER purse_requests_on_insert ON purse_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TRIGGER purse_requests_on_insert ON exchange.purse_requests IS 'Here we install an entry for the purse expiration.';


--
-- Name: purse_requests purse_requests_on_update; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER purse_requests_on_update BEFORE UPDATE ON exchange.purse_requests FOR EACH ROW EXECUTE FUNCTION exchange.purse_requests_on_update_trigger();


--
-- Name: TRIGGER purse_requests_on_update ON purse_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TRIGGER purse_requests_on_update ON exchange.purse_requests IS 'This covers the case where a deposit is made into a purse, which inherently then changes the purse balance via an UPDATE. If the merge is already present and the balance matches the total, we trigger the router. Once the router sets the purse to finished, the trigger will remove the purse from the watchlist of the router.';


--
-- Name: recoup recoup_on_delete; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER recoup_on_delete AFTER DELETE ON exchange.recoup FOR EACH ROW EXECUTE FUNCTION exchange.recoup_delete_trigger();


--
-- Name: recoup recoup_on_insert; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER recoup_on_insert AFTER INSERT ON exchange.recoup FOR EACH ROW EXECUTE FUNCTION exchange.recoup_insert_trigger();


--
-- Name: reserves_out reserves_out_on_delete; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER reserves_out_on_delete AFTER DELETE ON exchange.reserves_out FOR EACH ROW EXECUTE FUNCTION exchange.reserves_out_by_reserve_delete_trigger();


--
-- Name: reserves_out reserves_out_on_insert; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER reserves_out_on_insert AFTER INSERT ON exchange.reserves_out FOR EACH ROW EXECUTE FUNCTION exchange.reserves_out_by_reserve_insert_trigger();


--
-- Name: wire_out wire_out_on_delete; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER wire_out_on_delete AFTER DELETE ON exchange.wire_out FOR EACH ROW EXECUTE FUNCTION exchange.wire_out_delete_trigger();


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_exchange_signkeys
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_reserve master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_reserve
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_aggregation master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_aggregation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_deposit_confirmation master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_deposit_confirmation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_coin master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_coin
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_account_progress master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.wire_auditor_account_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_progress master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.wire_auditor_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserves master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_reserves
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserve_balance master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_reserve_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_wire_fee_balance master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_wire_fee_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_balance_summary master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_balance_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_denomination_revenue master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_historic_denomination_revenue
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_reserve_summary master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_historic_reserve_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: deposit_confirmations master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.deposit_confirmations
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_predicted_result master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_predicted_result
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_uuid_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_uuid_fkey FOREIGN KEY (auditor_uuid) REFERENCES exchange.auditors(auditor_uuid) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES exchange.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: denomination_revocations denomination_revocations_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES exchange.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: partner_accounts partner_accounts_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.partner_accounts
    ADD CONSTRAINT partner_accounts_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES exchange.partners(partner_serial_id) ON DELETE CASCADE;


--
-- Name: signkey_revocations signkey_revocations_esk_serial_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.signkey_revocations
    ADD CONSTRAINT signkey_revocations_esk_serial_fkey FOREIGN KEY (esk_serial) REFERENCES exchange.exchange_sign_keys(esk_serial) ON DELETE CASCADE;


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_credit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES merchant.merchant_transfers(credit_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES merchant.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES merchant.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_account_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES merchant.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_order_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES merchant.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES merchant.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_inventory_locks merchant_inventory_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_inventory_locks
    ADD CONSTRAINT merchant_inventory_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES merchant.merchant_inventory(product_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_keys merchant_keys_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_kyc merchant_kyc_account_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_kyc
    ADD CONSTRAINT merchant_kyc_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES merchant.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_order_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES merchant.merchant_orders(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES merchant.merchant_inventory(product_serial);


--
-- Name: merchant_orders merchant_orders_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_refund_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_refund_serial_fkey FOREIGN KEY (refund_serial) REFERENCES merchant.merchant_refunds(refund_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES merchant.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_refunds merchant_refunds_order_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES merchant.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pickup_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pickup_serial_fkey FOREIGN KEY (pickup_serial) REFERENCES merchant.merchant_tip_pickups(pickup_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_serial_fkey FOREIGN KEY (tip_serial) REFERENCES merchant.merchant_tips(tip_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES merchant.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserves merchant_tip_reserves_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_tips merchant_tips_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tips
    ADD CONSTRAINT merchant_tips_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES merchant.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_credit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES merchant.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES merchant.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_credit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES merchant.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES merchant.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfers merchant_transfers_account_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfers
    ADD CONSTRAINT merchant_transfers_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES merchant.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

