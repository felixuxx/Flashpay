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
-- Name: add_constraints_to_legitimization_processes_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_legitimization_processes_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  partition_name VARCHAR;
BEGIN
  partition_name = concat_ws('_', 'legitimization_processes', partition_suffix);
  EXECUTE FORMAT (
    'ALTER TABLE ' || partition_name
    || ' '
      'ADD CONSTRAINT ' || partition_name || '_serial_key '
        'UNIQUE (legitimization_process_serial_id)');
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
-- Name: add_constraints_to_legitimization_requirements_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_legitimization_requirements_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  partition_name VARCHAR;
BEGIN
  partition_name = concat_ws('_', 'legitimization_requirements', partition_suffix);
  EXECUTE FORMAT (
    'ALTER TABLE ' || partition_name
    || ' '
      'ADD CONSTRAINT ' || partition_name || '_serial_id_key '
        'UNIQUE (legitimization_requirement_serial_id)');
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
      ',legitimization_requirement_serial_id INT8 NOT NULL DEFAULT(0)'
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
-- Name: create_table_legitimization_processes(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_legitimization_processes(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(legitimization_process_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',h_payto BYTEA NOT NULL CHECK (LENGTH(h_payto)=32)'
      ',expiration_time INT8 NOT NULL DEFAULT (0)'
      ',provider_section VARCHAR NOT NULL'
      ',provider_user_id VARCHAR DEFAULT NULL'
      ',provider_legitimization_id VARCHAR DEFAULT NULL'
      ',UNIQUE (h_payto, provider_section)'
    ') %s ;'
    ,'legitimization_processes'
    ,'PARTITION BY HASH (h_payto)'
    ,shard_suffix
  );
END
$$;


--
-- Name: create_table_legitimization_requirements(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_legitimization_requirements(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(legitimization_requirement_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',h_payto BYTEA NOT NULL CHECK (LENGTH(h_payto)=32)'
      ',required_checks VARCHAR NOT NULL'
      ',UNIQUE (h_payto, required_checks)'
    ') %s ;'
    ,'legitimization_requirements'
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
    legitimization_requirement_serial_id bigint DEFAULT 0 NOT NULL,
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
    legitimization_requirement_serial_id bigint DEFAULT 0 NOT NULL,
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
-- Name: legitimization_processes; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimization_processes (
    legitimization_process_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    expiration_time bigint DEFAULT 0 NOT NULL,
    provider_section character varying NOT NULL,
    provider_user_id character varying,
    provider_legitimization_id character varying,
    CONSTRAINT legitimization_processes_h_payto_check CHECK ((length(h_payto) = 32))
)
PARTITION BY HASH (h_payto);


--
-- Name: TABLE legitimization_processes; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.legitimization_processes IS 'List of legitimization processes (ongoing and completed) by account and provider';


--
-- Name: COLUMN legitimization_processes.legitimization_process_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_processes.legitimization_process_serial_id IS 'unique ID for this legitimization process at the exchange';


--
-- Name: COLUMN legitimization_processes.h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_processes.h_payto IS 'foreign key linking the entry to the wire_targets table, NOT a primary key (multiple legitimizations are possible per wire target)';


--
-- Name: COLUMN legitimization_processes.expiration_time; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_processes.expiration_time IS 'in the future if the respective KYC check was passed successfully';


--
-- Name: COLUMN legitimization_processes.provider_section; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_processes.provider_section IS 'Configuration file section with details about this provider';


--
-- Name: COLUMN legitimization_processes.provider_user_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_processes.provider_user_id IS 'Identifier for the user at the provider that was used for the legitimization. NULL if provider is unaware.';


--
-- Name: COLUMN legitimization_processes.provider_legitimization_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_processes.provider_legitimization_id IS 'Identifier for the specific legitimization process at the provider. NULL if legitimization was not started.';


--
-- Name: legitimization_processes_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimization_processes_default (
    legitimization_process_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    expiration_time bigint DEFAULT 0 NOT NULL,
    provider_section character varying NOT NULL,
    provider_user_id character varying,
    provider_legitimization_id character varying,
    CONSTRAINT legitimization_processes_h_payto_check CHECK ((length(h_payto) = 32))
);
ALTER TABLE ONLY exchange.legitimization_processes ATTACH PARTITION exchange.legitimization_processes_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: legitimization_processes_legitimization_process_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.legitimization_processes ALTER COLUMN legitimization_process_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.legitimization_processes_legitimization_process_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: legitimization_requirements; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimization_requirements (
    legitimization_requirement_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    required_checks character varying NOT NULL,
    CONSTRAINT legitimization_requirements_h_payto_check CHECK ((length(h_payto) = 32))
)
PARTITION BY HASH (h_payto);


--
-- Name: TABLE legitimization_requirements; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.legitimization_requirements IS 'List of required legitimization by account';


--
-- Name: COLUMN legitimization_requirements.legitimization_requirement_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_requirements.legitimization_requirement_serial_id IS 'unique ID for this legitimization requirement at the exchange';


--
-- Name: COLUMN legitimization_requirements.h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_requirements.h_payto IS 'foreign key linking the entry to the wire_targets table, NOT a primary key (multiple legitimizations are possible per wire target)';


--
-- Name: COLUMN legitimization_requirements.required_checks; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimization_requirements.required_checks IS 'space-separated list of required checks';


--
-- Name: legitimization_requirements_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimization_requirements_default (
    legitimization_requirement_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    required_checks character varying NOT NULL,
    CONSTRAINT legitimization_requirements_h_payto_check CHECK ((length(h_payto) = 32))
);
ALTER TABLE ONLY exchange.legitimization_requirements ATTACH PARTITION exchange.legitimization_requirements_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: legitimization_requirements_legitimization_requirement_seri_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.legitimization_requirements ALTER COLUMN legitimization_requirement_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.legitimization_requirements_legitimization_requirement_seri_seq
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
exchange-0001	2022-08-20 12:51:13.332876+02	grothoff	{}	{}
merchant-0001	2022-08-20 12:51:14.370052+02	grothoff	{}	{}
merchant-0002	2022-08-20 12:51:14.777608+02	grothoff	{}	{}
auditor-0001	2022-08-20 12:51:14.910474+02	grothoff	{}	{}
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
\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	1660992689000000	1668250289000000	1670669489000000	\\xf51f9b455918cc78cae8e6cc2ea33a1585586126d01853912b876b016346f5c1	\\xcc12f62551829820324214b98a970bb96f476ed2c973657fe76c32161ed353de762a749940cd8f45f51e7493968078584335dbc81db05068b607c1737825c80f
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	http://localhost:8081/
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
\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	1	\\xbf6c471c4b4cb167f7487fcf0b362e5b5e2593ff0bf18c8831e838cea19188b6f54df9f752afa00eafcd43a1f5be9b7eb069393b9a03d0372cf476f3257799e1	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xe7d3dea0785a12a3d8c3eb1011c4c65adde69ade17b43424ec3aadd7e7cd7a81175b8519a074c21537bf295205c316681cbe5ce91c9f458d0eaaa6959d64a5bd	1660992706000000	1660993604000000	1660993604000000	3	98000000	\\x6adb31bd94f30695d580dc4a6c3b121a87d66f00eb90f7f355fb63dd15e97b4f	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\x43dcb4018863a3bd391d9f5c23a2039a6bf94273ad7bdfde44a5a74b244c59103950204dacaf2c7903c1ad55855a8949fa1ebb56638bcd6a5ee8da4445af6407	\\xf51f9b455918cc78cae8e6cc2ea33a1585586126d01853912b876b016346f5c1	\\x40d370dffd7f00001d29bb79135600005d17257a13560000ba16257a13560000a016257a13560000a416257a13560000409b247a135600000000000000000000
\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	2	\\x9fe342aa944573b76d328fdf6266c52fea74bedb2e461dc7e2066618fd2d82220c5a612cda552cb45d45de86dce66e6d441588cd9932b41463f735b5c5f647c1	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xe7d3dea0785a12a3d8c3eb1011c4c65adde69ade17b43424ec3aadd7e7cd7a81175b8519a074c21537bf295205c316681cbe5ce91c9f458d0eaaa6959d64a5bd	1660992714000000	1660993612000000	1660993612000000	6	99000000	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\xe50caf7855c8aafd0f9ccc21564f6576bd9e6b46d3b055090949b495d4a57437ad68bd69d4e01c6b1653765e99b968706ff8dab0cb1e97de999d8c9ca12b8903	\\xf51f9b455918cc78cae8e6cc2ea33a1585586126d01853912b876b016346f5c1	\\x40d370dffd7f00001d29bb79135600007dd7257a13560000dad6257a13560000c0d6257a13560000c4d6257a13560000c0fc247a135600000000000000000000
\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	3	\\x35d4e33c0d33b399b3adf1866d5dbb17973b9e444b842de549c532e446055e1a0212eea3c6985a8a4012414d38e14ed1a308b7a5497eda32f8acb87349244b66	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xe7d3dea0785a12a3d8c3eb1011c4c65adde69ade17b43424ec3aadd7e7cd7a81175b8519a074c21537bf295205c316681cbe5ce91c9f458d0eaaa6959d64a5bd	1660992720000000	1660993618000000	1660993618000000	2	99000000	\\xeef20d0da277529e070bdb760ce75207ac83071b72bba0ec3361cdb1c5d320e0	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\x287dd1ff3f6b799458025f0f2655487e042eb750e2e11862ccb8b55144b752299971eadebf6a3c690e7c87c2321e2edfd777b0badaf96109e627f0fbb84f0f0a	\\xf51f9b455918cc78cae8e6cc2ea33a1585586126d01853912b876b016346f5c1	\\x40d370dffd7f00001d29bb79135600005d17257a13560000ba16257a13560000a016257a13560000a416257a13560000b006257a135600000000000000000000
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

COPY exchange.aggregation_transient_default (amount_val, amount_frac, wire_target_h_payto, merchant_pub, exchange_account_section, legitimization_requirement_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	76	\\x189b669571ffdb88cc551df04da9ea2dd3babc0844c4b49b958fcadcf2386a3340abf35fb2418c4cf7122feed102fa0da1345af8dd32ad4e9f8176f4dc301001
2	1	198	\\xabadc2682a0e241d7bf0e29df00dc5b1cd7f09d70133c414acafa3d32fc310b371f4b0e9fb09bfee5f21c455a69f29d05d4577b32f86ac30effc2463eea9cc06
3	1	272	\\x9e7b7662e2caf37987a726f2105f23471d33e44fc8fa2c9d67b13392346c4a4cdb9d2a4c3fbc12ef675c3ad7b651173e674a993531d1bea79b6894286374250a
4	1	309	\\xd780a649e4ba458c2099ceac7b3336d3a6f885fdfc1bee4e71eb88f8fb9932476c42dff75413d54b63a4f26dcb905fc31db9296c5b588a0384b71a79aa36290b
5	1	121	\\x7106e41e105e249797d8d8283d7c08c472f70d1f85492b5040f42f2d746e5cc7fe0894b84395a54445b51ab199eec5fe664c5143ef5d9b9c151db693767a420b
6	1	152	\\xeaf802dfbbedfc56b149622330c34373ead83cecc31c05d05fb6ce004c3c98e0451cecff70d086d733d13946c558ad1cf199b0fdbb55ccf7a1bb07d8a3c77407
7	1	396	\\x415130d48708c901c80cb37a39983f4201d5f723222f38f9af3198bcd2574dd2f2e5a9a2457ab7c8be960b919c8b829c931d6df99f855c0c0c0e15c035ecb709
8	1	327	\\xc185a9296b84fb5f0a4f21e2a51e94b73e516e37d87bfae5deb63d5d5a26852a57ca9a86fb0a2cd9b5a39e66c6ad8fd031c8ca9db7d2397568a639094d0d1b07
9	1	230	\\x2bd04ac25f4011cf2a41025075919ab8bec258c825b3d4a30cf3ee90086f19d8bdb48c605f2e7cdb8fcb3a937e06da177e9b29874b219e77a85c99479fbe9c06
10	1	66	\\xcce3c11de19d468dc1d57861c3240df4aedeb12995f005ecf8f35fb98a8c9b562a1209c2b680888a5d684836ce3ac3f654de7bdf947e7f211c2d3bb98611f50e
11	1	241	\\x109a75f554e99fe73265a316d6fad21cc3c698e66cf3b31fe0d43023edf52c8287f00469fc6f62aa192441abbb4170f20c30f0239746fdb419670625555c0307
12	1	149	\\x132759bd685b550348796549e182d9606f0fdac5a2e1a60b031d3fdad088f4c9f146bfead7e8af4b10069137083ade1b8a06ce344fc18e069889d411f193ba0f
13	1	268	\\x4f33c8f308a03922ae965c116611f01e6b36600328b90d13cf9e17d6eab3b84948991f4fa0534992c9011a232cf269806cf47c22da809a18eaf8a087cd911403
14	1	102	\\x5ab50020cc96ed2166951bc69952e7b5c9c126694921558db31a21b3e96c786ab8006f40b4a17748f45195e7222701e1a8fd5fb1eff117fec842f62f2a44c203
15	1	114	\\x520f63fbf15bf4837657e0df54102448a0129b1cfd1cc47fe0c675ffb0483711853b4d3fb03527996f827704203eaf9641ca0c038290aae21e05fcf07f801f0e
16	1	210	\\xcbf7e68425bea7213c87d347ef43fd160114eb2f7f15544aa3e67ccaf8a7928ea831b0cad1266869fb3422ab9ca31cc1ea085d387c1ee92e00747121107e390b
17	1	150	\\xeb1fb4bd3491b53d570f98ccb6261dcd952cb3c1f7c29f239ebe354dc86d9369616daa800ab4dbf9cc12a2fd69a9e1d5064ab66fbc172bb219818729841fbc04
18	1	87	\\x0f16d9dec911014302d0f7302b7f6301e4d0d3411c50e1a4997ea65bdcbeee80fc23face6887f08e0e962eda0849db433061f855c746068d424462678b6e810a
19	1	158	\\xb8a4320426c660c36e159109eacdc38083212c354f4cb87f5effd01cb806a2cf26340b0b303cfe0df2fc4dc0603959e0f4a0170871df23bdc22343116083a80c
20	1	344	\\x9a1cfc885e06ef195554e970f563d00953780364df9da36701eba3f3589042966e507f7da7be1830feb8b35cedda51ebef1119f265cf422ab5000b1ad6b86e05
21	1	260	\\xbf29e1d1eab77163af409002351a24a5bd581a14b10146dbd9a4f6756221e46c85d828186dc39e32cdffd80f992d7b7bc8387fdf93b6a5358a7e3879840aba0c
22	1	372	\\x4350ea2daa14ceb1486c858691b9279cab9ed1043f4a3eb9483d6882dea1ea1da9b09e44b678c8ee45aaf30713898897db3848d74956e31059b205222548bc09
23	1	63	\\x25fbcb935f613ed75a075c01fc16c122613ebe203eecf6c0fce2d8d576cfb576f9c46e574ccc57807573596927458997f1f866b8255c0c1074bd9d9a4bffb603
24	1	424	\\xd3c8a8c6cce130c3efd456a320156236c2fe1b83e523ba803121db6438ca2ced405c00676123429c77efe49c8071c308a10a8702091254629a5441dc5b3b0003
25	1	180	\\x9cda562f30a1cee27a6e3887b7f73da6037e7f5d6aa14028a085a791af0d3782f130ec50d148f3e64a1409277b9178710fbba3f6c536bd83fd1ac016c1406a05
26	1	136	\\xa96211abc3742c09e7b3d471b646dc4a525ef008983130304c7a5d76a99462bcd4ce654a1c01455a508735c26d712ac49d531b4b6e01da8f89f669d087705d06
27	1	187	\\xee3277f2f4d77f06ad59c4068b19af8654ec2cb44fb97746ad5dc6fa6803ad5eb36eaf09e6a1b9d56e4f45df7d5eb1c205e287b46ab53ffcdb190534193dc20e
28	1	190	\\x847fb200a4ea0754752fd990b1f39f46cd7dbcf66a6b7bfb858797fe1557dadbc85232641a3e0be25659816612f06fc82d68183089f94bdcb63d96ecc77f9206
29	1	288	\\x26cc424d8c7056882e99105b4f07524997c12df3ae51932752f9a6e240292af14cf33ad8980e76388d194ab768afd1296e9f989379f80ca5f40a9203489bb306
30	1	90	\\x6e8f5a33b7f520eadee54f236b450599a53adff5b82f225b02c562172a2d1aea0d01b9cb3c0c66a2889ceb2fad800bab8c424d5e553cfaf45c25ce55147ef003
31	1	275	\\x3f40f32d283d3af2df48d644761a9f4520efbc4b673742f1594d3ccf470391e9e95c64d79fc2dd68725d8ef532d40f899c2cae072c64781c8caf94fb0153f40a
32	1	287	\\x86ff3e3e431e163df4e82d514784d8bcaccc4802fa3963e765a2f3c55f1b8f78123f272398710e4dda97a0789af49d81124abf561cb64eaddfccdc718c562b00
33	1	231	\\x6541c9ae543c3521b9130b09ab663d80ae8546a125b93d2ecbccfc216a2d75b043abd057ac01d037a844aba24bed09fbc6c3dcb98c4310d4f4696ef886624205
34	1	171	\\x844d3e738ef9daa042ad6e730144f20d553ed7a552724934ce40ad2c7d9b24996d3415b8cb9dbbaae9707e90f7740e70cf3ff1ef449872d0fbdde2ad0dd31b09
35	1	402	\\x4af3478a18f9b7a1f682cfd037f841ffbe97ad141684073fa16458875c852006925ea88a9b79bb1b97f128220b2b27d72ccb655ba4cd58b0537ff379a4e4f006
36	1	258	\\x5d6d9cf03c4556e167dc3990d764af44ccc83ae046ad9028b5c816ffe290d9c469f5079e1aa36c199cd0d18c1653ac4c7a3cf1781d711a95d1afd8c2a97afc09
37	1	41	\\x074021399b2b7ba0f2ff19907345ab1ef8678150e9dce804753c871843d489a0399b7ba3b04b9cdcf047add874b9adea24ff528857dfabee68fc521daaebcf06
38	1	360	\\xd58519fad625d6a0193a8a348b34a4ca96104a2a16040d097770ebababca09157809ea1d391d4c17e169c7971a07868483444156677909398d1d016956766102
39	1	401	\\x32144000d3e6426fb1ff038ca4cfcd16430f29995586c73b08d9da754d2c2c02be48e8f4207891bd25e9760aa0ec187c0cfb68f4d67fa6ca1931173ac6a8920b
40	1	73	\\xee5a7ce8cb33c6513b86dc6a78dcaa85abad8ca5569895b0eed203265397f7b9c1843b9e358aa23f008622f32c055064da397f1da6c26a9609077915ea58e10f
41	1	324	\\x43523be8645bc310513587bba548b3b212f60c16a06d480e6dc263585da96fe2e34fb3719ec8c850243ff41e5d8655eb995a48c740a5db8ead03f7b2986d300f
42	1	32	\\x2d17d406117fbbb175b53ff5048e0ea01395c759bef11c6444d6efd70b89f99a2374bf12f11e5883a72ab07f6a845d3b102e9ea91afdde2efdd190748b7d0907
43	1	147	\\xd056f99a55c7e461c90fe92efd0a9004b0cd0987897f82ddbbfb71a85c192539db25fa7e686282c1306286c673544938dfbe10c9a12af53fa1347b5c2ed5fd07
44	1	35	\\x162e41028d0e66c58af7c629fb1e0a42b480789f237c69f705a24067064c784a88ecc2b86556c02862b9e83c32b1c8cc4d864ac0b473fd580065fecfcedaf804
45	1	155	\\x3c0249fe2ed69427138c41901e7f5ce69bebcaf2b58d4d15b7717b522da22cf9f59b145bf474d01cc86497cd862b0c6a4a53a40086f43fb3148edd257a90e105
46	1	326	\\x9dab6ce60f28e3dc9aba49138e2f806421fdbcfe030d6139e72a56c0b0f29ef85ae81bd5b06c0d631c9c838aa66533a30ca3bf1514ecbdd77338ac2bf1f8a506
47	1	245	\\x9ebd2721977f4f1016aa5f3b37c229cc7483fd868704580ab5946e064e4ed9b0e9e9851b76a1f516629aeca122fa9c3aa989c1f2e37d63ae9d5b74e84c3f6404
48	1	410	\\xe48d4bff623c71d006d9db55ee48ceb72d34d394b02fa13cdb199f91b2f40b2eaa6aa7f43d08f97d1f1d5ce5f6f8ed51d05d4c6bb5c21498b418c70b8a190c08
49	1	170	\\x29195e924f40f5cfc6601e390c999ff87a3002b2aee4310fd1c9412f56215140bac11d7d68f0299ac64b434990f6afa3cbd3042d18e8475f12e4dc6682257201
50	1	85	\\x972e0ff694ffdf9b2cc1ca388f34b20fba9d9f1fae34ec31aaa347ae85502aea5de0e84d455afd0c8eb5305b08693da963d5368ea3e8c3ef96750980b3c9bd02
51	1	75	\\x41b6f06f9aa473365d314cd8e85e55f4bed523507704e8f774e2fb34d3ff3b024151e459a65939b0b17b6ce753553450def3b91ba959b7ef2bcb84b5842c9d01
52	1	373	\\x1cc4978c2a92cdb8b84552920462515cdc7511399d5c6f94765db1ddd4335cc25f37ce10a3cba92c94693be529ddf31c71dd8d27ee0324401a7e513aa8d5fc0d
53	1	160	\\x16746fcdbc50a18a9e93bd14ee07e254b289aaee982f6567c14d0d1bf78171d8834130466e1563c1bd07e2a126ea92cb2a469a50cdfd59cb3409dea33b9f5002
54	1	141	\\x58e176a5a1d392389c366d25476b86cc814a1a3f32db1f4a4a1d625772b14acd6b1b7915e1b476548719223de9bf59b2c47a8d50e44d52e434656eefe04bbc05
55	1	13	\\xc55b70192a5fdf4549573635ed6873642ff4a5f2fdf741252dd0b80bd55aae2b68cb7904e7d79a39e4a03128827afbe6d8932b6ab9d092f395537939548e260f
56	1	195	\\x5785dcc0d1242cc22794f75fb9f4c4854ee2750a68432ea357ab26b782b3756011bf732d7772ac241d84625e83c4da7e0bc2a63194c4fdc35d3d9dee442c1e06
57	1	319	\\x8ba20e387a656be9946955f8012648f1a01956c2ad5627cd258f1998bca702d3fdac466c79049ba772c09fe4bea5024fd4d0b0b438d60a8076b58594a14b1901
58	1	12	\\x57100e0d972d72b04411b2412ed41e09c0f53bebf3743b0606e70f709c46c5db976baac8223781d82464472f2d8530aa569f4374c1c8d529b5efad965cb2f106
59	1	329	\\xe34090965b60581b714d1d08defb86b32913af5d2af8717bfec72723d02351972f6ca2f49478f748e5772a340e3b6e6c6dedc1c1fe3fac84a059fb7518f86a0d
60	1	340	\\xdbce79f638c9e5fc37f0c03fa00713f709e6c5cf74d3df4660dcc2d0e9a497589c3cd7aa674f89dac1bdb25e67fc59dd54a9dd12477c8030099bc2dbdd23bf00
61	1	314	\\x2f7bcbde286c766d333f928ad2119b9db33288b58ef79a67884f4dadfd6e2d8a242e2e83a2bb2e2f339cacc083a5b819e5275084e6820aec8906d93812221109
62	1	211	\\xeb1d4a9fd4643a4b9c02becf3f7431821c8a0f6586ca785adc1e29091a39b1639952974b20142a57bf0f58fc95a853029f6cd84fd38926707c1c79106f72520b
63	1	383	\\x5b797feccdbf34db8abc3b312a8f26bfd0bc60318584fc24d4f8ccf42526da5f69f0773038a21e3eb692a891fcce94166837be961c2776569f3c15301c0ffd07
64	1	126	\\x5b7d424ea732fa9596bcd50d92a3cc3aee2a900cc2e5605448358f5634f5c915ebaf4c0e5ffa14dd2262d74ec35d7dc07a16f8b76ee769d854ae0d70b4985803
65	1	29	\\xcb9fea5e1f15cf5379dc713046ccc5ae5d15f739918bb813188322f22a346e8251330b46b3383f7404b02992755d36275fe27080319fb425621de00dd386040e
66	1	321	\\x34f52d51207cb1db4a9f203f4aa0bab6651140c4761e9a917bc0c86a5711052593336df0d463fe722b16174a2528e56bc37000671c5e9876e73b18fa70653500
67	1	7	\\x8854ad2c33690aec6b6c9a9388c183c06e21c3b2fd5bee181246cf2303594a59184e86e4c4af8c4dda1ff86d5c6ecc6631e691e8f7f37b8ad20200dba56c4202
68	1	111	\\xf2a9058efe4dddc9ae32473cb31c93ac4ffa123202bc91067026ddc29df151920683eb6997260b70cd72b280b4c6379e611324f6612a1983ee217d33f26cab08
69	1	385	\\x68e82a44071ba0708ecabbdb8b80ef8e118ffe0201cd2ecbd4421c25b77038e870b76f4e12f2b09561aec11f15eb08658a1071a7cf6a51a528cf12d30e0e6a0a
70	1	338	\\xc06b2658a74f3bba6c8bcafc8d96787eb245133f77e6dce9721e0838c92d3507107b5c0f6d3ef9d05f8f92087335b53e5f4e9f7caf6106b3ee3160d1da4d8501
71	1	365	\\x50ed131645b479b57fcb24fa9138241d917d132c157f9a888acf172662a7cf5e765430b93b349107da228f79361f7bb8687a7c5536f2a90eb168bc96e9887800
72	1	181	\\x9428aa722c92dc69420bffb916d45189c76bf0854159d044fc64a480ca05ec714684c5f7c9389b40ce7715e0d6d69468dda20de358033e6adae1af58d39ad30a
73	1	98	\\xb3a3d4b309de95fbe4645a0685de0966c86a288c220965b4d0ce6d76d44a396e31780e5f8924efff7c92acf42b10fee0f7a2c64e60e85302f1d04d437bfc810c
74	1	218	\\x6c60629585a7c5075a257b3a9f5f317ed81e18f302368e272bfceb2e800dc50af2f2e9dd9d935e045800dd824cb69697d5ae9f9bf4a5a9e36dc0da03e0dec503
75	1	159	\\x38de74d6c2041c88e98e058d09ca29a2122052218c8105bf7374370faae0e4e00d93f9d36e5010acf2179321f75f883f3092b92f08692ec9dbdb6483dd0bc30c
76	1	325	\\x8820671902b9266b6e481628fbc11a7369d89c14229987a8d381eb5e617f91343357d678c737ded31d26484e99a7041c0256690fb92c415bed700780f676f103
77	1	47	\\x0e1c78f5201b990bdd4dece8a790b34ed064c167363a9a5f80c6c6e5016abd36a62afe7ef806830a3724bf8919bb67ae38912fd2e659177359acf7f4e0fd540a
78	1	305	\\xe4cb8ec7dba60fd6a70841d0299f8f64fe891c46b2e44841d8aff5462de188e2d925b5fce47237e7c782b4f36e013688da4be890749cd228ba5aac6fcaf21006
79	1	387	\\x770874aa4856ef0974aa71dde7838d364c62677b60025d00ea532992e9948b1f03c2fc95bef0fcce83924047d8b820364188e548d7ea1c1f62524814eae35e06
80	1	71	\\x5af51ce6f6f8d752ad828f8c7620a39c110c033a4b1ab42c22509a12508c7f821ff14e50ef58370955e446b6078b80005561dee5515b852053339800e7800f08
81	1	70	\\x1dd70e02862a6926f053eb2ed696a7b07099851c8a87762f145634e7dc56504decd9ac77376c96956d0710cc600b3495414f0c3ba467d1a92b9ebeb75df4780b
82	1	74	\\xa5b9837de7fb2eaf573de9ca6b14258af50a202761c9a4cf1972721d017c7c0be86f3d79c23c654771ffd29f363f6ccc167c4e75cdd837e23efc0e1e7c923f01
83	1	104	\\xee011326e01a1aebce2be42b45d6b2ccfcb6d3dbc49a8ff866849d3877bb064cde74fc48fed77ca281035fafe66b8d665ebffc0f2c0d593e4307719b2fa3a50c
84	1	254	\\xfb01b5da8db2cc10a17018843a34bc05c5628502249e49ade2a1ccdb90ce311565ab3f8c4e60fed4b80918237fb6c088f372989b0ebd8e4555f1e5f78d5c5004
85	1	347	\\x61bfdc51babb837448774943e97ffa4b1f237fc199ae29cbbb61dc1eee83ade789596c7f8fa5e2946fdfbe2a0dc362ee8cdb166b1effe9c3d47587ea74c2ed04
86	1	92	\\x2191a1bcd25bcfe815ae8f95d3a4d169659556d62b27ace2ff680d187400fcfbc9eee5f4612b87d3cf3546e4d1709a891c586c27e57253956c7f666130dcf005
87	1	322	\\x009bc2309ea7255edeeb654f93b3c8c6e3ea547aad6f25289788200beb3c465f234b83ca4c7966f587b3451e6115d7d42d9cf8d273c537a10d6b3d7e0e55b20e
88	1	113	\\x6de3fa6b058af6fbecd4a0dc7338dabd1be132a96d5c1efe4f685ac86305aea9521a78cc74efca0723a692e6e2547a8b6f3e2332435975f2d7951c1c790f560d
89	1	134	\\x4d1e40ebdfd5d2c7b863af8c6353a41fabc866cf5833c0e37f17f0bcf31ac249e1387425d1b0116d7929f19be5248bff45b64e509cd6e875369f571739af7d0e
90	1	143	\\xf65ef9ec35de557330413fb3905e27c29698a33535280bf766bb12112ccc97e543a7635b9abdb97fcfcf221c18243b8d2c73da057c59e8fbc872f729111de00a
91	1	388	\\x18de8392c95530fc19e16844b269dc6cc4ca30533c7fe89254a39b168521a80908e925dd6bfda2ffacb93b54a37789c478c0212ea0fcfa2db9e5d5b32de6780b
92	1	207	\\xdef1dca9b719c67ad9a5f7c17cb2babf1f39239e471f1a5b4b7b8a6d73c9bbc54ebca0a170d9e89a8bc05ac62cfbff66f2684ba41a6bec71675907c39950eb02
93	1	295	\\xa401d5db2dafc2ffd7259e4193f6899f04317f529bcefbe2b4f3223e7cacc018e756b08e3cf5e63f6bfe5c6ff3c04bcdb86a110cceb8f61be16cf0df41e39304
94	1	176	\\x47a782954a0e3ed1c66428f9dac5583845c84235c9b1b99c14977d38eb6cf6504d9496d6af212f00812aeb58b3ab0c7576d2b0e69e0caf36747f0a572768d105
95	1	233	\\x71218e6b6a201fabb294f8a962dcdd5b4556658eaecada57fb8e68c427bff0fd1a4d2d19a3b77bafa422dd8b7dae183bcf30438d59ad6e3a60a0cafbf62ef50f
96	1	421	\\x13c03e57076f5ab272fa0d3525bdd2f762baf70e9daceb78ef3776ec1a6b757dc2128dd2405e951911bf04edc2bf9458743d032df12920c7fd31bc8a4913e50a
97	1	120	\\x18c7a0481df4a598bf6546f2a4292e5e1da23c7400ba5d24bf290a95793db3b843351eafc97bfeefab1c17694ebbbabd9d2679cf1b8c88ae1b1a251a0885c009
98	1	289	\\x9672dd98774d23ce3f8a185f884dae63fc2c7afc40a5ff8a56b60bc3d682ea3093ca4458e9d8ef75f545780eb33364e6451f3893f2c2cdc19c52b71bcb7f970b
99	1	330	\\x113062d5b984cd834dbe6f05d6678a858d0579981e812b26159ee89b134aaf91d3cf1c53d0368977ad759d488b76c98e799084c22ee4a0999ce66d2e0034e003
100	1	423	\\x4654fe387c9b291f7d92e4f8612146c99db2540f9819644b92eef9b754396642efc61664acb6805093ae0e4913186c776bc2247b8d5a143c084b5abfc1ea1405
101	1	130	\\xb44931ff6854974a401b64934943cd1fda50eb6b1ff1c64a1c22541f43c2e19fad29d5d5fcafacb47b641c94e8f130f747164d08e693efa7eeafa119ae26ca06
102	1	34	\\x730072422ea94f148d063ba0007bcd9dbd5949f1c9d75bcec7a77f973b2a325ac9482259c18fd0457b61ca024722dcec1a202cf9bf5d05c4ece9565149bcf40a
103	1	125	\\x0762e9b3cb4487a473b7eba3bd3373251bd6163ffb75d4958645edd60feb795a89fd136bf8ff0100a06631bda735ece1e7c9cc9000b40816b50a1c4dd8665300
104	1	278	\\xc74b00f0028d846d2d3e106571040bccf55b534559d072fa28ec9db5c6fdae7d9ce7fe2581bb3b9f9f5fdb347e277372feaa85313d01046f21014b3ae6be9408
105	1	178	\\xc46bfadd66c71830aceb8dd0e6a259bee1f4ac9e913eb143a59ff20a563845d5882227ebfe86a02977d20641f8825b9a13f72593a436dea67c6359a2c7044f03
106	1	133	\\x5d95f3a6625141c1de94c4962d4ca132196a227d4f983d8902867df9c57338da5b0782223b9d753ac8cdd24cbabbda2a1562b0044ba86ad3dae670037b87700b
107	1	204	\\xfa6d260c0d6ef8dd03830793604eb5f8f55305dacad9d08235e15378e18e4442fdcdafa9aef9e9eb6090f0830713aa949324fee0c60a74f47c136188b9b2e306
108	1	109	\\xa333da43f6b8a7ff8f2a6eb31403d084377cbba9c5c66d5c441e4bfbf4afaca8d2dbdc5cc8ffc6859d8e20cc91db7e71396427ca999d676865396a0471ae0a02
109	1	223	\\x4bf51daa51d1442959325e4e384bb8163ecf70d8fd588d7435b4e930c0b82e867c18764c465c2dfca5913f197233dd9746a81ec92353bbb5815493b50296930a
110	1	118	\\x142c7463811c4aadff2a14c3b09cb9dba3ece36d6c9442f525f6ae7e602258c0fd0f677c73a23e05e4bef86172152911980482fb62e92a1f2cb884c124106b0b
111	1	16	\\xb14c924a4d5a9f05658aef029a4bda42ac63c1a70c3329adb1c774d06e70a82a9fe3ca2cc750001255efc3c5ed7dabff849b371c7803a29e6d44ddd95e564f02
112	1	33	\\x911c272d9fef3b79781b102d6ab5b59665fde57b900e1417f7862e414242d48af575372be50f8e011759f374ad274461d2bf63012ca8ef1e9d44307451fae40e
113	1	334	\\xaa28d8bf302ec66869597ed9049bab17caf842265a99d5a8a7418ba040cc6708ed86db76f27d98e65f6db414d8746e837ad8815fbfd7e8a13f956bbbec27b00e
114	1	413	\\x7f9e9ba13dd755c72195d8b864e7f009c6e102d7ea335ced022172bb3a37539777e3e62ec424a4c258a6c13964a62424a8ab2c3aaebd375816f5cdb49b9cea06
115	1	297	\\xf452b0aec7a5ba215591f2a908f8af6df02c6414674a9f4b43dbf7405eb34cb66edc3a53b48b2df4cc76ae9e00195d346ef205fe1ef7be6f1225719df68c980e
116	1	84	\\x80430e14f092c7cb0ac0cb8662b2197c5dd4fe00c60391669ae644b21dd164055d654209e59cf7fa494cc095214e0dd4278787ed32df2a7f23a125e027b8490e
117	1	301	\\x2109a02aa5d3249d5a26c2adceb1cbcbc4469e5854f0d54f7588bc01e4feb493a8d1a85cc50384880cd67538272e911eb8bdde1d6154b47a7c65668d63df1b08
118	1	186	\\x7a59ba00eda58b79f4322bd6c3c3b9ce14a95cdd9a3ab4132189d95dc780eb2f7e021986b177bf2b7ae2a922dd1dcfef90e3b360df60252a70f5b7fad933d90f
119	1	31	\\xd89e442e38f865dba803506bbdbcc0b719cc5f755ec2a8fd8dccde483ca6659c1111e154d8478607b329fdf6bac7b8be043dd5eb8355cc2b8257214584f42e03
120	1	49	\\xc038b4afdff42991460904b8e65d80b474838fda99d5b73896c4af83236526a27af935d752a25d222175fc407bd647fea21e8c0762d5a7acb63d0988923cd409
121	1	282	\\x175b79fdf9ccbca89630e59fe9aea449a4f650d2677cf1cc72b94174fc15eda12b27becae2b8eb8f867763a0f634829debabfe520cd94ed2088cb27e57985002
122	1	110	\\x4341c6c08452f518c9a2bc9689b91a383e92097c56178c519fdc126855d98dccc9cbfdeb7208cc5739964779bbb1fafe6e02347d9e753be89891cc5d0aa41203
123	1	88	\\x0d7dd6e7b0c36dc80b3f5f9608bb30b8f95d983c728b8c66dcdd6a95c9fcc134c0481a48784ecd01db19d178681be6ce1ceeaa23793c1c9f0a4cfd1eef115007
124	1	148	\\xc8ff8e40f74b08eeb9090556cb7519a3a0d98467da99cb1ec08043971c52d292d957626c3596cca8b370a183b98126f3a7e85353c4236ba3fa292fd302a97309
125	1	27	\\x3156fa11a013e5656010d8ff6c59612c6d26e4f10d8f70f7045b91bb22d368515d5cb9d6e571d86ce8f8c9d7d96c5edf3c82707a7b0330d5ca960de30b9d280e
126	1	22	\\x7b8ea6f626eb5fd404e7bee07fad7733a06c0780a1262245fc778ab1cb6e00ca1c6e3d908f92e5fa1cb64318b8407291f339e771685072bcfb54f18587bef507
127	1	216	\\x8ededb2556d53f169bab91043b71aae913195ac100ed5abe2b1f3282891ec6b8cc39bd5762b2a2a7ca8d055f31250c088e1b577127ed7708988c9147f0a91207
128	1	24	\\xcfb30b69f90b8e01ac35a226a8202bf05b42ab9ebf49339b8abe9e1c45dad54769d1093562c0c642d8c9a0ec04bf16e878af0f04f10778b2aa50a03af14f7003
129	1	279	\\xada15c36dd413035ea8b7581396d9885c6ea1221f65fbbee5bf012b7ead05038f132edf2bbc90e52dedf8381dd6e17bf4182d3025bed1682c0efadc75ef51005
130	1	298	\\x2e67a42a14e147ac9e7e5ea9ce45bcf7196ecb18008a7f87e46cb109f56e37123a2a4aa7ffdd8f53993fae23b247abfb2b4b72654ee8dfcb51ac756599396905
131	1	62	\\x372734a5cd1c3dbb652c0345785a1dbf2479583c554ee920578d31a852d4715af8e85c647113fd4fb714023e80f61bf102a91e96a6391223ced09a0c0892780f
132	1	17	\\xd572c979876d77917f5d84f9b0c06a827eb3878cd8fe8bc085aa709a03b2cd0f4d713b419a1c593b6520335c85b77006725f402e89c6dba0e6b18edc238bc709
133	1	203	\\xba7c9742606f857800c3e37910539b165bc06cfb69254dc8b7c9b5dc9e490396cfde1785127bb273f0f3a1ac62c8350b4a349fe015555d66059fdbc6bdd49802
134	1	18	\\x0da0f186ee34f6ba4f19f9ce27350261e728c1d06de722c93fee7d3eb1a8cda056f53e64bb9e0ea33bfd44993d2aaa4f74dc039a01dd7aa8c8618fa11ae2d105
135	1	23	\\x1c58a8c9155bd595e7914d77d80c602cfec8bec46f24c46d9c477ad9b6ecf11c500003d6b4c371e71473ba2a416566936959e08ca9bfa75124eeedbf6bc3530e
136	1	107	\\xf816a5b97185b6e534b3e19144777afddab1ec6a4fc1c13e3e8f8850f76eaa396b2d6634e6061ccce7a4b9ffa967e1ca9b71c2f465106a21928673d2eb9c9a04
137	1	21	\\x7f224398e4e0e88ac8a0a2a3b9777b912635fe0ea263179b72643ed56949d502e0c9d780912dbc203986bb2079d514e2d8fb5008e71e0d5f9f41298fd827ad05
138	1	350	\\x6de91aa3abc7fe5775a7b309f7c4aef4349f4a03402425fecd7ee86366d35f99c7c64e23f20d788e6129dc1e9cfb6967566e0680206b821c0f2405749250f502
139	1	367	\\xd1d36ac29e8e1f5c70e8732609f5af496440319c0bd99d851a06b9f85cb2db46fb393a15e839eb76d0b7573bd4294aa3f1fbb0779bec0fb05227fce3b2bc7506
140	1	156	\\xff4be03fd22a372f3a8f8f50674c84f436bcb71650bb93ddeeeaee42c9ec40596cf763e38baacf52c770806b6bd149566cbb2f49d720f04bebf75932e7915b0f
141	1	394	\\x32aa7254e5146dd6333eaa24730bc6ab7d2cfaa6fbb2a09b30f71b32a50d1ac18f368173b8e74009fdf1b351f7e17eedd80faeb52f2e17716aeb14cc73821107
142	1	412	\\x197c34c3316d61d58ffe45da5e88478699e4385a9b6a0b4c88a80d53d6f46d4066e9afb65b5300cdd002db28f8a073b95654683bdca73c8f3ec311f363dcf602
143	1	45	\\xb8373c8d9cb02487207031534d24c8efd6be0cf02ef3a1cfa37f2e8f1655460d327842d96a76229b7b1e0d2b46eafba07a4efb3bcebbe3914708cc80258ada00
144	1	124	\\x39ac1d962ba66c93bc3a7ac7924105eebe7c34bac59e3c9bacda85f3f2f584cd0b3a7f22a24562ba8ce56ac31ea04bb65f9143e63ce7b4f5f97b93ccce40ed06
145	1	140	\\x3b2bd1318974ba7486313411e83ca3c7518818e921d96168051e75fe8e77af71fff06fea3aac375ff3459f2c6263a12a46d175af5891a439b5a9465d8dfdcf07
146	1	145	\\xffd60d6f0df494ce38dde3b91b935c5210452b4989459443125aaa8e3033103ab3af8dc699d536da6496b586c3b0b5e39f5c70ae1e802dc52990a238a3c4da06
147	1	40	\\x04cb7ee31324b0129f2019e6d5bc70f903a823414cad5346546cfb760f317a6abc1880b4c38c7d3ff0c5fa11c491c0cc94c64480c898bdb50f2b8285b50d7f0f
148	1	381	\\xe007eda636ff87b8c0a0fa6ecf08f94611b741c1c8b87e0b4859233b0dd9aa62473b6e32b58fec8444a329be7db34a4f046e92f196d132cde916a82002c92309
149	1	264	\\x82a7bbb65de418fda0f35dcafefcf1a3bac8cd095881f6ea3bed60c9995d200db2495c7c8defa63a2b04e4e78978c581438eb8e7c5687f6cbdc80973d16b9309
150	1	313	\\x213254d627f53da7de40928afba146a108c58247e788360b3c89d9519295c4f53846a421e14a7771c848e61633469cedc06a81b396a9bd75b30169de6eaa2d04
151	1	343	\\x5710a3a8cfcf1321f25ee47296201e9d229d891a001c0705c8b3c154ab17e47058ace28f2b9b8f71669bf098183b27c97e46a249fa85b2e9725d7772b7e95f0c
152	1	316	\\x2ff36e2b6b82bce1857558cf729cd01bc6fc0b72d49382e1539896d69b048fa66f2cab61ab21b3ce9a69071f8c7c9caee513b0d5a82c303f41e2c7d7278f3e07
153	1	78	\\x0b66cdc4d4ac2e06b1ea44fde43860bad8ffce65057f5f11c9e275aeefe7b42b02c60e2bdd4bea6ccbb3587ad7a5ef27f914edbc5090353f171683670e2ded08
154	1	220	\\xc9de74e4df85ee539241eb6d2248dc2e0f3dfcf28361832efe2d3593c08d3bb31c73d6aae8b56fc60fc8669ecacd97bd30e275c43b3edb29c14b0ea194caad07
155	1	416	\\xfbe3c8029e629f07c48e988f2b728fc9517fbc540b15d070c6be92fb1c53d1b294de1400efd53c2b1972b3f2a6934ebbdfa65ec7f9c379211f747202f0236f0d
156	1	283	\\xd5ac5b98ba26fe582a15bb1535900f7fa0254cbc76275b5661e5aa06f42970e01d3dace62dfe5a2c5601c491b29fb87077e718468776f6843f443259c5dc4207
157	1	227	\\x24b583da8f70e24f7edc9ce10ed1c9da0befc0802da68f639caf22b18e2b9157b1bd781d9ec008bdefcd0eef86b6a8feb27a3b2db1b58adc7e03876fd32f670a
158	1	291	\\x3afe319d8228b72cd257af1bbcb47bd961aec26fe3991cf1a078f70a32750c4abbdbe2ac39c02e4646c7c98fbc99a74474b239ca5b00074ab12044e9eedb360d
159	1	382	\\x4588363038cf0331b4321aed38e3451af22cfcfa808b7cc877b5c9fba83102878a7fcd11324940964cfc106795f80da58adc277264b3312b937c637f19870208
160	1	112	\\xe765a87310d28d50bb1f91d6687bbd2d75cf7ea43812c9226309bcc8b749db074c0f043769f6eb8eaf50acd5a13d315b9078ae95c25cfe3f0d2f9f14bba0280d
161	1	323	\\xd089d0db62ffd182181b2440bdc3fa05aad9ef9311fff39b92f693ae7b4801f858f9ec18a0ca8b3464fc086da4fb81c379180c329ecbc27bdb40d5982c949303
162	1	206	\\xdf1f56982484062f0411d0434e419841df0697d9fe9a99fb8686ddd3338842508da2920c938632af8b4277f16584fbd9e55ba23cad3546c1ab81801cd6dfb50f
163	1	199	\\xf7eb62e4e6db1a6cd63df480804bfcf42061c4fa0841322b4a6059aa5e82c26edfa82151f2fcbb52f3cd0c892aa52c0a6415f7714e23936405d2a0bede51e70e
164	1	58	\\x0abb6c9fe7bf5a0f49c220c85ff45fac68523ebd70ba4e9ab22b98432a2d42427314920bb668f755fafb4deb031710a806e73c0a40c523e251ae730e56e05f0b
165	1	163	\\x820cd378ae7d1c835e5008c29d6129836345be458c59959c28867691be4407855ef1c0328dc0088055018beb3582036ccc92043911f5bc1a3cd4f3a2820b2001
166	1	229	\\x23546439a77cf9106aaf6e04d3a65a311e717ef5d89d4945285c8fb52b617e9f98f818a9f527368759a5973bf791340fb58b6d392ffc2ea715b520f867e36707
167	1	83	\\x88b127f0b540d7f13811c347f3a2a1cd735f05373abf54c37dfbcba372d78e0580027b95d80fe010ff5df5007440eac236634336f7b40ec29bc6c22179edd20c
168	1	128	\\xcf4d4818c06e638eef5937300bf1f4b37d8f4247896da10fd85c2934f22cd7db5611541e5e38b73813a9abd95af34a845966b927e528784f49e4838dfe0d5b01
169	1	294	\\x525b73019c0a76cf99ec3c9f2f5d4eac1d43dfdb52fbef95e226cab79a848ddd303fe93855de3c184746120166461e3903204276acb32416f36a3e715ff02400
170	1	86	\\x55a238c9b6661598e62f7ea1b2330776578675a8866c916f7d848846532a5c5e1f2f02474ced37c86081094d80dcf7e90f3325cf8eaa640082dfe97691738001
171	1	172	\\xd868d3f471183b90e46bb5d0561dc6c8ed1ee5f81b4f108b0fbfa3ef21c83b29d1f139010af779e6fbf10356065d550e674c488b1f9519f2b79a15c3925a0506
172	1	182	\\xeb0e7a425702ba656966e145ae0112d666ea74fd5fe2ba0f67789a2649f28ba34fddfcbb31314417575656cc2f2d3558aecf47d02064e6ab49440665332a6c05
173	1	363	\\xe259f29a4865be5fb01f0ade6a03580537f301122cb74de45273d4976e05609fec0904538cb4dc080d13d6c53c5ed3ee53e06880e2d4a4ce70b5f363d4200c02
174	1	379	\\xe1fa6c87f781f0f9f16c135ef5e6b634af318f90f6b3824652934fc63ef6ee0dba1f7e9cd2693210ce670801ac723a276ba7b470723419711b4ee21e145e4f01
175	1	222	\\x9ebe1f99151a78f7ce27e621e0b4a091997d86940ad0341dcdda5813b49f3f7537d880cb86dfb63534d0c49141a3694e90a42e9321982d079c284221c6462e02
176	1	228	\\xaf5bd6293bb1dfdd520654b4e6ce68ed656f86a470fb697c2ea8c5b2ef7e89d80334657124edc0eda73128078c85533b8f74c6d25c0352da89f002d2bdbf5e0d
177	1	15	\\x1b69b2705e8f7e38df14a31a8d815b53a04b9e651a4b1384dbc08ba76507dcc14f6560ccd37dec90b0bb5a2bc375731f0f8411a98afabe12688192aecb429d05
178	1	219	\\x155da73e1be2c7aa3684fd5d96611fa20b7ad1a4ec2a9c70bf78f5abce18674b85bb15deb5d84fc9ae11c722e4500ddec8889f0f0234add18d836271a77b8e01
179	1	274	\\x5e8ba53bf1f6178c97cac86f974154b3d0d548c2452cd1beecb8a7a6b78e2bd5f03a8ba7eea954753abf82c83529a2cd8aa867690a08f52761fe879c6393d801
180	1	129	\\xa19a4a6489e78b6ceb5b8832a7252777068928c76ccea623e54dfe578f095264a64bb41eaa76e9a568f551d2d297cc3567fb4162d7c25aecc16fab0f05cdde08
181	1	270	\\xff1522c1006c2322becaf9fbc7446f67f3d49acd0bcd336ef991be967c4705e130c8eba29ea75af4d194d0512b982d86f7d8b663e2ad2a08a8e68f7ffabe3102
182	1	318	\\x246a742fa00530b7e8b57f41229775796e2b199b047d0ea088e17521ee7a41cc75cd043fb8a869640a3f9d371e8d0af863b37c96329bf9b28c469de31479530f
183	1	25	\\x32fa18a128a1999272a01eba26d8ac8897f5950525ae2ce1210c2d51e334b108a864efec8df44b50a90e510a1fb1074b1e41668bb7dbd58b49eab3601c9a9a0d
184	1	384	\\x29859b897d4f812e4b9f940d9ba482ccff59739e882201adc69354a66c33bfd7f7d174fa3b724cad248b6c575e78b6e8ceb5bad4ffc3255007d9aeae5ce4300d
185	1	371	\\x6990553edd09d9c67aa84e31184c43bae344f438e463521f18908041752538acf038abf7e55e3ff2efe5c2b17f69337fa66be9fe602bb2915c6ac6810126ff0b
186	1	72	\\x03ff9ab8716a14c7fdc2b22c6c1613a7a41e2bc5a7a4444179694cfb35d731a6a1d2781b1f1dbcc0171227fdd97f30a1c7d4d29913e89f942fafb9bb552f6402
187	1	212	\\x9bb3218d1503fdf0c7cac045d5c97eaa8214d4b742ef485ae53b72857b3e991483684d867786ebf27ef82c27d15d1be64adc4d894a046f53f09c346f10216d09
188	1	201	\\x5209a80b3c3d9159f5e43b84d58a983bab597bab7190c2ca2c33f73e0a9855788b9dae0c58aba24b32edcd55a212d8241a18aa956662cc0237c0e7e2238bbf0f
189	1	197	\\x4407a12dc6f910ec6109db193d23e1815126781319792e30d4a03aa150a6e9845fa8e70fcd81bec90304190b319bd947e028a485a0826d40c3bf1b6562c7e001
190	1	53	\\xe8f323e569921f27d11b80416541630f7c3f17feac36e536942dab1db286d566e6db7ae0e54bd1a7bb01d34e77cdbfe60c85c4ce1d8075334d2c92d51cb50f09
191	1	415	\\x6afe0d52e19ff8b36b55e0187eb12ce1ab3fe57f0e51e0cfbf4889b06fcc23c5fe387657bf37b13da643866b633581bbff4b7b9b901af98fb9029a4d7bade901
192	1	9	\\x9864d39b89539cff7a11b22eb2a8481f8f8a60cdd5c2153887189c5a0a7c3637528173627aa8d36d365436055fa86a8ae6cd74ca102e5502f1a0027b9ac8c100
193	1	405	\\xe1de0ca26a0953c58c8d87857cd7b16551457330c626e6d43db74ad9c0338bb8586b4db15b9e917e3d51417736bfd51d25f64ed912665904850e5b69ed018f05
194	1	208	\\xffe992797f0336147e591ace2686bddf4c882a0be57254c8b18e7c1bdbb9ff24ea2a0724679e8da35cac9c17e883912984b33275d07f4a990393c74ef3f7dc03
195	1	389	\\xf65093921140f54c8f8ff45d8e792838ca7e46c9c12fdb60391f27eff06991fef5b8b79b95ca3d9b889d77e0e3d32315e4a695427754245ca310ff010fbe9c0c
196	1	285	\\x5d06af346abd3244f20162186c7cc11bcfae07d464c74fe4c28b0be742fb6fd2d242f90daab91995b5343aa5c99b0ea5965974188488e6fda79a425601bfac04
197	1	357	\\x83ee09c5ac5074c37f46a1c9bf5510bdda738be5381f2d2a3487f87cac2e6cbf2adc6491a0781b4e946b2f48501940d24668e1742a1004222b9f42a480befa03
198	1	5	\\x6ba02a8845ccd887798b3bea6f54e7ccd957b4e4f1f11024a6eb8127d75dcdb39ddbc21b567d3fa239fbc0d9fd7676515f90913ad9e3bdab14b9203ff6b86f04
199	1	20	\\x838cf14519c1f764921e33afa343bc012e685be5bf50dced15e4086017789ec2533e71e05b6a73990c95573514ccb8c5e027b0597f43c6abe49f9ba8792fe20c
200	1	56	\\x38980207fa0387a3c4da686ac9056d77df54540c9d2278155c9eaa826947e4664fad1221e736f5a43ba8e40d7f8b6db60d0b2735de943ecf52c444878dbbe705
201	1	281	\\xa733d1c9614ca4f4783a55df313ab432aa6412894b857a5d998c6843abda22b76ff0cd2ec867796562046ed1ff369a27f79ab94c049d153e37ebe09941c7c503
202	1	368	\\x01aafbfadfca0047ff21b26477e66300db60129f544527cd4188de0a6dde12cdc635550e2a8ee5cabb45ad89d8e4cc8b29ef14d569011b6760238a570685da0a
203	1	99	\\x8b68619b8e7f6fc1eae5f9b1e10ae4043506379aeb57dc1e9473d294e5d896cd6cd71bb71a9ca8a954cb8827006d29a688ce3ac8d7d1feaf9a49de3d43a0650e
204	1	386	\\x2eaa5ae25d104b146690552ea002db9c9fd510dc4c4d5449d137b9765346018c272027227476172fc9d24d50c4c578da1f23a3f08b5b597c8174cd6c13d4430e
205	1	14	\\x45be4690643ff11534432f0f37fef4a0c4739c4e3b4f1831431d5502e3b9b4b0eeeadf963cb7adb2cb8d9403c11b6b7edce55c44c38470278ff43d795d25b505
206	1	82	\\xdba649c9c4120390b8961b315aafe203ae14d73052760c4f4b87171d2bbbc512a2c791dcdd7260a228cd74fa6461262fe92f2950bd118102215301700cc8110b
207	1	244	\\xbaad8574d128e4f53b14f92ccd73ccca7bc529aadf33e5f734d1510db28fe0cc0f2c64b082b9527030b735a6ff700ca199bea7ca18cafb8ee75d170ab3c80207
208	1	391	\\x855686da484b275c7493d549a9261b21e9d793981fb746f2e02a1bdf6bb62af8fedbf7012d06467d3f87502247390607b9e48d787f1ab4c93996e0f81d02f70e
209	1	255	\\xc3b51146a7b2841287564c3a48ce38a361b0a9325d70ec5bd585323747eafcd3fa626baef13aa9f37bb367a69d3b7a38ad5952fe72edb2c8a5fee181c6389806
210	1	392	\\x4a04807ccf4e6b7dc87a7944a76416515a5544e2577d3aae23897365d06d59a1cedd0ed34faae1ff1569e920731db6b39adbee773eb762d632434ade725e3d04
211	1	252	\\x95bf9ae6b4acca714f2fd69246eaa6641a51021b5cfba2df41fdf1795ada14df21f608271046c58482e89b07820dd139e1abc85f82a371b3aeb26d4c1d16f902
212	1	10	\\x4e143d60a7eeecc995894cfd93f9a7aac43bbb4e112469962671678af521588c17c244aee20ade08012f68718a63f75e08d34ee4a9bb478ede26daa976783509
213	1	2	\\x985a1d2d104fa39b54b5084af155a04f1e27ccf708dcf0faaaf3f4ad7c76eda62137ec378a36e4c3e2c0b58a83ece071bc3117a9e06f3544e69703af527bcb0f
214	1	139	\\xb13f8e435c7841acc43632f4782868427c476fa243cfd5d670fa986879a771c4bbdb64f15ae698cc6d593a008aa211987494d0dda9fcb365fa356d1f74781409
215	1	409	\\xedad63e4fe9aba08c4562155186bc7a3d8201b66f6a9bcf0e042a0adebc133280671804b9db1b9a57eef5068bca8fb5be645f31e677d452fc586e4168d9f7701
216	1	135	\\x25359c0b3f3f11ed33760951195ac598cbbdcf909507abaa88b8ce136473cd5ae64a1ee6b792eb4e40158da6dc2f017f43686fc32550df3c7e27ff01e591640d
217	1	337	\\x827ac651a6f8044dff928949c637f5e55a87b0d45e480025db4b30b5bce33d1ce629d9097ae358c21f343b217a27ee43589d701ea2c83fd57c8a2e906ca47407
218	1	69	\\x0d8722d8907062d1972b8a0c6309b7496ff4e3112c8200c6550cdcf2eee95d2233df7964812d9c3b499cc242bd50d5ac4b8a3ceba2b7a3acbcc616f626fe1a02
219	1	251	\\x3fbad0676b12d12b092eb7b2d648d6b74a609605b6e4007968fe9d384804760ab2d79005e5c279f2900cb1c5e8af7e31d5b73d1c5c18828b243afcbe0537090d
220	1	93	\\xe9cc92e454eade55dd555b9cd12f80497bea5df9de1a632f330593a75e36405a5381d9fb331fdb330d5f367ef4858dc57a342280f8da6bd99e1c2a856f2b2606
221	1	320	\\x237cea32c09f65f3782df2186102e2c7c2c871b682ec5c2f1f8ba888cc2bdf0dd184007b74e33f4c81fd6c207a07ef96c3f87e6091fb366a8780375ec866bb08
222	1	403	\\xf3f1e55bfdaa41a9745f6e2ba270efb11809d4fd545c4822921fdb028408a641d20518f5485fc3dc2a6cd389ed65f721a39d00ef9ecaaab1b39e28c4c3621208
223	1	191	\\x7921c4dd94ae6be332e42c1d4c6e85877c5b322fe9376ebcb0572e40991fd80f559083a1686fb2204c81a2fd32dae283014da8e4d469769a96968918fbd86b09
224	1	57	\\x138d38bd43450bef5633765235313dc4076ad61275a441b1f9776d1617c0d16dcef4a3d18d4e97d905542c901c390a4b5ff194614a0576e0e31cdace36fe140d
225	1	239	\\x53b46fe9fcb5f9e0e9974018d6282af3fc4f67aedb0c6a02eed5e2f1a720af27c9e1406138987b93f6f3d0f97af1bc39eee86dadbd60727d9bf9611a1b50e90b
226	1	36	\\x0ff96dd29bdcf350ade09d8361910633fb05b077a8280591be063cbc22f4cdc5b537e0ad0be12c971ccd0625c16051c9797d3eeb82207a67aa530aa773a2b001
227	1	137	\\xf2517f513ef5d056a3a0f43a0de778ac57214df094f04933bf95b901e11c31f8b7df18deb8198a022672f0d7712386f5610514f6fd21816668da766648d4ad0b
228	1	292	\\xab2b3674b41d3dc9dd456b9efd7d104a5514e2ccadd8a9285d314fc9d0b82bfc93a9b305d188b3dd263c157d3d91d92d0148f792aa7f0a8e32c126b6c579050f
229	1	123	\\x6bf48ae32a44780df7fac63b06511926860210ee313aba6965da80bce2d1ccc7e1eb00b79e5e54f42fedca9a833a814fb74298ee763a4e3a59d2ec8f221e1d0e
230	1	331	\\xa71cc9061d6ab282d78eb06e92590f27444209e4c289820c44b0b7ec630a39afde9da692b312c6dee9558b090c77be88d40dafea3dbf0ca293aae5469297d309
231	1	184	\\xddb55908efd4aaafb227bf2a3143f8fdc84f5351e472cd7268e57891399d217795d7446edbf030b6659004c690e4495adc838d7877f688a0a123e738e4ab9904
232	1	68	\\xfa90725ad8bbb46e2ba9586378db751204773a5ed4f25e95a5492a376c024c0645184e0928807357afc96c66d9d05a6f6a647ab3e2a7f582c6544876ba871c09
233	1	26	\\xa42714ab8c98f29827526d9f8cd157cb8acd1cf5490e2b2aa521c150aaecd8d2231e411db8fdba78e95950dbd2f3ce8333773d84a306783017fd61c9d5558d06
234	1	225	\\x53a9a667c76d112acd6b5aa205bf29e55325d81e12501efc384d5d9c3bb86fec981e9abedb9f8d3b4fc42a42b64c860140a32aafcd3093fa729ee01b8b810c07
235	1	358	\\x03ae18c8add5ad0a6bd0f1c484335d1a278610d3c3646d72443506dd86a2c88b71402ad99f87ac04ad979604afc6c439ed060f8a85ea4b52355923dcb530aa0e
236	1	404	\\xf71bf08d01c1c5443517c230d0133236cde68b679a310930f6e7e69b28964e441616f98e19f45513b28c2961e8df53bad3382ff944b62b37060e1a40b1ef0d09
237	1	376	\\x3c6e856455c4359f13d6542fed5347ec24d6cff7093ae1da0db9bde5b1c8f2b1fd4d171176a681c8a29d9d5cf06b9ceaf22d4a73457a4bfe8807c03532508c00
238	1	194	\\x221fb0e44281daac8e3164b2d5885d04a85132f118c6cda9885ce7bb6378cd23565279a2fd8e79e7336a46fc8c90b23025fc74366f4b877685eabab6bd5c960d
239	1	165	\\x952dc81f20887a712be047b9e78a0a7976460b31b2610e1068dc234f4ea230d0253d31e0e049353669b40c23cb2a503d0b749409353e86d516f13383e359e00e
240	1	390	\\xa49cea222ad1529a2d2d43ae8fa32bc19019d85276fde7353d05e9ab59a2cd3f457081ac1b00f476434fffd79d8af8163d9b8ad8501e43d67be051d23225090e
241	1	265	\\x51fa31660c823aa94e2c9f7ab842c689770c48dfe2cd226ec93976200e6efa4a2064bc7b9fde65f28f5597fbd045365762b62f089783251f7b0a14f5536f3e02
242	1	299	\\x0b734e6f44853b9ce0b4b57f2caed4ee874fc46ff4616e29feac6a2c1a94622387274bf4fdfa25b49a6078df8ad30e3b32d35884234c0d120b84249a228cff03
243	1	127	\\x8f35f7f9dea530eabf5fbb8c53c6e567a8a507f61c7b650ac4db041281646a7fc1db4a2c33364a40bd62d83f1ae1ac874becd10853e2248371f57d1062308208
244	1	65	\\x33ad5018591be99f333ddaf5a3950a8b1b869fd32b1e93c79dc43ce6e49377ae256582b362e673e482f740bfb98de23bbe4af9080044ecbb62df645bf022810b
245	1	30	\\xabacd669ab9343594b6bafeffbb0296ab416c20e6ddb380e069bbd8da1f1a2777e7ea709d54ae94b657d2ef76bb42cfe016f625ea8cb256e02043086a4fa570e
246	1	52	\\xa4ee799372bb9307d376bb37698c6158bf12d7f5b5e4571af918495c53f8e400bcaef81d38a0dd4fc04396adb845ab4cfad3fcaf8571725c3044eaed9792740a
247	1	3	\\x501a1dfa801986876b70ba24db3d82a7c95be762cd293ba019f818866a95f28cb0894121afc4e36a942e3b8e47b0307c1fd2e8d89c590d4d81f48f2261c1d70d
248	1	4	\\x786538d7a08ac8116eb9b2eebf41bb1372e768f53909e70e3a3d45d36d66d912f6bb102f13f0e396f244be90787c781904ca9a85cedac3e269ef62065a4fe305
249	1	267	\\x9fe6249d733a3e8d297b586d6ac8e3de3a9416d6f56bd55632ad8a7794d99d5b3beaa83bbea31287ffb126cca486b0ab5e6705e4858105bc7b4e1d19a462fe00
250	1	345	\\xc6b0a6b429947901c88c14e630ad54149b79ddc68c4f2b52e550aaf6366a2d9061b2f847643acaa12c78b2bc19ffe89e5589a7efb5e781c5ad32d2ac2d9fdc06
251	1	342	\\x3ada9ba484eb9b5299271d7a1bd903f7aa5977c512b79ae97e25e41ae13e0623e1e143bbeb98e16841a3b0f41756581b99ab018929ca007cf68b9d3487222d02
252	1	418	\\x0f732bbc955a4a7f1ff6cf84777cf23577d40387fb7230e343e1eb2ff4600fbc444bf10c25633f5de279980b739f700948a8226122481ab0659d5e8716816f09
253	1	303	\\x32ee31dd1779875363eb3dd03df59bbfa1711a2681be79aef249eca3b502c252c5ae3de78fa13c175313731e287be2c05cfc351586502f4c2b42b2231cfdd00d
254	1	273	\\x8b285c3f39d19f9a678be33521454bca5b35f331f68cd0e66dbe8eba3729f9549f2abf6612214d9871250e44c50f732676442f66f2c04b918c5e0175009c860a
255	1	246	\\xe07eaf1f98022e38df6a1bf14f3fe92edbaa9c9cd3bb1067d4f718e0019161e15b872ea8c62523d2f02abe44d5e71830915fdaca6f92835eeb8630b18045a105
256	1	169	\\xfd5798337fa310c2b1cc75c3beedca81d9ef0e3adca56c2d758073e6b37f9935f50475dbee39dadaa24d7c50c1961de018c0fa277194d21f7775c6ecb1a11e0b
257	1	46	\\x440434d3fbfa87c611ffa594205c131d97aab2dbf4786ec1fa93a9cc93045064c2d880bcc8896792c04649d10406e910c317cef204898039456f220acf870c09
258	1	179	\\x02b64a4ff12e779e6ba9fcfb3a027b3a527e173f83712d7714cb8c58047d96c6dbb8431f4750811dce46d3cfa568562c9be1ba79ffba33baa4249b9cb069dd01
259	1	214	\\xb9e94f3afd6de63e2ed589f047286acc1fcb785d1fd718850c34e2ba0fd6c3d8f46e596061309554a3f4dee6ff767677a8f1ba9ab4f4983e9e47adb5ca864907
260	1	243	\\xe0be73e9e07f267419c223a2c1ab76b85eaf0799c343496f50f6784eaba4a4eec17d47966233570add5bcfe1e9ad595d1c8d250b07821a91799bd8658cd4d505
261	1	146	\\x8c6545942bfb15b4599c2da89c65ab6573389b6408cd33855e6e4c043903805e10ec4fb95101cd4dbb4701712b31ea7b9b1eab784a526a124b5f5203de74ca06
262	1	256	\\x170a73bc188a1b2eba3c53871075848e4c2642e2fcb26e4a38c10b8029ef0848ef67bc51da3f82d775708811aad242dff45a80aca04af5c4eb31d5cf0b5a320c
263	1	302	\\x09ab95a37b583979560de67da35338b7779a7132c45f87f77514ab29c97f12f85b739c7134e30c037b0155e882ef2ce016c0e35c9b9ff245930f67a9914a6c0c
264	1	271	\\x4d43a30463cf73f7d0192660e69d4dc0acbbd03f774325aca5e85086642240b55360e7c4726330d534adfdc32e229bc6e03af49a255e40b8ae42cfdf595a010c
265	1	193	\\x4ce080b86e6f471ab42c16e950f204e69415b035ff69a63d2db4b15d5aea51bfc2377d9334d9de21577da9f93a51e2fa38809ac1d1ed623083a7a72b27194209
266	1	188	\\xe5fd89a3481a19497d5a38f98ab30eae4dfa2ee323dbe86c5ec0edc30ea77752b3c511eeddb71f9e4acde77d7b5c80750ed69723ad9fc05cdf1ba05bbb720203
267	1	226	\\xbf7622b3983cf58a052cd94a120b427cfdc64d502a4a9d92c01e2c11f91964c043183aac2bcaf4213c3fa04b462a1aa4a7ed7d1f06c5bae815059b05eaf94f09
268	1	262	\\xdd8ad82f87853b190c32a05fc7a894e680d772788e0b57c02d7574880d1fd59b6924a2604100023cdfea05241dacf4645c5c8466fdbe61c9023affa850be4c03
269	1	312	\\x40a3142557fa7bc492b6e08f1466ddc5a731cfcb75775d0e20fd9ba3d426431d2c6a2c14fffe353fbe0492a81ce1d8c2d834fffd04318575dc75b570d9fcd209
270	1	317	\\x8d0194b2284f551641a062580449605caa7383894dd68ba0228663a4ef35f014eb50f7562d35b8df7c3d0a775f7b3105bf2979ac377625ce0ce84d019237b20f
271	1	37	\\x8b3efd35820e3649c50ec4c97b5734756776696eb83ed8fbcd72ef29c9b5b13f8c36964acc379d9bd4817ef8926d40653554500dd2f3021400e5e63ad322c30e
272	1	375	\\xc12ea4da1a3848b8038c5ae7c6dc89545cccf88cb045cd2d25acb4bcb18603f1533047abc09d18b368170b79d6ddc205521225e343fe442e98ff5b3fa2b8a208
273	1	398	\\xae5baf83f37bf45a6fe8f2ba2bc13358dfcaddb3236b31505fe07229fcbbbefeacc7421fba41142828c64e6b43c946df541b50a62b951ee38b8518e29e888405
274	1	192	\\xa3731c3b65dca5b119614621701238a207fc2a3253bc59a5c99d37cdcd431284953ea99d037aa6861835549aec8005e381cba7bf77d9a41ae909d2b9db3d080d
275	1	369	\\x8b7687e096cabbfc0260a951c084ec936011f6b1dc0613fb37568633ce03e43e6f645ff6d87668dc02167af08a52b419fb2f1474d70b868047a5d22fe61a3208
276	1	341	\\xfa7b8cecb889e4380560d67ad95a32b29fcbb2dd5782149622547c067ab9fc5392f6b460d001010974902ffc0d2b0463579ad48e714dd2fe87890444079c8803
277	1	166	\\x066605aa760cc3c052c353c131da6298eec0246ede50402b1f840e24647535d9a2c7c3a7c420cd2d6f2bf94cc0f3a084c8f2423acdc5d05d76baf03a0b172008
278	1	374	\\x349954873252335749ddbec3bf72b1eaeaae3c0319e035280819eefb6f1b3894aa062ab7c067d35f164a17ff38d8ac8d09a51fbc5194340f3ca132710250c902
279	1	333	\\xe760fbe90d95b7259730f8777dc8b6fefa39dcc783b4df0821abdfbcb130b15eb9391d1cf936f2a5ad0665d04b8f7fa03e9e0a0dd2df889b5975bbed2d309d00
280	1	377	\\x7e557bbc8d7cdf2d761da09b9268c256aa6fe7a39880a07b15be44d20d8efb611a0ac61602a969a83838c4d01bee450e86424b9d49975da9a97aa4c53c1eb904
281	1	364	\\x5db78a48a4f8e8809b5f0fbdb71ee2900cccad8c0e2d38342d68383291ad6ca4d3899281520edc2202908a1a2da57f02312b6b5f2119413d0cb30c3b07359504
282	1	161	\\x5f5915203ff572a922fbcf7683af48f61cc4d9fe889937291a8182b123a8605de40f1a3bfe76d3104feeabc9a0916c0ae2e4f8cdea047336d9c14b0a3f594808
283	1	202	\\xcd5df448718587a08ac8e427abd1ffe7759907fb43b2f81920f7dc715df7362b094857d796f414773738752a160531cf350975bc9afef897a4830f2cb053800d
284	1	280	\\x2a6b790fc7788e55d21ea096710912277622893a32eb9b8942950e712e972f4d86ca9cd2eb047b4f0ea79ce9dc54cdc9122966fec68e29bd575f6098377cd107
285	1	108	\\xd9123d993141be919ebdfc8844f4486e1c2bb37e294a0ef4aa78384d44cc3865e2dbfb9d95b23229d489d855e3089e5617c7a220da4e38506dde64cb878df40f
286	1	237	\\xbee13f23671137e2e7a978b9b8c6b6023ea3c5a6cf91f905755e999482ee578e8459a5131c5c0ad820863e5b43fe27bce710a4e8f8a653313168c7cd5000c803
287	1	43	\\xcadf334617b11301928297816e12da877212b34ec5847343de04722d033b095a3cc2fd9f0b51f587332d3b3ce71925f668668e4c932e8df5015419e8a7076908
288	1	44	\\x561c7964ca56039501c08c35d44b30b7d9de3b952de5b06fbea45e64576a15aff37b3cb13cb1d7f66666d3828750591f52c141a0c85f073c464d4ea9c7894309
289	1	80	\\xbfba8a86b4810bb95c75a652135b37c3ca2b68112667067cea40aa2e2cb5e3c098166dad1f7bff3180313aa8cbe0ed4aac974c7e13b782adff43a75ae448360d
290	1	328	\\xeb45d12d5a243ef9e97e274b2a6b0cd81014c603b1d2f5155393e9c355da9205b5097270717e7396f6071373c4397dd5248a0b59fbd173c00abc87839f798c0b
291	1	417	\\xd06058ad2fb3ce3c13c3a3ae7c57fca4d4fe46a44249726c081d16f87bba9cc77b761a8139f2c9ab8badda785ea86f2c6e82c29b5d439dd119fe320470b1c30f
292	1	224	\\xbd8a70a4a74bd2388fe434796222d392ea1d5a492881279e14ddc24cfa0a25d6092dccd38d610797c8e1290ccba854745cfd8120e463b01a33294c792546790e
293	1	414	\\x33717aecd027eac8592abc643d387c16042e35f6dcb7b84c1d8fe4375d0a5d3f43833b5db91a862b00d9795474f7a929a9003e483100a59ea939afba2b2c3904
294	1	351	\\x7e05aee0d68ed073aa138f9856e0f076c450aca9669a38e94b33075cd8b34cc191a4ef08bc518da88377b249600ec902e3aef2b17376b61a3e1f1675511b530e
295	1	395	\\xd78c9f72013047aef192d91e7267f5e75b7379eca47839237655bd4d73506ef42c0a82483272c13d7ec385d8158d00c9693e5501107e8e4445ed8f6707f08c02
296	1	286	\\x2492de3d46e655f73e03426782e3a67636f8bc7bd5b6a977b4d4baaacdab400badd5dde1eb3d6fde7f66a50a584d47ec97057c8671a14003310812a9e992de0b
297	1	250	\\x87f007a3698f0d813e8c3154daadc6d4a7876ad90e0aea5464ff36b561a3decde6e8bf3ade425cdf411f04aeace288dbf2a225252f9c1077dd8c2c11c6669104
298	1	48	\\xba3d501e67b70250adaade6fa415e3852a52fe45ee6da3478672945474dae786df8f2a99116aa934525367ca1a0bbe2497d3df7023396d36696e8e506d3c3b0c
299	1	407	\\xdd96ce4288f48856ac973be29ca5279ae9a745cff8c32ff98a2702bf4b867b7e0ffc484d2381e4f2c3cfa4b5d154946fa0db1ab4556dc4da9a156368ae683d07
300	1	353	\\x705f89a15e9fbe8b34e1f8582eab201e9c3848a217e833250c665254c7ba1ce27f1542e4576dc0ec004f7dde1cdde10512c3578fafd9bcb6e899e81b3bda5b09
301	1	247	\\xa3b592edb1211ebfd6e95b57b54913036b65944ae9cc69634d0d76f575d52b4b7bb9c25c387e42baf7c95b5b5698b149b73919a34776f6be45f8b623247d9302
302	1	408	\\xafbbdb713680d27d1172be463e173d9bd070a14df06a930b7cf20bf767e23200b4867a2f2c90e07db6d32138d2a4368e51bf13c4d6c55a9d73a94927341d3e05
303	1	311	\\xab0ba10cc67246323ab96879af5a3e71d82a0736311e1285966958a1832bf85533c0c63133e4a17ff1d84b64562c5209848fe6a727f2d217ddc64716349b9306
304	1	96	\\xdebd2a369bbf39a57b316cf47509fc9cec7b30be47756a80042349c692c6ab4bde1475681976abd7ff612d5921f69c75f4df257a5c0b798ede32f4e6addc720b
305	1	144	\\xa599390a45933d73eae7d620bdb42f7e732d54dd3cd2f6e630de68165880a6a7e83c510fd5626cbe6ebf3eeab4a5deaf33a30a9fe0eed1204d38e99a80db4006
306	1	235	\\xfc67453b8a198589a7057720338b614e4e8b8da520c4a8ec0f4c33a3724c4af225dbf65e063360be79fddb08edab535c5fdde5ce103517094399530999654a04
307	1	205	\\xe1436ba6b83b647ca638ec189e3e7200a455145ed792d738d2367894f5f747649474843c59815515eeb2d9d52e0d7e6e0beb39a91a5d1993abc0c0632e61aa07
308	1	131	\\xd001db3f74eab40c044484bdc9a874f175f4254f2a0f3af6492e234048b434f0190ee5a59098ba0c9c98642b715bfa1a5c97337a7b07c05f36a44bcd55321108
309	1	422	\\x5f760cf8ddc4a475018e7a0ff6b5de59b365aae9e76dc872333c71dedda209d320d282c154505ffa42a6425faaa45ff4c1d0c58e2953e698819d8978eb81420d
310	1	8	\\x507d603ed3da80da8e01c6deceb8fee19b33a8c5e5904a0d9abf8b208213bc523f8590c5dbddbbb3f6b0494ec6a91086d65a63a1bd8b2ff2c70bb75c6fcadb0a
311	1	296	\\x9e00628f94e344b90d2fec7192816b41beb42e90ab2d5b4c1fc17e2ea89ce27f25eca1cfab032669e359dd88c79b8ddcf30a4a3a53bd14feddb31e8771f87d0e
312	1	411	\\xb64a4d78ddf3e07f208bb1f1b86e31da20e0246f435fecde57c5fccf39670f15d1bb1577bd4266486af7b2d396e2f65a2e74d4bf9b30502680e7a5d7d2026e0e
313	1	306	\\xff4e59abea3d3f1825fcc3aae497d2cabb50e42204faf76c87d129a2ac581767c2eae1ba747815e1d5b78645cfe4b623f4feb00cc167a0494b0f749dbd8c5d08
314	1	61	\\xec121b39ea26675641d2649a71f0537375be78571982d6e9c278f132c84d26771021ca4122ab46598472d2e6199db9d5449ad7db39b00e51ec14e11fe9b90806
315	1	105	\\x98c8552399dd0c9a6a97bf5ccfc0063a0a47d656e1c1898a6473054751649146993adaf7c09401dd94121237841a4b3e14aa1a2b50d2663692553ef09799390a
316	1	348	\\x5e55633e0420c8856dfe708fbc1c2c2509ef70d04c708147c44ea6034d39dd04441c4081362a2b8a0693748a8fed5144f641a7960eac8ac89ab78dba0c558f04
317	1	91	\\x30e80cdffd1b86cf1877f408ac06460d474db63b0399e920ab06aa67512cd6af7725f7cc83d5b89ed9a0977deda2cc3baf8aacf279c6e4871ddd744845105a0c
318	1	97	\\x5730440f566d44b8baa1b404cd51d8278d6c6d8219272c2b869266cf54a1f287eb29914e024e24d3edac78066151362115db037f0fa89ddfd691defd77382104
319	1	213	\\x2795311f8f76dd315a9dc606edef63e2e43298b73fba1548749956eecf7add27cc1d48cedf2c0efa2a0bdee94c2520a035beedf2a746160178b8390414633e00
320	1	290	\\x5745477709bfa2e9d436a38e4bee99e4e3ffac076bb221fa630ae0dd400e7ba16c95c06d4b2d470e81a44e375c48ec431bfc374f4f2128b585477814213e7a02
321	1	399	\\x34b0e7815b612c4c169bae86e2bfdd782e834bda530e86735d4a94de737bed106830ea3954af19df5a82d13a1c81669084536f3c4b45978db65703c1e2804c00
322	1	200	\\xa501b7a75e9a1687ba9ad5978a2c169e08881a8b7dcdaf3193845980d3cfac5cc10eb49012289715fa0816afe52dd4bb6c510f232b130bdd4df80bb83a55800e
323	1	249	\\xde536d160774e35843b2c207de5317d72205d11069575e0cf373e9951ca84f504262d5b7167c141f6a292b8c519f732b2a8b373053da1f35d0a7d392f555e50d
324	1	51	\\xa36c13d0c5a676b11a03f5df76eda8b9e530f1cf689ef3eca402711452c55e223bb2eb26a46f93dac46361a2d4743e23f09370f7b05b86d0979c4d5f19fc0602
325	1	39	\\x59148cd9163cd83c670df4ada3eafb366253fde194c839df98f445f47bef8837448aad7adf8ca8fb805303fa252a1d1122ed6597c1b228690920a9360e60de0c
326	1	175	\\x49ffbd3369b13f936555e36432ce0b3d068ed200502274793e2a0f52e293fa3a980e4794ea4095468d932815f1f4a1cfaf4dbf8be7cfa479e0b2c5992a2ebd0f
327	1	55	\\x21d060bb595fe24a7c0483e62b068db871ae64bf9ed7af6097f7506f9c83e4eb398d946f076f35d971d0d95ab96eea2ebae8a672b9a809af34512b238bfa710a
328	1	234	\\x79b1ebc56dc135db2faaa57bbd6552dcb003e3e69a401461c19fc00ffc902f2610cf23089697479dedfa4d1517a7cab0f70e7b0ad3c679a6a5612201b9070501
329	1	336	\\x382c34083e408af3a04d9e2bd9e3ca957067495f2290786de177a04b23bd342e0bc66481c6dca187e9f7206483cd58822474bf7ca4af5413ddd1cc71f83e9907
330	1	54	\\x339337b27c3c96fb440895e0c09848f11fbd0f9f9efd4ac8d6cae538ac92708eeea813c638a6a29feaca71c36ae0efab50ab698b3b3192156cc761fe82c21709
331	1	42	\\x6b1c793aabfecf2e05fd78497c54b33cf56a0b10365dc731966b4a14739647d7d9ae5750e74fe51caad9740af80487dcdb01c46047d1819e3a715daaa42a330b
332	1	242	\\xc76b116615cc1037a3eb72ad5f5d9391324a2119ee4b0c74f76123c158bff9ed70f9075f65daca7c5db13056aef61e00000a176be9fbcd9314b3e6599a31b70d
333	1	221	\\x9bb042b4dc35a022e2c473f0c1b9722a608f96d9061dfe70594afcd7c74f780d0cfac43d7de9f2ae49ea0c9ba7f0872815c244c55ef71a26cdb98d7b929db10f
334	1	153	\\x5daed57634b029f73114e4102221d0f4c8b12bb28067b9fe38fcc6d3d732ab70797cacf5429b8c7dcd4d9c640ce51b5ea02243fe7416a9e96bac5ae5bbb30808
335	1	79	\\xa52e10bb13b566be1a49cec60854f6eedc52b108622d4e3418d60c90cab98eeb1190a212268ef92e8f935561ec6d7355da14de57f6ab5d7e01c7c871d4a6ae08
336	1	346	\\xb199ab9e49dba6b66d3e3f932a3d89f9f9211b7e115f78d4002cb04e37bd145b3361361aefdcd4afbc052c3b761c0121c983ee772b480f408853e77975b6a202
337	1	50	\\x9fd283fcbd2ee60e216d32b0cde1c2fad0a578c96496f7d1e366ac8e9ad240a8bf4a9fe79bb412bef9e61c7834042f326fb79f280db6b53cbeb25d867c39440f
338	1	6	\\xb3ad98cc655982dd9a8886a890a685136411352c5d750909eb22d562c48cfa4de819451051c1b09f222ec9c13ef5f55d1abdb7c8b889fd41c58fa058a0e14901
339	1	38	\\x5ba944d20c16f2a3f7fa73d5a3f5ebf7712d6d5a3c7ea19782e39174e0ae802810fff1b0711bdb83214c53d21baed62ac55cefd67ece88d8f36e9c9dfcb26f00
340	1	173	\\xcee481add1dc6116fe8a32b0a71cde687d1e049a82bccb0af8a744ac4573bd074620bdd4ca8f4c351e400568d38c8c08c6af407d44fb11bbf4bfbae34cd6cd07
341	1	240	\\xb8a481c3a5084d2f8db7ece2b86eb061b68b57f4f8887490202d53a834522c2405b3d3c9006f3073af45c32dafed79dd40fa48dba87330f75ce36e9d40bd8e0b
342	1	238	\\x4eea8a044972753d1e5f3fc668460f0892736cf5aa13db818bf959783c67d3979a1a9376bb421ef8291a91091f404670f301624d96731414de8b0c7690420b08
343	1	117	\\x947c0e4e17c6d88d3acef1adee9eb2270c795a8cb96c38f0939962c75d76cb19bfad9ff70042f8c51a82620654d66c02c3b9657fa7205ea69badeeebd39cd809
344	1	293	\\x7c89f70f01aa6b8fcf88b1cfd1e981c9e0a18d1fd33e3b394d173e549bd5f0eb0133ddb30b4482f64009c99bc069566c69b1e872507672bc14674868b9b80c04
345	1	164	\\xf5df9e5651c2532e207395fcb76d5f6c6634f3ae9cf66171b285e6d3239764edc87897d362da353da47076a151995337850bfca3c68cfac16385b06f7dd7ec07
346	1	95	\\x82c0fe890fe6739ec953c519cb782cf39d3c73808188861bf4a05ecbf1f9f37c3bc079f67072686bdc1d50aa26132d84fe8d23ade15dbbfb86d4708158463703
347	1	378	\\x1d17442fcbd1edbc8018ee3fa7d04f8aa686a955b4bd008b8eec0f5d02977eba7f9f42cb703db10ee7381c8767ff580676f087eadc4f6e1815ffe78ed9c33104
348	1	1	\\xd6101a068469c178e86c6664858bb4b8687f533bba84914fe45e2c389c7894f9e461d4b515675a957d8dd4ee10910d13ea5de793b1c2daa9d13ef445a4af2a0e
349	1	339	\\xe48ec2be6b734e5824c11e78be0aeaada8258351f4e11c309f125cfb41c1dd8eb9a7f76d8ca8b0a2b2bf03ca81dfd77d89c401a8cff438e6f4ac12316c73ec0e
350	1	157	\\x8d0f3bd9b54939d5a09d3fbc32cd347529b65f3db7cc57a7b2b8e6fe776df704fee11eebef8e262bfa359759fd660e6f86fa4c982577f275826c56436e5fcb0f
351	1	189	\\x133873343a84e5e251a20c1627ff9eefc84331bf3df28fc5a425a993003eea8985a2174c099da31a1c1b16d1c442d6ba08a39439c1fefb2d725fab3bc020ad0f
352	1	215	\\x995dcf353aeeb4b484ef7b6be7070c68546fc7cad79758179c62add3abcdb40987062bf0bf11152ae46d50f4a89088bf091cc77e540b079b6070a2ad5ca0c900
353	1	366	\\x7b1df9e59a441e0b6dbc45df9de0a8de54da71256754075b7c8df18787d7a1f01ef7909025221d557f919060297fa695e0ef3344e214d647f4a60ac7bd44e50b
354	1	315	\\x6f51cf8821339c8fd08f3690b1e53651379354940e86632c60e3db495402bbfb593521627b48fc4a6a020f5c20695edd86494a02eee778c165233b7abf04de04
355	1	332	\\xafceacadb107ae687f3ebb94a7d87e4e17b28c5f4ac2774b8642188a6cb590b8245adfba8201ad11f95871b3507df1004b77d66d738e7ccd13e978072e86110f
356	1	361	\\x7cd1701bccc29bf1ee57a5db288a0924f088c63e73726375bbf02c71c0fef31db6ac555a9997c7d78d1d7b1eb58d1e3b2b15a6b41f0a2d2104366bcae5c03b0b
357	1	232	\\x341f8fa069e83aad021716e8ed53c0044086deac022802ac567ef3d670df70bffb18db4642c1cdd247d3ffc996253d16ebdd4add26e986698a6826a5cf31a101
358	1	259	\\x38457c1102a05134d6ba5978393c7e16f3a195a61045b42a1cb9773b934ea83d893b8dcaa511fcfba46279d823c6109a459924e93905de7d09421644f8d70f0a
359	1	162	\\x98bf85b01ad7cabd3ed10d08d7658bb9cba9cae07fa57dfdf499c2f3768740ae06618d38790d2f11f738d500afe948f0cb862dadb78206bd0cddefad96fe0b0d
360	1	308	\\x996cbc4d791575b0100f16b57782f22cdad80b10c25c1db5284476fd0bd13170933c7e54dd5040c077aee7f04ea95a533af0d06f9e5aa697f4e921b6e53ed80f
361	1	101	\\x0191792482134616040a2e6bf585d4af1fa9919a310b5229d9ce8114d959d161e09fb0a873098d71325a5cbd678daa7778a6c4882439cb4de035b459c1510f02
362	1	151	\\xb9f40a28a88c2d740b6a8609455ac097eea671687952f1cb1bc678979c2a0a8f755c4f7367bbb0ac35f4d3c3e1ff22d01575fcef4850d54a84fe69e06ac2b709
363	1	304	\\x9a7d7fb77db48145586ba29e07ab1a7527d30a1bb243bf4ed405165dd7478946d55ad784e1c9a83b910bf78b8c891cac4f935a7ea1c60b0e515995e106429c0f
364	1	400	\\x85ab4e1eddfb39e4520ecfe9d323ebb94b84f29693a281432eacd7e75f8152a656e7da0fa809115f2a4cf5ce972c2c0e2a2fcb1f80f1c5a914a80e22ebadd406
365	1	380	\\x1d2022112b2c4f2d5ab63e49ed88ccce6d9263bfca246d676a44e61146fc9429fa353bdae17ce93a8b479944145fd05a04a18318ae2608c59457e2b5ce359105
366	1	132	\\xfee1e70cd060e86211b44fc20c6982d7f1df22957949bb22418a96eac063e3e145da62fb96ebe0642c8271d1778516b2d373f7eacdfac37567dda5227a09f10a
367	1	277	\\xfadddd1b4e2d8bc3c44891ba21bdcd059265430304e440a13d15fc20074eb15aadb67fd2b06ddb103b260885ee411c379b8a1f9700ff3d8b7e286d31f74e5a09
368	1	261	\\xe62d9184c68a37f123673b6f86f7f347b667cfe39baed991887b522da4f3c1b1f8dd673fcaa950288c72eced19eddb6a97e1a3e73a51dbe260678c8285990e01
369	1	370	\\x337b9de3c6ef3ae45f8d7aef5050791ed342517170290f86587d9c510e95e5abfaba518de66a1ba6914b8e1600621deeb5a018e357c88d30f7c86545f38f4e05
370	1	420	\\xbbaec0663e694bc7a726f0a8fb8689a58dff779bc24db3ef40f2cb9154804bb403802ca7b8a60bc4ac64d98ea8c4a682b3226efd738ddef67eda78b7a1250a0d
371	1	177	\\x1c4202c5152f1b902b88570df615bce488905436fdc85b78e9503bfe39e40bf70fbd0643330f3035013802af065d6e1773686920e7bb620e0935c70ac7b51a0a
372	1	236	\\x3d89e773aa796af6c3140e226930b406b7d618ee15d363e715084492ddff2810e1f847918a5a6044973a8330f2481f1810dece9891d7e93c51dc7ee474b53b01
373	1	359	\\x61847bbaef7d4dd79cae3e441e1003cff0ff1c7a9c2b0428e715b75dba3fcad2b43e5e48d558dcbbd55e59af3486baff759ef42f3d1185849b9519314770e80d
374	1	406	\\x396560276e0a8a019670c55924d216413d9e116d5a4f0c6faeadf3596f9463e42f6c0a9328db6f2a8330bf63187ebfcbdf23f9945ba0e7da82cc33afb430ca06
375	1	119	\\x7866fb9fb09562d99caebe25f97e67c531d38e3f4a29cc18d78fcc8bca3ee7895a844425a47f44ae51501b5b80fafe2197ea0efa8fe18e85417acdd33a2bcd06
376	1	185	\\x9f7c582afbb92cc3e71f857020bb56384444ff23db0572fde4b1335c86ac5527d61ff4aaff0d9f4a5c3904328218e932a90e20ff310f7b766a1b7e0dbe820f05
377	1	103	\\x5935e3b19582d2120830c75883b6b508a887f3fe03ae35b7571fee39ab1c3fa9e6966e493065bba5347d1f2665730c1a00fc302e99a1c3d4c8e43260aa2e4f09
378	1	419	\\x303c2e52ac61f88b44f1dae7d90b647f6b09c00bc6647c9f5c965e923bcfd1b7e3869195389a9c4a1da90690a3624503251fa23d0d12d3811cda9bc9d5385600
379	1	355	\\x8a91593457263789eea4c05dbc4995e7ede0b21b4009aa6203ad7f4ffe1733a2a5387b16f5564379ae51f2c6f17d735e57243cebbd17e2460e5e17345e57a007
380	1	64	\\x063cd10089638238ef2d2251628ded1260a5dc2df1491a4d715f53b2ee30813d9679329f28bf932447458d39b37fc807ed8e5c60be888d0a142e33c8d5c4be08
381	1	28	\\x8c147e1e92d4c0080bd64e7417bd28398121f614d535cc855050be17cbf1385010ac886b7f66b9ba9f8e8374c6390a21e4804d3a4b6ffffe45641d7a4648df0c
382	1	94	\\xd3f83ae2e3063b651c9051ce41e7ae13bd88f2a6889ae8c9f1a3017d806d5253b48439274b488f2ac3c023f46efd7d5835130fc481ba77be277fd3e10c529c0d
383	1	356	\\xfabfccc62571fbb57243f0ea17ac1deb31f7f144750f15578a0914a521ab7eb9ba2b05db966b87cc4df31e78613164501fcd35996891caf09c7cdac2430c730b
384	1	168	\\xca9a90247270ff92f5840d71e63511414316777061c21d5ec65c4f21e5e508820f3d6e47cb7e1d7d245a7fe3f34fa3998551358522f925a51f79f9282672cc00
385	1	253	\\x6edcd94f0b1faf2874b54d713e27db0323a7d352ae43facf914d420485edd827c4826b81aacbb2043c84f110f0710c486351019edceeea954972cb83ee5ba009
386	1	352	\\x43a26c587ce160fe7d58eb77cf8f1c5f6d6eadf2d3f78d9e1e1b4b85e5348b276f147a7f2826354d58fc1b6857b2872e98b8189eef02d78fa4379f633b0e9602
387	1	284	\\x2fa2b9bb8f097e9fefc75122a162c6af9953cb0a00184da71ad117680f6ed442e565fe1427c7e506d203de28c2c20740b3737d59c6a2922b1f0b49e19444810f
388	1	217	\\xfba0c14a9e5ab58f70dffa0d6e435058836259a09166e7a5349601c11bd0585ff2785d2cec418976b308fbd53c9b6530ad2c0c15b8118e002adc21e32fb75b0e
389	1	354	\\xe968555f0181a13520fccd881cab0d99842301e62d79d1bc5d9282e123b003f1ae5d85fbda9c7a9fc00ef102e3e750986f9f6fe1d9c793e0d64096eaf242ba07
390	1	349	\\xaead43fd00968ecfbf1d32070dcb3c90905f99f0267d79bd113402929a16cea61071914492e390c79e856fa8b13a998b0ca729a88abec349f2963f453cbf9105
391	1	100	\\x765959ac409af8104e8a6b07d5ab186004384bb2bd90a6d5f8edaa0427fb090ad78904a395544b6ece683679e7f960bd0689e90eb26309edc558a3fb47701305
392	1	81	\\x0e9afaa3637a81c06cfa6006b92112e52542e3674d4eadaaa10e0b19998498c3a0dc1035ff15dcd4bdfd5149523005714879cf8647eee071ddea0a32706bb101
393	1	115	\\x4d9a1586f5768b076b603415fc7a1bb496506a3557f585183896372738b0bc99fa58c5652f418dbcc016d0dd5638f04ca324abc14d4181adba170381077b8f03
394	1	67	\\x97f53e1130302efc5e66e17e8a41b0a2fbc624c6f9ba3197491a9e95a07fb88d822eb96500224d96f4c1ae1d77da31df8a6a39a643ac23d8b00148a9cc981f09
395	1	307	\\x7072c54e699ed4f5d49c992d1cb10be051486e1473616adc77c2399d17672f29149afdecea318a9cbe01fdd04df5e92482c6a0fbb36ec52435be839c25694709
396	1	362	\\xb1de7bb27c028064d3ef61f76b9a14062323e2008b778b244e37e2400fca81b85c37c6c71427628da9cb5ddb646ed9d3ed1e8947422da3183a0a50aa86d60506
397	1	397	\\xae1f0bf9a4787a1b1f5168899a8da651d05ec7a5c51fe6a3642afe660eed3845976c91f09218905c50aa0842fbc708372be84022fadcf5bd237c75837e2c6f08
398	1	167	\\x523edda781f568b6b880555eec143bdb83c64663a7a0c3195a276f5f10ad59934d73ae222527a789e54ea518bd04bdecd1430da6a98858821e3014ec9fb2b600
399	1	183	\\x6ef02f2d51cb3646762556e1f9127b753b4885de0613a852641127fb216d0f5a24712d7697d8dfeeaba89b09f99dd0fcc360cc8654b35caea35b13473f661203
400	1	263	\\xbae1dde0adf4f5a8f2556c610ea0b600de1f5ccf3b2e8ab1bdd4c33f51372c6d156f76259f600f4767c3565a7eac557619b079e5e7cfe461a3954cd08031a501
401	1	89	\\x72df8e5a8581b4f2f43c139042b215d94beae20c607256c82722a3cee61488953dfa1eee1fd5d6ecd35b56d2c4642868a41d1f0a9098d82f7e89f84021446e0e
402	1	142	\\xd1cb2707b79588d3a7a5294f7a01da1af04634f613111ea0c93736afa86f0d127f93ed4e9ac92d20ecbcb4b8231ce0d0e98359d7bc4668b27a88e646fffac901
403	1	19	\\xf2ee6cb37895c608550aa50e3ce313021d5c1e4dc39f3fa884d2ace3acbfc6760830a09667c08cc4c6f1848d30bd4d81fcd943df8ae0d6008560d06c6793b203
404	1	276	\\xadb202472b5f336bf93c548b0f07108f00381b6e61ca382ef097602bebce7f302c16c77e91bc335ecbab63093d3300413e5337e3ef1be0b1f04ecf3b11400f09
405	1	138	\\x4edd3e65fededee8e38b0d1db5198a2fe8d18936c100d0377f799dfbeff7e0bcb2c2807a3076619bcfce356fab500f9a86cafa01c2d187ea8e42218741688d03
406	1	269	\\xa6628694aa3814a6b68895874a48e75951021da9c199e2811c6303bb5e0cbdc6394c869eaf2a1f60eb37c469f0e14580d6009edf11b26368bc5312ff8ee4fb04
407	1	266	\\x33e7b1f38694b56852a365b8f416712227c3b1bb838912b9a7f447e37ca5ad548b5f8f22fcb19febeec4b6757f8d61ba651f6a8d19bd0e51ddff0ce88f952409
408	1	11	\\x849428c044b211932acd47f634702f539af3b6fb2f4d5d44aaa4e40aac253a4fbaf7ebb662f529a4811293af7ebd5854894d1c4ceb6ea51cbb778c5e4ea24a0f
409	1	248	\\x56c8c14a264d25a20d82d21764a0277f30e100db8758117f8360acad1845f0eeddbf9125663b9795b5700a55a949e2e3b65b77e264cd2665e60374f6d86cf80e
410	1	257	\\x18807aff6c9c9fd189ed3258a93971b335af640b4aa23ca84e5433a21b12450565e35b0aed42a649df52308dfdeb1f7dfccad4033e034014b3cd732923bcdc04
411	1	209	\\x1c38f208bac4b61c747f5ef3722e4e1c1e3482ad0b7df6e8cd52916cb7b3eb249b434d80740c4d974fe4f511cbb8dab288bfcc56e47595af875b6e02d65bf60a
412	1	60	\\xe6cf0a02958de231f536422bf53a862612e2f5e3ecca2d4419691df865c498aa5840d875e7b32d5538ad3a5f49087fe9b30f40e417f2aeb3340a808e80280706
413	1	335	\\xb932c0de6657f0255cf8e5cfc3a538792fec951c66f96c0f7d65a1a4ed8cb6d8bdfa2f5706935442a91cf9db0523180e49b60e4447022e7b94cc89b01a446e09
414	1	106	\\xc6718af0633b65e51edcdd60ac07817a29f899aa954d789ad3d89026efff4fc1ac718bd1d6440c3f2b4dbf06dc5feecf905623e583a7c23e076c88143e12b90e
415	1	122	\\xbd54f57510754e21ba5e44831585ad0aec7d3caac91838adb869f8dc1ccb76c76720a8f001971198b30d5d6c2905b4dbd127e67601b31491340a602ce19f120e
416	1	59	\\xea44cdf4cd8f8f542b73ff131d5124d1af87bd0c8cfa99073ac96cc5b353d95a264381d79c3a6f02c749dbbb63191caa0726822bef8c4ed20eb2b3cbf1f37808
417	1	174	\\x4044ee33b41908d39bb59d4c8245515703bf87e892dc19b7d88b9042a92989337cebfb4830a024bbbf481f9da15dceebe7c0d6cc3bcfef54b4a7166b88768802
418	1	154	\\xeed6744d0e9067c664c640eaf2a028a80f470e66871bf50a361635dba0cabcc0dac78d852f07f46c55605b220319c663288b7acf6c0c0d9a94616dd4dfb7690d
419	1	196	\\xcf0e6a6c5cef40673cec8b4a1a28b2b191f12bbb3af7a0b9bf85aed28033ef04ad83a7e3620b5539520217049981f6464621490f8f05732fd921e6e124f72a0d
420	1	393	\\xd0c1374bd848457bf1d6f572a32197792a59700377bf47a2a7bc1832b8eb496fafe0893d8d990d801ee38ad5aad6596db803e9231110619b8a7c5a3b9ffb0709
421	1	310	\\x9b8a01ed96cc7d68ea680543a8db927091f00f5aa76592ddb91f454049d5c3d09437d6d2451ca39d76474abb657e78fde6bb3950982236566d95fcc75367c80e
422	1	300	\\xcebbea34711c3b769f1f3f33d2afc70c5c318fb2d625ed251e58608354abd2d624149530f1ed700b651e8e31165318526e382546f954892bd8311c407d4bbd02
423	1	77	\\x5941f98c9e95764e69c10056594235855c5c1d47f330913f2e9551469030a53eb8d767ae109205ce545b02569c30e55529d87fb4e37d8fd96e0abfc6ead2ec00
424	1	116	\\xd55e5c1562e7eac7ed1a180ea7f9df4f1355d329f1fcd73e482ed0afa6ee7ae19524758159f01179d7717806edc5550140594f326347a67c849cc59eaee8710c
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x03a36e178e9c7b6b5494b4ab051fe668932b08309eebb42b0f587dc3f392e881	TESTKUDOS Auditor	http://localhost:8083/	t	1660992695000000
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
1	\\x02fcebcb5e47c631c25b305342dce75c24bd78a99be83fcc9737c95af5428ef8a27bae1c51654ae641b1e088e51f70cc0bb8dbf290f80f064a0f060ad5a8a2cb	1	0	\\x000000010000000000800003b6e5846bbecf17c827320a3377f0a162e175fa45600e1f74e916b82fc57348af2b85ed57cd75b27d79902c156801954a442e6607173be0c7bd21079c16240ff7ff617a2d110979e1f719155a1bb904ccf34363df820045a6adccf166ac29c7150491ba8d5968f0809a806bfbdae814010a2148debdc8f63e87ca98511891e299010001	\\x6edad8d8df58dc7045de2cd3a2de5ef87874ebc5daa988289359fc1456987954b911f815337a095d7eaad2b7068e23435ce6df86b86444a2df72c8bb9f787007	1666433189000000	1667037989000000	1730109989000000	1824717989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x0660cd9ddfd38f2ed53c77bb1b59d240bfbb4a13088056d9707af0ad4c3b8340a64e33ed65c775774892750182e1d681ffcedd7d646922dfc737ddb6b14c9c53	1	0	\\x000000010000000000800003b0a1bc26bdbe3869c74bd0c5b1b447218e9edce2ecfbb4715e314db54465e7dc390e49e92aef78d280c164701860b67ec49665fff9bc11143c8ec553e059c9994341e150ca30c01375ce02069fff936934111f26f65a731a2915e61d0245a0916fcdca7871fbc7cb341eb05d42ab66ba225e041dff2438429a7fe5662534bf89010001	\\xbcfd3b1a5ba4da30f431b8c728507aff4221c8bdc4e955af0ed0c3bd8267fed99034fb8950ae201b2111e043378a8c72d402bfd330f00e98a45ffaa6e1783306	1676709689000000	1677314489000000	1740386489000000	1834994489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x08e42f134e20d79e17e55ed969f4865bf556f04f93ae3d23b6af012d5ea4b0922fb246d0486f6e5efa85a8f8a228c6450f276c7adb036525c11f060242722c29	1	0	\\x000000010000000000800003e12a721f34117ee2ef4bdf071e594582ad0f69b95a7c9e583cf79a7ac8fc6a6ddf4becb203f5a5c28480f7403aee767d804ba665f52145fc63660eab96243cb0e594528206da0d8d20ef8e56688384c3cf406c1f917207114a9f0211527fc5c9f4f50a3d4cab48020303e3f60573787b95925ff8a1aa45f5cba3b429b29a68f1010001	\\x410045810728c5410f8a673e95093473be1d3b5bd421577222a5e4528c91f9c38a6874d485def33d8820114e960db9c23551e90c142d608edaf5dd5a0334aa0b	1674291689000000	1674896489000000	1737968489000000	1832576489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x0da48578d099eafb8b8b8c0a4593889b795347ec9688a76fab8030b811926df8ad8590bd5fc77e5814cba952b5edfb34f926c027f1876ea2d2a98ab924a8fe2d	1	0	\\x000000010000000000800003ebb80ad0dc5b206614f0b266ed430157d9b86fe817452c650ef407f676969abb53b96d9f9805701ea1c449103b1941203cb2d068cd22b278ede76b2304688a5557602c8990c12bb48703ec3e12c0733764206af5b5b2225c1896f6a73302e158c93a525b77499a8ca50eb7391fc0c4d2bad4be8cef8e40601e2bf1301271bfa1010001	\\xb88c79936af3bfd0f0cfda39f872e6c245c9403897a5887933a494189c164f22583862b787c80a151a915b35dbc8476d3c6ebf328c5663e6c71504795a652c00	1674291689000000	1674896489000000	1737968489000000	1832576489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
5	\\x107c9f230b7159d2bc49c4813bcac985cc13ebdfe778bb78590013389988d217d40fdca9c06ba0519bbdc596467cefa4f71fc27b4aca87be09bcdafbb45452ab	1	0	\\x000000010000000000800003f45a03469c2e3b07c655d31a9bdfdcee6d7968746e83db1766db5dd6d7af8e1ad1c15f72b095a4a192f9aeade47b605eb18ea6ef2a46ffe628b5660cb36109e27b6c66841df0fd0dfad3753f47d903065b50fa6aaf5f3aaef405a7b6df54be75fd259458625c8fadafe85f4d26856bdbc22ee81bda978a6c163a2527f25d5c83010001	\\xf337268366b70c588cfa23f58cf75d9a4cadb54dd718281a057c68a75706d9e627abad88e08b270db1995702f9571f1256ebd38e663580ac1031508dea450705	1677918689000000	1678523489000000	1741595489000000	1836203489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x109895cf47e1559f56db4c6e3edfab643428b79f673032f387d05ab707f2c9173e967961043d23c1e8212fb1b6f3d4a3386e47e9c0de7e6c41ae7e8fef3a82be	1	0	\\x000000010000000000800003b4722d9e9dda4d87c42c4a79575673a0dfa78a90d9d81d890e79930e3d0bd4c77cc4dd7739ba2a94eceaaa2db9d9aefc2809f2cac10314eb15f02020e7709ba5433ef1fa2514ff681e7a51ff1249cd1ea1b150e92375f7d742c92b50b2a7ebf8dc8cf00870da0499bcb0287bf0f42a9ce4b440333c52c7251205c5b99fd6a44f010001	\\x5a1d257d5bf6823096f64d4a1380a7c3c7ed646c2dd0c7f134b59149127f10fd4935b09d9a503bb4311ad5bb65fa1217f288819a697c50d5b29e1dc0cb5c7e02	1667037689000000	1667642489000000	1730714489000000	1825322489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x1298d4ec7f1303ecc1288e9be08ea11cc17324a543df080b2caefdbf4c8599ce78187abd361395d9265012703bd129b700f886d4165ebf5ba5ef211adadabd83	1	0	\\x000000010000000000800003bd932d0590f8312e37bb715c446bf9c3c5a576397dd3face37adcf687f8af8f4b3d08231563e7deabf405c612e4e60b930a3702365ef99e81318a808d32380c411eae224230735cd14da4bca9a4f653f050793b3fa064f6693e90cb9e87a2bf7db371085c36e75c951cbd00ee38c7dca61a33f0f850d1597369dcf103c661785010001	\\x5151c47f740ba587d2aa7d7357349e2433cb52559dda1b626e1b579dc964b16764903a82fc857cf8452628844feb200e30faeb11aa2945db92df5fb157a5c10d	1687590689000000	1688195489000000	1751267489000000	1845875489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x1314a5bebc72a8b9804630ad79083ddb50ecb6553b667d3712c05ad07cc9bff78395147ff1ff33e2f150a578cd6ad4cd55695c8b000ccfd32d68433601c86022	1	0	\\x000000010000000000800003c52edad98a91862e33a724ecfadce4a9d520c90bbb337ad0eae9b128e4df3330ba13ad036fe40fd25f0a5cafef38999b2c48ee65689a1c852c147a5de2453888535d6406a4325910cf103a7fd2140d2d9e55d2a8b27f0e5f74a5864ce21fdeec6a9211cff2317faae185f20acead8651e266a21a1612a84280e8db6ff61c4aa1010001	\\xb8d480df830f88616b60678a1c6e250b14746d459626b8a61ea656a8f227f1d74e0c66afa7842e67f568235597eafe9de64170ab43ff9e045a46a5f17fff1f07	1669455689000000	1670060489000000	1733132489000000	1827740489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
9	\\x19d802fb8f66caa9f1efc210d85ba725380160fcf6469dfb708a8a306a09aad2ce59945631bc27c85661e1d3146e418bc66e0c1d0f7c6a791323e84193dadd78	1	0	\\x000000010000000000800003f0418088f830abe267361a441a439c041173bc92a38deffba721b22336c2ba141bdb369354f00e7c8f8a721155993261998c8ae54bf1ddc29ad41571b1521d51b0d4322fc21268d831e6a3640bc6baa105e7bd9d1eb5674aa516013a8d26e29d34d856598edd5a6b351665d6d9249bd3b3ebfb1cb594925d9ff35253086801b3010001	\\x65923a515faaf946d5c2761d2298c33071f5debfc38112905714f9b4c9a7ceae5f934c4ffe179e466c6a4130506035b2da465c050b27161c411bd562e2224902	1678523189000000	1679127989000000	1742199989000000	1836807989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
10	\\x1cd83cc9cc98dc46908f4c63190396c309e4b98706dda252848795c34de827c3f513628d6d4cbcd416ccb0f448a98d526a65f736f316194b21466c7caa8149ab	1	0	\\x000000010000000000800003b799a436e98dd126d9e355f14234ea336e66a0c99222405b42e8a7b06592a63e6640862cc999cd7895331845fbfc0ec4d113c59fc39c35d5a46e27b8e57cdaad93106cc2e0063cb121e5ab19c1456598d20b6007fd4874868f12077238e368254c9832f4d35eeb2aaab3786d2454af8d248fede33d1275e9237b0336c001945d010001	\\x695cb5f960ca4819ef83b7aa24263fc9146cd67c1eb4aa214e316785ad42a688d81da296c80841ea556f964a6950e1e848826a339af617f89cc54a6fef9a4c02	1676709689000000	1677314489000000	1740386489000000	1834994489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
11	\\x1db8bca88f61122a9034400fdf7abda89edd34fbb11ae14115f8d18db67e0f1e64e42266d1506293c13cd31546a9149322d56a40d14aa4b7850166b27369b9a0	1	0	\\x000000010000000000800003cd1c890907463428868519d5b977777b10bf5f8f7f93c57dfe2a99e7164277b715b471b587f0cbafa86892e536027872e9ff7acfe170731c745dac1174289b7176a61ef3f0662d73fc11fe3f8946b3cddd4ee78740f15f64d87d327f89a06dd5760a3685f227229179d16110e46202984ef9700b1f5a501d725e540dcc644535010001	\\x03394141c27e2b2e1af7140b9ab2043ce711920e1d0d38a5d4d069b97cbc62b66b33f51da0664a24fc75b556981e4d0e74f4ef5e4d75bf1d32de3006992ea102	1662201689000000	1662806489000000	1725878489000000	1820486489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x1d38f665e96f48c3d8c65df6d2ba4352159539f8c28a06c2c44e238d0fae926d8e65326d2c7af6145be208d7b6ae41dfefb07c062aea076853d40e0649870ef5	1	0	\\x000000010000000000800003d78b7d3073b4f9fbb57af8fd43b3a0fd7aa387c09dd36a2c6e98cc213afab333d7a908dff2e6e9a2b17018251003eb2ad7a2e39a7b43e5a67c9b06560c9b4611c46496539ac70c1365cf7c16bfee29c8bbde119057ba3a4a79f529c7baf8bb3dfa12ecf17f839c65d9ac5e9e19bb6c49ba8ea2f084d2bc1164358fe62187eea3010001	\\x6ea55a52b74374be52f8a0b830092ba669a37d92a09e874cc98e2586b921f8ca7ce8825d0dedca18778b184807497d90b8fd42abb8b25121f32590530a114f05	1688195189000000	1688799989000000	1751871989000000	1846479989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
13	\\x1e18be08bc01a3ffc8c565d1865e56738b99cad5ce0a4239f88cdb1ebfac31c8ee51752dc2ca7ac0dd41d015d0fb21ef59d15238c9b17be6e45a81b20d4b8b80	1	0	\\x000000010000000000800003bb1c477fad2855ce3fe0a9aaf40248ea15eab04e716612e7513bd1b0db35f44a0e975b242921abe3f18c9b864a9e00945f3a5eebb2d301a42b0907d8b7f6b6bdbed29669aedf0d53188c2e624a05794aaa778cbab3fa5c13fb791a26a627dabe499af1bc6879a372f9565bf93cf05ab80867456d177b6fbb05930f7f2610d1ed010001	\\x679a54ff80c7ca85c0f1835e84eede0a7fb84567d1e7917a47998938d43afff1b8b6a9974a4008c27fa00158eff3f2b72f3198ea06327d8dd2d136a44f66c50f	1688799689000000	1689404489000000	1752476489000000	1847084489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x1e9011624d761a8d0710fb06a0eb5156108e82a24742336387d8dd405070602666201cfa9ce450e83f9a682833fa0d0cdc4949c1fbc9543ccf33eb5503b6830b	1	0	\\x000000010000000000800003b2ab020d22b8b7ca3a69b7f5e7386a6b2158d3dc199c6c0165b7968f1e8586b088c2c0e08612b9b8464525d947f90f5821558f3623360e68f2d467e0df8879f5df002839b3d11a30d79385c2eb19e7ed12d4849f9a0db6c17d60890a58ff4586b9fe53d19d949e0a5226dd984b1b2ed93e9db9106f9c4b867a8f88e2fa15a623010001	\\x91b8322fd398b5beaad43ba93e4940068d443e0a405f099748788f96c3f1bddbeefd2aaaeca5551d57d62986b7427778a1b6737fc988ce7f51dd046768110a07	1677314189000000	1677918989000000	1740990989000000	1835598989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
15	\\x21a4d86242f6053410734a779fd212cbcd5d83077e7e1fe5274882aac256d68d1e9540e7cf8f50fa4e1f13a1979c144e04e87a7592255708bdfc79049ad55ad5	1	0	\\x000000010000000000800003b995207aad645a6f832c719279db4ed398f8b60dc3a4d0d98a1e669487a14e1ed36f3a58edb6b8fc34ceed6e85eaf9878c7d7b12908d925eed7fb4ba5ba1c91b8fa6ae1055cb47f4f9bdd0050b67fdee4c891552dac5fb079ebe79bc5b6416c2d3dce6d58d97dbada7d0a5942af9230cc04e874cf792b800bbeff77205f3a3d1010001	\\x36d771b93ae51b439381287ece105c89361cd054515f9e5bded068fb214b403c95528fd8843626599774a1efb1221a37db2100f331e491ce8f0224b0770f3a01	1679127689000000	1679732489000000	1742804489000000	1837412489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
16	\\x2384637b1387086bbcd31f890721e175b34d6a0b000ca6ca32ec932994a58418db3945e34f3eadac8e9afcbc1b074961cc89a80fb42be22b476a6a133cf92caa	1	0	\\x000000010000000000800003d497979e443c5d8b0d72ccf06d8d1546bb249ec767dbd413c5b0cc37bbb48770ad1a56c599f148b15917efbbb9baba91caea565694d370f570fde814197a9ad9f82855df162c5218ff304687d0dfb1dfb4c0ea64fef7cef5b7e7638bab8d09503de030860cf5d8dde96c41327c5cccc2840b6298a6b7d269ce4c858e532c538d010001	\\x0f3cb5f79a6d4accb1dfcbb29d1b61a841464ff3007cbd05050e149664aefa6309e528da6a04edd52adc5c6291ebce09954b7b09838975afb45705e36f8e460a	1684568189000000	1685172989000000	1748244989000000	1842852989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
17	\\x25e033d3856a9b41c3895e6e59fe9153545bc84453110a431716cfe76db5db40441510e73b938277d0ad9dabf20007b8cd6505d004aa86c1d82aec35a92c3c23	1	0	\\x000000010000000000800003c408293a58bd11baaad37ca1835222474d7a23548749c189256c8c1895f751b106159541648412a71bdad9b90f2efffa0cda003826a57fda54db870def1cdfc8a47c0185f869473e4abd765589407593f436c78d72aefaa6a2fa3c431df885ef849bfb80f5a81627908caec3d00b0a4a8a49974ffca9a45451504bdf08a47dab010001	\\x34e62945e8c487d61aaa21a9a0d5865cde0169cbf44e58cbcfdca4c929f8e58b056bd0865c69e3274499177f5ca69a48516b4130b6311c36104e820854ef7b04	1682754689000000	1683359489000000	1746431489000000	1841039489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x26146b30cad93176750a2a353090f37aa3edf1f751e1f4643018935b889e10ae89c1602dac5c1c6eb5d990e83792c509e71513781a98d6faf21c1df70aa6c8ff	1	0	\\x000000010000000000800003cfe4a69605afe0d4074f942b77991900f8ca536684a2346d5cc27890f7e1f47454bf84bb5c0c74f9a53d717dc91b5d021f5a10ccf23e606f8ee7b670a6b7f01b526e9feab3c062caf6e08a8991a053e3d773519612de4a82be59dcaaae2b4b54306f6329994b30857d3da2d769db4ad6fd4964fb5da9d1396d63bd7b465fe859010001	\\xfaed5d8a4b3e78bb0ed62351cf38c7e5211e57269360d087b57bc60579c943d6299b34f9939df69e8fb9ee6486816f78b5cd9efb40d6d3c4deb5ce7d185d0707	1682754689000000	1683359489000000	1746431489000000	1841039489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
19	\\x26709bf57d73e4c0702b511db3080e85e5a3b659950abde7e8401da212d2fde07d1fb98538d51ce970d88b86951b6922a2c33a1ce89441ec44493ee2b0c6f0e9	1	0	\\x000000010000000000800003a8efad2366ef67c8a19af0f4ed9c45c72b10702accd41bcbb0fdab6de05268fc08edb1c2eb5b397630f87e30cefc4904683a49a7e5ce270ab3af1e9caa3f9e9e3a0d163c2b9ef28db64d182ba72250d3e8b216d0aed1eeba7a2124c28529d48f41a38a6f7015cc45c95b8a02b88b4a7930109103ef1f114a8110fcb3d5165b85010001	\\x24870a0a6657bfba056cb47d3b0e38301517b4a1c6f1ea43105d97ea0e73c16fa75808b3605751457de3b7b7ac734eecb616e00527bd6057c8044f5bc3ae4e06	1662201689000000	1662806489000000	1725878489000000	1820486489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x26b0c4f412e2b02058c09d16b62ad7d09239d330523e77bf2d549fd4dd7f5ac5944208a00fef2a9482142ebf0b63be451efe69cce10af0b56f6b4c2c9948f4da	1	0	\\x000000010000000000800003cde687557d92693f59aae6d8b72ab4ee1c4fc96a9f81a07f9e1485007b7271d14c597abe55d071b0526ed447902a75d94c754017d04a9e09ea87408011af71685c51ae208f10c3c349dff7edec24400c7ac3fe19fbddd4d39cbd0bf6c2086a46a3aac952d1e3a8dccc1502a38847c6b106520b0207b1f14ae4513ab39ed441e9010001	\\xbfbfaecabf6c7f6260e2cf35227be4eea2ccb9c87af3fd4e52de5a3569cda54e010a50ab926fdf97af77dd58298e29b7187e4a9ad139c8b30568a465f680990e	1677918689000000	1678523489000000	1741595489000000	1836203489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x29304ec69b8de3fcd46fd10222fac2da6e87a6cf05f21c6243a44f371282a73189a01d32c0f42bdcbc2525ae0fd6de028370f31d6b29c2862b597a20f45c1462	1	0	\\x000000010000000000800003a0aaf977af1ee3b8a4b19e6d9ef729e794ba7e6134d7d3c8a8fc91b5a7f02e28369f672f62ab6030b3dbd6983344402539e7dd7c88eaf9a52df41734cbc8c2df4f14c7a6ac539b4914f791aa642e0fde6ddb2fe91111e034927e46cfcaf7aa528751293b7a92a11a587a5bef9b505199ad8c329fde0b7a64bee606cace79d34f010001	\\x53ccb1e7f9256c760d42753b7b709af50ceb843f49a108eff029e7f71809742ba641e900c8eafc0a8fc3649ba0e7373a7431c5db1df774e1fcbf3cd07a693402	1682150189000000	1682754989000000	1745826989000000	1840434989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x2b5c2743ecd5031c1cf88316d8b7082e5d727423cc034efe58d90880db225026ca61facef2f64982d47905e479b48f08d33d5cb9faadb818a9b350c20fe0856c	1	0	\\x000000010000000000800003be292bf8aae3a994239dd743d6cce5c3959ae8c558a7e2d69c4baaf684f9608e8f15a2f6bd98d4f1ebc3daf2690e35a74e3b7a67db5ea0ccb68588314a0d81a5bd4cb2002c6daa0bed0dfa0316433cce0e9b32a7bf381ba8c4169690f8283e4b3be26fd4e44d4724bcaa358c508e6535ed87ee778d1a2f0122106dfe975fb485010001	\\xfd4e231ddbbed9a6db5c24e690f168fd97e1c60c8ec04a8152ebdc279308a923054e3df3202cefd1ddc4f029c20d2f4f8727b980ab3d0ea8250f0e0b4ea46d03	1683359189000000	1683963989000000	1747035989000000	1841643989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
23	\\x2db8fa4a924832b8a22973b5db7bb8dd6031b6c74b958efee331b82e680d7297124f07c6789ba71903f53a643449a1ad9cccfcfab765c3f4d8b5b67a48dd179e	1	0	\\x000000010000000000800003c4fc5c8a972ad1dc43dbb451cbbf0ae1aba03340e86776e0d8eeca9a7b7ed5d6bafd2a65f264f4779cc546ee767a8c22917405d8764c90955871f165d5faf742f108ed3a3ac511a89c7bc59b6bc8d4a715736fdeaf634bb1bf3af00a0412844e4ccc0d7656b4b5d2124008414b5e2e1176485ab9cec8a258921a530ebe17ba15010001	\\x8fb2c4ea48499c3561607886930bd29851cf05191902c5080b5a33a7fc624853cd52b885afbb112aa388cc265382364959c4079288ca84bd984561e710cf0c09	1682754689000000	1683359489000000	1746431489000000	1841039489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x2f0852a26eceecd2a4487b0a896ed123536e49a967b4a6abe6a91ea0c08136eb463fd822df794ce1bfab2036bbe071e38ca98ab5c3c032f9a4d9e55d8032c290	1	0	\\x000000010000000000800003c980cd657067979a92e6e72d352a3d16ce225c34a4e9a6ddfedff2b1a863a8bcca2244368c034017ea6639c382329f6af9c5b7fcf84da2ed60d8f3bb35e3406871da6f47f57b650d0d839ce9095d9a3a78a2f7001596abf4bd17b8d9e0d9fc9571394fc0ff7cf1ee8762967b8f9b336c6025e80e19ef59e6080ac42bda92abcf010001	\\xae00d65e06e5938e17b04251862259714135c14847c467bb9476f7e70e1ae6d69271db8f8757182e07a0e42a7dfadf38c7495fb3b50486a74a76c53a3c237003	1683359189000000	1683963989000000	1747035989000000	1841643989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
25	\\x30402c0ae237acd91b4b908b8fd6168c49a0c15b43ebfd6e653543b8e49483b2c9ed57a934d02a8341b8111003c1cff455e3c07158ca9d03d7b20970b99cfecf	1	0	\\x000000010000000000800003e3d71fc2f7330332531b9ba45eb8517e371674234f84679cc3b693e6c1b4b85ca5d12edcdcd6bd6d26a0771d1831c8dbf3468bc37e5ce083441d76e9990f6cb38563c5971817905e5f127df1b90510276a0d136d47bd681fcac3bedc41ed47ca62d29391bccbc3b2e95774bb06efebf0edd56bb084193955328e5a97c52d5d75010001	\\x3fb430686417e5e1a4306f6a4b1cd6d900eb88fac3087efbe4e146e6c97b67faa501683e4fba7881af5a7177f7e8c8d826cfb8968b2050f6d178e1a1b4bd4c08	1679127689000000	1679732489000000	1742804489000000	1837412489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x3458ff7d562551757897fee8e77b66db889af8b108112a2d046265b50450165878680ec648671c65a020692d938a2e43d8dcc3c1f2b5d9515d6ff37762f02bf5	1	0	\\x000000010000000000800003a9bad79c7a1150ca56e15226acc3320179e6dd9cf1e55b19a357118c69dc1869fcea44eba68370a29c009405d86fbbc8aa611933e011cb34ad8fe65c1e9ec397c9b4623b077dfadd9692ebb325372437b8a89feeb55913787771bb3df57f8bb783cc6455885ef63db9e37dc9364660909155c8ddd6b2b51181bd2ad87903b56d010001	\\x974554c9f88bdabe92ae5898965ff777f294e1d78b0a9f2fd2a31ab608793afb451f2fd948b2bceb0f6ad62e8d19d454a83025d33bc496d4f2960c59f0bb6906	1674896189000000	1675500989000000	1738572989000000	1833180989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x3528635d936b16efadb3cf5f9843547c3e8f250be686db860403e65889377f3d7f8e15bf1a3d61b9da6631240831d687a1129d1c8bec7074383f99965242e4ff	1	0	\\x000000010000000000800003c34897c01f6e434f73ba0bbdd0ab55156ca62fab1100e8a11d82f79e126e522c359496fa43b818e6626299ad47cba333a9ae4c21f14e4e32422996c015b636fff174637806d1d3cf8c2d9120edf47fbadd75acd76476ff06db2437de1c9030b8e3b8b2b780444d75c65c4cf73d11ab5edc1d4e1272b9fbc997b7cfaeb616f653010001	\\x228040928e6495f30c7b3dbb4022a354e846ef4e78bb84d3ba2942183c5f119ae3e028881fdd141800b6171fb2056c2a630830ff02ce94a5b8920cb8d8e31f0f	1683359189000000	1683963989000000	1747035989000000	1841643989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x36346a022953ab8db0cecd05fd727230958bb9b57319733be89abd21e891e4a41e3841dd4831aa49a11306d46c00e7194ef99862447284c64f9f95bb98f1ae2c	1	0	\\x000000010000000000800003c4c971a927ae30ac0d6fa15569f17a2111900ff226cf4c20f0d2e0f33e12b7b71927fa7be40c8b45a12a726b10bf3b085565982d1c31108ba2f7b85fcedabf9551995cbe9f3578aaa6d7705a3f2889be00f40a1f54a3d29ff38bdd9e940b081aa7352542a92872089c8f1f84c7de0e28859c8e1717a9d1e60f83345c5057630b010001	\\x4c3c54ea4f2325ec2ac68f3012277690ef6715df50e57e08288450f19fe4afe778e701b8a760c4905460025869e0f69788cd68312686cdceddbe285d2bfc2507	1664015189000000	1664619989000000	1727691989000000	1822299989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x3a50b743e238dc57dea3580798d69172302e8dab66046cbb6e301ab498b6ea008d723003c347bd728ec0259079480229585002af7e8aae4ca90152a9bbeb8e00	1	0	\\x000000010000000000800003cde6982180ec271fffe8f5d2598a01918dae667bcdf1a3c2282f060023e8716ad31622b92a0e39c64b134a5472d8c9441acd9d476a719498c547f8ea7045ac26a10f2c3601dd94e7a54d70e369aef20ea21b37b48bf498e1efefd9714a9d0d0e79016e136a1359b3c1a8ed828b2370e7f81923e17f56c69427bd95ec500cd99f010001	\\xcf42f0c2eb59db7c54e6c3aae6f69575f55247d629776b96cfbec1b87ebb082ffe21eeedc6d0e90477136e258ffa95ea26d209dc115ffc8ab5c71084b327cf0c	1687590689000000	1688195489000000	1751267489000000	1845875489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x4010ff2caa3e0cef684653fa923933c1b26b7e4dbee437612aa41b5649ead96ecf9fb925859ee6511dec9adea194d0656a17e447f46a68a60086ee56538d0da7	1	0	\\x000000010000000000800003a9b37c1f2fe9ba8f842be68fd3ea7196123c30ab3dc9ab25a12c2859dcdb124bafbdaf0d908ee5e1622e906efac1e7cfb055b5b301e3f69400d25fd3c5be3ed727f57ead62499ebe944f37f746923cace8297ed6bd76462fef92af8d7346805b216fab0c4cdced8ef346ec098727d121a5f04c30427f2e755db89c7556670855010001	\\x06e2c87b3f182237defd74f994fb22414afd02833822071f8c9a21f9b888af765a4acae025d31deab183a86e49fc3798496a57836d35a317b06b7010e6fb7f0c	1674291689000000	1674896489000000	1737968489000000	1832576489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x43244c2ce4cf07ceae853e264838d007f05a902cf8738f3e498d5bb0e166d79f42b5e154d51308361415662090962af7cfda9b92206603d6c50f26cac84eaa54	1	0	\\x000000010000000000800003e65acd6b2488e995daa87d831755c60549b6ce70a76c5dc4ff6e640ecae5022c7adbdd4705e430acfa16db3fb5a204b1258c7101de2bedb1676bf29bf5e329df584068ad59ab9d7768d76032ece28852965e988198c94f6c75c7e0eb04cf5a62f2c2e610d1f581ddefa7b5e1d8add68666a665aea18ec9b7559ca752dc9f760d010001	\\x0c58eca4fbc2cdaad68dcf3646d97442356c142285b4afdd7b572e53a2b06d281c2e129b005f33192e11ad3fb7a695cc2ef6f49c21bd875315a883c8ec0e8707	1683963689000000	1684568489000000	1747640489000000	1842248489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x4494438ca8077cd39676efcc81ec836f1e84a1be4b7b2371017172b5e76e3896ba3072f39e6046e96af1c9a6d25a5ccd3df2a0803e0581644cb52ff499d78ceb	1	0	\\x000000010000000000800003d664c497aef4c6dc4a7820dc272e4e6ba1b24703801a1a6fbe4d4949537724161205a8c22ecf57a4f6238d12590ae7e7e5a8c7fb393645f309933b8228b4e445697650d811fecf3fee7c3299c0a137c91f8c074e9bb5e881ef6743480d45fd522021a05fe55f136217d6ad71f916b862050a242d7196976c122fb9c7e48bee2d010001	\\x436285ef5f4060c7cc7818b5b5cc12660614ffd909e77b4320963eaad11c69932f2acf86c694fe7e055e3f4f5a886b4218874be8781a36085711a0897409610c	1689404189000000	1690008989000000	1753080989000000	1847688989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x44dcf7477a88441ddec7bf5a4e3eb375bda22598ebd34b772753f6f50e14c9b8bd56cbefa99da6e880e709e31b4a11c886154a22a649f295d757b1dd3b9c0f8e	1	0	\\x000000010000000000800003b3d420f7740311c128d6f05aade63f081b83c0e4c4e6e525d1d1c7ffe4398c5bde56d8cb3763c82ff033d8eaf21b1351f89cad6c17a640ddd309e2c9a9aabf55909bcca9d9385af72f0298fe127a3bbe88e728988f9264b904f212be26ff22ec87635276115ca29f5b82d3d67cccdeedf484adfb81e98ec7942ff5dd7c31dba1010001	\\x66565aeb2004fce7abfee2d83eb7e704ba2eec4c633d8e2508def95bf332e54de9e82f0b76aa62b7ad84b41d8b6e6f972f847cf9fd9711e337b515d987bd7608	1684568189000000	1685172989000000	1748244989000000	1842852989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
34	\\x465056938d27cdf8c078c660a8e3f2e06e0f563775738857a6b9086d57ff3809838d14f3107efbf959a808ba688f86ae47bbb11712455b478ca5c021f9a3ab6f	1	0	\\x000000010000000000800003b8dbbe6f3eb32ecf6629a3d6170deb5109aebc2439fad5b87d41bbe89ee8ca7f50a087d05357e212cf9cbe42e03486913a253ca023b8687254455ae3f772a0d6ff9d66f9ef2e2229243a02388acf1f320b253495a316b0ba4e60e80ec58e2a354ba535c3f5ecc138fc8feda81856a4fa9f4692b86e192e96b99fe26ca9129e7d010001	\\x333e35aa564ea1caeb62a1ad02f0e776b70ede99a48c77a9be69eccbe5649cd12b73d4dd5ad1941f54ac57cb2c0ad446aae509f1c6856d5c00eb16f75ab8ed0c	1685172689000000	1685777489000000	1748849489000000	1843457489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x4944e5b9779850b5a8fa7b37f2065c36cb01a7ac21b42aaf08abf2c79e4f7e73f19000a90d430b0f6541a6c4928fd75324ae1aa7835a968ab351d05a1a6191ac	1	0	\\x000000010000000000800003c23be46b1dcca00dee1f3eb3a1b08dd47fa1b5a9458f8a6b3a25a1ce689fb0e50bdf8053ff9a4cf49d470162a6bedb336ed025006921931cee0bd279ddf96f33ce9b91dbcf02931c0192a1ec3cb42b6aec5ca553540ccfd7a94ebee755016431c93c989f08d58be967ec175672938cffe2abd15799815b4c5998141e3b605bc1010001	\\x0197cf74eaeebb12c1712a7071dbcfb619948eb5943989a9169f9f296f118694e84e70ffe3734815734629160bc2a2f7c325d39b502e133744ad3b0bd45a180a	1689404189000000	1690008989000000	1753080989000000	1847688989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x4b14ecd472edbe31e5c98141d983fac74ee9e27282e19e8d601dda92ce909d02e77131ed47821576fb50ae8c565cd8a0a6d98a9be00c26b8bcf7aa4669b7659e	1	0	\\x000000010000000000800003be7c106ea77787e6ab5599e495a24a6ab43e27d4b4bdb036c9ef6288f6aa0ae38215095161744949de8668ae842e61f7e403dd517197de76e0df568b7f15f39ae3f9e66e02734592ead1edcb2f388b4d26dd931ff14f315100cd51913c5f027bc787bd2eb4bc2748f6f7002cb052e65a49efe21b0b2d4a6da7a7e12b6b2467e1010001	\\xa4a3746efc5bb695da11d7290a2ebc15fe4750f132142c7cf8e760cdea76799142751becd09dce1347df8433d6479313c9877e2bd3d1e6ca90d4aebf7b966a07	1675500689000000	1676105489000000	1739177489000000	1833785489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x55440a124f6c8941bdbc6170eadb9db067f0837639761ed83ee49c5303fee22eca50a17a315231f2c48cb89ffd279edee5ac5090dce46ccce7a725d818c739e3	1	0	\\x000000010000000000800003bc55db4f4caede12b9e8d5d13dc46a0e8c9f56ac823b8d9e3658235893ce0e36defa672ee5a326daed7fda2643349bb442d9f8fc584054e256bb42a2e1614d0851a147191affd7bfc4a45ed8aac9f26144a84e4152241f35cd6b361df75459692ba652eaae2743399d977d2cf576b147d48f5c170d5c6115f703c17547ecd607010001	\\xf1d7b1429d7e28d8156d51252c4af9c5c8193ce38223927215711d3582e1375d97f3625b8726f2314cc31f3bcab73363b242a0fbedc9e5901d752d84309d3408	1672478189000000	1673082989000000	1736154989000000	1830762989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x56106d91c249e15e474dd9b63a9d613f98afa37c5832a3a4474f3f8f34d7328901db744cb53e1310a97cfb9d0e18da3615fb41d4189af2bb9acb5f39a374f190	1	0	\\x000000010000000000800003d7cf7285c6b30ec2afd39543382f1315391f12202a672bedd76a43c8b28e09bd7f00d397cadfad21d5443448b2091d9e88b35efea77879a5efcbaa8b70b0a87107b4d43128e8b2621e2d29d3b14dd1882948b3b5d0f236fbf47620bd13fda1e87e7cf128a0aaf8febd2a8c2e92f82e7da1b2681f015f6a0a580a5406f6b07f6b010001	\\xb4cba1598712340767175fd117678dad83ab618adf1e7f081e217b26170804f66924710c8012da493007a6b14e65eb38454457ab8c50ecbfdef95b8ac023b20c	1667037689000000	1667642489000000	1730714489000000	1825322489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x5990c37f3924c057f024b3a912aaf21f56159cc09d1c4c75a04356801285500166cd11605277ed844c2e43ee0beb31292f89689e412a4b9f162f45158dc78cdc	1	0	\\x000000010000000000800003d576c78d18d6c47592b6911bcf015e3e72ce3e793a933f11301ee5215a38122e6d6fcee485f5e7251f176a13a562b23d0925c20a81ccb54922a21ded28f5091067d8d789296971667de4e91993a8756977dae00341723cc6667f9a42da8cca1a9019082e3dc869e77b03abd9610bbb257dd467a721e492e3f80785c0cddb0dbd010001	\\x24e98297f2a0ee39c1510a3231f9b019c80cc4dd0b0a2d4f7fde920aca3607d5115947e3a1ed899e6dddbbbe35782238aaad78b205017327156db4c453b91e01	1668246689000000	1668851489000000	1731923489000000	1826531489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
40	\\x5c8022607db433fec8ddc20fb460a1f8f3c99c7e24aa8349be07c98d44738ef04d429977b44b7b1de5f4779b610b847a18308ea9b5850856d84fc2e48e83d351	1	0	\\x000000010000000000800003c51b967520a97cf9090f28c79c3eb7de2244f2edabdd2c60daef09ed54cec4e0399f9a17926aee5d2347af2c06c7700bf2eea02ff170611c94af1c44c2e34c632e2fb83853e6cbf53ffdbe650b54ac40a82a3a7d82e6281f4258dcfb8fd64f5d2f57e9ed4b9e7302f1de79519dccfd35b3c763255248899530ae9bdde77f0cf9010001	\\x73b90a06412794ed9e81b5bf64b15edb05071a8a3944f4bc6ffbb6fa7512c426371fc6f9a4ff7adf4b6743f7a354df0b2693f389d584fefc7ca236d8eb3b370b	1681545689000000	1682150489000000	1745222489000000	1839830489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x5da476be714a6f9e23eeeb8e5f59846e12c31f6010b8eb7f6ccf301bb9431e1aa6280537d3de0f6c921f79d563c94bc8fcc15ea06eed8c7054d0c8ef67db1148	1	0	\\x0000000100000000008000039ad6a01964dea035d90a082354aa62bf47844e67a969e0737809f9543034fee7ee0f11577d6e8b76329f7a1cc5a011fd6756fe573749ccbd7d9a32864219a09e8afeb0696d342ebb82eb28fb712933834c6b0a431bbde5aef12bc3edc39e7b52a9223e33655c83a60b0bc5516d2dac7ac92b48e0c22d24a906b09d44bc77ea41010001	\\x4a6dc192fd10ca64f05473d0d27eec0aff17a860369969418e57649852c3fe01671791ae6cf9d42a78895cbdc204ff76a4bd243a271c76d3f5d95787150aea08	1690008689000000	1690613489000000	1753685489000000	1848293489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x5dc8dfd63d179bd3c9988036fd2a6b85bc214003587e0e51bc98fbf4a80aeea28f1f0f4ded3e35dcb8287d05b6a592c05057429bff1ee92d2dd143523f8515d9	1	0	\\x000000010000000000800003cca6261bf44aa9a2315e3dc1eb030834f9ed1a6a0eba1788e48c3e145ff96dd892b945ddcdb2e1fe1b48fc97383dd0de23641c967ce54eff05a2f37118a8415a8b6f2ea9937d64199a14b44276ba127126507b54a06cb8598ea7233417a1f0d30dfecbb9ed39f05c4d1fe22d450d954b6317cc9d89ba33f8ea34c0e6313e2ee1010001	\\x6681cfc2459ac2801cffded5edcb83d950fffa0e2343389fc4b239e030ab68f4d6cb6e3c1e13b87abfe0a76e05ba3725fe47db4c504d226a2b8fde1a66107603	1667642189000000	1668246989000000	1731318989000000	1825926989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
43	\\x5ed800a044617cc06ac0e5aa568bc8f662361a0aa98b90cb6e1cc3e032c4d68f39dc8996ec6f0ab6ac78dc116c6fb13d38e8f3bfe52c160ea334e8e8310274ac	1	0	\\x000000010000000000800003e91b60919cb4cf3833661f2a33bdfa3ee3e1e7024be86498a87802418c0307176e0dfcd5864273133f88233474251aade8fd583436194b18a92cb6f30399cffcd0947d4302929998ee8579a458b7be78af807db78eb53ccb69fa3cb01e0e141c6a10d8c91d9eba793ed2efb399ada8feda99186b4c811da36be6591e7df27c2f010001	\\x9b8fb3a9774e4742a0731307d9f18c93683bad08987802a06b393ea8514ff1409509adced648f036f38717f17a46ec3602a972c3c09c328faf8eaf5ac67f5e06	1671269189000000	1671873989000000	1734945989000000	1829553989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
44	\\x5f7c91ede120651ae6ec088f44cd433e26825696ceede741c49107dd6c7cfcdb59af6af896607fc3f7f4a4fa973d52f7b5d6a629233cb633b4aa1d6e1de1fadc	1	0	\\x000000010000000000800003dd4244a991ff595b32cd6cb378b2e306c2950ab22a5d080f4d3ec1a3cfb4697c3b7a8c2f473e15516d4f5ba5f61746103faa237fc79100f7c8bdb301fa827c46d3095924053dcbea18e9d9264b2ae1f9b716064c081b28d1f648ff17bc6f42098e6de0ad90abb9048e077561358e0c081aebae7dca8bd79f7ee3dfb0e8b7a3ad010001	\\xd1eabb7131521eb87f379c9990cb3072f6a6012a1d275f940598719f2747af095bc3f2d4a5ec2bc2c236cd6655fb6cf4d2121ce4fe67436ebc6aa7f9c0a9ea0a	1671269189000000	1671873989000000	1734945989000000	1829553989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x61acabdb4de38fa77cc7d83db26fd869b576a4d82a49bb84f9593cd0f4a1ffcd2b66d5f10970f154ae79b06fbcc327abb4213cdbcc551a74c4169e9ece7649cc	1	0	\\x000000010000000000800003ebf1b57b1084f52e932cb472a4250a15a8db9d1e5d42cdd7940acbd2d63c9a585c7a026d0404baedeaf9bb1461f48e7b5638f98f965df425b9460bd891ad346bb1a1ce7ca0930920ad50b71dc54796c43460bc057b2592c0567fb8f8e1fea027412c2fc2ff6bb75b3c9e50758eee0b65035e48807ae1b50ef7cc91ce02c252d9010001	\\x5cb24b4fe089a23c6d1ce13201423d52f79825c0216b969e145f82213c25b02d10350163854668813ba962593a55ae5249c3a5d9a0987505a78dfd6ee730c105	1682150189000000	1682754989000000	1745826989000000	1840434989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x620053ed863f9d09aa03490eb02eddcc5008b016d0a88e7c7b71c805f3211cdae56cc55f24913a40ecf7643fd29520b396fe1128860239cc6bb0eafa68f47b45	1	0	\\x000000010000000000800003a5f20156fc08618480bd2ed2eb242a5a3b52bb0a95af2340e680132045477346233efb02d6d8dca35b2405b36213fc761e12ebed9c3f72fe482e821b9fce3bc62fbb2cfa4ddd00daaf5ad67590282190c3c2d348dce2785ba2ae33713e419443813c3d841d47b7219447887610e247aff2099eacc7e951924880565f34dedcef010001	\\xd51229bee978cd278e475b7f25469da99f6add5db5beb5658a4f201d3516f2b3afa086c09506656c8fc0403aa83c3276e8130607e54fd9e2527bf48558915f09	1673082689000000	1673687489000000	1736759489000000	1831367489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
47	\\x6504c3e353e9621a825cff3b1b6dae82241cafa6131937a3ad3b8dbad5b341aa1d0c0cddc95489de5094c0fa0d7e7e1e2d666c510e79d4f0b1533d1f53136e11	1	0	\\x000000010000000000800003aee7496981ecb87d1353024aecf8bfb921b84d5738afe216eb02c1e4df2ec43a17abadfaafc7567a8413b7f1468d6dbe711013521518f4dfe950e2b1f7100e0337e78538b6f5cf0835072c0a49fb854c8088fa2d9cdfd0e9d44ae16a55a15192416aa4ceb125da97eac48e74fc2f5a66b778d5a5e3f28af3a602f7b2de7999e5010001	\\x0ae386a97b335674ede78c68ea022b546235b8e00a0bf8f9b6ff533797e9a34d074e15ece0071a339d5d91b38d91669142cdb0446865ed8d95a905b8af299d03	1686986189000000	1687590989000000	1750662989000000	1845270989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
48	\\x664443ff98189ba42f01f0b8f2ed37b4379e45c6f84e60d45b19d267e455087c649d74f450b9ec0bfaa8b80d3f5d8346cc35a64dcf6538e641d3a1ba81ddcc71	1	0	\\x000000010000000000800003c924805a54189c9a9d4e0d91c21b9617cab1ddd41deedb5f19b9f7dab063ce8b9b6b1589882869c9001c1408d9bae76c7ca08576954e15e5efc62c418543b14a30d7657161625e795d937bc3e2b3d436b2185fe77a88eee97c8f09150063c39fa358987cb5ee4eb1dc280563873d6273756568c46cef2f71f0b260b365060f7f010001	\\x7bf69a31b557437b4561fd46231d3d3fcd1df4f28bcddc29c09bd602db515912e611fda4068783d674db02fe00a487f7f1c6356691d04d742eecf01dd8af5306	1670060189000000	1670664989000000	1733736989000000	1828344989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x68783ee86e8db9becff76786171862526fb5dc8b29cf5171d4ac538239605b21cab3bc476dbf26950d85d2324cc7b3b0c002179cf959cecdf193c84e778b3767	1	0	\\x000000010000000000800003aed78bc2c3edcd9143c3c9179c8fe87cd39a246a6539d0e3107c88c3ffc6c3d31a80c9a016316a5919342a6f5c37988bddfa631641024edcbd6de0bc6550b611e0e149ffe62e1d9764d65bb392c9d18a5695fdb83921f23189bedb4b8202e689024e3bd5db46e3b289b86672d9bc37eda1c2e34f245186e78231122e43840651010001	\\x607a4fee6ed5ac868231fb9302fc591ac68ce44c00003412ed280a284feb6b8061142cb2fec5022207ac30a11786a3a62f3ac98ed51562cef1ce67a57411850c	1683963689000000	1684568489000000	1747640489000000	1842248489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x6e34e7cd6e11c1419df0e8bd53e6b4cc7a334b8b80a38f0821a768aa0f47661492fc788ba5b20ff4e0f3d3b1beae379f2e892198606cf2d1344d6f8f0e51f5e4	1	0	\\x000000010000000000800003b5a754fe638c5fa45c3f3d9fffa33d02801e80e0365f54c9974cbb9189fa0206dae31aed02cd4ef4a7e47c19a61e65e806acb41fe437668afcf46aac74bb371794ba270413a25f31e4e45b996f4dad32eb88a1d199a3dc412cd4e7bc55461152f4e32120b28667a2162fc438c4c2c7be8ad555bcf286a16a0bdbbb3f18878201010001	\\xc8ac574d5ba3db0f9266f7c08affffa3abb42abfe028411c9318c2beb1948d3d08a353a752e20b5dbba853e89dda43ecad83a6c10b8171462d98660c29eaee0f	1667037689000000	1667642489000000	1730714489000000	1825322489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x72ec3da57ebde59756240f5619010b7e0b6ddfd555dd2d0d7f715fd86b143e9f1cd3d9d9d5a3490ee2400ed512b66217ccdfc396e93efda82cc0637f4d5a05d1	1	0	\\x000000010000000000800003c4cebae68a1be39845321ff0f49bff9a211f4a19bc190b69c206e73adc41e483b415c54f622c15b999391c1bdc6e011e80a68b808724955ab452d3713a83ca1562ce71af2e4db6d9bb61ddc8e36184b7d50e9b21e28c3d11173938e92b659a3d8e1e9c6e9c6c0d21c7c3ae9318ba77b476bcbffc2dc80f789016080972037211010001	\\xfc41b9c7fe72cd5e17cabcee56e395592965cae901cdd73359da711b38b510778c78926c9aba737d75c47651f34e0abb82c05f3fe501f00ae2f5dc3777c9c30c	1668246689000000	1668851489000000	1731923489000000	1826531489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x7348686b86bff6abf52b83c8fc7ba01841ebc57142f4cd1f540e14afcaa68702b263a84c41da193e9662b094440855eec30f0dda6fa45fc8ccbd825c42f60e1c	1	0	\\x000000010000000000800003d84f4d7c9bc8bb1e04abf342c3d8cd37d06996169f714afe2e78897d22f569e9ad41b2bfc156c673c014dab176985c65178e5ab02c16762a5e6baad325657bdb36d4dcdad9dab28cdff9f492b9992047109a3db570e3c3f787bfac3d4285156c9ce000120d2e90f862a6d38a3ea9a14012925af791b6f26c384b941e853219d1010001	\\xa486d61d222afc0f94149c3eb479ab2d895252a241f7a576f6176fc4d60a64c79976f1ff9e0e36b11a5ae75f590a916116b3540a96bd07d26db3e3dc49ffe801	1674291689000000	1674896489000000	1737968489000000	1832576489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
53	\\x7a6cc76f66cb6accc1aac97123264e44f7dcac3ab82079f2f0fed192436b42bcf2bacb430ca38b33e3bca545f10acb816fba7cc4363282fe63a3f4b2e75559fa	1	0	\\x000000010000000000800003b2df8332a199b8e6d33740eee11342b558a4f3b87f1fddef309297f5d24b79e18f7ee1436ede7d6dbebb19b40ac44ce78d47a568aee55284dd15b23e9a8484a7add5a93807d93a20ee6cd6b1eded299a50f959bf1a30a9b637628c25abedce8b30f588c7b910923e44c10a68e001f5fbbaad34887c67cee4b72e1a5870a06f3b010001	\\x6d6b157cbbc4a2f56c8c2306a979e148d4242eb43a1a91409bf600ef555892ce56d904ef9ebca25b963ae0c67eed9d7b4fc713909f1fa5b749aad7e7d9f05802	1678523189000000	1679127989000000	1742199989000000	1836807989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
54	\\x7c4c3a650eb69ba116e218e7e30f11c77de9f26e8e61a6889f513c97e50b97bc25b2125687ec26a7dc4252e0b14b646878dd5c66c5d8e7cbed26dc7fac130c6f	1	0	\\x000000010000000000800003d795d75ea88e0700f9a10c3314e22d172e1e47edbf3c3961786fbc95bb4d1ff9bd781d81e0567962d0a495cdd7a1bc8d9d8f0ce85e7ed71e1bcf90ed60434cf065c29d629973d6f206a2adec88cbbec686ed5792c1950fd3e3e32da0334991fda8f0ca74db9ca86c8e9f962565090968ae2deb8269d3a2a5654b889630a7dce7010001	\\x351771f475a2ef71b37b730d933ed69958708fb2f3a06d74d3a6ec3d53fa208bebe8c075995df118baf6dadcab5597ac9c7a0e0a9a1d48bfdfff026568582205	1667642189000000	1668246989000000	1731318989000000	1825926989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
55	\\x7e94439363ead8e849197a9d4b10bdf21953f684a05abe0f58588307736e3b85fef212cc1abca49bc3aed0c5b1d25796097f8ec26a58a5cc9618a43e3cd04bdb	1	0	\\x000000010000000000800003aa7f89853fa680c7d0f9bf50bf0944262cef188a47d158e9b7bc0fc36f13ac5ed7befdc2af7eba55f55edde805a6c2081d4c51c8d396398a639992c2430ccac378cd081ba6e49c09dcb1ade93c4484c8d7e57fd1e385921d5505ed1b724a38f05bbf8e04c5d47809d9fcec243c7ba370b703fa323ad6d79b34ba71bc42b7feed010001	\\x2ed191e081751be30b2096d3c771ffe3a90f63b4af4bd6a3f05b75ab9dbb42e53897b3708eaa2b20cb51c68af2233f4478cf3704ceef9276ef99cd3f49242303	1668246689000000	1668851489000000	1731923489000000	1826531489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x8014d0e7efba30dc05bd2298dc1960e1a978bc807848bd80f4b20c6a16ac669b199c58243b5ee643139d6593b9d76f381ae94e4466886b5ccfb930edbaa1d815	1	0	\\x000000010000000000800003af9f1a37ba19cf6a1beb7e0273715d80e142980fa7004c25c908f2de1fab496024536217176915fff62a4aee9bd522034aee67246b0d13dca5558b6d60a2958f65e8241796c79b8b8206659bc2202e15c7f81b0c67a3db97e323413cae0196267bff434817362e7f957d8be0ba752e5e810c537a881a4a686d92c44c597be685010001	\\x2f230fca581fe4acc612979668a1663ecaf17cdd515d444a30608c8ce7ab7007be12f9afbd8c79a1eb815c9f05bdd096c024b16d1b4b9d2fa222fe2cbf4a3d03	1677918689000000	1678523489000000	1741595489000000	1836203489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x8060be9e928ef350f23839af3f28cce2e81b99369eb8b4ce304600ce241df7fd5151344117938026f4b2521e5745383bd772f59b7dd2c07d80dd98c8ef2ca4f3	1	0	\\x000000010000000000800003aa0688a9bd133ac036f6192aedd2522c42e2308b32e92b051f7f00a70ea4e8d3f09a40f797fa030d1729c6d367d69f7e4b8f2b32ffbf3f0c43a6fa62e3952f05cd6bacf7977000984518a7e31b66ae36adb3ceae1940a648b70b167a9653b69d75ebf2fb37296974cd63ba418e5c94b43341f0f1b9d70b3c707be9ae37473aa9010001	\\x47ed0820dece8b5d0fd66ddfcc62cc26502f0f6cce73d8a5ced6f754d5d2fe02cd069e146866dd70fcdf30aed10442ce099dde0a4fb5871d27d953f7d0deb50b	1676105189000000	1676709989000000	1739781989000000	1834389989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x80886704253ece16390854ffdeddacfe102ab86c3ab276767f1d12a0e0b081b15114aee65ace58b9825640b17d7363a9e28bd4095ba150465e3814dc7ee3f360	1	0	\\x000000010000000000800003cb8d14538e372a8f9d8c342d1213f29eee42a2f3a8d01eb72767edffcd7470869af8af8d7fd5e71973698740470bf264a63d44896f1a2ad12fa080b39df7785345bb26fdadb3f9a0e7a56d669eb6c3587a52730c071e1f040b866e29f4d46801421659f89c7f36bf5d61ae622f3f111ec4b263ca4f9799668ae098446c49e923010001	\\xa31fd110c3166aa9e3faf332aa79f2c6c519b90dbef5394bd531320606f668af76c274794bb34e517a3db3a8910f1b1618028f520c7f0c1ffb66f69bd225ec0c	1680336689000000	1680941489000000	1744013489000000	1838621489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
59	\\x810017ab3f1d9b75144347f3fcbf66abe9de52dbb5f4987ad8ec7dbec0e229e8fd6a824a168cad1622dc92be91473b8d582287fb8f80e8db0ab503855253c5a7	1	0	\\x000000010000000000800003be2a9fe65370baf2b03d993be047cb03db76e60b76a23a2f3c8716b4fe35084827a89124c0283ed9153ca7ea5434226cf3f3632c66270ee5965d6220e7a5548376fa89c40cbc9ee5c9d2ec05f0be6dc970ee7568da6a8e33c0505e2a6b489bccfcadd2ae213e8243a7fa18f27902f22e65b92c2ba2ef957676ce480bffe03e25010001	\\x774050e79fa1cb2f5430525f617cf37c4d1bef679e642342a8d728119af6819e18f6db7463f71d36ae4c08bf96154bb199c92bb3394d9acbc1f9bc246daef90d	1661597189000000	1662201989000000	1725273989000000	1819881989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x8220bf9418e6ad587fddfb3c580711fe8b6325d1b00c9420b6044a315862043c5fa3e18f2d13d8d6d3daa878791e9c0932a79461c3b6b5091bdaed95d2d9c736	1	0	\\x000000010000000000800003d5b89f76ba34ac3ffcf29e9cc78e0ee28e9c433ffebade310f0b78f9220ebbb399ddf43186912af9956656ef6f5463438c45908be3605b3ba2e774d23474da035ece139f6724df8c2e380bafa7627f8526106a3f36b0ab9ac39c67283a512b211d672f833afc01396d2a5a4fcf51a1c350d44eb709670936eb4d23a507fb2847010001	\\xbd7deead32d6be0f52f74e1800640743e95afade44e874253bc877e4774d99de182acf731a64671908264085096b7da76531a4a681f1497bc8ab8bdcfea4320e	1661597189000000	1662201989000000	1725273989000000	1819881989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
61	\\x834ce524e252b82e6d1725e42d1adbafd17bb1cad31b8b9f8837ec008b83f014e8b359c5aa6149c66c133947447416d11257a95b31906b656ea2cf4ec093778c	1	0	\\x000000010000000000800003a4bccc1c3255c637f6531bf79beca95ab706dbf435c366298633c639c8ea0b776f3a670104764bf8eda122748e0745f37f95d1321d44e2da5d535c786b5f397c17583b54f54e51286ecd58a7f6bcc9a43b37d785916171f45c91b366ea897ca8670cf804325970061c8a17ae7bd9775d332858b03794ef05ccbc618ea64a420d010001	\\x1fd00abfec25b82e9c21cdcf60bc21bc6d2a409c83d5b5008b1f488e0e470594a1ba190c952119090b15872edf5e55d5473c3e2e5fa3015fec78d9cbe77aef0b	1668851189000000	1669455989000000	1732527989000000	1827135989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
62	\\x84aca9b6592a2f953ea9f7461ba6c641080ac6f948df07860a6590cc182039058bb7458b8c589596a4691c6649dfba2efaeea5c6b4d1ecd75331e51627e41241	1	0	\\x000000010000000000800003c0714f45d1db9044b8382ff4bbb5f82c33bb8c39ec22f8fd977603ae955b543832830778aaf89674097fea298e3729e3c1ee425988b7b9836268eb30f7c204b0a1c5b7201b199fecccc6746a161e1ced797323813bd019b4a601bed8ff160068438f7c4aaf64b15eda055af06e0c0715362462115f198158155955853bdab52b010001	\\xaff3ce51227cafa507d13343ebcb0135b0d0bbb135420171999aa7f9554f80ee563f94a5de086300b29b3ab079f61509b0a91dae5a8cc1e3f0ae67a7b8ce8404	1682754689000000	1683359489000000	1746431489000000	1841039489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
63	\\x8578d2765ef5ad8bc6c7172514b14547e394a53d1b0c37f68c3e17749347402bdc0bc91c77fe52a45378e7883f50b7ec10c1da854528898f74f46313eb711477	1	0	\\x000000010000000000800003e0ea03d158cb989d1e68fd838c6b69eee08f3793fc7384882c3eac9446502ff7ba330ebadb5d08e2321b7f9c24f583c5b6342f4a140d5506c869135066254a1aaf473c3b91d78cfda3f57adc9dd07663a9c97e63aceaed0d3f6e80e9647c78c831f1301c1bc5d37a3e61a3f0e00e8aa4788f1af71ac287f1400e85c9d098a297010001	\\xdf9cd31cbdb5770074d66baf7823635378ec27ec6381ef0bda5310081657faf3f086d8cb5038d7779dc02bafd6fbb41237095d438ea6b3d093b98dc44343f90e	1691217689000000	1691822489000000	1754894489000000	1849502489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
64	\\x861ccd4276f18e8ea4e53b345296eb8410c0ec30f0a9dc8c4a507ad4bb092b5513164e72a999a977229f2ceadfb108cc203cfc0dc97c0a491b919e41f2daba36	1	0	\\x000000010000000000800003d49fa3082326d7f8707b13f6dcdb6833c372176e50bc8f692842ac5fea02e3fd5a11945d57303451c720f57ee0105150deafe7204b5b1236ec1bdb92ffe451df62ad9f2e8d534267c15c974cd90182250043ceb03c4c11f372518051736b43e314e16b138c2ed6344dca7047b2f92c83631a9f0bd492ae909a3fae63f613eea5010001	\\xb5589fb07254e3cecbce970aa2d893b9bbdf9e068a9f6eb58dec8e1b3b30de57f86149fdb3ef9ef12eb0401d8ea4bd4885bf3713215628b3d9d088a01663de09	1664015189000000	1664619989000000	1727691989000000	1822299989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
65	\\x8a08f813742eacdf51975247d8f94472c2b689d6629e3d381f62a1d7f0c862a2fdc34f419cce051b0d9abda0586fc3ed530d487a293d958ab47df8d483b5556a	1	0	\\x000000010000000000800003b8429f8d8769aa541231589d7e6523e9e7a52960ef7a57fecb0a8aa90cf2e0a07b263efce5da95e7db8c69f3dbea6e6a48f72fdcbe481519652721cc614ca6392dc3f6287c98b79f0913fdeb97fe25318d5b87daf7efee9253eeaf1e4a7202e1d9f97ba6ce46998647f605f237c8b7f1b2b1519a628c7e20bebfa130fab28a73010001	\\x9a7c94f9b0b8e5a90046cc288274820abaedd469e50b6aabe0d3d40088357ea816b59850543a8b49f66118a2ed104f06bdf9970cc926a7f0d6f6d5e71f704608	1674291689000000	1674896489000000	1737968489000000	1832576489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x8ac4f3f5a3cc88edaad20de792dd09c033d277bbbe4a82c35f3038207f727b73a4af380da73c73c62c2f5a10573724e73f4b297e34b91cd90bd59b01f8dbe44b	1	0	\\x000000010000000000800003b90930be0e9eb31ce852f03449ce61629ec8cbf86c9ff6d93dedc7cad85e113ef529d92e837213f6d75d1c1254d6668347eef7737be3c5092c77addc4114f19d34af74e0967442da4ec5261bd9aa281f7f42ab2154ea9cb2c92f6da88f506d6d8c8cbc06ee0e6615e3e921027a5913b9b63ef3a70c2c37bf130686b149dc5fe1010001	\\x98cb6ec12d8849d70448ed82097df0d98b1260cce0fc3dbd2466f9f7c8e3a83aadde20a1103f46cad7cd8af1c936f4683de17bcd9aabf9ee703f6cba4a90390b	1691822189000000	1692426989000000	1755498989000000	1850106989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
67	\\x8b68948b584c636a145c1fcad78cc917a2c60de52e759efa1a4fd03d00d21956dbe5f4899dcf61dabb80d4a179d2f3111fc38ca14c4c7e9e62ef7754c091faaa	1	0	\\x0000000100000000008000039d8109ddc93954cac92f7ac63e9003cdd087739e8f6a077985a1a127c253c629cfe3dfbbd974eada5ed8b50325a95bdb0e04f409abf5f256927ff8233ca8d407392501917f9c60ed482826cdb2d5b3f94b3c180be22e146e3d50bc5055343dd8a1431cc65f419ec29ef0e35758ab7b424c29cc187605c74d13528e7a2b7610f9010001	\\x41eebc910ca82d4cb74b0bcd08cecc6ca8c8b1548a3423d26266287d31cf4c2127a15969f335946c0d117f1da87b7e666ba812b3895049e07ef0d4e8e3396107	1662806189000000	1663410989000000	1726482989000000	1821090989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\x8cec74af4c3c5621f68327b1abbbee338af1563b44ba4b729247dcfbb394fe14383c029126590243957c4c3a01bb3d658fa959548626fc9c7466e37d11d593d2	1	0	\\x000000010000000000800003b9565be9356df270e84f881d22f0f16226f71b3ab8792522c4ab1c60d482f20de0134d160432a66cdd3ac6253ca607af3ddc919f4be2a073b2603f587676627867dde6f3139085d81a99c581c28747603dd54f688020d8421db944f9c917ca7cd94f5cfb6a467498b5ebaf1808ca61f7d0baa61575dad703f21382f3cd4121a3010001	\\xa676d4c0459e2f240124a96c842573c502484cc772a7c5dc6b459265915ebebbcd48cd3fd5ab57ec5c36be65f194248538b56909157fc6db19b5e0f93132e90a	1675500689000000	1676105489000000	1739177489000000	1833785489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
69	\\x8d6840fdb6cf339898b7de3f40db98daf62e69bffb9cd87a0f71745f0a21761ee8d6275eb13f3ce3756a0ce7204aece6b36d9a511ded356cc6985f0d89b465b1	1	0	\\x000000010000000000800003b4449d362a1188d6160ca5ade6a10cbe74aa9f5359ee9b50e44a648dbbe6e042fd7414336766c8f4c16ad0702c67f17daab5af29725e988ee8116a5e0c525c76b5d255fed7e56776f3a2f0098770bd2cc1709b8eef1b79b51d7a1d697caa4143c155e2617c93ee1710c53561f6ab880616914dd2362d044bdd70b13e537a64cf010001	\\xe373e895db3de1b7cad0b16c1673ee3e20a08d051ce427b3228efe6b869cd95806d0051efc9d6a90a8a779f8c306f649d5cc88a079bfa6a620acd23902ba7600	1676105189000000	1676709989000000	1739781989000000	1834389989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
70	\\x92908fac7393a8121072d17a1e8dcee4f9c2d0d03dd5d89b6af5e428f8da7fd95bc10275b9fac19decb586e3e7e16b271c59cdde8ef5171e9fdca631ad8c60b2	1	0	\\x000000010000000000800003b71af3809870c08f6e1d1f5da5fab178d150dbe40f2a641fbcd24bce5f7d8f1a8b88dacd0e07ebe013e3b95a3ce5f32a1f86e44b5c6ec198f0d40a974c2961103a8b4a8469246fa0a0f7a56cd0e3c5fee31a8529b6042581326fe40dc48377c7e35929c471981db3eb74c9d8c889c3c9aff86d551bf12dd529d52a2b7151012d010001	\\xb6159688ea979c2ef901bbd11f152e9b4fcee963d08424b5da944acbf5612cfb6cc12ba1734d2ba6b44b93b8f3c7ba59f2f1b99c0e940f806c6dd1e681328404	1686381689000000	1686986489000000	1750058489000000	1844666489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\x9884d9b63dea026cf9182aa51835bca745a471940a97a7d2f354953b778797e928d07f6bd2254e2534b0b2749dea8ce74b9969f1cd76bd023ba2bfe2c5c8d4bd	1	0	\\x000000010000000000800003db3a848e081ea0d4c7613975a59c9e164dd2f774724df8696bd2fe083a1249780b89c20c59754bcc64960037b82730523dfb1edced716906ada1109a5a14a48febb26ef3fc6772c21e993e730892a3f70fdf17a859f269f1bc32c64f94f763fb412835fd6e4b678c07c904851a7f51b4f74f2188d832e2c65b50abe617ad4d13010001	\\xbc60b05f37834011608cc946c5586e6405ddddf2a862662e2e757a5bcae7bb166611de6e8f437ea056a8b7a9cbb74189688cdafa3c7ff915311194e84d0d4a0e	1686986189000000	1687590989000000	1750662989000000	1845270989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\x99f814ca351388ee017c5cadba6015339fc9e46845cc0f73043206ab07e165eac376a26faccecba0f58f806cf928ab3728994cdd983f9ba7216aac616c38a3d7	1	0	\\x000000010000000000800003aa8bbc36106ef2cf87b1699f296316caac72e30b4f5a241a55a34157b313f457db859ef9b141875dcfbd6e9954155c9c4bc660d00542140cf4fdbfe2ebdbb659b79579fa608ea972e6ad59355225db68f9438871cc710037c381813a233659e9bc3116c56522b529203c8da8709505be3e2c4013927b3113f0764b4b7405f72f010001	\\x2df8c3dec89dddd77e1707531ca4812966b624579a50cf8387be83d24e1813d80da056061268e10194aead5bdeaace2a59246f51992cbeb1e47434608809e60d	1678523189000000	1679127989000000	1742199989000000	1836807989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\x9b3832513c66e7f06e9c492710db0d253c5f4a585e1dfa65b777d1c0cf7c3232fdbbc06ee3cb702dc8e01318db1d72cf30ee67ceb8c723a63eee3f90ed76a582	1	0	\\x000000010000000000800003b5611229bbfb28af45497a9b1a35f92038652f422a981ba14cdd6447ab7c2ab8c1aac26c97a102a9ff621d846fcc3da2c91a818bf74fc49e8e9247d09873b4165f653d58d9da86e9ca3854b81ce959f451e5a0581355cd53036e6e6c4254456953677580e5c5c81e6feeb1b68ecb118b0a7106c7fe238ce4334fbd80197d4dcd010001	\\x9224d5a7c4976d77662936df7283f94a85c8f4f198568a6355c03cabec70ef119d39a17fbe5dcdf0cb566627e554e8cb5ed89ad74b21725f858e8feb56220008	1690008689000000	1690613489000000	1753685489000000	1848293489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
74	\\xa084a6ea4bb8c977b43b83678d24f93f3c23001c2b092d344e40578b1f2b625503344f4eb33b26d1e8933389d7a4c96e7b4c3c7a3fd5643da6f579d2e69f2398	1	0	\\x000000010000000000800003deaadcf677a171afa4e8f7d7770373dfa2bc62285f1b40ea38cc6b0d5287868666e91cf2eb8dfb4098052a98a116f6b50c93aea67403f27db7e16b907f4372b6bcdf8e3976b08fb20d50e571586420bc657effb80edad8526906b7cee63795eff2fc5de5e43acb832105502d9dcc64185c0df00b53a1156d18d8a7da5064c7a9010001	\\xfc6a5924dd23b08117acfcabb9f3ca410f2d02086efe5daa532fcc7434ab7ff30c2627ffbceb4549b48cac85359a1d8e12e3170c3b9a7caad8764d4d8828e705	1686381689000000	1686986489000000	1750058489000000	1844666489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xa1d4a0c7db5820a704007a022bdbdb79cf688526d78465d60bb1f05a15589e439dde2818979f83bf52842741b6ef963b48300a77d3fdeaccb3bf88fc9677c900	1	0	\\x000000010000000000800003a997dbff1ea38f65c9b13ffa6c8d1f4fca697cd5b345948416195b877fa51df55aeba79ce42cbc212ab9b898b96a45e09bc80755e96f390948604e0f91743ac2c9266ed62f6c27367891e3c6ca30718d5cf7a35ee0927967dde8b74ac100c136585f5fa46f85adb12593150659cc5cdf9936e4732e5c2bdb48da7610ef256245010001	\\x29c36cff8f16e34d1a270dcb7da1dff0605a3c9a91d1fa1688dce98dc2e4fb2bddaa5c0935835b0dc134c9eb3ec6d45d95ba8306a6ffba21e34f4d5049322504	1688799689000000	1689404489000000	1752476489000000	1847084489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
76	\\xa6c4283d99266129c7183ccbbff492523f9d01e114a90a035b700618963f001ee47500792685ace183cb33cf3a89ee5c29dcea3e95b3b949f52ef03b1fcf7e61	1	0	\\x000000010000000000800003c8d8ea68eb0a24401f70543b42e5f9d10c02aec69dca8413f67083f19095d9c77e2d864d25c1fb1fc529c257deec6897aed053b18f9d7feca6783fdbec2301b8ea6869b1820f4250cae32a02961ed40276e72f492cbce1d50ed09f016f36f83fe2c065d878f4d55fb185072256d0d5bd9402a6a5bbaa89482c86a17aad6c2d69010001	\\xa9667f3c540b40996a3d993ea6c612288922b674f3358c7d88bb8b68e7bf6ae7ebeb501f1d1d5bf1c69dea3553627047fb557f66e115a0af90170017bfb37004	1692426689000000	1693031489000000	1756103489000000	1850711489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xa7f0406e695311fa7d6d5036a0d2a5acfbc743f274a282edfdf7f5ba2e70df6c936bd259476ea13978e61ada7edfb08ebadbfeb6cb4be8d18c24186929ee037b	1	0	\\x000000010000000000800003a527790a1a7a11629703da6f18abcd7ce125eb773258eb4f32e81c7a1814fa665728d7392a1b23d8e1dadcdf84d54bd5b3b7c2911362ea3fc92e21d04674b4a2788b418532ba1e2b3c4ddd11decd6b4c060848acc2a23863d37c6431e8c0bfb372786690ade1641c2cc7864db1d358bf59b78ee6e7063fa956f71e92f6f584cf010001	\\xe190671cc33217c43ab6d4749f23acfc5efe0b6fce6e317f80902731c999fd01547e1e5e48ca3348cccf2697266e2317780017cdc18abe8a4a030ad0d4f1fc0c	1660992689000000	1661597489000000	1724669489000000	1819277489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xa718a06eab72b4e5db70fbccf8345a67723209d72a4e0bb4c45be9a28bbbbf0dbb0e60110e1132d7178f840a9750cb2bd3e504b802ef4745f3da2ddc5e26fc47	1	0	\\x000000010000000000800003d2ce606f88468e4bee440caa84bac41450330a71f33290909b8c8c0619b50fd4fafead6762d7e477634846e8f3af755e58b765654a0a5ba2af24f84368e43d6a23d46915a0b35a080ff6480084763a92d126e3588ac4fa6f9400f599187a39d6cd27d288375f5e0afaae0a5f783e6acb370c33fb7bd5ab4fab33c702776364cd010001	\\x6bab034db2216965d7ce5087edf11b60475b94b87b58b928c2fb6f8a4be0fe5b96db9713c4d5bdbcb4fd83a7ff3a930dfb02451c527c834fe889905c4ab5b904	1680941189000000	1681545989000000	1744617989000000	1839225989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\xaa385588d89b1ddebbebb20dc3de78b909679557e139aef6c545e0e1fb5dd4c55e1d60020eadbdedf0cfb2e3929eec776206925aaf7b6b1cdfa0655b6245c36f	1	0	\\x000000010000000000800003ba8bd75fc5a9f3d903c6581a62572b88039f27d3bc7179edc4b9283c469249418c99544ccc50bbf33da78c1a5cc2c8729718c1d9688bf75cb25c5391ef8f85cb431dcf03bb3455f87be8f5fca8cf29e5b866031a73d7e98478a6991cb647543fec2fa1daeaf38548884b7ad55689da6e1b04729c18fe68526eacdd5b212c9d7b010001	\\xfc4d3b9a53a526258e0f9a2ceee4b9bdedbe801e0adfc8978fc664b2c34831fd8e64c63bdd538cf6a30a322475ad2d6e6054331226573d38a4d042041531240e	1667642189000000	1668246989000000	1731318989000000	1825926989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xabecdf90da7d86290a242bc347fd94938ac58c382ed6313a8041e12f22e2a0291771a652600fe5de20f3a2b82b7a2cbeddaf10b33fb51307eea8f4ed3104867b	1	0	\\x000000010000000000800003c02b2cc238ee7c4c7ddf38d96848086903dc4bb9d9802c5beef0032fbb6347e46d4515e19e521df50248e950d7da0cb00b6e13f2131a1bfda2daf8024c0c18d8f114dbec6b9f47356bec29932c13f0f55883f9ae7199583613897533022652866dfc74011930e8cde7c1870783e4e7733015bb2615b049b5b936074ff4ae6e41010001	\\x5898f6a0c60e943eb7a8a1cfe65e3ab7f34982364061eba4f70fd8b937aacae4e8ae607f3177531f45c208d0c8578f4bc71c82c71888642f0bbf6460bede6406	1670664689000000	1671269489000000	1734341489000000	1828949489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xac2c2c83818a5998869871fc8ddaa5b4d09d2126c6e5099b7ac2c62f8f3b4622eaded07cd509c79546cdd056b37f95a174d6daa98535f7e29e6158b46e53b626	1	0	\\x000000010000000000800003c59a85310591ff6f4e1aa804d23474372fa20cdc1410254592a1a83774a292f6e7cd249dbad80ef2be06848e5fd9555bef0aedab1bc222ab7c7366dacb59cebff20970b3fe378ff50eebfd0931d571fcb439b5bdc44b9f35b6930c4306e5537bbed839a11a370208c0a3ff049ce8fd866f280865ac454801cebdd0c3e0417995010001	\\x740bd204e9b952334ae5416350f966b0798e7ab7ae247ac740734e5f3a081d9f9da96306a828be50a98bc60c6af202334db5da26bbef38a262157351d424b308	1663410689000000	1664015489000000	1727087489000000	1821695489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xb2fc8d6c8d755fd16cd75dcab9fb9b3ccbb65537d43a5e00c71136998d5107b05881ceab05662972a7768bb1e1d5e4799bd1d113277976742dd1c3a080224435	1	0	\\x000000010000000000800003b4e9820b4c54dc632131bffcc18c12e3e047aaa47000cb463d3a224ea9d0e0bf7f908b5e8415eab4c071139daafe2bd416cc1cecac5b104007ba5c3c51c02bb0f988951a1fb4c299f91eb39dc5e4da9e6b610a8945ecd0a63d171a799ef2615e276da2c79944f1b5fe3d410fb32ade4d61cefecd3c50e79c152f70eb59f50a65010001	\\xa9cf4fd20d8924f8b526207643260cbfcd8e46ac56b6dad50bfe3d1cdfe2f51ca697c787c09942973a27c1d20d08f1c67b53cbc6bb0849b6d466ae708bd94e0e	1677314189000000	1677918989000000	1740990989000000	1835598989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
83	\\xb27cd6ccd81ce943e024d60236f9528aa2a0d6dd3222040df8247610819ad5a5a67471c9f111d23776eb67020589f1c7ec2619691789a98cff2de8cbb7dbfeb9	1	0	\\x000000010000000000800003b804ac205d5b000965d84c15df4c8a81824279a8e73512cf43e61f79546c1aff1fc5a1ae133d61dd2ce5f25c406bdebb933b79563df60ba1c081ccd47e2d98ae85c858f99340b6341c8dff4e4f20f135b422b4847549bd3676c9129a4d01dc1f6fb84c6045360d2ae4949598f9b0df9d23500c507fe3988b6ba56be84faffb79010001	\\x1b6a2b10c73199dcab4060ede0f1d659fcbc6ae0ffd8272770e25823bf4606c11458eaea23a188329578eec0175fe1a71337e7a54f549c1e86dbcdfc72a84f02	1680336689000000	1680941489000000	1744013489000000	1838621489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xb42890994c5903d8ebed8eb17ecf26156432b19978272ce57bed529ccf250a2c15909634bbba2825101679bbb8e69e5e2f97dc024c2643f92d73dd9e6bd52b90	1	0	\\x000000010000000000800003c0c6ede0733635e894df70883947512802d0f060e48ad694dd51f8d69fd73976b3486514a02a6b1660754c9c673a7e869e92c2d88cc04bd357b9e60774d02a96c2b87b1105d5d109d24c712173ab04cdc9033f20994c6f5cd15e61672d8355562926aba32317cf13cd4c33f528441269c37298122567fe8af0f8854a6485a4d7010001	\\x7a6695961e637d742bcf4f284351e30a43da1f6bff05a2e6dad698ca0c290906629ee9d8152aa56daf6c00c1795e5dfdb5fbbd04c2c0c76cf00bcd2190e8ff07	1683963689000000	1684568489000000	1747640489000000	1842248489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xbc309d0ccd5c331fd339fe4dd3d328a31ff8aa201e548766a6e662c55dd21cdea3e6294f9d04b107fcb99b056bd40f2da3190016d0e90983fd3b3cc490b85241	1	0	\\x000000010000000000800003b086b24bb23d00ac76e855f8c453685d348660927e9869b2ec85717f7a790ef2711e17d70ee7d36291b9720e6c68cc36a8c0821b11ecc071210c8fb696977e492ee2c323aeb8c41d1b7cf95b0b83f3cb720e5c80f38d8b0824738b0778e243e6af844813f938533fa28455a3d43f02b9254f8f6d432b6dd157ac505de431a879010001	\\x6dc4a6353cd8080d3c68797361a2e3be4a1e5de763df8892349f2fe5e964f6034b4a0631bf05ca3597ccdd7c188e0a2d10949853843916f41b9d6dcda893e10d	1688799689000000	1689404489000000	1752476489000000	1847084489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xbde05f9edd1f66e549e076eba6130a3c2bf541bf68195682ae006e3f862799578bfdb9dd00d7f01d90ac628097d3effe334bdff005d8ad0f3105db3bd9b3c611	1	0	\\x000000010000000000800003fc224860b508589c6bfc1cf7bd7859bed08ef5dbd5902144f5df97cb291b2c22b64f2e1a4cc016099b4cdde97c47d82afa672f8f209ba16e5293095a13c32068fae7397f134e2149375670503c22abef7b353809360f7cebdd0b0bc852177c9c1ab353b594974f639ce27e723b893d2a17d0a8e641997d02b6ecdca626c970c9010001	\\x8133a02dd7b641100824b79fe3fd69dd71656be8dd63433b9ebf10e6b645a9c7f754cdc340f0c35a36eba73888d341cb265052f3538f5fd3d5745e03804de40c	1679732189000000	1680336989000000	1743408989000000	1838016989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xbfa84ec978e9dc6c68b3a0fc9b8d172d2559c3fa2837c276a350bd7bc11807f030ee2d4d165eaf440e3e9182cb727b81ca3690e144862441f74e522058cdfec3	1	0	\\x000000010000000000800003d80987b15a13c904944d4c2283ab82372fe6ace277ace5bffc60af2d8f2e4086711c168efa69a74d6a503c456370178723e578db4f44dabf78f815bff8d7b6a3c33b2d120ceb137cc1350464e9938cc376c149b93cf073bc7bb01fa19796e031a61a840926cc1aa97fdd123809ac6af2cc76eca87d57896e0333fa18b07b589f010001	\\xa8224402baec25b17ebfccbf1ec91d4cb3d4fc5d1313d309414677ea89c52f14a36db293549a979b89a9977522d029f0d77dbb355bbbf0085ee83275dae72c01	1691217689000000	1691822489000000	1754894489000000	1849502489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xc1908e28faf00d6444e79979702c3e9ce1bc63cefc4c949ce8af4273dd7e219fe349ebe560113988af6a547c9d9ac72291d5b72b9bf8e5e241714174c152071e	1	0	\\x000000010000000000800003de7bf27099f7ceebad8485bbba9e0ad8385a7b78b5876c4535e0f64017b10bf873199b11d00017ea6aecd0f4466e641b37f8c92ee90da60c1105c6a93eea9b3456090c2710c8e60a75c41560bb4ac314ca902e332c92651760e3e0480d065a186af4b83250c859810906ebbb51c466caedfc2a0b6f1c6e0e58deba868c3c0785010001	\\x857f1fb44ce2bdebd5b1796f7429fddb49af14b69ed3ceea522561f60ee8f906623ed55ea4876536b1a82123aaf8af57a5a80cfb2c469a145fbd6f3b18825f0f	1683359189000000	1683963989000000	1747035989000000	1841643989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
89	\\xc89cde513ed816116819811871bfc7b188914c8757d86582b83ddd24f5e8f3cd5fc8a32833ce416f6b9dc2f84398d2955be80204323170ff93eac19a4d2e9c1d	1	0	\\x000000010000000000800003ccce393c513abc8c0467c00916dc9f94e4ff86bfcaeb66d844702a0ceaee2eab61f835d45c6d029345d51a7fc08ddf7ded59f2b0fdf95053feba1f79e9884deb487c740deb1f7671dcf170ef69916fbbe7b36ed7933f5c7ab2a542a7b1ef25859d07fb2c9d32047f8d1fe4d7f1ff3700e1ea0d88ac85fa1d43c1224718c03e05010001	\\xcab9c8c7a73c7a95c000449656fcff370986fd1dcc25624755436b7bdff8c140858a2292459fccf3f4d9e0dfaedc4271eddc5d4f0c12d980124e753bc6815806	1662201689000000	1662806489000000	1725878489000000	1820486489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
90	\\xc850429075593add8af41f78c72658df1cb0332cbf19ad01a6735c93a4e8f72d4b8b2dca327f715cbb27219cc71170f720f6263192b8e09d80f96a3e60714a97	1	0	\\x000000010000000000800003d9e25286c6e198307169eb8f362b9adbb05363993eb8cf90def0b61508f1dde8183d7bf2654ba1b9fcce4f2bf5e1850e8cc67e6c7a2743eaa416a4f664781d316ecac11b48b6eed5113d5a3ee06ffd3fe9e1e1d2e2e89067f4983bc2a4487f917d70b1a46c77eb35e4342ee3d3370dec8eebdcc25427ad06f1929f9f82e1e979010001	\\x6ad470bb7dc63512669cc76ce4af31cd8e17a3892642e71e742fb525f3b7b0795b26831b794f52e94627c9be4c85132c02b55d5d6837bb499bbdea5268290d0c	1690613189000000	1691217989000000	1754289989000000	1848897989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xc8a805677942840957535d3e234cf5dcd2eb2e2972e577f87aef931ffd8a338335afcb56ed96e7fcd2ce040d05e9f0b4b5eecd21cc08692d888da250d4f9c57f	1	0	\\x000000010000000000800003bb6e98827f28db08fd36c40ee009180a7f9a0aeb67b9701c8d17301b9738ef31154d4eed65e66277fa77138f76fddc4bbff8e43904cf367df5d34dc8f903e62cb676447a0fc6e575ec97e06d45526c10a58f95a9daa84d4ee1fff6c4135e76f2e64bc1aca056b72300218d68808b53cf55b7cc4f6efdecf06e37c7807d9d8547010001	\\x69d03edbda13eb5df034be22114b94fc305fd08a14648e8e02958ef8782ef721336b2ec1877bd0cc2e6559589c47fedb2997c1be69ced81465b637a80319ba06	1668851189000000	1669455989000000	1732527989000000	1827135989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
92	\\xcae0dd09e91712c61a60a70ae217b61c202c59f19800159430310e75155769dd0f743f2563346b00085896a2a36b6837849383899bf2725c1fa1c50762f6d0ef	1	0	\\x000000010000000000800003df35b4cbbcc9a5a61c3b9b94d345962568df5a21a702e0342d70ee6946d9aa0070c232035ecfb759c69d3260554b7e6cf53ace99edd5294955844f67d9215bf469eade9bb16d799a85681c6d5f9887270ffd9d8f1195fa8cb06a35224ff2b51b2c360a723c005b01dd38169fb45663d095de9db20424b9a98311577a4a2fcdbf010001	\\x0e9f1e19eec415d3c1d3729d6d1329b9102832fa524e6a34585d7bcfb214605d708363ecba325eda5d7e0a715071d5fce81079802215ac52f737f0f538e45007	1686381689000000	1686986489000000	1750058489000000	1844666489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xcc2074d39098f74874d272d0f864ac8dd8371335c10e2fa3e39367651487ca025fdbaba261088bfea7ec8681c7ccb409e3eb401cb9c56c635365edcc5ae01243	1	0	\\x000000010000000000800003e1b6ea85b368d4c31e4146b0548f582a029c52882b0baf556038dfefff626c83a9f70d3cf23920663a6708ab935e68b4217edc7db08cf32faa1e7cb46f7863f18a962469b026a493fefd2ca7fd3eb003ae5f4a651166791f5fc2b263c9cd27d371736e7166215c08eab6d97ae3d35cfa5d0d0967076a343eb08c88d352ce7651010001	\\x7fcb952e28c2c99774f5f3a02ed54f73eac24a3b91ac359bd387f4b2b91996385a9d516affe7ec77e1577ec9ac31a3ac6f5c8db33938ab06a0f079a71797a304	1676105189000000	1676709989000000	1739781989000000	1834389989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xcf4827b8217a2145df081025030c7d49811473b72758a5e70da522752710f87c86bda3b9968b8c27da83b3a590c3241b06c124821e70f5213366830aea8ecd5f	1	0	\\x000000010000000000800003d9dac9094e0aa9f4be2f3d2f3ec70bfb618d4ce55ed31658805a50c2191afacaf3c3946ef6440d4687301f024ed3a763e8b7730d3a19fcc911896ca31215f06d2f5c6ea5bb402b31f5899eee65b3a30143f70782ae657a8cb6f05701fec98904bc502732d723627a7c85a6ec3ebd32483929fef820fec00780353ac7e8f51d5f010001	\\x19537b2015be03623bd5e6fe480ec0d0d28870bbf765c26343413ab05b92f3b5adb25ce005724ca92e4f309d98d669966da13dbe32998480a83bbb7db666fd02	1664015189000000	1664619989000000	1727691989000000	1822299989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xd180d58695545b72a5bf7ed0ead7488a849dd9ad29b3b966ae667ad49486ccc1c1bf840c36ecb8cd4bff5fc9280182f84cabeeb23bd7bcc51305dd1e30085ec0	1	0	\\x000000010000000000800003ba038f2f069e12905bbfc9d1b30cfada67b4d5c445f480244445b65783a27a53c6d38d9f91e3e5bf0a33fe3927860813a157dfac35840ed1228ce0801478f9890d999caf3acc05df4c69d03de130fa6643946bb69b9a72d0e243f17ff269f896e05b93f52cf2b4775279e22cc7172e79f0a163c62c62c7a9e4d23d9d67d08bdd010001	\\xeb021eb6ff734871456666ba207b572e81e2efb7e71b21be44f1d94ae19b278fbf1011e720b81db9082da58e8b8e530b4688c5aa3854c8fb5531e8f4630e5503	1666433189000000	1667037989000000	1730109989000000	1824717989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xd3cc2c55b834fe6be9f4739acdb1b85f027aeda0db00ce70786103882db017cc43c601fab33acae32b432efdc2c489eb21d912d183ff7147518d8b3189efb46c	1	0	\\x000000010000000000800003abd56fe08a4280f03803839ec419adf34d6c79be24e75fbad8ecca85641882bb3216642152398efb055bca7e9294b1351d8e53372d8ae555d2a2a4c9631430828ab4b69e5d8b147cc1b9848a7c0af30fbeacf52e8f5ce9634c509d96c04565f8238e01fbb45ff42778372a73ae4a8f2c7b8a27b9063bbdd4c6abf04d46fc5955010001	\\x91ad10685ac0e917eec67b97811c1e0d52e99748ee53a04a0383e914fde2709149cd3930ffecea16d1d593634124862f0db676956a7113241577d2c283baa40e	1670060189000000	1670664989000000	1733736989000000	1828344989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
97	\\xd69cc96febfde78dbf4b4b733e9e891171a3dcf99db99c5d2887ebe12ea47f7e7817f04a8003ddbe17180f531ee2b2f35b69b5039860da534ba73aa0773140bb	1	0	\\x000000010000000000800003af9d4de429b69446c7945fc4e74b4aa72c7d358ab561a3dd01efaffd5c5d4e7230727bd0634d277cd00c49dd2ba5bfd2a55b0a8de14ca8e4f5b783156e15900b681cd04a12d395f1d0e943dd54f0088435206dbc0d5943d9ec8f4189431b514dadb68f154f29eb955d7db1ce8afdcf94d9862af56a3e430e5413c0a33dc611d1010001	\\x91de78b09286b3b5b60fe679704a0689af705da9fdf80f1b8fbdc3e91b49deea00b520d2ddac229cbeb98277f2c02b896f966a58a85e63860ba13544e6ff1f04	1668851189000000	1669455989000000	1732527989000000	1827135989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xd7fca40b28d926ad0f019bd8904a602757c384ff1d9d7c52edcb70909b4b44c98146b510a26ab4ea63a53a7232eafa7aa1f2f4977e83cea3eaf61721fecc35e4	1	0	\\x000000010000000000800003929983ba38e6f35436ad07b9a867bc6d58f87b7a18ca6f92e6e1c00d11befc2c98c19d0579040e43d58d76e8036d006cd1590ee295e898a54d86bfd8d4e78f6bfd61a47bb2e7908b0858b4e7ca3da594d7e483bb3de0268011c3e7b0687f7136b200a6dc828ee8c64141a43c1a2e2b4d618d054a9577748fdc6986d03023022d010001	\\xb4195a3662169405d01db9545a359753a5af9d71d566cf0c6caf4bc4d47e827a024290592734d54114520bdb42f34a975ad159d33388844a78940408b3703007	1686986189000000	1687590989000000	1750662989000000	1845270989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xd7e4e0f40664770788edd2abeb02b6f841ed934fb822edc31a9a708faab01c7f08808ff62661fbc6be0bd610ae0565c91ea310bd0dc3112128a057f61ebdfc78	1	0	\\x000000010000000000800003d3b54a62e5c6dae1c64aebed8ccbf2ae18d8ce4b52f69c57b9b70392f7e2192949c55ecf602dccc634447e85a415323d3f452678e80bc74265ee0ac3dafdf9bc1beeb4134a2abcc4d560b5ea63b552bae3afdc987a334b20533aaa0241ff422e0fe29c4daeae6c24139a422198165c9bc388a8cdb37b8f63553c94d668461f0f010001	\\x0a412076024a0b6e8f7d6f9eacbb41edec35f26ab73c4908c3f8e8b305b02c61311fbdcbea7cf948ee97321ef8c89cf43c79ac2020e45d2f314ded3dcd91c604	1677314189000000	1677918989000000	1740990989000000	1835598989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xdbf009a7df184beca29d0a04bc63491c8089b79f303bad8c5ae8f010545bd6017e3cd7607747ce1396e44b240f33cd4970d80a728eaf3bc4db8c9d754aaf4211	1	0	\\x000000010000000000800003bc5d38b60d0bb16f8e7364986ed81e3e7425dad2e301ba8da80d5e3045980c796037289bb66a43a66ee755a15008f486db77105a31f84195e912f498092e413e9f88de47be9ce5a5766251fce21b1bde7f7af1bd14a52919b622320d687247b73439857664847c777fb03c875666af7634e3034a48cf1aeb9ae0a7fd9d156a4f010001	\\x94258335da2895d95596ab522571efab7344cbf4a99c39d045c24e3654fe7fd2f19270f061375e02e918571054d4f8ee5cfcc262993faaee89b1cb172ae8b007	1663410689000000	1664015489000000	1727087489000000	1821695489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xdd30d56ac65876fda4da36c8e87871295d5773db5d3729800c21f2039e2fbd8d652fa30b3ef486dc456479f55de124aeebdcc62bd14939ae5aa8ba87e68e84bc	1	0	\\x0000000100000000008000039bf9aa8f01fe214c8d18af6b055ae07d46bc7e2ceb6b4c35b6676122caf4c4eb7af6cc6f766179e5de2f54a124dc036247b4aaa3b9b7f542e9ba0813525e09421138035fce19a56bd7fe7327c997a6cd37921997ed7a63d2d930fdf5481006855368f5f1d7183a40df72a5e0cba0373f6c0cb5048dfda84eab83101f32d6c891010001	\\xe34a5eab478fc4e578e0515bc1e4b08a7adedd1b43f2dd08b779ba3fcf32bee9b3b406ea9741c9b5f6666ce3e27b7a7a7a01159aed7c69f8b9296ef4c1242c01	1665224189000000	1665828989000000	1728900989000000	1823508989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
102	\\xe23410c521195351afb953bd3184463931705c37b86d41cfa5f6b2c6daa9afe5fb163f1b89efe37e8a2bbbd62bd02adf70f6e5646fecc60fe2f2abbdff8e68f0	1	0	\\x000000010000000000800003a8e29e711324d6bd0f1076b3b925163ce23d0a0216d772d9ad68b8c078f78efe74d77d354ddbad29468411f7a7b18ec8b2609252b39a26726eb2b77bc1a6c8aa1af8b2979321b0479046b85f7688a759c9f1a1ac3ab24921b3d2a84c2a3b697dc11e53a65f0f43ec601553bca6962616b67a78753dc7d924706790f9a148c8c7010001	\\xd9818e6c7e963ab87ce84f695465e32815f296472a9590dbfb5e3f8823af07fe8a286a247ba9562534f7a426c5f9d2d72cb455bc290e070f9e5c46954dc5d806	1691822189000000	1692426989000000	1755498989000000	1850106989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xe4dc52c9b4500da54daa5aab7e8b0d511ab394b314d60f502a61bd5d293bfe041f0d511fe2473be51c95656ca6f9031fd0d018d0e683a0c101e8b2cc7b8d3fdd	1	0	\\x000000010000000000800003c842dca590ff1b3c4b8c333218264470c1f9993f729992fcff2a3834ce0e59cc65adfa0bed4032af55f1ea0e2a3c534197df7844cf4e3e816de388da20cd3f1d85ec8b086263b3ccd7559c507cfee44d75942cea45af4e9b42bb9fc98be5c3eb3d19f0fa21a1ca01777433c06e1ca14a2f7233f5cd9406645f4ac979333676c1010001	\\xb65ce84ba0dbe52f88396d25c91998825c84cbf44e4cce3351bafb48a6ffd0cd7c17da50f0495849c9443dedcf4a4f73390804a242480ba7565e8256d1b25604	1664015189000000	1664619989000000	1727691989000000	1822299989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xe6d80aba17f747fd0b0381119673072a6f65a143a67b06fc5614b242f7a55cb5f3306e41c1d8251c649b4ff11f87cc067d83feb212b196c18167e6c0a3c2bc19	1	0	\\x000000010000000000800003d95b81b4eb63b651a48f3835aea3dca26aa739866492a2b58550bd3ca86f4b3901249ee46a8471cc5446499a12467cd7cf8722a940c72433ec33df03f96cc28af61f107d7401416bf32dfbfa3395fac9920ba9937aa9536c209ccbd9301eed33ae8d5e08fb6f150b5189c59f8cd6b8fd1c8ae6cfbfc075a621c28d098555226d010001	\\xe14afaf7756707c1e1082260fbb15222c5132c997367766d10ccb0f607373a7de375dae128840fc944795a686a5536028420d286abb974a10ee5118360428804	1686381689000000	1686986489000000	1750058489000000	1844666489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\xf0400a483c3999e0fcf8d7234626e927d586315dc14e5675d03610ba1a538fdf0cf71f28fdf4ff97370fddf0e4afbfc4485295a0f2dc47fa5d11c8be91f57b9b	1	0	\\x000000010000000000800003c98647a61ee168fc987aa9a2528937c6387cdfb649a3422c2f93fe9e6601502c09ae16f192308cfbca0623232308b89927b4036a868366d5b38b930c50a169b978755ce74de8a75587e9dfefee8a52c7db52844abe0c2cbe44b77738bc0353e44569a13cbcfd81bff4da916271ad9a94604b6f4055276f5a932e74831bf7c0cd010001	\\x1dcea8e82480c07014d69e635639c298d88c62dd93bb39362a20b5f98a3b09ca878e8592a424ab817bba887f742ec94815fe29e8ef139803257e52919473b20c	1668851189000000	1669455989000000	1732527989000000	1827135989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xf13406c24576202f574892f5b80203da66f6da440edec32dc1c2bd03a47b9f639666f2b834563606300d4a2b5da098573b96fe78dcb43590a1eb17d5ddb09673	1	0	\\x000000010000000000800003be852352f1b6b5afe8b5ba1c425120aeceb5018d10227a0f9d3ba60a438de90a48c670ef8015041bec81f47be5b7a198327882067b7b623fd3533b67816e4702efe1e4a593ac675f841f24739cf348a225043f3523befcd8e15ecaf30b0bd5879809da7abd876bb96ae4126d3cba03bdb2d94e4bfa2ce26858ce7ff031860c35010001	\\xd496a2d5f010a87ba176831607a6ddc0336696d4dbb6157469a758681fea492f6fa5fcb4e13420312fa84a58813d4bb1043974502a98e51891a19a19e06bf50e	1661597189000000	1662201989000000	1725273989000000	1819881989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\xf2b019497872a5515373bf2d80212d82a9d461b37a0160fd67e4812a8332bbd0bffe379dbeeab765f522c266fb3fb139703ab236b8c0c5c13dc86ad5946209a6	1	0	\\x000000010000000000800003e4de469f72603e561ee3e544ff3bbde30de545d76bdac5d7bb085791e5ba17d7d5de4651718303fd100a3ddbd1c4d6ac752fd56a275574e35619ab676759591da7a94bcd0fb05d787bfd777d0fc84b5fcadae11019e647b9d7e6ce5d3a845d3da6386588c130a13bad0978c396e0e61eac0b85d49a349791581071beef8558c1010001	\\x1715ceb534fde8dc490ea69b5fac91fc123f76cfbd48ffd832e16a9daf0a7a6d6a249f271f72c7863cf03e2f37eb834a5b33d6b0588a2871bd2e045663add60f	1682754689000000	1683359489000000	1746431489000000	1841039489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\xf394565db87497e9597d3ad5e3579ef9208050602fd4d4311dcad039a046179a79a46feae4c0bb708c668cc547cbcb71ec56e23af8b235099c700b857e49ce36	1	0	\\x000000010000000000800003b97877566f85bd8e9464b3382c2358a6e7d545b9161b3e403de254ae09cc65219b464450d46e68d8246e61b4addeae0997e3e42f77bcf60da9e88c1bed872f63fbf41ce8d8a67e8f5a11e1fc945ac0852cc4afe57e66e191cea548ec8c600eb5a49f6d76f77d8a3758d7c46449b2d8055e079de0e5860b6fef4287890cbc755d010001	\\xda9cf8775e87cb03d36ed1a47aa017d4274ad4cbfbf5416c694a88cdb0b09841bf3f7d386ab46e421725fc063576c48cbd29e1e4c9e000a76c8af302b791c00a	1671269189000000	1671873989000000	1734945989000000	1829553989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xf30441badfa62adbf9b6fb9b6be8b0f8973c66a5da69d03e79e7365dce1bfab6a1691795f413054c4caaf1e94530698d6fd967a418f476b5a700d32c7869c739	1	0	\\x000000010000000000800003cdc6ee35fee256e993e0710d16e439b2d391addcc16e6422fd89506e824ffa9aeb501ac5d10d8969d50a029e4f00358bf2879d22c89bb722fc37701d2e00221839abaad4cb5d802d7be58673fb4c3e3aeebbfcfd2d0358a6c9436baf6e03e980cb8ed4e27c2d46d44a1133500aa3a473d33f20a5717293676fcf276e2e8fff95010001	\\x648c0c27b88241d905673370e6cb0ca0a7fd0b479f5ee9980a8309265a57a9b159c2e230fa638b0fab4d9bebab78905213ef813d1bbe77a16106561467acb400	1684568189000000	1685172989000000	1748244989000000	1842852989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\xf6bcfae0a83c4a5218efab2f5d336e059dfe61913b6e86b943e8a73ad226b52495d2460e78b88604fe8e0d45a2b139d32e328c43f6981a98f0ddcce2968d1141	1	0	\\x000000010000000000800003d44d0d705787e6336017db126c3a989a1ebd6285f1646091beb729a1dd53a7886e0caaae94379aa1585be81bd731846c6e45710c1157e2e9b4827ac5bb7373b6ed4d98b27496289dd5f7c6fa3a936891bc35c002b4bcf9d25e488bc656f2d4880d8fe602153206b6b4f95b7098ed4f0a5427ce94e3dcfbf16cfa0e59a0b04f75010001	\\x53ab23086734d9b8f34626c3225c207fb6bde59b35b46d07a246bd03dda390a0c0b0c539316372bcffe912b917a9be69878f40123eec6da7ad03a76db7dab102	1683359189000000	1683963989000000	1747035989000000	1841643989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\xf6e0719bd00aa73134ece15edc5fe08c48eed08015b83b925df1e7a2bd0dca6196a6dc6eceddbfd35935c279e2edbf22d221bce6bb6a3eef24acdbd890c0019a	1	0	\\x000000010000000000800003aac3c04e56ba65fecef72865d30f9d161e64e60121d8c8db1fc54af1c4998d4b865977cee30b4817dabd18edf82921afc402af3667d4fa1b5d00c08bc9f506f6f043c7598865ce071fe2bd4d7dc95a77214f1e662235876d7a037fdaa0b5961e9d3d1b6aeeef5101be5ea6ee82907275f6447b90fb3728780fdfe7f294e0cd89010001	\\x4ce06633d53a528cfac5c05de1e50da4af721f43043197bb6d3d4d86cca88f7250c129a5058d02e529a471a9c6bf6f49270980befc5fbf1ede312819d424e401	1687590689000000	1688195489000000	1751267489000000	1845875489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\xf60cc6a383723ce5499681e102451c4a9bbf79455e4cc3b1e5e4d6ee44b260f1005a9bddbe2ed4d5eb06aacd1746044d0c92699f629726dc4b45fc8a4d8a0806	1	0	\\x000000010000000000800003adddb9bd5b1fc8fdfb5f97a14ecea14ea4bc17e7b733d43f27b4cd7f133a5dec697fd799f4d74de526e3f0b6e7cbb49075d1a32a4df733f9023599da6f8d5d2205060ec7daa17588e27107d2bf2c39cfaa32f01346d0509559b63a431b98bbe84f002543767045463ae56bf46e2cfd3babd232c222dbc0676ad454cb7a25480b010001	\\x5e6c25857940d0be5dfa5a87f6a5d3afc0eafb7136a7dc184758bf8229e7ae8fbe90952fdefabae5bf10a557a5ae2cbb6e28783b0891106b548ca9ecf6c9f10b	1680941189000000	1681545989000000	1744617989000000	1839225989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
113	\\xf864f1fe26e27409f0b4848f5014e4ec8333ee02395f73c02175d04e1d4373e8c437600f0790656a7d6290dfe87eff1818f27121db0e944fd160af211c43cd03	1	0	\\x000000010000000000800003b864147b7fa773794de0ba60d6933fb74b39f506950e25a9f217d3f3ff4b9cf70491d1f0aeedd96af6c67fe5288b9a2e242fc50f7be5137be106d08b8fe65026632b78b5d9eb5a8db45b25480259b39961ad62f813177346c7fb71e0d58531b4033dce0532c9471c19baecd2ca9e9f600093eff10daf4f7829603b17d66441cd010001	\\x5b68889eabbaf7261d1cb0d063bfc1c4e8175f4290f8bf45444c42367ce5a7c5ca8cc04dc29e493f89f3c1353c2f5a2a84c9a82b6408fdffcd2611a20d073604	1686381689000000	1686986489000000	1750058489000000	1844666489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\xfed0947d0bb1f52348ce3b9eb3042d61dd6d07c9f8ed6c30e4ab65cded9417db318a929c856e73f9994fcf5a0a9cb5cf69f0496ca144a40a17d4329920f01647	1	0	\\x000000010000000000800003bcb7a6fc4127718ae8d99ba8e99c3c358472e3dadb2b93551e0db272236ee9137d9332fc4a59713f591e9359d6bbfe0e6cb8c7ce40794d346464a5662897616795e830d774434fa177be2e02a59830067b73f271203fa8214aaf713fd5417b480f544901271d42ae898409fe84b47eebc6e8c53ffce57edc212bce3f98b7c5d1010001	\\x9cf6bdfa461701307dc664c44e137bd9ec730d720e16c55d25b1822d0e42e951116c834eb4d11e62d469a0c856c8e867d533610e82e9bfe0b2286745b4590503	1691822189000000	1692426989000000	1755498989000000	1850106989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x052164bd5557f9963b473480d4e504cfe084a4bb5455fa243907478190c96678b690b208a56b366f57e69ae57a95a511ad0c8be32d293a7bffa59625be970a55	1	0	\\x000000010000000000800003c7bef5a56d6ff90f11069d716d0026a8e869c8148cdbe168d762d0ba0279ed72a99ca78e89cfe88e2948f3c92e870fd0fc4d419172d02f77a5ade9c887b1d8f9107b88161dd9c4852b3f8434d3a356372e4f8d0bcc78cb30385319212e561361ca5f0eb4d2e88bd3a811b3c7c125457e8a3513a4e0164dcb82fe1a205d6069bf010001	\\xdffc9c72cdb72a453b65479d164d5a86c36edf16842191bc83aa3c698f9090226cd4a2031b8b41aaecba042ff6e3f0786ed176f3215311fa2e11b7099aaff809	1662806189000000	1663410989000000	1726482989000000	1821090989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x0639bacc1b6cbc006706a775978035f808bb8147750bcf9b4f988d185454e1c953fe0a3b308ce1f3c361a0e2f4ec8438efe159b9fdd1ae5e565aeb570e44a79c	1	0	\\x000000010000000000800003af18e5f61049a0501f2f45df70611e44a5e33ac3c707c0c2c8b66c22e34cd62b0c06b16474361580c113c5683ac42783663bd2aecc62944a17ec85d04fccc90cbe58117059eadf13c7ea665a7988737e0b4ce34bfc15f41de4bde209881d47b4322196d74c32fc9692f89afb2142b74761919c0f770e36507418a374c1455f19010001	\\x992ca0cfb2d571d55564da5b42b9a0108663a284fe84ea16f81b9127ad46142924cdae38508dda6a11a926d1a1d7f5bba475e6c9a08419236d3023ce22abd30a	1660992689000000	1661597489000000	1724669489000000	1819277489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x09f1230da39201379161d9fe6989e13595b1685991a335c56b75e8fce62e7f645518dabee478f5ac8baa800802bfdda540f5f5d7015d2fe600647ac989426778	1	0	\\x000000010000000000800003a7fa0e09708453199144739aed14cf91239e1389e8965819c8019c01f18f9d39a4d30a4498e8927de609997d8b03b940d7cc83196c564d3844e37199a6933a5f86f1d71ba5dab96db64dd2e757d32a45a271dbe17222c68ee2a044f4b8254b99f08d34b89d1d519e9c8b9d4fa67d37278b4322a2e5de3e6accd2aa2e4111f453010001	\\x28a637658da36d8aae33bcac56d3e081465fbd8a133661eb868aa80c5af4137fa540efa7ca661884c75eb36e9a1f46a29676d0eb374962b0ec70e5845bb1900d	1667037689000000	1667642489000000	1730714489000000	1825322489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x0fa19d939a8c906fe48010055d13137b952eacd82eb92f201828b50a2c283a6589a0e124af61bfa0bf90b9a8cca08a9e6409a460898e407cf699ccaef1e828f6	1	0	\\x000000010000000000800003abd8d73b065b0c9ff76b029b33e3fb657ed08f3414620ba40d702c7d34b155fc93fd0b5a2eccb33950e987ac5f00f9cfc4c0f9f95dcfab62b69d56a46fb5e01b92bc8206a9e66f1fac42e02b1d258d3766657253c29f153134f5612b517c9bc07b8dda659d464c8e72dcb66bbdfc028125f727a0343b530512587e35e6c55cdf010001	\\xd2bd22ac9504463899137719f69bf1551124b9886cb66948ca1e66b353d08a102dbe2431732d2620c604adee65100af22709defb4f9e021cc8fff11a424f9806	1684568189000000	1685172989000000	1748244989000000	1842852989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x0f29343af9d00a0707a9608d08f607ecfa87453bf8e4aa7c6aa181b2e93c58525f50440d595253810c313a04b28468632dd5925830f564cd3fd4f0edd83313d0	1	0	\\x000000010000000000800003dd97d4b625560843c58a9d8de774e2d2df837a5b5861913516f8cd8afae3d7ee1f51176b0e7956dbaf3e7f4d31c9c40d9df6d9efe657d0ac8a2fe0a433530eaad475cf45184a80f1d485082e5fe72956b91e0defbf3151e66dec17676cd952059728bfb364923346b213e6ddcb50a236fa1440c9c90cc6a957242aadc521f62b010001	\\x42a60d15b62519a9ec803103ec54fbefa76ddc4449c2a3986e4a488ea0e7b73e41b5213fd2c09255ab28e867dc439eec7b61de7f7780f5ce45134f1e214c2c0d	1664619689000000	1665224489000000	1728296489000000	1822904489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x10b51da7ce4c0915ce349c2e5cd673ccf87616b5333bba1cb5776cd3923eaba6042a71106fe1ca197dbb1a58ce099ef9c6245b969f9ac98e60e39f97f6a9f078	1	0	\\x000000010000000000800003c588c8bdde6ea3a6d04dd8a47827d258bd9eb6092651654055d28584fd5a68d7f926cc040982fd352bf0091dcf57f84b2318088005ab9cbf7e0c36b935550ca53d7aab37d86eeab0065520f394c91e8d713b551894897376cd37d702113a276c6591d0450eccebcc45dc70ac377c944202a6e6922e6401e84b3684e2ea7b4a69010001	\\x02c674863bab17ef15664310229c27de69e9086071ce0bd3c9a885a4311512e6bf5c4ef2f4fa31248cbd470699b69f24c62bcd4fe7e6c8c47090865e02744704	1685172689000000	1685777489000000	1748849489000000	1843457489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x18cdef39b38685936f6e6ed14717a2401856d9c8b84eaff60d524182f9730dca25ea12520517d4dfa5828ba34295ae087377080ba36c6e229ce10666a8063925	1	0	\\x000000010000000000800003c4f724502ff7f2bf1c3f43a0e9b05f1901f95758c97ce37d8c2a6cb4b8e354a87b42f600f58b3540645f9a5850be741149b6c84fa5f0b9a54a6f8aa17796e2e75b331b9a5f3b2da03035fc1314a65e3eab42918e2f4887b7e55c1b15f0782e27946682dd097313a49b381d708230fa0e23f949d950d2ea899a62bf0e3d76917f010001	\\xef6e1a89c109510b7c3c4d1f5c7f1f8a825b8f6ad48fcf21b7b085257d2dcee1fd9ff715a45dddd9aa588eeef772079f1bc526e42f4b0903620fe99f033ef005	1692426689000000	1693031489000000	1756103489000000	1850711489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x1c91b968f82aa96a681d93ee3ae304a28e034c243aa32e6d810ef13c705f0f6509d6cef42f4b5c731ddc61852829c1aa48fe29cc245d7c68fa218f94d09ac8ee	1	0	\\x000000010000000000800003a255d90aaa7bfe237556aefa47bdf34917589558ff5848ce7c25c253bf9e3de002fdf87e45d9e031291e29fbc693a63cd294a4896e770377fb8bef32c5a8b1c0c659cdd0c73e8188ebfc50154bf530e188ff3387875472a6ccad4f941196bf2db95ed5d35d58904715806ac9b60726ec80066363a5e22acdeb2172c6cbae036d010001	\\x8c0a035bfbce7e0e19f28b9208783f9428e78d2564d1a5aac82225417cd28e4223dc273fac19ec1d4a21c292c1a118eb1877a7c1412f7aa5f21d23ce1ea0a704	1661597189000000	1662201989000000	1725273989000000	1819881989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x1c7dffeccbcb13a3cba307c608cd25590c0ab9d0a632119c2ee6b0497232b637fc904bb2ea8e988484e82a4b12763b8d11f6bf648bb202ef59675121b0167039	1	0	\\x000000010000000000800003dc5f8b81d9af395682f5b1b696ad239dcc52380998488cfb21dcd36bb6f0135d8af45d96a5a6a0a0317940b577f070b2355077ba1423d093095bddf4a4e085b3a9db3c18d04806c3d44e9e181a2c2ab9636e3509edfc273b2f646031ce67d9fdc0a05f7f70f15d67665b5b1eb4831bc3f3f0e5bc2c965ec2bec1269ebf912e0d010001	\\xcfcfda2c17b5c6c0d5db6ca487996911c89039f6e2bc4a140b4f90d0ca19fbb06583af3c057bce01b9c1fcdf0d1bd953e5e5b0552dd5d51c1092cdfacf0e1d0b	1675500689000000	1676105489000000	1739177489000000	1833785489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
124	\\x2139e1155912d17887593e6ab9e542c5b5a068d47badace0084e7c5ffd33f86fa6498dc4d215671229886675f8783a5eb188577da963ec2b3bcaf00128b9510c	1	0	\\x000000010000000000800003c69daeb46e731862773091dd670a8febf00ade7faac8fc1022bee1ecaaba1df7907c122181e843b51eff0831abbfd225bf0ab7fc26704d2308191e0b2bdc5343de0605ddf5e87f1ab78317bc9853aab568b7800701ac5e0bacc80d65cca795bf69829b87eb27ede685f42a985b30a7ec9dbe1cacda985fd7a7dd293dfe197e0b010001	\\x83110f17a6459459c91ced73bfb75cd24511dbd241dfc77bd596f8279c260665aaa3d31723f57c3fd38c72d901a1555a697b39d48c303e3e8adf70a4c44e950c	1682150189000000	1682754989000000	1745826989000000	1840434989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
125	\\x226da1bc60eca881c3992bdb749e17c50dc5b63e5ef0d4714dcf947ef52f217f8c9fd213af48d40a852eddf09f0cf3fc2be361cfec21a50f355bfa49a5827a67	1	0	\\x000000010000000000800003bb54afb116d64af229ebc7f48430de80b192c2a7d73ba8d44c3e260a68e118e44e9a681a332031dd43d159a66f6dacca6deb94393187bc15edbbd9beef9341aad5f460a52d3181f5c437e745aedd11923f0156bf0ab85a073512f7af05c0c5df7134fd4feac9cce9d8f7b3f3c404630271dae3f8c50578ad834743294bb81ac9010001	\\x6a26aa773a476cc832190093662bf14be7b53a922e00b1a43d933b15d3afc9efb4f5de1af6e7b4d65a4ce79da1ea923a877e67991cfabd068fea5b410545a508	1685172689000000	1685777489000000	1748849489000000	1843457489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
126	\\x26b19a0d7f183e58e027463269c9e656129bab3a490c94ee47e49b7e3b5d92b17c74c09685f8bb90d3e0f8ea6367f2e931578af36a878759dd8437ba29cd0e1e	1	0	\\x000000010000000000800003d5a5a862ae1df4afde7d52c7ffa118f1f3c2024363c65eada949e14024e246db90b5051c620215b511728fee6a403663de6f088ed124b7d25149c9dd8bb091d414d3c12e4ff2db89c145abc54a9f0480b0baef9be43c158ee30bd2c6e23c5f89d2bde4d502215df4c825588c42e5992670afd0950a9c238328e99e473733bb1f010001	\\x7a04257b38ca8bc9a3c737efae367f1f7bb02cde11143370d9c45e8e5f0891e70211bbe09efaafd8a4d7a928a5d87a1605e453585bb9699457e11bedfcfde20a	1688195189000000	1688799989000000	1751871989000000	1846479989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x28a5813d003aa943ba1b012e82e0a57d69ca3313a1e9af81c830f5dd5db49a3d28f1b2380b36e3dec5069456e1d61f109602d86118426036fc87201ccb0dbc79	1	0	\\x000000010000000000800003e64be5b9bcd3eb5ed58a07d90ead0835d322fe3d9a03a0b4b617a106a5f08eeef3ee2d7bc94605dc85ee001388d5a9372226c2ce557cb98b0b18743030c486c7994c9278f93cd7da93df9fd611b1bd90be9d4385bb51c7101a1a4fa803f9c9f3edfd9fe22938aa314da2e012ac34cafae610bbe11bb893c8b281475aa6efecdb010001	\\x015777f9258b8fa6baeb2885045e0adafd844acc603db3b967876f26be7e2f8024b9d4f5894c3e9eadc36d6bbb1a3a032638dec966f688fc82bf2ee559965b0e	1674291689000000	1674896489000000	1737968489000000	1832576489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x2ae91874691614e0e9dd48e3c0abb0f2f748d4a6fd1c7da98ea8a4e11c4c82d24cfcf7129a4b0e2e8e12d191fe5d00567f8a8be8b246ec0cfdd8acfd0d5b48f3	1	0	\\x000000010000000000800003e2494aea173974af38d7915871321fb1dfd6a5873ca9b5cac6da2a16ff92d7a437ba2a4ddf65ecb9a3a84b0035b89fd5bb382dfceb84fcadb7f2a628d9f00b53080d0e89c8999f1d0afa2296b13f91cda34bef30422c68b2e644829625e965dca39f4a063fd6d44f4a68cea0f26d208f4bcaa1a914e2e644593289e393cfa8c7010001	\\xa5dff949890084e4e2a1f0a05f6fd0a9b8347a73a2bb60b21d1284a7610e5402cc29bf63aecaf4f5735b71912392eba31aabee2ad47a4e2d78635b9edc1bc50e	1680336689000000	1680941489000000	1744013489000000	1838621489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
129	\\x2ce95ea2a0a3eb7e5daf9f913226d20a90b90a5f45e95f2cd6d9b7d37e89e34faa6a1550320b5a9e05d513f38e4cdfdc46ede3645ca03ece82c850bc40cd9d37	1	0	\\x000000010000000000800003ee6633f60c4d9d5105271ba647f7df5b2b865d181960354b7a7299405ed6339840a13a16f2050eb83d19cac4b6840f6a7f9dc64c99e7bb90ccb8d28cae58734260df5b6fcaf1c2b65f44bda0f91ab074f08abec259487daf97a1ee52b142c66daeb63c47f2d648b058a05a9d66c13602fe553bd7cdc6954b73b011ff10ca2caf010001	\\xf5e72e87a64c22b760336739c77bde8f2f2db3d68114598717d53ac4c71b820da863b49dcc99bb42cc88be949e58d0588e279707faaa7e452e164b4865ed640b	1679127689000000	1679732489000000	1742804489000000	1837412489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x2d9183ecd5fc69a7032c6b7da037b9f22cd6558c62b3698cf357a13ff74bdb4dac5b81c04a5ac1d8ff5ff2afdc7d97f73022d9686c3386b13bedf8caeeb24b8a	1	0	\\x000000010000000000800003e1c13a2d6315e079a3c27d839c9d1bd1b2d98e1dd601543db5a06da5153cabef386d441126400001744fb036d873e4917269e5b4c227c1081680186039f11d659fef81294974b461ccfe2c95c607acd0afa5941d7e9d563613750a5c8cb6b55d63932e2f4a07c9762f3238dce66c14164c60a362543a1eb1d7501afc9ccac501010001	\\x863e61e561283a466cb20ae27afffa1d88e3ea9b200c8f2d90ae51f249f38e7cbf045032d645f2ddb6ac0df1cd0ab31b47ac3bc1f915d43a612e007981ee3501	1685172689000000	1685777489000000	1748849489000000	1843457489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x2dcd967e272a2dc752c253305c50f46b8379437118b9cd3656e12014c781d4eb96fd1201ff873aea5a049afb0d7ef447d65fb623a6a9f11959d4fd1cd094c532	1	0	\\x000000010000000000800003ab2df457d542d3cd3303c48dd24a95a3f8c619863d0cbee0028bb72f11557de93bd6b4aa3bc4ba99bb89d1068b587b4669db2292c1834c98a9b630209feb9690e67a2faa63fadfe71d2a13f392bb01c9e715718736f76ee426a5d6a656a52313cb4dea494567da2d4f0c6134e1bbbe24504ae80116495c6594d9ebf5cd62044f010001	\\xffb682914e26eafdc941fc40dccca3597f86e1b1e14106b376904fb6ccd108fd2dfed724f80b9087dc3ac322f29d0e0003dc38b894ab01977387510f2a18e80f	1669455689000000	1670060489000000	1733132489000000	1827740489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x2e911982ff4fe51d609cbb2d0b8e974f60d150d10e0ee09253e9eb5dbe1cc12744db797d9c7436d1ad29e93a4a150fdac23a7179f2f3d1f73e3634795829a97c	1	0	\\x000000010000000000800003a7fa5f177f0e0cc36e7dd878fb00d7bc04615b20bd44c3912f95da0c48bef5192b06de8d71e70eb1f055dbd47bdb398ebb3c0872ef99280fa5358cb1ce66c2f683e8032c3b8da6fb450ed17c0b48cb8f0ab5017c10c34a79cd83ae84c1596380bf3fcc183f58c20ab5dc6b8862f89a7504d67ccbf3c4658728960e22e4dbcdc7010001	\\x611ad11e9d33822fab4437282e0fb7e22a6bd80956ff1cb906cdbde10a942d690faa5715edaf09c4a2625b6eb9eacfdffb638e27c5b1279771546ca21a5d6208	1665224189000000	1665828989000000	1728900989000000	1823508989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x2f91d2d5eb49386ad8cf7cf946e2080d34b33af550a72226fa77a275eb3d3989318686f01ad30d2abc63b18047e772ccc4ba2ccc5a55502f1270384bc47d7785	1	0	\\x000000010000000000800003adf3edd22bb6a91567d5b0e05fa9888f72d23acd837b744eb86dd8277baff2fcf33befe3afad60e53739817d953b48ee19c8eb0aef027562b13e1c95e07aea31fb13304f410d5801698ccbd8cb17c879f41527836e4347b5bf0616c9d826202d58eef11090c80d1960e97415f6ebcf44573865edbd591e9f4e43b6b198a6bcad010001	\\x9803f25287dfcae09a68a9d989e643d6001f45e0f868d29181e97cd87ab3e98dec8d8d3b8b0a56851c2b406721e0a06da4c47ad9a46a1fa03fa3fb849fb7ab0d	1684568189000000	1685172989000000	1748244989000000	1842852989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x30c185409c93a6d07eea0f3dd9dc3291df910c81f9f86f88e7ca582bb0fde3ddb362a272bf680e31f31e2e310377812532eee33a224714625253aa673f4eec76	1	0	\\x000000010000000000800003e1367891d9cd6a4be6b3367cfdb59f3a41def9d039a9e2f27fc5db5b061fc8aed16deabced2210fd6f89e35a5f9f67d27ad7ed9541b6b14374d4f562a633575b96e68807189dbe43149f3ac23e9a678ebcac8360c1bf4b2478437981c398205c5f172aec64078dc96866090c697b978232453bf19d87efecb276ed23294ca731010001	\\x3a21f29aca7c263a85f39a25c57d6d6059d68294b4d0d98e4cc841d696f25123aa5d0be364a544860f8ee95b03e9e8da6fbb40f3896b3f322d6cc8284e09780b	1685777189000000	1686381989000000	1749453989000000	1844061989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x313921608800fcca7ad2d47811db5bd0584170fb2445696aee962f65ff521be0a4d2ea9482565e22f2b80095bda18e4d1272456afa8e8a8b3a27802213bbc6ef	1	0	\\x000000010000000000800003c9a3ecde3b2f0c850b30e5e9e3676bacd8fbce81c100c5bcd437c100169a10b039b82b2b39eb1bf67ad64e33780419fc02ae3109a682d00f5febf2006ea0bc888fe1008e66dc3071720a22db450a8bae2e3ca786209a94abae23be407b0b767370cd45416d31ccc16bfe620679eb714b906c3e3d07eb30ebfedbb162f6b32403010001	\\xad9065b9a18cc514da0e99078c1118fd0275b369e774eb63aa67fe5e449fa78f50d3668aba871ad3ffe09a2a0ec6ececb43be0fc922cd40f86354af362339402	1676709689000000	1677314489000000	1740386489000000	1834994489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x3229eb486a4ab4f7659d4b043c8d15537c59de3192224f379f3ed1e29206b29bf001d5d8c547947273505a90483c00d2cd25478b7208c075da0bb078ac509fc8	1	0	\\x000000010000000000800003c9e2caf3908850065750eeac9a44e09c310646a6f6ad0c4f370ad9d8ee4644a2863a6715266e457e9ed68bce437e2b8c43079c3b850c7e42d4001275356bcef1fb7ee8688ae579a921ddf5e667b833ab3d90fa47ff2feea39c1355f9f39e9f32f25356ecc23f0fb6faec2e62a6ae084c98fdbfc8da94f3a420c04d38260cd1cf010001	\\x6ec127531b093334c07dc9290a292cfa543de6fd61d5a0a850d4e9c5ab8ace9926f759421937507e25ca21854ccbce5abc9b95cb9cf866ca681d8446bb5e810b	1690613189000000	1691217989000000	1754289989000000	1848897989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x35119a5aac9494ccfaed7ebd4f0057cb64affd7444261faa7f87544ba15d6bbc43622d68f2898f70aaa2090bbf25f55c0f197fce4e598c61c6fa7d5f5edc1574	1	0	\\x000000010000000000800003c8de5686a088fec95f79e2d24415103a2712729cfaa53e8a79edffa6d678b4b84a48a3b6177570cc686371562f035c15603b01be03701cc98ed51dbe293561dcb5aacb51d5a9b52e52c0b5ff7449f8af134e334c79cd0b01a4bc3c261958203d6e1dcc1071f5ecfe0de72851ed99634e73b63f06888ad574909642b59958776d010001	\\x72e748531a95a366bc6c5adb80e6f219e1e6784692d3e463dedb1c54e6e8aec1741346efe4ed108015af6e4b5f0a47cacada2fada4e60f96568311c5b6e3f40a	1675500689000000	1676105489000000	1739177489000000	1833785489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
138	\\x372592b9c091392af9d3580456689cb4886bfc09a099526721f8190102ae8e05dedd6353f7d68959be173d6884f42e2535c3e51ef8afd091091ddee82056f4a8	1	0	\\x000000010000000000800003b5e007a60a9367ba02ff85b40dca3baacf35306d2ca06f29d32f5a8074340bb9f78ee25635471d4bfb66b85959061a75372dc3dff53619c1f5b81284f6f363a14311a7d55ef522494e36408f34a99a86eaf259d93b0fd04fcb53733b2c656d72accba1a3b379751d990fb6a716675fe3f144aacc6521db0e01d839fe26b901ef010001	\\xfb445aec150ff22b1b930627e235833f695546b780dddcb60e5122c25e27b03372cc1455bdcc882ef60fcca6bfbe3d9d5032a7f368eae12f48db76b71abeb900	1662201689000000	1662806489000000	1725878489000000	1820486489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x38fda46a0f7611d6b3cc1505930d884db6a95b2ee4f8ab3a9fae6bca511e05313b2e37d7e1c14b99175a129ac3c248ca73b422ca41352ba1fa58a751a0ddbdf3	1	0	\\x000000010000000000800003afab79a47982482071fdc309f10c98128f09df456446ebcf39384b06e846c06ca51f2cefb9b50533ebf2f06babc5e859130feb0a90a8a866854f0d76cd5691657d566330d123fc864852b05300e4d5b2801b62282ff1ed195add9c68171762de54187d29c1b2273aa0496e5d5f9e495a8d1ec37489e0c85a8ecd7460184be657010001	\\x9e6cba90b40d19ad43566c020ab1344b8dff4ad4abe4b1b62a32b470d33ea87c99e62ce6fd260df7e527603c6c3df97ffa444bcc71562c0238d1b34c82d4860c	1676709689000000	1677314489000000	1740386489000000	1834994489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x399d3594de54826e0261de018f3f4c28ec3bc4f60b58f803978224ec85f13c11f44460f96c6be9b8254cdff4fcf29c0f8279c79918b036e9ff84407d2138abf9	1	0	\\x000000010000000000800003b511386ac9a41bc94102253a6eae1038465beabd27f57bfbc05e4f76d135fa4f31e4c3422101619e05aae12e918cd2f14cef8b660fb4b71777a10dc660db5f79dcb90dfee5ac52e4512122e00a85076c440c318f25ea7b53ef658467a9e5248f487610c3671d81bb3c144b203aecd6aced7ca3c6007bc7ac281e1a7bdd63a97b010001	\\x8b49815bd22ef09542d7f9ff9d028c7624678c1870f437d54365f519db402dbfe920597baad2d7e59f21a3d0e59727037cadf5f544bc31acad955091902cab01	1681545689000000	1682150489000000	1745222489000000	1839830489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
141	\\x3b1d6481b5d1545b308296ef210e5c9222bb9379341f419cf264b646bbdd1bebe59265fbff74654d0574f6a580fd7c3887e5257444b3208199e92d8616b6b976	1	0	\\x000000010000000000800003a24572d48214e8f500b784e5c3ebb8e3cc8c05ade1186c1c58991357f1bb72f74734cc6181db25974cb1d8a79baa8bdd5c80d7b14833db27d332f0d48e042883a3e7ca5f9ac7834fadf12c64f2c72d56e846383fa72afc0298a82c70015e9721d1a89f4e26dc465a5884cc4bbaee34e6f2da710da78bed531dbbc460322b1ff3010001	\\x8b70fe30d28df1fd361c3093cae1bee1b5e27329126cd47d18e500e807230bfcb3a60582e024de8002bde1049df62fd8776961e5baebd33ff407ede935a45404	1688799689000000	1689404489000000	1752476489000000	1847084489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x3b8db44b850117692992a8f9a08d1f40fce61a45aa8bcb39aae5e9c1dbf9462608eb17f378a4407f1aed202cbe87b519f56c178af19f0ab0592eae6fa694ea33	1	0	\\x000000010000000000800003d38b633a1c1159bcbda494ed63213f7b00f300342038195885accced33dcc999bba6b5e878411b66248d274f4b26bfa82f62efababae5664ba1290aed178bbd33e49331d4a99c6f7b2112dfd9186b437ea5ae911836037565fc7405497bda510e764e06ec2a37e26ecbf862ed7f4fa9e56ee4f5081227e0fe83c7510f63b43e7010001	\\x07606e2417cec22876d6574e862f5fc9d718da3cae8ebfa28cf9c0e824ca2b9836a9d8a084cad9c153c052e60ff6586bc526e36b88f7d94ccc0a3a8710a96909	1662201689000000	1662806489000000	1725878489000000	1820486489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x3ccd782c9a701d18ba8513f2f651b7828318550c16fed4155ea36d97a627d0dcf00d7c25c423dc6d27685c9e06ae38b7cd32d953f129d8c112db3b5fe5e97c89	1	0	\\x000000010000000000800003c14ce56e32bb5765ad44d248dcd18c1f8f4cd5fc6aef3c9a468492a67acb6b8d193b447482088471547e74badcd2ebb60bf2f2b779a8ea3b547f08595e05a90a4a26c9fef431272fc1adc5ca6f2597222e38dbb5226b5c6bbe93ade5d7abe99638f8e1c1b27f9f81a093af2601c34a5e59c47c12e903be083ab2998ef2a3bd67010001	\\x69c7589805df38b5121986761a317471fe9413c8e9b1bb3232f2f1d21c24261f98e04cc5ab12bc7f81bac7ae439c209b0f7a87b39bc5bae51f95d3fa8458ad0b	1685777189000000	1686381989000000	1749453989000000	1844061989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
144	\\x3d95cc59a67d72013941b20f03b9708ca481897b1efdbed3d2aa4dd93b8968071e3802b231c4b3d4273215ef5ddd52a6cfd74fa71df62f10adc72a01146b5d11	1	0	\\x000000010000000000800003c2678cfed42fcb8a9923d41a4efd1beb573591085cee64bfe51e27f0850182f939c8bcbf6ca43bef26d5ca0092d942b106e48e654979a94ae18b37c099106635af0371471dae7c24e27b3330a4c7b9ec9a29287fa90e2e7d3823a994fdb47560a8ddcf3de2411ca62cd72e2995b2225e1372cfb18a02f4c471da527f475bd9bb010001	\\x8239e8193c9ee50dcc23f41a9485fda566ea48bc595101244b7e9cc4c651e5b5b4d41d5980c7ea95c8161e94cb4a18c342e98d97bd1001844472fc0689c8910a	1669455689000000	1670060489000000	1733132489000000	1827740489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x3e358ee4bb8c6cf9e4ba2758643da6fde706c1cdef34c0d95a93055b1446908774fe4a02dedbc3636ed63c9601f996e6ae7792a7f9fbc83c7274e081b9464158	1	0	\\x000000010000000000800003d2f4ac2348d183009ebbec411bcf6f55881954f0a8e750f8b3edf24c4541ab98d86a80207e561ae425a5469a48eb505fa3e51fb5b19ce5c97cf89ad4d63eae202ebaf42b1700b8589a60bbc27e7c224421471af2e8d4ebc017cdfbee4818a5f160ed6b7fc6f5ec982389fbb4a241463b9103ee8f1af8cf4f9c12081d3a21a9b1010001	\\xae04fa91a02751c1a1ea6520dada3142c47d24b918b1bdbceab92a81205f588bf8189e58c93b596f4f57eb945b6541842648eef1adc03df9646a9af668a5560c	1681545689000000	1682150489000000	1745222489000000	1839830489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
146	\\x429577a4f55f476d9cf44181c24da0c8f0cc36e6e12fe848fdd476cdfe742f017a15e77f116665fb587ab55ed86567ea4164ba188581899270d8f860c78df131	1	0	\\x000000010000000000800003ae394fa1dacf948bbb17dc00a89ddf4e1a62238ebf2dad2a4645b83b55bcdef05a58cf3e5007868d2bc1519e329dc4207653a11811e1ff85990111ffae575cd467196e6e3750a40ecd299b0dab269406b94444dc967f0dde29849cde3ade87698e1f55021a213c413cbebb1c6910b5588af07f89bdb8fb64040550fc7eb6fbb9010001	\\xfc74d9d01888729b9e4b95c69e7a869832d311c0353543d766c53fbf9aa4d33a9e825ae50103dd275fd9ca5d61aadbf1722e4febc3c2cc9e4039d23bf1d3a006	1673082689000000	1673687489000000	1736759489000000	1831367489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x4251f1fa8d40a22bc923ed73b61ba90e1d37d71006ec77148db168c4e3a277025216e549ea2d7c121da1a96b5891f7f08ee7702ac536a1bb226d229c0bf086cf	1	0	\\x000000010000000000800003a3ce53824c7e6ad51c9a5c34ebebe2f2009ee6a99b591647cffbffad97bc214eaa03f8ac4b448b976690e109f2d5a1ee1f558039420afa49066e117bd4b9a2332a7f837407ed2b3ee265bbd0df582dbfdd3ec7a8fc4a5ee76ef0d8918c093ae918ef0fa4f9ae3161bbb7b1c614458d47ecd0ceb19b6fe00cbaf45a112784b6e3010001	\\x20431ffec51068cf431a1a5f903eedf339e0ef1ab9e68b8756fdd5ecca7e5c5959518cc767783c828a58c81c881dad5361682330a2a7eae6c45d5d62617e4801	1689404189000000	1690008989000000	1753080989000000	1847688989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x43557ba84097ba40bac210664b2f46611cf94b55b5e77fbc77a5163638f58034f045bca2e74a2977c3e6cd83925e26dc7de86e069cc0353bedc087be5cde23be	1	0	\\x000000010000000000800003e95b9553015c79016da79274f45872c75810635ac04abae8241e66ae58b32e9ff3f2e71786477ae10a18ad8db25f6b8b7ca8ddafc32985e9aa2b38e234874af4374cfa3b3bcb66eef2b66cfd73a214cbf22a6d7fe410ea7c178691d9919b4e16c1badd096bf0fd7148bce666b16395b8106b937d67d8b65597c6eb9f688bdf3b010001	\\xb544fe4a4033b29a5438962c12dd7ada282481aa1372c020f8075bd63cb085b4b37d7e0bdd8b6cdc0bc64defc34e024c0361803e8a824bea079f9d5711df7a08	1683359189000000	1683963989000000	1747035989000000	1841643989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x46957c1233f0386f5fe58b5787f8ecd0d774920d757a730e3529cab3d9691cca23d719799d5c88e37e784164c08e674efdb6b69ce8c07d3ffaefe10c006f2af8	1	0	\\x000000010000000000800003bc4957fc73b252798901b1cb59594110498972db3a2103363a6c57180bf7e9c4e6cc1d639aacc0ea17b838509bac9892a5d934bb1880f02f4c767ed183ff07741854bebe89cb653966b5c02c55fd505f66b489cde20465ea05c3a459fbec411754b65d01d6ae6d37466c42ce72f5327305a7aff9a088cadbc6b03b5a8587f4cd010001	\\xb31823dcd6f5f306d66d2f66b6582777e4501bec4ec34c291cc02a1506f6826f9705fe8774bdb0c30a81ad15681c21884caa4010f46869b697485980e5f0e60b	1691822189000000	1692426989000000	1755498989000000	1850106989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x47599058bfc1f361577873054ce61c35db09252f08de4c76313a9c72b647e28b66c3477db063c71a8fe3ebbdcb13fde6292d1f90b8fdc8e3fc29a98f4f2c8126	1	0	\\x000000010000000000800003ce24866c3926134b3672c43107140e2d6301ae04949e919d23e706dbfeae696e7dcbb8b4966d16bf2688ce876c1cee965c27983f83de68f1bc0d62a20f7ee0425a363d47236211437923e15003a2aa871a870e55097abac0c98c98654e78749ac98c06a4934b621ea2c0fad59c83bd04269a028da9d4302c14265d0d25ac4a03010001	\\xef214fbe6e71b56674066eb4e7f58706f8387a88dd11337aabe19891a54893dfbcb54cbc38af6142194cebe2c1ab3550c75395665ead87b9ed7bba4b25864707	1691217689000000	1691822489000000	1754894489000000	1849502489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x47b5271d1dea6129c553e8f7e46d914733e4b4665e53bc63adc6e01d471a52f82a904b4a52b39d3742c899aa1bf3027fa9ebc449487aa59adac0f5ca60918073	1	0	\\x000000010000000000800003d2f081210abf8b32dde7ff299e47aaa12d2b99b8b4b3fc52ca66ad5aa27bd3ebdef698f74af28f4765593f879eadbdeffa98726a383b8cdfd2b7cd07f996454897882b8010aad33f06a379acea8e02f12ad6b7cad8ec9c41025e1ad277cd1f0871a5dbae2e39c4df138919fa5b08fb5e86f4c8f17eb3e62e924b488d10b443b5010001	\\x66d195f66da463fa9e6d5b97ee4f32cd1039d8f348025e925c6e826b2481ddde61be4d00d6fdbd9886f5f8e61715ecdd580e4bef82845b7ca5b7c9e03a98e30d	1665224189000000	1665828989000000	1728900989000000	1823508989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x4e25f3813a1d4284e205c80d3612e4a7280147c4b82c6edb80868e050905c736c187124ef97d8846a0477b2e6c4898e160cf0f0afb872e4d02f70b98319b5bcf	1	0	\\x000000010000000000800003b2d79063de8fbfc3683cd4ccea1143a82be60008d7f9dd44832c4f337e236e1864310332ce368d5a86183fe6e0f328a7a0a645ebd658c1e865e853a913adfa7e6dd04f37add08bacd547a025c5625c736e3dd081038ed9e87a9166e04ec3099baea2c0ace5e158e8a95f88447fec7f0b0ad38056f94a92d714e93a396ba250ff010001	\\x3469519742bdc5a028595537c92f65350ea362bd00dbc3f65ce98c8214344cd6ef8ebc901b7ca62b48d239f533e70033a6dec9c5c7b44e72c82f784657a75306	1692426689000000	1693031489000000	1756103489000000	1850711489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
153	\\x54157e946d0efb977d6da827c3c104a95c9314d7543553b4a3818e86d2f40caca1ed385a30bd55783e604ff40b004dd2e8ce588f8cc0cc390a3a91ef3d8320d4	1	0	\\x000000010000000000800003cd1828d1f07dc3248c3ebc6ab1eca634d0f05459c80dd47e06a834162c5bb253b4912c7493be0b74488b91de9f75997ad37339ebaff9ba994eab0780bda6c8e69df7a6d86abf376e86dc290ebfc35e7b9c5bb69e591376ee6ef0df4312c51e5d32ad1b06a4192398f74e523f21275f2f5bef446848a5dbf37fe0801250690669010001	\\x943489b929bc1807d9e0b22c1e733f70a4b42d7915c96f65949487422aa45c751f17c9c02b63e7c8b1c3a01d4b7d30baf83547fa953a4449b309c73332137702	1667642189000000	1668246989000000	1731318989000000	1825926989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x5589dc3991b44428a26660ea0ea349561fc01ac1884c1d7b667791d1ee015361db78ffb617650af175fe5ed90352cd4e78ad7e02a86d61e289dc96d155b71792	1	0	\\x000000010000000000800003d0058fcd2f2d238ed5703e5f9102e5809583699968d6f9bc891dc02e83a56bc90116f70a3eb0a041bcacaab4c9d0e81e6132518cce445a4288918e00eb78f5bc53207c77eb1a32f5584fadb09f6750e0df3ea0529c1ca1237e3d9b2c6781f80a6d848ba0259493d13d987b0b840fb473c368020432958074dfa2eac5ef3fdd17010001	\\x744e4e0ed1a57c48eb1095b879b2cf0de703b258b3591992650ffa70645d3bb1971388f99a37b72ebf90bf6e61e9fcf68a377670d44fab6d62d97d6f82185100	1660992689000000	1661597489000000	1724669489000000	1819277489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x554978983594bd96f5fdf920b2aff582a5eaee9ecf366f3578d01f74a16307527fd83057098ca8566e49ffb6862d62f69da040c4662257fbee6e611e62d5572b	1	0	\\x000000010000000000800003cb14444de17172fa571522434ce55ffa7a1e01a34fdcb18231821914c99a22d54250a5ef11757e420c0204cf63af53b08c18ec52ad09e286703a0b2eaf86132605c653befcef813631ee6bf3f0c3c97c8d65d537d2b1879e0995a267ceff6d2e490d9bb9129081f058828077e5765f42a551fdf5f0c80bde10edd01ad91888a3010001	\\xfd0155ec7485ca3b7322e44f4074a8f984be60c39f3d72bc859a4b461c82acb0ed2cf120d036dbfc0a0c978d6b7b6d9012c9fa365bdbd5ad636d241f0be2320f	1689404189000000	1690008989000000	1753080989000000	1847688989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
156	\\x5609f2698378caa315794600aec531a3cd1aae59164ec044b7c7dac7e716af1254d1f084f53f1f6b0dbc0b8b5753591589cf89a5bd664c7cb1e2fafad58cffe1	1	0	\\x000000010000000000800003cf3e432bf71cf59fc00d2378fc23588a241b0eec8ece6ea31291c5c7cd3e98eb898e3482d07a3bd5cbcda78aef9833da60742ee6af16724e7f39fcf57e6ac66f93724dcc7d91d82a3ff31d8e9306240c9edc013873986641aaad1e65ffe2e48a4d7d9161a1bd25377fdfc5d8d81116ed2f4f60f316b8f1080797fd0a828ea82b010001	\\x1a540975c82191378aed8cca9c42b4de738e71952a006978a655aa1589dc4a5a13815a406c32dedc414cb591ab6e88b0ac5860ea729ec568e13f234ea0a6a50d	1682150189000000	1682754989000000	1745826989000000	1840434989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x57592526ea3cf73a0e3e4df70cd582cc53099b379775abe71860892422008de967b1c77ab902f56b73f30c937d5dde44d3b25a4b43b1b869f9d593b9d1f2c9fa	1	0	\\x000000010000000000800003babd8a9e3d0a2e9156b5df5c17e2004063171f3d4492c88b53a4df8f7eed0f4f4a9e80b98ddf1b6378f74b878d17b90f1c5536caba4aebaa71cc53d92e0f33e950d84b65942fc6c74843f35185f9eb87ae89046f915011f37aedee2a5ad9d0c43ce1abec2f395db337023d89bc88e224b1760ae61c40d97ff61f38848125024f010001	\\x9758f795775a9943ed62c143777f72caceffe183f5154aadb80b757c4a52028e8ef5f231bfd73ed4aff0ed24af2ad75588d5c3d37df4d217cdeb6cdd37e5b309	1666433189000000	1667037989000000	1730109989000000	1824717989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x580d4bf80fe5f846ab3c42e2d33385e9a8f76a355c76a23f0a9b80ab3af3b17f397d03c9e75b796a61b4ccf65a4d210f5cec4e6d78bec1bdf889aa46d3b4f7b7	1	0	\\x000000010000000000800003bba8f341f36e3fedbdbe950f85cecf5495b8c4f52360d97bc1769f817cdf811aa54fdf2a0ca5fd56f6b3b9d6e541fae83b73d6b4c000fb3269d1ca91dd6138776b88b79019aaaaef6b2873fbfb2d139b27461095793c07c32575a4d2af49166170b67d52ad82e2446e28d8565a96c6dd90e4a78c1f6e8f82660edc72b3127437010001	\\x6d392fa36973b3c5a26840fac22055ece6480c1d8f52037a22c0edf02a006596a4be2c045c32456558596de2dd93cd8f0f6007206d3c133c659236978e99f407	1691217689000000	1691822489000000	1754894489000000	1849502489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x5ad90afff4f7d895acd40b9bda341f2a6e7e0fc150f9dc13cd0ecdce067e294f64e9cac6e595d3a18ce713307bbb26440400ff7aa738da232f26493a0af8fe8b	1	0	\\x000000010000000000800003b1646e6059ba56a4a60f43dad38c7736f091cb3924b48965bad63a7e49cd194bb9f1d427413ab614051d3f6b4f31c23fbd3be576fa7d8e9bacc6e0495f894b160ed32a2ddd605933540adbb7a9e7eff5a65bfe5f849212c743884e9fd57f656ebc8e05988f5590c549ea1ff078bada41684699e31255358c9601e42370a3d2f7010001	\\x7a3defc2a7d609cf0bb08876c7a92803f01de4bfd6439a6d62d7d06476ec80fbaf252c5081faf970b839315e69e37c86057ed959c377ddb016a4669d35250a07	1686986189000000	1687590989000000	1750662989000000	1845270989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x5a91243287a3bc4e5ce3416675ed6a7dff428abc9475e890cb2ad7daf2ba9fff1a239b60d7782b4d528afd32319b7ef4c399c2a960bb59529b57cfd8b7ad74bc	1	0	\\x000000010000000000800003eb30c3b0446cc6fc8b1ac2ccda45c1abd315902ec99c19cb65a5082b4e6576b6fc6630b1d296aa1c9f789c49188cfe378afeb6395421f24a7ce460172ec98002305352804bb53bfe086ccddd2e6906049624bf89f52505c2aa0d28f33c077642131947635dfae98ef430cab65bf73a685a3cc81e8150ece625d677b7128eddff010001	\\x1bda542e0879ad09d7c9e80174012c78c2baa6f0f8009d2d5c1d3557dbc5039fc773d1cc8904fb150b1542f5108ebafbcf67e7175b9bbc05ba9177d23222f80a	1688799689000000	1689404489000000	1752476489000000	1847084489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
161	\\x5dc103b2b03bc82a45e30846e487150a56b4514a4b43ffb8c6f5a9f43bf2d7f35766b803c03cf7208f1b2b53df65b6233d5d07a6d403dc02e35d6dc060d33400	1	0	\\x000000010000000000800003b4d3b71a91c876e126213a5e66d50fa0efec0ccdf1a3d4abe63620c0b0729aaa01047e37de8e785b624fd6a0ba39e4e8367f51a3b746d385ae678338f36ff1bb521385f3d978b8ba44696d2d859347b3f48e8bb9800a494cd539e6b29763737592acdf93beeab085adf18f62ec28337468818b3666accdfbe52021c5916d6f8b010001	\\xba7789ef02c0722ad1780b8e26568d29e037ed2160ba56d0eafa81a2b4de8442e987ee971634c7fe5de55bcddf891b2b4673992cce16728727c1600c4107cb08	1671269189000000	1671873989000000	1734945989000000	1829553989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x5e95749041eca348aa92b42a971bd8d87657fbbc56bb75aa896e320d988ed62c720a4a3dd3041026e389b6f21fb7cac886a4369fd516b574c31d95122dab0eb7	1	0	\\x000000010000000000800003ce9522de678566b2980ee02f3bee076782937f3b4ef49ed82ea64420cd0571c38b8a703226f31c25d338b4687c0949fe62e5c329c4f8b40a877e57b4700dc8b82e09478b30fad1178a6a672723d1a021224b416bfa4a302d4002ae9619ed5864c308f73eb1800aff0fa674855a1d2e077138b06aa8bb73ccd96c86eb38669891010001	\\x1f02bb5f304e264c5d00db38c5486addd19b9fa441a8526115133e94ba1b3d4cfb09574d54d4f97de484ae69ce639c2d3bbca54f7dbceaf4e8425e71028ec303	1665828689000000	1666433489000000	1729505489000000	1824113489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x5fc94ee3a4eab4c5db673a95d0e6ad6427735add416808b0795eaa6f460d74a9c608e5a81b5972e334e1b05ecbd94d655a033323646558606dc2dacc84129194	1	0	\\x000000010000000000800003ce04b3ec258fc1cc82d1afb1f6e399b4a588824084f7f0389ce587ac87b5adb83aff06ec8775af45c9ae553ddb91930573fbbba55309bc6aa22b019e456b8e55ec13f6b85c96e8310644c14c4b1d4703bae17b7f0b3a0da7a512da95efe37cca1d7f3d46122b20f896b68b25e2ef38e7f6d2e716d5271cba6e70c77c2d9daddd010001	\\x97d30b53ddbc22eeb5ddfe46b2e87c1b07ca88611fd07ab0b59c0481874b59b33c736c47c733988e30e957fb0adf4dee577cdf181acfe14971d121f58c3b5c0b	1680336689000000	1680941489000000	1744013489000000	1838621489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\x61993082a1ccca5cb8fa1e66bed6ef2f7bcefe71908e85e7234dba49b430182f377ce5408439e68cce72fc573f00271ab34ac5e5e93534dbb207e39be2d13e95	1	0	\\x000000010000000000800003de2b1da6c6dc78c25ef4ce507fcf078301c8fafcd3a956b315b24fca592bebdaa1d9875f31a9accb8c9c8ca8ad3ea90aa96f6b475a1733bb5a85f9ffcad1134653279947a05117ea8e1989fdb0b58aa34e526b6f60eb80db52956487e943dd0f0b769bb362b3bc0e9d036d20dfcf484056e6fd93df894470c03069114f6f18d5010001	\\x3682e0d09659dc404800e8fbd47e9f808d839599131779bec08d3ecb0edd9c4dd25a1e7a38535f4bb6918d396558d50f2e8bdb3ba70de815d28e574add291d0b	1666433189000000	1667037989000000	1730109989000000	1824717989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x62d94226aeeaf839322a523e11446080d23f6b3efd31a69a8cae5dd1e025af03fe436f7d42dbd219c3bbdf2a08fb510e190caae739df7414ce854cad12d53e20	1	0	\\x000000010000000000800003c20de431d239556ce21d64fe2899a1c154c63082e18928b734f299f558b47070676826bdab5c67d460aa64b02a305c9e3702da696e9bfe201117a06b61412a23e1c930a964d7e81d9972d17ac814687c78d0992a5191827bc1e7114eb36b8b7333dbcc00c51465201179f3cf66ef4d2202a3d7048b1f9f4a6994f12734314493010001	\\x64caa65aa335552122c5a9c5db2c1d75f1ff947bc4c758e79aff085d71772f86cf2a93eb9a8123e41cde60500bc89d3c5ca4a2ba70ee300d28e63804de087d04	1674896189000000	1675500989000000	1738572989000000	1833180989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x6415cd05e204285944a4242513b83036512b65ab5b3e10156b770597141d62ada89875544a4c04e816786fe769826a2aa178f54cf11177a686fa1837eb12696b	1	0	\\x000000010000000000800003b50506a0126def225759f0ced787bdb9c0f1925099feb4e272f36a48782b91e56340fce7c7d8dc07f8a4a432e6d1867e3bde6c85ea0772020e26f1be2a60e08da253e6ecc3bd17fb39a399dd674e2accf8dddaec6208d697c5f6ec33e0d5ac0dafbe336f87d5a8c50b35c7a5ca38b6ba978a5259049124611848737a3813e03f010001	\\x561a2d6523b35af375457f901e1665c9b9ff7d800cdf3c49c8248254dc6734c3cf70f3320577a76feaea33eb0e046847fe6d2337234e296a65df11dcd33d9b09	1671873689000000	1672478489000000	1735550489000000	1830158489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
167	\\x64d57aa364a9858203df2386f24b40149e021452c7e384a0f4ceb228f562b0987a12a0a51ad6a6c586917271697b84d7abb710cc97f15f4998d42a1faeda1f5e	1	0	\\x000000010000000000800003a74c47954c88ba463284d8876e3c5bc9e07d57db50e6eb9c39de0ce6bd415a8a2554932c093b75fd23cabae64554384e9d3931a94c4c6dde5714a928dabd69696e9bfc86208a97a1c6837c017f35672f4df0c67f338e4923102ff7dfef534b8dddbe9fbe9f92828b520c7aaa1daa9e97015d6da19266e9bb6f96cfdfbe880a5b010001	\\x6c434eea9f3980f520aac37e5f37a6bec5f3c9634c8af4b9bf539b35a5d629a3b5a04c519879123bb2b06a8d6be1f5d4a736131ebe6a3bfeaedba3a549571309	1662806189000000	1663410989000000	1726482989000000	1821090989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x6699b3653c9d59c8bbb5fd0676f0c50dfaa6d444c2e15edf606a04bfa7451fac3e964e9c334f159631473353587c974b8bb152a4a243a7d358cca9b1f7adb9d6	1	0	\\x000000010000000000800003cd7ac5c02d607911c80a90edeeccfd62e3c4a30af04af8253af0ec839fa5fce92dae799a48e9b2f0cf07f655827b1211ba358460d68e994a479d3948287f248d20be2c06a473191bcacd027a3fcfab9e437aa788fc65baedc7ee5fbb1263a9228052223df9287602e5e794815014044199f0c6750dec22f430ef471556e6c489010001	\\x59d8504ad930ffd63e53da6381d74994ec6774126fa56f43f4668f99a358692b5e5754068e810795e34fa70eae447e62daf28c117a966ff4567e10b7e010a206	1664015189000000	1664619989000000	1727691989000000	1822299989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x708de34686ac231cfd0f7d85b3f4c6b556157eeaea976313eafb968c2d65ac556167825e18e09423145bfd1457cc838cb5970c7dc3d201b1b0c570dfff75da5b	1	0	\\x000000010000000000800003b08d2f5ba5e120be96aa189f47eb9d78dfc531ea2037253fb422476ecbd5641eebe028871d3a162dca0fa3eadd76bf9a3e47b48470a378c8790eb87f0d0ef5152253dc935f33188734f7fe265b90973ec1dabbfcc10ae7740b880bff555389981d882db4167f0d4c1ed76830d6bfeffa890148fb6fcfcd35e6669db9d7940943010001	\\x873d04f72eb89ce3205cb8eb7197ae5b0f22584176f69b99f6685345881b5ead8b023d36edbf0383ad9bae683c4b31ab0b05d285ad21a29f22956dcfe8e8e40e	1673687189000000	1674291989000000	1737363989000000	1831971989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\x7349bb46244564f45dbf717d331a3d5dc919594d384deb9710e4443e1598e1a27b8556f6bbb8d470612cfafca556e956baefeb7a3a7e5b7920f27863e535aae5	1	0	\\x000000010000000000800003a1bc1189b5f4881c4b6d154b76bd80c0d0263af13551bdddfecade51ae2cfb06c4dca864f1d389fb2f75dec16479c916164f4d97efef9213929adef3da4d1ec936c2045fc93e0689ec72d85686884af116fca752e77403e8ccadf75d2964b2f0ae9fa4fa0f8dd0fdbdf5e911ad746bf78c6c1d9134328ab97475a34073d20d39010001	\\x6f01e04ad3ffcf75e182850f7ab1a74bef91bcc1fbda1baf5b1af0a206dd9df9d99aa5598a35bc36057dbf4646c545bc26e822b663259dcb2134c4320083c80b	1688799689000000	1689404489000000	1752476489000000	1847084489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
171	\\x754df1cff6f0323e0e9eddbae7fea17cac1ad4f50d3047098d781c3b1b0934a497db83ad21e4cfaf3cf7dd290ffda76d0d3005cda972a61f9514a102b4d58dee	1	0	\\x000000010000000000800003b99adc275415145efdcb5648a2150ddcb8206d1f0e6316a69167eb4afb524f41a2362ebc3b9bcc53953bfd880eea26a3f776421b083434e96e9d2a9fcdb6f260f741fd25dc97040149c97b7f7847f01df520774ac6787267a5b29c242ab65a98ac14e6f2cb3c6ff82ba3e7c2551d09cc769f4df6b26b5e922f9264121962069b010001	\\xaa3bc9b12b5e3493114803a168cf828ca6bfcb5fb9ce81eed0ed451fa92b85933a19647242ef206bfe4a5bca5bc8aaf2c527977364e4e3cd2f6e6bbc6a3cb708	1690008689000000	1690613489000000	1753685489000000	1848293489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x75412724f30f59675f3482268ef0c6a67d8561708b3628e25aa173b045e8c7c634c5b1ea8eb1d2769acb75ed7090fe4caa2bf0a106203551b0bd23fce420aa85	1	0	\\x000000010000000000800003d66ffef2feb2714fa23c84d9e26a997933b492573ab441d2105249fdcdca076bb2ae639cc170aa5448dbde2138550a3195dc0e5969c8e2e459b2302309e657387d6c0c1dc2a5059006ebb9c88d3ed53f3dada53e924a9da62c7561d63f5dc3970c27f967d0b43ca3ba3e7336628810aec1838e8db23a8ffdbaf38146b6497ed3010001	\\xd7a3a0c86a98d39b1818dfed26838c82e1712727c453c8d4442428103e7fa9259241991758f122c58fe1e1401821ce05f2acd613939f60e9e652f7ce102f0200	1679732189000000	1680336989000000	1743408989000000	1838016989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
173	\\x76d925c8686f7a178e30680bff7197482fc5c7855e89c11ab53e65906e45fe43a84b43fee03ad22b105a50bdc099475a528821efee023dae41cd06b6c0330c81	1	0	\\x000000010000000000800003c7d06b9654caa0295377e879519cea6c6fedf205c1d45b313b0db686e3540950b211bd59de64315ef9aabde5af4219513a31502ca0dece624b1ba03fee1fb3f5edcd32bf194412130c8f73e2dc8fab646111b04cb6238d00cafddeaf94de726bd3d89d80b9cd1ab9e7598a49fd679df49004f4135968b774df017ba831b0c313010001	\\xf47619992a18ec6bce6d8b18b4db0735d8ebc84043f61ccd613f184256e4ced50ef33c850f64218c493a22e0d590ce8a0577669dbd67935f10e35f050e37100e	1667037689000000	1667642489000000	1730714489000000	1825322489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
174	\\x7a3da931900d382436fee0f9e789df8d4d4a09332e60aa093217b2390b009ba03cd7219c122d824419e170156263aa4543d424640e7c6e37490b197364be1c44	1	0	\\x000000010000000000800003dbf93be30bc610c622e2702e8477fa53c69445b95180259b1e0e4365195b11048b5ee7d92af1e0c0f798c5f8415cb35971779b06fa33fd1dc043c7b041880a57800ef604684c5e7f3ba5824f728aceaa7878e303554d9897403f65406475ef00ee0a8fe6c7a54c42b1087a116dba80a776387e17973bdad34db265ff4c88789b010001	\\xb33f337ff6804465579d28c384dde93946481adc2196586b33686f2b77c2b2ebc38648c1ab0f08ba2ec824e4dc6d20efad625ede80cc27882933ad8ec5c8730d	1660992689000000	1661597489000000	1724669489000000	1819277489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\x7b2dd78703fc0f7b1d51e733fc978441c2c205f892200a8ea46752757d605043c294370dd3708e2ded60524c5564bd72313868609b620c7fa871bd6b02e289d6	1	0	\\x000000010000000000800003bda0aed5207b951a3bf7a32c94798a265c6089f9fd3920845256be6fc6c7df79cd6982f5341c0c50b203dddcb2cbbfa3c73cdf3a3269c25d5d269ecb6e66842c6282f90db3eb3bfaf8b360205a9090806d11bf6dc531c6b250136d302d60debfdc00c19c6a1595984332c1ddaf644f42f17e036c6967ce70421303562de5b777010001	\\xbe736cbb4b1bebf4e48413c2fad9150281882f031452a8381e695f31d2b585d382e1a5297e874dea18d69ea0f50b66e056b4dbd19d93b9f8d5552856c76e1508	1668246689000000	1668851489000000	1731923489000000	1826531489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\x7fa14f5234a2259f3691b92ad220f1045f98da0446bb804e1b88bc0a0e1b38fae023e1cdd98cd364825b66a04a5d9edf0272821632bf319203c008e70da37fde	1	0	\\x000000010000000000800003a759ee4da9547682d106135d6d818827a27a8a7af78394b27fd276e4e56d68987471f71e1ab8ab7d4f94349c6018c98a97dd2ec194fbf823b579173cd52958275424852f3d193fcb54a7e342683682e4ffee219659357def793e06f988afae7eed8e918a8d814aee4b50609723bca8a9f3e77a3be9eb7867e65e4166eeb25549010001	\\x94d0f220cd73e9de7043d5ac6819d8e419bde431df86b773fb1c3106e9fe1c54d5efbdc63fa9037a0386dd31eec5792dec20af38b2d59286d74c34ec6e53ef04	1685777189000000	1686381989000000	1749453989000000	1844061989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
177	\\x82b18f0806dc454b54db3b73632225e661157c30be47bf9822ef6302ad24e9689c7fad851554e633326122ef4c18ee2b31e40d4500b1e69801a93b26148c3b84	1	0	\\x000000010000000000800003dd3acfbea775247d120e1627f91fd3bb37a527b95d118cf13bb9e127732a9eb1bce2f629211b8416bd1ed951c6549bdd5bbf5bb98ebbaee36dcb1b337350d406c423cda94d7ee22aee103b3d5bec5b646a72a5645a06c0826f2402eef28b637aacd30e609324df4c75c069bc17dd2883bab0f5177089f282638aebab86ca60ed010001	\\x0b42b802cf4a6b57557081dcfe135964565059a1cde0d61bfd7b59c9532b3b6a6bd0c99731328ffa559816b70aa0bf1d305b2042258ba139c70eb9b661936e08	1664619689000000	1665224489000000	1728296489000000	1822904489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
178	\\x83f9712232e594172226966f09623ad0a68779a4660f15ab73baccaebc9623294fa0151c88ab4ef916ab0fbd507588e186ccf55d11b99918896db78b64e6b5ed	1	0	\\x000000010000000000800003e9b91c3fa48f32e7aed29ae98e2dd9e091af453af2cba66cddc8e9c25d35d7177fc3019bcbf59881e01ebcc302a40bb038485b9fc03e9a4e41c6405a271eecd74a2dc2a09dd843bd875b6e86bc2a68a5c9815a4fdfb8ce02fa274d25cfa010151171c337dce7bd2764125dfc3ae3a30becc304490e9d93ac1dc69df1f4871a83010001	\\x153604e8be128286e1dccd0b87f035685668a60bf763d99d68cadfe80aeea419b0fc6810f8967145c24048d1b8cc7d4f63782b16909320d6d912f7a1e19dbd0a	1684568189000000	1685172989000000	1748244989000000	1842852989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x883171e782512f647aad5dca8a4bc3714a224e56cc11bc1c6502de549798201af22e9fdec39aed9ffdd3e3c82265c2de38819ec8d906ddd396afc72e51a315c3	1	0	\\x000000010000000000800003c5f362b790f114cdc781aebc29e6b977fdda9ac9f04e43ee143e3c22a9a3e4b878316f11278661c471ca1ba499dffcc441f045d359ca00f69248cd3a77522b473b4ea744692aefc0016597810ca00a7fe9125ce988384c77ca2637b1752b1d6ad761664c2d22389441dd6365324e2da8d5b36d45060b24faf48bd94cd025dded010001	\\x0c8c366519ab679667f758b0e2c3a342b32b3efbd42bc6a5de39c4275c535cafced10d46a43d690163ba1d54a5646516991c153756e0cd36beae62baa5d78d0e	1673082689000000	1673687489000000	1736759489000000	1831367489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
180	\\x8d19e252e7c86205050b86b32935128ec49ccd4466eba7a718ef40c6789f6790c688bdf43ce9c90a6f580a6639db8c04e60cadfad05a8c971e127b875e0a73d5	1	0	\\x000000010000000000800003ded4744ecc9fc828f3a7fc3d66a925b1a8093fb1ac847f11b41cac54fdf7fde7f9aa3cd298f4178e8480c31918b63c1cdad97536819465011c2491d3ef70acd6ec323913c8da8d5b3f7aebf011dd8b64f888b203d180f89f11074c0477145c4daed5b6dbc2fdff2ad6070c32c4abc85a466599756f797c4b22b90965bba4c4a5010001	\\x77ea76ec78a48d833948ccc7d6de4eaa6b986a517fe0a32bcc338eed7caa5251965acdf1d72d1b2582edf7b853b0949fd3c650ca6def0fbeaa8536abdc7e2904	1690613189000000	1691217989000000	1754289989000000	1848897989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\x8d717b96314ddeed4ff99b9b8f17dd07395ab2f9aa7da6e56ed7e24918c428d63fbc88c712f916917f20649e97aabedea0a6a288877bcebfad5ff92bd2829941	1	0	\\x000000010000000000800003be5ccddf9ee7cb22c663380dd2f646ff715c44ad1b0e3228e081ddd6756e88e9c8d65eb8eebcb11223e6e605ee24b78d886d313285579781a6735338a8116fb099968a741808f7d0006553a37992431a80b4a3815ebb0df36929f5da72a9ad958ee411dfce2a7e02c421afd8d250159fd3e706e0d1209a71de7f87ce6173d0eb010001	\\xd92ae8297706ce811d97645a048e90d55e8f942ca1c277178b0ddce042a1f5a15c041eb9b3ee2044acc538a9c04af6bb6f6aecd87406ae9d979eae2236bf6d09	1687590689000000	1688195489000000	1751267489000000	1845875489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\x8da179ad27cf20e9bfae594d069611f2f1ee79d38db92eee54095b100b62a752e5ce9bc1ce5a2d647a5fac6a5bf196efd3081db5630b70c76ab5cc8d324c1dac	1	0	\\x000000010000000000800003c65d2dae8ea7e3911b600cc3b718758c1e18e1d4d0ae7446d5e5b8be61acc542fc85bcffa64b8b2fbdae457ccbcfd442b453a6b79b5574c02f37deada3929b7ff59a23d15231057b3c38104afe196c49e725c4ff5b523fb6ee89bf860c4ed54e93110a750bf05fb2848aad33db1e4d064dbddf7c7c6042c6c38049bcf816fdc1010001	\\xff09487d4b258d662dcae2d73f4ef3fcedd00f42dd69de511aea20ec634309b10f65f3447de76985d45faf11031027ab719ac946a7440ce6f5c12adc3ff95404	1679732189000000	1680336989000000	1743408989000000	1838016989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
183	\\x8de1c08e18d1b43e70fc5ba4bf445aa7fb67a54746f99f8baa9cfe4d2a3df8ce02d60e1c541f76beefb4999363f6391e4d9698138e1accb717c228adeac43a87	1	0	\\x000000010000000000800003af5b4a99f83b390b1905c34cb2f2b7a51b414a3dce8ce9269c42b827d252cd1aa0827d161d6989847527a12a5bf6e6def0b583900267085ad4d33ed1ca93714b4b532c6878ce29fbc8b6ddab2fc6a2582ad966de3d4b16e50552f52900b837067f893a8aefb617d753fa4db154ad34b16c6458d96e5ac65f80c42c7d4cebafb3010001	\\x8f461bf74c4cf159106ca6cc95c391184d7ba5aaa9046896da044b51cfc6c98949f017963d589fd089c96456fbeb4ac9a1c978a56127a52762814185a11cb604	1662806189000000	1663410989000000	1726482989000000	1821090989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
184	\\x9255bb78ff6992a1ce83c0b0fe8f359dfec37ba210dbe05ab4a9554973381a62f8cab6091a119d589f5f178f01f7ee9657a3a8a4f14d4438f7da9e9176c0e89b	1	0	\\x000000010000000000800003e5406161e03c0a81a0710c196af3e4613760cf8983492ad9bc1d9bba6a9a191c02ad8525b27dbcd3c8eed50d6142c4390fd4bcee44ad00fafa6f715961103488e30b29ec83ed6e5bfc69efe70d7d781277eb3c082fb1069ce7169dce4336ace977af039a46347daeab6923d7532daa485540c8e02b51e8ffd2f444c534930e13010001	\\x952f315d8ea118bf0b5aff3d825aade427f21e27b886afbe4dc072fd28be83383717b0665c7664e943e5d21ba2c5d5c66adec82fd4320eb95dca4c9716a3600f	1675500689000000	1676105489000000	1739177489000000	1833785489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
185	\\x92c92399639b2ccd3371a6bb9bc864ba90851e6bb27cfa91382b1b54a9bca462ccc333f8049969496ae07939db60325b49e8086f5301f890bb3c1acbe02c565f	1	0	\\x000000010000000000800003c3cdb278235adf0da674960ad8c9b2da7aff8019dd8279b35c97f082ad8945bee22b5f5fd0590de28335ad769fc5d6752c935a0c78838cdb4db47cfee0c61975dba6243d379e75a0cda1aab7d4b58341fa93193cd8518dd73bc0a7c077cd481e6fd36b9d4dc1892bda6ad878c7194dec53f0bac1f53c9eb9bec1a7e7fe5e302f010001	\\x0a1965ceec853704edec2c0e1fc84965d9f067a3a793e2b13dab0303281ee9652d91cb074194c09a673881faf9c0ba53cd2bf82e205d2e74682431785e122208	1664619689000000	1665224489000000	1728296489000000	1822904489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\x9265f846ec02399ed3f084deb1664edf3b0cc94ac5c426310335a39d191104e2939195988c31339da09a5ab0bc37ced372f32bc2f4dd8ddbb1d4353a7e1ca931	1	0	\\x000000010000000000800003a399e6a15117ce6dc94fc21bc95582ad58c99500f09dd0c1250ed20dbf4a56387c6236f7f66639df2d4b90e31ab54d2f6a36928b9e53d3e19e171040121d7971e83c0bb4511b81182c52ce11d253e8c7651799a5ab209df233671fcd0e0b62fa1d02dde82f2863cd868016dd13a45e8cf67d336bb7fd5d723015b2bdcf42909d010001	\\x0f35291d5284bd5cf0da987b530637c4a06a5deb09f33603e539223eb57704a17a47080bb9ebdffbcac50031775ae9900461a18dfefb09d4506c08200064b00e	1683963689000000	1684568489000000	1747640489000000	1842248489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\x94b16900937f93088814d3db794a13fca776160077d7b136ec9a7de474b75d15bbcae782d520c4c99baf886f5f1eed974020127abb7acdd12589fd47edab4355	1	0	\\x000000010000000000800003b93a5c60fe83e1973f025536135f5684f21f7b2c7496ff4d4cbc770f530043b908cf12551abe399e178d34c9ac5f884b2453e1b1565c66e6cd1592f14b4f9423822a3ac2a4a7667633b3569d7483066192fe72031b96c231a04fa2afd2fb9d25a84e604efc8b8b9e2fb1f3968fdfb0938c10719c2f33f8804ea6ff36c5ef9cab010001	\\xa0ab16692fd8cc150b78c0b31ceac46b83d3528b07b22bc65ddac40aa4edd5264023f03942bc33c6cc0d1cdc4c747f2dcd767f27a73f4ace68c105bd08772403	1690613189000000	1691217989000000	1754289989000000	1848897989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
188	\\x9e99f5a4c734f85c67bddce0a7cab9a1ddc6b63783464159e1d8a29e7b73775be8b2a093b7eb9883b9a3219729aaa4922caafd507b30d294d7825d7862131633	1	0	\\x000000010000000000800003c4b59c78aa2d71e72499c063dbd1ddc365893323e791c1fe1ca40cda87514aebd7f125a0b9e6299190636f3070c33fec08a3239a674c61aa90148e01400ee5d554951e42e4d6cb228adc0ea67337b99643ef15836c0be33f263560a59736a9f503d0f834315d123584407ab7be1141f8e2b5fffffee563384777b818f4c3a001010001	\\x51e9b9ba620d1266bf102e3891c69557221b0137120f4252892e1d9305b8f1d90347eac3f52f5accc27e900bce06f2fe9c5a05740f0ddf48c1c510fe29da5f0d	1672478189000000	1673082989000000	1736154989000000	1830762989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xa1991d9dfa9cccc46e9a507a9a1e28b5cd99e338c8df332168aadb42e70f211b2a355ecd26bdb18472fc7137520ea454ccef49c05e27ebf667573be068e3009c	1	0	\\x000000010000000000800003a1d17702798bcecfaf5dbdf1ebf450b7c58459a6c4e9a9e9561391ce9d74d82d522a3a7d3aecf99d395cc91b48c2221247509c543170919c518d49bee400274696a442cff45ee297a868c9e6e6e2d1c4608925bca76c6adedd3a215610e9c29ffeeaa40d5f5cf7d5f52c4bd83dca5111285438403db99527b28ae3f69f6c7be1010001	\\x705edecf9e231a586f97e8678b1823f5014a0ff3b8e2b4e75026db849e0d69ab3d9b591cc33bb08c70164528a2a4d50c95258c2523558e74b7410e084bc7220d	1666433189000000	1667037989000000	1730109989000000	1824717989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
190	\\xa2117a7a1c5865da8b30531272502c609d5d534a262f0c6f9a42a8e68a772b173a0261096c44cba49db944e91dfdf4269edfdc07be248a0a18b236e2bc1504ce	1	0	\\x000000010000000000800003c1b44f4c80420e847b0eb92cc62fedba51659b8b9f9fdb726f9587bc569966f149ac054bbbe024e405fe68f585f6844b1e65000e8d66b919a4d0b9d1099fc53f402e058a28dba3bca7a7908b26fc468c3b2e9f132d683fd609dd944de66afe2bf98ff4397e824106654fe9e586a4aa986875e752af9ea2e1f5a001ce42a6d8fb010001	\\x8213299c8927ba8e8dca7eaf88ed0070e0febeebf782c6d2cd0d862631f4fa6edabeed35e338daabd6da693428b96b7abc1dac51549e344fb12c448507eac404	1690613189000000	1691217989000000	1754289989000000	1848897989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xa4050d4c2b37d7048045ccbc5a598beba58f2594aa74862d301757845dfc28e04eb9d4caf425c2ac7f73ef392157cda4c26ed7ab111fe3fc11a559f4c50d7c7e	1	0	\\x000000010000000000800003c27da065091f3fe289b0b70c03e211caeb9943aeefb8f8353b3d3bbf0fa2c4e70541c7ed8ca1ec2eec1eacaa5b0e256cf34ea24712263db089e85d7cf68f5c1f876187a0f4513e19a165e2d495b320d4bbf47f5ac3ecf7d23b8be1af77d11e88f6905378449127eb4c5674b095fafd324caac1395c41b9b7377a7a08355c040d010001	\\x4b8920e35be63816b0f606ccd665342d31d539652de75d7c3dfc86bafa64481fd28a59b50878b672b31d1e64633f81eb46b7c53cf233ff50324cd1083b852903	1676105189000000	1676709989000000	1739781989000000	1834389989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
192	\\xa565b1f35774632f704439d818e76cbd42d0ee8e8788cef9b2d389c17a8f7d15e8b65b3f7422b048c80ce2daee8cb77deaa43e38a56a8af7b8618101f8d0090c	1	0	\\x000000010000000000800003bfef4d20de05716523249a5a31c898a63b41eb1b6ea1e42ac0a6f38680874528db4e601390962a392211647ead270379aabc1a8b733d213ded7c6575f76c162fc19283604ff8c664a5cad28ae13ce0d5a54b05ca1140bac7969cbfe25eeb28133c64294c50a476ea77e48f123982f2c15dfc7edc1e333a73a4345956bebf7289010001	\\x3908fb92ed9a1055322924d0f46eb383a6260a36802a35fdfc9c80a4c166049934046e31aab20b967e484b45f5b983156f8c637f08cf865dc5dfbf6efdff6c01	1671873689000000	1672478489000000	1735550489000000	1830158489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
193	\\xb2c101cd9e8f93947e6f640413a513f40024743f9d6e3e1753f8f4d744f582e72d5a7063004da78d04d807e3092acc614fe002e637659d64d9a64c3492c0ec4c	1	0	\\x000000010000000000800003df043c0858bc784e1f49f8b2a72d5520cb36372f676837ffe68e86ee66cd4005cd3c8a6763794bce91db04666560088bf1da10d89fd14e2aece571c8c32d2bf882bd9c2bfd42cbb1cecc87a560c6c6a8dd00fab00c641226312e0a34f27fb51df9c53a414b7c572fa90fe7f19ac914fb4bf32c0dffe9f1e283211c4e18417179010001	\\x4ca5adfc16a267c021f520e0505d169eda27a0ff7f798057f252a9d5bb820183027c5172c343fe53d189f894b9a53345268e65bf53fdd77687278f752e459c06	1672478189000000	1673082989000000	1736154989000000	1830762989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xb36d9414b609ac4f94029cbea4d06e4d71909d2ab0ca3f3765fae521bf2eed2918f95de2a74a2ab66f7b10a53547fa6b90143218d8394b4ec38493639833ce72	1	0	\\x000000010000000000800003c1fed7522b2c1115ae20a7489bc674f61e5a0b46d6bc14a256453230e090880176d433a207123b80f18097676bfb0f56d1302ef5eaacd4a61b8f8095c6a6bc321d4cc701e0931d0224c8748e5f453428548724ecd8afe93a16c10659e1980eedb091cfe42388839e9f48fe2aa96431f97155e0ab296376cf62fbe8bad87da73f010001	\\x4a7ab9233f538ae602a5463a8f8745a16f4d0c07e9351159143d4ad127ffda26376faca91c9ec8110cea78b75c60cf8b9e522f2a095770a4380734f245e75506	1674896189000000	1675500989000000	1738572989000000	1833180989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
195	\\xb5cd23cbf9abd3b765b22750b2296b7c9e1a25d71b6df3e1ba8c30c9d7948e799d8df8da82e0e8680bc63c0ef9633fecd1c5d46e16651ece8af072ec289e01dd	1	0	\\x000000010000000000800003c9a78b8fa1baa55cb1e599c4f69594448a2fc56f3107e33d3f0a0751a59c77c0dd3b988a479686300a29650932b3a9388f50ac9fd731ea375fd4b01227b5878a908adf012849b73553766059d2e4387045426e0a628291baa7d0dd0a675dc4534511d848f0e102ea42fd9c6af872c09ddb414d73da46f5bd4c16c2545c5e18db010001	\\x286fa62bd8e4519e54dc69fb31350103f9e26f162429ca6c003e1db7004490146288545927e0e1587600b3cd88c30e0590cef6db87854b95bd40b7f8f5b4860d	1688799689000000	1689404489000000	1752476489000000	1847084489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xba212630bfe6ad8d5e9e5c985e28cbc5e7316830c44dacba932afa9e022172bc2cc1c3d9908b5abe7e00e6e40276dc16c15e7d44c14d972c691308ddea8f528b	1	0	\\x000000010000000000800003cf400af9cddec7e5e102947336120306163a72063584f3a07d17f9e49cc091cca9e8a77adb6f538f0e3700834429cc89faec4ef78baffb6baa5d2eeb1408515bc5e74453b6c8964bac8b1ee4eac1f2ec02f8db8341c85ab70a1cc867d404e15692f4171ce99cec6eb1bf9a4bc0505fbce9c8b12423780834d5383f4f0ca75183010001	\\xfe8c52a59f7e6a2ec9b10f3b89e71bb89b6a731fafd9ef304273479abbc824e59806d1b3d6a4af02517e993fce32b5950cbb47f61cfbff424f56c215ad80860d	1660992689000000	1661597489000000	1724669489000000	1819277489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xba7d6171624d79ea6392c7c3965e5b69dbfac45e203eee374d4c669e7b25f262672d09b0b95eed145041900fddcea3415eb21b0a321aed55d220cf3ff283b821	1	0	\\x000000010000000000800003aeb975b5d2870bcfbe74bdf201285563f0d3ebe899a82fb40e86850717594369a10b0ce857850be0c775864dce052ff7b219b1646ab7a56f91d524906a423abc31653288b6f17139ab1fec5684a2414a2d2dd0fd8862309cfc32e96d054db2b35f846d9dff686a3b4e61b21ff0b7a88e83e7bff62fb06a2ac1b3a2adc2e2dab9010001	\\x195fc19c2c56b7c8d28d4ff2293c6d32201b82cec07670cd0e2098f3b8ff4e7cb33f34a712432d5797990580e7119c637febf23a92bf63ccd914ec54e9bf9b07	1678523189000000	1679127989000000	1742199989000000	1836807989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xbe01ef203cc25b0d8c5a8a327280fea39e6aedfdfc53f9137dea7d057591432baee4076b4d834bba9e8e1bfb7b7328c9503d88d7ee3574ed2504cd7613c8d594	1	0	\\x000000010000000000800003dd2581aaa2042431a8950cb99bc5833c396ae194414323858775e86dd72c704e48d53dd9e1af75304050fb6b32e44418721174a2aea4d0af92b05b323d32b75e5962704ee5830d5d16506576cfdb7103258c68de983c8017405c6c9d44bc2ea3550fec124d1b2d16aa5c2fcabc7f3e0785e471df9e0d9adb534d25eddb120f7f010001	\\x7367f9d7368c4f855650a5833181c5350654649f9f4f97b20756d65fc0c3bcf589fd9162537cd67e6f165e370acf42fa3123648fc902eee15d770edbb35f3200	1692426689000000	1693031489000000	1756103489000000	1850711489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xbe412ef3cbbec1978738af26d0a119a938e89ba46bf215fb72ef6b316ca4108ae7e618a48b5f2eb25670df914e40d8582c3eb471288913b15fe8d4fca23a96b3	1	0	\\x000000010000000000800003c965f8f657b0efb3d8961c0fd1b46961040ccda4d29cf3083f46fa46f5447e683126821b5a118bae0f59e6c8bbe8eb91807d81e53209576066a52dc34f0831c18bcfd23d231a826aee65db7419ab125f2c6942920abf8b10c6dd7cf60fc29155373604f7b5a826a10fac97fe4e89d393b551e6d82254765ae93c22709bf8bc0b010001	\\x52f126ac3c46467450cafd505919f7dde84bc571188cc0e06ddf9977bd4c6757c26d620663c6b2ffd8c32b7dbc8d7be7747f525aef161e8ad94f57202028580f	1680336689000000	1680941489000000	1744013489000000	1838621489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xc65db3f41889a40447d118803cf5a9e9050deb676f7d3ed76b9fb5f708551dc3f67b19c6734fe23b00ff767c3ddbefe9a423cadf5b9dba4e6feda31c5fbe1e93	1	0	\\x000000010000000000800003b121e7eadb40e2b32eaa2fb32000e580110ff025a07dac3b8f020d4d2da9d5190c5f2939dc23c9ae583b8185437b444f21a8f04ee739047eaa6a33af5a602ba0c79ba377a0db80aa4959f9a030401126a541b5e30b1fe7990c5db8a006c1dd7ae2299d61ba6a13fece5316b4240cdd155b1a95218a7258dd462bcada9dcbfe1d010001	\\x5c7e040c4d8db5e1141ba76032871344812f35cf8b9b023317e6ebf5c989e2dde8091f7fcc240f4cf7ace6f7de8265949f8f6890fe4f7ffc0d675624e8db7a0d	1668246689000000	1668851489000000	1731923489000000	1826531489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
201	\\xce8d77b970ec44450566e6ed64ebe74993ba9089e81a3126e26ebb0c1161b1850a7128f0f40ab69bdbcc413f9c6a5797e8dfa4ce8c22295c649fe37da35ac28b	1	0	\\x000000010000000000800003c96cce19f20904d22f23c42576fc5d14be8010c45aa5580645f394891db677cdb82831789340a56e0905fbcfedf5c3ca3cc2812dacce647474cdf64fc6a4b980604c462bd07addb31666c42a9b24cd08c96974bce653308e8d2d33a762d28932aea2dad4a17e82bbe17c467210159cc8b16833769d05326d720f6d8e2babaeb7010001	\\xd309b9d34433975f582301d2183439adc85948abf3f3b7df1f2bb86824765bc84228e443250f03397a5e6aca8096706766aa2d5c9a30e90ef3847efd44c3fe06	1678523189000000	1679127989000000	1742199989000000	1836807989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xd1cd27b6a8a7099ade5271507aa5ec3df3ddd4a580644fae2d683c2e3a269fb9b8d3df10c2a01401316c4b177f0c1f5a24eaf8d1fe75ac21a866b5029f23e28b	1	0	\\x000000010000000000800003a364fe58062ce1547c001cef4cb4119a80b1ecf0ba75b8efa3eb3104de4b59753e0150337908abcef05371ffea8ce9c6c0aaa85c639d9f115912a476fec5a2e28f2371de15e708abd5c7e8bceadc10502046e76c4a61ce3ceb359138f40a4a02c6a2f39d3ccb4c3b3733ca6f7d2d5c75afd56d796b84b672523e87f77aa4cd99010001	\\xdd9a7bc9526878964da55da4b89d6a4577c01e8bb5d4cf5fceea5f553e9df2a9cc8d32adabb94949446c66c29b84bf47f8b0220f30c07b47c3c9637cb7154902	1671269189000000	1671873989000000	1734945989000000	1829553989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
203	\\xd3193f5e3e60288e2593a9df8ee608286f3ba67e4f2e80d1fd8f86ea8429a12fd46a9eb736b7ca2bbf43c56b16444b3c8e449765811423f15b00308bdd18e4b1	1	0	\\x000000010000000000800003970dd5bbcabcbc563210dae90aeb8d37dbe9768816ef668255aaf57ddf489c66e5ced5bdcba7b649c23a2f97e50bd52ec07d58185cf7c8c6b27340bf71af608df0110be403b18d0387fcd33ecbdba012bce3a17d81305d0f499cfe2767800c818377c9938d807034542f8a17ff47b8780b0e89e46b56e098dc82d85ed0e1aa17010001	\\xc880571290e34bd5ad70a864eee1abc8dfe24af390480d36d734abe20ba8377d0b7928292b773e0d1834a54668f4271fccfd4a1b6b981a3c4f37914b669e9109	1682754689000000	1683359489000000	1746431489000000	1841039489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xd40dc8bf0fa98b65e3973e80f1c5db72a85d4a903e22e4d7e6b9eb67981ccf2fce0363ceb15ae8ec3c60c34e61fa2bf5e9b667bdc52b03c3ff07aeaf8f4f2909	1	0	\\x000000010000000000800003a1ed51febf10854c651f09c74c66300252c7562b4862c1063a9a1a27cd71d5c8a45a13e4ce34e4159ff1f73868aa25830d3dbdcdcd4ec29a8b26e23ffc9088eb979d215af6026ce9c4206afd6ce026a37b9953a60804b6f9b94421b915c7f9c93f6656f230d57b175e0c1ba8b1289000eac252ed6a69dade58efbd5765440a47010001	\\x6d51d1845e9e21aab86ba656a5cdb25036113e9e1b2f33e2048e59c9b743435c9b5db3265572c60e147ea681c694691dce600b50dee7b6aebdb64e2ae1303f0d	1684568189000000	1685172989000000	1748244989000000	1842852989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xd8b1d184ccd59554fc27ba64d79cbc4775f68f13f0bb9e1bdc4f0f7400dac1cd4cdfb281037d2f47362285935a62b94a43859478746d8478f6b09d82f5ab87f7	1	0	\\x000000010000000000800003a198b6f8d64cfc14335217c82ee7d111a4c223e20912fcc4db135fb394d88b989f32203630f98a3731eb338af526d45b99d2adca4b7ad264b54a1d3a17a8ce84f814316e1188a86fef44bcc0a4448a71daf7ae736e9d6e652267e7f44c4ceb19ad8bc3432dfcdb3601d6600d376e1a5d26eda81908f4482cf6c0492de8313c07010001	\\xc28001db803b4d06e5accb2f3e759f6032b72e93d9c3c23ba1e7181b32e0c8cc452dfbdcf46eb12af0f7ac6ba167ba9b369fc2581ccc398fc1afdf06f7e3e700	1669455689000000	1670060489000000	1733132489000000	1827740489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\xdbbd44a9e2efd926fe7ff5c70a4f22f7e73cbd1d2a8841796ac84cffda87fa941a45160fbc9b1816b427177b826f2e8df1a5ead35e001b83199c6c878dee7e25	1	0	\\x000000010000000000800003dcb5119267d1287c977681730bb3753a19d81823ff6bc1f11d177803e993064c71db65f2144c0e8776c351033ab7063550741a157f40928131bb275772bc2d7a499ea69d4dff86b9e2ed66262b29cf3a3e2052b44474113339a26a2dd645ef150bfa2c741ffb05747b9850303c0cc0c5224c1911e0484ee40b57612d35d82fb3010001	\\x3618dec4b512f5bef63d12ceb9ab1b81854c814d25f56d8ce79f2134fce7c14f19f04d56c59c0e5c32b36d659493dd819383ae5edebfafbc9f76c9f55f00d905	1680336689000000	1680941489000000	1744013489000000	1838621489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
207	\\xdedd19d72070eef87fc67b40da38ba7e6476f33331d85d090b67086d31586af050d46fe56ee3f61a2a88aee1ad1561c83c58eefa62fb5aadccc0a60c7be17459	1	0	\\x0000000100000000008000039a7787f012e6b5ca370ca004c44b943da716c0b12214bb2b9fed864a4990aa9ceb71d7596f5adc41feef4ae13df95d7812efc2b492282c1c4f8a14d4db69259c56c0c0a3c3a1c785687296a262027de067b5e3ff7843306c99055d9eddee2a0c6ff1cfa0ec86536b01289f6f073ec44f818d593b6e3fad8420d0d2ca017d2fcd010001	\\x596e4fa87d03f34a43b22444b950e49c0b40cced09d2ce78765b6c2fedea30246e596836cc12f9be6e49ec93edd771a9e18cf012915bb0d3f03315e4bd397e05	1685777189000000	1686381989000000	1749453989000000	1844061989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xe09948b48bc70753d9654cf79ad0475c1372cfcdd070e6b8cb9d00f042451fb9760c5c4678342702d281b13014da4b8024e8c651cd576aeb694b8db3c06d7797	1	0	\\x000000010000000000800003c1e9bbb736b7c0fa9141076bfaee407367a7fb1145d6feff497affa712d0959e01d4e2f2ad4ebbfd04d21975cbe67c116876406c72fc10a6b17a19520d045618ad9a2b97becc27048fd0be464937e659ae9c78f7c0c854443b4dc317c3f605beb7219c29a6809e44d82e3fff9240819a93d384f53acbebf734c16a44cd299117010001	\\xe792efec66dd376d028f780ba24f296dd17b76ebd114d431e792675f76c5644efdf250eded7aa781c792faf72b8e525a740b75b1d9bedb5298b4f3f5e60d8303	1677918689000000	1678523489000000	1741595489000000	1836203489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
209	\\xe01d4252283423fed6e66ed573b0f2512f8f56aa3c9b9aead808b29dc2dafdf4b7abfd7bed09f5dbd6f2f75082134bc3bf00122b372e1e09faa12a9e175903d6	1	0	\\x000000010000000000800003b9324adad2ac7d04333af0aeaad344aad0147c1387798b6bcf88c5c46f687fe1441dd0981c78ea3f1ee91225ef438a508c73376ba69a91f16c3dcc6f484cd624ae3103b57c5576441dc0d4896eefd081cf2bd57d04fd25b518d5fc1719f1535420f806740e46cdc54a960b775f97d11847c7370c7ca8da63f960ea1af7b6fb51010001	\\xce3d96f1aa53711dfc9106cf93a016fead46b221fae461d6d9ccbfaf9df20ef2e7dcd0c7d0c3c67dac7f64c872b5f35986a84275d932a0c8c017d23fd5ef4d07	1661597189000000	1662201989000000	1725273989000000	1819881989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xe5cd15f40c0d6378c7f2ee44bcec3354bfe4b586393b671ce08e398ee78abeb6f56626e58d3c0dd7df346c1fd3b952cee23eaf6138e05293bdb922d4e0b40c0f	1	0	\\x000000010000000000800003df0a1ea1643b8983c791284676a52651e7c617102e30a5380fd083adcc07f6a297c39c122416669ed67e951e9dec069808d3bd811f31d0bf7b4651b3fc46b736239e0e61cba0abc56a651b77ed29ef9964b6a015d8e364dc48e62fa28fb10c5b713af3fa2a30f9e3c84d06f882cddbfa01afe1b871ce00e37b50a141b48086a9010001	\\xa97ab72369ca64e660c3fe6723da44cf63c7a9c59435606a036732ff15bbcef0d23801692e27276158190c2c52473dd55269d4778156d4a837082195cbf89e06	1691822189000000	1692426989000000	1755498989000000	1850106989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
211	\\xe9b5958265d2a4916b122dbb9aea0ebf306241047272bf051cf40a9733b144dfd3cc22cf3e610aef58f68bb868cf3b594ad6eae6314831e9c3cf3c853e8ed895	1	0	\\x000000010000000000800003c99a8fb1751a274c0d14bf1bb495c29c9366e6fe00e06db14c9255ee8b94b2943198446202c2cd31bd5f69198f82ef451d7a974752a9a85598a464fff8f26c8536467448e6b5021c4b2c996cc5df67a6083136c0b69ffc2e2e5f2ac56456c919f131eca9761b6d9a2d61fef828356f8a2d5cf44f558fe413b2c52f443626ccd3010001	\\x08998a4f12ea2b260853fa7f2b8b2ec7e0f1dbda8ffdb64a28775a619ef9652bcca36acb448645253e48f8e8e892ceb807156b471f958f3b1537b4f3fa5d0d0d	1688195189000000	1688799989000000	1751871989000000	1846479989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
212	\\xec3901c9a68afdba317a444b0cdefc832ba0e6451df89eb277cd77c4d066e4dcabbeec2fa8e736deec755ff404176ca8af418279515d57fb386ff268526d59e6	1	0	\\x000000010000000000800003a67d0d3addf468ada872cbce26b0f262185bf7174e2210a4089b9e52858981cd8a74d7eb7df673eb5bf58e1bd2fad5c23a7b6b2ee3c0c60a5b9caaa4a948e45226d8320f9e5864660308ba86f6643cb28a8b3bda31c6a95e8920b54966e93477a5523d2da450c2dcc5853e9d3ae04fce85a980bf642f3c2ec03bc8a3061aa42d010001	\\x6fb1999994ca1c3cb206c3380fc870f6c91345e322401a544c19974107c8ca4e9dd3a1ef0e7494f2f53ca4bf121c9838d3ae2cfba992ed05e87f22ca812fe503	1678523189000000	1679127989000000	1742199989000000	1836807989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
213	\\xf4a173a2c44084e462f537e01b7d8ac5fb67134aec3af234393df7973ce85621e049e92b292b10bf8b4e4bf0b84c1bb4329c244f47e1555d55d007322b181c0b	1	0	\\x000000010000000000800003ceaeaa6c08d998ae3e699761332f02a35f3b3bfeec02ea1710d2eecc049c21df16fd7bdd783ecdf41e2346d667cb8c0cb1b7dcac324994bdaa300bbb042b3d8921eac51ad28979ea3732b32cd900ab5b8807eb3278e7e4df6897c2c91cfc1a429cae9ecfd1dd24adede33cc4e5d4d5c37c071cecd1da3b34754d5f2b2fb7ffe5010001	\\xed8349938d3a73064cfae8ee44d07c7aebd06c12b67520cadc3695e9e0c5b2eb3d5767f959397db46c925659080cfd78c39d360dae500dc4243affa15ee9430a	1668851189000000	1669455989000000	1732527989000000	1827135989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\xf55d7713444b05afdfe0da24b7a4ce789520279acb1b801639d164ed96a5a6461dfcb7a229281ec14366ffeb7dee55a582ab6d63ab21c2df9f3ab8e80768bbee	1	0	\\x000000010000000000800003a50e0812bdcc65168c66ef0d8a95f98649bedd1d287a18aef52da1bda9ed8a649ed0a8416b9ec7b604bc0914ad46fc68c042ccc8b7a964424ad1de3c801d40fffab1529cde0b80fbdb8015728798f137e0adf0186e61a459169f2817297a550961221c4e542de4af215a69c0a4d20dee19e3cbc28a59ff9698d21864defbc423010001	\\xd2dd9b0c940634359f2512f2ad0f597e2ff856f5d26a6cc1e65068f7474dc7d20b3da88144c91d55a8a65f1efe8c55a1e710fe1f7819b3c2f0549fbcb672780d	1673082689000000	1673687489000000	1736759489000000	1831367489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
215	\\xf639e0e59389aad0bb77b401f72e2fdf6afaca785aee527e26e9b81b8d87ffce7307929aeec17528915d5ff2753b84120519bfd8295962b8a1f7ef1f75dda11c	1	0	\\x000000010000000000800003dbdab50c3ac7a9f779bf3476252461fb7bba6864b62e14c3490a9045e92fae5d78c570d3496473e530389cbad970b717e36e76342c6b23ffa70485fd3d5e060f8429ee5ac505150e45c6d9c35b977c091e500f6cc060e5b8910892042a0217c204c47fb89e3487571d31f64982aaef1e620d9fe59d28cc34b25848b561f0c94b010001	\\xc6136f8615ad47d5a3a970ad3b6aa6b49fc2c3d767dd61581a5f96904ea0b17a628637a363883048f8fe5dae0c54984380f6936edb53e2309968c83e4a2d1f0e	1666433189000000	1667037989000000	1730109989000000	1824717989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
216	\\xf711bd7c4b59eb7c0f130a269d54d3ccd3133bf43dc112f93f5411de55aaa269519a29e65f249d7e5cead4f5b6564e8319f7c0587623b417ad6cadd32d101996	1	0	\\x000000010000000000800003b054086f7e2f7141b9ab8d967a2b9f51cfab760b4a030d26bc53a017e96b2eb99f6aac7b870b8ca5a986c8d9689b8bb330a0dd2d1a1fc057f81639b6bdebf0eaac9ddf65bb924da4b18b4b7e2052e53cdc57adf916e6d6ecfd3b3de68a59be6822d4ed114e816bbdc14098c81961d898c46e9b68905df8807a5c86d50d476b6b010001	\\xe9ac5ad8fb1973679780daa7dd26ce4bdbf005a32e6ffc1f890ead8a1650176983e276df7bbea715cdb97b2d0140cddfb8fa355ede5ad096ae0319969926bb0f	1683359189000000	1683963989000000	1747035989000000	1841643989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\xf865a0e3ca520bc2079bdcbfb9384afe25b61c5709f1241b5063f1ad2b94bbb08443b2a7fa3477db7c873dfa9feacd38f18fcc8b8f12e38116913cfddde5510a	1	0	\\x000000010000000000800003be5abe4a0066217f1442291784388dc1af3dfb340140a281e6a9be8b79ee609ed28e6e7ae8ec7f4ebb6691ce035990cdc925ad8f276e2353505f795b22f881a4cf56a4c9671ba74052ece1738e24c32491f7e0d6719fffc8409db1ba7271fea6bbf99cf7d70ec555009ce87a5c6bce955fe90568be6baaa1226cbe05956a5001010001	\\x80bbff85f11bf733f170d2861975b0c79b4096fb7e9d8878748c824b50d4caa201f4bbfec8b6d19576aa6f5b8a69d0ec1f66809bef7e30b89d26dcae49a1fb0a	1663410689000000	1664015489000000	1727087489000000	1821695489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
218	\\xf8957efe51752d4094ff5d1c9988f7b871e5881b570b0b7b15b8125166798cda98af1bebbc7b66bd8a1b1190e1c536b33ada01c6acb28efcd20c78cf3567988e	1	0	\\x000000010000000000800003b8f496f16305a624c8b94ba4f962200689266aebcd0dd753c7be3f4823e0fec1ccd6a31b19498b1c8bb5eb401a1ff984e3de13ea6ff3c8f76472660d4cd49e9700a18b0bac7effad628dc1c073b829867ad8d3647228588fba7cd2b6400ae7eacbb61f3639ad1a5715239236c5eee1a99e37e06a5fb94bb856b966b747169b3b010001	\\x965d5f219f24a81dfa41bfcb0cfaf63e6b270dd549a4fff6ba241b8cec64a487508ff4429d7c49fb4f0723ebf0784c56ac6c3d11fe07b29874ec194954ece003	1686986189000000	1687590989000000	1750662989000000	1845270989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\x059e873cd8447124fb4a99991c78002bb89905eddc1dd733e84d552a0f42cdf8f6294229475c94f70fb8f4624db6c42b51f91f5244953a65b7f4517d3a5219ae	1	0	\\x000000010000000000800003a9ce2cd533407181b1a5109168da358c5986084153854f963f1a106ed28e61d1441cc03d4b677220cd4fdb06517942b337611839c071d1dbe6c2abdea9545bfe83c75644eae534c020458299249d1a4288b3b6def6880579f4638e953d68f433dde972f709390a53481240e373cdd627f0e3cf7acb2022c93ce1136101bff0f9010001	\\x738ee274aa8a828f66edbaa803c47b0b3097d58529e517e31a676d62f24eb6968a418dfd4377e5c37d584a3c6d15f9b8739a06fd2a5a67fc1755ba20bcfcda07	1679127689000000	1679732489000000	1742804489000000	1837412489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\x08d6403cf9141885cf798ea7e034e51016668e554fd6c35741b66175cf403325ef1a351b0d21972a82b8f9fcc0f127a67ea4d1a96b02bf7ea73c07ad724627f0	1	0	\\x000000010000000000800003d6c638e575b6cd562f92c55ec72daa590a6d54f15e7e4a0bc36db5f69a0f93a4e11f08f2fe6453fd397e624731cb05664f55d03b83c192e14d478fd6f95668bd525b0a4026ee9c622474e8a6f439024ef272ca88de3305349bf6b67b5f66468fe5e5234198ec974be6b4cab115149333d818408c3f01007dbb06fb8582f66bb5010001	\\x71517cce6b751f1976b0bab047e136bb4038a35c316de7519b4940369f297ce9006853da62fbe4eef2090a9f4f03aa0ef799a4c3adaea56f24c2be6c9fa14d0a	1680941189000000	1681545989000000	1744617989000000	1839225989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
221	\\x09deec47be3f34ed8d1a0894c7b2f9b62a2ba22292696edccce6a7ba469010c6d04b9322c2cae4df6484904b8f3731b8e3f59cb28a2e09965db33909a0afdd48	1	0	\\x000000010000000000800003c555f889c824975b972d231f94dec66fdb2871174c36cb35743944ab94955543fac57f084ac64f5250e3a7aeab9625e20ee192d49d06a0368f5e51aed56b36340e124aec37ea50265e9b6ab8dee838f486087d2ee7346be93cccbf522a3487e74183144b448542a0c979b4c628f17fb13052492b386714e0fdd1414c4d19f4f9010001	\\x6f4f5cf46a1729332e7bb51a89046a21ed28747e6c36f66b852118563a115300069616fc5edd8679d790b9691ddef2dad8ab2998cb19582a79cd614177af5605	1667642189000000	1668246989000000	1731318989000000	1825926989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x0a1af1f7523c42665ac326c49af7b632a4f88a022dabd55fae1c5ca22cda4cd6a375d7d43b9cca7a04f30a40f1e49c0be78a24c4459c381ce035b4556bae1058	1	0	\\x000000010000000000800003cd64ac4ccc14f6387792558a0c4b78df561bdc692f5014baa69843405e9e302b437690a3937995f7ebc02e5983257081175b842d10dd1e3d4a7b7af5a96ac959437bad664d72d4e8f1d1e1d9c52d4d30a1a9e988108b24bdd7adecdb528f5874396821eb0940a4638f236c571ff5a5cae3ca43211862ebc44a79c1de5874887b010001	\\x48db533ce1b50ce32da9d8461a6d9daafe7e8a35bd8d21031cb0d4ab8ea77b09b142074c01e2044b150867dccbc5c83d1038776e3e69eccf459781e25f4c320e	1679732189000000	1680336989000000	1743408989000000	1838016989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
223	\\x0cb6d7ab84ff0d91e3e55ebfa8becf22356d594d5999c2d43051d7487ad5cdb3c813a9fcf0bbe0e172fedb3bd72df5f8bae4797dfa5cd32f0cdf94dbca89eec3	1	0	\\x000000010000000000800003ce5f494779363ce52e031b763955a40a1b3d27fb22ee80e9136e82cb6f2623306d43c177c84b2c7fd1512762aa59e8a9ed8a03505f3b303cb11160a787ae08a9e089e5a01957c8f9fa452696c9f57f75e39496669cd4b502dcd4f433b419754eeea57b65e97984d1f913be90b9cbda14a14b0d93d8b1292c4bc1a94b4005537b010001	\\x08e1afdd377fe33256047108081ddcb02b7779de3c6010b884139e1714ec8843541179230a87e824867c74a1e11e0b5845ac2b22a72242d27e63e4898bd0de01	1684568189000000	1685172989000000	1748244989000000	1842852989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\x0f9ee96e2c190e06f65957c32463b6f259764085e075c710fb1fa0ed72b8967eebd2095953f84405afecf842300bdea1aacb60e6f2e9798f9297d819ac663cdc	1	0	\\x000000010000000000800003ce458ca27646cad94ddd4a19902f0f4899b891190b21cce9619242aa0e40ae9aa7ed99e6f31b2c115fce67cb94164325d886ac53468879bd42401759ba8df331632b8940c34a4f68ff01e509c64cb3e4832f8a2948cb66a24506fa84cf1f53fff199eb61122cc9480d713bf3ea42593fb9b0d01c07e2217e0dfcd3300c812189010001	\\xdf28170404355ab7d407d740300939e935ff21eea136469c33ee24aba0e47d4b53addb986287c3409bb6ca35dda2d10db6c65a1d707f18257e7f04c120b47a08	1670664689000000	1671269489000000	1734341489000000	1828949489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x13820528bbe0e579409e91963db197e1671e5c48af283c0662e419d1644b48705f4e4057b2329cb17b3f2dce2793fe2a1b3d0e44a6cca9fc02550b854e6dc28a	1	0	\\x000000010000000000800003e7d6bda944584f88249471273d08282dbbb853e2cbcb846423b107078f3c09c2c09ec71fae08799f0f7fa985012087fc2b807970b65d91ab2d3d09a568cd7bbae5d65c78aec2eb77781dceaf90445cc2ca3f0ff8fa4f1459329e1754084182bbcaed6943b3d8ceb08b5563c6f83753a6cc1532e5466feb14261e26b822091ddd010001	\\x27b5c692fcc46d3c4bd5d719f7785daf8e818965eb1a566a31c1679a0a96fd8b9a9572df1ffb6b045db363203e6544dda66235c83b1d6b6aa54d05c2d0a22306	1674896189000000	1675500989000000	1738572989000000	1833180989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x14f28648c401fad61c95c771a9c90e9a8f775913ca51e84ae9b0fec8c8fb4e8da552540852e4d3749e515aad6624d826bc08034f4ee3b4a9b4ecb01eea9c2433	1	0	\\x000000010000000000800003c8482807a0bc38cbae7d9f62b2ee2246e7b81d9c6f1c9abe70fcfc5810985c07ecf04759d78c59f31cac100cb0dd3d88d0de14506cdbe0d8de90abbb28630157d4c80767c809f9454827d0330cb953af7b976bfdda5775c80780b7b519e90d4c8acafca9a04fab3e98a307503b34be7d43215595619dae9b397753ef38650987010001	\\x3550d255444ca40fbb033c46602f0702714903054dacc7125e652f19fa14b5adbc88b4f20263991d8da86fee8ddf9108fb6595e47f2864c53e284f1303050005	1672478189000000	1673082989000000	1736154989000000	1830762989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
227	\\x15a203adeda6479f7902fc58668040f88b4b907fec6382daa28e4367481a59db3d41e1c1e77d73c9a0317a2cb3eba51140030a30e3fc984d457c35deafb417ab	1	0	\\x000000010000000000800003a8e747961dc4178fca6e384c3d8b5a2bffb3724c718b68a0981f0c14f5089cad7b011444f07b5f406757b6766b7c6db3a7df759fbdd37dd0763ac404f47e066be29583cfdedd055c8e4b114cd83957d36c77f642e9781d626794759a70ea73480c8a460a7df4e781730d7de5c667be1a2d41233d0a52ce06a136088ecbd16071010001	\\xa408568ca3ad568a85af441a9e8248183ea7af27a9d9cd5ce8876665075a374da8429166939758239c0b0dbb6806a32e6abead69f512e0d2ee865028ff66c90a	1680941189000000	1681545989000000	1744617989000000	1839225989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x19feb06c8a641395dbdc682461879d2966f50a4ea9f89a4f3ee0d5756e45165827d317592f53ab9e0b6d385cb6f39f1faf1e873ae4d1c112eae933dff97db337	1	0	\\x000000010000000000800003b7d8f74617844d9f8cc7cdc57d717206431957d3262299ee911e1a7e015ca582d24ecddf324e5ec17636e739e1cf9d8b5abfd2da9c9df876f43c098872bcdc6ee05437bba9cff59b7500362c1e7f7542e4e2fe0c1ce45134175f4f42f86b5e349a1606a28dcd9ab15a05acdc7dd5f2e41887c9a371f81544422d4f8603f1fa27010001	\\x85ea85a114dcbea7507c7d6a999a86e9c06f55d716beb33f8f492c2235125eec3644b951c117863b1023bbb67f352cda9e3764336b410eb758fb9025a305a604	1679732189000000	1680336989000000	1743408989000000	1838016989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x1c3286b5ef9b965fddab1df91813b5c647f6d60db64f6f8e676b9cce8360b695101e07e815f054d499e686344eeabf36e631f9ef03a54a7b24a080e7ae748631	1	0	\\x000000010000000000800003d6417318ac882027579dd8fcddbbd676d78e48737804259a807aed462974d7383359f6833e69c4335047f7e7bf76bb9ef3aa79dff94545886fa846a8a933973d3ea27893ab497657a5d077c80f7da58b407d67dc875af1cfdadef0d62867b0ec7fd5297305a78077898b9f800c4da1914b67e6aae35ed6082e9c2bf3cf7c6e19010001	\\xe54be29a7a87f6c4aecbcaa5fec276e08f091fc7c03dff36f62a84d02a96b65e94940be348a4333f6ba464f21c42dbaf5e8c4c3404367066dc90b7c95a485308	1680336689000000	1680941489000000	1744013489000000	1838621489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x1eb6b97c1fc3dbabc08d41e07ff3bd1bda7bbf585945e767b1023a6a96e44909524b51fb28ac4b63ea667d08b40ba68e844a2c578594233d4d9be9cae96b2189	1	0	\\x000000010000000000800003a4a5749c389f862b839a3d2d06d6322ef5c758a6529a1a09d0fab75f93ca24bb317bad69bf9001094141bc879ae2642c472870bf523870358f01eec75f51b2697afc9210357d557d499e189fdf973c3fdc000850702fd3556223a947c8e15597853311bf1b753526f26e2cf77352f89e30897e0d1e41cc2377596b761f7f3cbb010001	\\xb5b7be6d34f755361e3882ae945609fca4d27d6c4d586e9e594d544c26f1677fc84927c1a78a39bf665d8e16d681117445907fb168dc86f590fef42a4199a607	1691822189000000	1692426989000000	1755498989000000	1850106989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
231	\\x1ed285a261a708146d63df9ab3d2c506bd07cf49dfd7a267def391783d1bb15074fb06281e6d9b7f7aa9a0a6f2af933e1cc220ecdf80b3b9dec89c41fadb729c	1	0	\\x000000010000000000800003cd51877b4c87d577e760a06520c3f388b5fed6b80e10befca956759a510865771c89f7a5a4615846261480dc554f4f4fcdf79eb77c64f076c7b80dfcedcd173a1f4b2f42bc65514320f9b3c3a05ff5068b262c5086ac2fce4ce76e8385ba603b52b7b68742872777875c5ee377fb62482616af462a2992bfc10677b5b7e85829010001	\\x2a58c6280b30e3ccb801bdf6fa821953b2c2ba247688d0c2e3789a5cc2dede5332f82c8bf8d14fc308d372415dba165c79293fa3f6ab20666bf120967d1ea701	1690008689000000	1690613489000000	1753685489000000	1848293489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x1fd203471eea282ef7619c9bf68c55781afc8ac50ce1d0bea753bb112ce87a4fe33dd57ea8121909d6fe4915209e8a456b3209615e56740eb81b43b9442eebea	1	0	\\x000000010000000000800003dc44ee0539a5d35369503c89eef188cbeb531325e3c7966031ab18549037c8e4922d8c0cf1ea62e2ed3d2ba380f5791b77974d8599449342d572552642e927f3ad28c74502a1f8e015d4a7c5b3da7bceaa5f86bebaa27d52891418375b939d328068f02d84027b6715e011546382a7bddc5b9fcbeda05879279cb0ef47c9646d010001	\\x806094064ebfbf0262dda7837d36ec3ff4e8b099535e7453edacf04b0cad649015e87b0f35e4eac2acd0633a8b315c2aa1441dea0781d72c27c730224d0b5906	1665828689000000	1666433489000000	1729505489000000	1824113489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x201eb4f480f9788aa1e85c37301e396b3965f770d15e24d1a92e271e46cd7b60ffd8d8d9be1c558d22fc465bbcf1dd632dea672d1bb2d9c40ef53cda603dd4a2	1	0	\\x000000010000000000800003a74c5f03c5b49ef14cceb40fe7d0b4dbd5df34c1fe04a023c81f3a056846e106cfa84389053b0d0374e98d7685aa1b6f710d943f5f138e128b6addb7d156ed120e6a27dffb0f5c53feaee5c5a3a65570c6ee3e752a1c2afdeb91659746c499537f01fff01665a76b45d18651739e79888b162a417f92e3cd28e6dd503557bd93010001	\\xba489d5ea890fcea18dea956a8376ab3315c2c52c95343a1ab78d2bfac55927d9d00dccb920fb131a3cb6d78fd1e9676dc978895631ce80a0c04b9befbcfe100	1685777189000000	1686381989000000	1749453989000000	1844061989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x26e6834dee5d6aa3ff59bbeee26c830cd395d1b1d40ab8c64d9ee9d1ee299d76b788dbceb525b3d655db009a47321ab9af67e811ba863ab82d359d1a273cbe43	1	0	\\x000000010000000000800003e516a84ea1b64fe093521f3f2027108f652f0c0c657f080201e33ab7864bcb5ee57483136b2286ab9a2ac8f079aabb267634b5218b5b3a6a61df0d5092d18989180306816b299f20a69ed301cf331b9e8ce0a8ee5e88ee56ebee700de2f79592a0212324339c0f0395045410e571778024ecbf25661bd465bbd1db3b81d832f1010001	\\x58838ec5fbfe639ac6f517cb0236acdb6c3fbef545c8c5685c224dcd61c2ee567cf94732c63645325b484af34c019f9cd4cb32a19413c5c1bae8ea21d7f97804	1668246689000000	1668851489000000	1731923489000000	1826531489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
235	\\x2aaa6914753dabf14de81f1647c3ce271870db6b968fc5474bfc1a16a3294a33fa0c05bafdfea8e4fc8745b60fc009811426f8ee4532ead096af4fc5f6616f5c	1	0	\\x000000010000000000800003a58e2219b38d877232df0c9719333cdcb58f57a2ca001a470eeb13120e17cd2b40ed5b5c8af66f017d53c8a1d3e504b932ce55b5d1ac307af7c326baf36186ee00193c78e50500612bb2b2eea0d0ac6fa5a8c87826ba10291ac37840e9241035b732572a13077c78b3f19880ce718076de2bd0aa964bea0ee5b30c33a899fbc9010001	\\x4c6dfd9cc2398adf7637de50411ffeb2bde76089e54277b09ab17137ccd2ac738e49883d895d4fcc041b4cba237bd108668691a5044b13dd1932047749927d0f	1669455689000000	1670060489000000	1733132489000000	1827740489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
236	\\x2b4e9ccc9b1c264744914e83d7e247036b4441330bf39be700f97cf3b1fee2981534e89d0145057b53ce6b064248f9f29131401a314fa03642a31f8a83c643fe	1	0	\\x000000010000000000800003dca9da7eaa0a09e69b11870523cdbe1ece1fd1eab1d681256e05821e9d67421c934dad8e9ce37a3c00d366b6541b3b1676226f65424662a8130ada26e31edf96ce0908c68cbbbb66330996b5f3f2cd80eb178dfa6034a5f6136d8574437a107c6c538672c7d044022fa62bf563016f10a49661f1eaacd7b2b8ea6559e8ef35bd010001	\\xce46b919a257780f6de6d368fd8308bd9b8cbd81bc1d562d9ab528f9a494d4c27cbcfdbe97dbad427bac804906fe80d899dddc720cd2aa7378ffaa8e942dae01	1664619689000000	1665224489000000	1728296489000000	1822904489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x2c1efb5016dcc48f4172609c26df505c3d33f59b2a8d417c17139100ca3070af1a5b6346ddee21b08e82d0c7cc86ac287e622c62a914bc3ff00bdd0d30a1f57e	1	0	\\x000000010000000000800003c0927bd710d686abe2661219bcf376a8ec43cccfe52f2088233c661b105c8162f3370091d69b3c4483443669e7ca47db7de7b7749ba6d3b47d69b4f886464e34b500c8fb85bad3ce7d832133405c364076dd969569f1c5658a716eb6fef4045b72f790a426722b08d08d25f9b5aa1ebe3b6d9b2343df4a4458bd58813c7b1da1010001	\\xa7ad616d3446f3cc386a93e7e22e79c180d6092d0f41fd638e7e78114b4b35f1595e16e9cca468fb8a8674f246af4324b6debe748a75bf2cececeb8923c96406	1671269189000000	1671873989000000	1734945989000000	1829553989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x2df2a980c3bf7b935c56fbb9fa9228667d95f50d913677590fe3cdcb33dfc2c84a3063f5ec1a0d3c31505dfe8479f8b909c31529579b40d4dbe9f75917eda87f	1	0	\\x000000010000000000800003ca7ef5d1268f4b53cccf8dc66fc42d062f183bcb82807fc014050136a5f0322d2b4eedcf6c348260e42d42c0ebd0f083b16f95c28db4a48d039cfdc7088367db8bf721110a15638a6daaf91fffcb3e7fc0149f87d871d7d3b2975950c93e3c93b3d257294f8f935a91ca262672244f983e1157da64d65ce494eabe1665b74a65010001	\\x73b4a303645e4b21deb856e602d80a41b41914d6d195e86dc4033eddd5da0880b03827909f665846c8b1679a9ed2d62b21a340e9dd0757b27b872c5af7dad00f	1667037689000000	1667642489000000	1730714489000000	1825322489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x2eaa21cd1f693f22830acd76707eef455d15903ece53c4f0e1a0cb902ddd04cdb68fdb4b8298c59effb4b94275c1a6cafd00f21733a9c9ff755712734aaf0ff7	1	0	\\x000000010000000000800003bc9f0566f959e653fce223954d1c6be842c8874908f46340d4bd3298f7e47e13fbc238cfe3a4a640c87e7677f6e0829474a767213b981fe5fd7e4f8b4f0d5abdbc00df6116ba61da61cd26006df047e96332f03659988b51bbb24f083aba39e7e834f78044740551af2896ea8da7aa3d822262be982ae7652255eee3ba30febf010001	\\xc06b9e9ef764de3f5f6f3dce2b5d3a76774d5c56e2746a160a42914665c754db8c5f5ceab08bedc8a713b582ef54948943f9a4a53d6b45362f6033a2cd433d0b	1675500689000000	1676105489000000	1739177489000000	1833785489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x31625bfb88ce48a350303d3035c81bddbe73aa9a819c8e0635ab1583590f8c9cb2547cae11e1fedec451271541e9fc63a49d2c4fd88c028375c5253c6f021e8d	1	0	\\x000000010000000000800003c7d2a852f9c263974734fe4cbd5a8d335095f70f679e30ac861bf58c8aac6a313afa0ee6e5c80c98f8dce9fcce65d699cef14c5ead5fa6215d6ad2efc169c1386cdc140aee2f281c1625a49468fff38782a614d10a08f593dfd943cc086dfb7446fbdf70aac707e6d26286a14e87989b7664d5ab626354c7e557a44002a7e957010001	\\xe6d992c4d532485422658950a6d1f04e845fb5e1d5141e804242ca853928f28b3758249f4f4aaed26588d2ebda85465f08607f0d3ddde197949b5b1f68fdba0f	1667037689000000	1667642489000000	1730714489000000	1825322489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x3276ac0dd6754548a94ad3f3bdf7020550647d658eb13ef15425232e863983ed6b21c49f16ee85758be74b4db381f44a521b8567322e05fcf29e068cb3fe51a0	1	0	\\x000000010000000000800003c6f7ca0bb088d02488936e97c65b623326c766f60f4722f870055a0fd5ee4e0858050821586996cbfe8ac2914fd41ebd5ce5d9b80830916ac253b10d3d3c761bd81c247374f5f247e75bd74a1d37e8fe3813b10d9aaf6ed756bb61eca0a9a443e5edc2b928f149f2480fe7e2710472485ea73fc44d97a303ed7f913fa0c0031d010001	\\x85b2296b0649275eed6e52b6813073b2d173d8ab9e7a301cbadd38f2e70938dcbce54f84d14199edddb4e6add5ad8da73289a47e0203395424f875046c80ac0a	1691822189000000	1692426989000000	1755498989000000	1850106989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x3452e5b0e7a8ccd1abc017dbba5ed2f6fb8f9392791cf3e4dca24ea08b2b3ee7ed1fcf4190e689013455d6be2a41cf300b0e6e8b07790c246e17ea7821dfe199	1	0	\\x000000010000000000800003e29acd207d6ce196cd738a2f4a96278a04475810954d3f07206b4bc3c0a31ebb0783b73700035b80476654d81285acbf84c7965f5f97ac185165bd83b9c9ecf0f9406bbbfea4fe0d5d3e7cd27a361172f4e0c43f3590eb64d94ecc34e9e4b797dc5bd8b517be7744cda40eee8ff4f20e738f7ec639a8abeca453c99629c29d77010001	\\x94198e6355d7edb193926fd3710a24c41bc983704a3ae8dce016ad545fa513710a07dc00053d81f85e311873f6a89a415f605c1393cabebe822689e5bc786f01	1667642189000000	1668246989000000	1731318989000000	1825926989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
243	\\x3826fb5868a03adb0d54d05c20d7936eff790c92738989e14da46497e4536488c3a4d23feba1b5ed67472ce55d56b78d7f9785334151c47060f7fcf783c156c9	1	0	\\x000000010000000000800003bf94045c40faf3f1383468c4f8659368e7996677f4613e9211948a11e191e6a3baf6fdffb3b4ed1bbd7d34fe8dc1563688588bfae04b5449544eff3f35c2d820fcd38a8fc129c2864b982e7e5a4401c7b41170f1a4bfb4c7155e69197fcdecafcec4b3b8826870288f53ea421889d11f565fb6e7511288811f70432691a59de5010001	\\x1b6b0e57b72951ef7862a5b545b8981bff721b68c54eeb2db6430bbda60d3e0de1a39c28530224a65962365f183e4b232e2a6bcf63823041c91390dfb988020e	1673082689000000	1673687489000000	1736759489000000	1831367489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
244	\\x38ca57b3f8106a332cd15a17baa3ce49d006a2894b7a74bd173acbc3ec06962726385b0752f12ff1ab5cfa5d4182c8e9cd17960f3d45937729d4ca5343dd57a1	1	0	\\x000000010000000000800003b3a38536928f29584875f5ab76a4ab2e4ab135516b53e5491b7531a83069d485203266077d8219f089268391420d23d84b641483b773867491bc0f0b6be197948d56f172576d412e6f20f122c683ddbe61604e12988062f423c2b3bdb8303a68e461a938707c2dbaabd9148016944ec46987c8be038ba619c5ffd9960c24a0eb010001	\\xf20a5ff9317aa6f86da8f5dfa45b3123fee62801b36e933f729b935f081956b98460e32379b6243247bef29c9706449a542f680c818f850495c7443c8611fb09	1677314189000000	1677918989000000	1740990989000000	1835598989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
245	\\x3d9ef38969f9b972a6e474fe83bc4aca4c37e5e91a0c140653d4895671d0ac5a75fbdf41d66b07a8935350c9bfaac582904e9d8b32048f8fd5654925782682d9	1	0	\\x000000010000000000800003bf93cc4dd92f30348afdd5cc24e6008502116ca0aa960695ab94d7d3c47c3108b133028b0c14e89d1b63c45be676a787c3296ebf9309013ee0bde2e1a587d3aaea21dfd7a9f7844168bda5fcd9ac4cac2e8f146e2eb59f70387fc36830d7b6d6751fa98507ddfc33f02d2e401eaf19e3318dca1579485fa295a14898a6ecbd9d010001	\\x71ad4f52f4e4399fefd421ab38245f200e77a8ef06d257fa3d3e9237bbe67b22a0cbc1d2a4e583fee922725e271a701531ceae6518da445f3a866d1318c8720a	1689404189000000	1690008989000000	1753080989000000	1847688989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x3d466830b6d0123d7cf10af22443ceb7e0c1456b706745bd5ab72ff675bf1859466d3facd84b5d14f5c4066b3c1f490beb168697f9b45c537d2928ff5b41ee84	1	0	\\x000000010000000000800003d091cbba4e0d0021018d77d7227b3d9d2b2f3ffc6e3cd747b2642dec0cf760a2d72fec060dc12342a837a6779d47f3b4cd0b9c4ad18e4389c93e0a40c359ea8c298c45a6001a9457f278a817610b5ee5b4b433998ef66bd6e13e68c7df24c8b598839cc409cf5569c767e42daec0abdb3b0e93999e887791c6fa5f6cdbc2c9a1010001	\\x66f3034c4e0d5891aa941f298cd64cee7d6c28da01c70021f1b898238d9efdae677f5babfbf0421a2b53ed8f3a8675696bc67f5a427d268fc7a30014878ae20d	1673687189000000	1674291989000000	1737363989000000	1831971989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
247	\\x3f2e981f5a1bb9e6bb8ed93b44a84b58bb6dac6e209a97ec27402373060a9c51f7f3fb0563b03eb498dc8eeba4b242ddb9e4a0f132e516aa838c581bb1ac0ccb	1	0	\\x0000000100000000008000039920bd610d48944af8f3c39d8091331f89abd525a8ed0ce53f770093fb213c73c408964355ea2715c2068afbe99e6061a34b561ad04b100e40072139c0049caf9fcf56a35f140fd368046aab06619d86688b21b6c86b6e90af4aab4b796fe513f9b34a35c7a935c182f2dd05f44deea44c8a1ccb134119f503190c0143d9d2c7010001	\\x98710a2a9f74c0f3935f63fa9cbed0a15f593ad1f1b6ade774a196f2b616a0ff07e0e9af74db6ececc6455a6eb95809548ea05013121fc8b322baf327dda0e0b	1670060189000000	1670664989000000	1733736989000000	1828344989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
248	\\x42ae035b3bfe9113a26c4328fce06403d8abae27c3c2e2bf63038927136b7d804a8b4cc7c972428c3281ae2f709f13fe98b3ae11a4fd5c7df079a70259aa3022	1	0	\\x000000010000000000800003c399b31dc5626818489b086339e9ec7a65b981296646f356ae9aab5439c073733de1cfbdc6329f6a9a3537794066de1000b63ea6b7422f68a31ccf6e786414f3283c8260e139421264a16096b8dd346ffc0128517287cca40b250c33ead276f644ef631df2dfe77eab0154d38bc207b0b8fa757ebd1529d0cc8543ec24b912cb010001	\\x78a20203aaa448595e51878d33712c6811c659a962b39e5130adfc71dee1302b589b8cd1a06f16563d0c73a032524f5b54f9c2b65bdabe746d83e19419657107	1661597189000000	1662201989000000	1725273989000000	1819881989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
249	\\x430ae5fce7b1b773fc809ea1b4b24a924159e5267df300b0a1f3915545cb73fdb3bb988688c660a9318b57d457514534c728b91872e590b02e1561d13e4fed60	1	0	\\x000000010000000000800003bdfd0f4f00de2292016bd3fde95bc59c93ced9bcdc140d9b20f3d2a2f94e762029cf093d3115e486e1b3c4ea79aab21d3c0b4bb2ab27e909a075f188de0dd8b7a2f42f6554e3e9749637f6e682c5c0e56f27c84c64e225d75b04dfd48e39ca10876cc1ce2ee4660361c0462ae73346391320038283a88172760b76deb3d5e59f010001	\\x84c01b84d39020c705b3afd9bdcc5ba35292984c8df97504bb1aec079e0e361c86b2fdf358f8f90fcfd2d9bd176ea47737e0965e0af99d5aad051030884bac09	1668246689000000	1668851489000000	1731923489000000	1826531489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x44fe9dcda061d903091e9ca42687ebbc6d68b186bec7ca35d05515da0c59bc2a3bda19053f3b18dd591156ba2900c97c23437d9c12b37e54fe573be6d2166088	1	0	\\x000000010000000000800003a7c607e0ac93130ac8bcc6e3f69dde5d23f469bb4ee2855e55a92953c29fd8b964b3f993224a78f91552f06d504018f397118c888a6a4b0af2ef5bb0abba3ceb0c162996b8e98e13ec35e50fa2eb051b5b2b73469aedcd1f43bff104d2eedeb1bdcbdd10eac3d192025a1028d27c940cef51eadf969265d553b42bdce41f34b9010001	\\xe956bf103f8e16c1f7ebc31243be1230eff896f01fd50727eb27bcbed026da48ab6e54fccf235b8ce910b15e2d41cd09f3ea2ee5d8420a981398a8baab5d2601	1670060189000000	1670664989000000	1733736989000000	1828344989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x447a0c4f84d99d8427446cfc61b3b3242b9a3263bb62d095f831ec67b641bf7257ee1197ebe7ea805b59f92f2eaecbcc411d08e4984778c0c33139d61b5b3998	1	0	\\x000000010000000000800003c3b7d0b2d925900261d4c85f86577c53dde85ff63c4c723372ca7d1a89323e1fd54abf08f8591e2dbb0ac4caa613af0a3de976fa4882e4afc41bc02c678cc47d8518627a93a670e8b71467f7222a75213d9e3bbafe098d5ae78de98ef11f6935b3cef05bc4235d2c2b966b7aca18f0df9ee72b3be80a0578a8afafb22ddc8125010001	\\xe9d1589c27f0a8504f40ce5d49413e2136f04a92f4309d2a3bb1e155c3cc581e23683705ebcdaa09ee00fe8587fbc391551f064a3283b754ea8641f3e0bd4e0c	1676105189000000	1676709989000000	1739781989000000	1834389989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
252	\\x45c2ed803cad18c314093649a642a7445dd75b666f9fee3b0e66a62adfaa8a5b7c912c7c41d565d0eeba530117c93440f8e68cebd9982346896f3ee32533d626	1	0	\\x000000010000000000800003a46cccfccab99b75fad38a403e76abce5488c402f6ac2af77ad44b86543aba34fb43910816c501d49db1c944c478d818db363385250b5ca4e2c5d2fcfa0a424d70d9e2b026e5c90bebfce8a853d970ca2d48e8af5e2dd0542e7286de4aac1fcfd4b48189a90c74fe1bcc2e49efde2c994613ae13d10cdb2b58b03cdf49f8adc7010001	\\xc2b48b1cfbd7c355386d4591039d10e024f09d6955bad4e32a52f528dccbe1d90eda78c2c6ff8d4b27e5627ce3488e0a394348aea5287ca05d66cc30503a6708	1676709689000000	1677314489000000	1740386489000000	1834994489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x488a9f58f2697035e36c20c4d4bb5b380d6cb21139f2dbc622e463f19afd8120356a54ed9e016b9683583dc8b3bcab229fd08d826d2e551fb89c62bd77bbf40e	1	0	\\x000000010000000000800003d224d6df98ee216a9a7a0d2446844cf49a063ff64f53d404f009d6eeafb376684b66eedb603b4b07f07a0c38b8e11bf7421bc1c6281aefc3e85e9993aeb8d0c1f941a601d425b982e8bb7e6f7bbcb1201373eccca6d9f4355f6a39559f0c9ac17eb420a5bc5d8229634570f9a494b4fd396cd2e587068b9df6a62c054a04ba31010001	\\x20b632e83cc815568e8c14c0ab621011cc8471c5382fd35f09d23ccbc9a034f6b19f364126c7cf0d716060e91c3971e2168efaf5ff3c1476293b6c73f9630803	1663410689000000	1664015489000000	1727087489000000	1821695489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x48928b953a44b75c816faf7e60fa2535de135b08d9e5f028bc7f9f4c6b1e2543498f30c53bae12db6724cd052b9e2ef66e9b8213ea25b1221e4b849ac83ee6ec	1	0	\\x000000010000000000800003b9529f491c37b8a7f07d2f3d3e0d00f7c5a650351c9a6437396bb5e306079ab016ab211a5543c31cc00faa8409e45893b0fe1825a92bde90a3857c6340b1221f8ca11086ddd740a3126944e6312455af86c74a44de018ec52ee384932c5444edb6b958c4f06e2eff428f0f0502c3511bc65c75cd90477228a6479c8b8fb48291010001	\\x804ea8ecaee9d7366014e68b58f125ca76db7c4eb97bd1464ddeb2e7cc318fc62767888dbd4d75f91a9ec654e741467ec9d3152107548c134475e9a32717090d	1686381689000000	1686986489000000	1750058489000000	1844666489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
255	\\x498e3ae6f49053b653eb3c78cbfe8160771b22725bdeb7374ba919be605ca4978e1478b84bf29c3829c77ca9c71fb16761c8935aef14f78a792746b7f2fe9cd3	1	0	\\x000000010000000000800003bf044677f292896d481d4b37c85ce035d4eb1ebdfa33935c37aded60a3c4f2b30cac78c8ac8230e2c13dac8087502e6552ccdf3e65a718c6c66d13df1159b8650e61ebc360b2992163d9bff031f114332cf5dd6fc5f9ad2d87f5bd831361ef5bc3e8ec306c212a5db1664e9b2d0b7b7d4961e1d6fd5c6b8432ffb44d3bce6deb010001	\\x1bacb7ed64c06a5a815f95910dfc115bf30e969828ced1e6ffe139e7203273202d93e0e709d049817c02f0a29e66310e1e71eb1b891ad3492a36e0ae39548d00	1676709689000000	1677314489000000	1740386489000000	1834994489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x52b272067d149ddb41d1bb8a624edd6bdb9fa0cbc3dd3bf030c55ddebef1e4bcfe0bb91923f9dd7c9daa4bc4dd19eb9e5db46ec31b293718e4d4b12d261a4f98	1	0	\\x000000010000000000800003c72ffe81b4e0d843fe7374658782035bfb5417d384baba79b3d9811558da0e3f45652623bc0120dae20aa7853590932caaab7e1ba700a70046673877cb0abd4a9b637a63b36442b00e725a40d637b7cae46a4e8cfe6d23049b2d80b355a1fd80ed143e423315733e8e941454db21ef92e3f9a34099918c49dd2bf8d670f0b791010001	\\xbfa26e2d2849b4a9e1c59b4f8df1aa49277aac2b8ee2b8a08211cf55e4cc95d22ec2c99cc2c48bd114242fe6cf29073fdb5050f905f4a639acbbd6d08b36ca07	1673082689000000	1673687489000000	1736759489000000	1831367489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x54968c75e15c82aa27d77e6c6bb1d448cda015ffa203fe8506c2d715c325d4b65aed6d8f250592c0add96d8168d710daab8aa33b7ccd811d623de43438fa40fe	1	0	\\x000000010000000000800003c16a4fd0f730ce54c83b052725a047289330f17a08c57c55158c6321b067c3ab01344fc9cf55438163a72f1c9a6c131456cd22bb64dcd75bc35f18ade153d93e1d1b9ab30a4d0337fc4e17113818bea439e3de89519d148913f180f4e73e1cbec3930af923d3a841898f1131898d9ff50ef970aee9c12f08071736f70d78d2b5010001	\\x97acee2197c3529bfb6271b184aec835dd79fe7d6ed07a5eb46f7f925ffe26b9cd40663f2a6e8d636421d7da5e14626c31b930fb01afc2e088c535813216cf0a	1661597189000000	1662201989000000	1725273989000000	1819881989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x55f6d6abfac1be90958366fbffc5f6d9cd86694ca1561cfe1469dc420e6dd15b951c67dc8ec3e3f074c302a9793d5390c2cfe0d5b7af719bb72019838b3941df	1	0	\\x000000010000000000800003c52e49cb7271e65b2dffc4233aa65d91c0794c7f932753eead7392f1290d3bd4eaee9bcb11e8eae1ffa787e83fe47bdd4bdcd08ee34ab9ef115cd99070882c8e8e48dc8ce78d2c05d8e42cdeaaef24e836f35f3b0f8f4c5b61e7ad39d4569cfedbb7ef02257d0340b997f6fb48116d917dcffec9c4223c166981974992dde2ed010001	\\x197259cc1a4c8970fd89e228a7969281ae16a181503fda7b951e6bdc08e19581b91f4f1fce50c7073adde981ecfe03b75b25a933614846e44d7719d9c51dc10b	1690008689000000	1690613489000000	1753685489000000	1848293489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x555e6224ff0453bd4fea43bab11c9f7e25d18086abb49c8269806849e8c592bf1fa907f509f7372a71ad4d8221a0988b3bdf4f9bddb8e8f0318a2b61c5628b6d	1	0	\\x000000010000000000800003acec4d236614c024c6c5f9dc1551f9003901f9fb10b6a9d0309b85ae08a1a72ad41f428945d1e1ef5dfbc155f4b78bf5debac5770d0ac8613cefeab96207d7c13be98aa1e616a8cc392c5e69bb5b2a38552e393855b3e9fffafc512bb83bf5ba1c35d0744bf00bbea46151a3344204159d43ca2c4e80851785c5c561afa8c059010001	\\x7833b96dff8ac22e2f50746623334eb284f1ebcc78f9e153c7f44501c48d2c39762d8ec4f58c581785589399a9a3a2c329b3509d37fb4dbddc1d0b9780636f0e	1665828689000000	1666433489000000	1729505489000000	1824113489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x5cb23b52d47a54c9f7e2595346d2e62fbbc6e8e0d97af4c0e4e3562afd4b835311c906e1137d859f11ecf07ab177393277853aa53e80ff41fba076588e2938df	1	0	\\x000000010000000000800003a8c4845a7277e85e059edc672738f7b19289cb30ca9f4922b19b5092bc453bdcaefa70f0ab897467945f51793dfeaebf98b8c0520fc4bd3f4d363ebb82f33a773f749c11fbfa049d49102317c430f779b856c7a8a1898c6ee034342cf51fd740fb86ed056cdab016ff0fb544dd8d5755a1792668e01f5ad12e9f04e0294a2f19010001	\\x4166aaa6a775a9333d07076091493c6df3eb594e4cd94520cbad2e1e8688f62f4c45f66b43ebffcde0abb18bcb8ec825afd61b3d2eb69ccdf5339d562cd1780a	1691217689000000	1691822489000000	1754894489000000	1849502489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
261	\\x5d0edbe391be3d5b3642f73dd8c8f56963fcc153172755aa8d7b806cb868aca8b836a65cb33325c59c3278ed80854522881baf72ee7ae644217a9216cd36795f	1	0	\\x000000010000000000800003db0923203a66b0a48118c48ef67e0a902ec92305d9bc4a9ccd582396e68a192209c3672760d1a466f64087ba00e7897414ba66719d75b71b30e38dc873ab3e8dfd9d484e4972aa647084b86d01876edbba00d31a9edf8b46c47010a082beff700e5962127e1c657e6f01254478fd681260f3a6ca4d9dcccc100715e6f419d485010001	\\xc370aecb1cac71208908a646f5a575b270819bea67d40edca3d05cdf8c8fec4b78dc51b261e17ce9b23463be28e69e7511edb11b9cde2fe28fcec70f9ccff70d	1665224189000000	1665828989000000	1728900989000000	1823508989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x60164f4c17c8f4430534476dcafc4bd19a5a6d625c43245afbcc27ecf17abef713733cdbc53a6193c8300fc45395a8563d9106474e5cd8bc1160585a0711317d	1	0	\\x000000010000000000800003b502e679aa0557fe64903424adb6fe50540341b4bc4a45e7591f5747efae6bc69f3d39a4b8b438d3f724cafe16681d6ecf81f646864049b33bc83b68812eaf53ba8d3817982c64595e460870f38e19b7c5c2d049718db8a2d8152c51554d37724126186824256a1ac68282754f66780237b8709330a9e22c2fdca3107ee44f8f010001	\\x817c5f316a29c3cc5b0ff58eca3af070e6043323ea5ec1bb29a41b255e70f0a6ae2a7bd6238eb5c17886602ea3bffe7937136114b819293f27af6ad150d48807	1672478189000000	1673082989000000	1736154989000000	1830762989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x639e58702ae829bd2ffe46371d05c1540eab9842560fbe277800cb7d36eb998eb19fd538e6e8ab7da85814af24f53e7e2ed47cf994bee7feb0c282b7a710473f	1	0	\\x000000010000000000800003b70633323f82791b893c21f94b4ffd27d823808531ce2232609aaa917cfad717992f539c2bea1e5a0cb1aee29362467f5a6d4cb3c03acfdc158a57bb4776cc02bb400d40de3b3330fac0d46f89077342f01960d1dc1c6529395f5fe2ca701f1f4e6bef0ac27eda4087106cd0da933cbd4b37e0ebb6f0b2eb243e9edbd57e312d010001	\\xddba08aa55eba65cbaadec6b7b6d79df88e7353c623ce0fa71826aba5dca7e5d2de10259bd2a798ef9cf7c2da8993cf7e730d53e18c3e1dd595855ae8a34970c	1662806189000000	1663410989000000	1726482989000000	1821090989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
264	\\x695246c0d9603afc06c882e48d366380d1c41a99ffdf02fe062431a2e5318b4e073aa2a7bd248930ee39c8f1b435a3a2b969aed2f409e378912b86193da1b538	1	0	\\x000000010000000000800003cb878e1255306eb9bcf63ed1c7b0ae86ee6e73a8085bf3ffd69810fbd75630fac597c90a24831cf2cddb301638ec7f36cf82ec8736d05cdfee87ce756449beac2fddfde0bf7df73f98fc2820b58e93f98edd88219cc39f49ff768daf7b5fb436f0d8b53777d84e2266e5df8774c282f3ecd7c227fd1d533675aa8ade5a722bd5010001	\\xf84bc7ccbe94dc7a8188336cafa034c76a1aeb5bde720308d60194c5bcc03e9fd09337f5e7e1217a68fde095cd2f54d4dd93d0cdddcc2f40a77cc2fcb07a7502	1681545689000000	1682150489000000	1745222489000000	1839830489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x6d5a08856c037764521f6613371a0b4499e7e5cd594439c1d91193559d1217b49e24f6238caeca79b6cdd971b1d22aaa8366f87de8cf815231060914b44c0714	1	0	\\x000000010000000000800003cb2754f0dbbace1a3499ed33e66c468e73478a1581d1b57480e27dff747b6da1fb6e8c4ec95cd830aa8f8a2e89c68321f4008e31c852b0d3ca70637fbb432fe1d98ca14c48769ddce7418ebb02c0a9d7760cbccd1d98b7ee5c5ef8a1615225e9309d445c1c466f0884977f9da573fe2bb5607c55fa7d72add3fa23477558a673010001	\\x0386f69592647e502ee82d4cf0b11aa160520cc72461dacadc8eb163b53c6273aaf5fbadcdd5846a335a6f0f9b56757c7870d1bec11cf74ff67474d294f3fd03	1674291689000000	1674896489000000	1737968489000000	1832576489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x6e2646f5a2f5b39e3203eac274e423b0bdf532ee212932d49cf88cd4c942b52abb75886f7d162a87d5d786177a89a76ebf8e5141ac7b33c9dd128eecd1fd0896	1	0	\\x000000010000000000800003ca446b605083ca55eacf2e782969fcb43b93a63caa7d52d5071e38217f4e45501c2fd00fd4fc62939e94b17a30406db6f5aadcf7c73591df50c43074a27250b240c7940211234ad4444b9c5d2ddab4506023f79124bb9915a7feb8dae0b334918140ecbb9aa868e99929066a8177d049f6c6c24c25e4d5ba656dc52d954c05a1010001	\\x3031951908128fb1a264d6cdc37f1f04e9f7c452d656ef0f6e42934d3690e4250edd82e30a6a55b76c4d05e2171f7fef5b8695b611ffcb3310664e3a92e08409	1662201689000000	1662806489000000	1725878489000000	1820486489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
267	\\x701247a3ca891769cfe98c781893f19c8db30b63ab16272fda3bf9bd92af8b0dee8d463c7e1c8c5ec019af192afb892822a09bf0b3e97431d486579f49f64b8d	1	0	\\x000000010000000000800003cf9be233225f2ccc946c08383def223397cbd6c94ada51f1faf4bd91ee5247d1a19e33ee4dd064ab13fb3c88ebae8def17da6a5c0bc58f3f85de22c94513a4824d3ffa410273f4ca755922be37161d3c99f4548ff44545e72d85b899c8f06910d88dbcc2455ef6bd1ac4885b32c07fe4777ee73e70c0973da8df7b103439099b010001	\\xbbb698f687107eb66efeb012e1e33973d66613447833c532c608ee2ae11f859101ed298852d5f7e3a43e304af5a5aff21e9dc664cf5898cbe152be903e2f9403	1673687189000000	1674291989000000	1737363989000000	1831971989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x718a1b90e13325e0993e1552f3e24aa332f7fc27ecd9d9ea15d180bba58655745712b465f38d7f23c4a2121cfcdbc9b978aa7a917359138fe0224a6c343295ee	1	0	\\x000000010000000000800003ab57989b26f1dac50c3ff85964012107bad3db99bc1e12300c5751b1606332db4dbc3e29ff2af8cd0a8e7cbf2a67cdb9029c74996cc2e3b101754e6c6741c443735bc01fc278c61cb07f599e34b13be59632bd55138e373de8b39ecb62e377b5ea0b0dda93ffcd035ee73bc4a71dc1ef7212286142e5188971b52d1f577377af010001	\\x1bdd0eb8a8b1feb9e48eec7e694dc4aac155a3b4c26189be1d5ca3c47bfeeb4b5f72ca32722cc7a1d076d9e82d966815429ee012810e3cf5f34d187ca509590d	1691822189000000	1692426989000000	1755498989000000	1850106989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x72f68f57fff519fa9c06b6fb29402fd8a82434cdcbb5b16cb9878329c07c12551b33445546a39b30b0ff722a8b565b0ec399b68fc69324cce75a252746823ad7	1	0	\\x000000010000000000800003a4246064a5d6d2da2bc196d956ea878f22ba7190d1f35a86e3e083899076ffb36b55155c692a71fb071c56e2bd7d2d0fd3cb278e8915e1e12be4f778d12c1582b455d1cf70203766cb473f59469fef19a8a8b70a6be6b778ddcbff2c75a7b1b2f218dfa707b59d97ebc325079a898e7f8870d2c16291135abd2476468a638fd1010001	\\x4004e8f46a46af4521d214df9b6b7ef734c689c10e06a2b90ef1de86ff98e6de0476ad3429c37be838a32956ecfc64f8228109caac7c8a48ca2f41862cab2f09	1662201689000000	1662806489000000	1725878489000000	1820486489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x754ae4cd848f3d2e59cf4e0ee3533eeb62367712bad79b633cb20aa2883192db9787039decffe38574bb5d1b9ca0f68b4a80f7249b0098d3af19f27c0c6094b0	1	0	\\x000000010000000000800003c1d9ab4004bc2cbc4b441188b24111e20a0df752b8572a7c8443c851613ed6e3ea598fe9212744b0812fc6d49a7776e5cab680990bb9c686c84feb7ffea2f1193b9278e2fa3b040563f734a810062d0315552364d536517c179ecdf20d5f3958b6f97390c4406c664210d72316bf930147dc5748697bdeee76a7906608f39bbb010001	\\x3966e0c8986541f64aeaa2424b19ed4d578bf288b9ac7ad77ff84b955903a5676e146eb078b092c1e084369650cb7d0d78dd5a977f4ae902f68efe112d4d1e0e	1679127689000000	1679732489000000	1742804489000000	1837412489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x76f2ad4179ea41b626933c8450ea0a82608b738574050100dddcf485f9108898747c03308dcb10e54875a4b3437bbb7d261a8bcd7f5c48a59daebc8c1579d93a	1	0	\\x000000010000000000800003f406928996c9d9adae832a38b27e41ecad9fcd4d1c43da46e550a1c44bdf2a3653b97adbd48b28b074240363397681157a8ce899187a8d28868ec1819cef74e1789afbe27bdc8e0d2b1692b1ed4bd8e32458b594fe64f7167fd12ea09b457d0d775dbe7681764252e690b83da71a14998d88a92907553fb3e290d59c767740b3010001	\\xe3cb2b6d6b93999fa308366a0788437f0002054049ccbbd91780e40782315b86f1c0e499cbaa767d9f14270aca172c7a6c489450cef6d2755e2cc16bfe58e40e	1673082689000000	1673687489000000	1736759489000000	1831367489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x787ec57ce179b3a720aa55ee1924e1c82221f3d7e88c6e200ab7db9302130abf480fc989e4c02c93486436088b8c908ba76e31e7f9f49eacea7971932ba81bf2	1	0	\\x000000010000000000800003c8304519e88331e907aa5aa856703b73a23631c5431fbc804a3992cb2fe45e5354e94dd212ad132a56b4c53d59be4b800dd0e9681c57be0efab3854b16045d7540a5fcef3d5c707ec2e96db01d3635fdd0172f6d27ec1b242448f2027c9f4832e586023a4a2dd306f8d83cf494dc9a00dee8a82286c839522ae9f6bfd8148b29010001	\\x77f21752f2cda961a2d80f34482edaa2ec11eb1a88d6838b0b9198990d130c40d2e1692272a40ebf54ec8aa402273191d82a2f0c7135de250993cc1dbd58b904	1692426689000000	1693031489000000	1756103489000000	1850711489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\x78bad66ea1efde2f893590143dcb816ee4e140d6b4630fcff3e78720f2bc518460063774e7eb352c79d5c996a05c85e5f444c3263a886b8241fd9d9874e28a71	1	0	\\x000000010000000000800003bdf06cb7e2e5d4294a22c2ca29e8de39b510e780b35a4271b568717347c6770cb495ebee04ff5de6e5057670c368697daac77722cd38a5b0a281d3bef72cddfecc0a9afa020fce70a0e536ece4f52fd740d5263daa383e42d1f841ba03718537668db62c3f8c61de15f2ac372e1bccc15bc16f4e9a11ae0ddc5473fc7d1555a5010001	\\xec8c0e3399aedefbae2e139fd17b53b10e6c0e5883dcd138b2277a6bf7626c05072a2b6d4bc32d2a6fb1aa16fe05776ad8748ce9b25bf5d98a443964bb470801	1673687189000000	1674291989000000	1737363989000000	1831971989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x798a172312f03a35faa7af4477d87571d7cca68f1ca9ceb08a45e3722d3cb78ef08cfd04b5afa7b0c00701fc2917f3b2fabdbab52b50255d55fcdf7352a4b914	1	0	\\x000000010000000000800003d33c744acb838266deffda22c34d2b427f1725ece872f6c8845bf2ea7a831194001cec9d1a79f05f7fbb9c0ad3fa1f33dcb6734d1cca0c9d52bb8bb134ce663fcf91dc791a0b6aeed9485e8b443839e1c99f257c11f6434ad3ed56a75bcf6fc67b694ef5b8487e5114a5f29b610903dbd15accaf23d978d6cbb8979c707473f5010001	\\x66ce6da974193cce68e6cccd3dc4c3907a1b349387e2e76d3864f3221a8ab5dee00cea2361583bf6fac170bc3743c7e5ae4cb5eacc01cb2a98b7aa6578239a0b	1679127689000000	1679732489000000	1742804489000000	1837412489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x7cfa0ee4111c6e7b2ffb30c5d6dbad19f46e61071518242fac535ccd668c0329d3ae1df9aeaac60c97385dc8b4064de9cfbd8e01fc03ee2efbdb524b3e1c5698	1	0	\\x000000010000000000800003de26931dc9bc79c4f27a49064d84506979e1d1c82f7c5ea9fc814423da37a6ae61348b1f3d675ec8b96c6c7bcc2e4a917c284e6e924cc98ae63b747e1652abaf396752d87ce2196fd7f2875e03f35a00e88d054756651328afd53cdd359e7000074eb47e7cfc7f53efdfdec1c9941202de3fb01d8d82109c0122e3dc4f03892d010001	\\xd9ba0b2014f56d510af8a86991154054091886f02d156db67a1f63af7d22f358ef877513b59c371db0ac7ceedafde796cad936c357eb4bc0b66037257d24dd04	1690613189000000	1691217989000000	1754289989000000	1848897989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x7dbe9e03fc0a006c2155d5f73f54f7e74f8372c5a4f74baaddd34220bf710b8e2a13b09b8b85b336ae18afb7c4f08d3c72e8b4b6d1ff2e3c4fd0567117430c40	1	0	\\x000000010000000000800003c1c02ec7ccf2262ae05110b88b4baafe2903602a5c8c8c5f601519051278edae31beb05e4fc22bc8e38015a9ab7f808377bb7413bdde55b81bfc0b4c389674ac1bf4522e3c430aeaa3270dd297fded65fa2fa86514eb31ba958adf32fe2b1909d89f45142af8cd48a33ad97da502c8f5b01be5cae0e449b3e3f0255c41762021010001	\\xafc660c914e11ca00050e2ccbee1ee75774c79d36fca5f77adcdb9f1758873e692c550223567d92f546e5aa07fa20b4032b04525142c043b3e894b3a23c52c0a	1662201689000000	1662806489000000	1725878489000000	1820486489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x7eea160f96c523af637848b40bd1d31083ba7ce9f3066c722f426c8576fd3db9bfa8cc887a244443c676902aa45f6dd7bfbf8772392335d58645a88e6b8633ec	1	0	\\x000000010000000000800003a71d01af23a655f8b60322a0ecaff33af042d4d2a0bae73c9f22bc972b0e03ac1b9250d3d77a57a3a7fd8992f634cb4859f12291fd7c49abc3464ef49ac37c62c3f6866c069d57c9426da87f5c4c4df6d49ca335bcf09c4072d1e96368f59c162ee3597ac21b520913965b88736ae222ccd19463c2431aa3fb0557a35d90d9b5010001	\\x841321208f33be802de5b04aaf62d3e497109ab50b9d1c6ce5b4bc24d65f53a45ee731f2fa28ecbe09b56804a3df4764c2a560a6387a376f75557162dab17e0d	1665224189000000	1665828989000000	1728900989000000	1823508989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\x852a505494a023d7924756651db8254c740c53ef786113b30c093aa971f70c8986c76cf39d98d873526e06d347b55dc77d8f0b856fe8d52528af9c4d6a5ac33a	1	0	\\x000000010000000000800003e7c6b32803ad9fd3c22321fd227710ed20562c531ed9220ff047945e4d6269e54c52c1c3a15eebf71cf5eccdd160aef135171c177608ef1034af04b5e48f8d01043852a7844faf36e09eef6d2df403b3b8fa8d0baf1606db40035ae6c95b5c96aa3967b8ad2dbbec84a1459fe742bfdfb7c5aae614e59236d21014504ac314d7010001	\\xbb9336c52aa52ea5300749c19162878b2975e998bbe83dffc6bef2bc518753a0e84e92b206df3752374ff55285c44092933148b143c5a409d3d15063819fdf06	1685172689000000	1685777489000000	1748849489000000	1843457489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\x8c561ca2d5d76338341ce98f2e78ca450071bd932c4ad526dc35557c26e728240e47b459dc61b710bb104bf3e0fe2dd68ad473d4a9bbc0a4f0c2c5398ef33f57	1	0	\\x000000010000000000800003bc71833feea55ac1d88c94456b223cd1f6ad88218dada7923d5ca82093bb5702ca063b25db33167e6e9f0f73999679f6cd4d69cad8b8d8406362743dc68bd8fc700c5abf085b2e94788d89093b5565a07217d9a065ac1869339df415b8c1a9ea9d07cb7bb4da3f1901fde6fab4a8bb0d82f373bf3323098aacef894b5fd43f4d010001	\\x563638a95fc258ee230f53b38896ee849814214a21f642da8e59655ec4679cb406a3f54c5ebffeb8ca1a2ec48dc877d20526e5a8af6145e53eea95fee7fade02	1682754689000000	1683359489000000	1746431489000000	1841039489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x8d7a494c75cb447a3452ece5e96fdcb524a75ef5ee2edb55c4b1f7ddacda353e4e85632f74c55e75bcc8311b99e44eb9dd3362df3fe34b5e3ef661c614cb4667	1	0	\\x000000010000000000800003d38d53eee22c0a2c1f6ddc7a2301bb6954dd21a8d0a94cdf610d0a22ff8dba302bcdec9d70d41f74440b045c187f1ae6055f9afc42bb096cf8a7a6b7d2692fc0310d3894ce8119bc9130de98c55b3cd77edbcb4c8ebee1af95fc1152cc7e8e6d45506ad80cc4f28a8bbf8586d51e6b1196626e77c306b22a3b3e83733af47235010001	\\x05818d1da0fa2198a1d1a2458aa592f865168db750053b12722a17ec891314627f9965152cc979cd8ea46e582788ed9a7833407346a324cc530a5bd292ffa40e	1671269189000000	1671873989000000	1734945989000000	1829553989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x8ed6d262c73c272d0c50f0d05fc4e7d4f46476358b5580df203c40548ed22012115dbd4ed2721c72d94d1e8275a8b09f812328dbffed4356850f765cfede3ce8	1	0	\\x000000010000000000800003c622010b2bcb9dd815b2f26b5cc47358975237d20d88969beeaca4b098a892fb7b8233fc6b9f2556cff5792950a36b9e516ca7868ce8b2488af88bcb682edac4b91cb079b6463f2a228b87164f18b0f8de35f0d23e66b1ec69b5330dd82a89ba3d4951f2ab91ec88a02e969b3ed44822b02a18dd5139cbf30390528307465d07010001	\\x0637a180e924dc9ab0495568da3efe56b860fb585e317aaca7a3e4f73eb7f1a7d120fb95f0cb1f222ff310e660c61b9bfeeefc5283faa5fa506ff4e2b938ee00	1677314189000000	1677918989000000	1740990989000000	1835598989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x8fd650ece979747b9968772af9d081f570e4483943ba1821a8b08fcecb3676b69afdba22220549f7475c0e9393c219d011fc6ee45db07e8d6732c28057646767	1	0	\\x000000010000000000800003bd5f2b42479aaf16ada14918afae32b500e891635eaccf8004d83f12ea772b709b3086b948bc4ee9ca7ab370370e7a4800b36621302a63a51d34f13687540b9e8977f2de647a3b9f9f2246294b7f29d8c599a62db0b6f7ae75446ae6722e6aa25bdf7660a5a68c9603d906cf51c24af716d8e0d4d2bdb1cca461f7cef4401ea1010001	\\x858d5df3c03a577544031b4873b37ad088287fa85dcbc174bbe759cb252147c24538a6aa60489ccf92ad69920d76614a970548c5f9f477d3bff19a96e1f33508	1683359189000000	1683963989000000	1747035989000000	1841643989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
283	\\x8fee9eb6a7816c4f004aeb8b516fc1e67101bdc58021bbc300accc9ea6548837601440ddb87c76934f73735b7ae7429b6110c35a8063dfb202b87f670aa3254b	1	0	\\x000000010000000000800003ab9f6fb0e5b7a5a1b2093c183a27322823059c0d779059ad126c313858ee753257f54bca77670b722fecf9bbe1bf6158283f2e93a78f199e5618c2eee2b05f6146baf4445953b7952c70ffc628fd7275af25d0b47c2bf79700b8edda61d78a2f75253a7ab23869b48e54bc1e993a2b89b66f765dd456852350297ef961b824c5010001	\\xd2607e2b55935a36bab75f82328b8ce0bd52043e8610f69b635194c72c015c0f18b284ab96f16c3344d62aedfc3767e2044a7effc4b34caee1321ecfb1b1110a	1680941189000000	1681545989000000	1744617989000000	1839225989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\x905a0007d139bed3a10a8f2fa73f0ad5414e169ed815d9bde8375ffe12467752ca360bf6b2d10fea3b2a6b0c4c1af5530dfc6c2a0bed29abbab69f8e54f08ec0	1	0	\\x000000010000000000800003c0871e45b7ab20d0690dd1b3889708b72367439c71b96fb91d16917e7090d09b9d09c0dfe1b0c43d4fbfc6963fd5f0292ca452d1db963488d24daafa43f2bc4f738f8a11599f41ebaeca7398002006c62a23cf327fc14ee93766e011f80bb4f7e4b85a248abb7d702343627805d9974e42dd41632dad94d23b0471a487928151010001	\\xae2d630343957b5ed0bcc4135c8d498d63ba479d30a2f753c39e31206282784a15b23f95858a55c44f9f64d89b7a2118d10fe8dedef68b9fda8ebdf8c25e4c09	1663410689000000	1664015489000000	1727087489000000	1821695489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
285	\\x92925768e8a82ac922ac88c7e2162507f80a3f80b6a73aa8ba4a1b7291f9568ab7e30c92c940026a6e88473976faaa39d73b6ec8b15509473aa96281a4c95855	1	0	\\x000000010000000000800003ba8b07db85488acd987187373eed4c029b386fae43ff3c7538112b5ac64740c7537922486ca79c0a1f590932e7294f55d80b0abd15b8628dc92330a142bf8fd5a79361401dd810a2da779f11719af3f17b86b7d64efca663f790282bca1089f9144a254dc3bd9f897cf16aa4ec6efc16dd8a7f071bce85f521ed859036ecb4df010001	\\x40aea46ad4f3017033f0db5ff6e991ef352e6f05747da717d90662077c5448ed52e03d452ab2905236100c504f6dda284aafb53b2f261fa4283399a994fca30d	1677918689000000	1678523489000000	1741595489000000	1836203489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
286	\\x93a66482fc08f529f53d8248c5325e5ebaeb84b026d8bf7c5a2c89eacffadcd87377725e4293f7320c5d4fa68483f6b9f2973d201eb8fc2c7f011f031c6fb5a2	1	0	\\x000000010000000000800003dce896d399dbcda8a2a3b795f6cbadd0172dc1aacbef752cf5a5f45d52fbb2b03d89c6d0c738f2b390c0ac3738fcbe47bd930bda999a3ee520862306fd12044cb448d20a0179a8bb0d27bbea4b67af615823d484a63dee854ef6ebb1efa9cb705b51ad757e631ac1e6c273bd0178742a22edaa84e213931f824e068e5b87d6a5010001	\\xe7a6de50672268ae35047d7ce475763c969e7d2d6e877f7cc29fe91df999df797057981106714ffd1dcef14e7f685d8e11823bb4e37f2c15d6fcad01d525320d	1670664689000000	1671269489000000	1734341489000000	1828949489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
287	\\x96d617e09c12b9a074586cf3cb2e1929e209ebfeb79e4cf8ce84c88e6e64b6c9211ca20377924ac19f6f2bf9db3da044a18add0ee1c9c9dea9fbaf8eda507b33	1	0	\\x0000000100000000008000039a997eec5bd996364af7b4b9631e6832d02fdcbaf56cad97ad36919f52dc51596d857f1d3ca8d1b90e97f0fd5d07117e1c3784f57761e4ed3a9cb3f7de983f0649957e20d168b4e7934ecc308dfd2b3aa4c837f2c92af4fcdfe866d6b6ba0b46297817380fdc03479696843763572602e47e5f1ff7cbc704744ddd295b20801d010001	\\xac4e5a88e9bcea5dc3dbe18c88a2ba939adb1025689ec51307d3a4485f518f628818250fecc2ab09ee247976ed24889fbebe09ff817c8615d25ad080ac41580a	1690613189000000	1691217989000000	1754289989000000	1848897989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
288	\\x974a28982f8bbfd160da8b2c265d5a4675e618fc28514a707882513507c6527624b5ffad2aa3e21df9572725a4c306a74d838ac7dc1d87f64bbecc6465bff69a	1	0	\\x000000010000000000800003dec898e371e62b6b157a460ce663c5ecc803a24b4064fdcebf7acf32c32bcf10cb8103eceaf917ea797b24b4e6694ea29e6ecd20aa60f556274165b77473e04cbef1a47443ab15b188da9adb4d68f96ab3145d5b3ecadefe9a9e5046b58f4573904a784444b2b081e2fd0f62e469d9787b5e46d561d58b858387655e77b23587010001	\\x2cd74d29ea70a19677075d7b8853a7168e32d37582d54041e755cf5863d6949d50f529f296a0d55174ab6caf600ff9b040a92c52a0c8bc51331391b5e22ca70e	1690613189000000	1691217989000000	1754289989000000	1848897989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
289	\\x997ecf7c8fcc4d8cbaf12ee8aee6b9a59eb3555820bb2197d7adf94b263610828bf4a595056a25012900ed91c70e27af503cc1bab9ae1e7c1669ff12484833c0	1	0	\\x000000010000000000800003e196bcbfb83af967b8a99e8b1f7501ab46fe68156463a6e9284c4ad5b5576747f3c4d84ecd20af6a583825735fcd6bc7a5b7468de464debc9db900f4e297970fad51faba354428c927e3d8aa568b43d5fbdfa2a98aa1c13da50f2d1a0dcfb6fcae7536c923c5f6e3ef46a547729359c6fc4c9dbaf0ff826245430949c459c793010001	\\x0c0a3341ba91b1054e6845f17a3ce731a0e7ac1127d52e0cd684db0a4371a20efc6c98491b82a493af08d3968078d3e9b82756719a0ee6f26d91f20c1f4c5100	1685172689000000	1685777489000000	1748849489000000	1843457489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
290	\\x9aee13ab1c02f869e193d2f513ef12c84d15b343949889c92dd4b972a80ad945d0ec74d43de44e0a6dff129e6a67f0d8f6194aa637847e05e7cfcc3cd1819c73	1	0	\\x000000010000000000800003eca25b555911290cef651f522559e8b9fca9f943a79301c6c3381c4d0dc0002c5a48b64e292fc63e304e721d5f9cf1574af276b165dfccbb3d841ab2b507bd5059618091f2bc86c536819b460af47ef29d6ca7c737d0db0ec72d934af149c479bdcd3c9ddae854516dd5b52b8a9e0ff434b545ac9ac157a84d9c8245f3cacadb010001	\\x11bd966a5bcaae74e21cc6bcb957e228609b46e5f707d4ec6d79b4291cae9b008f46eed67c0104da68ed706459bf2a1932a2cc98473382b6fffee6129c6bad01	1668851189000000	1669455989000000	1732527989000000	1827135989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\x9cdad99bbcecbc8983bbb245546d5e7724336709f3cb74e5c01a0fd5355fdc1882287dd93a9df72a2a3069d519479679a48b4f00f32efd5f6f7f20909920b3ad	1	0	\\x000000010000000000800003aa90224dfe6f037f4307f9f31a4919357d1682cf06d08208b5c0803afdb3ad8cde14c6d93ba26b532641948115814ad616ff903c0cbeb0202245fbe4fa16f77a628520f1ef472442d6037fae08fa38ef72bf263a41cff9d7588b4251281fa1ed1ac5ef356c229ac432b56ca43b2c3238da1c3a6b7a45250506975354ec3e0549010001	\\x90f341a3ac18ba74e9c2266beb4838221f9fa222e52d5d736bde1464bbcb7d308c3c72cad0d5ad45cb8c9e60806e5f598cc618c77a6c3913140daea18b74730a	1680941189000000	1681545989000000	1744617989000000	1839225989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\x9e9e6ec3282295f782d70d98287f8b59db710fa1d6dab2800e6dcebf76e09398d09f214e7c8193fd3c88cf99ac6658c217c243596748d59fff07e6283a387e4c	1	0	\\x000000010000000000800003d3598e374fb1c67cec94eb5fdbd314d1806175c3931c34e1a06086735afd378cccb9bfe64b820d06702af19c95c019176a482e3ef9cbceced0aa9484489ad1fcd5a006135591bf6d61e33ec60e39a98cd884b6f145aa2d57f3e04af8c3bc183b8c84a04823c962f3f85ad948ac9fab4eb971069498822100e13047cfcfa06397010001	\\x03a2e4d2d06be409ad34ac2dc46710b3e05d115eb3ab66477fabbe54f575c83e2279b4a4bf7333505e7c8fb4c62330a0d9fd30d7aec958e30932db1102744b0c	1675500689000000	1676105489000000	1739177489000000	1833785489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xa08a113085fae45e8fe8dca5ede2760aeec86cf47ce6dc24ea7a92389112903565be38e7427d3e0a3a4480cc3ea6f0311a4c1635421011feb0c7525823b0495d	1	0	\\x000000010000000000800003b22c42088956732a50585c3d025f10f65c56cc10aa05629647febe9fbcf3b6e903181e2e559a00b6f5d831bce52a163207a7979ba43a8c632efb46df1caf4962297afb6e964ad673302ef0f21b2ea0f115f44d5d845e27cd6737ba8dc140d6d2bfcd16d9bca74cd8d97c1dcdb23bfd24df41e2059d4ddbaac92e613f0742c4f5010001	\\x9c544018ef9e373542fa8785e705630624a0444261eeba99a9fc743c8cdac5d7fa810735bacb4dc78a665fe023776846dfdbf1f6a4416f583a49fa99bc94d20d	1667037689000000	1667642489000000	1730714489000000	1825322489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xa1f65a2a24264729dec14e53bf5b1ca1402a70e597676c57a6888e5eaf31b6484136e906e8ebe31467729c04008c12c5b153edb1d4a0487c6c439f3094d3287f	1	0	\\x000000010000000000800003a85a8a40c0a91a52312928e26906e9eb0a8bd167db931ca212d6ad652853524205a5fdcd8883d98ae2ec1f7fec5c6072846e1cee78e1e33c1d8e36b20675adbb78c3b9a55c5c83cd60f440515efea2a0b9fe1be9d5144118420acd04f354c5512feb87b711ebda08cecc36ac3116bea003d2a035771e9c2185a112ef9b7bd38d010001	\\x03834767bad26d4bf64c768b0fe3f8213336443d2bc7356973bd673b3b36f533aaa9691213dcbf01b75fbe5f7b5f834a9336b05944c0bbe2d5ba2a498f906609	1679732189000000	1680336989000000	1743408989000000	1838016989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\xa20e85b23555a3b5335f1a67d0e312618e121dfd5ff5ca676bcd4f455f21688136ecd462b650359a2043afc0b36cd207d46ca4e6a5e285449991cb9c23d413dc	1	0	\\x000000010000000000800003a705a6fabf909410ddbf29ac46c518b79eaf337549557c7d2bf265affa1d11fc795fd0c43467f4b297cfa3fd2680afa28389612825f02b62d8b6c54b85a5c4e0eeb8ad7b96604e6460538678b3bbdee6353e91929791779a0b55f36f8d67e311d5ee7a9e2fdb8b8aef80c0bfcf3701e5bfbdc25613df68374601f8cd98a37499010001	\\x22b357875cc7b903c1a242b5f206938dd4e35c424c3a35ce6bdf3e101843ee16f8d440d9110f81baacaf29e490c80fda5edd4c9d45b4d343843627e0fe97f80a	1685777189000000	1686381989000000	1749453989000000	1844061989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xad123a695a2686761acbcdbafe9cfd4cfd41058fa464ddb220ca35792b92229565c91cdaa7a06e999007681bc96132d92f5992e1c69ef2d34c34c77742458c65	1	0	\\x000000010000000000800003c51b847a006dcfd9881ba5b7f466a12ab067221faa7661ad79cf732b1fc60bbd989480b40e8e6f1f4507f8d319ba1f4de6f8d2ea72b5e44daec108ff6abd390d07960f5e44d77765bfc0f94c4dee0aa6d590c4934bfbc04a54d447c91cbf4af1af8a618191ac7e1ba0298dc315fe3d32109142b4c85dbcc1c523cada2425117f010001	\\xddd19347e612055e9643ae4dc93ea737cb3c587a35cdaf47c3328522aa3e0defc39b37965411e0ce42d3e3b33d20265b2f9bb8a0ab06a48fc6fd7a108936f30e	1669455689000000	1670060489000000	1733132489000000	1827740489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xae32c53430d449c9414db7876d62e15033ee07aaeaa21e357bac76a6f376316ce58312b6b981d25ec7ded280c6e73da7dd517ba3b7ed3d34a4df7396939efc32	1	0	\\x000000010000000000800003cb734ceac6ddd06d96c4f4643361c1e78e432caf223a170f79f2adaf35a84c5ef1c28c6177f0698d0d2d135a44b7c4f10edfb56706eafece05f849038e464152f63e4682afb980f6797ece20c82c97255c3f8cd03203b56d5e29d837290eb0c544ccfce01f453d4703729bb600b4d9756bcb7f3208fc68ffd1976eae3973b73f010001	\\xc7eb642958ad749f86f81ba0c9a7fbbd19164c2e8100fc57f2a3622d7c169ab2e913bfdc50529888b455864b3e95d21f4dcc3d942ebb984a71e5830352ed130e	1683963689000000	1684568489000000	1747640489000000	1842248489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\xb012a35ee3ea5f4355976f4e8787de91d1223d83291fe7206326c70d1f58af0aa3ca58f8ca42fa511b2be57e90c0bf22f502ce0045e2528784bb7749e67b3648	1	0	\\x000000010000000000800003e83f69c568ddba6c0bddd306c238489895093b7b51946ab7a552cf6677503102430e8ce8ed2da6683b706b3a37ec81a76d5f7018d164a16f2e74bd243061862846f3ebc0e796b5ed5581d2e71e1aad59c41bf928d226eb1cc8289e50ee03e2d9f695ae0e1b46c963a20978f2e7a4b129d7f98dad6de020816e0b9a476e94880f010001	\\xca5756da5ddd7d05cb75205a85b20a3778cad095b0ef3efe46321c053bf3d8d487a9039ca8cc0107207ecc9d4d73ad91cbfcc3fab44d0312aba97b8f8a6cee08	1682754689000000	1683359489000000	1746431489000000	1841039489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xb5e6e7563056f21596e2432662c5782db0d98933603404843efb7c0652fb74f1aa9ce65b053770ecf76f8103d13f1d683984cb4f72884dcc95cfbdb7675b1670	1	0	\\x000000010000000000800003bba7b19adc8863586ef5284a9a95200eff5d713044e20afcfd45c520cd3d2791ee600bb032690ac5a87de19791a590ae842816783fe0acca027a45593eec85407343e391cac7bff92e1325d155b0464ed4fb09beac07556841596d064fde283a949e410576834a18d5bfc55b342d15fc7e3aac76f9f5dd22538190220c863177010001	\\xc3de22b3ce69ce7cce05f0d3037f8a17d23708950dcb089df4a2c6d80416df6613cc07bf6178a4bb12f905c5127c52f210ebffa9accaf517e7cab1f85146fe05	1674291689000000	1674896489000000	1737968489000000	1832576489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
300	\\xb842b4c7b68c2b1117b17e49ae8f94daac033d584a6e4ab2e2f85717c3b45559bc6e8ee9ef4c450daed5ef215f88bb925a0ed8205c6da363da43e83f4d8916ec	1	0	\\x000000010000000000800003c98f46629d92f24ec9142e16b3b1597e307519ef0620667c88ee7f369f6df2efe18ed620571282863ec307b61447aaa7e95093586318267ca5d17611746bc8bdb188a408df08eff1c032583fda968d56fd900726c1fbcd18290f8519174204ec93348de0376dea64625eb025fa844a6a710ac363ee2cee017b2585062be9e9ef010001	\\xcd309ba244b3e7fa7597cdd382f22ea1fcc75dcf13720591cf6ad9958961b8bf217d74152227f8e822d3c2266ecf93d17401ef3b37ade52b96dfd24783f3bf07	1660992689000000	1661597489000000	1724669489000000	1819277489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
301	\\xb9a23d0bb8a076db676d25d18723994a9002c9eb5f4c269e9dbd12249e8dac358cf615d720bd46ba5d9bf8400d77ba003b39778df45cd534a168e2d2a96d62e3	1	0	\\x000000010000000000800003bc221ef40f0a73965e437cdca60dde2a967e8268c4933e4d7cbe6f17c6766c968f09ba4629f28402e99a6fd20751ad454eb8c1da961f54a291a79c8a46a4afec6d63fe4ae2687a8867fa670d59f166f4a1a67bfa0ed0d3be1273f795333ae795c7048fb73b9c51d1d4be2da8880ae2213b189607ca6187cba25840aad69494f1010001	\\x6b22d4292057bbac52d7636b1b900719ba7d3277f12e217fbbb2df4f1495fe5a4720d071752a41f9c38ba0e70dfc6b65df1b7148815109eee67025e07ed6c50e	1683963689000000	1684568489000000	1747640489000000	1842248489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
302	\\xbb56b43405caef005d37b677ab88fe63f78b5103ef42e6aaaebd0f5df8f6d2186e72b343a1f466d861d1c758eebd670daaa643ee25de796932fbf3d0341611e7	1	0	\\x000000010000000000800003d2a8bff0f56812d770fa547a187ff050109417f85a44906ac4b273fef9f08abb0c8e70a7c72e626069fe20b28c7ecedbba6190a469d8864305e61c9b8e3f7f842d9dff6aa4a5c2280db48b9fdaf266e9f2f9035ad0b7b99a24346345106ea37c7f5cf512e1c6548faae5b406a599cf93573e3ad4be502951a04e743ca6a8404d010001	\\xb9747f6a7867600a0808020e64a2b69aead5f39332e798711084f4229cf63b52d7b41c9fdc019ab98e2012e50f4f2cbf448bba09c17154b0aea77ecb9c77060d	1673082689000000	1673687489000000	1736759489000000	1831367489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
303	\\xbe8af5185370e67ec401b0fe66cd6fdc8e7fd7870fbe47bb52440f34a5d206d0c8692ac70e4034460eb295359a8d6d8f4aa2a5b6ff6a70130d5cb4c6ca569a87	1	0	\\x000000010000000000800003e1baffc00aab1bb2f968078bd5d3fb93b1e298f3d9b865dea253bcdb9ff4e1e33a25415506c16b91dbf146769fe78521dbf3e2ca1c440ea755b7fb721a1d3ed1cb762bd5aa39932e90155172e934a3182138e587a86b69af2e9306791c81d825c499e82fcc181ada716fc84c236aeaf738192d8a1498c8fe9eb395c3d1ff7e59010001	\\xc63d2997cc4f7a0d0ef85f1a5dd7e703d70a92d3c3c6a8e9050bab4c5c2836a4d8e904ba063dcc4fd0c17d29990a0b290d2ad50005260a80b3b72b6d981ffe0e	1673687189000000	1674291989000000	1737363989000000	1831971989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xc4968a94cc487205d982a021c96bff734cccf79abaab4de2f60fdf6dda36ff3fe8aa33c4bc48c6daca1c95f9774094481015733925cffb873cc535f526f64322	1	0	\\x000000010000000000800003f1663adda88b962b1ec10591767aa36dacf9f593952e398997a1efb54cd8a73567b55d7ef9fc008a3ecbf2b94862bdad8babe955443a07bdaad20cf0f46ea3ac77448d5caa3f351f1f166837426a138ad29f1a553fd5eebe988fa19b2739c663bbd895bc485b4a8ceda3c4579d006ca3b5509b37ec5fa03ce3a80ec00e4dc3b5010001	\\x189874f2b0211af558498dcce5bfd558e020ef471444be79a3823e93b4f75121e7c370890b98518b0720b87b131e654f4fc36e6836fe3d3faba004f62abce003	1665224189000000	1665828989000000	1728900989000000	1823508989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xc74a88ae24a65e15298eaa87a35c1b87ed2256d3372afadce6d6d7024e86cdc0deac532f029c32f064fd34620c6bc5489cd886960e18f1e0cff23ab2de2e64d6	1	0	\\x000000010000000000800003bfd407af2a54c5ba0813fb64ebac8460ea93e7cb73a7e2a3404db764f2b2321839d2b49d83ef21645e50effab45e2e8f66a081724dcc28b61b77716deec816c4d9a04e3032acaf8a0d263664d368776f4d4864ead116b0a47bf9adae58402b751f28e50e6fc1e5b2e73bbe33062f95b20b6397063b77bc654d9fb2f2bab9b415010001	\\xa8e543adebaaa7050532652543307ff442b9b02edf75c6d569542b5a0602eacf3495008d298ef9e6f497a749f89b36a44840caee64fd8404f43dfbdb9f4bcb07	1686986189000000	1687590989000000	1750662989000000	1845270989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
306	\\xc7ee550ee6237ff0a2f89d94346b92a9d28a296dc0aef0d43857eb071c72229587c7f48eec907676f9b2ce2660e08fd7e8b53250de8696e8fe43e07a5163a4f4	1	0	\\x000000010000000000800003ab67719c857ee4400110c7283555bbcb89aa4807c54bf7d716790fd2ea92b10651f00de1e1d74f6e519ccc85a6964c230ed5ddadd98eb75b6bf3e395841f825037ad1abd3298a4c023a44a72c1aec06d6ce742ada08dc59623542c438c1c54992481b628bf9392281bd9e5a794af9e594b86ba2c90df7e2cce534a4371d43d0f010001	\\x3e899ea5ebcd46f0f46ced03ff2df692d233a34b39fb3e0e329468fd7d2da24e027a48030d56104407957cd29722385d990ef5a9c07546841b78aad66a07290b	1668851189000000	1669455989000000	1732527989000000	1827135989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\xca82b06b3ba7f2aba3ec04581492b575cedbac2587cf8dc574eeab4e0f8901ba76cb99a00d8d089db979c723b51e6fc5083164fb3d04feaa5fda7584e7c1100c	1	0	\\x000000010000000000800003c555c89b4e154cda7bf34ac7da457c611fdce21a1b6bcbcd26b555bdba0c4e1abcc3c352808dd82c6e4ca7f3765319512417d6e18db34fc305a9a836d7893664308567ceb470a6fa1fd6675fdb489c3a173db34965d0dbdaabb5d963337c683fbcb929024568954b1c114a9bfe0375315a92096b392f8d0f142a43f79a03269f010001	\\xc3a51a6c23b39fd1d77faf79cc99d60057be1b8b87534eb3dd147123aec7a508c89ddb89b70637ee77f00c2a9636414a47df834dad1ccae89fcca97d20af1106	1662806189000000	1663410989000000	1726482989000000	1821090989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
308	\\xca12b8dae251ecd6fa018665c152aa2787d129bf752dd375613838b0bc1010932906213e31bb25f638d935b321fdd2c0ad98346bee39e1a8c32a691de6bfd1b8	1	0	\\x000000010000000000800003abdc9d8e80652d51459131126a35d6dc8201125cd420809ae0c5f768f69e5bd2ee5ced84a4a09b482f0e11a206c8d12b1142467c1779765be1359613e68733e5af80406fac64e2e7583de61d51ea09d9cd7a425e91f65659d196f31e52caa114311c38122df0911471affb60cd41a7463790c479ea55517b7400d893147937d7010001	\\x85f3be9fb627c5c263d6aba4b56346caa37784d98c167481a53183a769d098f8003bdf170dbb056deb8e368862fd276d08672ebabef0933bab9559f141ea3a0c	1665828689000000	1666433489000000	1729505489000000	1824113489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
309	\\xcb0afdec773f7914ef677ffcd0f4bbd900652f4d2b7c71d12e1eaa50ad37e32b0522b294106c8627c66b45807fe860cbc4ed86877e069acac20d4f2424e08b47	1	0	\\x000000010000000000800003f8630d53aa2739b7ecb6569abaf7fb0045bedb8bd031e1356f2b040cc98b7275706445d559071d0ca42b3ce75d9df259f4d3a0a6e7b26674e8d69c5020e9a0d89d205530ace14b6f48b479a5fc083da070734c3bca82466d3b136eea693a2ac084125911da295d00f8077a49d3d00668ffdc8f9980b73acbd28a8611dff2fe37010001	\\x5956178a56419c944284690b02e5cd45272ef9f229a0430c52aa516067fa91ceac137f29818b16a907a2bdc889460e808989a420258633a0e126da772db12904	1692426689000000	1693031489000000	1756103489000000	1850711489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xcf9afe89adee124dca14334c9f4f86a8dbf00b627571857377ba4f7bac8d327b68531159b02040a1fc8633708d823eca716ba185ae329cd9b2c549e231c56893	1	0	\\x000000010000000000800003c4f64f4a195b9142554590f449729cc3fb0cf0c1af1eff001f88b7569178ea249eab2303c746943757db94ad45443be26929a434108007346d724d5505aed62558e4692252a287283de2edd9de87766160db0f4d4e7025c6c0600e140dfa7758b2b8e7cf15167762c1e26f0ac3a9288c1d34a51081bec3ec17cd8da154689fd3010001	\\xfbb4da062753f471a213d515c919545947774c26834b172a1da77c5268c6c3d6043598e056d8ef32e8b57500ea7a22348224abcef6b5b3d03c9147dfea643805	1660992689000000	1661597489000000	1724669489000000	1819277489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\xd15acd56b56bb67ef1a821cdf68761ee289545947f6bff6296ab43daa7df3128d1bc1dc45ac7c4adaf2ed5e319a21e854d1854a0815fbf7c4ff2feb3386f3cdf	1	0	\\x000000010000000000800003f170efe380beaaf9bbda51fc58a298ac28df0fd844a2c8a9d2fb29468516c4b493d73de5e721be3f14354791288d2134238f872200c185022dbca4674dcc7fff744e60326027d90dfb4e1a05783f7ce7d81b4c9c5aaac5612cab276561f8cd80d0ec59f0d97f9b8fe7e367d095ac1e88d7016474b7c2dcbfa578e21dfa3420af010001	\\xb2e6102c301b70a8404484424568eeea42f52a06b6693c96bb39683624d1f8feed8eaa27e6db9f7f474e0a5c1ea77a0c6f61bddd4a8abcff7f78aa425906a406	1670060189000000	1670664989000000	1733736989000000	1828344989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xd96608e96180432716421c16d92a90d5087378266755d478c6682cef0663d886d164ff6136e2abfddacae557d4c4b4011579cce6d6f1f0ddc3fd57d8135d7c38	1	0	\\x000000010000000000800003dfa50dc7105c5b7860058b53eaed55ef843fa9a8c2d4e37f9ba9006212c330402dc38344e2ab2b74262c0550b4cdb00446194becc991d97b4b53426be0ecbeb8cef28efd09c67bb9f8419c6067011382495ccfb8c340dd324325b921e64e4cd4b9913f83122ba098d31b0bc7d8a616cf684496bf34c530bbf7787068ce4951f5010001	\\xc0bf830b4c34a9b45d3c61747d407a4fa3bcf61869ede052db8079fe494ca6d6f89be63373e0bde9abc007d120eca7940f8065e8fcd562257707d14c908e1a0d	1672478189000000	1673082989000000	1736154989000000	1830762989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
313	\\xdb1632390ed56c222d100238421638dc371b771f4183fb132c8276cb7614e02857f5508880e286ade14bbfd0a6cf33f3e17ed4d2f288958b63f9d99954a7f427	1	0	\\x000000010000000000800003b908a20fe656b8279e35d2e270df06d933db632a6a1b23688f83f5027dc4c27e04d8c14ddb471084e98f808986b1d9f272243f4989f04bc5c1dc304ce3b7bd04c506f74013cfad931854b5929c2ba0399009c719f99d3e1ec788e06d07d28211ddb136399d12441b50f62723364083e048a6bb4cebc274ee7f9adfded265aa7b010001	\\xfe9b23081bc0c46c1f61b98269aae5fdfeb887758c8a0a1a1d08e0f16bf679733cc32ecdc35d1a25011ea2d16aee5c16d9dbdaecb637af1858ddcc2eed89e204	1681545689000000	1682150489000000	1745222489000000	1839830489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
314	\\xe3a2e20ec0468b952fbe2d8fb36059ed71caf5cdd26b7eaa63b1bc0633a97f66020358ea421e23a8eea820e176f22e0b7b5ef0c92e199da7a6e8779201795e43	1	0	\\x000000010000000000800003bdfbd88662f9f5492ec5c98a547f73c09a6c256340822c9c054257eb6bdf13ae731a79720061da80852216ff31186bcd2b98e7f78e060fac9177b0ee142ff4e67f9fcce9dc85e525fec6e3098c7e329bb6fec42db45f12b8342b02d504a718c73151bac95dc7adfa51e2ad97c518a3f59a62746a550fdb13822cfa1e42e201d1010001	\\xf3238c89e48dfda5aeb941e7b87d8a521135c8d929d531aa46acec7ae1fa48b3c70429c700e9e238a993ca0a7f7771c7fee056ee9924e1c34d998a017ece2e00	1688195189000000	1688799989000000	1751871989000000	1846479989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
315	\\xe45e1b821b1f479b9a84e3b671b2acc613d225125041316a062f317a902fdc133b88b49aa3af249ee7d210f84862be3e03c5612cc2aedf35eee9792c3f96ddab	1	0	\\x000000010000000000800003e021c9b5db411f880afd547261af57afe31fa5f5c6d9b89fa79acbcf9d2f51d1e86049090dd04afd54f766f2c717b8012f163e7ae8d1f34db377ce115dd191097fe4ab00a3541db25e1c59e542118b3f47cf99f3463b7f44e5fee2644403448ad2c0cd188942765001fc5c206f512c65a5328b3ab356eb4f68ba96baa0b4d6af010001	\\x2b13775f0defd5dad50278d8455891d2dbc1dd2f9a2c0b00337a5d54af99ddb3d6feda5a404a37df091a535373f1f5708e19ba1165d476e7de975fd1953fa206	1665828689000000	1666433489000000	1729505489000000	1824113489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
316	\\xe85a43f287a9fc1496f878581a25337ca2dcdc3289d37e4aaa95ddea4018cadadfbf7010f2f37c7770cf8aba44e5309b82f69fe8a2b481372f08b69b5d677b55	1	0	\\x000000010000000000800003bef0b7f6ad05e47a84f74586bb3eaf2cc05f3b189acd7fd9a23e8a1464bebd85c488db142b42aa9a8bd300382dd7ff54b104a294ab7fbc75fa6562b514926abdaf6e34de961130b0f4bf479d5c88eeb7522ccd717b57f7cc672fd9f7ce9818c31444c3346768c58f55f2a945cf05017e21ba6cd354a71f4e98407423b433a9d7010001	\\xe1362dab7172ee351bd79cb005d7e8fa3c6f01a8afeac8cc50b6109ba8841a291f017d6203589d228c4d2c8f5dff08cd27a006e84d6d44a49bf4aefb33f6370d	1681545689000000	1682150489000000	1745222489000000	1839830489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xefbed685aa3be42e8270b38928ec81ecbd349ad9611295be286b71c727c2a8cca3906985226629c6c188273fd9547588f27f8017ff286e80666fe259de512313	1	0	\\x000000010000000000800003bd65ea1d2798452bb5bf769b4c9eecc25eeb03a036162ad5d06d7b9356500afddaebed9157a9b6b92faaad77e030ed73d028cdd17dcd332848f3cb4c69ff7ce4d97889f7d007baa9d64844c29c69fd5b11f940c89c4c5dc7b550d2cfcedf6dc6e4576d8e6548916c871afe70622b508f01a69aed2f3afaf69732ce94ed8b3ac5010001	\\x4813f8af5e43d19a6c014de5ce569a8dbd1bec8a73442830415779badad52df302de2c754239f4bf1bcc0790349d6845b0ab7b626dcfcad0be4563b2af8d7200	1672478189000000	1673082989000000	1736154989000000	1830762989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\xf05ac686fd387e062796a4b33930474c8ae42a1a187bab04328ee21121dd76343bbb442b9972b9b022af85b6f1cae2528da1949966aadb419b3b1909204e8d7b	1	0	\\x000000010000000000800003bbb1da3f4239b5d71a0f20270fcaf4a32badba8720d7873ef1dc4c8925710ea7bd58ad1143f056c96d91f9aa0d180bfb44d045f4c8a3d72e22a2f588a48ab50ee76e6851547c217e28784b731ca776c5d2f49ba39104be8affdf97477e82ae0ad498275a702939059e033b7ccb0f50b73cfbd33d6be73ce3798dc67570fa1535010001	\\x8d0bd8fb7286a2d36a6eb0c99ac5f9b7074679171869e240c9d367e04fa9d4db4a9a08a678ef73402eb52771f57f87f9fdbb39aebf3cb1a108ec5e1a6110f80a	1679127689000000	1679732489000000	1742804489000000	1837412489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
319	\\xf21a28f7bbb91e1b83bdfad760d8155037fd16d2b284e42e6cc51fc32fd38d37cc7f1c6d0d80734b414123fc2f6db5a51f6f3cd80efcdf09a880073514ffbc43	1	0	\\x000000010000000000800003bcfc3524c0af191511d65a407cf5fdccd4ba2dadbbfafd92cdbe9678229535b798afcf8990592d2be57a2b32140e7847da4fe5a8ac7950b84d276d9de8184b57b8b221a17d9596f81d42b241dacc5d477d46d2e803c47d8ba6673fdeea19ffa94426eff6a7d53b52eab3d229cf88401cab07a40e23948700fe9fede2cefbb021010001	\\xb03bf3b93256253cc51f637149221d4a364a4a5c79d8624c1ba81f495b51a3d379eef2322ccfa1e80ab48211f1b84cbcf9f49394d1a3b02e8324deb629c36e0a	1688195189000000	1688799989000000	1751871989000000	1846479989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xf6e22801d3733103477b8fdb538f8e99883dcf5a40e2d66d35d70567365ba06cf140ae71870049bba78450af7290adf15c164173e4396ef6a267184caa4445fe	1	0	\\x000000010000000000800003cdcd13adf73168dd73e797d4b80150734c1f3eebbb2a6a68cfdde9adad458a60a9cdc33cca1a2da3f2bc18901dcf0f1b6b80db0d4ed120e5c1a22dcc5db04f22ce304baa365102bddb77bc2afcfbb327db8fee09fb79212f699d8f0a8e0a1f51c487b1fa05e56a039ee5e1b57f5e3e91732d66b9505b13d5d769f0fad18fdc07010001	\\xaa612673e40352af2b97e67e0f348a7bb69727fa0667b297770faf75aa07536b1e0c9bee3ad189f43b5a3df03834f4cb952f46deb74c332c8679351ac189e808	1676105189000000	1676709989000000	1739781989000000	1834389989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
321	\\xf83aba2922fe86b7345656155b8e0daeac4bafd7420539c8f1552ceb80a9c5562dbee22b424f7bfe9785e3bf90737ba2b99fb415a363bcce8a51a0d1043618a5	1	0	\\x000000010000000000800003d9302fc6fc86efb65b6f54609aca45f0cb99d60c02ce387c969dd668ef34fef353471594f81e1dd05a6323b568de408d261aece103b44f768153a34a4ff529322cc3c012ffa27ea67f8161096ddbd737c849b24d92e1cdabe39f3b7ce430269c8dfc41409200fa5402649ee734c5495b2555c8b8fbdf3ce83768b2dfc2fec6f7010001	\\x0e8af01119f5769f99d79ded34b57d202a75227f3c99fe22c7942a7f8ce93e1e500aac99ea1c3123208cfc4b0d89b7474a6375ea93e51bec693f67874d5a230a	1687590689000000	1688195489000000	1751267489000000	1845875489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xf9a2e87d77edaeaeb1e441e3706254a4d1ac11d848fd90a85649900bafde86e8af761b3ccb63eb678faf42f7323060bf19302484d945a8150e1b733c12af0f53	1	0	\\x000000010000000000800003e8e142572bb704a00b2cb043ca3482f3d4e73080f966fc409b72c26c09427391b166c0b94b51e5ba2822084d4d4a40dc0f26a470df54e2ddf9c9eb489e61c81ff90444a82fd077816dd93cf07b176104ec1390656fe890b3986c71a4e372c459a4ed1ea3068bdb800da8160539d194c50e274f92f760c1db35e29eba17a25f71010001	\\x451cf713873219a3e1dcdb906731873aa1c154353de0d601c162696b8edc3ed991c9f0a2b642a600685d3e02bff1216083cbcf44cb8150e5206ab587c1b7da0b	1686381689000000	1686986489000000	1750058489000000	1844666489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\xf92e86e74c23c07910439063ef61bf7ec171469c0e6ac83794ec1b71d6e3805b6f41c1c13b326f17c6e3901ff4b9f368218e11c8b52822b6571c2d7b80fe7212	1	0	\\x000000010000000000800003eb26bf82178fc19ec20562489e6f1eb9e5b38c075521cf27b7c39b3b5b54f5fa879cdba5ae7ab50295a2f3391236a35335ce654d46824c509e55b8b1415022ec15e56396e3773e33c5e6d393c6fad8272c925a65bb1055fcf569bf29edc796eea2ae120bf7064b241664a8611bab7ed2be2840cbeb440217e393d81b8e81d613010001	\\x6d858a6e08df1a9ff5d015f48bfc7828b2e8fc93c157d8115036573bc9d7866c2e22027981f2afe57897c9c794d4b97fbc5d28a812e11ae598b0d19e8e8df70e	1680336689000000	1680941489000000	1744013489000000	1838621489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\xfe4ad602cc6e0bfa4e93e0482e7aae1cd0f26bd34cc89eb32264823d582762d56903c1bf6049578a695cb79132c29cc0b46568db9bdafa5c1d22dce380f4c29c	1	0	\\x000000010000000000800003d668d82da6c5a10c0ccd9408b26786d39d7ba289070e345dff9359f57d6ce24affcff26fd1c90921481b97fab767664c797d44e32b2528122fce75ccecaf91668e33e067d55020508fd93c81735bedd9282348bc4e8f055c379d71b20bace165c5b73f3e4b5f02d79f13a95172b0b57b14401c5e4c42eb2075e0575b94433189010001	\\xc6df526c4ad1af894a0ad7162af7c4852e199f279a164a80fb40db7d7412f4114e881345fc4ff4f966a7f192749b6889efd1c6b51b45e5b4498ead43d199e108	1689404189000000	1690008989000000	1753080989000000	1847688989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
325	\\xfe5a1e0b79ec967aee4fcba7fbab8066a3b25cd3efa24408c10f425d8ef6cffdf3f72a0c338775debf980855fae94b182bd9373dc3b0dfac1597cb09bab61bf6	1	0	\\x000000010000000000800003ccd29681beb38f67e12cdac7b0fec6b431a14cd223ea6322e4c7ab1533ca7ee0a3835bd5f73d1be0ffbe482b36119e64abe7df105071b6474079cab343217e13f5c1efa803cb4376b2732379e46c4a7fc948e01f52dac6e1df4480ddc5c05b558404a0645d2dcd14b1bbdb9ba421a4b9b3b74c59981acfeebe415ee36e7943df010001	\\xe8a77cf05053445961835c16e2430eced717c69fd17b407fced3999b7c63e24bfea53d0328e436bda9b5f3d5cfc81be2421b5a38eaaa4ca7d0d1905c1a6e1a06	1686986189000000	1687590989000000	1750662989000000	1845270989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
326	\\xffb2dbf3991f66d17af512ae3dad712460ceb26d1e309b821e911dce00510704c767995cb70f95574f827edc04346d5597464641c705c45c8404d1fe57e1cca9	1	0	\\x000000010000000000800003c95d1fb54fc65f4bcfccab0c16ee7c6464ec4e391b7d43e85abce3e415cec8a2573df050b2e3b335f140074ab90d1b5358913d9e2f093834d8132bb1c494ccd588a1287dd54e7c1997eadbb3486979f55db7a085f89b983d2e79942c74d4efd5850239e4b6aacdf9271cb0007aa725b9f063694245ca568820ac3c54cdf596b9010001	\\x32978ef14967e0680b26a5d3b23c149e87eca9791534b23225ab54cc635773489f0cad15a2cd99e1b1f3c873311fbf1c6b3d78914099e39eca7d90b58916da0e	1689404189000000	1690008989000000	1753080989000000	1847688989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x0373e0c75c86e03b3320239b29d0a8de4705f478d2cf0b6eeef13cb45239482cc8b4380a8cac1d4d47ed9494d74133e7b683b592ada0d735eac8d26eda37e1e2	1	0	\\x000000010000000000800003c570ca44568451f31100658575a91c87260fb668695f630b716a22a6cc148891f90962b3bb0f3c66cd9f1707beeb9ca2738608d29ec904148ce1bc7a057c1add74d0be0dd0152b0a156dc1a4753c53101ee53ff85e5061ea18e85afcb077c7bfa286624159c8450c9b4c996328a4cf2fa989a76ad5b3d4cfb2b765aff5d667f9010001	\\x3695a5a6810de48a4224631dea8a1ea6b9f33cb2b7de6da9a777cc735548771994c7e8731759405a3eef03c5e8147122c929fb277534bc1b89c6f139c1190600	1692426689000000	1693031489000000	1756103489000000	1850711489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
328	\\x06effc311698f93cbcb34efd6acd9a303f45bf2012c2bf0e233e60083e8e3ebd8442e60129ec44fb0a4747a185ac3a19f8e36182cc92a74d2517875e01cb6846	1	0	\\x000000010000000000800003ce0dcd6791a22b8af6264ef47398dccbfa0dae3bd9db97188da6d7bd01890f4c4db9c330611773ae69ca16f3bb7cf2a9256fa4756590d9dcef63010eebb2940fd3fa729f36ef63af5b0a8d28ef6700608014f9a7ed4abe81cfbab8942eb34a29b702ec9b8b577dcabbf461dc8e58eb6e3f6be2180ddb271d1d21e698a1d634eb010001	\\x216564547aad5cc735351dea5e05fddeccff37ec08838254fc423932abde4ba3832ee3243a136766e7acf50cad7d4b0885f6854c55eea26282838a9be701bf03	1670664689000000	1671269489000000	1734341489000000	1828949489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x08bb4558469e996ad4d7a2237a9131b172075329811509f51c8130093aad5b33c2b8dc0c2ae0f3d02d45171963817ade1a884dd5ef4d22aaba57282e4fd36ca6	1	0	\\x000000010000000000800003b6ca4b84a934e3bb1659bb1ece2f6e290aed0b9e8cfe179dce9d26140cc9d2ab5324af0a9c361964fed85f81d5e1cf6d380d55fc891f8857a266d193cb7cff6c4278c5a1a667ca6b9414a5bfbbeb88bfb41cbb09cc0bb67865063a86d154c2a2e0e815ae66b25e344f01bbe0fe252977d0abe7662986e06192cd448602477593010001	\\x8b9125df11412a9d8ece674b26d447211e0b04224abbabc5807f49173ed18749b0737a0e68517e4622cb32423e4b120c56733a964e2e91cfc04de805f20a560a	1688195189000000	1688799989000000	1751871989000000	1846479989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x0a370d3304f474b8a25452ae81c98ff35fe0ce0df1525dcfea89585347e1077c885e6224086ff1567857b2f89941c3d3f8d998628a0196cd0533060217c02799	1	0	\\x000000010000000000800003dc1ec4c05bdcae9cb6757539a0f213617b69e09836665c41df508bd8753f07244e6d247a3720588f9818f1c26c50262326839ca23a292f0bf184f16715483f08853b6302d047e096f8fa1e44412f65e66289f69224d3a37dee8044b82212897017f9ecf25f46fd327dfa383a9fc6088f423c0f56c5af3128fd4a702a7faea80b010001	\\x840646150787de72815a00b287d4c2ef1b8f2cd7356704be3f3bdce5bfdc9f4ba99408b48791cedf6f4227c35941ee90e5b14b4a8573ccb14d9b789078491d00	1685172689000000	1685777489000000	1748849489000000	1843457489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x0a3fb6b141684751d6a8096b3e734156fa767206149b18f3a2cc997248d20e096ad63995d58da87147d759b68227c054c4a4801688c439bfd7b0b15e9045235f	1	0	\\x000000010000000000800003e0ba570776054e646fea1121cf83f538be450251d8137c32388fcb32b6923b9fb200a6a8634752c094026f70bf4b47a0f98ad02d1c75defb8080459c3f2be52466503f044412297b249e6c19e47707c30e5a3b721400e001ea0efffa5f90b3bad98bb78f84040e3758c15ec16c5f5a2c3b9ebcba4cd92d932fb834bb6e313883010001	\\xa0af2dcc9e8c754558f492fb9b5ae20e242ef36590ea1f4aa48293d4308f7b2681db3f5e36ed51e5ed54ce3357de186f1968f9ccc293b807183fe6fce1b34c09	1675500689000000	1676105489000000	1739177489000000	1833785489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x0adb523b594bb4f7595e7e769997c377b152456ea5c8ef18fc224ab9a88c9acd4541e490b2f09f6e3f0e16aa594641a36f4c232834561dde903af5dc971772f1	1	0	\\x000000010000000000800003b09064ca3232a06f8cb90a856a99581241e207ffb5a9311d740a2f6c1ee44d2fcf21615162325c99170c796bfb2d3771b79b8d47b84817b4dc5d90b78e250ff8973b081d4017cb21b37388ab71f5394e412685954c758ee80852c062650dd506b0680ef6432abea9980b20e5b100221a0fd03304a4ccf78bb0c977953081329d010001	\\x4d5f1153f128474da30a6e864f43147ac522bdd0e123b1e02ebf2adab4930b89dce5c44d3554b497f1f4e3dd366df966112041842f79e24e4b6c14dd637c9502	1665828689000000	1666433489000000	1729505489000000	1824113489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x14af71ee505ecf88925d96f822f8335ab99917682bb58a72c735510907774a9cccb6b7e147dcd2c4894b8632bf0c9dba44eaa61b54b6cb4457292b2cc2c4bdd4	1	0	\\x000000010000000000800003b7820bc97489869f6ca765bdcf4e2c410c479d6f853a3d74cc7782c04195094e1158107b61b78b0548323c0e45f97716e8209584ab4caa7f96afad89212bee33401c726add85a58bbcf0f2225ca97ab449997c8c7dfbd8526973f0a2e957dde8eba285f45c80d4aee5f15e78b10a2d8a4556b3b6f56c142da3d161333f72efc9010001	\\x0dd84b2a4e37c79fbe069ef3ef2bbf31f7394cd9793a575465322bbdf71fa5351f03d14fec7497cc3017921e1954e1bd58187163b116e1a9b27c105e6475a002	1671873689000000	1672478489000000	1735550489000000	1830158489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x1747aa63192c4c0226ef2bee7013bd7106d8ff94d14d2403f39dfc5cf8f3775bae5fb6f885369694ebc64a6317c4a7b460cb92ac1309e1d8186f8f683fb3ac27	1	0	\\x000000010000000000800003bcedae3cfa31cd22e77a00480b3cc8c9d7c32d5820fd65d7054a457b03f61479fdb1ad93ea05c9d5ab5f1a3f15332e761c9c56ed2a7b31afe187a831a0b80c14ea6c292922b3df5f363cab2cc3943af6f1af69bb5dba309c2fb452e5b09f6874c50bc9ecbe1c1eeebaec0bf117124214a512bc9bd7ff60ec792b8a6f44ae41b5010001	\\xe32c278962e73e39d4224490e4b81ca856d356a4ba0e89a7bdecb91e137676f91ce7a12e2a02553c6804c60c09488af52849a7a82bde8a1d3ecff617b794ca05	1683963689000000	1684568489000000	1747640489000000	1842248489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x17d3192cc351fdf7a82b52e2d575d99e161aea5cc7d3c566c41684717abd94d208abcbc5ca25a8ad5f61c819451ce514c802ca468206d3268933ee776b10284e	1	0	\\x000000010000000000800003e7085835651b79a3e05d38c5d92a8e21daa730bc26303febc9d9db63af35e0da19073f5b437c6dfe010b472c1a1c2f5a5e1b6a51ba676cca2160ec5cbacff085c2584c85e2a99f0a1b4051f994f919df1be905c9e1ac68aa9de936adc8c97602296786e5f849f0d145795c66710535ffbdf9a06f69dbb94bb9a0779dda1c3655010001	\\x6ea6e3dd7dac6d325928472de36443561dae3c37bfb085b49d1bb3854d269789d9747d490958c4f2e2bf311015ec77991fcea8519c7a318b802fefe6b6068801	1661597189000000	1662201989000000	1725273989000000	1819881989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x19732b1274fc939318309cfa988638e630f63b8bf7a48df8c0848be0a1814cbfa3805caa75ced0d30356d95f6e1b0b18c9fbfe7a6b25a0d38bd7b249e2e934c4	1	0	\\x000000010000000000800003a3e88387ba58c2d9d447efd2fb790b8cac2e61e2e1846bcd6c18e34375bad6570ab3b06ad69afc0dd752288072fda3f85ce1a0fa3773b1b29312938912e1e663396a1ffe1be2e8073d8d8686eba48f1367d2207a7fd6312c41886343514751a161de62561ace28cebb9fe6bededc2fb23c4a2eab0d32aaa8c085df04a20d1e15010001	\\xc3f959b36dba049692378d3b942db852e693547d7a4b8123cb69cdb85583a07485aafe4686eeb6363849880a80fbfdb29c83ec7ea133a15e48488ef66b871b04	1667642189000000	1668246989000000	1731318989000000	1825926989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x21e397982ff158ea4a194f3361d7618ef05bdbf4bae3a75afbc7c2e8b27804650f44244e4ae8743d9e4015485f7f09a62117ce3e73af26fdc192d2ffa9164aff	1	0	\\x0000000100000000008000039e95f735db8dfc051729fad2c0e84dcc38345af7764d22bd87547150bef1b6e5807b1fd730ba97d13aa9824e2424b4e1f91269654f1086d2c6fc6fe8919e301c965fcef5fc64d5dfbe72b7da4c6bfea0d7aad5e67e5b258b6bc6754446177b038e0c070ebc421b95aa9e11bb29b174d50b15e5860d4e35ffec5d0f3cd63dd9ab010001	\\x197ed208ecdf4fecb911d0db4710572bf4f1989354e33aa0d9a53554fee63760127e50a4a8cf0d3a268636d2a9fe05acb81a13cfa2766a48b1301a3d4051590e	1676105189000000	1676709989000000	1739781989000000	1834389989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x218b72083c58758c4199ff1c3cd5359ea8694e9c3b00edfd06ed616fee483d85fb322abe848d109fe0c857a2a4a5fd3f41caeb21be423ea85a6728b5cd37f26b	1	0	\\x000000010000000000800003bd54f937f3a680ff2284292c5ec7ac11168db12a7a4a310de7e1420975491b29bc61f0a260c2bbc4679de89e611f9baab34da936b292d589ef21b61e98204304b8603a1ecb2e7d0a401f1b7886d9fd2d99a69100d97a99d0f54e63024293853e6557035ec32191464baa8861e7981cec7eb89b150936a70258187ba1c32b73bd010001	\\x34e8e40fcd9b981ff1352201afc1ac907fb24dcfabc702590f9b3846e66fd347d94868a8f1f7c6bcf30991cbce8384755fa9c03fe2ac6039beb01892bf69fb04	1687590689000000	1688195489000000	1751267489000000	1845875489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
339	\\x22bbf665d98f55cd93971d530f37d2574c0371c09d8d431f3c48a0c17b48c0718a1b9b55bccf59fe021665bc124859ef778d9385f8f7638bf12489fbe0aad2ac	1	0	\\x000000010000000000800003d2f3c7ef1106fd1db90e2947cb33bef36ac1b39bf457cc9b53ab5f604f70771da5b3063475685763460bae5d63e80f70557a8592975a0ab8d5221c1b9674a3d08061c7be9e6c779d6df5f752f4010f76ed8bd58f6518f5fbdd1aad974998e4c6c65575cf99cfdccd7f40fb99b25fda3f10cbdd967ef50e42f03da35075c2a1ad010001	\\x4858c95969e44c8d3bafbb91032649343e28e2017750828385ecc7a46c79526313b8015b5a072ad2e93c69b4a4cec882dec16edf444a25b82ba41a0e0ea6aa0f	1666433189000000	1667037989000000	1730109989000000	1824717989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
340	\\x2427ae81d1563e2988a7f63dc940a50c618b7c85ccb18723858431c4747288d0cb8cad90b5e5b035c6557350b09d4c099f27b5c52165da0a2b921237fb421ebe	1	0	\\x000000010000000000800003bde6b5d5351a215316c1681d031f56ada3f954153f741170169b4c4429f3ba59fd90906e894041d917871c60e3303b03681e5cb95f3887b7ff8e97795dbd6469d93a89400d369bbcf167f6ef1303d7e5c3788aad5251283f610031d5fa46aaa50c6978249b0c728c0314c53510646a8decaec1e39bbdcd97d495439f7f717305010001	\\x62f1b98dfeec9469252c9bc133d55d9dc8e564fa282a546c71359d99f320fc88beaa0ec1d11158f2c4012162723dcef8f22d098f043fedf5117d18904fbee203	1688195189000000	1688799989000000	1751871989000000	1846479989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
341	\\x2aafb8fcd18fe2ef25523912e7368fe65451a1534d04b2f5dd836defbf18d2630409f94ed749b74934c0c0968738475df1f984eb84e46224270741b95009415a	1	0	\\x000000010000000000800003c60b43a431f562f04c7b6f63fe51e51707e732dcd9cc22ced7210572ab230f167aa210dee586ee6b266f876ac3434c3b5ad159b3daa08741b88b4ac97899e062c1c6343654b9b0e0b1fd4b372467ffd097dfe6783f48b5184897ca077b8b92af01962dc27d5d96598e5ca49074a607db39e5352405e97b237ca2d6aca0b563f5010001	\\xbb3252f43aace78864d3abdb499a9e993af7417a0f7bbaa14ecd5d665070b69baf4ae026e7efb9f95cf19589e248a6085627f53d40c8082d953a94b2caa70b0c	1671873689000000	1672478489000000	1735550489000000	1830158489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x2ec329d41d7da343d7184e34ce0cc83228502d69bd94a5ed3954d024cb4f9da195a2bd1fccb1f36bd62b9cc20d9438c2f69a4f5826810ad6f25ff40d7284f9bd	1	0	\\x000000010000000000800003bbdb31dc408da5477e9077755e668655fb51b37a67c6b2daf3b61e1e5b955b7a1b8d804cc89b0281733bc4d532635719525935cf5d81c2129d3e373ddc92064ea6e861041e5dea571e4f083c1511cb3b4e9a2fb7aeb36ae37664161f21943c7ea2a5404443a176135e04557f69930c9d9403eee272a6f6667147ba0ecb75fc2d010001	\\x5bcdd990a8062f043ceea1a44c19a5b85faa884c5524ee2d9c9bc50f3cf5cc3320df80cf5850e6654a62a22788faf7a7bbe414e234f8b12c264c7648b0a8290e	1673687189000000	1674291989000000	1737363989000000	1831971989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x2ee3929587c71b9c5371ae6cadffa0d8fc2fe2aa1656492fb3cc9eaedfb537e895004f17918e7905b8abb7c70dbc8c5f43d144db6bfed5ee889f80db539709a6	1	0	\\x000000010000000000800003d2143d52ea8e788397c7e177cb7da476e37feb4ae39be2c4101a111f2e49917ba66a32c0cb442b0df50ba1b6dd477ed6b490525ecd56a9bcadbe1480f0d7bf9cd901b52c13aa2592bebfc35c9fce3b3afb100d0756e334eb57a7cde6ca1c542109e5093be4823875ab51181d12173c1043287c3003b8ba072ca03c133ecdcd83010001	\\xc5f8a84c3ff8001f3e8d3b2c248982adf471543848821b4aac2f8ad0a980c5d217b7c8946ef691b34308ea641ff0541e648d969b09aa640a0b0b8861491e4c03	1681545689000000	1682150489000000	1745222489000000	1839830489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x33ab747c4c24c7db3b4da252940f4876b647f4c529000e96e21691294d4f57e4d4e681afd091cdb94036cf26f7e56cbd96ceb3d388dff6a40f29617ac47e9d44	1	0	\\x000000010000000000800003c8ac53e0a8f73a89df71489584cc6a13b5356ccc91ce7c2c667d666a943049f69c881199bf52bf411411f8f8f936e8912316d97ab7003414a264153011f500a62de195f0d4490100434602ecddb8a59b5236f0fe4c8cc4ad24eb9d4205c78224f9e728384ae5d533653aa0a8bb25293938f7b682884140094b55fe36a904d565010001	\\x5a221d98748bcb29cb493ae8a754d435828536732afe5698554840aa3958f1098ebe55627d182bc938ac867a7ec8737071898f75f57324fc015bf9d101d2d70f	1691217689000000	1691822489000000	1754894489000000	1849502489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x346baac3da8b4a61c923b6855a7924e393a85ef9c5fdbc5b4e9314dcc2eecba002730a640d398c9fda0a7539203268644587ea76788f114be4b828ed465eae00	1	0	\\x000000010000000000800003d55e2a06596e76b28baa0b304951e0fb49c0ada224b41fa2cb45f3e84d94b689cf6567acf1e41bc545251a5aaeaa2bd543711dbcbafcd7dc19b7fbed4c621ae320f1ad9ccfe20aaf09552ad39f9930759a4f0130e88608ab026bee7202613f9a4f9d3066cea56db760f1ec5051aab001efa28e909b11f5f86d8d3ad564d4bb1f010001	\\xa6d4d7c1ec7f41bc21a2331e19cdc27805c8ad5778d6aaf2f9321b21e5a05ce8b8c2bcd3fe136fb91224ba901e48a6f5b6e776c3c610afcd6d09d0f1f5c31600	1673687189000000	1674291989000000	1737363989000000	1831971989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x352ffe1405ab352c111ae0c3789aa0e397a308eb4443773c93071ce515bf4340e60d229b6e2b6798744cdfd3804dd72bde2ccf6e62f933c6c87b31c49cdfc248	1	0	\\x000000010000000000800003df8adcc1c46275ddcb135359be5aafb650e5f315b252d6e06995fb28fe6b76b6831153dcd582cf0f912ff5fdad442352e9c761dd93e4ed5c6266b388c2ee9cffe94dacee2b3ac6a41de08b945f4cf9205dbb4f7b4f291af4cda3e8d223e09dff3b7856be1c4f4eb36915c12ea2fa3a55bddd34158d39675a03b374865de8a0d5010001	\\x4a1d32f6ec7981d1a891e66de983b080e4d8f3f1a5e45be3da371e99cc4cff061639a20484e52387d94c3072796c334ef087ad6aeb1e89bc7a5e936ad459cb05	1667642189000000	1668246989000000	1731318989000000	1825926989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
347	\\x389f8a19f97a9fa89b5e38e31e45c78ea3b1bcb17476793dfb086eae348035aa058cd6088e1e73444d81ec19f5f8865b9551043036033ee8eb416a5d886baa7a	1	0	\\x000000010000000000800003c7083966f7f99fe69a955b3d3b98fa0c98256a05da0a94a151bb90399437c541d7a95336971a4ab8f4e5ec3ded6eb1608c41c307c467f8c93b47a3ad545ca4d6ff9140bdab1b4bf176a8872242b2cc175eff52403950cfc79f4a14cfe7c7110ab881ae8cdf5617b8cb0977fff24c74e071ab21a2723e5acc5d55a2df5eb0a9b9010001	\\x86e493c289c1636df3f88b41a7997f6e4f6ea46e76ed7ba2a61b6570e5b3437e33885b057107d78f3f24528c2759001b54b2fc14aeab743f016102673ab5d90f	1686381689000000	1686986489000000	1750058489000000	1844666489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x39cf933676a156d319cc2bc51abc5437ee860d80d9cba206ee11597207fa43a085607e648947b816673fdddb660611260fc94aebe9ca61e925db178688af6d2e	1	0	\\x000000010000000000800003aeb7802a83bbc8b9a20a325b68ce16c73e05254bcc7ff09c327c334012d62a4454765646c26bbc3d5f3fe5887820afe02e716484f483383bb4837132fc00c4641c277bd93d7a8b292a31478e3cb961103d8f4ebaf6f329cff311ff9b02d3d0f08228e488ad39357ebf7768c534d6b2c76142b503dab0b271ea23c06cf8c184b7010001	\\x2aa544a6edf2cdf9523e1b5a2e89217184b0688a9244b95802f0ab4ec782ff375bff58dc987e06e22266f16c1a5c83ab83aa09947ba84aa2edccb93c0078090b	1668851189000000	1669455989000000	1732527989000000	1827135989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x3feb50de48b75c2b34c871a14eb9cac0a109635b6c5a90b9b5a0150913372b5f084a50fa50cddc5a8f96a326a5babfbb5703ff0bdf146c971dea42cdaab2fbc1	1	0	\\x0000000100000000008000039881d258caa8950134477e7dd6db253a4aa2cbd5fad078f614ff30674f71f5d1040d3a77dfc4ff93ddb63b1c30e57778e69875be2999830c219abcc90e6872e37f23d1e8037585d05269d48ac6d7eaef6975657c62f8de4f1896a194a56cf5f6734798e20f19e79e9eb7bacf2c109cfc2010872108d2bda55897ebc461d76ba7010001	\\xa0b273a8e14ff08d284242b4eadf7f6a630fc175570de9454954534428506db292568702c50d15fd40e30f5b26dc1e7ab549fac39e3e4b10c3b62877dea1190c	1663410689000000	1664015489000000	1727087489000000	1821695489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
350	\\x428b8c64fe9ce4e7682e9cd1805f5485e0f0e6c205fb16cb60d6d0966ecded3f92667ab0930e95599f9410b074fd8307fd18e1a57d1a40be9e7ea001b2ed9007	1	0	\\x00000001000000000080000392a0ff5de7e6512faad3a9abb2daea9e8a94935e5a70b77a532b8836ded0e5871764c9c5fed1c7a52d95997cca636e505abafb5a1fd7567f30034770ce22eb2a51cabd452ee98a66a4da15576a4561e348bf3e5a983294413dd88fa1a796995cd919a4afaa2260461b7ea1070b5b268bd9772839d041c364678b7e510a02698b010001	\\x811ec40640b0357809584ac8d7a1a37f304dc3e49f87ff82cf88459544494945f9aeb8c2cd789d52d8df4ae0173d03c339bf5f65a8b3cf667a361904c108e508	1682150189000000	1682754989000000	1745826989000000	1840434989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
351	\\x428780e9c1e56815d2648f89cee305edaa528ae31d16664887695abe28c5c1791813ac2bede82e45b375af430068f63683ac7c6c2dc8c46fe1496a90bc637dfb	1	0	\\x000000010000000000800003a7d02d35be810a546ffe20ae42398c9a4f2d456607318189f78e24a53eb65a3e134b4a853a7d18373ad355dc15122349bf3aab31b62e20eb63090d03375e751319ea6e52198829010c3926b208c57cb7a008c06e2c025bb5634418dc9158b2d97edc745dca88d4a4248b75c75f40680786142a00d30d6d0b7f7bbbea98d37cad010001	\\x658b7d7665d3284381cc68d170f1249fc4164537681f21e8f8d9fbf1a1ccbb006381912180530eaaed932024c7737bf8d09297865939ebae6e290a72ac3fd909	1670664689000000	1671269489000000	1734341489000000	1828949489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x48dfd87eb91aa769b3e02b1e360694d202c7cf1dd3a36a3be4c970185c3b214ae295267b35003f6c470c4a8d309da4a651a8bb25e226d1ba685cde6597e2f63c	1	0	\\x000000010000000000800003e11b5326401b5a71174f7e78d33e552dd5d5b5e62b0fdd566f82f8bfb82f2bb92d65e22141739b70a9c4904f606f9e5ddb9f6a44a4db1702d3ebd34a2a3a8b0ee149eae543b8603a60ce555cecf0aeb03bd4eceaf0460da248a3223b305d936579d91a5108e8a6d9da6d094de5476a29ff28445d8e482ebc7738924c8951f239010001	\\xfaa7f82eeae922f93ec78ac2deb36ed84e57c5b8f0d995abefe9eaff16d2226c1e9e9bdee0be511c9e53a284a03e2041ac5e4d02b8c46c8659fc40c529267003	1663410689000000	1664015489000000	1727087489000000	1821695489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x4857de6b966197be5fccd1c776a6d771681083f65d7a9abe51aecfa133ea8e95c5bafa20a3bcf724f7a9424b21bf80b5830ba1f6bbb6696e4bf11afeaadd4eee	1	0	\\x000000010000000000800003b52f3fb1d94e4e5b8bac1ab3c73a8d10c8608a5a44863af1599c1b3d61a4e76b8a869898197b7d31135a32a36ee61248c7c5cfade4da85d6ce60078d86c22157fddaeae33420b9bd3a6d94ff313f4f45688171df44444db774204c2402f6aacb97b5e2100bfceb4cb3492d32d58f350b648300a2d9f6be02e5e678756e532123010001	\\xf1ccd580cd09f00b177a3f9a152dac3d226d39b7acb493df7d470b35a55e035839424b76b6b88e178b34bba92b2b320b76bcdf80d50f09360ac745467384f20d	1670060189000000	1670664989000000	1733736989000000	1828344989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x489b015b46d4f5b0499a717e7e923b28e716a763910fdcb87058644bea6936ae45fa4fe111303fbdb41cd68d4cfc36474f713d480134d56818f043b66e400b69	1	0	\\x000000010000000000800003dc1b85d49d15ddd30a9ecf2dc56e77af42e5019c3ccf0c38c02014fc69e021fce32d9f8afd79681aece22de460a7f68f80ef662bf62bbeba4082a37f7536793a17472cf67e75c1f6dab2766a95d252be18d2a6f2c0756c286c7a55af109ecc4581077ad1cc94acddb6b3aecb0fb14915bd61ef79fac1eaf9a7c670709ebf5471010001	\\x5ca076d4bbb69938f3ff30478b16893851630cef96739e25e66bd4484de531d26048aa1375b16ddff35cb31ba6b3f10477ba2e4803e1a2fda9b0e6cbfa97c601	1663410689000000	1664015489000000	1727087489000000	1821695489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x5503c52d107c4ebba2568d923c46ea0b299668aa504ab79b3c1688482c03b89d5c1893944f6cbe7c1f5ad0aaa7ef2ade8dbf2a3a490bc6d697803dd02ff1e76a	1	0	\\x000000010000000000800003d09bc3ce4e28a54d43cd1b033dec80457070f0719116bd675072d9d0008be8f71c0b25165ffea2d23ba0c8459ef5c051e3a66e57f7af41d16919954ce202ab7f9197e2d96f8edb9eb2671d1ace3610cfb96b17f236d321ce615460214138e0a4fd5e96f281df0162af1f86aeedafbc0d8b9fc1e8384d24bc275b68ac692c86f7010001	\\x6c7c695950dce55ba0a5c998f6f4ca94de271de15e3d5853ba11c9ce6b570fd7cbaaa386dcb444ec73fb8ea59c6cea9fc06da4860ad5ad5f6507d35a86719c07	1664015189000000	1664619989000000	1727691989000000	1822299989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
356	\\x56af6cc5254f3c474c1d7ff328333d422426d1f9355e9c4ca5fdb2ffd9ea9f9960b0f91ae4afe9a380eb44237560a241533eaa877565001668bc26ea7f2cfd2e	1	0	\\x000000010000000000800003b728b9bb9a2a43a18f8b08ba42d8178006625c268e9beacbf6d44eb7d595af0d6d8fdc36008443505559f97f46f16a0704ae5c3571bc4f5d905e1887869cb327312cbddba6b2e225a4eb88f9e40219a5409c2d56ff02a46dc8d01a2f161072e4e23c969dd85b67bfd4fd27ca6c3b74fa3723f361021de7e373995b91c39c3c71010001	\\xf58a18996d54ba9f4dfe3d6a12b1dd33e13263735189f9e3f82cec00f0d1a0146ae6813792758fb25b81cd88e84820412c880de90b42c728440d24345b8f3e0e	1664015189000000	1664619989000000	1727691989000000	1822299989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
357	\\x56b72be982ffcbf43020c0135b7730164beb8918ad7fa49f392fcb18d6305aaa770f3cfef373e1b940068460ef7c754ec1188f4af480b4cc2b0af5f2ee1bea53	1	0	\\x000000010000000000800003c650064b5ead51195e4ae970ca4f93cec3309298068503cf6d9594eefd8376e49847f73dcb00c307abe49f9bc2aa09737711bc97f76ef1c7c5a9c2c9324effb128f69151431ba8854a9dca4dfe4757b3013909f2b96ae221a2d9940e630a510320b845b934eac81f752afeb61fbb5e5e1f1c68a5ab7b7e1d410b3095a2bf84cd010001	\\xcca4b5e91c27ddaa8fc1649cd83eb81602aed6e1144a7e42613ce28c547888c4458ba73e49ca18602f690ef359d98441bdf2f7406184d7ac59e3dd9bbb7cdc09	1677918689000000	1678523489000000	1741595489000000	1836203489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x5717e7572c22df67657ce8d3f2b329bd99ac3a9b761b0a23ae08a0322b26d909ef61030f6509cf58b8fc7e8b121b650e0407c474bc5cbc4f6573b12fdcd933ca	1	0	\\x000000010000000000800003ae4796ca3671578d857467b8ba9847b623bcca61718fd026b5e5fe09f4ca3ff32ee3786d15030362d8be333813029f4ecf874df3c5ddc1ca3127cf930dd500bf5146d330a42764c8a7dae59f29af06c355cd5d0978393c506bc333a493abcb6df7548d87641d03aa80c743f9abaa87ffae6f14864ad1e961aeea3739d33cf6e7010001	\\xaff747b59ff8caf8606665104d8eae81afccc67243f26d783415c6138687df8c8c177f082d9ba7bbc3cf3374189d2e3a3030bb3f6289a2e76e8955a94afc2f0d	1674896189000000	1675500989000000	1738572989000000	1833180989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x575b92fbba5b51894d9d96cb591088ce0397549a1a0cfc0ee06751c9d3c49f2baa5c2d47b389197a64ae7556a8e8d9982f9e50a07bb0199f0c7b19883a443eb7	1	0	\\x000000010000000000800003a308bb99b539a6c6c03b68ede7a85ed73c8562970f8e244bdae94cbbf31c25f2df74dd5b6598de02a28c528f16e64be0567afad283f784a2e05d90b8fd291985406975285d44083ef1539678c775fef0784d589d144842931b5e17d3970881fcb928a6df75d5b49d573bf22defd02864c2ca1f8f90da808798d18ea99f89540d010001	\\xd613a2e4084f53ccf322adc414b04f5313680c42dc29553ae8344ff44cb8d1a5a57e4c2f087acdd5233daa28981eaab3ee2034547d54ad75049d7bca20e1f10d	1664619689000000	1665224489000000	1728296489000000	1822904489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
360	\\x58873023b47ca8e937d49fd064f4d2e3525aa7c3979aa0e5b452983f0c7e38ce4e6b0e5510af67c0a75f7ad1c2ca5ce7f9bbe6a810c7587ce55eb7c665052105	1	0	\\x000000010000000000800003c12941bc41daa83adeb2a79f6a685dfec274a1aa8c9896c774621ab06d18b225cdecd5f6d347416acaa80bc188cb61368d488c818f1985be85a7978813c9771df6971077064de97a04d15f719229eba525002fa837ce4a7794c90e12a9011c1f3f79c509f17549724a417eb7aed5343e4d15125180f7de202c72a9148accc7a5010001	\\x083d21252d06947beafd7721fec95efe8d9a6c0f608c45b09c25664faa8789cc020af17d6708c51e4a467373dd4bdd2a55039f15b51767258e022b828bb18a06	1690008689000000	1690613489000000	1753685489000000	1848293489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
361	\\x5843a6b9375d7467ff684eeeca7de99e3d7faf0596bc2ffc2cc94008228706ae3516d20671b4bb70d0b33983c50c8d1fc539f750da5c52e941a608fc5c48087c	1	0	\\x000000010000000000800003d1080a2e751352002bb7b1c34de155192ec9c6314dcba56c0622341f58cdc15d989ac46d062998c0c14481fa25361990639d92136613f9e299a3963641056e976c295c05fb42b6431d55b27fc476f16d2df7c35a1647820786a508064f07fcf9dff24a8df9703f1aa8faae42739fa4e30b471c227db0c3f85c8fcc422ec887ad010001	\\x64d4fe6279bf78a18b85dab096b53ae7acbaa4e2236d00e732d24d0863f29fffec7de03da0504e8f64bfe6ab9920851e9a1c1ce0bf8d693d03d82d81c987ce07	1665828689000000	1666433489000000	1729505489000000	1824113489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
362	\\x59f390b45b63b4266af3ebebff76fb33d105963c72603dced28aab9301307255aa73307c04eefe513f8ecc5c385f8191a70644657ebc6dd75b5f094e2e6aa170	1	0	\\x000000010000000000800003d3c597a13e11faf5e44c4f5c0628ccb28737ef47e387918080ea92b5ddc19f85929df3aa5fd53d67d40fd615e78b25ddb4f267f7ab0888809459cec6e99f695f8bd624e2fa4829aad8f79af97e94fb3f3c2fa265b7250f5c1e1b9197e3fc0503cd77513885189247c09e462d73ccb77f19ccb3f0d0a4a33824f93f197550a3b5010001	\\x39f7cc7c12709a442a7d0e9960c9e9f52bf6dcf5c4c63bb0fb84fd7983bd46f8174f6a5b5e9d01163f00a088ee34514f725a8443a6aafbfafdaad2cccb799b08	1662806189000000	1663410989000000	1726482989000000	1821090989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x5aaf91c5133d536f5bec43c517d714c365b62384df5279b561c33f1a10fb3db7e0f6bec9e06499c9b3a8daf7bca52d81f06a9b1692812c2fc4f119863fb112fa	1	0	\\x000000010000000000800003ea7e97f6b8d5c0e01034fa14ea8288ba1ca16a6a42ed7b1c72f517adba1de69e3a62bbd883ae165b9894c10c3fa6f8ae331cbc9137c2c1588c8a4cbf3a7c362aa4f162c1d24bd8d08106061ec3e36efbb63e4ae0fdb2c310c1b0a6c211e3506fd0f064333f20052a3a77728f971a72474b5de6c0c53e3adfc061de16cbc8e7d7010001	\\x3d13c1f10917e8a3faca5c9e94c091e12fd68b66d495cc3f60407540ead91bc3f42814f5988f3a3138ce9436a80076231f414eeaf87622a28d2479763340630b	1679732189000000	1680336989000000	1743408989000000	1838016989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x5c633d89626371362ddf7dfd6ac2e97516cef862cb106fb58821a18818008944d3cc9ac1c9c3991c3559ab7741d0cc13a198b0490239bdc97494802a666c2801	1	0	\\x000000010000000000800003c108c58b68aa182a280f2a30b584056ef9ead8038e688f06aba579cfe15ed9389416433e96666313d1d40bfe7a3f05316460edbdf5f28bd2d8c2ec1785f1e15d9c55d9385556efe89a7692d5e53e6a2ad929e549b77777a0aa77ea62703606db16500d9901a4a35ee8ebd10c18ce6104d1e72291b91fd9f19e0f38048e507701010001	\\x3bbce5aab96cfe135bca33883ac0a776e4d006ed79fe7ff5dbd81ca9194b8fea8000d507d4766adff2384276a3d30097db554fe137a11e8ab0124a89b344a602	1671269189000000	1671873989000000	1734945989000000	1829553989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
365	\\x5d2b41e0ba58905fd4cf33532408a8414b2dfefde209505dcf4c253b4f0c621402b58f70ec51910d85793f7c8ef321e472a690bbaefaa9b3284d6fdff1b6bb3d	1	0	\\x000000010000000000800003a8343a52e84d0a4451b6c352a84972446554a3a590e3ff7583bd90815b4149c408c3040693fee5e95327c36c22488beab4085db750278b3094ec5cdd81c540f47052ba3d7c9c7d7cbb83ef1eeda9e056450a9d485c2d02fd4bbf6cfe79c1db5afba5618c9eb9d41b1bdc775fa6feedb4add0318f8b61decd74baf003dfff2bf7010001	\\x81b9ecb75830809b1ae2bc4638647664e326b0c20b6dc6b011c81f985f971271e5275aef72c36c52258d1ec257f885d7a30124953612c0378d0f07d83553e303	1687590689000000	1688195489000000	1751267489000000	1845875489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
366	\\x5d1be08d76d764154ae6254bfe6df87937d85613a1b134d1b8db2c1283e2c87c994e12b4d60ad2ff1ede17f918853e5c434d678e7488bd8a5ba052ad2f9a67e4	1	0	\\x000000010000000000800003da60e93ce6de441280283a06cd6b4d7dcbe62f996e394134f1d4229c7a9476d612c498d888c390b7f3cd625b71a66e81fbffe5e7e679dd8bd0b71c33db677ebc9017c63fa463764cca22e768c074775b084712eab74d39308c0d435107f66037b3ca482f272f9102f55d5f96197508042178a7ec0867fd7d283d2c0711441005010001	\\x2c2f490abb6017d06ad66c5e3a83dd6fdce852aae3f6a8155fc17e5bd81ea32def14965548e2da099f0107bbb3c59c626d028ab442a68ae528546ac9998c4b08	1665828689000000	1666433489000000	1729505489000000	1824113489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x6253935c6da7cab65154813e1d4f8580fca96e13cf0e4efb63602c10730fbeb9333b11230924bfcf19dc99b9de958ee4e91d54d8a82172aca725457db3f670ff	1	0	\\x000000010000000000800003efb9eb5a172b9d16593dc3121f6455378af5a9ce184a32dfa33a32ab0be7ffa264ea35a6aa829d2da90b93c5b6bf7ea04508a5968a962c8000ee8582feff517d688c7106752670cdcae894afc20987ea64693466d036cd749bb71bfd6ee5e2591263926687698e5c846c59e1d2227aa3f34a8d6214dd98d1ea2fe78fde04490f010001	\\xd57a8753caf3d80791d5681944d97dd275fadd6990a9a7729e10f11fb1062b9f5ce8822edd9b1922dfd9adb93359e1636e884cd60e1f24fe36ee08b30709900c	1682150189000000	1682754989000000	1745826989000000	1840434989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x637f22ca800bd70d450177e961aae78a76304563fdde6e6277e6dd59dbf87e65d251b3328a0a1d02ebb150ab21b33a7d36eaa5cc86bbf516c89a326ca4f803e9	1	0	\\x000000010000000000800003a23ab64a131b3e9b6e9db4eeba79429458d3fa9f81283426446927c007055de9eec91d93e87ffa3a58c5f111fe0fc7b92c10e5a1d71a35d098fbd832a8924e162f4ab631be154bbd4b6b0e1b491187e6869bd02463bfffb8c21ac456ae524582d74b0315a3e2d190cb6050330d0d60960d6a4f0691d1f7f91baa93e2f31f6faf010001	\\x9f7e43a9521dac03028751da46ed146716dfd3345f262a4bd7d377bbee0014fbcb67062e088179e5c30f70bc6cfd849005a5c056bdda7cd1e31d877c16dcd40c	1677314189000000	1677918989000000	1740990989000000	1835598989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x6507936adeaaba4e67ec65a982f3a866cbf9eb76e64cff35f344bcf710bbdba79f37fb017586dab0e8d9861c8cca24f3773f1cefd0a4ea678a48e6e524b9523b	1	0	\\x000000010000000000800003c5607f2d86f93b917d2b4daa2615fdc3e8ef004eeec82cfe2d58483ad9d83f47cbafd34b34378ed99da93080a55352a3b6cfeb217a48983436b70cf35e300b2b1c31d93ffe4f0dbdf53add23a9ca4d98cbdb337383d9b5ef9ce918064a7de12ae02f9a2708389dc9f7c50cf8249acace45411dbd5c573a3b63ffc9994c60cbaf010001	\\x33c179bcdbb2b0ca9ce302b9d90b382501710e3c17d0e6fd9ee282bef78e55f072fbe7fb3644d7773a122cfba4e3415ac3f48074f2b6a2e42544378f02e4de04	1671873689000000	1672478489000000	1735550489000000	1830158489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x667343e27762dd683f95eb5ee18f77f4e564aba2a99f78859d60c9183d1fb4c15149ffe9c4e8875ce9be1e8c544c04162840e333cbc283b2d7bab2104ae95d71	1	0	\\x000000010000000000800003c1104ae2359f15083f8c1ac3b4d0fcd932bcce833b3eaddb1c990128767ef54ba9c94442dc1a3280b30b1aa8773e1b70e44eee9aab8f124cd1c380ffeae872b76bc5ed5569e35cced71073cc8aca70189430885ee422d0b1f9c4bc3a36d5ee88482c7d1a2777863c36162bb8659a38f7f659b960ebe433b8f34270b0ef05de83010001	\\x3dfb3d0e308784b717fa5596d6ed366f960a8b973cd52a20899c2d39034baf6ff920f6c911e4d5d889a577f82a9054b77b99d19780c0ead03f00b73b2ea9010e	1664619689000000	1665224489000000	1728296489000000	1822904489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
371	\\x6a13a956701a855c03cbb733d46d38fd98ea88aec2c8eabe7008302849024a0c040abbf0110ac945b750db56734fb9be0c8bec0e78d13dffedde0416360f60d0	1	0	\\x000000010000000000800003bd61d7f188054e499b898ba303b50920dc41045e3368cc0e2bc3ddec6f1d0ef0d2c4be6fce252ee54b8ecfddbd45bcbc086f1cdd7e3e1d764024073937b0d473fcf40a0b7d74536f6f4bd271fd7d682931977b4176f3fc3412d587ac160da5102ad5d3c87c77fff6bb25767d86f4e1824a06c6f230bb669538b68392b80a7fa7010001	\\xcedc559979c7f725961862110a152f5927e8f4518a2442c08a83984347e62e054ce39db2fbcfe714f1122629ea92f3671bcf2c8bbc39bf2e59a0e4d026878900	1678523189000000	1679127989000000	1742199989000000	1836807989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x6d4b76bea97f41a3116e0d61d0300aab79ca1080ae53b2013ada3c26d2e48ac7f4568cbc6861195f098d515a43cf5458d923d03eedd3f5eec9508d63ccedf4a7	1	0	\\x000000010000000000800003c6fb38815efb4efecd3efb42fb820944e4f1eb6a535bba9115b75ae84d0616e295e6e888c6f4cc69bb20ce8faa92bdc69bb62bb62fdb63725bd21d88ade95932fbca84f48bac1aeaecf2ce1105cbc2943b98697bcd734f3c456331851afd086298c1072c1836faecdccdb801fbc9fd3a9d0c02ff0b8caad0139cd3e6cc1bba15010001	\\x79d328f3c9a2305d5c84e43a1ba0a8f6bb6456970bb58d85fee256c055ed6f1e482457e4f8b204f38a0ba6c5b3f9e4df835b534d270dcb54e7e3b7308834b10f	1691217689000000	1691822489000000	1754894489000000	1849502489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
373	\\x7343ac49f87337e8139990159ec5c11e0da11b795528e155c1b4d46f28564942481c966681b106908f70769960dc220b571a74b68bb5e49c6f4498129ab79ce1	1	0	\\x000000010000000000800003c2c913c4f0ba93ef660a95eee9233dbf63ddcb041b4821e3e30593a86313606c25638b2eda383fc4310657eb17bad737ac545498170fb6afd4188873323a8374b90114e39fa1525aed5f50928818e30913b8ec54b6c4fa458955a385e028509e6c7d58c4be318fd03683a939018695274d43fac606c788c6fc4853712d866551010001	\\x5bfc6f0e999407406587e37fcee0ee53e35e15508ab32a4b2b151548e371a191c1bf87a48bf542da8ee4e657c3bab8feb9cc4f0f1e27db1654347bb0d2cf5308	1688799689000000	1689404489000000	1752476489000000	1847084489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x765ff6c6941294a58079fdb0f7553a3d4626e218d0fd680a85faa0986f208b6f73c539d1bcf7d1dd52df813d95ba695e5fabb0efca807291bd0d871dc01cfe15	1	0	\\x000000010000000000800003c64f2076740668032f0bb2a0707f2658be71a5459fe84d173c0e65e094a991640696fc207c1aa179b5143c1af769a70eccf875d7fa043bdd1ed7003299b2aa10eb7c82ed9e1e285bfe48f2a12b02f3bffc2f4472c429c6b1a00fb1de20de13277e8c66719ef468e0baf07818d237aeae53e86a1e04d3e0106e3b68f013315f79010001	\\x079cac0f5c250b3357e96acec211e7053e11cab53ef322691da25df6b19963020e0962a4d41680e07432492f3013571b417bd6aeca93705a773a0b45d708ec05	1671873689000000	1672478489000000	1735550489000000	1830158489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
375	\\x7817803164db7b0506824ae267264fb4d1760cf39f98e16dbf7317a39b2d52883f8813f9f56107fde5a8b558a1f1f0428636b34b79caf47593e371b822adbb8c	1	0	\\x000000010000000000800003d070755211fe6235262cd1c90d933b4271486783bf521c80af73c5ee0aa54828a7d038190ff280ab2c6ad72b90cff12df5dffe144e30cd5b9bc6401795e36075ee2a2b5ee65a6e20ddd359190091b5a05705d30880855d199281f19d0a7507fc6134185cfa66eb1da7a9ab4eef6b65a1d9208a57623c725038404580ebe6f539010001	\\xb35747fa930f562c2f6924a993bde9d0a2a2c1d0a091c14cc7a35260c053a8904a874861f6171b480a3930dee6351f84f862db2abbe2939e8e9fd745d04f5303	1672478189000000	1673082989000000	1736154989000000	1830762989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
376	\\x790bb5d0135c9016d6007bf18d97a215472a4303a077eddc896df8f362e11615263a83e1a3c72b96d22ac966c0c911a88fb07479439f636fb403e471d070ed12	1	0	\\x000000010000000000800003aa074cbf480078bb0eb020f51310acb920ee2ab7b966ecf287903c0a23a92417914d370db4f3742c18c0c9f9641615a5f12f231ed101c93037efc9a5dee0ad10dcbe5462071b52078bc3e74890f24417c64d9d040f558705477db5e910281fd10c74533a9f706f7c33dabf07083c55cf92ec903f2228bfb1adfda3e1082a5f4d010001	\\x7ad689e840eb759ff6f03b566b0f4636bea3f76f3104f98c5721b9abbdce21b0311a38903a1339102c36c6f07de179036e5b4208ef0e9e24a7331a23c9beb907	1674896189000000	1675500989000000	1738572989000000	1833180989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
377	\\x84238a0ab02d44a4a9678b0ffb722d6d5a13bb02cb5b8a85a6165c6d8c9bce972dd195e89d63d95d2907d41e4fb2448cca596ae4c04121c13eb4c38164604a14	1	0	\\x000000010000000000800003dcf98d0f6c20efcf51bc027b0a2b2447f54c89058186c5061b6cb8e40d98536b8896d4fafe2719c172463ca1e4c83e7607ad4af136f8503891659407fad00bf444b6b840993a301bd90ff83625d90abfd6648541a8fb0822e2e0bd97b0946d32f60981243a4f1a78dbeaa1a28156af562e4accf92e43a072c54a2a5329f85f95010001	\\xefc5b1a6a58f012a56ca5dcdc336de8a2c3c39ee94ef4ac59a8cdf25da6a82d367ba0b005d59e50e103a8dbd2750f5ad8ff11c44d684825f4b0e30ea2424b003	1671873689000000	1672478489000000	1735550489000000	1830158489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x855b4f37930b01b5cc76b6070c3a9929d8e3135cf5aa75c7518c6c9814d0d31b5b3e97248a752c6486fff1f98572fa8422a94700342ffeb7a32ecc5bc837055f	1	0	\\x000000010000000000800003e3b6f43c5c9de6f5af3433e931d164b2221bc8bca99f28b991646d9f20822463d5a89175c3020e5637664647a44aa4c9f78567762f8dab1c15f77d6758568a6f4901724a441cc590467d931811eb4c66887d31f5ceac6ef56bbb059f0e3aa27a115c357068d75a439c4c259a44b4774b752e2db26b1a3bce55e01039705185fd010001	\\x32d9d4c0341cab97cd953e1ee5207e8e883ea5b6332875cbbeb3967aa0bc28da246b9e08b6234ef5ef18e0d2586ab891d5b29f294829c1a8b952fe63267b1a06	1666433189000000	1667037989000000	1730109989000000	1824717989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x88ebf12430b93afd603321394142ca3dd11604e0b963d77c279235b785c7aa75ec7c418b99f35ece2da0cd40d8f1b9284dc6c8e60dd3729256496ada3194f9b2	1	0	\\x000000010000000000800003af1c543444f36530412e2ddff6a4419f306828e43ea2e4669ef8681786c0d3e9c461605767bb4714c96f2e3e973e292fb0638779e847649c8c208e78d83c0fcc52bfe3a8c39b74af981d6923fc0f461a0b8c3a78506522f56980860a1c3979f61866fd720dc9dd2de2eb496102ff57b89ecfe003bbd03f88bda430f45e520703010001	\\xb908cc0586f1d9ed1c9e1b6a0de6ea3498fab2075b3c1f4d28aa4f260db726c9e62755631f7935e7728991fed3d70fc6a29fad90b7b7606010638844b7b60e0d	1679732189000000	1680336989000000	1743408989000000	1838016989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\x8a07c79f738f7e4ca6f51f7300b0f0c6d6f6c23c9369f397548e22efa62fd68fe44757f858208e670a3440d8e45e89c2712f02bcb4d25a201ebb3b70759af58b	1	0	\\x000000010000000000800003e2aca4643604fc98e5aafb548d6a36a936c18454521ffbe135cfe09857c0e497a519e2ec690a32ede8c8c5821aa7f4f7ccd63e6cee92863aba62e30596f420e9b1fc103ce33183030728dee492cc33b4cd6b702aff6c3da2adc286b3fb1fef4b0ed38ec0ea2492fd2648b8356d9184bcb38076861ab673d7b6df584e0ab2e991010001	\\x4d94ceff320842aff79b6787312621ba8a73ff6062c2e5dabe3b8a53eb7eaca3ca3fd481967a136c297c26a8cf55f791e15e6e9bfbd8b4ca32906a28d10c3701	1665224189000000	1665828989000000	1728900989000000	1823508989000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x8b036c00380731bfc0c88274cee7e72107a2106d0a716acf05e36199c1f6fd22aea6e4daa655add3a9876a9646685d124d7f1eaa4da353b1234efaff0865fa53	1	0	\\x000000010000000000800003a95fda1baa7faeabad10eab0aaf993cc3c63297f487f223087b13ec70a34e6ddbbfd4e9c8ff95a12c5c8671b1a1ea9c666aab5b1bdac54d1eecfdfee949b29d969f9a57f1631405d19c4ea6cc9405ee2c2588aa1b3c94c8fe6097749fe62316aace69d375a7f0e7b67d46e22709d45e3f98a19dd4b9e1f73d84b2acfcff08dd3010001	\\x5b6e1c5b34cc00f7a57502a62c4e16bded99d68ea862e6534d8325a50d7e27cd7d5de6f69231ce097a105b817451ebaaff1fa0f7fcaa3cf35a41124e8b3f2408	1681545689000000	1682150489000000	1745222489000000	1839830489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x8b33e652e5286155caa78df6f99cfed7c88d72d71435bee5cb965df56990700aff87d5f301eb466920de8df62950b106c633ad9f400145595163da2961a3ca2b	1	0	\\x000000010000000000800003af47eea5362ae19d4f91a4c1c4257a1574482c8bd9be400595c0b77f51c56304d479c111979fd189e53dc2326a6555cbb6cbd448f040da3ef833ef23fc5d0294dd3e068c25edd61640f2293517e03dd7ba5e561bd456d2d8616f439e53fda6ddd9f1f7501a5dffb0f2e184cd1ae8b6e4a39bfc780e5724a606505cff9f5dde4b010001	\\x746ce41f7521a03870f143f689aefbfc208d0f4306a17c1e6fb2e62529d7cbf5872fb91bdfa4d7c12ca48794a607720d0fe48df76a251976e63f9df2ea424507	1680941189000000	1681545989000000	1744617989000000	1839225989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\x8b673c30b35f68c6a4c407ed48dddb940bda2b84e6abfe991f703d43bc04be3ab00737883d8ed8ba1849fb8fcb35f93a47b991be99cca6f7bf83d88d40ca4319	1	0	\\x000000010000000000800003a1a1c28f438e2b96257c7d4010160b7359819d4e6f373790eb926efdabd8e23ea5fdfe51efb82f5d57f8a7f3c2a3fb598863f0ea16e44de86c196d047da4094c8e6adb5fafe8482471db24a2045261d42cf0d0b911693ee148aa87f8ab5b0fe57222a307631f1cf0f6b7fff0f3fab152a7b8ec25091111f657595ce3f3ec94bb010001	\\xad2bde775f4e03399724babe5924c284d9db9b5cb6a6a3700952c8b9044492b8da952c70026d462503dcacafe3db1616076d46c714eff42f1b84edd3aea94200	1688195189000000	1688799989000000	1751871989000000	1846479989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\x8bb3ca9bca30cdd99ca923b0eebba9c9ad8cb616d34b5e4583a3c0f4ff61cdc63f9b3a866975185ad6290b1d3050be1970db6fe9c528c7d63f3f15119b336d38	1	0	\\x000000010000000000800003dfbfdc0d1754087165df076efdcf8271dad6d777d923fdc28ed1be99f7cbdac096b0bffad1def862638569ecc2eeed586733eddfa5a679f7fa692b90295ace26819f8c95fb13e50b9d7dea8c76328d15be17d043d8a9be7f5afaa4180bf59da3f46e33e428412d5e903f8d4ca4f3ce7921af93a49c8c7a25941bee9872ad7a01010001	\\xdf29d228bcc526d3071ebf570443112ad66c38d608fc38b41a3205333bc2d702994c9a0034edc3f4c4597792cbe6b569ac3b1d0c6658b8e135ef6c276b3ea903	1679127689000000	1679732489000000	1742804489000000	1837412489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\x8db3465b2af9aaffdbe50d07cf13e32c515045810eedffd9a6f9eb11487f95098144bec84eb1b98e432df720d0aeba81c368e05384ee731ae6015be25063e207	1	0	\\x000000010000000000800003d6e0844c9c0f1c14a1228c9283b0e3e8baf0dc814c3631b48c06e67da95c8b4232d199fda43dbede71d97f7a374c18e3ac7c0ff0d830f9dfaae672dd1925b103f9295e5fec960cdb4e2a616259e8462f66b3ebb9fce482ef2651dbb414b03d1cbb2ad5c895b8aa9774fe82a6cb5ad7699ae01aad9d05db569696715da61633fb010001	\\x2da13e9d6e04919f984525652bb01ae228774eb0e58322631f8437d2bed8f7b8023278d4ec9b0751e8c21486a46f64711c453b35132f4b5792df2d5369c85c0b	1687590689000000	1688195489000000	1751267489000000	1845875489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\x8f0b2a9201081183cbc455099617f57ce035b4cbb74d451546a61b86e17d2016e046d2203d2a18857dba58b51af84568c36bd4e8f92679b0cb6e8bed57191581	1	0	\\x000000010000000000800003afad7b8566f22a76e25aad6738caa79d68efae310e01b73955b1455995012725d904c386295f6896bc0a7835c8ef5e4ac34b13ff5538ca8fcd9a135c0158f275113f5541d6f6a025fecdf50a07e33673293918f617d57d74e16892c6dc3b04171b03ac1354be4a0b94464f6598c2669a746b9c5d7e8b517b754ea65bbd5a7b2d010001	\\x1d4fe07e12a2a41d138d6c9a825d33b8c2b48a57db84b3cf0e5e9a32fce4c7e6d99afc6488edde7959158f273b6c0b2dc2bb8c3e4d79dd2ba5693862039e0b04	1677314189000000	1677918989000000	1740990989000000	1835598989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x8fcf4694fc2d5f76fb10f454f2ebd5fb799a7661a15a650da91d30bf877a7bc94f3e4f9eba285126dbcf8dca5de23f85f222462d10cfd2b82cfc96dad0e2a5ce	1	0	\\x000000010000000000800003d1eda1cfcc5ff24363de1b2def8d66c3dfefe3b7096feb6bbea687c4f11ea1e0ea1d053a297ded931d4e4ff261d8530b18872d5d6c10040d1ad125b2394c547ef94bf0f150a765ecc90471de8a0693b9b69df70246f5edd12f7b787c0a95ad6bcea29de4ceaf59821f1ae0be19b27cba0b5361c4bd0e030889c48a55dc7e60eb010001	\\x003d8db903f1fcd1cd45d5be6da821d61cd2ad6345ee75b61ce82a21e8fc2e0c75421fe8922f51f122dca4813580581b4a2eddeee3bbd04079edcdb87fbdb80e	1686986189000000	1687590989000000	1750662989000000	1845270989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x90f306144235cbe09c502b28f1ac4d1094c14a15de74b31431cf61e57c56ef09d2216e18296b9d298f8784366c72f7a77b50de06b79b56e86d293ec22a8981ca	1	0	\\x000000010000000000800003d056709199083af0f5dfd514f8ced92bebc305ce7f82d5fec64a21c279148a37b12f58deb42aef462995db5b1d5fd07102984d8eaf9c4b86ff39789065845c67a63c571c025ac0cd71db0c131e8b1c4ece3cd1a67a4a8ff523867f0a80253a150c930a48a935d799a2905ed6f91af57da8643809243603b5a8d997a282eac445010001	\\x3b36145e32274cde321b81c6e3f35fbc58fe22ff9508fba932857798d8054c74bff2080c431858e1b4291de6cbae07c63693c806a7135e618568ecd9f50a9a05	1685777189000000	1686381989000000	1749453989000000	1844061989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\x9423d501e27f2bca51435227e319fc1fafc485e1bf26f635c5eed48f41bd8c319a54b65069ea47e69fee338043ed4d4c0bb5411d2b8db7eb12a2592ed6611758	1	0	\\x000000010000000000800003dfbc76b5f03568e00505d3216e6a4fd40053bb6507310bc4891d9f00b305e7724fb08783d0ad6c0c8b32e9f241e044b40f38764123eed60b03b4b2749cf1bed242438827c42514dba6cf5111619bc769539af428fa2c087c7699b8854068cdd6eaf06a858ac3bdd9a7aba195b7a59991911cad86a6e6d628fbab38f0d32d8791010001	\\x92d519152ac867940da1a8a0befb6963bcfb4fa6c5c74d048440430571a3d2bedab7f9ae9e595f81b20f51e6b10e0b2bc9fc76fefa1b69163b4da6ede628650a	1677918689000000	1678523489000000	1741595489000000	1836203489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
390	\\x9e576581b4fbc34ef0bcc283a943dc0a5bec36da33eaca4568c2ea089c389abee22ca055827eee9bef0cf78282606de31a1f29799d17579ffca6205c6bcba537	1	0	\\x000000010000000000800003b487db184ed37cb49fd6c0747dafa54878c4ac64fa36b4fdc74f38b361e143620c04b05ead9d18e05a6f669fd94a5a4b7cf8e6a782038768a8ac2cf85d06ce1c0c3db0baf3ab8748b8cec2eab281c71ce494053f2351e4c30a12b92a3b8f35be392482d8d69c633a8b4159fa006ffae701e3c8e78f17f46188fa408db2bef4c3010001	\\xc8ca7aa45b078e44af603d6117bc839f4955226f69c17fc95579f8b93dac73bb123ec51d722c94ba289d6f88670dece531f57861b4c33918cc85bbcd79343f02	1674896189000000	1675500989000000	1738572989000000	1833180989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
391	\\xa25b2fde9d321fb9ecd1d5d342775c4bc1cbad387f5900b100a4c0d3b19e288e96f0f009f0b5b89bb7197b065f42c9c1e224b48cbf4a52b6ff671bc09bad8536	1	0	\\x000000010000000000800003a39a9d6121f16f19f65d91b249e730c0953cdce301cc81df0257bb185711295de51f6cc7654aa70ee7725d5f9a4ad8e4d63ec363fc0834ec10d059ec4e1e5f5331b10c462196e66df9e0da9f1e3a86aac96640e12904b5a36d782a029e60285ce739adaac02828ef115095d9cfbb649582b06b8571b5a6c64cc4395c05f95b9f010001	\\x84a44b864418c19117e47b1bb7a8cb937ab5a256bb5a6eba6005bf511df97fd51fc4dd46b82af7870c48448e14ac80fdc17ad06f4739e617d1b48691824ca706	1677314189000000	1677918989000000	1740990989000000	1835598989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
392	\\xa4d71ae6bd687f31bc83d6f40a5ed3490a84aff745bc251382bceb4291a3634ae7a50fc487f9d10ed2fb7786e04945a9fc09a67b4ac940a452ab2471a311fda1	1	0	\\x000000010000000000800003b191efb4f45c437561efaa31b4367a70ace48b8b8bcba56d36c75d3bb54378bb67148840cdd01250c3b42ea984d42d098f9c97c8dde507b2fe7167a95559702dbc91915d0a742b4a313884558353035fb0029cf9e0b243bb3ece73f3a4a357d528195b526529e1427e2d3e00a267e22d50c933b5826ab2555d69eeeca36d7e91010001	\\x1c3b502b7cf90eab561c98b9179da22a4a5335efbe29f8db15ac35cb8ba908379a91e82e629c972069565c24603c848bf4bf0cf740c7a8894b0909e9b3c4dc06	1676709689000000	1677314489000000	1740386489000000	1834994489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xa88beda5831b347433ee341ac64f84441620e381ca0d75b041ee245b8388ca99af8d883f47b504e234885340bbeedb9821b2e515a034d87759f4b5796be4833c	1	0	\\x000000010000000000800003dd793895c47704da331e0708fd40ef0d814b7f447f71b5e1ae0cc86abe137d90e4b7fda97a3d7b0596d857559e76b66fc7a907bb69d170b3ba883077d45f47ffa3ea8b09dbc20d80a7b25315c3214075ffa85eaee17d17faaa02352847cb25456b0f4875865d0501bd5b6f9fb694f05c084e57e0f769e8cb37485012d89d5bc1010001	\\x67b50e357c3d76a827e8dc903efec37f1e589abb077885a17d1bd4c556d8f3aace8a755114912daa7eed725262bf5c1f293f9fe99a656fec3ac5b99e7156d606	1660992689000000	1661597489000000	1724669489000000	1819277489000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xa91bd139e504173279061f7b0a301b9b0a2b323a8e6b383d5632f4f13621c069f55066480cad04e42e973a323761e0a278cbb1b8273bb7be8fbe4c9c31a904b3	1	0	\\x000000010000000000800003e25851b28e5d16c881044d32849f66d132e32a9043e6009e573e969a34ceadeab0ca4878653c71ec16344b1530d6ab0c0e8450f5808c3ec0ed506b0b588e724e5107ed84d344a519125475b7be23da668352ce1c96f70cc91b695dc9ac14dd6d3f38a3d6e49c09f213e1ced3ad9c9b8660f9bbf132bcccf1a5ab727d3ea191c9010001	\\xdaae9decbdf92f14a531ba822263cf84dae3ab28d169a703fba082074abfd8e1dd8c3984997186ce06a5ff8768b77e83142ad67fa78e855bb619c6e19bf4c30f	1682150189000000	1682754989000000	1745826989000000	1840434989000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
395	\\xb2a3648b57b943b1275632da6c43f0de6a577546591b3ffe5459a9cb59f6fb7c5d78e35fced80246f727abfcd054fa8b395dde64a23983fe9b209c6c6c57f941	1	0	\\x000000010000000000800003e38e4edc3343d7c13d8f2c681333341ced5846ff2f9eb2eb5bae837dfdfdedb23a918ed809fa4d662e6fd93587f928ad9077bcfe13519f7838271c1bb9fcfe01f6274fc625b9a34356b2e441f5a49a476e17484a442c0b0765ade9e788c65fc499ff5eaf80ecaa60dab97f4a758622bc7d57141ea52b6f64f5449cb963732d07010001	\\x5829fd2f62908c4f244fe0280455ff5e7e783a8f3b4eca99430bbd52a9ab28e095cb19798eed709d9f8daaaf2e6053e8b46c7ebddf320d3a4fb65fdf38bc4703	1670664689000000	1671269489000000	1734341489000000	1828949489000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
396	\\xb37bb1b95763425713de84bb82bea92d7790f67f976a34dd14042863ad9b36ed5313fc61ec2722cd935cd31e5d61f4d6c3c1718dcfccc174d4c2d26671c53338	1	0	\\x000000010000000000800003bdca2e815738b59cec02fd9e353516b94a8613469ed8c6af3b627e2e0a1ce609a1e1a9011c12eae6ab1fe9c13e57a05aaf8ee76aaa94e3c9ad8d765c42451f0f1a8c2d89fc97433204ca4944c959adc5d3518b66261a3ad18471bc113d490fdd8f79b55a566eef03b6310b94787a668db8468b51b6d9d9c433525e0eaa017b7d010001	\\x6e1df6d9be582a63be4a607d94d53ba8d6127f79c07e8bba05e38a6686661836973957cbec1e6725e4582132f7cc6652b19a34abd71a750add3b3571e330c40e	1692426689000000	1693031489000000	1756103489000000	1850711489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xb76721d2b78cd71074b8e8373f0f85b6018bcc768fcbdba8bce98dfa66a8ea869e0b97121763eaffad70aa32ce52d00a85a9daeeab95893ccbc1a90408f36dc7	1	0	\\x000000010000000000800003ecb5fb88900a8ab710ba096adf124b9c2d90c40d6a382d63d93b5544e63f972fb3afbf768ac3df9bc4d4c02bc68fe95a32093c0e3ef8bc0fe029255ca4fcc5fe16fb72b84a8d5aa9bc01336d1437f7541c18dc5ea6b85ca7ae676b89b6ea64040e7a7755ef8fad566d58837b6970521af8e8fbd39ac1947fe26efa2143f3053d010001	\\xe77439c5c4cdcae6d4ac8dabae50c3cfdf0c05a428e2bd13f47c7d13ddadf7f5c28265945428c439ca002471261d317ecb0a33dda96cc18bece18ee14fa29d0a	1662806189000000	1663410989000000	1726482989000000	1821090989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xb8f7a8f479f2de9c21d2ddc725837502dfdd0d522118b5fc31be243f1cda869144397a88d99dca275172e5ccbb1079327f2b878a06818f7216f1e4fe7c78e7bb	1	0	\\x000000010000000000800003b7e937d989a573f5b0521bfe55ea9e30e4e1cbfe5030fad21fff10389e73aa847384c3343f3fe4fecd907b51b94c1da950dc817ada2f4cce15af6690b3e23b4dcc0bc5ea9399a4fd654ac70953f27c7002174f91eef806750a3caffa9df4144915990fecf778cf2d225969fafa0a0d989c6ec0da71f20967811056dbee4167db010001	\\xa0f53f2fdac4911101687e58d54cb7dfceda039a3bf0a145d51af98b06cb7722f5b61f39759fbe5b49643e5f39e6dcfa70ee1454152a232b79a9df7f94e95d04	1671873689000000	1672478489000000	1735550489000000	1830158489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xba531a979ae4991fd4fde93af00f92f145477a62033cb3a99c57dca6d58d1601b725d0f8fda1d31f3e056913452140c9cf18c1ddf0fb57a7b466175679264573	1	0	\\x000000010000000000800003b426a0f1c8b4ad718e81d5e4a3dc5b4da021ee9eaed1bad0171123e85646601b936c689420f9558db63690fa06f997cc7ebe6a5fb7f1b1f4af84df5e482c16587badef5744e3ef1c88b56546012229953f85879e9673897ff45682a3963a22cbe9ccc0afd90642d8e07920995a1cf0d8bbc622048907bcdc259970c6f5ca95ad010001	\\x15b5a6bae0f74220356601da5661d7b69a8cafed01f40a00ab86caf87930d40e65213a8bef757f6e3e52166c5732f0fcbf36c871522e16d613a373b98b51e901	1668246689000000	1668851489000000	1731923489000000	1826531489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xbaeb747a194330cc0e0d5da97a20bb150f25757d0dded870916cfe11dae65529fba9fb52864b01244900c59757a963cba0784cf19796509b33fe359c01e12fb2	1	0	\\x000000010000000000800003bcd5829b324f58ac933d7edc4f79d184c554548e84f3f500dba9e7cbccd30e7e72d0b41f3eef81a90dfd9747ddc6ae82353c14a23890e5b0bbc799cf3eb68e733f9672403c1906677255af804dd3cd7cf180ee0ae8957d7655ab89dc3bd9f3833f7539f43673da3320b88247f647495ba28bb549f625bf2183c4ea57dcd48b93010001	\\xb6de96237221f8524cbb37b6c0a95775e302ccfc233717f21db223594a7bad991a27c72c935f9b7ef96084791b4f5e205fd911fc351dd594702c47d1bb96200b	1665224189000000	1665828989000000	1728900989000000	1823508989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xbce773e26e8b0cb2c31154343cf9364d963143e5efb92698b3c391cfee06430b2ebd2e678dbf6a04ad2efe19b164e45c9954284ea250c8f808e2819d98e07dfd	1	0	\\x000000010000000000800003ce3f6a1e5a5354bb85c711e13b0810b5abc7b29f10f3e553eb42e184d66dcbefb3975f00f2edb795f90709877d7c9b4ef3f659693be6e3cbd2b386a1da66e6e82f28faf61074b92e0ed2394716507051400f98100f318c4ca5aeacb549914dc39cfb14d9cfdf0f4b4b46938c57b64aa17cbf02ae3d4d0d42cc3c4c7e79b35439010001	\\x17b42ca5ef9bd7fc13ffdd09c6dbe8d46e5fe123e9c7897a831805b2a58e6ab0e9b80d62ec51e0fcf91d2a5946f1d99627c7a32802d8e0a560315aa76b8a700d	1690008689000000	1690613489000000	1753685489000000	1848293489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
402	\\xbeef3fd95b6d0d5369bf4677678b8145d17db97914c75af9c2aa276d2517bfbd4021ef16ea04553893ab047207abad83a0f61fa6db533bc064652f9c1e748ff5	1	0	\\x000000010000000000800003e9b1ef54c5ab7b3c0d576708dd2a8201003fb161ab29e8e2edac2f41315549126b044c6af9491df4e227ed900d1668b527868de771483bbec93a27f230a6172519abbf42c3184fe4e2076b5d0e51749f33fda10e7f89bf22929254025352226db61d456d121cd177a8ad4abb25d86e12f69813fc7b70fdd17089df235e48aff7010001	\\x460f353d5d3505457a97a7927aa7fe7d55ce33ca8c4fe36af55e9a626666c96c2e5f205fdc23d360387a428ccd90682ab2beec115a8a844c055ddc0ac1b5a603	1690008689000000	1690613489000000	1753685489000000	1848293489000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
403	\\xc46b1b79ca2bc62db7ffacf9e6b77a45e1b1d3afb616508200c36f21b76d7ba3afb668dd832e797fd50193b479436def8eaaf7e5f2c71d517b737859d23ac93e	1	0	\\x000000010000000000800003ab9f6c28ac7e238bf8eb911c48769866a1682c9ce3b34ff759b169c3976c76ee53323015ca8e33cfe6d1b558f677d50c0b0a276504acf71f1b4639676feb9b70927684d15f5c8a7309e482985955298134ca5178c883cbe5f264060d0f9c973d693586ba02ff6a9ff11fe25a5dc344d00e646935466407f720ece0227e8487cf010001	\\x8170c07895a79e1dbec9b509d7fced183ce5f82727ecc8d6fb1d41c7556cb716a8b04b0d47718fcbde6a6b2e42b07525c00dad2a6bca47c98a6d6a49ae965b08	1676105189000000	1676709989000000	1739781989000000	1834389989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
404	\\xc9d303bc62d5809f1168d6fbf5102b610232b5fa03c5bbb337cafaa06cbbbe132703e65ea976b5097b26d350dbc0ef92e6151c0438508840a3e690cd50319d2e	1	0	\\x000000010000000000800003e57f53635958238a6c76ce321927c699cec24276f4a6093332d7f29936deb2285609a8496290a24925ec974165c6fe1e816de39d2f79d69ed1ae8c83c87f5af75c46446dba364c84b94a379b60f4546c611f44b51898c0b6647471a8c816bda10a642d9cdd984c358267c6fec60a575ca6f94188c97e989445975cd305c36697010001	\\x44b8744111dd7bb1edc49caf72fb9df2b443d422ce1c647d40a654a1ce9a6e62236166bb9a55b1e0daa5cb65e3fa641582da0fa04d38138d0a9c3e69900b480d	1674896189000000	1675500989000000	1738572989000000	1833180989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xcd9f084f52cf8f2d57be8cd83052cc9074329890a8f140a7fd0e1f8d64b55d91dcd6202c92b9b092c92a960829d0d151fb9683681cf69b73d0bc0c855ab54178	1	0	\\x000000010000000000800003c723bd54a3740bf71ee6e7ff7fa561ab2b4787e51a34df0c4bdb046f0061eb30239d41320609a8a88fae51c9a59d38cfa81b52a1f553b09ab4bf6d6e6de0d035d7f3b5bfdafe8f39bbacff9c450673524e9c28088e8dcb9be9bf930cadad2ce89d5411f4ebd2a525ff836f3eff88ad69b35d40186800d2b849c4fca7e6893b59010001	\\x9fbcb77e3a4d72247fba760d023a441c72c6e87afcbf092cc2da63a753716d082b457f1b7706217a7cefd4fc5f0aa3aea0d5db031826297d1c5440c193637d08	1677918689000000	1678523489000000	1741595489000000	1836203489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xcf6bf04b668b782dc9e3fa2b1bddc0632d61336472cbba5c6d94d65cd1d7290e911cbb988d5f66286eb94f6427d7573853a9f9800acfbea65e27a062699ff1e9	1	0	\\x000000010000000000800003e4179e53d0ffa5fc8ecb8e1f4b2ac6cd0af487fa808688f714a08c9bcdb95cdddf80c3809801226c28af5d15766dc07848132e991ae0c526e5e85984038e66c991aaacb8f4f3311222a5632ab6e82afdf8d0450ede04febd76d58e3571da341eee9b522b8f9836fc24f75288eb48b6bb9aa299135c7caa527f88dcb993ce26df010001	\\xa9c5af9258a7fe346d5f76177879e33f3464bcea520ee3c02e21c5536fda0d5a4d279d13c9b0249a9f923934cdd72f7ff67f4d78c2e215d73a77ef5cd0763d0d	1664619689000000	1665224489000000	1728296489000000	1822904489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xd02b02f0de1cfa82a014a79f64c49e8a9bf053a8436be5ef7ff20dc6a715a38e9694488c2cc7758607f0dab5456fb7f8a40030ea9ef37dec35cbcf582418dc48	1	0	\\x000000010000000000800003bd9f1b996f2eaf6e26d32f1326b469691f0f4f42ca99b9b1a20d456519418ae0c162acd340a0aa025fe7087f17362cc18f652e61025c6e1a54eb773d8f354ae279b7c42e1b2246d85ddfa5662998098d4c1d09fd84b3a021cf0f41bd80ceb71e8f421d071e939ee823615efcb97c3c47237d3951d3863f07d06bb5f0dbdcdae3010001	\\x8f7f82ff5ae6088309d2e899c45be4b982032780e1c7be9c974fd73915a95a376971327bb517df5d035ac1fa707ecaabb41d2af3724cf70be869bce52dc9d505	1670060189000000	1670664989000000	1733736989000000	1828344989000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xd343d7cdddf5a762e7a783e5061ca662cd2aa8adc6d6899ed8e20b8912c5580b15e39343e6468193da17b83e8f1003bfb1065c296b125e529db9f4d74bc85f74	1	0	\\x000000010000000000800003dffbf347787ee10db44ab1ecd3d880a428bd28ad3a703fe5b56130dcdbb2811f5703a94f3d145a9b872c971e076d62522a3ea0b6b7b26db7bdfea10a5295c262fd2e14e0b24c6a8d0d967599ed72340370aafaeeb51d6b9d77832a4d573a427a996133a5d3645e714cd273e5aef52ab6ca3a343156807d85f512eb5f895761c1010001	\\xe05ae1bce7aea630c500da8c8fd48a68e20f88d8999f604e89cb97519b7e30a9ad7687d54e349d2795b377f42d57119db983bcfd1fe3843858740bf5158acc0d	1670060189000000	1670664989000000	1733736989000000	1828344989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
409	\\xd8ffa4f7eebb44c051546e80b99e7572f500a4127c17fa5a1956eeb652a72ee69d06052e2ecc0e17458f1b3b0d16b38e79bab53f57e1fb61d0a6c98d3804bf32	1	0	\\x000000010000000000800003baf278deb10096efc982446d802b9b945b34a45099657245e22b5162235c9ffd201be8a1b4cd7a3bbe8ceb79876530b9d73fe3ca0b5b509971e1058a53995a44bb6aa2d5d0a843ac2ba025fdad1e33e1c1197f575fe3060efbe4d4b31b45ac0095ef3b02b15291c34134abe7c2a4a3c05adf1280c99f70fcc787af28a685937b010001	\\x5673351fa5c43a067d14d4fee8f186c591ed594b2e4816d6c6fcf75f7ea0b5a0c8984aaab1da96ed0653c2c8533c6e1abd1037897b26d389c9dd3eed5b728100	1676709689000000	1677314489000000	1740386489000000	1834994489000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xda3bebfa9b45bbc0dd0eb9099d05a1635533ed77d099dbc8709ddccd81a8f267e5087cd166093e883ddaf048a22ca5374260446dab704ad5dcc1036ecfbcdf38	1	0	\\x000000010000000000800003b0803398dfdfae2d48cbcc735c89c753b658d46dbdeaef6254901de5d66f7e2c6f09edb4723a04e436184cf11fcc7e048e7cbd9e431fcf541eb20118739958464e7cd125555f646aa81f4f1c47447d0a73ca02e69bb0694918d8cdcc189d82c853df660339dc50bb77f95f35cd57587068a5a6373a6b4f07a255d2f748f4d3c3010001	\\x2fc0ee147ba830723a3c600ff479320e967fc18dbeeac7ae1da13ad733541afd6a3f685616bbdd3c24bf960a9300aad1e133a5913de46bd0739cf414bdaa800e	1689404189000000	1690008989000000	1753080989000000	1847688989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xe25fdbe80bd3c07a5b85e7edae6ca9eceedf33bb7077d89a07a1d5ed1e787a8979fe5e2149caf4e8610c3cd51b7b94bc524e03b8abcafb24c1d1737e69f7a23e	1	0	\\x0000000100000000008000039b79f225fe48ccf36d02b00d3c85d86d99a0157672993a9d72f40bb092c5703a2d357b4f5f2511dfd568cfb3d75aea3b0584f99788ef7e02f29af4745494b6bd2515dda2162ac173abc89eef7aa4c22819fa6fe94cca01822c09635d73ffbe322ee4f8697b7830d2f5cd11773ae38583de2c6848a11de947899134bd10f70bcb010001	\\x53de89307edb37de2eb7f6e48aae67d543bd734bd01a326187d54be2566c82853d12facabddb9153d05267ca29bfd2b2dc102bbab6af1713cf8ade1db05ab10f	1669455689000000	1670060489000000	1733132489000000	1827740489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
412	\\xe6f753ad8310df7863ee8330605c2be1224dd4562e584fb262856893213d62c43b2b2217d0419c81acdb0032144dec5f219499f9b1ffb0245202296d2590a569	1	0	\\x000000010000000000800003b3269691a89aabaaeccc07e377b2aeffd56e54a318e000590ff29c4ada828c9b19862e562098b037f452e65d7f1fd26e900a6424b7e81f08659f7cf95500ff0328ba04b21075d18f5c886994be1e782eb04c375e27819d3a0917f51b84978434cea348ebee966ba67287d486076d1672e5fe1ab44f7775f1ba328722594366ef010001	\\x1cadc44287669f6d210cfe11570b09c6cd7411c3d965b81579f3ce76226001a67e9b79ada973954d658cee871ab4917ea37d5103bb4d53b20ef8d66bfba4df0c	1682150189000000	1682754989000000	1745826989000000	1840434989000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xeceb0f5dc93e1891c1a01a9f5628105c568bdca34eaf7fa027b69957f55fc8e146ad81fcff1f851ff03672c4223dc0c12a574dc83a8080ab0b5a2eff30608aee	1	0	\\x000000010000000000800003b8b9c1857d63c42ca676076749a8bdd8077969bc436c1fb7fe66beb99ae0de12514e6a2beff8e2ee94c615c26a07d1036bac256ee32f68d2b021773619a9003f03d16ae7f1c24db1f59c7345b7a28ac585107ef71292d30499fc7d04edce4884187c27aacbef66ca09efb599acd2c14054599ba538b1442570af9697ce598bcd010001	\\x356123142c881937cbca65af589eeba4e94884a183949bbaff13cb60941181a49e78e9e13a615e13f2e2d4a124810a6fb3cbb1b7c4481e4d7e192c82fac81f0a	1683963689000000	1684568489000000	1747640489000000	1842248489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xef23c34e7669218d57c1c1f9d01040f36ef782bcd670dd29c0a3e2de561849d624e8be5ec0e85ec70609e9423c1a1d712658b8ebeb4a86dddff32d08e64f1f0f	1	0	\\x000000010000000000800003c906f54f1d218cdfe3da9d115903959ffa42b8577a2409cd72bbabbf4391cc402e9f8748416a7e87781324f377857a494abe42532ff00f13c5abe654faf9d61a220e3f0d912bb1b946a189fa7b5c5ef9595e804f0f65c823de55ad2cf5e089a3af23cef05c709a30be571adde8c3b171cc9cf3a2a5f98c658cee5b47d6f2d293010001	\\xcd581ec692d24f8b4fd109fec810017a020c72d4c7b67d19e58de059e75c29c16f3d11644cf4b6b362a7615fa41612467cb95a85837b937a6eab6c7a2cd9cc09	1670664689000000	1671269489000000	1734341489000000	1828949489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
415	\\xf01b1e16973fc48a9b266cb238e59086c6407bfdc978b86324b689d94fb01bbda3ca3920cdc3cfaf614343762b5309075afc4794268d04026aab9606e5e9efa3	1	0	\\x000000010000000000800003a1813384b6d43d2e19f513e68992d82412fdf287bfef9c5d03c52997e074018e8cc8958aef42b429a2cc02b2e0758dd8d27afa37d828b773e1276726bb26af27ebaac0247938a30fbe9a9fefc88d1dd2210fa062a35703e87a5f201b06db17f5a07dbbb6fa0a2feac45b07f4ecffad2d2ba46e89c45d0fa586a9a9df028c75cd010001	\\xe5aff6e3f2208c4f6366045bafe485dad2e7853eaceb7eb9235d4af03127a397250839fc7e4c3ad2ac6ecee64c04012a2503aceb18f6f63d78d23ae7a255d501	1678523189000000	1679127989000000	1742199989000000	1836807989000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xf16b8d24037371c786f4c3c5b80407b7e5044321041728a11122c7fc2225ee914312f6b29ae33556206509ecb756fe10b125c09a7c48275bebaa7be652701d6b	1	0	\\x000000010000000000800003b688cc69fd638cee9b3f11721d6c63c564a74cccddc3ca5082b32e27ce3e4f9a06ab17fe4ac28e203b083376e3811669f339c9ba3756ed8eb788daf068cd5cbe794d442b7b9943e109a46421f0773a47615bb04f7def95f57c2d738a27910f84ab49c7668013d350068775a9f5d83565c71d87b6d1fbd447ea0c139bd496e4bd010001	\\x5bedb4cc5663dfceb00baddd8d466130a1e9e19f5fb4401c8bad8a256b565cf3da614e593cf3c400b51f243e13beedc433ee0d2cae5e02e9fc1a96e935b87309	1680941189000000	1681545989000000	1744617989000000	1839225989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xf72b0215eb1fc965b9ecf50304e8a7cd8e74ff53347bff2902e810edf73edb068fec66b78a4c3cd34e31035ced77f4d09648f7916ede87356014a1ada4f6ec34	1	0	\\x000000010000000000800003c1f989c42c9ab56672c016932f9e3d3731d6341a798ae5fd7c745f34dd575e4c6979979cc4ed8d8662c51403f1b4a988fdf3048bae16bf1c00bed3d813459389f1d40af5edeb7f72939a486e4cce6c6a6550f3f91285c9b18ffbdb0bbd2bf8be6d381bae660a0c821652e7c7b5e9ef5ed469576a74fcf37aac23f7ada5a368f3010001	\\xe9b544b0c43e2f5c77d4725fa4bbed830fa8eddd2e44b69bdc165929544c099bfc6fc0d32ff64e671793a591066a8eac810b41daf522f8aadd467a92e17c9a03	1670664689000000	1671269489000000	1734341489000000	1828949489000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xfa3b606fc91a5503027376c1bf62acbc06a58737965b42b2553f1286514a3cf001544428439af446e9f54ce899fa825c468cfd849e842293879407b74aa4ddc3	1	0	\\x000000010000000000800003d2b987858ff2364ce237356b698282341f852a0d5998737647b9921da85417ce6f455330087fbbf2c4de5081db22a528007da142b351451aa9e455c8fc107e8b1fdae4238ac3ee199d0a00bc3eaaf5aa54b3294f4b5ff1ac35bccda1e1ac353f9d62c5b561ff3fba1c575e02cf0f9af9e982ff60f64409df90b526fcb6fabb65010001	\\xe1a7dff12b418d93a9e82cbbaa52a09667c716ade833f7ea8737815adc6a1ba38e9fdb518487207993fe81bb43e8bf6c7fc96513b8d6051e2eb3879ea87d930e	1673687189000000	1674291989000000	1737363989000000	1831971989000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
419	\\xfa6377caa03933dd30342eb1eca405ad543027c92e145dc019ea96b886ac6a3a649fa5d15a2324459f95b652851baf1dd33aeec40008c476ed45a05b72b027e1	1	0	\\x000000010000000000800003d0c7e19c8c3cf7798efb78e6ea5bb1fb57e761e819f7e2aed56392bc18ca5f47ad542a3b77e514e93f2eca40662ada02fc828b9d3dbbc6983765c553d0c0f804a5f94246281391b7d982a7cf1bedfb36583636fa186ed2c77080876f25bb0d55db34e2314111363463733a57b6976eb5f078cb2c6df91fff9142ac772185b919010001	\\xa5fb6aac2ddd14912c8a866e774faac818e502a8f29333cde20d40dbd18abdb9f9a91656324f6e0c528d277f6368e383dfd1671390b78ba526362720ca8c9f09	1664015189000000	1664619989000000	1727691989000000	1822299989000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xfa0faf0400338614f185cf76eaf471ca5182c5c4cce93cc0d8717c1b0e5b6163e1123cd75ef21323d664080491cd063ce1bd34de50a2589dcd80aa55ac882600	1	0	\\x000000010000000000800003dbe2bf6b932f38b567d18837f5f9b8db2a6d4884da45a40a9dba5665fc1a0ec574c841a505e3196f6e457a46ba2c7c9c8b1a7e22881e871b4a657749a898364e96e613439ed724b3ff6932dd78bf825aa8de62ac0f715ed0af873c0d1d5ccc941cc2322e8824bd554aea36b193cd024979ad890dd5520f98c3501f52d0025b6d010001	\\x315f36f8ae4c7bc6c515bfb3c70d8172a1b589e7ef420a80f81b55ee638ecd037cfde48535f2b359c6113f8c986aac6d5c622ae4007a3bf1be5ea63b0f4fe50e	1664619689000000	1665224489000000	1728296489000000	1822904489000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
421	\\xfb176b7c0b8e88266a5bc5f218a178a064416778ad942665f4bbeb2a6e56d03df85b7ed45fe903852d950d53788e4d857393c0a47415b88c0b3ca8bc06f8eb14	1	0	\\x000000010000000000800003f45265838a22e56fe67ac037722ff4afc21cc6790ae5736cbb9e30d9fd69262de2ead80028ba5021773400dd79b1e99f2056d9664627a08cd8628184e285e4c3d1de7f84cf69d8f7893ff0d0f1339aba5e528701040647dcb98bdec5212e41a2154219291ec2c5c6ec3b3c5f5eb1e9227e416ad7c4b477ad8667a3f14a40bae5010001	\\x9fb5f3f7523d5a168ca8c2f690f06dda1540a9b021dc77b5a27c1f49425d56e190d602a1169c3dcd94070987929ba9442e915187522cad918b6bc3b3462d7704	1685777189000000	1686381989000000	1749453989000000	1844061989000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
422	\\xfc9b7a118ef1d759c2b688f472fb8fa7f234a8fef2e0d8e7225931ff249f6807013ce50a35faf8b775b8fb9858134c2c3993f3747e29340394904e88ea492ffd	1	0	\\x000000010000000000800003bfe6e6168fde0f83d5add0fecbae378aece169443663d54eb22a9bd7d4ab749c11b326981a668d8c54d2813cce6134d9755d19e2ca6c5ce9b265092f36b55cd86cab2b55a8f5b076f0e7f23a2cdcb3cdcfb1f5aaf97d71e75f2d482bb4f3bc3b40b789611961c09ac94a99c6b7c3f52a82adebe32894be5a3ca06ca32e65aa15010001	\\x7b70a010d52173de3e5ea4cf524eebe4eb46a912aa3c2d2fae05361fa8f241f9d8e50ec4ee066705f0b7ca303645712c0850188474338cbc55ccb537a392890c	1669455689000000	1670060489000000	1733132489000000	1827740489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xfffb9dc9d12f061c9963f8ea3dfc2f1787f1dac5cdfdd671add64b115dd0ee60907fa118afa0f65fe8dddfe910edd386f1a953c28eb135e335e13102af55a918	1	0	\\x000000010000000000800003ec10a33c33b2e9cd7e9caaee8ad26ba67d0948b50a48cbe24ea5ae85e2f344e7b45b2a8729160392584b4f823563f0902c53c1db12a9d6e186c99138d1ff0df9c3c1700cd17074f477d68ce29fe018f37baa6e062ed61357564592cb741840c9d0e4c4e4bae113fc944d7dd2c5094c513a30b6e18c3305fc22cd2e8601dcc977010001	\\x41168837218460fc2964210168da41f3c72d930ba19f4734493331fcddd7a6e4b572d23d305e0fe730621b1f75c65b0a65f5ab404893a563b814202f39ed9e0d	1685172689000000	1685777489000000	1748849489000000	1843457489000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
424	\\xffff82293eda3e42b70e344b325d06e69cae324953b917c147fb4858b67a645dc4746c74ea7a7b2d18b6e3a5984af9b74bab4cedcba1926d52c0b01ff82c545c	1	0	\\x000000010000000000800003a1bb24ec65023f942ccbd0983f0d001d9a15155cd05356849cb75666385f5212f1126c1d7838398f053fb5c129530bba67c5af186e403ec66c4fbb257c004e9ee4d2ef59007077bf377d0ed700fa212c28c5f5894b5cc4846e2c48b776489287e32ff97525dd5a1ae9455ca3b604fc05471584f9ef1b4e83e53cf7ce4315dc39010001	\\x655fb2b77ff5be20f407977f11ac4871a5682c0fc2c36746e4e69688af2f598f344eb77e50bc8933a29129608ffc39f1495d59b1d8d6616a7c2fcbfa4a2dfd0d	1691217689000000	1691822489000000	1754894489000000	1849502489000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660993604000000	1056399225	\\x6adb31bd94f30695d580dc4a6c3b121a87d66f00eb90f7f355fb63dd15e97b4f	1
1660993612000000	1056399225	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	2
1660993618000000	1056399225	\\xeef20d0da277529e070bdb760ce75207ac83071b72bba0ec3361cdb1c5d320e0	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1056399225	\\x6adb31bd94f30695d580dc4a6c3b121a87d66f00eb90f7f355fb63dd15e97b4f	1	4	0	1660992704000000	1660992706000000	1660993604000000	1660993604000000	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\xbf6c471c4b4cb167f7487fcf0b362e5b5e2593ff0bf18c8831e838cea19188b6f54df9f752afa00eafcd43a1f5be9b7eb069393b9a03d0372cf476f3257799e1	\\x23f98a492143f9338529295adb94de022b880f8a0e563502ff4104a57ec2a500df674d6425aa7b3205446d1a6e27a0fb8b9ea52cdb0c7e925aa069c8f47bd60b	\\x43ab138760205551077a1b1d64030cff	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	1056399225	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	3	7	0	1660992712000000	1660992714000000	1660993612000000	1660993612000000	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\x9fe342aa944573b76d328fdf6266c52fea74bedb2e461dc7e2066618fd2d82220c5a612cda552cb45d45de86dce66e6d441588cd9932b41463f735b5c5f647c1	\\xa49a60a0c1e9de2edfe3de80d0d86eca66e6f8d043556fe100832afa9d13eba6983448f5381d22d89319f11b0488be22fa1ae58e6bff3e80c1393051a288df0a	\\x43ab138760205551077a1b1d64030cff	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	1056399225	\\xeef20d0da277529e070bdb760ce75207ac83071b72bba0ec3361cdb1c5d320e0	6	3	0	1660992718000000	1660992720000000	1660993618000000	1660993618000000	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\x35d4e33c0d33b399b3adf1866d5dbb17973b9e444b842de549c532e446055e1a0212eea3c6985a8a4012414d38e14ed1a308b7a5497eda32f8acb87349244b66	\\xe21cc77815254a2920158c73229bb95d5e891a8d5685dfe0db7200184ea0dda1e9268cd49daf821e2fbba7e137609dd144c0ddfe3c3ae7cd3afb887194ba1b06	\\x43ab138760205551077a1b1d64030cff	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660993604000000	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\x6adb31bd94f30695d580dc4a6c3b121a87d66f00eb90f7f355fb63dd15e97b4f	1
1660993612000000	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	2
1660993618000000	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\xeef20d0da277529e070bdb760ce75207ac83071b72bba0ec3361cdb1c5d320e0	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x2747e8d76adecfc3248cc06f3e7e577f48ae9c5c0d808eabca3a573b0f095ad2	\\xe8bf9052f9c1075ab8c4bf3d757184256b640594b3af767aa39bd50c43d6011b0e1ea2479c894c6a62b6c34aa4321c094391c1c7ad878024047a40c6fe26f003	1668249989000000	1675507589000000	1677926789000000
2	\\x2b163a9fdd5f0ca35cf0a76147e3ff593d6addeb5527f2ee36f16c8e3899e3b8	\\xc7fcf13b65d2a2a7096133bd41c531cf96234fda19dc1c5e1031dfc4005e6696d65d4cba4942c43ea485b4a7df12bfd650af1cfca027b3a12d5ce7e227e7b600	1675507289000000	1682764889000000	1685184089000000
3	\\xcd177186b7ab0d514e78a8cd40fe94d434d6ce7c3dfe056f43992e2d2a3cf16e	\\xa19628c59762ed749b7edcfa447dac56f2185181491a95d0b03258420c5a7ab497f01d55cfbfdad3d65f5c252e2654784a7239ff7bdb2cb6e329410cb5fbf20e	1682764589000000	1690022189000000	1692441389000000
4	\\xf42008b02c9df2a62be8986ca4f6ec45c6cd64bd2437075a8acc9bc53aeaa284	\\x2fb4d4310a3b68ee76b733961e1ce6db0c38e87881cd2bfeb156fdeca4651b3b2f0db6e5c06581cd161bf45fa83b6acbce522e0a89c004660d5d2e8d869d8c0d	1690021889000000	1697279489000000	1699698689000000
5	\\xf51f9b455918cc78cae8e6cc2ea33a1585586126d01853912b876b016346f5c1	\\xcc12f62551829820324214b98a970bb96f476ed2c973657fe76c32161ed353de762a749940cd8f45f51e7493968078584335dbc81db05068b607c1737825c80f	1660992689000000	1668250289000000	1670669489000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x56c5c3eb592f66e6cc81fa47af60314b81049e60bd9f4c6c0ef969ac2a42d43d10430187367523cd2e2384eb5391ea63519ff64e13e6613fe84e8dd895c8e202
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
1	300	\\x6adb31bd94f30695d580dc4a6c3b121a87d66f00eb90f7f355fb63dd15e97b4f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005e3fc75c0e99479af544214ebec5fb20778ecf166faf40654eb7fa87fdf93ebae938732d16af4574c90b48ac4e6d216de2a0d0d058589f2af3360a8f2d617f5e3f895309a5cc73ae072d30d7c908b93cde2851c1a4029d4fb1e426889e6b885a0c080e1e9185c81fed5cfe8fb38644556329bcd6b9b960db58a4d8239a93f617	0	0
3	77	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000022e758dce2e4efc1f59e20e2da80e43f3ad65f6f0890495b0c2dae1b46c0a6e357ea0a413081b903ec2e54dcc3c081b66f03344320a82e95e56318b34808486494b1f2fe4c8f571c756e94ff7e3696de420cc044d86d74f073ff9254d1cc30e7985fd0b1e44e631753bbbb4b4aa0b79d0d26874a05543fabaca69d2a09196884	0	1000000
6	116	\\xeef20d0da277529e070bdb760ce75207ac83071b72bba0ec3361cdb1c5d320e0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000001cdf5102c3450f6a25cde868cf4cbc72f363dbeb1d466f66f871b13c27265b523913c7beea0620d4a2f3897901b0e680b46ebc9fbdca19b5b10cf1b8d3b944edc2b8b210c37d4e45a6e3aeab490399bc7399ae3d15b5bf931f8a198a42144df79f5a0fa9e82e69e99e82d8ec376cb6400d682407a15a948baf4c23d750ae0d9f	0	1000000
\.


--
-- Data for Name: kyc_alerts; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.kyc_alerts (h_payto, trigger_type) FROM stdin;
\.


--
-- Data for Name: legitimization_processes_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.legitimization_processes_default (legitimization_process_serial_id, h_payto, expiration_time, provider_section, provider_user_id, provider_legitimization_id) FROM stdin;
\.


--
-- Data for Name: legitimization_requirements_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.legitimization_requirements_default (legitimization_requirement_serial_id, h_payto, required_checks) FROM stdin;
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
1	\\xaf9033bba1d6b92e878743820d8e04d0066159516157e53e55fbfd501c41169a63427a7f0c3987b9a9fdc0a8e29d50609edfe7cabde30a710b8e083fa3f6ee4a	\\x6adb31bd94f30695d580dc4a6c3b121a87d66f00eb90f7f355fb63dd15e97b4f	\\x6e08dec22b3fa894beaceefb93e6a4539dc86d548f72469cbc43e2a9c7a9582471f7f37f5b220507b20957d2d1b13d6be2aaa5f2c80777982cfc6d2db323f702	4	0	0
2	\\x8418886710cc921d9f25fa10946ed4ba03bf2af8cf7352c656ca95f8af57992353aef103f5f80e55fd43983eafdb73d4b710615ee1be34657030dde7e0733973	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	\\xd36305c122cb84ed6a0e2391672bb2d297db275017871532fce9227e046ab789b723d29dce71a528d98f4176eb43ee5bca942ffd5652a59ae76dcd1d34e0c404	3	0	2
3	\\xa1b4329422f2ebd842e72b2bafa599ef269895d79ae7835bcf61faf5be96bec58ddf8840dd0ed458a74b8301f2470e910b720f8c76661465e00c53a75aab532f	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	\\xc22e2f413eb662afcf3a5e3964db1677a4a0c1050bac091e87131bf6d99efa5973324ebdd96f04f341ee0822ffa54d7748c682424a57b10f41c8181e46839a01	5	98000000	1
4	\\xa0c824546444a2607faaca20cda5e3fa20a4535d075684ddc44d5370fc259cb699205d884a59e5f4375e22e656168a7991b86df0757f4e8887628e0e81a577d0	\\xeef20d0da277529e070bdb760ce75207ac83071b72bba0ec3361cdb1c5d320e0	\\x61aa15125a1b3272027b54354c217409b83870485dd349dfffb1dee4950e4b36bce236cc8f458ed73a273d543bc8d68365b51757270eaf9e006423bb99b63906	1	99000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x52d108ad8717e08ea146c24769e52aa586f71315db7b285f10277a8ec7e3a6c7f6c5f84e323f7a6023691360bcf19dd50a12ac6d4cf540c69e977a27987f1b0e	196	\\x00000001000001003608ef53d6c7025abedf2ef08503afb5afb4c4647d45b33d944b68060de6499c2c95de615258c4d83364837555dd2b05ce3ddb49f64274f12c0f5d75eb326527d2ba2cf7d01ea065822010303291afc66448441ae7441d2d90bac0be1d29fdae74fde92fe6a9bfd036a79630bb227974a67404060c9a2ad2401330930074279d	\\x68b15ea5a988f2427f40e51b2ed669c484c8d6df9d7847b2c82cd3a41793cd768ec6f545ddd7b621721c0b0a2f5aaa9ee104eaeed6c9c0eba9afff1ebc4e1268	\\x00000001000000014fe69b6b156af171a6d3a7300ad071f90090960dc0635493ecf56d0beae78cf7887cb6fbb33a24e388e2031970241f76dd7d5753f435a950af3a55ef9a00ea09c120cc7e1f23e7558559549c11e760d5d09e9231ef195c58a5ffb4ef523ba4bbbb28a45342843df803aebaca2b9705cfe1e8153cffce95dddd2c760333223907	\\x0000000100010000
2	1	1	\\x25cf21afc1ec058737a8c938a22e0a8cfccb71eac811536c5dcc4def26ada3b3062c146d7f4849c4c1da4f7b9a7f61cc3c3b06028d029e532cafd5ba20c45303	310	\\x000000010000010049dc99391674b3ba136a5229ed6701fe6363374d7257fee006f144d9fefe3f3165b6c131d59043580de75b0922004910b44da2876810cb8c4c0ee4120b6b0da1d4d1067cf60ae9e908b492c46cbe177779e72f6b83768ba46a14a642f0cee10ddd98b61b5c712ce8b037d99a8812f7bbfd87459864271557164199c5f49c2791	\\x63d7d3f0607dde4c4450e2baf8df37ab475b0d99cd2f1f3f9c774063f84e13f524dcb99feb45301154670b41302574b792d9132c37c22ce1ceb3d6cd919970bd	\\x000000010000000157765b7f28f13a0b614e6ab2f1575791905aedc64f3bc9de085937226fa46fcd18aae3a093452a4b88fd0d2bb93277256b6cb12fa6dcb7389a74d8c0f4384f8fba257619ec28527a9169ee6f0becb0afcaeb918ad2fd70840a56d7ba64febc93def745498ab24adb7b35bd80d66cf5140ac3fba5936e5ce2bc98b86e79e23b7b	\\x0000000100010000
3	1	2	\\xd62e7b61c969592d51a5bc8334246532e36888dafe41f3ec6e7f1d74af4a698ec143eda573e9a9063011e9e33dbc2e7fb5ffba7346cdbca5fa55ed25cae9db06	154	\\x0000000100000100b0bd65cae08a6afcb25cae4c2bf7375d38a819ee09bd289a92c20af38b4eb57a213abcaa6f113223a96becc82c8361ea6e554e38ca89eeacc61c78c4d7285c4f1ee59fce009786fdb943d9111362c5855164b6bae6ab6ca5221ba4129b346a82631f9f914d0a87828375d1e9051c339b318285049c03d886d8501cf804803696	\\x9ae56c64429b6cb3141abff8d49a56f17803bcb354113462f8d459e362b59472aa37ea18681c70058994cf2a183c7a3be25ee74a82507a199455d071bb59dd5b	\\x0000000100000001435b09d38fe8f1633dbde387c9dab0133ecd451815a7c97dee032c9aa4796153a92c8234eec075a82f55deef6dae939f1796ecc8cf6dd62aba63009b5195709ceb07b9a78b31aa055902e172bf6286ab90c0278a1401d097c4c126482d8d9dbb8e9d258635ba972630c9dc9509f7be60a8146388eeb28935b1962f0482be64b0	\\x0000000100010000
4	1	3	\\x1fcae04fb822dd9c2c5bcb3858a72b5a0656ab0e4b6405007bfe397208912d98c005cc83820ef8670c998c55a96d88a1941c1dacd07aa8aef274f2a6b9450f0b	154	\\x0000000100000100b0652256eb4b9b425a112eed76e926ccdad14a66e866724c5302d12be59089c6b295321c37c2938ede633f49bc4a3aaa505af90b346786934f2fbd66b5df8d813d36d3a5e0c1c90ba1e93e72db655a65749395805e7e548dc586d7fe7731d8836365c64cbfed5ff831348ecd3f4fbf7a430435b59f300d9c69bbb3acd8b2d316	\\xf843f3105b5d92f5cda1dcc24384acc94f377af8b210261057b559d0cd94c3ac40831c7bcdd1aec21e4851bb922edb2c60ebd9266bf8887eb91d1a5bfd741745	\\x0000000100000001127bb0027e3291426aa06f9bcc0787bc03db25c60e6e74c0cd402d7774b0715dbe0c4749dd4659a2fc17441a8d1cf2f8f2c1c3c02e60e28c61a7e7b49f7cf495fc60eea3a4c70402129f18bcd0b87f75b202c7cba8815d6c2e2b1c57175eb7fc24c49d4498d819ea0e30b8d0a563dc8c294b1656026a1061411c19aa741cd595	\\x0000000100010000
5	1	4	\\x6409da7f2e9fee00fce55751149c6746be66b5651fb62c8204821de73930c726d20d0af916e6361554546f8a75bf1485c6eba2d5f185710576ed2a0c98a96505	154	\\x0000000100000100bcc5eafca23f4ed6de4b143afad00d2dea14900e965f8bc0ba761a5cebea202d9b868dafdfd62c81e8742f921a8743101af1714223a5693f49ce0562317295ce9f7f26b704cbe340162ab1ad8b9b71e63b84c68f9b27aa5aec1d397a1f3954c4ccb8e88285f6b07fb5cc9861b43d002fda23e1e7f9107119b23b05b4d0b7c557	\\x37c052575050a1eee36470f96b7115586a6655e337efcc29964617195177373e10fa153984815b99096488dc5cfb67d7d3f430f2de29c9b70582290b8c572816	\\x00000001000000019a9ed6ac3c9827e5caaef1adafb84d0f96114f618c0231d4bf55fdbdd8314f3e03ecca78efc00407542d1ccaed5a47dc550964af7407d7cd7d47db882c4b892c80a41f5c1ef4c6619df4f7ac2b9eeaec4368b007887bb683c4a49707820663b26c08127f50fde5bb734dd9535a54006e2d34e808d27f48f082191ce641485380	\\x0000000100010000
6	1	5	\\xdd189833c7beb78cffbc22086a0c1a8728271f5b6f2e354d85555f7570b9b9a60ccdbe5008d39999a8d34c4eac12968555c99f8afaffd5b274e6fe5cf0124605	154	\\x0000000100000100a28f9fbe0a7af393696c11594bf9f419ac1b27513e44bc03dd4b598120424e251325bc765a61e2f5db71606cd944e6487343d7ce82e1f816a86d760914db132b27a6714b49f2e54fd8421de91c3d83ba922e55c5eef9b7a0ddb9c66c3b2ddee7c05d78c6d45f96a9f92469ae57fa5f63e14f79e47437dad7df7289eaf88348bc	\\x7db48dd5a7810b431b6d4cb3ef307094fd0459823c5818389763db31535a10edf3a0e905a617eb14ac451965a2f8e386bdd7ea207f3c3950b7de446e2dc495ce	\\x00000001000000017852bbcc99079e1dedc8adb51cc2ff877f5712f56a2b659f05c72bac4ceaeab13a1e009c3f3ca7b23a1902b93e47e37d1f5143d06ee02b176f2fc72c38b4f1d5740fd4207ce976c987dcdeb3746ca380b76acdb91e6d7fbe91bf62ff65591d1589c5a0d787efe78c8f88fca87e940493ede41ddd2919fe22712153f1f74de5d2	\\x0000000100010000
7	1	6	\\xed2c2a0f63dc968838577afbd99266c08764d5a9e995fd3b82eb2dceacf3e4a27dfc2710bbcc24f464d47d95d25337a806b0241e2e1cfe60c4c56665d8b42d0e	154	\\x00000001000001007e74cac58fb81cae7793f1bbfe51d6eacb30c81a6dc85279fa7942e9e854756ccecfa683fe4b33fa297329d5d14138e6f35db1b9fea9cc0f2d9cc90c30822a238978a1c8c56b2390527a59b852e62c8e3641ee5d220e757706abbd5fb004fdb2003630e565cbe504c2e358da134ed4b032278dd2f11e5d4792652896b5367739	\\xe698541bc19da552cf706c76ee16ba9b6d6cf3db5da516bdbe03b8d5a720bce9a98b7a8bc13a7b0649c12d867b3033de24a3028bcb98b6ea578ffa46e992f2ce	\\x00000001000000013696dd466eb0087fbfbda823773881d4522e6ba8c5dff10c7588a0f3eeff1f2953073c8c8e3131d8561bd5e577a49d449c865aee02b41f22b8ce834f1b4ec3c54e94f1cdadd611ab8562baeeb7fb8d6268c8dc690a91adb9f96693a8e694caf509323e19fb083ce6a2e958a5cda8578672eebbc4942288227aa824116ca47cdf	\\x0000000100010000
8	1	7	\\x1429fdb84180475d6910bb16ec8b196f3d4a17e3008795fce195de3b1f7a3a476fe8a0b31019f4bba7925c5a8b2fc776c5a8a05c07ae476825eacecbcc04330a	154	\\x00000001000001002ed3c81b21297dddf9e65af5d6f5f3d8fd98eb34942d3be41332b3fd7ba8f3a7fa0e36673ce71f5356fbe049100925609fed787269f2ab43c87b5a0f1f8dc7e6df2b9c6650c2e3abec58eeadc94613fae0ebc2f0d85046eb6bc085dac37800baa94e6f322ebe3589fff0a844c3260c424ac027e007308a245567572cf7036d69	\\xd21feb5be7125dcea9a9817ef6adddc3b6c2056edd557854011fd78212556241cd12e7541b51f2d7d6b92b88e442fe149d6024f18b2f940e10b9fb8aa685461d	\\x000000010000000143e0b1bd80b5373f41ee51ff5151ededd5afcc809c4733de5fcceade51da91a2b47289b24db3014f446b37310a8c98724fe84a97b2e5603b9e3d94d3080a505325c765fbaabf555a90e7a6d708f2f9775b7e9b740d18a99a0ab46b570936aa0b75986347a7682620a9f875216a753afdc4afab1db3b24e6f95dd30273c8904f7	\\x0000000100010000
9	1	8	\\x53fc4df192573ea4aff79464d8425504a70583ca2f8e0168e5cb3847a4ad776dcba5ec1406de0ca7c92bb5fb59687153838c48d58bf3219d539fb56cab628f0e	154	\\x000000010000010065505d180dc7bc325c929015b95db939a3d5a92963ab71336bfd8933eba2cee129cd61507349683ca1e8855f1023ea8c94df4feb6b863f1f128691cdf3b8bb7ce874737121add4961940ea1f27c673e1295ac6f2da165067b280f07584e0ca2b4ac4a743f1b02f0dc28cc3d4c9a126c0cd30dd8d746fb194f397b094e9eaccea	\\xf2230aa7787ddf8d724ae6c1ea168423e110747c863e9ebe68369d4e5f66399d297f8edd3a3ccce8e2561d03b456cf8bf79ceeaf093b514ee30ebc2a753641a9	\\x00000001000000015a3fc67b85e4085a9a9d0ecdfdb74a0802e4bd26c6e40ed8a11add86d86d00b810fd083383b325901e6ac0773ecb2abefeebe99653611a1896604513e1cd777140b03635d194488d5b6e6c4ba3dcca3f75bb9d4cfc6d40e4d2a4ba480fa53d19e00126874eedcd1e1ad18aa228146141b96c2fd1aa886ab78eb5e9b4f55bfee6	\\x0000000100010000
10	1	9	\\xf1e1cfb11d5ff61460a63a925c4fa8718c21d1fcfb10841d46ffff29493700ab5f8ef9f757ffbe71ed4c48b12c83fcfae253d18816a9ddd6baf4e2603d7ae603	154	\\x00000001000001007037503e3062f87cbd763fc29a7ab97253d349d59c331e2eedffe43ce6cc5e2dfafd23b459965b172c4c2a33075d03cb9d11639bfa69fae75306a4987ebd68f22430cf152efa59bc89e881877c4c189f4cb466a2c2bb4f47f4e2b0b48a3c7dd745e71bde14fddb7f909bb386748f5986624d469515fda3aa69293bec409d6e28	\\x10fd4f4f022d1b4a54d9b7d0b045952de27430779f858b30a1a0b76569ffa932c9178018ab0876e99c25b6922994c2d44238d0f678d6eca3597f0dca02be549e	\\x0000000100000001393c130ac5594e38ab22e9785425b50737b26d48963daaff26625e972cc319f8d8103b3c7792e077f9a0a5055a3c4d3016b27eb5e74ed522ed1b81a784ab3abae35c5a3f9816ac453fccd587ddb63959d04a13e25a64c7d3afdaf0181429fa54565a380119cf076b5807cab8f497c464be2f5dab3f63c01885459e2943cf6712	\\x0000000100010000
11	1	10	\\x5a57af95e3f47477301af91a85d86dc17a1b0b66f7b342d521889daf97b3669eebda2e28d5d3e51bcc459c0f32d87d5746d1a0dc43beb903c896a7acb192e808	174	\\x000000010000010041ba0ebb594ad677de9068debe0e180b9fb1bf47fe8a570173824ec8b57f0f9b47e72c70e7edc39db634c9628fc8b3061cbe0fb7060bd18da5af0e3f9d56b1ba25cd83403d06e742ceb42971105663e264f0d481baffa7aecc4b64c56a4c44f92643c870aefa654c4f83d056a5a3fb575cac324c83013c32e6476aca3ed879ca	\\x6397461e8c5547a5b0e4b9d8852f6ca8119683819c01184a12fc0ef0084450381b4a156738940ab57528a61cdfc38abba909e3e9f7aa14dd1d1d4627b4e933c7	\\x0000000100000001861442e8a31e8bf42ce7950ba69008a00d02b9f727417cceaccf83388edefed57b99dcbcb60283f316b1738071f49a141027c6e2fd40c6c93f22014a62c312e75cf730090060049550750c7cc37c4c3d81eb1570c58d8cf9a64d5a6ac9b86688aaec21ea6ce3e072785da423672eee6da2b4c1c1508fb4148d05c977e13d149f	\\x0000000100010000
12	1	11	\\x43dbea97c02775fa078f2b9cc1eb66258ba80a6569acfd5c62068e67afcf8880e2c08c6fcee81f2c3e339f8e641dd991226224d4ec1e2f1a0731433803b53603	174	\\x000000010000010062f8d2771921583b392afcdf4dc702d72c4adc0e18b08c150b8216af23195a2c5810b16e7136cf6ad61ed9c93a52f0c6ed558601523273c2ef9beb69b5e115c5d9720d2c3078b4c7fc539b8545d2d6046234b5edb09f80721798f42221c002cac24bbbacd22182d624a398bf62b6f020a5be2e19d1e0380c68d22d036d8c1bdb	\\x306a33103d75ac0c92208dcb408773ca5f5cd135bc8d118a76b5596eaf03495f03bf8b89ace1eca40572877557d56b6049fb22e4b666ae098e711479b84b61a6	\\x00000001000000017af86556624b6059e191dfdb42fca82f6f7241b3ad13a9eb009e2902419b5cebc2b036988b86e21aa85917940fa49cb76ef3ad8beb1b1fc86c39ec060ab7982a753b04be4f312a13f90a0fa5205f982a30e1a7f8bdb32d1079be15c98f04996c99f93527add4fb69b474323f5f21f7de1cd4fa8b55a393256cfaec177f3afc	\\x0000000100010000
13	2	0	\\xebba54dd64eeeb13b793fd77f4ba1b30e208c954aa4b583c3a8476e37fb98b71f1e4732079d4e7fff21dbd9a22c83661f916ac285d4195e240277cb21c55c405	196	\\x00000001000001001725e4aeff39269e4bf2a6aafc3944cc6a4b29d5f11e04e3b2d453f993c9fafc9924cfae93c92ea9fe8fd801d2d471ccf0b2b4aecd7aa57a9c6111f80e4c28baf0775628d3bfcc35ad3a9123c1d0bf8383dacc98d266cc7366454d5acd41b50abbb7bf89a9d6daac7658eba0d3ce6210c8a50e6449ce831a0e9eed52e3aca244	\\xf8c85b8b2eea44f1f91ae3f7babe872b2a0f46a7328d151deee35d98f421f1ca7f802c9e96b4aed9aa195d4f2578195dea280b2800b8191600d2810013bbfc51	\\x000000010000000151de44f6e808b20f7debfbe1538156b2d51b2bd06d684bd592e5098b76a7fb5ff9ba9d0a3c47be2df05aa71cfb981160ade8166b4fa7b24206649dec2237b2ce42e2805646f49c43d4edcea0f9aebc8dd7708852b4379f8be91b065daa66942f232bd1ffc34fa25c84d66fc3bfd6a12dbd29c133138ed3333bbabc213b07eabb	\\x0000000100010000
14	2	1	\\x7684b0118be6e8d99d8857338ec4b51d4b60b429273ac27c63a46e085ca0d517e451c318036f0e70d493fc3b858dba951cad842c6b47f0e6845b019f66fda40d	154	\\x000000010000010062ead2e2ef48908322718f4cf9cdb54d5568c32981741f970e913e7d514c405391b7472ae28f4a20ae68b6bafa3f2913fe0ce78559f62f607b657dab2e4487cc6fe5e7d0a1e647b842c18f1c83b5a3b86c79abf357f14647e324207e8b55cd3909b77cc8081f33c6b2d88745ae9a7b5c04557fda54aef42c8e80721fc50ee0cb	\\xf874ca2bcc91ad4630077f7181dd39c9b7e18f7b6c06eb63bc011d966eb4a6eb584101c71a4f916b0710aa6323bacf3ae535372a159185dc6945602bb0dcbf9d	\\x00000001000000010508537049bb0b006ab59c61f7cd211f31abf756f4ece5f0ffdf89c3e43991edfd4a0148e28ff44cceeca3ad4d31d7d2e8001eddea5e84966f645d0cceec3b4a9d8b16f4fd72a19ff3bbdc2435672d4b30438e80716d03a7eb27d43aacdc8f137b3f7eac34d25c607babba3ae6c5ca84ed58f86349883e87941fb98c9f30a72b	\\x0000000100010000
15	2	2	\\xd8bcce39b7aec436617ddd5ab2a56823371f82c953caaed4780e3d9d1324e7c6cc6165a7dc3a31dd49378e5d6d829fc3db886be5cce1e255141f265fbed79c02	154	\\x000000010000010060028c35454b988ff4ac21ebc5f46f46c50b6133d573ec4f08ea9b7fc1bcd742f264f306dcbccfc2344f0fecfd84cc42d84cf286e02418899d905fd7d6e4503e65c1e50b2abe0aab38a1af2888952829e5a1654a6855c3bcb26daf1479b6ecf1e81f7a0072b21dd463370ca06d61712a2c735ce18a62b2ea05b3b383ec47fe27	\\x681699b6dabdd1379cdf13d5d4055c079e768d5f5e0868c396c16ca82a2bde53001eca7da2c0802ec8acebaebb0915fab906499c4077797d64efc9a494ac0c3c	\\x0000000100000001ab36f0f2ad28b5beb5ec288b5a10ffd1c19738a611cce2cb8a65f69ecc8c61943958d3ed1522dc650d6b7f2cf76bb45cefc6b93e9bd7ae3def7c4f33509699c7ecbe3ac4b6ef0c96205db5c13d2b5307b14b604ae0e261179841f35591413db6c9ddd6883064906a69276bb211d260694370f953e23dd5a3dd1e72c0af9ac76a	\\x0000000100010000
16	2	3	\\x6827b3872d90d769f62693a37695a40ca53f9f5e3190cbcd1384e408b4477211ae52426373ca808f040e0c503d04ecd806787c31a6a3108463c6b1b8ba30f80f	154	\\x00000001000001007d41dd28da7e1a6a28cfd2cc9ba176b2a796e03115243cbf14512c156b1abd0c3cafaea3c15b98b3387e24e0ba3fc72af8fa2cff6d80e7330797cb60418b27c82c680c9a9311d88af5abe63a97aac78bf59170529b5427ff8e302064c05e576d2542a4813ca25a3859bd28fc7f51d0112c02f48bc63a371df411c37c22e7bfd0	\\x03487016a6a38f1e36880fa55b2bd37213000d551552c413251b7b6c20ce824a65b2373ade558486c959f14162dae6fbe0ed1f3a9e08c334957252bd86fa992d	\\x00000001000000010a40c71e9ba262f85fb8a7bceb644333a6d35b18225649527a420e5d462035fb5cf54ae561c0d424bb0fd8e3b04f5dbb275e0e4f6e23621f7fdc1d6f326604df3ad33d5b3d914e329ed9da6fdcd63dd8142332f31efaf6c86f1fef76ddbc9a920c87cda533f5757015c848f0327f6be07c21120873f35ed1b25e8a92076b9208	\\x0000000100010000
17	2	4	\\x1892066a77bafec9819dbd47dc3a929e2e963d7f1e7bf261bf8408b53cf1a690948f03faeaca407a9bb51e8727f96c081daf11409c97821cfb4c522363e82207	154	\\x000000010000010009fd2add1643067e0a2024460227a261daf183a473b3395c9e6f38e9501f4645e8c5d1a2d53fd9780746a44e5b40ad5e6c0093a128c396256d74c4f04f8b972fc839cd5a65b31b33c4d7d510a32e88885c34dc69a88c62f3c255e1bfba32977ae60172235077646ee073f3de736c6caff4fadec21d159ba547b09379c8283d38	\\xcd6ed2039fdb5831882b9181885df35ad54815a643bdf5fad4b67a23e988421a64cf47a8ccc9c41900f68ed9a3326b85df574b9ad3ee06136fd801053e26ec85	\\x00000001000000014c5281880d383136cb1cd0d20fe48572d448f529995f001f065c25591adf1bf969c553fa75d07906999b26496fa82fa9fc1fa4c40f1da7a6bf5d8374842cb008de90b57960e59d5c35f7073b86e17e0e62b1c81956f9766fb5ecb2b03a87829f6abc6bac579ab10bd27eafa88a96618b8c9586b3374a0b1821d6c6aa1de5ff20	\\x0000000100010000
18	2	5	\\x8d483d761e989106f039a5c7df27378c0eb30f6df7623e52323675749949d2e692b17eeaa2d03b676682dfee84ea7929dd68d7cd9ff438df9dac1d8a83289207	154	\\x0000000100000100b628bd792c7720449c13561ba4cc801e34999a222649a5dd0f2a7a6b5f553394c9636466cf5324f76b3defd7ecbb14e3807152decfda5cd9d717400f2838fc8ec0a74f07458c83dd61065ad7e0feb0fea752e4e0ef42b67e6628f714a9ae3c6159e969d31ce91f70b5e351c4df29afcb60a21cb3a5c738d5fee8e753455f8b20	\\x72f152bf572623b4d17c1e9db92daafc2ad5e5dab81665cfdd9d65d032d65f729b2d8858b52a4b7a040ca39325d50904e0eba87996580c18615aae84334ea56e	\\x00000001000000014c81ef8aa68e30de8f493740fc0228d011b437a8027f9ca03d04e56fb372951fa28e8432b9cfcb6e24933bbefcb6f6960596920aa0584a13419d5d197ab39774a0f91ec4c354b61edfc993a0b2d957bdd465dca0a0b429b9aeef41121005bdf47b547e4a5ead9f2f0b23f6f724262f7b311e30ce8720f8f3f38a552319518faf	\\x0000000100010000
19	2	6	\\x744f759cca1732f50f97544a7d28cb845545f0afe0d19881ef43d12d9290727919b2bdd2c32929c0d94f17618a70a2146c627a05df1ba3f2d6a486759ad97f06	154	\\x000000010000010064974d1e5cd49316d1df764070400459dfe1f64a558f721313bdb38dbe765c53717287e4076635506663b0b83d57e46954357b6bfef50cbf77d879b14ce0135f390eb2c3e863a4134609da8842db04f37cdeadb598bee7dc574879609e81ac2642b1b0802a2405b346cd0851928df461db10bb55599cad568a6e2ed25213b6ad	\\x46c16cbd24864323b316cc4705a1eec22c4731995d8dcf5232e69299829b779ae5c9e76ffa1843b63d2dd8356cfacf4f482ab0fde5a1798f55e5f14cacc7db9e	\\x000000010000000128c7ca33fabaab12c92e44fb746a170c5ad61f0eead2ebbceff871608bb79bc30677e45303497fac1fe6791791bd5540804664810de5bc45b2e43229bb1d8a27cb87542755d2bc949e44e0ae8ab1020926a8f3c45dd4f364c64459442dd0f64f67ec1ef43a710995cf462d425ff137219b4f3db7099945ceef1eda32112acd56	\\x0000000100010000
20	2	7	\\xf737608f40d782745e99ab5de022b292240cf36d7025c3943e0f6adeaace4cc9dedf1175fd2e587c954522971c226d7429014bf0a7917cc068dffaec0663f609	154	\\x0000000100000100a93d5010035b57f78fa6772cfb51e806f47298c55214dc97c31a8b76e9c325d7049c1f1a6498dfb6a72dcca22f952c7cde70a564f70e6ae00b43d850551f8e3f8351fefd7445e7e6e7f6f623ea484bf76be9fc23a8f1477a8146e48116c58e771f936f52ab8387912fcb934ccf1a9627ea12ce39d457b1a80803a2e730c1d165	\\x74cd290fb00df7d48b1460fe9d441aa5f47125e74bfa906aa24c1d8b2266bfd8a44c22e882020255a0f438389047532ebd444828ac10621b8764a5aa89575eb7	\\x00000001000000017f8c068e16458a14146ea159eb6209f889d225c2e3cd0c17021f28107843e69c77b82d4926f2cf86f4c0f2f2f3620925fa5fd36fcefefe4c70272cd0690adf8081bdfcb880a63584e8d8de91515830e4228d58b5ee3dfeb7c81ea2107d1bb7c5411d3012c6cf1b372149bf9e4d53b44deb10dda40ece59601bbe3a17cd1ba38e	\\x0000000100010000
21	2	8	\\xa1144ab0ae0899d72680289b5b78052bbfd217b087dacfce6ad4c4da015cef9156e342a9548d8b4c228cd594a2e019f50934f042d0f07d828fd3d501760f5901	154	\\x00000001000001007c1d775d4b9c41843bedfda090cdbbf27a86846b7dcf39afcda456f77d0e8bd0c2a6a510974118512180ca55f822669a04232b31605e305d231451f663160b0b9df1676915b06b945d070763dafc39662a7dd51daf7d0bf210b0478ea32be10c149814ce5aa59c93ed0a17180af5d989b480387422f9f3f0f1657248d5a17ef7	\\x012b35a91424375c2764137ccf358eba4bfd468222023565d8805319aca50e9e8150c7224d3862a1c33ed01cd4cf2f59fcfd20af5020ce99a3fd27c7eaa19965	\\x00000001000000010beba0e730b28a9f13c25a8d45be09ae4989a1885090865684decccefb6293626a4b9ce66ddbf2860f6dbb38356b965ae058fc4984e8058efa7cb2aaab48675dcd2c0c7bc39df8871da83b305281ba55a1ee82b68af551ed4561804e548566406636de9da7ace09ab7cf50e3724186f137f2c5bafa1b593fceda605addf5efb8	\\x0000000100010000
22	2	9	\\x3b4a01c599b91a60e1dcbb58bfee7004c0bf0a4b9ca8fa25c6adf973c1b63706f69eccb45ca138a58b4e635054aafa9c5447e0ce18db2f578c98c7d317e57f0a	174	\\x0000000100000100093bf3939cb2b8e94279731c80457c74b5402f913dbb449df7937fa81c6fcf1e437db5acfa57d0c2aaec9bbb0680d8ce8a97943b1edbbc82a882b7d81ce9124afc45013b0c284a1776c6af775b07b71092e7464c326a9e336a322e752b47a16879eb74dd0a5e9c3c2a909e7a45930b79a4aede3ad974e35fc98328ca1700d27e	\\xc038ce74e870c1a096b067fa18e0ec419bbc5856ba370dc8023bf667f35f3e6c7da17abe66fc5c595be303a4fdd67dffa7d5f2dca9b29d50e0eb7a9e5f8ae533	\\x000000010000000131e5cdc60ae88470107d6f0cedf2b569b866e466fc88fc07989f6e6ab766c0876b9c4b032f0e7c528ad63f8fbedf619df7ae349a06791407b764aa53815ea8e5d11ce4e18f48f59464e73fc93f207c4ed11a5d3f728ee6d9896067fee54984e2da9958fcbd56fcb74c685c7ba26b70ddd41577293514f37bf71fe8f7ac84378d	\\x0000000100010000
23	2	10	\\xce9072947481ab9c3bc04e82bdb0a1a11d3a2cb43c9f6f22276df9f7f68210827bd3aba96338e436ccf348cd20746a4226c8f0b222b1b680bc5a9c870e8dd10e	174	\\x000000010000010037af40f5464610c46f37daa3c0ba9d56caf76b0b7b541debb303f1c4486648946d426a22109c14c7b2eb409d005b921684563da7caa9645d57983e28bf195f87f5043e1aab42bab6a6f601482dfed83c1c89bdc4301f656147d05c876587aa7f885eacdb34af2de0cbead738cceed6046c7606a0d4f48b1cc5cf52990d87be78	\\x6f27ddd8ad4a3a246d53bae23040dce50cce8e2e47f578974fff03e0db826cb2c53ad10194b789848ecf22df339defb04b4bd8a43f5cb87b44ea77128d7b66e6	\\x000000010000000131de872962269ddbd5bd2b9fc07c3f844e948f87bc572195bdea284e7139a9ab7797f3b62d462a8fed27eae861fd9a2f2d122debbf4a113d3f21940811e98831103afe791d9666dcbf1730a566ae1a774b9ab2286c6ef78f7235726e04f91924733660ee96bcadbdecddbd6eba48e7837c4951a8d31e1a4105400a0a41fe269e	\\x0000000100010000
24	2	11	\\x96401a36c6094d47687510ed383cdf6f232306ed9ced2091b6068b6d14def3789379c82ce3ef3f7dd3d14ec98609bfdab8a3f86a2bfdd7a636bb59d2aac24b0a	174	\\x0000000100000100118b004ffebb4b2414656e304c891092b212cefd9f2f3f1146e6ae7982b195bd62240504e6e5b8fba360df8979424ba1e2118b0bf6672e239bb03ec8df2446de8a01571490cbe56d72edb9abb61ca2e1daa7d95491b2a74af776352a8d89ef35ebaba7b63da5e06da7001f8dfb6bcd90d7ba91c1c713bb40e2f73df926e16e58	\\x620dd618c7b3b45a97c4f0d30bfee7031da7ccb741eb36925a97a7cb7db2e75ee4ea878c979868c936e1428cd6b934f63f912503aabedf88efe1d72940f95590	\\x000000010000000190b252284131c5caa7cb1fa76c92a1ca27e71585df459df4209170f08cb9ece8a9a1323cfb2935b797494ce14036e76b09fb19ab922fd43256e3fa507b9cd154b8c179c03628be436bf3fb48960ffcb30aad60dcb40d6177a3f994edc34dc67fc85e58b64d092945461e0533e0fc6e342d2f7df7c34c1c0f53cfd6725bf6a26c	\\x0000000100010000
25	3	0	\\xb9c2c3a80fb471f8ca9337e2a62e4192cdaed91d6ebee73fea993732dec3cfe9f99bad3cbcc17d3dc40f7519bfa0debbdea70683743cab4254a4d88d5222e60c	116	\\x00000001000001001a3a7252a5ba94d9a476adcc95cd746b339f79a44d081585c5b90c6f2cbc7aab335b128aa003c9c935c5866439bd2c0c672064ca712e30c2df9b1c0a5c52e7c146642a905e719eeab4a66f6e29222d235b7a738423306d721924529fb81a955e2227641e181df754b6774e19131b7c45f46b26a1fa4f5fec6a70c374cba2368a	\\x59869ca46bd7890e3ec01617db204e58bbc1af3a7120b27fd451e17763615ee6956d5d4bd6d26631243b82eb4af7991991ff831e6348bcccfd90428a2618768c	\\x000000010000000166b9d8cc785d82f4bcbcd77e71b888235c64da2d8915d561861cb5372f6e86a2a3c0f46321e4eb259bb9357240ff66a4622f1663f9c3bf7d3a96c1a68769cdd7f16197b5df60d580bc1e66e3f7caa415a1bb2d3b81124573e8f9ecea599ac89c6ecdab22c38ea6ac60b2b31d06a67d89f2f3191a3bf55597b72ec154eb130668	\\x0000000100010000
26	3	1	\\xb22640e09bbdc526e10633ba77ff55a27f9360727b0036db727f4af2558eb23f5425d0568b8ed79421c00f7e33058993640017eb49268e94aa60c77b78e8f80c	154	\\x00000001000001006e37dbd8335884160e00b99f8dbc47d2746068f84960fea7b9b56e8c4b4c65efafa6144a2a2c56cf72417c3251af274fc9ec97934e62f820c7da4063bff61e691888426d039bdca591cd29e81fb7b1f1c124d84675136a9cddee8ab2cb1c4df18af0027e627b99b6756cf54f69eebf0483656cacafa458dde266471ca53336fa	\\xb5d779e858668434bee7201fbc1c8c260b81a0eeae3c1c521fe8407387480cf2806e7a93dcc5cd64c38acb862f4a56e8863244764151d2454497ebb332d4f206	\\x0000000100000001ce66d0acec028b4384b4bd4913add4eeb6c983438c08c666bf04b6a84aa7c9ceb30bd0e65de6a4a7605ce37653c197fbbb1172ce3d2cdd075fb32857229586415823bb9b8e59c06e980ede37a92d28b2f41bfa34c306b937cfb2eed1c1e772a3bb01f3faa5797cce4ccebb5648396d7955660cac828eb4e2f04eb2763f12b54d	\\x0000000100010000
27	3	2	\\xee770cef0ac4f048bd7b5a22d1f3ced6ee162540cc213d8bde1cc854f121c096de6f2ffc274f3a5c4d129b12cf4fb9f2e5bc6c797a1110a327156ea434438606	154	\\x000000010000010045b10e385e7553e7d069c5c55b210ab2b252873ca4f2a874bdc3370b7f357126c6e6a7e22e006f2dfab689e1367697a02883b71d484ee2c5545709ade2ff7226f6bf19ba6b0e3f23731eb4e4634a8d69104eff03248b1df49b4c074304cc9e79dcd72bfa4403e59bcbafad72e6bc69a739cb19096391a485bf4a7b01e4b041b8	\\x539e2dfeba393a3352960e65e5b67ca934da2425715cd62f26cd7c7e5875a1439a609e921646d6e6124129a4091d18fb1124e15de0f59089b485e790e6974915	\\x00000001000000017691cb254b13cbd4461448663eb5a09e54d903b09d947ac18e1ef4448c0dc8573499762126717a96e22b5fe5f043df9d61cd83eab9e7a43783eac2e5920d94d2ef7273d7e9a1134ef765453f548e91b423b13998ef8f865841c2fe013b5b738befa8453a99c2257f4051eec1242542487ede219359eca9e2ae0d704b2ad5444f	\\x0000000100010000
28	3	3	\\xccb828b4ede8aeb13abe027608a8cc355d764e15f88c658b74a94f0d8be705f5832b66775facfdceed282b4f6b64f7739abc29a94698fc1d3a5cb056344fd305	154	\\x00000001000001005ffa104e1ab890ce17342946044c139a59410a74a18c446d97c6b4557da7086c3ac4199337d6583d177dbaaca95ebf18633b59c08c7c9aba43fd452df866b0abd0b3c3c2b08bbe35d91f71321fd76a03be7c762b52f9965232cfb8744839030e0e6b79431f026697c9d4853b52bd3653e77b4337e6c05b990595f8eff62351f1	\\xa2b0bfacfba1c4872de7ee2cf32ce6596db86d4e04890aa694ea93f5a58b394541522892bee635b5091fdd9978d2e4615dfb4b28911059f693349a44c4b61c3a	\\x0000000100000001a1c86674557e0b1692812eae928b4d20bbf87b16922f716ce6885f3f3aeb24e7230d2acc3507c883ea362ad5351c5869a0101e4aab73a5d75c7493f9a725c5bd18efa35602c4a63b50cb27c68f477622ee2266530f46bc45bb8de9fd730fad128d7e94470afbcbb85794438592da23fa27fd08ab2d8c650be0ef6f6480da83e8	\\x0000000100010000
29	3	4	\\x56915390b38f002d6bfbca52dc467c040a3e2a2eec616bbaacf3fd010020ff52ce166892743e37d7f0279d092310c8cf3ed1f4ccbd1fabb9d988146bd0553a05	154	\\x0000000100000100b85fde8044801d5d2ce3daac4cf821fe38fb7c7b173acdeaecb7a172117391aabc074ddadb7a4a92ffe6cc33b3bdfebb4271dba53159e163a373e4ed148d53d9d0d9e42f33ddd8e4ca1fc4098b1d0bf0641506d9e7c9da0bcf9a98a5782a87bd801412173fa5c219ccea92586d9ee719bc85e08eb9611d951f847b882100f3b1	\\x7af7783c27b7721b2afcc5620b56f3f978172a474cbcf2cee8d3abdae1b7cc7900487cc35cc6bfea8ce8a0073a51f63d87ceca009c64fc8e168b29f26ebfc2b4	\\x0000000100000001139d2c20ab4aa3a77e8625472ed2ef9c7617b42d52d8d570502af476b686e0a5a0b9e2f5365ba764bfd8364195f476006fd4644513be7931547fd284b5aa6c26fd96642b7b446a35845ecd086f141ac9963bbeb3dbdfe6d316f435b03e69e4d766f1bafc22f75b5d9bb6155c019bed9744758f3cc13078c7e7aface954f7898b	\\x0000000100010000
30	3	5	\\xa30202ce20c55c0ac2624924ba5f0b6498434679e485bfdae6a970f5f53d4650440c12fd2bdcc6eacfc268881cae565ed0cef99e98e47631b7bfc6758d6da50a	154	\\x000000010000010056e17ea6adc0c4d79b42a0306d5ed31617c04473ee1531c0ce0783eacda8db4ab99e18c9f051fe21d7327a19f07a5ea3f3735ceec7b6d92abcff9715ace36d15abeee4755cd5ccde5222dddc66fdd254b33740ac0852101e909aa989430111b66d3a50223073468abc1fcf74abd892fb24f9d535135a189fe3a83ea3a7a02100	\\xfb683cb185014cd13660df1414e84f74361a8dae120693b429f99a2089ee0ec80396a5c2ba2c6e3d6263bafe7e1fe16b9af77748b864023ba337dd45d7e3af4a	\\x00000001000000015b517a3786d1df05376316257143bcc34edf63b0cee48572722f85e53eb3d4bb19739ef1650494dc9e89acfb186cabd281e73626ae0a23a5aa0914cdca38547080a6926ea309848ee14aca6b8a2137bfacb228ef0e999eb21b56e8b848ca0b97ce5545221ffeb2f60c65560c93fcd61f0d3b4d51533f7c9f7da3662d3a855bc4	\\x0000000100010000
31	3	6	\\x23eaafdf7b1e4c08bc2cd3a6f4bbb5c9be4913752dd0881dc77e24d06253b364fb3b86577dcf9122d5794265c25af48fd5f99c1554db27e9ea1004144b19cd01	154	\\x00000001000001002fbcc1d3b6c7c0b7ffff277e65e2c739c8c55d42cda0f846e59ed51b22638ec56b3af97800261a28da0875bf4658454d21c9e76d799e6eb82f7b98b20fbd3a5cd1f2bd4e6616ca4a8f6d03ad22063a3e3ce0d88462fc5a6d15ae2fc64e874a5a6e7b31128f58b54bf55645091c9150c94525577cee0a007e4852f40379946bff	\\x0492eda3e6a75554de2a5382c5ca664b2b103d50bdd5e29dbcc704407d3041e12d4063db61259eec5dea589c9d10eeb34509ebedffec1577e25ad54834dceba9	\\x00000001000000015e7fe08dc3834a68ad7f1df374f5e8950bac4691b206fcab46ed550d40c1b013e7914faad3af228cf4546c3745d62b8e3dd6cc0f7c732cdc8c0ea47862ead49f621039a6909f1765af59e391fdab44fc15ba70f6b2cd620a6cd34f203297067ed76442325fc523257525add3b726b67f6d7c299101c54a2fa7082895fe68abd6	\\x0000000100010000
32	3	7	\\x2f0714aa11446c359829ae21787b9d5d92e15ca43f887f2a6ab5d1606070d1418dc229868aa5444c1e452e33fb06039fb723d01a83df4c3d8ef76538ba6d4a09	154	\\x00000001000001009e33028558037a405edc3ecd887adf4cef5cbdcd3fbdbedd277b214e912f13f8cd18a467043e68dadff80ec5d993370dc2e20e8b2afb0ed4016a2546940c55c9e747396ba21ef65d72e18caa218d5da2002432d70e29f006e580cdf9650a0feb31cb833faf2c79b43d6016aee49b5975cb7241a0e87e4f1f53c7c09fa04b9c1d	\\x713902817377b2cb9ce17b22e9ec437838c6aa9f24443981036e720ee4587a0b9bbc2696d5b9e0921034baf7373b8cc07d88f83817a60e9b08fe9793ba918618	\\x00000001000000011f789fd2eaf9145fa67e0242614ddaf017f61b9ec2b4fcfcb058a6124bd852479069f650f28cbf42a673f8364cdfbd4b3e8fbe92404fec4b6c88f3a231be122daa921d2f6b38c308d3c54d3d58192ca43df98564b94e90a87c4bd17dddaa157925eb124e489907a9be1942b4f8de3eb6738e4025268c3acf8346f07dd17c8d32	\\x0000000100010000
33	3	8	\\x8bc5ca7008754d35bdee63325b45056ac8927b37baa295b3c0dd0f83aea4237b3ecdaaddcda61895b354b8f124f05bed07adfaaa0398ff31b2cd40cb65ce8202	154	\\x0000000100000100c4c812125e14d04fbf36c8c1ead94e91465db867af8b16835a0632ebd78eb5d0203868569a8f9cb17d9ca498e5f610997b4499aef1bfbdaf67a40f7e351f4e210faa90a46189db7680d301bc132b25011e9b1eff74d7370a3957eeb4c6337e8510538bff2ef6ccf22edbdba16d50ef51fde69d5352ba766c0c560e9c975ed0a4	\\x99d8f9153326e6fb97d0422db4949b20e178585f49e3e1501f99ae8dc7c4aac04433cda1cce1f6436883c3e47d7a2a72b8659518a3c06ccc5d64b3cd0c311e00	\\x00000001000000015823bc204568c0612c8a3e5a4be8bbb3465d72d7a248eafc23ced5a554cd66bdd6d19260449f6b23be71bc9480a356830667bc8008e3de3e07ef68ea4e9aa670c89fbcb13bb39951e0602593dad6ff8876447d74f6b719fb5a75d054145564e402527e633b43b3ed38c06da7248ea0e1ff17e95852ad93d4d69607471a3b4ae2	\\x0000000100010000
34	3	9	\\x6c83415aac3e6a82200502594dafa0d397f530772fe9be5f0b84036dbc693192a2fd41057d198cf3c918776df14f8fc0beabc082724a28d2ef34ae36e93f330d	174	\\x0000000100000100995f6b7947a61eab1019b3913d23c0dcd2b65a68175ce5cdafca411f77bcda76d74d9dc2671d6c622b7e423c6f57687df71ab8f9f81a8eff55038491f0d8b25236708469c206b27d13f62bfec2ead10866d5d937892013652a1632123b0b1115772260931710b62b0f0bcc017b8dcdb3d84979c0b4d20fe557414c7ae49d0b91	\\x0f64155bbf637b87b160919a104fc19398ed4e559f5e104b2f56fc898a24e75d1d0ba3838f47661da9634a9e3c8c775de9935ea06b1b699dbae0a3290a347ae4	\\x0000000100000001cf709a8979d63ccbe4c36db66eef6aad1a1b1f1cb4ebb08aa51b3bc6dc2e6c33100438f13ab57e54f8837c163a7891ba28cb2969b3975dbafcfe67528349e61a05eec26c5b897e0c5412fce2fd86da0166233b7487d7401293ba693e38725e4b95a530aec5862df7a97fa780c673b67b7d01185568e434e026d1690c4e42ae0e	\\x0000000100010000
35	3	10	\\x55e49329d769506001587a837c06710a7c1f79079ef9b10e6eda50e8e367faeb2139dcd2c9d4174a1c04533ecbce2f3dab1b1d00f869c84edcfe294e87b0a503	174	\\x0000000100000100cd3a2c2bbcd84232b43e75dbe970778cd3bf2d022bf0e6a78e44c87bf01760d04fef4fae188527ef75de6ad78548522897caec7f92d66216e291acce519ee6eb05c1bedecf67289a32a6055823a99bec1544d1ecce0f5c63aa2f95d7401cb43427ea90f24937db9dbed8c06e3fb22a2d9e7990d4b6619b0fbeb598842acc08e5	\\x128903678a407c66018d4c3c798088655dd432bb4a08d8f5d6d132ffc50d2d18a92c0315df063ddca52e5745c650b6221da12b1787798e303a92609a167dbb50	\\x00000001000000016283f3061d944b6dd2d9f2bd347fea47b6f4908e825380b8e84a1d011e08ea8618455166720091b6748ab8189376249d92ead1247d023cf678548c36a67c6d9932212b6f2246be1f19f56f8af610a33a424ed57fee6e3e15109453a277065ceda205b6df07002dde208f2fb4435a1e14a4abb4f4260aa8a98a1c2ddf7df9dd39	\\x0000000100010000
36	3	11	\\xb855d4a687cf83fad8dbf2eeef574fe79b778a923c8438183a752ce946f7e74bc111c34f9295695dc561b7783f0e3d9db96136d458834ceb351c0df933cfbe0e	174	\\x000000010000010026b77139b61273b0c991a8ac1446b08c11cd4b5ffb36813ee506adae6084a940aa28b7440f9ae5f79b76e6274fddf9a7c88449292210a746ba32e1bc70688def7b0a30f4d8c0d59063f7aae6bd2410c2b2a332a2bb9432dc01cd491facabd1269c83757a665e45ed5f13d1385c6b02026396a081ee3c798f1f0b8c542771cc6d	\\xa82d24f1a797c823a1153e6b726f5a2bec1ca3fdf2d4c4276fadfd44bddf1c8e8cd985dcc7aad215a74f06e1cc7a2a0ce0b170deb16fb18fb62b55217b4e5b6a	\\x00000001000000019fecf1342345bf5aebfe413158daef3cd58d9c5abcd7b35dab6ccf1f75afe613f8b59c26d18889f75925fb5122d029d4ec8ca1f054b8d6f9757e95ede6d431145564a51f99090dc13e94cbcfb3c97a682acaf77c9ffdab23bb79e68646124b87bd9facf0cc33eb6ec9b0d4de0b04b67f559473072392a74629a87e792c342cfa	\\x0000000100010000
37	4	0	\\x24ddca69f93a982f33bc915c97cbe2fe49a319957f651fcd2df36fa28a0d365ed648a7f61c12ab14cce7f967847f1902c6338dd418ed5b15e6d275feee81b008	310	\\x000000010000010085e4c01e4631ff8fbc44a86c78f84776165f14c030fc7e54e01f38bf82d4885209f7c1bdaabe93fcd525a6d342708333615ba942bfd04fce39b987f150399b911f156d63b06b1113de3ea6816fb8e446571fd85d5d71c7d650467d98f0e80cbafa6559f327e6e18019fb2f4a99e888f24a74a2155dfcd895d82595095c034445	\\x0b8dc6829acfec0491f110f4e01e98db8a33d4c00250f4b047755d00cd062ba38e6fb204dd96e848a3de43f26710dfb0fe374e638d4ceb919f3f551e11590010	\\x000000010000000175ad21ce0d6ab90c521da62b47b17b92031e544647aeb15bf55b49e4b663cb86b5b566ab67ffbc89e7a28d220ab450cd7efe1d4fda201fc7d826d7825a35ab21301713cc3d44e9132697a09a1bd7b446b2642535e3773690d91889c1212dc4200202ed434de66a15e20e831c2c2f4cf62e863848fa4d47486582c8b857ff9a10	\\x0000000100010000
38	4	1	\\xf85a48ecd2c4dacea0a74f24cc52a27664c572b01cca3a5fbb886e63bfa03306dfaa77d0669992d29c2aae026f5f1375b94e2dfcab2321eac5386b53e6f9210a	154	\\x000000010000010004855c2dfab0f407340d5d08628be47bb4f4e94df7f460a38b1da3fb5050019a54100328d4557fb88b7b3fdf11b0fd25343462a1003261ccd4aa2a113e2730a1d3b8c0d0862bfb5c71445604aed7e34d5bf54da99128602d00878581ed10e01f2f440614d8aeba1f4a1d115b86967e302773011d888092ecacf1cd98eac40706	\\x276c0005654a109db7f7d58b1eac00cc47d776ade37e5367a9f009ec9c7a10d476e6c34b27b72fc54882bfea31133ed44770bd462835801c31d0731acd6a18eb	\\x00000001000000013d61a373d2b95e6f310ef6989483dd66b843be0c4cfad42d7744699c8e7482b5ba3b2482bee6020a35793669fda9b06e408910ce883411e3fb6a06405b09e8ce633b47a1174274e4c31041df3bf3302ed0ee914b46c94e4eb6da91937775eff501f42077e94734318056324cbb9fc767f67df2428b68799511c6f00fdebdf84f	\\x0000000100010000
39	4	2	\\xb87c1552bb8e9cc99dd896125a9611087deef64d13736f039369578444ea5aea9b63b952816b2470be69bc6dfc90a914fb604eedd64afb3bc78e69b364509803	154	\\x000000010000010040b61e145c101b0c91626817d2fef63364aa870ad5c7ea8633233e318444ec45212c10c2b438132c60529670eb21e7eff22ed7d0a9c729ccc31de150f528fe0917d1eb80253ca115dc57715b8bf8f46c7f0fa4ea78dfbb15d8e098de10d7d440fad1fb2e47ed385ed09ee543f1da5eedba2e228ffd70f9e5ee59aa29003b4a03	\\x368e6f38a410fda113171de10d53e557a2fa5c2395543e336ebdd300ee86e0d0878787bce2c7f6be8ba289f37f266f1019e851cce26d18ca0c8b21e855462360	\\x00000001000000011fbc79ebed1aae9d05ba75438e27571f06acc7fbcbd9b34c3e39033b6e91309d6852020b3424fe7f10744326bb85881231d6fa2ec1ae4b6bca152cfdffe64308f00836e6e6721b137701bad4f8fbd66c81b111001ad7c79f75c248a6423e3bc5eb27f682f0e67dd1bffa30a3ebf5a43f292091b6b19a78e89a959ea4d1890aee	\\x0000000100010000
40	4	3	\\xd7b97333a3a386142a09682f8884f8d58b3c98bbf73b9b55fed9f8951681c2cdcf04ffefbe9516c9ca22726a8e435a068c28ea3a40f7e772af02baded97c530e	154	\\x0000000100000100a5ed22e9cd63830087aacf08ad1d2fe3fe46c5af58947cbed116eada6b19af79fa8249c1801de226f55536396e10d2623883a7543dbf3d2f5fdd3efbe3e3bb2dbefa8b28f42ac5dfa3071968627733fbc6fa5184a7d529517a3fbf822d88002752e5a4897ec2cee7b200562a727309babd76c794aa23b97c36b50b8b4a63ad08	\\x34b2720a40133effff8fe5b4c144cfc6610667e683b7c64f9e56fb29070ac468dd101fe23c26c5a7feeb92945a34b07de2ab86121caa747261f0d92caf1d2e6e	\\x000000010000000127e20da92a0e28ca10919fcbd54f7f23c4d886678268784b99ffe404dbd52a5e79298417834410e19162336911f85371222d717ed69f45954e2fefb8e628afabd2f690873ede2912add8f253bad15fa8ec9b8df1ee1a5749eb98123af2d98b7e0a409989be2d5e60171907c7c46daaeb710dcc9ecacbf3e7953fdd0b44bd2967	\\x0000000100010000
41	4	4	\\x2931a9d8a8c7b481061421bdd64b21e202d4115efedf1e5cd272fcd7c3d4fdae0058b4771fa00b013d3a55cd88e97dfd49293ac4764ac501472c82364cbf7a04	154	\\x0000000100000100c960213ec4b6f0ba8382291845d23f3098d0d09f4af155e2c58944967370f746c28a3a7c00b3a180464e3439e10d99bc72d11d3f8c3b54233ef0da7bb0b70589dae16fab6b4649bc838c5898357d5612dc59e1ed6c30dadccdf76a4dee4934e13d745a2ad7f2885ff89b0b802b96b09d28f1059daa8e26fdd1c3c5143f7f136b	\\x99d8db010395e3d0de910375cbc92f9fcbc472d391c5b3e1c06e4ed77f6aaff8163c76a68d0e6d4858e64f31cad0e7c804900007edf42f52810d2f08b1ad0212	\\x00000001000000018c189a1980a45bf399e1fc38d922eea6e819f7d639fa1b2048cd5436937c252b7e534cf31be49b2493a749e3f0f2cebce8bbd4f8f2c79ceffb1286c216fd4f4732f39ad74ec07b63dc7de1c01980e19212d16b9639ff56a32c2ed6322ccf09949d50fb3357a12694d597325c4c2ddeabfede09e96cca40c0157d1849be05c8a2	\\x0000000100010000
42	4	5	\\x7a60fbba5ec529588cd5f4e5981a4a9e5860cc34419467f17257341208179313534abe0aa39e5e6b009cf458abdb4f34a1755517f3be33e5573757a0adbfe302	154	\\x0000000100000100c2a03aadf6731795fc3e7a232744c582b54d740b24af721a6948c1cb23eb9dcc275fa6299503a2cba12686b537c0cc6d6cca88f057bdf0d89a33834f0918e642d63088b87dd9f0d546eb2918f5f012288722606b030e2607fe158e2d934dde6d15767172dc7b157b1558f60000593a26f04187a6acf6fbb72a6c6ef1407eaceb	\\x616429b3ace3b10672bb44596a25d6439619b078ea037251d9f97041d5e480c813ab5b38ff54df111eb9ff4c90099e4da63d12684f95de2d4686c66ca830d71c	\\x0000000100000001c2e7983f8505b1a350319d2aa4f7911d4ee31915acad52fe5cf59391b64c556ec77bbd55dd15417ab2b91f9722b04ca2d2613ade2253453feaa2a1b994b09be2bff1c0b3f3e7ba2e5939b40d5dea452a98bfd2b99f46120e07ac1b2b510ebb1a12d85e5aa37a2286e1a879215a0a971a3f96a693a208c6e9b4372641a5efa574	\\x0000000100010000
43	4	6	\\xe1a161b3cd683226cad0045dcc7043b84e5f92343736457e05e41b4f60a3c0cc8a196f0fcb7ee92837277af9ab7a07a04d24e0f8c3c9754f219c1e4f7354290f	154	\\x00000001000001007aa8342de9c08e23848b0c14a1bd7f40da5d24643cba323c8fdddd137f53fd25dffd7a530e9639d9668a11c3102579b09779661580ae3e0e461473c2106810fe37914bef2a33088d83324a57c8c5945ab52c8418353947391acd6a75d2c2f736e6dce3e3530ecc206791b16773351f312eb4e3e3154790de7735313ab9007f73	\\xd33d133ddc57428392545dbeb76234720b19eef51e27405a5e03d12197e1b553024d83b412365108ea6f4fab25c975b0ae308b77348aa9d7d890046e374fd618	\\x00000001000000016fc608f7cbad35207e7d6f28e1f05a61e3a0c0a23b3d95b2f3213de4bd6543c7b93a247978a4a23f95247c47cc28409fb4db674caf787fbef15ea4e0475ec6526bc30dd208fd77c572aaf47165949c43a3f2e971b86d8e20ed64417f319039ff871ce9de8ed45d78bebdd9d1848056e163c0d8a1692326d135111ab880c541a2	\\x0000000100010000
44	4	7	\\x5e54d48d973b40f68c0d19f4fb47a9b375fcd14b1bc8dd3ac40f82f952a41e9d18b2f3d77199ed97ec2d4223828978d5eee2d3e6c69522b821f545207e04d70f	154	\\x00000001000001006f33c25fcf210745f111a6f94bc9d48df165e062e6c7523378328f25f7c84a171a4a80f36c80b99f58b30f0583758d2bb87f7b67232ecb43c9cde27f7a3323302428fb127a13bd1d0863baed792a4644c10b2fed02cf1eca0a59d0291d22761878ff924308b04e71f65415dc6b41116d1f0cbc8d2f8259c316507479099be026	\\x5858ed86f8c8c72867b5dfe67ec1f9fbda64191b86e98fa74d97ee02488b32371de1d350de73b8ee3afb0bb11c11f23d7448fffa10bd1cf512c02250ff797b71	\\x0000000100000001b3713d792c31caa7d92af255c28d2a405304e0c67308399b511a4ad5da4ff87025762555c5f65b1a298eada97f6e3b3560a7837f7490a1ce927f76d67c57d37a5eb5f200a2fd47087d8fff5b3ae9e93213b8afb3e1e2b23e22071c74d05a283a6604d7f7925812dc528c5d838205fb140a780c94ee947130c08a4404681dbe7e	\\x0000000100010000
45	4	8	\\x0b4e81b7450c74341984ece1a6e153a185eda4b3b876c6b2e190d2ac62a45c9cd6948f0e7a9b4b15d74e2c75e25429b2b145101cd0ad5716ea8bec39d3a7010d	154	\\x0000000100000100a1b7309f715c1fdde4e118530b66971827e1b089de789f89fbfb910644b4f9ff1f55e13118c7f8e036c66f69696b13db2db5c4a0e3db4e9d5738b1cecd1b59bd4481dee1bb628386552f26f52a69e02ca904d7dde3cb2550fc29f70780a502000f4a054fb74f5f7bc545c751ca601a4952d03e37355d34c5cd1919c14eaa702d	\\x3308649ed8e6ffcfe1791dfb68be176d38ff8d0dc43efac3a83f2d776dccc907f66a3f84065459c58ffcff16cd5945cafd03843967ffd7320a505526cc662fc5	\\x0000000100000001acb0c27bec646bbd81cc0527053f3d280be335352a6d27f739d80e235575595b99d1994153d1ec6be0e684bb31999fe2efbe74b250ec55462c8dc976e0e81195767b2da205536f967c4876df723eb267c55871eb3a0d635a37ec53dda18a3baea1e0bda312ae0dd30c765746ca1ee85d719bf26b62b572c1305fbb5623ffb850	\\x0000000100010000
46	4	9	\\x832dbcab011bfb3feb915747ea076c4916c84dae1d0e56dee8650470537aaa6a996ce559ca565d6241ca84eb1e0ea13ea299865d7cad849d035b612285dcb802	174	\\x00000001000001001a7e0d2332c5b2aa991329d1ebf422fc900d63a89d548443ff3bd985c4b6382c7286d9b912c5a4b64ee2ce8c6dcdaf6e164f81fe343e478eec40f5e5f26adf320736960ac7cb09559523a56682cb0cca8902456e0f3d4b97af6585b18f70dfa5b626767583f3c14678dd4c785ee3620e2ed5fa1683cf27c2540abb191030b74e	\\x1b0075006786e5dd6b7f0a58ecbcffe9402cf78dd29e9fb8c4dfddf2283ab5b66e021c1ac363815100b097953672d18a491ac1c87de339252249ec755e613421	\\x00000001000000016d61a6013d6b87faca8a1bf96eba65fc93374394234e5fd91e8ec8a8b8e18a72090a91ef8476d81302b5668bc9441f4919e34c3c2bf9ff180423b14ff45f074c12b02986535c04210bb440f8017f015489e03d5a46f4e77bda05ae0a6478221fa0fd57a30cd8005e68644e6928a42b305327b259252968a8c740fe4bc92d08cc	\\x0000000100010000
47	4	10	\\xc9bbaccd18b403ee383f5fbc7b0148e7e4cd4edee711cdcbaf855cfbc4b4cf543120d1d202e303ee4b081a9e2433e76ca37d8f8c407860f2ec72678c6848330f	174	\\x00000001000001004744861a1c33cfe4a843c2132de09c6d394de20db3fe3049a6cb0d17159b0c9a947fdfa05976ea8deb75c294d3908f77db810855b09658224cfed931393b978f8ceb96fa03fcf432dad059a7878e2c7ee1e527bdc0a2c29a018e907e172809b9d1d8fcbd885e83e781ccfbdcc158c4ccbc837f3dcd5ecde716699b87eb285a40	\\x186683ed7cc3d5fdda39d8e30e56ecbaebced49be3b5bbe805aba2e6f220a64cf01d6cf9c2cfb26510d7c04ab6a3306ddca557c66c8a6096edfea88f2b748735	\\x0000000100000001817c114abea78895a1a4abd693609d2e498365a22ed21feea3539b01203a192080a2450e8cc73ec12bcb8786f8794baacb3f9e3cdb1c3fab03f59af5dd4e3a72d0e17a6ce76a500e91fa6a0f17a3d6abdf2d17dae25c1730126070d395a1f8b23db3129f157ce57e9a9caa19044d2e8489ba19618991164d9fc09ba09174f66e	\\x0000000100010000
48	4	11	\\x8ce132d9081a37677eee9caa4eac345aa05d7185f7b4aa16f4784073f1c217bded42f286ee0717eef4dc2c03b623b2d5abbb0ce016ec5212984c37b323f8900e	174	\\x0000000100000100a7fe96ed3708dd71b44a9c360ff5ad33bb4890bb50c2873bf4465c5d523153c38bd74a7024a90bae2c2092b26344bb58d5d834137dfa47118ef9a793ee4dedbcb8b3713aab13a028be47ab559cdb46cc6e0ac30dfab126a0a712cab88344dd4cf79bf9e5af38e30037fc43a6ecce65b435417c9cf9c7c0abaf67790f8997f525	\\x106be279f3d74fc1c961d9876a7034ae8fd619139f10ba3662dcbef741978d27f21323a02e1787fca5b5be5fe8823fb74187052a99d50bfc2ff5c73692b7572c	\\x0000000100000001b4466473c24e1056a3a32117dc8cc6b0b88e126b71b859f3105a9581f7f8f6c06b411a89697586b728af7ae83cec7e32aa16b1776072a1048c49c72a7a590ffa2dec09ca1d5c21f8083f9ffb51c53677c4320a80d953925888259100a0dcc0606f73f7d5e9f6bb7c23a85051df353a85ad04edd9b3bab873e127b4104bf96fbc	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xe7aa2c687f5196e179862913451daf1de87adae85d9b760814647a253cfaae5d	\\xbdeced8fa7476443a8e56e677ed71f8c5df0cd25edc35b86f63ce57b3cb9322092cc0d7feb64ea060e91d0814863d382ead525df5855a63d84e84bbb56fb04b2
2	2	\\xe1a85d91d37ed28299ea79797b1dbc0c702553683137b2771d6a4a717bd2ad35	\\x43afdcf186bb7539f57f0e5f89e1373560dbeb27a2a496fc1e019d79a1f6694f895bc14e82a1399890071aa79a4482f5c3d92bbe0ba5c5b0181e36800ab9f5dc
3	3	\\x2ffcbdb8d26712c9f5097a106422d6ca980c99954a8b882debeb8833a9488a16	\\x6f2b3b0ee15a171a4fefc400da9b254ca1a3f7eea33da2a08df22c16202ccdf7fa10efa0210ec89228d30c11bcbff2fc6b943210bdb6e0d506b135ce030cb3eb
4	4	\\x7c057657f34a59dc4a9f7c49bf84963bd4bbc5bed84b592c3efd87ca18a51a08	\\xfba4680b8d8d889d9ec98fd9f90e676dcb6d893e731de647b802d996b1eff160e795516318b26a68d149760b5fc38c85a46469f0720ed45ec951d37ea2062905
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	2	\\xaa1c3a18b4a43e40e80754783e4857629d489611419c83075848a565c5e7acde0d81dd0f9ea6a1b986e45dc5a4f4b3458aad18111688f9d261d5a69bbb2cf305	1	6	0
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
1	\\x7d2ff72b4c4101cb0c616edfc780bd82cbaf805f06359c852e5e1227a386a3e7	0	1000000	0	0	120	1663411902000000	1881744704000000
7	\\x5f58d30539db83464a0c5cda163d54b29df32f12af10f562db29a14d8fd40afb	0	1000000	0	0	120	1663411911000000	1881744712000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x7d2ff72b4c4101cb0c616edfc780bd82cbaf805f06359c852e5e1227a386a3e7	1	10	0	\\x0eb8056c99178da3545a2fdb46ffc41e51d0e67849270eaec69f011eabcc6524	exchange-account-1	1660992702000000
7	\\x5f58d30539db83464a0c5cda163d54b29df32f12af10f562db29a14d8fd40afb	2	18	0	\\x27f98d4f08acdd658b8f16dcc1f04ee156d1ffe19ed1149880c52874b3db3361	exchange-account-1	1660992711000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x94fe87fd44d97d1ae70bf031e5d1476b7e078a832b66e0572df8e5635d4367aa14840f546e97d79eb2dc503b788f241656f7e47e7435b757ca2590aafbac3513
1	\\x6583e3c24091219996c2f60502b79f6153d405cd1e8e12fc6e224f76c49d1984bb8d7764eda9d5eb08f14db107e334c9ac781b140c83283adeee8be9eb35aa5a
1	\\xec8e92b5dacb92ae84386464f056f9052cf006eb021b6c7bf379a259109fe447dd964f8070acb6fcb6a101311bfef29ce0bca51a0b9a6c1952bcb3d642d58a23
1	\\x29993e72b61f134e95aac37a985cdfac926e626dae8282d8b34254978f1ebb14e28dd8c285fcd73e3d409050f11e24f3f6ca437f484cc2dab2aaa3fe5029ba66
1	\\x052d33529aee1faef5a204d8d1069ffb464224da1d301322f71506b556cb98eaff99aa6d6a08fdb655a20bbd6af8cc3d00b9e4b364c4700147641cd4f62ba9d8
1	\\x6eaf405dd9aea91b3ba18e5b17a0e7d6fe6e0eff0d9888babf70bb196763cb5209fc101d044ddb92bd17c6666f1562f9e06a5b0be6167e7faecc8d73c1134bb7
1	\\x6faca450f88f3a6f258e5be596f837fed5e6a36d6c0942ef49774894cf81e9665b47e0397c3c3335f069533c19086e556c0ade76c82ef42d82ef5351724082d8
1	\\x297b6f96b8ea07b018618b5439b612604fe61caf3cea82f97eef32e4ca4d849008a999d876648ac977d87f42305dd1ac6911d644d270d31c60f2003d4f60b356
1	\\x9995c4493398229bc29a7a0f290baf81064def3ef6d82fd96f7d911a51a29061bda26d3b9bad20b8698cb0b9ac9c63dbf1fa88f3938706201edde15c2cb2ce81
1	\\xb913bae26c9c0ba8aa41d627163dae6801c71d01326c0e4f01ddee83a5498ea86495f2d6ef0c1188d1df93d3935662229cb763f7993cba9770bb54ddcf4cc252
1	\\xe03e0066043f376cd9178c784d64db6035de4f0bfbe7b167f59ce3c6173733187daace78d83ee584a2ccbdf55e5818086495b69d4d3f85df30f86a14f4f4a4bb
1	\\xbae5d44185ca92e093ee3abcad987a9cc1b738e4718c1d954c6bc1273ca18bf0279507f6b766970e5b69ac2338f7035781d6c8458384bae19fd8e01deb65abb8
7	\\xe41f0bbdf5ea648bc7562a58dc4e589b64774fc4909f212e69cff392b4afe5b90289b8c40815cb5e8c1e5b3e3fea213b35dc691e96086fde3b9ffbd1cc02f028
7	\\xd67dec4f12a5a498485e873c21a7d0fb5e096d20ae4b20d4aaca8876d3e0ca9d35ec86224e4c889afd48e148ee4a0f54f7895178122fe90490587cb20462ae5b
7	\\x5590295f2205cfd4ebbc1871e54d54487bcec2f334f5f9275b0ef44793fe9c47f63b66972ace61db9349ee045af014115c9d12cd72b60d5742c1c1284194e7e7
7	\\x84ee565e7ea6f29f8bbf5cc0f022a89165c4af61a026a3192f76a640614fc6a00b1195e1bfd993cdb678a0588310ebf866cbbbf226a1cd84e38057b0188e04df
7	\\x2e3704609413280532c88a1e608925eed1c7e539c60328f4cbc1ef05303802f6d477a55a984102bb398726142cd2fdd9414ec6ee207d666586128168c699381c
7	\\x2562b26e3c2683c809f04be8c6462955b04903adbec2378b7b70b44fc3e52411740f7fc4a208c7fa192db59b1cd04b91d5c6b316cdaaeb1c0230d63d5e6be2fe
7	\\xf980eb78f32a93aa14e70f46fc2184752d507a3006f14b3f89cf7bd564cbedeaae79b4f9c1d3690b08f04dcad3e0bf332dfb19d0ccd9180fd3c7ebcc28e5a0ec
7	\\x8262886bff958487013fffc579cb862dbfce7f5d5e4e16a4dce448fc7b681de37c392928efb43b6209f26743228c27419891f4fd1a2db751a71891262637ccb9
7	\\x244b8df79a5110f3b3684423f534a9b9b5d4cdb459fcede49e6bde03058d65c7ca42454a6f8311bb52aefde3797516dcbf99b3fd34b336b2461d162322bec14c
7	\\x6a96f3aad170a8983c565b758356d44e3a4c9d1f8a4b4a0c8e087a22b1a88e62fef8111c709d74285900cc240b0661c28622f28ca46155b687367fa5183f8e94
7	\\xac36d702871fa820e7c9030c3e02626b1d73c45d572afb930a117da1e5fad368f84adf2511346abea62e1b76cab63dc2c97281c330404da7b2062c5711c7d1a1
7	\\x75f123cdcc9f33c53e29d208ae574d569ca62a06e41f92071f0b319c3b72f3d88628529a232a42bcc0b6d430222789cdc8566190b55ca1a5b3ef8d2d28e14943
7	\\x742919fd6ebcdb11710c8084ff73f1fc3de60af2914c96e4b1537e8589892637ca78356581f9b3db778e10e165deabba3b776270c346febdd92ceef445b24646
7	\\xea144f1c55783c58b6ab4d63fe653ea12a7f1474d2e302c14d39b0b8048ffe9c56a4b96e3edb102ef7133b99efb55a763dca98e6c95aa9fe9f26c13b507bd28a
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x94fe87fd44d97d1ae70bf031e5d1476b7e078a832b66e0572df8e5635d4367aa14840f546e97d79eb2dc503b788f241656f7e47e7435b757ca2590aafbac3513	300	\\x0000000100000001951b31741d52d2ce37abbafebcf26bdd1f837cd4d639951e3af3da1416788d94cf30a381182a9a9b02cd91e71b9010f81008347cac258661c3e8b881607079e9c4296af5322f510ca448bb8c58e69c9b8cf9b3dab3e54b9adeb2aa7a728b125e68a309aece8db8c23e396f0caf519b07bf549f757b355ecc3626e11b44dd5032	1	\\xb351720da9269d442dc59887b9dd20c2e8f3ec582165545228a5bbe2a5b67f154bde63e474db1f79d998f06e66ecc4f28be47e0769aff21bfe36cf3b634e7f06	1660992704000000	8	5000000
2	\\x6583e3c24091219996c2f60502b79f6153d405cd1e8e12fc6e224f76c49d1984bb8d7764eda9d5eb08f14db107e334c9ac781b140c83283adeee8be9eb35aa5a	310	\\x00000001000000017a7eef1c996023d02c281c8476f64b93bc29b5c94d7033edaaf6840661ff377b954db8f910282fe5b4939acf62e8a12b148a887493e39a92e8ae78415060790e5be6e824e52c3981d9dbc3c7c7e226cd9a25c6e094b1cbdae3eaca2168ce3c208eb06513f0d1f8455762f2ecc1c1554fc50616a74b1329fcad17559d78c13b05	1	\\xd6ae6672ea03232c058b8faea399c8d82773f14732cf10394d71b65947659ec9cc39d51c93f2e8b41f38ebfb40df698816d9329a2feeb2461a2b3093fd91ea06	1660992704000000	1	2000000
3	\\xec8e92b5dacb92ae84386464f056f9052cf006eb021b6c7bf379a259109fe447dd964f8070acb6fcb6a101311bfef29ce0bca51a0b9a6c1952bcb3d642d58a23	154	\\x00000001000000019a915da29587bbbeef93ef37cf9ca4741d6e3eb6e572232cefd262aa22abca9e42b73ae210bceff9b9f437cf1ef378de5da624803cbb08cb6a7408a88afaeb68c0bfe9b1669f596f52c18132f05e44ca3600a168942dacc838c7aa5762cf6a0dc5be5043c6aae3c0331f2cda53874f8ee8b3faed2f548a06d081a8c30f5a5e9b	1	\\xa21c55d46606711a135555768ae6bf94d59a12f4bb1176614562501c7e186dfbbf441b11d6de194ed923c91a7b04ca5021dbc37d300dcf72f06f20ae59960209	1660992704000000	0	11000000
4	\\x29993e72b61f134e95aac37a985cdfac926e626dae8282d8b34254978f1ebb14e28dd8c285fcd73e3d409050f11e24f3f6ca437f484cc2dab2aaa3fe5029ba66	154	\\x000000010000000123df63adaa611ce1a2ac9a935032be7a6d44a4067aa75763e6db375da164ca006cadc875771c90ff0dd417bc8218e4051b7267c7c300bcee69457c54262dd7f40634a9233dfff7d20e672486ffcad08cc6190460bd161ddc0f4273cedc911e3ac77ff4f1420f4a70e1b59334356c4a21349508d7d6906e3ed5bf8d453fcab4e5	1	\\xd67d3ed26595a34289babb4802f393c55a28e274aacdb3e08e3fbb744cf8c5b6ff17de7ab1411328d1a946f33810fa6c6fe53d3eaaebe073120af1771ff4a707	1660992704000000	0	11000000
5	\\x052d33529aee1faef5a204d8d1069ffb464224da1d301322f71506b556cb98eaff99aa6d6a08fdb655a20bbd6af8cc3d00b9e4b364c4700147641cd4f62ba9d8	154	\\x0000000100000001b818832524aefdc8e815e2976d7de1bb4b707ab1ade81a4313d04f94474942aa776dcb9746cbaa6f7f602195816be1aad41b20f55777d163f88498c41147cb17e97193803015e1f67dcbc0eacc8d45b71fb91b81c7e25935304155120825aa0f1d571a4abf017b8be4557804fb7cff73fdd9a4b9f603bc2c77721ab20336c6d6	1	\\x53d7f65e11385997ac5cab89d4e52149366afe0743673793cd67d3baca1947c1f1c3c44b83581143fbea72b65d5a37000e8f14ac35cd73a5447813abc361230e	1660992704000000	0	11000000
6	\\x6eaf405dd9aea91b3ba18e5b17a0e7d6fe6e0eff0d9888babf70bb196763cb5209fc101d044ddb92bd17c6666f1562f9e06a5b0be6167e7faecc8d73c1134bb7	154	\\x00000001000000017a18eb83114b4ed38ee51558c3f1b706117751e91466c99e870e9a260f53f1e3d0caee18ff17679354f9bc748951aebc53fe25a86b85d31e64c9d086530194127576fca5fe56760e5a452e35b4679cab9de1771ec89c44e0e9ad1648ca71bfec8b41e758dd24ab3a1e14e7093ad63750c8e889d44215295302725f1c432b585e	1	\\xc8561db64ffffa89392cf739a546a038a1704d768916de1c304841a40d841796dfe5ca3ae3e2291da3181ea0c158c9b3acc7fb361e6b25da6a7a5be9da1f420f	1660992704000000	0	11000000
7	\\x6faca450f88f3a6f258e5be596f837fed5e6a36d6c0942ef49774894cf81e9665b47e0397c3c3335f069533c19086e556c0ade76c82ef42d82ef5351724082d8	154	\\x000000010000000118f4d85117ef8239ffa0fd833366f76521dea39d65a3914da5c8af6af4ab1631cccad5891db773f1495c547431f96237f04baf78a90bd12e72f1abcb1255688f01f17df932f6fe28e310510237adb5ca11cd655b357cd905fae3b22745d123cfb514830ead3d57430decc0063c0bfa0bc51bb261245cc04ecfcb1bc3a4c88432	1	\\xb242f530dc0a3ecc1fe77d104b989a04bf4d7995c9a7e605ad5d196727bf3992499e73a5a33facdff9e4f82a386d822bb26552126104a59c0f7b8dc38152a00e	1660992704000000	0	11000000
8	\\x297b6f96b8ea07b018618b5439b612604fe61caf3cea82f97eef32e4ca4d849008a999d876648ac977d87f42305dd1ac6911d644d270d31c60f2003d4f60b356	154	\\x0000000100000001ccec68fd6d86aea1d80403b182e7c89e73073615f9462ba2223f2333e1717399925c285ba0f018bfdb63cd04c68d2315a64205456edc1fa70df6fe4255c81c4e9e81294c08c8f60c8934ad0c85f0001166dd0a9b68a55a2fecc543e7b50a11b24d92ce17870a4b94ad967646f8fced322dcdf34bff958cbac8b7286bbfffad35	1	\\xf0265c801a64a1a43a44b4eaab4f5e5c7c2a7ccb74dad66fd42d1a7481f66255b3dffe33ea7037ca55ddeaf4d96c0c3a23fec2bac0d013b9fe5ed3e530129e0f	1660992704000000	0	11000000
9	\\x9995c4493398229bc29a7a0f290baf81064def3ef6d82fd96f7d911a51a29061bda26d3b9bad20b8698cb0b9ac9c63dbf1fa88f3938706201edde15c2cb2ce81	154	\\x00000001000000013e5d209b78154f7a141e422295848af6b0abc69d54b4ab06c5bfcb7c09aa2d69dd6365ec25862de1f1bf4ed89d02d80301e5ccc7fa6f19de992e7f23c8b3172ed451826f4956f4d01c7a4acf549d4328f6570b467fd82046cd0df24f514dc2c9e5cec1670d0fa7ceaf43a0c4325e95e86181eb3815c54acdd8a084f7fad1d18b	1	\\x61aca7172b751d4bcc1d7432b5ee57511ad6627b42e7f9dd44507de76f5cc7abbd5c37db33858d98162c08a0fe9144bc202eb3087521011fab883a18f0b69002	1660992704000000	0	11000000
10	\\xb913bae26c9c0ba8aa41d627163dae6801c71d01326c0e4f01ddee83a5498ea86495f2d6ef0c1188d1df93d3935662229cb763f7993cba9770bb54ddcf4cc252	154	\\x0000000100000001897aa79d78fbc132ba2aeacd89b5405b5c212100b22f1f4a8b2e4003f9a9ac9cc2fe67171252f12b87d0ce0f05d88fe43b9816ddd003f39e03d3f6e4747208a74159c39aee538082deb92b152ac82dc10b5e500c748e43b5a50de656d19898ce39a4b4ae9e9614752b285291d6c9519f356c48d55502346f0cc976907ccff4df	1	\\xec101adc7e37e98525d4e420b77decd78a5c91554d6ca3e67fecd96a58ed775a9a273581482e1b7c85eb40af9cf45dce7020fcdbfafbbd4f156e23b363393102	1660992704000000	0	11000000
11	\\xe03e0066043f376cd9178c784d64db6035de4f0bfbe7b167f59ce3c6173733187daace78d83ee584a2ccbdf55e5818086495b69d4d3f85df30f86a14f4f4a4bb	174	\\x0000000100000001aa86c6758835dc7da14bd159619255c2948a4c4ec539bcef39abbc8e9e721966f19dc78cc818a12ef85f3d3563cdd82dd747e411027a9965b1d6226c279896ce03ccec6dd0b01c32ee586b6b3eb84bc76f727d48ab2fc56dba5e4633e5b786bdf3757290778c29efe10ecac8e857d9752afcdad1231bcaec055adeb9051ceebc	1	\\xd772f7d4f36d582eaf358c94ef55e90d8f7c4cbee1cff7635ec180405941262a098d106bb54cb70ad10c7153f983209bac98f4044f96370f0ccf2b69613d570f	1660992704000000	0	2000000
12	\\xbae5d44185ca92e093ee3abcad987a9cc1b738e4718c1d954c6bc1273ca18bf0279507f6b766970e5b69ac2338f7035781d6c8458384bae19fd8e01deb65abb8	174	\\x00000001000000014bf53b6aaa41f4e4ce3b87ef25cd29c903e9cb7d749a2e03056fc8a2ccc855c519f287a1fc89c9afa7435b0b6bf9fe819397d2a2b289b90e6ea7647abe4c226edb6a97ac9e30f3852699d659b75551bf129df4803ab2d9542be4b1af82072c032d74d2289622a75297d3f580bb580996f310dcd84fa595d6b64234940bfd34a0	1	\\xc3df217381fb94057afc7f9b921372d339a009d220673730701c4cec80e74ec1f512c30be7e2eb7da400bbbf292ce7fbc3a5d073991a713120260795892f040c	1660992704000000	0	2000000
13	\\xe41f0bbdf5ea648bc7562a58dc4e589b64774fc4909f212e69cff392b4afe5b90289b8c40815cb5e8c1e5b3e3fea213b35dc691e96086fde3b9ffbd1cc02f028	77	\\x00000001000000017812bdd6b1879e7387f0101df86f016680a3da2c67aa405bc773487cbff0bf543da7c853ece759f1803d209d2ce275f18450f57c7bf7b674dc63890074b5bbf83714d39318980ed5bf5cb08931e44f34027b03d895785153e03180a6202b0d38b439778b639707059ae9d18de267dc66830410133e95e6650beb16eceff1e5fe	7	\\xce84c6cf30782acf4eba9b2b73cad32290ddf211b934d13e18200b972f24c5a5b158d1e187e2a870a916e1782cb7459c4aad1b5372a3aeee31950647a5660d04	1660992712000000	10	1000000
14	\\xd67dec4f12a5a498485e873c21a7d0fb5e096d20ae4b20d4aaca8876d3e0ca9d35ec86224e4c889afd48e148ee4a0f54f7895178122fe90490587cb20462ae5b	116	\\x0000000100000001a83cd44a1d0072ce86e46c727af9fe4b2f912e98510a434994c8aa82a250a0d7d7601813290c3ac3d439106dd977258fe419852b067659502d80eaa77acd661277c0ea3ca954952ac27cf62be24d94f234622a84fb0a098df104479010e6d900109dd70e05d761bd034d1925b294713502f1330b977f22684da5f9a470fe7434	7	\\x8908067cb6702a4a79682b3de5d045f2df764d2a1030ab20a96145aef7fd9cd4f3c2ee63378ee6c7ea12a900aa9a0607bc5b5534f5ad514cdaf6ebfac2f1940d	1660992712000000	5	1000000
15	\\x5590295f2205cfd4ebbc1871e54d54487bcec2f334f5f9275b0ef44793fe9c47f63b66972ace61db9349ee045af014115c9d12cd72b60d5742c1c1284194e7e7	196	\\x00000001000000018b3cd7bd7b7d7274aa7deab86a500de1c3f11d383c8c90f0548d77240a6e05a3512300fc72121cdd1bea8ca245a38e718ffc2c01db82c94ad65083f6ffd02df55a53c426ade206fcfaa8e4e9eaae44bc28fdcbf5327a2630cc2c69e38dfab8cc872af3f96a9990ef0403485ad3d7801d6c781cfe051a9913e00d46e0ec8fae82	7	\\x072b8bc2f455029541f6ccb27bc161687e79fa7873cd3888ce77258442789428c5c875c0d5ec63939ae27400f69f62ebe2b7400dad68370bdac6e869d4af7f04	1660992712000000	2	3000000
16	\\x84ee565e7ea6f29f8bbf5cc0f022a89165c4af61a026a3192f76a640614fc6a00b1195e1bfd993cdb678a0588310ebf866cbbbf226a1cd84e38057b0188e04df	154	\\x000000010000000191b711e310091713ee9bd611cb89495ce7e119595dd9a042571233ad4dacfbb7f11162955dbd8f3fe17cffb41b7ba865e8a551a7b72f453b133a7592a9b72128e91387a5f2cae286f10faf55daac3260b9c5272bb034d3ba5e63d8e4c9cdb33a71b91cd3eedb8de72c634d62ec90344f1db04fef78df87b812c53feb3594d937	7	\\xf93364f2f8617ee633996bf4de27a427af01d7350214d50aa6c3cbb088f81085ffda999006cce73668d6e3360ed769c48dc5a4387e08fdb84452d75e5812c40a	1660992712000000	0	11000000
17	\\x2e3704609413280532c88a1e608925eed1c7e539c60328f4cbc1ef05303802f6d477a55a984102bb398726142cd2fdd9414ec6ee207d666586128168c699381c	154	\\x000000010000000131ce4781e9f204e3fb8fedb16972f619d6263453038391def363a154abce776d9be9d4ecc95d3199d97ef7d9ea604aa49a25aa2bd09e769cad08a5e4b4e1295b58821601f82a6020cf5cd344ca76859bc7906e31c6b2bf3fc4e6321721ae3647df0ff59dc0b2fef2ed45f84d04aea59a896e8a68bd432bd3938ca9932d03cf02	7	\\xc90c26e65edbc2ee58dc72bb291ca9b78c7340f1a4211823267f47e6628e6ff50405b92f0c67ec96437d3667fecb3c947ee1441936d7a3a0c9024c1bd824400e	1660992712000000	0	11000000
18	\\x2562b26e3c2683c809f04be8c6462955b04903adbec2378b7b70b44fc3e52411740f7fc4a208c7fa192db59b1cd04b91d5c6b316cdaaeb1c0230d63d5e6be2fe	154	\\x00000001000000011ea8082c5e84b8234241cf8207fe0d021751fd2d90b0c7c49b04e549025228065626ae1e7203299620e384211d21e857d767b88ad980b4d2bdfb57bd21211d16e48d8c62f9d85531cc3064e844d2c2bad25f4d22e9e4fdb77b006544285c8004c49980be9b03149839b268fb4e98240aaea04a7e9feb9f236eb66e359c756e7c	7	\\xaaa2380864d625bfb15521117836180f372699872b1536dd164883ac584d11e808ccd0d92a4934bcc2d477ff17df1d2fe6faa7112f689983961960238ec58d0d	1660992712000000	0	11000000
19	\\xf980eb78f32a93aa14e70f46fc2184752d507a3006f14b3f89cf7bd564cbedeaae79b4f9c1d3690b08f04dcad3e0bf332dfb19d0ccd9180fd3c7ebcc28e5a0ec	154	\\x00000001000000013f6899e9982dd43675ea15da59779c532630eaa5d905ca2f459b598f7c8ede3f0df9bfb77d7af42db49cae4650c2f1ac76378bfb510ac9c4038a4ca62cab8834d561eb13b13eb4b11a2fe8fad9438f5a94e9196cb3007d08aacaa3289798ef6409f7a0ba917cf569b22a63f2f6a616aaf36dad55c731c3d6f88a8a601c2ed722	7	\\x849ac222203bda39423eb128e136750dd84c81f877d32a1c0e9bf48d1c63af220e446e4eeb5e4727ecae5d1e8a4026e3f3923207bec6480250069b2d1fc9f101	1660992712000000	0	11000000
20	\\x8262886bff958487013fffc579cb862dbfce7f5d5e4e16a4dce448fc7b681de37c392928efb43b6209f26743228c27419891f4fd1a2db751a71891262637ccb9	154	\\x0000000100000001bb26f243849fa9df4a0c5667068c0c3ba07ff484a07794eb83fbe415e27f3668f80a929ff565cbbc97f8dc3e77b1c0b2b3aa67466d116e32487ee09f8528945dc72fd106cdda52af17a9f255f9d913b095aaa014c0cbaa6855d59332b38f2eae71621745448dce38adf1b843440229bf72a9f3bad508e5065f9d8bafb0198063	7	\\x6f1e2266e05aa96f52f1af9bf2096868eb82d17519886d21dfdd2be317741ec4ad41b62aa7baf1fd18d9075da388bb9a71db45e0f6869151a3ffebb877d3370e	1660992712000000	0	11000000
21	\\x244b8df79a5110f3b3684423f534a9b9b5d4cdb459fcede49e6bde03058d65c7ca42454a6f8311bb52aefde3797516dcbf99b3fd34b336b2461d162322bec14c	154	\\x00000001000000019ddafd89d7f5514dffa5c60099fec859d226f58ae8eff54a58fc9b0207aa1d359d2d037edf11ba0854eab5a09add204c0480dfdd4515be2bde8993346ecdc8ee64886eb330b70154b7b52afbaff99f23d2db7545d129d1b51ed03c63364d6f817705d775d03e4022e91678be5e8ac4fda082432f9bd7718f8c24d57966a63da9	7	\\x2692a24178a58313746a75acfbcca113992d45f2838c25424b9dafb1b1b4e60a156ca4aef744dff01441c0d1d2650d6a6fb87b82b2f2dc73e6df551b7e0b3d0f	1660992712000000	0	11000000
22	\\x6a96f3aad170a8983c565b758356d44e3a4c9d1f8a4b4a0c8e087a22b1a88e62fef8111c709d74285900cc240b0661c28622f28ca46155b687367fa5183f8e94	154	\\x0000000100000001bd7f6df8785091f1ec56098d38ad1c65c4adc2656042c686e2e9957326028f77294c18de00e4e95bf7ddc652150e88937bd132491c91c7320dcf26538d45ec8af34e24cd9d9612a025c079597208a8706c1ea0c9401a4af372a5e9900c266bfd58c7ccef77a57db583eba10f51fbfe0098f5ae2197553ea49efc00d79f71ffc1	7	\\xd1755fc1380d24aeaaf83eada1e666f4d44143e2a0188294f3dab67a40abb37bb4eeff933ca564ba4c6ab5cfeaeb31a9c8498ce59d1094a77ceaf048b19b5105	1660992712000000	0	11000000
23	\\xac36d702871fa820e7c9030c3e02626b1d73c45d572afb930a117da1e5fad368f84adf2511346abea62e1b76cab63dc2c97281c330404da7b2062c5711c7d1a1	154	\\x0000000100000001bbeb4891369d35d68b78ddea71de90b1a5ac844bd5136d07e861a1198816cfbda52a80f5dde43c032f7ccd077e0a63157c4af706da094e6a01b9bfc30606693596dd20f7ce45237019ca1a5dc0d152e35f9a6c10f8ecbbc3e57ca09fefc438db6c94e9b1f734bba2ca444f50acfdfa7a53687e3ef144f78c156088543b8575b6	7	\\x9e54b7392aaaa7421066a0e8cc79669f45b3d9b16ce7fb22878d6feb18cbf30e046e5d6bad5b62f064a83906714c4307e09de352d7384bd35572d9030ae5f90b	1660992712000000	0	11000000
24	\\x75f123cdcc9f33c53e29d208ae574d569ca62a06e41f92071f0b319c3b72f3d88628529a232a42bcc0b6d430222789cdc8566190b55ca1a5b3ef8d2d28e14943	174	\\x000000010000000164d6caa0fc80c96d5c97c7080efe2ea6ad1c2fda9595f55629c2597483057b7038618efb5d920cf330dd025fc62674436f7c667352ca9477d743d688f8b48ff3a7619797dc5e4962b38e2560f6c9e9807a16fc01bc9de7e039791a06ad72c6ffa2f0452fb5599c855d786ec058831ca0cd70d9bd0baa6dd65b9264f858efe15c	7	\\xa95fc1275ae0c3ea88843697ea9af6ce347ee9ae05c58e09e5ffcff6d78e70cc06c2bbca300ff87c424c448f5a6c194b3c3922dc8e956d1229b3fcfb12baaf09	1660992712000000	0	2000000
25	\\x742919fd6ebcdb11710c8084ff73f1fc3de60af2914c96e4b1537e8589892637ca78356581f9b3db778e10e165deabba3b776270c346febdd92ceef445b24646	174	\\x000000010000000196f212782cb485e309ca9498fd012d1f3bb7dd73d997b2b2dc3257eb9902e3d54dd735016ca305de2a07f38c730e5afee1257f4bb9827baf9e01454b99db576a2dde455d5a9b94349694a2fb564b12e8f7ff45882ecdcfb79a83f201bbb411f5dd93ecf873870a57c8c6eaf3e3c3f5ef73754a7d61f1cadfcec03ee96f2bb97d	7	\\xa7692a3d2437e0fd76b04f9d3326eb4a75bcf2e1182c530905660a3929179ceaf6b98a3b040bb7ac7aa99964fadb521a7ecd8615f2c789ac29329b3dcc8f330e	1660992712000000	0	2000000
26	\\xea144f1c55783c58b6ab4d63fe653ea12a7f1474d2e302c14d39b0b8048ffe9c56a4b96e3edb102ef7133b99efb55a763dca98e6c95aa9fe9f26c13b507bd28a	174	\\x0000000100000001b11d3b0e3fb2af179283cfdc9e93c609487ac7cee37642eaa31c77e302b8fdec23e3e2240c9855980f684ad791d0cb6bd3fb48c550c1716715b66a70baa578a3a3eddcbfd32b6558f732cf6da2bd48d9b34b200120b37c1ba21b22d4f399007b6e9038bceeecf4872a997a7cd26b434c4c83dbcd16aed5292d685e05a6eb5418	7	\\x0fabe7f118de09c9a312f561cd7db107d77ea9a74958f908164007a242b796643cbf577beaae3b72d5b9eee69c7a7dad78698d2107d37155749c0e81b351de00	1660992712000000	0	2000000
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
payto://iban/SANDBOXX/DE989651?receiver-name=Exchange+Company	\\xaf45a4d163c71c4bae46599a8fb85347e521bfdc3d837bb0d903d84495151b96ea024998e966081b41675c6fd00786ffbf97edaa6db2b03e515f858f7bdfce0e	t	1660992695000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x4a65d7a22dec49dfdba2ce66df95e5d66bd240f1e874c9f97764a9f360eba9aa109bcfdd210973914a93a8738454ea9bf84a4c9ccd9f9e48c4fce41ee3c47305
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
1	\\x0eb8056c99178da3545a2fdb46ffc41e51d0e67849270eaec69f011eabcc6524	payto://iban/SANDBOXX/DE371825?receiver-name=Name+unknown
4	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43
8	\\x27f98d4f08acdd658b8f16dcc1f04ee156d1ffe19ed1149880c52874b3db3361	payto://iban/SANDBOXX/DE328996?receiver-name=Name+unknown
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
1	1	\\xe7d3dea0785a12a3d8c3eb1011c4c65adde69ade17b43424ec3aadd7e7cd7a81175b8519a074c21537bf295205c316681cbe5ce91c9f458d0eaaa6959d64a5bd	\\x43ab138760205551077a1b1d64030cff	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.232-01G41SF962GF4	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303939333630347d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303939333630347d2c2270726f6475637473223a5b5d2c22685f77697265223a22575a395858383352423839413750363358433831334836364242455944365059325954333839374337415058465359444641304845505735333647373947474e36595a4a4a4d47355243423647373559424b4d4853375435484d37414e394d4e4b4e4a41424638222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3233322d30314734315346393632474634222c2274696d657374616d70223a7b22745f73223a313636303939323730347d2c227061795f646561646c696e65223a7b22745f73223a313636303939363330347d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22524b4e4d505247584358333548313157455958445859485052374e5832514b39424731354d543051454637355043354b52343730227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2246425a46305248484e56594a374844305150393030375451474a334b4b414a53385a46345048504556564d5a39314a4341425730222c226e6f6e6365223a224b544130384e4a4747355450434d585756584637394d4e52324d31474e545156375a525259484335375434574437414247504547227d	\\xbf6c471c4b4cb167f7487fcf0b362e5b5e2593ff0bf18c8831e838cea19188b6f54df9f752afa00eafcd43a1f5be9b7eb069393b9a03d0372cf476f3257799e1	1660992704000000	1660996304000000	1660993604000000	t	f	taler://fulfillment-success/thx		\\x6be886a9b3448bdc507c4a88cebdbb70
2	1	2022.232-00W6YBYVKAVSE	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303939333631327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303939333631327d2c2270726f6475637473223a5b5d2c22685f77697265223a22575a395858383352423839413750363358433831334836364242455944365059325954333839374337415058465359444641304845505735333647373947474e36595a4a4a4d47355243423647373559424b4d4853375435484d37414e394d4e4b4e4a41424638222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3233322d30305736594259564b41565345222c2274696d657374616d70223a7b22745f73223a313636303939323731327d2c227061795f646561646c696e65223a7b22745f73223a313636303939363331327d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22524b4e4d505247584358333548313157455958445859485052374e5832514b39424731354d543051454637355043354b52343730227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2246425a46305248484e56594a374844305150393030375451474a334b4b414a53385a46345048504556564d5a39314a4341425730222c226e6f6e6365223a225447313848434b5130363951455454565758395641303241413657304a4544565a32344244514d364338455046373758565a3130227d	\\x9fe342aa944573b76d328fdf6266c52fea74bedb2e461dc7e2066618fd2d82220c5a612cda552cb45d45de86dce66e6d441588cd9932b41463f735b5c5f647c1	1660992712000000	1660996312000000	1660993612000000	t	f	taler://fulfillment-success/thx		\\x8c007ba5ddf589f7d452fa103983620e
3	1	2022.232-02R8B095V31C0	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303939333631387d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303939333631387d2c2270726f6475637473223a5b5d2c22685f77697265223a22575a395858383352423839413750363358433831334836364242455944365059325954333839374337415058465359444641304845505735333647373947474e36595a4a4a4d47355243423647373559424b4d4853375435484d37414e394d4e4b4e4a41424638222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3233322d30325238423039355633314330222c2274696d657374616d70223a7b22745f73223a313636303939323731387d2c227061795f646561646c696e65223a7b22745f73223a313636303939363331387d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22524b4e4d505247584358333548313157455958445859485052374e5832514b39424731354d543051454637355043354b52343730227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2246425a46305248484e56594a374844305150393030375451474a334b4b414a53385a46345048504556564d5a39314a4341425730222c226e6f6e6365223a2242523658394e344331305245313138594b46314e545238334b464d463746534556385a5a303758575835544d3630435346323630227d	\\x35d4e33c0d33b399b3adf1866d5dbb17973b9e444b842de549c532e446055e1a0212eea3c6985a8a4012414d38e14ed1a308b7a5497eda32f8acb87349244b66	1660992718000000	1660996318000000	1660993618000000	t	f	taler://fulfillment-success/thx		\\x1ce0609c1b36d51bf9d96c30c1f1200b
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
1	1	1660992706000000	\\x6adb31bd94f30695d580dc4a6c3b121a87d66f00eb90f7f355fb63dd15e97b4f	http://localhost:8081/	4	0	0	2000000	0	4000000	0	7000000	5	\\x43dcb4018863a3bd391d9f5c23a2039a6bf94273ad7bdfde44a5a74b244c59103950204dacaf2c7903c1ad55855a8949fa1ebb56638bcd6a5ee8da4445af6407	1
2	2	1660992714000000	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	http://localhost:8081/	7	0	0	1000000	0	1000000	0	7000000	5	\\xe50caf7855c8aafd0f9ccc21564f6576bd9e6b46d3b055090949b495d4a57437ad68bd69d4e01c6b1653765e99b968706ff8dab0cb1e97de999d8c9ca12b8903	1
3	3	1660992720000000	\\xeef20d0da277529e070bdb760ce75207ac83071b72bba0ec3361cdb1c5d320e0	http://localhost:8081/	3	0	0	1000000	0	1000000	0	7000000	5	\\x287dd1ff3f6b799458025f0f2655487e042eb750e2e11862ccb8b55144b752299971eadebf6a3c690e7c87c2321e2edfd777b0badaf96109e627f0fbb84f0f0a	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	\\x2747e8d76adecfc3248cc06f3e7e577f48ae9c5c0d808eabca3a573b0f095ad2	1668249989000000	1675507589000000	1677926789000000	\\xe8bf9052f9c1075ab8c4bf3d757184256b640594b3af767aa39bd50c43d6011b0e1ea2479c894c6a62b6c34aa4321c094391c1c7ad878024047a40c6fe26f003
2	\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	\\x2b163a9fdd5f0ca35cf0a76147e3ff593d6addeb5527f2ee36f16c8e3899e3b8	1675507289000000	1682764889000000	1685184089000000	\\xc7fcf13b65d2a2a7096133bd41c531cf96234fda19dc1c5e1031dfc4005e6696d65d4cba4942c43ea485b4a7df12bfd650af1cfca027b3a12d5ce7e227e7b600
3	\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	\\xcd177186b7ab0d514e78a8cd40fe94d434d6ce7c3dfe056f43992e2d2a3cf16e	1682764589000000	1690022189000000	1692441389000000	\\xa19628c59762ed749b7edcfa447dac56f2185181491a95d0b03258420c5a7ab497f01d55cfbfdad3d65f5c252e2654784a7239ff7bdb2cb6e329410cb5fbf20e
4	\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	\\xf42008b02c9df2a62be8986ca4f6ec45c6cd64bd2437075a8acc9bc53aeaa284	1690021889000000	1697279489000000	1699698689000000	\\x2fb4d4310a3b68ee76b733961e1ce6db0c38e87881cd2bfeb156fdeca4651b3b2f0db6e5c06581cd161bf45fa83b6acbce522e0a89c004660d5d2e8d869d8c0d
5	\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	\\xf51f9b455918cc78cae8e6cc2ea33a1585586126d01853912b876b016346f5c1	1660992689000000	1668250289000000	1670669489000000	\\xcc12f62551829820324214b98a970bb96f476ed2c973657fe76c32161ed353de762a749940cd8f45f51e7493968078584335dbc81db05068b607c1737825c80f
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xc4eb4b621d674658843c77badefa36c1ebd15e695c025a681773ce5b30b3c10e	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x4a65d7a22dec49dfdba2ce66df95e5d66bd240f1e874c9f97764a9f360eba9aa109bcfdd210973914a93a8738454ea9bf84a4c9ccd9f9e48c4fce41ee3c47305
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x7afef06231aefd23c5a0bd92001f57848739aa5947de4b46cedee9f4864c52f8	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x2af224e0bca42e5c4474c69d750c772769288edd7e491185592b3963fc96c747	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660992706000000	t	\N	\N	0	1	http://localhost:8081/
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
1	\\x5f5e7ebbed3baf2203048b24e3d62da3b3722a6dccac55932f592d9168c0f67ccbb9ee0f1bae1c6ef00a973cc49ef4337f0b10d571433e3046d8d0e419a7420a	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1660992715000000	\\x313b9c4a779ef6904dead059e2d10cc7c6ebd55a5da776632255b960809851dc	test refund	6	0
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
-- Name: legitimization_processes_legitimization_process_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.legitimization_processes_legitimization_process_serial_id_seq', 1, false);


--
-- Name: legitimization_requirements_legitimization_requirement_seri_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.legitimization_requirements_legitimization_requirement_seri_seq', 1, false);


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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 13, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 13, true);


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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 16, true);


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
-- Name: legitimization_processes legitimization_processes_h_payto_provider_section_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimization_processes
    ADD CONSTRAINT legitimization_processes_h_payto_provider_section_key UNIQUE (h_payto, provider_section);


--
-- Name: legitimization_processes_default legitimization_processes_default_h_payto_provider_section_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimization_processes_default
    ADD CONSTRAINT legitimization_processes_default_h_payto_provider_section_key UNIQUE (h_payto, provider_section);


--
-- Name: legitimization_processes_default legitimization_processes_default_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimization_processes_default
    ADD CONSTRAINT legitimization_processes_default_serial_key UNIQUE (legitimization_process_serial_id);


--
-- Name: legitimization_requirements legitimization_requirements_h_payto_required_checks_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimization_requirements
    ADD CONSTRAINT legitimization_requirements_h_payto_required_checks_key UNIQUE (h_payto, required_checks);


--
-- Name: legitimization_requirements_default legitimization_requirements_default_h_payto_required_checks_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimization_requirements_default
    ADD CONSTRAINT legitimization_requirements_default_h_payto_required_checks_key UNIQUE (h_payto, required_checks);


--
-- Name: legitimization_requirements_default legitimization_requirements_default_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimization_requirements_default
    ADD CONSTRAINT legitimization_requirements_default_serial_id_key UNIQUE (legitimization_requirement_serial_id);


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
-- Name: legitimization_processes_default_by_provider_and_legi_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX legitimization_processes_default_by_provider_and_legi_index ON exchange.legitimization_processes_default USING btree (provider_section, provider_legitimization_id);


--
-- Name: INDEX legitimization_processes_default_by_provider_and_legi_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.legitimization_processes_default_by_provider_and_legi_index IS 'used (rarely) in kyc_provider_account_lookup';


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
-- Name: legitimization_processes_default_h_payto_provider_section_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.legitimization_processes_h_payto_provider_section_key ATTACH PARTITION exchange.legitimization_processes_default_h_payto_provider_section_key;


--
-- Name: legitimization_requirements_default_h_payto_required_checks_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.legitimization_requirements_h_payto_required_checks_key ATTACH PARTITION exchange.legitimization_requirements_default_h_payto_required_checks_key;


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

