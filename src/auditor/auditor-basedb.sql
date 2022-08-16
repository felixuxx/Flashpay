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
      ',merchant_pub BYTEA CHECK (LENGTH(merchant_pub)=32)'
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
      ',h_payto BYTEA NOT NULL CHECK (LENGTH(h_payto)=32)'
      ',expiration_time INT8 NOT NULL DEFAULT (0)'
      ',provider_section VARCHAR NOT NULL'
      ',provider_user_id VARCHAR DEFAULT NULL'
      ',provider_legitimization_id VARCHAR DEFAULT NULL'
      ',UNIQUE (h_payto, provider_section)'
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
    FROM exchange.information_Schema.constraint_column_usage
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
    DELETE FROM exchange.deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM exchange.deposits_for_matching
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
    INSERT INTO exchange.deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
    INSERT INTO exchange.deposits_for_matching
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
    DELETE FROM exchange.deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM exchange.deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  IF (is_ready AND NOT was_ready)
  THEN
    INSERT INTO exchange.deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
    INSERT INTO exchange.deposits_for_matching
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

CREATE FUNCTION exchange.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT ruuid bigint) RETURNS record
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
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
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

END $$;


--
-- Name: FUNCTION exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT ruuid bigint); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result. Excludes storing the planchets.';


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
  FROM exchange.denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  out_denom_unknown=TRUE;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;
out_denom_unknown=FALSE;

INSERT INTO exchange.reserves_out
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
  INSERT INTO exchange.cs_nonce_locks
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
      FROM exchange.cs_nonce_locks
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
  FROM exchange.reserves
  WHERE reserve_pub=in_reserve_pub;

  IF NOT FOUND
  THEN
    out_final_balance_val=0;
    out_final_balance_frac=0;
    out_balance_ok = FALSE;
    out_conflict = FALSE;
  END IF;

  INSERT INTO exchange.close_requests
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
  INSERT INTO exchange.extension_details
  (extension_options)
  VALUES
    (in_extension_details)
  RETURNING extension_details_serial_id INTO xdi;
ELSE
  xdi=NULL;
END IF;


INSERT INTO exchange.wire_targets
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
  FROM exchange.wire_targets
  WHERE wire_target_h_payto=in_h_payto;
END IF;


INSERT INTO exchange.deposits
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
   FROM exchange.deposits
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
  FROM exchange.purse_requests
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

INSERT INTO exchange.purse_refunds
 (purse_pub)
 VALUES
 (my_purse_pub);

-- restore balance to each coin deposited into the purse
FOR my_deposit IN
  SELECT coin_pub
        ,amount_with_fee_val
        ,amount_with_fee_frac
    FROM exchange.purse_deposits
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

DELETE FROM exchange.prewire
  WHERE finished=TRUE;

DELETE FROM exchange.wire_fee
  WHERE end_date < in_ancient_date;

-- TODO: use closing fee as threshold?
DELETE FROM exchange.reserves
  WHERE gc_date < in_now
    AND current_balance_val = 0
    AND current_balance_frac = 0;

SELECT
     reserve_out_serial_id
  INTO
     reserve_out_min
  FROM exchange.reserves_out
  ORDER BY reserve_out_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.recoup
  WHERE reserve_out_serial_id < reserve_out_min;
-- FIXME: recoup_refresh lacks GC!

SELECT
     reserve_uuid
  INTO
     reserve_uuid_min
  FROM exchange.reserves
  ORDER BY reserve_uuid ASC
  LIMIT 1;

DELETE FROM exchange.reserves_out
  WHERE reserve_uuid < reserve_uuid_min;

-- FIXME: this query will be horribly slow;
-- need to find another way to formulate it...
DELETE FROM exchange.denominations
  WHERE expire_legal < in_now
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.reserves_out)
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM exchange.recoup))
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM exchange.recoup_refresh));

SELECT
     melt_serial_id
  INTO
     melt_min
  FROM exchange.refresh_commitments
  ORDER BY melt_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.refresh_revealed_coins
  WHERE melt_serial_id < melt_min;

DELETE FROM exchange.refresh_transfer_keys
  WHERE melt_serial_id < melt_min;

SELECT
     known_coin_id
  INTO
     coin_min
  FROM exchange.known_coins
  ORDER BY known_coin_id ASC
  LIMIT 1;

DELETE FROM exchange.deposits
  WHERE known_coin_id < coin_min;

SELECT
     deposit_serial_id
  INTO
     deposit_min
  FROM exchange.deposits
  ORDER BY deposit_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.refunds
  WHERE deposit_serial_id < deposit_min;

DELETE FROM exchange.aggregation_tracking
  WHERE deposit_serial_id < deposit_min;

SELECT
     denominations_serial
  INTO
     denom_min
  FROM exchange.denominations
  ORDER BY denominations_serial ASC
  LIMIT 1;

DELETE FROM exchange.cs_nonce_locks
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
  INSERT INTO exchange.history_requests
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

INSERT INTO exchange.refresh_commitments
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
    FROM exchange.refresh_commitments
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
    FROM exchange.recoup_refresh
   WHERE rrc_serial IN
    (SELECT rrc_serial
       FROM exchange.refresh_revealed_coins
      WHERE melt_serial_id IN
      (SELECT melt_serial_id
         FROM exchange.refresh_commitments
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
    FROM exchange.denominations
      ORDER BY denominations_serial DESC
      LIMIT 1;

  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO exchange.cs_nonce_locks
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
      FROM exchange.cs_nonce_locks
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
INSERT INTO exchange.purse_deposits
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
  FROM exchange.purse_deposits
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
  FROM exchange.purse_merges
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
  FROM exchange.purse_requests
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
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea, bytea, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_expiration_date bigint, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_conflict boolean) RETURNS record
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
  FROM exchange.partners
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
  FROM exchange.purse_requests
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
INSERT INTO exchange.purse_merges
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
  FROM exchange.purse_merges
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

ASSERT NOT my_finished, 'internal invariant failed';


-- Initialize reserve, if not yet exists.
INSERT INTO reserves
  (reserve_pub
  ,expiration_date
  ,gc_date)
  VALUES
  (in_reserve_pub
  ,in_expiration_date
  ,in_expiration_date)
  ON CONFLICT DO NOTHING;




-- Store account merge signature.
INSERT INTO exchange.account_merges
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
-- Name: FUNCTION exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_expiration_date bigint, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_expiration_date bigint, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_conflict boolean) IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


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
  FROM exchange.reserves
  WHERE reserves.reserve_pub = res_pub;

  FOR blind_ev IN
    SELECT h_blind_ev
      FROM exchange.reserves_out_by_reserve
    WHERE reserves_out_by_reserve.reserve_uuid = res_uuid
  LOOP
    SELECT robr.coin_pub
      INTO c_pub
      FROM exchange.recoup_by_reserve robr
    WHERE robr.reserve_out_serial_id = (
      SELECT reserves_out.reserve_out_serial_id
        FROM exchange.reserves_out
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
        FROM exchange.known_coins
        WHERE known_coins.coin_pub = c_pub
      ) kc
      JOIN (
        SELECT *
        FROM exchange.recoup
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
FROM exchange.known_coins
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
    FROM exchange.recoup_refresh
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


INSERT INTO exchange.recoup_refresh
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
FROM exchange.known_coins
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
    FROM exchange.recoup
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


INSERT INTO exchange.recoup
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
FROM exchange.deposits
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

INSERT INTO exchange.refunds
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
   FROM exchange.refunds
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
  FROM exchange.refunds
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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, boolean, bigint, integer, bytea, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_funds boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO exchange.purse_merges
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
  FROM exchange.purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     out_no_reserve=FALSE;
     out_no_funds=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_funds=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

PERFORM
  FROM exchange.reserves
 WHERE reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  out_no_reserve=TRUE;
  out_no_funds=TRUE;
  RETURN;
END IF;
out_no_reserve=FALSE;

IF (in_reserve_quota)
THEN
  -- Increment active purses per reserve (and check this is allowed)
  UPDATE reserves
     SET purses_active=purses_active+1
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
INSERT INTO exchange.account_merges
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
-- Name: FUNCTION exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_funds boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_funds boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Create a purse for a reserve.';


--
-- Name: exchange_do_withdraw(bytea, bigint, integer, bytea, bytea, bytea, bytea, bytea, bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT ruuid bigint) RETURNS record
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
  FROM exchange.denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  reserve_found=FALSE;
  balance_ok=FALSE;
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
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  nonce_ok=TRUE;
  ruuid=2;
  RETURN;
END IF;

-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO exchange.reserves_out
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
  INSERT INTO exchange.cs_nonce_locks
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
      FROM exchange.cs_nonce_locks
     WHERE nonce=cs_nonce
       AND op_hash=h_coin_envelope;
    IF NOT FOUND
    THEN
      reserve_found=FALSE;
      balance_ok=FALSE;
      nonce_ok=FALSE;
      RETURN;
    END IF;
  END IF;
ELSE
  nonce_ok=TRUE; -- no nonce, hence OK!
END IF;

END $$;


--
-- Name: FUNCTION exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT ruuid bigint); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';


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
            FROM exchange.purse_merges
           WHERE purse_pub=NEW.purse_pub
           LIMIT 1);
      NEW.in_reserve_quota=FALSE;
    END IF;
    DELETE FROM exchange.purse_actions
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
  DELETE FROM exchange.recoup_by_reserve
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
  INSERT INTO exchange.recoup_by_reserve
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
  DELETE FROM exchange.reserves_out_by_reserve
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
  INSERT INTO exchange.reserves_out_by_reserve
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
  DELETE FROM exchange.aggregation_tracking
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
    merchant_pub bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
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
    merchant_pub bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
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
-- Name: kyc_alerts; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.kyc_alerts (
    h_payto bytea NOT NULL,
    trigger_type integer NOT NULL,
    CONSTRAINT kyc_alerts_h_payto_check CHECK ((length(h_payto) = 32))
);


--
-- Name: TABLE kyc_alerts; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.kyc_alerts IS 'alerts about completed KYC events reliably notifying other components (even if they are not running)';


--
-- Name: COLUMN kyc_alerts.h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.kyc_alerts.h_payto IS 'hash of the payto://-URI for which the KYC status changed';


--
-- Name: COLUMN kyc_alerts.trigger_type; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.kyc_alerts.trigger_type IS 'identifies the receiver of the alert, as the same h_payto may require multiple components to be notified';


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
    CONSTRAINT legitimizations_h_payto_check CHECK ((length(h_payto) = 32))
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
    CONSTRAINT legitimizations_h_payto_check CHECK ((length(h_payto) = 32))
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
    amount_frac integer NOT NULL,
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
-- Name: wire_targets_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_targets_default (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
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
exchange-0001	2022-08-16 14:52:56.703394+02	grothoff	{}	{}
merchant-0001	2022-08-16 14:52:57.777958+02	grothoff	{}	{}
merchant-0002	2022-08-16 14:52:58.191824+02	grothoff	{}	{}
auditor-0001	2022-08-16 14:52:58.341164+02	grothoff	{}	{}
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
\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	1660654391000000	1667911991000000	1670331191000000	\\xfe2916caf605ab248662840c40d412468fc0c6bc087a1059df017a5df7e02c51	\\x3e222dc7d5df2768e32c4067e9dc2e1c6edaf955299c10474b6ecb24c9b0ca33b2c6ec9637e330e03c6bce795f3ce5141eafb254d98de97596fa0a693913430d
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	http://localhost:8081/
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
\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	1	\\x827f73b62cdbab20753edd20919233608f6e3d166b5dd5d1f63b7e9ea866fd183c6c4113576dd85e6f6b9a16d3852008d47007ad9981435d78d9375b35110ae2	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xa2de7d3db3c3095c9c37f0b4cdb56614a64c8ed5235a1032d4bc94ab0eca424b31c52a5fcf29bd18d1d9b9a2bc88166531db9ce649435fb809547d7b001d9058	1660654409000000	1660655307000000	1660655307000000	3	98000000	\\x2dabf8597c744b25c53956be0a58a67853eba9e3d03c7a473a594f609eaee337	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\x9c632360d0c900fb2d148afada5dd65cb2d0002d0e0d32d970ebbac05b163bf06f79c0e68f75a813f012e00cc00096f32cf420a9fc05ceb076dddcb5a2899104	\\xfe2916caf605ab248662840c40d412468fc0c6bc087a1059df017a5df7e02c51	\\x10655469fc7f00001de9c1e3b15500004d1f3ce5b1550000aa1e3ce5b1550000901e3ce5b1550000941e3ce5b155000030a33be5b15500000000000000000000
\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	2	\\xe7c8a519ecdd88502897c79378308b3a8f2be183147fcc56fca83b622ce4f99ab34a46ea3b4b9b4b53892bf843a591fe57730c9cd883ee498da05376448e3508	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xa2de7d3db3c3095c9c37f0b4cdb56614a64c8ed5235a1032d4bc94ab0eca424b31c52a5fcf29bd18d1d9b9a2bc88166531db9ce649435fb809547d7b001d9058	1660654417000000	1660655315000000	1660655315000000	6	99000000	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\x0594eed06b2991af84673626b6eed133274bc63fc370c5f5145d3d732319b2d94328af0a90b45fbc787db69cea4d51a692e9a2c2b8ca81a610a2082d4ec1e70d	\\xfe2916caf605ab248662840c40d412468fc0c6bc087a1059df017a5df7e02c51	\\x10655469fc7f00001de9c1e3b15500006ddf3ce5b1550000cade3ce5b1550000b0de3ce5b1550000b4de3ce5b1550000b0003ce5b15500000000000000000000
\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	3	\\x7d17d97ddede1070c10c51a33e9491e94302d74014620018f0f54bc991e493c0c33cf0d5c483444e6c5dc3c258246849d19cf15170774f361db56ae6fb724e97	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xa2de7d3db3c3095c9c37f0b4cdb56614a64c8ed5235a1032d4bc94ab0eca424b31c52a5fcf29bd18d1d9b9a2bc88166531db9ce649435fb809547d7b001d9058	1660654423000000	1660655321000000	1660655321000000	2	99000000	\\x218ffcd2cc9b2ff4c35ce5eb12500cb091ad85e091ff642d13c0b94169d848f3	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\xe881e2b2cb12b6d6539f51aad37e39c247a2288bd24d26efea90c013058353327aacb578a138011a70390518d22cdb06099cf5e6648af4628396eb5206505d08	\\xfe2916caf605ab248662840c40d412468fc0c6bc087a1059df017a5df7e02c51	\\x10655469fc7f00001de9c1e3b15500004d1f3ce5b1550000aa1e3ce5b1550000901e3ce5b1550000941e3ce5b1550000500e3ce5b15500000000000000000000
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

COPY exchange.aggregation_transient_default (amount_val, amount_frac, wire_target_h_payto, merchant_pub, exchange_account_section, wtid_raw) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	94	\\xbc6d87365b70384641decfe1b948be21aa78799eaa8fe9950c6b1ebc7375fff1ae04c0a2d7cc30ffccc2db5188d469305dc6a4ceb76bf5c2773ae71c21d81f05
2	1	289	\\x6da61cd2d9431eda8da6456124813d65b584dd517a2e3340d0df717d3d1faf25634a582785ffa5a22a6c89e9fc5066edfb32aeeaf44e299d956445bb6e88100e
3	1	409	\\x7043c679407a962faf8d37d7357c94f7d99d76fe8c0092d4494893340bc99cb2a6b8d7bff63afc84450750620554a334c27044296f7db1559e42ed0d2f489f05
4	1	421	\\xbc551b6a573b3459ad04167535c88d60a3281b2956a8a09bb6d5859d176146455d4009beb07acc7db8d35c433dd4fceef9d87f7f8fee36e54f14ae820bdbce0e
5	1	121	\\x2251b0e768766daa0a60609937d6c5b59cdb071249462d1ed89a0570384e665a39a223318b33876a738bc71523b409d70804fec3ae4333389ada06c7d7acab0d
6	1	291	\\xb424270d3e964180a8ed11349ab94c62ee88fbdc9e24d5f7cae537434b78a3721885ef700bb5f5cc227f08599365b5e5558414807c54f156cdda59099d09f00d
7	1	412	\\x1be5b5484e4f1eb5aec2df8787cfba93af10064c630e94ea66b05891974826f429def6f98217ee90b23486f987af982e0be5b4f4efcd69d12755bae22b43b200
8	1	341	\\x3979cfcdf8075c345f2cb9953c19a8c092eaebb4238c9442b0c851560669fefa445969189e508871896af5b6157b1ce7336a62a395820c3319f07f1c58193a0e
9	1	303	\\xdd983ac538f71f09e3365c68d47ae37278aad86ecbe5f5198c3c93f0adc1ad56caef9d3892ade037e6ed9c23f152e7424413b137e34da5ed52a1bb4486305405
10	1	100	\\x0f369a5cbe7f9b2aa19e1593065dd4f70fdc1e7f0b751123ec119330fe59c57af226be4faa02b46e11bcfa55bdfba6d38346e5dd22f89c1b0f23c874d96e5b05
11	1	154	\\x164f34d791f4a3fd65b9166f2f09af64d65e62f8c164d18a9b9f64b9391bb11603d602c348a57d77da1e7a82e9462acc331c5d2bac77f2b9f018859bc5cd2400
12	1	192	\\x478854ba20aa6bb06d8eac1c37aff3398e3e7aa51d9d64d1c77bc7e73cec64bd8421053a16456b17d1857990909acf52203b16739b57667b39657d65e4db5b04
13	1	117	\\x29cc55d9a0d6120807b8467d08abd1f9f092ca3d273c890d0571cd0d508eb58113877158aada41c531175f15da961084ffa90566c87db813945872049b617a06
14	1	29	\\xc7c22fc9d3ac7c09d90f65c9685f2e244530fc45424b7488167d2931ac1ad5385342798dc6b41faf4c46b3f5141153f6ad4e577db1c9034b22f230c606836509
15	1	242	\\x56a66c3c79f84b8833ac39395e8d434270acf54a7902d3581beb1251556aa4b36651539996ef6577c9e39aa0b2ef119b552dde843072b187c4a6de5008d6d403
16	1	220	\\x9d00ec74f3eb6587895d07feffaab45baca2cfde2b6b6502db498cdb5886b16ed2e992d0bc736f20b229ef22bce1e69aae8f91387976aa74f3d67a6a92d05603
17	1	147	\\x07a3bbbc41c3451973f37da20a21981353b0a87e15c1b353992b6a7c2b6c5d750528aa906dc56f04a067d80b46e21a1df04418e91455fb655fe8ae4f9f83e003
18	1	170	\\x8b299e528c1f16cf6026624b6584539df897bba02ee3eedaed20d0d17880f2cbdcd10f2b5f10d82f699b6b32c3416c35d09635ad0793af87c50b948044629b0c
19	1	344	\\x9bc747e11c12592a3ee9bea75a981ae7405dbd0b9d2669c5f32dd66c07fdca85356cbe6530e04f7364fe378d251bac549f79b9594c2df38d543e1c0dc785c10a
20	1	60	\\x26207cedd493d62a1bbc4c92bf41f97b71c91d995400418edb85bc9e7f4018825830995e2db723587fc2fcde6c1fc982764cf698dfdc2b3cdcffdd1f9efe0103
21	1	86	\\x4918571831d78dfdb0c6c41e59ff8a219623d27c435e4d9a7b03ea751ef2cd33745bc6ddbb21c5a654b91a74a31d6738d5525bd0e19cb36a5f2a5a7d7861930d
22	1	352	\\x4b9551752b43e0acbe4a55842ceb7719dd4ee82e6376326793f730b7b1fc777289ce3c9bfde5a49246e58bfee215738679ed97e8bc83c05249cc500cf0f04d0d
23	1	355	\\x18054d00050123ca3bbe97c12bf11a5756d56d61f16cbbaf6da6b7487c759bc5a6beda6fa77577ff54a0914c8a9b7a2fb4ca703bccff7a270cb33234e2da310e
24	1	377	\\x5f774c3c3e6fd294cad6f55d7ec1521f4e643e831a4e951b92cdf26c8c5040d4a3ddcd12bd3b8b56be5209bf89c2638348219063b4215f822d3df1256c7b5e06
25	1	405	\\xa98983dfbb885240991afeab7a33b6cffb6b3988267aeed6a323a272c39bdf776d2a2b20f72cf74190519baca4b51c5cb2da2d0b9c1720d050271ef920d2f901
26	1	189	\\xbb3c5f9adedd9b41e1d7b1fa31a87082cae45bc27cf4caf11ae6de55fc98b0ceaeb5f87da78ce49b15b5b8cd59d53ca0e3fba4f873f78bac95c66b88e4a37101
27	1	77	\\xa30f09ac192c0c1e7a700e45b233a9b170a682467be3d7dea24387de3cc083eca7813a1e25ebd90bb40c85a52ff83f37a3eb909178dbeedb117986c6d3095e01
28	1	290	\\x724e16374f01269a1587e5333d8796ee72d3fd0ab94b8dd5fe1565362e116f88a88e0b94483335436db862028eb896d652c580486a71b0d446215991942bb10f
29	1	116	\\xa56a5746554588fc6876ca5505c5f9840c8ee0e8d4d92948555053dc918f51806ebe92532aa022456405d3a88b24cff9bf60c0798f34a99773802d139540c60a
30	1	62	\\xb669a8c1e080b7339dc98aa888563e694e7439834acc47e27c142d07bc6af92f7578fbd27501c870593cea77187e7386a7243afc548e1de518aed9c1dc7a1e08
31	1	131	\\xb1b9e73fb5167a4b92bc3d37d3f164efa2d5177e572148fd37b64f1885254501fee8b834d9b8b6ba281a7ce076a335bbd3f8bcad29ffba6f8307f05a0e542602
32	1	297	\\x37c8bc15334058ad90f9db474d71df679503c5cae0318bdb7dcfd4bdb7f33b9a22c5c945c636b30bcb3889fd3a09902d2468b8c63fa6a8f163dd4893c13b180c
33	1	72	\\x11da371e254091d3c096b1d97dd009f3cc7a76e0674bb386abe5498468c6602d476ebd1d24b16abf8232725f29b5858146d519cc12128ab444bae0972ba4ee0d
34	1	329	\\x21c7f847dfa1911fec7885e6a1be5f2591c1866dfcdf9bab2bbb8bc48062d38d1d272d848e09848ee82ebb0305855e643b8b3846a3521c645ed175d9a8c63f0d
35	1	24	\\x3e957d00ede8fb3a0130c434441e9f09ec3348111b0576048a8e7a8668b5755e3aa02b5cc5fda10e7707f25a522cf8016ebf903ca13e0f73dcfb57acf7b21909
36	1	45	\\x0bba8aa64e2d485c36cbf9e8e71dc222c6b67cf1116f4803dc8c6d8df16b90d0e8b95d8dc866752f89e06cf6bcd56f8653442dc3db7f1ea57b4678a487e13c0e
37	1	253	\\x3129ddf4be5c1070f5699440acd40d40d4a4a6e2b3363eaeffbd79ba7a5a17a61032acda556bad1d6585f53aa9d104db4f880d509c84df5fd60e108905f51200
38	1	402	\\x64a547bde6888c1515f86702e6993ce8c3fe725b966b9f31a25071874c499cbb8d42b33d8d9673868f9204954fd6410bb0f5cd48c1d1706ce77f79b70b328908
39	1	284	\\x97cac77b20cc0662e2f9ec3637773568d4e3345e93e02b0256da13676330ac89ee5c3a144ba829b2f6d6c698c6681e1abf8dc6d8941e92256b8b491aad16800b
40	1	319	\\xe739288df16ae6b6399b71632fb3cd1e3bf3ba92bf90a901f28fc8e73d512e73a7294def35caee6487ccf46937d98f2de11c678408716a07e9589e4621192a05
41	1	337	\\xf410c2342120ad06cdf6d67c0644b7881100b0e25b59ebf54dcae369a905345ae83012bcd6ca72363bef2fa046cd1bdd4ae12cf22ca491691e95d60492e3130d
42	1	138	\\x90dae9f172ea968522d7674dd419bf70be103896b82c5f918512982cfc22dc1e4cbfc18756dd7436231b47a43bac6046be62ca44ffaa4c0ae831fbc2a57bcd0e
43	1	294	\\x6064d64d9b18e5838f3c39391cc776345d57186a69bf4aac4b4c6d6ab11efa8c65fbcb1d29299efb579554c6608c482237f20dcb2de95f04fbce65ce9f7d6b08
44	1	227	\\x42f2e7c72114ce498eb67669aec5fd8f5e977af4ee901cd9b7891bfbf5111b328bc6280f3c88c26d955144314ddaef160f7756de17612b1e881640f7e5662b02
45	1	422	\\x49ffaf9d465f52c65df85a02ded4100ecd1816be21790716f0619a14a1992f55a65be49bd8a347c8b5714417544ad31000d2b5fa3d07157c576d561747e0ee04
46	1	38	\\x02345784a9363d29bd39ee023687b131b06f9d9887d2b13c70d732fdb97bd1b1469b2e20aa4f849a6748184a5174be19a1ea1fb0963fdffcf1412deb622a7c05
47	1	196	\\xabd55761d924ad9cb5bb98b0b780bb1182cb622b9b2e590dad48375f40645a7fb6bb5ef22c63387231fb0de36d3714a04c55a8932dd16df9758fce853a90290c
48	1	207	\\x0c4240a7c423a106ae1b57df47806e2bc0083bf36fb364aa088dee89860af4036434f67203c6797e53b968813c6536b88d3fd2120fcdeab1cede5924deba2005
49	1	372	\\xb9d69548cab877e17d86f719d2d54b49dc7827f59a6d6c2589c2a37e01f6c976040fe9a8d514340df1626c7e6767c3d5eea0c10bb037843d9c7e0325028c8807
50	1	292	\\x38988187b867d98a59c29a9e26f949512adaeeb324e9fab3d2525aeca1bf8bf7895e6abf61f7efc909ea2985dccd6eeeac3485e9e10726ce38e27034b61f8c05
51	1	108	\\x97c0ec341350df1f85cbf07e27599f61468429341303bfd0084e50caa20292ed90f47f9ac0667860d9866ea694ab4d28b298f7eb1cc0326ccc9a55ee88267a0c
52	1	201	\\x64d6402bd4e69900f345277aac56c5b51ef832b932a835ab639d69b13522ba5e6b75d6156826ce8512cfd0d0b3de6af05dea332ac11fefb1418422d3fdbef008
53	1	300	\\xdbf9f87d8668e91107909f5a3fa894aec8410abd0bb182c0d18874ce1ec3fc552ce3dc7a575fe09301ffc293a1bba3fa543276bd4fa4eb006db791577134660b
54	1	264	\\x741452d3517148a154710aa2e594db04c9349c8510c534c0c6df48f6a1a4283c36499844512089bed4144265781e3c87d453e9aa1a7eb33ae6e782e26756620a
55	1	26	\\xec13cbf436471257f3321e72bdd21adeb8afb48d8f59db65f59fc3141a905af8686ac27059162485b7d738ade912ee09ea157c6f4f1315d0588ad2de7043e30c
56	1	130	\\x836bdfd259448d2686a202d9f468e194a08c35ded23ba0d7e31cb56eeb87bc9a6a83632c86b1e7fd5795186bfe1b90d47b21b63052256c17d262077b5a2d670f
57	1	234	\\x67d5792103302898eee1811972dcec5032599dacf39ebc7f8b40ac6b0403132fe3bb4b165368835f1f4a4274c1bc9592e098786ceadd36ea70cfe7c163bd4e04
58	1	151	\\x5c3a3514e8db08c3d3d56f2bb9972cbcf36935e5a11ac807c1109305f9ac4d5d5fef2d1f6f150e4814cb3213a730e4c1ea4194b611e6599f2490020e8bf9f101
59	1	190	\\xd9c38f9d52c47945c5f579c6c43a429c710d74773a0bdf1c8ecb4f68e049537d294e29f98c2defc48bf2c888cf11d625a635e985c557a112661b795a04508206
60	1	96	\\x9107072abd81d51af51217bbe784631842d341d29cda589928b8866dc2bd1066119555e3463fad905d64cdefb1b48ddda7b3581d97f56a6872afe50ac9479502
61	1	102	\\x51c4fb6b17498aecc44bfa8b9762e00623804031e6e97dfd4b8938935e19d3953ce708b68813deacb01132aa9e511d20b3382b9fb858c866177224a81453d606
62	1	299	\\x2e50056d4ceca57a162e357e5bf828ad16c7e6013f565e436996f5024c9a93b813bf7288493af5364c0cc8f2e7b1b95f1ecc4849f023976c6ed995f57699df0b
63	1	49	\\x82d705f6d28f62f91449a7a30db941c253dd8fdc39a96c8ca9273e15784c58e17885f853f54230a5cb54ea85ddc35d31bd225b64941bf5d3c47a65c84424390c
64	1	59	\\x6f84b0c18bdfed146b4aaf6c36f71f7e10f1a0143f30e34def8de4005e01cca71fb2ae0680e554adb8c674177b10904d4a78e59b5ca33135a2adf295571dab05
65	1	238	\\x3508ec96a3fbf3ea52f7dd6ab356201d83d60665be2aeb8403d6adc2d29e661f983d9771f583d6aeb42ad8ab595b492fec5c641a60858e42b0a08d2aad09920f
66	1	91	\\x58a9a35ea87d566efc6c15d2fe1208d9bf6916e2bfcaea555c5688517ca26f5d8cef5413471d058ef8d2fca9df43cee791c553019b0ae4da7074ac231730510a
67	1	53	\\xee2d0ac26c05924067da2a0a3d3ed15db1a4b9d09eaf6554d6735bf09e0cf72b3577e192dd0ad812138e4c33a5ab10dc1266dd45cdc6b62e64a5ce931e61dd0b
68	1	33	\\x961774b9f6e6fede5bd22669ae8ee1fdaa6e438ac78020ae2d80cb6a7198a01bde678c0f1aeadefbc646df6e445116f3517b660335f71604c80048a53d494b0a
69	1	171	\\x105fdbd480f302736bb28851452b1f1552f605b6ac3771f34e0f9459fe3f90b77d31aaff0c35a05be9ec10052de64b03c234cc85694caf6c9673b66c99096a05
70	1	127	\\xe502944f1ba5698f282c509a12d15f34da79a8d3ef1e405edead5875ecc0f9bb267a3e032f1303d49eb0197c7adfe50516e634abb16dc58dda75f954a48d7408
71	1	251	\\x8790192631ab1917f8890e72e81e494d7ed224e5d1e9b4f18c7df2d39daa40ed0aa3687fb2e5131210fa49a22a9113f640ce5aaec21da08837786e4b214bf80a
72	1	327	\\xc227072a5020a38901ac10c1aa2199d672b8779c4adcb73e1163f2ed121a540aa7c0904dc42c23ab0bf053f9a8e563f399e89089ac8da453c1ca79e335ea7607
73	1	269	\\xf0385f6233a364023d710b51af2605b8f47d1d639e40fbedab7b704204629ec10e405539fb3e2497451bfc0e9f1799755a8833447e807cb376e711d6c362da0b
74	1	85	\\x89cbb7e0e7f2b2520055b494bab0145ee32d0016e67bf2b3c518a8179a8e0aea47bb2f0adaaff33b4354ac0aedec99f386f0f0086e3668d6c410f0fd3998be0e
75	1	99	\\x3c7d82ce28175b34b4031298e65b743a69fac66d9b64a5703d9dc8ea1019cb319a2ece228365e58ae6855a877cb2c702533880218c7b059dd776f460a693d10a
76	1	169	\\x1d727d6fda46363ed2dece115df8c2c729b39ca2b5269ea00cebd0390809101e44df27a878b30fb4d8fbaf065dce88042530d612ffa25e892d643fc83af16c02
77	1	420	\\x802705f7d3b71bcc6b3496fb3dd89082f5468066905c683db0cc71185ccd74af8b90928aa14828b547af97ca284d956a0a16fbfd9d25e97b829342006c61c506
78	1	8	\\x9d00e40af81ac5387aec9cc7973dd25f12ec673fca0f4219874ed764b9e720d1b304d8a3d5967741798090882df84a0ecbfe828aa49b1ec889b756d100bb610b
79	1	13	\\x0dedef5d253d1b2aa1822548da5bb8eeaa5b624cb63f8cb9850bf44fb716eded2af90c7b29b3e7e70301b2a78497567fe79b8f1a066c3e30c9190afa2685fa09
80	1	88	\\x18814277fb7f1ab4ccf527c57f6a9a0003e8d636799b6eaefca4cd3677860861bd37b542c1410de9576d5a14692af96b6227ec38224beaeeb4a310db409cf20e
81	1	68	\\xb0b8d95895b31a16578822885d829b5ff61a79c80d653d079d9ea871a2b3dd38e28415213d202fc3f0d30e524163725be40e7ad0df190f26192fd83e4ad13c0d
82	1	199	\\xdd048450cea415b1f5237b345f288525db5e0a8b67d33e2bb4c13823405d1c4137b7c98de40ae21e32cceb435934018c7af38ff6b60b3d806a90609c524f3802
83	1	172	\\xf0b4ef2038c216ed3e26b073b41350a423971abc2fbc94eee2059b2c0550b3277187e3ed5aa6436d1e618f487d6d403926d399e37ca40f9bd3d17b1520fe5100
84	1	144	\\x6e9a4cc97be3b1b88513ffa4f1c0cc1be48c5d4a36514751dac1393295aa3e1b81de637abddf4435899e4ffe161b32879a579c85d85876a2dd4b3c040efd4a0c
85	1	403	\\x39de3107bb71a119cf9f1c7c32fe1d869742d292de1f6f2303a94b8d8d3696906a9552ec35623669c3eb41e50e58bfbde4486300df0665f53dddbf1fc717d10c
86	1	314	\\x5f06e91aaa98b78e9f1da6af1af3dcf8bdc1fd151240ad0dbcac2ee5a58a62c3b6730fc529db5685aca5b98f4c570ec54fa34cb37320c55c032c6d2fef18b407
87	1	367	\\xeda4510a50a9cd6c4c239e8f0678336fa04de7ff129e0a0507265cb62974cd9f7c611ac1598594f80d86b53c6f8c7edf54e1dab27c17b77ee8f2d3e1e0ea4e05
88	1	166	\\xa6ccebea305c6988c1ce77ffc576159b958457071c9e4f3b6e0ebebe0a646c61c0f3e37d798b4f21405237c40a1d3b06a00d0b01218f4d9c385b51893cc69509
89	1	37	\\x0d711c0fd6a6e68787f6e1159e06b12a76c0d62894e5de3436d51bab4a6098d2c1883c42c875c7ea674b9a69dcc8a986b05339fa866cc99fbe1fa5aaff562e08
90	1	118	\\xf40e250415b0c558cf65a190eaf76c9ad498ca4bdf434f7ad9a7fa9abe5e091779614eccd4b0b3051b52d8afbfcb2ab63a8e43fd890bf71298bef05c44244405
91	1	119	\\xcb7f3fed19cc6a73d70f6a776b1ce7182e5a68075358dde22293cd7bda63fcbab28e99d69515f85ad36ff4bd4b988dd6cdaa5838dd0d20b085f2be2bb1030306
92	1	39	\\xfb5cc8da7b9bb07d5169d0c50405e5930ac7a834f2d116d41b02f24c029b861cd3c89f82dfeb64c960f3972fabad1c3294926e6de856908d39b3be2db17ffa07
93	1	218	\\x036e7ff7da4bb8aba2d94ef7b9e1f4614cac8d4cc65e566e4b8e04369bda5e24f21fcd75205de78cd769a475db82fb98d91e2548280f20eedbb8f485b0ed6609
94	1	194	\\x0b6ce5bed7a74cb4cb1d9a0ba3794912cf44a7af041466f6d9799125d999bda771ca0ca5125df3e4dd973d72d7cbd4cb8688bb1fae9a4d43cfd62dff9dc9680f
95	1	195	\\x690b09133b5fa58c6f65117143c270de912b62fe2a6d4d0b61d2abcc21653c03512bdb1024417b48525c8dec1cc124cb8a94112b82a84dc13934e28b258b720e
96	1	66	\\x4f2692c42e3e23766682c3aaa9b5986c4c9cfb554e090a4d7c61fdb06f7df04ef4b6e3e99812bd6e0ebfacfc82cfd6e7e2159709e65e0330de8fe12080621a0a
97	1	254	\\xe15b2830e60f1fcde2a28ed037012b49dff6f2b77d9bbf897abe7b980257193b97a283baf0b762d58ffb81a75ad91888cd296985b94111b843478c158514640b
98	1	250	\\xd2b193212a1ac7a40abff386c75718ce03e5f4a92571223b3ef7806b32ddba6047ec64eab12d39ff2133d61925af65658a3261c10f140e3008ac9992f4c7080e
99	1	167	\\x55bdd80941f9162a1886efa6de6aa83afd4a61a9cf99f3379810bf4112236e1e1fdd10afc556c807d330d882770ad54f96b5fdca9392bd06f7569ff3ef4f6b03
100	1	275	\\xd2205f7b702632551c1470555be10f84156b5c22bb3d0955c4350e46b7047150652604da12b4ce80e1e874f054c47c4bc67b4e9c9755713d1f4feef618d5a208
101	1	15	\\xc3583ee368a17f0044db6f38af98c88ff6f4bf98502a31a941620ee790f55bf33c9d5217dbbcbe9be84c5c5a5ac9e552adb650d9ea35209c5b972c4a0a1c0302
102	1	213	\\xb4d9d6e70f5af60641b486d87ead857003dad4ec66358c6d2685ac2dd631064a1892f35fa32cbfdd9a53919c80c087b33cbdf3782b9d9eaefef884a1273fd802
103	1	41	\\xc558f412a36da4a6e65def5b38cb6f9cf3d49cdd2fb86515e343dc8f87a61c3bf402c20c4d5e6f46dccedeff2aab5e17895f3ab6fe982e64588577aafd718f0e
104	1	224	\\x13691955334d97aca115348102453531932c3a0a94341d99ab2700460209e0ecf9ddf721df51bd716eaa48337f3671661672d674b5dac63755d0f5a2f41bc30c
105	1	176	\\x4e3d1ccd2b778eaf500782990dc3408d55234299308e48bb7a73cf7a8774bb1e965a5768e01b88969fc92cbce3d7434e79a85e882adff0bfaff2ac1c58340904
106	1	61	\\xb6fd7d73db0262ae51e9b9b255640ce3016a705da3c77af18f3bb3f80e83bfde5c75cc33f452b90d2d594c3c40ffc97151cc7eedde7a4334dd246925e35bc10e
107	1	357	\\x4b3dc34f9a78407a993703cd8685d7643c31063c457d310adc9349459a8635fd561da53f8fdb45c5c340bc50a0858d9ef54785539a9de1b9350f77e78397380a
108	1	310	\\x954c4f48dd8354bb1b4530a8798e2869b571e37900c8b677374734f26a00cf532e00dbdc8eca7be3ca58aedb1a2e15ca165644938223a64c3cd26496e3527a00
109	1	183	\\x0d64366df0828fdb674497e5ffe525f6015af43800cb645fb09e8719c8f2b4d6e3d2b87ada90db6f9a44e654cf053e600b37d6afa51d6534d474d3e3cf311d07
110	1	226	\\xfe0aa93b0d23ad1fc9c9316fac99e6da7989f9e735ccc21ea6016cd6f712a197ea5de77890b0240d6021ef67df318ea6d3f405e1938bfbbd001605c1c04ee70b
111	1	281	\\x4e1ae9702f88711b05eccaf337bc10506a00e78ed55a758d07cbd8bd7a1e8387ea56072b84a385b4f4d9b08ce5bd0e1aa131f6e6d36707778f3fa60c538fe50a
112	1	286	\\xce80efb371ebd1fdb31125be0be6e684ccd5686932280cad5d82a9402509cf98385dacaadedb0f371be88e2858c39aea5185324e854f6948788364791aa8f601
113	1	353	\\x6bab374a6ee366f5159c5eb9cbd644c929ad5efca795e841224780f1f565c2184d8e6f2e5b3113872640e6b4b504914ecfd9f59d0d5ed8b6f0c9b9e0f12b8a0f
114	1	97	\\x83fab93d39d29751dd84bab57675c514e5eff5f964c8bca2d6af5ed35f0cad3479c4f663fd93d3e6ae4b32b5c8002e5302bdf4df1b8a7f449ae8dd3e3b7a1c09
115	1	187	\\xeff0c0ac56ab4580c30d16f1a8bad864638bf3ae699af02008996648028520b38a4f83bef9e17943dffaece92bb62204f017607cb602c1c52f12673866c56f03
116	1	379	\\xf0d67c6f613029565dea4872ec7c492f217744e15fdaed69ca5ea2f408e8b7db59b5110853fa5332de13e6eb1e67a2ec04599395640be18dacc02ff0a16b5902
117	1	361	\\x8b56e1875dc97d062d22e3de8b722462746faae6b3def483f4b3689bb4e07eb7a5d82c7f02dfe5cc951182810fd237564b145618f2387d736d606c6fb435b40c
118	1	78	\\x903746aaae9e006641c79cd29d3b40729921bffe226cee553eadebadb08ae471c6008fd4ea4d5e2d51f0bc0210efd9d0c97f7842b17f8e6b7cd93827ae083402
119	1	43	\\xa1b4264475b8a721783318db9997c8c40001c95c255c25caaef95b324a235596cd37fd3459d9c2cd860a898c2c094a694bd2d3b6e67e78353b352e7897fb3d00
120	1	55	\\x4be6733e01e8a26e1ad786bbcfb03714ebfef38846ffedf2ce323ba7af870e0221446e38b17371b1e93eb7a17178a4c5cc367c7d82ba26a7ef76b61cc02a8b07
121	1	70	\\x945f331a5f1abbbb15ece49ad46168062c48ea97bc6b93b5e5cf88b30beba9efb532d963d995892f0951f4df3396d66b3987e405be48f7ccb2f3cf3e09a3d805
122	1	101	\\x0b7e9837c9d2b32b185a3eb3568c60c905ba6367b2e0e458f6b88b5ea0bb2a08d6bcfad45519b91c252f61276441f3ae450241bb9bb7d33ee80a0e02f82c6c05
123	1	322	\\x1159406b9a5c9ece4daba9c28599a09d4499449504ba37fac3bccddcc67145c54e30b416770f3755711c8279bd49ac34ef2979505cf3249b21b5cf6537b11208
124	1	383	\\x4f8a85b2920e2f22b8a045a773bf9332f6036f91d10dd0b2af1586caa56901f0b37e39a71407f1c9696fe540801fc08938aef74dcf7847f866ef4ac433a5df02
125	1	332	\\x6d95c3f686df26e1448aeb0c4d56f31170cf970ec958e6f28d1e1753f59c6811fd7a7552b556dede4772fc091b90c3344b6e24fcf7c9a507eca000c3b7bf2a08
126	1	407	\\xacd69dac53a0de0ad3e9b4e53a463aecec4d34f3e2d11652269e1a0fd492a0d455c3cedb494319e7de48311cc1a87efe7a7267253d3c0554ca7947d15223a200
127	1	164	\\xfb517771664860125f775e48ebefa2fee7021205f4f7cd26c2cccc9682b775c38c411564f9c72ff9363ecc465eb2f27db2efc7afe6eb902596f5065eac262d00
128	1	75	\\x3ca8fa2422c07fcd3b14b3ab072436c4093f0fd2901c409811f82f4c5c59de9efc2d10d08436f75d58531b6741ad50f44170b9bfb3b6c56b558ca7042fa6f504
129	1	73	\\x0a1e309d0a436a02169ce4ffb7c812f93a2ac0609f7910c25f4c6aae233dc231e7785f22e154a712dab73b2d6611aef2f26f290b438a7aa5f57b9768e92d9908
130	1	272	\\x05a263c4c2f60a47151a63eb73294c4d37334c9c927052f8a5ed9ac79cbee550040250049c4cac3a61148dc61074b18a1ba1f99dda1201de67d2774e1f7bbd08
131	1	304	\\xb49e7e930d3572d1f0ae9b82816244e52188ec0a2c59ed08701570b30cc8f2a01b38b53382380aafafd88391e2ede502ec939b183bf4d88698ba1477ba933802
132	1	296	\\x1d56da75425a358383ef3ddb15333ab8f430adbd840e528d11b2951ae3e1a8eb32b03a83ae8129c1fa69421c3fd51012c008276b3a1b329f03fcd8aece9a8105
133	1	123	\\xf8b6530a85c2c9289b45cded642910b07032df1af71e258fa342a21b2c07ddb9d0795e2757d154b6692a2d6321f6878fe5d6b832ee269a15bfb8b0f9fe7ac00b
134	1	35	\\xd912458ab42cf8db0ee4a046284cc0f4c4166f4d5b5d4c5dac659acda63ae710948a772e372866705dbf842ef93b6a6333ae0c54f46d73e79b7c426686aa870e
135	1	257	\\xf9bcf0c1e9b9be3c34dfc4e1c578753e3a80d17f6b9150d2275a1efa0287f61454d03d9c802d134104f3cf4c59bc97812924a84032a6de764500d9a2011f7d0a
136	1	324	\\x2beb00a0eeda96241520203d231d549466d090661c948a1186cb28b03a16748dd279c3a274c3ee15f6f07b0152fc2f75693b704aae1532947b83031acd5e3600
137	1	107	\\x5653a6e7f40ba81d2ea7ebdd1c6ccbc17e83aeb213b542310b0dfa8c0cb3ff68021d4c9913829743f95e2386de99be872a8bdb921f7b33ddb56661fe8137220f
138	1	346	\\xc292fd79d21fe315af5caf56eca59d45d5b629727a238ae1fce6ddb0c814c026b64d05c3b9eee72ca35d5af2e25550b870025b9124dbdf31ff9a024df44afc0a
139	1	247	\\x5c601b650a20743d851ed62dc3d67cc98c7d106f6f36c2194c8911319895d34b08d7a08957ffc4b0840991bb37001b5741a4bd3bab8971a2c1dbc0f536b71e0d
140	1	148	\\x0ce017fa6f0214089a7ae4c15a6d0c6d1401f6d92d22658aac3adc60ce0de5e118e01af4e0f4e4d91b3dda078178c620b81456d2c16c3bcdefb49797ae24e205
141	1	230	\\x10dd8bc1cb2454d7d087fbb10ea8f144e8e31ea6a2974a7ca21c3081fe886dc594b5bda10fbc824a74186318cd08c36ed82fddf1e080b87be00fb4e96b94530d
142	1	9	\\x4c09ee6e0e6aee6603ff787576c8ba5d0a557268d94d5465a4797faee3e90120e14fcc1e9ee289fed4b2f2cfa8ada5edbe9b56f0858d78f449185eebf2ee070c
143	1	211	\\xa74df4952d4cd54643b4eaedf04f39d9a7f74ae3439e1d794c81b50144d0b55bb91888b025dc21bf93bd78961c7c4e727ca5032b30804895fdd14e5cf7572304
144	1	384	\\x1816b38764aa1c529c13bae2f4319211c3373f0610de35f2a8578ef92c078c90d6c06c3d00241b0c3ff2852e7e7afc0d388fd286673aed9389ad5062ae863008
145	1	69	\\x9c7cd606fc296a0c4b402684c15fa341964c3f6dfeb5d88a7b16b852a88a9a4d4f19998de2730c5fc2593d82664f92ce9b698a7e3013eaa89a5f432b3b2a9e09
146	1	16	\\x6f567e08993ad3b12cb432e3b249f8eccd8634e2c7afd6e38a8eed464cd6d7d7e335a4d0d386d33fcf4ddeabd13c40e7809134bd01cec5362cf786e470d5b900
147	1	316	\\x114631e49bfd9ed48c0d0a22a8c159f29f4c48d9c76d418968bdfd27cb26ead2a19632d11da051620d18673bf3d4654045cbfa9023921bfc02b15a099c87d805
148	1	374	\\x01a7ad82ac73f78ec1663ed5f533a43bd680115903e10995eed68c445e98254dad2308baf41721ce2125028debe693cbdb9ea5c6bbd6ff243f39e1dc67f86902
149	1	278	\\x1f41422d925ff37a8559e5d86523bdaa839a23d04d13bdd6f63cbdb595e8dbcfae04a00a07e2b102dd38e5802c19e2c0638cc3be8853ff79303f2e9530ffca0a
150	1	178	\\x02dcbd9a6de426a349dce45edef11a3512a11a81b8a184e51d162dc23ea209b2c2c66969623a4e0808dface4a6d2d2976d957f67f460a55f9cb38d7f6cfdd305
151	1	333	\\x771556da6be86a3fb9c2e874846fb620d2c69ed6df8b303aaf271a4ff97798e09be97eccfbf8bd90746ba6dc5c2145d71806836a1383639f4ca2bd93738cec0e
152	1	411	\\xdcb294b7e2eaa695027ebacd1e2b5d9d24d2dc7b2a86fec060e5b1a30cc4406f6d90059e4f78403b131aa9d681d1514a4bf21b145b3ee9b314fc5142301db205
153	1	56	\\x98744ad758760fafcc54933c9b57195f06c2a66f73f7e6790e3e061ef9e82b65ad38bf358ac5e2d7c619ea1399f99cef098eaffaccb212bc0dea666576ace708
154	1	22	\\x7148e332c8f1ec40a07a585cdfc177c4fae7429ca6ad5ac4bef988d338f9004f97be73e6264945ad29a1873d7d712f34e8899978c941c2f97565555ec414ef01
155	1	410	\\xe94e1fa61c73ba09eb6d7b020c88028822ef2cabdce1ddabd2ce5067c2839ac58e62150d0f2ae3fd5b3ec7f547cc1a80da6438e48bacd3257cbaba3e218cea01
156	1	343	\\x25d01c1e78da687148012b39f42c51c4f233759ae84911ae0f134663b7d7df498ca80cfbaf0601c35b68811dfc7a427d13cf44b67077496aee2055886bc23707
157	1	47	\\x84d3bd7e14ccbc2c82558d7dc946012e6c0f11d45011462b5315a8e5a37e88bf3373965c50c60870610f704b914ce628699c5e2a83b2d729b56151efe28e410d
158	1	326	\\x984438dce1dc581ad6f93a5075c41129ed2a6b8fb832d5dc3d6c700fd4546fea2b1fe945ee4c05fded4dda709a8bd8a374d5b7d26b093ce35c279670672b6a06
159	1	17	\\xb93b7512b4fae2c7eacfe6bde1fffd967c0d2c2ee169cc53fdf02e36fb7a3733da6ca490635b08bc135b7b48052104e032e1b103211d7fbab8621157cd48bc0b
160	1	398	\\x2d5ca3b5d5082559ec53daad114263ca028b9801acc675b2aafaa5e7ac4936e19b1f544dd54ab01966fa00193462ec7b16f57052353d153fff6bbb309dd4e901
161	1	245	\\x241222303210798ea83810c1db030403322d58b77371cb5ba9ec77a64e46e923730ebfd9a8746aee82cc4537e8ee22e94348b4766440f57a8a370ac796559209
162	1	330	\\x8b436dd3fbc13722c3cf1114467c186b036826c0a474a9c89d890f51ce14c50e7397dd5e0c917296346908e3a25ebc1b524eb16786a1d70eeca05b15bc13be04
163	1	419	\\x7b0fcd096e954477445faa91fb64201dd160599db52f77ce1061157866cbb86faf065f954afae74ecc17f6a210467948cc9b55580a76d4b28f936fc3a95e050b
164	1	122	\\xdfe05412fd1b903094f6a809b090150ac05d2c21e5a9afad3b9e6293691910cad8171fbd19a79bab6e89af65b51a5b7146d1ba8f5027e5bf50169f010c893003
165	1	184	\\x5fc81eaa47e6921d1bca144653ace24fa7f73bd69e28b90a82e2e51ab268e573704c1a4f124d604f6fe1d408dea0dc9fa5c784dc93360de46f4a2b9273e61803
166	1	5	\\x425c6845cd49a0e64d015c3764ce4be7ab8994b725da74a0a4636b4c26f1abd0461c339c58b6535f6b30ab7b8df0f42631f3bada42bb014f2f3f9cf0a1376802
167	1	260	\\xe613d814573cfbe7b3b7dcc0a611430331c14901d1ecf0b920361284bac554396cb091ade53dd73d806a30863d03df89ae1165baf69910a4a17d418624597e0c
168	1	193	\\x8ac964770c78b85d4c2ca95f32ce9e85bbb6181e61debca7cc830401d2891c7584cacc6a13cfabc51fbd9878ddbb99fc2285ba3497b68b260a51ef7e833f880e
169	1	51	\\x4a9a62410ebf3041599b4bc2a05573499577753fdead35246aa35eb50bf4b9011b66ec18c94ea08e0ba7ae86eb9315d3a998521d585d7cdf3d5408235d82a001
170	1	82	\\xddad716c43dc3f2d0f7da249db2bf9de900781713f9f40188f74dff5b0be444f9ce3ae27c7a024717ff08db3c10fdc39c2df1ee17d9d05d17b09d6d70aa18a04
171	1	115	\\x43a2f59fcd9b62e3a3abe023b815b172cfdba0f6f15dfd1f0bc0b03d177b06fb6dbaaa92cee50241c1b22da58c1fe5f18cd4898c8a411c7851f4334e5ca12c07
172	1	67	\\x9389a23c1da2c743d93a029fe0a441cade7eed25ef94d1e9bc7f812acbb650d4520c4ce9028fe568f57aca2f81769a61bc784fc83dcfefdc6217b853dae11e03
173	1	111	\\x2cf11385e75deadc59795c30d1735bd249af4e2bc65e214e6167e17eee78ad533f0524e7bf2e7e02af6f59c27c57a31cac91f0a7616409203b454d4ebf99370a
174	1	210	\\x816403b5ed59f0f502d36b88d10192a17ddf93c3ba6948b06dff4d9bc21957db25e6496d2f3d361914d20305e5cac54ab662ad5fe512e02d71a44d71f626f304
175	1	302	\\xd0db64670baeba7a9ca3727aa8c00ab89725b70a0d8cbc09dc55073a36849e4ca1b4cc5b2fea5d5428ffc68e666ac29dd933a4606ed9f904c34e70e5f034f60f
176	1	87	\\x9e1b5c22acae6b04ab9af0b0db0ba1d480142afa3bd5d34ffccc240d7b8bf7e1f8fa8dd640d9e5a491b01c4ab4dae1c181a4478e0ff4817c245c942d8151a108
177	1	313	\\x77724e3d4538296067fac32a14ecf0ee67cb7769ca2875860879029118f6d628393708962e77545a2c8bdb327a760ff28694690a1aae093f012db91bb1c8ae02
178	1	373	\\xca9a1a077b22fc462bb43913377620729691bbb4f1e51bc7e99d1b0ca0912528934866639ed9898c71c2c962cb65339711e64747079791ef306ae1cfeb35e302
179	1	168	\\xbad73902e5761523a4e150a57adafad79c610805450a6621c3b154a2ed5f3850df10fbeb2d29d208966a257757011d8c6ed38616c09bfc448cdb3d917a92f70e
180	1	153	\\xf8de157038e811d4d6200af44f2a94e38ce69f7ad02310aeb629ef82eaa656db94264e32043d55684ec20ae0c303878008e7cb8de9362e417a9f1efbddaf4906
181	1	126	\\xa735cae1c90e6cfb3ffcb9ec0741e70fbbe2461e58312fef56252e50982000a70efb302169c4da92f6289acecce55a81d4d9279097260002b47191cca79fe401
182	1	109	\\xf87bd2308169ea46bc2c654f0bb9716cfadbd8b82113d777862940aaacdb63fdc7cf3bb16bba7e07ba8fa16faffbe05a7558c00650974bea1878de00a6cd8508
183	1	381	\\x07731a0125ea073e540210342b1b135a4027ead080eea953f4e4c24fc971e6fc2541e5a02f89fd26a963f10a59babb63b04a4436c0ae2dc7d1aa2dc3d3f8fd0a
184	1	317	\\x110f57530eb51bf7e77be2cda01cd404935809ea101b5ec0092f5a3b709ede0d2c8b048b70ed2938f1ad33e1b9d3aac74f0f11dd9ccd70a29f0f5920f548630b
185	1	205	\\xad3b45ddcb27bbdf0f0d305898feb7095f9ba00dc3bd315355872f16e200b86aa3ec9b3360e330fe8a6d69f503950bca0ce94162b1efd9ce5f3204ada720c70a
186	1	397	\\x946a797f7185e5376783e934473a8645366f58c31a1466a0e28d58b05d4d27db5a89606d7b15c431e79914543cc31976f73ffe52b16256b211d6dfceea88e100
187	1	364	\\x9615d1eeb54b5e433a8b67470b56217c2ba728f7b829ffdc96701eaae0147224df0268288cb33d64c8e43ee19f32e0c59b357100941f3504ad74d0362f6dd30e
188	1	273	\\x65ffb69503076f3c4781ed3e8eaca03148c3b1cf6e679fc8b765a9119d84e351af857f3138d9a291dde3f7efbe0046a489b1d59e5ac949c187607ec2df2a7d0d
189	1	2	\\x704bb7f7caa9575fa20fc0141bd512abc88f421036ca866cefb533a41c6bd42b3418532510949f9a8b7a04cd3b23920b7bf70309f76dcecca8f33e89f6cdb60a
190	1	350	\\x1365852ad476fcfa4511e9534747c78f49ebf1721cf657442ae280e1b1681d7a51557ff01169ef397fbddde0566fe37a3bff4557b2cfd44ee2607f5bd23b210c
191	1	345	\\xb1ab3b241f39b15eeb6017c162ad1c55a472d34efd7dba9be6bc44fbd00a44dd5090ea5040bd8fd6d88c2024b327ca831c31be2c51a36558435b3ef06090b60f
192	1	268	\\x53e171d963b13cc1cad284fbee7bd875a9893b34ecdced11994f04b13f08be66d8157c5daf5a5273c3d28831b563502c808d54bf57b0aa766f723e2389a30202
193	1	394	\\x181af2895656b95f6bbd4b0e3faea1fe4b1a7216c3abb7e33236e1d9bae7495c6558bc33a49436eca8a5cc5dc351e03d8a9e5bc7e5ca51b43d3884ba34c8e805
194	1	54	\\x585c434d20962fad1323c2c6b02aff13a884d0bc26e5adc8a892a4cccc9e4f4d240a7e1b84932aed890a2b898eab33a656ef958f954de4b6698ba57546457c04
195	1	225	\\x5f01083a513355bf37a9ee86b762b501c6a1e3bfd5d7f55bf9c339b2a1a5e1b8759a585d480d4cce276ba9329aaac69f8eda394e63bbf579ce0b35a7b0483c03
196	1	276	\\x0e5387dae9398be525f7fc57fd030f086dcf0cf1678f2e058bfefd98dd43b4f29dc6f88b6acdd3930a6fdf1da5e429ed4324fac2710f14cc2e1df8ddd8a4c103
197	1	395	\\x0e08ef0c06bdfd349d2df6161963dfc2b8936e19d8939865a25373ffac0df641d200f45ed21a0d0465f20bc2c3f621d660fcea104f1f8673b24cc022bf74ea00
198	1	152	\\x5f18e3cb167d299082e7e6598a66d1f58c08271af9a2ff50c37cc3200ef414cf60c3460a518b65798ae11b9bd2034c1e7596bffd9891d0c74a98ca4a9b73c400
199	1	219	\\x5e731fbe1e79e4cce1a2b75a6ebcaa8af1796b490650944d7516ae1af34625052747d5fa1f37e11b198af4b9f3e10c36e6bcfdbdaf867da7c0e73f117af4ec07
200	1	340	\\x8e7ce7bd2fa7f6899d0a7a6b1f03f1c511a5040d5638191df0c9481d8f3028612cfe0dba4fab958afa8df46a85ee6cf70646c2bbe39e74c488633557f182dc01
201	1	320	\\x4f8a4a411d57b24d722b1d77f34b5fb72304f68fc7c313bff7535024b58b2a5ab2f1df5c291fc39ed13ccf709adc4659d3fee70314b6ff0bc64c8d74588ba00b
202	1	71	\\x37d89ab9b6cb6a579eba41ae91ce952b8339419b6e07b173c301c5b2bb6e8902da1ba64f459e4c92382773a2f14898c3b93763fe601ef7a27d8667532a3b2f0c
203	1	128	\\xd30bd12061911bd32a8e97f436af36302439718dc39b96ee8ae21d9ebf597726a128405b6ae2fc499fc85c63201bc070f13beedab148e57af63ebcda822b410b
204	1	212	\\x1e8285e4b5937e473e7445e390c657dad8b2e21834abb0c0d90756f8a2be16e2695447b2dfb1fe0d12a22386bcea60a24617da2bb3be6493c20962f3c7732708
205	1	244	\\xf0cd06a17da0f9820b66bfe3c7748cb672ea31bb322e6e48474a62ac55502574afc704407c8eb6f2c30364992668aaef97326551d2e922b1f938998dcfbe050d
206	1	423	\\xba403fcc45f41bc4233f452e4dc79b72d3d0cf0715ba8776ee5489734a1afc783c392511271f68dd89f3d632bb5c68f1a6f514535da066d0d5ce94bc79e1750c
207	1	258	\\x9547df35b5118582e2a614a6323dcf0216e8f3292ea086b16f3ae1abef139c9819960c572997e5acb4dafa7c58cc726dca919f57caad00c2de12e998f4e05909
208	1	282	\\xe453ebcae9f9c4006a809edc53caebbdb16a20fe0fabff34bc9f8b5653bf6e904728ba5536ff6ce578ca12bbd3155baa7acbfbeeec6dadfa4b30b7201178fb08
209	1	203	\\x3ec8f9e305809729b21d5602cb1ba8ee96e71e31a95b21c523c5b5091004ff9d16594ba4d3985d6b8be4c97fea8c7dfe1859d4748f18aa6805c806ce59b07d0d
210	1	137	\\x69e9ba81e036ae3345a391440227862c7c6361e33866b7155ff5186a01dbf87436c792c10bb3c2fa89095953c161686551b7430e9a83ca98cc464923a5e51908
211	1	7	\\xf0afd6283f3c45ccbc51d131b70cf05b67b43aa4da2549639d34ae447da302eaa42cb5502a04bf811953dfc481f60c89fa00acdfa2199254a7ae19cd3047720b
212	1	387	\\x300995368a3236be9762ae0b97bc0aac43ad79fbab49235c42766b89c8f1fac44641a8aaab5438f31263b6aab93252afd0af27a99e0df3f063ef8feb850db306
213	1	318	\\x734b19dad16f25aaa39013fd3a3a93484d3161cd3f1a2d1302fcc6a3d0a66abe2ce486fe5c31f1fceef4b0a431432f5e2c0f24c9bf78e8196a3c2088993f3c0e
214	1	356	\\xd4b1848f6a05b3b4b307f881a50ba72171df26dc15aa673145418dd3746184f8745effac08c0580384d52f1d2e52634ffd47d9e20b12d1fc303c93bbd4644a05
215	1	173	\\xc8919d52ebd81fc857a5248b9df3a43817614599dc88e215a901b376c88e8a2d00438f81c53a0cdf1baa30740f2a6ee6401dabf795ba7848cf9944798a361a0f
216	1	404	\\x119f4cecac7bf5c2e676fdc5ca1aa734d64ae6f73f483340b8e2ffa420e773a8ede38023a7af1b040bc10f8981e67df07ab84c805a7e57e978f467ab75dd8602
217	1	64	\\x9388f16d27fb0d7cffa6b693a189aa680efd5ad035ecc7c7f383c621afaed74a25dd6e8cde2584dc2be9e967e6565b753f8a81baec6b9dc9cee6ba4eab648309
218	1	146	\\x10d148630de3850286faabc6eec9baaa9eec49d847c6343527fe7f46aa7093b6a941d927fba0b88ba1f0626d9c832f3020d1914261059c0d8087000652b67d0d
219	1	305	\\x350ea5cf3d6a0e86d27ed93a377443f4e3e9d3b05ac137e12b54d77eaa55f4e8213f4608bf6db8e87918ef93a37526bfc8de8d2ee7cf81abc71fffe6ae8bc40c
220	1	334	\\x379e81631551baf1634d9b7f6d652b4259052b68f5d971c3cb4dfb75cb59a9b89db57217b5d51b697290b2c1a8416ada0113bb650353b5815bcc1e4a18fd130a
221	1	365	\\x315ee4a79605932a398ff2bd8bea935496f5955e265c63e8e1bd5e7e0339a1e4ffcd1ea330acea09d9bcbfa002138bec1868394d3cea985ae68321cdfc7c480d
222	1	370	\\x18feeb909526f480fba8a89204bb53e22af0dfd8037a185347cd1352d902334084075795d59eb8f0e8111ad1de1f02de4b4e7d843f6ce979702e393dc83a200f
223	1	208	\\xd5da9891d3c073f320afd87a94de0fac31f07d7761b058c9fbf4f2d6bc53a55e6fae4eb8862de1b0810adb4f4982d31773f0f72c9d42094ec1c24d5adf79ac0f
224	1	125	\\xdfe93a51baf4d2359ea21544cabf10b06bdb0af0c5b8db70f1fc7b681eb85c0140bd5cec506a9db7de622d33bec0ad21602c140ec67a260975f784ac75980d0d
225	1	389	\\x74b9f9dd22af3683e44891b5288ff05d0c6c426ee888d355e9eef06cc4102cf33ce6ddc0740db4e6b563638eefc58485d318f292cb4569322fa8b00831428f01
226	1	288	\\xe41c0aff3b886f00d3b07aacf4225be6988bf3ea862f4547e4a6746c2854a246e73e94dae6645c62974959ca565c9d112c44f59f5a0c544c6ceaf9eec9b6b801
227	1	382	\\xd5fd17e82a49ca49a13450c51e4f4a02af43938c20829025bd68403a75d0518f2c2623abbafae2796fd99f1f6a0dd35c920e8bb3c2fd2c4e47b3c268dd147f04
228	1	80	\\xc0ac40b26bc8aef05e4fdaf915445f8f8d2115e619de51e552ac93d96f8b8c237e7a82aa27f4a8d675d8fd551472f6bec1dfdf6766bdc6678f2c54db24fd880c
229	1	328	\\x6c1909d60e91ca5445bb23acb57230259677327609d0661a90ffed7b0ecdbe865bd2b160d7e72e4ffe576d45f9820c0a9df0dffd8d4c1f37eeb035a689c01105
230	1	174	\\x6da86d46b709e346882de55180c5e224da793043c3550409502316ab9d90ddcf6dff9b68ac150e3d227f110915b5be2dd309caed07dfe6935e5588f142dfa70b
231	1	18	\\x7ad5d930850ac3ff2026df6ebeeb22ab819ca69ee9e6bd2066da12c62a55eea14a22284be596d195e26d3c61c7dc78da4ada2353e6638b1a1ba816e7843f5f0f
232	1	267	\\x411515a0d6ebfdde6cf8b5f2f611ec16175290b3e8f81bf34ef687490e529c9922174a0b8cad9787eaa0aa316fcea280a79df79f194455fd7cd1f66692e7de0e
233	1	354	\\xe32d8edff65ebec2e669ff2dbba061e84345eb930b96e59b48699e816b74e7094ec6824c3a5795b64970de939e1bec1355a920a610c290f1317c4132490c6c03
234	1	155	\\x158de7c336086fb5d312fe1fdab47b766da5f6969633d2f40e471b1bd173dc7db71ef3ff265568eaf96041670f8360dbd9bd61be657a392afbce9f10e14edd07
235	1	63	\\x5ec491faf332258dd19af7462533d792c880697b2acc72539b9c1ec6c10847c017ca8a1583578d2675310fb7588b8b1d04bb872c1805e1c169b8187c7ff4f209
236	1	34	\\x38200b7d2c965be6bd31a7c2440eb6a125262fe9fb2edbedf9e191f2861575f2f7f0cd4ea70ef723bb1c24be2d283553857fd29184add2413b0679260b60be04
237	1	202	\\xac05a0fc5059d7e8c80d39469cd5568d2c11329af1aed38b6e6eb9159447104bdefda060abfc2d72ec8f09d0f7f90d77f0c289cdcf635861a67b72c695945606
238	1	295	\\x69cbbda1b7a21ea6815b39a63facd45c025403de1786a29347d7499cf831cdfea828a3f05fa4e02d83f4211bf0ca14845a3f9b587576749341d0b83d2f281906
239	1	235	\\x9e0412e8821540f9a08652c6d0e23e377581b7692837f391c8a612905943c681f45d7d49d52e577761ca68a4a41e3eebd2fc2579a9d865faaa4e7e1355c44907
240	1	149	\\x3027149791388d24aaf28dd475a1d4f642a69064723653317064c34babb015fdd187394a3767ef1ce310282de63c2047604a3af1e923adf9e0ea8859d2cd3f0f
241	1	309	\\xef80c8fda01478e2015a951e98207a9a53386fc329e8e3b03702e2ba295478c4c56558b314659f94455be19eff947cf8d41776477eddbca39ee8ee9ffbf78708
242	1	418	\\x0b30912ab8ec1464831a64641e1f3a3dd383d5b78c17c37b9293ddc5186e904a920ce63dfa818c785abc388d8f87971cfeaf0b387478519f288240b27075d005
243	1	181	\\x81ce91d47dd40e6e95a183455fb2b47bade325b51e6ef11c8662c37f3bc7da945bfa8c40b8723e8c701baa4f240fd55670675261c397528ea4f05e7d73673e03
244	1	307	\\xa684f03338d830b5a432318b71621266dd679b4875c0f3c4bac601136384328f2d62e962206fa7a41be6205d746446a4311a02723e6dfb346e212135d9ec3608
245	1	335	\\x7267edfa467bd23a1276a3d16b08a088b3f11eb84085ab4c75cf95c9f0d9f010018d65c17e4bcb0e83e2a3be55c6a452a2497cb402757b839546850a857a6c0e
246	1	21	\\xca8f94666e6932e3f31df8483b6806c22b87e567e52d0365a0a2dc4a7d9494f6238fedeba7c25ee50eba2259dbcb7bc3d0395778ec7ced15c679b1573d2d520a
247	1	285	\\x90497f7204bf68cd728cb61c77d4e89dc304bcde5ffeb97ebad8dcf8cfd30fa26be67dd7b2adf30f12447ec9b3c527f664a30f1d1e8deec24e8d97b932f5510d
248	1	376	\\xcae2ed6528f02bff77007779b584acc5942d6e8832072e814dfc3fef73bbbcfb54ea447fb768659901c926b14f19dc46ee75f934f61f6077f8317c90bd85c005
249	1	32	\\x5e63daf460398dbedb34623f338f5fe8589b7866d55023fdaa7f1f31f08692f74ecd61b0c82591420ff3f28148de0414d8ed76888fd998d68aa4884343d5480b
250	1	12	\\x6280f5cb079c24e8fc00ee7b5d05a4fe882ca9668da82df885e3e3a99630040213f19d6100aaaabf8063794bb4fad2b3b97d438e574c390752b51455f1198e0f
251	1	6	\\x940ad6d0568faa9fd9c8446f222057f99be7e37053bbb72d6f232e23d7ec070b1ce810ff829d5d0039cf9db4e1278011d81807c96bcfd4220a798ae8c448d00a
252	1	255	\\xb2d4b601c0592369707b23c7e7e612ad94127514c443082f782fd3afa5d5f974eb1420f12dc0c83609fa6df411be0ec7f39c72ebef4af4e8fa68926503334601
253	1	129	\\x1108372ed05809b703eb416198c681200a909923267f52466048788a9f3f3d03d46da1d212a3f5b1a786b4b77aa89fc6e00e12b0a6cda207f547d69e54c1020d
254	1	229	\\x89011ac351a5dfdbebe1d7582300e3c7e2f6210b7502c2c292dbd3f8996dea099ae6b7056683a33215e0ac09e38062e3beb44a228f17ae5b629e06571f13c306
255	1	3	\\xd4e76ff817bc1a0574f68a91a60b235dee8469a090ec138cd5039fbc75202cd987b7276bb6c185ab9355cc5d0b9f1ecd060abab8511d7bf7e34c2bffea0bcd09
256	1	312	\\xb8d8efbd8eba667c9cbcea464e37c2e6a560abce121398a4bef052dd259e30029c4aa8fe4481f8685212bb7c1f87c06e064c8a835d5d81b4380ffef0d19dcb03
257	1	347	\\xa341acf12daf89eb5906c5dde588cc7c39091d39f02ec3c0e50ca0025c7cbf19330d9ba5b7984b3ee11addc6d8ed0359f6f7409dff503cfdcfe7b135f703160d
258	1	84	\\x4ac50cf12f4b1d9487a46fad88098807a85ea3364449cb82561df79f1e543f25cbf941e0f4d1c5d20d46f4a52d6a5636b83be403f10a39de1c90d513ebd0780f
259	1	277	\\x53498bd3e81e600c58d544b85a4bf219cba10d2c23d9f1625e8166e349862e56f42577cf7bd731a69a43d64569983dcf91cb0099a482c7bf606698cb601efd01
260	1	321	\\x6fbc3ab87a15ef44f6ab00333d87d798ef0f5df4d0d554a373f89cebedd8e295c649ca080e15c111ce68a3dee9359d97172fcec79142eeafac554a7f03862d02
261	1	92	\\x5fb12efbdd762adfe9206b930bb4f26bffcf17e98053a32f44f6f30bec9328df4e40643e24e738ec9f75ced733d9a26b3343aab8e41f60540564003db632af00
262	1	206	\\x974d9f62d01be577fe3a3eec1593c59c2a9b7090b369a34403bac2013fd40c7099b4dd574c07da2cd6f1a9f15da921b576cddb19e8e5abee68e048d82e00570d
263	1	57	\\x83d9b2b1ac6984716db66a8b0fbd7073c8db284c0e32439d1d75baef7365757d14ba5980b74762e4fa51b01a8b54a3c9a61ed08a10f14ebecde8f9dbdcc5c008
264	1	283	\\xaf4f8267d5dd56a5ba3ce214baf449d24e9db0a05f922b6c247e6d78e11785728d41737007f2e5fe4350f4eee113db33657c9887f1b7b482c331d8907cce720b
265	1	31	\\x61ae71e80dc0ba6310162d0effcc99c9f30afb203f65b354120be1f3bb8b8dcda68a634fc1b9402c6aff70fafa8dfb839a12ac5dda1b7e82df0721551d25bd00
266	1	58	\\xcf5e5aa18c04bd4231bfbc28ea1e312d6e970c9dde2d54a203b5f532701808b6eec94d4f113684d177ba39683a78eadbcae598d01a5a9bacbab26468eed21e09
267	1	236	\\xd5d231e4af9e2247d72855abc48f4e8866abe4d0cdf02b80a59e33fe56d3bf7595febfe06e5d2ad6989b5ed59d1ca36c775727cb0bfa00f2b7f91f595ebd8e0b
268	1	228	\\xafb7c8de734006382ee72b15f0879433025dbc1c951feccf45f855aa5a2ecb0f8b0b2c48ef4f2ac01ee1c62007abe32bf054b400daff9d6c0d05ca44bfa7c206
269	1	36	\\xa0b979c048f8d4447dd040e2652b2b7e5fbc1e0a444684761dfbb071ae47beb65a93d2e4d22014b8a5d3338860e3de3374a3101ac87d9b43188d8dced85e1707
270	1	182	\\xd1a41305160f13c16f610f95a70384b73bb935b404796dfcdf91402b32b183020756a7b0debfc975871a515c8716811167b4096cf5ac283c69f16ebcac2aff02
271	1	89	\\x77ae5e94430939d2a5ae1c2109fd4bb2724925781ac62814eb3f8e78f6e82dfff5ec88687216a0d3f33dc18ec845188069b2f393c7c6f4f297bedcb5c763df0d
272	1	83	\\x590fb730475d936fc7a136ff1af02d3752ece554a89c22aa737dbb5929aba72219da6133cdff048609fa0b07354e1233ddc665c4bd34e2f063031179e459f30c
273	1	139	\\xcdadbdae6c502566370004af6d94f2a198627dc018ab7bd55cfd6d46688fb633a65a37f0670b2b98fb324a694cdae7ca4fea5f54f77d271c816ade2b3d471d05
274	1	145	\\x4951c03289811442e5fc443445fea4c417caa8ef75b6d0148c824c2a611d24dbb82614109904c6bea5f3289235d48da280b94f9c690cbf763ed3e8382f03ab04
275	1	261	\\xab5c2e0008ccac0a778a089504e82acaf42e1214750e1aff145079624e1b6cf1811af86c6fe540ef6e51d1d12f3952354d9d3bb8dddb27df1c4c7abef6a0ed0c
276	1	106	\\x94c3ca02c67bffe324108cd389ed99c573d7b9a7cd338e911ac49f6302f8ef9b3cd0a098ee3694fd0523494a193f37a722f91a374d31b5222b9ef9a0707b4d0e
277	1	162	\\x1a8d6a72e4c9725c22fb2b8f118f48e953824acaa2613b52d8a98916bb9d131bae020abbbe33b21c324cce76dbdfe1884be610e1309250f0d71ba63bc163a80d
278	1	158	\\x0adafabb4ea29a88d6cb64d838f4fc929cc56776bb5a4addd11998c03612768e40823f0067cf52f3654177954369cd8fc48508b433911fd41b81cc1a0e8d2903
279	1	358	\\xecec0ac6ea8362d1bbbfd0b043a90ede30e3b6ead5f587dbcdf52221166d21f4f2d493c31e9eaa027ca6870e524888e907d2821db38a604946c4ec185176d80d
280	1	81	\\xd2ab97e6d1805984b58ceb3911a2fae6dc5b212d85eb81e5a658dd358ab390012da27fb6e3bf3a7a4b33afc6b542639a1dad9409073d2f2e7b31aa45ca1dcd03
281	1	385	\\xa6dcc57114bcc75fa1e32f43349ffbb27913b69f1c1f0d7ed07ed81d8d43721592583df468ca3aef3a955373f527fa18a590abca9b6e8bd7e3b35f006802ba09
282	1	371	\\xa5bcfe8ca2d2a447a3be4c8352d4a61ae1a7e7cdbf5c20114b2fb82d04efb8ad6f2e40107ba7e5c9d76b0ef459d4231172237181c3eebb8853813a7a4e505f02
283	1	239	\\xac9dfdad0c5a3d3d157c5fe4f31fed64d8b20186d968b88300ec17d252c9b5c3aed24b582ab0659b5eec2c6bc4513ad02c87319f89ab3350b7503cc99b0d300f
284	1	150	\\x8da087358bf168e9f296b8228fcbb2d101b3cdf4c6abaf27d9b621201c70d999157b3641547e7acb3589a649c8da2c9da4a7d2e1b6d5308c2ca93e38a82be00a
285	1	141	\\xa5ca5eff0a8d5d4ce716d3ea2ba3ffbec7340ff4494cc65c6d084578ac4b93f40db9e1b1f8b4dbf78155b90329183c822a2a1dd7f737d17afc4e50201f3fa906
286	1	177	\\xa4bc7c44520b48bbaae9e65fdef50dddc559f19fb288154b660e09c559f19b26115c11cfba995313b33f3f41260664aad2856fa8c8dc844ea63238840329c507
287	1	360	\\x7511840b45e6df19ada19e95e08484288b1675d23bd53fe76031f2bf96b980b49c27a56cc6a1e1782c133b347986d73090a1d2425c4fb701d799dce8c5b24d00
288	1	222	\\xcf2f40265aab21b339f409f3566e4b29c41c42d66f599c22e4e485a9ef230ed14117570cfaae486cf844029b317fa1940220fddb75c5f5546fa8640c2220be06
289	1	363	\\x35441c6c8dd5a945229fad1ca5a49cc3088b2e7f5c999954a6cfbba18a956c0c33147fe880a825794b9f4f1959ae02111be20bdeaa94bf9be884975848ac6d06
290	1	175	\\xdc9e0c1020ec9564ae0323650ff2ca8e5a552363a9bb639ef675a9e375c27083cb37dd10646beffe004a6fc11be672b76671779fceae4361411504f492fc6d0d
291	1	359	\\x229f160b871a5493ad2d3bc1d08cd75863b93b0e421e02078cd5a997718cdb81229a6843f3993e987f1f350f3877de3687838d3f8ba94aab00ba2af8d1bca705
292	1	23	\\xbea81bfaaabc1eaef2d9710b8816faa99f707093f94c6402272bce0528cedee8609bf42d278ef2ee7c55630ed5466bf8990c62b75b12373d1cb8b709799e3000
293	1	400	\\x0c699bdd99a3e108991b9f8339c276788719dcf3b0ed6ddaba5484f379e90bc698bce05137856fb88ca77a58d75980dfe7ce6b1632a22d86d92749a6ce895101
294	1	393	\\x42a3c0eb114f7cbbc326702328f33bef3e3f7f1a635570b75e20013e2a69aedd76eef46e42b4fa7ca9cf515df52c74f8fd29c05bcaabd64178e839a201c1ab00
295	1	11	\\xcba7ef2994bc9eddfd48bde8893376d9d544b057ffdf24992e6efe298654a3f2954a29401ef06e3e83aac2c4870f3c7845e242f459cbbc9a8c3abb4d274eb60a
296	1	136	\\x763de73bdab060c50701ded0e037e130f2521644ad43329a36b253a4dfbcd8340bd774ad00bbc357e54fa410b827b4e85dd07a6a2ef50c0f278939e1417b0e09
297	1	132	\\x0fb528ec132410dd4990b4f7daf0413999af2518319cd0e8cbe41e7cffd761e87c3c7abd0a6c3e57d60802614a5095787845d4a70b5956b9de36954122d4c600
298	1	50	\\x537d187bd265b5d66c5478fa82d33bc7a4add9328442a906b634e09b85a9a013378f428cdebb05ed7e9cbe2bed07a52ba92a2f663dd186be42d985c3fd58b809
299	1	270	\\xa0afbebbd6a731a2e0f7fbf28f234cd7c6f51f3a0a1cdfa4b78dca9cfc4280ff2d66e79ee093e1ee20c1189ba8c47a14ae72bb86690740c2ba1c47506a63020b
300	1	133	\\x2996ab72ba6b7b6767994683964596cf08b375cca744d40d6df44e047703e5b8f0193e53b11b5325b6758f1c1c8f82391b9e434bff305ae4813ea4c1519e0409
301	1	298	\\xe3151adb4e99a6c337d831d4531a9c06820605711b1f733c3f77d9bcb21d0cb2b0c7300dd075125bfbdcc4c7da17cdfda16cf9d1465804773a1d882346d5df08
302	1	1	\\x83f3a0219a6a5a7feccd1ed575f904d823d9ab43f07d91115798829059a0bc449bee1294dbfc9687145b6c892b21e144a01b4f61a2b3d3aac13a9f261229870b
303	1	180	\\x60e9e1767e5c33418b68439b27a71271006a5c5d50ba36e434b833a1b66e011200d2d01b67c832b5d68b37ca70c9785c364038b8a7dfd1afdef4867340241502
304	1	165	\\x1079c9260b65b32cbbd17810de9965513e659e146ecc1cd8d6f2c7f040b7f37a39f41a773df541844880acbd0c2edabee07f659882d50a0b99daf2a041715202
305	1	10	\\x9c96df390f815fd23c82a535229877d8ea10cd600e99be0413b505d8b32e4c59d67e56d85d771c58d8af27821a37c7405c5e8c1e7721b6958c112d7c2f7b2a09
306	1	113	\\xfcfcd6b40fb7468624729095bab7883a21706d7e98d58f6644aee5eaefac9b758bf56a2f892be061a303f48707307328fbbecc31a5e0b25640cda56993a9030a
307	1	232	\\xa14fdc8b0449056daf95f06368adee9a7f161417245b4a7b4239d4405980227edf2e29f6bc410ed6f408ecb87ef15d4cd26c663ed445f718f28e7f35d666a602
308	1	191	\\xe3171867ba26ef63bf33fa339640f2f74413a578222578ebf51235ab2124d798bf31db4330d32b31a577a3f7c15739f89d181de62f7110e1b0c81e1bc441ba02
309	1	392	\\x863106fc9931a243f2cba922fc79e8e5689622ed484c8dfa66e662469ea3b879fc2d22e04b7c9f7245908e8e43758fb93de90e5e1f4ddf761be751ae705bf602
310	1	380	\\x8d0a58799c94b62a868dfa81b18156df015c2b8287500aa6a1b335ee13f41f0147f52b8312de0198e58a28ecb5fb995780ee1bd8800beee0b261c18256015900
311	1	30	\\xadfab146f624f8b0b0271c3e4964e764b19138e37f5909aa0f3f04703295d21c2286e60f6e440a755ad83a64275b7107644d9a31e46645e92cfbcf3193a9d504
312	1	336	\\xf5302407a641bfa1f8c8e829bee29e2dd3b681cf302dcb68a0fbb644a3d346999ec415d1b4cd78ef1fbc600cdbb55c9d178692529500896f5570f4bc3c14ac0f
313	1	415	\\x78df463fd1933a98b1f5013ea7a787e0723c07164d8f5cbc2d7d94ce499691cca276a1cecd71234b16d287b0aebd1eca1fb4799cd5b02e02960a551f3b902507
314	1	362	\\x94d1152317080be6b6a3d82b0aa40959b65321912638eda764c8b06f11ce02ec303448b6597c6302fb154e3d4b62d48dd390d249c4f982561b6ee10d7e6d0e0f
315	1	256	\\x99012a39c6597abb6e74f6f08fe9f0cfe0e69c9096aa906359c691a16f0fa41a661113e27c9cbb096220b1a0c5e4420d93d38783e4f8081fed56f52d9e03ff07
316	1	306	\\xdf9136d8c333f1fe669ef259bd0608355150e72bd3e0aa17ec27cfa68551cbb48f6e332ffb5ba39afcd85b47a5d7b7aa8798794d86b331adfb00226ff7843c05
317	1	331	\\xfc4380f50c41e93f276a336ac4fff9c781ab49f20d03a8b10c1c4725e5775321ed46d943cb4343d20012e0045ba960ffcd3771988d3f539b44f91c2346d9e609
318	1	48	\\x52818487963ff8b3fc43f2f4e3aafc0ba82a251b7940aee0c6b7600318c3c517cc3c60f2bcebd6a633ff0f635e8ead2e9e1a1ec2d9c063382699fdbfb437510e
319	1	369	\\x25dec174b47cf5adc4b56daf550ec75e56ece0ec392c6a62c3eebdb1071b207f37745bac6f04ced2e56ed66079ec5abd88f7ab00dff4eba3eefbd6afda04b20e
320	1	42	\\x42385e7e146026bbcd389656cd4ec1ac55fac1a64b05d35c0d7e81c8ac06bdd705b0660d3c617a4c544df2204e0547709e622fc235a0b4018560e4c1eaa3d60b
321	1	103	\\x4fc415833affcac1675b2eabeb69f06460f57251d8870c4f41c8517bc3cb8cc3fabc0103d3bbe19ec7f9fa96951f44edd4e70a01482d49d6fccf4a3f674a660b
322	1	4	\\xa493a1a98a9177560d029b25c5a375bf771ae70b92ca7bd1718f2fdf6778dcc1b189ede87162e0c6aecfc0da2b5653c26bf015e7024868d4325087aa992c8304
323	1	76	\\xd051276d2f12d691ada7ed2394987518aec58374eacd949466143b53031b3a3d06997c27a19820ca20efb9644962afa2a7b8f9297525ef00700f820bd454390f
324	1	217	\\xdbb8cb5dcdd782cdcc57a30aa09c11942dfb28e18e186f3c02b6a3ad00cf4ba4eef62c65865f9b960f872528e9989a892e03a78af8da6902b512b039d422630e
325	1	266	\\x2c5b502ec0070ce448f26b4979a626f30cc90cbe442a09a191e72217bd7ad99f1b7f4d9059fc267cef0d5819cad9ba9ea330732ae62315e0cf96bde437ac0e06
326	1	315	\\x4da86229d6cdb7004706dc6053d4b27c0ed82efaf0a63703c0fe117c4bbcb9fc00b4408ce5de169514f4ea29ab2c4c87c594b2db696fb82143e24d7842fd410a
327	1	140	\\x33517062ce127541baa6ebf10373949b22d23ec9336ffd60d6255874f5b74b32133ab90d8197cc3e034017819e540f655cc31c1d8b8976fae8759f39b95c1d01
328	1	19	\\x57bb74f474e83c88644d63f5211bed0f9651e1f9959059e3e2c59822311cafd7b38ab3666ea246887826a4a8fef853735639aaf0fa625e575bebb9ad6bb65107
329	1	287	\\x9ea876cb146a1f2e1b75301c5b85bafcad25500e24497102b2171ad1da924c0a76a89cfbba95705a2f3a4d3a6277034d506e49eb260b60d63864127d9d35890f
330	1	134	\\x0eea3e593dd795f16aff6f19b49d47352761dad6fe938bac843ebac9d3667fd2e6bce254b2251c3035f3e2345c2ff56e507783ac94a203401e37484806fe040a
331	1	348	\\x76d65a266cfed55f326c0ab7be5b5b370c42f2c863eebebef3c67e89a5e5d167e6c5cefdd278f99c1c90ec3d5a4b584e3e6e2124d9dbe1a683f6ef079bce8801
332	1	105	\\xc33394b92df3ed333f160db566f56da332eaa7970b993b872c6d9ff102ad8e89727f12784e2428b82a261cdee7e530a41c864218a3fe4744a066f8860dc66906
333	1	248	\\xa3be236eaef21e54da611c6ba46789ceec50ebb232e8b74c8dd24ad7080cfaedf40f9e02f2703b8fb6541538b0c5cf7462b4e116ebdaf3731b7a09309738780d
334	1	339	\\x13eb04d2561b1d77c4d740a93df85a04ec4f6766e10cd82b5ded8e4f5ef9d75ceb0062a9d36c88c0462ca552ac1401587cae3ff0f7e0ee86b1fb28b5ed40d806
335	1	243	\\x52c83d73a3c57bcffe6680207d235fd9a8f1a89ce09d639b8a1563550f1b20853a16b51312f701e5f5abdfb48883b866c776acd88c2d0fc475176fb0e5cec80b
336	1	52	\\x26915bf571b6ef6f79bc305fe65bf3030a6ce186bebc37ea18a3c0bc1e7ccaf512f7e848f5cc1f381e7e1913cf7c652091ccf84e879042bb18c401bc399d650a
337	1	342	\\x3adebd8a7df1890ad98cadf103a592ce0014a69751aa04c044b1371ba8be3471977453cc7bc62d2f22397682af3b5e25332712aa8f9c3a35a5be91834f30af00
338	1	401	\\xdfa32bbfa0ea3310fe9ee13a6cf7f42efca863163cc5829c147b6a215b58d0a6130350b5ade3dbbe505e808540a8d39e4f3770706621d15cde12dad15fe11307
339	1	214	\\x5a2191778a6b67bf0253fc9d82149bcb56f9e774f9b890f2bcb2e7dabc0b6d7066607c28b5d675f3eb311cb32a1e50eaca021343754528567f344dd212fc6d05
340	1	114	\\xfbc9c9d3508dfad12c79eac425a86f8cd2852b065c60a5bf09423e73699962601e48ec9d4e883bed227ce49b6eaf2b0e509c360e3dd0a6213f552d38ba478503
341	1	204	\\xeac05bde2f3cca93d45e3cef69b3850f0e0344d2faa1f26c2c058f5d8a688a9076031aacd6640f7629f9a8cf5ccb8552a684b45423663f3137c246111dec7200
342	1	349	\\xebaa538a740c6a5c6f97abbd8fa42774d4fffad07026a1ba5139a5b19124db8ef809fd276f62a56387d41d384a6782e6259fdce3056aab2a84616cec1ee81608
343	1	366	\\x04197719f79288f07618f5fc9dae4f9233d977d43d0541d3195a076d24a8aa653870abd322d5fe4b933af26c79b003a3db051f1a5b5c7ef9dfcdab8a4459a200
344	1	390	\\xfe4a803fd22c58ed8f9269894c2cf871cb380e1a998812a8d737e03dffb039bfcdd53a3477ce9d39a4930975e77da091712aae6cf32b9bb5abf6aad02e5a7904
345	1	104	\\xa1c4cdd8d4033afa7d9519a18a99d8cbda1ad585813fc29c1ae70566c0eed9ddc77b9ca0ac851ca082951544cce95a4401e71247adc63a7563c3294dbc2d960a
346	1	259	\\xa50de3c88157260791be8b16c4f1f7f350d05bd0f70a35f7366c2746774c93507659f0967c440039ca1994c048c71dea76a19d0d502c08ca3e2e319661936903
347	1	274	\\xc6c96192b9da79467ed5d1c8d91745e29495de31b192d0c9ab0c04d3a85963c88adab88f90c3b7d92528819e11320184c2debba7224d49809a610c9013683708
348	1	413	\\xc7c2d7c1d6fe3b6b88192751c089a22c9661041c184e2335a041cc90d456f741ed269936309e24353b846861a40e7f75e17d6924bc3e914f0a17efa1115fd709
349	1	263	\\xe643c8c3be4619ee6cab8a1de41e79dc29649c146172daf56af54fe5fea44fb9f941b5f4f9d75d65ee8a9857a60f6c4324499abcf46fa0d699240a44765e8d0f
350	1	301	\\x8445327c8141d0ec215d641de1f2559576e8be0c60e6fab7ab5a01bd75858aa96e385cb23b08227f6a833dc8532077e524e39a564b25c05054415f0c8086d807
351	1	215	\\x43477ece5dd42bf81e13fb4cf6d6bb991c43eb900c80e99d65815be9126c67b8a82a58a3b8da9e9a576dd4346dd56553eddf157f6e1e4abcfc47ac3d10bb980b
352	1	159	\\x8bf3157ae51ca8b0d670437ae71a8811a83d066fdeb2c15208a61b2df1f6d36713daa23807d6f3fccd6c5a86a1e612ca61f5719b11effe19ee6da1f22c95d709
353	1	323	\\xe78afe0e6e5ccc7e1b01db15eb7ffe8db45d3f2fda209f5eda22ba024702f6f893da6ce1eaa8604f82be218fe4672cc46508e15260dbfa7a02ebf1a4ba608703
354	1	237	\\x9d01b943a6dd8564f00f81ac7ff1180527f1f89c70b46d973ead9b98ea9edfbacdb29a80ccebd5838c32fe01ba75036c1f0fc22d12e9361742b48d5ada4d670d
355	1	98	\\xa35c51f0da579c649f1ff8ab310b95834b92db5254b0b004b19ff65ba23df75662a63f8482c35d8dbd50c04194de527ce3673fc3fb07c150155994e2bf6cc60e
356	1	179	\\x7492b1814e4c9e170d918d51cc2f523c8d32238ec906d19f28a60289d78e416a9ae7edc951a60edf07adb9d3023bf9cb6986659b575f8167d83d8dfe27fec90c
357	1	74	\\x76c20ad6976b9cda2114ae307a057c8c1467b9513785b0c646a397392d12c7cfe0037f11da31b7af91155a4bfd836c9a199b579a22896c824cc33508d2ea9c00
358	1	416	\\x8d71a1463d36e7d88d3877bd6aa34f947f3f2d74ce9482ed5c7a005415c270eecf5db7a2fa673c0458301d3e4c1102bcf3487f1338ff56cf9c01fa367f513807
359	1	311	\\x66787995c6e03136ccb7d11422b1bc7b14fadde3b19c45fa6f1874ab5a7f6fdfd0173d8f79cc90c9fa6f15bde18e206ef328d9510e7bff7731ed70947a62e50f
360	1	351	\\xa62ae7aef403ec6b4df930a2e3b3e6f361ef95169084d68a46f9c8ab2e148ebff553b4eb36051fd02b8d3b55c026709b670df73b708fd33600b0f811e3d9a201
361	1	200	\\xb904b27a9bd4f5f34f5a02eef43967044e8ed6a6299d953da22f4560f2dd3cf96b70cacc2e84242c64e3bdc2151608e573b2b1fd7bfe3d3af23d61856ea2ea08
362	1	241	\\x4f200b0c2451293d884e24d8edf319150a99e444c6867829b168c60040178385c216b8eff51ffa647b78768fb397697f898aa399768d574d0d0a4d5a4494d208
363	1	246	\\x161764eda33c48c9e9264899db5a995a5a8013f752fa942b65a370e2854e723b1705ddb174970165140b49ff4e5785f5d199665c9e7d5f3717928401702f4909
364	1	308	\\x8799fdfae44907d0ac823405e217f0fe6a9985a070c8acb8d0570f0704f6b4d4e6200d388cb028defbe173e87d5380914960ea50ed5d1aecebc1034f0e66f90c
365	1	188	\\xc0cafb07b057c0d062e30391b733ef789bbc48d0f17d65e2c59117e52e8adc16c983a2b79d77c3766ddaf7d447f5b838bab3d2f23cd4c63c5fd60adc430dec00
366	1	233	\\xd23ed297300b9e358033d2ce04b955eebf878ee7bb3d909479ae97011a7e52cae1bcf929550689ee0f82b2031d682494d883ef6c3470195ed13cb77fae89500e
367	1	280	\\x0c5c905521e262babe9a7139b6fd3be9e9508eed960b25a8be7e238c7ce0029c43d581117591656f2f9c09b526ac37d8afb275651e976c69927ee843acaf5806
368	1	161	\\x6b79f93a946aa0064581c5021b3d735e27a6392c0359c76a5849b16ceef6eb66d2c301804ef965376dd02c5d30ff22f71f36c371eb199f3f0ba431011555cb0b
369	1	44	\\x2c005daf923d310baaab3e2bc2de9b54dc763c08cf3d03460211f742f6e67d729a798d058d85f44ba6d39aa383dec1bdd639b1bcefc32c64f5df5b549a95130b
370	1	93	\\x9336a387bdbc2e3f0c38ea5af6c63d35ee3bea31ab7fbde0a9555e8905eaf9faf95fcffc661788014625070a91629b4ecb6b2023118a433f4d0c741c9b5ddb05
371	1	28	\\x94d102ff90986a599df0b5e1068d98b9ee5aa8902cef7592f6c61e2b4b33728c5ae2612b0f69f89c89c9115e14d70bc89698e4263c6cf1e9191d999569fd9507
372	1	338	\\x972c539961bb985dbecb5457b4786a1e7ad94202a580a4e273eb3852deec83c96f3582423465d62ad074923543af4b8e3a0cfdd6fa0042b4b8ef9a7f5183e904
373	1	249	\\x8898d6c077ee72bc6b1ee14d1a90cad2dcc0b345d5966c2373f905a688c09af3d42b3ae878498998dba888eb7ac37d5bb837b706ec328b9ceab064b3b148310b
374	1	90	\\xdebf811d87aca48d54ed44cba0011cf7b37373c6ae035a41c55a8092ebe453a9e35506c83c516e2b9ab55510637249b5ac786851f56fe63743e8a4276d992103
375	1	240	\\x64abe4a44ee01f55411dd89feda78c7bf2a43ea9de94e8cee059c6ec06f08b43b0a77602f1c61fe70229b7f4c38956afb772d304bb973eb4e2057c8834ad410c
376	1	25	\\x1638dc2438ef409b10b1d2d80f8f2f67c6e71e03187f9986e09571a9b64839186e3bead4922c0dc7a78043756d80210a6da9969985a69320dd5254c4e16a2801
377	1	325	\\xe6029421930867277d74f0ba743bdb78ae0cb3311d50d40e16073ef77058d91ab512ffedb5fa476348294cf5677624ea607c76e967e376c2df08b1aa788a930e
378	1	185	\\x5c44227bfa4ab5380eb9ba42f0d6b5cc7b18a1b9d4e4ea1b0c155ec6f75d986b3e5edf8f8bfc59dcbd76733decfe0f62f7ad8d289f704be4da0168a43c14fb0d
379	1	186	\\x480e858255bd9301972193335c7bf9b9699bb3c695b06b1930ca1e0c8205f4a60707cb254856326da5b6d86e0d8d9251596a6bbacbc2016541ce6545929dcc07
380	1	396	\\xbaf2264c239e1a77b1f36ecd47e5775028e9aa029116d480067dcab88f050e14b7a9c6a1c34e7034451708790dae59994b8e5f7f593e212f098f784559c3500c
381	1	27	\\x8f335024ac72f59528c0f5c23c3bdce257dedeb245c04d2298dffb4d677c2f187d7c38abaffd41b7e2d763918750590f6fe5a53dcc36e8d3ff61f7a22345520b
382	1	262	\\xcf0e2f914f2ae6b37deb8eedb188b9ad90e6d9152ea4770109d8820d80a46cebd9915fd4c1064b1b3f160be239a93d35ca72ba67f5442291cc1d8a646ca76802
383	1	279	\\xba2c87d384b452fa3ee5b6b9b25780fb78ea28623439c966f8333733a08f95a90093cd81ce8d013aa53d4fd8638b5e3884f5b2bfed5ab8aca76c5fdab505f209
384	1	417	\\x5f812e386e2324ffa093aea1961d889d5aab4e026385121856254d2a4055a2c2a855676151e664a35df5fe438a61d8e0d6bdae87b4c6f4277c4b97236fc39e0a
385	1	271	\\x1410e7da204a770d0443fe1cdf014c0305efb2ce9eca32bb5b8eb420e240358efd2c7e9c3f5ae268944f16160665b71559ab0c4132fb2bf1fddb7c90589a6303
386	1	46	\\xf5c90636f91a1bbaa7bf9ae954cbe2de623ef2822a30c86a6c7115f49bf71a8a5dd6e5e0f8c535b9ddf88a6b5db11e1e35fad092a7e375934323853937589b02
387	1	209	\\xc912900220f9efdb1765d1dadb1445ce311339275695243146ddeefa0dcb3ec3259eb279809444722f563d939e9c6b7c8d18a432651951302dcaafbd1de60203
388	1	388	\\xa8c8e1343439f4f5c55b4096d7d8414789abf597ea6f710063f0d133d18ba36aef73409d94e718b41e386b6dcf9a94c740b91670c74d2525abc55312ae8a2c0c
389	1	221	\\xed25169486a0b1e4985b619f28d803e1730b986222229e7d27ca5c85a398495d448a13eacea8683b810ea76c46e78d99ce65a92f46bfa02bc15cba57289bf602
390	1	124	\\x8309e96144b77c3bc8dfa3c5c11812dbb56308c0bce56d0d9d4c25fea82c55dd64f1271d924c3f2fd1354f07148a61a9e5fc5d3f0ce4bc98e600deb3883e5c05
391	1	386	\\x8b57da29934d4571ce8f089df3880fb4134b006093a36a0f3928367e06da8f21e1ee727df0c3b51ad8a09a5f1a98252ba48e9fa0e568c95a99b3caf67182630c
392	1	20	\\xff8f33f1b951d9cfd334519c80f79e9f6fa668f9d31b186000f8552be7e4c13ef2b3ea2720c3a1a447fdb5c64d74b5b3db76580a0b426b3b07f8faadb80fca02
393	1	197	\\xf31d15b8a372fc115070f315a936b36fecc5129e30c1d05674e9406c083b75d3e11b79e4f0dc7c8de30583b92ceb457d4a7b766e99f1563ddfe685565af2a101
394	1	142	\\xd615d77059eda634385892dd1379fd3579745da291700d140c2ecdb980a33d1c29c95d381868ae23f54c7e3a484f4ba86d3813c059041e51b38f7196d45b2108
395	1	143	\\x015d3df7e2445abfe785960d03064f92417f1012c1aacdfacc83f41827d49851fcc413d04c800b483c3c5ce89c8241808e93011c134b3a4f2546887e6f59050a
396	1	414	\\x6b8957993007fde40d3d06263f4dde43c0e5eb6505ea93918ed11c8d2044459052eca4bfd22163e7079f42c8eeaf0c0918cb66dd4319300896258d0481c5e50e
397	1	408	\\x50241e0b913b8f51c4a8d57854336988eccdf1b635a1836cae9bb05844b3cf717016d79112a48bee6e2222efa9da2b239a4f70a695ac05f2dba8633f3415400c
398	1	135	\\xd6548a0311b4659820eb0574ba63bdb0d66948a3984fdcd68ab7b03b9051945edcb75e7a37b5cbb7bcf50e4f9a958ca12e1aec491d02afac1b000d441e271c06
399	1	110	\\x787a2b695636d39dc2f04787c2ef280cc57d2844f2aa4f29f8bf400a4bcb74ef87a1a35d0ee9bd30bffdac81203e34eed5a928c376c2dbbe04e8b60c5e58870f
400	1	399	\\xc26befa49582deec43e324a6894cba27539d3cbd17bb7f4f304d044af9547652c5c47c62cad4515349e38a024305b1b80fd78340f9a7eab811018dc47725530b
401	1	198	\\x0d565c1dc6d643791da129dca804fbb2c8b3a4ba4a0258ad63eb28afe1bf9d179adb98de8f2eca9e2bb5855de70caae369e26b59e2efb636fa0f64dfe0108701
402	1	252	\\xb11a96a4f8d458c25369c5aece2a06cb9e362b04163dce698a5429eb9a9aca5abc485dc2afbc94d17f601dbcd0a9d03416178a15abfdc4efee96289605e70a0a
403	1	40	\\x8d508ec81ab5b3c9ac6eef0533c02fbacbb01674fa7adc359b53f02dc7aed1eb1fe4c4df09aec6e2437b74c35e4add80e8fe8e750d3c18d8d4d91aeded168b08
404	1	156	\\x1246fe2eb4dafbafbe385dbe91e155030f29b9717bf642659dd7da36ce1ed31f5160d47217ba606e78c82093d1e702eac2f605a9fc28448d9b8edc84f1336e00
405	1	231	\\x4b549a95360f7fd09b46325e3c34864332e7af8742ae0cebf1cc2cb127c41edfb8844aa82c08b8fd0a66256d3ccf8ec1f357faa05cd1e21b30282b56ddbcf405
406	1	378	\\x296181cf72c78b2473aee71fcb3f00e5f9ce63367dd17ebec5f7966167aff185833e53e703fbe6a74f6d1cc545cdafb588785a71abdbfaf26b6d66ce00f0ea02
407	1	265	\\x2cc27c59ccc00aa7a20d8105277691d5d8865ddfb43b5616196dcb5437125d402c496dcaef59a8b81157f281ee1927701c7074884c12189170e9b8b10f57650a
408	1	163	\\x354a2ac2138309c2af6c560337625264f6e320c279cb2f396b7bf3351c163bbc27ea086631d2ca59a9ed0e379a549df06539f8456badd7a143443c3eabcb6b0f
409	1	375	\\xdb7c505fb6969a601ba5d30e431c1b50276475ee588aae12fccc635bc4fca28ae47f512a3abdba832bfeeb62b0baeaec9cce2d8201958c5a31e2f7d8dc932409
410	1	368	\\x61565610a696d5cd3356444fffc8e3d063bd1eef83166f922db87bfd9eaa6b7ae69de9ee86abd8b07f7d1716cd7346c245c76309720695af0c39a5130cd52002
411	1	293	\\x1156a9876a497ad2923b4d18903177089825f950ee8da0abe2ddfaedc8a787db5e013ec5ffb799b2c19d4a08412888bbba1c1b0e9079cdfda263e8c7b629050e
412	1	157	\\xd412ccc06df9e202f36d74014b8f63d3bb4491dc332f593100ca2b84ec1e26ec89a404798767b901cddce90ab26261932cc44f7b102a09b074e98be34abd0b0b
413	1	79	\\x67f2c613a754a8e14fc38a52cafc2242dd81861f55ebc2b680934aaa1f948f30e07cc57992114d1f111c717d8d48fccf9b130fc2a6e34ed35af2910d227b2902
414	1	95	\\x75e04ba5006ad32433b08ed69f5e0466f367001a4d8ac4d04138996c2237b3cfc534c10e961b1fa86d0a4cad27f41e6d4d930db30baef8adc016452653ebba0b
415	1	424	\\xa8905b7ee6983164c971adda56be2ceefd6ab884de1e80f913091d6131cede879b091458e3844363afade377b0f422b5a9f5295538e328f6b4fce65e4bd89608
416	1	65	\\xa738389850c021c300aec7042458cb1c008cfd51d48df6923aaa3b5608df381f003e5be8f6138b3d9e815f1d4feb80e6c5a299679f29767f5432f4373ba45702
417	1	120	\\x287662e90ed92f72eaa91ddaf072423450a02dcf49d7137b9af635bd966ff48b3b73fe5a8f3125e3357fa839f3564a514c2117c4faacea3b53d8997dc9db4408
418	1	14	\\xef05f9493e8a305436a517364aa8fbf6776642f422ad2780fc6022e30384041ecac0910968ae5a65eaa4b33977fa87d8ae322d0f70a88863c392ba9bb8e3a803
419	1	112	\\xf45a029d1655c3cf90e4994e3301320c57806f8d2f526e25d18d5933bef8e7ea2dc9eb968a4216263ba731df38ddd4065b8d6cc4ddc607cff090f5ec4ed87008
420	1	216	\\x18a0865f04dae7cdeba9fd9c667c83680364f217d55840bb104a04c8b7d17a9e09970810489c245cae8ce262e6ae0f121489b430f88f89cd2223e4ad71bab30d
421	1	223	\\xbaca3ad591fe06e2a3032b1c5a0aff996e798a21a56dcc89d24d4bab7df926b27217eeb5ca9bb525e4603c1c5d2e2ffd85842ec7b0265e202adac8d324f6dd0b
422	1	406	\\x1c0d73b27e481b088e161ce88af9864a03f83ca3c00970218bb5573def77e13348b19c4ef74ae60c7603f3c78116816056b9e8f6ce46afa06eca613218e3e70d
423	1	160	\\x8fe3937f1ae92502a0e41f162940bfd480933fb92ef989f1f7d5d5a4f4a33f5e484c049d3413da274b7e7ceaff2a7ea4fdc07f9705fa273e9a6ebcef0555f502
424	1	391	\\x9ead8457b6e58e31611fe4b98fa5d0200d787e63235214f149ddfe3b26df465ed694a1631a544e98834e77ed9abe1294d727eb78711c045b4e5e695d7c06f00d
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x474f01473eff6678f028f089078b5ad96faa85b67689a82278316c52252072a9	TESTKUDOS Auditor	http://localhost:8083/	t	1660654398000000
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
1	\\x013c0226d53305f1d800c64f1530f3a0500c8092c46dc8264cd84cee535e62fd5e7e34d4c96f47d6289a23992fe6700a428143255ac651791103a09fe73ec762	1	0	\\x000000010000000000800003efa2bca7cd5ac924ba3230f981c43630aa2a197c86e5f11fd027e66a4292f33cdae59a506e1863f603263d792e249e2e596c357102a6e1c25a05acbc7d0ebdf0229500bd8cac0ab772ec0a55f1a64daa02f0496f7962a81848c43d8643a10d642af37af66e2645d4dfe4e3591739a244f2370a7e631ed5496eeb655c0dda2531010001	\\x1b849daa1e74e257698a42736af4993658b53488c938817a078c53f4b32d9cbe2fc531eff0626bd06b7e0ea735aa71dcb8524a63e8a041964b4a25bee8735405	1669721891000000	1670326691000000	1733398691000000	1828006691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
2	\\x026ccd1a3c7a1f9515ae760452977818e88b38c50ee1bf9f1f3ffffc9677797d6da639df83e07cf80936bec19083f59669675ef7c80075a72b45c48360617329	1	0	\\x000000010000000000800003e05f0ce66d4e9fee84cc7a2af58591918da3108d7339aa48e39731a05fc213d76136ec97627e46a928f4603cd25a35e2de11b1172b4140d831d4b10a4b6b8d8b35cf111509d5a8440a9e8e7f31696f9d2d6c47c248ee13873cefbf60b690e1adadb9d6c77f4508e15ba32ef627e3459525f6b86f58c77e6e0dd8604d21acd173010001	\\x76695a37c1c76b1873796f6c6b51c531e33d09fce37e3dea7b4d21983bf04635e9fef27c5fd59fc97d4f1b0132aa273a5e2d7a34336678893fda9a10aa61ab02	1678184891000000	1678789691000000	1741861691000000	1836469691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
3	\\x04b4a14dc072f4c27cf04ba6506dcab0bc0753f37c9786aface5bdfa54393a12c6527fe8075650185d13fc7baeec841ebda970104cdfd8ee2118c80003493ff5	1	0	\\x00000001000000000080000397d1ef4b2df2866d1a597ac3dad8c18d2f97d261c4428322cf2bb1bd231a2961128627fdb905220dcff8cd86e1ca37c499d4f316b4d9560db400644cf72086638bb752c10cbab196b2504420efc34dce98c03dbf9a3ea3d9372249dc4bbb393deed60c7298031f93444da21db746e2e709359b9bf72ee88f89708f669f98223d010001	\\x90063c8e6ac1719c46a5d4f866d428bad0a2e2533903e72442d2072bd99d35b7ec17a45d2c6bb053d726becf2bd99bd3b5d55dd8244ef685cfa75353c4d9fd0d	1673348891000000	1673953691000000	1737025691000000	1831633691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x04981b0782b736e1e115b2fc2e55a6eeb0b592df544ec732d58ef2a674680ac83f8d7a30fef356d64ea125a2705f45a179e8be0ee1ff80a7b6013e5cef35ec0f	1	0	\\x000000010000000000800003ed69dfcc37d9f86d9b2af49d24224a06a202a19bad0e00ef5b63cc503000254b86379ce424d941ad718c4c3c55ad09a07a156588ffd1fcec9cf880aee23fb5b350d075d83f6e13a5a89073d6f11bdd3cf96e21d3fb4be33cda1aad7167d0c752e4a553b03ff08b5249f1a5be9682a2190db7b1ea07f238b56f49ed7dc3ac7513010001	\\x932aa2191cfa67c2c8d2286d42029daa2bd21836360227cfbf2e67747d37136411c23a75b93278ee67f030059cffaa35ebbed56d27fa7c23485bdd7c76d8df0f	1667908391000000	1668513191000000	1731585191000000	1826193191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0b44d378bf437ab21013f0ef39ad4119a4f9dcfbf4e66689f60c5737cddc0018bffd1a66d451069db258bf8bbbf1dd0b8d67157c704b9b3e51710775464506ae	1	0	\\x000000010000000000800003c54b5df7ea6c3b672633f7b6aeb77df4bbcc426d6162c480c52792ca9366f06b5cf27d2a661a8206d68e166064804dbc9609a5717cf230457e3245add816793a9c00fdffd63bea6e8d3c840a70990c9a058ea060856ced0638c0c243b38ee96ef51ce56b5c04af1231a55ee43b2aff1f5a222246a62309ceed574f0461166bb5010001	\\xc584fad787c66c0b27fbfd619365505fb14545c9208a1aaa5f3d14d3d1b934116573487188a2ecb5fd00716cbb24b6b6e75ede3d851bb9474ed14df646dad90e	1679998391000000	1680603191000000	1743675191000000	1838283191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x0cecd07d7c6f9baf12f08791560a8d065cffc8d965692c67473379b5cfe7a68181a12ffff4862213258c48801309348bd91c856be1070f4e37dc3bc82c674ce5	1	0	\\x000000010000000000800003d56cdef611a868fe99ba90cada90436df283753fb199a9a210f63fdbf6d8622ffa82e92af5513ede436e989d10b3a9d08ed299316755819a62257c6ec61d5efa30e50d3941989b6116a14be2efc1aeced5b55ec17f1f20467881bb52a7676125122d25481888dcf77cbf5172d96352b3a0c2e10bda91073a3ccc8e90fcf3459b010001	\\x435cc06bced8e5f48a49dee59263d03a5274ea917f7811fe2041052d535c4a6d7fd46809afe517db7f88da32ae94771374ccb704667c8c91223ea721d6eecf05	1673348891000000	1673953691000000	1737025691000000	1831633691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
7	\\x0d10b04fc4b615c8a312d6eadc4d9e8a318cb599cee3dfbabd609139aed4092f16244bcf37cc8a423cb3a07b56f13bec5026b12cc2e753803fa8e0cb86bb8f42	1	0	\\x000000010000000000800003c2b44c85a2d36603447ab7748ae2f45446bbc04a97779f68f5276fef062c84b4e1aaac1715e676b24ae2c6c150808e9d9f4033b4687556671fc216ffe3bb7da7a6d564b356b2c805834fa18e1fc0de58dc2ffe59e71ecbd61246530f06f7d3fa82f84382e68dbbb484ee80a2d915e1574dd7ee1abb1c99c37018167d873f8b11010001	\\x116d295b3080d252a284c267cc4428add313dcdd1a794871c951bfe6da4d8ebfd863e2cb2f3310bc31d5fda36a600997291fbe340f0da05decf638e1e9bd0907	1676371391000000	1676976191000000	1740048191000000	1834656191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x0fec7423fadd645c16269e69d451acf8bd7ffabd57ef5610727591e89c92457d6f3470546e276d5e219579c0381dca7fa02a90720fa305f55cd8ac356c1849e7	1	0	\\x000000010000000000800003aa9e317ccd5ceb503520c2f980b58e1ec91ae8af563560782a12ee4b794ae66f4bf8c8cd483802dcc9f734a79f368a56703d835ee1c0625a02884ebca329e13db676b79363134ecfc1773a17bac6def223d92808b5443b6c9b849312f2dac43a6cb7680874b045bbbf2e98cda9fbf65259b0ec1dd1302ed8aa7e81caa04e4255010001	\\x79c05e38a9c1f0dfcd54c6db06fd90d0e55cf4982c7dab385c230ccdbf33037d935c7748a75696979b96b860d2fdfc3f95bbbd9b3031b6048ab3b7d34b49c00a	1686647891000000	1687252691000000	1750324691000000	1844932691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x111c42febc820a69edf51ecb845d6a65bb2828c946bf3c857fdb74a44ed82427890a8d531584acb40cb879bf0a7cc8bd5cdcd1f581e6f827db81aed8fcb2631e	1	0	\\x000000010000000000800003984f43937232aa5f470dd10a9e254bc0c502fe62d0178a45305787967a6389bc573b3fa595889f69d2578980fc3628162c43bf2b0f0c503cfbc1937093dc34b30e073ea07254386e90873ba4cc45680b50dec96f62f051bc8862a81c499b45fecbd39000cf3326addc7336e13dd430e1e9fc8b4da538265eaaea6d19e21a3965010001	\\x4a02584e86fbb628bf2f84127e711c0711d01629f9c5946302a2f66c3f93da9de12a9f9eeacca31a5bb5225410ff45b9c42714a73d16820c78dcda7359281004	1681811891000000	1682416691000000	1745488691000000	1840096691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x16242b6d3262adee347467501dd6197d486ab4f4a530395a8ae1d67770cc363aee95e2f3670739cc926a0f759f1ea51d5e6210eda598e200dde5b87ca9e8514e	1	0	\\x000000010000000000800003aa72251f206bc9a837fb2532fa183d3404597985f1287d685df08022a3722a47ee43252d286d0bef97110cf7b7ef88ea375e5da8f65390062de3eeff39d3bb8c748a654fc410c9c4f8ea59c55f7f08f8817cbd51b8bae40daab9188ada9a94042c10e426dd73168f8a9c2b2d70a10fac498a28098dc91dc22c645f968dc4d8c5010001	\\x02aff62327b7391fa39254c58628b447c5c6bf9ce1b03e5d9855b2d4d48ec91753598df46699f95a0042c359ffc2328afb54aafb0107197a0667525cd8b42f0a	1669117391000000	1669722191000000	1732794191000000	1827402191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x1740d9d5780eb537bcfaacebca8c84c3632795f7604f90e9a981166fee6b3232ff7cc6feb83f885a51477362c8d625ce21eccfb67fbdc07f43bbd02156a38c0b	1	0	\\x0000000100000000008000039ed772ea61135dbcc623c8bf7b80e61a1db37d2d0657e1428be9e2b6baa7c65340a0e5a37f93020a36c0567c190169fe62cbebe2bd5d3ea77c229bd42f11b7c497c5a05dd0b8540818c15562faaf1ddba3fbd421edca69c739b7238cff905f0ae8428918fffa1b6870b6569d1ef38f124262d8464ffba19ea448e6bbe3f6bfb3010001	\\x8265f048bfc0f1ed7d2a1971629001b8abeb7455812ee652877a714082e99efc3e07b985372edcf696b409934af7f5fbb6c6d8b33cfe73e113685bee6b4b9d0f	1670326391000000	1670931191000000	1734003191000000	1828611191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x1eb4b8919e5b1c06dc9038207b356b736e433ce04497a6e52101c9b5cf7a28b5e10de2d8ae0cd7cd8a8dbc0b0055a0fc8b1c04d0c962ec9e70d077ba3ab75d7e	1	0	\\x000000010000000000800003aa9decf8b8ae1ff41562f435565dcdfb752975c15899402630f9db0c3807b0a0eb345ae871d55afa2df05a950272005e6437e588541c259527a8e5c2d616924d6bb81dcd1a96b4de99dd515799155b3c5b809db2af14ff7cd15c1bb7ee0e7c5523a726f57ec398448155c5e285bfb9d0c08ebfddf21e260cc59f597e4f6089f9010001	\\x0e5b159442f8e8694afe7b014df4d46d493ab78aff1511aede7299b04b655b39748e205a9d2bf79e0868b4acf60f5d8cdde34effcf54db748ebc3674ccffbf02	1673348891000000	1673953691000000	1737025691000000	1831633691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x1e38751abe71258a42dcc868c3b5a74326455af3f37774f559a6bc938865be9864dd098fb0fa40b3ecbbacc0df3ac9df2ee98f4ab832c6dd45ad7fba80c2e1c4	1	0	\\x000000010000000000800003af096d112d1439ef93c3a442ffa2217b5e3986dfc83a2895fc1590724102e95daf1702b874f34b1fe3f83e30adc9f04eca853c20257799572dd646fb3c1ee906dd1a3b8b94287c4adeaa6ff98fc6563ff0a8f22b5415686ab8e32f416a8341f9f50b5068ccc111ff584c0d3d4d8c27e78f9e5aa7c318e27b14c787a38ee14e2f010001	\\xb9f4d6b30bf2c7889e5674cfc224a29ec4c85b5ce673606ca06931699147aefb1610255d59f001607ea4848cee70d55a94af583818cc1a0c01e326a79fc2990d	1686647891000000	1687252691000000	1750324691000000	1844932691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x1ef81269fe81cd735145388ea39df9f0e2599f2b7b143304b241c2c535ce09aa79e0428b189a1d895768abfd263c95312708e71e52dc73312f50e34d799f8e85	1	0	\\x000000010000000000800003bb152c8c2b1bfb317f847487c30650ef45a9ccb11c11c582ac6b7d538f405f6ca7bda6f44d29b8ee548c3e1a4935fee4ae010373e1ff518299baf06a4194604d65b37413ebcdeb7f32eb6875f1f3fb24fcaae8e33842c2d4e542ceea13da5aad2f105de28fcbc12a3ad4ac7380a63b594ba29018436aa105be3d41c08c24a843010001	\\xe4b98454db6990f700074d671aac7b79c4bd8be3eb53d6960a05bbd3a6383599f92c320c1022e8c609e872bc74a599a9e0ae7624e2a6336064778f2954051f06	1660654391000000	1661259191000000	1724331191000000	1818939191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
15	\\x21bce487dd92f020d99b04504a3ed2b23655fdc1229cdf42ddd5e676aeb732bac8c764a734d1f3857d2d48d70651b36c27bdf976173a6aa97a2677f75fc6b99e	1	0	\\x000000010000000000800003c98e8308f4d1ef9cb1af360c739502d637e0b562a4a4987c77af5e0f7ce6833a87443128c7ac47937e0bb6ce559f17235428418524c79d38ece6cccd37230904221a4ee9502963294a25651b4a5fe9797cf1c3b253b03f166e873b9d8a32795e4b25cc7a2c166bba1713f8161102ea2b9c023ef77170dab75157710e1903e815010001	\\x74dc291d538cda4aecf74166e1e307337df54f84ade20d384f6a3a564d488eeb2a0178f7b1acdd5e1d4879151280083d454d002aa62b9ac9e941fbfb0c8d4a0b	1684834391000000	1685439191000000	1748511191000000	1843119191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x211c2315d72b6b0d8649ab97e9a83bfcc9c6bd3a4ea9b32c8849b0eac24fa2b20061904583fb8ccd61cb0cb94cd946b62e09abb21ec13f507b9284cc5f0c6730	1	0	\\x000000010000000000800003d4f0a0ecb031efbef03cf7bffb10b58f171b2111cc44c59afd7dcfd72749d55c7737531821713700b6f4eb55ebac072407dac37566554c80450b824eb6db51b54dcca68acce5ff1da915fc11d5a6359fdc1b77435b198aab37ec10fed3228e597105d6852b1f7ecd2efa3120ebe235fabd5213e8deee300a8618adff112f3949010001	\\x80864325642174a561bdb0b29a614d9fb8237eb78a0428e7b4469b4fcc5148bd0baa3680b7f8a648b15d551f1701760c9d72505affae9c19d23d9ae17c61d202	1681207391000000	1681812191000000	1744884191000000	1839492191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x21508445fb9b6c8a44ba7f4d60fda6056f10d5f716f380fac748a769fdcbf10e3c9e228eab25c1c0892c63ffbcb96971284e4254152dc24c9bb0e5af1d47261c	1	0	\\x000000010000000000800003ea7bc561422547ee0e198488b21a16af83d8ea4814c620c0b3fdf4d7dd2829c1a183cc42ce75b468ac64f84e7e0d47c415d763e344878bcc120fd77d234953030c9596593a0233321bfec5fbdbae18161a531bbc1afc67b2ab15964f8ac27cfd8e15b3ea72390f5af6a09404b686539016c3056dcad2304c1a162cd74d9af377010001	\\x52f0525da37dd682e2fddf985b048cb825260183a65b1e438ce0870cd5bacac242e25f017d8006ce6eb11d83a016b589b80bb2d7dad46545c2448d8caeaa1f07	1680602891000000	1681207691000000	1744279691000000	1838887691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x27bc02f74f6572f6347551d57f256608b368ee715273944d97004a220206b931adda32c569153ec7fcafc1dc735e6fc03d84b3053e3d4cf974d60e76d52e4147	1	0	\\x000000010000000000800003de9c926ea1d0cd97d91560462e70b43544d861e581c19c11af93f1576b52b631c10e38083dc008881228e37421b97ef2262f53968d829883fec77dd9bb0b2d17043fc17576a31938ee9be1a62ec8e5ed26ebfa289f06c2968e3850e5cae4b994b852645efabdcc06d661cfcbf02bdc89e9a332af75466d47e8121df3cf3e19c9010001	\\x0c233f3cb278225f4fc4177c988ded1e3da68a6288620ae82e117898df26fa6f00cd4f4c3e770e579800af4196f2ac33b4e002ecb74b32440e38110802fa2901	1675162391000000	1675767191000000	1738839191000000	1833447191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x2b801dc3cc7b9aef37ed8018f27a0f4be4082c1cc4733b8be0fccc5ad970b1cbed889804a5447ff7d8ef0fe4bb67945dc053b63a01aa25124885012010dd85ea	1	0	\\x000000010000000000800003d13cd1ce5cb3ea84108e7cc0eb6603ed03cbe2b3c2488cdd7d627f6cc64b8c5b4602789505b7c76fabf2d098a10b4aa7a12836336f21311c4928be3e9e2a99f1e6a9c2f4cf64f45667d2b0efb472beaf9babe5c4cd6564a0044d0951a729dc23d4e6748d8ac30edae988460fc51189d468f5b4c2f02bbe052c09edec107f23ad010001	\\x8a6ca4412b4d60af1aadf7b2257c74db33ef558c8e8b904bb5ba09fe868bd6e282cc64474d22c90fdb653a448826ec6aa58a358ec58e7bd5aaadd3bec90ef209	1667908391000000	1668513191000000	1731585191000000	1826193191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x2d5cbc24879e215780c5c09635761e53cee0087077176508b702c24057b5c951c2659b902c02dc4c983fb3af7fb9bc1e1f1abc1c825f18830f4639bc8127284d	1	0	\\x000000010000000000800003d1bf083000a65f16f33991558c33ba177748590a923f1b38f965e3a7d019a8c4eae79debef5e3ccbac4f3f73b77e853105f5d0e194f7cde8008dea141faa679dc14c26a891f9b9ddbdf05b6f8ab0d027280d1929f1a730718dd3a90b9a47d3548a0266b8f37065baf5e2f998cd8974abb7d9ed51f805416a03d0a5c4a4b97739010001	\\x1ca05fadf78a0a77fef5165765a1221daba1d0ca264bd51ed5d1722265c34505b4f7404a74503fd260591514b6ce3b6f474c39ea9e8aa0c4bb75ef6ba0d4f304	1663072391000000	1663677191000000	1726749191000000	1821357191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
21	\\x31e498319785cf2147a29478457389ac0f4041a95f43b2e569c75ccc266b1dbde9e2bd756143b349ad4ec18f5da58c3d1b5a8000d8f2ce83300d57cf8ee1018f	1	0	\\x000000010000000000800003bc671d712e0f44f516a02bf3a7e50a701ba8e0cf45bcdf21610d1fa04cc0568d46e45260deadd654c1765c187a96a60b819f9d25b9f06806ad4ef4b80ac1c8da0fbec38aaacc40554438225ded677de7d75ab642013c85e1fee52f78490c35d4996b63001eeac192eac478911b9557c454ebafc88e874bf45559cbd5666fad19010001	\\xc30bab704c3f0f3bc1985cc973b0bec7d398901e98cb51835a67565d82432dcd141e75b5255ae4a76ea888d23a63a1d703e6a1f6d3c4bf88f726258e198e710c	1673953391000000	1674558191000000	1737630191000000	1832238191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x325c991f285ee455928263ee1a9d88cc8572969e07cb98863175b480ed6fd79fb946c6ccb3233eac6705d5d2958c6baf12d129cedf01ca6ad2e47cf903a1c3e0	1	0	\\x000000010000000000800003b0fdc47e16d5aa7a3315fadabd43be36f8f613d02849ad91761e1781d6a6505ab255bb49693e835c2c6799904184f8227544a0c3e2457d390fea8efee8c10b6d583405a698b28cd2134994c374221d213569a2d4d4fd2dc8a6c67e371c08d9b77d152c3008c1fbb4d732e69258333c364ddb97a854f0a4312df2ac43be605a0f010001	\\x4b794db37c70caaa0b5de22779e71aa09aa8e1fe17a352fcda8874731dcfff7109d0967154d574b5fcb76b47d4f39648e359b4f6396ec9088d115693e1af100c	1680602891000000	1681207691000000	1744279691000000	1838887691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
23	\\x358c25b541739b7ee791b89decc3a71554b1699a75c7ae837f3e33116e5a1db9cfbe880b2cbbbd0784d222092ad5ba3d78a83f3ba537d39c3b9802a42fb57725	1	0	\\x000000010000000000800003bb99aa919fd67241437b915cae4bf01c04633c085cc799d1654b555cf729e0a6b32d2363637fe5e1a3116752bac0a4260283e791b951b94efed79519dc1e68d84a90cc09959f01f44c992650049ef03c879c73563aff41afb52e8c5f0f60cadc453d3ea00257bb49cd992d0d5644b59ddecb323cbb99ee5e7bd06b1cd8c0af77010001	\\xaf7a5619b3d3ae860f0bf664e0a9213ccef741e8afa1ca6dd7815d3d0629de3a5de46ce7abd14b0327858225894c542109f6ee34bbbe508977fb5e13fdc0e50d	1670326391000000	1670931191000000	1734003191000000	1828611191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x36142ed936070ade6c96c96c68e9fe560e304bcbaf9af826c33cb4a6da08a4deb4c39e00f57201c7ef6b75a2656d1108be9b1b7949ff448276330fbd69a9ee85	1	0	\\x000000010000000000800003b7824c8c47bca06f641795673152b7de3ef058bef3413e12db92531b179ad020428502d1c7ff6c6f1f5a66d60b81b29ec1f17f0302acd1c8412d27859666f114d75aa27185c6971871d2faa8c0a1c2224046a08e5a535b2f9c06ec69a561dc68546540380d054ee3df7e36c19a80f7de755c2c97e8341271296a28e1d8edf1bf010001	\\x7c463f4a869595abe5c03bdb30e671b4993b2004018074e3c755469a797c414289e8726aedd0623779a059e159241cc7bb25a3a6ad3bc74fe871bd311c3a5504	1689670391000000	1690275191000000	1753347191000000	1847955191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x3754937e5d40e92c91deb6317e87909f4f7e1d512fc54fbbeda1f901b5482e6f56f3b3ae919ba03c6bd2bdacc3daaa8647b23cbdc29f83133d52651196f9ebfd	1	0	\\x000000010000000000800003e8fb38e1f092dac8bc83cd1d503d44b0e188a45e5442024ad1f35c71a72d8eebc36a5ed9a24b73bbbd76f150758169a9a3a65da4f262111ff9f8ad059049e32d4b1b2c5d40ad20b9e037edf7e4dffa26456a6852e8046510c65ce1569939ef1b04ed651b732bc040ca736a0e4bdc16ad89a6b82516b227ad12313f0674a67359010001	\\xcfbf721bc67d4c0332ed1ef953b3ea361b02aa95fb62232b595dec8b3c4909784a391a214d21b7be25cba31173fd0864f2fdb6f902565019957ad95690f4f304	1664281391000000	1664886191000000	1727958191000000	1822566191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x39c8af747ec6e1d673d3862fab717596dbbf973356c5a2a4eefa548adec46713206d9618d63e23b22515a8be358f13f075737813ac2d2ce9082acfc7bacdb0ba	1	0	\\x000000010000000000800003bc94bc89c261662f1d788180f17561ecaf9e4e034a0ac4c4c148df059b5c039ac2bf0aab06743fa80642b0f5be4ad58a33b1b7d7912fd223f0f18d24307f6485c6bec7bddd748fc9d4ed251aba23628ee52f56b025b85deea530f233488a43afabc8f433b7690fd5a242219d703e31fe3be8c7280119f1f0383d531a6e99db85010001	\\x87959b80bbf835bfe6bc5685c556284089299b1e53c135648949af5e0b566a350de01570973f6fd229a7f429d95fc55fa803b17454f4192e4c3437d21008700c	1688461391000000	1689066191000000	1752138191000000	1846746191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
27	\\x3b94432b4629a8f2a5776c9ec59a6fedef6c9f8074abb536a3a94453c45295772939c9948ff715c46f70b0790d59b1157cd5c6bff323540cc80bd4ae4a92d458	1	0	\\x000000010000000000800003d45ca42539d2aaa2d27a6fd028428b5a7a971585af7eb04eea3a6c47374253bbdfdf9ef5c95229108cdf2c7edb59f76b794f725945da2647ccbe05d34481588fc03389ba500140b6d350b22e9733f23229860b7fde32740d57e2ba914ea78f521313ddbcfc40eb390551c7c2a145a5516c8fcceac53b4f5d126168bbbfad2dd1010001	\\x7652e8ed038bcf530f0b3dffcc28ceb33837143e553af6e7258d1464ddd4c9e8c79e96c8a075be4457a79d632bc7fe38f2fce2ee3bddf6271895c97724567701	1663676891000000	1664281691000000	1727353691000000	1821961691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x3b188037202a4c6707ad46ba24627518215df4a036aa089c4acc038ee004f7f1dc20718f0ddb39afaeb2024a252cc9456f5441b3729ab7211b8b4661b42eecde	1	0	\\x000000010000000000800003cad84bf8e5c1e9066f5980ad695d1102d3980578032571da29e4a26f4aa01392fb5cd358b7ac7396da4a9fa541acf53a89aa7330e37ccffc2f1c3f9bef88d6fede1ff0136d0e980200fb71e6a5dbbac5de29eb9275aeb9de81a8d7163966e96cfa6cb93380badeede666de29b1084d93ed6b20ded04eef0817749210b8ecb481010001	\\x258607f29a381c7b75d7c7c8276326dc9073728ee1dbe9f75ff68b73a6b912f63d497668cebd97cc739a499744956484231ec2c579f809e6e00401125cbb6a0e	1664281391000000	1664886191000000	1727958191000000	1822566191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x41047fe8bc032fb93ca3df4761e17503bcd3036d3a0643800d22b508189fdb45a71c1d1a0ad3ae43ad500f32485a8749fd8137acb9593a652858782a1bf4b01a	1	0	\\x000000010000000000800003a87243e20d063f5e2397be6710565064a157942e4c0ec58c101bba8b1d0922a1558dfe713e8afce4a35a376b0830ed2bf433cf972352ca8a0c9e1d9751bc822d039b00578eb44e0b705f85db64098d62b69db293d24ee7e65cdf4b0614332c225c616a4a72a9624c8bb8544557be82e6bcd8a271ca13ab318c268e4b1e6c0817010001	\\xa36111b27a0ba401f9347d9c292621eb5336504caca255b70309472f86df82482641aea3c850de714d5d52a5a6fd49dc7a6510e64007127b963bc50bd383410e	1691483891000000	1692088691000000	1755160691000000	1849768691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x41e468d531773433a7be3a661cc4c4f27a79b8fb4e4fbd9b2875ee555206583d4f923b50958e94f99ebd403632f6e6414d0e18da99ecb2a87e96c5363e1193c4	1	0	\\x000000010000000000800003c0aac29658081c1c76fc64aa286598657567463f661e315a3cea989e3f4112a32a0754b039f67ad326490de4fe8af595686b08d43e05e0848c76c6a6e73b421d392b5ef1428542f47d5f648259fb36d7f722d159ee4e278ef9256f070a2ee2fa903b02b3c3abeb01f08130d33616fa0f37624352dc69f4baf61efe904ed08ae9010001	\\x193e151fe17cc8df9b92d7fd4d65c00b657ae24ebdd47ef8691afdaa6c23b9db6259be7455758194be3f1f4492274e2b9e6a533abe6c9876275fa73a28fd6705	1669117391000000	1669722191000000	1732794191000000	1827402191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x42e435ab78b9b5df755556dfeafb1e200d1730bc6d1ef92539c57f1db4131773b8b15f88ff95b226dd688dde978f8a52ecdc5a1b553199f34448fad4cd76497a	1	0	\\x000000010000000000800003b50e1a78fd06c0746201ad686cb79f5f265298055f908b81d45d20622641106be8cfdc85d0cccacb246df92554923017412b4875fe07504813fb9fed60975406d8bc75ec6a936fb5963f8ab96ee0bde5693d06a41d2a816fa32edb9a9177c710977ca2035976677277ef674524d466a7ceacdc6ea69d14c23c29fd7b6a2dbe59010001	\\x562dbe3587d1b2b355867d8889f56c8d6af529551ccb9927177c24336c453df7c871e201eecb206a7684c945faba531efe2570bcf0fb3ddcc5cdf570989b2e03	1672139891000000	1672744691000000	1735816691000000	1830424691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
32	\\x4930683464f09f62bed52738cf07dc2e991324485db1fe7fc904e89860bbe5f832fb28de54bef3d001c3e3b6d936cf7c03616527a46b6280d2da30f7b0d3f368	1	0	\\x000000010000000000800003f050773df97675137118840e4ed61a0c6d46e1d32958cd6a205991510e9a5d70879ba3f45546484ef55c4ae683ecb29f7ee2c5915bcec32d97a827500e80a6468f899a7084c9af0c08d95331bd89aa46ad93a2cd3520ba36428a59876e98c84b28aa84b7c4fae0857718b7da365825ef52d65606b3391eefd34b3a6e18289645010001	\\xd279a988e1e6ee5915de667bc0b102864b0856a6a80c1d22954e6024706f7b186c597014d4f147da4da977f2d419f97b273c1ce0548fde7342255ae675db0009	1673348891000000	1673953691000000	1737025691000000	1831633691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x4aa4957f682117d37ad000b8468512bfc6e386a52c1118a7c534ac1c49a1418b244c230189aba7bc17bf49fa3e21ceafb9e7b870c2aa0bf793962ba6b4bda2ee	1	0	\\x000000010000000000800003da414bf39aa329042d26b98f953b28d808ad5badae7f5c34e77584e61f5f56efe09256ad1d02d03443ddbb56f67e8420dc466e1a7f6c8deea9b93190eaa843aa84f196eae8194a816b0852c1e08f122558fd14939ac0f41837a52f350cc9ca922130299dde92013b9802279b3900583ae836e8f0fefacf9c4519f8a5f488db8d010001	\\xc59cb7d5085586cbbd3f5771d5ee800e180169aed2cbda203684162863e63a775a94d11bb9ef1caad3f31027d32e1f7178d70f3167b3cbe14ba2f0037573760e	1687252391000000	1687857191000000	1750929191000000	1845537191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x4df485d8f7eecf81dd3930a172fd1747668af80721e8450670825733c1a62a813620d67551dc769aeafe76138d565e9851fffb3f49829455ac207410fd7885e0	1	0	\\x000000010000000000800003f058402ed5e1870a0c72b43b2dfea4fc3be64390b3dc90ad93cf8724e2475b55880fd379284af886e80e2452b74e39deb1089e1466e6b5387d1633d67685a7d78e411525e335a1f43c4592b4182330598fb3e6a95651be0a354defa2373c66ce166334d366b8b1c93c071e4a72de22fba41cc22a8f74bd2239f1099a20892a1f010001	\\xd641f586f3ddbd2d1939bee56b8421bc3c0b2041a9b1654ef50aeeef5fd7f61067a1716cdaaa2693c5692955d0ff4fe2b1392bd05a40e4e31dd4ec0ec68a3f07	1674557891000000	1675162691000000	1738234691000000	1832842691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x4e18875e8217cf623e3f7d3fff66c37691c681c6b1e3b1756bcaaff3709e7c171b7d8a9dc5298dc91cda70c3b240276160a2c3a7db9af705b43a2ffdf8f9e8d2	1	0	\\x000000010000000000800003a6a9f515024256f55ff6fd29942b17bf77f610071ab754176197e73686ed15febbdc4103a6006443fbf9c3e439f92690142455f52fdb67d66abd16b7782c4bebba81e6c388cbf21d7004273d119808d89e9dbce169255bac23c3751ac71a1f62493ae1a9ea31479ec7a153b59c4b66912956d168a5fcc3e4a4571ff6f5dce23b010001	\\x611ff908373de791e21b636bbd2811877605421f4920d675f3a9fb6189209c8694fc0a8ae26663250770bedcfac443400d3c722c61a7aaa6cd4514ab93e6140a	1682416391000000	1683021191000000	1746093191000000	1840701191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
36	\\x4f68afba27fa67e6ee0cdbfa417f7d30c50711e098c6aa0337382f5b7921378725f9ea5d50af0f7fcc60fa76a23229978ed6391244f325ddfb18c402ea707204	1	0	\\x000000010000000000800003b9148c1d0d8c951be69954283efe92abfdcc7ab292349d2b4f7660fa047338c1f75650a9d958d6533c786f184c9a9c0a7cae8ece10c456dbc93a65b338c8a41cdfe9180942a9110027d4add89f5866b0c856b459aac68a78e0cabaf8e09e94435a487f6b2c2f5ac579c2898c6642f397a1914bf46cc5a9068c004e63f64e6983010001	\\xc02d2503c463fcb6f2292ab5cbc80e510bf6c4378ebb7ee383d563aa37de2a8ac9b67057780cb39b1b3c10e6c5e08de2f8583a1e77b72e023f9cfeb0a75bc00f	1672139891000000	1672744691000000	1735816691000000	1830424691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x50b89f77605e94f33a7e3ed505ca5d4a13c68c3cef33da27b4a882a5f84f641b7877a77b0077dcc216a189ac3ed6c60b952547311d8416392784406319298072	1	0	\\x000000010000000000800003c5ccb0df7c1f46605d4d1ccbca407f8d3ca224b41908b5e6d48341f07aed81e5d381f0f46315996e8a2bf04bfb5a02be2ef248f33b6e755fd30771264e667371f0f48a056bc0526f7f64025669db90383497f55b1487840802d06bc7a310549f125d93e5c86bdeff15af6f7df53a85d84cb500341a299eedda9a08b5611a8f27010001	\\x94973a4dde7aed033682e223ced14bc7c9206c16c7511281ddb4bf7406d2137e840642a0a93995b4953e5e6b9dc5e1f6970be293a9964795c7c855d9467a250f	1685438891000000	1686043691000000	1749115691000000	1843723691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x56887e85f3c0f20da12ee4d02e31f7c706f4357f796af077520dc61d7c8c8025c53446bfed2f605b6b185e7e0df179c8fdd9d4dbfc88835245783a9f263aa21e	1	0	\\x000000010000000000800003b217db6d90e5ac68deab73b45d6c784c5c64f1a41deea1e5a6a3a0f4efa836fc1de6cc9559d522592d226a03839dd58c188306f533f9295022a38d677070f0be3183070121c195a977ed89914114760aa28e18b8dca3dd509f611d5b834dcddcefda690114036cb4e9ac613aaba869ab483a4bb0a931438ce3c154d8de2f1243010001	\\x2117f51c05684c6c2d35aadc4d4c8d7f4a9dad3946e6eb5c011d86a68c863590dec0c6a5b2b11fb4d12d153b2d54fd0ab35b4ace5a8b75382811f1c747cbdd0e	1689065891000000	1689670691000000	1752742691000000	1847350691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x58942b93cf0ea2e0fc471274be95179fb91f658d980f9e00ad699d4a2c473af6acf33b9fa1588177745f5db94dd17d3997fb2712898a67812263e3655e076ea2	1	0	\\x000000010000000000800003b903e532565c2c084202c3525bb5bb6789705185cf2e2c79e19b5a2b53b0e7c4175423c80ab3e38fa4e9e27b5c186ddd76e94ec6eb82ff4f98ea1c6a409d8a4c581cf6febf23d0ecb573d692d5f3abf2f74ae769c23ddb741537ca249ec78f34307b2d69b30ba7e79632075818e0de28a3f9fbd7264767a6a488307794be00b1010001	\\x3a4d1f813422d58a14ddc8431c93838e007c081b76008397129ba7ae79e811fe300cab51f2720e92a52dccd1fd7dfab5ec2e454ee6272ba4e343a0beb0e17809	1685438891000000	1686043691000000	1749115691000000	1843723691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x5b946ebf5bb8550bfe0e7442fbba2fb651d980cf856ca4d297658ff9fb4a3dbc06101850324988e1f52c5e21f75b076bc60ecdcf67530e310826770de17e25c2	1	0	\\x000000010000000000800003b913c6e9349ebbc7d1047db2f1eb15cd50bfdcb5370d9816b06922c2b9beeba9775e30e6369184830f9dfb5d8b9c8852a03a5f341b3f31665a67a8a86a09690d4f11b683db6212fb080506175c6aa1286992daf3a238bc1f49c7882413b04eb75af971f599ce8833638bcd5e4ddb3a57099b52eab107d53bff6da9211378b1e5010001	\\x9c540b5786445d1c5a41b0b1fbd0db3858c9f0e4f52c4e6f6c36ca1bb397f9fd8ea93d46cca5085a68193491da4734e726b6de81d3fd6792f6e461995416d10d	1661863391000000	1662468191000000	1725540191000000	1820148191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
41	\\x5cc8c1cab751dd60ee040745482cb3635f858158f86aa69682a54b64c18b2bbd43b792dbd8aa08114eb89378325ef455ef6e387bcc627cd7f49140e7deb45a85	1	0	\\x000000010000000000800003e3c670f5786cf696d3b379ad25da23c1ae70248b013ebc848608ac14cd10f611c3c40d8bfc332417b99a13f8e11d6a3704eafba172a27d4584202a3065901c0ba628062f032e31034da0ea9d43b81373aa0d712eb811487e86ed39976c23230a51a820feed1b809c88dd72bdb4598d826f11a12c6be105ef8bdcce14df86dd93010001	\\x9d6e964d79d1c4733d9229d87abc7dce31d5a2e6a69f6b472ea0d86ab9971fab0842183ec27c3a10ce9c03d492a5927a12d42319a1215936c99c1b551015dc0e	1684834391000000	1685439191000000	1748511191000000	1843119191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x5c584a452bbc40c54342f80663b4ce974c03f676e07f8fc920dd75cc70d1e6087e864f61a522b16c70068785268ece1033ee718da366873839f50d4833726f59	1	0	\\x000000010000000000800003ab7301eb4e807ce3981282d53e9f5df63763673570feabcf9fada8c3c907e0543aaf870661f8ed338fbde98aa73fa05132826b53f742e84239d16d93f8abce160c415326720fbd1557287620b791ec4cc1b880666eb4714cf4dc23f707acd5a7dc58aec65c0cad8d31d77d6d14fc9d1b86a2960737a0cfeb986c771ca508cf77010001	\\x488d0bf6d67735a6138511a2df27a4e65d9a3518adbd920a7e9faa1189a7b7ac8f946f90d4515422000439d0cc7cc8a04d96a8f74fdcd29191fcc95f32cccf0b	1668512891000000	1669117691000000	1732189691000000	1826797691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x5e4466a54d9b1a2e60a3ba00f3269dbb5f1257220be1d1995d6c0a7890026137a36c251702c564507f2dfa4c5cf566f7261e5b7e664a98fe50079499c70c6611	1	0	\\x000000010000000000800003b69e042baa14f6e1ac30ae776a3816970af843e4b87f7fa9283d88540a7070c8c0394c16c3a99e6f002a39c1ef53160a26b5f907cd121cc2e8aba2a0b4e36a612dae6fc70030590f7cd071e76ae58d7bf2750d2a6f5aff4645e4d63adb8a9b05490f2ab45afa674ca6610cfdb26a4fe8b4cd5e0201ba769c83a3b7c69f5a754f010001	\\x8d60b8c5811a5279016bf54d15163f11b2e68ef74c32ed1144dc3414b8a3d4850b73be917c581683f60008831b7a515b9aee0bea0d65d914d46aed3c9734af0e	1683625391000000	1684230191000000	1747302191000000	1841910191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
44	\\x61e47c662bb861fe7bbb970b5379c1eb6bd77950f859045b1a1445f0df6e258470df58235defe12027d741edc27b58a8fedf3ae077c092b08c8867cf699f68a4	1	0	\\x000000010000000000800003de9e04cd8f8b1d9557656ae045dc8ca3dba25956b177fd364a8a11ec110055cd544f6784fa64f6e7868744916f349df3090bc4a5469a381dcbcf4763c5d4a10c70d72d07c3825aa111d5f06339223ce11fef65daabf8e1b206bc02cc0ac875b8c5c0d2185be434af891d50624679398860200ef5694e18b4ddea6fbf9a86a561010001	\\x6880f2dd3a851701942961e8a29bb2a5f8a470dd40cef28863789cdead2018110117ec13d18fdab14a966c6d5eec1dfaf5877f48c915036212f2b6c8f0154507	1664281391000000	1664886191000000	1727958191000000	1822566191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
45	\\x65e4cfcac1aa2a7522f0af644c2f1bfef4d476b1ba997cd5c5901229d57844ba9a88967573196cb98304608c9505f30f8267671cce09d84611446d361dbeca5d	1	0	\\x000000010000000000800003beb85b84ea8dc12db45620735dfe2480924b63ce54eee37eaa129d6ce846da09426a773d139f455e039814685b11c1786bdfdf0b3586ed35c91d220a280bbd28f4e8afbb7edd0286bc2175547fe3344e7cbb4106d8208134526d98eacf14da7ae87b18fd3784902f0ed2a5f6f6a4cf1768cc51b2497fdbd884a8663e304b2d7f010001	\\x954bdfa7ce63181a36acb4c5f75112d6dd757b8b5be28058ce117765040436aad65df8f755b3c02e0ab8c9bf95ceba1fc4a570146123c990be4a403e28282f0a	1689670391000000	1690275191000000	1753347191000000	1847955191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x66105ae0574dc88c5d46a72b0feffdd907a78fee1a279a34ea4a20d25a4f532d1e59a4f69363535f9dd05e1f61ed5d26c9b1ec8f1b6bf0537c01d02d7bf7e07e	1	0	\\x000000010000000000800003b1cd73bf5aa4e92f50d2536ceb0467ebc0c5a0349ca1fe96867f28f7a57b910783c9385ab3f4fc5e2608702ecb2c3dabd54374dc606b91a7d4a084470bd9b0adfb4bf9db46f3cd7cc86a9bea57284041d494ec9aa63769043fd4806a46690721214e721d0ce6e8d2529fdbaad10875af11f13d0d9bc0e144e7faa667cffcbe07010001	\\xae5f3a91c4b976fdf825ca59c9eff4e7eeffb42854f89ba6f0707247d1755572426c5693aa7dd586dc04a61af179057e0b05963ebe6b8f41917f812b4f3e640d	1663072391000000	1663677191000000	1726749191000000	1821357191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x661c556f32dd9ae43d45c72c0728e4d60929137974e50e885f551bfb9e3c3e0095d84dd91fb957636d036f285506e58bdd03f03d3118d34502557deea0c21669	1	0	\\x000000010000000000800003aefe84200bae8f69fe3bd3acc8f2957c684b8d1de56f33049d4947053d2f1f7905670e417027c7f804fecbf96c3fa579a48f7d00a16be979e0bf53b43d3cf1f2346bfe4fb51e9e8c5bbf4d0ce918098f2d2c953dffae9da5a3f235635a82b71f9c7889c5ee40dc2a03b9073a9423bd9eb84d2050d3487712e16fdd55f5b3ac75010001	\\x22c8d2a97ab11e98556536d40167765e0b14ecb43f22936032bba7eed2dc329feaca4cf1a24feebe64e645972b6061585a77f895357861c3fe09bf2f496e5009	1680602891000000	1681207691000000	1744279691000000	1838887691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x6790ed924da42b121dcaf5c402e5cd2e06c29d94ca56f3ac17b33e03f4ef5a52f1a56f338f3f660749d928a0155a9fc88f78ed3019e54d600707ccdef9a1e57f	1	0	\\x000000010000000000800003c03785fb16745453ebe8f51185805f162ef9adc44ebcb28c174055a8e3f929f2ca4757a72f8818c920bf01503c119595d56c9337da87af864246bdeb3d0afda6bac3a5a8ffa4d90819bc6669e14d36b0ac6767f762675edbd1c62ab4e03c30f3e1d680cbc727bc310890fdb45e9256f90f6b01cd7f6355ebd7150024e009c911010001	\\x4043348e711025f764fa934dd574494c57523018f3566774e4b5ab33bcaead8faeee0c2ac6cca7dfed82bb98944ec7c45753e93a3ab816908927aac6c61aed08	1668512891000000	1669117691000000	1732189691000000	1826797691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x6998192b3ae4c840292ede029cdf98584a96e3e567890dab5efa4eec5359296a6f69412090810b92bd2a26da1f08c05cef3c571df289e86877ae446fbfbf3f20	1	0	\\x000000010000000000800003d640d43f0c25254249b5eee9dd52cab739548c3ba4e96889a5ff1356ffbd4a20fe6c5d388ed5b507cff33946b2f9c2703d7e9e7f263a261959da4f7dad1c1655d9d990df1c2b416de3923d42652013246496febbe67f89548e6de5bc67082396adf5856c21722af7c3e45bacb4effc19cca058c832a3c10c8540bfcc4191eacf010001	\\x6888898ba8bab5d12a6a75278af5aab4c99cb3fb5eb7ad4e34cd1f1382d203966518c8aa2663d8bfa8ae4e45900a81730d20c98c872889c4244ca295fc6d5106	1687856891000000	1688461691000000	1751533691000000	1846141691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x71d425a67a1ce2cb780ce95767226a27f5d41ddd0d2e4be13ddb66ca24ecf0c99cd0f55efcb2e5764a292d408f1ca4a4f05ecc555f0f693d478f808465a1270f	1	0	\\x000000010000000000800003a05e2fe5b53c851ef82f90fa631a5b58bedb574d70fb9137376dbef55a2049d1b3ab5404d2f36ef5a7100259070c5e55fbea3cd0aa8fd6d2331f41035da7827cde821908cae2b401924e200bc78f4f2df0a0378d09357c00e2d175b80aa9611be2d70f5b74d3255d1d61c6cf87bc3ab690b852dab00ffb66dbe78053ee573e23010001	\\x684e9280a200ada9d928e27bc6fdc44daa2bf749db319f835d47c72448537ef275ca14056cab9c7dc1088fa1ba351578422be80263554a068256b5fc506cc00a	1669721891000000	1670326691000000	1733398691000000	1828006691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
51	\\x7290a549a0048c28b93f262ea87b116d0dd54c007fffdaceb905003a8de8c8fa76a3e6deddcd08188f813d2f57352625ded57ebc395d07f9a0e64b385b5a2d45	1	0	\\x000000010000000000800003c9932bdf760c65e20249b480a6aeac4750c65bfd0a540ab570438208d8d5142008031bfa633fec20caad8764390aab35b59d5f6d0d8d57e3f60d29143b1fcd1d469329f5e3a1bc361d0a48875f3b39786b339f138588961aa7302057c557dd2ca10f13abcfb9a1a87a5505c87efe7f9abff9843e6dd109049b57ef4dff50f11d010001	\\xce3fa76cb88df206eb06682e64f022331bc3a8d528dfc62503633c6511ae897152d4e6fafbc1dd6d7098ce19298dc75baa497b765ce1ede878d730061d31d901	1679393891000000	1679998691000000	1743070691000000	1837678691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
52	\\x757ce694b3e56c9f40d622837f59b2b621c601dd92962e28fd9bf52c1345c9d18601bddd66aae890490dae1eca10c89e7b9f6615c52f8f8002dac6341fe0793f	1	0	\\x000000010000000000800003c7716450ebaa73caf76777346b29260c8ba976b65b572167aa39bc6ed3527ca926606d329f7ec2524909b0cbece2ba7c7e8faa4872cadff493ecfc21153dc043318dbde12681214e86a64564215bb170ce8441f21d3fef12c02a475412c9c149350651aa0aac45691ec8caefaab618f34b472ccc131115023cf158f9f6ea61ef010001	\\xcd751464f426bc6a7baa70dff7bd6399ca2c8d1d6bb25e0b2ff79cd89a7d2d4f922ae7e83501f793ae684076da3d80654b25830a5db9c9d8cab7025f88aa130e	1667303891000000	1667908691000000	1730980691000000	1825588691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x77bc00edb0fe4dcd6b0c83b81a71264b589b37bb6262b9f69d66292fe636d6636757a3c47610391b1e60398eb9f1869f83afaed6c4a392b4749e8cb703633ff5	1	0	\\x000000010000000000800003bc53adc8f8f46e8ac55029037f746a1c423180f3daa5bfe1efd696c7707570d3b2a0969407436c79aa40b3e027a1c0cf00e01971362cffb6df6ffa82a378ed7a2b5cd2eacd7e43a5c933e1cb6d88fa4f0acb773b4cf037221fa25db4352a35fc042c68999ee6442da365778bd34d8b9f875fe70c14fd6f0ed52f9a335ee7066d010001	\\xec32b0f18de589a946ba3d76484f55723dffacf6ee765ab827a230c43d56cbc4aa2b3da791a9847ea46254face5f9fd2946ef0ef845ede011a103ef1205f650e	1687252391000000	1687857191000000	1750929191000000	1845537191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x7788ab8d12381ac54888f054ae0bad4545b21052968b6e3a79e913aadf8f1abb6c21e05f8b64749922eba42754bb8543e25e17d700a73d9a589c675b258d5526	1	0	\\x000000010000000000800003a5d601b447af288afb60f0c1a0b3ed8d42c0a410587da2b04edf89453e572a7060dcf98f881826e7c9df746f3725aedc211986b1aee08145cd5fbc5f9a6d89a51b0d797e8f6dd0c5111da3cafd2355c70158f43ffc95b65b3c19807ad8dd0dbf7e7a6a0694acc02678d40a49888664e77eac0c91f02cd91ed4b127b1a6c4210f010001	\\xaf2a03475551d941b9012739e3704051402eba8c58bda7e93a47ef5ddb334880a414b1643f3fbf3c93a245f428e263ea41b4137e05b651a55fd0d57c304efd0f	1677580391000000	1678185191000000	1741257191000000	1835865191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x7784efa07de5fd63dd2c0595d6c8f49111b42cedf473865e8f2c60b19309f134f28dd643b4b339ccf59c2ab5bfaf69b71535ef576883a3556db5340d03bd040c	1	0	\\x000000010000000000800003c13e9bf2601e45a8e185d17f0ca4968d31622a2c79c116d549b8fbcb9d4e8fc8ab68586cb97c880171239a72e12ac9c106cbaa554f3c6f72d32c072cd0d2d6db000c11bc939cc55220db6ff178dfb59c243bd1d9f4a76fb5f00ac9a66bdcaac9b67140e149919b52cb91c1926d1c5fe48138cccf83871c6223e14af80b0478d5010001	\\x505fff58b0b83f602dc47fe637cb082065f3bb9373ab1408bf42e3eac266c0464ff1c5be2defc4abe89f684cd07a21b5f2b206ed769ad1f4a236f16efaa2430a	1683625391000000	1684230191000000	1747302191000000	1841910191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
56	\\x78c8cb5fb9318f4ebd94861ed8dae1bfccc4344f4717661abb68fe8b2820ac6108222523b2e22b2c23d5328c1361f50bdb35598675f34ae165d2d81c162847f7	1	0	\\x000000010000000000800003c29c35d0a8e539bb809fbee6aa19b5050a801e2ed84f9d314a54dcf6df56dad6b56e8ecf3412485569c5fa274984ad61d9183d500aa68e3c381fe984571d2db488707fdabc935c3f3d640d9cb1f700bbeac6d5d02548b7a531f1bd52e21887d38766a4a27bbbaf7100b2cb04eaf46755e193e327bf04a9c53883ded11923de0f010001	\\xa78111b3060b139ce6a0d39e227c145787d887bda4d7b8a9513d2f095ebc33bdd3a9fa23e29e7a801480aef127211343b1d0fdf6e9bd827d78b2178832ee5b04	1680602891000000	1681207691000000	1744279691000000	1838887691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x78a8063887ee3ff3a8690f10ac5f35d46f6f43a2c9ba6968243cdaf9aea60718d7bfc3c224533a7240d4d3c2bf15c6c73a692c1bcd7de826cbbdc60885c4e289	1	0	\\x000000010000000000800003aac4c23f5e6b1e6908e6be356bda9f25ba248dce2090231b74db805e2027633b9a853d990dd8864b0c600d8d12ae1e12a5494c039b80d5a3fc84bd6202b3ce1c48e912152c08cd3f2987ef356a7b7d040006cb18498be76d95dae88b536e66dd626623730b77a3f98162c3e0f9e4412776baecf2bf3e0c61833504637f742e63010001	\\xefce6a163d1c463f71410c9adb50c79a545f22f301ff7e35fdae1c6f22e1d2f1fe27a483152e111b2788830e64b116133ccf8b3e3255c55cca00fb09770c5706	1672744391000000	1673349191000000	1736421191000000	1831029191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x78ec4ed0dbbdd3dceaf166b05cc4bbca41ab77926c3a99c9cce5cadb661a60c331610d5500a605377053aaa6c313c8d522a1798ac27dd5ea7787aaabff51a416	1	0	\\x000000010000000000800003999ed24a4fc1c7dc2f79a275021fef344b663d6796bbbde97c4a90414d824cd68baccf981d17dc1420c6f84b423bf39d5f9d486c4ec282b95a0b4e50fa5c65d52b78d687e74abef7f5e4fd51f5dd91f6d80a592f12fd1cff5b1de4ac2a51df1ec3ae2ce7cd37b0e9e8991bda7e3b5f442cb22c1b41afcb155237130d4694fae5010001	\\x10dafff72eb4e9dc010b69233cd85426e655bd1e2bf7f9750dc5e82e494535ff6ba8b07913af7fbe01fc1d1028685175b3c17f968e3f29fdbd1a3fcd9aeda200	1672139891000000	1672744691000000	1735816691000000	1830424691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\x784cd2caeb801c1169749d89deb9788f822f893012b938af3c2494ef627cba60d2d699994c221f27225f1461ec898bf27bcb214f402d36647f387bf7fad4547c	1	0	\\x000000010000000000800003cc466aeaa5c6aa7a5d9390974aa7c81cc670f31a4da0ae6512bbfc3715e364b2f7d36c9bb5b61ef07d4039b5e5745518b4a5e4eb524e7231dde228e6869f9876bc68f67e5ceda8fec2a9534cafba7ccf841345d66c0497e4453869b70b3f8558d9be4abdbd25833648509faa307f96c57a631ca1d3aaa5552e9a23bae367a09d010001	\\xcb6f0a437e74a7f296f911353253ba9c1141e68fff7ec081ce25cdbe43c60ebdd6b2d88be4fc101ae0bcf37962ed1ea74372b28c98df099f6093907ec65e4a01	1687856891000000	1688461691000000	1751533691000000	1846141691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x791c5de2114606269fedbc9cb3f5c74fdbcdcc6e64b4845343ace071f9617d0c3b3ed75611571c96ee94c5ac52d4440c2c1062eeef5c5803f0f77271de460be8	1	0	\\x000000010000000000800003dae774316b153d7bc555b8ad6821fca4fb0af87596f5027af00190ac60cd13061d2fe54421e8e593d6edc59163ff3cdafdb29157283009f6a42a6703a259133fdcd7cb395754b7e45e470940444e29234bc1d476232a6538f15bd92bc3818eb4a795ab75167d6777e96896067ffc3eee37ed847028baa40991239de39dc2c3eb010001	\\x5a64d007608c624fb5ddc06da4f5d78769612415bb9f84ca4565c846e9267cead654a0b6f2cd8adc9203080bf475c257e68c8b12966ec3661ae5adbb5d6fe009	1690879391000000	1691484191000000	1754556191000000	1849164191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x7cdcfeae262a20e81e2b37bd1bee6deb6ef312eb8c3e5b60413617738f1ad214cf1948889fb20866a3e2dd28168130fff226c86398da9514c86929353d58c49b	1	0	\\x000000010000000000800003b47ebab6702b79282afb5526ed789cc02939cfa421750acf7e18893c3a4685ce13b58b3955414ad62802c79077ecf4b942707fb0d8ef94df3f5ef5816f4cf860c91fed83836afc42468334d7d34da873f2099910b658425722c23875c7847317bb6cf0425214ee5171e885aee61e5052beebb4792b4714772b3c30e415652637010001	\\xee24568da4243b3e7d92dd6979e73dae371e378d99bb250a72e7fafc370d943ad696f4ac673c4afef9f56e6c491b39d2cca9d9fa67b4c42d34da0147bdd3450c	1684229891000000	1684834691000000	1747906691000000	1842514691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x7c0c5fc8afa4885f3d9f1e5da8efddb50644e4a53f2acd09e3cdb157d431cbe02b1bf8ca976605f1ccd1d1e0e95f65cba1812ba8f16a37b4fc62002c54afa796	1	0	\\x000000010000000000800003e64e22fdfa3ef08a8549901605ac99113a793035b73975ec20680cbb0227b914f165ed27e3cca85be49afa2d07a0df4ece51d07b8e01821decf04b58b97bef4dc9e8476a74cb74cd5996c2c8650bafac5f8a3c35f528d7b85c0ad736442078d14d583d9b98064316acb60f8d89745dc227de3a1f401b3cf22cc59295b57d03af010001	\\xe7432051eb15bcd548933f4b6224cd461a2214bbdc28a660a7795fba7b98553d326dd5bac69479c15d742b26cc67ce9a78522491c56240332c022a3af6e91703	1690274891000000	1690879691000000	1753951691000000	1848559691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x7e0c159a04b44f522abe8f90520de2fe9f3e6bb84a196553cb6ea168703f989c180b3f0b9d8e35aaf5ebb4262a4d9cf6293a3c8efb593765e6acde5735944694	1	0	\\x000000010000000000800003ed828563bb1a3d90163575362777c25ee5b8c8885312912caa99ebc15182e3f10f9c252386780f1c86af1a8e16ded1d4103cd79bcbf062bbbe5b5e35dc954f49e3e9d9922b6f2f7a2f279e135de119bfb8430921e67dc7df624b4589ac45cf791479135d0e24fae1261a79ed1e3ff6aa5aecbd22244d2fa58886f17d88568941010001	\\x620f1cc02ca417d9e697aa9239db3e3b1beba1651b3b51224fd0f3389d5d722e5020ac03f8a060ba61c04cb873cb418f7993772305ba8b68b711078c5ebf1e0a	1674557891000000	1675162691000000	1738234691000000	1832842691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x7edca4caf9254bc6a5a1330dac9c52bda8341686a7a5fa64c4a894b59ee9419c93ef2f3fad9cefda5d4a57a44dee10a5ef079e9cec3c5ed90e8813d32c35dffb	1	0	\\x000000010000000000800003b9166644e2b9bf52046bf94b37831b1d62b15a81c71f29365c41a843986d524c730dbded0500bd59ad1fa8d90a33faf4d73367611348018f1ae06900d34be9a2d8a7a7c4b9975e6eae600a384f2147d8bb87a0bca4c98e7c8eace7f4c0ba1de8ebb9bdddf6df7e48e1994287d702a14547d67714b49f1ca7a8926ea27c2da59d010001	\\xd4025c87546b76aed896afd8219ac9bf13f120b85829bfd58806486675345056fb0976203de358e63383bcd80f336bb63d12295718e4743067f1a831a9d74303	1675766891000000	1676371691000000	1739443691000000	1834051691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\x82a03ed62ca743ead5b4f1ecac9e92524092a13c324abff3aeab209fa2c27b0d98ca6966a295bca2960f11efad8ebb1b776e4e011b5a345cebd3ae68ac77b707	1	0	\\x000000010000000000800003d707490020e4d7f75908e773c3b94a95e90b09a1a646915fe63eb62973691b1fd5006edc9648bbfafa9bbef34f84610dd50df6e01d4936c2f9a943d6cfd06ea1bc26b4a74f69b377fa3bfa4fb5fbb9e24b596d81f837cb16fa18ea08efad9629beb4bc1ac2f5045cde9a0eb329d9f53097d4cc78181557cf0ca08d2b27f12961010001	\\xd073cc0c478576f9f430fc9ca268f59b2e95a8eb54999f470a924c0af68b760324d3fc14404f9030b9097218a4bf80aef09f5cb4f1a0d805ecfc13588d9d5802	1661258891000000	1661863691000000	1724935691000000	1819543691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x83e00d8a2edc4a8630e189a31f8e4d2c87a1efd7e15ed77b84a993ea00a867a2cca995da6bb4d228609d4aa7c1e9258f520da51217bf9b323e300c5333ac288d	1	0	\\x000000010000000000800003d2cd2dbe3e78cfcef0d7949564116afa48e543c86e6add3d31bfc3a05d0113d298dbf39b6229a71ff70c55584d8c3c38bb5402eaceb76010487725204d955038e9b4bfb4efed58d550dad3b61809ea9bb478b054870c7c3d32ca74608b8813d9f77b345ecb275284f69c1c4065479535a7e7ef00165a8efdd742ffa9390ba749010001	\\x736c46e6ea9712115f455fdfa2872bb57f96384decda3810b5821e28f624dc28a9667881e35054babc960e066e01c6c35556c9615e13b77775a5c922f3dcf103	1685438891000000	1686043691000000	1749115691000000	1843723691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x830c3d8dae70765d8ffaad8bfb13c4557f4bb9c9f08c4cc7e77fe84201aed2329e635644450923910a6bf3c6b0cf2fba20917ddf77b947995e2822b23e1b09e8	1	0	\\x000000010000000000800003ca25b5201f4cc376970e45010299fb34ed55f880fd9221b27f718e7e5290ab1809a0e20c3f41e2f72473bb67751de37a41b852b7568dad558bf973e605a3c50dde02d257af139f815b15ade699c4377436a2c4dbb1f5ee8a26422715358339eb4cf59f2c4319d706b5ac20d60cb61e0c278951e2c17ecac1592572798e4ff7cf010001	\\x7c7f3efb7c6f50c3ab11993207e8c921425dfce927010fda1f6b02b732cca7d9901fc6cfd3f0083ecb49d25cbe1a3f807f3d73b84b433a0deb1fa004f9a4890f	1679393891000000	1679998691000000	1743070691000000	1837678691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x8550276aeddb1e53f5b529308e076c638df139536cd02a0e1eda3aebc263c79597ade6cd77482c05f038b3c7138ca0364c6e8e83a9c86d31192835302eb00574	1	0	\\x000000010000000000800003b2cea5bbbd48cddc24455a284bb9bc231593544e596b1d804f42d501bd6cbd414036bb7fac439da6490f6ed28963b8fbcbef808eaaee652c40bd75fefac6a0ff7702d50965b20de18da4d85b88c3762e85eae5262136d85f4b664e5d38b0b76e9c2fd3001b980b9f284d9a5c93cc2187a5d5b7ebaf4e3d914edf4e20241d0ebd010001	\\xb7c8b12a64bdcb1217e8cdebdb10d33f7b77970b377e735019b6f5c21bd98773021b8283c7518bd82494ce1837069533be627f1ca72db4a220713a0fd5aaa50e	1686043391000000	1686648191000000	1749720191000000	1844328191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\x85a88fff0dc7a67a0ad19bba04152bdbecccd22eb1e73819ed4a7d0462f686a70efecc651eb182657f0a8475b8b78b70a678e8a074b1797baaa1483d8f54d25a	1	0	\\x000000010000000000800003f5b7b4b03ebe2ab0c37d324b5ede2967c46fa627a780018c71f3e7af5ee08891c7a5dc70a90bfeb30c7244aee7407dcdaaf8fa055b86de628065243c3f81c139e635d0251722ba96ab71fa3513ee8a95aa2267a98b5948d0ad0e927ae7d04bb89f8a3936279004579ce38257d26fe2da539595fb4478522583b85164de866e15010001	\\x3b25570fded382f83c6dc2fa094431772dfae031e1833c33e7d8490c152d28056ee562f6450c2eb6079b5b9eb9ded63a954d6eeaa9d738d4e37d1cf1a3a1c808	1681207391000000	1681812191000000	1744884191000000	1839492191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
70	\\x8c74b55bb6f50ef7130a2d2ac68980a1b2de324244fe1888a36374203956d5f1b42384877706e750b9cfdfb64cd0c3702259edbc90423c26f08f1185deb2eaa4	1	0	\\x000000010000000000800003e23e39d32ab6ca426beaafd086474a49a44c72e4e6a62a588a2c0a563c34e5d085bd2d21abc0968eb88927b6c1da4688ddea26c665874aab13c544d393d227bfd47d200d521ab938f2a388f4eed2897e6266ea0e2f8a1aee4ad1033bc2a3acc9b9277a30620dc0ff1dea836e91483a7f30e85c4636c2deef8808fb93ff3b485b010001	\\x675fe9a78a6772182acf0154bebcf963e93ea0cf7956bd59ccda82fc48716c5182424a2900b5477fa764dfb00608346cc9d2fcffe8eae2fb1afdb7d9442b0201	1683020891000000	1683625691000000	1746697691000000	1841305691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
71	\\x8eacfe085c73acb6b99ed17e45f1eade517025980ee7f15c1a8b7e1a7b1b1c9af9d034bf9ceb28b7124a483451b3231271ddd4b066c8c9754a3176e94009c49c	1	0	\\x000000010000000000800003b8c2c6dbc7a38f867d4ada6bc2eb4b042d3cc1f69e4cbe027c974ff36509e7c0f986d915018e082bce2ad02ad8e8afdb00f13e6958990e3dc30c5ae7ce3bc8445e3f200d3c56f7238b71924ed0774a8c8759a48047139d558aa7efd6d1c7308a9d2fdfd9d2faa6700e851475a533e17727f47e7eb039672112d1e1dbcfed83c7010001	\\x7c174d6f7994c42dca6b28242919dd85d449da4b09a9e526b1729bf6aa71d830b1114890c2f7f2481727f2c271043af40488e1d9b13b19d8b99e0d9e32f15205	1676975891000000	1677580691000000	1740652691000000	1835260691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\x91504cf08f29e2cd1410573dfe18bf52fecd170d1d4de37fc1788fe10c8864bcdbb69f747f98d1f027c461dbdd0b374042f2646121a52690c0181ed65d9b7489	1	0	\\x000000010000000000800003c732ddbe1d9b73918379dbd87cbfe931f0a1e1f401a596e37c36c8917129f5dc90a3bd39ab851225f716c57bf37b904c9c7c7c0a9c93781ff634067b8b4dd0ab3771b0aac9325a89d00b7f274e244b72e9402b4e2670ac985bdc3b59e0c5c3236d1132ea0de46fb284298f38ea268dc09da4f596cc12896df4d7e7ff41a26415010001	\\x7613acc577d5220ef313f60ebe8dfa42a7c4c2e8d6812d5189cd47465e23db76442d49f810923e4072cab83c05fc1fdc7762f118e4719f4050812a378153910d	1689670391000000	1690275191000000	1753347191000000	1847955191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
73	\\x9260051dc17c77a268540f0143cd3c1549190db7c489cb184d99dd4b6b632e10f99fadd5a4a36d346e0c92afcc21023e5eb97ed170f45002b1f88abe463ef217	1	0	\\x000000010000000000800003ceaeade4ca411fe472b97cdad85cb597f729d1151f3c82f95613627ae4227202e514128959dc3b11a6e54a463a7e9d2e153eb99de8a63c64a994c75099163bb569793090f451f8cc5aac9448008480825902ae9d43c1e7150c5a384b0ac38c1d8cd8403d2898b6772977ac7dc82de2be2535dbbc1216efe7552453a413bfeb27010001	\\x65eb6b92c8538f045144803b0cbdede517fa21ef793b00464c7af2f9306348b3d438c71dbab002f6fcdaecb78dbe95fb0b418cc6ba77fbb3daa3059bd9cc8302	1682416391000000	1683021191000000	1746093191000000	1840701191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\x9a44e2bd8191ecd44665b2cc545e0d40867c042cfd72a85e5c29bdee1488810e8d5e1575cbc88dc775a27d7fa3c8007dbb84f66aca9c4c4b10862b9f85ce4c50	1	0	\\x000000010000000000800003cc941a2613adb4f0cea3f88da93dfabea533a17eef91c0bc99499436be8752d632d657960f43fa0638c0aa776660450a4618a614788cfa1369970fee8ecf8c5b96ab1a4434a7973ea1173d597dbf68d97c6fa403872a6fb92dab8e0b248775f2ca5a9439cf9c2a7ba75661ab00b70b0517bcb911ac50c6a135ef47dfb6ec86e3010001	\\x455b856ded3a9088c04d5c8f739f23d988cdaf83f349de192108ef6c5512319923736d3254fa5819ceecd3ab08cad1355b6cc779db24faf97065636846926b03	1665490391000000	1666095191000000	1729167191000000	1823775191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
75	\\x9b7ce2264013c3a2a5625ab7747389008e9660783f3e7ce82108552afb34b98ea278ec7792459ef37e8c18ee405371967cde0996f4e6cc5251216d21869174cc	1	0	\\x000000010000000000800003cfab54aaebc296f9d20cd40ce0145c39dc0095108aa0c8ea87a7dba9a56d98989c55c837b9592ac346cc6bd2ea58243e4320faffe8b320a07e2b39fdc237964d9cdc8d5b1ee7aa6e22d6d579ec1f59cd1f88fdecc2dcc9a54ed44bde3cd1c216ac228b1773ad26b89d403408bbec9d06f375fb222a254941986f9c406f97a007010001	\\x6f070035a431a6a543dae055e0f16e8a8c15240df0d63f20626deb745a42e1cd70aaccb082e91f85fda019b0751830fc68cf2cb3efec7937e470f55d574a2501	1683020891000000	1683625691000000	1746697691000000	1841305691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\x9c14749c4cda29a1be3d00c0efe5f84d01c0c1858eed6a958344185e9906a0f698a359e658f7fea2ef730bf07eafbb850e9e94dcd62f4135cf3c51c32c0350ee	1	0	\\x000000010000000000800003bbff7ec53941b0020ed4eaf6dccd33f351c15362c3719aa535fa90e975548696e1e023e9a39f72710172aaa5bb0b62b8d08a5300dd692e84fefeba08f09dc14025350efc1ee0011fac4809ac933195153295c1c832a45f87a0e623e71ccbfdd88a6f577b4935fdbbe3a71f3fff0a442e2635504fe61132bee0817586ef32e077010001	\\x0af7a31fabf924d71fe695e4df403f411a1b8ff57c3cbe00e4d46a147a7ecefa7354bf3d75dc3b300140737126fb6dd470e98c536d1b3ea7e0af186b57935802	1667908391000000	1668513191000000	1731585191000000	1826193191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\x9de46ce3389fa91a2e9493c1006dc8e05db807df42dc806aaa639169ca7bdd4699019c03e30a19304878328cdaeef8536727b3658d635a4e93e8349824643e7f	1	0	\\x000000010000000000800003e9bc78a6013f483e1c8f4ebc8375f0ec46c4ea2875a41736c8fef125473546d1b62e973d145a8af6cec0949bb198f55c1581bb79cd1364c204bb82b2bab63c3a4faf0d8378c1d7447c84ae22822536dbc6eb2a531578b583dfc52c9e5333046032e50cdf1e9b6ba4d37e8e933452ab6ccd38fcea3b6d6441daee485742806151010001	\\xd8980c2d092e76f79a3a2fd1937f57cae06b3053dbabedca1a6ec62ffd25f53ef1a992870c0b2eb81b2c056d1ad46580cfa2d87f207bda5f80b94be93d15c50c	1690274891000000	1690879691000000	1753951691000000	1848559691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\x9de00556416b289e4cc9d36de44ea8d8e3fee7c253087fd2953c6f36ac1e8cfb028e6cb27edbce4896d7f2b406b642d60f67628e419d7ca6b49df29bf2360309	1	0	\\x000000010000000000800003c218bc90bff0182fbb26fbc843069daaf62a9a20766b3d78346c61b42fc72923f9567e5449e5f9f039a00920ffb0553ce4232975d096d88bf8ab2303c863ac13dc1a5554a9f9023ff06e9c83be0741d9f9fc732532019458ad3c1523fc9333cb9ff8e3a99a8f1a35972e224a2a789149e2a4a47a67cd04e6fc7b5d4aa243d949010001	\\x0e0a06382189ec923c8f269e9a4edbae6f46773a8bc799680b4b2baeccff527b6db3af10a1ecc4c698f2e1c41cfdc4ea2fb9a080e8d6e885e6266b05d98ead0c	1683625391000000	1684230191000000	1747302191000000	1841910191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xa3047c6e6e9cf058c7de8134456c7f29d6c202c6661497e841a35ac6cb633f068aaf8bb10070dc986839f9e0761477be9464f5c05ee216961492a1ca069725bf	1	0	\\x000000010000000000800003b7320b5f24fb22fdf1ae2114e9eda962142afd33e9f179cc7510545c350013ffdc6066d305b4dd38668ef81aec99e968cf05ef6d5d368b8d604244e215c4d36db2dae98fda455da61b2d857aa4b0516cb81fd26141831d78bfd26e77894b930634b4a5f50bf32648a465a6d8a078aa39b441a12412d7639b55850025a09fe9a7010001	\\xce66dd5504fde7b2a593c31a21202c694fe53b051050b556ce6c9fa3bcef5550c923b5d7e6b2994c9dbf55809652db4b574d5ba64b45930bef1033d1afe4720f	1661258891000000	1661863691000000	1724935691000000	1819543691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xa83017e1d8b9c6f1ab49cb532f908b64f5b85c4ee7c6083923106f7df954e0b552d2eed058387d74dd7c1932bbf845a1a6dbde98ea09ce020bba3877df58503e	1	0	\\x000000010000000000800003ab08ea563dd04b192045388c358bd3556b00bc69b8627d677c070b7c0edfb8c4117752d819a0e20be28f3868b032140a5f35ff63321ea5766555fd937bf9546348df2f2379ff78e126c7aa89035065fe98330de996b607254e7cb1246c69ab06252411fac98bb1d70b98e41bfa10c2e633a2fcff8f8c7ea4168038e824a64711010001	\\xbddd17ec216abaedc256c8f362998d32d5711ae7a0450292260109c949e32c2e0c3db9afca47494184d3b0a143146926622269206670c8f38a187287eeb0f402	1675162391000000	1675767191000000	1738839191000000	1833447191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xaa48c6960d23141bcc320039cc19c1ff20a788aa1839f8885d3632d9735c4ae2ee1dba6ce3fb7fa87f91da2b0b5d00e4192e1f5d11a8c8ad68b05d0a7f3cdb02	1	0	\\x000000010000000000800003e97fdb8d4ffad6bf758e318ac3a7730a640c0acf13888fa91083836f9cfeb8fa8f1dfd513bc1db1fd4b256cdb9ace7c1a9efb4a05981572c1a096ebcb45ea45281affb5152a1cbd2425312141d316d4c1fdeab424c55820957c5d451549c710524b880fc33aa60a8a36580023b8655c566462de97e06e4fddd64506731559433010001	\\xe374af4ffc2f7c56551edd1d0e1feee929349da28af495cd84a10037e3eaf0ca82e103b287dc3c6bb071bcaefafe4ad18c9bacf91ce417835134f599704e7b03	1671535391000000	1672140191000000	1735212191000000	1829820191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xaa1c74d215cf242570b24d53d8992500b5908c5fd5e9bd8a14e2e8ac69ac485643e4e03935ee28c85e7fd1745c3dd3c3e96b83db16be9118adcbb9c6d8bc3fa3	1	0	\\x000000010000000000800003c8faf690258ba830a16566f4288c28d74bc6b6297d174dc7a7343e7fa8f2f5ae37ca1d9035fff8a0495e54b6aa9e1bf72ce0608a68e9252bebc3c3d0260dab43a0ac6a79791a35504d677d5fe43755621766a1d3e9df4cbf89011f8761dade4bae0a61bbb3e47c8da903b503b287d8e7004a25836c66424f76685d2c8d0397f5010001	\\x22346e71d79b05b1899defa2e5d31f109870dcca418cc8ea43188b43fe35ea8061acbc6f17cddc13cf286c3841e3fc2b23127c3d6821c956178fb7f6402d9e0b	1679393891000000	1679998691000000	1743070691000000	1837678691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xabfc9da7f8b8e80ef986bfa95ee9d2b3c34ba4b5c2248c17469c3bedf4c5b2f5729ec5173985ca7403f2c963b4f3508eea2cc206b36b8f93f47d8e2183b1d307	1	0	\\x000000010000000000800003c6f9820de137c42b4cc9d341f8976c773464fa827f1d8536c892c648c31f3c8d4577ac626724e75744078127545bb8a9e15380f8607421f7bd93c31618167368d4f1bba87939cc6a6ea9961770086429e9fa7e93e2cf812ddec191eaa42127645825fedb9719a62b851ae83e92fb6a6b2113cc25c351a065ff41bddd4227bfc1010001	\\xbbecf1f739eb9d68df6fd5a7d559c41a16bbcd85ed48693f3f5b9b2c9fb2e4ce5e93f0aae823b58bcaf442a09c04b588124c08e7fd2391d13e9ededd4658e005	1672139891000000	1672744691000000	1735816691000000	1830424691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xacc83f0f48526f61f556471dbb5173a64d4b6b8537ae8c5b4eb095a77e77c5b2e7ad2dd24571151e2a7d483f4bf5d7038b2a6a4188cd6ec8d89b2e79d56bbd27	1	0	\\x000000010000000000800003ded772b4351f292051f4ad0a766a8e2dc4b7596babf21737a1567e519f2e14ca6c0e61980f73025a0dc30e66f648b5194bbf9ee1acc368e901797fcfe068a5223923f7b79f0caee423c12c44b3e5f845483c94e0ed3ee1cd46d11fcca8eff9299d76c95a85950dfe5f3585564e4a44512c2ea099d8851a9951f077a13c9604e5010001	\\x2c8008279b5d1388b2a177358299382f2384a489d6ad27303a6b2d7b975c60364c252ae0c90409e6868d6510a27a8ce4197fee6d0838072988726f7eff49da0a	1672744391000000	1673349191000000	1736421191000000	1831029191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xada4b6b90cd2f76ed7ba81571e351d21880c278ab076813b72227f3733c8e28ebfb8f8003f108a0042a3c74bf8fb2710db882d463a819d00723d2d86dbc537bc	1	0	\\x000000010000000000800003e788d2758a3c3e4af3b0df588cbcd30ee64371c5bcfc7ea694424e7721267e79b1c8d725a8b6abea71acd92ce2158c47df7834bf5ddabf250a8277c2273ae31f7fdbc99912d42b8724ef8bbffa9e2117bf223cfca677c356e757e69c7d5c1f27b60d460e0ebb4af3dc8718ceae54fb561e95a165010e47cd15aadfe91d52588d010001	\\xcb82d082d1be081cb406ef565b8708552f7668f34727a6d93ce7163c6c03b1eb48a38bea436afccdb470f26227e32f2ba620295e89ff307332b507cceb078909	1686647891000000	1687252691000000	1750324691000000	1844932691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xb1f8e00911924f049daec11119a8ef4c826c099c7b98831389d1ca94ec67a3a9deff26c410ac99863174b86a3e7661fa52a72b86ca2a91f0d3d99d4e5873c275	1	0	\\x000000010000000000800003e1e09a84dd3f6e19c3c8c559efd9d1ef815cf6086c0692f3059ea4d0dab848c0d092d95aeb941ecb74db8eeba14f015bea09eb124ab8bc881a826f7c6c92e8d4c51e79997d6d23fe39a53887d318f4e5c8c20220cf1c548c3f7c609c67248db08881a8e0700e26b5c8432697329f201db9afbc031962552344128c93d2e94e4f010001	\\x5e6aedb0781c74483e50ad146a5cbba9f11d87e5dee9ae68b946dd6a952ee73ca4d39dec128c563e0fd29f2f38ef16767a7d05caec06e1f014bf4825105b3502	1690879391000000	1691484191000000	1754556191000000	1849164191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
87	\\xb21c090e1478c59237fc1516e1db6771c292360395980237d3e68ce71f6141b1cc808fd93856c6ddf57ee3c2ca0ff450c15d239a66dc8bfec4b9434b3ef07636	1	0	\\x000000010000000000800003aff23cfc92ca0ff6d392f76db4b4c87fccece60bd358951fd7d7696fd71fdd7dee2ce81705f109f6fadce49d276c040dc41155dfa52824a74797639ca37ede9877c09d566ef0e18b22dbed02a110fa1222114da93e02f714cf2a0c4dacb348a3d61ecacd98a0e0240e31d7129d7c8d8e5e3af7add4f3fe6cf2bd00bbcb06c4b9010001	\\xbe6d41b2a6a40dc0c51503620718e3b9026772d360a98d69958a54e145f8b82ebab3dfcfd78e1bad29fed7396a5c7c8e523b192764aa818a662ef76652284003	1679393891000000	1679998691000000	1743070691000000	1837678691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
88	\\xb44c5587b18994ebf946fd3d0f8983f95f487a531eec487a6dc2f3b1ebe8b428f571385067fd8b1a36844fcbcf1946981d6868b16a035af7515e6e15a4fadcff	1	0	\\x0000000100000000008000039d66c0857d170bc5234d0a4bc319656c8b233d061325f380825e4a67240076970b315f336b20e1dc5aeb95ed36395a36c6f56b34bde452caf4d6f7528877afc8ba88e78b6cf0c6fdf78bce874c6f87470a4424fe7242d2a391d92dc8a2db7e49970022b9d165bf43a47331727b59f42d6c65ea0f2b4a2bf3f2c512afd4e856a9010001	\\xc709e7006d767b6bc59aab221df8c93513ee5154c0d7572d8a0734db28da6cb31cba09d61862ce42b0db84f6c0c6fdcacec47d6e816805e3e02f66ba6059ab05	1686647891000000	1687252691000000	1750324691000000	1844932691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
89	\\xb460ffedb4e0292c5e3ca46bcbf845397255457568b0580e22eb4b4a02bb1a8323678f0cf827869d53933e9eae123e0a86aa9470a937dc98d7ac3acaeba9b6bd	1	0	\\x000000010000000000800003d6b77182ab2a06262ada6b61deed60ca53a4da4dbf4c46b82b1f8dca0f4059d44b3bbd3c4b6fa0e69230b2d383a29b4c5bf7b3cbc1a34ea8c854a285a9f445d08b80e29ef63864857a63c8f9c3433b90e710077b9011f8096b8ad5df015fef45cefd09876266dbbdf73029e22031f6f81592bacf83ec59a82d37694d94721351010001	\\xe36e3c13b25a23c38d92dc1cd1aeab1ea56d2e0eba0f937c5ed03be308acd4de4e75aa83895e755d6c1fd035d9dbd8ccf7f43cf84658d8e62a5fa0cee510c100	1672139891000000	1672744691000000	1735816691000000	1830424691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
90	\\xb924f929af6b25f73bcf2e0b45d0a05611a46470464d4e35183286b30186f11f26000564b4d30ffd1e1c496c0b6bcfc1ed6d2c960bd66a84a1cb3740d197f8c8	1	0	\\x000000010000000000800003bd667c02b8bb8e97a9778e27f366a4accfae6a8a5050bbf5ca6608099b7e5ca1e4ce18719e333ee4b1fb5cf72410d68acf170702ccb16314d056da54980f227c67ed97d18ec18862502876b1b70252ba58e519c9b7aa71b1eafa49cffded0ad9ba0112253fcd0971e21de05f59dee59f5dc18a8850a564c9e7a2e5e0b6b11b75010001	\\x5f00e872abe73ae7efa119ba96cd640c47fbf4a5157f9697c0d8e6a9daf89c2a348bc5a7c7bcaeb8fd152fe582e87a5608c348e8b3a3310d48b2b6fed0932a0f	1664281391000000	1664886191000000	1727958191000000	1822566191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
91	\\xbbd4796152f5b5873aa1b69d41a0e27e908a61e0c7e75961c9901eb8018f0c6c3f5321c269f7daf87dbb02337bfcd50f297237bd274d7df754298307c1956d45	1	0	\\x000000010000000000800003c9a4b6c86410012cbf514b0ada68c17fd929e03ae0f7b8f7cf11a7c8f49350d34787f1b1ff0bd10c8f66768c0f7dd43f75ac771466e5bb47164383865f1e8abcf65dbaeae7bd980ecef7d88ce0ca0a2bb6d9714b7f57fb8767b32ab4ca12b606872e32c27b200a97f78735a9b1e1ac64572df8f0dc1bd1b8ac12e98d7495e285010001	\\x5a8941256008fb8ee52d36e5ba102dea645b5aa8c06218c292a640c7bd63e310bc575e76667707cfa926df2a9d2ccef67c49b17521c843f890f1cc343ce53905	1687252391000000	1687857191000000	1750929191000000	1845537191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
92	\\xc15cce2b11de1b0ab28eb2a678b1746b1b93f3b6ee9f27c6c48f7f12f3879f7c4c594d63eead869f2f97ca1b7038faf13a02429ced361d79c74c22970b1e6c03	1	0	\\x000000010000000000800003a9c8aa474bc6dd7d7af4da8c32306f8fa5e5ec3292b08b31a4fd51c894400bdbc1eb9482330cabc46df729f154a8025a6a46960c6d051a8628fb0d9c6530934eb405fb7a34253b2fca8039f9261f49199254bb4809cbf962fff27550f7bd2052eda69ea62a337317fc18d4c20ee8d1476105361f97858ef6cae829230954ca4f010001	\\xf1ca4e11f76001e65105f7d669b3abdc4128da3461a7aa4b70eb857a5ddf464819e963c158f05668974e8af2a62464a586bd6552aa93b875a907fe3cbf362809	1672744391000000	1673349191000000	1736421191000000	1831029191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xc2843808057011c17f6224e905053b4c7e76156e8eafb35974faee502e0ae4e80921c5ea78395f5f40778b978dcdc7efc829add1873463f5beb286165e301c51	1	0	\\x000000010000000000800003aec017f16369487c15f8cc517111c2a5664abe95ce7c52adb079d4d8dc32ca86f09668506e464a284c8b6c600f5782133802cfb24481320c7458a779ae906614e4e2e1590bcf129af142c7631c9e910c6235ae215892575b50b24f0eccbf22c642a0aa37f8e6b6e17e244caaa8972ed19010d8eadb11e6102b13fc164ff9a90b010001	\\x5de4c7a76522f79bf1d72f22f2052ca0e2221ca80bbfccb0181e12b7ebacd4d40bb221ed94a7b6a4bdcd6efd61a768cf4562263430a8a5e53f85074aa4abc300	1664281391000000	1664886191000000	1727958191000000	1822566191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xc5e4badbaa929ae81970f8d840eddce7fc60666e9c2bbdeb6ba2e3906f3f5df7b896f8f85eb48246f085a335873a67f9da33442898fa4d05b5a387ebe2fb1526	1	0	\\x000000010000000000800003c3ae34294b9272cc047b16580319fe805223450c8ffb49a9be0b866960804ac4de7fb2e7f324d4ff75b739347a074c2cce96f16c00d83ea6515fba5017aad6c08f5621a6c48c64b2f39b529cbc19779334c54f949d91fe23220e098de6964da2dcd73cd385bc8b14b33afd863d954d3c99b1a0092b25588a059142175df03255010001	\\x07dde920f8e4e09a23f1738dc5a8511cbc62c22996942575ea449f48f704217a67e4575c53e8779eb7dc4de38beaefbb795c8de9cf5b7b507f3d39118a55bb02	1692088391000000	1692693191000000	1755765191000000	1850373191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xca6063bb6508ea4e3eaf2dc583ccc10d38a453d87c5810fa81ebf570a972938b40b957d82deb5057cf2237b9c8a0b390b60d5a28a0f33c9a6db3ba84676fa690	1	0	\\x000000010000000000800003cb4ba704d84446d26ff9a44beadfb727e1db688e30af6e2f4fc3f292d29514c5566d34b2e563abeb6bb08eaa5200bbd3c9974a8ba85f8aff4e65e73c7133468c3b9d89b6db6a1abda044ee7d94aacbd968eeb9a92f9e152f16ac5f4e60ffb955095dce8392080f2b45430d63e83c791d1b106f72534dfc8bfdbcfe5cc476dbf3010001	\\xa3a97acb0103c2bc178fd5262c70f3fac53cd15b026958c83d2500328cc1c5632f04e6f826a493aa0f6174440c8f29cdaac155a669b3eb1e606ff3d817522f05	1661258891000000	1661863691000000	1724935691000000	1819543691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xcc5c5dc16f86751ff34a5e3f5631a94700cf0806221907a9035b4a18a5cace1f666bd36325e2f4974a38dc08319dd4b3399f2860f75c3db084fb598c202d1b62	1	0	\\x000000010000000000800003cdb7325b6d78c268fda8b75b1d40df9b561de7d09293cc740a9b9eadae697dad42eb9fb4f508c7f5b68d4f529c65261f5abf9e0c0046e94e5121fa03c806c710951a7e8054597097952898bdf23c6b4ef6d0bcd5d8b9c3c0ad018829c184d5ca8b33f11767500295e5a0a54540c32f403c66844f64982315884be39837bbce39010001	\\x2d656a172e7c7a49491bb517a852f3106b4c438e16c804242ae5b2bd84690bb3167cbab797ac8ece2a4cbcc54ef36a0447c89e777fab65c947bc7c7213a4ea0f	1687856891000000	1688461691000000	1751533691000000	1846141691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xd01088033c5930d39962e667a0cc0f95feffbce4197013f1eaedb1368fb2d671626a962a22c93dc930dee809d03032252c01224c21c5de5fa0bd5c1c4880196d	1	0	\\x000000010000000000800003da29d8ced06923cc66237321e31baa18be4175cbc4fb57d3a73bc52eb6d3a087e78a0ee150121481f6703ace1f0ad7570f19775fd3e39ba98e5423e9638d015e62a031db86b3711ad56f2f01b9fd620f3bd98415329b9122702dc3c283f74e57513533719fd8f9d3bfdcdeacfa5e45f3ee498f670b2a8a23245b37fb983a4561010001	\\x2abf6edac96b0732329f5e0778a5455d38614719cdc903a58372979a4b722387a831d326b98016e45db629f053c7c2227864d1438b6aba02d4fd306cef83540b	1683625391000000	1684230191000000	1747302191000000	1841910191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
98	\\xd718f448c190e59742263f3458cafe53b6d5e7fd5ec19edf674f37ccbbfb3563ced34c10ed9df3561451c2a3b2d921dc7310390ceede6eeebe549dd495a98fe5	1	0	\\x000000010000000000800003b49a481b3c7647284bb0a816223af63c0060e23b5f6133c31e11c9776b7001e36c98fe023e34eaad50c14b13dbf303b63fa7ccf786a9edeeeee492e47285cb652891b3a60705ac5b31101d8fd2116b37db39af7d1eaa8eb074ecc20ef6ffbb1e8426f24c12a8c9ebc0e0443f863bf793adacee4d4af5e61446a2cdaff41f37e9010001	\\x3cac413855e2184e68bcb3a6a60cc01b992471844d0de13649a42da851693249bbe290eaa4ebc0a39973c64a9f0ab6b5345f85644a838f9cfa8a3636a5c68e0e	1665490391000000	1666095191000000	1729167191000000	1823775191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
99	\\xd8a4b0e62c1289969c8b3cf827ef614f68b8b123f33ec06e0b41495225c9bd6b891ba67d4d1aefd3854a57e60d1501a20fe9555425fb745df6f35404567acbdb	1	0	\\x000000010000000000800003c036620d7e4d9eb4cb5a433902af5952cc7fa6aca653fba60b993c637676aa9cfa5a872c337eb783e182b921011af968073ed2e008fcaa3746ae92b44a5e2a9fd60160a74175e868466f8b0c335f16db91694db0ed10c8a8971d2361be4da03727c8919357f861e295861c54e06b50de4260ffdf64690be40a41694803029145010001	\\x9fcd956a15b6cdcc59972e8de491707f07f6c3d4fa3bcfc5c91bd2ecfa5b700ad83d9a85e0977104679c383ca06c54eeda0baff8d3195707f2168ad496280802	1686647891000000	1687252691000000	1750324691000000	1844932691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xdb4835d6f259bcf1868e2b733d942ee949d97195cae734c10045af22bec20bafc8606caf5bf707d1de7b980b9111d3935ba9a05e4ba93bb6314cb8a5494b9f08	1	0	\\x000000010000000000800003bd28222b3c106f011df72f07b0aa6af37919753516148c96782d88f99d38699c0c4cbf43076fcad36552be182bdc391b47882789afc4d40fe36772f8cf6bb23c8bddba1b66da9acd436c1e1b6d00872d594110649198a65d42f9787ad1a74cedad42220078c745acfb53d21758360dc0f28dc7ff29fb3e57a033babccb081c33010001	\\x490026b5f77a347adc1395b34cad75fab702e326a9e795663bbbf0de64c1ce1135968679cc09354dac926005a02bd53044f950ed08e6a7b53e10ee21b1afa303	1691483891000000	1692088691000000	1755160691000000	1849768691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
101	\\xe47ca7434e92efc8afb75fd894d178681d537c38bd336900f8896bae12cd812f1ea81c42eff9c8a2b7ae5d35b9ad1bac9e9c9c5e77bd98736e9139a35a78a05c	1	0	\\x0000000100000000008000039fc6070e945e53ec20b8814aac2eb97463543bf20be91cf5f2b8bcc28f6a622ddef679e58027cae20b9d9fd6cfb3ea9266b49b3ab61d6583762feea18f43d3f72b7bd4064cfc472df970b7f024bc47002f11eeb171f7b0ec323609929b9b6849ebc3f2767f2b4bec1f7f980a71a40e83d6fdeae415a7c164436e5cba17e7ba4d010001	\\x8372af217c848bc8a50828aad1358ad03d9561762facb8cc41f7a6df65c79149f7877b2886bf54b62d69fcb6083082bdd8ecb2147f44a184ef4864b9e615060e	1683020891000000	1683625691000000	1746697691000000	1841305691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xed501c5e263b307f94b4b94cd216c00d33b1e0aa577e3a1c71771a06c30955c845e992a0b0701bb1c4a501ef1be8bd504c894011825a984b08b4b105671bc888	1	0	\\x000000010000000000800003aacade8ff4ae8b6826b72ce02a150d929dfd32494326f48f80768409de8df4c0733a177d1805c4d334c56ff25f4afae70084a8f141feedc1a935b445e034b38b78510f685805d31c01d2ea66e25b7b86414f2df343123f9d4eb7e9ff85482fce99de77678bdfa1148909cd3898b312bdd1418610e5ced6ad164bb9a9d47cb2fb010001	\\x74912a8160b248293d537e3a61c0f51547fdc491e00e99515ab00f1bdd675bb408e43388a6c9d12e9793963e2a19f3382b7d4f2564195068155df814f07e900a	1687856891000000	1688461691000000	1751533691000000	1846141691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xf1b4ea4dd32d2e4366e7ae49842232e16dcb394602db741e8719e0f5ea9b6c78ed51e101c76e5f534202020ef246f5bc91585201d0425662d0fcb4cc331787ed	1	0	\\x000000010000000000800003d553cf15daf2c0e1eab5f84a29fc01c67210454bb0c4152588f16e474d4e9a47fc515960dc644a75ff38681f796ed3a8644e1b56c23046a76e8bccf450e822bca92f6752ed3c6b15956c881aa6d5ffedf52634f2381dcd828c96be678bcc8b9eb646b9d99bf498fe76db9e98b92f4bd2a910f71458702aeee5cef54151ab3f7d010001	\\x6cec59f3f1e5fdf7667db45b2156f0222781e83e11dc895aa952b3bfc7cdf335796bc18ebf8fe1957c20ab780f8959d2a0f07ed51507c767d2a0ee8dad76ad09	1667908391000000	1668513191000000	1731585191000000	1826193191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xf588c7eef0bc18eae450719a2c9d0e8d8b04ba4be3ad073c98a248f1fb18b82adcd450e3a2d32c1873a6cf52e1435444367ee5926fcfe146a99eb3e7811ed6e9	1	0	\\x000000010000000000800003e5e9f2cfe7272041bc689f4aea2cb47e289ff96ad2280a1e8c5b9d86c836357765b7bf514a8fed3c8edaa4838676d2b6d047ed35ce9cb290a6f96bb99556c994c0cec0615766a719a825171222763ee538f3a39eeb0ccb0fd05353b41eda9a993a4a2cbe243aae0bebec10a0587a7b9efffd4aae28434f5789c607499ea5f09b010001	\\x3f643323fc6eaadfb31e6a28cff92ca5cb00a8475e1e48a576d8f8eacfb82288f45ec118948df31d2a64e80d001a935139c7b994fb42ad0d198cd2d7b0152409	1666094891000000	1666699691000000	1729771691000000	1824379691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xf56419e46e941bbcc761deac4d581f1487d96b5537964785576c00e394267cc460e9eb182f0b7d257085c303341903586c7eb8ce00f7c38d3e1db6038cfe5d98	1	0	\\x000000010000000000800003af40e16209020359c6b457c5a9860a43c9a5376ffd5b1a62eab6ccdd2cf4189fbaeefcb7f9d100a9a17fe178c7f4e993e0ca216c9f13655e6d2d612a4172b64ac683f96dac9c8f443dce4eea8e04d68ed2dcb8291e302396621e4dc93e756647905fbcdf64406f6b27044884750b4db78283a01eda0a6dad0148bb283f43f3a5010001	\\x6715b640d105190898631d988a3dc994381c809c3949a7f91faff56a7f079f140411866208da2b6b25dcee60e57d1891943380f3b6efaf5880c73725aee39f01	1667303891000000	1667908691000000	1730980691000000	1825588691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
106	\\xf7c4f6c3e2f14d35fe0414d018cbdc4ae4792555ee3e9dba6267c3a1ceddd5fc5aee702933b865fcb280e20a8faace52cfc1372e749c8a98c82c5a5a7274ba74	1	0	\\x000000010000000000800003a6c41d40139eb075f6a5d4debaf1e6b8d14e7cc7ab67c657286bf4883eed98622bd3aef38186d8e5aa284b0cc72b9374262aa8b1bdf645d085d8a7c65dd92d436292b3e9113250723a4c5ef52b8b40628ccd8ca42dc0d7e3fd24abc20945e0ce587a04129575aa9da59de32531e8e6a1110a4d19df06f73931b02c009bb4870b010001	\\x6711f927d8294ec99d0a4b38faadfd9e3fd2c28477e0fd2bdd8d31b1dae029694f3b3337cd420aa18a08022f9c8c8c9e005801e37a8b40177c3e94fde70efc0e	1671535391000000	1672140191000000	1735212191000000	1829820191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\xfae4f524965f1fc529d2266866de5318448161e5428df0fb20a9030a2bde516beb9b2f66f9dd280503974041c3c6532ada292251186655b9c613909a0abe0c80	1	0	\\x000000010000000000800003e83eca1e48e41b3d486d40c5a15c63b35367739018cc40d9ca90a496fb58b83a212d5aae4373dc34d7b89c04b673f3ec40a33c8e2bd3d2ce8adab2af9343ceb3d3897463b4ba60a60c86795de1d863e237fdcdffe36d7ff68d9e03e5ed375a8a2371bdf7bd95320a11bb4807d4036ea91aac64fc871c002c515e2c57eeef05db010001	\\x1bc44642c47956bc43fd8725228ad4991cdac53601bb65c570a6229cc46a34d7260e5c48def843a4461df5b6da2da0d7313bd7c15886b3f5e46c401348c8cb0a	1681811891000000	1682416691000000	1745488691000000	1840096691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\xfa401fb1de9990500aad6e4629d7010151ea504022e986c1f3ac9a8e63b4c8b28bd21c10a203db47da5f5224c1ec55047e7d2e9838ed23a35190da0c844c1aee	1	0	\\x000000010000000000800003dfd0b3d1a5410a600f1aa909cbad5fa8e0190e29d07a486ad58988013373265d39028e26d30236671d39c8b31f24435295a3b05eb3492aaf37695a169380adf8a1dccf4b7d8a7bf9593a9c82905cda0bcb35e233e5dff11da3de1b4147c721be7086a72fe8a3f179537c7e667a5d2bdcdf4f26d0126dfc51436cdf8e751daddd010001	\\x7d0a6f1e958c70758997b6aee60ff784d3350ba2e50d40aa9ccf6a3e2a58a765ebebfe8b2d170351d53c89ee3b5b3e867bd86493dc156181abcc4b92aa8b0100	1688461391000000	1689066191000000	1752138191000000	1846746191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xfb343fae93bcb676d49919fd4cae48ff4e403b6b3417fe87ecc9f65c0589cf83c21f1f0d0038b52ac522ef941e82a1a5f57a3f3c841172f9346f87008187054d	1	0	\\x000000010000000000800003d6667a0a39daf8152107f64e03c7b2a4c5589fd4d9d2f948ec6ca3419226e72a3dc3b095ffb58de0f7436a342623d83bce8b5a5482c9161455c4295e43fba5625698162107695a9dd775d97bf28a7dc453201046b84e268192ef511689241206306a9430ceb72b786f84fa4ffd67e68476fd8b1dc2f4a568e8dddc1b3952b009010001	\\xbaf7e7f999f737fb1352ac7a2d6167a7f4827faabc0b5748ea4fc98b581a7e05d120f2e278d9b8f2db0b7ffd0ed3492089f73aae5153d26e4da18b1e2a8f6304	1678789391000000	1679394191000000	1742466191000000	1837074191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\xfc78840055b4c0012264e0d655656076859346664fb6db247ef3c3b363604ea8a5f4404674236e7ea2309eff8519d68c3ea6f6f5797ba840fd5c6c962c666020	1	0	\\x000000010000000000800003d84a00f2e74fe61dda57a5d8c63dc8eb2c03badc80ff54c1213ec504219ffe5233a0a17ae440768abed981256992a2b331ed7e8288dc601364cf24b6a6887c5aa354d9b6f7ae3f0596bd0b74503d5ead19d1cfaf2244c889789ac154ee8830ec048cf664572f1aa014738a74da1444b120903c54634f28e5f1b3ef92f422c633010001	\\x94c1c9e98a4fd695d19cde7ee91a019b5930bef392cda5c92f72098583e77faba0c1a350ea143b674dfff59ece3fd832b0151550f39d61eb8f73e9e7f454c605	1662467891000000	1663072691000000	1726144691000000	1820752691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\xfc24132fcf95eaa71434fd53a02f108e09f560badc32cfcd6f33ca94c5b3436aa99b43001c85c1c15a63785b04ddfb1bd28961b4d9676466bbc5b0bf2bc5cacd	1	0	\\x000000010000000000800003ca54542717812c0c12479dac0ce96c81b43dc18da77364f9ce3e8fbe06ae5fd8244d64bacdaf7713fec4a655e5d358015e6f2071856a298f7b78e5b2e0caedbec05af795465c3ab1fc117d4536203dce907e3c0b4ee571014d7716a875801af51023b7fb9755c3349f9ec1632746d081168c7a0a1e48e076c896c59847ab6d27010001	\\x7d57072aaa266c3ad084df19bc7ee4b6b5ab3a83492dd3aec58127df9b01e11df053192f724f132f385473645e371e17036f0f82d945076d4d6e10025a05e10a	1679393891000000	1679998691000000	1743070691000000	1837678691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
112	\\x0529d4f01dab6023379afd72fdf74d9f95f57b863131402f58d703c1584525e5f0d34c6e699ed9baf05278432909049c72725d183117f1ac4c3fd1f69e41fb66	1	0	\\x000000010000000000800003c01401f9436c345a6962c9885b95fa76e5a2a979b0ffb8269d44a1a8f5038430292ea994b89c31e891ee4e73a85ef8839d70d81de53622bd8b31212ff42f89389dabf102a62b9007ed8c483b8e7ca1d294fc0caa289ea413a6324cbea862c6cb4fe3a79e9c45da5682fa7b1665193c3db30132ec0a00e4f24f599f8b5d042deb010001	\\xd99ac94d756417b61fc0dbdea58929082f1e232e0f9e119c56d16f2a8f34fd59c6211b57b9f5076ed0efd9ac4d12aa4b6175f35d581297d824aae2a7ba5d6004	1660654391000000	1661259191000000	1724331191000000	1818939191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x052df830673dbdd63e116b343f8750f1d7406aabf9c29080ccc80b59e37b81533df43098831f40912a2d6e9b140c66ccbb08be3d427a663a70f18b4f0773432d	1	0	\\x000000010000000000800003b9f998139fc90c4fa478ee2f60261313d9a15cba743db8fbde16d13fae96538309f7c9356abfe06faf48d99806d5bb6484d953a3257b2e4606af01692a146bd5967d6cdae392e0ffb19f87ec33e7ed1217184d17f9caa2d3f12ed566558f4793edbc1645025a5db38b8b4b43065e4cc095064e100b7358422b4338afe8dec71b010001	\\x9d5a6a74d438a08d599edad6e970918903c10dc884727e7f9da9dca1bdc2d2b8054ac7ccdccdbdbf84848973f7138b905c02101f5b6c4fe8c1bcb970a156380e	1669117391000000	1669722191000000	1732794191000000	1827402191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\x08c99f1144734dd446e52ee5fcc647fe5d65ab9ff44caba0b636bf2d5caa633803765397d5892f3f840f77b550c6d47b48aa6d066818c98e2c88bc960af97055	1	0	\\x000000010000000000800003c34a28258723c9d33084a8ebc9d7862837a2f9b3fc1efa7b23c44e8ceeb0af5e4a226a04abf678cd8921a56f3bd76b9477f43885d40bcfe331862b6ee6cd98bfe2e4e4759af16f9c6e9a1405c2882aa5fd5d16588032e29afe5144554b4023f401dd9142340d71c38500175c8e8c098c81095117cd75b9f7926968919a3c5d8f010001	\\xecc86165cd82f92259ae1e518248c9df48928c4fee6b4e1c39d3f479dd707a2c850b22f41227b5b6e201edf0434730c741c228a13d9620a6d14a36191ee17c02	1666699391000000	1667304191000000	1730376191000000	1824984191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x0cad974387d7c33c157c578b88d449382e132d782bfcdbb87b745d41724a77afb4ac46df7b8c9198d12d8a001b900e3e18945afefdc2e823347ff3313b29dd81	1	0	\\x000000010000000000800003ac3a699e98182a24c4abe02f7acf203a492d5e16d1610c121917a530bfe069f8a25869f0276dfd688c8da7b95eeaa63251fcce9f50a79df5fe68f61aa6da56ce955ad0425f7bfe9954ac5bf78728ed0684d55734669f7a95756c9b007b0143fdddc15049a283b55ae89f8c95e0219b464b3e4116069a9691e3239215d3fccdeb010001	\\x2faa865ffc15bf6282581a5474dbb6d73ea118236d7668e8cb636a0b33fee4d6822cc95987282701aed42d3b6e5d245b8999256b93565b25c6ca053940dca50e	1679393891000000	1679998691000000	1743070691000000	1837678691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x0c39684fd401378548df189442e11c46cbaf094ec64ccb289d4291c4e088cec69cb3ecfe666d3386dc8360da901fd9ca77a6fb31f2ddb2b7e6fd31ab36c7a984	1	0	\\x000000010000000000800003ca8449e53933b0b267441fe9ebab41f19f111fa7ebe426b5d0a6616b76d6a420e4e43739875143ca85eb2111b4920d2e82d317936c60d0ed233cff520f93c1905e615fb08a03c7e1ad971f4f81f9aa7f0a83a4cd5ac4375551bbbc1498bc15eedda356e4a7468fda23412b27eea75d0c90364b9691e9e2b3d6e47669c5b7e68d010001	\\x0497a71f9aabbf4f7cd04be614ada7bdf475490328592a64710867703ec5276245aabccadbb9c3f3727a9c03c57f8b456b34d452baf8b14c8726e4383e048501	1690274891000000	1690879691000000	1753951691000000	1848559691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
117	\\x0d31d5c513882eea994aab690b8cd4dd0b9a85273048f91e4d84f66cfa6e89dd9d710e205a26242aa8213df7a304146c46d6e707f1fea4bfda6225c7a89c62b2	1	0	\\x000000010000000000800003dabb83eb2e2237959488659fd0593a9487d091da87454232b5c2f8c60d7cce83856007fffa37387d2075737f879773d9aaf8842f1592ec4b423533246f4548e7656fbab8f9b7bef6f7eed8f7beaa1a7995d68bc0d13a677b31c643af160bdb497b2c2a51b819cba7d73c097bd0a74df349067c2fa5d76be678e2cb5cf3b2bfed010001	\\x6bd93534bb028700a987feee7996f694556766794eb5a308cac0e60dc7f8dbfe603e71d04139ea3459984eeaf7ab70b3057bea81762d2e628d72c8f24967d503	1691483891000000	1692088691000000	1755160691000000	1849768691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x0df53c0decca20a1919de17623428437c45b790485831e9932a8de4a5f7e47513b7f9cce22df2e38b468cac35b690f8eb55da7ed0f76d40dd5b0d82646684b60	1	0	\\x0000000100000000008000039d9439ce4d5b1ff02542b043947d2c7685e2cbbccc580da3de814252e01b53cd37753a873d0eaedbbb71dbb5162a2dc369b08ded0373f959245b3e0bfe6cdc431aeb818aaef633c212e5808d71a8974d5289a39c5812ad1c995a935c60eeebdb4998fee229cadb5ab6038d92c8dbb3d6ab208ab9cb55dbeaa79139d64a08cc9f010001	\\x7bbe25d7a10c66a6af02cfd495f5e6b1f9b076d9cf5c3101d496a064c89726c84c6b21aa231c92712dd40d0ca8adbb944ce02d2f0dacf3df41a9df0b5cf32908	1685438891000000	1686043691000000	1749115691000000	1843723691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x0fc1763e867f95a334c2326ee7afd22c32891b498e9564daa0fd672007c7531320188facc5efbbaf8780db523ff43ba8cffc77d2a3a184a95edcd5405e6660f1	1	0	\\x000000010000000000800003fb0f5d0f6d89b682863246d84d2dcd7f4d10ffd6a37ea46e42a9689d01216a71d510e78533a97087eddc990503a8ef43360b183fe49d5105d27eee88e00b404c4e0b5b21338e42197309633dea76a25f47780979256585d7a6b2912feaa341e72a0bba91629860ff64f5e65319a1cf657dcb49ac666c7364f6d32b7141dd71bd010001	\\x0e4016cdd78961c1e0b623fad2c0840dcbe904b325dc5d896f68947ad652462cdbe49ed6c576118956e7369d27c608ebc186863d4719e44212332397ce657906	1685438891000000	1686043691000000	1749115691000000	1843723691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\x10e9ee6612f18d039397d41a38e8ded37a67bab0980d19539b81737af0b9ea53e75d252f472c15f9c2cd1e0b300d372c61302babea04955527c465874fd5fd15	1	0	\\x000000010000000000800003aab0e5e3a1958d9b85fffc3b4f0b1d0a107d94b14db9cd2ba00b77d49dec10fd511ab936160f0602b1e19411f6aff48cc7e355b113d8008fa3149d7ba0c659beb4ef9ffc26a480360bddbf5bd733bde27dc46f9132b44cf7c529ba19598bdeb2dc4d10b5c6b36608350e72758e803c73f11bd6834adffdf6161c4c770467fafb010001	\\x5d2acc62df8832ba8f93fd9c8b1ed1e03846969269f3be4cebcd7d0e0388e922c05ed5a1a59dba95f1884dbdfc3aba7c8e9d7427f42a940cb9d456093bc50d05	1660654391000000	1661259191000000	1724331191000000	1818939191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x10a9f824bda7ab2a77a717a74dacade578fc65d582e634806ad2614f1fa2410462e5ba121c9a4e23908d9b6060248cc24e8b2ded991a7bd3bab916404f9e9b77	1	0	\\x000000010000000000800003ab25f04e058dac72c53e4f9347f271295c5708af37ead8ec744860992c64a006a195eeada4b771cfd43a051c94beda01e875a724720866886988976fae26a56ff73e07bd7df30fd414ae894857f348bd36dabd1d7b6555ff9b247afab2ba69349fff7329a6c96b9f3c5467b07c062aea02c5905cd0fc217ccde83c8a0cc6640b010001	\\xe04473b498eeb33e6642b5dc919a9c2698973d3efdb3e821dd397509a0b3e7ecbc7f41a62ef26f31ab6e224783b867deb6a8c14a0f161a32199e66d4dd00a20f	1692088391000000	1692693191000000	1755765191000000	1850373191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x11a9fcb85464ac3f8bf3eae33cb84a446e11eadd35d06b3a96d137bf85d5123c470f2239ac4e95a7f922710945a183e9d20b7b2da1ddfeb50fcf29dde6abc860	1	0	\\x000000010000000000800003b70abfd8ba89ada1d39e7705a90b563ad341017d7d61ed841b4430ad809e9f049d7753d9eb44186306c400eef3b5afbb58e48f269f5ba631e6f1a01dfb067f0fcb895f7389ee3afd0fba7f6721da02f2c3069f652b1c967d0945a33460006b8f62feb1ee238798b672a20e0f7f81b089f89f53a5773da9a468516065ef76a981010001	\\x153d9fd4545fe67a22aec22a16433ece14f9bf6b31738110dd5a87f4c1fd919d86f3fae98876321ba1b2d0d8f2595acb3d4783b8965badfcafbb78868810ea0e	1679998391000000	1680603191000000	1743675191000000	1838283191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
123	\\x13a5658bbc131601ceea4a4947e98fd41160e01718f367cfd25158b464b233dbaa647c5e303653742ef4d1950a264a2957e8443f4f22b4eedf948812bab86bd5	1	0	\\x000000010000000000800003cccd6b90dd42519e1b5cd91e7198be5885d43e18addb219a69ea8eda054a4c35b814734cbf9e317165f0d60807b499e9bac8aec669f0073d2435d2b27773b26f47c017a6d5b9eb74d8a9b99fdbb9307c2accb4a5f5a3e9f7f4193a7ea7a826257ab1f7ef50cdf71dfe6c3ad6ecc696a051e253f219f369d65450c86c3769e43f010001	\\xc77ef5474a1e82ce1ec7d28c6e1af413c70a0c3fb95ba2704ce09ce6dd82957490078ce977799aa29298e6031404f7c8df0d4250ebe1fd5c4ae6fb026c213202	1682416391000000	1683021191000000	1746093191000000	1840701191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x14b9c8f10b73e902fa8a6680d35ed464f48c218ce7b9d8bfae314daa4a0828781c8bc2e7dfaec720c535660cb38179ed83aa552d32424704b5fad44b231a3e54	1	0	\\x000000010000000000800003c218c317bf8c9e3ca78557cecceeb5bbc3478e804fc9843a2bbcbb7f729267d11fe17a55eb2522e07f6532e2ad2761742d0736f70a43013652d9135046aab11b6579734067aa04408a46f138de8e9ac2cb28eed91a2d2581f2a316c18332b0a6d408c42164d1d10f583f65b7e3c4cd486ca372b630cf7077d3cc68a9ab0431c7010001	\\xf30cedb49dda93f4c94e7a739d06c53768909b20b1fc7844b511a295412a1990fe3b2032e8964b36aabd4f65ae519781cffc1ba83d6362e48fa5f4fde7e19c06	1663072391000000	1663677191000000	1726749191000000	1821357191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x1689e5a595459b56f5923a5d6281d224e1fbc325641af161a2ca3ef2aa196d2fc2130356e7f802df75cd40f98e9d26825368015f93e5f8bf618af46d94fd537d	1	0	\\x000000010000000000800003b473ece6ebee42b540b41ab8b058b974a36ce6e38f202782deed4b8bb4278916c5f6702d77f0e4a49e549ddd661e06edff262b0838f00b4d3fdae2097422da8d6c011c99cdab7ef26901754baa5621a45b6be88a2e36c358ab11e2a58371d9cf6c057c8ecca7abda1f09cc1e9621baa4ff5e4195ccff2d65283c0115f8f7ef27010001	\\x3ee8f722f6385bcbb915bd6a817f265b3269eb97e63284db93566ad70563271c69ccac7283e6a53c8af6830858958f42f04bdb0db71c554d76e0de496520be0c	1675766891000000	1676371691000000	1739443691000000	1834051691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
126	\\x17a18f6c7be461c2ec06b6c2fa10229bb1eba24e861fb9dffbd16fe54a6fffc6b81704c2bad035cff3209f6ba4bf092c1e8b8a8c1828593886cfa841e4ca1f85	1	0	\\x000000010000000000800003a89a538401d55918f1068ac804987d59ea02a237ba11c99b4d90888c997284f29539d4b89f48e4a06d918313e9d5d88d0ef3d7c78c3c8009a2371805c73defaa4304000488d67d315639acf6c056d1f6f6986f16cac1ddb984abfbb79474bd48af986f9e91ca80dee7e8b15307a45214e3108085d72f43b8a6ff9054f022bcf9010001	\\x26395857cf66867892c56650f728f5ed9eb3f2e6a2954345c5259cd6da99cbe862847c589c48eb603e7ca9ba361047a51dfccd987faa9fef351dc199ddd4a608	1678789391000000	1679394191000000	1742466191000000	1837074191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\x18ad22f917f47727221440b42357b39637d4248b0152c2a97bc2e1349b4cdac0ae3290147eb693ad8ebfff57bbdfd3b238854caa22e84a197ff1fe15a33ccf81	1	0	\\x000000010000000000800003a428fd1ce59412d1192aa77652ed58433f82f84deb36990c30e90f713559780afab23c0ef4e3781434da86c3dde192f325026bc4b06021967c84e26e928a3158f8c3b3e834b1fc2a027886d70d7dbeb92ad463d4662e6821f752c10be655f5fa229f9b99006a76a908144a11dfe3e654f4d22b6143452f3f8ce9e6016403218d010001	\\x80f1bc58aa18680d287004b234d7163f15e9f70083efab0efdc1ceb23bc32f90cec75aa274aa7b2561d5d3b5f766fa1fc42cdba72e27511aea873d846b82090f	1687252391000000	1687857191000000	1750929191000000	1845537191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x19b56059696ab2e81e032f085fcaabbbb5bebef65f8d9b12588f33fd84627016f8c76a8cd172c045b70b63ac19d69ce2f3fe452e23068336ea818af699220172	1	0	\\x000000010000000000800003dfe32de6c5e41ae451f9c89587540ebcfb9043c38f802c25d48949f64a1062cb6be2b56f9c2e49cc18a5dc7d17aa570c5f08db760ea33a6d9b8eac9b023ae48754f7adeedd261e3d0a5aff4de5aee4349c229e939e0166187a6db6e0beb8cfc9e19160b6627cc63d1d64f716bb9b27a242ce282fc0d94fe7f5be2b8942a33365010001	\\x7f05c431f8f43d097a6230930a8388ca505486d4479920e16df13ad2227e32ded36ff45df577c3ed1fbfba329487dcf440bd3248f9a5cabb8da7ae62f1e61809	1676975891000000	1677580691000000	1740652691000000	1835260691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x1f0984f1b12bf454d921f2c58a81a512abb1d4c8467a31a03cf9f810db91e20264c0c9f8ee3ec21c11eb9dcd99f4c035f0987dab5fc487a1040d4acfe8b27b68	1	0	\\x000000010000000000800003e0d4558a8af55e244dcffd69bb0ebe5f9bf54bc7b0623d9974d4dffe26995eba4f6abab8dbafb2c8f733a2df36834d052f8049f155909d8bdc4299eeb128c1263744e51928b363bf729baf8888154c0cf6eeff683ab05d7bb6c4e03c9a2c571da8449db8eb0ca0706680aff4d1f1dab5391c51090b09978ea4ec9e72b6fec8f9010001	\\x914ad7dc75781bb1efc38d7073f725c9b3b7bedc10fc30a21f67fc1b11c1d8719e6f8de1816427ffcd9055160579b3e782c80005d8e6b256fda51e475ab4110c	1673348891000000	1673953691000000	1737025691000000	1831633691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x2021c7da73b593c6c4b67b3ce5ff4242caa12575f406f822def70040ad9cab004b6372c08416625f125cf7e19772a09b590135a208dcaaefb24c005c136a5e1d	1	0	\\x000000010000000000800003d93d8881e77a0ac5ce3733119d49072afc9e7fdba9dd9af743115fd8c074b435a641a6c866ae8d1a1d39ec837906caee47dd81b0cf46f4fbdd9c293b8426991f5d69e961da8f4c14cec91465f7eb3ef9e4f3612ed1c057ed3ca6f22672b44bde1f29e6b797262f99def728722a1dd7f4ba2b002937685e7f5fe9233a2e435ed5010001	\\x9e0354ea49dc411ecf061eafb44c6028357abc4cf5dfb62bc7c4eb2a99ab746b3893bc0268e85fe2b8ca5c63c3fd9c368c4899fd75e14843e7b905bfc40d300c	1688461391000000	1689066191000000	1752138191000000	1846746191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x2219e4cb84b7f57ee9f49b5c9432a7ab58e4ab2c5750a7d9e3d7c5a414e38888e8912384692aec053cdabcfa041f7bf8e836243f3537c98ad7182264efd9f9ca	1	0	\\x000000010000000000800003cda70e6acae78afaf93286320ac438f8b9bd003183cac4ada98e42012dfacdf394743b9890e8c2d0646f873c8f599832144dc9d58c7159bfb1c25a8feb56f6a4cf7a34216a8aae3be04868b864772686c142961d71ce3a0de5ea6daa085894edc6aef33449f0a468640419c46f26ced9a28ab70f1854ae3abac42f00afc313f5010001	\\x069efa922a89f1a10380ba953310ee84e0883c38b906e88b6b231815f72fe1433a2df9cd0b1e3e7bef1e34e4e8a7b5c7795a872808becd98f79c4041a9f43c05	1690274891000000	1690879691000000	1753951691000000	1848559691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x24c942aaed186aec299f1e3c108166a4ed8d75d319f4f3575ce993ab0d69dbec56ef01607cc28cba44d9912116d93e9c87bdd043e90fff5a2974f191f17b1622	1	0	\\x000000010000000000800003c3bf1e13caa6a1ee9b5f5637cc8c0a2ae9100615bc89b84dd9ab9decf2be53a04c8ab45499ef90c465155293ea06e9e5d73613d7ae708820097d96c4b67e6973a1a35d1b1dc9640471ab87e2c6556fed9596231243aef352d0bcd8216ae94b1a41ca5c251de768c42d237acff7fdbca16999b3ba9850a55fff177c7d4ab1c129010001	\\x6d7da543c8b2ef1e9e415243d1e966446e153dc53c83c71706b979fcfdb873487c7d1fc8eeecee6c622d40500d4ada4193f5c1d795553e45efb5d03c86dc9c0a	1669721891000000	1670326691000000	1733398691000000	1828006691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x2a55fea44b3aa103cf7392e9fec8957b098fbd7b717ffce67095495969a6a1c97b17819de3159e11e15dcb28a9f70b950ff9c11827532654252b7663d4fa4802	1	0	\\x000000010000000000800003b05f40867c1b06dbe198a18d122e70af40a4e8ef123337be5cf0ad44782fe77de48f0e37e01532a53984be36528c28e704cd617b600e3f242819c0d72ba6c58147655775f4c82e43ffebdc5b4eb466f5655b49336b41b15e7b5b112d65bd1552229869f043ceae8d7c20fb2540b16352822ae764cf4cf4c4734d73829a5a7033010001	\\x5c8d63e80ad3790040118518e42eaf045eb8dbdee2ffb1b15553896e61c8dcd15c47022c1c0e0cacf8ade7e0b74a9693f5856e90315fcca22c760bdd7bde4608	1669721891000000	1670326691000000	1733398691000000	1828006691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x2a216959726d894bf7bc79e3784aea06490da37c70b4f78a21f57e58993007d18f332f919e58a78cc742f4a44d94e77fa2d309c0a49809e50cdbdc263880b93b	1	0	\\x000000010000000000800003d2d2034a115d07de7fd4cc11d05fccf5664537d28a406a42b988e06b6bf7ddf6cb0fea47cf6c1900006893f52fb8a78c9bf58de6226a3bac89fb41ba2514dec33d0c3fcf47999240e371ae613549ed1e453df783cbaeddfc8875c8a572577fc45bb1df2cc5ae4cd713da7645f77a4c8e23b1d1ed454de879dc65c39130521e57010001	\\x129f0367f9cc400c0ad62447b124a5b40112086e19ca4103d3b020899a2ef02d8f1004e8d97ebdf6e63b94fff559fa4d5e93bb1b5649b5289cebe643e31d4600	1667303891000000	1667908691000000	1730980691000000	1825588691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x2a8d718771a30696a554898e8d850c715a66b6248b7a02e62f395a88a15543f559804a5842919d5a494d949d0db052ac6a768c63cd7a3f8930e745f27f55320f	1	0	\\x000000010000000000800003cb944d507fbbf08ca13bb0f01beab93d03ea1e089651dc864466ed295941e47e7bbed48af0c743eec3033311fc321b215b0f957ebe900c9b724637f214bcaaf608d370e190d13574283adab442cee5056f10893b9a3b537f2829f7fb50d1e52df0fec9d9eaadecf579549fc6b1eec62a8704ab00a3d20a27ea561269499efeb7010001	\\x43019e2d907c97bef08845fd0328e0101a72c75feacdda9c481e29e91490b60c5042ceb8232b28dcfef5043fad3bc94af42a2a92903d1d1a62437a13267cfd01	1662467891000000	1663072691000000	1726144691000000	1820752691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x2e25600461123c1cfa4fdb8189263c72a2ac12f2eb16d49f6296c31cd09f2cfc0f3cd215538dacf8e4f5427eea7a43f922979fe9132c1e75345071e4e69157c2	1	0	\\x000000010000000000800003ae5ac031b21490426cb922a5345bb85749df77a8815bc00372932cf94429fddb1f0a11a5861e58e124ffdf241424887e550d356c389dd3adecca9868d00f80c55240cb2b81164069e636befa9aa857a264526bf40adc08d7572f25f664e921b37bdd8c7b511bcea14b861b5346ab41bb5348caadf1b5f81da11716090eac3d09010001	\\xe84be438398305d47683cb9e8175610210e600d08c12d577c996caa6b590b5bc3e03aaaa447828ee63a1a5cd0d3b623b2be3d5e17ae967defae19fb4cbb8ae0b	1670326391000000	1670931191000000	1734003191000000	1828611191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x2f95d996be6d12a678cc819d221798ac3500751c410211e406065f7e9f18724e54cddd4621e8b584dd29f8b6021bc7464fa663f94a8b40b765acd3f8bfec1739	1	0	\\x000000010000000000800003dab80a243ecfe199cc095d8fee8ff725f9984d25901d246debba3955583b355dc98e456c30e207d30c0915eeae58e406503abeb9a101c7d5e9198c69ab76a6e248d757fddc8eb8349009ab904243c6326c43611f331c48595a6e5f8c8ffe3eac6dce9a869b239368bbb566ee7098122b5cb762abc8b95c61114a63d539d1d423010001	\\x0e7729a0999329cfde4dce345c9b16845ce2996135afab7872ef9cd6387cab5e37d08d608b5561632b70cbd22881413b16ba1013f1d7ceeaa7bfe483c026880a	1676371391000000	1676976191000000	1740048191000000	1834656191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x3a0d63f81370f6dac5e6dad70d6a13c90963d66a3decf11e321e0543abcf3d8a89dab5fed5116f12f9f726c1f494eb8f4d019b60ef6e404f06bfa4a4086e6fe4	1	0	\\x000000010000000000800003dd18c8c2b02c25bfd68b4283f68523f74cbaa236a0993bad93b00e3f6ee04a278f7708938fb9c34a0d5a86cf079c0fc140fef41ffc224ee55b0c784763f948ce69b46e910d096c27f6ab0028f081483f70e465bdd3d552867c6080b4e100a22b748e9701e6bd47abe29862e168fb7ad25c92d84f0965433ec8859871b5b4b5b1010001	\\x5cbed0c7d9fa21f45fd536b7d7c203b73d82f5ae0a8e858c2ff9c773072b71fed8f21e6b05000b3f9e9acd079b1ec4ed332360542eee5eac7c2adf2e2cde8803	1689065891000000	1689670691000000	1752742691000000	1847350691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x3c9162afa58c8e7f6bf4cf5ca725bfaa84e9b521a4ae89972e02eb254b0c375733f18aab41d9bf18efe962db0b7445f4b1d872f0dc1f22d310f45f196979189a	1	0	\\x000000010000000000800003b2a377992033dbfb3280a1a2c59eadc3dceddd36b60f4b989fcd0a1c5f3eaea29c6f05d4dd74179bdc3432d2cad9b7a27b1d1add38ccca7f9f3e0c11c03cc218c7075760fc98417efcdbfb2277f90442ccae8ddd1921aa2b27436fd5ad73a83fefeac169e6745688d255457384c3cbb77e1333aa3dc0d3336ac3162390a32a2f010001	\\x41b3dbcae76301e7a0daf7ff7f12ccc079ee5c9820fa416b103149fe782c530b1d3ab9ea066e35a3f926df30abbe1a03b2fc24fb955fd3a9d163c94e64f37901	1671535391000000	1672140191000000	1735212191000000	1829820191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x3f3d52ad22de39319475d12b3d1d6f20eed30365e6e6ce777d7fc606710548814a8da5e847fb980a66e487e5efe1a692f16285d1c8c619730b393c1d7060b93b	1	0	\\x000000010000000000800003cb10f7e17ab7f373b483ab416c8b7fc1315a6d9b5f6b6a95b558a62a65a4f0bb68ff4d0376846c0e3a9ff1203766a82ec722891e0cf3f60189a2613c4a98a9b22943b04d548be5e9c3ae40abf0f7238589d9745498997909867bf316bad703003085533b7afb206e507e72c2b317543b59ba189eaf66333798e6826a55127719010001	\\x73583ea8c9ed325a367d5b785b31bf5b8d860985797994e48691ed69e19dac67c78433d857721fba4fb8c0ef8c48ab106038b35bc18f4952ed50fb37a04ee10b	1667908391000000	1668513191000000	1731585191000000	1826193191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x3fdd09aa582b5911087b9a8d25308b903333cf11fe4f90abf1e56b09c64e02aa1b8602bbc62c21205fc618713d3e0991212d8cd520b3b6312c847be52b36950f	1	0	\\x000000010000000000800003bf345f707b050a91d16464d0b37e1d09e48c2bd2b4d7231f8af319ee6fab4e6b123d46838e613faf9b98fb0656cde4abe5ae8b05be68bb52ca44715ae9f86bcb6e9d07ba51b7d0029a56ff27d8b24f7c8f261ae9a12aee5aa9d28e54886426c4f6698fe413dfde2084b42a812c46e9a50f9e72d9dac5d6a4462a2d61918802c3010001	\\x1049b859d2674848e3b0b124467ddf9513d50429dfbc5832fe3be798cd8f455f7d622d3efe3cf07f5e14e518cd4378e8151a1e7fffbf6cf3dd92f6eeb97af907	1670930891000000	1671535691000000	1734607691000000	1829215691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
142	\\x42f5b7ef277a7bb635a1126dcf8625c5a63b42cef69ca600412f1668151c866ac3df08100d0c6c816e1ae6324c83011ef7d7366b6b9b363ac153a81b7f12314a	1	0	\\x000000010000000000800003dca79965c168500248930a64256e0db74515c37bcefe703a090480ea95e7dcd74df5f039ad0f38131dde3626f247960f2017f1623657880b0a82a946adf5f07c2e5f29917a91a77bd3903c7b171040c3d14855daf90e6c697d769a6f3eaada296696ba9733ef847c906654bf60faea5f457d68d5f0f8a116f69ca23df55d7dd9010001	\\x31dcf5f9feedeaf58c7d4a22fba5aecb9ca47401ab37dc92bee2823dd3bc53c06569ae58fbe86e92422f9e1c2525bed00d01300264d318a979088fd5d9989007	1662467891000000	1663072691000000	1726144691000000	1820752691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
143	\\x4a09f9f0e093c73b27df39349df80718346d82f273c708f58bb2e82425ac05bd69f14eee58a030a3f4cf2409138d14d8d83703ca930dcaa70817900562ecd1f1	1	0	\\x000000010000000000800003b9f925e7dde41177172939a71a0f7fa1fa843426282de6e89a6165bfe476122513be6047bb6d7f185e3e3cb0fd35b47cbe744d0bc3ab3540848fdfca6ef721c1bea81207f49202340f29e4e6804fc486c1f535797f2c8570cb03f44feb87e2f221ded18a7924ecdb0375f03d17e57f973a2523ee5d4475a9368a9c01064a52bb010001	\\x6438b713e709ad055b8908c77aec4ed916ff00e88f3d2029b142bb3a46a783b163546e0e2f9af53a51f53def40da366e12a89b6359bd7d4d8b680f834c3b5703	1662467891000000	1663072691000000	1726144691000000	1820752691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x4c35489c5dff235b9a83cf6bded3184c72debea4b4b8911217bdad490635a8cfac61d801c5d52d612482cd9d87bd5582f6dc79b516166890c389cc7b55b0fe99	1	0	\\x000000010000000000800003fc206b9216adcb82af387a7af71bf82cbd9f0777514eaa983ac3e37ffffcf9f49027bb31d5747625445bc80b182c6564282b2bbafcae514db901576d8561a576c4b4bdecf3a188be27c1bb5f3d2d772e16dcc8b2dbb3019b45f4193fd3bc5b11fc5d21500cd6a40584b3cb86491e2a95badfcb4c384a749da6b7732943919f79010001	\\x8ccb5009e771affc69b774be193943a196fbb2f32039c8bd47d911a90db17bfc3439409de7f4b863c27999172a2e926dca0011e8ec4c91122d25d8abcd268b0d	1686043391000000	1686648191000000	1749720191000000	1844328191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x4da919566ee122cfe642642c94d3718cd38279af88cab3084303ce3de85fd26a0686927de3f5e7c35a5ba949ec091846c4a8fcfd98f5609e4028c5e8e5f45876	1	0	\\x000000010000000000800003b8fae78cfc7fd0f5663eb4a5d6c25bc99e4fbeb50cd3ff4871e559f979f1cfd34b0052664e99ed092abc17defbdc4d3d55223f093119fa372003973102c3542ea570f4d5ef08d42bc600099b66388de5c280f3cfcfef9d00cb4cd79b99085fde62c8f98aef5229769352d2a2e17ae5d3ea0100abf33b91a6335087cb74802355010001	\\xf8327e9b0090cc00227e34c98c66b05e971c0163bcc91c1c0af94712457450f3025a208f38710d930d3467baaf1b4fda2b7de47a0ed58d05fc23a605a6182f0a	1671535391000000	1672140191000000	1735212191000000	1829820191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x4fcd6ce64815fe36a359d7f57823e905cac003685e82e87a96235828b2a0cdd6757856de196750eb6c8d048636db83e8141dee12e2d2c613f710770e2fd9653a	1	0	\\x000000010000000000800003d14a3a824d1eb317054bfa516694288fbb95a6d71c7450c46bd154786729a371897f5d6857b50206f243e1053164d97971f2d9f0f72c96e15f50b14ce1e84b4059a887bff78d2f38202635ea78ae4b6dc770ee16cb16fff5776e4638bb5e22300c0936fdd932427ace7e59d81382ae0f3b38f86b614353f98ead6d5e95a3d38f010001	\\x6019be47584383bbbd3e7bb8c1c8bd435f6af1001f36385dd2eaa0b8acc2695ffa2743afb754a312ea1d0b0fb4a7def5130674809c12b152b436004e31abbc04	1675766891000000	1676371691000000	1739443691000000	1834051691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
147	\\x5381f71cf32d5c6d3bb3bbb12ca529378a3c4ca39abbe3ffb4b4dedb4c87105111ee0690dd84ca8eab33a19e9a3207de5fb67881bbd728392248a71b3b62dcaf	1	0	\\x000000010000000000800003bcedd38aae8bab25b40c0a3d94e3ebc49499c09c1e331fff7918f81927f937c9666f46ac0cbc28239b39f410d351dade94a185661e7e793f0d30a08d3c4a28cc07be60a9d52c883631c66337181a8bb8fab0cb5fd8292694376e2fe7bdcfb7c3726bdbd6a18075c039925fdce762c69a4d6584444a7838352ddd8586cc667193010001	\\x40282791a0b1b190af3e6295db587e8a776eeebd7e1b1f1a39c49909fe0d293b59e71dbfb8bd0bab6649a903abf9798bbf7918af6ecf25e3b41bc4f7e8408c09	1690879391000000	1691484191000000	1754556191000000	1849164191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
148	\\x54bdafdc4f4fce836e2bbb2ada3cf9219ef1a70704bf526145709197f53198c29bb78874c2382c05fc5962d5314c779535a7608cbecfe781dde6f573c700dca2	1	0	\\x000000010000000000800003a43bb50e33fb2b6695b28c317d1b0f5d014cee6a6745546a144bf9d8cbf7a3ba0fcb6da9c9626ccbe6f16122011c45fa3592947e3e0fa5fd92e0bf9577be869530ffae81203f0249a00564f568cabf886e3ff014e8f0315cc67e24e208e1335b4bedbc5c249760ac18ebb97b7132d496e834a04f7ed382966c104668d7633d59010001	\\x5851ef0f63061701edec3bd8c4c2b0beb549943f9694a22eb36ff498cf11ae6f51df02c455ef67804d455366d11b548d2088fc379b54360af3c680cae5333506	1681811891000000	1682416691000000	1745488691000000	1840096691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x55a9a9ca268d144e1a0c0c3672b9dab658190d9308ce667870b242a256d77b654e981f1e06e854f90e057871db82ccf48b35d1f7fece85e4ac162e3a6ea40e97	1	0	\\x00000001000000000080000392720933d3d7f30e642c697cf41f3af25789ebad75a8ec0cb53c936e46e2debea2bc9eb1fa594ed518cdb097684419d1a666864b8fcc4b98f48156cf415c1691971b785039eb45c669667d5b866f1020a37678e7c3f3572ef12adea19d82c7087eefb2cfb5f04612f14b79880ccf9f1f5967469b850cbc99519eadcaa8419dfd010001	\\xf1d62b9d09b06550255a15b394b6ebeaeb30c0b4b46614a2cf220c31633bd4f467d54f2bbf66768d07e2755ac14e4bd4b1147f3d10d9d2a141bd7858fedaea0a	1674557891000000	1675162691000000	1738234691000000	1832842691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
150	\\x565dac49ac3aa92933bc7d585fc3343b2adbef0bb66ebbee30354e617b33490fa46fb0ad1e1901a739594165785a56a58f18cfafcc3b9a80ae56479366a80af1	1	0	\\x000000010000000000800003b158809e34a667c0572e351e2e899279290b7c91789cd0dffc0866cc46be23c05b613da81b5e852f572182a201291798fa287edae8daa61da56cdc6893cbec43e787dad112d1d95fcd2295b8b41c158afc242dd9ac0212ee350eb66f85fc65ea7010c372a6ad2b726b6e158fa538485b615ca82ae3e35622e76b10ac93555921010001	\\xc04b697fc535dad151326342fff8c9f44798f39b61d45ce05cb6d6685e4ecdc6bf0a910dea945c591aea643f08043d10450e582ab675d21c184bdd20c0179403	1670930891000000	1671535691000000	1734607691000000	1829215691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x5ad1254d9c7f16ab012de87cb2608eb7947edff7116d9c04ac29dd46f1e324bdd5757e2f0572cd44926fac368d14e31339034429b3de1331d563e891fefe5b20	1	0	\\x000000010000000000800003924f9a4516df621232c24dec05aa20569e175016651ee9a67fddbc42f6ff7efe22e5ee15231aef923fecb42c0ac1f41799c193afaeda3c7208063a44fe0257c7875516046eb925d4024efd54f2ed04283a6e71c15774c5bc61cd84bac811bca7c0a7abea0a805eec7d15f97439e6751d2ff4326b78a0145e0712bf3c53c29235010001	\\x495b04e6ac6087da42f5999da59cbb6238727a7db0d4b83f525f0fa2fcd91b81dffa6373d6ee22fbde74eb3dd6b45c338229c1d3d5c8d25f59e798b0e92d420a	1687856891000000	1688461691000000	1751533691000000	1846141691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x5ad9842f9253c5103eedc6ad5cf0194666b5c2e51a055cc14f9e084b5ec8e3eddea25918916c3c8a78ec7a7d358bc668c6e3211a6eb4d5245c884f6ccdcde66d	1	0	\\x000000010000000000800003b404ae5de17d83a578a23480429d9174cac2178bb46315e30781b164783b070c91024dbad681bcb769fbc4abc873d25d9d4fe8ae9454f6bab3f70477f836c2588ac9e92a6ae942dba1795dda0babd031deee42ce1385ec28c7caebbe524b964f50112a00b71bb649d86399ce47b2e745309e691f6ff1ec032b2dd17d121ba813010001	\\x7f43c347ec8045b6715b128a3f5e55511797b9a152d85401e2fc0f533edad55066a208d0c6686262d9ff4d102bd0a59cd05559772d6e59835f79e22dd7c5e90e	1677580391000000	1678185191000000	1741257191000000	1835865191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
153	\\x5b3d2fc96ab02806ca25792efe810b0f05f1532805896dbff2ec5df185b4ea7993ab71836729143bc55628026c63f6cea3bc4780b730d61a1b5ae5eccc6fc762	1	0	\\x000000010000000000800003b7cd8f60103f54962c29802a1d029e3c4cff9582dfe350d8060654829a47319106a7b57d87aaba46ea9bc8e015cc0173d30cbfa2272d705fe758aa9c6d201f56f2e62157d38b9660fc44a7de85ba556838f1c24dca17733ba9af1479b3c164c75c7a696b6601f24e66165e0d369b4c7d5333fff7d4e84dbef66fb11b631129d7010001	\\xcf0069d2735dea035390b7051ecdc37e1a1becd0f1d7e962779a2ee1058850e601ef1cd6c95ee39f948471c724b5fbbfc0aad33914932b3abcfc7f3536da650f	1678789391000000	1679394191000000	1742466191000000	1837074191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x5b41a6071a849322d8c98565047b826f53f0354b2a1b1dded749fe1c89f50e845470ea689bd9c31a0174d0992caedacaae6db03e20edcbc98a9f09499546dbf0	1	0	\\x000000010000000000800003fdf96f1538a307464b5b35d3123232fe3b6cb3d1687f64dc0f20a0492267c443ecce5f550c3ef33405f2c4853cef6f8114605e78d5ff682462b20dbd5e507f910d423f6374093c86467244d898e8f03e193519182ead334698c2065de6e037400d7beedb5d7fc566fea76e6f4237c6efaf6f05db0ee9140a909d38a0ff2916f5010001	\\x0d9d88939382e6aeb6b96d5cb39718f97d52c2b0b8f4cfc75546d9ca4f30b56e5a3d806a8c0c7f2acfe572c075cc22ffbfa06defa59f16abf090ff17a20eb408	1691483891000000	1692088691000000	1755160691000000	1849768691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\x5c890c2a38e698309a35c7f102503006c4ef6ecf43d3cb6fb1662594fd0bd28edc8b53df839f80a12cc48e9400a75e2db3a1e06280f1e60399c8820aec9ad178	1	0	\\x000000010000000000800003e33d1a17a3356e7d0e9c1ba481db4bde6d976eebea140d29c0890a7881fa786953a364e36dab9fd666d4f7da5f652a647de05ca9121d94658bccbebb2aca5531bbeec1c8859fee61cf470038fec68a3cef4d4eed7f6d1555a464e8fd0ce661313934ca3053683917a1933de30779c25c7497f2b987c58936460bcd4d0c70ab05010001	\\x9b151afe1695ef2cdbfbdd3762187bb97f433689fa0035d972e721b08237c7319fd7914b8d28de39b635fd2c624636e4e484c5ee835aa1e09e227a3a0a4e9f09	1674557891000000	1675162691000000	1738234691000000	1832842691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
156	\\x5c9d278b858419217baff6ce7444cb00881846eb1fe5c53c61f67c33641b111a8ca45dbd2ce340318b891661d4632ad0077e677ab74628f8a6c599a4cc261f1a	1	0	\\x000000010000000000800003bf1bda2eb2a5c4dca654c763d2e0fc3bc74feb8249fb70bafcd011f9dbed2e1f5004dc757d8b54faf279ce4da1d1bb8734df6b4f860a91a215d819f299486caa5c5023d4490dbc5d9b896e68dcbffccd076402d627b3613723ca40bf52c18aa494e52c0e9602352fd3b53805b7c576efc0ab95a20a4cbb337027bd3ae5cb2171010001	\\x15106f71b5ad789f1d13ea0185c93e0a296a258a7e702e883dddee8e9335b9ac69a3e3ed11ec0fa9a532c3e0aacf6491bf083b706b0db45db240cad2c1a8750b	1661863391000000	1662468191000000	1725540191000000	1820148191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x62f9e9c4a69a2747d67cd33ec03bc0d7dbf57dc1e031eebd41c0485a0aa9fe9fb0a23ba6d0b9a6a08eb847ace15719f02eb116cc156c4ba15a9a0ca3f9eee30b	1	0	\\x000000010000000000800003c32c660d735ac2ea31dba592c3c331cdd8963c458d8d5d5bb24549d6083ec17b810f235af83c64d1d67bc91f7e510eafc7dc9fae7df84de1687c2ea9aa43856eb8d40af2d0c3e4c47cc1c65503148a97c1cb77d4bad80a664dec0a3bd9d154c0cd729e49075b079df4436832e77cb1650170092fd57cbc3bf49b6570b074aecb010001	\\xd031ff8ca0199a1da135fd386a3db4bb64ecbdce2b3857a6f2a4a7f3399fac0b48b462414dda97ccbe12cf3e2389d6972b443ba9b106d583b55b4115d2e9730a	1661258891000000	1661863691000000	1724935691000000	1819543691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x635d9f0a19c2669ea8a6ca190e33e4efa409eb7e0f6dac1a2335c4a20a7c5ab228365447d151880ee869987a35781eae26ea05059569586225e5393e896eeee6	1	0	\\x000000010000000000800003c6de3442a03b66e1b80dc7a9f067eef38b1572eb209d7375e1292b7ccd70ee539dbdbbaa27f0b878ad416b93c20062a94e1fc31e4237c2fbbeab74053875eb50a3635376c1df99a3bd08c73fe965a0339f4ddc3f45c7698f1e049194f9c5117aa9373e642ae7e6129a7884a544925ef99e0cc342cc6246660d13630bff5fea49010001	\\x2976da0294ed53c0e3ee7f16a9cde36695344070a619c2d81aaf01044620a4213c68695bb6c380c23128c2c69cc0c5f0ef9731e60c51b12437ace2ce2d622008	1671535391000000	1672140191000000	1735212191000000	1829820191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
159	\\x6395d31d9355e437fc5d013ac1ac4f582247d1df5b0fd04ed9b107b49385296af31a10e6a718eade280da1958fc8797b8eb6bb996cecac125ba95edcf74fa226	1	0	\\x000000010000000000800003e4d78bd5c9d2f0ea6dbbaf72e0e3777a5cb0ffdb4d33824bc18e8068c900061648cdb18a397ee639bd522af5e9cc2f5ff4aff88adbe02a63ece5c3248ea7808c92c1fa3c9e251140b93d1a56af2b8d92f62a856a56a6d82ef0fb07c23afe82cdcd80fe12e8f422222db76d65aa6d95e2852eb9e1d4d8a251bbf91251677b2547010001	\\x8a52309854d379261c5517f87b0199f7383ce7e755b8cf9f8b5d58a4d58db1a09fc13a33008057ad9c1d746a2c052b2fe3bdcd8ea6551fb096a95048ebbd5603	1666094891000000	1666699691000000	1729771691000000	1824379691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x6c3d20492d61e6fbb82598e22678a8bec658fd770c2a056424222e65d2937a0e537406f0c0ff5ab3b4e312ec719603574c8cd8688e5be1e3740df9286772137e	1	0	\\x000000010000000000800003bac1a4813a7264f04d5ca26617c92998eba0ce848a3680b7adb1665c5cdf11470ccaa000ed593c7a7dedc7032edc36ce1cce2d10f9cad059a428ef791c88e1010db1279b7767220a7e762ad5bc44b8bd21c53aa176f6b41cecaaaa8351efa5c9d375ae67af128f0c2987af3f836f6dc297ea1f60b56a656cd902f62daa2805d1010001	\\x99e637099c2a6e6b9535a3994472314669aaba90179bd00de15c8e8735376b78d0001e7cf7649078eb3fa4bbface1c74fbb8c951e37cabb65abfa86d13a4880f	1660654391000000	1661259191000000	1724331191000000	1818939191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x7705cf74190718f34227039035db48a9f576af454241d5274591be218267d727c231cb7c6485dfd47034dfbf446f545e94d026674782bb4e9b18aaac7e2dd60b	1	0	\\x000000010000000000800003af2b8b3701bbc0202e625fa1aff7f9a6ce18c8fc91170efbaf8524ba60f3f5810afbd672e1d3562a4c6ae17ba41bfd7d37691938fc078b2e921f9d40c1c06e89de445d7368931dce3c523112e6c8a8bf34b1640ff32a84596fbe872d2d999fc847023b69a4408a902a51cb81c8127d73c918ab4a07ed48af3032fb7d601d7c49010001	\\xd3b008014c33ed945d36bc41250f4de0fb3d52ce0612eba07265f1d54eb5e74feae16d9119ed62b38c2f2c7e29c44efaeeb793c7c69089aaed042238e8af2507	1664885891000000	1665490691000000	1728562691000000	1823170691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x77fd290dcd352492897ad78ff47f565b12bb0583886bca89ba60e55175b344ea5b73581993d9e40a6daaec548f2c4f287af2141002a93d412157e41cfd149d62	1	0	\\x000000010000000000800003af0d70a441d10d22d7186ca22d3945163825ebb317609a32b7571b6d5c211ebc524133f1701806ed14c74fdd6aa23209924201d525ea3d2199be34d9cb78ec1a523944ebbb493fb33417d7287419cf64598a7f79c2554cd988b5f16bcff0f0977eb17a49228d58cbdb7541871dae233d32ed38f3c28213100ba01c4f6078f1ad010001	\\x6ff1a15b46dda3493618f243c5120f58ba7527e11cadb8589753cf08d7194eaff2ba418c35d01ac15e337510cd2a67d8487e6f8c8925e500b9a93d07c9259604	1671535391000000	1672140191000000	1735212191000000	1829820191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x79d193c884e625bfc3df8149935a48b1655aa6578e5bd815876f6b13e9f14d85d490c7e404d101a05a9625f446db1ee7b47f3941c7b77ec493e75aa7126cddda	1	0	\\x000000010000000000800003ccd28c03b86de9824ef0e136ae02664ed23d33ab67df62245fe2fbf960782c25934160c2aa505f611f532c811056dafba6902d4d2e85618079dcf21df68e3c1ce2be09087f1ce1590a0436c370584327e556152be9d81bfce86a6c37ef8fe052aa35dac2ef92b32b87e5be90c86e5328f33119481c17579029571f37fbc034b9010001	\\xc96c0a0e39915b754d853aeb62167245a9a9cc80b2a173238cddf31e914f3ec354559b30957a71b83c223f5413cc2f74a22197952596f028932a39b9ec4f0602	1661863391000000	1662468191000000	1725540191000000	1820148191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
164	\\x7cb58b92ee9ce615ff7e8c3bd2a751541c07343f1a04ed1f2cdc5aabc422496e194378ff7506b0cc81d1f57963332568198497577d8913e1b43a67cd7dd4e4b9	1	0	\\x000000010000000000800003c9ebc1068b6391a4527dcc7f54ba85870311303fe751a7cbf48bcdc41c8daa5d9ab9f2ee7961acf872a973ef1ad319767c362bbc3898c66ed2c24cccd9a6b0088a6e0267e1afc557d5a305c46ac4e522833818ddb797d36948928b73ec8003000febafa59406695d13e4af2b222f13aaabdf5434274caf7de02fec1511780855010001	\\x971365d13033028af8d19153743604c0c3b95815f7178bd534c41f1fbb63aebb5217b44ded08d36d1abb5ad405159ed6e9befbfe6eb315e793a5b1799cd78e0d	1683020891000000	1683625691000000	1746697691000000	1841305691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
165	\\x7d455d26cb27977c47ef757dee183102be01f501fb8e6a283573ebe50847958520c5c4eb3591a85e6b8cac744bb62d3e73805d48d3797f18eb13608658d7ccb8	1	0	\\x000000010000000000800003a1e33c583ad43069b2cf58850040a664c9c5de29f3504956bff6cbff6085768a1fce883466ec40a4362262c538a6f5adcf4ccdaefb9f456eb55491f5a05baf18f587828946f08a2b1f7a4d8c184529f3487229ff2d5fdba112779e5088c016ce48bb08a6634b34a667efafa9e181b6e368d528bd9adf9edafe30c9261fdff95f010001	\\x2ebf4861438afbf9d681dacb89a472f3042f3b8df3cc790fb1946eda2ba04c5e8be8153e38cbf9b8e8bdf095482836aee4f7dc6947395bcd3aa0251fccaf0e01	1669721891000000	1670326691000000	1733398691000000	1828006691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
166	\\x80410148420f0fac9ac282609ac65dbed7d00e8fc2504565b47b8dcba52d46502a18f1a2c7dd201ae2deb6c105d98501f3b2578ba74a3b8c70d78ede9988d834	1	0	\\x000000010000000000800003b16a449a9ee1e811cc5e4b6fcee8362f02b22ee7a2e2a9d572732f809fb1ca48668ee37ee38929d739bdee9754f716cb51ce52658e7da1bca2e5c03e03e7b0817d2198a9b76e191fc195220b6f313bdaee0b122ec85d1ec24a84a68aa62af6426175ce5584ea1f0501e98f87b6531c4f06389f065af7e3e7628e63aa37912e13010001	\\x28ae6492a16dcaf2c3360a6a55b9b2a577ea73832d7e9c10b19bd7a9945988fbef7346cab1b53311f971c35a2f60f0cfdf5ca0d57e5b67a66b5a049f1a3aa407	1686043391000000	1686648191000000	1749720191000000	1844328191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x8f4dec09da68fcdde12e94db02cbea65f1bfd76e53e3f1e308ec9b3fdeec10f9dcff2d08306933ec7afbe1c46ff9a3d2469cc4ae2060c77c02af1398ee2305a4	1	0	\\x000000010000000000800003c49ff6b6a8cd51105ca63ecc32764ed930126a4b450f5c04e725486634a683f4c590cc2242932726fe636daeaa2179ac0f6ff6cbe24c258ba4c47b0006c6ae4ab2682f8410dbd1b68eb7a31a5c6c10e9316212aa66e88558c9b8dfab4d2f0de84a1a3c31354ab90cff67276e06d9ebaf7427b133f3ae4cbd089bea7fff30fc21010001	\\xca14b03cbbcd3a8b67fb1707328cf438834f84d2f60228896a4364db15f77b43c47843020a20e71568bce66e0b7fa3bc272749a5a82cd697e9a378b6478a120e	1684834391000000	1685439191000000	1748511191000000	1843119191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
168	\\x8f896170a7bdb7f12d01f8e6043fad08b658aa64e1f64f127e31751b29e63f7343512f5b2654f09f3fcc778cb8e8ee2b54da74be9e577cbc59fb3d5fc8f96a0c	1	0	\\x000000010000000000800003c666d3ef55eb57428e7217b27a5a75f021b4c12af80afaeed776a4fc9c413f397711e48324dd975e45501f383705788cda5abe770334f7edf9062a6a5e89f45e98762dc20952f0c8bc8ccc9dfb9b6adcab44711cff07cf95a575c7ca67c1be7e47b4925201833c2c97e4c1fd53790553794cb15eefd834ef0d9a523b613b2931010001	\\x1cb7d23a30b529fc667414e5a12d816384c9f2c471fae92387a8702afec2c10b66d158ba7a69972c72c8efb9251d57ac8787cf34337c7a04eff4e9ce9e682f0a	1678789391000000	1679394191000000	1742466191000000	1837074191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
169	\\x90b118e2e78f57816494ad0b01ceb3864b5d74e42f53fe947acf0c19bb20861adbc4279ce1969b2e52ce456908942720217539361f7682de6e4967a3792345d2	1	0	\\x000000010000000000800003c60bd639b69b9d274020751c0e8c4386f226b612105e7dc180a4d63f1bad118c9d9a8670d8e010894427842aa49989d5c1491703d42d0c98b654cc8d62923ffc43ba84a4327330cfccf0bd91022a9bdad04bd6108a34f02e5811d91ba824742c0b06b1d301bffc15cdf988b376a398c7273c0857e03f44309d283c5b874eab0d010001	\\x76586f57acd69d3587277521238b7b03e0708087ece2846ee6d821e3bd41291fd400eaf3ddb62767d659d59e0a496f44cb3a56d761f29acad62889fb8a51880f	1686647891000000	1687252691000000	1750324691000000	1844932691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\x91f1a602a16bddc14c8e44bfc06d01f57dc31b87a5cb23a27837015e84debbede15ec51cca6445f9cf852e247421c6c72106208a50919c94eaae9ffb5abee6fe	1	0	\\x000000010000000000800003ba9c132fc559e56dbf083db5d42edcd3ae3723aeb0f262bf47ec16e1b8e995fea4fcc955ee79e7ec6e590a37d32ea25fb4c20eb04017d88d388b904fb24a3aaf341e73ca42344a20fd1e535a941359438bfe653e568d2929ebd04970fd0aa1be92a3d2a7eb802d198d58b8140f84ec8fdcae50fee49003c240e054eab247aae5010001	\\x5c66c28981defcaa9e130ce92ba58146b933f8ef6e0f7e27625ed1f9dd5989a3da3552dc460766731675e27a99d4d5482ca031381027b2b5ea799d212bad9c0a	1690879391000000	1691484191000000	1754556191000000	1849164191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x9595c6f432d311d105b5ebdd10ecdca2458073152418bdb125974df17cd7d58c318701f6518dccc3d7355f67076b03ecbc9e672753085846f5964331e40fd49f	1	0	\\x000000010000000000800003962a91d9c77b5cf3762632ecfc62a7cda4a445054ca848fdaa0d33dbf9dbc8a881b5a98fffb0692b374e47de14c5aaab22bf062bb918f12ee188f70d57b1abe38e8e540a7b78820ac7903e59ffc31b729cee09fd575aff725c37860b8756ab5f95cb777904972300462c51fc9b089c1e7010efa99f0fd4a4e3c59d51b22ba113010001	\\xce080ef5192ba2b706edd0bc6c5dfe5aa5b4ff03c4f91ae64776a2518122791a858e675478a29342c30bb253c41f9b168355a74c59e439d9416ab1cd40ffaf0a	1687252391000000	1687857191000000	1750929191000000	1845537191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\x9891700f16b5a7df884ad8a6d3633c8078ddb8e8c590eeb8ac75251b2816d66e9d2ce94cb3b975a8b74ef338543296fad7e9f4e3e7722833470d1acd0c79c7ee	1	0	\\x000000010000000000800003d6a6659fa9488da81d56b018b08a5252fabd626df127218b22461f2b0e59420d35f3a4ade3a050a83cffdef7833e0b615bfefa9faa19251c7960243ced5b5975472e5f1173f2d8f2748f437a946cc6d1a39efe0fc1398a55c6abd53d6e1ed244bdb105ffb8fe83b52db8bc00a5efe3c7abab916f87f1767e7f612d72c37400cb010001	\\x9958ccf5592b8e00534c5d26cc1c0c852d28061c13472d953fdd3e21b599cd6841b891f65a532e15a0d168e51c107b2d0e0e9a7acb720ef6fa898f226655520c	1686043391000000	1686648191000000	1749720191000000	1844328191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\x99adab36a536ec1ec2b9ad18ee67a3f22f57d0a29f55459c56e7a7f17bf0b615f4f5bdf277e5bfebb3ce116e33cbdbf23e224a63d87c3065ac7d91127abb2ff3	1	0	\\x000000010000000000800003e23f68f4405e45c7eb362cd19e5d936e473300feb85aa57247cab1d6dd33965aa7fc9426ce0ea4011ec7080fb7b33493490555af2447d4dfd830b84bbd27d5d1bcac3c19e461b8845601884e9e33fe9456abb3d4e94d4f9272da1dc34b8e95bc539750800cd6908e742dd6d51409729045cd9f47794f4a571237496b96326a65010001	\\x2eef294ae561a1573f834a30f8c3a4e6d51610182b3717d6374e840771186e1336986b3400d0d34cb89a279dcaccb97953ce4c8fd672a7544b8daa815e58c00d	1676371391000000	1676976191000000	1740048191000000	1834656191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x9b615e211e525798eda6f8c1b499928a648d58ffa2cb1ed38124ff72f78d3f63c8e78c96edf8a74d215ae0f801c1c3e69b1e6cdd76b4d978319916668821a241	1	0	\\x000000010000000000800003ba4a2e02aabc27c94d4cfc8251a6151ebf6f2597dc66c3b9bbf3098af5aaed1d800b138e3e97dba1f606d83d1257c896a3b4fb457b17962f509198c44af68e72dc6ad7e5a70fba0320927a661750dd08d6d85f82362d95873594cb5c735d16af1a433592d7ebbbcd48e4340b2b7789725de766662535f2f85ee408cb8f25d857010001	\\xa69f57ff8f7e973649b96b57f80ea0568b49c3c92dba3a5d2d6b43f5d1d3f287b5baa31aaebc0905e57cf38ac83e6876f617467c3910aea69aea6e76bf208201	1675162391000000	1675767191000000	1738839191000000	1833447191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\x9cfd718e63d64cf6978aefd2e73803b0f76f0b36d59660bf53b546908eaa4b4f9051e7036197a0ae4e7604b645457daa99f764f7ce05f61318ecab1b60f35243	1	0	\\x000000010000000000800003c00753a32be85b87f95be73e569cfec6ef6b2def34f25115293addd09f7562220e08386d44bb7f6fed872379e1f7ab12835ca698d4676af7842cb4a67561a44e16541d43e9c2601e578271e1073588ac16163325ae99eb53e6531d577dd21bbe3debf3ef27aca951361a870e14e5ea70ddb0f82725a81faf71e8e8d76f02ca51010001	\\xf462d92e54316367ca03e980b5b19c8cdff4479d9e11a1f00cb234e7c677013ba4f433adfad78aca2a01d9aa62b953f0725c5a0dbe59f2b04e7fc1143a703d0b	1670326391000000	1670931191000000	1734003191000000	1828611191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
176	\\xa1d1c570005b9141151b094bd0b80eae94ededc37b3276a503f0153185d14bebab3c7de7ef33cb6d16a7f35485d867786fb17771f956420609100d9eb9192f86	1	0	\\x000000010000000000800003f40e44076b4dfe30af0e6df5f146ce3d456df9637af4053a37a4816484852d3901c4e5d57da8b8a4973524af08bb54ee66160cbdf9c7544695020612a7bed6b707cac5dfb449f6aee4848dcc1c776ae594d562abd1021156775442f8fe359b793aa41bb5c32e5e6840cf918bed35d201e86b208331287dcb4ed97f34f6055815010001	\\x6965519aec881578d7f5ab2495cf158b7494eb20543059021e286cdcd9120aa32761388ca3c6c14f85e73ca185e0eaab2e4051b6efd4557f79d1f57332d5670e	1684229891000000	1684834691000000	1747906691000000	1842514691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
177	\\xa3f561652003d5181d3fd24c4b5ec60a1c3b26b4fbaf366cef8de45065d5afe1213745a3657da76a023c1279d6403dfc08ac5237230c3375d36164255765ddb2	1	0	\\x000000010000000000800003f65e2fba32c4082b0083d351617a8492e2518ae5b1e7064c992b267a3315caac7571144c87171ac6987e756d5847e5af2f90e2285fc50361be0311c130469846d5fa6834c132c763f5f6b2f3891e61592af3963e1ddfa3c47a6e6c638decbe66ff47089f1a1a4e1335156def2b4b2f6cfc7f20dcb928c5feab7035b67bcf7da7010001	\\xcf326742898871401f83e42fc3ca487ee70014575a985b7d0a8fa7b5b8273960886952a558633dd826bc6636eabd92642104f000a1f88b1cdffc78b07b3cf20f	1670930891000000	1671535691000000	1734607691000000	1829215691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
178	\\xa66dabac98f733a3fbb775f63520cbb955daad4a6ef407b8104ff420d0c023d005409de59f9ce402714219c8619d8d53ce1a499b149d4789fc99c10940d68f44	1	0	\\x000000010000000000800003fb0655019f39be6fab714bf765d6f5d51fce91007ddbee6b7c9d911dbd8db6cbcf2c16b7696cc6b1a9a8817c94ae6fa12402b4ffa79659c6fcf5728c95725dd4908705884b12d8a8cfde9b5d54ecaaf2f1b70154933681601f727635ba29e198a24c7e4ec6f33e821fdb1c493f83f41b5398b7c5f82a600f48a1d2427362df95010001	\\xb7e2d6511804f93dc997e2d7ab36472a28255658d478066fa1b49407dfd2872dad73859dfae02b5d9575f234354ae254902ad1bf98aaeb5a07566aaf30d8fe06	1681207391000000	1681812191000000	1744884191000000	1839492191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
179	\\xa989f34d47f67d713bec787faede97a5d68c51555cc9b0ce2940f147e12ffdd483e2a5676f10dd896d67ab0b5441db1dd3458b47fcc15a4bfb3b5e6d8d1cb0e5	1	0	\\x000000010000000000800003df2aa17c0fa75bb529a6ff033cb5878d9c67f0fb5f6655193a352ca897145ebe8f5f15dbf56b9311be75bb5db8de72cfee32f0e449ea56b012f6a5ef1f1ad8780a13abdd0de6f03e7dd51ce97f1cb781d05b322642b76e4305a5783dbbda7abe3f5d3fdec58f055786dc292a4f3e206dd724f7884d758a830db5fdbdca268137010001	\\x2de376931ffdbcbce64be665453792b20dcebb6bb35342415b0e7aa605a6c01a0a2af2ab671e99158f93664a744f0156ce590aa1ae291a186fd55fdff37c3e00	1665490391000000	1666095191000000	1729167191000000	1823775191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xaa952a461547aa9b7d5f21c7f6bd12e0d2f4cf376a97cfe7a5a48d6456ba0285ae005b611f03cf97b75c126cf29aaedd11a2e019ee43fd9440d83788bbacf0a9	1	0	\\x000000010000000000800003bd6fc26223f185d04e1dd189c11861c13c2245f76c7e255edcb7b5f1738c09d0fe869f6735b7cde7e38eeb9469a3e79ee586ee10394af42903230f944e2d22d346baa7be0cc152aed26503f722a7850125171af7b7c378b55e6e6ee43a63fc1703a08a4c6cf6aaa7c4f72e9546240265daaed8a5d435b008a4ffb75169582fbb010001	\\xd97f664cb929ff934f92bdd2004b89ceb1482c608d74e3aac22fb60e8adbd7ab250373a312230b4fcd1d7dcc842c06fcef4e656d63f216f53d5c3df2db102306	1669721891000000	1670326691000000	1733398691000000	1828006691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xaa5dff3c7fea43314193e419d40dbb73b2488c08ae5031eb537da1549deab0eecc4214442c1cf3102e460bd4c67a253024afe68d9ce9582eca1d71542560afad	1	0	\\x000000010000000000800003f29356fbc6f37b4b46f912701167854269ad392ff05ef7180df08e8245234876183f8642d44ac6353078a7838bc79cb6255b66947f8ae4b80eb0458275bcd62f841302e169a79cf5fcaa32b29be1f6a26f5f79c7a80919fd2ca14a70bd8c0b0b1734fcb5d14f9d4ea323c9d8d4393e6ef3012c74fddacd204ce77c06d9eca921010001	\\xa795261494ae7d95167858e0db8eef3204e9db5e7f812016d07f4af7411e39fdbe8ff335fd16b4e40b0b7af26efb6af610cd0860efe947cd59fd9f5db5d30604	1673953391000000	1674558191000000	1737630191000000	1832238191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
182	\\xab85727d1d0b3720220256302b56adc6b4ae29d57a287eb30c52c260e79948a44baae7d5cbada7adb6b27298e335f1633c3314be4f1cf6c137fe414618b2d186	1	0	\\x000000010000000000800003bddbd14d55a2150ffb0c5fb825b9e5bf04d3192c63f815d7ff3455d86a8baa06633258979490545e646c4e38371a36bccb777733e835e59e743b59b7badb434885585f1af8d68c4c02dce6617f772730c0f6167162d8f2a3ce70cb23154f0a289f1661ef0ed4aa55d1aa7dd78a6b2072330b4e610d7b9d51b5c01c6140e41321010001	\\x35e9bf060f1491eb8da7ea7b49f75c5907527c936d0d6d8d84c66487c63eaafab050bfe71b85f7f12a4703a525f6c5a72f917e91d6300c3482b3ed3193738901	1672139891000000	1672744691000000	1735816691000000	1830424691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xad75ae98ec473add3b80d70cb3dbae50fb40f7ef906f62261b2b935ad44c1f20240b2a02626762a08dd908b5e9e48a082cd080bdfb571addc8714353e8939230	1	0	\\x000000010000000000800003e08cc0affa6e1c70aebca45ddb4b4dbf3645961b1a031983c0d56fd82e44ad754644963949805ef4c05f018072bead9ed55f85b49c07212afeee27ccb74e8a4a279fed372c49d64039ba3e2a382548cfc4f1ef773c164e9d2e4e1a61c091c18e602f4bf095d673ad2d9d196782f1a6b00353c771d190ee67654a1fa25a7a200f010001	\\x70a1bfcc001b487debfe415ee72027412723ac91f9765bb8c6d63d08930aa86e7899519e035507f8b7f72cddc0fcad9d9de1d632313329f2a1cebcfb1631f804	1684229891000000	1684834691000000	1747906691000000	1842514691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
184	\\xb2fd9fc005e77d47c77884c30ea5a433aeed3eb0ea49e8ef4097a3567fd8aa40144fdab4be5988748ab90804d77f509df7b6e01aabd516092999cb40bedae7a7	1	0	\\x000000010000000000800003b9c54c9b218da7548374de746c34ad72f4df3720904f75abc1f31170e598b37cf648c4682f6ca34fdeda2425490d3e14499ef4a92050330434184a5c391961a6fba6b0deb7690556dd1f056514d504ced7ff0a37ef8e28185a08485849496348dbc8d43e44fa1fd506f892897fb68f40da4998fcebf39076eb8adfe2a24534cd010001	\\x49aa4dfede700458a8943115d1ea2b655d24e0f413174cb0ba6232e007d9d89b7dee1fd6cbca273cbfddbcbba6cec1eaf98ef4da66e15760d89e77e31eb20c03	1679998391000000	1680603191000000	1743675191000000	1838283191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xb431715594c68fbca1669680c17b5146aff2eca7e171f33c51c6f34a421ee31c0cd93bbdafe44fcdea5c687ae6e66c7529fd59052d896781b6d599bd8f712b71	1	0	\\x000000010000000000800003ba69b705d4af808c92493db293839359d1be2b621e5fcb25cd216cbbc63d81efe818348390c57b205959f6ef7844dfd201c6a8f9cbe405417003e7025a1a228d726267fa40061d02e5fcf692aaf5b6fef95e57f052ae8d87fe207cace464d57cc8da34ec671ae32ead817444bccf7b537029802e41ffbfb20fc8765703270bf7010001	\\x9bddb463082f2b956e90cd49029a6c5125e6697673a7e89ec20d10bd3be1eac774340d34c065a3fc031e63cc8d5dbb25e10d78e439238596522c7022e083a604	1663676891000000	1664281691000000	1727353691000000	1821961691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
186	\\xb4419f3d640ab91dbb52d47b89dd2861f45f90eb45c4175f240dea82c5e382e03404fa9d5c47561223488fadb9f566b8ca719628fded3237e68a5f6804b69a8e	1	0	\\x000000010000000000800003bcb9159ff738e8cecb5558b2d7fabc6e121d3eefc7537e09d378899068a504a0bff07805cccc1aa3ca4a410402a39c4c6aff61564948950041f0891645c5d95c7936830b8be3dab9730a6752d6b83fcfc7f722bb63e9ba713f3dc59d48248ceaa449e888b5b15fead04b139a2008f8a9d1a3d9ac103f0d797ff585489146110b010001	\\xc034b8285461246652e6e55dca4be6bded7b2e84a919e27e08d4ce1097eb7010bf8679d234d010693939b3e675ef22fc915725a0b8b412a9b6319f6e00575c03	1663676891000000	1664281691000000	1727353691000000	1821961691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xb54946403e95547e19b2c638a84196861ee16d2300d67451147ee31feeb39b4a817b99f98b00b26c6d59c5fceffbe02c12418bf669ac7768f407f9b06ea753e3	1	0	\\x000000010000000000800003c20b1032940a428bd5bb44f1751cf6cb92c0f478ab4e54a3ebfa8825b44cd5a2916a410ef75a8494643d096a84aee36a5df75cd58e1cc75ace7b62c348ad8f6cdba7769648432533dd4c51974fd604cf4ac5bb8d97746eda2d903c6b3ae64fcdcab76ace0de43ceee7b313513da4de7f6fde4f50a6f8ae6537221672491f2a8f010001	\\x1e2cdee2ad1e380ed8a42f5eda85f1a184277b0f5c835fee4ab804de0c736c99a74c387c137e27b0b5d6fbe9211500216db427f4b1651420e353379d6e321c0f	1683625391000000	1684230191000000	1747302191000000	1841910191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xb585562ed03cb762f1f2e26490c76015232c968023585ef0c70d17520a5e7d448adc0fa5a3c20c6d302122813581b2ebba840d6111a1b7dc2dc62acd2363c4ec	1	0	\\x000000010000000000800003b5d6ddcd50005d16f73cd47732f5e4db334f3888a28e0c51fbbeaa20e060bd91f05be4f283e04e7d2c1ff0d6224bf10ec5ab3a82ec6e5ccd993e3d7d60ee71c2dca2dc46c412c696be9965f9798748e0b63e5a45f471ec8cd409deb31277fc17f68177d67c576d9753e7cb47d3fb6abc2d150ef695442520f2b92ee47253309f010001	\\x387a290a24c8a7e3125c6734c942cd580fdb4899de8e45e1053955218e570af581722ad55afed5f6472cfed9624a5b2d32ef1ee2fb195e0732d95381a7fdc90a	1664885891000000	1665490691000000	1728562691000000	1823170691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
189	\\xba61f5f5a64c28f40c65c2c8dee8591522e684a7eeda0fdea4239a6abc8336fa23005cdd6c2e3d3c8b58c8a98fd20e36bb4c01a3609ebd120eac4d8fa767b249	1	0	\\x000000010000000000800003e391591cc284ef127f125790977116b33793d4d76b5daf3907e3fa36a71bc15dc1b38b700c446c9cbbf71b095f27665d4ca537a12594fc33e24876984d230c22be17f9807ffcd3e31b7c1f17030f3443b9e924d896ec9bd95ae61c7954db75694bfb0a98a4e2869f04e182d0b4b1f1779f88b2697b090f9f9fe67910bf7ca847010001	\\xe24decd913dfcdc34faa8aea75b8702500c17e4c8940aed82a0723f044fa515ecd3f18711b0bca01fc0be78ddb70b4f1028c0d80f2e22fed77925c1009d8050c	1690274891000000	1690879691000000	1753951691000000	1848559691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xbb71ce7f4fc17869cc04ac786f841104112e2ca6086dc8cecb321bcb46143e4c479ea8c1f57231a4a9bc00730ba2a1d8a79cc42c6a41bead83e67f20d7fb72bf	1	0	\\x000000010000000000800003c89c2feaad2e67315a4e69dd2fde16420ed763e2bd0c621eada086cf9e5a04bfe213efa075294e74992dcd8c56737fded3bb943ac757afcd7c884daeb0842a1832dcb4743fede7a35992046c1ff667de26c688fb5cb5d59fff9ab84a0f6f8e0c17741518162729b255b681e373c6f2ee3993a23e2a1414fbe43e0d0356f89e2f010001	\\x7452870cfc9f704a3dc1f72536430b655ca39db7ea6a48b32b1d2df42d55ba2e447f085b63e029b15390a19a4f038bc7d26c811c9dfa8bebde3e70fa48f2370a	1687856891000000	1688461691000000	1751533691000000	1846141691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xbe755df21425b45942ab9748d6c247e7fd4c4361601962ee0ad6651c6eb222995ac08491951b367a5377512b4d4f18bc3a197a5b1e32d8d5b8872191e72d4c12	1	0	\\x000000010000000000800003b6d19e927a2fa9b3885854277094bfcb15a3f5e302a6ee9d137d09cb27b44a1097d99d8fd34b718f738b1273fd782e3fcadf2e6e98f20fc5480de78374dfac68ac6e2de39648a52c7417dda38a675180f54a5f4c3cd0963d44e20536a81382ce3d905f7f725d76640cf4342af6161578d065e38dc731325167ac674a9d305a07010001	\\x220f6132ef2ae2926699626a19d984a2a851a467e28d818435d7a03ad338210c9e2fe703f8255b69e328bfda25f950335547957c139bc7df0a9d0b42fdf91408	1669117391000000	1669722191000000	1732794191000000	1827402191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xc275ce47693e0d15f76bcd49b438efd004b2c67b9db1467a913b6965a0f6912ad77c887151fa5f1863f636e65086c07de81e821a779a1094da22341ae0d364b8	1	0	\\x000000010000000000800003ed63a94a2fab13a4677f108fc44a83888984c05564e5ff21cff1fd58086ebda6cb64a61b39f9a0e0f654e1fd2fb39514a8ec56192f30fa6519b9492c9b5333df8f30038fb17faa5e5b05b98c167fe0235ffcc659ab4c4150b93f22b6b6c0157a1971d8a05960128865e0d1d7047738ec5dce2bed12e403a73ceccdb5efbff941010001	\\x127d530020f84405d73a219f6ee76874066296a381d138724df44b96e54a6209d40e6b46081a5b019474200cb61e067edf261fa01d91cdd7145249b6bdb10107	1691483891000000	1692088691000000	1755160691000000	1849768691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xcc41420d8eeac12ea5d3eb47d2ae77b8cd6b1e53d22a11c46b62d5ce98c268b21802233df8cf2986535d148d87adb7f318a171043bc3ff716ffe1fb00586ef54	1	0	\\x000000010000000000800003d00c2acd9861c8a47282d29ab51a99d0491eb6794163dffd8506d133298d2b04d86464824afe6c1e47cafbcd2d8b5b41891b76808076340fa41bb35190fd2d13f930530d241f409cc91440881ffa12cca8b1024219ddf1b8dab4312f2ebf3ff16b924c0eea3e4eb5c61c5aa1154e430d7bafa5835f2a000388cbdc2fbbf77027010001	\\xb758ed5d378772dae55298029cff15c18f049062372db106084c8f5f2ccc43b8e5fa921d1aecc7b374dfdd56aa82691877781322f3235adeb7524c0ce2338604	1679998391000000	1680603191000000	1743675191000000	1838283191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xcdb1a9956b174c0ecc956e38b789da9ae3fa5fd662bc7eae5bc278f7159f9547652de36490d74daa251788a51e6a666600d37537f1c99ae3cc6b2c5fd36959a0	1	0	\\x000000010000000000800003a132073ca66e119d4ac738e41abc170aae68182a7b10089566a36e8296183e25899dfd857141040f5079659b575a02760bee6cdb937a6257c3102ac9fc5c58e0d268450eb8846cd0713a535b0469ef6b5b1ce0ceea1c6f672c5dc9dacc2793c7d87f03e1b69b6cc70424af0eeb0262991712f7a014ce3badc6731c8c404c33db010001	\\xf8849042b207449eaede4dbba5c99e0ae43916ddbb2ca2593ab27a40f021951a911813f55456ac1d7520acb220f20c6c3113806d3e878cc9f926fa96d9823501	1685438891000000	1686043691000000	1749115691000000	1843723691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xd56545f649cc28124bed508e4b180259ff22ef6146eefd3392bc4bc2ce18d408c307a2985e87c0c87ead4f33be88a4e6ec7af7f64c820699a1bb12e2c8ca4506	1	0	\\x000000010000000000800003bab0421e004ac92af55b6a9df8e201edb8bbaeda9bd8b50dfd917b82b0bea160b21777fdecd407350baae42a918c1877b2dffcdc600b765feefea9edcb779eb99c4cacd88026fd40e4a62fe0bd929f4611c17d430dc4ef5bbc3db773b1552a4b140f2fe020c15695070a591b5f779d31f248d9ad6d635af9d0cc35749fdd0b2f010001	\\x8da426227a220c548f0d1b37c8caa472f1a11b30970159fd11175f3572bf7fdb633d19ee7109fab0c6c7d26bd560c6af825f47e8219cca4a7ea730ceb52b4d0b	1685438891000000	1686043691000000	1749115691000000	1843723691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
196	\\xd545b6fc06b6570a2c43f094c48ba5811cd1b6dbd95ceacb71f5c9a0384cd662ddbffd50def614bfb87f83abaec2626095396ae6fdf9503501518cb23885f9df	1	0	\\x000000010000000000800003c36969dc8640cd0a074df7ca5ecd81da8d646ef78ca722282d1b2a30f31580751973d1f69328894034674bca16fcd46e9e25833cd993faa2715b9d954c84ae7d3fed77f60aad95b96a2f936f382cedf9c5a8d1b68d003a88df0d4a7dbdd3e2726599cfd9ef56d60730c0a13a67673b8faceebe4473419c45c9123742c595b6c1010001	\\xaf169671d4ca6989c60e10ab0906cf6d2a198d117c450e88f1135c51b3002152f26aff9165259ac4cf79c752662572db10d61798db6000d30def83af17d2c706	1689065891000000	1689670691000000	1752742691000000	1847350691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
197	\\xd51d29fe6ef462b364bdc735ee85e95e447c6529bce734bb5324fc3a1ebaabc4547a171a67b36a85a52413719804796ce13c3dccc3dd1ec9ac921083b53d1ccb	1	0	\\x000000010000000000800003adbeebd2437c55c72584c69f6bd3623f1dcc37e40ea2349aed7560daa60b8e8f1fc510c56a058dc0fa40f2bc55128cb16765a2808d4999cd2bb91c6681be875e869f002141957bf05f8b1fdf47929eaeac70c53293bc9fb6330213c0fbf043a061353b8ffb454f7b949b33f642249a71878910d14e219ddc59e21d0895c0cfd9010001	\\x240900ca2b4c46a3c2639d53e08dcf6e7c987e2c4e317883a54e1918943e82d97b4e4646a1e803c9c88db5a75d49c6f841a04902de39789118c6ad73a962680d	1662467891000000	1663072691000000	1726144691000000	1820752691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xd7b1513f80bf50fd31046e5d652de072721a9a1cc7b0bdd99a372bbf3e361cb4e4ce11e19c837738ac1b6e62c3c2308ab067f1c8188d8c8abf2bd05f96689fd2	1	0	\\x000000010000000000800003bf9e884aa4ec601e1957ed68ee9fcc5f42f7f729a2443d491b17f61fc4ab20fa1d315ee7b80bb599b37e7b097aea882754a801a1c89d5c1561fbc6d5b534fbb26ef90cc8666f584eb02c001e761ff0928ae880697221727af8b23b8832e52c38681c0a2cabe5d31a3b5b594bf9b02171aba18197eefee3ca25612d0299806215010001	\\xbd0f7ff28e9c0a066fd446135f53e2b10a8e438d7da1e551959dcd55212a484d0aaecccac8490655a33f8770381dcbb9c361a2cee753d29ddbf03c043d344606	1661863391000000	1662468191000000	1725540191000000	1820148191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xd855047eab65bc8580758dc2578c7ea22f1d5933697eb5338ad081c9c7d3dc703b601fbce10b2193aacc4618028e27cb2c6ada1cc3827ce84c991ad2eacf3386	1	0	\\x000000010000000000800003d5f11789cfbddf3fa0a35290931a6ea8bdbb84bfff1e4c7cd3c04bcb68e698640d6c984a4865d75ad2aaa64c58ddfbed502e2825af583ba9a0bdebbeec502eba064c4907480e1841ba88a947a5e0d199a6fa0cac859402d7e0404e1ee8c13994bda90c7e188da04d45e29a5dc396ad204f6dd16b0e7c3b6894a3b66124b542c7010001	\\xa56f481e5e8473efcff564ddef010dc942676c65177a788cf4b85a24e88a0736a087d0759b4aaf9fe435118fd39ba4d2662922672bc9ff9e76c877578eafd60c	1686043391000000	1686648191000000	1749720191000000	1844328191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
200	\\xda45854e29f8fcbf7dab361753a0806b8efbfe3b2270dd428df59b8a6a4a25d146f329c4c8a370dba3c4f01e4e94a2c9e31e358a0146ffee6e042951921b792a	1	0	\\x000000010000000000800003a9d1edfe44851c0d140a633b25075330e6f5cb199fcc60480d6e0f6cfa8e43ddf56310a6dcc9406c27d4b91ffa637191c3ac90daaa67e1403b186d06a8f9b3486f07b842bcca6888519004da26948865826c3e2a77456adaede30c28e60581e2cc9ef3c2072fc2f2448c5147c7a07bde5f260c7dcf9260ba28d8b810c4411911010001	\\x4f68c8f4d6c188a852e0b8264fb3d48ba46e733eb2996c33f953cbbb61c24f921caf318178f21e1fa1f4870889fa496e4700c4c971bcb30c0e0e3dac841e550d	1664885891000000	1665490691000000	1728562691000000	1823170691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xdd21f27dbb5c2f6705dfe3a2364926e5121df5ab9950f882d74e139c8003c16db31737c01a4de60158f770c995482c00751b15397f0b0597ee47769a52bd729a	1	0	\\x0000000100000000008000039cf81f4e8fdb8e665f6c16491b6ba9c160dc5c13b2135802c3b8fc9298e3fa8a4ca1efccb7527cd5c1b985214590bf276266707f98811491b353f1b0197ab44facf330b8c14683e207c705d45eb0ddfa1be53049cefe5b90b3fcef7c27a0435923d2af94215a1c1a8c45a142a7bc4b4341b60ccb77906563c518b47c1fcb88a7010001	\\xe523b47734ddeeca7878bfb9bd77185fef13bd37a3b88e56baa1e845a891491ff3c62b19bfbd495f43657f8fd0df9e715dac2fa8b92e70621dd66185b9528b00	1688461391000000	1689066191000000	1752138191000000	1846746191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
202	\\xe1f14bd39ecd16f427b34f9393b5b92ce19b4d4aed431314b02331dda0a32a8dc4964f7d5e239b175c9d621e8d70f502339f2e132a71550917920f521563bc99	1	0	\\x0000000100000000008000039eeea9e1145378adb307edfa717e4c3d623453e179c5e1ed38219bc409620d2c807675c94397abfae3b98eb84f0d1b8f0095d409be747fde431e2c962f11c54dffa7d73edeee91ab630644d70e9d992a73c7651c53f881065190678228229665850610a57f941b1e5c18184dcd32542c6bb13b7e59c2c434d22c1d89064202bb010001	\\x8f6e0373b68f74dc85db6397223be974c51fc1e103f643a4d36f98de5834e1632beb5b9fde965033c36fce3c87552e225a0ce2974738e4b0959cf32d0dff090a	1674557891000000	1675162691000000	1738234691000000	1832842691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xe3818fa4728392ba75fc97057d4b4381cb19ddc6b6adfe423ffd972bd33d6f8b6fab9e7ab6444ca167fb441cc54b7b3cf23e855995ad4054e723d57f0d632fec	1	0	\\x000000010000000000800003bced4fa5f6dbf714e108f5e4f502763dd87f5bbd6adfb472f2f598bf2a0346dee708e8984902fa060d74bf13dadcfadbd267bf5c5a58c866edc244fbe16dfcfd95b210e502b166f089438ff2055365706a792c17d517f6dc7a28609f95dfc459d0212ad9da5c332e443c654205f1299bf97ce97deeecc5b301cfec816637b4db010001	\\xeca8212aad4991ba30c39ad429c46c214bbcf426b246f1caeb98afad3de73b21ad96f5187b4de8ae54475b7f9370e0017b243eef878a1f199bf9fb3b02c3790c	1676371391000000	1676976191000000	1740048191000000	1834656191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xe7a932b6de7ead6d793614e03f105363e7ae23be2d3446e0069ecbe9d91f01add4ced52684334c604a82a0a7cdbe371b93056d87300a0d82ed92c184f08fc5fc	1	0	\\x000000010000000000800003b92bdc4f8d4f8d90cb0fa704747f3fa25f0c192a3dd2675aba5ba9854111d25d6fd4bbb6ca1a51e8525b921d9d513ee53de3b664fcdb3eea19ed99aeb2e466fe083e6bcf2b0a19aea88b00d582a2668f0503adca881234c753b0a5e7d7a801d2f588297b3de1e986cee9d05c236b97cd5238345e4b99f348f0d80ea184984e2d010001	\\xa6789c3db41c03b5b64558389da4ceab391ddbe3d9d7524d2928acda019b1fe81ec4c841ce6e00b1c50460dda62cc5c1d6a23d8296418e9bbe3380333a212507	1666699391000000	1667304191000000	1730376191000000	1824984191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
205	\\xe829532e2d8187302eef667fd3638061b04673f6e049b003790430740a98d3983372ec29531b346a748ac3f7a9a144f59966123d2937f9a69e1330888040693c	1	0	\\x000000010000000000800003dc48eaf6626da25a45d2ea2eb714bbf516ac1047eb79ff3b128884a92e8fe2b7d41a6729a6c1cce31c53e1ab1897e25193144c2d5661796b3bdcc6964ec268727bf44829ba24bafde28cdec14b87211a0529bbbb5917ad9a33aba9ca3177d527a1d1f95499a06aeac8e1bf24928e3aa15411468c3ce8e79e9ce7f9a5b8ed8337010001	\\x840ff8d8473e77519826b3da7ad51093879e5e6d2469bd802d89ae714aec6a9a706d901a920f4f2ff1efa8b65d9f3c7483002e1c4802b716ac67c318df39ee06	1678184891000000	1678789691000000	1741861691000000	1836469691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xecadaa68c74b434d74db0e94669f2f34e0b11bd2cf277ff7319258327c1882cf576fb33da322ee0faa30c4c7c9d2c5df5d6c587cbb8c34484fcbe8327a6eb339	1	0	\\x000000010000000000800003cfd9b2abc29fe19ed31326d2d1660ec43c5f22a0ad6cca8aa44ceac4e9791d181558dc82629d8e64f313d54feecfb191bf192c70cc6bcc3ca0949a0f3073ed3066c38e39cfa51e7204a23bbce54af7cefa596d3c45b7eff0115d46b3bfedbb0cf68e9576bbefa5a9a7f65ae61682dfa67192d6d6885e211a918b057a35f62443010001	\\xefc26a8a38f3f9ba65b54821ed37ba76771ec5b08bc416dc40c4ef2150cd4cb7ff67e830b7b9b076adcbb77cb298508922e6217146068e4ec42593e17179b205	1672744391000000	1673349191000000	1736421191000000	1831029191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
207	\\xedc963654d31c0fdd1a0162ec940fcb96ab64a162c173e629ee05602569d185dc6cf04db88f9a42c2aee0af779bc76aa648fc3995ac327059f348cb7b1db2190	1	0	\\x000000010000000000800003c67388e7273db86ffa2cac39d94eeb0bea0a699e200831cba2365502971ef9307b301aaaab647ab0d49f9fba9e30a19e4576b7eaebc542720cb1bae58df3d9606b4b079bedda9165cc3875872d48b89f1e04543263f7e47ee882a03d361537da38b962a0ba9da9fe5c2f29b0cde8945ecd926418df226f6d502a317ba24b66c7010001	\\x9d1feecd87fb3d47bc0ae6e99a667b3d67bca2a81151b15a64231b03ebad4e8440f2c62ae1bd88acccd6c26484a692acce41a9483036a971eed417d4eaf42905	1689065891000000	1689670691000000	1752742691000000	1847350691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xedc92375a6522b202cfe67e688f3fd1a69095a582fe6f109901dbf2484a5a01b4094cbf480a58674fcae594e3e88791caa83def259bbb08db1b311af0e88a5ff	1	0	\\x000000010000000000800003e2848d6ee9fb4b9e31486d8c087d3c9357900db5690a2f7d1eb35fc663c5a2282d7b0e1c3273f56873abb3e0c4dc893aee31508daef905ce61ae699ad13f10bb31fb9a13eaa9a169595f8ad114b200e17046391d9c321d85e3cab8f51681c13f3718ecfb16860925b9b252999e5efcb3f3eeb5a2cb8f067a621d5a9efdd95d73010001	\\x437aac982e9084cd60a81d9378abc8b6449613b1e1da8ff2a64e1e1cec15d86722615f91e5f0b27c54680e1292fd3eef12ccfd5144284873cd0afd1a64265b07	1675766891000000	1676371691000000	1739443691000000	1834051691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\xf4e98dc3d9fe617ede89d858ecbc630d60ee2b4bf916b29b62dd7d27f15661d4f62d21a087513161b4bd01055f1a5e0d316c96e592d5ba75efe9c56f90d9c154	1	0	\\x0000000100000000008000039d68ed2a678ac481789f90a0d3f15b472fa41199bca4096bc8ba75c90cfcea7d56e394da4da851ddae3ffe5402592ffcbf64077dbb3a7ee3b0527307b8f414ae27f762f2d03fc5c54253c3d8f1d0079e3a4b90840e9778a147e4d77b48570b62fcd8bf5de2abe5f7af2324f78b1869b805f92baf9c1f5c290fb4ac7f10a80983010001	\\x0f86500341143de66568a2f3de57cded4f12821608d9b9ad60f88d146935fe33c0c5bb8d013884117c501d04b1481c86fe952fac3bfab699c92399c7dea77607	1663072391000000	1663677191000000	1726749191000000	1821357191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
210	\\xfc1157a732b6086a5bf2e1f3e37c41779c4b211ccef3c7120d0df0e81d6412774ae4060f43830f7d42d7e1332d305971d3ae6d3e60e790fec058d72ec811f463	1	0	\\x000000010000000000800003b722ac711d102dd5429c3b42777d6b2ac54c610b27d6fa4282e37dad99d36b4fbc189f60cebd05e07908fe5a3e2e35489f8dce06952ebbb7f97d45f8edde950476d88cfdd025b4069907502925cbff54c730ab90b3ad84e26a7c39e29c3af570dde0fa06f5e47d1c339ae2df9d7bb91bee274aff918fcdfa80d9ddcf891e4fa5010001	\\xbe8ca51a605e117b17bb60adf15f4c92ff84f9a1f19665046b7c31ffac908eb1593ef4f8f8a2a12b69f25167bd777728e97ec7224e204801a58bc0d04723f104	1679393891000000	1679998691000000	1743070691000000	1837678691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\xfea1403272c7116f72457b843afc27050db198460565b60589b8b4f76e9ebe7342bfbb6dabf503abd511563f96ca9a9a12acbf8b179ed16c40d7988b5c1f3362	1	0	\\x000000010000000000800003d4dffb806c246665174d22397435a87b8821b088bf7891d2e2d27be082fdb006a9a9715eb1e0ca120e94ec3884127eaa27eb9ad97934fa32d81e312d5632f3a23f18cd93026ab347397f0e42328d044f71acf53a6a07203271cbd7f1978597f7e7e83726a4a99978f9eb8098eefe5bb95608b2f25885bd954e5570c57588b649010001	\\x8645541a18e53b0c743ad2959c33de9878e3fd97398e7cd746b30b8231f36f9c192c5f146d3d17d8187c31ea088d5a9c3a751720bcc827a8017d8885155f5407	1681811891000000	1682416691000000	1745488691000000	1840096691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\x02daa97c6ad6a3522f6f0926dbe1e21dc2f4fe45d3e844bc0575ddfab8bebbfba8bda85d545542bfe6ce9bd88a006765ef70c2b0d81d36def3bd5c72eb4dd458	1	0	\\x000000010000000000800003a615500e9ee6bf3b6388c56cfb3563c10cd08a91421521aa7414113c07eedc2929146c8f57155e291d6da66414c249a9eb7e66fc362f29ca8c3157415f90d554827d9cd7eaf93e949d14b09504b47d228e4075726f1617533f38438cf9fa74661356786cd1b680b6fd93aaa037886601aac11bf161a8a30a37b12601510295af010001	\\x988c1c1bdb0fb7cb88982cb2238cd67132cea74727a6e7e85a341dba141a6031a7bf926c80e080e38d50ae869063a018debdca31de9d87b2f937e18842113f07	1676975891000000	1677580691000000	1740652691000000	1835260691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
213	\\x03aec6ee276a79aa91f8daa7df72f191c4186a0353ae4a7fab73b8e5788f16093f4a77ebba6b5d3bd8a514c78bb3bc3e1aa902a95f843c4a25f73bb22ae2313d	1	0	\\x000000010000000000800003d8c094ddba4231102525be86aa1a46310595c94fd5000f256531752b072606fe47829dad63359c071835166b82f5eb7c56ab480c38d21791e57f981dfd01858f41d7bfb0c74ee2664836d925301b3b154fda277693864e54920ba80c15c688b66be42b0c040d6ca4de1dcb3468250f26fe9a1a9d6911e0afcf8b933740d90a09010001	\\xcaa15759b8765bc925779be64abd36d414df2a30111a8df8c25f99f0238e128c6e929c360bdf0e1ddc8048cb5f0bafb3bf9dd78e273dd44f50cd9b6b5e5e1c0c	1684834391000000	1685439191000000	1748511191000000	1843119191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
214	\\x04e6d01f19e8f7a84699e1a9f803cac907a2fd2c236b77d934274316ad8f74bfb545b791c5f43057d57d29ebcffd5b08090e12220cda22e4cb35cc5fe9aa8384	1	0	\\x000000010000000000800003b9b1a17cb1c3697cb05a81104bf31e4e0851a3b3b24987ad862e899a591bb978c858ce7da51bea79f468d3e02f513e5df325da7a83d93cc3ab27506e586e8bdb00774cd9a12c939f4b9326c9509c49e37651eed90d3e08d237c180a8738fbb08b7dde809fd4484b15e845b2ade01d0587f5f8e0d7059d663c59d8db863de09a7010001	\\x5a8adf92030b996cb7f26ef351938a4928c18163622b181fb5cf7b132f4effea4d8c9395c355867c616a716814b0b015d6f4667ebe6d621f188d9dcd74b3220a	1666699391000000	1667304191000000	1730376191000000	1824984191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
215	\\x05ee6fdf6df59adb516da474eeb5fda6f3692a36fa10c6b49fa93331ee2a084af792a5f2e16d848c945f58816191bc22ed2b2aca51b8d969b001d418fe360ffb	1	0	\\x000000010000000000800003c28ddf748b677d0430498108038f784a6172aed3d05df3acb995abc737a37091db76242435c6452a26b736debc7cdba19fbdd3cc4718afefde9cbaedca249f70acd832714e9ef3fbfbdb5ac26af38d18997f04a0b90244269ac3a12a0359aff77975f6efb8b7afe8a3eeaed36e6d9417fdc3b26540052b6c05b8cf14865fcea9010001	\\x96d6603de47aa02e9b485a4617eb4e00dccda0a414db28ad16934efa29de7c74627bd8bc9a48f6b3add371f889b580b5d7ea286de6f0e53040ced0a5318c3001	1666094891000000	1666699691000000	1729771691000000	1824379691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x05f672ac7d69c8c375a612267d98267cf17024adeff789019997df79dd8f7447aac8189f3e4d1088cf5036220cb22617c1198b3d8321c05c2bcc592d61402f15	1	0	\\x000000010000000000800003afb61c618e2fe7191fa07ad4721630369b84293764c7ace77e367f01de2688f148fe3d10d86d30bbfdb445d8ef0fd51ccab7190dc5b1210bcef9fe97533e4fa023dc039d0417a5f25f42b05bcfb02ef3fcfd4720e33952eea5961ab9b563ee5a714cd2fa6febe1c2d36428f2f362f6470614b9151d4a2d15a413d8a466fda9ed010001	\\x1d5f0671003c92f4689d076f1cad889e177a254841071497daceb4dd1bca2a081427ec7541e0bda80c55be230b9aa0829b50b8ccb9c37b8b9c6724d2866bec08	1660654391000000	1661259191000000	1724331191000000	1818939191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\x062ae73a70031b74a8988a8fe3dc04fe52ffa184e218a1e183cb6586cd2bf2c919b6bfd32cf48d1ee3d4d229b90c979f34d0726025f1d644e2caace9390e3b90	1	0	\\x000000010000000000800003b8252e347543e94f71dd03ded773f63fc5760e1e92bfe864a7ea8c281899c29509cf4bdae5a7d27829007debf37f4fd6ecb440b93912c5a57f03c9485c5cae68fbacf9f0e2b322b8eb39ad044194969a52f74e33025266649136f4889b867906c87c34b46ef2879b0c2ebd6a8dca132f2f3c36c0d2a9e93f994b334476ef80a3010001	\\x960fc4af57e7cde1a8e7f71854beaf8d7a5e48b513189fdedc8083e1e3f38c3a3504fcf09d413265279b44f38c5fa125a58707b89b6b2a47b31411525600590d	1667908391000000	1668513191000000	1731585191000000	1826193191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x087af277c683cb0fc4510f34a93a1a193f075b8806f023e06fb365ee6113edf4ee25649ca08b5b89313b2b36d6133cb9875cd78334e9c692a16111d8f2ede049	1	0	\\x000000010000000000800003b648aa6a504cfeffe75c02466fc77281f55cf2c87bef240a98862bfc13508e5787a6b8453f199cf200586a1fbbe62f3d1d0de2a41c7cbc3916e3c257af2cfb7dda117b593f038811419cd184727e53b75694372294caa7b9841b0d8900aa0c1cf45dba47bbbeddc34c7f78c80749cd4304ee960802c2b2e2cd3a4892c415ba05010001	\\x093fb1ba23b45b2cc9753825ed3debe92afd3cc0ada50d9a079b5dbe8805434651764ac057af98836b877b4270f3c0357ffbff860cdae3ca0d33624811237b0c	1685438891000000	1686043691000000	1749115691000000	1843723691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x0de257adf8afc26a65b0f9750390c918e0020f1b2f1e627d1f540555699a10e0c2c947552cbb4033a9ae1a858a6db7eea586a4a9a8cf0fbc3465bafdc6373046	1	0	\\x000000010000000000800003b707d729b0bea28541ea012fbefb0a57a97bc6e73c190d8c1e20d6a673dd9729b87220ea011326c0b27c7360f8288767a223a63319cbe87f494a28f5c8643945e7bef6c927379a568020a4b318cea5fe677b0428270f54870d0cef98979515ddcdf5a60ee29f3d46bb06eb007e7dcde18594d70e2cfbfc822bc36ce3bcaac27b010001	\\x9c47ac401f04632119447821f8a037a50bea2e501574576da4704479a0a402ee7510ee61edb175acd298b09b291e8e57692cf4f03a72e75307426d35a6c13203	1677580391000000	1678185191000000	1741257191000000	1835865191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x0e7abd9f150fd897858b9221e3c9a8cdce8e8f61eace27475215caaf8b6dff34526783f6c78903d11ba4293f294662b6dfeba844de8fbcc39eed0d97256b2149	1	0	\\x00000001000000000080000396f4dcd8a9b72799127ccbb4e4bb77a19fb47c1dbb70516cf9adde4e9d99d008fea36327a8bb207932c49c33a0afb7a3d38d416bee1b8cf67cdd9d02a59e84839e2f2730d663e453e5a7a59cb9b9660adc0a48333ba47ec1a175fc8bbcebbc2ba83a3d2f1952ae13aa83442da1c356aeb39efa2caeb44b5d10a4d324d29347eb010001	\\xa7d17b7ff36caa465cfab9723ffe48ebd6cf2391ef5b067a559c70f05b76cc399c9b2c097781645b25c139c862fdf0b9df24c851752c0927c93ab00d67ef960f	1691483891000000	1692088691000000	1755160691000000	1849768691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
221	\\x10220b1f5a1bc8737a408d6f7185df0f6e2a9c210df9a248c219bdd0508395cb4366b3b6d5919b5152302623e0429bfc57e78a640b7ed9faf1b5726f11ec9f1c	1	0	\\x000000010000000000800003c1af848453c6f4ef97eca1af562f39d13facf0addd3fca1849a4bc36bb622b2834f0ab6cbf56b938d12affda63156777c521e4f9ad09f396cba99781460f8b7a31a62dcb2603aff7abad91a38a32f8412bc744d95bfbba0fc14ef267a0da7a069754f0e6e185f5738e0ba436e1ac3b58a191678b86f0d724d1b9935d6a550691010001	\\xe61aabb6f362a030ddf1537d9132d27546e055f2830578b97092d5207e9c33f3ea70561f2b1c049bef24fe98d07f0c6de0387003708bbed9a9f9cae3d5c3a809	1663072391000000	1663677191000000	1726749191000000	1821357191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x11ca6b5bf71d52239743248774537c205b8b7359feed4fce6072853c3330c8b580fdb73bb0c9248e6f950afd9a4e98297222f22d75ebd6e2c29e859f53219437	1	0	\\x000000010000000000800003c71935df1cd8f675d6592d6a0190a5b6438a70069dba88e97b9134fab9c926e67e8cfc1a5524b2ae8077333121d997d333634f2d6ef56a99f340c47b3d694c1c7ff4ca102b4657978d804ece455d86ad39653aae01c6e07d4f8aa1c976aab8aeb5148ca5dcaa68cc47b57c45f673de4a57a670b30967135f88f6e41a95367bd5010001	\\x7a10d571ba2662db57d81110505e7281ea06a52d0f055ff12b4faa98208daa5917fbe907051bebd5ce730c84ac14a8c3a595e30ca37a54479181b82306359f05	1670930891000000	1671535691000000	1734607691000000	1829215691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x139693a2a59dd24f6bfce8c48d93fdff53796d1815521ebb63a43719cc6e272991008250bccbfef351f21d1503e923d62e3645dafb8b73b6858508e3e0c9b53c	1	0	\\x000000010000000000800003af41071eab14cd4c742443eaf7a114638d5229f61b4e28e5401d8c6378fd19d065cbf3c39cc14fedda747bfec5c5b9273f05d00402f4a58db2a29c88964a7c8cb33711283006c3bf2e0790e21e340c859897935913959b0f8ea4b2f0b18ba2487c0e5e29a74a15ae7ef458ff93bf2eeff5fd8b3999514f70725f705bf584e1e5010001	\\x552e964fcb861a8c3e196b488293ef22c5e64ac54ce12f8a9d6e654484a1f36115c6854c354f9d05ef6f663b56fb2a9748f4942b0273bb79b7817fa140be2d00	1660654391000000	1661259191000000	1724331191000000	1818939191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\x13966c6f2ceacd3185b6a41906bfdb3e3195286ef261ae2e8ed460656a5d59787e699769b2528d5d090087366694c32a186109aadd3c45339637dd338ce33b71	1	0	\\x000000010000000000800003f087957edf94ec8420b7deb9add96a2fddd18e2cccf4c77d7ced6b0eb54ad22eb98c221a52b796091f9971ef02999ebf7130fc305737f84aeaf046c6c2615383f3cb81f7c5cd6d322df6c4e393c4592790fa4170ab8d05caaffc721f7dd5483ed62357674ba190da4e41b5393c60f6621106d127350a98d7ddfcf6cfe14b44e9010001	\\x9641c781802407bd4812719b880bb7acf28d8ba13700e0f042a9e7f2c4b451567f1f43256f8aa3eecfb44f4bbcbe3ef8c186dd9e4879a43d9691701cba798005	1684834391000000	1685439191000000	1748511191000000	1843119191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x130a0c2f37c7395e784b882555c976e0c106a61920aa56c72ddfe4ad0fca942783b49d1aa67856db4bb9e9c43460e07fad4e84803dbd1f49f058f58fb1b2bfd7	1	0	\\x000000010000000000800003aa16efc11ecf67dd51262592ef848bbbb04d55ba6a4b1ebf8926f7b5c90d9723aff370537dd14218b813b17aaa6ab46187b651eb7c27f6a78d771967a250325d91c58d93be3dfceb1b18afa90d81198fb8309ddb051f4a9d3411efee60d55e7e616897805672ae996c44cc88bce144e33089733c2406efa50e6c2c33a2c4aa1d010001	\\xac025ff50e962b601a0983d8b714b6f566232edea6aa92db1b96a9a7bbdbf4d9e9b4d8ac958e16b5f38188b790b463dac08fe018591091f18c898abb8be0200d	1677580391000000	1678185191000000	1741257191000000	1835865191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
226	\\x161a2e8c4d4d35d65c7ed55d5af1de161f9b32a513dd910a4bd65d537650442e7eb86d92c293a93db05c791f12ca3f51928161eca099d1062cd784725cc10f2b	1	0	\\x000000010000000000800003c49666347d7dc4caf206fbf8ca09d970d604e369d84dbb30eaed6fc2a7461d64e5b1de935c8eda5b4c611d274da550d686b10755d5d023fbe04f2e23033898c1fb6be6083c3270b2ebbf25ac53714f2b436fbcce59670bc672490245a499bc1c031523780eec827baa527d02af7f87ce1ba07900f16b159f5a3e54fde1c1709f010001	\\xe22c424d6479e6ea9796679d298db9ab4c1ad5175889327b9531c2b9aed1cd8417781e14c455a7d6fabd9bf7d42246607c345be90e87502cfe55148c2ef9980c	1684229891000000	1684834691000000	1747906691000000	1842514691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x1702c38ef33bd366109b7640fea484d5fff9378bf8b1b4f2ac6bc143a71634777db0c76dabbfe73c6538a7bac74683ce3d0cd8ff91322da508a3bcbe475bef35	1	0	\\x000000010000000000800003bd90dee07b4292720dd789173c8aad309ac1c2dd257ad4630abba7e33699a1de6d87fa4c020e0e26adfa6ef3561ce56425b71f2ddaafd3aacede18d3fcbf9f18a48de3f870a8c043b47d859652f0a9ec887ef1f62dd699ae8b3bb71778f47a7e174ebf45ff133f7334e01a1bb90f9500df1d16d330b38ba9e3a5fa5cf563f17f010001	\\x1cfeb2ca5df15250f4b83bb629ea5f115f52523436d885dea04b8a28cc2c9c101483c15758624cba179761cde5556f71adafb419bb7455a25a89374c5fa66900	1689065891000000	1689670691000000	1752742691000000	1847350691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x18ca8be45fbbc576c9880d3100de4534594836f9837f0890a29de489154248553ed3dd2bebfd56179ef058d3eb210978fd9f557803d885d879052b4bb966a0f5	1	0	\\x000000010000000000800003cff7264ebf4fccc2672de8c6da89d05b4cb6402120990ef0ef1c52f4a90872fc2ceaf4e07b83576faf9d474249c897378a9c0bc88f8a5d7962135247b2eea0ec9cae82278278a0b3a5b80ef3bdb2b46ccaa9cfd9c621ad81a8e65d56159161534edf98805f8f0b0e2e1c1cc62fb6463c5b771ed930da3c0f20ce1897216f3a69010001	\\xc8b966b498d0595aa75acf7ab2209c80216a0d6af477ff91f2a6bd6d9c7ae9a07ad771a3ac23e2a4cf883bb0368d46e023c438225f4729dee6ea0a701ddc520d	1672139891000000	1672744691000000	1735816691000000	1830424691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x1aca5062dfa1c5d40dd9c0f99e569cc4de2337b6a3f550cc58bc0540a599136a741ee1bfa62639dd08be32fe45fe1774f74a909e8c1da6dc59385f04dc46efff	1	0	\\x000000010000000000800003d2e8963f7e54c69b6df1092fa22706892a56d32a94f1415c48ff7dc9e32515987d25971cbce6599972659ca4a07109ae49e68c69dd26a50f041d33e49f0d8d24b574f86516c9f6e72ed92c530a951a1511c2e123c58b7eefbdb5dd448ce353c21f6a108a1f7539b4f9e882a3f9f27681255725c4b2cf86c7930f92e1d1922723010001	\\xc3bed17925941dde4369a9be99babe962c8ecf3d9edca4f69cd9e19d0414ada88c73fda5fa23248fc8238d0a725d5b2710a619a31f46601e3f5dfe3a89170606	1673348891000000	1673953691000000	1737025691000000	1831633691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
230	\\x24f2f8edcd42e069559e7ed78584f1d71b2be84fefa7ae26ba667736c9921a2f6f925bf92df5fe9da8707668ee31fa2179d8b54d525f982575b9459238f43c1c	1	0	\\x000000010000000000800003b20a3e784a8c41fbffc76233fe35b28b1960197942e229d2c120379e2d17a98ce0cd2824e7b78811dbb4867774750ff94e1c6850f7b01c73ceac97e2e5baed001a24ce064e7ad06d6a6f5985a9e50df25b877f7a1089ccf08dd1f0725499c54a2043575872558208f97c8407c196b921bada146eb0032ba6ec3755640dcd96f1010001	\\xdb6fd27fe1008f9471c3dec0f8f53f5c3edc3d68983d5a98cc88482be067e1caacf3840eb1a06ae2ae66c7aa166436f56714170c779afdfd04d2fbfbe0fb260f	1681811891000000	1682416691000000	1745488691000000	1840096691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
231	\\x278ef9ca11e07b4dfe9ecef86c4a6f56b3ee824957841de6440492ead520ef7a8392bf199797cfca8aa0e81e28ffb86fbb06e476f0a9de4cbe768adf03f1f892	1	0	\\x000000010000000000800003dfee2bbd5fc3e6a28ded434a0396dc4b44522fab1ee8038116f87c5c9b6727e91ee71139a471ce41ebdb8575d4d824613566081aaad2aa6d4a8b2c3b2813bd46d15ca153e41f67e5dd38335fbbea9bc1a7ad31997b199441b5c40cdb2eab2d7cc5727fb90de62485a69462ecc9056285417f0fb9dedf0d029d306a13b3d5c443010001	\\x8c73b2c6a55d4cf4055818685188c35a6dcf47f6baefca01bc455438c19106d31ee340866bf4cfd88a6709c1ec804256e67b68d33138f5e89973406873ef2608	1661863391000000	1662468191000000	1725540191000000	1820148191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
232	\\x2a62aab42a1fb09307064d55d62157604c739e19e0b6e9ab8af8d4c8958f42029003b9e70c9af1d94d53e63a0aaba33fc084bb04a892e82bc96544f865531630	1	0	\\x000000010000000000800003cc46f12224e1b26d96db7ee9d6deb95f49dbba253c110daf8127279e17a6045f3654865d084a097f94cc22361d1e295582f2293f9f9dc8cecbe33018c067024bea20a8757158a723f438923f963206c795fada0f1f8a174f5610978c9602bd8bf0646d6095504a8ed54b02d48aa75e0df21dc136e58ad1ff01b27037c06ac275010001	\\x334321018260e9a0791f6a64da0b93d5636a76e1d4fc6ac0a1eaad4d02422ffb2b6bd7aee45059445141cc925a8acf5454d9f450ff6c0cd55dc733e6e699ae09	1669117391000000	1669722191000000	1732794191000000	1827402191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
233	\\x2af6039a0e7f27012ffb1366cee755a7283827114c2c97891291d8f0c3dc2b84e1801194e85926073eca1e93114b74246c6d3e40a58f582dd5315454ce9b20cb	1	0	\\x000000010000000000800003c6857ce393e4b72608c040bbcef3975745da103b8acb447efd9e275fd6001c6842c046fa2a289102946239e41c000ac898e322c22598a98abe6fde5ea500370bc793c9172e482ffcc204afc145715de42ffd2b65a6ac8013c03b1ba5a6bcec95d5ada8e21768cbc1a2820cdded6020b572632bfe7220c0db291ea0d1da516e97010001	\\x055e5f953f975eb18517ee2650c1da25c746418d34183d7622152b7ca3e6dd345eba2f57368dd4d385c600273327c73dc10bc345f66712353e0f7fa5b7b8e80b	1664885891000000	1665490691000000	1728562691000000	1823170691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
234	\\x2abadb4c74737366caffb3da9d7a9c449d844474e727d06ddc023fb3e41abcf68113395ed259b0aeb253e90e0e3232b558535fa1e927d069c58cce09a87d9ad6	1	0	\\x000000010000000000800003bc19267ac43d27b2e47dd745cc41009e60fbbdea2daf4de5715b8740a192326c614b963872f6653d42c5da5dc28fb551992f71a4d0457cb10d1ef7cec86370e070cb0f32c8e2f03c9c6c8b2223ce7258972bfbee384d9e951e7e22bc1c7d8cf62d761c3ff198ffd7c387027cd78ff1af6e31ebb60a187b2ea913c3d402bd1193010001	\\xbd47f07ebd293e275e8a8054b1d58b6565a477fcd6ad135094bd2abf7413e8872a2b905fd185a60f027d472eca0f9650c240f3c9b65c0652576b72362ae52303	1687856891000000	1688461691000000	1751533691000000	1846141691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x2c4e57569767675118af4cb51f59197faf8bba94161593ce182c1529c2225200aded9d608efd68cf57ccbc6681c0709ec7a1d2dc74003cbea63c1fa1d6ebf401	1	0	\\x000000010000000000800003b7d89a3244588ada5424f4691359cd858aa1622d0aeacc948d6938b2a05db1f7af7c10d1b1a9445d0081d802637c745c919160147c263fe925c2d442a0c262d4806c706b3b42e906a720bc2018b20b3500b31bf17713392b26fa35acb0da0ac8ee535994cb6d3a781030df894aa87cd4069fa94964bf45a3e4c88de9347a26e9010001	\\x38172ac2b0b38763c00a7de32f78c601752227431d2c0f508df8dc30bc4b4804b61c5f680a5d67e32a7a63e016c38493b0a46a257996ded9f5b3b6fadb1a690d	1674557891000000	1675162691000000	1738234691000000	1832842691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
236	\\x2f1af6f88a6cc1e8c5f2fea3cacc465c32cc769cf2a32c20d7746a3052050495b09496090c3610ab12c04777276d875bb7ac396dbfd3ede3702304ee0cc2b79b	1	0	\\x000000010000000000800003a3479ab1784bb193db20c8774c412df4b79bea5bbc5651db9573a66f38f25bd168a65213dec270bce4a4d101f3f758168f1b15d38e3223be3d80eaddaf3aa70a9745908d22209ceb311dd77fd84353c587b17c2972fa6c9192d5e8cddab46d448d08f7fadb56d2b8b762ca29c8dc6946177b117a74f7c05fd99ecc880bf479f9010001	\\x5f88e77e98f474f2785d001a005a6ee8bd1b7ce9f890a2aa0952ae5ce48106db5845a6bfc9bcc4e9aadd7f85d35c8700702a28b441e87e8a56108d63e8147b00	1672139891000000	1672744691000000	1735816691000000	1830424691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x32aae91222e4f626b2dd6f9b7a32d5007a0214e4bee506dbece6e3382f2c690eb517f92e6699f005657f9759b88ada2ced52c88c08fa5781d1623b0ae4fffd04	1	0	\\x000000010000000000800003b777cac8397d80a0b71b66bcf8933bf8aba2a008c3effda4da24d24dba75b691f59706eb7ae6a030a3e0fdf1c56c99b1eda47c60445a27ae3517529d4025f6779913f28e4bfd77176e1c2efe4697ab946d0ddbc67ecd4c8c653cb5e82a198aaf8e29699346900855fdea5028a0fb1d87e22a0b54af5896c34c1499a37a0f9cd5010001	\\x56589311984eaf07445e2d08fe6cbfb963e451c4323f4df9060258b7956748c827a888defdd637aa9654609d93eb9b9c75044ffc96d0e0905a3f57df06054707	1665490391000000	1666095191000000	1729167191000000	1823775191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x33ba049942a82b48a066acaa9d56e07ab23972f5eabcf720cf9f56263946f71a80cfe1157b3112ca12de21d26d5e46561990f3ddd546e41033128029a81559fc	1	0	\\x000000010000000000800003a48931209c971efa58017df57c87043b6dee06f69331a6af7388d73ec66ad94957d17f171233f3881d7fabd5b4fce259ef90d1e3d38a4076ed82caa6646682ea9f2eeac4fa5b9c77f66e02bb53cc4b36a240c63f468f8181dfce0af19cbcb974a9b388ec017156a121926b48e20c87ea44a95a1937ec747c1b9adaa702d1edf3010001	\\xb39405e6e62255bb2b4929f8c3c2ad645f262b96cea1a7bf3b160c1339d5c251768b69b48a6864b67b55d71a5f8805653aed913e5805a5f0b6721c0b63af6006	1687252391000000	1687857191000000	1750929191000000	1845537191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x35820812f41363f4248221046ff48da031640db462a69db35cf70dc8786978955cfcaf19c6f3487aaa12800f653569125806ffb969a4349db971a7766c3a0117	1	0	\\x000000010000000000800003c5a5c20acd50b32da96e479d95d755765a42761314f249dc956f660fa035d35baab5386fa33ba956784b49510897f62abafb2d4dce6cc5c8769bc125e06629162415cbcbae518af027166e7e0685b5f3899803fa36673d649ca71077a33339e68532163490df0ddedf525d940877055bbc1715ed6562ebd5a1c15ee602aebbbf010001	\\x498c261d95d5263f6a3a846861e2de60e8cc21694ddd3662f238ff2c9d7d66ac3ca46fc115dcfb1025558c4d5c680a32ac4c04b45fb752ebbb5c5e11821f3b05	1670930891000000	1671535691000000	1734607691000000	1829215691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x37023805e4d2c7882d76d9ddb9536674d3067fe3f77a2462950a6ad6607c76f51de4f9442729722f6a23b41b71824f60917d01f2df68ebb333360dd49ccd62b5	1	0	\\x000000010000000000800003b61cbd6dd32f03535a453d7625ac51bf6fcacc6f579fb69b32f530cd64e9e13fe27ac05da8441b0ca194892e48e9a4d1b433d0a5f055e53b59c933abc20de5b97769fd7ad9824696d5df741641db17f805245e8f42a24aaf9ac033ab25ad763451f689f42c32cfcceae7eab99eead3366937d9a3f33c9a491356cb83b747c77d010001	\\x137a105ce8bde36ad83eef902e5c470ddebf5e65d2a313fca9ec6cb410a87b11f19dce58acb102747f3eef4391472c583f75cf9d0a1783ef13c5e9348ba85202	1664281391000000	1664886191000000	1727958191000000	1822566191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x395ea34609e05b76d523f29a740a0e5edd6e512b7ba9d45275322490d98647b58436c60c36bbca11387aa4d54f2fbd213973dac59ce1e1d215e004cb13393bb6	1	0	\\x000000010000000000800003cb74daf23524cd4f6cfff8f5dd8eb0892a0d705b919581740437a93209ed3b4d7ef4de661846e1425c5836193c57f8fd50fecf159a3da62cf6be367c52f9822d41b7f51674234e493d8f99703f0b88af83436264606d9fef44ac33e2c6c24f7743b9bc779f6843f658bb9a5673e55a0a50fa72bd1c7f243784711cba69df472d010001	\\x80726e45bc0e0e7c55e368a2a9c6e4c96d0dc8e683e19c8361a3ae9b21121907fbbe9c820a4f2612e7f0c5155d26a46444a7b8ed707e17d93012c2d798f86a06	1664885891000000	1665490691000000	1728562691000000	1823170691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x3c62f2864e8ac12f6570d47d5b1cecb97ce40ef38bf1fb75f4509132b36ce5cba8ca2eeb0645dde434fee78f274e56e44e7adecbec9383cbcd53585e25fe8d14	1	0	\\x0000000100000000008000039ff335162167f0b9f3fb9127820a2f55dcba7e9b65c61bc033213b5726a9340f9211705a9a8a729d60db4e4ffd7deb96d1199735b325f244319803d8a1c5e290c7e5c7333cc7cdd1aaa3012ab13492fc82c97ef0136e1d207e4f342f944afb864bdf586c7a56a7efc6faf7d3e9749580e3b161f03290d618a1742c1bb6f6e371010001	\\x068d6e34370b40e0e19e02cd9c04aa4c31bf3af1afecb48368295c1bd084645f346f2b62073af10f7cf6bfb2fdeffc3e38634214555a0a4f315ea73f80f4ec08	1691483891000000	1692088691000000	1755160691000000	1849768691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x3dc2d2806594de63bd4f88e6b47a7030231e5c31cad6fd439a3031049e425eef4a5c37500d0637b9dd4d184b0189859f3b2ff9f9b31314978a70d426b67a3926	1	0	\\x000000010000000000800003bf4e7453dcaedc3797cf031ff5c548ac5c5479171e9462a54ba76b0cf0f6a38ff83e82a8a614b5ea795329bab46d55b75c0e11af989e3391be7b5e0bf5c2340b395c0f6e72d6f0d08d4cb3163d6792db96a536c73aca0df8f26ff2ea38334ebf90be2d2b9ba0455a08c035d65d5c18bd081e6c1f2c4923262cdac39017668185010001	\\xe556aa46ba1fd0a7863c429bf8e237868c362183cc81e64e4937766448c742dc706669895f6cd8ff50f31f579f0b1746497cef981da7603ccfa38e6d95bb4e08	1667303891000000	1667908691000000	1730980691000000	1825588691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x3d72ad903aff509f19bbacad1254a2608b247792220c64c28029c6ffc3d2e29ee4a8f135ab99ed46d0101bb69c5ee3ca44651e6e67ac27d7a1c22d80cf9d28b0	1	0	\\x00000001000000000080000395700b0051eb9e98aa1233be0c0373bd84ee9f22eab6121f8b943759d57115167d5059663189b2e1c73b44f1226fffeac92564aee9f9b4a4ca238d3eea33f116daea8b6a53f7beb0ce367b8ceafc83317469818a8a8ec15027d410291485e0f5488796e09bfaea2f5d74e36972254a8693bc312087e0cfb912826233c81198ef010001	\\x23f5a75e4c7fa00e147251689a4cd73537a4fc71294600275cc898986c68feb4ea349f2c22c69a6fad20349d1d58635922486115b9d26f92ed5f3bb6cb4f9003	1676975891000000	1677580691000000	1740652691000000	1835260691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
245	\\x40ba4854f2030bfcff2b7d5673a0694b7adece165983d8d7d7a8696a7af36f5ff34aaa2da19e7126aae8651877e1bb8e196b2f26e2c8c72a6152fe2ba0429801	1	0	\\x000000010000000000800003ef30bc6e7b2b7f61c613b17c8f1963b43ee69d0eaf95c5e8830206687d7372a76c4bd0fd6aad037d9a68625dc779b4dc22d7dc640324c7d3b4e89635374a7ee4dc148687982464603668765a7a6884082360d7973eca0e674da07d8048351434c9c4143204214981b8e60b52be1c3522c90e74895493ae4a81d0c23c0ac72b07010001	\\x84ce3d29c863f0bcd7e35edbe8f8b86bb317a21314a13e205a81cfba0e955d42cb6e997d2b69cfb7a2df7d9d6ea119da2440751bf0410272d5255faded72d00a	1679998391000000	1680603191000000	1743675191000000	1838283191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x4112f75eda90cb7a53559ffe9789d4e6bb027567f9f975e07eb6135e8532c185eb17ad4a3490ec97b1c8e06ce8dbf419f585756aabc9d5a12a03400ef041a8e0	1	0	\\x000000010000000000800003dc0365f5aa5843c5b1a5a418a8bcd40c5f3e6c0542d945d6957665259c3512f5e60686baaffd2564495620d67412ad351e1649a8366b462f785da1a5c9d765033d3c22a8b415010ea2f2fa0125bb0f3aa690d9321ec0c4965e8064d58f9f92f408f22aca1f06a9fb13d010d453399dd70bfe394bfbb7a7b88c8f0ddd373a41a9010001	\\x75d83a29b475c867872332c6acefcdea2c59416db570736e38a474c63bcfe6e0639fb053fa1fac4ad7038695dacaf3664b09372fa403a7a2385c508835484503	1664885891000000	1665490691000000	1728562691000000	1823170691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
247	\\x498e0e9ac007b6de4e1b3efaea35dc72980978b6eef78ac4810cf7204d72b15b105882bff7a19f6e0432a073f2d14ec06ea03019464fc8620003b75e8771b9da	1	0	\\x000000010000000000800003d42b12079549933ad3c4166a22e4c5b31cb3dee2b52656c2687b591140bd03cf54587a0f0ee6c2dee0935ecf7b0914d1f586eeded9fb295d31db39c339dbf4454adefdd1acc0db0676e4e36074e9458eba63aa27cf50b384287bb557e1cd532f007ddb6024ea69d0701977d4ee0ad7d4ee355671dd08b5443875d8c90e4faf15010001	\\x3292a3000dad12d776bb17f961520fb9ca9426ce475092b5bf1bbe8b5d6e4ea05f12b8e14a6ac09943eb1f6d3edd20c0bf9128cc87ac34bb854bd819575a700d	1681811891000000	1682416691000000	1745488691000000	1840096691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x4a5e521089587e476ceca043d85677ab7171004fbcb8ee20da1d822eec69dab75c76655af03686d3be1e03c01cc349b60ca041ef811881f46bff66d823c4951d	1	0	\\x000000010000000000800003d56114390663735ec59824eebf577bde8f46a9016a3a6a0b343b7c18fc3779f1ed9314ffcd0aedc5d142becda528c11d0276dd508aef6c54156b1344514598f7ee2fe21db2895c670652df0b896d6c5779de3f76fdd4782ff1acbe9af2c9d371c0492714104735ad66f95990536a689455c26fa0137dd766fc2f7cfe688faff5010001	\\xc5704311299242930ae6c7f0b76c4f132fdf93b97ccd1a3e742a4de21395a545e9c85ddb7632975e355b0d35f7d38dada068054d414cb4da2beccd4d15728801	1667303891000000	1667908691000000	1730980691000000	1825588691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
249	\\x4cc220dc8670173c150a160b44a590ea75c62e6129ff95cbfd7992319b51e5580923517a972d841ffb389515fe5c84c8a577de5ad696470d5a87a2c9e18e92de	1	0	\\x000000010000000000800003b945b5f71798bfbfcba4bd340f1883f248205f0007761a7515414f6319de1f4d5c6d9e2cd454399f262f215a14a0ec78147b015d25c0ce6bf239397a09b78318787d47bb8627d2630565cf60e59e27236780cdcba5268a1af900efb2501609be132de3803a5c1bb9995c5bf2f5e52d10b8c3c3760567e05a9512295cb7fe5ea3010001	\\x5cdf2e98e65323144f74c7c94523244767e82f6cddefb86cfb6f06e731b060bd5a6abe62501a456da7f8124c0b583b16fd97729a3d413ba4c183de31f19c380a	1664281391000000	1664886191000000	1727958191000000	1822566191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x57363780adb3070867565597cf589d73c11100c57221fd82106fb25a22b457340c3d5f751c647338570f9b65485f694ef755b732b949988ec98c0de20d623647	1	0	\\x000000010000000000800003ae50465515062db42e10f5b19db895dec218b15cd748bae9b0981eb5e7843cbb490fbb0dc96c9e08545031c41661994ede8dd8dc98b453dcd8de9c50fe92b3ba912eeed10b3ed9c944dbbc64f1aabe9ea825da45f10f3e3c515f6b442125ff568574a36bba2eebc697fbbef2df9e10e33502145b245bdce9c0c5d466a9465a4f010001	\\x7682bee19f1acebdb14f83a10d26e2406c1161c50a3a01becaeabd99b61799a3f5d5587fb55b3e7a48b42d9dc77c21e436a15b2f5fcb7540e3fa2150d4135a0c	1684834391000000	1685439191000000	1748511191000000	1843119191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x58bea50b6fae2880e7fb79ea9fd0eeb5a7b9a00671a2b1f625740297923ddd0d5883b35ad6e7fc5f7433f822b40010ce04d7dda6f8e9a549ab24dc843232ddd2	1	0	\\x000000010000000000800003d8209e0f81d5ca3e950f18dff90aa93e1ed9d23becf94eae719e26947c0c45337268a6997fc5ab98e90fbfe363fad8b2d7f5ad1ee9bf00b5df97b55b341426a83c513040e3bd6b038b66c5fd1336d09b0387097f79f7c49a3b25ee6324eb48ada039ef37f896cebb595ab46ca9abcde9276dc2e308eae4bbd4c9e069cc807e49010001	\\xfa4742921211aa15f7cd6a1e3dd5272604d10119514d3a0bbb481675b5eac789d2ccf353b6e71d0272d68fbc8933c97c171ab1d69eb6e44348d5318e9b970c06	1687252391000000	1687857191000000	1750929191000000	1845537191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x5a0e937326835e9303b32a6fed859cb176e21124c203a397c33b255183c8fd99be34dfbe84fac8e1e6b317c87e9c93f96b086d5bd87e8138b847037ecad14ea9	1	0	\\x000000010000000000800003bf1b13b776c3360822e9841826dad84fa4a16c7791a724f0f94e23791e0df5d0a6c46df34c6ddf5acf2fd3e59b5e3d6c60a78081525f8f479ea3b77118b169212470e2c1f9e548f897cd554303ee814caeda0a73bbff16cb739c327172512b8a4f3518360e6b704cefdb4bb1bc1d69d9ca64662d6c0f5a5da3002d0b921c96ab010001	\\xaafcd77f6cc8ed4e1409e755fddbe2cdf6980462901b3d812c078e04f5f6faa9fda36275e4f21cf426d47de1a9c380c1652647b46b5eb53e01e0e7443c324a0b	1661863391000000	1662468191000000	1725540191000000	1820148191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x5b1acfab57f60b007e5281bc9617d7c96009ee12108420c935f4555fde71653f2776ee352130bfbcb1740a67bb345bd8041aefc24425e7139881c20c65e23958	1	0	\\x000000010000000000800003c99e5ea4aec0a8338492150945ff0df1ee772f9b5247f982d796a4f0ce81cfb3542d2311394046d3eeb05849f659c50ef9cc6833d6d598529290a566585b13841d3f96b91147783d2054bb9eae9bb3424ffb7b4d99327e80f909ec386f6854c1e43968b4cd04754ff8b6c58384bf92663d4433e8c964d3d3e095598a099d4b69010001	\\xc102fc47bfd52db6b19b67db2341cadc136862ff2f397e0441f47591b322a9e309d872b91a3239ea43e58eb834c772c926b0401a27b95d75b89e184ceb442e04	1689670391000000	1690275191000000	1753347191000000	1847955191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x5c529e8e80b60bcbb30a86a3dcbbd40cde5bd9a77104d469b622f0327e3389cca32ef33857727b3fab90727c49dd08d6beec6a209320c46ef1e00c3391886cd3	1	0	\\x000000010000000000800003c14ce4fe8df605a6e0eec8fd3f9f90e5296b9fa8f40afa5d41688410db9418bd2a333a688a8c498221ea5fd6754e6f9657ba05ba1db3c052b52609aeac3923d22d135509c62d39f70364d2c6b59dda8fc3d99eaf763a2c5e35c4a50e0ba22a71da2f7bb02857515ac453173169aa4b175b35b583c2688fb8933e6120bbb99363010001	\\x157b507d5f0dfb325a093abf671ef62ce0ab0addf76bab7c6ee637895b2a911b4a9306633f528b722b7b3f358618d0405d3f6bc2fda46b22b4488ead7dcea505	1684834391000000	1685439191000000	1748511191000000	1843119191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x5e9e816efcdde370b92051d53453b28f30aa141012389de6a336c8a61a4fcd7055da301428cae1be0417515b7e3ad7338eb8beb6a9fff567d4174e59d7aee39d	1	0	\\x000000010000000000800003c77ec3dfb297b0dfc685986ec1dc69326f228ea823238c6cfbe491724707017740cb8aa69c1c5c1c252526f4627265b759d0d5b4ba1ddb8960a2149391ca2464c13524445212fa193b61412242f76a108517430941d4191b1877e37e6198539706102d95f4ec0bd4a507dcfe0aea402611a5036679407786c190523f0c690ead010001	\\xf63ad5a2f3b37fd9a68eea7a5468ee53a0ac1350e9137de698fc83d4d99234acabc9c4754ba52b664f2a15120f74228add8f7b44522273f827d33394969ffa08	1673348891000000	1673953691000000	1737025691000000	1831633691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x616aac1e7e5846e347a02cc304cdce6552350423f9e58b74ff268568a760b2e51b9b55785fed2ed0316ee7ca6e6d8482bfaa4e9c8a26ca0a0888eceb4e163412	1	0	\\x000000010000000000800003af8c68be9b119c485566612ab75db59478155a3da2f2f7391c3ce54bd674ee3ee3d12eb77b88d4bdc8c0233e6b652b76e1172b2721ac7578f83987051151d7c5adf4cc1c7ebe06334c676e37e4e31cf7db44732f6e8e66114e129a9f420a7aeb468c00dffb694060e6c44073d6491f1053be56587e626746fe7f5a4008da757f010001	\\x6b66c8a5b7ad96f06fc7da6612d7af77ff50d0aedd7aab9b06ed84536acef5bf70ee8ba2c40fe85099d86b5daf6abb4413c49fdee18bc050ec5d33e4df550a0e	1668512891000000	1669117691000000	1732189691000000	1826797691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x612ef4639f314a3a106df5ec310eea6d3d7ff127f0061b7021a67d8025f49eac1183fa5edb3efaa2be2ad252fca99ab93988271d5a49a2dc16192ecf043e013a	1	0	\\x000000010000000000800003f1497b329812a65882db234e4e9463ed535ff3a5f54b309db53e95a525daafd26144f7bc888580fae603aa815d49dc0f1deed42610db6dcf98a9bb38fe9acb3e5307791c5e35295eb6300e7fdf555ae958c0ae2338be2113c9197fea37c15526610caaf755a35946874cf2c2211ae10e109db61e062bb22d4bd14b744529cc2f010001	\\x68cd048639b284b0ae54aefed15b7eb07503c45887c5ca49c768df56365dff6b63410275b94fa673fe024a01759ac27a7e55d14453eb99434bb9744c74b1b004	1682416391000000	1683021191000000	1746093191000000	1840701191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x6116db3337bfc1ff95ae9b48d00f69b65a67650a94e7bb9128a0de2703ec907b901e8baef026b82016f487141faaa9e9998ee181dc452af875f42f057e89873b	1	0	\\x000000010000000000800003f384dc75defcea71fbdb1d0de405f44f35ef1549eb3e44a21f76d2fab5e95a53c586f7035f6d5225c551f4504681eb85c2da661198c7190a0d3fdcd47e088cadca3cc3d093524cad19293fc8f797939cb32086bed7991f1081856aeac602a575c8c5c8b0c3f9e1f0d2c11fb716c93e990af8538c06c74953e2fadc997ff82a8d010001	\\x60899d15abfbacfc9974e512c7bd40e476b678864e0f16a84370226be5bd86d3083d6bfd2e4505b33dd59445690ba06945a4fd943998764c61ed1b6aa20f6306	1676975891000000	1677580691000000	1740652691000000	1835260691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
259	\\x644e0fee5950dff9d9ab3b923c1b125806dc65eb542125a551b0b80c36f389f762b807494f4f5d54be8a68ea2f7a1ca13397ed69e273695da03928ba9313931c	1	0	\\x000000010000000000800003afb3e71542c5907ae5da6d0103472b56f5eb0ccb19eff7a7e6c18bfef0be5701fd8e5bfa83f1977d8306199e5b351e2b33b57fc4d8e698e7678bcc50e695a1731cc1dd8be8a58f90bb8294b47e3b86bb5b4883e5030bc213ba5c45241152446e9352dc0a333016852e2501444b64c1911abe16dd51f46af8469e185db82e6f29010001	\\xdac98045a2c1144c08ed27503ba85a22b8d57022c60975d2b592b4a8457c2a3375986216bad708bbabf05b4b60d36315046ce151f689f021ad2f71d61f5a4801	1666094891000000	1666699691000000	1729771691000000	1824379691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
260	\\x65a28bca96c37384aeeb21dec4a81d3b50b4bdc26107e11860bc1903eeac95aeb77f1628b27ca728313f4a2ce7f6d70f0cf9ba10c4762010ccd1fbd4102476d7	1	0	\\x000000010000000000800003cb9f090c26e53fdd8aed7052cdb7bfdcde5981e5861e1b6325660d5b7302098a25dc14e6c6665648bbfb29e4bcb7c72db8030d713fb111b5fa674d40b41a7892217c9842015440c08cd7a11e635fff11e07fee94738548db056ed4db156e119a4d677eb3b22dd9013562cdc032e684f79fec53d36ef1e40f40351cd90261caab010001	\\x072d328a595202afd1da92c9860235a19b1df591fb62d787db067f767583e5c262407bf21d15911cf24ef031594f2f04ecb5b7da043c45e7819653114704f70c	1679998391000000	1680603191000000	1743675191000000	1838283191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x692e314966dbf25e3aa7e1ff35f13f9786a4ccf4245cc1cb38b5aeb975a4b8495cbae902bb3c3da398437c3573bbdbd37bd8db929aee907b1c18194d9e427dcd	1	0	\\x000000010000000000800003ce09d7b4a580972e2a9613cdecf3e590dc6ae33462e5d8c4107a32ccd5c7d0362108800f8bbe427b7a497b26dd70bbd00974e6e421ee6f61af7935e337e06cdd1feb0a38aa219774c1cb7c3dd0b8abc129a0c4f6441722641dcec259ec6426a7c5d66b7a9ad111d52b9389733bebbe75d1448b45eff24cf6f500a9d5d4a507e3010001	\\x5e684bd267ea1f771c892c55558b11a0c44dd876176f62b7087c5b9cffc24b79dff54775fd139657cd2cc7fc52ed4dda43149cfafd6801f78c2179d747f90c01	1671535391000000	1672140191000000	1735212191000000	1829820191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x6d8e07f5332e4e5fd5709cb5fae14a5f287b86cc03869fabbdaa9638084a3097477072b8044edadd7799b9b7d09fa7eea72d723582ac2306fd6587a8497a59fb	1	0	\\x000000010000000000800003f8c9cbabf97e9c226c627baf6d3a19e25c5d3011878230e988219b298128bb940e5c7a3424e2dbf0dd7fbaf1d244c04081991f5f206495b80d7544eb00e2c28dc30e1e3847f022247e0c6ae96797dbc507d04d09312fe00b2ab350ebf209450b2acc1699d1a9aaf944b8176a8b1cfc1883bb837dad96af137db5b327edfebb75010001	\\x8a1085cc52ba14c6cdc7fa81596e85bab9c343725a5afacc7d09de13eabee6773d763fc8ab43ab8b551775311d063f83d0e8a66691efa78ac617cd3005c0d30a	1663676891000000	1664281691000000	1727353691000000	1821961691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x6dde217ee359f1aac8e3f967f1359b0ebf69a0e01906cd15b0285deba777f500441cc5fc6ae4cf2b33ce853747df67c2ad386b848f447ceafa47ee5ffa62220a	1	0	\\x000000010000000000800003c99ad5ea507ecea692c9c7b8057fb837ff316cf9da2997c048e0555c9906879f653e13734b2ad6680ed669b4bbf4394cb31e5a188ce1916021f1522c05a2cc77b42fd26428c260641f9d337fa53b091b2db49bef0d5f40368d9c3d8bb397217711788852adab0def20e6f12ae66b3b184cc4d136af830f755a5e4fd700ab3691010001	\\x02ca7938214d800305288bccad9ad1b2a174da9fd472216c0342cdcaf0dd50f2dba4a6f44a81fc42265c992a536c41ee025e383cb1c6e73f5025bf669daa280a	1666094891000000	1666699691000000	1729771691000000	1824379691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x7076a760c39c790f05dc70cb98aa1b02bd924ac45ccf0b013bb7ea4764f050d15b4352aee988770685df4ecaaece365daf7ca2ebeaf0b047fd2f51d5729f06e3	1	0	\\x000000010000000000800003d44344ef76f1315a67d25e5e5ddb825bbc9a0ecb63bdc17d32ada0d4c44344f1559e18c62183adbbd683dd37027dcc9a22dd11a1012ed8ef8c99714c52e707133ed514fe90f02f773443d485a3c9dc08297e1403413cedde3daff975e8ff98249836c73293d900ae4c3d427377c5d059bdfd3528de022459cf8ef81f00656ed5010001	\\x67eaf8531ccabd417c55cb3c8eba8dde1cae1b0c6bb6d0dd8a9187bdaef5c62fea83dada24250cd6709e69e2e3f2c2c3ae0c2c5892de6cf52cf48100ba211d07	1688461391000000	1689066191000000	1752138191000000	1846746191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
265	\\x7416f11e9850af94c7d7cd3600f674b4c4ce994a4f35ca790bf4363163aec3dfbbde87dc732205cb3ccd1ce8d45b9fe2055cc3ff3b2536b6aac5b3177651840a	1	0	\\x000000010000000000800003d3dc49bbefc94483ccfa0ac542249e3f35ed28d9ca44d31ea3ea744b31ad1c26a7642cb0463c8ba1396bad0a609b95d7c4ff55d69817d79c5ab3db3e6efd8f0f5f69fd77ebc4d16c1a681ff8077ba36c76540b4c8b9acac59099bcc8abfd30f08a1d56ef6d7f3a67fffb07d068a490ab12d7936ce2089c6383293960d8493e47010001	\\x301a6db0762b302f7ceba5e3e783f78bca6a24f7ee019ec7ee9c6456d2ba24f6ff9861acc4e7096cbf612c7dd86ff1ae206caf5b5f036dff74edc6266f801306	1661863391000000	1662468191000000	1725540191000000	1820148191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x7aae7bb32c154a320d8094b52edf9ff906638095e273592eb7068d71ef3d1b900b030eff349543efe6a10f551a8135e40083460839731c4450a8b13ee675f51a	1	0	\\x000000010000000000800003bf4941fb3819f0ca11295c91be01ca348eec9dbbc8d5a54b260657ba4dde14374a1b171b61b70b5cfc2a736c501a1879a4aaca54f3c1afc5a59626182f9bfde28080ff7ab2ddfc4eb22fa0acc6d866b6cb5f05080c1ef5a24a9423b093700a27e2ae7e62bf1e8906f5245d9a07928e9b8d302ded6b0214bb928eb2b14128d00f010001	\\x7b031abb676b21445cbfa79592be62c45153f08ba949009aac0b8475229a1be3340f7f13353277fbbbfe7ffc33ef08c1d1d4fdcdf88b3d6a0b682aca7c2b5603	1667908391000000	1668513191000000	1731585191000000	1826193191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
267	\\x7cbe16abf3ec28c9bfdd0d8e9f8324f61087842265e1685db83d7797ad6baa0c11ff59bb371fe7aeec863fe202bfaeae35e0c0d18fdbc7f1f0189cbe795a261b	1	0	\\x000000010000000000800003c994a0b370a796ed27329da7efbe1923ef6176ba63edfd5ca354e00fc142843723a19bd93e93c802ff9ab4dcff4e259a12aec88a350d40f81111f2b516a8405faa190f7df8fbcbe1d0add5d14e1fca0cf7ed09332a50557a7238064c30f735ec2df3d228633396753b27cc4d1031b8447e1946eff26849c58bc093f3921855d9010001	\\xaf8c69cf4ea6b045c4c9139fa44d3d3a1419a9e77f2bd906e43b834ebe615cfe29fa1ad521d074758ae615c20398670cf1058bf9560371f3dde40a15a5f1eb02	1675162391000000	1675767191000000	1738839191000000	1833447191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x7d06602c12cecadfd8896a075267b20ad3fb5e60be7e18cdf2b7e68a021d0a4052a10cf1c2f394ed36c853e657ddb9693521b2fe287d2967008efd2410349df1	1	0	\\x000000010000000000800003be521cbe64f0a3c245b587a0d2426415f5a93d59771125471c338e8fb5b8e5771ebc77a426cbb58a2e378d9285c63c900a77f53d02fadc2d91390d32a38a854fbaa40fb58b8b500ce22ed6f231e5d1f2659092acedee805c078a85ea67da911c270c946d68c3cdf5633f02bbd7809f20915dc3958cfdb2def5ecdd63068b7d21010001	\\x3bb1ffd89620a7fc400f8efd5c9d3dfd26f066d67d8fcb16b80871df960124cd28dfe031b688f34b185e44aac28041c3dd01480fa71edca2ac6a973836c10a0c	1678184891000000	1678789691000000	1741861691000000	1836469691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x7e3a48dcd8807691e88ddb8c6bdcaa51d0839ac8b79c6dd73208125f504ea7e9b523b0f78507d2e2e815561999a8cd194c8846f74dcf7138d4ef724a4d6484ef	1	0	\\x000000010000000000800003c11ce1b04058f3d63f5dde735239351cca10ff38ffa08d60268fa89f65ebdc149566dd8e0d5ea433347fddfba59e29b5346dee231c46175e15e4777ae08f4723cc688da726f23d7a4ef959850563aebe8b84224cf77e89d71814cd86e465f94bc371c054f4326ccfac2bcda97492c9dc8c395d4407cca8c99f3f6fb672793d07010001	\\x543182e8289de8f5899d22e4ae6933bbce5cbb34628408d064646b5c8b5af45599e3059e8144c4b51f06ba89edbb69cbb692df84c6d1d6a0f7ea31d9f7c40d04	1686647891000000	1687252691000000	1750324691000000	1844932691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x800a99184a86b15592be12503e652558252028e0b8557975d4d5c2aca2663b20c9276c4ae29db2eb8738aa7ae9a46e5dac328b164ae6b04d6492a2859b1bb1f4	1	0	\\x000000010000000000800003b373eb8147f58a82cbce149c9b52c262a4c5e3c54e93ae0122a3d15da3251569d252056b0a3831240a2125c822b6df6467d01f6565a4b134f215b1b2778affb23a1b909e8ed920a157924f05d975cb07eb60c9d1a1f021522da91f86badeaabf4dd7991e9e5cfaf7957572dd443a8550a765bbf01a34a5e1b92d12d516101b35010001	\\x4d3ec4431ce729cc690c40ab9e33c344f6231b0eb8cfcb135545188914b18051626708b1a551895ced4ad62352a2773582330a891b1084b05aba30f1848c7f07	1669721891000000	1670326691000000	1733398691000000	1828006691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x82f22da373f84c81ac5f22bf307f3829842385a6d75250a6388e88aa8fd2c6b6741c481143f3b133eee55f4b88d7b8ed360b348a7b3b089e4b13c0f5ef977d4b	1	0	\\x000000010000000000800003ebcc9fbdff1ce8ac3dbe53f2039a2da2cef31d8be5801accf520f33e49c6e6b3745a85f84160b718e648efd2056c9c4a7c3130a0ee39302d5f0a33fc9fec01fb2956766c5fb1027eb929450351effb86b3cac079c0578268f85ba99a1870b6cbe0ee736ea1f941f776f312c70957de6a2a39a52298c64bea13f76b6a1693987f010001	\\x4644d840de735e7f64e0d74bcb74e2185c0a4a404070fa476cd45e0feaf6643d603c3c94bd30c3b7efdae14d698d34347321f06d05043188e022df8f9ebcde05	1663072391000000	1663677191000000	1726749191000000	1821357191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
272	\\x87d6a9e616e3bb11b2405caa326c9a95d6dd36161be441f3948911a99d86807dd008d5964ee458c59e2cf09a48e7a77801bbe45d23573fd990fe37f8b4268bb4	1	0	\\x000000010000000000800003a26488757344393ac54ddf6fe8d18bfdb061e7c4c601c0f00eee1dc907ec9de5a0053e6e951ac8533c617f652ff4699b68b63980d557ae11884cb907c700eff2f48e035d04bbcd908c21f4e512936c4d5427e456b5dd05f1435c0af8960fcf103d4d93314de4e0ea12d735532e548c3e7ce1dc57c3d299dff2a82703ce7bae21010001	\\xdef1495008e8d3bd9980453e3b96fb52a001c1ed95077bc24ada04ba965879a3d9d97638ea530e989e9d39e6e655fa6701faf25c8f2dc90c459e7da146a15c02	1682416391000000	1683021191000000	1746093191000000	1840701191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
273	\\x8e7addd0c73bb53bc43761cebf41028aef30e59c632b7ff1ea1782a8765b6f5d9552063501841d57f137007ac0065b72d8ec07b513085c179c4e8b816d89bc07	1	0	\\x000000010000000000800003b93962cf8d04691a9986522a2c0c0a17be51788f5fbb054f13a682fc6ac2edff78def20807878d403b945aac6549596dbd7d515aa344cf2a4a11d766a06c84f891eaa604b743192db096c90b07e6db53c2f9d09f4caab3d682a7a0186846758febfc48043c61682dadfc6d730787069db00b1a33b1c94c51b8ef93067e027459010001	\\xd9f3ef0bc817362a2e6182850ca79cb959702e9a3f9daa02f2e03e8d8ecdb2d6f404549eb49a3cdec6edcafd8559ca2529bbf1c3ee483cd00aff52c2eee2cd01	1678184891000000	1678789691000000	1741861691000000	1836469691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\x8ebaa7aee466a8aa74fb791e3ad28aa00de271f532433be7801ba45a9e67added85792c99f8172ccb932bdf6a28a0a006cf82c16c688e7194479c8f3eac9a623	1	0	\\x000000010000000000800003b52109cc5c706f1a7a1adf2cc8d8f58a1fbc6304f511e85387853c7f1945ff52d6788e3f7727b53fa0ee290f9568c59740b6d0697a4d967982f73ab40303248601e38b909e1709cc7753859f268843e0df9b83f852fe6284afe9b8e6ee1bc693f14a2f6a650ec221018bd061dcd105ba7c7ce53a9586a1cd69bffe878e4c8437010001	\\x6183e60a1c783d8aa4af9f4e7dac7e6c9b49c60e5af1524cf7b10283a93cde27777b1a62535b50a8becbddbe6a5d6a2d97bac32d5ef3912d64d8ffa20a3fa303	1666094891000000	1666699691000000	1729771691000000	1824379691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x9106bc2a678184cde8379090050bec43e67e92b3f5dd72081947e483a2ff3ed3761c8ea63af71caf1b7f9d4d8c9a668d7536248a1cd0c15322233addefde9023	1	0	\\x000000010000000000800003ae1d788a74a6da454ee8defa4b694dc8c1c8347f4da0d3dd783c066b811271f9e8bffbdfe0583d6986549bbb34ad79ea7d5cac776a8d3c951ad2ff241198c930f403649fa495a903517fd86350bd90bd65f4df4b5cf6f4e1793cfbcf92ac5c01c0f0343a1796d22fd08be23770aeef66c711171a1819f78c891c357f335df4f5010001	\\xf39d97e6f460d6389ec4ee20370d41a2a16205935438a3589cdc4a1a219b4eb774d3403ce7214def8a862c7cfe14408ee6f0a5d9dd3561146868ba496a7b6c0d	1684834391000000	1685439191000000	1748511191000000	1843119191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
276	\\x917aa1f6a2b54fcd2d3b76d1157855ae109b9b420969f3367e2441ee26d57897f26d96c3b30ab83c1481981ddced1ee1909e322afbec3525676553c7c1999d2a	1	0	\\x000000010000000000800003e14007414a432cf33088562ff8c538594345ac72aa9216219c60df66628040d09d4a407e0d8a059ca53cf2886a91f887cb0c54099092e143978883a23f3e86cae60b5c1d2d1578e5d5254f529fd38644546b0526b0337f298f4f8c6e978bb8592fa457e315c4381a3722e9560a5e239512a4ca0d0e796d9da6bbf6d57d6b4b5d010001	\\xcaffca46a3be1d1c42f8f99cbe727dfb0b6a9cbba5d9c63aecadd01b1ac2c9a1c0127b86f4172f06c829d78e965bdbe8e88ebfc08218c5acb95e9c332423fc0d	1677580391000000	1678185191000000	1741257191000000	1835865191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\x93a21b8c81bf27edff213d47bba825f83b0ad9d48e6d5646ab10a8a51e3cafe9cd161abde3bfce5db13aa62fafaf60b3d3efaafa16a6b9cb64ba54ec64fda138	1	0	\\x000000010000000000800003e60171c7317fd115566c278c409e0d1badc428f21596c0d786b5c04ae83923f5aff969c59fe729f8c17daa4de93149b615c60e9f29c4a40f4f7895c644f6c01add25e0f09ce573d5669c395efb8f2c7f94d61212a05e63d7beb49613da8e1f35da90872cb05b016ee5bfbb27a8f3aeb0aa3f7fb4951fc83b064ed95b1cf26e17010001	\\xe3829b62a032e545ebdda2b377c2ec3e772c016a583bd06cd371264ca8b112414ad03bee51cbaba1dd095a129481df6b07c238eb50a91dd2fe5e450841c2de0e	1672744391000000	1673349191000000	1736421191000000	1831029191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\x945ae37749f3a83370b7b196765fd358d2a9d3dbac8f99ce44b08b3a1a7042092a3b92681c1900611ddbc9b214ca1ea393a93220a3aa2622123af6c216537157	1	0	\\x000000010000000000800003dd28bf0036c4bd96d96eeff23a03e2a6777dc031c68467eb83481b57919e1f7faa5b23eaa785312ef92078e8dea9a5730c6ac164e0f7da9472e9b33a18ab8c37fa16b2a8e162a86911625a912b12570a68ffd670d66e54989a85de8648a9fd43743057d4a1d7288c08137361fee44246b05735aa126de4a0fdc7576df6e4f791010001	\\x571e4eb1be6985f406987f7e5225bf7064cc6540c4510dc40850abc6e949e1857b9706724d86580e80659770244d44eb0a54a5f86f79dee8e3676a17565e4105	1681207391000000	1681812191000000	1744884191000000	1839492191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\x97922c17177e0b022fa467e142f7dd798d9732cb58a7d3438cd43a1cb35d8eda0c1d3f4310231fbd04c160bf7f9a451ce9a03364350ffa343bb1d45e5bccd40b	1	0	\\x000000010000000000800003f278a2bfdbbff994ed9e057f3d7928a923b3d59a3385b1ddd065619ae18411a6db421d578388598064112209bda2d5d8ff589615d081a7de3dc088a3720dad6375328d61c5a6bad10d3d4ddc1f856c002aae04075aef22e310ab749a2c788860844ff9aa0bacad2a1a9cf0248bc10ff235d2a16db7190afe08c4ba18a3d24d59010001	\\xbb38981943263b810cf4cdc32f5b16e5a008279f837fda2848257629eccfcaf655920336891586a8de367100a126735de09c870a4f310a98996d0334dc5bd206	1663676891000000	1664281691000000	1727353691000000	1821961691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x98f2b7a836b31f752176fc0ca1e3c651a462eca50aa02f7c8ee6ca9c109208415a2ee1f570dc49265276ac3238196488090c552a655c17af1010804346182a5e	1	0	\\x000000010000000000800003d67b8413e25fa9917cc73c604ef2f6bc9cbf4fd33dc45e245f39ec0998f521894dab5ea48a20de5b5f997be59307163485f30379ab37247ba5cf4dbcef4981aa99b31e33c1ad389e99ec29719c9accf1347abc05787153277554b19dfb74ba67ac0fe1c663958a7e1e8ce48a09b0920c9a69e872d5ef163e4db111f15a1169ad010001	\\x38c75a29f423c9303bab2af27400afc1927702549a4664bb25d8abc4f5b3e6589399fe19e092b96fc2f7ba7c62fa0696a275269878b69b5af7c4ecf056e3760f	1664885891000000	1665490691000000	1728562691000000	1823170691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\x981ea79d1d9c0ed6c849471735d56ea6ea271d3b391cd3072fc5e736e739777a5e27cbd2525b1c33d05c4c7d348e5b7b291bdc5eb1208511712fbe11cb11c903	1	0	\\x000000010000000000800003c8b0ede5177d4d92a40e1e3292776fe09fac4c1d375853e983be2aa19e80b51ebed0bbb99c7e185df40310bb1187d651475eea0e68ac416684b5a2f646fc9155e2a64c743d5d8aad433cac29b8432aa7121f649dd5b571758d4055a1fe04e88b32f7396983b37ec0cde9cccaac2aa6b2f156e3e566e6c286d2fac410895af089010001	\\x92fed2ec55cbe6e1c7612b1699458127267722c9f58593798e2ca3b7cc7085129c3fa5ad79afce16031932e48e6c8123a747095c789ee9709c2e40c5e6887902	1684229891000000	1684834691000000	1747906691000000	1842514691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
282	\\x9e5ec62bac7d2691994815c5ee1cf7494683805bc3ed915fc6100b640d8f335e7291c797d6189c4bc000a80655c53f715ceb7ffd0fe537f106c9b0e6b38ec9a5	1	0	\\x000000010000000000800003ae169b0cd8fa30783b092a687c4660dd438c9364241c028335253b3f1fa889409b7349fdfce2a9a4ec0ac7daead94603cfc79e7ce50d12e52d463aa7351cfc59e0220c32ef611d9257b8eb291aedc0bb43b404766df23ec19b25fec2636008a20038955e43e9562d5d4284a55c37a53bdcb40546158e0b10fbdd5ef0a6717bab010001	\\x9967d3d86a885b168f1909d3632faa58f171001eae30955a89e3db97faaf79f9c2474f8a9780fa8e8a698229266e80ad61a6391c2bd787ecd43f40cc8368350f	1676975891000000	1677580691000000	1740652691000000	1835260691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\xa07a21505d79b0b10ed9458458bdadc2a4012e93ae212fd6e9e11b05bfd6523cd4a354d51263b4173c50ac56fa50285bb02e63156120148de48199362bd977e9	1	0	\\x000000010000000000800003c62f034d4f65ffa4d0a56cfc8676bffb48dd0ebaa2571a927be1861ec58ec31dcc019358e2cecf580ba87b1e648d1d326bed62d64e563245fd5ee2125c709585c25663b81787ee99171a0150557fcc4d2ff47b260106ba470677d9cf50c5bb9a1893c41d0f0e6b161d1e4781bc9e95d231c8fdb934f05085b9feeb13a999cee1010001	\\xc78665a16220ec6e3cbf5fd1b9e8d1f9242745228b05262f05d91306dbb0ada8960e8d119e0ea3afe9159245b6dc18f4caa2c7532192dd7a41b0a9122078010f	1672744391000000	1673349191000000	1736421191000000	1831029191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
284	\\xa15279a5e013854945430a052818997591c1696f688861775b8cfd1cd0b07875c580011746958734c04b4c7d283bf1ee52388bd9e0451675ffef999715e05687	1	0	\\x000000010000000000800003aef64159c5fd3953279752f010f81b7499393a7b3a0016ea200d8529c6603d3e308b0c73273955759b57c1910951cdd55ede73af2cb6c85e973f29c68850c1345f5f1ee822793f8f7fdf0c0b042884d8d936ea120638ff3a153fd110b824504c7b822c7d8ab4b70b8271e4892304dfd6864f504d42bc5880fcecbd9b13210aa5010001	\\xe6bb9b2eda717200d74e46e4738b5e214623ad5fa74f88d451da784cbb39cbb61a7dbd8b1490f2cc3425a60e584d40f374a8532d3935eb09f3cf819a0072530a	1689670391000000	1690275191000000	1753347191000000	1847955191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xa1a295e1a6aaae7471aebb46689d2e6d5de8fb25714fa0cd35c892c047e7c9ebbb7eb82678b278eddd58475aa62c63dc8276210d5f4519b7970bdb3181d75656	1	0	\\x000000010000000000800003ceb11a07c6cb67dc57754beafacac0ec9840bfbfc7c32942b1d1baa1d2ccc1d35030798812b2f96d41ad8e46c9f242d5ea0444582d0f9dacbd9724fd46afdee98de0c74bd4b6b1934a936d9e64506872431c69d79fae7802716dc82c526ab0518960ddbd3592bcb67a60bff792b22a631bcf28ed1cde30ac5fdcd8f03a8ab7d7010001	\\xbda8f7b5e80869ab781e121a74ed8e6b122d7dff9355eb0ca349223919c65ce57ef4879dfa8cf82a140ddb449f97919e11f58b1410020a18a43969dca8ef6a03	1673953391000000	1674558191000000	1737630191000000	1832238191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
286	\\xa402cfffbd72a593d76f4d55f374f97db6a29b8c00b8e06527fe153768268736194f35a8c7b2fff7b399774a11e55fbcd16411b6ef30f5c403a1c614a35199cd	1	0	\\x000000010000000000800003dddc536f4bf62c5f6cee99ba3bc61ba1a0d1ace5a92ca51d7af21f7976016ce945ddd273da9159a8b4b2ba0950941dfdf2b702bea09a22fe32e70a74a072ffdea95f3e2c538a78028f86700655eadde951c5e72ba823993051fb29b835d9ac51aad56efffbc2849f64b613a403babef47d73e76ae8ebf779a04de6f800cdf49f010001	\\xe341cb70485c7b0b069215c3971b9bb869e2b26b73ca99727773ef8e5743b13a7f94ed3a8572908e52cf9003fafa2cb4d7d28b71200533fc6b52e405aaeae804	1684229891000000	1684834691000000	1747906691000000	1842514691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xa442874e00f74bf2705bed3dbc74832e9e20da64364c476b5804f91181b42361aa32bdc1ebc1cca997885781d71744cbc6bd825b0d2350fcbb55aec4b5c144b3	1	0	\\x000000010000000000800003d7f9bd30b07cb3eb3a5c803925a1daabf5a44cc174681085dff396474f86f096264d21feb6349930cb60db2ba05ace7edb94d359706321a97ffa8e712634bfa92ba838e9a2b6387c3d424bfd54668cbdf32b67d5a02eacda7fe6cab1fcac72bf09f3f7bb7c5832fbb66dc6583dec9572051a1dd880528e6cc0b45716c1c70857010001	\\x164f391c0bf46fdc6dc21ad9dd342bacb4245e3efd5cdb439ec26b90ac6309b65e895871cf61580ec00189de6ef6b21017203a6998e1e0f5e03f620bb7e73f0d	1667303891000000	1667908691000000	1730980691000000	1825588691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
288	\\xa57a914b350ea41af31dd08558c0ea1c987d6b1e7ce706d61ad70336cfc2df9a9c4ec21f804869d2f9e3de4b7195c78eaef6d393fab747e37619773b392c08fa	1	0	\\x000000010000000000800003b295035bae0a62e8973dc736fc13ace78df6a9e263aa89c541981387d28ca84635cbafefc0b1fc5c63fd2b9f58b02e9d456640f7d1a4b158ec11c2a87b3243248e338633451dc06afc0597e6e5a777f33b58d9b5c0c5b3eab5c0bc07bb3291f8d424b29b780118d732252429d6bf6655226e7711e8750088fcefa77752bce475010001	\\xf40452db1c87fd43ec91620d19d6e38002a2e31a03fb1d4da08bbb0b64dacf4b1848b7fa8e41e93c7ce55d603b056150e4aa7809af0129964e0cd0c0358af00e	1675162391000000	1675767191000000	1738839191000000	1833447191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xa716eea6716aa8b222d0f4511d8e4023e3f596de3d39df4481c8a04b2e8a85c0ec1e15ccb3e6fa4e71dd6e80908ff8c00e1fd1aa1d408840fd5066d2885910cc	1	0	\\x000000010000000000800003d34efc0786c9f2a96c4e47b32b3d90a6df625277491b5ae82f38463592b1faf2a189e43675817cde707bc726cc63a147487b753df0e4e81fd744cb8cf10085f9683b2ee956bd7aad2d39c868ccb8fb363df04cbcdccce2606cd587e1b0e6df5acae6c8e6aeafc52ed5201c5662ad148f893d2749fca7fd56d893d1c1509adbe7010001	\\x67c7dfad405c3c8ddc5d15accf8dcf71e2061d58c08d4f7769516ccbc72fce98e1780cb0b5251c881314a7db9198cabc25ea3d33c7db0fb9b72a19810b04d50a	1692088391000000	1692693191000000	1755765191000000	1850373191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xa82a6f5a9cd065d85041d48c9a5a5d9d980c9df96e722c96593759e94a883accc1e087d732b5820ac8ab964226ce9b3fc14b33db09d8722926e72b7372ea4cdc	1	0	\\x000000010000000000800003d2995a7369705f4a32fb9795e8eb1f6bdb43aeb1881647fbc08132183507e229ab37e9809ae313c9d04c0c4f8a9996caa9e0052b9c2b71e3e674b96cd4a2746518d14273cb1d4c4af7130502f58a79764923dfe96c1657fb3a56435477881d4afb6c2fd5ec1b107937c89fa7e74a46b0b1e6f6b551c29f2d7160288a076881bf010001	\\xe26dbbb82b94b699606b5126380c322672bada1f4788c89bae6310427747cc66820e184f7a772168407ed64cd34de7433c689e5eb74cdfd8f1faaceadf3e890a	1690274891000000	1690879691000000	1753951691000000	1848559691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xa8ce74a2896ceccb7b93812ba2f2f1164a65e78de4501c60837c13fcc8b97b761ab4024a625e21251fe408d1e449efc5263b8f912f2d9be74982a27895fb82d2	1	0	\\x000000010000000000800003e823cccef46d7e6d1fe06e75afe7afb414bccd39f812b44ed22c403d56b567fcb6ef97b93cc480d7d4574add2a77c465b23d9b07a28f438f8df1456fcc4a50ed1ebbb40ce17b2fde553747a002c1e11591f976a67512071fe4eca175adae4da8caee1fd75efac7c0464975ba8dce04fb3561e44dfe5dda89c6f8a20d749ea22f010001	\\x8c65269a61adba56d6b3633ba7759bf3751927126c1db56463d0e69c60ad5aff36cf12ffe675e8fa3d8bef1ceb94941a3f06700ee0eca2bd208da4a48b262102	1692088391000000	1692693191000000	1755765191000000	1850373191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
292	\\xaa660e1b8a4a2c4b1746718a9bb447921929832879c8e9ee7ebfa4d85d4b9f901ac00ca5806dfc1a903e02411a8bce7a38346095fa2db350c0c2707920f4d2e5	1	0	\\x000000010000000000800003c171be8c5ac807db6d2e65451da1355c25ad78663b76a31babe7d30b5b8a9b04fc751953d932eb0284c33eeb75bbd7690c18ce29ff431b4f01aca56d3193893ca9aacf7bd4416572e50d700d813a7fd6596f941b1242d6cd5958910e4a3dcca172d62db06dce8201ad9b73a0f93b4bad3733898b15ba780a0de65414385d8a3f010001	\\x5c1456be4884cd1801b3b6bf319fc81773696e0a54af1bfeccd96c1559fe102c53dd2484de6bdee4998516f645b66f1bd971da997dc07963e446bf046eba9d0c	1688461391000000	1689066191000000	1752138191000000	1846746191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
293	\\xace22357d5310c9e281776b5155304850564bd7247cbf3f770c2a23cb2e62a459cca79fc52881b78b05f37a495ffc5c0519ca4101efbb27afbd81249bf21974f	1	0	\\x000000010000000000800003d708397e08c2780e8550b075864fa6769dd2e92e3df0feb1e1eb38597879d8212629ac45d81cb872e3ec0e13ee50dc5037010e9a63f860b99f8e0e90f4dfb128ae5d9178ba234663a8b0c1e2e86b86e26dd9c726ee4baac15ad3ef998de56dc425b2069061b667c53bdd5f9e107e39445077e7f9f1f04beaaf3b37b327322245010001	\\xa85ceb2ba6aba2a7da50f5bd8cb406e5561371a8bb7d85adcbe73c2a9e6f27d380e7fd03f8891fb0341726ec4ca3e364ba849d8c561126487e2e9acdcfc76101	1661258891000000	1661863691000000	1724935691000000	1819543691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xac8ab4bfdd188b0e09daf2f283e721d8dc7368d71b3d0c673f65c84259463235bfc8bf74589f8cb9a241444abf5b3bc2891cc542f665a33996fd85e4a4eabefb	1	0	\\x000000010000000000800003c98d281b08c2ff017cb9b4e0322e750c9bfc824cad8cc170512e1f08520865d7e108bd7d96dcbfaee7733c6a812b70ee48f0577f175e7bf1b32879f8a4e9e6884e59bb85972da2a4ab5a0d1e3482ba0dcbf325321179193829217e4ae5073931eee1005fd93052fbc7f3227b812cd5eaaabc53729e5807aa994786383e9c27c9010001	\\x44079e7dc8f7f35054b9e5cf5fd5eb1e5ce1e9aa605b580850603de041041cc6b1e49ec3e0f3d1dad03a44ec3daec92480ad7bde4cf3fcf506e543d22fe5960b	1689065891000000	1689670691000000	1752742691000000	1847350691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\xb0d2271df886882c0bfe142f44bb4fbf16665f0335fad3bd9931c77044d982bbb0831c6633aa3e6dd654e863519660fe4deadc3704e5514d51851357e4bc1789	1	0	\\x000000010000000000800003abedebb7e3739fd0e03f608808321704cc535a428d8582e4df147575b402f5a6ebd01d8fd68e5a9b0ce02056e575b8083de7d4c7c92dc9d2f1f95ff3e41e74cc52a82c4ef852bb2c36dd1a2cc6c003f85a1c7ef311bfc29efbcba230935094108e9176dec8f34a68f0c31031b047662082f7b3104fb5e77d58ea200abc29cae3010001	\\x4203ed6d82a6efa9aef0fbe570bb1322a1111d68e0c956901925bf17259f01bffb288060e3d71dd7d98901282c060b9a1fbb905ad1bac62006e9eaca3952f500	1674557891000000	1675162691000000	1738234691000000	1832842691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
296	\\xb272e16eb8d2aa03ae20147b10e1ecd23b94e27e52cd83058aa4a11474bd4eccbf4bbdde7b384363512fd2d4dfb074d6f879a1a042bb499226d5787996ece6c3	1	0	\\x000000010000000000800003a41a0df981622c656f19e2dfa48f0ec55d455606d4796040f8d293791d0d9487451f0867babb229bee4fba5f316da0293f6ee3cbe6b1f6c2c18b7d137952fb2c197b3a8b686f293dfdda75f1a407a3cfd8c11ff0ee5fd79d287e652e4b5f62128d0df18f16a79a828cd6c210ce8024b7c522ed00c4f6a9269f97f0654ce4e6ed010001	\\xa48b723c5429e2910db49eea170f473ea58fbaacb14daa17391d01e4b0b24f95cf316ffcc50bc5c37e7be8a4c465062d933e261e6b0620fdb3db0577fea59a01	1682416391000000	1683021191000000	1746093191000000	1840701191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xb59a7f26a0abd10cea8e8a4f2fdea518b19be61a8a50e8ed9cbe5338e1cb2fd0caf701abcba5fc773e904d35b93cf4fddc539098d0e9057452b8495b7debc472	1	0	\\x000000010000000000800003b489d99db449afefe42deea766bb526ef9ddbcf6045c8be4f1f55413805c1be8c8304b3e113d5c60794b7143c96d6b568079f65346a0bff96f894339cd40ffda2c38c663cbe95283993b78d6286d90fd905608557b0d31d82b5ab2f5c61f4175ba4306eebd2595377baf842a726a9ab315c7810aa2969560375923f5bf60222f010001	\\xed4fdf7ac214e10d288db8a21c91e901dcf3bc43e8157bd38e0766e1fbd8b2fe6cc1938b310cf79b3d0b5d200f9d3068a6d127d619132b0bca187f0c96512902	1690274891000000	1690879691000000	1753951691000000	1848559691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\xbcba86d3501b69f8cd8714ce71f2ce346bf8486dc3c70a16cd49f1f294952058421edb6f7483f8f17215f847043a30baed3ada1a1eeb51819f16f272c3c2c52e	1	0	\\x000000010000000000800003bc49c754789a1f2d16723e42234fd9b5b1146b405ef86c21169fc9122ee3add965385ee4c65dd91d91a354b021b8d4c6dde162eac50a9ce193a1009d3a1dad34d58054a1e02658e30dc3a120d20283cc6e3896532b595d306d14ba2a067feac44542e3dc10c8c19d730a876132d8ac9c18a0bea1c9806f78a0446d89070d5f25010001	\\xed81e9eee769e94e0d59acb5ad8d3ea541b9a7c4ff57d986c5ee0f47035158cadd8b6f50ac79c16eee04b1407fa820726d59b17f13a1a9353990219afee91406	1669721891000000	1670326691000000	1733398691000000	1828006691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xbc9ae75a938fd1507ee07021b4ae462d0f3053144921f09f0346556fff681f07e8263c530e3a7a024b0fe248b1c69095a5d868eafeebd54cc716a3f0283944eb	1	0	\\x00000001000000000080000393783c59ed16c2963d2c221c92356033302e71befbd682a811de7dcaa987ead8a039c7a676dcaee89550da842f906dd2315cd7aeeaef7dce477d4afdabcf1546c16f4f6b1bf947bb7e7258014ea6ea2d16bee9be7917d0334acacb6ea8a345ccc5af4434404748cc15323de31735645b8e28c9a607c7c86b20e11a7a6fa482cd010001	\\xe4ca0bec0c2cc7da127d0a8cc3cbf7e7c92a27cd864d0c6d89dbe6764916ef512265ab253f5dd7e5a58e20e8bcbe0a7fcc5b47ef150432cada949d296c00ab04	1687856891000000	1688461691000000	1751533691000000	1846141691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
300	\\xbf666dddb6143575a62945f2cfc2fab21817991a35dfaa77317bee02e49e39ebc5b0e9c4dca6860456c090658b51c4f1fd2f8db4e2c4c62935064483ad92c04a	1	0	\\x0000000100000000008000039ef1b8229ed717f93e2c821814c0db23d2c694657a42fd22da8b7400c85b3d1a7867a7a0801d8652b7e579baac3770ca19ee1087b5cb092473ced80526f6dc92c388c44f30fcd512e5bc392b433c5a08c69bf2565409e337f06a200f57bcc1f732dc84a0cfc4a1b58d4e12c6c5cc0d1c41ddca15c8a494cfeda95d6e94b3d6b9010001	\\x49668c918690f0a986215cc3f12574c939eae32fe5c83d342baa7e6132b88bed736a613ec4bf4b19d8bbe88efc5f9bb08b0d314cea305fb2fe865fe7f9ac4f01	1688461391000000	1689066191000000	1752138191000000	1846746191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
301	\\xc0da144b1bcb03c8c0b0c681c85cd96203f895b172f0e3017cab12fc7a6feb2c3d420d25841e4533253440596d81955db0a58e5a7ebad019f5e3db282a2d819e	1	0	\\x000000010000000000800003cceb18d4200d73ec102e51bf2f9772cf32ed709f4dc5507757016926bdb5f34af4936e3a0aaf6ba05b72c33c0191c3fad7a8617730198d9446efb7feca903fd6d93eb716098621a5ddc6d5fe0170e7cf9c05115ca9a7a879df6a662a749b91ec8a324e35f19c3e757511570817abd896725e9b55a4529dc1c84608ea1e78cd8d010001	\\x047efef700fa2ff36bd3c2888b80e238165ab016b2d12e0f39bf5ebc3fd0447eb6e6cc43c0aa290acb4ac470ba036399a6fe92b8059b6346fd6b2cab73fe7a01	1666094891000000	1666699691000000	1729771691000000	1824379691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xc36eab4ec26ec4a1456ca108a1ff3ec535f718892d0c0a4dbf75328205c061d6252ed1221e983a5f7fb16280fb4f995e22cd3410858b2b71e20a221b39f68c49	1	0	\\x000000010000000000800003e72cea64c3ee0542f55a94740bb4cd473ad0d00e2c0e56d7602b0703e8fabab5d63b5f760bf3382c2b2818013a82800aa4d236e9a97dd3003326c1c4fb4b4349a4a5da2c48c3613191385869638902f871b80f65fb2d7874f9230f7bdfb79aec2b6e52ba2c0c37c66b571834c6e88d7f1cb4607aa80308aa41d74877146b03a3010001	\\x95b74e6bb49570850669b898513815783278920319e4f8b594a7b293a256c7e4b29810555b79be289f25f59d5f296f04acabfdc54674070152ae700e8805c30d	1679393891000000	1679998691000000	1743070691000000	1837678691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xc3864f745b46ad8158b37a0d6fcefc7319b7506d42ffcfb907da61ede7c1b76370dae9b74a6e4e554946198e65964405eb7c52400788ce64e1864974638ac41c	1	0	\\x000000010000000000800003d4cdf5b91f5d40d921fb96677c8f057dd9ae025341baf48ea69568b13ece6bf1f6565e175b40181debee3747f8a225825eecd6fa450d849ee2de869794d4067779dc846c13987cfbcbefeb73ee74717f48dad75c5bc5b27d7401b3e737aa6f3b0a1fb72f9c11f7a74353640cc29c2d532927e075a62d7345ae6477139deef65f010001	\\x4963ce99849b08ebbc2038600ed924dfc6d4e17563cd080967242fd7a8ef628c739323a749783b1a4f06aa1e04a0000dcbd6a8966cbb8aeb89898139f5645c00	1691483891000000	1692088691000000	1755160691000000	1849768691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xc9c2cc67dc7b0966fc6ae0b3e69b572dbf552ee32b38d0e992d8bfd9c653fef9b56bbe2946e1fd0177b40bc9fe7a3e6e2e53ae621dc9fd4425386ff27eba30c6	1	0	\\x000000010000000000800003da807686bc90e8e03fce0f52c8e50108eea38dbaaa1559581697211ed5af4f3d4f69c52f03ab6a13cd91a32da5437031bc4f27895fef707c337d396c90088ed00aa2afa179136142f73f16e4b2fec989b3d9dffa07bbcc90ba459eeaa9799f0af5679236f5d002e93b0ccbb7e38436a8cbe4166c889ecbf5d8060d3527c788bf010001	\\x1c631c514272fc772011722987310faf8f77e45442849db7c1bada6d97c8c9b88187a9d765a9ed7ae50ac7848a84aed3e6720aa5f219f908dbfd2eb603e79d06	1682416391000000	1683021191000000	1746093191000000	1840701191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
305	\\xca3a6e122c0c4535defcac67eb2abf890c2cacc395eb673d062cffe703764f8221afc990ea446568d8bfee8cbb094fc668d23f617900e3fac717353d37a81c5f	1	0	\\x000000010000000000800003f3acb3da33c960a0ac4a8aa00e4b531ff880e5aeee69b319791a46911542e234e8207e02443327fe571701c69c3df34216835c340f5a0e24c7dc3d0e47658d908785e5bfa520e1c8c17b6673ca2ba1456d0d4867070ceb1d8f7042da0ce241159617e72fa0ac7492c1c88a57972cdea9ed9cb95ae7d989aecbe06b17b8f60961010001	\\x2d253b4e14a43672070c87011b133873d81f52c901e7b2e90c1bde2e369a12e505db9d66ed6d30e39c6d8a4b30e0b9ef42b622182547fab35a48eda10eac0600	1675766891000000	1676371691000000	1739443691000000	1834051691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xca2a312db4d3bbaffa4e23d12b9a36aa69afb1365bbe29a6c3fc4adef4d39c22f3b1ca9135995b99bc7770c45cb35615e158d826c3f8269e7f707c509a4b57ab	1	0	\\x00000001000000000080000397fd93fd3db61ae2eb2ffaaee42b02e9e8a2c41f2b59ab15ba393778683f61d705e02a512f9d78f67f8d945832825c9f4452843e157b514335d68ae94fbba2318d706f2e188a214e04586211410ab7c5d2c80e68bd7a011711153d9030208eb3afb9c37573f5283039c302094a92fb73dd228359484ba653afe3a56c0392c89d010001	\\x2cf5aa3b9bb052d1cad41515f202d1797b0dd0124901aa6aad0c7af35d8356605a0a167fa2383b0be9301e1453b4977ae263e55da4ef673b290ba5ee92b2c709	1668512891000000	1669117691000000	1732189691000000	1826797691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xcb6e42dda575a60d969d62c1c584d3d59a8ec6abdd1434089765c371fa90fd24987b29e8da85cd864edc96d6b39804d58e9b02cfb14478a0c906f499e8187f62	1	0	\\x000000010000000000800003d94411504f8b59879bc0f225e81f315af3fb07683a2d1a5166ed6d56fa07de7a30f9036a4278e976367dcdb51385bb68f8a1f4915571f1ade3cd3a2bae160b25c243273d78bc2ffb967e6ad43f5c4cabf6fe50d1292515eb2cc56772a5c48c8d6cfdbdde11ca7759798a22ba612545c4700a32288f7283043eb98e8132e14a1d010001	\\xbbc2e14d2608ce5fb04eaa14c755a047742065ba5dabe3a44b33016a4af59ef93658497328628b52254f7e46184e59107c2e3972f19b33d870dfa190a037ff0d	1673953391000000	1674558191000000	1737630191000000	1832238191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xcc2262d9067a26d6f0c785afd0a2ea0062bd7ac6cc0b9851bee5cc12e9880baeeb8666e800fcda3dcd1de6ed7817cc21007f24a6a722471ed988c88e7295392f	1	0	\\x000000010000000000800003a7cd0d1220aaf571b8500169a8080945195bab0fecbabd840f04b454bc627e009c378f7424afd11471db411e4cb674f7b4e8377a68aabb7195d8d0253c8a6630dfd88c4d302fd4d6e1c322bd0674438245df56df4c1c38fbcd3b6beb5e320de45f5fc2d3eecf4153b80fe26a6333a9b0e3872ed8a3c39ca364283927122da449010001	\\x73d049d39ec7c7da599a386364caa8184db11dfb64571d834f1369ab1e65e5c471ec35195c9b90a57b66cfc13d6fc8213481a546684eeecbe756d08614647f0b	1664885891000000	1665490691000000	1728562691000000	1823170691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
309	\\xcf56e0be0b383502ebc7a6be1fcc428c3e1db528aa53de184c466d3042d331d546d3c33687b14729e7e9151675f1de94c8331d97008a9ec0f6b51cd20dd7f559	1	0	\\x000000010000000000800003badf9673e4e59e481baf9a688bca25fcfee28a7de11d9691ae9a8986ff5bf020ae40fc88b3125763a544eb6ce0f6e2d6eda56a51841b45fb8fc98e860571b9e6be077dee73447be7e482fb4366fefd1f91c2ea3f1ba8e203e307bac7fa1d002d44f24a9c645affd794652d4d079be98900a71a377c35d04272fcc897576c8c01010001	\\x71aab4d60a3fbed8b3e86bcba087799f0501f50086a8f6542be80c0e2a7c15bf1268aea9a87f40bda19d0f0a402c4cef1f6dfcd46780f6dcc94e96eafc785e07	1673953391000000	1674558191000000	1737630191000000	1832238191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xcf0e82997f19e5211bbfe3f6972c2dd75adc1efd45474bdeb9aa0a732a42072476432d42bfb6971b5f8220d00b6ee60e9b9e8c5d388037876f4e192d0d4cb1e4	1	0	\\x000000010000000000800003c0693cd81d1502fc1d0f634fe6bf42dbe059dbbe525ee11cc572fd053aa903b7a765bb5cd595a01b49990fb8849537b7b11e0dd657e56fb61b7ed3f171f9079d8c9df547affbdc7bdd204f9080137c25a76247528e46674f8e2477bdc28ac6a2bc7005289bd560eae51e365665da6a9d7fa590fb6e293b674167f33281ace7bf010001	\\x3e33e2708416ee07e0318252f4641e44d46ebb82929858f6c001f0fe1c88f3a50cb6dfb7d3ed5e83874d363cc2ce89944074fe21afcdca5399273f806c2e0504	1684229891000000	1684834691000000	1747906691000000	1842514691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xd4c2b503775383f6549eaf2e3890472136615e53bb19883cba66ea377f21ab9f0b86d3e6ba5882293c456a3661f5ac419d0c57388250feefd45afefa4877139e	1	0	\\x000000010000000000800003d744494fd0270d36ec693180482acabcb9bcc1deb42cdf6fcd604ac59aad678a58b10c2bcf650ecdcd8c99d8ede684738589c6c0a31c37a534b6074cca6055934dc30f6bdf6e032b02e21f9e37570ed8248d0d8126b714344f1ee3c49f73c18134eb2843d39453d0b287c76ac20300707533a678d80e9d704435d874ae4604ed010001	\\x8e7fd2c89da0332a6e8d11ccf5807a312f09066d1836666d2a0b666ea27e80f291de77c8b7be5de90e727ffbdaab976a3edd2522cdf968d9afdc301d6d6ebf0a	1665490391000000	1666095191000000	1729167191000000	1823775191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
312	\\xd57a990e9aa3e897fbf252ce1d3ce62d517ade720750d176a3e3d970ea057ed4de5ece4c31b226001647928777e33f8287506976474022ece89f24b9abb3278f	1	0	\\x000000010000000000800003c2211f6307f82b3acfc4de1343a75f379a143e04c722ff191f29a3342aceee2bbf806f3170760f6758da3acffe713d3511e627c5909dbe8eda9c40eda9dc531dd091295099b27b19684afdb79da4ae92ec57373e426046014cfa149f10e4b52de28f3f00deffc0db54ef3e8bc139ccbb2f89c148d896e1f8caeee5104a72e99d010001	\\x7eb5784cc7be72ad5461bc057c8dd4d4b115d32e40bbc4d8c953374b51163f231881bf3240988d964ca0d57d35b2017b13139b82e61b8e1473528bfcde512e07	1673348891000000	1673953691000000	1737025691000000	1831633691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xd796acab848d0cc08ddc2c5eb0f7dff7ca049ec91b63db0137803df9f3c335a0559dcad4322bccca86d3283536aa58e103492c88498ae42ecc4a49444ced11c9	1	0	\\x000000010000000000800003a134b01c748053f7dde5c7da35222d465bd435dd430111ca6272fe056a5c4036039a075e278847fbb6b2941de3c6ed4e4af50885ddb563e6124cd9d7dc297fe95506b23fe7f9d45e989705ab3aa5424f30fd52c86792c78dab313614f05a39a61c35b125d4bc775c0420de17b6653f221fc922f4e4b593f6d1c1a5bf62844f11010001	\\x17bd172f097c66787f99f000df36c79bde983c7fb03a58a303c3f5ec62851681e57bc54f2f3e012af4a64acd2a6e3a39849766f740480736c775c7e531e5cb0d	1678789391000000	1679394191000000	1742466191000000	1837074191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xd7b69c0ffaf22e7b6d52efc40e33c816bd4f58f27ba374e29c62aa4b3321ab099cf966d78e254670d8ee6c5b727d154c10569ab93f09cdfe78ef9cc08c31ae0a	1	0	\\x000000010000000000800003a463c18422ae6fdd2d43338095d73ddf3dffba956d651c4550653943bbfc576542ad12c54685ea36bcfcc2d9693cd7ed16fbc6836f2fa730ee0b478913c95c194953d831fbd425e9cd991f56f8bf22fc813d1f6fe5b6c1531944a3441ee4134a27b132143aa14b02888e89042e201c16d8aad7609ba6781e096a61e868d7332d010001	\\x5b5691c091b1d6d8e371c01d3caa01ed74da450601ecf3cf0d81f4e69584c4f969b7a97072bce8814698532a1e07f80dc010e30cb0b68a4c27fe0fea4626880e	1686043391000000	1686648191000000	1749720191000000	1844328191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
315	\\xe12ac94a1c83c337bf9ec86af8a306789b9141576730bac1384c2f73a6a299b816fc5fd7dc65ac5c30eb880ab8cdb60754b4f1d9c7096fc07cf6db2a0dc20d39	1	0	\\x000000010000000000800003c529abe9cb7ee0da995c5b09deaea8d14bae7ef0e1008a0d6ee81a2f1843ec4da3007812993d4438b1bfa66c8c6d863fe14fd8149f3f004a20a87c79849ada4d033967688490ef10414679c0703eb62e9e082bf5d15bccf69d6bb18c1449cb344691c611b7698303889e490d038b0e36da58f2da4247674e86e2318ae76064a3010001	\\x2f38bdf248fdd34d95286f3bc82451fbcc924b0dfab3b716f03343ad711de2e2bcc930288918ea0bfc3f8049dbe383c7195b58ccf24f889e039bdc342dc5ec07	1667908391000000	1668513191000000	1731585191000000	1826193191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xed4e9d96306d576aafeceb7b074d0ffd40000e58a682f1e092cbe8d6b9e52aab5a6ae2b7a4b5c626733049f5d5ce3c7a66544f108203392130d61a38eab22ec2	1	0	\\x000000010000000000800003cc40ff877146b7fa88010f5142a26707539172e2085710ae9d01f9071818078fc9fdf2a8c0d922fd20d2fe10c0059a21af1db6ed2b8db21a3395e5de2af6e9fe813c1f85e21def4ab165605c20b2649da82e81c7caf1f04f36a3b49729873c6efa8425dee0a0b5cb83ca225490a98fec6a888a828d7deaedf07e3fb61d01330b010001	\\x26b1a43622aad3acd199c5118e5859c1ab8e7f140e12d2c6a1130aec8a9d5ab75b15085225ec63c2c8c5c41c59c259f86d786492fe93c70bd94d0313e1a20e00	1681207391000000	1681812191000000	1744884191000000	1839492191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\xee8a80a2d4dc5052934797e25d39852a8f1be7121bb63c19803b6dd8c4b6c86e3e1bf01cc7a277d42f42ac05cffb441a4deed0eacefc7b5920bdea6802f8871c	1	0	\\x000000010000000000800003a64ca2848cdf25c08119822df86e7de0d49caf40237e673ed8daf9fdf679cb66cb890a92ec89d8be72128e3cf7c9dd4563312de1e2c1d2816b5dacf986c13b6a7a82accdc939a6f46ece663142e63b748795e14911363f01be5a9ad4be4e2c3984313cf701faf7cb19d8fc005ec6b8c0bc2e3cc2daee081b75ee2a4c888ac37d010001	\\x76c5ead678b8587b1fbef36f8d4b6d2ced88f4500ff9e0a963103d9b5e56c27419bbf9f654ee57546c30bd6a80d7b99cbdd58f06dbf64634f80c6e97090a8602	1678789391000000	1679394191000000	1742466191000000	1837074191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\xf1a292327b0f1d49b074ab30f1e36e0902900f8e00da95f9efd8132f8d8fe475c7daf932deb6fc77c65d316d75ae3c8b06c857b2e992879ffd1551287217e0ff	1	0	\\x000000010000000000800003c3d8357e0ab82810c5beb82f48eb23ddd0c947e021bab73211069738f9438e6a9bf20c1f058566db3da6abedb03ef9df67957abd65baeb76608c154cd3448b6f76dd823e9ca171c3af7d3ff97c1f3833240965c36e5da22cc7d5c17e4e7cdc40e04094638081319a52d0843e12c227063aefd5921f10cbbb72b1bae92c78f815010001	\\x75dad6db88d51adfcbbb6414c8dd3fa261a7d4dc91d1e3705b311b561ea26db13354f073b7c30fadf7cbc6ee00add63c0d8f9aae426b696bed5dac7c91c63907	1676371391000000	1676976191000000	1740048191000000	1834656191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
319	\\xf2827a54fc5921feaec7f536bd5f1cd5b88977e69a5332f1196ee73b89718e95c555a59d7acbd25867ccac0e26d6ca6d0b6cdd45641d0b7127a074906da899cd	1	0	\\x000000010000000000800003d3fd3c433df22a5cb1d0bccb4be2085bde77ccd6dd4982063e19c1168cf1a7dd83fbe468d72e8c87fd43f6de9470b761d82772b1e286c8314a03bb5b171ff969394b0cf92699ca5afad6bee15574c0b182cea006c30c1336fbd2aa111bef7546e06e78cc2492d5e721566ba9110c81fdd0c56cd6b32d628786058d45c24cc977010001	\\x3b4a23a9a4f146fc86b08e47a561ee34247cd1cfe61dce8eefb8bb558475c343df0f57049b2c71c4ed63e9c71767a9590e0f7cb0b7e91fdfdc1ac18bd615e603	1689670391000000	1690275191000000	1753347191000000	1847955191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
320	\\xf2aa6593a33224974587a791895cb31bd915e57f734e51207ea3947aa533efda0b076fb082885335d4b53c319a118b8e632c610ef1de3ffc346d20cdff37e58c	1	0	\\x000000010000000000800003d583ef8de7b47350f07196ed5ddbf3f875391ea434f96f92c31dd3649a90fbc6fb1e3c8efcbd06932d22c71c4ff1e013cec0a55d24e42d3b7dcff7d876f53895b4f0ce8db91766b212021404cfd4986ae186a7e9593620d43d29f200fd552617f7a63ad8e3cb4791409df4970bfb7f39376660fa71af833ba5e8b6f1196404f5010001	\\x3fbdbe26a400906cdbfc87b2011acc189e6cacb8dfe16d44125b010eb5bf03c96c9aa98a8457b7688145d1ad719b5a1e2fd21a5a3a2036d8d78862f773748f07	1676975891000000	1677580691000000	1740652691000000	1835260691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
321	\\xf41e5cd54b75c7f631fba7ae7ee1d858f84e2baf4cafccd087de6cc823c7cc3282c84afa7b47fa8ca4979383e46e6e8952e313606fd4052bba765ef9d989a115	1	0	\\x000000010000000000800003b79abd65b88826ae8f4b71440979e82803acada73c2f85d21cf77279ad02562480594302a63dca8dd19f2fe816a87bea48f11c2a6c54e0781d4b6135f40ff30d8248c76afb9fc235aba70fdde7e049b3cfcfb0038bbf2ab380641bca9a5ca0e374d21435ece1d397696195667b15de843ac7cfa2bf82e3d4056bff796000056d010001	\\xad66616e5bbca916fb50f1b9ac0f25f5ea99830f0dac8b3dbf826008f1492d786d423b737d5110e0c275acf5e1b23bc7faa170c0f7a075ce0603238931191709	1672744391000000	1673349191000000	1736421191000000	1831029191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
322	\\xf74e102c628d37afa3dcd6b3b43dc745cecbda5b34bf7e7d09c9bf86896c61442afc97ad820a23681997af59f5315fa0de8e1a85279bee348c127fb2312c4d94	1	0	\\x000000010000000000800003d41c6fbf8d20e782021e50560dc7a71d050e7b35f78862edded3f3171e485d9cd8e55fc6cda82058deccb4063efe8b69a622450471832c9d53152cf0985f08dd2d0fb445dc63e41a4da0cc6fbf18bbb19d245638c9343e10f779212849b265f81e00e3e8b2bccfb7916d11ab98a9096200ee673a48ef88b56ee77fc28551abad010001	\\x720dbc5f81958e02ae220ec8624168ff89d050311a89e536a3b77f1cfd21b10395fa53cc5851b5a7317d3b3cf1489f6bc2420f849a1d7bd95d60d0a9d36be10a	1683020891000000	1683625691000000	1746697691000000	1841305691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\xf90ef309ff1371965c6833225ba03514e4ab0ed5c9169705eb99c32266aed15e1c3be0a68a564e6540b8701a01e19994d730e5746a8df976fa393161d7806a6c	1	0	\\x000000010000000000800003e5da6d9a0631e6a7bb89eb826e3168a3d9b0205c1e791bada272cac39a78571b37a6cd3895d6a473255859f299d957d3f98c6efb02ec5c0c67c97f2b20cb04974c00753a7ce63e584a0d7bd1e7ef878c6079b586320e5a3bb9b8866950a5818f3129843795d3a53bd83874583af41d321bb089ecd888516cef5e7190086ec14d010001	\\x5fd87d272c57f9f0a510f69da95fceab64e6e0a1691b94a925bdbcb030202653902ca94521d25ed6e12017a568d66f136d0e43804da91edcd7b6354066cdcd08	1665490391000000	1666095191000000	1729167191000000	1823775191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\xf9caa6ce92866e83b7657e686798b29cd205001e5f2550898ddc3c587d319014ee891d3761bbe4b682f1313c6a1dc17b23f838efdd02ae0ae4d85f54f4fee088	1	0	\\x000000010000000000800003ac3b0e3a0e24e24bc7bf1c7c311e24f210b57393658ea84f492ce888336f7cc113749c8002d569a633abd6d20c8035603f9c7eb175400e48624e60ff889c98546bc08fc9931bf2231cd06539770845cdf559055d4fe8b983648217cb0b33f599948c0802b7b299cce3796006f0a88bc286848c1a63bc3738bc8a81fa62956815010001	\\x0c16e6c096cf5d62cc301f517de4a4d6e154369e91a128a66751b8f9f0ec8677440d8e7d21547cd3e4e45aa4f89f2ae24e40e61d4a4527260163a08e9a0d630a	1682416391000000	1683021191000000	1746093191000000	1840701191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
325	\\xfaba55b33cd2ecf6c8a11b6c3997df9ed10c9fdff7003ade3cda30f9061d90cb408a3f7be74eaf1ed142af7768ca0ae8ccf32d50a72f72d2b1a7541d57dfad26	1	0	\\x000000010000000000800003be924b404dd2d3d932904ed1cbcb4eb80f05e7960b890f9cc9cfb25e9789dec036aceb888329afbba0e2ecd51be318acb0b9c13497cbee427ed254b09fa7d72534126b1d46a6afccffbf50be226eed6976b0bd21d4caad180b917bd4dd51b76b5fa993c2379ee48bb3cc695f55e699fa2cddc2b24c59a1bc5d0fc48a93f7f057010001	\\x829583fc99f3c6255614a226c4054038bfebb92e723094ff0dfabc521c2bc252168f5ace68afaec35035e8a9e44d286071bb5beaad7e6f5b9567b8bf1c2f170a	1663676891000000	1664281691000000	1727353691000000	1821961691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\xfd023e6133d6cd24a2683150fdd2c795ae0c676822c89f3e90c2018207f7983ab5ace051d1c3c50210c61c0e8a8467b495f252f6a00e5f6d7bd986bfe5ebe16c	1	0	\\x000000010000000000800003be5094acfed112f44f125bd48e0a45bcc996475ba7a73ee95dbef1980ca7eb6e88e511d1c8b704f663bcfb7597abf01a2801da2cc64dd2459611283f037a529523e8fecec00654393060716d36e4a563fdfff34cae35c373150ccd86b9ec1a64e970508012442ab3919719332557293c6fd25b2ed84f3a41b557bd51d989f989010001	\\xb8fccbe55c872bf875a182d128cdeee792dada7db536aa41522b1fc2306c61ce690900c26466c7e4b6bcc51c88598c34f41c06057d3f57d0bd9d943c52a9ed01	1680602891000000	1681207691000000	1744279691000000	1838887691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x0033a420f59d6cf58f81acdfe0e11ce3a217761a6357d2eccd6e075505ab8c3d761656f86ba3d6f2da8089c3d4d92e4d1c0ec35df580dd6c9c53724b6c48c4b6	1	0	\\x000000010000000000800003b20c5f2d6f7d2bcb1aafbb7c8385c8eeb533bc5820de31bc026d7085b173bf61599a16750d2aa32f8b837be97fbe2438bde0bf59636f67faf7707419540e2544e6235d32836876f6366953ca8aa9e3a0a3f757ef17cb2a20a781114f26bfaf0c2da37538595d62633fd03e115ee87cd1396c8b838b71a7180100d7bc7ab7b529010001	\\x2fbf87209d443472300f8bba5895caee141ce2f73e5be674fa6d02a311f5489c1eadf353524c308330b6de4ffb0383a3ccfb5b40b5a3e580b4a444acd4f15706	1687252391000000	1687857191000000	1750929191000000	1845537191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x01c378f744548a1d27224ac2e0b87bdf6cb956ccf6743a3a8ff04246f770ce4d6f6dbb629f84baa60b7a48ecb10bafa3527cf075b26072fc78b99537aec45502	1	0	\\x0000000100000000008000039eae3d3647ffa66968ca31c5c676bc3e1a893ec8d972ecd7d5ff1f2f6743064d7e78e8fc735591b34be6aa1703e3998a04f135b2c46d0ea8c850d60f584110291ad7f6c569ee428151e85eaf1bd834f8e192139d9111727cb72ba061b0821ce3bd4869b4e06d037c49015261c6277daec3f67f54cad32d5949080d1492268aa1010001	\\xdfb89a83217875d395549b39f0246972ce5de72849d7ba1fce75319c4d57f52dc29e3372728add3146bf98831f59921f6ba1dd4bf1aaaa240d4797aef0af390d	1675162391000000	1675767191000000	1738839191000000	1833447191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x027b53cb69874335ea61cfea9eaeb2bb6bd00c9b92f74c09868ba94b75981c16e2cd17d27432b3c0aab226e3105c02dd8d2cff62caf7175db702951d562a1789	1	0	\\x000000010000000000800003c53d627cffccbf8360e1c26fe5b48f064e14eec3314873be77d4fafbc0ef7472eb405d73e1c74c4dc0286437540b77fd22e548afb0b9b2d4bed6ec827deb19e2c2d9cb24f189341125aee80b64ac98b49b3b79bddec463d803b0b88bc52de91b7c7e2697c6a9670de0579cc45db4c4ea945b561d1d0043c79b26b6441976a84b010001	\\x0aaae502d55b530dbd8b13ea9442d9e6fb2312ebf232ecf1a1b79404c65ca176cc025efd2b24a5e593d4405b938b7a37971024239157ee1c9ba3827b2e12e207	1689670391000000	1690275191000000	1753347191000000	1847955191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\x038f6916d43593c92a1959aadc8ec7f5f7db4a98034216f28b5f4e5f40fb15b289d290184e8b5913e1d07bf16dd20cf304a26ed24c278b79b4ec15b25e6a7e42	1	0	\\x0000000100000000008000039b54349f4189ea524e8550631e0f725e75fdfef28d48e82c7e2309ea23f8aa6c936ac60c92ba32f1c25b976a9a0d147f3b21ffc924a7d0edd0f965c21022d04a9deeadefa80c205c944569b99858886679810bd5b5046fdde126525bc5a5a920c94acaa22a920aef4e5c51bcf1d334a10cb7c834500e2f66c880c65792c7b8fb010001	\\x4c02a68a142488d5a8e0baa4d50f4f5ea7ced9b3075f9c176a8bb48c2144c4c6ec88f4da830e71e66afbf7531d3e9f814e8f84ac234d894c43acc19435d5b30e	1679998391000000	1680603191000000	1743675191000000	1838283191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
331	\\x0713ab0d0b886a879e937dacb252de763a966d723cd14a22e66bb866d59827710637178209438a3a44a79b3a6e85f1274edcb6e2fee8dfab0f08caee8d4dbfab	1	0	\\x000000010000000000800003c3c9f8f84841d3f83d5eed20de36fc25aef448218f06015f4bc5320a51769a8b8f5379f37a303e55177adf086fdd71e57895ca117c61ca1d99fea7bf5e755d7ebabbeec1258d58ba82a01bf5501482598117e6b50402d6470cd513c341b680a65626b4e79a157fe59b7851d8d7198b9f9aa016e3f13632968704b8312d13b617010001	\\x94f822a90f7e71119c12a79b1b5310704c547870a7453f23a0d4a234fe4d8571bb0b626dcc486e99b8e9aa7eb7e1ac6fe0036baa1e87d927017863da0b3e6a04	1668512891000000	1669117691000000	1732189691000000	1826797691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
332	\\x09576371337c0bd385192deaa1af612bd729be479ae010f31264f16b4823b29f2f3662d031e959d793b71bdd385b6d4677b78283f307cdaa2f57d19021985763	1	0	\\x000000010000000000800003e36003ffa6f516264c7b1cafa4cd9ec2475ef2ab78d106856d2c2b9b1967fbef9a47532c63532932582742ff8b83ada572e74a523f468481024499d6c0554f64a0c515a54bb3f372a0492e1e05de216f37b826885c50d4465fcd20ffb6ed755ca4eb4a9604cd2ad1814eb9204fa5c54619416d319e151f56c082803a441985e9010001	\\x40ad4345fc0be95303ad95d385dce04d6789b3e78badf7665c6d8ec069e9b2b71ae0fea39096d3fd0fd9a22627c7c1d9a9fb0a63420ebeec3892d39a6a49430f	1683020891000000	1683625691000000	1746697691000000	1841305691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x0a7b602fec38921241d4276624a14ad574544b47c206bb15d8e9f8d48e19123c65a0d15d0532e5b73864918785a13530c2386a6f6a44d2b1bde140091ccbd0a8	1	0	\\x000000010000000000800003ad142bf5487a2f80b5c7b07cde35b5c8ed136ec02d99f6a2a695587330c0b27252e771d5e2c60e0225f6d3d0382d1dc5278b101f6546829725bd6d1576a316a9a93e952935c0f96618245c60c9bbc2cd34ba2a5575daa8a6ffee0cfa862344f939f1158b2de08a220f313c2c55bf50023cb3c90113c3a8d95aec6d59412839e3010001	\\x88dc308e1ff448335a1715c597db7b59f7f1eba04c386564af0b069d3f40dac4a1f1eb7978a41f1f428cb66d2cec130f034f09b9461c3264e3e7513f752d3801	1681207391000000	1681812191000000	1744884191000000	1839492191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x0dbfd9650daa9727e1e0f8715ce00c886b76d30bb995d095a48a316de63867deec3093862582a30acab1c6c542f8c762385f59e4f28fa48122ab1f14cc27dbe6	1	0	\\x000000010000000000800003c7039e909fd4e309f3a9b5f8db0cef1b57ba96d433d68df88fa216ef27e24155d0629ff33a4a03bb9384c71e8766d0e192c14faffe9174b3a5f190d33750d685554a80ddb72563e4cddc27f62a89667b6968639f26fb0e6dfad23b83a5eda22e66828e111509af28a0c451aa6341eb970090101cadf2706238587ac7b3c8387d010001	\\x0c4950a77d7e9f25f3b7f827c74ac950a9f86f022d06a1fa9d47996cc12e3508cd5ea104616dd32cd3a95fcb34a861c63a74d6b7fb7ea124419ed496b74ec90d	1675766891000000	1676371691000000	1739443691000000	1834051691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x100fd0818971e1571f022520020ec973e478a642d31417fa3c707df2c1bfbd5875a8249223fc8680118c690176d3013b30c05acab06935f16f287f7ef8a7c985	1	0	\\x000000010000000000800003e75f180a7cff9d52b57e89b7cc5d0a8438f7bf2c7ebb29d4d070aff34bb62d7c3d5bb9f4c84a65587ac20fd007fbf4d8ab0378eafb65dc6d0461701b4c44a854a9fea71311fb11446757d86a15abc4cbeb14ad871e126f0579724bca5ad339c26e1c5f27cf8761759035314fcd74b5ebab6537778cf12c95e8b64055b5fc58ad010001	\\xd577408c8b2b6e9ec2deec0fe1f81ae8163419dd9b7ac5ea9c41ecb76e220f265156bc9d43ef4c19c91ba2599797d4248c751190f8ee01d83313bdaf8147f506	1673953391000000	1674558191000000	1737630191000000	1832238191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x12cb8c6c8946e30a7ed90535032573fc03fcf1529516234d5decc4b730af8b3ef1dd224843f37c67fe4167a0235a61109d6302a45c8ac71a44abcb42a11cfd39	1	0	\\x000000010000000000800003c3b08c8305b9097caae12608ca8077d333aff328257cf59527fd8129721b76b23b5a83101164d48fee5c0de73ea89efe929c7d5ec2cab20a934599a2b3555160a8710619eb1cbf952c3bdb51eb973711ae79d2ab5c8864922a08a6b5fb8198f19937fe184c94e4e8c0302398802a6eb7f9c6ecbf22b6e4f98b59dfd42ef3a3bd010001	\\xcb11f0b7165038b21079a08008e701f5e80017015216bc48309012b43681e44b8762547d01f9befad8546eb1892b2824966565f42d8f73c0d573198b37b48801	1669117391000000	1669722191000000	1732794191000000	1827402191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x17b75a6e8e0e172065945b08ec2b76a3238cdba8f761b88a72f5df1b43d2d0cd6b7c934a417195dd5d44166bde3d360d67833879668715797e717f4a4a28edbe	1	0	\\x000000010000000000800003cacb68213b9fde6eb401882382ef46f432e4993073a2bd438054afc5f9ac9e4c6483b393d93d8edc60a81b13546f00aa541c866ab7eea6c1570c0a81219d715d0d27f8b0ee3729b0e185059a138e539ee96b6cb3dcb07655713f6c02a27434241822573849c65764600695fb894d675edb860ff20e8148873bb9a11ecd39b031010001	\\xbed6a5fdc8dc8c07ce937dedb8c976e2e9bf0f35c953bd4339ddc6677888e858b2d6969d577824ac37d2c476cbc855665e58c66eca9c9d6633400540b8a10604	1689065891000000	1689670691000000	1752742691000000	1847350691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x180be5fed12d8e98aa3ae461efda4a10c359a470ce474c7a34914bb5f3fa8d39cd102181c34c2f2b0e1b780ba5fa11fa3dd316953182ab451fd6e601b7005209	1	0	\\x000000010000000000800003d7fdbd04812d4c5e8176a686e1a27eb42bc5129803597f099cfba20c244a12670b23983ca80fa6bf429a41da900262575d264742d7671766a690e247e3324ab25202dc31f8e9dd0eb869817cc66eb8e15198e0c54fdbb83112f4f9967c3958a3bac284693ab6fbfdfd68fc6434230e3e7952d2eedaf68f12641b7fcdea7c88f7010001	\\x30842ff119a5b7ee526afd2427260c8f6725f14745ae3d1190e8d8ebf416cb8a974248b21e67c5fc5ca4e1b8abd00bcda165cbb1f724e004ff384253fef41506	1664281391000000	1664886191000000	1727958191000000	1822566191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
339	\\x1f0b301f01009aef79798e220d06fc0a51dc11258714603b0d78b3de14f1b08c3ed2a04f67e3f29e8ccaaf10271565f3705e5a952280ffc69e11101c6d130016	1	0	\\x000000010000000000800003d0156e6319fc8acccdf8ee73cbbff1155beeca88e7ebb60099e7424ad8e424c4e8cd1309a06883e2f041a0013f6e5f3bf8eeedeaa8c59ea0b0d29f0ea6bffd55fa1c8786c7853ca0a4a50373d470604cf2701f33e9987feb38dea3db3bcb43fe4a392c9e0fc9513fd90a1a511e8acafa20dd2d8db273ce6238f0cd3f74f2817d010001	\\x79f51a60136406f3d9e158cfe2696a0d4fd26a985fccce0cfeb9eba7f9eb49bc79487a2e6c0146626b25749e8941e3e59485181aacdd5f63f6d41a3fb83a9509	1667303891000000	1667908691000000	1730980691000000	1825588691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x25eb9b739d2e5c1fe441fecc6cb6a517c8ed6335b0458e541a4d3fc758320df8c04f5853d69600b2ddf015db07604245aef3c55e488d210946c67c81b5e60f83	1	0	\\x000000010000000000800003a20ba717704c6252e08f11338931a59415941c419c207e31b4f3e22728653538bfab3899188c5e8f688e075c4281f9c7b3bb87104b47161ffa8c3cbc73dff899ee2a4d67404d6bb9c9586dd397f664e23f7c7fe72ca44910d34178fc19e5237eb9d1e05256166a00ee62b8f564f163f8ce3dcc5a7afafd0c4d33fbf22d706c91010001	\\x1bd347de04837d36a929eacf15e261422b78f24801f22a2e3f58f145b4b5a6dc19a1b0e01783ff0a9cfee3a8d56445c41dce04a93205931dfac9c7662be1b900	1677580391000000	1678185191000000	1741257191000000	1835865191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x267f90d51454b31fc84b55d3f491e30a1d07139620a551abb28584fb80744b7b0a8a1f826a9d20443716551c17150a8480b711908f451c678e512099f26f57a3	1	0	\\x000000010000000000800003e2f80550197f9e961aa71084f59484769208305847e095c7d75657629cb12ef78e37b430d9cabe23b7ce03cde50cafcdc6c6d93bc0045fcd0e61dd7733b9af01bad5fe8c26f90605b82938638ad6772628f3570ac4218490744778afa9c5d3899b9a12199a2095f4c62c517cc969637ff9a695deaa3d7770b315228dca21bb29010001	\\x1bbaa75060d978062b227e0265d00cebdbeaadacac9d7e8dcb1aaef32a72c55fdd5205e434d497816b6cc723a6f32df54757a663aa773a3f22c6ab328c920c06	1692088391000000	1692693191000000	1755765191000000	1850373191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x26875904ca50da57d0fb2c4c879f324c6a78a1719115e3a74fd516a774eb78746d2dda95f956b305e39d2b5a12136f9c243b9449d06757e804a3b3f012ee48e7	1	0	\\x000000010000000000800003eb1943eb72dcf1b88e488dff9cd17b4f37b9c555ca494203ede59758056c0c74a7d093f64ab323700028455da492c48d0ecb6cfaf47c36fdc6b2539160f4d327c973b091144fd9f93a50f6ddc6e783bc6de80d0c3dfd5e98c1d95201ac9f586070537d35721824e040219dbd194e5b524eeb54fee0c8558941444c55bcb5dfc3010001	\\x7814c8a7278482962269f19e7c191592246220f6033e25ff85339c5bb2d6747ca087f390ebca1fc7ae9243d052ada7d2569cfffd661ae216df49e29261996309	1666699391000000	1667304191000000	1730376191000000	1824984191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
343	\\x290be7bf1a0a9580b5c10a2aceea2d5c79ed2e3c938ef854090d23f4639b87ead29b7e1b20527d233839a72ef9296df5b820d5568f8645b30eb0ce2501e4ba2e	1	0	\\x000000010000000000800003e4b57c7b3f60efda8b2c716676f3a15be7fe05dc3e3d0f264d738dd050c2390e256a2e06e1621a0cddaaea4d881cfcb17370289766edff1de56d37399df7231f3dd75624ca742fadec8d64b3dbad1064c1fe5d1d2be0128e3c17afaa9c4eaf0f1a1dd0eab1dc7ef0edb4aa16e36b73d5ad27c68dbc865616fa2c432f45a71755010001	\\x842ede164bd9a9a33fd5f696dccdb76306d4f9bd3fd6564d9a60bea2c37c1267bee9b956ef751721ceafb76d3547aef694671085164f50cfdd659f9192479200	1680602891000000	1681207691000000	1744279691000000	1838887691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x2a4f4097bcc10f04a36dddf4dc6517f3cd648d9dd15c04adc7847370409254bb341c363ba0747b9b51e25123c5af9fde1ac5ede401a1a151adaa2a3d1eda223c	1	0	\\x000000010000000000800003e667d240627dad5e08231c38143b00b38c0932d62dc1282b1fec0c95ea5fe94a31f44c077e03f738c43565b5a6181912e7856acde0c18fe0d978d9d4a5d7101f0b4c6a2d56f3e4c900ce2a0935d9eec33a691bb86e5bbd25dc483955fb2f953b069e1ac2b9065448406b2869c6d2f81b1458c526b768e90257ad34f0a7d33f4b010001	\\xc8b198803b347a3ca5fded1da51559ebfcedf25b2ce9273a9c065ee830fafcc43050e684f8e8dcb991ab600842c2fe6f781a6717c31bd8133c96fa5f03fbd103	1690879391000000	1691484191000000	1754556191000000	1849164191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x2c8f951cb4e4a69bb172ef803e8cfa646bb7b96c50667d077b871883562604c51cc19c0c658060b49100ee89be4e88f1fe388df6c46937cf81902b5c8978388a	1	0	\\x000000010000000000800003b8a579f44fa89c6f77f4c7766d500561d230fcbb39532d1af7005a5f1bd908fa9554b798d9e39d835c89c698d74d2c86929fc78339660084743de9ec3833592863d2dafea9732bd263b5f16eaf2d15beafcf4d3558919772a2d999a96a9aef2eb785e5e352e18b7d794fc5a427529430d6ed6f77bc0be442b75109bcf771b6d3010001	\\x58b215fea7aa8abe3ab32c52b329a4ebc7d3f93ee9e39240481bfde950827b0578a26408c9305e862da2eb2fed05983305883e251a034e314e73865fc30b050a	1678184891000000	1678789691000000	1741861691000000	1836469691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x2f63ae9b564d8efac3071f18674ae99a9598634ee75a85d50d5f1bd7c4de8300f8b62f24f328d9f6f2c778bfbb91388df1a0c0db7e11772b418fb67cfbdde509	1	0	\\x000000010000000000800003c212f21130bd04e2e81e73ef58549736dee219f10158342c54b5c2eb112c81e0b2bb8faffb12dc29b974bb7b7a8078eb7936de57c048fe1caa5e8b0889e9462314d071ff6b18c0a35121dd26f9b9777047a3a327c44ee6be70d26a450c1c7d3e5eedb21cc1410b75d74c1d79b05a3b96ab7c4f6f17e12df019bb2a922ab3a949010001	\\x3664495fcb3b64b736bac16c46c21d806588c23d117e522e6e1ff6dcb522d779cd16de0487fabb9549a9e989581ce15cb4d49345412f24ae9f7e92b384ac940f	1681811891000000	1682416691000000	1745488691000000	1840096691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
347	\\x2fcff8083ba32e9b6c6929121d09a4121495441d790a69747424ed2a5ce7b1bbc74bd3dc8e7c259bbabf2ad5757652d3d749917acd0c2eb67c383e9e6b575f11	1	0	\\x000000010000000000800003a8e0241196d1ab332271b5a7308b4c019c7bce85375a235eb964ad5854e2ebdd39328497d926b4711977cc9763e792e01c3e4934a43a4df2c125e4dda2c779f6e61c814dc6a4a24ca3acab58a17803088c42d8df78a00423f2b3075001f8ea4b22fd744c941c66a79dbb44cb5500d8a1fb4ce2258a7bced1958e6e3dd8621d07010001	\\xf97ec3a95a062dc8b0f88bf160442157510b2feb401545c3ee9d71f2fa873e2f10792ac3fb88b9c7b17b54ed7d5c8f216f1aebe5de602d66ec4667e3fd3ac405	1672744391000000	1673349191000000	1736421191000000	1831029191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
348	\\x3f2bc4b5ac4304b82595022730500287b74785f79b72112f8c168ef32ce5ef6d3ef064d0db55db0c8327a95148f2c7144b3efa0d46f635e1e1a034cf6ba6f5b1	1	0	\\x000000010000000000800003c5c7b76efdb860a60d3688cdf8ea853aa0cdd6b11c8b1ce88a6b556b4a57e5f972d5a0f524413256ec50d08c34067d29363c1c05363227f14d0d644e22a2a36ddeca7e765189047332c7c8d8f02953810c65ef7c9addfefbb772f23cb162dd9480ecb7fa3b3477c9952b028921ab2414e1f7789c4675472618bf579d97583c6f010001	\\x610c46000fd5929624232a90774db30ace9967d98ef8fcbd18a65626d5ae5dba816b5ba5d729f02ec8982668be0bdad2e835e49d1585b9c65515a90849465d0a	1667303891000000	1667908691000000	1730980691000000	1825588691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x424ff82ebb7e093fd70bb092c96949d949665da5e77a1ec407abc2d22f22db3671c45c95c91efb6c6911f01875f57c0b7b03a8a247fe7f43374d78b8d56315d7	1	0	\\x000000010000000000800003b9e571c85f6cd8305d606167521c167cf748d36553d163786e8692705fd4714bcf56ed5cb85e1497ad28142ed162d96a8d19cf7ecb3c1ef9e5da75b5957008745867b60d53e3caac84781215cf590e1fa1bc3a34568b2f3a87b323a82dcf9702213cfd7c4a4090888a4f800247bdba3e92a458e1767d3da94eab781a39f35137010001	\\xa438957e9c8044370cee62f2d2059a5979f141d33d2205561a9290f79eb83bd9ef7290a6ca2040234f74ac6c2422a1d1fa2a2efaada2e0144ea36ae6108a0e08	1666699391000000	1667304191000000	1730376191000000	1824984191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
350	\\x45dbadae186d4754b5d76e4dc9e38f64d972cce7d39f6b94324c5f3a0eee3024762a12efa7927f0e4b7e4d389cd4b7b809371b462a3967c720be8985e7e1ea50	1	0	\\x000000010000000000800003ea1368a7db0551eb980936d7925d7da05786b3be8634b2c697490ed132fd0138b755b1e238cb9379f5003a20aa3ea4770d7a936072b14c39deccbc2872c73e6eb11594a6a8f91ae72ac808fe58fd0e6d405c2d77bccbfd7d443594577c92b9b346bca004327556f4aea4ff0ae512bbf523f076d12125299f9761d59c3f40e2a9010001	\\x12c8b58bf7a90039bfb946c1c09b4947997e8178e1c6d6a0d8529216e216fa78a98b4971483bbed36cd558024b0f800ba57294ffbcc9a02670f0f8da5124fd02	1678184891000000	1678789691000000	1741861691000000	1836469691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x46dffe067ab2d09bc795079c4ed3e2993fc9c801fc1c11453955363733ff833eded7ef0a60579ceeaa369c7fe56f2fc79881adb2e0c37b95fb1985e00078b393	1	0	\\x000000010000000000800003a37e44b0e53b1e664e3c3b68f72223b68913e55f829196c89e8f1934c7078b5853a6ee46b62ae69e690b6e095165450657706aa9542b26071f3e2eb3b8f253bf8a2f520ee3d878ab92d8c9d606040c8e650f1c5658439a4011209a685ad542655a7dd30fd721e312728fd923ad81aeb8799f983e8b8ad3a6c929e383aaf5df97010001	\\x3076fd8e8f3f17415e8ba5a2823fdc0b72a7d6de9ad44f699e76ba87544272dfc69325db49e84bd68868d9ff69df7976c798a6e88337f55011ff0464406a240e	1665490391000000	1666095191000000	1729167191000000	1823775191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x4b0f50dad891be7819c845dd0fe39968199ec33ba3f63894a31803d2087baa62a8fe27774ce81287cf5071f44b20fbd9b369f2547ea474800df7ddef38f462d7	1	0	\\x000000010000000000800003a7cefed03efb28cc495050dcc6331e1a18e4c2c1eabe17abab8cf59634da9432da8a1da62a429c6972fdcbd4da993618f4e37753f0aa8adc4c0266e9a1fbed78dc17baeef6321375b8348315f0fff784d3cb247077aa2a0d5ab4f628a4d07aa4c0ab5fdc179187506e2fe08d8e2a7af59525baf332bada829cae71f0db81fe8b010001	\\x007ada93a99266fc2b252293cc664f971dd942ef909edade182e88a93157810a08fca2cbbad14d4dd2fb717bda454bc6b53d048c20738421ef7ecdf9799a0f03	1690879391000000	1691484191000000	1754556191000000	1849164191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
353	\\x4b5b8e0d97c8d215460627a213af5bff0324f98314219f4bce212477a196e522759cfe29540628259b74f03af6c0f5d48995aeacde0f31d7592d8bb6feb2ac52	1	0	\\x000000010000000000800003c110ecec617d7f0c0629a3a64b93f62b2185e283c59fe7d0ee9d86c12af0998e4cea2a04d86e8ba8ecbb2e5d85808ab3c201f799c74277cec5637b2836aa6c7d7113d48789aff49252e08c34d12f534840bff3e9e008451e7928845373051582c981cc0e507d9501476ba91cddfe339c0057ff105cdab1e9a1fd767de8e5bed9010001	\\x70198cdd888c711d171787b0da587c45d6a466e326bb7cf8d19ee47d4c448cccc9418a564a2d66551daf1c82cc029bf3a7c1e7944131cb84969de8f44f3e6408	1683625391000000	1684230191000000	1747302191000000	1841910191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x4e673fd8b849ad17d3ffb3841385ce9347ad0c8c3b3a81ed59a523930fa1637e5bbc3933c0f10edfa77fb460ea00fce19243d424e3f4204bd94a5d7a14a1a49b	1	0	\\x000000010000000000800003c4e6878a5b108348e46e2b1ee2b2b28eef535c6b0ac1ae4caf0219d2b4e6ad63af1292ad5f168ba5e42c9ecd7b2c391b1245e3d1f577d419447ee85a4585b44eab90b108cd5b389a0340121592ae37f7f695cc646c9cac3d1c7475f48f0d333067c52b7771931cc9821bd5be097a8fea9d46529f4c2a8d912ef2e7bdd50b3ccf010001	\\xd9f90658f0c6079984d2194293cbc37899576240e2fd523273037c36187549dcdfa5f9028222aeb21215c981c63039fd4dad796412f301d28dc7445a782bd70c	1674557891000000	1675162691000000	1738234691000000	1832842691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x535350aa8473635d3925490f41ee1b007b4b0b0162b7b4d88657823f0a4ec70ef6b018878635be771b8963c69c39efe96a55ad283a9865c5d549942d00a83c20	1	0	\\x000000010000000000800003b78eac36cec26d9a73ee3bd7a4702fe3bb9e03902e0d923153e7b6b85064eccdd942fb8f2ce4789ab0ce15f44d77f69c3e5e088fb615f2118716efb30f381a62d0a6da44965ceb2acae4934551aba05475e5bbb11e1a6e24f7802851ad3544eb95ac9e67bb42f0364461c4bdb9c77c4d1a9d8e43a543d3041f122293bde995cf010001	\\x6fc343ef4ac988479b81e7fbe2232372491e1619c5b8b03e1d80570460e843331dd53dce8e73bd00c79750130b82bf9125512be31264fe7559010cb75bf69807	1690879391000000	1691484191000000	1754556191000000	1849164191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
356	\\x54e35b62aa0d7a4b3d8395906ee66638cb45dbd05bb643cee6886641e372ba7bade0c9712d38f9f4b956658d36ff6aa22b8966bc6ee89fa8e53a3b600de4c6ec	1	0	\\x000000010000000000800003f33041b95c3398ed1042d2fcd410688b1cb91ef0291ec0f8032075ae56fa2854828511684c7cc81a603d869c03bdaac6f3e151a1a1842ff554aefa2518423e7a1e21be7b298895c4575edec842c53954f8aaef7e697eceef5a8d41b34e9d52cc70a2fac73b8ef8bfdbb9fec0152e09f4d587dda7d49facbd0fc5aa4038c63361010001	\\xc60eee10e6172af60ce973ba14a0597af06ff7c16e41306bef20c0ef3b16e050614954a201ee379e6acdc295c006fe8982531ab2804a50055464935a60ad7905	1676371391000000	1676976191000000	1740048191000000	1834656191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x553ba824ee19de39b8fabe67b723bf7f5a30e6108b721bf4657882848565151419a9b7bc30a4055f880994951230f0e541528c5070b58499999b261dbd41b346	1	0	\\x000000010000000000800003b53fc2be4cec573ab504f38be5ff945998e9de53f47ee20f094e4da5cbf25ddea4b3a8d043a47d0ca9c0d0b6393218d86ac6db1f1c03656c6dad2a709b2fefd825b01a72f0a746e03bf9f2456d2956a37ead779504b58a956e59ae4ba17d62ba0d8f2e6a76ed4f95e9a5bf6b68e36896c50298b5496d7e366c76ae6f3ff5ce25010001	\\x99d85773b4a6564296d879964fb83c7fb6a15fa25529b1f5535c7dd9f005c1f719746a7cad5ad98ea7cce40730d84bd389dea1006947ce05084864ac77697506	1684229891000000	1684834691000000	1747906691000000	1842514691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x565388069926d9e9d02e5097a30a37d907a63565a4b24264a2b8a1d326b81ba9d3626319f43d35de732868da7956f0bc4ae5c3671a126dee47cb8653c0b1da81	1	0	\\x000000010000000000800003e8a8b87ea6dcc1032716c46ddfc6ec2524d244daa841a0888a56e5d2c6246bdc965be2ac5554ef502d2602eae5698e6cb3b3dbf63c67592a13bc3c3bb0fd3ff0e16b2d3176db573837835548d56adc79e533dded4e33b015aae8894315227bc7b3fa8d1021319fd10c6e1b707dae03297df4a2f3a2bb91dafad3336dc2fc3357010001	\\x2d057a4c1f8b2bee696ee71d3c9779473bfd92b934185e004238ce6828eae7eb4c7180e3e6d626f09503da833464c6c1dd520fa199ca709d071eb8983f52420c	1671535391000000	1672140191000000	1735212191000000	1829820191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
359	\\x5ac70831c7ff7c5f1be87a2370b8d769b87e1111646921410759fb29a5fba31d9fe8c418bb292ab1311bd7f1e63e31558a6e5abd67217aba8e091f5af7fec7c3	1	0	\\x000000010000000000800003f07314a77e0fbf29052163e8159820c9bfce64af88f2247d8faf5497b5931ed8e0bd5b1e24171dcbbe59ccc6104e03265124b4f0941596392fb15e3ace1c33feb12a8ace6d8a122ddb4f5db791f7da070161bea96c2250ba19b8e520a08ef183f390746932568b0b8b1733252122a44eddf9ec5a82f5fa2a1a6bea18a53b1905010001	\\x715d1460a52cd12f39fc2f2cf85a162beabd87aedc2c9693247b68f0ea0640825485de47a8b42c6fe6cf51a87fe5156ee0de67fb201cfea5e247a594de63f403	1670326391000000	1670931191000000	1734003191000000	1828611191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x5abb56aeb0438f4d7adc75f4d78c248a097aeae669222fb845525e2287870ecd90c11d76761fafdcd92c12bff154941e1bbabd7787f77eb1a41e48b2429ac9ee	1	0	\\x000000010000000000800003e72b0a94b2cd4613ad6a9b8665f5b49ec0fdddb9454c2fad4df741c42ef1ad3c3964e862d4527abab2d854bce9b960e4544d7a5061765a13ad0c913250bc4373061e83a55c7627b713caa6ee62d94f3a4af0e06335a6c980a423ec96aa06b45e07c9c16b7c787f33dadec85e06fcda65975710820d32dbcb147876e200026ec7010001	\\xc0e384df86ff878f330060add2c4c0a8624eae153639b1f84c19b1288221453a9998a4a699920241abeb042364ca63fd36aee4fdb91249babf27ddfc4788fb04	1670930891000000	1671535691000000	1734607691000000	1829215691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
361	\\x5abfa4929ebe9cfbe68f1430ff22af15412e02f490f7ba6102fa16b463f231614307f7bd4fb46fd4bd931c393c93fe2b0556685cff2a0513e723a457bfbc5fd5	1	0	\\x000000010000000000800003cb2dddcc5b5f18e828c92066656bcd828e6c33f44cfb899077a2f8400ecf70dbd4edd8929874452eb3667424488ed360b874459d947351d8378d747dfc4fe7be33442992351eed12d0025825c9e23eab4f70fe285adbf8f78956e96803576be63053fa19c68f93dd31a71a0bc2e8a76cc94d6e69213026f39042089d4dc43b09010001	\\x66c06406f50176f7f06678381783ddfec4f76189d1b09fc29e4284f5db644446c0c4a59cc0dcf5087fd207a49415c5029d2646005936eb66a396db6f0307e900	1683625391000000	1684230191000000	1747302191000000	1841910191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x5cfbd103f812c409ccc69ab986b3b94bd275516439a0f23138ec8693fa6489d655394f422ea4d33be92a49c0b1ed7e6cb7ff159d0413e236180820bd21b6f6ba	1	0	\\x000000010000000000800003b27b130086f6032a49ae85a82f1215cb5182cb1f77e8ff886bc62a47abc11d70f76baaac84014ce44fcbc1b7894f8061ba2762e625fa28a204f3dfbbc5f453d8d6367705b2eeb5ec87272db9b6dea6e41338a1eefad8002e82babe41abe2d4c9b61d130cbec8eca0fe3e0d66344d602026cf6f27696192553aecb3fbaa3ca3bf010001	\\xd39ee33c232dcd269c81c49d860718ee4e1624dc616d836556dae11a05ba38cc2202651cf8be00d7b13ba22185acd5bdb00767dfe2f111d80248784d6bb5ce06	1668512891000000	1669117691000000	1732189691000000	1826797691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
363	\\x613f3093cc2b789060cd8dbafa5337d5f4b2fad2e0ea3daa7fee95c8177c7711b37164b38520332d87771770cd74424c5c47618082d1191bc6758603beff580b	1	0	\\x000000010000000000800003a58ed6fa49d6d594e7a44a0e2081b486e5e356ec15a141bc9b08b2c17882ad0e30c4276f113fae3c7f68537e17c1041d769dd64b7bce3b4bb39cf8bc3968ac8c0f6a95dd005f6804c46e4c173e35e31d2f5e5f8621dc0ba5a331500a0d680fc3c01ca6f4ed75b9435e8cc75cfe58c45cf6756f0f1cc762573d9080427ac6e0b3010001	\\x493d1d1ea084a6c72fc5d193d93d030ce4189f6779adf13083bc89c1a777c38fc85b6c18d6dc65eb99cdf5ceb99208fe77fef81e8a73bcbf092131a0c60a4a07	1670326391000000	1670931191000000	1734003191000000	1828611191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x66d3d941363638738c599a3916f2a12b655fea631459481699aed0c3fd3c93830b09923a1f0e2e2c206f51f4758af9c4962f63b582068d43d695bcbe1ddd3a9d	1	0	\\x000000010000000000800003df21930aa6d52d10d7e5a53eb8d20e27126a320ae71d914effe5e2d3fefcc5309034bea3b6682746c154d89eb24904c702ec36443c48551afc4b19a7b6a959d74b1b4a08cf4235e85a438c7ff428f8d8a0d9db38afe5fb72aeeb200f627c4173a6bc80af81e7273bb0f52250766337efb4c80edef58e6c1bbb7dc8b3a48ff407010001	\\xb5b4ce5e8ac02218d72e64fa57fc67a2697e9e853498baa438575aaef4da84da7a4ee748ba3503663916d48c845978f89f845e433325ea04eae68f78c60dfd0c	1678184891000000	1678789691000000	1741861691000000	1836469691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x67df1354f652de7313f78af1764d6a6e62266fb7621b236c943ffdaf7ccfbb36adfa412265d84af2aea6e7df1b82e438b4184fdcf8fc45da7c0c2c41bf91e932	1	0	\\x000000010000000000800003c9f1e3fe483d56c0d1b84eb4a4ebc118184dba01ef1b1e71621228c43f7b83eec1a1bcd5769e3345df880a15f95d32fab20621cdc6bdf5ba8ce17a628c27ba0c221129f7de7c16e6cf0cec7fa0dd87f6cf1270d52262124b07cd2c3a043655b43d3738f07d5e6b498e3a927facb0756aa34db2ff727c41147ff544e42f991d35010001	\\xad2097896777c9b503e666858f2c2e2b75d2196c85e918695e7676108c4fe67bc7d9233bcd2ed83561f22da7a4361c808c7eeea48a114c8534dd83fe5d95b300	1675766891000000	1676371691000000	1739443691000000	1834051691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x6a8bae13453844d30bb9bd74f742cc4ea1a2d129deca6d60dc1b5810325573b8b8ad7de643bed60f73b376ac65bfd80bf146ad82fdd590ab39b88b4ba4471c36	1	0	\\x000000010000000000800003c8de41e406f6183395e65e73971fcb0e19c0f780e2b16912e67ebcd246668f0b3f5b5faad2ccd902486bb64f8fe5bdd453137925b1d6e70d3e8c364056a5dfa6dd36020ec4df886c971fb2e7fa19d35e25995b7f616aadde28a4e98110f53950c0082a5c76645cae2a650fe7dfad41385cdd9f434d9030f721dbbe38b650b717010001	\\x5302557b9a9040bda381487315715a98310e0115e733f1a73c89cc3414cdb44ff08aaf1967ed5410b64023c5fd9b573c4e9f06feeb2b250b821ecb82dbf3f700	1666699391000000	1667304191000000	1730376191000000	1824984191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x6a5752d1761d96851c7bfd5bfb96f3b1fb1726a164bc18dd764801921ba36b6cb40d492697d13ec3dc4f37b65cc2ac6685f51203db4864262b6a43ca0b000c71	1	0	\\x000000010000000000800003d7d035e8ef657ee913a4b6e4d0d8c8c40f1d9e0f59fd1c902510a98c4a63e37b1a8f7e3723e7ff29554513fff108c08efeaf6c9199c60f7cde9435ffe835fd5404d030402f8a77aa199d4cb83c57aea19f8acfc94fa652889f54056009fb420a69f1b222cadffc3ece1d3dbd9367de512db50c52aeaa1e11361ea2110fc35e6d010001	\\x6e39409c91ef6cee0c9f2dfc314649a3df4e0c76af467a1e01533301fc6118e450fb580493e24bfc616543287a7bcbe7fc0985426664367114ed725401b5560f	1686043391000000	1686648191000000	1749720191000000	1844328191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
368	\\x72d72735127b556fda829d592461280b9647f566ff25c4479a81883da0cb58a9aaa1ec2a3cfe2b3a05e298c821b9ba0feb109b5a7f65206d0e000e57c05a005d	1	0	\\x000000010000000000800003f20e5712ee2f27d8e294881ea6897d3801b24b7e6927c49e1140fa65f89784c1f9775dc9c77c78789dec56ef5f6d9f1d219ae271d5f63c404784ab43294dfaa17eb89c42e56cc882100b1c0b8bfce28681ba94872be0f50528f89168b8c2299542a909ed1c4560c8c9ef40d3e2d58b8b27d375db49dee4e25fa013e7d7f037bf010001	\\x4df61efbda425e8bbf34b6e039c45c15e3c99683b673427a35323a8e56aed64f5ee1fe7797e2ceb748cd479b7f9e60201224db749d8e728be4973643c7227807	1661258891000000	1661863691000000	1724935691000000	1819543691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
369	\\x731320ffd290001d0d11bd4bc619d06bdb1e1b9f1234e524569d8a3e86a35366e05b4c73b678cb7430dffc68fdb401801a832a3bbd4b427cedca62bb2ab5a776	1	0	\\x000000010000000000800003d1ea7b5b7e6bd85db684d113516417074128041af5d6b76415abbd19c3b342d4260311957a4f4eb3c1e1d6b2627e3576d61d7c8334fdf9ebeb16b26fd5e7fae8495736b3e83a647bd03f0a548ab348da0576ac5d9e108d87246ebdc943f59a6707425a1d4cdaa29ce2f075fa4400dfbf33f17934a95c34f1db569870c600580d010001	\\x44a7130df4230dc8d85d80f2d62b0bccdb869c9d101bbee857fa5d5fa685650bf1b46cffc8d0d00d3d8d50c074f964fbd31507baf2808b0fa7c000acae79380d	1668512891000000	1669117691000000	1732189691000000	1826797691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
370	\\x7c7b1935692e91c2d717f7c5b83afaeb5421dd675129013e4d2d6b61009a773012d883c3c2a058ca20eb0f71502e301df21b9cb01aacf7a91310b642af6cbc01	1	0	\\x000000010000000000800003ae7a6c7fff9e7a903142456386ee2995b198667fd4a897d57b47212cf9cfeb0dc289763ba0cca23befa2668ca0fed3817c5dc06b80e03fdaacd8d8d17d669eacfb258e2d5cc4adb96b3b7085fe10d70e2faed2c9eb05653f51a03a4023e615ada6bd37ec546934ca763ed5382bfc4fbfa7e1bce4f9e4b451daa72b576ac48be5010001	\\x41150dec0200afcced8db104097424e470dfa87d4dab687bbfdf1831861dd8db0db86a4f60240b38b0fafa54f2bde4e8e1796e62d09ea7819d0e5a7f4e2f7504	1675766891000000	1676371691000000	1739443691000000	1834051691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x7cef16655e517b75edb25be5f4f062a72ac9d989cf91f37d1358df2697f81d3411f0105cc1de58dbcfe5e79cd49411fc1acfb25739b2b87a67edd15857337815	1	0	\\x000000010000000000800003c95aba29562c408250e8663e5f433c68bb45a8bdb5872a25402885f80ef67c774a451eab6b6a232cc9e32d4411f76bfb0fd493e2e565ec67cfe19940500abbc2e880da221328f9ee15eeef58be7e6818615e890fd3c57c1fe77cb1926ca6c2df14abdea1693ef43984a7bcb41257852b0035cc3d5b65aff37aed7ecb27d9e5db010001	\\xba4f9db321bab5caf66eed6a2e40969b44402c9744f0a878e035a29e9cf4699acb21fc4a5538029aef2aed5c921a422b7784376e1df247d4c8bed544649b8b03	1670930891000000	1671535691000000	1734607691000000	1829215691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x850397ade6e9fcff71490da5d8866df6d2fc576d041b0fd689816700cd6b7741e1e22662cbf1cdbdef309b5fe0a550bdced2d0a83ba3b22c48f08a265ccf662d	1	0	\\x000000010000000000800003c2039d8648e7c52df5f82a1079473e0951e3aa13716e2e33b0b334cd8e3099ada1d57c1173422edf903da9de0a59e5ec3df04e04433ff35b4f8857267908d159332932b04d820cd2906ff6a04b3468bafb915ca5c1d1bb0ded89801999e1cf670b9fd5ee780d12c99b7c53927f9d90ace178381b1e77fb5410095d4977a5e47f010001	\\x3819cbc7a54437c767dc5c7c772b4c374ee468fd37703444c9ce0ec8cdad8342e22dfeb7124e3116504b3c484c5dc5cd2358d97e93cf21f313154cb8c545130c	1688461391000000	1689066191000000	1752138191000000	1846746191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x86af23d1909c63d8764db577c789b866651f8b6f68d621a25085ea71f5f9a5760e864676b4d52b8695a52b2fefa0f8c1b2b8b8d275df9baedc0b8b5bdeed7f22	1	0	\\x000000010000000000800003ec587e5203ff83a6e2f0b16960634ac298344638837cce6566922a93191fa265ee3d7dbcc198244401bf5cbfa3adefea2098c02a835fb661ab5dc8c5bdaec3608f8c44ed79e56b918f605fe7d0dc888539c0247a4502dc24a0c076c456a44e05b7dddd0f1d269dc56744e3e9a8de8c9f8e7d48165fb1b72bcff6c97af9e0ce6b010001	\\xe3dba87bf9764b9d3439bd97dd9eb3ef62cc75802e75fbd5ee398ec55fc470d050a4c1f772ca76c6d47ee7f3d9aadec660648ad0a6bba91515173245ca6e6009	1678789391000000	1679394191000000	1742466191000000	1837074191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x8ab7e1c031e9026111629e158929e94f9c80c8320486b6983c7fe381bcda9f170b4a5204debe0a5ad204e3a47a23231c1f798e5ae2cec9d2c2e5d5a33a6de21e	1	0	\\x000000010000000000800003edb714a18efa5f6888cd71e5d74a9970e3cebec1c8d067ba3b96d364763dd770784daa5ab2d12b58adccf9e7279aa78f4625de755bc547f0a762e25da020ac43f301496da88509f47d46d60300d135e3f7e48f092c14894faf43e1bdb3abe4dd4d9f14f297c588f79b502a218ac06edcc165826f06db1c0c4db9dc37ee7f79d1010001	\\x510cdde608d1e03278fc76f812d77e78102e5b76a8316bb128c6e07ce8e8893113c97b165956c885c9e2ac7fce23514396b54390b3d256c07c6aa5bc9c20fa05	1681207391000000	1681812191000000	1744884191000000	1839492191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x8fdb20dc438da78618e10a51f2ab22336a7ba816d5cc14f285ef87a14cd122b1945bfa8f76dc08b2d71510db5379596c192c541f74acfe82c480f8d40a9bffb4	1	0	\\x000000010000000000800003be1017dcd116be39e5d5c96a7404d9c3937d95e141a161cb2f31e529bd3f1f5d1016344e932fd4b66c7d9ea9a19bde9a764c5a1991a1016ac3aee3685370f80aded3a226f0642bd110844da9e7efb4bf4c2aee8f7cf4c909c04fd8ed003942787ec8ee12c394f17f0ac6b38c75ac0dae4583d38b704d184b48777966ff2c2959010001	\\x36993fdf1e039ea58772e152a9341ea491bf802a235ca0bde2517eaebf95a4752ce3ebe6b30a021f6c5fe8372f0585cf15c4f79f3aa734e8b4ddbb776964ae03	1661258891000000	1661863691000000	1724935691000000	1819543691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
376	\\x900f5a899b6247f450573e83d11e43bcc2e3861c95887c4932d2d8a2f7701b362328af542e433959d770031b1249db5ba33706ccf90f3244aa553cbe7cfc4f03	1	0	\\x000000010000000000800003bd99ecd2028b5766ed08ac22952700513061117742b11ff5c0d153bb723c144bfd1ebe3bef36e9fa8d7326e6b1e8c5ee6d89a73b441f4ef478df8153a5d6d33930e777fa2f04e41475290022e31d48d5baff57e8fed73b3d0ba121d35ff4099dfe9512ef528514685028109ed3843c975f04ecec961ec0bc53f0d644c4d84b2d010001	\\x0e0494b69e5e9dbbf00c8c5a3d555805dbdb6134b50749f366df0252422b8da387a1304571089539d137d17de3191c4ac71eb0d12f2f318b5f762411da37e10d	1673953391000000	1674558191000000	1737630191000000	1832238191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x9167057e80d1f128b67d471e9e5b6d37c42d5e97f8b00e1c4fe94ec158c87f37347ebe4457412a4e3aed066ba5796a6b9428cbb79b0b90dd1d521364169bfee4	1	0	\\x000000010000000000800003bdf6e2bd08c172ee2f2c1a7cfd8b346702e8233776dbe1d21cda17b4a7beb648a546c9d834e15d1b433399cf67b1d850c0e026bdb1df9d17da88cbb2605feb6e1ebbfeadc43be6147548f4bc0ffefa938fea03ca8a21fdc490d8e2e5119dc5077f22f0ed1065d34c9abc2f1db8a02a1157bc1f801f1aee8532316d7855623831010001	\\x02e15876d251c2274c3239459d5e4e032107e7a1f6259f1a19c5f1715d8555a994ad451ea14d89e41465a912d7f2be04677df6d73b250b9ef313817bd9cb680d	1690879391000000	1691484191000000	1754556191000000	1849164191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x9313b6e98af9ef0d1fae88cfabe50bb445942d8769105ff885a7879be03c0a4ceb4ec0398082df68b93f023af03ca1aca1fe74c5409ba588da9c9b9832d670be	1	0	\\x000000010000000000800003a0a7b26f14ba593483643ae615e8c928241f32764e8676a7d5465d3c1815cfa5502b0182812ee9f3a5cf0e010fb8b018e0eedfd9b426088afc68e67bdd1955151b3a830904f35166f1db5ddbcfe18c13adfe39adda2ed33073924f273119588c4b24db195996b7d796d7d144069b24969fe5a63b1e1472be15e85f65477f65ff010001	\\x9a2389d0eec5faebe1c822cdfac13f57662c61f59a5c0018bc1e1825bd63f60a9b87f3f976915bc688341f5f80eace9583cfc2e37c15cb11e70695f4a91f8e0b	1661863391000000	1662468191000000	1725540191000000	1820148191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x960323fb9dc369e3dd76ec552caba93b3052f1cc03499b3c4d4d0f0c40d1f02aaa899ac9815bc484d729ecc0b87428c63546ccb38ad2cceb44155e1a0fef66eb	1	0	\\x000000010000000000800003c18ea53c8e89e2c44c3646af7727047f5630f45efabd76744aa48938a5d5f784a9e1a2703cc6880e99655fcfffe848c9d9491a66242bd684a7a73dd8c715973b352588acfef3437c16506a6ea2d63d82561be655100d3020c5a08634190ea98e8cc82e3003ef341b8769e0ae228a5b374a06e6edc0d5e3962bf316a09cff35ed010001	\\x183d84999dd14eea2df3b4d549b0bc8fdb021437e9052471bed7ca006303cf5499ef70b08dfc4751e2bca89d50a329d6e048c2fc3125f7e9c110b738c7b59008	1683625391000000	1684230191000000	1747302191000000	1841910191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\x97c37a4f5e4ad8229834c5c353cae83070dd8307ac9aa79478083aaabf42e886e24f2f90b114a5d2082247912411e95c4dce795d7792056b64b013b6c8359dd0	1	0	\\x000000010000000000800003b7c8e0adfd43d853e0e6f774ea9becced3f9bf1ac7500b21982894aa98d114ec50ac303ddf8f916e56035fae57d12823a0eb9db08d247079c0c98d4d30a0c604f2cc2d90b38ab87f7074dc553db874785db066b958e5f03b86ce7386ac89d8b4da123db1428b0fd4674aef3be01e43416b1bd0ca151a0cab7af2d0c6ed69612f010001	\\x5594b8ffa84d467677b3ab7856ed2ed2bc266c2a72528a1c66875e88f05277cb03a91a09825da9c927f43e6af2c1d3fb1230fed34f7bfe38190cfb1abc378205	1669117391000000	1669722191000000	1732794191000000	1827402191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x9857f315772e5438f7c87fa90d8df967dd56f3e483048c27a2903d38026c10968bbbb8426fc3271338a9de8d4c1fee53d010335165587f0550f82aec13cd4c0b	1	0	\\x000000010000000000800003c964770f0cb7efa7ee9ac804c98e7d04e4664eade5cd6e7d863e3de5fa25297a1491b2339319d55bc32af57d83edaa293885497c2738178599826808394db09c15948ba96000a564a0c3dec3827c7d4c7b5387c3093081f61b8b1d9d39c0d415379953def6e44d4e7ef2a6485fb6465c179de2c404d057127ad4d41b3c204d87010001	\\xaf5f91b231a73095cbb6b43fbc8096cd8e90322afec2f700e11ba5f1f1a5396a1791cae3c19b9744deede42889562327fcf191c8b2cc89a028ba2914de1f7906	1678789391000000	1679394191000000	1742466191000000	1837074191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x9913c22d604b33d5a81b52996f4b68b28d7c85ff7a88297b494c20662c08819ae88da3c5bc0b7b253dfcd1996828f5030e10638b85c29b38683b738c71f91ddb	1	0	\\x000000010000000000800003d346d99c44ba0da5007b54820a90a56433a294fd78a5591c7496a0e937cce3c825348d5fffd845d351893df669518035844cc8c77b5fa34035e9c6d5926608d6074e5f29d2e559ca9719345f4c9c6c09799489e943982dfe80e4ad7dbd501787afdc11454f56a5587c5750bb602183a01dea90b478f74a1be414c47197068be9010001	\\x613a3583e809c918fbf5115479afd8d14045356a51f1c3927a4e2c64e23f0dfd54d9eb2d4655a902331518f4b0ead223770d0bb3503cd26c0f1beace825eea06	1675162391000000	1675767191000000	1738839191000000	1833447191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\x9983005b3b0fef75f74ea1b4cd356dced0bb5b008274520b02a8b6d730123902665e4ad563255433abc842e68734e060c609fe44043468adb6fd02c10a4381df	1	0	\\x000000010000000000800003b299061d49ca1da4b5c6b8a0d73e292ca920b0f6b885fc25c865ebfa57cf435ecc4ff80170297686c0e33d686cb2cbe702d92b90196403e306e6ecb0c1732152cf8d26625b0dccd2af16a10e080c1f0978f6f2bbef18e05bc7e440773a3629e46d3774f3ccc39be7ed60745e9e350467a44321d2232b58b6cb1eca4c288f97b7010001	\\x4d7b5667b3797ecc8773d98b1b55079aa04f4d73f66963d3a1aeb3635f9112098023903052753fde3a5ea5f73e541bbe956e88ff082b1eb483da01387501f00f	1683020891000000	1683625691000000	1746697691000000	1841305691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
384	\\xa323e82a6efa801371262503e8d24eca4d22bd0caac6ddf90da9fce09311c2f681a568c2309afec0f1668f7646154c6c789b56bbe89056a0af9d74ff3fd3b764	1	0	\\x000000010000000000800003e706e9ee40f943050f486d15189af3705a373d535e2a6103b2b6e7aa496b9fc6a415213d6510a0c3c9b5bc8db0c8be339a3699a2669f700604bb6d0f8ab6f3df6cafe5d482c10fbccda999236571b5df6248b6503876d9e95b3f181cc03c58cc9cdaccc0a1bbe726ad984007a72bc89c48c39adf02fc2892e08739df22d82667010001	\\x9a95037025370451965dacfc4282ceffda676bb708acbe6501f9f1f547b33cc6367d93d47faf74e6204335458819e178c1e501674b8a5a025d749d8f817eb704	1681811891000000	1682416691000000	1745488691000000	1840096691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\xa4932d0c2f4d7fd1f8e98b6bcb235e4d6494b7dc2f087ce2a6667978ac9b8f56792a872c0f8c2b271c21f731d1dab3eaabcb6f8064e3f9aed702496404fdc3e3	1	0	\\x000000010000000000800003bd8f45ab7cb7132e67a6770607c110d82966cd0b64dfdb25fcd455e4b9905b3c2b5fb7990c4fded4491492ba6e6d7138e73c7d6ac027ae6d555e9dd10fe6c02e9f790dcdf04c6919944f05addfada4a7c310d4de270408e6992b09b3835aff271fcb853d969c65cb74c1ef863cf9c7471a30b93d0017b1634d6623252cb768b3010001	\\x654b4ea61f59367acc617332dd40adbeb90cdc96f03a43077b3cebe0323c64f34e087ae9c1d4444f6a592e2f1609298ec13937eb4d40e5e62641135a13b6ee07	1670930891000000	1671535691000000	1734607691000000	1829215691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xa5574b5970f7346af27527804bda29628f18ea637ae098905c59ed98ccc9ac1d6d54c836f320de5e2fbc634583a8593ee99f574e7bb0c3dc67c3cbe39da7e2fa	1	0	\\x000000010000000000800003f037d10f082d8a58b27d6516fc770389f182274835e99a69c8caecee2d96ef498782a9c16150e028c3c503a0400475235af389b0d74929f4d1f96ae780f5dabb18d2beb3a99bca749e95b3ac097b47f98e47ec32d452d07956e68696bc42a9f2d1e497ade99d775f19f2a83e5601c9fab5218bf54324cfa611d35d2c9c7c6205010001	\\x3a58841966f2867fc0d8e029000fbc1ab0cd78028af35c045f981b648b4d88f9e766086b108a5c71f14bd3d6ec0c0e80d43ac3c2c281b4bb3ddb296114ab470e	1663072391000000	1663677191000000	1726749191000000	1821357191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\xa7879c0f982518b85aa8b7820ce1e721d493b5c9de4e7947a8828bb336b5dcecb8d97525d4a273c3a4c6b19f3ad57a3918e1810962af979b16984a05447acf3f	1	0	\\x000000010000000000800003aba0aaa4f2158fdb927f394d8175ee2e7e127053d057e9e3c4ac16caf624727971b796d23648e596d55cd016ec802c5653f9d23bfca42cfc1d30aabad761af1ad0056a17e01fc2732019ee01e4f64be47444a814c49c7d15759b9a0391c43a2353ca997849327afcb29b2be18245a799a3f27e60cf3b5c207d84f037d7f8fe25010001	\\x68ff10c1d1d9979d250a344c1f96cf0d0fb7f6e3ff559d2c75ccdfd3c91acba9e2d7dbb6176104de0091803c51454021bcd2aa4ca927eb53ba1ddb02681ad209	1676371391000000	1676976191000000	1740048191000000	1834656191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
388	\\xa7373a85ad017032c4b9ee0fa125e35f8928228ce4090221bafaa4df6c7855fd05cd11fe0de13b3fcbfab498e78b4a636b81b4b5e331cc79c2e598e04d735d05	1	0	\\x000000010000000000800003b8e116e3b340495e5160ce8f0cdcbf0325b0e81f054f7b427d6a8263ca2b2f21c850d9212154a7557dc0e046d2e1b1bec804f61406e25d297c2145b8f2a3a4e255fe35233ed7a28a3d2b989710e37270f2dde7bf2850d09caf6004c56bdf68f3efb9827572e3f4dcd2df2505967e4a6cb8fbf40751c42359e8a42684bda57a4f010001	\\xf4aef45a8c1a1006ead5d635201576fc3f896b5c247858f612b6638051bb60541fe65b6bb1b1d4db2c1afab26072a21649bf3abafb31c2bf8b1707f14601ed04	1663072391000000	1663677191000000	1726749191000000	1821357191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xacef168665da9124232d9ace70808399a3ff3edace123701e07fd8d84a013f1e7d00f81f4c48b150b0e5dfd6a6761dabbd31f1533fc5d361825393d98f23e9d7	1	0	\\x000000010000000000800003c374f4254ba4c8c9328c64b8d4d19b4dbd6a7d20df3b3cd96d117abebb212b75930ffa920e7bac380ab60ffd0e1fab3c7d948ff2bbc56e774becf5f8135d913c981b48acf0ca437d9a6b76369f8ef067c7380e094d82b5f3126c38930102831116e679d58769298b970fa9a275d8826db28ae25e2beea1e1ab2589228d9ae445010001	\\x41d923ca68ed11ed7596bbb9376f13bb3584b6e846dd7e84af9a36fca88ae4bd067ae670a1fc3189bec014a4dbc553619bab7ac3e5fbd29cc1c06d3718f14109	1675162391000000	1675767191000000	1738839191000000	1833447191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
390	\\xad43d087295c33c021a6cb15e6f7214c3a3708a2befdbe5fe5e418a3b5a72972f4401dba4c19db61a320613c9345893d6d774a39d4ed9010a350d67177d8384a	1	0	\\x000000010000000000800003f6564ec085d459c17bf233dc48440ad647ef6ee6ee3a2b1e00684a525866bbc6c60d60b73d00af933a767b5a5acef6b6befc01a3ab6aaaed104a6f2134bec571f0a712e1c1ce07390695cb983f185f7736dbcf119c09da081c257955befca86c9199db7286ffa4c3cb80a35b449613542a20e2445d7ce11532515b9ef3c0a5cd010001	\\xd45bc9c67a1ccf989a208635ea43f56c397c1cddfa70d425bf0a30c089a406ccc8e07dc599ee2e37f6cd9cd84d8efc96e56d8ce6671c0fa848db202874a9db00	1666699391000000	1667304191000000	1730376191000000	1824984191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xae5f86d951ab7d8cd40d48beebea5096b5931ec53b6feb858fdba1f3b4f6dcd5852b93f32c327aed32ad29a9cf38cdbdf4badce01cd1bde7e7f3914cf04a0b0a	1	0	\\x000000010000000000800003bcb39d968a32fdcb7cd99e8c57309b8cd3a4f093354c45070be1028e727a85a8855d7a75533e316cebb55b921ff24dc559f9a5fa3813d7df126916aedae0c8f26815bb5e5a00ff85b5e03fdd19f7dab0ab69e02e9f560994cbb21e582e0afed1ef4771372fe4710a6c42e53913d1943758297cb79ad27e12988cafdecd04a1a7010001	\\xae3d57500b3f0622e719bf158d94b99000c96c8034cb8ef41709588bff132fe051f08ca4127993e5230ff578d1bd975a8f49f12392a4e53861dd7dbc14134108	1660654391000000	1661259191000000	1724331191000000	1818939191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xb0c7f37ea2899e1d010246d342470ca6ea00f59cb7b19d711c9b94a31127374a736bbe0e844ef5a78e1693f877447bd8d1da9542a138d04364ca6d440d074809	1	0	\\x00000001000000000080000398231dbd949deb73e1a46662ee8efee4191becc12aaffd099ca6376d8f24948b3e9e82151e97deeee4819a3db9a8b73fffbe1a35a7dbe07772935286f96e0702471293f7af3d06d1d146c991d8e5460f1f89c1032641d278a25b1d7c678728d77c8f48563cac8a165bc96b1b6dd9c6e2f2cb8c87f24f1fe7907af7e2b8746bf3010001	\\xc3cdc711a96ba9f0ab171684460ff3bb816ba250b738b74402b0f1512941ebbe33acaaaa31dc1b2d51bf298c356f6c50d74f3d67c1681bd81c824833211bb304	1669117391000000	1669722191000000	1732794191000000	1827402191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xb27bb12ddb8b19c18103408754a72f8130cd198ceac1359565b4fe9fe8a03cfcda7cf771dbb502b89116273bc9fdfb10fa46837479868a0bcd62bf58c6724824	1	0	\\x000000010000000000800003b1069d30bb01464d3ffa28415ab70ede90f8829b707daac9c5c683c54af65de814be9d7d8c5f314bfbe01eb88c73b54a4dc39f1644de41e4e75b701f84a2cb20f6b5c6426afe2c348e07f46bed860f6ff2fa0f9e8575c25b4b25059e4525f80c52fa6c55e518dceedd776b2dc5a1102f3b33db4b5c4e849b784f72aa8a6aef71010001	\\x180c467759d2709d3b326399f1a03850b4f87e3f014b709399adc2ed9b0590585b964a8867e2181a07cd4bb7f8c559140d4e58d2bed7df2907fd9a06fb235e0d	1670326391000000	1670931191000000	1734003191000000	1828611191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
394	\\xb3f704c905f088be462d2941ee3475a5e1c8f38239407bed9c844f21f69e044380333410c91b33d7142a349671b50aef8b458b6f7c3583dba542a50d619b6b49	1	0	\\x000000010000000000800003a29ff9d73771273f9429617d785fcb7e59946df595ce1df1352308f4d41b76930f9876f81d7e95ff9e641d5963490989b6fdbcd814add8ff11187c6162668c1e10136d61f2801bd43f24268192d972e4f5f581a9db04e9d74f6efd069683d43d6c2e2530cbc538abd7b8ede7b49b7f906028d3c3dd6acc0287ad7e3a3bba0165010001	\\x9206a5d2b29288c96ad2a74fa3826b0ba977543ab2e859fc11ac7ba95a90315ae2a4c77e07445e0552e82344e8b4e1a22773c6c61bd5f957ce5597b08ea16604	1677580391000000	1678185191000000	1741257191000000	1835865191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\xb6c7a8b73945487f74606af5479c699a68f8b494aa04b4411523f16db952f7f9d431b861aa21db3803df08949ccc21e4957e843ffbb580a2793c737fbf81c61f	1	0	\\x000000010000000000800003b838f44318ec9500e9bb1d7ef82de8c4d1c4738b2abba70d31db4f5d2ec084f44865653518b517ee35fb4c6b4b9d958f93d7b43f0cb7d03cbb2a399b41adcd83ed4a50afbe555463f90c4a36bd204074b8f7d7664776168994d537783cb37784866ee58eb6ac0dd08c22507e22b473832da46eb1b2940898722fda461b5441df010001	\\x38bbd4a982ca91bbb9b3922379d203886a23257f42bd7fe6e39c3ce3ef3979957391ce850f8c4d7dcca6827c2fe16e7973c95c1547926b137ad49d8e2889ba08	1677580391000000	1678185191000000	1741257191000000	1835865191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xb72360c23c30d1675cfd2733c456b085aa3ee7d413963ca5167d0a0d7f88d429f8280078924d2693aee67ca92a79b015df67932f02b38cd76472b433675bc1f1	1	0	\\x000000010000000000800003a4a94872a5998a7c7b0aabdf0cebd04cf8ea4f587c0c62b89879d26c5249edbe01c31b97a078b34267fbdd4159e625157ffb88b2bca49ecf4e602094a165d87991d972000dc380149da434418c8402c240332d36c57c4b73d676071310c2c372faeba7dc764dea6b5fef87673bb61e6b9fec3db786975195c35853ac6b6be4f7010001	\\xe212ddb2178abb22674b21189167a80d1baa7bc53aff7edba505c5be10e5d5e8aa968de8c15e16837ebb3d1048ccb296e91c30070a583e213c27ddab95838701	1663676891000000	1664281691000000	1727353691000000	1821961691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xb907e763032218b2e698fa83db375db39956c1066baa738c38aa163bcba810b9bef809653d853f3da53cf781a74cd114034d4fbf1264fa1117619059ebab68a1	1	0	\\x000000010000000000800003e06b1e34e8c7ed979c2707177a4508285b55acc047bb239ac3ff6e5713dd4b9b16fb3baa9ffe42b892fdfdf2220acc29993ef53b073bb49c1695470fc2f2874a2eed4fb19c4353a92bc618cd0375cdb49b7bee179ab5ef123fe4f60bb7129c860ed7a860e647d7f065e4d5865e547375f5ca85e0ea9cf16a692a960ffb3bd083010001	\\x00f7630172f0420a23247851449f898a2db4603cbd3dc76eb1f9bd71f86636486cf4c9449c8c34904832af7fe79b24e49ad29f84c9c25440db1d7476a3a68e08	1678184891000000	1678789691000000	1741861691000000	1836469691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
398	\\xba1b4e165c853fb2a4fbb183ec288707e81375f05066c18ec7bb20d642653a5a00ac19ba999746e80c40b63673ef2ff62d27f4210fdcc8142e3ef884aa34b0ee	1	0	\\x000000010000000000800003b17e4b09e099e283d0588c87c92a56615a1962daa19b13ef81b02d0f02b1c2e8b49cf69f2fb59ab80030ce63d0c9a4cb30a2cb76b541248ad6452493edc97f48559f1484ca9f55adc38b0881f5451f091525da7a369a08575b83bb7770a730abeadd78f1648a81cd3029d5ba5f4ce439fbc6903877a0a738f00c48215fbec13d010001	\\x47594d074ce66e177609376b28dac9b59d5577e72fe0fdc37409f71352d633dfe76015c4168c4f99cc93c509b9f4ea7e4fd480cd297aa14b3edf60faf4a0910c	1680602891000000	1681207691000000	1744279691000000	1838887691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
399	\\xbc8bbb537fab46ea64a1a611b83d4812af91a24db1c12663525467bf364571de933b22274b57bbeff47bb7c5e1c1591e8f9237f209612510a7ec90b72ae4e9eb	1	0	\\x000000010000000000800003e3c1e714d0da6e417cdff3b564b74fa98e642486ba3efb4f37e927167f992297bf4289ed476be6b1acd48ef649c1932d0e356cc039aab5df6220f1a9fd8e4b2a8c23c91705da4e093cf030b8c49d33d10e3b471562e28caccfae70d71934cd53db9ae1f97bcf95c76e8caa373f9da6c45f66decd14084538f3d35e3d9b1f2257010001	\\xbcf2504040a448ce4ad69cefd6b3c2482578ed74c89160d44e8b2c873d2b8acf35d663e09e5758eddd4cecfa83eac034077bd8e40a1cbdc695860ce8fd875f0d	1662467891000000	1663072691000000	1726144691000000	1820752691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xbc2344ec3ba1743dbe6e8ca56c005440ebaf2aa88507e874d67f9a7cfa510664a4870608cd272c11d5a0163a68ba60bd1f9011d4b019ae8125cc54e8faed6e10	1	0	\\x000000010000000000800003bf03f649e6774d14b563a5ab7aea1098341205a1cd48583e86d4c7fe16df65b082dad8770a4dd31c6c8e266bdeb22c504a476804f1c89573bc07ca29213de2b3c7e741056a57209b53bdad11809995907822561ab6084abea57c8a715b11a898fb22927075017a88b44987e0da8fa0d00efc3acee296914b047f01ae0e65567b010001	\\x1cd7c908f0a925c78ed97625b99ea43ab0c18ef375edfd2ccd6f2a4b6d59f60f505be03da04c8730bee8b070e9860a9d6062b720b2719d385acc2eae04271e04	1670326391000000	1670931191000000	1734003191000000	1828611191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xbdefe769ab7a57f8d04e9eebfd8d1736bd12ca6ba2accc321b06f5968b578c4d48be49438994b1d028ec0ab09c4dd13733d9032a3b6bac20564ac8256d390151	1	0	\\x000000010000000000800003ab181870402060327c0b338934dbcaf02f7172e971b797e867ec292caad13b8a2c9ba67e047cf1c1ece0a992ac1432ac10942d09e063133b4b260761f431bce4839a9e4b3876e9586eaa9b9a35f1c05de721a37acf7b305c4b0ec31f7b4b03c32c0a5955aaec7df80a7d2367af241978ac4c136d7f99f15b73895d0060d01e85010001	\\xbf05ba847c888c9f83a2d2231684bb5d91579ee3d1e543628d80d774e071ec22933a4a11d412aec0d8c31b2d7e6a56c226f9379088aed256237bf224eb1a2203	1666699391000000	1667304191000000	1730376191000000	1824984191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xc11f1c90eb4dc0a953cdca71a24dfc4f959a451c169529661a57b8341f4b6262ecb8a5205e739233f55f6d50f317c6fd1896ead46f30a451405e0f2a8a5f94e6	1	0	\\x000000010000000000800003e1e80646b706c83bdc75e438ddd4547ce2879065e42b6cd5dc5113e2248060a58fb916d72a6c1ab888475226931b900f4fe1c0c32d398efedb7965ade8cab3adb18efc05a170c1eba8ddd4ad498c7b1d9a002a08cef58f9dfc59e0ae65ae317d188704b754e316d1929258f4dff39adae6a79839340beee1740d3e2f15779b29010001	\\xd117e7899b6f22b40b6677b7161c8a55b54f169e559704c686ae4b0843003e1528722ee509c50c4c0721f923f02c8b07cc07a7189b8324031f1ee00101859603	1689670391000000	1690275191000000	1753347191000000	1847955191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xc883996bec48272b9181ee565d4594eb933a72a5b34929b7aa59795c53a3f2615a326096d28bbc3a8b90cdc0dbb08a46035ae93a9de3c122ba65e69434756781	1	0	\\x0000000100000000008000039d7b9c57a1041208726644f0882bc9844a08e799558e6fb5443f1d5f81a350b2c82315fa33afd7a5aaa0381d2720d21350c95fbce989430befe9623fadd7a24b3cc1a473565cbd77508332e0e6ebca489a17fa8b4b6898ce8f65b5391df636d2255ea1c4f383190e99fe0ffb944e4920598660a1f45cb99b0b47cc3c9fd0756b010001	\\x66342233380ff5dc137a1ce6786d70e66d81b432f77d6dcba93529f8706586c227d813356881a79c74165ec482f7222b0f1f1045f3db9d9ba0d7efd3f223990c	1686043391000000	1686648191000000	1749720191000000	1844328191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xc88f3dc6c90861bcc5895b18fe4a36c9c8eed0e6a958c928550b8a2b0f529b5ac81638177ea60c7946163cdf803406cd941822a7cc68f55b69f048eb316b1990	1	0	\\x000000010000000000800003f33c66c547fedca0ea2f9fadb18228fd93db5e51c9751650779f6a0751e57e1ee5a08419968bd902de1b2ce56206dd5845b52259f48b78bd16204683b0b4ad3961fe296f57e7263fd04c7eee1bcaa722dcd6e79617d0fa6890ad9495a4eb704108d4626582846ab5bfb7495cfb97d3a4819a223d83e0cd4cf3c51f6b8b561011010001	\\xf510a1c15ce07ebc7ab19dd130d958fcbd2d6f6f54e8e88e9a28b953d378219c9008e36ed61865b4ca5d650ac82987fe613e3101e431d5b9b48096271e9bad0f	1676371391000000	1676976191000000	1740048191000000	1834656191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
405	\\xc91f1b3f5625556d5e62818cd0317bda9cc2bd6b0746abece0b735df047a6b6a8291f8221a2ec665306b9076a27c04ff138a78f9f6836af550df100cc7d70718	1	0	\\x000000010000000000800003cff19de0a6f1a8b20c1fdd6706d3a65ea8d12e7200ca786ef2e0b8c78e80f3cee57b7af0f00e6b8f48117874228021e51aab288010f17fc468eac9f6af5034213156c0420ada07dd33c881ce40193f2d1475c0179de773893159ff735f408268473200a420ff6be7569fe9d71eba7ae4d9f89dcd407c076cfb8ec619401b68ef010001	\\x13b5c9f0da334db8c16d7aed97b0986a8cdf78b5afb22889ef162778f4abcaf155b2b906618135ada0b0f608ebccb2c00e1e628a3c87e895c49f9f6ad12e4f0f	1690274891000000	1690879691000000	1753951691000000	1848559691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
406	\\xcccf8d9adcd937d20bdcca9b106ab68ad906fabddae48e07ee0eee991c66ff40213ae59cb6f7573c359cb520f38aba34292ee68864888229a1464bd98edddd7c	1	0	\\x000000010000000000800003d75e6e06f622cf8af0b1e0002229c7394610d91b97815059981fc1bfae623fbf1aa3128859e2a80e7b4ed581e1b03b13c54de8b2064dc85810114acdedaad016c375c21c53c428955aa3fcd4c9f124ebc527450fe3f56d85e53a3a8f53bc1308dc109f3d985ccf35125de9a1310386c37bec5f067f5e21c8cbb433198439c877010001	\\x0b7f14348e283e6ce69fb2c85da41790e76f76bcf02bbb458e976be94e8bb18e947e4fb0825feeda5541cc13d4c91df693c3dfcb216078adab30fd04c1602308	1660654391000000	1661259191000000	1724331191000000	1818939191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
407	\\xd037daa687edda0abb90eae586fda8b94547550be0e1f8dc63be8dac38c6fcde429dab767fa473e248ab1c119dddbc00959e2d48f41413a165d12b29f8496893	1	0	\\x000000010000000000800003c497045a08bda3d99de9e33b897a68c1d4143f816e38247c60799acd9574e8d59cd53bc0da23aac9c2b1902edc548ad084918b001cb668edf71d535f909c30d6cdcdce913f8a177d62ca456783e5185258c72813f2219456f1870f235d0286314ec3eadea5b064ebd0b95bba89f09fd28ad4829eb3bfe72d8f6fc5bf5407b86d010001	\\xe81d1fb4a24a43348f6d132af693873818e9d971675c7e64498848caf92ae8e389dccfd5861d8f7aa8094a8715c6a3531642313a450a9511de2ed5980e8b3602	1683020891000000	1683625691000000	1746697691000000	1841305691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xd0376dc3472152a9782edb97693b3bd0255413da6cf85cd7bac0bbaebe7f548d6d8157a38a74a74dcf5012e3e20c6383348452f0fafa93c7d4c95f70dc7fedfc	1	0	\\x000000010000000000800003a87e15a89a5f001dec42a8e9305bee781d19d4ec1663c167d6c77fb6f7e20d4e53db22a767db2c980a768a3cd3fb3f36fa8247859360ada773d7775803734620926ff3d3a4aa5642d9247803bc1ceb5e252803b4b4204872593c5203e06504d0176739e0615bfc90518ccf0ce5ac351aa373fe868837f029daabd5899a3b5bb1010001	\\x1ae8ab3f5aa1400fd17708177fd9b37e26ac307fc9301b5eae58e60083e655e1cfc1fbe1b98ab3037cf2946ea0e897be1a607b6491faa80c4189f81dfae0620e	1662467891000000	1663072691000000	1726144691000000	1820752691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
409	\\xd893219315c66225db4a7653c851250f7eaf36b7369ec315abe89decc79b750248395327c9e2e0c15ad6b69161faa2f9da801c1a9177c5d82cf78d0e73abb95a	1	0	\\x000000010000000000800003df78919709a336a4ff1200cc9c1c883e703640a7ad666fc4e14a950dd22e5f9634f5369c3d30c44d144b5e5cf1d3a56386fcc054d0293ab7704b176f2e24eae93fbc7fb4390b9cc5fc20e2ef690cdae06a43ddbdb8bcdf0f21977ea9e724f9a787e3695d36689f09105630162eb9d05033c64f69b3156269247599a43575a95d010001	\\xa20461b709284391a635de8efb6d362761149c281c112c692ee239b837a86926be74d529ddd40b9f331e0a1cd020639ae4172f5ae6420effd1112ce64d97f702	1692088391000000	1692693191000000	1755765191000000	1850373191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
410	\\xdd8b694bcd9810e381a24e05db6f37ab551aa50ee37c77acb706627eee9d5904e6ad63e762d12f8ee637ad7042dce6bab164fe4b84e8ca96974749c9c1e0fc60	1	0	\\x000000010000000000800003f4957ebb66143c8e8135bbe6ca65d071593cf2c54df3292f093c80c86e30923e3327e314b2d82ded21c4e3a82d4abddb84d3d90e2f69406fbe4d5f07185613177dd5708761579a79e3f310fb36bc46018bafb36821a2284859d12bde8097c74d41dd9f1d4ebb596f2aa7ba01ef98a595c25e5c314375ed110397e4a440387dff010001	\\x3e1e0cf9282f36c8b9231746425b54a62f8bc6ee508600ca52c7e33c82824f1da509624f2ffe550c4ac82bfe4f3aa228735c85480c6c090bb6bfe06bd5dbaa09	1680602891000000	1681207691000000	1744279691000000	1838887691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xddff2d00e24404a145ba4a1e7200aa6e85b29d0c014f29f7e96b3b9129586c67e13a94bb64ea8bd86f40d287766803fd2508ec8402e8505bc99a1be7a4f0a0be	1	0	\\x000000010000000000800003ecfe371d067907d8cfa7732fcf15199b853dc314456f5982b242121c557394bf6686eb5b16e28af8db437075decc5f61ed5d00966dd5ddb3239542510664d94a3a2ae770bdc95b0df3a351e7be3b5b5bbeb4f75e95e3f6003d53aee0f98aac34bd04ef281be55cd58cdfc2b41eea144ae7e0326815833572b5f978c252d1ef1f010001	\\xdb0e46eb07bf0b1a93891d6cbeed2f8ce4e01239c999aad2f02c0c8eba190e3ad4aea594cd97232f5a646f35d5dddcc16d5517ae5d13464912eb5caac3e6d10b	1681207391000000	1681812191000000	1744884191000000	1839492191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe5ff22e8904969989c4bbafbe1210a8d3437d19e9a2b691a00f50fa22afbd778495408639390e9d7b5f69bf8025cd7746d6362c148db0ca6a4d8837bea583ed6	1	0	\\x000000010000000000800003e60553eab984644c521a0e21f8a35045eab3dfbe1b6bbd52adb4611a19493101d363257edeab3ef2d7c86f9a14a1f9fb6966021f750c149364f05fa7b4b25212ed91dbbe09879d63f54af5e512c2ae70feb34213702b8626e50bbbca0d9a64a03cca1bf0dacb418dc3b78bc947de87705f3abb52a9faae1b161e6f22562334b5010001	\\xd7ef13651b5819d11fa7f5ef68945bc4585c2bd1f2ab620e13281fab5718d435306452477883621d73018b8521eed64f683053774ee58e53c7be76a32f98cb04	1692088391000000	1692693191000000	1755765191000000	1850373191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xe62bb216d35d8f0206d37aaf87d2ee5ad114e6d69f2d60ba8b83b9cdbc892cd710a847b100f5bc982e7af41f5df50cfd1c5c6270b8b7940700ceae4136dfffed	1	0	\\x000000010000000000800003a58845a92351cc3004123cbc09c4eed68a70387638a81054ccdc2e8c054b5144be6e21e6c2985d2d42765b70203eae430700259192ad4974be790ce8015f40790ec86dc1a7d25d6130e7eb20206f5d419ed5a8b49852967aa9903c1dbb45b0c146e4fb61e8bf394ed40bf4a372f7252cb5899e2786567efd93142b5e9cc4b17d010001	\\xbdc9b4c1fd480a702ba36a6f9f00a6e39b9c632fcd2ef3dcfcc73533abc70d7dc91d924ace21898e2ebd867ad3773282832fc2157ec181e36bd9df3b9533a101	1666094891000000	1666699691000000	1729771691000000	1824379691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
414	\\xea97aafce26dbb55f1ef60be73ebf966f9563ecf3fbfa105dd1f90e379707fb9b269783abd5ebbdb24356d19957ac127eae379d4c506c4ec55491786fba62025	1	0	\\x0000000100000000008000039b28e17e2032959a65a786812b76cb148fa869c99c7b60debc92530fb3a73ca390add9a3a10d758f6aaabb13eec0c5bad6f1184f337fa7cfafec431a3979e5c7216a1cf188c0cd252e19175fbd5cd86fa62048858648de0fb9a07e8bcab4cc0dd3ac0e21114775c42cf5e8bbec059aa7cd9c49f93a2fb392fc7c7b75391dd5eb010001	\\x246152999f3a8b37014c807d163fac059e434b8e6e5cba1a1efa59392942b810c2bad099a153cabca0fc31e792dc14b04e681feba4b2f5dd61033428a4639806	1662467891000000	1663072691000000	1726144691000000	1820752691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xef9fec7102e807be20cce7ea357f1f0a18b2308b2bc014faf29d88d485d62299b3d5aba2596d5e0b9674552671357d95d4e86736aae0a58b1eb0b9d586be9f86	1	0	\\x000000010000000000800003ccd4258d2cb4ea5c19b68d8b3eb31a3ff04f576cb9504dc28d01c3c057429d69d9af432c61e13d2ac474a532f666de532b1a2540d6853f76ac1f93e8d3ea2c31486e63e01bb4fcf6153a2c409cdc330277906262a077dec621cab95d3cc0d6468304c1c222b002ea654d6d8dd6f35d6594eded1e21776966f62b62f837124503010001	\\xf23253d1a2c3bdbf8ec86b8139d7902736b51da8bc7808f2e57462ce27e7f31bf1cc6e573bb71c8951e302ac57c2177154350919639e80c1ddc4f3b0e50f5e02	1668512891000000	1669117691000000	1732189691000000	1826797691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xf47b8507ffab797e99e23202d34832de2c60ab2e350a477362e8a99ddd3da1f7f960bf158e420331c1492b32ce58db170ec7e44d094d84304b6cec1089e0b7e0	1	0	\\x000000010000000000800003b192c5f5799c53d846f017b439a6ab723e2a701103c804d8ad34b4b17b5a9d408fac254cfe585b58cf13229d186bf1e3463dbf3a07dc319eb6c85e05280b4a1e3458ca5352451ca2133fb34b765f2c4aff9911a4912951c1c8bbe51287aeb387dadf5dcf5404574716cc1012b5910b1eeb8379948521567ec7e9baad98aaabdf010001	\\xe8efdbbdeae9d9b6658f9023395ac3ec942789ec86acfddce6983fe27fd35e31efa2ddff0bfdb614759b6ef04d2ecd85fc4032c2fb077eebbe517fd281b7b401	1665490391000000	1666095191000000	1729167191000000	1823775191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
417	\\xf6dbc681ccb4cfbcdb289548b616e03574b9a89173c3fcaca55613b339d45efd38cd062606617ea42ec50fd3685bd5fc6fbfcbd335a5fabafa9eb9e2626a111d	1	0	\\x000000010000000000800003c6eb540dcc7bc3c796079403a16f3098c555a5d0f706bfcdf9461ffcf4fe131903fe56f9b52b13c9a9003fe41cf83a08964ebfc3eafb9feffedc77b2906d88ed6c23c5b8221e658a39a72b9b9b6673d251fe08affcc98163293803f14a3152314ea21b9b4371873aca5db182ccb3ab8e541c382aad75a1895aad36e208c8c5cf010001	\\x32f40cb70a9a7e32a7d762c10128896d9c91cf492a602591b8319a2a68d9c562d683a6e33f69202fe41f77a6f346695b52942fcafb473e511e6683f9bbe8360d	1663676891000000	1664281691000000	1727353691000000	1821961691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xf7dbcbce5c9357c7d9a325e3b443ef4f8b393e529533f838369992a1aafc73c9bd06f4305dd08bc152aff32fb9e04af2160a0cd8bbd9dc9c3446ff5dac60fc15	1	0	\\x000000010000000000800003b1022b9e1b649a38026f9cf7e6d1eca9aa5d0d6955e194ecde90270c33aec58d9483fae4da9aa803b7f16c98ee1378bf045f29c3741411105a8062c837fce66d64bdf31bf11bcd73b78c16bbb62e07936a0a0b081dd20c55ca2e55f2dc6289904901cfae62609cc0f605e64f5c5638609066d6d5ec662deb0e7ed279d2a3bac1010001	\\x758424068d2d435a981419bb2d74936f74acda41d8eb9fcfaaaa2b31a7c73f80366b53290549e2f88163d2159439dddc94e940451d45a236fe04795a9767a500	1673953391000000	1674558191000000	1737630191000000	1832238191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xf7935c548dc7a750a7907140a93745cb9189032f8611e2cc90c329065233d17ff6e0c6626d633ef2b8408cf1de3e801be2095e21d3d9749192abc41232f56fce	1	0	\\x000000010000000000800003cb48e4263c922d6f3b20d6dbbc3b969057fd3ae405fd008342489fdce774942b4562c84d773a86652567799260517f66d2ec8e244a87db132501a0604b9364d8dac1468cb93bec27d1d8b573a02ae5ab6b6eac3b7b80c344c565bce90bd3ba35c310c5288728ab1e636a28340feb8360f24b9c3f1abb77d18e2bf387b9f88e81010001	\\xa69601971a2f43b5d7d94d62e9869288058f5f06cd919913accf134c4e38550d70ac20b3e4dabe0b2ae18688a0d9d363c2cda09971567cc3f38bbabc10d2190b	1679998391000000	1680603191000000	1743675191000000	1838283191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
420	\\xfc232fd7d93b86f2b10ccb755846a0826e87aa07b3ba3320f38531a4b4d1a36647b5941d7ee28f92e702703bd7c8182917f7d5e8ea11d885b2bb77d749d13e1c	1	0	\\x000000010000000000800003a47518dd33c853bafa7dd73930d269e564583894e1293da3510e864f8a5781f77cd97cf86e83fd069a075b7f8eee98bcaabf248849f4eda30e71436c6797c4e572eaf8d4a419a6d5bf633c8ba8aefafc6552e042f5209ff53821698dcf4e79b7ec26f024c043c2519b64fe01b6f09a83aa2f0e435c7749543137c218055fc397010001	\\xa6ca1bef7919d51cef95ec6ed1c8d632c7f584215fe9e732a754f6a44afefac65962fbe7862b430ba93d9fd403267c44f725c503b15b551dc8ba21d2a22a9e07	1686647891000000	1687252691000000	1750324691000000	1844932691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
421	\\xfd53a73b1f6b166514f261ab1bf34205b3dd4eb09d298908c8a2533a2a7c17b95ac05a5248880beb320f750ff5cff924fc16854c899ca1eb46b0cddbf1241565	1	0	\\x000000010000000000800003ad80b109c083a34a46dca1adaef065d19772c60b97f2a6103c7e91a2d9e4b44ad9a67c7bc36bee0e24e99990d07877fbff108cb9ff15c09db7ca741e161bc98f1576299fca66e99c2a40c04f665e13fb75881d97bfcd56d409571cd0c494a0096b57c7d38a9ceb4227b4e2717778b4c0c52028c41fc5bf0530ba9769c744835d010001	\\x35743e7acff42cb33630acf99432e7022443d2b35cbd98ccaeb3de2324a3ae66fb9758b9ad421eaa44d86d6c8588be9220d4979adc287c01fad972ffec5cc305	1692088391000000	1692693191000000	1755765191000000	1850373191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfd43fcbc0213639eb1e428d908ef50109c07ac2ee2267250a6f3c1ead86eed409c6e6f1ea0098009133f4228cfa4b7863f5b17b4f4ea17a622e94d1365f5aa9e	1	0	\\x000000010000000000800003cb1d30775ce7f72d69ca245974f3c697bcea5d20ea0e2c430e297df9d0949dd5618b16d41b9c58baaef86dde1433ff978b91aa904f38b8439f10415c1c2555287af351df0a73ed89246aa689c10e78a67475ee711f146ee5d983404a26632d9eb5ef25eaa3e1d922ca6d829ca0e591436da1c23be608a69df6a076cf58ca2c25010001	\\xce9225808070c6bd82e41c982367d83bd44d2d2db6f25997fcd17434d7cdb68daaeea594fdae546141186d8f3d110cbd6bfd31920c11b136ea34d86eb0ecd10f	1689065891000000	1689670691000000	1752742691000000	1847350691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfdffcb590a5a97a7a9a91d2f0d0fbffbf70bd22e68d41400832b61ef48bb84de588f4127e3060b345f70894a22aa642c7c734b877f9bf1efb9d3b5f11817aa2e	1	0	\\x000000010000000000800003c5260414567cb921d5b43066f7e7543acd4235d353e185c343aaedf1f07c9158819e8d78f20c4a7330f00a977bba572b5b91018e855dd1e131c3a3cdfd018cb061bd7200c5f05a599e8aebac4ef621076373221bc67c85780f680b5137654ff70ec3b2b96e96ef3ab7ad53460e4cf4149917b8342fb615689e5d326a99e57d23010001	\\xb86d2aac9a390e37342105718aa8a9fdafa07bb4d843e738ad91c270645455984960a19c34b5e1560d91524ef9b094e07690074bf8556ca3f7b7081a2242020d	1676975891000000	1677580691000000	1740652691000000	1835260691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xfe4b93bfb297c92f113797fe1cfd5c3d1939dde60e5affef4b7d5dceb43b256e88a200cbe65ad377918cdeb8bcefd7f14a655441d3e3de65567a0346e9de9ae6	1	0	\\x000000010000000000800003bb22a13836abcdb6bd9718d4648c4359d962f523b11f890d873b48bf27f62499c7446befcb74dd14cf99dbcc9c73f5467fbd647e1b5bb0f22ddf3cf6993105e91f8451fa9dadcb87db2ef3b8d872d101046156639254a73d92f97f9d0589e5877ec5b1a6faffde708eecaaf38dc3b2f11cbeb8fa0c4d75b0d725f6129308a0db010001	\\x30c0a4fa984798e9285d59219b5f3d06fb092a7863b51d0d7556cb6c677d31188a3309bf444bcf205ffc3b977536fe7fa9ab9c28923dffc8de231c3212cb9a0d	1661258891000000	1661863691000000	1724935691000000	1819543691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660655307000000	1495836830	\\x2dabf8597c744b25c53956be0a58a67853eba9e3d03c7a473a594f609eaee337	1
1660655315000000	1495836830	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	2
1660655321000000	1495836830	\\x218ffcd2cc9b2ff4c35ce5eb12500cb091ad85e091ff642d13c0b94169d848f3	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1495836830	\\x2dabf8597c744b25c53956be0a58a67853eba9e3d03c7a473a594f609eaee337	1	4	0	1660654407000000	1660654409000000	1660655307000000	1660655307000000	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\x827f73b62cdbab20753edd20919233608f6e3d166b5dd5d1f63b7e9ea866fd183c6c4113576dd85e6f6b9a16d3852008d47007ad9981435d78d9375b35110ae2	\\xb1c3769807741baa5633b45396eadd4b3dc3f425ae23df88825775e2d97abfe290a4520e5ff36cf829b6ccba46e7685d7d8588d296457cba69c24e791feb6d01	\\x95b8b123aca8e5792f318eb8ad9827c0	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	1495836830	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	3	7	0	1660654415000000	1660654417000000	1660655315000000	1660655315000000	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\xe7c8a519ecdd88502897c79378308b3a8f2be183147fcc56fca83b622ce4f99ab34a46ea3b4b9b4b53892bf843a591fe57730c9cd883ee498da05376448e3508	\\xe3d5e9e0838608f21d5abca3fcda9d631d104ddb224d8035687f279da1dd5e1302f9634515f7b8efe78abee9b35a55f79cd67396053c43d236389d71c8656c07	\\x95b8b123aca8e5792f318eb8ad9827c0	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	1495836830	\\x218ffcd2cc9b2ff4c35ce5eb12500cb091ad85e091ff642d13c0b94169d848f3	6	3	0	1660654421000000	1660654423000000	1660655321000000	1660655321000000	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\x7d17d97ddede1070c10c51a33e9491e94302d74014620018f0f54bc991e493c0c33cf0d5c483444e6c5dc3c258246849d19cf15170774f361db56ae6fb724e97	\\x91824dc32aa51072b4a8f5a70c373ad43799aacce6e4d1b23850f5d30b98565e45536ca6eb43a4142febca57f7e6ff3ffe622e1b0b7c5e7ccbf3766f7a5e800b	\\x95b8b123aca8e5792f318eb8ad9827c0	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660655307000000	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\x2dabf8597c744b25c53956be0a58a67853eba9e3d03c7a473a594f609eaee337	1
1660655315000000	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	2
1660655321000000	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\x218ffcd2cc9b2ff4c35ce5eb12500cb091ad85e091ff642d13c0b94169d848f3	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x63b9d959e67e642c4aaf6a544319c636d53337e944cb7f3e4bc207453fa01e95	\\x7fa3cfa3804af9836d5a421e97b5daccfd0d0876a511d3df14881580f0b7c4259a8922fce44f7d7801fad4540645fe97c52bdb542971b9d4973655d8e83aa909	1675168991000000	1682426591000000	1684845791000000
2	\\xf04f93e0462e5561211c2965203e125a50b66de698d59336db015a6a3ed4e5c5	\\xba376e2ba581dc09b7c980aec16a28154d50cbcc56b4c019b2a74f8c11e90d641df2cc2e465837a18dab7333340c2197b611767ab3b11941a3f836634f7ef900	1682426291000000	1689683891000000	1692103091000000
3	\\x15f6a1c6e02150e2159af7c8b575dc669e2676345844fadc82640f8dcca448c9	\\x80701b6ca302d7dc016a070cde5f744138d0d7bb58c138f6ce5acc3c08300afc57d4ce4169b92a7fd2e1242a7fc8beef1971591d0286a9f9bb171445db64a806	1667911691000000	1675169291000000	1677588491000000
4	\\x3c26105d9cb3541f8134cf8450ed4f6aa02572aa33d0b14b705c8edcaced4cc4	\\x7fd2984ad70d97c2d7b3b5ebe8d9355f8c941be321fec6f3709995cc8adb49c9b2903325f07bf4cdeaa676bb55669cf5cd43392ebc8f04d8aeedf89073441609	1689683591000000	1696941191000000	1699360391000000
5	\\xfe2916caf605ab248662840c40d412468fc0c6bc087a1059df017a5df7e02c51	\\x3e222dc7d5df2768e32c4067e9dc2e1c6edaf955299c10474b6ecb24c9b0ca33b2c6ec9637e330e03c6bce795f3ce5141eafb254d98de97596fa0a693913430d	1660654391000000	1667911991000000	1670331191000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x79a05e509493c6353a105eab8c9b86cce896d074b7dc6a0f2d79010091fd28d73dc820ec03f2f241665e1ac01352d49639c5e916edf9aa6b2d67d2087b95b80a
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
1	223	\\x2dabf8597c744b25c53956be0a58a67853eba9e3d03c7a473a594f609eaee337	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003c6458d6197a3b350df6824bdb3b1d358fa3ead724322e1acf71f793d50140311cfbf8ec7baae06ed46dcdb93d71e4157784f0ef3e94625a578b44640885df88934fa3c8443fe12571a81c14e005bc5fb6907c54e7cfcbb4eb37e1601f7789743fa166e135fc829f3356155514a156fadbdcd9ffe6e7bd7ce0b5b0f6e559e03e	0	0
3	120	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000aa0501d918459312ed65167a58bed3da4933ce3dce5270be16f554dd17dcaf408ab7aba64d66a29fdb92cc21db5e4635c977f2377ae266e50d554a696ff3444f2a8c8591f651963c6c990b92cbfb06a4e72d06dbdf3338870d9e940a7cce0d3a4c4845a167c1d519bb6dd33edb45e29202266f955cbbd90317e6da98dd3a6655	0	1000000
6	160	\\x218ffcd2cc9b2ff4c35ce5eb12500cb091ad85e091ff642d13c0b94169d848f3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004fe6d6408cbb9584c96f73fa492e3e2ef719ae61f05d1d00859d061e511b33328a962711ebaf240b8bc8792028260edd48e031093cc9ad0e52e4eb46438c67eb503ad072e6ae94924a675f6114568451f3b8d52a7d81ff76730334043a227209d7f6264c6397b9ababcb6195603bd78e2dd157685ae09d7ec486d6d4e28ba0ee	0	1000000
\.


--
-- Data for Name: kyc_alerts; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.kyc_alerts (h_payto, trigger_type) FROM stdin;
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
1	\\xfd38aab6498ab407e72e315b66dafb54a004486b8c3eb26af14d44bc41ddd9b29af521a903d8769ea9fd4e78e92040fcdae20d59ab511f072042d4b801e8074a	\\x2dabf8597c744b25c53956be0a58a67853eba9e3d03c7a473a594f609eaee337	\\x3d3b878b79a3901bb9796cc9b8f22330940a27aa6193c4d7d7056514a7a3f9cdb5f4d1673793dd148f3c16a1e6489310f01cade362fb399c9463e4c8ca520c02	4	0	1
2	\\xff277d88cdce41d7419c86dd69fc4d59f458e6b63565ab491fb6496bcd34d5580c128bc9d43cd00c405e51ad3d60481e7374d0fac481ee7b3327973f55ea9e39	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	\\xcacd85b0eb5bd25e4daba952f6b018f0f976f76489d711f87195a487d4ed9f71c9e58d203f815a90225b001baf57fab0e008217599228a0737b132f6aa3c420f	3	0	0
3	\\xde766b9c8f6e3fbb76d52eca9d02c34c4ec1dedbd0497985a4a71f78cf1eda097557909a21419508b4e147dd3a34dbe6b5c809378426db30747d4f78ba2a4aed	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	\\xc6296b43ab58c3e766f7e594f0a98c92c96123f365c311f3eab90ba27533484fe96a4cfdcaad46054ec83e8ddab7f6960791cf59e3fddd86c3939a5d0ad2d70b	5	98000000	0
4	\\xe2aafbd5ed2506183218a98302c26081a18806ebc0599ecf30c2aa58fc60785677a7532167afbc6b72c18745f3f98bf4c6db14fce80bf996a0481ae35b51fc25	\\x218ffcd2cc9b2ff4c35ce5eb12500cb091ad85e091ff642d13c0b94169d848f3	\\x923253f551c645da1957adc48501d91ed5962765f51264a0f13f821b2456fe04ade38def6051e847e3e784d2c9b356a8311088831c0c78b606be3965336a6806	1	99000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xe402b9dbd7cd0dcfaf09ce6d41994998add133204cced874e802d59ca95fc11234107c6d89e45819f626de5a6fbe4a5f9eea48f5292e49dbfae28232c03baf00	112	\\x00000001000001009f21160704a4be0f62ed9010d5c4fc843fcb97c59025bc89ee88c8b7cf83ab42f5229f745d3a6b964d96d5bd0b4dbf13768b0fc1744e6feca2fe58b6ed21f2e4c09960f14c8798c191bef5b75fc0ce3b1dae8ddf5d6ef56191283d18a6f3236ffde4deb6332588a8db33d1cb8b562400cee3588cd788e43b86f2cdd3fd30e8b6	\\xc913f1ad0a0cdffb7e60b1d7ee4b35ba6efcc545857e6ae14bdf79f1ea990f66af88da20c0f30c3bcb6bc7c45b6ec10f0be2691ac8c87e57714bf586a6df8844	\\x000000010000000142c0101c3adfd1ec100479f39b84b76c33244432963c9472df360bee6de904caaa3aa409dfd3892bff81f34e9a350e84425c42e95aa8d1e1d49e30d69af302cf91236229a17d709830b22cf0c7f4d86dd07912db930c107bf117cac30bdc8beefb13dd32dd5251631058713c958d378d91edec35de9340c9ec0cbd1e54dadb71	\\x0000000100010000
2	1	1	\\x05a890a0c859cff76ec2649e57ed2dae935db8d3ec1fb9395c9f51a2ce9dd6240055de41649e8bff507cc33774d1bd9efc76313c021e6c55afa67123a678380f	406	\\x00000001000001008f78c8309667e5a9bcc6f4b4a6cfb38168e1cd584be94f0be14dca86ac25ad28bd126e62091ecedb80604e3378a7e97ae8a6d051b10b2e38664436ad906980ce64b9897bb8f94470d5df85ed6e830e91ce206804fb62d582718024a0c4ec279bd90b9df84f856e7050fff6df7e9bef0d4179dcb4b2f8a50564afda6ed08522d6	\\xa2d49455a81cca1292b911f7f57a967071e7ee3730fac7a78e5c797c489b9ccc64f35cfd93c0ce4e13748f494a086026c2f377e0f0546b09b634840e6c8715a3	\\x00000001000000013279295e5221fc44f08c4d8399a015e30dc471dfd5d8d2d22f8395e21f81319ea0447bc06ff2b5eb5631a5f4acf8de6064c561b6f25305945bb59b5e4e86e098020cda7160bea55e90d4bde9a674edbd0d513fa37af12bcaf0810845970d5dee3b2ed79980c14adb045c3b13ec67d36d89fe6437fd6c2ed39f59368f15a76e2b	\\x0000000100010000
3	1	2	\\x870b393c813bcf832d1b991a5890f7b825c1556477df2fe29164e679060b05ab2ddb906978a9ae72da225278d85ca1397b684c6abf2513542ae16da0a2e25205	391	\\x00000001000001003b41982cb0765a7ff5940f360e9b8a7f7a09da567510a1570d0f1c51bea59daf3479627cb668f9ac9924d3b62ec07b7d8c8e23717055a76de1b55c663598bc850ba5b0afdec07ea258733af6348fab8a24bb4e37daf2a5bfd35f566b4c087b6c23a190c654ce56140cd500869a1db155688976f37f21ea7169fb301cb3b815e9	\\x9cb76d8f39d12637947a86ca36c511521564c5e3db0ac08ac6cd8facda3c174dbab9899fbf29f899dbac82bf0413fd2f459e5123c33effe85c43aae5992c9aee	\\x000000010000000151a893b929147188e41bc6ca88adaf460492d82fd67dab5afa6af326481978b0845519272bb45f5b7bcc2c62485d11973476475ae35da2354bea23ef02e616f51b7b9b9f77bb6755457e575cae36911de0a5a442204cee369ff307fe80639137750fee745dda7337eea6e32d5243b868a6e2fed216410f98ce3161ac63340661	\\x0000000100010000
4	1	3	\\x546337f71299f4c0a527f5090a7ceb945d70b7375f1d906ac8a3c5edcdc06754115b7938c0e237851aeaa8aa046a2918389b45026a23b1039ed3353b8cf3380b	391	\\x00000001000001005807bf21e2f81bc1c97038653ae0e7c686819254386e378b99e6fb3bdcb599f19fa88af808592e41a39050c60e9cc793176e14e1fd1e84811175806028512df538b1a733d4e6b13065e310676f39f6eb827efe23222b2dc1217ec7866282bb4358488b581c401916448f4116b3eb4d417157c873f358d19491f6d6556fc34759	\\xc56d37e5b738effec9b15501eee8eb1f2b469de6db1e863520f94a94ada8c0364401b281361acc7461df98abe5df78e1ebfba1493164dcda1d00663bb99ce548	\\x00000001000000015b95645682fb3a88b97f6e0a9440e7535d3c2bc9395b41d94012675c239f611f6e6f3493620081c1b557463e5f6904fc6fdcb73cda05d48a6e1cf301440694c7c5a68f362a23455b40bf48ed9a26c03e569b77cfca41847f02773c643e45a1b28c5d4663adc913523aa49196957f560f7682d731649bd5cc6dd61965844d632a	\\x0000000100010000
5	1	4	\\xe06549802517c150824a459ccd88d8dc54bd3162bebc836c77bd6db553cb7fbba43559f947c6f9d565138c88f676fa0e55f66bae1f3aafe9a43065c62f4c7705	391	\\x00000001000001000c1b0627d9b52358f2c44892d197869d06e36b677234411e8a7c4fdd512912645617629defb4120817f3a7c7d15a50dade9d5de7d27b238b06e06b77a862483c6d08085ffabc15025ed3d09aa988dd59eead3967c7a2537e004fd9a892deb19292b63e70afa5c292da34715138d2e93fd92987b9f5ef18e1f93aae40803e248e	\\x2bb3b2d4703aa775ded5564f5a5600e5fe646bb80832a86a0b69d732141aae8c3cfcbebe9233acad502842d5d81cefec542b16c4854beb92b2aec5561e1bacf9	\\x0000000100000001a065897c8b1e948b011879b475465b6b3cbaf6e2a90e4101760a21f4299458dbf0eaacf949fb4580387a19fdee0c57681918717258350fa40548c652a3b5ef9b4c509ad0d1f2d1ddc49b199a9a0d0d3ed921e59daf105204d892f8a88d55a8e808c8ad24b49fa80f676380aa9d6e50165482122b01504acecf1682c16dae25ea	\\x0000000100010000
6	1	5	\\x4deb04c0646e0634f6b81d6f749ed9df3cb9437eb7d308c0a90182fc27ac685786e34dcd40f0809de79fbf3fc8f1faa953de61a325cec3cd952725ab864eb605	391	\\x00000001000001000767b701f55ea8774a2f35b2e4e7123fa9da6dd348539c1487541fdc0d6b92379dacb76b3ff65380015248350eab44075d8316b2845b8b847631729a12decf4feea17f544d22e8249a844114190fcda01f4c64a915da64af0f1881447a4e265c1490e17c235be792f97dd928515eddae8885926f822ed645a9ee9fa26f221fc2	\\x63a1c866978314fc26a001551a28c26470476ca18275cb675f6cfc8613c1a2629ad27bf5464a216a097cd0d4cd8baddeb7e4212f4c0aad7bd8b3ea74017b2396	\\x000000010000000164f6fc20843978c1113499f5b6abb68789ea8db3f3db0c841c5e4466c112b0dcb4dd9f056891100343f43fc48166186a38bfa4c384ad1dba39c8b3f678e3e38fbc5e3975490af4e62c45599159eb8c6c99c7d3e12250266929c27739c4e91d7c4f7ea0e9286e811d6d88cfee4f66b3d8f66ff5a21fb7d3cc6ded7f96efb94fa7	\\x0000000100010000
7	1	6	\\xe96a95a058052431b9da2250e403e25c343153743a5d5690b063cf366b146f2a26a3f834c27e22ac8966530c0f734dd256d359ed3652ca8fea6bb8858362cb09	391	\\x00000001000001002b0f1b6fa44c29da99e87ea089ef8f5a734659ba1a1a12e5cfbbf75bde460c5eee1ad30f0b8536cc5344f3764bbec066314296eebd15286699108c7c1cdd0987162b3764bfbabb0c158ed8fa6cc87fb6e6eea8e06532233f43211816f0d29340d6c5d2da45fb15758872c493d87c371612bb95747ccd162bb1e785112542a4a9	\\x9bc5189419284f77b866579ab4a17e0e75a819cecdbc3d59e4f4101587f4c213e42844b604d054ed9bbc8da9e69367655704764379c00a924d161aea729aada5	\\x00000001000000019c93ee8ce04d42a0d5a464a76af73e11aa962732946b57930e391dd800ee2b46cd18205021b35776350a8eedd6113943a995bcf74d482ac6f0c1ef2460158d63ee2bd21c84beefc3ca886400552d9d4702dc24c40c6771da967e23bba46db28753c82a29fab16d751d7c31e14e5b9d59583191b5539b8ce6e2218a4dc4f4d16d	\\x0000000100010000
8	1	7	\\x076297ebb1ccca68c832fc915f368524015c7613adb5d2642b8def4d9f201896dc1c949ad67e0e6b5b67050503816172566d1cdd0489eb8422a05fa1a33a4100	391	\\x0000000100000100161d419f0391db8f209883543baae9e3f756a2ab6b0001bc503e1f56dd0bb17402635a3207f46444b2c6966c2a95b6b580748cc2d00698e93d9a871451d9fc0758a9eb7a30b92d0109f4cdf4388d9ae97d8a97926f2eb97ab2f3bf6c7fa4a020ad1ab7d225d51778606b25f7a3a5bad55d2c0efe603f82bd4fd692f70b01fa18	\\xedd54d24b65accd89a886567bfe93148cac6fe872ec9995e62bd0503ec136d806e70d3eb23536fef3e605390b9aea89c52ab283eb231f19ff9349d19f4844f86	\\x0000000100000001805f88af3c9ce7c3b07394d6fa26a2052627af364f5776c175aea3617577d25f7be7be500376e8341cc5760f7ae78a8635253fe2cfe875fa5762d813fd940524fee0f34c561a8feb95a676aa5ad0dc3831852d6555581d13d7c7265dbf30411b21a2aa19be0b81e38b21933957a4e3e569a583db2645641326fde841acb5eba2	\\x0000000100010000
9	1	8	\\xe346ec14d6906ade87160de209b76e166df2e96f912355e61c0251fab18f42f66b9dbf0fb11a0386940aba5f96d768aa12dbccfc11559971843d4400de21dc09	391	\\x000000010000010096247f81763279c418e20fa47369631a7630bf09f9d3f66c3eb1eba87458fe04df84846584b03de17732a832107e7216e49300d38a35e3895f3cb69b6ed220e93c303e25881cbd1bf3de751b53c0bcc8ad115da3d3b1d78a38913c923fb3125c5951f5698e49999e6e674eb59e7ea75e798eb3f121857aebee6bbddcab837c7f	\\x15a2be866169c25307804235784aa0ccad226eab49bb33f3d18c520eac0e9a0273e1b92d2fb586d431467d2876cfffe917271a01eede4eb3ffe2b41bbdc8adb4	\\x00000001000000011ae1d824e6d2054760a65999ed3f465c85714f50382fab2995b053b23c5fe478ccef398c952b7a7786d5480403cb738ea2b1e036bb7b4b975ede525065b639e42947825ed95fa43c393bbb1e887f2eb7389dd19756cdf7f3b607491c398df17d952f25bdec80df76b458d6988bac015e61de876f1b04c2f64ae2d244464b9982	\\x0000000100010000
10	1	9	\\x8946eb7874e5dab552487147a8e429f38f45bddbb29c76152cebf13860caf26f8d0521a0b7a115f3b2080b7f456880c04486f923b45e848cc95e89ebc84f7106	391	\\x00000001000001001ffebada36862e306cd2d1b27e78aeaa7bf01d5103981ea80072664b76f3a09e61792974721ef5cea129e658c825c4aba751b4b757874c3b55ff149d6639e908fe165d71504de0de62183c0f8efdbbb3ad73a016e54e7a7b8cde44c675e45bcca46e5ee1829f5b06e74afdd56ef80b1a82344086835f02e92cef3004127371dd	\\x899af2cc7d8ce09afc1aab1ff41ef559b7bed92c4ac3d12ecaa3562c031c0c8d7277639b3a8d7a80dbeb99ea61f55c38b0138c1fac8c83a0de6181f176d7e654	\\x000000010000000102e969e416e4a58fdb09fb825d58960268196fd1bbe5b199d6ec32227b2de11831c9ad7df4d39bb2dbd4d10771f2dc6cef43ca05ca75cc09888f2ccf719618da660b733df545ec03d6618824a9fa71b7816a0fb884f838ceed8ad3c61aaa0467ca1a888667f418159fb499a8a0f08fe3b80cc9d016a83ed18b5ce20230796e20	\\x0000000100010000
11	1	10	\\x2ccd0820789a271aefc1d9477d7416fd5c34ccf87fafa77894017c7a291f677409c7313728ddba580ebad8ffb2bf1dab08fe4727f13fc7df5e6b500906037b0e	14	\\x00000001000001000f8fdeaf46832c90e2c4d7425ad25b7f1e4d43fd3a64da22c960bcbece5f57766aa6e6367fc532154ec167b000079b165b8f7925d1995a82f20f62afb1ea6d1eb720c1c902a2f4a0e7bea1b8070f98ba25c9e0e24af2512830a4145072bc93604b19913c1b92e04408531920090395352f993511cb575891e518cb86a5bd2604	\\xf2c7dc03fa7f0f2eb94454782c132a5f9a2a2bb1d7d379b963e5a84fdf50a962a4c8968a9f93a2fe11215be5bed89a918c575c90b4e0d4cddd8f12a2584c0a75	\\x00000001000000013629ae6ff09b00ead536f397b4b91a45ff76a1abf155483645599556c72a48934bff51bcfa57385741e618e6f6e360a2c8cf2b2294defd0f2ae2f23d44bbe0538b91654096551ff24b5517b358a0dc7729e02bc8126e8423b39771f3d8cd27bd6bf9978779ee128db4e0e464f406959a32e83a8b4740d449445682f7a9c43e10	\\x0000000100010000
12	1	11	\\x54de52db466fd102da328c2bdcc33674f7981ec13b1e338fedc6801ef26a80fd322f137f737d6b87e436113340855c81e0e327c5d781de5e2863ff9200dbe50d	14	\\x000000010000010062348923dd2cdde365ba670dd02741ed4dcd2528d3e33e178656bbadb3c3caf3d1f51dd8e817b0564d3a0b4131a56c4be903ab6628c103949e2ac2d3d2e6d2019f4df4b9b1118c990abb9e9146520ec58bbdef39da4b3e004c92f69af623bed013138693213f9b652457ecc9638fa1fecb511e3e88e4b1c78ed3b32504e3ae8e	\\xed1f64daa2abc8df6aa49f0b01ecb538886c165997cd4699cbc88aee71da8d0899f3447f01e6be26a56ea0a9dcc3ac7f65762b1ee010307f06c570e754471ef4	\\x00000001000000017250b78411968cd41eaf57e13b372fcbc98da5d2223bea8c9549140c91ffc03b6ef6a6df551ddd091bbe8d586cd4f775cc87197b478c37dde438cc34f53b3c037382be5ed8abf8d9a406dcb5b95e4caeb086e55265fc988aa23f19a93e194024a4e046003b6e14c3cab424212699476a510a6c3e88d075cab76ef618c95d6113	\\x0000000100010000
13	2	0	\\x81ab19396db2da61233aba52fbe4f874a6ae5edf4d4b1ec786f3cd6daba724f8f223687378356cee6be1bc932e2b3b813808f04608133d4adaecf5e56f49990d	112	\\x0000000100000100668c5832239c25eedc791578fc0ea60551519583670a8743a816e901b4a9ef45209b7e1c1ac9f30f5d649a4d00083561bce713f09f88bc5b9d24da314ee64aa6f33cbe4abeb1df02918b6f49109eb9e4d7704913edb35030e82bc2b3b85523c0f15954896dbc50697bff8c51aa4c6dad55d89927a79d0db25fe62f62a5470e0e	\\xa008a15988ff96016c0d3a7dfe73e8e4c516d0de82e04e211f7c57874b65ecafa12c950629c59cdcfa227c3d99cfa456bec55ebec2cc7a623ba23d46b46d833c	\\x00000001000000012a4f395a5b889130cd72797d07b9cb75fa0707499b14d65046c5ad73ceebad84b55df300a77fa924ed79c1c50c5dfafc98d57b0a4cf8c67a4319b29d500d20f1d18392e09b6d63e3e9de694b75a0399cf0b852a6ecd6bf1aa129da98f55b885b2ddb06a3d801513b58cfbd264156f11d4b758a961c4e56858b9821e4a65bb879	\\x0000000100010000
14	2	1	\\xe7ce0c17ffef35332146878ccd724600c9e5a0d5135eaa0aa96e646462ef6056905471fd8c4718653a96e9e86e87d2eda66949083c667075b1d362def7829f03	391	\\x00000001000001007fcce77423126b57edc9e7578919f8c90f039de49ca8476123d65e8d950f224283391b533bf246544eb121606ab99ecec3436aa96c44f5fad04be88404cef191bd4d7daab296f38e12d1985e393c1f447cfce9a4571285861e175c30880346b25f9816cceb6129168df5e3321dfd7a72c713710423b682bb00da4298b6f767af	\\x9be954ca3289f5229884552d4a6a5d8e967573e269b5dc280467c78e27f93a22c0f47157013fea261d3480c206782b8c9d772a1aacf25be01c3a1dc4b9689cc3	\\x000000010000000162ded98509ce4d132bd4e96488efd32ab61ece54db06f6100ff5ac43abc672c681ad5aa419b63643f6c2a6b8932249dacc21e465a520dff11a7a0aac06144cf0105f66be0bdc933267ab0bc028a4bd6e916d98cbf967cde09bcda97e585796a6fbf4e23afa7ead4812ed915fe8585534f449f3b9d19eb46472a73faf50aa5630	\\x0000000100010000
15	2	2	\\x14479540fef14966442ca55927be73f2f305a63c8a26de6821d7aa4748ad514d17e47f068c1f593db9a7aaa652669efa78428efa04cb8a7eb487bb6836aedd0e	391	\\x00000001000001001fbe32ca53b9e742d0627762d9695c3783befb979fc6417ee7654776b4865d122f128b89b913fde75f8f8bc0ea28fc2e36586cdec4214d08bd0f9772967aba59ccde037df496591247601fc33b7fe4767f689e80d533625c75a965d41c4df8418c9b727c36c439a63a7d01c33b105b030636f32386b1fdceeabcca998592a6c1	\\x7c7d1b22a650f8e8cd35093b102c90382cb98bb4768c646d41268797a3644be6f4310b95a3d606d3121bda21a4965417e08813d23f15396a20ef6285ee126605	\\x0000000100000001500c0c8f8338db875cf23b835e7c5b8c270cfb805854a2e22a82d0bc6d6beea1a22b14b5f14dff428edcf611ab93c1a521cfcec228cea22e975bc3a2260896ad3611f3c2fc031f6315f2d723fbf941789f87e6f607983e03509d0bb61ed0353635008d74695f2673929e6c2582dbaa1ffeed0ccff6f2110fb501dda50bf1475e	\\x0000000100010000
16	2	3	\\x6a01309fdb9ab7136684caac44944dcce8ee9415457a9797acbd9a4c9b34e209d4a088766179066138064d99d30b454fc228b878bdd149555afb48473769f305	391	\\x000000010000010047e57f50164582d58a93fb0fe15223261b988c07b996765eba7897188cc01d1f6d47f58798e97a41321c75a869d97c74066f408fbf264fa1622907ce1def95fa9fea917ed1943896dd15a6ae31d04557cbbaef238b5da52daead81ad9a0e7258ee84ba9d010a3fe558c9b26a5f3cfdd3da69784879529fb192176a6f6c484e96	\\x68d67aa7dde875ee525aa0d9df1341ab21f2c54d2ca6a80b3614a96d28e6b69c45955e77ee61b06400d797785016435df7efa220c998cb6fe1a18bf97dc929dc	\\x00000001000000016dc6d2b566002bb8aa68465ae2dd1223885fe9b6516ebb9be4e04788d8a3b1e04bc4e20b09ba112499fd9a1eb3d5cdbdd1ede8a4049d1d7378128e470dde6b68fbf7fc8f1d4e3e76542582e01e897be9871320642216edc8ed96280e8f12351f291e6db4ea0a8ea298dfd14dab2da7fda277487f56f48cb9a0bf1e5ac021f098	\\x0000000100010000
17	2	4	\\x00ba8e2159ecc341fc22b28c4361a66622d70ab4f43425c7b558c1f4ba56e37f21e3ad9fcac536af795c8851527d5a0e6e8b3703489195b3b1e0312b77f3270e	391	\\x00000001000001000d8d3ee2285f70da7875563346ecf7e1a8bf1db5d04601384b46a904152a1c354cfb9c3b7919a8c7f7441e2319b65abce58301f75371ea3cbd4d7df69ae0b075b4b5acd251050333a17a5aab9e6ef697bf867852aa78a444d7ef2aeb0423858669304489db8167ea153d4f685243743066859582e82c1aadd267db383312143d	\\x270410312ca48169e52feda95802f0b30b5447e61d32809adb98d00ed423872aa458c8894762f0e479e16b57b4122a9e171c08b565197a3b7e7a5b8a7031a5e8	\\x0000000100000001b599d8918c69a5a84e8c4c0c4b9ab5205acdeae43fee0edd5b079ef5e993d2c1ed340b3f3a45778a8e379f09327b01fcf4d65efe381d0673199283b34e2849e530b9d11dd653c18df186b22eb4cbc52dafd45e878c51d7264d12ea123aed58e78ca956d1706c6bb548f5d3e07ae410b6ee07dee1d98ad890110e50d5de14839c	\\x0000000100010000
18	2	5	\\x463419cc9edafab33850d0f50e2aeac8a456970ff290b3c396a5e3bd290e4c68d67f40bbd58a7fc5d087389060fa285d3a1dcb88db6bcd5b5eef2dbe4d0baa0e	391	\\x00000001000001002a078c896f1cf9fb56b37d2c335e3a4451a82ab32e8ac5e7dc053d2c77a811e3a5aa0786869c3d87cd201dde21550f93891285eac6d7afc35a656aca29741290dc563a62cf033517067458bc06ba2f03567f2d41be7fdb1db59a1009601970c7580bc1e0f85e2686cd5b7f3dd5eda145248c2333853b6e6f19cb821fa977e2a3	\\x9b8b226d341111743cb6e1bc6009c7f0a2b240ed9ba559ca0a90f811a6a9036bca04f5b21e5b6f6de5c00ef85ad7c58b9b600dadd404b1b8599b399730ac0379	\\x00000001000000015348fe92be4b88f847caf2d1fa957dbc9e6f7ad607936119889ba99ffe442ff469ff28b2bdd0802e694e8f6a7127447f5cf407564bd77c1bd2a434d34d54a07d1e0f596f2777330f2e458a8a68b201f5439ca8a9007dc525f94ee4c1db853a9ca79274f547daad4ad1a73eecb525ea53e475bc2f6d963d21e90d86a297c2c279	\\x0000000100010000
19	2	6	\\x04448242b4fb1de22532de02bd5225c6a75f54e2c837dcda0238340d948f17451610c521f2cc65c41696bc0abba8a832bcf6ca02cfe8e47c29357f36a205e101	391	\\x0000000100000100558299930ac29eaaf8f74240197116692de7ded79d0fc98e2b77c591edcb0eb88209bb08582a4bc98b05db8056b948dc12a8413faf0f6428e639e53b766fe2033718c3da0a0a39b19e0c1e04a87f6e1369022c593025ad62e72af0f9c1405cc9e6203da72758467d2c462998d9181d29b917ef44bf6cf1db555c03917153ad2d	\\xa29c756392c8e6b6cccae25b4ff36354cd47a216878318955052f092f7143a985a798424b8f5040f66b6ee6670be8be8e6cb7c3f096f3b2c6a4da6aa9603842e	\\x000000010000000181d2f16a2c10de8452c52afcbd71d6fb72b76c4c2cf222353f3ab55efeafe8a0410cfea4f2b608b65902530cdb734c4d97149987b6bf379d26c5854afc467a3c94dbcc595365fd892ebfdf7307b37ad3cf9ed316befec4bc6bb6216d7d0a1db0236e53ff7533081379fcddb9b6e9c9b5c6b879cbcb387b9a1af1bb87f4f84d7b	\\x0000000100010000
20	2	7	\\x768819b14421ad3875af37b568806e41df13a50aa1667426ac776225054fd9c2c7ca77a6f7a345d7e0b950549a0d2d0e5ff92c013c1cd3338f75fe931c500003	391	\\x00000001000001001ecb7a80d6291497fae169818604f513dfc555e52870371c9d6cf4121b477cd6c3e57fc3c29011aee8ade17bd797cf7cc4d3e109af506074bd184c9239778a90b2d82efdc3075da9f1323be99f63a6932ff9bde4e673b09b5273426fd58389b962a2bdc6a29717281640f7a6108b0faf1e755eff1bf21eb977ba87377a2de237	\\x703eedaa1fbc74633222bb74b69aa5c6f440abb376e59028b141b372f61394e0c1ac831a179221ca8e3d9ff16ebec041c14125a7a2bcaa9ce6cf3771aeb08a97	\\x000000010000000180697e031849d32d6efcc5ffb32df36f7d802e53c093e7df11f46889c66b53aa245a9d4e8456d8d43941b90ff7f822bdba0cb06700a8ec77d9a13c94209d393feed4a4e77b48abe2dd364e17d546f27c2f432ad9b02d4c9d6e933246a1ceada65cf250c94a0af7b4441f6b73bae136ebae4f9005b8b39fff8f94603e6cfa500f	\\x0000000100010000
21	2	8	\\x8437b151e177d0e8b8799b3c435ed21417b319c37a956b522e8ce091d5c039b040a85cfb155113f9e0e40644191bad11fac9f78eb2fc0d4c022a9a8a82d32d07	391	\\x00000001000001006ead956a64416fa90aec894779df27dd7a597e1041b683d4c3b891ee2f756693d87fa7e2f1d6625edc39670a7112b6daec6f56b453e6424d35fd64fda383b481807bafd45cd2c4cabd15209103d84cb21552e0aecbbf3459964b8007dd5aee624ac6506302d6d37f4e2a7e35a8567a4f755c0e357a21d77710e5c66f60c35e7b	\\x02515fa637f7c9d0bec291db5e2c424299e1a83370b5a176077b0e59d3fc1bc66eaf70215ce0436af4e3d117665e509f267f96786e188c03d46976f67ee2a242	\\x000000010000000121d2bf9cefcaa4d282c77c9c50e73069376f5b289c2ca19ef76b96fb65a61dc90d072b7f639f637bf4f917fa107f557eb43cabb3eebe7130bf49a3a0b04dbb60220fc4f89beab82534a1d242755827f4e42d3a511caae108320291f4b7dc57643c4751a5630772c1080a0d246c6d96062efd02982125a49befe8b9a714401a1a	\\x0000000100010000
22	2	9	\\x6c53fc358752db9dec6bbe1ab3eb37cf6d77adbbd6664598b106e0c8947a97b33f1d777cc01bafab3bc8d8aaf980ed23325edb4e127c446a776b2f86a6ecc307	14	\\x000000010000010084dbb56f101ced499a749b32bf996f32de828f3b1204fa1635bf92635cd90b4b6d2fc3d7cd9fe0f29cee56dd72da93c3c3967fc1421dab6d2dcaa6b508fe75263620018905919533c67c3f73275b0c908c16dca022417ab384193ab0a0792b4d0de5c667d58ccb1c762c0e8f9dc04f14173bfd89b408da7cb87c681dd3e86408	\\xd4caeae3d6e4fce3a54b77470de8c8495c8d104c8c0fadc12437e51d2e6d789952640dd27478260fd778f1905e852602716be14432d9c35492c6c1ce176044e9	\\x00000001000000016a505b01358ed4e3c0a3f65719bc9bcbb2d1b7f58bf0e6f700b9b57375e0f87e5f0e5fce77cad70a6b31d298f09d311f6b1fa1cf3427ed8caa7562ad2903629a4e5d5f0047dd3c91711aefb5b2e3435770b4d27afa9b07654c1b15af54a2cb1c048da9e361d68a2739465c003b0c2f1998a6ce5498a1d26ade453027643a29d8	\\x0000000100010000
23	2	10	\\x19243634389b3c02a007bb673d4fec863952cb891a3131b63bf67c87e360bf70d871c698b5725abc91b4d098490485b73c2df76112f436efa4edbef96b952409	14	\\x0000000100000100069cf583a4aefe4ab60c4aff78a98624ee1a21af90f62192de7af7b60f098c92439a00a99a09bacaa93fcfc55e0001b8e3fbb96e9e412948145d4481387720757dc42a25343e85cee9483981b280b19502851621ab5552ad7640b56cce5a52ff766a916d219b12c13c72234854a636570cb398191df58e5cfadde8ebcdebdcc3	\\xf80a1da16cd863ec881bd62b89965a4a85438ebe9ba52afac69efa274edd46249f96b9e77a14ea18d15bc4a3a9befc5021eb9e9fe559db16119650a382cf2380	\\x0000000100000001653d16784680a15974aa76b76231d8355fd45ecc03de56ca4c72210f2de4f825cfdb5a1969ae5d4c00bcf13036b09ab35861364d1e082c0488dfd998c6237a0e358e3fc940f41677d0deeef216a6e89cda997cfceaef761850840dc186235387ca338fa544dce45809748198112be9f0a80dbb5a0420a27d546ce5ad69310b7a	\\x0000000100010000
24	2	11	\\xd8b7b10328fc0edf2f9bd9b7ef58780312db24cdde735b540d26ed406dc6a8a5f43527d413f5a6cb090311e1e69c020e09149ff642f029c2927067531c14ea0a	14	\\x00000001000001003f2d62314c593e6473de76c6c1ded0c646e722c0836c8b9b3b1eef54ffa0d723554695f6d13c59a9f9d823b27ecf8fcb8b91adb9685d86e09aa3b101c25d9d07ccbab27e0215cb1f49d8af80c7d8f4c433af02c2feb49549b2e46ce3a61618642b193519560e91c011ba6e26ed29af960d170abfe8d86cfd187ed5890f1daa27	\\xf0c16456ee503411833f5fd1dd0e2ba9d552f2cf5d5387d0de765154d6cb0281e9c7bdd484193df15c38acf00d239d458b079cf45591d1a1e78e4f9dce69a865	\\x00000001000000016574fb78754c27300b55e75993c286712fd59c17f30331a048f27dadf5a0667ac676a2a12f27f0cd9c2fc5a27fa753d243219fe4de845f711f240f0ade6e52ec9c18b55e6f3c613c29d0e4493262dff9a296fcc33811510dd24130702b9f100a4288d4af51903e1fa7d3b374f6abb8c9f75b66e2a311eeea8e7d771d02b4eeaf	\\x0000000100010000
25	3	0	\\x5ea9e4003e273e13939a52dd4d7f86443ba1f83668a6c859b2036b411d868fd3378c78217d799d257b6b08d854b4a4356b71a6492abe196b7e6d3170ea62b202	160	\\x00000001000001000305dc42345cfedf740cd932e1a476152480903ccefcccf71424b0c5d14a964cf1bf770dc1388c4551c68d7c2386d8b6b0a99167716f7b0225fc03346842edf3ed70991933d5debcc78ff71e7621de8a3cc590df2a182b5dcc74ae24a05c2a018463d5434c9c0c6a3f30133b49e7abcc041d211888d06cae34f4fb0cc6a03b87	\\xd890e8df8ccd6b5da3e811a07f0ae5e374aa544f2f6a81882c1421e710f6f113321dbcec4b182a3f4f69285282eb6e4a14d5412d466464a40866f0f00b3de052	\\x00000001000000014d9e418249622f394dded3faa04656d77f82c1a90390cf1b67634310cacc0face343d663ef28d39655dec9c599483135bffe6629ef33f92868b34b2271688429bc4ccfd516f1d3b4f741a92f9d4a92d6543d9bda2d94adf844b57b72e005a50cf129cbbbb7492d5da8e8ce86dba852984ea59ee1af523276d8a3e0769dd44f58	\\x0000000100010000
26	3	1	\\x7a7df3412fb0df007bb0f997fe9769131ffd5bda6c34fe5926236fd8187760ba2a730d4806b6dd4971a1ee09552085c11227ba0f349eb796dfb8ce2507b38908	391	\\x00000001000001006211507db9e1a2ee33ba68fb45a0791431123fb743a01ed3e56707a9649c191e2902406afb0e0c82af1210dc1b03794d3e6cc27c1f034d355178e9125ecfe2b8204e203a951f275b44825383d9197d750aedcd43bfa2984ae13bd97426a7e5f7f896d00a332440082b652b2cde24131002b40134a52efecd9542ddd1d874b718	\\x0fd420243ef39a6febfa4b53d73607feb3ab8e3d6f368904ba44e03e11c47b419b9cfe09fc3e0d7a15d831bbb2766ed84f1fc88ee434e1835278f34a7a4798ec	\\x00000001000000016fd85012522493dc9e1068fe3e527bdfa721b23e71fd2b605442c0aaa680c9fb763ee18393f9e993600d615ca353fd3323ecbb236651587a824802ec185d2ada8c37e96bebb82c006a43471aa573c6d62a2215a9ed87e2a0c5951cdc99256c17ad49aae9d0946f854be4516442906aec2bc73afebf2399071aaf03ef981a0ae4	\\x0000000100010000
27	3	2	\\x78cb32bccd131012864b0c75349091c6a0f8c41504054cd2a9ae76f3cf7df6a617710bab0efe8a0edc38277af3dc46bb8f8ecc6d217c4b75a2f3bfe6f94d8d0d	391	\\x00000001000001001b6ae710ec680148fcbe1010929c9f4b1592b037f91d248a9523b5492732b17afac06d2711ce2ef0881b50d639df01f54f344e64150e1cb60be86e60844a06efcd0a51fe85618411c7bbeaa709e7547114493bfd3be434a497343ad10d062652c16f79f4e007fa56359707c0511cf4de873498ec231f104ca253d69db6f52b00	\\x75fb5fb77e3669350d886612660f53fd9039845ba6616e880cebf8e6645e2f027fff5a3c3708dad96b043ab52a664004c38a944fdd6c83452d877a045a70fcec	\\x0000000100000001111000a69c7c99174735240126f0cd54394d8d03e0ef90bf360c74b6c37b036e150db088920c91a904228bf42b5452f4ecd8090c088d597493e48ac6c77ba7dc96a290e58b48981cb41646a9486c09c10494799469461c2844f8122c00bcce4382989723695bf74f81ef5513cb7c0b939cd4fdd338fdb6d1820d40afcf1276ae	\\x0000000100010000
28	3	3	\\x240169afc27fe77dd648c1497ee6ee74cdb8ef8ada8adbb7333c874e03f18e4a54121a5508b6e424097b7eaa3f1dcdc86300725d013f5e17d9d2aab55bc3e900	391	\\x00000001000001005a403731851c44b4c326f28cbd06cca744a2675a69e50ce825a0cc682322640905e1575da4c95ac7945396b0d2878cd32d2ca5ae5569bce4c6cf8ca4bf5b110c8cbbad2c95b46c3661177a087501ea2085ea80feeb11d357097b4260e80f933de139314b68e89f649d00bcc0974c5dc316fed9ded2ba7b91b948053237ef55c5	\\x4e33e8905b22b35d4d955ef6a75ea66276a2d7bfdd40c97b6f9b0fabfe8ad116aaa4aabe902b4ca854f03c906f4b01bcc4af90bc35c7ffdc45d5782809f82635	\\x00000001000000019ba7999398dcc90f7bb7885f46ba1c32c6929c5de3bb57239e3928971d9b8a72a741f02e47f658b39080bf38eeba6634aaf2f1105ad83853ad84faf58153e342b40b7da500917a0b37d6c8d10e16da5e032909081d82ad2f8fef1eb4449b0c28e490e9104cabea2abe85e6f4274ed898c7e12ff1fd186f2793c7a5db2c9c40ba	\\x0000000100010000
29	3	4	\\xa6462d7b53c4ca3de5575a715dbd72e3fb1c6bffd2816cbde673d8196759824f2831539d2a0a90841436f840684d192cea62a638e6c33b869d814d91dc12b806	391	\\x00000001000001000d80872923e42fc905511cad24d9e45555dacbca8255e0804024eeb0608bee43324ff7b0d7f6a1c7277596c6f86f294198c9b1dc2c58638d64ce3c0b0593e2a313c54a99809de5626abef11797cf1caad53f732bd344ebf3114d937a009b0aa724c6e8e2352a10a2da4a1d6f196fea48fd2b36771dc4855fc1447fb88b08b3c8	\\xced8af3270f8b2e5aa75b0a797b6b86e4ebb4fb227830eb8c7560130f88fffd4b7632357eb957f8972b669278a1772f603ecb9d1f73baa712d94094d9863334c	\\x000000010000000155184754bfc803880c82fc53ec01cb7f1d53dce679f0e97bd9cc84035d238aba3077247945a1dabe63189abbfd7307f2c072fbd2a1ba406f6264d49776f31072eed065d8c6a0d1a7765971226c4abfd8e39d3084e795c63123845ded78b9431821717594447cddad471b6a1002e281ca986e945c4d6b0bbea0424828bd6da024	\\x0000000100010000
30	3	5	\\x867683ca1243bfebdd7568b093c5fad8cac552f5d6adeac6ad814b7313eb884714a90399b828871d07d1922a4683d0c253ad2d2221be625ac88af7474890be05	391	\\x0000000100000100074a445a86253315949759403103a2e424e34a2c345aa6d72e3c9d2cb0a59db55c30a243cea7bdf6a319a547c68360d8b9dc954360fb24163e8e6fe6a161218039034e0bf0c8df6c0caf73ab8722176bd47900d8f11c879a213d1797dbe8ca1b99c5cb8d3349e8cba294dc59124981ce62e5826d1e6095c5e6ffbed37a2e5b02	\\x48ef2bea5e16882690707275bb58acc8bc5d85aeeef1cd6f57721bc168f4df5f0cae4d10963792373fb805c7872dbcc833b7cd9d0ab8c842f6fad703880b5c51	\\x00000001000000017fccba3fd8fb7fc5182965d1ba6961e083b6de6ae0e1763942c3b193bbbc96221d2679f79253090a634848412f73aaadb124245ff5e77bbea6ee790b2ee8b1f85d8f11c7d11fbe8176f4d7812f029b64b200b5b02f8023955e4d0c0022f9ffe187c5b721669378ede659e7fef3eba2ada7a73c23ce376a46b45bd7f9afba120d	\\x0000000100010000
31	3	6	\\x9a9f05db53cff3407f19489d590d6fd3a12ed1a32c2177e061b001d48dff275f8bcaf730a28807f81b5440397401739a0e33197871f3139bf8ba2d6b15e2f80a	391	\\x00000001000001008ee9575fca7cd44d37ccdbcdb999afcf433ebdda5759c4ff003a4d86c6ca287dc29c9b2c1d80cc43d5332b1db936f30362437a25c39882712b7c3fa3e5c66f597a8d4f21c092d797f8aba17d1b80c281f2142e2d377a829be08772f8b632c12b1aabbf89bf12ebd842a67cf3ce50534ce8e1e8025342f38c007cb96734985a73	\\x72cea15484b9d830ae02bb36358cdedff8f21d7232e3fb0104563d2558988829e816439e5c3e121e0ae53c418ad4de381f11266e41fd70403f6bacf279215e04	\\x000000010000000134a21d56e893df01f6c343e957e748ea4453c4e002ce23eedc3476a4823190bf794721bb17431d2127db685ca49ea9fd0b1267006fab9fa73744e01bb1b5f8e2813bb0461bad8d732325dbd16ac84cdc13393e5e03f108983b26c8098726d7a9a523e1a1f07665cc6b462ce8f448a967d88d97d0a0ae4e41e4a502167e94518c	\\x0000000100010000
32	3	7	\\x6586ea591805d2437bc1224a1a2c777755f9c83d58a9bc8622a5da927f7d5ed127f1691d2002c96477b8a3bd2b20fc47bf268791b4996daed2afc2e8eaa4890c	391	\\x0000000100000100668292a07637d9a24a35b7cea13dbcdf32055146972accb7bd0633dc2aeb37594f3b06517b26fb138abf74a05d430f1dd75105bdc7ff8cf960cbb9edff6cfe9414f1016af9eda297b65da1fd2608c7006bd2052f7160f324c11811e1c21c001fadaac0bf74226fe06bbca42502ec5800853414a3000e1088f55575c4d6b10169	\\x875b651644e461c7404c8a6f2456079d8341ff5bb8e0a10ddc2e96439e6935b8ab4058574284c62815b00008ffe6da8bc6c75de769077e667c69ccdcb784dcde	\\x00000001000000016fb4c8f4683d57d6c854fd788b05a386b6d2d46720cf317732b55c327fa2ba879e6240e4092c04a4fd25056c153eb80531266f342d382da917b1128d491fbeff83cf42f73b9f19e6ce67cc216c40243517154b7a2331f9850662f3d77e9b4023aedd0ffd6521b60bc7fb5e814291f6e1d3f8e4f15de3f491c0c1e21818b45e77	\\x0000000100010000
33	3	8	\\x5e27cb67baa325e53bb918a43f98db11d52505bb531cca691b34d8dd1a80d8a386524edd2e940f980a3771fc3b0ac58e9a0b4a29d9a9cc290bd106603d3c8b02	391	\\x0000000100000100307cdbc1e5f3a9d6d8073dc87dd147cd0acac4b4698ba8c8a6c94706c86c5074329fed0992cbb42664eb9fadb7f562c3835bacfabf78b162d7e2e3f2b864a6b048f6d519df24924de581cd9d1b9b9b5778c33a6d4f921bf66488e58bd315088560cee24ae785dcd3e3ebc2f72f911b9211a1540a251ce6bdf110d6a97b286268	\\x983772a70d47067263f891672ca035fa9820b2b4064fed3a39ad53c12dfd6df399e9d82db0cc238c966f37f997c72f350bd5daeae173e18feb9865b3c715d304	\\x000000010000000178b14792a55bd6949020955a629553118836954053ccbff2977aebcd584d4a3fa455a85d43cbe806809e7f4b137ead76efe8e0b3a7e835106c3a25e8f995c0e17fa8165c557bb0892ee795196bffed7a89dbcf38383a06746f9c8802f361c784fb382f73bf837c862b20840d008f61ef2f8bdb2cd340ab7ab7f3de8d9c5896fe	\\x0000000100010000
34	3	9	\\x784ec625a24e7438c46d22869c2cabcdc31eb2bc5d0fb3423e5c58ee04934b0e2edd1fe1cccba814f2a2573c8529b5b8df35ea5d2b1f4e0dd097b8520afd4d04	14	\\x000000010000010071572fc2e726d9295eb49137c82a13dc12c08cd038101122d8a14a3841bbce45768ae5526951afb3e4681f90a2e769df22ea3ae95cd95cf011fefc529d2c44e156741b053d29a598d05a0a89eccd1901739570cad71de53983eef7b85a2ecbec84353decc65714cf02a9976bc5e874a8ca8cd1439a3501a7c30683021e4f5d24	\\x831e29ce6e6c439d9db7c8807b14ed47af0bca0167fce972f968f1605760928eb0632215c941ce286aa10bfbb427e9ca13098b2e1839254583fe4aea3bf138e8	\\x0000000100000001b5ce7321288881f83c44bdf03da5207558f19f3d3bab0773105fc506ac5b89bfcbd249eb3cf40e95b004790253ed25401c1bab71f328c66d70dc313137aa20608e478c88eca100c4389b689a8dd8f7f7942f487980a28664bb500a9e583ad8db5fbd4b2077b9896e476fff66480d6591f07554de62687bcd5d9255adf0282344	\\x0000000100010000
35	3	10	\\x4c3fb70222cf876276727c87392a446453c3c9f04828aeeb1d268a18b8fa89dc57b4b29fb360f515d49ee0fbc413847f331a7db75138aeda4cf6788d3da1030b	14	\\x00000001000001004d8707fe7c683cf5f65dc197f94eb50f7a5451c1ce6b9954ab29e7aff87d70e364f09d19bd57c302bc7212b4f6142374d39c147a7233bf5f944e840967cca4a9c33fd7c1042b87895e6e66a689041c0c4f8d5dba1c8922a96b030b1c8cdd958bdcbcb66b699c907146353890982a0b3a3eafe634d88a2d35116bebaafdad5a32	\\x62935e4aba2d3dfca83219f69335b7078778cb5afc30f216f51e82a1f83a96e4d79a8bec8547c7c0ceb740f0707215b7655803f9d8de379f3fd695d1b77b8aa9	\\x00000001000000011a30ebc7ef9aad1ec274c5f9515108f4328c2af3cac8e0fa9f14abba22cc551753f5c15b4d8b0d6c75b338618e05d61685b0e90107b02f4027b2e9495c09188aeeace480f7ef86f90010eceb8d793d1761b656f1b04af16a4c8a654cb405d408dd4f74690815936cbbacba8bcc506506ae7678b465757f0f0f26bfb32b0b3999	\\x0000000100010000
36	3	11	\\xac6ee2a6b44be729ea8c6589f494b4481b808794e10eedf45da96c9cb8d57006f7153e9753c2b902dae0b80e746e3904dcb9ef7807ea9dacc76d7ebb09c67705	14	\\x00000001000001009389916f58dc99df4054cf6b6f31705d3d489de101203ace005283471e0a67a1e36d22eccb69d3a0c7c7c7b1e3066e51c69328bb7c5b2fa5f65d0ed509a7fdb1abc177660f1ab059b511cb2d3b55aaec04ea24fd02b7d1f4b23626e9ef6bd41a7d825edc70ca5d7e5547ea3c2e1709ea9938050f8d29eccb7a6110ba0b6ee177	\\x71add7f49d0696502622f7d9cfc74bbe629d680d313ccad659a323e597bddcd03d638ad6c3e87804fb031cf844b98b6c53ccb5b981fd580f1a1a0ed3ea0e5476	\\x00000001000000017bcb38bdce4bc257bd4f9ec68b2d71b2f0ad80ef6d403ce7d84784f42fd3c71a9e1f0014ece7babc967ec0097084baf95ca8bfbb3862c5771afa56c43075b98b648ae983e3a9cd1f5b6df942045d4761534869b48312c67f1633bebabe6274bcd94064d47d34c75091187c679b6a26d63aa99e0a25dfe1917fe26bc55ea7a1fb	\\x0000000100010000
37	4	0	\\x032fb82bb77bb08d9fc51d2797d1eb8631a1b2bb780263f662e080e411d62265b214f490c0e5ef48f09718ff6e4b7f9e3694669a6acf196efba03c4cb18bba09	406	\\x000000010000010064bec6514c8d6031a814ca278d7145118576d0686a421bf306a05bfe592268b3bf64b0939a93be491377291d03b89509147f1255c314a27295c260c61634d3b7a051857b73df656dfe545461035acb94ac7ed91e11b4db7fb86c8d81f0bdd6e7744da727884875ee5341deeb4cc206a42b931cb29557d8211d7134da587d79d2	\\x9277c58b3cc5b4b60399c7a61f96a6819c3364777d3f065103dc61135b567555c7268b5eeb3ac0ca44c21ef87086e18cf8003d688939610b311a6f48cdd3f481	\\x00000001000000010df4dfe8fa87d35debf87bfaf6ff1e0912e59a1da1b4e3487c97c1cc4e9a03c900bf1a5c75dd47767f517ba04a942c26309041630ade58fa71a52df6677650aef545bdb6ea7a29e138b3e0d9aa0f3e4b5aad5e9303a86a29bf4161e943d238a6ab786f322e6afb8c5fe3944d6b670ab2e37ed8ef747bd49f4314fdbd8ecc4e33	\\x0000000100010000
38	4	1	\\x37ffab308d3e706c6f829be7edb978003a1be3fb2a5d4b048a28af61f60cf6e525465f4183028e15f0f7f04b0c0788f290a77bb742bc6b33863f273a8c60f102	391	\\x0000000100000100b28b2b89e303ff35ff497953722b8f220179e52f988071918024fccf2ed036637e5e731d3616a913f98e81bec3e4b0a8780ed0c7a022d8206805a02e6c407c5ef8e28d0b7f78079278a0a9fd11fa00af678ac769484048f90eb065c8ad37af115d18fb169645ac1bbe9d932105ebc4014944142d1d5179b674f0a235b38df359	\\x4b8a71ff6345bcdd6066462ebe30685589f5f406e86179b2962ef949134c5f3de9db8a9893d0432a394e0f2d7faf35f4cf61773b55af310080fa4cc0f07a6c60	\\x000000010000000115b274dee45d02b822ebb14222d6a71fba0a0483892d1cf34263cb60f14fb5a478fc9dc0b2ca163742021ac56f8eacb4d0660a0d2a7d31d78e88cdbd824a05c0fa9315e193f9c92684222cb2c7b7eaac102c8eba85ac3e1fd9c67128e87c90ffb514d0e0c383d4b9dec701ea09011736589a18f4a5bb5b58d262d8f1e5cd40e7	\\x0000000100010000
39	4	2	\\x9b78b9b333518ee5519e2f21aa890a90f5c4f23a7bcda4de2ed0d755dff449b194477fadb08c9ecb6b191a603284d31c1d581bbc8e8e31aa5d821894ad09260a	391	\\x00000001000001000c613c83b76fa8ba10665fd6b946342748aa9eb17831299bb4ae7acc8030b2719c96027eb165c18cd6fe5e0c25982ccb0a61ad4f734b9c9dca0702355cbdd13048d2855aeefb501cb81d62a24b148e3636d6177622cb2e03c92232365578c6a6a6a1bd9e8126f057d78dffb6069ea76d0f689dd1dd8afc4acca8c88e0fd6de70	\\xdc9415d838a7faa5b35092498c4c9a9a8dd87f3013457c3a4e198ac5f94fc0858c9e86ba0ab98ead81123360713d624a845bfe397acd7f08083e251b3b1dce8b	\\x0000000100000001af584fdee0a1d57f2f6331fac4bc92af3868c2c4bc80a2bb17f45c6da51cf636024b800031048b5df4dcf6ea36fe134c23fe0e27e9aae555a65294c8764c6fb0eb9d6ac46c352e27afa6f8551090c8eefaaf07d9273a6d8f76c80244e13da7a9873c7458fd9d5851214c03d894ef05d0d09e7b339d679262ddf2b7f32191691c	\\x0000000100010000
40	4	3	\\xaf3ab2f172b707aa5ea66741affcf8db3ec3ed55f810bbcf9fbf7b0f67a4cd5fe5d28bb28e92bed43326512fa4bc11992caab8ce8db0d522bf5597296368f006	391	\\x00000001000001008f82a5a1a97950b0a6f9b769ec618e935fa8421a8551c2be44312e863275905ed47f8e0f0c2856ac9453c694027dbbbc713e14cb91d883fa8438f28517d1fa25043621fa8e98271489147bcb960f91414a67bc82b85a409ef39274b38110db75cd6647ec01ff930e7fde444d3d4200995b0ccd9a6c76057d9e8e6a340f43f718	\\x7b34f2efcb43caa3a5dd8767265d23a4ffe975c2cdcf9c05b65c0354def640acbc100dc23ab2d52a1798670313619ac58f65d25d82546dd3e86ccd4dfe4b0d72	\\x0000000100000001a2b6d154f29a3a31d9982128b0b1a1ade994e26801cab262ec28d45c6f92c4c8eb8174848e83e876adef01438529094c2d1ef74ac01362d7d2adefe008d7a4f3a15cc2efeac3baed36cb91a59fc5981dbec361ade8fa0233c0592a1fac5d41cafc94f2f4aa5b6266fa8e6f54ca8cfd91d425f167868b61277f7def246aaa5cf4	\\x0000000100010000
41	4	4	\\xc580cb9f9cfcaed699bd84a6773be04957f933342b0a923185944b2cb84c3c8943460932234b4b8cd285af052e950fa86206dc83de1ff3c85070ed58ebc7200d	391	\\x00000001000001003817cceb6bb2d0f01c0e8f51a2d2969e521b6ded88683bc8806884a806bf78a5081b6791498c8827102d039b555f2f3df460fdd966ba89fdf03071c6317db1110cff34e844bfd3c9f71269f364e59288d4dd2f01fec118238da638fe32c5e912dfb88d3f699ab20b71953a2e6e25fd06bb116ed59a2180312a3209de54809da0	\\x6cf8951f7581c93f510c3bdb434589383efac3a853363f20f3cf3e256676b0d67b48b2dbaa2d428697aac1d6f095f9850e4e925d69b43eda9b14f39d78c4faea	\\x00000001000000019307ab036cd14c377298c0bfab6edbcad3533e249a0015a884b6a7583e3ec67e1ba54261c754650d2680913d4d9ce5685fa13512e1336ba8c253c7c165227dac7992c6854684605faac3eb96004a347eaeee0f518d73ba878a5df052b33e9c0f0531dd1f0375000249da381248a935bd370b865de9d2f120663dcec0267af923	\\x0000000100010000
42	4	5	\\xd3a533406d09d116cb420eddf6a0bb4a08fdbe1e7606b4f54ab722849b2eb9d7e38087a11ff551c03176cbcde7155785d43ca1129e6a83eaaca43dbab7d97709	391	\\x0000000100000100c7c244579c5bc7cea384ede40dbf2601b38fbc5dfae6e25ae74da6aa35448d80bcc546219bed6af3b739296f5eb485a84078316bccf0715b0a3e72955d56a25af16c555b3a396509ae8fcfec8c201628ed781648553408c8ae5c7e5d5a0bbbd2d36fb78c39ec0074008c03d3e6dbf234a9c2887568a212f7944b8e1cb6fc94	\\x23c65b63641b5b3d4aefea3ccece9270911c55e300123f3e1f2c35eb1916988ace490134a9f7cae8aa8d42ad862aef4a31fd4e2ebe1a3573bf392295d5bbe0bf	\\x00000001000000018400c158aba40cf19a9bf020499e72044a167ca19cfe7c59abc859d280d7922cb1559ce2a63e87691a0584409bb98e7ec332d2b2d84f39842334e4ccc369e996b14c32ad2c23b6059dd63269c29d7d6facbdd6c189497f60e0a8fd3a153439be5790780fe707dfb936dc9a88b81618b67814a99efbadf90ce1d2b9338bd87af6	\\x0000000100010000
43	4	6	\\x69c3c617fbbec3c6f658183d5aac19b803c08db9d6bd3f93b512c9875b752aa6ebebc1cf74455195095a81b970f6d43dea87d34f92a05fc3c956c1f4f1782902	391	\\x000000010000010041c0f850773daa09ced46fbe15b637852fabe3161b56502bfd1ce44e9fc16a651777a9b56e73eb1d7d4fd1720fbe64e21a07a91c6bc1a075f930acda62b770902e94eb56e576e27addb73b0ff2803f2075a1b88fca90f2c3bc47be7ac816a3d591812365035c69bd94097996172a14cbc05d8cacb3bc16ff9e0b099e16dcb55e	\\x80d3b170168783497c1a0aa8bf3269014ce7a4ec72213db3d8aa1eee868b91c60ee62cc7d831bcbdeaaa63731380a4be091dd51b2ca2b4b34cebecabd0e3c00c	\\x0000000100000001a2cf3b5c57466b6d20d92a2fdd557c79a95dcc50ff4677091cd922eff00bb4cf4fe88083fe7593356882f181edf8e57934087f47d087c4a1b2d8b1a6fb47d825b49a0f10f89973a10d2c4f970335375cfea751d59c8ffb07eca6a266f1e1c1e7a613cc89c3b57bbf56e81373a2ecaf3f9da4c75594ed9b73f60f3d2f536c3c44	\\x0000000100010000
44	4	7	\\x9a0394f7ee9ae72c62f772df215724130d4cab4e8226e39af1c6a95b1257916c09e45475053a01e44779ac2d6c3becf801906e48ccc161e5e5cbb51391f38006	391	\\x00000001000001001196dc07e8a389bfdf76ad2e2d87d16d01b4a7513278af6f9a637d5ec68638e468fd2109e0f644ff935506aa3421d3e56ecdd89c43aaa269838fd3b5ade3301dc9d90d3c979d19e87d88e12a7a1e12f71bce39c3a886b49b56656b7775479c47cc2f5bfa01be41e2b73c75a1f446b39129aa45963a16c054d14cac31039ff8cb	\\x747e30143d3b4df61068e9adf24278f82574b68a7d69f8cff8a98ff277412b32a4c2d9c86eeef36775fc1ace1611a0aaf0132d442735158e2bf58e9f5e7c022b	\\x0000000100000001849aed2f95a904d6685aab01e0840e470858d40e2c988cffa3b5ab889c556c2021a1c046f3484660f4f6886b8e46165a94b8a16ccdfc8816399f66d08d5f06edad438407561e139ae47b4938da7e232dddf4b485653d9e1789f8b27f216a02b719a9f0ea1cd8c39aa38889933126ba3a6710f793715179b200f1b7ef8564d0ca	\\x0000000100010000
45	4	8	\\x352525209ee4ff4d9c0af793ba3d9344eea0f0cd60e92dfdc1124ed65a8d2249badf11ee9991134023343b304ed515b73a9605bf04ab8c6b4088b0352a884c08	391	\\x000000010000010080ec20487887b006661cb62a2d7f9f3509958d68a735561829ddca4f7a90d234456bf64e97cdd0526f91754330466eefad2592d897fca2b56d6e1041893456c5a2f200537c7aeae78a51d08a95cc90891823aad76ab7285bd144eadca63edc8fa69a19dc064fae41c0e5ce77f71a831283e202bc6eaee0652d0c2ed6fc4d728a	\\x4bc210b44ec290462c2b79715dd16d0b1327db634fa0672213502ec8f44b06230f2ef78a4252d421a990adcafaec938790666732806682747480ae5bb68ba824	\\x0000000100000001a9b5b05f9db51b6d88f3623cf2e018c24fef6b43ae84fdca67604f41ba288f4a8ac452903b04b574516fd678191b40697075a5dfed7ff64eae1260c0b1f79e67f329e3385cb27dc1dcd42d41313a7f4bd600445196cd59e5fa79accd6d8a18cc73d3b3c66c51bc9dc0a1bb64e53d547d5189506ef0414eb56dcea5cce6cc5065	\\x0000000100010000
46	4	9	\\xe6d6cda7de0afb05552e4f6b4faf4d6d0e7a412ca56e5aea52d86b3da591eb6fdd09d6d501e1115e0d529acf40eeab19aabb1a8774ef83f961aef6eadeb6700d	14	\\x0000000100000100a4a5944d7510c770092effa948acb3e2adc6c2385cc366f077945358f17d97c5ba286cb62e2258d82cd9d65f20ea21942ed0ce2ad1d9fc4ea89f1967d243230c96a11988304c0530a09dcc28d9f6d56b4d9849220b0a83c1bbcf15b8a71e1ecd7a4155dec5b936cb2b0abb9b814190b176d6222b2a11882c4e4ea745c4df2cce	\\xfc4e145563ed3c5e4648add0f3c99b2532ef8859f97e73eac7297313e612af244f634e54667fa30cef28acd042f973a28fa86f6d4f9fd50ca100f1cf1a3fd46d	\\x000000010000000146689e64c6a5fef8764ba5fcf323dd17f047069cc4635b6df654416aefb54173f4be3a1651829b9116a23ff31ec3dc553f9288a1b83134cbc142ef019b87fab324f586f04ac7b41b09eb0713008ff4f10ea0fbe062be34f07200778ede41ff191d09063c30a5e12cb521cff983aa8baded3c57cf2dcd9013e21a24df3071bc3a	\\x0000000100010000
47	4	10	\\x50787da13def68f1f83996ac9c279322840c6be3d8b84050e1f454e28607dc82050279bda938cdd8379667ee09b9ab820e9c7b9dffa426ea9a67c1951f4a8102	14	\\x0000000100000100b71a07a4f6a9ee9fa6fdc52eb1698e3040d6dd79028b8870fb0f47592c7ba83218bdec2e3aa7777c6a33c1de24bb5dcad3ac3376858478713ea4a5322fd6a4404e91ee9dacdf81594c59b5be0ce0ee6c74e9fbb12eed89cf5cd83c694a72e619f950258038e4c18c6b08e0f5a55856233935f37c27bbc55aec0864cef3baad69	\\xe347093ff361fd9482f8d518050700215fdd2d5a6380628e42c9e3542b80e91f5d7ffe0075570fe1cb0ca7b5ddfdbdf74eac47bae950da72374387f920e6ffe2	\\x00000001000000018f53d05004b6871aa1cc65afc5043793c7f9032effe08cbda2bf35dbe5caceefccc00f1b7b94559cbc23cb1b6cf9c41434a255466468be7fcc57a871f30314b3230de0c7e55b56b13976e63be5c8ef26bfb8396407fa3fc3966032c9962f7032881530f47201efc004bbf8cfa46e50dfdfed5fede8646c58a3f450f2d6b8ae51	\\x0000000100010000
48	4	11	\\xebd6ca0842b84469b5a248a93f84bccff376e55e3d89083c5fef7d6321145280e27bbb727d6f4cc71a9ec2e77fa8c2903606aacbe7322c4718f345fd55b3250f	14	\\x0000000100000100b07cdf535ae68f86b00225e9ce0161e9292870c5102f6095e10155f70e2f912dc54a8e931a25005db7df99372e265f6fe346fd9c45810afd5ad96ae3f826a0171a9472e89755ef5435fcd7c0ad8ac8185546208d7a798e61ce537fbb33dd8d96c9583f9424bffcee4d183658c236eedd80246a9e7c57a1f95db4e6a1ec6520e1	\\x856859c405fdacaec101d710f285e9cc1b9641677f0db0620d97c5c41502956986a92eda4dd1811424048db7ec8f47edc1e3594bba893086685e30a9a4d2aa6a	\\x000000010000000137ce92594268e068836fcb90b5caf9f1ed09894c53afe63e2f76a14e775cdf4d1388e7d0b1c9140b61e63eacb2489a4329b6ce4b5c3f8134d23ac36f1c6dd0228e4b39ffb3fd8a6cbec29d0b7352542b0857c0b2d2551e1a488567bda16ebbfb7731bdfc274d67fdde011c5a4eba5be03edd272dc6b66f587722829fea456c15	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x88c8ae90ede4fb76af563c92954f80155b443adce2d11528b6e0b06387b0a87e	\\x6d3d1944399ed2bdc7f985b86052d37015bb73409efe9e7dcb7b99959cdbe5dece309f620f0fa4cf8c77e077b621509f063abb0c28c091a69fda5d051a3933b4
2	2	\\x6e08daaab3b3af6e38b20bc41e83c7c957a732a785179a0acfce76c7367cb607	\\x2f2ac1efd024804570cca5fe7392efb48407dcfb707b51f407b8871d4468df041e0e7c806c980bc09aa05567212d27a2aa04d25018565def68ff1e7c3753a67f
3	3	\\x5bd5e1bee16de0844b8219b35af03b80dc313600b817a647aa25611d0e77b76c	\\x0332acb1b1221f132ec859898c877132b7aeed1e1dc0db7d74692cbba43249352b1de01402ead8c66db7e372724ee50c48f6cf2785e64530e0503ce6fade7276
4	4	\\xec7f949a594a49bf11fd93c7a4dd00e4cc18ccf6e374bf3f0ee41e1d9d3acc19	\\x85f78f13a1dae065db1d608e8b5553fa3e1702add68881d766f5fddb1c27f354d10afd7aa5c850358d835e1048a9f9ffa64cc3f7fc8171cf83aef892f2ddb791
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	2	\\xaad0153dc4c5564044400275fdb0aac96057cead28d38bf64547513633a5bb399a675e4a5e264237a957ad4fea72d2bb76df84ba3890b7be73edd4794b8a9108	1	6	0
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, max_age, expiration_date, gc_date) FROM stdin;
1	\\xbd20ea3db4647abd447b0d7fb5bf8e0c95b325f95db574fee43b43bd04aa0db7	0	1000000	0	0	120	1663073604000000	1881406407000000
4	\\x1e8dcda2f5de0323c2fdcbfa5278e19a43f8c4d31090403a818572a2397e6240	0	1000000	0	0	120	1663073613000000	1881406415000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xbd20ea3db4647abd447b0d7fb5bf8e0c95b325f95db574fee43b43bd04aa0db7	1	10	0	\\x17e36f9902fada59cccccf07172878ae75a41daa3537c439b45b8c4ed129fb57	exchange-account-1	1660654404000000
4	\\x1e8dcda2f5de0323c2fdcbfa5278e19a43f8c4d31090403a818572a2397e6240	2	18	0	\\x7b4b32ec2d7f43a6b45ee01806ab31368d50c45c7c6d1783b0d7c0ac26368540	exchange-account-1	1660654413000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x5a7f7510bbe60fed8b164e472e56f7138f4393cd8b0314043957bba941c204adc3d2f22e320d07afcc9b86afcc7d5b83ac7b896a543d1ce0cce31dfa9b708029
1	\\x80f609ae4874d0d1d27d34722303eff525dd6b1667832027a8a4ddb441cbc401c48e91b7b7a313c58a253f6715bad938e0628c83f2d1810d08724cf28c492028
1	\\xe7bda2ec636b9f9f175caa40872fe13f69280877c67888c990c39340c9258b0f295ff6f41e5e29d1a39c799b7e222e1b7cfeb81c5044efb1483a14c5ae7c5f6c
1	\\xff5ffca6ec51dfe1a76075a3188510f720514b43b82e2510cf5626f999bfa0f146428aa965bad5edb0f7c471b7bb7827ca432af4718de6998ef0c7dc9783c89a
1	\\x323e5a1163f5210e82ddd56a30f34c56f4e133723c6938e7ce8b1136ee1faae41ae1e8b655e768e07ea10e6ebc56b4cf911956ed73d144b78463f05f7cd86d51
1	\\xa5012e03825ba9ddc9fed44e5dfca1f9c98d9a06b14641cb219b403306352dfe0c60b29b24ab55f0f103d7a795bddaef1900ea471244c4db410fe860ff2dd3cb
1	\\x67baee369bb152ab80b17ea8543be2e148e7d7da63c0b3e8c8a0907d1b3555a67373c736ed5f66f99fd2b0c8eb3ac856b430aa6eef3f79a925c722ac39667f3e
1	\\xd707f6ee0f47d6d533206ed994325363aa329646b5d0314987a06b33fdb4b9db3fcf0a76436e7e5d497d2df51b55083e7aec98e2d1c4c5e18da4d647f8318e88
1	\\x565d8d5f41b66f7d60016511badbef3dc33dfe9c7e1a7bc20c87daadc41824be61b485a5d9d4a27de5cde5648249d0ff67cde5ce1731ba3bcb600fd5eb76b801
1	\\x0a5c6e2558c383f3008bcb27970867e46f7c62aa1f90ef7f923f8204dddaaa35fe8eb20c141a57869c5b895b5ffad1bbdb19e6cabda4e96339d3a98b3230d8c2
1	\\xf39dd6d991e8b39c9f0a6d8705a8ad0068c74ec1446e96ae708ee4c876f16ba793a42ab12b5a736147019011f1f8bf95cd439c04293481223bf822a89b010ee0
1	\\xa598329649094e0a89155d72b42e1a7225767b140d8452f4327f06ab8af8872ac77ec2e1ba90be2fb14e19c90fbaa8b5fd7df2bcbe904598e17c09cde0d8952f
4	\\x3676e14bec87012a1ef4e7bad8bcefc96b18a8d75b24b191ab4a793fdef2b983b43b206f02ed469c190138f12f269f4f23057d3ce97a2865f2e7de2e857752c6
4	\\xeb6c7cae835471016a55bffb10b979b266463a2e6e9d8f63377de64880abf86a935c61450c9fd38aaf768410bd676905ac595f02a9d947d8d7ac404cdbae3b7a
4	\\xff9c671a71a07cbd1e2984cbba160990ae40a528f9a1d7475331c1b97f5b0af21e1cd4066c0ced0597ff262ff1e6538bf4775b9f41c77dd7db4d637a6473b1ac
4	\\x9c2a64e2f36d05b45411e9f1c628acfe6ef6f9cde87d6156f17b1b114de078b92634bd8335b8473eff8a3906be636057e2ad5310af4da96dd0a501061875859f
4	\\xc49d10e052c2ed9cc54d1f247e6cb78868d1fab7d6278fb936d5cd98121f7b1c1198e2a6ab5c80ca14bffe3fd2e2010b32b02ae2e6a3c29b10ddf7e849de0566
4	\\x601a139fda0ba3142c9a11f5f64ba0dce8289c5f45c0f4257ba39a15f686f548419be0c127ec9406f935ad79e083e675286ebe68b94134014f79cc4a1ec050fe
4	\\x2c8a770832c20541567958681a6a3cd011c92051bdd9da77f61282c75f0c9843f67a49c0532aef0ad51da657bcd85b9e4364b6b6c4f107b1766cb891bbcd8080
4	\\x7a8f3c7eddca9e1670eea57756074c4d8545502962f7f7dc03bc88960ea501569a91de7a46db636c75aa3994fc5045e154ef6b1e571ff51eab511afa9dbf3e71
4	\\xaec98a1be95e02769e9486472b3729e2a5771d377c5494419dba889998b5a7504501ece18729d899d0955d425bb94f20dbd45ab418d840760fb1ede87a02c689
4	\\xa487effe9d926e718d4e6aeba52e1c46e83f21c90c12b0edb0660ceac9e7e66fdd2db3cfc8c3282874be992ef9a4cc67665e72963de3f98eb3b98601587bb6fd
4	\\xb649b38d797bab334d46f1700fbca9f5d09eb0f38dbdd878ff24f7c50fdaab393cbc1924d772cfe821ba0ade949fc628721a2be43c767d83aff049c61d76ab70
4	\\x2db46c560e35c1c2c092ad315f25004ff300428d2a7862827feb5eb4f3762d8ceb5ec3b88eb2f6df35beba8aa78cc841f73940d6201cd85734099f1faa814b54
4	\\xb2ac27e5ccf0922d378f7b2e4ae8affb4adceb68d2f297a9cec9b55dec2b28e3944f06cdf6513eeb9b8e91e944cadbe062951efd3a96958e0871d1f3272255fa
4	\\x9cde06ac1cd335d8f31e740989e9a0ffe544c651144d12b4f3a63cc14a0f19e003e2719fc9bc8692970e72ffb95320c6c78e3467b228fdf57fcd950a1c7a7d60
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x5a7f7510bbe60fed8b164e472e56f7138f4393cd8b0314043957bba941c204adc3d2f22e320d07afcc9b86afcc7d5b83ac7b896a543d1ce0cce31dfa9b708029	223	\\x000000010000000173e2e47ba1765f5afecf031ae1843b780738092f271e2711337422dcfe6d3429d7102542a2c2e2d0b403ae9b94db8d42e5b87cf754e834d38dd19ca3f669ec25cce7e7f2ee3c2b5a5757944ad3a937445fae3c11b7f5f2961c3a5a9ccefbb3bf8dc4e8dfd06c556cc5ed0ccbc63aa050e23a2e2a4a66006ddcfcc50ed405807a	1	\\x25d56c5441bc6090c8a75072eebe7cd72f2342ffc0e5a5f710227412b6554d0327afc97e2354025684a22eaf9aebfa303348006e9734a7810b45abd263d16a06	1660654407000000	8	5000000
2	\\x80f609ae4874d0d1d27d34722303eff525dd6b1667832027a8a4ddb441cbc401c48e91b7b7a313c58a253f6715bad938e0628c83f2d1810d08724cf28c492028	406	\\x00000001000000015682be45a1f768fd28864610ff01cf6e8a3f1cfc7c35a70a75bf0a42d6c69a2c514101deaf6e799ca14ff35b67abb5ecaf5a1135d6aa9d1a6879fbe0319c925c95867c7c3c0ae8c594d17257948d2263a8b8273e6b42a7e6dec237a276b7613702d5260b43743b8652f83204eaf8a7c0bcdbff6039b18bbb6ac69e8999304a1b	1	\\x85e2fa242fe5d0a52964d0b1265d3e350287f617e167ce1f52ff1db84f6266641623751e52dbe2e79dd5705ac2a4017bdbb9d767101e6956928c86fdff21e20a	1660654407000000	1	2000000
3	\\xe7bda2ec636b9f9f175caa40872fe13f69280877c67888c990c39340c9258b0f295ff6f41e5e29d1a39c799b7e222e1b7cfeb81c5044efb1483a14c5ae7c5f6c	391	\\x0000000100000001392a68efea0993517362a487b7289b3ad490c4b5365185418de89fdcca85bfabca5425361ba1c6d2727eea1c7d1246e1e74b19166add04a5f3961d4f939df5a37a0e6be9fd7205e73243c3ed74b7931a16c5901ffb20e41f9e7db70511e7c74c59df976425529697fcc4b94c9fc5195e9484911dbfb42552c39d6bc3f799299f	1	\\x9a799fc0a9d9cf25830796b7a27fbad36fe741ec6b564002df2ef077292d06746968b1e15252ccfbcfda6c8cf07e6e21e4e87d0fdecee311869e557849ac370c	1660654407000000	0	11000000
4	\\xff5ffca6ec51dfe1a76075a3188510f720514b43b82e2510cf5626f999bfa0f146428aa965bad5edb0f7c471b7bb7827ca432af4718de6998ef0c7dc9783c89a	391	\\x0000000100000001ad7430052962936295df39f347bb5f1f0f3ef7f2ba959fde84349b7eeb794523e39473b90acb7028e9626e42b52f92614a183509b64b644ae1d5bbaa411c7b60da3e999a2b050a96d75cdade7eab3777aa3e41310ebc0ded4ff2484dfe2d2c1f75592b4b9e5e24d1ac1baae9f0791d0af8ccb4b2d1541b77739412c7ea866c79	1	\\xbb88a328f4943a10a8a91f7fe11b0a645af2a80d5ccf6e2c11c926d55e5af0dff8f12b47599220be993a9ca8b422a3bcb04f919bf8458fe0626696ffcd9e9b04	1660654407000000	0	11000000
5	\\x323e5a1163f5210e82ddd56a30f34c56f4e133723c6938e7ce8b1136ee1faae41ae1e8b655e768e07ea10e6ebc56b4cf911956ed73d144b78463f05f7cd86d51	391	\\x000000010000000178df6b54310183dfe498ed9f99491762de8bb55dfa0058849f26e73b2cc06d83da95db0afdfba8914911f465bbe8ebb4ffbc464b20b5315fa191ae568fb6d1216781b65d41387f49660bff5b4e2e16d0bd39314fedd3aa690c743bed34dd9c32c76320d61630ccc857e52ffe5a18506b6adf99613bc1884dbdc8345520e8161c	1	\\x000c4f6015ea62b1965aa84a00faaff59e6179db6668576cb7771ca88f8a5f6b296baa3869f3063d8226c805de697b7f7c907d9d5534c67883b896e0932de30f	1660654407000000	0	11000000
6	\\xa5012e03825ba9ddc9fed44e5dfca1f9c98d9a06b14641cb219b403306352dfe0c60b29b24ab55f0f103d7a795bddaef1900ea471244c4db410fe860ff2dd3cb	391	\\x00000001000000013f352fea094dbcd6a5ace4c3532e622ae70e3b8dfeb0eb4296ca4dfa2758ace17a2218e8964b2c85e0caaaad9bc1ebf9f811798677953387237ec3a241b3277e63d685b681b224a454238c636972f24674c496ce58e8460abbce3c883ff0fb2c5c65028f2184948ca6b4a048e8b98f799be0d64ebee18e2bc1b35880c41f567c	1	\\xc7de62604637338a96c513262e6ba0191e215b4c2987e6dda05015b212f6f21c363be160121cf99c248771a5b0674e2ccaede0998c3a710b8fec0bba63800b00	1660654407000000	0	11000000
7	\\x67baee369bb152ab80b17ea8543be2e148e7d7da63c0b3e8c8a0907d1b3555a67373c736ed5f66f99fd2b0c8eb3ac856b430aa6eef3f79a925c722ac39667f3e	391	\\x000000010000000164fdeabaa4b1ddee6329bc2f7a5d8112e00bad65fb4cec99719fe64c32657826cf7aea326f3c1e0dcb12207b8399501bd51af5ba7ea1ce99e1bd9ed23fb29722675a90fcd86f8a6c6583d29a0f1dd9e860d591574f1ecb585ec5723ad91e3a61e8c2bb61ede6071049910119e3f032cb8d95c9e58cfda4cc34f64497b49caae9	1	\\xaddfc54a41566a16441d05f4773fae88a821ff0956d3d88718b46ecc191a673db552615220a9ca6e6b36488b713e3350c555fcec39c19861903f320b7a0c760f	1660654407000000	0	11000000
8	\\xd707f6ee0f47d6d533206ed994325363aa329646b5d0314987a06b33fdb4b9db3fcf0a76436e7e5d497d2df51b55083e7aec98e2d1c4c5e18da4d647f8318e88	391	\\x0000000100000001697ab9c35228b744451f028f0a875c84a0e6806405bfdc44bfb9b1caec69e802aa3ed8049453123106bafd31eb46a52ad019adad6281bdb517f01a18e33a97b86a096c35570f2a865c8dce848b0087b7627547a57548310bc20489dc103f293c0544a6660102e5e7d21cdb21df2b1ce92fe6f10dd545691bd02d096484b88056	1	\\x3d172ce330becdf46df5e7f1a5b2fe64463059a803bc13287fc32f8f8346ffb1d957968d8038e927a9c5eee09dda875598428cbdf91e0535dfea86c69fc21d06	1660654407000000	0	11000000
9	\\x565d8d5f41b66f7d60016511badbef3dc33dfe9c7e1a7bc20c87daadc41824be61b485a5d9d4a27de5cde5648249d0ff67cde5ce1731ba3bcb600fd5eb76b801	391	\\x00000001000000017c5d02515be2f7ba0cb399eb24383a1af3c5355ca4a87304cb97c7eb6bb5edb92ce9d1cd4abbf08f74428df90fdf93fec6afedf55d7ed75f10915e02eb8f9b7b4f91482ac48cd3ed92a87abb74cd9977643c2d549a3f6d80cb0f761a4e1bd7dd1ed53d23f104b4c855fbf1ee0496cc8cdbabb0c87552c31d9b14be084d5cd28a	1	\\xafee72b45bca47c7284899030ab91c08a6a25c903272097c8624a94f891a447e72b49ad7275c83c35e9ec59cc53bcd9eb1a9c61fc0fdccb71ad696f78a1c0e0a	1660654407000000	0	11000000
10	\\x0a5c6e2558c383f3008bcb27970867e46f7c62aa1f90ef7f923f8204dddaaa35fe8eb20c141a57869c5b895b5ffad1bbdb19e6cabda4e96339d3a98b3230d8c2	391	\\x000000010000000180ca7e6471deee5a29d3f584391c9464e9983f8a427be6e751cf68b44b20f9e16976a8a574abc60e92595569900bb8ddbc00b8cf2c56601d22eac71fb9b7a0492e7c03d995febc9ef24ed67ab1c229f2abb69b9e1a2ef3dd0c2d17742b2f06cbb86e702b3279cd478547d47eb1f65a3afb91b135f30064d260b013ec6605e3c4	1	\\x5787221eb37494da38a20762066e8728d985f5b1e6576a3526532614148579a03513eab70281264e306ad17f912fa911ec471c8f7be901a084222d8b37c04806	1660654407000000	0	11000000
11	\\xf39dd6d991e8b39c9f0a6d8705a8ad0068c74ec1446e96ae708ee4c876f16ba793a42ab12b5a736147019011f1f8bf95cd439c04293481223bf822a89b010ee0	14	\\x00000001000000018f078a1a5aafd378ae7286eeb771e0fc50ccdaf20d0c384d54c0bf2811706eb9bf4113cbcf3bc608ff1745c299b882daa92023bd9ee3d51ee7fa7f2ce0087bf291cc2b800d5688ece9f8ce29824002ba6985c18da7198eae5c1844599887af17b8a6a54bf30a24ca8a868a65104b4a47f1a9806ce8b3c01cefdb4806151afa65	1	\\x67e1da6d3f248f96d4ef573c08291adc9c56eb14c7926e878de6920ae12edc445f9980214922a4076e2ae009cfa012e1f55ca0faa8845d4ede3a3d8bd92a5207	1660654407000000	0	2000000
12	\\xa598329649094e0a89155d72b42e1a7225767b140d8452f4327f06ab8af8872ac77ec2e1ba90be2fb14e19c90fbaa8b5fd7df2bcbe904598e17c09cde0d8952f	14	\\x00000001000000017e78e78e9ee649380d854ba408db9c722fbb9e381d66701124a087949543733e6e627ebd6527d2380685ca7cd9fc57710a0ba37bd810d206b8cd11edc2d0bfafe83590412c4daf16a1fc9f50c356e61f5d11fde7188c32cf180657ca8ce47d48a72e0755b7708047fb7204c0964dd3648368471a8f243f2cb43daf91b013dfa6	1	\\xfccfb712fddffc8c467df0bae8f2e6bd93e1294ea8263a03a4f422a86ac65cbe8806b89e8dee72e9ed519dc8a82ea6d25c2f195ffca8025e9f6f371ed7515302	1660654407000000	0	2000000
13	\\x3676e14bec87012a1ef4e7bad8bcefc96b18a8d75b24b191ab4a793fdef2b983b43b206f02ed469c190138f12f269f4f23057d3ce97a2865f2e7de2e857752c6	120	\\x0000000100000001143c70ac85e3eb02390a9854ba20cac82241d7bb51bd278e670a5b1a8ca1fd77f3f601f757d1bf1de789de851d505522eadb19844e631483dc075fb955d8c1ac470015d08d9e8089e20acf8cc711efe9c407d7992bd3cc9edfa893230a904a36d22de0cfda77ea7425491c7a9d4fc4d23636bb9c122dc82a25cb9da92b860adb	4	\\xde7b52fd7f928c1e68f51dcd4b840da0579a86551385c3e7e0c68c58db91b7d0148322f2ddc0dab9189ab1ee7292142f877ee738a346aa5cf36d8e227d4ee60a	1660654414000000	10	1000000
14	\\xeb6c7cae835471016a55bffb10b979b266463a2e6e9d8f63377de64880abf86a935c61450c9fd38aaf768410bd676905ac595f02a9d947d8d7ac404cdbae3b7a	160	\\x000000010000000111ebeaec4dd9631db3d837747ce1d95159a44f38920fcb1786d9305b4f2d42191f18f08630957b4590ee74d09fb1ca31128944a736fe4db465ae273c30ea18f9beda7f6ec17cf5ec692862bda4c71b31113cdfb57f9920a4a03c8e84ebda852d6801f02d3b2fd3cee2aefeaac136faacd269702083de6526e1e72ea7146307f5	4	\\x3f8bd80ea53917360cc01c38051849f7233277aa03f6383c98626eb1aa9f750a719f12c8a1a75827f8b3e45ef112526aa4db29d455c195acbcc19f65de397100	1660654415000000	5	1000000
15	\\xff9c671a71a07cbd1e2984cbba160990ae40a528f9a1d7475331c1b97f5b0af21e1cd4066c0ced0597ff262ff1e6538bf4775b9f41c77dd7db4d637a6473b1ac	112	\\x000000010000000180eb3e3211a2f409d0eea5a104726c00548fa81071cba8cfcabf91a00f3eb4e538fd237c387bcbb3eb2ce21adf08619ac4b1b0fa063fc8da2a5036f30468184df0177e3382313af02a60763a8419f5420091ed66ef8431c8b4984b5841120b63f9f66c85bde0c4a2d43222ae95cee0440781f56c805db7c6cf1b86fd5270ab99	4	\\x8efd976f50fdabd0cac4d02d9d24c78febc17f30a852da55eb99d6ed923491c68c669442c3608e40baac8cb454c1a89c03390767a84e1769848f64a5995b8206	1660654415000000	2	3000000
16	\\x9c2a64e2f36d05b45411e9f1c628acfe6ef6f9cde87d6156f17b1b114de078b92634bd8335b8473eff8a3906be636057e2ad5310af4da96dd0a501061875859f	391	\\x0000000100000001064b027d6bbb24ff79e8642e59b58c69b5ce032b33395ef7ec6b2bbc4daec5921f772da78cca7395e3e51f06428010b58fa7dedfbde66277abe889b37869958581f86cd550f1dd784ccb779d6d9123c233a57033b8294fa4b915ceda569ee2562939b58f38cd44918fd097eb891f2c3aaf798c8ba1c86313691cf035c8533af5	4	\\xc4ffb42f0782a463a9561b3b936f71e654510684597eec0e8780df7a71442d4b08491241ac1dcb457f7f8b33a73a284fe497b87dce44d528e96f72bcef318c0a	1660654415000000	0	11000000
17	\\xc49d10e052c2ed9cc54d1f247e6cb78868d1fab7d6278fb936d5cd98121f7b1c1198e2a6ab5c80ca14bffe3fd2e2010b32b02ae2e6a3c29b10ddf7e849de0566	391	\\x00000001000000013dca500bd18c8347e1ccef9bbc1e18302555fa08d191dbd3c31379d76dcb266f401828ccbb9f62b34efbb739e688c8c705e96caeb70792b129229a786164c4d7bf05e2438112e3d26f628236525e00facf3e02bcb77e4fb537ec9460c2cf4080cb0de4baf57a9cfb74755be141dd58ace45a0a5a286e6823e9c072d2bc044466	4	\\xc9662cb45e29745a13be6dcd7415ba69fd38fbfa988c3ae2715cb78e6fd0e4710c6a420b94578010cdb2cb1dff8696c461382cfcf8753c6302966062fef2c102	1660654415000000	0	11000000
18	\\x601a139fda0ba3142c9a11f5f64ba0dce8289c5f45c0f4257ba39a15f686f548419be0c127ec9406f935ad79e083e675286ebe68b94134014f79cc4a1ec050fe	391	\\x000000010000000110892ac724c2571c41370e1ef4d899eae6f9f349c8cdde0ebc1518a33880c3eae80ab6558b0bfba83560c5aa75ea6c0d1a181e0286f5cf60c1a6799c0a8b820a7297d0d2a85ebb3e8f8ae04d7bfceb18af885182f634b566d90d91f44e0d9ad366b3a047b4167baea5a3339d55331e9cc06ca91c3832c6233a63974b2a0fa6ad	4	\\xf434a820cd9b5472d8d9b82a2221a98c089e92c74ab833416abbbec1832495bbcf5d672c1321e226bace72851b24feca97775e40ba4b5bc79f3ac76b8404950f	1660654415000000	0	11000000
19	\\x2c8a770832c20541567958681a6a3cd011c92051bdd9da77f61282c75f0c9843f67a49c0532aef0ad51da657bcd85b9e4364b6b6c4f107b1766cb891bbcd8080	391	\\x0000000100000001b9ae9ddc3b7182abdc4579d88510c51656dcb36ea7d140a787d0a058269d014a8805abcb439b955c026a4fa05600a463ceb7892c16b0fa5e31111e45026a2849337b729635a2b819bc958a8988681aa0ce6640d5952984527ce7ad8e116cfa9777d0496ec163052f2b95c44be1b54988d39d069ca7fa11a0458a13efff5d1f66	4	\\xcfc529423f5065cb823c78b4693b701bc2fee7ceba1a643e79d61273e83a5a778b0c3706f6208c3b70ad6834625f69589dbb03437f279d9f75a85518996b0e00	1660654415000000	0	11000000
20	\\x7a8f3c7eddca9e1670eea57756074c4d8545502962f7f7dc03bc88960ea501569a91de7a46db636c75aa3994fc5045e154ef6b1e571ff51eab511afa9dbf3e71	391	\\x00000001000000010c6cfe76138e41205d56b6c7905679f2d2dea3d940039ee9032d40a26af23e004a183d936db8083de5e3560db17d0f29373c28403c15a7218ac08d69926367dba7e29929851171c2586306fb3d4fba490001e920b9e568a69dad9c7337c599d68480766f111b5c2fd6baf3a9fed3f7c181b6735bdaf159b84d74502ac7b87567	4	\\x62f211442cda8966755e6c5007aafc5f2227846f277e873c0cc29c8cd582e318cd4b2e1290864b6c3c1e5f42bab42eeea658454dde001c35a3941d6a7548500b	1660654415000000	0	11000000
21	\\xaec98a1be95e02769e9486472b3729e2a5771d377c5494419dba889998b5a7504501ece18729d899d0955d425bb94f20dbd45ab418d840760fb1ede87a02c689	391	\\x000000010000000162f0e890d19d5d0369a2bc727528cf26f7669a8b6fd418e2c9a671847489090778e31ebc182a91dc1ab96411c960567aa006a22f5584b2a40919d8b4b31419c1262a59aab5f7e554954e160e9637603e8516630b156bb44de0458b46900d484b784fd4d7a91a44d8ec53f58a066a134e7fc1cdabd6cefcede7d79c16e235af88	4	\\xfebb1d4bf9dfe4b9fd7bb5e8053101b9287fe9096f72c55ee82fc74bf51a75da50c0458e42f0f23da35ea05c10fdd1da2b4e7a69ffa7cead14346b2863f08601	1660654415000000	0	11000000
22	\\xa487effe9d926e718d4e6aeba52e1c46e83f21c90c12b0edb0660ceac9e7e66fdd2db3cfc8c3282874be992ef9a4cc67665e72963de3f98eb3b98601587bb6fd	391	\\x000000010000000123f6ad84672c424ec8a0c22883c4833c29be1bf80ca9517226d5d04551a974d7b2a6558c9f0d7fc26fc986279611bc0392d56259b96543e5aefc6f6a206d2fd38a37f76976a83ea4776270d7097f51c434549f0923a63403fafeb5ff5e060e23cd1f4820eb16d58b5d3e1b9b4d624aec3a3276101f327d6b8bbfedfcd64f470a	4	\\x3b959bcce96d034de9ba5a6cef7886c1b01f349c3518e0938bc9a0b099063a8e69c297189a2595d487c9ac8ac53a069fe502b8abec01b98c0c4f9a5a5382390b	1660654415000000	0	11000000
23	\\xb649b38d797bab334d46f1700fbca9f5d09eb0f38dbdd878ff24f7c50fdaab393cbc1924d772cfe821ba0ade949fc628721a2be43c767d83aff049c61d76ab70	391	\\x00000001000000016a0e094627ed5ed7441070147eb828995fe74fa3d5eb3e259ebd08b68dc7fe5de57eac03d616eb7914816283848197c1f44d6be719d2df86010c11a1c57ca9fcde0bfa278fe23a7b0125fb850f72143bafa0c81d0853f22b75a396c2c0693e5d26bb319ca186bb47bdfb22adbb9aa3230422644fafec42a2bdc44e51aae7ed2d	4	\\xf60f7038069dc4fc60d851335ee65a685835c5269c8f469673762dc917071c33ae29b5679ca1b3d0e1a029d8b4328f3c64b0c4664f196bfcaee408dcb561b200	1660654415000000	0	11000000
24	\\x2db46c560e35c1c2c092ad315f25004ff300428d2a7862827feb5eb4f3762d8ceb5ec3b88eb2f6df35beba8aa78cc841f73940d6201cd85734099f1faa814b54	14	\\x00000001000000011446ed6c532b2f13de97478b2c17b55c460c410afa4380a24dd42ee6381b06949b7fa0b675c602cb1d2cb79d8d6f1f1692e2891fd1edf11d12d09f712dc99c5cd0fbdc4f2d69f32d01cc966d00b0b4a96a3e13a636894d23cc7a8a4318072f0977d7e1c617912b38c79e65c74c1a136bb95735efcd96cb7c21b8259ec251489f	4	\\x85cc4cf8c1be3e111b8566dab26018cf391799614f1147a3bc056f8d89e028f3db8e13199cde031635f5f1d8821efa6ac2d9fc038379225d886a0d91f04cc907	1660654415000000	0	2000000
25	\\xb2ac27e5ccf0922d378f7b2e4ae8affb4adceb68d2f297a9cec9b55dec2b28e3944f06cdf6513eeb9b8e91e944cadbe062951efd3a96958e0871d1f3272255fa	14	\\x00000001000000015d78ae132da796f583a8607ed39798135678b9e422fbf47412f1fb96e2a72f2eb0d25daff19443e1ef815bd0e241e19124f2ac1991621cc0d1e2cf20dce612727a18c9a004aeb13a5b04dba841b75af6a10d486b2c0f43b021c80f4065bd8011b3c1a6d4b0a76e8abc1c4667dc5dfe705012a9756f2c0dc9691a26f9b2eb9e7f	4	\\x1500f178ef359ecf2c8f617309c6e1ce51c16b6074f231f7b7d28e3ea8c2d15b1afb9d51dbfc1f94cb3e6e8d955e2a7c7d24b94c721d9a9ad92cc6b5cd602c00	1660654415000000	0	2000000
26	\\x9cde06ac1cd335d8f31e740989e9a0ffe544c651144d12b4f3a63cc14a0f19e003e2719fc9bc8692970e72ffb95320c6c78e3467b228fdf57fcd950a1c7a7d60	14	\\x00000001000000013ced93af7f555c6dc1cf8f9b138441c7535f2bd08988bb2908870ddd609768a75a0ca1dcab03be33d8b12339b806ce6934489f18d77699d6b544ecad46c993ac3af60e71c45a4bd11db7ebc0b8b1bfcef6a0e34bff517ee52fefedfbc39eb41f0dae82d9c4ee673a752e1c37b452ea7825730260baedf81478563c8d3ec0106f	4	\\x8224e0d7d8374882ba9bf3309b36eb42b7a6981bae811d644edffb7c3712269b59d0353508901f64a68de6d16ef470bca2bb5132dd145486957aca057692cb03	1660654415000000	0	2000000
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
payto://iban/SANDBOXX/DE471160?receiver-name=Exchange+Company	\\xc5cd9ff99335ed5c6ff491c840bcee93c232b8296713b7b76c22fb00bf0881fc9ed108c7438428fc78d1ba7ac95ce2378b33063a4b808e1a24184008eec4610b	t	1660654398000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x3847cd25aa2def0d9c1863c388d1578231deee0f2149b873953b63e9c2b3eb0f272ea762e7da0ff897a1fd88604cf68e0aace0b5607838bfd628d7b3a585b900
\.


--
-- Data for Name: wire_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_out_default (wireout_uuid, execution_date, wtid_raw, wire_target_h_payto, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: wire_targets_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_targets_default (wire_target_serial_id, wire_target_h_payto, payto_uri) FROM stdin;
1	\\x17e36f9902fada59cccccf07172878ae75a41daa3537c439b45b8c4ed129fb57	payto://iban/SANDBOXX/DE236345?receiver-name=Name+unknown
3	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43
5	\\x7b4b32ec2d7f43a6b45ee01806ab31368d50c45c7c6d1783b0d7c0ac26368540	payto://iban/SANDBOXX/DE209794?receiver-name=Name+unknown
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
1	1	\\xa2de7d3db3c3095c9c37f0b4cdb56614a64c8ed5235a1032d4bc94ab0eca424b31c52a5fcf29bd18d1d9b9a2bc88166531db9ce649435fb809547d7b001d9058	\\x95b8b123aca8e5792f318eb8ad9827c0	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.228-00RA4YMF2S8VT	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303635353330377d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303635353330377d2c2270726f6475637473223a5b5d2c22685f77697265223a224d4246375446444b5243344e533731515932544356444236324a4b345333504e344444313043504d514a4141503350413839354b33483941425a374a4b463852543743564b384e5748304236414345564b4b4b344a47545a5130344e385a425630304553305030222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232382d3030524134594d463253385654222c2274696d657374616d70223a7b22745f73223a313636303635343430377d2c227061795f646561646c696e65223a7b22745f73223a313636303635383030377d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22334e5642474d573853564d4b4134425342435839485a323356374b425852305a5a30324a5756584243524836524e59534d353747227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22433346585142384a56425144514e364b56514a543650434648465151314a5833464a4d335848394643584d364545344a46594747222c226e6f6e6365223a22354a3841434238414b5a4158395943383350413741464439424d464b333357504d3954423647483656324457444732534e445030227d	\\x827f73b62cdbab20753edd20919233608f6e3d166b5dd5d1f63b7e9ea866fd183c6c4113576dd85e6f6b9a16d3852008d47007ad9981435d78d9375b35110ae2	1660654407000000	1660658007000000	1660655307000000	t	f	taler://fulfillment-success/thx		\\x30cf1250df17f685a9c3e6fe6ebb6667
2	1	2022.228-02W1HWVRBJ67J	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303635353331357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303635353331357d2c2270726f6475637473223a5b5d2c22685f77697265223a224d4246375446444b5243344e533731515932544356444236324a4b345333504e344444313043504d514a4141503350413839354b33483941425a374a4b463852543743564b384e5748304236414345564b4b4b344a47545a5130344e385a425630304553305030222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232382d3032573148575652424a36374a222c2274696d657374616d70223a7b22745f73223a313636303635343431357d2c227061795f646561646c696e65223a7b22745f73223a313636303635383031357d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22334e5642474d573853564d4b4134425342435839485a323356374b425852305a5a30324a5756584243524836524e59534d353747227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22433346585142384a56425144514e364b56514a543650434648465151314a5833464a4d335848394643584d364545344a46594747222c226e6f6e6365223a22595233594a363846534b4d43444145544734524d4b53424146465a48534139454247463434343752425858324446473241395847227d	\\xe7c8a519ecdd88502897c79378308b3a8f2be183147fcc56fca83b622ce4f99ab34a46ea3b4b9b4b53892bf843a591fe57730c9cd883ee498da05376448e3508	1660654415000000	1660658015000000	1660655315000000	t	f	taler://fulfillment-success/thx		\\x63dc236aaf25b6d15e8912baf51b6316
3	1	2022.228-01W1EHNFQM5T6	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303635353332317d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303635353332317d2c2270726f6475637473223a5b5d2c22685f77697265223a224d4246375446444b5243344e533731515932544356444236324a4b345333504e344444313043504d514a4141503350413839354b33483941425a374a4b463852543743564b384e5748304236414345564b4b4b344a47545a5130344e385a425630304553305030222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232382d3031573145484e46514d355436222c2274696d657374616d70223a7b22745f73223a313636303635343432317d2c227061795f646561646c696e65223a7b22745f73223a313636303635383032317d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22334e5642474d573853564d4b4134425342435839485a323356374b425852305a5a30324a5756584243524836524e59534d353747227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22433346585142384a56425144514e364b56514a543650434648465151314a5833464a4d335848394643584d364545344a46594747222c226e6f6e6365223a22303150544434544441334e32504434305833593433414e57414b395633585050514542464847585a335436574b46455932534e47227d	\\x7d17d97ddede1070c10c51a33e9491e94302d74014620018f0f54bc991e493c0c33cf0d5c483444e6c5dc3c258246849d19cf15170774f361db56ae6fb724e97	1660654421000000	1660658021000000	1660655321000000	t	f	taler://fulfillment-success/thx		\\x70025150ce5a02fc1454f6c7d63812cc
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
1	1	1660654409000000	\\x2dabf8597c744b25c53956be0a58a67853eba9e3d03c7a473a594f609eaee337	http://localhost:8081/	4	0	0	2000000	0	4000000	0	7000000	5	\\x9c632360d0c900fb2d148afada5dd65cb2d0002d0e0d32d970ebbac05b163bf06f79c0e68f75a813f012e00cc00096f32cf420a9fc05ceb076dddcb5a2899104	1
2	2	1660654417000000	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	http://localhost:8081/	7	0	0	1000000	0	1000000	0	7000000	5	\\x0594eed06b2991af84673626b6eed133274bc63fc370c5f5145d3d732319b2d94328af0a90b45fbc787db69cea4d51a692e9a2c2b8ca81a610a2082d4ec1e70d	1
3	3	1660654423000000	\\x218ffcd2cc9b2ff4c35ce5eb12500cb091ad85e091ff642d13c0b94169d848f3	http://localhost:8081/	3	0	0	1000000	0	1000000	0	7000000	5	\\xe881e2b2cb12b6d6539f51aad37e39c247a2288bd24d26efea90c013058353327aacb578a138011a70390518d22cdb06099cf5e6648af4628396eb5206505d08	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	\\x63b9d959e67e642c4aaf6a544319c636d53337e944cb7f3e4bc207453fa01e95	1675168991000000	1682426591000000	1684845791000000	\\x7fa3cfa3804af9836d5a421e97b5daccfd0d0876a511d3df14881580f0b7c4259a8922fce44f7d7801fad4540645fe97c52bdb542971b9d4973655d8e83aa909
2	\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	\\xf04f93e0462e5561211c2965203e125a50b66de698d59336db015a6a3ed4e5c5	1682426291000000	1689683891000000	1692103091000000	\\xba376e2ba581dc09b7c980aec16a28154d50cbcc56b4c019b2a74f8c11e90d641df2cc2e465837a18dab7333340c2197b611767ab3b11941a3f836634f7ef900
3	\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	\\x15f6a1c6e02150e2159af7c8b575dc669e2676345844fadc82640f8dcca448c9	1667911691000000	1675169291000000	1677588491000000	\\x80701b6ca302d7dc016a070cde5f744138d0d7bb58c138f6ce5acc3c08300afc57d4ce4169b92a7fd2e1242a7fc8beef1971591d0286a9f9bb171445db64a806
4	\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	\\x3c26105d9cb3541f8134cf8450ed4f6aa02572aa33d0b14b705c8edcaced4cc4	1689683591000000	1696941191000000	1699360391000000	\\x7fd2984ad70d97c2d7b3b5ebe8d9355f8c941be321fec6f3709995cc8adb49c9b2903325f07bf4cdeaa676bb55669cf5cd43392ebc8f04d8aeedf89073441609
5	\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	\\xfe2916caf605ab248662840c40d412468fc0c6bc087a1059df017a5df7e02c51	1660654391000000	1667911991000000	1670331191000000	\\x3e222dc7d5df2768e32c4067e9dc2e1c6edaf955299c10474b6ecb24c9b0ca33b2c6ec9637e330e03c6bce795f3ce5141eafb254d98de97596fa0a693913430d
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x1d76b85388cee93511795b3a98fc43d9e6bee01ff8052e6fab66226c57d9a14f	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x3847cd25aa2def0d9c1863c388d1578231deee0f2149b873953b63e9c2b3eb0f272ea762e7da0ff897a1fd88604cf68e0aace0b5607838bfd628d7b3a585b900
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x60dfdbad12daeedbd4d3dde5a3598f8bef70cba37ca83ec52f67686738927fa1	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\xe7d4c77080e998b482881f1f8380f68457cdd351b89eb864c1059f18c32935c6	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660654409000000	f	\N	\N	0	1	http://localhost:8081/
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
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
1	\\x3b877908c67cb5398a360a1197ecded3210e800402f4c15583f5cf837c90d4ff42bca70a5ac2444b30a25cfbf9d46f90219f374ee33964c19420fcb57b610a06	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1660654418000000	\\xcc0700e2c32290c2f4603707c44ed0d0344afdefd394e144bbefd390ecb676a9	test refund	6	0
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

SELECT pg_catalog.setval('auditor.deposit_confirmations_serial_id_seq', 3, true);


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

SELECT pg_catalog.setval('exchange.deposits_deposit_serial_id_seq', 3, true);


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

SELECT pg_catalog.setval('exchange.known_coins_known_coin_id_seq', 7, true);


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

SELECT pg_catalog.setval('exchange.refresh_commitments_melt_serial_id_seq', 4, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_revealed_coins_rrc_serial_seq', 48, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_transfer_keys_rtc_serial_seq', 4, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refunds_refund_serial_id_seq', 1, true);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 16, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 16, true);


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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 19, true);


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

SELECT pg_catalog.setval('merchant.merchant_deposits_deposit_serial_seq', 3, true);


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

SELECT pg_catalog.setval('merchant.merchant_kyc_kyc_serial_id_seq', 1, true);


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_orders_order_serial_seq', 3, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_refunds_refund_serial_seq', 1, true);


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
-- Name: kyc_alerts kyc_alerts_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.kyc_alerts
    ADD CONSTRAINT kyc_alerts_pkey PRIMARY KEY (h_payto);


--
-- Name: kyc_alerts kyc_alerts_trigger_type_h_payto_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.kyc_alerts
    ADD CONSTRAINT kyc_alerts_trigger_type_h_payto_key UNIQUE (trigger_type, h_payto);


--
-- Name: legitimizations legitimizations_h_payto_provider_section_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimizations
    ADD CONSTRAINT legitimizations_h_payto_provider_section_key UNIQUE (h_payto, provider_section);


--
-- Name: legitimizations_default legitimizations_default_h_payto_provider_section_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimizations_default
    ADD CONSTRAINT legitimizations_default_h_payto_provider_section_key UNIQUE (h_payto, provider_section);


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
-- Name: legitimizations_default_h_payto_provider_section_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.legitimizations_h_payto_provider_section_key ATTACH PARTITION exchange.legitimizations_default_h_payto_provider_section_key;


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

