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
  FROM exchange.reserves
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
--   FROM exchange.reserves_in
--   JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
--  WHERE reserve_pub=rpub
--  LIMIT 1; -- limit 1 should not be required (without p2p transfers)

WITH my_reserves_in AS materialized (
  SELECT wire_source_h_payto
  FROM exchange.reserves_in
  WHERE reserve_pub=rpub
)
SELECT
  kyc_ok
  ,wire_target_serial_id
INTO
  kycok
  ,account_uuid
FROM exchange.wire_targets
  WHERE wire_target_h_payto = (
    SELECT wire_source_h_payto
      FROM my_reserves_in
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
  FROM exchange.partners
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
  FROM exchange.purse_requests
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
    FROM exchange.reserves
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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, boolean, bigint, integer, bytea, bytea, boolean); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
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
  FROM exchange.reserves
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
  FROM exchange.denominations
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
  FROM exchange.reserves
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
--   FROM exchange.reserves_in
--   JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
--  WHERE reserve_pub=rpub
--  LIMIT 1; -- limit 1 should not be required (without p2p transfers)

WITH my_reserves_in AS materialized (
  SELECT wire_source_h_payto
  FROM exchange.reserves_in
  WHERE reserve_pub=rpub
)
SELECT
  kyc_ok
  ,wire_target_serial_id
INTO
  kycok
  ,account_uuid
FROM exchange.wire_targets
  WHERE wire_target_h_payto = (
    SELECT wire_source_h_payto
      FROM my_reserves_in
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
  FROM exchange.reserves_out
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
exchange-0001	2022-08-07 14:07:55.3674+02	grothoff	{}	{}
merchant-0001	2022-08-07 14:07:56.428361+02	grothoff	{}	{}
merchant-0002	2022-08-07 14:07:56.83544+02	grothoff	{}	{}
auditor-0001	2022-08-07 14:07:56.986213+02	grothoff	{}	{}
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
\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	1659874090000000	1667131690000000	1669550890000000	\\xadfa94939e3c56224320945b7abc0878e9e40e0ed3ae795103b4b8e5d297f1a9	\\xcc863a201633a3b759eb909ddd9f4e6499032853eb8cfde2732f51389135f3b5de2504fbfc8f93161ebd285c677c0a1c0bfaf63b1cf8f6f8801098620f88ad07
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	http://localhost:8081/
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
\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	1	\\xafd8593e0e08e7e53e7546f30db6b09d8e6165e4c46162d195e2441b094c5e22cab5ed010d60902c044ee9664e50755f554f215697b42621caef77310dc3231f	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb7f43f0ea9b503c3367c76020afb1b8299828e194b5ecfd16aa1e17222a3e6af6fff4a5e95fb08f8e04de3d158b19101d0eb9c524d9d4e7f8c241b0c9bf22c83	1659874107000000	1659875005000000	1659875005000000	3	98000000	\\xf366195f0b7757993a4e601794eae1f2ce60bd825dc0eabef38717c5ac63b1bd	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\x184e53bdb81e0efd654d04799e826a5cfb728967ed5c5953380399f0517b8086779997d3dbec9796d5b07b071326a8a2b080aea2ff51696583b09ed2f3eba203	\\xadfa94939e3c56224320945b7abc0878e9e40e0ed3ae795103b4b8e5d297f1a9	\\xe02ad8b7ff7f00001df996c6825500005d537fc882550000ba527fc882550000a0527fc882550000a4527fc88255000010d77ec8825500000000000000000000
\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	2	\\x19247447150cb7ba71190aacda51e73524b7f6a8f52df0d50397c1cbac0838c9c910498c557ef5a37a6217aaa4461bcd2fca1b1508162b393d147585046af572	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb7f43f0ea9b503c3367c76020afb1b8299828e194b5ecfd16aa1e17222a3e6af6fff4a5e95fb08f8e04de3d158b19101d0eb9c524d9d4e7f8c241b0c9bf22c83	1659874116000000	1659875014000000	1659875014000000	6	99000000	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\x77aa47cc3c2a704dc27bb65230a43832ab45c713c4110d277074a0867109ddd0b390490b3a554e499e77403e51826ad80c13531fb18c57b37c385e8165610605	\\xadfa94939e3c56224320945b7abc0878e9e40e0ed3ae795103b4b8e5d297f1a9	\\xe02ad8b7ff7f00001df996c6825500007d1380c882550000da1280c882550000c01280c882550000c41280c88255000040387fc8825500000000000000000000
\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	3	\\x72f7f81b476669f23ad458dfaa7cac2afe371e7b1d49ae6cdb960c732c9dd0e24c3135f4a775acc65205554c6f75d2540f79cdedffc78dbf5d4025e77e5360f9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb7f43f0ea9b503c3367c76020afb1b8299828e194b5ecfd16aa1e17222a3e6af6fff4a5e95fb08f8e04de3d158b19101d0eb9c524d9d4e7f8c241b0c9bf22c83	1659874122000000	1659875020000000	1659875020000000	2	99000000	\\x37bb931d1a9f07d32ca8a0fcd212e3ece5c21a3be9d3ed2614d09ee9c05d4737	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\x3e844d0c640f0fd78c10a28e118bb9f79cdc6d58203a02fac5045db600449d26eb4e2d4e29db178eee8fab620fc5d5c22e20703247decf52d81209e4d7b25f0f	\\xadfa94939e3c56224320945b7abc0878e9e40e0ed3ae795103b4b8e5d297f1a9	\\xe02ad8b7ff7f00001df996c6825500005d537fc882550000ba527fc882550000a0527fc882550000a4527fc882550000403e7fc8825500000000000000000000
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
1	1	143	\\x339dfb9cf689673df768dc1f9b698ddeca878001bd6f26f28db2785ce44e500f6858127e27c5dff80e0ee3e830b6dcb9ed7e9901651ae0d025db7b2742160103
2	1	320	\\x8a9283de3209dc8a79481cf4abe2cea35f1a43b2413805f9fe2ce8b888f7dbd7137454a2bc17fad50564eceb632d1e164bbd97b0e17f46e7dfbcc08be9630708
3	1	359	\\x5aa7c11fb8c74557922c58c99d9e1a26d61588036bef58156d3b1930d53272ab43f64846d41009802e80892f520c100b7f746f8d7dd030d2f345d75e5284f90a
4	1	150	\\x58bcfabc9b3f338e8f693f05cede9cf291f72c7b027403ff42eb9fb703342e1f4602781497e77371d3358c6a66d386f0d98b97f6d9b7162295a187d3c9c2ac00
5	1	160	\\x1521c654dd7d4fb78a0f7aeb28455e72ff59827564b8d40da36703d397ab2339277ddc3f331303ff2e568b8a823d33c2ee0eb4112b4206aefa0b9ce920bf4603
6	1	202	\\xeaee4e83f4cd7c3b6ed7d74d8aaa99f9e5fca245c831b90623c6376cd923a07ff49b9bf52c0386724fe0f430526d63d210547d4881f9cf9d2f0b26241f00240e
7	1	207	\\xd73188681cf2ac7481e0cfc5421a9a0ec520cbf0412667a49d751a823fed28e98b3a8804572c91a8966998b99d546e9052f32fd7705a260ffdb7a46bcf732a02
8	1	281	\\x7adc70ac1e9f7fc7bdf13ae66a57165f421d4d279189f4852cdb456b2452312f6e98eb0b24d2549f6f51bfcee0e210060db4f6b03555c18c653955a4aad23e0b
9	1	210	\\x939abad501415e04e776881383d297282a05e68bd8ca69498217628269a50055bad39427097a5c7fc9b407f60ce5c247e95c2099a473ea593ef27fdc61e1680f
10	1	339	\\x5e53829a7ab60d872a6f74073d39231d2c5fa9ce0a2e30fa7e2b7ce483cc5bf747eeaf105b331e9e8533923eb835893861b0f3371c5e6caee188777f5e4e1100
11	1	238	\\x3848d7224f1ecdaea1e5663c88d7c8e7f8603d7395a4b906f8009cbb66660c4cc0540f03b168b0a309b6ca09e9fed11bbf151d9371bf1f5fa00377225c47810d
12	1	360	\\x8acd58be29d83e81184cd0dc606502992efcf9393c6f0223ea9ef9c5a10656b974f96a1b73c665a7453c8c12b632b65d0f7780d2f06811af146e06c7b25cca03
13	1	148	\\x087da2845262f9cb0d3ba1f88e496bb53f7cfa14d0dead4e18ba8cbefb02634db9f736faad136f58f2007da28c47324d3f796ea194cfc21f28fcef6cf094f00d
14	1	382	\\x7a6ad785bd45cc0e0f1fa091d247b81f905b5adbf31aa1022c986accb76beb05d10a27ef742960620066e6f69068315599f393b723346eb061589f30e6262803
15	1	373	\\x6be03cf60c563808c28e5a82ffc1f6c1469db52598dc19f0d8daf3d78a2c58ab6af9fb2822063b7ba6d85f7b1a0d8d3fc3ed6a1d8bcba442365439ca052f8d0b
16	1	7	\\x5f4f25711af47dd24d128b53b2d3d6aa00672dcd643b85c78bcc756056fe810c04101e452ed37477440928a08c8662d078a7ab5109c0c659ac089ad9016a2805
17	1	15	\\xe78372c868b520e639f3ae60aa0716713c1135fc844413e10b53541d102ec4a4e5b51581a1eecfecfa3407ba1e86e7debe09f54b220413371c1c09a804052101
18	1	39	\\x4c21a3f3e5860f32b0a8f2e3609804314def6e3e43190f3b20410b6cb44c543cd0a115583a46096f1eb92cb5a2639362f3be29b54ce9417057354c2815aa030e
19	1	112	\\x70fd9a3a704b9df4c2a7134d44b7f117b1ce2540c0c09f4afd114146059a5a4fd1bd7e9c5d9ae19c336ba742ce47022d908582329b8334877ff880fa44036001
20	1	141	\\x2ff40d64c771caad6c8c0fabdc71a00bb2388c7714c91443117a80160d708b054e22b1853b4b282558b80be5b5cc5aab02fd0a2c2cf3e7e775c101f8d912780a
21	1	304	\\xbd81dd8bff6b1b56dcc2f0b4b17f0210f2dd550fcf63f922efffcd12ee9e5b5f81c61c604a4d43230df110cacb05df430741cfef83612e0254bdd298d4c72d0f
22	1	149	\\xcec0cf54dc1272830086cbdc98a23d251f2233f9dfcc2aa1171a11414a51d13776af3b02e7ef8c223fa1d9393e721f924167c69871f76c6af5f312a79acbd009
23	1	316	\\x8834a5ff90dd2394e7f10a2e7d2f131b1da8d1426e92b5c8e51355cc093ee74f6281b52454d3f88d8c03728ab9da5c7d5b4b7d932c41cc547218348f35a3420d
24	1	416	\\x74aa087f85f6fda2403feb0d6d88062ff96e1e4829bb17c50d84cf8e51160c928281c076c83bb68a54836dab45e1a5790bfd8903507d748da20855b779924609
25	1	30	\\x7b0b32ec993570a5f134143afc48a11ea9226a2d8130e0b2bdee9657cb3e1532ae6a99f7fe5fd855606e4af902e240f799b34870bc755323625cc914edd5700e
26	1	341	\\xd062f7824440ef20a671b4f2bc1d5596cf1ff97c87a7579144574b90cfc0df0fde5b0adcc1f01d3539fe67897d83bfeab2681f20962cda2ee65da6d4cbf3f20e
27	1	159	\\x72a55e4f142f0ce78077c4a8338f3b439bc26bd354efb20e1cf3f3ba4dae3b947c6acf72838a06727c4df8863e931e4c8b60b739c87376891c9b60a769589c0a
28	1	187	\\x877b0e05d49b6c5f19f8c777d45d096bc9ce809cefc675331b4490e7f0ea8ee0d3be4408f43932a631d9d3b122c148429282ad1c272a4d0d9f4828774cfa2808
29	1	67	\\x773d93c8c432423191a2e2ec2ccb709c4fdb3db226eee1619a2297b49b70ec3db65f984d6af0713a831bb112f4500ae3339668cbe5f66bcecef28b3608247e0d
30	1	287	\\xf3a65e70720990de0204a9ec6543f0a6cda70793eb12c3b7a1a344cdf77a3963c0ef77e77899e4bc44b758252cee0d65bef17af987b4110db375cece69dd6e0d
31	1	75	\\x2f69f4305d437b1388870b5498e49cd7df75debbba23d4faeb2edbc05d123ae142f5a77476ed085cdc0d3de4786c76d4ef2d4b98003654051042fe2c91e4400d
32	1	389	\\x19a0bc97ca71b82ce05949f481cc13ddd880e630c9568f0fa45f5c05d9c04aaea5b2f4266ff8d8d6cabb0f33cfdbfca95578f5efbe74421e7eabb0b951f9d300
33	1	193	\\xf4d7887b525d47510582f286299da4484fd361588e198f8cc0c21a922d3cdd1b6e0849f301197d15a06a671fdb60247a2bed91935115d28ba13667b09e838e01
34	1	58	\\xa5bb85c25ff8c00aa4048e9341d2e9dc520e13ca6f5cddf8104584c15cd5b175f67232d3c2f2dcee58e75fe7884fd1affc70422c73ba65db1be43c0f65277602
35	1	37	\\x03aff8c175f1e2852f591587c6e2aecf8fc72acaf801fd8abb2793aa5ae92b00b92b13b0bd80d6c72bc7697a878f631810af2697006990f81937f54f94ec7704
36	1	354	\\x9e084c3ab6fba9b5a42d5761a87b0463d977cb9bf7dabb5d87197482cd3dead388679006e67baa14f200d0428423f57609e2a18eff2b5072d46cba2f2fe0010f
37	1	65	\\x2733ca020dd9319e7f33e1cc58084ec01f943b9481dd1bc69d6f5def4826d9994d63731496479f8210499c2d2f07f2da5aecfead0047ff5311906d5ab12f0e09
38	1	221	\\xba367289242b6b06ed2aaf0a7e50e15310a31686acf6ae901a979b715602ece9f6019850ee3e939623ff755516b8316278b8356a11d913d6e780305a71fc9f02
39	1	224	\\x922e1d3a121e28762b0276aa979e42c4e05cc23977a1eaf9735bc937c4aa6864ea690c34cf00e4aa95a929ea7a8d7b8c07a5994f9628c8270a6af4153dd1c50b
40	1	236	\\x330a84e7554178ffcf9aba1559102c9f9300eda9cce523fce1d57af8ab811bba0b2ac1d7069c03aec1e0dc5dd8b4c21de7b6a17185ec730c9ec453f3e9e7880e
41	1	329	\\x61ba713d97d8d51c752faddb4e37df50dc10b0d32135587967c5890d2f088f5b275219c7e0e4a8ca475f5f04d20c58eeed40bff47bea88add43405a25c0eb806
42	1	271	\\x0b2b886005fc07f7af9ac1e7fe3b701710c96ce8b07c772e1599922369f7c15afda953d2dd2fdb49ce04243635419b13818ea02673d555eb460116be48e2dc0d
43	1	34	\\xe272284b2e273a5a46fe2a130403aa0db383b05305b9adb7ee04a01271d2a766ba62c14e65b246fbd2dd10726ecae1c5f73af8d7acd610c6ef028ee10e629b0f
44	1	311	\\x200cb9d7a5efda6a5ccec8fb10b25f30cd71874df43231ef8e707d651101f5fdc578e4f17a9c130fe11fc09f6a010e003a34173a3051949e099e014b57d55f02
45	1	19	\\x1fec306e365272b0e87ca07d57a23f4e6ba53200a2d515a2d583043a7b18c60fc67cb7fc4c182f747d89ca1738395b2c4abb41b728f664c1016d10668dccf90d
46	1	253	\\x60ddd65aaee7d143c2c3720683f565ea387a2abc104495dddf184f18642e3e7e56795d1dd97e11544edeaa2cb512dc5bee398654cddba405be1ea63207749603
47	1	239	\\x78f873447332edd0db7d7a5f977d439fd356a5cb43f2137cab3e5456af51d43edfface05d43c9f646e665c015fa855b845bb7c0f29f9affd0b507948f095b90a
48	1	243	\\x03778e756112ac65dac06b5e1a5133f939bdf955186b161e9fc5be782a16ebc19842cde5d5cef490874f50213d182d22f20a6a16efc1ea7abeaf7ace653a5b08
49	1	204	\\x3819eee2ab2e9bf4caed136ad97a812dc4c8902c129ee83d305893d4e647ef163089345671f3acf88b3f5693f5e9fee3ff42e5356c07913194c69ee7f076fc09
50	1	219	\\x21f5eb4ab01b459e76fba095606db73925800d35459445fb5c0cf0df18c6412ce360267544e2e1fb0e27fa8cc10de4fef4bae2a4b46ed7b2d53784fef59ef907
51	1	335	\\x47c7ca145e4b7270e64303a404bb8441a030a4a3539ff53b7b09d2263278aedad0b2b4f31639eb723338d0b4ab5f22210f2b67ef59fbdbd6aec57ef38c519f05
52	1	146	\\x152aff8397b1a86fb82306687d71c88609fca34df6bc4e2ffaf4465b7c9ce6dca949d30a41aaecaa40ba938e88ecdde5cee97191d53da7f8bc51c6c6d3578106
53	1	340	\\x5e11fea8e031f829367458293913602d514622a0dd1af96a48d939ef8d8a6d15d31da14d4814ec98208e623ed111cdc92ed5f59db12fc69957535a0b75285908
54	1	279	\\x4a36bdbcd11cbdac403c637788e52130aad070eb1291cc3fbfe3dfa648f34012635f6eccdafe35fa389d750d9a85ec44f204ae8ac90078f60020beab7356430b
55	1	336	\\x05bdf6663b8ccf68624dd0256e2814285862bb9469ad2652aad5bf36a8ea9a4c79447eeb8cc0d896a97ff70480d1eecf9d0a65adf999ded511956b5ffbc8e802
56	1	345	\\x3d872baca7a2a082f5252f312532930e9efac1ce706a8070a0b9cd75c06d84a39a8b5bc240bcd0811c5769b503ce50dd0da9dd91e94b512a7d37bdddbcd9f809
57	1	312	\\x697b59762181c51da0ba75ceaf0d9947ae62ef099b30cdb7a3f1ad4c48450431d9da573e79836b1ddfa9bb40a058b2b0cd9f77646f35711a0214a54c8d819c03
58	1	171	\\xe2e246c86a3933cf26d52a79a4d53040b67aa40ede701bfb2e1ffaaeb66beba0b1b31c8f625e0ba3c391e68949af36042871edd936962f1932f058cb7efec607
59	1	33	\\xb0e5f2a1dc9ef463ff9c25ad4aa4482a363901db09d3ef877e738c33cc6161a777c1e85a2299ee8434eb277694a2d676b85cfb7406c1b9e4e203fed039a2870f
60	1	208	\\x66ae399e0079377078a9b21c32c49ac97bc2c4f5da07bf5221c58d0efcaf866e9a04635914617604895e9847ada8b2964908fe1a604e11781353b67b8ea64707
61	1	101	\\x8c94d3e694096ead65816af002918cd6f6070184ca8b921a628955c075202e2dbbfcf17dcd614c17ba0217714756bd997a2953293ebe86918ecd492577a5df0f
62	1	350	\\x93bff695581a07edc484664eadd6d99c84655d6a9628ecb49989115d398c4df9ba8261ad87968098abcf2c379289db438a6c81d3c020d7ff0acc58b78afb1605
63	1	257	\\xbfbd2624626b2712dae4e7bef2ce1c22d198b23312b029bd7d0c819a53bb116302143da54fd725ca51a96112fc75a33649090fffaa562e3b9ee469044d727707
64	1	96	\\x8884bdd30c04fe314dc057b9b7bdc75cd8a8220a443e88ed1601f958514ddb2d152d741b2eb880c309b41e443e29eec1f8d23cb89d58165e06c9e92cc3a87009
65	1	259	\\x03bf519543f06ea3f6477fda60bf0f68aa13ff701fb467cceedc06fd6f8ac859128003f6598a312e55e674370981f9318cf75a878049e09007397ccda287ff05
66	1	261	\\xed4e9986a94c84784890a9314c6dde57c8b8d6c70a23e64396d665b1ca8fe786ef6135b5835230760801fcb83d868ff4367f1633c0b0f9199f443c102b5c1e0a
67	1	262	\\xdbb7508f1d10050df38a10f51bc8cea5ff31174eb9f326b6b837e1ebc8709f46b00d931d0bd220893abd6014a51ed5e3dd981e91c07a268ffe870e3e95e54e03
68	1	44	\\x6d70727b5f795dc218454a8d836b3ff9d689d8a2782d9fc94bce3026966178f975ceebf392e962d1dd5b76b2ade5b793062567409982daeba1b53af60a461809
69	1	99	\\x834c2606b9c9181054eacdb2c6d06261234deb812fab8d66ef7ac5ddcdb92e6ea26142969fd577719fe0168a76ce379161c30b72c04f117185de8bfc090fb40c
70	1	268	\\xa3502ed6ad2e26ce15a32485445a3efde06e3dca512b8a443d0dca9418f26fb18ed83070ac393ba837822ac6b51235288012e3058e9e6aacac7b942d3298720c
71	1	45	\\xd71aa1345d96afc5694ce59ef7e83c13d0d4ca7ca9dc5cbe711185a6572b2bb43efc9671bac6644d52086bf22f0d006f2e7d83ecd39bd11213683889e07c6e0e
72	1	225	\\x1e97f75bb6772c2331a293a5465792f76714ffee6bb2b503e5a14528ebe051af8726a0cac8e4faee5c6c9141ce45b49a6da6b7c77e504a2257ab379ed512bb06
73	1	57	\\xcb9684978e3becf744486b5f44b7a2dbd0364ad4a85421e65fec361fb281a9b73f3fab34082246da3a3fe0dfe9de3154d436bfa85560d5f7a9ed6bdcd17f650f
74	1	144	\\xedaf3f7ad6e374c935d3187169a91de1e30da8381ba02b5b9f1a9961537cdcd2f38f7a8428fcdb56ff09717d3db0c7da3aab4396cd22b5f6e25ffd478251c003
75	1	333	\\xa178f575d8da3c1a8cff6b93ee311ddb529084fceacb9a23fa1495fce8d0091c2bd6a6aa145c15a3a7115d6dc103783d9032bfba2e5822c28dd183d51908020a
76	1	330	\\x984485a37bb357068cbbbf87ad8c35450523e6cb4f6bed235b5a657aeef4a5dcd97b2550f0feaeeeca12654c2c784820130b96222e44e731acae4ca3b453ba09
77	1	77	\\x16664b5c4c30eb193dba0d90cda08f8d01b23a33c2d525996f66f5deb254207d0a9804bb64154bd36a2cd7e17136488f61679416d3c1baa616fe8710f0de9a03
78	1	361	\\x6552342cdb15732d90b1d60dacd78a8603ec8fec9e49795ccfcf5ac6b237907bd08174d62c3149657a060d1a3aad0e83482345981d4baee854eac2a3e57fee06
79	1	344	\\x99105814ef548de39a2bc5f118ee0276bdb3a33e0a3067c8d4d0afa85a9fb90cb3e11620b92fafb703a8e608f3b0c35089746266141acb0a6c1470e36aa0bb08
80	1	398	\\x9be8f4ee8b0495c3a77f5cc83cc7ef6aa3adc491f9b949c36070ebd8d27a17180d46af068a7bffdfb9502657a59613f2ba002dbece063c38b02a1a26f574050c
81	1	383	\\xb6c0db672571a9aefa8dc511ba2eab66e2fdcfa6b752f4e0259563dbccb5bac6d2177e77688c7986c41353e4c55095a4de5a72a7b581607bb6ad1ca4db56b201
82	1	154	\\x2c6a0c052e742aaa6d50d9848eab65e30c767b91117ab425a8bb4670ff1be3fe4259132d728b1234db76f2851241e0d6853927d79a146ac48f2f2653a89bf70d
83	1	73	\\x5af528d9a988506355a52430c457217b91222b9955459c7063afff42e166aa672331b517316ad92c7750fc4acdc777b89135fcc2897ad559b0392c408a2b0707
84	1	264	\\x181ecad268ed95397e32b1e02bf8784f17e5b26b29fd62eec713dfe02f33163f54929c795dbbc3fbcbd38171546fa1a710e9d3a77615b9af26a6b11e7a058306
85	1	240	\\xca461ca37068c75e912429fe93676bb1b0cc97912b728eb757732647a98df61f8cd6704c558a8693c8ead7f6befba4901badd6c1629f69157fafc2a802a22c0e
86	1	371	\\x5cc02d4a0a7234def7ca4e20d7946a7c642ecdcf5ec7c327713efc918622b80352af392fbcb4b696f72196d448142ecc546689c83412435114935ea9ed376108
87	1	337	\\x4d15df9492ad4636455748d502ecf6b255dabb1f5592480e4fd6bc021b91d128f3bbb0fcc8a657747a39dc3964fcd9c53b3233a420d6ce6de0c2c8385abe680d
88	1	189	\\xde75760436423bbd2f9f6a45c3521b8577f99a34727c591926030719f5bc350bdab85a2be19cd98acb8f329b4325857d49ee09a15fa5501521749e705ba1d202
89	1	256	\\xec43c2cf83bfef8c2ddb9644c50d39ebe8df52a3a6b1b05457aa3fd40755414404cab1fc5ca5de0c764df3846aab62449efff862546e34343437b96021205b09
90	1	158	\\xe1321a83dfe4f6dac659c101c6b21e4d70da7b16fc1a792e4984af2b5e0aaee56365f9f8918cc18bec3e232d468f4910d07dfd82bc70d06432225abada18d10a
91	1	205	\\xaf3da900e17f1f7be95d7c36b8b77c3462fff5ca7b6c5faed4cee98162748e3f7dc61f4c14e5880875d54adaeab798b3a9b3df74c3ed58f153247bf36d11c604
92	1	179	\\xccca137f626d6683d3192b36652d8e0777ad9dd29f7f971cbe53a7f4202ff4caa61209a57bee23cf09f421b3da332e4856b0122709dfb6bae1feddcbef050601
93	1	343	\\x2daf5b86b5ae3d60e98015bc16fc7246e36f115da89b3f8d1d37ead6ee5c448ed1d11f722ff88a92d5afe605a3764d2585c4951682de1fc49db8fabfbfd4220b
94	1	168	\\x3fe8b425e1e667b376c44a6b6f08e543f6508ad60487e351f1b038446f98526fadc6a6435a1b14ae2d410019e23ef2fbccd71eede39d30b9292aece37f0dd907
95	1	290	\\xe5cd29c170a813be31c6b6a46fd674ebe926ffd43a839946ab0ff4254aeb591145dfc5f2cfeafcf998b5d91cae661899540d0db11db10308c8f96659a5530a05
96	1	31	\\x0545e1d620b98907e0d31c3bc236cec08b97844c53a8fc494f2ca106059bcff3206d7aaab34ec47db84e0f5aa76d23bb912d5646bac850407882c64b01f5590d
97	1	353	\\x202176896e2142704515f41642847a8647cce252e1f641c00b83567b9d3b070f6f1a6993825dd20066e79c6a672bf315c2f8ceae9cc9706c6b7a03a7995afb0b
98	1	40	\\xa1f79a8af724fa69b2fc376754d43cbaa1d92163d2d0af005ed7827a9959b9ab58625c83239738327165f1bc9b1fc295e2c2c81a50097b25b64ade5517447401
99	1	145	\\x374796ade3c76f12dd282ff887f6b1daca3ff86aaaa580ce970570c66fa0fd261dc5f6c0d40c054338b1f9a97945339e6c5dfd63f0a89fd40b0603fb8b0efe0d
100	1	301	\\x64a67ee2a8d9eeffdd62bb0836a0cb269ffd05b8d4b6bb56a7162c325874390bcb2975520cccf1371cd9e00d2ea2846dff236c5643bc12c24a854790c0cd130b
101	1	424	\\xfe803fc29f12df6f5dfc15e9e1b7314b9070a431dc81b58b3ec08435c7121c5b8eb14d5a06c04dedaa9ea7142eb9581049ddb89d6e24115c339768e84b782d0a
102	1	50	\\x1d625b704c1745ab819253af83425550c93f31cb1c9e87fa9de01b631bfaf5107921e1373f04b3a7b0ed9d9ccfca60e306225eb93da200db9f33359d1caf3b0c
103	1	139	\\x1764b7ca7a6de2e513f008645a53cfc81698e2d79a55a9689dddf2d6ed9d12a6d69680d50c6e7b91f9bf27f4ceca1bf45185ebc53136c804293a2513d5c20e0c
104	1	289	\\x5e94d6b11c04914d64b673e68b72ec0a3b8a2e08bacd70bed04a026c50425a3048fec3f593568a80630d38d2c62964048dd2a60ec366ef97f7698104c7d84a03
105	1	60	\\x54fddd8731b4be1238f6627437166cfb5a2f06c0f0e1049c1b4224c06c499d448e9eed51c67ac9b969ca003e403c35c326fadd330a99aa5aa7f446e081a60d0c
106	1	387	\\xa62f39f5a15fca3aed5795253cc9caf0c22de34001135e32b2bf1b4b996c43fb31a0c58eaa0494192e03618c0b087d3559746b21d1e62323857aa0d66693d708
107	1	228	\\x8b635ebed7d6b51bec3b74ae8be3a5651e4754d4c7dca81df6298422eed256001d07e616029edca5a2ae2e6a871eb8c5148eea6532858aee01a8f12b1be4df0d
108	1	104	\\x6e65720b5954c6b73fff1779fa41f1347c9c53646761b30d5dfd00a96f34421c65da275d339526dd94ebea6eb1f89fb5a13ad525e993d3454963e13ab330360f
109	1	136	\\x42da93dee11f0d2b1e2a0ccc2d0a77fb00a2e78a1c65292aab6f543c8a0f37c9d278a3af7b7abf491f9f2362123996e3bfbdba15516293316d2a855c068c0f02
110	1	41	\\xa8554f00b257fcc5eee82539951c6d4e2d706805bfffb5f202e023bb5d08e37e5c3d238d1e328f9bdffabecb056af9c261d6659fe400e33d926ff8966d2b1702
111	1	66	\\x54d032022a141148837bf92c98fb0c7910e348a3e3de431d20f01bed293e6f7a44b10962307ccbe48306b6bec34ca5ecdf9fe198f1ab8665a9a2fb88be684100
112	1	404	\\xd8eae7856a2cde41ddcab06081f1542896774816afb71fe388a7dd7f984b25c38a253242dbac45ea379df25d1f1845519bbeb2cf98ddd88a33bb25569c93450e
113	1	342	\\xbf4c07d60299a1faee50f04eb5ac0af56358f5d92b7393e39896f810f2dd538d1134c3b79829618bda725f336234b69287861b17e546036ccb524cc9781ebc0c
114	1	178	\\xd9b718c595ddfe6afabd6a2b7e15370efb6c8e1684e07c54bd9c839ec5c23a316c70973af0c186aca915b440a0bfc6286586803f07ba6d5146b99d6d3b3a730f
115	1	314	\\x36d2af92d0c8208139d97cf8440b56f921d79c62dd4844e42bc00350bfe04a6c459c154378e46bf7c275201869d2363947ed1b08c5ca615ecd4deb454e5ebb09
116	1	317	\\x62056a65144d7d71d7a31f333a20793b286c8c2efa2bcb3fb9f6602ebd81e6bcb1134f51530b1826dd90db7266a6fa27f953ab3c240a2e261545b3a09dee1c07
117	1	237	\\x149b4a032f5ec4bae60f02e75611a0c54319ca4c11fc96e7592730f8a6a443cfb5c24889841a2986070ab63d4c3055619caaff6709122b61cca45e1d8a02c60e
118	1	263	\\x7524fc425e941cec7e0f79684d042142faac7e3de014dbbfe4c76157fde0087ddcb04b6b912dfc49b328edeb5743239c5574896afe0efa1851b0de8595ff9a08
119	1	55	\\x097b2f27167da3df6af9c043cc6b28fddc4b30868a3f0d676b28e7d1c8f24fe7208a3d6c39556782610ce71020c0a2bda7fc7606e5eec2ee26b30429c0667906
120	1	175	\\xf408388fac7dcffab83fad200c7bc871d546099ec9c6cf89d3e71b45097fe012fa61016f81adacf795df1272bc0738726c3d2e909c06d62327884e11b1863f08
121	1	242	\\xe7fcfd88fe21ce274a80573a76ba1d968117870643f03ddfe02b5796939e07705bb0b097fc92620419e24149cd03e1a9dd9383b727043f22aae41dccfeae3703
122	1	364	\\x28ed28fc64ebd91b2d643a3d98ea47f6e26a686bb03cc8ac3d3cdf04ef20089b85f3abd3e52000d63ef0fb3c601534c06a32e13d760dc6db74b7cb551a56a009
123	1	384	\\x74c4e84fb0c4dc5e3cdfbaf2b2c0ed7e378988b898e00e861ec514392acf4b792113974f33043a921aa5e2c1b52aa8826e670caab557216263d9babe19619204
124	1	315	\\xfd075d81c68a24f1efd9e8f812d8c63a5bb7ef911b0bcb20b7e0723584503ab3dd8e0b9f561e87cd4a5bbe22057016eadf773f4aa223533041f7d1c5cd2c0003
125	1	209	\\x9ea1a280efcaaa80b17fde829c66ad23905ce537079295cc4b54980c5c8c53e9d561fdaa675b55abc8f0cdd630c9871724f2ebc102689a3c65c66b2019ea6b07
126	1	328	\\x48e854fe5312adbe6e948ef249566cfb5dff3aeb7db14fdb17e4391643b248ff13457bd6a42b03b3d17d52e1ba13f21b105d7a495e45586fbc289413a5dfb204
127	1	188	\\x7703231c93138a40bc70a83a8a9f0dd84c0d21c2076b947a7418cf37385b93bb26d106ab76192f8a337e215b5bcc5d1eb98e1f359734f68d9b68cff8ee566b01
128	1	422	\\x2212f37ab57b88353a2f64992f92660b8a8e902ae798e2c56b0e63a17854e84e0a1f96ad00132f63c08391c2b72c5bfc7d3035519f90033e83c14248400d9708
129	1	48	\\x6f014c2291722476133a1d8d2c1f4d8dbc43f8a183a126e747909962fca55254448d08741030fefd3128dae54ec0b8f6a9002066147b61f1f435d5300f200a06
130	1	220	\\x6148f1e6656944eff76cbe9a3df23bd92c413d4b7b115c3dceb6680af672417bfe99b534f80b50e115e8ab29359b47b0264d566cc4b9e4285778c4f7c806a805
131	1	80	\\xa5fe7f11214d7df807e0716e155fa3fb14c574733cbf886250bb410475a5ebca830a2c891c36f8b4e7b67e7746f0182da3dd4ba5e8b1e9174cc78bb8684f970f
132	1	111	\\xed96ef740f8b1ccd0a6a36c09352ba0bc7cbe9eb7e489a6235c5c93dbb9ea766a337e1165dd9cee72a053bb93b1abb2247a898ea92b518b45e1698c28384de09
133	1	190	\\x25810fe19231314690d41e426cb7953824e33e7f4348e72abe3355edea6da19275eb41eae99d844653e5cd41f2979f5e4b360f4c64b9e4179428c3f68563030e
134	1	388	\\x4b3ae95c603447df9d0f28b2c0fcda5bbc75dbfe3aa2d4d1cc47f843315c70424ccaaf2f74060a78370bbaa62ca879899208fb13d4f58dddbdb0452473da290c
135	1	283	\\x9b177a6602fb36336f9de6c64419993a29aeac59c903376da497397e96490bc58b89825712b37f3a12d8483d3ddda03a1ffc02df26995881645cea80d017ff04
136	1	152	\\x429780c2779e823a76f6269b54a163409f1c3567527abcc320af666e039492d447b8a2ff0f8e4d6ef2820b08ad3bcb0fa0e35e5480ed0bb49394cf83279ea601
137	1	334	\\xe6060dd1e1adc3bcd46d329ac6ec1d271385d3c1f4c769b41ba6dad98d51a002b9b0913e74b0dd55bf6c8853ffe67e7cac76554c4df480b3d70b7acd542a9306
138	1	362	\\x7d5f49a3fa190bd895c20a334c5713fd3abbad5c4ad28dd452c839f10d48b65955a906eec46fcc2354142fbe86f6707c08b685c132fef4f62747d2622c8c6e08
139	1	222	\\x47bc717ab9de553e0615383dfaeb58474f186e2abfb952b2c3a8c09c3d3540190ef1313bab57fd5b21f807905808ec7234736c1cf2773f75152f843158e6c809
140	1	410	\\x054bd11f84a1f4fa3c53243663d2d532b42813144b942496880296c88f3feeb64a7c6e95236d6c678dc7e04f8923067c1b7f9e2ae2da5d716667ac8cf013b10f
141	1	297	\\x5efe14165cb8d0a57d9af0f3555c2fc05ee02a5439eff6844cf7210b96feb47b98f3fe87f336afee36408780b4f40948fcb3525d796ecb936eb5f93f82f7ad0c
142	1	69	\\x21b8383927aa9c2b7d7bda758f7fe1cc6eb9e4e402c59c561c3a581707272a5ca3d4cc5ea3b3c0e894d109b77176931254c485cd89646ed1dd2a9224903e8501
143	1	310	\\xeda45e0193c9c9eda1afe93a1d770731528cf264420ce5eada32d0b67539097eff00340db6a5fea62e45d1151825523ccb04966eda3852008e7b565d1a0ed00d
144	1	326	\\xc1bdc2c49ef801b2d397706e85d3d53217b3925c3a39b54dd0515038ddd07dd9318a88ba167a9b9d207d2720cb353336a28bd0a536cba17ff324e57206bf450b
145	1	38	\\x9716938ec0a861701af447118d41006b08ed15560b99497331faf2fd0a2fd0397d4875a3bc3ceef1356973e0ce9d84a047aac931ce3e2496a9ca9c000ed6330e
146	1	88	\\x36d5c778441e51db58e49fd4ee396ad15c1d31f8812807a8572fa73a1741e2fb8ed026ce1def7d057b714fae94b3d4c18ba55000a93f9de391f1d42e3b70ad04
147	1	114	\\x34c75559a02cd1eb882e47d1443ee93463d761dcd13a71d42b4a38950d8ba7b484151a59fe1021da88ed665e502d5360b1e0ad6b4d24f92898348b05d67d0205
148	1	397	\\xb3866f5a196a1ce65a8e0ce93661feb9665f15887715ad49808e9c51998b77af931d75ca8f43772e4311e6953480ca745063a44823a139415e0379c6c3b1100f
149	1	118	\\x1091536b7c0514526fdd91d579ef73b28372bad161a08a7cb7e985907e7cffa1d9b362cc734ea479811914570b7404e8121a4e3f702600e7839122b929b4e401
150	1	375	\\x242ff6c4ed87468f6db04a822d6a39fc4379ada56db5ea1fcad314f41f99fca8402f1a12f0c8388dfff0e7f3ec25db4389b61cc8655c9f5affeba6fc04916c0b
151	1	357	\\x22502e16984f25ee4ee89277caf8f903cf6daacf89b9aa5dad9515386f8ce067794b89531f7a0bcb9c617706e64d6eba1b1c1b4608e7512bc23d625cec330a07
152	1	6	\\xcead5a4b42cd441e9b5ccc44497e334e8fc2fd874984da3276a7c3157b68f91c6fb1b555797c9679f79107823de9a9fd3e035930becbfa552b6daadc0c4f4502
153	1	293	\\x2819b20fb26f388448a3f3f3b221b6b4cae6f1c852f221b75b155994da33317ab0a654d105b5c3f847bb91ffe934074188b5e1692eec5477e218ff69f8d48803
154	1	379	\\x121aa70e2671b8ec2ed780287a313d7928ac050de74746ad1a11fafd33fcfbd8d1df59f85f97ae945e5d28b7f930c62fbe1a6ae16e3f9e529457c24e7c739d0a
155	1	164	\\xc12a69dd4ba028b089ff8248c07038391007382f13e04a384451023f19af99e97ea30604800805a31f5a548fcd813b9a4cf245a336f442e0dda30107fc8e9c0d
156	1	79	\\x48a479d938e4e1d835ea976849b341507977491d431e832588fbe0a93fde67c5719d83cbad13ba29bbe9bfa4b212c0e31864a2bda16f645b2213e3da76c2520b
157	1	61	\\x83fdc11826e2d24aeca2e3bed4666206f908a26ffc25246c34093039473fa0de4fc883366cf9ddd18b53b9d06900772d03012d0d27f34ae29bc8b4381de22508
158	1	308	\\xa859d6bbb55b24fe378318dd6f610121ae95eecb2b9c3db0fce6c6d7d6dfe1ef4b271ce775307730754193e33b069059aa45e0fcdfb36d64ccc26af7a611e000
159	1	245	\\x7ca9d415ef7a193460fc06164ee8a51e30e47e1d9c57c5ce1153b92dc45fc96a688563edf235df312bd80c9c7ad9d7231ae251be1693664c2c9a591fed7d8f00
160	1	95	\\xc9bc4287644ce7fcdeb4397f6aee282d34064a5dee052aefffceb3b51dccef8dbfdca5b473ed7a9c26530c7a8376a8a3a6e3cbf78024ec1cbc54a1f6dada6006
161	1	59	\\xfaa2493bff86d1861ba9d0a76b43b9a587b64b0b5f64b6c68cee1fbdda9f3d243b631056156090b5d7130587ebddc688a350151d8c0efa354cb4fc5827dfe00a
162	1	176	\\xe5fc0a702d2204e2bfe0ba79b479ca054619bbd550aa7155f76cc19d25d6fa678c56c31c32077fdefed38a49b8a2b99d9fb5a9cdd7d0f01d617aca05b671070a
163	1	47	\\x283e4b52a0110315ee68a4402e27cc31ac0413b2b85a67ba83c0e3a54292e70ddbf3587a7162fe0a5e62270bbd7a62c0c28d1a41ee79d4ee42539297dbab300b
164	1	131	\\x9ef4f91b2cd77c01994f048f9e87664edb7c66cf69b9b26e066291599153f506ca82810d91ae4902979218bd8fcbaee4877f70b8583222ca1417a63364fa6f03
165	1	278	\\x007de3a1d1a138d6653f6bd1c360506ec0c84d205e47bf2fe6f351c0e50d72435cd4f804b42b2bafd79120b9601a96c5d77fe6ad889bd41e4ad1c9caa4cbb60e
166	1	27	\\x0b013d8e96b938198a75e0c862c381d56d33c272a71d962fd5fc4a9e04f03df2c0d9f4fe5cf8d3a89ec96687152d34894e9c5c07bcbd3ae927a510fd6229d10f
167	1	124	\\x925580d955a354a4e90b6f5c800fbb598c19269e7abd2098e1daf18158e511526f9781ca21d1e2025c5a35107351c6c99cb72855df37b8744cc3aa10c14b9602
168	1	2	\\xe9afdb4436abb4e78b78b41e53af1c500cee13ff1c28cbc5dc2980e337a3270b4ee888e944bd8b0e6e772ae14c9b6bc033f42477ab6d9b98544acfc3b5b56e0f
169	1	270	\\xbef82275a0e5c05c0b7882695c7792ce0b97126c153e01a2f4c8d23903ab15cca1e368fbb774b968f1ecd8771889ad5f24e86d2c1fed37288b714ac317226809
170	1	258	\\x5ccc45e3ce0584bdbdf71c7ad668a8f11c6cee0d7e422de255bd618a930abd53d0a411ce0f8e4d151d348e148386e53f77d35a6844781895d90718e9ffd75f04
171	1	231	\\x6802657c7870c43e3bbb3145da0342a13e556a02e97fbf711d8dd314c7b2cd3b28f1fecc8bb3376b0a23aeba0ad03d6933b65337fc29d7eca540ae545a3f2d00
172	1	395	\\x93446ece9a7063cafd521c8552b048e38ad0c429ac838fec629de202adce1b9cfb3d83e439a90a97b120f02dfba67c8617a3df9339c3c7aa431164d075608003
173	1	377	\\xfa40417425a583c98468519e481cc0d6c3ca559d14d703c3244ea18966a1d66b282be48b5342740314bac9b631dafad99708174ac6c0e080eabcb9c104e45d00
174	1	402	\\xe12e8b0daf536ad86fa16d86fd2e3a5727d2f205e32a97bb072b50dc68c729daee88dbac5054ba9a5526c80e9523abd454b5c5ed852b886bb704f5d3482f550c
175	1	286	\\xdbbe5175f0c3c6c9b516faca0d8476d009bd838fd0ce1014739d96d65377700fdc7f1a918884bfd0404e447714ab3720e612993f0952cc88d3f8395e5a542508
176	1	265	\\x0aefa52014fa84ad9737fbed98a32e6fcdffb127ae5dabdfbb6742fe7b80b63eed1674da73a0407735c46919d9b371aedf4da220892259f23d987a9c3e45550f
177	1	92	\\x8cbe95ded5ef15c9a6d829907c34efd5abd219c5167f8be4acd8b46181e1e4ae38d420a8c671cfb259970b3e21a5b4687373ec891082b55e3dbcd9c360e9c508
178	1	68	\\x8ffa1cb36aed104d888d9e24cb6fad4fe189a64f015dca3dafd9555e710fae51769f25ea677cc8db075c05e5db6339fa2b7feb89f9ad7d1c16eac8bd091aa908
179	1	10	\\x2c86c9659702fb77fea7b51a9bcd5801f2594c26efb8ad3ed8da787f566f7a50a66b9599a50684b41aaf21e7d3bc5547352adde6c571b797423d07b0d9025507
180	1	217	\\xb59063758abe3906fd06a0583f5dcf4bd17d3c086dce227a684f43cd4946b378e9295b8cfc8134d10e6750b45300dca6fa97892ef3e0d191622d5b2423459b0b
181	1	252	\\x7e1260542f8395ce53e95fca1951653446b0e39abfc49b97ed0c119641bf3fd6d198692744503a22b178df208660527d3894358899dcc766bae22ffa95cde707
182	1	267	\\xff90154209bab1f2e5113fd2e930776fa40b69d393aa3908fedeaefdb7b8e9e91ea513e79387c0aad7a2e8c05596874abcb25212f65d0b2cfff263e43b27ba08
183	1	346	\\x1023e26386ee8e043afcd0fd16a3ceff5c5f267cceb90d62d0470c13bad5e15c38395fc7349e24cbb53ed5b16880ef7cd9726d68fe0c89132da59d321d52ce0a
184	1	244	\\x04c14d3bd028be4aa800175554f31cb214684dc6046707627701cb551b98a82fdb6d5dc0984537db996d18c47ed3860cba17c928e78b9ef4b1ec61ca23084800
185	1	408	\\xd35cf14d5958613bfc1f2f3a7fea676274b4a1651f99e6cd20c6713f711c968c7000557a3d42921709ae070b30aea05785c93c2c0de4a2551dcb9b6376590502
186	1	201	\\xe702986b3f81347946d7d36942b249051f6f33b4d20adae78a4850b84247d98a691413eef3eddade068e9bef84fb4dbad1f70768a67f7b9a7719811e2c990108
187	1	321	\\x31e5a4abb579d86166652a946d84cff416e50946a60b9eb8f69bbed19be68c9f1017b48c9cc177757621bfd4c09ccb87fb726bf87522d516c67138afb3165704
188	1	327	\\xd6a80590bc3601c903433ab9a4ede26aecac8d4044412d13e4f49a2540876d08e57b0633c86bd470034416dd3d05cde95b2ead8e73309fe2ec29958057a6e80f
189	1	216	\\xe070d8cbe2a60fa04881c9b90eea02235a05af32a3682c3af21995c0dd19813a35df7bc78dedb7570f04721fcf64fa637b69552ab051de007973f31825f10e0b
190	1	226	\\x35e05467ae273a599c33e99f2a917ca8bee36d1136db3a129e94690e6cbf5197c94fb695408ee0c867142b266f93bf639a9c884a951efff86c71aae22b14d10a
191	1	174	\\x274f9bb29c4eafe53c876b33ad2d1a0c7c29dd700d0472d745210c74f8118d54f715a94232cdbd3e0161dac96979e2ab8edcc4e02aaa5c28d353a6ea09548a0b
192	1	87	\\xf1d4b7acea3c335adeeaab5b399f0143064c2c31f323a6a03c002b2dbc6157b5871d20ab4ab6885259450b4d3b0f8ebe3eba4fd44e9f0237de55205ebd75da00
193	1	43	\\x117c3e2296dc3e7ad7c6168a4fc1b7ae956113411203dce652dba121a75f4675416f1da85287c1b0350fdd2d38fb971aaf9ff47979f1970989d46553d5227502
194	1	185	\\xf64e544f80db750131ebe631b1ba28138ba0177fbc21764e88a8ec4112a3eff6bbf28ab79a435ca9c73d8d94015b40249db2ed22d50130dba8f19363652f3809
195	1	113	\\x9d2c38b63846afc2a1af4386beb7a02ec629fd7a35a360ffc6a0feb8ae659d39d70ca8d36da922c98126ce94579e1358d6dd43144f53e9306f2fdea37b00c70c
196	1	214	\\x92b90c5ab6f973c4ebb02f785aebd1c5b6fd6aba913210988ed87952e20517b6ef2142262b93d870f1fada8de5e8832143b974e38624c2ede4ee04b0bfd56e04
197	1	305	\\xf6cca439fe9ca399bc9c9a04a4c745e25e8184f99b43056bb77cb73df43fe4676a6c1ecac983d653cd984e03b28210dd83d8ea8d9b098d7a7ab12d75d8d42901
198	1	381	\\x332330affa65a3d4c5dee9f0df706ed004f7e53041341f67da09241c18cd7f4f5f5c8d9f94a5346775111bd7f6728ac5ffbaef081c25a83a02d2742751f1340b
199	1	52	\\xa581a568bc415b26ccf90879a377b8bb48068b5c2aefa21425210922bd6cec3c6a6cb43c9579c47c70e7cc598c2b3b5c3f9b4dac2c44b34d4f27896f1d48f403
200	1	147	\\xf364503066549a1c1e04f2e13944bea42435c8ccb1522b5f4e20ceae81b58fd61b020b54a37a15a7a5e066f50cc23f1fc88e782ffd665a55b7b2ae9dd7b98703
201	1	72	\\x2a278b5cfdf18a971b9345720100d44012d6b2cd4723f48c4ee847d6314ad94108e2638f6ac82440c1143ecb79b8f5535d0689354ba4d52b55c351967349ea06
202	1	161	\\x7bc0181903966a579b3509d5d077916703ed95bc5122bd192daa2d45ca91eb304aa3a3e4e394a6a70e8d8ab3952402549b0289d1c25cacb4afc3255d9d553202
203	1	352	\\x1d7eeb6e2f66ffe1c13854faffb75b17097f8162701e88369753f046e7a2c49eb16af0ada6dba8e91e16bc9697cbe51a6383a21565716e4e1f05f86ad7912e0d
204	1	374	\\x48cfa3d1d582f3088d1eb09ae57e2ce619255feac73abab418b6ff7b174ae9853ae7bab9d15ad37346f49115cc2141d6083e89ed46b558fdc8c013f93b6fb500
205	1	125	\\xf8af992e39212325104aac30df102536c9421f6af8eed75f060a4b7975001ad2b54dc46f3216c8b97ceb122c329a2ac92240e04fa22386f0a9e9bc3d8b9f7e09
206	1	134	\\x09264345b6e973334a079ae7dc8ff7a0f5d2d4ce12432ca2cd0088178175d40b7ceb6580786f8c3a30437ed9cd243210712dfd2f1b30d9e3a2a3225064e72f0f
207	1	196	\\x4c6a6852656300a4a3c9c05a69bd742ca97680bfd9f9d74dc2fa19e46174d5fab27f2e4eaac62b6b381a8938a6aae3d29f5077030acf22ce32a100c00486580e
208	1	107	\\xfe32d81b2101c555a33ca9bd8a69f43c711df9740e7a37227409c9f79fbf58ac768ac96dd458094c6b8db9dadd9c93bc1bc3ea9df7597d0574bea849496c3505
209	1	386	\\x73939da9d0d28c4262f8441c29845ceaa9b0f1805d1a97caa43cd722a926f8e2165d7a9d243875067f06d3263a664434af9e8c49a164a68bc3d7bb98337e7d09
210	1	14	\\x8eecd6849700e95b7b1e6aea8403a834db644b9646ae75e361ead8f776a8ecf155d276263fd33e3cd3feb76cc9b51b3d1db076c9960fdc514380e0c033fd9201
211	1	235	\\xa3424236ce55150cbace0e34071d641edb8ad72970381b2ae05bee48b53e333078e8caf1f79af6397ca21f0b72c2d183fb1142ab36a225dc53e373eac857510f
212	1	285	\\x32d840d300d006691f280fa027fec88d90574175b8fe9012e920f3254de0a3032c69b267e57f51f5d1e3ff15968cdb37c77c4fc40282cfee808368543e9ab905
213	1	23	\\x6dc19721223a96f41db97cf2e4df4c05581a5ec7ef4a3ef7a773019d51ada03a03500217e7f92581411f58b27e4983c66812f3d5871be4c0250e5ad936c9a605
214	1	137	\\xb5d141f8276ac98c7d092d10198b33ea410465d6e6f11b931a1a948d9562b663ce5eabf2493b0dcfe6705448e650e44dc23a2c5042b585ea9e951789b3b6c40e
215	1	399	\\xaf9aa509ab56d783752e06b2a28d8dc85c733c1d9e86a6a94e31345835b8e8eb3defccb7a57060184bdee4e9c45ab58544fced2049781a80fd96255e7a960800
216	1	421	\\x2db14c7b6fe5b1a6e238993df9eaf53be2ca95559fe9167c88d2279cbe8c1d2ae9ba025f95b2cd8fd8d77b91988b476a09df217620497ea9bf4e53ef39093e07
217	1	24	\\x983c39ec4cd8e10ecc93ed94d3378ef987820e4d1888a19ff8e2ea9d323ea37408387b2715102e7c65628b6702c7e89707280c67e49dbc4bcef379f0750c140c
218	1	74	\\x199a8752871943e37939dc2eeec8b9587bbc0ad9099a194aff29e64935a64d23c40bab6638f202deb8482db192448f4acecb24a581270e2e8b1e9f004b16190d
219	1	331	\\xd7f11765626a4b0d7fe0deb16719af42e3e7120d41c78e687b3a0313d4635d0dca985f72d0f2087d891fa5ddd2fdae7031adc9582a39c743bd2ef1615e4ec303
220	1	251	\\x7b7b64483f678db6c1f21f26cee61e17827ee58c87f8fea7dbc8f0dd87b64b4b1436053a6c73920cffd9a035c7712d7914a0d85a2f916fed49126c5e58a6e10a
221	1	349	\\x568fca432a53280cdf4f8165fec3ea9229a63190bdb480bba8e28851a9f2535236703e5bdc723f5964d71734f826081f61181b6325a93536599baec2dcd6460e
222	1	183	\\x31f3425dad359a9f60c2747cee515931956cf31760dca188dec77dada4e7c7d537b14776bdfdb462d3f60ffbf3319034d9dd90d8177969504d68b549f79e8806
223	1	376	\\xe848f58c61537814a4aee1b968deaa2c198ff86f8a5af121d8cec1654cdd43198b7a326e9406831982047045a10a81eccbfd9eb4b16bc8c6400fb2118c0a0b0f
224	1	199	\\x3636eaa3c30a09a69e20f296e1aa52f0f9dbb580897ae1c4ae2cd82a29a469ebc11bdf8549281fd8a7e4702c5959189358a3fe51ffe81803209128d2d37f130d
225	1	355	\\xe8734929fce36c920f313cb7317405c890d6f257536d12f86e7fd2aa25c1099bb868fd22f82d04db1314e8593aafc5be919576dd276593df4a2c834ede85b00e
226	1	200	\\x6433d2ea85f302d1ebeba0e14e88bf17fed43794abaa82bdf2b19509a32e52de3413457bb133d28305122430e2d71846f5a98a114f833a7de31ef4adf104ad06
227	1	8	\\x91dbd9bf8dc1d9c7b255c00908c6946a9ef0328bdba4d1716f471948c9749b5b8268f13a6311bd0d5baf17e20a694b46e0b261638c4f7d1e156ca969c7f85f01
228	1	170	\\x5e720eb48c900eb55ae3134646117d16a636a3f61f52599d54c2755e97ba83e2f1b6d44ca46ac39f0ddd07cd0162b68b4a4e254113b9f96a81ece62aad356503
229	1	165	\\xdb49bac7245fb46917ffd1327fe32464da801d8ab291baa14b2d3766fcf29007abe520004929ccdbd31977dc2484fcca004902d081ce71d292d28b6a268d9504
230	1	25	\\xd761e979a03253e1a76f5a0099c03f9e5a9070705e7d7e2a34d66255e7c7a051f3e7c7803375cad25b5b06f0d24bcfb899898d2b50078f1b63587f898de59808
231	1	295	\\xf71054e7d9734b824804432c69fe58433902f943c77cc975a133ed84472d316e30303d4e2374c47d841b72e8d3e4003908eca0693ced588b6f8e8bec38356d0f
232	1	12	\\xc38e754c95170e9fb4752baa0dc103bd3e3677ba2b62e881a1ade691eb52abe5f13611bc318c0b0afbe0b2e775fdac3a8a589d0e808f1d49430c82563750c20b
233	1	400	\\xc844a53ceb63271b08f61cf79e8d4f17b03a3e8f801804b2e04a0b79a6c6136c64b9d4a4a9e5ad5f099918d9d39172d8422b04a7900fdc48d911a5c79e27e50e
234	1	275	\\x3c4336ecf5d327ea93506d63e628ec64b5c31f06fe1a534a4f9a1f5a87997721f5695becb524063f266be95d1733eb1f8094b2217ed4e77feba01a5dc357910f
235	1	157	\\xc92083fce109057d0db02333b3e81cbd5bb093da6567e48f6ba49335f19828cdf14ab2f32d8affc50e8afb81a3846548a517903bebf531ebe6736bdc09a1540d
236	1	21	\\x3d4a4b766847020f7e5ef5996623ab2b8c63bdb08f9fe8af172a536e7079c7d428b84345916f3c8f99be83bfa06ada29c53ad4d85c89e281231c265d3c82230d
237	1	28	\\x90107b54a351952169b9ec09a865c605ceacf5439fa0738afda5792b51387c1e31e100d34de5da23f391708368dd70ac785373f52298a0051976b1b6e5987b03
238	1	313	\\x9a32c733b42b4011d17d20f5b8b8e7a504dd0e86f372b2a843b437b1d074bca8d9421bd00ed15c7add5868dcdb5c1b7a7ed48e591c4925a494214dccf7d22d08
239	1	356	\\x0449d592659ba3a836af23087d664e04b6590fa187201c64ef2392672ccda65a53738c67017c567d2ce0e8bbae669c74bd74a618c411a1f98668905c4934f10b
240	1	63	\\x126240d30e56434a5112723ad09e12adbb96411bb7fe0a0eb3c5d5f0abb03f1a3edf076fcb850c929e8801f0943c4999731acdbe3ae8e7276489196d9d411202
241	1	365	\\x4ab7b60163c338660cc71bb1e40f271e47f87da318b3abb1b2b50622696bb667eb6620d71f6e1983bce3b5ac6cca70ed9acbd92c726967a93bb46012c1894e00
242	1	266	\\xc1d2dc84481e287310cb526383378aea07d49ad0874f9c8f36f846b416b1c23d0aaa73c2febdbe1baedb2ff7f4a375d9159342f301ec01620845e458a1651906
243	1	71	\\xf26a566ab7d7b9de830298d82b20023e3fd0f0bfef35a297f6e5bde72deff3eb4e4b573b8bc655a735d4a76b04e52afc19f1d3d1a5889634b79e22be2433f809
244	1	130	\\x518a84e7b1d899141f6d55562bd13d870e8e8b8ea86d0e3b8b979d1d8c5edee15a83b14e27e46bc954899905807f953857a615315881d51c46c38fb15984db04
245	1	94	\\x5942e4c9586a1075285ced634689f6df4e06f6c123e58189a038c6ae8e684a75fec00e6e016022055f8cdbd38f3069576db3680f908b54231d985f7c9647170d
246	1	153	\\x09927edeab3e758b96c53e130978b414ebcb1642fe3945ddd82aa161ae9665d0ddb681970a7b0f46eab12e4248537b269c6ae945f37e390093415a327b1e540a
247	1	192	\\x0b593115fcbd950b7534f9bb7d98acbf250831286396776333f46fa053593c81d3084b842893273fccc40962dc32d0d01956fbfc8d8bf69f18ee7676365b7d00
248	1	347	\\x720ff11df631560aa2ff7b65879efbf6c2e4ed601830ebf49b732ca001d5f5a01ed4afdcc0f212d684454db99533d25462a7f6eef19b1284e8e8134cb1661b0e
249	1	84	\\x3fc8c3df70b91135c2080372f94b2b4946e259d52411f22c7c8b4fe83e616ccc778942219ed7c7e621741e1536bf4a79fbfcfa742ee34eb4a9bfae061b52ec0b
250	1	140	\\x871f6423927b4816650a10730b70cf37656c3b59257254d3a0c224be41550de1ef2dbc8814396f6767cec8b1b57b544a4369823725a42f6a132db7b46942d901
251	1	417	\\x1e952dfb26cb949b515754eb35abf50ef128c21e58cd7a52aa9980a2a349b9314604575616c802264c5286b63d77aaa89a00931171a9170bcddd4348d07b280b
252	1	162	\\x2f8ab08962e5773866007ade67ceb1cec43beb1883e5e72536a5b65d126b49cc66a0fb009142c413454702a46c754e4887cca2eb211e0ddc572faf3df5866c01
253	1	173	\\x2c73b19a8d5801ec29b4558d62de912d013b51603c0813e5833152f67f1471c2fc702125f1acd102bbd5c41133a88714c54d68cc491856f63f4894eb146c1e01
254	1	248	\\xa9132d5a6109b8f80412aad4eea6e2bb6349c6cdc5fdcd7e885bcbddb0a3edffe1b51a162a4c3d1f8a51e3c4831fe0d44ac01c3681c82c4c9ebff776f6bb6b01
255	1	151	\\x055fcc68e9ec6f68a248525b984d12083a80f55db41d054cbba812c326eac5634b0de5230b9b87a76d82d44b958570d64ff92899a9e721e58359de5936b18406
256	1	322	\\x93198a6ed327c2fcd395a7eb2d3773dc807394d9cfbb0940bd489b6b2b4de36e4cb14cfb29b96462d4a166118c033f121af8916935e14f21871f2a4eb015710b
257	1	292	\\xa03b9acb6b5846f7785e3d82f7c5fd1a16b2d0076116ba3b85290708a1356fda8d04a5d036ab345b8bb539a13f4f60b64b6deb0015a748a8ce961bb1e126760c
258	1	56	\\x780308432e59965870e27a365337434e5e6f7d83040ff0b2e645cffb6a35ccdd46a0dbb498c14166c4f58662799d11a7c477e55ecc46907e8edb00c98f41200b
259	1	309	\\x58872c7e2b9da0e07707f1fbfda710b46b41d7493fe0f984edd85b3432b03eac0e2604cc364e1d07122dad3be5c2069eea16679dfeb1283c6de61d9116e6cd0c
260	1	85	\\xb8db25d40a5f4f023f015cfdf6f82bed9ae101671c30035829b04b9687d8e52fdc6c24e5c508fca5e74272b07713b41a9c75c44b0fba711c15f2be447917a20b
261	1	102	\\x75959b74c9e96ad7c95d259dd93300605ace7ee840435b63cbbb687bf6a44c48b922c577dd88d54f6384868bf2b7c3bd4bcb549f6ff77d08d8822eee12645506
262	1	394	\\x4dd954298b08ff24e1e58a69f40b4777401f8b65cad0f41329b7b9f4dddabf4776294dfca07dbefa780390ef1200b3b643650173ebf1a6b9ffe60de9fc73fc07
263	1	412	\\x8ea146e9dba674957de2802795393c19f2e092a962990ce39127b2e89fa28d17be8da9231b0cea842faf681ba409c3d4822fec4241d02c588f30457eaaf3c80f
264	1	26	\\xde5adbbe7960462a882ec3ef7ea3ceb84f9a53d929ed85463ba21daa47381931c8b66a38ae124d81b2549a7ad09632d0618072c54d99dec1e09bd80c74ee6a01
265	1	299	\\xd92ed6a64af36dc48dd18346fe1a44bbede52a318186b542a12796fb5f7058028feba2843d9738e13903278dc59d25df94528037a86297760831be7fc4acec07
266	1	385	\\xa136fc2213935adb8f8c2f03fa008d54edfaafd25c51b718a1955199e80b9f5df8b661edd16b2cf110bc73ccbf0ab55ae775ff4955902209f3d6ac51a88c6200
267	1	325	\\xb4e1b24bf4f4086197bca4487a1b2a59185d307404b196d794a800e1c32f11b7e7700c59b6e1cfc2cf85ebef8f4ae6c3764169b04fee7eb5a51907f49ea9cf04
268	1	393	\\x915b2a4e1bfd193863d75991441d7bafedeaabe6ca1766b534fe5c93ee0c81419580820fd93636d0369016ee9960e2ebe2ce1739115b582c355db1ee8b886c0f
269	1	194	\\x363345aaf736128c5fd6c6916a7e3db08ea7af0d318325bb2530ab06a82a7744b9e6bdc2809008c03c3388bd8803a9c8434b2cb44ee62f9c879ecd6ffe6cd709
270	1	4	\\x82830cba979f11c80e7450dba3c60b1b50a97c6f8c0306c16a7f489d7a34b150a6b0c0bd1e2a48ec68a428768fbb4c7c5fcf626e8d989ffbeff41b2905b21903
271	1	215	\\x552c43276197d29ab94fc82005bff00e395a54539869c562028f5218f21a4a955a4ed14c8d7c0ee8fcdc95eef5f6be076db31c4e9f36f4ddff57b6ed55892c0f
272	1	36	\\x4b42752f4e0c2de40811dbd6b317a0a4f1311333c3f16263a505abec4a0f31bbca8bfdc2f019ab9ff8fa546fa0a84b98e0853a4e8e3acecd6db023bcdc22cc04
273	1	13	\\xda4567694313a564fd0355234cdd49243a3da3bb8dfe1c1dd4633ccc765736f8dc44a60de18eba7a2aa889c16c2743570fec92e6ed60786124ed22052df31400
274	1	223	\\x60ca6620e154af7737f36d12128f9afbeea187608e26b33963b265e5267fa37a5d5c3d2196c584218c08f2b97d99cc60d2ad3963b5c59505f75926e609735002
275	1	103	\\x2d8402d1f1c6c2cff4eba9b1585db4130337c0983b53da03f37fe2586c3b7ac6953ed08aa1abf0e920b146b92553138ce1aefef902f65409753ba19b461f3f06
276	1	82	\\xf4a51493448b84885b22a9a9d4dfc7d0d9df1e7622584516d9b3b9e67929b9febc29a53b22b2a25c3ceb92b85648c6369ed65515b593b83bb24d8f9ae461740a
277	1	167	\\x53d70faf1ef43a868ccd9959e43a14a8d40891bed6e618d90c7408b7c7adde2d44c832eb921d635aa42cfd960ce61b51459a5a7e187203b573af26b267981508
278	1	274	\\x74bc115e4fa7628214ddb89cb1b602e051f27bd6bf8a6d52cf4b27e809c8159d03d1b6191191a70906a912753d88a8163e19cf8223c88c67c495c016ec4fe907
279	1	277	\\x9a26f460d745c0fc7ddcbdfe48849bf7cdb98c9d71aabce9e140fa5f7250d3275279be7ad01ccbd82783406b29cb20661bcd3c223d6df5f5fd11e82d10ba330e
280	1	302	\\xed73e2762a208545285780fb58268ac218e60975bfdf379711eceb514ad0899d3a6cb804df24064621a66894a47a37bc625515735e6a6ae6d4ed6cc12d0d7905
281	1	122	\\xc288c1dbbdd1f79ff7d1e2c0911b3f2617613f6d1483906f855c2497eef7b1bb60a9a125fa707d97879b63608e4f4813337e7c31eb0b8f09f4597fe6ba976309
282	1	367	\\xaab7306b0b2d2d7f577f6cb56bd90bca7c9b51d8771abf2858da87bfa53ec22941cc5f25bc51808529f7334d40cb3a8b58822564a639b369f8f4f41e4ec76405
283	1	291	\\x75ae0df7545c6e34a580316cf440c5dbe4d0c1d68cc9909b486cc79bedd0a7b886a04afd9b37ed4aa46cc91d278943711e4002cf2fcbd7e09b5285d3cf4b840a
284	1	358	\\x1a1424aac2d7ba4ffe1f67ee1423044b19f54074ef1fb45a47cf43c722a0183cbd1430b3d80a9ac7554fba184db7f0e7baa02d8d503d7e584daed8218453300b
285	1	120	\\xc826bde8cd970e7ea85531eac9dd6a8cbd237cce4daad1bfad8b4400921e4ba6f637c8bf687fbfae35d7258bc4cfaac51271c54835758fbd38c8a9275b6a3b02
286	1	5	\\x961f4f74d3d4a8654029115a69232b153d01055033109af52369774f4bf5c7e64eb97defd407d9215785abf7f91143ae7359ce098fa76d2312dba0cf72684100
287	1	180	\\x1437c86be920f99bf73181c8e14d3a297d6b0a8aa0865bfbb0955348f458d160147abf23f9e9100574b8e49acd92d8e7d5a6837a22ac53779f456f6405e6b00f
288	1	276	\\xda423d9b0afe8fe99cfe17ab6f00302b30e0906921496bfbbd96c288ed7435f6f9997c0165188bdbff1398e48203b54bc9a42fcbd70b0f684a1d4ddc0fd4f704
289	1	110	\\x1d3c940904161a6841969eadcbaac7f5bdaaee96e61c2ebe38202cf2fd0f45230a518b9d810615e75547dcba8a57c1f51047ba8004d6d43a2882343565238505
290	1	348	\\x0ab384ed9e75a6c9dc272d390c9ae7b3e23684ff116ecc2bfaca21f0b4e6e1e24286885fb8911d0b968a49d32499ad62d6a53cc1774757bcaa8cf12a512f5f04
291	1	195	\\x8af45fbdd75c49d8cb09ca305bd78dd0de3408123ac0992364c02731ab720d5553546f96cc45d735cbf606bb0b1d3bef2327eddd4060706353328bdd48f2240f
292	1	284	\\x0489ce87ad8b9c4862f299aa36aa23557a6fa8a8cc04f746a4f0b66a053c5df23a4cb49fee3800ab427216bd348a5809df596641755f2826dcf4906ee1cd3600
293	1	142	\\x99063d8c219d08d2c26da9246d9b5a2d80317eeb3fb9736dc37ebba6022de2818cf64b1d63a9a651060f5bd3c897118b1ef69cc97e05a4ce2c74892a2d7ec700
294	1	338	\\x03520cba029bbdbcec29e40430e9485d14d96f364cbc5e706fc093eacf98773c3beceaead8c37883933d96f954a1ad86d891f55254498392f360f49746bdcb07
295	1	403	\\xe43d5003146aff881d60e24f5b95894e51794a8379b349451098ade99353523cdd36aabb7a7e340da1a71058c45cf9e84c97f5897a73311df65f8315ca806705
296	1	109	\\x4fe6e44b8077626224939055fc87ab61821739f17e9310faac4a7bf13c5dff12c8b7b2ccbdc5a957b97baed0926a8c6ab9404958aa1b64047b41c0e5395af808
297	1	22	\\x55b838d19bcf852ec2ebbafc100bc898873529aa0608cad961dcf15306f05ad802ba8a1a1f80252ad0d2fda57b6eb2f04ad44c3b88b8d2ecb51e093053843906
298	1	16	\\x4f00c5420ebecadc1c63230a8ff06a0660257e6ee6d684e930c5c05ef29c75e60580b38ea7697c5bfadd9657448ac7815a5e0b59947dc48432e0bfd026ab5907
299	1	3	\\x3a85a24e4a210fa62127d3d7538ec6b21562fa1d4ba07612fc0623690e7397b74b15a1085d120898490f9e66b43b7ae72c18bc5f7e1edbe8c8ff2fda6d88a30b
300	1	419	\\x0170aade032933d6249c3400031a2e916fad083b540285c0b9c51816d0e78e9f69fd3e8ba368b36005d1a75161d6c3130b423d4110d29d80a94c824932856f01
301	1	186	\\xd61af0dab6a12f6c8a4f282341c847a9f20f04444804e008c59e8438949348201448569672e2da3f5560b62e5dc8cd7ae53424bf1b606ac9ea600326d2eb2f0e
302	1	11	\\x8d5da91ef514e88beb1eec01af84d8ff0bc98a30ff423db75d27af930b6c87f0da2c36460b0dd3a1a4cced3f3c2869bc55ffdf21d4efb0b4ce648099dfbc7007
303	1	423	\\x293d0bd25e3e23dcc63b9e1fd9d5cf57a0e2e58737e0f477c9306678d1c388d890982bf572a003f3df3e8b84328a6c730562e3809adb95141752e9e465c1c40d
304	1	227	\\x5b19296303861fe1c8736ab0e15e0cb230487fc8d08d23091921ca52de5724b1e9862c8009ed9867f083fddfd3cf91a4dce9236f11677017aff00fc9e9fb1307
305	1	172	\\x7c3d4a0c86e9593537944f3a01e4e61d2cd31aedb4903e96511b42a7a0f30f0dd0b8b39f91c723e46afece5bbe1e6d76c043ee9eaad6938801d1c3e187902904
306	1	197	\\x5ffea7e3ce55427802debcdbb5042143d25bec9a65698b0aed089f6aefa5e73b8f063d5d13dc688d38898feb41a577e706157ab7cf127e90813ffc724a97510e
307	1	1	\\x31b91cb1fa86e776469708353d658a839d2f7f892b78eaceca6f7d6b3cbb255066832e955fde20c5e1dbcb9e726843beaed00912cbfcda3ccbd9a4ac68690d0e
308	1	97	\\xd81d70f51d313bdf701a830500507386087807ca9bff13643cfefcc008964ae95bd2bae39c2b778b6f786b9d4125f709afaa3e5ce4f26e62dc862f009b3c8e00
309	1	280	\\x034f82ae007ad3eefcb52fa29c67966f82cbd3b7c95d2790a6fa081ffb4624b49132ba9057c5823aee461aa2de8c8765839735c5cf4a5e59007163e1a7115305
310	1	332	\\xbfe2f4ae1c7b6072a3daa8ec5b0e637c77ff662185ae0dd49bf58dff0c392f9a01f649b84f2cfe36982b6d9a2ca7b18d2175e50ac407c5a6e644767197daa30c
311	1	260	\\x7cada2bfd60c057d2dcf922903fbfed188b2f408a58cb75cf3716295a2c2d457bd3535bd63d5522841d2d6bb880e05c075a907e68dc1a43805c8b617c06ba706
312	1	119	\\x0cc1304f33ee49ccae30c57d4ce77be27c77b31926ea5005cfddc71620751793fa7665791fda093aef5014f9c53646ceee2e4c1f2f3bd073f52845d972597f05
313	1	392	\\xd4f21b22093ed0e43397883636e20646f5f17179feb126b881ee810676f9ea6210d8d92cdf0e77a1f194b246cf1aa2e0ac7a269ea70fde7b60f617e3ac7c120b
314	1	135	\\xe43ab347449701c634e6696f342144761a3a91e973e12cd37bbffe82d1239e4924bb8952612c52d31a4be0bdadae1066bcae27d810e41c30074c682ede71db09
315	1	123	\\x9c814d73b2146a7e3027f8eeffa014be1e6a01d58271a0b56e10db0f0bc5eed9622809c70f904e9859a7b2c65458609b101d0cf2dd94c2714392cc743bfe020e
316	1	369	\\x434aad63b286a6ee91fee7d4142f1a0ca793a78c1719f9f3dfba85a78ea30e39b923139ea6832b5ecaf4190a326eee9e750ebabb96b892c8aa94bd6edc9b9901
317	1	405	\\xef8d6c4c3819fcc616ac11e7a873bcc3c1d5ff5dfa0eb79994742057f2689c9e6dc14823a49278d08fed6db62e4560dbee331643d4681dc6cbcae84d49632a00
318	1	62	\\x2a78f7a8ab0f79f1d205a4fdf6e39d2fb4040234cf06a2569e8a45a627215e7e4cf654c3c46eae94263c6b9a3817d494a38fa82308b27e61dfb5bee350e7f70e
319	1	89	\\x266ff9081b5b69f4dc108c921b1dec90b17cac336b50c3a4e936da8c1a5e0185686bbe3aaed1d68b8b2d9369f2eb0f4151dd9a649a1a45140638a8caaa1d8608
320	1	391	\\x636e8a833d84a3217c0d59d088898259f655446ad85275c09400e65db27c0301b91ba7eb6014269bfa6c77eb379fc086167e64ef06deba801e1cc7d37b727405
321	1	155	\\x7f9537c1d60e16ae85f878b942c3042acd447f8886b1f1548328bd7ce0ea2bb1b0a883826cf8affff6d495bc1ebe5c1d4f085a2eb2f719208caca8c771d9270a
322	1	166	\\xf6c21460d5146e7692dd9d5fc8ac7545807e4a39317b37071d874658869f5e44a5245b9603da121e0ed5ec22de48f80a0a1a4bf021c58fe4400eb19e9af9a907
323	1	250	\\xa5e628a800d0c97f1c0c56ee79d3240926fc0893dcd598fd9818f31c12bce6202e8c6c53facdb0f4b816c7c2fbaf40bd05364837debd4742b2e99a4f8b919800
324	1	91	\\x435cf12bc88eb65cd595ae2a57ef212d2ad83912796cf954d30644bf526da82a898506e9a2456ab4665fac18101deadc39fa91b12d6499024c2f488bf11d1d0a
325	1	117	\\xc9a6e26af19f3d557ec5afcf618e7e0beb1287a0e8340ac6be71e15d6187556221577f6de38a397ded9b3e99b17d1cb087c444dba688bd90447d065f964cfd03
326	1	370	\\x2a15f4b252e2a18f081b2d45fd193de1217077221c3a77ea409d6dc8c6ced29f3df15d6aee04b5fe6fe63f5512bd0f00407a20647cebafbab6ad6f0513c10f06
327	1	191	\\x636df955e1935555a5a05cfa3ac76b0269b1fd26b16bad4899c1250f60d26497c52fd30f523e8275108340e17fae61e909a0c00746f96c342e32a3accfc4bb0d
328	1	282	\\xc159ffca4a06165134eabee332c43f99ef652c9441176e122abaf6d92ec8ef1e614baaf056b2faea4a5fe850982dcb7555f421e7cf09eaa96213bad510a0ee08
329	1	35	\\x6c01e0c8cdcb09471cd1ce4402012b867db1fac44c4f229fac0f593ad17dada1cc92a1f1b97da596a97dd806e3f3f6b02c24922b65cab27881c16349e5208e0a
330	1	78	\\x2573858ea9d2c0c5b11c0814b665b4c99f63dabd9751bb6c2bf0cadf2b2d82e680c495d4a9dbfbce038836bc3b62b76c9c96d14ffc9da392a306cfa7ee9ee50c
331	1	156	\\x3920676c2d98ddc2e13ed1228905fd4bf4b03677a3222d89fcb269c3ddbeaa8d9e1cb5253e79a0e501cd242c8d9d3b8f0e23fedd6f17d1130e00ea2bb83d3c0b
332	1	108	\\xf3024158a456aba832d5f235638b8b995c179b8bfaa9ecfd6544da39a212d8cd75f64937bd70114fbcb06c5d2b351ff9c34f9e9358d9a1a61543fd1410f9cb09
333	1	324	\\xbc22fb8af3c8c63898cfa1623b2faeec8a884e1b6ec79d14b5698e1011d113f191fddb39ecfd8551c053aec77f997b6e6abbd3bc4579b4b7f3a96389b84ed40f
334	1	93	\\x55d50ff9c8736064bdd4692a34899cf5394b5e3ecf6bbdfdb1537aa22aebe2ba8f1a045fd2fe39e0d47b1a24182f38fc41fad99f3fbabb0a213594115891f207
335	1	106	\\x2be87ff0e84b3194cce82a1ac040fa5b3cb2067dfde882814eb462170ddc044d6efaf951ec2063191bf4afc76aca16385fdbe2ef24d33dc939a800a79e479a0c
336	1	323	\\x084dfbbcc82af87424e585331d314317514fbfa01f6abc37e1218bdbc525538449dc4ca73e35c1db13c805ce157b6506eadc812a3cd9827781a670e86ea5af0a
337	1	288	\\x61d0210da7a2f1f97efb42deee351121725fdeaa3ea3e3d5d9f5c29c3e24d3b9e0bd7fb8e08391790007091704d335913aa77c1d913cebb5bdba93aff38fff04
338	1	115	\\x5fbd98f6081434fa3dd04942298c2ae3947c0da1a53ce08664152def9eaad721af3ef45d412698241d2801aa8ab35b89812d98a1ef58999b795502e77393bd08
339	1	51	\\x43633589a9ec6067c97440c5d2ad9e4cf617ebfb2cb751cdc42a24b280f8631393e107c5fd4a7dc87f353b33218b2413839ae471aad005123f8002ae1698a306
340	1	49	\\x5502cb3835ee8c2413b245495818187de39b440a9482c03c83f953d8617bf2cda5cff45ee36069209db7f7557033188da72b347db9aedf9595d6cdc302f47202
341	1	129	\\x41de9a5e9fe89b871f501216dcb7b18b188d687ee0b032fe7782d23304e27302415755b772bfa87d8a8961e5971b9578de230aa1c36c1c2359829c3f4f85fa08
342	1	42	\\xf538a62f4c6c174818831a286d906a1cba74e7f69d36b6b6335a192a755254b4e8bea4447e2d731ca83911ee7c0915cd78c4da94d23844e72069ec3cd4464a08
343	1	255	\\x2d8425108d0deddc9b8c6b5dfa194326a8f0dec7ade89794bc90aea2be657abddbc0606496063c47e11b304a074502cd58712d4bb460b5b6141cd7cbbc171e02
344	1	70	\\xf75bc30653f25b590b83abec5bf6f2ba2309bc67cd63b2973cfb2b9158937dd4f52478d0e7c357de5b6fe45e44e3c3d5ce665290f33cf406ecc13b643ee6f60a
345	1	249	\\xd6409300da5bcfd35698647c8563cbc931f5e957565140c38330d5d978034f42c9d3fb2d3a79a194749d2cc27a4afe1af7ac6498e33a788e67f9e5a5fc42310f
346	1	29	\\xfa215e3a0e9066f903de76364ac9a6beb9c36577728a290acb93f9c54e31de3fc983fbdf44784b59a5bc2721b1821d83dd68ae6560648de14fc595386d0f4105
347	1	206	\\x8c955a52dcf37c7a66c872558d8a17e74f0027bd2b060e0b974d186e57ae8edb8a211e6e65b78a8371fdcb6459f1558887a7ac54fab0be46912d694c2ac7dc04
348	1	366	\\xe3d49a608f225b8a794dd47b8c48774aad355fb58e8888faabbdaca68d49112e77e2169dbe8c376a3f179c9d0aa6f345fa4f6c5706c89137937bade5bdcc9108
349	1	203	\\xf6b0f510e053188301b9fea27bc85bc06200b8e82287f552bbfb7f01c3cc4ca311285a295b7fe1c3c5ee16bf09f9b15767bf65e05b68daa95aba6c23ad2a0200
350	1	414	\\x36dac6c63ffc7bc0993a3a0712367bbaaa9deacd4379530fb0010fe0a833ea8c80381a95504206a74a94210679c7da8a532199bbf5dcdfa1b88b47b4be875308
351	1	54	\\xc73497a78ccb9b64cbc26ec4b54b7598d42c26962283bbfddd53bc8649e8970ae31d96fa0bf7347c64b4613e9ba5490517138f27cce1454974578daefc072d0b
352	1	81	\\xcdf1b29072ed130766a10bd19de81f94cb3360dc8f410082c55a1c5579052e97bfd9e45c6ab44c0e5bdd9841a55089221ebbf6a9ea69f65c41ad3a0e83e21e01
353	1	294	\\x460333bdbef6090c012789818360566674fe7f4cd9cf70078098901a74f079ae1da65070613c9bb8e1e61e37d4ef2e73c6394efe5efec5c109d8d818a2563002
354	1	306	\\xaa0fcb464b59892914c374a3a9ca9fab8be88c2ab3eee747720214cb889cbfc2a9b46e093f67126f631395ca288d873c4784129f28514352d225408937757f0c
355	1	300	\\x0698c3b0d71361ad837f9cea0b828a4ded5c53c7e0ca80958de97f8474eb22ea5738a6ac83559f3820cfd671ce18c0d27c45202549dac4b983c16d14c6d8cf0e
356	1	372	\\xfe6bbcb13248402a0bc5813a05a6c6ec2d4a116879e4a50c843e373c5bafdfd82b8f56d3c840990faaa0250200c30b5b5e0b163326488ec2f72e29d9fda3cd01
357	1	303	\\x61b6d349c61746e245ab8ebba8e9cac1095c9fd23b33938c6fbbf1b1754e4bd6bf4b0fc7246e7aef205861289963759443e752675385685bc6b82a1291220600
358	1	46	\\xdde38fd5c40cbbfce822f1bc98ad4d01f460985af457a762a025cf604fa1a1a02a630177e631bfd50f072bf4b3a0afa33ec2e887b4498066352d9e5a69265305
359	1	177	\\x57f2dd09d937edd5e5a794dfb1e2feed7c97634ea59bf0ae56edb75a55b1c7a54b948365fe98163919b095ee8768eb74f3839a1a8a66fe7a2d8e9c6e64b62b00
360	1	32	\\x5d6785b2e0ec0e65dfb0213d5a3ce19f6a9ca8bb7668bda4f803d889d99e829bb653f42da52689d8588b441a4a9d50c32f86013c98deea6c60d76b2f66553900
361	1	128	\\x4ee27e1dd2f9afe7abd56d0bd44249b460e7acf7a73dfe2f9a829afec9ec16414508da75496a57a23e9d704a47b91fe7b1dcefa93a40442dc8817b36169bfc0d
362	1	396	\\x63e679411aad72138b8ebfa8e589919f47b1edd74f753a6aaaa6c854ddece3dd4c35b5061901f7be410fdb6a867ae3f9fc1752deeadcbbdaaac1119c58b5ce06
363	1	64	\\x3e4c6903813d176c4575c54e58b84dfe6ec33005520d9142f19508ffd596dd868aa5ea554e60b28ea2a83cbe9de7fa375985a81a52644983b03b6e71a9f5bb04
364	1	163	\\xee64a7a8efd52e3ee9bf2f073d292a4a799deb3971cc2258e43d0c0867ff5bf1a0117c5ac0a86779ed2021b9470e88fcaa4cad83695491d49707d855206fa803
365	1	182	\\x26a774925ec7ce549f4a1fc3ab12a07025470075d3c6c88fe50d7369e850b3d839397cbb8b45c201a517d80048bf706457ea50aadb155794ee6afe32199e420a
366	1	413	\\xa4eb27a52052d31082c163bc903cdd8d610219a8f376e6ed42915335ed5901053558372c02edab11b730d70be017ac395d738895de2d090201b35c45a2660e02
367	1	230	\\x269c78c28475dc4070c8f5a8195679d07fe058e42f74bf64f950c32f00ee4a7e617283d2c196d82469f71ed4ebf79e6b75f5aa077cd44a6ac1bdf957c834a803
368	1	100	\\xe1ec6ae94636d2522a2dd524ad2b3046ce4ea8bf052c6504a1c71d7864758766ee17449ad9e8967308262cf543c1efb2b4297e3e3ffca5e8c788300105d6d50e
369	1	116	\\x47b6541a8d781cd8b0b470452b1ea452351e8c8ab25eb261d9705c9a90a8a000c3910780cd661c63d6fd14ad718315ebb191cc702ce613e034ec7d85e6e87a00
370	1	234	\\xa6187257230b58b47932da372be15dd8faaa5de1182ef0b570991e3e4e4d4286349b22b30831982eb0d3d1244604f6d245064838713ab26526545f798589070b
371	1	126	\\xc89acf30901a673400cb67731bbfbd8be31f7111e0b5a395d4e37a344f8564b185836df47667b39e8a00c1824b0f3bf8895f13d507f4ca5c0766192995d8200c
372	1	83	\\x710f00f3cf47b2b949e2dcf092a087967f8c7540c6d809dd05d04525968c84dabf0c9d5924ce58de1eccf09077a12f24bcf9d31e4a2571039d77b74812a59808
373	1	53	\\x0b7b0964d9785496a0610679d49846bc9c7bd803758068a589eee8da2b08fe3bb183e36ca65ff6de4e1604ded894ac636c99a28454da83d94835bde705bd870c
374	1	272	\\x3e6dbaa74246f9bca761d6d1fb1825a36f46aa7412325abe98b8c2943a50949ce1f410a5dfb949692777d3bb4e226886dee7ed7c13b8892d1e2f015577f6460f
375	1	307	\\x223e974908e5466858543cef291e29ed76a223b19e6a5d81ef3fb62a49f88aaad793d082c2f342df36a6ce5390ec90adb93cc5e9c9e5d7114e7c4d3981c8b20b
376	1	409	\\x2bd5b4ba7fa46d36e5124f9178b785b80a3814b01adc46132484e95ab48a7de4d61a9bf45450889fba3d141be559c7ee7e733c6bedc8dac40f92dcdb7eefc802
377	1	420	\\x5faae6991159970f841f579e2476381f105ba34edcc5b076c74ce641d689ef1487ca83602c463d394fc278b7d3d5901901dc85ed206f9ae25000cea98a5dd40e
378	1	138	\\x1840539b9f7cddc813976c5f354fd7554dff34a777310bfe73e9989d1c55cbe830f191e0b2b43e2af5883f733171f8bd201e6bada411d0c8512f250deabe1007
379	1	298	\\xb5b832461157df6ab93d5cbba71110218841cf812778d7acd9fc1c7205b17f0ad479cb50d8012c4cf10109d631d6a7c15ba1a6b2d94ad9840c9abddc7b06000c
380	1	17	\\xc15c2a10c082d73be33693a1ed26f0e244ea6c83a93cd7357ec65f18c09a91269b82b0531bf2f4458a5f636ad616a932bed8968eb123cf234d5089d6f0979808
381	1	233	\\x60e1d4adfecacec70794e6a24ecf58c1182a980300f4837d3f10976c7e7fa18b602ca7351d3c1f1943f56e5e2403acb4980957cd17b6fe99c46509984586730b
382	1	418	\\xfa8bfba6cb9b8a7e15bacef1cc95968694926491f45fa0513eeb08ea55b5c6078a064789cd9a625ad5d1a2e84ac51690e33d5d9f06d02ac3b423dc73f45e1301
383	1	133	\\x748a4bbb33f68bebca200fa49eb043d66ab31db05a7b10c82b534336d9a35a52be5067fc7819cbf2d7f6cd2d3658096f9b4938af074b3e48015adc053df2fc0d
384	1	407	\\x9e04baaf4625018be3566c4f0dadb0a0a984eb9adf45906dcce340b52c16fa30da24db021c395583f16cafa5ec2c6bc7bbab4ffc5f523459d18054446a16ad01
385	1	169	\\xee24632adf9e3bab3665b797001078b8bf4586a3806424bf1a3a99887b23c44bf717904ef6738fc3ff75ba7f17eb5bcc96c5df51fa58ee37ebe0c95d20e18406
386	1	211	\\xb18cfe56a6d71d59efa7938b7f7ab8afbdb8bf5739ddd5984ca99e21ef1bd8d691ac7624dbccada15119844f7b09f0daf1c674799e5cddbf4dd71bcd4ba8b004
387	1	319	\\x7f84c1f5ef73b30ded379d185c575f46bfada4ca99efab9c955b3f2649c903ac552c7c3f70f427eb75da5846ee1c1b02690dc95275ff61ed9300f61ed75b0503
388	1	18	\\xdd1c99cf22549d017d5d2ed2faf549ec90314f7d5db56547e0a976595fb4e275a89737e9f0e2549da4bd76730805f2a2c412d1b13aa21f3e2dd957dd3bdff406
389	1	132	\\x28aab5deb08af85a8198e58d6cbb9dcbe3496f6f9a501f230309958b0ae801e7b3a12d5c1655612d0cc620b8c0fc9a57069094dcc31709bacfcfdf9f481fc700
390	1	351	\\x3db80f2ebbd2f62ea33f79331bd1001a441545422485f37038b10a85387bee94c6b6d2d4acb2b01e8c934fbf0c9f13fe53e48f086d659a9421ec5e205004a40f
391	1	363	\\xc3cbf071c1863c388109a7eed87ca06b60df1c289c255223fa8dd42fcb05f0d035917424fdf5926cac02c31f6da48fe727e3ce2102c35f0a1cba70d5afc67e07
392	1	390	\\xd9e953ca27b562cae439844692571d5e21644d20d014f91e5c101ebf69e034f693faae78a95cee2350f403c6290edebe288428e9b913f61a502383cb7fcfbf02
393	1	90	\\x3c2b139501cf4ad5667af893ce4e012ab68a5c99c811752d46278cf708c94d0e3f00e73b8a928945d49e79d443ab311a6f2431cc325a01abd7c60eceba129a06
394	1	401	\\x8603318bf6b908df17c4c2c9d3c8665fbfcf928536b910373b462265259b1e385b7dc9300fa252f67892605815219a24d74eb4aad22222ab5f94aebf85f7c800
395	1	121	\\x6fac0000f0167ffe582bb7a44a56ff529303db927dc62e018b567bd51ab53ba52276b54dfdee3b9c4e73cfa7f3a9d9eb8a0b6e01bfb1271fce5b42fec9862e0e
396	1	406	\\x9eb873bbcc3731070873750ea12510fff3bfd1e28a1714a9133870f9a53ea5cabae0284c348b8272a9f8a9be6f7cabf7c4b450447397d0d7d603baeb1c518600
397	1	229	\\x258ca3dab2c30bff0fd830cb6ed7ca7025be4931810ce04476976fe9652bfbe1e9fc9f81c02b56f4b7910db0b2d768f2da4953cd5ceeffeec4d4a068a1ba5b02
398	1	232	\\x885eb8088d61fbfb6a5310e6f61ca6847748315ee6d147b2f2b52d694612a7e6f5310d17f6466a2e81cacffdcdb7a87d048d0db37a664896bf0de5506470d80e
399	1	254	\\xe85d8be4132bfe388ed8a7fd6d3a5667f3d4ea418044f5fbec57a90c09e80c2323e566494087e6d39cffc6f551e742eb3b44f275031ea1db9af52d3d3733ed00
400	1	378	\\x56842b51259493ce696b40dae662015d0ce578eaed34aec23a8d03fb999428c43806798049a50d5d7af41531577a4a6f5b8673aa2fe848c78295961e8076cd08
401	1	380	\\xb117c1900907d0f9f239b8c9d26d346e0b9ef8c8abcff8cdef8b9cfbb03609528fd917a14c0223a0d49afbd3af2a8062a1586a9198f85f2203b7d3125994710a
402	1	368	\\xf2deeee2dac22378d02a27cfa529daf155773640b2faa61f23851b9797e76e2f6ebbe11d374c7838ed592325ba9c2d1a5c82d90b524ad70efdefef5de5b4c400
403	1	86	\\xac2be9856c3adfd5362697671da89131b26f44773e6b0c6ac54b38f9146eedf1f4a81b06031f1beb5fdf6fc3a188088cb3e07842cf742ff2c175c09c59c0f004
404	1	218	\\xe43be7a1ff114416a710711322b50352ba7dde53724a0a25b07fdeb85530a920efce2b63ef9d22e774378bb2bb31d10bf7dc433375ace84c153a9bf624f91204
405	1	273	\\xa8448823a411f4b62a1da5df97dbaa67d710164315505516f39dc48759ccb0da0de66c872ccb3317bb5bbbe3f1ec97100a0002ac866e17db38a9082ea65ef70e
406	1	198	\\x25fbc609ff7b9d10d2685b627e89bb8cab0fbacf1bcb6cb7adc598c1a7b3f639e535146134dda5bab93694f3a391c227e93640d0ccc24433ba8d37b941dcf908
407	1	105	\\xc19ab6df82ff4a8c8018f821fd8009c413ef9ee2defb82c5d8c047169d1127933f46835c5cd4a1eaae18f12c583e2c8b8646d8a42990f9f4ad12b455f52a5c0a
408	1	246	\\xf8388aa9fe3c761ee05564a77d8c01fadf724b007e8c2811b014adbbce65c9d1a6ab664ff283e695e4b8868ea658ed8d30ac19c205585b5808c7be7f48e06507
409	1	9	\\xa94933c469e07e004f3675ef6c7d972648a148f051589016fb45741cb431ff4ba81b72d742171f8805c41d9640a9753930ab6c54f1630378ba4a15756fecfd0f
410	1	98	\\x3639933fdd7f2303b527028df8fea3e006d8798006a59520fa9fce42699251bfa1dc0fb7c7d3bc7610a1877a7785815c8a49e4b33a975d399bfbabf59bccb20f
411	1	213	\\x276d969bc0248ee9b2bb1d83871d4476d8aa9c8c4cb754da7b2be088091760de2c296f6b5fd604027dadbce872414dc3bbc277726b4b7899c3ce4bec25997e03
412	1	20	\\xf4c34003c1dd4b6ec4984a13e1a4e2ea980c3cf36563b5fd2df0cc60952eece4a776b3f0213c7c95f5557fdbe0af379d59c2a2ad4971296c93e021eae303b40e
413	1	241	\\xa7e74c0a238b7a4d885e5b655ca1e7e5d37ecfd858bcf16fa657d0db9ee0ed2dba0eecfe6c6ce16b8ad9702132291d5bd602ae73a29ba5e811802bc6c3a5ff02
414	1	212	\\xe8ba07b2296f84a1393576b0b76ce8f94c6836fea6208e6ee87d7e49b8810639b046c7ad188141c9b528024ad99de5c1c925cdb9e7a1607864703885c4efe208
415	1	76	\\x226fc26108d150320182a732e715131462db3d6fe43bc65d7e04d6915a05b8d8732e966eb0d8e064ffabab1855667ecbfb79a922e650bd5dd0e645a0c43afe0c
416	1	411	\\xce290ff439d508af35f7348ed965292b01a7f618334157096a69068a8b4572e633c88ee334f45e1f586bee48eb70075b44a9114cc366fe1722f75c2369d87409
417	1	184	\\x81166ee9dec61087168de6b0bad216f90930f28b8fd7a5b7b170acfe7b93562b0b94b0e3661532475765db1fe428f7babe7624ce9fd14e96d8de714dc8b9a508
418	1	181	\\x69c438f9fba855a754fead065a3bd2ce8896dc383e2fc0dc541eb318ca320c826f179d0f734bc26bc013c2705805d3a9a6b0eaa574d0eff49e957eb6f0873504
419	1	415	\\x7f3ee0abf17ec1785d21b984cb863e895eee69ac519279d7f91ea8fb1a89414a3400039dc0b978c6350bed71b2ac278ec3cd14307e783e2c9494daf1376b5708
420	1	318	\\xfc008cbb3d9d7b26a21d961be9b5509009c93e3f62b0cc1c7e3cd1694a50c7f80f00144c31b797afb088f7b98dc9f64a87e20059e1ab2608d2c539dd4ad5c408
421	1	296	\\xe0c600838a3570fec4fb91590548ca79e84b155a2d0338735aa73db50853ae866fdfde17376678c939c4491228a4a5dcddad592cd1194d89beb4c72c23fc040f
422	1	127	\\xaf1b5550b1c934ebf2be19e7f92264aac4392832886f5eb10e3354803a11699537f7b99f0342a35aa4e3a953174d8ee8697558c9ec43a8c3511a04ddba0aaf0a
423	1	247	\\x7a0e15583f2946b3ab86da47e635006517360228f1e98674c37030143a37a9d738acfd00f1aa5078e2d758ce597a4af3280d041e81f8dda17b87982892d14907
424	1	269	\\x09f0441ae4ee75abfdd1b6b1ba927988c60df211a962305127664edab291aa597f9718c0bf7cfe45856782c52d595be3e7d6fa52a0bbf7e0f70781b0a81d7f07
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x72d0d8e76675bb6db5cb1faa9ea4148c92b775a09c4b1232fb6163a98557907c	TESTKUDOS Auditor	http://localhost:8083/	t	1659874096000000
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
1	\\x0238afd1a50fb749a35a16a6e32d314f0f9f697e7ea9406a7bb247a3c7caf8f781230ae01c7e0cf1f1c76cfb1435089e548cfe04b7b87914230e15c22434c7b5	1	0	\\x000000010000000000800003b97bdf5aaab7e24855599654d69f76356361c4299cd46ee8a16f5c2edc3b8872e901db7889e57a419b72286c8736f38598a91d6cf335d815ffbd776cc08ba7d40e6f6cce3e8270610118e17e827cc105e6f57c0652eb4b40155564c1c8a3f6085e5a9312744d938e2c84586405389845ad10dc57e6765016f6c3597a3701cf77010001	\\x6a3ab2ebd76f0f5def878765365284f8fb87550a51f3f5eaf868cab955f7a1660aadb6c03b19763976a7eb967ca954d47f6b8fc6d9eb3a088814b284afea1204	1668337090000000	1668941890000000	1732013890000000	1826621890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x04f84a6a8830f9428790e635a8dec20a07d48cbced75470f261f474411da25192f5769a8639103a26e1e88aae1a160e28d3ba0e67409458ec61a71af5d3079c0	1	0	\\x000000010000000000800003c0b89c7703a63e54bf91a37ac7e45eb3a2225afefdf7edb5707b7c0307f7114431271eb8fe78fe5644157604b7ddee9633d331b456bbc512d083df271912483ea0f7a3ea6c3939716519dbef1cb0ec00fac7fa6c2be882e6ed297d12fb98c6d73777cc70e62b68942c52c55e25236ff546b4b88ee18954b990b322ccd134446f010001	\\x0c01555f961c57e88802e31fb3af82202c1a9ba168b7f63a4fcd37084d4c343b0716ea1769c469835d50d7467b920e7d825cdf27aa9c96883818e32b2f32f908	1679218090000000	1679822890000000	1742894890000000	1837502890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
3	\\x0ee079dec1915c619c79a8d7f0c9f78f3bad6e9b40841b86f9b8cb9e925de5ea075e55a5132299d967964e534a4e7d0cdfdbe9fa7b92fd6e47d6c1e4320ce039	1	0	\\x000000010000000000800003d6b777ffec062b67b61cf380f9732d816c810c1d495ce7ca2b96e71091e4c3d5fe7a2f80fc539b4e0b431e9cc1ce8a8d012946ca074b403b267175c138cf9d323305056b2e84508057ed9a16e6beb188d356e7b42cb06fe5d60980d985d0a03d23ae5045781c85a1b509bcd7283cd4c44b67e95c4c52bdf830cf8679d97f78f5010001	\\xd1574a42e0a70790e431266d3900c8118cace21d7dca90343ed83cf16992da0a359568cf75746f0be4a3d3a7ab9d5091e99b7d24f01e1ab9a15e92356d821e0f	1668941590000000	1669546390000000	1732618390000000	1827226390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x160c4ea1af9c8fa0a02781f53dcb6ce7cbb333978707bc591c16c17ebffc82ceee1c2926a65815e14de3deb9f0b13a808587e8ac4fd09b8744d70a12179f94b9	1	0	\\x000000010000000000800003e92d6d5cbf2f8d6e59f813f6367f93cfe81c1a0cdd43a9fc58db263b207ae23f5a1452c35b3e61290509a84e8229d41e4df21bba28198644297c8114539db6e6c6f6cf710ae110273ce196d00eeef926d29f46bbdca9f0488b88f0b64cc383e3034108488a4f0b895c8cde6174cb6639fa32fb0d9420ab633b96a31724507071010001	\\x3141e9cde025d0bd4273be6c3150363d3e69f5e88f91b67fdbffb5fddabb2c93e535117103e058ffaf197cd097b7d1ea6760b40c3a25501e7d5365df5f52920d	1671359590000000	1671964390000000	1735036390000000	1829644390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x1a5061e136bfc8e6b771de25bb05796cc5623b3170d13a41411cd60d165757f925ad9d9f159a3df2b8eaea17ff8038f6b38a4414d6262f6f7c5f8ffb30e7f32b	1	0	\\x000000010000000000800003dfcdd1cd834f7b7a144f661400676b6377ffdc194ab7f91a7a3e99272dc9ddbd4ca3c2ca8f04f5d397c46e1ae385a7fafcbb11553f43e062ca13c53f6d663393d3989bfde8323e6cad68ad486edab4b6469a584e7060d5aa1abd25af76083959596946cfb5000d87d8871a33b4e4c6192a916d2ef9e67f4db3345ea4c8578681010001	\\x2524fb96270ca2863859d093e8b72523fb9df77fe2bcd275ebe367bd536ce98838c9803651ecee4d5a4c145ab17af2ec95605866efa4436d30c1a5c7af60fc05	1670150590000000	1670755390000000	1733827390000000	1828435390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x1eb0be396684f883d19fb1e8bedc23b971cd1a8e8703bfd231d7b2256ceb0c7ef6a852b741d7b69c0138f2e887d367c897847c03a965cc4743406cc3e6fc3ed5	1	0	\\x000000010000000000800003d0b0f9c794781ca65b3fc09caed4fc565fde274db77198cbc287b3f3bb9dcd1cca1f4d9219b315834a7c8972296407de13c3146e4bcacb9dc2ca7a46f3eb572eb545c7efb764ccf294e5a4c6291d7affc15eb85cdffc83c239360457d8a39c9acefcb30ccd078b9f4ec73b5da96f0ffbc3796f0520b78bd88636c22aaeb663cb010001	\\xbbbb81b9f6383257916a76681300dbb1db7d3b96c2e1ef38340c61b78a04ba79506f6e4949ee13203622f8322d3ce00b65da3cab8cb4c081b8db188319eb3e06	1680427090000000	1681031890000000	1744103890000000	1838711890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x204024b87d3df58811b82f9e9bf1c7c5dad40070a0e6435f6735a94a6da0bda49a73eae85d93ff9cee0be392c998da40a344dfb9d9b76f0f674f8ce5b71d2b20	1	0	\\x000000010000000000800003ce75cabaa2d8720ad8f63dcd1159b856a078703ee0c7c7599998bd558460b91ce0a289f915343599f3e222a2cd886062b3aa434dc31f1b297075bf47aa4d86c2f92ca34f6c12206b5d72813afe961ab1a84028a2b7bc4f42c92fd21442f7c474dc6a089b8836d562628bf7c5dd998cabe5bc5df805fbf15e6d41b8ab0e827df9010001	\\xab8d482d647fc3e1f746e6605632f16272cc9699fdbd081b48b3666f07ee4ed7e37e69068389e1fb1fa755ce96e70c3ee92ef74c742184faa818a016510a2e01	1690703590000000	1691308390000000	1754380390000000	1848988390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x21f8ed230bc9944f23d62eb19a861656472e0559654c0af63fa859116e33ffb2d186bb9b172577c0aedfa5b8bc76e07dc346e8f48896bd90467a698485b0e263	1	0	\\x000000010000000000800003a40f2c6717307d668497ed8e7fbf65eb885f7585f4210ea6528e8b9af5403cfaea25043935f7ad69738bdeefa907661487264e62a34708c9dcc03a7767154bd7ce8fe2db187616ec922552e574d5725d8ed81730f2e6852b7d08b55e932e2fb0329a86143dc1a3f0b4016b12923c0846dbba734328cc7a734a1e3746322aa1b3010001	\\xfc4f6879bdb1d6495b3d48a56b0ab2d8a496b925e34039d01cfc22e5c80be11d51b8091d9f89116a03448dd2239ae10d8a02d65cad0db29739d6264330df9d08	1674382090000000	1674986890000000	1738058890000000	1832666890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x2214d30a10c7aba112aeca0b171d18590dfd7ef79b4ed8911d71de78736450ea4e08a1311f2e5a53df8c0f8da32491dfaea5073947443cd3ed802e62c7dcaf14	1	0	\\x000000010000000000800003a87e529f6b25c4afd6d5bc18c4e8e6ac76d7b29d17b96491bdf135f684e76184b132e7bfbe1c6ecf1e0fbc24afecd0e847d502bc7b085ac94fa66680bd4fc529fba7a41f6afa8504d9e103e12a5e385789cfe91dc95fbc5b4b02406dbaff0209d9e17bc234e7863eccc0a4171c77ec0d4deedbb8e888aa3e6bfdac4e2f8ad497010001	\\xa0b9a10330d85854b6919c498ee0a96cb4b95f8a9b09ef49177d4539551a8edefc4adfe7cb8fa11bc147abcce0a91a19cad8e7e5f63a21ab9e36fedcd52dce0c	1660478590000000	1661083390000000	1724155390000000	1818763390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x25140811d1297f4f74f1a1109c71c623b1a48461098af495418e5d2847ec75c2c6a709e81d46404a0e2d54995b77765c734ffa9c121dd34296b6b72fa3df0928	1	0	\\x0000000100000000008000039b0c7c8bce56fcedb6fdf73b5fcf68ce2b9d3b1438fd57d9ee04794fb43c01f8b08d5f03b4a718775ceca9d69bcaa33f944c4a29d7b106ddd8d99e4b632800a002a685e8ae716bed7d5547b5d1fb3d67d33aef2fe8a63557d105f9805a4f9ece5cdf0d3fc9b171d1e3152854623cf7fa32fe753c8c3c8c8e1141963c3f25f2e7010001	\\xa4e6ee7a1b1cfa2191054f25e84680d3db58586c347e6ae5a1f3ea126707ef00f6ee38fa00f288d029ee7bdda2dc442738892e224f0f4445a6f7b41f94e34809	1678009090000000	1678613890000000	1741685890000000	1836293890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
11	\\x2698eed02d44996061fd2d0d314f5e40ed1b7514813f6cb475114345fd9100116efdb8be57cd1e71f151e76d43cfd8cb0917163f2d0657f2a52fc626ed9bc6bf	1	0	\\x000000010000000000800003b93bef3ba7e3418f7fc4ef7facb6e1b162e4d1deab8a954f3bef2531faad399555e7566f8684228fece06193ea37e2c3f0060ba1c54d0fa9aa691d98866ce3de193d03d60346caaabcdd04924a7ae1c5301a8ea44787b3c629f667f8160175ae695209ddd7938d380712d1514b443a655dab274a3e797b0ddf10118050ff463d010001	\\xd323f7625093c6be2d6d677d638a90682cad50a84bcc7252922cd138a697a97be95c9d0d522569b0d533e0702ea886a57eb50f417ccbe774d9206e7a369c7801	1668941590000000	1669546390000000	1732618390000000	1827226390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
12	\\x27942d807d69fb9c67cca705c39a4da7c04c22e16a0fe3c30b0c42cc0a65993f3f71b6711b4aacdd87bce7dbb9acca30e70f6b2ba923e4f07601843b908cf5df	1	0	\\x000000010000000000800003df10a49ba4cc6d62a160f66c7660e07663f0566ef8ec24605c589488a4143edeb5e776f95ea3c99abc9813a05014893cce68959a7a7096b985034568a4ae7c67b1fa808dcb5330f2c6506469ad1d1d7a250dfcd0cefc52d1260436727bb49318f1864680d8d3c7b4b76d2a401d0b93112395bacb8c8fae6e2025d256d9b2a7e9010001	\\x243d4eac45517016075432607c6ad45f6ab1e55c54ab5d2798604e07f5544f8b294aee7773a46e9353b8d553c050ea67295618fd4e75e00fa4225c4daccf2403	1674382090000000	1674986890000000	1738058890000000	1832666890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
13	\\x2868a3db8cebe514f68bf107750bd2cd9dfe26ab8d89b7b5902ec81fb91c80a85ffe507425f2b01159d0719f277c99bfca63dcfc1ead0bf957635535f8fc82fe	1	0	\\x000000010000000000800003cb9cd409e2843512f581a5b19b1b887e5221f7fe8d1e898456dd116297b591c0473ba6c827448cfbd043531e8dd02bcc2129908a045f7e3d36ecd9afb73054cce06430316f116e745ba13510b0863e4cc9eeef8725e0b18e38c7eb2b78f5b27c747b9957607d5a0312387bac54b782555673ace3be11243bbca40eafb25c5049010001	\\xe3236419a9b4a7ecbfce9762b9932167b7cad2334ecbc75e8a09b9c6bea1fd590eaf13a5b5dcd2b931b714d7f9ce631f9e17f2f3dcd179987d5f0d9f375c620b	1670755090000000	1671359890000000	1734431890000000	1829039890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x2b64f10bbf4b001a2cc472fabed22fd54951545ff5096a36974a220494da8ac7c460597a2aa89304fbf45c081c2a4b520db8e1a530ce6c471f6a59dab76303eb	1	0	\\x000000010000000000800003b59af639e9023cb8d156fbb5ca0b5992e404dfea2c744e413da542676ed7e26cd38bb92ee073c5627493b52bae400435f9b053f54e8b4ac53d8b89ebc57ba86701056137b5937bbeff83df75fdf07d4f968bea6d4db3a911df82d83db4789c4fb76f26939461cb5b631272b3f00daeb52b21b639bdd3f293ce8d96e05f2a0c03010001	\\xfac0c825c4a82fa87621c29e954234fee6991aa3d8131a38e1890acd5b8dac0c4a9e928d523e4f1e63566623cc4e0255a54c21c5d3267e48a776f263054c8305	1675591090000000	1676195890000000	1739267890000000	1833875890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x35d828c892025c3859d3197a139f792237c9d5c09fd1e1d1c8e631bf1aabc0d9dd42dbaea0a9ea13d539dac2f2b2021ca26bbde4abdc8e9cc9126e0cc876e72d	1	0	\\x000000010000000000800003c47be8b07e38d83f5d739234c39c788d2cfb0e6a37c4983c68af9e88db4a849f8c8de130ebbbff8b320c5a11d7fee2389af3cc134bcdbc6b1ddecbc10bfd146256e7141dd55b602265342d7a38789bc542aef5673d87dbdb59d865803b9da2369cb997f865eb147d630c0541758c09cd4cda50b25e454611843a84869f127e15010001	\\x3ee0b9e0a9a4bf025deea50adf475416e4e9df7ce8649f706609e2dddf61e6cdd664adfb5d5662499443d79e457b6b24859f1640e26d9a1c4a3728181e6f6807	1690099090000000	1690703890000000	1753775890000000	1848383890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
16	\\x365ca3f62c0ceead9b4be5d726392a55fae6317d3a9eef55c54d59f915c893a3f2c625073fb4015ba01b365947fd21d8bee0af46e14f084d9aad56e53edb9259	1	0	\\x000000010000000000800003c866ac2654d3b19dd4b3ff0ee5b0f4cc225000ee3f70ca47e5a7e3255fbc081c363bf88f23da74e3d0d954d8a3ab2b3c0df342eaa5f1855bf52a04742cb779aeb6511dbbcd31c69b7796572d149de96b1ba1110c47322d57226c744a6dd16353be43a79f3db6ffee9681ee0106524575eb0401142712a20adf0738c5be4abf9b010001	\\x49d3c01615fdb2d7188deab73d41a52fa468ee7066c47d4d50e155e2d040bc413b8ff186f46a7bd5c5bad6caa141a7bb9bd0ae13fbb8a0a65d8270bad04faf02	1668941590000000	1669546390000000	1732618390000000	1827226390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x3750f7f8c76fd2124f398005c8bd3c15205ad603892f10f89d86654122ddca6fade2a8f5c8c979244e9bfb983f0ed4228fad7afcea98be7c945a14b052246aa2	1	0	\\x000000010000000000800003a9d51507b0ab2a232873ad4e3cbacde221602ab3281258e685ac3b163a88095533ba2f2968a95aa8bdc1af1dc4970b96492117cb1f3a0ada3dfa2a86c5d0420dd62815d7449dece7567763a701566b9021fe23e700f6fd8ba69acf8bd99e5c568a69b3e576c42c9bb94614deb576fd17d6014369ebe866834121aaebc466ce77010001	\\xf2f36116dc7d545ff9e9a68cb6442bae265d75ab194ba388c768582e93557f4ff16bdacf67a32517bef037d8334ba7cda66f8f72776204ac165faed04da3840d	1662896590000000	1663501390000000	1726573390000000	1821181390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x37900a72edadca1ae8b44581f23bf3162f2191952d5e8c3177fa9c1c8b616b7322542b5a4e13f14aca3a7b393f6015e386cfbda664965c5279b8ae276461f17b	1	0	\\x0000000100000000008000039d2b2378cfdbb10df8c8009d8335a1ca13a9472a3e4df9b6a62a37597b504ebf5e06677ce163244fe5000ada78ad27dc102dca6cd04a1f10a264dcc5f0f1aaf85096262bf60e212f6c1622d9a6628328c97845db960fa1fbadbd292933e658fea63593b8a4519ded756728bd5ef7ee799bf35c6f278e6142b604497369d7cba1010001	\\x3dfdcf943b11e6a42d732e617f3230040c6670852e3d899af0239cf3599d5ec3e83cf53a2e4b0b7500079a36f65026f1ac318d7879c60c184c864e76cca2840d	1662292090000000	1662896890000000	1725968890000000	1820576890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x398c503ebac8101cd5bf7d27f11f18f13a81d47e8235ee499a512f235b3b6e24c546dd070bbe0b21d8ec1cda37e0a6fbc74a733cbb3c8d74286ebb844dd96042	1	0	\\x0000000100000000008000039c5934e5e2567ae57c3b8c43ad645c2dd8a3161b4d89b82e733940b4db529ca5e1b6f116414b806179a2b7f54be3222c6afa9ea0ee8ab9fca717c80b8ef0296f0cbf8978ae0753feab3f5cca547ae73ae48e1013231f86f2c901855981f8ee5afdef76d3d1ecab5d41b6a7d8c68482830ba0b323a0444b3a609bacc43b8cd6b9010001	\\x9e97c18f3727c9c893feb2d624f2e7abfd7fe757c16580585a3bb22c61b40adda657cd14240b8f57015ccab58a3b26f49486964b586fa2d7e8774cde91e7f50c	1688285590000000	1688890390000000	1751962390000000	1846570390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x395410f51c38d1cef564817d4917d383bf74335a6dd27f0e93bd562c7b0473053ee55f5ecb59cce50d4cb2ecc5ba7c1f9d8470f054d1a8bee09e7f3a687754a9	1	0	\\x000000010000000000800003e60070ebf874e0f09d2f7c27a743367a71d374b1ef9e521f72602c1b710f4135250ec95db3afa09d8ce56e602ed4d9fcadd9eb85932ff6f9ff1c4c1ea44ed7522b23d654d88508b0787e11751eb2b205bbeac97ce000eae2eb0b29b0c377adad4cdd5e9f54f74c36251864fad4c5c3e887a9b0534a73bb2995a4f0850dc1533d010001	\\x3fa0f214cdf3a9fecee0e217d6a6b4147c8c83b191f4da0a3900eada6efa9fe98a223709c4c0b5d3708c228167ff302cbacac95d5e8ff8e8d505ed49fa1ccb00	1660478590000000	1661083390000000	1724155390000000	1818763390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
21	\\x3b20af004a160e76f9d1b0f1bcef7f61059ba770aa5f5f95e6b73fa5897cb0d996b57f33a3decb5b15ad70384ee3eece64edacc96c239c1a4650bcf645200094	1	0	\\x000000010000000000800003c09500726d5a56ff293773963fce29ca05cb5034f64bdb642011154b9458c0ba014885dd5414aaef2fb7e0b998ed74bf6f22808d4efeb59e8c82257cd7405e1ba8f04fc662186b8cef89b6db868e2d988f26c2adb98f40f3cc5505e5404d5590c5d0b8b6175a5b36d75f5aa1ffafdf4d2a05974006600d20f8cac51d01e03933010001	\\x8b5d76709506880622c42f0d7f2555af7989b2f86ecf0677f40d6ebda6340965c6efa1050f9c62a69f342c16fb1e239df158c3630f0e44ad26c90f91f197890f	1673777590000000	1674382390000000	1737454390000000	1832062390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x3da80d85e8b896b98686bc23c22cbecd3b06a06b58000aad0b17344307414d451f23f2db73a91992d0074f6f7ae01ddff7d3af552ceb545fdcc0f66058c3aaf9	1	0	\\x000000010000000000800003cc726b4e550fa4adbee05830c270c4d7da4b1243f5013870a4d77c83773fc18471a29fa75be14c2a7fb21b4f7445923cb7138ff97b581071664724958b0c6bbdfd7d10e6a7f106a0966321906caa40e55abeb84d111d19b5239547e5304874edb7af6d115d1c3dae5d3f5489624adb9f369dc38fc2500d7b6b63a1e5bcb47619010001	\\x24964e2aeeab7778d6b7ca2e7dab90d203b2b9b56e397858151729a476138918227814108c3ad0c4eaac60546a6a1c724ce6d9aea91ce8df1605b1e3cfd5930e	1668941590000000	1669546390000000	1732618390000000	1827226390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x4084d07731f73c37970c28df98616923fe12be5dba1007c754273810dec75218cb7e0f50c666aaff849351ae4fedad6bae3d7b17093fb3136a4c063829a4a3b4	1	0	\\x000000010000000000800003c6f2398af0ea2abe149e462b216eae1075d43acef2c074b37f51c3ab350faa391fe05526941da11f786864e5ce1b429ac5bc92c6e50ee5066ac38b0df8476e7b3ab1d729b142847a644559f06775791a2b146ec5b17f05317cf2a50e4f59c9a47c24314ac05e831c1a03ca2b9e9f6effb965898d6e8279d6df55394b2db74f4d010001	\\x8463968ac611ebdfde2ee03e2197ac9ba9284a68b3e47fb28c284b5846dc87dd067cc8467bc87098566c2b9c1d16549866e1cd8899185b621bd4a399ac565503	1675591090000000	1676195890000000	1739267890000000	1833875890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x411cc3b6a1bb35dc33dd67224e9bdbcab7fcf319984b64a17862e3109f21bf1bcd2c631e7a4b6635a86d3911d8313d12411973715019b813a221c957e27485a9	1	0	\\x000000010000000000800003e4a0f0944a98ff18c82d09a7d5a9df0dbdd9bcf74d04c05f43459eb2bd940110dc9dfcf96773fde66f0ba6b25f13b756c2c9030e858e22e8d3c9a8bb461a72453aff59b8b2103cbd77ab0466483bf3d7f2f1b6a9e7357c660f302f2768dd4f1ec0d1da7a6d509e8db4e89787b1baf08b908e1441d5913c6c83a198de0489e793010001	\\x8c2ac146cb8be2120cf2f88d0fa0bdd6bbe9bbe42bad44dde8b4af8763c5b3d0108be142f9348414cbf51dd6eae68f602a8da8d98d1817aa2b07c7e354204502	1674986590000000	1675591390000000	1738663390000000	1833271390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x4b880e7a6bc083c2b7eeb415b61d8e7e22ff930e1b46b46ba80e955fbcfc7a6966aec97dff10104372e6f397d14c99a39271b706f846388d65128935a3e657d9	1	0	\\x000000010000000000800003b6f178bc5826451a3f4c723db2c4691f0c34dd6c7a15a96af3c2b65fc9b777aa67ba63471c96e51ba78bf9562dd51ffd03c6ab958f29d8872067fa1ecdf9d3d34f4c42270a83b35dcd427cb6c3200995c17521047bf5f2bc9737041b2380a5915816915ac2942351b386ac99b694e2003991b3ba9e7d617162593513b97ee8d7010001	\\x0c903b74d20bbd7e27b31f513e9a2d9418274d0ef7ddca38f09effe74fc914a3907ce80604d99e61b090c400b2940261b25c8653c82649a0985af99d97567d0f	1674382090000000	1674986890000000	1738058890000000	1832666890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x4be4fed2387df1eddc16cd5c1dc420b38ba55e686fc5c9222e1521ceec5d7b41557e0f6c056044252283f516b590506d7e8c5b4e0bb1a3fd7ad75b9e24af4ff7	1	0	\\x000000010000000000800003ba6285d9c3bed1aa643bc81a009ee0a6df0723732880fcaf9b1f288adac00b90c86394f20f907926c0191c034baccd45e45dc619f8a607a153661bedc10847a07421ad67e077851ce972d9ffc1983ebf33cf164cd4f555c54de0ca75381c525c24e19aee7613995aca13379069c48e91f3615b3b08e93566a84f5f6a49614d27010001	\\xcc9084c217186e32b037dd959c915d1c5c3b703cf194d930d0e76d90aca13adb333d9278ff654d79bcdd660297e0e69e4b0b80ba3ed0b5631cd62b9c81c49806	1671964090000000	1672568890000000	1735640890000000	1830248890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x4d7883cffc324cec74f02e33a2c7a8b74e4fcda5c4f869776c8e0471a47e4ce92b6542a29638159822a07b5831ed3c768ca7620735e7597e6d8e6960b077aac8	1	0	\\x000000010000000000800003cab52a9fccfd1efdb0b81408503e3a74bff28521f18fcf2f05c63a64cdbdc6c5046291656f82c847cd78470eb0076110894670f28e71ad95a8ccdad06565070520a639e4e12c75a5bf756fd6c8e3c4e6f833237ac5c1d2d9d22d90c869c29c341049367362972c54e7168051bc74917e3fb74aca6d80d86754159c83f10d1d6d010001	\\x98fd1eeee1bb7a0d5062ec1b1c41c6a914911a83598c0d8c98c3fca579feae59fc964fcd642619e2cee786d64ee1f170b908e13cfc4a293cfe50cc494b9fdd08	1679218090000000	1679822890000000	1742894890000000	1837502890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x4dd449cfb3ca54ccb1f10b4695b6ced790a7fce0f1473b75ac4991ca63f865442a2225b4fd00e2b4ac63163889ca2c33a447d6e086fed17e5697a215c6b74ce7	1	0	\\x000000010000000000800003cf940d5d7ae82b51edb879cb23325b1b8ebc542774dbe249a40ff53d4b02933bd78e0f0ae544ce9af36bf59c0bdb9b0200859d9ed20450b4c09e5bba0635d0c64387180c4ed93db117167c2cd2509c8c863f9174ab83e5fb8fb6e7bf7cf0cca59d1a77b74df5d4f988d47bd637374f5b600d96ecb92a4dddfd05d6447bede07f010001	\\x7a27a72b76d2b49f9e2e520c6dcdf4489bedf98ea72f995be2b7c8e25670ff7ec9828f4abeb7e2506784cdf059901273cc567b9df2b81a4c6d5aa5dfc6987108	1673777590000000	1674382390000000	1737454390000000	1832062390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x4e68c831fe1d3f9b8352e050213d8817df947671a797374238d6b38786179cc1f6eb85cc94a187507940c671d28d1ed41be725d715f6427dd37889471362e6b9	1	0	\\x000000010000000000800003ac80eab2f3630d3fa7e514c0369a3df1a79a7c32e299bb22a6401d1740a47d8e24a5d078569a1b53ac4fb8f2defd8eca97c9293a16c3c37e88c90606630dd079dba7895afd7fb6984054e2959c523288e286dc9b688e8582323d2a27c88d232947057ac125e85ff81f39c1cbcb6a3ccd383d3d714a46470040fa6d70a9a5fec9010001	\\x13dad66e663f8f7368e536c43f328f52717495a2fa7a5bb3a66b0d306b7ff675b678dbb46808836f1edd9335a4e39cf2132162cd4962f1a4a7eab96bd44a300f	1665314590000000	1665919390000000	1728991390000000	1823599390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
30	\\x52508304a0e35efbd691dbeb87781fe390b58801ab50ddcbd66ad976a6638125fbabd61a176e376384980a8b17834ee0ced8fa31de53a741a8dd1405465d6af4	1	0	\\x000000010000000000800003f8a798d860b227aa58a3becb2b5817d107c6d59f2a97a39288c4afd44aaa3f0443a3ebdabc0788b8bb3bbf0baf60a62cb0f664c6fe2b8ffeda89e32001ebdde9643199e876b41d86b1be0552d57b5e5d23301efdc6d06795d39f4d52e28f058c31c8e3025043fbcaca067c63e89219835f18671e7906fdc5563894c5e336391f010001	\\x54abb05503a7f62c79f81c05f9f1d45590da9b825dc0fde21c29f6241daa2e27c2ed8cf1660a68bff6c6a9e873aadea86afd07991e766bb1e534f9c9ec387e0d	1689494590000000	1690099390000000	1753171390000000	1847779390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
31	\\x55c40e3655662ba48ee5b1b42c033886f6b598a097bac97a40377aa065b7a0b665a162d393ac9ad5598d94bf882ac139fe0893698b11f8315fbd7784eb8985c7	1	0	\\x000000010000000000800003975d00c32130e0eee7aa7513ce1a492ac13ab8ef113eb1a40c2672a7bb956f36ced4791a524771c439ba73627df1829a71ab22f984d8cff5a617f8a611c8f0255c36d864dad59d3bb2e714dbaec43315fe588b3282dab75ee4a2651cd7a487ce8f95edae896f6d3f525fcec149abc27a7261694e8ef6a057cd8480c0e2868def010001	\\x3f47bd3b1ad77e13f31c499424653adfee9e598ef75a31d3f638474f913fad1f5b1b82c6470bd98a91bef5bcac135e406bf7b40a6b612cc87e36f7827a41ce08	1684658590000000	1685263390000000	1748335390000000	1842943390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
32	\\x59ac97be401e12d5d4d45d448e328ee1215c4f753ade364fcd7dba2c3a54eef2519baf7f8590f990e253b90d8be054ed59f5d918183e97f99126b15bc61c4a71	1	0	\\x000000010000000000800003b1be736050c5c9e1f2a64703647f088029615994c026d92a47fe9afebe5686746edce0c4985f63c138dfaa838cdef4ecdb65f31f590a600b0287a125433be02316095488d3c9bfb5902dbba62569c8f2cf7527ebc28a65fb4780a6bdc730e949be6ee42e4c26b082127b0a45f887b732f44f7b3f2ebe73a84773e98f4959fbfb010001	\\xa75b7703277d4c4dc4f2a6fef272b51ebb9bfd1ea60e8d47bcf22bbb1822dc3a7c9fb03f3052656c4951bc67f0b34b4c9a9195b7b873f4ab692c81dd6331d804	1664710090000000	1665314890000000	1728386890000000	1822994890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x5a0419e6788d8e068f2dd263142e3c6835e128a17d1ba6e05f702af271fdd645ccd184b95d6fdf7224db93e9a314889c39b9ed94e5bfe25a74f8f559a266df82	1	0	\\x000000010000000000800003db036999e1da2bf092aeb61b1e3958900a10598b81ee9a47bac13bc58c9675517c06a8a80966f708a6c8e2b18f5dcf66c16ae451bafaf258965cc033ce27fc0a8af335e91bef4ace1d1c03ca223f87bb4b4c282b465499a9a958268537acf16cb110d8741ffaa37b56811a43575496844e440926ee29dc3d7a9c3a9ddb1f5e8d010001	\\x562ad52d15cc8dbff85f336474fd4fa0e81dd2678cc30ace7fab83274a7016c64660e8c5577c9dd823a0180e7e4cfbfaaaf67ee4e3a25c5c4b2fb12c599bd20b	1687076590000000	1687681390000000	1750753390000000	1845361390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x5c14c55fd0fac49872a1d19d5ffdcd16bfccfe5f396045813be01c672280835c05a0b57647805f8ff15bce22e9da72dc583371a3f57b8b97247738a3fcefb1e1	1	0	\\x000000010000000000800003c90299f8fa229ba087e6c58c002aeedd51697648472de474dfe44689b9467b3655729d143d528e204f9c372a244cddb284fbebbcc7b950264284022d64a8cd7e14421197d31656d1a179dc112e91987d33a301fe270811b5234d83d48d2461c49e2f03d6897ed92d835fabf4ad64fbcb0fab07156f5a641bccf17f784f9fcd71010001	\\x6a0bc3d4fb4651894bf5bf074a783f63af34ebe14dfd866dafe078823bd815778689e242c1fb9cd584b90c6cefdb0b43a52e072f567b195f97d13ecd3bd09509	1688285590000000	1688890390000000	1751962390000000	1846570390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x5ed894e277ccace5b7a203b9cc3b868ee3e756b3a2cf49434dc6783db1fe559e223cbb23aadcb2f3476f6671f5affd79e2a790af6ecedd35aa094df68d57afe2	1	0	\\x000000010000000000800003c2170df529db5663feaff9466ddc4db9035cb033ec00279ce56b469ff00ba3d95bd36961d3a91c6f1bc1b2a0f7aff1e8cff8e6631071ad6fc36331ca7c7943b66d66f5c23bbd0384b6e2aeb01161d05a4f287bdbff50fb7265d68cb70b6789aa1d8afaa43ebe4b2b7980c9fa56ec5a965eb80e3381482021b38274e174c52611010001	\\x0c3cba72888f60ed2f3fe5cc542d4d5350ab768fdff101414b03a374546a2c66454f9751fecef268ddf0074f71e49ef865a4e3b814ec62c4c88b0e7c50dee30b	1666523590000000	1667128390000000	1730200390000000	1824808390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x6054078d606d3cffe7ecd8f61bf055b019d9aba3c387f39632f8bfd8a23331a2200b0a3205a8282a7de2f2fc70c86ba27ed1949c427cb8fa1343bd4af2f8c571	1	0	\\x000000010000000000800003e767d562f6f0dc659c0cc86796fb643836e47d8c06c34e155f62b5f2e4766a1d289b9dcafe3b748828454f60860556f8e26f79bf6e1e62b93993a4e3d746b4da94afe1fce0c90f6ff95cfd538a1fe0eb6a0bf4733c97009ba631f780594fece72514a83922a1c42f080dcd55932c42b15c399edefb39308482b46da62a048b53010001	\\x59ea4f7c0947da2874086ca0ac86c7a81e4e7658a0a74eeeb47080f7504a43847eff2f4721fcc198de97054ab60a9d5f397ac2b5962541d7fc8e68a90b282f02	1671359590000000	1671964390000000	1735036390000000	1829644390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x65e0991d0209fd559ec40000b7138fbac2c8556b2bc3e7428948214c98ec79a3a10752ecd3b5529401ba7b3fac8d934a4b4c660f38365a61a6b20d683c5bb4d6	1	0	\\x000000010000000000800003c53aecb0c68d5e84659c09156c60374594d12b341f706bc978ae8203cfcc95aa7b2b3e90136086bcfd34cd02ca0ded5fcd8b1326547a65f8897fce7f7f13923397f25ded8dc51aec13efa25d225aa07c8034c9034613cc38b8b977f17b6fc43dbcd4584a418dec91312dbbb3e1cb7f8e1662aa03ba9557b373fb012882792701010001	\\xb27d7fc2e4b36548a9c9889e91eb1d2773dfcfa5a9b0d830e3bf51efdbfa5da2787a6661ec485c3777521d6a0c9c9f8a7d75075af9a1ecdc87b3e7a3bccae601	1688890090000000	1689494890000000	1752566890000000	1847174890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x67c4524a645bf04be038a8154cbd48ad85922586fdbe6c7c1346bcec17ae30c44f2ca92ed1018f2744cd1ba0a0c10c57cb621b067de38cecf3b714a9e0c4202e	1	0	\\x000000010000000000800003dd39cb1979b94a75621aad1f219d4723fbd541cc86ce43013348ac39383c1f73473d920622cd1f2d9ecd3bc7b4f2b6f7ef39710e6dd48de59735889116814fc492b63e0fa712a3f649212223647ecd5ac58c5dc8e1da1961d198b5e6995ae4462dbbf757ea4f251a75515f83a5542f5138a9157f6c2958aff1a120b8009d3dc7010001	\\x74f6401d97cd8670fc8c85b6b7c06d03776065e08e7817fdc9ad9df3e55bb21506384cc332aa0c14bde6be1f2d63f74da1c347cdac4dbbc509c72f2fa05b1b02	1680427090000000	1681031890000000	1744103890000000	1838711890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x6ba881249c170f92817e3d5004d06b704e016e8a01f0948c9f78122f6d7da3dbfbe70d49b44134e4c36776abea74a1c77b53938b03ef998383cd7dc9c4f5db48	1	0	\\x000000010000000000800003cfed0fed0189a537547944de3eaf6c042a9f8d685aa19cbc17e49c63aa6de79308a97eadef213d3168b3db55225a75043028b76090de699baebee4b8b4972effd96f39c54a16a4e3afb94defbc3759c8c88f45fbc59bb7200ade8e1b6d2f5da6793b691225b5a7d847ca400f63f05b58b40dcc4b36e0292788506025372ac489010001	\\xafed1cefff13071db5cf7737fa2a748a7dfe61d15bc93d864714605fcc12369081873242117ef5b82f3864005bd37a0485d52ebc8f4ab6ce04cde5c81edf8a0b	1690099090000000	1690703890000000	1753775890000000	1848383890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x6d280378d259ca044c7341a80e2fb0aacc67e3d7ccf912358ce09236c4e9b57937637f59965ff70cf7f5c0516acf47a90aeb4407ba6cc54b5b53bffec3c1bf40	1	0	\\x000000010000000000800003ac545319705d1a8b024209e5c1998d6652cfb57257ae3e54bf51b1a0079b41e9234a613550db9b33d38cc6feb0c70658532f8de38d4a46b7e6eedde57de0f4746cdd8ad02023bc6565a66393f3c01069e2a82b46321d6304fd70b1e32d7e006cdf97ebc205acc9ef5a29bfe496596dc5bb5875ee8808940bd87a5d2318837637010001	\\xa8aaee267e3564c2b5ed4e1cd3314f242e427bf054c5286fa93bcfa685b7a2ba76a470fe76457ea58737b4e229b828d9b65428b4ebcfa6c79fc143ccbc94ae0f	1684054090000000	1684658890000000	1747730890000000	1842338890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x6e5c715d7134b289c9a0e62d6979137d017dfd33726420cd781e42f06e93f349399d8565adef9ba75c339d1072904de1512d7598e1092571d7bcb68e293e88fa	1	0	\\x000000010000000000800003c71089d670666e58b5af16bfc61a7f78b8aa62b6598ea7824e6f97773b35193f80fba9f5c3c8251b66c6fdf14b707f924ba52003677e004a76be835d45a3fd81fae579207b220a09c78a16c8fa6ccff74446ee0066ce86dd0d5248d08b925cc1100c58d57d05deb5186138d9cb7ab0c941e6263311fb06456d0c528c82c58d83010001	\\xc8ababd1e7e82a43cda8ecc35fb157365953466ff88f339d2383af6d329b2a6d3c5c3a08b80a37acca766a64a44d12d73c606061fdf85de848dd5b9f3822270e	1683449590000000	1684054390000000	1747126390000000	1841734390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x71b0ce3e0810309f58c86872e7d1194c6d61440f58a6afeaae76391990db83ecb2514d6d9d65936b87aec1465366f73d1c9f3bff7244d0dc2507a8ddac7014b1	1	0	\\x000000010000000000800003a6ce93f11da46d9f03bf2fd5944b7cfdc0e1765a7a6ede3d5f5bfec3f51533bc78d9f01b44ddc70f4556ff580b65547586aa7454250faf899d8d2b70d795c1b8aa665cabaeb8f4cef862da4794a784c5660050335c5627ec7c146755b558c66ae8db0bba73dff18a6e1c6fc8981930b8c6ba7c13a56de3cd25da8b70aa428c57010001	\\x28c637732f0b527a0e0f48fe5e88960dad86953485ac6a5afdc7503b230e3d8b30ef17e8297c543ba38936d59d20b37214ce1976e9eaf0431d45d8ec11706c08	1665919090000000	1666523890000000	1729595890000000	1824203890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x79b01c47dcad7ecd3dfc48cfd967020fa515e7493ac2e0020b74dd91228bb34254643bb697b7a2b4d6a7e0bcb39a70efaa595c542b7f126df9724ae83eb8d9d6	1	0	\\x000000010000000000800003a4cfee2e5a0f433db61a6f78153f7e8ca711075fb2401af807987dace55a61e5916fd68a97756d9f6cc1571c8c13a3555a6c401d8db0b5af61ed502630d74bc4505e718397badcd1f93266b705298c7059a5cb189dc65f4f2f491533b1f891148ffb0474860a2ac8422a29af5ba794c840cf66d259e8b7a37c5c54c959093069010001	\\xa95c37f2f02015408596ffd1a1084f51129c0dd9e8a0705638011dc17492ea9e63c0a85d0244ed79d76359200cdd7390fa13fff6e260acff779962be8b6e1c08	1676800090000000	1677404890000000	1740476890000000	1835084890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
44	\\x7af478491611b5265fbfa3bac086a01806ad2a8e370784b67e88004a8c66b5b5e151e7f32b54192d2ee6605f701287b3876a3d5d81b45ab5a63498b4a12e20cd	1	0	\\x0000000100000000008000039aa938aaead517dd8e5b4fdf01d6f084ca8987a1bb19dc3aaa40f462cd4d4eaa07b6ba0d8731a7122b6f9b727ff9b27fa7133e03e5a05472cea40bf247cdb8c16faa5bcd3500df2661ebc61d7c0fb38d63c409ab9830afcd5048f0300bd69df388f753f5b9255e566f66ebcb084c8b73368f1883bc466b9b62b71235c1a783b7010001	\\x83a6c212713bf8ac80ff48f19b722c1201e329355a7c852e8882be7dff554248fee2120113889012e17b12985589f112d08a3621636178abb2ac76c69fe46c0e	1686472090000000	1687076890000000	1750148890000000	1844756890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
45	\\x7bf46124a66e2b77bc7914830e47a6ef3240e0c6ab477abd550557235492245c0d778d34ec0fa3cd126baea91095e61654fffccc85826b9795c7cb018f07ace9	1	0	\\x000000010000000000800003b08a6338bf551fc69730cc614120b4c4f1396fb5ce9de7f5d31b6844d0a628fbbbe6ac2a50997e5db85406c0f69081ef0738976778fa90fdf141c845252c788b0daa5caef9ea80e54edb3da5c45c78ff480ab8c2d631f8b761ccc41e792fca6d8575005da9e7f27d755c82c4b1dbd63de1a5d4867d3f930c9d1976064aef2511010001	\\x78b94e6d38ace873dac2b7269397d81ddfda50c490ef179647f71e2a961b820dde8aa43c48f414741ac4d9d11c26720f41a7cb37d0cea18e18ae233102964409	1686472090000000	1687076890000000	1750148890000000	1844756890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x7d30152a5c846866e313c95ab208cf24b041ec20e757201298db965c9084dd053d76bd89a5dfdcc949bbfc82d92105ec6f5e213a5d7bc01c2fe87c908d13b367	1	0	\\x000000010000000000800003b0588015434f19d8aca6cefd344682de4f19f72c1fd912a81cb7a8ad2e7fb08d293137142f0ff8eb17a937378f646ecb0609311e69c6bc0d886249dc64bcb528d33c535ac66b30f0c25d95d434cb490a2f325d867d72cfa4ed56339a433d40e003546e810817aaa891849f3c1aaa9e1a4631ba4a1f6ae5dc6057c7c3840ed001010001	\\x8128fcee808f5dc63560d72a51cdd002ba3aeab1705aaa363aa5eb705bfa5c14e6c29898b740bc37b2b1ccee79285291c91f5590629cd14db6ad844ffe3ce30b	1664710090000000	1665314890000000	1728386890000000	1822994890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
47	\\x83448b47f69db6c52fe87461e9bd6bb01686d06a0f1333ee61c6ebd518c3cfad3f311af25e6655995429a5f633b3251b1a2fa250559842cb3928b633738b21c6	1	0	\\x000000010000000000800003d0598984bd050bbc7498ae344a4c2928d865120fadec85a12c7884610561622f3294956f94972cc93c7d3e0c2f1ddd8f71cba2d8a41eb9588b43a5a87d3b1e3cc875a7834a42959e74a09f28f8324920d91bd101a1575ba5db8d6f7b10d3bdac1bed1b8f4756494589a355e8762d7441119a3b960769f6013742062e5840fcd1010001	\\xa69ce264e11dd667a32d51fafee3a72bd851c3ff0adef3544280e22cfa5c813ef08edae830de3741e22ba95a6071e1a6bbeaa2c7c24924459f39be0a41a5da01	1679218090000000	1679822890000000	1742894890000000	1837502890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x8668ba5b4f274c2e4f9927be79bf92b4d250b5fd97d7458f2008fe48ca14b5da184f123525b9eb02981e810afd56d46da06839b61376b94cac3b89df3548127d	1	0	\\x000000010000000000800003b0bd62f3e07993d77e176b76eee928f88c2d343f01e76eeb09f25d41020d054f073fa1e6fc66e3a9d8a23f636be1252b2386cead908d3e7d4f81152a5312d28f2f19aeb708e576abf47b739c1bf0f54671d8cd4042c6917c07f7f6dfe9841918ff5358261b932a3dcfcb07ed51e26d2ea8553a6345bbf4be3d1c33e45c51731b010001	\\x6411f5d568cc76ae4454141f21f6f0add7f31ad3cc1e7ac6e04308029c155169d937bcfe7ecd5fff2c33f08ce6662172c4cc45c7e2b1641058aaee9c7b4f9d0d	1681636090000000	1682240890000000	1745312890000000	1839920890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x868470a362ad1da5b7d0d6f61590a9d57e91f147cb96f96fb087c5a06927c95fae19a8981214cf2014011821fe41d7635dc8068faa936871400852fb458a80ba	1	0	\\x000000010000000000800003f76608b26cf58e802e02be6b5b01dd25c233c7537a6f85747abb87f7a340ab3120eca30951d848f4959afcc20644724a5a0524b445e8aeabc7c46009bf2ffd5b6fc0d43974348d7526dc67127ab42a9d0f071052478b0bb371352c1ea7e69dd9034bafbf4e3a25d2d0255a63906d37797fbda4f3a0ac49e4d4ccb1cadf97dee5010001	\\xbabc58d3295c4de3c2038946879af700af6d4247fd62d51c525d59e9e2c6c377697aa0528f3b2d1b6c54c9098d28f3ea223900dc8683fa9a3342d8e35eff8102	1665919090000000	1666523890000000	1729595890000000	1824203890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
50	\\x8a9448ec73ac99527ffed22fb5c2b01c1f8fb1f2985e3e03d2db20b7209f8fc4d0524e49c807d2e039ec2c29b41babac9b086a2898c731557073c32f0f90238d	1	0	\\x000000010000000000800003b2218d345c7bf2168cb378e7595f914fc0afa6a17a24681f9c90f4f1ddfab375ef90a20b9317c67e7cb6cd6a48c81d423621143dab45aa55d80abbcc8f24688767629075c51994f7ffea2e380658e916307de36271d66ffd3d74d185dc4f02f18c6f178952c559ba310035c5f98bbd5e191b31cb544542241a34794e899d26f7010001	\\xcbc9d876af0884050e6f56db0cd2cccfb92c19a0eadeb1de3628b57af742bfb65a98ffc6adfdd7de7c36b92b8797333f71e01c70b2b6ec2ab6d929633f9b190f	1684054090000000	1684658890000000	1747730890000000	1842338890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x8c7c347c7bd1b7d68332beb6828aaea0734fcf61921b0bd0d4fba87b1d9db60e610783a96e8890f7696f1d7da5736fb628787698fe9c960f988dc1791e738df0	1	0	\\x000000010000000000800003acdce5432bd4e0f2af2784196ab2fc95645bd5c882dc273ecf3c8496927493d6cee5c7833ccd08ded3147f7a50046cc55fde9b523731ae9c49117d8868ea4d4aa060412850961d6dd4f01558a07db33e1517490184d1eab47fb42e8a63e0d6f316f159968ea7c87c4f8b148be1d17ba66e0f43bcdd59c8d4cab509071a37f3f7010001	\\x49055a408be75803d92f43b609468e0cc85da7a09b38fc16e74b079acc1e28bb1ef523443e4c032ff3bec578338ba5089fe6c861584ef274e62fa0226d66f30d	1665919090000000	1666523890000000	1729595890000000	1824203890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x8c680d669fa8368aed3f9db1ee9438825d34692352b197a0691f2550f6b083be5c52995ab8615050902341cc7298adb696af1e68b7f6cd40bb0446ac22269a32	1	0	\\x000000010000000000800003bed9714c60d47763588b0b32de7c448ecd0f76ddf868ea2e94e0b505e3240a426f8329cfd5ddc6170087f9d75edc0dbbad847bdc234d7e72cc5f2de3101306ac5dceabe4a9e93a65c7018616abf1e4ba9ed2cde8d22beac3544c104eacc196747932102a3829a2432bc98e9a5212efd12089dd15685594104714d41d320584d3010001	\\x70a39c7683259496a9778d32cc548d911990b5eb567c27a288ac437974c7e923cfb80de0b636681a623c8c7655c53b6dbe2552e91994c996897760a4dd01bf03	1676800090000000	1677404890000000	1740476890000000	1835084890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
53	\\x8c04dde5e18fb6892f01f43414042ba58a697f4de81542f93751b6f6e57bd8c6d2b71b1eaac5ee9121cb9c8f0e0e8e047811d1d61735cce6103f9a75c50de3d5	1	0	\\x000000010000000000800003cab9536129e9dfe172f89c2f0f7be4039e79b868ef357469d6e30613b085acbd62bbaa8acaa1166c1b97c2c0f2a1b63a2b8bf97cba3c4204c5dc6e2c3d46674502c1608e4b438808434b0ab49abacb314376a1712bd06b22a2a54ee4044282d56f91ba135e131957042a76f207702810db236b2c323deab76b9a4693f041e3db010001	\\xff9bd96e69e358f1dda257faa8efc3a00f7a12b6e16c2a117c41b96b206040dfb380973d3590f8e88c26756344030b5161ed1222d2419b760e57a270713c9306	1663501090000000	1664105890000000	1727177890000000	1821785890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
54	\\x8e78cbd98a928235eede91d56499bfd3c9897d90df30ada6343103d0a3bd4fe8a800a2a2e916ef3bfc5251ed536968bcf4664f30b50f0c6657c17019b1dba9e8	1	0	\\x000000010000000000800003b3986b61cb6f3d7f7876c07ea56e8bbd2468bbf24ccfde49a4f5f7efcf6e7d0c2c414b0508516fdd1fa3caba1ae8095463ddbcdb40503e23e1bbda05403330429749023aa5c75b612a8e37af1296015c453974adac70696dd66e73ab058e8e5c54d1fdc813c7aef961e615eeb4333fd7621f3ce40dba69974687824c020f88a9010001	\\xbe36128d463f1140cfb0ca0a0cb16210ecb1220ad630e5eaeceffa125b6252ab3a11288a00224789378d50027d1dbc9b0135077b1369721a5b0540a4509b910c	1665314590000000	1665919390000000	1728991390000000	1823599390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x9014c5c31a5ea1b7285a81b9fe0bba2d74d76bf8d1cc28b4d460d0e45d80ea1d9fe1fac07ce1a2f8171216aa83745006f07ca91128458a0d0d439f84833dcf9e	1	0	\\x000000010000000000800003acc870eab1f9f74be582d4b338692d1b4301a807eaa876ca3e0f084d913c92e7020bdf6c33954d8ab36964d1095da9ac5069a6650f6a8b3a8afa5a16dda59ea9bec91299b0f35391685e110c9c9789e1e4ef2df08b11ee39738e068f0aeedc0b64c630d5c67b3e6f7de62ea0875101122c16466163f9d6532d0eee5b607d10b1010001	\\x42366c4bb3a2f322e5da280821e5ac9d4aee61dbf62eeebacad7a157dcafc8fd135276dddfd5a35328d3d377f5d2812312226b8bcc708fe0ec8d90d11e452d07	1682845090000000	1683449890000000	1746521890000000	1841129890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x910c236cc1eb0ee25dd67d454f32869c0d447124411ff2f1c0122fc76190f0f5636e7e1db682de921b2eb0443a20085568ae0608a215ed83aa9abcdcbca65f4e	1	0	\\x000000010000000000800003b27fa1b3084f66c4a8cea8037a4fde48c5410461222f4ded6c18a14594b71b9d7f9d15f3a5bb814074bb3489754a4d0470c6799214fadec8dddbeee7c82613e66eb0800ff62c3210601edc804cbeebb9a330361e275cd5c4a74fb8f8017215c2e6058c9ae6e611e60cbd3359d91ea7608f9e94ae9235a9166865a07b58885703010001	\\x055ede5e75331ee3cef3e0af0b3eb0761a1736672d32a6bc26c1cb2de56d0710a7e829bff9cac96ee69391f2f9523f7eb5334fc13cafa0e6beb26be828d4f30b	1671964090000000	1672568890000000	1735640890000000	1830248890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x9540e1b980e618a4c8968a66d8441f92f9e8d03127ceb2edfc0c83c99ef98a6c7f49cbcd5a2aa17c11630abfa7f48550f81aa2d43e5c042a67a2c09058269ef8	1	0	\\x000000010000000000800003c42f9a8c084eabc30af09c90c7f1b2d51aa2669e1aef7a42ca2a594a10791605b566f1c7c31f8dff9828750543056fca81b7acd8005faea75d617d87eefac373d3aca7225d8eb31b8bb27b7b6920f8dfa8a804b01fb628ca687174041c2902f3edffc840e19f54a3e23dbff066606aae14d1d2de9d9f7e1ec3d68cbe4ed1d2c1010001	\\xf294797f8b52c3dbea409c95fb8d2d4cbdd5636587aa2a7e87a4fd357808062ab133e5454b41dc85c12a7c3e574e52bbf078e8903229cdbb9e9a5d8665c65604	1685867590000000	1686472390000000	1749544390000000	1844152390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\x96185999b51fd595069f7c42d377b49fd8e197a197cc1818615b25d9204771fcec40cc420bb2574f9dea0a15aa08d6d6c4c9bc9281beabf77035de8e173450b8	1	0	\\x000000010000000000800003b559578d949c382a37357929a210ed9e6b77379e7213c8eebe7f6fb46efa141be48604fec6b16431e019388762ae56b03acb21a61eae7f06582a31cc182e0c68c082ca825e019f80e73de9470c3506da0a561a1280397e842420a70bdab983e84071f209032d0a13458e67e7f506a47b2176d19e2543245c309d9a8393cb420f010001	\\xa883e7cb56d59e0030a3309ff6dcdb24c6b09f6dfc2280e8f4d43a25b763fb650a7076c5c6451f5f9d6b6bddc26ca0fea0b3cabe47960c03936020295204f80f	1688890090000000	1689494890000000	1752566890000000	1847174890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x96f863bb41fa6a98485db9ec5241f9cb6ae4eb9491e045726ccf5c1e32f42e2a854964856e1316b837e608086d41dea669366a8069d233c9de6b96632c74d6e4	1	0	\\x000000010000000000800003d03503e7338841a6213daed5101c5d61f00fa1eab8c85d08af9c19e168534a5d0d7031ba3e68a8c5c5726ba5543740d7f9309cea7aa40ea22a00d829f773a236f229cd8bcd8c70cb887713c512e275294c8da1424545342c8d0960890c3a23194af1cd12a2d362fc23ee7c7138254f203df51c90e64a98e097aa0cef82b5b4f9010001	\\x2c7d1a213760534f0a052d23bf6d2b30e310eb2454d2a9312f0df7e36cc9964ebf876e810b51a8ba7b64dfbc8bc066d3572dad97acf5e8b0768a438f173c6605	1679218090000000	1679822890000000	1742894890000000	1837502890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x9bccb4a4dd8b72f771a9b1570c40bbb9087066faac1b06989de7417f48539df90036b80c58f0bf482cebc18c762d35b80f7e30d209b518b91a1d79c5a91ff5c6	1	0	\\x000000010000000000800003d45d95b54a197994db4446c5b797cceef7c08ece833caecbe57db5f1b31e97af0fabe766b9c7c8e883abadc980bf0b139ff8768bae3eef22b12fe39f70848ac12aef1d58520fa746d5cffa6202c91492d698df906bb13a18c8ae3cae573d87d1a2a4894ccaea58bdc546573fe85133c66d12a03ff7bbbfd8c5888ee0cf772121010001	\\x8a68215996d52bdde7172fc9e620eefe9f03025c0d94381630730209b1a1661d7a7846dddbefd58e72228d2e0f70c130d2df5327c39304aa8035fac300d9d603	1683449590000000	1684054390000000	1747126390000000	1841734390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\xa01442c2d49f02857e5076ace10f402d524f889828ee5ee1b91fa69124fff4acd121a412db38e672599f1f23b2c7d256342b2eb21ec0af40f17975ed93b1cdcf	1	0	\\x000000010000000000800003b4bbedc8b3b1e38a21e2984a3e3e8deff9cd23467caa0d720d0b3da08441d3416ce8716f0856defdb061853728227670e9145a4cc63f1625e9183d07bc3126106166c8287154f5fcb97b96aa443112dfdca73900a965debc77e61827a5f5f5b4720f0dc272ac41b5f4b0499e22a6b8a4d688964d34cf6cacbaa3c52fb8a8912d010001	\\xfeaa4ae09b4297cfb973efdea4984ceeba0a3d59c762bdde8340bcae8cd20cb5bf996442b92a40ad79c3c19941370c59cbf7f894e8fb209dfe35346b56fc4b0d	1679822590000000	1680427390000000	1743499390000000	1838107390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
62	\\xa1d0d4e0c8a2a0e44ae6e1592cc00a8c677c3e23d45999bcd2d7180ac12f9d1445013c2c9ded93e21289684b6c5ea64ed6fd6e62e6f18d85f5007d04f9ca0fa9	1	0	\\x000000010000000000800003bc42b42f3241e5e61407f6f6c7ccf1dd525c2b1fa68ce863f30f6de8aa57db19ba31ac6d0637ad13c6fb8adc31eae6857d51883e608dd7e617d4f3a87fe94950aa2be59aafc3184c797d15433c94204626e0acaa26c226c8894bd95bf984548ad8bb84f45454cc69146b8d9f72240a55e591fd54810f166bc04e3dcd00a3cb01010001	\\x8ce35b1038392a15d63a44cff0534cdedee23e632547e89719b55f51d3cf359fda4fc87f70a8f3b030503cf386e056405a9116aa28c77eb642c61aa0260bf506	1667732590000000	1668337390000000	1731409390000000	1826017390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
63	\\xa20492ff169e9cc8a3899dcfbf9767caef2e7526b3a7c2dd89277ce12c054caa7bfd9d4aa3043256626e3f72421674bd8ada535db30b4503a6835350c913b380	1	0	\\x000000010000000000800003a6703e13d555c3acb2f3d5b23fc69a6b7c897697a81767a05ba6dc2a64718c325185480915e26d6e9884905436f66a3b59be6acd11b1a2f47c983efd2b707cdfb904e6477465ff18603891e5b7ed75564e89cdfd4860a1c2012c84ce923764527ba1fceb18c0f2acc94e69b5d2f39c52cd15ce64a24e67c553718a20914a06cd010001	\\xb212bc22de0c25cc6978caf31cf5a5ed1f4fe0fb45bc0672e8d425a10da21f9afda83f837688908cd345ac79692f29f2df03b20a5596843c995057060e4b9206	1673777590000000	1674382390000000	1737454390000000	1832062390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\xa3848dad77013b3e525443ac6c61c66bd7f71348f8f0da28b96f18bb04be1ecf4e065684ed73b58754bbe2d4a69623b089b811f978f03992a143acf05ded5fa3	1	0	\\x000000010000000000800003bc972b2a3962746f57796cd099b15c1721ee2e6c95803e3628431df298b4f1edd0a018223e99cd130831bb0e4f1b04ecdaf4c53f36291133b16339fddf36a617eec7a4eeec6872336e2d1d02af5c813ed730a1b8c61246dcbafd981b60389f6d319d99b2f3071f07f3b0717597d1bb595aa75e787c771cd439c9b3f9822a0c5b010001	\\xa4800caef7e6cf774f3b1416c8e0a2180dffc9c016273cdb8ef2cf9748593df751343222559e86173ffac012cbdf95fa1d5a245c32effbe4a418872a12c0910c	1664105590000000	1664710390000000	1727782390000000	1822390390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\xabf48ed8717f415a3f581e2906cd7ac96cda78fcb388f20c9a48e7c2555fcf78a29227ece162c4c9a6462ffb3976f234164605bb5f2447aa3be4f9cc0ece9ffa	1	0	\\x000000010000000000800003c51839a787c5c68fa39db7d9fe0a18f4391a8f278354baa160ce2128a113adbf1e830e3ea05c66e1920ee32e1c15eb3f5a906b7c2d017d1e821f4aca730e393ce89a702c7f8bb48a4b0c707ee27307b12bbae09c4c00e97f5c02afb66e9f14ef67a186a98eb372ba46fbcb0722b7614da23ee2d23f857d355386c53cc87ae095010001	\\x3d5077374ce7580641b17f9046619e3e20212084fc2015471f25d07e85295e145735dfa27f00004af07a451ade58836c09677363755107f67ffc630d68259d0f	1688890090000000	1689494890000000	1752566890000000	1847174890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\xaf282c34ca3749ca4a4070b2bfb5782f787d3bdaead07d7ded84f5a45b393c4a6211a072939c3657f88f30543d35e0fde2f6801a745dbdd31289789dd1d23eb7	1	0	\\x000000010000000000800003c400aa6d7aa6d9b080daacf980aae3f5fcec3956a6a15c5191259541ee61da27eaa5d564484f040d1236101951431e2eb6a16c6564bf0a5e15ff41948ca1a6e599fd3681a508322e3547d91a61302a18b366b7e79a2d519fd0db41344939a4512c6a21451a27ce41235fbf7db55aa42bc4ca9561d7f009cf6e1c1ec89fa51093010001	\\xb58765f06a797ad0d6cf852c9984c92d82662b1fa1ad3c036f320c4894cc1fa21c13075dd42e1baebf3ccbcee67e24bf5a3530b6f357f0d06aff5b9e7321140e	1683449590000000	1684054390000000	1747126390000000	1841734390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xb0d4e00ac4d3b5427e7775f3b475dc4e3af5dd4d63e3fbd3524f953338a624f88b2441959a4d841fe602d070c9ffb9e2636d4f517dab32f72081429bc085ea3e	1	0	\\x000000010000000000800003adaa6fb74c50795ac3fc34d079d6b8b784dcbbe2435cdbef91bd21c93314d2ca08f72e82967388861567940f09c304be9404d4a96b7f02efe54a486e8133ac768f7c394a2e9b7e6f286fcd96c94562ee994caa67d59c2ff3e38366b284e90fac620e9b7117d8181ae44c37c7d67289c66ad3493445bab80ef023e90cff5c1d67010001	\\x02978aa073b73908ae0453a0ab6dc88599722de8160ec4b1647b584dc42af83e5c02f6ac57cd4ff278a58ba3983a76c714fead456b7f55412720b27e1743b506	1689494590000000	1690099390000000	1753171390000000	1847779390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\xbbf447c0a66c84e1f13844d1de4be22b80a82450520bac5706d40352df740a288ff955ba1ed499833d7d880155d61592ce6224859a3ceef71209f63a67279d7e	1	0	\\x000000010000000000800003d1b75b6d3fcae60007defbbe65c23d764d3842e0d91d5b7536b7d8deddd18cd2511eb583e67cd911fdb25bcd9848298c2a89182b283ce77637ba161ea024545bc8deeb1ac0618102033bed16f0bce774cf83d5c679e33283eaed4900373b0cf6ce6b1e5121b6d212d6c260c1b8f9f04f33dd56e34dfcdb9f451101199ea0c08f010001	\\x6835e971dfcdde2d1b6dabeb1604b70b1c8b47b3272e4f67c8e2b57758c808e4567ab809d85ed2beac5e2e5927f5a1dad29eaa0e6db3ffb13396a3de50dcf104	1678009090000000	1678613890000000	1741685890000000	1836293890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\xc00c1fb6b4a932eca558d7c251a3ef1b85d2e60404de8ad6e6061faa00f4af394b823f75714988f0ba377cc05931346004566f5537e94db1061102e8f61cde4e	1	0	\\x000000010000000000800003b1197d10854ddbf8883463c145a70a507692e5ee658d0f7c51a0f898c2ac90ba22bec33525a76a9fe5ccbae01c98688795a4d540a2b53323162713a833626da2e12287053d2263b985f1abab5964c0be8c87e169e46083d5d5750ce8f2c2e7f7abc8e3199b999da26376ad8ca31ab531a39e83855063831daffa7edd569c4321010001	\\xf2c7108f01161fede36a75a9cc4495308c0c466aa0c846123fbaa4a82a298a5be23c1d2bd25940d194e698e7c7847e9ce3a92b5176986e77120f877b03a3720d	1681031590000000	1681636390000000	1744708390000000	1839316390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xc24c0a5bf2cdcf0475eba5b621936317f66be20282e2e06d594b3a9bdb64f7102246bf4ca80bcf312dbe462ed32b8ea025bc9911ec0443c7c03bd1bc9316a538	1	0	\\x000000010000000000800003e90e7b3ef6f7640f3298320f1f28c27ec68c23f3b48193e89630aa15fa659120c7eabc3f073f66251b0df58e2de80a5422d89cd03ee5bf029f2e36cf7b35f9138c676612dcf8c9e307ec42c3565a235d0a8786e39c5d48f76fdd06b9692f674a3ba6f403e5740166bf8229e72163399f6d0737632bfba05f41f20608dc0f2da1010001	\\x9c56145bb5619edebdc39ee6592d546c208c6d43c68bf411ccdb87ab998777c04bcd6e4ee6cc96b9b5c97e2c3875f0b892aa650b79e409dfda09f80b590b3307	1665919090000000	1666523890000000	1729595890000000	1824203890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
71	\\xca405f394f8223e26ab98b6a520505d50d03ba1553ab0987b4207de37fb465bd78c4fb2c70cffe2deb5736e8512c8d14cc7a24f33c5e4a455cec64c27f50b132	1	0	\\x000000010000000000800003b709de74ea2dc07af4b664c794b965f31fabe2064dddb284d54311b973fa9c231f55383311db2efe9d336c07445286b81c925bc8b18f3ca905c005f8db12563a5d5c683ff35444a30c5e986978ac3c1d6aa402cec3a03f90da5f13f63cdad5a233c21db27819edeb542c2a571a1ed710f21fe1b0be226e7b34abeae2d25e55df010001	\\x453a1f7c11f829fbda297bdd69561630513d029803900b152b3a41ab3020cc5d516185a1a112c679cae43c2cba3f855283f0c0d3da2f6d321dbba434b10cf40d	1673173090000000	1673777890000000	1736849890000000	1831457890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\xd438caaef9bbb98e778b87219f3321c6f34cd0e58e0d1b45af01a20186d17fcb92bc6afeb84ba118909ec05c25ca3bf9e6e5b7450484cedb55561d875bbff985	1	0	\\x000000010000000000800003c6353ec575fa469c88d8edf0866972766ad69683e681fc4097bd23dcdce78a12cef4f216828d40487e04305639ae86e3e594ac6efa4392399c2900efe4523714ccea8995baea83f3b41543374347ba99c38ed20da9b0d3e148e3298277b3ca86c21250d900ee4056b24c9be36f60868b6b784fc194a01d65928b134ef8d60c7f010001	\\x1525bcd27c109817bda5f93f4e5e8fe2080ec1bb73fd30a0776de4a3ee5bf730e507d906a621fdc935093493c60f06603dd46b5abb82c6cea0bc4f481b41450a	1676195590000000	1676800390000000	1739872390000000	1834480390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xdd68a4013c29fb6329d4ee9e9bad177f03632d2dbbad1c1236be3def366402d8f358770e7fc9b4dfb635d507138daec160a139e78da90ac9587aaef7cd618fbb	1	0	\\x000000010000000000800003af28437b2e6a052aca41511b7f4b865f31316b001dd423565c1b2e4c3d0b829b37b7123f8f7ea6b6314684fcea48cd51472a3f80cb39031872563d4eaa5a8cb23a111a8bca2ca83e3aedf18a736d8bbc1adea6f5fcd7629fb704a9dd2fa2395623041ee904372d31475dd9ee279daf6e9ef1050f428d134618f4387f134ca885010001	\\x6664c60b6c160986dc831c3e59830566156f74cc3ce7ad4690496a9e91823e8a4218fdcb6b5f711e1c1487e17cd4cb519e634a21841b6d10b5d1f8109d4b560e	1685263090000000	1685867890000000	1748939890000000	1843547890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xddd8b7d37b2203ba96fae2f7064145238503bca520ed6a831111d4ab566e779373e32aaf0e8a30909a16dad81442f7fc5d0951b0ea88de2e3c629adade39fb1d	1	0	\\x000000010000000000800003d583d0859f59201575253a6860cfe84d1498be248484f7927e77fad7fe5c9e659bbf3c964fe89eeffa71c3de33ad6487bf56120a38186dda7a1cc0d0050acf6cd43256aa267da850b71458ec7d27be96d8a63faf23e354cf9ed1ab787c1f767b861817e51739b74f928ee212248cdbb53a9c62217b4a8a81c6202e12526516d7010001	\\x0f8d717b7f0ce0017155aa8d5dd21b1bba5f885023b03effa3dd11f7516705300dc2d2935644e6b2d62b9c30689fb0a82c58fbe83d3bf2759302f8f9a6443f0e	1674986590000000	1675591390000000	1738663390000000	1833271390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xde6c5e3eacf5dc017c5af1a41aae4a21e46613dd3690e80458c7a784ff11be1ff928e3039a731a3ffda426f6cb71b8b4503b4ff07aa61028503c7e952dd16502	1	0	\\x000000010000000000800003a1919fac26ff6b364a6ded53d5a10c04ebd7a92575b3c2a692d9df304c07788d574fc5fd585da6dd72ade9f26c7d7d5eecc61847727bf1a8c9579521595a34d41b76abbcab9bf2d9d546dcee80f91c3096e287ab0a3da52a39f7a60fd94c0926942397a6ec023560782ebe9112d595851d78d07fb9173e119af80a0842dae78f010001	\\x86bc112f3ab47e02b9354969298961caec7c9bb320d663f05c6143bfd51e108f021616dec3b287268cf8ba719d96a1086b706fb1ac53813ca3f78e871e0c6f07	1689494590000000	1690099390000000	1753171390000000	1847779390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xe0244e6f9ef008647590a13c8682b7ade60c2524bbb5af88bf58b1d9cb182c38a4412276f3c3a8969569087df0f2cbff16b8505d338b7c55ce5657a80f149d19	1	0	\\x000000010000000000800003af99adf495e64f41b9128f68eb42192eef035b12dc9cf2ca192d1e0a260e4ae22b9fc5496701235dcdb08a3a2ec3161646daf029a0ff35833d5a1d4fd0619e728442f45512895da0e7afde27f9b91c93895bd835fdb14ba90cd8e759e1f3c04cb61cab6f055797cf92bec40eade63a225692164ac8780b91734b3c23f33d7bdd010001	\\xac41c6464036c57456a56cf22ca5994aaa89f24ef7bbe29dc4e393999a388d4e45c9f9f24794056776868b20037b8c4d01541c1e87e63fd0554bb7afe49f2105	1660478590000000	1661083390000000	1724155390000000	1818763390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xe308f882235d765d975ea16b4d7107ba93934373f9186005e4e92c076333ca9ef26d0c33f9887652e32b8d2aab8cf27179395758fd9d4bc6122c5873157019fa	1	0	\\x000000010000000000800003a616b33cc8cbefbe2cffcafaea10be6d1967572a4798925fbe2f8a3c6b9601b9b15a96d8aeab6898e0537a01c40f8bee3be6f40c0479720f83016790248720c7fae06227d0b525a8399d0bd5bd876546ca834171212834669392532dae842e5b6afb33088df53afc85f503e11fd4878b3bbcf60ef48454ab922fbeca3c3f1a7d010001	\\x216621ba1debba6d1de4c6e1b5c8789bda0b37f7dd8cae4622f188440ff8611580169c55fd72c6ad2a3120b3b3bba5ec3e0c9170efe43be37d0d2d1edfce9804	1685867590000000	1686472390000000	1749544390000000	1844152390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xe3b092576ac6b853a2444cbd0cfe4db4f620df801b66e6ff31fd5408e5b079d963aa8a48286e8d74c6acb7fa08dfad84b755381cb43548f8d351304e9632049b	1	0	\\x000000010000000000800003c69df93a6bebcb0b69a4261c097a8988f812a5b4f3f7c4dff5fb706a05d571f9644bb38caa08e79633a68ae85b344e15f0681f916f1b9d318a029afd88b27dcdb847ea6a0aa359203c15cd68699405a4d3b676d631666a3d2125f8bbfd356778683f38502215189bbbd92e952d1188f49149fed2794e9c5644ca5a8b236d7577010001	\\xcac7b3d8c855a3d2fe0364d95336bc3faab850c45836f5a0a25adafab9127952ed954d0a02f201e76a7f2666128f80fa330cb0bf628e19253aa829e49e4a6c03	1666523590000000	1667128390000000	1730200390000000	1824808390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xe8cc81898b502633774aec865ad99e1784680f90667c113e7e5f488701eeb382b4c626756a16e58abe3dee6d8ee82c247ed360f1810b310d173db6b5389bae18	1	0	\\x000000010000000000800003f2a34604a63b2da1e61c8cd32d98c5d3bafa34c9849f8f01aae1924cf93032ed2fffea57213efa1a202862e98a6c308b924a3321f492b5d46c484b4750d935c640e77198e728a65962fa609d9f703eb4ad2a1cd5f0c809e838cc1cf930bf9ddf18a98cedb7fd30925a25db43659d777bc97b74907c6ca4658357b8a00c3c0e67010001	\\x70560a6bad023764e6d1f7b9f127d7f9f57997c13652e6254e116056ca976d59ce1b22a7f190a1168f72ea542fcdf4ff12ea7d3cf50f56a683de6589efaddb05	1679822590000000	1680427390000000	1743499390000000	1838107390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xebac7aa7649b906c555ddd9dced110dc5dafe317a8ae266eee3b03e9d89d9ee31b4db2f4c877789ec3aa7c2fee036804e96a52e0c773fb758ed17c59845b1798	1	0	\\x000000010000000000800003a7693df4f23df1d37fa7b81ec3b594eefa6d7f1f37a86214ec246dcacfdea793d4e8b627c8361b4d331d29eab744bd32f96e648d3ee4f5be5b6b5386a93516d076a8f7411fd8a7bdad2a605d7cfbdc5e5b29e473565ae207dc34a0bc3d2362e2532fef248f1ccd84933319cb8bbddc7b972067c89a681eb4e38c1ce28e32ade5010001	\\x9b5679bd16cfae9d14587989ba21df90b2026737fec72993ea2a1296c0b23196a1477954d58f390ea419e8f72cfd2c4033d6d59602efe32df17bbca4c8f5ab0b	1681636090000000	1682240890000000	1745312890000000	1839920890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xeb6493361e6a5cc4dab713fb5e447ba34d3e166e945939ab72284bfb1a89e916fa4915b70e19076d08059bd919d3c3cc031c1a96ce829f8d149992275045880e	1	0	\\x000000010000000000800003abf5e3817a2fe6351b06e5871c26f3e656a8b645c62de44caec5bd273c7b0304992dfe4613e737b402a44bcfdb8ff81a6dfa1624e31abf2714f29718cbef80edaad2e0560f84d34cd349473d243e813a0783583af0854287eecf15af73609615b0af0919c32186c96679688decb1b902b8750b981fa185ebb19bd8aada88f861010001	\\xd5fdc8d4d995dc553c565fb20bdc151bbc775874570d9b8ef0dd7be6a124796aee4715057d179a5be13c5aca26cfdffe0149d0bd23b28b01d474a89ef6f0ca0d	1665314590000000	1665919390000000	1728991390000000	1823599390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xecb45559fc63008b183f721aecefc639c77ba26e7a75a225009613cdf9aea64870abb6160bf10b05068b780443fe3a2df0fcc99902da5daa01be980e126eb2d3	1	0	\\x000000010000000000800003d943476fe71ff8b47c7e69f69896fcb325a9d48d38815cece25599dc16ca94cd763ea244e8a2eb8f67f5caba0d3f2d6d9c56e8f9c8516156b293683fb5f4004901bc39e70eb74fdb8834208fc5d40b65c2b87acfa76e60d44546c7f1bed11ea798f6ee907e36d3cdbd343bee2749f86d57363cf8bdec0489ac7ab05a8fcb8843010001	\\x6f3f98ded2014f534c36b0e0706ffb77d9137e888b28ad346106e15cc40b357685b58d48c2b82d5faf1c2b23f56aa44db2d1a4c3cd47cc0a1d8242eac02ee702	1670755090000000	1671359890000000	1734431890000000	1829039890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xf23095a4a4b96163d09faa3a18b305646465a10535243d2bbea10c258538e87687563bbc7090cacbfc278aa7d93158ca6d72a07b0085cfbda1582482e8eb9bf5	1	0	\\x000000010000000000800003ae487ca9c07ea385aa577eacb41cf7cb1c55f41c3d11e7142f467c03480c96ea8f4e293a5aae6b6ba37a1438536100ff955b224dd18e013f4a018d7eef370b560ba3e9da7f60f2d6216714b3ce8616b8c89b7ee6ba591d6774abb47632b88f376b5c7b223392ca8aa10d6b9c78df4c8e23e72e939a4e034b40a6fe1d4c913f63010001	\\xe24d9ae1ea3bd9d9ce774d1715b37ae4bc4770b7e8af4cee0911aecf94ed369d72514b47a5a3eccfbcb26d6b4c7913f4533e41692946e91491a8b26b2ad80808	1663501090000000	1664105890000000	1727177890000000	1821785890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xf30492e0e0a4296603470d00b55d9eccfb023da7b54082a1dbe8d99a1dbaa84c3905fcba6b3c9cf93be5895f89276b0e79fc4dd8923059aed411bdb89a8bb20e	1	0	\\x000000010000000000800003dc3f009d2649b9ff490619148aaf19a62f2583ce6ffd77adc228409850a774243906b381cd70ce70346689b29771475f426001528c524542dbe6ff0f9f3a316b835229c3f0c2c037432dfb993adca21f764ca84ed0afe532511a38fce385d7f7b2ff0fa77ab59c54fdc8f1bed434151fcc65358e74f6937e1931393ae2f90843010001	\\x8490f5a2d71b361bfae6e1a613ef10f2bf5a7c1471f787fdd0f939be5f001c1c89ace2423f35381ac9e4a5f30b571b13e4f3bea9225d3b63021a6233c89edc06	1672568590000000	1673173390000000	1736245390000000	1830853390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
85	\\xf93068708e434c3803d07279176de063719e6e51eb063ff4ec693cf1a5b1e51017c690c78e5d3e171b97541ea41bdaa7798e7dbfda8256f1dc8acfc326b3db8d	1	0	\\x000000010000000000800003f2a5f985c1a658ace5a3b26673205bad4a2dceb53de9f2950bddb377d895c25222d8de8e6ad881ca7245298b447c7f10a21715440b5326efd35da85d63941b994f779d4269fa776d52d64a49b43c0ed27eda4f892c0089bdcb9807ca4bf0e8a05a104a055ad2182df55ae14982fa769d5c293d01bffa050aceb933907e2a4a4f010001	\\x4ec9c14c6ca5d28fb8780e20f903a0a76ef0bdfd596bfd1cbc369213d5dbf5f446cda0ae26aa5a73c6dad2a381e0015b551ca164eafe62b814cff520c868ad07	1671964090000000	1672568890000000	1735640890000000	1830248890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xfae8e1e4cfad0886842c1f326015ae98596ba390430ed6bad31147417ff16e1dcd56b33ffe25906895a52a120991df36f1001a03968a489d3b9a69792f279e3c	1	0	\\x000000010000000000800003bb133c7ebe767e063da98c1b0111dde3d1b7fa993ff0378d5b366de1692f0c626262717409d963635354284be970561f9cc54b19e3e71f001dd9ab57acb23659681fe699d061d14876ecccb24473551913c7ce7cbf69d916226a7469ebae8ff9b0671e99a53fd48164f8bd8df2007af1bde1557c48881b3e7cf3bd98f7562e69010001	\\xf2b758cbebb0e42021e26b1b9dbdaac382e04d792e16ea0a0abb56be28cd4dea2529d850e3f031abb1dea192f2bc0c5ab5e2008cd5600411ac9642966b358f0d	1661083090000000	1661687890000000	1724759890000000	1819367890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xfef0402f3dbcb5bca4cd43501c8cdccaa40637b77001feafc65a298734bf2bb96718677ad5a8662c33c099ed1892a04d32293ec9f4c50d00efa4823c363c65f6	1	0	\\x000000010000000000800003ea272a5cc7d091c30e9318ff6a5c509ef5dbd7e392fd9a5b99decaf13ff129826dc21b408a81f3949a48c10a68e8685a14ea76a0cbbc6027563bc7791ea242ed906c2789d88276b4d7fffc5f144cb7afc9adf1e992a7b2eccc9c1f0169f5ca3a3fa4ec0f920e83973599369f3a1d7c167b422e4a3397500b9fef0e5d2919adfb010001	\\xcdecd18145afb3fa48666dcdf4064553a954b4688c2691bebb40f58a0d28edbf6e555b76ac0f2a54a7a42c1b1a4ef31f7041d27c9e9f490ca6a496af0818cf06	1677404590000000	1678009390000000	1741081390000000	1835689390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xffe00a79e4d778c6cd5637b89a4329f9426a17d5f786dd0b8f8d7d7566413cb94b2248ea073803455c08b6a53a214db5be5120003e4df70ffe9abfecb7fe39b2	1	0	\\x000000010000000000800003bb5b1183228cf473790243f1799f516fe97fd5f404eeb4464cce6fed5cb6411c0dec4a4030397cf711e74fd05f016f3f2dd2742373fd2720185e6946572bf096038180e77ee6995190d5d8c666cae4f9491137b331a6f4bd1a9856c3380e2e3b25f83c986c9f11e54ace8986c443e9c5cffacdce69543d3a5bd6c4d4cfec322d010001	\\x100220756900779996f7d7e1ea280c5bf717167f89fc4c9aa64093c3e4b53578448975aaa33371ab9b9a24fcf2524f7cb39e0f6626f5252f9fcdd7faca61a305	1680427090000000	1681031890000000	1744103890000000	1838711890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\x028116a0bd5443b005d1827b8483e6d759e06b07f7671870031493f6a349299ff9e574be71a4c83e1a8ec33c6267ac71b2c7af6790c68aa6c418d8ecd332f460	1	0	\\x000000010000000000800003c2f245ef4342064af38e747c0d659cc81bd13cae8b9fd82f786530d0ca3b86d633422664511b629fcf38484513b10c88471c3883586dff286f2796c5a8d151e6605ef21c82054c53236993a43b858013abe3c08b93bd78970c61de76284731cadc0162ed97866f6952f16d7aad9f4205caf1b7f6f11d2cf92949ce9fa19cf427010001	\\x292a86f4b785a6d6c57b553a9457f7bee5980cf7388d84cbea2c2c1ef45b5eb5e1c7785e7a3c426403588f278e033d2432b8ed14c14342ab5582374a4230c50a	1667732590000000	1668337390000000	1731409390000000	1826017390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
90	\\x0339f69d43f326d505e7624a270885fd2d57c948382e9ba26dc533b4a7940570001e8b6b97cd4706bc4e3fdcdae1a6fd31daf38128a87cf733cd892dec46591b	1	0	\\x000000010000000000800003a7fd018131c1e62f562696f39c630a5c073b88db0db318c4bbd49e9ec216ae01bff70c5fac2d29fcda944c39419ae20be09b5d8035d76cc0b37698a40cb543f040d9d8cb69c913b8f84192258616dfd6b2e3021ed7c2933c0dccf99468e1526fe658a2d4897b4b07d069a1744c29154d29e1f3e006617507ec1517a6f68b3779010001	\\xc73df82c86a82f67f1d366b35437264d81185395a10df3118e28904517c72bf15e101b837e223e3e1d859eff16ed6a7ea76109464e8cdfcf1271c3d202124200	1661687590000000	1662292390000000	1725364390000000	1819972390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\x0699e8b51a937b07f1137219d4860fd3ffacf8668963d1a5d2d9c9b5eafa5f5b7207fa6c6aa0f48028bb27335e7aeaf3165f663fbf4d74f2ffc0966ec61071a3	1	0	\\x000000010000000000800003e5a8bc007af379ddd3047d23d4733fd8f1b0fcdd6db58bcc5f36a797bcb3a2df8319080b0a62016178940b5eb38205d458e0e0d644543f81d030f45ed20a4a6abd4bc9e369b640de75e85949a52ad0333c9156c2353769123fe27f372f26fa1ded8d48225b7007685d82e9c50f55a0c3c52106646eb7e1da139e964d313bfaf3010001	\\xb38c61500a3c2331f87955a45920fcf053005b1836d740cf81e151c6bcded2826a0399ba36151528728a7242c6ebb12a0fb41e3b03088c920e8cc615a0bc7e02	1667128090000000	1667732890000000	1730804890000000	1825412890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\x09e1c7a55d81663095b1ea8a06d7b9efe0096160cfc0f73f513048592aa243890396da47f06c9cd01a7e1bf988dcf7695dac38482ba57eb4686a1b4a0a22a315	1	0	\\x000000010000000000800003b998e9cb6084576328ffffe8b8df21c451fcf5a38f22cff2f91bce8b72aee2f63ee38293dbef2bfb21a31643fd34bec28a420eb24eb57c4e429e9265f7fe04195dd96e45669b7d445543f30b59847dbc9c741efda1cf4c26f29af7aeb50690d01837ff26193b4e47fd9e8234fb9e138af8e12dbcdfebe046ca5a882bee3d2f77010001	\\x268ace94e4362a780c5a409c9e6e5a1d98c2e501d481bfef5d08e3ada27a01d412f1a7b5fca49bbc65aff99da16444525ae40023f95f52c56fc01099c02ebd04	1678009090000000	1678613890000000	1741685890000000	1836293890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\x0905583253acef19fcc26e666933cf8bc6d170045ab5892c7a8107ab2e3ffdca09d624449a1f382e82361ba840296f5fe6978a022476c2413b9dba195a115dd7	1	0	\\x000000010000000000800003c4f43691ce522908616c758e9b00308726e1a4780138a44534d27a6dff44abc6f94371f39a51c4b0b78a76dc4ee49240b17ca7be2a21b818727799a4ad492f2f1778607c6d8eda312a0b627068c31d0981807ec7eb576358f9dd9129ac61c0c2351f9aedf6bcb03e68bf7b5fad9277885a01987121d34c51ccd434dbd60bca81010001	\\x24ddc5c1ac0eeee49f571205691289877aedb6e1b8690dbfc713a7bab38941eb7d9f7f67d660af855c6532391316b7a4401ba31c9be67b7aad4e139920d95a03	1666523590000000	1667128390000000	1730200390000000	1824808390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\x0c45281c0a94be53c49099e9f1fac17aa17ffa880965985225c948975b7ded5e9aa0024159d36fae641ac4ed4c876f804f7d5e283b3d15c57bd5578219d26015	1	0	\\x000000010000000000800003dfac7b9fa55600e602d2ed7fbcab5758f68ce32d520497032b2c11e545ad5bb688c9d17317f5cceeb16177d7740d296456646fc1b8f1a4dc489c37469204bd9716279d5ea67aee9b876c69695f82127d3cd6a69e951dcd92790a27d18110b180826e49726c505ee568a03541e3a5eb539bacf5978c46e58f51acd2b501b3a313010001	\\xf13e2accbdb554b7f96b70e08faf4a63ffe71c72ebe4ee190a111574fec2109e968c36590db361e4e72d9b4cc9d6dd1c89fa922c58aa6bf7f6dae76d0f6e6e07	1673173090000000	1673777890000000	1736849890000000	1831457890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
95	\\x0c156fa9270c3f7676692010ca4a78beb27201444caf9d04f683664c7c64c22f59e1558d87d6cb31c3f515a26d593236b0dd78ec288067a09ba170891823555e	1	0	\\x000000010000000000800003d47fad908c7580ae84afc844c9c8697755104ad3757e2c463ebfb9c074a9ffe2bbd33a25da729cdbd92d66b0607900fa08bfddff083cb3e7b4799f74f5e8ca6402e114a432ecf15887edb66c6dc4c472fc2cf9763402105850443d92958a3529d394cb6ce0e19a9e750da628dfc32c03b4d45da25a39f9787b324be788be8b2d010001	\\xdcc680b8172fb2af94b0634f8e73348a09f49a55cd33f7a01ad7834d80ad2cea6c79855ef5f64073995596f68d607ee0ceeceba627b7c019e899a301a8d65803	1679822590000000	1680427390000000	1743499390000000	1838107390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\x0c1d664289360ca919d7f3b2ee6517643b96f631871a1eb10941784425691975a17f26868027b25591ec5503542a892cd9d5a343cb54db023f0a8271d8dab720	1	0	\\x000000010000000000800003b67c9a4aefd11330da03499abcb151a6e7725a1d03ab48192457c5d3ab896c22e292d1b5c0fcade316bb3a4369c5e18489827ec1b135f4316a97c7e992ce81ba7eb4889e6e7dca20ef33ba3a9e26be50c9d4b96a19b4bd5bacba16ea4af1e82183a564974c2e5765742e646482300a13c8709f51fa38b48d31d071bff9061c47010001	\\x889ba13d54d3e38c743a16ed065e8c185e380630eb685c541e09b47570f8b1d7af2a5de0794428754202fe6a46014637eae3bb53fd21903469616b2e6d826506	1687076590000000	1687681390000000	1750753390000000	1845361390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
97	\\x0ca53899b74c027b544e78c754387c5b0967bed71ec91644969c4dc59f9203283f3c6cc870a4d10e54183907b693d07c9fd829bd71ca4f90b048c600e33d485d	1	0	\\x000000010000000000800003d8a5cf68c7edae3aaf8ab3097f59382e8770077a66ee15a2f66b88a78fb4844ff337bb76a6247ecae5230dec1a656b9a1d11bd17ebe1b84f874cbc58b20517478e5e289f68eff551fbcdac245d28854b500abd0a4a549cab1fe98b64518b01e5b84cbb0c231e4e4a23fbff311b72dfdfbc5d046c5642cf30178210ca4e2f508d010001	\\x125842351f576ec8b669608c442727eef1820b813b9ee9a8a5088c0e8d57b85062bf19d8c7e23ddde9c1f2456d5bd43b838cb7ac79bfa28ef5c6a8278a04a002	1668337090000000	1668941890000000	1732013890000000	1826621890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\x0d896e1079322b9e4d93774360cb11e269d6038e7f5dcbbda8b391004cdcbf35ae9d1fca6279d724b3823354e4b923fbfbf0e15b7f76a19ddaa3f64e1e4c85c2	1	0	\\x000000010000000000800003ab279af0f72797338e8be6c12a2f03cf4aca18c03d53b5bb9bda90457bf1e908db7d9efdb4b51d6bd09bc2b0f51883405b675d46c79b08c1df69529912f7689350be266d8ab2be340865f5daf79376d214034b14ea838a04bc1089d2ad9fefdf72024fa9cf89d31e7ca1a6a3509b9594482581048cfdffc84394e5c476d4862d010001	\\x769aad8e17bf7cf48adaaa320520915e9cdbb7677dbb26b2e6aa099ea85af1895ac522de3eec2d22fbad654808084079d74f654b26d847a22e383e208022ba01	1660478590000000	1661083390000000	1724155390000000	1818763390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\x1d25be4beaa88c77b2195e642553570cb0cc46d8bf43f8c4eaae58bda0f13cb5af1cfc779f48a91fcfdc1ca0f3218cdf2fc3dea43a174e1c86e0790158f3957e	1	0	\\x0000000100000000008000039fdd8e3063ca778bfd46e0db1c75ec1e5fffc80fdfb9c7efc22f0418c15932226878ac9593d5126bb4bc0cc1593d129eb334aef272686e5f81b8271aac5f3b60e0291ea825e7788eab6c0370cec919a5888f071043a6d803c7de4f118d3289ee557371b901f9929aed8e3bdb924e152a9ea94ae6a4d806805cc12b94ef498e19010001	\\xc06cc3ff29ecc38b5d75f7a5ad16535db7461bcead0f8aeaeb92322df8d861d0855a0f6fe31f033d6df55d479a6ae439e36d977806db7976f0127fe2f7e39e04	1686472090000000	1687076890000000	1750148890000000	1844756890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
100	\\x1eb9e12164f8234208b27e55449071daf203c0df360f3093b2df382073776ec5e67f7bca8e230b9bca18152ea067629eb88aea4df1fd5ef9e05cb5c4740e19c5	1	0	\\x000000010000000000800003c9a90cb8571b2630dc61844e65b63bdab021f02c67d5fde8be19396a59ff8459a9052cebe4ad8703569e022365f046856d70047109cccef3f338ca3cdac7e10d1491108d46e5f35779d7f79989af31391a73e1c01157395b714722366883e848c276c68505ae1d8e550cccee586d2355d29b6762fb770f2e0d10f9e5e733cbbb010001	\\x7b927679e7ea2bcd89651a1cc1366a090a5c24568ded2e036aac28f0044446f9bd9bd4d9605a7f8ca3c97f4347f3fffe1d4316a69fb40aac98ac4cf48f619c05	1664105590000000	1664710390000000	1727782390000000	1822390390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\x2205779fdb587774a9e2ac23cee75266dd943c658134f913ea28997b30f6ae1244313342bb33155bb1f156d8cfcfcb07e280d8e726e39803e06e34e0349da8f3	1	0	\\x000000010000000000800003af14cb98004b12ec3a6a54eb682d32541d7a780509088740b5f27781533e8960f0e4e9253527a96a6892a9527822cd11ff367ca7b64786067668cb432fb64a81a7c61dc5288f4df2927ec15b31a8a3d757aa45e2f8c5123b37272da3d20b5a629df002241d128d2810dc0045310b1aef07835a800a0583ef7bc1936eb3384f93010001	\\xccf6f168001a56568af652a57662aba36b474a7fc9265c7080d70cd611be2061797c5efb77b2079f34face6edc1bb44a4ccbe0a0c299a973eaebe06ca3920400	1687076590000000	1687681390000000	1750753390000000	1845361390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
102	\\x2385602475144409db5b514a8c0a352fe828fbce3082e542745efd02303df00c2e169985aa17595b4ca3fc8077d2985868fdf6e0caa5cb239db723ea64711af0	1	0	\\x000000010000000000800003bebe7f915c0034bb5ebe34738fc18fad74f97c38ee016375526a2ab3cfb467f1eb1cedc1bbb044fbf7b16330818a080e3fa047f249e9f4ec5f4afaf19dfed731d6c1210baa2072ce9a4082133233eb8800fb081abd8a731e496175cdc7a66869472f99ae64fc49aed088bb10bebedfd9598f12708f62564227e5f72e09408fd5010001	\\xdb790b8d787131f60a2aed04219952ecc33703f7a9c4b7df26ab479f05b7c2ab6fab1985ac26a3f84d97f1ef5e06b7dc851312f06835e2ea36b3d42fc289c408	1671964090000000	1672568890000000	1735640890000000	1830248890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
103	\\x2475795a98132114a29e4fb7f962e8e65e6e946d87a9cb5d2e9e43879b44ee667188615ed6728f32de57b062bf6cb8518eee80a361db09b94bc3be7c2627569c	1	0	\\x000000010000000000800003abc63a7eb8ec876813c36c9b1ebd82a2d4e025a58a02645bf2c70dda461faf1abc1b69bb21a6c0b1f4f96fd56e490007d3d3ac7438ebdc10d970ff5433b662b3c0f6d5e1bde975d780dc6bc6c7cc5159270cb3bf8e0edcc4c7c2efe54adb819d2a1af39312b95ce0d60bb4f40c7e7cc5c3cf628c10a3397b8fae823c6308b77b010001	\\x81e98f6cb2d90fcc98f92a5b6b3bd2c2b5b20c5a89153216accb75b834ee900025c40f04b5a7c795f2118fafa499b2ba0a008e78dc6a395cafaae23a55caa707	1670755090000000	1671359890000000	1734431890000000	1829039890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\x24c5fdc7070e93bb929a56aebd2cb0fc19357a91d9f3e87d1bc6e5785464949a8fb70371e5dc783672d3e4fd5ea2929d4ea7c161298fede32f616ff991896f3e	1	0	\\x000000010000000000800003c5d43022f95bedce017556b5e7a4b15d521bef6e86e9cf09eeff363a39345b4ad9ba5cca724acd0424d6951c19b2fc6f4d1e026666be428eecd56385496b7090a5443766a49e40ad5bc1726c619f7ad54cf02ee2a2403775a0d8e4860440c95f8bcb89d744ea4c030bda8c12c587beb5190b1828afe531aef8fc780fd3e69e61010001	\\x58bcb21e3601829a5bda17a8df255b526e8599d8fd01e068b6200f55fa6ec12efaf3f09c9454f06897249f5fd146c9c931806dda39b96e7c535032d9bb888e0b	1683449590000000	1684054390000000	1747126390000000	1841734390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
105	\\x26d17a499550515cc85a63392fbf2c3041ee28e7851cda8980bcbde25a67f5a62c63ff5355900bf8f0fb0797cbf69075b84ed697ae194f6348693416f8b18a64	1	0	\\x000000010000000000800003e08b8b85f6823654d5d0140cf50e1e2110c9a75a0f81f1f54c280fbd18b7de2ed0dbca663d1993c6c7d2e3682d5ecfb593af93a7529909fedd02234f1316cf6237c54a86a63f2a6f162ad9efb0dd0ac269f1aae096db73a9b6ef52159988c22a1f7b805e072fde5696a138560fba1f4abe54fda6ec094142a37ae867e6a491ed010001	\\x05e1cddce8d4c9cbcb86cc9fd00b5037dccadb05daa5d115303f6b663e66f149b3f5272cacf0b8a78f03405f635f4dc019746c57e37291232d0064ef60347b0b	1661083090000000	1661687890000000	1724759890000000	1819367890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\x29f5974621aef72bed6f099201573b3166d23d347b36dc9eafb152829d1ebeaf0efb27f0c6045bd99b9044c391756e3690ea206e0419a79cbbc2597693431469	1	0	\\x000000010000000000800003f11b6b01838eae3bf662bd8e50811c43e3dd62a7be658179f1f4cd2261da413e895a022bdbe661ccf1f237f3c5eb3dcd06acebf77d05b1b780a6ae3d160b81f080b60dfa2c6b8a5dd76980b2c3cb0229270ce4ad53ae0eecfad465684fb424a02a4abf393dbee4a5a3ebb6ee0fe7fa99ac558500933a27998aafa8d638ab2b29010001	\\x435f64ada24f6982377fb95150aadd7039b28148ad0cdbd2cdf86b452ef3de47f3083d614eeb1c9ba12f972e139a2b356a7cd63d7f84058ace6fef9f73e69d02	1666523590000000	1667128390000000	1730200390000000	1824808390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
107	\\x29798783229bea6d8f4709876e00e526e435327485cbb9fe5f27015b60d4aec83f67f61d8b785a361a676eb1514cd00025dcb4e204713b96d925bbd5fd3584e2	1	0	\\x000000010000000000800003b707ead7cdba954384e52c66926b854b646170bdce6d366309e79355d58e4e30fb57f09446902b8ffc3b506e259a20f57d12a4ed6ac1360c957bd217deb3c0c0b924279e1b7749a95696cd55db93d805fba66b87ed1d7e28b1040d43f9fb3ce94f550f3e9eaff949f263e893464ea9e6206f8657b20a9ec9d426493f56f756d5010001	\\x1e6c0b3016a2534d017f8931579a16cd8c26997fd35d0768d0379f44b4e3288954071f584d14cd72c496e62b5fa34641c9b82e3faadea45347a67e148bcffa04	1676195590000000	1676800390000000	1739872390000000	1834480390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
108	\\x314574ba71db950a088c4a7121ad9aa00a84bdd81077439697a16091f013cd72debc388dd0ea7d72035d49e785b1c1718c00f1512e76bdec6733bf015190c5eb	1	0	\\x000000010000000000800003cac237f572e87e9b32535140e654f9344a61787676148fc64573678d9e57cffe2765ca571616eb3e0452d6a87d29de41f9f633b5e56b76d8e4b49cebeffa5769d8f2a51ed1ba493e8d39f5fe7c919fbfe78b1a2f971b4bb1a7db94b798b2aea9223ebe41f5aead14a268b9aa37046bc5432a71e4cac82ee3adc0824f539ddf27010001	\\xd901f601e9aa152b97b45473575dd20ca046c6a936acbac4bc14d1bb096abb556f1bdab45be811862ed3641cf7f2de9eb83a1bd42ab7a8ec01e99220866ea906	1666523590000000	1667128390000000	1730200390000000	1824808390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x38996772043bb9c4fec05afb1fc878ffb5544a33a41da1ce0dffd07e5491a02f1d0c9c144e9f5330ea59fbe28d74e8292cefe7d032b45ccb6f255f486873724f	1	0	\\x000000010000000000800003c520f228d13c0d3a2db84cc093963d58f45f36be45bbd10f94c97151a91bc0baa8ee05d0c86f9bcaa0b2f953977cceec83c1836f72203ea636a3b87690df7d32944b99a830810abf47a377cc587fec4c567ada7380a0ae64ce5b6b79b9f3a7cf9dffd35f108c407bb5a7c5f746e9e417a91497297441560dff719525630e0099010001	\\x586718fd768da757455e4770cf093959b71fc63736dbc4d66e63c44e586a761a57c613ed72929e2c786a8b133eead6eaf0c1d7d5feb71448f450258ace170609	1669546090000000	1670150890000000	1733222890000000	1827830890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x399d71a70ed1806799e7ffa3999adf3e22990897321448cf353d739d4465dba405b72bf41f67dd7369088c6322b3014c055f38f2bb574ad40c8ce230d104bfec	1	0	\\x000000010000000000800003da1e534b93ddf56ca63e0011296214fabba23d281595c806b3ff2b9326bb21a2199ed3857b87dec7c33fd81a2366b2b3de925ee443be07edfe6b2b36bf1b32bf7d11fc210058fc32d605dc963fc99789824d3791f2a255827507feb9bc5519c28dc5f2e7fcfbef375b5553847dfcd2f7ff92ae92db9e60bb99e20021720b8933010001	\\x1ae43a12e92a468a07dea3fbde941913a3aa54c6911380c45dec6214652fcf9554fc840278ca71512c464207c5536de1ad78bc04b922e038804a26e36f5e330d	1669546090000000	1670150890000000	1733222890000000	1827830890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
111	\\x3ac1aecb53f0c2ce038bbf81749595981cfd48c04c12931427e27e20c9742f35c53be5be6cf8e4fe1ee963999826413cdb631f6cf354e3a0f8ad956ffb67fb5c	1	0	\\x000000010000000000800003ea955c8873904bc0cbdab5e554c1e4ef0374cf9c67ba84fcaa0fc80a6c3a39f0c22eebf9ebc67e7d2407a69488590279aa7a809a5debe8826e18b124039199ed04715cccb2583eb6cffc90cc374cc8b4f746c5747b9fb1cd65d2a28245de56f26ad0b486325f034505551316c6e73ef14d7927cc48b7c6f3c230998a8f9ff8c5010001	\\x5a6189474bf2428a85e5b587e59364914a1e18ca7bccb7bb10e838f499e56d8de838695af0b6e62c4dc8351211f6fa1b6a4258dfc9b4b275476a27f585c50702	1681636090000000	1682240890000000	1745312890000000	1839920890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\x3c31d880e78098e349d9210c881b40fdb727be3258d641cb94aefb45198123a9f4848df95eb7ddf1e47503e04e7640939a7be9dab2152edf959060b867636197	1	0	\\x000000010000000000800003d73f34a82bec8ca2a8c0c496fbce10d34b93f2ae3418effd88846a011737964ea3345fecb74fac53fc29970d75703d66d6e153ae54cb604df98ed7e4126894d84b1eb2b3cbf15893ebb79cd04a4c0d3dd31c417c3d81ba321308f5aaa920727d1500afe6683b4c1dfc60a67f00f109150b0618b66fa047e275074c4b31e3d0bf010001	\\x74003cf2c2b44d1707e4bcfbd98282168ddfc4f3afe2f215b47e783942501dad03bbec8f3187aebea0c6e11055e30a9302c7b1cc86976f11a194a9bbac887d0a	1690099090000000	1690703890000000	1753775890000000	1848383890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x3c39f80cbe563547eeff467d94a83969d89e0c0afdad89084f750b3e58b8eb3957d0417d9066d6dc0680394c285fded62e7f973c0b5ccb761fbe71dcee7ed2d9	1	0	\\x000000010000000000800003b09e94308a8205ce37c1989e0d093ea7e8631163dce425bbd7a787a0c68f50221a65dbcc28ebd370d817f83dd2caabe3994989161bc63365aa8213c1c6c91392bb2783412af72f6ef26331c3716dfe66b632345546e44a8061ffe57e04be88725448d3c95528034bf0081df757a6277c6e570f3e29e6357140725317db6af3d3010001	\\x05a77a89dfb32a8aa0709d37aba04e73abb4a174002c6c0d76d63fdc223b0e7be2bb005f71a34770021546baab54bb09dce5e33349018c7c3b89057a4f1fea03	1676800090000000	1677404890000000	1740476890000000	1835084890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x3e096acbcbeed900e9795c2a1647081cdb2ee988b202a2f2f2e612a3ae9af94b441cd7613de3154079d172c4fac34588731e0dde456098a652a98ac5d6f794c0	1	0	\\x000000010000000000800003adc8e63656c5f265456e18cbe1a0e8c0148f7058aceee641dee5470b7a883393c03db086990a2bca388e829e09a987bb1f2483ba7f6de3f825d09d78a2ea1eb3a0db68c0fa46e984554e3c96a22b63bad1df1a52539bcc9100a3425d6d5f58e33bd0d27207884035106023f6b7d7afb187b786cd016563640e20913bb3545dc7010001	\\xef32500077f7fc2858432c23d2f3aa1e394b54d0ae1fd1c184d0c6698c438392ded4a0377de09fcc6c7dea58caad21e0d3e879fbb0b90badeeb34b315e215a02	1680427090000000	1681031890000000	1744103890000000	1838711890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x3ec520dfd65084d93b3e80465986e2aaabdfe7ae9df9150eb1c3210f3b1bb4a96ff2e03c6c8d3682e96a388c95ef9ee449e339dc3a324a37069f83096eda6224	1	0	\\x000000010000000000800003c10f02b30ce52d8195325662f2b1098f031c82bf60dfe1236a038af3107ea59c22b1488d927249284c0b0be19351a8a703f9fc65a7d7132bf9513852af8cb3ce71b7b177d8ef9e17abeefac684701edca347e5c0487339cee217952fdf8f1f5a2f1979b5a1caf49eca7720a9586d419a80f21bb13a39f430e7cb976401ea11a9010001	\\x9cdbaf2a4c8cf10f85fef433e3c3bd26a84dcae9e306d5395aaec6f3b6fcfe154e48b7f17b0297c9d90da6463feeb9a0f78f18b69f1d489c2e642210c1874c03	1665919090000000	1666523890000000	1729595890000000	1824203890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x4061b94838e783004a216cd6f9f8f09e44e7fd171e4f0bdf6aab09d9d39edc03fafc0e4fd452f55e7d2237ef17e6d7b37031e934850e702622242f9af75b8efc	1	0	\\x000000010000000000800003b888f98a7e27bc66963ee936b57605b04e170ead6c36545c3d618e193c20bb688f79ee80d76239ab785ef00560def9e1ddf0fc7fdf10a2da1bfff8750f37f3f508bfb4a1315b89338e3a0baa97cb359fb5eb6226914b14f228ebf912e89e24195b093f978535a2957b0478c28f82737ec32460cfd81562b98ed2ae5d570fe33f010001	\\x2a2638fab498b62b31bf9453b096d4168660c836c34d68d34b39a0501995796cc3cb8c6f4c1aad7843e590cfbe0947be63bb51c96de1e6750280ad06eb859a08	1663501090000000	1664105890000000	1727177890000000	1821785890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x40713769bd669c240670ff6eed0a9b7e132400a752310c6310ae3d9c24f1096590e543f3c180c2489410b5fac3fcacfb6c00e507e262dc7e59e31194b66c7c40	1	0	\\x000000010000000000800003d8e9df76d61794673dd81b7920db6467612440d76deda549f7da29e41659a30f40f1cef0bd2e55d74a474adfdd680727e6bc4244a003c716ce16b86c713ffac57513805dfd63397986e1e2f8152fd21b68d80c9481279a95ed1543149385a2e6c951f51ab853b45f98f24c0c75c665c9ecfb7a208a7ccb459f252cf50caa4877010001	\\x279a6b76c96c62115d2ac9bba4e45cb8610b42bdb9b50a75595228aca9510a20ffd4c7242d846fd28e02a96447db6216067249a9ac72b57bb05b3bb40bdebb0c	1667128090000000	1667732890000000	1730804890000000	1825412890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x42994e4e9393fcc0551f94b57b81769911a7907616b7dfd7ee8f6e3a44f80af1d0d48a762e1d4998ba30f160314f773743825bf16bab4d94ef2133b012e0a925	1	0	\\x000000010000000000800003c34264de337c46ad3f32a2f83c9ae99bcaec4108f599eac6b9290050fa133964c6d3bd2f64ace85a94c322cf6d57fdbf9c1e19fe26f746c14eb2a81f7d3e0090831a230c4a6e67c18d69e4d3313118135bedb588b6a5380ebc5ddde463e87a3cc94e95e8a27192d1176aa6beafc94b74d930abb527a2d63dd16151bb8168ae0b010001	\\x1042795550be8fd820166c1b38774fb4caaa03dd69761be3f7457d9ae4f22d059d3aa5887cad194c348b26479bf50abcf27584985cd39d2c4f824862bbef2a00	1680427090000000	1681031890000000	1744103890000000	1838711890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x4b2d3d140630fd5b8ef53fb578fc9d714f1ca15604902dfe887b25e168dade6655ff3b7ff22fa7551373ca5c6a35932aa1156bf33dc583e95d2f3346d4c57cee	1	0	\\x000000010000000000800003c1f654934634a7efc9e0d100194167149644db50128a1c0833ff5c1f844673965dfed17facad756fd2545788806faa5dcd8b6d4c7a8fb1a95e31e7f0ca313435b7a2094b302d116fccf656aba98639f9dc33e31a7fe879a214f989604b080332da4c0656da8357e75d0ef4fb0f640ac7f7acc40853d22938113857762822d9d3010001	\\x5e6f78e5ebbcb6107efffea2e9bd314402743d6f588e911b375826c4f39e45463e24f4fba7f3a237cd2eb347260291792fa21ba17dc9794dd07e2c85fc164404	1668337090000000	1668941890000000	1732013890000000	1826621890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
120	\\x4f397b3d18dd0cabae228f34e8c68840bd850816c12cd5d229b9f523d9f74a0ec1d8aa791b74a95a9eecbb49aa89c8be1ea89144c52ed1b6186dfa1c1031e6fb	1	0	\\x000000010000000000800003f1d499b04992c67836811e7c92343106101a0feb50531c2d108ce615f909f0c877f49c99c29b957f22ec909bf135f2775f88ff9417ad567fe653b500cc824aa61f7424aeb30feffe61412a9a853776a789a37866ec79a5e90fb2befbc7a0bc44c4267065a6136bf8674f436ba8450ef718348ee6fcd9497d9d2420fda2c05635010001	\\x45d98f5b4a617d6f5c4a94060022571b5f34b025e55ac2e94a25a5c3808392cf3e8ff46808310a29bfda949ae0b1c4effa5773238ef312ef23b6243a883ade0e	1670150590000000	1670755390000000	1733827390000000	1828435390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
121	\\x50fdfa7a289c345d43fa20af724d73e37d170e86319f547f5253e7be5c04c5eadc510832d46726f398184563242817a3ce621ca5a1c125d09eaea7728c45d97b	1	0	\\x000000010000000000800003965c350fc56e1a370dd9f7373e03e49401c51b6b4cf65fb8182b2d43db4f027033c9daba2c0e779e3b4639f4ff7695b60490089f7917380f8159a64c97a74bd608723687315496c183d7410c471844c1f35c333eea0501df97d3054e5abd6b3ffc8910d8d2808d116246240915aa11ff86b7a038960da7af50716202d15930cd010001	\\x867afba43d1b80e180a3f91367df00aff18de4e9706fad5fbecae508f1fe937678abd24c9dfc18ebd6bede56bd2d0174cfbc448612826e9a6d28f986415eb50f	1661687590000000	1662292390000000	1725364390000000	1819972390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
122	\\x52d18f01d3d858347c83c8875ed358c82a1da62397d7de75306b9fb6557c85c3d345ca2bf6dd04e299e05e0dce08501ae3fc786a5bdc71d5cc8a690039b9b97f	1	0	\\x000000010000000000800003b5299280d00e64985ad9b325ecc753316d45814243dc4d76864a5a931e9766c952c1b1f56a379f56030e62ecd02f1ab24b071cfe1305fd8a4482a57932a3e80492d899d7e442823adb1076dce2c18b1b07df3ebdb5e94c7298887ffaca52d1546b58ad39fd8aea969eb131144bdb6d5e5ad5c2a5e11de66822f269137dca7a15010001	\\x4752d98610b6a8250db0707226626e0e345f5ae341610830a2be2b1c6b184a5c9e9882981c0bb0d4f8ffda0e7724d2075677c3bfec77433f696a6d03e1f5290b	1670150590000000	1670755390000000	1733827390000000	1828435390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x5275fef7ac2a2b57ab6705942f609b58e9567c4d9cb59cc5be817606275339433acc3c79af4046bbda708081f88a26152cc4b87358d3df8aa46bf5c02a1234ad	1	0	\\x000000010000000000800003b19732154e84fc2904f21a3a06ae7dfaae0754c40075cc71a89ee7374a3997996a7a266a2ef6b133e76cd7045f7dbb06f55bd50bf770adf23a103301f9ab0d2ad158e682f775e9d25f31cb62e34c05b2766d1da927c5e19026465360f76a662c52e6fde92aed81e6eb2446eb1d26980707153537b96e91540be8f412c49595ab010001	\\x5ab55c8b49dfb2fd612d0e602fd4bf16375fea2728b93fbdd2b31b7d74e8a1214a0bd5505ea8479b81b7453d2fe393a96afa20a9a795bed2d5dce2bd84f7f80d	1667732590000000	1668337390000000	1731409390000000	1826017390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x5289a2d1fa1b308d960bf481f27286ea50e638614a6cc2972c365305b979ee11c3a935f824b9b88571dc7cb42a2b9318f326f5dfcf1e646678cd6936efa92e8a	1	0	\\x000000010000000000800003d84610600fcee0fae488532691b4eb2ead6aeeff93c39f26ab6dfbc6cfac9123f69379bfce73960a6e85670ced38339a5a1baf61cc02600cb83f62a31a3f45d6f45c41a3a86e9b3f8d9cb65b7461d422e19e2ca0d03a8aef6620beb7de95bcc0b63c1e891954aa244eebca2c06228929af7027b5a232471071c88ba18c70655d010001	\\x6915891f09fa92763e40e367c78dd205b8754a550bc138f69b22154d6a00bb21087f541243e05713273544eb7ad33092e6915ee448a32081dbb32177ba081f06	1679218090000000	1679822890000000	1742894890000000	1837502890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x53155c9402015a47685305498a89cea9a9cbb9e519091afee8b2df4e6119e07ce5fb52aff4543a760dc1afbb7f9b4117ee4cfd0ad53956b2788bd7220a2afb69	1	0	\\x000000010000000000800003ce352ee8ee0960830392699712f86b258bb8e3709a7cd1c5cea8c362b28ad85708d4d3b20c8340779f02abc8c8807586e65983a7cb3731bbe2a896cd510afdcdc7e8fc98913e78e2fba6ef68ce593d977e32b6f7a2d70c65593a2d2eb2c7f011c2522e833518007a92f3f991280d8197117c15105fa7cade297578eb99fb28ef010001	\\xb3614b516ddf86d494276de00acb1aef6b754dee9d7c163548de8000c963448832ae9ad0ccc62b14381e310824459cbf8247b3d0974a2ff7b621efb43950fa06	1676195590000000	1676800390000000	1739872390000000	1834480390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x53a1a90568394cbd2af9bdd73064ce12d1414110a0a1ec1a93d10adf9bb09cb126f6668cf348ce7ba1e29c50766eb1b9660cbee6111989d978fe199a0e93c2c6	1	0	\\x000000010000000000800003ac23e016d4ca12a0be9de3a27ed835f24b5a96250d9f1fe3ab85e3f40ee7772364576adb852a5e4b42bae9d3496dcdfd53a61812621e04be74074331022e021266f38c576691110587e997bb3c1d37e70faf89005adf48c2522dba8b1d06c478e48d337562a341d8c3820669fac132ae54b1d92825d3e782949c06291eaff497010001	\\x47e5c370aea961cd16653020081d2434a106aeb67f3dc7b94141d207bffb89e5f99c214779d6df3339aea4d18ebd9204a5839ff09966e2baec7fb4a8e6dc9308	1663501090000000	1664105890000000	1727177890000000	1821785890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
127	\\x5f010fc0be7cd275bd5bd1de56a52f3c6190d1214b6133de30183b66d17ac65a515c93b7c8d78d90adc685fa6c4449579692f7559634a3948f9fa53edf7e15e3	1	0	\\x000000010000000000800003d5c23e3ea766c6ece55c32d51e636208cdca90a711008630ae8f60dc631e69b04f7fa73997f12401d8864fd2529cc7061e45fa38b673446e602962a6e13bf9bbd972523f5dcf00760d9c14d749d5a5e3d759f70c94f38ff222f9fee4b80b8815db89b7bc2e1c556722a91f100bab068b264d50f1f0adca934c8b900fefcb28b9010001	\\x31595b60c568e31f1ecdaa10690c86ff9987a5d747966fbcba2b6fba6acba711148928c8fe8004dcea9b4784ca058e0c00bc7bedb7427d1ccdbbbbb2715ace00	1659874090000000	1660478890000000	1723550890000000	1818158890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x63350f43660b6b8d1fb74f6eae1969e4cddca40e7ad2f22208b43dd7ec4d37b73c0d2b4968db2ec82096e83c6eeb73fe243b9043658e2710799633626f656ce0	1	0	\\x000000010000000000800003dbf490644ba00f64bfc1c2df0b57df7e85041827d74f532195866982d9f130902fb303d340e8f0ddfb48c7d28c81f0beaba1b145744792e049ff93f2b81877dc9a23e477eabec84b604b9d2c9582ff66f7560aee8a1656a8ec7b30e007d2d9d4845f98a71c552d99f9e320d49e9ce41ccc3c9c5837aed04413d5fe55cdd5aad5010001	\\x9451fa6b9f685bccd35d9286299330882cf5d5e4dcf4ec761a21adabaa28611502c7459d550fed66842f75921095b757a9302a34307d51a0c1aa727b1f4a7d0f	1664105590000000	1664710390000000	1727782390000000	1822390390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x66454cf19832fd810138232be264907ff0f63e6f57781d23b53e57a08d89b84cd2771d145cdb42b37ab999baf30cf1e44abf03d252be4be7eec24e36f0deb8ba	1	0	\\x000000010000000000800003a056afabd7a5521a7edbe119d59b8d51e0a2c75538402be45a9d11f5a597b85ed2fc52f9b5b7d419cff6e277cf2f72dd1ecf05516c3972908c94d0e1375793a721a4dd890af39bc6e2caa8be39a80a45fc8ddc4996ac0ca4e39e4b4e0f2aecacdd2b9035c241f50aaaefb2f59094abc4049cd986641de83ff0e95371a30171b9010001	\\x0f62f70c98168b78c9e167a540187e898a210e40c82743c1f55c181f0349bb0dec656dc077f292ce15240a620a34a799c82c437bcd6e1e23475e1efac8ce400a	1665919090000000	1666523890000000	1729595890000000	1824203890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x6e99d858a3fce51a940d1f80caabcc5996de754a72dc5a70d0ca9e9609cc89ab5b0df30c3aa33bfac8eaa41c091079dda32c583181c5c045f062fa3871e982b1	1	0	\\x000000010000000000800003d7f8f0c051e74796e7d9557073e7eb1ab561ce57f80698325f228d05dc30da891910401d71e7ed3d806dcc4ec21fea43ba6d47c08f507b05a6124e81fbb7088d4d31f893a35bb09a4582ba49ab8efefa392ac414160061f0a03164554b59e109f7e7428580f0e53e5b247e772f65567bbc8839437a73303595cc609847faa503010001	\\x474ee2e7f05dd89f78d4ce78a2c021031364eaece29364a2c9a6b49ed1064b49905ed3dec6d85e2e8cad3cb7f0acaed5194efca99e77ae9b82ea7544ff8f5804	1673173090000000	1673777890000000	1736849890000000	1831457890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x7189b730f0c4ca2ea341db99a9569368b08f23dddd2aa0613cfeef494c1754611cb5a9e6b3618104135c551b55c800c21f3fac11cc6a9cbe72fd99aac51574c3	1	0	\\x000000010000000000800003c40a49294f14fb5d77105462d277a0031bcfb99d039c268acc8b5fc67901db480bd3af0b3584000fa934c60c56a878991fc30ae5dbfe7e60d6a0f5f521e6afd02541dcf1c37c832eeb762938a2385ffc2ef30b7d1cf0b5c907e08abd36a9ed3cca5153549b5a2769912b6694c784963d37cc733cdd97cbff1c6183768c3eb737010001	\\x4820f9ea8429834d1c77476bd5d6005223e1ec0bc26b5b8e616a78069dc6c274e8d806d634f040a36adbcadd19b114c9b0dc9b5e2ea32a5ef77d92847b644b0a	1679218090000000	1679822890000000	1742894890000000	1837502890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
132	\\x7279ca354be4e0fd70747bae19a1be498165c4da5d1f202bffa3a56f44c8c26161390decd1996d889e24aedd9a821bf7ef1164cd39a6785c2515cb3038e80fb7	1	0	\\x000000010000000000800003ceae7921b17b91147e6bca31d45328c44c8f662a47a9ebdbed3bf64ebeb685cd1d351285d4436645f91d666e45f3ed1c781ca0e9085fa23fa7fd3527faebf2d556f990d77d958d1a4529731639a7c09c188228054152b56c89856b9e14722e70cd3e90421f9d01155641fb6f95f1b188d97b9ec7f700aa1be1b580b5fb3b1357010001	\\xa9549fd9b885eab0d8717b3d539222b355a4854455c1d58119583e69dcbfc7391970cfeede315a101cf614f6983496c47cb2026e330618c53df2c00055866909	1662292090000000	1662896890000000	1725968890000000	1820576890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x75b9ce949e6cd118ee5e40168727918f6275eaf2b2c310cb89b71769debd4beeaeb6282af6e4845941b1752a7e4d5ab814595309ad9b493b4eae0674a6b232ee	1	0	\\x0000000100000000008000039435b81970512e7f8b36a830c02dfcd3c4c6a1c13bc05f69051097643bf8c80d23b722bc60b5f835b8979123d6787ea54459c149e583ecea8f6caea75ce57e4e37ab9777b2bf847eb76032bcb11bd346a7e4eda7a3e696af848ff64f5b6635757d94b95e191ad565b69be986a62aa3f3e0a24af3039eba4e3846e66c5b1094ad010001	\\x15be0fb7e9cbd7df58f9bd19d063c63258a30f03b407a0937f202d6784f071cb2c32dbdb21877570fda9fe35fc3a6738c7280ff4dfaa0b6200b35eef5809cc0c	1662896590000000	1663501390000000	1726573390000000	1821181390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x76153921534e08ecc1cf4793683bb3a188771683f8ba8ded426d3c4e38dcbb704a1cd154e7d24e4b386f4972a797aab5f578729c3ecba5949428b67e178509a0	1	0	\\x000000010000000000800003e5cd3359dbe143625a4fa9e491115cd1c3a9b62c92b596507d823033b131c05a36770609e89a41e997105b54416dfde701fde2cdd825328aa7f9a36048672b3d520e3fa5f8cc1a95b477ceed46ef9c901933b22ad1a115a6b9c93dec2b9b52a53d454690d37987d6678b76dc2cd99c2770c9c9c05be0aff4aaf7f081a5280913010001	\\x1884771a3938284167912f4d7675b231ab1ccb8445c8205690711d5cab13df9d726115c0ffdffd65627ff61e829ec2b8a1ee6bde280dd0a86e0f990f3fe5fc0b	1676195590000000	1676800390000000	1739872390000000	1834480390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
135	\\x771910ce3675f57f474b12588500f9578a80e5e9c5c9bf9eb112f600695368261a398fe6d4196feaec5d5dc01947ad4e69c475f78808233d65f6ddde15ea2e48	1	0	\\x000000010000000000800003ddc57b7d0276f556bf26f3c9b91f7e6c75a68b8a73d9fc5814a627c6a57ce861996d0c8bf63b3fc140bda969c165657db0327a7fbaa5beb6c6f11218014a203d46cfc2bcfb37da176aa1d82f64b44af6e25ab62b7d3919d9d6d61cb07bd9ac98e8c0e8752521902cc88386ac91eb71bca19db4256dea9fe3f7150babfa80710b010001	\\x0dd04d969ee00bb9c13881b450e3afd55f906a1ca3a300aeb1e3b49f5897d0ad8ad25520a478c007e1be0f5b818db1a58ba03573e596035cc97c862be1d36304	1667732590000000	1668337390000000	1731409390000000	1826017390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x79b1af006c8d117aba5f6f88eb5c7ae9de2af265f6fcfdaa67706f72e69f5d5423e93006f534fd94b2f5c2a14108b61bf972ff2ffee59301c6b0cde7440c363b	1	0	\\x000000010000000000800003cb875956695c40cac73b5cff5abd2f218861482d74ee85d7a386d3f4c5405c764057a20f91282e68a50f6b125095005701dffc1d1dec4b3006647234e954241e4d633f4830fa8d32c62e8d895848af51ba94f005fdeb6bdd8425f51aa4587022ff176811f6dcc3080453c32c975acf65eb73159e2090f7bedc519c722bdbd2e1010001	\\x57dff482735aacb2afbc76a3873f7e7a26f57fc08886bfd4cc702ee4e6965fe4b5cfb47955605684561d5faf9c884ddb0fd5a25711e971d96c5ae200f7accd0a	1683449590000000	1684054390000000	1747126390000000	1841734390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x7931c5af32884a113d2b98b3bef3d0f6e27efcfc7e763f55a06fe32a3dd5e5c8d119fc5d9a4657116f0044194dffaef643fd04f76d24b90be1be9ab0887a4377	1	0	\\x000000010000000000800003aa581a9ca9b700bf6beee76cd430c2bfa972620655bfe15e8b6cb99272529bbf20d1bd3c14b473e92f7e52c98f34a89aca0e0e839915681494eb29b8ef8fa968a0edc74c8144eca167792b0b4a993b5420a3e61a6f63361d4baeb5f6b4e89d22aa03e06bdb3e57a384aab98094c64b2dacdd0eb9c2d0059f99a3b7101fd052e9010001	\\x2fbf741f9a6a0c8d28fb0a89bd16d71ca241c61dfbdd5974f5b837143d9116656de9084424662159c530508982db3be66f16d0adc312794df12b527e50de4b0e	1675591090000000	1676195890000000	1739267890000000	1833875890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
138	\\x7c4db1fd81b69f110e485aa7f6a0d6653cc4e35fe799da232608d292fec6b744243aa57590cec0c99f8edeed22254368aca86494b997059c7702b3e73dc1d526	1	0	\\x000000010000000000800003c40ccd486f8a8c203747cd02af95f61eb9f2d803c9b3f6da2d03da0dd73428f30b121814d6ff2049db7d3c22c461842233a9cfc2e80b2c294dc4be3413273721bd44a4261fd49f15da688c9b78bfec5b490307d127acb142520c3f3de953d0df64a58e57f5a985df5619d03f1bbf77b2dedb896a15aad875d63b5d797078fc83010001	\\x7bfa6c8b1be07e847be7a3e2b5dd601e104ff4bef7668e922cdd8ae1b5d83f114a280ca51f85270963625fbd2658ae959e7a3711e5d2b6a2124e13916dd9d30b	1662896590000000	1663501390000000	1726573390000000	1821181390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
139	\\x7d01d05bbb599ea7df55e3f1f27843e7a090a14f574a1590a52f85e69948ab44b73e5558861c56214886d69688ffb72bbd4792d69cdbfd043f18b4042df33f14	1	0	\\x000000010000000000800003ad11138fb68294ffeabb4e6c1a19d8c7107d17ba92f5dbf5218a3450642d81ef2c17804fe8cd92906639df0ea5b7e7d19ec21033b4eff975a7f8e5cf6fad7fee20db7f04c2842accfcb23794d54a59f8c8e7b1ebfa2b7070e60539fa2480eb67773e9a05d3fa73396f3a84d9e57318afd9c0199dcf1371016ba5d1eeb2b88643010001	\\xe7713e5c1948f0fd451f15f09fe8ac31c263a20a2202f7f33d707d359112dc01a47e9d4afd8bab8657cc08cd74ba818c48ad18d06c076f4de73162ae3203ef09	1684054090000000	1684658890000000	1747730890000000	1842338890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
140	\\x7dd13422248b1d0f0852da538253c902b58aebc41530a5e64852231bd6a5f60e266188f949c3a40b25035bdfb01149286b08552ef1c2475a4d1b8d40536cceaa	1	0	\\x000000010000000000800003c51d9a87481c0e4a06031966fc72dc392b8a92f015c5f68748aaddbdd32efda48c3662494954e80952b0da958170d408c3eb15d13dd34ec264535cf623272f3b9058ac167d22c0e07608c16ec460ccde4faa4c13cff9835fe5557888be06c6fdc28af3f1c24304565960417a68b3bd7141ccbf3ce362bdb92cba4b10394114ab010001	\\x9327743a464a25635f86f8045d6ede79aa0d395bd9c3f1c89bde6e7d8d6779a747503ce8d2802fd9e0d38391184feef991d1ee41f25301687e4fc9c35e39380e	1672568590000000	1673173390000000	1736245390000000	1830853390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
141	\\x86f195d82506594da6813df7408cabea533deae07c4697c21dd3c959882e364a26fdaa5c78a82958371eb9d7fbac5c0e2b8a2203f55dd2b0e5b4144cfee4425f	1	0	\\x000000010000000000800003a780839322366c3e82b7499ff87635ffa414e2933298fe613be397f05e1aa190fc238da77d2e26552cb4f0ec0ebcf2c6555f3e7999ada78ef232ac7f9d9483bf0531f5cd5b680feaf125889858b1a1a2de897ff36d10ad9494eaa097c6cb66ebcd87bbe474f2b7a6f27ecd8eaabad07c176811d9ae357f478006c5f9d5461c87010001	\\x78b481e68aae5fc0a0cb87f8e968767174fef54efb7b1b2ebb1e63cae4dd9ce2f284f5745616ff6fcce5ccf6bd4272a675d6d6d8886864eb8fe57412075a840e	1690099090000000	1690703890000000	1753775890000000	1848383890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x8a2519c3213b042bbb87c570e365986885d43e74b2e15095efd025a4e4a56ab845610244b97c36a100da791d2dcc7310d4d72c10ee30befc185dd4a01c05abf2	1	0	\\x000000010000000000800003df53c84507b792d886c26ae029bbd40d38960c8a40c1d0dae8a777a798f2bc0eebfbab4cb3b8381d8ca663ff6519c6f1c7bd4716e3d692e55e3b1fc363720dd9b7e055a75f1b51d1a71bdd302f453ae9f6c0fa3b29981e4f518f851248a22e8d8eca59bf7232a33ca6e80df57fa56702703c6c4570b9e8bc8c55b0fc9e9f1605010001	\\xa90957c718655ce3fe36fe09472785c7f6cb08bb523283555e216a732042f52cd55e0cd0bf6fb0160f3898462f704d5017868df4325bf260d4fd3a60b4f1990d	1669546090000000	1670150890000000	1733222890000000	1827830890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x8ba9f286124d90e05c381d798de2b2dd93fbd5f2f1d8145a3200a13011f2f4b6130e02c98c8505477cafb2b486cfb14ce67f7c3fbdc4a3dd0142f8c6bd14aecd	1	0	\\x000000010000000000800003cbc516793e9459f0c06501cc77aa38a9a765f6dceff2a6e24ea98c09df4448e95356dc7d3230d1c81cf03e6bf6bc05b58d49231cd770b826eb86d49e85ed6b68efdb295503cabb1388ec9363af48deca6d6a89794941bc0054f562ebc423de75e7c9c8c793b5b5d0a64065e4c65372d4143417da9c6afdf990320347a879d619010001	\\xe83ad3ab5db285cf42eccfeb78dcf71043d7ed1786b20c4f60993fdbcefe2af7afb689b25571623cf0af7e9ce9d40977ed8203da5492bbc02b2f907f74eff501	1691308090000000	1691912890000000	1754984890000000	1849592890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x92cd36cf39781344e8fae073a2713d99ee38219df4f45d18fbf5df967dae5020de9d16449cd56e076fdc9b4ac0a6de7860281275d79d66384929bfdb9e2522d8	1	0	\\x000000010000000000800003b62fe3003fc86bbeca286849d123008e18e3bfdac90588ccf48052618a05fe20e82568f24bedc28d0982ac351850cc7cb86a821aa3c4d8d44ed65a37524ccfbcef473e9fd89fa45aa6067e5fb41f839c64b6378db448745562886d873fee1697b91ce710992905d0d648b9aa23bf3e1e5af7125a1f621958824874c4c19ab259010001	\\xf26957ed491b64cc958d863822a3202950dc7277817a798606df0190b325d6b2193a8834e9e84a5152b06a7d1e01e63be6f412d0cc65918ecfd30ecd268cf203	1685867590000000	1686472390000000	1749544390000000	1844152390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x93d9da4be438ab6f0be69d4a04856f36dc032a25ccf390780367f9cba21787bb115cd7a1d56fde47b445fd78570fb965c575f29324bf5cb3db265fd65324ea0b	1	0	\\x000000010000000000800003b22d5c65c96f09380e120076467cf03ec2dad0a3d64226ceee638a1bd2fa92ce37a32619464a63bfcf941ec84bb3e7ab5f1e7c2e6b4b412df3823417f8bb55ddde9c1cd40172a51a096eb4375a30ae18a452ff8ecac12acf0be4d2226fc3e82f3df115aa335604dbf2f8d6e81bf53d1ae40e0283764248bbe0851244153b777d010001	\\x8f1b0894fecf600cf49cf4256720b0f78174bd7e85f87d35033719ddef115a37f920d00c4c301fec9a2397f452ce5030c886f3c3f78727c13b1294fa7954890b	1684054090000000	1684658890000000	1747730890000000	1842338890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x9811ab498c2b38d27a418f62c99930970aa32b474e993ad3cf6c616dce492c59581ec87ac2d9466d736d9ff1c4ee1cf25693289be1727d0f19437d848752ac32	1	0	\\x000000010000000000800003caa276a1e2fd5f21142907b7cef45e1e3ebb683e04a50a6a1f6772614d25065b2e710824ec3044d149b0a0effacfc26e4bc1508b21a21d389fa13e3b60e1782fc321cd37c6ae01bb4638bbc676665a759c1637e628130bac5896e613e133c51e3b8d971363b425e1f73667e12e6cd13ff83c6a3086d3b273bb9f2e873238b78b010001	\\x61618d8ff44449618aa5abbc284c123260f33379fd55c926c08a4823d7340dab13b9dae4c3305f65523d2671c3407f3322691b9796b0ad5c7189cd72081ef704	1687681090000000	1688285890000000	1751357890000000	1845965890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x99f9e9bec357a78597b3d9d49b074fe8934e8039492c3def9725fc5125b4d444385fadc2dab05e56ef45e7cac3bdad566094a297f5b4bf57ee02488301807409	1	0	\\x000000010000000000800003c25c44f8dd3994085ca05f1ee835df2192e1cae70c409dda2d9c117c670ef1f33dc935cd143336b8a070ec8543e4ca8ac4184de83af479b43401508b26ea4b2bf3b775c83c499b1317d9ce3dcce46a91247df57b9b70ca8c99ade8ce729271e83c9d8a3ba9e6560264790aad3c39e2be119a56d2db14ae3e8d90d4fffe991127010001	\\x66dc8b2d2dcf1e6fbd3934962db635dcb81f3aadccb3823ec731cf383d387d93c7690c7dcbef94c8c4f348ff4d6a88091e3d7c87a296c11192e35dc8543d8001	1676800090000000	1677404890000000	1740476890000000	1835084890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x9f99b4b6a5042469b10af48b9ab52b81865208728b81ea2e96ef4387ab5d027e6ec87aa7fc2ae28649fb5d1ce1fa70a5f7a5dc28e01854123c3e9f235fe5e305	1	0	\\x000000010000000000800003c0ecb6ae2d2d331c1b04f2e6a8a1521ea7f4fb4e491e0a1f08ba294470f33e2b65bfc7edbbd1c443b07b36cb4cc27baae467ff0cbd04b2d121cb825480978a009f7ead8c0e1c52dd7fef583903379ff7631e4c0a133fda612b67c23287738435eea87ea9e0c9e3bf36ee2da799cd75b826df7ad8930b916f07a6ce95d70b67af010001	\\x8a33b0208ca429bb7cbfa99f50bd89c84271656b1d75727fc8c4f423001dec3222e04f1f5ff8d31c58c3e75a8a91d24ebd70e1f73c35e57a6f540368a0451b00	1690703590000000	1691308390000000	1754380390000000	1848988390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\xa05dfde6dcaa053a5a9dda9cc70336cc125c670f93316884fac663a1ecae05d55b97edd286f2ebcffda52f58f660b9a233f36251be057df8fede519a8e40c57a	1	0	\\x000000010000000000800003ae4011ba5eb73ec404a529defe14f21055d9c40a7970eb84fdfd31d6a9ce47e6d57f926c41933d051e0e52f3ba9aa483f9f731d6f471bff336fa3bc4a250771bf655ebbd074de93954a76653969b7b1f8a4dab0847b23d355cc13ec66ffdf27a3d813e0ed4e58b03e187b8e1f862712a25445e66a61a810042bfe5355ba77957010001	\\xcbcfddc5e16d57054805811a71a17a3059ed9b39a32d08e93df3ebb0c008f02200f384f9287d64a8a59b8a13011148e89c5066ffb4fa2b002f07449d749c3004	1690099090000000	1690703890000000	1753775890000000	1848383890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\xa08549c434f9c3822fee7510ee24c7e2d2403aae39933ff53be9bae3cee5d0254b514ced580d901311358e0817fabe030eba6414bf7208920a97ecbab256aa16	1	0	\\x000000010000000000800003d64e339427371639506e7a3393ce8458f8654086f7d9c50a82c836e89313e4b0d71c2fb3c86efb9ff36acf3c8a62ded771990d5de597e8a7a764b8e07fd26649cf0641b8959b7a5176d5d56566359168aa627afbbd3bd7777b271933bf206f3af9a834d4fa6c953be03c33e5c4ac7933a453da9ddf6f47f3be96f7c2b105a9c5010001	\\x216ef121de6328a3f4d5ca982b2eae941221536a535f26d3093ce42cff39bbd2544d513fc1c4fca007e4f397a626a1c54c3d9dbc58a8f490622393dfaefecf07	1691308090000000	1691912890000000	1754984890000000	1849592890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
151	\\xa24140a76fc7ff2175db2d2a8cf5c564182fe1954bf38f20a1e4df31e290bc1c6929108e4f6cc2c18e0cf9cfd14fc75b16a173af655bfb1b13e7cccab510df59	1	0	\\x000000010000000000800003c5e718bd2d5d349803f3cedbe00e8498add920548ccd66d55e35840ed5e00a95a79255bd7245bb418c9798366b277c2a0b7a60f369c9fb41fb1025a08a8e10f11ca2abb3e634585bf1b8cdd740e423da483b25e8901a999436b63e142a0a98bfdfad015bd29bfd8869314444b2b3bde2cbe103e2287618b98bcb2f206fb103f5010001	\\xc04278afa0f1f86253af8b3b6afa105906d4f27506e56ad83041c6d2cd27f863f6df92d81468b2bdce057b5b1ead036dffb9b1ea9dd94d58b31f2e6fbeee5b05	1672568590000000	1673173390000000	1736245390000000	1830853390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\xa325da2cb8fc84c4cc4ab31a7942286d95835fe12209f7b95dfaa979b6715e25f680646c5881a5cd79ec158a48e06cf929f5d2b0259f425d55ef4bf6be3e411e	1	0	\\x000000010000000000800003c3d8570e7146a556b944fba2c334ccb2b50aab0363fa0bb43aca1ee449f8cee00708c694f7833c41b39d0f1607251dcaefb721fdd8914cb6729445c5c179ddb65ec2a57583757140ed647717901649a499c5cfe0bab3293149ae32435a01bb6feda3ac016518c5a593ba7aae83f84bc4623ea40946a1215e4939ea7e3a5c3749010001	\\x9ae022ec7685bc1c0c950f787545075601599d8ea1689181f4b7b49a22ad057edc4165182bec3aa7912a322a2f73f8a228192848100a1a4787e8d8e6f88e5a0c	1681636090000000	1682240890000000	1745312890000000	1839920890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
153	\\xa961f89b90a47998f351b5f970720e8b403c43cc38137027b98c0d6df27e50c5396663f6581ff182b4b085d43813b95c6d2531757c75553932c1a1ca57e6f4ea	1	0	\\x000000010000000000800003e57ca2f2dc1b82de4fecb7ed0b8a538fa771fd9b9bab5df9dd06a8363a93757976c6d175d4b5b095e0eb35252e911224cee830dd1eea048c2d1f23f4cb85eb1dd85488a470758a7f067ab8a4899db8a89221989c42c5f757b3ac259a4e9833707bd7f3b5de16113b7c764ed0581fcf3b96c0b63caed502713ca83c0e8054f451010001	\\xce5d3b8a0d86e743e9807984e15c9fc091df156bab6aef6a00b82fca3e5ea3f7df51c789fd4c7aa81da99d98f2d207446b1d98563ed8fdf2ea7d12edef3d390d	1673173090000000	1673777890000000	1736849890000000	1831457890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\xa9257ec62f46c66136dc0f80aeb9a5e9e82e0c97a114fda5e910b8cb16d0f28b88590539dbf67bc8977ed1adaeb0eb9f5cc98990f01e070dfbafe822f4c5c430	1	0	\\x000000010000000000800003cee4bcfc1cebc45ccb0af7f758f12319f94b1f33ea9588d7c859b8b7e4a849e21e70dd2209bc92a6e83eae4578b441e376a1dd1cc92f215cad524381b6473b05adcebb62d976f673aed56f4a8dc47e33566ec707ba2d16271e40b890e94e30d1584935dfd513679e93779d1fe388bca6ec0ea7199e22521acfdd3e9321e0bd09010001	\\xc68b8201047ee0868d91c7b4afdf81a5e3263ae0982d21fed7172e2bb38cb7de9f499f526fb34df0f2768e2a83e970241ce103c80a1a2c67aee75656141def06	1685263090000000	1685867890000000	1748939890000000	1843547890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
155	\\xabe57b2148e147a0f78109f9c15084a33e473bfd33112f05c1abe160caf35b0d4c1826a3f4aabf13b6f6a599a1e13d5c37b58ac05825d2d6045cb3616719164b	1	0	\\x000000010000000000800003a730bcaed119c958c8d9c29d137c765c1569bcd0d39fdcb4fa85f69b255d7895cae6a1d91a5ddf72b19a202d7227081a5d1ba95f8b1553764bba6699913ea990cf285461d84418214eb03b2f1b23abbcfd19622046d3ce3504bc70dcc237593a41524ff8886937037497460f7801e8c4ce8e968fe1db7ab40b9fcacb38423829010001	\\x212831fc431aba453b62b83d3d81691046c53b07a3892de95642aca0661c4b6de2756685f3c801f9ec6f91084e11996e5ab1879aafed1eb10c5920439ab68107	1667128090000000	1667732890000000	1730804890000000	1825412890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
156	\\xaca10e2c0f57cd657365b58be9a0d4a074de32d2df0763cbfc16470d3a885ce31b1fffc3260922d453982f3b9ed618f53277197ce6a0f0099a82cae4583574ec	1	0	\\x000000010000000000800003eff1a7dc9a7810db2e07abcb19813bf1680c514c43c56a96771064bb09c5629aedf4b2c2bbe22963dcfaab3c768d259d29ff700d3a2104e432a9ecc30590af61274d5f11040413a3178966fc1ff15f773562cd861c75a2da5ee0ad41c83d539cbe8afb31847bb44c5b98bb3e569064224051df4a4c3b5954441735b2652779b1010001	\\x07bcdc700fe718512059e713e420c05d294843c2801c9a8c4c06423061454ba2ba515a80e59e832db34a26163a2707ea6b8d51336f28d52dc982a7eef2fe5a0c	1666523590000000	1667128390000000	1730200390000000	1824808390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
157	\\xac19ffbe42b5426911b9027ddd0cd191c9c6f148330e222f5feefca7aa199814c7f068c6103c14f154f6515e5e83cd8f1418d0f042edca2a73684d3c70e26aa6	1	0	\\x000000010000000000800003c73935c9fb3a5e9c7ce1dee9d4c641b5d9195f35c2a7888b4796174bdf1dbed44b7668b3f08f1c57cd01fd305d4ca645f1cedd5118a8b137312b038352cba02c86b47e35171416c2f77025a12e55d591bfa793a9755cdd9032e6f81108d51304662e457353844340ef2c4094adcab6c36f13048cece8ae35b162334bc8258285010001	\\x8fa253301d0dc07536d5bcb8c66930d30ff472160246a53c0abd4443e93cff22d6f5f5112205b6323ac6afcd6e0e06501b7b7b52355939cac4ad5c2462ec830a	1673777590000000	1674382390000000	1737454390000000	1832062390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
158	\\xb049836adaf5119fc80c5b4c6e4c977083a600b11a63a893f58a5bb6db6c9bfa78538b2a2db885540e3824d35f610b2734ab592484c0b76be76740855eee73b6	1	0	\\x0000000100000000008000039909eeba7f946371257cf81e0526ec0a8776347a325ab72951856bcc10121fff8602b7116a2b88a7f27adff2f841f6e9480e777177685fc4bbdc097bbce16a52cffa17aed64555177ec8d81b5de77f03b64d9f1e4c6df7bc3afcd087816a4747f6237f566abae8cecd458b29efd6fc197eb31f2ccf2e6e23c6d03cc25b5eabd9010001	\\x77843e0f65cffe99686f1b46e4cf3328bf946c2d4251a697e55cfccb8d47e9472c5d6b7da5932d4edae35fed47310950ace6c88be6db56cb4c56da74e5939502	1684658590000000	1685263390000000	1748335390000000	1842943390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\xb36905bcec38eb5d158a7745750f2da1be53ebe3aa74c74382b96ee27c3061881e75fb67e0dbd9500603322950a443fa198114c6cb0d0022c88fe9f2059c53c8	1	0	\\x000000010000000000800003acd0c79262db623c08d77b884a0481633a4f6c7b3efd475d6d4a68ed70a503b7ca05f786e4cbf12ea26e96b2b09180e22065d97f16411c49a086c55d2c718e3f6b59eae7ccb952bcd24403cb8a18a29fe0a6dd5b7bc3e25c5f7a04f90959bd8a1916fd4951f9773b7877b2644c914afb9cb9334dedef29c08285843dab6ddd05010001	\\x566125610dccf127cfd7347ee5baefb8c879db0cd19290ecc4f0f474f21725b7bd4c844015007907ef9946cfc2a2c624ba0424ff51f7360c1cbaca7dcc3fe100	1689494590000000	1690099390000000	1753171390000000	1847779390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
160	\\xbaede45b55c92420ca42819b72e07d88e0c53e366d9c88217466c4fbd64a8671caa5776a8f79de59665f52b73a779024388627ac4dcb6fdcf1fc365d8a3bcf74	1	0	\\x000000010000000000800003abdb6cdaaa3a772bfeabee7cb1df5954ddff0bf31c108a101844316fb8dfece1c094a3f259b937e3f8d8f542d1ae7824c7568f61bf35be92578c2e7ef53d2b32904ff8ca09191ca9658cc330980736469a4ac2b9a2445de03bda74418c46de80de9d511a9bd727f34c94ecf48313d7a17eb1f9cb7e74ef623baf64939d2eaed5010001	\\x42258dd635548e5f9a8405d5db9c9f97d531d670ca7f526c7df831fb4d277a40b6c457564ea87d7c36389e30790d411544ec017a56bf04d9d24907c4e85d9201	1691308090000000	1691912890000000	1754984890000000	1849592890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\xbd114f34acb6e64ccb9e53ca80a0f8f864dd5d017958143b519d0c792dca3d6d96b9cf613848f18e73f06a33bddb1d3d9a063bea53eafd7f19d136c5cf74541f	1	0	\\x000000010000000000800003c269ea63d1d43c7446fcc48f40ffde117cde69e70250c9fb335856a2076fb119098e1cbb6708263efb5f852fd10ff2b12e2b07a026cb1c40e4d5e321797ba3dbc405aeab64d0153a420026a0cc5b837d6049dce00450cea33f9d4dfc36049859cfc3f0f037273522fe9c12e74d519d3518e54b89bf50813bd4ab8bf6dc8c94b5010001	\\xdeeb7a9e7b05f44dab3e95fafb97917e4c14711761a79e4d1b8c474af03c73290bc5fe107dff50a9c4de042879da5675d17814b6287ae065608b26a53606740e	1676195590000000	1676800390000000	1739872390000000	1834480390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\xbfa1e671b2e175a8e8905ec72bc2a1f7696eb9ebf435ef8e01380815a0c082c9558767276d8c229eaf61c846221fa32a0e84485a203e3f1ca2016dbc4da1a7aa	1	0	\\x000000010000000000800003971f049cfc8f376add425fa8ca73d8bd56436f4d764387fd191e1799f9c7179cc096d2a68695912ea6db485d4203f249b523f15205b188298a9118e7acf2ebc086f475728e6fb535ad068a8ac40f3f69d0d126b680736ba73137edace9120547040c8398b729a8288cee6d149473af053aef35f4e5b392867e75867674aaa7f1010001	\\x3cca7f44cb0d416338e0aa84b133fef7c39ef8f663afa7c9e6e16100cc741b60aaa4e4219d6df279b660d1956d312b1efc9955f70806b7412e3f7ca2402bcf05	1672568590000000	1673173390000000	1736245390000000	1830853390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
163	\\xc5b18a6bdc7661e64a5d19990097b38d552fe541d04a0fe4d8942c16cf64cb199ddea80c255bdee7a444882c5aa3905485e3ab5edf2a09c7d234c0b741f9b1f1	1	0	\\x000000010000000000800003a00edf08e7ad29f8fecc58c9039c59c225c0c45e52237640270a86b31c5755ae4c778d9360a3dd74ffbf62edbeda3d4f2a296ddd92c34e561634eb3c73db2c4c12ad4ac71edb660d5b3f32179bb4d25e28389451635b836947cc768eeabc3588c37a92123d67b63713fa4349b028e4476b8cb86405799dae6ba0974cddf2a365010001	\\x17ca12bf3e9ac9623bbe3604045d319d1d17676050afd0e5eb41b14e59ea046877bf1aec742ba8518981a6a9a48018a081aea510dcdf3e82fcbbb7883091cd02	1664105590000000	1664710390000000	1727782390000000	1822390390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\xc535680d914b9329630ba948875797e3b3b222b293a78eeef73f9e5fb7d4106e5624a57b3239ca41aa0606ad0fe0163a515e4339d4ba6097cb728664a3c5c5e5	1	0	\\x000000010000000000800003baedba4d7354d597f8a288214774d3a861c28da8b7f00720ae0036a033dd4764c8b1902dd176e7bdb18455a8fe82f7d3ceda769ecfa9e538961d9f69ffc23cd281e80c4bb1d8355f78caa38a756ad2b3fd6375e7dbe002c4c83220c42a96b73e6766adc4c6e0dff37355d7c5536e358e75d73c4ceb6a74e6fee12110807f7233010001	\\xe7c4a03c0e2de6212e21c4aadc7f61af877d6c4d932e325b08e1cc18ecc950ffbf8dca0c991d031cdd4d1e149bdd9db110309e060c5ec935ef13778d727fc60b	1679822590000000	1680427390000000	1743499390000000	1838107390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
165	\\xc6396436488d755f01745530ce85e304d110e95303ad95bfc84e648cbec58d4aec54dffe000ecc8382fd4fb0a26a79a4b63a0c403262621a929daf7453c0d177	1	0	\\x000000010000000000800003c6a8e9482d04818e55331070f7489cf596efe8d3ffcd47f6b5e05d33af96765203c0f97af798346fbd0bb637b9ddbab08e01382674c599f84404a754fe5291b25df8d0b0e48be5162310b907e246cd39872977bdfc890b809fbf73334bcad3bc422af6a2bfa8055ff942ca8330deadeb0d71f9737a2cceba77f64af1beea6ef7010001	\\xaed5ab51c5da7af749c1952860055f2059898f47483403b872138efd038378c4adbfea34379dc63da9e5f84781f2d63b8449c7081836bcda1c056fd67d9af804	1674382090000000	1674986890000000	1738058890000000	1832666890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
166	\\xc709bab700894347e5761202dee0beb7864e83c17ab9099869ca851e7d3393fd6dc1f56f32d8f6000813cd60a5e7ad5710bf77a761bf43bb68bfd360cb6fabce	1	0	\\x000000010000000000800003af5caf8200215ce63d3bd021165340fc765760f98f097432bf6f11621686e80f85e3308876a99b619682a7661a1bef26968badf4c82cc730ec12a1a2fc8cbe31d120fdc748884f2c02b6bfa53103cd23179a697a9f590e21b6c789a632b6b4256cf3625fed39dc5898bc1d618e08167ceeeb219171f1ab75b4746a3c81a64dc3010001	\\x6d5f13f77731f21f32d5b6d68f0b42786f44ddce3896fc06bb1062091101d9bd0765b7b32d528e55ac95fd2296281651d76b8cc0f6cb7374c7cf97661f88db06	1667128090000000	1667732890000000	1730804890000000	1825412890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
167	\\xc7cdd7c0a871275f67e2813b50e32b7f0af12c3523a7e0354ebaf40fb7a984faf29324dcc14cc4226e77e8156aa9fd3aba4613f7174966d71e0e0845dc67f6bb	1	0	\\x000000010000000000800003df4c92d5c2ce104232d52f49feca3db85203b83470b2b325b7a9056c412133acf8f028d3be5576baef6a7b1a39bbb8b7e04bb0a06140647279d9b4331ef785753a2576d2e450884ffefeb8796ad2c2d07127966d4eef15f6678bf7b49bfb172056f14bc729794018f7ecf0b40f8a7c96484585db5b9da67803028a2a83c000bb010001	\\x36b700a28dcc7be8103446665fc8450e819ceebc0572c7ee3d6ad9486f592ad495baf8e64f2ef32fbfef38fbb30339b8cd094c2fc9d1b2a766b4be93758a630f	1670755090000000	1671359890000000	1734431890000000	1829039890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
168	\\xcf59b230b66d719f659f5f25822ddcef50508a055843d5fec5abb983b7bc24a87c104f0e06cf826f5046707f634d7326c19f6fee4bbc5832f70cd33071885722	1	0	\\x000000010000000000800003f609c6eaee5f5e5324046a797612b6bc88e5f35705d45723393688572d6685861291b064cba3fa14f05cf4e63f499174e822d995bcd74a85b8be68d2d25faeee08a5179dc611c8c02b17e7600efd05ac66c2a5c82553207709d0fd3396cb9e37d729caa58a26e65fb3282d683ad638c1235f8b3b5fba392b45f5b7fd46a47b7d010001	\\xb9d0e75939c89f9aaa8cb5fe83d4231f9cbe6d3620e4e3e93d2d90589fc28e688502d5e4db3bc47ec04b80b764eb5cff287910055c53504a4ed2b8e8e6c9ae06	1684658590000000	1685263390000000	1748335390000000	1842943390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\xd0e1074ef55f4d3d5718297ce7dcfa07764c7a3cd4cdd16fde7a0e398a5d45b7395a901651c8f64aa0faa5bfb318ec1ba7e69d8b59e2ba3e9e43dec86eca78da	1	0	\\x000000010000000000800003f7b3f181da640299d3a1e3adaab47cda88feb6f99418fe8a6f8afafc8fcc359f876113fd007e4ede9f4b072accfd355b2e8a7ca31b212b9c54f76a7a4d549a2bbcfbfd86fce95d9d091b9e14166ec2517d02ea1330f93bad24fbb77e16fef4f661e92cbbb82e3da9381629e7e3ccb8ad31940cd31114a7e1f45ca3a7b26c9571010001	\\xfd7580894a2a15cd2a06aadc77cb0192f44b2a9ab75fe36b366ee9457aa24f1880da031b7796a2129afa7bbc44e7a64c2c8da049d285ed7a087b5e518c378907	1662292090000000	1662896890000000	1725968890000000	1820576890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\xd42550d179d0fb44564a19c23ba6a014a161b777ecd73499a17e7f227aea9a46330aa1181af67cb0cdb95c990a7e9cac34831a4e9c2167bfdeecf1f179383f19	1	0	\\x0000000100000000008000039fddbbbb710c9b8e08201affda808c61c404062ff483720401b713a8010308915d8a0a5d9d5ed2e2ea5af43fbf087b25a934c4b7a9c482466179f2c07f69d71076051a931f0edc5c9852581f3d2cf848f78403406abd32bc88b6a197ffdc6b15ec98b65a6e55726cf4eade3b1a9ce98333906223db08e368542bf9c2fc6bd48d010001	\\xbd2148c90003f817bf19c1c5f23dbba504b3ccf4abc8c315d1e3613ceb15183cb51bff3dc7d49f200dbc782b174a679c7bbe05ee35799824e8418c882e609509	1674382090000000	1674986890000000	1738058890000000	1832666890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
171	\\xd535ec6ddf532d1a01aa61d0bdcd8f6de360534ce65a0f32fe29e567c4ac4233788a9f4e1cb2b3282052664cf6f563fee2a8612187d7d9cf2e99ac1119160ade	1	0	\\x000000010000000000800003bd32148541e52f1d0ab790cd0b144bf481cf0885ecd9f4f250a5fffd2f79b99c7dbf9a2f7e496f504c68ba0c51dbd8549170563993e62a42c1df94bed2cb69ff232679d292ea99e70471ccd2488cfbbaafe6755c3ba1fb02dadce1ee8e01e9b26a0811bad4b70001616af3d91a31e49f9ad36f9447a8b404c6e2952c1c3599c5010001	\\x9b73cb2e38db63ab18bda411a1c1c083d4884e75754dff611cb5e7cb234568c915a3e0a2413e0c488da2ca6028820c148cecd08b33a0754c04db29668710e20c	1687076590000000	1687681390000000	1750753390000000	1845361390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
172	\\xd5edbb9140c845f48ddf5f88771a71a94c09828b5c342f3ea999fb360630513e2220197cc5ccafe21c052718fbdf3cb5efe63cc18b956f5fc31eba7ab374e7b8	1	0	\\x000000010000000000800003e541876a3cf92da4bb8ff147c1b528630f699fd126be8390429e30a6ba1f559c162ae4ba01a212c608e3c4d18a9f300a9138c2facce02b7a703a7b0baef9ff78a2d1a5a3fcaff2ea8a32300e644f9d2b29d56ba1ee45516adf4baae1e893df1cdae0af931b396b33292bf1f8272f9a62a3f829bd2ca05e27239a45729c60f3db010001	\\x4bc9809310b58da16903ea2bd0b6c4c4cc9b52896b6fe7d56bd27f18c4ea090392baa8153f6da963123eede05b4659e5b3796231776e1aed5ab1ddd79bac680d	1668337090000000	1668941890000000	1732013890000000	1826621890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
173	\\xdc8130121f8a0bfa47f074b69aea954b0df740af55ac851d4fbb6c978f8fb6c99b543fc742a18a6d9e1c417dc67fa281f01ca22fba9a074ad9c044ac2957987e	1	0	\\x000000010000000000800003c234797f690fcbb946ec4d9ff3b897365865c9f3e10734e5b8ca708f7256a649791d898133ccdb44cd489841d476355f88accd008bd2e3269488e2e437b719f37e932b629f2580de5164d11217b93bb6a3845c7a9c5a32d5c6af6194f44f361170cbf73247e6e0cf4b26fb0da4a7635a6d671bf8fd48e8cfe7ecf31fd5c7c5cd010001	\\x81686d1ee22d3d28cf53ac1850d2d6b062398983f2b60e0f20373d7d60c635763baca294967d80fc42b1a790d6e2d1847b7a4f5d90308fe98f8f5ef989740c02	1672568590000000	1673173390000000	1736245390000000	1830853390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
174	\\xdd490fa4d56650268a3555c891a32d5b54d0c56f97d0740e55119d91c95fbd32fefeab73bc4c76e261dcb8fd3f00f6c643e0e8c5ddab5325989a022c02396a9e	1	0	\\x000000010000000000800003ca1ec1de56df60fb7fa3bf29175ff643e843adef1d4907012fb85e3b8248fab5a117edfed0a6f2070b52da3f592f95872c8b01e13a0d06a55b2b27fc7b8732e27501caaad8333b8e2d610e995dcea51a751cb0d4afceb4689c6f594309a2e3e1f0a652f4ea7b061538b4a0807c04940e94be86348741e71a0ea7d039d354e3ed010001	\\x3a9a3f6b1aa7556c693fd37724964a8504b64a949096b4f5f6f7205979705a5ca2d5af090fa21ab2e59669d657d0951b39930cbb7cc3026bff2e5ed4d0c0860a	1677404590000000	1678009390000000	1741081390000000	1835689390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
175	\\xdf5569bcb16afbeb6a2eaaa12111ea2b47251f4dc0fd765d56d503b56605f09d7ab8711502db34b0b57260c3bd577b85ef2e7b07525fe0c544821439420b1fbb	1	0	\\x000000010000000000800003ab7b5dbed0b082f68f5ed0dc7f785e50cfedcfa1cb5067a0040f56427e5a5ac358b6c4b501b7e6ef1dcd6964f599872faf06242beb3f99f115327f470f039ce6f2e08afc3b865f3e558265ca4da1414d77405fb3b0f5d7dac0829dc0b309b99cdcc2a0014c8906d1c5939b6af9f2d288491550802114b19816799e0f05e9e9ef010001	\\xa671b6e284401ad7c9d4135cc583367a12df30f44cb01752024a4989ae7c94af9527e1d7afcdfc92903725369596568e8b844a6ce045e5c133cff2e4adcb3303	1682845090000000	1683449890000000	1746521890000000	1841129890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
176	\\xe1318f7894f85c9b93aae7a03fb9d756de80715dd6550a80a79a9f78f5cbc6e9d50caababe7cce847e3dfe264b6c3f1fd5d7aed2ab44c1ca8ea9d3bdeefa064c	1	0	\\x000000010000000000800003ce1fd376187294c2119487ce9d99b15fdf31931692ec351cef062d9e73befd5ad3984f4fd4801baef4d198eb10f106033dc1c1683519bac55e77e2fc3d72d5a1957b1b4a9200067556f32f8c5af64dbe5b243b1c519e49c44e19029a5485a947f91e31a1c70be7cf887e2378618c75e2609b9afc133556f129bdd8bc61f2ef07010001	\\xddc71e6a22625b72516119be7fb6d74597b426733e02f2c15593d8b8b66f8f25820839a742528ad36d07710fc687f4c6a57d8230173ab481ddd4985833cb7809	1679218090000000	1679822890000000	1742894890000000	1837502890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\xe1d58574371757aa768422ce460ae0636f452c5801919078e70123cf61ac6fcab5809da582de3095d2e4f99c8a759fa53f1613b0a7736c06ff1f1d565a48028a	1	0	\\x000000010000000000800003d62922c07bc84b1b56b04c4fdc37fd73d6d557a6fb325f1e31ce0fac46cc2f55e916108e6bb05e59d82c80457685eb31e1723165f7ee19eb4e1769096a15dabf58d189859a9f3e16aed486cc7771352165c959f628d1349a5440111c68f1bd31dc7f2a912f255072ce824badb0b829fc5f08f39e07e88fcb184b0eebb8fbfdf9010001	\\x150a871a84333ab688383959891b683cfb77c019f95fb002f97c7dee6193630ac93f995e4305863471cb6259b01ba40950c5532224ef6b7661c1f9b16cace90d	1664710090000000	1665314890000000	1728386890000000	1822994890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\xe441bfe6bfeecaead4b9227e26cd3ced8e1dc2529e3a42749b36b4e771274bfc65ff1f6783464f689afdb4a0107e59fa76cf79c56347846e0360dd81d21a52da	1	0	\\x000000010000000000800003f1ce7f3eea9a7e6e63e52149df03bc49c5ade8d8cf452422821fa38e8ed85c47a7f67735eb4d446b66dc540e33a0d5957c37787b62c6c7f4bde9d370fac454ea353b59e8917938f4e33571f8b3896f789ace5397f9eb8d4258a1e7c921f7d2444fc5b479d96a5a3eb7b1bf1955a6cd1cf93966c22907a188cfd1893bd42a0cd9010001	\\xae6a75981e4fcb52d794a0f968871344768f2773138c4fbfea6b910b876b1d02ac0b1631a8e9be72d2306a69c4e5f36e84a8b2662d52353ddcdc3ad92b3b1003	1682845090000000	1683449890000000	1746521890000000	1841129890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
179	\\xe5495ed149d0bcd06013352095227192bc51014d1fec33a495cc206414f9c07f4b82e92249f18e52fa4a26cebd6d76062d9914a0132ce8871fccde5b9e2e13ac	1	0	\\x000000010000000000800003aedf58e23557ed52bbf602d55de1d1a7731dca99ef7a011898a8c263467251e9218f5507364ab6503036fc1cc0b305b6350e8d167adcef63f32c59f02fc91422e62db73b8eca2b13f38af48cd35320b7fb790149e7e646d44fc481b935d1ce6bb06c9a4df7fd4a8b726e5c7dcdfe39b9a0c72ef69a572adfc62d550a3d90af7b010001	\\xcbe10248fe54db408bf5ab78bc5f580a341b50615097c8dd4ff58a966c5fe0cf13d2b437b7d6ecb7387cf4db3f49de5f3b3fd4f598e6ebcdbd6d9bad53b58306	1684658590000000	1685263390000000	1748335390000000	1842943390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
180	\\xe589c46c9ffc4a456ac1f4cb3b4c267468cbe42a39dfed532892614c8bfdd7c24a4fc2465d0837ccd1aab091b582dd27ab2bf29af4144da8dce9a15e56cd5711	1	0	\\x000000010000000000800003c7a7a11820461da1c44e471020231a8fa89b8b17c78c38c9a22645fe2b47f253fcc38e415b1cf9221a2afd06746e1cd1a781600291c2e33f3d84c4ce4fe690da822ff30be0fb928f0d25c065f9dc706742df7654d313eb7c69ba4b940603a216aeb5aa8a941e6ed53d34a3db1654a4a603599a2fedb0ee754ef2e87c76e81afd010001	\\x23d9d1f19b41dbbde06db104542ce113d6c4e4843a226788bdad2300ca511bbecf3ec550086d04843bf4e0d68fdb967588b7a2d103096bb9644004114deff70b	1670150590000000	1670755390000000	1733827390000000	1828435390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xe77dcdbfecd5a3bb7f8173d3908422e46805b25b347522eb7aec63037ef42682a833e49d806138d14b278eca3efa857d928046b863460a0efb703ffb7f5ed172	1	0	\\x000000010000000000800003a28bcbecb9dfeca48096adb2f92829cf230d3842af5265753bc41b74e7bd59eef67cf5c7e489ba612b3e847719b55680a69a0d59111d00c7ba777d2a84b1da7a93e1bbd089b7e695668cb05216c1a6b097dd16a66a480c0f4c2c2cbaaab8bd387242fe54ec2faf62536f7cbfeec1a433d51ac87d07b7fec932ea9a604ce2be4d010001	\\x30aa4be7fcc3732ccf7333765caa1593b3aec67f339d0c88a1a7a75112886793d527f1253448c9daffb4f8b11419c11eb807cba735109adda2ca390fc1746d05	1659874090000000	1660478890000000	1723550890000000	1818158890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xea51f8d7a9d4cf5bc74912f6f013c4a3e0f7895011a5a4907381059cd838d2a1b06ea5fab13238b6fa9093c0f9f77dd8c31b8259c8cbf98e8c87daa3afe11eee	1	0	\\x000000010000000000800003e1ad6ca37349d6d7fdf3347d1e0971beacb6beb86623b4e65e67df76bb676470e47369e80f15b51f674ba6a08704e22266e599d9baf5029c41866b1415e91960a43cd8e0634b2a8cb5a8c2ae77326fc2774a9d2d72e9de58beeb86bbbfe6152132a6017e14575937d91bacf119b4699209b695f4d282c8e1c4a91a4c60b34299010001	\\x059add4e9a83db7ff2293f1ffef7df85002162c12b109e39ff11528e6db7c4773db928806b3d559c149bbcf7d6d447d7aed41c45418d72dfcf81524205d80107	1664105590000000	1664710390000000	1727782390000000	1822390390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xecd1929ad05147fc16728fffbba92a97fde401fc8ce3fdfb1756e672671e59380c8c8da8adfe7bc27839aaa28be7e596569e8b9aa2b939027e5ef29ce38d1e58	1	0	\\x000000010000000000800003ae446b8187c15302a71abfbda23d55249fc41b8aa6a287194df034f8507f1e98a422f9187d80094af33c69a0d83185d0724ac852e5bcedcc5f8544ebfeb2b41667b71024a0e50af7adcefaf4b15e306df284a09501ccc2483bafd45d6be2feb54cddccfdef61581450e9d76cc2c8e72b513a23d86dfd369b80ad6861266b6bc5010001	\\xa8406c91a1c3b019894dbb34dfe5b1cb1ec8f66fce7379743ff6e1194622c1342a507cbd03b1d8ed092e471adebbb5421178d410ecd85a51e691d43d3cb8db0b	1674986590000000	1675591390000000	1738663390000000	1833271390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xeddd5b5bec049e9563fb6f9874dbcb20fd0889f162cf70e6876ad7145215d1cc0a9e5a514a3e4bef4fc69d13e125aaddaaf62f8273e385e722437cb939a619c8	1	0	\\x000000010000000000800003cd744c986181b567952ac260865e05bbf905bd686f376bbab69e7fea53431a5df3598985817d9161375954cb28ca4cb174166fe3b0d4fd1b2a2daec5f584ae293959749ddb08e478e6a2844aa12f9330914a652510e0de698eddacd9dcf8dd1a1c4a954c9c445649c8011e4ca38f61c39d1b396fce616044542c45a9081bfeb1010001	\\x9b3e42584dd3ef5f97239c8198fa6e9dc904a78751c1a281bc7d6da99fc1e27c4cc76588b322727e7d84d68f6a02d7e6194e12f9b4e65e9e48206af8824f5b0e	1659874090000000	1660478890000000	1723550890000000	1818158890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
185	\\xef69f171593ff6273f6d0b01e0a5cbfe1ded31bcd543f8af3ca087914d73562b49c147f7dff6c2582603889563e022dd470edd5d2cf4ba6550d2ca977bc1e755	1	0	\\x000000010000000000800003dafbbdfcfc9174de8591de5628ddbd10cdd026f9fa0ad7c8de053cda2237d01912cecf1cb101653506e6b3af5dec3f628bce235e18b892a99b2a1bca2135e7c97a5730716135efcaa06d3c5612d2cbad3517955d77b7dbad5da08221afa75275d78d1c94f0b6a3bf383b0cb430b7a454af3ddce68011512ba16deb7b39ab8dad010001	\\x59d3055dc0ac205be4024bfc32a96155a605d52cf2345d992b67248fb83f8d30165d0e3e86c5354bf06429aabe7a28326ee5fac7c26bec5befb6ee46cc2a3d0c	1676800090000000	1677404890000000	1740476890000000	1835084890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\xf0f144330df95c14217f76d61833ac152ebfe6058da07625e6a348596e3d5c539ecffddb4c7fb1ef8c979534b3c5948e399a780770bc9a3ef03da4750a521a79	1	0	\\x000000010000000000800003b55fd0998fd55cc1fbb6d50a5eb97dc93c0e12c29077ddccd768b97cf389775daa35a03bb42f2f3c0e7357b9d0ebea0152cc67a53978105911101e47b577355df59c4a364ba7dd79ffda6c0cf222e72d2591a6d3010a40d91585d4dff48766ff4a7e38f209b17fe8f0929b1fd595f4eedaf5224ba03500471aa4a845e4f871b9010001	\\x490ea2707e931646703a19e10d74e079300be7098a84d551787149338b68876d6a6b23c2130dd19ac20174de37d6bc89219761463c1c7361e4b3fd6c352e9a06	1668941590000000	1669546390000000	1732618390000000	1827226390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xf2fd460f967b696e8aded4d0ba83312a61b374da1dac308e876a4a3e7074bbef45b5cc5976eaf12338aab3cc3acf65de2e2a4e977c0050f3ccd067c2996c0489	1	0	\\x000000010000000000800003e10f9ce8d1a7d36f3fa966cb8a4a1643aa2f4ced085e368ec6b71f4bb7714436693898a3dfc4100cfd9f722a25359b903d51ca0bc9ab2e078359605c1d60093702c8b80c077394dc831cc11031272c4cc80db8c6b3b58b0cd5e3b4b185c8dd862d91ace0bb8b6706d0f67331f0451ac7ec6ac117aba9723afbff4f0ce5455dc5010001	\\x9b477efeeaa9787028fb27536be3d2b80c8216ba29bbd53fa2adcde47e833cecb62d392c2efb3624a5399f5b43a8408d416f684eafcdacd3bad7b0587ae1030c	1689494590000000	1690099390000000	1753171390000000	1847779390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
188	\\xf36943d69c5d87bb5a8a0f42d1f96e14db040bdc72f593a7b55154359fa6a5fc27294117b8a2221daa688d32f5c47e2e2b97f1c7d55aa9a73bccbc1b68b1b5b7	1	0	\\x00000001000000000080000393975f4cf7502cb28eb1795d1fdd8ac51aae9babe6e0b698116ab0ca2850377dfd161a95f635a9f7f5fd2bc6525938bc24dae3da146c50b738ba2f074b5b459628f5577e364f4bdc9f0440e53a937e4bdda476944c3a00fea37b7493ef170ea5580858d511144828892f08a3728ec48fb681ef26d39bafdf05f77a108db6c795010001	\\x77351afc5f1d517a69c8a0cad54b5dc9b061c4d2bf2d7e864913e8700bdde6ee46566b626fb0d3326e7db107891e37e34b859a312f8c387bf36a0f6b652cec02	1682240590000000	1682845390000000	1745917390000000	1840525390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
189	\\xf6314ba078bbde74e06c408e46a8869bc6e048a8a2d7d57c14c3652e5f7413f26105e29f6ef07745b011b1a528c33a696212affa94cd37bc8fc28014b6d1665f	1	0	\\x000000010000000000800003c09b8035c0ecd991e9c32eef3c1ad6fafbfb9ce71accbf484044b771527ccade5746102775ad66d2c2f4332a8cbf64079731959e5fa7982eecef959e72454e61be9971cc9f9c6e1ecd162a85a4d2847147febc5a1e1b972820665b953af7c338bdfa8749d72c1b304b0a17e0f6dfd8eecf94699c396d75420c4aebc83a62bb4f010001	\\x01076dd1b4be11c1621c5fadfc4fb4835a96bb593e74591f563b11d1ae0fd8b0b82fa6ae8799b5469e6cddd9d38f7b9de7381404267674390c155a951c1dc209	1685263090000000	1685867890000000	1748939890000000	1843547890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xf69da291e0eb8b030d3106430a616b5a78fa6fffc975c50beb54955b523fc5f1411182a8b4ea198a541c9811d62efb3dd74179241937cf445d544b466df77fbd	1	0	\\x000000010000000000800003c6ff2022feb94647f522845b3e6787ebc239a035c97da808d3e6913018e3fa5f851137546885613b048150ed5cc4fa5075b8fcbc5d46b975553d3b2dfc8aa77d3a36e2a29abcae03d1311edb68d6b012638f992c1d7c8746155b0b7dafda9d1bd02b59a29a7b2a27402f6fcc1b75173c5ce1dd0bb9a40af87588b8e545924f57010001	\\x8d08a6f6c8caa0acc3e3fba1c648c3b9cedfce8a834b01623334b51daad62b9a618c85d6b692986de74405f8d514d3340b039df95eb07da02767cd3be08b540e	1681636090000000	1682240890000000	1745312890000000	1839920890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
191	\\xf759e12b1f4b09456f03b75dc22894ede7f9f7f1912982ebf6f433546feeb7c1d96d1e863ac2dac5a42787dd719bac2867ee4e83a2f3dced8a5d742fc41ea45d	1	0	\\x000000010000000000800003e4d2432419f320438961367f725cc5f72338a40505af51457675abd7de00b42d21b0af1ac5b62d99284ce40ddb765e88f9acaeedd4f990ac1387d51b0ec5405bce836f21d2c7d9dd58e50aa3465a79e91c6120cf180ece2c2920ca9cf95b602096ae345aea35132dca3fcc52f64a612089d93f2499fb07dcea4528592dc7a2c9010001	\\x96d97d849ab22082477e9b95a0a40313acdb73e5d6712cef50b8d12e86bd5a538655abeecd82f211247da4bfb8f481e02336b39d9b8e405d0b95de651dae3f08	1667128090000000	1667732890000000	1730804890000000	1825412890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
192	\\xf9d56b06f38cd349bcb8df7482323379cb08e114eae9f7b7dd0355ca8f4c25d7904d9d37a2b13ee2e014f3beb0bc5fa9eb28e2439b2f9390f677366fb294a73d	1	0	\\x000000010000000000800003bd6348c22404a29e98f37f0afdbf58a6313a2d9295bbf97eb3fe46425ea0755c0c3d8f1308941bd7a25b1cd15456b7cca17b7df068267bf35e8276568911e67aba32854c0df88cbac3b49af30db38eb6674aa30c7ff07c8365d0f7da5d76bebb9dddf62e144e2adaafa599ca59fac44a0d899437510dfb6552b6cb3d52268da5010001	\\x52fad35f9d2beb265d7f6cbfe5dcc3668eeb7253892337f25560a0e6fb5f733c76a3c991b55c581be1466a4d19a7f0512d1a685982e640bb5f909a302886a503	1673173090000000	1673777890000000	1736849890000000	1831457890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
193	\\xfb3daff551e2b25531ca8d884780bb56fd8123cd92e94372b75e00f3778cf266bcf39519d04399d30c1abbc2753cfc10f6daff57388e857fdd4e0dd5f27b4274	1	0	\\x000000010000000000800003a69d4d63371a39d2755b8ae71e531514405c66a4e40f33a8c2877d72b4595d268a1fa52ba70d41a891bc2ec2bd2e5be38498bc2229225baeb3f9bd8337a0ad6d459ea34b08a57c75f46eff5d99312a97a4dc6288a85b8d34ffc7bc60bf96941ae152fc3ce41fb864544249f549746925e72b71667126fac12d5f06928df73e6d010001	\\x84e2a4eb1a8e7da3ef1cb900a554ea837f440a09abd3e2112293236f768ebd9a3b2678847052d6194cf43b80813bccfaa78ec7bae0332aa73f1259272f6d1b0f	1688890090000000	1689494890000000	1752566890000000	1847174890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
194	\\x03da07399c1880a8580a25c29e4368bbfcc5faf45d742c135ade5bc20d230a7e743ab3c5f9fdfa889a79f8b05db54e213adf50445961b98bee6ac3d35f731abd	1	0	\\x000000010000000000800003aefd4020843a3cdb1585c6a4da3f88fc51daa79727699dca80f93f14d36f5b236d58fd2775b8823f0b1b620f4ba120617d7fd4895b3dd6cbc936786fec7dee24935776b369a3696ee71654c6b6be19d87a711d701c2c44654dda686d855135442402a664ee63bdd48f5adacd2dafbf0a872e8f8a155d3e3fc8e7b2ecc6fb5321010001	\\xa5a04cd4c3685f109f69321e7b69a8b7fb751851185f7a65fd6554d36be9c04885188fad1e5ca7f8bfb096575176c05c7d66e62c0bed560428ebbf2e394bbd00	1671359590000000	1671964390000000	1735036390000000	1829644390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\x03d6906d647ee341a234fbe089519c515cfe1b49f6ff0aa0ce8b6eb0d4419ff895969eaf544b7671dfb440d114fa08ab382aab65c202783c1e32074ec3847084	1	0	\\x000000010000000000800003b9614318e36962ebb6007da91367a97471bc2bb62e5e64de122f3b3c4acc3fc20144f90fb96fded028c72592cf0d2e795529ee9b7f2c46680453cfa5ff4ee5e2baac8bc2e79356f728cfec97ee1505d6b4ed5035886fd073263b38ee9781ae7e4a2a9fb5a2b9fdaa84c1ab85bffcb8643bbe9c0705fcd51ac11cd9995b18871f010001	\\x04e34bd4a04dbaed652033c77cb8e9bb7cb20f8080f23b9acd2315814ef2546514c41c333e14e4019a3de6f1e6a563692cff49ab90cc45ea3b1afb268ba3d700	1669546090000000	1670150890000000	1733222890000000	1827830890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\x05e229e09bd663d30443503b1a3da3d0d39f7e3a61ae7da8559731e6c9760b6c9cc479e0876b3711d578d4b6f1307758253501c94ef129b9f19194e08ffb4c64	1	0	\\x000000010000000000800003d16841c9688f6ae0c10cc335393b90a38078a05daa1866d182e722e7322a3e76eeef314e96871824cb9b9edd4c3ca55e64fa328aa14a60123e1e19acee52868fcc5f2b369222768aa41c561b84ad4610956fa91be96ff4092f4ccd421ab5ee633ad9d1ac40584f19739b1bf545edb1bd1e1e5ae24398616b38b4bb7f0363904f010001	\\x9ac480766bc7bda56184cb01e6f518471b12e7a028c5815112937a2a8998e8dc133f2bb31656c6e856e97b57dd5dda80b7c38748a5513ad3d865dada7e7fff0f	1676195590000000	1676800390000000	1739872390000000	1834480390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\x070ac4954a4b0f9e2ec5709d4db9fd87d60170c5a1c0d5ce642e1f30e1af46b18244dd39edf4b1b7f020cecb97b56b924e5477110e62028a497e6d8b7bdb13f2	1	0	\\x000000010000000000800003ca606c7b1a6a6d99483054b8b5f5e190f99e5745138a2f0650571a06b261d4decc3f9b38f082a683ba72e9a1665796c358539c538a3af9f397fd680b1eec0208a54cedd890dd31267f4cf0723ce9c1ec051025d7ed1c0af01232b5e549acf765af1dabdd34eb63e1ddb324e5ffd5619d46f482682567c5e1b37d26ce480be263010001	\\x5861f569c21f9a0de100c2a8683b04a98d95b6969234b70de32d6df1417cca99bed48eabc76751e1c627f5664bd72f9aacf5e5759cb94421873314dd6b032a09	1668337090000000	1668941890000000	1732013890000000	1826621890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\x070a69550b895ade71a6364cc41367bac86feb58514a1c8ceab2ca6e72e1b6b4792851dbf23c15291d2067aadda2e97b3573ce84a03a8335e0aed0c9223098ed	1	0	\\x000000010000000000800003d3ea26ce12f3232ec3b51803701456f8f0749180f5ddd3d19ed20f87463bca9c27c08572295ae72846cc5584cfb3c65636640471363fcfaff3e5ef90d20296e602a32e31550b75fcf986a54a155a8ab3a97e596efafc6a1b14cb632c4bc67c03d444a46e4b491ec9996d931cf9f31cec61ff6b72cb203aa19d2679dfc4932d1d010001	\\xfa740bd7b27d03188d8edd06fbd2035238839e7b186470449af403298a66c10355b60a03cc810b073d43df4dcb53529681514eb7679f5cd3fcc84c437b5d4208	1661083090000000	1661687890000000	1724759890000000	1819367890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
199	\\x08de8393828a6b3a7491d71cce1d3ee523a89caa02f9f23cc9518fba8db630ecb76370e79d3fea17ecf0cdac5f98871bbca6a84aebdc0ea50d589d6c7d44a001	1	0	\\x0000000100000000008000039362b6d5c65885b787d418434c11f291f275d99d71353d28a6d77ea7f11b3af66c7f162179f104b3614a56b8c780b83795742fd5ce773c879ecacb3be7f6bfe2538cfd8dd28b715c798f0b8f628b8c7eb6fe45314145b13bbc068384dcbaa6ac78331f2c13c99acb5fb85393453839473e831b519ee0adc1a1b58d76cc491d5b010001	\\xcd5f13fa000487fe2c48f2c583603523a7453052852a306eb58df862f75e8c58b5a794f7b554c4f460c6d527daa705735624492fd817cefccdbba5f76236b004	1674986590000000	1675591390000000	1738663390000000	1833271390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\x09fab98dab202d03050bfa8cf703321f44dce6b31341dc2b1897a47e6d3e76bd16c667a896387856c99ece869eceb9a1230f41b3a7bb065b1d58c066dab6891f	1	0	\\x000000010000000000800003bedfe33ea1c9223797818407d5a9acb2b265491091787cfcebf1dc08348b5314166d1c1c595eca8e50cf541e5acd5b12dbbef8788132d55984e995f096ebc308aaac6143cda6b6dfadd796cb86852181f73eb815e087a2e4b39c793c517fbabf8d98e23efe19f71603c5ecc1c552b584dde4fd9f99ef042a0fb6c5d55ade1a4d010001	\\xada5fccc0991ff64af3860a7e7192182ea02cf149c1b3b80edb54092121a04526079ad04802fb23c8dcb01a5176f02aafd620da0bfc7d766eec76295b3072d09	1674382090000000	1674986890000000	1738058890000000	1832666890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\x0ad213114087d9c7ca58375b99c7727e7d7ab104414bb3900ad76231fe5601658a8ab1564c622d0038826e61384c7eae4bc3305adb82fe29e14dd412c8bddba4	1	0	\\x000000010000000000800003d8691e46e5be50fd7f8812dc576a24ace98a53a3f840c3ef112a5d433dd4eee2505bde6054c4bae70eb9d0927b669dc50b217d511adf87123c064c0711bcaea3b0ed47dd55091062131801e7fb5c5be823775c3cfebe3846ada8dea14552d20ad332849ce66422c53ea5e3860f7d229d870d39a5c54b1c040079db8973243373010001	\\x401cbb13e72c9f03718e2cc64b082576353711e854161c6166628baba820b09cc1e63acce5f040ddfefd201bd27bf0c882723a461906672932a47c9385ae4107	1677404590000000	1678009390000000	1741081390000000	1835689390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
202	\\x0f0ad32824b0a35bc31d969d8c9e39faee2d5a415d8457c9c69825649246e63bf8ad20d64c3260124e9449fc9947449dde43e5657e1a48b2ae6ba72ae5987eb5	1	0	\\x000000010000000000800003baaec15dba22c21b16d4c3efbfce7734bb6143b7802a18d52f8772cee53d005017e22639e57777d24cefa731e8008ab03b46281ddd8ef50ed9e3aa4d7741b550d3c08169401719e32a8055f4cd00989dd97a1e81daefe5b8314b948a83512ec3c0740233bf4ae010b46758f5b056a340f305197b029588f0f63f3422be2b994d010001	\\x9f85bf00eaf054732e9004294cf2b6cb2dc793f0dde0094fa0703ba1cba3952b352781274f38bfd1f7d4f548a042b148afb1c0999c3851efdbf58eb5e5dcd306	1691308090000000	1691912890000000	1754984890000000	1849592890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\x13561c29f267ed3d58fa8232f1fa9ca06f82927334adda2b79f73d760caf7b8d58504be0e3e44f01a8bd6da238be155147983907cf157b49841009cc79a55344	1	0	\\x000000010000000000800003b06c4e9ea9705f3bb7f252149e6ca8a41d90967f6e7630f42b83118eab987f387e027017354dc8fc9521f04c3c16e55c768a34e0b173658f69c7d05bdff4183aac7b90382b0eaec7c6b056350408d3b35585da101326dfd51f680664ab580ca020fdfec2e95056a33dede67c32ca911058016af5457e51a95a03f19075fe23e3010001	\\x21d8795631a2b44698967e9ae8c2f94c8b7b2aa29e7be4242da0973a152d5875868da4e3ed467854087657a34bdfa0ea6873470c71bfb94bef655bfba8681702	1665314590000000	1665919390000000	1728991390000000	1823599390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\x13faac27d8aed45e0ad7a43885c1ee8023845640d1e88b4d2148d099a973dc32f826b360327826afa9d7b1a6bf6d19514211208fa1f4dff0a4c35df60905fa93	1	0	\\x000000010000000000800003bd089402bd3b323c7fb8d78175ffe18bdce0c236a5de839064e8545d9ff7c50ef6c24fb7fd27806bd46b1960da1f6fa0d19b867201cc08efc9fac0d3eefdcabb500bdbd9b51973593b505fccf9477961d69b923537d1822b8aded6a197d416c7e672e98e82cb3d0d712685a30a23f46507dd6bfece6ed78720cf581009f42959010001	\\x2daee5e39933ad48021b930865e57c34b71e3336e100b00d120389cf773e6e5a956f9d2d224520be44482131688d8fab35a3971d5c32be29f58d389ee90e7300	1687681090000000	1688285890000000	1751357890000000	1845965890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\x14a294b557a092a704f1445bc9c56511e4c8f1337693edb884f45eb78697b926f720310c076864c13001d42c99394c55a1603ca360877de9496f4634b3aa10c6	1	0	\\x000000010000000000800003a7aee510ee15600f8f1be394b3b34addb341cfec987aea102fd641a04e4cf8c99952ad076a91906a2bd6128c485414d4c808f004944b10cd98e35c3ddc4a5ec15a6c52734690e912b231c9f0d8dce888c2498476f2aeff539ffbcdb052722445b11ba785ed143d117072fd5b28323a06bd1714e537aa7113d3c26f6abb1c91f7010001	\\x3c3537b641bf421828a93efc8d79a73de4ab327a65ab11000c99265e106af7a972a087705e0b51ed7309b3f8e4720c4aa3a0c613835bb3f320c4aafdf0126901	1684658590000000	1685263390000000	1748335390000000	1842943390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
206	\\x17aa60fc930635c5bfec6e5c87e2a8989dbb933882c2f98fb399456e632220379da69b82517f3bb9ce762fd9ad4c4ac730492a8a8ed5e8bcfe23fef96621be3f	1	0	\\x000000010000000000800003a7c8403e6f679f1615e5577514eb31907d3ff2e6bc08847a14c67db88aac2120ef91a8f22792bb8b172ac8d6b18d9f8e4f75f65075e593268357e6e61d5f28a087255602e1f9ecbb47b78bb0ef731f925d387d11726f28431235dab1f2a2136909e821d8784c35089c510f8c7a431b85b157eddf4a7a15c126c0e0f3ddbdb7a1010001	\\xe4b4d289cb2cf2a6878d86915d4332d32dcf1b0264f397dd5b6b36b55893135862d1efcb10169a9b689b3862ff0851315e7e11f0033f474ef463f1e3dc9fac03	1665314590000000	1665919390000000	1728991390000000	1823599390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\x19da820838f5b0d79e5f2ed5c5d5a3f4da94a16b91792528331addfc760270d48eb9b695ff4f2c0f5b5331f1790da1d14d887acafd0241956ea0e5c070f7adc4	1	0	\\x000000010000000000800003b356a755b83e60731ff38eb2eaba2f0c32d1e8925e24cb879253c590a70db6e4b51316e9f4474cf89c2e70f1d1b9a4419c55437e822cc00aa43e3282d4b67827f065c88727aec9c7d25f21c63ad7694ba501c82ac0baf5109e61ed21a1f7c0796e800dc7f2b97d4b80a709cc75c9d497cb50978599e2f3053679760ebb7a4dcf010001	\\x1b71e5b7827b03db49396e1e1dc172a2f335031bde54f347639390aa80785ca7f5fb3a3c536823a6076b86ee0849cce8b5f7f08687ab47d61e17173d43eb380e	1691308090000000	1691912890000000	1754984890000000	1849592890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\x1df6d9c4c4382487532814f15c95883a8591f7955dbedc61d278d8c337d944a1ef877494ab5b95311ccea7d8f92d4cb9b2301a73e186262547a52705c32f4dc4	1	0	\\x000000010000000000800003e7259c3cc92030c361aa0550ebf19f685b86fcf1a4aa71d427cf3529225ab1be0ddb5a7598705418a21817feaf7c0889c6b6a53c5ff11ccca451b95243432b6f2d773eea1683c06c1d0d2e165753349d695ba46bc4bde20893527fd2cb76b9b7c10d30f0f1931e3f95c1cdd5f06e0fe571726a20dd7886906f6f546cd0c3e99d010001	\\x1742e5a77eaeefd249f9c4032473dea4cb7ec6f510eb4eeb38e3266dd7938e03be6379e40a6e4ec6868e458a4a8ebd597db407b14b158dfad43ca5e3a86a470d	1687076590000000	1687681390000000	1750753390000000	1845361390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
209	\\x1f4e979db6200fd929752cee3681ac9c4c06cebdad7e160076d543275251fb9e0814f113f43507c3703a420ab031d87902f6640e1c77e3c566d1ac8aad6aeb2a	1	0	\\x000000010000000000800003aee0ef09d5d2f1a7a27eeb0a1d0360de68edf18921cdeb49cc7c0b3b3692c2ab3ffdbaf0ab1e972800fd79a1e0b25985a008906c95b5a4ae0996623c6581b7b53ecc6c80f60493b1a0d3045212c6fe2bc9e5a79749bf9cbb5554aaaa91ced9c183ec2af6deceaf28c0e4965edbba894d76fe7ba9c5435fcf1fed13661b15c7d5010001	\\x801f10cfb88985d315448d5053bc34471d339033a6d1e2305c6ae8bb56ad13ba2ac1fc5e49e216b8562b3aa930e4e3ce3a8eceb26d134f374df85abb23f2ef08	1682240590000000	1682845390000000	1745917390000000	1840525390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\x22de9c8476c1598759f7921888e5073b8ec2eee8db4597f0b5709cca0ff9739e0d3985f608e0bbaed428bb1daf3b6631865731572aae1c0b1ef9810d4ee1c0b8	1	0	\\x000000010000000000800003c14f30a8208a8b65341a083888024d3b3df89c02d4341eb8716eb4f74ef34a04d3017ec744bc5422ed6f45145f7e99c78e084f1ee6ce0962a934eb7fddb5dd28dfebdb01b9e9747c11554ca53a08af16cf4316836ecb3f1bae0f4241445b5cbe76bdf796c0242aaeebc8cf4e0033a91aed2d88c97f6d3177207e04569c982025010001	\\xaa51e4972e089ff1f8923a3466bada93da94dc3dd41b3f4288b81392a096f83a17e4b77f77e5eab8ba7e287ead340d5fbf86e20f3476b57fac92fe9ae3142100	1690703590000000	1691308390000000	1754380390000000	1848988390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\x22befa1f15f8cea1e739604f1a8b20bb3b638b98b05d0116688139968a6f642437b443761f48cbffb30b78e9c2590a88e62578bd55868aad9f0b60aa44e2885e	1	0	\\x00000001000000000080000395dee55fd99d0d69f215ae9d3dc4dd160e37d512b63ad4810a2104573f6f5b41e7882a059a48eb44798650172ca77c25538ea3fdd7073343379cd12ac1be3966c6f15e1f7145ec97c7712dde4fc67527172a53aecf4731851df25e1c458c1b4909b23560650c50c752a60ed3ffbb1a7812f2217b6da768e5d450c96177ee1101010001	\\xa08d4ec282cebaadaa7abc8e2a243e72171187b72cf6c3ffca3566ed44aac45d46221358b45bacfa99963963301e464903fb80e4c8a01c6c26625a22fcca4f07	1662292090000000	1662896890000000	1725968890000000	1820576890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\x225a565ade3f28a8e906dc20d52cdabd08fc7bfa35e31a851345cf872fe8e04b166ba6ba5fc61c9ecdbbee9ed6328cc56a0b449740bab2557202103752cd55f6	1	0	\\x0000000100000000008000039b3c00ebb0adbed0d3a3cd292c1a11197c0b8514270cc3900e04b44433332161885354bc5d8925842c28c9a8bb9064c63f74e333933a24d33c021f6e1ff7cd912f1e1bda75aef6e0a59f884c98f4b041c222a0f93aa2f91a8e884b52de7af73f0e997696a2700bc54d0ed7dd2f0bf360e4737fbedc57f8e283c89fd3e2938c93010001	\\x5a287ed05040765e97e52252e95c27990f9ed6f3ff5d2e567eecf72768c5baeab6e15ad67f52c538742a58cf6c65866ad076bf6b8a426fb9e01a008f0a6b680c	1660478590000000	1661083390000000	1724155390000000	1818763390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
213	\\x263a8526fd9b8bae2c96252e44f08e788b2d4d14d93f76235e9548da62bf940b6c2935fe1382da2f224970225aeb6f3af4505a50683b1829f2276c23e4253d4f	1	0	\\x0000000100000000008000039953fb7bc114319ccba5fc9d8ef8493b93c84676c7cfe382dc716842efeae64b70fae04588ac50f4889b83ab05b2b60ac023ec9d2af71a8910fb7e1bd2300d73608798dc9044fa4be71a04b56be97dc67a20169b89311bbdc61cca8f981cc0999fd543380a6a626f2adecfab128902f0c586690f2962f301b829b345a6c0616d010001	\\xe82539ebfcaaf299f7e88ba98dec9f19efe07ecf184bd295dc89e2af8ea5b0bc798bc159f181c0027b10d6fbcc3d7b1fecc6f95bb75d5bd3a96eff9ef4d3a809	1660478590000000	1661083390000000	1724155390000000	1818763390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
214	\\x2a723f4a353771bf7053dba832f1b85e4cf2f88a7f1e267e9dbbf23dbbf0eaa80e629fc8d82887e75c2439e6a04d1174cace22bb65acd429e1005123c2c3cf7a	1	0	\\x000000010000000000800003d8659aeeb7a96f2c6a7917cbcbdf46090e2badfd290e83c85c4d6084adc31777e122950b404a17938a55095696e745b8eb8e4ed33b8e4f190fb1d74911c764efaf60cea647283941f93f2423a1701ee0e4a117fcdcb2e9211611b4aa6c70ef470520f95b534bdc2257df640617faac8ea42a2dc913fb02aaecd8c42a253f1fed010001	\\xe41b19e560dfe8ed400dc3001b5affae0655354f22a9623307cd441f94ec340f47dd3bbf870e811e28251d52c73d1f6e3bac0c4470091f133e4081772a7cdb0c	1676800090000000	1677404890000000	1740476890000000	1835084890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\x2a06ce681d249364b11f48ae59fe5b9682455226ba6f88e5b139626bc496c4044b1b5cb98a57741d9a37f78b4e7f900037af127328aba985fa8e1bdef7f349fd	1	0	\\x000000010000000000800003b3ab220d416a3c98b633bd48451e5e21f80793711e77038653ee5e3ebe47bb78f135b7347711a5cdfb09689eaa89f507e567b1e1a5d6628be2b72c3429807486ed9cbf0474ed9257c5fda9308e265b2466e5d147dd56bf7f51571278aa79693877bd2e26c3c0ee5e9d7a3b6a5199dbc4623b6fb48f68384e91a2cc5e9ce2a861010001	\\x525806d0c423177f5800641158e8da773a944ac51a7949534896387d4b68215f0c229a25c8212cf582193afac39ee00371eeb099a915b14beab6795ac64b3203	1671359590000000	1671964390000000	1735036390000000	1829644390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x2a825dbf4f373b901986b62d4ef253c97d69c2087d58923b239a13da2b75653cc7e185f316909b3017d061f8e10bfebabe550c2928c5aaf3719239fbe94077d6	1	0	\\x000000010000000000800003d08834cc81f2cff0498620cfe52f096cdee6d6c94f686a9a7e30fdceb3143f544bab3cbccac0fb584e93480740a01ed0cd1ba4655c5932c58374166a73050c26ba7de1811976b9381eacc7b38203f7cab9ca97da537b9576a81e964d1e039cc6e44363492a2257e5072c0c7c1b38d666609368404f2564f505202df2e136534d010001	\\x05e1d8115a74d2a1dc7bbd0b098559d3a05e3f54deaa9d0bbff3ebbe6d40eb003238f928cf516992aa12d673f9757d4ce11d094b5b8bd0bbf78ec17c2fc3c904	1677404590000000	1678009390000000	1741081390000000	1835689390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
217	\\x336a6e4d2f7821d76d8b2cf254e2c436ded2ac17163cee8a4710830913ba7a6af29c92972fd3ff35eaf32831e46c33b6502479f8bb4cf9a5d2c6d13377e29278	1	0	\\x000000010000000000800003db5828c2ccb36afa891aa63ca382dddc4036348508dbea1e36e6ba62b6d0158c149b0b42e541012f42845499a5355d1d21e755625956067aac0b5b87f2bbc55095e50613352648e64e506fe75fa32076528ea73326ce3527a078c445b60d9016393cd59191b960729eda572df595f82e54cd4946ecb4e9671b69bf02b9766859010001	\\xe4335bc4f6b7a42d228771bc46250873dff3fdabd05910ba7a2645e07becbaee0cca303d5c3f4f539c5d9eba75efab0c591b5917554152ce035c21569540f10a	1678009090000000	1678613890000000	1741685890000000	1836293890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x33122aabb1d58e2f14148c8e76dd363a7245eee918f4e7c4a634ea3d539ac07b2470f3d550426e4bb5a7f61cf12a0138fe29b6a711d95c4d8efd792a1b8f8eca	1	0	\\x000000010000000000800003d40e1d5ed0f3e39bdfb39769257d33acf4b0f621c1e9dbe4fb8dd731c706882fe2a5281847708a10039cb9da1795b5d27f9a231cb30508cb4f799b29e088cb4b79733e05c8b02483ccb4dab84c1faa0cbad55b74d55187da8734bd03e0d4d925c2674c9e3e078502361b7fd0272d4d9e50d0b34d4116c5aaa53037a0ff24b4af010001	\\x1516184951ef00450f30f6e31454e7928f4187e302a716a8393813ce7d216f1ec10aa19b1ea99c276f15d47fb5e2c9077b34f3945c0be6a733e8a33b1c6dbb03	1661083090000000	1661687890000000	1724759890000000	1819367890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x3caad1ef551fd83cac13f277735497959f2614cf4888b6105b01a1b0130a861922b9c24d866416da36aa6d11d86d43119f04484ad5ad1d6c6053d4e61dae1b14	1	0	\\x000000010000000000800003e2693648f20121d030b776511039ee3640759e716c08488684e5520c90da0e9d5f65f94158824461df662c10b6ee7163dfa618f3d914e6a3b18aca40079a981a5ea6e4d12bbe98f7bbbd5c9fbe26d98159388caa30003ac297edb3ffeebd27095cd0d2ee56cc34347c3ae115afc4984cef183f97a60671bb54486aaf98e11085010001	\\xd6100cfae937c143d4a025c831c07f45b3293586275ba5b579e1763823e13214d9079ec8980f58ecee0937c33ea65cb1edf462692e4dfb64c040f5ceabe4f209	1687681090000000	1688285890000000	1751357890000000	1845965890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x3ef24884271ebab8e48442bf31221386ca34374593036b568ac0579b574b577ea8257c5d5bddf4ae97b0c2268d91923125e36083327ec89f1573941142ad690e	1	0	\\x000000010000000000800003ad1e9f4d33a77166ce00c6b2c014c06bb6d903922b7ee4e2708f0ea1de0076bcc837ea704e7eae809e1aa48b75bf8d15f485663f6678e8e4180a53d7d20c61d6046416af6940d0db99ad428a49cf1bc64a25b67c54b59bec3f1baaa3e2465884de1c49317dd1803b600e9e24c6bf62d502dcc187f307069c06d9de0afe475301010001	\\xcbe2dde49ee58e345ba4d57827d73d1cc9ddeff24e8388c97e408d20bcbb9a62bd9206b90b00e82fe371e788cd8c4e49345f4cf7865c6f6d969b8ff2b5767f01	1681636090000000	1682240890000000	1745312890000000	1839920890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
221	\\x3f3efd3e0eb4ea202efabbba5c60d493c4ffc916c2021df39b282d7861c6caa8c884402b7e88353d60471d63eaff8482924c34b4b2ad8e120afccc8fe4a72402	1	0	\\x000000010000000000800003ad66aada3ddc99efa6dcec9b290b2da4985a73a04318954c5da854fa4f8cdfb538730fa0026d0b89bcd0a0d783848f1d56f5a8a8fb338b6c8ac5bfe4559f5782ef39c2d08fd03f6e6d5d06b1c3833f2815a043d5b92296e2e536a9d4ab3368618c2188217b8f37f3f18fcc29214ca1f7dfc472d76d55bdc3c0af57538c69ca77010001	\\x443e51118a2e262c3acf78abd3017ef36447b6ac883841b676bd09e64078944dd8f78e29ea94f31cbc76572d15dc24988baa933f3912d618e3ee615e83263105	1688890090000000	1689494890000000	1752566890000000	1847174890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
222	\\x40fefb84a36ad339a568650fc664391dbbeb447d613326f96e1935330e601a64ec4379e2ee3ca783f75b730bfc02a0a9a1a320a12a90a2dac292e6707d11da02	1	0	\\x000000010000000000800003ca7d08a0d77dc75b1e35670d5900d6146c94b971cc38e8f0efb7f002f56fc54a874a355e96301578febae5e298b61cddcf2131ca458a1a5f74e97978d7764475a4d9b0ee19b3b60f16a39c7dbee454dae68c05559e5fb90713662452ca472f8917fa2d55d16ff3314a9a3b2376faacac670d1f2a23cb8c6cce7caccd7d136cfb010001	\\x4d3f7ebe025fe648e39d4a7501e584525660e6a0396bbf83961cd2a60a107c10cf89ec4cdf1b847e428f168575b4cf2302ba3c41a9e1ae60d813bc92e0a94d03	1681031590000000	1681636390000000	1744708390000000	1839316390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x401e4c10aadd3d50cf605b468916becbcc5001556120161479ba4b640929009abbfdbbc5ed0882f7301bd6304f02af3d4a263501eb6f023df5f310858885192f	1	0	\\x000000010000000000800003cc8f70e361d953f3ac720bc31d1e4c82ef5d3c9d10ff6c4b39a2169df512348757649aa4799d41917f25080a5d47a04fc3264312b73de900315da827f182824bc69c8a7d572aab4b3dc8cc4d9634c9b4428a278ae1dd0c0119070e9ca2f97e1a54fd66961dfa86000d3337d037f2f0db4640e9beceb9d654d68f1daf726f998f010001	\\xf1b822b9db80ba626b75e9d84851d6fd1765fa37955d841e108a6a58af0aab8d1a69a54b6d0de87bf809b543e6b247bab7dc821c394d0517e0308e8d5b87ca00	1670755090000000	1671359890000000	1734431890000000	1829039890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
224	\\x43fa82818ffb381a959c84dc73f4bd45acf752972ccc68c4a5dc8b376380fa4c37e1d56f31cd15be34dcc69939fa3a9d212ba28fb49d16b8d3c673253c57ada7	1	0	\\x000000010000000000800003b28fbf750c701886c63a2829c9acd010f20bbbdf4ed9ea179cb73ad855f402b9ecb97dae471e9a25aa527e6bd617f7de8e839980033a6b15676d8cd1c3f521e435ca698076e19f756945dcc07de1fe610091b8700aac104f750e4b8f307e67089ef71d65ae3f01e4ef210a7247a22fec005df6285fd6fe92d43902d5c71baa67010001	\\x1268f8cfda831b40dc04925a1281e6240f53e867795bd15cde2987f1c338d7190045d430168db54a2048f8f10dcd0d4fb0cf2885340d061f6782c47c97a19800	1688890090000000	1689494890000000	1752566890000000	1847174890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
225	\\x43aadef71d749557728b9a8e78fc39a7c68b501d3d33a2d5a3a479aaed09bba4ef85acfb81287abb2e422a807d5b5aac1c6d7d7b22f9632d92c97c8a038518ce	1	0	\\x000000010000000000800003f37150d9e8af11f0c4ea6f927671f414c0929bcbc13b79a54bc1da548170a1799c1eec11e9cc6907444592be4016df768ab3ef54cca77673a7063265542c2410f875c5558ff4abfd58fc9e78d9528dabe5dcb03596f4ce4cec0f1718b48650750cbb039524feab0f9bed5bb302531c62721f8f9b5d83616faa1775402b280163010001	\\x21e71c51d8ba4dc7e3da8016bb6fe9d260a8efaccc83eef5ac12cec99581613bd9328599915492fca2afadca9267d79c3f3b8bd80d6887c3e73bc2c9ebc4460b	1686472090000000	1687076890000000	1750148890000000	1844756890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
226	\\x44920a1468dbd8bd9b41204874610ab070a5e0e120e407a5a05c0ef87d3be973621f5ef1357547c229c159bd41f143ac52bc2259dce0a6fe1e97bce7f733a022	1	0	\\x000000010000000000800003b14a8517c1df766699d15e22c66db583256c5372da8306d26558fde131988bc4339b59120ecee884753ad0f33748a89f33aae0899fcf10888b04e25102589e2cf982f18e593265848239141558c1ed2144227abf59ebd48570c5004e00e5b5f67983d146e929d141540dc190ae39e08eec533caf320feb1fa1f593385328b36d010001	\\xe484eb28b4654d44c5904ef3d21cb71b41d76d2f13e1886e4a12924fc485f6e7eb418ad87ca775d61db990c7cec28a5b8150027bae1092f26290940b5d3a1b01	1677404590000000	1678009390000000	1741081390000000	1835689390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
227	\\x47f2fa3e7f72e73b5cf4bd361252cb09d45eecf505ac27874d268347b4e3f029181f9f6597f29ca3d4b31ffc3487aa4b22d713a1e5198093b7dc43e0471f4aa9	1	0	\\x000000010000000000800003e19ce1b13fa4726fcfb8a802748b0f0371cc0da401663b68d34c14a6a83d13e53637e5c0e5443791e00fc710ccb9d8e834574db6d225de79bcb4d58fb5de9c7a636f450d96db424e97a27041cfae6bc8e00a25a64f194e572c56d4b2c870898e3704e0ef02d8cee7156972e63d1f0325c5c5e91137bc2f7e43a63d340e5ce075010001	\\x2c62d8afe1ae74cbaa126feeeef086b6e18e8f47b54088bcb1533b491c7abdc1331d4236b75bf8fcbeabdc1774eedba3e89bc76acba104475437853b25f12403	1668941590000000	1669546390000000	1732618390000000	1827226390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x47e6f2c9f8d2b1a728ab4915871c91457dd22f6c9f3d6ebeac5b2d342a231766f63118dcf2dcf7dac89d37653a2809dadb2c128d9885b19cf24db5ec7e25615a	1	0	\\x000000010000000000800003dbd1162403cbb0f9ccf044f5b88c583471852f10a47ee3b545546d624e3610ab235df7f940b548a776875fdc1d892db63e8f6dff9a1d9fd7700f8fbffd70d62ab6f851e652b6cabb55f2e51f5fc97c26093963722b3eefbf5c2689ef9a86ae0c8750d9f473277c23405f9678637e478f64288ca7715049174fde86a9c6953873010001	\\x042dc229b9622656d3c90e8304f4123b399f70615c776fc788dc917fd1ddf1472ae7202ee31cf6047de1d32d54b2c9f46b457e1eb69b498040c4ccc6d3707209	1683449590000000	1684054390000000	1747126390000000	1841734390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
229	\\x4bce8bca577ac2f8031305af7f3e5ebbbeea2349d3a21be41449720d185c74c05d24d048bf254a8b4d61f883896fbb1a34a7c4e9943d817e9eac24251c008484	1	0	\\x000000010000000000800003cd147ca95fc943695bb83334ee2e19d3a18c2ba1d32438f98ebd5977c602066c6ab406d957b4e83d14f2de1b40227f6ff5d20199ca949da2a50d02498710793824942364c378144c569cdc50bdadad4582d9700eddcf34482b89cb2ac227d5a31028a4214e05ae59f8e6a8729f2dda43dedb5046a3035fbb3f3380ea8d9871fd010001	\\x1987bf836a41ed428dc538afb6c9808acca64ca32caddd63b117adebb19b1467ffe3d72183e6b382596f47da1f9c4892fe71cdc434e94c8785bf135bbe483c09	1661687590000000	1662292390000000	1725364390000000	1819972390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x4dceafa6cd2369eeae04bdfd57005497ffa37a1452955563b4dc4f8de279a7a5869eacb1befd33e52b6aacddb99b5106f199c6d6a5f7fd10473b6a1c4622ff88	1	0	\\x000000010000000000800003c5e88907b31282e1ad97e26013192d2f6a2154f6c7a180632375ee72fdc002b2230062a750a5445c6ca43cea4fa7e083d935cade588f15ec7460e7bf60ab1ebcc7fdae91c8d12b2799b7ec20945c13aecdb9c0d5088f233c362d3e1a051429d3bce1865b1264dd325f994f33f65717657a288806ea3a4fee092377224f185197010001	\\xa493aafb5b4fc4ec42af5b22a7cc8aa396b9c80a8c673a0c4c05214afd538f6ff89df491ba313d6502df683dbdd47340e3bfa46e6ec39393e15f8a07ab8bf20a	1664105590000000	1664710390000000	1727782390000000	1822390390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x4ebe1c6934e07f47ff533f4c953aa93b21c50d2b172160ef454fbb6df353658b3db6ef931bb0a315ff54637398aa2f76fd75ebedaa404cd3baf2eaedca733345	1	0	\\x000000010000000000800003c0cd1c55ae5a896b02ce3ad85f2ea917d08b8840f5933839cfc371a99ddb9472877b150bccc915272321ac3d208b1cdd40a55679dff2210a2e586c4dba614b0627baa4d2fdd806224f50aab9dd3c9dd81272363adaf01287e26662fedccee02f871572394484519adb8d11a1baa27f6c69b61c264d54154b5a365dcd6a683aa3010001	\\x96bfc59b659cdcd7c5283f0062be2cb56b95a94bdba34e998136e9544c1cdcb031be5de00490abc781107e7fb2d21fcbbd12855b06084041fab816a8ccf8070f	1678613590000000	1679218390000000	1742290390000000	1836898390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
232	\\x4e9e67f7cfb1840369769618ab31f29947ea12ab1a98e72aa4fc53724754122098a3ad0d1e9104ed23075b6118e0ffc307385dd80d881b0db1e42a71902de364	1	0	\\x000000010000000000800003aefa4fec3e77b68c4c5adcc709fa82dc6c516deef260c0132c9c6398b7fe23e5c84a837ceec178bd06ed92a7ba9387cfc0b70fb29e76249fe5effee45e8f533202ca5027a122091604e0c4ee057e2841659b3564218bb72ee30589ff35e74ee1dd94e4e7cd56313e4e4d5aae18b6c43f860ad9bc6f790d958f133165ffe2530f010001	\\xebf63804283201c00207497f1b4d797da050ef0d59f8e2873c51efbbefad6229dffaf044cfef5538a1c54dbfc72e7775d06faade90e9bb3160d3cac80a1fe103	1661687590000000	1662292390000000	1725364390000000	1819972390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x4f0ac343d0545faa79460709b07746c7e127a7290fbcbc32d166ead4b5c74d1490e426ed485980a10eacc96b42ce62b896b746e4bdb70eecaabd33b2036c6078	1	0	\\x000000010000000000800003bae731ae93abd800efa75b53e0ab8bed461aa082ff1ce29dd599a0cc22bcf2fa9708b243eccaa4f73ab8069c64d265dc80cd5b5a606a3a43e650eadafe3080da65321a5465e2cabbb9b46d83c221a9bd7023daa545971bc68e8c211a2f5b24cd32d3f1dbf1b3aacc11c4892f5c9fa984d28bf8a17bcfc99acfcbbc54d9a31633010001	\\x73a7bde9b371d1ed415af3c43a1fc3acf8646c3c2c2632bd0fb4835d789cdf8392848c4923842002aaf0dc71bc8421eb04dbc7566e387d3d7f457cf5eda11a04	1662896590000000	1663501390000000	1726573390000000	1821181390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
234	\\x530683dd2ec552f0e6940547cd701624c46933d4895c1133c84bb4d1b45cc3ccb4a3cd6a7c887d33bdd672f94d40a7d2d035529da3d198590030f76a46e3f242	1	0	\\x000000010000000000800003adfdf3ee8ba4fe25e204731f42faeaad7382f974a862fcd9cc5e9814ecc658355f7ceb29380dbcffca627335ed0df2dc501000fb8da055c6735792008ed3f5974a2c0e7975c74ab74e8f94a920f1b8001d9059e911f6ef098c56797c551f56bb5a1d20d50fc3a6950debb764b52da53fdf184340073f2acc4bcacc832ec223b3010001	\\x0155b9882074128c48e82af02acc31b21d68e2754aca76cd36ce8b6a31ea9b1dad880d2b954b41d4cbd59d83176a81bfa21874663a55f91f265e470972bc6f00	1663501090000000	1664105890000000	1727177890000000	1821785890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x5542e3c4d90211c256fba0f334a065677888c3adde0c35256f008d0dedda47a62dff4b6857048fcc4672d6ca7f7684db523b57da7aa30ad8edd0d71de33f10f6	1	0	\\x000000010000000000800003b7d83c680042546fe6171485540c37e986d59df3879b0a1031e3985064c8584c2956f4671c6444e1b82a8396470847e3e2d45ae4b91b73902d85f1d2df21a3f1b8512bd0b119eeea6d95c14e9f29789d82954362d99659e5b82d7255655190875967925f334db02b99cdb601377177a7b85f32c2a7d9d6d80536062589fc689d010001	\\x4a7e235337b8dd88d36dbe4819a2221380789c64de47c8ece2d4ddb888da97bc55da61d2ee4c5e3d19e0ca8238b61a68be552d931653561ba2f9c5cab9186201	1675591090000000	1676195890000000	1739267890000000	1833875890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
236	\\x55aa7134cb742ccef8c972511f6f33ad8a233621d5c721f48e18fd44f1dbc70d96b7d6a4b6a9526c8847b5ea72e6cd3edce39fb4d5443fabdddb82e2bfa1bced	1	0	\\x000000010000000000800003e964ccf72ce49aaa6113af973fc36a1c474490a67b28ef02eac62f6f0258f0343d9829633578a91168c59ce065293a2d9897cd89fd1f328f2bcd5aacd54c275872315e27fe2ce0b434391eb3faba427262bdfbe81811fe26f869d71804425400a16868b917c045888d993ce238066e957ab2d625604e63b4a59be438374444ad010001	\\x4099fe23f56e758542c1eb2cb499a0a4be993c4e177efa0a4d6a4db867b5432906bf7d6edc07c8a541954bc71b3a1d539856bcdb927fb2236a5e6badb319b900	1688890090000000	1689494890000000	1752566890000000	1847174890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x5666dd103a185cfb5736a7f5f38661e8b66f3421b3619348997e4ad07862b09ba9c31bcd5a47e52a48854986dcda4423ba4e1b5ec1eb60fce73dc0031797d047	1	0	\\x000000010000000000800003db44fff7d436da8f6f3e04d40a4456efc63aef5dea8f829c974ca51ea942618df8b313987097aef2c23244645fc583f608416c6ad44b4f692e450d7bfc4870935a15a5c9b8394aa95d53a6db9bd91d05a649ee4feeb6e395e00e5651b2f157db2afc972e469894d6724a3e4b2164840b62809a7f550647aa1c90b3eeee663041010001	\\x802457bb74660ea39ec28bd8130bf3a7bb6c2be4fa76cbce81de8e7183fde95acaf76e17d6fb99507619237d5532ff8f9aa887c241533e6dbcec1f63c9e52c0f	1682845090000000	1683449890000000	1746521890000000	1841129890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x562a65ac52b1e7164ea4b1de2d8d573f3b3bbd732ac5208dbd8514e4da356d93df2116fe39bd5300daa274decb58e4cf2a20efe93ce41dff926c2bdf5949920e	1	0	\\x000000010000000000800003f4f0b7ef79a23aeed4c8a4fd6f557d6af737ed650f7831bceb633a03ac250b4fe66eef2eb0639fc0d90f8d41339633d78cf96712ff6d45f0ea82a390aca73e74d1bac348fc5f75baeaa4dac12f110a5710792950691af6faad5b2ee0f2f1010a1fd5b40409f8ef3b70184f2bbc84b9c872cdb0d88f3dad5d7674d3d16a94b77d010001	\\x320e2e371c73c07c03d26ced945efe8c5eb5898b2d620915d015e4694563ab96fb9cd83060f61f9e84541d3e23415beea3a94cf023d5067f8d597d5e25f5ba0b	1690703590000000	1691308390000000	1754380390000000	1848988390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
239	\\x5a5ec9b77629ee15c51cf50cece503ed6044784ef9e7313b86ea5eeef7cced5673c1146567a722bf6904d4ed8e0ae4f56017f0469a3875e009c6fad007b83850	1	0	\\x000000010000000000800003c49b9ca05f8c4ef35260a182d5d0de6860f9b84e63ee344dd833b4e34e086e679c0def850baccb2c42f4cfd46eaf72c822e3e2dda8a960550ecb089c278409c4a02e8373da3d72b4be4c434ac941ea3e3e5ab731ead3b761c54c281360206a338f06ba18595c9cc346dbcad8f42a1dd0f4b4ef6f21c41c9bd66726113aa5c8b7010001	\\xf08414d057898c9453426662bcaeff9980add87d600db5a222a52be6dcc3f4082f1649896d920b61a49079bca3c79569223d829df7dc864f141900d948499b03	1688285590000000	1688890390000000	1751962390000000	1846570390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x5a26f676389723311ad955a3bcff8b2b8f8e69e3cecf9e2bd0f1feeb0736ddba5b7abbe75da885054a6b7b6a982e998821ba9ff67008746219ee82f3d262bfc5	1	0	\\x000000010000000000800003e3dfd492b25c499f36ddec6f6c650e74a532567d7f9e08b8f8c834b9ea5e29ece9263644308d2d3259c9b4975821382bfe72e6dd413df21b993ae5e6342482a7096ad4a35d82363b7de59ea5f1c8f684b453f54c32507a7a72bb1f4025594cb1c90314fcabe48c78b3b6e808ae0cb00a45cfc3eeacfaa4418a38c29f416eeaf9010001	\\x6b6edb9db3789ca9827bb6a2ac338143d7b69f64dbcb9a517372b090bbcb31e716d3b35368270217b1e6e53992f09de03ae1ff0f9f93b423d50cb29b476ddd0d	1685263090000000	1685867890000000	1748939890000000	1843547890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x5d4e2df750e3a3a34c66c8cbc3ba0fe7d94c6cb63b9927bb84b6a8eca2ce53f5130925581367b66a25ad80b1d1fdcda1dbe30ceba04155ca4987415fdb8e337b	1	0	\\x000000010000000000800003a1f829e1ca6b686c4d72ec6b4c15e6585d84756e017e59dc36e1b48aedd1d122d231ca8ae173de1eaf561a970fa037e97c80ec6bddec06d1785571e7d2a718d70f71ecb8208144f8dd3ac57038e5833f7bcc72a74df8043c781b0c8b4294923b271f766aa29dce3bea7385053bc4c0d30d0ff8404ecf5e8c5d44d17d7a708ebd010001	\\x5519d3562d393c8e122504848afb11f4b107037d5fba5f760691dfdd9b44eea0ca71604dbed901cc5adbdadda348397f75d29bce23b13ea31cdeb2c557c7fe0d	1660478590000000	1661083390000000	1724155390000000	1818763390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x5e46f0f350ef4213a4374e6a83c0fd07a3789b93ce0403b6fae8494ff52bf6f855dac49a774eae16e83659fbf1302498cd3df005c807b04d1efa2611cb9db908	1	0	\\x000000010000000000800003cb8b2cf381331dfab3971201455a26defb0b54beb5490223eda95dd35bff3f6c0eb4cc9a9a952dc48c679478883830946335864f15c4bfcd4c4ed596bffd47e51c2d8c2b02b48c8960745d948815413a47c9df8cbd27349ca03c248c221cfe4c2f18440311d3a455a34aa2bb4aab5dc852f5348878cd13669d48b42347d67d23010001	\\x182e0c6ee92b5ddb4d63e8230c1ec11967aba86d28ee5e14101934c411ad0892d8744df7573b6dae4577c611493e972834d44cb61184dbb0f99ab44229031103	1682240590000000	1682845390000000	1745917390000000	1840525390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x5e1e306563ce61f5bca34c2a09167eab9a1e633553cb0c3d6317d0b37f68f9b99c460c3486c9564208a566a7bb78a7eb4148f3d7ef486df3e586071c6636e7b9	1	0	\\x000000010000000000800003acc34bca7d89be4dae8a17a3cd529ada5151e3de4bdfaab9df972446ca67e5621243f77a62ccb73904facf506bb78c9c06b0a1945c96e119ebaeb26e061f9abcc72742b345afded8dacf9cacedb54612efe2a239144666a0ced69a62c781d13239128658f472c7a56e4e5216ef460c1a9f9f3ae8fc5b3ea2ba55768c7dfad8b5010001	\\x3327a471bffc34e33612966e64222ffa89339d716c164e07143587c563bb22ebb5b22e544ee8fd4e01c79d9fdeb627a63afc1142ac3adff052f8320fc7665705	1688285590000000	1688890390000000	1751962390000000	1846570390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
244	\\x5f7e6c086288819c5fb77e8b5c8e78ea045aa75b75a24c9ca6cd92adad6a25e7f0264ffa330668c1a2a858cfed26106dc243873f2927242693111c0e24a4c153	1	0	\\x000000010000000000800003eff02201e6f601cccf4d340d06de8bb90110ed2f8498c124bb45c8f2fd06739fc8fe21799165e09b39b53c0594ad6725d057050683d7f3677e6888acb39727ea77093ef0728a0cd5fc026d6e5acbba1616df1a69ddfbce60dd1ea0f2b03c156a0556a6354674a641bf48be8d2329e3a0cae6aecbedffdf0ad5c726f3cf69e221010001	\\x5526e92c2a0edc3b9d83d7ad35e26c2731d7f5aa36d3520db6a84f83a1e9d617eff2610656a27f33632f31315a1f96a56921a2247cad3f7894722c12663ca30d	1678009090000000	1678613890000000	1741685890000000	1836293890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x5fae25ccd10df5fea8b6c94120d7cc12ba94728af3659e0b71ac2dd543dc325adaf2df18526114a705179ad2017e587dec7701c4af57ebb68f5c60b4fcbb6bf0	1	0	\\x00000001000000000080000394183cc37c0f6a97edba26a917aeb11d5b1ea1caeb3c4ea384da1334ca50130bbded407fe3e9284a2cbc7e9c3ca73628f6d27d255dd2b930733abc1c0ad11c2d95db5e5236aa0d34d82a712b08b1eb8c5311d2f0a75ee659462f813fad5ccebcb9ca3ef1d27f29ce18f4bee5c5f600f7937f3ff8cf161eb441ac52ac69280071010001	\\x22e164a8205d5d3d7eff17dfdb5034da27369cfcb9915dddca81e1fe12f976f7db93aee7ff2c2bc91b4f485abc605db3208234a62daedbaa2100845a79f4420a	1679822590000000	1680427390000000	1743499390000000	1838107390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
246	\\x5faeb2ec7bdc5b35ca25be49af9949c6305ff03e06d199f2ee46c398739eb7d5e88cdb938f33088082713d0d5910db21cff9ba9741e8ca022b94d341a5b0cc1f	1	0	\\x000000010000000000800003c63f8004b92cf903f8c71ab1f183a20448bacb78097fba0ee774f6657a7b127fc0a67f8ea595f632f4fc5685c8a638fd8b6314921aa25439dbd0a29fadcb8bc75183b068ef41b17081910d71582ac371baee1477506ced8ca9aad6762b76496e9bf717f13790a9cafed04bd8aa470cf3e848abb535a2cc76b6f03360aed30671010001	\\x96e8d7869dd2db4d6f24a76de9173d9033bcad18ec3ec9bab66857196bb7d98516688e5aac4135363b8a01e11731ea182642e91aedbdb766acc7e2ff23ab1b0c	1661083090000000	1661687890000000	1724759890000000	1819367890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x60de31c930ac3ae06839a06489d537a95556bbd6160a413c8b591e9fa87fedd99ad20771b16afb8944802cbeaadc5e3cd9f22a917a5d520aafe94ddf92a71525	1	0	\\x000000010000000000800003e0e33aa6979ca0466ebc079ec0bd49732d8aeb98455139f04f7b03fe95c5330bf43022c7ccf59833cd1b845f87c5648a99e58c4a5dd0832db6986c1e07734e4e8f8dbb8be437f786f70726fd2a80122e4135345649423b4a46309e56da096c8b908b57612a638289d1b6ea51e3051c76560d7a260582386a60f7e8d024a1d883010001	\\xf765a28dd01fa491ba806dd2ab575ed40726287a38775fc4e2781f123b98ca865b4c68dbe6d1165c0f87e00315d21fb8f2cc3e68712dbc6b6b31108e7427e00c	1659874090000000	1660478890000000	1723550890000000	1818158890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
248	\\x602ad71fc48cc91c611c66255901b5b123172a272c47731a8866da07ee5aec737e43012f59ab596c11fe83d68675c413992d2300ea039b69bc4f88cbc9fa879d	1	0	\\x000000010000000000800003bdf582b5eba4e62615a95d9b2ac45799b7cbebc06b34892dadd2f879b38560f4ef1e4e844f318bf38e5c736f8270f4a0937d99623fcacfa358abfe4a702f06609473703584451240a5e57338c0d950587bc45a18f924850a11365121e21240284baa80479aba033508a75fa92c2c46b693d6c1c336d9562a742fb1a4d1b5f2af010001	\\x1fae8d1db9aa5d241ffb5a990a293ded7ca554e95ae050f662da39516ba5816beffd44f55b619213d521a3022eeafb4de102ec7c8e5d896a7bca9caf15ab7906	1672568590000000	1673173390000000	1736245390000000	1830853390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
249	\\x621abae27003f7586f71526c7e4a5087f0dbbd5fe5ccc341a5bf08991c407b874919906ff276293052af83747fec9508669f1bb905f3293a7b14e7db5c130046	1	0	\\x000000010000000000800003c40f74ff6c70ea7d3d23b2015196917eed8d81c686d601c91c28c670b141c011e3b546299ac48b967b167688fec9ded065f0a5cc0e8bf5d673501764268ba0612188ae4b36ceef2ea5ce6c05c1d88f07c81a7de5de89db9d40ee0225a5d1d8472840553e4719444f4726478fe51241d111a453e631ff7c4350c688da0a7bd6d7010001	\\xa0e979cbf74209f99112fb5c200a2e43a4d5efaaf9af26ae3af8e88c8ac00ba0f59d6573549b8ecf863e36bfc2cd51ee6213eeffd1d129a5ac810a385e265c06	1665314590000000	1665919390000000	1728991390000000	1823599390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
250	\\x638edfb227078ed0a9361a5f106ad77c24840166471fbbc93c434072cd7176fc3bf8191600bab50d495b3f264c01b37d9bc574972f8f72f57ad57e29b79c52c9	1	0	\\x000000010000000000800003e264aff806f9d1c280943838d1e36846c6ed942b55b8db5a4dc6fd487c0db4c988852af048bbc9fd2b7328331141969fbfdafb32b9cb7dd04436518fa21719e07cd6643cf9adc2bdb0613e56383ef68252291c9d6253d787024ba7918b52c8ee5d37dc278b37a4bdd95e01d7103db92ff46921159724a09c70ff8503de582637010001	\\xaf78adad0e224eb0b3ea449db7fa9525aed4df35b0d697ff2fa45d60af8ab30f168b5ed9eb6af3a7183671e3389d16ac7e94c1c9a1940b20df06a8a829bc2e03	1667128090000000	1667732890000000	1730804890000000	1825412890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
251	\\x63b690e61072fe31a463bc3e935bd6a5c7b27a3dfc1a54a0dc45ad5129def0d5ac06abf4fc7417bbb42b9cbed7a3dd6bdc25f909cd4b0ce8885733d4ac010722	1	0	\\x000000010000000000800003a0b0c27b1e43e60af3d4a500c881bcaf3bab34491a834fb5433fafe3642a2cd730845db9d644f94eb309bacb6c3218965ad696161247ab3084f0fa0e6ee8aae78ca0fb8b5d1c653f03986ac2e49aa4b725e8ec5a3a146517e8a4d70f7fc22d72042fa69cdd5642668fb0f2262f46fbd72cc77750587910afc4e2e5934b734303010001	\\x12b2003006c0e6abded3d4670426cbc5d0173ea7ee7a3c9d308caedbbeb629b84f458f9f46552af4585c78b76daaeb17a518c41cb0e6b0c60cf52c841b78670d	1674986590000000	1675591390000000	1738663390000000	1833271390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x6716defed36894cc5b0bfe4b93652dc1d05444273bd5d2ef6e2b3a3680f94fb77b1ddb25bbc3dc0f8f20634b4a3f6a1191e7ea38c66d323d83ac2faab5f39564	1	0	\\x000000010000000000800003bab8293ef1e9322c12980035355e6e914379056ff3f0c16196215c2e02f21f4b2f38517abbf09a5eb965b711b8abb766b3e9b34640ed0864a5c9e99e5b781d28c5d7975228509da8ddbff420f66f9e7a2d9a6a799065734b160af36cad8155ee2e83138e33e0e73cc1fe8bc3627942c2993a73ce26ea5f29533d3fc0ae873541010001	\\x2b68f5644df876d3bb31aaf66af66ff36e16c0dc4d654a5e745dd6f539c9947b76fa21028c2088b7f06203cca06e5775ed36fac62b8097a1dc25c7d2e0ee6d0a	1678009090000000	1678613890000000	1741685890000000	1836293890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x6862b04eeb2f0b5ad737c20de47a9db5200cd40994fc15ef343193090f192185ade201b122f5835f85b6f042b057a57eae30017e00ff38cee4764d8eb28e19fc	1	0	\\x000000010000000000800003bd18a5f881d9830b11bd67f3c143f4f56f7021d668d0fbb20281992a1b255b8e308769eb5087976485daa8911a4345007eeb3db2d3e02de8d325cd9a2d92893969f4bb31534a2b286fe6372fae12b12fd7fe7d31124c1add99e39a29e8d2d06a946791ef9652eb91441144565d0af9a3a980a500e783cdc85822842d3e691ee5010001	\\xd530ce08acd46b0892a9520b8d9e49d75252850860d6b6ba6fd3b405d91e1542f33a1d9faf6441783fecf0ffc634b0b6b3f87fa6f230c4a6f9f85b748b956d0a	1688285590000000	1688890390000000	1751962390000000	1846570390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
254	\\x6946a26ea7f0c7e937efbeeca8e314f77eda5a575e2a95d6b42f07dedcac8fcbd998b9ed0d7102d397d92915ae7f0105fc15ac1903f70c8ad0cd6de002ed6654	1	0	\\x000000010000000000800003d29d9d7ba08409497ddf7c20e9f52dd3b7689512bb55804ec479859ab384d8a4248375d673389a6f4eecb7b5b63d461f2e5112eb33725d4bd8c806a30af4debc69453bab908f2990395b46b0137b6df1a85bb1d029055e3f8b7120cb69a8a71fa9b9ac7fe30df43b7a2fa5b56a0e89763bf541414847fecaf4e5065aba2f4297010001	\\xc1d6f1d45607b959e6ac345988552366c9953bb612f2144f25fbbb95b6cb69851738bf32f7fe55d0164ce03525540722e883ffec2096e0ab0e96672481a1f902	1661687590000000	1662292390000000	1725364390000000	1819972390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x694e24f60e6beb1f962e9159b6e48ff8b8f78266a33c7364da4793bbee7a28620788bfeacc15aceaf531ab4ea782c23913daf5e6e77c280bfadfb782df4d4af4	1	0	\\x000000010000000000800003d324bcad9ec7c7fa1b74c88fb9e145628d48d5aad233d982e06dbe5328fe23b816be69c362a68cb21da137b52abfa71a826c76a52baa9b88bca9e79becf9f31f7e214f2047fd96c2fbfd3c89d5cbadfeb241c20b26b9fbb6d937875b0e82a891bc668ebf6c83d5c8c371493386bf271ee7949fa46390a891c9f8e02111bc588b010001	\\x3fcb62ab547493c589c9fcba0557609b44a03ea5f7a5f646d1a2567cd940b903ece0cbedcfb3d52f8fbf2c94c3ed37463981d4e1b6772e00982bca6dac10100d	1665919090000000	1666523890000000	1729595890000000	1824203890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x6aa2540c0a12f9800424a098370d45e1f9b10b6bb928938b53465d7afa19029e569362078740d4ad812a8136d51f2455d2c7c1a280efeb49ee1f2aaa6824f194	1	0	\\x000000010000000000800003f54ac8b8fb8f77c7519344fe053f0787dc2f747dd3104d5152c2c705a983d4db65a9b2598ec9f0b24830fee327e8174a062d41f2074fed906f71b1c738a042e57d8613e2b5ee422f25d8cd5d9e7396baefec077b138e35dece617cd7a413e449e43f58668d0c8d4af36d492fec1e7b5f1e874d1bf057058d1162fa161ffa6ea1010001	\\xda9f263347c911afdcebb62861cab85e7f1192530122d23f3d07e66b736c2d283e3ad8fb041f96c529d157e67882de67a9498b27f46078e73088fe72ebc39b0c	1684658590000000	1685263390000000	1748335390000000	1842943390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x6b76c0379cfdb2ec5e0ca88a40e6cad1336fb0a890326ea04c8144dc5ce6134fc0b1eb89f76c9069f4e15e23ef531e8fc41ee7c37d9b7eab8e23245cb0044de7	1	0	\\x000000010000000000800003e31762bc84f5e2c388e20877aa225408fa56ce182dfa2dc169e29b31080e708a4fcf18f2d72f1105b47f31e33f77d2661504b60238b74a31ed477bc6b01a25018ba1bedf3984afbe26236196328c14196bf50c872ea30bbf7bd41c467d3f88907f43ec707b4becadbb717fd45ce9d3c6130e36e62a8e02852f5184c752402b9d010001	\\xe15b311c467ed304a6497f04ded4bf39be62c8a7bdca020513662ebd1151cf7f59b9c6b3d405be16ae7b4ecafe54c8a0a5c04ad1066d59321164a1a0fda6530a	1687076590000000	1687681390000000	1750753390000000	1845361390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
258	\\x6f0aaab37441075159cba4b70bf59bc3b4948cd22dab70b55866fd7208da21ce57eac67d77659d2dcc7f893a6c426d59fa4eb19e1dae15400b2258615aa26628	1	0	\\x000000010000000000800003b15b5006ded6ce4cc58c101e177c3b2e8aef8b30e577aea3eb4bdfdf4e4647a387d00b3a459a76311fee96f8e4b7b50ca56fce924731f3f5c60da71c2c8fbe2fcf1162c74719b17e58cace0b722ceec016cb375d333df6094fad05a23acab2d46492f5aed06da98bd71b99a32d82f35a3fb0e20ecf1eebb40f34c50428f82e41010001	\\xd07575b9a4a27063602add28fb47abf2d50105864e622491b20d592e719d519eabf07ba7f842d6a6ddb8e4c9b677c33a688b6f7f330a2db9e61d08e107b8d200	1678613590000000	1679218390000000	1742290390000000	1836898390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x7146cf4e95e105d99d9f45fc6c5d1bd1971b52a9bc90c03fcca0777e05fbd740b2e76e41e22577f203b9074afe535262157ce2ea57e6c578b81bc74c0eb5d916	1	0	\\x000000010000000000800003fb8dd86e58be7c7301e640e5d9016cacad9a4b782b79a3f0a2309c72818e8d07d848f062c7a0a2273dbf78fa710dbec718266a49c2670991818ffe7f6272248cacbba699685b9b46db5fa2f2e8b55270a73c905fc345bb3dafde83702408098fe862f8085ed6bc94cca20845b90726a575561b983f3c74c30be47bd818e8db8f010001	\\x4cbfc55b74d2e4277d46f3d069374554b9ab708c9f2a0762ae3b2f3b12b4739d8536af78fba1e351fc51cbbcfd8678a9d76f25b43c68351f5d6fe189d855fe04	1686472090000000	1687076890000000	1750148890000000	1844756890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x723eb665a7b672352deee802015cca34d4bd21f7dead58d755869a0918e1c31a19768bd5bd627a72ec2c2a90f07466d7184d25f496abfdc4a8eebe81fce7a158	1	0	\\x000000010000000000800003b9c9120b0aa2d65ae551d75b299a79a6424b813791c2adddfafa847e4a2d86fcc85c63ccdc929a5672395a0a58f1eb09f3f6836666aa1c91cb456f24353a8868cee365611dd23bef2274b565e7dfedc0a814b318ae04c3c18f375c3183d370e11f3bdb3efad551964f83d69baba1819c42794c3bf499c3fa6af81c60f58e676d010001	\\x1e6a66a86f1f276cebcc6a36ee2385ff4b8c398cb9c8a01dcdb1bbe2a76de7c7a2011a896ac1dd132eb2e472592ed0848e111e77520429c0d8a42d4e8e38c10f	1668337090000000	1668941890000000	1732013890000000	1826621890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x7356c7acec1555c40bbb29d0018e15eef40fe1153390f77bb8dea777946b8db5c353c3045b114f0cc7e18f734e8228948274aeb0b223c18548076388dab680e3	1	0	\\x000000010000000000800003c50ba2e7a62e3db6593ca0dd561443c5969d4962a6dede09674d522a1dc91b3b9e71abb6cf95679322b9b8b0b3b33457c68a370f59f9de1e911d1785d81985b8797f19c4d7e9bd3636073e0fb1d544ce4a24b85701ac589227b690302f851f45cca55d185fe2e9423e372c39d5ee10345bd710d0ab50689126638f287e8a1895010001	\\x457453303c6fd7b011c55a9be3270e45d8ae5ab7628f4c4938518699ef4679d88f9c21941a8b850fad329e82d6608e67a919af4b21ff1f2809a03ad7a4accd0d	1686472090000000	1687076890000000	1750148890000000	1844756890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x747aeb27bafd330d803e7e003786b5d7c83efffd1470b6da08569254c7fe0ecea05d5fa90b31b1256a2167968f1dd04926bd62165396696cc0f0956902f992a1	1	0	\\x000000010000000000800003bc87c4dccc85af3170382bc086e0e58beb08ab5a9b37ce5ac466582b36285a9ba970461a6901bf3cc429d2d2774fa19c7005f7edcfe3c5e2ec6bed6d5d89ba862d1ee4fde28b5787f4fa0db4367c6f4ee1c7f94f70620e94617f943394670d2873884be1af0683ac2607ecc6244d7ab6a8eb92dd646b713e3e68e42667fafd77010001	\\x54a52980b33668d67d76b949f614ff505880c8f84b5b583b586dd3fd7d643bab9497ac582066ce4185f800d8afc54d3fd6edf680b5a044abfcce6125bd3a230d	1686472090000000	1687076890000000	1750148890000000	1844756890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x7c4e7971ee5dc978291e0c91125f3924ce569bd16f7d896fa2a56cfaa01a5b8928c6c85c3ad579ab0fa096bf670e46ab3eaef6b63f53e752ac5047e3b3073a1b	1	0	\\x000000010000000000800003a32bd4e633ed52ca250130c08f3c4f8b9ff6daf2075e986b8aaed7ca010a1c545b377fda60f3d113ad8c1c0e462ef3977ce3fdc5bddf670b4273e4f9f48d6e6cc17e2a5df3b0a7ca0c8bad04e7022ab7b6dc51458fab31969ba2d0fe98567030005b32fc572e2507f893da7dbfdca0fc157bad65f0a114b9d85a5e1d0bc4e06f010001	\\xc50ab0e16db00115a59d4713021ffa39de662f0fb608fe56bd0db627a0d1cc482002c927e6a1270dfbae378d9df11f4d644dc3528f64fd8b81fe663433a7cd01	1682845090000000	1683449890000000	1746521890000000	1841129890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x7d4667dd759a727679ae97bcdb3a0e60ab956058b349f7f795c56dfa91a86163d54cd3e50effd20bedf737aa3fd58e49350e97e8113517f374e85832a24b33ba	1	0	\\x000000010000000000800003a6ed51774e684fdd3f929fc129e48bcb6f26202f95fb9413702209f1b75b1bd7cc92688dd48f71f8af1dbc90a7fb70e3877a96203ab2f5e5cd1ab1432745413fce3b9eb652acae1efe1176f0f1b4dd02df6e8faacab4a583ca87b4593d4098b31e74ded00ad8eb1efcfcc326153c555ec910a44fd20a3feb09fd3541d902670f010001	\\xce5541303eec9e7af02aa722ba70d51e7bce9f05a3421eb424cad559dce954c83bad2b1fca2778de28f79f48b5db7fe67b34b9e93fde40a993c7e8501043b70e	1685263090000000	1685867890000000	1748939890000000	1843547890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
265	\\x7d222885fddafd269bffbc78a941d2198ed8dd705660c0ba592d0ef165a9a1bd3e89d780f777b8235ff06f66c4e2fc4f08db6726a38ee3260c463f3e450aac4d	1	0	\\x000000010000000000800003ed8c516a7326632cbad63700ab08c2290359a9ac9476389b69ffc9fdd973dd72fbe840c56604a37cdfd834db06914c3ee9037e76fc7981e69f72836e2702a141d680eef599311c4db6eab474aa16223aed678e5f001a9c51ba6662bfe7a19050486bbd9b36bc5ed41d0010e33175a01ad383b00b2cb77a8c1e5d14ab8194a68d010001	\\x76819ee2c9598e43368e416126d66fec408ca2125aad78906b60178e09f45d206aea2ef560bccaa08a7f31e5e9c4004e583af4a8fd9ddda7155576c8d07dd50d	1678613590000000	1679218390000000	1742290390000000	1836898390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x7e96882a79943a1605d80e084db561ca44368379a1b396b1d87d8748d4b3d8d391f00b918e9eb863c940165e7a3cb3ad9e0b543279d73b02cad3ba3764351dea	1	0	\\x000000010000000000800003a1f3104d563d2452bdeb9727af91c40d8db1bb6f09c40967bbb19a52092500458f80f8b66681e32a69819ee08b9798329d2fcd1e6809455378e5e106a96f4c088590add61e24b25fe97e5b8acb2711af8fe46d6cb712567970abbcb7a6e82cea5a44a5d4590b1fd5a10d1c9c6f8c91057d3a66e31e32fb07b453b7a7e9f5bd81010001	\\xecc15f870861b2085e383fa2dac204103f29dd07d15475fd1844ec60a9fe8052781951147ae2e34b9ec818f1d8c208621a7d7d1304e5722fa2848a5c924ac10b	1673173090000000	1673777890000000	1736849890000000	1831457890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x7e76031206f1057692923a3f0c5008d1a633b78f2be51185ef3506626bb64dd14ec60984ceb540ba48aaee0e4a4d003257591861599a853e5af1c930c0040cd1	1	0	\\x000000010000000000800003dfe1f9698bfec255455cd09f9aec9f060db32e0275a786ee273a4429be1362b1b28596b6ab960d3a6ea1ca0c8eff1676a7d4704f38d4fdce02147da27d6ea09bf988d24286d2240c807c4762142231e5f29cdb4ad4be4fd1928080249507d68be8a0b77ed12e87417d60044b07860a27c5b5c2f0645470d8ff56195706d47681010001	\\xee6762823407e63dc04fe5b502a9521c5f5aa2c46f02f7eca59150950ad2d9aab1b1a941d9f17bf918c0b1413417d8fdd109f61698047030515e8272d7cf4f07	1678009090000000	1678613890000000	1741685890000000	1836293890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
268	\\x7f76d3030e5d74ea01a4d69e75f1d8cb5479cc3d82b2cf7a14174efab966899b8c8767a0e90fbcffd98786f6d8045eb379889d36426058f9f8a0c00057ecc797	1	0	\\x000000010000000000800003c583e594410a44715b8d62eb9a7d5d56d1491fe5b932e2ef4e66d0d753eabca448a1c9ee792860f18b82ecb0ca8b3cb41f7d90a59624f4d0fdc2574786a0bdb60d95f5f17a96aa3ba52fa35b936987691897375c0908699feef40db5e43a2b26c71b809801c1d2ecd4419926093cab252f51155ff4f346a8c77e993d9f5de8fd010001	\\x396874ff4605df7cf82f285ac50d196492fb3e55677fcd21a77956c38c8e1742173bcae4fd9a46297332ffe2134fb3bbe3cfddd4d2cdf86bb0905ef0ac351d04	1686472090000000	1687076890000000	1750148890000000	1844756890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x80a228d69269422529ea9815d548c14213487ad1b08386d1042cb3f155d8acbec048913ba50e96fd8b4f882d13051e719542cb99b7a055d7ec5dbaf22d773cd6	1	0	\\x000000010000000000800003cd1bf8acbadc989f91cac641a963b821e6c1a16ee4068a946ef498965aa1a416b3fb07f4bf4062f54ed862952bc07bf2f179e3b6b7c39e2134e0a328f47ac80e0d1d1855f36562a046f1932475d287b081d1a8b2033ac2482b8e72404ce6af3cc5a6b3745037765d84cf1c1f36a0bab1d6b4fb2c7b455e3ae8d6899d6f39fa5b010001	\\x84199b46ba2dadd3abdb1f90980aa61e4bd7e4d09bc5e72f836e6cb927e4f43da28fb1b46a8146d53f78d52f0e3692ef9b6fc9b1260aeb1871c03b2017d9d90d	1659874090000000	1660478890000000	1723550890000000	1818158890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
270	\\x830efc40bd6109f9391c60b00ca0f52a13478d94611206f64f5039c9359b2f9f7063b562782d7e39ae0fd3c4aa9cbb10f42a1cdd4c3c51cf83ca5dc89932abcb	1	0	\\x000000010000000000800003cd7b9cfe9a144c37ea726daabecafea9f53d96eefd03f65a9ed6674883a96aabd00d4547be8af260014f2bee726aacb62ee12d5c8a6ae37c313cfa1cfdca4694c1df1e21a302e61332bdec67e8621c86f233784f44ae3d318309a24dd95e803236bb5677c3f9194c84beda0a7f9e94afe2cdc400e3159f98ba7736a6675f4f4f010001	\\xdce3977974a6862575a77c35388bfd7b8882280242ab3d54547305a881e664e92f4d829a3b3f0c5960e171c034a1e288106ee3293c7fd8cf3f7f9621e9c5bf06	1678613590000000	1679218390000000	1742290390000000	1836898390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x86b27c01295e51f34faed74cdb514cf13856f5e063323d9986ee37626b6afc20eeb6c0b8b4e1744c5cd83ce6303541fc73d1fa50cbc6533580028a96632af57c	1	0	\\x000000010000000000800003b26ed23a6c628851b17f2ff161fe74fe5290936df74a456eb8ec0daddb0e0f99f67ebbe49bdc995ffaf7078b7566cf0088f1181a019af8bd488153a95aeb7cab5f31578e1e3921e5da7369bb76e133f3444a546cb25460382f49feeac61dd6c658fdbc76e36a19f46c902729b842f99b8e0c7283bb882512529c4a89e1f51fa5010001	\\x552c4d303b7661f2c9afccac94c2472b98c47ebf771d0901cddb86ed715dcfee2928ff9fb1dbe084c5f9c06843cf88fe3e930f382dec1c38664dcb426761950c	1688285590000000	1688890390000000	1751962390000000	1846570390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x8636dff6ec4606f6b736b1a54e83540e59b7f2fa53e8b6656c7219650d2a68cdada368bf2b04f6e5eaf20c63d1c4b41742e89aeeb0860c59aa98b648e0820192	1	0	\\x000000010000000000800003f41df0ebf288a6cec2472b5c6759e0ec51357f9380910f73c5e39af0d895ea35fa55eed02f9ca2e5c1099ac74e1564b9e90dd6e21f451037e35da77b00ce272e52cfad3aae935e4ed85acda9d9651ade31102ba2d64b36543f80c08c71455b7d3912faf3ea058a685ddafd431482b38bd6d818c7c0c244e6c2ad6f85ebce1eff010001	\\x29b65502f7ac5172f41c072ced0d0e9c7fd3589be682139b1a3b1dee456e47b41cd865ad31b998e5e47be1547b208dfa8d0def95a0a607311446f74ac6b2a901	1663501090000000	1664105890000000	1727177890000000	1821785890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x86f225f456cc70270bcc61e3286482fd9ae2f4ac5e469276523c8813be6918399debb22deda77baf4fdb366f67bcfeeb5212d43da812cfe2ed6ce6912e3a5d34	1	0	\\x000000010000000000800003af68e06eaebabccba4e4528eaf4e1ba9c8e417ff76bdce758ede95b85720d5d17370c2c94e3620780a3137d50c9d2109b8d7e8a176a407316e02439af3f4363ea46ae7f88965866cefdc6867935ca02c985bd3058bf822899f58bb10920e3e211825cf3931511ec77c7e898be6bd19b5b9fd694a225b63b8040d6506d6085a2d010001	\\xa43956344b05f3fd422388c07ec0f59b73451c02f67fbb9215fbc89e46262d7f4cdf041bb00400939d2ee1459fc7f75e9b4ff685c750603b87a35d06d919a803	1661083090000000	1661687890000000	1724759890000000	1819367890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x8d8adc81efde0fbc9ca4812575997dcaf7c472d08ce497caa8bc2164eefe6f8d892cdfccdaef93c26fff0257bb52186c468c132f78183670f5dd9203c035aeed	1	0	\\x000000010000000000800003e8901d47a4c4dd3710eb560983b9b3555523c6a649634299d77f4a4ce11907e20f2fb7b133359dbae5defb172d7ad34541e9a91bf298f5b7131b2b704f2b2cbffa3c6813b684f88268da653830f3b40a0bc7a6d3193d0d9d0738f0839de5dd5872a9b8d8001b85d188a37b6c021444f11b0652bc8217f675bbc0391606bb1d09010001	\\xf5910b4d40bf65c7a190b88fac5668c06ec4705d24a47c4c0270a3e287ec561a5c835919f6aae8c18fe12e3da4468f07b16ac77fa665a450d22af878fea2570e	1670755090000000	1671359890000000	1734431890000000	1829039890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
275	\\x8dc2c42f53fd06ca96e15a8aa5edba1c61730ed3d62dc2e38192489e2fe0d3d8fda6300a75327e4fc87a37142dbddef67aebbfc57e3025e9398bc76fea98f13f	1	0	\\x000000010000000000800003a8e5d8321e86c0754be662c9cdb9fe00413bbe60cf5bba34a19e025e6dde49afa5107b95aa141a6975e82dead5b0360c08573972a0b4fd289e44d82b805953a1e69388a322513c78319d7c6a37b6b9e16b15e95afbc33d72e7f673e21c290f391459c3fc4a56d9808f4b886a2ff0d5e0a9759095a6636feccdf8a802852f7871010001	\\x0b932f77cb275ba6f844ba7a044d1cc2c388bb757f468e970e2a79cba2b00dfffd063b1d2ef54c0d6631b61225c90d0f036682b317f1500a30f5f2385ebd3305	1673777590000000	1674382390000000	1737454390000000	1832062390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x91eeb317d80e75fb5ba12b9a55652e80a3f0054c940046c6f3a071e672af89b5858a95092262286cf85f4056360dcfaaa4bdc859fd7d1b09423d3e7eb1868f4f	1	0	\\x000000010000000000800003cda507590e3895f0e08d1ad2d97567c86b7cdab6fb7ba3b2d426ac01f546e48977907f6cd99f768c18d47cbfb458061d2835a9a6547d213b71f7d1736be79db790ea28cb1b96ef6c04a158f2f914701d27160be099da08fa977a1901b7adb7a71359181de8d9c2d5f95c2e9c586cabae1bf7c6bbefe88b0f8868ab88613c7603010001	\\x2cef194a91298d0651105c165e9c33192ce288c1f303e0c9cc391ae51b29b7f926c443f80d7f2c39b749339c9e2eeeabe6cd71f6a2180e77a24d5c8f66745d06	1670150590000000	1670755390000000	1733827390000000	1828435390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\x9286a3844f22224741d54f641b5223a49cad30b578e37a896c0e4206fd7ccd664c11b4f78e02b1136241bcbf3e175cb6b6f654b1987905b9c3bb865ce31b7156	1	0	\\x000000010000000000800003b4a4a58eaaed325c5abc01315d2e2165daacb051e04a94c970f1b235b2a9d7bd8d37fa1eaa49b870a133496c8ad5fd15060870588dcbfc74bc579e5f3da004b2afdb4ec5d06d986564a561cac10c08a502a04edf4cddf21a412ac2935ac1784436eec36e41698acca6fdaf1cd14bbad4f2f4cdade9a1a9e86292171775507e1f010001	\\x2c4384d0a6de99c5e2cd20d9cf48c861b19292acaa1dbbf6a9cea2f26f249eb2a6512cbead2b047091ae6487d43dad99e6f242b35a70e75466c6e6afbf17dc03	1670755090000000	1671359890000000	1734431890000000	1829039890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\x9206bced9689b1c278fd61cbe367dd0c593f9f5d7981ebf4150a3605103ef8473811987d7702c42b662af0c21b2d874ed769e40abe2e850abde051884f3bc7e4	1	0	\\x000000010000000000800003c225bc506c90ce1560c791b1dea07f9fd2cfd176d3ebd51047847c2600ba8817992060cd8f75380634e183014f00edb7dc79b0d9d7dd2df49a87a0f1f1e6cf76c418f29ef795722e63d8f5f04918047aa69e7c9246178ae9af83e40a6dd52bdc3b282e3eb8ec0bd6670d74e16a2930707db4b4393a06bce7b0f9a5fd40a42f09010001	\\x60293a23fdb4b9894f66face40494f4cd5b807538fcc5ded70376fa6abfc92eb9a1dc0bf1dc593b82e42682716965aafdef41ce38ae7d6145f43b49d4f863c00	1679218090000000	1679822890000000	1742894890000000	1837502890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
279	\\x93ee400fcb39e46e6293db67bcc494d6a4d9edb90d3888918204876bbe39b3462f5121b3c9cfb1810138cf3a93b5dd6737191c4b6d6251f3424b2a566b65a1e0	1	0	\\x000000010000000000800003a667650cb8c8b9a4845a0f12260dab934034de3a5e351af1d5c83753333e052acb60f30f0a91d3476b6bff45a6c2045b2fc411379002f1284c264293fef44aea1c6d26f2f1bf7dd2d3d99fda1269435b24237fc5d174e32fa52680543f78842c78e6925a3f7f03fe95f26056fa63e6bf885c861cc39dd478203361652f96be8f010001	\\x6c4d376a1ca886ced9dcfc40cf111dde7da6931792576a7b3edf967d6f45578837da399c4945aa301e72c311eda1040f9015e710cdca0db042fddb141d585f01	1687681090000000	1688285890000000	1751357890000000	1845965890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x989ab7aa5f4d1766bdda8ec3dcd07461b05a4974b6509e107b1c1ab83636310c4073994d4ef229adb7b5a5bb7e72c65a7afb7ed896243e1bc9fa1812a914b119	1	0	\\x000000010000000000800003d43777b8ea6e81d64a99782054d0a0bad9b525acbd93abdc2fdba2766b9fec4e353d08d5780f4713aa67c61bbe64fd49bfd87ddca8a373f357bfc272cebb5616a4340f6c9601ef5a0886527cf1c0e5d8da622e497d8882e6122e4a4a63658a3d41d605e959933e0942152a5abadedb46aa6205e4ae2fdffcf9862fb2c4b98541010001	\\x3d0a285496c37d321019b7468a26277f1464bc51c546ffefb5b92ee76205cfeca9da475dd58b65d529ce3b8940cb5076896afcd2225fbc2ace791d5375bc740a	1668337090000000	1668941890000000	1732013890000000	1826621890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\x980efbad2d86d9fc496b373647de664e11cb4c7ec808aed0dfbc146f90f5f01e276c54521a4ed4830f54d7ca4a8df83f66977fe72665c006215eb70b0d71e4b2	1	0	\\x000000010000000000800003aeca4aa15b5125eb2ad4efda5751d834f590f6b9b71d18c080b20cce2b1d81bed594516a1202055242f20bd5e069711777c34d735eeab1506c783bb8eb161b7a31eb9ae1672893303a810d8148babc201ac3010761a5e09053ad9f14a553f3b754d152b2af09a7b70605fb0cafaed8d09e6ce5dd8307e589edd82ced880684f9010001	\\x60d862ecb56d5ad13959418a9f9931311a05aebdf07dbb85e62cfb444eb2d52dcfa4b887dde8374778ec676d064de2b98a0e9470f1707ac279a3fa75f9a60b06	1691308090000000	1691912890000000	1754984890000000	1849592890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x99e23a8cf6ee3b50c786950ca36043cd57f9bc360ce62f6d0037fd615199a7bf453275f0668af1cbac7da49f89294d1dd802ae44577720e1b20d1fadf3c6a063	1	0	\\x000000010000000000800003ea1f02ab20cb0888124165051e5541111d5e2bc343fb4cf026296622787d605605853074643a1f29eb5ada381212fd986266879f2d48edcb086668a5edb9c850cc4fd8277a68588ccb3fce871c0de7c158e7b0292463c2d2c1c0ab0a10e7a70bbee7302fcd00f5957535c44399d8890dbf22ca3e3b04cc8a5cf05362000eea7b010001	\\x3e9030908b0f95f665a458c31a2ab6bbe8a4208ea1e0238e3d1c76051392d3f2d5b29656c1ed9fa0c7198c3ca421f1536332942d7c3ebd3448d2ffccbd154d0c	1667128090000000	1667732890000000	1730804890000000	1825412890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\xa2f600887695d48bd8f15f592189c6b8d8f457a4a964e0dc8940a0e9f509c75d45251856b0a0710c275cff62beb1fcb94b8736ec0f6590fc4c95d91134d09f0d	1	0	\\x0000000100000000008000039e0144e7cc6430c5bbf301b981d1864dbbeeb6b5e388a02641a34d2e080af513dd13621d8ca8c64d31df1bc91a4bb7b67ce8bc38ceeeb2089ca3f2652246160401d2dff6736fd0cb1be4527dea100e62eac93ea52b56e8cd69c14a5ffeeac135f509608bea7d91bddd10929a01a7cb1c2f1e518a4fb6db9eab03102278bd9de5010001	\\x22239d8864a7146ab17aee6e097f95b0f21c75cf2a7b8aada34082dae7e3075ca849f595576d20ac70b09562104b4b9b04b4c73e469e4848861b6d0a4486ba00	1681636090000000	1682240890000000	1745312890000000	1839920890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\xa6d26a865662d6191b115708291f31aa470e3b5bb7fcedd7b4da7c303ed462a46a231b3cd9c541ebef2e029d93147506e30b95a14eb5a60a678984f3835f1f51	1	0	\\x000000010000000000800003aca5a2cde5a644bce412df8ca4424f358e539d4acee8a5949154f996c8a55922fbc2811ad8d04d3d15aaf671a38d3cb176c81cba092621078dcc05a193bd3b570e7f51d7231859c4a9b9f96bfe372f71cb952bc6ba9e72b605dfe89a122d5c575c60efaa3793e4d841314d70d44a250f85b3b52a1b9660a126104e3938c4d137010001	\\x4f98adc87bff686c3f9ed33e1429da680535e4c1ea7cb233aaafddd0714d9bb5766391da511b906b8b4dbd9fb303cf67517a8314d8c08ed6b07ab46ede23b706	1669546090000000	1670150890000000	1733222890000000	1827830890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xaa16be5f9ddaa6b86ff4e19ebe4ba155dc9aa87bc861cdabbdb0f2926c5808280dfc970ce30a00888cc138e943432c348a1cc678304079296868a5c0961f231d	1	0	\\x000000010000000000800003be3ef0255ccd93b5d88edca68c468d02d32f4aab4fa674ae7d38c5880139180cf88d8d9fd91bdf33ebc7156fc54caaff6a632ecb80efd236538d89d97e9744066fddc6b06859190ef2b757e8d08397131acbd253c378b905eb289f4083d41e2922eae17af624e6f8d7edc658ae2d24b4d627418b9d07a74f9c9a785a2ca34e61010001	\\xb76c5a620c34269be5815e83573b12c04a982bb073a64543743b6ef541dadb560b48f1701a24d206d63e764c19102ad038f09d041c716cdd4732f0e806d4f40e	1675591090000000	1676195890000000	1739267890000000	1833875890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\xac46b90d94450e0139ecc911f7a872bfb3febd0537c3dc2e8817767d60f0402451b2838b6d7ce5fad59a13b7221b7edc02fd6f8f1420ccdecb05294215dc4fde	1	0	\\x000000010000000000800003e9f373e50b641f1ae545228e488d17983f5cb8b9d97690d8e15d6d007d545bf02896464da9ab4153947ab190b7b500b937649563a0154d8cfb2afc6bdb1721d05ac7631d7168d9497513a27282d3dab80355a986f6c841546334c80930aac3780b63ecd36054a9bb4f3488d0f60d2024293293955d74bf592f8f21400857738b010001	\\x9722b8a7ae3839011ca19fa1fbb632ffea3b053529a3f2d87357813f855e8ce4db265e042df35c8e6a5858b5ed959445d6fda079aab80350c5b1d050e3c94e0b	1678613590000000	1679218390000000	1742290390000000	1836898390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
287	\\xb102907760604bae0a5ebce8d224d727ca959939f1784eb4fd94472ac2a57a50d6de6bb90771abd1ff549c41d0d33f3c8a5fe46d7310af798e881d7b06cbf364	1	0	\\x000000010000000000800003add8c0a14f8a5f4945d0355294ab80b6ddf5da7215d255b4a7866b5706a6fc843ce70c4d27989f00127e4e94fe7d47db6bad4efcaea151b2670c98773f34c1d5ddf1f125635f4777a1e7d8fe884583d3d9e0fc5ff2b52b1f931c1ccf9976faa2acdd1a34547a732eaf64876e5ae9b71002f13304d732b77d14562362e46fdbf9010001	\\xbe2f1b056904607cfe09d931fd42c46e4fde4f9ff3ae0dd913b9630346999754fc3703c941fcf1f7e4e78ebdaa752947ebd25f77f92c568c54a38160aa7a630d	1689494590000000	1690099390000000	1753171390000000	1847779390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
288	\\xb2d2649a77954bbf6894ceedee82dc65151784c9a31cdeddcbb5f65b319763559ca2923f68f5124576eac42cd572de50e7fee31c46feb95d52758861cb2f6cee	1	0	\\x000000010000000000800003d1859813db44bf749edb057ab2a6c0358a3f8a8e4e22a263b99e90816b2892ff80755f5e5e7f942b402154b9f5dc420c599e56a1439bbe8f1dd5cea7e45248b42b975898892135811a97987821083f79dd4b522a80e23a87f675ec9d6a0b0dddc7739382bc9b2d5b9505c839bb167602b0c2b42a4ab4b73d99e85d442f66eabb010001	\\x27b2b6e1bc620a246a1cf1ed1eb043a73e3e693e8c7873a1996b0390aaef85fa8968955a1e4fb458554bbb85aab26c107d4eb5e1599e4a69123da8da3655210e	1665919090000000	1666523890000000	1729595890000000	1824203890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
289	\\xb45ab88d98369333344655b295ac86bab9c250a8603a3298552cd7a0d14d596fd4369a5f1d09ddff7d25b96bbc9b607361619058bc624e019b1e5b23aa15a61f	1	0	\\x000000010000000000800003c75e0877709486252163e3c4aa1597c8bee8949cf4849820b9f069ffa65ab271fff11b26d6c3d36861e180444334cbd223fd01d9c80f70f17bf930c71f54c15b0592b9bd7566ade8afc9eccea9b55bd7213f145a9aca16ec00f48d714b25c87b46e6728a8999f0d9c45eafd30bd27aa558e96591e7d0b153e2899221c89d21cf010001	\\x3889eff5b2b1afe8287871eb9a117765417d50314983f27afec8a69ba1be5fbce15f01e6ed280e106e3d1acd64c909b406ec5360fce7d87edeb57ed9a03a180f	1684054090000000	1684658890000000	1747730890000000	1842338890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xb6966aefff8f70e354daecddc768717630106bd97d0b0b80ef02c7798dc5ae5da7255a845356e774560df0cf8b415a3f9ac736ef286770c5963032f7adf6ff7c	1	0	\\x000000010000000000800003d899b9e2ac22553d8bcb53536aa0b35a2af497c91fbcba9dc472d78dbba2eff8f3c08442bbd11f77b94d06d5aa1bee51122ae8eca553d51df8bb537284a1b4ae6798a7247a9823d486ac73906cd315ba7da6ef67e7d958ef9dbb3525000746105438f0870072a38f5f4b1a843271149e0a35ab8ee2e670cf4ad21766682fe4f9010001	\\x6dca44353ba2b52569b72d53b5f11648150b79952b47a69922be1c5899c590a406e05cbc980ec9dceea785ff461443849d37a85e9483b9762e545ded63c8f704	1684658590000000	1685263390000000	1748335390000000	1842943390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xba224dc760b23cb73e6e495e0245b56a5068e07b295deafe6d20cd10b587cc088692e0553451723a92731af093ab2156b2973cc6204cca3a2de1a91d69dd0838	1	0	\\x000000010000000000800003a7dc231ea3637cad57746db85e50d8e0fbb3e4412058517803652e6edd8a39b0c349cd1c6fc79b6c5ba9e2738ce96bf129a77725c61821eb0876dd78129dffbeff3c788ce663d7dfb18341b5a7a21b2688143d5e003e978c53865933bde42e41c8dbb2815bbd5d3fb4995dab55c9dce99682cde71b04b556a9575d6f9d7fdbb5010001	\\x7574758613e463eaa995974ee6da04201ec96a74f268132ae2d72b1f45975515af08f3b3661448afaae565dcb78fc54e6438e9f98e712eeae2f6dc4e95aa0d0a	1670150590000000	1670755390000000	1733827390000000	1828435390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xbb9e8198bb13e1d4dd73c51abe672324f21425633e066fae841bf50de5137294bae19b2ed268e97c0af0e192f2c88049cdfea4d9625718095f3c2279cfdd129f	1	0	\\x000000010000000000800003bfa1d4e32edc77cc736d535117c399af6502708d7f0225996449839e1025b59d4f5e0e1dc8d98a0b9fa3d3fef8b3579e5a5142c3011c94aa812dae5a67e32f08701eb4dc0ad9adfd0b3c25474dad2b039e19195caaeec42eb1141b94ed8890ddc94f92274710ffbd77229561a2ec0466bf6dba9e823b536f75289a1827a99c43010001	\\xc0760ecf28c20f27fc81758359ad41ce4ea108c20ea1d7e0d01b71317f174f285b05c09f569be8c8fe32f6a43c67ee8a06ae4628f1f1bce8eecdd422549e6a08	1671964090000000	1672568890000000	1735640890000000	1830248890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xc13addf31922ef58c5e9682fab4ba8355bfd6ea544f94e3e9016cd57f3a71689a12be18bd7cfaa81dcb834373addd06e766431b48504b81b8ba92497aaec7147	1	0	\\x000000010000000000800003b93e2ed44deb27ffa12c999696e8f0cb2ca68d6ba1a866cb96e68e850ec334691795f6c0c805c8d282a2128c8cc0bca378c58b03a815a6cdfbc786a44a923e09fedca62b921a63e63fa03868d7a84d555e125f775d2e9cd2beda8443d66b82dce798555245c99acdef7a0b6485b06ea0e78857d325d768b6cbcb8c02c311cfb7010001	\\x7bb12afe2b9ada8568b0504f2f62dfbfee7409133069e4cc7d4bcea171677d32b28a997a428b05c43baf9717a2603b548121a0898edbe0743d17d68a92a1600e	1679822590000000	1680427390000000	1743499390000000	1838107390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xc25200c30d89ba9c5a103f889aa729afbf0ab87f500d2648c86e0ec7d2eb2a48249548fa5652e88068cb989cba5718215ba3cb3bd1e77ad7400354dcd0d867ba	1	0	\\x000000010000000000800003cbc500daa4e955fc55c276dd125b503ce995620a5ce4be8f46df02347a59614e7872b1724fac11745e343053863671e1df75dc878b70a1b9774fe5d730d332ef3bd10a6282a7f55c66ca2a3b160be1023ec0828776647fdd9a41657eac19952f09ef9d90cd2febe0a26d9e03740511ba99bca60d8150e06e0a2c4396f69ff9c3010001	\\x11a5be79e38c64cb66644f1970ce5c3c34d20319d8f092e8e9c572663406331994143ed75de2de6271c5beda4d15ddec68a157f5ec2dcc74e560b3ca7ecf3a0c	1664710090000000	1665314890000000	1728386890000000	1822994890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\xc3728c10e31c8747ebbf4f2d62cddc2cbeb0d8a80ed636114f6446a585644f8428e288c4f42574e698b1f6b8a5f532330cf8e7ac1c0bc4530aca21703cdcedc0	1	0	\\x000000010000000000800003c826c2712696035e4af9cb93109f5de500e570b698465c9efe889ae14f3e947d153eb046129b335d28a122ba37a5960a9fdb8f68e74b95d3b84971c76252a775f5aed64b87ac22a7aad4be3b5b53917bdc8bec9c7950031271c7e2011e7ec6e44200e7f4c6554a06e02d49a9c005b4785b3943464f0cbcd97c23e27ff26ba60b010001	\\x1a9dd14b1bda4785915f41a9ff0d98c8973949c9e1876ecf4f44d8d1b4d932515e2ffb93d0c3db236c43d7f1a8c0084ff25e36d3af899be244935a342504d80f	1674382090000000	1674986890000000	1738058890000000	1832666890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xc7ea524934f94f29241e48cd5e30223afdb31fc7af166cf28e562e076aabbc2e58691f556c5de553438e9fa2a21c7bb47e6d6963d09807bcb30602a8a7d0fe08	1	0	\\x000000010000000000800003b99a3c89fcacfaa9845f6473c9830b5245855755b20e3dfee785b73d9e1c2fc05696c2d1a7fa1a20b5110dbdb3c1f36fc1a2bcd858c488d2710bceef8ec1f529efcea86b88d4f28cb86e3b8759a2a3e03849f7b2b8a5f092330c972cc25dea44083641c8d398874c741919dfbf9d29ebe057efc1aca163be369cea440a45e633010001	\\x40df21a1302455b343d8c9c301f49babd27aecb100065205defe637bec7c9dcb9546d5d5ad2c3ae8ed2ea36acb2b90fe4fb8aeb6f2680abc438516af6edac800	1659874090000000	1660478890000000	1723550890000000	1818158890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
297	\\xcaaa3132b1ca7f815ec27a3fdcd8544ea1191f4897c586c1234334e1610671e86be3dfa6fb165e83f6ba5ea9501c44d1be354694de7e6409e5a8f1a48db08d39	1	0	\\x000000010000000000800003b64c0591e3f6d67d2c18cb1daa4badce6a995c438dffdb742cc9050216f67457b999402bf2103474180999a194199de11e3330f94c4052dbbe7fffa8a6cd32cc3c2836393fe0ba61798c3885d734654415aa02efcaf21d8a0b4edce0e20b2eba1b9c48cd63f7f1ab327a2832a8c842f91ec90e38ff36e80c53c21561da8b3933010001	\\xfba93e2ff307a7949a721162176e3f2f171342313b4f9d16fa17e8492e0e0eed796d956d7871e3ab757249f77e0cd5327bf44c9bbc87003ae9840617b82dd707	1681031590000000	1681636390000000	1744708390000000	1839316390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\xcba22ca210af8791bdaf34e90a4f1027128c8c89e589044f29af0ef700062023face5cd4267f1e087084803a060576d77e38585132d8282620a50d3f6ff1503e	1	0	\\x000000010000000000800003e9c3ac5d9e941cc09926e121226d885f3b576486e870b6318e60c4761bedeb9803817a5015e3fe66baca53b95298798a76ca68088727ca4bd9de9fc280806ad9f2a6af20404e07b3a0aad17f0ac85a6ea56b82dac30fe6e9dd3a76ec38d45c099d3c3ac01669779b6bdf5ed95d65dff368ab84842df5df311bb41e902750e9c7010001	\\x40688acb5da7b4885328149b3b619eea3544aee3e781c8ea6c86dab7bd2a32a75beea5b4e4d5216f94f97b99399b8dbdc42a6fb0f1c2c6435a22c9221a83180f	1662896590000000	1663501390000000	1726573390000000	1821181390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xce8e9f2a94b763f9e32f9501c3b3931b8034968ee62880a4db9523d16640bc0c6dbebddbe3629d46d5b87f342ecc0dc42edfca55bf26022232dfeca5cfc8cc52	1	0	\\x000000010000000000800003e76aa4ebb196be6867d099b76ea528029968815fd2eb14f966ed734d82e17586efa278684173c6f983c921efeb9015e8b1f624503f9b262da2161ae7b30d5daba966993378c0ad3d5d9c3de0afd6260c626ca3c741e42349f1e8decaa59fd9006b55bd04df453ba1eb5e651e60a99beb2224fc4d5a13fe8e911dee2af3988dc1010001	\\x596e19af78978b3d14b8677c9ecdb0676f488637dcec60644501300968a5328a9ddff08d91e386f39f108fd57297b14872fbe003f0c716657c8eef65518e2703	1671359590000000	1671964390000000	1735036390000000	1829644390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xd11a737c5cdf32fa2ec73dc68e1134d8d4aa00fda5f8ec236fb668ef60dc0d98d61232892171224952ee861735bd38a81405809c97fb6d20986ae59be0c57d9b	1	0	\\x000000010000000000800003c8cded44fa2a1969961ec15b32be662ff1982aa24c5d0b514dad733c4685b2af2c7b0a7f6abe9fdde46cbfa51658b9e64ba477cf8c7fbe5e63ed63f275b4b1fe08d147a4b078aa6ccdc5b0522d263fcbda98895b9ebc27a0e36f13d7d5dbe1abdd6f0418bb0820b8aa77280eab25a0cae33efcbedd24f6bfd0ed531f801473d5010001	\\x10ac28582f54f2457c46871c26cbd380f7552bef9939fd740c7d0aaeeda15af1f55e625dcc70d0d223b587a60ea1b63e286a1c5ed4b609498d35b75c54a78009	1664710090000000	1665314890000000	1728386890000000	1822994890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xd6620a131a2f095ab55f2090c22ecabdaaebb56cdca75fbd30977ec5871e2038ed55612bc483f46338579127d582ac112c40daf26c55f9727dfe96d7382706f0	1	0	\\x000000010000000000800003b7f1e76d4bdec89130916298fc6b785acb2bcefd3491a63e7cfd9c0516c78635a136758f4e39704d0697cbf9a9c687561169668c205f3907fae1b3410b74842d837fa3570757d8bffc8f9d85d2e8a85dc79ad60152bf468a6b35845700578cc35eb28a3b6957dc6aeb805ec84fc744f7b625892fc7d52e0b6d6736718a537501010001	\\x48878a0c15943c4d1b94f46099b1b9293ce0b4dc56b9dedc756f6797dc39372682a026c98a422bb1573b872fd0967254d01cbbb9e665734f14ee42271b741e07	1684054090000000	1684658890000000	1747730890000000	1842338890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
302	\\xdcce45fbfa7acd46683c681529b990e17b4632b940447f052a3db769d116f9674f9c4c1b5d3715974058e0dc5b919828d55689b34b65b49fb29a1af12089fa61	1	0	\\x000000010000000000800003c30d95bcd308fc8a5f5a09f89d6cd5a6358fd583f26715d06ebfada1fc0fd8ee756a4d7e5fa2a54ec3710ee7f16c035b1e441f89875771fabfa252822683a113b79d8ace6f0069582339e7248569f30e0ee630d7b996a0d765ea075925ac897024979e34bfe58eb0efaa16604203a8e9019897687728cd5c1752fc443fe5b387010001	\\x73dba2d202f15a91868d21070d56baa726875092a37b97426fe5ccd8224494a8f82612fda1d4eace727e5a12642de3e6cc49bc73c10c759e14a7e64fb1d6cb0c	1670755090000000	1671359890000000	1734431890000000	1829039890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xdcbe894cd438588d451424f82a98dbd58125372596f78f98fd1e578a1af2e119c5205cf35d3c3f0e865ac9304a258b6b5b607346b1772e2564a656704bde2de2	1	0	\\x000000010000000000800003bbb91620093bcd7dac31898be554bacb6dabd172e0a48e8bf0ef48ec52dcf9af8ab5545279de350c9b2d68c5d6cc2b3aae5f765791e02c332627b8935b36156b86dbd643b95a6388345c8801cff8e9f510adacd543ea06c5d6418d11b1199c342ba49a36b7eeaf08040e063558e4b7f59d3adab7b4f7f68c6f98c9283701097f010001	\\xb99425a361bcb5b87bd5d591ec32dcfa5df243659ab02e8c587ab4615689c722de28d5403215dfbc097de5102bcd3868ab006b31f5daf68a9a419d70ddf6df0e	1664710090000000	1665314890000000	1728386890000000	1822994890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xdc0a74f42bc47f8e7f3afd4c4e139dafb564e2d169b9ae8a49551bd4c6579043ba6675ec84b292ae94285a4b6a84267776b718c033f04e41c0a6f3a56399d758	1	0	\\x000000010000000000800003c60c1b2e4e88c5f8c9c9b0eb2ff9bc607912434098a819d340ddd14460cbbcf0c22199128af4b44bcbcc8713c4e59a5202bf5c0f8375680ac672ba027dc6165f3639a53de747e1a6b3d611da226415f8575af9a6dce20f4323e1144d38fec053891c07b03b8a5d3523dac8cca9e90122cecb1ae78f278153a63ec0e0f9c4c4ef010001	\\xf4e96cf584fbecc238995467487c9528f80d16923687743bdb0aa69e22cb5236174cdd845d9608c5e5761f9de4e76c8f8f1979261f33a9163917f43edcbca60e	1690099090000000	1690703890000000	1753775890000000	1848383890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
305	\\xe1f21b849dacb1f66430401fb1a20b4d4dde0f098972116e72f6cd44d7948e338ca2edb6901666d7ad5f3e1d83a4e200891e297050e884eb815390882f42dfe6	1	0	\\x0000000100000000008000039f437c27f00ede2bcb566807610d8ae210c448909ba0d7659eaa6b0a1a9c6090f6f1c7c9d6a8c51524b6105f820ded575c62b72b8868e46fc88170588c36dad6da1338c3209ffcc796e2bb1d8cdea21796b8d6bd951846b564e0f2e8af4a835da9ae0330c8e1ab5de06eddee4866f4d09aaa3fcb373eb931c0f2fe8dbb7a3cd5010001	\\xe9188508789662a6aa465e6951a93d568c2dc0d68343e2293e8e0e923c020e45921eef7da9c3d69568f6bb45420f0ba61b14894e693d1d6b4fec253d7d26b805	1676800090000000	1677404890000000	1740476890000000	1835084890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xe3628662bc0fd29705a32e91ffed5921b7f617366a1c9df21935e1b91d283911572717026f1ea0c5bf2fa48e9fa3da7bff536e54b6091bd7a8ac75d03bd64cd3	1	0	\\x000000010000000000800003cfbb6d2d8a3bae00761e2bebabf3f1c37f67e657994341dccba52bf60640eb76c02a8f2b8ca08b6d6b7f08a0b972be932c21b120430ec62809abb1301ace7bb01396eac9ccaac1c49357418d1fc00bd98d6466dcbe7dcce263b0ae2acf6b291ffeefde5294df440f4b509a1e3a78c4391be482a3888e2fb664c23d76146bbca7010001	\\x9f22d1d73b0dc01b1cde1e0cd9562cc0683eb0fb988424ecdde6fd218fd95b523c215a08b2688a8057cbc24b968e9a73a7b6cdd3f0a9f4a0c42fb1042e630e00	1664710090000000	1665314890000000	1728386890000000	1822994890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\xe5167149c46567630b019cec86170b0f5a7266bbaeb1cb7a04ab43d28c44c523ed89a6c29af2642fa323c18ecbd5ae152dc0536d2a55e1b01876fc042c5b3f6f	1	0	\\x000000010000000000800003af1c88829974c21a02edd8d6d336c6d034ec5b4872dfeacc08e165a650a469f9c8cfd5b6f7d4ec2b67782aaed12787643858c759698c122a9602158234da17f99eb7d090a25710eb032d8024dc4103dd9de1336d12b5b87bd25b78f47dfb95539150fd1414e7831ae2687634bcbb1aedf775670b84dda0bd72ce6de389cc3f7f010001	\\x3b359a727df01fbc9ed76b1ddece9d8e4e0a48f87fa42708bf9df9c4a91334469ba640c589079a905d19e76d634d2dd3c6b3be328d44ddb4aab0793b45d6c00c	1663501090000000	1664105890000000	1727177890000000	1821785890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xe7feee7c7ecc24b166bb699a8af157b36cd32560d7be1763b73c776c0989455dab60bb433771e1fc9550d7d22606e0122c86bf4bb35e6029e45e9b72feb58515	1	0	\\x0000000100000000008000039beaf72193dcd267bcb8767bd9b3c56f93f6756b3d6f40565f12bb29c534eec59be0572dbd53b29e55789b5cf7183683f3a40947b0791b932fb2aecd228d1ae16074f12c82a434062aa361bdb15dc8f31bb9b491ec996f03bbcd62f9e1faef575e8762727adb686cb47e8b7c5353d05888614c555842e0d7a228b759b8538d6d010001	\\x782e0f4b461a9783cbe96e49ca79a4a6645808c5db5e04091cf6a731d803660781c4dc128d7f02f71bd89825f9d594e8b63712efba873f5f84b89dce822f690b	1679822590000000	1680427390000000	1743499390000000	1838107390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
309	\\xea4a9e8c10e348f4eda35359e98bb68d36e73dd9a62558fc07715609e7aebdafbbf21398500d722338d842ff2e3563da225181b4a7724fd2c748726beafb07de	1	0	\\x000000010000000000800003cb505a17029d791fd320d9e21d0aeb9018aa90dfdd938d206d3ebe732fd4298531d7a67cc1ad9071e21f6a8adb8aef117562b6d9f1529ea02c7c87112c842cdd53d290a6c237810395304927b7fce19b9d478b11baa05dc5112a3db01e85dc721aaedf9596d32cc49904388bbc55e07871ca681bfa1b538ca1ec709861bdbc09010001	\\xb53a69871b7192088adc0e4d6c0bce230897bf76978eaa1f5bbe3ade9abfec2153b3f2a5036300a85a05ff8b21929ee73c4c15a2825309cf2b42963d5e63e202	1671964090000000	1672568890000000	1735640890000000	1830248890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xebea31cc2e234843562a138d61e9035a8f6d18f570f4178c5fea7f8eb7241a99f6bb4e068262451aad92c7d07cf0b57aefa8791bd490d686cb50823f8c29cafa	1	0	\\x000000010000000000800003e37ba27c5afa7e4b8a7a607ec77345bcaf6a5bf98d346f4b56aed0f023831aae6d09aab2b9923f35c0d01af315637fe91f088bba50ab1e7c0da0a0ac419eda6de3af1f89c769843b8d9044b67aa2c27da9d4b13370bbbc5cf0a2ef3b2c65ff7377f1b71da0996d9661a9def2f1bd74e867a3af05d926f01c77b605866eeb2fff010001	\\x5111699281dc96c338b82784f8f8f672655b6522affa56bc8b0fd79db41d4a36d9176f853847e7b5a79678270ee6a3d45658548c264b5f6d65f872b9058b5f04	1681031590000000	1681636390000000	1744708390000000	1839316390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\xec8efabea3a5e34f6f831dc8e487215e18a14bbb2f45e44f1ac04f66cd687003c55cddb45509b26be275a56bea7cf2af5f2e2b0aaab082b7f7bcbdea44fb3db0	1	0	\\x000000010000000000800003ce5afb665cf0b8e1c9e154ac4ed293f50ef84d95aff2d0a1dc37ffb999839a053c0b34db9069e80606ddae5916567beef94f6764e143bb74c23e66d6791d2719f9151fb2d97d08418fc264b98aed343ffb940fbe23bf4b517a96b90c52ce99fe206651917c8f2a5010b98d6dfd10ada036820c19980e522fceafcb7cd2c5e023010001	\\xa264fd9ae05339fcbdc347f9d61884e31f0db11efd3489a2ed34d20526fc4ad47cfa748c8ea4b8058ec2a0ff79f5759b85fc86da4152c3a0a24542a3077bf809	1688285590000000	1688890390000000	1751962390000000	1846570390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xee566cf5886947af8a4fe7a7232af660b6c3e949a0f5d9cfa029fcb2325aa887303fe9f08e85daa9ffac003d2a4ae513fb98895bce9b9ed8ac09b5cfa47f526f	1	0	\\x000000010000000000800003b3d208c23b7f9a3ae2b8215dac4048f6ba73ed1099e409e919a09bedcca29d57618111d1b4936d652e889ee23d2607170786481cf7fd6e3f347f50e76443c1fc89266e5aaaaacdebc3c0ab9037261fc260b986914458171e2f3e532648a40425cb098e58dd8ead752145d2c0c14be5388cb2b206ceb67ea6644b171c428c1a05010001	\\xe71aad92b81fbae6ec1a210787cc52c4d6ea5c418515fc31a35fc23f71a0ed372161d258f5ca00ba6813ec42483572e8a1963739d9b49801f5b72d4182bfa506	1687076590000000	1687681390000000	1750753390000000	1845361390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
313	\\xf4a6f4fcd02f5a8768c8c3dbad81bc9b87d4c918911be34d70f6320f46eb516b4f52d5301c2b49dbd8b0a945063c1118bafbc65d74b838560269a554515fdda4	1	0	\\x000000010000000000800003dc99c6cb6cf7468461a70a748d2f09e426ce0455f6de990553db44d9bd12913b1674d56ba36e65bdec169438ce3858eb0280b2a9c2bdebf40fbc2f9550b9af6eed0b6157b3d3a237ad023a2ddc774f9f5ac2f2f4c18c5bb7b819e065ee797d03e8cac33a7b4821c5d3b6b40820c4019fcfa8f7de2058f251f7ba1653cd423a8f010001	\\xd74b4a0731d1b32838c45e79a56ae8f966a9d767050edc53215823c90a9989013062f2acc1e6e099ecce47333b517c6c4af132553690d109a36bd219fa84dc01	1673777590000000	1674382390000000	1737454390000000	1832062390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
314	\\xfd0a7554ccd2c7a185a05b3a129af6e21285c494394643d5424ba1286bfd05eba5d9a86cf5968279386ccbd281df649b79a2725524ec9ed20cf391387ecef684	1	0	\\x000000010000000000800003eacd14d4d3a0cdc4177765db4c7c40609a8c31c68f87564b396cc2eb7c160f139039dae94f03593a9b26f876725ad5efe95308f3788e0f6febd1dab167d872b68e0ef14b548156a49fd1b30fe3c4430feb690dfe783d659bab04042f6defee53ef7abff17103834795a7bdba0b0ea7618060719704a7536e265f3b81cdb645dd010001	\\x313792cdf35243b56fb50ebafa21dd4308f2f10c8392ab3295b90f3fb7cf88e405afd50d9e3d6e753ee767e49891ad08574508e6aa0f4ea35dea10aad848a102	1682845090000000	1683449890000000	1746521890000000	1841129890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\x00ef06b799aecbbde3165357070713c350360ed47206824880f44e5214608b910b3b7c1775b1c9761f10601298765265a98a6d561748827608aaa7a893a29d0f	1	0	\\x000000010000000000800003cdd7855e650328414097a1e84d0b52b42102bb82b79cb8193bb7f8b28474a8217fb178f7faf9eb170ef2a0ff8e7ce34bbe41f397eff26510f9fd9de67653c13421386daf1258e5b5850308fd54702609f5d0e79bf5ea196c449d6081a080a7836dcde10e271baec67fb20aeea811e37f3433edda0ae54da8f7fe87f93b4c3161010001	\\xd01281931359f1dbe51ba6df2a2233afdd54ccd24be2867ed415f523a0fcdb8c53f7502239b5e42dc2c216138e448e8986022c7eaa52d48d728cf903b158e70f	1682240590000000	1682845390000000	1745917390000000	1840525390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
316	\\x02b7304c8e845dfe0e021b7eaa274e2d526d3e6968411039cf540aef6ca98f782e59a1c12d57c89a072591b5fe50c42a64e9a44bd3ce57a9a9cab9dd5255c73d	1	0	\\x000000010000000000800003a6c1d6690050327e341c360f98c108258474ea5f54460788c6749b8ee61ee3e77fb7d03279a7aab1b4b0ed4c859b26bd332ed585496bfb1c50e35ab5d776a636211ee4b8dd4ebbb8a0ef62a6c62a3fc32046bd247b3d7e5f90751134a03a22f0d84026556c33cda13afc685b7d6d96417199ca56bbf3a4eb0371f677cb916f47010001	\\x5b83814f69d35e076c6651d4170154193dd9599fd444ff0f292764fa19ba1f4a912cd9e236a8de74033f1dbb76cd7244b1802d1a93e98867301dc841d389bb02	1690099090000000	1690703890000000	1753775890000000	1848383890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
317	\\x0403403f5ace8242a7044a95a391ef6fe5c5783f0fe5e105955922069e785dd0fa4ab1f55d066d6454b119357fb41d30e148cbf04895a96bddecdf11507d4a93	1	0	\\x000000010000000000800003bf814ecefd5c47beabcca96eb4a91bd270841955e64ea41081d30c9fc364c7a0177333eddf3496457c04dde064e1e5ffad1905b473806c3c5cacef8abe0067d30e8d064ae843168a6fd4cb46a6f3d5df016e30483e5103f39dc897f7bc788635f4a23091b77aec7efb37ca2609e3951d1ccd0cbfaaf24cb6476d046f49018ec3010001	\\x35c635d907271630a209ecd6b0822f3f470150532b1376ff6cf750bfdd059996a0f67bfc72b8ac795b9023f950924b3369a25a91473ec449b23ad6074dc1c30f	1682845090000000	1683449890000000	1746521890000000	1841129890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
318	\\x07c73faf631f2482652b5f6726331f33dc1360f172e18c7549736e2fa84b2bb80054a9ff761eec3f48037d41cae99513ef04cba44da01297e3b53b8967d600c2	1	0	\\x000000010000000000800003e6c6984e174bf79a54141448ab0c9393523082887d36c0964e00d31b3aae97afc351d81ab1e65cc867944b8c2a0331b828dfc817d7c9951bce9acd9f4ab3a9eea3ee1d79cdcaa9fc48ac4fe7ad8d3689b643d788547d8ab7efb0c21fe1ab95fba5543066539d83ac3488d9f2c19ac230f82c16db3c33223134d28d9d2a2c2f17010001	\\xa4d717b2cb51c6bdda94a5e39f554b3c9981e2bb4508c562d8fd030139a577f840b26b601950de9cd0f5bb466c211b383446da5618472fd03e88859f1459190c	1659874090000000	1660478890000000	1723550890000000	1818158890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
319	\\x095b63299045b621ec09fe3192fef3a00663967bb3956118a24542f842f5428c23a50380190d1b3d7bf9d9067912407dd3785265ddafb3e6d2cf87be956a3203	1	0	\\x000000010000000000800003c64ab40075439348c71e6c24ff49e1b20f441d8ba5108c7d8623841abfa9006a91c224d645483ac4193601d708faf703d87d50871991c6e0c5683b9b7c7512082a2c4d905ad45ba39a4fedd287e7a2001dc9276443bb96456da5565b212562f3f6744c607800d1475387e35147893754454c375f23edef739c4371814abe5995010001	\\xac73e292e1cac0363944512a162fd56fb948fb046c2858ea53ea964b9eb6aaf6fa04030af6cab54c68509bbed5f10b9b70758151949ac8916f84a204a204460f	1662292090000000	1662896890000000	1725968890000000	1820576890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\x09afbaeae476eec963032a000fc0c5ea83874d512ab1a41e2d1bd6693c1308eeda4ac22d306a1e2f0218b3f71955e23d6ac3aae8f2123e29453ca0a115c7f53f	1	0	\\x000000010000000000800003b29d82c5453235c0bcb48a269014e92f7b154a9ac8fae42594a77fa38ec0dcd43f62c50cd35cc73864ddd2038bcd11abcba0aa1532de115640f613437bfb667905c71a9ca00837b32b1d37ef1379ea7f3bc5497b120f9d397ffc8669caef65a00a1a14f304af9fb0a2ed1d98d27680b8e56a2209f2e62c1a6291ad85cc757b0b010001	\\x4b691ea46764c0939e8321f29151ecc4ea10991805c01bc759484097d9da36c9897401db87a9d49867abee27de9bfe18776a55e87e5c6a5995d9e45a1e81f40e	1691308090000000	1691912890000000	1754984890000000	1849592890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\x0a9bd18d4631487f17d87e506deac3c4c1a6a6b58dc40c7ebb248a1f8cff67576fc0eeb4ea52f900262c70ad8619eb008f1c960ae37710da23149309bd2921d7	1	0	\\x000000010000000000800003b83ba891182dbb47111f735019db499bbcee4c76c0544044fb97a51e863c5a9f3580edde7d86f521e01cc932837b7ff9b2315881dd2fb8d5efd9bd362c8db267e45225551d96a07cdf19895c6a2c2f6668976ee7e453045ff0fba4df83c9fffd8b7bf3b583c31cc9813150232fa3f4ef9838d5f25c744eec48c1c988ec3a018b010001	\\x63938e209fcf6d67ee80b4d85341a1d8495c8305043e0f1c5a666ebc530a80dfe6ff67e744ef763fb6590cc8c761b691da0c57b74bc1e3048fc14f36cfa1ab04	1677404590000000	1678009390000000	1741081390000000	1835689390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x0bd37c6cb9c3f3790144da6323d7e5571a6bf18965e17dad5a574e7af2bfb152ca4c4147acb0bf109c98175552ccca8ad53b26dd629000cefe41b69ca22944ea	1	0	\\x000000010000000000800003b352db9655344f5c60dfa3c77610b624a6dbd77bbfb6d60e739578ce9d21d3e918dd8d5de24b1d729491906ff6a10856914997e768e721d3aedbe9cbc7d2269283a29d758afce1b5681a87aa2141a6dc3b702b2db641cd505fef8b0ee4651bb42a3d94a132a12fb1071dc61c538e5e304340986213adf6cf1a9caa05af32302f010001	\\x1b4482256195386ffe6191bc77f9691e4373728e518737e981d09f11e441a9a1a0583f5b4699378e07a7c1b0e750de9d2c9869031aca4eab642ebc106804de02	1672568590000000	1673173390000000	1736245390000000	1830853390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\x0bcb23ef0c63bcff95991c64b4d72c34349ff1127ebffde07f4a0d2d4dad8c6a43fe6eae7467dd73249aafda45101c4379e6d40086d75f99badbb237a78f04da	1	0	\\x000000010000000000800003e7919eeb83b8785c72b8ffdb5883475f1e938f9ad427aedc9f67b37fed426234a89fb1762c21614a7caf3623b59c974d013cfb8833ca2c0224464ce937331b6fdbeb84ddba2982d719263ada31feb2416b7cb3bc52322c0d02420d0103c4ba206973e33387fc0d6f2c53c7349bb593602a78f0ac63b5be25aa59e22ae9e58033010001	\\x9e562eed72ce7f1aee21e217689ae45682d51121cb7c183f98114b3a273e27d6e59b26b3bc77f8d228a798a40142097e52f105711844b48b55998431dd165901	1666523590000000	1667128390000000	1730200390000000	1824808390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x10a7fb73fe5d47d4a38799e05456df5e577db7d86a6f4a0d249707462283875b339ff52b300a42c4d6e5009bf8b8a9f05d3863bfca75831bf72419fbfd689a63	1	0	\\x000000010000000000800003a40435e0c5cabde15fb413e33e8567127c003f2345a83a9abcf6673031a076ec0721bb681b44d2d2bb0ab6672300d2225835e7a0c8b5d5556375d22cb700668f854a7a3bced92f15c5bb086bbf4a99a1d913cc3debd89582c5b8c719a578fe87600834f2b1c147fe6bd7dd463072be27d2033ce8fa16a5af1995065c105c7c11010001	\\x59e9a5a0fe74248ec9f3af0d5ea905962d1c051d10facec8113d19fea02d3388aea3ec78a7bbd14580d482e42a90a1aec97589d5bafbd69dd69c37e78360a50b	1666523590000000	1667128390000000	1730200390000000	1824808390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\x1167533e6e407ae0679549ffccdae3aa82975eee5cbff020d477fd88f5a798a1c974cff9d7d737d23c31abe7d99f65a0c0eb9b3c71d1b38ec7888de61780dd71	1	0	\\x000000010000000000800003c23bc5a3169a19a6c5d7187a70b32b46900037811594c7240c8853e8a6b81654cdcb157e36f73e05bc2b9a7f311d3a976b0db86e431baf2f317bb169e4ab9364c831aaf42134178acd1780d80c0c4cdf66a5f01bba11b2fd574602de14eeae218b927215882ef2d3a5785466a715dbc2b52bb5867bee822e623e96961b04cf77010001	\\xfb47c70ddb67be569c9b172751f8fc03af5dda66f389838c0deb0a0f481723778f4b25f66eacf7a783172ca4a4ec9ddd4817c0d71a9cf7e3f3b442d17b8c4401	1671359590000000	1671964390000000	1735036390000000	1829644390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
326	\\x1207f29a8de466c018f43511cbbce03bee81afcb08457ed8d7490d83e8ddd24423a30cf8047e963b199ad16cafbbd4c41912dd0d1332688cbe5ebd7da2aabd8c	1	0	\\x000000010000000000800003d9eac1bac057d1cdc207e4f936db0c4494ff70265709bcea92701f05a41202d04927bd13dcd982f2ae5b99f874b0f7c87e9a724ba9cabf55d58acd2cb1b372c59afb5bdc8111213385df5dca0afe36c88cdc6eeb66de8800947a5324491e181fc40f5923b0dc0182e8693e37689e36932e4aa79b99a2d84609494761a37bf811010001	\\x67a8e5b3eb8925ba67cc0e95ccc1133594b0d67d09a3c2112aa819f67ac61ea0907abeeaaeabec1e9b361d3786f2799a337ca7504859b61df4243ff77e44ed04	1681031590000000	1681636390000000	1744708390000000	1839316390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x1503e4537c15d523c24a5ffb20d9e5119391149df11816cd48acd54e5117be30cd954d980f957a3e110c31d6784b08c2bf604d929dbab716f62cd3a0066e1c03	1	0	\\x000000010000000000800003aead1cdddc7360d08c7930686d41446b61a6c52442df7d58ec72e26c152fbfa571e2b06d201a58c6c18a1bd480c7acf6f9e311a1f4949776149a9fa43bc99f62d8208d8f529f4d6e7df2e500187b2a20c913b59e84bba5710876d764140b3cac15271da60bd21aabd72d507b9c504ace98293a66bf3f32952d46e622431ca307010001	\\x150f925cede1619755493c6ef9431bb45847b615aebf288f46bec52b4623a0e6b984416964c47d7c9c27c56668fdf45c39ce188e3e15204880fcf1785f19cf00	1677404590000000	1678009390000000	1741081390000000	1835689390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x1a2baf055b4cfa33b4892737b66dd8c95565f8f06b008851015d097e13106be2bf41ccefd228ce5b2b9990cff50c438a1bfc3b006de5da60436f4e7623e424b8	1	0	\\x000000010000000000800003c0de13ab113d8ed57f55ab716cbcffef0b7d1c5490f4b8052d62fbb8029ca3537b670d40f5d6ce89b0e92c4e3129019417937779b4f5e61cb2fa11aa40d9e5e62ba7828f2c09f3e3fd862b35f28edb9e9eccef8e78d7b97c53c1f2a743da357d6fe2ced26a737519fd6d4cdb7f76d0b7c3d7c0c839dd1632d4dbb51ad5f19ad3010001	\\x7b2ba62e3b544efc2e6942ba0751dca3f9fc8f71fed627d80a49c8b74dcadcc30ebaf1d957fc0f5526f6eb24deb0e93be7c898510d8c2adeb104560fc6b65406	1682240590000000	1682845390000000	1745917390000000	1840525390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x1afba7e3a98ddf6b5cd8dc4a2a1fee6ec25846cbf38403617c60f6d8fc80df44058feee430fab7ed98e8a6f0a6fd41a70b709dc20670a405dddcaa20ad0114ed	1	0	\\x000000010000000000800003af5059136948b36e441deb1827f843e5fc00feda1f7ddc561f952ea26086fb1c0eb7892c243a55bd2dc816abc4e24323e3c2d50b9def90624b4c0ea29317f01004c79221cc9c5cedd2959d3440a56914ad121010cb38b93107ce64658f041ba32fc14099dfec7705563bf96f3ac98b9015b3e948e26658b3cf522c5f3cbe3b2b010001	\\x27ff4ccc9fecb862f4911af135fa224996d27fb07e29b3c43072a90e2dd00a2e67899674e9a40db8cc63cbf9978c34e5ab2cfd2c9e7ebf4e8227d7514f01cd04	1688285590000000	1688890390000000	1751962390000000	1846570390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\x1da31a8f3365afdfa91177322e54353e5cd99a654cc8245d1953d9682c11260c3f94e6c1eee3f6dc7b230d4ae4724516bb9002b7c4ea0e48c10e9f18c1b87fb3	1	0	\\x000000010000000000800003d210adb3449b69600aa11b29947fb80c174f6b30a1648a0342753ca2cb536d271d18aede816a8db47020fd44721dd19454662a5ed55e7573aff99f0f06d6bce5844e67ed4f146985e3f0fe9d611d51a579910ba86b42d17ad5864376b65bf77b591f0de2c68645babf1a962cbbbdfbde3adad3867e03dddd5e0b79022423f127010001	\\x2eb2b9dd5570934e62d8ced4212e97eea58154f2a880fe2a4bb80e08306a9bb6739de69438147107654543ccbac4da7d99622a2d52e3be443c9d64652baad00e	1685867590000000	1686472390000000	1749544390000000	1844152390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x2047898184ca164426ae685b20d87ee77e329951daba108d5829256bb2755951d7c9e589e1dbee6eef46973e3ba43decf98fd54bd626ad24374cdb9ce0f8be06	1	0	\\x000000010000000000800003ae09302f653db812cbba9997ea493a668779258e4275e319cc79f6fad5669bd500a298d3ecea3d2254458d398678ec6e61506054f1b6e43ab24a484c8ab6f9282f5df9468c2e1ff31ca4fd20cde2d12c5eb4aa986ede96e2cdc83c268c55039458b91a9f11a831706ac37d67fcb356050189ba2ddf1fef7113f62728ee0d461d010001	\\x67ce97a9521fd85cd03c1cb40dfc4650db90660de8d4eded7d9dfc58dbd5eb7ca8c686b2a9e1f6487d01656b161ef5d436e34238275492dbd10a2f137a4fab07	1674986590000000	1675591390000000	1738663390000000	1833271390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x2417895fc24f2d385b0b63efd0f8ad26531ec17c5b5c9432a118cf0beac3358fc6835aa9d1640c9b92ace9d1d6fa292dcfc06243e1816d4e328101931eba9e86	1	0	\\x000000010000000000800003d8bdfaebbf238184709754430f22e96b40bb5c768d5115b769fec21e30dbc301de3f8baaf7402951192a817fafa953b1c997fc7a09f4f57b7e489dcbfae642d8d102662df6a56618e00255b22eaf82f4c857f111dd1dde0a50c8b93cfb5f6b831a4c6470540265341908f718f5da7fa37db485c27ecc7ea4f5936957fc35df71010001	\\xaa403726b9466d07c4c820637358dbd569634dbbb0386bafcfa14e42b1b7b1391f7eade62f3c7199b53c348786e4440eedad173a3fc8a1aeec8b1e6177993203	1668337090000000	1668941890000000	1732013890000000	1826621890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
333	\\x2d8b608fe067be20aa4d133c8857d3682fde4f100af126b9f53e4dd045fa57e2077dc0e1ed42e7a2ee11ea185e9a3dc739aedd78706ffb8a8a45f374f945eb22	1	0	\\x000000010000000000800003c340167ef470ed72ac5e3c3ad60a57f3307d823412336956591e804e3a96f2d19e84258abec06f3ddba1b95d26de6b4c029434b27033f1dd650119ec1dd9b67360fbb36929e7580dee49cd2561dcf46057a904296c583291b943eacecf1633c4fa442785bdfb95b90487938d281684dec8fa42ca6195bdc576af59ffe3a010b3010001	\\x7feeff1f1e76e91da6d8c9835de40d736c8e5bc35bb69d1d981372c2a5bf4b90aa19c2dfac9fd63dcea31a80698d8749f71419ddcd43164079633e64f979670e	1685867590000000	1686472390000000	1749544390000000	1844152390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
334	\\x316b3876d2f85c5c22020558a3ce7f8f5da7ff8c4ae80e157ac51db706929017502848e4c834d6806fcef4ac7dcbcf70db7713637faf4a4b4fb187e3f15e2abb	1	0	\\x000000010000000000800003d098e6f3c55c232a1d2e820fc0e5b923f0dbb6df80991c86f5b1b313ee814b8987a2b386b23a763c5629084a87b0212420c603e2d22f625348add14bcdb5a23f111986b48cb98e0063a23f535115f6ff7abdc028936120372e2a59020f20ce32d33e058bcc6a12f5985c21fdf9f41fd29709fa768dddc861fcdde3d96d80c63d010001	\\x8df1ee065c3184f534e9ab04fad3b370b42aac715baf7891b2ac0e6c59ab455163e7747d357797443baad236e4adaeef49fcaac2f76e3b314550199d25aca202	1681031590000000	1681636390000000	1744708390000000	1839316390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x32df6742bca6e09a182f07844209458a257f8e620612a5f6b910ac29563c4432109845b1f337f3e8f42a36d943ec7a62104561c81e83dbd918383f176fa90a18	1	0	\\x000000010000000000800003c6ed9aae4125799fcfd8c4a4092e1b015ba2ff1966d249cc287eb406153632e0b90d4218501dd8b9b9ae800a3ce146759ec141da9019125334e537fdbccb534656b4879219fc389e06d615d34d16227ea267664a0b36bda3d22881520e3d760a7ebf2cbffcfb96af4a1546801a04d3a69957b64efa00746290520055aa1eef91010001	\\xeec4c07fe21cc0b55f91ee9c393b3724fb76224e35a647f752301b71779913c14c4a6b5f2e6b789d34e98b984fda5bad4bac8fcda5dba081599f05d10315690f	1687681090000000	1688285890000000	1751357890000000	1845965890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
336	\\x349bf4a1061834756d343527a754000c131c3586d5dcb2bf55613a69e77884616847c2bd37ae9594835783eb2cd3b41fcdeee0936cec52046cf75976b219a96d	1	0	\\x000000010000000000800003e6a0bf7cadcd1698125d114b6f1f373ca48bc64061565c15fbddfbf3645a337f5eb5607140636e508790e9fed063505145c4f66f78c3f78719b0aa8b4c5861af4bb6802eab15b406892d17aec9d4e9035f8a4bd2db5a140d5d07cb3a732b3a2522f730969a19ba802e469bb33d31a9207c1ebddf970d8209e7bec0cf1bbdb879010001	\\x0d15387e30ef0c57357e1e88636e5c3822c28472a8377577b4187fbcc9b89f8e3c40c626c8de2aa8e905f7a12fee10dc186889da0229749b42edd0eba8239d08	1687681090000000	1688285890000000	1751357890000000	1845965890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
337	\\x39df866b80e5d64926452c2730ea7ef3882940d0a37e604f7c44ed0566ef64b12c38faab0dc4c2d687ac1c3f5a3baca7d4800958d5866be2170d1a6375b18381	1	0	\\x000000010000000000800003b97200053ba0a706b27c1290969fc45a7782be174ef0fed42a42f63f4ee40b12787875455e8df0aa1d8de52e907d61d08be55bb3018b72262341def5fa29c3392a8c81beea4d6ed81409d518b02333199bb8a63584a498cbd1225dc42a3e3501190d709bf492bf63877fbbc986bf714e5995f91763842061b75f29045baf4449010001	\\x72c69c05c002f68889e63c7c07965a68077bf1ae23dd0223dd76b7edad8bb1ecd5e8156ccdf82cee9648820add6cf4654f6bfc1171cdbde1e9f530c8053cd102	1685263090000000	1685867890000000	1748939890000000	1843547890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
338	\\x3a6bdfce834ed8684e990af4e4d0cce87e164a2a119ca0ee2abc76833c5cf4c760932cdbcd1a583764afd467f2de8f37d05c038fe2ea3fc33caec85bf2dd24d2	1	0	\\x000000010000000000800003be10ab6d4006df31f29d2d51d69c2f590e05eb5499aa9ed5bc7343f5c21fdbdd97102cad6cd97f34c8c097994665a3d4c7b8fbedb5544835209a65c982c5ea2373f6dcf885d7063d2e984ab5cd1c4cfed7aef0e162ba6efa0d3dd4be152ae13b0e3d1ee83e031e4686af6da7f75a105c55d1f873e28edb616f811efd35887b67010001	\\x596e98141a235e590a43aaee4109e480b2bf3bd7499740c36f5e9f786ba53a70005cee53317a3fcce15761095f4546104c0582d61e2ae5fcc5bd57c54710d703	1669546090000000	1670150890000000	1733222890000000	1827830890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
339	\\x3ca31417d974c5d6c468861a0ae530acba4d7359924fd4ba2251fa2452a631b45bfa49bd8d2988982c680a3d745a553c3d03af26b04d271633c5f6415de7ca87	1	0	\\x000000010000000000800003cfa2f5cc973a93d225b9053ad151af1f3352424a60f2af5607bc06ee6691dd742602622a6680a7a23fa1c6892baf7eb1689226eea80531dc002904d09290795b26ffd3bde14612510e3bd1fb0b66df4efe30c33bca930d072193a38b5b52a2c50d034f7d103872ec2e03ffad18b3a7aa492211db33880abeda158a97c594af31010001	\\x1b1d452a8f3ed8a75673de3b80d553cf1434e41083c3da2720c75e4ec4fd5c5df9a81ab686cc36b7ef04ec46e7982f8cb88198b79949800c14497bc80436b90c	1690703590000000	1691308390000000	1754380390000000	1848988390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
340	\\x3c130eeb13775dfed8bccf01e59e898270e487dafccd3f7748f81fddd737b942ecb1eb1b0e3b840d0040c86b770381f1f5c76ed2342ec3eb460018d71ed0c680	1	0	\\x000000010000000000800003bedcd30e9fdaaa0e645bc0dace46977b1bc5a574b2fbdb2575d0796bb9b9366a7f36eba2dedeae39108c49858afc6040f3c77fb2f21ae18c9a9b0b7b40b18525f107d6fd612672f6eac701591cb79f818ab3782f0d41e060d7da84018e348248eb009dba8eee1c44694c4761191c840919b5443c9166b92df2b573b17db786e5010001	\\x0b6eba687c24aafb1096b33517033a76f69535ac40cd58e9779bfde86740aeccbef7c6bfe14aee12da84f15daf897f676707bb298c186a854a8f04f661280808	1687681090000000	1688285890000000	1751357890000000	1845965890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x3dbf4c3287d282742b93b425e0272f7fa055f0b28daf73d6692d3d8f65243873801ed5076b83a4d41fabbfcedb19f1e77913eb370a6c60c35391176838250815	1	0	\\x000000010000000000800003db223d4078e3b62ef6555101c4bc8bae0987d3e0a9a14db42f5705f46bbaea90aef2da3a6b2a72b3a019f80fe588393c30927f7f4e1ad11ffaf9b25c07800838cf92f1bcd6dc51ed0053b28c987a280b3e84606dcbb8cc5acc2152b2dfce5d6802cff88dc41f1f7b236c00c220dfff47274f2c1022d2f504a0c35ea47d615f0b010001	\\xeca815facd1677490b22f4c6b25120419f88fbb64abd206baf3b56c8c615f33d19a5e429653278fe396b50b7dcf811b127ebbc14c28be568204f729dec694b05	1689494590000000	1690099390000000	1753171390000000	1847779390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x3fcf6112f642486a71308ae28eb585a3e79af73e102a7b04ed66d7c35969644ffa5ca78947cfa6bf1c8d80c404355989d325fbd0ac69dce0be51c67e21ddd0e0	1	0	\\x000000010000000000800003afd183643409963151287317747813c341ce269d56c174838a49837b5283ade63e54c43815250d264d2114705b856250ad3fb2ae1ad3a684457f714fb44b20ddfa867093bc4f230bc985ab437d650497a1cb4cfdee0ad2c12f7441bcb66f28da63e8903ba62e2890ef6dcd6e675ca736ad61a05bec9b4387134e9f05173df985010001	\\xf803d12efa42b2c45025af9f7ad2b9a506bf625da8dee0a8427c994b891281ee7a3f667210597e635eadef33edd1a34d925fafbcbce9778e548745456176340a	1682845090000000	1683449890000000	1746521890000000	1841129890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x3f03158b75afa1252a348a7b71cbee72d2defa9f7f1870cf4a275a2358d8416c9e3836fa9d4cb5a7bf6ba2a45a1bd4bf8f20f29415173f21ff5417b051c2501a	1	0	\\x000000010000000000800003c04e644c824ae283a8dea6e5ecffe73c90e621f672283ec47b798a6c02a861e6e26c7297603b04c45c38c9649cd2a56233ca5265cc932259238f8ef754f680c3e3f6950750c3896bb52a615efc6397aa6145c5364359945f71f5238faebe17e83253f360e5dae4750fe80bc09e9bf77b705261a37fcba0e0d642775e49b6ce9d010001	\\x274a6e7680910956f6cbbcfd4fbebfb02ef1ba058188ae8736e47b5b2502f53751b6c1f7a29d8590dc4d9442f4a4f029cb577e241a55486d3d06ee34bfefd303	1684658590000000	1685263390000000	1748335390000000	1842943390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
344	\\x40dfc4017fb8e7470c988fc598e172ed8beeb1381fe183dbf19a6197b3523b5e8f0249f690ac7eede53118a0ceb475a41d24319735c78336f092e4bd0b77ee93	1	0	\\x000000010000000000800003f67f94fedc5e3e9300519b0d8ab639c1fd8edb35f6e1e064bd327f78471538ac72f89e8cf207542f45c9e44cc9accdb273f4541a7002d1324c7e9eee2f3ad229e3ff2731b12ad4ba5ade7578073a7332d7a79326c1b0629c4cf2ddd68758c1c9ac3fcbf1ac86b51b2fd9841dcfa87ef6dd8bf2b5b062e2155b3e6fb2a9a7563d010001	\\x67ec7702c05e9669f2de23163d2b2f2282bb6c41029aa7347a0a825e47b8e14d665b0777ce0c37dc16314f6cf48acc76be7c7e057eadd05aed18bf96c36b9d05	1685867590000000	1686472390000000	1749544390000000	1844152390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x400f148313972e325223d2bd4ae5fb55c53d31e2ebdc2956a70719bfb90dcefb6f90d33c79dd652de22669348d148d2c09f4ac728ef409fcd4557a5ce74d58b2	1	0	\\x000000010000000000800003aac58ecd922f2964183be86843c98c3f623eb9313de1a79db82ba152a50dec1601985ce35a06d8fdfe6fd078ba57a32b3ccc282357fe0234fc9f93900c9308cdcadf5687309ea7fbb33aee24828bbd97553359bb18e6acbc29fc1594018119bd939e1bebdbfe99704043cfb5f4c3db60f9d36f0b8675061660340226bc10fbcf010001	\\x2c3929df68580679cd69d6ae3750ace0feb10701ff3a25d94bd6cbb9a6f4273a33ec4f2212c59cf8456f303028b6781af3673a4a88c2b7a04e5b121948341a0a	1687681090000000	1688285890000000	1751357890000000	1845965890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x42531e359925f2702d292c666f5630cd0444b4220b05367fa7281d8f1210db81788a02265709686eb06b490606988a090e518662ab379d586ef740e1edfcb557	1	0	\\x000000010000000000800003d806c1eec262b09c576b7f29e6f6c6c3326cce24ee952e13f64edf6cc70077e59f5baa393e991b043aa01a31709ede37f1aa378d5e07dc64cbecd7f7e97bc716f3afe39f5e29a75a436ffeda4241835ad33f74edd6d888c59fe78c7036383d958fc84d10eef5dd6822fd5931993f0f0d6b9484c9b164a9393430057f810b562d010001	\\x88c7936a0345cbbe29f764b1486071657e19db24e4e015a08af13c7df1d2da49ebb767a77657845120ea0441e5f7670672d408dac2a992363e0f85a5130eea0c	1678009090000000	1678613890000000	1741685890000000	1836293890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
347	\\x43774a857c62fd9cc51aca866c59a8f0abd794d6c409469929937647b60bdb0ae6095493c8319de58bedb81dfb9559023433a9a0aa5319128bea918cc98b84c7	1	0	\\x000000010000000000800003bfa83379d8abf518dfdf3bef5573d30157ad2d93f0ffa4b1ea0de32bb87989f452fdbf3986869ed13ba06af27efe85d324290c794aab2853c57f620e9ce5ac801f4e4885f4db8827a170b90db62566e3276c6511e04e6f5166132802a1bf7038ba2f9d7c07a915d84607929d6b8203b0551ab9aaa6bc112b60ca16f97873f801010001	\\x50f10d19cc5b1c6d1c9de5d43c4e72169c96639cc96cea398479422f85355eabc9357f549a0380673953e7240a70543caff9bc96335990772a4a26065053cb0f	1673173090000000	1673777890000000	1736849890000000	1831457890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
348	\\x46d7148c60f51217a7bde58b48a3bcca4de0a380a80b9d2e35f17f26a2c50a2877ed3a4ea56cf45d8323c25c7ece71158eecc5a0751546d9018349b870e3d3fc	1	0	\\x000000010000000000800003c811a1d4df844d35f2f84d91fe8c5ac5ffa7194930e053c2c60c1d5b9f25d0c5637198dd10acd3e6c6f272ce34c57cd8754eb2d3bf929e794e0bbd2eb314c88af60daa78761b12eb761026eed53bb59bf2dbfbd8de6c0bd907a5a1d50efc4529fb2ed0ab2f7b848e937621f002da977125591fbac22dce69858145a1ac98b3f9010001	\\x70de0829fefa2af43835ee47ed72a1efc843c141fcd287a9760caabc678d7321a5a01c25c1061bc205641aca1c4357d629e514f5a80125ab339324c262ac8b05	1669546090000000	1670150890000000	1733222890000000	1827830890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x470ffae5e9bc679be3d319b515684626455cc828ff5dd2cd1f54943d10aea91f82b8e93a730eb1cb7a1d34817618af32615949e8c894064a638583b0a59d4752	1	0	\\x000000010000000000800003dc239d0fb75a403dbd69b750f950a092772b04799ce925fd6a022442fe1c63bb92c3c24ecf80c5c06d2b4474ce3f84605141815b1c98c0ecd16aa54b418c55a51c0fd5e063f139e408af2cf42fbadb0642e6f59e309c2030e10a9f25d4ec4d26d8a68318f8b5de6fa09807c43a348c1c4eb995a208b95d2f4e4328073067b16f010001	\\x30af6b353cbc3683b29eb9c2546412c523cac1cfae222a02073d3ab0b86d22dc0c79b67b56163f40d690c5d1839c58f4ee01cff2727e0fc4d4404d305d70f00d	1674986590000000	1675591390000000	1738663390000000	1833271390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
350	\\x4883678c0fbb77eb3a43955b09768126f637ba6d23023bc2c3f119104061f160573999453b0428610d33733e5da5e5fd64e4d64935a34a1a70becb90499cd1eb	1	0	\\x000000010000000000800003e6eeff1eb70d254cecc9836009b24017502404a7677ee19e3d7ae63fbffb69dec24837bbc9a30044db43833389f9e43d35d6493ab0857e73cc5bc625d96d976c4dbe111087757b9c77e7894bc425b45698c9c8bf3ded6d7dff11876995168b1a19f8544818ddf0fbfa2de8827514cd74a1df6925df6c44f6a120bf12a4921d49010001	\\x7547d9aca3cca6609f2327ff313387712c9332fd80cc1c6c88da6f00d57471a777d3c07014e1d4fba2aa80374c3c5dd01b67a29458a37f755c6461c9f7de7b0c	1687076590000000	1687681390000000	1750753390000000	1845361390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
351	\\x4b4fb96e80376cdae97973d6bf9de7678ac97bbe9bcb0d21c9e147f6905764a6be6275ed9126439393019f5320a2d926b965560235596013bdf4394185d7fca4	1	0	\\x000000010000000000800003f238265e6b357be164167b943b83c9920b3fc551d4bd7353f5af537baa49d13fa340a8c197d23c94e5e7e6781a675dd04791aad2bf0d98de266c01b0b46b5635fe9b1f2eaa15bdd360d03069464f1eba2603c793c02f30e7fc704b44ff442903b9d861df66f69252308569f48eeb072a14fcddf380abc4d5ef7e1edd4b9ed443010001	\\x47bb92f9bc3378f65a91afc4d261560e75c7c0c5648dc940b08849a612bdfc98ee7450e839dabdafccb1a8b2c705e4be372fe59dab484f0bcd76179dd6dda505	1662292090000000	1662896890000000	1725968890000000	1820576890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x55b755a8411547e3cd9c5d3d9a93345dd2737aebb8418e660b52f854c62335c05839fe927fb5ff814fb047f3219da56ef45de156b19e6729f8f57df147f85642	1	0	\\x000000010000000000800003ba7ed645bb7aa876c93358e560fa1c18d66b33c2c3f46a620d4195414b53cf3415ef5ff8e3d8934d680e051b66ee28a35b2d002ea5f400e3d234fd4edebb01b14fb0ce788007f3efe8af5ebedbfc8eace9c47a5e4357e4443d76021dfee5c5cef0cc981ebc86a75688d365d6a1eab5aa3d8ce497b9967e4eef36dd2817e3cabd010001	\\xac340fbe33bd0a1b279995a85c16225673f543cbbb064da74cddee4c2e4bed9c52d782a05ee5d46c3c6c599a84c8f69c186e75665803ed6034441258f7c8c100	1676195590000000	1676800390000000	1739872390000000	1834480390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
353	\\x574fb69c0fe5f0b002c6277d6d453141736e16e474038b8788336bdb4688ba8fa488240e217d8e268c04c317f115f3c25b813af85eecc85a0938bcce77bc4058	1	0	\\x000000010000000000800003d7712265a8fb6a3a56414cd6b1e2bce595d23ba64f547173f4546431f627d4da1bab927075994158e24395fe1ba6bbba8e5d5de88ec9e75c7fa559cf985fbe3b3a96a97cdf57b02db2dc0ee2ab5b2837a4a29ae143bd661dfd9118d2eeeae7e25aca3ced8d17761b82a0511d832e35cf3264bc7fed92804a592250d84b262999010001	\\x90f5597b0d51db82b114c7c6d8cd4b2bc61a975d2f21e05716d065703377c0e0338657ccc88eddbbb84a75a5493aa46dca956e173e77ddefb6219dfb97cebc0a	1684054090000000	1684658890000000	1747730890000000	1842338890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x57e7359108d83b6e88e012d8a6abd429df526519ce58796ae397f3813aa8f68bbf381b818cfcceb59a7863f3ab6a258e6d8b8feeeb0564bdcc0f616bffd5c6fe	1	0	\\x000000010000000000800003b7b2e7210a3002f85260cbe7f159e985f54be0ca524dd4924f6bd35567dcd3253250ae20ceeabf3203552faff149e86c4440f49097b02589c276ef640a16a0052081ae3e22d6d543ab3385b17a4a77a572c13d57ff2439d8e6557a49ed5a168546b2e8589352d1b315a20f9a61073b93894239311e97b118755dabbfaa1eed2d010001	\\x6a771338cd61d6336d12fa014902903074533603358b6c0d052a8b7b67d3d5e050f895aa4e31502ddbf8a135dd66a25f08e150894cde562038bb32e6b152dc03	1688890090000000	1689494890000000	1752566890000000	1847174890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x578f35ecf9bc828faed9588da7e0953b25f3fdd08149d3403611ccd88ab580c3526959902d16c86641e96c1255e16c0a7d07f727d29b8ba915a9485b014bfa25	1	0	\\x000000010000000000800003bb4dca049c5f17954b1bdb5f185dd7b5f14e2d1a282b19076e5a42adab20ab1b0311079a246b419ba4b957e0a11bc7f0f5a9021343506d712a5db5421121b3d9e259b850ebb7004878105f90cf6026031387dc1aa2b17ca57043527db8698d2bb3eb373ba658e697231951c14278dcd099425ee4c966e735b6fb862ccbebc603010001	\\x31c144cd5aada184e43939d5e39e8e0c12a000b32a90bbe274b0a2c4b1a50116ce2412529270958e32993308b6cb2c3336c1ff628decced0c9c187672a94ff02	1674382090000000	1674986890000000	1738058890000000	1832666890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x58e3fdb50b6c539957640607528a7214fa89538c70cae8230d4ed41a2fdfdb1d49066b2d6a985f97d2167216eeab2c8ea2c6932d1d5a94f4cea14bdbe68624f8	1	0	\\x000000010000000000800003e854abdab78c345ecde0d7a4954e737b83e27e5d890169c9b63f682e09956d577ade663d352a62cc56e49dd177eb00753c389d416e7c91a19f80e6e2be8c50a3688e082bff523a6df6a9be3daf96084dedb2b195f44cae7fe78bf9db58c7c55fdaad09e665083847f538a55a16d831d5fad13d29476f9eba9b3c7b369373d941010001	\\x52fc23f2e99da4574e87d36735803901dac1ae3d4953a05003f14adce06869fd7299262cc6b1a38e58af42a82d658f0b6e1e680bc6f21409b5f6fa5f9dbc650d	1673777590000000	1674382390000000	1737454390000000	1832062390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
357	\\x5d97865cb647c9bbf80d412d4c8ac259b638b538510a173b398f437b7db2cb6874b70316ab8db203c9b2ef4f0007a80d072d584bfdba46f579962e8bf1abb282	1	0	\\x0000000100000000008000039c77d6f3de15ed09932ee79cde2c3e881d8833952a6d7af56007fafda63e5c34dab14dcbabc8791d5dbbd98388a373a213f9b7694fd3c9fc1ba6b87d0b44775712c3c83f588f2c9372d09fc54c5bb1013ce919e11fac4541a6ae3963308ea814ce94e0e5f8be661d5d2fc6f6ce292fe2ab97243aec4d7e106ebcbe7aaa586083010001	\\x5a1d41683eb5b08aac3419112810c01f8d72d954fe710486fbbc61e1d6f3c0dd97d3f3f65199e44e44f50bff3dd195dd087b9667831cedb1e7fa1b1d49d52f08	1680427090000000	1681031890000000	1744103890000000	1838711890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
358	\\x5eeb041ef981851bee37a3a2461f87cb52a1b5304c417ed69fa9191173724c2f785ff53a69ab1c0d6b17f95e211df95bb91ae82125fd768513f1d7e4596a66f3	1	0	\\x000000010000000000800003c32240ad46bfd54803d7d749ea50a7617d507275a74bbef7ba78aa42171ee7973a85c110529260c33802ec454e45032bf20db42bad374e39f6f270bd8b1606e6ce77d269c222d0ee84cf619cd335dcb71bf37a6875151fbaa7dfbb9ef0a5888c13d2f452efde0c074fe9c951eb721c85b4fe344ed4e9814b3ff67e96af02a87d010001	\\x2751a9f575528d2d0ae9565e901c96b265450ecdf6c2df2f4fe177479522ed92c8fc6b5840f157df6df179b17cd1f3b98ecc553919a4a970a533195150f06309	1670150590000000	1670755390000000	1733827390000000	1828435390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
359	\\x606752ed327ff543fce6580dd0effdfd022bcbdedff627437b67bc1018180aaeda781ca1c24cc0cb06be1c0ac7818e9e1bab37d09709d2d04614d93f0b13e945	1	0	\\x000000010000000000800003d30f930ac456b076b19ca40279d6171c0ae9e13e873dd60fd02b9835e7532f9eb545d5bdeab63ac67ce19b7a53aad065bdcf1d2a33b0f6a05fa62bdf83de1b083c075dd99ddf2c58e8f917985e559918e47cae9ef071a757ad39af92214c9ca31c085dceea3371260fce572188dcb80c04894bedfc04c190310d342a2e375287010001	\\x692fc8927c5a866db03280c0c5932f986b4bb7823c1b4700ce7ab2ef6c42a647f859a5ed24f626a978203e2eb2d830bfacc088e8159de5bda8e9796448171f08	1691308090000000	1691912890000000	1754984890000000	1849592890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
360	\\x61b70ff1e815112dd7d015307209fbb3a015b108f16ace083e674bb152c329707ec9d299ce0f37a55dd77c1b846b330dc2a03baf932e5e9f55eca2d598ef7a5c	1	0	\\x000000010000000000800003ac57b536841b42c7ff62112f8ee5450a7924c5c2a2263fdf593dc8c6027a074b590b647fb2ad7bff116a4d1eac005d73f5184c2092119407af75680e2e6e8e094ce08adc96c76995c18aa1828a7cc3aae57b72ab4e4f0f4a9a8df832dbd789f44ee0c06d5228330d6cc0c72ff7720b0bf28693ad3b4b660069e3161abcbae303010001	\\x15572490d79a93cb381e371281ed597743bb60ee8b691bfa70b432fe12901d230cf0124162e088ebecec5e6e455b328b8ab8548b1caab6e619445ac248fd3701	1690703590000000	1691308390000000	1754380390000000	1848988390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x648b96753fd6683b04cf3a1a2093a7f398dbde8b837b289c664a11b2b53c76088040d3c49118a9826b8df87dd947b28c499059145d8a45978827d704a4cf3a34	1	0	\\x000000010000000000800003c250dbc9338579cccc73b6e2b7688e1df78f0338dd04c0ac1637a5f1bd340ea8466f02a43daf79a581ed9767cf8e5ae50724ca8b1bb49d2235c19ee303e7374a400b3307e71ebae58660459ea8f56b5c3065ad7507745d76fcda7ff8140b4863aded17de519acf0ea1e6c88fc532f133655ae1533d1837002d24bc5b058e69df010001	\\xe4e9755759245d087cca810c88f45f93d3b24eec3bfd74730c6483ad0156da8989a8de24e372ecb788079994dd7476abcd5aa8eb48f759cb2e146f7fe5c97205	1685867590000000	1686472390000000	1749544390000000	1844152390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x64f3b55bfb83c5023cdc71c5495747fee56edbf77f7339476c973387898ef9c3e8eff44c02bb26cc814300e83a57cf78e1aad66a2eafbb74b00314b9704acf81	1	0	\\x000000010000000000800003bc96853fa4a3c1277e67756a2be87368f7deded39be6289ed0cbba43fa1fa86a220a57da0c11ce751d668d93b001af679e13c5bcb2e5f5218c8830ad14cefb5536d4e88c958473492872adc549fdc6f70124f0fe63ec1a5509478abf42ad358f5f1efaf69343f0974b82384a4752fe9dd9337559be5aa61120df9ddbbb31c703010001	\\x402d6eb1434c23bc9cec4910709cd3b76f2d023888c35c3077bbb68451a546f993a6371f51dbfb94d52428cabb6814d5ace768b605e5195ae448bdbf41c43f03	1681031590000000	1681636390000000	1744708390000000	1839316390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x68c7d9e1660c2dd963221d4c5071a1a82408d51edabf5e5a997db492e6d86f32f7467e1df9c1b4dcb2b33746504c87859c26543faa65b91e2b3938534da0ae35	1	0	\\x000000010000000000800003eddbe0e471b9e57dd16f5fb65eb12a64f1041531aacfb3f6e197343a69326ec7a7ded96c59fad85dd125b2741f3f808e172d506e044eae140eaef6e712d89f96f1ad62f84894b9df7d5e6170712dd5597aee553de447d339827367e73e6db49cb1fa446df8b9f61c21cdd749502dcb4a00dbec891c241072bff3be90399094f9010001	\\x10538e58271d3299eb651179f2c581223c31a3ebb87acf91525e40e780ef66040297f98fe3e4bb25a6017754bb312c9c2e3768e6585c2fdcfe3f70d77589580e	1662292090000000	1662896890000000	1725968890000000	1820576890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x6f3f954bc42d1e8de72ece06d2f086cc83ca817ac1e575e1263bc379eb0abac210135bd540ed60bfacc79f0c5e846e160877238916e25efc877098be831e09bd	1	0	\\x000000010000000000800003d2bf68c94a9d4ce323747c9ce5d90d97bfb93a70071e76673f30672609da659be7a54db914e519a3a0ab3ba243705294feaa0bf58058d73ddbba9bd7e7384490a33c142ff5df022397e2922439e95d1ef1238806da9a461930b6753447e9ffcaa72302adf58bca4c9adc9d4715150590044b427f90b1fe5d1c0cd7caebc5d72f010001	\\xa25c160af63079fd839943c35747dd0a7c08bd931a7e1924d3cef4e80f37a141b2ae83c3471a0018166918fe8299e5cc34a0b742cc943fc88235e31e7683960e	1682240590000000	1682845390000000	1745917390000000	1840525390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
365	\\x71f39ed2e9bb35d62e44623bcc55ec352413ec92070962d991f4b4b83090c355c9baa21b190ecbe53eb63fd9d76171a90b20810a036397894333b26e04773241	1	0	\\x000000010000000000800003d5e0b9ce18348064120b63e89e8ea6ab52f8d26b9a32a128a572b03c0ec7b9bd603137e0d03bf7b48dd81af32c5fe9962dea9acaccceb6780d01086f187fe047eeba0ced5634192fa345851a71d12c62f04fe641ef1ef92c3b54db96174c963d6f2722411091bafe04ff1323738f87c86be1ac0fb1d5fad409d05dd7392fee17010001	\\x0e4f8f0476e5b0f9b4ff6e7e31c0c1d99df456d2e32b8509b04857dc1124c5cd164d380d2cc9b3b2dc108e646563d08bec3e8b9acfdd920d82ecc4dcf48b0700	1673173090000000	1673777890000000	1736849890000000	1831457890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x72e3d37c8c523b0584a56f8d902a5d8f21a4b737b2253748787dc313356a47b2e75303fdc457f116386654133b9feb83151cd5138e709297c1498e1c53f1e879	1	0	\\x000000010000000000800003ad53e0ef2b1b0f0c7e3ed460cdb1d5f714713cc375adbb924d8ccc87700214820417c12e6363a95f38f0cc43fd957063a88126108d2209dca8331eb360cad6d156c9f358a7801b0e9c365257c6e0ba17ad8b6d36f68a30af0b91026d4f36e721ecd0e9ffbbb3e6cc9dcd9589775ec737e3b10408222967fc429be03a64124b17010001	\\xc357067f60022c2d0eaa2a508d1aaa5ece7f761e3fe9f6b62d5b01982ae02160eb8e1576ca5c6028f5691a600282373bf00847f61c3c2b78ddffa71ebc9e7d0c	1665314590000000	1665919390000000	1728991390000000	1823599390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x726fd5a0ffdcb43585e123a003fa975041c755167e7f32f66c52008bbd5d93b9828cd75d6cb5387c524329209a2779d26b25d5deadedd9b6e8dbce6187675d91	1	0	\\x000000010000000000800003befa0af36e2069997950e7e294e551f04d516d7d606bf1e46da2356cd959830ae349b64320a0eb504f114ac9387a6b01948ca172360ab93a7f2ad4ddcde10e1428c1aa5e6a91a5a612402d755ac02c8d06fb4a1bcbc97879c31c381564b5ef2b8f6d354c26216c915c05656b462f97b8bb64801f7bfec010ae8276d6f6a60037010001	\\x57257b85927321ebc815a0bd022c4d3e916a7c54371acdc8660e7c7f7f68a84aac5658fcaf8120fbe380140e11a3aa87f798a2ea65a5db2792b0161442b60900	1670150590000000	1670755390000000	1733827390000000	1828435390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x73537771a6701cb8ace35ffe99dbda3c636d36a6bea7f7f57a4b7c7d8d3d41b23eda79921d9097c1c76a85da900811b89d1336f86aae6b8da43066217fa8b2c1	1	0	\\x000000010000000000800003c9c8ca65d2c0c2e25829e82c91472cb12a7df588ad0a225f258abfdd299149c44622efab0ee6ff7ef77ea2352ebf3b29140df8f205ad1ca69934ca02a2b35ba78e96d092bab551cc8be13f3df3a80d5fd35eddf7a2f3c368afa545f40ab0c1a406daa503e7c46a987e060d02e2d14e1bb95b30ea0c775052ca431d94c52a7e05010001	\\x423a525496b640dd614b370c8ae09af44487426361e502f45baf03b1b0c2897cf05adf25b6b4f4df88cf8eba438861578eb4a4e9a3a5eedce2338282ccac1b08	1661083090000000	1661687890000000	1724759890000000	1819367890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x78270393b1bdee33ef87a72f520f39cead96669405fe5a7ccb476414d9a32c21e9e2623483293dc83cec9e32d60fe70317686311a372decf1523cd3ec83f6568	1	0	\\x000000010000000000800003f0797cd2ade49e1c777d09204317fe55771ac4e95abd85c1a3509dc55b2987e04bf5cfb775bfa441399aa7191b11b70354b3f0e42ee2eb1be48719ec93bd16b14427e54c06654e3b1f4cd6f3156d6a93bcb52cfcd095b0d8d2e479b01fd71a5ee7cad9c609cca6444544254d368bbd742b5abab7ffb6bb755c78b28c31899e2b010001	\\x105c75616ed6e101f90f60b9857d0d1f7efafd934a5809f5ec55f2b1afefd77d38dbba7c768219b3cdacd4678f52118078282941b0e1040a9a0d25a999b3ca08	1667732590000000	1668337390000000	1731409390000000	1826017390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
370	\\x7bfbc4fb70b43977644772ff1e917428245ff7a3386910c75fb4b0ad66c247eadc60caf4b788ffb60703dd51ed868d0c19aa369b35e8fc061de0899aca798434	1	0	\\x000000010000000000800003c7f2906748452e2a8e113d14f5859e6fe74be4b9a09c5b1584d8ec7e1fa3dfec57eb1d73787813eb089e51aa2733106d37d246ba04202169d0108dc224ed82c63766efb9e4807400f64de39e44810d719d280ec1295b45c278d8e6495ef705c63c01cb3387a3f3a86553bb3bf0bfaf16f83749e39db4520d02acaff54e507ad7010001	\\xb9162a3ee26c0ec470b198b2b252b07d2547ac7651c029de39f1a89437afaa4445b574a759a108bd18e6f187bf5c2e001c7f8cf4a59665c499060f4818bc0f03	1667128090000000	1667732890000000	1730804890000000	1825412890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
371	\\x7e4f581dc1931dd5946b5842b9becc325576f2a56d7b33067cdd159ff91a8bd72bc8d440cd574efcbcd032d139d3e9e5394c0d7c0021a5e614e875fc300ca03e	1	0	\\x000000010000000000800003c568c218fa0f47d70de21088da2843764c0af80a18e3fcd6af517a819d4f65a6b7af46b3cc50069a4b5abb218d9e75ecc175d6b8cb332aff8ffcbda8b4550e4dcf6def7e35130d3c8f4994bcc77e31c3500a9290a93edb672527e308028679e6d83d68b2b2861e22f95d9a35cc868bba8f5d0014c6b71033c431d2c581f35da7010001	\\x02e30921a3a27038187bb5cae5b93e54798ef66dbc3bcba2c78e707377b0f5b62da9a1f3825b29cddbb6eee4a1570af533614940b7de1ddd6a32c1d02de2b80c	1685263090000000	1685867890000000	1748939890000000	1843547890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x83074021a83a250abc9e6d0e705302f8befbfc05edee3b5485a7ef4e6f050de2e61a584c493882fd523929ec2b2eb83ff559ea4451d067a24d7ee8b9147987b3	1	0	\\x000000010000000000800003b6d7acd3e8065e4b946806561d9dbe8eef3e7d943b73eacde8f7cf4806875d8c6ac6a838410484571005b5ba905e176c24b29e8eae22ee53394aab4dd6979dbb4a0a7c7a7a44193f26319d79cf056450f37a4720eca698346d2c0227cc388d638f584a6cdd0257d0bd2706e214fa30d0d569e573f91961e411ca04e41cd79bcf010001	\\x19ad82ed50b0f50ea6607590a345fa7e472841c092050a3f83c0b6573451ac8732722f4e801670dfc4504113a39318dcc88d3f5e7d81c6f76e105b88e521d208	1664710090000000	1665314890000000	1728386890000000	1822994890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x86574580838edb4039494be2c5a880b103d595633570f83001493eac055047395be1305f19480d85994968ef7a70e1e15a8c084d04a3152191bf80b47484a04b	1	0	\\x000000010000000000800003a924615573478e2178c349eee384393efc3ecfba33a984a44a43ccd8c7d04c1e5689430f9f17dc7d0f7d8aa499d80c692f14d8357df91e0066c5e8130f987052c4d748eda55f9fe2ac78dca70116ec7705a2d99cbb9d3e7731a17acbc89f4b6cba971d61366e62013d656904b6ef6df1d38132350f388c5e2b7635b5efb61bd1010001	\\x0e09823ab40de2f5901e3fe7fc7bc0de0eb5456caeefb47a2df9d39495ac21c22d559d2dc2ea9759fe2dc1afb3f32f4dd345c8140917ac0063849fcd70022a0f	1690703590000000	1691308390000000	1754380390000000	1848988390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
374	\\x88535af6826859fbebabfb6a41eff719e3ef13b91f525cfbd98f2307068a5f6b26992e655d18e4a72aa703387d7436753480bde2494d22f2dbd7aed6a1cdb7fc	1	0	\\x000000010000000000800003abb425e810f9cbeb696dd1f6bcb7a80cb1bf720ecfce8cdf5893034689483307d852a8eb6a6a6c139c0e404eee793c5ddfcb061c918b5f52d6d74b3d4d3b3b3805fb3e98c51babdddbfc716279a420ca879d0a0971daf80f0839820280ffb07624e1b958075fd9c4cc22aecce628b0c737daa4dad0e21c24832111610d6ea291010001	\\x92a2839fba8fd35a9374757a11ba4b74c85e1ab6758c17c1841f1f2cbda678f66dafaa05eff55caa6a82eede9f3d983ce93acc2efafadec63099579ac96f4b0c	1676195590000000	1676800390000000	1739872390000000	1834480390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x89b3008b110a13bc009aeb3a547338a151bbff9f99ad3fc80899e22fe9bfd64acde58290159e9e41d6abab0326dfabb36f2fb959ad8a1d5ab0385f7cc4a70588	1	0	\\x000000010000000000800003cdf2e7daeaf13fa57f87f489159b00c34668716e4f0471b9ec65eedadc43713bb3827cd7387574844c8c920d686fee97b8e806f97d07279c8986f9910d487aa441f2b421935b00dd1e6accdef177f1fd72ca75d2ef824b418aa0fe3e2262ccedb377f3f01af086238f1862c21ab3f07d65d6aa848cf825a4c5be6d4d43cb873f010001	\\xb82e370c5cd9655a65b4b5ecee1622f1f9d903eacd6e65f9de5e2c43ae34581ba4e0ec192f3dba69f69a7472de0db7ee7b64b880e39d7ab72e464e863df5e30d	1680427090000000	1681031890000000	1744103890000000	1838711890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
376	\\x90c38e3ec2f70c0889af59ad8bbcee62e952348bef638a082e6feb12b55acab754d637085992413eacef4e347ca829fdd298ce84de28ab16ee0462224ab6a677	1	0	\\x000000010000000000800003dfe9de47bcbe0c894cffd6ea9595763dd9db956d6761676bc3b2293c8dbf3ab8f933c09b747f7a72b22cf06e5c02ca356e8938f01a8b17f71b24f4209fdf2f0f9dbb7c5d1d2a16a229e5a78509411444ef1e961c8b1f970e5517c636519608a733199695fdf8151eadbcaff54324ff98a7129da596baf7f458454eb113df686d010001	\\x52a64d531391ff044676ed89d408476d5f0b2636ad6718c0fe106b737c3b0459b5697eb3f96f6ed1408fb3cd4d2ba2f19ea112b99d030d7cbdbb5e5bfdff650b	1674986590000000	1675591390000000	1738663390000000	1833271390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x928f2950c563bac89f9155f0063cc26721ca73d194c82e6a8bbdae50f288635f41fd0b882649cb62a996792301e36dd47de57e8a3b629a9757645e065710b36d	1	0	\\x000000010000000000800003cbeb7ddbb6bb4ea00d44f35bfe79b0ed05063b940a26d074e362db94301e1c07effa8b4a804b3ba6fd10e688d79fb89a836b51160bec8cd2bc9cae475d896b6d638d2a0420c6424c02a8223774c219641e8ad29f4b27ae25908896de039f1604824fb92967448a90d4b06c2453593fc78c688ee749b12616d55b5f5e647c6699010001	\\x6f3fb8e95aa9b58e10f1cac9ab4840af0f94aec79557ec035c9a71fcaefdeb031d74d7d2278137c81d30555c04980859ba9ffe22983f02adc57b5734ba74d107	1678613590000000	1679218390000000	1742290390000000	1836898390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
378	\\x93cb97580fee9cb55e6cbad2bc4c12454e40512dc7bee6076d34a36b9a6c4e29788cd0d70ea90258e18e7d712e0e2e6d8e058ccb7150775310043e9df74107c4	1	0	\\x000000010000000000800003bc180ffcb64fb6704dde09830877af558f549292405f8ae141205b8bf13b752cf4a59fd8dbd141fde06f5e3eb57439d90fae55afd8ffec295dd807068af670bcbc14000749db29922ba2695a26f9a5351e69cbd805a6415ab32a01ecfc5251397907c2ba35859469b88c87ab16e5e58737c42f757e5b40f8de7e4591de8ae7b5010001	\\x70bf71b6f6d96f8f8e190018adf0dc3acd8a5ee2a483d9f205ab1c567c5a9c23e81d6464d1f829d01282b57adaec04be20d6b6fcaad89c8b59d69395ab81fa00	1661687590000000	1662292390000000	1725364390000000	1819972390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x961b1bae2fbffa8c0dc4d041eaa2645cb051b2b532b32c5b50dbae41bb1336baa424d9e59c0edd146b867f53a293dff422d64741fbad00e9372ce65cc00f78fc	1	0	\\x000000010000000000800003c105b70b6d0e348740978b43e349b90d670ba6a3fdc28b43c5e521e48475dc497fce2b73dd6e4f87408c81a3cf521daf6bd144ef58c858370dbfd7139954d6e96fba66a75ceded76b227612df0d297a4b64192a9cd7635de665e77427c04e6f29f864cb135e49fcaeeb8074ae58576c4c6c001257e49141aca178c70c8d4630d010001	\\xd2db3ccd37dac4c2167c9cbdc4c1a3a2e01ddde09a8c58daebb4cd95a828f8754cac25802b00399f70d39f5a52b101156f5ccdcd46d4dab595d51f6d4483dd0b	1679822590000000	1680427390000000	1743499390000000	1838107390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
380	\\x98eb6a4b1a5487ccf2d83fe1989caa127db64159411caea90cc5e4bbe76ca17050877c24d972d27452752bfd3720ff8cb476474840f48d555b4b0f95728867a2	1	0	\\x000000010000000000800003d06c5a6bbc9a0ac0f20b5771d67fd761c17acbd1335694b919b57b37bb24dc961c22ee869fee0b4712065633147142cc3992311646b506fc27cdcb2554ff8ab28ca06c213cc05e2298f0e84f6d4fbfdcfdf44108d83d0fa54f5df7d7c0b50bbdb16d7b1b371a9e0a4e9d75c02e1e1bcc44c24da267d3934152eb1a58714a98f7010001	\\x7bcdf65d0dee6076b27cecf607385e65fa8f00a1a79b6dfe3cd3eeda9e52efe58760734709b86d8dfe58c4ee37ccf17150846bd938a401f93ed095134b35a409	1661083090000000	1661687890000000	1724759890000000	1819367890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x9f7fd2fa852369dc52e9846971602b9262159de4fa485cbabfc8e62c3e30e5571841da0a47d00491b1d621428821070050a39e18797b4ae7f54aba3fed54c406	1	0	\\x000000010000000000800003bbcf1e3278a9506264ad4ff1e735a5dc0a99db59ebabba09c417fd0ad98aa4d434e4b48e9afdeb8fbffbc1a8ff7fa52b2f6ea7a39d723a4fea46ce241054d4acefb1882bda39739a7bbc083199eaafdeb5281e6b432028f0036486b9a1fb1c0711934a331f864cbfde314c8b023aeccfee22753921217aa743b02afeb31311bd010001	\\xd56fbbfcf5e8d2e2bc7be04d117070184c4bc459897e2069fc9fdbde94195efd2e0c90a702e1e907a74305d9cb9ed4e721e5bb0b8a1df6a520ce0c9049bfd80e	1676800090000000	1677404890000000	1740476890000000	1835084890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xa0938749a9212747ec4a73d4ce6460fbec0f396fea237b7d9168f262727d2325cdaeb83e89014c507a4f25ad09c57dd5aeb9f6c98e12da9acf5891d7fdd3336b	1	0	\\x000000010000000000800003b33ad9e651b8f25d58401c70ada5a7d5ca0802dfaa2d7b575536973f933dd6f298a964a42b31e48e6b4a635f4386831f61d4b9b692f03e2568895be8880c66f6f5a81a8d39b26a7e9f95248075ff32c1fc2955736ccf0edce5342a733e6ff232a907e538455cba1bef81dae3f6b6cd11ead306ebd35f9558da63509343feafb3010001	\\x2ac0624f0cfcc9658f9b5b6479214135669e815711339d159a86086f1267f17201e2c904594e5c63cda33356cf59b5361a408d1908185edfba17e277b53d2b0e	1690703590000000	1691308390000000	1754380390000000	1848988390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
383	\\xa46362e39eaaae722964d262a93395563b51b857d04f8f90856863cbea0b469939371d274b0c807c6f1c6d899567beaadca0d4a77996ab7d542ef9bfa52c7659	1	0	\\x0000000100000000008000039bb48ca734fe0fd61daff0e9a32d7c83819bb0245e551122aab5f5e42cfad480a16b506dc06f8a5a369e568b07fde3f0737458f06239fa62258837e4f259e9e0a8dcd48e82ee6f26b9c58ad3f8fa281fb96b68c7eb5e922e2e5182160d94c542e4b106fb40b7985ca51f90a7f854cf45ce088c6d12252bd70ebb84de4fa4d335010001	\\xc6a71fda219da76fcc862d69fad31cf0f835d2178f4ceecadf7311aa57fa34ccb19b5834182cf33826c63e2c9dfbfc63916eb83f8e2be04abdbc79d2c0be7c00	1685263090000000	1685867890000000	1748939890000000	1843547890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\xa5c30268a82d565065bb2673137f186c49da1498590fc8ba6888ec4fc730d024080edc8caa6dfe56b6adff841990fdf3c9cb6e135cd5725c3e6c71f93d565ae4	1	0	\\x000000010000000000800003af5f029d3b9b3fa3daf1fa09512fcb4a63f609d754d9a2257995bffa4ac3a7d6ff9dcb973c44058758e3410ad8a449c70fe2453486a71a01a48450107803d6b99192ad5ff9e211fdd1a5b10b16eef71a715bb26906b13349f6f6908023d806343d22c1e8756c523c0f781b5b316ccbffca6a084aa0720ad9205cfada38297c95010001	\\xb1afc52ce907a54082c7a0c943d1c792913d35c7a906b142bd4fd35e84b208ce7d5f0faba379b710341d3ac404654500f43610ce58434397e187a0f890871305	1682240590000000	1682845390000000	1745917390000000	1840525390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\xa6a3dd9db3723199867894067c0f6a29c4f1bd702e474d06e2266d5c41bbd4039a752591823e8f22bfe09c2eda632cbaaad61bdb45902c1889e1f84f252ffb5c	1	0	\\x000000010000000000800003c9da1dfd77253ecf1209ca8ee4bf57527be9400702e1e5ad58cb360e7a88eca6b0cba60992084255c34afb149093b62ae6c25003dafab18f240606636f4af48a56de8e39c60f92ccc4d703cf3ad5755ba3f0f0537ab3d012e1db57f2890928413a1a132e1abf7895b280a08c54e6ace6e42e5cbbd46a77e34f80c33f3dd8672d010001	\\xbab1788981da06592b7703316f35f1998261c6465250b8c25ff9482bbe0f594c8a67c9ab5e1131aca1f2b52e570f2f48ddb79e7a481cd1e13e56e5be75a03209	1671359590000000	1671964390000000	1735036390000000	1829644390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xa83fb52aa556b81db34b5d552cf9112fb106a9c11bc22f90548acaa6c6a80f80b4150dc4fb34f014089fd0b70dfc8efec837c25159daf5956287a998357cd178	1	0	\\x000000010000000000800003c8a155064c5c2de173818139dcabc5bb11de59bf12d4dfc0f88a085ad9534aac0a588f4ff419de1b423daaa3798962476276cb31e86fc2c9565d020bf7f56fde9611de24a98dd7258423c046023957b329fed508cf521f5f525324283fc7218599669666b5a8e7683631206f1cdb434767a987ef0bb81abb5b2704cd0fe3756f010001	\\x017deb53aa5a02b1cddd517a5e9228de8587c8d16f119292035ac42165f3d13b89117fe94d86625f330e9a1fda1a7a4cdc5bde277ca4ca28b06e1127def4bb0b	1675591090000000	1676195890000000	1739267890000000	1833875890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xa9cfe2ddde3614b37b8981e3d9be920e594aa3d5e6d0d5800945bdd53e4d385bafc7f43fd199734ec99d4edd844711f639d41a366b20b76d73756247362559ca	1	0	\\x000000010000000000800003e1c4860d6aac27204174519343b963ed7aaeddc50e320df0cb2ec2cebf41d8bc2cfd0a1487b5ae53349461dfa626682e008ded857fdbcc35dc0519c6fe961a6fcbec39a888a3852b852f5e4c1555173d7a92dc837ed146f824d5b07bc2e21d605f3f4570b02e441abb9229382694697465ac5a3e72fa0b96a2a0958a10f05ecb010001	\\x2ecc53141db37991c1b79fd7bd7fd8802251eedd6a0ee4f774e2f3a734760768381e4767566b939c8891824e9fdd5aca2e677849614cb81c727d39db46d05000	1683449590000000	1684054390000000	1747126390000000	1841734390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
388	\\xab9f1928204623d2d8cc78b95044756e9a8bfcbee61843db1ea1f158a00a12d0a4aa357ded4c9d809eba39f7afc4ae5d7294051b45adf3c67e400f728e14546f	1	0	\\x000000010000000000800003c134ac5d221e87f04b39a9670e721dde59ba577af65c76db22b3c470227661bedccf9f6d1090a946a6aa16a28d3f02846b899d547f0aa69eb952d4b51d5387c1cab74076101a93d50e154097237f6122ad32bc1285098c81fed5b1fd33010bfc15f3b805ccfd880fb84d8eeff541d824f23ab43a5dbad0238f6f21b6eeb00dcd010001	\\xd4de9f4be7bc765b5be63270082d8956bf986db60570e0a54d08237cc66b66251e64926ce40cdb8c0771ec3642e32953e90e6580962e2acf964d59cdafbf4000	1681636090000000	1682240890000000	1745312890000000	1839920890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xb0b37d746ed9b3d3dab9f639cb04e026846234ff51eae0e42cde743c031648e0f5c98d67c802217d3b54d2678485250aea33740573c7b63a97375a93d759a2d4	1	0	\\x000000010000000000800003d1803733b53a963c9850f55c466800aa2a71392e617bef520356f149bc2ce111bd3802433ca08ca4bc77292198cb9671fabf1544d0729d4c48b9ccb6d00dc81b8e75324a6f3922268adce1c307ad6bedfd36f6db22966c22ee3b35229ced0c70fae419c0cefadbbd59bdbf1e21c679539672c2e11e2cec11a7a9b6ee12aeb219010001	\\x00f82ebfd1e67b0ace48282ff6318e96450296327a7ab3fe407645670ec7c131e0f76eb72be356743a1dae37b2dcea14bb2b35d17e7f56938f37e903dd4bb901	1689494590000000	1690099390000000	1753171390000000	1847779390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xb1b3bda9412812a4fd82683ec1f8da2d9010869f69c8190e318b078ef6ba9dd5372eb0464cd12315272db5ca247aed708bd5fb08e13ee555311de5874377034a	1	0	\\x000000010000000000800003ca8022bad3a79e14cb09d184422779d25cb0dacfae9437830f763ee34c7b31c3c9f818686f36e81f8dd7263794af0c0b7cb3010350206e0ed5216ea607941dafd8b7379cc52421922ee8052d0f2c5a0ec54ee403d8439b9ef16d3a830cab7b8e6b7d7aedeb93cca43710d109f15ff045cebb792b2d6365d5491d89555a38d601010001	\\xb879ed58afbf78cae1b416141080180cd3c48619813e83333d04a4b2f590baf8a49b5f82c87bf9ed0e477ae8e52fec3e346cdb7d2973d487dddc9c5dcdfe0b07	1662292090000000	1662896890000000	1725968890000000	1820576890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xb58f4a2763be7b89ba33c52ad7340c2a7620f061b37919a491f85cc67421ea4a0a9be088a1c0bc111694940047fadbd14e38d2925d478ca4780db1d6b997947e	1	0	\\x000000010000000000800003be3eac5c88294c0dc6dc721aa7eeea7f0fd8d5f9cb52f80390e84f76b56546db0c2879b97e3bf256dc2e8ea060b44cb54f81c2ef3c154c58741958d9eedf259809aa0019c131a5f95eb8c3c2840fed6e20d7abe7baa22f6aa2dd874eb93d16acccae6bee5be4207bd2c0af5ec5a56f0103e69d4c018e3dfbf5cc7ed0200fd82f010001	\\x6f048e3702d42bcf49d6fed2f96a3ba832c3f6be33913226783ac0806884910d4db9b897a004f66f3361c907d5a2084823589ccfcc4a1d6515c917544a27cd0a	1667732590000000	1668337390000000	1731409390000000	1826017390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xb5f312522a1bd17bf15a4530ac3f1f5d353d5b3ff468c223d5a50b17b57b52e1bd811e2c189985a2edbd56da6b987fbd5975c0f81aa15f0802c264fb8321bf7c	1	0	\\x000000010000000000800003b70fc4612d6f88f061262df1d18557812591390fa3202657b9be45e651c2feffac8ece00dea639f6bc32361c6f58f03037223207ef8bf7728d4d3cee9ef2123bd406bbea633b35b53a3864816cc88c92405d699fac6043aae9b6fdd9d06e445850507079ee615efc922fc13ed9f1c64313f79aa799e7f7df4b0db4760020b213010001	\\x293bfaf1fc16b2e8fa3e5d406f122edccb6e476c36de9c75e5356c48f4afbda81cb050f95fc7fe853ebab02ca1f1c033e21b4d0818a83c59dd5a23c165171205	1667732590000000	1668337390000000	1731409390000000	1826017390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
393	\\xb57f366d9723c1f175c4e740ddd1824b5300364cc956bd55967ef1923fc16f1f43988ff46f1c731aa4691bacd56c82c264c784bc0972eb9b500a22e4bbbff790	1	0	\\x000000010000000000800003a797886e8590c82edae9d73a21353ac279f50459f6c33dc25a317897d2bbc2e9f7142df416d084aa81982c28335e5c0fa407170786fdaaede6ac8d139681316c446a5a1ff0cad71fe692572e20aad1bc03b3cf633e644da4ebbf159e5e69c6071b6f363467d7ff9d2e65d96a91cdf773eb5d43b7a066f61eeb0b126cc0a1ed23010001	\\x594f72a5e5e129fd4c8c4277544c279bf3ba01d46d454a7dedb0066bc2bd3ed88b1434198be3a6f8c281fb38335cc2e68dc3dea01ad38437234bdfb18e14dc01	1671359590000000	1671964390000000	1735036390000000	1829644390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
394	\\xbcb3d873255628042d9099857121d42694a52e8d9e00624fea20d414f0662f051af19504ca041b792fb3c82d15400f1c4afcb7b15b8d89d84dfb035ac14e8356	1	0	\\x000000010000000000800003c3c212f773671a3d2d0890cf05b8007ed8d948e97323610922ce36949d62cc2e1a7e251b6154d42da3e4c9174c3f0cd0fbdfcaf002a3a7d8d5c8507e8f0936b2d5121799c43eefa0e54a6ca590951d0ba958185404240b81647f8c7b7decb4a75db86e3abb923be5e0197a0e8927dc3220a5a2aea0179949b917eda071c5c0ff010001	\\xe82c3f008b162a7132cb6bd28d9273fa5add11761d263ba936ef5bb00cf5187314ddb3e5a4cc5880bdbf18606e79e01d9218baf0abbaebf1afc767b2ffeddc02	1671964090000000	1672568890000000	1735640890000000	1830248890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xbe83a62c4b87f7af300e3fc97a14cf28188542ce2861178a2b1095ec385d8fafd0ffbb2a80e84cbe51d909c80399af7d170d7dba274bfaf42564b3367e83655d	1	0	\\x0000000100000000008000039960b4b93bec021e7e8d3ae7285bc90ce80801594b9d147d64b2facd981d0bf92d1d1be472401cc4defd138f96af0130fd8ba9edde51c7d24fc2c6fd9cf0e4b6e053fbb42278a39ab2ed69d887432487514eaa922ed3ca5d198abcae260d502008a310f378a33ed6aef00c5e9c5d87c82cdc59482bbe32554846de40f0b1de8f010001	\\xf1648d76b185c7d62d129e700957a5368a473e9d5aa08ee798f965154fe84f710ccb2e29ca1acc7902e0fd2d6e171b674bd4d501020109e971cc335f48b3370d	1678613590000000	1679218390000000	1742290390000000	1836898390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xbf4ff42d149354867a7bbafd450d7ab77e8d66ebed04d23c9e9d959cbb92f152295dd7bba79f11a9e13ea531a913d0a244d4f5685df1e6e1f4caffa34fb7e639	1	0	\\x000000010000000000800003d3e3c7d6169264cad107926c6ddd4a28c8609c8564a7bb0c5e39c85e12cc1fd17b4c2cbbaea73891c9644089dba7e814a254b029072405ea1e70035e388223503e58894507b8a156183b79de885dd95e7db818b7bbc5445f806a759cc124ebe7e1380447e1ca4a65277f9a4edd5b78bba6a3187f8bbdb723e0e4bff0ec23276b010001	\\x193d133e9a91b291d0f005952ef10d942f0333ec9c2ce2255a08e5cd8823b1cbd3a986827b137542e34ab6f41867dcf910ddb4a8cfc34dc791642b3449c31606	1664105590000000	1664710390000000	1727782390000000	1822390390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xbfb3cc8386f3c1abc419ba7ebfec805c698447f362f3f230b6f5c8b38d9771bd32de332301e57859c32b29ab333a9895ce12fe6a2dd30298ae71cae518e311dd	1	0	\\x000000010000000000800003fbf7d6bcb1830c0e2904864a99450e47437498fc0f3b2f881e7deb6da826e631ae20860c53d59391ebd0c8b4ca08b755c33eacc858b215c525106d6cfe8889f006ffe858c90de26722e83a1c2faaee57350d9e3bd0859e132aebffb8afe7af2b6fffdd872f1bede6822f839984f58732a0a8cec1c6ed1fa87351b9d3e0261391010001	\\x097debdca0a1cef0927c94c2f77a4de7b5649a50231d1c6216af845c9ee0b7b367d801a105da9357b3b4273b41ee0716eae1b1c5ba1139ed5e7b027a023a8906	1680427090000000	1681031890000000	1744103890000000	1838711890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
398	\\xc097bc3e24e8260585883778256b14db8cfecb5ed40960028093a1b136472ea726332b5efac458442f405b76ea09837f37fc3541525d0b4b05282e9be413d13e	1	0	\\x000000010000000000800003af5a57fff627eafba5f25594c9a6f5cf1cb3d5a1f75a43219e8e90fd7a673ac66aaabfaf13a828ec08e2c3e2335a3d8cdbe81c9327e991cb70b13f7e2a118d2e04760f0b68ea0816a45db09235eb8488a532912cdd2d3794c9e0ca05d0c578fc95e33d5552abad980be8001a38959c5ebf703b69a4c9c5ed8f165744ea78e211010001	\\x6bb4fd714e1a769e8efc8d9310a7291f92af31ac810f20f1db6aa1d44a5f6013683bd219062bc063f99e3c98aabb122f885fad2c9f2be396e821a486c51dcb0e	1685867590000000	1686472390000000	1749544390000000	1844152390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
399	\\xc0cb808eaa0a420161ede320874ea900d804f3a795060c4b2db201feeef5ff7479af5281484773c0d38d299f10bcfd7f98366f99d7638d0e3e4b21e1296e524a	1	0	\\x000000010000000000800003ddb6051871ddbe9b9876b32c69305081bd10e93578291e2f045ea902b31b770d380bef6e8397f38925574d66104888c562077904e27cb10bfcdfd5346645bca3df2d4806b8da035f97f34f72547e9e6d1804c7738048f5a02f9416a5dd8f768e3625cb8f06a50d1e84b2aacc7d718eaa7bef981889d24c104156481074f68713010001	\\xc05d3b954aee0f6677c4a143972f8e5575a878134fac4c976701d3a6b9688087593dab29298f958f8ef191b394f31f0f97e89d35fadf299caf7a35947da9dc01	1675591090000000	1676195890000000	1739267890000000	1833875890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xc25b31df13fc37217fec2354093dc90da45ca660ce2fa8cb4423cd28e328849146095521f22ac58c0933b74d8bb0b542fee42cebf7b98186750835c8be8560a1	1	0	\\x000000010000000000800003dd25e0d67a10e904f2efffb076969d0f574eb81cf1799386aa207051ecbce1899081e6e5d9119a28139f04944ea75631ed9b2c73b140efd2639f58c447e0a196d5a1a4d74c1e53811ae674d6def02acf2dcf36ff24af0d04230db39bfd2c97afd75a2017f5172b58b4896d36ed7e7dfd84ecada179006f2c099b1b943edc364f010001	\\x33ba57d64efc0fafc62bde647a84437179a013fba674ce2f055516f018138754e56e7acf2f99de556587238eb4554d9e4eccb9bf2d8ad207d9ddc7c97629fa07	1673777590000000	1674382390000000	1737454390000000	1832062390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xc35322a957c31bb3431f0c69088d386d0e7ed1c00fe21e53c1d81ebb19764106691e7d97976b56bbe115408d90b277d82573fe02504863e2844e5cdb6b4cc108	1	0	\\x000000010000000000800003f5de25901b875a6aa867bc69085bc2a1b3758e8874e4306fa82afe22b6570b0c02ac9bcc96c0c89dfe0e627d9c862029e56610652bfe9879723d0904b4ebc9c5fbb1cd2f87c5e99cb92e2b1f3281ed85dfd27e1cf346212dfed57f2c5f37bfe350bad68938ab49e655ca1706510705841bd86c34d4db2e346c89509178fca5cd010001	\\x6c620e8ae0eff894b59bbddcdf8668161d25385708f05229a708688fed1b6d2b11b4d91d41a688a119675444724246af8c7b128c5538c7a4dcf7f48cb18f5304	1661687590000000	1662292390000000	1725364390000000	1819972390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xc4bb6f84ecf4a64b731a41ee1cd9dfb3b72cd7f32866249c226a7adf0e110c0e98714cac9105f1e24b9a911e231e1424f518c13133b362cf4745fdfb637b317e	1	0	\\x000000010000000000800003c8da4bf307dc555203e3bf7e2774398f824311fc201cec3c217241b5d774d3b8f8c8a665cedb1b54992288328d1607a0becff0b1f47c9980a7275ddaff10ccb85819af33806ed33a2b13645ff2feca3416a495968349e4e2690d079c08bcae80bcda7112ece33e5cba7238d9ea6f2b5111eac73fe939b9d9a77fd54a136c6b7d010001	\\x5416a2f1111e3275a425b465fd4e138f930da353eff41c187489dc8e6adfa577f0188011204e90286b03ade2b358738cff57c5edb213dd3dbb2a8ff3d8d8b60e	1678613590000000	1679218390000000	1742290390000000	1836898390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
403	\\xc6a76db79fd52893ebae9cb2f4a62890d2db06768a2f8236bd11f29d2947687ccfd610444f2f18dbf351f6e5f167d93bbf14e5ce25be160f2614eeff1bb3a566	1	0	\\x000000010000000000800003a750c0c0422a33df15256e8e9abe5f11342c98e1ff5a8a428326de090ba044fd183b3c7e4b6ec568e69a0747d0ff81bb6d23c5633717057475c4fd2d176b62fea48b8972ad563affc96c527be92546144e122fa2403286881e9d28b30a8c78b3a77ea6df519b8321e69d5daea23af21c651a400cc03a7741378ded86db7b729d010001	\\xdb45ff6a31430e148355408e36d689c9d3bc9d58e81166aa845747321ad5f238f94c34e2acba400d0b52ff2774fa39a551007b329d50c5384df53aa17d61800f	1669546090000000	1670150890000000	1733222890000000	1827830890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xceef0b834fb5168556305048444697df774776be1945c75b46b3f857ee2e0d4acef8c3174e0aa8752c65adb1a5ffec1c48b90f8205c7dbf460be312e03ca3d03	1	0	\\x000000010000000000800003c59939af360f8d4479fbe7bf9ce1efd5c7c1767fcad58817d537827e1104e597b0bf94214b9e337d6f93ae57c08c9b1086a639ba4130d1840959f6248f3c16f418029bc1452d66028e669c59750a89c1588c268391e1540651927100a06f4fe1da85611da69c4956e868b103688f6f68455a07e92b812b668d3c2508ae8ea01f010001	\\x1a8ddc051f3ade0d2797cf5c2dca68666378480de7f8eab35e890a02b5220169b9d9b8d851010d1c529b89a81d6def108646b6524f602feee9e9c57805419d08	1683449590000000	1684054390000000	1747126390000000	1841734390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
405	\\xd187a041c80a8bf5e31f8ce3d6e7ba68d6e20baf815a11645540d7d813c5d65cabb6088e16ace565cf52877c0931974f6fdd0d045386518c874e45fc54db7b63	1	0	\\x000000010000000000800003dbef62ed7892ea49ecf91ae23b928756e66151c43c480f4985f3624ee64e7c3d28e024669d154ad032a6d0b07b0377050fb5f1baf9d8fe9e2359cef1e4ab0b23cc9faa0a8ab81e684146f71ac6b2de5eba894a0aee1d65b0eab551e6c21ab44780c6315463af69d47c56e37cfbacf853f3ba63200182eb92fd74b4aec23b0bb1010001	\\x04c33971ec62f098eaa5bd3c9fb13adc5c2afde00493a74e7ae4e135d90ac5caf9739ee73f92d6c3e89f56b8931e7de4b87ab9b29ee14bdc47f1ea68946a720e	1667732590000000	1668337390000000	1731409390000000	1826017390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xd667533c38d50b6205b4d042c3ae7e35f84a5a70fe24be1194d0c44b618f9a420602b01bddef89f31a7e38a860725cc97bc069d5455e357cdbe7b29659eb69ab	1	0	\\x000000010000000000800003a06736f6350ddd989c52c236da7fd0500dc72cbb431c7f47c0c5a2c4e070dd095ddd1b006bbe76f4e74f4dee76754423ed958f50750770b09ea44308e087c8238aee89e423ccfa149ce879a4c4cadaed7d3aa3ec847e42a951d4378d117d6094a4acda734e2162c1bdd5c1b0d73336065b9a4459c889bd75cff1a4f6caed9f35010001	\\x2c98dfe82d21845d170fa62d4016a22f15ce213ee386729880fa0202087c9bce24b09c0b198a9508e4a4014ed0d36d46cd328c3867e2ffbd0aad911a5d94250c	1661687590000000	1662292390000000	1725364390000000	1819972390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xda9f77eacc36eda43853f3d4f3fb2bf248a1e349ea3ae5bf61b9e6cfaf8fad4ab6decf35cf6df8c3a681c6e2293a45cc0a51475a7246bb75c032a8a99da3e88e	1	0	\\x000000010000000000800003e8c3b47ee34ff3e4bf0705208aa2f66dd281453a097cf0ec0211c561c2b483a619bd942a08279df61a2c602d7c60d5a805b246a59a911783cd4e74ed25eb2f96d1e4403fbe4bf4acabfea5d84523286df47d7bcc91ba8ff70420bf1559febfc98ada3f037c3bf6453f6d621e02e09fdacb91c63ec6023143377141912242b119010001	\\x14c1d3c9b0f4c8b7d83d2a1cee8290091838e33246bab6c4f677fef69475e184a08ac5e072c3659005b5e11d72ea7c00cb29d75b66ef76acb53cb8cd468cef0e	1662896590000000	1663501390000000	1726573390000000	1821181390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xda2756386d4b597f897181541ee4595792ce8d64ce74a366f89f371757b9bf93fdbdb4b994ed81bba3fec125b7994e0a8c9439c4f8420b63618386b539966f24	1	0	\\x000000010000000000800003a718e9c7c2d516548932881cd53af808cc9b6b41fb07fd3da98dc3c7ca444456e86cc5f4f80eb891ebf4b95528438fdbfb3ffeab00352be3fa97d61faea2facb2b781bd25a2dd7d38283281afe5ac18122251f1c175e673f5ef05a6831aec04c98f3dd22fb72347fdd184352d813a82e77128e05bcbd09512c4d69baeaaa629d010001	\\xbd53c05e6794609ff9f80d408d8f52096bb96b2d9cc4c0de2011278a510f5122c43ff8a888bfadbb2b855807e43ef11f411addc275f71fdf247460f5967a240a	1677404590000000	1678009390000000	1741081390000000	1835689390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xdb43bc87649e1030e0dbfcd1315feccc72a92b23fb7f4e16ecac2277447783e7b694fddbc25215d0958a30c1421b900ac5c63b4c0dfd448d2a8446ccda7006df	1	0	\\x000000010000000000800003c98bbf94a1d40f6171c6a10732b62f4c5cfb17e25cfdd465807da006ea71d7d96d93b52e5268c9163158aec85594d7f79a44aad21ebbf1db0bb985a8d93c5d958bb0c45bb48b8fc818716b2276d67c98fdb3893e68fa5efa4eaaa600c00f13e6e3a342bb0f07ecf857d1279b62d139af88596488fc5c4c9dcc99d07b30b5ddaf010001	\\x8f539091c88e080a6d8bc68612d21b91c22ddd7ff1acf40ab771fb9bd7fc4108bf6b969effaa0fd3d27cb5fe18e3cb1d82ed99e5dcf0bf9e30528a19a595df0a	1663501090000000	1664105890000000	1727177890000000	1821785890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
410	\\xdb534c0060626753c71577f4eb4f624245f148bec98f8bfe2bf5ba136144dc12e87d423d8ce455a90c98125dda8d51988381664759bdfca30e78e68873ab4819	1	0	\\x0000000100000000008000039d2b16dd07c8a714153559e52c2c87f2cb418d43b094f41d907fcc102eef91d9d4c3bd9a05291a3cbb68512752182941235a488abe7487d2a7be1500e2399e6fcd6af58f2549b848c1f52ceb2876de266b4e17b2674078e809c56c040214b5d22eef8d310dd35219466363507f7faff273b7645f3c7345a04dca4a4ff3acdcb9010001	\\x9ce19266fe8bfc90179dea07062ba31674b0b6b75d2165f71c63c29cf668fcfbab38f7dffa2ad77d254f7cfc739b76b676b9a9ef1e28730d7b0731b95fd7530b	1681031590000000	1681636390000000	1744708390000000	1839316390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xdddf1f1d701b10c0d890512a562d6a545b8a0348329755e1f2574ff9083498cf32326d4fb762926af2d8995f093b338f5150788a56807f441bf9b798df299f77	1	0	\\x000000010000000000800003f4f687dd52674448f7647649449e6214a248ec5d4aeae4da895cb00c13ac290a4c57652ec9ee8cfc55717f29d7e1bcd2ed51bc5bec0df870b35f3041d62289ee1bcb3d5b5d6e31d7f36ce2485609494822cfc4db25b8cab2e6290d7c980f55c41a2c3c4ca9c31ccfe0dcfcbec9135491ba8354f08d71d922c1f90b93045de885010001	\\x5ddacfa3b6d9fdb1ec521e83d7c837409c7af395c5d21e1c4b339cd3309f3eaf6d3aa5da4d2d1b5d71f94a8921e275c71e88a727428dc5d86a39c2227ef9330e	1660478590000000	1661083390000000	1724155390000000	1818763390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe137aa6648b701d0a7553b6b2bb856c66cefdd754ebe9f5170413580172cf4b791e7a439265d285127d4fb2c449a0482701e928d1c3f6ad9ad6efc2f73cc942f	1	0	\\x000000010000000000800003a64f770dd1085b50346f36c611f44b6c07f86326d16b3920988a6bf823eff3085dcbef106efeacf02d8b11d48a88a7d76feb8c4d376a4a57a1f0fe346f3044e2125ea36d1e6ac75e45ed3ce58a13eb278891bf429ff54ee58b550bb7e6c6db0b0120378ded591e3a356b17ba256664c2ad28b7c16018e8772af89b81ed8a8b1d010001	\\xbd9addb7608b7fb2c4b461f33d4ed0a83f509bfef27c049a3eec32fee1a89a6be13599ef125b79eeb415f7e13b3277c0c5723908ef5b5f9575aebd4e73f2910b	1671964090000000	1672568890000000	1735640890000000	1830248890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xe4c3b18416591c6e6e7d562a860f263b51d9fc29c69aaaa883e0eb167a2d8dd3b42305c7870c4e05e9f663dd6242698ca239060b645867674ac930850961a3aa	1	0	\\x000000010000000000800003a5b0a80e80a4a0d3530072dc98fb317ccb0e07860e6553eac895afbf6b1ea0b773ca53e9042cabcd9c82dcd0869fe637f4b5730337f6e2f66fe15be463068a14b572e27fad2e38a233457342bf1f74352e6804fde22650e5d7cd5af29f9b29652bfdf35b843a69fcb652e3d6fd14dac4ba7d86f7e081f833f3189e37db7bfc9f010001	\\x64cc6f5e3c5e1ddfe3eefd8adb93b08a5ba4ec01e1daa53c1607f8839fdaa4eb7f98fd2e855aa3715d5b5325f00f7ab4ec64529457f37e6754d9b83df46e4d0a	1664105590000000	1664710390000000	1727782390000000	1822390390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
414	\\xe81f626f27a6da9d01c76f541fea45705e0ea3dc755e3230d8567acda2eb63487874db0001fdecff3046e476bc213a0b648f2d455dae42e806e85141ac828465	1	0	\\x000000010000000000800003c0e8b62527244db15da2bb2d1d89d15cc3a8c3430ef95c5887bbc0ff85d80fe1d71a62fb6a799156272f962b07e980e1a07d25b90b6aecbf2df44b2765604d3d935c4712d5dde1c3483056cb004571285059713b48a844ae41951a3d270f072d77d47faa417ee4580e3678bbfaedc18d547929940b82e70743a607c3f1ad1e25010001	\\xce1a987bb77394b49f6a791d1f7c60579a8dbe84f19d5add975cf31af1b70d4cd8e85e03ecc7938b479a9639f94d573e5808f216f611899359e53aed4501ad00	1665314590000000	1665919390000000	1728991390000000	1823599390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xeb8336114dc7d11ba488b80d7def53189794119430b64db606ff501d8e3e61090578da65f952bada8151fa50b0261d16618db469cf7079a31bdb7504da5376f6	1	0	\\x000000010000000000800003ca8e7fb34d78255c8ed5ab9e4c1b397876603bf77027635b47b5865b6521cb023e09de5be456777f57e9ae075515df5901c1f3d865cbea3f77f25a1bad401c2e1ea483f176a225e8760ac20b4996043123ce9dd405c010dbdd6fce45c36c44319cda2abae0581f6beb4c1b1887acb66b825caaff60352440f371c5177e4f8375010001	\\x8a3a376908ad07236d003a74dc0b014fd9a527af71e677b957c29dd0053b4f14f1625f69828aee56e8df6c98ae7edc5482d6150ebb0e2a8ecf2cc0b7fdcfbc08	1659874090000000	1660478890000000	1723550890000000	1818158890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xee372a1513dcb13e299808719d0fb59cd2bda782edf5af0979eff593e65128f31521f1b70683c2985b8b105d94adc05eb3426684f2349971058910040ff4fca7	1	0	\\x000000010000000000800003c0cde01276492e011506651b91494938b8d149d85f9bb410a04caa4e1e88c7208cc288eedf920db839463fb99637802b78b6be44b7d59b391a31d9dab9b18f0796f6c43f971b36c3db20885e2b8b3a0a7202181c7e76a6f4a9eeffcaca5375e1cc04c7a534b1a8790611cd28300f57ff8443ab0a1346e687b5b24be5291eaf0d010001	\\x6eccaf59be05eb0d98e8a07913e5cb298c3c43bae5ac01f5100b85bbaee63f244ad5f8305e290d8db7834cb831557220c28c48e7ab7d45aa42b047cabfa78900	1690099090000000	1690703890000000	1753775890000000	1848383890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xef9ba1d476b522587106b5c48df1a5d4a24df90769c35518af73781c83926999276de02339657527a73024f393e5d5f25f2ca2c7b581deda003a33326d7893b2	1	0	\\x000000010000000000800003c0baf3144ab153aae17fbc7790d8f0eae71f93240cad78375d962d228a38145ce3e320d997dbd5cbbd9e7eeed47ec4c994a6a7c7466a624874268f34130470c7637cd73be2586996dbc48250ed6992980d9de027bf7b6d95d3af7a2622e86de8067274b76f696eca26256842825260ca847b514d6b11a03da5e50ac3ac8044fb010001	\\x88426d6ada62a57a1ab9544fcd2e8dbe7a6bdc5c99daa8db5f0fe7e56fa9b77078bc0fa89e58353549fc9d1758eea87daaced5f78868cff93547bb33bd98d00c	1672568590000000	1673173390000000	1736245390000000	1830853390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf19b89e7de817d58b2178438c612fa50497946f93f953d10e6a21ca342fb56a4f089e7991956dbec9f3f0d3d4ee3972c230d3a5e223924095a0e1ce547b511f3	1	0	\\x000000010000000000800003a73d8e8ada08ae998fe0b0d679cecac9b784f3f82b71b3673a4c39f0cc5b0a06eaf32638561ed39f67ca9c4d3dc8b03470ae1642bff6aff8f1b34eab2126ccac520a2008de9e570a46b3a0efff000ead9bbdc25ad46f4c4c9fa74535b39a6266bd1de306679280576606694f44a139035c0611c6b187b2a1339070fdab0aecbf010001	\\x89532a0244c4b8c47506fd073a882089ebc85c19a6ff1b0fb2478bc6b469fe22a340fbe02bdf10dbdfd418e1073ed5cd57fb46085c988dd716a578f0efd2cc05	1662896590000000	1663501390000000	1726573390000000	1821181390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf133776b9f5242cce8bccbdaf1b4fa16657ad0825603b2e17b98355aa016ac0b149f7a4aa04d2c653fdf7009c1f3c91599b1f4ae499bc67a297be50f14da391c	1	0	\\x000000010000000000800003a77254c0baa0f050dfd232f8cd9d21c9ceb30d519f0033dbe271cd5dea87c7fc95db1a8e9a3c60ef70fcc99e865049c4e5c612a2806ac80ff643efe9cdc19466b6cb38b1d624657cb9b49b250c1ba00b50c72926818a87371670351854ea40562dc14e06b296fe873fb282ecd0bb6a3fc44e997f05b681845e5c0a2ed3193ef1010001	\\x48f877b68029128d90bf513513e0ae9815cadf3380376e6d9c44dbf86bc585f01bc254141f836f9857e41c7a2dbc6b6b715ed6f2e650c091211597b016abc40b	1668941590000000	1669546390000000	1732618390000000	1827226390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf3379b69a7b2300dca00e7a43a9ddbf5bf81b0eac30dbc70a9f8959a97fe5d577aa99250b251f490147bf3f38fb16fb5f77ba71b746f429ca33c62f3b83f6216	1	0	\\x000000010000000000800003ccf001652f7a267843fafc14e7e78d0847e5dbe1309220a008393ae1ccff906980f1d47f34c6d3874df92796770b4716904e819f9319e708b0a24c5e82f16956db4aac2988e861d498f661b820396b37939159530b26288ffe5e6d927dab893620cf83f965bd935f3710efe47ca626e382fb756f8e0b89d3697476dc4a43e1f7010001	\\xbc441c176bbe1e9ca5af6d041cce6d039fa09224804dcb436e2a469cfadd74ea622e329d733662854e4d18b67faa95d75ba8d1f0b51dbd100518554eca5a9506	1662896590000000	1663501390000000	1726573390000000	1821181390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf40bf36f88031936a668aebbbf6cd6d6564c3b930c2ac14f3dcaa7caf0ce3c14d1fe8a5cb42998f7e72d6b38d3f6793c441cd804fdca01acf1b4c8854fe43f24	1	0	\\x000000010000000000800003b402ec71df70ff652f7cd28c773be0c4233332d80fb03a025a995e57036822154e352f5317880ed09394ceaa9783e6d71940a2ed40647466d29cc6c209c1f423b7224912ef148b5fe36d5a6d49c13089f1c67d5166b4ea8f8d4a78ba5c9c30983290277439ed339698737f13f804e74c42c5da1a4907387e62f0a565e6646a8b010001	\\x918bfdf4454ea6b716cf0cdbae6dc5f7282bcf755786be22c6ae8ba29dea3ceea24ba6807c82d03dcfe33d08f4d8618dac3c35a5dd3c551ccfca05ad01dc2107	1675591090000000	1676195890000000	1739267890000000	1833875890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
422	\\xf8b77052eb091bf376f62a3259f2bc430f1d5f65a755dddeb444caa53a9160397971f6fa3011968e29d9a6c316aa51029988905c89da899ca8069728cd2554d3	1	0	\\x000000010000000000800003bf73060f23ef7f8c5cef1b8cca089e617733cf31edc2aa7d0ccfc6343fc08ba05f8593a8e8fc3a365fc05259f95ec87aad5ffff2f88200f6bfc1c7a3053f918c5c5f85f85e286c6ae9c52680d9ab7e0ab6c9151e612d1514bf62943d5a013e5fe1ee2725b36de32a47d88a7fa7d0d0b5cf2b316a4e98d8b8ea95c986fea591e5010001	\\x4bc227d1533ebf8aaa8890dedd88de16be43f95398ad4a3058210f0de0afaa6789dacfb118fd24a9947725ed6bb7ee44ace345aeea602d3ed9d45b319b29340c	1682240590000000	1682845390000000	1745917390000000	1840525390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xfd53c0b6a2d1b2c9c44ad1cdbd306095edfb302e0964047f8d8bf71ac9b4052ffc56cdfdced3834b2fd56c7c492e68282bac9e804a2c6b8ba0850866d1578067	1	0	\\x000000010000000000800003b595108170e5626ad444976228ec77f125e49393721668f19b04d68f560d2a280ba8631965b592c29ccd4d55d2d177e0f64d4aaf251c3cd3ce211a946eb2d6cf91fc1546d46470ce3f58fb7f4a9becab77185d2c1ea39c900cbecde024ece3dd89c7ed4ef61c47d868c0d0390e599f66729d2e98281388492dad54e20148ee91010001	\\xa2f4efaf1271d023f51b8f6de38041b97321d0c824bf7fe1028c7db592ef837ea0721431de3d0d6b5c1b5675f4f3be27958ef1c5c60cc55e230f3dcd36ffaf04	1668941590000000	1669546390000000	1732618390000000	1827226390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
424	\\xfeafaa8914a20a6f63fa1ec71a83b02017e3d210af27c270a440e57b4cc0831c882b4608ff2989cfafd5fd9c36d103d2d49fcfd3e7404e0dc2d15a3d7183f9c6	1	0	\\x000000010000000000800003dd329c1673d31ab25e4b89fb2a985dace3ccee3df94d2197bbfe2b8171a76627ede570b04b6406a14393097b29ee406d200db931d550b0e2c9bd81fd3905511098b93025c7897544c46ab047c6d013c6e57c09976ed5437afc7d09e628262fb9264f47221930882d9e5bdc3c7c3a39b9cdd0f019726e1e7289fe937c7734ee7b010001	\\x8f6a00aabc48831440c4e7a0dc203e15891e30541bf1fe30143f52b29b79a43e0eba7b288235aa45ba41d8565c6357cb230359be19b2968ddc9f9938a6e3dd04	1684054090000000	1684658890000000	1747730890000000	1842338890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1659875005000000	846062970	\\xf366195f0b7757993a4e601794eae1f2ce60bd825dc0eabef38717c5ac63b1bd	1
1659875014000000	846062970	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	2
1659875020000000	846062970	\\x37bb931d1a9f07d32ca8a0fcd212e3ece5c21a3be9d3ed2614d09ee9c05d4737	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	846062970	\\xf366195f0b7757993a4e601794eae1f2ce60bd825dc0eabef38717c5ac63b1bd	1	4	0	1659874105000000	1659874107000000	1659875005000000	1659875005000000	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\xafd8593e0e08e7e53e7546f30db6b09d8e6165e4c46162d195e2441b094c5e22cab5ed010d60902c044ee9664e50755f554f215697b42621caef77310dc3231f	\\x0c1ed1f738cc64dffd9eee095920fe08d0b68fec1a6763929503d0a246093ebdf5f747cf14722927714f65275b5fb2de881f34ea0574eeacc234339890ae7c09	\\xad12bc88a1657e53c9a48a10fceaac10	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	846062970	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	3	7	0	1659874114000000	1659874116000000	1659875014000000	1659875014000000	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\x19247447150cb7ba71190aacda51e73524b7f6a8f52df0d50397c1cbac0838c9c910498c557ef5a37a6217aaa4461bcd2fca1b1508162b393d147585046af572	\\x69b5b50d9dcb631776536e9bed0ce8094b6e706155b307b38f05d9f7ffc14b6da0873f6f8dc894f51231e53e1f05c516c9f6fef8805e5c79e2d18b076d81ff04	\\xad12bc88a1657e53c9a48a10fceaac10	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	846062970	\\x37bb931d1a9f07d32ca8a0fcd212e3ece5c21a3be9d3ed2614d09ee9c05d4737	6	3	0	1659874120000000	1659874122000000	1659875020000000	1659875020000000	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\x72f7f81b476669f23ad458dfaa7cac2afe371e7b1d49ae6cdb960c732c9dd0e24c3135f4a775acc65205554c6f75d2540f79cdedffc78dbf5d4025e77e5360f9	\\x486b39d2a487a2b12215e0671966f66dab0ceb272f68108b8ec57d4e5d6d15816f196631cd86bd8459e647682f293a13f0d9134f6cef35a6e73ed6f8e2d61d00	\\xad12bc88a1657e53c9a48a10fceaac10	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1659875005000000	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\xf366195f0b7757993a4e601794eae1f2ce60bd825dc0eabef38717c5ac63b1bd	1
1659875014000000	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	2
1659875020000000	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\x37bb931d1a9f07d32ca8a0fcd212e3ece5c21a3be9d3ed2614d09ee9c05d4737	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\xc26fe414b1c09972c327e6e0f1c5e70e259e3cb5ac6ce411c550c06d7dea96ed	\\xa2653073086d2b12265597a61fd9148df7fec53fca8ffbd420831cd06784b65415d12553293ec473fe651eb3916c37e0ed0a7b051fd8d3e3d152b578ea2a310d	1688903290000000	1696160890000000	1698580090000000
2	\\xe4025ddebe0401d2c41b93b22c29c1d7199cd7fdbe5953abe29b3fab39ec27b9	\\xdfee77bca0462055e3ab0f5637d491acc443f092eeb662391a4c648b3f8dbfcfbab2ff65258b6fb7e44e1e5537a35ca402930a34095fa7e9382fd1c11394a600	1681645990000000	1688903590000000	1691322790000000
3	\\x0c8567d9bff75495151836cb32f8c055b371af4961ac7491a680789574f166de	\\x48279d4cadd49ba0a1e8449402a80b5cc2cc44ef5c3ab215033d3281530405203c41b33205ac7b2d8680de4ebabc7e36c8b689de4638865de5afc4121d0d9900	1667131390000000	1674388990000000	1676808190000000
4	\\xadfa94939e3c56224320945b7abc0878e9e40e0ed3ae795103b4b8e5d297f1a9	\\xcc863a201633a3b759eb909ddd9f4e6499032853eb8cfde2732f51389135f3b5de2504fbfc8f93161ebd285c677c0a1c0bfaf63b1cf8f6f8801098620f88ad07	1659874090000000	1667131690000000	1669550890000000
5	\\x951e025a80993b821ac4a0cc0b243ecb36329988a87d86a6046f9ef6a25a36e2	\\x14b83b6489bc31bc5e4772a2e2ad14aafe77ea47a29737cdd1f9eccad6c5b6ac11322ebc7a5224c60e19c6fded06eb163d05c6bc76a42158ed6266cd6130b005	1674388690000000	1681646290000000	1684065490000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x117023785e548135b5ee76f0cf1b650476a0fa3084bbf2c73c0c9b96bb7f1d1862bc569b5985131ad64d37d321fb25117f49c88417f8ae51e4a637db50e1dc08
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
1	247	\\xf366195f0b7757993a4e601794eae1f2ce60bd825dc0eabef38717c5ac63b1bd	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000bc06f742f267d31e70cd65baebddc02b8b908316cb8ff715d7110a9b117b8d060c140ea7059be6d5256cd1d12f32eba683bed04d41da60ee5c4cbe8c457d2c3c55dabdafe41c6ebe10d39f696f2e64ea22d4a8449fbf51f683fb58867032f8f2c685f25fc407aa645e14f04f5a54ba9c80337ad75e40e876528817e6b35e1e0e	0	0
3	127	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008d6eadbd83deec9e93784fa59dc963ed7f8d2db0107dbc6d27150739c244e86a6579dc3fc38d5256f81d2fe67f6f658ac8c578ecf6dadb2163bb17ba51fbdddd859f73f2de35ad4abca0b1e73f9914aa994f11b638f192364fd98b4cb8c7fa0e8ef24db0b7e1788eee6b799ff3923e736a7adb7a10759dead0b758e0bd1651b5	0	1000000
6	415	\\x37bb931d1a9f07d32ca8a0fcd212e3ece5c21a3be9d3ed2614d09ee9c05d4737	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c80ef1d37613f02783f4c94025db4646fd17b8f38a9687d75c19f792d65c3b0634168755b07dcd2e81cf93c5d8d4e1cb5ae04ad8a988c60d2be340a9a1560a8cec0787b6212edf66cd1e51a180323acb387139dc6e678b27f716c387ae7b7956340067c879045d6fc5c0c0ecb699884a87cfd35e0c71661bcc20e3acc76483de	0	1000000
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
1	\\x2cca75a61c9b6dde10772d1ae1ed6f3869d3fda107ae0a44fa28b2400e2b7be114b994add60926b3daf7f4c017365a82ce1067e31952b9424f56bfac44c3380f	\\xf366195f0b7757993a4e601794eae1f2ce60bd825dc0eabef38717c5ac63b1bd	\\x95613292cba72f13c368e8a68e2a68169e2b56da1eb3f784caae514ee7e0e9ca30d97e974a1fc5573b4726598e868b1302f66ea8ef2ce1f49315d1b7a12cb000	4	0	2
2	\\x33a868df141abcf6b2ed7036c5ab844432ddc6a880b232b81c3166a4063291233ce1ca64614111b690baba4d9f2a0d0ace2b087391ffee282c38c7d70c66a71e	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	\\x28dcd73862231d90a921f051469e201e87d343b3f2aa048fcf55e210fee582d596bfe9c79e648bfce7a5cc2e52017b9141d9323bacce307da874bd3b5d2f3f0a	3	0	0
3	\\x0fa32fdde19dd353dbc33d637cc49bb7d5efbaac324fdb67aea8711127db2680ccf9569c26e640e902f9d4e2d98cc87865550e19988dc615fab66021941ac83b	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	\\x2d70a7470b628ed8d5c0b37ec4ef52173fc49e0fd27697a527fbf541f70028ac37f7ea09f124f0dc573ed3849c6fc5f5da4b871fe38a074e78384e224df87403	5	98000000	0
4	\\x90cb4305df3246aeb2372c338048cca1a1a194496001eecd462fac8950fa8bdd0e7650d5864ba5d34e48e85e1a5ffeaf4098503b5a949fb03d571232a0bb3b60	\\x37bb931d1a9f07d32ca8a0fcd212e3ece5c21a3be9d3ed2614d09ee9c05d4737	\\x0cbe102c96f54ad8b861b446f425ac7759c7a971e5d5b7d62ffe5807b532e705e36c88427716d1b5b0645f35f322920b20106099d04f7f30dae4bc996204990c	1	99000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xfeb201705c68deade0d79dd23f4b370c1a2eb591ab8701d83cc2e27634c8dee044a4f6e24a7bca9ae3173d21f0f41521ff5582a4c6d4db50e73fc9820007c20f	296	\\x000000010000010004e24f9b25900038cc96d28aa90327c8808e1bed3bfa96919bf9fc4bacc8bff84a8403bd56e13c73efde2f58d67a320fe0f54a83c95667d8dd88ba5bb07303644ed8927e2b6fd52b6778d6439fedd81169f0bd1f61c53608f5859138a46b29ee4f08093230531a034f9549d61c581adfb0475b74bd39326f20990f4209e396bf	\\x1c542f39d7170b1ed4a39c5b229175cb367abda7c5e7985bef4f1f80155a6ea55e9a89412c2798bee4dc990e0f1783ce73a0a232992d11e74323665f713bd3ba	\\x00000001000000017e38efcf75289ba453319322cd9e299596b5e8232bc656f8fe65ac6897d670de4ffa3640e1b379b156046912924f8305310ce4084abafa42885907b1c6c245e431ff310a0f7ddb2abf328de08e168590c1f3ef30ee6be663731c95867bc6f0bae78dbf500a19b2eb1f05c4d2c1de52800a61f99c3e7d158d6f1351e8a52af723	\\x0000000100010000
2	1	1	\\x4a3698ab91e5c9ab1f5d86556a1a4058de68b752b70cadaaf46069e5736e2417dc6a234958d945893b37021d5395d76e6edf74b08df9a5a4e89a6a0d5408f307	269	\\x0000000100000100224d768de8fb6343181e87e2b852df92ff719d0e145e02c57779352c01d86acf1ac5f2de86aea9cd297313e858bf0213910d35314bed616b78b3290538c8e0ab6c8f181b9dea6804932881165090fb43b55c0c7cce3ab0eae40f4b4d01a17c07cfb232a066d810d7d8b90aa3a4d9f40ee5a7943ff83553fd84e3c360bdf7143b	\\xba5b2bef311717678e653927453189dd42583d662934ecee6202acf9bee1c901a2b16bf87f937a635e447010df74170c2b5e2e5b7291e4a270d3c8f4f8f8df32	\\x0000000100000001b20a04177fae5c8524dc718e7f57d36124cf821b8856e4a8713ace8362776018450d7d5eff7a83bc3d68c3a506ec5135ee7449f8af3934d587ea03857b0e87d67a69e515ae0405b70f6f63ba31bb2814de2702378255c998ab31237eb35fa7b7a82ec626eddce57350decd18cd57f0161bbb72beeece9b2518ddd5848bb1abfe	\\x0000000100010000
3	1	2	\\x07ad3941ece593acc86d20b1a84f0edcbdc98b19e350941cb6050f52ac18bdf071067c8a6d9455a152b0952a148a7ab768194379c994fc5ba71d19847ed92606	318	\\x0000000100000100965bf9c3b48d649e22c2a60fb615e8c063fdbfc1e139c9ff70aaa7546e7a0c84924f93333eb2e0aaa83df11aaa4d496f10e46e82da690cd7a6d36251f3cd36b141c83bcd28c78fb3279d271346c328edf76d806acc0fe4e2cc2162c3275324d6a2fae55ce83b7eaeeec9714847fce506d76e548c56f59c492e5c9be30698fe2a	\\x66e389f74e7de7aef29a3bb0df41a9bb3f0dc2ccca8beba9b2c2e3aa321331c5460da758752b0b06052bb1b209de5d3de461b92036eb99c1e846c30173d9b92a	\\x000000010000000115c0848ba3d211736b04625119d6a833935c365de50d7e7a41d51b44f18ab148665cc5910532ff9934c46239bc5e4bf4694fd934341933b036882e378858e995795b945a2d1e683564418993684cde31e2d47bea2a80f9f0d6289bf7bbb7dabdc6900987bac71fc4a0f23bf7cce971f9ac6fb9770ec27a778dec81e4ca3b25e0	\\x0000000100010000
4	1	3	\\x061e5203af4624ecffbce2fa58147a3319ddca989e9664d04b2e7b52122a8f378856ff603c3f99988efe9046e4cd65223e5ada4d36cc1fe26733eee2ac1b1e0b	318	\\x0000000100000100610f21d22d65bfc322ecf0ab971b00ccecba72b5f99f088ee3724f804e73ff41a77f1cb4778693b6d5ad2c398100871258ac6d1ee10c19048a389e448f8043a0a136f335a81651a65530f37ea4ea05205679ea0b3aa5dee55fab7711d6d1c0fd6d504af50e23d2ef5cff4e9b09de1a46ad7b99a5d6bd6d8e9c6b745e2fd0cec0	\\x30f6c3cf32f7970af7610bbca977ab430f482ba4fa05603cc474b4964a2a574d4c075cef127040ee588e93f33b4f68cdf6d0df7d3b2db8e5dfec2a18c8f57d04	\\x000000010000000172cd88c8592baa05d9327d2d7c41459eb78fb3858ee86a2339fa755312b407921c8d012f1a97d2bfad020dd0d0aff95a2e570bb224ad9e70279b1298fbb5f48d8570111af75e1fc5e1572d7b29b14c07a7dde1764b87ac83e064e9c5acc4e4b99db3a8745639e5696a7eb0ddf9aa72e96472f582e0b166b1a89598b172068dd2	\\x0000000100010000
5	1	4	\\xd482868e5f9a64c7d548706033a88c488dcca359a4e2ac77ca7ef8f9899bab0fa905d0e2aae6a30e33a8155e80321daa387b8e40595d91c2bfddcb457aebb402	318	\\x0000000100000100d7490822776901b8957521a182a55cd15ee06bd0e8bbd5614d9457ac8471711e01568ddd60dbacceec6ea969085e6212d98c9013d76a9a389647bd074a9cdc413ca728be550100dc8b3bef9cde62cec84d4e9cfdf13fc4554716494d0c16c5ad91d7c5c645a973ef10fb37fceff7199b049cf2374efaed2ef1d4f74e37f822f5	\\xad5d190cff1944e15c3ca95148388fb59cb2598d27285a09338d6ca1e58fd4f56c592c69223f9209921d5d0b33b3f53b9dca3c03ae68f9db5daa3e8c0d2d0677	\\x00000001000000015fbe8747fd427e3e9e238ecdafb638b5bcbc6eb8ef204796418ed473e95858e6010b9170f24f3e31c778b093e626705c670cd02bf42bdc048c87ae50405a9bcc5cdb6ebedd27b5819d2ea7a5854408ca07da2a0900cc55a0eaf14d8a30ec0b78f72ff4266fecac11604437c7c379312e450e37f3d27b787c342550db706481b6	\\x0000000100010000
6	1	5	\\xf488af1d411e38fdbc12cfb9a7ce546fcd1cf70231efe861d6edb5ddc412dbb029d5b4f25b27fa91ed5565264baaf6b4e7692fd4263a58d12b645a84ddb39706	318	\\x0000000100000100ddd3b6ebc712ad7efccbf4d0fbc8f2ffc8e4dfb728b71759d9da5fbe80b6e5ae59e2e1bad492e4f0c7d6665b3a7ed666f58de8c74f8e6d3be4983b10a86810ff86baf44f9ff7399bb1cba897461fb97c56ef6cc7ed8a445a177492e81396609d2b7db8c1771f0df3abf072c70c59f027d717ffdaa556a66eb71bd17e020699e5	\\x7e87b5420aefd4d5d303e5a12ea337301dd087263392bc32a61477916d8dbcd9a772146d9f2a44ced937268d812d10d70027f9102ad5141b105bd045667bf3db	\\x0000000100000001bce3df1f92a30ef80b0dd9452ea10932abd488344916a2542c1ca1ec7825d4173464a89c10903b1c7bccbc9a9e3c1426278854e5e873e8af2386b6f4525b7632156b4ef2f9e84c89d0fc59bb4f75ded9088ca50c23320ccaf59a3bb5a9326f1314b3280582a47f2da7d124a47a24f75688b89e330dbe148cb90ec4a7f8aea76d	\\x0000000100010000
7	1	6	\\x226853054050f99b280ea97894672b24e553534de3e3c82f713ef299204944bffbd581daedd9819134ee45b29f53425bb644f4723f697318ba53aebd0d7fda0b	318	\\x0000000100000100399241326a312b346fdae3334df16946fd218d8f5fa49c991253e38bce6cb3eaa39b577d56622860c8acf2c1fbd0a2d30cdcd7ef45a6b84817a9b49a13c8ee4dead1060c633b8456e85ae0b560391155e57e547d5179e1fb0a2aabcf447d56e153657f368f2c1d838d1ef5e277b5578f0f6c46a6383c5868a6ca336b17af7e56	\\xa58abcdf9da0f2d1943e40cde30ddb40039c13fca753d48c1427932257f9da3e2396e18349a3a98da1067475aa0f769a66f048d98c266a3a710ff83e3f96f24c	\\x00000001000000012ca270cb9b3544650ec761ef6e3ec19bbd2ef3d73cb0ce45b04acac98b4feacf68f7f21d241ae427fd251d1866820495dd6e20a2e175136c4b912a957e778fb98b006cb8470d3d40db47173ac9e6afb6de162a987d873cb44862639c9e6c036de6fdb9eb61f80a9b4acb4428c6cee94eea6512bef2d9a225843b0eb86c5955a7	\\x0000000100010000
8	1	7	\\xbc180038468d01b313922c033261331103dda1601e3873cdcdda5918f7b442bc7595be60e0b9d82576af21f479ce78be3dae1c477f74e5cce1b32acf7c27fe08	318	\\x000000010000010065d1fb0094a3291f09f9acdf260d97ea72ba46ca0e823f5fb0901b4bfb557a4ab7b50947dc9262c26e0618c549347e71491f84eaba000cfee82fcd81a4138b392c03b173c8db33acb1c5f3a8379bea64292362ebe6e20a96c86331b6fef8e1b648057df56f92f96f663b10f815e1bb8eed6e7247e56de6305fab245ba24127cc	\\x678547f332f6034ccdcb46410f43b749558a7b66a5e481d03dd8a93de502e00abe28af35e75c31df0a523a8b01a7e11e53ffdb07ed50d864ef8e3d3f2414bc15	\\x000000010000000178a06a17d35efa23fd58545ed76c58056ea4f39c7f0a430d4fb126410e27bbdb372c0b795f8e7d865ee8183e4bd3a5f9b524e31d98fc18add1be7aa79a9b383dd81f3bb37c9edbe399ce9df81336478d9fb0b057d9e5cd9f8b7fe944e8c163edb8343cd07491012a5f27da57d699d98c4d8341c28b926efdea4ae4f80d74f2b4	\\x0000000100010000
9	1	8	\\x4df6c3284ac1069f9a322cd884b8bd72ce82bb866b06bb1bdf4ebb5eaecdd33e84c1ae31b3fbd9a62e6e10e5edff0b59b7bbc24ded3e569291679a406ffc2b01	318	\\x00000001000001008622c2f24eb7696426c033ff8a658107ee3becb57ec6df1a6186414c069bdf672994f60c6c4360c4d97ba57683c8f782059ae16ee947ac109f97be33309a71c166c74f0ba91b4cfacede96368d53953a4eebf82e2c5d519e4b00c59b69c40f443242600d3efe60efad34ccca2a8bb2143142436db79d4e602ac0d76f475d6696	\\x076a165a20f5316f74accb4e8be38e994538ba5e89245d0e2473c51e0a3e92710e7f47601970db8f41386ad1f3a3f1d64c70e7a4045f4946afcafd86335d8283	\\x0000000100000001689ba027b82fd4afe125fc4ee0855670fed0f6d48f7e3f87c8a4fc66edf5576aacfa5590637136f41a068d4941651be51eb80b863a6d4d09c944407aa502728fd4d66a9e5aa6f3bc9ffacaf1d167e8dd06bcc45eb393be509944683b6db3d23256e38a322aca6f8f0d6733c36245ed66b816b617c9db1e606b13a33c04f92c	\\x0000000100010000
10	1	9	\\x0abaa5636c88e63ba1f26b6e64df38bb64070342dd48a054034c8a71d5c1c104e81011ab4c3d54eccf4dfb5e49af5421c9e51b87554032dc70f18e3cd225d703	318	\\x00000001000001008e14f5831373ce9f91d254358e5db60bf91baac691ac76ce193cb5ec03e01e32e52440eb2915e3d36fe4a0a1afb304fc7e084b37db4041a6ae4cd23f532208b867e2b999b965e2708c5bda9780b84297045e470dac93f258a57dd432b5cf94145eda382b4d19a8e5d8c2722e55728f695e614856c2fc5609a05bbdde80a5fbca	\\xaead07c66f91c7db563f442e55064da4309677ecab87973139a5ced536ade27019b9a71446655d2449101ba8163ae2545b4defb21bd4d9dfedde205fbfe3045e	\\x00000001000000010da90322c0bc5466bd2dc1dce75d5945022dee92fc95aa5c4e99e71c39829f9099e337a8846beadaff1593bdbf27195730f1fdaa4515ece5b33170f96e7032bc9a82fdb28a9e50b8de652099eae9cd1c619b4682a15ecef72f5c54f7439f24aa1d52c2aa69f14c8753ef678be219bfecf3a683caf854d5833d5188d1ffa368ac	\\x0000000100010000
11	1	10	\\xf5899532dc74d8d9edd7960040ce2ed40de60c03c290dc92c89e8094d6e487726548fed800283898415e31208acbfeec71f0959d39870beae8348d374a846a0b	184	\\x000000010000010066f89a3a5a233152fd552aac2b27dae0a78290fef1305407ea9351148b1f9824b0b2f059aaa81a80c1bc89f8689a696360fd14b7f3a9984ba71b5dce084a3d329628cf7e46c79df3c2704a5792ae8cca696edb7fe2f5f592f13841505cf190f230c3ea71dadb8a83c9482ceda7b5827af4046b0e132ca70ba58afed8c5cde041	\\xe7b4c3caadf70dd117cd6686418ae04f7a3a8344ec593034e8972ec1ddda2b45844c0bc03360bfe2694e21a1b7b85f4b5b51e9e9a8d37844a8175166cc1dba46	\\x000000010000000114049a537caa404c5b1c549b36f656249d765abd76f1c2f248b503e6d64cec6c6ba696e19baab076d610a57dbfcfd14b64f61c0942decfb81b290f2087caeec4476b65b8e1f50a93dfd7fc439c88d734f70713c068f009d977a5e487a6737b91974d2d4d5f3a693c2bb5843883d7d785be56f9b84190d04dff82ed5d9e66ddea	\\x0000000100010000
12	1	11	\\xc463c1951a54b83091be67a23c14e511cd53a328da68c82ee94ba25b22428418d5ca525fbbecd0f013293131ee2476daf8cab4fc34eb182bf384ff6f4d2bac0f	184	\\x00000001000001008e02bbf452d8850a40a50ff8c1f8367cbf7ac6bc8053b1f0d633d0fde3839f2c49ca8a8ca9c1007110e3e08964c2d59b425dee9d725c885145225d5dd403085e70073a0cc43094dfbd41877e20c791175f81e414ec61d613ac527a0ca3d29e5f4c5c3b34714269c9574469e577e6ec4737ec84cdc6b03f7bec7711a1aac56d9b	\\x57162404eb590f7108ee2360ed481af544b04e0a5371ce415c0fc4740fc04cbbb3b4824c9ca36a27a90a2304967bf9e79697289bdd2d2fcea02c41a8e302f6bf	\\x000000010000000193620ce884182a7273b6fd0558b964489452d5a4331c7d701a3ced2880245154c7089fc8eee532c9df57b82965eabdb70532ab13330332c976b00a51add80e8d16c397758b1a5d6b85a5af1175120823b07d13a13dc82dac945608fedf1c2b4cad7ae1523091ce9ce159edb2b9a51e873319f012c02eca2a1f61c90d67933606	\\x0000000100010000
13	2	0	\\x69db48428c1408dfb6b617a5e95a3bfa85fb340947f6ad5818207fe3e6cf6dbfb9d1d8643c036779a05c96f55d0107ad735730bc3533e7da5f0dcf742b63aa08	296	\\x00000001000001003bb7a5e849f01da605f717b9d5b7399593cb2d523cb22bd700d7e8635446088ddb506b6db0fee377ac51c3f99d812cb993a58352a881f027b472b9ae922b42486b25dafe77d7b4f5ad7ec7d9b5a31714c96d8fa4e0e26a5d78f7c26e3720f1d5a344eaac0a17ea77756e0e8d03c5b44a6be35e521077b445dc4eaa1d23891b64	\\xe93769da0573295e2fe85fe88e39745f9a21c10246153c8381c5296ed34968947948cb38dd1d9cf781dc296bdc8e4d482367eeb63ec8353c948645464a0176af	\\x000000010000000165ce0153e67bf32c5a5426b129d9dce4cfd697b1d3c9c1bf4478c4a9dd0934ba0290957c19ecfa4652f6eaae145fc1687823c0be41a8fe3d14696c53118ab786446f63599ac40d67f20495d7aa8c12bba345b0afd5b050825a1a7ab46bb3ecf41b8e6cb222203ed17507a3b535cd12cd7d77375275be95683d67d48f301313e5	\\x0000000100010000
14	2	1	\\x2ff28efd8ec68c475ec8c2694c01c2cfd5e90dcce148b16f47d743856ab7362118d42f292f6c60e46e4d8a89a16e793dd359bc53a1abbb514ec8d6c5b7b4e703	318	\\x00000001000001005e078c57abe621236a2ad8a5f3922c5b881f00322e8b21d6b9d790bbc72411d51f053e54a4a70bd5d4936512d9c365782d18883792c4f667784cfd4df2bb83bd13143466120d23eb6114417ac0aca9029d66486dc49b29a1e5afa236957fb2ee40a9f69bb19f6fcb4fe527c7380a1ee8c849bc888885af71274ef8aba8cd3580	\\x16b422c43654037cf5d5130bc386d8ee1abb623ea53f9c0e8844f243a2ff103b3e6055ae5af3e68b4d594f01ee33735f53262d216e18c33d9fc26f462163e785	\\x00000001000000019643fa0c52833a06c5c6c6d00b5f0626edf1d14a06ecd51ff40a5a2ed5ba971cac03cfd5ac38f08f3a8ae4219cdf8fd448e21bd3c1064596c914a2e28f76b2a1b5a528025fb4df503597e3d77c1bc2be36c039d253165c1fb95ad16a30fbb44255c9d427f17f62c2658fb8eef2e833e17a29bc4dc281b1ad78b6bba804461d3a	\\x0000000100010000
15	2	2	\\x7a46ace7807ac412edf2079a9f7910b110e0eec15db2b7bd09d36509d165a3e8d45ba0a470d21f9af856b17231865420d0fcd34d4494263a8f630355d2113e07	318	\\x000000010000010095a419bad53c0cc016d44f63cdc5bc78df46f10ddedc85c87850c7f269f0e47d4a81c94487adecf53f054c1401b57d8c1983fafb57fb4b81396b9390c8a6fefe90922d00422765f38e2e2ab98d3b73792ea54a88aa3fbff8c3fa554ce53f0876afd142c95d0dfe80e0feefa2f9eb4360f61133dac0a978847d96c6c2ec215d05	\\xf489687d14f63210396d98539d16420170b99c90a91ded145c9fc8922cc630c4bc8a4954a7c2047aeb4eac6ad075372ad73d85a6f58fc70f03175639b2805519	\\x000000010000000119d4bc90a5c7244dafa82444bff2e96a1eb1078ff827a278db07e99d2600500fd8be2dc0b284ecd9cafc0bf6e27c9beb067d0e7f3237669d5fa0dcdfa77a8470689f4f351ae2c7d7b6ab0bbf88ef9bdd301d0a9bc2ba18ca6d6fa839ba9c14183affa2ac752f755ec573160ed525558ef326e3009997476dddd97d5029d6cb5f	\\x0000000100010000
16	2	3	\\x0acfe00c47f48cd22970cdeb6a6079161e863572d99093b3aaa3b59efee9be02491f3c9c2447454849337cdf7663242dcae23dbeb6d0dd0086ef94a7975f1c06	318	\\x00000001000001000c3a7e45d63047f70c2da6ad256d4fba56c41bc929d9c1db36fca8749bbe898b8c826e9fd2931db0febc1bb13990b3858b66c4ecdb8b28b8aa4495bbbf8352aef5bfc88cd2bd37b56f2dbb59c2c233ff7075ae71e82c8a26f913fa227e9d375d31e6a1827050e57dda84f5cd0f1196384582cfa771d3691370043c49d6730e88	\\xbc5aa200b5f8bbc44148de2d37be5d3ed36f5aa9b59ad6f2cbf5bb51df70db920c3dcf1522911a4ceebf49107003a8ef1b24cd7e0973b851a7ed17e013e322d0	\\x0000000100000001b8e89131f5c895f5b084f4e67d0ebe0d8e175304ffbd4e4d1aa2474b553754191fbb740818df49d1d58fc4493d2a261286488e82f4da24a6328739781c18b6b9f6de8e05403b4a857c4c0db163f19858e34a864ecbecd8c7ee967bef5a6454cad3b8abfbced654ccb86a3d1b40cda238401fa13a12f9cb49ad73a045a025cb29	\\x0000000100010000
17	2	4	\\x294b9f013ecaf9dcf0eee3ef4fa0ff024af7937f25a402b8b45a85d6d772903f709b9f43f3a0cdc56d9f865c29298a593257c0f2970f323d9368cc78a33e4e03	318	\\x0000000100000100c6453416895dd30cb81f0c8f35798c3992e252c877ba964c2efd213776dc211ed77c80c9367e0cf14597fc8acb18a186900b229911d7bec9b2d93f733b477b7d37615bb1deac672f356217910987e8a18210b448fb2bdf998dfc7014d1d14a61dc68403a8a135290808f6aadb83ab7d7c99b87e59f2ba042a81e894f3b134823	\\x1ce04dd58b8652736a06f266554e0797cece88c66b24f132e77c83ab2dde571ff600ed1ecbe810ecc918f0395fc0813ab2935296a95cb1dc7631260815512f1d	\\x000000010000000138baeefeccb223d4d4c17a69346587cebf8bc05ba9af4537467a360e7fc80e3d15e5f7d075ffd0c4e3014a91d2d7b35e5d7b3766a9686ba2b9481f65c42a397924a1dbe91fd96ca7ff080b08d0b388780c45329f160718311b7a2ab477d457f1b7d764e08aec1c2c077c5e1305284020ebeed9861b00e0efd138be7d034e06d1	\\x0000000100010000
18	2	5	\\x78fde6a4b7c3dd6ed89b66c1f4ba17c5e99a34e69129a792ab039e4b6f8ef7ab52df8e7e43c58f6e2356a696ad6326d5ec163b20523ae227b6f6b1d4f1b03b0e	318	\\x0000000100000100205651ffabe9ea8d0cb352694d852fe2219c6ad1bcdd9835e8110f9ba08d3d54ab8e486bd95acc3a93a607127bc93b662f0db30bc386bbd483959223c7943741a317c1475d114acbe916d108c5ad5fee548acab8c38b518affea6f9938605f0d2edbe6405437f64fe8c59585c5aaf1334423e68fba615d7bd87cd0018373c7bb	\\xcdcc22b535bb1a8e2a334d60f5d09be65cf7ed76d468308ed83c3b3486736b15f4e64461e59bcf0fdf216dbcea3a1b81f9216b339f9e3d21c2e9190dfbda84cc	\\x0000000100000001ab5848cfa35b9be8e4e483c79e63487a33564aa786265dd240951ff934089e0f270c46fda201186502f68d25dd3cf26acf54f5e882db0bd115108e477ca653c7e8f2107d41fab5c172dfda8ed96d95f720c74ed416e23926f8a66fd7a73d7edb5587c45219b451a12b46e4f1b8b36c772c717f0310d6e5e9204173cf5e8de015	\\x0000000100010000
19	2	6	\\x85679e7deb0c68a8026858e522c535cbcb03d0605c08cb8fc5282b51e934ca7e565c96360e3004c0b0765b57a6b729d7f52b8c868e573866a46d72c80b4e3706	318	\\x0000000100000100611a7de23ceb8478cbeca6049c2a4b3cc273a5e53c03d69a5c76d15360c017025d81fe1fdaf9a4443f079457e0a03efcbad2ba870740c0f0020f46b08bc5827811e4a9c4429ef43c1a6901fdd775dd11bd6438b00555f60bcbcf2e072f85f75d3c1d0f94e8788c313d6e862386ea2d4573fcf4ca10c467da3e4f2506e9220376	\\x6d572821e483b84f361836fef8a601c4060149e08f8f76e8ebe20d0ee74c9fb3b70fccbd81a1665b260cd9b35ce24e66fc5cb3179e961fc18be36bd1534028f0	\\x000000010000000117d280566af67959e4e6006e4692b656c396196d9414a9d70794f86417ae2856c09b2f6197f786e5e06a92c2a38db9e5cd61aaf1ef5995ff92c8101dadd3a61a904f0d0995adae121fb8c2fbd6f75f09c3d2816767a91114c7a8ae029eb88e4bd44ca5b9f82427443d3767ce9fcd4dabde52e962f0379666a7dafa6b3b80774d	\\x0000000100010000
20	2	7	\\x626f01be275fa2983a703730d64285efd69bdaf149e145b87dac70ebebf1c45b0734a8b9179c4d99e938bc2a891aab29c92c8e504259c3153901cbab2b6e0506	318	\\x000000010000010020864dda2d9dbc71a075e0c698eb833af3b821ba1e5781a002d45c8bd8fc814f204eb29cb054663bf1e074de3fe52caa5ee33c49f5d10e8f5a09ab05c44427dd8fb4b5565ebd953b68bbefd10702a3e31c16f94b5420bb69fe41cf894be8a6823c5d14dbb1dae1de81f4bd4c8ac2642b3d8afa89c6e736db94114721c00f97a9	\\xa85b2ffd02fc6a845208b09dfcb560b50d5574567f6aacf510dd8b06d8b3c6c78175a74f05544e76f18832292f30b1df92d39ca9f0c3c31442ba92a55bd2ff1d	\\x00000001000000011d16fc18ec6129ee914c529420195074900ec0f0dde4b259354e8295e5350311e7cc050fd080198ab06a3e76f8aec10908b73762bd31b88390170d95dabdec3123939a3623de98cf73c32bd93077570bdf2d536a2f18bb44916a3660642715c2a80d5995aa56bd8eaf87a114fdafb00d98668e5c3595e87d20083a35641dc3e1	\\x0000000100010000
21	2	8	\\x1dc58310babd25bfa80e87041c2891176a245f4eea61ab619a75a9bcce4dd7ccf504e1c4caa4b477785ea983991adf76eb5b8aa71dcfc44f255ca85f2046850b	318	\\x0000000100000100cc4aaaf92025e9ba7cd6b44ada8a79a427817739bc3544f777846b89e54bb7fa493ee49e1b38c7c2e23cc753caf4a9fcca633e2f5cc77e73b9f5884112368014416591e556c1da84974af5f2ff5a00250db45deea1561fd94a032c1251e2abcd6a64b64ca6b5d87453bf24be9a98173bbc6eb54748b6883951eed2bf53ecbad0	\\xf11454267bee96aa9f8ecddc41dd3b412c9d8b78772845162a1a59a1b5d891db4f0b54f4fa717b45e0ee29e51d0f2ac5b4fb52e5bff57c04ba5f687b909c6ad9	\\x000000010000000193ca7549910ed22427729f0d7f8a09fa7b8c6a6c6e8e475d869d169afba9a8ad9612ccc8058c13caff095bd669d531da28d86d8a2ca74faef5ef2fa80786a135fc93820bdf6d1e3959020e86d01b64c2da7fea449525dc120a295dc9509391a689ca4fd424edda007bf3a7aff274800fedf0eadbe5c725bb5886be8cc4ee7f90	\\x0000000100010000
22	2	9	\\x3f08b29f55fa01fd8ec4c056cd1135343d79764fe763ba77b86c32c3186b4d20fab9c8ba2d3ab0dbb87dc4fd3fa8fdd363e452aa8e2b7df3a99f7dd40e4c1d0e	184	\\x000000010000010002e06b088c923f9accfdf0c5a84c285f651b2707e1fb43067ab898908df8470a5cd6250eb876d3799cdf1a59f364e6406ac1cf1587624782b7e320069e0e7bc22da3bbd6be61d93b9a4cc9cccc82d92502f2822b8cdf7f2caf74690059fb8b70ca9e3a7c57a4203c7d97c11d93fb89d23515f19d3c614ed57a18390a90a9c406	\\x772eb7e7d6e857b6151b42214a955377edcf52181fa1b6b68b09fd0f679b65f9eff3d827365bd36a92348f0a696b3b9e22c0224d76c08426ec9a62a66bcf9f38	\\x00000001000000016a95d6e9d0517ffc41fe454409bf66c9af822d1cca7bca4b218171688debcf11c2ee81b1292a6a17249fa2e505f6496f17cd8ab7d23a3a36d9a2c6cdabcde40d60a08db07bdae04aeeab5df89e3a3508cdea43d19bfdfc7d209352775ef0c56e82df6b76ce50db82688573782b53c3f30a63393154994b9f9f88982c3b1a0aa8	\\x0000000100010000
23	2	10	\\x63f8c1c548cfeddda013719f828abbf1f535976b6c80c17e00f3383f8dac9ec75be0d262a35a045ecac7412f98a45cbef396992d8fae27e9876fc2dfb0514708	184	\\x0000000100000100130deb36cce65837f6c54f2d7c4ae09a2f650b5f470a706cf87250e165679c21d2515330071d12495c455a34a94b0347ae090eb658f3f66c85c3fba02a270a8d2c990767fc9b87794aa9f292a56ea237d3f5c080e8c34dd8f1bfa4b3a8642ef8b685632c148b946b894409eaf911ec3879baf8c9cc05d8662b25ced2eb5837b8	\\x0c4c8bc3b3d0da4b2e27a8b6a634d8909a77f4079eb23a5ff6aec17998e22818d1681ae732653085e5bb21e01458eb2ce52e2e38e15c95198a5933a83c4ed1c4	\\x0000000100000001336f522bed36c9224db0b4eaea962ba2ba23fbd1c1d0e0e479b25c610d4ae237e90af2f529d7400f4e5c40d9f05480f05d3500b5832167c14c7ec324bfd001d6c91b0a609c23c58512af815339f12f3a971d5294376513c81ea4d81aa07ccd61e0825095cfc0e48807dc7159a672e09d47c84e16c06f3e4b717f73b6ccc1541b	\\x0000000100010000
24	2	11	\\x6f87d8cd9b61f72524b19ebe121747c7602accabc4fbd67c9af5792a133b789a2c13982a019095f5697561a94be66b644a32448c1cebaa890dcd0eef7e71a50f	184	\\x000000010000010075cceb0fd8ace14711309446b5a703199af94deee01cbbef8a694651b9dd26aef6b3f7ff8870e12aa59d8fbdf0e3cfb5e7617105fcd138394b451fd7dd61dc23dcbdd17b8cb22717339a517befa09a6853432e2235cee2efdb0303eaa826ac17afaa2ed27661284bf28d2bbb7cf9b0ddbe8324fa2bb1a01c23a8329d69a0ab3f	\\xc9635f6f1c761c3f40be4cda58106441c346419868e2e68503391d9bfa342f0df9d3d66b0957dc13670ee1b4b45182521a20ff09cf5b38f2e2175aacec5b7072	\\x00000001000000012571fb7ab00d1d96d7c41f57149d6a409ec59d42a62a463fab1a0616a9085fbd348061fb4c0aedfd31c93298ad118c0b4b8b3a59eed91c8174fb079ace2d0ed5f7b8fe2abefaf35a415945273211c5c2536d2c07bca87bbbed7f09b45c3472d35bd5a903cc91703d29ea9d4fe1aa37c6ffe6e4a81c870b9b834cf00d1df22aec	\\x0000000100010000
25	3	0	\\xf20dea18ad98c90f6d365b68119d6cbd3cb5328d7b54a6567255ae6a0d83f1c726599dbed1065d6c75bd62e62c6ed8f90df2017078bb690d2a9570fed6c57b04	415	\\x000000010000010095a8d5820d9650e06ed7eee4a88996d9975ad6908bf45e599b2e92b4d38ae4256fd305a51a54af329f31633862d9850777ce254726b29973ef02a8f0d5a550acdea864e4bec5b889a57fb6db779d1824a246b082c009fc4a95abbf11557c9d830281656f62b3a483f007b9b31ca10630f6ebee5b81a9ca4b38f083b9e0a513f6	\\x387918ccb28a0c4e990a8002a35830c832f22ecdb41320010758c35916b0bd82237af877d93cad75fc1dc0405072764f6b6a45f9b14eb21fa064ed5020cf32fa	\\x00000001000000010943e557b12db3765011d110bfe99c38a10093a6dadfd84bdf4727d45ffe2e312ff07bbb9977f14024388b4c10ba01eb5c44f34776d5ddadaf991e2da706480f659d1f616430203675a242cb6bd119b26081cbad07a2c94d4dcd23091643715a247d4265178468e31a07a65ffae66bf4f824e39a7a4237963e3e98229dbbb853	\\x0000000100010000
26	3	1	\\x5de8fa836f6ce9d054f6aa89674daa52f3be77cafee6b5f8eee9da76c798460bbc3d69f333fa32ee043f0845ae226c4d0b4ac8b0df51f5f35bbbc469d16fb009	318	\\x000000010000010098324c3a42898427638900f917219cda7436d271558c25adf5d2005355dfb283353aaa9e7e0c5c4e473a48cc251d47419cf1ab1a7c3eda462b5825a6f18c6a0fef0e1e7668db144cd7d11ec7cc3cb02fdf8c5d58b0ad548cb5e91ffde9dba88ac8fd76ef7eabbfbd4d500ba9ea233b3f1e597e64d8fb11a72d2591b79d0d49cf	\\x9b85405cb978a7cec0b891770e42b276acd127ba7d2005890cb3fc3ca09407d871d62680c745d211c3f29f0f88e1f278f7d2e793f70ad8b9ba335bb1deb2fd72	\\x0000000100000001ce73b8a75492278e3ed425339b8738975e24735871ae11b50e573c8633266cba84eb3e9c3cdce019e7903804219ad4a453c8e6b8e7bdb25b2ae908d792715934aebaa13d6f32116e41bcf1f3cb539a0fa58b91c945efd365ec0d52b79b73af1ec186402352db8f5c605e4907519675f5d9ef09bce8e84a2cba1edcd741d27925	\\x0000000100010000
27	3	2	\\xeccd189d1d625d691dfcf554e4a134b37aa7ded3094722f873ae5e58fb5c89bd164f8ef1e918f2aca8b7f97edb2752c3eb4b6d0ef33aa1864e908c23049b5507	318	\\x0000000100000100c515dc847b67cd50fcf7f4f666f8a5e27a3ebca0729c7c168b3c23bc6383255edb92b171cee0078f5b15de87a8edcc893e45c9954474b1b6a4d45a641c5ec108b933540ea783a651bea1a8784f257091b5cd85ab91677b41896d81813a4cfda39c046af90abb0326c9f26e9bee7d1bd9abe726ea82d9762c7b9592b7e7aea75d	\\x8e590ee17cd4e127ff667fb4716c1e017e9b093bddae641abae9415c1c59e4b1ce6cbe15d4c9bde55d12d7a0b98646730fed730703fcaac22742b2eb8f32463a	\\x000000010000000104c8efe89df908435cea07e1e69adb56e7da2cc746ab50078bd09c51fe493fcac6258dff63e1c7cccf765166f581f3e80db142a73631698554e77eec17e0c25fc757791ff51dfda093b7c7d38a6ec402da45e354f9b4d9f7644dfea05d275260670bfa2d1ff6d8c61b210a910949f8e0aaf17fd376dc206433b8e0d237e225fe	\\x0000000100010000
28	3	3	\\xbca2cc3277e2270e4c53cb8d6faea998bce2dbdcef5d6c8eee942b385e914d0990831f3727ea9fac77e721616d40e8d9bc11da3b7c438919032be0f0c1773306	318	\\x000000010000010097b819a0bcd82b6209cfe684276a82f6968823920b6a44c05bfd46e4d21d71872a70a0533755a98ca5edc2c887cc913300ed66075b5260a01e83ce00571c9e361198fa06f19498ea2bddb004042b797365e5760620ff3c4d5d373336f3ddcaeaa944d0b7df43ec481c8285f75618665892bfe7fab9b28068b60f398c6e96f5f5	\\x1563923bd629361ee1b3098371efdb0a8c8e2d70104a4e943d54eb87cd15a81c1b9b844e36adc99d1b67ff16646ef7d29605c4f1c1ae228b8c4d576337642d10	\\x0000000100000001cd5a7ceb2fb00b279f24bf615b2d91acc04fa6e82563a608cccbfdecf40b37f69fdadc8e431d3d710215994ec74ccb456d711b09de753441d1e5667a080d2ad01c09aecd4fc9311b9c5a52a223ed498a6a4296ee98afbb5ca3cbdefe82af0b1f3871f52d6ef69f0c6b3750ab8b8427105352bcd98ecfcf47bde7c9618a540902	\\x0000000100010000
29	3	4	\\xc24ff508d6878e1a640a7eb7e7c81580915510fdf713f0d4e53fa1f426a67b4e496acea2c7a7e8e8302dcecae4bff7ec667216a79388cdc7de99146f76485605	318	\\x0000000100000100753fe473dba70b5417e4ce404c781286a7f3f4fde42cfd884e5df64042bdf322919a8bd4fd4bbf62035c2e294c95b7e5510953ac230946ba916004ff914a46bfc4a2f91cbe9f27349b47b85d84e86328a73587b62de7215d48291000ca4773bbafdd143322b46536e3ecbac3eb5fb31993ac788427a7030687127f11f10c28e8	\\x414ce358c86ffbc06540235d0b0739c6dcd771da4759af035a7b2cd381dc9ab4572105c4a1949a1a9a0397c086f07b3f661102f250713b3076f9ad3e1fc0855d	\\x00000001000000015185150c46ea782d33589f06c19337f2de9dab378b6dd8dbc8547fa64e6eb0f5834027bf7cc5a6c5304b8255dbf3bcc0e176c5dad8422788074d4522670917dfe8226bcc753e70b770851ab4a1b946841656c54fe553e5d2056419cbcac8ab45bd6b870ca5571b6ab0d6861cb65231537c48a33e483e259ead3f3a9b85af9ab7	\\x0000000100010000
30	3	5	\\x175bef77a9fbe7f2e3c3ec76c6e1e998edab4e6c3f144695bd0863916166927d2a8c64d1b4256885a70775ea885d411004ecba32733c7d38389d1ec6d9d00c0e	318	\\x00000001000001002ae0aeb8c204cf41706a73d31cad2387be88940987fa743fa8e52790f505da58f84c55a7b09aa6ddf2b4719a825d3ac29eb00012be5db413f681e0c42bbaa299af2920894ec686264609a78bdfc10e27405a4566e30d54b3567ab7f8dc28a65bd75632a412f98ad1b553c9341d9fa924208531115c22c4d33e72c51c6eef0af4	\\x91fb259f63ccc355a0c98673f615886470e337f8f0e4c380070af6c8094f7f8dda571fb7ca8f1a8cf44ae2d5d972cc413a7e7550a85041645ab4c427cace58d0	\\x0000000100000001d1f304ab25090befadd18bd425ec034bb4af4751e493924163ea03fe6acb56fa9eddde649ebbe58946b076716542239f7ac6a3bfa88dd84b46b66beb97b4afa139a9f155d875b8786b6854da40f3570076a9361e6c847b27e016c5f6a2a7d1c0587cde542fc900aeaab298ba2054656bfd8cfb39bd26535b57adde3dd41db8d6	\\x0000000100010000
31	3	6	\\x3bf8a3d3fd4d56724b196fa0793013b235e9f1cd4ceaacf96ad76d2ee1d5ce2add2737d78f2d60d961979965bf581a5432df5ec2ddbd361875de45069ca13d0d	318	\\x00000001000001005c68190fa6e86cb1b4b208c3be61bf371024ce63ab81bd508124bfec795c503054dbb484d9b39a5b4c035a441ba990b419306e4f1bf3fec4ff223d0e0f469446c5257b271d98a83bed0977a128717a0fabae9c2ad86d5dc168dbb7bf192702d7f6ca792162bb295cfe45bfc59b0a4505baaa2b8b0cc4207eec6741eb2e5ee27e	\\x48fb3b6444e9f773c5ee39ea044320059a111c65a3f75cf11f942adb54d9e4e9c02bad92a56572e69581d85a0b2ee4ac0fb870b8761760132c1b6756da7aee30	\\x0000000100000001563cfe993ea4de521cc0633d936a45ae0a37c238dff8d59c923fad9367d330ae6f3a133daff75b8fded3b29b6dbfe6a91bbafe5e162cd59930921b9dde6350c0619acbe79262418b688e26bd85e88a3b7670794309b689b3d5cebbd08e1e51dad99ed4f5b5fda1d0c8a4625ad7f67200d070cabdb39b46a93ecfe0805b715518	\\x0000000100010000
32	3	7	\\xab5a80571f47999893e09c83f54c37b505a111326af96231f354204eff073e26447d4fc4fc85df2526f39eab31a2ee76bd323a99c8488a8ab96fa6b75542cc04	318	\\x0000000100000100c2d942bdcfd72f6b6c964a7d33b6c366435676aaf219641e518c10fda9d2724f0fbe3bad0659ae781e97052e8925dc23ad6e9b79007e0adc575e0bfb0c3c54f5b7dcc9ec298b89bc56c79bf6b6f5828cb3e757c1bbe4b472e127cedc001eba225e00d0a525edea109da34c7224d96964191e6ad0a277607f6ebec79881830b85	\\x399cd586b7b961966361edb4f9b0c351c88c807b8fa19a6c10e4df11cccf0aca130561d5414b9267452812d14587a5891e4e311bd4349f0330b46aa1ad23b243	\\x00000001000000013f8422990764f03d616cb3e4fef464929d7f8b367027d2a4e9b76ff6354eb946fc8cd2f450d3c12ef5956940bc7928d6b894d4749bbcb796a1ca45fb51756cddc2315466a6853f5e14f632ba9430efb719e923119bdfe4d1a663df98fa8f71d40ac151a2345417e68cec86b5b862effa9fa9a3d00cc6efc73c568170e4b60adf	\\x0000000100010000
33	3	8	\\x4bfbc819ffe9ae61278db26803694477c9dc6b7e31f59d9ed7d10cd5c4d7533685e4f196cf27313fe204223f68966cccd82ebe9beec5bb862539afd31cfc690c	318	\\x00000001000001006782acc40fe3fc60ca5a23edc6aa293683f7ca7b1fc59c2bcba84b000e72fddeb6b33a3620403172573be52792a9c9b230fb3016796eefff0e0258f731edfecd272890196ab759b4b0cb6fa7ed164817e9969e5ddce68d2b807bf4bd8339e9d162a7927a433e35736647304b578f3c951516559b1ff62a2b8a606a00ad30be27	\\xdae1acab250ed6e9dacd09962b4b10ab614ee345c3bbdfdc139632ad0ce21bccac37be60c26bca72bea8856b876c3e10ff0e0e168931413b9e6b6cac0d7a00bf	\\x0000000100000001c9ea8e590a3ac89f76980575c698cd0bfb2fd7089652fbfe6bd2f88291b2e5655a471ea1f53742e4f27d62369a480b2ab30168b6f40f9ae056740681df27234a3719da3afd22991feb5469aac2c9f91665c67648616cb9ad150573ac6cb03e45090913e8e44d43d949d6b4af1a7d0ae7a0ea10b1dd7eab4dab6617647c3726e3	\\x0000000100010000
34	3	9	\\x4a752dcef143e09cc13f91e1fcc486d940723f6731992b34f0526e8df77003b8942093d7b9fd2cda203669d69c5e61edb00f6a9cb56f70e4d80bbbd35da60801	184	\\x000000010000010027b9791faaa9bf95c8903629666e516593348691c0c87560b5a9e0576c5f44b4033a4d852021e7a4f4a1f7b0bce3f8c48b253b4042372fb1089c7ef48943f3c6475ff216e883d6b3e8351a1ff5984e17bfe2e6722df1ebf5725f23ffa11c265c35d39023d37b9602bbd36871d89b0ea2b498cd8143a2871aa6588ad2c763f3bc	\\x49f76ede1e580a79aa68624a2baea51ed5199e17aab28d7eab1fe48f7135579400e65d175339ec517ea4283fdc322cea8491937894e348d5915a1b5c355feb7b	\\x00000001000000018ee24dbe3ffff5b82914a5c0e2a28c22caf5dab5b3a6e1a1f5995f66e7a2ba5c227ae1515d5c77d75bdc15c3514a212772f11380ffbb646f3e6b4c5a51778347e3e41e55731fdd95571090f399ed1ce48017861128ef823c2eadfee7c403e3aeb3c45c9f1984d20ba49a93b915f9a9934fea0995bf4c06562f6332f38b0017bc	\\x0000000100010000
35	3	10	\\xd2a69749b07720d8c81c4c11b063557f3d4eb55903c5194ee275c274b4e3aff170f661f4eaa0a4bacf7ded9a6346d724dfd4bd3aeae5e955bc2a1827a8cbbd08	184	\\x00000001000001003b67942c4b009500d6bcd89c10333f7dbb6a2430d29bff7f200816acb37fdf7bf2155fad7067369987a7d870d902879b83f40e2099f4591fca3411379784cd72364e0e66b03ef4f1ac6f14ee8beb8f71a762a5416e9d2a7c9c07765d8b100f63a72086740dea1bacc1cfab7810681abb7095140c5e3efc28697832f17bf4ca3d	\\x968f4490f18ac9e3d3368dc16ca7362089261af97ca1ddd7f0994da380c1cf57d142c59e4c6f338bd6e00b1b0a601bb54fd5d29a8bce66a2f0b114f1bf5c5fb3	\\x0000000100000001910fb6826b8fee804c1c147dd8ff01bbf5bfbf83a80ed8ca6708315ed4883e41e8203e950f2c46230cd1217ae2e07e79294e70b22ddc3aae2c939c689b9de53aa0b3c7f8df000f2efeb14d9f9f4ffbc1d032aa210de74bbc2d0ae417f555927275253a294027b05bbc9b8af86388fed40ed0019d15eb1af835480046fb4cf660	\\x0000000100010000
36	3	11	\\x95a3da00ed60b530fc3eb22d5b999fa13866b0affa9ceee9d9d718c7f1807ecf33a4b5f35239b8419710c33fc4e8d88ed9456fae39331dac27122493a0da1304	184	\\x0000000100000100aec9492f9a4ccc9dfc892ac699eaeecff26a8cd153d47d76af9c12dd1abd9901796869b2a8c83bef1b46c10a604622f3a3b22096624f324b11ead80721ac6edfce1636150c7b47afc98fe81b2a94274ae73e7c7a3e11b39b899af9915aa1d1c955ee4c5a4e63397431de12abc94a5487f30eebb4a806679dca3e575680d35ee4	\\xc2d1e41bb7711234823a35eb3967288011d3c8ffe48762abc1cb5c6e4edb1298cca69708ed66d9087248342cf8ba37d894dc88edd44cde6239d1b710e4c2c9c3	\\x000000010000000136dfeb8eed93523dad5a3e738f35383037a60d5af30129edf313d7a2b4f9cedd5a55441b259cdc1dac636c3059f4e132ead2de07f0b4bcc511db3ce01f74b47e51c39d93213bf47583f6b19deca5f5ac9f55c8c3914451b48cf63ff9b48b0c038f1dfb31fdeac432b4212996b010267d2ff5608ce4a979d5e964d22217863bb4	\\x0000000100010000
37	4	0	\\xd2867e778b52821c7a9c8896383a545d99457abb163d2eb5e39dfc6c31eaa63f88eac2869728f5ea4a06e3c1a5747c97295e178282de324940bcc405d2dc1f01	269	\\x0000000100000100863e5e43930c2f9e7ad8ec98fb10dc5332c1e3740e69205561fbdc1741691511649cdafca5cdbd9945c23ef503a32f443a1ad7b43190b4e3ad24d98adf4c42fefbae250861a9450539e6a5479cec386140a90da2b05cb96ee93cd687fd2a32f5828327b78a5fc5d22a933a6f4bd6f3d42434cb82b1686b438a1df56b33ae1805	\\xd99f3f065c4a2f7d8eda4f7f8a4a3fb47ef2a146c0ee974afee5315c00fdfc6068d8a74d2683ef467ff3d940e61b70db0f3f7e251d0b92eed88d238d5a9f4a3f	\\x000000010000000173a9524282a2ff893c1a93d7a4f26732044b89e74f8a74cfa2b070983013673c9f537c6f6cbcd1d1269aef0c163a195ae9af21c450ca77012b21c137e0ea5c5730cd57b91c5aa3b483812b926957c72276023532638e3d52e4efdebafb91d97395d8d75e983858795f6a5732a2b4cd1de4b18375416d9d0e454889814e3b027e	\\x0000000100010000
38	4	1	\\xf206acbac80ea0877c3b9d85e0e983006b74186e44703c738a75a324bcf36b3d9aa7aa2d3affaaf58b74e54233fa2df987497aa6f3eea1fef27573585e545f07	318	\\x00000001000001006bc49cd832181da416fff3565a9bece81c7b045f4a90937a6d86afddd17401aed4455072143574e8419e2255735e78ab1b4f3299a851f64d029361f55aa9684e58fb0fa6fc4ae6c37f7e9939cbef777d0f40ef50ed88cf8f7546ac72efeba95d3ade0625bd38311a4937f0545436946092db55458a3895989df5026fa04459cb	\\x5f6aacef1a74e2fa9cfa9f35471a7c4f72c605fe4b9e3a20831020a598ae8af0bcdf2304c4d2289c95fe44b184a418976e4c74fb36d40bae30bd785aaa019d69	\\x0000000100000001a8bab9222653d21dfcf8bd8dd4ebc21a2953785018c5a853c6ae38017b57a03e354b69cdfd648f959e3e41a7e5950786510ef9469966159f79a12186bd57c685c1bfc15747d05e1b612907ea15c6c51ead6c4a813da73fa68724799ab6e6e74fe02e012a78129aa928aebd1b83aebf281d96744d4f04806bbc26a69dd158d180	\\x0000000100010000
39	4	2	\\x0a8c04fb7b6bb46489c2f55878280a31eadb9055e8c1aa80b1314823309b18677485c4a9fb761107b857fabd3c0beabb09b3420854f67709a85b97dce3985303	318	\\x00000001000001001d3436020db16fff5d0a577c0e1b3d989c74fc32b858ca5f426a9b59221ef2101bdc106498ed1baa7cfb625c740f9511fe059c5a8c912af114b89657344442e360c5642da3870ee35beaaf57b61cf7d0f9ff5c8c06b8892a0edb2dbfccd5d09c1ad58b43f63330fd52fef1f2ae1abc759deba40c094a1097168a41a3e9126ec4	\\xd082bdb42fc33b2653a27e5940005990051d4947e9af8bdeeb4030aeeb79751e15abeb197c0ac3caba407a68ce24fa800262588e73e73e1d976c7e2a71bc665a	\\x000000010000000126accef3c9348297732b713964ced0328577f17cce2b936c7eb7031c1e2120d21355c1aecabcf88c4ce74fa8dcfc5114abe8746ebdbb2193c7e5d9c375760baf64ab35346db85de0873e9e3431e2358aa7a1a73646d2c69e10ad8b48e27d740497149e02f35d71d9eac6190b11e0fcab2193aaeacefb9c1515dda67b8be81186	\\x0000000100010000
40	4	3	\\xdbcba10466a08c87065ad1319b9eaeeecc973f81132bfcca6177309029c52f713505f88e54941830b1a12484c49f4ee1f181c8a305aeea59d076b9ad21e93d03	318	\\x000000010000010065e337ab48eac32827cae153b93020972c0af932ffe68b74eb83c259692d0028b1ef04b1f7e97ba1bd8094fb519d3104d51b1b334fb44a009f6db8e12d55b2ce1439961469d059be14c9eef2f87899c67e0731c6e25d5f8b66f13bc3e7dc5a0858e58bfcf2cdc0186d81c306043ad6d4db912ff3201eaeb5831b14ffa3948a94	\\xd039ceb3e1d6233521f084112094430ddd5accc852d7b7c7ea747cc023f9dbbb51ee524d2c7cb2f349163516bf1fa00d589e5795ce5b67bfe957ac663ee6876c	\\x00000001000000013f7e5b2cb4b8badf0b768671376cf9c185473d767c1c9fe0d8c18b44b7da4037f96f7566f1f3bfdbe708cc7c440e5cb0c295d63ffd86b528ec9cc9bdea0cf423fb85f422827cceb31f333fc90b220e6944d750c0692e70eb4a64fee0e286a82a7738863d68f460c35b1c22c4045bcb3db9f09cb0707bfe0193604f5dfd0b2f58	\\x0000000100010000
41	4	4	\\x59061b8043675354aa839cfd3c3ba9c0ce5fbc611e1d9f5b48289255f66d1ae670e9e8962d7b434be3f10be32821e4a8862c99565e2b0c2a0b399b4971f4c404	318	\\x0000000100000100c4df7cae289c8a2734286b69f981e22d0ab3954cedb0b3cb066728ef406f884d6750cef57f2ee18da4b909b9398abc98f743b740c07e035ba4357a9899769ee438f32854c33d93dc4cf4515f174cbccc9fbada30bc141044e1ac246a3ac70aaf9c28f94b004112ed143d39142dc1a43967e801dd552381d647f84432a59236c2	\\x3152f404f23fe719575f3b8970bea2644ac8d1fa7bb383cdecab98f7579f2d26e72a4b535cf90ce6b87ba5124182f5b7e5dccdd5ff9338e3b859250e207837d8	\\x00000001000000017139811a97d97c3a17de56bf59585958f3bd63c77be348161cc10e7942c34b297523f7b2c649c5e8a048ba40cb322c4650450b532282781b457090814cf28d1ae97fa4732f440e74a4103ec7003d5442c094e76f4f5b72bec4d60234c1d899bc2ba3f32e4c03f4a27ca0c5265c34875bc5ca5993abcb196a87a439483176488e	\\x0000000100010000
42	4	5	\\x9795f44214b3100fa05c16f2d43e52c839a257f43f26a6ba5968ba790c579d61fcb989b28065b65552d75385d1c50a22435f5ffba1bc7bd823a3be22093d9606	318	\\x00000001000001001357b89c90777e2e9749c1dada3d062a3f192d8ac0d8be2eecadf12722945dcccf6776ac86766ebf5c4f1bd9cd3c28c224616f1a5b141e94ada3d5f7c3e9cc4c7a9161cd5a68fbd17536c82032eb68c49bf711c97a9104bcea93fbe978175528341b7f88a7b30f59d452895b02193fc1c440cac786f97e7c70487f8386221237	\\xf62b6ebfcbd6a84549a985dba96eba7319c489ee53372106ba9ce36c2068db4b2448ff0d5615217d97040457dda45a81666b4899a5ce8fbe549818be5f02c87b	\\x000000010000000115ce335e5e841640b5e1982f761a2e2edae2b5498a761796b5930c8182f92fbd22c1b478a8bf8df3b55ddd49f12af8af9453c6a85e7c1e0852f179ace701302bca26bdd1ff74cbc05b7ca191837dd1195a3a08eaadd41e151431e735ff8b229964452092ef0ad8d347ea37047ac106626ddc5504d026ec1d3b1f1acca8ae4c53	\\x0000000100010000
43	4	6	\\x67156f7dc63edb6cc1f652b861c4c78b0408c11e4d7114fb640a7ad2fdd2ba6d10c71bddb8d1e3f05490c9136dcc5856727b6be615dd318cea3040c9b29dde0b	318	\\x00000001000001007d0f285db60473ba312068d2e884ffebcd713c725b1f379b01a2827cc46f695d40ae9f10dc38f3046b25d3a7a515961c28641526495186873cf09ada8d544a7009bef65d09cafa56553417752d05c62d832bc500d7df74af2204784ea1bbbfb3ced6da8e1923dfed3da3ecfa07c02c85858a82309a00ab21db5477d33fb6a202	\\x316092a87b8f047ea4921e2f02086e5eb768e0ab7faffbb9efa5b52e43c603ecd73fd1a57cdcd39a5db064a3664e8691a6907ced8ed1b8b76de0a9e8d8f2a36b	\\x000000010000000103a53ae196b14a3c167a6ce27f7b376ac79e11a9c41d9dd457117ef33c53dc377bc3ab0138121183968cb5558e7ab1acc932c75c392ede95a6d4ec8a223ef16c2ac05f40cd325981e04132db3387e6c312cf490a2c7f241cfd467a92987b27a8c28770ed74bbe8d4f0cdfc202f7a1ae4796a8d9259c674387fcda42c74d68e68	\\x0000000100010000
44	4	7	\\xeb9d835f5e74e62b57887c9387be4f162383261889d661620283c979c9fc18fdeda1f360f0bd077c0da144b7575242f9f97a46b8efdf7e41a2ee5bfc6772d703	318	\\x000000010000010056ab973aea7092ed8dbab2208527dfacb878ba30a64431724e08984f86c768f725a4e897ce183158c6dbf4667f1113afcc64636ee054fe0ec44ce7e0faf183b178031a26bc018a7ed010db43deb58d3bc9db22f5568f450f651ec650391479b7f3a8e6b6daf315611db906d52e007e3193445b696a3795c6eb8b5cb9a714ca6e	\\x22ce8eb4dcc17d704d4a3d93e500b1ace87b3a0f293574cf0aa0aff604c947d42176e01fee9eb70e50c305383b1210db910286e3117497eeb7b55b978fca20a4	\\x000000010000000154bf0cc6e6bacaa25f8b07c66b3d05492dad8cc2bc056fb7e81a4f1c001a05a730544ebf7824d8b23ca5c756562f235166a66a29692856dfb93f205646f6ae60ae7183704d6f8ec548ac03858974aa77760c66b77385aaaadb30ba318726d4bdd5a2cdab28a2001d80a4af66b6015703da52073375af25e60284ce9566819748	\\x0000000100010000
45	4	8	\\x4db6ff15792b9d13531cbdf37e7d1e3245f4e9c82e64f840419a9b316cd178b1f39786e7f2364ed495d570f21bc7888f5628f617f5d8938b009140a1348ec00b	318	\\x0000000100000100ca35435fa91fda28b6c23021e706c25e0ab5c6b4d67d102d4f1e20285b4e283997c5d6215fc41951f64d6fb0930ae893d6e7a12267ebcec02d9732ca9fdf4475ae001840799b0d92b802ab3830784077c013d0d1d259cb70a9490a7746d156533c0d970ffcccc41f11e0abde7b888aced5597c29f75fdb8d1ec29739c0e57c24	\\x3f44589feecbe9b0b0a42c5a417b72261ea25ed1e002cd894e46ec8da6b2324043353bb25bb619016e3a365633712e7b4adeea8a93a4e48d39c1d6ec9e397e20	\\x00000001000000017bf9b0623db85de236d6620d691673195cd5922ecf9cbcd6f894b04128a44334658c1e60b0194036601707d32dc6b44e150cc77bdac4d9a2b9e912d2d524e57370063267a39cf4946d992e51037e656d5047ba7f160ce4f8d675812eb05123187a7a0dec9acad7ce9c1e7926711b2ffc3c5078281bc58a1bfd225bdbf483dc8e	\\x0000000100010000
46	4	9	\\x44bbb9c86af62e263d72a786ae123babce77cc9aa9308572dc421eacab2707abbefc89847c5a4c9dce7306352b24c659a24a1dd55a4ee6d2f10520e29c765704	184	\\x0000000100000100188f8844abf125c47ddcc8b1ab4b90978d2473b32af746023cae922324e56c4acf3588c5e03e9403ab7fd9f50140d6dd27f78bd97404b001939c878de24f96f6febe37dcbb56367c0f4460df1cbc412d22890f1bded132e18363c628e70399410cf2a138fe4e5a4c3edbe8a51be587a907c2c13cdf902a56978bf954169fe57b	\\x1e7ee0224b36f51589372130c8a54955a27ac5f352c3efc11e463dbd4a8b4eb5062a37523281644d1513ce135304d0d8d00243cdec71fe0bb74dbd57b62696b5	\\x00000001000000012ae05d6fe7a8af9fe88427f007c8e71555bad1a6e0d1a502d6940b6476c61042a0ea3fad8f76f78a45d87984b4d6d222a5d79d3e29f8d25dabe5790710ded07ff065f99f8b57c45e3c80691d2d60695f63672774993392b6238212b561a9f70649a1c1f193d1bed1afa67c875d62583f310179781d72b0dddc3f87a21d74f9b8	\\x0000000100010000
47	4	10	\\xa053a5ad9990a680aac15a4238fbd76644f0b7ded4f42d4b0d9f77e9920785633c18ccab6120bcfd225b6b18c015aa201e398847e62bec67af62e4f663769a06	184	\\x0000000100000100a53552f236eca4c674c1a9bc1334e4cac23d7c633928bb108e365ca900343a70e2c205bd1bf58f01a285daa4347e01d7774d7ae152c8664813274d7b9c84245c7a75f1805eb47df622dd215ae26b062e1ca41ed3a3bcf94d800ecc4b3cdadc51d6f3b78841b7703102fcc91ee5f013ad8c2c11b1586a7f515c9c112bfade1eea	\\xa92164d289ecac2b7184c9674ec35e917378533c9de485ec40a6fc89fe52c0311e320b3f26e720789b9addd25d67e7822b287ceb6bdebc05620f67a55c505ca5	\\x00000001000000012d032df8bd0bac7f5998e8d2ab8512c1ecfb09f1f648c311ed07e5741d61f31869a426a9cd6b75e6037c6aeff6bf65b4f3494b884d49cfba4fbfdacee540421199d7bcb4d3a4dd8dc24f26a6df071b34dde8bd3856c36fbff18290d100183d736816df929c7a1ad6eb3c3be89139b70ff894d5e7ee66ef683075b22815ce4413	\\x0000000100010000
48	4	11	\\x2de889f155135acba8915c04d133a754117e67604d6a523d6f82fdc5ae0748a50218fe09ce1f07a41377dc24f06683cef645230aa0a674d84ea19683300acd01	184	\\x0000000100000100aaead189f51c72f1e2b19152a06d2c0a04d0c8a2bd2168b386971adbec87277708cd46e250c51a371a8348d401ec6c2912b37c9501b36479395f13a97eb03bb8fe70655d6c4a22f3443899f15956cad53cad9037751f6cceb9c8a1ca66e7846bfafd0465f311544196dae255b5901ceb71baa46eb9f0feb99d570ae5c7985efe	\\x796b7c740196b921945053dafeca54e17aaf8e64caf359476e3b49c609723f12937022f85a2746484a30004cdd6df972fe7faca43c07d540ea092863e54be1a8	\\x000000010000000183398b504b23d5cf0cb2b63d0a2750d017664cb022a5fe70d977ff0e51b7d4928012f98814fd0a4bc33d7112fbf12529adf5d322d9deaec67472edd0168cc2e0546bfef588d6319bacb4950cb435ea0b06af82e763af3a2a6089d44ccd46fad8e827bdcc5e7213127f83d2341d8c507cfaa2b993b6f6bb39a36da7758fc48409	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xe6bf2bef3c3149b35008fb09a607100cd50d4f67a57935a07c82c34c30029717	\\xdfb476c06fc51b146b52c9645c2b0a71b0ac88050ada26b47476e73ec0960099f8eade4d6b008e19ed4c393759f327e513ce7ab63ce0a52436fd4725cc2f4620
2	2	\\xedb3c7551d6b9d83a241b872066662848ea47591009231cb6bc6a65348623465	\\xacb3e1c6cd132d2276676c73748e8d77535e7c8e7ba0fc312fc55275e67e5d20965c8f369e6b650491002958baeb4390cbe092069e882002b2901c7562bc84ab
3	3	\\x7d03095994a925bfdab9ba7a46d24e21ba5374e5cd54515fef7bc4506f8c8e2e	\\x42a167ca3ed3d6206a7cc6270995f25c625911a0dba402cfd81ef868f0549c54dd3b55f409d39f039f7a3e64d8c920f49495ec0790ea12d3399bd17ca8b92666
4	4	\\xd768addabb258b7f7176f0ff10bc43abb386ea10756b140a791ab56bf5245d05	\\xdba5c76bb5d809ac8ec66ea72b58f6829c97b4c869a4a5cf190f574333b10eb4be0bca77f8d21b439ba2114fc806a77fae36917f4765bcab1377ed637046ae14
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	2	\\x0d6dabc2f73488a99fe1b94b2ef511906fe00f59f1fbebf0b30f7c4aef25e8b0ead1fa3e2478bc221b47befe5c289c061fbaaff3c3b04c3b5f9752969b6db808	1	6	0
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
1	\\x4207124cefe0f02b6f5c4508f04a6be62a3d6c3b13f9903738ff300ae567f3df	0	1000000	0	0	f	f	120	1662293303000000	1880626105000000
6	\\xc2eddfe7d616ac549ab6225297ee8917e52856b31d683ef312ac9f55d3e5abc4	0	1000000	0	0	f	f	120	1662293312000000	1880626113000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x4207124cefe0f02b6f5c4508f04a6be62a3d6c3b13f9903738ff300ae567f3df	1	10	0	\\x27dcb2bbb3aede071f468b77e2fbc34d812ed2d6fc95b769bfd9b21d26243304	exchange-account-1	1659874103000000
6	\\xc2eddfe7d616ac549ab6225297ee8917e52856b31d683ef312ac9f55d3e5abc4	2	18	0	\\x15ffc87e7822e9a7e8099de6187cb80b29262d7300784d44f1a0326b82b95257	exchange-account-1	1659874112000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x16c904f7e8ac0de27be7c4684ffe87488eb8b72af69b580a28c56f20df59487e7ded9024c4a217b89efb3ec61b329266df03d72a1f9482de9135cc461f0d4f08
1	\\xf5d4a35c5959d63101cfd424d9c6d074e8fdc6be777d9199ce82bd5590238d2c1140b76db6e256f441055218faa3a1ee2358b16dff62b916718781c8ba839165
1	\\x3ea3d3a3b04a77da3e33bc6d246ab759e8c509c67712ca4c4a5b2ddf4c73d34e2cea84d5ad7263f4f31971622c2ffd7b66e8cbfca3a8328d422a0a52586164da
1	\\xab09a693fb611a7713017216ce71db0f8b6ffae4b07851924b1315fc4dca080ddbe9e021b485f80e9dc6ceb4a005debc09618eede5c3bb1ca1369533c74495f5
1	\\x4f127be0067ca364f826f63e450e169c9b87dbb8ade03ea971c030453378723511255317cad4bd6f2d6e0e6651869830170fe2be5afca6e2f49c295203d536e9
1	\\xf62f657eba253836d49e51c013610d2df74a8ddb97a6bb21deb7c9037554e4d6fd2fc9e407e579826ab3cf40fce1065a2dad0f14383b0d5eda6bb01f924e27d7
1	\\x4a5fd017c3c7fe7d6029a7595f3769b8850541319fd4e7b03bee58ff811fd438eb56f2f53cc3b685931d5427320164f9afa6c3b7d25ff47d15d5853a606c1248
1	\\xbc67c57da095af0c12c98954ea5b5cb58518b29d3adec96edb3eb826556eed22d4d63b43bd7c11fed778d1485bcdcdcda0e9156abf8cb208c61f66fb451416bb
1	\\xb021406bd13d4ddc4ed78f16b5e51e7de7135d8e09114db5f26320e896a7125c0d8f4cede85dc115a4cdedc1e6a9086fe075bf093c25e8aba012fdb7dc057048
1	\\xf06047d4cbe4b482a2d1807560e64b99ff86b84c5b8bbe6394ba6087050579e5ad4ae2f3e887f70255a3b2c259d9264b4f5b7f6e726527fe9b7f0ec060ca4a27
1	\\xcfb03e3f4a73fca58a6d73e4f428f7108362e781f2e347d07558362f87fe7768912bd5d63a833ab7d4b26c2320c5a6219dec6e5474eb4b7acfc271bafd388b94
1	\\x3ba53721a4d5c1dfe93e48ff4ac0cd630f439b9ca3e614657406d952f5603b11e2da9a514fcc32018acc22f10607f3136c21f453daee45f96a933f902cd45047
6	\\x105f4224853882c7348b93a4588fd8899329a59258e5d053e32a6948a2c76687896534a18fd48d9b5bf76e2b5bcba2a82db0970e582bc138121daac8328c18b0
6	\\x382893891d28f6ef885a44d917efd17fe420c30783a4e03d80ecc8b7488ec34d91e89cb4469b12d6e35173b78950a20cecd3bd09dee70c17879d55e829c64162
6	\\x5afe63cb0ec812f54d4cd0c59c1c5d08789b53240f716af7e38f3c44ced9bbc3592fd7c01d7b7ac50c0ed8369edfb576d089bad350fa4afe1f756d2d2baa8e63
6	\\x5bbd71e63a545ef40ad43db8549f9c042b7d812f6cc4ece2c785d5508c48cbf4886f90f5e5b516b2f5c751931658a837f2fecc54f454d70756fa8e65b5fbdeea
6	\\x6efea9e8fba4809418b825cfe57070b639885c8d3e6b8269494c1cdd1d404beb83852a37865db27904f80b893ab833fc8c341da233bc877388172e7b571d7aa5
6	\\x11cb79290b486c438b0040ec6f6b4b788911ddef5677cfe47f67e3ccb41fec52fb5b6e2110ba18910369b19d63652c1f1e4d3f2e3cdcd939f4ebb9383a48393b
6	\\x03c5eafec3eee0f10d20d83f83b77baea7be271f37a25b134652ab8926c5d9187929ef84044609142a5502a84520761c6d78f9b66093c0f1444af235c0a89bc0
6	\\x4935c53bf73860aa927822c784d9e46f5670b8e8dd6e01ad1c45ab76926be9afefbeb577b131793bcf31cdd474c3ab2ffaf86329ed9ee538c0d9aa77d5f34ca5
6	\\xcbac7363fedec522dfc9a4963b22ef23d6fb603e76b87c9a2e19554e140e6177bb08bae1955b8d1279035437e946f03db0fed29e4d48fce2d2465dc2f1004820
6	\\xe76fed9035ff19a651a55ecf94c21762189e193d6778383644c97ea28e0806bd6d2d34f19c75d98e1447078b1bc15f63d2427b6592b5a1d65d468a60f31e3fa8
6	\\xb4f744a0be574becdffa71ea703cb3e2648bfee39bf2067d703b03cf3bd9cf73c7cd113d5e0828cf13052dd3d22fc775baac3573243945c58a4c4846f5f83b02
6	\\x65d5c7847e1e84e75810e1bd8aa24ad40054778103d383ff8d12609ba4156b1a8656aae119723ec9262dfd87a2ac220fb9545a5da3c5a164bd5a57d0cc4d2c1a
6	\\xefb234ae971f07440cbd526f1a3bb3870db66c303a646380a4556ed29da351fc904341b06e4a9d6fc1efb381fd80c9f568ad4ea9d344e720d6c4fdc518d7df22
6	\\x600b1684e0a3b722da29f4f87bdfe83a36e40ad5d6137583bc78f8f9989e9621dbc5bc2df1a6ecc2938857535e4a892e511f911786eab6fb1965221a6017e37c
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x16c904f7e8ac0de27be7c4684ffe87488eb8b72af69b580a28c56f20df59487e7ded9024c4a217b89efb3ec61b329266df03d72a1f9482de9135cc461f0d4f08	247	\\x000000010000000111c97bb0b2761478579b33ce560dc0706592ad11de19e42d55eab6b52d5f729a12684eeb9bbc91b2d6a8d6de2db48790f53e42e11dc787758b206628b1c6e5997d7947f856fc3a774e7429dc1264a2e09fa7d2a07f036464e97d8b584a3054244170a5419b20035b39b639af5df3c819ea45a917696be51cb0a0c5dbcdd63f1c	1	\\x948ae8168b11340ef78dff6f4fde8ac4bbdd1982be1004b76c8e7eafad78d02664b845effe05a07fb8e0b637210fcf4071400a90ce696e0b7afd2b4f2b73d705	1659874105000000	8	5000000
2	\\xf5d4a35c5959d63101cfd424d9c6d074e8fdc6be777d9199ce82bd5590238d2c1140b76db6e256f441055218faa3a1ee2358b16dff62b916718781c8ba839165	269	\\x0000000100000001ccf91c6e3c3497f277c9e14084bdd0df982f2ec030173067ce0a2f7a0a2328bf678d6362b84497b3933e6618e2a197b7fd3a4a6457f0e37b089dda78db442291c86829fdd53c780cd13745c9da34750cae95846cfa9e4a5875e14d3cebe4798ef056d8c17b4cb56a2955a8caea7d0cff16b35bd6b7225d84764ab01725020e21	1	\\x07b2e5c37fea409d348c1fda9767926f72cd44be07596e401ba6d0362a741711e3635618cfa768c14bb2934a123152feeedd65a499c7f07dfffa61d3436f020b	1659874105000000	1	2000000
3	\\x3ea3d3a3b04a77da3e33bc6d246ab759e8c509c67712ca4c4a5b2ddf4c73d34e2cea84d5ad7263f4f31971622c2ffd7b66e8cbfca3a8328d422a0a52586164da	318	\\x00000001000000016324dce1bcb6f9197b6f9bb61bcc8f27033288f39903c0837335cb711c82e2453cac326f7bc8875c1c72661349494dc319b3798e54cfade7240c1ccb3e20f7dfa343c98ea3c2ff37f8f4be6383f56f74822a0fb6468113b6c116aa7c68b01732f4aaca040c16049b2bdaa8651caf9e93776657869cdd12957cd20dca8f802b3b	1	\\x57cc76f30e96634417a80ff5ea626ecf0956bba3e6e259b52be908b018be9a66db829c0d1cb99f2b1e617c10974b1e1e176e861ad74805cf586616fd0abfae06	1659874105000000	0	11000000
4	\\xab09a693fb611a7713017216ce71db0f8b6ffae4b07851924b1315fc4dca080ddbe9e021b485f80e9dc6ceb4a005debc09618eede5c3bb1ca1369533c74495f5	318	\\x000000010000000162adbd6af37d89483f18cacc9ab6e10756a97248aa8a2f056beecf1fe9a2fb0e7d6ad778402e6d9a23e2d24dd9f3833be03c7afd7448abe400dfecbcb1a9c30f943051834ed3ef98c8a6da6eec728fe40ddda685df772d5c518e21112890c846b676c376eea576afbeee1cfd74b9d4efa9029b859bed5ffd25a737897c8e5eb9	1	\\x94bdfba35e55c625a0cfe70633b84719087299bf4edf4adc71b6223e092bca71411953bd6cf39d274d2ce047f83a0d81f7a34609badeaa635a3f7e0144dbdd0b	1659874105000000	0	11000000
5	\\x4f127be0067ca364f826f63e450e169c9b87dbb8ade03ea971c030453378723511255317cad4bd6f2d6e0e6651869830170fe2be5afca6e2f49c295203d536e9	318	\\x0000000100000001baf444e4d5e2159a6bb7549225382abc9eeb86c5c6c6e66aed6f01f9c4bfd67cc4a355aa0e85c4243743b97ac73ae2f4072a15a2e44c00c8b287be56089c3fcf1106aa489abe5d86b86402e53c19f16ca035a9c1e2e79d615ebfe56040fef3740b7243ec7bbe81ee7be4b95e8bf57b4db09e3979aff703cf21419f811f4c6d83	1	\\x83a89c68f7b57f57d1baeb116e9c01bd89e3b615db277706465a70cfe948a14ee7b58cbee03bdf99b0104b578873ecd820d073cee0a14403f374acdff41acb06	1659874105000000	0	11000000
6	\\xf62f657eba253836d49e51c013610d2df74a8ddb97a6bb21deb7c9037554e4d6fd2fc9e407e579826ab3cf40fce1065a2dad0f14383b0d5eda6bb01f924e27d7	318	\\x000000010000000173dcbe84c0b58c8f270de7997cbf7e215cc72701c6fbf2311054874c612cbe9e64c000ee903355463b4165404506826a60b1154bb5bc025fe13a5824699bd7ec99966f80a943a02c695501275e0b6dc9b4e4176233beb7eb9998cb7f8cc8e662c1c71e06c133ac55b6a882abe845f036de6e4da3848b1eaa9308a4ac089c7ca2	1	\\x9ad2d047712472ba9569e13f3a0a219aa09d30f66b847a3800078f8aa5903838e01e0e119ea9ce0710dc587a0a6735e30f28d472d3a325b2f45f8ea21761760c	1659874105000000	0	11000000
7	\\x4a5fd017c3c7fe7d6029a7595f3769b8850541319fd4e7b03bee58ff811fd438eb56f2f53cc3b685931d5427320164f9afa6c3b7d25ff47d15d5853a606c1248	318	\\x000000010000000173dc9cf97154b92f7205e75554edafdca44866a9511064a2198f3863ed2e25dc90a6790945d694a25cd3680171cd123f5a09dd1a51938307b8f2f29352dcadf5f707d7d1c4b8499f9e4b14b2da95f58d323ee78c58ed79fe05a7730d2ff892b20200217744bf647344cfbb2d7fb1e9678f6248f83d99172b135c04f40534b9cc	1	\\xe6bb9baead5714445b08e5e8547fc6418b6600a9a2c02292d7a5d06883f591f0b6e12fac24f8089204565a63f20886380bc464dce97fa2377239dad70acf9b05	1659874105000000	0	11000000
8	\\xbc67c57da095af0c12c98954ea5b5cb58518b29d3adec96edb3eb826556eed22d4d63b43bd7c11fed778d1485bcdcdcda0e9156abf8cb208c61f66fb451416bb	318	\\x00000001000000012ab3e0ff2672dee2921794628be2e500249da46ea2fb2368648b6488e7db83b26d6231518ba68172b4513f49bc609b7ec2137f77a8cf35b2dc1340fc45774776332269f17f4457e41de0844e6040fc51c5b8a01c3563f6c61e73951227d5c705697a3b90abf7aa27563ebdaea3edcaf7e9d069c0ad4de5a809d8334ec357bfd3	1	\\x9eb15a689a13d0e782581e0527b2fcc88ebd955494bffd2e797c7a85c3951c9415bb278d274ecc35bef1c4da72f55b7f47fbe28dd4821a0d25cf39a33dae5205	1659874105000000	0	11000000
9	\\xb021406bd13d4ddc4ed78f16b5e51e7de7135d8e09114db5f26320e896a7125c0d8f4cede85dc115a4cdedc1e6a9086fe075bf093c25e8aba012fdb7dc057048	318	\\x000000010000000154af93e551366edc9f8a3832af38f3911df344add9cf7588262b0f9c9c87e0935c15b5d41b100673d2c807b8eeb5b3ff3d736bc08ea06c7b7452c446f4b6cb8eb558d544d61be7c3cc71d8007e0bc780c9e1dfaf51aea210018dfb219b47bfbe3b4dfd030205e25343cac820ecaf44831df42b34e6e40f2644463be387a09df4	1	\\xa082a04b50c67c0c57d3791bd679c75f22594753de8900f62a1daaadf4e8119acc51c051bb1f26aa210b8e3ae785029366c5c9da68f30ef09bd64c4586a5010f	1659874105000000	0	11000000
10	\\xf06047d4cbe4b482a2d1807560e64b99ff86b84c5b8bbe6394ba6087050579e5ad4ae2f3e887f70255a3b2c259d9264b4f5b7f6e726527fe9b7f0ec060ca4a27	318	\\x0000000100000001231b0f59bc7cfb3acbd8bb82fc17759e7814ba359e052fa3b67d6355bc29824e618d7a5f6251021ab1e3b895f80054896dffffacfc43906e6d7b7f39ca6befc051eaee9ef319941504e3136e2ef2c1b94e5675c57fb1dd461a059dedbc901b4c38cb873958ed2699a86feae3057b3f4c16e9ce1c1ec4dd147295841e55d34f93	1	\\xd0ca8f7e8c87a0de7cafa7d45686ccb73744ffd96aed16f0ddb9d8603568a3bf2dc21add78d38fcba8ff8bf9fce81707b8ba1b1744914f983ee65c1ee62b4d0c	1659874105000000	0	11000000
11	\\xcfb03e3f4a73fca58a6d73e4f428f7108362e781f2e347d07558362f87fe7768912bd5d63a833ab7d4b26c2320c5a6219dec6e5474eb4b7acfc271bafd388b94	184	\\x000000010000000114e26954f3bab857d3d2973137ca9d3c6f7a990dbe5f62839f609cce9e41e62da69cc4fc6ce980d37ff70e25ba5f905c5cbd5971a330824924fe294aaf28c651afb43e3ad61246017daffb66e83e2edcb54734b9c5922485b686a7352d47893357327d62156ce34a6d38d024aa26df5c426e9c0977104476ba5bb6a75080be08	1	\\xb2936304fba6222284592a0aee3e1e19bb500b1a8d99f3eddbb7673e327f96f435261c687cd7e8d432d64f25f01f3791322e1abe55932d3380421d8e6c5aab0e	1659874105000000	0	2000000
12	\\x3ba53721a4d5c1dfe93e48ff4ac0cd630f439b9ca3e614657406d952f5603b11e2da9a514fcc32018acc22f10607f3136c21f453daee45f96a933f902cd45047	184	\\x0000000100000001282e920757d38775f146e16e64c09c5286b9ba0ee94a64b1276ffbcd5495a3d0499d2f9c69ac5382b09c8b7fa95ff5443979a0391f48f9ac8ca5e05a424257b8a320302db949dba7b7d1334249b374c9783d5a685412a6435a785e3f37ca7b809eebe3eb3a8e3a9b66f8aae75a06ece4ccee8b2986419f8f3501024c0fc07f2f	1	\\xcc652e15c11ae65db6e141b3091acf3c9c93ea6f3af9b62c629533f4e6f23cb0b12eb871c91bc1fa523797dd50d660c4ac4d237a462dfd15ae1dc026c839890e	1659874105000000	0	2000000
13	\\x105f4224853882c7348b93a4588fd8899329a59258e5d053e32a6948a2c76687896534a18fd48d9b5bf76e2b5bcba2a82db0970e582bc138121daac8328c18b0	127	\\x0000000100000001936ac6a401a3874057246a6de070811bd6bbb6d25f328d4911ea36046691b4d6c1186525ffd0c25acdcade182bf03aa26402cd223735cc05371cdb8fe896b40bc4a61797d545eefbd1f79e13155b68bb6aeb4eb2aafc80b733ea0bad0e0e4c70d91c56600e776e016cd34c1d347a540e184f9d3e0f74a4530eea08d50944a3cf	6	\\xa404cfee75adffcd789553323b0badc306117d0a9df6270dca55e1b675cecffa42f605353198954dc6c96c88b3d8b3ecd3efcac9be72c90a8a4db365f60a8109	1659874113000000	10	1000000
14	\\x382893891d28f6ef885a44d917efd17fe420c30783a4e03d80ecc8b7488ec34d91e89cb4469b12d6e35173b78950a20cecd3bd09dee70c17879d55e829c64162	415	\\x00000001000000018afe85ce7654dfdafb5942a421e2a25314fa83f429cb20d563858ad56cbe43df77e6c14d4a856505bebc98151ad16d7c2487f36ec7dce38d14d5151c0d9870c09e41a070c8f424bc2bca8b2ed94109eacea5645a621eeecbe2f32139c2c99f278612d4466150ffa971bcefbc5eb6c8702d73c3f509b97005a619d375b4de6d08	6	\\x292d86e121b4eacc5fb9e857d7a6a0e69bc06227aae1624137950d54546be081a44019db02e2c553da3cb13cb120757dd166635164c769b76d389b437c994b0e	1659874113000000	5	1000000
15	\\x5afe63cb0ec812f54d4cd0c59c1c5d08789b53240f716af7e38f3c44ced9bbc3592fd7c01d7b7ac50c0ed8369edfb576d089bad350fa4afe1f756d2d2baa8e63	296	\\x0000000100000001806f059b6fa75c5be93e7ccc0d49cf16253f4e8b0d0ff14b5a02f79031d2b9ec1dc2e45371555d4056fffbef88e096d29d3ac0da375510ca66fcda5c90da61e648ba8ca52e38b31a5383c1f4078de6871708b0996b8f2f8db9da42721444725da4362125aa2fcf4cc6390efecb2128a2890101f83765ac3f16771c09339e672b	6	\\x08844dcef0c4ee77d245294289f4ceb2a80e5f6142130986783eaf460a6a4c6fe9fcdc3243ab989cdf1ea8c458e2410f819e4e1f14589199b87cce7a0f239b04	1659874113000000	2	3000000
16	\\x5bbd71e63a545ef40ad43db8549f9c042b7d812f6cc4ece2c785d5508c48cbf4886f90f5e5b516b2f5c751931658a837f2fecc54f454d70756fa8e65b5fbdeea	318	\\x000000010000000140fb6de0cb42579126ae602b66073d87571426b34786a7a697b7b1f549472794d0ef28f236c9d7e0a4a9dbbea4592d67900bd40a841d82ca8a0325d628024c0afc0acd6a6d6181e085d87b7eb06ec804aeeefc7bd6a8565776c97538f47d6ca4c883bab2ae1f9f8f3f697c3c32865b9c1bf1d062f72f0c5fd61fb4a2d4f4f8f6	6	\\x800ae4b3f3020c70f8464193948cd11689be8f202585f0b213fb74992d36b5d3a612de4819e1ec1b4dddeeee74f76c0d24799ef6247bc66e0dabc4e5a3b52a01	1659874113000000	0	11000000
17	\\x6efea9e8fba4809418b825cfe57070b639885c8d3e6b8269494c1cdd1d404beb83852a37865db27904f80b893ab833fc8c341da233bc877388172e7b571d7aa5	318	\\x0000000100000001921d9ce5f60dd80a80809d1e807eb4282108f26be55b9561550b4cc09367026dd29d6b16912d8819f5632c62242a98eb31510313c6c19f77af8056e5da9be53fad0a6b9626184185ad2d1d192b703e7d7c307b0b3eb91b7386025ec9a9c9cf57f7e08c099d87fa03fdbf10cd2c6643836a8ae5d22377392f1a2f5f3db5a92a2b	6	\\x7cc3b5e140947dfc82367159a92f79cd014f82ab0c702b80b17afb14b50ddf95ad37646ff20aa427367e37db6e22ab3fa4030ad7b580011fded2357cfbacc70a	1659874113000000	0	11000000
18	\\x11cb79290b486c438b0040ec6f6b4b788911ddef5677cfe47f67e3ccb41fec52fb5b6e2110ba18910369b19d63652c1f1e4d3f2e3cdcd939f4ebb9383a48393b	318	\\x0000000100000001835afe6a53b7ac2f5cbe1d14817da8b8691544f4cd1f466703fa64ee56c89fafb1c28617e3ac0211683be65e205078b8de4ddee5ffa43f3ae8f565167b5ac83c2fbb92216d5f436134e3cfc85da0ef760e368c09e76b78348bb927932933ba398fa69086da2a7b6fc244c33eac875193b4269c971e1b7c7dda2594224563d40c	6	\\x7d6e655df9ff37944b4718550cba64daaed7af606d813d3054213620ff7582d12a576044dd1df7de57117791686ed55b87a0eccf246bbd6f29b10793c67ced0f	1659874113000000	0	11000000
19	\\x03c5eafec3eee0f10d20d83f83b77baea7be271f37a25b134652ab8926c5d9187929ef84044609142a5502a84520761c6d78f9b66093c0f1444af235c0a89bc0	318	\\x0000000100000001df7523308605ee259fe170fbdfc48d08f167fedd3ae4b50e7ba707d33576124d7a1c7ab2d5a11e2fe4b559b1c9bf43a7e711b0c49087075abd222058b8ec409d833407effa84eb7113afd0ebee1d305303a1fddf2d07f7488f4a73938216db9b6747d9dbb12b2c93d8f84d3759063b0bd676415b34a4c3cbe781b2a4f8e10c3b	6	\\x2c4ba1f2eac716ac697b661c9255ca8e0dcfa8bb974545ab31b54af995a71857a740400b5e50213b073e5053d22ed63dfabfd65ac0ed4671492aedaf15d7d50e	1659874113000000	0	11000000
20	\\x4935c53bf73860aa927822c784d9e46f5670b8e8dd6e01ad1c45ab76926be9afefbeb577b131793bcf31cdd474c3ab2ffaf86329ed9ee538c0d9aa77d5f34ca5	318	\\x0000000100000001de961f06320339f07d9570a3ba92d5f4a34364ba3ce3bc1e80847fffd0aaf052c02c046c2805bd50bbe3f074d37e38c7018b642106afb46f142074fa2b5ef4f20efc6092a6fdfdbe7f655306577a11c36fa5d58c8b79baef33dce60f40ea1dd3a033910a6e218bba298cd4e6eb81cd9713f2457ee204abce9a7978b4103b551f	6	\\x47b24cdde92ed75f35554bae02a61c45cba41ce07813b86ad0b12b44433b4442e7181286355f94dc89821218748f2b888db76c2149e7ef9b474ea24bf2ca7005	1659874113000000	0	11000000
21	\\xcbac7363fedec522dfc9a4963b22ef23d6fb603e76b87c9a2e19554e140e6177bb08bae1955b8d1279035437e946f03db0fed29e4d48fce2d2465dc2f1004820	318	\\x0000000100000001e4edf6245487830f828a06d83ef786b3d49e8432dd0d1d789817d251ed538ebab1f67bf75702df665e982d0315cfc55e67f56cfa4e4835d110a2cb515e39a0f11836da791884ad687fa1c3280427606ab043fed0f806b15a8f7f865849c5e83efbb7ecc8625943b7353ae108df39807ce5e1c4236bd606625c9605e47f98ba19	6	\\xb15c54ac7c25bf9057561d8ddebe883ccb2d2d5f46bbefd78887b613efb77366707533a7e7d0a857d5cff6bd49318d7c930bce29004b838e8d2790b75c7c0800	1659874113000000	0	11000000
22	\\xe76fed9035ff19a651a55ecf94c21762189e193d6778383644c97ea28e0806bd6d2d34f19c75d98e1447078b1bc15f63d2427b6592b5a1d65d468a60f31e3fa8	318	\\x00000001000000016e1e054ed60992370cc00c19a9ef5133215d0018585ac36751c471fb668157f21144c9509979ac95306d755ce748e50e9e0d6a52d6c6644b0ca5c66f1bcd021bbbb7382e7bd89e18e12c61257f0d6d9b283e644906ee67c2c89e1586c77b2a3fef177ed15d12d23e5c6c357dbfcacd3122ebd1fa0b3aeef226f4068137871225	6	\\x1038cb0e88e30ae3f087e34add3865e2ccb6cbaef0df93d5fde3d5c408e3570e96afa3ac76fd24beae5e5cf4582307962d908a86c629f83ad8ba07a72612c10e	1659874113000000	0	11000000
23	\\xb4f744a0be574becdffa71ea703cb3e2648bfee39bf2067d703b03cf3bd9cf73c7cd113d5e0828cf13052dd3d22fc775baac3573243945c58a4c4846f5f83b02	318	\\x000000010000000125cf468dec6e5fc85a82e9c1ec6b253274dba89cb5abbf7b6beb7e49726c2ed5eb3177076312be5ee4b726edb3ba3de36a12de0caba451f62747ff4a7da4b052325908d6714ec3a056885d1af625ea9e6548a5697877910520c1463c06010471ea7485580d7e1e2ae70cf096b723ca25bdfa1f5c4c9e957da923ce8425c61ca1	6	\\x041cdb9c168ea38b8c18cd254cc74e2f629247ae4c53e44894744199668ed41c8e29bbd4f553514be4367c383875a38fded0cb958b33f308136cac8ddfa78d05	1659874113000000	0	11000000
24	\\x65d5c7847e1e84e75810e1bd8aa24ad40054778103d383ff8d12609ba4156b1a8656aae119723ec9262dfd87a2ac220fb9545a5da3c5a164bd5a57d0cc4d2c1a	184	\\x00000001000000014f00ca8534ce091b94bd2ceb820d32dfcc3ba324b736a94491c3f793eb0cf0221a89446ce85c6b6781c6a4d8b6d06e35e8c77b7cf824aaa4f0fb4e9bdde381f1ed746e37ebe23ff564eb6bf393b57d6e95ef431bc0491fabc9093dfa78f1a9f284357eb0379a028ec623702d491b59b9b574bc913236263c029489f9b44ab793	6	\\xba1124177b20a52e439ac0615578b81bec3df38d0da12064b1a821a4adf07c718b4794ff3d7c4ce0f6363516a50e192cebaf1f568a86353509b3ee8792648602	1659874113000000	0	2000000
25	\\xefb234ae971f07440cbd526f1a3bb3870db66c303a646380a4556ed29da351fc904341b06e4a9d6fc1efb381fd80c9f568ad4ea9d344e720d6c4fdc518d7df22	184	\\x000000010000000103324962dd70f0e4390bc02879d8c8e6c95362d2ce4d3530db82f74578f43755de5083735d088dcffc6f2a4351a22f1b71e56dd1abe9f79616f372a28b07344d4c99564f2db5ed994df74c8120140956ac88b421732f5900e8387701148c19291ca2cf8b1b5dc7865150adc6fd80a0bf770e94fdec4af31346993c88eb5cd9cf	6	\\xf7d23ed8089635864144b343a1f7185acf009f588b4130abc1deb4dddd34c25b236f42692c80c6232d8a98f3bb80dbc48e88579edf2b4c755b8c120ea93c3c03	1659874113000000	0	2000000
26	\\x600b1684e0a3b722da29f4f87bdfe83a36e40ad5d6137583bc78f8f9989e9621dbc5bc2df1a6ecc2938857535e4a892e511f911786eab6fb1965221a6017e37c	184	\\x00000001000000011a33a92cb56a858e0670306a82ddfbab9d1d4bce3550ad61c82a4040d434505ceb2d8048debc21da4f98d7ce9892487de8bb05291af45f45da1807f837dcb33c857a7c12ba82d26aa8f440ebdb4115a7016693dd5a4b9fe5802902c1993303d8f1b4c0c677685e6d225ae02cc7f35965a109f9a800afbbd68204b567593ed471	6	\\x45b2f37a0a67cf06c2633158dbe8f8d23c9282617d0f891163d6fe00c55c925a438294c4cea379d29cb3a202364c01fcc91483d8031070c1c6eb018f45d26e06	1659874113000000	0	2000000
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
payto://iban/SANDBOXX/DE614691?receiver-name=Exchange+Company	\\x3ec76798e42c6b8aebe84b6333391a5eda9ea7cc422b90d88235e614d9695220350dea5d9e006db225c2294208415ac32b7c516f674ab5f20b210547e9857804	t	1659874096000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x1001eba1462f2c138b9fa40a884f103b5818a9f2dd632b1dee5ebe993ae47aa2b39475faa89ae1ca95b89fa08d4e02f09c3508e73ee064485834ab2bab38d30e
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
1	\\x27dcb2bbb3aede071f468b77e2fbc34d812ed2d6fc95b769bfd9b21d26243304	payto://iban/SANDBOXX/DE390722?receiver-name=Name+unknown	f	\N
2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	f	\N
3	\\x15ffc87e7822e9a7e8099de6187cb80b29262d7300784d44f1a0326b82b95257	payto://iban/SANDBOXX/DE206399?receiver-name=Name+unknown	f	\N
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
1	1	\\xb7f43f0ea9b503c3367c76020afb1b8299828e194b5ecfd16aa1e17222a3e6af6fff4a5e95fb08f8e04de3d158b19101d0eb9c524d9d4e7f8c241b0c9bf22c83	\\xad12bc88a1657e53c9a48a10fceaac10	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.219-00W4ZZ1KKCKZW	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635393837353030357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393837353030357d2c2270726f6475637473223a5b5d2c22685f77697265223a22505a543359334e39504d315736444b57455231304e5952564741435235334753394446435a4d42414d37475134384e33575451505a5a54414254415a5032375257313659374d415250363847334d37424b4839345637414546593632383652434b465332533052222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3231392d303057345a5a314b4b434b5a57222c2274696d657374616d70223a7b22745f73223a313635393837343130357d2c227061795f646561646c696e65223a7b22745f73223a313635393837373730357d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2242563745515456564830363938315245474231455a4b4e4254594b32574d415a5744305344584b39525342564e58504243573947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22594e4d4d475a4630345135544a47324a324330564252595a4d5845584859454330545147515954574b4b52365846594a31514447222c226e6f6e6365223a225735425145523956345736425a56433552595042544d5a465432524d3344354d3646313453413033364730453258334830543947227d	\\xafd8593e0e08e7e53e7546f30db6b09d8e6165e4c46162d195e2441b094c5e22cab5ed010d60902c044ee9664e50755f554f215697b42621caef77310dc3231f	1659874105000000	1659877705000000	1659875005000000	t	f	taler://fulfillment-success/thx		\\x9f66f1dc6a5e8af1c711b147a09181dc
2	1	2022.219-02C91JAH9F4E8	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635393837353031347d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393837353031347d2c2270726f6475637473223a5b5d2c22685f77697265223a22505a543359334e39504d315736444b57455231304e5952564741435235334753394446435a4d42414d37475134384e33575451505a5a54414254415a5032375257313659374d415250363847334d37424b4839345637414546593632383652434b465332533052222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3231392d30324339314a41483946344538222c2274696d657374616d70223a7b22745f73223a313635393837343131347d2c227061795f646561646c696e65223a7b22745f73223a313635393837373731347d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2242563745515456564830363938315245474231455a4b4e4254594b32574d415a5744305344584b39525342564e58504243573947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22594e4d4d475a4630345135544a47324a324330564252595a4d5845584859454330545147515954574b4b52365846594a31514447222c226e6f6e6365223a223545334d4a313353524252393446544648434441465a314a33525a46455739334a58485147575457304746434e4e474741475047227d	\\x19247447150cb7ba71190aacda51e73524b7f6a8f52df0d50397c1cbac0838c9c910498c557ef5a37a6217aaa4461bcd2fca1b1508162b393d147585046af572	1659874114000000	1659877714000000	1659875014000000	t	f	taler://fulfillment-success/thx		\\xb94b61fe0c5855d0214dc37042081d49
3	1	2022.219-02DA4TRP9Q8KA	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635393837353032307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393837353032307d2c2270726f6475637473223a5b5d2c22685f77697265223a22505a543359334e39504d315736444b57455231304e5952564741435235334753394446435a4d42414d37475134384e33575451505a5a54414254415a5032375257313659374d415250363847334d37424b4839345637414546593632383652434b465332533052222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3231392d30324441345452503951384b41222c2274696d657374616d70223a7b22745f73223a313635393837343132307d2c227061795f646561646c696e65223a7b22745f73223a313635393837373732307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2242563745515456564830363938315245474231455a4b4e4254594b32574d415a5744305344584b39525342564e58504243573947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22594e4d4d475a4630345135544a47324a324330564252595a4d5845584859454330545147515954574b4b52365846594a31514447222c226e6f6e6365223a2243315a3356414e47303038374753443256584a41474d43325458514e394d3053414e5454593454315354523232453839474a4547227d	\\x72f7f81b476669f23ad458dfaa7cac2afe371e7b1d49ae6cdb960c732c9dd0e24c3135f4a775acc65205554c6f75d2540f79cdedffc78dbf5d4025e77e5360f9	1659874120000000	1659877720000000	1659875020000000	t	f	taler://fulfillment-success/thx		\\x0aebf3a1dc4f4365f7ca4056f8e77280
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
1	1	1659874107000000	\\xf366195f0b7757993a4e601794eae1f2ce60bd825dc0eabef38717c5ac63b1bd	http://localhost:8081/	4	0	0	2000000	0	4000000	0	7000000	4	\\x184e53bdb81e0efd654d04799e826a5cfb728967ed5c5953380399f0517b8086779997d3dbec9796d5b07b071326a8a2b080aea2ff51696583b09ed2f3eba203	1
2	2	1659874116000000	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	http://localhost:8081/	7	0	0	1000000	0	1000000	0	7000000	4	\\x77aa47cc3c2a704dc27bb65230a43832ab45c713c4110d277074a0867109ddd0b390490b3a554e499e77403e51826ad80c13531fb18c57b37c385e8165610605	1
3	3	1659874122000000	\\x37bb931d1a9f07d32ca8a0fcd212e3ece5c21a3be9d3ed2614d09ee9c05d4737	http://localhost:8081/	3	0	0	1000000	0	1000000	0	7000000	4	\\x3e844d0c640f0fd78c10a28e118bb9f79cdc6d58203a02fac5045db600449d26eb4e2d4e29db178eee8fab620fc5d5c22e20703247decf52d81209e4d7b25f0f	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	\\xc26fe414b1c09972c327e6e0f1c5e70e259e3cb5ac6ce411c550c06d7dea96ed	1688903290000000	1696160890000000	1698580090000000	\\xa2653073086d2b12265597a61fd9148df7fec53fca8ffbd420831cd06784b65415d12553293ec473fe651eb3916c37e0ed0a7b051fd8d3e3d152b578ea2a310d
2	\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	\\xe4025ddebe0401d2c41b93b22c29c1d7199cd7fdbe5953abe29b3fab39ec27b9	1681645990000000	1688903590000000	1691322790000000	\\xdfee77bca0462055e3ab0f5637d491acc443f092eeb662391a4c648b3f8dbfcfbab2ff65258b6fb7e44e1e5537a35ca402930a34095fa7e9382fd1c11394a600
3	\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	\\x0c8567d9bff75495151836cb32f8c055b371af4961ac7491a680789574f166de	1667131390000000	1674388990000000	1676808190000000	\\x48279d4cadd49ba0a1e8449402a80b5cc2cc44ef5c3ab215033d3281530405203c41b33205ac7b2d8680de4ebabc7e36c8b689de4638865de5afc4121d0d9900
4	\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	\\xadfa94939e3c56224320945b7abc0878e9e40e0ed3ae795103b4b8e5d297f1a9	1659874090000000	1667131690000000	1669550890000000	\\xcc863a201633a3b759eb909ddd9f4e6499032853eb8cfde2732f51389135f3b5de2504fbfc8f93161ebd285c677c0a1c0bfaf63b1cf8f6f8801098620f88ad07
5	\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	\\x951e025a80993b821ac4a0cc0b243ecb36329988a87d86a6046f9ef6a25a36e2	1674388690000000	1681646290000000	1684065490000000	\\x14b83b6489bc31bc5e4772a2e2ad14aafe77ea47a29737cdd1f9eccad6c5b6ac11322ebc7a5224c60e19c6fded06eb163d05c6bc76a42158ed6266cd6130b005
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x5eceebeb7b880c94070e82c2efceabd7a62e515fe34196f669c657baf6cb6713	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x1001eba1462f2c138b9fa40a884f103b5818a9f2dd632b1dee5ebe993ae47aa2b39475faa89ae1ca95b89fa08d4e02f09c3508e73ee064485834ab2bab38d30e
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\xf569487de025cba940521301b5e3dfa75dd8f9cc06af0bfb5c9cf06ebfd20ddb	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x03488d99ff9bc09fdca84ba27ece6787c751d0e03eb571f6c953584dac63fab7	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1659874107000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\x46cdeaa81cf7340913d823f78941920325c8729f4394d64ce22a734af8fcf809b8f27725c7303d59f95d4a29e34f9754ede544384833200f317d1a4c2e9a3f01	4
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1659874116000000	\\xa7a0941795eedc2a13e1c7fce572e36a9ebd63266c2b6e437ada36562e670b15	test refund	6	0
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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 12, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 12, true);


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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 5, true);


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

