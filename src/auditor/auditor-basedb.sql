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
exchange-0001	2022-08-11 23:02:26.210551+02	grothoff	{}	{}
merchant-0001	2022-08-11 23:02:27.235168+02	grothoff	{}	{}
merchant-0002	2022-08-11 23:02:27.650659+02	grothoff	{}	{}
auditor-0001	2022-08-11 23:02:27.799589+02	grothoff	{}	{}
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
\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	1660251761000000	1667509361000000	1669928561000000	\\x0760064bb267a248d9c069856a3656fc9e824e3796f5d7cb1747675d5f67a16b	\\x3a1198bc48724c589ce73c4bcf89635166d15d08ec037466bbb1be2aa7e92163babae1e7619803508996c5d089a2479dc2e6651dc89afafb138be4492722660f
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	http://localhost:8081/
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
\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	1	\\x3055636e89f269e560df6e787197f475d0ee80ec7fde580d98ebd494c66a2c7f603d2e8cf3f4b5d7f0119fe35707df4a27e45cd2c32a58aa6f66f7f926b14989	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6000b5d64505986e5fcfd8ae2bac7d726fd1a3232a8746b5501a157876034075f66926a7f9b25ca85cfee7ebb5e5aa0b94b82adda8d0225ae924cfaa9e3f6f7f	1660251778000000	1660252676000000	1660252676000000	3	98000000	\\x34cbdeb37774f40ed3cefcd9686d70bab30c31a9afd4e055c2bfa3c8b8597b7f	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\x2cb1edb394a66583a8eeb50b600c85f4770e9611c8e56db24a7555f34f526af3c6083083c25c7141ec47734fa2a08c6d79b2132b64c0203650c693354b6a4603	\\x0760064bb267a248d9c069856a3656fc9e824e3796f5d7cb1747675d5f67a16b	\\xd001b1acfe7f00001d290dd04c5600007d1975d14c560000da1875d14c560000c01875d14c560000c41875d14c560000109d74d14c5600000000000000000000
\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	2	\\xa5e69e1a65ec203aafa4dec8d8f3670ac54e97dbed5e3a274440d57e5432c1c99191006515c26b11279394f71ce416ee9b1c5ad881411fe0ee84a14ae61bbba3	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6000b5d64505986e5fcfd8ae2bac7d726fd1a3232a8746b5501a157876034075f66926a7f9b25ca85cfee7ebb5e5aa0b94b82adda8d0225ae924cfaa9e3f6f7f	1660251787000000	1660252684000000	1660252684000000	6	99000000	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\xcea9b3a91bf1c73acde5f85eae2af246671add2e146105849c5a0ddba7c6d036381edd6aed5a47a9da945d24878c22c45c78306825b59587b0c2c290d61aeb0f	\\x0760064bb267a248d9c069856a3656fc9e824e3796f5d7cb1747675d5f67a16b	\\xd001b1acfe7f00001d290dd04c5600009dd975d14c560000fad875d14c560000e0d875d14c560000e4d875d14c56000040fe74d14c5600000000000000000000
\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	3	\\xb44b55b0bcfabdb7ad1c10955b62d7f2674bff99c58610e73f34f1d12ad2379ee7b9051c2f1706b23e1b94c93afd812c407f969b6c09a28f8ad82125697db1d8	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6000b5d64505986e5fcfd8ae2bac7d726fd1a3232a8746b5501a157876034075f66926a7f9b25ca85cfee7ebb5e5aa0b94b82adda8d0225ae924cfaa9e3f6f7f	1660251793000000	1660252690000000	1660252690000000	2	99000000	\\x6182c65007227783a4d92d8509ef78d39b0168996859b65ab1443eb6fb943633	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\x2a68da4393ce25bc6b7608fb5b6e7bf7f855926cb39366a84f19e31b3c98824fff8c0c777ca34f1aab7b224ca01871c33e271b853ac163c86ebb633c60da930f	\\x0760064bb267a248d9c069856a3656fc9e824e3796f5d7cb1747675d5f67a16b	\\xd001b1acfe7f00001d290dd04c5600007d1975d14c560000da1875d14c560000c01875d14c560000c41875d14c560000200775d14c5600000000000000000000
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
1	1	37	\\xb5f5e626896c77b94828e978cf01ca0256a4c68049c61b28a01726226a39f71bec8252ae6e5c590f21b3e07bd724d54dc4401590e45e661dfa6bbe101e82280f
2	1	184	\\xb1231e32f6e8d57a2383a40cd00c02a7d79a64e92965939605beacd893a12c5941e97eb14d2e4c4e193edc555849f31f26e0713e2938dbf6bf5245ba35391102
3	1	317	\\x2c836c2bcffbde42929baf50ed668afcdd9a4856ec215b01aad54a431606fd1b8b9021e72fa4a8784f6e845074d7dbe054f9b82d4f16c488e186a000b283850c
4	1	348	\\xb38b5a0708be914fc8d2ef7b1d1c813519f777f93cbeed941604685fc9b8ff024bbdd8efac7a02f7a4991e62f59cc0c5778f3ffb90523e4881d54f4dd563550e
5	1	44	\\xf46ca847792446ce29ce8c9f92b6a3e7297f597241598668ee65a4466123947372db0dda991e71f1480b3cf89014a466b9b46c02f63103620928f66acf72c405
6	1	246	\\xacbc6500a1101c9c0e34f1846aabbc580cb328f7e66444621abdc511922bd3913ae9ad49923e181d4fbee531a6908f13c42711997487fef92f01c848b2fd6e0e
7	1	188	\\x86efd395f2b93bdce39d0bd4fb672b75a6219c8641be9f4135dc0d6684aa16641e0eea6ffcb2a3904c56816805b407fdf9573b65a673a1ee42572db2b16cb709
8	1	306	\\xf797918aff8e8624053dd57fd8213baf38a5f162137b6d37336db59b37d429cd9fb78b5a47e50cbdea68a0ef030e6a968562a8ed88721d163751affba8a62603
9	1	286	\\x65924981c500f3e45c666471059a72e1c80a186de61abcafd1e2db5b5fd6366f66ff7f698daad833c87ce6334b0fdee924c398fe382449693aae0b7148d3c100
10	1	55	\\x04bdc3501602c7a796505d89be66df1d575fbc6432c07dd787bd2ee2dcc28e546001e6f75a8be2a94099e11d2033af0910a00e663d70ecd38e21cd2d789d3807
11	1	215	\\x97d707e37e4668f03dd693b620b8fc016334e79bb3eeff6a5a994f1d6691fb4891d3a282a6aac078a56e44b586e8e0e0eb61b831942d5de94513ff1142846b07
12	1	384	\\xde7b32e65c27c169269d0a095febf8f748b984be1d0f242226ab9f6a60a25179f9fdee23928a42ad65a3bafde23d15d18a5ab2e605d30f3c102ed7d9ba05e70b
13	1	313	\\xa7d960c382da0720e5cb31561d3281b7150abc7e60461406ee46b8b1c75c22bbe664f2093dba38ec4065fd89ee1458f55c17bbd6df9a2ae2828bd2c24de20a0d
14	1	366	\\xefaceeb89916c50c5fe8a8c3a5b9f71d9601567e10e35db1267f6f4b3688e21a2844841a8821c52ef2c8df07fa826c27038d8de1c37287d54138787dcc277402
15	1	312	\\xb76f10f1bbd063f8e388d32c1efdb141dbb68e9de3b7067c41ab6350f2ac731f177563ab2fe9aa552eb39eb539a108fc983ce5d290c5b18c897af654f3b2270a
16	1	336	\\x49d4db6a64a3a31935c9bcd83c425d9caf684f0ecd2fa4c0878435a36147b68ca465d16226d5be30859d5f87f2837a74d7e97968e0f51a7aa9a422c74d815b03
17	1	65	\\xdc7ec58b720b82b0aec11ac6cef06433da441249774a56eba669836b604441d67ae848779cb54f065fc297da77fbfb0e54a0dfa714449b45c6f9fd0a500cb70d
18	1	216	\\xeac160061be7d3fb123c76ac6af8f1e9f44a18210f0a13a1c5ff3f2170af8b46e29f542ae8d1f93a88ca95f720a1e76f5f0eb6edd0e955cf95b3d18455742f0e
19	1	417	\\x91184928fa9fd1dac0c9c306aa040faa02f9d09a311a9dbf2a653928dad3dcfb5eea87943ffbd3356066ebfb48393de6de49a8b9eaba0d800fc78be6d82aee0d
20	1	156	\\x795cd9d9d911f53c71da1be26d840aae6f90cd3c839d9a7c71fee2df67ea02c76bd17d38fad842bd03f0684204fd28d93c6b408ea1124044869fd565f60aae02
21	1	406	\\x425a899b43f2b1eef88a32c18eef9d631763b140f50d415df39e9594ab9f1c94284ddab666b8f45ad541bd91b353e9fdfccd75afb4bf339fe09c6da3d152540f
22	1	33	\\xafb8c19b192875e47fd368af7c84bcd248b10bcf141dc737cb7ca017bd7609c4e224135a2cb86c6e6f63f4cf45b47e6870ece696af57261714332b62719dec03
23	1	167	\\xc5a4d06346568b607cc8a710f857bfce2d0f93d1af8ddd21bcd877a061f60171d528677eca3ac9a03a822b6f806bdf58121b51f99eb5ac04675a43e4de58b500
24	1	262	\\xe4fd094681a24528d93497876e9576bfd095a9471b407f3d332f7136a61eceef70786d633b79cc8a1ed2fdc33129f275f384a4d98b5b869b4d703bd4743d8a08
25	1	70	\\x69bd376e2303463f52ad1e49e39ddd05845101f2036207203c6c8b29b7f80c8567467ba8534db189465126f0db75cdeab94678921316ab5ae79512b89f89250e
26	1	106	\\x6d0e7830607550aa7b123f8081a99d3c83485f2141c40e88469423d0d24b1e61b3002af59ecd214358439c46010453bd4ac523181971eb5a6bd209d01bc73e0c
27	1	222	\\xf4f7291971df39073016a6dae74aa7096e80acbd82c9d9a5adb77d4a6fc57826bbac3822c776a649eabfd621c56758ac0f16cabf204bcbd7b81405ed74e53706
28	1	367	\\x7229d0c6eadb3b9b567a42e8ca9331c4747d91d40475e59973d488061294c5f0646d785a5c980178fe94b566f2d0b581608006e1a4ce1c87297020bd06500405
29	1	380	\\x717160a8c9edc83fa64f327d2ee3c7973194f9dd4c5f136fc6d19700b52810a52a70fce0cd9fa3af7e73489f2730cc9d011923b33e5c30ce2876f35d29e94607
30	1	28	\\xc57929f969fa407b50feae76e59e7d4b6d26f23f3b35108dfeb2947f9bd80b0619bf588e6bfd9134f255476c21ec465ca1958b2cc1f19cc2f96d084ea9bd9707
31	1	49	\\x14c11b0d14260f9f502ed76febc176f34d93b182b108f226e2b966b4c8efc75a4633f746f37cdef07122f6cf0061d1a67ff54ddf20dc102e6b99c44774f74304
32	1	126	\\x14aad1b015af5726c9ec94fa52ca5bc8e2e7b09c820d86181bd7e83c113db677e96dc09f1739bc104eba8663af1ee6a3a0ca43325f830db0a6a94c53f1c9000a
33	1	80	\\x1a51a17c00f1b8db1e4cb8159c7bc969043f676468a6d74d53d417b3d96c41de7d1284ea2bfeb0c7da6ae241e71c04420a9984d89f4b980fab94a6cefe24060f
34	1	121	\\x8631fd112f11506a6eb11229d03c3aafcaadd1a27d15b00ffa66b23d7714baaccc0f5134adbbf51c3639712adea6f25a8acc3eefad331ccb6995d2f607b66802
35	1	265	\\xd5962937d89d971833a32654f84e0409e1df7ce2aa905c3d0d17935eaf387858d11f912b7d9610b0c4da0d3c259aa5c01cf2cb8fae4b5515a33d269f754d820e
36	1	53	\\x3756608a8c62819abc293004138a3626efeb806bc8cf5bc4661ae8e63f61a08216a3828a82b4dee8e99a5a2cf8599b653390acb984e546f72f25313aa4a9be0d
37	1	361	\\x6ddd1dbda75db92b24b1fc201b32d990bc63c52f350400f16da7f057dbd943b79155f7f1afd6591e3e03e8d241832136c644d89222c141202f3b6d486b24040d
38	1	185	\\x7f03fee57fbae089836538548a5a041588baf50a1d12f389e148a0973307bfe79a7017ffdd164eb657330b1028e82895db8e2b3354fb0e6d654a6570fe639505
39	1	201	\\x0bdefe34bc53f8f5237ffdd7b8061ad097da31c30dc0bbfeb71dedcbd6220727728c7d9bd0be2413bf4ebd08a071f06443158c5b9b4ffd714b9150eed49c5c0f
40	1	205	\\x8855a0ad19b2cba9e29c44983b0c66a7e85df6e988f45b5be923de2b52e60aacfd5611f865a26a28e0a829367fb5e595b0039cc68558dc5f4b0b6f921fa6f80d
41	1	78	\\xe6979020946baccbbb8baec426e72ed6e0c34c297e6cd32d7d79b415a9329eac375dad4971156c59290ee46867aa5911ea8454559e6e5cd1ad12ca36ccc62f05
42	1	118	\\xd537d53a4388d50aac05529f1e296fea34626cbff9dc826c41baa8946818e3a4aa9ac974633cd36a2b5b45cd725b67e4a69dde3c21e1efec429b10c812e0dc00
43	1	100	\\x0b42242e3a71ffe0378cbd6b1e5e6bdcb128801a84263f7b7e0e9520ca3364db65e9a82c7bfa52d1094734676ebd47d6e682a0421ba92f2ec4a7bd3013f1860a
44	1	132	\\x5961e882074829c559f7c05fc26ff3f617c9cee2af0637ee53551deb8069cc33d6ce04699b623ad298031340db8082e59e0d22d37734aea855dffdb30c481000
45	1	278	\\xf5f93e9e545629f31f618a207bd7c949100dd8b4c603a15e5948660e183e5ad8fdd94679ada44c500d6a6d4421d83bcbd88043cbbc7880e52191274c8d121d0b
46	1	162	\\x677ab8d91257eefd66b66a485aa121a04f632974abb620d22c20fb706ed42923fa538988bbd7ec901ebd5cc9ce9037f0b3c213f531a27c4e187d37fd3526d707
47	1	217	\\x11fe268d605113da424927b929018a0f7909e1097d44da03df0f2ad7d12f5b6b72b4cc01b885a9eaa6766f1e26a69f12d5725730de24ad7537173e8b6341a501
48	1	231	\\x59080361ad40619a512db7e69f66e27633a09df5dfe604db237786cce365ae94821a997ae2a751ff11da8c656aec1619e9ac8fd00eda3b4e7fb29d236c584303
49	1	270	\\xd0e6e75ac26bfcad9e81386895697ee0a76af2a4644ceec919c92adbec964f0c21a5f02123242244a99417a5aedc1521e9df2029815523d73c0a843199a3ae02
50	1	186	\\xcdf899fab7e7dfd43ddae6a353d14b5afb2258afe89fd8b5f5bdb2f61fdd6fa7d07943f9298870a4ac616e2582bffbc4bc0cacf03423305d06633f71a378d00e
51	1	263	\\x5380cd2b3713f3255482e29bc8c14bf01e397936ff44025e8ad35d42ea91c860a16a442cf456e5399a17941c4f5a71d8fd50d830c07b21090ddd07c5b6091f06
52	1	363	\\xf25cd72ea201a887db167d094d84214462f9b9753dd961796d06194baa64aaa5676dd07848efdcded52ed4d0179a310059012a0924a28a253d6e578f3ba7cc09
53	1	352	\\xc59ebd572e0ebeda9841a06109ccc0c7b7fb29ed07508ef87045dabb2bd877f87fc5ac5f3775e120b2820e13135ce3820a4ea3559040a97624a0a27b56211104
54	1	193	\\x417612712d9c8b64a557462e83c3472d6e2e7dc33ee71952a5ce661ffcdbbc2f348bd11cc9ae48eedbdb274fdbe9a008ded42d719c97f7a263d8d2d2bd949c00
55	1	254	\\x5afdf19086b58f58d1e1422d33bdf33ff3ae50c5d9069a8e5a83a7a1bb440fa75e9b389f192f53782d43b707a8c3499010ea108d8774daa591bf57095a18230a
56	1	264	\\x36e9a5064aadff5dcd4357d3e6b81643bcfb8f68ea2033b4140a112404426d2ba3019cdbe224e50698a738efaae66ee8e430650c13445bc1197fa26edad4ac0a
57	1	213	\\x670457edfb4b9f21c56a9bd0b5a38d5d305fa859a9125d0a3a83e7d4dee0b855757598c93497a9bb5750b352c20f3de1d960a58720d620747d27502187bf8208
58	1	142	\\x10c5ea666039f9bdfb3c920eae1a97bed8d37b2cdfdf7e28ce8e7030057fc8ef88ac6fa3c5fc45dda4bcf1f9ca8a802798773687ff6d387c51a7cfadeb803c0c
59	1	400	\\xa10de5cc9e294dffd7f7aab5256f440c2916356e4ec10d0b9b29a75b1e13b3160697a56e70d513679e1cb96c014ad3793a753f0bfdc9a9fc0c2c67f5e527500b
60	1	299	\\x58455a701b09def84b2eb7635a2d4bc566411efcbc496b05fda409b4d300de46626e5e9f20547510071cdd1ccd5fa9c9d972122ea408ae08045838a71ac5020d
61	1	335	\\x335b18b9f0947363c68b46f3e169dea8e541fc25fa4eb1c7e0e9142e6d0c7eef930b76192778d70a78547260b3276a093045db73199278056cfef7a86694e107
62	1	407	\\xc1fe3e3bf4da3c46ed1469005ecde4ef122d8f35f88551f25ac5a31ee2e842a9d8e0a79f4083b23e058285e2dd5c9c1ef09d73b86b427b3922d5251ffb083109
63	1	81	\\x1c80752e7d564f8b89df1f19376c5c50e2fccf35947b3fee07858f30c741353d29d3dc16e0f57178a3ab67f593350aa802432a384545285c5f8e1a836718ed08
64	1	26	\\x8be90abd4310ebbc374f2643dea3bd0e6021ea1afa5960293844b377f6bcdb5d2a30ea916344476686d5983de265f16c4487326583d47c1a09789624a1f7340a
65	1	388	\\xa3066b7c84abfc218fc26b95352277ea9390415fe13886882c8c0dae44182d6044486e33d774fc12b6f278b73aab75e481fc0c867162fe41d296a50fcbf36d08
66	1	422	\\x1661b1bc85f10872370d596657e2c09d9364e4d982e914f7d7e6e411d9e2f86221a64e537e43757ab54fe5d528ef7ef724a4aeaf6365c583ffdf32e9e167660a
67	1	376	\\x09fdf33a15b9967fcf426c5d9811304986efce31c797d15e5326fec9b9cec1dfa04505b75ca81579838902650d0d9581d4d8fa489012d50d1c415156c4386d0d
68	1	258	\\xe951e7724c82739c9fa624795f5a54e2546ccce2d016aba996dc024933552bd701244dd99ec5abc85d10e4c36611ff76ad83f9aa6394ce2601e294713cb58602
69	1	379	\\x238caecc2e54a95b57789258db8d8cff5d6ab6811bdeded69f8310e04cae8017e9498d3bc3d2cdb98228fcd94d72242dd211ab2c96217e5f272c1e61954b4305
70	1	69	\\xa52589d1ee3d8c7c3393a355fecf93b31ec8c111ac79c3dc266e4e3fa6d12424f5cc7dbba4298e2513f3315e53e4818085249eca3e5c3ff57ae3a5a73d6ffa05
71	1	331	\\xb304236f99bb9fedeef18f718b6d5c40ac5a2ed0fca0f3839c31e14ed83745a75686382b5b5fd411c705f84abfe1404310064c25c55ae1b648385b34e3f43d09
72	1	338	\\xc954333f43e7663cfb3adee12627acdd290e74bb839cc7d834ee358ac84c06310272d60ebc7287d4393783570f00f04c560582c59bdab537c3cc2911bc9bfe0b
73	1	110	\\xee87f19edf0a1909ef6f2e28c8d66bd8c417fbba20e57b0a52b0ebf0b2110da0623780c47fa3755c96fb3591bdd48e6f6473897208c38e534c904e3e5cf4120b
74	1	309	\\xfddd9f5a15786ea2de5e29f3606a98fa779a218d7fdf8391ec67315508304e73bd5911e7b6a09df34966bb82f851067404420514bf52354bb6e9bae57b8e740c
75	1	34	\\x70a390d4e4e8ed27ae730dc65fdfcf9160adda6b2af6193abd318ee5a346d0f5b891437d250151154dfb7714c688826b73c33d9fecf62f70e41408a55891490a
76	1	296	\\x5787023ad5e5e5a4419657b5474a45f7ef1619a4dc1e64a81d7865e5d7588957e48546cc903e64bc25f13abe0d94fc4adeae74fce81dc7289785517c4d0c9a0c
77	1	332	\\x5d904cd46edea2885b72839160674963604a8bb88e4e457bd4c45cdeb9923b527413add3c7678b253a50fc6bff4f538da997f3bb2c75d0ee4afef6434f716304
78	1	74	\\xbca97ebe6ffeabce2d506b2b657d3e7a01a781a703c4a4c514500bac5ea287db1f7fb11ef1433066a512874d305d28030a654f0aef050dc10a1f432bd2ffe403
79	1	229	\\xcd977a2a32fd42b37b9cd0633c1eb0e4e4e0cd629a826d15e212d892f65ae24dcc09068df156fdffe1f16dfe438a61cd4e0003b78aaa3c9ddccd5c586a8fe201
80	1	389	\\x888bdb8bd4c710a0241b41a47698b28e723e10a86ea1eb4d4d38e2040eb372948e5fdaf15ad2d36fc39446dd5c364b9c3419cd99323170b9ec2843b90e3ee204
81	1	89	\\xbe3ad0c151bb1a4ebb2c331ae904a196d4987924c3f6217db886f9b39aa59ff319a6393636492d910eddc7dc10490b2a6a62820139b47fd5d2d98ffb91284b0f
82	1	61	\\x4df1ec69d951a6a7e07dd186097240fb858a1b1148d96dee31797242b1fed8554f554e08fe8dbd0041d218e928ea1b9205d7d29fbb13d8f805461ebdfd642008
83	1	220	\\x92cb2b04296b61b1ad785b433fccf53f9ed73c8cdbe99dbc2c22dc8e888bfead268af688479d00a0427942439bf2b619631957f0153dedc9d3668ba6b1a9910c
84	1	103	\\xae61bdd9474e0dbd9ee0cccdcf012c121ce9468cf98ff879a346db9423e22c4cc2fbac3a6a85d5f3068e234bae1333ef09d1c66d525a6f6215efd6c9b8a26a01
85	1	8	\\x57b58e6d40bc275a3306cbbaa719d9a8eac662f72181df087cb25fb1792137cc91557fc03de9a8edf9cd638c04403f112093994f52cdca5af4b1199be573b501
86	1	87	\\x228c39aafdff74824c7be6f72f9709a6a17f27a01d2b0a14b1a5e1a0adbfbc6214b580fe7303d1f8bd7f8acfd5919d2297fc92d45725c01ec3213f4ddbb0db09
87	1	401	\\xf028d8b556217d4f2f80a67da61b8c3819f448091f86131d5b6c547654bcb3339dbfc012014e2ce87442f1cb5577aebeafb300cde1a02eb11d2fd1988900ae01
88	1	47	\\x3f0b7ff369ef96cca8dc3515e21b9b42b5857f6fa576609ec5786e84ccd8d581883b0c20c4debd20615376e5d75b3bb0e2035a909ad72bd8b485525a06d4a005
89	1	40	\\x4d08784d844cddc000d20a12002d906ef4d07a1ec8125953d6c9948ce04519ef55da3fa271df8aff190353fda6d3604cb50aabc330b68fa349330d2d13e5820e
90	1	1	\\x78fe3d1b828b51dc50ab85c32a703d629566536877b26309353eeaa5e65f4499a9e1c6161aa27fea7a215518c578ecb759c33c1f857f7fec24bf28368b157b03
91	1	189	\\x0258bda79aa814045249fdcd878ca3c567a7dd2cc0f82e03688e1ac6f8fd2fd0cce91dabdb1741c8ead88cee1e755649abfae4f11ae0703cc1080096af97ac01
92	1	365	\\x801ca23f5439f9f8825b4956c95bb40d875b88a1907bcfe686b3cdc6d21f1b1a4de347207f923efafb1c41f1984300641c9911dd4eef442c9baeb6d108b69606
93	1	145	\\xd09112e94cbfe4b5fd517f49ae2fb785641cb5359299d6e3a8afe2cf27484f4eed5fc9e65a5fd3eb38024fdf7f2b96939450341ff998d2f65ef84bba01930d00
94	1	198	\\x88bd290d3df750364d00cf387831b4f103ff3ae6e1a56b67c23518b7ba984b9d7d5a9f65431d45f07d55d780c17562f668c50569081ed99093c7d50ffb456406
95	1	197	\\x7dccf4f32e288ec5d236aa3975ded996472a35e816cb31d4f0e08bf74019d231157db397fbf34aad345be48204f8ad03a7a2a78236ac3be76a50e8627c6d0201
96	1	199	\\x22056dd5b549ee691aacc5c6f1c0389b69ee44514361b7fdd3f1a96a9ea0a0a22663e15b8e10b3e8e98695c8ac85dfc028a1254ae9b8e0662232ab187960eb02
97	1	277	\\xf664b49e9b991e4e2c2443d22dc5b1d196cc727c60f50534c6002c4c25350076b551f8c9a91afdbca718ececf19f4e1bdd8634180ea5cf0ea28e47ff8875b00f
98	1	307	\\xdd98dc13ad27587e3d6dfb06f75c7298c165922f28e08246a7bca7a46849445ac01e1a4959d421bb22b5b70fa8d96c574893b0dec7bc8a73ad4577f9a31b4a00
99	1	303	\\x7895b251da6ad7d7cba105ec59a9003e8ac2ee84431198d5c266ce4c97f4505ac04d5138267d6f38ccda153c7c0f156a634b5fedcf4a9656124676e00ac20209
100	1	5	\\x7b34168e31485c6a202abb73a8aaf46ec97e18d5b32480f9bc35687048a17ab03932adbc92e2501fcb48da7e179a545992c6d6c369e8fbe352c9f0a5c62f910b
101	1	20	\\x0d4efae63a0caf0f7ebd059c5ae946b14dc4eefbcefa8e0d259f2888509a62ff84529e535a13274d130a1e94511af8e35962270228cf9cda8c075023890d6c0a
102	1	228	\\x29896f73912aaebe1900007691bc479e11c38427bef5b70db4b2c20ec7413a537ae5de19bbc75daffe63f06beeb9df47e71e6cd931c7a3b75963654169971f03
103	1	412	\\xcbcad7f45f29118914329708b226d30a269434c0ec32e272f3e849ab6a3eb4a830cd2768e3902e7c0be4d00d79cc0f858a57c84c25d8c0892eaae78c7e6c9301
104	1	202	\\xc8ebd960f50f630242b19a66744fddda88ab6b4ee75f4a3393f28fbe99cce30f825e399e2dc2ec1ac8cb87af984723d1ba6f372b564aa955cdd28fa28988770f
105	1	301	\\x227871d101f8b2d94e0a6cfd601f0738f8ccf5e5b5a3affd559d17d082df2c4be017ce8365b9f7646eb5d47beda9be5efbe19cb5843c966d59b03fe0f1d2700e
106	1	285	\\xc2961a00b679ac26813ca80a0fca49119452a8d5c3cc445ebe31b6304a8eac6fcf87b1fd576235a4acb00eacfc42182d93a8413cb6aca6b1df16c962648ddb06
107	1	409	\\xc4da330b0ac5ed97b56d914dccfebe6ce4e6dffedb23a01578433cdd075a5946c131237400b7bd9bd34929424172049c3d02bd2008c630a8a130c242cf447f00
108	1	39	\\xe7ae978e5eb8d4bcb51851c55afcd15ca7f102737bbe0ad8f2a2e5877e4c415c928812ed4ab204419d5cf4ba53cd6fd6cdb3b873cde88be8f4937668b0848409
109	1	244	\\x9d7d4d053c17fc154ac0ee428efff1f157961a384420096624cba5fd2b8eaf142aeb986cfcfcf197c0a4e01cf722133b9cd037b52a684a7fddf673e3908b5c01
110	1	95	\\xf2c3aa1057c10a49269263ee6b86307cea2f36ca9439bfcd4ec7ebdb409a4b76dfafd1486d27437a5aa0035e33e65f68b3dabc803fd5d3e0071d6cbe88cd1100
111	1	115	\\xc8fdd145b7631492a58ba94131a2d9804c1cdc419579cd26deb2e66442c48639e9fb4a816bf233f56bfa6c1d78cc5cb916e5888513a09ddc80f25139053aa50c
112	1	21	\\x689a47f303b2a5d866d23ae01ddd88b8403c57e2252bde54f22bf5dcdbfc6d388b3d9fa32cc50a9dc1e43d928398ba62c67352f091c7b00cb2a94ae321c2960e
113	1	42	\\xbf22ec1da69bc4b19996a629bb0f84298bb21c365c0d078cdea5e89761aa664e616420846456b3af1ae99d55f5f668c2f0367d307e748420bf7b151459e8f206
114	1	38	\\xf8261a945dae328d70c4d73fab5351cd3e7f10d66dd69512e748b961ea19c1dd2f504b7e0374e446cd2bc76b0ec4e822e708be88718855fd04b4eb0aff74d506
115	1	157	\\xf8b5c26802faa989b70b954906a12e2eab0c50a7bb363e87ee0bc928ef9054b8fda12a65b982d4f7ee234d26491061795caa9485e8e28923dd8b4e4c8f880300
116	1	411	\\xe1d703719d5d9e064b6a913530d39a5df24407bc5ce4b56ccd6dc17aa055cf0640b37952664224a5ccfbb77614ba4ea70b760519daea774e965303b612224106
117	1	98	\\xf015754ac03353ec8941de77259e2ad4d5a297f675e2f826d7e6e276b52e3b21c0eb02da6e74f343692dd7eff8924d17716ec9bd2314c3a4a9cbc55b3c14fd02
118	1	405	\\x59421547c84dfed4e748a55c7754a2f9277ef04f742cb4e739c7630d7f454e039cd488e447ffe8e32268ab638393ba13c98b8ef1e5be848a029366fb44d04d03
119	1	261	\\x53c7b2dac2b45eccfb014e1817f9a8b4adfe302f7e52dfb1915d4846eee4fc4220dfaa35e02bec7a0ebca791f26112f877e412a278b81fc6b12f4d597065b10e
120	1	208	\\x99da69737b53b8bbbeeea7c56f1baee58fdf17531c2abe761b713babbaa28264d9c756ddcae2a53fd343223135d0cd32d6199efb73ba900190c86970d998dc08
121	1	330	\\xf416fd28d88d6e95f32656cff71d53a9590cf56122a18c36929d0d9e7b00777b069f781a51109e11577f858e9ccddc9485807e5e7e354d4e025d6b222ea28906
122	1	155	\\x92a8fe904f60178fb547fbb6952874490dd938cec6572d37852196e5adcc6a44ed49ce96d4e75a4b5eae88024eecf26b3279e9866f98092838ce77fdcfb9ff06
123	1	75	\\x9d6fd4d742db0aa9a5a8c42a910453f5d40d39f411dffcd8ac25183ed2e56bccaac97724d4dac7b1b5c9a44bbe0b7a7258a486f96912a3ba5ce87007160e8c09
124	1	111	\\x7938c2bef3a6abb720a5703a61482e8a6b6a9d6c68c35e1330ac5df9996fbc32c34822af1fdcc11e014359facf2e41e235e6684ed720a887c1a8d89f1a2c3009
125	1	7	\\xd5b585a7929460691bd282363644e05b468b0d69a5aa7148e02e898c4ddda16ea19f68b3173ede6098a3276fcc71cc728d91c2ace2d1c6b7a6fba0f54f2fd907
126	1	85	\\xd2595fc7b2bd9a8a8dad176c518d3e3f446c3eecea9dcbab766c4766124d75b1be2c5b7b090203b1467b8fdf505e2da8aa246dc1352fc484464c79116ce11909
127	1	27	\\x66b388067d21c51e422ef29ad81b09c4c94e50a0aee98a14fb95d427af67f470019f7f3e0e6add934d2a42543e88c52ce31549f9f4b0fb81aa9b1e5e3c9e0702
128	1	180	\\x145e8ce67a6d6744041cb9f811bb83f5a85f5c190a098fc11cc010a2e587c447d69933af3bb2993873a111a27877128c3b3c12e04296e4e6ee55116174a18d0d
129	1	320	\\x3f5ac54b441586a9b406fca08a07746a98c19b1c9682f3c45eae4de5cbb4f20595f63f6df26fd3ef32a8dee161b98bcb2c600e4fab32e18ed035dd907361c50f
130	1	31	\\xe5fa8065d275b41cd808bcdbfbd078c7c6222b1eded735e96e22e5e9886c6463747530c8927162f1cff977983192f0858b6a7e26b5cdaadd9c64e653b27f490d
131	1	41	\\x6de5dac317f03784ef8ef7c61e4d7a3489e7d4b1e7b21e6c70d82b91ad0f274b8c8588dad81d81d735d3b734acf91b89dd934d32231116fdb7193f54c4d14806
132	1	62	\\x31de2bc92134f3ea5fde499e088889eb269499cb163b19b81034f6faa0ce4d1578f29120482d30b4feda0ab2f3bb8561edd21df0f9c3f4898847221d70ee3b06
133	1	10	\\x10bd8eda726c2fa56f62c47427b0722c1e6b6c71d9766549b7d580789fcf2ab4d8bddce4913b83b99c5bc7ac89216da911dbf19168e3477c59ca9d567bb02605
134	1	349	\\xfddc813ddf094636f6cb89a1a630383a867f48986f178afeb5606935e40078b685845039dad20b43bade6afa45c65040f13737d89e8479d444b6320f3a6efb03
135	1	137	\\x5054aa991a9a674a9b9a5a8d10d38d985e608b0e08f114cfe1ff76158ecd6deab657004914707dfabfdb9b28afe4d50b1196a7ebe83b3dcd4e05a811c0204802
136	1	249	\\x0f2d904fd6042b0430bf35006469872f63533c272c78c804cde2d06920158fceaccd2acdf0d59cb69125a0f3eb69ef46d104a84e3770f8899015adb661714f07
137	1	29	\\x3b508950859f12b81ad86796b8a21707699d9211f27fdbc21d5aa3219f488c2ca9fa0faf989a427be492795c44b64ded2b4d7488e5bb6fa010ae3e97c6c27102
138	1	339	\\x0628fb8abea3d42114a1326bd6e5b1283c94c873611148a2258095e0984d494bae7b3378c2bbea128303879448a8a007fb5e2da4c055e9b2188e42ac2357790a
139	1	289	\\x99807f22da48db2c8d3c2aa64964dea5a4cb6810a3eeb6b88c9b3ce636cd0d51510203bb8c343ba72bcc71d31041da10a045bafea3e8b2109871da8e7d319301
140	1	345	\\xad65d6110faeb9dde3f358e3534509f29f56ce4b50be090c953a1e087cef3f8a9e3a6f6ab13673964a3e71e9fba70776d55cdb479614de4c31b6ba85a09b9b02
141	1	164	\\xbe2d23a18d273831c8396cab895a20aefcd0666128404883ae9e26ea7f6560b0d80546ebd75be283b9c848b24ebc29b29afdf3a478e2b972a108d8426e594a06
142	1	18	\\xcc593b75f51a90e13e2b923d3783e14238b6bebc20cebbe8a9d7c0896bf2e0d18b1144d5c30d7ea0f8a055b785cb791ed432d9dc443e8dad25ec8b2663a47b07
143	1	396	\\x8f1eeacf86fa1e2366c3e4902bf700dbb21e261f258f7a7bc91d9a443315cd094a553f6539351fbf62373e3dd38586677251c44300ab34335feaeb111308f109
144	1	120	\\xbb6f6f8e950522079afc08c07cc12fd7cae03e58388876b152abe0de4b24c8d78b6fd0ec6d3737d410cc98064dcd96c97b8539469ca0e0c11e0b15040375cf02
145	1	14	\\x1174cf0c6f911d4c19f04527760767baad97d4c612634bd90b81d64445ddf9fb87bbb0a2a6065b164925414e7a02e6ca97b474d7b8f44637974e609bbafc9405
146	1	284	\\x0143415e70d1c842f3168574b24433bb976cc98bee50598b54d407a043537715271f8ecf46cb415a726cfb9553763de4c6e88a27a0a8f4cb5a0506cd28754704
147	1	102	\\xf6f4f7031d687d8ed0f7eb67bc2889ff3f2c0520b38a7c59bbc71c9ef77db2ed994fc2a32075635770f8a4f06d3f20d7a78468e4b9618c27f386cff54febf803
148	1	154	\\x8e652ce396331e2643b11c785c324529cd49e0ef0521051b85bfa2249fcd9169dc22e1c318586218f259cb00fe4a4d7a93df8d5d9f5ca3fc12a58fe05900bb09
149	1	71	\\xd8e48cc69128807de9e6f0a78679b664d482b8825ab516d03d0b6cf8aa454479fc1faf487b62c9a3ff15553b610d9159c3e5065a329fd02058579aa7ee66f80e
150	1	294	\\x2952ae4af27ca75f7aa5038d112f2344dc81f65c609981608adf9ab7e304ccb03f64f1eb0e40bf9ab1161e63b1b08edbdf1dd1bbfc67fdab4eb200b5a485410c
151	1	105	\\x893430b17ab4aa8ecd3cdbc232f713bc9d4a87867c3da27002eda3f7fdf974baf81c21eb73331e2759f7ae94f0538a75db8e803dd9f889f1036ee039317e4807
152	1	370	\\x3f993b7b4d979d7dd1ed33ae6c8c4cebbd07228e0a072d33a50431fc481f1826500421ea4e5d258088cab4926b92f41b2092034b35696800b9edfb332190170f
153	1	304	\\xa5d5065608209a7d17a2ba09cd38ba0bb323dc2aca2437312cec545dbb82a48b6ec6cd8eb89e21c42ac7869c5b8398eb9ced5cc69b9fbaf2c17a481950c49808
154	1	314	\\x63ed5c9445ece5b00b39221a9069a415e43c74139c5d3c67091130a3b99942c0a12855a3597dd69a882fd0b575b4971b91b82e10201ad731e4fe662f3117ee01
155	1	291	\\x43a40cf318980c236bcf44f2adcd7c24a0ff73c987c459d5f4f562da2f9dc66cd47ae621cf2c5d3fe62380935578cf8c3596ead28209f6c0d4ef7e7bb79a3c09
156	1	168	\\x521f3d0553db70bcb9ed0683909d900268b062a465a07463772d66ab33ff301bbfb5278eb1bdf88ed521bd9d971960ba2220b6ad184a785896e3cefc80ffac04
157	1	371	\\x4aa3ca0b42763684b566d4e8330b30b3ddde678310ac8a8441b1d6ed29b00b806fd45a6cd6f44ef9ef0a8c5bc2854dc30cc1d18c706bdb5d2429774f641fe309
158	1	172	\\x9a9aaf97f75f2ed789366c528873adda765727c34acde5ff0cf1d2ce8a63f4d9a405d7ad6a4a522686eedbf19c19cf44e62f0ef1d33f5fd03bbe9a07c29b260c
159	1	269	\\xfb974bc9bddee6d73f1c6580a0f849d01b2bc3adcd6e5ce9654dbe989ef718756ddff8777cdb3430dd62a9539c9b02eb78bac03c3afcfaaab9dd054e22888603
160	1	255	\\x01dd15086bcdfc9ebf7efc9207f165e068b8b2c3f311c86dadf194202ffaa55f708148c365af424e5f9487115fa9d527bbf9b5406b465e258d93e0bd1540d50c
161	1	266	\\x3c0f00cee3d91db84828676f92cb292c5d16e296c7af9396d5ad9b012f56166c71df4c2c989a980d3389ebaeaab546c240a17db8fc7eb9aac676be617e41020d
162	1	6	\\x06af65c61691248aa99c0765a182e8875a8562c5b830178412a8382575879c790d5c19c6f203877bd8cd2f55830891b45fbbf0a76af5b0c0519c0f2efe8bba0a
163	1	36	\\x7f62921749670fe71eb230f421d00d27a25434a57dfbc19b4f561db902f91b7162f90df8af1df4a02cdfc712136368a3399681c22fbf485592eb889bdc89ca07
164	1	397	\\xc6fabc2f5852bfc09a65226b1f03b82d6600440ad7af5a2dd032ba4b80f0851fdf9997c1446fc81dcdcee4282ee0ac3196ea6041c235ad17f2c32b1495046d00
165	1	300	\\x4d51a940233c972e267c50d753abad13bfec10b92fa173a01ce251c6bb16f7e4d0ca0813bb7142a3ddbbd2b616a69aecc75f37b79362bcf578ed8205094c3509
166	1	13	\\x7c6b634b623d8aa5508bc599287e6326c7ee608edbc849df2db9dd0eeaf1be98f2d7624302de41cdd27ecd93ac3407083c03445a0c89c3aae89f9ee823dad50b
167	1	91	\\xafd55677578ca7ebc5ab454c2bc379927f28f43ba69ec18ab603cb0eb745df1ace2845356a7392923514c325f90d339a295238bb59b77090c061628df9063903
168	1	237	\\x1a74293b5691ec9eaf43c3c056ac699aa469637f6b0a6799769c34bc949ad19258d087a1d07edd6f5878a05e54b2c3a8aa37e4ceb73ef9f1b2317cc141637101
169	1	67	\\x0405478661461760076d9ee4a0181f4cc6c8d4b408249b426ae0c05e6b42a956a2a6a60b6490429d24ecc40f900d8a352ab9a8758e8a66c9f9077569c839620e
170	1	64	\\xa9f208676710a81987a0ecdf23788e76c1c10428713efb4ebb6b7855532e2600e23e5357b65f3e5835a603044b1cd6ed58ffa957c99de9d0fd3a49904b221106
171	1	93	\\x19f7e4096782ea065cec168e028dec11dbc20e95767fe5881bd9cd4b396dd292f79c63690f4b42dcf22eb9c434a78ed728e2ff1d6ca4f26b0d05ef0c33b8520b
172	1	377	\\xb2706690e1a1a6e8e9866aa3461fb1e6ffdaf507104b369a0d1dddd1c121fbd1a85b7b40a69260276e8cf7e082265b5a5ab2f3c45109b0dbd71aba27af64e602
173	1	2	\\xece6c9a3199e19c48697db28c6962082eb64fab4e83783dc5246d32badc5c5b2162b6b5d60b8e39ffa236a824b7bd4d1acb9d095bd1406c18b7a4d6217f68b02
174	1	16	\\x9933e914a0289b1578a1968fe1080017391fa7aff0faa8f6dd60e7514100173279ad8562bb69c2da2daa405fbf59582a3ff58ee926c792669f21debc0f86d008
175	1	88	\\x0547ec813d43da6662dc0a8a6feaab700d45edd1cd8990a3c0b5576630dca0d62a43bde0d7dbbb2fa0ad8b3f71c0f5fde08bf0656dee64db296b1aedbc783c05
176	1	333	\\xfaf6a4fb486d4f87bcac1cd4195b7afd2a9c47a6cc5aac6b5851e1c4ff4cacd5c78df45cf6930f87ad7d86ce239aaf3eb74ed82d46a74a17be8875edf8566209
177	1	256	\\xb0e622a9bc369068174adb277fe293287ebcab857d4443727bcd65086dd47ff32c82d8f16b4b8b7c0d60be06221ea288b7acea8e06c2b6db7702842c3b852c06
178	1	143	\\xb4fd610ea8f8bc54bf04fc571d940ad77e0df2b2371bb7ad47033965bdcaa250074dd508addd7b348465b1551fc3fb771612faee30b3bbedef7b86fcde0ad705
179	1	373	\\xa97074d664248fad673ba00bda5a58febbf9d505f11d5254b04112d044448d58008065eb33ff0c305a8df45b9267d7f6aa5d0731c7be54641012e1ee5097960f
180	1	310	\\x5b35f1759094ea195abb7cbff4b89f731882cd2ad6cd19b2ee9a4389ae8347ce4af39b464301b68d3b749ea079d4c854928d53f0d5f0e8b2534f97be82568b0a
181	1	3	\\xee32b92c8701cdadb54cb27debe46c8287444e7b5bf420255bbca9447944f65e29848834a046aa35140e06ce1d1503e4efe342eb241755d2a0bdb2e4e082e80e
182	1	293	\\x2aec61da15151d484f4f8f20d6d9d9a21ea81d480ef8bda52ccaa478e11d08109dc0fbc078990bd3a970d67e2f73cacb62a08ef942915cd8cfb050d342dfa70e
183	1	358	\\x0a77400fbb45dd033bff13e63834efe900690cb409ba30312deac06191d2fe4317387f9a3cd8fdbdc9124f8c6342b952d033d9dc261744de6865be8ccb09b401
184	1	272	\\xb8e012561f4338adaac20c4d6c453fd31faa58ec163b780ba43f9c69b03ecd2e57905a56fb9c09cbcabdc64f36a5477eb42788becded02bfeb7674b058cc5405
185	1	233	\\xe27c894cbae35166fefd8c7e99c8dc2cf74fc88378aa7d339f43a5526e4b569c95baecbd4f8a21620118a278503d6a7ccfe7901deeb18c8ca5ae581fd9526800
186	1	178	\\xaa550d7eb03375c4842f120a3bad0573319f8eb92cfdec53fce8022a7862d3a18b5afd591f2b9a5bfd9029291025463f64a88be797c826788c7c77dffff9c20f
187	1	420	\\x984ae4dbb6b318bf923a3b91ca141d09955c5f7d09c5bfaf2c0bd52e2b790e2cbe637526d2a5dd37fc5134b5c655ddef5afc72dfc59ff43f12ead587f710160d
188	1	350	\\xd9f0d8b7fff794e43133165646d60d0f00f80d00b9953dcffaf97a8e42acd945f7c73f47ded84b259a4a9063bf181e86e760f23311b5863ec68a1b87e907b005
189	1	221	\\x03cf2945e4e92ddd62278348afe67c71d73d1b6d3264302b1bb6c715a39c844dc05d4bb4939623811fc17582225d0dd9525c5f297c085df5448dafe8d8747a09
190	1	305	\\x835beb6ca5492c6c17e34758b14b574d333d7cc0296b6e2a37bf3888f3d512675fb2ff28edc82735974fd561fd1df68e310d3574026527d329781a1b3330a709
191	1	279	\\x4da299bed62984659aa3311afd663db546473be1f03ae888b6389ff3453d5671b4d614d7407da5eb53437b08d098ce2396ef65aa223db05c1e0e52a01ec7990f
192	1	209	\\xd3217c18f4ac85caecb806be186863f02324b9b414ec008108d90f659f22ec960b8a06f50ad2f3e06b2a30491a657c7eabcd00b076c6677faa72dba3c466e008
193	1	101	\\x9665890be2f49153c5efa8825b88e9c00979d9f0f36dcf64299c720cff8155d7ff24615ea4c46dd2c37ca67a1b15da31c92b2378815bce841412ad7dc1d20205
194	1	298	\\x7d4ddf4a3ede21128ff611c9e8ea110c16e43eab3b061d7c94c71de4ea0b985e8b13684b6882cddb0630edd13807305df2bab316e44f695684327ecf0572a201
195	1	149	\\xe926ac1584e9bccf0d0d19107ec166adbd2889a4da031b2a722f0dd0806915b0f0cfe6aad71d5c550d1d8c11c57fe1965ec32f871f5544ee1ed2e73ba552790a
196	1	45	\\xe7ff50332ef1beb1adccaa71bbd689a16b05c99c92488570e69a86a1d199d685823aee259b766e8da66fb3a70a00a65f7dd25a1e4ef0fe90d213831d747c5b0e
197	1	204	\\x833a75129e4653ec40d194d788b4e206ba7d49e544b206a177eb61298af0a8f5d80fdbcee1996be6e108712a60043ac6dc20180d959219defe8605ff9bf9e90a
198	1	15	\\x2f6781ec26a7c32b5fe9cc9e366caf4096322663f1ba2f1c1c7040c6986c2661eaa328b0b4299adca77c99fa791f9f672042b3caf07ece5b32b5ef9bb126c800
199	1	176	\\xa7d401e12d9bac31fd892a94783c8b28f425d6ea0bb0aeaa626f1ba7c73739025e5861043af5b2766cddc2b8759c90225f3788238d0d28d6b54f349c2575a305
200	1	368	\\x7ea778b7623973ffafbd6e1b5294dd3269060af63dfeed31dcd8743d16222eea4ebb7838729b753894c761e9f5b0a44cb1a66ff3ae181435b1c5c1f1057cb603
201	1	316	\\xc83b578d2ae7b1ce8c98077970a42fdc6592222591628c9dd694c71e6791d67d37351ec476edf483d882e6aa89632c68b89616628cbfd105cefe3652bc66b405
202	1	353	\\xb23d2cdc6924173ac622b3b11dfbdb062e7a5b114b8b3e2adc144bc3b808320aee03dfe1dbf8ee5ec59c5ae582d6ced502e028d0feb6d9f70464178262b1780f
203	1	214	\\xacd6bf6fcaf19571155c5b3f232c1c01ef65d145d5085fec29596e4c29942817e5f63191a3fe23825a5ca137a52abfcb36a53c49a4c60fd3539f7567eadc9e09
204	1	418	\\x92963d0e4a27ddae9b96579fa6afb7547b5e84a245cabe0e88cb4d1039ba04a1c55fa06bfaa12927150cf3577a1d01c24bd9f05c128d427a3fa36e7b5d33ee01
205	1	311	\\x8a8f55d4b6bf4321a60ff4604b76be64770a74dde10102fce4d7ce6fb2c2872c4457c2b506e3f54166f53f1db97971a64f3587431a65c6ebfc920ab01dea7007
206	1	150	\\xab88a6264c4c7db0ceb1f2cdafc5a284acfb87130702e9e2abcfed6d07a2818d2757a8e096d4f1ead532cc85b808df8d4d538b7a98088bc09df154a4339dee06
207	1	19	\\x29114154944e90358c0fc84da33c0751faf4f1026c4ad1420c089099b8c6f7f76da10cbbcbf1b1190a0dc57b10d20403588941f16d529fa0fe08e07f350b2e0b
208	1	247	\\xd12d061b59aba88426e0ac1d81fd9cb7fd9c29451e9a77db85b4c1cf43a49beb76233c9eef77ef65cb5a8c4ce121024676892880dce28ff13fd407b86823e308
209	1	192	\\x8c4b266e4a0060a611e3a2ecd4f3c36ae735ad882bed478044da889d7a72be0ebd650394fe7179ba822b76c5f3ca710c8f0106a6742ab2aeae9a58e19de9a70e
210	1	334	\\x1399f9700f405313851b9da21ae8f0906b8648def76fcd067a164ce82c16ca7b56cf4844fa7075f97b54c0c6030f04088f87270a33fd7d83446e507bbdc5980f
211	1	224	\\x2787d013d7866dcf73dad4ee7b305b17d90351146932047533e75c74de060d9930bdfda2588e8dbc981aba2a5ff8f2096e31905fc687c1beb51dca0db1846d00
212	1	163	\\x3583918287e3dd1dc0d2211a5876eaf73ea1b93e9559755f752167e0771cc8d7def0c2a3d9bbea6322b717411b87aa1d57273d34d3b7848808277d2f34e93503
213	1	210	\\xb99e077e411571cee971d84c465d0acb72438d9bfc706af18fba3e270fe93d1a44e3f456f0a213bb1595833aac162f4b789e07d28de9d3f71b7f8ff8bd414702
214	1	323	\\x354494acb272c570def055aedb416c256224e9543fe2314449facf259876d43a88ec487e05623a2879ccc5088a6a25ac34a014608d41f2539a1e7b8745780407
215	1	239	\\x97c8f6eb7ba1e3d938d723d6b21763448ec8d9630d5be36b6816b813b2fbd9a852ceb47e287450710ab87d1bf77b060d20cae2eb605ba91ec306cccbdd4c490d
216	1	414	\\x6f5ffc0b11819f62262cf7cf926e2d029d1939ed25af9e585e08bc55f9b057bba32cebf8467530949b1918fbe32975a2f7acec66e3326b655ffe841d96c2180f
217	1	54	\\xb1c5c2434fe63792af2045bd341e7d7cbd4da7c0118f7c392c890414c17e41e7309576a45c92a426738886dc765ad74a040a29f5b8cf431650cfd0c30faee700
218	1	223	\\x24d8cd381f5ed8dda537d0cdd413c0918a86d5fa6dcaeabd0e7c53fd16ff0e1943aeac90264b64cd8060f10ea2e6c651b18e890c6f53920a8916553856b71a04
219	1	153	\\xffa31c867d58b51c37a9b5e4cad0230e78faef68ef0fa8edc00372af81c93b29148385f4e9f46ded85257f8e3459b520b06d95c0e0f1ce1719a1e312fcbf0307
220	1	387	\\x9eb81e2043ff8cbdb895a51a65eae90f3f1dde562865a07dd03f798628313f88690828062333e53c5a3be9c8d91090db23098a670853ee21a45c55e7de81080c
221	1	114	\\xe69572ed80b56f1364fbde5c47a5661c7e1c1b463fdb0cb0c8ccd4d431d5005a357e71d14979209771522b21a051f2d25728362fd414059f667c62e7422cff03
222	1	159	\\x5efbe8d4d90f0c58dfece54f74d18f1e21c8f2484b855751df52de7d638b7d619753bc5a0572c36c0da3c54dbba5ed8e2db6c56a6fc4f07d51affd4eee0a7f04
223	1	360	\\xd1aa487a99bee3d51b5749f2e2db3047be60067249d6eb8a426fad72514e06873e2652f137ca41690e240f551d0c03f755afb8c51cba3cb9a104c4610b66200f
224	1	416	\\x53cf566b1bcb99ac41c19c93b691fce0e780a8329882ab33efffbb1f136b5a603b1b268b78d50c1a066e6073b438b8807f5cf8b7df6a4a5197586d2499571e01
225	1	136	\\x6f7a897c70ee841e9bc4d76770abe4a8a143c17abd5fdc0a486f8976043497b33ea814bc739150e573843f0059214c3b302f694a85aa23f61a3eca12c76ec704
226	1	73	\\xe70aee60d22c5b84d7014a92b5ece36fad2aac1c9f6386433d381b82a47d16a0d94b4f9372a5faf02ecd046f7c3b7e6c94deeb40ee1c51e382a0e827344b4b04
227	1	58	\\x4a8ddd36ab3b59dff4d1634ef44902e5b3508f140172a8159a2f58a59fecc578b9dc160f3b2e65e94f7e383fca808f2b46f645d65943bb7c886b1ee95daa090f
228	1	177	\\x5ca28146c91f6bfedfc2a1ab64463bb62c017e842303cb6f469d7cde57aac3a77b510f2c6f552b90a1227cea82835085daa8dbd0c35e888de6bad8a04b900f0d
229	1	236	\\x5a43cdb8abca70e874e6805af0991ff1f9a85c630cfa0597e69a03cb3bd2fbe7cfe124ee151d1a112cc40cf77503f035780875a5ad4bfc4b7f1d6970482ee90e
230	1	267	\\x1dc7cd6cb97a1d455e7c28eb542a1ea5a65455c8df317cf676cd76211222f8461d3999e35f3c399ef973aef9fb04cd59305c014db3f2e8a9b402e75d9f10140c
231	1	225	\\x889711f408b2d8e13aa0ecae72ec8941e1527499ed970d41afe5f7012f3e79419c9cefac8f21506c0c3f66ad7c720089596a93097b3494e0240bddacd92e920b
232	1	97	\\x40454c94442e3477de88e9689d3c118e9f41eb1054a73fc16df2bb407d7d60b3922d2046757eb9777c5ceb6a4fae17dac33a8ab7121e3d7b78d2fd51f1a49909
233	1	290	\\x7c0ffaa020f588bc2863331c788254bb97d4b111229ae6dcf47829cbbaf43c2147816f657ab0a0fff67844df3f32fae0eb459eed8f7f9d12250ee34bdfe9de00
234	1	395	\\x19e580e2bddc50a42c00d62996717ce839639e0bddc5f1506abf9861c73d687e07efad66dbafec1317e055aa2ebcfaa61f9a801e02faa994e0fe902ea8705503
235	1	415	\\x14d1aedee58a42fcb2af38d7f6571541a16f13385d6bdcc78804e224b235860ae9ce4ff346dbca9ea5eaec7018bbe7153bcdd375fd2a68a54d2b5f27ae370802
236	1	119	\\xc2deff336c97f04cf139b605ccf45b5c69dc7c76547e10eb1b804c18a5a0556a3fad8c4eda223f12b3f08991cf143c7f56987b7dac80dfc10c775ad25dc75c0e
237	1	24	\\xbfee76e167429c2e8bf3633250c7151376e70988cada9ad86ca435b3103008490c4b149ca25b636c1cce01e4d2c635e1426232ca82c35f33693488fef10f3409
238	1	413	\\x67928aefd05812707adc6a1b6c767ffacd140fa4ee6d8d999b7cc44ed3585b6011c33bc1c5d40a8774440a117e2af24182035b6e9c109e9e91a39435cdf2080f
239	1	211	\\x8883e37e25f717556e0e2c71d68dc1425f4149335214b03cf64120e255035b8bf6807025fbe71142b2b316cc426ddd18c023b385f7b7f23462e8e6dc45962904
240	1	337	\\xa54ecf5d31ba312cadee2483bca58c86887da735d9485080be9904fff8804b0a666c5dc0077096301bf859686ff4f60a1a532e9b50c18a5a16f07f203e07090c
241	1	72	\\xcdd848ab37dbd21e88a298bc37814d09c9bed5707f0921d8d0877d93d2858352b33a4a553e26185e86a4c700e6928449ebdedf4fc170dd752ae91a52b0068c00
242	1	99	\\x331cd29d1f865e49d85f6b26cb09a49bec4628d2e00833a425c35fb54e8cd90171060c67658292fd9a67acbd5b5d31c3e560d8e9795391c67587343d663f580f
243	1	383	\\xeba4dcb86dfadf7c439e6631ad720928418928a98313b0ccd876274bb47738e4e58f543d7f0bab0d3109d96cbf0da706683e319e681e06ac288bb9df3129310e
244	1	46	\\xee8298d3b45aa964798eb847c00a5f2bc2acf3659894d6c79b95ccf72a6247c44d97fb3d8a24844633d2fdea64f5ade53d6ac47ac303f82431104d3235f24009
245	1	404	\\xc1ee4a341597f02cffd5eb7908f1de287ac0df53d9f6f3ca769ee0d49323456e892aa5ac2709b2eaf09db2c38db219f6e0f0e5e6fed7d7e5f121f01ca1d02f00
246	1	171	\\x3950f611729a84def29a0563ab87bf0b472160959ed89eea7289e20a2a7e3cd4ca6661436326256e69b453ba763328874ae1405efbf2833472cf537f5c5e1c02
247	1	83	\\x75efab82de6c141208ec3f3a37e56410a3fa770ffc56556faeba2b2dffe2d90b8ee03903b593445224ac3cd6b208af975d427701965e993e96830cf5f584ff0f
248	1	242	\\x0adbfd2e226e45b5aebd32afcde1faf23ff52b1894fb5eb4029706a370fd848614af9a364709fac408466bd0c80480a300c216ec9e100c29b928f780a6384204
249	1	169	\\xa7c1c01ce4c3768a60aa4458eeedef2a4806b059babb04cd130d2653d1605560f3269c07a6ff022e19061d08cfe43c95321dbf64b9e3b678c49712205da6560c
250	1	11	\\xbf540a1ef13915ae165bb6c48b76bf20c44a2697ba844ee66e37bbe511ad7f646778eb37edae291b53021a6e250e77b7d1c0f5dd3f36169b52a65e4513b85e09
251	1	238	\\xbacbfe981e97d608dd59b67587dd2a07275898a94cf686f93d80a545d2eda353590b567e64203f0d3877ab3c4e5083b0542f3dce3f67109ebaf722650b99c603
252	1	182	\\xf0f373eb9d905852238d553a6cb3f0fb02db998e1e217195ce8a913815a5d09be8a2057f2396aab3f5d3dff7b6c60a113ebd3e7684ce3b2f41ef450f3bc9ae06
253	1	191	\\x1774625677b5ce0a3dabbe27dbaca16ad35550c6923491919f7cbac9ab5eed3171b89bb21d7029cd719b11cbe174ab4c6d6c21ce391761f3576bfe3edf5bd505
254	1	50	\\x0a9150b74d2a7d9ee15d43dd6ea9f013f8a3d3ed17169fbd43b8a7691479980c480d19e4810d90dcafb9bf334d24701c084571f986abd3e225bfd6f3f088550c
255	1	165	\\xa7bb573b4bca0ca3fd1b0d8f6ea53772e39b41b46d11570ddfdb7392e506a826d2950e19254dcfc0815e7fdc8faa3bef97ebf7a118cdf72c4cb03ebe8f571504
256	1	113	\\x69beac3c530a5f44f9be4a453d8d54a4a92e9e5186b1bfa64774a34f111bc60ccf93650ef16e7dbbd65928d9ec201fdc3e4ff7fc8800382890af95bc4323070c
257	1	347	\\x0efdb32db9e9c2d621922b68cc01d2d2b5e54d8788ba874246fbfd190b145878ba69c094850b2b963ddf18333ca549493855bccffa25633614fce84eac2fcc09
258	1	109	\\xa06054b0cfa79f4cdd88e3923391ef81ea0176f65ee8c740b56c793b157a05cee55ae37593dd6480f9065ceb55699c680a6466c15b29557cf05e98601082bb0e
259	1	68	\\xd262e2608615b18181461f80882ad3e7ad6d1967c6e98371d9426104862210596faaea606f50da54a771821cb6131a10fd53cb89a1365d97faee82b9a3e6f400
260	1	362	\\xdd3f4181de8687f167d2cd2b3b7a7f1e8dac00546c8c38a7e2b5bac65826c7b05bcdbf4e8d12dc138a26fbf83b1168a4fe49857aeaaf6dc0c22f10ad1c95d206
261	1	200	\\xcdee15f3cacf00c7a62dc71faa61c1d6a5af194c45c9be72226d5f2ed0f6aee4bd8a82780dfd880dd160a85f798b10aab98bdd7b5bb6e68eb58d1e5b87957003
262	1	410	\\x63d1f41e949e70e6c10bd5b708d49707596b118bf7c307b94d402358bff904c6170e296571855d4374f932a6a603abe74dcb0ebc80c4acf3822abceb8f619f07
263	1	183	\\x4f8e095141aa4841981077189124bc3387b89178884db595f6ea040a6f5d3b9fa05d6dc0d9c50c0a463fdb129ef4480138d5317d4d14193e569d44647dac7904
264	1	116	\\x16941d75ff4c790ea2ba38d78db183e03347e2b1655e69836304f0f998d45d2ac19ffe6ced4f0436cb88acf34006311e485f846bf3b19f85e9ae24d22358920a
265	1	124	\\x555001a8eeb55d2e3c44570fd40ce3ff45bedf595620d469ac2edf164388d5476c13337687958b86ccce3d9f9ec3e5be1bd84640fdab007625430f221d57e70d
266	1	252	\\x5cdb6de2bb74edf5bd83c5cd0a443ae9a4a81829961860c948265210cebd3123627e1590d9bf8f9a53a809f62f941b4507db69c6619b6c800ca6609ca280db02
267	1	219	\\xd1a41925f182418a350bd7eedda7c42da0710cad62817ecd6220ee13f97b3950c214bbc57914d54028873289f86d9570572636cf0d8e633426d83dee18d65306
268	1	424	\\x6e9fd473983d6a2e2c5eebaa92adef868ca8bcea05156ed89efd85103d58b315c18191c7cf93489907ce58b176a2af9fe8ca17043e5dd203fc8610d78148c404
269	1	79	\\x428eb9f4f33cffe3ce112469090a2cb36516e297985e9c49527c968e33942a071be7272a6c5c0c9728a9e59df0f3a86bf9f1ba2ba67b0b4dc755e9576601a10a
270	1	324	\\x06152008cd81d891c0ce400315475eb20ab9c732bbaf6a8b58225e7af0518a6d719e12fd1b1284a9edd3a4059aef0fb355f2d31d1830ecddd6a2316c708a8d0c
271	1	288	\\xad4320027eb0a6ec4d3e904155016b98ffc6f3d7cef7242c43206d32c3b5295a7dd8d1b447cae20105bcef200ae13a37ecc2a654bfeed0539f5def5aee42f80f
272	1	218	\\x069710f95dda1544ebc04cd92e013d32d16e2b7b73b4f586add4281334eb286f54cc1480a6a5d28001c9726c50fbe2bbe2e8359f3e91a33155f26c1b55a54203
273	1	259	\\xd3416808de035fc7a69f5fd8706917429021598a5905b31ed85002c66141434cca4327f65a9354d62f808e7bef232716158f97c7aba064399b118e8bd3ff4906
274	1	52	\\x9325757fb0452099d4806417f3285f1e9b1db7f590383ee2ad916a6d151544e65143b2de03bec42fbed4c05b11bab9e77b209c993cc9403462667e0fcd54b300
275	1	86	\\xf5af9079002425237bea8e4169a08ab9ce4075118f90e03cded159f63e30c1936dd5e3b532cf8d5cbe3b33e52c490cd2a124bc30c891c56af2917b20c8d6c50e
276	1	107	\\xe31ea9b0488f9fc309da3c788030ca48e2fc1a090211fa341978e800d1d2e5ed093ad876b866cdb78ec79630aff0490ebe0ff44cff63f8331cb35387e2bc3e07
277	1	342	\\x8b88ee51653b6c8f86decf4d85278f6e5e6e7f3ceafb454faf5eae5866a77bbcf2587986c7fc33eea8d995fb020bbf2f64c4c14d337fa67012e94a665058e804
278	1	227	\\x2304c7aa26f8dd1a46b7d770a1b6c9d4eaebf7875bc9fbf612f066c715864ddc08da4ba57e457fd1861afd710700c5a058ca85e64b337a241ef1a7563694960f
279	1	226	\\x87ae529612a9be7c8bad87381f603b47b7c03d3e3521867306e1a6bb8555c95e1ded80ae30e3f5fc0cc7faa94197dd97ce5470776a5ce392c4b154331a5ac403
280	1	355	\\x4a803dff1462df03e753378236341f3de307a7b059f06e1587d8947107735f93df2a716397e785dac5688d5eb43e9bc85d495faf951aa41bd92e8922efdb3905
281	1	283	\\xed7ea85b48dea9a0c590e7d048626d13e61d661c8ea1f753f7d533b90d3cc729aeb1733cc9b8438dddd886078b42cf91af8c196e32538627330b29bc76c73c0b
282	1	77	\\xfab28ffcbed40c1e15f15923c5ce2ce8c2df97d6ae1a578009782e50f1ace7e6bb29634f463f0a76fa334379b5a04999a5fb50c163d7b9cabf655838fdb27606
283	1	207	\\x151743205fc01a14fa4e81cdf22f5f3e57d4112df9fd0528e8785e0aa3ae5d2b366d929a7a090c72dfb358ec310b3c6ae9051631f57701c9c8357bfff9209d00
284	1	419	\\x4e67f22ce4eec18d588872c4e7106317176755e606e063c46d50d4c09f2ee68ab96fc1231e8b4581604427208f8704cd65d8367c4b1fcd42984770ae1e2a7701
285	1	9	\\x89237844e060b5fdbbf03fed373e5c11ad0c8d0d446cd175e01b4837cb48248e978776e2cf9e16e1c54477cce515134d55896f315c35e3bc0375274f356aa109
286	1	297	\\xc092b4b7b13df0640459f8b0752eb2330430077b2ad043e3838fea59a7f4627266afb6b84193daa2577ff4b2c0785e2e5c0d909f4dd8af6df747579d392ebc0c
287	1	399	\\x59c4bfaa36bc321c871c72eb9eccf95157324f5222d65c0b4fc333107b94f607b328e34acd947cc0a0c98701ae35577457dcaf72219930e6a851c8932e6e7503
288	1	381	\\x2fc5973db8e9932d10234b07f266bbc54673d0d45c2420f02985ca24404a1d1966a494edb5677b4c3b34cd2a59aef4e833c4121efe27432d0fa30ba0fed2b30e
289	1	391	\\xa344558cf1fe0ae5c5b5981cdf3ff8bd3c21f23e22ee689d6c738240f25c2a2810f7e9a89387c8467bc7657e6c83f4158494a6a033df0fee766621c5b579c506
290	1	63	\\xdbaa05c27f4b12df40753b56ffda5d24c2e4f7bb765da11e23114f14ec42f3951e5b77c1c2e34a783a79c4865ff29289002576aadcf64f485c0e3701ab6d7e0f
291	1	128	\\x8f5c0b5dc479c379ea0b78cd77c7a21ab71c341df241b33a0d3a2883380895ba72f21d85e5352111671dac62ba35b96f8ef9b9415294ac3fdf6d37ccf80fb302
292	1	174	\\xa70ee7d0efe5a8a300f8c58a7efaf453f33c52031f9276c1b0ad52d1bfe2de8530b2136f342ca2328ac53b5f04626d244421efaa5fbd7b89d5aa3c1e1a3c6a05
293	1	356	\\x22ee48b4c9f27e39aeaa850d431861b6b0a9a430503c8d4505fb8ff5795137658cf2326dd41f8181732004101207083dce25b7dcc963364fa078f07bb4d17c0b
294	1	234	\\x860e027a14edbcf715ba4024bf7ac738f414f45304af652f09ae9857b48fd688265e7d12944943c823bcdc41c15c7e73711b84028ba93cb5e9c3b8fda1fc4b0e
295	1	390	\\x6d74f597d4a54a2fd8e93c07951e0942930eb97356a46b92505ea468a90ee9e422cc6d1852da28ac1fd14590c3ac5a0e787b799744aca0d0d2ac7c6d993c0803
296	1	274	\\x2b5dbe8631acb73fe73a73084a98799c19c480249064d5a0e5ad41026b075764b72f794363f42015d004b6230db9266aed682d3cb64942bbf87d8a82ea5d4b0c
297	1	374	\\x7f6760abb321508db8c68df526347d93b9cee02f36d8b3cbf38ddc3fe124a2ce8db50ff3cf8b7ee919845624aa54313c158cf904adb5be6a15831d7994fc0107
298	1	179	\\x90076fa3cf12a4110402b7e18e457b4a692feca5495b25c900168ba4498b0777d01e75889c57a66d498ee3eda2cfb29a79a9e3df6817798c0d365911190d0f0a
299	1	394	\\x4a8990f1af4bcd79900f1abf35911b9026f909d4e47076cbae0b6c6b06385184f4633f4ca47260855a89a8307cdf58e852312b81bb11d2628f8d44b0bd1f710b
300	1	235	\\x354cf15965f23dd2a2c57e6215263054680734f748726af1665054e5148363e062f04948e656054268eace0d77b61d6ef0c175e8963029572976d01e0345090a
301	1	357	\\xd609d72526aa9bb754f67db5b30eea6fb982236067df77f72cb87d4d1cb706843480fc139d163a90e44cf70c322b22ff0c716a8f3ff86793be129aec63f0d602
302	1	230	\\x7460c6311f68c9f3df248cfe41e2f912e2ac69db4e41e30a10b41d2371dc974531fff4cbdcad773abecd156396b63e3c86b55c1b8f46f7f5aaac476914c3010a
303	1	59	\\x84ce4ee3e61db4d110b75ce30f8222de8b922d6cdc799349917351ae5489124a4acab301cd1e483fa078dc0a5534e665eb08bf4e745738519b5ee49c78fb3501
304	1	281	\\xefb939e7fb7cad5e7199fda77557f07713afeb54b72367eabf18e26bcbc9a4dc730965013fb656ce7cfd57399c2c657a232d96bf668fe5c5577f2df65019f507
305	1	315	\\x8eb234cd05d2ba48e38206795e29119b59e538722216be33390402c64452cfe97db1632c0da4519073eb01ae00b3091beffdc3f6caf46b4534b7e64397f22902
306	1	66	\\x66c8500ec494a3b19422b5f2e32b6617518a9e587ace9900d64b5249d1428a7c07488822b6d285a948db833a3f07ed08bbbcd3f6da3e737588be6d67af193406
307	1	141	\\x1d796d06e6713ad2c3216f7f4991efde551c0dd3bb46c018312a43300d7ef6b3f6b24bb381c4c313dd0265e77911cc487ce5069a3e0697295f4f446e51a89f0c
308	1	173	\\xcb4b46364d5ea975eaa240861233bbf6dd1727755159d048b936202c4cd988ac06d67af7fe99bc82d8d9c9bf0cf619141f4725220c87796b2061f8c03cc39b01
309	1	378	\\x88a1f0e52050c2c2013d698226a15579516a860129093e3a6d68d7bbf62cd552d8643bcd9ce62f7465b09d4664d70f0bb54deac749ba87283bced031862a410f
310	1	133	\\xcb22470f9c658a2eef5374d3948542bf1b18a21b8317425f23b77689e8c871aa53bc642c96d663464f0dcd8d013c6a977027500b8a9aa92c0581f52e3d4a3f08
311	1	421	\\xbd2ae9a1b3b3764bcc818d265c74e140332f9f799f92fe5500c9c544e7e87cf4c1ceb6f6cfa187b36dde1fb359c9b642f0da742b22e02e76dfea2e989e001b0d
312	1	122	\\x37c1aff86d4db7ddfe3a58236458f11e11bb3655e571cf1967533a7eb5e29876e8a96d6791f47dd5bc10988ca57ab834d4a8f1119795ac4a1ba68884772acf00
313	1	90	\\xd93a59268a7c1511da9c849967603e412bcdfaf2ec4d14bcdbd61be34992795a1c2563ce48b5476f11b7313ed952929376e6a82cb72ffa630a661b08e9621f07
314	1	343	\\x4eb8e1b012bffa455fed3dd9b370bedcd5aed08636a4de759473db14a942d384c3a03b4f2afadef2b390a52973d4d2d3deaf91264f1a59e03b9d4faaa1c49206
315	1	140	\\xe0b2bbe48a4d406a436349b977708bee5c0d548f560b1e5dc230bd28ef87c4563335de74200f01a3eacf23bdfc9965088c6fbb1ac6586d6b8ba517bfba313b03
316	1	94	\\x47db17bbe6cacf605e84b2c6c92ea65bb516ee3abdd53500aa39a7803e7ca648b1c8f22a0e560ea1aa50dfcdd7befb130ba02bbb795b612622d7758679186807
317	1	328	\\x7df7d4c513eedba5ab3dc3e23c8ed423bbbd679ae95c375f5616e2430f554d8a62c0291dd542b03896c5cc223109e8a8321973ba6f0c7a0df501f51bcb52b70b
318	1	144	\\x73954af7675d0afd15ef779aa2e48f3bb384e8fdefa3964e0e7446b9fb981976ba00d53e6a62fa2eda7dbdf9d988df6d5157ca73aec484d3b1e139cf4a75ec03
319	1	403	\\x750115ba3b011bad063e3235e3c1d50fbc107067d80c410f324844b65ee40e8212632db7c865e4fbe8e85de78c7853250576bbfe46666966eede86bd21350201
320	1	212	\\x5242ee40ea63b1b0299875d2f50de7269681cf40c7d9dddbbd4e4b8321aee6acae091e53fdcf1d3d36ee1e9b5bc29e7b0ea1dc994d7331541dbee3ddbc1f650a
321	1	308	\\x978731e0b95330ed6fa018031249099d3a48e9f6e041ebbf548f4a29c2f63437b2cd2bd2210eadfbed51d20d50f720bdc72583653911a37b1dc0ebe1f2986509
322	1	4	\\x87080365539346cd85b2fd662440d5635ddc191458baa293d2b4da09e282c2c9ab5a4d29f97f1733540956464aab401b6c11a54362a6d1b409f34ffb2f33ca0a
323	1	271	\\x33cc6c1e487080755d49a8bba2e20e5ebfbe685f37b79516a21fc11c424b3a007ec63559e7374aeb9ff197bb061bd0ca3b5a18912ce9f2a05608c8127987ee09
324	1	329	\\x9c5cb8c71ec2da3680d8594a7bd664ce16789ac7dc8beac960698f26f6e51160bc870c2233f0aed40b689e62ed307b8816c0d47dfbdfb830dc3566bff1a7930e
325	1	130	\\xc642e42bb33e980a9851b21c45ae4fb9f739d6893455167165b1c34b864ca537e2ee624a015a3c27652fcf7f8aa2806c7ebb0fc47956380c62dc26563e51ad0d
326	1	146	\\x814e7db6b706bc15d7d348e30fdf8c7e99f753d7c2579b80a2352588c2afefdc501c2188efcd867469b319ff9aaae0e3ec6b5861ac636518c6f2e0aa5399f20f
327	1	60	\\x93a5502764e7a6910665d87c9f9c6eecbd90eca5df3d13433a3e4e0579cbd7f3349c54d29342acfbcc2f80a701e398fa9100612bc89df7a79a3181181dc26c07
328	1	134	\\x1b64eeb5b93b4ffa308bf24378d4193f978c47c4da2910344ae106233c6adf16dd12a783a4a8658f5c68eae9ee20e0187072292f218571f785ccfd3e5d9cd608
329	1	206	\\x5114f46768f8e7f106dd5f368f66f690f58e0b1e3120cadc2f02fb528393d7a2abf04e0c7d112d64c07afd84002211f0e9f43f19a67693f4446c900788acff03
330	1	161	\\xde1533e422c26a83ef0c15a75bb6f0bc3387b2ce375addbccc8c3065c4e26836d7f211930adeafa4663df253099614a9c01aef933acb634c6aacbe64a4150a06
331	1	295	\\x7c6e2f23629e48569d1efd905074fa4ba6449895ee23b29299e71b58bba18c6859ca7f122d3558adcce6189fcee7ce823a7c478242bbe369a0fb0fd56203f70d
332	1	96	\\xe5bf0656dcaa2c51b991c441d0f85f5f3c5714ceb4bb6ba1c6190ca07191224aea4879764cca87b7258a5a458f18676d7ec43d72c110d31e386a67279443f700
333	1	170	\\x5c6ca0c259345351c59342b6f3a5c76913ceb8226a6d0de33b8abee345bbffdd1f4e23593f59f4bf8bf0c8db0ef22dcb70cb9ec7af522e0cf8cc825683b00408
334	1	166	\\x5f51471cf419108646af035767c35346ca53775e6029c3988747142efbbfd28f38da3de233dbea9c1616a55da27e26cb884aaab5e3511781526659039f180b0f
335	1	57	\\x583bed414c9e38a939388da1c115077045ca1c662250bd14767e32fd61efb792f11216850adf4aae4d2a5ad62ff48c4ed6ed6f382fedf7197b343523231dca08
336	1	273	\\xfe157a9d2dc6be8661f6ba3c91ac0ee8c9e6b5018d47d1f39add0dbf0c50266d36d619dd2a60b837a07e5ceb94a1f03f72fee7c908d79d52c13da7fe6e55860c
337	1	51	\\xb58c5a0a97891474fea34b56982dc31a17d4fb79bedd2d8b420e1073fcfd67bbc6e5c90a9132fc1f6d43a089141b2ba836c314793903d52380225f06a434d60b
338	1	108	\\xd2340e57969f24b909e2c03d0e0f07ee19f8c5e72fb2e95008d071c21129360f81fa60c38f5c485d6575fdc8a4948b7d6bd7459311c51359393c9b53ad49d40d
339	1	287	\\x5f125655986be5e8e73f0026dd4237c4f93186614468b1a5284c32b51b99a630c2ce500c485689ff9f070ec6f78997dc3a1df6cd097af820237828f3914ef701
340	1	260	\\xe1df89480c337fa22863697bffe7192518a6480c3839aa3578e2dc0178e0f4b992350f43f04723f1a3af15ba67eb97f93c3913f98fe9b409c55c3fa2edb1e40d
341	1	382	\\x0938efe18fdda0a31b6ce1cb1bb10ac07eca007c8afe072ea012fc6a463e36a69120af4749a2a60ba1326eb2fb18f95d57cb320c890ddc1894d8d5aaff3f2b07
342	1	158	\\xac79bc5f09b062517b0c3e1a157f9d8a672c74bff7d0d90d2da33d4ae6aeca2af7e8c1c920dfc1e31dfe2b64b35b7607a1ecf8c7e7d247e6911f2c964e774804
343	1	243	\\x573228ca9bd1d2f8871f6a57156f6dbf0aa55b1425a9a04a36c7e4e762f34504359dcfaaf038dc5d75b3d8909788bb2f84b57edf56ed4451deb841406dd8c505
344	1	17	\\xca151af0ef34ddaf5e1917fd3a967c7f1cc5801b2a63bcc01fd3b8ee889af7c5ac142384a22c9456887c17b629e68c9ce858f484e97c11d1b6c202d5bd12210c
345	1	194	\\x7fdab148b8b1476c92ab30d261979a9d16d6daab60dabf679c6cdee73710edd742474432a88961ac47037b93095eaad584af0e69d8783f51ee361eb2c1cf2800
346	1	139	\\xb824ae3599f7b894477c1662d8344be94c3778525fb3ec0f1a3ad2c0cee4b0e3670d766bfd80d6d11dd15e2d43e449e35a12dae6c3b243a3c3c2244163650c02
347	1	48	\\x5a82e35019b5fbeba8d050c1cf141c7e666c2cb9fd4a0968198b081daea4fb35a9159d92411e37153a6ea2b6d0b81ecac276f019bd8aad52adf26063a24dd606
348	1	129	\\x51c6b7c194b9bd0fd630a55648f24d356f9ded2559d43a32b90c3f2f4973f85475b5ced63e2505086dae72c8f01f15b2153506bce8bb4d4163a68c14ce4b8401
349	1	76	\\x4b1d9ef0721478277d16c5df954fb68a2bf5200e659f8532cbb07b293a307d848d4e2feea3b5651147a2a49e39a2ce85d46c44b3c9c4f64ac9083cf9848e930b
350	1	22	\\x4dd44a4cffeff08eeba0f903d6f84c9b160f9ddd66ae34e5adc40d537bcc20cf53c88d64be314964569a440f587222f77489c2bc467d82839be4d17f7bd81806
351	1	280	\\xf60e0dc93c8d94506f8d8e7dc4fbba1a1d9233a3231852d2d9f388f229d27709d38a33c8d2476ed5bafef18586f140a9b950a74c223a8f18a6520bb707279809
352	1	251	\\x7e26fb9f2655e02366dd68c41e762b8e19821e74bc1d4cc92d651361f06a560f36d3400de9841e2b53f07147d978b6405c77bf4a486e06611ae90843a488ac0b
353	1	241	\\xcd642d3c9b86e0c294c3c1d26a4df8f3d5e401122fcda67dae3fb0f2db2d5190ecff01ba8284d2592dd7ce239ad260f807b63a47096e5596a3b2b1467c7c2004
354	1	35	\\xd17cd3b16f29a0570e01484d13bf0e9dd7a00a8c0fce9ae75cacde8c8cd8b3628d5ee3c5b037f465d9072823953b61e998c5061dfc22744ac5cbf74c18d80907
355	1	364	\\xb00d8dc2bc741fada45593fcd48364f6b9c9e45bf11bd9ce631b9b07061825deafc8b4aedc94159f8ffef98b0cbb3bb77ff5b34018017b97186f277643f8b906
356	1	318	\\xa701222a15a5df00c129d8e7203d97bb89f2379775633217600a6492ce653930507c158a1e11074ea6cf5c88c1fff4cc6501792b6002f8f123bb2d72012ba703
357	1	321	\\x86174203a1c659328c4e92baefb6b29af3dc1cfdc1dd85e08d359be7756a47e12fe5ed4db1dd2bdb322e5faf1b6694ffc3a9ba4bf58ac06cf48f9cb3ab8d7307
358	1	196	\\x4ede51decb245bd0d4e2a575193a530764dd7530d33cabc299108e6c298258512814d12022b55d58c276ee98da4819dd378061f6004c0c1c5d261a1f4c6a3f03
359	1	92	\\xf2babc3a02cfbdcdb097e89e6da9f2c7126af0f7865e26c8ef8ef755b92b5a864dac8cc17f07678a6683b8e604e3764506d201f31467be6b921834287357c10f
360	1	43	\\xdf596ca66b5df21a75afe017993a8e74fc149514bacccfee97ab61091cc8ad2c501103ca63476db6658706a8a6b5d0a79e07dc7944a761b05a66dbadf2181c0b
361	1	319	\\xc89f90ce4360fb00517fbeaf0148f2438d7e7266f474a448e73d513b9b6a4599a735c352de26ff00e537a30dff1562875915d4581702f855d0b00e40e63d1309
362	1	152	\\x69cf8c51df8d2c5451e84cc784ad25137c301ca44c3cbc02c39b42ac451cb82281f80227c45237bd454c72ca3d3292377af41a7fee7595589723f22b2e7a6506
363	1	257	\\x4f17e55b24c18eb9380eb6393a6fbcf2d478d7e992ec7f9f9e72753fa19e5c9caa448d13e9c90321aed09960a020dbf1c69b7e1ad65be6b32c3f9c71cc24ae09
364	1	393	\\x12a9848d024a9f5fb17025e1acde421d6566809175d6ced76fb76a2f6257209bc78d4fa74e104776b3660f509263889ac69ca059f5ca0694d17b172461e0160f
365	1	341	\\x5cf9c142afb68a0ae6382781f75d6ee1c4739dba63e3bee37f0fc5ddf8a4c19662640818fb48c75839781113cdf979f7e95e386692c7cf0a84ef092da2f00403
366	1	123	\\x83ebfb1a9d5895161732c062ec1c65eb2199ffa02cfff9ff8585844c443de8f4003694811922d14a762a2b455c9dee417013058c40c4eba1fdb45ab7e952ee04
367	1	302	\\x3113c29efd21a8fe3777d204955b72193a231afab1df9fbda8c9ffe22d1b8796671ffa5dd958860e99bac617e170938a61c9486ab2d0880df5b2f02623ac2f0d
368	1	203	\\x5640276ef3a72955507465c9296229382dddd3e35b9b539842f13e3a032fca1cfd348c227df059ae7c2e26d9ee0a94856b63cba88254a64fb727bb40d96d0c08
369	1	372	\\xa9fe50a573db4ed7700bc8641d7e80e96dead02c0819a9ad4233a853bb6a7ddaabb446ae42889005062608170d900c9bb5159e1bc28f39887fdd002956958a0d
370	1	187	\\x03bdaf37d27769836bf490a0517a570a01ddec9443815d8f3895ae6431aacb9244384f9b2033ee3e10b84aed478bdefafd6065fda280c7adca37c7ec7b5fb60b
371	1	276	\\x6168a07b40aae6e1eeb4d108158a8c9ee85b394715a05a64c2292a6b800bd9f8f1d39a14f45c8f1433768e0c38fdb715c0e3d297920786c4b7dd87dc39670b0e
372	1	248	\\xc54c9ffc4937601be9dd8014c3342827edbde97b2461a298eea2f9138bc9e27be9eb3fcb9d80af45d544d2eb73281c75a72d9a258ba6ebcf1664e011643f4d02
373	1	340	\\xc41d832da13a5860d2b19093022a67e6f4b97597ff877bc9c1458ca0c1226218ff090f3d0e3eb0a8335144faf6a9b55df9781b65d238e13724d75e5594b85308
374	1	112	\\x0536c1970c388ec24d4bda09f63ad83b156563b54a25f9d0d7a11641ec303edb680b4368fff59608f4916369de9d18e70a3f5dc00f1420fc2d769afca3cfed0d
375	1	245	\\x445b73bf4ed65a76ac3bf89e7d935d850845850773c0932005782834f2506fe4122310b3799baf0db9379eb5153d330d8548caf6bbda6a260e20b49382cc4c0d
376	1	135	\\xa916272f4c88f5d0f54467dfca8f5715174abcd0117e1264377e6b9aef72650cb8eef63ae0a8599bc0bf7b1a9f0752d8ca9bbaed4b0e9215601ba7733169f302
377	1	398	\\xbd88a6e842ede43a0008e96571372372d716090380108a7fd1a9596c1159bb9c4b93879f4f48b5a3da68d7a4e947035d40e4a7ad63a7c4b264cd8e9d9a978d0f
378	1	30	\\x3c0ba580d0b875c3c65827f87056ee616cd7172ab4abecb315d7a5c72cc6ab2b4244165cdd5374d8b35c049d893aea9598c707b2a0729662798b812f17a34a01
379	1	325	\\xaba39c4aa676722ff05fa63946b40f5eca64612a5dbb6e13d3847187a95a663d8a978094f112c03ca5441f01fc47354e3c526938e5377e3830fa4741a4bd3f0c
380	1	151	\\x3510ca496254151768dbf35b215653e586b35707123348a43183325b1e9e45a5b5bbfb0d7d3547533ad006cbd5b14c9fe3f2dbb156e5a8eebbfcb44ef73ceb05
381	1	82	\\xf34281fa64e5c317cc80fc1de85e5a1af2840cf6b05b036c078b0f1125a4d162b2cdb1fd2bcff1831b0481a667977f23637c4a27c869d85acfa67e33f0215e06
382	1	359	\\x069af8ee060540518ba5b3d53abe37194bece1733cb3d22000906c906382ca41d280675d0d289c778b32aec8d2a66054ac07488ec55d4390c6b4ff6c85774801
383	1	148	\\xbfbd3ba0875b8eeb5fc7e4620515d1dac1eb4bdae7ca7899653154774b34df9866949d883e648167647bf3cb51aac57dd51969497f1c6294ad6629dd1660e901
384	1	344	\\xdc4f27d3d2efe0684f7d1bca206d951b22081d687291433d17ef1ede65b33fd5bfdcc5ddb57a6da9c47a662bc42d7bba52e4b3bc0abb7283c8315461ffe34c0e
385	1	160	\\x1fc711ee86aed686e380e7ae73d5f37a5385ef9b01ed0237e7a690f9baa7106e96c26fbae3a053ed6dc53350ea1f490f3bdfda0267f0175fe230fdba404eaf0b
386	1	275	\\x8e72bed9dc3d21d08adc8de4a0ad7ae83999623c07a3246857c18e79a50dff0db7d80974feb49fb6c3d0be4ab11efff081eb2cc684303ff72f6fc0823e850607
387	1	392	\\x9dd4b6f34b336e94f5ff20888c93ef772deb70b15867ccac3607cfba256e8525b25b62a553caf2a50f03e6fb756a866ca2aadf92d996190b47dbb1eb0b5c6104
388	1	408	\\x28e1490346845e30ddba21327bad061f7b95671350d5fcf9367b5dfd9ad4a0123dd284102f2f667bc3536cd05f5d26b016a951c2867df88a85f858fd51423d07
389	1	402	\\xb55119be26a68558683162744a131fbb3052c24d3e8cb52d072459473221c85234dc7e28851abe155383584bebc08a2cd709266108a61be5e2b5a61485d96805
390	1	117	\\xe0667af9e955dc8b71f2ce88a9a468cfe49e6ff54a600c693301e93916396ab7a01244cce1fc49e532f3cfde96b22b506471d4895dd809986cc5441a99968b0c
391	1	385	\\x8478fb6463ba5fe08d9c7f99f7806bfae98050dd3c816ba2b01ada79334d575bb875eb1c637ba6050b71ae073e88d7be231623a60dc6cdaf252a2fa731ac8302
392	1	327	\\x1f293ec453f4da85d7ab0153e8ae17926021b42c83844aa440dac9267c9a027886f790457a84bd70a022d97fdc55e3481ab520c5491f23b3fececc38ab746d05
393	1	104	\\x3121c8558a1457748721b3ff401f9249c48b504f979d352e73ce4a5b9c6aae069708a993e7c08a25f3e50a4cea8bd5e1c1d3def3d979dddb4e6d475445114401
394	1	125	\\xc6231ffd2693eba1455cdebdd7d7ad8640aa34e6199c3993b11ff0441ffef6f535dca75ea3bd4b531fd64eacb8fe0544387ccddaf9d1d886943f3f55f170c004
395	1	354	\\x5a600f84f638eb1c91f9ca183fbadbfe9c3247e5b4928ce92f3dd64e0cdbac4d8c6dc39936e9e52450e98589c50839cd89b7bb6b13df2083417edfbb27be5202
396	1	386	\\xd42189095a5458b6ccd99581b3d653eb76fba87c88e560e98bbe2e1c047f64e3472b7aca353e137f4ccbb397f5fa39e82e605ba126407158e3b25112d270460d
397	1	322	\\x27ed4ef5f0b2a3547b1e26b049f9a75a00e2a450dd67b644a8aee56dda51143aab45430814050a0ada4aca295a78b892fceef9bcd9d541f66478ef50b2258505
398	1	423	\\x2342c858dd0a2a95ff45e8b01739ac182196fa8b1f4d0575a5dbec619c889d41d89a23a14bfff570d5892b792952a07eeda7735f55ed9de2bf3388ab39ba5b05
399	1	131	\\x3d50c0d4ecba3bb57c8433214aea9e250787e2c39ed40246de92a2c07e98b52566e724dd08c3328f16592cf800d09f8a0b85b66304f30bfa303d0dffc6bbc309
400	1	346	\\x7228ac227a98bcef4fd8855183f8e45a0f6c1b6f83ce5c5c7bbe830ba0ba7776fa02141e094f54d63672ffc1bcf8e21450ca65e1f4f44362ba59b98c11c3d301
401	1	175	\\x5a557f0f1796fdc564122f479aa6ad320ced84f47b4a5eb49b1e217f3190bf459274f9a71725a8b3b5f0c3ee6c750d55a6c17c29c31a793d68d7b93ddb9d190c
402	1	12	\\x3a973eaf80b01d3758fb22f1857cafe5eb40ebe44da9da298bc66eff5ed2076d3bf08a9c6861b2778d0688bfff49d1e22576b57c6faf2cb0d43f20b144ce150a
403	1	351	\\x27a5a05904df5547356046a10bf9fbfdaec59e54c6fd339c8488389fcedada79a563b6e6758be4f8f823cd3486b1a6a6b7a47b92ddf727a6e6c54e7f5743930e
404	1	326	\\xa34a7c776e6b46ddc26a6f31eea7d02cc4671358d862bdb6402520cf7885b14871f59e5b6fecb41987c721c6b52ee76ff2e18c44891c9411497a517d93e2df0e
405	1	32	\\xa0742b8da28fb344fac59a5ff21fd0ecc2307d778037a489aae519d0dc997a80a2ee7631ba33c7bb4e426f9a218e102f5726177283124c92d54073d3a7a10c03
406	1	147	\\x7bbac975ee330fb7b7393e40a44705e5ecdd5e56f44487e7f69091972104f806f4f7d68239823f37e75f22f783d4256a57814e1e961fa2ea136185749683060f
407	1	232	\\xf7fc7039f091c1b8e5b4488892ec1f9fdbfd1f80d69c878ce285b4583fa4cb75c3e57bc84a438957de203deff8d321893d47b4aeea3dbb13780f4c31d0b9ba0d
408	1	268	\\xbe9fbe7d9659356db4e7f7e0412422c67dbbfe97a5d2bb72b3950142ec383f8b75b63fb8e28e577b266dce090cbff4fab90f6905283417b5ee362a8543bca606
409	1	375	\\x0de423e0f4d7f07a238101ae7d072ea6e663e5ba2a3d99b710d7d6a315f4cf3605d8598c4c3311d52161a6ec12e69c1bd693ec9c75b39d5006fd9a9bbad5ed06
410	1	23	\\x66c6f0a226660f7edc587bd1494829b668c89a00ee471ebdf7389bb011232ae1a66d574f1d5b4cf79a984dcfc2330db85c174fe4bd09989ae4f4fb51c7d6da04
411	1	282	\\x6cf296e24b181aca58c920efc24779f2a6ba956f90208ac33f965d1df54cf71f345ca9b69f103ecf6325fc4760a65081de2df810560c3a6f887823f9c364900b
412	1	84	\\xbc6a0fecbd67774275922e087049aa858b1ec90923bd06d0bf9ce0068d953408596bd6348a00e345a16d1c6783942ec286a16fe89d73c74c52e665efeeee4b05
413	1	127	\\xa78eb81f8be2f82def65dfaca6a16284d9d0cee8344a744b8f9aca80b745207547fda9859a32abc33a3d240104e7b156f9743466dd1d789b57f6a8891c614d03
414	1	25	\\x951a5976dfb47768e9c0753ed2ca0fbf34ce82f6c1b9dd3039f4ef775e9ef5e9bc883862647c45e6712a14d3fdf67875cbfda71ead3a2fed5523cc3061cdaa0b
415	1	181	\\x11f50743d6c77d4627298e7f8d962de63a71a0ea0c7b962958792e0690e920bd0e1a38c08d4e55919546890b67a3d9e6e578e1b956df3dc828eeb6f61b77c70e
416	1	138	\\x3e11f23e1795178a08fb825568c6a63b1726f006e636e354f5622ca7c1851e553ac2916ee2f3ffc608ab5c6b565b85e2b89e8c2d82c4f7a9b974820af461c70b
417	1	56	\\x9052f0a0b70e896ad8699272b672a351a742dbc25f5f8d5f3c1a26af277d4a927c594915386321f1f22f52c2b653d79e17cabd7b2f91a7aa78f469845bdb9705
418	1	369	\\x22f2b6880cbed770d4c93096667eeed4c9b291f4e036ccd49473919b196a40a0f611dd2176029d4d7953e1c2ffbb6bfeb802b78da009742c8c41675340ff8f02
419	1	190	\\xed152088596b8df4d3861a8c8d2c04c588245efc6d5e9b2d5ef36824db5a30547571513ca0cd9f40d633f86e015017b3709102438294d195d6da45b12d3b9e05
420	1	292	\\xd61f01fa3bc82fb3f2f586c8a22456f20a89a75206af3ce6e21670520f5dd1c631a65e94ffaa8b3cf475cb7b6fbb57ed849137b73119a888297f5b6c07240402
421	1	253	\\xbe8128397fd99b594cf670f35163b5791a48bb50b97801882d1276554a5f28bfc1a1f995d47fdca995f5f41e9969bc6181e676affb0f0d116007219290b44e0c
422	1	195	\\x7baf85eff1fd11a4b20f0783db90e96854f69cab9b5eca77b9e86b500064b6f2f1ce50fbfd8ccecb05429a7167ef525d2a24a813463ea3c589b9819fdf3b9802
423	1	240	\\x6885565ece2e23a3986b890b8983f109efd99ed2214df44579d9c13d687acf15dc70bff985f9112a4fe6781f0aa2cddd64cfc484b8394f299ea04da375483e05
424	1	250	\\x439e7ddd88e99799d61156ace6b3c4df60db67be573aa298390c457b7ffe4911efcdc03f19fae4af9aaa5d2367e5ef6fa773755471466a58d9072b73c08e380f
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x97fd67147ef0874b823ad6c6df470a5f098a1b32c87c08bc51a65d675b1239f9	TESTKUDOS Auditor	http://localhost:8083/	t	1660251767000000
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
1	\\x00f83320a310bda5919bd82a343bb93f08ec5d2a88f3efdd5092439c1dcde4296a782a83da567b64009cf8d60ce82b301744d3d0fc2f2422a108500d277a0e99	1	0	\\x000000010000000000800003cd7eff47e81b024588a6b6bef7d8274c8c6cb0e3c830be26eb0bf93817e6bf13346036a85b7570249b4f6f44182c4b940862c509bde1177b3ee37a457b4038db88dae111f80101ff45a8d12253151a829794f03f16a0cd62109573638e0f8f509184a186f8ce688fe7648260df4020932529f9015eecd369104754e19b24102b010001	\\xc99c83cfe72e8cf1744ac750fdb6f3a853d2a0175bdc06bac86803e1607378d6b20cb6a9ef8240e80d6217290875d6925d5d553c64d2fb9ef67b502e53169909	1685036261000000	1685641061000000	1748713061000000	1843321061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
2	\\x03e4508a152cc349dc2d4c7829befc4d157a5daa5ba3207159ee1291c372cc177a4303e1eb7010669547529a8d15ba6c9276685e529f9eb19ec92545c15757ec	1	0	\\x000000010000000000800003d8e156915bdd885503ca9a80413ce231ee48311be170946daf9e10873a171dca89f7e77d046054d2d48ebbbcec3a9cac5c3ce787ba13633c6134d98e7a3e5dba269d49780336554d424c2b5a84e314ed91c63c9bfde9902a34b0532ebd48f64891c1a32b5d873061380314bcd2c5bed6efb83fb052d7397abdfb37cf66298cab010001	\\x170eba3f62cb0912afd02c32d856946bedc3acd14e80f79f595108247f7732b08e64fdb939ddb6305ed61ff66c9b19c464dfd403e09c28fb47109cc09144820a	1678991261000000	1679596061000000	1742668061000000	1837276061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x063092e047658d9d4ac5d0b35a2b2c4e1b7dd2e6244b9bd19ff2a95bb8db1fd21a5f4dae3e14eab632830ada43216c653aef3b8b28858d0e911d1f8a1f29701a	1	0	\\x000000010000000000800003d5e94ca187dab40b7cce602bc83b99c88051aac505ebadc4aaa02253c79858fbb084842b42936bb46b3feb736630cd6eb9174829f44d3adbe6601fd516faf5a78ee744a43f15267c90b5d96f4f78037c2a4a39cdd6c0a99cd1dd41e00446dff0e2b250058e14a81bf5e8628038116ad709bb97ed799ff4cc55d8fd83aa60920b010001	\\x2ead994a3518c4b54ebd4b5c52ac507465904be866d5f85d24ca748544f92db31d57d6b4ad6adcd78052a6db0d9e1642a671a0979473d7a111b5bf2e4c164e0f	1678386761000000	1678991561000000	1742063561000000	1836671561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x0720e6531868e7a376a2564738b4e1db7616b466ebff56bacf78c2bd86ab72193c5fe270898e94716859ee58eac116d614350e47add2e43cdf6ca034b1837b3c	1	0	\\x000000010000000000800003bc29d710fe64b48f2e4b26a81634e9c16d1d0c8e78a6166d576ca67500abcc1a55e7d080f18f97b8c788649a6309c399178239e71ba640cbc1ceaed8a681d131d012cf1a169659b5f43e3311d8fc7cc860886f4bc082c7abea5fae04271f8e9846da11bd1c892f695f93ea57c625ca0814b58bc604309f85d377b2a6d0c4a073010001	\\x057a70c943758bfc72b6d8e41e737c1d7a4a572c520a2a138dbc53d0959f8d5a090c2bdb3fe3ef24e46125ea8633422b734edecccaefa682215edfa6edcee504	1667505761000000	1668110561000000	1731182561000000	1825790561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x0cb438c17fdd61baa7d5e7497331e7be66171b84ac2147b1522f7a02f95359e0f89805956aa284e43bc27bb8da700d2cd3a7e29dbaec03dfe19745d0e79fdb04	1	0	\\x000000010000000000800003ad070e7b17a1c0eadb03b7ad7459d035e73f41ba618f2ee98a54aa31630a5fea24ccba0349c8b46653889e8ec59de027c5c030581fbe0045576ec3b4df0440d1091fb3e38447924ad14a8e60be4af72b8b93b7d849f32bad73b30f0b705aa1390a50ce10d13eaa665f5db441aa129a25b483849d174e60548b1806f316d72899010001	\\x3b717b17213c91267b752e360bc82be3e3f9b140d023b3fed9b136e31f0845114f28056179faf0e5f5c985f0d035f3b0863289312f7d097ab5879418af6a4d03	1684431761000000	1685036561000000	1748108561000000	1842716561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x12483e5b2d959ffd90c652e8711e64bd349c9e85daa6a7dc2235d8ab8e3f9d5ab32fab7300eba63b978a9bca14f79222c6cce2a5ee47c6c5084e2fb8e45f2e47	1	0	\\x000000010000000000800003a905a4845158cf8682404f51583898f417b7502d094bdde7041b754668a3f787a893c8aa28d428b0a7d260909123310b8caa91708f4a8387727e784d0e2f15b82206f274024d332a520774b6dfb6b9894e9dc4c0d3727f9f68531f05772808483e37fc6ae8fce6b23f986e1271eb7224935ec12b16f609da3eaf7f82dccba3e1010001	\\x03420aeb39d208cde772da18ae441bcc983fc40a2229f6cc1f6b39d1834e11043d39ae759a8e8fbcbf10cc674777ca6a82d3983f15063d878257651c9489b100	1679595761000000	1680200561000000	1743272561000000	1837880561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x14f4442f64afda64ba5a9cdf9b1d6f43c938831c63700d00fe8c85b577bb92e290029fd3b6066154bcb156d0395ecc7a7ec521a6c4d384d830b44aa2618981f1	1	0	\\x000000010000000000800003ca6e62551167beaa16ba7fcd0a7811b5028faf33f6efac586489ed7c2df8a3c047e60e95681c60cff56dc6c1ff876c29f5fd0db886ed0af720affc66048ec4c1e4910d79f150cd5a4fc94d0150fccaa8f52ad3e65875543a5457a550a33529721d2a338e5a5e09aff91864c1d66b5a24778a7b056abae485b30d3af849a79acf010001	\\x68971cb1b0b8431065bf08e8203e41d8eaee320a8eed7f64837391aca3da58edb6bb223a7ba756137b48138f6e69f41a782a9b2097026882d1565284a5027b08	1682618261000000	1683223061000000	1746295061000000	1840903061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x2018490448eb449c3dcd3dfb2e532711e1e0a4e6e9acf59489aba53af281b950fff83b98ec2b76a653c906a63bb98d0e66f223ae72b4746dd73897ac8f2d59fb	1	0	\\x000000010000000000800003e6f7c00925462a37371d47da6ccbdadafc024aeb455ad9db3d73645b70b59c357ee163525377b9beaad0d6c51cc6a4b08cb72c144d1e8778d0c1251598a41f5bfd4b749afebc14466b902b0ecb2952a63306d5714b29c05ae6b994856667fd5c137437a9080f4da615c7eab965379b343c93f4c8243c596e6978e12f263e5ad5010001	\\x38c03483c3fb9b6c7aa5f93d362640ab7814fe8a8a75b01154da2e7ce0c6b9755e5f10d567307f530ca43582c4d62c181951ec94443ce42d754cf581c6c65d04	1685640761000000	1686245561000000	1749317561000000	1843925561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x206c3119de02d04137b81c226b7cfe5bf488abf92c9cc927367bf47f4caa2b16121ae19efbb30ebfcb7f826068cd4c79150bc1bd0bdb48c481edbe21192c7d38	1	0	\\x000000010000000000800003c3aab36e540930ff0c05c8fafec4520db48f5135a6f01a7bf4cb2c825f89e41ec9ec1f091c2d7c568f3253753f8356d525c1d460ca886939858f9a2992d24b369573cf8197118258b96aa5ebffc166935a14ec6859fc2fc17f9e9a65a6e53ea825314695a529898dd0cd65434087a3387468134d87cba26bb85a11b71bfc7b01010001	\\xff55ce6e8391b39e2d6f276bb2504d8b8cc33a0cd7530007911fd866504cbff40f08ff4eb31151816d0b4b1887ec6bed475984aea767bc3dae466e172a666f07	1670528261000000	1671133061000000	1734205061000000	1828813061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
10	\\x2494b34d0975544d791193aca423f8fff3c33075f11747c6e4586c361ac9eab7fc0dc609d0ab2b2ffa03045339605ca62b06784dad094ac4b36467be0145e0ff	1	0	\\x000000010000000000800003dcdb2b3a343f547c66eeb107ece75adb7e2b848804a398d2967862f57b6846ca98ab548c858e196373e9a4e6606e34d5a64a097e658d87a05e177ccbd045bccfc1d29f19ad98779f80075536af7b6bc64199cbd7c7fe6c02e9f5baaee1f1019a2557eb84ed2b7e24b1b6c2f410c12dfbc3bd00530b934c1452cffc0dc0514bd3010001	\\xafd97cc5afacc22590280c7fcd80223afc65ae34c08a236d4e4d95759ec91c28a7f245e874903e83e98988bfb006ac863b638e26da61bef3b766dfd2412bdb07	1682013761000000	1682618561000000	1745690561000000	1840298561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
11	\\x2b708d76c58288e13fb19bfb264a3279174066ae45755041fd1d6261dfdb77092ce683e7eb5100178956d1147667454640afbe5434e571b34d78f30d1c4d6ab6	1	0	\\x00000001000000000080000397d112144c6b0b58fd1de441feb98d2460294115e05ab09a7f790353baa8f99f9de859a2be007e9b398308ba02ddbd0c22acd2cca2196ade6c3a0be808c8c91f114dd7d447f492486d83df0f46d5961247f40f1f869f40d38c3d5e014abfba29743ab6d5e2480df16e9bf0cc83feac9cf224c5de3b66724341f7f77e57dbb3b3010001	\\xc8d63e0ee78c09c8fd91d81e5251d61dcb573a59fa6e83cb8c57f7dae42185fcee52f96eb97b84f4fb665fe10c17c8a0c15b0a0e2ab8ba6538fcd238db750e06	1672946261000000	1673551061000000	1736623061000000	1831231061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
12	\\x2c68866d9f232f507ff4ec6dd33cf85e050eca721c409f8550bc8605232c32c5e415c62ae005cde7953770c54a5e3ccbc51fc6b0243782d27807f5a2e040b166	1	0	\\x000000010000000000800003e2f61213463ed1b2144c9d378cdbb11513398cd6c1b7cdc58fdead71bc1d2e1bffccf914b345198f81754447feb051127689c3e590082e25fd3f6bb8aa6883540fec89e11ed7c3458b49ea330f6d065c36042298180d84e83a5fceb67bc59e58bad9fde8c5af2eaa07b43e006c7ee24bff8fe738f010acd3db98bbb4be52016f010001	\\x603abcaba57cf1bfa653c9ccffad28456de094fd74dfba5cda41fb3b8d493690bd92eceb2db897843f490def10bc477097bf1ec6c63171b2eeea511f9a37e20e	1661460761000000	1662065561000000	1725137561000000	1819745561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x3014bcf08f3ce969b1448914a0438ba922f9af72064a110a98f066fd237b99c0d552ae0dd66e68d1ff7544a9464c185fb032c78d5744e70af9857f92280d098a	1	0	\\x000000010000000000800003f51f956a17901453aacbf82cbc3330a2e757de16d837c9ef4fc2f0c26636e48958c4c655f71270644283ac7265fbb3eeab33d84192930b7e497257d182b785c595da75dfa085727155274b5f23abd6321d11dcf8167137b26aedcc50f2cff13ee0093536effd74bba961cbea0af8a2519a64d9d8641f7924668132011dd3172d010001	\\x0910d7c781a43b1d43ecedcfd949ea3555a973fe86305e59e2dc56d01fb95cd7e970bd285d552195420eb1baa577ee790873719cc18ddd0f21da6f087609eb02	1679595761000000	1680200561000000	1743272561000000	1837880561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x3234e2bdc4464031df819ab3269cfface20677bdf64d789ba04320f0829386715292330ef7cbc39e8895c48f1a63197604006690de4963e485eed9442d6f184d	1	0	\\x000000010000000000800003d955f4850b1a1c0816f9c6f3a511e4cabeb1485b431d5b8d1c7661f05778510da16a606967a1d58288ceae2289adcba8191f0a7a95ef37428f4d26eda3abc179b55a25ccbc2d9c9e534da0caa32fc096a8fafe3a462ff06d4de8ecc7c33552eb84e34a8c9098bc05cf297b3455aeeed04e1bee508b9b62e9c9ab4319737a3451010001	\\xe0fa4290a3fce3a1607519cf73c5eb0164e76c966627f0d398d3e805a47c5585d60e7f65b13dcef87e652e61bcc71f814fee8f50cbf75942bab9aea0c56e1604	1680804761000000	1681409561000000	1744481561000000	1839089561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
15	\\x3454d1f5c48e58263433087ad96848ded0514bbe1820de63396d0f0f643052ef9280254dc84d2d7ab6d345cc88a605f5c3139fed414b1542080cbcf49fed6995	1	0	\\x000000010000000000800003ba2f0843544a6d9e593a5f31561ecb66a605c80988acde14ea61d8d0b7589fe92c8143e3b3b74b89db90c1a8e7132ed09951305d073213347ae67562642901a4ba8741803e173fd3e24ea2ada915492a7b12bee83b92fc6f54952e8ac49ffd015df9aa05e6b070ae01aed8bb0967def53f1af2e7385d8e58386df1eb29a7dfc5010001	\\xa705776dcfffc0a393519d14b0a17f44bbb4ebaa53b78c2aca5861ffce61c15386d8486fc41975c5790353e896adf25fcd0cd6378eebc2048c6f9ccd0a21e40e	1677177761000000	1677782561000000	1740854561000000	1835462561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
16	\\x3960956a9e533e594a6a7e6fbdcb924dbe86b519ce4868e103282268a0cbda598c2b420b42c32b549804f2f37b6784bf70d62e2c1c290b30574b435c90357e74	1	0	\\x000000010000000000800003b0bc51db3177d1f16d97a2dc4a605a552a0032a646034b347f08488b0281436b0ef2c5afb58501289093717adeac4bb23fbd0f4ce6dfd03cc64b93e22a57e729348219399cc777a12b22a5fc0ba363d31771009f3e9c211f6826f997c70b418db043014a96b9016c699abb7211853e370fcb1209a528e70a8a1ffb90d7bf6b99010001	\\x02371792b22ff2e478fde3c4f38892b7cf5302aa5303d5957f25fe281a05cb897a45511c6bff9112a51ce81fc800bd0bd7c7a0e51fa202988e4592c0f3dd640d	1678991261000000	1679596061000000	1742668061000000	1837276061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x39f83c1e9a8d1989d8c8b1c8eaf16233d504dd5db4d483ed5aa71a2bf2b8cb2d11a1ee60dde54fff0fdfeb72e5a7aea07dcb55c4c73a42ee65f3d36054d00972	1	0	\\x000000010000000000800003e0fdbbaa95a890e6978eaafc52364ee9fbbe0eff46f488e811b9528a55303c3768b22614aff38df6f56447c24dd7372201b9c260c09a4e21336fb103f65dd4e7efb28b25c150c292d124ed739d77befc73f14b0af84e20e45f746739415ef5725426d1d152480c1c24d04fc0928f2431996494be7a8445cc70f8b44fb5849463010001	\\x674d7a2cf4b547351a58bfccf095e87c79d710ecee3c6216b66a4655d031642d69b4b13e17f1bd00cd4ff63f82610975eefa57c6c5fb78ab8ff2abe61d025a0d	1666296761000000	1666901561000000	1729973561000000	1824581561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x3c04e4a747a592d05e3974b7ff19222decdeafae452585288def3960a595c4254a2bffd0fb32ed3c17455c71770a3eb4d74824f491d015142790852b57808c9a	1	0	\\x000000010000000000800003d9ce0984afd6ff93925c2ecb2874d46f230094414b42bf472e1045e363ca637a372d324d867e46f0ab87c0f9ee5b6b5058d1a1856dc1304b4b491a41031ad0fb6f70e12dc789afd5ec8eaa9b35c089c73cdd61dd94632ecfdf5cdaee20b7351dfb2f7df8712f92a254a3fd4b988218df14f85630f798d1b31dfd911b48eaa4f9010001	\\xc326733ffa6929f40be4b1d8c04d0df24b53e4033e68409589e55fd244a5dff09bff0e1fbaff9cb245a172ea5b071a159480d587c606fca745e35446fa5a2f0e	1681409261000000	1682014061000000	1745086061000000	1839694061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x3f9872155b3759ee2f810feb3cebefc141ace05addd018e0ec4f2d5257228c25ac7adb958e900f800c96de8cf58982fef001c81b4994587fbefa75d8bd5090ba	1	0	\\x000000010000000000800003c1cdc6a649586b4facec1a8025149cafe7590207dd2b23a814faed6d0c8ecc645e0d852620f77dd929790eb2b71d61942a2d603643e43a6ea1e8a886a4a569fd7658bbd5f372bfcab36c1b9d9db26cd2a7444dc7f459adc2b2d377fa45ee1659a4f78c85d880b52992f1496481eb6f540819b430ddea5f8f2474b50cac3ad25d010001	\\xaeed99e28d2ab0b785439f806bd27371e37d845ea6029e2db4ab0c95eeb72174ac6ff8fc3beddc61db621c8584da4463b27be8554aaf642eca7e2f61bbfd780e	1676573261000000	1677178061000000	1740250061000000	1834858061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
20	\\x40d4930e772aa7db75a22dbd41d0e2ffb6ef428e3db274385b44c7d1423c6415e357297bd1dd784abaadbc47546ad518a48570549257a641fa4ac6bc6ad40631	1	0	\\x000000010000000000800003aecdf47e7f5873af07e7234beb225172cbaef562c7c106fe273c424738b017d5dd8c641fb859e70103e497bc564ad818f5a7a70de2530a7ad61b6ec53b2d404d9f97a7d20b0f96e5b952f70f3e10ef74171f978b4ba04dff3803e58f4fe3fd57629d4791e2f9b3184a66bdffdc92dc13b426f7d2d0ad2b920f857439a8164e89010001	\\xfdf17e945a2ad03336c5402d5d08d512a89150a7ca596d6c8474a10df400758db19760126ea03df362e4844ff986b959fc56f755491679de87c1b3360baf480a	1684431761000000	1685036561000000	1748108561000000	1842716561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
21	\\x47f06352cafd25790b91b9c4aae6d8aaa5a6ac5c7ec3f49c8d0d9f1971c334be6e75a8ef87f564216ae742b937d09e8bae5e94c7f84c4bcd77ad473f4f7480d1	1	0	\\x000000010000000000800003c4f1d2c768292ede84b9ad2180339166615b30c64d9b6b1908c8144a1f85ff386d8bee6246ed970c41e642070f34d69080d65499ffa5ee914a511daf8d03e6d27e73f205a345c35cccafa05753cc74e51a90024562623a60bc07b00d7a39bbdbf09ff73d7c9033202149176342b0226c77a8a40170321d1dc1e2bf363604e41f010001	\\xcbe81fa812c6ec2a6ac1676ece48176f9edd7a1b5e4fb80fcf9d63ea38bb7d53b4c841b5f26c73405c7496a9d8f6b1d98cefca68ced39a9a855f3af38c11d909	1683827261000000	1684432061000000	1747504061000000	1842112061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x4b4863b602dbb5776ba10cb6bf1a9c1ca6b9e7ae6ecd669cda9dbdb617f2d72b64a3445382039958a4be5a95d1fd8a775fa7fe4cf36bbdfa66c59960e7179baf	1	0	\\x000000010000000000800003cd5ef6af8113004625f740f9811966808376dee444f9eb77176d0c1880e6999af72ece2b6db8bb1cf7c8b1ab6893dd4c40febd02217fa1976024976db4b01d5685e3459d031d757928d77c19df06a6cadc0e9b1f7e076793857d6428f2d087615aaab1ce14356e3820b168de1d0f732c60f4f3e052559e53901762889a50a331010001	\\x368cc626cbd881acf3548b3ecb13a82a84c381413bcca2f990c3fa2045071d4c2a118d1087e01d603ecc62db4f1d4c2d8a25e5669d778792fcdfdd425517800a	1665692261000000	1666297061000000	1729369061000000	1823977061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x4b7097b0db328da30f011a1e73ab9d97ab1a894b80deb5f158efdea454a76bb7acbdc8e60f4296e123c982995cd250e7fc9a8f56731beb464048f1d805ab8b43	1	0	\\x000000010000000000800003bddfcf4cac1112cbb96209c53b0ffb4b183003abf8b6dcfb354380c240a6e3ef27545cc7a7eb5d886760b3f4933b5b5ffbe754749ddbe2c986ced78e799cf5992e9c373d26699cc96c67abdd94043825419c7e95703fe7c667a9074f1faf52b616da37a3b00a340f86aa878e5a10a3a17e4ca3bcfa0259efe6be10ccc4221199010001	\\xc0cacc5dfc225e4d32456778ab7d584f07aff18134fcbd09b59b04ae8c168cf8c937ce3d43a54e0780225151960bdb1de28c968a75a3aef87d2fa3b5829cac01	1660856261000000	1661461061000000	1724533061000000	1819141061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x4cf4a5e819ac738420c58e7dc98a373767a0347b44f473f3152a02bc641afea1a994c8d5fca43245551855ef4c3d4475fc53b9c9401ca2a8a76d6ddc013d1d21	1	0	\\x000000010000000000800003d4415b93ae5e6ed3ce13f85602411f6ebc03861783fc227c1a7ade785fac81f6f40d87de874448ee78bf7594e866738166ea9ea2403548cc2630c9211254273535df1dbe139bacf418aba0b144f84905ae6f318c20b0228e8608dc3d6c82bae992c274ce37d4a765ba01a3f2da73757d7aa005b94a7b193423d0a2a1ae2905b9010001	\\xea6e6e79dd511962f55ee06a5c9888db655861af81ae745b0e1e252fc8679eefb7862667a7421837fad388eb4483915bf8aca3cd311a970370d0e9b445628406	1674155261000000	1674760061000000	1737832061000000	1832440061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x4d04f97b4689643a2d6d8fbec496558f86a2ff5952edb6a5cfb85bea4f0c34ef075d2fa6133b3c7c41c2e107b4eac8389e5afa354fb982ac380f4928738f7581	1	0	\\x000000010000000000800003b70fdce3573edd77d76ef6fb012642aea1fb7a27905532252b34fb025ceee4ef6908128a9a2828d15e6376f37137a0dd46bcb9ba577c53529b867b3fa0911ab55141be550822e8b3617b099e50b61b618f87ea42b32063d0c6d12e7fee09bb900c96410293a757d5416463e1f7b18356cb0de66b837a73d1f7dac219fe3deb55010001	\\xdffbf7b3889cfb49af4e21f9c4839eded1359f68dee2f2dffd426689e74aae73161d9b13150db7e2bbaedc15ab9894f73645a335ebac029063ca02716603860a	1660856261000000	1661461061000000	1724533061000000	1819141061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x50987659d6d21be3123fcba28922a181702b39229a3ebe0b52ebc027c30a0ea76f082faa559c8d3ae8368c03696b917b31ad8eced80591c372d2ffd1fa5cca68	1	0	\\x000000010000000000800003c4f5489da6965e9386a0b7165085d659914d0f4fb79dcb0d0f1055959e6daaef90cdda3827253820ce815e19b12d18047f40815146c70ac1cfbdaaff4804f0d5a05d4aae69c71043a3ca8acb907a4c7cda62ffaf8f4b1f60cf1283091db679da0e5609cc42e8ccea84367efec8d6c34676a4575c12c8f9b39628efb0e9330293010001	\\x211193742a40417d9fd2e509bff2bffbe6153da237f1c5e364a3d54da43dc015a0a2688de948caee6cb9d948ea0d4dcd62efc2fc7b27847dae9de2a8da54130c	1687454261000000	1688059061000000	1751131061000000	1845739061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
27	\\x51300072e26d4d71e973e9c1118833d00a274271a882f008e5f6892d998e3906024011bad16c69ce00afaeb92552ea765f3f8c0b2e3c6cbe94fd4230c4f4105e	1	0	\\x000000010000000000800003befdb2a8bb5d49d8bf62d1aae13946ab1c9ca229dff6cb3860ad2298aedb926412e4323b7efd71889c01ea32dded6c5e7ab604ba4c48be7b44b208e11f7ddd49692b5c2cc2c60b1e3a6b1321fbd5615db92d23ba5c85ee578121696c611e89d1b9998a3be1bef09b101a27bc0ab480b0ceea6f58f38253998ced2c5e0275394f010001	\\x370f6f42b1eab697f429f5229cc85622fdd27a376bb054bc5e2d3b36484958e12bdf10247aaf18d15abb37b89415a6f6564a99cbbad7d3e1fb5194919b1a4b0c	1682618261000000	1683223061000000	1746295061000000	1840903061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x52846834b4b0539e826327386f33c5db8cca4ef081e12fb042e9d3d1a59700d187a368f1fae0f35d2a21e6dd8a098cf4ee2609e6a8f86f86a153d0b40bac29a8	1	0	\\x000000010000000000800003d4c2acce4ae6906fead7cb3f85a7e6fc3da494492d1ba0a1e50f3d17dd051b2bb4551c2cd3743629f395d0f2f7635630dfd5d2cf2c8f2480d543fe6da937926f383022124b2b1e95c4d1668ab0fe886758d756abe2943fa514323d14b4261ba763ded4ee0dc98803dde39f48add55f248356aac667451da7aa420df5977177b1010001	\\x0ac73cd574662679741904e4e9788af4644438dc1bc4b73da7c2d5c48054e6e554efdc7be83c851988a9d204fcabffd7e0cd2059fd6870460403f3a0523cf00a	1689872261000000	1690477061000000	1753549061000000	1848157061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x54ecfd070436bf8a042eadb01b14655c408f2b9de12e38ef0b194b276096ef057ab6dc268e3f1c8d9cdea047df198210c7d63a1c8e6ce4c75a10e64db514ce30	1	0	\\x000000010000000000800003d107240dce81584ff8e947912a725b233c7e49b07fe873977ca364e4c79d8db317f5118bf78f22f92e98cca753136b927408cc93d9c4240303d8f6455f60187173c85af04d6c830b1e91350a11a23681510edad82eaa526b3e3efc684d898c98fb7b73d2a85715ac5113ea33856d84823cb46cde51ba97e8e186ecdfaabece0f010001	\\x58d9238746ffc35758f4a1685bbc654c94b54392a10a00a009b2700c4c94e17d9d58b66ba96f61172ecd8977d4b0b6759a72d028d7cef4b3dfb50888e787b903	1681409261000000	1682014061000000	1745086061000000	1839694061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x5a3061ad0fa9ecac2b44fff3bc7f4ccf02caa4d7455558928d1a5600b766f40a3356cf1be59aebf683101ea79c276766b4e0e004e157d7f85c6210a3be4766d4	1	0	\\x000000010000000000800003b12940b415af18486452f75a6aca5544869913a6612989240a59d2b54ea9c21ba96cdaa114b46f460f5ad49b38995f4ad58f8eb56099825fd6d6b9760c81c5299cc56cf52954bca69b23732f373f748ff11af6afb0785305eeab89a453b550e010d5a9014d8bf600c39180edb74f8b1f3d6319438114310beb56c1e9f15260bd010001	\\x4c4bf7d3a034184d52f1c15beda1dfdcb7498939d801024176e5bece5fffeae62ca96d2a97e482a2d3f2bb5384c1374bd270e4cf48deca9014dcb66320da3300	1663274261000000	1663879061000000	1726951061000000	1821559061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
31	\\x5b54e4a97fffa7aea7dbb522be7265c7a5836f07bca6261f08ce70b2eb7575d09ae567caf583aad4dcf59b58dab8004cdc33e2085ff37bb1ac00fae573b4d2d2	1	0	\\x000000010000000000800003a83d73c2b371b33204175aa3cb3b485e7471704097c3e5baf0b5b4572400fe7f280d4a2e56d9eb432475446b2d5c869974185cf3131daba71a6697db97409fe6e753828e89847847aca5573a10177090ba313c41644eb730b8d23e77810f4048b627bfe214344235e29f5461d38d2f74410595f4652ecfdabd92bc9ca1b4b06b010001	\\xee394ed4520ab37fe8cf998ea525022aa68466a6c41701cbddc330a3e78891e1cf53fe84c756974541e09720c4d9842c133a497b6ff9be08eb9c38481a1a5504	1682013761000000	1682618561000000	1745690561000000	1840298561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
32	\\x5ce4343e27892ee8cf8fc514ac5dbb0c2197edc40cc98e70c3a2864f56b0e944f39a1e133a37c21b921ac95ee8fa2b30dd24d7e6cc8afc4a55c7345765222014	1	0	\\x000000010000000000800003bc2b0ae564e53ee606b54e02809f36460900e6ad59134e0e855831f5bf10fbe65905ec37da927b6a2a8044dba20e0a3494f003d44c03ceaace7f7184d513f1fe3d38495f057c153a868edf341baa79d3c7ea03af5e4643f9abec10b1e72ea9591bda484e083aea314a43a84473282577b4a6029d6e18853b7920d51d0d8f790f010001	\\x1672f4e96fb9c8df213869c8291772fade5cc802ceb04c98b23be0e3f8cef6bc2cecf72e04b485a39dad8ddad98ea4f0dc7fe157ab4f13c6f5b9aa31bb447f0f	1661460761000000	1662065561000000	1725137561000000	1819745561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x5e54a23c6e7ebbabac4a8c20de2700e708cf17a92a3aec6925ea65e1c33efccdf3a9f205e2322cc2f3e2ef7432c75edbf5f4ed3f8fc1cc125040d629bb404a1a	1	0	\\x000000010000000000800003db6ee807afa39473980b7913d0ee9f6cc748a6c1bf3f5018b53bc0bd91217f7807bfaf01e7dc19a4dfc430bc82c81002cdda9a2d604fd47daafcbf854201199f87f74c817f6a7e424cc1f53ea19e3661c5e9e2fc738909fcb3f684dbccf54e7ca4f9b64057c4e648f4f22bf7428d6d55c410855f44f08fa2879c388cf24b444f010001	\\x11ac8c6a6ac555f59dc24fad0c450ec6abdae589f40e7c6e54a6adbf3875b1a864bea7493f7cdf504d42d74ca35303c03aee3867f0b944ad98a3e10c29482800	1690476761000000	1691081561000000	1754153561000000	1848761561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
34	\\x6320f7990a9337b9d8b687c6990ec217efe6d0a1beb06906b6579badb2c9d09ed13d5b0ea503c8fc8820cea55d55106ebdfda6a0e722325b88c507ce6b53e0fc	1	0	\\x000000010000000000800003b49fb9f5db9e8feec912adf7cb4f914dd96f4e0590ecb72525c2478d2515fdda99730f80f062cb14457a981ba407c88a4a6085b21e19e1d0990ef1e20ecf357fe2c0de336d7ded72ec85ef74a044f81380d465b7b3954976765ba742e98345067ec41c8222ba10a4436375ab9891ed0a5bf19d888e1a4227164fcb1be4d4afbb010001	\\xba56d1442aa27950e164d001b4055c29331a8a5637491ead0638e3ca4b37dd195fcb6a323e00ad2800227b75324d845732739f6fd456d17da7482fac0ad65805	1686245261000000	1686850061000000	1749922061000000	1844530061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x65ac7db601a7f400029a14fa20632f1ac877680786f662e3806779fbc07ccc2beb620ddccece5f55bec0ea4287253e5903b4a709e635138573ce0f3fb2f2b4aa	1	0	\\x000000010000000000800003c8bf7888dbaba469cdb3c926763dd0f772b1d81c98eb5f014a21c6e167d2c4beb8b260cee67cc7f63ad506bbccd85e332a7a1e1533abece945bb93c271762773204f44697057ad3dc11f7f9c297c4ca6625f42d60bfb8ea39cc068df20abff6017ab9f2e16aa1dba39389758c275ec43c4f7512bf7d959ade3edfa2b8c94455d010001	\\x523ab70b1d38228a3492fdca188fa54103b154ca7e5bdcd408b20ccc541536846e36abf5bb96f2481a30d103aae79e84ed8691bdf522c117a1c1ade1cce5a100	1665087761000000	1665692561000000	1728764561000000	1823372561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x65c02b45e57e628156200ac533739401ee81c1eec76a433058417633ac55ccae0b90bb1a988edd53aa3bd678b4624dab9bac12e5aa1eeb4a7b626e32be402feb	1	0	\\x000000010000000000800003e61bab0c49c35d66eef4dcd8b6a7cfb97fe4cfd3853d01fbed10d578d1306f1a36ea6a966aee1320e48882091519bd3cab7a96b77ace17824e99a9e1d2adbe3f179f3e90addccff251c819906a511d10351c9c6018194944494355280746965a6998f182fabc7a7bc7867a5d1b996aeb2e325d15f8104a5c8cdecf41f6055b77010001	\\x547acb80c8fab9586bb50c48cd4748dab97c403cc3330b839393b46c3bcb4d6ebc7cd17e45925b9edaf4df270137c07bae03803f20b3faa49a9d9f0f6c676e01	1679595761000000	1680200561000000	1743272561000000	1837880561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x6aa4df7460ec89c5d41018f116ffc0c5f91c4ad078ec1035ac71c48d287a5c0e759da6fcec837624ae189ba29f03acab4827ead0efb3fde24b80c8a748519c06	1	0	\\x000000010000000000800003ac774454009bf1ff29c5d03cc46f2ed146c8438ef1ce6f55a06c17dafad1c878739dcbee69fe3a03ec29506e48bdacb3e126a993d057a643da480c2686e5ec42a184b0dd6d26d38744e1e9c66423b91daf7acbe2c1ea1f864673b33c4785e218e20d0009df226ec7b39411a5119baab7be31138c88ba3cce893920d049a9f58b010001	\\x83da8fb8797e4db9b398b29f2b3170d7088141f90fece2a205c26e88916afaa481baf068f726bb4a7b519c1cf6fa8790e6e775f921cf7567163b1b95442a2b09	1691685761000000	1692290561000000	1755362561000000	1849970561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x6a208fa941de3f67a5e5c52189997bb76884c19f5eb45566b5a68c97ba2cbb4a2ed8b1c723ef84ec4baf0e197ea278bc4ae191124dbdaceeea49f9212e9870f8	1	0	\\x000000010000000000800003cb96e1dd0ca518cf8ed659e005e56c88cb768f141cab6606fe5c449006c48ba0930b3b125b4680972ff81469fb8bc09bd30f0cfa4a471101ecf3f9cf67a1820657215135012456c1958228171936abbd4de17ff1a4ea394056b3597e97885b310c90e345a0d2f226600e142ad754c12d207229d268f76ebec72cafef41b0f2eb010001	\\x3310cd3e1f129388ee690a4ded0d3a97a18526d315c1966a7d0186110248d3496823bbe15b38d3c3ea58ee64b480ffe6797809a65ab3f607caacf15694a16c09	1683222761000000	1683827561000000	1746899561000000	1841507561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x6a443fcc3d2ffa747ce9e0d201385b3cfa122ee1d1728482738a82797e52ef637961d58ad7fe7060918986d180cc0a3c0f4a6365aab77e0e57f88d76ffc0b7bb	1	0	\\x000000010000000000800003ce71bf30c90d4a562062e614fee2ec29965b2ce167a8f5c3a05e23a93d78938f548e504ad4e67202c371716314f80b9dc5a31c597f5bcd1b5c9030170b9745583371481ea187d60797ca43f6efe045a04f004e84b15acf7c75b6a0faf86a9d1baee7a8a500a2a7f56258af31408083defff56b57d1aa7e8571b7520add8bcc45010001	\\x279a380da00aee6b9d79cdefd74dee9c8dc108fe716ed19dbcc5a7973d4ad7d0a1874cf4e931974e51a553cb75a73991884f9ebd36aa86e25bb6435fe842e109	1683827261000000	1684432061000000	1747504061000000	1842112061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
40	\\x6f5c3fbda0fad616decef7cb157c30a29f7dc0d7e14ac10f03f939ddcddbee92a81304885fdd9268bcf31a72c738144ea1a8b60181a4b7b9b3444ec0fc61e5a9	1	0	\\x000000010000000000800003c1790972b6fd1f8e6817f5c7bb7eae99ff5fd36240dd4f39d8fb2416de1d6bc136a9a34bfe6da8f891116125d583485d00a3c94e19b9c58021761c7d3f4784b8d9533d682ef44f925e8dbec42150a695d1ee35737f5334cd0a41d9ef66ed89b2de22e65ffdee0d4fd4c794c60801c87be31309d3dc812da4f91c9aa01dd015b7010001	\\x919bc99d3a1551ed68aa96818758f72cad3a2c2b6beb63399a23fa657d83c60fafc298596bd6fab889e2b6c2c8a3d0247fdbbb5c1c7758f742e2a989bdeaa50f	1685036261000000	1685641061000000	1748713061000000	1843321061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x739c37a1b34b4cb898d0fe11c7c71e3611251900ac9a7c980d07dd26b8b3f580064911945dc086b6ecb89f07815cb583d851fb1d3ed16d92de44e2e3f0f946f9	1	0	\\x000000010000000000800003ab808a218874b178dc882c2dd1800edad204185d10ed8f01c4a2c9518a45bc51ae5ae1aa8b1b26791e8eaa0e4afe81f105ba176f838c8aa99c4f5890dda39fd0ab4c5a7de23596152b83f57327e5eb413b32bc35fa034c5be7ea6e05c600056b3f846e54411a8986144a5268efa55c40adbaa58887be7397bc6f58042d2ac683010001	\\x2ffa24dbcbc8eb86cc0474499ee83ca4e93051a4243199952f033c0d9cd6657fc71e99f39b5dc09312c92aa6360ec0cb1d9961971063ba868f9bb9067889f00e	1682013761000000	1682618561000000	1745690561000000	1840298561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x7428be110b5bcd1e88677ca065ce5726bac70bbb78fa31e4cfd092a9fff2b7374ce87e4d5a47704709d71507a19339eda2971858fc515909c24ed19cc29cab51	1	0	\\x000000010000000000800003a4ae259cec66f792b6711169fa236ef8840c09bc6178cc0b46fc5cc1ffce91596abe67669d90692870f7caf332300601e3431600717948895aa5f4d1152bd61b5b339ae29c5660a5821a5f824b1457a707f9c9c33fabd0c8e94407f25e115d8fdeb3f76b396e8623face0cd1393fad614358220db77f414c12466b00249f0243010001	\\xdeb651c3b178d628571a586484658c0849d4e7883603589c7988f6bc808a49941bab253bd442ede74cea9a2d68258c91021a44885049d28ddac9b85d77142a05	1683222761000000	1683827561000000	1746899561000000	1841507561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
43	\\x7ce8643421a1a9bcb82d31a47b46c9197338f735d19d926d6838173daf300f38f6f4267b361db29ea5c4bb4b8502a12abe5ff8f53ab43fc21de145143b0571fc	1	0	\\x000000010000000000800003b8f40a7ec467378b6abc13b75abbac08ff67fdedaeed1532dd94ef8bdd71909811b6c404081dcdacdfe6f94312d09206260adf78f42ce71bbbdabc18c484d4b292ad11fcf137c0e1fb3d7e76556b682946f472ba1014e66d0ff6dc67a8770272f9f0fb5d7290e39ab5aeff574c0bbacf27144bb9c8b66597e076e1550839bf7f010001	\\x8fa6bc8a4faa0d8694cfc68823a17e1ad3a05694d780afe4e24e740567c22074d59e9cead40cac39d92af1a2da313bfc0bb342f0075640e00d304b24aafd9f0a	1665087761000000	1665692561000000	1728764561000000	1823372561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x7c0c29dc37742ad8a7088f616a5101f1dd9693f638a097203358c1ddb2760bc1f9af5b5489b2fdeb98c5ea8d30aa62f00d2c74e0f118458f7a5f0f9baecc3f1e	1	0	\\x000000010000000000800003c3d569062425d176a2408dd13d869205d8ab0a9cee088746a87aa262381c2015d25364152de528bc90c05e0341df6750b4e38bfe492d21cfd2498efeab7075f6fc77cf76ec88fcf61ac17eb05af8689d3f013cd94a2fccbcf29b8e631fb358ad4a65ad0fb537f0b5d6b272e4d30df77976d3815aaa3437f51f3ddeebfbf5787b010001	\\x8b50142dc8ef0a5bd8ecb4189ebd738a5e5f4265e89eb77c29f9d9e6e65d320b3e3bced337c668a2828ca7d100c9da5983a19719c4bae028f6e6f744336d1e02	1691685761000000	1692290561000000	1755362561000000	1849970561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
45	\\x7d4cb683e5afb1649e5d590f00c55f08b1fa47c23078754c5dd15a4d8791e4c8e9bd8d7fce674ed85be9450a9e4b3ccd50b2d59dc729b4dd69188f139fdc0c75	1	0	\\x000000010000000000800003a9c0e3c6aafe1655291138aa4a9eecae6cc2747ff2c54beb084e8c89ac3c3a77e507efdbe4e4cc8caccfffd2c07feaf69314ec7144a93fcaffabe972a79ae39b2ef9ba0212efbdde87880b6c935b6b3a7ba7b0fb6f863407014f2d826158977a16731954d3e848cfdf63e9f02516aa5510bf4d99f48a46d4294c3596d197825d010001	\\xd21adc1a358e10e5ae2096c9517c99933201f17fa673029fe55c25f3f55631943d2c28cc9c8eb36362beb4044e076ad0dc9ba62dcab2865130ff2580ad33c70e	1677177761000000	1677782561000000	1740854561000000	1835462561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x812cdeb532229c66b2fa26f47a3284045e77db2da607c1ec5caca00d40f04754ab50896c83238cc8879b9f63ed385bd9b704409567866075582b191178065dfd	1	0	\\x000000010000000000800003d56a0fa5439cc3f76d6caa12625a47c85f2b82630b9b65dc09c112897d70fbe69e5cb51b827dd00d012e7e047aa982815d680ddc47a84dbdd2e324307bf1abb69f488741b1a08634548cbd079d2589669f697dd82cefa3f3f8cc89dcecc738edc0bb85397a8729b4e7bcb18fd1fea9082ff636d6ef75aba063e68e795087fa4d010001	\\x5f57d982b90b532a7494fbf5de5a8dabfbd6324d48c838ca0e1a035db84470c5904431653c660de631b331d9edd7dcf2ff8f05471362d342b2b023c3f49e6e02	1673550761000000	1674155561000000	1737227561000000	1831835561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x85c456c0a0d92ddd935dd0e3cfa083dbd29c57e6d227f9b71fa739e94fcc8b64c9c0195f34566f77b79280ae94143cd0ecbddfe7c8a6af3abc47259c73de03e6	1	0	\\x000000010000000000800003be98152d8f8f48cf0c060ec7bc914afb0d8e5a8659b62f489be164cd8e44d023f5865abc70d953d7acc30a1a8fd7589661c038ec0d95ac3254a253e0ec3371bac10b47267ad4c7e291f9f8fc287e62577d9f23ebfbd7dc20e1497921d4c6aaf0de133016f3fad6475387eee5ed7f7cf171190919c305296f8236938e3ea6e733010001	\\xc4ae8281911099578612b06513c1780fda02e64cc268928def5a55c102170a492741f750c468c19f33c480bcb7b2aa9fc01ec95b1bfee39a48803eab203ad90c	1685640761000000	1686245561000000	1749317561000000	1843925561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x85a49ed687e566a8b63e2bb5decd7cd9a8d64e6cd4314507347ba5766dc7848647ca4ffb0ac173f0244d88498ab19ee59d647b8e0f4b428ff8f0d72a1f36045b	1	0	\\x000000010000000000800003d2dbee03c6ffb017a51564d38588d584ea616c00d28edfb20147fc507cfb4000c2547eddd262be190fda8792c18f1b54d7fd64e4909322cf788e813cddf015ad7c42263ccdfc932c1da482aab3bb4d661cab076263db50b067437c4f19153d867091337b3f98e832b9b04875022c184d960b5eed04bb8c89af408505d94335a7010001	\\xe4160a16526419c15d9632516a130fc552b7d19dbc4aad616788ea29cc83e9b773b3a0788b94a7a449fcb9b16c7eeb568162f84042a5fc3c2bea43a98f99df03	1665692261000000	1666297061000000	1729369061000000	1823977061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x8a38db1a6a6269ed54fed0aa70066c4dca02c6db05a792345c05297d845052b97f9f326319f2c1ad4625de8e66c4fc2f1aa93cf2b6e1b80a6eded1af688bd52c	1	0	\\x0000000100000000008000039a2cca59ff63792900c3c198907dafe4ad3a2016608b2d129aaa0eb49acaec77258c7b6c1766377ab95e460445f6ce4bfcd081b0912b6d42afeed7aaa9d31de2ca934cb698acb8bafe49bb5474ef2d307a636e7a763f9d7cf1d7673fcaed668beaec725a1c70a7eedb51bd2a47a83ab125e1cad043b169132e0ab0715435651b010001	\\x50079354b82f04e20ed9304d54b0bbd71906694d8651054612a648f6f164fd430ed7e9bc3f4d42e5d5219d362d4c53a00715aae72a33984b32590a80d7db7b05	1689872261000000	1690477061000000	1753549061000000	1848157061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
50	\\x8cb43618cccef1592e590ad1086a60ec2545522f7812f16add660d69449fb3c34cd6b1b13751287a8ae8295ab7278295a4dc10c38325297f891addcc4636bcfe	1	0	\\x000000010000000000800003c7be72df545bda12ec45b7db4075c18f5ffd94293e8ca3518a16a67a27a56d0693802c0f5ece64816e04a0f6ec6748c0e2c9b8d27d5470a7b584d15a9bad85f6251441bf8fca69742c29af0237a13e79e2f1bea1fc81379b3d72843ad2121a490e76c3bb753fe0afbb2b43c089faa6ccf136b3437c5a0ad890d1472f6cc8b64d010001	\\xd95be8a2521057ff9e3d3b79b54ed7c75baef99cdde00ca6902fd1cded2f2971aadef97e10d820c567936f1180b4e202ad1064b42aef977def447c22520a0106	1672946261000000	1673551061000000	1736623061000000	1831231061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x8c1063ddca8ee81ec85ae5a5e1b0fcabfa0fa8d0534a231c7d9ee08d735242daede747e186538772f180af28305a80d65652a2899104c779fb98faec7f8f7996	1	0	\\x000000010000000000800003b9802741ea1cf80b854bc86c8e68944005bc0de971602bd296f03c81eabe4e86e9fa957ec1859e28e31588a8bba9e5a1016e88c68d5c74453fc320c5ec7a1211d0ca6a467503088cbe367cd9302d6bc3ff7ad22910b40d29b32ec563adc21b5a9aed408b6ea6d8731b5cdebcc8fbc6597e3edb66e85f0d1d9a5363b5be2dcacd010001	\\xfada817fde4156344ebc357b1a963c207152193d13cbb2da04e45c6ab07b25e93f138626f451a1809e8564bcabed2b86618465083a1d95429055f00200d1380b	1666296761000000	1666901561000000	1729973561000000	1824581561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
52	\\x97dc9e224170fab932483b3cb985a40502361ead5a42d361e8d6ee2da4b0dc4a96b24b88e5bc2e3b3d8521b41482db63b9bf7697f6831021a2235b220d8655f0	1	0	\\x000000010000000000800003d73c0b2f0cafcc985d65c4b7cadd8d15a220760433f936ec78b10aefa52acdce734a27e1d894356eb0b0e05c3e5f46edb5ceeb5cd5660b3313b57c75b6a14462825554c45ac30af006ef08cc592b766a5f4d6c98a0cc0850be68d960a46bb43f1caad92ba4af28349ace068f3a1bb07675dd5fd7abe7dd92529cbfa99f696a15010001	\\xb0b028f1c2dbb10b12e1020415ae2e476dbc07a2539c2d2f4b3607313ef0e74c352286ce730eae37f1d5f7e63061955a2e3c4e342fc8c9936d1bee98cffd7f03	1671132761000000	1671737561000000	1734809561000000	1829417561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x9a6082c5f8f3900d92c0472513bff53fefb679cc13b22b046117f9bfb8603151a1e472b0ddc930523e1222c3c98893ff4f88fe679a8da6b78c6303be77cbf40b	1	0	\\x000000010000000000800003a739c9754dc4e1f4dc8c2aa7d91e2f29691d9bd481acd611789c985215a3202ff061608e38650c61bd1ef5f9d573bbd9bea3cb4028f2e6fa1a7881a008f5ee6316d4e95fdf1921fcfc231536b2267d8ee1ae5fdbf4bd64b4d6ccf5659a9690bbba9e367982d2483f392de8cfd2bf413eb825c9526d632a2b40b80c70967db189010001	\\x67cf87d1f995b1dd1e0232514a4ebbf4e257e3b54bd77a55483058f770bd9f11972cef52fe08e8a0e292f12325a4004dd3b50650c8669fe75105f51b4b342f0a	1689267761000000	1689872561000000	1752944561000000	1847552561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x9b1ccc2ab65ed443ef0af0c1eb6e1af8f9c88b5a1f67a13953b068d231d415d8435dd2b5b536f607434e844d5aeacbdddd0f8d39f9034d8bac2e19be7bc85194	1	0	\\x000000010000000000800003b79a6ddb5aa44e36b5dbd2be069d5574bcaa15f0327dba3d7092d6cbdec67bffb7984a93a199c480207e906931065743596ef0214204bdd8abc59550a52a6eb2e3b991898512852ac5e90904ec636ee86dc1f1adbcc7b3245673eb6183f3ba70e2b0b02e7c813c8becc0fab1b7fe2353b813aa8e74f146502097b41fa0a4abff010001	\\x3edc02f712f512b0936e2da2ead9cf674fd46f1801e33a6bae87911895dcb7acb2fe4020d171d951be86c4c6a30b5e6e2157f2d0667607869e092f2fa90cce07	1675364261000000	1675969061000000	1739041061000000	1833649061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x9d3079ef2d4649838c17b8ec6925a7032b2fdd489e242e75970f1d937d5c0b63bab1eddd0a1771c57a1af94da9325fb8ef659e2d6c65d59e47d007da2fe1dd18	1	0	\\x000000010000000000800003c304c138abdbc2ef1f6b6fe076a38a83b33f4f9f5cc2be303e14e7d8aec19006c09577fb60dce2c2685d7f092d33323440a827de950f225caa11bf6385432f03ed8fe7cdddf71892cc396b61966c3eae23027605772f48b5007f2841ee64182a363e72068b3efdddb6999a48d89961b44b7f23377b90c62c64b5fd9de91ff229010001	\\x403fbef4dcbd62b80f963f2a0af1fe5afa80df82cdd485abfcdd310f8a1d0cf8e4a8bf04cf3e94d7102f09d0df7dbd74d1eb9890d0f88502263028103d221202	1691081261000000	1691686061000000	1754758061000000	1849366061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
56	\\xa1683ae2358700e83b5796a601406e7d8d7f383bc0803dd1a6e58e6d0ca0a339acc86e34176b62e9b8334e7e49790c16c67fb0d4622c04314b0014488567e575	1	0	\\x000000010000000000800003f1a2aaf613967eb78bce3992c5247820e01f5438ab9b1e4c56472eda52f5279af568db9d023615ba5ad3eba714dd45971cf47585f966aa94f44e07734fa7dfdb1a45d7aaa7ed1f6b53fd1657f680cfa71b7ce2fffdc974330fae85e65744715515de735ffd5e67c34bec53900d752346349cc509bdbc0864eb614c87b9b391d1010001	\\x8bfb8a500dfaa4f48c24aa4c5ed053ee2a166d54a18aa5a3bcc4139f8db2f353b04e5479df4270f5e15825c75bab321d554b565b84431606b3d9ff888bf8a604	1660251761000000	1660856561000000	1723928561000000	1818536561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\xa314cbde221c479bdf85dc2a80441303201f098f34bcf75dfb258894b5666ddbbfa308035f3dd50d19091863925eb2a98e51f9be9da41cad548322f76f7e395c	1	0	\\x000000010000000000800003ad36f6ff0881342b63db435197e9566bc97926f0939ff8419f719cfdd9dea49aac9bdfa3ac34121a1509ddb14f2da3e0d7e2467e263a95ef12cd03276019527da80e8c03b2f85257e15aaf38795c195c34978ca59b2f57ead68acfccc18f17c7314b962aea5c66c3b903f0a9090d89b6215ffd104ae177eaf8f83680a5427ee7010001	\\xdcf189a68ea42c1f2268b2cbed6119c2ef7f788ebe582094a00abf8ae3358cfc05b6ae9f5b4e7570a52cb506a3c59f4c903ff8a118a97e29185504763fafd70f	1666901261000000	1667506061000000	1730578061000000	1825186061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\xa56063480879cc82cd2fece3dec1c9cc99d2b7424214efdeb574778b2507dc0c24f940b1245de131cb6a307638de372cbbb37a51e5daea9f161a04116304e531	1	0	\\x000000010000000000800003c048a1e554ebfb8a3f598f86de8d01d8d9a73ad24008ac43f9e9bc77315bea357be28efa09534e0838e0b58335b12fc2a87be3913e73cc51d69b03bc2d42bf62ff99e184c2bf5dd88baa95e56cc4f1d6dd847371b721d7ed48c599195b4977755592031340e8bb73abeb683e97b9daaff8555f2ff69af255b44ec524fc2a650b010001	\\x8acaba0f842a6c90f74c7b6e77ca62ccdaece5a87c8e93897af6be0e300812d0df851e7b8b715d06d29042aadd9e59923c906c69cbd63a66fbfcf61bce5a980c	1674759761000000	1675364561000000	1738436561000000	1833044561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\xa5587bc3c14e1172874307f8a8d795cf6134b4dfc358b46f9147833a696689ea02d710bdd02cb2f290e82ee068d0457d5eb09a8dd86599c40faa35a18ff7d3cf	1	0	\\x000000010000000000800003db59c3a5c4db924712d6a28ec4c8266c72f945b44f00638b1763d28b61009561a18ce6e9cc5329c49482c1265b68673f26e69a0525a79c01cdb62a34a0f68b12142f87bb7407f0659121e8d32f25b4105ccf1731fd628e8286e621a330504c336131d643b2251d553e88fa1b0f5ad1d09de5dace607b445d78d92da81996d5df010001	\\xd599834d7d532687baead73800a2d7c43e5f7e57734356295b683bea837a25d2bb654c89f3b6ae4ac79e8d2701779ee517bd493c1f573326193d04f55e2f660e	1669319261000000	1669924061000000	1732996061000000	1827604061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
60	\\xa6c40aae6ac02cbd5199c80ed9eb68cf741b42c8ded27e54dd6946ee5edde14b5050b366e9b611722fa7106b17ccc49cb37125cbefd832461b20b2ebf3af6ef3	1	0	\\x000000010000000000800003b1f917f9c7dc0d07f9f9282b9389967e8b99a59bc227b3252bce8592972b44e21a765940112db04aad1fbf5ceb38b043c998e8ba2f4331eb725594f1e93cac27450d9e723ac515873c64c8a6545d294a45622d762c2c676fa03f952a927ca934a573fd253f64b9d0ef87b4d3efb3bab1b2e433799f5fec13b9dded105167109d010001	\\xd41994d032f447077ce4be3319ecffd9a32f293be1466899b6833749fdada1b823083497e73f62436f05da2fd726c1110195c928d4e5e791f9e187b468915f05	1667505761000000	1668110561000000	1731182561000000	1825790561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
61	\\xab604c0fc7dda26c2985bb143cc2d598f522ef43078ec609ab8719381f6d6c422b87cad60f4efd189ded2bd9b7dabf5301b2d314fa33742e96ab0441e3509505	1	0	\\x000000010000000000800003beb82ceeecd798f587fbc62fafb81390b01b398714275fc361b79d2561f0b14d87c157f8fa71c7013fe7cd26ed5950b2db7b2da6eb5b896bc5bd6b0d32bc18b34ddff0c935db04c4d21e8ef1ddb2c831bff0f69bbaa20daa43f829d01e6990d04eb2a9e4b99a0b229ab3ccb82b242b33208c300e25387b354f3b00fd39e1587d010001	\\x64d2840a1cfc046c3e83d8cce4362a916214c056fbbe14a84009fef3e52849ec25c9302337958ca397c4323ac3111bdd1c28f6f06f4cec6dde227176f26e0000	1685640761000000	1686245561000000	1749317561000000	1843925561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\xacacdfb83388525cf854f729a430cf480abd96e09b1aff681de73db10d908e783be7e82b618019b96aface7639f9c2c893e57ce623bfbacd61d1b89ce7f673fc	1	0	\\x000000010000000000800003c35b442aedae379a704a220748d90629ed0ca33c8cdc4d037f9bda3814087b7e2f67edfedd7990dd72f30ca49525de0a23f1ac14883d797306ec820148ff93afc26986a58f61d5c09c1705a0d240b8e7e3f5b5a8f4355eafb7d6384505ffe0a66e3e12a42f54d665d1ff1af9a41b6c27204646e89d0630f7c8db1a06405d0fdd010001	\\xa3300532f5655393134be0e57332519d02b8b209857366e1cbc90f7ea680af9f94fb529352412684a16cd533c39e4edf9fc5c894de210d418da14374869df601	1682013761000000	1682618561000000	1745690561000000	1840298561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
63	\\xaf34f0dddcb4d3f2fc0c073443b496fff0ef6da5520cea9bf1f67e54bae92cfaa8cc87569a82dadfdaee37d57b7e2e5099eb8cf35e299daa5806c567f6f1f791	1	0	\\x000000010000000000800003bbf32ed6d2cdc94759859d00983f7027c30d8a0236398905d4432875065198139b71b8437e4f1992d71257767e90a596856780147fac2c05ab2236df2d12a390373f751255f06575c658c30082755ff4377bbe22bdc5dd6a3dfe92501c7221d08a0af9f21fa372dd300496213986fac7f88902e96a96186928b19e84cbcad211010001	\\xffc75476f8d6fc6b2ec11730498649e008a5e93475092971dcce73e9d911a2b4e27c1b4d376103690629eedb97936e8c5074e75940abe398249c334a4b5b1c0e	1669923761000000	1670528561000000	1733600561000000	1828208561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
64	\\xb5901b2368cb370252eb76860f38d3cc5d9075b35b3dd19911f873db87a9c82cb97c5a4866c5192ba869950a804240a30433a03d4c0397f56aca94f8b87b314b	1	0	\\x000000010000000000800003eb2e7568e4e3ccc5c54dd81503343f50f42786b7c97a4e81ca05c72ac095d9b9e0eecc0899fa27a6f38c1b1bcacb69cbb453cb153d6422e133e8a4ec048be0b8b1e08eb01cd8df70a00922cbbe657879132ecc7aff80140602b7d8e21884da072f8dbae45a9a4f129752c788a3c59b50314b62868304cd7ee56f5c9880a06665010001	\\xd03afd892d55bb25b6eb47e7523f7541ed20e2b1e29c2b5d4b9a977def256ea872165b56042f17acf9775a77cc53762d75114d64501af8c0cfd9195ef3260403	1678991261000000	1679596061000000	1742668061000000	1837276061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\xb758f902598f2ffd07150f5e681f781788cf21b59d39798792abe0ebe594a80a47b40dae1eaaed8319079179fa028a10e1482b09ffc2f1408bbc79cc4ebe4d13	1	0	\\x000000010000000000800003aec13007d9b80f74d7a5b59c1af70451c5aec62ad5ddee4cd23628a3fa12714e6070fc2af144543da027bd50d6fc16eef8094370f92ec80873e40aa2c47957e17d719fffd18d37a638162005902bf5e40c298aaf5ac7b2bb89cce2e149a9606b1c269a2c42408bc47ac950fb8da2b04683293112cd048ca47ca093fec983d511010001	\\xec613f6d2dba07fa3663730234f7058e1da1a969571f8c7cec4ba73a60b5ecf52cf42aebfb1045831b6490de934b0f41ae9294242c431ba59bf99885dd2b5803	1690476761000000	1691081561000000	1754153561000000	1848761561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\xb748f06490459a1c7ca74b558c645cc9a7d79bdcf37ec9d58b22eddebb0e6eebd61905ded44f5e343c6dcdf236e7e07c8fd745fb902750c1162f97f69e27c82d	1	0	\\x000000010000000000800003ad621d62034971b4c5431d2342ca32bd85e2beb7865fc9efce7bec39a82e1293138f9951cf25b928c58e08a592fe91716693e5034832ab77005c265ca0cd528e99aafdba0fd2a012b2c4efe6f90e1b2f3b6d18779f14ca9baaf0e5dd28569b3b8d853f93b886c8067a217d253b5557a361f4b64c24d960f218ebeb8d65583037010001	\\x6d57de13cb43b6a81d174fa5000a945fd6a111cc69c618d934c06676b805ca5ae49341ff531546bc33e3d569183e8b8ae16b06dc34df319596fd2518764ffe0d	1668714761000000	1669319561000000	1732391561000000	1826999561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xb9ac6e4acb38ea0411d4ac1064de909b4e1ac7c62cce00de19dcdfcf61d809fc71ca590be6b713b5b72bad63167a0a3d81adcef6e4eea811feb6b66d1ddf3a01	1	0	\\x000000010000000000800003c5f5ee8c61b4d96a4a27c40c4606f26196aee6852777966ee59155412da99e0461c8a7c37d569b17da9f34f6c5e66553c1aca9db2751ce663da95f86c555ddb121dd76016550153049fba0749e27cb9658c8a30d8aa06bd9100555530e5dd540a80bd51368836ef52c942ab2fc1ea3a307541033ca0d3e060904a29a7aa169f5010001	\\x527911b5390a6f6331c1565e9a86f312953fc663968a33f0cae68f5125c77d9b1a07a02bb8caa8fabff97c524d8c04f625a2374459cc027f3e966be0e1ad360d	1678991261000000	1679596061000000	1742668061000000	1837276061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
68	\\xb9e8b3a38fa0786cfc82742219424c3bf7e79ac2e672d882ef0de07dd454d02ec31e43a1adacd9a3871ce2f84a8dabbc8bccc5843278845f4e15605684126b8b	1	0	\\x000000010000000000800003b55236c8df73122b432e147285ff27f0b9ba68e5b596789c3f38859df9ac08d854220f49f83497a4d8a27819c0fdbd30e4c7a9004ec8d7742cab348cfa74db8b2efddc606f4db4a404694e5f7887cd92ce21fbcb38a8c140a81b468647ef12dc2924b27ade211e6e2a00fcdc894a339fc3358d5ec75a054d0e94f68a3113cedb010001	\\x90bcd1a3e4a90c4b2bff62e931d2f4e8dbcf029d599168d265f0dfc0103ca95dc5848d0d72b4a95b5c81c080f472197e3be6db3714520d85ce2a11c29c7d7b0a	1672341761000000	1672946561000000	1736018561000000	1830626561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
69	\\xbbf40e02c2ad7ec039f6f3f09fffc196147962e93b29e452ea988488d61a55476360500967d63a5a3de5eed74e7b2c64407ee7924402bf5559850df8d8d1fca9	1	0	\\x000000010000000000800003cc73f118e9d59f1f2dbcf4250e511b95f5b9f1d9271fbbf64fd440cb7b11446d214a57c5a28c218eceb229721540544b2d03f9f0806df88778332531844d1f6ed45beffa822960c17bc5788f125165802d3e82e7935abcef86928084d999bf1a43af2f571e819ceb58fa61b6e24743eea548d8c4678455ad5414bc73b76dd2ff010001	\\x13d8b039a6eecd48ce29c657ece089874eb0268bb4f2be3a241c1c1d2386eab85d611fc2ef520232c0f573ef42850d88f6ec0c70f3baeddeb29c308bd9c71e08	1686849761000000	1687454561000000	1750526561000000	1845134561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
70	\\xbcf0de3664f6f8861304404fc3b21b84fc90cb531093e3aec75816066f2d9c073f5b3d1b5ef034d34ba21bf1d3f7d5508e8c76498852edccdecfcc080560d00b	1	0	\\x000000010000000000800003c46dd1a6b24724d9c9de5abe01a7e34929ac72f27bc1eb92cee7b61f76f1c975dbff536abc29f61a36308237e892c3c4a24357e0caaafa0cc81c7d91fabbc7db1d8cda5d70ad20ac78ba3c7e62484e27992015bc8e8886bbd1630a8e3dc8a14cfb072b826ad2992543a49b19a11633cb68bf1780815eac8615046f836034582f010001	\\x3eb415d979e7149339a93bd068643415eed0ff8bd07e301c3bec809a1855d29b9c63a98cbe48d2cf10f7c35b53f188895cc4304cc9b2acca3188ea04bea76409	1689872261000000	1690477061000000	1753549061000000	1848157061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xbea8e66f839d48b0959f16ca3851a34186dc441787ad1ae9912febca9add132323d4a367b231e046b46ca5ca68e8fe41c3a5400be40de7e01613db47e9426bc1	1	0	\\x000000010000000000800003d2d76e1bef6ea2f7893274f4dab43e9b1c21b875fca7f2cdba636ff7321e2eacb93767329b5cc7a90da53721668bc937ccffd45ac0137ae748fd82b38fb4a808063488a6bb8960b9b7942367fc72a84a5b8f6cefd9b6a269e13e766b861be599571eae0c0b8b6dba36c4045faf47bd3241c476ca3d584f92c1d2789f92dccff1010001	\\x408688c0dfdd09dde31acb85d9ed1a591723d33beae7602bf7312a323d4edbb92fe4fb1bdc9fd8a7c50658f7c385a8c6dd2375aa67290cad80904800cfcf870d	1680804761000000	1681409561000000	1744481561000000	1839089561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xc34043e553c0f71fe620ee113a090f573ebf7e4c59d59cdfb1ad82beb87907d8e3942f2d3db211fefff388319fe22530c318d67f98de0166f8886c760fa77f83	1	0	\\x000000010000000000800003e5dda4e3f69c9880d7345db4170dfaeb49cf8550e9bddb75b039502c402ce3bb5ded6b03eebd4fafdbfd09ee782b1c4216e7eacea4176907de68d7654042fade19191e3742a111ba48c68664b6ec40d7d3b0906db0c9aadd838a7ee1e0941b35a3cb8634668d6ba2d6577c4014f4b7172c2c44b5eafcd8f4288a935f98412211010001	\\xa9049dd303813c7a70db2f7afdcc008d762a76ffbb6a3bdcee7cfbec76b545478bd52a6d14e8abd95949a130c7d04663da935eb465344bfc3c91789709b6bd0b	1673550761000000	1674155561000000	1737227561000000	1831835561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
73	\\xc614d7c1bbb9d67c4b8d05a4831bd356e3c9d22d01b28c260e6949f95c7da05beea81db185c25d416e2e14fa368656f94692bca495f982a7e217c554ca266d26	1	0	\\x000000010000000000800003d42010d486546ec49967312ea128872245c42a4bd710570dda8e401081f02fd27f49b8a5c2bec44b186b93a920c7e1020257d37ec24c45cf63655c74c7d0ea70fb0e0765d7e5c70a33caa0f8b6035f796c9167108d789fa4b9c4414d5a6b34d417d908230908ef672144f5f17102f3b09ac8defc476efbe193ad0e5575bfe47d010001	\\x52d93e8ff120315051913d2cc55adeb5e45c2a7de5d392bbfc1dfdfce6492ff23966c1b2499a874cae168ba5442204e585e250bf7bf7dbddc158bf77e6b4c107	1674759761000000	1675364561000000	1738436561000000	1833044561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
74	\\xc7a475ebe8404291e3599cbc452bee3f20b79740d7d7438a26238496049684f5ee412f9dce09e2fd1711f78a1518df6af63298eeb0f454e7ee24622b82e780cc	1	0	\\x000000010000000000800003972f070c14da8a1680966f37d2d765effe65c135bf83d7c9b3761592a8aac925fda3ac1aa6c941e9b247b68e470bd7ea29a25068ef522d7b4b0e7fb99834a9da83158b1835d4b09385819de0a08fb649f65f4f45d41617af28f7d05e90204a0eb979e777303e858974c304260451d2446940ec95ddd4bd7c3cd9026b6146f75d010001	\\x9b01e8d76890241629e7bc4caf216350133b90f6bbf080b71693f94ee82c34f73835e61f8234b1040f4f97805f44c87acad65711eee57fda19e89235ceb2fb00	1686245261000000	1686850061000000	1749922061000000	1844530061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
75	\\xcec06ba9043e9e8e56a5060bdbb4d62ada634e8ae41a0acdeaeed764b9b854ab5e5d9ef59db6cba1961d4d709ae72e29c0ddbff2b64e00cb47e2da6023fa49d1	1	0	\\x000000010000000000800003a403bbb4aabfd21dd98a78025176a3aac0de3cb74f05f2fb1b7e79ac8d42f08fc15a7ea1ad98d303b28fd4cc1e52af4246f4eb460a7d5abe526c42aeda4ea1e741a1fb318b9530006a5129ef02e5e8b9437aad9fc4a751f62753466afd0831d714ff4c3bf3310439eb5d422c1c5935b46e3232e898d6624af302cf455c8f182b010001	\\x19f63359edca67bec8693bc0cfd0acaaeb951d6ebff02f7c1ae1cdd3293e737e03bd8f67c3a046a1ea2d4c831d6e676a98ea390ee02f1feada66a419d9c50e05	1682618261000000	1683223061000000	1746295061000000	1840903061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xcee4352aa2f407b4855c25935fd1785d6bf1328f198a85202849368a48ef31d3b485bda57dcf10904c5f0e9e67e031733b846d1557ccb9b1b2f28837d861cb1e	1	0	\\x000000010000000000800003c06cbb8a64e18b9dacc539dd0ce0a8f40c034c2fcc816475493c1a3895a7e044526b17065c90b6556a5c8e64a52c600659344333fbe7e0121e10d75756cade510b121204c65d6b69c8213804bfbff342aab89601926fe9d5edcaaaa7300b178306e4b1893172902bf7e9311597bb775490322bb8e64e8aad831924473af7151d010001	\\x4d534cf3435d0acfd788454b9309d49ea4bf42e8a4bdf92410118d63fbc7cd33ccdeb825e28146e61866435ff31d5d9f00659a6c59a03c21e9a950dfb8255707	1665692261000000	1666297061000000	1729369061000000	1823977061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
77	\\xd0f0e467db8f06dff99740326ef3413c24dcd77a12e034ae1b928a426f5e128ae2e57c78c4a8b4a455a3d8650771a67fca47faec143b894e60b171aa4c3756a2	1	0	\\x000000010000000000800003b7909039dd1563388d07e5ac9bbb8f18a4130cf3fc74ff1651ce089be76b330f5dd557f56d5b1f3d33542d77f9d1c5785fff32e8caa95b40198aabbff577fe02094ee3c5ca32379492a598818ecff464cea25c73eff30cfa09b87ab580ae4f83d2c5c2ec5ec66ac0e55da6134202d07251abc2457349eb14893fb99d4ca9c9f3010001	\\x6336466fa37ce46a44b2ced4d96c5e6cf272212b83975057f5372362cad36d13b2ac90283145dc536bf489cd2d17eaee4257cb238ba3c4477bd174cf16379b03	1670528261000000	1671133061000000	1734205061000000	1828813061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
78	\\xd298be0402f402cc8ea9f648892b4424e8958718744e54fcaba08928e3882f7bfeac17bbb893b43e2297a6eab2fe8ae2aacb0503a53dfe07db4475915f6e353f	1	0	\\x000000010000000000800003a9db0ed7598e737f29732c4b694ca1a6f0417a1c476788d94f07b766fbe4ec17e7f0062fe63e119546b98706c0d2266697c0fe58da629b4d79ab337e41602a82da4f930ed72347ab718044b7ec7d34262f7149001b8ba4cc66eb31b2ef3ee15c89a08eb842dd3eb2964def920c761e51cd304e72b24afd524777f72f893a3fd3010001	\\x5147d7386933962bfe5f3d01a42d35783b4a1c5bfbe4324a06602addc1b3f1b82b1c6ffddb3ea8975fa422dfaf45604a4b7933e2191344ab0bddc71682c3990e	1688663261000000	1689268061000000	1752340061000000	1846948061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
79	\\xd72cc356298a3e7bdec94e1ec27d7f3bc62f3c85e13ff4f0f3941edae93da01c41fbcf83b31303964d9134b74cabdcba41740a5eff0e25290bc192d219624c19	1	0	\\x000000010000000000800003b502b66f0555add853059db52de45f7d9f75203a47c30bf5c2b1aee8549c0626faefe3a61fb50da774812a9fb0499e970d4d91342fbcf518d07d49e7dafb762badf3dbc5feec2cda9f0e3b9eb3215fbd736f5f560298c19d7b3289a6f3d46dad7ef680ad9104ea74bfa6180359006d890c325f93b8333320c910b7a0157779b1010001	\\x5ee97fb4db27f6b24585f5dca045e52be370c564b07d95f54e4b2a50888fc9a49eb28151d4b8f39797b469b4660af3c25c39989359d786a2cf519c72467bc302	1671737261000000	1672342061000000	1735414061000000	1830022061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xd7d09dbc9bc062aae41646672c424d05300d2ba8cfb157c15e17bbe1e727fe52265ffd1c40b873e99e8d966600639b52cf095121f34da396e850e4d4f10405ab	1	0	\\x000000010000000000800003e251cc1ade30977e9fc5061e5ba7f59efd279d367869dd094f8213d3a3fee7b0b4bbe9c707dabc027988c4df29b699530eff4b079fd510bfc6d4eba093b0ad70366cef31686fcd7c04c6b0c7d0e50e871e2bb9714b79369e9745d33cd6549dc5a53e0bce2a1967612d2fc476c102a9bd5047c2d0252f5c15b712459947f78ca1010001	\\x1b88d4ffefef3c5077f4ba0995bfd99248eb74bd926aba2caecb10348a45a0c7d12eccfe8045706829bf776b09d93025e1c78982bbabe446b3c04a66efafe70b	1689267761000000	1689872561000000	1752944561000000	1847552561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
81	\\xd8f8887f30ab35f3c0c8c11a0371124604ab40440907070706c83afdb21e1ca3fd218a3ef353aa3e44ea8de5d792188fb84c58f36a365eb1b8e31281debb9fdc	1	0	\\x000000010000000000800003b5c207050d275b1a84eb126b073d83331391fd36c2d289de9dc38649c3d9955cee4cfe7d5794897e95ea959f2f389397f36bafe6ff2d7940fd22b72786e7233b1c2123ea410cd0105ac9ed3323bb1828ccfd632afd7ddb8bda8bba4046f30df354538ddef5c19a620168cb6710d0ac9f001130cded6ca97afff3ec440e5de399010001	\\x73cebbda25c93c60db8f6743e8405e561ce0856f7a36a0fab618641e5c228910ef3519de9091d3140e0f07fbbf612197df03bc7375a0378339f907db3a4ec60e	1687454261000000	1688059061000000	1751131061000000	1845739061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
82	\\xda744cb6db86754e456b44a99b3957688be325538afc84374acd02d3f68741e9df7eb96dc2c5a1a97a2a6684932264076ac5274aa66b18fed56113c0e5b629e4	1	0	\\x000000010000000000800003b11b29de0e27c8f1f71ac32b83e68c897a1bac0e8fcf26ac169945eb9c6a473b1b0f973a741854031cc4fa836a6435552516a12ef823da6a9f1d2f6161dcb82a196ec78966bfe98cfdf5c370df1ebea5febedcd75829724747ce705fd5bd61f1a738013f8277afb1858f3cbfeace76326ae0919ca0e113277e9928d6951022b5010001	\\x239431ed9343e303b0154669216be1c4ed70aac1801afdb0d42afc6b3682d1f447b724a0671d3a76eed0b2039d4536f551a03d63cf8ce9c09e29e42ec7c7c304	1663274261000000	1663879061000000	1726951061000000	1821559061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xdc88216c1401bc32b97592e7a470c913c674ca48d69286fb6f2351751496a8688b1aa438f656d95dd7487b58b4ebbb3b37f9ff65a0cfd77a57738b65cfcb6041	1	0	\\x000000010000000000800003e20db346a594783b54a92c7dc73ca29858898b1593d413e196550fda729536b94bf5237fea8d44120c9e05c7d82d733583152d47d3221194eac268fc8fdae970011115bc02dcecbca8364f4abaa0b71d842757acbcd1587441b1c5090ca1891688548a6628ddfccb5c514fa6d10a7e6a3b02125a39b9fa191af05b15bf2cc65f010001	\\x3e5ec8d01061b38ca04c08cc38ae55f5fd2d527bf2e41aa77ede01435d8a4014f73078c47856bcc40c23d72d704067f06c3b96564860a10120e52165b263d908	1673550761000000	1674155561000000	1737227561000000	1831835561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xddc4d1ea458151e6e732d92300fe9e0f5a98b3511f639852bc5233ef95e131176ee649af0a8446ebf114e21e7e532de4c03088df23db8fb5133a20cdfcbcab51	1	0	\\x000000010000000000800003d38c27c941e8478e1d399fbf13b6f9458cebe12125df8788a2dad8cd8a5b4d4f792184ac16f42b55659bd2729011a8ef033b0609e7f96ba41fd6be85eaf39252d1dd4739350b788fcf7cc4e160d0a19ab2f06127eb331f196bdf2635aefd3226d7e7a7d90d54242958277b010db11036b566dcd12ea4a2daf159674d6e9ab9bf010001	\\x1a2256669405ed6d0b9ffe000851cf4130efca3f820005cf6f87e8e868e8a4e35a5d5dd0efaf0885e96730070e3f4f3f7b6a40b873275342e5afe30601658f06	1660856261000000	1661461061000000	1724533061000000	1819141061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xdee0404c976448c6e4edd137d7a0d7e5f0c139f484fe6c0c72eb04f23426dd779cc161e4cc805fe12c0d0ad044b4f636ddf6bf1ffbe0b523a323b64bc5613202	1	0	\\x000000010000000000800003c5b5e12aa207ae169fdc998b78072d81cb46148a45660ed1583dbdcc4ae8154be24b53b846e107783decb26a358a4270823c2d5f32490669762f3a6f8a650001f9ae0eb5c743837628aad13587d608ffa33e3f91fbc55e2cbfc524e04731069bdc424be6a05641cd37c62be7896270598c47b7d56a1daa89650fc939280ea249010001	\\x769e4a4dbd9ff89052bf80c660ca98ed8a2374eb93141d5243f7d1c5223b22dda3273eb3fb8c65a1859be582b6e22c4a4b018e88315df487953cece60523db0a	1682618261000000	1683223061000000	1746295061000000	1840903061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xde6ce83d3a935b64b406df47407747f2c820459af5c032f52ce0a8a68f0e0d82a3365eecaf4c060262c3c5f203db403cfd09320856a57b84a203090fc11e086a	1	0	\\x000000010000000000800003c4366fd7978d10f994588e111117ebad8e7cd9910d3a980212cdafac21c3290e7d40f0bc583f26043a9b2c0e13f3deab185ba30352484eed3a9f94e52e394373439bd53ec874fc79307c6e610a7a8076f94b4b7ca3a2262ffc74f22b591e9b6c59186d64475b39d61e08c55bbabeca0864f09fc7c20bcdfad50db2a3be1b8185010001	\\x890bdf3202edf32285e9110717015f943f9142926923afdece1fdad8cbcd24a6ddced4c818c9841079c861c7d6c52b85ff832b4293d32cb4ac1573f6f6f81a0a	1671132761000000	1671737561000000	1734809561000000	1829417561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xe0404a3c8e37a10a58f62db20912435c3183791d7b5d5873fbc53c20e92bda760533ee58edcfcf280539f4c8a70bdc42a8ed088e1f9d794441f536099321e2bf	1	0	\\x000000010000000000800003c56c132f57c49b1236044916268bb942aa301b9ec2dc71b1499dae6723df5e2470c3c22d4db5b0c20831cb7313e6c9b85a341d226dc2cef37bea3fa7572617b7771944630481ddfd040e064b11821f49e36b20fa877ae5bd0253c32b99b42d52e3d370ed12b44999958bf4cbb04e9375029bab4acce9e015458d78d2b8e96c5f010001	\\x2a416d3da7083071234935dbfc31b04da2b10c3825a73193247027b4601897d922ecf4066202e065621c273ed136991de076832d3995c912796568f613959f07	1685640761000000	1686245561000000	1749317561000000	1843925561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xe19cc4ac9692e8465ff01000eb11027b92709c64d106d8087fa42198c1e8bfd87891aaba0abd902c55809817b88798792e9ece71fb8a14deb3e69dc6527e4118	1	0	\\x000000010000000000800003f383a38768ab8305a14e97e9801757813478e2d322e285ad4cab02f96c63ec489a744cedf08fe78b72062574390dc35e608ffc8600b5c6527cc01d357885a79559533402f472e95e2ac3cb644ef3a3c5fe6d2ad736e1d285d1dcfe5d2c38ef601a4dbf3a2f7774125eeb649778a0946415092585498fd865c714838e46b7b463010001	\\x507ac21ac428dfc860ae174dc07a051eefd29f749dd97dd4e68dca5752b261076db9f4e4e2ec7dc3069d43a87e352620f6a889aaad3517ff6dd4742087c2590b	1678991261000000	1679596061000000	1742668061000000	1837276061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
89	\\xe3207ff2cec3d46eaf2adb95925728b1b800acfd82cf71a8fcaea6c468113cc37f1815d233d05a10a656d5413f4e6dec46483020c304fa27af44f162ec1b9a88	1	0	\\x000000010000000000800003b5fa1e1b5eef8d67326993f80c6908d1484acccddd5f4f57b6af8221f7e1f287d232fb5bf591f2672ef0541bbd3ce06f030a78b689cadedaf0d86e3adc958ac3c3993c8f84608c52e8778bee7bf155ed4e660b52bf2c4d41067098df9da5cfc9d56fba3e1b64dcd28a3d978941da5e004a7537dbcbd92920f894ab94da2f10bf010001	\\xc110d77ff2c87b49a9d84ea528b67d8d61cbfd58b22bea26c1ab794e0b8d74ef02c76354de1fb7270fec79fb07f6d3238448e15c706bea72a1cfe00d62a89206	1685640761000000	1686245561000000	1749317561000000	1843925561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xe498bc044ed1f596aec07655279990134eca39239e1e3ecabb75d3252b8f2190debd8d93e57f81a0a82c7a413997faf0c6863e7bcac9729785b516a8875771ab	1	0	\\x000000010000000000800003de26507a5a1b737d76c81e6c9ee9b1a7580383ea55928335a4727c9185493c5d0b36d314037650d1de68ca2b30e1a0c7577254ba7ad5c5250cf7d1ea8597478acea23e9fd447875120e36ab84507573454cdc1100cc2771261cf5ba64dcabe4d6e0ba3123c1426439f29ba2373deed7bcac34f664298ad987c7172c2c497d023010001	\\x0a2e8731e4604441e9f60073539752128925e0273e13f5cf29a43a37435ab7b791e5acc68ac7b5137fd2aeb4d903bb82e01fb0dd0bcca2ac8f3b95ae205ffc01	1668110261000000	1668715061000000	1731787061000000	1826395061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xeb48b274bff1bce04f3ae78bd9954e85093a2862cad719e07b538fcab62f9e6cc94c4828b7377bfd5ff07872349ba76cfa35a74b691343ad362ad0ad596cd84f	1	0	\\x000000010000000000800003cc4e768381824c036a07d929bb534bc1e05b6eb59d57264fe90a025b4bac4dc456483ad2a84cc511c1dd47784050935d762ac3dc124ac3d6a0d1e31baefab6af1316c78738000c10f90d027b93d48e34ac964e979073e0fbedeffba424448cb48074ddb173da30769cebe5cc1db623f90ccccc319570f5f8a5558226662bbf93010001	\\x811ea0837883e5a8618a410a592dc455c1a90d09f618896c795c55078e50e93c5d7148270d21b0a19bf0031b3c6bb3372581735967cf68d5ec50e08e16b27f0e	1679595761000000	1680200561000000	1743272561000000	1837880561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xeb6403345b0137ebc8672a024e77d287da857b493f45715c08401897572f57ff237d913d64b00abeaa58dbb59cd457caf9f8f82548086b5cc455f35c964ef83f	1	0	\\x000000010000000000800003ac6dd1891bf1db317c52450f484fd99e5453656d19d6d3ff67cd8fc074d9686988ef79edfce261d45efebd4c612d62f3cdcf70ba99ab8e770a669edb5a587bcc19e6c0eb73fa08c1b176aa6dbbc14d2182750165663e89b2a4d6970b721992d920341b4abc50397c33bc23672d37f73a3dcf0b983cf185f68cf555928741b68b010001	\\x04814d3dc5c29364be57d553286b4a85898b77f3eee29decf557ab5a74835f01aaba46d54ef576f974046b387919af011f392d1b98e420bfbe0f91d867cf830b	1665087761000000	1665692561000000	1728764561000000	1823372561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
93	\\xeef4faee3355c262e2e3ba1a1f5d08fa7a41fa0d3a10b0a353ab296daa936461117cca6bce08d8d4a1228706cbe9a86b6a7da11e2374f8e6520832eb304f2ccd	1	0	\\x000000010000000000800003d307037d8699303e9dd8ad9f993d4d87344b81c768a92b9b3f50429686c24459f6abe010105c4a80eea4a1dd0dce82024901dd59166f4d44123dadc0439cb58f0205e20298a6ab31613a2ed881c7c125e27df0d673238a9de13c55a32bd94e32a2eb838c2d3767db7a0f0edacf959b377aa4896091c3e008604ee86da90beac7010001	\\xfed151023aa553dca49f3a7bd6a8a36264223265e22e1f346f066b36a2fdd77a5e298727eb6fe162a01ffc98673836915ff94c9f322f2eb5cfedcc57a557d505	1678991261000000	1679596061000000	1742668061000000	1837276061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xee1c426e7141440b1847106543e6b138be88c65e2fcc3ef7e458f1a8fa28af012e735783b40bd2322da5332d06d2269255b32d65755138c08f3fa9dbb2c2b2c8	1	0	\\x000000010000000000800003a8026a978e942311b01b781bc39c32e06c744eaf986fa29ed079026b24a5e114636ba2fa34312dac57d8dfccc425de30538e0612f273026717bbfaa24dc89b1f0ef7ddf6dabc54b8acb74b726adba3774fe6c0d529e2cd9c3639c202e163fc90d2da8c1eac07de2c656f91d3907ac7fdecaf6e8eacdf099a51045cc492668863010001	\\x1158636d8059969f307e56ef88c5183deed5b9cc0d7e8e2085a498228460c89bb3226a2e28f8478918a6887ae988111607d00dd45a1e8c2b617efdfc5d3e7f0a	1668110261000000	1668715061000000	1731787061000000	1826395061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
95	\\xeec0b42c14e76c7e860085ffa50f315b3d73f09d6ef464f4131b3813dc9c3c0fd502a4b175ac33a23d02f86d4b26d89c92ac93da00408c2610f75d13c2e73ef2	1	0	\\x000000010000000000800003a81057fb76eaeff3787cedb8f332c4ec66ddaca33c1040d5d84d34887a1a307a24068cc344ea8086f15a10694d5f70a8fa446d018ccf46c19af6a63d920aa827becd5371cf65a9bc2ea336a43e1059df22661cd186425b363a4a9c2d17cf00e84ca8a8e2c56b1c6c496cffb0992531307da85eaab5503c05d5b2b89be4a9a307010001	\\xff3e10d1b8edfc33372a2d5aba89914192583a046ad317ae92fa0bc3eeae0c025d15d8cd4462c4ad547c7547d4a948fcabca7fdf8ee51c4f9b7930253e12620d	1683827261000000	1684432061000000	1747504061000000	1842112061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
96	\\xf1086cebd0f5bc16c508f387e26fca3e8472052fa9f2d206873cf6ba1389ffff9ec1e69f896060ec42cb3a6341d164bc09875cd11ad7b53704dfdbe8d7a01b10	1	0	\\x000000010000000000800003e3418bed2b1386ec76e99c118c55b7850f96d2f03ce9b3eb81528c891b087c1327880b0ec7bf55709220732caab1a0eac3767f3d4ccafcb65e6019fa5b2262e9dc207ad17a8601d14ba434cebc2d673b73213af08a4e63bdb161b6057a349c5fd5520bd01384ecea38cd7b3827034b1b5d19f3e2b79c20724b05e93c1a208617010001	\\xa7c6869c6294df066eb04d65435a00d92e4f774f830bd573bc3fb240c7675e1aa9b0164d415e6d544b03a34d84dd749376fcc14e40067057d1740b01b4e0fc00	1666901261000000	1667506061000000	1730578061000000	1825186061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
97	\\xf3ec1384ae583482e03376eb29b4682bc05c026f26ed8b081c4b3c5faec24b8462dd41470d20ada5902952672be37781917e9e9f173a6c5bd05fa01c7545cc9a	1	0	\\x000000010000000000800003bcc5b96c4da88649abde8876ec2a94d457da8adca782031bdfe0160f1406a20d2b02e4bce06984db5d25de7d5c2fd17150734f2388a622d70c4c505417a598ccd03b4144a438bbdff679bcb0081887effad385c5527034e7a45c08a0dcb76300b47ec1b88908f866e44572e7dc4d019d06fdbaf79640973aa46838ece8160dc9010001	\\x6ac108e12b9f23f1ad481eb5edef596df6765aba06fb52c50676640ff1359d3cd87b9aef1638ba2f0a32a5e371e32b597a0c188eea5a7b052fc276d4ef01c600	1674759761000000	1675364561000000	1738436561000000	1833044561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xf4e4c17a3b5527bd72c5deaaae076ac3fae987c19b0e1cc7e487df643e6dc4d19f3333a1c19834e68941ecc3dca9916fca3613e4ffad9a68bbefdcfedc88c762	1	0	\\x000000010000000000800003a76c55ed17fb4f054e508df6f175b72e4fc7bc66c7fb6183036e45363c8892b46fb60ebfcb7f71385c45365813219850bb22966f8c300a4d8908ba36f5fd83fb8bd0f1e915d1435a2ddb139218e1d2d292f2715babd10218494e4f22b450c7987fb8e8dd330f53fb54fd39d6d4dd1775d0dff5186965f36e02be18b993cf7d97010001	\\xc356ae0199462ea9da52281431e1bbf3463536d2f74ac4e2eb9ea6c8b02bf7fcd6e5a3d0a4053f4ec6d1898b3298cbd79033e281be18597124905a7e875d1f0a	1683222761000000	1683827561000000	1746899561000000	1841507561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xf7f4a2604e1f02d77480dc4e626031f84a1aa0d170df7888c79092b436da7e52ea80d221c0ce6b99af4586675eea33038e8f7523a1e0240f96f6ceae4c657318	1	0	\\x000000010000000000800003cf932bd7b14b6dd5695f600043f530f5147c529686286696431db6043ae2b83f291f96c16130cf1cda30e9792a2c64da14cd92399a92c1592e2ac48288d3d8fc3ef602d31113333134626f2c3ee09bda8d16effd8516f36a1392d804c63b77c32811e9aa5cf10eff012652f2934825a485b24ba45c33c69e51c98b63754dda75010001	\\xe0b5c0becbe4ea97af8b26e4064a6200635b2677b7dac6380313822b45d0272e2310693b23c6ddd62c35a83eeae11529d99e5eabbefeb2e9d0fc69360069c00a	1673550761000000	1674155561000000	1737227561000000	1831835561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
100	\\xf8648ff1e5af38090b9059d2d09a1860753e0f986a5e159b41d957c2f53e76e97e7b3edda3e90938bf2c9519b9db860c202d9cde17a77931d6c741537c46207b	1	0	\\x0000000100000000008000039dc946a01149580ec34de4d4697684acb5155943831c0a1be45c82f82b9472d203a47335ae2c4e89f7765bc886da86fe00936817ab8263bfc98489b96f8619058e29544eee79023a8ab3d1ca1e7917509dadd3015e2231f258f4941be0830400f47a03ea563a6dcc32a2bb1acdbf0f7db8a49bba017170d53730643b6f571ff1010001	\\xb17297867d2ce7e4c6f01e9d02859e4dc555c0a96dc670475f6cf37b8800eb1722f41a7bc16b5cf677ad207af1c4027b9ad664de4ca5c98bb34426fe084ba305	1688663261000000	1689268061000000	1752340061000000	1846948061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xfa2c9e6b74458c91918bf360ea7ae99d35044640f1b33c332e6d7424286bf6a6d197c8fb80ff18334ee145f79fb1d158ec253dbb0d6146fc283817065a049f1f	1	0	\\x000000010000000000800003c5479f34c7f78cc779d44752cfe1290703ade277bbe7cb88c37674c39a9142c4ed8a1c1b72eb5079847da7d7d3f3c4f7c977c1adbb5aef98fcebcc52603cd47919800e4f670b895c29532b064e9d2f3895bcd6c59dc587499d57802750c62b4d308f5bb42c58cb90655cf9d9f0cecb5fb1518f9fef0e59252ffbad05c78ede83010001	\\x52cd7f9378db721f1145a08b1f9d0e39a409d9c00b4aa82d345ed6831b033390363abb4b3be291f03d7152e7b0d54220698944ce672d7f6194d76b4336447708	1677177761000000	1677782561000000	1740854561000000	1835462561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xfaec70f9f153e70f86fa101d8ecdc2b34781bbce29bfc8a4d41a401e7b07dd26b2862154dab456501ea79ee88d1b5c905ab65ffa87a7af1e0643bb0bc59117aa	1	0	\\x000000010000000000800003e2b58cc4d18b505ca4e90556eb40b71dea985eec891e597d99a1554ffd532ea42c8ead28027579b4bf6d9db1ffb5ed29cf537daa38ca6134a00478ff873b842df78c7e8f193af19ebfb79fcf940bf1fa4b6ebc3450014fc9ed43db9a10885456b0344affb4d01e2ff41bbb28021fe5022b521e72e9ba554677e536d72bdbe273010001	\\xa0c02d49dbbe7b4721c1efd044753e22cfd1e90af9357200841060ffbd2786b5cb66ce02dd86aa6d78ad6ef9ab95541076eaf5eb0290ffa2263718f25b5df70e	1680804761000000	1681409561000000	1744481561000000	1839089561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\x00b986d12d0868a5f88d71f8f4b8c09c4117de10c5ec06f078adcaa56ee0eb8773ca00dcd1353b60dbe4b23b89afbd700431f5d312afa0e08d5730a654cd7e6c	1	0	\\x000000010000000000800003a91f992885cef73145301818fb997d0d67803ebfdf6809d1eb2e3961b221e23e9c8b780c59f671ddf036b45bf741f63bbbed3f6d60fb16e16d10b1cd58d66b33d3b2d4ee46cf9b533738d3da7ab8574195ee1fba80b62fb62c2ca5e525a4dc37494eaaf38372e407cf321899e24ba634c6cb4b462dbea648b304f353638991d3010001	\\x5d4d9a176880dc9a01cac9f443aca66f66b07a56c1d74f41e6ec29a4aa34329b317934c2965364eee8177510bf7537a55402252d6bb94c8fdefda7a73411b203	1685640761000000	1686245561000000	1749317561000000	1843925561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
104	\\x01c9c7b8691c92f00cce472881a688c7078970d162aaee3a49439f07064cc9ffacc79b48ac776a5c07088042780ae1d240f35cbb3e1dd4ee8da7d6f561b94d14	1	0	\\x00000001000000000080000396b3d4ae1849b84ec4808db36e848107f2517fa2af40ee22ee6ef2caf8955590e68cf9baf617ce3971a8c949ba31b2a699044a0600ec099ec27b6fc2b0abe690904a0ec7b0d52014709df44b4d2a6db4991091f736073479976e7ce9381183f7a424540281c920a65b1899fd328c2076f15fcffb02be1b716a7264dabbf7526f010001	\\xdb5ea3771f2181c51d33ed741fdea538e7edc9158a0b8d83b55149e102a5fa135021f1b0fedfe674b22413ef7f1046ff34515d1d4b3e4d35ba618694382b0805	1662065261000000	1662670061000000	1725742061000000	1820350061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\x02a51da0351186484fa96317eba3adf20d165a6cb36c5e04a264f5e1da82da279d36c933c3f185c3a3eaf38a59e8c0c86014df91a0019f0d58a83200ff4431ac	1	0	\\x000000010000000000800003b848e657ee721316a825963d54353831c6d1a556e123ddceb1091e746fb5d4ed57ebf276774b33a570f8a52f2af1e0a8bfe439d64d46d9b802cdd657abaa43abaff62252d4a54494c6cb4c921e5fc9ed510bd6ed0aec346dfbeac7f17e82b802d27a5bf2be42e0d1c8f9a7a05c9bc32d4bd62820ad0dc9877fe412ebf8f65713010001	\\xff4a642cc43ebce9753a303afd35f83bfc6cab2afaf54ae2f1e3f109816bf0869e9f17ad647e7b0f0b8b749a7e6f0c5793bc7fc557465d348ed482750f79480c	1680804761000000	1681409561000000	1744481561000000	1839089561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\x03edd5c3b724f9566430ce54c18c061da6567d48c00710bf2d1f7aec52d058b4f9ec3d0654ef5e21f785af42931192a9a25a023f9b93a8d504bc9a2e1746891d	1	0	\\x000000010000000000800003b3e0acd30ca08f0c3c758c7b207778d42ac6de82dca786b44fc0b7b5d19bca019e645a8fc55b1fc863a024a054ffc2b7da656f6facbf97ececa1510e4f1dfe4da4516c6a690d8b5db588f9c1bee37e806d93661484360e969132b80fafb0a7607e44ef42788883fb873e3be024d7bf472d9409cf02e67d4c4852c47ff7458be5010001	\\x7fc8e4ae879687c2ff1d46c8f07dcff7c30cf68518f6ce76a1f29948b0f3a26c16bc3f3dfff880c285290081eff5f9f029d9e01cd04ec6f28725d87aba21eb08	1689872261000000	1690477061000000	1753549061000000	1848157061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\x043985c8d7572b6a9b4562240322f02c8fb86f6fdf805dc9299453ce1f8249e02e218102d98e2b2d3b108d3aaa3879f2c4a76e07fe9af9fb52c6ed08f586d0a7	1	0	\\x000000010000000000800003b1e729770b51ff34ca06253bf957e05a78a78b635e3458457980fc5843b8079353726a0ac1b3b7f1247056cff409f6b803a194beba3775c54cd150ee94a1ce55e41b14f1ca78cc511d60fbca1324fb5a546da00b8fd138f2caeb445fbef8cd8cf4b61802c8023cc32e134604ccc16666e416b86098eaf7427f315d9e7a7a5553010001	\\x682bd3c3a5235afbee47cf917fbb18d70af3b27034e17255d814323b3689b229b7fb85ca9e5d2f1db2113428ce68822910942401a2be53882bdb6544458a170b	1671132761000000	1671737561000000	1734809561000000	1829417561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
108	\\x06dda984a6a4c010f7f352dd188955006190506f596c2984940e4ca7e9f8e816745595623ec9c9b64ceb4b4cbf513fc3ef4785ca5a9c45cbc66b2a3850de938a	1	0	\\x000000010000000000800003b792f0576739b1c23f30cbb98e460df98e42b865609995c505bfc2d3ef0402a1fe53e329e3ef99dea42d963e5b50772fceed637b5378d6cb61f7cf0982726125671dddb7dac49900f54d8a70ccb0d6791c45927a650cb9523da8cb0d2ef62fb460f934b25a8cc4430b3554fb4a145652808b848ac007bffcd6439cdae0ad59a7010001	\\x3babb5d9af35490813a8ced5058d10c004b0530e4f2ce323c9fb08ab684eb358ae410cd58b9d332da7e6c9b8ba3b1d2f8b43f8bbea1771dea42d9900306e8501	1666296761000000	1666901561000000	1729973561000000	1824581561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
109	\\x078951d717814ccf72840e8e9c2a53f5f1acbe8f913668ffcf502b27f5f0839daa22c5da7eb485787fee15f9ea7cd80b0399ce2bd1b9bdbb0017156192ecf9c8	1	0	\\x000000010000000000800003c8ec19ca257cdd0d202094168ecf0799b419bd1f1eb800c8ad903ddb8f325f38c68770619df5c694dc4a3c0a90a1fa3c0d5812a6aa67b086c9a8c131f22a4b78fedfd7f71cb7270158442fabe3cd98c7f3fc47b70b994947b083a0e4907b15eca9d89048a4094bc6f518ac6dc400d52587c39160484c6d17dd07b15046e3eb69010001	\\x44d63dfee2f8a020e0a39a2ded6e62c17ecf0f7b3a142cca0d6990a440c3da140675c3b2024953babe4969caf0f8caaa409e65e5b35ebf92832266912c163d0c	1672341761000000	1672946561000000	1736018561000000	1830626561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x0b112debf74c6f4220418cbda7a411a0b8a2499e8450f499f5b14101b99e2fcb783338062c312924c4aae7261aa4fcfdbe88d85daca9a73c83419f755ad53ea9	1	0	\\x000000010000000000800003e67b462bf106abae8e458b8802cc93cc059de12c2ec803ff4abc760e1f52c29a68e47da126552bcf326a1e2df22439ca738bc8d5b492ce226a41102b1ae7265d2e418ba24a67619de9ddce07c7f7bf6e68612f01d0b8ea5626541d8781b0b4c9142d80f9845aacd64dc5f6577954c1ece7d705438e06c17f9016472ee17a9fa5010001	\\x2104e605bc54faa8cd21bfd1e32c3716face327f149d09301722a3af77f00b56b80c81c8fe48dbf2efd8ba5372494bf9e87eae0b37e7219740cbceb5370e7b05	1686245261000000	1686850061000000	1749922061000000	1844530061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x0c456be94606e0518c363a59d642df62ebe217f0b78601748a28896930a825c804820b6ef969ab07436da60b9f03dc22a2ed781d4fbf4b274e1669d97ae96009	1	0	\\x000000010000000000800003ccc7fb760355773af4fb657620efebd0622ba1ee3989919fdc9121dbc9e174b21e54efff2f5b63e96216db14fb8a3600d54c633469395166e4a2300f70076f2457f86c1bd24d0d5b8a9a3da0f0ab901df337d9b06c919f8429bcb3d6975bf4dd3a07ba22dd6913cf7befee549c4d43584a3f2d8bb2a3f6b098d940cd76fbe3db010001	\\xdee5a29f496e30658c3f129eb6b973f4e0c449abc44fb20ea164c08fcdf05cbeda6ad5f5592c75ddf09f115f1af3fcb0c3bf6243f824b85a5c017a34cc2cd507	1682618261000000	1683223061000000	1746295061000000	1840903061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\x11d5cdce382bc114eefdca1a74812c40fb179441c35b93f9c7ded4b48b1015fd2706d6a5ff0441f69c94bead0f564f0b07a1d0f61b5bb3bf512ff7fe34bce97c	1	0	\\x000000010000000000800003bb8ab2e16d1a31ef3b187aa7c14b24ed0fe927103a4143721014d95065a9948b93bc064e47ad6a11155b1dcd5eea3022fc8b7a3b8db4569fa6f9ab03de9fa83cc22cb7b20414e2053dbd401e40024c99551bc4c5d2b093f33f4a3c803ad77a09d2723bdd868ce902739462d5e4bdab29fe594201647b663bafb6c7eca342117f010001	\\x49751483e8a50783705a757c18e011b9ff52f8124abfea92214b0d079566ac7e0497863ac0b87fb00492c0f76b947cdce9edc0bfca45bdd7ad02abd0c3381508	1663878761000000	1664483561000000	1727555561000000	1822163561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
113	\\x12851a660e2961d41cd6340af24224aa406865746f625c2c7965e3b08b7d48684f4262f42fdb121a7d9ef3ce2dc0c9d0fc2c62b19eae9967e86465e4ec0a0270	1	0	\\x000000010000000000800003a7ca66076c1b11946338990db7634048585b4b5547531963628c0ef8122ed85dccb383f5991eb493d692b8438f0924c9be720ded2fef1270494badaecbb55e9a093c115ff16027f9199dd400de5ef5f2daf6ed1004dc480e2ab3db574b8fd0af987adbe63b1c3aa16025252a8e14f28d50206f538a5c6784096ae7adc54ee393010001	\\x41a1e58d573fd2cac36834d303fb10420eeae6efd427f704f09351cc99b447958731ccfd3f8fd962f8c259220de0a68f50abf22b01265a16f1993a7ea5f71b05	1672946261000000	1673551061000000	1736623061000000	1831231061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x13d91b1b70159c3a889e97501ddbb8500b3af451f2ac3cf1e56b3ed0231c4f391a90a259328793690cae12cadaa83ca83c73f38735f8b9aa358ded96b7c35214	1	0	\\x000000010000000000800003b9aeab77bf2d0949938a67366385a5d8ad1c4dfb7a96d2d86b39181c9460ef5ea485b400e4403e7d82f4d6b905316443007d986725aca478e3f31c1256b2c50c043dacfe35283a082aa1f339510dd7d6678c59688eca75a66ffa265cd64486b42a395c6f70e9b0004f70a9ccc2dcc34d5d598019a67ca2e4300647205395c223010001	\\xee3c4700a18264f35c8e281dff3a2b96b77c9a41ee18293ecf16b5f8a176af8a08b2a609fe23d41b6806776e70a4868b0a548daf6f666cc7160729a84c03bc0e	1675364261000000	1675969061000000	1739041061000000	1833649061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x13d9ff5feb8eb739f71877a176ee4a263308e1e60010cb5a6e52333b41d157f241b57ca44cd0c73fab1ab6de48cdb865df8ede8a8c1db33422a397faba13993e	1	0	\\x000000010000000000800003a73f0fe255d46264e09f7033008ed5015acfbf98d11b48c74dc2d8a8053fcaa05dd428c418450c649f9fc743a6ea3a6d20645d15002fa642a515d865aea3d04addfc6915bb5d196c5113b978e2803aa4ff2a06fbe2e6f53f4a6c960b2ffad9baffa62f7e2dded5d70f5370fbf12b1d6b75c20a61759f70456b2e5cb29e1256f3010001	\\x49200d37a6af063ca9032a89b5a73a68b777f2f03eb31424290ac1c822fd968e82fce59c4c961f44f2513ef2088d7ba22dff5e06f100362c12827aaec7492101	1683827261000000	1684432061000000	1747504061000000	1842112061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x14adedaaa6cd0a3a1c80a455da26ac63795a9cf8472a4186c3acdf7ea04c5fe727e60ea5e9757501107d8459688dae8315c2e7cb5dde562742505d98fcbbe43f	1	0	\\x000000010000000000800003d2f50741e511f30b6ad3a9380ca4d061ef455ad9b012e5dfd00b46d439d8cc0abcdade08ff022939db3ce25c422565809c3e60d82004e62cc73f4392bae531abd0faf3e8c324a7c05a3db21af4eceec90659b0f3fa5c4f7353ad114997d90d9e4a71f78d23f2b473437f21fe4d58553d02e2e32815bc7cbc5a5d2772d3d7e2ef010001	\\x97e54341ae4714216bf719863655f207915688e4516c5ef0af0567f855430c1acc2eefac8737eb5f04efda2bb9d17210ea31ea1734766bbcf7dbca959663d70e	1672341761000000	1672946561000000	1736018561000000	1830626561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
117	\\x1551ae5c74705a6e355ceeac045997eabf2a10ba3df1045d01bac62151cbfe2e3581ceebe16aa933606f81e21a4714ca0317b66ff4a33582231586887345e261	1	0	\\x000000010000000000800003b91b1db793d0ad0a2a5096da7200f65d9db8d5c0b72cf860443a7dfbe92e36022c5e15c3e900afee1cd6f1ff08e35c515edf29a7d4c996d2b2d7bfdb09e28615f410a4e90693da9c1d3350fd4a72a576a0efbba45a34fd79cc5439e457f853461e4cc5350620960a7cefed8b8f1bc955c0a2543ce329611bebb3c2c2027c55af010001	\\x097fe9c5e1c025975e4009198fc03909fa88ad472e1a2167008f966f329e86c6a684288c0edb298986b34a133d23490af6783c4f5b3c6f2d36f89fe654987e04	1662669761000000	1663274561000000	1726346561000000	1820954561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x16898e0244e7567d88e6d5a05f47f37d833bdd40aaf35081363609469be88fff064b0bc9d18dd6dd40c7905dddbd9ab8f9aed08adb836034d4328f9436fb3fde	1	0	\\x000000010000000000800003d8e963c917e89389bbc3ab46827db59eb8a9a61a8ada667026b0c7cc8ee1bc5e2fe36b11167ef84998146cc8e3ce7e7d7527381f6d212716e522ecc84b150c052a109f264b4aa4327d9605f54033894574fadc66ac5c88eb3ffb8a7eb22a46cdfcb4b1f4444350fc684d5d078fefac510f691da8cac83cff1a8f1685a56faef5010001	\\x79cb6a1f50aef5bfbf35d173bd10694ff183130bc6379da08176cd48230902e4d60074aaa6b0fa65822e5642620d603bf931c537898c81a8080ac9abfd64960d	1688663261000000	1689268061000000	1752340061000000	1846948061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
119	\\x191dfc0d914c3d8983ffc76856026054db8ac417b61c1de403f995b077574bf09b01baf9d2e4f0ec604599d983f2fbe89a0fa51e7594d7d9184a430dc6b801b6	1	0	\\x000000010000000000800003bb7593d093ea3b5a08dbc817b58aa092c7739d934539732f9c51944c5fe0b0c0b34a772e4a64650829f50ee947c3cc45659f5edcbf7cb3fd7a1a1ef28c4bec7e1fcb450bec4851d2f1fc8e450bfaa880513f82480e64594ea92d791984ffee8f5334c54675a0bdb42ad067166f9c3668238073918598f9eaacf3458c5b2020a5010001	\\x46f0d117613669e33e93d0536e705cdec950c6357a325f57a19b3adef98e17268c837de6e5df197f64269fcf964c68fd952b3d9c289b073ccfba8b55af785a02	1674155261000000	1674760061000000	1737832061000000	1832440061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
120	\\x1afdbd3f61c55cfde9f07ece0688bc24572da6d313e9aadea59681fb5f62ea01d033689951bc6e2edfa2d17d763d1e7c130464648024704c27f429c441bd9184	1	0	\\x000000010000000000800003e90140ce9f0a2c92e71bc0a1da6b3ea3f6745868aa8625ebabbdb0bed35e21910a8e0983b6e54512a171485e28a66efaed7004fc2351bd902725b700ea244bd53390dda89c85a7f83c3d8c1e073e370373e7c742e08df60199e54365f7e4526666cb96f58f11ab2024c87b963798c781eecbbbc0d68a4cf11dcc8d1585af8bb5010001	\\xa2f28889f0a7fd70e6198cc63a5003494d646547ce51487b05ca59b69454b83be4c85ecfa283a09a38ad5154facfab7865be607743ebdf198cf6ca67aedb270a	1681409261000000	1682014061000000	1745086061000000	1839694061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
121	\\x1ec5e25974229e9c823381087629fcbdb3fe226986474634fdf2749f98f07e657401b682c427009a935bf9708e17b28e42d56ef9a84b30b87f9dbe3f265e45b0	1	0	\\x000000010000000000800003a6e257b2d084250b772d777c04381924d683ac3623a42d4bda5b6f4a64ce1186dca631572c4a3562c73c74f9aeef231ead5261d2e3364a9c797ea44af9e9771e7fe3d7a387e0a4750b4e28e273eac2ebd7ce3d3ee171b6064d3a0a1c608ec509894441d8c257a09b74571d60955dcc25094139d73de8f7e3755c302a6a4ac50d010001	\\x87fa559df44dc9adf85fe7cd83c118acff62eb62e4c1291483502b77e494de2b0bb07495337307237ad9d78e1bc5c413ffb1768299a2fb1daaa33ed125b2680b	1689267761000000	1689872561000000	1752944561000000	1847552561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x24756fbb5c13b1c717f6098c3f201fcf87505a10aeed79be71d3d6dddc3aaa8f256d2bc7d45f3dba8c3ebdbcaec94bdc27dd1133049d5a5b7ba7629fada6d37c	1	0	\\x000000010000000000800003cb59c4eabc8d9788301e9737ed56fd6a22ea76ba8b41af6181cf5cb7d274df96bbac6d42c9ab778882a0dee354bf022f4e75614089c573e93eabd1c0a21eae2f9361115dbd1e51fd14644432726c5d931b87818cd85e261ac8c3528d9a7234c757bf162b54760ebbd8fbc57d5182880e11ecbe5b6f319ff8f2db0ab1a9bac4cd010001	\\xa91fb8084996e6e62f9a69f97cc389849e440f19917785e29dcd697696ff5b7a1eb05396eb9215f809d841a87fffd354cf0d20a3eedeb652f06411624eb9dc09	1668714761000000	1669319561000000	1732391561000000	1826999561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x25c1d11986698c324c052baf80e662caf1b2131d09b316a6d5cc99007cb25917a6ca26dc462c34587446175e91e83830b8fc111c9a12f15bd9519b6081a3c5a7	1	0	\\x000000010000000000800003ad981bee631d8cf79020367e55858c91f47495ea6af16fdc4780e388d16bb5fb6a227c2698ebb0ab71fdbf3e0fd33bd25b3228f927d5badc596291ccb486f572ca6a058a2ee5f93fb794dc851775ba63b1c4bdbbd38ffec394dc6e05cef73e2f4fcc24f599a8eb27d59bf0a28f1f2129d7d6f4e045e1e8d7dd404cb53af29ee9010001	\\xb98194447885775ff5fae78cae2a961baefc5061abd22849447d4be596c5b4a8c8e0f556cab933dbaf561de8cbd2d759f86200548bf112daf246115858259909	1664483261000000	1665088061000000	1728160061000000	1822768061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x273d31f3d8e0b488c275cbf23412441ba41484f875dfbde96299a7e60c6c2ec395617f34c2ab389b860b1428bc7e5c1386678192f2d72d37bb779f2cabd0003e	1	0	\\x000000010000000000800003ca54a577e393a3fa11521180782418611070ee715f2ee852d76625d2daf60df7bceb7befb80479cca552b23ec3cd57fb57553ea5b431e25d9874c69e2fca866c9159ffc37684858513fbff195a50e53ee39bf479cdecf4c0e177f235db01ec5c8be43b00525872bdb16f2c8623c9ddf469a8082c707f2f91988dc2976809287b010001	\\x5541a0fe5b6587a5f986c29955fa62e02f0bfef063e6ea9692eed89c2e7d7a37c599c722514dde2075548620e12188137be9bebf94f02ecfa11179ec6c0de801	1671737261000000	1672342061000000	1735414061000000	1830022061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
125	\\x27d9f31fba7d8fb0867ec1a3003a53fab96fbde2f62e77f7eef41fd6ab80cf1e3d804114a0fcdadb25e443a79dd2ea61e6c950321cea6dfa41918b210fb15d04	1	0	\\x000000010000000000800003ae60b0b57f774b7b3ee3690f02bff53704861480f710d60701feb1becad59feba4b564756c07099d1538ebe488a40d42e5f0ef2c821522b44486c0433efef81b88248c7bae6442ae05d1f8601994bec7b3904579f7ccc4fb305bed7f91c2671d87bbb521e62d28ee79900c8d86d8b962cffef168b48dcb3aff4e5bd06bb0712b010001	\\xd90f125bf8e18226f924c892633eb525c2543cb28cd9b7ac9722d28400da3773154ba90beec7af5bfd2ab8d70e7a3bf1e347005f859786ce799cbef9f4558206	1662065261000000	1662670061000000	1725742061000000	1820350061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x31f58e06c4e00add279a7412aa980166cb37a675d5d91d457350c6dec056ed7b35af0dc88c973b470ed8e6c86fc69f6182ae6edbd82ac11fdb0862ab2f37a0aa	1	0	\\x000000010000000000800003f47ad640088c4726567105f360bd57385bf247c81aecef208647d7e553beb17ed0e04ef20e3da1a23660e96d3eff332693b2ceaf04cef38a331a687f6e2dfbf14ef01f502fe2c734c21b8d7c305cd67d5cb58d0652de9c28d10f8b70fffc0ae734deb16b19e179cc3c4212cd154b28c685b0869050ca12ddf741e9e92b6a8777010001	\\x3ed58b21570233e1c77b738a669c38218aab5284092018bfe4024ec868684718ff0dffbb00b5ed4a9a4696d81e64152cf7bb10c05510d29ecc7540c276bbc802	1689872261000000	1690477061000000	1753549061000000	1848157061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x318164cd1f7b13f57a9a047448607a2d0fba0f10cf511ac1ce5dd6d51b553ccbfee261e07a897a65447f0f189f04e52f05c65f6fb356ef17d39c1a9267b0a9af	1	0	\\x000000010000000000800003cba726437ad4c6fa6427cdba62a86db2c59c9c4191b5de03cd4486212ccc1f6fb2512981cb78fa07fab82a14fe318f08e57392ce64404b215fa23e94048f36d53c23b901cbeb59912255e8615fc952c6f2139f4648b9c059c8ae4b9713001d2f3b1541eae9217d4da3d6724ed628bcb753dbcb52b4f9ada81d10b7275020d7d9010001	\\xc220e86615faeb80e266f61d8f462a52444d10b25f5ad2775b24ae7ac9af3a7dfd5fb38f2d28fe9a44abe0195e0853a34a51e150150606627410d3a00fb9400a	1660856261000000	1661461061000000	1724533061000000	1819141061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
128	\\x3185155eabaf26deadd9de32809b3265741e74ad1e2b265977b0b3f2028009e7c56d7f4478f1d6101607a5d46952401cdb648d7dab4f263158b03a905b16e218	1	0	\\x000000010000000000800003ce4b6cbac419f3f71e13c4ae5d4138583d340a02f6a14d73ae7a1d89a461b9ee9fd6b12ca9a0dc325f787ff85487897ce222677613c923caa7125d048cc430b517aff814d07c692c7465d77614e6326ec4ec1c6cb93bd5a62f7bb6342041d0471cd31dcdf8fd70d5d131beb06192b6908c717177b0ea45e247cd4d0a070270c1010001	\\xe280b3c0a1e8f9f15f1c0ee35d779f62dbf5238e47928f6c729e45451f87fb859c042f4aeb2097c929f97cadd130179145034a8fe38c589aa34b4d20af674609	1669923761000000	1670528561000000	1733600561000000	1828208561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
129	\\x391576c5c169015b2df718c3a5a99f06d9e431510b1863f07294f9c97079025626206abf104b1b51b011dc2dbcfde049afd3d066cec87c11bf75cf0530ccf552	1	0	\\x000000010000000000800003bccf2af0ff0891d4d57498ac5a6450cfc50907657615264290db699c64ec34cf257d975998739a613bcdfbe97b0fb87fdde8f07285e96e9ad1d932f420546f4a52be8f513a2c1d873097f544b084352037eb606cc40830344581a21913f359de259ae36a09526dc512531a6440d9a8e3163e6f1960b88be225d8ad44643132b5010001	\\x8a10f9cb94e2297b7f21f86072dd5a1b7ecb57b21604d650b5abb1f2947e113ce612f3a83a2e2df63703a50b753c120bd0e1e67e5d9ca8fdfa15e03828788103	1665692261000000	1666297061000000	1729369061000000	1823977061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x39f98a0047b0b8574be951fe859a3d9d5bd807b274fba4cefeda6339767c04ae66e5ecdbf377ac9497639a45b2e34949721d86f0cd666008f73c3dd72be15f7e	1	0	\\x000000010000000000800003c8d3aa7763f451143560e638e819f86e11fcb76886f519565cb9f85c1832ef81437acb764c5e6e1be403979281240d153f7987d39365ade5251a5a126b7c61a43170c21a2cfad4bec63206dd5573102949c5334ce56fc614284bed016010bb7955cb651c8486d2758ead50be8e2884901964341a0c2db60c68d1cb27fa4d89bb010001	\\x3369aa604e620aadb5e28e932b3263fd97f83781aa4f1cd81f999a35d6bdcf6444f941aa8d56c0a3d38a67ff7b59e7b9f5075c0a9c312cb7a02cf44c8421c90d	1667505761000000	1668110561000000	1731182561000000	1825790561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
131	\\x3e719179a316ee1306efd3507e3f69e948d03890a2f69212ca010308a0d1ba9195c9c3000d33d3623215b2207020bd5801c8bf7a5573c87314024a5569d9e845	1	0	\\x000000010000000000800003bd5cf8ef339325ba26ff9f5aa0095d69cc40dfb395fd7f4caedbccad1e5dfc36386cd9b48fda359783d2f152a573cf462013f622bc4a0c2acea66e6f3d0909423deaab4398132b526f457e9271b1bf6705aeccf6de2efad1a2ff5b9c44f27cc51952397dac8412c582cef171ee388d5d662f9d09810c06285c954ffdb24f34bf010001	\\x91322b5bf027eca5de5f6e1dbb33d4554b5a09dee575e07addf72716083d3a7293ce9977e6701d04fc6b48a5c93027b036d6713dba2b098ef60d8cfaeced5c0e	1662065261000000	1662670061000000	1725742061000000	1820350061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x45fd0dbf6c10f2e6af0962090a8ea484286fe31bad4ebaccdda75553102b583beba6f054a841da651332f9b4a08f088e8db5e28532ac65984da385b1dfa33078	1	0	\\x000000010000000000800003c59715e2165bce0cff74a3b454a8a99cc358aafd2b8c671391a15559e59a3d1a1a544ede2f30ff78968555b268b54f8520eb982305e523c8673b7ac3e05f27c0ad0df6203e8b2e00a5f5294a93eaa1fdf443727cd81935c9f4b127966957e099452003c29c03d293bb815c35eec86b82d13b36498e36bf7ae229c430ac6fe235010001	\\x136503f9d0b8127e4d0fa777a8d2a7b27b0b7a78442d36fdb1a5d02937dbd315ceed288ce84a9eefc3270a2dc9ffc6a05132af5f82560fb608f6307323bda70c	1688663261000000	1689268061000000	1752340061000000	1846948061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x45e160300b3b55b3b739ae938bd9504a9c43f335d83e390f6c9cba8394a4c3faa0dae463fa45dafc790b577756c5cd47f3867f49991fc8275107a5bf9091c5b9	1	0	\\x000000010000000000800003b13777665f18dbe91f809c3163673c00d837e9522e66b8b41a08ff51d0b3fea06e39f3395383ed517161ae4e84eefc4286dbbf7ea76c82c5482a424607a05cc3791542dc3379b3dccf0fbe3c70e4b729e9389d4c6f47a5fb2eba6ca418bb1f7a2fe282c150dadc05f1583c3f99e843709204b26bafbda0a936f8391c3b7f251f010001	\\xd5e6953a23ac320ac83fb8572a7891f0061277349ff4e2851c1d6b0afb718b098e78b18cfe5a3ca87af3ca71685390432342b17d4a5d57196ec27ee1a68fb903	1668714761000000	1669319561000000	1732391561000000	1826999561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x48c17d56f2beb2b6f84d389f38eae446d7a2ee2b57783f83f9055106706fe0031e39bc26e582cdda7dbcbb0db6704d8b4f3102f95dfb96653de318a6c0e8a66a	1	0	\\x000000010000000000800003aa678f081993da44c09976b661bd031279b6a02bbec4ae0d8e6e5a7b7be7a225f29bef9c0cb3f9215b1ee4cc56963a5f0eb46af4f27e670d45096404903124cd5a41ecaabdca590621fd728581e33600593ed7aab60fa802fbf17c3b65564ffd239412bf4d3ebf95d2c22593637d3c5bdb9a9ef246370c7878b2f8c05e3badff010001	\\x3be08f280c4c159dde6a7092eca9b151eeb84340508e9e166156496b7cc35b9225a46ce5c9174b6e05ce456dba8862a85cb2a5d8303e62d95013441da524df08	1667505761000000	1668110561000000	1731182561000000	1825790561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x49cd151d0bddd5512f0fd1059d638297b53514aea5e6adbd04d71622ba0380b55102a7632184a5a83c34b421a42380f729b50bd6ccb9c28c52202bab232b530a	1	0	\\x000000010000000000800003c3c534d117fcf0b8482b668a13fc50129b562bf763c9f5bcb9dad5baeac6dfb57814a1bd69d92f21587c5c25584682157faa20d92a8862cdad80287543e608bfb19c05e57e03a1546f9e13cf25e4638f15b74ce010ba2382d8654f95ef8ea9293d5071bd7aa7e409a6eb6dac0bd12c2322794023a3114bc5fce8ee9cf3748371010001	\\xda435cfd9481dcf321136cdd52332149b3d098b0e67775298a4ff13de84a8be7689ebef5bdd89c9821de7d2163d51229a7b2e0193fbb2cf32effdbcfb502ce09	1663878761000000	1664483561000000	1727555561000000	1822163561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
136	\\x4a8582b1b3dce57f1b2350b29f8e12f0648d43037a4eb0ed102fa8f111d4d85b4a71b192251ffb4035ddb5ace683674eb21674c6ab92452822033e5629f5d869	1	0	\\x000000010000000000800003cbddd5ddf070d90f35a82c3d923f16814a7ede8de032c7283cb8473b3f37dc236d440cbc429036630c95db4461f18df12ff7ec7fbff78b116abefbc1807614d4b8feb8e2da1c63f145b6671dd1d0ad46b627cb12b8456dd2b62d9076dde1c8e6637b12710277003b43267f584090c2638d49a3bf9e946d910aa6a23066413a6b010001	\\xb5eb482ad31ad54de2e63f8737192eadb4324d461ba127d80dfe057e2f7ca20d1b80ac5d6e4227bb6ad5f93226d8b13b2aa6a272b597c057a343b13e38ec670b	1674759761000000	1675364561000000	1738436561000000	1833044561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x4f818827c85491e6618a1b3945c89dc46cd533c94b759b04d8947c16163e8cb9b26e35e02804ef21822b3125f68ca8ec3dd33a2ee10a70c28696795215032632	1	0	\\x000000010000000000800003cf7a63851551ef065855e587fb984b8208126d30c8f7f80d8a2f2dbecde0e26a24fdf84162451889f9c1a24aa4d4c45c6a7c90ca97d46b75a172164ab9f49f03a1ed6323591a2d7d0bcbc38af8d763b75e53a3704fd2788e4760355c52d0daeed74deff1de678fa4dea769a6f496fabcdef6c947eda16fa39084a5d5a23db171010001	\\x95a47a3f1507e105a8fe2e4a92afb65cff27da409bcde9427a978e4b4529c3fc2647705bdf49badc3e44fdb27254d8e268282045ac913d101edaf05c83b4b503	1682013761000000	1682618561000000	1745690561000000	1840298561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x5331460fccf5f064b22d9327aa32f30cfb841c5554043b6c669d74e0524deffc5ddb75ca70e4e47f2c41e67cca712783721d2c984679876e601d714c2362298d	1	0	\\x000000010000000000800003a2ec47a43207aa26a62e9a8fe4951cc85799a7cc32db562e2ad11c22f6cce8af5452a25111cdc36a25302c0712a3d7290e4302acf16818aa9770a2d10be9d06dbaf880ae9fcef92c30cb752f14d073a9c2ba4ad2bc74bcfcc04a9ce0c9375573e19a5080025910842a0fbb1eaeed16b1b640de6237cadb0c746f71df9ba0f1ff010001	\\x515037472b816c610c3c165b4426a1cbd89c6d15e20107c8aab34e322d794503a78aa00c45d6a4c0fd84ae18033c58dc3f57d793b00de0500c102e035cc49208	1660856261000000	1661461061000000	1724533061000000	1819141061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
139	\\x5611b12cf1d45c77f0f697118768901f7ff5f44a10a7598f4163e87c3b1ccf9cd8dca236a63e7ed74b3baeb98efcf6a5c66f22f18cca50069954666290710a65	1	0	\\x000000010000000000800003b8f6e28c3da68bc10ecb44dd1f1a25bebb54befc6d58c6093657051a5c146614fdaaa9864d2d58c3083051633fd83296e5fc44d608af1e5a0b226152c096188e26d469d8c440c5cb956b6a1ea4a43d5e83c909d945e31c185b7086942dfb9e2656e335b69746ab499935f277585289b01ce0966214a4470ebd0a9c3667b1aed7010001	\\x7b429265ff4155497d0ac9cd8ce9bf42b3c5421e6081606f963123e4197d21601a78cb992e37f28926813f1c1b2b907cc21f2cb4a043bc9ea9bc9c0dbddeca0d	1665692261000000	1666297061000000	1729369061000000	1823977061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x606d4bf35e3c73fb2152575797287fd0c435b47d00200992fff34375b9ec8b3027a46fb235e1183fd38ab0696e82435b0570001ab02ba6878fdcef83e09c9bba	1	0	\\x000000010000000000800003b1a0d99a23cebe4b8d543a5211e235279f76d2215164f94927fd99abfbfd92f91d4cd1d190492d3b855ee45d8d4b99ae7e0cce5ac666f1852b68f899dbe3da2c480b2272fb5fec39d35bdaab735d6ac85107bdf5fc9455ad8ea61759368c2e493c30adc59b5bdd22096926415307e272f88a244b4f6ff042d9cd1f05f29bcbf1010001	\\xf2fa604be9c968a8777503a17a807bd74710788f223877010cf340b9ba07a7b23f43a434c63c73d34c4fc7917fe40872d5df688522ab6c090ee823975dc8f304	1668110261000000	1668715061000000	1731787061000000	1826395061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
141	\\x6415fb0dfa6e26189d98d5127c87f3505feee21d9486a0089d7901db2cd230ebc29925ce314e9358d9e0f5c77679a4df7d55f30b7feaf1379e2e0347707d15bb	1	0	\\x000000010000000000800003bc7c55191cf1147a382aba224ec61caed9051bea5c31976efb1ed28fba5cf890d303b87dd20f80104973a585cdc495c7e9b174b3b0453657740396ae6f39c5da84a8e7363c48d586d88904349177896d07af6858514a43f2c484f22da4ae6751f809ed8e7380ad63649743903c6236e20bbd7a2698288d496746a5396196aec3010001	\\x2057c0e75a071dcd20f065e742741745818dba773267fb5e1f59c46a1a8f565880b79e4c04d7456cd5af85e9a8e70925b745868b2d35c7bcfd62898dcde8e309	1668714761000000	1669319561000000	1732391561000000	1826999561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
142	\\x6bd1423bea10c54f50b36cf1b927ceb0a9a42daec86cf39f7f6bdade9bd93a080dc4bdba925a90d01879c0bd4421b405fbe6a05ef46b5de669e02329c2df2bd0	1	0	\\x000000010000000000800003c25ab64727fd085701d5d1ef92ceb1ccd9c48000c675e95b37653fa724cfe798f9dbea1871400fc656bb2e5fb3141bcc1ec08237975cc8281badf707fa6d731f3ce0139bfe17d657c17d12968ad6d9b45313e9ae481e5d1ba0fd0fa6b5e097246f2966e31d5e9c0d459e863839cea56098c56af07c47bc29ba7b0083c08ad20d010001	\\xad55f569fd978f7609543827bdfceb4a1c887c27c345f6bec77ff2dfddf23e612e305716deb65ee6af660c1bd413e2b5a68c413db373b0aa393bcc7506c1d708	1687454261000000	1688059061000000	1751131061000000	1845739061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x6dd17494163be16cf315af46965af8ef7348720036e4ef241e034919cb48d68dc46da46a1fcbf5e26a442fc88de2a4f40205322b1d532d85722544e1cee06419	1	0	\\x000000010000000000800003d18a3e7b1886722e9e11c38cb1fcd48c0b14a684faef41b56751b057bc585fa8a9eff59c2d8e314d7f6521dbdce6dcb7017c9b6e62a3feb7f9060416ef2881b3265d51043e9ba6df560298e43613599fa3a4994278263f8bbfa01cc43cfa258890538b09b9eaac6546563c22d760810c4004f2a1a7f21a26c1472814de91255f010001	\\x4d24090f27a9cb237194338119846211555d5ade6ebd91549df4943789f3a2fffe699b102faaf5d711a09144ebd5d66f2431cc2910532f11e90bb560f37d8f07	1678386761000000	1678991561000000	1742063561000000	1836671561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x6e99979ee4f7b3c670d2cc67d0096bc677f26d9409b2ec3cd0a93a1272fa49e7ad3da5d7d24323119918ae535ae26ba19c39ed008f44c375374780eea9bf51f6	1	0	\\x0000000100000000008000039371ebdaff9c9c84b30b5dc8176789e503f5b6449dbcae7f3661fb39f41f1e6b554bd148245f23fa9a5922186fbf2b1b1a99fade03c5ef0dc793c9a625de575944898c608a20cbd2b482915eaecc524f99ca25a90eb061f5a674063719e631f1d16e2d60067407ec45cc100c2d98ee9e0c0f9c2e90b9e7fd1296db232c2dc1d3010001	\\x11615c93782a9e936badd9766cb4b3a7c3281f4fd124095d4088e3eb732e70914542568078f4ad01f10f957ae5aa601883a05992615d2dfa6297e514217a2603	1668110261000000	1668715061000000	1731787061000000	1826395061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x7171fb0b68d339fa51147945ff8fc8981745cfe3810257172a5884e45217089d2ae76681fa85c3093b160fcb4d4f8283a35be30e55fa0d66f72c7fe7a6daba6a	1	0	\\x000000010000000000800003daa12d6edc705b4fb4b2c1431a569c1e9da4e09d3300bd3d3c3a7e12445af44cfbb7527edacf3be50743b6f172e8d62cdec31f72d7729bd2f11ec9d49b84f21e740b36a7abdfa9535174eaef08fd7d6d071eca6898aed3fb67af121bda633882021140675a210dacfd2ad67bdf2bc93b4853f0265ac28443af6282083d77553f010001	\\x4156a63da181405fcb9f920499727612751bdd18ccf4e97c371d443d7612d4ed9e87b0ecb3455f7afb071cde476e9d8a009acebc2026d3ef4ebc4b91b826e406	1685036261000000	1685641061000000	1748713061000000	1843321061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x719941ff09a8154de91d7ed0d22b0c12a69fd902ff6c2945f661fd882dae515018aa115dc9aba3c5ba43c0b459e7fb3ba9a1ec42ec20ff73811fb99e8a365acb	1	0	\\x000000010000000000800003b3345ab0ced9700a704c4bc15f3c045b99a15208f340f24428dde4592baab8ee5661ac4c1e91096dc34ed7539b7c28e74ef60561b61aaff594f464ca502e1b955d8fc5ca607372f5b58d91f3d134771217360cb368da38695abc50340fc24514fbbb852b8126437116ef21a0e948a01faae00d6f4aa2a2fbe4ade3ee0bfccfc7010001	\\x7e256ba53a4218f520ce4cb67717c1694fd5afa002732586e0afd8c870d915d5f8e7721f191dcf873f1033e8cb9598676c88b48cba915e85626ecc6511814d07	1667505761000000	1668110561000000	1731182561000000	1825790561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x72395d17c7c3c88ae7b04be05e01665d29894b437a178789a0df4e4305aa8ade31a2ff0bc53c5c4155b25ac03f137cfa756baa6fbf02fd1ca668d2dce91ee78d	1	0	\\x000000010000000000800003ac18380bbc778b6cfaba3bed05e5dffdec961a93c8fcc811f110921faa79fceccc87355fe4898e1908982474c078f0f3222456dfca5f5cff15f715cc93f798ab224ba64c69da453bba8b0f0eb438e076f8157bfecbf513186e08a1c2f5ab1411f175fbceb2770cdedcb844e7641310ab36b0bce7775ad4724ae707fe6c882999010001	\\x06d5754332806aebd42bafa785b3b74820369d7cf9c5b28f0b12d35672d1dbd2c2808103eb4b743f572eaa0b058fb05391a8a9bdb09aa68738e110deb0553a09	1661460761000000	1662065561000000	1725137561000000	1819745561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x75d9eb683e3401b4bd33b6e9c7be211426d5f19518a2d43aed0f92578909f50b4cd64014e551d9d8310718219a58f0494cde69339814bc8d10b652ace400cd03	1	0	\\x000000010000000000800003d1ca1fcbd2ec74fd5a0ce2ecfdc8bdedefd8d2c4a46c156ccc75ba69a7de06fff768b0a384bd63a1e4eeab547259e36cde12af608d8364816588d8d988d71fab0f67247abb3cc24435b8e3b72e0b1e6688ae3d2ed031ed4ace21d85a39c56d27a3f2f684d24ebd973eead8d891c8167a8aa6b243727d5ad245af078902e16e11010001	\\x6c52619d2675505e36bfd69f92f02847e7aa8b7e186a762c3da161dcb4102dcba70b1c67cc74d877cb7a358bfb7a4d40872224b05b47cf03d02e17d0146af105	1663274261000000	1663879061000000	1726951061000000	1821559061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x7ab1001b7a8eb066876476182b2c8d28c2c3174a4c2e4dc5483fab64fc102697a665d4f9e090bfc647f0dcc3808f4e6c48b7db1fb6eeb2cc89f7b0d3c2bb7940	1	0	\\x000000010000000000800003a67e25ad75cf6175a2d22bc67154aa7ec53a38a09387e66090b4b93f6b14cbd5e1ee68344e3c245f89d525175a4b206fb16b366d036c3510d5df9430b0208887e5cc6691f57b8ebcecc93e31a5401fa38f8e8e5cfaebd5eca50763c9ed8fb263722fb8821d47f99895f67b410a556d1010b83896e49311fc825e7c0825613199010001	\\xb1b7269a1946d0c99bc3ffa3b027bba9a45952bd675b7759b49cbdb25cd95683c99db72b836f915dd0690c5f8f087c837bb12e86fb73508a8a78805e9f7b9600	1677177761000000	1677782561000000	1740854561000000	1835462561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x7b2121ec5da4a020e1da7d4175d153aad9398e7968cd5f177d5a86d6f1c69febb0be02c935809888aca568ae13654decd785526249693ff71ffc0f6378128c0e	1	0	\\x000000010000000000800003e8a60894abd6180c8be790278762176460be4d81a80985b13cdfdef1898ce8e74ad297b9638c4a5a143bc17869cc510fbba5cfa543faf50965ee8a251eb382a017086e86ffb9d83fcbc438309254dd978965b3039568e5ec8c51ff64b27406d3055c052baa0a9ae1011956becf9d5971032cc7d3e7e3801f5f2fe187c74ac4e9010001	\\x402a7b0c11a840652ea356e4290ebd07c24306c3b9df445a95c8eef1c74053eefc22ed7bd603c0a8ea3024a36b16f3c1abbe4b64ca31538fb480fc2a96d6bd05	1676573261000000	1677178061000000	1740250061000000	1834858061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x7b15c46fc0af1b784238bc71d7055e5edbde4882aa6a293c9e6f29eb6b26e6f6e0e5bb6523ac79148144444fa7b725293d31ee0c39f1a6f5b9c0a29ae7f6b51a	1	0	\\x000000010000000000800003b6884e8733d93e5d1777a6cc2ec74c0fcdc375596d620f16bde62afd9e6f51077477db3c4ebd84c86b9b4a0cb91230e0f79a567e9c45a35370288d1e6933fc13d12c0c77f20a90803c6745948c8ca050a90b294158e7d34b76597f64388fffdaec749f1f042952bd7cfad4b3781549dff0408fd44ab04a86c73e81ff77fdcec3010001	\\xc669c90d23cf92518c3aa0d40e1bc5a63777032cdf8d92d544113bc996a3a4d64b2c14e67dde595477009d9bac3196ace06c05ca806bade506a640a246ed2d0a	1663274261000000	1663879061000000	1726951061000000	1821559061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x7bbd138663928cf3684489f98bfbde9707239238e3d3ce1bb2f29076db05aa96d346cd0c3516742e7a5bed21b5ed74ec8e8a391310a09277213124e2e55772c4	1	0	\\x000000010000000000800003aed17c241abf4b690891a682d72e1835b4a4d1dcb0c6e5cfae87d2290890392b6becba3f9eabd61b8f3f9131616d4f29455ac31ffa21d4b7867d4b521483ff591a19baeea1da2b4884aeddf51fb701b116191c2e8329e33bbfdd22b70957e359f92bdc937d1ad946e8e15ed17acc438c1443dd460785e85260823d3b4f555cfd010001	\\xed71603efa27e875ff96faf7b074bad7c4f88547b67e5eb89d4f0a008d6e4e313e89144c81361a86b8d25c5b15c75e1f1739ba9b14cf788b4260d835059d1c0b	1664483261000000	1665088061000000	1728160061000000	1822768061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x8039ea40fca0abe4b6a9e4c20bd49689fea4742a30838020ef33e73456bb445172019e69682de00a2336be979ea831373d4c564d5805f14022bc93503ce22412	1	0	\\x000000010000000000800003b123a895eb7d993a6ff1d3f546717fff724d82d83a379153a8fd860064e701d43907c4779679ee2eb04ce2efa85fad6f713e7d465ed0e0fd88cfb2ba3063f2984ae6a4cc6b26b912e2ca9d0ae21a61a3e08cff9d33ccb593761539e75fb0eb190c65faddece443e06faa3a564ff37b95815a5ad0061837330a93a84c3c3f3de9010001	\\x8311c55d3a491d437fbfb9e389260b1edecc275407b7723da0dd008e55da427f293ea9c357359314925ac15d72cc2d6561307add22af03dbe50b834789605103	1675364261000000	1675969061000000	1739041061000000	1833649061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x83656d7fce1e00609358c1fb8ee565a4dd833d1f9119aaf9ed4649de57a9e46f4f34d53c8493ffbc19285d8aff55c810aa138186c340522cbe72f8c1c225d27e	1	0	\\x000000010000000000800003e126640cd69c03fa5ee8d42cf418d9afa12a3c2ba003f4bd78488cb6359760a6fdf9dc06e4fee4c6a58c684bcad18c06401f332e464b0f0b68e3580de8f180902880fa053d0564a2f6d0463888872102b6a185a8d540e6a3eb0c2142364a9d1c40f1bd90e8d0d5563515b12930203f393b73d96a1b44de13f28fc32a70e1469f010001	\\x09a58aac2cffa0247e38f08d8504c10eb6a618da0f09c1820e49833bbb86d0fa0b446e4c014f4b78d10fd903ee25accfe8c2d284d7ced8939b17deee076dc902	1680804761000000	1681409561000000	1744481561000000	1839089561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\x84bd9a1d7189008e101ffa9ed5d4c89f3dd0bf0209f7702ec8fd36ae118bad2c9e103818700be8ede242826ddeabe0d0273725fb8d73bd980e482bbcffb6cd0c	1	0	\\x000000010000000000800003d3674ca8a675690cfe2f7e659ef203194c0c3b01ac52871455cf1265d6ae691992add2f9625087e778dda35bdd7356720170d26a5ff8667d81c23a1df1f683e251343528f0fb80bbc720f196b3956fa9e573d4497425fd0ea717391bc481e42337271f119f454c877e490ffba935ec9ef7dcbf410383fee431a9de8c0ea3df3d010001	\\x3b2781a6a1a626fb498d684af9b03fcd023e8acc2a2c780135dba86a0b1ea738f5ed6185db6d18f226bec97eefc561621d0106aa995e2a008f4972b04443c60b	1682618261000000	1683223061000000	1746295061000000	1840903061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
156	\\x857d4b0708ec86b7c313982ec2f51af622d655a4318bcd2a533ac0a6ea37d9145070e586451ef231bc6215caba30bf8caa2c8d7005a15652cdbb1172a0f87f7b	1	0	\\x000000010000000000800003be55ac36630e8e8650d149ba00c9b75f8fc0df5e60627945c1ca55214afe1027c54295d046dc4a7acc3bee429e0769c879a650516c7466fe8e1b41542b077a25abf8e79982b8741bb2c4ffe2759f8c2f05586cb73841902e709f8403a50e36c855b9c160103df0f7d1a3fbb25763886ed316589cb25b5ca6f914414e7abb52f1010001	\\xcdaffde005afae8b1d8a14a8486e82506b20cffdaf288cdde4ffad8c4a387fa529ba4d2df7defea95f7b753019ebb3d0191fa039fb20b9898fe583d23e3ded04	1690476761000000	1691081561000000	1754153561000000	1848761561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x874171d7c1c0c4d0e3d4cbe3a79e19eea238018eb395d6506b87f6dabd15f4b88f92d263e74014756ca8670ebf1167e144185facf453796175be9a0ddd47786b	1	0	\\x000000010000000000800003e1a3bc7d27f9c0cc2dccca51cf3373e599294fb3e526ee5022e84cc78ab7af309fd9a384c60179fa52a4dde70dac454b1aca5cb48b59253e87f50b65d3353fe282eb13240d05af2beef2c2127a2811158e842cc687b16211d0a4beea54e36bb0432a32bdf99723a2205e5ba32583f8b54185bf88c918c111d359e8364d4721e9010001	\\x3f4f90723dc2518a21da5a9732c7add4dfb0500a2294c0887794d9f4c2eb16ceaf80dae4137b0be9a1eacd2f194e32b71ec7daa1885e2a8dc2f3ecb701cf990c	1683222761000000	1683827561000000	1746899561000000	1841507561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x8961ba3ef929016598aa27b3bad8116d5683b2e679b73a10f6dbbf52a45f914c2add270f63689b05855797c4743102f823a57c9ff6b974861883d049f37860e0	1	0	\\x000000010000000000800003c49a7787eda860e4f621407476226c71b43237b8a5fcb7ac0f59b6d52f7400856e10f489d57ee8b17cf8579e19cdb1eb7b8f2e2517272e463b55a04fdfd824fef6ffdc067493af1fe8ee552879fcd85588d014a3e6db755836754af13727c841495e9ae5bf711d687116222da540f382db9dacb20b5aaa28432608180853005d010001	\\xa818a9ee755014b3b6174148aae0b491f22dceafdf8dac513596f78182725450fc9e29731c953130cd2b88dc475eed53abe3b98e5629cb124a66724acb1d9e0e	1666296761000000	1666901561000000	1729973561000000	1824581561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x8905fd396fb072f9ceaa9ce790915feb0d01560c2407d010f7ed980f692e2b0b9312688d1ea1dd52a8283ecdcdbdb2b02f9f6615f06944551024ff72963ac243	1	0	\\x000000010000000000800003ceea18fdabcb48815188e9695005d697db499c56cd4b1cbf44610ab0acdf880ae41273de0ffaf1763f3c95905dff51f0bbf91ec4f40d42068cafd4bdff87084eee94bcc1bf46caa6dae716af7f949efa335855246014b714a28272e6b2f6b5472784537854b9f6a26c9a16f6f4e7c7cc9ab93b529eee9b29321ab8791a492f0f010001	\\xe7e688ef5ff7eb3282f85cac5f98e3279612f8ac1a382f32964d47c2606a7318ccf363166ec172c1e6a351aff52d7c6c69ba8a9c6cec3e13eeff1e9bb3169300	1675364261000000	1675969061000000	1739041061000000	1833649061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x896d6c0d57aaff5f7289fdca2dca9983e7a5acf58f4f2804aef9f302b70ebe9926cd4902096c2798462131383c173c31f3bcabf779644524d2cbeeb0ed10d27c	1	0	\\x000000010000000000800003d78b32423ec7a92683ef5dff8a745b9a63f6eda193c554b3574caaf91a36879edc2a5f617627dd1bccca66c8689ae24b323548733832bb100f998a0f950fda2e6e359f5a6508022a2b66e594d5c456c687d3acbabb4ad722ef5c77d6bfeccac3aa9572a9429f165c43e50f08845aa4cd4319d211449fd1943f0fffb456321973010001	\\x3f0acf773135e24eca81660890b20edb73fbf347d50d15d678d8ed966dce9e02fb0e065e6c0360e27b46f276fbf13dbd8dd5da69d3e47f7bdb75488526556901	1662669761000000	1663274561000000	1726346561000000	1820954561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x8a6951364431cc64e0e2363c306f517de14e04794637654bf78accceec6c24d102bbe532c03df7ab585c39bf5a94cbaeb48683428e7a1422a491f52e03cd746e	1	0	\\x000000010000000000800003b14b95e4a30aba31cca5d880823798c6cfd0b241a4377db4351372b7f4da0fa35c440a11eed6b91de5214d8bb25db3328af02a249d797ef6f56c22f9dc4fbf5aba6c67d9bda9d2ab3570fa890496f6b38c683bbd925a3eebd42cb64864f69643c797be246b0f871128ce6f86df9410166e81f79c83f80ad0d4d6ffa93aa5616b010001	\\x1af6926d0ec9008fc75dd9b63c46667d6cdc8bed9c9ff942e985d2e8836481d5a5c1cbd6c7e3e9d100384984c9f15e5ea0c4bfacfad3ac2019e664e9ae1a9700	1666901261000000	1667506061000000	1730578061000000	1825186061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
162	\\x8f5d30df3c5b6ed84c75845a1974b81fcb52c600e66092da5ebb96edaf964aaac62fa030392c84f7fa20ce6a562451b227f2160f1c78b21bc1baed2133adcf2e	1	0	\\x000000010000000000800003ac5e5b18a791375e51e4a116668dea9d746c195f188013a34799f80d0b1b62af5961bded47a07d0f40eaa2fea1c1e6bf2550013431b849c97eae04fb562ceb2bda8cc7167ec052e6cbf956056e6cacb26a45e04622a70b9e5f3488407858f349ec0d0da04bf4854978b59c8d70f28e2c11f7748b155373730e4b31cc0dce4491010001	\\xb8421c60326605eada32f5102eed9d0acc816502a1111a8a78f792bedc92ffd09881d66ba617dfa23864264a07d476293fa334da78d0b8c6fca6d0e06cf62209	1688663261000000	1689268061000000	1752340061000000	1846948061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
163	\\x93f5381b17e674a9688f882856f661bf84b815a616d73605bc381c827774c8559afb965ca22ff1c953463551905897a2c1e8f5ccd4845ea23b28a21a26e8e4c4	1	0	\\x000000010000000000800003b819aa667705d9135971481f8fc71f693c2937624afe40d5818156f0d09a501da044404426bf479c41c62005c551afce7bab6e87cce59633d455500dd39acfa0f5e77d96e643b644567dfd71493de851e4c9f306991017b75c32578281d1dc7eb274237ca19130cc3153cfcfe43155bd927393f051c2ee890b048f59931ff7f7010001	\\x137d0e968825da309698148f89ead14e3274c5f2f9993e10774d52bc69472f48641d0569a019537b7bd7ae97ab82f54b2e28f5c579236bc3d1c870a6c0ccb309	1675968761000000	1676573561000000	1739645561000000	1834253561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\x936558470510e6113a048bc3addbffaf2a376410e15cd4996fcfd0f367c65dec60ab0a6a50cac3ac0784d870fcd0914df89bc6ea2f61351412a5653eaafbac42	1	0	\\x000000010000000000800003bde367d7db5086997a2301fffe54d15e4a2fb59a14d58087a7f16b038ea6a58d696110cd70762aa95fde68c04d9082eb6b524532963a1ea4749dce6ef99e505e420866d079922b36d160f032142b50be5e8efdd69be3730139f2b0072ea9495cd7b756622e276d0a621b348c60782ec5a75d4374675a11fa87fd4f1d998ae6c3010001	\\x79f746622cc491091cc376619027b190eab941cffc74b1e81ee6d285e1ab32ca04c409530b76497c18f36c0ef851379faa7daef708ddedb1642245418d0f4805	1681409261000000	1682014061000000	1745086061000000	1839694061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x9389e00cdc08b8c617ceb458460520c142600809f26570e602bc6871364c2a5b88d8949ad226ddcfdea345112f9335cb41a2724aeb48006eb2258732778379fc	1	0	\\x000000010000000000800003ad3a9194981ce0f80b73a9be1a8458b50f0a39ad00abfbcf211cc7788a308e61e13fb32ae40f6360ec71cf7de160c229c977703f5d218ed78564112a0ef451507bafa0d14ec0242f379d9c74616c283bbe6ceac61f06bc9da20eafd92a930c6a76eb6a58a43deafcea97e7201c9f19b375455c3ec050b2bf2444dc7cfcbc01c7010001	\\x04ea3125c5f03fbe86209481a0d194f6e9eeca3331616fc3967e132ef55f24b7162d6ed44377f686551eb22cc9ad8f8bc76d74f2ab1b62a49a735baf8963a304	1672946261000000	1673551061000000	1736623061000000	1831231061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x94c5d5d8718531d58df0f88c862ba471375a837d58c43b580482d1a875577abfb37e32524f79ab7e33bcb0d37521f11141d792e25fc0aa9f3e54c77d1521c514	1	0	\\x000000010000000000800003ab1461a607a2c6cd5a002f43d66809dadb95855a6a765384f409ed1c963184f4a6e890e21668649b726e4714365e99f1b1eba84289fd4e0556331a40bbda099a6e51d13f8dc3b77790c56be29f15510374945edef8a6ac54b01f2fde6bd41867cb93a112b506f39cf6694f30f7f40595513576b148db84018e6322ce7175de53010001	\\x1bd8bac6e1acde4be6d6dbfa395f6e439e369029ddbb3087ff4d29bf359562f93a3858912195333e5131cc6093a7f132e319bc8843d9a9a28d329cd1bd713907	1666901261000000	1667506061000000	1730578061000000	1825186061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x9565901980ee23fa49da46f8cd82b74eae8715097827045f2a291337da69e4d90ee2ed823ddbf36d8ae6fe692650e91197a4ba950ef862da5694e403f7626a9c	1	0	\\x000000010000000000800003edaee21cf4c0601b9f5cec95c2d65dace601ee043dfb4d7dffb5f924160309e1db3afbd5290cdd9ebc917edecd112861a0ebf628cc03a17b9e693274cc3e2adbf503783ed820009ece99f5c96d088529eb8562f7ba35e867cc91b779e6b462179a21d9c4c50e88e8986f978b14611aa8fba9eef20cb64e350742a563c08c8e6d010001	\\xee6437254e94152832a062ad53301c544f9500143113ff35868ff40e2c0bf9a604deaf2763fe8aab3df2181d65b060ce02cdda2dba43d7704411ec2bcfec0901	1690476761000000	1691081561000000	1754153561000000	1848761561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
168	\\x98d11f3eb56be89a934d84d87d0a0eadb8abde5a5b441cd851e3f82b14c76a34acd7d62ebbe1ced4a47bb44a2df357b5daf40ae403478aff290482ad0fa61d09	1	0	\\x000000010000000000800003e1dfcc3f8c2fa152bbdccce0bc75daf45196a40070cebee03b5c537713d05dffe0ba35ec90b260242397045b6c24580937e4062cfb077efa07188c9093cb1b80057b926ccda0749e30d01ff1c43bac899f9f4394895769adcda285f1d900cce380f6bd11c74c5178defbfd7ed697eb8a4c4f24d4c94defb5ada4fce432b7ba5f010001	\\xa13e073a0911325838e71206f2641d53a4b7f185a4923e9875d010affce919c1c2a77719d469e1f724ca2676c5c15fb8e13cade710240fd0bfb241554efced0b	1680200261000000	1680805061000000	1743877061000000	1838485061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x99114b92c5da27059d1575ef20e2646004c9f1d90fb35399ccd2a43ddf4e921581312dd8c190a003f16f6c93a74e68240730f7e854185f330f888a20f8ba5653	1	0	\\x000000010000000000800003b7d081d8aff4a2d6f8177557edde406522a93667b28b5709818e67f7401f6d78eff63b65d927d58a6ad304bd39aa87e75e3c35ced1dbcf4e88ffcac8a79169920e08fcb4ae2cdb717a864e1c7050184eca87340b73bc4619ce4514b242764c6d8d441166e3fed3777eb063a7d410a6118c2e73376adec73a1d4df3dc77c53b1d010001	\\xaae1204b33a52451e17e22259b30d1391760046e4beb2efeb09345f14ebec49af579fd0b770ef2ed4e601a134380fdd99986038503e63b9997f27a5b5951f708	1672946261000000	1673551061000000	1736623061000000	1831231061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
170	\\x9e6dcf4b64597faf7e318f8588b824db7a18132b2c39078073da6c59ee52e8d1a01ed16a6e64a472194d2342314007c455a6a50498055d67011ab5b3594dc320	1	0	\\x000000010000000000800003b5ecfc7cf8ea9bc52d5745ac678e11b84fe3270e3bd7b6a636c2a80c551c5e92e8a311728ca042c1c3fd21d256367e2f3f8108ff0048a5dd3aa66b0b3af63ab908eabb3030c49dd6aba54b53fed734d4b3edc2d13e3379690e2fa9ac87440bad61c6f1a49165fd3f1137d5cbb7c686a3a06624128e7f28a2c8be5237100fff67010001	\\x68569d7a6512c7ca85d96bd7651671446485f33a9bddb745b894df77c6af1b8b99f818607b01cf2cf4863930f258f41833aae7b909466a7c4be374c0ef9d3c07	1666901261000000	1667506061000000	1730578061000000	1825186061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
171	\\x9f15767224242e0ec08146387cab266d49c6a2a789c0767c4645a0ed59522d13b19c031d9ae1b25d879545c54eeadb0c2d8b939b03a1fd327e5f296a5bae1af3	1	0	\\x000000010000000000800003c66c0c9dc675450111df199ca6325ab0ddf503fbe071f2af4b5746653695e79e71797fabda1d5af5f2a245f5694731a14060370acb262ea01d7646482b375845251b84d5a8df39cb7e987ae0995edc46b64fffd53e1b79ada8b12791f183c5f4b29d44e28beee40bfef6d7d9d867510338716d6e6a9fc0199ece86e2fc0ddb2b010001	\\x96494a997ca98e67723fe3e398185a37921fe11d8e787e13310bdb54e33f4aeca2551bec289f746e03211c2e26756e0a998380ab8f2df762242c01803fcb4502	1673550761000000	1674155561000000	1737227561000000	1831835561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
172	\\xa49dfc1f2b2dab6fa821f1e99d5a4f6707520a3528d15fbb315b4bf4dc8e4b35c663464e83862ab6d23fc6c55cf2b534b3ccfe56e1cd1ea07c7dfca65a1498e2	1	0	\\x000000010000000000800003bfd7f803fb7ee85008a73bac0faa497028a69ec9d86d1713582b60922aaa013dd5abb65b8ed9040cc8aaef53cafabe31542e87ba1e8cb83d3eaf8f97cf7507ff603fc7ac299017d56c99ef2b1bdda8c29b300186b7ed005cf2e0260e9d32782135d70229386febd4f167fe28d911c31b6b14ba645a47534b631b03fbfb9b4187010001	\\xfba536a7d477b67ceba137af5935bdf393d4b73ad305739981a0594b49f0820e7c9c0d7a480b30511017005ef8f43219e55c95743c78975aa29c0667150f1705	1680200261000000	1680805061000000	1743877061000000	1838485061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\xa5c169121c04114714ec953166dc6c53ce0733b82696cb85f1d048cc31cf5200c4b25712607bdf16e5d252791822a0847fc597de880df690f34e12fef72204a8	1	0	\\x000000010000000000800003d81740477a22a48431b4d94b68722b07865d05587a0c06c027008f5b94188c5fd953fbed76ad1977e15fb9e6086ae5487bc3f0e7a1858654388ee1a7de1082d8a01465d57b6d4027bfd655781f9441e5ce1fc8186cfe8b1677747409a2eaf93e372fe450d8eb9d52f62e8e5cabe5575725e6d579d03392bb12ccecdb5b7fe8fd010001	\\x7a48881730e90c9f397b0232f51c67b9c9c4c96074d0a02f70bdfbc1b4d2688231e651c19369e8feac9d18ab74c7c143bebafa07e7b78ddc0372e0ed74d6e705	1668714761000000	1669319561000000	1732391561000000	1826999561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\xa86d7f7b2f7df305c5a81a349b64fce57a3e1807beff4a7bfc0c85db5aa4b5fb624cd5d443aff209136d91b5ee814efe6ed579b56937b2f3e170289a479c4771	1	0	\\x000000010000000000800003cd203b2c0bf01c31059e08af7f09bf577c70cad1f642cff1eae4ad1e60971e23f5cdb98904f156a26e2868350d2e17940dfad5332be1989525160d0c96e917f0f90297d80ad90064844d99dcee11304621c9ed85a7189df530ff627556c0754a75eada35af4ed4bd0516344899b6a96fc49b03b24b8cee30d93e626988d784af010001	\\xab21f32736ebf3e42eee11dcf39271c0ba60cccaa23badf4ed2773636af02f4edbac626e982ea19835232177c1cb6b87796ba32944efb3bb83351d2249de6e02	1669923761000000	1670528561000000	1733600561000000	1828208561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
175	\\xabe1ac8215995f832c49964ebf857578ce68df4a5ffeb38a6619ac90d45cbd6bb98e76553c349d45d4b8716c5159ff93b37ff18f51d89ea04d8c42d8a3434957	1	0	\\x0000000100000000008000039565f90cd7a9a442027c7205f146ab0d52557f64faab085ef9438e62d0866a225934493aa39665f9589c01f1ec4c0e30b07e2a9f3d806764131b5a59e268a5f4a23da6cda489a249c8a580fc40f47aacdd1b9a7aec700501664334ab43d5b61c9898df3df54ba4fd81ca89aa9ae2f3c60ced25aea11f750a1f088e3087d6f767010001	\\x0d4e6d64a95d1bf8a380048266419e8fa63fcbc437c90b7c02c06afe8eaa4ee66f3d4209c8a8bde65aeb80d617c447997454f49b02bfa5375530408ec1ffc40a	1661460761000000	1662065561000000	1725137561000000	1819745561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\xacc9b31939f88eac07267c50b31b70d5c88d5cfc10b601b499888fca4dd12e682a236fd227293609903238c082d10f87a00f8e63a3a15e0abef8ee9a91a8a27f	1	0	\\x000000010000000000800003beb18e6008db32c1d5ce000f442e83ca16a46477b792e1b975cef33d51812d3121e2952f508458898556e6b00adde8504cb0de484cb219af2f535fc801a6e706f4a33a9bc933a1ee0d916e3f43b1f5175010337470b236711b10eed5a09eb7fc315392c1596f9d68bae681f176eee5a3e2ffc8827a97714f384dc34b3c953d9b010001	\\x161916346334eb6eb07b2169cbe9eb880dd75ed1ee22de044f82771a0e284ac51ef542fc7634d86701f5a1d1e2f0d41fd7b6248f64dfb6038513a4e6b79ccc07	1677177761000000	1677782561000000	1740854561000000	1835462561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
177	\\xadf18abc02c9537514611acffba8c9d6e24ab42d6cbfb4fd0b9b06a57f6b0e8ba26a4b221ff2415daa23d6afcfd365967f0ea934a7a982af93c098639bd57adf	1	0	\\x000000010000000000800003b9279c6be82a6d55bec7259aaef9d5c3c1f5534a92ea0dc9f699fc1c742048b34fbdae77a1de21db68190f162a6b306b90c0eefaf3cbdada42275c0ff15dd52c65376af288c2c2b4fd708f0a18b5eed98c95e9967fb248c3e5ba62196892d9e47bc1572168c6dc9b9ce0934f4bd5e1302e4b92c0929816275c6258ee9be74585010001	\\x6bb14fd9ae8804966e255fd62c773570e32945b033a2d9865abfb07871463ee469047d1cdcc2407609062e34615bb9672696e13df8c9a64523fb116cba19d40b	1674759761000000	1675364561000000	1738436561000000	1833044561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xad39e7a189d3053193715ef6ba2b4f52292725a71e75e464ae9e75fa59bc822991e7b2d5ad7c248359c46d055427232ca7c90f00039c98bf1e765ccb45260b0c	1	0	\\x00000001000000000080000397122e64c7cd69c01bc1848dc6970e9a10ac0cc743122bb5963c1f3d4c969921979b157af209bd50e561b058548c2983d12ac8b7d3bd1d61d617d29a196b33771ac0238f869af8fbc652cd3f21ea045cb7a24134369f0b3a38897e8212c47a658d2f5f73090bd8f2dfd69071cd58278bfbd91844b02d20d2b0bced9b048ad617010001	\\x91bbacd08b26e6129e421bf9e54544e0d6040abbad74cd980a20825d16af5b3cec8949cfd3759438e038756a629379fbe8de3f6fa672b16ae750209bb406fd0e	1677782261000000	1678387061000000	1741459061000000	1836067061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\xaf059f298bfe80367466c6058a7672f96ec739469247bae89f19d489ede0c26f5c45cda9ee8c432a15ce40bbc931fbf7f94d0a59432358ca3d793d1e5670351a	1	0	\\x000000010000000000800003999ff4a277c668dbac2174cefbcfbd6a544902a0f85762cfb6156b134800336cd3482a1190ca07327345fa49925221d6be64bd4a40c312271bf38e56ce077bcd29af828e055708cf55af2454ebdbbf0c35735cf365e618a0f2c80c6b991cb890e722033314ca2ef0aba5f13ead0067fc6fb2cc69cb63fa8494ef99da6ab29aed010001	\\x4cd0b6079db860cbe8ed7b62b97f270c729f7f640af8aadf53c082b68009d03bf1eb37a8f0c4294011096a467bcd074b03de56bd299cf14f31e1e70e0d8b8b04	1669319261000000	1669924061000000	1732996061000000	1827604061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xb111c416827d2f63d057ddbaaaa771aedd7f342ce533864b1ca5dd2e1cd414f9b3ac6d8e4b740fb436e2d8670173a9c4b075b9d8724e1f0db6eb743eed1d047b	1	0	\\x000000010000000000800003ceba20b5c78f8dc1fead81785cb2e7d50633e08ebecc522b4ce543b73d865e2549b8488dc3457670132f86b5bde1437cca28e0c8e5734ca0b4be7ced376ed8888d637130166b2eb599de9a9020338a32efd87e1a982e55a10d700f1d5c0d22b7e2b4f7df331fd3d27280fb1c075c3b55188e8559d0613a37088bbdb2af450797010001	\\xf901a30a7387e8b7632be0b64936347b5716c4b0caa6a0132ce8156f8613b5d31e03ec1f1953f6c64f27a5ec34e290825f78fd1236ed3ee8848de36227784f0f	1682618261000000	1683223061000000	1746295061000000	1840903061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xb3d1054372909156e84f3733438091b85d9d9c1b0400b53f5794eb5c9d004344aa454a00866554a8c7edd7c7f2bbea21c3e8548f58ae0f1e9abb2af804b1c294	1	0	\\x000000010000000000800003acf0b79a09b22c66dd2886a0cbf046e89726c599960b579579c389bcb6d697524d9f4cb93a174f2883287c1c0b8faadf61ae2ee2489a3322de44b3f96953984d784c3978a7ced9960a595f43c7456a85346ff23990cfd0b4f2815eb1b48bf1791173252f3f468224378d0c3f34f1c38787bd0f7bf8676643e1efdc8f23c61873010001	\\x446d9c1ff0d7fe26b6f6aa0ddb15f7d6fb2c61e55745eb73750b627bbda51bcc7844ad0ed20a37b055285f60c50fc368bff5b774e33ad75c6d041edb52eaab00	1660856261000000	1661461061000000	1724533061000000	1819141061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
182	\\xb409554656791ac15e657f8066e125a7c093e6b34a2bfaaac7b53328d6966fd2dd0a0440e7c48708d12bafb9c79126b63d36ea4a54d3a712a7e84fb6983e4d64	1	0	\\x000000010000000000800003bc08e6c228c690dfb0208a14c030a57840f8620a3abfc4c70e88a12c7e0199fbdf10314f181980b24a45d3d18e432613cf1368d00fa2d1bdf951449b849a8ee5f43c497da069ecc55bb86c2d866ce16b4aff119607a87b16f1db5e57a2e8208a82f2c61fecc3b0fcb7ccf62fe02bf8264216aff65bea95d2338f3bb2ccb2bd39010001	\\x85e736325053c00a35b50bacb76ba1aa1ad46d358ef107980eea256b4a07a92584cbda973dae8e96486fc3122adc64ae70b226b328d2d87cff2b87ff55386e02	1672946261000000	1673551061000000	1736623061000000	1831231061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
183	\\xb6e1ba6f2698b9079cf84bfad0cc84c0f61362f6e706ebc325d2ff93433ce7e500969d2bc4c8905fd929c47525c297ae12576f58342c502cbeceaaa23bddef70	1	0	\\x000000010000000000800003d9927a28b796d6418643eb28fe24d8f546b380166fee4a9f5553473fe8e59d128d9f1106aaa05ba284a94f0afc83568d6e79ecfe37877ecbc07b5509a35f26bcb06fa8ae1bfd9a027803622f73718d4f860a6dcb908df4316827de3898b7706db97122b949295fbe614592b32b3704d7870409c6a674e0b4ee5ad1d0a3a2701d010001	\\xbff1b74efad52dd9acba00f28ee6e2f35ef2fde7d2d46ba4306996f4d9be91f02592f70f547eaa028440e23a429a1c019d43a2f6e69b3223ac8b91b3d1c38d0a	1672341761000000	1672946561000000	1736018561000000	1830626561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
184	\\xb6fda74785dd882ba83fc22db6f04cc668a938c36a124467a6d74126552ccbad9d46a6c4a0b2b2ec4fd102a07b744a1ab9891ae53dfcabc28faa77513adcd773	1	0	\\x000000010000000000800003c609f7c61ed9a5f74d8a3b83d3e7d86c693f9736502588339017dfe3744e2434283bbb9c8ffb40af87dcb712fc059fffc0dad1d4fa1b50caa676df395e5914a3d01450016f6d7bbaf01eaefe4fb4527c440ef483ebaebaf457ecdef5284485bd0968ae74075fdb209e38d540e39eb0d9e385004b1af0dd5eb524398e454c304b010001	\\xb140c90b44a5808ce7998a6ffee976dff15c41c250e7ff7f203987caa00673c0ed778228956be473078a72097d04c94d0e373a82160d957e9f5bc32c67f49907	1691685761000000	1692290561000000	1755362561000000	1849970561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\xb72d613d29fbb9a6e64e7989d769cadf11374da7c9edeefd66c3dcc563769f5cf5de175d6a482c34270e3da022c2139246fd5bf1c1b0ba9ca665dc6ad74cefb3	1	0	\\x000000010000000000800003e1ee1752d96be4cabadd11d9e2598129c35b4bda5b0477e2f2c9d56b0f113d92516987ab22e7b2b8a50d13f5fb156a77ba92edc8498cbcbce43409749b0ca42273249e6262bb158b696edf5d72d89b4d97df526820f415008c64fb339f0d82e448d21a5a053e6d2297318e185d282b469f837f14572877d304764a1088e374cd010001	\\xaca95c18814623d37a98d71a4a796bafcea850412fb7712433a5a854cc47129872e28332854996b5fddb069bafc0e9739b93eb5fe736806763aee62d8aad2907	1689267761000000	1689872561000000	1752944561000000	1847552561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xb7b5cae0daf3085d7b38bd42f805e5fa64b1883d002bf1eff98828141f6bb52427938330b17969f28e1508759490bcdfd252391885f5294a18677fe2357a53be	1	0	\\x000000010000000000800003ecf324d9ddd465df5b3a97364d27688ccf8cd8435a7639a4abec6b0e486b0fb076b9f9adf7841faa4c26a4166206c26e29996888512b08afc456badad3be40eb0ec8feba352c532fc4c7ee949e25a32b9f921e8e155e6f1592466dd019787a5d899252049f46761d5278de834b1bd2757e3d0cba32bb4df55a6d6b397659fbeb010001	\\xde77f077025befd6a2d6eb92a050480e4ba34d9988c0c4d92216d1ee2657408266aff4456ec9d87862c8f378e8ea8934532af8bcab2ccc816184fbfc2c7e3c0c	1688058761000000	1688663561000000	1751735561000000	1846343561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xb7a9a34550dbf37627ef1b1919ff0b0347a2dad3f42d4f1129b5ab983483e1c81ed7714dcd782bb1d3c28d16a067fa823fa8b0ea9555fa6b1613dcc8c8feca9e	1	0	\\x000000010000000000800003b1c427c295dfb7308749160173c30bce95d721603d78deb1373c1bcbf4559f707110336e79b109236ad077529a9c85e4289407cd28911f236b574c032566ac444e9d9e3f71f63cacb242f0cae57fbc543f5192259299c54dae2b56031f2dee67a3447bae5c8db03139c2999e3bd8e7f7fb57a5741da3dc25edc63629e033235f010001	\\xbaa5c2d21f1255a35f0b5cbff22e007cd25290176da32a94500226040e174f5de5cb9a048d1ea481d7279af71d8105315bd5682e048792f10f2312bc28361a09	1663878761000000	1664483561000000	1727555561000000	1822163561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xb94598115dd30d991fd9a606aa03e2dae0c92cfd5460c272b7eb1be258adbb745178ec76cd06c16384a80c3f02ddbe690cdb201187e3c24a20fad2c1d552bc3b	1	0	\\x000000010000000000800003b92a6db0fcd91edcf504f948d56e3be7e67a1104fc57c975c8d9b3fae04c3a179007b06fd98aca933c3ae9635b090e206a81f960c49315d7c8e1601b17cab7ab32ed2506b751dc9a4d2ce8b58bf9dcdd3e85b5f9b82eeb3e1153d1d7f0c9ecdebba2d87249fd9fdf37e103de4d874d5b3ed71ea467f2d2247cd7fe3dab1376b3010001	\\xdfd3bb7492b03f654d4b7905b67a63e23d8605be8799e98cd05afe1dcb70c13cf83124dc4636deab0554f60557e5962611c72453ee1385f32d49d33e14eacd09	1691685761000000	1692290561000000	1755362561000000	1849970561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xbaf5d11ebcf840ae84218cd913ba3782a82514b92594cd1a381b9ae012d505955487ced93adf201b5ecb748218d7fd8427c4bedd71d6f9189f95b5cbb7bd0043	1	0	\\x000000010000000000800003c28abe1f68afb25547c29605ac53cf82f9adccec1575654a9be8c79b7bef0703b696006c00bb6514e8eaccca9d67a7c31ac8975e0a3bcc63e72aabfa43e2cfea080c605c98bfa4a42250a1fbaa64c4ccbad642ded4d76f078d86850b674115da8e599aae342fc0aafaf23fc50b267c63ff0d29f198d5e11cd6d8366d538c5737010001	\\x5721228e39a2ac5dd88c416d28173c8f6f1fb141c48d53780af22b30e966caa45c6932bd04b435aa5814b7271c0be5e4e82348ef2d9dc7917b07b9329acf0207	1685036261000000	1685641061000000	1748713061000000	1843321061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
190	\\xbb7dd0e1c54f31e72b316a871d0b08b6181a0a680b788de21ad21907a22d515c69c70ade8d2324bf4e5f2374bcf1caaee7e4243746fc8f16b42f4ec6a5f37668	1	0	\\x000000010000000000800003def1c3bb4500af350a9c68ea98505132eb0a27f669c2f83da4b2ca9a70572350f6a407fd4662d475685140c0932967eaa2bd162aca56dc838f7ce5c7a6abce2c482542c0e3c711f61c8e3ddde9122c748ead9efe142498f4e51814f7c386dc188b705aaaad7d912d2104a517194b5af304e9243c709334d27b6c13dbb94c1461010001	\\xbf1ef4851d8d310b4b0084a5f22bbde58d0c4872f160cf60633b67ca0e7b037b737e4176932425b57ab9316693567f29074c5ba409fe6092ad0ff9beac4f620e	1660251761000000	1660856561000000	1723928561000000	1818536561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xbe85bb887c4eb046a10e0a6f1096717244a55826123d09ca65cc926b3c0c79ed727af06dd4ea57448ff540fe05c2687c8aa55131cae413b0836c579ce9f83e99	1	0	\\x000000010000000000800003c831f9b8b9d84f832740ec54937675cfa1cb6c8cfa898c0140020f11d491e5b935b6474edb033acb2038bc0cf2ab7ad135a450a3ec2bf762e2385533a5ab4bc491b47322ab8045db0ec363157209ad27b856b0930b56ee3177be9f8d8862f7a45b358c269588338de8acebc6fff1352722e5066366be1cf071808438046b1dc5010001	\\x4313e24550241187e4ff0c888ae802d2669f81e60bcbe4f8e6f2ba49997d13ef5661d235ed8f08cf521c53d15319d176f48a54fbb31f5bb70c96c7ba496e6a00	1672946261000000	1673551061000000	1736623061000000	1831231061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
192	\\xc0411922827485d38f067396d9238bd6172c0fa7dbb1f5eae9442359ce19af9930ec67ec50484cafc5d1841908400e54ee34d79908569f186ac8ea115b437ba4	1	0	\\x000000010000000000800003c59cd304635d56fcc0fcad156375b010022f3d8943a04236794e8100fada2ee52e79e2b4ffd6544332106435416ba283ff91fbdaa45682d277abaad8d65815daa226d83aa8d1f80895a9d52bb725259b8b10786cbbed62026712be222aea72ad9c89fb92ddfaa40aa97ec09db545f1fb9f33b75831052f8f09894051f6d54cef010001	\\xbec7baac0bee2a990b4880b4d5a69613685e1b05685223463121681c3a04bbd8410ce5d707127d2e2d4461316edefa2ac5f5879f7b57b0be8a6427f76dd8a807	1675968761000000	1676573561000000	1739645561000000	1834253561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xc23528cb3ba8ecad9ffd8f9974868f37cbceba730ee21ccf4206da31cf4acc4eca8f2e2442e95b2dd09132aea091e5acc3925040de95631915f023967b922d64	1	0	\\x000000010000000000800003bce657328eabd2d44767a4498159bd00f246ac871d1a585a19342c53f284db6fe0bd13746065a06b615d18d4978de06d2386233ddb7aaf42bdbd36e58a31ac437d76f87784cd2a0a21cd16c57efa29e22b1437928eaef3b1363ceceea4d6840dcd3d6e0b8205066603cd4047f4024706345227b50de69a20a7d06c16f005f7f7010001	\\x2aedbb9603946a5a3b72f8d6fc9cab5ebe49ba81115400098e26249b9a431388e348cf93404f9bef365e24b6f109aedb39d385cab170e8a287952de527b39e01	1688058761000000	1688663561000000	1751735561000000	1846343561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
194	\\xc6692ef70a54db93b9023c07331dcd6ad450e1847f78af088ab11bd6b268e1d1ae25492e4a67ad437cbc3388a6a384e4496572ed145cd8105e252c67a3c4c2df	1	0	\\x000000010000000000800003b9dbfebf86997f8b9709095c3503d7cb5dd3a91cd21c054a2a81b3e877f47ca77823ade5531ba2731a97d39e76a0ccc248ea4b0ec1728012a85228d1fcc9488f536ec44ca7079ea7815e7cb73f72a028526203ffc9b4a7fd3beb5ec26559886dedeb0d44d29caa3dbbf07bdce3485f4001ca77efc0c3426515aac922efd70ce5010001	\\x98214b4b131a853104cc70a94a86de2e1e8d63b6abc5e1f3b49b76b12804563db8e276040638cd8f0c0798d37511b31dbbaa838511cdb86e09870ab11d5c9406	1665692261000000	1666297061000000	1729369061000000	1823977061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
195	\\xcbfdc5ac76b0aed052fe25c41270ad32025c1248522f00da7bdc59a9ebd400f6ac741d613c325d21ee94705bc1ad85c5613a342ef3dfc9f3b1111c5473a0dc28	1	0	\\x000000010000000000800003e05c1567b8f9156d948dc9bdf1d39dbf2ab49b296217f3f26e4e7647955bc6acea9454ce7061f9b1722a3e2b402d437c1b4a6e15a45333bcf8122089b7a3e29bcaac84d4864acabdf36aaca756045b75ee2c1a2259f639b6d43987db273112394e215c56812b70f8540d0c447117e1a62ebb429175988f0a98310bffa771498b010001	\\xba8f93606385f2f09a714bd59cb889c0953e6fa7d999fdf756db3f7563dc503e89e1dd34832eca4f23030c0c144cf795f01ea45e4d1bc92f092c15724d88fa0a	1660251761000000	1660856561000000	1723928561000000	1818536561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
196	\\xcc0105cda29bb6e8d75e482ba9557fb85a567ea713484e3b7285c2b45e29abdcaffb7cf1b658959564c2c32d98f660c0cb65dde38c46669a9db8feeb3b8aa0e1	1	0	\\x000000010000000000800003a0c804c2a033427307c15f384defcb64fcc1d3367c95c340d46ecce0713d3dbabb8fd154706088f36d707ba3d3b564d00ac86193ad3cf96f90aa6e029c69a8ad7b633e7681e443a82f2c3da22ead5de7352bab9da36c4500cac22526937efa7262f29129d98a8abe3bb23c765134eb83b02eea4c3804a34b5216c66d13fda4c9010001	\\x20708e8fffcf951e0aca355d70608eaa81169101c3ddd36d94ddae54ddd12ffcf342665760a97604ba6d90d0c752f6645d53338c8279d3a5cbc4c372996c940b	1665087761000000	1665692561000000	1728764561000000	1823372561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
197	\\xcd49a8d67142a12ab59bdf8cf2df3aa847dac1242138c2329e4e262aed00412b74e550e1c9d7068d4af2534021252f7eb039be98c9388888b6261adca26c914d	1	0	\\x000000010000000000800003c1145a5f4d8d227ad053290b59379b0cc8dce482bec446d98c127779adc7755d535276a8e9c49a6bfc43a83cebcb3b0681622641049c03a01d4e3ba18336ba067a36548e8191839e52df3bc78c11a86d58f7e4a51155a8ad3fec3c20f89bfe18174430d3956f3de2d1a2e28f8752738418be810a79c30a06faa41dcac2aac5d1010001	\\x203286fcee3722aa6251c574565a95891520179539344aa40fabefb35e8cb06e2d8edd9f7ec40398f27b794862ad2648264dd54ccac91d6a2d3379b26a12e303	1685036261000000	1685641061000000	1748713061000000	1843321061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xcdb5b8c09b41618e6e696300d558302798ae2df76d1f6cc204729286cc759eb2336fa2a8b6db9a41d32dbc868dd721741184a6298e4b4f4657235cb333bb7c8d	1	0	\\x000000010000000000800003ce24cfe06d37f3506ad07137b103266daa3faf89775b76e94d141b98b1ee20894a0f6b999cdd643c56870d934da4163354f378fe52cce2354c390466c3200a03266ef4a45e8b4cd6051aab61deaab77f08f1797e1f1988c1b38b4145ca0690934f28fd285952148f2150997c1bdcf37db0548e6eb4b07d2f067baf8b7bd4cbf3010001	\\x6e4a3780645b39da7baef4c4d2f5a4d2ec555880a82a5ea15b9320022f55bbb3867e2212fc82e927dd40301b1070afabba9be86035c9f343800ba24c17d11e0e	1685036261000000	1685641061000000	1748713061000000	1843321061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xd0214c7877ca818d165ddcefb22d03977bafc34dd2f866073e02f8343a51687eb4c26d89c88cdba40ddd32728fa0261878ef82d8c6bf744214e1900996e0f74b	1	0	\\x000000010000000000800003c20e884bea5d337f49f67102431c5bac7f19612ad4612b9ec1d1223c9bf5d7ecd61f8614f787469218e206eebb0b4966df14cce37c9608512de15b7e53153435574bfbd40c3f5a17c27b95b73cfbdae72872376ddd84ab1f78a5a0a667b43fb343c4fc93cefa60f1e9871c67595067e6c1a94380828e9a8c1dcb5de21439ed39010001	\\x8eb8dc9865e018e70e3d4425b3e5174e70ce08a5b806a1af750c3a4c5fcf6e2c1cf944094016f614e97815208bdf876e9c56b202c20a5583f1afcc5acfde3309	1685036261000000	1685641061000000	1748713061000000	1843321061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xd03d74003366fbb8a048fdd6730af3abf1401550092d61c1c92072c4e7a3a3dfcf5ce14a8fb955ed408097eec20d4e5fdeb2f9abd57a2bc4b030fb0b492195f7	1	0	\\x000000010000000000800003c7b41320c6bbdc747486e7a5f99b54aa86d1d20fdbc084ecf43df2d542101e22cb6e47daea2b4be3ec689a70b2a3b44ac817381873142f40563d8e89f8cb1013f9e8f015c1b9ea467cc2e5d25eb6184970171c63cdb2e0fdf29a66ad6071b0056e32d73df82dca178ed91418433390044026303819ffcb12b29dde75231b9a09010001	\\xbbb93db0a98b82edf7d161caea744406c5d7661bcf6c05442997b413433d88128a721228afec9c728fcd2317eba4d6228b47b446445471b883d5fc69fd4d5f0a	1672341761000000	1672946561000000	1736018561000000	1830626561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xd2ad6c8446654c74d2e2c46ea00a06bddfc254ead78f27eebf9f70bc4e4210e4c9057a2f519091827616ead8235b422a1602268b7af4a3450f92e2b735ccc176	1	0	\\x000000010000000000800003a5039e70b5f2b5d624f465491c77259f7244ed170680e137974bfcc57e19d02a38f00e84e0e3520825308eaa196d2dc3506ca3286da81be1b8383a7df06917d0b49b3e321788701c9345825b80dd883b86c663c578790eda21305f68b8098d5bc0d16d2b8e112f736df4ef690375de3f33ff662af638a1115dd32c93cf9e3669010001	\\xf5471344785c0fef411ae52705649c10a62737906751154c0cf94fc681781c97e76e68d76298a3c7520eda22b7b7b887f0361d8e6b0a4fcd93edbebaeb2a3f09	1689267761000000	1689872561000000	1752944561000000	1847552561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
202	\\xd8cd509393ee78f731b4382d984b36cfdd1458e7bd535cca6419e967c3578c09b783e9a1fbb88b0341e20085c112482b8fffcbb71d92279c6a26afac2b0eb15e	1	0	\\x000000010000000000800003aca2e997d363e6f9145df8cebaedcc338a507e3c701de346ad18b8a8f627ec780bf6b14f07534555ae067fbd304dbac8f28eb6dd072865b55513d3a49b8142b653a7232466a2f857e10cfd0b5b2a6f17e40ee5b81e42d30896838ed1183122382e4f4cd0af3bd49e7127b84e62b3fcdc8bf43e034b06a805e2d002861c035f2f010001	\\x5decb48f40a1c281b010589dc0ed4fc48590199e3459ea16bd66c1b7740593cb70121989e649e62433f39c3a04daeca927b23f3331be6ab1235ec0bf91ca2601	1684431761000000	1685036561000000	1748108561000000	1842716561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xd8d9edfaeb6c8970979519f9e05d7da5578296e47e3b0a5b4f40781bd82527c2a01addb14dc6a1fbb567df2d7b164c8d93aa9e41567ad34bdddc4620d259ae8f	1	0	\\x000000010000000000800003a388169da476ebddbfb1c3493dd9fcb62576e8fe8993c7833694d55ca90fcef721ad43b139e2b7cedb7f3bcbd32c76c4915d0198c99a724d89e2542286668213bc490e06d109463ae4e810f1cc17aacbdf3f7816d12a22fe0aba7438ab334c90c59b31452de5e1593fa4bac35cad3a1bedca5d27a7e7c6db1c4f4f8ec04bd4f7010001	\\xe958fc08bb53414fb61ad220db0ceb2a003a35dd96296c91308d6763790bff36bc17ded09e7209afa9b85f9bb6c5f0f81fd815c0fd73c5ce6c02aeef6cace80e	1664483261000000	1665088061000000	1728160061000000	1822768061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
204	\\xd9598d574fc3205c06dfc5549450f79da1976dc02aaa4f76720763714264dc71f3e1d3e170afece8efc05ea9befa89f582c0e8e1b7ac1c4e7708fdc1eebd0a15	1	0	\\x000000010000000000800003e526c4206a8d83b795a3997e42b934f902665c312ff0aef4554e908122719585d414ade656df94944a330bcd710481251955d6814aa6e43a64e741dfb9cd22e177da10eb2439cb8e309bbbd657d0b0595a8d0ca5ec29a1eca24d6a6787fdba7d01bf8f0d1fd21d49371b82b61afe89e816de8b129f82862e9c7d03ea8814f25d010001	\\xca1c0a51f8c48a8614adc4340204d508649ce7a0dc180bb325b816e0c0ad51b740f9300716c1fdcd11f9c793bc91d3f28b3f1086ba64f9e4d9fe3271ea824201	1677177761000000	1677782561000000	1740854561000000	1835462561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xdaf9658dc8b2755300c4f60c9f95961b475abf4295faeb0f99d4b5428660a4c9e877b62da650bbe9ba8c789a53afff13147ed119ba6058d46d531788d7797734	1	0	\\x000000010000000000800003e405d7afe1dc36dae4f3eade27bda6a3845d901f4c81a534e701071a49e8a3b395927e4dbecf7d2b30420b32fba6f8f209173b53ba7cec62a62c4ff9b34691dd2418e9d7fab9f6430e4694e784de27e0f7f041a18a9150da6b957a1d6e903b3ad3a3c858a76501dc90435091ad7812e2217dafaf63d5c6dc2086ff3c7dd6abcf010001	\\x88abd465884a7db133db653bdd5326e09c3cb84d43b774f330cfb5a78eda56676a8d063b98ce72b568bb95d38b42c721fd20908fcc168e48c265db9d7a68af09	1689267761000000	1689872561000000	1752944561000000	1847552561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\xdc15b9b9efb076d05103e3810afd4bb3a3d4ac13f299c7668e97ea8ee80ffbb7990ea7c78ec9f7472d1912ed688014c3d360a418ee73a1fb9e0999ff7569312e	1	0	\\x000000010000000000800003bef977c1e0b7e0cbf5208a49e40e03e27c6cc76c1ae086ac49bd3e5d25e76aac2740690ad6a1371994b3ed27481fdb59b30b7ad5f02307bd2915fcca2543fc6122547774d5eb925f8ba3a85cd0fd2652a5f7ff03fe85affecd19f41b053d8a233461c89b90406303fa6156548c65381ffa1a84f3e130ac6794b8f5c2763b25dd010001	\\x88b4e90601ec6cac570f4d92660cec8069fe2b2ded05dda15fda6e3ad0442878766381e790fb8ec9644ec216f2874eb23ba0b75aaee069d5631af3644ba4040a	1666901261000000	1667506061000000	1730578061000000	1825186061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xdf857611b45d3aa7d0f1eee674badabda2d9b6abcad221a3aaef02107557d55183fdd6c412bdc22e66093da9ac1a23ab4e32074de76117e66e2deb6448581107	1	0	\\x000000010000000000800003b20568827376ff48f179958fd3f0103a622b30ac87b571d8a552a539960fe111833b8dc6a676adb0354ee5867c9169f8c05ec6968d17b7acabf525cb8ebdeb3133414733f64758798d3c1ea0a043c49a1d8670cd176ecc940e8fafa3c0f7437944b26f5c561d9e7227433cf484a955a8e09029dd0627984e456066d8962c5237010001	\\xf0006ae608eeee9427f16f9caf0dc0d4101cc425817b707ae4e434dd3097c8f0df1ff1cc7d57615f6934825f9b0afa2cf9b415c8ecbba09e8ac90a50f4d6410f	1670528261000000	1671133061000000	1734205061000000	1828813061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\xe16d5bd6c746e1a541d884197f59f5a8658a28baa32e98f32fb1c4bf467f903579810478bcad7a02037fa61851366f877b239e629d848bd1ff56aefabfb5256b	1	0	\\x000000010000000000800003c7d31625a67726f9f65433961bc967aba5e0586a482a93ed2828f8ad56f3662369c2631a16576f64957604c36a95a1a6419ba8b11dd03d37e93d4ca0626fbdb33185f28aae91f242ccdaaba787043c038aa3871fb9f105f1b68dbeb3117d4bcc0bbcbf20afddc61e9450dd30a437e6bffeb37806dcc8414b262221e9b429de8b010001	\\x774e9a8d822b3c9bd6937d90b5a7ea46f97d216e4d7fe82a6d3aee8ffcbd5c15fca736fe81e878bb4c232d01d6c2efa9aaa1795e36bc392bfd8c2068d552db09	1683222761000000	1683827561000000	1746899561000000	1841507561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
209	\\xe20db27939d2a3ff74cb224e2a866317cd63dbba989463e3070b8e2321feca3bcd6b67737b0237c5113209330b2fd9aad13d8814f4c7066f9f7a255c405e3d66	1	0	\\x000000010000000000800003bc94d00d36aab11b4b8ff9c13f9cb8ec07b55344f188688e234829b9caac88cc05205fd583759f9f5874f38a70246c33a11b6b231d63d37df64ae1001586b09946b082afb9e3caecab6eeb30fd32d8a322bbd77c5a4e4d670ff4bba7730e95410d6da8295f354690b3f2e83c5d35a26ca8344f13e13185f5c2b1b26a2aa6245f010001	\\xf82f64525ee66c643760b4b971c5c229dbc902044ed279fe1793c1993f82e37084375c39b23811772ecae5835a19c9c05da0fe17495337e080276ffe6ef3da07	1677782261000000	1678387061000000	1741459061000000	1836067061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xe2913d7398a964bc56eac853b4dee06a4cf29abd7321fc87519a5e95c3a05891245b9f64771572bee28bb2e7ab5b06bc5d24c3da2ebe53eb5e73f93055060e18	1	0	\\x000000010000000000800003bf8d0122c74ae5cb7035667d23ffb5cafbcb016f7e1741f2261ea9179d757db2c89ab7790303f0794e27f63c9c706c17d51310f65fb769be210901dd167300e056b5b12497aa4986beca8547d8964679599002efe3c8cf8fab0e35fa828742ba10f49b9f83a5c896a23f2dbc2e2f92fffd095eeb589ad5f61ae8bbf34b516b77010001	\\x6cb87e0c978a47cb17789a1060e89d30f097f3aaba5e1a06689e5626c42f49ff049494a4f6c764fdfe18803486b3f23892b6dbeb6b8c67e5812a71bd62210608	1675968761000000	1676573561000000	1739645561000000	1834253561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
211	\\xe3b1ad914d2f2ffdf5196b5a3561428ced59ca622ecc427467451eee925a18fdae495b1579e0947183f304c4d0ec3e83835c1e41976b33329e0d5cb1b73d747a	1	0	\\x000000010000000000800003cda35fb5c6186249a09e087c34ad67d2468d8e936bccbbd3cd95ccb75c4de58e0ea1fb55eb649467bc1f22c888c868ec36a8f01b53f4e2c51891c4eca73181d9469f48d1d403f3ffd19933ada38979adaed15b2f4e54327ffd890021497ad28bea47aac27ac51a9d8627827d3550889fab665dcde8f5813f2605fb808cab3fb5010001	\\x81272d07a926c335fca5e8011de26aa150ace3994adfcaac7214d5ab1269c8f83f0bfbb59f06e0cfdc453db2b9386a71cb09788c186b7245bfc059631ab2f50e	1674155261000000	1674760061000000	1737832061000000	1832440061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\xeb355383778c0878c542b21187c1e093a6018a5b350518f326c4837cbc517c86c68a1254635603c7734f833e8fb8f3f2ab8304faef952d09940ffc9af755e3ab	1	0	\\x000000010000000000800003bc7f02b29720fbaeab0e0f74c4ca61cb2904b46e16d705406c99aed546f872d438c96df02741d0fc04347a05aed3bdea3f67807b8d1e2b175baef9590ac6b2b43d06f043a3d345902f34c4ebe7da8a923825315c15b6eadc749e71dcc996f83e5bc6acb7410f23b593617cad4327c4ca1f0f579dc176836ec2506b250f026d3f010001	\\x52de419fdbb3cf949e8b5ac0b74e3117a78ee2fe75bbafa13ce4c6b8fac08b818b6feaeff995260c7801c0e9206256022503f8e68494f6a125e82892fcd2b20f	1668110261000000	1668715061000000	1731787061000000	1826395061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xecc961bdeab669bf5cb340c3223082075300bdc4ffe29bcb5d3e83fcbd216443a4d88725a9a5fbbe195891cfcf2a0cb0bc5aafdf82130017440a3e802f6039f0	1	0	\\x000000010000000000800003cc84bd00c2064c68fcc1f1520cb110eb10b601a7110e612d76114a6f31a9bd1fe5fb63631c907f6ce1a01676be152296054d922fcb88278f07f59c1785209d54c45aad5cf0575d29ec615e89eb68d74525ba6592f7c5def991d5a4832eec3b4be8857e4f98cfd9060dc1a10dd120072896dbd88b0609bcc478b58f540c050e51010001	\\xe2be4efa82fb17c77129d34bf924bff1e0d3815f9b728aeb2731280d236341889337e2bebb64a599d093f381618ec8e3756f232fb23ed38b8f5e651daaa72d0a	1687454261000000	1688059061000000	1751131061000000	1845739061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\xed7d964f5716688a8822a72466146d6a2f2f28ba2b7509f7dc9e0ec4ce94b1178f0231c116dc04726017f92a1362c124be5995c63760cb2386e204a6e78b2e6c	1	0	\\x000000010000000000800003dfb2303105c96bb02d76031bb49a7947243cd87060eaa761e904064a8f687f091c35b0edcdbd8a5633ff2a03a8bffeba70692dfe3cf99f79781c041214249a1051caa617f2389e911133ddda09263679f1f935ac91068cf0dd4c381f8bd7fba99b779402cc7202dba398d3dd596608e4872a3249d162d99aa7336d216ddc2dc3010001	\\xf24382664972e58a4b2fd2fd510fde4b7ecfbec5d941fd46cf6d2e8d014eb181c276303518600689fa0d6a01de0d3c313b54daae3195a22fa455c138d091fd0e	1676573261000000	1677178061000000	1740250061000000	1834858061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
215	\\xf0d125c9f7c4e24135919a40375be390bf7ca3130653ccac7c315167342d817f4f5a0f14520d32ee6237fa19816c9856d2515f91406c2f0099adb8f59b8e30ed	1	0	\\x000000010000000000800003d6537880ab5b11ff53ed9768f740757c9f02da969be344dfc9d3f8c5879ad04691c141bae4f79c8455d53f86ce659d63c550e539ab62d4d7b288bb563387afeb04c1d1bbf1c686085ecf6a3104c7158a682a1757c0e610f9a747fcf44bcd2f63ce90c9882c573d589e2d4d11add8f7b805ed970bd5c06022a73b60250fa6d877010001	\\xc9988b89c009f30f0c8b0a04644b35261b239ca917b27c74177251fa14d5543b0fa42a29ecebbb252725d855524a1590db715a87d7ab9fa9c35b9421afad4209	1691081261000000	1691686061000000	1754758061000000	1849366061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\xf3a5ed15109d714839534d6533df59da9d50bdd39963ee89d771c5ae03b548b64c8716cb4ef64d22e56c8b02eab96db8ee058144168f2e53ab133b51133c1b68	1	0	\\x000000010000000000800003c7edd24fe3f2c8c62f659acff5e3b0026c468062fd4b2f4389874076535de26ffbeb1a18d1df011abc8bafca8601689cf54fd311f60fa9b52edea0817a0308ea173de48500c784b4b825324164413f1a4e64c69bf1ffb29776a60060b25e0add97588d299d62cf6261f84116a3d8f59b5643859a3f9d2a49dcd141d17be8470b010001	\\xe34d8b02eff9a7d801b0951ac9072b534607510a6a100f70fc85557335ef7e86e0d912e8e22085126f78e8fc5f225fac69f141e8e6adb1c79d050e9279248202	1690476761000000	1691081561000000	1754153561000000	1848761561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\xf4b1d580acbf88b74ecb8662bc8e3dc5209339d8f6becf40fe5640b9d4ce9f0fae093fb0d15119e414d169c085aea0c3b68ad9b61799e3c85c54f23f3b2f5f7d	1	0	\\x000000010000000000800003d62865f5773222609fdd7f49b307ba39bdbfa15984cb5062f216b196ec5052e870dfcf70b1063144a2bc78049abcb444a85c666ae2e6c1cbfd5d22193ea6cb2fde9d32ee59b2ff83548341d515367955eac1dcbc186d2c144fe4e4790907d83dc597ba260452bd5b22838043d23fd10ae8846c19e13a73fb7f8bec7b54b4b2e3010001	\\xfd4428eb25cf2b0f6b85b4f87523a8d827efe2351d8ddd202d3aa92c1cbe376ba2fde43242b9fffc5a1ab17cb74d785c8207b9d9d161932779cfb62da037ee0a	1688663261000000	1689268061000000	1752340061000000	1846948061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\xf53108f0c203de2ef1fc2f43b5d07cfb139927e1abb63b69aa40362be83423625d246317ec27f3ac63b84d75c19880b9702713d5f605816b2ece848f8fd6cc03	1	0	\\x000000010000000000800003ab0c02f6ea3691ab2ebc78235ff838905770c0ef20f5db09d2a17a71b8c6799157e718c4ed32c23e8947672fdfdc162adbfd5131ebb3eb89c068b45e9ae401c27504625c1340d3986264034d8413025d08c6b9d5e33baa93df31a46d6d0fcc31716a953652b97a2a560f342ae9c20cf91c20b443eac55e9cabc5b0d0296006cb010001	\\xfdd9c53d627bed19b083fecdf016680d9f3ff34ec8e801c9d13ca566e8e2e3f8f91daa2ed54c6b9b2873f1144ce0a150b39e0bc02df0c306cb131297d4b3d60c	1671737261000000	1672342061000000	1735414061000000	1830022061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\xf55968c0cb17c65195a4bdb7d35bfbf460ba0db87e9a57e0cdcb441c93ba3569d439331937c3f5688503b42f4f2818d43f613090bb7143ea1dccfc32feafa919	1	0	\\x000000010000000000800003c130d83fafda2aaacad93754c2b7c030ce31df0f4daf76dcdddaab100f187177cea00a07bcb3fba2aa5471e24176e848b768e0315157a3a148e2a550313e8ce6f9a43403c10c7235bf577e3a1458d357af71bd45c23fc1d2e90b8f2f8fb68022f9751bece1964bcc601844d250deec81ff2fac9e2352e4a0ad0118d961b10527010001	\\xb75d90d7bdbca36a28e4270a5d25dc755d040a7e7751d55d15ddc23ee1423f24f90dba80dffa54d2ba6c22b56d37083f32933684ee2eec22d67e9c818138c909	1671737261000000	1672342061000000	1735414061000000	1830022061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\xf729b30faf7f4e17d8ad670fc9853024c20145fdcc9b0f1db57691eeac5740c36eaec9a90ca9635c9dbad8ca1c2fb7be4d9143da9eb282a5a8bccd8b9137577c	1	0	\\x000000010000000000800003f16a6ea91aab45b3d66e32df9784a02c3036bb996658575aeb0a3418b94b6747d40eb6798c23c5ec73b4b8473bfc91188c58cf4c45d5ac888612673000e6166466cff4a534004667b704da1b6cc8167dace47388256304e79f3df764164d344bab4ec847c60d00e1c0d693178181c2a9d8a3233746adcb7485e2fec1825884a9010001	\\xc72a14aeb8f35bf29f30ce2d6e4b79c744544fbdf300ceffb1caba949987976def219ec2f23c343ff54706d22481ff7056eec3876a81d4bf470e7b7b13756809	1685640761000000	1686245561000000	1749317561000000	1843925561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x024a97ec0a652ac3d8fb754fbf4542a999bcd5af7ea6e69b602d4e2cc7853f5a7a17e425c0b652a612e1b900da7d397d8e2eda0c9d20733bb92c3c404cc18555	1	0	\\x000000010000000000800003c12597cff809efc2fd7e05c1bc1b5784f343de7fe32f2d42fafc903a51e330c173010187cf11a67dec947387213315055decf38e6f69c66c71ae20936f10b80aa3409426a5a219b130db5d07e18503bb0c28661a31d686d93552640ca4347f8100d4e0b1dc2affd469ee67f051ff67db46beb379a11e7213b5a8385ef09a6ac5010001	\\x5e5d2b2351fd7da63eb0df6ec3510105f86ea232bde2a147630b3c397b93ad2adc2fd058673e621307993b2cef19d35d302da83b6ad78ee0bba8da5c6db20807	1677782261000000	1678387061000000	1741459061000000	1836067061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x043e25a37e06df67c2b3df519b1156c117ec95e6611e78fe2e55f5fe077425561298b87471cdee61462d44aaac3b76806563ef006ef36361952a7b57386bff7e	1	0	\\x000000010000000000800003e2c273507e23a1664105be617c90c063a54dc59143307c3a2e428b12b7d722f72dbadfc71f3075430d3a0e5fae37779c5cd519a9527476dff9c763e668e2aebaa8a604e157a538843dcca2fc89de5c19402adbd3d5cab2b5df69f8fc94186405fb41dc7e6da60e78126f20ad940fd94c39ad4580aafe7b132aca879b245a31e9010001	\\xdd42001dae16b185fc7f82162e71f9de4388a9df7c444392c2590b425ebb44459d83db0a60e2a7a5bfd2db995361a75a640d3be82f898126495560013fc21908	1689872261000000	1690477061000000	1753549061000000	1848157061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
223	\\x07de0faa8dde02433b7a7d49cdad2bfb8e4be74a119566d6b8f9f2eb34f70db9ac501014fc2ea33588dc9e2f4758b849afdde6e4a0f07dc4fda1c024e20d9b70	1	0	\\x000000010000000000800003cf8cd3e3926be7d0d4b9561ad313b24a77fe9ac8c4286af473373adbec7f040b17f9f1a84d79ff4a7caf724a90380f5086c0462e7b80613a704a1127293e657ac54b4a16878004c94d276e90f477a3b6325292284cc7e5ad2f9269fd159475e4f223825d826c3779f95c9b73c533ebbbc9b132861f496d509bcd7885cba9cf09010001	\\x8c161bd76ca6d1809a74d6bb1fdf5d6197a9ddfb40bc317bdaaaa0a761262f690b1670f49ded59c5ddd22aa24c0a861f63a66570ceb5af11b93a68891e210e01	1675364261000000	1675969061000000	1739041061000000	1833649061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
224	\\x082e4994d004d8cba6ccaed3ae91d3de884c9082f29017e11eb6e7404635d3264d8475087c7ee417c6a5a6e6cfe763d55831f6b8a91f1bd6fd081b00b7b60e76	1	0	\\x000000010000000000800003ed12ea337a2939996c84e05e3485147bf1e496c6d04dd2eb81829581f5c028dac115557e890cc956484ab0a54c18648b35e86d6c944572110778e0657ea8358240a1d75f41e0513bbd0290bc567a7dc5c94a1e995bee0078f37655153fe8ffed247f08577b3738d84d15a4e9d4610a70a3a82b9077356031f801e816cf09c023010001	\\xb709419f8d82b48ab71dcad50563d8d9c13bf4af6f9a11a59194159f39c7167fc546c64abe45e1cd57bedaba9f5d89ab370cd47bcda8317067795d796e8bd607	1675968761000000	1676573561000000	1739645561000000	1834253561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x082a9bec2058fbb773cd63bac09e302b63771b2c2b5f5245b7992b696d876998ff16d9c8f1e02150c63dfcb191ae468250ca1c7d4056e755fc4b140a323100ea	1	0	\\x000000010000000000800003cb48256f3754ca4f601e7a099b01c212793b8037ace819d1df813a448630410e2649471eae6492e188df654f2943f40f8736df63efab4735557e39c6bc82214f3f32b971756ae2ac7cc44acd1410822e6c76234b71746c8f3e569b8d29747be5c20c4f8ca9af4a83d9e53d652ef4772b4692e3bb5dc790ea0303ca70158dbe07010001	\\x34c6287d9c0882ae6faf612ec542a27ac963749eac635fbf7add560ccf33f5478b66d1b01d27e04e2db2e67f838505b66486eb035d65d5afe8c0f65123b64106	1674759761000000	1675364561000000	1738436561000000	1833044561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
226	\\x0ac68d28ad72e8aecb172f90aff9f6ae46266c75a1bf72a9cd2288bfd826992f1b69add5f3332ff817bdf82177267ffaeb2b06a274c61bd2a832d9460827f03d	1	0	\\x000000010000000000800003a2160b23c996a699cf1dbd4cc7bbe0ceec64c34b782f287c90260ebcc0b75c37210b19b53917257c0e264005277f3ad405c8c51369be58c6288fd730a103447e1cb484968e257674ea76f83c146b3e11428921fbc2453b601f1030caaf149b90d71c97d09b6270c5c428f51f9f7f9f3179ee5fe44d4b5df72e1283ceb6397fb3010001	\\x154746aaa856d5c812789d968c78af30ad8d49dcba2a9f767065608d560bec5a2fa0003ab6e597a356208f8910ace5d00d229c7b03ea84259a1149d0378d0001	1671132761000000	1671737561000000	1734809561000000	1829417561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x0b9a10c47878a19525d5d1732542357cafba08946a659196898ed1e96c9bb215e389621637649f150872158cfe52afb1a0c47f0f6d2b05f087e3c780595cd5e5	1	0	\\x000000010000000000800003caa7a5ea28010bc9f5578004c83c61b1a635d13b0541340883f81faafec0e6e53ea7bbdc5f34bd1252bba3b7e19b4f52bfce802a13268318f741f7e4fb58f716af7d359bab9cc2f3c2953999ccc0432a9f5b22bc6615cae153a0eb149970db8c15298463597ea680518fba17330f51fe523950522bcf95967b753ecfb8eac489010001	\\x704ce7288a541f7d7e2925ed99ff9bc83af44d6ce4c0ff5de7cf42923cbe2fc6a5406645fe3d834002e9a309e3b80c1a8d23a70ab612d01bb129a1e247cae90f	1671132761000000	1671737561000000	1734809561000000	1829417561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
228	\\x0c72105da703f1b1a6f4eb8630cdda728d61ffcf2db31ace1f86a94ee3f494e18407638978a685cda13d36a414614a87ab1dc4550a5370261bbc942ab58eb157	1	0	\\x000000010000000000800003dd001a47902798c0383892f47d76a4ffd06bb7f6af11824435a8831002cf5bf0c34f8f6619f7cad7c940fcaedc363ed0b9de33a3fd54db2d49ff82f42ed34d13ac7f5f5904e77bbc1a53ddc0e789a8ba58513563186f452b957739ecac8301d7f9ad104546f872b8e528b7754b15b0e46ba95567fdaf74c49ad24e6dfe9ec2b1010001	\\x074d4e4159c4b6e0b4c741992a6deda59836cddb70d14e7e72d6da8a4b0a4285d0cc4fc9220f9068c4c0aeab7367c6f27e2eef176e6f40cb6da4d41d2e73f800	1684431761000000	1685036561000000	1748108561000000	1842716561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x0eda61369ef60c48877ab195c4d91e73b9a220a2d676ff09ef66069f43810f722a2b2b77e737ea649550718d10dec805d74485b41026fb4e59c2649f211a27c6	1	0	\\x000000010000000000800003cb705acb3c8d439c705e6b17e85bc906f94ebf420af2e979bf45f1221ed118554a7b272d88d805713cffa08a77e0c9acd48b0188a942d78bdc5ac3752d0b1c0dd98ef19cc5a9b85d7a8588e8f93b4d7465de8a3f71eb0b158a5a78eedbf44380b1bec9dbe773c93b4be47f246bdbba14d8d1f951be8c9a7b426b2893889ebee3010001	\\x9ef8866fc1b05701e66c77405d3e8ee84651164f1c71d50caaa6835eb18abd73f51f8a43f7e66c8b3d4cf2a63d12dbed3dc9e62c32ea6306acb23ec3e0e26001	1686245261000000	1686850061000000	1749922061000000	1844530061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x0fc6cc047b8c8234770ce16e7570d663998e80d2e46f9f376bc6e9f25db55efbcad85f9f4fd6144100e8a5dfd9dcdab23c8c6f4cfc1368ca32acc336fc7ee41a	1	0	\\x000000010000000000800003d0a3f664671f78a738fe288096a32279d21b0aaf55d2612d4ca4e407228c48a92919e4004b5d09ce32b5ceca597319028a8506054c78e9a724f61b43ee4f2da643dca7b8ada77ed9ef3807d7d66296e42f176830e8ea799032de40b4079667ec128188c2be697b38d91ad7a3cc0f224bacb7eec312ad55a2d6950b4f3e808f11010001	\\x6e6e4c58fc7e2661b8f7f33e766357cf6b725391c0969137ecf805cb697d8b45829869371cb287953d83b6d6a255662cdfd07f43944ddeb205bab4789378bf0d	1669319261000000	1669924061000000	1732996061000000	1827604061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
231	\\x109e8e4e1584a90d9f5db375d7291813d070187a6272b9e5c5d97c6f35df5521dbdad48e1e40b8c65fe9500b07b3e1e50ab429a429b850f3989d9fb57d1e0c29	1	0	\\x000000010000000000800003ba2dc7ed74053d22e108e976c0bdd2c36eefe430b4098fbe9e927dddfb541b0da3003f407ef91aaffb726f0e48b4511343f778ba0e3340eb51ddf890a94a66177f2b003cf827af07d838fd158a81a32b3cd5617948b71bf254911790d619723ece0c36e803e7253b6692429449ed120b1624a2e292f5a254b5ec4bda559043f5010001	\\x138aa3ed9bc3707f01218634f8ac5ade7350225d037c8049486d52873d1ebc441b2d9dc5f24eacc70a235dc464eb906180a449b07cad992f0bcdb3e87ad4820a	1688663261000000	1689268061000000	1752340061000000	1846948061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x134e041819d5637fc900030bcb542787e3c8cae581b9e26e78207327cd4ae08901d65025082d77351bc5afaec0d106d300e976d4e73de9038af946c66de7f7b0	1	0	\\x000000010000000000800003ca9c11b4ef0f8fefca25af19ed48599c450986712650ffd2e7eb2b382ab3058e22b74cd0b5c6194a2c0162eabbde1b04e0b3f95b7a0cce02da2927fdb4a5428fffab56bda93e576cc2fdbe0403cf54b428ebd1892d49703b5365af1b62630a6ecbf366c00fcb0d18eb3933474fe57f848a46b29d2b503136785dee7c58f1f833010001	\\xb51c73f8f9994427fc5c5498560228fe06c6dc9e401a7e8b8b2dd1c70b90aabe0f11bee1bbc6a414151be5615cd15c97c176c66931413c7e4eb60ebccf24ef0c	1661460761000000	1662065561000000	1725137561000000	1819745561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x1706250bfb2ff95441438b325e2012e5b4f63306cbe69d60f23f23a1c48893e8cb83d5767bed9ed1e81441e983b6ba1c4f5475255b70e2369b7681776d22f8e5	1	0	\\x000000010000000000800003c22d96beb20a11b5a9aeed50e1d08a91ebc78620db223e803b1c18367e36fcf7d12236f3b4a26d4084017f3fde99cf0e603a730ed8d0885c1febf7aad7d8bcbc3840b0af447391c3c28eb757c2fdee1520226c4dfb0d25e3efb0f83121bd5cf637b336561a3fda845cf6e7f33e5e7a2e9d87e4b5097689b0f4558a584145f9dd010001	\\x2e685944c621cf49c8ffe8b5d9d925037ab88589e7bd8d00cbeac35f5b217931888bde34cec235847af37e8cabc8419d2c4a749cb99aa130f279163e3478110b	1677782261000000	1678387061000000	1741459061000000	1836067061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
234	\\x18067231c3fdbf4cf4f11b208db5b8dd47fdaca7983b6a516c5476ff7601513953b792e5272dd994ffa260bb3411f921f8f7b3904fb4cb354248da79317ac7f6	1	0	\\x000000010000000000800003c2a7aa3a1563dd340712f1533eac2246f52a09c057264f567b14ed7b6da9b5a3b203bf564d060d1bf16a0f1c6226a381597f0696f64c503e1943e21a09adf7086d13bfb6235606876a4973335b6a9b4ef343acde1f596595ee7e0b558f05f829be1b16474e8e59e48d8ebc4af43ec1f6e3480a1ed0bdae16576248e65a6e6a35010001	\\x8d606bf3ac92c8987b76acd020c8bd0e0b83cb2225d7f8154bce2e9a9a142bb682948cd53364ad33659514d3ec8ae5edcce67f7e00472d3c24df201af648630e	1669923761000000	1670528561000000	1733600561000000	1828208561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
235	\\x1d0e0508be9dda05bf9fa19df67c0a13eb3b162d452796816eb35b8f24e825d930ffa8b380f7a613a8252de7dd01e8ba0c88cece8fdcb23c2590f5b91be48015	1	0	\\x000000010000000000800003bfcee2647ba7b0e88eec1e0d62835635e49fee56ad526e04d3690bc801dbc05fc8ce205d1d6e21ccccd9ba53e873594673d716bebb3dc3e0406ec6dddc010af984db7b530a362ea8c42c4ddfa8c394226e0aca1abec52b60888438fb5a87b755e463e93e3867eefacd432c0f731faaa4e671c48f27227c5bdf087ac313a5b7c1010001	\\x97ead8fd93b5d49157cd849572f6f07941d6ee8b7132de5b9235a39d0af6a3794bedc9f96174f85f52930b79f24ef7be621dcbb31c50e9b3acda56b0d6c46205	1669319261000000	1669924061000000	1732996061000000	1827604061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x1d121c71d515ee83867b6742be4c96995f12e178c268991021b1c1e01aea969463f590fd67d7479b2def55f344ac3c8d7f5d4f5bb434e5b99c64175e4ff5f41d	1	0	\\x000000010000000000800003f164833453b1ba525f7b98420e5e73ff8c849c117195a7e298c87f1229d763c2f255ff952cd16bb9b401234fcef1cbf601fe6be250dc801292020f01483b55ee21d3a25e969a4abe0506e8ab8a1ff55c6acbee929dc222d22639d475431ba5f609d72d7bfd4d74a98539ceccc9953ac46ff5591f5f4e6456ca6683d6673bdbf1010001	\\x64890f639b17c9b50fa61007100ea2acbf3387b4217d068415c822604052aae4ddb2e3c182710b113ad7de6ffb174466610a7805eb494e1ff92b56a6f64c4c00	1674759761000000	1675364561000000	1738436561000000	1833044561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
237	\\x21aa75fae3eab421da12b49765ab3f6d0394b8a41f005b578a2020300a5a1977f440792eed29221622d0cdc95bbfdb4d94bc096d56710f10bc2e73d78b4ff334	1	0	\\x000000010000000000800003a93c51e17e99d4eb07d9649c567ba1bf9b589ec4c9f1aeb4ddf3ae5cd3c5df8b4a5e621005c844440990bc48e693150995632d7c0c7e3e358294b10ddbdc261ce3b677569351b05b5bfe3de4660e92fa7a36d23538036ddaf954352260581c0561deb54fd01ccd057d9765ba11121a479e259867b3726609140757c1cee7b037010001	\\x02c789e819d4f3183fe16ff44cb98bd8930a6f366287a328ec9cb7418b814aa5880bd789d19a4d11d33d2ad90ed87318e8faa5b0d74e34fc39682a50a9fc5c03	1679595761000000	1680200561000000	1743272561000000	1837880561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
238	\\x226a8723e8bad65021ce43aea0566e84e0a4e3e09b71212a92e7727322c131d56aba20db4db317f11a0fa0dd387dd7f24f875cecda29800ef9e20fa34ca6a69b	1	0	\\x000000010000000000800003ee77764cdc0e16eb2a5f15fda0ff7364e9a76d89446485832a5ac12f309227b0a75fc08bbdb72c631714881b5d4213a96a3733046c83ce9102c0dff1e4981887dba99b19835306c27cf2c78aa8673f8192101626fc953d8950b1d8a7cee17df453d2952c74ace67801587b4a7e7729d7f44bae5004adf404ab84f9b0d001ae89010001	\\x5bc889d953a794cf94599915c279fec40def8f53e37b5e6be73e4f4122ee6248625e4e6d2dd4bd786db1bf79de96b64450630a1f68a458d4485ee62db57d1100	1672946261000000	1673551061000000	1736623061000000	1831231061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x25de9c2c1c460c93bdfc3303a5d7a89e5c07340803c66fb1abd77b101cc9fdc3dea5a1eb722f1b5fa3d382d4b74ce6a8d7585c690cd9f991fa426da15dd4842e	1	0	\\x000000010000000000800003cc2a0fc98f7e4505ff9afc9f0df6fd39e94ff01bdb9ec64a0f81bd2fe4f9a6c13a28a16f4a172614725b29053e31ee9826c22a51a8e21ff03e68650ad38df6445b520c7d5f71c6377167d2733db871427e1a73d0d86f41f69df43725bcd2a4ca0a7b5a604db3a025411735537470dbcbfc8ae6b08ebf1b0ad64493d83e80e45d010001	\\xb499d97ca816fbb65d32f7afbf6a1386e87283dc57e424c988fc638009b110980dee7d4865e88904b2ceb20496b9e06ce685a9c2ab636693eb210f378980a900	1675968761000000	1676573561000000	1739645561000000	1834253561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x2a169cfe0eeb30987cfe01d0466a5150d4a851d083f09708be4c002ee92e9f9313f9d4c962ffc3f19ef04018e261cfec62c029086212f04826b80145b540e81f	1	0	\\x0000000100000000008000039e389aaaa5774c0b1bfbe8b6b53f88eb9a8155afcd98454cffd07161a3ab5a1a8a1fb08d9d7ad10b973223de6fd5a47f33aa7fdd74d09531ed0a7c3f3e94bbfbc636317900aa43ed1b16ed6fbeb5fe6dd9a99b9e636de48758f0ab98d2d06241ebd40b4b6210eadc98900f3883e0361d6a1eb42acaef3667c9ab39bf8392de75010001	\\x022aeb7b913bc6851b8d047f4ab408efde20e82b57c8365d5dec3b1de5790d891078fccbc1d8cb557676c7183275a8128ce44aa30e6d8a34d2aaa32c4a920c08	1660251761000000	1660856561000000	1723928561000000	1818536561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x2c164f1acfc00b876b0af4635bed8ab64a6e572e161f4500ee6e1245dd6e1292719f4434d4aa25dc1825da334d2b094ac74774b53886bbbdc40c7ca6b081a572	1	0	\\x000000010000000000800003ae85d7be8fdf8e3931c27f14a9e89b1820d0bc9927e72c807b89c58a99a719ae1d30f3c833b8ff8bd72d6036fcf3164e203af5b91a030701904ed82e0b5c5817eda9eb36570511c1169e0d6af84e7be88b47cfce8294812843b97a610916f6b52f8f1dfe29bad05fd89a1aa313a996ae7049c30493a7e95b462f33082a5049a1010001	\\x737c60e2c5992151c1a198ac3eeb219f85233bb8b6af55f4c57e8a431394d967ba637ec68511640c3405cf628889c77df4f479168d497cbcb0f90ee4b5229c01	1665087761000000	1665692561000000	1728764561000000	1823372561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x2d069f05a5d5bd3417d2f3631a88be6789dc1e253bb6182577b52e1d96cc1857c5ae0693778112b6b3951c06256ede79538fce5e33f79379721396a12562dba4	1	0	\\x000000010000000000800003b513580110f90f5d0278ecb27855e1bd6bef3d8c9c7ac79a1af184803bfcc4f5ab96ccc1006eff3c9a83f8fd4e711ab9083909cf13acd7246b10598c0629bf7b9037b9ca6e94404b9c7a352a575df241fbf7a0beac5d6264155b75927656c8467a88d719b05f1725c7df2ea81441548d65be899b1e8b87817402a7ccce2b7b25010001	\\x684e98bf6802ebfc229fa2b10be348acb2f31ea13c165357250fc19e60454fa3dcf2505a0bd406dd1337d622672b10d59ca5fcb034105726a2108006cb73ff06	1673550761000000	1674155561000000	1737227561000000	1831835561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x303681c2aa4331fbf974d81ff4d54718a82ec348d0181581a509a43fbb864a95d92fb12c56c4f609fc3369e80cadbf79e161237943d1e6b40f1a19a52e6c0965	1	0	\\x000000010000000000800003c88ad21b9cac37e54d5b403c0e99a86f3c617cbef1414e71451fdf47fb68a6dce0a8e424104ea5c85b5977479c84fc07f6a3c7614b1fab97bd4ea7d22911196d1d6871d2f4643aca098664dda3e6004f82f3b3d92b04a73760760c500e6fb46b2cd2c6b8772fbf8b0a0801b0406ed03e9ad32c3e50c4710f0f38df9b2ad8cc87010001	\\x50cbf1d7f0737ac3e34e315390ac3d4c913c4438a5a8a444d2284f4bf7a035f5fd1e593c922cb8e9e2952456e0c37f2e7b9b8700ff91d659a670991460fdf809	1666296761000000	1666901561000000	1729973561000000	1824581561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x332a8d9139e4399b28e2f57d6ffc57f474c5d0ad59a7096bf1c3cd09c36eeffc51215e73e9f7e1ef5c6d669c059f9cfa86a0e3a1e32c36d9ea64c270d8f8aade	1	0	\\x000000010000000000800003d25071faaae181b489cf523adcfe964d9bd53f7cb1d89f5cc16e88e24b53a4160e34c2164f0d686bd9de83eb19a94ff4e619005559cf8f75a1cd539f540ebc5c65cf34e8fda8d6ab63e5a2d3a2698dc0598a25d1bf9a687f15ec3f44191258a7bfe5968ad05f07f1a59a0baeac8fad69464bb87c07c4516273e53f6560e26803010001	\\x016134d201f98bd9f1b83168f9c193845738d7a6367839fc9b140e452d530528caeeb0f3cbf815ecf9673341045e32bbf06ddd591f25cd1f150d6fd94235eb0d	1683827261000000	1684432061000000	1747504061000000	1842112061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
245	\\x34da2be1be8da2e59d6cd1e55a8931357d68247abb25ceff3e22f477383240d8b538f10311495e893825d5d5655271147f37528fb5afb035e24876b6256adfc1	1	0	\\x000000010000000000800003b41fff1a658d552a7cde02dd28ede25d5295bf9de796229aa4c4f2c28cba6e8351676d78234bd59691d283ddb025560b93f5765c396ac6adbff6e2806f7d8809f948b36822952838f6836439f2cacf5c14aba7e8505594284ccd83c3a7bf311f6711640c1e33a71f71fa058bb893827f48c7f7a81061677a20ef736c80af8083010001	\\x373e3c9bdad8dccf4935ba8c2255f0c60764ac2fd1acd17f05ba90c2fa0484bc6cde9163ed38a31f28ae0c555ff81a94f4eacfd7f83d1be2029c4a485a16950c	1663878761000000	1664483561000000	1727555561000000	1822163561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x36f27620a2430556f46ff1f0fb01127d1b87e373c38cf2079a601a07e8e592af800cc2352f57aded9624d3fea39c7dd21aa41507c465c2937d2f5ec7da249a63	1	0	\\x000000010000000000800003f7cf4164ce8c2423dc6da8ca135274b831bad912bb8e48c1a5de4d7bfc3aac957425c5e73beb479ddb5ecb3c1922dc0d55aafa873b347c56d73c93f537b471c5905a46442992a850982f70ec584fac545fc6e92a1940da18a57712ea055d85ed2ce8c452df9f33cd55e95db35a970c1a696635058ef677cf3426b4abd749ad09010001	\\x1d5f334ba120eae13a9d956b21d763c2e29aef21ec2691c1797f27334131301a6dc7fabf46def2d99b957e602933dae17bdc7f63b7609e0b685cf9cdc3a81e03	1691685761000000	1692290561000000	1755362561000000	1849970561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x3746d56db8dc9f4a1e759bcd8611f484795da9a1c82bcaa3b2ca2ffed447d3e02bf410db664d1160ee150bc1bcc62bdd469107391c5f5107d519d9f2db39c8cb	1	0	\\x000000010000000000800003dc3b6ac6c0cf379add6666bb585d511dc9cf6e3e597e63a35ba8049da2386e263fe7204ea409358761e0d2b3af78eb850a7bab45334482704d6bd80a2e724a6c435dbfc6cbb29933b44bc820ff57404fbdccf49f9ba5da26466dd8c72047528e3d139a038f0a01a43932ddf6cec8eed60b137d4410c83f814ea328fa378ccbcd010001	\\xd3dc704857d69f0d005d0dcdc16d3d8db4dac309945fa905afdb34a2256a34f3296db1fc60039ee2764d1dcbf43feb4ba0beca9b855de0ddff787e6717369c0f	1676573261000000	1677178061000000	1740250061000000	1834858061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
248	\\x379622f19898775d81ced7469c8698855ae286b98c95c9fffa8117d7f4f595d7c5f4b6ce5906db18f0156f02b4933b90158f24ef87cd672da7e77cda6495fa73	1	0	\\x000000010000000000800003be7c98b3bd3f2a9952a9ab5546f05b9967f1f95458ac5dd1594d5af20a862f57388935a563a42335b559e0b3eccc37a404454d35dca1425f9b9e43ae58f152f6387c726729562792ac48fa8d2d65114a06d1a1c0157f560b215b29d54ee3bc5dbefeff4acc730d99b298f9b24eb2ef31075389faebd1b13fb1a033c685a9ae2d010001	\\xea9271dd39bf65676d79eb8dd73501fe6736da1f898626f8153ded8c38ecbe810282556f2149354de887c93f44bf02a8851ba48a9627e0634d8a7ac63ea9f605	1663878761000000	1664483561000000	1727555561000000	1822163561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x3b4e462aa8c3d469c29a3fcf86c8feb6a806d6ac10560e72dbb146a90d0a87ae03b384ba89dfa8b0e2b3416478487529e98589ee43cee5fa5ce7b2ac7d973ac0	1	0	\\x000000010000000000800003a37eb08b0b0678edb82e0c691de95607b1512d1697d3e8394885d129428d4e8d2e0f0452983f70532686739cab9fa67ba8fffea8c00165915b9dae2fae576e11aacb14832717db53314d2561b82191989feecbbc97551edd809f39d2be0aa2f49b1a101116e1274b084971bbd15b6f85b105c4ff676f167f28d41cf343d7b11b010001	\\x275828755df8c2116b9dd2c7ddf8c04e0284861a23ff223bf2e570be526be3227578819ee1448ffc9cff743f2ec0ba78cd7f6b9efcf1676ae797852d766b9d0a	1682013761000000	1682618561000000	1745690561000000	1840298561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x3bda9d0eb703d3643344a87723b9331ee7a4a588c281ee7c57f1297eb74198b510a753b56fc4dc951c6f5b0d075015bb6efcb8d29892183feb202ea1920dcec7	1	0	\\x000000010000000000800003baf709d12d23d6ac15deb62f26f42a4d4082ce87c8367871294397ec13bdc3412b5836360f502c2060437b12db4b185ca7672e5f15ad32cfe8fd50686b7820c60aa7c3b86555737747d0c3b82c864277e87be85ec6ba2dfbae8aec6af9694e3a4d69acd7381207cd6867b4494588f0f10bd34dc9d1b082da34be6127a00266cb010001	\\xa8144d8c1be8c6fea35594e8d0ed70fe1f373970360bf644abfd7c4085281b9c949df955574f4ea6baa0001f6f93434c7dd0f48ee46ea7a55728deaf84d4f703	1660251761000000	1660856561000000	1723928561000000	1818536561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x3e16238c04f4d989d511b5b56def25f4625847e0ed3121f482ae4e16d9b980341fa68c3bf1ab5d997d248be57f849c263c0868f759d7dfaba6a0860d55351af3	1	0	\\x000000010000000000800003be9c47f938b3c1899c275d9ecd1b17dd206ab4ae2e5503ee2794944ccd18769388cedb3ee454e7d5a39a349fd1c326225f9dc1a042a1253557facdaabda7bac144e9c79d87a8fb638d1f1a89277c05ae7e7bc62d1baf3bfd1d72ced80a7f11b45a1e87a30f25128d33002036fafb35ff86076cb18fe18a2f524d2a275b06c901010001	\\x0a2647755a1ca44b414d11772747ba274781e93d1c5095c4815832cd7b92d5367654759a12cbe50c63de98687532b6ab2752fc04f54802ccbdfd1c2e0841f20d	1665692261000000	1666297061000000	1729369061000000	1823977061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x42928e45d0cc3dff0bf701541e716816328b8cc0dc633ba6eac74b859333bc591403877dad1336ac823e114c7b7d7deb0363f9d285a0873d088fd965868f14d1	1	0	\\x000000010000000000800003c023e463e3cd1716dab51c64992b543c7331bfc0ec075bdd3deb3075a614adac7016389eac5aacf15a6c678a9ecbb896fc21b14d38d9fd82247096a97330086e745cf24eb697017e1c4e665992bd57972973391738c624aefe099b3a8ca84b89087204832dc931679e80b8efcb5c949990412d712352c96b39dff531507bf2b5010001	\\x16fb4e9f6c9522dedef02a10510362e0161ea0611142f0aebef4e3b884e607832c16b8a48edafc0c8206e4d52c9e68e6f1afbb9bb40b89d56597ccd78ff9c106	1671737261000000	1672342061000000	1735414061000000	1830022061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x44d623d5da41d86d44d8ee382b2054d6c385d5fa9c7ab5e23e941054a4dd48bbd92b37dc938f83e262df2240e39a548f91db128acbba633271bab9954a278055	1	0	\\x000000010000000000800003d69134365671112f3ac03fa2e7a0ef724afcef6bf5cbf32674b359249e4a17cb8cbc653e2bd941f27f33c54bcc2f44528797af5a29948a1b94ef6e04b8ff154445704786d36cbe443eef2d5156a7549e0e565a6acb4610b7a0983e20a3d1b1cdf0f4b3a3a56e93d494239617485b9e8be83570eb405c7a0faf39ccd23c494a25010001	\\xdbc17a3b2a81317407d4cf7977bc9247b5e6e8efc8f9232f3bafbe29ea6591009d28232b5e3e474412071683427c1b64e14cd60c6482222f5cabf04d96ec8604	1660251761000000	1660856561000000	1723928561000000	1818536561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x445e1e6ec5cad70fabff2fe62be747759b811dc24bcad123b7fae87f7a00ce18eba7e6e9e19d166f98e117819683bf95be8ad0f5469c2e3382f1c13ca1dbf1cc	1	0	\\x000000010000000000800003b231dfa259905a23da8cdafa1fca5f4883ccb1ad02a282410b490d7499685def0bca7590cbfff6a5e467d33054a9eefa3af8350a429c72bdc334f05f6b5a23ac4d04b6ec3231b8b0f4faec6a947f2cc57fafff56ec568be3dd36c7616f805316b7e4651cd7f3de44b7d5377bddc9b4068dd78c10ac2273176f6e571b8c909191010001	\\x7f7b3256a27b2b89a087141b4af2cd47c0b8363fa6b8f510c1cad69540472ad1d90fb978768a2f021562fa1cfff3f5ee5ecafd8aed38a1280716c7f6f28bec0e	1688058761000000	1688663561000000	1751735561000000	1846343561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x4766393384659c95bbcd7cbc870487d954197bd924ac66362e8d9c34d7b8e42a3c6e7dee86f63cd5e577fd5a18a7a5866c5e36dfa4b81b1fcdb1508d0fbf0db6	1	0	\\x000000010000000000800003ae09f3ceb7b9b5ca53d62896feec431e42bb2bc9333eb63d56619c28d6c81a2e2d5b08895657ecb5c66a8a0dbb31f5d1b74c1a0f1b13a78cda58d194e25b936b1f10c4551e5cbea8cc395aeb8ce31c5c036fda86313dfe5279cd358c675bdbe949f863f03124cb4172cc95df4cadc82ad10d2923bfd74d6f7442618ec6398251010001	\\x965b92cfcf0b7925e9ea0b937b6dbcdaf90a7292ca94279f3afa4c4efcfc105dddbf64602f7427f3f0e56e2bf88e8303bb0dcf2f94d9846589871c981d4d900e	1680200261000000	1680805061000000	1743877061000000	1838485061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x4c0ee36c0006474b092147b5539d55da421ca7f1e1dbf144998543cf7476e005cacdd5c476f6dbb0fcb3a6ef6bc2761613573c38eacfa438cab782513a2fd2ed	1	0	\\x000000010000000000800003db893f0ca71128fbd79849703c5d77c2ebb509d1ee059f7d8285a782a44c757f90312115cbb205a7f67586802325f151248b17769e6f6a7999d1a3877e6d421c59fe78d05be5f2da31fda2ae6902e69010b1d950713c0318c9ebb731ca699e6583b3ab9857eb5727b8ffb20e3239aa2f5313916bc34d96583b46a6b62342eb93010001	\\xac21aa525ef0e662057cb355e74af42f4ece3d1d2da155fd8e0e3a1e699253d25ced69a0b38de6ff96a2be253238d62e132e716c49c7c056e959d64d4d16a701	1678386761000000	1678991561000000	1742063561000000	1836671561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x4d06c7b03845e7fd1ae8909539fa759d0f1e7319e74521521a43ae2fb66853edcb01a3fe3014c0c65c62a31b7cd411edf2431fb55f0db8f5d3ea87ff4701eaa3	1	0	\\x000000010000000000800003ae56986ee18f67f27c4c61e445a15e4e64c3804f0d525d582f1ef36ad1a32826873003a8ba677eac2f5628209f4e819328465add184aaaedc7167dade361d5c04f4ca5fd3dd694bbe4974ee2f31d6b27517f5dffa7f29337e467dd56ed5a337fe33f8936cd3cf4f982289327e3d8e33d4e9abbfd0532b192bc55bdb936bb5835010001	\\x34645723d78af40b4039a7892d9ad5330f598a589e88157a5feb3e8d31b47897cc1b53e243cc408828142a79b0916273b81f85c40cd537e0de8675dc691e2c0c	1664483261000000	1665088061000000	1728160061000000	1822768061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
258	\\x4e2e324c96fbe5ac1439ef5c7c92e4a618ee19098ce7efe5553a6eb75656ca599ff213d42df368df74010e72c54307bdb318a0ec4d577c726d0abf8a0333ab47	1	0	\\x000000010000000000800003d68cb83e8c8a8680fc0b97e0e7936e9c7428c94b9f1ff2dd45eaf4bef58cc791f6da29d5249815231ad9d0cc67c8d3760245b96765eef21c8cb27659197019956770284ad040cbf10754f3be8cec402ddad9af6f1fc6801017431918af265a1b35e68eb4b3c21d2065f29782f318b89cefe873f0690e36119a546d33ff1c302d010001	\\x415240ef62f9026ee7ee59dc3d176783bec162ba4a657b6be4fad66ba60b222120251d77e478c7ac688a5c538ac8a0fc6b7b372b14a9393d3e66dc8df3ae6e05	1686849761000000	1687454561000000	1750526561000000	1845134561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x4e3eaabb9ea49875f58052225f50d6685fb4bd5c544b8115f823ea0927b242b9776687c3aab4d7aa53c83f393af3d432ca10f1de86481f77108d6fd4695d8a13	1	0	\\x000000010000000000800003d875d205db72557574780cbc4aaa54cc2999438029c70c8eeef9bd925a55ed0ddaf3d0304ab349d24610a71460bc379b9f446370c3a9b7bddd3d59ae83279771f90212cf3b650f2b46ac2e4d32d13530d41ab5dcf2069eff4309bb2c1b231b1b309d96a5e084862ce65c08ebc0587db8f0d55ad93da82a21794618ae117ae02f010001	\\xfa5ff2c736736163cadc0aa8dafba3b865c6816d224f9972bf87ce75c7f9e172b4394a3a72e800f39baee73ea23e598875bb87e4f8e62870edd6b43d2c393007	1671132761000000	1671737561000000	1734809561000000	1829417561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x52fef378ca3bbf514b574ed4ef6d12e00ec0b0519c3165be516116b20e7261f7292ec8fa23f460224f00f0939b31bbf2f6415a170657d3f48be7f1fb7324e301	1	0	\\x000000010000000000800003a046bf9a38c2f79df79768970076aea68528e96d5eb88e7369cb17a26441363c75ea1cadeba1df0f0a10b86a5e668f058f0e19b56e5e6082df5e0a354cbc17363368dc226370ff4ed4ee50f797ebbe0995fc994de5e67e1c7e9597a3db479b6b92132acfb9c9a74d9c88dc377aec2d5e47143560a1d76b34c443850037b5b91b010001	\\xba4f1f3685ccaf2a9fb671b0d68cf3fa6915e44439dcfdb78ffc8ad37d0f8a17330345b0423ab3db6a2a7bcf5b875692f685de5509e68eceb73754a791c9c80d	1666296761000000	1666901561000000	1729973561000000	1824581561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
261	\\x5752729b04fba8952fad8633e3408d6219cbda90c851ba72beff3e8b838422b07803dca753d1a7f7809e3a880e791ebd08a89bfc940d3b8e65d60e21288b09ce	1	0	\\x000000010000000000800003d4d3087763b6797a210793f867211491c6bba59939f9bcbbbc91eec4bb606c62a86c615daa657f0f41637af951b6530f90e11ad6dfb8eb942222239e537823892d82e3d051bac7f25bee16373185b9dd96d1c0de1909805b2b0c1420da989d731293202a4e28634a9cded7921384679e0b6668ab59a4c432be7b6e469b4daf89010001	\\x4e8445a3fa6970dc5c476033f1e8366d77dfc1e6f515e59d4e8e8d8ed9b71db3b03c6eed37c931f1c74b14e17038d50f1ddd388c78174eb5f95e6314f6b5b308	1683222761000000	1683827561000000	1746899561000000	1841507561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x5a4e96c09706cbe22d0b152c046e5fad53c67005ac9723ce7f6c82c5be1f826b5f01b22cd790e49aefde18ed8ac5c2911a1cb0eaac39becf28a9405c95b5d3df	1	0	\\x000000010000000000800003bb581b8e5a6d880e807d4669483ba8ad358f94d55f340acd49bfba2180ba6a280289b3862ffe67693c38f42267730e40367c5ecaa035944228ca5c35d3ee659bcc4aa966ed73412b6907976f6969607c8a3a90dc978c7bad560b6f094cc26d4fc89b10dc882b259cdb1afdb2fb0a11c841a4aed0839d6d974ceea2becbeb3825010001	\\xb97fccf453a2dc0c6bebb1b76e34dcc20862dc6f3771450b1ad18c96a86400b90218ca47137277183820fb38d44ee4221873451953cbd0ebf930756201a4a10f	1690476761000000	1691081561000000	1754153561000000	1848761561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
263	\\x5a1655ca73d6d023e381dfc7b36b2823e47e0c6ab7efaaf137f70e47414f8e47df7d3110cac86172d7836c0b2b4509e843e5f67cb639060e9ed7ca88e5d67715	1	0	\\x000000010000000000800003bd799299106fc160b35f5c15f869430608693e43cdc5b79fb339af3556e2c57601bbdc36889ede762903231b6d419ab913d3ca26248531001d8eb2a8a080d00b01af736b713a15e748d73878e8197052cb6486f2310027c36369fecf1469e626f56c194d91e1fac43e2d39d1b352ff6d788727ad87bc68b0d0931f858ebf64fd010001	\\xf67911566efef9f94f8dfdaa96c15c2c6b9d66c6b91a1eb4a5477c472450fe5f2559e5f6a45434bd8f8ed55c4eeb6f667b3a4c9fc68852240e169b30df644400	1688058761000000	1688663561000000	1751735561000000	1846343561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
264	\\x5e662f3d0989bb0c5955cc93f74e72fe271d5a1eda6ee20593b625930774710ee6b2d5a789b391743216c58a0808833d246853248d0b8fab95c8404520369599	1	0	\\x000000010000000000800003ca7d0f9b2b4124b13b740c14771cf57198b9d1fc9e2d7d4beb46e79e2603d2ae5cfe94afb2368ba67808dbbe71b1efea14c24b54aacf6d57545a9a6bafa70def1119d4584cbd43a3f4955232bb7860e50f1f700fc157d797a4352741e6a796f07c0485de71000e5eff2a2d7bc74ad129f4b68293b95708ec338a0e08ca2c2513010001	\\xe4d89cd9860e8603702037c72d26dbac5f7c1c91e2c910d4b2e8e67a8966e229771bda0e5684abfcd7b26aad6b4fd40f4d175845f964e592640eaaafced60e05	1688058761000000	1688663561000000	1751735561000000	1846343561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x61bad410de25d381a699baf3cdd292cebcd70107fdfb2798508880f55ceed4540fb9540ee6492f63325bf367f5c8de30470e8bf68dadeadba711b89fe4b1ab3a	1	0	\\x000000010000000000800003aece481b83bd09aa14c66abd2ff24f508ecdddf7cd4456dace5bd652a7271d96ab9f93f9ef15497a9ada6ee5847b8206dff1bfb91401043a6d4eef9c896fe37e889989d7fa4a2df0772602798b8cdfa95af78314b8ecbe67727a959d89fa321d1d2c83af4aabf65aac5b8e43ac97aa3d2dfbea8df6256c7b036324ec01ad209f010001	\\x4bdef295ee7a95cf07620761c3fba2992578f880c5f88358b1210dd17af57c1b4d43dc16c545374a723f8da92b8e2e3ff0eb76aea3b9c8a94a50862083a68604	1689267761000000	1689872561000000	1752944561000000	1847552561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x61ee5e0b558b39dc29fca57253ba039d2a7ded8501f45177b85e77e433fe4a693f3df0f77bef2b3b322e503558c55dd691696d1ddeb47dea0c5e1f6f1179238c	1	0	\\x000000010000000000800003af0cd53beed1491d933d61df2d33f5b076030b61fe6e2aa2804b256f34188e77032ed1a17573ed0d52fed19315f8c42009bca99eccc1ab7757e6a8e80cefee0ac3b5bb302653bd65bbedbad35c9d09465141cd6f41e596415e550ae4036b1a3e2a0ff2508f829eb54cad56f6f3e73f43b9163bd4a4685533cba5052731a85d27010001	\\x2fca6db6e9c9ea4da622be035568f007ee8e4182f420000020d2b8b07af19aab3d3564bd186b5dd87f31586b2e9becdaf70a3c91960d704af0bab90e14e01009	1679595761000000	1680200561000000	1743272561000000	1837880561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
267	\\x642a3bbe4da155aa77d00768bc2d706138c28b8dff7b873ffb0d90d885a2bd56bfcaf68374061d7a1567e041a46fbcb39df61511e60259f4165d7e880f865a3e	1	0	\\x0000000100000000008000039c763c5dc6f25de81d9d5d3c089ac7951a580e88e9873bff4a2335057c1c6f551879e9341c231443cfa7bc8a101a6bc30cca4b84de13ed7ca2cef106e81a5179a015f2c4253c9a24fd0928fc42f5023794c9ae5f0284a38b62b14ae902d5ebfda2b79ddbacec7c3ee4c71a193b402bd98f062a51fb84151899a6ef0bc6ecb4a1010001	\\x506e333daa14438c329aa8a3d3f5e78c5420407a0caf84a812ab73138b756f6673a7fdd37277b17456d1f4bf8501519a21d2e8568f3a918d37be067baecb0500	1674759761000000	1675364561000000	1738436561000000	1833044561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x659e2113217fcdbe641d09dd21b174da0503038e5166914fb933268e3b872041a66d64c79aaa506f43d79c3634766fc055f05f618b890850db4c6bcd72af5e5c	1	0	\\x000000010000000000800003cd9573f9d4080e9dbce356b58d2be3247ad24ce420b6d159618e72ce042611ce8afcaec3b8ca6e04e298dc381e9b593cf234e0cd5962ba9f2fd8a5e9f512056ec39d3a35eb3be0b4b33938fbababe52fada51478651b337e5a3c9cafb923c0f11b7c2b0e3dbd1faf21c09a8a24d070d16ff492066d64632150eabcc39a3c09eb010001	\\x57558026cc2d6fafc74c4dcf3e0705e3a237d314fa3681706bbaf2c49c05c1649def883feaaf9c3356b7a2026a2e7c54bb0ce11aec241bcccfe4e5856138ff07	1661460761000000	1662065561000000	1725137561000000	1819745561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
269	\\x67964d8be644c81bd5661eac764d7e3a6d4b5f61a25c642a709c88afebf82299c84f210e3bfae69746b5b368b008f2cf384e2b8bf62079462011282dbce0d246	1	0	\\x000000010000000000800003d7a975c4ddf4cef5d2297e7c5f56a383be456bee7cd3dbdc465667f96cdd21447a94efb7189e8744e45b37919e767e058a54d6f090bd7c8a744d84ad0c3633bfb69f3d546324789cb54e18cd24b461602c20bbaee4e6a832c1dedee945e738710fb66e46e66e907013721aa9abe6085fce581e41cacbecc70644f34117fd39e5010001	\\xc7441dfba77574c3d8b6f6fff77605444a9780d28419699b69e0a2e8a02e8074a3f1a57440dd39026df638e48c95ae8da23ece8ea2cb5ba868837a0c11ba3d0f	1680200261000000	1680805061000000	1743877061000000	1838485061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x68d6b5975fa273ffb79bc7c7dd1803e2628f7a99abdd96a4b3e1c4f4c514ed5c8d48afc623161bd499c88036d627c396508913af44d54debf8249f693410bb3e	1	0	\\x000000010000000000800003a9ae5c2ac3f1f684118996376fc551f9661ba4b8c96ccc75679dee1bdf8a52b3f3ee58c85194c65286708401c1eea6e483f3f8ad12e03d72a2db69969b55da16d7399e8e82c84331bb5cf2ac5efd7f0fabab481dca627b81df3a6c79fd4dd3d83293cc9069cc254dacd0cfc815a9f67210849a16f61e72b945bf9a5fd1a36a11010001	\\xa2cf020ee2d92d99604789773352f2aa5ff08db9adfb81453f40d5944efda0de2f96debcc735275f8bf83e682cfb033f873d9f185ee6e8a7e84b746c0f48090d	1688058761000000	1688663561000000	1751735561000000	1846343561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x6a2a17697295369205232277bb180c9ffb39ba89bd246ae2e962dd25b28b57a60260cedaf4afbd2f6f0d815d84e85ad51ee78554ea9503ec024ce60da4d7640e	1	0	\\x0000000100000000008000039decf88f7dea47c54dadf744dccd7137d9b0d4cf15748c917f52e8890501867a2ad1eb70d3df275279e652d54c813db361494c905401ab5bb2b04df4406fc1a6e4de14d9aa0f2eda74f440a183122d09362e2d993869b87e0098d9fe0b34958f674b038dadd5b22ad543768355bff9ff76a43e455b990a2eb87355c0900d98c1010001	\\x568335c4f8a8e3ebdbf277e264a9875beb76fd5ea29f6d00ca3108c79187a13c33f08abc0a7b67c24a0265d36cfdade7c9629d30bc050188662cb6fa41deb70c	1667505761000000	1668110561000000	1731182561000000	1825790561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
272	\\x6baad82db7b4ec48c7a4532dbffdbd116612174b9d599bb0bce4181ad78efc14c1e5a76cd3cd2db0db5acb7e6de6f20e00c55b014eabf9e063ea71c75dc70314	1	0	\\x000000010000000000800003b5ecf7847da83b72a23154e3bc455d678a04fbca971e724d9e94294ebacd6aff312337417abc3b06e77fd66d5aaea78425aac3335ffac35f97dfe8a45be31ac6269555a336ca0c32493a0ad4aa8e805b31bbd090d520af3cf7b79e55a2c2a4cd4bfbb6aee9695487ae845ceceffdde67a3310b3c24351b7fd65d0b978fd023ad010001	\\xfaadf518fc7686902153628379e98e05c2ce068d8480fde67ea6f9f2b660a4ef46b235e7ef2d9ca4be6429c78c9dafe6e2b00192ca1d3c5046e0756fe748e60b	1678386761000000	1678991561000000	1742063561000000	1836671561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
273	\\x6c3a121a5d4f28dc797db8524d2fd3913e0e52f3e7371882c3369129e48331e64e256826d5c36bf0f8b0ec3b903845553f1cc4d6141aefce6930b48071980dc0	1	0	\\x000000010000000000800003c47f8b388180733953f5e32f43185161ca634dd07c604bc17359646d0d3280177f18b1f11559db33b7501d1ab58cec8499a025a1c334073ed9a80a7ba6790e1e92ea87cb9e1bb27e09c0d22c8b3e5a531ba7b7284a2d834c2b41645f6ad4045227377c03cac5151bc8a6ee69af2a1bff34ace6fe17dfcdd8e9224c5068cc174b010001	\\xdce725f9ef68d4ff6226b0e230109392bcc7e76f0c6ab158359d876b149f7f7fd06e27835abd4d3d156058b15e8b52ffb44968e59b46cb92232f0f9f5c7fea05	1666901261000000	1667506061000000	1730578061000000	1825186061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
274	\\x6e46eb25098906b18ae513d96e62a261dd51e1187c29b743bbdc68b25de281c1a061b71af16f4bdccbd7b90e80b82d3d1c2d0846d7150e76916e43012c998eb3	1	0	\\x0000000100000000008000039d94f77de5ffa2a6638ba17d89196cb39888cf1b816250bdc30ee1988f9d657e39df9f0d7644aab3b2c1ecb910210063d4bf36165b708667696b628b968a486472605d386a31cd1fd57e379589e2e3953897b86051b160e7dc536d2826b90a7cb69ceb4ef281c6e0ff4061df4ba6e29789a36918e8fa971abf7ad89a70a4eabd010001	\\x9fc87bf1bec3b27b111561e3f87cf3c38c6537a27aff2bf93c099b85ccff4c2d42f153efe170d26c1d0180c530440034dad655ced5c925e05adcaec4531f9a08	1669923761000000	1670528561000000	1733600561000000	1828208561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x71c2bbe82d5c326745cf99baf5c78f1ee3232d77afd0f3877911a95d9f9e0cac9c4fc935b70669ab134fbb7e0a96c56ee62e54bc7d2b7ff23ad4ee6c3c3353ca	1	0	\\x0000000100000000008000039bf85553c37b6a88433e5a7950fff80908dba8d7f47c73b95302851ea65dfbe42a395a5e68ab7b9966baf91975459ff9d42dbce53f2d15d9f06f02c3b2063e014e703c66d9414674da4fb1f6d6861c8f7d261f57fbfff908ee8f888ef2b263366271def24a3fe33e50d3cd07eae99eddcc24b3759f38eb700b3bfecfa8b429fd010001	\\x3a444bc4f1d136ce9ccfb6a022daa6f44cc6b3f43596b9c26944a3b11a588dd5dc203cec7a37bcf0b01d74b95eb34dcde0f873f65b0b4b344eccaaec88c67e0f	1662669761000000	1663274561000000	1726346561000000	1820954561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
276	\\x7226a5c9642e8ff83661ea5d6057a50e14758d6c6b93172721b1476b5e46987ee87f3c54117e7f346d9ac2de398bd6ef5333637d380c86697694184c3659eac8	1	0	\\x000000010000000000800003c51d414cf1c859cedeca5e7142ac029452ee4ded04ebc07c3b6bb3e94c9d442f71ed32cd92ae50120696a32e5572cfdf34ecf5251dbb01db35bdc73b1e4be54196eeb80ab1dad50a9288489e680e7319a38f4b24b37ef76c01f2c158e5b62f7e8c4897bbc5a2eb209fca469ff6a9596dea08f24f1d63c8bd2d1d77bc84ec7347010001	\\x094a2cd56a5e56769f8d2d76ab10a60670e4d3e3410288814cde20bae9121fceab6e3b7b08bbbeeda1898366c5d0500439eff9c71f438be4cfde1c5b5214c108	1663878761000000	1664483561000000	1727555561000000	1822163561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\x72aec71d8fbb72f7f7543648ab3f60330ab7a3954e75604c6990855007ad5898754c0ad80cfc0d73ecdeac363abc3e1ba64703e519e5189ea23b02c3abd23f1b	1	0	\\x000000010000000000800003c2c99616a2f43f77de66774ab8cc0066031fb636d36cb4dfc834a6c7d976b1f365ae5cfaac8af2a2b12e12e51e87db762eca5877be8cd21a1596a58cf6f94b6736bc9f17dbe56f9363d5295fe2c32abac6ebe273a66fabb4b3759b53b2ac4aa3752c67465f9190b2d2ce30c5948039483e1c455ec21966944249470f8962734f010001	\\xd0ff51ba124f29d0d0eb55e34c3ef44c5ee9b068bdfef50f081a712fced41904fe3c8233d977d0c4730cb9ac045b91dc48c521f020ef865cfb80d43f5f9bf802	1684431761000000	1685036561000000	1748108561000000	1842716561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\x736632fdeccc13429ddb0ff72d8009cae0498558de7b2b6d3f782c2e1ab1133250de1073d289d0e3c3407d4c7247c0171218bd4e18ae08f08f8df6577a7110c2	1	0	\\x000000010000000000800003ccf1234859aeac57e6331d1b0882e04b046b456806bb1d68f6a7a4146a25e29cb2a05e93ed7a64cc84c0224de69905c867debfd2018d2422679d904e8f3ba548649af287d177ed68ef117e8c68f6bba1a009cb65d650aa709bb66563248ab51875479a13928960b8a00baf535ae4ddbe3c9fcc40177b34d0770759032ba55001010001	\\x5ffc2474890b665fb9711b34c9c1ffc85340a02f525d4ff5084d6c7898345a4c57df9c0ccc33d91a7a1ad7332ce7101e051998db69eb23511821263e7836e309	1688663261000000	1689268061000000	1752340061000000	1846948061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
279	\\x74f6543e448c02bfe3877a9a257d3328cd01c6db2cf71926eda1df06f7388ed6ba28be72cabc58f0622bdfc8d06fa9555f76240b6fb9ae4e8f6c4d80015d7001	1	0	\\x000000010000000000800003cc500da47a12a4b7e17ae2d54904c39e5f85fcc89085d45df9b486a9514761875ff040514f6eaf22ac3196ebdfd30c297693ad70d0b70b11294b8ab2d6b8f8e199eb7ad8e9b604739c9f4711d28b9dde4c113e70551fcca8a160eeb12232c20e17b6375240861ad269f65651bb9460d947f532bcddfc2180977052160c1370b7010001	\\xf3d8ef735bcf8fb7b50b95ac83765cca854e1f6b39e53f2cc50933c4030c418028b57c82a1544d5fe77bf8eb693995e0f640544ea9aa1de274725f169a382d0b	1677782261000000	1678387061000000	1741459061000000	1836067061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x7faaa29811a3141388b893b402126d3fc0e00e13adbfe618e5594997d13770c837e11f7a0aa0b35b641d2dcf4441e878add71daf831c412651c7e03be9e59c8e	1	0	\\x000000010000000000800003cc1ff1146bbb5d8a04878f6eb35cc727ae6e21b5d7bca8f37ddb9bdbe54963353ee8bd061e9c9a99a587780390849897683ece62095f31151f9159e9111aa40dde4c77de8b3c4938d58a7a8fb345d3e4f4fb19d807961028c1e2f9cb5f5997cc89eac235a2e2f720253934315b4cdd12acdac995f690b3a3b54404da8a17eb0d010001	\\xd991eb17d7d3b4517be2f9df91104a0e5de72874fefeedc0e861a85d9af39128412a29d52f7a042ba1073dc3fcd91101a28eed8cfdd481321ab3572055caab09	1665692261000000	1666297061000000	1729369061000000	1823977061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x8376fa5eec2b6ab188873a4fa40966934737279eb742438a7c83f762ef8f5b31bd0761d1f851ead466f0f17048de0d42ca0eda0ab9491707fcd5e0d7d23f3662	1	0	\\x000000010000000000800003b6d149541132e5a8fa8b165886302d4f6f2637be72f8b83f19aab2b2b3c1c8a4642d255e7dc610170e3f1cfffba852f9932ea3ae0032851348aa194c4dd794da23add468db9ac25aea013fc95bf75b037e5c073c2515ea8d3840643023ed18c12dfddfad2c3c8a8a4167afcd25b1c54bcd77795bf4fb586455bdf27d6990b8f7010001	\\x6a72c22dae6907ec2bfb46d8fff821bbb3a6dc74394776cc8b9f161f4783105025d3aabd61341644bb1032dbb9ce3631b3695352065de0b18cc0a82d683e750e	1669319261000000	1669924061000000	1732996061000000	1827604061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
282	\\x84fe6e4be66b68fb86eff07216aede43e6a103f10dcb5025681325dcb5ba7cd819b5bfeb88c56ac1d90d03511c482d4ef44c2dba435d43d6e6dd3c40a7b643d4	1	0	\\x000000010000000000800003b42e1211e07e8c480005169c64a03daa1f6ca3625d559bacb1bdd36d6f3f1e7bde937e2a80219768ca660e9da1a4c310c38a95c15435fc3139e386d7f149f7d928e27da0c5999006a6d517676d6def2e59ed76c86324497e032a23a47f6c47c4d15e2c03d2a02707ef41555452f1f827fc8b1387d55379d3f3129d48ea3b4709010001	\\x9e015a565469d0b72d01b8048bc36822265056738eca8189c0fb8d4f15c5bdadcd2c03392eb3e8b3a23f9904d8a87996485d3f78ebeb7e221ac1d8a9dcb12604	1660856261000000	1661461061000000	1724533061000000	1819141061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x85ce9633681a1e025bade67fda681def75bb0391ee1fd6441df4571356782bca4f323ae72272e3394e0796edd930e86c245c4dc425eb45442a19209acc04901b	1	0	\\x000000010000000000800003b702d7c171daaaf6fdd6e6855a8c61721d632bcb6ef4aa9480956d9196be7c832e0d3748805e5a39c1e1d5b496053fd74bcbc88c4966bd0d2ab7f509d225183ae837dc22558e547dfee886443e24b82ebadcb77e36089bcbb2a2c04f8f1e471aeb3404f63a5f5e5195cb2760a40e474c6788bfff4a6d8d489888aa503ff7f8d7010001	\\xa6c0975eb8e3a754c58150c6d7bb01a1e5bd3ac062d4dd037043e3eb827b72b0475605df2755f4342cf2f4f67be93812805172e5b171731c1e78631c53aa1a08	1670528261000000	1671133061000000	1734205061000000	1828813061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\x877e2bb4e264536eb2114ade07fbfd960ba4a354625dc0aa994e9497399a4d3329fd0e1ab09c86184097076163bb764d93da507e5ecf23de4e068715d2b945c5	1	0	\\x000000010000000000800003cfcbc6d024c197011ab193032a8e1f91b5fd5a6c038c4a815eb830e73522107a2c42bcfa7efb5d732f8eabe1a328edb2fe1eed2b5af4bff98c894350af03fa2a1c71d54999ba3425735c19308c6db149eaedfef588811c1adda3fb37fa940ba5bbd5218e7e69eca949a61b9548c51f95a16699e716c84bb5e6abcefa1d77d0ff010001	\\xfd91c2df054ee915f7b478f786eb134954a395e845e718b3211e79acae2ae6eddbfbd6e6de4dc8ee492ce584322ee89e995a7ac4c087765eee31b42f10974e09	1680804761000000	1681409561000000	1744481561000000	1839089561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\x8882bd636b066230a5877fde343058320d7027f0bdfb0635bbcd76e211b121559fca4c9a2c6921940262c053ae7b71adfea31c7cf9c6d99735e8b83262505d73	1	0	\\x000000010000000000800003b61be9da3f44bc1beffc7795c68d7acebdce294b6ab0a2c0fd41c60b5391bff437e2dd9065b6e40ace2d15c7a610f4a92197b2221733bbaeaa3743332bc9a729a31ba12ba49512aaa33d5f37100274072a8d0bb17676c0d4e364a3718397c4ae9a1daa6ed086473adf6f9520bd11fabba288946107a35d95f77db45bc9b2b025010001	\\xb3a2533803d0d2cc17507732eebbca6783d65cf98ff2a773ab21c43f2cb53b5cd7b9a4c688ecdf6ec499f4186f00c32e693f3c8d95f3e242549c90ac5da2c70e	1683827261000000	1684432061000000	1747504061000000	1842112061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x89fa2b8ab0abba60a0c76baecffce3f91506dadb7d0df6ddbbb324719773008e712a2a260f29f590abb746b5859aeabd81a112a54213dbf0d6eac4d480257d7d	1	0	\\x000000010000000000800003a154227713c7a381bc614ccfd0a43bbeb2ccc7f233fd080a94c395019bf5c28a3b9423641a3ec877407585ebf0e8deb5998089aa8cf82326f33edb3952c8ed593bc6f24bebf2e426b02a6971386c7edf3404e9c5fbc4b281168db496bba74b2846a2c87b8040632817ca67140e47fcb83f18e061d51ee5c90afc1c3a03efe02b010001	\\xe4fa6e969e76a0077a5fc76d0929cfe020459ac7c7db23b24dc9cc6c4283ff59e661756d53bcd8c580c900f8271f1878492b9020ef1df7e8270ce058b553cf09	1691081261000000	1691686061000000	1754758061000000	1849366061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\x8a62544e127e9743d72857e54faec835caded45aa47e5f1b5e33d4a923f902354c706ff200ceff58020561d674e2fd947ac07e939fbb99da1f8e3689dc766a14	1	0	\\x000000010000000000800003e692eef2a1a6f0dba348e39ebe6270f7d9e9962e97d97099b4f1c648e9e803acd556171675561dcb89d6ac6a4b6a430fcfabac1699a6a51e8d80df2a2f4a8bb60d2c4271d8f77aa31a3cab2553de4493cd8e18263da3a113d9e9ad60dbcbf62d78d52c4b65dccd69d6a8c78eb07e0f0548a68e7160257090211517c9035893c5010001	\\x954353b1150238159082635d5c54a0d3ed81d16bd6120ca0bfc37cbcadba8bd77967679b87edc6a579dfda8b21ab30434d97e4723624f8252fb9ad8338d2f903	1666296761000000	1666901561000000	1729973561000000	1824581561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\x8e2265d342c4002f5c3d47cf6ea3a28584b0324ea33ef841dc0ab934d0de4e988e998aa626cfa52806842ca9ecc9000e1731d0eeb4d73f2db31db38230b697ac	1	0	\\x000000010000000000800003c20db6540ad104cc411bf0ed4e272b0212244b8fd8dd36bc9759cd8a64e345bf22926a1335dfd0c0e216e4f352b0c6af82380f4700f6fddc8153b2fcdd7746a5bdf9ff67f5d3fb484a72c15edeb88702f46d27810903871a83096a53c1667e3986dbccd599e9e2527c1196cd7eeb13ee90a94598a0de13809b655711b4d6323b010001	\\xbcb2fc16b150238fe6a4258b1ee6aad1ce3cf9c76eee3c6f46049750ac82e30f5c8e5f129c511d633995c4ebec89ecd26a4ccdd18063d70d313803eba54fa60c	1671737261000000	1672342061000000	1735414061000000	1830022061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\x8e3ecd979909a2bfb7cf96c47d41dbbc558b6973e5826a16636048d05f2a6b2806861c9c61587fe56c586f0ff7b1ac1f3e8f40d0cd488d7612dac24a33edc7e0	1	0	\\x000000010000000000800003d651f9680054b69bf05eadae58bee53452b9b7468b5710edf300ef8b341ac4e782cd0b034e9a849e0e4a3b7ffc7f4e17f8995bd8796769fa8c132c3d401982afa62ed2a63cf9c85ba54ae1f85a10aad8fbe661627aced40dd5da17c0d89482d6d8ce84aeccd102380e4975711ea8af8ee7f9b88d49290e7d39ecb7d9464c033f010001	\\x846f6f46358676113d290d4d6f87fc5e707ad501afc0b476464920e03ea3873dac601d5b4650ca0185cf5eb885edf3c00ce598d63254d95418d166a201df0609	1681409261000000	1682014061000000	1745086061000000	1839694061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
290	\\x8fa2d21f88d9f4f2a29613364da2fea2c46959a10e3845b422f14eb5d2cdfddda1208522f7ba689f8e4c4f69c4df191e743d8a73e3fce31f2ee1a88a9b39f19c	1	0	\\x000000010000000000800003cf25fdf6efad68202dd34e66a2421e4087764f726127c3e1a611b001334e748f6f45c5e149aa705c908efc0d25afab3f29f2e6a1e543e832794fab5bdaec256c4789f7a0f0f9b84684686f5d9b0c55992409dcddaf64cfaa267076b7fff58f4cbe3e9f113084cf4147df3cabb0338083c27cf5d5b0e5a454fac972df9bb85457010001	\\x6dd6373c01f21744fd77a3914068f3dadffa34a2379beb3083cbe6b32d4467a3bc7aec4dc10845d4fe9ae1759549361286dea8e2773a4a676829f630d05adf0b	1674155261000000	1674760061000000	1737832061000000	1832440061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\x90ba7573841d1b838c952fdf88a5d0a216e4b6dbfbe27b596ec33d0756218124bd73dfde1a2c71e152d53f3cb010471e0e49afede71334505f8011bea31e3263	1	0	\\x000000010000000000800003aa175270f619f1ec9c36278c5423f99786c5750b608aeb7bfa9772224894060f0191441accb45c7a1931d9da920440684b6803b9ecd6fdbef7f64b574fce49684a5d7cb9a57d01fa11eb09049e212377930387712b64b78ee70ecb6d41d95ea124c7e7caad9bc287c78d7e49f2329c196197c2100adae66a8fdaf9af3e1699a3010001	\\xe476fc47cf133b7facb771082223d073b8d29e02e5c9962b0247a1d0e2e54b458e401133f22564afe9d420124a0390389521621f0d711f223429050794095f02	1680200261000000	1680805061000000	1743877061000000	1838485061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\x921258b9a2f7cfb8cdc5ed8d64d5829b7dbbe4d75ea24cd955a82beeec58b190c4cd12bd413b5986a74454fb7d0b32ce4cec2abcd2f5f191f6277ebc3dcfbaee	1	0	\\x000000010000000000800003f06438ddb1ba1d2ef45d07aa12a402ac05b10c02668d1e9be61e61a7dbd4281696f027636bc5360f4ddaaecf067fe789b759932843bfa0eab98e99f582ca0da9b281a6d3c473ea6ba74dadb6680d9193db5c0c5fb1bc2e6fe297319fb40d371faa81a0b2388bcabf77dfb70a82b6c2a540046ffa1d8f3c4bd78f96a00f8d1679010001	\\x882e3e8dabfbd43e334cea7153ee5b2869b92377f955b741f5c6d9546d1a5dfeeceb6d7925692df3ba252cedd856626fa764f3777da10541ace90ae413defe02	1660251761000000	1660856561000000	1723928561000000	1818536561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
293	\\x9c36459cafe7a30c29b0d963e409198f1d179ec8a7c2eb5c53482ec9645960d621064af87789265eeecdabd30eb0cdf88ee3728d97358802af567df4f217520b	1	0	\\x000000010000000000800003c53a5c76dd1e2fcaa5c29770b0051c2c68ece9e5de3eb46f057f5807034eca0142ee0da71ae88e87947f871eac8ee1790d7643130321963416069f0a37b5fee559cc64e3a0483dbcb5265f88b4cf5dc60998e1e66b596ab0aaa1b6aa9fecd45393c9a75c7c5c9252d6127bb364c69f2b55ed7dda9dbc7b80a65e17e97bce92fd010001	\\x6e49b7fe12b832c8936c84bdde3fbbcc28b6a1061ee8f57f2bd1e25554cb649453f825ab256d4f6374311fd6278e7d63317fe84def2b50c26f0ee5fa8be41e04	1678386761000000	1678991561000000	1742063561000000	1836671561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
294	\\x9caa852a6827d61e82a63a5d327e12e527a7289e69d085f234333cc5d6706feaabaa2a688a5ffd091be571ad91135910e0dfce1cc9e716d3c2bbb057e60a59a9	1	0	\\x0000000100000000008000039f148c6a7c75e5852df9900414af3d7c3a22ab46b84a34a7d3ca6103bf2715d092a846386e81f6a6362f7af1242405ed041186e6bd51eb504c5ca799a8fc7c2ab9c46fc217f4e1269184925167c845d71958676029a9eaa3ad779c524b948ae0830960652739718e8d01eb3fbe9f3c5deb578d1f9a924d81f2650a2c82bdf513010001	\\xa4b9b1e1f8b8835b1474eef184be8556d126702be8dc48adbf1be2b6bd218fbcfa467c855ad31cdd453a72315a303f792f32119771dd184e3da00b371de94007	1680804761000000	1681409561000000	1744481561000000	1839089561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xb4760749242ba3bd53a7d8b6efc709502b07ad5944dac5419fb4ae1fbfe93f13b9a29860a8c6efd80fa156418d9a8db938e840dfa3c56b7426dde017a1e71d21	1	0	\\x000000010000000000800003aadae66de06d27473a31240895c364497e95d8ea3a54b7c51b92502d9cc022bc86bc486c4c4adc4ffa10f66bd7652b4c5bc2dfe9cfc55307cbee6a76f98ecfea9e26e28c0186d2ed801d5b0604b06b6600796e74072f1bf8d065634c563093cf221ddfcf26f8fea81144850b5ddc8f574672ae3cbb66353e151f25685cd2662d010001	\\xa2d35a294bf6763e33cffda2e019ad365504e9ddc0053a4c512a3c7aee48db38cf0d752153ea9b6d1e6ef9145c1751e7f4d276dc8571e73b3fb5354a1fbfde0f	1666901261000000	1667506061000000	1730578061000000	1825186061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xb4863a3235cad2f6b0db7194f0f126af517568243f7b4a693ae3d87e5e1b4b8202480027ff85f6c95d4484d63822405a9b9ad1314d2e8d44ab53f72f8955e712	1	0	\\x000000010000000000800003e7ff79f9d01f6e34f697176b8e1d6416a12f40a84abb3f198cf2e121b214a5a92207df7787033f29cf85be14613491020da3521ed5f8130a3e3cd79d47c6dba9ecab543a009b3c3f1c31f6a963bcd8c78c4b8378572b9889c5a92f458f01587461f097276e5ba05594c573a5c82f40662ab886f761f1d1333d01a836d8b22c4b010001	\\x85d4bbdf0a0574e4359000b766e77d0deb35e7d289340daa29fe768e026f3ebd42576507957f445b522cf00bdbdec94be7b5d751edb2977e627939072e162208	1686245261000000	1686850061000000	1749922061000000	1844530061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
297	\\xb6d6232051dead7dbd5dbee11bbc7587bb5300c8058422f72dec003830c88181c3332f17547f19903a65434b11125ac635922eb0f7a06896b519dcf6247404eb	1	0	\\x000000010000000000800003bff87b7c66743edc35b3d422be6d9e8bdb013fc535e311367e1be44b040bdfe97a386832409bb0bdb52534f8dc8bd4a696c920cd60bd50b6952c6b21d119da095ddec1eee7a4267dbeffbbca415e9823264f6a7d890a6ef7606176e55d6619b41d6cd31fa58c8d7c76af9521449bec9d69645c63ba2a21e18097bcdf9fbe4af7010001	\\x364643c8fbf5692a02a557a3d329ed0018fff1517d95b5765dca5cf723a0c264f37c39aee0e8aefaef203ca4444b5114067f92eabf476563a4c91b3a634ce30c	1670528261000000	1671133061000000	1734205061000000	1828813061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xb7d22a27e90330cd2c5ad35086e6cfb1ee2e330488c56f6089e56327d2aefd34f3709af93ce055d76517d17e343fec2a188238d255e253898004ab1189b6e473	1	0	\\x000000010000000000800003df4aa0192fb88215b251b5ac049304fdf821c0f39f74b98a933110a79f96e739ad46bb34a579b793ef5d412174ab75c8520a105a5bb16bed79ab47e60f9fbc4bfa44709c515a7623935723878d89c58865c44d264cc561008ae167cb250939bd8d60bdac07e8fde3d769cc179f74294163b38f35f5bf4b09826ef2dd881e5c8b010001	\\xa0d72a84f5a6f010159266ab01b48a7ed45e2254b2ff77ae501b059deed25ebe3d5a932057de05e50b9461a15759d1647b1de9e1db52d395d1332e052c6a4c02	1677177761000000	1677782561000000	1740854561000000	1835462561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xb75effded0e7adba2028c2e81bb7ed667c19207794de6f8877af3e6a8af98c037830b17c5d61975582bc863396781d2afbc252dd4af3256cffd87f87d18d2d16	1	0	\\x000000010000000000800003d4de63ff22ee8762bc38df62e43f06ec3a01a2689f6f63a9a24ec48058fa5c300233b65b44ed6d98f5cca08ed0ef5ba84b60faf6835e087e5e5d76eb487593d45ce40d9f5e7f1b9fc8a6248181aaf5d9d92e9f6344957131e1f25e606ec7ac460b1fecbd9e0b6d2c6842e39191a724d5e8012f9f9bc00315fba3e8044a6d402d010001	\\xdf8f08f83e4a55edf0a9c908004d8e70ef8aab33e37610c4c8964feaa7085426cebd6ba2d01660e580df51645a4175a161f4d8cf84b543d7bed26d6249adca00	1687454261000000	1688059061000000	1751131061000000	1845739061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
300	\\xbfa64c162e245aba3d2cb346afe6840b566701d2c4697da1e29c635a7175fbfd622207bf73bd262bb0821154e7c8ebbdaede8c68d06d460921796b21be378b1a	1	0	\\x000000010000000000800003a8d9d6c5cfad0be71293016421e77033e4a23aecc8b6a81686ffbc8739b77defd37a294c1909d1773240a33ea0ce48fa206e72014c6c6ffe9406983a0cb87efb0416932b937d458934744271c95ba14e5008fdd8016acf13e22b0f154a65c09cb533df31e11056cd489bfd21927c84093385d10673361eda58db999fb8c20267010001	\\x2c4d9a95cfb67c73434cb7f1bf9d8f1fb1d8064053738cdb11848a986302b7c3e6e44ae06d070644ce564e0774636255dfe655a7bcefa45a68631bb41a2f3d0a	1679595761000000	1680200561000000	1743272561000000	1837880561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
301	\\xc09e6826c4f46be47a83a1cd6e891294cec9edc763005440c8f3c552e58ce6a12bc22d56442514ad8a7c8ae8be25e196f8bcecca5c55b7b9b9ab90284e0d9299	1	0	\\x000000010000000000800003bb241d4c1cceb0c75d7ee7ee955c56cb9fb577de2e9666f7783b6a539f7683e5bcfdc5640ae7d1232c150dd2e9cbddb7a1315b7e5b5894733205a99e7cd0f6d34d0b6b47089ef5920f6ff79467f27d3911ddcddccd4a146f00d03f12eca330ae25a395892f88a5f6df63adf0b18f9c335ee335c076c7a2faf4b0e19d0b12bdcb010001	\\x746f8622dcfa3c05faa9cb607250a056ec36f03d77654c0a4003bbd8a70e50caf2bb133e8d709e961141f263d04a2cc1f0bf89a113cfe5747427f746b0490c06	1683827261000000	1684432061000000	1747504061000000	1842112061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xc1bebf9e774cf0e0df002a8de718526e7e87cb95fc5ab3ac2cbcaf928ba6bef1ba9c41723c226146f5dded00fba86384fe3ba17929ddca5ee3b187df1fb5c35b	1	0	\\x000000010000000000800003bacb90fd31e56bf10c1f09f13317036a54a9df32a4dc6bbd2ad238391e2fd835b3a69e1882cf45860cdbabba37c2c27eafdc0a5cb342581810bf268963c70a8ec113c720b7a20ad4b24fa1b3f2d5bde5915fbb3dc323f7836a2cf539427204508814d2dce8a0ede396aa5a4fd7592ccc172192541be5374866d6cff138db5685010001	\\x4e31a37b1b5fcf5d85b40e46954efc7d432035d742e46e3ba1374954d38a83061b7922236dbf61061a954b1561926fce888c816f79d16e08ef9d672da3bf0f04	1664483261000000	1665088061000000	1728160061000000	1822768061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xc33e14ddd024af4e46f32b147e2367b39aadc8af50307312d5358ed537bcc6ed58030b99742e863b8e5349772a818e2e9e9a7e0a197d2d792ac37a2eee9e288c	1	0	\\x000000010000000000800003b56eda3a163e8e294d868a47d06cca53ad74634de70ee4446ae93259c1d6c6d0ec9ac914648a7b960f07cf858141a45b52524b0de35aeb8b3081fb3c7d6e52baded8e71ddbe0b9b40c02fa7456ddc1e469189d819d23a16afe8e6fd8b99afd7d4b2f61ec07345e48ca933ccd1482c79b84b75dbc7cce80425cec3dd6bcd3cc97010001	\\xd9738964563ff90a799799228355754393b4a384d6dda9cbd3cd3931e34b9873cece64f710de87c68cb017889ac0afeefb5017ede083d27f7e9bcaa15088fb0a	1684431761000000	1685036561000000	1748108561000000	1842716561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
304	\\xc3ce4590875785bb925bb6b59adafc100f531ca343cef8bb5f9077fb6616057635b36c55a58bc4ccc35ca82e09ec76795c918499ec32e30430c26d65236cb1b3	1	0	\\x000000010000000000800003c68b476df3088281399dc089d3a10f667edb64ebba2f5cca043cf0e887f1f2872684eaf78a4744bd8c03653ba5f94980c234c16e88a237577868af06e7b7141dcb5e9623bcce167d21fb8e2b9e9330535ba22d9d48a099f1939a5f2e4cbc90da90f3606b5806b57392d6dd60e8bb9176ce86e7fa72d7736502ef37089024dd35010001	\\x81b3698b8df5a8b961b1e56bf4025f8fc437b3aa6e292fffed3d38e53ab4769a8c4659e5fe50b245e65e96410b7c8ef7d8a15ad256a900dff535caaf53d35007	1680200261000000	1680805061000000	1743877061000000	1838485061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xc646f3924357d5be6ccba66ed367ea648928b5807afcb0fa0886731716d098b3f852c519b8c568cef0f256de76702b74d7aedaa2660920654e11eee79c76d135	1	0	\\x000000010000000000800003c47661e82e37781312d0b8aa3da1cb58da4405d80280a791cd53d75e9e25c8b276313c35b837ad552d7bdb0bbe2509e20fb86d5493de632050f14950ef1e718b4b3fc766455dd13cb07dba6e463b2bd19ad5916a13db6f2fb325710288199b63d9434d6e5fe48746ee60864f82d2320324452472ce97879d4e44e7942089eb41010001	\\x506b1d597af6484cb452f9b1d37bec30a8a24e6587ff8fc8e784941247830b8a785bb480915781fcff6fd6958dc0b6c8bc43e1050984999938e4abf96e8ae301	1677782261000000	1678387061000000	1741459061000000	1836067061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
306	\\xc8f6eb452ca1ff7f49068083c2b1bb4daccc4f21431d8a493b4cf4143e829c544f940e63a1c144f508fa2b4eac4873c6107d2ee7e5a666702df82455aede3021	1	0	\\x000000010000000000800003dcad62581173432db54fe256ff04e63779a7c7b7f24976b646b1f3b25d264a6a1801e76d6c634f0b3c1b23b3e55e9d03f32b93e1038c955054f2ef9b52812419ecffee4d60a912cf3c0e60167019094249f58652c838611fa7508845116cb075a3782e5cb7d20cf50296ad1d57215ea63a5ca6f526a5620268de997f6de6c439010001	\\xa68752591e45538206f80273d4f2564cb46f3bafb60d94ddb3a935ac2795cc18bb4aebdddc84b82742863d6da31232cc4ea8565aeee793759317e8471a165306	1691685761000000	1692290561000000	1755362561000000	1849970561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\xcc2e40bf376bc0d2d425a52ce8e0b84b1280fc44ae42bf37c823f99e693e2cee3aaf7a13eda6febad561f1befa4b775395eab410029fd348b95d5bbe97fc799b	1	0	\\x000000010000000000800003b95bfafc68982292e17e80e07546ca82e28ec7e37954c9155b7455be2306361881a11656e9892797fcccaa2548a74a5475cb545451d10b9f8bcdeaa4bd7914df88b42b7af8ef3d377abacc6368684f784258da169e9241e71e6f03cbba2168112ca80f6aacfd71dec943f3d716ea7f8c91489b67ab3b27e52955549d35fe1795010001	\\x7cad5c6e3739f0057f01e89771a5333211ea4ef9db82319cb844c652c6e14d74495497f87e2d818c85311f8d431b43a018c7a50f3c70170df21f49bdb1879705	1684431761000000	1685036561000000	1748108561000000	1842716561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xce52353ca608b741ae43df8df2536d4aa9de78003c0712f80a63c11d8812dd3047e8f4f49ded6b38588deed830c5fa0677c65f98f9a72b2f0888054c7a7b2886	1	0	\\x000000010000000000800003d477e97db1723ed93704767f7750eb48abad9811c30353a60bb895694a6066daa4c68724efb279fa490df30491bd62898fefc3c3386846e2d7cbf94fca9edfb2c1c2b9e6cca8fa3934f7888a809bd18444577e0c07b11fd3a143f021b81fea284c663b3f728c88c90493a804dba11dae7b1e8b8e6d29c57d400a63400e73cbe5010001	\\x8035bb21d1c70ace0eaf6bc0911db56c514c9b4e0a84a350af87090d63025606711d7dba18388f4db0a8cd623db366611f847bcae01bd25ff4dfd6aa3a235907	1667505761000000	1668110561000000	1731182561000000	1825790561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xd1ea188a0888b62a307d9c7737a6807710053b120deca4d981e5438002fda6eb512633dabfc502eb8bee3a9784109ce2fa90a6716bd9a53d4964ccb95e2c96c9	1	0	\\x000000010000000000800003e7165134f2d20d7bd8d59fbb47a050fcbd39c036732cae582bd5a5c93b13d1d432f012d18de01bb660e562b408fbe935fa7471270d27cbab9e92df880e8372127604a7f242d4768255412a771ba59bac9c6441cabd3592d04edf84a41f0f08c413de3bb93c5204ea54ec080ee3048240b688a480ce8ba5c7614aa62ef0af485f010001	\\xd9a4bf8ca11802537415f49ee52377e9352f159df7d69f3c62ed8e7b2709fa1863ea5443d3d88ceb09f7cbac68d2111a7040c3e4e0c9e3fbdd2d1f259410bf0f	1686245261000000	1686850061000000	1749922061000000	1844530061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xd4760a8171ec3e7c1d09eb0eaac424aa1a6bbbc47a595ea5b5d212913dacb207273042e2d98e0b3ce06464a535260df99b24fb2d0c6466f32090f0220e0c1e59	1	0	\\x000000010000000000800003af0f2ae6b1f1044caf168f90685cf68f57296f577c926fbe8017618842a00ac5d9b22869f5a437a6cd39c5540b702ac6cfa52ef2cafed6f40bea8e8c9cff904037fe4ecaf45bc6521059c1eaeb5021c318048b6d8f323c1b3c081f1abcf9527761aaa513caa021e696a27c09b6e6bcab21c5758f91f5d3faa23afb15c5e2ef13010001	\\x00d67e41fd7281544a81daec9a1889d0919a335cd259300b85cf5c60c7c732720989f6d2b1b78bdc04d1483117bf89d9c4574021265936a1eb3280b58df07f02	1678386761000000	1678991561000000	1742063561000000	1836671561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xd7e6a4d2a136254948e44f2b7d150bfbb81ce36aa954013662576c90dc5dc7e74c0d1d893156fd6bd067171f684fd3fe3c3517a412374ac2acf5c06052aded5c	1	0	\\x000000010000000000800003c8f58d72b98cbef1a690dce2f1607dea4f12c5f5d2bef4b85cca8004781668fc7991b09a264537313c9f63d2af536fceed17b1b3543b958de1cd5d8aeca82c8871f8d3b16b0e6275953d7c77c2b97be2012bc4b9e1112478e82f0eddb51ade1fb08f4e3dfe263806c6f2f2c603a5bda5711a36d9540f9eebbc61dbf2ace9b9ab010001	\\xd7cd49aa2d87b6ff7590622805025e22ea41d3b38019aa2a8bc500506d6093f85599dee2f51d86811cfd3758cf677b3a0290ff56c731ccbd078b5ad838d6a704	1676573261000000	1677178061000000	1740250061000000	1834858061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xddb243767fb3f5117ddff98ca0550085987f0516e38002851ec31a8ecf631a2b0b5e1b764429b588f28cfa8645ee1b9a1a9c4f27eb3e5b8e35099de3976361f2	1	0	\\x000000010000000000800003bb2c9dd77c429684b60fde7746b47236771b8dc93081efa9df4825729783ea9924f491c7294e2efe06171e092918f3c91c086e3e86e81dbda6d6489969708a51ef06672295594a1f6c25383f8bd50d5b5cb949acc86cfa2da2338fb045e18348f5b8c04cbd4c0d1213d499cb740450232ef9f95354a6c8794eea28b848e1d793010001	\\xde190c433f1129ffcec619fde5352c97148b45e58e0b777bc87d9bfd0985efa01b160f7749f5dfcfb0d1409692063f960e97d9a1d2920e9f597a99797d60540d	1691081261000000	1691686061000000	1754758061000000	1849366061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xded293ed264f86dfc81c6b3502e1c7d65c8a6dea4011ca38d18d466981580f5f539f38c17c7946d01513148e0f4b4c09e0679e0b79e711a48ee248876dbfd37a	1	0	\\x000000010000000000800003bfeb31d4a379e59cfcace503c9d47ff9fe8187ccc72d9bd87923fd1195a89befda77a8e5f34554cb07b4f7d918983598383d97f3cc25d856061aec6635985a391e228005b958c1415074d2b316eadda6acf3d45f741ec6c347b75367b59c8dfcbfb7c40ffdacbf293007958f6084f272e095183461b4049bef90161d07efd07f010001	\\xb959877dde647d8d8d3989b6aa3c9faad919f58ac7c0c15769f5526b01ba253d6ba23166ce7e4ef3498e6d4fd6b93e6a96373103fd06c02f75fd9d475bb6ec02	1691081261000000	1691686061000000	1754758061000000	1849366061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xde8ade5d8c62404a36a960aa7754da03754d4e52fc9e29711ceb6b8bc10bea4eceafe13667208e8c5854aa9d390406b6b3f25418b0d0cbc5e06b0af262e8d038	1	0	\\x000000010000000000800003b2a17af4ecbb3a4931c5d619858290931c395b2f7672790085f04d8a362f8024a803e5726e141a049e7a391de9449df9b577e7c2e9d6dfae1167fdbfbdc6c0b21765caedf40e8411d4ea47406c3b45cc8532a0079b34704e01eccb34de5b0a2d85b4cdf73e7790af5f983f9e21f691544744dcae9eb6681ebb6e1e7c5221ae6f010001	\\xc0a0fba4fd9e3cd9ea1a5b5496c1da639d043431dbeac94b9efc3f0cbad1448ad0ea4fa47488874d0046a629eb423dec9e2904df9402b209404e1f7110644f02	1680200261000000	1680805061000000	1743877061000000	1838485061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
315	\\xde0e8e44d932f3f56e7590a26dcb2cc011a4b888dea347c6c14c1593e7652abe7a8e3df6ded5c87ce258d1f8ed349fe1bb0062576dcf01d6beecdf247f6cf6fa	1	0	\\x000000010000000000800003d947abe064d35030402b8a8942eb456754a72b67014429e13f5825a108cca9b43c34ba7bb22a9625b1b90978618bf9e38e7bd022d9fe33c266b53c31cdc2a676dcbe7e752900b0037a95a6fa4c809d6e443cc32d62dfe96fa42818b30723cc4cf7a663ac0e70b10adac463e42f20797f91b55d4c8695db325e4fa6f387abb5f9010001	\\xd93bb67d1490815b8a2a3ca7ddf4075239cc18537287fd6e0c8ac4a44f54417ce385774ddef36ee76a4b6ae8ba5fe4c08a0c819db7c86e9e9e27ec44fd673d0e	1668714761000000	1669319561000000	1732391561000000	1826999561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
316	\\xdfae5c7f3d4c39cbc43c496fc455125ce4361479660b4a242b5427483d773397ed42437a5b1fc13c322b4fdc37b1eb971433a81a165fc928fedfcf88de44a2c9	1	0	\\x0000000100000000008000039e1e1a4ae82b586d4d1adc02c727d62727dd496948520b4ab4f4e3c25416a968e96fa74f631a4ef6bd43d81b25984f7530b79e3d1a85d6a6ef614bdd57d7708c6afb596c5315d25e889b0fdd9b7406d5ee89124311f5d50d149bde03a363adf9759fb37e89bc978f19b654b1cb505640178590a75bdf0753ee7569c5cc78eda5010001	\\x0bc61a22aecf97d79ce3e99c6e470f1c14d56a3c6f2bfa10cd24af5df8b0d322c6ff2812cd07fc0e9e8101505ff54cc60230a0d3eb4a90099a1c1ba86b01cf01	1676573261000000	1677178061000000	1740250061000000	1834858061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
317	\\xe10232b77ca618b437a05b3675070d663509daf5ee664583796087022b0a006f8c2c3437255e01dc5675f245a17579d120213ae659cd0f0f07fff4b3c884f3bc	1	0	\\x000000010000000000800003ba74bbb74bfdec3b574d41f3e482c3526ff7f910b31e871c82e6c759abeaf112bd3660a0f91b319168cae830588ffa4f4ae550269b9db01f2091a56edf78293aa591f3fad5a565b9be08d789770d6785cf53582a092ba84fb8ddae35ece0f00978be26a840e5fd4c6a99ac3e14b7cfd214c7af5996f781f4afd12c70821b2089010001	\\x35eac16716fc7307bec6c4dd0eac812f19fbb11e6ce68aeddbbc622c7fa7804e876cd7870808e765e145938da8586582c675046e409a90ac9423dfeac0d5f905	1691685761000000	1692290561000000	1755362561000000	1849970561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\xe20ad3e98d4a36c569b456062697b11b834e13ab1c0db68e2b627ec461c9a2995a5cc7138238e54465caa10ca624bc54f2f9251d5d988eb5be7f08c2494e2084	1	0	\\x000000010000000000800003cfd7005f4ee7fde377da4c045035452607c6c5342e25ec887864cc1289fe16b7b003be4967dc75b5dbd6f7f170b42ace5347c30e1973205f575f78c38be98efd341e92fba426be19011bce50d9ff23867ca77fa058dc270014ee08e7b2a664576b86efd444f46b7af0a4e5efbc422fb658cb4b438273299194ddcae4c594c635010001	\\x14ac8aa67b451092f860069606b306db599c742978a609f43e0aa541ce76412e1500bd3929fa68ef7eb559cf5af7beb5eba060cdf24276326bfb2736d76b1402	1665087761000000	1665692561000000	1728764561000000	1823372561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\xeaaa45164e94ace535065910f810c1dfff7f7d28b6c77747c0d29d316afaa361bbcd2fc779b209a10754b34264e38222c5ba987762af89fd64013c8faca27e0f	1	0	\\x000000010000000000800003aab200583ed88b7900fb0bce35fd47e56b1420c79fdafa69bb2b65951222d1cf4b5d8532e835a71a1be7c27074a85b64abaeb65063ac6fefde9bbaca9d8c1ea00e9fed2ae414e63be9da96f5fa339fa6edb33c1666d786724a3eb7831aba18de94c47c7fe752cb2c5863b30a0f318b3610ec2f22d9c8a6666c9c1d033a102d1b010001	\\x963a605777f659faf189901cc6d9cf046a2de01e776a53bf85aca01aafa5adec821afe68e95ac415d85c6b98d154e5ef87b4c0f42fbc5ab6d0eb9a9c6f05f30c	1664483261000000	1665088061000000	1728160061000000	1822768061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xed96d511c4ab29364ec70a934c144a9077c8e07199d4b2dff7e416345e4c79aacae05ae2b2328905c51012cd3378a57d71661b9bbe897de023dc4f2b24a7fff0	1	0	\\x000000010000000000800003c91dd2f41b1b1e583b84d6b816e742e30ec42c6b423921b8c95b52653a3a10a420fcadb4aeaf2d851210d430b383790bce86e6927c3c8255ae9d3c7ca9c06192d94a1e08223cd181afd89b1bf8a8235efd288aa7d9136a06f1b5adffc6b2e063b7c2810cabafd2f5e7acc52648e9c96785e27da2ecd1958c655fbb4950c374a3010001	\\xf11e8fa6676fe65a45c7365e31227edd95a8c2b70ca3f3738bc1a38b1caf100753d69172883b649758d306327267265af61655492979038bee3102ce17c71502	1682013761000000	1682618561000000	1745690561000000	1840298561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\xee7a93b376816adf2b356b9f4a107f208e0428033caab9b573abb1079367e5721250dc425491301f7084dc34d850ff896fe6342e531d3ad9e95b46500e6339d6	1	0	\\x000000010000000000800003aff6a3c5db5fe863192bdfe3e438cb730b51412f49a1cc6ebdf57ab0298b2014e9c685762276f14ab5e0b27130aecf013c717636f70e60d4abd5b69900bef9e39b25b1298e3b1768e3be3b160b8219a368f00ffc4a6327e09f8ad3648302ad5297c55e7d746c4ec1809594df19648ab69acb3a57de5f2394a912660c4daa8a5f010001	\\xa8955fceab21976bfaf175f6283905630a19f9aa33c6b0826fa55d6012adfec4517ddfe0194bc64db37841dffafe97fb46bd2b6bf87296fc4eab39fe321bd003	1665087761000000	1665692561000000	1728764561000000	1823372561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xee0a535551ddfa571f85e97bb3a6799b9233171afe5f7a0f1bdebab29a1e7ab61683a489c4ab669d35074ce998047d37d7575c9bcfb019ed76ed7c918f8e8fe9	1	0	\\x000000010000000000800003f4efe263a3008827324984be8287c1d14dd37b29a732744d36bddde7c0348c8345a324468bab03241d9fa2684f38766f838a6d275b55e7b2340cc3302d4c37cc23f19dd1cc6b97e45fe82e7c77609f273409e5da94412f03d65d2cf1f2de4a66ba451a40cdbbf4ee95b6b21323caaf1537b29df075e973dc489dfaff1d0c2161010001	\\x623c8d149126aa1769df0875a4a9c7d53b03353ac7439e39f2fa4378299b39290575fdb56b8fd4e9821716901f80d2cd1f1ad9fb76f007f4711814665ee18f08	1662065261000000	1662670061000000	1725742061000000	1820350061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\xf0f683e6b1700c1b5a776a47ed4adea55a18e934061f15df6481f4e981b711f2460a25dc249a5da7460401091c24c2345954d6dff444a44dfbc90e49a47f3077	1	0	\\x000000010000000000800003ea1980ff9f6770f23cc32d847378ca39f2ff27d850cc8ebfd640d36fe91e4d410ce595ba58414826db0150c25f88438119c7c31cadf6ffe2d360904e0d0f4c92d0da97ac9d07373df687d24a9edce97513c33ef6d0b4da8f36a00216c2be106f715c046436c55eade7502f9a3d6c4c3dbcd2fd3b39833c79e542498f5ff6ca75010001	\\xebe47e4c099a854a07285775201a495b752c7f33f26f7e9f6df10fc0e22072e880f1273f063379158ba67629cf709aba88292a5c8691b0e2d02c8530eab8a60d	1675968761000000	1676573561000000	1739645561000000	1834253561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
324	\\xf1c62555d27d3988eb32b8e468caad44f882d4e8df65207224df1910633957d96f623feda025bd81790a9f4a6192e90bc2d6d0388a4ef169a9d2c09e9370d805	1	0	\\x000000010000000000800003c99e6523cef7eb6798eea9a5922c2a23af4346907dcae2cd12623b42e1ed730fc71ce3a141283f5583fb14477c126a251c595872921fec4487744004dc2e7004de05fbd4ad4d0ea99a00734aa7b46378b55c4d03f7844091bc26dec43b1ed2fd880e2df5379af331b4c5520c50a33f3cfd07e92e9573faeacac2c8336eda4979010001	\\x208f8ad19f9f3b7369f58dedce79216ebe30c71826a0e3f86dbc57d56df43d87203d139ff73fafc5b3af26e852f9330c9f171d17a444c2e39fe82b98c65dc20e	1671737261000000	1672342061000000	1735414061000000	1830022061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\xf2fade3c88bb31fb0aa816c3f3bdec645cbef041c6b7076bac31d4ecefc2c4656dd429fda37b277a609d6c0d01e8a1c06d782ce2822ae1ed57806f7bf8f3ef67	1	0	\\x000000010000000000800003ad915fe81f1752abfd80ef0c8d02186d9b52c338afad0620000948b670a31ca7997d16f6afd07152b164e8972cce810018a42029c2647dd45e6ab74871a740bc62e16dfcaa229563a50b1edd6e4d6070bb0cf78f5a5024e22f9035deded94728d8201553866afb321a469e11f8597ee17a8ca644e189d3155c3b67e85ccd33df010001	\\xcdec388e2a506a9ea3fd6faac66082e4cf2dae60b68eaee6fa4a4dd5ff64385aa8a1c49234e016eaeb23ac2648ec232041a213df87dc1397ab2ba9c7868d100d	1663274261000000	1663879061000000	1726951061000000	1821559061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\xf3ea3c1ec1646062aed1a77afd4a749b692a486881fecf3292f1296c345d888bfed16786867511b54d2a4a6637b579714578ec80e1bec1e09ac65b0e21113e18	1	0	\\x000000010000000000800003c607ea421f1d272dad3b5d1be053857cace68bc004b3dd22f35e5ec13127c2f1ef0cad6245955660739a9f9e34503a2092749578275ad25d7c7deec2cd1f7898b83cfe813a5eb2c9a4cd8cb90e85cd55aa2e3e459771f534a2d5850cfe1a0bd6d11984f1d44431605481a42a878214ca98553e98c40baae4f347b5099b46bf61010001	\\xd7003a65e628a5ceb5f785bfd804005085f4e8cd4fc5c9e7f6ba35e811778a56a80d80b8c2d683d7e4b7a44db68298bece8954a61cd62b452b4a71d61b959207	1661460761000000	1662065561000000	1725137561000000	1819745561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
327	\\xf77e97424460bbbef111118720f1d67beeb077bd2f2046482e89cfac4d50274adc2839a4c0198f269bdb37b17c59526240ca8c5d75d58f768b70b5e48335d580	1	0	\\x0000000100000000008000039c059dc33529767abe652a281ea40d19bfa6b5dd1757db23236d13ac9900fb2a48f50c71de5daab10e26f6814d7219f6b0df63188ccec5986283dea1573a47ba53fa84cb15c25df0dd5a5b4c8ef8b95f2d2b3d7244e6f598106ab265afe458099ba1af02e911dec033027fdee8c0c2a581f27c7dbb258d5661483075e64b3ec9010001	\\x042c19d17a82a2c3a1b75ea8a7b12f00789f75a83824fcb1681e38ff863bc80ef12d1e6c7378a620d78d0a423e5c5b2b821b5310a0a0b9011b93009ecf572c0b	1662669761000000	1663274561000000	1726346561000000	1820954561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
328	\\x006fc345d84b419d83631f9964b50ba24a9b31d8cf212503aa933d03281168e7b99dc74af26a24736388a37e6d8fad5ef6821b7ca55add35c23211a9546fb529	1	0	\\x000000010000000000800003f6f47ea7bc9c2537318016458c0679155df6ac43614d82484e221f806ca03a37064302652b71c59a4e8246fba2b3ce7f71a2f08a8ea573a6f3fa434c197c95b7384c09cc5bcc90913f60d105beda327c8b699ff035e2831e5564de08e1d0e41cc212ffd5e1abde5b313b89a2aa0bacc296bec2ebf3c4061f3259b7a822b10d69010001	\\x40170d05b80b8c9ecde440fb0af40798f53c342b9ae3d36e8c97f64e1331c72dd44d8fab18d44e2404c4f95d47bb0679330f4169d3093238115d6083f6659204	1668110261000000	1668715061000000	1731787061000000	1826395061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
329	\\x007fd0dca983083aad7c6237b3d6be2ddf81f0fb0ca716245223f9c5b3b197838174d1ca473c9ee4ea27328520a10b325d09f0b570647c5e6046266c6b29ee97	1	0	\\x000000010000000000800003b722d16bf6ab47614a7d3c2adba9f4997acd78310a9b66dfb42c211bce7eab8d860ef414c3b76af5e7e6983146cd40ba4b1c7d69e5344d051ac086ff49eb90b8f512fff7a941a2475f623324391e5d43577d147e02188b1330408d722ce8035c7a07982e6373ecbc7780b96a3df1f50c573e00e9c803bd816b2ac3d3c0e7197d010001	\\x2d551dc95bf8033490e4f2d507527447318cca5b26e5e563f1b288b665feb1535b255966a20cf5c72c78170aecdf3f078c94d587a06270abd7495dd4e928f001	1667505761000000	1668110561000000	1731182561000000	1825790561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x02cb66d95cf47760c2f380ef38aba0244ac2ddc3d8e6f90155756963719a9ef0da7dc2d4a568e5f2b293852c6b4adfb0de24a64950566a6bdfa17a2d647bad9f	1	0	\\x000000010000000000800003a1eccbee8dd965f357189ba02ebcf441e776a86527664e2eb071178e55ab9e15f9dcba195e3a300e346822a239192218efb15e7ee41975cc95ab048e3001ac12f0a1b6a745229724dcd5f6cd3610ad58694b92382538c881cf229bd9765bf78b9022e9b7c591d4801251d367b38f21574487b2bd1ead58e3d0c8a30ad1d6fedd010001	\\xf237ac4b8a2fb69468cad46bbddfe46312315c7d3c4d5d93088ca941765ab35238e6e78d233b308101388f4c5d6b77a8d764d580a03937dadf74d7c1fb7d5100	1682618261000000	1683223061000000	1746295061000000	1840903061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
331	\\x079f381f2e81560fed2ebf1eca5622b2b30ef88509a539aa9a57e0d3a2d7901ce07021c6c101ae569870560d17acb154f4ef3366d293d710a5104608dd3bbec1	1	0	\\x000000010000000000800003d169ceaedc05ceccefc63ad7bac1047a20ca0d3299f7958ecf63c78ccc87d95706150aa08af4de81fd25b7246ff820d880f19863f43001fb46abc55e8a0313ee4160d4cda2f5996bb9ae0f700a78921c61950b0fd003b17c7b21dbc3c4f7002610a89f4a2efd50eee05a2f2d22ccb773c7cb6e716abf890c93bc00350507e6ed010001	\\xd50f5b496e4cf8d5020292c812c9fedd64ed3d152b7eaf0a89a2b8f559e799d8cf359e7ad0ecb44b3e0b034d9075fdc05d4a5fe150f6893b7b1f506120438a00	1686849761000000	1687454561000000	1750526561000000	1845134561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x0a5fd4cae2dae4b1a485075ce4b3e204e845e34e880f96e1d79ec4460efcb3c9f0aec8f9c75a8584e6eab446f049782f7e15196a05562e96d5dc8243d4804c46	1	0	\\x000000010000000000800003d1bf17af95251ebc76aa780c2360cc64ab85e2f8617fd80cd9ac2a09dd14f67cfeff3100c45dbea51abce1671ae0e284964df47adbc3322ef741bba38f527e7e27793121f309a93141f23c3102663e74ba415fecbbde40d8da959fe018fb9dd0eeacc71897741eff24b461c682f54f27e10101dfafd01602290137c8731cf7e9010001	\\xfaed9f9364fd9b010e2c2bd2d60d892b308e1ad3299d707178513bddef61d7c5e34a1f586f98874c695ceae808e68958c7b8d9d60e6bb5813be8aba5d8293f0c	1686245261000000	1686850061000000	1749922061000000	1844530061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x0b5b19b38ca6a3a3279d410dfc5775bb4f50b04a874b0e003e41b3ffd65915b654c4265c57ec08e7698ded7667b2f2fb990c46519cee9647529564c2e5bee8b7	1	0	\\x000000010000000000800003c0e40a12fe1ff20a24cb9668cf00a5364ec60d44212e624ac64dbdb2bb65d0551736ed27fec9de9a87bc28932091005367a60242a3a755722b2361cafba2b5d4097b51265d34752adf6007ff35fdb059a555d1d69aa75af6d481c03b273da916640f5cc87e75542c84cbd51d4487d5bda38a68ea819ddb88564756f67b59e6b7010001	\\xf4d9bc2c5a596ab105b8a59f177f2e7ab448cbb220846154033d20d2e44e4f90971feb48d6db72d1b16392f96cca99de300d5eaa80d20a842bb7faa6a6f4c704	1678991261000000	1679596061000000	1742668061000000	1837276061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x0d1b657984c4ef4c54a669e2f24fc686b8e3d7c1d7b0631efa63f06b62a79970abc73753acfba0a73a97ae1fb319125cd20e362e551f2bb50750bbfbc963e7f9	1	0	\\x000000010000000000800003e8962d6d2b95da7eb1c0c3132626ac3b9b3062645c1a8f355f7ff5d6ede1e0b5e4567d671faa2d5d1f5812214118fedbb672154058524212872408058221ba27397d1a1fa46a3290d0a39f431d6915bb9f8b915cc63aa4ab1ba69b8ade38e4265979b8ff805171e34828dca25096d9f3518431e31e5d665f4e1971ba7c18a465010001	\\xf3b039191995453c675a6c4a2752b9a12fe3cce73c927ee8abc54873065f9226676ffc765dad6f7402071c10d59ae1671aa6c442033a5c3ee923c9ec59fd6305	1675968761000000	1676573561000000	1739645561000000	1834253561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x0deb2826f13ec8c937ecabf945c9ddedfb8b6c26a6b1190fdb55271bfedbcb1b0e5dbbdcc4a53699abc25f722e19dd6750cc484881bdc5a8a0dee91850093180	1	0	\\x000000010000000000800003ec01e744a84eead3d5c1ef2dac5b34dc30a0001aa4cab6c416f6f792807b8156df930af06572f3e0adc2bf6d17f03168e086cfdad6c3288f8e521de60f34fef0a6a4797074bfb1ba24ee3b6b6d715665b80a176f2e75439c31b83b8bd59996daabbb4525c60099d22ef4eb1e0aa7ac18810311589e44520e979404b8cd25ea55010001	\\x8d538f030341d0562ea5b37ea68fdf49ba6ab4b75f0c57605b2ef61f758de224a2fe237a93e2343b25ec850daec13d2a1045ee62cded889b1b95652b385a5f06	1687454261000000	1688059061000000	1751131061000000	1845739061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
336	\\x0e3f5c28bc7c4d82a02a39cb77935b9a665807e4ec6a424946a14f04e4081b150d6f61f4056872f965da2111a7eb5009a16e08595a4323d2a3d38a421b59af56	1	0	\\x000000010000000000800003a53942a884bd7ea1dfc9da472bfc213bfb21d1a2c9d24f6ffe038e8585b07ad35c3724153a22662aa231d9b29a5ca41bb88aa830dad9bf571d43ebba95882caacdf0c885b6af5404045785216826aae88e9c5ec2d06ee44b52ac837a06bc59191995dd3fb4ef8c50720331fe7ac2574625f2a7cc6340dd86638871d99397f6cd010001	\\x26b58d4819ecf5a5c2548e3eb3c14af372ef0a894ed8e9cfe6084dfe494b151d1a8a7df884af72df7f92064a22a90f074da31b0cb4ae4608653403b65958b406	1691081261000000	1691686061000000	1754758061000000	1849366061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x0fcb767db5aa80b42a04bcb8b34b9374ca076c4203f144c617effa4949f2dc29ec819217730a23ce02031147574f5736e3ee3e6d666fb6cf9edfb649b399156b	1	0	\\x000000010000000000800003ddb1452c216cf2e635163e4193e76055a294e9a2c502c29bb0d53dc4bd42bbf2669dd22da437834e77e694f33f32e6f812a9da195f70aa6469b08cd5e11d15db259ba73deeeb4160ed3d497615009f9d46687cad5307242d4b11fba91377c747429d723894041d702472b43c6c1ab6d0cd3810975994f28833b95dd53b051551010001	\\xadc0e5848ebbd154e5c2d01be2a9c7bd343a3b170b6eef25ebaa2f14a28d546d9ca1fef93552e378496028264e618e2f4f78a75bb9f687f9ff4ee24c6dcffe0a	1674155261000000	1674760061000000	1737832061000000	1832440061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x1237393c33829a14b9593c0ae11048a90fe44d477c6d24345efac823eeb6540f7448a9625d4c1a1f1b510584014bbb03ec45c401d845a380a2f141e5a50f730c	1	0	\\x000000010000000000800003ba915fde4c93171cf6d3e3e5ce039791ab867583c7186f9a5552ba5793079030d584f0bfcaf85e8409dcb3e74d83531eb1ae72e50e7ff0b458386057ce5a479ba13b63eb66fb3fa2ebdb2c5800eaa357b3800ef4acaba28eedebac315d4c8bf73084b21fb4ccc5e60dabeb545a30ec6a0df59b89c9acbbcb8f16cbdc7cf92c11010001	\\x26717c28bccec44f0674483f2f1e0a03c6743de6a61cba44a90dc592e94d68309d08c040e8d84ed4e55e4a0fab493217915c202db2ef3cbc1d33f4ebd789e308	1686849761000000	1687454561000000	1750526561000000	1845134561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x12cfed4d5a62232f8811067ba842308330e33bebd6839f5dd3eacc36a9231d4b5160a92cbba5f44e9f7ad3c56123835b9fcbebd1cf3760f0db38740dbd3d5f46	1	0	\\x000000010000000000800003ccfa3c8ff6207de8ff1e09d8f05ba7064f69e35bbe065232af629dc2143f346bfb5563d991c1711e6b9b430d94d0d48c53d36724426e47211da019f74d2f6338962540842762abd1d78b79b8bcc89107280f89ff11ed374d1289ed655c3c6dd512a5005199c7369be71db45e73eb583fd1cd435ff32c8b7252851865a0e645a7010001	\\xb6aa1d0f1896d9f31289d59dc275b15f96d2bb6b7b7274400b8da8fb86e087ae189f629bda4fe1e098e2ae3054aabbae23a52f6f2efaf000024551bc4b5b310b	1681409261000000	1682014061000000	1745086061000000	1839694061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
340	\\x146f84657918eabf954c73be9d01cf75bb82d39643f41f1f5576705cbe75273886b1fcf123ea441a52aa58c73591e6144faa8d468f946764e4ed1da6e488d863	1	0	\\x000000010000000000800003b73a445ab7a5b65c903db660ec957c60ae6faae117cedb76e23f7e95267e41a7ef2ca042c6c4234736f2f60a87b3c6666348f03d6016b4eefe4a83572ab7a50b2c46686dd76ba11c50e06e6b87fc29cfcf302e36b4bb8a30baec4d6f96abfe2ced14794146d80a8fa29043ad236d95b1cb25a015f25bdc2f898fdf3b40cec391010001	\\x8cfbf022954cc2b1c340f540d73945b27ee809d4c82c101e12468f1589f35778e9e6cda1c8d3dea8953d54d3f317a27e7d99a9e315b05cab629848c699c5270e	1663878761000000	1664483561000000	1727555561000000	1822163561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
341	\\x146b250bf323b20e90b231f99c52e37d647433938ad6369898ac5b6ce0a05e186f684092f9d220b1eae19571a7876abcd09069cebd7cb2fbc1e45cf2ed824966	1	0	\\x000000010000000000800003c976c16d5b7ba9aade94a5cbbff5c4c778c68f6b7e02d2a6c5881bbf8055390994419396cda300f0bab033879a1021eaee0afcf152d49960c211838e6cfc94b7c2a60e981be23bb4fdccb44a7a4aafa4239689644b187ff8ab1e19928a8b0b4ac1afa1a97f1d9bf20d60d3687ddc86b212971e001f7bc8df53840c4c8de6fcdb010001	\\x1d531451a3d8aab29052c037d89f9ffe15fe24727671d6136aad70917ae20c20248bb03fa90d64ed2956be1da3f83fa98ed914cc5e0aadf492211fab77610607	1664483261000000	1665088061000000	1728160061000000	1822768061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
342	\\x15f31a302ec78ade08d2436c4d91d1b444f4af0cc541eceb642a20b0c5e2762a4ca8fb20b4c72246357d51a459c58e6577e5f2c093b598fe57c42665fe30e13e	1	0	\\x000000010000000000800003bd997a92771b0d0e48e760b8ffd232b5964a79d8eef250ef2d5aed5c0c368b050e1dc7c9dde728058e540445cdff711a9e435c8915a688c3c2879d1e79ffc079ef6b9684f8d72e127d71ef9dc752e20bdcfba38d44718a7aadb25adfed37b1671c6c9016691b39ed4eab54db0908bd525c7d63ab3cac2c97d52be6e8c0fb85cb010001	\\x845287fdbcc644898ae263118ea7dd615265a33c7caa22bd230018215a82872872a63909f4e3c5f7737de10690171e7791ae6f884e950b089dabb3976d4bf40b	1671132761000000	1671737561000000	1734809561000000	1829417561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
343	\\x1643bb2d58e80175e4d7e2e07eb1d03d5294bd8b4724b1ca46e10898a14c745f64d23960ec072a98e76e3b160723cc672b6648d5c6ffce38970d6514d6a43263	1	0	\\x000000010000000000800003d8e811cd54de1cde61835db75538c5eeccd85aadf1d905d4c77ad9e266fdcded11818030deeda27fdcff3fccb147faab709b849591e87945f9635e12b358ae8732741f533ae50c323870ec32d97518cdc0285e8cce12198ab54fe817dc98844368df394dbeb4e1fd552b19bd9fdae2114276ab9ccffcfbc7d24f7877190cf2a1010001	\\x95de471afd73e59851c9ef742a1ceadc4f2e2b9870ba19224a9829ac635d5e0d603844eb72fe24a5c4bb47c051056dc4b9ca59653547533e9bf4155872070a0f	1668110261000000	1668715061000000	1731787061000000	1826395061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x167f43d31c7b95b759e14089ff9e9807e7c2229cb1858e4b440a40228bb76cbcda9d4d8e946481747d1957d3a3da72e7c2012f60312a42174b5351e8bbebf404	1	0	\\x000000010000000000800003bb1dd9daf3cc5dcecb68aa9ff0bd2f5ab895d08c2810d9cdaa77a9831cc4167c1c07705979def68b66a99cf9160f05d94e36a5ba12a3356f920db532b9dc321a632d7120186fd69988197ce22308a5feb34f4ff9112c084d5c65f83c9d97692d93240e96a4e0b653e50bce8955059ef0f4c561f9183094373e1df301aa92178d010001	\\xe2741aed83a0ec8f69e5107c49fc3429f9ce022611880414227a9472df573e2e284b6478a1d80175036fc8b62ead7d7bb5593cf68571cafb529a93c9ce5c2b05	1663274261000000	1663879061000000	1726951061000000	1821559061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
345	\\x18cbba49c4f4afc6d7c0aede31901dfe4843970d39685d5c71453396f8f964bc06a4dfb266d369a91f5d5350f66ff1d1a2d2d4f43d85ec981d7894bc1b5dc9f9	1	0	\\x000000010000000000800003d94732b4eea9c27980eb0c2895d1f2874d5393282c81d606b24c173d5f8563fad2fb2cf5f3ac544a578aa225960837e37e9fa0190d8791c04905bde468feb61e89c748ecaa1e1e3949a1b2044948d51bbe5463279433e44621e88403d49ddc0533cb67aff4c0886237e19a9154405b165368aaaedea8309c38b67faf81d92005010001	\\xe795fd994e995cfbb019e6c4e7555a976316542e44edbf1c4797d82fdbbe7e9768d4f69ad4389b032f3eb4af4213de9656af4915e9a168e372b359a55c1ebd01	1681409261000000	1682014061000000	1745086061000000	1839694061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x1ecf62e404f8e2d19edbbfa42c838570e05525da1ca4882b75009998a5d246f9c298877e1a82d6dbc5d3f8bee46fc4ca9162419ab7027eddd8b69ed0bbe6cf1a	1	0	\\x000000010000000000800003b79e7be33eba94e54fec3c595e45d1323fadb787c4f5ba5108b93b5c621e2e1dddc6850990a53efa9394ae30f94bc36cff38142051eb411ed786823bc1c722a216b9d25611c051e31e86a14e27da33c78a3eb36bf2642b215058eff4a2336d66e86055b8bdade7ff8bf32ce79ab4c8bcb9f7166c76f9c4b4500f69133058959d010001	\\xb2123a95254ba3ad61244bc5f75023c89282d706b98a7c3e9387da0502072d1ae9e9ba1ad601eafec4923cf8490816dd76242856f35958c9debc347354b69b04	1662065261000000	1662670061000000	1725742061000000	1820350061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x2467cbae4ca240745ac683adf3887a18e91dbfb53521e73538c0b0bdee77453424aef197b3c8c70747563a38e19c7b873ab6f204ced10a606cd5da9dbca54773	1	0	\\x000000010000000000800003b5d05798bc19fb4c9c117f71bb66dc1b7c0c8a18d652af259613475078dc8472dabf024d20450fe4cc949a86c92df3fd3edadcd2a63c4f33d78599c0331fa8aae7cbf03b4d3d7bf6f1ef1f5fddba1822c5ce492076658c653321aa88b794886ce5aba6081b365297bcc4084757390d9c6b6e80c31e7556f06ce562bf46edeb43010001	\\xd6387808396819ef80eabb18686328b7d1076abed0974c7087dce31c1f1d46f7d458d8bd733c468833facc291232ef2c059d0887d04ca64d212b1369c6408503	1672341761000000	1672946561000000	1736018561000000	1830626561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x2653a731393468c90c48866b41eadbf62df253f36ec53d35285b0381edfd29f8ce62a6690d0f9db4d8352e96155612cca26ade232bf94a0205469c06ce2178d1	1	0	\\x000000010000000000800003e8d06c4588f3bd8f349081c8b98e73032e73f732b0bb23155c799c8fe5a9ff8a815be0f423f978bec4cf09e22b87fa2c7ac935489d8f05e028d0d0cd18232324b623fcfbbd5844fbcceb6de8161e222194b6366216596c8e5bd3de96b35dc055c29798085087d022d39279f61700c3d329e273781ee97cd673ece7f53e1a53c9010001	\\x84b4f0760d15ab4fa18f8c2e5c061195fa2b6c30db09a1e6aa4c278c9657e4f64208ecb29ef017fd4871dbe92617c1c852b1408efaa1cc08dcbffae906e0cb0b	1691685761000000	1692290561000000	1755362561000000	1849970561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x2647283c5ca5a6422cb15d99e8cae722295e20df7dfa08e2d6de6f96100a196ca2376000287f0ea39578af1575a6d48d62c8e2c542d7c83da6a4eff6979c3196	1	0	\\x000000010000000000800003dda383bf7a89f2d146166c9c48c0c08d6445972ae93c52b4335e8ce1281f6414064e8e66664aa928613f868e13955fca6c7e3479e0b22830dfd401ff6c0edc9bbed0fa7cf885b43a13c6f707a4436574ad0ba1a1c0716cefd26f79b1ab7a5135bb577b803c90b6edbb6408f31da307ac13736ac527ecb6a1e166aa79a32ff7a5010001	\\x44495627436e5c00dd0d59477245ccd2356a529439d67eaf4bed033af055112f681eade0ad010cf71b668daa3ea4465dc063c28665e4f262b26b0623e8ea8004	1682013761000000	1682618561000000	1745690561000000	1840298561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x28cf846512d0d9eea4ff5a5757fa0a87ca1d2fb3bdfa93502960de05ab1fa5185e3c7bc70a2e910e8836a4a7e513c11ca68e4be0473e4d5dc8339371c8c6233e	1	0	\\x000000010000000000800003af87a007c369b39b3806e880b0134ec2bd5662669666b4bbed6d121953baebb8a8b912cad9c5ce5bdc0558e0555646a8765e3476d6773243ce50abefd3a350b3de52f2cce2ea951ee07adfe930844ac0cfcc45b50cfad2d4df62991ef5f1951a19db199b09f127c8733ece88166cbb942fa0d2166a3c3c511eba989b43b01cc1010001	\\xab03acdf264b16f9027a98e9bcfae14dd1f27c4a21539d1db26f30508c97f9c29c7030ce0f5e4e3bbae0f4167c81a7387d4289dab627e27a7598630dd4af0206	1677782261000000	1678387061000000	1741459061000000	1836067061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
351	\\x2f0bed1491c17eb7eb8ecd512e11c41abcc46b24c5144cf48dbecc2c664f801e23c3ebb36d63e61e29d9bcbde9af868c90d18c3939f7853994f4c2939cb296a9	1	0	\\x000000010000000000800003d61386103d39cc8500b8f463c6a9be4dc35947a833f92a372c0a371d9429544e0446bac352d12c1582d95028aa5fad9a2f38a5a379d5b3c7331a18b7cd93391df62e5437e16d8ee95727a1e27b0464462bba3a4b5273a19e39543b6db020c76ef01a4e5f17ebb830b61c7f23145affb207b216022aa9ab01bc5d72c26a1f38db010001	\\xdc3daa18850cfa0ee3c9096e4b40316a8f6709f020825d6aa4e188e90c2df83746a6d908f8c73b17b75dce68c4d6778fcdb679cac815051a8bec91748a039f0f	1661460761000000	1662065561000000	1725137561000000	1819745561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x2f2f96d1791ae963365f6132e5965c14d9e0272bcca5c6bbbded5991716c8de00b89647c7f4dfb5dfa80648bb2df22600bda86d4a00b90b378f2855fed9fda57	1	0	\\x000000010000000000800003b4cf6c874c7bf13cde8fa0e10bb3ff9ce72234a3972e64be27f36ff74239ab59d84b19bdfd3a410a89c67681d8995376136ed7eceec79ab6a255c9343f7a820a97a553a2e0a55b8696e84d9cbe30d950b3448990c309448457ac05a4a52d03e6f43ced199d31ce1322fea47eb9107a576d52e5561105219d894ef794882b3ef5010001	\\x6053cab59fa9bd7a6bb0391a26a3734112c3d245cf26d59ab32ee3823aead218b72da6002aa843466fd051959e74e22b88bdd5ed6b3e46f2ae9223356257660a	1688058761000000	1688663561000000	1751735561000000	1846343561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x39971e46dad13a25f6e50854cd2b4d49a3b5f00105ee502c7e177df542c9f919da74560c42c2abccfdbf4a2e9ce9423aa42a1e4f5d8125322b1a8451adcaf97c	1	0	\\x000000010000000000800003d10a7f45fe14c0c4a84398752d3ed7a3cf6d26743880781faf8522c8786a3ac8c5495338a42989e7842f7c0168a68c2f1f2d5073da9c71d794dfd328e9fccb563bb7b1a45a760cf9135ad22c350ee845e3fc77bb89973666bb8b809d299bc78bd38dbed9ea14b1bac9b58f5ced2d563f7efc4d47a0901311fb0f9ff064e48a73010001	\\x94a43e3c6c8a8b68075ade7621d69c4c2e5845aaa4ee82b0e26509d4211f23ce9ef5eae1cd95330f801c22c80fe80fa16a9f2b567ca82828fa026c9db0c04a0f	1676573261000000	1677178061000000	1740250061000000	1834858061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x3923f86d87b54c4ba083c386eaab08eaabf641e0bc2c5a3f1bf75df1b877d329ca0360c861697a560bfe71cf48b1d3ba21ea23f9199e8ff2ce06ad2cd1282ed5	1	0	\\x000000010000000000800003d6ec79dea8aeb662778751798cd027a0d399eb073efe6c34844a6475f2f19942b9732f41c9b6b09dfbb451551cc7b8191d3e0b83b0e990a6898b880a6bcd86f5d93e6dbae64f0802692a389f2992074339ea2ea1998e5c916931a5d5f0c92e72e8d0d38ce7cd2cb457372709e5dda612b396709b9c7e33982e5beed2b0ca326d010001	\\x5cfcb035169bd3d7bef5e510e0470a6ece89babc6310babc0a59c5dc528dbab47b37ff044b09101e6e8a0df59e27fe5ba06a9fef582ffe8a8172fd18d2edcd00	1662065261000000	1662670061000000	1725742061000000	1820350061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x3fb71123e6a25b9906e3a573a5f34f7cd7e2b4ef065d34c4c7127515473401b710e2be25f12fd9e4d113f71abfbd72b71a172ddd43db4217b5959e60c82364ba	1	0	\\x000000010000000000800003d9a2fa1379697a4ac50cf6d0e7621702af21ac73807b7f75ff0073690ea44e2bb84efa2727d818c2dd6bdadb4b22d9a22093086073126a36b63aaec9178181d2570af79282bcf75bb28300a1b78f195e7f94975f78fe9c058a181b4b07033fda66b633d6b8f6d7b9dc7991666a5b12182abfa8fda64404f7f5ee144e8faf6c05010001	\\xc9d15eca59a04d78c74a6984649b44fe2df33ebf70e9e1f08232fef49283b492584a6c20d11aeb4232b633e58cf348d3d73ed28823ec6ee27fbb21ccaf288605	1671132761000000	1671737561000000	1734809561000000	1829417561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x415b0afb3abce003c75e8312cc0f1e94f5375dde31f921eb67ad5a736396717dfa7445dcf078908fd7eb42530782566707f8e34d0995ea3bee2faf43298d83e7	1	0	\\x000000010000000000800003a4f3561f1c06e95958fba78a8f0e739615f182aca47ae27bd94e9036253d202462d0e42efa4d1ac75d0196b851eb7b94faf956617bbf68bdcbda6cc3686bd7c10eeec9f8170b72addfb61c9ff1aea34823cb5d1b6dd91ee6c42f241db10055cd4e3a80a0e7ad15e0de9cc30787305637be07e50e530e4dbd438dd1a66c80c4a7010001	\\x44975a39abcef77b9e820bc24378429c25b769573349865a9c8674180e0afa65bde9111343ee20688f0d9999da2507368756cb052f19ad6e6e3911e399ff750e	1669923761000000	1670528561000000	1733600561000000	1828208561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x42a7c765e4c684fd2f2963fed834e7c0ebd18927b6156d2b42722075c8bfc7d71dfb2dcafc8a7540e719bd2c40f1b7611ec8a78ab081014340b56486d3fbd387	1	0	\\x000000010000000000800003c5728f6d63fe3f058093698b04f8964f4d628d19c60f2fad5bf3d54882460d14aecaba9cc413fb4e766c63b0ab7c3f4f4d573c65ef5ea3dba6544910909ed33851f42eda50fa109cb738e259031d9d256fbcd59bae77fa2aae36df238e047b77e8687b13c732636d9e70f5b22513efd46e1aaeca48675c3801aa8cf4346e0c67010001	\\xfb96c1ee4140a292d0c8fd14c63471fdc1bbb22f37ce856fc253af71bf0a7a3cdeb26ffee2658318c3063b61d5a42ebf9a663f137b1e756f595bc88a5841b303	1669319261000000	1669924061000000	1732996061000000	1827604061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x43c7d5d3e9f8b23610407ce5f669e10e9a0726a8be62a15003449e7ebdaaffba0745e74b81c12b2bb03dd64ecd3cd8ccb2943b0c8a197d38ccc0d8ec8f9ea145	1	0	\\x000000010000000000800003b03a97b4c59addb900944aa0abdee0c8bb5f5f16484b49e9672c3c21824731b2ccfff66420c14de66d377a2e115cefca6b6816e7c60fba40f074daeb98273d661ba067e6bf0fa14a9f7b7fb2954a1dfe876f4256fdb90465c5a5a12acb3de459860d5ab31ed086c28b3767ede735345e6cb581f65c8ba49e5cac6847221cf1bb010001	\\xc63ba5a543b5196ebbb30ce92423553b8ce9dbaa31a1b975832b27b4852594ff002fdff6929815be23aee5a5afe01b0d679650e2f40bbfa31e90d6d51825bf0b	1678386761000000	1678991561000000	1742063561000000	1836671561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x4597f981bf76525f647d078da92c5ef4e99a72199cff705ccb071874ebf28090d8375a027572cd6bca86d87c662815f0a19b86ca8e89e259ac5d268b2be92222	1	0	\\x000000010000000000800003c1daefa34dc8e141a260ed752fa69f50aa53ddaab55368d0091608a66738beb0a6fa48f95154ad14b0f6255baa57b5a75ef30ea15696c6fa81ef9a49eabd6d4f3e9d3fc1b69d72ab7adb940dcd40e3198c0034c11d4a8e1bd59471d72f03668ba3e3a506927697725eb550328421b1f261579fdb7b68c43c832999aee9683369010001	\\x40142426cf99b7682e527c101d0052fb78c1a7d6e74fa22ca436b2333dd493a55bea73d48ce1ed6a5418b33a1d0ba3f383ab1ec52e929a16ef3fbd6cad3b3a02	1663274261000000	1663879061000000	1726951061000000	1821559061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
360	\\x4e1bf140c83e2fe1511f47cd801b680bea3524efe18d8d1139b4c1737b90418d50da480818530e7fcb1c8d3266ba6442f6e141181b0a58f2330efa8fab455ff6	1	0	\\x000000010000000000800003c3e362f6602cb212787c0c8ecb51fae476766cbc1dbca4c660520411b9a98887108d05ae2155c332dbc009d8b7734559b5a16e9d6f43164428288035339d809c8a01380fdf6358654a221fbf68b748143b2e366f146ff184673fa98212a7f2aaa951929520329d33e69b877714bc09dc3cf9f61e5d95395fa527fa216ec5af5d010001	\\x8bbb38f48439665bcb1e090e20e00522a8b4eb955403f2d9da293b3a7007e267eceace5981863e3bcad2915ce58fa2f32240d5e0438fac6a3bc8aab4f92fb601	1675364261000000	1675969061000000	1739041061000000	1833649061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
361	\\x4fbf46302e33710c28db9cd7a4e56a7e8716717e07d78b0863280e1efc0ec686bbe01e2a1835ae3121b5a27bf92d5a9437b18558142449e4d4f781e91466b1b9	1	0	\\x000000010000000000800003c0025652dc9579725832bc1867748b00be135cb5b0518f59e787f8de1b0836995231910120f5a6a6f003cc428cd106de9101aff5b5c2175584c654b94f4d07572adc031885dfada21fb9127bb2d7b10e18daeed2befa12d69bff829b7cbd3d32aa5b5f83634f5748239637377b1af8e1fb2ed0668b1d95169f4ad15d4c3c81f7010001	\\x923e6187a0c190558622c281cd217a6713efad15f7913f7e6e4c1828d54639f11dfd4995295798d73ae6a3f3e59ac8f5754994628b7b0b55e857164028997c00	1689267761000000	1689872561000000	1752944561000000	1847552561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x505b589e89ad0c6dafb9bd499b55741d0d68518f48d1a82f4cce456a5180903a93afe56afcdc0cab4feac1d9f8c094f1e85061bba87f312943aa917b2c66b50a	1	0	\\x000000010000000000800003b9f6fbbfb99fb7cf350c9a6c5a2c6d728830514096e1240fc68c20fbb49c8fb9ac7c2ad8d6a2fa27d4f12794e4131818884bbf7bf60f516ad2ffbf0e5d6fe5d006b2918deca68290b08db576a96515a4a3869f74f7e9a1978d4a523f074048ac571da32ff1abec288ea3ce0549ab8a9cd4d12b043e75c0d00fe564863b302a43010001	\\xb2f49837673a05698323fcdfc57a1a3e36251921d900e2eaa5030f631802738cf686f2a2bced58687ad507963db1edc30081ad18d7c75244bd1384f24abb1c0b	1672341761000000	1672946561000000	1736018561000000	1830626561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x52ab3a237d5b066256aaa34fdf7270c5a3ae243eb53bceaa9ac94a6f76b6e2ed03d7688d4732dba8e75b9501bdc7a74115f4a335b47dec75c14f90e488760ab0	1	0	\\x000000010000000000800003c8c3ed5e7515fffd906b867af4098f24c6240c3e0f4e78d06d2f6367d0bcc72d80528d862b73b1d8a7b739789a3899bec1536b6b14385f4590207ad98415125decbf76498586525816701d86e39731ab16d912b0eff29893516880f56bf9e23c0eb3615f04c4011f82283f4c2fc4996a5d6645f44b5cdabcc0baed2fbfce25e7010001	\\x20214d1d8118dce3502e43d99e304fc3c87ba34ca039c8cca2e41529620d730b64c106652f867d5e79ea3bbb817d8ec53514e8c02d1d77a1ab36c4d41688100e	1688058761000000	1688663561000000	1751735561000000	1846343561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x52d782138a391cc598ba4a60dce5390fb11a56dcef1e29cdba2edac96ccf8e05999685a25509114caa27369e82d4e826ec35aed24e3e6604855f0e88ec0be314	1	0	\\x000000010000000000800003ea81be9fd0fd02d41504395fc3df98bf74cba96654c574cb7cdc32559e5d5011f6a82bdc91491eb52e52cf99bdd2761146e3fb7edf0115179d7c55cfb8d3aaf4b3ad40635f089eeb52e53526ed5596d101e4720fc648de2d8e1007ed9fa33a80422871e6f36cc432de4a6180a4e30067eab5fe8cd8e20e5cd39320b7638b3e25010001	\\x3998c1314c9444c3472efc5dc2929155da0218b18a03bd8cd1bc684b4c4c2fa1eb1047ab4e4c4ece4526f01b1f6c969effeae729fc1e661800fd464a22d20207	1665087761000000	1665692561000000	1728764561000000	1823372561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x5b3bd25b23071e29d6bb856ba702e9245c16dfbcd14da510b8f43ffc074647ce4c58499e1617d881760b91bcadf214e6dbb92c956aa88ab87f339b0688fec3b0	1	0	\\x000000010000000000800003e73b4f2c2f2cf3cab7c08661c359b818d6c1a4aaacce898f866af41d592678d400bd4627b71f55eae02940300c6d93716149d8bba6f4836970a5d714e45f0d66976b1b53875ef69e7ea9c5e90f4299fbd2f9bf57059ed063b9b9396d1af121677d9c4ba9078bdabf2cf3d91a18482a543111929e2388689c431d2c9780a3e0a9010001	\\x52e0332424f47a980d66fa6f7ac013b7836920e09d966082083214b53b1a4c53942c763c1ed8938c1e6fc93de57363f3e4da8523e7cd84f90e2fc7fd8f88790a	1685036261000000	1685641061000000	1748713061000000	1843321061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
366	\\x60a34023c2dba363d771c79c12bf6af6a8d795a098fe3d1666db013af8eacbe9576222f36779b2d0106dea01e055787f5612abb723318f94ae8adc028cf90d9a	1	0	\\x000000010000000000800003ac59ebd469cfa14fa31d47c42ca14a46b7fe27abf47c9ae870f5058eb9de93139dc2afedfab20057f5966062a061e9cf0e167f5e7ac5a502a4bcec89c03bb660e941b84cb6494d1d43d1ce1df7c301bdbb06b5898ae4adc3c4ec9e9a421bfa828ba106876a477a6c2e46bb3296aca2cc73297db3822d3391b24bdfe7fab6e701010001	\\x19243c42c7ad52a281a4e777318d93ac72fff08f740b58731bf0b7888395401b3b32b7bb4e86766d5f3f59f13443b9c29378f104b79d8c64ae193163a8a5390c	1691081261000000	1691686061000000	1754758061000000	1849366061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
367	\\x61cf63269bf57d423b88e2c7c70e816a52c52788c846c3baa85683dfa3c424a965c0ec4ecf0b772841dd6e279a7eecae8678877444e6aeff325474883e6a18d2	1	0	\\x000000010000000000800003cfa06671f7a4362fa385998e3b9fda79118769f017f6a9e1d8ff424eb11d12f3f159127fb0410c7d609df79ac646d97488d2992bf57459e86c5135979c096ff3fa83fcdefba8ebb90960cded4973b594173c447e73c3b89099157011df7b1900e53f2f5388cc5c1aff9faeb0c426438e2592b4d6d92205a93023da8f36048401010001	\\xa293253c7285a3d81362d5772de8bbae91b40b408ed7ac1e84dc5817c3feaab6dfd31c40dcd178d2531c59aca4b0b2a855cf1c27ac1547870fe9803977a5380d	1689872261000000	1690477061000000	1753549061000000	1848157061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x64d3134cd9becdd87faa0b1ca28a442b80de37a7471d9d5bd5b44c691ef2b7bfdbaf978bf8a539c487244fc9c9be5b4e97bfe93f9e607835aeda8b25875cd3de	1	0	\\x000000010000000000800003ddf3f4f4e49db66c04329d2fc871902c93fc0597170afbeff8280938ec829715b38efd0af8918d6a978ac50f8247c258018046bea15a256070980d41aa1cc1d040fe626ecb97d7f208e61090e7b4e3fa3a0bfee8af0c91e49463e734b9f67002dde606c40c5ce049d13d9aee58fb83c6fc934190600533afacdd22f3a0f57ac3010001	\\x623341b59cc1addea22b91750ab81e81efe55b42fcb285a8a05b6973c612b6436a946b56dd8f800c1eac2ea1f2d8fc38ad383619e59c970b2ddad59b907aea01	1677177761000000	1677782561000000	1740854561000000	1835462561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
369	\\x699be68d120e22e2a055ea1433548aa03cc425f46e7602825f936699c31a5531e35ce0661c740bd977e88cd4806f875325c29333b9721cf03db41b0c915b0767	1	0	\\x000000010000000000800003d5b348c8fb2224b322ba02ca6f9441ec9b9806119647885f49cf5aba047d8f862a37583d8ece96371359068878b5470bd7116ece4eaff93f68ca9da540017e945c29ce374f4c87d512704b19f8d67156e4f72baeed55700edb0484db8df76d44972127ce00f649c8000b8baa1d42966d46ebc74e32e2a9cf90fe704b8e79cf39010001	\\x03f450dd89349acd441a3683b4e9ace2bd9fee2ccbefc96bb4784518575f38da1eab067c89d942f40393048fce728a706e1c13af24ccacdec69073bd7b83af0d	1660251761000000	1660856561000000	1723928561000000	1818536561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
370	\\x6d4b971c65e24448dddc16becf9cb287b5c070cab46b833cad1a08761aabe61e68f47bb55292f7dce0a37b970634964466b7065fa4b1df7e6bc0fb019389321c	1	0	\\x000000010000000000800003a21836d0888ab8069b67fe27ac9d07ad993afd3af5fb292517810ba87e74b078e38ebc765334f996a003478bc50ba5cb656384bcd9ea3f6599893d7569f46c71a30873fa65735be8401ce554120b42354fd7a084aff5766a3cf76b613c9b67bab2430937ad88e0bc6a5b8bf4c222757dcafc49cdd798709f1d656b58dc2f4b3f010001	\\xa337550fe3985458f1d4a02ad217c016e6bb8ca8857a0693703ece994bb46d1b058eb7a6d20ec6bd999793eb0f9b7d0d9f433c482878f432ec85e826483a970b	1680804761000000	1681409561000000	1744481561000000	1839089561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
371	\\x6d97b78cad463301d8993b9c22ff3750db7600ff6bc1b1c1a19ff377d58ae21240fcd4a34c82ea514da8ad0bdf992ef2a8436b53e2c18a13f8f9e9f90b75914f	1	0	\\x000000010000000000800003ba01a96c40ac52b675d180e82f9fc430d1a4cb0ca0bce9f70ce021e325a163b6ba3911baa10423ef111f58ee1df064a3038d3d01c9237664733078bc925f0c33b1436b6a1cf3002ccd1b3fa1362d38ff5fdcb9ee44ab943545cf4bee5338b2d6077370126da8b10453d0f0bb5fa053934437f3d0e3f7143aca4008006042c9ad010001	\\x8c07e0f34c52ef878cd7530d64cb2d0cd08059f743f4758ce8da60245863808d73ef151186823a4849c76b1838ac7ecca5b6e4d4e3f173fd6e227c4fd0a33205	1680200261000000	1680805061000000	1743877061000000	1838485061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
372	\\x6f0f15d3aaa2bbfbd3b5faef63483b88741c6e22b9dc2a60ee8880ac85472c2c62836bce596142e6d494b63c99a2e29494eec2ad379aa6f532d6fa681e8becef	1	0	\\x000000010000000000800003b62fe712666f251147cde6795a1cca734805045e6b202715a8d256a656fc404383d8a8b16e1f8f7c6dbc68e27a37123de718ad7c78d75a9c5109e00e02eb9375de8a2160783f9529edde10f2282bc580e2e4391e735a0b0e62d1cda889ea93f477da721d18d9daa189624da909b686aa92fe9acdaf3b51c11ce93c01048703f9010001	\\x19409af61229920fe59b79fde7144937f603103ea6151fd493b2489ed7bbf7e20d4b3f862ee072cee10cd8ec79c80bfcba5d953fab70165452e7f3c738aa8f05	1663878761000000	1664483561000000	1727555561000000	1822163561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x73378e85b7bd2ada57e31aaaa40610dcb6d94aaad32529a7432cbbda79a5aa5c4ad0926d5fc0872dc576521f99e0fab9e77ad7e798b5dc40c0fa5431f361b567	1	0	\\x000000010000000000800003cb0e328b6cc45e7b5a9f72ee375d01af2f0894a8b8250597e4df7a9813f62f0bee1efd65b04ca7332e9ec1ffd7a247d539881db8c70883e2bfafad20b8515c57f3b973ab9d0a373f831beeeb4569903d98c39c77dd1d04d1dfabd3831dbc62b501a9aeda4490d3dc7e257f35f5a1260957ad026d6c8c3daa2b83dcf94008f259010001	\\xfa4d8f2503db37907ca88f015bec562d183c72848bec9c6a242bde528a06fd8212e69c460149ae6e18e103f078a8effe81fb02444b56928cbe0d87b55058e30c	1678386761000000	1678991561000000	1742063561000000	1836671561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
374	\\x778758fb0c5247f25c7aa0b0e11945e00032cf83df6abf89a6b63a5cf510a62cf3e9be3bfc28fc757b68b4cf3b1bd1fb6dfe035339c6c2d25e8aa51b8a134a28	1	0	\\x000000010000000000800003e00cf2fc071caed1d7cb83569452dd9a76c7af14e646a409614e34aa7755e3c3d5f990b967b348cabfc82bd9e43167e3c2f4f5e08bc0cff8df2d543e7ab8b1f41f8807ac59be6fd98aa5ab758d6d49175fd6e3915bd9a0698d2c9e2e0a1549d793fe5c8590a677b3046e1fda0acf432e29eadfb12e665e3201326984fb74f88f010001	\\x5e8003713f1bbeb315bc72822115b64521715d00a374e7a66b9d46662bdca30865814543761deef7cf5a621e04f3af834f3029eea796b5e955f067b21ae5a90f	1669319261000000	1669924061000000	1732996061000000	1827604061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x78dfcab1217a715cf49fb6c20ce040ae63ca3925b6c43247b13b9dada7a90a37b69fe854267e2c3716c93a0e7ded9f1e8c32b2b36b6c87c06782bb0226d4eaf3	1	0	\\x0000000100000000008000039a270426bc354652c5b98b3c9b20bb5ff034736ce707ead573812fc5c4071b8f765ca81a3d4471b51e3ba8faf0e1a09744dd44582a9b9dc693cf86ce764b8eb68fa68c55edf7407ae77162840fedae2398e3c0dafb85d1891015d885502c0c7ed451d29606f70b12113e593bdf7614f0253f71605eaa2bd035b2e7072d4447a9010001	\\x293daee628a2ddaeabcdf2d2e74163b4470c829b0b074acd5fc47a0f3138db9e640aea574eee0d6259abdf18982adc54fec6fd32de7b77c7eb8388cfe2a6fe00	1660856261000000	1661461061000000	1724533061000000	1819141061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x792f81f1eab9f09c67c2299635411b32888721cb0b2aabd1f3d8af1f882d01d376abab0b1e032c7fd9c08d7af12156a565e48a65d05f32e51dd4cb9b36fedde5	1	0	\\x000000010000000000800003cc3567db099945af3ad5170b9a1249edbbe423989126b906656486cc73c5a5e740d78c07ee8b8f67447cba88fd3bace783820c8c696cc6c6689a41cb0fe01896f0353b1434d660c3a755691b9a6649dac69cf348baf58612f50a37c50464c2085944bbc762111eb9489d4deee64444dab9380d12a7a1444e39b466a3b560cf3d010001	\\x0240e7477b9a45ca48bcddf5b40b840086c563cf1d821d8db8414b65c30219ccc9e10d32fecbfd2a34588a4498438f9fc2629e5a7c9a6079ddd3d5aaf982c101	1686849761000000	1687454561000000	1750526561000000	1845134561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x7a0337f87790951db916bd73f223f019e1852425b41ac34a40b1a9a3f4c6df4242ca5a3413999573acddb61136283ab98767738266a1fa6166835142762e89d8	1	0	\\x000000010000000000800003af4a780a2f4a3581163c860b3fa25e4991efedc5a0d6ed2f9be27ac6a922aba8ee8bdd05a5a21a005af29511a3d4d1a68886e84df3e1bd79f134fcea1bcc843c59e892605359cdbee588c613a4f496e79919347a6141315e9f72129e63ee6e2e6f5d0d46f71202a2027304e449245e78be3aa95b4a511cb0b8541094c0596ef7010001	\\x14ad50feaeeaa6bd183af04171cc2ed29ecb2ef65ca978913317861dbece50af850302e80712971799945bdb38df8698cb26040d02e11f0c2377b0805dd7520f	1678991261000000	1679596061000000	1742668061000000	1837276061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x7f378eca7dd0051a8f4ccdcaa93cd62e322e3832bd34126e5da2edaa4ef70e98afa08b743e6143194fd3b0fc6644daa532123d83666d44a2f1a13300b5a57a68	1	0	\\x000000010000000000800003d2ea114a177b3714b9b1815a3f275f9c6b26552b17f83ab47112f60ef88b3ebb032c12095a133d2c22c672fb7132503f6e2bc6d2df62a37b05b38d4e23aba95c6fb663755f7acafc712c80245d0d803e6dde58cc3ce5600dde9fa9e3bd75b4f6b54c74e5283c8d5f471704f2ac9a5ddb40f05c2578b70e8b9c75e610e64ea469010001	\\x64a8750e1b607590c4f4ad5de11f0c32cccbbc39c2a77228ff3aa22209b378d38fc48be31192b2a0498217212158e929a2dd6e30b98099ed91bb498c3eed9801	1668714761000000	1669319561000000	1732391561000000	1826999561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x7f4fbe49ce857486e6f857bd44129932a67d8ba332b37587b4b0342f3be9fe5badee8335cea74a306a0005601d2bf380f320eddf53270a8c6ebaea09d05acbd5	1	0	\\x000000010000000000800003c1382f6e63353db7041f4b84fb22e2c1a1969a9938e6200281d600f1ce6b596b76f08ea9b81eb91b2522d3968473d10b0296a1ff411badc750f84e0fb73b850e4649b04d9ecd5430a93e72da96958944f1b652839fcc847b15331cb89c7a4ef0249646832f5660373ea71c68163210320b8153d48dbf72219a49f60d92530cf9010001	\\xf34c9734cf1d9d89ab3c34f1966fe8be443e00cec83a8d6a72b735a12f48505822d43345eb7c05c11671d9c2a05deb1bd28ebfa9bfe52ee2bc0e5ce6502ec601	1686849761000000	1687454561000000	1750526561000000	1845134561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
380	\\x81038135761e09951544d5d2cf19bced1e5bb89e1507887282a46911804f0fdbb9adf3c1da2823f5c9fe0821a8e69afc07822ee4c13bc24c042989d119eaf005	1	0	\\x000000010000000000800003dced034422b74018206a47ffae51a0b61e1c646b88cbd347bfd2b5c0c54fbe41d8666f9238c65691d4adc9333a5053df908bde6b75dcc05e2a57d2244e5000de77355c901cb933175e93185617812e215cb3c8762ec804b0fc99bbd66cc807ef4dde9fef5f348d5dd66c3eeb467f39b3f2489f05f6cff612e028598e8297e587010001	\\x969c96c1bf44f8660644a1a0b4ff05bfed1966a95b30aaffddc0e4f44d6f0c0b83e5945064cf7846d71eb8de7294e8f2d4e963704fe704a64de4e4ae7794470f	1689872261000000	1690477061000000	1753549061000000	1848157061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x833f4a2adc4c5890f10f84aa6633bdb60e5e5f25502c07d1be637be2a663b48ede4df36a631a8acd57bf2fb00c675ce8caaf2c9fce0a337ad0d74adf58ffc5cf	1	0	\\x000000010000000000800003b8ae6f74195f66b6ba0a48a94b0b75ef23bb65da485c3f04f078a4aeddbd14c21e319aa5e79c0bc33dbb85d5dab3929f17412c4d8d2e59b34d89c8106186d64f9235cd6db71c808fc68075e66c4461ae0fde409b87120a72f52a431a860e447a90fd4dd2b95e680c70c77c3ad7dd5922ae187ba4d92aba61022b2b621e9467c1010001	\\xc58118f18dd55f5ee232f046ee684bc20e8600a7ad412f27f9ae105169df3ac66e7694caeaddab8238424647029cd62b1863bc8d0013b90895b3415194145307	1670528261000000	1671133061000000	1734205061000000	1828813061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\x858ba2d937dfae4d0cd6ee17b7bf8262ee3c51912af7589bc1cff0f6de964341116fd83b5915e6fe07c0876377e1b67e382f19117c69e74eedd1fea1a9f006b7	1	0	\\x000000010000000000800003f0407fef534b458e02197fd7d71b71f86c5ed9e542e33eb167c257fd09932602f5c934d98b57860fc0bbd7975202f25939b12bba70ec98503a96e7c13cf3315e844ef2539c9a9dfe68600c1827b0d133a86fcb228a6669e600d610d7f84227d30421a05c55da4bc63e6af3e4ae72f137ba195b0c53cc2199dd86d394ccaeb1a3010001	\\x01f8f4f03c5459fb0e012642762972d81e996a013cc6db69c6e531875848391f308661c5bceb601aec4ba03ff2559206ed8c3b680b93c9f2240f8a713cba780a	1666296761000000	1666901561000000	1729973561000000	1824581561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\x86e3b43538aaddb9dc028e570441de4fce60f4e5e7b59bf31848f221bbdeda01bd82411b237a4a3d382b24285c0bf42076b2f235e0088d027cdc0ee8dad65811	1	0	\\x000000010000000000800003e1651e5c322a4c150fcc0ad334f4b9537a56830dc6941274e27178f229ba42f7262524973847cc7543e43cbd4dfa621b0422d5324d89f3f51a2ad40688792108560aec095fbfcd220235e01bf155df21bd29e5c84ad1a99c7613a9d2fb0a7968b7ee196cd297dcf272016639e65a331a990e3e0f808a7dabbf5ace688e52fa31010001	\\x382ecaf2a51b9ce4ad8225a43c79ba5417559c0d2f3d4b0c94b153d0959bdfdd3f35c18d828f137c3afade97545334aa11a5d2895ed5af3b8fa22c212ee64e0a	1673550761000000	1674155561000000	1737227561000000	1831835561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x86db79e1ecf47176ced494cc89f304604d343263bfa630eafda3eb4f53697e13ecc3bdc17338ae9fdb9e750ae82fb4c986f8989459c76889f588b23bc3a714dc	1	0	\\x000000010000000000800003a8c2c8a8f26e620d0f7a3120270ad85818550e0c0f4b7029691a0a30626ec36e416181bf3711fccb0294c901024a18b8355770f96b9043b4f669f7262cb30ce34a75ec94fac8537aeb1f7ed5393f8e9aa850d94d3c0af68359c76e4208a6bf6f171d503979ef0829f4d16161e95a9e639d2ec599fa9955a1ee6d93203c61424b010001	\\x70d4c35dbac069058715d19b4902002d794b13729d82182db97bc00ff3caa9d4861ec57cef84481da423d47c62e2b4185ab87aad7522a7e26031e235c070db07	1691081261000000	1691686061000000	1754758061000000	1849366061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
385	\\x87ab12ab98e364cb9ab407299176101abeb9f877c1d413f49ba7ea02cbb2ff13c0a41043bac949336eb7588fd3ac7783a27f1b93ef3ecb5cd25b9f033195acef	1	0	\\x000000010000000000800003c5975a92a19b7256687856f4bd2049248b98ce3b2471f8aabda946112fefe8590db36747d69dd5ada41e76f9047b9652273623ea5569c1f0a56c3e0240833abe70a45e0b540c517f86cb17c24a7b42ddd52a8fff00a71b29576536b386b80a73354552fdd3d1ca9ea788e30d89971051d193fb7f754715c647a2b241a1873c25010001	\\x1fcfd9796f3bb9f3dccef943667b416a11b7b91a3c3d9709a68af32c545f30383d704be2b0610914f7abb1bd9dc332b4410bdb42ee002a387e58db46901a8f0c	1662669761000000	1663274561000000	1726346561000000	1820954561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
386	\\x8b53d4646a003e984fada9dcdd2accf6a9cf553bc2891475f341b469910f6332b9ed9b2615995fa95975572479d45bb3a655e2a53bf139b1e33d3f9d4030bdc8	1	0	\\x000000010000000000800003e4e1901b7ca4584eeb70018053761f4355570c9165415986891fcad5544c264a00fcb0361d96b3d8db9c588f62a2b3cfad68dabb962fac3cd754d3f6711a01e61ab01686575392b2f0f3651b9f7537883835cce196c3b36b20d3642b4b7c96a6224cae5217a1123bd61cc649237ea68f7cbddcfd70acd772a0006522cc366c69010001	\\xd8c5770bcf70d674f7aa97ba9b95239d4119db2450482e9637ecfeca564f05897526498ddaa1f6215eaca9a54ee15df89b75e2578a9c22d898a6b6eae9bd2c01	1662065261000000	1662670061000000	1725742061000000	1820350061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
387	\\x8fafb8ca756bf05615ef459d20858d0b3d9e47465cb85e4ac3205415706b358ea9cb82f1d331fe2bc3a266b38edf031273fa7188e507247ca0d8137e87533e37	1	0	\\x000000010000000000800003b3e0e018f9f602087540651519ac0dc2f6d1aad2cd518150ae32ef7447cc1f5bf063c7f526737bb3ff57ed8cb015d64b6f0d29896f6efc3a0f70b7748430eb7e802f74ac75872edea668d031f726370fdc52f71142016d72537bd6903c6d704848fa8549ebbee1f35de92712d3fbc8ee6bc76349f0f60415b9c0fd06747373c1010001	\\x35d0bd536bcb53887a864e4175c50b5f87c71a867654c2a64de60584157e697aedf70b93c958d8489ed76f9a330a087626d872066b39783bbb3bcacff2a6dc00	1675364261000000	1675969061000000	1739041061000000	1833649061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x8f7ff816c495fc51eb588b86f60b512db49c7fe88ca57c576d0074442377291d2d09cb72055d1b310ea5391a9dddc7edc6d27fc2468c5f031f8fcd7b00778959	1	0	\\x0000000100000000008000039270d808e317b9aedb3ac697b469cdc03dba6b8298f57184c10b45fdeefd4780789c3a3162e45725390d897035913ec5c9f668f7f494493238e4a6ab6068024b8613d69d30bbacaa5b1d8619eb3a918d8dad80d8b7d0d04fa7a73276aebf6c658ab745ff5b76aeef90ef3ec5a53b61f1e45ab5b37125577b3912f0af31c19115010001	\\xa31f307e104b65a05fe08539b77a03530bdcee5f208ab82440d177879616df035fa2f6f17f8b12917bb25ceeacf1476f620d27a4747ee6e99f50602af00f5806	1686849761000000	1687454561000000	1750526561000000	1845134561000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
389	\\x970f7a014bf28f29a1fa4829ee55f790c3c58eb8d87c53e0f5492725d76d7ed2e7d887711448d126dc86edf20c217c679ffb7e373a18099673d120d8e75750cb	1	0	\\x000000010000000000800003d0a7c611bbc7ebe4ccac60b90f7fb600b7285c4fcbec35c94bfdd39aa3881210528b9aced036e4825fc4ea8417eb56c304dddccc5630493c07556bae7adc5b73925b1c783dbc978894d0a9aed3d219ac6e4f55421ca9415cbe3b3e860e55b90ed57df57cabf92afcf24f5f2fdf59f64c2bced82debb68651db2fdd1a2fb982b9010001	\\x04e1fd2f245c5a25fa71d52ae12ce72c9e9327419c1328ed47fe70eb16ab9e34108dea9e25a6430d8e39ea266f99593d126f7ed418d4f61eccf3912064c12005	1686245261000000	1686850061000000	1749922061000000	1844530061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
390	\\x990372a8ba740ab39a93d16406d8ab46a4c67a30562b9f9c76df77d4e0db55bd6e19ccc2a56aa6630ac7b356a20a482494b6604b9bcb6361125c0e6aced401cf	1	0	\\x000000010000000000800003d98222b5c0fa260af96ec5bc957f2ecd69470de0976f8014421f9b26ef0f9a9328379de10a014e1c7058b5b5aff84aa5a7fc7fe0f15f34f3796e6eb5cee048266dace302acc301143de62a9e1d5f3c520534dfcf77d481c6bb0d8e33fb166c7238eb2179f8b7362543426ad63446f90189ee4ff25265f25e23b3c22df596af2f010001	\\xe4f3ab59b8fda36c6cfefe7c517251308322a23052a5e7a64cec9979fab61f4f4b8d7b7d5a69c2ad58870f31793f5e2a1f0c6ab7ae1663e4a98db018b91aa407	1669923761000000	1670528561000000	1733600561000000	1828208561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
391	\\x9b3bd34c8e14bad8e272eda4d7284bc89303f4715175c87c0fc87638053ffc800dae156da306ddab6cc20134e70aa719d623b5bce7db09c3ef3947d9452f8f0e	1	0	\\x000000010000000000800003df38a2f7a29e456d01651bd728f24d8e90acfb791caac012eaefba2fd091ed4f8d7d240a55785d3b9100e9faa4d8398079429f9eb7fba143345c8eeaef03e1a65aaf50faf6f382db65d9b2cc3851b729eb4bf8fe54a7fb159bf78408b7cbcd2782ac2a626937b3af87ca27b11c66aaeda07177041dcbff910fdebdb08d84ae81010001	\\x5d3cf5e75342ea6df77489060cad3983c0f21a9e508617fac5b8351444236165e87eae0af316cdf46db5e46cbbb2941afb34e839958297aaa93f129f73274e0c	1669923761000000	1670528561000000	1733600561000000	1828208561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\x9de3102b4c03be0799362ea0f9ece57897e875d7e2ecf56c45d8f12eb60f3acc8ec892e809983735446358656605709a30b927c57e14e33a550be3104abf4743	1	0	\\x000000010000000000800003d09ab405ffc8095d1f588aa50a5028ec2a4ec0baccfcf67aa6bccca9524acd4740e180ab94eb135bcb488e78c171cf0072d8e0b718866f571ee42d41e28e13bf17cafc1ca80b7b8bfc91c4b6c6232b40a7e01a590ef333093adb9420206640495f9b27768be63c8b4b7b39f28a9008de6cfd9577864ae34bb45cd924ef7f7edb010001	\\x334df86ad6bd5afde6bef4c7e81e02bd76f58fc5542b47d6b83bf22bad35c8c877d00825798f36aa4ada23ec69fe2f4e122ca733cc0026326f04f0a49b4f0f07	1662669761000000	1663274561000000	1726346561000000	1820954561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
393	\\x9e474a104c3f8871bce3f99335ec595fafed0e53fa3839be95a7b62ffcc1b65935ff26a21447ba62e10111e274a0540303f4469f506282a047d4f180f758b58e	1	0	\\x000000010000000000800003bab961d3e02560a91e9b77138de563b61edf0f0a85a24cd468cf5ab68f92c792a6c08f080ca51f9d40ac501169560ebf61400f521c43508a916e200152a7931b238ae502901bc3cbc2c17e7f38a90d635a18749b836412523965d35a469095312fefa643c02d1775b36424c74d60e77d6bc1e3602a4f8389682d932389f89727010001	\\x491e659152189b25ebe36e92e0cab9deb690a1cea7edbb8c58543303b57707370de0bf48261c14fe24bfad69ff190523132c4f331babd0e9647fb2e93e525605	1664483261000000	1665088061000000	1728160061000000	1822768061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\x9fb3a8b63bd6aa2fc5ae799ca421de63a8055fd49c791393ae27851543cdedde914004c15c76959d7ae6e5992adcdfac29e70db0fe52fde106fd1112cabb141a	1	0	\\x000000010000000000800003ae954bdb2b201e08cc57a17e28e1f8022c1c689a6e72298fbce29e3e970c96e87fe069f8846779847fa312664168cdb5d941b196c5797d921598f411a398c510f77657dc16d96b6c244c9aad0521518b7e389b4d041e2d8819623156449f81dd8f390bf25fbdd1942e2b58826484077020a615ad3c88c0bb6f5be6f7434c77df010001	\\x5ae77082b16c5502dd531ce694ff698a4bd01bb8d32c25e64deb3f9edd7a9039c8842283659f71b9055abe0b5ce910c8eb8a28b1619ef44c889d67db0fe30107	1669319261000000	1669924061000000	1732996061000000	1827604061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
395	\\x9f530a6229b434a33d2ce0d0a17c13752216f908438c6b56d3580c4a938a6fe8e196a256137d5a6936b4c75732c18186a101ee48afa4ba50dae92988368674d7	1	0	\\x000000010000000000800003aa21f91faee28a0133206e536884955fe94854bcf1b92a17eede5105613be1c45126db522c9cf46aba00688c55c2f0f920c7a946a65c6f09dec3487f932e7cd3b7f182498ade179e3a8b8e8847993f025540a6e6530a208876466194c93c3fced258ecfb55fdcb0740895e9a9575de42ebfc7c2f877653492956ccd9925f9369010001	\\x165828e066e8aaeac316c314911724889ad0b57cbe625a9b38dd922d71d0d9fd5a1b45591d30e091aa2ad28b85faee5cc94dd91006778cd163304ef80c060600	1674155261000000	1674760061000000	1737832061000000	1832440061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xa353e64f0ef90a621a684b3cfd65296c9dac2638d05f04c475504bd8eb08f0b47952082c969cebe76970a5a21bbb30b8dd6d787f30df74f9c4ee5ebd46cb2d68	1	0	\\x000000010000000000800003c93251d935f8e2c5090149f9ca8720462738c7785f133b038ca9f54f49c456d2e349abcaed244505801c42e60b8b254e6031228e8283b19b1cd3144757f8e63bf4ce14b2ae76b932af881f91203c13b982dbe235c38f2d6528c4215569baa8f1904d1055c8fc11c36544f9738921bec67a3e46630df6686370ea8fd6a1e02c8f010001	\\x9f5b50464aa4e085e8cf552c989c8f10351f858ec210e48914df60a6127afa697f1db34ff4d1202e1abe9621cb2f099add04f2d43ffbdab0ff0a6df76ee74c0e	1681409261000000	1682014061000000	1745086061000000	1839694061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xa57f7a6d3ad54d89ff27a171724a4782c77129ac91c455ba73c1d5b4215f1e5eb37dc49864cc6e343960559bc9f67a676455cf30e23598241f0387d64a93c09a	1	0	\\x000000010000000000800003b5be2a765b85def12943e36a30fe561f086ac908257e9b401bc97b7eb3a03c5e701e3a88405b636f847b5601793e82e9d583da117ceaeaa5f524958119577aea2856815b91da1c97bdbf05b521699d459f4dc3f2f2aabca5ad6e08a8a3f3d56df588520e427d3e3bc7b8e0615b1be5c875a5e1f32cb953e03049c7189603a089010001	\\x91759d819920ddfa3b37003fa7e6a9b179f221ace2cab900096c48870d7f63ddb71d50a989f7174db55995187a771e96edb6a8929eb7abcef1e01fc98230560c	1679595761000000	1680200561000000	1743272561000000	1837880561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xa6172fae654584c41542fe1f4ddfbc43adb8f6569595f1716ad16e756be3cc7f95cd3fbc499e4e73e61666131769a2d520c3db487c144607a7e48dda8d853955	1	0	\\x000000010000000000800003b2390f3498469806c61f819136e47d4693ecf5a58f0d3d1bffe9c289d58a1e1174137feceb4fed878ce07a97b0332b80d96450c94cb01b0059ea20369b18463e52f97aeb4e3952a0bf9faa19d9b0b4eb9d24909483f4f982e972b6f1811f779a649825f70224ab9e8ce2b0b388e49b089d58d5d414ace0dee1198eb3594ec1bd010001	\\xf91ca1bb3f5382015e90a82782f460a33def20916e2d1fb707dbdc488497d30831ffa06172eda10a1b04117ab6e6ab54550cb2737a0c987835c4b6fbb87b9e04	1663274261000000	1663879061000000	1726951061000000	1821559061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xa967a1e06f1a5632922561502fc9ae66a79e0a37b8c758720718f5b85c98bb4548ab5c9407fe6f0617f66ac1e000980e34aa74b7c460350c960124dcec5215c4	1	0	\\x0000000100000000008000039fdbba13d6941542f1d74fec3e55f3db137f0397d208adf295602aca19817bc236e29f562dae8bfc44e086a25c0b61541864b7a2c88060e414203a52e0afa6b40fe0f079389185d45c0b409df544d414d0ebc4e38db4252823ae3dbd6a4ac6b923f3edf04227a34c6e4cb7c85ec09746eaf936308f82f890512f56d88553d391010001	\\xe495bf06938969adbce809fa6fd7afd5f99cca3f73d517bcfb83c69931240a6bd1f5dcae06cb2b6a5a4aa4b6efcd52b652bc7f9afcc55116a0829c4772686f03	1670528261000000	1671133061000000	1734205061000000	1828813061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xb7ff19919280b2400922d3ba69b99aae6e89a747eab2557adc5fb14a4f81dfa968e4579013644246ecfde8df9b7c3832f294701dcf7a8dadd8d4c643e07143d0	1	0	\\x000000010000000000800003c1ac6ae4c7514e4168d6db8ac48999f497de070294b0fd55f05fb1af8897c3f559b550040e16b1250bc26abd2d691deb331877ae5ef7d5362da485828b3f08d08ab55a2ba51d15195fe28dece1589c8f13cf7963f36aa7b8abe258855402c8d792346ed1adc9b0dadd981d060d4a31d03490e587bd2f84860aa6cedff2fc86d1010001	\\xa2b745c45423103469df4fb118129cdf84940f0481395e964de6ea44eeb47274b61d8ceabe64521cf3dc1cbd406d4db026aab11bf2565143fc4e836bca095c0b	1687454261000000	1688059061000000	1751131061000000	1845739061000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xbfe74ac87aaa32bb0602159e153e47ea0ea0a07bdbd01cd4a48d53ab62f1b3f242daf8e6ae8daccbab1bdc5a90dbbb9283b33bc07225569522bcb22221ff4a35	1	0	\\x000000010000000000800003eea8faf0c43e4d2fea4c378fd74f69ee95cf2f4a51ebdc77e8b2f8e8ca59b5de76d3504250d71dbc97651f3d463a4f10401ce6b69d1599f557a36efb1a46f9850666060f10008cd2e360eb72097459d20e238f81fdee1b3f902926e0ec7c2845658156c9f6adf366aaf51c90e1aeda49b50b7261560c7d16273ba4dfbef48743010001	\\xccc159a3825c34ccdd5ccf6af5ae306450c4450dc022acde6b146c2da25aff60f9e79f58d79e5624c229d750e357657e74ff2db7435078eaaadf857a6d996209	1685640761000000	1686245561000000	1749317561000000	1843925561000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
402	\\xc08fc4c4c7ec7c798c0ff9f98f7a1c7f04b51f0fbec26a339874ad6aea669fc927a6940c089c0640ee4e5151536eff4c292e84dac9ac21bb2da825cf2cc4e118	1	0	\\x000000010000000000800003bdfc98d7c49d1710fdb32b663adb0e734bc3bb34c445426c0f272a41bd1e77a4a110db149c828c4f5703c076dfaca5349269c5448d9ad8493e02b68e5b4c971db791b17f033c13980d65cd36ecd8ab894ad4890502643c34f54b3853f6f7fd126c9fc58dbfd12f4d48c47434f8ef7e46de5f85be9fb7d0dbd44b6a85abb61c1d010001	\\xce7caffbf7af2438e22ecd884f234ff17c81429e2a49dc4323fea101016d76649d14c3883cbd1917719102c2edc6b18115630c04d4509b67790405e06127ff04	1662669761000000	1663274561000000	1726346561000000	1820954561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
403	\\xc1e389d0b5b54b95e82269c4d7c669b4668c280ea119d65f0505bd060f870f45f5ce8b97c451f6d983acf69f87e5f168f4e6736b50707c400a04eda341922199	1	0	\\x000000010000000000800003ce387772c6747234da9f25c3b4c6bd5372aac8f08475faf55d9bca224bbffa59e6d74af48f884b8ba1f373c3b4e89b82f30702cad90046658c6cf77b5e98168f0ea44ce19a9871d5a5e5d16bb7479f9d27ff7d0ac390e79c5fcdd7050173ca669a0286345c13cfe745d4b2555d500ecb16330c6d6ac854d10400e41f57a96401010001	\\x509f35ba14f064da53f2b940c3c18c64ec7bf0d28cfbe54d09a101caab73560e584fe48b4adfe6307af114b4e7b9a41ebd572d27b5ef8c8595486f21dcb5ba07	1668110261000000	1668715061000000	1731787061000000	1826395061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xc1bb4baaf3d786a37631e80a9ed799f423da4214fd42b2f21d5457ca7fa0a60d3b0d8fe8082049133a665a68cb250e2a8a638f4f0f55a9d04e15ccfea80e3bcb	1	0	\\x000000010000000000800003e8a87a812f922442736c15b1bebba523f5d7e7c32f074d8a72df8fecdd30035cf01613d4c39ea4f9151f36227547e027c7955283fef64cf9bdb1e8c6ff6a383169c94d3e97ff340c50594240a2f1498d3e568946715e3569ea85b25d0dbd94c890b6051ec4cb9a7adee9492a50831b9a1b1755a786afb2ebb4cab076193cacaf010001	\\x0c45bdea9382a726efe7c60c11a4b9fd649b73358da77d3458c9fc6cd6a3a4604e43377fabdb06a2c46493210867ea6bcef09fd702e9cc29a31be210e5288801	1673550761000000	1674155561000000	1737227561000000	1831835561000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xc8bba3eab71f03616f5e623a43d2cd40b3e77966e4c8d9a63b570eeccbe87b7f8b6bf229e71ba7ffb1db62b84e4736856e7a250edc1a28a493b6538f779e8445	1	0	\\x000000010000000000800003caa215d84d98c4bc77a0350c39334c0f53080e0971a8ba9d55e5674cdf36e6796d373b90e4ed625ae22b36c5611cfbb75dceb6836710cdcf60a926fb169e23025087f6bcf29a57e59312da8e911d6b56a9fe679e67a74c34619ef2451b48247d1a65681fe21115f2875708e6f83fe52478bd09aa249ea20a62f30d8cb2075f8b010001	\\x4e5f02a23e84499f8cfccef26afdd1e1b0b66504719ef0ea3dad8a1a06565c24ef083f35cc1914ec8ded2a1d123647b867b88817623e194699c8920eba5ea80b	1683222761000000	1683827561000000	1746899561000000	1841507561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xc95b35eb839ba371c04707e442b249341bcf13daef2548dd10355686fc45058dd0f69236c6eb703bce21d4398bb2ed67139ebb7625df8fc2d2e443112c17a696	1	0	\\x000000010000000000800003c092f17811cf787fd14dd086b5d44017b82a875e3a73f0b3d890eb75d4f22d2debb556413648427b4bfc7ea7974401dcd999fc3725f4a5b157d950b5552b984b9494cdcc9e3ce344e99f788eca998843491cc265e7d9bdf0ab38d8b2a666d6c052e43c01edf956d56989b179393d15771f1882871a954f9b6514a0eec09f13cb010001	\\x8ad83453696a75513b805db93453e52d9f4db2a8f9d4b03b5d8a143bd74b7a7ef1e7bf9cea73272410cb0c714358bc33faf770344c4a1cd76dab18b2bb380400	1690476761000000	1691081561000000	1754153561000000	1848761561000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xc9d7b936c32fbbf940258e3b82bc1133964379dac6c7f8830a711d3b482eb3dd11bdbcbabf43a833ceb9b88f32eebba4bd8ae85f0e4b417206127d52d7484782	1	0	\\x000000010000000000800003b84fa45e8e6609a6b79c8fd38bb883d5c5aa723fbfac79e6d8f8e589357e9fab3018d44e3b7c8b791f61779dd36fe28198377c20a5b7ca42124f59a5c7cfcc2fa38b8a3503022f740055b0856d52421e4f51aaf475a78f10549eeaa7d688b937d74757ff7cb8470a783244867576074e3a156d03d69e5ad6fe8269c012c76fb3010001	\\xfbd2f30d9dd950fba7c25fb5bab68f100aa81bc3705c6167f1dc0897c447250d05ce9975929028ff1df043ae9572d0d01ae970f96e186b0d1292a3ecb9f64109	1687454261000000	1688059061000000	1751131061000000	1845739061000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xd10fbab16cce83d3c216279fbaf36557687d2e6dc5717eab6566cbcf3c1c461700131eda6d7e025b3c8c6e231064098ec000ccc28271ded748f3105763d51844	1	0	\\x000000010000000000800003caf8690b2b9539f8590017ee1d3c0e25c1564315576630be524f721a73eca99ca71d44e2ff483fbd4e3466724b5f5ec30350e4072132e31a3c83ee9d6069d522d03f7df75c31e26f621256ae91ecb69989f44c07edc271d7fe1f73e7967ada28e385e26b944b407732d2f1bbb8b55587705f79ce7f69870f34285ac225dddc01010001	\\xd17a5af7a147b569e5ef0b5dc6bc4cb11221752354d5640d97997d8cd9d307897ba5dc65730c20138e1681c66bec5f76f99e1c595e613466d5363e0607fc2904	1662669761000000	1663274561000000	1726346561000000	1820954561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xdb3f97d9d3fec07b10c019979503f266ff6ab48636439e11c6119840fb554ceaf98d994828566bf105e1540035874cb0b571f3b1b749ac3adff985de10d1de30	1	0	\\x000000010000000000800003ba3db6634e88d3a2278a1d469b3c7969f4eb0a7a276b11e763cf4cb19e1ef2f0fdfabad2241e174a2003e61bb4e0d24e172e93701ce649d79aade2dfeb5260b30d2022683c4cefff7d44fb073ab85e259131f7f0056bcf2bb730441ed5c3b7943cfc70e3426b2e1bf63eea1e5bb18ffae57a8292ecc538d112e4e9a28d5d3d8f010001	\\xcefc613cf2d0110305c964e3c7f23cad5e6c67d5f5addbc9f25f4bae84b99f83c344d94e57ade8ca6b5307c43b036019dc84d5bb3aa985ab2c865c395397da01	1683827261000000	1684432061000000	1747504061000000	1842112061000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xdb6b32b56f90ff42cf4249a6ba6000dce8ea85f590cacb3050da4d853aa332ea8eec6bcfd0ef994c140f1fe4a7b8db7ad890f89821bcc5e5c6b61b0c9f1855d9	1	0	\\x00000001000000000080000397f7fee8bb782dbb01e7bc00afef87964676de0bc02562bffb3527ce173ad02ff5ade00d53f93470b80aebf4c278555beedc12922ecb2ddc6b5ecb7c6cde7015f6079c5f1daec32e0f9e1e05ab3c4ec751482cb530051a6b2688456f9116e3de988033394f27347649e7a2668722d9722d6b6ac9d4be63b80899c5bcce61ff79010001	\\xaf38d3ea814580654ce4d3d367eea1cf416cb59a9955180bde4f70c1ca3e5be8221238835ddbfcba9eba578498f2b595dc37b11feea26ab6dd760bc6d90c450e	1672341761000000	1672946561000000	1736018561000000	1830626561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xdbdf73f60a708481492ade55748be2d4debad450c8d80a2a4fe954aa050befc5ade810ef02045a9e9956bb82903fa5e3333a4d5b4ddb3af2570dad86ee5714b9	1	0	\\x000000010000000000800003b5c530f5181e45569b07fc8dd91409576cab18d7ceff3ac7e5cc3b96541434f904fd939ea044668f9fb082c35db2525bc8aa6bde52f4eeaeb6ef70f306ef2b91def47b8ca2d5890d18a50ab4f396df0043210d6a089545aabe9c1ecb479d6e2d64efcfb28b363ad978e4883433234939ea2d298003f35d64b055b766881db31f010001	\\x1cb63ac62359c7a52d462890408a150cc936601e235a25b8759f85f64a225e5a19f0807bcceaef71e0c555c1f9ab796c63ce992a446e9cd3b2671b7b640d5109	1683222761000000	1683827561000000	1746899561000000	1841507561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
412	\\xdf8375eed669936b26c4c13d10d49508b358ed580c7d9c8f9b2452728f2e5c41488cb5b3532b4cfca57c16e5f970706db8f9a0d4b0d0cca94d47ade6bfd4da8d	1	0	\\x000000010000000000800003eb310e49209d7c182c73ac111500cc999d17c78f93865488a403870f0b76def1c794d3ce3685f1b393115ae3f53603eeb304e8d5bb008e4c84c002a058f9daaaa0a48372545d342f6e18b7d2db1fd5c27148672e42cae1bf88c235c5a05cce295b547e9d0591d7d58548a6344b25f892b63e66d18eabf3f8afb1cec6ec49b189010001	\\x97d722a49f5c390660e5362282f31b6958e50529ebe9ef347ea3f8b753da01d7465e9d5ee825ef492d6739ae6d9b1c938114d77ee24892fd70306261aa375603	1684431761000000	1685036561000000	1748108561000000	1842716561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
413	\\xe04f059c5fedc52ff0a04353550ff966f4c39ea48542048e4fd683c84e4e24d0126995ee8e90295a1b20ccfd4eb2168c7d4d8f4d371500cdbbd54d9853817336	1	0	\\x000000010000000000800003beb56e0097b46ba57eabf9d48205d1ca38a78b790297fafe87b2d966c13278a212811aeb7264a4394b44f88691a14685cdd33f1c5c9f6250302cb216e0b5e59971ea5964a830f55a91a75e28aca9ec2bc26d5d0a88c8810af9d56845fa2a2afa23dfdfab3c61145f48cb26fb214ae4ddf8f8eb7da2eaece48d989096efdff95f010001	\\x288bb986ab2e4fc377ce95c356ef213c74c6bc0704266a35ce3f9bf7d3064204677d2bd1a82999d22eadc3a914b430c8c80a243970e5d3fb2d62b3470621b208	1674155261000000	1674760061000000	1737832061000000	1832440061000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe0fbcf5054ea93db0c4111afa075b449b3743bc9ec36cc07dedbda78ddea3a69d128c283354720b6396b24d8aa50173b4ac2ef02e0719e70bc7ed67608fa9533	1	0	\\x000000010000000000800003c4d87c5b7cb1e311026cc48afa0828e1da3cbaac7705de50215891217a41e8fba2bfe73320c4a6b6a56c0da84f25f2ca21076e66b74dcf91c505229aedb0025e648224673abaf59b7d3a265f486b0b3f89c5b70b05c7542dc22de7e6ec48ce00b4349db083bffdb838bbeb456083b0df14f6beecb5bd5c88ce53a5bbbbc1f3c5010001	\\x57926362d019edb07ad91e7b045abae3c6cf7002128885a0818545d6229e2f568bba2c37d1e81b3e91d92e21567057fd0a01af4438acdf58e41536a7616e090c	1675968761000000	1676573561000000	1739645561000000	1834253561000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xe45b57d72887a480331867116c9e378a0e5cd98dccef8d76a5e16589eee7f99eb79217585905e9589538b05c9b5fce5e8c0e4be6d94a30f6b966c24581cd235f	1	0	\\x000000010000000000800003e2ee046b7afeff3b6bf053484b044d1a2ea529277dc5690126f63ea6a856e46c2b28971a1cec1d9db782eb6894c2c6ba72c2eaa30fb4fa0ee1d01efef062056e519c15faa44bdbb5a0ce120e22ea99e03444fd513042053ea67d697c9645948c41768dc5a5dbf5db308aad42173cf07daf88cda7a9bc1fadbb58ad8c4b7fb63b010001	\\x78698f0907377eb565658a68e5516912548920f224d6e29b7448435c05fccce45661cc181523580cf8dcba14833522369a3afe87545597616bc1d6e9714a0202	1674155261000000	1674760061000000	1737832061000000	1832440061000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xe553117c609fe644a6182dd3b2466ed2b8bedc29687a77eceef57e366278d200ee3f6204cd3e961714276446ce85013f6d3f7a391a03c77943c36c09919b8c8f	1	0	\\x000000010000000000800003c7d6188fc9c24c2d1075950d976c8b374a851cd08c607c313a271f3e5e23d74b15de1f4ee7b4fff9e3c2de76992e4ac9aa5fb8efdc4abd488566d473488e0e85dd5df0eede310470609a9f5bd791e3407b3ef667723dc6678754b974660192321ce7f3e43c74d25902d7d84e8ff23c109777217b5bdfc3b54ffae8e33555f373010001	\\xf8ed462257d86b3c67e3b23cb2148e6e7213dfcf6071a8736b9fa3c165bc579bf05882280576a4cdded6d931b6fb3b942812a703204e98b75b0f6c1c52fcc504	1675364261000000	1675969061000000	1739041061000000	1833649061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
417	\\xe93f3dd918edad7d86264cc54d90109d524f174ebbfae26ff06194ec02fb1cc8ff893ed7a515e9a895d39fd5d61a82dc229e679eb2108e786e4d9bb704261f06	1	0	\\x000000010000000000800003b885469f2fa6b16b30d1e37085268913e2434595741c17f5081dfbeaa7ea55b9b6ecf77c39c33f315ae51aa17b75c8455eaca9a193a89cfb4a734f32dad41d7f62ca4b43b099d029b89ae7ea6fa4fb0e1f249408f13fffbb84812d16d67a0b9da266595b7a38ac0e6dba446d912cba74b276fb6bbc6e9545ccb1301e3408d6fb010001	\\x2d87a5d9d8cc5597bd688d82ebc326a5c527b93087765e8e7297a82b6c18bda52f04df861fc4f7ef7146f5490c8f3b7fc7b56d0642cc3f48916c765733eb2e03	1690476761000000	1691081561000000	1754153561000000	1848761561000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xebb74be3017b011f57da9fdfa65ca62368aefb1169c5e44a7d1ee4e324567261eabd41526a7afce3350c4412d631d963d8f665f332a2dbdb73195b77f8bb51e7	1	0	\\x000000010000000000800003baa2c91630a050538c1bbe261fc1f89a7ab8a206fe01a811c83cb7a61644fd733f2c595175a1d91d37b19cb9ad7e51af0d11e8cfbfa6a5cddaa15e1682aaccfc171408d15fabfd410e6a0874524aaaf732f8d0c2e83eb7b8aed3b80377b577e5fb98cf337e7ad11cc98c53709b4073711a55a5828caad79c4bd305fee449ae5d010001	\\xd7f68217c052178aca0d6e823f6cb20ee5d353618e521622097a41c40fbcaa9990284f04a0262def6a1cf44470377eed0383ff8f89b2a181485063134815e40f	1676573261000000	1677178061000000	1740250061000000	1834858061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xee47b72ad85e44d4909db961640947f1e789efdec22379b67d9a3e7b9d2024ff56096f5e824b7243bf1aea00481a6ca03795cbfc1de699b0846486a4b14cebf1	1	0	\\x000000010000000000800003bde2bca722814fc4790901a93b868dc753747076660141cf9cd7a2d139b31a690ce8bda683d994379bb0ee91c87db4db8d9ef09464b0028ea7c0053127df9cd2d0c81089e90fa3357ced07e62310646b90c2f08f0b12a9ae8a0d5af7bf5e34af6d9d78ba2f9185022c106a7b9d62da6db1864530d9634f14213f6b7b1e26db09010001	\\x18df66498a7efc14ed4602bfbb0b3390ad67e05a95702361eb873cfc33c730d4e317fbbd18913369c22c99c25256e20893dbaa7ec1e064f6386f590e5241e301	1670528261000000	1671133061000000	1734205061000000	1828813061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
420	\\xef63e1fb97f84aaf72176743e23e87acc8f5ae20a9187043ad3507e9d6482a8ef37093cac450e5f98d32764ff5bafc1c9ed5d07484965588dc799063a32978ae	1	0	\\x000000010000000000800003ae80d6b8e02e7e2eba056cc93e3a36370af6599d23560880bd174b07d27247ee6c499dade8ab36a83ee96ad987042e363f8939026cb17004f748ac58824281dce8cb24f5f7963875103f8d2b199abc523585fd1d3e523bd723b8fa24e47ae9bde5e92fee804358b8823968045bee59a73556d69959706be1353f26877f83052b010001	\\x74198dbb2fd9678e6427e3db2e33cbe2562781bd72ea3bd150f36225f9fd054d3faa3076865ed67250aaf7a47d2f04389e22deec0a6f0c58c5056c54389d2d0b	1677782261000000	1678387061000000	1741459061000000	1836067061000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf64bac42d6dd1712d321466812e1e745d3310d0450e92a3488ed007844e1238d52c662a2e38861cba061dab1c8ae7543a1a37e9f011e0dad65c058978d50d2a3	1	0	\\x000000010000000000800003c11433efea074b67980a8350343e4980f01cd54e44934331adbe40ca8364025fc3f7ba4800ed6c954aa48f0d512d2b26d1c43b306b58f53ced37ea742d9f64eb1e5236ae8ce0af01ec5998778286c49e78ad4adf63c3b560511711a655c5c00319422e8680ebed462d7f9da7f99c670e9a2dc9ce4b31495a0b36a31bfe6006bf010001	\\xe5621579eb46487986b4c0c18a7cb9b710151e3203754adfc54444a509af1cc8434ec8c2c3610ff9f10ea7a9c9453c4d09dccc4b0a173aae9ff553b02e7cb206	1668714761000000	1669319561000000	1732391561000000	1826999561000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf8279dbcf00bf86da94d3300e1b0a6a346315109568e98e968b97fa48f44247fce6bb5a233021c8e89db2785fd75da8cd48ad3692bbebc50872834f70483f26b	1	0	\\x000000010000000000800003b87bd0cbb16131d5bee06beaa631e74a0e6d99a01dc384be770382238d93cdea7ea4aa80ded2db4e6d8f5d8633179ccea3b64f7db0d9f8a771a81d48a7ab5cf70b6c0b506c696aa39cee88dce10d066d47c01c659d6cc8d96fd27521e072ac18788d347f4b9fe1b5c36a48f9e4ac6ddd2299626e1f95d6c3b3ed2ebefcabfaf1010001	\\x479d3f924346e74d395325b67504866c9edcc2193339d79730459fced2da875afcb35295ef2a70753d24762efc226b70ff75bd8eddc401db3e2ecc45a55ecc0d	1686849761000000	1687454561000000	1750526561000000	1845134561000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xf997cbdec3c9f22d687bbccba7e6592f24ad5d4e63d0f79cdd345e5b333c65f1aeecdf5fb6372fabff3c42eafcfc29d4b26816e0d713d558aa61afc1f2fa267b	1	0	\\x000000010000000000800003bcd8485083f625afb47993eb3d0ec4c1d16347ea3ac4cfbfe27d3512f1a29742b6308f3a48c8833882da2b07ac4213e8528fbd6bd28be24636e693ad62484a8864d747e82379c35d8d622c340797a8e461d34f30bec2f1f89b9000d1b8ee25723bcc4c7cfae7577b04b43d2812b2dad13a59a8531b6cd12d27eea3a6bd971a01010001	\\x2ef1d36995c073b756dace2d0a6af4bb8c82d95ed5adf807a1767fab57ccd07f45cddb9c34827901e301d6a3e87180745a8b40a0688375d9e495325e7cf7aa07	1662065261000000	1662670061000000	1725742061000000	1820350061000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
424	\\xfcb7df20dc7acb7ffec0364b9e1dcf408c0329ad656e2ce7000bd39fcf02964436162781534a30ef6483b4b1b726ab52711cc46420e2044bf1237e4abec8972b	1	0	\\x000000010000000000800003cca198684ac4df61638fe6f920ae4d0c5b87f9f62e4e2dff57ea6c0ebd205122f4bbb945f5eb73b506370a52daf27e81a16d1a7dd9015e7d186d1b281ac9457552e96d761648b9f9259a543945cfe502703b251f095e5536d04a372d4dcdf4882e48590598f969c2b0521870ec6fa74e68780288ea71f16774f1fe87c7a57a8b010001	\\x125de2da649d618d0bf98e7dea3c62fdc9e054c4e0624bf853116d3e0820b6bb18dcef259dd8246721e3c319fd857bf3201362ac74d00a46113f5baf485f730d	1671737261000000	1672342061000000	1735414061000000	1830022061000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660252676000000	1455367116	\\x34cbdeb37774f40ed3cefcd9686d70bab30c31a9afd4e055c2bfa3c8b8597b7f	1
1660252684000000	1455367116	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	2
1660252690000000	1455367116	\\x6182c65007227783a4d92d8509ef78d39b0168996859b65ab1443eb6fb943633	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1455367116	\\x34cbdeb37774f40ed3cefcd9686d70bab30c31a9afd4e055c2bfa3c8b8597b7f	1	4	0	1660251776000000	1660251778000000	1660252676000000	1660252676000000	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\x3055636e89f269e560df6e787197f475d0ee80ec7fde580d98ebd494c66a2c7f603d2e8cf3f4b5d7f0119fe35707df4a27e45cd2c32a58aa6f66f7f926b14989	\\x682901c6597276745a08a1a91ce67062dbcf9df3049b4ba204595b20119fc8d042920bebbee4a39ca6b5ae9bfc463792f91206c24c7cfb98981ee77558927b0e	\\x2b8270802bceddd01e56777d30c8a81f	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	1455367116	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	3	7	0	1660251784000000	1660251787000000	1660252684000000	1660252684000000	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\xa5e69e1a65ec203aafa4dec8d8f3670ac54e97dbed5e3a274440d57e5432c1c99191006515c26b11279394f71ce416ee9b1c5ad881411fe0ee84a14ae61bbba3	\\xeec2892e88844c6b3cb446f3eaf3ebdd6cc3acaea5ce71fe375db877b385fd2f4a0a636dbb6cd9367aaf2a5228791309919be7d066edaf32222522e4e5d79c04	\\x2b8270802bceddd01e56777d30c8a81f	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	1455367116	\\x6182c65007227783a4d92d8509ef78d39b0168996859b65ab1443eb6fb943633	6	3	0	1660251790000000	1660251793000000	1660252690000000	1660252690000000	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\xb44b55b0bcfabdb7ad1c10955b62d7f2674bff99c58610e73f34f1d12ad2379ee7b9051c2f1706b23e1b94c93afd812c407f969b6c09a28f8ad82125697db1d8	\\x3a805ae8aa1fc95265bace1cf63e5ef1bc36a2365816ec5214efdf2a8407235dd5f7b87bdfe580218437d09d0d0b8ea1d80d76ab9f13eb62def18e487cc91a0e	\\x2b8270802bceddd01e56777d30c8a81f	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660252676000000	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\x34cbdeb37774f40ed3cefcd9686d70bab30c31a9afd4e055c2bfa3c8b8597b7f	1
1660252684000000	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	2
1660252690000000	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\x6182c65007227783a4d92d8509ef78d39b0168996859b65ab1443eb6fb943633	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x03f5e4ee136ac823b2324d057c72a4acdf006e4485fb00a8cb6fd7a7d95cfdbb	\\xf0d5615e090ffb1c5196dd0a9aa6a680c9731f23c8d7aace56edfdfc9e4d6fb71a9a81423134d69f6b6e3a737d2c8f874e3fe9f3c9fb145823628ce6a1b51907	1682023661000000	1689281261000000	1691700461000000
2	\\xc53e68243951aa823c4df89efe2a4768ed056b90993499889ac22d8d38ccd736	\\x074668a2dd1e4299108fe8666fbfaa935167341390d0b26399122c3d25d2519a7e30beb7a671b4fcdb89d151d981062baa6ebbdb115458464d047205a8715400	1667509061000000	1674766661000000	1677185861000000
3	\\x0760064bb267a248d9c069856a3656fc9e824e3796f5d7cb1747675d5f67a16b	\\x3a1198bc48724c589ce73c4bcf89635166d15d08ec037466bbb1be2aa7e92163babae1e7619803508996c5d089a2479dc2e6651dc89afafb138be4492722660f	1660251761000000	1667509361000000	1669928561000000
4	\\x8859787e9d258b1873a2b914385a3cf15c8332445e3ad73fa3facdba7a8978af	\\xe12e0ba4ac5fe84e1bdc2c49969f123485d6a9481667e38675a7e627ac704aef2f0e0a776ed19160d37066494e87863952de293268329b2d3f1f346b3195020c	1674766361000000	1682023961000000	1684443161000000
5	\\x360a6fa91038e3a6e4e740f719ed37ac7ca84b3b69cb4ec49e701043aef2033d	\\x9b8809aeaaf249e93b4ab2e4bd7eb985dfb0fafbc84cd1ff1aee0223d4976bb721efc0a4824574b0aa28d860c4fe1b0b3a8b58788f7e12cc93aa4d57f906230e	1689280961000000	1696538561000000	1698957761000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xa40b9fd7f50aaa05a5e8802256aa8ffb091af0491ea634baf6b50478b463200de2b72bb70f07821c2ba61bf59c817cdfd88d576fdc12251273b7cf8993180409
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
1	195	\\x34cbdeb37774f40ed3cefcd9686d70bab30c31a9afd4e055c2bfa3c8b8597b7f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000dc3319a8a18cb2f009be5011d7ffc37605403228ce60af852a280c91cefd85b41001321cd159b6c7e59c9a7fc39ddc2776d4f6f768f695e82c98e5200e8c20b905e94dd665774152aced4ae5b2e2c12b3d99199f545c247b7fd337749d6aec0e24e9199d8f5c4c02eb94c7941a2ddf9572cbba28f326ef9c1c55fd34eaee5274	0	0
3	253	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000063030b5003dda821ae9555e65bfe7c778bdfc64cb7479ea445b99786e812488d7313dc12ab6a91306bd837ebb5c5383f43020e8ab34af3a5ddd802ddfa6f3465305a7d494bfacbaedfd35e74caea0d2e4c04162275cf47dec0bed7599d03b478071423249be8267bb4a2ea3ef7fad5d7716510b88995c19e7d89c75e65d94aab	0	1000000
6	190	\\x6182c65007227783a4d92d8509ef78d39b0168996859b65ab1443eb6fb943633	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000046cc1ddf8c431193ebcc093e93a5d7bd85615b21606d4532ef1299d3976fed2531270a8e7a1b85e0e177a227f8fd446cad3f3bfff6e2bf83b213d94ccfa2110f5e4ff3a940c885831b0e44a3431866cb7caedea920aabd5c6f2ab8fe383fe1f8312a9525262c020183dbd6ca3283f31da7420f786a285c25fff730c5a0acf5fd	0	1000000
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
1	\\x71cd77e7b116906efca1e3b3948100fd33998c89b02c225a1826a03f643507529671bdbc5239edb5ce8b4b19ea58e623eea9671cf1821189fb77f7f8c3bb71c9	\\x34cbdeb37774f40ed3cefcd9686d70bab30c31a9afd4e055c2bfa3c8b8597b7f	\\x4a13051123a3290492a6cf67b0e81bd6dc1835a82f1760eae814bd58f017c573bd8a570e9397dffbf24e7c4586f15e40438b37427f99b835289415664951eb0f	4	0	1
2	\\xa42845b99bfee8de982aa857910b4d3ebffc619ef1b424fd8cedeefc322d26f653e6e3d27fb6124a9bbfa9b31a82fcef2082b791d17f7ff7cccb203cdcf58be7	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	\\x4f7287ed2cfdb10399d31413665906f395e40273c7cb51dddbf9f421244e83dd3f4b09310351eb613bf91e13f92028e056a846cbe8477ba5da82f1e0a8b9cf02	3	0	0
3	\\x99c270cc6a7535ab9eb4d1dc9765b3b65cb572889e7040fcc5c6909995749233ea25c3688b57516bc5cb2f4ce9705b02a88ddffe6b0a2fe04d70fd61e981da97	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	\\x11ba0d691a26b35c5615d750f17b515e9d694c0706c017c173d29d37b94984d8c6cc6422211f38d9a049d0cca7f861206a5694226ff718aeb91a6ab2041c6e0e	5	98000000	2
4	\\x7f3c56ee2722dcfea69f01798ebbbed7399de25749aab92d39b05d7b8667f21836ff7d57eae67be8bf2ac7e71b54962037002d0e0d73270bd8d08c051070167c	\\x6182c65007227783a4d92d8509ef78d39b0168996859b65ab1443eb6fb943633	\\xa965d460e03aa592543a251ef7f2b9f2df4c29389771ee02dab507fd8ba00f87f908c42370f79716c7a271e2160a3b6278a31d846b93051b66edcd4d0cd7710c	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xfe7097370f26ec076317152bd33f3e25822fcbb8d61dc75b7f35c5493c0c03b55cc429f4a57dca9d76487d19b5a51be0ce1af88c240e1ad6e5535b37e22db102	250	\\x00000001000001003d12d996d29f698bab0705d82d0299c23e106cddf0e3f232b44ee4f489b92d10fc9ff897e0e0b890cbd805f5bb1005b025128bd71e0f44b698aab49f258ee21a3a8898a9e73a0e859b5259dc7cf5c00d47ccceaf2d8bb4dfec71ce856ce08c8e5076d31f6a4bc8226e2a153a7aae144998cc6c7eb91cbfdc13b5f4fe6d9aaaf2	\\x8263f485b4b5749e5d2298c2af64f4816d81903535b734e15c9007e0d0c981db8e0056c9a64ef0787258dd52cea9f00217189596692cf5814138a8d774c95eaf	\\x000000010000000117b2d01b15f69254bb6c711e0d70e5fa634e8fd0cbf63d9763931c01459d5b49deb2e0dbc7ec2ec4eea1ea68d8ca3e4a520ae60955f589e863f5e534e0b2190915406d1c544e7decb71e0554e71db1b791a9251edd9ab3a1499d3d498549023588aa275f19b41d0b37cc1392b9ac933070419665a1f93185a1a5d92397c610f4	\\x0000000100010000
2	1	1	\\x33be7e0079d4227be4c88b5dbdb4adc45e62032463c2e4f9e4ad8f7b82cf2d1f8938f24ccff78272a31ba3d02583070853c8cf37005c30104c59cdae823c4903	369	\\x0000000100000100a6158c44d5ffe3442d070a9892c1ae1202f5656e3cef98ebd35fb53a1eb0f012fc5e079797e610d912fded21ef34668ef79e3947b6e6f0179afa76fe8f376a5980bf931d451887590cdafb209553350a543df2f6b1487fad9543d847fb544c304bb48b44fc7cae39d24f8870f20d0875a14bef83788ca738f0b20fc6a93e325d	\\x2ffc5e82e71b7d357b70a16d40ca35e76710aaf0f326d59f5d36c3cc744f808998bdd1251be4d43f6c39c36d0aa64d29bdea04fda9a58e31b0cbc21379755b6e	\\x000000010000000158dcfea4b6bceba992a85159e7ec0e2ac70bd65e7d1e7781090bca9627839c8ed3a88079c3019ab4e8221936fd81fab976d39cc36bcb53ac012611c42c541a7f11e8fd558b9aff394c342a08d09ad20222d0aa254d0b87d083fbaa2a484e664c58641a43c2959ebb10395c99892fd424a79b62afcbab1d4ed22364f5c27b7127	\\x0000000100010000
3	1	2	\\x62aaa09bcd0bc62a54ad4641c2927b53928dbfe72de99cca2e4e884af667d4ca0fbfe766df7e1e9b3b8fbea21ac091709f2c73d6e2aed25e0fcb2fe6d3226002	292	\\x0000000100000100e34c48a4e25f7c6b66249cc55cfba1d60776a1d8e65d7707d0d62eb8b7a145a91ee0b61f09cfd162c613e6fac9235bbc5b9cb4d3f1fce4002f91f2e72fc2a4d0bae3ecdc54b0423798b24167d804eefcd5329605267c5dcca27eb572303fd51c1a552fcca42f52864c75769edb99bd74aee818e4660201360e3c1786562afcdf	\\xb6f75b8655aa84219da415345bc55bb6733c9b804f9728dcb397d7e975965c0f74a9e8819beadacb0669e380fb85420fdfb13b6ab7bac8e3bbfbe1e1088e3670	\\x000000010000000117872bc8205eeb676aa664a61b97230f08820fa6f25d6ad8af03863f337f5cc120177161bb0af2d71d03e1d1b71197ccc63e2ba9a1c33104daa2d4d754c2803443aad17115eb8d810959a9cb701ec5075876422b32fa7c445f324d8000c7048bd9ebace0ea93b037dacf467e7504e036566e95e413e93bc6e60d98bf739b1cfb	\\x0000000100010000
4	1	3	\\xf901f37f3f9680dceaef66c034cea31aa96bd46d3b946fef1d6ce9b3a54d3dec5ce251d88e1394d645388030b46d6b84c826749615dababc6315963260a46802	292	\\x00000001000001000f2c95dbd29a9c6029021c82cda44acaa756c95bd12af53b88655e30e21ccbf85386658e924ab6d5ef454efb4cb7c2b67b381eb693c62e79c0419c1354c73e87a064d618c40fb9649be631d69f8fcb4a407fb30617fa2e8ad94a0c754c657281d6ab74c03f9aff1fc6235ba8e2ee7fa354e87b0b150369ca6fd0eb412b66f6ec	\\xe1304fa8b526ee1e41d3ac10776014a469d6489a7b58177ecb39a9d8357d4d90333eaa920f7a002c5d33bdb458b2e9d6073d9c29c3dba2b31149a3e0827861be	\\x000000010000000111a82d5e69b6e03e29825d511482241cce025ddd572b779464f709c7820e5de5cca044745175b07ed7bba97a83c3a080ccfe0169e764189158f54ca79cd6f133dcec2213b0bddf38d3d4e52c0d8542eda694fa9164c3771a5db13e0799b6b0968f266a97c1b13e1fa57f741c1078049e2b7bb5ec5cddbfd8d7d202cfecbf24c0	\\x0000000100010000
5	1	4	\\xea1fb7b26dd0bee557930a33edefb9fec0a91983b3671dfb9ff753b218f7d75d5ad87e57b31b756ff9abb4f33cf6a2243e61562b99b6f5e91e939a44a78d1009	292	\\x0000000100000100742178621c43a0a9b8b964c271dd48b98070fd17e20fc876053a40833386935d5980662bc1b1ed8fe5b02643c7ae9dcd0da91c09d41e9fcfb9f3122bea6f38827155f441eabb6f263c02605f954f1bf646e878e07fdfda0bc86ebec9f22b347ba5d8709825a4680261658da0ad50ddd4940c547a35f6120cc668beb350254086	\\x2147d6d1046f2da3ce3e113aee7978b1fa65b72e3759e5511a7149612d5b84c47a4e608b00695737b2fdda9ff6ef781da7fb6aa4135b617dd9307b76034cd70d	\\x0000000100000001ec2953e0fd6539652888251d82b9f071440323284e110fada4a01cd039d80b9fbd3b66749ecbb62885c400eda30ddddaf5ba972a9864c7107bbe3f8eb2f5d790e552370a13757103913dcacf8e25e34b2208fbb111d1444f86d04cb89aa2ca91f9485fba94d0cefa0a406ded7210dc8c09f8c9692979e06ff315e653a616c9d4	\\x0000000100010000
6	1	5	\\xe74fa749a1c4bcd2f1e513fca8e2aa4f82035e9a29736b2335b231719918ff39f11a3cfdadc9d7f01a19fa53883b2dfccd0cba543192459f5a92576e10bf1204	292	\\x00000001000001006b6296d6ab9fec66fb66704eceb8e8bea261a580b96643861299df90d410b09e923e2b3c9ea3c9bcaf4da2248f14125749cf678ecf505818235376db1ec5e143e672c1817e895c0c39fe3c4b46f58ffadf5654c5145ba45c27459aaf499189a05ac85389cb3a70f5fbf2d2e80c4b1bc516d66a0906d6302d83d32a4ae28f8c0e	\\x8e7554e03316aca336f1df31a49da02ba1d5f1c03436bfdac5d8be457b0fc3b6f2ba3a6e0c5efa0ab42e81401656019c44cb2192486974916903ff85e7c9772c	\\x0000000100000001194bc41028ba7b61112e93747b33811bc040d90bf01e93172da1f5d59958b24f047d154185d9ee02b92c59052fb5cef451f52ab66698d61d2784c2cfa95fcfffe2ef255362879b5e0c4f14c045463d9b77b46a306b2998bc4cf84e455d6324029edb3716fe66efd39efbe075a97ba4fab93c9ae23111546b6d0f46e2307029f3	\\x0000000100010000
7	1	6	\\x6c18c24acc3b666ef8e9f3d3ec80872d29656916b5e9565bc2139e767b00b1245f4893989e6e71e48977bc1f01d04ee566383f433e0108ceed8b77f3332ea508	292	\\x0000000100000100a4dfeaef1b2af0ef25dd91a7123466b14098fc15f6fad0c8c65705e9084167ca2a0a88394ac4377ca6fd372d78a5fdc614e4aec2efd8081601774989fbbf7d5d4d444c7335d8d86bbc8ac179f2d1bc2f974b87f0f56f850be450ee392518fb5a87f42b2d377b6fdc629c33d5337ccc594ff0d6deee3dbc78006451255f4431f7	\\xb857d901c0b879b332f0d5b5157c4aadb18c217917178fd342a700d3922dc0bddd3c15929f7a318a3b8b14bae41f427e073aa76688064100a0552c957a0f208a	\\x00000001000000014d6060270e8715c96da60d0bcb735b54801dae9343eaaf51fc019c4a26f4e532c6d8bd5f46e63e3268fcf1ea26f19c4d23dc7d724e533ff9a4ddae44415e601edb10aeca77fc22be34ea41bd1d4ad78467940b1ee4c06c253f68e185ed8d32ded5cc7aa9216cf42ec0b76a6e9a132ffbac703b3058cc617bc8291d042e432b67	\\x0000000100010000
8	1	7	\\xd247dbe689ac194e02dfa29aa3126fc4f80543e00e13c77799da523ea79f3ff79cfbb3ab51f0f08eb14c8fcba7e97e7c2fb19f48d32073d336e554ffd78cc60a	292	\\x00000001000001002bc759a6e041ebfada07c0299b20ea39a58691969f8fa235b11316d191a64f8bb6bd5e7e473c4c630e52d0d2946b673b5fd9b6ab2f5d1ce8c50a925a76bbaba37e9ab881133dabb45d089f2793c12057bd9f1a241d38275afbcae36b1ed6f19e66b0c6a086ba3443380dd70ecd6355704571b79e68a9ec42c9e392446ae8af78	\\xde7eebf17783aa3105a45f53f1bc585cc0c0ff3a5387ad724efc9cab2261e6bebc248f3207378673ef036ede3b726f9bf36f65e154a7d8d2d17fb3d9e85bbcbb	\\x000000010000000121ac2e0dfd7e7b43aea95bcc6073792fa3c7fd8f2c326ed11e273044ea72fa397d9ea0e787a048f923f86f3884582736dc1da578d6b98589415826374ce39bbd6405e0dc23c86b694426be747fd846682fd3447538bb581ac279fae194e74405ddb71a9dbd951ba8a6a82ac765c7f566ee427275af1672b799f784a3e110ef96	\\x0000000100010000
9	1	8	\\x4242063207e82e10825cf8b8ce2c8838953185f8bcaee31041846b788dc736835ad26d16f3d2b65f60364d43537f45630f3dfc7485f5ba9b7e934d4bbb56cd01	292	\\x0000000100000100944baba5039ad2b58cc33aac8415459894fcd63e4202f310b06e21491a941a43fee1250aa5b6ac266ae4fcbc8e2f1832098e5ce714c6c65aabd83a42d473d275609c2cf131fccb16bfc9bb9d89b8f8f1dca7910353155afe0c13ba982e9cac52d81a583abad3a76021a8f4af9adc92d0350e5ef85a113fa584268376b40d68d9	\\x42e7a564756bbe5d373c1405d5a8cca7988b8fb68a0c3f1345da1a02a381f68912a1e7eb5c10ab0d6ce9b7f24a108aef032fefc40255d958b00dfdd081e02970	\\x000000010000000121bed860b3c2fbbec6b2e1624291d2e19c6aedc637257301c5139e33c686d53bb8979b9001b2acad5866c3f4407e1da49b31027acbc8980124fd6009e5ac1361b78e4149223f234be159e5d32497c8da2bf50dceee4b9d8bb19621e72e875eaa1c95a108e506ce8cb08f53e6e4302cb369fd5e4b15eac5a4a77d5ca04e4839d5	\\x0000000100010000
10	1	9	\\x717ec74ca114c33693fbec46085c5dfa3e08ef265dd6f0db07e3a12c834fc3928cbaf4e0da830fbb333cddd37f92c357ff1e0f8c5fb92410f44e7d20dd5b120c	292	\\x00000001000001000f2ca0e117684328b6247ec3279dcde273ad9b28e2837999a14cd68e11cd2c8fc317c68878bad9cd8621b0ff4336bc4dcd258689d42f619711bf5f39bbc5bdc57271b3453b2689f6a382267b61c2e3e1d7717cacfea4880bab57285f26d547841ad3a7253b8c6a1cc0ac44f4961230644c4e39cd69197c2b30e9adf1324555f2	\\x81b3bacc25a8406410eb026405bb0dd263ba400689020d76378dbb78667d3cd0aa3a131f879951e5c7c885d305f60e613f94709cc8c636114084f5cb007e650c	\\x0000000100000001906d5aa4231fba02ebcdf93778edd394767347dc5ecbe95436aa11be42b7494cac64c4e01d51304b62897e38cb6b22a88f640e584533a64a675baea980370384a29289272435c0ee60c9494f604a108956135763e803bd7365fc4d40eb0bcd483b67ba7dab84a9c9877ad35c66973cd4d274091e9457b8bd3b342be90306acd8	\\x0000000100010000
11	1	10	\\xed7c75f22200af0d135b4f692161093054468ed137d1a2e7a344b0a2cd2a8531bb67949136ef0b84e26ca54573b02132b288998f02d63c6a0594e14c8111d30c	56	\\x00000001000001002a81c2c92088f95f0862901ab0cd46a9f1d2754e5597bf9f8fdec43da2ad22755fae0526ce7fc74e702844d193169db8b92e4260ebfd915798269c7c51f755189a6c7041d89f9177a56021f6d7024524141ac951c2aa080cea25bab804015ff864fe155b96f982f4084abc9f3d4780f770012e94abc2abf7df167347b78d19e2	\\x7145faf926df8de7c8cd8b4aa4dc74d4dcb7863fdfabb7299adf9aa41c09ffb54046ff11adcb5c0d413c7aa8549a17556c36190d1fcf30052f49ad8089a2ba5a	\\x000000010000000197c46acf7af5c12d6acdac600f98c5fcec49fb2d9d9340864e2ede89d7056c2178963ae31396758060c0f22a416235a5813884bdbf7e9e4d0e40d9b53dd053d52279c25dfc78d13b9a125e0d9317f1d12bc0d7fddbb7ebf2d1c972cc72a473a0ce4b5b200990889d78e01ab86bba73cb0659524f40e37259b690327aee5c93fa	\\x0000000100010000
12	1	11	\\x8474364068663af0a3fa1e227a1d3add10b2531be840471272503370f663bf25e6748dfe8f349cd2c0d4e35679258a8942e6796d4cf67929f40b5979ced4d60b	56	\\x0000000100000100a02fbf72ce129a51aff4640ecfa19fe87d49c46bfa34c17fe7e33811ad71548349a63879c91220bf678da1947c403253ca238622548f200acce26d9a4e187150114a1f2b1d81c2134771ce3b9a74dfa3110ca7c3f47c0c46b327331175bf29d0bb579340dfe6a440ca2c262215b031bd03995a5381e66217e9917dd06ab19d20	\\xa60fff8e8bd55851be2d87231a5e3b81b982c6ad701253bf97d1080a6e82df68be7d6524f071d3d334522891c06b2f6f283476b3488583fe902ddbe5ac98c405	\\x00000001000000016eedfc8b968c12048bc00805f8058e224b8b3762c0a7abff14067a7bba95d50b3402ab4f18706596301e64dda0854b2cf4e0bd98fe425dd61b0fdb193dad22420ba2c0d64bc62903de56bdb9af233eceb1fbb6b81b13acc9fb1ff6059ea48257ff7df06f3b812cf1e9f9db5142c774b9ee859ff52cc51bf28f343bd3c7ff3fb4	\\x0000000100010000
13	2	0	\\x35bf10b7c82b18a9b5febc879751da5735b23f024bf493da742f9440724b4d72172c071a8a67c66910dfc296461c28d943de8b588d2fdd896c62f83a97ad6609	250	\\x00000001000001002c6f748924cc64042c337e0ae3e1bee01edc404e954278ea3140ba2eeea8ddee657328d473a440e8b6d5226ce3e67a59a06b86b6590fcd5af0bf1e3c97538d903693c365289cd3246806ab752dcf89d6019fa222e52197e3c7af573079116c5054f1fa8ffb82ebdd22b3506ba99e4954b532da144b8b5c9016b6b0ee9158f3b2	\\xbb594cbb69b82fb5daf698354e92c3dc28042d6c8ce4af0f51affe63f0b56cc50f74092686f0f84ca8be9196f3b9ea29279d8daef6bf2ba95e2bd8e907912ac0	\\x0000000100000001883c4d0a7c96b10d9781814da1727a14963f0f1496e6b972bb8673779a997980f92f742d9d123a6efa9055f14a02d943ce116a4108c2987ff43e506931f372772875ca9940b30d9143b81fc5f7235897c68fad626995cc0ec176c68ea91cb81c66713c5f6961ee109f4953dd9a89b5bff96da1a33b8416e982aeae1d638f4a8a	\\x0000000100010000
14	2	1	\\x25d80e8e9913e504bac5abd996e8505ff498082cf51c8e2b0ff25b52a06eb4fca20105fe29702c7be498bfddac311d2bdf477b56a1ffcb54ef1d6e6e08149606	292	\\x00000001000001006abfd4e39df662d5d4687f49992db654c21032bf5af0b4211be7743054b06b46cdad73602f7bec2f43a5e7df94feebc28947878256968b8a541aef6a2c6084cb58578e72f152a6a78104a7cd56f608762b592b9b37c9bd4aa1af2b5fe7d0a08281cd2ddf9e38790504f5c595b75ad63b8a015f94b5d99a1077ddc3deade2131d	\\x55ac069b0d18a4c05d2d98d3c211ba0e519d96629af25e228387134f5fce0edaaf224f546acd4bf9ff66ea5799c5829797c4cd935be8f7d5eda3950271c88598	\\x0000000100000001bf47bd2dbc4ba36f0f8a6c566f742aad40a4dae3e6315fd851bfbba8e2024c6bc3e0b613c98a4f7c483ebb53c4ff21a8b5342fe6c23abc1f7fe9e9710c3de6177e86c0ec5170a0fb66c5093dfaaabb45f04131775dbb78be8f21707d679ac6d0815db015af023d3901ee2fc9e410c84bc8575436e8b0be2113e58dfa7450151c	\\x0000000100010000
15	2	2	\\x7f27a0b1d9382662523980616feac5125df4f5c8e1c2a7ef5df7616b5f8ffc0f9689c1a0d22f51b6e0ef79e39cf81e8589840f616bc851f9b5083804f999dc0e	292	\\x0000000100000100343f2543f2a70ad84cb07002f529297991b461a817c9ba80c43d5673555fb3eafb006fb44808290e79f9675b315f1e1d595330475c531de599a23dde5ca5ebd0c6fd0a73d6c13c2ac7d48c7a1594414301fb17f51f14c757b6759b120869d071cfa7e20e19762b99ec3073452b64bd4b094aff3c8e20a6c68b62dd169f976785	\\xf05093f5feecf70c1d3f34f5a1681a160b5d10e68771438af28b0247cf1cdff98d9b6465485af59fd4ca254568a509fe4f0aa06ce2c94f61122c2f4247c5f6bc	\\x0000000100000001e6e5f683b8e381e46f9faa73af77a9c93023754108016af9b804ab64bf7e5e58ae48a9c3def8b1d5a832e66b42d50dd584f9737a9f34cdec1a061109e5183fb1a7fca4510f685a16ed2cb605332e9d2ac9fffdd31d3d6a33f613b838000898943268775ade5f6f64600afe300c88a4510dbe5d429790c13b70fee929888500e2	\\x0000000100010000
16	2	3	\\x452955fc921a7769d7d1ee1513cf62bbb9becaceb02dd640e0556e35f4b101c3f6fd9b0587a758c742d4ad773333e68ed2dbd47a9b45b7fd275859cf091f070e	292	\\x00000001000001000f2aa513187113753f45f1aa298e675374f6444b9bf89186ec540953a869658885239cb6a74854dcd1d3f59d59b148a04aebcf87124b18f599456187a71d0902c3a15a738f17b2a233583fc14cbd50051ea3146f9443994839dde7fb1da661259346e5b6f132b82c928e5194334a120a7092bfaa7aaef75fe2647160ff26e19e	\\x57bf9c47ffa0f2a8a71f6f0589ee220aeb817c7399fad79529e474d8e3a99d189ea0bc403616934a9aa73f10d4060bcf4fd20fb541a390984ff6f05e31ed3958	\\x00000001000000011916e516dc7591aed341964279329f22ec44513fb3b3a16d3394fa6f0f32afa5df5c17b9b742eb2ef03ac5c0dc17d7014764dafab77c38158f2a1223a82d884733947ff7f8c841e21f5b78f9071cac8ffba43b3f3811c2bf50c346d253bf6923f2e2f5f28e353a7aaa875ceabbb7824f08e5115f2702583984d010841f7a0f8b	\\x0000000100010000
17	2	4	\\xcf7b7413f710ef0b084adbacf0b274a7ff833d2d7c3d23c2793303d5cce26ca0617758f979bb4b0917eb8ed245990241ed8d161bafaf2234f8e811dff0108e0f	292	\\x00000001000001007e90a12ebca3e741464bea1cb43350407f9d2b5bb9db057bfc2bcc4d037095badc8f5ec5cd77f4f26b200a984f48d397bb04df7f2bc5bbc7f1009a2f41946464ab9949511197446809bdc1b60b6822ebe2115525fa5e8af92f922401ccf093eda5b4a5f925cf60564e384d9d15d25eae34f2d2ca59952c1bcb27b84f7ea41f2d	\\x3ab42c6f45d9e27d11a1a203a58cfc2e12da956a51a6a7e12a2196871b1ef687ccddb27d4b2792c0e6f464c98dba077d02a15cf07ae032994dbca3eb1bfc071d	\\x0000000100000001646d92e15a2e865fb72e703dd42a68c3003ecc48ded19958c6ff5c9c87540a8740251d2a8ba252f4b8d59143db38e6e9c4b893c255e0a8d9dd814cac38999feb8949db0ccd73f1e26b159efa933a337d6d804839fd5ef20f3d205f8752548cf0b4b4290d3188f890fbc8cbfdedbe5aa4e6fce80b816de2ade4c6dddb41aa1d63	\\x0000000100010000
18	2	5	\\x67cb38f7eaa9177ec261f20db6c1c6f21b0416fca847044ddbd06afbaca97bdbf63159193fddbce2e3d92e1c82a127697e3b8bb7102941b62c96f68345a1cc0e	292	\\x0000000100000100b2a2c511b2ca72f1adf9308f832d15b58173b2e03825913c06ff9d6a4f720109bcfd27cc92e4b9970e542aa0ddc1a71308590ff65d16c84f53bd57e005f3a4d2bd965a2b5744fe0e63c4ace475e0c2dc159309086c1a5b9382875bfffd8820e4dc252016169b96478b89b6acc42335151d2adc6e9f27ee22269aaad608fbb829	\\xe79fd07d3a3034f9e30119669dc9b7bbdc9ff9515e6311c3346393b08e9cd72c223008ee8e811e3d65fb1a1a58efbc8022d3b53a167195b5a3eec23dff863acd	\\x0000000100000001bc6e5739dc6eea141467b84d8c19a024b968718c8a79e025ccbd95b97039e0ecf750a74a3a2018a5843ad69364d8e171aa3f0c8a85abace5bb276da735005279ba0094a0881fe52df89f19537fd682323bc1c21c6207fb9ed490ca3d4db76b3e10124d46377cec9914602f6af5709225ddafe149ae4327d03469b65d965008ec	\\x0000000100010000
19	2	6	\\x0ddf34df168b6d11aa07870ab8415cf47e6ee148d2a9471d0a2bb17469b3737a2c1136d5c2a655ea383b54c3a0f0dd89707facf4470001d6b3fd5cb562d63d07	292	\\x0000000100000100761e73f46687544ff3a0de8d763ba643b8f0c2c324f8a92882d08d8399612e56c66f8d2f56ae50abea49edb7b340960372cb0dc01c62cfc53086cbde4e720e4f2a42e6fbc870f42e134f09517b94ec516a7cca34bd81427715b59a90067977858ca5753aab896669ee9db758f95487c951d05a4f400b31b759e6dae16708e331	\\x67a49fc391c9be46771fc14e5dff33104f48043bfd43c1a5460e1e6aecf70f7e01dd2fe42d72f7cfa0ac28213dbbd375cf3f081f66e00b283e5c9dee91696a5c	\\x00000001000000015e51405217bb563947ca7fa9a8072099f42a85aa73b481959a4d1125dad20699903ead8f4771ee4d9c0ea2e9211ff5aaa7af3e5552969c044d80a33a545ec55b8f7e53cbf7a0c920c7c1a56699cefbf24bb01f98f52f1da7980a900bbe2bc1c52dd23b406cea7ba4a188cb9d494f79532b866e87ce301a1180f5fba558fc3041	\\x0000000100010000
20	2	7	\\x182ddecb76f7002e64a8417e66e58766c73f40727ae08d1d6e3855196433cf7884b130ecdfe980b63de0fa7b70ef78421dfdf01340e78e68cb99c13624b78e08	292	\\x000000010000010029a1aa1ae43257a634e265f9975f03441211745e5d94c97f4fc3dc7f06733dfe9c706225c3b3576fd9db34aa0e597263205c4775d46e943d8d568bbd2828d929224f8d7ed18fbde910792ecc6706ddc8b6fa31e914099382c2e397c2d7b7ca097bbce4619851f568135c354d78c23ea86c4df4dee8c46e8d265fe5df8cfa441f	\\x08e967fb20783287790869acbd3701a9377f2b974451ad5ab65dbf0a3c0f73a54718b80007e4d1aaa3f14f6e81bbb9171435ddc4fa5cdfc88341a28be07f7c2d	\\x0000000100000001cbfed505975c542c05ae4218cc2bed31184f829fcaf7dc1e9635dcef59460f11a5b167dd4f11c13096bacf6501f533e811cb67c293f0cb00d484b05c78cc68a8f5c2b9ab62bdc4ca0b2f472ca9cab7c8aa95d3cf1d3f6968ec9124d7aa0d555f56f943cba0eed7be5dafa607e84f6a66d9e5f45ed5408b87b6715354e06d7e0c	\\x0000000100010000
21	2	8	\\x6b2191bd8353fb7348c3c260fbedf2dea12dac93a42c75005a7c899d0d8b9b892156f721c9fb0b32e27b4a52aa7270472b9421cac16e96e39ca3ed276791e108	292	\\x00000001000001005834741f15e1d74a8746ece074a195c125c48240f09701c19ec59eaf4d4a76a2002b1106f37583e19318ccc50e7d262a12eee02878a1690e7e727dce9723423f3a64d54e2adffffcdb8c1ddfa83f7ad9e676a465ef73be6a5a2314efc597a9fc5696d79a2a4e3a4e9944510781776e5f826fa3e88c22ff21cddf480f983495f2	\\x77f958e7f8cca0ad641619ffc2a0c5df73e7a4277e681485b07e53188eea5f514b05aaa15b86a6476f16a66137241e5d7c49d1ecdb306ab211b9d37fbb0dbc10	\\x00000001000000017ec3b47ea272b5cc8fc2832fe00c5ab4374583eec85811495e5ea107600b37825609feaabe6558408458ca51810d0a63152514a6505b2aa882225f4bdc7a4ef3bd5c801662515d773c196384efdd340d01c1d7a1a21aae6c3c2a196256a6802febd26ef8aaf752670a45abb1d461b96501a3e43384eba5c63f3d947dfe552d93	\\x0000000100010000
22	2	9	\\x894762cdc90d1c3aac1a19002ce47dc213437084f08d0724a41531dc4370b5167e5f22c43842e9aaeb826042b238f91e1f70f001befa17f17e822f157c3eae06	56	\\x00000001000001007d6e7d4577d6e8bb287fbc2568fc8e36ffd047abda707c54dcb6eccbb78f45d72c223e3b53b19acf4d20fda0717846cd38da5df57a4be5ecc0be4e32875b5ad08ad32210ac125f3cdeed0e3a5d0742d70f267011a9f3c8f8b739be063773913d3a82b5d4658b8313018108758ff07f41587db836b28611e2a37261fa08b323a0	\\xbe2bc79f385352857aabf5e35b0087bec57b5606fb6567ab6efc03c7a9c809312709c9fd40766ff9ec4ba9f6f0b69b1f93130497bb133456886d31d622066883	\\x00000001000000013193735cf425856f1f747ee38e754b7e516ea52247ab26c09eb0e1bc0c2473d88fc63b608caebe81f7bdf24e4778028b9417d2574dc3f977de3971292531dd99547fe36b6cb3a854bd1a6eb622fd8add84d2ebe64b9289ccef2464076ff167d002c0cc537011040d305178c51b65b580dbf4b8b5a40eb3d1bf9a35c1d44773ab	\\x0000000100010000
23	2	10	\\xd82e9df62207aa1ae7a90914cb005783439a6727cc5752f7fe00699ecc8454712341ea7409aba3f2324134db30c35dc039aae952202a5f408ba416a7f2bf1e04	56	\\x00000001000001003c24a58300bbab24bb8187407225a7efade5787380e4737e525e79a4db30fa66a923ca97456837546724d0a77a95084afc2cebb49ee5c8dfa341aee7543a7aacd231567e8d8ad22e5d526ad25b85f8f6d27da290fec5efe1f9cf4372dd12daf06daca10fbce3c0e6039e7eaf9af31011db96aa6ad504ad99971a9553550826be	\\xe06c929fa93a3892645816239795843749714bae11e96f499ac8a15473c9a72bdab41213c9c27eefcce297e8890d9a1658d620bc177cb4537c076e5f13dc8a53	\\x00000001000000018870880abd6c90691dbf2b337dff1238412d90dac84a70307c5d72e6b2a6762738041fa31577a8d5dab4312ca20d7b0319478987b9cf9ef18c604c6eb14eff63a74c442486bf110fa1c096c124b265e9a16c95bc7de052e667c1989d89703cea4590f33653a7ea07339f3a022659bf85602dbf0ac46a932d1dcf02c420cb7823	\\x0000000100010000
24	2	11	\\x8589cccabe2a948d9b0bd602476b25cfe1ca8276912a6e11133c89cd96da2bb490824007fc771729a852036557ea98afca11cda1b79fd097d465bb35a26bcc06	56	\\x00000001000001004888a6f36688aebc98de937c24f251a668137b163fbaa971fa991ed4b3225b88ff403f6a33f2472b9d0ba9d6db5941a423e508d775f10202ba45caa450d538349244513f6061038b61b9fbcd29a1ae28dfe099163b94dcf3eadd6228454cd31265883388dc68026fea8a7fac29e4652b208ffeefda1d6c20a6cf0565da100207	\\xac4d59eba4f2a6e892d03236f77a517b684fd51472ca86783d4a846161a97fd8ff0cf1e31bbc0cbd522596e0acc19f31d244ad218e45533ac5cc6de57939c1fa	\\x0000000100000001cfe627d935e4231f9f2689f8d42f028549d2aff848bbdb319b0ca9aaccfbc9638f26660b93f8b78282b6aae7c242a2f6778e2633e0c545ec9d099fe3c897ea32701fa03f55de9a380109a2df8970d073795d93e533198d597a3c942ebaa3680390a5482bade695fe9724b13cb7a6740afe961af32dfb33ab419f51099283286d	\\x0000000100010000
25	3	0	\\x5c6b8dd058d6430505f0e1a2c0ad4633c12812b98202f21f90f105446a5d247582a3d530de2a0e97a40e35566159fb368f25c6102d805fed9ffef581139a4a07	190	\\x00000001000001003bd6c2c2c3810d5db51e6ffae1f7b2dce8f756d286a890f71235f21420e084338811d5212501cc516a0aa3deca122427304879d21f3898fb16a2da6c24cc705e4616debefdf2d3c9b69146c065d49acecbc5166fc7fc2656358e7c418a6074a8de36bedd2c46f3043707365aea1f4633c0737088a2b2e2b17e65cbe84bb294d2	\\x0e99b0d6b5ab03746202c3f9b24e4e162f9c53fed87be4535bb4ecb0213677aa28751b588c37b0f652f9eb1cbe2f4fee1251776dc3972f3a812ab261b72c2f79	\\x00000001000000012d68ba7c445796c7f0b1cdefff34b590641e22fffb8e34e26b49cffedbd000c9cbbe4eb88e0d7bda032ce5e5c9672d30bc0c9758061b8a6397048f0d0c541fafe0c1fa9489bf2de7608f9b569d7b98212e41f72508475b584b2212103a6d1d838bc01b14fe434b13bdd34aa4781159ebd3f4c0fc9498ab2f75ea03cf4692fa83	\\x0000000100010000
26	3	1	\\xe055f4574efdc0334e859cce8cb65329cf5dbf5b988f85076b5655408c92f46dadcfebea09e701bbc8089420b30ebde9fc5dad583d8ae526e547ee77ec04df02	292	\\x0000000100000100b08a75478b7ce73d422ac702537f47110bb40b2a4918ab8b945cf7159f430304863a5ddde36ca4aab9929b497f7bb00b0a4e1274803330839876cfbda302add42452b5ade662964e29edf385adb6ce8f748596b7265a29b87bc6cac9795e0501c44c6f6ad3d8ed97489083fc57f3e72ca0fac98620083262713767d546674c04	\\x37fce2bacb623080cc9795a3ca023d4a9666743f45735b1d503896628d563abefb424e2b37bcfce6efbab786f591aa1ec4f1cba6095790685b6b644c8deac816	\\x0000000100000001d00c74731804aee3af690a7ea1ec33750dab9bcfa0c5bd31dee8c8fe4786bf4b8f07ae509e4dc860484edc18dbfa3369919d109dbe863b53b771afb74f4506b0dc96e79de339e58e11484f15cf6a8f722518404d3febb496636dcbf868057fc515e11b3bba81a6e2e36eefb11159b5bd0238d022ed03f9e633cc779f472085c1	\\x0000000100010000
27	3	2	\\xa8ecb1411b606e2bd0a2841e45e9d7199bed0319e550412ff364957e30a2e23d2955088a58c27e121f430817ce9833453e75248a8f22509b95808ab9926b290e	292	\\x0000000100000100dcea3bc83128af8ee8e6c07b659c59fd729eb04ad480ec497adb8ac1fe4177b4522ea282798ae0d178aa3afc139be507dfcf692a70836c5f6eb02a4c2fe5629d4838a40c320c79ad686f104565dc00c71bac901f1ba43dc80da2d958d11bd11703c6427bd7f539ac9becd58607d4883483ae8ceb63f22d478b2b7ec2b2b6dc55	\\x78355feda4c464a9c56cc00d5e1eada7936871508ac23ba6b8e591b2ca7f8790d4093d05951a2634270c3cc71124a936232d81111647659cc247647e6d5bf7dd	\\x000000010000000143467e679306dcf2eafa44f50673040fcac4341d6a6019b248af5ad4c637dad60c270f7fdd84c79cf8ba6a534fbf4a574909c51cd46ee0684360fbb0dfbfba3a7c61595cbb03f5ae358f931571d87191b372fa471f97b6f3f07bce8d09224b2dcba831cbf7df5f7365e1e95eea2ac9e69edc54d16c0768b0af81cbc934bdbbc8	\\x0000000100010000
28	3	3	\\x6a6c17387061bb8a05c6a5ac2d8c1872f0dde11330ecfe3a16af662606bdbdd17eef22187c7798a660481632c79b68c74db8eaf0f8f9c32d5917ccded2cd9d0d	292	\\x000000010000010066fc70fe75d757db5d85cf020b49cad4b16333498c7dfd795ae14d8630df9518a9a3c105442e461febb2365582534cc82c052d36502944a55b2d0e25228b7d76048279a74a77d5368a056b17386200f831dba983f7fd84741cd9f6d8e88f5cf961f2ccf0422a3c9cecde810556e55b04e301b2e511bac1ebc157eac983225614	\\x1eb5dcb44368824447d5e396a734ded9adf8bdc8e7e56652b3ed0e10116b237e2c7d7ffbcd14f0452d10bcf8910aaaafd7e825d7ead004d28aac885af8bf0bd8	\\x00000001000000016c16b13045a6f06bf66018455093264a2c0e96da1a51a3294500d17e9f079d6c877cb51b11e24c4e565385652735e1b7fa2d167835b2d7d144e9fd6f7cbf6fd09427e70472ef5d5ca3d9f9b27d2fb1e6deb876b18f7b9d4dffa53228a52c62ffd165f6f45b82d8ff2061dbc33c3245e63f9be2b45e9a0e7ac0a585e0845a23dd	\\x0000000100010000
29	3	4	\\x4ccd2ab3d9f8eefab3ad2b0a5eb9dcff5053514bed2be5aaf79f5fce3611d14c1cb189e11964208f001431021c3b237157d32a419fb097a1d5fc078f6fbea005	292	\\x00000001000001002e003733a67f45189f6458443b94ac5d6584d458845df787e65d6f0004a29c72b4c62b21839c362ca9ee72dac5949916c2478240934ec932debdf1e6c6f0b5e4be02c6e4a82d3165cea44df5700b07beb4a81c38c5259b4e7df812a558299a6b6331e60f6113b6a1f957f847395b1e08cc19326c8169116cc8f819e3f02b9e6c	\\x69da2d769da70739f94635273d48c75f3b112f273d770d669b6b4d7a822eda55a831e36241bcecec752195ac488911333a0e5c929989f52ee90ae61cf302e57f	\\x00000001000000017e9ada932406fdd07784efba2bb5c0e95f39c587bf4b5a7ed67e0d8887600f637c01c1f7f6cb5fa1abccbdf3dad8acf4e540c798b9937e577b3f086bbcd9db1f654ddda9a1911f3cda16435db096072750362344777832573ea2b1c3278782764b054f4098cc40408b69d51c12c3ffa94ae18a009f013d74896dbe93032dd7dc	\\x0000000100010000
30	3	5	\\x5f1f5a304e787fd1b97e83fc0358ee359834592e1f3ad8542840e1b521e2d76dba3bff60b5f5a3a78560183435cebbae53ca1e05a28b9a478ddf89db6169310f	292	\\x0000000100000100572ee50294b2957547cd38a7ae99a7553c3da3783abcee08a40048a391acf2e1661621a70f13ca72b5b1752d6f0ee10dc443152519a424c3a5f3fe31ce54006474c066305d5e1303f205cc2bf2996952818f628483ca8f37928d09afcf3a0e5dfd26ed5db8833108ae9b8b9b236da469a0cb3484132a82fb067ca1b0a13d993a	\\xf10924655dd8a1a5f227840677bca7679b025da931cb366a70f8c0a175630854b664210b3144e43e1b2675694da8adfbb60206a59796a95de71ee39de48c1711	\\x00000001000000016baba3ddecac750458a3e7dec7af47e25c21a6eefefa8807491462b31028bd0f94ffcaecaead288c46babb92fce250084ad1f5ec6b08f41ee6615814e345ac88682f1d4813447abff7a5a372a7f3b1a6614e4bbc0d57df325ad1944908a5104862e6c9a2fa45db0da539f49cbf78d29bdbf806baa1f244142c0f525dcc31f5a9	\\x0000000100010000
31	3	6	\\x553d7dd8db1aa8a5c5970c3a684cfbeff43face10d8c7a143a58539c63d85d26a64e90073167390d71bf69c02113db0ef0a25b362bfda5f41457520ad07eaf0f	292	\\x000000010000010021cdccd67d9d87d94eda7987579821a31b67c57bc790497d0741695258859cf13090fa4a2c56632564857581baf6addb320c764c4ee0ccc13fc4742d41abbb7700e87debd7dd58233c1852e49a8c468a48e41a30d162d16a8b3f15952f2f3bb23d5a64ae6e06ac0133676dea7201e376a4815b797bcba42a6c62a00becc55af4	\\x6aaf9e34b08111e07655e479cfcee68337a3a607b391546ec94792a25464839e1d5aaee21d39634c8b94b9260bd0c8638a05d1298edc2258e1fdad5ec6cf6f0e	\\x00000001000000015274173b506d1a9b4c426f2c6339e8c9abf0a19737ada83da59cc9bbb964b80db2e16d6d4fc243dca41af9d512f465f0703da081d507dbfdb4f2a1ad8f76891d9c585303095745e8b505bd38dfba5731b82c060bfc5c73fb7b592eb637ec042ec879318909bcf0232d25e5030661c353f4509cf234e20e24ee1f0d9df2d3f6d3	\\x0000000100010000
32	3	7	\\xb86233fe1613fc6b3564d72382b07456838ef46005d954b11f505f7508eeac9228243b17535d79ecf2d0686360594b0db04253f1c4bbeaeb1b22f5b20d2afe06	292	\\x0000000100000100514de95cecd94ee74b5b271cfef8c129ae84e0f40b0fb2b85d72218739252e0fb2e1e5120acaacb87136136a2994074d7f2c6384fec0970d615e999046734297f884dbae51be0d31f61ba275ff80fc3d52d2ea967de631f1795b94ea983bac8ee8f845c8ff55cf39709ff1fe44e4eb4e9f6553634835e52a862053db02719f9b	\\xfb27047ea76bae60eec661b3b9c633c77ef4d0131432de20d76cb2431c71792b3e6c0658c76d72b50eefadd64217960e4a1aa124e0be079b938091445dd31a3d	\\x0000000100000001b9da2daee5fd250dd11cec3a7ceea135d61a8ca31af325b25b1d1bf5052e9881c338b5d848e4087cb4b6dc6c603b6615c0c31267537f0502afa7f07672c1084b06695066cb1b9f1a124450be5829ecabcd48dda50d4c76ee2729ab27fd3d3fcc3cd2216c1e13d0ca4728e2a97902c424864c8a39366ef28291dfb1b1ec09538f	\\x0000000100010000
33	3	8	\\xd61f8cb78e1610adef73cd3aa0d4bb424c08e92c6e4f019494e1c8cee31f8154834830b6d69109d015f76e5048e14e01b6a7c868cc4ec4ef0e96d1de8774ea02	292	\\x0000000100000100686cb3bba4d8e4819c5208189a4aabd37bc9e684e897bc5238b281684fa7bbbdc8a6288d6f2d84269e5a15eb04c6c8fe17389c057189e8d16825e8320bcbbd3bafc7776d170cf26a8b42dc7723e0130e5f459b4a6e85b4626f4b69ff10870f0924637ceb0a9481f6e87d206d5370bb77449a94fdb74e2035295defec5130457b	\\x327b8cafb3c9bfff626d9c57609030b5372257b2aeb04f96d6e7c25595d67c8ac287e6f46bfaa812e424935f440704ddf92ec8a148f4a5c63426b89bfe8395a7	\\x00000001000000011338602e648f8097e45d9029afa2dbda25531084af5c0566b6bc6f9e26a33d93154cff0390f6b60b3f0e2a88d3dd28d87992673a057a6461136639ba5baa6418b1e9dbd6de08c7dec401d4e7cc101aeffe8b3e93f140ec9c67defe2079ccaf4c5d947f8fb95d3ba45984faa2e45b2969152fafbfc14b05952a83848173f9cae9	\\x0000000100010000
34	3	9	\\xe4b83d990600f39d3c45ffe03bad9032e5dec3ab87214ab0900134c9fa3ef7aa6da8cbf77130ba56f06a785a8925704f1a36a4d026f692c53bfe302bd0ff2b05	56	\\x0000000100000100c140e609deccb8928795e321ff3ad655914d66f16e61e611286df36f77af2f4404406941ba1653e4e975e91c70171707d5bbef954d7f545296d530884895164ccf5b29811503ad45cda380eb17ee9ead351fe12082b3ad5056c5e1a0eb9aef727f1d686f75aee308477ec9c59313d938cc13ad87f9127df7725b3288cbf877d3	\\xf9e18c73e02b96910730c8b994c4d4b972a2dff432183fa2e8a91c3e2b73943a0c6bf4d206f537d8a43a88996421b66f1ccab9ab798734a223230aeb910d76ab	\\x0000000100000001e00bab4e3d4724ac706de70969add4dd1b49eb752aec6d505c065414a742008ecf9dfecbf23e4efdb3a83e867b80e9722caed36b6d304e491bcf2376c656276f3f7b9dc746057676dc7c856a773a0bd1cb3075248d18485396ff5e030c55d0e2a4a36a4ecc8b2f274ca79909d0e2616647da00873deacaa25fec1f1b504de96c	\\x0000000100010000
35	3	10	\\x63cf09e93e65a2caadbb4247580cefb0e327abe751632d13d97b7f904bf86bbb7e1a7b6b8efb43d9c1d68a68a0839537a3372febe68304525103365ddee75903	56	\\x000000010000010006648d9d7061382f5b0f8bc23b79b8d728bf1dffce1adc4a4b97165ec2eca354c9222d4dd2b17da249be94113f86278ed5210a2722aab8ea5a13da81ce52eb01f7d606bc20eded78975a129350377ff6dbc62fbb26e5f1efba069eeeefcc5c76722c48b5764e2179cd91710324b762d59c6d8a54e9673cb249cb8c0a95f18f76	\\x5e820f2ad96fb3a9463f8732c8d274f2f8305c1c931a36a80188b774f33b30776d9f34f365a1e66be41f0c1047808c7c7248fd4ca7c3125981d499bb56b799c8	\\x00000001000000018fa066892af390c379a734c87a0d1161853e4112b733e4618d795df0fa5902a559589cc80ea8ced6d14a1ed85a714f2106853021fb161e535b3238cd626549e0a1fe9c4b539a498db21de945f4f58dfc51898fca0fd421dca8ac24e864965b69d08a4bb5cb88a9f472a495791a4edd24a59b307e8268636d44d2d194edd921ae	\\x0000000100010000
36	3	11	\\x2ec4579b3bb5fe47deeb9f349dd1d61c4eec998ec753b413e21ed128f41372981d2f71c75507fa04d2b3588bdd289de3d663922dd22a7f275049511b3b949008	56	\\x000000010000010058db327cfd64f71b883026afcaf6db8ec7f652a814c4f343a8667d2ae98c1a7867fd800a9b6bd86804768134cbeb85c443f6d0c7bbd3bfdd7c380eefd7017af4d293ef357be317c4d091f3b931324a5120a90708423e48c6f12aa26aca2687b49c39ab260cc3b4d912e0e07cbc74d333b87d37f66ee726d0309cbd483fd2c779	\\x09c2d8ecc6768a946576dcf2ebefa6fecd372875344a21308efd92d7a957378f82027af75806de4379446c8903ee2a53114d6c66ec81484cd76204e1d2d8af26	\\x00000001000000010b0e9cb0c13b31917f0d6a4ab542403d148c4e6d79421b9d303fd73c5456f98538259f8f57ad23b2c72eb42e9605fa4bc2a555eaefe8c3672be45006cdb1237a61072c2bb9e2cdb174eef8989bd24a049a8af9184a27fa85252919a3581c91d8e14888355b3398c202e799f02f505d188fa0c5c936ec415f5b557dbbe327c952	\\x0000000100010000
37	4	0	\\x425c22e4f707db6d9151b07c5886ad1eec8ad2018900838a01e9044b3ab54b118c79d5da255c5f17539cd95d21033a2d7d38f56b3656bb4b6554259462e5750e	369	\\x0000000100000100d572ec78f32975fe3888050e647fbf2e03db8d533542d773c6a26c0d2a4d39499eb20edc5511c6fb2d4e275dd10dacbe71600d7439e6a90112875e8615e94320cbf58bc891706d36c0da8b9ad2fd0ed6ffb2e77e8a9b03254b657017750762a75908612152af59e73aaedbecf843a7bd5ed8384a9c77a14d0a94e02c292c5d67	\\x2a03a787eba7418ae2a49346dff6252b96f0fb93140fedb6981fe53c1e69a12f16f642ad1ae6f23b1855dec8305eaf78823505da28affad51f65b8eb0a292555	\\x000000010000000180880cc08d5f7f38cb240c1dc12dc33130f1b211c49df319738bc8d5af151a4cee6c7852ec8423d899c4e585b32605fc429b9acce7f15cf165213900a2833f110db3133430915e6c9d502203e122ac2bcc6180ec44751d15e480bd254b75703af070df17173ca083b3c720d6efd902f66c9e5ced65b0aab8aeaf1fa5b8d38f92	\\x0000000100010000
38	4	1	\\xa95ff92d9dad6774f103dca5c9497afed8da70d5542f8f34cd1dd42fa299584b01ae1ab7b6914613cca23fc67884838355d9b20f5665fd0219f003b3b8681e06	292	\\x0000000100000100a21c3f4e49b56bc401de6652cf477c709372815d707e90b6959e3e10ca146ea8df3832a839e3a9374c54ff606b0fffa6c6cd2d78b6f9da4f12265987d49627dfbbc1552567414699bc6e5a2451bcf89e3528bcd4af74e98e6d181362894fa2578f72c8e937af47db4692fcbceb713d26e9fbf40b128605facc14d4bf98770572	\\x6b23e1aded841a856ea0dd4ad37fde903569bd4983560a9f069764846e118950117a06dc55c72e3234081300cc002fcd623d0b0fd2b71f75f2f828961c6339c6	\\x00000001000000010c9f0d69167a0441ebea73468fc0e15925b9716a644db6e25d6c082bcbaa121e42924b1d3506ca17fe0d4537db106bab4e5a92b3e7a3e3a6f41dc4a8fe97f4e9e84ed16c607ea83cb5a3cbd050791d812459ce5ebd11f996a11b05ade784b84e14e69ea1c90b8dd1f822e45a02e25030350dabb2c741014daacb0605bb5ff5c4	\\x0000000100010000
39	4	2	\\x50d281fc7406c8b7de5a3e3e405f3db1cdbc5f7f0938c8d274ce4e07ddcfd2963d27e607ff6219e5aa3e1340a8bf80287fc44c94c8c5cbe8ff8b881b4192ff09	292	\\x0000000100000100b5bcae47106cc65cadeb8f12add2c3b03dd75b34c964a4d34aef6ff9ed8e3849f210bdc21bb632b8f3783958e36647799d6893d50811046d556e3d42967c8b79fa399adfacafdd2a5e27a4e142887405fbedcab08e12da9041f997a01a6d451d455209ebaa591281a2bbb4b853aacbd88989ef990c8a2e6d48af2af975d9419f	\\xfc1cb9a8e462e254da10cb5b566ce3b9f03dd906312905b155f41de1d5ae1e3598fa94e7926e6175ee9c87791176d3208e736ed529c1876d9b3d7cbd64328c9f	\\x00000001000000013d8631db360ac8720ebb4f233229b228d4da8a8d0e5354454df75222ed3d1572b68e1cf3e450771f398e9f8ce19effa141b8237981d060c60abd77b91b77a80b05f21acaead5716cae1eb0e7acbebbb54c8b6dd93dd870b7cb186f99490fd71bf8f6c4c441fa4cfd6fac7190a11a320360c01c1fce51c8f09fed6a78e799c8b0	\\x0000000100010000
40	4	3	\\x2d7ab32fd7e73944d9680ed29b00bcbaf9e1f7d8a8286634dbabcce0d8c103a85bfad98d9a4d35a5f2a416a15fc19ed22fa1d684790bb68437cc4e4b665ca300	292	\\x0000000100000100a8ac20edf8b71c72960c3182ef85e6ce7e164524e40be485902b6b641d57920499a451cb06b12eb3de40f1ca8dff204bf0b9a48a64532f69156640426de1a317678f1b0181e6e207ff17c561730d567e42e05e37fbb1bd979772dcb7f6bd6a7edc7320665a08176f845e069b96911c49e21b63a7ceee281eeac05540faee2b14	\\xbc0ff705102e00bdb3fc0a37239bab38a12581162701177cb1d225c9dafb82961de93426a39df99899a1052a6aa44d008ba4c5a8d6ad957f8cd8b2c6d1ea5fe8	\\x0000000100000001b73b3675a3bce9542035659181e082807411d4cbbfe9eafdf174eece3f584f037425be97a02e245569df25b10a0cf211447bedfc8dbd42166e0f34586579696fafa5223631c15dd083aa53820913609453eed13beb15204310d928ee339c57ddf78276458754042dc3694bec8cf4e5fcecf9c393a91a6d1a2ca3b70259d70165	\\x0000000100010000
41	4	4	\\xbeaf6889b34721d79c131e0a0157792596ba2e21457e9457b6f0b5975b5e59c829b303800b7c2882a697e0ccdee2a8f0d5b3db69cb8881b6a184b2690a4d9d0d	292	\\x000000010000010069d9a446a979e6cb247ed7ac2ed3a002934f07726cb3d203a22ba65bd4ecb8690d6f331e1f7031583936eaac5bc1502d23dc56283f16a99998f27006a888a6f465499c573b393230e1b1c7f40a9df0c93ff0edad45b03c5358202f139c8ce6ad049136f3d9a1b8e9bf68583c0d5a21908cfdda634815598a84be3fd1dffd8b85	\\x7418a1ba33c9c0010669682d079a8ab805d9b8dcb54029a1919a59afabfcee7cdd37c4a57996f7e68573d28e13e7e6808cda9918622126f6045a39abcf99a7e9	\\x0000000100000001353f8bf5ed31c326d48a52cb98d271408916ecd1a9b296c9f3dd9321c43f6eefb7ed9b99cf806f794fb76e540f2a680eb197de91a95250b22a42e435ece107b018f37bd4277ea3e4dfd3cb206f65cf998198d3ed860b95b5bf257929dc816a9a7efec3b961dc5a1bd71f4f9e8c7cb477670b9868dcc9ec30924332f2d20498f7	\\x0000000100010000
42	4	5	\\x4fce9716aac2f3a621a6ab481911460ec98745d7befba40143ae8e7df5285dbb682e880b74aa8b621f60c4824938a5415e8e384afdc8dadc48e4532f80ebc409	292	\\x0000000100000100619490386bba7fa9021ca2af5a92a17eccc18257a58a642e9141eed028945955ada3abe3b134234412cc136c84880dc2b80b5917b309f0ad0ba55cc4380c76bb8ba2ebe7c0e8f961fb291b982827476144850fa87b2f6784b3b2edaddbffab79c74c58bc9bdd230e463212bb3c11050c17b83f11be76c4b3b439cc938a8ed386	\\xf1c69fdb391bdd5e810964be17029ab7baf6d37a1d3eca22fb3cc2e116906202e06508b68e9797573b6ef579ffcf26fdb6f883a1e4a61981ee849a6535a5fd09	\\x000000010000000131808af1194a5a28e83d66802fbbb057b2ae4d9938d3a80cf7a91aa376de3d3f16a68029af36b7f7bfa00a8e7560d64348f835f5b0377aeb5812570ce6900ac0c184731f92fc9f64885e9b682fbab4bcb41e8956484ba8d5d5c7572025c3be4dceafe8c5f62257bb587811fe2e1eaa64652a0205d51b781a44a1c4cb9fdb43d7	\\x0000000100010000
43	4	6	\\xb7fa3f95f46dc6f1b1dcf59b79edf28aee6a7a25fb28ad035dff6eb76277195a7c9dd15dcca408da56ea9ab0573bf75d4211319b5cfa865957b6c69062cdd90d	292	\\x0000000100000100904685ba448e5a6f6027b4de4dd86e959976f37cb1054dc01d92598e434cbc846f403cddc1190e994f10a2ea9440a3debbb50c15af3f3107babc6a314e35f38fa527dbaa9bae6a927ee157d424a0fb6cb52078a9c21ec1cb5d073a7c9b4e6d8ce615064885dd3da97d00798b182e1c45607cee1fff36ad4620a1ec36d173a88a	\\x2562d084f98639de71072ce141a60cc1d93b5ef864b31a7dadd4d0dd85a70827e7961f5639d609fd929a131ef152bc9484bc9bed0c2b8b092982a55f3606f985	\\x00000001000000015067f4ac39494ee57e51a7e043a0744c57aaadddbd907e5a7e7a5e79e08a5b3cb25615516ee05e1640c47b17c550a8b128bd4fdd7d0bd9b2a2123db9ca0eb32b59d3884add4c845aceea7570113517cd3d8e0bf6d1d823c872db48b190c6c180653fb429a24b206406c6d6906ea423fd2300708ad076b58037bfeeda92342e20	\\x0000000100010000
44	4	7	\\xccb1ae7d5a0d7578afe40efb4b85d98f2a79aeb8f603854ab90a7e0a232757270d783dc670222cbcf336e5877625b3bb31f846d208c884baedcdb91b3e581108	292	\\x000000010000010066f3b0d317c9798b6d48ee92134b9752416d3d24258797790068e3e672c0a521c2bbd0554f914d47b8bd1b784395369f66c259bccbb51d336d7e8c1f80a84265d4b11dc991435554528eff089b4aa7ebe447ab56cef39955ffe4624cb21fbef92f03a0c5ed000f129935c1a99fc61a8bb28cc936e0e7a2c0a252d62c48ae683b	\\x92edf110846918bfff8b3b14f6bf7d6f12ab033a0f2be9ff09823d41e06d025dd6ac3d2c72d486f13da779b516c6dcf701669337ee8cf5e71ab6323ddd45d29d	\\x00000001000000016837a3f128e7fa8a26a7f0db8b1854d066294cbe3831a3135aa4b5fc0850505cf33b824d122660fb5d173a607a55b67703f8e75ea7c80eef0b22618ac18deddaeb6f9b4f847502a010fc0af40be6ef16356c64086e3d3cb6f5c1a44f06b339d20e584ed02a0d6a7151502862d017f555f0cf2f7a94ccd4a199afeb933c8b5f4b	\\x0000000100010000
45	4	8	\\x7d9fa4fd370ec889af376e16fc6538665d661f1d048c20b066d444888302036a6a164b3a66e7643f0050c58ef2aec35dcd95d839eafa3b61e091e23fc46fde0a	292	\\x0000000100000100b845079de9ea3ca350ce0316f50eb89d8cc94a99fb95ee126ce9fe09cefc0862efd958267233a2cd4295c611e8ef0625075e2c49731c356db645a583390d06e7e91f2df8822dc6f6f392455e9f95cdb36d1c0e4c9da2ff470eb46d91916b95f126e3a68eb252dfa8feba93390b55a3899f05f2b09f8adae7f463f6390206a08a	\\x4683fc83d7a1d3d267dcce416471c9a020951c3907cd1e108a51a77502f1b66bccb9ab99fae5a2aa89ab13e46e2e30a8ab0908465378c56584a970c877740bf6	\\x000000010000000194a3220dd971ab04195996af1edcdf3a98e2887f121efc1950a20a54cc1f4542ed0a602322de18323e74b78bd33c5a334bfd29aaace7c6ff0dc44ceb75e9462eb6a4f2473988b49e90fc4c7deda6dee34befa6495e2848ba0fb23cc47e98997c21e4a20ce6530f0f02cfb1a8b51684e2fd185e7db5ec1bce7ddb995ca8f18d9d	\\x0000000100010000
46	4	9	\\x488b6afdf5b52a84dfc191486176363044fca73c096ad57be3e6c35f84b5a119832c8909001e5009e2ef54fbc8614b63b0a999a404671b6d5c6e643080754b09	56	\\x0000000100000100aa0766c87ad99db2d476c3b3a29782ca96c6ae86a7a5b6985e11d3747b404702d3b4ba3ca33f048ee9702c5b5b0e9b100f9be96a1ae851c84be5c02efc9e32048e1d9def90813ba1b137a0b316aa8ffd000a8bb508846fa98a8f63c16aa10422bbc336c894aa95db9589bb90d7bc81ffe55b66beb2c661f195ec44b3e6c55ea4	\\x379f194390a30bce61a35b487111f5addc9b3673dcb7b40839cd9e513be9cdbd4e348bd019a903f6aae0b9d81b3a5abfb929141c4a0adb759579edda8ad703cb	\\x00000001000000012a7f158873f417ea5aa4bffcce9f1d966a8cfa512f622f085836d4ffde662fec4028ae2e71075f4eab34c864853074b2c0b1044e7c7682015a7d2d51613cd8fd635676b616d0e7feb56b0f5192fb7378272714409958ac50df8638151aaee8a680ad77cb365b051c93ca6fa41c2dc9289d9651591a369aa797ff7c8b3f3c9e6c	\\x0000000100010000
47	4	10	\\xeb87ee14774a9a3edbe9a44b5a155ed555d8ce0560ef40e3dc349a7e492da7622bd9c4f18fe5efea176c6d4927a33854a942b242ed0f4b4241614aebbacef200	56	\\x0000000100000100898eaa3079b64dc884ac82e866de53fdcbe6cfd9874310588babed7ccb78ebff76c1ca8e0e6cbdf0c158f26c25c721e490499f903fe304e4288d07c907cba2fcaead7ba584cbf8bd3336c42ccf4f3ad9be83bfb78495ee088ba6b438f9f348947b10dfba9cbf4ba85d78b2a4a27a5a165f64c3850c6db76d74e23961a4de4383	\\xb01d0dbc2da76f5fbe0d0fe7e1707a78afd4cc11e002845f77fa9b6df356539dc47d87edddfcccefd351928db417025518f8d356ce25098f6254b5adaf963c56	\\x00000001000000014fdfe921849177a360eff8f3b41214f940c2d8aa7679e658291a7ee7aaaa2f6a6dab6ed9014f7821622121dfe7fcef6613788d058b49511abc7d01a3dec92a5e3b54206c7b232746377b15ab65ef1c413005211c85d636f012652baa1562cd0aefcc7d236056e977c4c3c90291726ee182799fb08e97bb5794a4d03554af2668	\\x0000000100010000
48	4	11	\\x34130cee5b1e449045391f49198e99e5e3fdd53d524fe136e88aa720e4dd877f2006050d57e8b4fc215b0e9202c1c0fe650370f20a9d4ee1fd9176cf8054cd00	56	\\x00000001000001002a30139818fd105a6b6a7df42b6755b2fc123e9c52d8c3d9488b7803aab7f4e5895176ce68774f8b7fe0563e52e7b7d0a314c41e95d8ff834c80402257a24dcd834ab1af966ee03ffc9abb84f473a28b9f9b983c931030c791ae1f9ff89197e7789448b8d07d5084b35956b925464fcbd160a60717882a113e0a751f45175f0d	\\x2b48e4c24199228987782197c27d735294ea37dffa4f80e6023c86b2bce4828f4bbbecaa09f20f6941b6c09cd7c423f06e3eaea4ac5afd5a1c1d71ec7746d869	\\x00000001000000019458c52fce81a64824e183e8a6f3c7464cacac6e6f6f2af7fe69708f642a06df5eac88e3b6b8f94d48222605c3d97bd5109f9e8fff7cf0ec1069a85928315a4452b8bd80980ad8a347e9592db023d5861eef4f54bf3bcc7c41332599fa80a6d1612750385aeace0aee56b6e3dea50a73999aa04a775bd04f26e362855110ae1b	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xa06a63b5c45a8648e20585584d319836b00079223255cb7d203e5417e41e6448	\\x5f0fa80505271f6cba2411ff46e84c00b65149bf3be3a1bd4a23de877176a30dfc3d0af9837430c37f566b92ee01d79691ec53df6f3c418ebbf2d56011b89a01
2	2	\\x959f5ad72f0b7551931d710d6c88ba5ad73b560c92b65c0aa6321b62583b2676	\\x094d9091e8e5d0c400b0a8b4eb7de385e6fdcecd58379cae99e77acb4914d2897123b1b4e9c42c6b607a5e46a56a062badb665c50f71d1982899b40789e8329c
3	3	\\xc3e50bcbe481fd8313b30e3fc78d1a72b0310805ee9e969bc68fd078b76ec025	\\xb49095163f34a52f172446ebe02332e34bb7824ff80b979b6df9c7a51694935698f03e004c8604b4383a883e11980624463b5f38ac64adf4ad3d36bfe0185ce9
4	4	\\xae96449e07e4626fa166d4250d11c39dd19ad61afbdaf0ebd9db9faadf386f76	\\x3e478006fba4d33218d3cc6903f2d9decc3c549aaadd1cb3c3ecabe8ca27a76eae1b30ebe36c1bf7aec7dd16df125f6a2247aaabbec8451ee7d2fc472f2debc0
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	2	\\x8724068701806b1768e9dee761935b71373320efa2fac73315163b95513c5d1be3e5f0d81f8fdafb70682d47ca880aad1361b4a507a02fd5d58a7fd300773a06	1	6	0
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
1	\\xd861eff5c230ae965384a2fdc113926bfa4d7e29696095fc15d83d438e88070a	0	1000000	0	0	f	f	120	1662670974000000	1881003776000000
5	\\x3363ca4d3bae0c18d5f9e7fff9cd75a99f04f03a502f32088564b8b4d7749b96	0	1000000	0	0	f	f	120	1662670983000000	1881003784000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xd861eff5c230ae965384a2fdc113926bfa4d7e29696095fc15d83d438e88070a	1	10	0	\\x27ad60e4ed488950c5fe0698032e977273fac7c98c6609caa4ea1f63fa1de493	exchange-account-1	1660251774000000
5	\\x3363ca4d3bae0c18d5f9e7fff9cd75a99f04f03a502f32088564b8b4d7749b96	2	18	0	\\xec24b3a5f585a661aaa81a89f2dce646976205c32e73e68c6ff338e097e43005	exchange-account-1	1660251783000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xb66fb37cb9e3e97eaf1235edeb2852996a762df4b981c332dd062e85e20955a64d33a39c33fd0c38049f28dc1854ccf024d4cc52c57fa8b1e37ea5c89f8a63a8
1	\\x45beab6e93509092550fa760e705e3bf3eb3638ad60a7e507e798be9b87821973491988798e7d8009405ae3565264d52980e4d9755ffe5065fdd700098a057e5
1	\\x27c1766cbe8c21906809a583a3e1d0c69d021b3c93ec2005d87786de8909a560f7c288baaa620d4208aecbafacf7a9a77c2f420456254e9f6377fae4e0d7622b
1	\\x9883198de58cf5787521da3ec6ecf1eb11caed84d40826d0fd4ea32be0f829a4eadb59eb5e52e4f1d8a99d9f38f56de7060a90ede8ef1ec66e0702337221c926
1	\\xe1d051b6463fd59ae1483dffa9bb13f8a485bfcfa28d196b133609826deaaaafcbe22c6f3ab7134f030cef7ce0eaa0683930ea5cac969f3fb6b0868b318dcb22
1	\\xfcf19246e210b348a1840982f524e36c7f4edab678a9263c70a5f0158445eb8affec1e9fb817451e7f0e09143d854b7e5075b2a39b0bf8dd91223d15d5fed9e1
1	\\x9080a3ef1d447a5bd836f3e7f9ea069d30c1d7fbae1e776dbd6cb5a975ca3e0dccc74b7cae5468d10ecc9e6469d48f3102d40acff678e9cd4be17e076afa477c
1	\\xf5cd1d0de2c8d2bdece963ef75d08c7ec9cc941de3a262ce5766bb84e223708bb3a04e088372126e6cc1a4df5c4cc48459990f2bdf1508f961fca74c35d86bba
1	\\xf232932a753d62a389f50475b5f9f223eb5eaeb974400e4a9e31d75b398ddcc5dcaa9e9801d452618159489936cb1ae16bacef4672acd5679d460f48f54efbf2
1	\\x9d4152f05da514ca1de06a9bbddde78d36ee67985f9c45cf274c1c72f2ebab8cbba52d562431fa502b0690bc9ee897a95fb0457d23a5d2f25a24d94ab0f7302c
1	\\xf09832b71339d8c151abb0e79a848df0865a1fee29d45536f1139f2aa457cbf419ac1c93836ec06eb6507b58913554f83402807bb32dad7721e4d00a05701ea6
1	\\x19c627139275cde4769301641c791f774302c5deb4b4057dfee79733ce152330c8127a4e513e4f352c484ee26ff44272f5b57d6c39ae36b52f7a052c131ac96e
5	\\xcf61243313e7367c08422a08aca2213306d3645e587338acf6c632e93860c81384403ee95511ba3a2b26a58288f9f731edf87bf50ab33f2481111ab5df813203
5	\\x38dbc00e048f0f036acf451585ccb9e68a1c6b864ab27e35e36bff5147b0c40c05e694a87b39e84bd7593f72a448e9371182978877893165ec14499c7495573b
5	\\xf0405f9605fd43116c2f67718d1dbd34ff208d28a6c600f6e60a6429e082054f5448438b42434362586bf0359635de8b0733dccc9eb75800fd90df47a8055cfb
5	\\x6931c5fc50013c12b8103c0fb5d7ab97c41b2ee43aab02a824056308e680b1767aa503f8fedac0cde3b4a47a5917d7ff1124d9b1db5c18a001dee1580262c580
5	\\x3805ed064975a354be2928562fc6d015d856a22c11db714728d694b2aeb7a127bf86e05788ade9b9175a610b551e9a70a225dae6f9d8ccb41655cc6cef0c570f
5	\\xf917c334ea160bd642ef4662cc7b3b2971611c46f034ca1fa3d934ccd3d717e20f9bdd570785c6ff462d1437a1b833cea9993d6134957d5498490ae1ba325907
5	\\x81d2521b00b74d71429566bc1abaec5d65c96ad6b55464fa806e2295fdf19366adf14009c24c58c8082ee84ea5d2a975fde53d9b19b98ba5378592875524d25d
5	\\x5111c6b99a2f44bda4700d4edd01a66ac1f2092fefbec9d7b845ead79a782ef1227a7276cb9ac623193e69bbc80f04108c3cdfbd8d142b43e02a286933bb037c
5	\\x703b1fdb763113dd73986b4ecab79d20ce8e4ad74cf3591a93b8281b7f81cf654c7a2c0e38493b296c04bddf79352e3962552c30a235b0e70a3bc76a60ca8a29
5	\\x6929eb237120b4c25d2d8e99aeac705fa1363b8c0174616c89aa194bea68789a3138d43fc9f090a54ab67446a2366ad856be96090d10c68005580903c8d222ab
5	\\x4d9b7f38fa7efa959f69e1677b613799b64aa000b1042221a01f6787b57128c6a101e1c7593c9164271443c121571c3755224bd14f6ab50036e044a47fd2aa80
5	\\x5964322c9eb19f30e06e7b475eac18192ee832aea772c8cb801a638ff8007ca802ac47eac03b045e59bf338346e6de6f8b77cbc0f4a32b002488ca727506891e
5	\\xe025370e9378fae4b643e7f83e871f280ad4b021c8851a4391580cdb18355440e0351178fabb7ae40f62347a38c4d94fde8b7e8168016fd7a5071bcfac6221da
5	\\x92b12fb4fa1b29785ec6908531ddb6acd757f6d985a1964c153fd253386c1da8b832bc8320c9edff888d4abc07e47d8bb4b3df5118f595c85b52a3166b55f1e1
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xb66fb37cb9e3e97eaf1235edeb2852996a762df4b981c332dd062e85e20955a64d33a39c33fd0c38049f28dc1854ccf024d4cc52c57fa8b1e37ea5c89f8a63a8	195	\\x000000010000000130f7edce1335b42d7a9cdac2bdc2b1dd8812c68711c03fbf01ff9ce837566f45af816040484743082fc7674804cbe9ece1460e60bd36917fdd7d377e246f4301cb698d05b2b33abe649c096e43ad470342f952d70ed313d550bd6a97c13180bf2648d472919544207690ba4e68d5db09338d94a839fe7c2f455fd60fd6753e66	1	\\xd4859b7c2469255fbc079084225f2312ed962fd57c3bb413ebdb4901cd02088d1aceacc383125f172052680104bb2b581e7b2b877836d7977e464647594a1400	1660251776000000	8	5000000
2	\\x45beab6e93509092550fa760e705e3bf3eb3638ad60a7e507e798be9b87821973491988798e7d8009405ae3565264d52980e4d9755ffe5065fdd700098a057e5	369	\\x00000001000000018946ec50d087f338c6d17c2cffecf8ee226ad83f63b68f12ef1d1ca1b3be6ddf69321e086a04bbd0d28dcbe48b252ada1aafd18a90b2880243eb33f6aa31325518a9fa9d0354503911a75bd9c1d70c7e6e89ccbb81fc6b8e6d23df7338fd453a84459c990c3bc3a4b846216f45568d3f90b244ffc7e07c5be858327701245b6a	1	\\x72f3a6ace7b2283c21537add5c434fd81243fe28744873b281617a04ac6a907f422b756e745d3d5c2ff77b0b58eb64e00195e5f44db7a928ae50d9b6c04daf00	1660251776000000	1	2000000
3	\\x27c1766cbe8c21906809a583a3e1d0c69d021b3c93ec2005d87786de8909a560f7c288baaa620d4208aecbafacf7a9a77c2f420456254e9f6377fae4e0d7622b	292	\\x0000000100000001b2a83b8f0d4b60c389dbc810ab7d93571576c9abc84d900d6cab44472846b9c854c35d38359f848a2e9c1674fffd1daeaeb84e9617e9e156de73f080739b4ce4012f1fea65dd1df41684a195624df02f9729bc34e03d51fd8de0b958fdd93a50cd052700346a24ebde125cba4a8e5f0d82eb6e30bd081b7cc38bf3cf49ba7194	1	\\xca83b1331961128b70a90b98580a1d0924c649a792c55cf015b840c91975e324c228476fc1f3bff33bcb5bea18b3e776cf921a13186420480993700223a94502	1660251776000000	0	11000000
4	\\x9883198de58cf5787521da3ec6ecf1eb11caed84d40826d0fd4ea32be0f829a4eadb59eb5e52e4f1d8a99d9f38f56de7060a90ede8ef1ec66e0702337221c926	292	\\x0000000100000001408881077835fdf3c22ddc9d524f7d2deae9ae88db642abfcc175273f0b595073cd29abcc35f2f0e4026f9fda361d9ee99c5a9fb80f9d2f6785e9dda0a4accb42522e5918c8e1ab2a084dfaabab996b62980eb55ac3663eeb964616159d0ca453135a02d069c259d51214227f91906098e5dabb298858304f9f862a71bbedb89	1	\\xd9e979044597143395db833445dda783e13fc311cf5fd0ba230ebc5bd98cc0179ed42c41ecce3d9bbfd809abd0c91f97954e4b7c1baa3f8ac04ee7df5f386c01	1660251776000000	0	11000000
5	\\xe1d051b6463fd59ae1483dffa9bb13f8a485bfcfa28d196b133609826deaaaafcbe22c6f3ab7134f030cef7ce0eaa0683930ea5cac969f3fb6b0868b318dcb22	292	\\x00000001000000018ef2dab5b9f6ff11f070b8e6466ae67b69ca1946a1d50acb05ab951c47285d1099d32fc45c03dfc3bc900bd7eee433de24801118fa0634a3b50e4f0a598061c04b01c46f2bb088ce945da60181514ad1adc7bcd052a57defaef4c38de163dcdbcfcd79fa5bf09d55bea2a86af4916f1bb23f5add7010d135c3541a79a006d064	1	\\xf89d534319d914e35e968e553fa4634f5a168a127269cdba90239f2a246d7f4a6a7982704654341b99a82bdd3e03295133b9e7fcf6efbad78991b6fd5b76f703	1660251776000000	0	11000000
6	\\xfcf19246e210b348a1840982f524e36c7f4edab678a9263c70a5f0158445eb8affec1e9fb817451e7f0e09143d854b7e5075b2a39b0bf8dd91223d15d5fed9e1	292	\\x00000001000000015458d1f643f3652e81a254765c5f49284e2f1a9e452a19cf4e0cef9991c3b5ba39307c6fd58682cbf37002c29d2e96db280905e66bafa73a34a25b169a4beb70e8585dbedbeff5937a414ba55e006aea701e02943b71b88370e3d87a497e590313fdf9ec15f1c4a228a91a3f0434092689bdca8c71096422e0b61904ee173bd4	1	\\x4d5c5f9ea5857e304a3bb457dc23156b0d64c31f4c75ebbc00412c910f05c75a4f86c8f18c9f7f8620153cafb10c03b5fb414c9c07e35ebf3fae76eba656580e	1660251776000000	0	11000000
7	\\x9080a3ef1d447a5bd836f3e7f9ea069d30c1d7fbae1e776dbd6cb5a975ca3e0dccc74b7cae5468d10ecc9e6469d48f3102d40acff678e9cd4be17e076afa477c	292	\\x0000000100000001285c1a1a0385bdb12a649784e25cd4d74ee6eb2c5ea18178933fc315ea1b81be4cb7b9a403232328dc606ce42a0a6b033d59ad3175ad50a3a1d14547fa8a75ab5abeedb69d5b4dce9fcc67bb5734da55424c2fb8ff4341315bd120a7711d17d5ab86e25fc71049a653e8920a7a14a71985e82e24c331a3a7fa2aac67e678b83b	1	\\xf6c888b6c4d6e1afc38803887a854f39f085af64ef2ac041aff737b2cfd611cd654ab388ab932dbcba4cf47b91911c970d0e00f660e96f6bfeedfe34420a4e06	1660251776000000	0	11000000
8	\\xf5cd1d0de2c8d2bdece963ef75d08c7ec9cc941de3a262ce5766bb84e223708bb3a04e088372126e6cc1a4df5c4cc48459990f2bdf1508f961fca74c35d86bba	292	\\x0000000100000001acac59b790455d0324029011f79bc00d1a80824ae299b171589e1dac77e1ae0a79dd5d000f382ca75e013c90b63e9915fdfb4eb04b95a7b55ad6a2542b305da864daf7dbe6ea078bf5e75c1267dba1f1b75f81db340b42f1b228382b8490273bfbc0accc12f7db034dac895d0eb03f88d1c66f261c47d73740c16f790536aa6e	1	\\xc53b82d891b1c3a1cfdd6e1c80a857a0e9f8d588809de6522122d84faf3b031356f03030f12f59ca7135c3c0a800b79afd42938410a1eb4ac3a849bd8f0aeb0e	1660251776000000	0	11000000
9	\\xf232932a753d62a389f50475b5f9f223eb5eaeb974400e4a9e31d75b398ddcc5dcaa9e9801d452618159489936cb1ae16bacef4672acd5679d460f48f54efbf2	292	\\x00000001000000016717b9c09bec1221ebe8c61da1aaee0cd3b86a9b7ebe3f42ee321020cdb26c969d67a5be88dca1981ab34bf594a80c55e31da67a3043dfe7571709a0355ba3f781850773300492e620f501d07865afbbd54e36418b83848317c99079230de04751071464792ca4abec653dc806840a0c5d4dd793c53e1fc27f06813137a5f5a1	1	\\x1d2e5f7ca8f8da36c208b3960c648487093e27f6cafec6b20e9b60335c84d6e4ff977ab8904a39a9fd9e9744fdf985dfbb6d4422f674e1688b465f06a8b09a04	1660251776000000	0	11000000
10	\\x9d4152f05da514ca1de06a9bbddde78d36ee67985f9c45cf274c1c72f2ebab8cbba52d562431fa502b0690bc9ee897a95fb0457d23a5d2f25a24d94ab0f7302c	292	\\x00000001000000016af9ce48f5a05fe80c29e310f19a48dd51ad0acc563a8dfabe8c972a30f6eba87608ee2fa0f8a5ed5fad316d5783fe95de2ad2b04ac42f723f76f52a45ed307a52f291e65a9436627db31ce8c1f61992495ddcfc74393f705513ff66b8fd318a398541a1ad1ad32abe6d1e80af50041d96269fcae8ba8b4700fab9e6b10a24f0	1	\\x4a6547e02cfadfcc49ca6555e7a1b879685659b32bf6023598842fd9cb5ef3b056fb5666d66b2d3c14795bad829cba51c8f2c1e14a838295791994d1a740d701	1660251776000000	0	11000000
11	\\xf09832b71339d8c151abb0e79a848df0865a1fee29d45536f1139f2aa457cbf419ac1c93836ec06eb6507b58913554f83402807bb32dad7721e4d00a05701ea6	56	\\x0000000100000001b7a5e5fa62faa7c65bc5ced914f76677ee18880cbb9434bd16203a25c2f3b074ee9ac98cdd62e9981adc6c6b06b5b559357d5b732937f41030f5743f8e3c175eaa9a0b5d8545e3e780e140fe4465caad21247eae38c110e222d84926998392459fafefa3ac0a992d75fc2bd4d16e29eb9d5f23b95cd8debff36bd7ddf8703f81	1	\\xd498817b7ec139214abdc56d387ffa0aeabec28ed59fd739e0b26c52c60de9f27dd7bfb89aa4976d31cdc12cdfc7c59a7e6f54e87dc55aa42b48bf94dba04803	1660251776000000	0	2000000
12	\\x19c627139275cde4769301641c791f774302c5deb4b4057dfee79733ce152330c8127a4e513e4f352c484ee26ff44272f5b57d6c39ae36b52f7a052c131ac96e	56	\\x0000000100000001470fd6fac0049eee0ab6b742ffa31f0bde2a49eb47d0be0a957041926402a40a2ebc2fee9c18e6e2acfa04d3d15be6d09920d6fea21746e7893053d57357d94e956e3b520dd6e72426f572e0418e7783f46e9ef4335dba191234a776f67980f0272098ed53ddcd916d6f6f9a4c1a221b1c45b8b805931710b295fb2189a3689f	1	\\x62af17f660310a07aa34712b918937e696b6101b94de510c9aabd497045b5a88f47157b707be663aa693b9014c65bdba6c840a7b7f2b118acad0483743e25008	1660251776000000	0	2000000
13	\\xcf61243313e7367c08422a08aca2213306d3645e587338acf6c632e93860c81384403ee95511ba3a2b26a58288f9f731edf87bf50ab33f2481111ab5df813203	253	\\x00000001000000018c2f7ab446feb486b155aa37cbcd2aaef98c2332d2f0dcc8664426d832a4472ae457fa42680b730a3e444c200b3a6520abbf75fbd7a49cda71e6127a8a50ef51abc5e911df2a007c4d23a1604e6d2813de9025b3b27df6470237634910cf011c0877cc4e6881e549641cd9f945921ecd8e830d657739698a035c4d187cc41ac5	5	\\x86ee187c49db9a7893637da8464fdefe5e99a2735f012213ba3afd70d2edd3cdc47ed62e03d90f98f916b7cba62c79643547253ea20cce8744e322b9ba57920b	1660251784000000	10	1000000
14	\\x38dbc00e048f0f036acf451585ccb9e68a1c6b864ab27e35e36bff5147b0c40c05e694a87b39e84bd7593f72a448e9371182978877893165ec14499c7495573b	190	\\x0000000100000001686458b591e28ce82d73f10e8f81c1c7270cd2999f92dad64753e5ddf2a50cb135961e07c340f48adf1a00aa61e6956d2147699be2b6789ba245eb2e6970d6eb412fe9b3037cf4c4ac4e246fe99a2fa19d791ac5a84a1b324579854f1825b51bbb899106bd6c72e77c2a6f33ddfc8673125117aaae0db69a57901e1a4300717b	5	\\xb88cea53240f2665c2b56c46eacc18324b595ab048a1aa3ad1a0bed5752997374a007faecb5cc28a8d15887ada6a7400ddb2588bb205debcccc2587bd2a67005	1660251784000000	5	1000000
15	\\xf0405f9605fd43116c2f67718d1dbd34ff208d28a6c600f6e60a6429e082054f5448438b42434362586bf0359635de8b0733dccc9eb75800fd90df47a8055cfb	250	\\x00000001000000019bf2e0865a97812b77002eeadcdeae92b636d22b8f23f33017349fcdd176086dd05f54e5ff425454c19e81a8e9f1b79ca00ee351234799244d9c80e82d37d79eb675c420f25dcf99940a9c08224091fb99f059a4b4bc7c439c7093a90a00a08ad95c20771c90652c7d1c3da5d73673cd098269593b432bbcc1ae12253393ab0a	5	\\x2a8dc3e8a00cd3d1d4513b41a6f694ef9c6a8441de8e79744d3e69df5ba630429c48500d5a822c7b4255888185c4164c717c856067aa43f27e44220a6023ab05	1660251784000000	2	3000000
16	\\x6931c5fc50013c12b8103c0fb5d7ab97c41b2ee43aab02a824056308e680b1767aa503f8fedac0cde3b4a47a5917d7ff1124d9b1db5c18a001dee1580262c580	292	\\x0000000100000001587ed1e15c31c178e79fb71f8e4263221e46a37edbd47b207b1713004ff8eb1a4527dbfa8b1c80c6ded817c9c3d6bbf84263736f657397709f225f62f7a47b66db8798e64384a1cfe1982a8118e9cbc0c1f2e599a463ff1207bf1a20a9ca1a423e62a864382ef426321020073938da3e62d97c8c921cbd96d4791742772b1f45	5	\\xc18e7d483947e819724c076aa7ecd4ad2d296f9892dd483fa90affacbf734caa05ae2ad3a96933236b99bbd145f796b26b5acbec50b29d09d2202167f477b507	1660251784000000	0	11000000
17	\\x3805ed064975a354be2928562fc6d015d856a22c11db714728d694b2aeb7a127bf86e05788ade9b9175a610b551e9a70a225dae6f9d8ccb41655cc6cef0c570f	292	\\x000000010000000117c6c804d9ddd06880bd15bebfd59d0b81aa86d23fea68394f2dd05e7c03f0fc48fc1ec33904613ecc20ae67cf645891cf3886e8bec3dadd234aba2855b5e81c8cc623186015cfa78244524602e409601dfc504e7a6baf4e497865756890830715cd00675399031f01a92ef6b3e5af5b117d1af66c43cb60f7f7922d6ee01d67	5	\\xe548a9247be0b37f929856f3f0a8acc7a5100a8e171d8bbc67bc30dd8e817f244076bcc274fc25831e9b7ee1a250913092836ed2eb4205bae1ff1559c08bc100	1660251784000000	0	11000000
18	\\xf917c334ea160bd642ef4662cc7b3b2971611c46f034ca1fa3d934ccd3d717e20f9bdd570785c6ff462d1437a1b833cea9993d6134957d5498490ae1ba325907	292	\\x0000000100000001437e107ff83d6c8ed517e5fa162518ad9520c192d8ea9cc2371c6cd20097c69bb73c55bcb043e397c58cc01904085ca8f4c036b0e8c426da04f881de5606be517e8115241c50fba14157a87524629f856e4812105b0d67c1eec2a3a5cb2ba0fe8322cc311bfa87f7f7500bbda06a88425a9894e8829912bf7802651e0dcb3c5c	5	\\xa13f6c7d78e1dc3cf246c2fb4e17af41877a5a01358f05785437b8aa3aa413a85ac4d802a50d707c58f117ff6e1c4012b4f76bf6a406d2433e66b4d4fba1e406	1660251784000000	0	11000000
19	\\x81d2521b00b74d71429566bc1abaec5d65c96ad6b55464fa806e2295fdf19366adf14009c24c58c8082ee84ea5d2a975fde53d9b19b98ba5378592875524d25d	292	\\x0000000100000001cfff3ac04a0b0f47cf9ea2e6657e5cbff05820879c473caeca3d864172307447f256490f332a4898da2fb62c676f8aa985e54fdabe524bb88b2c8ea7dcad790728871a73fee6e88dc70cab42325bc3bd9215b62e26907df9ec25f2bd3bb4af5a876a2d0cdd336fc8ab1a8e2d19c12b35cd9fe10b89af0e8b6343e3603e75c051	5	\\x7e69cce54cf62bd84246aa7a55e5666d4d0b8eb429340473caea86931c8aea196fd0e688a72a00ddf5008444ccd7185c160cd19948ed6fc2baecbc1d538a0108	1660251784000000	0	11000000
20	\\x5111c6b99a2f44bda4700d4edd01a66ac1f2092fefbec9d7b845ead79a782ef1227a7276cb9ac623193e69bbc80f04108c3cdfbd8d142b43e02a286933bb037c	292	\\x0000000100000001d5cbc9c83542ac51101223e1d82b907c9abf1a1c425206bcd312bc472f11126dd993c8e595e8c5e248de043d8f36773593f34b422695ae5a62c3b77d01638250bb47c865375802aa2e32ce9fbdcd5f383b3253b8e17c2323e7fd5b946edc71d78946eab0319d05aff6a7b877876efe795c8c9239715f6006b215e4992f7ac7ef	5	\\xc443e5c7abe7a8700e591e62c2bd548d536cf611730e9b325adadbca903911f7807dd99af358131991f318e98a68d212506b3a6349c24d27e3d5757b8b003d08	1660251784000000	0	11000000
21	\\x703b1fdb763113dd73986b4ecab79d20ce8e4ad74cf3591a93b8281b7f81cf654c7a2c0e38493b296c04bddf79352e3962552c30a235b0e70a3bc76a60ca8a29	292	\\x0000000100000001b291cd789a2200ee7b1e3386dc449c4d5f376e29adde8c915f188b54c969067ecd1a3b9dbd37988db84d5c4f173e1ca4b9e49c9e935fe901f0bf75be4bbb5b89a2ae6f93699be47cdb5b76534c847316412232a734d0749f20f2ca340692ad2f373461f75157ead0e9d3058885e0cd2a98da63f8b28f7cd77f45d7c9b3af4b4d	5	\\x820ef601a229bcc10ffdd0d1e03530ba0ac81e60c9fcac64269dd90c9719742dbc6ac430b49f5e0d3063cf5587723c5c53e60952482e1b85130b149e8fafad04	1660251784000000	0	11000000
22	\\x6929eb237120b4c25d2d8e99aeac705fa1363b8c0174616c89aa194bea68789a3138d43fc9f090a54ab67446a2366ad856be96090d10c68005580903c8d222ab	292	\\x0000000100000001c2be3815cdacf5d89c927833f105414deb80abfae3256b93213efd26f48085b645243600453860ad78793746031c893e1bd16786864ea8bb214a3d4e43e841a474bb1d4e4c7f7d13ae760bb72a490c9e47d559d014dc6c1d4d4177335805d224b6158915980c4f15a5adc0e67497d158b310de851cf2cfba0e6c79b50c829a	5	\\xc22fc792a7582e2f2324da31f955c3ee63fb03e0491a37b23df90e6ca29d3c0f1ed0a8349b8908b0f8a5ea1e9dd755c9a6ad3d7daa2e473801c0aa0b6e5a9c07	1660251784000000	0	11000000
23	\\x4d9b7f38fa7efa959f69e1677b613799b64aa000b1042221a01f6787b57128c6a101e1c7593c9164271443c121571c3755224bd14f6ab50036e044a47fd2aa80	292	\\x0000000100000001135e8d09f3b6d02500eed5c4cc98819fdb1a8f5b6065d538cd28501f0084670317d8dc6c0665f71c82454eb675c2e3604d76764d3376b2b2c6110ea07bbf1cd19a0d19f674bd4a7ba8a7a8d4e03004e068d1832b13c341172259901f8fb12f7dc85d8a5019701aabc96d4c6a60a995e2a3010886b398c6eeb208a2a420af896f	5	\\xb2c6c4e7f8d17c819e631bcef8c770d3012bd3478c09b2aaa9a8262ae63858d1fcf88a07a62df09cfc89b1618ba9f229d21abdf46af3a6f95655566b9686d20f	1660251784000000	0	11000000
24	\\x5964322c9eb19f30e06e7b475eac18192ee832aea772c8cb801a638ff8007ca802ac47eac03b045e59bf338346e6de6f8b77cbc0f4a32b002488ca727506891e	56	\\x000000010000000165701957920827d7a3274416b7c9c2e1a0376c10af5acf92329e4afbb373ca005f4fd9797c188fbaa28a76a961cb9be84b011bcc5809cf25c587751b34d0d5929d51658d00b48510681ffe539ffbbbe2e51013b1b65b724713a40d7ebdff7d6347cb840ba3371cc119ccef85effac680c821007ef0326435ee865cf5ebc8c972	5	\\x92dc6c9d6c981fd4b5208c9ef2a81d34c1d32e6e5a72ff64e7876304c115124cc016677f064f568b86c3000404e1a7c44dca52e7c23f83ff016c1cf75b2e190f	1660251784000000	0	2000000
25	\\xe025370e9378fae4b643e7f83e871f280ad4b021c8851a4391580cdb18355440e0351178fabb7ae40f62347a38c4d94fde8b7e8168016fd7a5071bcfac6221da	56	\\x00000001000000016b5219514c0b0cdad21e3b51750bd6c909ebf4099119a611b0ec5387123d7689310cfc9d710e00a9168996f487ad99560482ed8c40802ef6040cedc06d547c1710eaa4177a9abfe8b5e98064557ad50929a82fde94aa318b8c31c4d2622da76bc5757bdca61a0b0ab6bf162e9121fb3f252fcd31004fecd2dbc51f4c0d25171d	5	\\x1d63cb76d28be7e0e3496935629017ef5a548eaa25213971691fd944fdff41679eda1dc4d58e1b051f7f43edc00501cb9ad039c5f139d5348c6aac334c660e06	1660251784000000	0	2000000
26	\\x92b12fb4fa1b29785ec6908531ddb6acd757f6d985a1964c153fd253386c1da8b832bc8320c9edff888d4abc07e47d8bb4b3df5118f595c85b52a3166b55f1e1	56	\\x000000010000000138505be8d0a9213bc8d160b7facd2bcf6b54c828dcdcc216613e3f9ff0388f6d34358a74fc15e3e6f63ea9ec38d6465d90b267b84bbcb12924425043397ec63a56cc1e32cbfed74810123b9435abd77c937a5e127b6d98db585da2f4d3a93e0df24532c7abc05614fac043da8981becc75458b04df75a2055e3e97fff6dc8a2f	5	\\x56b73bd20c661ebc9aeaae4accb634b5845f1621fc681e744971a964a0f0e4b7c11faa4426e0628d558a231e7f3b2505be848b933d6bb2a33872c51ce475c50a	1660251784000000	0	2000000
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
payto://iban/SANDBOXX/DE546854?receiver-name=Exchange+Company	\\x3c43057735728ed34a51e2f3f5cd6a9128c6c0b41432276933406671ffdfc07b9f679caef7a45c1cab4bf0448627fdd353ee4c473b166b15c9b981bebae7d001	t	1660251767000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x2287fdbe9828660f7442da450ed5907de4383853181cddcf0351eb6f346649bb7ff9b98ff23697e8c2b8d05ab2880273cc3a8d5bb90c15fe0c0eaeb9ce0fc60b
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
1	\\x27ad60e4ed488950c5fe0698032e977273fac7c98c6609caa4ea1f63fa1de493	payto://iban/SANDBOXX/DE687184?receiver-name=Name+unknown	f	\N
2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	f	\N
3	\\xec24b3a5f585a661aaa81a89f2dce646976205c32e73e68c6ff338e097e43005	payto://iban/SANDBOXX/DE871507?receiver-name=Name+unknown	f	\N
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
1	1	\\x6000b5d64505986e5fcfd8ae2bac7d726fd1a3232a8746b5501a157876034075f66926a7f9b25ca85cfee7ebb5e5aa0b94b82adda8d0225ae924cfaa9e3f6f7f	\\x2b8270802bceddd01e56777d30c8a81f	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.223-02C2B3XFSJ9CE	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303235323637367d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303235323637367d2c2270726f6475637473223a5b5d2c22685f77697265223a2243303042424e4a353050433657515946563251325142335845395158333853333541334d4444414733384151475847333831545a435439364d5a575634513538424b5a454654584e57504e305135355235424554484d313242424d4a394b58414b525a50595a52222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232332d3032433242335846534a394345222c2274696d657374616d70223a7b22745f73223a313636303235313737367d2c227061795f646561646c696e65223a7b22745f73223a313636303235353337367d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534134504d47484d343033563146325451564652564b483942545a32464247335636523746465656545946454644594733415830227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22584856574450564243424b3439334657464e45354132384e53394d4646324b56515a543330453145484a374741414b3154323430222c226e6f6e6365223a224a525344304653364834575038484b5a573751444648563741383148454a324e32515a4743395a315a4545335244463958334a30227d	\\x3055636e89f269e560df6e787197f475d0ee80ec7fde580d98ebd494c66a2c7f603d2e8cf3f4b5d7f0119fe35707df4a27e45cd2c32a58aa6f66f7f926b14989	1660251776000000	1660255376000000	1660252676000000	t	f	taler://fulfillment-success/thx		\\xdc840e04273b0c5960ed88d1ecd04bcc
2	1	2022.223-03Y47X7EZRGQM	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303235323638347d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303235323638347d2c2270726f6475637473223a5b5d2c22685f77697265223a2243303042424e4a353050433657515946563251325142335845395158333853333541334d4444414733384151475847333831545a435439364d5a575634513538424b5a454654584e57504e305135355235424554484d313242424d4a394b58414b525a50595a52222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232332d30335934375837455a5247514d222c2274696d657374616d70223a7b22745f73223a313636303235313738347d2c227061795f646561646c696e65223a7b22745f73223a313636303235353338347d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534134504d47484d343033563146325451564652564b483942545a32464247335636523746465656545946454644594733415830227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22584856574450564243424b3439334657464e45354132384e53394d4646324b56515a543330453145484a374741414b3154323430222c226e6f6e6365223a224e3947334e4552343836373634564d323752353538393358304b335439535a375947514a52444a58514436595945414254505930227d	\\xa5e69e1a65ec203aafa4dec8d8f3670ac54e97dbed5e3a274440d57e5432c1c99191006515c26b11279394f71ce416ee9b1c5ad881411fe0ee84a14ae61bbba3	1660251784000000	1660255384000000	1660252684000000	t	f	taler://fulfillment-success/thx		\\x7cea457da3be470e41ca67992a56ac85
3	1	2022.223-01RCBVP7Q5HFE	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303235323639307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303235323639307d2c2270726f6475637473223a5b5d2c22685f77697265223a2243303042424e4a353050433657515946563251325142335845395158333853333541334d4444414733384151475847333831545a435439364d5a575634513538424b5a454654584e57504e305135355235424554484d313242424d4a394b58414b525a50595a52222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232332d30315243425650375135484645222c2274696d657374616d70223a7b22745f73223a313636303235313739307d2c227061795f646561646c696e65223a7b22745f73223a313636303235353339307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534134504d47484d343033563146325451564652564b483942545a32464247335636523746465656545946454644594733415830227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22584856574450564243424b3439334657464e45354132384e53394d4646324b56515a543330453145484a374741414b3154323430222c226e6f6e6365223a2243374b5750545145335a3335584e3031543536325044364b525a4846304b3935415437454532464643365130353453354a544130227d	\\xb44b55b0bcfabdb7ad1c10955b62d7f2674bff99c58610e73f34f1d12ad2379ee7b9051c2f1706b23e1b94c93afd812c407f969b6c09a28f8ad82125697db1d8	1660251790000000	1660255390000000	1660252690000000	t	f	taler://fulfillment-success/thx		\\x3a2d493ed67fed035b6868582cbf0dbf
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
1	1	1660251778000000	\\x34cbdeb37774f40ed3cefcd9686d70bab30c31a9afd4e055c2bfa3c8b8597b7f	http://localhost:8081/	4	0	0	2000000	0	4000000	0	7000000	3	\\x2cb1edb394a66583a8eeb50b600c85f4770e9611c8e56db24a7555f34f526af3c6083083c25c7141ec47734fa2a08c6d79b2132b64c0203650c693354b6a4603	1
2	2	1660251787000000	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	http://localhost:8081/	7	0	0	1000000	0	1000000	0	7000000	3	\\xcea9b3a91bf1c73acde5f85eae2af246671add2e146105849c5a0ddba7c6d036381edd6aed5a47a9da945d24878c22c45c78306825b59587b0c2c290d61aeb0f	1
3	3	1660251793000000	\\x6182c65007227783a4d92d8509ef78d39b0168996859b65ab1443eb6fb943633	http://localhost:8081/	3	0	0	1000000	0	1000000	0	7000000	3	\\x2a68da4393ce25bc6b7608fb5b6e7bf7f855926cb39366a84f19e31b3c98824fff8c0c777ca34f1aab7b224ca01871c33e271b853ac163c86ebb633c60da930f	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	\\x03f5e4ee136ac823b2324d057c72a4acdf006e4485fb00a8cb6fd7a7d95cfdbb	1682023661000000	1689281261000000	1691700461000000	\\xf0d5615e090ffb1c5196dd0a9aa6a680c9731f23c8d7aace56edfdfc9e4d6fb71a9a81423134d69f6b6e3a737d2c8f874e3fe9f3c9fb145823628ce6a1b51907
2	\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	\\xc53e68243951aa823c4df89efe2a4768ed056b90993499889ac22d8d38ccd736	1667509061000000	1674766661000000	1677185861000000	\\x074668a2dd1e4299108fe8666fbfaa935167341390d0b26399122c3d25d2519a7e30beb7a671b4fcdb89d151d981062baa6ebbdb115458464d047205a8715400
3	\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	\\x0760064bb267a248d9c069856a3656fc9e824e3796f5d7cb1747675d5f67a16b	1660251761000000	1667509361000000	1669928561000000	\\x3a1198bc48724c589ce73c4bcf89635166d15d08ec037466bbb1be2aa7e92163babae1e7619803508996c5d089a2479dc2e6651dc89afafb138be4492722660f
4	\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	\\x8859787e9d258b1873a2b914385a3cf15c8332445e3ad73fa3facdba7a8978af	1674766361000000	1682023961000000	1684443161000000	\\xe12e0ba4ac5fe84e1bdc2c49969f123485d6a9481667e38675a7e627ac704aef2f0e0a776ed19160d37066494e87863952de293268329b2d3f1f346b3195020c
5	\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	\\x360a6fa91038e3a6e4e740f719ed37ac7ca84b3b69cb4ec49e701043aef2033d	1689280961000000	1696538561000000	1698957761000000	\\x9b8809aeaaf249e93b4ab2e4bd7eb985dfb0fafbc84cd1ff1aee0223d4976bb721efc0a4824574b0aa28d860c4fe1b0b3a8b58788f7e12cc93aa4d57f906230e
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xca896a42342007b0bc5abedf8dce295ebe27ae03d9b077bf7bd79ee7b7d01aba	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x2287fdbe9828660f7442da450ed5907de4383853181cddcf0351eb6f346649bb7ff9b98ff23697e8c2b8d05ab2880273cc3a8d5bb90c15fe0c0eaeb9ce0fc60b
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\xec77c6db6b62e6448dfc7d5c550915ca68f78a7bbff430382e8c8f052a61d088	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x54999ba667d8cdca9aedf5300a63a785d372d294d4439b92e760298758736756	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660251779000000	f	\N	\N	0	1	http://localhost:8081/
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
1	\\x810da6c85252c3f86cb0b40494d07db1aa1860e2dd50e4e5ad753b6ca1958ba07f0447fef1ae7fb65ac356f93d52e51fc03eb2544d18ac7036bb20b605ceaf0d	3
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1660251787000000	\\xa26aa63a6d21afcdacade214ea16e768a6386b49512936f0fb57d8c3761a96af	test refund	6	0
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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 17, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 17, true);


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

