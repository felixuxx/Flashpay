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
exchange-0001	2022-08-20 12:52:13.547704+02	grothoff	{}	{}
merchant-0001	2022-08-20 12:52:14.619189+02	grothoff	{}	{}
merchant-0002	2022-08-20 12:52:15.029683+02	grothoff	{}	{}
auditor-0001	2022-08-20 12:52:15.147215+02	grothoff	{}	{}
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
\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	1660992748000000	1668250348000000	1670669548000000	\\xdadc5cfb79a7b94e6d311f6033f32442d2a4791150799ec796049f6f7772a8ea	\\xc19d70df3db53fe89fe00a8c74fb2fb06f8871ce97ccd812a80b12a9ea181bcffc27b8e365f2d0f97cb34c543741932805a30e72bb6f964b2cf8c0101ba6ba08
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	http://localhost:8081/
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
\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	1	\\x70450b46e592fa22e4f2edcb92617c60e600e1454e9bc52da02397bc862901f139a4ab579932a8810809b880982464c45cb8f4a4c075bb462131c5efdfd965fe	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xa244abb59475dd50543a653bc2c2c6609ab29b03b1bad126007bb99202d5809b37a15c3ad70b7fafbaef55f1efda5375b10fd9b6f890cc2cacaa5e24c3e55fd7	1660992778000000	1660993676000000	1660993676000000	0	98000000	\\x633286aec399616c6bda89d40013c5d27e83e34b10dc958e2c6adade957a00bb	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x625da3699e7aaf380cf081925b5ddd64134f875e5e7f1f72fd558d37c1490b552f6792cab9494b41c7cceb6747321182d5c9729f1e481286e06ecb60ded99e03	\\xdadc5cfb79a7b94e6d311f6033f32442d2a4791150799ec796049f6f7772a8ea	\\xc0372e33ff7f00001d19979870550000dde0299a705500003ae0299a7055000020e0299a7055000024e0299a70550000c0692a9a705500000000000000000000
\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	2	\\x7d0db3dc8c43719af46e3d51fbb65e0ef73d4e4128f0156738aeafc3d59de0bfdb64e63a40804e00592824e4c9c0ed72da900017a28a4f7e30658731044df108	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xa244abb59475dd50543a653bc2c2c6609ab29b03b1bad126007bb99202d5809b37a15c3ad70b7fafbaef55f1efda5375b10fd9b6f890cc2cacaa5e24c3e55fd7	1661597612000000	1660993708000000	1660993708000000	0	0	\\x028b2f54b389d85b20e243a97645d85b4122896f343bc22f96e506ce8a053a61	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x11b8376a6f8ed143df4bf5aa4cb92b8431b2c57528a3fcd5be3f2a868cd11570c25a7c0965887422bb6fdafcffa7544776c43d45bc772f5985e60ab9fc4ad301	\\xdadc5cfb79a7b94e6d311f6033f32442d2a4791150799ec796049f6f7772a8ea	\\xc0372e33ff7f00001d19979870550000bd112b9a705500001a112b9a7055000000112b9a7055000004112b9a7055000020e0299a705500000000000000000000
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
1	1	12	\\x10cf853797c8045b4475b89ef46ebcb9c6c213577db80a7ad378b62af6095f2c89d2252af8c1617f554b07056e01f824cde006f6df18924bfd58922f355fb10d
2	1	48	\\xb62cb9527c9c30bcfbc2564130367cb78a68d70a40dd14e2e7a6c673376856f7cdd77ad89b3cdee4b70fe6a1e6d0be0ea7242653346e59b69b4ef25209229a04
3	1	203	\\xaa3568879bee745fd058074b817933b30cc41656ca68d5957cf9369b7a25f267df0055436f7a5568c3f60f9f46c742b7c12b69262801825b6de75793ae7f9502
4	1	407	\\x79096da769083335396b696c498794b36788b4a95038e59e372e487c1d77803e5fcfb18cf9b99d2e95891ce2b963ac35617e9b93207aafb7759b3f1b0b59150f
5	1	395	\\xcbe6c19676d67dda8b65d4806fd9af9cc94efca9a02591f1261d1b178c90eff6b1be82682d388554ae68de6ac7b7bcaa496668ad8a92243f7b91b767f6130b01
6	1	76	\\x13f789cc636e65293b9ea24cc1e89e84bb63715e7eafde60e2630b595e3a9c1ebe38d9bbbeb3570c72780640e00a3741a510ac000d2a9f36f668a23ea907190b
7	1	32	\\xa3d125a55337dc08547f38ae658b86bc23ded4324866840a0d8974fab57bbe2deea64123a0afee51cea39c9a0d581e69a9c3a531b4aac3fedc3361ff4e6fd30c
8	1	260	\\xed8cd3a252b682b72f7a48faf319e407c57a6d9c00cf739a666a6ac000e38f472de58d55c5a07fafa0a44739bdceb3d9a0c30225efd1446047822bfa36544f06
9	1	23	\\x99a57c13dfea9c4734259884eac7d4be10ab14902706895ac9f9ca0c46e0934ae7f578c6035a2b2f75ae1643a629f80a02be3e10ecfa490249b2b3502eeea807
10	1	391	\\xee57b67b1a20b521518990a62a0d9d91560e5dd618b0d15614c088ce34276ed3846ee4a2cd87bdb108ea3958510d738bb7ff0bcd79dbfc90fa60355fe95f8e06
11	1	270	\\x481c38a6e68ed3efc3246a06bcf0825a875cde36d3c4ee026ef31ba9d0b3a6379b9a9e1b94b0732def5caa42bff170837a3d7baed6b2cf84e5f19e7416c8eb00
12	1	87	\\x804e3eb604f686c0d48c5cf5895f82d8147c3892f0197ae19ff595e05260af4c1c1d5ff92c9141a0d6a83066dee2028f1960266e1f8bb33b789b0ff74a8a2c0a
13	1	374	\\x4a741733901f0482f69d83b1f174302bbe0ee4f7d5b058bda47c0f6ab7bc1594ccae6ff4bf03b4e98ae32e089beaf0b48f90af0acd6c8b89ad67930e9bac3c0a
14	1	392	\\x12a326a6d45f1ab716b992fa096e1088562f5433a33d8cdeb367fe56503d2ddf2650f2b0723fbe8cf5944df71e5124b3e50933df687f319d3046d59ed5f0b608
15	1	103	\\xcdb44442fbb90e7a52cc739485d3137144da4df683f1e7cd43d05a03f063a72be6ef25cce168b9368ea83497c68a03f0382b31adaf2afea5058ec40d3e936907
16	1	126	\\x619a7648a2fa2aad552cf6da225ef09ec04cb43dfd88985d3980cd341f1c5e6ce079c0d5f525d67c0e621c7f250897a3af9872a56d09109546d0a0b602696a05
17	1	418	\\xdd5bada8f69897524331e31470419a48b8d0318f16b76e0d692757eadd76f3203969901398b3125128a303fb49d29ff70215c1b548a186db3d66d5b35a45a40c
18	1	262	\\xdae329583b6ad02bd676cfd8b9cc7b134a133ba23136853ed5d5bc44b3d5a2649fe4dae979e2e69f43626958e80193e5c58036a6f7e4f50319aad2664ff5cc04
19	1	344	\\x312e8e5bf52d07a0ec41ac0b4b7da6673c2b0179862c00e0f01eb6a1c1f3724475a28106ab0a9661ace74016b558362b816b080176bafbcf2068b3ab4ed28d06
20	1	145	\\xf86572c1003bbe9476348cf1ccccf6461fd4457da59b61a55764b3164a9405d919cd83f1db616bf4be3835f408c99877090c50573b020c1cf18cbb4bc4443107
21	1	15	\\xcaa63002252b85651b2514415a279533ccc3352d549ce9995d11e59bb6d5e5bd07473eac8d5fb656789f63f877a761afe93c7e0d896febacd7f58cb51a05c30e
22	1	239	\\x09279cc3b92704a37ace7b8cbedb2d054e40726ed7eeb2d7a41bc76d6badb2c2ec64090785d96f22abbf0978e1f73fddf6613d38976fcbfb1432c513fdad3406
23	1	225	\\xb211c647202b709927974f03f22c161144d6276db2e04d35279e2632efa3059c1a6119f576a85bf988342887174764c5ed7db5537e6945ebe9090e9a0278bd02
24	1	29	\\xa9a7e8d0752d2cfd6a1c4a5e0bdbd9f376d6cfa8a732629a02dc752cb0e90fbeebba65dc3c8a6ed641504e8999a7ffbeaf18a2c2c16f71c61363d1d5c4714d05
25	1	10	\\xc2fd6e93eb6e95902733c4d031f745ae54df6fc2076b6853577a9761bf7f31ada82ab11412ee3448566e17b362b16cc60025d5b078e44e52f9c09b5f86406408
26	1	92	\\x2020b49c684e65963a7a7c93d2ea2563d81220b5b2ea3f817d27c2fa6e1e8ee1ca71d922d44d496bb9bd6761a73979e8dc8af7e0eab7d992abe5267bd1529f00
27	1	82	\\xcffa6fe1ebcc098619f2f98ef4033486c914eccbf963337e8a2df9b70b7bd66869c0ff20ed514f5307b373995a7d4ccf36e09295f13b892dac14349ed6d46206
28	1	186	\\x19e73fc9c58035c7766774161c3ca0b3c59e4e108bc3f54a830f3339108174da8a2e624c8a6d030faaf6678b560a70b55faddc4d695a14b5d22e6e06b29ae000
29	1	419	\\xd90fd1afe5e1cdd94e8e464b52e8109beb9065c05ecc988a1d90de08f464042b2933cc1d2161d3d4ddb0f4596fc392e487ee60c5cbd53058843cf27c2a3e9c07
30	1	94	\\xe6372031e39fe19cecfb5b371bfe9df21475dd1528493d4de0c3633db53ab5679727bfa3e565f8a7e3dea449b9fd99f6cc755678861a26a4742896a0b7c7c50a
31	1	336	\\xe9cac9400754e76c55729e6409b5249d583c657f78c15686466d516e2e688ffa981b76c1bc761798ed84a1a6ae56547c1761e6ca8f57b338b08bb85f5e9f2a0a
32	1	133	\\xca8cffca66f9a397cfec28f30cd76d6ffdabcfbfe7f7eb2c6c8f48c7b48a460529d16e3902704cb3d93a4387dddc673887a0d7c8ebf1523d926752138a144f06
33	1	301	\\x6a5ca12e9e45527e4c522d44ee1265765bddbbc8c8c51509b0f5e31b59c28f5bcbf62dca8a438efe8afff0149f5ae57eca2545a9af6a9587d948a83d3764ca02
34	1	120	\\xe30caeaac13647e35c56ebdd6f7ce31069f06cb3c6a7105cd8aa51d18a6e0dc2c3c1057e3ca45d9200d83875c196a5272bf8dce56b9bd8dced66f242d126ca09
35	1	341	\\xcfe6a71963220d583acac8df3b29dc0e4208e8941de6d368969ebd606794a67cf4aa3c4b51d08f211ce7682943eaf091679a646abe79a316d5924004be4d3c0c
36	1	393	\\x6e25262e8a857d55cbac2d66856b938aa91786dea1856375414f110d138a3d8ad7111e5aa1dcb9d0bdac9ce79bc0efd4a99d257b69e719ac04b3d5166a2cb206
37	1	406	\\x63115f8e5bfca6964ac856c1dc25d4d65dd96e6ba59d7720b409b042b91f56c03633e9de621fecb8abdc0edf77d4145ecfd156e1474cb5235f2618a3ba197e0a
38	1	216	\\x631c26377c15e62010dcaa3b64e23838a0739038c72faed11269dc46c62905a1eab250fb21f7495d8432406389153c6f8db84b468453469b5cd4ed0016ef6f0d
39	1	410	\\xbb2fcdbadd6cfe1547472922686917d9ff8a5a417db54ce46dc668e108756715a610ea118da268a8703f5e13c730ceeec1da19ced2e495fe9936a86b18f10403
40	1	93	\\x02720d054f6dad78b4434dff2fcf53e50020fa654d469349c3fc8a81c298dfa441368fd0838e69ef8a9aa861aebeb765aa4ef628c9b81c7c01a091c43ad7a709
41	1	33	\\x9164e96e6134e053bd03e68aa5bfc3b4ad72d70e502022f2560b0b86b25a5536e71b3ffa65521680dd9599a06620db9bc6920edbfb85d847d735284efeb79f03
42	1	39	\\xb2067049b32b6069abff3578e6472520d007d8ab2dc29296a27421ecf6b49e6a202c0e7258e48503fc2b21e914a280dd7a6b136d262130f0e19609388b665e04
43	1	4	\\xd54d48f965a901d4cb30c0616ede170bab64ac53d205e3fdd7a9822b672a002f6e4aa2214f51439a47f42c780f346625205c748214b5294e5a7256efe4588e0c
44	1	212	\\x27422707a1ed5f0a04efcf04e10efa8e6a02233fb7278a761fb14b106494c9b712852f0aca608e927bcae236e4df20116068e080abe4b0e6d6d17bf04ae7700f
45	1	43	\\xf52645378a939bd3a81b8c3ac166d8df963c0b550d2dc891e3ebc42fea9d71ea3faae1202ad98ef29653272659e5f99ee26b9ae8e84723b4387366b60b9f370e
46	1	143	\\xecae8d84fca5f0feb40d60c11052a675fd3338e096edd960c62acc148832e93842944c8be2c59bf38bf9dd85b5c029578cced03c424300e93fe4aac116361607
47	1	217	\\x437271b4769431539524aa454e0693875800918a78d0afd5bf6983a7761a294a628744f70bffd856502481693a5e0df13cf48b72bf1c5fcb97947e90ea4ff904
48	1	234	\\xd574eeeac54dc2b5a88e5d9efde009dc8702498dd1bd1a18c83e5119caa929a62c54e9d119b30052761962f3063ac4313e449424074eacf3237d8ca92dfba406
49	1	250	\\x9a9cb4879b87476d47c538b22770ccaeb3fac9949118631a7f32c87dd9132474801882adc22c9cce0d54e139d4d1dd259eaabd0883a08adb9996b585d1c60c0e
50	1	162	\\x2a323e91e47510072a7b4931c4d1c0c12916bc83a0436db5fdf220ead49ea6795310023fbf2a35fd01afb723267c11908db0923762d055d109ccc8e544e4f30f
51	1	273	\\xd8bacda8f625a3070ee60585a0a41fd91d8ed5bae0be39e7ea9d90f7555e9a7b759de18375bc791d00585c275d0139964d274d3e0a0407d422b3e2f5cd40980f
52	1	30	\\x1e864929a15b40e70eca87c59561a8f5b010901fbe490ef5a3b464999e05f5f4c890e0d3d665fa68b53d634e822789f9ffb35178182ed0e1b44885d444b9a603
53	1	227	\\x822adc8436527563c93109763c9500c6283bbd318eb8c1096f4f4c288ecef1e697453e9aef51ba4db488e3319c7a7ebf42cf29c9b78cf0969699cad3e2feb30a
54	1	151	\\x652331260e5d43669a782bf81305ee2ee5f4b8893bf0cf21d87ba80105c2cad44dde030464d7db7cda38e7f23c3448c91781dee517fbf60595dc9cd6266f4605
55	1	268	\\x49aff3c8d9316c2c33e80c05a56636cdd76040540028fc999f75275c18c7a260de09fc9c1380b1106241049e8614ab17f12021628097dc7634b7a37674492c08
56	1	371	\\x03133a05ddfc0f68a6a4f7137620490a1b27c26b475a0bd6d36ecc6eaec528312c9064d900fd1a39f9c4c7c1407cb6edf95e16e337e50fb50a29571be4963405
57	1	363	\\x940d1b2618f2e6cad26eb9a23cdbfdfd1035cc83c95212f50f14715ee49d9136bec91802b44a171a6f7df5426a49266bfa6e160611b10f06d1c77f55307ecd08
58	1	210	\\x05bc1e1b252942eb93d21282a5a8010ff2f11c4d03d85b7ae46ece0f1f0daf2cc844e57e14c7814bb0ec2a15f8ca6a0fa8e2686847abb9f979462dd93916a504
59	1	101	\\xcaf3dfe9bfa977114f91aa93440615566a80d3d7aafe15ce072a9340b652314e217a93760f875651126c2b099e738bb36f2aabc84a70294533f30c645ff7c60a
60	1	195	\\x4c761e41c856578f0b1fb0ce41919c039733d01f11b3ba30ac9979191c4e737dd229296c052088ce3abc300ab0dfde8d57845e77ee880e26ca9fb634119a570e
61	1	149	\\x0f058a19b7074e9d9c4b2ccaf852ea0270e119f56be1f67b8a5e1f1b95b4ded8a68354fb9b7202083efc9344b679e598a9d8f225391f3bfdbdfddf5a2a1b6700
62	1	207	\\xbf14635025874284c8a13616bbf2d4790cfe6255b02c9fddf4f25bbd13a09f913ed0182541a6dee8dffb242ba31fe16da365f9c1628e7de710d47fd6882fd80b
63	1	232	\\x87285f5275b56f4c269ef4826d52b89b8cc5ecbbf6319b2fa2ea68defd33433d0dc33b270480ba313387bbb17883f59182e266b1f127d006155e0c8d307d010e
64	1	201	\\x02e84fe6294f188ea47dc538e9255200664cc828b7aa10c09dd551d29599d6906c134df5ca3ba66321869fab2f9eccaa9f2fc639a2cd22dbfc65ae3d2d8f7a0f
65	1	127	\\x790554c123d85d30c9cdeb87910650470fa85ef5ee7c8a618876d29bfeb13a80e60c715699c1c884b684a921c3e5140d1c401d0b0f4e21b68d43705e9425ac09
66	1	182	\\xce55b1bff4db2bfacd38e059cfd1d4e0b7a645e35035e0e92f9c5fc214cfc1fdc8f9a43548de7b331c98cd141c8aa0e59168d8ab8b2787fc0c62c6bf05bc6d09
67	1	306	\\x6eae93215c0db09fef02cb758248f54545cb8df974874143f752ccc39ddfd07499a9e30cc86d0489195191a6ea1173d38a839b90b4b85eea2531c0f1717c0f0c
68	1	248	\\xe6433a78c61bfd6c08ad88e6f9e62376ea1e8b2399d1dc19227f0914865f86ab6e362fcbe03e90294cfa338a98d737d2b4c097d327a21034413a33618783740b
69	1	277	\\x0b12f5dfeb967f0d08886723480be297b40f3256797138484871bd18d9b297d4d78a23e76f12bd43a403e484a09a8e0a0faf3e7fcb095a306112629108955d0c
70	1	390	\\x3c7f13265558c412cbf5864c6341de8192030f728e61137f84c55f57df5760eaaa55df91f38ba41c0861f7280bd2c21f8e7cf1807f868b7e18450db556466f0e
71	1	353	\\x96165d493474561de191f4a17442a525e528143e0c6e8d69b779b34c95c65e9cebf97f2ca189950f5841dade932130d0d3db19474d506352fe58b88353703b06
72	1	119	\\xd80721791900229661dc915aeb19a87f782ee8a7d49b36fe3ec4c7b1dbb68e91650a3a7b64d15ae6c6fe795fab8932255d5d9a23987ddf8e12e342b95ef16507
73	1	57	\\xbe529851b7ac96b15225bf5f4af70bacfba01f73908a90491660db25fc2d496084c75bb86d9ef4bb2283f7db49863709407774554932089cc1a92d070c769804
74	1	409	\\xf63463e79ce8508cfefcff40c8c5f2808b475e56a356bd5fc900766cffb7491173edca7e43ca56db352089132bb9b6921bd5dc9026c1cb2c6177dc049561050e
75	1	176	\\x4009632a27e7789bbaa37f235b7b60f2fa3bc8903c46f604ca5a99fb6c06de045d4e0c6f4eb8d52593d9b26c445162a145716f40178900c1518b5d30d79de10f
76	1	8	\\x4904280325dafb01b13c20b5d15920007a625a6149f345c648234dca72aa2f4af9b311f2b0ed1abc68338f451e9e089e3881f731879de37f91efe04ec73a4707
77	1	405	\\x1a6b553bfdc5234be7a01fd12e5b5e1537e745948fc2e6a80d4d2a2a4e5d908a1af4719df4518cadc0eebb0efd6692376a0555979e8db0788e7e89077718c101
78	1	315	\\x8442e48f6b3308621763b51fd50b6595d3e8e4bf5196ee6a67a764caddd023d6b373e2df46b274f9c1fabef6456669fc6df446773ae1cecf0c1c7ff033be4d0f
79	1	179	\\xd014e158d814502fe22bb827e8410c15c7e5afd5156b018f6557bb22745d48f8663c31999158bc365c5e27e2c4366815216a336d009b6aa72d6224924915e709
80	1	368	\\x7ce7c9bee2443a930b23a87588faf9ad4c2f6432241b3b185a073b0ef84ffe40aa2e247d6f4ddc36e40db14e33b26c9b96a97adaf3e3f7b27557a49a6683f105
81	1	14	\\x770132b405b7af33f89a5e2d7e0945727b6ad718137b4cb4f962453d6f60e539c378303743a79c7c6e9ac05eb732de2eb96719d180cc5d17cd37a65f915c630f
82	1	135	\\x47f2bfbeb9b6cd7c3e8df83fc5e1db0f33b09179788fb953849df827d654e34aedb06c5801072ab27bee9419e5f8b569c14feea9ebd2b1f3c3395dbb959f4f0d
83	1	222	\\x9ccc5cb6f4f49f57591f824db29d1a310ae404ccf14e8e19264884714381ca3cb922411ec727f7acb14f32fbc4de054b451ca6285bb5e0935ca0986a3bb06709
84	1	382	\\x0d00f0c024161c0c7c1134e9ee20bfb687657ad6ba9f2cf75448f0594fecb2c830c96fc8fb2a72105aff4248f2778537dc29100aceab80206beeefa8cd0aaa04
85	1	318	\\x0e0acf5c8659223ec62d5d1fbac60acbec039ed597f31d1bc875c8a4e32be131f256ea3c38dd7ca6371adeb4aa6889df18ce87a860b5e17b07aaf89833fc0208
86	1	416	\\xa0b3448c464e26405c288f6528f9aa134bc7192b7c70172668313eafd51500d9d2ed975a11a9eaff72177ee85244fb0806fbd9fbb6461f05d20d8e0aff831c02
87	1	18	\\x01345d906e859294c95dc9e151be47620d6554c3252aff15fe521e55587dada600d27c675c3323ba037e8959dc7ede99bb15cbb72e2ce2049d8eb8b7bd06710d
88	1	252	\\x5ad234ac1ebaf7c08e0701f97bc56621aa4ba31b10e8761c9ae53d63e47b1f5dd47ae93e0623f8a6abf26b1057f970f96fdfea1a6afbeb8f5ed114bbdc628e00
89	1	189	\\x3b3044574e43d06d427784805dfc33e5b3e8f19f2d571b719f58d07b98a395fbadcf0fcada557e4ac041e153de58380a69889ac3969c82bf80d58ac37fb0fe08
90	1	79	\\x2feb6b79307c6e98e030bc0e8a5dc508c7a17556ece836698f26fa82f655d7d35e8f0687ab5985b517e2378659d859de18a0686b6ece9003caa356497e1cbf00
91	1	81	\\xfc3fdf9fde0f1f7035e50ad9467e8601d6fa6c4d94d2599538398c7dd8136e1e621ad1ef9d9904346474db9d7bb07eee6abf63fb7cde993d9e0b7a876f733201
92	1	233	\\xa1d509a97daa7abe2564459d804beee755ab322f5d06725e4d5a49d7622727796bf454c3dae4e54bf15ca028d4a3066eb9770e5388e021929b47475ef3938509
93	1	378	\\x9d3c5266f6458530d410d257bddd636a957c0104ef03943b3535d1a65c94129f5ae2eb886e1f73048e15c89d370d09a41acacda7c6021b2a09084761135d2408
94	1	54	\\xd431cb05fb5cf4a9724c225d2c13ac8281bedea71298352337c6c4fb20e116cd7226af100a20f084b8a98b54c9e4c9f8d886db0dc7fa9ae2c40ff67bc1493205
95	1	68	\\x709e0c28614c07247945e0bf5daa661733db652edb0d28e865e3f101fcd5ad3ba4b5db2821b9ed990641a1e7889e3720b0b19c8fa9cb3e3b0845bc301e4f5200
96	1	411	\\x69f63a2faa29d8911ccf747e34b69f5e0dc38fc9e367c0fef64a3c6803eb17bcf32f98ce2a45febaa681635dbbbbb2dd0b5b7e12129ff08849fcf75a5ac35c09
97	1	90	\\x78a4718748c7bbab84df107e14673ac274ede05227dea7be949f3530c201ba4dfe7332db9dd77e1456f7fd1aeeaf77fab71590f6fbf22599b807c3088432a30e
98	1	164	\\x02e53fc7a6e7a5f998eeba4958fc584817e1f4200b02b90894148a47db2d143bfae1b1ee7b997ecd0596c890a0438b0dcff4a8e12ceb7599d104ffbfba2b5c0c
99	1	204	\\x5a030acee667f1bdb5a519153da79ad286ce12de732e350aba4881aad98e752dc44c78dc431e4bba2f8e7fb71069fdb2a33835cde1f8bac85ed01d469379a006
100	1	258	\\xc58398d6ed7733fd280d98bc6fad9473b20e901f9e68d325aca9847e862de96e681fd17b6aac86a0afcda4509ec2025669ec09f4f4cc91003e2a769e0c006c03
101	1	27	\\x863633e57dd3fcaab0ed32fa3315138c0d845015c8b7f7e391cade9b4e95710789242a4fb48231d6c736fc3c0d4f0d9a1f88eff5a25bff444210ee0df211fe01
102	1	272	\\x98fa4ecb76807b82ea7818d0b72af2764e9bbc74349348057a1addcf6a4ae042ad6da2b9d5a88fc5a29f0ff747db95fb6c05538240b3e50e3286f63636525508
103	1	356	\\xfa5c9ace68d5e4b35a818966ab30a267f6c772ba29684ff7607f6c853509cb8ab9d0d1bae52486727e639cf2f10dd9600af7789a46d70b4bb461fd998a5f1600
104	1	226	\\x8501cf72ce83e676ea01e7764b001e52e015c79d774362ce8f175dae6cfe6abee67033f6372338475ccd654b4c3f1a530eb1534937a1150482c0d5a741210e06
105	1	148	\\x1bb4246ee552b3b4ae6fd627564a7e3ee4f673363345357ef05eb57b2dbfd915fd96cc6a729dcfec2d8b6617540ab4584ee487750db4eab3a0cf0d3a1dd1500b
106	1	275	\\x0206e21a3daa48726652592aedb51e7ab8e74eee4ff87c5fb4d513416709a34bcf34e63e6e89c11bdcb4df877bf1c4cf30f1e570efe2fab1ddaa3991aab66c0e
107	1	282	\\xcbbb61e14a01db5991a1da7ae8e45a3f2ac2e7c8f2fc6ffaf6114258d1e9715fda52c4e34be7890db35776c0cfa8517eec0a399b8989ae1462074c8041e66602
108	1	309	\\x45d99eee45336fd8fdca75d12cec8f9fb860f5f24e6731a8fbc65b08160a875a60c13844f3439df64499cda0708e5989e2ac4e308f3d1a4b1d9c361ff10e9204
109	1	152	\\x688a3fe429418eeb16543d0e5fe6b05a15a79005d6490a5addd28d3cc4ea31a450654561a23c21f118c1b31c1f5aecee837c2804d9ed1b9440ac2ee0df3a8c0c
110	1	99	\\x87405d745c8b61609851729780766714a65f6aa7647d92ac0af995d2a5fe83372c58e62a53c637d3c794c9c8081504359fa04cf5e7c37783b163ff023a63f403
111	1	394	\\x87e057461166e4ca937e2286fe46d663c00df77b05b81f04a863a776a002eeecb532587d679ba5b19d35b5b3bb753ac4c3a97296d715c8a7491e25aa01fda702
112	1	60	\\xd434d8ae2df2cec3bd252d3eae54b0e9b905a76a8f420700229b47988b87e3bd1c1aac359bcf4e935d09fe5ee6fd590398691e9f6cb682acabd1c270b4f9cd06
113	1	249	\\xe43a039b1905c375336b0656d7609b31940d8ba4156d8ab87d8c6f0ac1573adc377c58bacedd67ef889b78bf0da5dae7514a11d4233dbeb6ce8422a0ab1fcc02
114	1	324	\\x80bc9e73d7bf1753550bcefb36e2628ce5529e1b6be1e308e825ed5cab4eb1518e5eef5d954af428f5987f915d864cb8646d88ca7d4a5a76e495e6845521d903
115	1	388	\\x7ec7000c3c1bb66543f2f6a9155a5636878b02852772e424a9f18f35de3f9f5a67291daba6894651e9e4425cf1fd1a377e38ae44d11c3eab80a3079cc7403805
116	1	211	\\xa0b3b5e49b1b673bd9554f7be99099cd0361e6bea19e54fc8c06bce2aa5b04076a86dc0cccab80eb71b52a291fd20311465bfed22cfe84ee38178f5b7cac440a
117	1	213	\\x6f1081cffb6ad8806c27fb99ed5ed1f0e7402ab18fb803be53f6580583eda9d87d2af29cb29dfbe499659a58f6489ab97ecb1f99f1637d07b7be24d3a57b2106
118	1	413	\\x4235303206231a4bb663b4e4734ee77153adf3a06fbd958283d79c7f39d9d03bc45f032c9cde4f026a02890e874980dfd125db5ae5eb241ad8403bf196ac4304
119	1	214	\\x2299b8f9f10106e59161e992475f0ba52db3bdcff0a4a7f700a3eff4229a8fcc03d5ef7dfe01d43c5cada427d319bcc9266205e16c2ec6d10c8c96b359db8c05
120	1	308	\\x5c1e46d608798d5d7d51edd64b8399824b50cd85008ee4b9201b5d33150e5558065be8427ffeb08db3861324afaf9d3e448579fd711874a0ddbac15a8a500f04
121	1	169	\\xdf25be73c89f2e7d15f4d89938b5686200f17dcf04a3421d62175bcc6488e720a6546ecd0eb5e16c52ea0d307fd99982459666339b25967699113afd56f40500
122	1	193	\\x689885f1245b507db0b799c9cf1914513f64d21ef0e5e7d774bb101068a87a3064c8ed1ef933d982cec665e12f0d33e88bd51077cb6e32916768cb48077c6f0b
123	1	183	\\x11c3f10711fcb76469d45b048c9e6f725b78f3a85565227175c3d55267661fc26d8ccae5769a7b5989b754aa4781db20eafd9df137188795c1a9074fc39cc80f
124	1	209	\\xd9574fdf5c07f4223d41ff070df8a06a7fad760681ad8033ed81eabfdab8e0bf85962200342fe52bc5eded6f5ff2d56c33b68e9ba1d54480e3408fa3a6b0ca08
125	1	6	\\x023d86bd6ffe430e6ad15e4d4a6e754461330a5ec25f9da61916e04720928c634148bc8685eb34f43acacc8dd86e9e18572473d4027a0b41e275069391efe508
126	1	110	\\x12f40d159f3ba301b335dd73ed15164263b4d7a3e692f4c6a5ca6dcc45129b57feea30447ca9ba17e25034cad134ab99a03af3eca136b0459ea38ab068f30303
127	1	13	\\xc2ee56c5e8fa25e943663a79432cec64d541f4eeb2b1f0ef5d691beab0a05d9e257dc8c02c94983c8ff932613c76c64dc2bc9d03d30e7248357bb12163332f0b
128	1	236	\\x9a599c224ea42271371d1035271937df568170820ace4854d2bc9e74c1c92efa1724dd8504d51299fb0c73290baf6c15d297fd9f886fa370df99ba8da6fb9600
129	1	350	\\x7842bf76d3199d3a9bce581ec69ad580a940091ee1bf11672b2fa0452a5fc89176e34937e4b5b9f829aac7d9f18c38970aa5333aff632c6c5bcba571eeb0b702
130	1	372	\\x18064867c3e5fbca756c3642bd483bd7d6870039803d7199dfd915168a29cc28997065c40690c83a4e6aa799212eb8e37d695dcd1c0c9f0e8842c081ff003908
131	1	88	\\xa7880625d2b5bef070881e6a73123afe429ee9c5fff4cab63fa1560ae459f98f77317211979c3388b04492e023f5e2f832586bdc84df1802edf13e3228294504
132	1	26	\\x006fcfbd7e852c1bb568ee5d5454614de2fb642dd150c3556f829349a2000258cfa59c786f4c20a99d0b17c0f00b3528a8e6c9c6ac087ce1ccac63a6f863b506
133	1	28	\\x04688481e7b746c38de260f2214f896224dd397ef606da78f2fe04721f47d34bfcb5a20b642dc5e5860486c1dc804a7c237e65997b13f2e4152e413d88130c09
134	1	112	\\xdd41fd8372220d93fa8d5483de468a42b0a311e333888fce482155cf61a629205379046dfc8afed810c14b445018a00a771486daab16908acf3bb279f7245701
135	1	254	\\x7414d9124fd06a13a5ed3d3a729bb887df7ec687493bb26523b17e0b602c958918f627c9f618fb09d04508b76e32bf22df7c1f2aa49fc888d8cd5af70216770a
136	1	113	\\x9f2e7cc5ed4afaaf9dde2cfb11ac0ee14f01a822c05a5808a0dc3584211b80ef74b35924492551fd5e38ac4f63fb6a7135d24c026a6dff93e36ac2fc53cb100a
137	1	134	\\x045d7381c337ffd2aa75fbd4cecf08f3feed62dce2422aeb2a6ac2775722448605bc9b3d69200167cc082699be61190588160f7c1ea2f069cf71ad0c66a6d60c
138	1	161	\\x33006fd52ea775d076b050ce14e8a259040d85e2e3593b89cdf60fd627a0b0ca79c7855c87ceb70ab2266b7f771e8a3b6c21f9ef59b4c222273ae9bcf9147a0f
139	1	279	\\xdd92d44e76a0b586def71967722a4d8d10ec8242bcc1ccb91f623afdf9b95f65b224b2e41dfc9634877c1097f7e12dd3b6c5f732157e2867ee8b168c8ccc5806
140	1	307	\\x20dddff049f7f1d85be70872a86419b87a13458b2cfa9091ed7c1c7a841781e347fab0370f8c02aaccb1dde90eec5b6dbee51a9c09a98cbd632e2756c2d6f00e
141	1	106	\\xd8a8b5b85b055472b798dda82ad4c8b60ba983a21803b54e34cf8764490f929e345b5b52eff96df0cd642ceb683da3267a53572bba2e0ce2e7de125eb8c41803
142	1	72	\\xa6cfdc37345664e81f4e3ac298427f5b8513ed12a5a4d1f0885dc89e80d9b7eb74897e55a6519c2eb95177c3689f0581fb61ac97e5941017519b01e88bb6cb00
143	1	284	\\x55efdf6b4366dd00b3b8c396c73450c1f8de33add869e3eb6e6aba93afda49e02313d515973c720dd2df9bae47b7d6c5550c582f639131504d191db28d2f5909
144	1	3	\\x3d09b38da7ee7bc2a13a7595008fdcd48db2e5578f671ee46dad918ae1a2ec9d13f32353e222947c3913289d363332d4abf4b246c4178fe9507e7dc8de6a0f03
145	1	269	\\xf04288aba3767cbe54bb7338f42c7cc879de1e71e083596717c38ab773a86e4bc45581f722fb2d4a63e02b524f9915e3f6ad41ee2ae0587fedb9839449e9e609
146	1	335	\\x70998b851d70fe22a963a381656d6bda76e967df9a5e5f36f37f1a727b23dbe56e7d9a84fe1b9f832144e858743609348141bb66166526aa4212d88d8d0ef206
147	1	59	\\xcf3f8f0986fbfe182eb5f08e4a312eb5fc2c68b109148d276dc4b997b009debf6a5651c73194c6792172338de0ee365dbadaccad2b900bd5574ff76bccb8ce0b
148	1	247	\\x5912a3f3b88ebcdd6aa17158358f85e3a67868ee505b7b75f49141ef261c3193c2133368f1f518c3e04b74f1ea67b3945f199d1361a7f463f0b6f5ab70924900
149	1	299	\\x1e2a6c45304a98d404a9ce553080c985b07846246f150e549519bf54339464f3eeabfa40e298c7b04a83825a6cfa1b3f637999024e3b59c9326d955d186de50e
150	1	158	\\x529a91cb0142159e18c9a7f7d911e079e066db88d9fd3323d7cace001b6bb233ce6f1997c0336ad137ef87aef221226246ea1aa3665c2e32945f40850151a200
151	1	85	\\x6f0dcedccfab752bc983a8dbbd210fed3b3263e6fe19fe113367c2c3c6a65b085e64d7083f6f807d0e1fd5852696bb3675d01e523f77be8f2e19393ed9fa6706
152	1	305	\\xadf60edc481b7c9e8a135238395497d783d254942d525a1fb29fe353750b6c022d9610409ed7ee7fc7e30759dae8a04ce436c8d84fc92683165819872bf7fc07
153	1	265	\\x13b7d5c93b4ae45365de1044d146e6ac64d96776d87cf6e1b63aeaed23bebb06efb47575030c63f9a233b71719d30506dc26d521250194a2eab2e2e087dac906
154	1	283	\\x483367b1c06c94450dbabcd71f9390ed1c10996949fbe9476479e5706be267da7d931cab693d5f6cfb668b564277a90f23c705a7dcbc6d1f90ba2f8b7214160b
155	1	63	\\xbe7d645b0b6315f1152f17d096dfd4f8b0b691dc6dc46f952be7abd4d0465da0ffbde507f3ad5edf7a092b77c2c2e4f638eb25bee66d01c6f5fcc2a6af68a200
156	1	325	\\x23f8ece472e8961689b06d25aa9999574148213a80492312f41c0cf5bdf493fcf8ea3c579497645cf5e419c6573caac1ba73012305bc56f898cc4e73f37bd804
157	1	45	\\x751420ffb657c7ac9ab83af244256e8063f79f480017675cc13c0c9457b25542849543e6fcbd2a8bd13884db3ff7f948819e90555766f0519b0042a0df699d05
158	1	157	\\xb3d7246e0273bb7cc36af2d2d8e794ab1f7c9c24fd4d735b5ca6eaaf2d483b4e44d4d5dbfb319fd92260d5f01f480e7f1d0e28d8cc33895c8055842c6b6b9408
159	1	402	\\xc25c713e61f8d5bb3c147fbca8e218d968020132beee4107a6ef79dd6a38784ce321a543039ce3e689ecb7939ca1b3de7af393b5e189cb1be1af0dbd04bd8500
160	1	97	\\x5f0ec413fcf5711b70c1395832b985983151b302c09f21c1360ee88c6f78d2bc89b71b97e56a5218ae6b2b8f47e30b4caa468ac7ff86bbf376c55f97220ca803
161	1	385	\\x28df0d51b30310e8a97462498c6a976f20dcbb1a7964c15e45b5e190f2d0aae16f5b0f4111aa102af542560f8a2cf144292ad69056b09757e979fd7729c8a703
162	1	357	\\xd60923a28dd48803eb0552807bf14537d5fdc437a8e95c55cb960c4c962c0c2c594d4220dd781a44cc7ec9c87a1080583608afbd15930c2b0296dc58599fb504
163	1	369	\\x43364e6acb4c8f0b7b59784169ffafe165c065771f2c56a545eaec6bb7b958685eaabe3668acd387be18a84abf7a11c67d3fd141c9d64ef0dda828e6e72add01
164	1	25	\\x501bba7d67e77330bc92c133681078cc1aa840cd49a1921c288b3d05f112be8dbf220866a85a9513f31e43c8573fe2578814097f094271d32bc610bd7719a201
165	1	69	\\x5044e9ec2039b6a3865e4b76357810eb5130d8d03f9a0a600e17aa624f58b9baefb240f4c338f88ca8e8b36ca9ccef712491e505d62b70ff34e5f456af234e0c
166	1	375	\\x2cd80c1aac06b002213e1d74712d39d994d0b51af423098be69497dae11ffc05a3a987d427e201f08b9d6a75d004b928594b2eca52c42879035cf9ddec33b60c
167	1	51	\\x8972b85fb4a216ce83fb6aaceb009861d6354d55aed7a0b6a80092ad219b4138f935065bde10c2b59badbe43a9457ff560f60e37c47ba326595bbc37c9e62100
168	1	71	\\x646cc0f99068b1f6c268ff5a347ed9803cef3f28746e00a96b4d2fe6b65081ae354c48c7a8fcd0c938379586542b6658170706bb23066bdfb83f81e2b092c303
169	1	290	\\x089bf1e96705c83a336fe9dc05f191dab74e6cd16a3a8350a3c436b07d295e86734741d182a232df4cbed8e19cfc9d024c020d9662dd0202237270e18f722d0e
170	1	46	\\x51ed77589c5000bc7bce084d3478d3f01473729a0d0898b8b533219a09f8bd1fff5018542ec717b6fd7b9440f5c80aca5ebbfad4050eb111ad9974323fd5a50a
171	1	349	\\x74c26dec7a895d51b2733487eda9f26f1d8a29b77f100c0392534f3f4bfe0fa59f70a8b1602ddf5588d7871855064a25e2f100eabcf48ba51b22b88bf4ff5101
172	1	121	\\xc7ed22cd2490cf1377b76980d684b16c7eb60ae56f015a33b14d3bb18a36cd72498dbf3140932fd95f08b385486e5566e93e76d47ea84bfccd0958805f67ea0a
173	1	317	\\xfd37614998f2aaef4507d55dc68a0b662c94a37adc4eec1837890c804994b2842093e1c7cba31245261aeed59785679e5770d1b461fcb7dcb27218a74e63ae0c
174	1	316	\\x20a34dfa8ac55562d4a62e0f85e1bbbcf6c890a365665756341a5b57bdbded1badf783e18d537b24b6014a08cededbf87b5751a2bbfe30ea13fcc849f31c6a0d
175	1	197	\\xa3e475171f4cb07f99db5fff635065ffea4257d85b95f7abea2b2754f739c10bd2b0b8b3e71a2d064b031ad2acad8e15f364391afb2ebd68d38fc1b7f7493102
176	1	218	\\xb939b40a3a91d4749d2e2445437ac59878020e6d7836b80ded94d2e67f3d5d22bc3d398db119579c151a6611a5b6c1765b61a640e2687502cc7f982bb0558107
177	1	331	\\xf37deae98ee20104ec349a0457039b02244001695896fb9188d8f1fc354d7a809b01eca7c065fcfcde80708c2ade27af5a35aa2efd341dea78f36096321f1c0b
178	1	123	\\xd37e4a1eae0617e072ab6507837275d43b2603e1c273fd2d5e5ebc9e349d347560b9e71a6c2036d13df9ab5b789d9703924dd7272648cfe9128798b76891800e
179	1	376	\\xb71c1f224d7488a5f723454d24ecf14bd8f5fab525425f0011b2cf2a5a1dcf94aa132a20bb67fceb050f0e18c46fd7060ea0ce2c61e946f8fb78f7005caeab00
180	1	83	\\x746673fad78d1516e4b83f8c5db924eaa392d52c5f30c0142d72eb8f09e85d471ebda8ad48f1952ee3cc8600c1d97549e9c1a73542e9200d2fde241cb26b760e
181	1	55	\\x0dc7662ae8d3854026513812117762610f07e3744faf0f8e28490a0b0f75f812fa24b67807886cbc4346b65cb84e8fb5a2f67603539f9e88bcb8e62c188aea03
182	1	194	\\xdec6131ab8a4415ddbe33f109b45a88f031cee636b940af2d2981007dad8ed757b6d7844a05009a79298b684acd077d930fe7dfac02dd22d10b6d2a15ded5c0f
183	1	297	\\x7e8250f837bad4328ecd2c53e587aff8baf0cf02d7d1603cd4466567a9ab9af02a3d75eabddcd376e167c2f1b5936823d46e316fbf42bbc54e790cf00661120d
184	1	267	\\x49ec3795807724179f9c997186d5abdd52c6d72abb35a81ee5840877f5b338536cf4ac50944c71b0e69290085ed85eaf5d67757f34c14baf04b810fcce3a7b00
185	1	244	\\x431fa08d8d193287e1363da77f9531596871fdf5f769b6bc8ef66edd4b4292bf558cc10d322f71bbef8b4c1aa648feabf16d0c3f61cd9a1c2c90d6e3d4f76f00
186	1	311	\\xbd21fa8b36549d3c9a8bd59027699985d5f90f2f6c0b2bb56687e0973297a2474055e13abf868fd8f0363125374e8bd347704ba77d7b5147d640e14655c34909
187	1	19	\\xf9a51e641ee3dd6618b184bd7ccc303ca090c2850042db8f86b7a95590f429b823378dd3fc6997ebc6d0753ba74c58b5ca6df1b5231d278c451e877c78e5d200
188	1	114	\\xb3cd99cd483c70a7b3ed45cbfb8a767cfdc5c1ca5aca42815b9967529f25a20b3ef0a4349499d08be1af135ee2baba7dc86b867be027e8e846c99a63f2e4a806
189	1	237	\\x77e4db48c905c54333f996d3abb67e256b34102fd323db864bd0c703fca91bd4b511ace6271d233ab86a21e7e4671ab2789d887af8ed2298d4b8000303f8a104
190	1	7	\\x0e2c93db622c63d56e2e0f978c8b7a08557e308bcd90af211841f8b5a1c97a110a764caded31cc41b9572a4d178d30c73db397e1b6a92e6eb26c07d81556a000
191	1	47	\\xd72f88eeeb9523353123b8b089ef1b10c049385ee62c36f8a1ba311fa1f7d18ca39fbde73b2e9769f680e85dbc66e585babed4d5fcee243462ae6888cb284106
192	1	132	\\x18fc93fb44d51fe33fb57d6f37afcf4c503e50000e9d582f16340cd49522fd0e221bbc171fba7d79e07b734f15b8122a99c1e63d0250c3c8d88f584a9728da04
193	1	365	\\xd5d6f931f19c2bc991fc659882c86e77b89b3cc3c02993dd14044aa431e70da54def70905b24943b1f4599df135ecc711c96915c34197bfaf7527511c758b001
194	1	346	\\x4be4702efe989bc35b41862790e8a4ac3fb2673e436ee275b7ccbf0081851ee98f4640db875a0a883590370473f9f1b3f9685bd18e3fc3c2040cc20ef165b802
195	1	122	\\xd0d0dfbca96091606291daae169621c2285dcfbb9cf5be3a528de4f2f145f3e1a70dbbae613b24428573f60bcd63fec8ea8ef513e22ecc15a34a144801a01d00
196	1	342	\\x5bfc42eb05566ecac294b4bd715e263e88ac0aa3924188cc06868f73f72164e9e0e940ea58b0f62a1987d4a235c9d7503362b6d6edb22f7b3c62631a1881540a
197	1	188	\\x8a7162706cb01ff5485fb2954104d1e6840f82295b424bab59d5eaa568036dd58e28609fd25ae59f16d9f20973560c27f4b8573c2ef39650e878d1becb50d304
198	1	199	\\xc474534b226ffe3d7d9f9765a3898564e398f3086a1ceb0dbce46aaa95dd6ae249eefb202b26c23655f2a1639d782d139bafd73812dbfc5e31e053c405eedf0f
199	1	322	\\xabc27e080741d1cb72910a22e1f2ce5f65dc803f2bf2ec4b69ae9c2aa888267b3d92e9bae795e79b703088e0deec2563a3fbdc506221a663671104c143f80a06
200	1	172	\\xc13b33b27945838001d5a7b34db7e6eac81339ac5e435dce678e7e285687048e40072651b36097e8fe9e81c00a2dc66683ab42949baefccac0ebc7c59eb94409
201	1	398	\\x30dce14b80676357c99d679651ca6ce081ed51beea9e411c12086e12b3f982ec53f90536a4e20199d83d5a306b4e1668c8bff0833c07bb0f7b3aa9db19966809
202	1	80	\\xe1989e178c433405037fecc61bbc57e32eff31ef9b8da9e212e463e3c797d1b06a8a15a9d99825dae672de889d8311ca5152c4489eca399b17345fb99c55c507
203	1	37	\\xcedc4d1989a81e036beebfbe97346aa0589ef1d498b227b37e796ac0397de27fbbb2adb070ccd913147d6a46e37bfec0886dd21de91e2c93d7061f4ff4532a0e
204	1	140	\\x5da91e10c09dfd54cc2186bed27248500233721860290bcd25cbcf3ce9016bc6f6d34ddf83cc36f103c54a3cf22256b2c2747b7cfef161b165fc11392b210d02
205	1	296	\\xd77aaafaf689e6a8762392059443b24846a5dd5e5e31a6cf76c4e51a805fdd1ae5a60f2e01251bd7e9a7739b3af9e85268b25cb01951c0f047f84a947d320f02
206	1	379	\\x53ca59ad51654abb21e86429c733e7163d320f6435838eb84affec09f64a069ef1d4462c3475279f5ce6d0f4244c3f6b34006b8b57ff6c9caf7ce27c74820305
207	1	144	\\x2a3367d4bedba3d7196661c36cf0bd619e20bc28705c2f779381d8e04007bf421c05c11a9e645c34059d083632ed5865ef70df8147dc2626530522c85c5d7800
208	1	320	\\xaddb1edcb5ad88b60fbb2a88b9d99e3b918b0bfb88c140c1f5787b270ad0179aa13de0ec16f3e1880908882226ff4c9fa51625fec893f60d9137a90d983c9a08
209	1	111	\\x7f9db72c08a7fda6fd43330840350ab2147808655b9c4b0044a4b77ac1d09fface3afa61cf267252a233aa870e0c2a0eac225ff3c9c1811fe5c338d897fac802
210	1	354	\\x4999a0a90eea04d9bda1e79992011736c8e94d81e0f2084f2e9eda561bcb80edbb710ab97860f7615ff378b1f19521e8cabf01a87ab7287b1aa6860b3e32740c
211	1	224	\\x77bc7bb7ec3aaca93d3ce9c359a5a9246f7bc0a9e05c53c32c6e78b4de508c2926e878273ca78646e9e113401a6a2c37355675e24708fb678363be483a8b340f
212	1	154	\\x0e8acfb600fc551781809e2f711f92c0125833f816d97c8d0874dc24befd0bc4f8a41e3329df123dab5a3e34c5038b2f1653e0b1dfe8621e5e44566fde063307
213	1	276	\\x18f9e109f360f98224b91cf099beb82988b155c8fdda623632db191ed446fab0fec136cbe8e0961e40df4f0d6b42c986f78e2c01c48bdf3b659f08932c5d9b03
214	1	86	\\xbf962e03f805c600c6dcd141b053377f64edd825620c188acfad86d09831da78509117afac033f1cc437a4cc0f1a410571573127c69ebf31d4efd5c62d99c10b
215	1	16	\\x697ed873f6f7ec506acb2565f7be08d25d07a74d64042793fe206c4d3501a5efb553f4e1c6771c21a00f61def3be4ab1965517bb80d6b5562cb33df7e4057e0a
216	1	1	\\x9e54dd5c4af151e03e1bad68e6a33ea564461891f6363ccfc901e23765efcc005627cc17f8efe26c14f3407020fdfb2e8aaf25f4ba8f1821afba708001fd7608
217	1	196	\\x586d9d5e91e1d649d5508e0d4e26ba933779b1bc9f0bead8ba802090b00dcd938239b720126357052c9341185acaef014eff03375bb29698c4611ddb5847690f
218	1	168	\\x30477e4612a2c3cf8eb8f5ed5a8c42eb70ee9a7fc3fa4cdd83028271970aceb0cc5842217bc999935f5b653271385169c2705ec5d4788897ed2ffadabea16408
219	1	124	\\x1e378930d4b8dc73877570ae50e7a8c4085e390a1ed22b0b8469cba25b39ed01c43c10f2c7be650ba18e9efa15738a3edd517fb9945a131fd49a051d8bd37905
220	1	107	\\x91834037ff55ddecda203035ada183bc483b2c5f0174a49914f7e98bb4b8f3cfa8437d3278c0396766675deb40ad4dcecc42561957c743a61804c2fa6df3dd0a
221	1	163	\\xd64d92ee561b42ccf65cb8f42d386152e258798f06e8a6ad1cd83969f10c6ecbd14ee579062620925197ecff6c5bc4ed414c8cc28aba9732402f92618e8f6805
222	1	198	\\x9383cc25c1dc8c9a8a3fe57154fde2f4592932f4336b618142f7835a2133e50aa3062eac004785d0ae76a10880039c7f5a3792b8eb550618d90fcfba5cf9c10f
223	1	181	\\xbf7335c2a87456eba9df69581ff98a319e2d66968f0911f2b13f70135b10d2f8af4703be066f76390581349ef98438eea369434c6dd8d3258250863168969407
224	1	98	\\xee7558ef52aaa4c3564944a293c661c7f32c2fc660785c20c7df517888c8fc27a0372e4101e1cf8a64430d4b2d86c37235096592c395a70031bac9149b9dcb00
225	1	403	\\xbb335af98bdbfb2da890cb2fef6fa56d864eccf07490fa01d849112db6734e3504b9f3c457b20acd63da0a85ac07caf9112896f690ae07931fcc60449567d103
226	1	191	\\x405e57dfd4ccecb0d2300164f17800cee4f2d52317ebbecf36c0e8e91139158937c5b8fd5cf87abff98d802c7f06ab5a914130bc8c25560ac435041ef21eb201
227	1	190	\\xe63bf570bb828ddc9e230026e62cf752cb6040fda77120713eb0103aaeca7034913ce2cc0af8651ce1641d5a4f844edb6debd3c540c912887eb1e7465b81880f
228	1	200	\\x2e9bf04be20dece56ff15db59c17b663a474212cf9c1ab0808865d9f85819085d3c063c44803cd932b7ebc626e658d430ed84f927d0316c9f70bac0337823b07
229	1	424	\\x47ac68adbfa796ef711ce7836258c62021dcd2c331dae98cca12941b502723e545e41c1c58b43280a86a8bab2a2ec1f5f2310ffb9f37b3d738344d3fc1f3d404
230	1	137	\\x5c185a0c6c1398a3fb1c2d8469134bbad98876ac6a9aa3c472004c6f0616c8e213193903094b05b2aade0561dbe42413799825dd75e3ca2fc651227d77e9220b
231	1	130	\\x2a1a0e116c06f151192ba0de799da060a5e3f4e5a7385f5fbcafc3ea15f7ef76fa1252abf06e02784a32732e0d670d0b46a571e353b2bf02ea7213c427946d03
232	1	240	\\xdb93e78f8b2d1e7e34aab8f57b85de8ca5a31ffc0b1dc7502bdf8fbdf7f1a40f43897613cf8d07cfa95212cdb981a66a85235736eabdae804a54364f29e2060d
233	1	351	\\x2af3f604b4527c242cb0ea275cb794945b74a3255aac4750cb51b5d44e405564777d3c077fac86ca5755cc76d052c3bae3830e824532a0bee2e13425202e1a07
234	1	215	\\x948a245eba64fe70062926387e48dc59222b97439ab73b37373d7976877eef4e9697cba55dbf08deca68383f25cbdfdbff5452abc7e792a23e799b00502ea307
235	1	62	\\xde6dbf97401272b1d3929c3b51346da7bd98aba2ac4018aef0384ccca2fb5d3d900e2361ebb9a92e61c45d748bc0143959dc574af1744c6c8f62681fe9a40304
236	1	175	\\xe89f101ee7fbb56deb525df9e0297a3e3ccdbc14fee2980f27c3cabe6409c69c746faba1f923439275e35f24b626c893b782d82352295ada9d3dcd499125a502
237	1	184	\\xa71336270b83c11e2279bafbf3ae1e4afa4ddb2358135a5ea197f33a613d371e79e8f75d7e71fb9d187b3849f9d0a56a1415ea71e2cb7f189bce96a5d042e809
238	1	274	\\x63a33d655d0ddd07a5228351f4af5c327f846d782a3ce9a213b090fcf3236ab17a842528137dc48cd2a95e05b19ccfe86ffd37e2332a2adb221280856b9e950c
239	1	278	\\x39b13a5f591e217d09f3a603448d61adbb283631c7ec0d472c996649c8443b3386716193d93987aee3851d0ef68543885bf7424b617ac3d300ac22b47678920c
240	1	294	\\x096365f854459e158110bfc6cc568bc25ff95f7fa024ba0753fc7e930e76b04c5c05a253b3ae3fd1c7d3a42b940b9bd1f6c0c22d80ffbc1291d7461eef992708
241	1	399	\\xad13407e6a8b5d4291675faebc3c5c5c660a60c01f452d506128af23cb02642e5199ab5d64df4447df4567c07d21a933f2cff97bfde4704735e5d8333ba4460a
242	1	53	\\x69948beb8ca32f81e57ea0748b54780b35ada56a499a3e9259d42a3bf2367fe679b4e754586d3a5470d4225b51ebc2eab5d051ee79318ff39ec72f1886d25a0e
243	1	253	\\x085705e2da1fce5bbb0fbf50afed1f49de9e776fbd7383fb2c2a62fb41cbf1bd460c236ca1877a37578ea33b8171f2cf4bef65d633d3334d75cb356ef148540a
244	1	291	\\x901af0e5a2b7aa844c092bb76051d7143c65bdefe8b535badc1f391f175575b9dc173e4b1f160e2877707365a98c654d9f72e9f1e037b390cf5ef8e89e433f0a
245	1	245	\\x035eb740d45627b0732652fcb3974f76c530d74765ec31db3ab1f42ff54fd52c82fea8f38814b64f79ca6e0bbd0b583b2e21a79e7a2d7895744f694fb7ca9c03
246	1	387	\\xf07bb0beecf0ae994e6048d2c0d9378eef19a1d2cf1184e2a0b171bd25424bfbaca9fd0a475dc34ca24691476858e8bda89da8ccaed130d47005a89731875d02
247	1	75	\\x138f3ffddc48e76c4995d62ed9e05db7940fb1a1fc4c32cb69316d30627fee960e2626cf5e519e08e863579bd265e75afe8ebc710ec2bbfef11ca8c5800e1904
248	1	42	\\x7f388f6c559e8d99e99cd182c0e082141ccdf39fc16bc3d82d02fa0e1ae45e0c9432c3d7ad680e1a195440f3c39926f6cb0ff2112a5c83263d70ec2ec60a8001
249	1	256	\\x93dda3fd9a529222e29781edd95a231e5411543267ebe6ea76c254f9d8e2b9957fba3616281fe13d813bcf3d69e1d9b9dfc304a324e942d70eeb194d0ee24c02
250	1	287	\\xdefa2b4898eebd27c6f84dfdb94a67e564a9af901888dad9c41fffa4fd7cfce12a86dd890393b415d29d116cda9b2469164be9f32ffba93020db89b0d120d408
251	1	421	\\xeda2e195aef155c90066591531b7663b0d6127d0d99e937eba4cca4484f61bed5b07d30b0cab923f9116e861444723fe9d5c2d1f96a86af0c5f53e20e6f72d04
252	1	38	\\x9b9e3ef7e192a7672d70544eb7d99efe926bb9b17f1c5e11b21bebbde70117e4e8a260d2d4cdf8b136a2e9a2b120e43226cec2e8dbf0d7a746048c7434272a09
253	1	397	\\xdd25231100ba34149492999b03c296d84c4e69352c73e2c906f546cccd9b9963d98fc4b4c6b9833715551a56fdf9525133d5b5b2a3d805482dd076d50c096c03
254	1	264	\\xd2809fe961355fd7b89edebc07f2d1c09113e4e081569ad217ab4f4b2707286d322a4a61a98792500abc2ca625bfb8cdca19e3f2ae6119dd8587d142f644c603
255	1	355	\\x7037e12fab0e03afd80fca132ed86b891639f4f41e578d8d509bd7deab5d5a0b89186234114a2f269f60593f5949ded908f629342934d0ef7d5e4f87de82e70e
256	1	408	\\x44ed3aa824b047ffba46f273be25861f85cba470452f03f4cdd0d5ec81561f93e829b3ed231021d345d6b67ff6198191aecf2f79518bd17e7080f60ae831aa03
257	1	141	\\xe94b3ec34fa564fccf98b9e8762055d470c33d48be4690ec7342d3263e5a2ad3dc1e61dac019fd999d8c444f832889bced474878cabd546ec89580667c37c809
258	1	300	\\xb0c101769edd10cbc1b6cc48543c1fc105a124d6450683ce314d7e44a3fd021dedfdbd2b7417c54d2434786a05a9df96e066cfef684819f207dcfe4a0086110c
259	1	312	\\xe95047edb199b959dade1d1a8b43c5243a3c0b0f24142b828fb09c7830a0bed2b997b0de2cb53e310c6d8c385db8b0c120e92b02d841a06ca2847e413bac5d05
260	1	2	\\x12b67284f6d96c1fe1bb6c4dc7ef43e5fae024d42f8cb6d4b89f719c277f1ad792e1c075b3280c1983a45561e8a46264208570dc035aa52173ebd1770caa2205
261	1	31	\\xb474bfb68cf3de9847df3c98632f02c89be89d23477e38409db7e1b1202ae64974131d0aef53a040185f15a1d4ed14211db87147f84053f749951ec91e83b400
262	1	321	\\x60b42114c1adb116337d64e76ae04ae9e3a373dd3ba68d65749a92d49ac3092b3cd349684e1657f4e54bd3938e0ac5b619d5e32fe0594050ec1cd10f2ba0930f
263	1	180	\\xd7b22c61dba5bca812bc7c030acc2575b7702480871293dd0530e8050700f070989847b11a8060fe018c4be38b23625e43f422bdce11333977f4ec94b4aa0b00
264	1	332	\\x490eee45036bbe9cd14256a716bf0445badae4f563ea034dd812c2199a52bea2516993fc0b927ec1afac4ce12382698b08bafe831012251735da74ac255b7c01
265	1	364	\\x171ba298445b752cb51ac638ec4a0249524ac47e82b40fd9baf446327a60791eed7475cc2b9f811ae1ac0b4e7923d678d54c45d5cb037fe3ed118cd171b17903
266	1	242	\\x8b365dc76bfb36f91c9cceb471f84b39c82c7cb9d3f7b19c141c52138d91896ff83a06b6b39f3fa1b5a6709b4e7fa576a48f2ad146c00e99be1280958da3b701
267	1	359	\\xc771359f003b8bfad125fcbb65bc8104478d427375b91d4b633562efa879dd0f9041a27d13e1f8b1a7aa8cac688fe8b202940ff8682c87d5e39fd94128a1b80f
268	1	208	\\xbc82e6543901c66ee59713b8e70341c7b717089be188a258c73b03ee1bda4be53ac50a0917b9e01ae58645b0b2453539e420dd40066a7b55187c074f44cc8f05
269	1	319	\\x4e059f9f5891e70db9f2c2616c84538b08392a1a8b34181b615f8afcf642edb764ee83e2d5a0e40543510a903eeeb88efcbdd763ae9526bb3d720b5fb90f4f09
270	1	404	\\x2c6de755038301b01ce4849f910b5cd56914373f6a576be80a2b5c342062649056994aba6a342b00acf6676056f8f517cd440c3d10612e27d8c258b66b834b01
271	1	108	\\x22cf37912163cdf21db0b061327cc608227edbbac22792f91d53f56e9ad6774062e7f55cfa397355382ab147f4b7f399cbd87b42643a452a1c684aafddc70002
272	1	116	\\xa37757188368dbd8f4114f29aa46eb2aa5ada3bc92802e2be4af266ec5c28740abb5c7ff3cf4005ee52705ccfe8c10de4f6ebbd88c613e1f15e35e8817ccc90c
273	1	298	\\x4559170a8b1b437fda7e928ed88d931bafb111fd2e21c8daab03b17648b5d500ff34293375a6d2369339b4c2ff51180c6c0e450698593ac54cdc68da02d76e04
274	1	231	\\x62dd22a33bb461046d6f292ed0dae30d2ce9c80f73ee9f837915bc2b68a29a757ef2dc97757e5448c77ed281175e149c249976833dd11af39d12cb4873ea8504
275	1	327	\\x6a5387778ce689c9c4b97044f107d953a0bd0bad1d006e194fe4a55aaad58f6ea2bdbc8fbc74a97a4f3b53245630d38b22f826f0830bade94c42bee0f196b40b
276	1	221	\\x554a4d554336ae748ca58f58920c0ccf171424c01d225550fa74a713c743e9c1c8e3f25be4b61ff8fd2b946ff90e5d77ac8af0d7f4950f65cf9fc3dd866f5b09
277	1	117	\\xf302b57097aa600c9b74076095136610d65e675dbcc91d04c6cb6bd5c6398113de893bfb6a87f54e4e78f4c289cc4d42aeeccfe8582ea89840db3a9e0d6b8206
278	1	78	\\xa1e0ba3e9c77e3076c5a1785b8ec6325a84e27e80cad1db13a37b747bdbf71af0a16df0e7b0d092f01eee9d62d0d63f1ef270cc0aca8b5bcbcdc901aa31b0e0e
279	1	295	\\x97ca713a0a32b3516890cfb076a04d1ab2728ed397212a903a66dedbea1a87c92f0f4e33c546392440acf82fb52b0b43650fe8985289e92e7d5e6c288015b50a
280	1	171	\\x10a4f128ffcd8b59ba0732ea77cd7fa1225178713e096bbd00b26efe19cb35d523e7435939d75054b052d920994c5ed2f5188ed7554a1402719a64c1a8d06f02
281	1	337	\\x49dd4a9d1db9d55243e5959a305080177f0bb739fbbe56dbd847450e59caa5da08af0797dde3d78f152b700fa31723d373733f522bd3494d095159ecc30c370c
282	1	223	\\xa0879c3a9b69a9a3b0a5b6e9e0c2ff19f8472042e406eedc12a4b899c4033cb0c28a23e2c0516e39c678af543b34bc1c76586b4684daf14296286cc3ffceb906
283	1	102	\\xe803b5fac2f0a1baf28c37598b769162d9a7d9b1452078209dbe66897743321b387eaaf35a9a7299e913ad00f3a5fbcdfc858bba55c16187edcfc21608e93d0e
284	1	52	\\x8d937ef17257c7d295e6e004845cabbbc1d1f57004a27dbbd3c13671b28e4ee0af9be423e0ca8a5c60a60c0848a271442735fbbb32787ca8a52583a66333e10c
285	1	380	\\x7dae27844bb0a216c617a86ac2ee73be7b7525dca9c7373cc8bc54be116ec605f0f0cff349e77051ec8955ab85cac0fdf53ca05a32c59969f2027caf0b65490c
286	1	170	\\x0335596abe7b2c8d1cafba09be51ef33d73ba1580bdfcfb22ddf1a75cac3930d15d600adccb233190078d493766a5552cd15f82805828bc1530bee446b8edc03
287	1	118	\\xc4d5895ec4cb0d011e6387abc04197088051a416e914c1d58508a28eb017dbc39788b760e2cafe662ea2351e58a7ac65dfebc0b4f6bce81390b0bccb36456e01
288	1	49	\\x50c38d72b06e6ce52ed57d5066c3ee8066e546549113172e230973529f2595726d9f06285a8937319973b98d8313121067f876417dbe08b8e92177dccd6b7d09
289	1	243	\\xfdbcd41707f87638c36c04107d9c485295625a6a1eed2b6e52497cd3de5cb4ef350adccdbc3b8e0edadec2074ae0097d9ae5d47a3da0ae119d33405929e7670c
290	1	66	\\xecd4d0d75022e251cdbba3e118d75cd290d2891e5f875602723188c68d21f00f2abf3cf782c6b0d2852ccd7bcabaa01289a7e5e8595b21475c0b4ab32ea6960d
291	1	70	\\xa7edcd554b98ec196c28b5ddd7568201c843387b8be3b177660c5288a27154db05e0abeddc97db9bc14a38c4a30e73aee2fe6a06d42afd0111e00cde728eee02
292	1	338	\\xdd3c963c18573beb004f59b511deb05a57ffcaf0e285d0ddf67589e0177b91cadcab4232bd33d180530a995b05eaedf60b5624d8b6bb764cce243be48c714701
293	1	56	\\xd32500080366d8b02c7dd0ce610a0447bc1c174fb1b016916f18d172b1b3d419df6eb4e155cabfe0af8f14233283da3ae84f5e7809adca4543ac1a951af19b05
294	1	67	\\xab400e835dd517c49ff7c8528a2bf0d508b8cb15886e79335a17faa24fea6133e9754fbd05b0460d41528b6ab2316f531cc23fafb32df7680ee7a9cdab8af003
295	1	136	\\x9acdf98a6f1145e8ee23ccb52f1718e8839f176abb02edfb9569a4ccc081ce073a6e797b4c2c444b7075a699deeaf6af9ca0ac3cc8f9e3081e0c405f0a6fe00d
296	1	187	\\x9d6b6c17ad47c3c30c43e78e6b5fee28a92979a6a4fc2760f9300241d7addf58fa7fb3e41f231e2b80f4f909c205dc2a60bebb4d1f03150c659fac8af3df9b02
297	1	150	\\xf036f92d2cf205c4875fc9386615c8343dbc8863d0870101294bd96c8e4ae0955bc9116e645b19a5be304c275858efd5ab7b5e45622430426bd141d875530109
298	1	314	\\xa60cd85c67a5e0b65288e12b9312993c0b358c993d8be9c2a051c09436dc47b4d9d42d83e9e441b212652fafa784b81e02427229b7ec288fd0acc5174c9b0707
299	1	36	\\xa3967f84650b79ac96c42fbf90446741b67ce484339762fd6315bab518c1606aa856b7320fdfbd7291d0e54a568d7939b740427dda7fe0c46ddfada21fe9130d
300	1	173	\\x2f017b5bb13614f95cbcdf0591fdcfb5f8b83f639f42c59a26cf0bcf627595b5f53f140c521dd85bf46e30b4854a109db71998ede4ac22908901044d682a9205
301	1	417	\\xbf79737ce6b7827e136925552115aefbc1e13b0e0c048016eaa3487fca58ab5409597dbd41b198c4a700b7586af863d2cc07a3f155fffe59f6dd0fe38887bf0b
302	1	220	\\x97ca5a6474e3f6d6426922263f8d2fba815c9cd2148b30deca4d7e22c1cc7686890274258b7735d13ccee0ac2794a34cf1743cb3a4064b27552755f3cdcb0201
303	1	261	\\xd3ee2ae1aaabfa2512dcee8be417a89b450d00306d809f4e586532cd241ce6a940bdfd2538bb1b17771baa5b2c2fb9747cb7912888ac0c0fefd9fb45b43ad409
304	1	345	\\x3f80acfb75aa8fb411808a533daa9a8864db6d62f4222782c0fc5d099981969c72a9c4f188b6a6ab492296258220f4f792b6e7ebd041d3db24a1663914024d0b
305	1	61	\\xc77418ecd69e9ef8b9f102599900c77d6c6b498d0566063e43f6eedbc417a46411edad10e190cce292bb30995e6284b66dfdab426bfd65ce13615b575dfb090d
306	1	241	\\x7a9b456ea501fa24f505b486224151e450daf0a0b6b47a202d668d86c9d2179ba5b49c3e08d8d8aba98a5f476a9ddc78e084d8373ae48c0b1a846d5d34a7370d
307	1	310	\\x651e29cd19aff05775c38416c86a62880239735b7f4000dc7c113df666bcfa4800bf846df9216a36721ece976b82fa87e2b78a0772f9f46ebd342fdad02e470f
308	1	91	\\x63d2a9e4b6a6aec7f2975a86632a5affdaf4ef251bffca4c243b08642a15c9baa49b059baefa8f3bec858a4c172ccbc25cf971d5fab8309ff69dc94b2b0f9f0c
309	1	177	\\x8b5ba50862b4170a0c6d30a1bb1fc3757b7dcc98d3fd93d1fc723761b47223655f0df7e02d146111cfc4ca36ce2368e999990e6d36ae2ce8cffbac87e80ebe05
310	1	167	\\xfd16e67df72b4be44df8545c43c953f88c239b6a4413d690012a219c25cb5e5a47ea6f71c58c4976c45ce6ed4873cd2209c15f693bc891def5c5c4afddb48808
311	1	420	\\x609adecc315a0cfcc5cabf8dca3facf1b200d1fc31b8b528c80f3e8ae2ae88d864ebfdb0cbbe6466c71163f847542ace1b09336e13ead0fac60f152f50d52e03
312	1	105	\\xe65ebf8e87ca37bf4b7f45d608b14d7fef9f32efbd343e12615c4528bee63fc7c6c7c884f682f2b11ef6af1dc007ce987eb62af294cab45a293cb95ea7b3f70a
313	1	352	\\x9f9c41c695bba100cf2fd05dff7bf687c238813a7ffd3440b7ca2b42999f650034862ddf1de77882adca98c825c248dfa86cd0c5678c208cd18e08dab3c7c20b
314	1	128	\\xda0251ec73739460d89d691d026304f35a67ff6d6afb289cf5eb3835dbec09369fe54d08f8f38c0f30bc65409fcacd81c6b4681aff5a812c91c4bf29dbe1740f
315	1	192	\\xd77dfa50a0a75571af82886a175fb6d5c8e011f610ccf1562a3d568d488ba2cb07002eb9525bfe59c295540607500c9fc84b8c17def13f15a8c978abf72dee00
316	1	348	\\xc811e2682499d17a78c0fb27297b5a07be416d655691710914ce6aaba5db1d61b67e9dee98404d3a4460a0234f8f84413ed6efc83f2641c3c7168d05a99be102
317	1	185	\\x5c1add1f81bddd233cf43eae8b8bcca7b1dd2221772a779b2dfc89c2ea582e97e95e72c2cbc92794b5e435432a4acb7b4b6d4507982377d2503e491f8b7a240f
318	1	74	\\x92c89508ae139c772ca001fe3fb3544d1e86a9f3793ec33b7c5b73c494dfdb22f4d50042e4a9045b7f761c63fabaa98a581c4350808225999615230a9b258e04
319	1	89	\\xdf22d7c8dd0b9a624fe657f7b8046c2350bce7eb6cead05f5ea2fb4340beb99e140c6f1cd0a439c037fedaf2d4f8809dc19a76ddab828e3a5c7465a45edaec0a
320	1	44	\\x7a15196e69ccbf5eada9324c4320a3c8a709b3861c5cdd4c92093cfcb245b87c150820511b6d59eae4b94e6e9c9bed10860dd2d6e0b3ad69d1be6c372d7fc203
321	1	115	\\x9cfc1eed061245e11d88ff8f8867766b697e674e7546d2c3eabd269b9c0cc57f464312e9aa3849d79fa46ea09851a018b23fa39bab6b0dde946be5155834500b
322	1	362	\\x9baf4dd5bacc623e63348570edfa21ee6e27a4434ec2a0808b94323aaeca9ee9d621bb10a984f539516646305872e3074327276dbc9dafe7295ced13c7315e06
323	1	386	\\x749e05fd078c303e07c8978c4772dbd3b97c71c675892b105be431f155bceade27e910898229ef40aef07b61a24496bff18a42d49bf83e1e53ce96303cedf306
324	1	153	\\x0ca97ae21cd1d5c0d4b9418a698d5f1a24cd8085e996447ca876e35c9835b69f8c7b6d4dbf4decd5fbee84684d953c7addd33e4f9f43b3397cd3f50e7d489604
325	1	146	\\x7e91c2890ab64d164f02776d817d191dfedbf2576014fb170e3fa4a744b330115aa045fde188301a47f6aea327ad843dc20e955e667cb6e45ad918ef819abc07
326	1	155	\\xd259286ca797e28b0fe21d948896dfcb6b58a3f8e8678fcd4610f6470dd18969f88e1d5c6654a799deef4637d1021144fd515c16903a77fa3971018f94729f00
327	1	246	\\x76619d0d2b5f44873bc12c021e4a9087d7744a3f26b1895206bc3f145285cb49f397166f31e5491386ca4ec2bd23709517e8757731e672c6db6729af67b82b01
328	1	230	\\xe60aa1487b89cbbb8b65712854d5a4accc292edaa82bb55011a01d04b09204b98f28f356e6d65965fbdb1f4c6d5fc2463fb910dda7d8a748c3250a196f6b0e09
329	1	292	\\x4ac64faf545c4634d3196807b0d18bdc8ad76a82cf797396f1c5eab3768319d71d8e2e7fbce1209947fc2fea26e3237c7311e316905cd4e873505ede48662f01
330	1	343	\\xb963fd379ad38003b21e2d89f2826953bc9458ca0bcfaafea57a58ed5b570610f819f215b4a4d06266ae260643e4fec8af27fbbf5d01bde9b08ccf90201f980b
331	1	340	\\xd653aa277545f9bca9533124d93015bdc87a61cfa3c6960f9d32d828f86c235d656665457f8e5d40401b55d01307e82856d915fa469f7e6d3df5c5f934670e0a
332	1	293	\\x131b71b5dc1a977065876cc0c5837788e604867d13a05ce88bed51d49d0451bc603d788bdeb1a31021bac82a4cd8f633cb653d8a19cb978b47ca0ce3d4ac690d
333	1	139	\\x7fe7e0478e7eb693b560b3b99982713a7ae212e9911790ebcdcecd8c23b1328fea24f1a56d3d8fd157d85fbe6285ccaf88d81838debc28c7c63bbbf6cc33fe00
334	1	396	\\xabc40b86a78f3ddef93d33af1dc4b02185408921f2fd62a9c78322be921f01032e9b5098ea78f4a8b02fc37db5f74c97755df4db0dfa6374f9baeac13c11410b
335	1	377	\\xba0ad7ff507d6a58510878e804535b5fbc377cc351113a07ad39b3b4c965afdefe5fbd61975f303d89100e4f5edf60b2e4b7b9c978c945997007185230c77500
336	1	313	\\x2c839b453728b53bf46f210ac71b606dce616324c832c911ca24806868ef660fe40e9a0b7b32351e3fca26d1b90adde403f450c7250e14ec3ebf610333360f01
337	1	228	\\x30563c5094f52e09083dd0921d26d91ba410008623f8ce7198867d45bfb209c4ae7ad3fdbffb91cd7f03a39cdbdb64cc53e4f8db0e763ec68fa73fea0ffabf06
338	1	104	\\xb9f93e5cf45e439fcc8711cf7a4b2cf2f85b2f5146fe507f1092931c882b3c3832f0bc557c4c0cfd7459f295ee158c5d45f93e43fbb3e02df671c9dab12e3b0f
339	1	373	\\x68dc57010c4c6c76fdda70a1794d5a7e856dfbaeb2a0cd8b4da9f26b35ec258f7e8e47d398e60857038cda1642809b659807f7e54018691e0c7ba1abac9e370f
340	1	401	\\x3b35b61e84eb21518f5576312d983bd969a0c0614b9793cb011d5dae92a8872d8c51c4c1148f720d3513c99c5d3db18cca36beb58573bd6c8a1670b3c2f58c0a
341	1	259	\\x5f2fc71a589393ae58414d5f680858a5befeab1bf93d1f53d090a72bbaa9c902ae858ed93d79f0c445c3a2dfd5c532c2140f4e61da18dbb6c3ea9f2bcedf010b
342	1	414	\\x6205973ae06a0b2f65be7273db6d06b397c43ec8db294aa7e8b004d18a070429e4782d537b7eaac954ce3b5f13ccc17b994295cc01c4d48882ca3d25e335860a
343	1	366	\\x146c35f53079e17481397c24d87cc2de88f636cb552951ccbc343da8543f2f92c6770086c8c94c778b579588e6ae7737b7b806494523c5ed194dc4bee41d7a07
344	1	21	\\x47b1bba0320d6e5c8d125f1fcc5d573eddeae6c97a88162b9504c3e05ff14ffe15000e94b31d9e184bf5bceb19ba731a2e0f8ef837faf1154bb96c6ef218e801
345	1	360	\\x755577a0535cde266b6414f2410aa71151cfa419ac04569f7e7018c107eb6bd035bce832a1c8446290dc1dd9e3f78667e3ee2dab99833460ab4ca08944aa490f
346	1	326	\\x40f2cd7bc1b8b20ef06d2a93667db493e7cd97c50dbbe52070be7cdba29317797fdc674b8ee22c2f2ac135061430dc8e3a2aa1cfc7fbef80fff91ba0d8689d0b
347	1	255	\\x37712471deb8c0ba2a22b4184f89d1a0eec133c40e40e0ed029f11dfdc8655a062a3a162ca09d7f4fd761da4bd8a4bcedf5e925c95e46fd42c5652c0118c1401
348	1	370	\\xff932a7e0332fc2bbca102a73060fdb4389f95dee6a8b3883177551bc6ec3925c271a939c2a92de55cb2539b67009f0642787d9851d22aef6dcae63321df1a04
349	1	131	\\x7e2c518b0146cf17d0fb322a0fbbd3a091bd872f28df4ab7e05dce6854dd8f7c628986a14d8057d6801c9312a5a17f0a121649c4a617b58905f1667bd52fc200
350	1	257	\\xc5a4b53efcfd45b2010426fc5c65dbe807256e99ef335942290f3554421565da5e7061afe99053a14015f2a309503af1f67fc58ba9f43aa9754a2e2a0d255500
351	1	100	\\x534131f93719c866edb6ced9f4c4303d596d50afc5a2fb2b77906207fb922c41cdae6513ab639c734a21cdb54bd8f12485f0dbfe569d02a4c32798325d0e090c
352	1	5	\\x53fa49bc348f75b9cbf35797d0e5a4a21c05e34c5883521c71112f901015f001387208dc9163f5fe9d9bccafa9a2628c709fa9c7dc3503b0387dfbd3821e6f0f
353	1	166	\\x35be774d57c478a18d25ffa3d1826d6fc07c084520b0caf8cc0a9e9b81c7885659899fd0e4752dba780ff6129ad9a0541c11775c4582c5dc3be5e8ae8d368404
354	1	96	\\xcf2f708d72b1bbcf8a63141700ac07aa44ccaa44dafd34c1bd6b1d4541cb1cd4780c520dc523c07c392f11be9d49f8a54641fc0af695c44c230c8692a33c8a00
355	1	266	\\x377bd8bea97337360d0816c3ad31d0241a8389da6be8db6387692ab856b21f7d978463ad986af4f652032353c5dbe0673817f4c1e7b26b86c010342e500d8100
356	1	229	\\x2c60eadfabb40067714055c84fd252030d2a826594d8cab9a50f0573607ae74014931866aa15a7b03a37a9aed43cad506ddf4975c721d92df96440726ca6f903
357	1	302	\\x267fd651f03b96f6213dbf536878a9a908b291267fab5f59d3079f82cf3c1c954f6eef29c72bca981d36300d78b209fae2e4a2ed3338d920dd7b59bbcf744e0f
358	1	384	\\xafec49b8a9ff8e0396712666ec183c8f1d3508f1db0f00944e669300d0cf113a56a6fb36a1a478ca156aa57965650dcade6f3623e0c2c738a4591d57c55aaa06
359	1	329	\\xd03b455d2f4f11462f815047f7261e79022bccb16ca10948315123f9c3eceedfc446989d92592f7e2597180f44e359ecf974d71c2f4c9eeb4bf5f61b76e43f04
360	1	285	\\xc721cf5ef5a7a8bb03c37e25da437e21106c5335e49b917efaa24446982e73c78772dcb64a9997d91a733116e86d10f154da812ab1dac488fbc872034618cb01
361	1	304	\\x1717298808d82d81a686161dfc7b83dda1629a736d36bcc1059569d399872dc7c678f8d6482ab2ec7033d34ed397d41a9784cf3409f158f17738efe154fc0700
362	1	125	\\x2df92498647f32adaf2a511c3be60c13d58e41e525ce398d37204854aadd2383e41430136f86bd22e87f71e918629585e7528f970b1c87c66a8618277a04da03
363	1	271	\\x0af1ddd4834f3272ab043d19d1f3f9f238b74bc57a41c176a1b4448d128c778369b45f43ec11945a81a23bfefbe2a68ed45adca9a3b625531519a429e9390a04
364	1	73	\\x7d587cb6a2a499d19ac4c3ef159e34f8f73a53b6417b1e20069cbc3c4a8ca6757e409554dc20bdb9dd8da384f9d569419144a78952808592c56c0a45a9dfc40e
365	1	34	\\x4be4ca5e3438e4f53cbc9926e92f2606f09bdb4e4b3ad54acac37e6a10c15c6a6acc6d91e61fdf59b52e1825cbba7b75350521642303340a787d46eba9ff2b0e
366	1	303	\\x7ae8f197f94583f33ff7eb84097b0e70abe297337c9e605e8cb8d63875cab0b26c477db7eaedc1a498bea15659fdc0d7070fc6f483346e7666bcefb09f896802
367	1	58	\\x4cd3e6038600485f647a1b1dc11c6b6c7656ebf543071c9fa19230f5a30dbc822d4d0d81b78ff92c9cdeb71d4a7a922d96f947269c86d3aa3d526248e096200d
368	1	9	\\x50ddc790b607bbe4404e52dbd266967ad01a12bda6ef253ee7d87dc8f02ae0cff2149b519931c63a79ec5b0ad36245fd2b897bf41d1facd94eda003746ad5205
369	1	205	\\xe9250cbd675affc900c380af8a4ce6f4c840aab37c645a7f97522cdf4b531fa44269dcd08d1679f00d0100d6458bafed743cdade4e487289ca49064cb5b0340f
370	1	412	\\x0e8614b0d621555baa8ffd34590b80f03ee8f49b070e752082aac7aed96976ef55c3c5f836bd016692e232f7b1bc26722b31651da218217bb161f499abb4e80e
371	1	35	\\x7dce37ac6b8e232aaa3349bbb728566e35a2eeaec69438b4a2e20def0ee565115ca78619b73296569ab234c4f9842fb0fd2739259e8ece182654975ccb1feb02
372	1	65	\\x7ef60fb720ae3993490b313d1f8b1291687b992f3030649aa8adaeb550568410fc73b53d2c69b0bd44f1dcc1efc5925fcd4eb7bff983ab07274f44721ed7ac09
373	1	40	\\xfc535394cc64089c49f12aca90c7aefe91ece3d8249a6fa1381dcfb7ab68efd41807532306df8eabe7592f2b746ceef422bc3d3d6a7673b50f5e16827fcfc30f
374	1	202	\\xaba9a3ded2a872adb92040d3b285a9a3dfd3da04f84952070f42fc5d038b0bb8b14b999f84755034f00ee8b653da9463f5dd479b1a084b52e9598f50ec8e790a
375	1	219	\\xc9ac0cb08aa599508d7102744929c7d8b38f944682eeb95731e316fd48a4fecb2e108da9d0c68b402bed8e597aa11b614b4cb02531f0b06f6a66d0f396e45306
376	1	286	\\x37b5bf245a0850ed2011f48fde8db56377c0e8e0379648332b1d0d358e1b14c1007b569fe484cc7ebe78c038b53130071d9479608370d71252adf10cd9d95d02
377	1	347	\\xf3c0e8b9f3299e1f99f210037536ef63ee795e92e5422a6f224f92ec94a4e8e43727467423d8b30ff43185ba34464554351670ee0d0a6f449b3abce5fe3fcd0a
378	1	415	\\x57efa4597053aa8d73cf0aa8cf884e516eccd0e1f69760ac8c108285f4e16a46a0d240767d5f0e4bd1e2ca93ec07bcbbbc121fbae4ee3dd519a342be9f90860f
379	1	358	\\xcdecdec18241b3e88adc6478cc2d93fa756c77a2e0dbfde93ca01536a4f5f170721b77e4baa4e100a107c2ca8e476eb9f55d0794321409c52b16a09af9599c01
380	1	11	\\xa5109bca1c652e94c1936d288010f43b4383d201a6f0ea10dadb37938bbbda0caa483aaeee824e9c2a8495f84b6bfdfe106ec5e9ae122591101ddd0218941000
381	1	333	\\x44045494c56c10da2b6c8749097ca03918af56d4d8bb5f03bba086cab5eea44f7fa69ee4f67c56c5adbe266af0aa823d5c669945d722887fe83fbca95e332807
382	1	17	\\x524b1e628ce53016d99e3a720eb7a2223469766c15eebb0ab4de7028ad95309cba3efb0a2f51a646b9ac165a97b0607d1df87c44475238de820c3afd1b86d60f
383	1	50	\\x4b40a8756790ba16bee322dedf80f7ca2001df5d7d35289fd1ed147d58f3b81f66b4e7040d2906e327f02e97b617245191ae86c8315632e5509b5e6be3f9b200
384	1	138	\\x6bc95ba4bc2ead8e4859695daf5aa13d6341761fe91ccfee294911e4b8122f5d07d0a4db703a2b5ccc7387bc5ae7e3f3c9818f07ac41ee8ff156544f95d0200d
385	1	389	\\xc59ec70300a6c77dc1ebeced282681bd370dc4c9ca62cdbfd5bdb79230a8267ba392ff10fcd3814acc8a3be5a5e489b35544dfb03bdb9f84ba2f813bdfc22803
386	1	381	\\x65c455e2e6e7d4ad9ec37deaa0a957ae3d1a7565c6146702148b2d37035aa5b46318d214b68ed139cb55b0caccda53218947db37fad616bb68df489183e2c800
387	1	156	\\x3f006771aadba2585114c152ec3c8b731305bb698eccaae0b969f0b102c352af42ef89b103aae48e9e5f5ac1c194227c39e7436f2529264f72e6c12c7f87c906
388	1	64	\\x5c5c1cc5140248903898cdd337af2faacc50bed116699c54c2fe39fef7beafb308a032a018fa1bba8c6c0b12ab1389dc6fb9e71d7569c7d3392e90c656ed9303
389	1	165	\\x8987a9aa71e2e4e30f0c8a94a0081e161dc49b79757a8db402a6f0a8b6de81f5f1253a0c707fa7fe5488ef04a54d09d32453894e1a7559d0f2c343b13041d401
390	1	334	\\x1b8b5a717c06b372ae952c24bf4e33a58174c38f9285d24b102699f3eee430262b56e9d26dcbf363adf0440cbc48c17b4a3cb360a5994fbf4346f841ca864a0c
391	1	235	\\xc20049f9caf8fc350963b7c325af8333f1db276395ba072539c12f42d9cc3a78981eae9985b5660bde5e930e6c90abdc70cfb5078d3af683007b42959f4cba0f
392	1	323	\\xe634ed2f093471296b0fb539173a71f423fa8deed2abb0e04179cb394b0dcf4ffaf2e407ed6194cf03a674b6d53456ffa064d257ee1e0c80d8822552ab6d1505
393	1	174	\\xe4654e5e44c1b63e0d69891c126277d568c1c9d9fa01a7e5206908fe15d5b74284b3b246dac5c4f4ef2bdf4514a9606ea36f9a128dc5e51150199f2d5ca6e10e
394	1	328	\\x9daf682f5e2133c73a425ff0fe74ddc717025e0ea2bfb240a103e54db8017781782d0d0aed7e5d746bc3fbf781de16aabcef69f7158e27ef61aea31b0937d30c
395	1	263	\\x4b46553b2e585aa95bf7ed920f3317746c29d0586c3ddde2c77ae7cd906d69585f4b24971298314ad23ac0f3350acbf4436bf315a65cc3bc06e8566b2c73ff0f
396	1	280	\\x6da52fe8bab37d12e4cf20b5f937884659de0ccc1f8d03bca8fa8761295992f84fcead7ba3af2f94bc78be8be6140e3921ee7bc8175fbf0377878579b2c5a90b
397	1	95	\\xc0b3a222d8982fff10850dd65b9cbf6a5e47482bf9b8a888d3b21e1978fb8c32213f2fb8fcea95ec7bd28d5b56b2a14089e30cca4128d27f2fe8ec7d87b8e608
398	1	77	\\x717babe31e136138136936e7b430afe1512fb64c4546747528bc1dbb757bf01f4717e843e53e2107a42a2da8cd66c2573213cfbaccd84190f6777e86e9800808
399	1	159	\\x801604227e8537a8cf5729b1796de538802d6e47a3e6a6d0f67c6b2b79bb0c969ac18d714d4efcd0925dc6eb3e77a4a8aa7e7fac2c4a0ee07e3435a522a61d00
400	1	238	\\x53942282a7afb93920710343679972273977cdd338c28cbc994b6f96a97e88aaaab6de2458a5570d39e80b8bc6b155205ec9e3bb49ac28ed674399be5b774705
401	1	129	\\xf7902258a1ee48322b1bb58fe5277f565f235c3adec57d99b38636b2d9faa9bdc3483fba9b4cbcf098d17d5776d9ef0cbfc88a88c0ce04ea639514d22e4fe201
402	1	24	\\xff4e2ed6cd63149fa5dcf7ef292130bd6e0284bfa1b6384dd00744c6309491ac2d7d44875f2567086de4b532f662bae9565f37c71186ae27f43c147f6e27da0c
403	1	367	\\x766a40cd44c2e096626b705a3f2ee6f322c59bddf309d71b0ba985c3142e679f12b5bfadb17fc53a6b54b67cdaff32071cf2ec269efdb53635496e8a6ba7df03
404	1	423	\\x061efe5b6735c1bbc08c09fc2ad970580a4f13217243bc54b0e2596a4856d16a4ce288fe3733dd7561ba160c46c4d810d49834ec7c012fd6846ccdf91ddfaf01
405	1	281	\\x468bedcaf282da35c1ede210e25a591d0d21b3aec1e56461046c54ef037c05810c13a085b804e69555f9f08411c0991d20cf4d832cf57b34dd580c62e5681b00
406	1	84	\\x12d15ed952ce4675e80dbf3557d6c13b2afe9247425cac73f21de51293a8b1dfa8f9ed14b48d588b9557bdd6d211401bee01f8842d61b33792f8c50f9767a402
407	1	160	\\xa070b469f41f84ce86953b56c3edef7660d61e64c621227478c07ae948ea87c51ba2f7530294190e33d80cfc7ed1adc60cba20bbef2acaf5c8c21ffd64504206
408	1	206	\\xff7561f5a5b48fe8a2c5b4eed49f1d6dcde2da498ea60259d92132236b43262786c8ff25d5d3c6b1a6729c482a4e3c75b960d77f4eca0f35b18f5a6cc1ccd606
409	1	142	\\x07e4b76e085dcba566896e0419cb1bcfbd9498ae0f387166cc6096f8b2687849736f2e36bbafdb17e5bb82df26978049678e81e88701e8b6be70cf4da6f87c05
410	1	361	\\xa8539191af76bcbaa0b68925983e9c0bddbac8a5bab7546b7c169103e0107422a16ec73efd8b7b4d6280602bdabf7f662571ffc084fb47ed144981442ea52201
411	1	400	\\x13ede071bfd6794641198deb452b38226f4aba36c6f0d0512d74654fb5cb0d9ff72a43a7df5a95b64e2b4ac231e6e1a36d1c5c38d07e71da7f764c588146d00e
412	1	22	\\xc1f5d189af0f6f971e823669fd4aa226f1db0f8ef4eac28653d77866086fc8ac143dbdeb9026b2d497220e6fb51e9cdf766ee2db645608cf48c3a6a43f57e206
413	1	383	\\x9f2ae06c53b94da92e3a114397d80580979deec5e7e27063817f14463033bf3d2434ad877aba2b34ad2167940a7b918d12e9e7a5128ee7476ac6200fadc9160c
414	1	288	\\xd45acb849d24627cea9aee74201c14a532331076c7cde8777c9532b42c8ea20403b05baa5421db44120a2f6a4dbea111732e9fca5484c3acf03b29e4a765e506
415	1	147	\\xfe9708ee64053e55288c7645eb1f458036cccf5ff108cec7f4f8ff610f1645d4c9e54f046f21ad203b433d427f040922e8aad087d380aff91081b658f1fa5409
416	1	41	\\x46b259fb65d942ca90bab2723cb40363f4e11b0235d53bf4e1819db1c8242706bbab4671aadc4d42cd51c0bc6b9e0681863213e3450af2f774203f1e60ca170a
417	1	339	\\x668f2fb3828ce20b1a8d5c395db1f07e300ebed16a243aa9e1da3cbec344c67853d919562c7ae090b8e878bf58867beac0026045319bfeb1a56545402a636803
418	1	20	\\x12b19d4d344fbcfef68bc7ed8c8f9c73f2cc3c2a85d39b9bfa7f2ce9c92a2c62274a1f606758962b1611c1cedc866a4a6d1319a78a29ad3b39d2c61ca439ad09
419	1	178	\\xf93971d96e98444aa698aad726e3305ebc51e420d84db54809344ffc939c54ff9ae67d234e7e1858789ca0707c35d9ced94d466979fc75d148e8ee6c346ab105
420	1	422	\\x94459f27407c4e9918d1d7bb4e1f26ff655d37f25cef08d5cf8924c77c733494072ec3a48c8f14631fa2effda259caff5f3df2d84dabc2b9b9e8ac4e8c8d8302
421	1	109	\\xed645ab2601cdecf0f1eb4eed9ccb77e9aea34211fde4bb95749961ca5b298b38689f0986fc56a040290a8c021ef72c7f0ec4f4c38fce12b8b02514628915e07
422	1	289	\\xc7d8a740a638427b1d39fe51c604892c6fce90dc92ca84902aa28bde53042cfc443db3089b1cfeeaac3c9fa06c9463d37e1977a23a66a949dacb97c78bd61a02
423	1	251	\\x454a66a959b0e9be9e0f2fbcadb984542d3b370161a61e90cd27f8ba930aa239cc633437512381198af666d630b5bfffb3fa6045952ca2ec734ade1dadb6cf05
424	1	330	\\xbd3b10850233d31f6b7236d79aabf063818dbc5fdb1c57e48f33de206d0b55b8844f87994313298b83010708d0834cf86b4fac2ab07e6275676405ed0ecc130a
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x4bb0e0f563c5303c877539c41f8abb0a7d87fd7598f9e35dc14c522d71944394	TESTKUDOS Auditor	http://localhost:8083/	t	1660992754000000
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
1	339	\\xf834eba8cc9598d667fb83df7968ae43126e86cce480d870733c9612934d197e1d3c8dbc8e67f11b22b462f146891b493946d449c07a4d16316d8e8e2be65a0f
2	400	\\x8df2aa8b7db47277868d6ff3e9845812523be94cff3a9c72a25d1f528fbb84709eb609aff734c8ec5194116d5a70a6d5cf0a58e71aa06e2816b3ea5ac90bfc0a
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x00144207a8b0035c749b4357178f2422a51db610d3ae8743be9ad75d08c049b2f4c40568722a64437e0edce345882ea87142e6ecce072b51b1c7c286814015d9	1	0	\\x000000010000000000800003b2770e18d0aa9a76f861e5c4d565c28d6c9ec432660f48f0da6c14170c605d9b07c5ae5db891e591b230ef25ab12324d50f22d35692f6fe8a2d7a7a2e40dc196e7df5fb3b76e674a29c92651e6b3c6606ee2258f5a75a829ee9f65f2c37b58395b14abfcb761e8ccca0c1a17da885438fc8394c6378478fb5a6002af2650f96f010001	\\x54c7b45dcbaec39bafacfa78382e35d4b3c56996e595a03df5987bea2a9131c0e899048f138b928b2d8d8791779869836a8a4c1a6ac707e383a649d02b8a3600	1676709748000000	1677314548000000	1740386548000000	1834994548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
2	\\x028458e8086a02d79bce23cfd462b17f8f8cc9e0e9abc4f80d773d3ff3cd6a669520f3a67ac82cdd9bafa052502b43b0e278c0cf54016e2acdb9613ece029e3a	1	0	\\x000000010000000000800003a486d01dc9abb48af73b4fd38f2ce6d8c28dbf3777d69da956d95c993f6e41b5b2e78cc93f38faa380462ab3bdac6527898cdc41d2e1f8eb9eb1e9aa8ab8698951665fe5a53f3e35c4645aa2c1267b7c937b24859ca9cb51961fcef05144e3b21e7f2c49d1b354fb83f11bb674958ae8ee01186e328451901ed04609465fd9c7010001	\\x0c2160934ecedfc09606c02cc3d29864307d7cbff9c8ab8efc64196ea28a373cf0564ffde61b621ead129eefbdbe0ade6ee1a13a661f6ffcafa5807cbce93d0b	1673082748000000	1673687548000000	1736759548000000	1831367548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
3	\\x03749f84ca0d2449e354c25db4033f7a8ab2c32fd856908df4ad39ec415f7a92328a86f81a09fda2320fa17e9b34bbf7a5d235a8b2cfc16b9acf819f30ed27bb	1	0	\\x000000010000000000800003df14ad311462aa82b2c7f2014343bcf3c511adefb39ad58b5a9f582f1d2cf196223ad64ed38b3ed75063c349ce55f36f5afd33ed1e3e2907ebd64f9009222e1c5aee528684311bfe1fad4128472b04f1bb63d2b2f8cb58c2c528be8c2dc24e74d6a38bfa148e0faaaca852bfae0968e03b5c2e226974f7a2ff6677fb7136ca09010001	\\x7685620cede57289bdfa3afb72b970fd0b4eb1e995fdb513331b90d405603020ee2c3208f3285d80db24d881e92f3c4973c6a8184979ae8301653ec8931e6600	1682150248000000	1682755048000000	1745827048000000	1840435048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x04183c36da8e6059f0d519c279c57724f86f938d7e4fff8357b9b621b74cdcdc69e2a048c3e1d32a240f85efe11b5879a745c56fd2b584f14d903f21880b6571	1	0	\\x000000010000000000800003baeaedcf8727f5f773c8afc606f19559eea24b155fcfd1180b0279162f77bd4d7bdf044357e39f42c1e6ededd29295a42424228437a6b043df085721367819e6205af0cc6c0e3e9ce30af1f1aadb068e489351cb43ff28672e32583eda9a2cbd3bf0b5074c759eda05d1cb4fd18e4fe2a8cfc0ef862355fe08e5a530ea4abc3b010001	\\xc8d0aee566f56bb6a892f4db3acaba4c5ffed857553baf018da0f154a4532d156cf49a0b61712eb302ac97b7f7ac1a8ac0ea438725428357f675afc84e43c900	1689404248000000	1690009048000000	1753081048000000	1847689048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x0b20cc7129123526f4cd709f428ca95b2466d4f40db13bc5bce708a0f9117269545bd661952612bc2880460131523800381332cf43daa43dc0540a736f42c804	1	0	\\x000000010000000000800003b954a14143c6a465b512b123e3ea711dd889adc86f861cb8ecff82a307030af530683c477b09f3d1c10350e331b673ce0b432b228601a2d77bef82cd806e91af3f65d75dee928b6a34f8c08f8f18ff1539557dbba8558116d5b0746992f7b4532b352dab5477c6c24c2cf0782fc98440cf2ea33f10f8da1a82ff4b1c095cd3df010001	\\xe6eb713e15504cde4bbc7e950fbf1c1f96d3e57b3c0d2cf12b768288a642a791b255c63b113c57f27583ba8dcdc05826a27fee61ca925053a91a72e5df72b50a	1666433248000000	1667038048000000	1730110048000000	1824718048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0d40a7419cb3ec593ea30501855bbbf0b2dac7b06fe0a92d9c9ff13a605dde277b29db31d401e73bc7d72b553b736b972389e6f7d89008d852c1c311bdff9922	1	0	\\x000000010000000000800003a95e818a8b3cb8502ade59cdde8abe57f55b80072615fe0c17cf230e71da186690f32cf719f19c73c77bfdb1d3d9238f2575f92631b1a9d21da25216c237105345511fbea1dbc58a8fdc819dfcae59210a97e55ef6b91c5f770547f04157d79af0608449b26c2151a3bb1d0719514ba5e403779aafb144c5f03a7978b3a7ebf5010001	\\xca2d19c1ab10d5f437347b1181d2ed2e5e638aa3c278111caf8298648a6b337704ddd79f42a2da101e20cc3e618c6b871b0bba556ead33bbdc6ff6ff071ad901	1683359248000000	1683964048000000	1747036048000000	1841644048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
7	\\x0e986b3aa8d977eb969d59f1c0df0504a611487b968d3c203b790a2e7260015bf2b2c34493a5e4446ae6187bdcc977cd9c381449a596a21690c433b73dd15d13	1	0	\\x000000010000000000800003a512cdd0a8782d97849818bf481c249a84d54f3f84a3b08c0168de5946f70043d9647b8a1bf00da92bd087b408ebebb565c7102f5ec8c975d20a72a8676b2dfd1de02c7a33e40d5fb673b43fc030a3cb5ba106bfc8ead901cd5ec6c7335b4a821d97196bdd184edd4a4f3ead3e17eac80a1d24bcddd9950b0b67c31c8b4b4759010001	\\xa948ccd294ed6c59281ec758c3d6a1848ce8386b3856991625b678d436a91467e84b6d567b4e8c2a3130515fd70f51b3268953303041a96eef0dde7b6608e605	1678523248000000	1679128048000000	1742200048000000	1836808048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x0fc0269a8876e3dd77a55ed64afadcddb1759f8d1cf776b5f8a64578400b0da3be6f30aeb8177784363ca700ee4429f7db99787b1ce9dfede7dd7aa8644ba5fd	1	0	\\x000000010000000000800003bb4241bbb1540ed3e8d98b73c4804dc3b6d9d4bd4686f48f8cf6f24fe7eaa8e9c609403e30e50fe7901ca8878400b2974532333dbda94e4554c4f24f84eec1dc71ba53195d359339bb8c7622890cc5a505abe3657c7eceed22d3c34370421244aa50e447bceea72d41c414105a7f64ed3029a9dbaca45b97d7aa0438b22ce80f010001	\\xcb1a26b39794ef688fe9a57aef30d8283f2bd8661cf551946065c713dc0c78a78eb928167449f2c4f193b896729c77ccf0867c6ea3572e11b262fded8853a109	1686986248000000	1687591048000000	1750663048000000	1845271048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x116078711557d0f152308aaac373a2e2cdb88b2d3173d0ab763d5094ddd770b672e1d502d9494aa2bc53c562435e083af2b303e0998042598ceabdb328ed95b6	1	0	\\x000000010000000000800003c1601d121cdbfc59eb7a1ad8c422c2e928489c5a407b6c567434c9c708ac8223ab391eb15415a7e4a592e9e5b468c11cbd6bc7e96901636587e68603157620a9dfc46bf1bdbac2b6abfad40b9254b81575e2b48179aa4aa96d1b035032516df5d564161a825c38b68edbf78608e9c3992d4e358ad4d505246f0b3fafb1c07ad3010001	\\x65244acce9e1bfe5be85c27a6c25b02a330ba7dd40975f88f95a507d5a0e526350da7c4becf1484e0f859f24cb9e47267c5122250e2d8cf909605a5c703d4302	1665224248000000	1665829048000000	1728901048000000	1823509048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
10	\\x1188679bfb408bf3f364131757329206fc0c9d123f5c69483bb33a765a9896ef36056723e4afd4f64876096c13c1e51dd8cd1e6b23874f5f227927dc0c9c6542	1	0	\\x000000010000000000800003acd96b7c2488472fb96387c3428535a7e5a05b627a6390e8d3249ca2069cf833268c2ef4565c957a54e9b342ce4edf875823712c09ae703a579157fba277327ad4ee4540445d949f1f0792582de37a37f7b92283e85bcdce6df3f0ae4fc5830c75af6596a67ba11855df09dfbcc50fd42154799064620f627cebaec8e15a79bd010001	\\x4d457ae8b6f6997bb42243b294bd3361e7e428f3086bbf3a6a9f43ef7925d7eef2a66c98db8128c33a2fbcb4203678d438f73a0c2163430818a8fc788ac31c07	1690613248000000	1691218048000000	1754290048000000	1848898048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x12f4b03351dad64cc386efd23a4bc33f8e9813e81f1b73a5dfdc4a63e469d914429500be6a4383036466f3246f194d95d538b2412474b9181db6aa223dbde897	1	0	\\x000000010000000000800003d439ff7eafa72560c43401be81ee806e66349c455dcb0808632d259ac3c545b94be2be79587cc6fc930fa42900480e09f96c233ef3a6f95202d76b6208205e1e5224ddc40e7e99bf823eb62ad8a9023593b6adddbc251a8358f622e10893e0e0b53d90ddd006cefb199c5ab7e65f71b0756d9d5edf543a11de56e3d08475fdb9010001	\\x5490883c6aeb45c1ddcb2faab951b94cca8ec5aae6717ad4a2969599749bb362923f2be31a471bc9b1f3961143d8c9fb4d630b698f329b9ad37a4e7f11054b00	1664015248000000	1664620048000000	1727692048000000	1822300048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x12b0a971334ed10053e5c22f835a3dff0f3cf02d63509e89a1e86f181e2e6719c14c4b5294201d354a15c65fb5ac626539caee4a29b94f73ccc5ef2e39ead9a9	1	0	\\x000000010000000000800003cdab3b418f3e2aff9781f4dce9f64dc9fc774b0935b3c71ccc4873b22fc73c94dbfd8d8c02463d69c828ef09d51d0170ae817506f43861d95a57cc7b69415ecfd86e7ac3cd4e38b5dda17505e9909385889fb8e53c17a8255a380676840fe96bc3e1ba95afb14ba630494385cea7bc6abe6e0f7814dae3a09e794e054aa64c8b010001	\\x429703a83cb609029696585efc7ea16545a53fce3ae847abab5015ed49b9bbb58c42403b2bbcd2e485d92fdd747a8935c122f66af69d2c5c0455be7ae4f81405	1692426748000000	1693031548000000	1756103548000000	1850711548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x180c95f92194bd537b7c33640579409b40a595764510b09a2fe4067075f325cf4837039020fba79436720a198525e4e4ddc574d380f3c8048054cd9c5fc0fb8c	1	0	\\x000000010000000000800003bc4e09636cd4abeda2060fd4d375d90ddaa43580231d69e47f14c7b790d77390486035471708bccbdc65b043ab162189916e746d1fd0d4a2f55cce9d5fc652ada83983815ef25e1654db7e53d8b66752c37fe3af2ea896a55886c11334bae9539ac4e8ff4d54144d7835fe7155a91effceedba18e411cf3f6e794dbb695af5b3010001	\\xc326709566d0c98c969728e484800eb327db58a9a34aa0123c10a4f18213ad1b1d716b868c00892368fa791ec54c221dae01fc9b5d0dc44959828c6fd320430d	1683359248000000	1683964048000000	1747036048000000	1841644048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
14	\\x181cbcbb8884c7e8abaf559472d112ee861e3fe9980a7742ef56c6840cad3cbe75cee7bba4cdfc49a15ad025c7eef8c3fe8d222840a23b8fac9935d763718bcb	1	0	\\x000000010000000000800003d7e8ed16169168d1b26c3197bc42797133febdd7a9dcedf1887c4108e83b2cb2443a843136df049cdae10cd7fa185c13444b186c59c226562b3c68f008232420aa2f488f078b8e6e4d45dc2b727bbc0b6829aff8bd9375d9d621d714a32a2b935a453f2a140ea0cf527c192033ee398e23864a09df3d01d0a52b56269c6cc723010001	\\xf2cf6640c319f5f412184718459e901569ed01e2afcecb88e9bab826f503d16303dc9d88ea41b882d79de1f202bcf81abe8624e4f7524e5652399cc04b31e202	1686381748000000	1686986548000000	1750058548000000	1844666548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x1b90ad0babf50db3de9d3eadd4a33c21e706070abd16556024ee5e816ed7be6790176cbfe0075b75fad8d93e158e43790c54ee6ca46961488de4974096c51ea2	1	0	\\x0000000100000000008000039929986a25078eaae92cd831f3cec5964ad71f46d336883faff1310d17bc72a65115163a3b92436184471a66d334282e44408bbe0b349613f47b28f52f13e91fc45fe55635e9dc0c5f20e104b3f7425fcb4f1ef44bb558f81217d462ee3504dd546096e5297aa6d730316e928cf0afcdf23ae970c80b33889b90d55e03a72005010001	\\xee955cb5af7ec89a1751997260b6376d7f1ae60cc61911fdd71d69de0fbf18a0ddca82a5c27031fef7c47f9e23ae21b1b29ce4f066acfcd92e88b2a1b8668a00	1691217748000000	1691822548000000	1754894548000000	1849502548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x1eb05b94d4e13d7f384846450f0213b313cb7c550ae43086d6516a1c20baf59b85fb6fcb309216e77f8b879557df408520f77b206e7e48d66ffc4fec3566d58d	1	0	\\x000000010000000000800003cfe4e1c85850b276ac4f49a136e4cce5d872454908ddcec2a740de58c61322ba8f9f75fc133f88bfd779eb4e17a8268dcba2b74b73773ae8043df92ead2530145fc723e472e15e7e3ca8fcf89c0f65802a6776e0d7ad4604f1512a49e875b1319d4c67f2a613f341a2037f6144deaf4e6c3b039eacd2b1dbece64f9db9025719010001	\\x5834b42ca47eae033720165a51c0d17fb19afc1bd5babab5cf1d1975fa0bddd499aa6dfc25d7c531800b180d989ab6c322780a93a8c7078376899c1851b53d05	1676709748000000	1677314548000000	1740386548000000	1834994548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x212853283015b22bddd97f867c51f8bbb9b2195c488766c28a584f4b035a79c2377cc17d5c7a99c5c5c287dbe84aa4d41cb6634f1fe86ada4784e70c53d2b827	1	0	\\x000000010000000000800003ff4764279e3abd8efb77023df0af29f954972db89948b59937cc3bd5e83ade744793e8a58d6230b91fddf35c1516f107c43544bf041ef24de0e8875b156801d714eacab9a4fdab951fa5c279fa4607a9f4cc458ac3ac683b32a29bbfea40dfb5d2a8a374c9a8cfb26bd5a7340a55fbbee82bc962ee2f574d23f5eec985ed7313010001	\\x319bc1dcca0fd59acb62420cc624741e4c068acf36ff0e080393cefb261bd3f41c40e190a0c5afeca7e80bd24f317bcf0eea327fde8962c8a54fc13232897204	1664015248000000	1664620048000000	1727692048000000	1822300048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x23802fd88409beed953640591df661538c3f99eaadba96a2d008b08aa127cbaba937cbee69d000a8140ab41847102026e848c29474b7b6ce00533c9e00b0db59	1	0	\\x000000010000000000800003b36e5b7b796cca4c13bb308a4891ed4f1e8b75cc305b57ea84ffe632c621a4cec3183994761f8eb51fdc35307b8058f94db4b6eef19b6b295960603a099401df9d07ef6f6d92f99f3259086faf012fcfe935742ad1369d66d6851ba5c67e24aea77656786e60065882370f3a958933e204705443586db12b6db5210d054199b7010001	\\xc1fb1e33e1ceab95200456bf5468b8f40ac5c0cb0c3e22264ec27e19ebed90d4c8e2d38bc9076293f0e734259e763d16e8bbd282e7b75b2704375de1bee79e0e	1686381748000000	1686986548000000	1750058548000000	1844666548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x25d47a558e05bbaf79df24e76cc490cffe4320b45d963196871ca0f9c2ef9b9973bb94aeecbce5afc37fd4ca29b0dfed5193b3787631179fb2b7dfa8b45a7fd3	1	0	\\x000000010000000000800003d11b2af43f65a534cbfad22696e93cd9fec594a431cdf148f51963d45972e74ef769f988c99d7385d99d709fcc8e9fdac83b3a685e55856cb03b4e858deabc82d74558beef1310a6ac96734f86c75e17875a8feef98b7168308139e07bd43be8187a2a502c914735eae964fff313f21b9ce252e5ed62117bf000da0cf3010149010001	\\xce505aa9eab970e85262ab53ea9a6522ccbdacea194aa6702a5ba261219d3df4e76f6e1cbcd572844e726f7d3edc407c83a8e0d67492ec751c5eccd502080003	1678523248000000	1679128048000000	1742200048000000	1836808048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x2bf8c55e328086c3e1ddb6cc5f366802f41600b8c18112ff10e926e6fa22643e55327b346e3ec28804215236dad5bf7c3f32737e156bfa1e72e8e46b297f4cbf	1	0	\\x000000010000000000800003e0014f10bb86be1ba0115850baa1cfee04c14908fd8627994d797212d95846557d5091eebbd27e941e57b158bc056145f6a8259cf6f1e18d46b875b25ec61c99066bb01d8c77d3d7a7a097e2d72d584e98dd075340abfc1a64dd963b3130bb2d5be0276d0d72b5e7ad0970aedd6119117ca37b0fc9ecd02ed04eb374d7d85a49010001	\\xaecdb826106a79419e31be5940a0cbec19502b526ad28a67b5c50aa488ba78deb34fe9765324cf55c1d199fff4ee81b89cc6ac0725cecf291b6f6519d702e30d	1660992748000000	1661597548000000	1724669548000000	1819277548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
21	\\x2c787d0e72a0e5426897b87a62f904c99f93f0299172b39e130e11bd79f0edd1d0771ee9d399e52cc0d4c0080e9d851406363b5c48fbf17a93ca9c7d1d32a5ef	1	0	\\x000000010000000000800003b9b6bda8c05f70f060b7143dd562b2e24ad2180f5584d1204ed5e3e733f6a21156e3dfa702bde84090578cac7be2c073554277235108b368022b05accab463488198ff5e57bcd205900b13dbcf745b1143817787a3a98a32a2638a5be3e5fbb0d22d2a9f58b8229e0d9ba35e43d9f370124d0e42a15fe16e72dbabbda124a61f010001	\\xddc0ea5c03068c75d0bc18d9e0ce9ac68240d6d86204ad603a30292b77888e5e8dc01030cd6be456fab140724d50587d6119554934ffd1473de8693830489906	1667037748000000	1667642548000000	1730714548000000	1825322548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
22	\\x2dc89b8c86f739fde54f8c7cc09fa590cebee5ef746a9cc357c7f9875ec411b299332413fc95d077ffd472614750b5941608fef54866c8e1313779f55c8e4b40	1	0	\\x000000010000000000800003b32fc173180358b348b6e0e21fb9a21368447a41b60a3167c1b18fbd8039ccb2077a6756e909bbc69d4d650ecae33d57dd5a4253c19306e604f08bcef6ca69a20c37121bb4c1a88812c69db826fa864251655c84736c56da6d43f88ca63a7159e0e3598c3c6016291f6de5463c98b9016e5d31adc22975dcefd343ff1e07a88b010001	\\xbf98c7576be5185d5f8872f4199b84c5c801b258cfa5170566a897544fa965c51304f9432c44ea69b44d7395db039d0e35c5764c4e0ad9f4041070cdd436fd07	1661597248000000	1662202048000000	1725274048000000	1819882048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
23	\\x2d0075a5c104fe77251f95372aed580942bf6a0328039b4f6c5b42ddcd908a3497725eafd78b91f2ef7520eafcb299daa7d617dd47167cb526b08755c55fcec9	1	0	\\x0000000100000000008000039037d9f8506a27c028ad368036bfa3a7db12013cdcb1f9a139512776aa3dff00bd12e4621c3a16e3f4cebe5807602da8e5de2af3e48ad97d74282e7f13b507158cc105b23689927450deb5090b14469a338aa794dc89d62404809f21a679552bb6cf69426162e3602770a05ccfee8de5c336971c912ddf7c3b88927a8e82f859010001	\\x3835a432276bce30416c7aabb3f82a7f152667942cf686162b2819678a80edd2ec278a9fed5d46e84c4eb8fb515db350e56893294de9d82359183c269f3d5307	1691822248000000	1692427048000000	1755499048000000	1850107048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x2f08753979a5789c9b3430eda8fbcb036f356a5fe6ab9591bc6f17c64d022912d1df5059387f3cc3a17316729ba177093bf0d33e78cf2494a95d2fd5168c6935	1	0	\\x000000010000000000800003dbecb6db4783e54860a09170b79584632fe1bb8269ac52a76a7c359989c2ee23205679158e6d3e1d7ca0e55e783c2119e294b2d57d6ed520710568702e9cb7cc040a3f1b41c452c5c34aff84ca43456a3dc82ac628b085b8beca10394441c9abee684391039644efbf16d8c263604783c898d0b6630cbd0d667fd79505fca31d010001	\\x5b5e86e3b1da6af7a9de983b8ff050ca5a362edeac4f2bd425de09f9e4e98111a5273354084cec63fdd5737bc7825325b95d1f71d8d69d79ed5aeb46fb1d840b	1662201748000000	1662806548000000	1725878548000000	1820486548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x3194c57f6a677e6bfba48d101ec683bdd6acb58bd3d1fe0fb0da17ae64c9241dd60e87702a0e1c3ccac8a2e26e79c8035279a15c75c5a43824715bda7c0f93e0	1	0	\\x000000010000000000800003d7ed24600131a8ece4a3e84642b336dbc10c86245f5c0076212a4f8cf019c7467607b1f4bdfd6647d5efe29c2ee14c4163f5ac9abd92f1479cd0641d932fcdaa72ff6452fd35d087213e7c73e23528fd859b207b6e21617af42fb53d5e4bf4c3475e0b1c5487e419b35723478018ada3796bf06df13cafe43f074c98c0dcd561010001	\\x599f468d180b43163aedd0136fd41a84bdb5f311cd0f07345896f96b350e851df9f7562798d8096c0bca0209065a2ee4c31e061811370012814afffff5904e0b	1680336748000000	1680941548000000	1744013548000000	1838621548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
26	\\x35c8f812f73f90511ceea2978b5455e24c8fff72e0bca2f8a436e965a9e0dd1440fe51977d0f3df2da3384d54ff401c75deb8ab0f6c5b6cba152d5c128431ce4	1	0	\\x000000010000000000800003ea61b56af2da2883ae3efcc1fa8b14bb95c4348c2bea98f95eb4d6d2ffaedf666d9eca2e20e8a64b0485a852374424ec77d12b25b660dacaed2feb4c93b1fc2603123a5561317ed39aa3b4b5d334215709d02890f7051dd5d2d4a9a8c19ffde30ca2f255f266764164991c2c684fb6c419f9c5858254045adfbfa5b3af2312af010001	\\x7e0d5a51c54397b0ae3a0528f591f527f5e3aeae2785a6ade486207b64cd1fb93b4e07dee499b08c2c75dde757c7defc35102b512f4988273b5536c0ee0ba207	1682754748000000	1683359548000000	1746431548000000	1841039548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
27	\\x352025623472e88faaaa4c7640142918d918bb21b2b6aad5c77843f3b2a4bb621fb9bcb5ffb021ccd126cd1bd8af5acfa42da069893c35e24c2504314b501d82	1	0	\\x000000010000000000800003b7e0894bf460e5e0851ff617c193ac89b38b13694068ba93d3f1f5c174b853ecc38c644292da7be5fddb7b6af9c7744fbc2c3c933c34af85da52f33290525f2a528a3555f6913099e253cf0f72f7fab4aba1e2ce01894d692310164425705ad97bc85fe09a814e0013b78442eabf601a66043ee62304e3f838db28d5b3ce6943010001	\\x8006ad2f2de770cf7389b559cece451aa581c9afb9815c8d4c4fa6090d628664e0d1713a693a3135432e97387a30a51c09d2eff9806fb5b613ff0faffafae800	1685172748000000	1685777548000000	1748849548000000	1843457548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x362c9e3e05591e3cd39fc42f6f394a22222d7714829d0984cceb942f6db9c44f217fb98e81aae0455d5ce0d28fcf00673ac50c0e86caa753253118f17d155e0a	1	0	\\x000000010000000000800003d745d2d511aadbded2babead751bba92fe46aaa130e9c82cd37254b3f9c0f769844ef8404b589ab98d960a67338864feb8f63697f2811d2ff5f5c99d90c491f37faaecc1bad2077125c3fcbd0f3edccb59665be9f61a1d400f0d57b8ec7818bd04ccb084805a35527829d09b81999b7ed01729dc0c1edcd799fd0a30f139ab31010001	\\x677341935c26085a05745b986c1fcce31569cdf69e0abb572dff41394148bbebfaaeca7d43b7dfe156ae1768c700dd8b351fd61497ffd4517acf7a350e04ba00	1682754748000000	1683359548000000	1746431548000000	1841039548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
29	\\x388453bda1b585fd20d85bf37c7537a9a59030b52a4cb15456a6fa619686279e514989c114fb3d8eabe260986413d2de6a2142142878874ab31e65d00d697d6f	1	0	\\x000000010000000000800003a47347739adcd3c09bdbcc64ec0d0d8757dfc3477f8a654f37739fca8d7789f5bcd8f7f9085bb4442dd96d51686f9614251e9bc4fbeaa07f6f82e085c59099397e24470b21b6a8acaf5d5b50b89039a8140445cdabc7a7d63dae206bdfab96a48fcfc93954f39dfc88141508b5fd9cf499f869019e83f072b4ab2810cad9d161010001	\\x2e5c4e9f9c38e356ea04b8a0b1b724d549c30885d89e6fc59c3209eaef31f242f93f08f85693f5576b85d54c49e648a909b4a7782fe3eca528f4434717d5f800	1691217748000000	1691822548000000	1754894548000000	1849502548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x3e70eecfb5cf341793300c0260027a25ee7bd4f3c3e076170e3b4f4f09a34a929218f0b4fced276be389aa9981eff93d3c99f8e68e1256cc7bd290ec740bb0ac	1	0	\\x000000010000000000800003b6074d3809c1e0631e3c5cd8e59578591f00fc90839f4f69ce1c988d40cc371519bb148524d81525b4081544a97c792d886ead927e6d8e8ff4ae3f4ee4d3148eff40d4ae19fd9f3ce1ede17d0b4297be671d0fb59fffb4677bff7e2a9cb54d516c188a6c2b5ba8ecd2f218de7d8fd75c7a8da16cdd7f8dc60b9b4eb1b8a33973010001	\\xe969e617b31af5e03e39dff54ee8367ae534d4cde77d85bb0c243fe37c0c074348f7905057d6e649af2e94359a1564475690ba34e02b708dc70dcd57b87aeb0e	1688799748000000	1689404548000000	1752476548000000	1847084548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
31	\\x413cf3b9b2160884c737832d97a320bf7e6889ce38302c7dbc8b48297b954cccd5a9f8916e7d963e1880fee41177efd6dde04858428a716875511a179512a42b	1	0	\\x000000010000000000800003dc5574b8dae070f59d248dc04c91624dde5a7f31e28915d55ca7decccbc2b0acb7d62663229d3abc53201d8733e02653836c6d0e2b88602628732f49ce8747bc9a871d755715fcdf17f268873ccfbbe753daceb6089de9c3f762ba47ebd66203c85f1e03cce09449565dc2dc87e3016c3aac6bf712020b2b2008bc527479da51010001	\\xcd4f7bccef99b3f922c6b57fd61e3d40def44107fa3715820828e24439ef7600a74d6b1a60c0b1dce2a4fe5063cf67efba6de5ce8855c626408c34d80cd83e0b	1673082748000000	1673687548000000	1736759548000000	1831367548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
32	\\x4230ea0048fa31ebc6a07a2c74c6f2c8cd64565678642267069074c51e650c12957b226ad4afb622fe207f5c17e6456877c9c6f497d3e9f6de7c35a1c986c4f7	1	0	\\x000000010000000000800003bf9d6787d6e33c1589ff36565d4abda10c064b2969f1ee6b8d553dcf9acb1c6db65a9ecc3c615cc3cf019da30c35859c78e7f22d0d27746d803b90447eb76e9977bbc3ce79fa8237c011a5e2fb7c624f094d09e18984139ca7a566e24e7b3d534ffb9426045a603a20bdfb7ae2191ca4300900985bafeb95a2c6db6a22bd2d2b010001	\\xf856cf2733630db3d6469db94d6164f5d2eba1d073c7d4bf27db925411da10fc6f637654c0fffd1d34c150ed10bb1f5f38c48be3eae46d38aa235ac2095c3402	1692426748000000	1693031548000000	1756103548000000	1850711548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x448897ae21deb4384a2e362fac2e37a57ac7dec3caec9a014af865979490d9d552bd61e1925eb9150423a59d0af142072c2de727705a4749c74f1f17a5e247b6	1	0	\\x000000010000000000800003b8c01d2a7df6d3ce17ae41122fb007d748189985dc7ac910a124ca19e32b9182bfda23fa2fff1dff7c915072471196d1d0c91344c754336977b8c38ac874f8bd67ef349961738488f54d0b591447b432f4f7b778b56973150516ea1b5dffa9620f60c4f76d0e4f4f72451c0bcaf201987d0512a04c6bc5fcca1211b650bb8629010001	\\xc929d62a3861df8384130737c41f580657c7889210cda46fcacfba2e7efe5deab78ead9dfca233395415d4bea30f618db20d91d87046ee83adb9b60a6f3dcb09	1689404248000000	1690009048000000	1753081048000000	1847689048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x44f40d99abb4bc241b82ca6148ac67d64265fa9cf6965ac66ecbfc822a0ee1ed9bdd22f14a17fffde301904daf8d8f71c54e543ed2a345244736c5e78b3bcdfb	1	0	\\x000000010000000000800003c07568f599e081b884ae080215164c55f6329421f68ffc5560e57dd66af164c4405b06f438daa90dbed12ec02a65735ecbfe7481d4c168d85e77f9195fdfdd6622f3485d6fd7954cde1a81122b18a0e7651b8cb9893a28ba4823e739e799bab85f6572c281535953cefe70fe10ea941af4eb626939660cd4c23de199a7f8e59f010001	\\x76a6275ee319232001b2be3733e548a69b4c55ebcdbd5a43a319a0485a698865ba7046c2f7793014a1a85052a94369fecbd9ff84a14de525835117aaee93800c	1665224248000000	1665829048000000	1728901048000000	1823509048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x47b8596b7db5f392a60ef8eea1f17b9b4d43ad10c38b1c6a6737e83ffa36065cceff4de37f7b8848fa4045cbfcb25e061dfbdc85ebd49c29b11101bfd0a1bb83	1	0	\\x000000010000000000800003ebe7c53ca70c37eff78d730dad3bc6aa6f22071d34caf7efc2ddecca9543a710b0a055d97d82e8863eb9d6250620b4cac84f3998be8557111894a19eb170bcbd0523806e7b024ad77bc9f914593a12065093a707bcd233b9e740f3fad4720f47484a650c5b414f4806b615d6c2177549a393eb110edb35d0e51b92b7ef2d6f2d010001	\\xd83add6bd786d11a1640d70dd3ea4981a094674555955f4b723627d0513e9c16022034715c28863819646fdf1823d4e709b7b7a92e185ced436b598db0248e0b	1664619748000000	1665224548000000	1728296548000000	1822904548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x48d0492da0af15eab6d2d3c9692f9ce4d19d8502ae34fe5ae165f64b5827d6d15142f4752bf91b697ca5891b3dca3f2ff4500f0cf9f8883880f15432b5a2d615	1	0	\\x000000010000000000800003b3c3d17f0691648e4c41c4dcd57b1b8b09e93e860b4f179a770a7cfc071125ea62305a7488548aaa1e39f5272308ca268de1d30d678b1521739f05cf54c764a8f96fda042c3c40b2789a076679e84a0c6be23ebb50085f22b06cbd1a5d303c214453f275cb3ae4f70d5fb6ff358d1f99922143a49ad106aebde5ddf00bc789eb010001	\\x8119a701489fbe0bd20a67e060cd184a5afbf7ca7903d004e034b694ad9f46d6ed4561a843596b058ce0f6d7823ec6faa2f0094d2f9ae82d9533b797483fa306	1670060248000000	1670665048000000	1733737048000000	1828345048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x488432e1719db7c1cebe97aae993b26b8b9e8cddae538714632bd5311cceaa6b7092e872ac9718ce7cec9670cefa2561a7795677e0cdde0c3763c95869d58ecc	1	0	\\x000000010000000000800003a90eb0613458466aa5426f464af0ca451b6d746c2891d9bf22f20ec2f74755c4e5814dfc93f19503e14ee648ab993cbe698c59849a065451b4e93b8f9b074b6a17951df9d9530ba4789ae0ff51b310487c8c440d4dbe539c63b45d64ec8d1dbff6d60d8f03c60c94a6d5c9fee8ede72d66fc35ca2c75aa24bf2441b33f0cb94b010001	\\xfdcf80bc5a58a2162234ca070c78a426ead6e068a1a9fa4924e6b28e745d325a44143f43e2db7b06aac2b84816b5ef0267125b5619907781aebd4e8818054f0e	1677314248000000	1677919048000000	1740991048000000	1835599048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x4a043f1aa80f8311b03fcc1d6c7996fc0ceefae4d33e8eafc2e256c77ebac9acd945b59119c99dedcee6c66080e0dabee0eba778435698c876933fb64cc88492	1	0	\\x000000010000000000800003c81d8b4619e25b172b941511e250136d16a13c9f0e298367f13d20ef0af73f1a3b8aeeb971e7b29521ad0f06df1512bd4386943d0f964edd96644c86f8c85151fb66d91ed259fff064f2899031a8e465f739ed04d0134dd2cb6fc755cba47ed314537f556d7c58b2d4b9c3e489f6eb979b776e9ac7867fb777b5ffcc0ce6a27b010001	\\xdf3ae0998ef4f1b9bfee22b06347412a12f94d7525ab08ef50338af8680894659869835ffa8a4925806bdbf97efda845b433d56ec9efce6f5c24438c22272d0f	1673687248000000	1674292048000000	1737364048000000	1831972048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
39	\\x4d84e1ca5cecb873f29e79c9360608b15827a7abd41e45989be9736c2fc11540b56daf793c10edf4e7e879784bbcbc94ab1404c67f57df6d3afe4bb927a0c168	1	0	\\x000000010000000000800003b391697f0bd7cd9e30462980975522cc33d789ea6c3aa5daf021c11d1f5257d1fe8baaecb1f74e21ebacc01c005653918472906d6136081374ff439030b3227c2952a66139a42acde8b9599f6efe88e6a1d6320656bc929b37de3d2578279152bef91d4dcbc38b8463f5d168a2fa6f3d66bc2620a3f0754d39bf16ab0bebfa0b010001	\\xa5b37c6320ee27ae1ab124ffc1e344612dcd843c60757ce7d80b5c2b9ed4377dc52b7ed18977c67486054cd29560e086826e2b893f636df4e59fc0aec4a78404	1689404248000000	1690009048000000	1753081048000000	1847689048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x53fc0464cebc677f05ddc65c10e22300679d4938c564336795f7c6711ee43e11d51f82701b6375cbb0c893b4875d492fc6e23989a63da5d3fdbee35ad2adf892	1	0	\\x000000010000000000800003be3d6bc88d7c7dad61d98422531b09420ae53e4cde6d345c8d5172697c1f8ccc50138d618429b7cc19463e4fdd9338a94a5281362f6c5717a8f414f256d03598e3bf23b05b8e0a528c958c8217cc4fcaf6d2ebeb487e3208d6767e52c48af05bf58158d3cf5f101d58dc4defbb63b1a66013ae81336dd13bbffe691b2b0a8f67010001	\\xcacc4b69c0485aa39b3ab5ccb4e7e200b7cf912bc2088a49749851684316fde4f78ea2f6093dc9f4882f39398a443204a9873f82f0711398057d951cbbfe5a06	1664619748000000	1665224548000000	1728296548000000	1822904548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x5334a4d20890b739e646278a5ae55140d9344aeae6f9dd0e56550721d622f51a5c608db16216c9bf7290ca27c81d26feec474c8c9acffebd298e9d0d9e46487f	1	0	\\x000000010000000000800003bc5ff4df467d0ee8770bcf42aeecca27508f8c43fa19ed15022de10dc049411d893e9f3487ed0f16c3135a783ab1a3e88cb447ae433211744d34bada52d5e6e42f1220ba4b65ba608fb9ae55182a1df4b63141803397907ac959513146c0afb54615a5b687a6ac4e5cba1f203198f07ed28a8c0add1a9fe5a9b1c14a857b1023010001	\\x1bc0731154b01c12cb67d503f10ab060c063ea5285ccf62ff5a40f3d27177e99951417c83de47ad52cc9ddfb3ba3cecb60f5dfae1fbfe580d43776ee92c7a400	1661597248000000	1662202048000000	1725274048000000	1819882048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x5998ecdeacf12f1beb895768d2da4e6f0b28bd38fd69d4c251122982ed125748941668b17720dc32bea88ee4a2cc847012c7da325c40309892d28cc4d3e750f0	1	0	\\x000000010000000000800003a7ce8e9776c3047c00cf35cf9626f9da617f17a2c6ec1914853a06565f1215f1f110cb9dec434c7e8c2d82f47f1dac40371de4e706db36fce85f824b6dd1b5a0fc8e12626fc9cdf4860a30447711d786c8c1d39d52cdae1a65361eb102317d266ce272f83ed96b416725db50227a460e141ed8b7a4e70c3985bf42a30f75d377010001	\\xbc92c0e6369723e61768504166f296e38faf2d69625e9c1488925a37117e2452d20c354ee62180e6326cdefbab6cd10b21d2335e4857b510d168177a74eeb205	1674291748000000	1674896548000000	1737968548000000	1832576548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
43	\\x5b04e05a5fbe9257716a5adcd160b7b075064cd8add70b4335cf100b3fee1081c1663d5ea4bd57cb844edc3b1ca6d8b687674c8abd10dfd9e693a039a67751f8	1	0	\\x000000010000000000800003a68a7a65e4c0316b822c1c990acff6299cd37f97da3ca336015a9653ef47514afbfe91773b7043299f6967dc0cda1836afb40a819cddb21f8a97004e4003a9cf1cef606fb377b339b9668fb22b331d7a383db637b37c1bdec2fb64e79c4110cf8ff9fe7a7699ee541a457eece55934e36667a8b01380fd9854dc427af22fdb1d010001	\\xdc9db58541c8e3205e18436d820f9cd818e24bad02042aa62cd4d1f18f458d1b84fe7251da03c63d43246ec795de3f082e49004240b021db4bb0cc97b889770f	1689404248000000	1690009048000000	1753081048000000	1847689048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x5fa81d0f0dab2c5279ed3d1846dc6d01accbb69a038e07b4b6bf5398a09f1fa8924e75c386711bc891e5b9dcdb2d9614c1c3312922e49723000bb42e30a7d2a3	1	0	\\x000000010000000000800003be09b3f5d8df38b6ea23599e5541a288d963afe7150dfd28f7c5514af141f18f372059cbf1bfc76fa45c7d7eb53eb8e5f11fef6fed2c1b223d3c3c4630ecf6b27794e0b779ba2719d18f390c140abc5fa3b77e4ab7aff087eaa53bcc70812ca0b1dfa4b732295830527e03a45c75ebdbd1c5fc7e8826911ae5a437dfa3a79603010001	\\xa54a1f57d41706988954e8996451039399c071a784c8a9e6fd0b32fec4ec0bc065bafcde876e2fe6795e42aa3e9a1453fdb6974e121aec9c322590b72adf2407	1668851248000000	1669456048000000	1732528048000000	1827136048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
45	\\x5f9824e186faf62adb6e67dfbd4d7f12fd78506a26cbe8b62600ab465c29c4f20cbec42218513e6275a16940e9bae43d7a5de51b5a357c2f823017ebacbb0e12	1	0	\\x000000010000000000800003c6f194e38679111530e899bb609ab0ea981a0cc1fccac9bb09986579685eb0c46f05d9f6be5a04b497c874189167618ac1eab01df195adc4231882fc84dfc46c00cc61eb99c0f5b096fd90e1995c4285fdb6aef89701ac9369d98a40463790cf72f8b51d12b34bbb7e289b90a23110c07a96a4fe3ef6588c82580dd29f9ea123010001	\\x269c4d37b368ef2e29a403c42bcd3e512ee4c5df3f23648bf832b6aa02bb0d6750e23bbc79ee2573f209a954bb464837955f3aa298b6e1c021d2621120102802	1680941248000000	1681546048000000	1744618048000000	1839226048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x649c549d614e5fe52d32bebadba63bcd25b2099959e040709446160f89da7b866c7952323c2d00ecd7067b8261f89a8a7cdf8b11f43b979520fd90da4492987c	1	0	\\x000000010000000000800003a9e6792dc3606e7dde76a72692c4ac4efc0b297fae5a0dbd74dca508180c1fd5e7bf1f9f3451f1ee78b521835881419fb384971e9e9588e873e96624e2696732e9d3d62c6bda6c9d05a2eb744a6a3c2cbe00279971f68f3eae83f5810f70e694a80c28fe4bb3393c0837bbd2a9159516e20b42651b53af78963a0388f00e0f51010001	\\xa420b27b0eb186e61d289e5628676985781878af683265a6a34b52b40596abc88b7e32a85676737958a2281463f00a34343ee04168162fd1785b81b7ce06410d	1679732248000000	1680337048000000	1743409048000000	1838017048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x68c8348516d81df7565530b2b09247e10220ade7b0d0736317aa34db59c6994dd61292d9333e911c1e8fed0b32a41e0dd7d7ad3540f621cefb16a62bb52660c5	1	0	\\x000000010000000000800003a899e57456ad9a4482cd5c219259904cbd9893c8bdeaff305dbbd2fe4dc44e63669f8ef221b30afe265382f4e815b7c22b1edd1e7574299f8055c23ceaf969ae156971d46c0131927c29d93655c74beec8bbf4bbb9959e2b8e891ca59fde2e87e65815034ca1dc0164bb00ecb76fffd697ff457e8fce37dfa8cf7313f536045b010001	\\x3f4878d1bb141d7fc75519f4d00d426596a2608f1feb8c98ab135e5a3754678942b501523910cd70b29e6142b90430882cf657d77f8ce96e0196dd9d1e91d907	1678523248000000	1679128048000000	1742200048000000	1836808048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
48	\\x6b4cafe8dc31911da85986d42a6b67012e521b470f9488c251dd8682cc5b17f7fb82cedfbd24ebd16eecb9e21a73faf3f2a7ee932f12bd3792d9c79b86e6c8a3	1	0	\\x000000010000000000800003e9b0755b3d5936dab82e0e857cd25a849a636b6f5caef3e5f65ef223ab9b627e15f5558938d636ca11fd4aad3b95363f63e6ae17fa785c4f96a5b29bd0169cd7223a9dda029286a60fe5c950334a240b016da4cc7fd16f0933f9cae1a921688d14c8d1111182d9ad9068d8128890ed3397b7de585ce8b6e15a71586ce38d9a7f010001	\\x77f542eae5b4ea29169f41b9f0faeba9c027f765113a8f6900bb0a25203c1db66451f2a08e4a2099295ed48ab44f45d119d4fae11fd86023f09c5d650809d30a	1692426748000000	1693031548000000	1756103548000000	1850711548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x6be843f4997a730d5e28ef353428b0c620cb0a5e8f584ed9e281974a2d679292ced6eb80501d6327b32f56e774b3080084cb79fbae75831b2f7a32297094d1ee	1	0	\\x000000010000000000800003c50346242ce6c40e7eefaef2e9ed038a8a91f1289ebd26deb07b7e8015e786f7d9399e02d53d06d8a0e3e3b3f2b4d284efcd35de74a5aedfcaabf2c5f2182452a23fc9b63526b810ddc8dddd1fa4ec8121fbd346246aa8402781510d15404f84f6d07709bc26d04ad0468d1edffce7e5498f532da1453e4cfb9932c863ffff25010001	\\xb4f861dbb0bef5430df785023adad8af10f81fc0da4bf746ebae1210a38bd4467a9b827877de60c9be71e8f78f1b8151b1618d57d07934902c7c1b06f2b90705	1671269248000000	1671874048000000	1734946048000000	1829554048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x708cda6ef20cdccf4513a2a6c73562297f9b7d2b0cd545bb11c7ffff374a4c7e8000dff2b20808a2147c481a39b058b1f522727c28d8348b1d39411354b71651	1	0	\\x000000010000000000800003b08ede7b611d3e5e22816c8c03a47d69d41c0ba4d0b7309b7c4793c29b7e6308042f858ce52f6e2d4019307195baed949313a304badd493757eda678c5efcd12792f70e927ecd76f150ff8ee74759806a6d219e44228f03849bfe4f3769dfbd81112b07e6df492ff9dd6fb5102e54e5505bda456046e691f420f8ecfed4c46d3010001	\\x201d3f8bd9d7f5516b26792a09f75a9dae3e771aceec63d65690ca20cacba23899d00801039b11d9353d27b494a1ca174ab813f5fb85cf9e4ce3791da4d3fa01	1664015248000000	1664620048000000	1727692048000000	1822300048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x735c5a777b8552d3aa4f10bea733ae46026f18f6c38314541b5c03528796344d65775007a04019cbe939d5519fa700e262e6dd5e72f651ac7f8e896ae98db2fd	1	0	\\x000000010000000000800003a53dda9ec1dfc220ebf6f7bcfd838b805035fa67b55bcfaf3bc0ef4f69a47c046df8723207355bb945fd023efd942fafe224c21de1f8f980038182b5aef456b1f9c090970606d6039114cc0b75ea3c40befe61292be49756b1d74497ba3d4bdd0c8069b1303c3fa7661f40ae074dfc729667d8e29b7cac1da50f75ca52b676d5010001	\\x55e78bdcd7443fb06927e770d31a8862c8cba6594f6efc4ca8ca26b08207d05a6593b361284aa1e41718488649f93a93040ad7d74d4fd342881e63a320521d04	1680336748000000	1680941548000000	1744013548000000	1838621548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
52	\\x75f4441a6e4aaa3becb930c066b41b9fec43062c7654692dac9260453cda05a3b99f65772a3611320b96ec3fed1ff62a35c678b17d0440d9020d332c051e802f	1	0	\\x000000010000000000800003d8a301f2c31ab60f42a521e6efc5ffb498910483e9068991cfe9bcc50737c32c86724f129d3fb6713b4d432980e5d7b86cbedcc28fc932672d2e0b7aac520dfa42c18c325a5ef419334f3877d92898611496d65e0113da8c911e0063ab4b903c5e608d6ca90254e3b86ea63195af5cb49bd1d6c3bc364222cbdab486b73222c9010001	\\xfe5007fa8e6e154c0def47cc1885d664dfb06c2ba85a92d196d96f207be24bed84a15a0fa55f41e057d0ba2c86c4a8e38f6c244b24956c286f7ad29d0a26980a	1671269248000000	1671874048000000	1734946048000000	1829554048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x756c827dac776ed540ef356c4d6ceea2d2dfa4a494a19a8fc299f58c5b87be737e64161301294911930ea7ad53ce8105b8a7474df5dec5ecfcc6e01a715016bf	1	0	\\x000000010000000000800003abdcf2fc620475bb68a59102e6385f729383152cf13f0c5feae3cdc58c96f184de29088f4d13a4ee50c7cb467b59b695eda5906459f0e45674ff874f7ad51a185f3903cd415830bb3d17f158bdd1fd4b900502857561297d3c242a3b21c4f2432446a368355e82ab42a48994c94960c6b2983b3298883994c4a1ec5e58851de3010001	\\x091a82d9175f4ec343a628b0d7059ee33e0984dfe9a78225c4aee344669c85d4dac00833584be6cf8063ec933a2c2d425f7b1dec294fe41d8a08f3c222bc400f	1674291748000000	1674896548000000	1737968548000000	1832576548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x77a0f64556ec8ca32b9ef28570dcaef0d75a1f15bfbb3340b57aee58606fcb42508d74dd857df08d3fb0f232c490dfaca6415980cdd87d204d0d943a1b678341	1	0	\\x000000010000000000800003d4bd6ef9df7e96d01ad64b3ab418d76ac4bf578b184390083f9aeb1d58374889417c60f13baa9b096b895ec9ce08d4530f4e7665a94e31e5e19a128b5525ae43c564ee9cca5c8c1549d8b6807daef6dafb4a52a4fd4c950133c012cca020295728cc5da540597eae09a4527f325126a230153900a47859c9f3a6f195a2f5142b010001	\\x52f43b5c7637c3a34f81c81857db83482cf3cea67b0d1713fd32f3c2978eb122e8a1c714cdebb81c3b351b704e9c17a62d263f7f3165b547f1ab207b7c84dc0d	1685777248000000	1686382048000000	1749454048000000	1844062048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x7c340c416cd6cae40a111fe67a2b3f606d5203a5877382ecd94c905f0a83739d430dcfe6f53e7290ea61a9fb99c1ba7ae23a5f7088e341bde2645d61424f3477	1	0	\\x000000010000000000800003df38058444b7598c11a8c7fc8d1bfd6c916105906f981a4b866433bed31e0fc62c5bbd5237bafec4e86e016d0cf968e915db6fcc05788eb31c3fb73ef6edc199a3bab9ee4651eb3d207e3031c0878dbdbbb3eca8a40f650eb572b28f2b90f934e214bde09ed6d4a48783135c437cecd0417da0640691f97d278a1e4f043dc6df010001	\\x3bdc7c745e84221a17bf9be32438fbf530ccc7aac9d4b50b26a06e2887aaa9f25d9813e229478dc8412e8f08b11ad77cd96d692141d067eb985fe8d4671a000c	1679127748000000	1679732548000000	1742804548000000	1837412548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
56	\\x7ce4320453d4e0b33b30c1df5a70d5b8f719c71157e7a00c7cb869be1d7e35ff8cad221e2d188a934d605fd5f03fccd3ce1a80014a77c1dff0f9b53572dc7a2d	1	0	\\x000000010000000000800003d83e172908e66f83cdc2aae10d4c4dcf4fa96cb909cf34e355cc38d588297ec0de63113991fcc8117ca8f340c2344b763274fd6169fcafaf4851aa17d371abf005aea943dd6085b2cd3efb70e586fc5a0feee989a62979ac978dda22ef96d3fe459a97b9d3d4fc24731c0974309999c681f4a4638400a58730e7cedb41f71531010001	\\x18071e1cb77d02b615d41548e2f9c18523aa8ee19423185610c924fb07974c78235c12663e0f26889d6bdd94feaa7946251f0a73999065888dcd179434054200	1670664748000000	1671269548000000	1734341548000000	1828949548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x83f0ac427522013de54aed66740cf359f9cf56563506ee0314e31dc9d0fc8c81b9f913a32eb5b5e4d705cfdf2f113eda1206230a5aa853109399980916d2cfd4	1	0	\\x000000010000000000800003b6b560412e5e5f6e659c19959466bf2793d6b626bd69f9a03fb18aa355dfe24756d21e400b8225629650cdb46c2fd168fd5f5b7f8276ff4e6912b9095a4d4e65a2e6b2f0631b5717ed45dc81c5a153b90be93d8b08db0b93a3032dcb0d8aa9494f7f5bb9b0c5fa9d043264c576a339f85c73d268e7621a972735bed9417c0a99010001	\\xd55e2a474bd8dd31817dbbf362f3d1d69ebca618f4aa293cf8d61047ba492a56af32472cfed8ef3077fd53ced5f1149f5ad623e846a8bc8a6bb3e75b88c14c0e	1686986248000000	1687591048000000	1750663048000000	1845271048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
58	\\x86e844488b78ae03a0b266be10658612046f0e02d746c4419f789d22e1ef428549c33cf067251bbafeab170a34fa2f7d78c2dbfa26732e2a98bb7ab0dd01ad3c	1	0	\\x000000010000000000800003ac3400e42dd1b057ed4eb5049a680067b0d3ce569abe8bf1631ddbc6ba2ba3780ff4f4b4c56f6632b7115c1285d8b26b29358bbbc33e5650f32dae42879544647895889cc9e17e24e2a7c25b45754e25954e4d057061689c4e2b7f940ab9df7f3ac93f2fd1fff578c32528b35dd8f2278283df45c71bbf4f3fcaecc6b2f3925f010001	\\x058a85be5e056e4cf9357fd564a3ac00381f556a343cdfffde184a7a8403ba2304f0eacb038d0cf1e1a1cf067bd46a608276293b69518d2d4544af1a0fc4ba02	1665224248000000	1665829048000000	1728901048000000	1823509048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\x86142cecdf1b7391dc4a259027679c47fdc2afc8ccdfeedc4ac2bbe1e322d0d0b1e3ef1bc2e6e5efc54180a65e91ad5791c77dce4b82ae07878ded489a87ddfa	1	0	\\x000000010000000000800003c4c3361fbb306c86b37dfa3db5fb75d2814e936b15a7e5ed28702ca530c359964fce2bfe18f1833c95f16ef7794e4c729eec75ce0774e00447ae9c586726b63fcb492dfe08f8b1245a17b94c0ad5e055a2c5b6255f43067f302813eea4fc1d5697646350cb95e8bca4cafcaf3e2c124bc5165fa736a9bc40d5dd11aec1a20867010001	\\xdec0185bd8903c5cf03a2877ee29d605e84d6a4f46f7893b22e985eefcbfa10d56345311d0cdfbc94ba60dfc82e9209d74a4ecdc2cafac77ca4eeb4fbddf690b	1681545748000000	1682150548000000	1745222548000000	1839830548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
60	\\x8cd82e8b40534584c7879ad745b0a3012f5dea890c693bae2debc01d0445514e5d8d87c36880bc2958a02e2ddeff3fe5a648e831e0c7f67128cc057e607ec515	1	0	\\x000000010000000000800003bc5007377600f5b9b725e8e6c10cf0e266485dafcc9274add403610551d1b97120a3cc28e5b980e08db7ad296f341e4d61090a211971e4fa059ae758633c019846b5978a0af5d6dbaec8d9bc62d6f81da4d361fa88a3592810efeeb1773e00ff319dcd7f25744f234818ad03dc773f9da6852afa2ac3baedf34e0064dcd590cf010001	\\x8f2bac61eca14a55072b596bb9e7f10f8ab2b57151e7ec42bf0b08344b7aa28d1f2f34faa57195b561fe414588f38a2801bae99c4a0b6724e892856ed52eef01	1684568248000000	1685173048000000	1748245048000000	1842853048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
61	\\x8d40e0d8ff69b64246b19d73473a374dd2995bff5c29462baf3b09fac8db41bdcf6394f96dacc7036e131d382e4eddf0466125778c4a6a10295e8a6506100ba2	1	0	\\x000000010000000000800003a8f7e1121d6ba925c049bf9e4d2a479e7f63ec2c212c749aa04286623116cd1a6d8e9f8fc1a443834d9f50a9de35d593c7188cc989322e825da34a8100689f3ea135ddbeeba9e66f02301cb9726e3ce8c3230ec5c6446b50de8dab8e27939e14b6290cbd47716ddcc8f326aca765a1edfe256a7fdfa436161a69e8db1a59887b010001	\\xafa9960cc32858c81bbbcc9dfa1505709e3fcd13cdbbb060ea603a7a20f9fee453a0218f118416631a6fb1669c146a25a3e73bf08f8a810ad8a04ef319133400	1669455748000000	1670060548000000	1733132548000000	1827740548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
62	\\x93a03742013fc27d0f8f4c6a236218b31861734e6acabeb3db7bc33a2f060c63694b1366c4e625e5d25a712bc95e404020180818587653a87a9c6815ebb413a9	1	0	\\x000000010000000000800003dc7931c4172d349e42dd189e403972b1eb7064e436e5cc793f01b35e8a1f1f08bb816ebc848e266a588c474d2187bf846a3eb3dd0e0dcb72fc64c7c6e12a7f8a7d3cdadd3ee11bdf0a0be4cb1a6438514a802a9e8180739982f7bdfb226bb36b71d5c2060bdacde39ad97e3afbc7459a87cdca9a3aa86c85a609f44cc160f797010001	\\xacaf54ae7891b578f7616c9f10f444a549ac7662020c64710b145b0e715c8ef84a6acc713b00b53ea8e8eafc7d966ed4809488e3b8740e27d5c886768c6f8105	1674896248000000	1675501048000000	1738573048000000	1833181048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x93105ba38254533ffdfdd5c0ddd2127f55372194ae3fa5f176573976e3ef994a71dbe0eef7ef68e4672a1aa133bcff160f61970c550d5eb8f212f64d99d7d967	1	0	\\x000000010000000000800003c951444bd94844a8055f00357bacdb71f54e536d70df0b509fe543c7cbe0993e5d3d4cffe77de4c8ebc4f8159a87127423042e918dcb295e6163617cab7583c500989a36f8969fc44987eeec78c1625581d9ad3eb01c7b82df23f6b86fd607d8f52e61266c2f61896f04c9c10d0949b8fef2977a862ea7de599ab4ab8261bf6b010001	\\xd3366d9af0cba93b197bd5c22e846d4d1b15e4f0fd5e084e3efb701cf9ac4766bd549bd672ccccbbb250e8a2f50580c8a56b2f7a283c870fd63c187d3a236c00	1680941248000000	1681546048000000	1744618048000000	1839226048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x93c8626787ce2b905105cd433154be7e4a10f90a348c40002a61091e44e367d2280da60cd52db213394df96abd8db30abe2c748d3d53189342d96a1f6db20753	1	0	\\x000000010000000000800003d2e1e6c209bf92907ecbda547c08a6496c575e9dabfa8adf22466413b6af6343b54ce9790b744131d074118d08145aac3fc20a32bbf759f5a6219c36c2effb43c66d77835f2d8611cdb4784063ccdb61999773238f49226873176d23ecf70719f24a57f44d7b443b7edf83b1dc485bc2c0a1a47a04f2a486738843ff4ca88055010001	\\xd2c5e199d853ebe9205c46545deb64d9dfba748ff7d7bdcfa22574bd2474b97b5d070e63640e16f591f09eec7803d422679ae9c7b58f526d01ad7ba4aed2d009	1663410748000000	1664015548000000	1727087548000000	1821695548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x94a0bf989999693fd256c8409b0153144ef067626997d81e0a6b8549650c1e65c7859802cfaea213bf87e33def39b2080093c43eb903f48a07256da44c51694e	1	0	\\x000000010000000000800003b44062c0151ddfb502f81b6cf56a6007aee649c2ccc184413ea06982b5af4bfe624bffbae31c57664ef2ca9fd82a26119f48225b272d6fc22c18bcd9c38aa44c9699331d1592f94a4cdb70da870e7c9bf0ffd2b3f1e2178afc961b57ab58b70dda843479c10d88baee11f7ea07d103cefca73cadfd7954dcbaeab68209d637fd010001	\\xf1c0a350a6cf3263137cf89907b2841251dc7c3c5df31ea05e0c456ab90ab78eaa0cd2fcf48c81157328be47457bde1db809b04abfb729d6d1cb66e8589e8f0c	1664619748000000	1665224548000000	1728296548000000	1822904548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\x9c6c206b1f672151ee00b896caf09416635890add9b0ce9f28984a181b786036c8d5c0eb1d8af654baad15a00cf531bcc35f925a5f5de8382d7878cf9ff22311	1	0	\\x000000010000000000800003b7976f500edf883c27633910b77ffbd128f8de52b60cc8a592b5683a555d769c0872055bce53692a2b33f73d668c6e3a70b4456c7fe4ab94b177a6e8c03a313db48d376479735e70c78772ff8c014a02f45ac822a43d78c32a7c5e57eb99dda35491c180cb9fa76a13380d2ee6828f66c79ee1c793cb8771cca44552919d6f87010001	\\x18ef05fc7576168da3ecbbfb440433c21e322af5a9be6dce04e0697506d722567051f99dfe59df92f3311e6d9e028f33d9ec12ed01053dfa71beafe4d63b0e0b	1670664748000000	1671269548000000	1734341548000000	1828949548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x9e0472a8d250bbd44cbb2151cda1c1c15850d2e2cfe6da84fb43d849b072ca6a3b7a67cad920ee66d27cfba33a9491eab02079e88afbb3563ef16e84af9fe8da	1	0	\\x000000010000000000800003dc34e78b1294a9d8855a2543ae51153ff0d045b4947865132c2cba163e1c464710a5d48c45a24167d236d01b5db4ac5b8cf9766419ec9d7ac5dd1e351064393f435c0118aece0d7d4304f77f33e286f29bbb1704488c4d7745cda94ccace9c51f6bf86005a9fa067f24fa49c8911ea9b0cfbff6531a8282bdc851c683a0ea4df010001	\\x565ed5ce32272c8700b8b49d936010ea8f61985d9e4714fb849eaabbaff87155ce7ebe709c62236b66543fdb229523e47723d777d0dce26c6c1c92e3758e4f07	1670664748000000	1671269548000000	1734341548000000	1828949548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
68	\\xa174850ec7e08afcd7e04adfaa7e1f468bdf54b4312216ba347f4fbfdd4e640779aeb6e0f529f20efb0ba8bd186c7c18c862f6743e703babe256d332de7ac660	1	0	\\x000000010000000000800003e27aa0b3542cdc8ed8651d353c5dfeafa7d10e6a0977a15aae322db52324764a8d92c81c84b6c1b31ec7eac2a768dd28d9dcee1d4ade68744df67bed207fcdb08da903878f9f8f1573f48a9b89bf1aa7bdc8929dc71e535f8b5c582a9dd6988accc94f1a56ec3688548c6d5e87551a442f25bc37a6259b7c38024cf4feb362e9010001	\\x5b6d083c556ca630f97c4a7b04866887ed157732ca47a10306115e8c1d2d37efdfdfb8b1fd7d67b502e9a1572c7357f3e574d38b7647bef2dc7e2c1b241f4901	1685777248000000	1686382048000000	1749454048000000	1844062048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
69	\\xaba0d4aabe181994d99ba4c01bddc6c42052c310a8329c16e7ab4cbd603fdd455d1a1dc749447fd04189e0c1b582cb0cd38c67f3ffae2469fbb5958cb3733c10	1	0	\\x000000010000000000800003f9217c2850b09112b93b0184cecdfea48a79e3772c6ef7154fda6a81c038473fc3259bfca6f11d6e8fa48bab4ada4ca576cc824d628d578db40e55b9b986415e9b931effd5d18dcb6e86c788132d0b2c9640cd6feec61e9a39ee62a3e9f9cd85c4f1a9a5f64728b743225069ca430995e51d630f5c2c6f94f4fb78c4a130a1eb010001	\\x03e36e66250d7c7bfb12d9832dabb8ff7c2cb85dfc47a60eac5b8c748d4f5dbb6767f07e584a110ccddba32612e9a07eb13176647445b42593f02cf01217fb0b	1680336748000000	1680941548000000	1744013548000000	1838621548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
70	\\xad780c3c875753653275855426f8a93b8ecb0cf4334a6cfebccbfe737dd1191ba2bf835bbc9d33208ae30eb56a0580ed986956356ef21e78353a2d760613aa3a	1	0	\\x000000010000000000800003c6ff466e3d8147278f804712ae7766fcbc9bd50d55f8a5bbc6aefb4015c3d00baadda7a3993448c754e40bc966c55e91e49a0bb2304cddfb8ee4c73af8640561a7311c490460bc7bbfa1b616fb9e5e68d605b3f2edf2fd24234a82fe2ce0eafffd09433fb303574b9c155af6cea7fadf76cf54155981d8af44e2c84abce6d07b010001	\\x8cf645ce03aa03727b3a71993036884374919dc1f4f544bb68537f79f79e72fedaa74fa15ee76e9c58e59aa5c3aef7f29f8d8d326b2245226dcd5ac61ec82704	1670664748000000	1671269548000000	1734341548000000	1828949548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xae04f8c26fab844b9d8f7fc709a152aa0e01b6ef5b83837222e62ca810edeacc21acbf1d1a3b0e957f8712f0959079196cef4dd2917e2d290f072b26f2080dff	1	0	\\x000000010000000000800003e83826286f353daa6683596a29b959ffea4ac3eca2a8260f859b628d586864633cd67ffe57079ff5009c0e753f996395b9b87448ef720a3b3efdcedcaa36006a6a20d299d305998f12636f668427d20dc1783c96ffa5542c357c6f79af08e330bfb18f88c020a0c40f307c01676b7e262dc9910735f3768ace4801a3bbb0817d010001	\\x09eb3e5fa75f6e26d8fd46476febb62cebc21ed3ce4e680f6db77ac3c7cb1f9efc368bed3cec06eb01a375de1d4e1f3a7ccdd166508645930bef47449f59e801	1680336748000000	1680941548000000	1744013548000000	1838621548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\xaf682ea480705343a478586db54a305f343f8f82ded33c2d8b3527c1ca74f2ea9896eb0a0feac933ead1cfc72920978af93a7e98dfb8f05b9895db456d2878a6	1	0	\\x000000010000000000800003d86a07bb2ae5ba021c7ec060ffe4de3cc6a39e725c1599749bb95ebbca59f74413456be8dfc4307b24ff88e3c7c75ae9ee367da15b2848b9849a84dd27fe459a4fd07cab17f78c273bd4b575d3fb16e728ed4f33ab5bd8b2e21618d352df28e719fe6a87f1b8ac6bf5a63fec4816006592c290f60d631fbcdf6c5b62a11b727b010001	\\xa75c3af08b9a0b8a431291ed3cc1ce7aab1c60597d9f14388d67eefa636dce6c5330d3560f5f16034090cb936b142226362eb4f6a415877c022bd0200cf0f208	1682150248000000	1682755048000000	1745827048000000	1840435048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xaf1445cf80d4791ae81321637a8ad0254279266a058df8eec0a5bb4affecfbcd7e2e7a1ff88fe55c840cc1e1ac815d3457770d0e57aea5fdce22730c922a9e3e	1	0	\\x000000010000000000800003f5535be0d3bdfa0fd9fabeec00a7ba1ba56514def9e532c1c4bbf64862490576fab403cf72d2475aa5ba540ca3f43cca06fcbcc7893ee17e13ef398e381fc40555804ac8046c0f1d690bbf8d21a16e21687f7050d744e637de1a5eadd8e0fc127de93572a710f410d42e3ecc85c67e4f0a238b3b5fba33815dee907b1473bd71010001	\\xcf3b01a145640714ea46867f6baed03e97104381783d50035861ae0bc227960049a9f21899bbea06e815dc5fc2b545cf8fbc956a16643417a6ab60d623609e04	1665224248000000	1665829048000000	1728901048000000	1823509048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
74	\\xb0087bd39b38a610123dedf0d142593339f86ec1883ade4d2b673638b4df39ca6c80622de89b8712f15f2baf3a85355c7b19ebc4da14dec36a9e09e9fec06cab	1	0	\\x000000010000000000800003b1f31b15efb91b8d7a051defec691258c97fb6a5d29ffdca5dec1f77745e4112b11440f6e193fa5f6bd48304888fd53995993871a3fbbcee12f83833dcb1c1ac265d6a141a458887c8ce83ea15456bde040cb5bb35bbfc80df8155d4f851c0cc4278be53e6169419590caf13738948013fba50c947158abcb6bf6d22e450a1d5010001	\\x4f0a5a6873b3659b266875026947d96c14cbfcdc661fc40f4907f211d836a492f2c010d4af64aaeb652aa272613d2524976cbfe327daf8c807918d1644ce9408	1668851248000000	1669456048000000	1732528048000000	1827136048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
75	\\xb66cc10a66ae0bf73e6dcfb98b9e9f097c80fc6b62bf5dcff358b23ea225c8c3bc680f73e17326d9f5932402a0150c06dc769375579cd700a3bdfb3c263c11f9	1	0	\\x000000010000000000800003bfed882899f5a19705c409ea2b1176fb0195a419f7fbf510987cd098f305221be87924fe25e2727c9bee166debb87e956b1b0f5aa2a40df7c58ec55d0dc832ec8103ba13562752325be7c099b6e2ac475b929a1d26a9c154b25e2e7e0027ca2c9bf24a066c9bd75a89303eef6b9b861240b7cc0f6110e5a2525d6cae0669c143010001	\\x5053a03c938d81d32692033e6f60f4b5bf315a426988546a1c155fd1fb586c55bf80f5e7399080fddf100c7f973e8914e85c18712198f50eb1eca77257201d02	1674291748000000	1674896548000000	1737968548000000	1832576548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
76	\\xb660e57982def69d8e10bae7000b80cf05dc7bfe4db1f00b6143b4868b60bc5142e571a3168fb945383df572da5204da3c5f38c070d99dda9f9fb11fabbccdcc	1	0	\\x000000010000000000800003c17062d1ffcf52217621cc481971987a4d4b76d42bbd775e2a7c459a76b650eecdb1e4d28d33ed284bb9debbba60c9596f2a3dd7e65c52870c6ba36d702f432e392bac3715c2eabff08f737d59ac5a4c18ae6881b4bcbc628ea441c830d3f502411c700148067a5c5365d5286d0dc32df3605e14ac02b14e3ec061a3eb88780d010001	\\x6e6d89b9cb21542a4252170db7ea9e8e07b7b7a992364101fe5a57ce1587c5d16eadcee6789182ee0c2753b95668bd3f9af9d1e173f980c0ddbf584ff138aa09	1692426748000000	1693031548000000	1756103548000000	1850711548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xb9ecc4d4cbc5bcf7997136fa4f6f0a6c84c10b7c7a3418eb1be5c23ca3ea555c8413e226641745d4395a905f3cafa7be8cd936e3438f1c7d67a0e9d633f01730	1	0	\\x000000010000000000800003d009605b9a83cd2c7c8cc1313fd6c5aadcea9f8bcc7be1d18644c997d4690263cb1704afc37046eb7ea6386d2b17f96578bad252168be5fc2df43dc174331428eaee7bc375aa4e80773b5b2a5904b3b623007735395fbc70bea644e5a454aa2cb6c828b0d2706cc9b5c7e98433a04c4d9f26a2a573e3e3b9d036c8b32d31fcb3010001	\\x719be628d347598e56bb3128a849d68b6d3f2f273a1853876c56bd82f5947e63c88ea970d7103c0700fbd59948fc1cc08e59e5f1c51bcf1fd56b2895d6c6fe0a	1662806248000000	1663411048000000	1726483048000000	1821091048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
78	\\xb9fc1e9fbb3126e2c99717f502e22d64936faf685c6de8620a857a905240de0e40472c13f532531d4dde17e6f18cccc309f6106cd5e1f86d51682c0087c97650	1	0	\\x000000010000000000800003db6775006a4e2f134c441ab2214215c901a2b1cd2e6626b84bf23cb5f94dc990d04553f54dfe97c4fad886f08dc843f3cdc351b98ef73ab86725aa8c8a9aa4633885bca48a6da4d80fbb7e6af673d4a68a3be1a4aa608ec7a7f86dd975217ddd9288ffa364ce3d02e1b1aff3def25e53dfb953adcc7eeaf64a3e3e718c69615f010001	\\x27afba063678ae6788cc877300f5d62d8b8bd4e1e2c7d433dc32a8344fe36b49594b16653683ee161c0089500aedfba15645b2fe871293df2511d913cdcb8b0a	1671873748000000	1672478548000000	1735550548000000	1830158548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xbafc9fe8d6351f44ae7249e11f156d69e771a76afb6e9cb59534ae4f441dac4d45d7f1bc5eef14c8112e9f771a9ddb0a6dc3a60b6f3f98be539fd64af11a9066	1	0	\\x000000010000000000800003ba874f9808e0f174f9a1fcbf129590f6225dbea79d35faab49fdef1fa13e6633a06e2b8cfa2abf10d5853410afbd95af808227f825b28f4d08e38edf9917e096957ddb4c11d8d3bf8fbffb8ca4cbecf5b55a372333bdde5a78008c7d846040c5d965eadb2d87e602aae302b70c95a0e2f707a695ee9cf9f087bdcd080c937145010001	\\x05643b6063f0b802a17f393b174097d685d1467378cd6870834f5131cff25ba7f0de9ce5c7ec53d3ad5ec4bd72d7cb18e5c0639060209a0586c266e79bd0b30f	1685777248000000	1686382048000000	1749454048000000	1844062048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xc15cb411379b0224d305a9a6db13269b9e633c09ec91876ec470fc163489ad92eecc14c099a6df74864c88d0fbdcece2cdd1c35d006de68577f2c9161d6e690e	1	0	\\x000000010000000000800003e382d1127450566ed16678752c1803f435447ef278bd181e0206eef2f4eff72ac8d410f22255f47734b48e864a250b1778ad328e96c5e72a76ec84cce58d2b389fb19a662836bcf0e80c879cc6b73cecc6b3804905c40269889edc98995a67ce849ff79098ccc9222ee3335792ff40c954cd90988ebb64e0696cd389e50f3d23010001	\\xc3ff636facc8d6482521a1098a375a64358875a9ae937d5f3362268103e0b2bbf7953ff42a451090778c56440e4d13b7a2be612fbbcfc13f4b9381fccc4aa70b	1677314248000000	1677919048000000	1740991048000000	1835599048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
81	\\xc6bc904ac2becd138b0129c4b563abbb829d7c90a9116b005448298ff3d83a4da23ca8bd997962fedd3c8b0e4bd3fac69d2257b2a8de7958a7363e25f6a8a1c1	1	0	\\x000000010000000000800003bb125549b6679b305bc980e67f43ba869043d2cbfdac834074d995c256a7409000ec8b08076de562f45648a25cebc66a8239cdb42355fa31158229a83096d3c2b75593dfe3c6afd2815eb15c94dc51d750567cb566daf6022c6e2029cba47612a16282e0b45304cf20cca07a8ad73cf9548a458cfb1bc7665cc19a6f9f51741b010001	\\x06c40797f268dc01616136e84609ec04b6b7eb883d1dce458c527816c139884fd0bb98d3c45370a82b4a6d32b7db77ea859834b58fb54a3ce48326fb58d21302	1685777248000000	1686382048000000	1749454048000000	1844062048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xc7148aafe285f92ea271c28cd75353afa15af35818220452a543e84cba019715c8e547fa0dc35a220b78c5543e798aa0b3d187528567aa4d8238198b4a090478	1	0	\\x000000010000000000800003ee91a7a203a28b7caeec81d184579d9fb95e5ce9e52025825f75087d5afad30a700ea99ddc1fbb9b9f0718c0dd2c5175d530ad012da83003a2aba352c97000ff71b4a10174c59a315621bb4469410fb806096b73c2b25aa3a1db7f196c15b6e532dbb39a82b5489f89e283092b91283ca45aae7937a7b39a41e8abed2213afb7010001	\\xf00b3c17a4eaa232754c211cc1b53b16feb23402e79c1f94962f9b68f7c51f9f50f015590e5fa85cde5cb90df8a5314650a970858ba75d5f160519d43f95d409	1690613248000000	1691218048000000	1754290048000000	1848898048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
83	\\xd45cfcb1c34736f606f27af20f762eecf3466a371e772b614641c0a3cb8b5c1c056f289b77ae9565fa50db872d58f39cfcbe100cb5bb952b9d132d70fd4652b2	1	0	\\x000000010000000000800003c58bb8aa505b38361dfbc8f062bca5362aee6d1fb149526c58c4de69002f747288af537af61398fd74fa96c70021a36191f67c5a3ba8b18bfc62ce72912ef33b5e5e01ca162ca5eb1c2366c28313a5a4716129ae1303d4be779480eb797192f9f7bc0bb5675ac70893de556dd685fbd1f09295ed7bacb67faa8c9216fc9563e9010001	\\x670a2582ce43c19ba7a5c344aedc80f1b40364544950c963adc5ec77fbf9cb2faf1c189d20f77d233f5f3b28121141a168ab2937e7bd56093fd3e9e35bf8db0a	1679127748000000	1679732548000000	1742804548000000	1837412548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xd4981d5716128498507787a77179ff9587b1439cfe9860d44911b645251c9ae977989054e3e2172134d8847f28dc08bb3ddb82532cc01ec1b3d90fc331e3a08c	1	0	\\x000000010000000000800003c6c69139b1d4b61cf39abd1ef6bcff09638cc3c9b4083a8f312b26a51a1f5b5c558994cdd8afea0832da20bc2f8eee708161a371afd25822f280c369215cf3eedab827ab81977f6c92c86f59555ff4d28e87d5e157006be7f599155b6592d5b8158ebdfb17549dd33386044ce79b15dc71d31621ae5a99b0eb1c15525ac2f1b7010001	\\xa5a781dbdb6339ab7720376f918b1293d5d7b4a56b59d9c6577cc36747de3fce9d48cee481c3e77b66ddb7a00ff1ffc80531b8dcc862b24d91474ff9e3a9b001	1662201748000000	1662806548000000	1725878548000000	1820486548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xdaf40deac8e421aad9dfaff0eeef198562b389a7d4389c8c52efbf84a81051fe4f1769f533ca28deee19dd949f3f5cadd329bb04d32f1127df48cfc7cef93101	1	0	\\x000000010000000000800003e33b30c74ec49fc98927a0070524fa94fd104140929fe51b0cb60561bfc6b1378c5521c7fca8d24ba43532f80ed83fcf62505cb1432ad935eb42c5baa995821e738e7281d25e389dee10eb0f1bdd0edb02db7dba60e2f7c49dba3e74b98e1713a54f012f193e58ec8b059773479209e76cbadc7c9aeaa52a76427521f306169f010001	\\x58afcac08a986ae107850a7277625af1641666ffa1bc589429df441d78f632314d231d32762e15ff282aa4751b2c8281e2ed5d9ea3a0286323d05d2fc289e301	1681545748000000	1682150548000000	1745222548000000	1839830548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xdcd01bb7ef474bef48ffffee01800ab370b5a85484eb1882705f564981162bdb32416b085c1d1db68396fb5bd10ff0b74a29414dff0c2c7513ad507d2711e9c6	1	0	\\x000000010000000000800003e8df49e22186e2197a93b90402d1a4601ce4ab3a460a3369f720e843de03337a4d7a6a6e898eca4a66296e0554695cec2e9870fb2d5d65b4422250774a277ba9a85c9473776375e391040d0febe5ef2016e9b21ed7fc030b93c8dd9d6a100f33e3745358d51533a8ab8613e8e0cf2cbd3fca2c2786ab38d693b210e17fc82189010001	\\xf987ab460e2c9d8d15db91678f2bfe55b6c51f04b54836792117a47fcaff7bec01e61c4045652e722bc451f55c99f256cab8f848daee9a843b91c6a1571f5e02	1676709748000000	1677314548000000	1740386548000000	1834994548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
87	\\xe27835ef58e95567b808a8ee14f0f81e0c4b45788863ab8ef00319f648e6d317557ea038df9c5a4666a8a76562b558969b3628309e2d06ea8b6e28677f4b74b3	1	0	\\x000000010000000000800003e9bc2929ccf6abb1d29c2d0cd727f7777de7339fa67f36e68b94f9e4e0f019920145ef5640ad967e71e027b37e12a5278697eeda1929ec1f125f6d09cb5ae41a25cdc3e515d73fbd54d816d355e8d57a010d1acad95c70b63b9a17f756968e888dba20cfab618394fb48df532ddaec44444d76b29572178c0c9aa18403d81e19010001	\\x300dae8c5400709ac20054c12dc1afee5c540059b91e0d83cf8c8bb6e4806b7691295fccdcd93144b66128905099d7a69bb5f16d811d545d1a4ca02f4c510e06	1691822248000000	1692427048000000	1755499048000000	1850107048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
88	\\xe37098cf7c53d50aee1e1036616de3707b7121651b0398cdb30d84e7220fc32009ed4b80f801e8dee38ebf5ee6ffdf3b979bd120caaef27f6bedb5c8d763eee1	1	0	\\x000000010000000000800003c9a3cf3460cdb8373489bb9c13d1f82bcc75046f2be4510f670e4560b3d55ea243be4161a800407499b44978636842e8b9031ac88923c72850c22aed0db0438dd1e57ac1f0e225ff3a44832d1c556897a263be174a72fcd3d6aaf324aa49ddf2a4b0d6f856044081b221243988d3196fae059cd22bc719d228a127f2749f7617010001	\\xf3a69d38732cc9f6ba70bf60134007b5a36b176e0767da9cd485bd6b3699233a9e9c45d54656bdc3d62f374e3a08080830820d8c3c9a4c9d4a7c0273c13b3d06	1682754748000000	1683359548000000	1746431548000000	1841039548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xe480b07f4441df828f2485713a750e7f37b0cf196d87fed2e3021dbec5443a819b200f2a8e2fe7597bca6a89caf517cb3cdb5b85477d857871b1cf6ded6823e2	1	0	\\x000000010000000000800003df28388e0d7ec7bf62243ff763b5787a9772a59d061d58a1466c2fce73e0d93be29a717a4f1737e5e0e2e0f3f3e61ada5598cefed29d5dc9fc898eb2737d00249bffbf5ed1bb3119e001473647b8f2d26895aa276e62eded2a88c65c1dfa6ebd05da20d386e7897df834098f937373ed7251f0100901f3aacc5fb5b05e88c717010001	\\x0e7f0f7424ffcb381279837aa1657678308045521fb8fb3683432bf2956d349a5dfbbee46c824c9fbdcbf1760f3f703fdf6b00e4a42e565478beb51a289ed506	1668851248000000	1669456048000000	1732528048000000	1827136048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xe6fc87e780748a078f1d74c99af840a3b1130ac7c622c0c6428fcceeead29fb8bf89c4816a81e227f4b6e158f746072c9efce900efb17a10a2ed78cdad3c4284	1	0	\\x0000000100000000008000039444fd0fc0321d3e7bbd17e6cd9f54de652f282ecf6639d23776d61fc3991cf13108da6ac083b8e8ec9ace08d35d354fc6e36eb4c81a157864f826e0b723f2dc2dcfe90f077efcd12932014bb21b9cc31dd0056956095e6fbf91ed92081783b3e88f569aee98bcf42a922f22611050c115491b4a4e15cadea90dd8696dbef165010001	\\x7d571d64d88245ac7d2838b870dce7c88b0db4a7ed1fd7722835831502b3acfeed16f99ba8b3909eb50c580f81196267d16df0bed42aec725c5486c27b25e002	1685172748000000	1685777548000000	1748849548000000	1843457548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xe8780d1f32df2291c51af82f24941e7d2645cd85670caa9d08223ceeab3c7f5aa3d1532dad671afb73ca3616dcb7a4f47d425140be5dc4a56b7d276c2bf71a6c	1	0	\\x000000010000000000800003c5e647e58cec7f030e7ecd64f9f3ab2f2e48690a9c70b90d1a3541755c5dab6e6586967fd8cbd91594be953a2aa6a82d8e985d39fc086068b9a7648299235d6fa8bfcb7b6cc4f668c4d62e8809336ef35861c75926d26a3160b003f47f79083fa8b05d48c3efd8aebf23c22c0d154126cbdde4809860d04660308b411f4f2275010001	\\x7c859d7c3b35e402dafa1fe8ce28ebbdd33b46c4d461cd839a4b98d92707f3f45cfe550dd1cdd1c1e61fc9ac5b57c53b93ce6f7bfcbf335b27d0f2febf55820b	1669455748000000	1670060548000000	1733132548000000	1827740548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xe92c76492be276f71fad7f358890a7034555a5e73f2a78c345e5d563de203087385b9ebe4a13f8e6f6ae41024e305a74dc8dcb093266bb5dc843bfb4b84c969e	1	0	\\x000000010000000000800003c70de8aecd4b0e5fac7d9a5e53e709ba2483d68df02673c01319378cc177dfb217cd418d6222a523718993792ce6ad0250e1d9d6f84ce50996df375a584a42d3eb98f71ca26fc05fc3f2139e9575dad5f90d2de2f0174f630a8d746ec26afe1b54087cd3c3ef4ad7f9887b4164e03be7d328a455dac3cfb8504a8e5c484957a5010001	\\x4bd1120b9cd70c42f69972fef5af700e07caf07d59ba20a0161c6b29c5fa890ae200d59fadd524f8fb41cc7145f294dde0d78e8b665c2213f7b93bb8791b9d0c	1690613248000000	1691218048000000	1754290048000000	1848898048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
93	\\xeacc74f37389cfba4cba37b4ec20043f13508297adb3edcc6e7928e1cacf01131b4ee4ee4f56f44d8a21897a7f18f1018c40f672054112c6e0d14b9ed49e78be	1	0	\\x000000010000000000800003d0ba2e085062c10f7789a51b2d10b94e1c458c490e951b99d96f9ad56748aa693448f04482ce94d571c2fcc8dd7d676dc8637ba68fe988e1c34785cb8bf0314400275d4132995487c906fae1bbb2cf4f41717a547c5a8c7887de9be59207d6777c40a5bca129e6b44d2e6602356e74cc7b54e0546ffd342e3aac3500cbef98e5010001	\\x962d19e164c3959826bbfa2a125a77013c21236284ee2d3754274b08c1f5a7e8eb2141c0b9a531a45382eeaa21807613f2d24f2266fc3af92f3d18f40c9b730b	1690008748000000	1690613548000000	1753685548000000	1848293548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
94	\\xea9c0045737cb5756c526f0e32ff856bfd60ec0b74d9bde52a42ef28edf085416f5b420773a8fe5b569a7630d4fda09036f694d1edd5a5b384f9dbbe4cd07aeb	1	0	\\x000000010000000000800003d34e4ca53b6502857f4aa92b68c5851ed93871c8866822eff5507aca553a21d09159ce713c0207787952a70e1a96d58b26ee6e98a47fbdb72c26e86848f38193f8deee2fcd38698562a92b7aa8e63444a5b3f457a83aee42cb5b2a8fff07b0a32d3c09e9e4543fbd3904dd58268c95a94b7dd2205a419695d8124a681af1216b010001	\\x0263cb8a7f52cdaae0e909e7d77aaa3ade1ff047e2ff2e360c4b3718a83ebff0049400d0036ae8784f7e0c2ed35f90b5c66f7a2fb59d53dadbc83345e79a6c0e	1690613248000000	1691218048000000	1754290048000000	1848898048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xeef4ff9876a0df2c2265bb475c7a9ba7b0f5c3ec9dd5d175ef6cbdd78320c0d447d1fd3f67b24fcb3c0be67bc1578f55e69d6bd6ceea1c8e677d0faec69eef8d	1	0	\\x000000010000000000800003cdd1911ac4b0dd318711fa3be80a9365ca51047dd73e155de904a7752e7c006044907c870512e4af6546f726983e498215ebdb2d66c60ae92d3a577397854f8484c85191bc7ee56da46898d56301635a8f88015f79e7062cfb8da0edcfbf60a95980b3fd9ae720b63a7c79c2c8ad05d647d52ae5458b761d0802bc57142cfcc1010001	\\x9c64e4cdefdbdf00ad6ed13d4bebf5a55559c62122e378c9fe633c9fba2649e755c3a67d015bf53131b72e2f6e1ac477080e27b7608864d4b0eec2d0bd428503	1662806248000000	1663411048000000	1726483048000000	1821091048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xf2e0f96b3438c86abfa3c33451557d90536515ae8d787225c7c84a873e3d92b1c48710336c3d4f4c707717b906fcd705e23416de7e4191e98685693760f25b6b	1	0	\\x000000010000000000800003e2baa9bf1d9ff3c756bba96cbbdb23d43fbbdfc606e917d9187385354cb18bc686cb8741c3436c3348efe5e3770ce0afb7ab9b3fd2564a98703812e031a2c7065332ba60873101299dc67682827bd93f7c86e4337f4602e842957ae3d5fc240f76ef41e963e5b2cb40e48fde213a20c9cb6760ad54c54c76fd3ee3006046e683010001	\\x06f5d03a52d737b54ec231435b68a25bed85fbc7e809f56a44fd513b10119a6879e1cce312f783f7c8c0545733d7a0a9a24ec66a2713aa52ba77f439a36ae102	1665828748000000	1666433548000000	1729505548000000	1824113548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
97	\\xf4f8c6f8fb1e3a58960554b9a92745499cc01474b77605616e1d3ad641bff8759e4ca2bc9835b2f4fdb72655430cfc4c55357f6c695431fdfd087abcbf2e33fd	1	0	\\x000000010000000000800003e259271ffcd0ed4b49c897ff6227709cfc093b3cf66a3fde5dfb20221e850d932e0d7edf23d8b2351e2b2a5947b721a9209aa1bdc90f7cf6a77fc0811b830107cc8707fbcdff865349fedcbafbeb7523dd2ab5ecc9638a3dc8ae7188fc2913798f7b02d42351c36d2a50604f7e6636492551213bf33a08e64bdef6bb510b55e7010001	\\xd38c7bd403ca9901f0ce4aadcfe05c04ef7fe37bf2f4a2d1e0acc4595d08048dd4d7aaf7468a6d01f40339977107ce2dfc56301ea2d83f92fe78a5a3b653e001	1680941248000000	1681546048000000	1744618048000000	1839226048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xf478f59b832e08bfdacdba461685c9fe19d165129aa9c28540c56096f03c02447c15298139e96d76c23134a4c9421c2e2c8a89a54fdcf9843eb1c24da76bc178	1	0	\\x000000010000000000800003db3dad22e7d5d7692ce0a1de874d2381c8f1980ceac38081be66ecd63d48ef05484ed1e64063b9fc81e6dcfb5ec50be2c769c8755d444a6044244ed467bc6708933ee2f5513e858d3a7975acaa8b878f5877656ab56a5f964986f88796852b2a027160d1c1115ce01c315da96a8712fcad3b6d692a935ae58408ad048bfab3c5010001	\\xfedfdd5aa9d2994794bbbeb355ec7c1c14c3965d239d8f420094d15d510706dbaef05be1595b284de46914546f9f2444fca7c55ab99a0d71f568f9ee4f536806	1676105248000000	1676710048000000	1739782048000000	1834390048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xf808be5167cf311f8d98f69f9e9ca5ee41061091f48562274c69ebfcb72233bcab381c6b4e47f838388e081230b6740e9a5506b501f238108ebc9fdabeaca93b	1	0	\\x000000010000000000800003aeb70ed8ec67bb2df86ea0f1f5572e44da971f4d6789964f76d7a5892adcf5abb5198ca220eb1193ef94796e1f291ce32ec72c839ea676e139440e46d1eb66100ff68458537a497d831ebf84ba7f749647547774ac36a04b5e53b3d7fcb7e429c4c26ffd55a9d0a4e884dbc2fde2b4a12c0510d6841dd8f1e83d58da84ff98e1010001	\\x606108660d160817ff35b65a83f8886ab8ff4c182bdd050658d1484f7e1f80b2e1ee33306f739d5c65f2714a04df8d977bf598bd7702229f28265ac1665f0a0b	1684568248000000	1685173048000000	1748245048000000	1842853048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xfcf8dd825a00af244960461d7f74cd89f6b1ec9ed69445a0bf53bc6b98f99a370a178edb566443e4aba9400a4d6098bc48a00e7f762ad6260c3f2b3e0dec9c59	1	0	\\x000000010000000000800003ae2d25a679abc99b46602922936d2915575c93effdb3a700369fe406ac77bc88a12083b863278408da5e11e7783419b2a5af3ca8352cb226010f1c85358d47ddb85d874b6f5a8682f71197e4ec6dac2b9db6d32b6ba77e6aa278392e985db54f0dfbac6d1a8b9e302ca22e2a753b60bf3008c79b478b77a297275292a3ffd89d010001	\\x6a627379187955a5d10e7ab7675fca2f1db3dd55746f0d3ff70e1cfc2fce90edc40934a9ddae54564d94248a0e6fc8a5c66bcddeafb960cc699a2a3ffd031f04	1666433248000000	1667038048000000	1730110048000000	1824718048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xfd504cd4f3b1f22f66a2b909b7798cba6a6e6c5ac5aed9ddbc7355fc97f9399348a11bb0c877cb1c3f0b5dfc74c4b9e0a9630c4100d5c5c5813e4c973d37e4a3	1	0	\\x000000010000000000800003f0ab770f847ff36621a108b0ddb8bc3056b51344b9d3e59a0b6d8845a5232d25f773102b8158ed9b12ba846c32e87badbc2537315bdc61095667970f9634a455bbd366e13398e05a9e65bd56e20c213143df07da4d1c931b6b06632909c4a53c7c2ef0d1aea9eaa699ab2ba2bd03f6b47c9cb59e489bb67caaac7234a2e3624d010001	\\xdf473c2af95eb77b7c811bec8e86ccb8f1fd4eb753a6f2bcc946103bc8a1438a667bdcafa145778fe5135c75cb27fc141587e168f0666fcd58e54f8f870c780f	1688195248000000	1688800048000000	1751872048000000	1846480048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
102	\\xfd6c0107e17ce29fa6c0ac0908e3cc85202734dba7e5ad61cd2817a8678248125743e6fd9fe64c1b7e734880564bd3a6248063db2470789615a59a4ac22ad81b	1	0	\\x000000010000000000800003cef0c9db847ca435658644b73dd2c05d2f02b8096109706d8b06f804c4d287e86b30867f8becec1ed19b5f55720bb35e62d44f267686b420c2f5784a48a2e634a572995bee77b97e626757c043b6c4da117872022d9666272e1d34710d166cd548e22c933ca638af3606ea2a0a59a0ee61597fbaaa76b0da4ea3bb37886b881b010001	\\x4d10df0cb1ce7b3852d8220a525c1efe72fa318238978153857755378c868d6dc468275ca71dc4c82a1caa6be7b800cab33010de8a755b5e3407d6ac1592110a	1671269248000000	1671874048000000	1734946048000000	1829554048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
103	\\xffb839e9e60cecae212e177e1db8f8270fc2fbc53f8cefa35356a43e3a416d7d9ec70ee0ce3f7ed85c92822470108d3fbafcf26c3ebfbd140886e15ddc691fb5	1	0	\\x000000010000000000800003b9fbdd4eb14ed3037c7393cf17e12700703d1b98924a70c560c442ea06c910dd89c4e05a1ead968eb3a3ebbd283727a2214174d367eb8c6d9a45530a22103bce43101c63a763ec82e927d6aaccae7370b0a78e00574a3c528a89f30aa3da039d0861f16b7dab086b49d421e70e50cc941ca037a57cc946be8a82943f78b1169f010001	\\x4b16dd8be902b586c6ffb7012a6932c25a2c9907418d8a49caa88d321d96a849c0c207d848e4031c87110d73f4e8860047582f258eaf255727dde95393fc7406	1691822248000000	1692427048000000	1755499048000000	1850107048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
104	\\x017d1603395545aa60337ba723c088f12c3c82b023447e70e452860f32f36ba462f1f3e7fd93d043a968660cb6de348d594eac483a98d55a47976a52284becc4	1	0	\\x000000010000000000800003d3388e30bc97f400cb2c096b56870f9cdc1cb4d9462f6c0939304d01d9e56ddef08e09362749b141b6351d9553278571d7d62ebc7a1198e510cba8bdcf7fce8b924ed2fd335d2dd052b2f18c6a943948b6b80b743e6dd89cfb8934b1a06b2483b5765ce48e98cea0ea9f7ff5a9aef98a3ed6c120d0b811429003ab27b7114997010001	\\xbe9927a7acc2bf79998e3a3ad853b9aafe7ab49b1237c35e6f0847a5db4f36d20f28f2ad3942bee7f4f5b250276c28da4930da11650adc7a5839e160f1dd2209	1667037748000000	1667642548000000	1730714548000000	1825322548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\x05d9f8d62c8abc49f9e5ecb7b7d2e4b3d95a6115940cbfd2f751297ac1ef25a83f7b60d2ed6d9fc7248d2a3f0b196159d9239ebffb522c86b3bc2a0c60499f73	1	0	\\x000000010000000000800003cbcb44cff9ae99392ea951138b17869598b050d11ccfe3cf2735bc36e25abf915150fd6f37e1483d4a7f78da339104476cb50a472e81d822967611b45ed053d4aba4b50856322c659f9d382078c3f2edff51e2c27489aabf38ec9f26e88174db1fceecb82beacbcc387634229da3574b00b97a9e3c041791a8ce1b097591c69f010001	\\xc5e9894c59c5f8ad12f8eb6bae2188fcc7987eb8a5871e053edc841fff7281efd5b15f78dd6a5111378afec545c8d475589790c09c18538768063413efc6e903	1669455748000000	1670060548000000	1733132548000000	1827740548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\x06195744451fdd61d42481abf188bcdc9a038ada01698ca287b17ad82b6275de36f51ffbf50726c33f1bccdae57a4f7756d2c2e5d88d24ea16aaaf28d3cf7e96	1	0	\\x000000010000000000800003f474528d9d17d8e834318ef165b1fe19e2cccfa603b430f4f9f5a3cc152d578852e474cf8cff66191f9495548e18ae295ca45a48e305c8ac226f8ea3709daab2428be23de7c78a67958ad305db692ca0efeb09bd08fa611d6d4134cacccda2311bc57e7cd646b6a84661f323774e84428632acdfbfc070bbe0890820abd48d27010001	\\xae3c68b0b5140824a0f6ed7865364b269a68ee18963707c949c1420429aa196efc7dec21e3a5f51ceecef83ff5c4d3f204b1ccce5433506dc4a6b1f88c2a0f0a	1682150248000000	1682755048000000	1745827048000000	1840435048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\x0941e79139d646f12a991ff8c566deb0f1f5aa79474778380516be34b2941e785e11f4d524ca9e71a09532efd9dd741a05f1adcb47cd84dee74270871c29c848	1	0	\\x000000010000000000800003a3578c3696122b2ce79be472ea9c41ff151eef124451782d7382ca94541ee4e84c18be1a03d6608530fcedc4c7075fa37251106cb98d9a695b1fe17a6e1a719713fef201863110327a285b92da94db9d8958287021e6e62f6eab1550553ec2de5616edc7a35409c3442ff519e5f8929b126bc05f8dccd591ce5a57a7be1a9c5d010001	\\x13abb41f1dc145535cf72629677bf9a0c50b16be5d1a3a91d9e9a5c499b4926b08b9f66df945b95a1bca60a94c2977573bad3c5abcde2205e1747caaaf756a0b	1676105248000000	1676710048000000	1739782048000000	1834390048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\x0ac5aad1210e973e59d92c8565843db08c9636e0bd2f9b39c2d6483e41cac0c1c7bfc740f179db56bf72e00ae98668e848120e196ba1c8cd60412598ecf692bd	1	0	\\x000000010000000000800003aeef550ff3965a22fdba5975dcef50e2d93df8a15ffd3f72662743d1f8c37a8bd3dfd43b9a5ad1d603d920f88060a8e14bbd5a50eccdca8830a70486a40b86f1a02e93080cf3a182d6f06a7da5a38b83397af26f52b40243821571b8bcbe56e770f8aeccf2729f215542514e1cb0308de4a4e4a031c8bf8933aa49709ce7d495010001	\\xdf697eaa0e63879d7d336a62687fea1a6d33eef10e7281c0abaf3764fcc778f2d51bed3a8cb644b36b7b838e05f8c8b0ccb7af9d0e2366abec55438e47bb5d06	1672478248000000	1673083048000000	1736155048000000	1830763048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x0e0931db40077f549fb185a6034babd2e086d9ca8f8f013f87048e9773de12ff9adff25e054336c0d3e303e14398d7a711caea59b45b8275690e97c7abb7c4ea	1	0	\\x000000010000000000800003c6e5a78c35225377482d9f24e1d8181f444bd821f013fa7a095b22e7d2f92e3070a6c209bf78b7de54c984739dc34689a4c3fa6311f56519f38c72df1f908e73b06f03f0c0be4aa0febacc69e145bd48aee2cdd805f1b0a3a94461d11006285aceb850959c67bf0aa82c0b0b048bf092e5ab7e4a42575d9725b445fe472b0885010001	\\x5ed62d4df929c2f6f3f04dd66e4e1084cd075ea8b6075c63e3b773ac34b38936b86954e10ab718a93cbc3d6e97ae20bbccf441382bcc0a5432bcbcbe42bd8100	1660992748000000	1661597548000000	1724669548000000	1819277548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x112131824c553af5bcf3d0ff90e2477cb7072833ea3a94e452fcfb8d67d2df09f714130904e0710d385fe2796d91194603a0b66f1a052dca71ef764165d63db6	1	0	\\x000000010000000000800003a7a23107bf6878ccc53268e08a18e5f728dd2a771858d2f7ec08efc32f27fd8ca67e504c4cb4e268842ab41574aeb28b114c16d20f68c34be52defc56dc652d49b42435351ac4f1c48074f0ab7d64d15a510e6fcdd4174d9dcb6fe0cb5df85543a79096393e6d0e9c08f1d812b22af3dfa2f0e2fd8e1535e6e53b8178a0f4e93010001	\\x36f8ce25673f2c649a96449d24dc6b01d4241c7d693fc844e18fed9465aa20869866bd2a7da838b90ff8afa18e112b808caa787e7a94885bcf7c39ce269f7704	1683359248000000	1683964048000000	1747036048000000	1841644048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\x1191da3e44d7129d6d4e02795e34552637ac7bff70d9d39218ce619071ec398fce69f4b6ee21d66573884bbf8365bb220584a4916a70835c056b77ee98fff047	1	0	\\x000000010000000000800003c19a9ea2992890ef62f86abea196749dbb5dcb11845af3d9ff03b38346e877ea7933c063cebb77992f34eb0b304461c932d90a14c0b4adfa29fa186500ab47151dca9e2cad0fc3346edb91c61b92988c0e195cd3141b863bd29a2be75eaeabd3761d65553c764a16f410eeec18eae208ccd0a2c7f3887ab2ed01379219c26d07010001	\\xd5b0b87258e1aec128ffdff77a8606e8ad7aee6e36a4756d5458ce00beafd9e422152406ba034727b3c927812c5595cdf3826dfb3a5c3ff02f3f54c1e500c600	1676709748000000	1677314548000000	1740386548000000	1834994548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x116156af0dff109bf86cf83aa8b1080a07fb8d2208e4e822cde25953ee0a3d1e95040e491caeb892ac32487d8fcbfa6af75ea7e5f2c16c6bfbcedc41e0ac0329	1	0	\\x000000010000000000800003a899e39a6c2c55eb006a9a03fbf2929beac60c08831f1cd79f8f52181497f89162d093c70ab54d326039acf905e604603d8868d481b87dc32d885ff09f5d28f54b0eabf348c20ff64035adf35a7fe62ebbbd521632747738872c078b0e2a414b23d9b406cd7b9a66dd5729edb5c5170c03b282116dc5dbb84dbc97553053fc3d010001	\\x38897ffdf7140bb8e40305c00aa91598396e0bb4e3946c5128d08d69b62a347d00bdf9e265785c88bc1660a51905b2dc5e802bc6cc239c462d5ccdadc0655206	1682754748000000	1683359548000000	1746431548000000	1841039548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x128553014ecdfc87f9ea65847aa584aa8c1d9fdb306b98bb11d9befe989aae2384a243034d6fc7189b2f902e73f65837ac48f4ba208d0c12b54594cb0d27ccbf	1	0	\\x000000010000000000800003c45ca48680dbafe4b41019bc258acbb8fe65b90d6f2e9e808c71ee7640b77b6fa8b0e0b31ff37c0eb3f1f3c06f475b7c5a2ad9eba1a016eae9713f216222bdb525b6432739f35feee8dbb5adb88bcdd62296f1bb03e0d2ed57ec033378555e899ca61267b09036debb20bb0f455f0524dfc3b1e853a04b5b3194723b1fc4bebf010001	\\xdfc79b0410f91d8caf589e5f579b9bb9de4edc41b7d2cc5c78a3f7d24318003f2b9816c23c1548e0352593ec3971a9b85199b5ac6c50e6fac836fbc074aac600	1682754748000000	1683359548000000	1746431548000000	1841039548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x16753c61e142ed7316987d0a3e91381bbe1f9dbced754a0e3b721ba9a2c78233fb1176cf469493d5ae620a00a9350856c06b8230133ffd84b1a31d45bbfa7b84	1	0	\\x000000010000000000800003c0f08873c2fafb6448360066d74db7737bae10c90ee9c4dbc8fee6ab95f31a88d24861f6796a1f9e17c911378c7839349e79abc11013f64b47b70eddab8526c01f99f875f8bb6fe158d1925685f72278fa5675bcb5456ca4be70715be9fe65f6fc0ef19916304a10467c162383b6bd5691ef3e067c5835734ed18ee8643a43a1010001	\\x610ed1fa1d7b54af4d1b06df9799dd044a1e399996412b4e8f1b49e04735072099cdcb07c95890a95ff14dfaa452ec8cbbb9d584732e8b3f72ca3e6d47f2d809	1678523248000000	1679128048000000	1742200048000000	1836808048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
115	\\x1b59e01d1e524bdc9234bb606d7880344219cee5c44fcf34e5b5ce902bdccec532386b06ac538f3e41c2dfbb53a5cd8510bfc7e19b59116bd97d631afed8d5be	1	0	\\x000000010000000000800003a483bc019ea31010253c398d408463b0bb73cfeb22bb8786b5c2286b56025690b296eb616edf14a98c81a161cb1e55a4717e26836238eccb6d0d0bf901401132963a7fecd46f31ff6f6fb104e9cbe2e234aa2f8caa09719d7aa332d1b8b82e537a6be9ad1a2edfd3d488486e2153b66ebc2548d7cbe5e8f144557233f733ea8d010001	\\xae7d46d55642b2ab210c02b9a9009be99444ff8fc3c197562eb9e1a270ef9c278779bf66322d90e983e4a60aba1292e36f7b368ff6e755383673798d128cb606	1668246748000000	1668851548000000	1731923548000000	1826531548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x214dcad790ed9f3727e4f20c47f58290e48562e692d46875c8733afc37aac95f24837ab63cc69a4cc1cd837f3edf5376c2ffacab7462f41ba2fd913b1f29ab3a	1	0	\\x000000010000000000800003bb61ad9a522b6eee209e73db9fb76e01c2d7fcbbd8a71c10e5e81baba89bf25bf821130779ed61d9cd6d855852d4a8a58456ddb6d08178e36144bfeb420607ed4b4678449d508f2a987392bacdba40acf977c497ccb8c96542419a1771756af92009d8ba77d11577c8d4d48d5d699335e66ec2682148f86ef52c67ae992b2761010001	\\xf49befe6d40dc9935bdfed177ee3d7c07756913870e03004deb540d492df3753c7254d774a8d9dfc7f050b9b814e66192b6d8b354b3cae26c30329bb82ba4f03	1672478248000000	1673083048000000	1736155048000000	1830763048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
117	\\x27c5f1b08ffc1b58fb03e4ecbea774bf9c4583de48f407875cd582c13aa0950e48b775898916f1183a197505222f67398e69af77afbce8c14254cdd876379c41	1	0	\\x0000000100000000008000039e01461ab65971fa4977ca7f227980ffe9cc33d089babad4a5ace9524a60408692ef49b14ffd06959bdfa616df1be53d1a540381c65a13c61fabfa47aa126d34a99e2887ffad9bcedb4b4cf65672f46ee50fafaea3bf5424c01de8f7cb84998307e329b43f4290937c851661f8ad6575c46e1b9a308c8515581e050aa8cf3e79010001	\\xb8e0396598be3f42c7e80a459b9a1e63941652466957ce17b32c4e9c36cd0b17a27d301fbe23025418b1605fdcf5b45c0c68ff49f367e60b4e76303ee47f0e04	1671873748000000	1672478548000000	1735550548000000	1830158548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x2a3d8c79bde925608516d514141b0203c1c6c1341fe90a7dc942c176e54a74b1010b9acf3d022e4746f6b6842b9f09bec75bf4d33c136a044c0b2aec32cfbde1	1	0	\\x000000010000000000800003b5e820d5baaeee6a8d403002c3ac585813e1a19f6e0b1c92d251ee7d68785d8f74b89a5a0d5487000a4f6f78b50579aa188fee6397924eb06d13d71553b4870caa39ecfb0cdc32d7e7b417ba5e20bb34d06fc512a7ae3ff0767b0c4e877e3fe2c93a787a15aa9873a206f875236f248c870198fabbfa341b54bc752cb6afc2d3010001	\\x31d91bdcff66139d8237ddcc1a84d2471c2481882fd06fadd7db210946e30548b9a05e1a6c6297eea4e43e2037294bd68e6d286dd21e801f9f9eae13fc97670c	1671269248000000	1671874048000000	1734946048000000	1829554048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x2fa598e7ddbde9838b39afde0f627eccb0f2b2ad6e0b38c9e6b5ddc8f1d1956ddf2bdde05fb93c4ba08bb5cba16188dbf1d221fc89e79f81db84d95352c71961	1	0	\\x000000010000000000800003e85e935ed84b56b3fc788c15be6093a44214ebfc84663fdf11c415d50726bfe85adf2b2be90b7fd20c0e8422e739a6f066f5502ca438d8921eea08a917c923e5d9e405863ac21be30b6e4cb828f8ba8f541ade0e42d7f0deaad8b0e7f71d268741048d7ecae03e11982af42e4896ce4ae81f4d9127c48f19c3325813a2c043c9010001	\\x9727108d460d56e52d064c5071bea31e3aab56b9e23046ce1e11df8cf89236aa8531f48eef4c43fd58712d01958ca1351297c2068e203636f8392dfe1cc83204	1687590748000000	1688195548000000	1751267548000000	1845875548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x2f19fa22b67b9cf04564223d8dea63017c3116603626e1b1b1cb4d06b1151585c282a1aa0a84a5416b5345eff5983e382558b1648a7ffc69b77e1fe314e5f4e3	1	0	\\x000000010000000000800003b5cb9fc44101fe7345cd0d20b35e795c627146a45731e1b25479e1d97197e1685e5ec2f573c2df5f5ea9571e90c3accc9491ad79758d50310696012f81c114dfa380cf03710c68617956c531f97a2fbdf051d78b7aae1a7cf3f1235f6de52b0fa267f9a9401de8c2622740fc3e95d7fdab84f48acdb050699d95b23d79122895010001	\\x1bff1cfa4823becc68df04e0ff4dbed49ab1af31f3b17b1d26a5a7104d7c1bc3808b5b0bda3d98ed9850f2b26eb4661b3ec42c59bea289769f01d9c3171dc603	1690008748000000	1690613548000000	1753685548000000	1848293548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x31212d86bc882ab091428845dba1f2bc711e6271cd5746f9fbe268366bcfd6cfa3a86b6d5d4699c280ab58c43f56c50ef12cfabaf2c8b5d73fb9888b8f868827	1	0	\\x000000010000000000800003cce60e09f93fc4c3c8465964f189056350e87d0c08b311a345161a0254447775d9dcc997c246917b4174c78869d861b76b2c117524fc307afdfa971ce0d78cc6f8ae32a30a5e8753c45fd88b25491c3dc34e85584ea8568d1b466335cb4d9226bb7a6f05bbac8de51377042fec94b663c33c6a32c77e87827145227eee72fc3d010001	\\x1e969591a2f6c80c30bf8c2c9f5423b64a3b7d83c14064b6da8cddbd5b83e7316b305a4445efbec894215f7740ffd5aef8fd4734b79c6ef5175c82700195fc0a	1679732248000000	1680337048000000	1743409048000000	1838017048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x34853f62ebc68831475aa77fa0c341598db11c54fc0497abb64bb21879ded37f6ab0cc0d0dc60f0ba1d5bb8cc75ee009a58ee3e741e4148b331f29f61adb7d0f	1	0	\\x000000010000000000800003bdb33feefc2d062a29a616f348257c5c3d47a46058b6d526f75a6e2051ac946612e21cbe0e4e0eac39e9d089ff2f74a04d1fbb97a370060722463fa8446dbc92df0d035b0ef2173832e5a2eadc8d5c450e6df45fa49ccfe490dbf3e5bb83573f349bcf6ac9959f989d6ed4dde68e4d5450dd32cdd839d39e680a5ab8d9e133cd010001	\\x3f85fee31f10fa76c1307da6ef70f6c5ec318750a472925cb725f6da7485a2b04b41233d268063e4df498f66547316c38be74ff6041cc077f6f0bb0de4505d03	1677918748000000	1678523548000000	1741595548000000	1836203548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x3781b9acd0a9594d1b0dd6235857f407c53fea3f8a57b2dd6b9da0b873395d54e2c27b29047cc3ea76f04bf97308740a49f7ebc9741a13f5c2273c0701e6e4d0	1	0	\\x000000010000000000800003eaf9c75685bd93ab48efec81619f794938aa2e80bd847a19a05cd60515c20958b1e80ae9c942e84cf8028b658cab0054008fee9d9d86ce97f5b56af3b0feb82b4c4b48a71b92ccc96e0a77f3fd4f2110f8b8271a5999aae6e2422eec99d42864754371eead51fe8e4f4088cded5559a08bccc1f00fca644087d5d59048b59daf010001	\\x73e84cf74001ffde0763698a75cd2aa6b076de93cd7d69aa77ea0f22352f3b129271ec59ee3931f052bf70055d17839a416400fb887918337169de66ba749c05	1679127748000000	1679732548000000	1742804548000000	1837412548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x3b4173593e5879fd9bd23cc88ec4ad3ccf7a2ee5e8c2d90c89aede30b9a3a991e6e803e64e479cf2aaa332c7f3f23111dc776678550e6b23cef71988e1338041	1	0	\\x0000000100000000008000039891ddf1c53d0985c2874eeb04016935bf70a7ef1fb897768b16808e5e10a4f321080f45b7cdf7313fd70839754637a7fccc6b95a6a6d7d0aa879e2f199c1810d2cc5892b622399c2eb896dd547b1334f25cf44c728de20f2a2b2995e6dc575a6979b952bdba79f833d21fcd8bf49397d285ffe86e431337fe756782e3b36069010001	\\xb109b0cd30c5e6a7e6c180e71a9c5e06aeb29fa720ade66176cd01f1a56f2630c4bd24fde276b84e65a205ab721e187eb94d8b758bd3d0d58f85634970706204	1676105248000000	1676710048000000	1739782048000000	1834390048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x3c55d22fc1a5381bc565871fd077e4590e2c435c70e34a442b72a9aaa1492a8d9404e4bb7796ba220ede54373244a1a5f084d6396fec5fece54707d9ac331306	1	0	\\x000000010000000000800003d3a6ccbf5bc7614ba25cf250e487d251c18bd4fea3214ff57594c0ca7bf12d526d494533d5277b298596b73bdbe211a4938bb11a1d0807e8e4b5bdd780d7f0867b05a956d8d94aacf0246d9a4cce4fc6f0eb04aa095604b78ae219af2ca93cca23e180a1d6f58f35bd9b914808f3ee350cb8aea2951f0cff30ea4f2e21273d6b010001	\\x16e2ed1e56a506dd10678b56abba3163ea7a526c765724ab28e05e336834bcf49d745fe0ac7b6018ff9d6dd6451993d5feb89e5c281e40bd38f0c484e1c0c203	1665224248000000	1665829048000000	1728901048000000	1823509048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x3f117f79b953e974d23b2ae4b6706ccb79cc81fe1fc9c77a7aaf389282e2f83318edc94e09db19dc819598f343d31a9d1f28da7251e1ed6b9db004fdfd26aa00	1	0	\\x000000010000000000800003f626c53eab308f2947efe663a4982b6ea754bcbb3de3d7d0dc4252d21c957bd6f8fff3334d7c30ed63f4deb0410bf2d0ffc372e6ba792be5c9d74cf9e75ddf673ee960de739359cb0528ad0c0b08999a9ae56b846292f89dbd0f5f6a0e7e91582ee02ee04355eac69b430acefcfb90be54c427b8bf6f70009e6aaf600671f74d010001	\\x3e32e8aa4e46a587c7656ac737f5d31350248b1c7f064706788168148b8c0c91285de60369832f0a0831c2d0cf0c588a9938d3a3c8022ca92d77f3deac00810a	1691822248000000	1692427048000000	1755499048000000	1850107048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
127	\\x3fad35934d217428283677a16c72084ac3e32371ac84658531b6449d46657ec0447fd818299eb575abd3178e632444b755c116461ab4df3aff7d1c066cdf91fc	1	0	\\x000000010000000000800003e4e8c3366034493973e21f8bd3441747da00b0690a54c5f71983b3485850aeff8fe4afed7d6c007d233f7b2904aa757bea1733d131b06f011ce801b99aea718b9b494a9ad763c123d2249c9f3b775556dee9d947d9694bdbc43b6530089f13c1f8e7100faa1491fb964c7eb54e83133dda03f0abede9bf646b671d80e3e79cd3010001	\\x1d37177700c174da3085cc56c394fce5c163cb3f78340acbbf86c1cb8ee8b9720ec889fa413da381e9bf71b7fd6cb202d0be51603ddb6e2c814b5e590293950c	1687590748000000	1688195548000000	1751267548000000	1845875548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x41115ac718dc85bdd0dddfa07a7517e5533a371112fe6e644d22bc6aad77363c4928bd051ed0b4e5ed2278fc0054b3f65c7fa47a980409b0bed79831a627a2ca	1	0	\\x000000010000000000800003c365518b008c1a7a9fe4c43f406d3fcdc4d58b72bcabf52f53b990bb60eeb8f5969b480b530405a886240953934d8e4cbaea20bdba347e1acbf0be2d87fb89869d841c42f48a5312297c662d90547c979d9ebcce1af497c4a71ee7f3cbd74460f3c04ca59b196031d0f46f1e34674b3ae64614a1b52bae32b5c8f4ce8b5058d5010001	\\x512ad33fddf20a208df1932748a836bdf75eb08f939b4aa7982f47fac8ee1c9e611f9fa436500f41bdc25ef76cfbbb80cc649160b30882860760076b9b2c440c	1668851248000000	1669456048000000	1732528048000000	1827136048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
129	\\x42c5d22710faa6c8f57c3a91fd6f594ce998de1232749cbf02acadf11fbd4e85d1f60f99962a22268bdc7c96ed95ba1a8ba5dcf117bb9affa336cc3f54bb6d8d	1	0	\\x000000010000000000800003dd2987cbd71a5cd8095d78eaa0807757f0179e319f935c59e5e15223599dd2b4de9e75b30dbfdb07217c80c0e53d1072f7ac4c3689a68540fb34194dfd30220bfa774ddb79edf6c41d4248644b26445a50fe5ccb7a5ac677535ff6e8a30238b8ac866f9c6840b4c6a1ee6963bdcddf08e044145cdcccf6fae50b151e54aa5929010001	\\xb2a51a42a22e122a755d9fea32eb6c80cef92b4bff66f43e332d65a49367941bc02fa2e390160cc9f4917ddd45d72e15ffff27200ab1d021ca23da46e7931606	1662201748000000	1662806548000000	1725878548000000	1820486548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x449d37c99fb9586b0f3a51be310a4d52f4c90140e9226de4eeb4d2d483e19163812f0f41666dfbca4224f541ea3d9fca9f4d875485cb10ede67d84edcc54ec1e	1	0	\\x000000010000000000800003a69eca62c18cabd815dfbf1875aa67aee7af60f1d28db518397ad56471648b3381248603629fd695fde5438bf4d15ee94d89aa0d9e30ef5f12a580fbf72d13711c86b509d8fb4c353b1361ea1ac7f8515469ee14c2f9bd2df84368f69cfdf84ea5e8381771ab55aa6547caaf128dc667c1dc1cd72e8201bc06f9e6502eeb141f010001	\\x617c560078bea4b9534c33fb2ef20c6610cf1da49936dc094b4525f4aff7df949aa162089a6bed0d46122507f656d9a65a84069bdf28483eea80d1c779623404	1675500748000000	1676105548000000	1739177548000000	1833785548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x45d9ccf80e7294095a24c6b0aa5737e7aaf2e714b5c45767a7f2e3bfb4ebafad40af73ff8f6cb6b7857b8a95ff80d42e6dc423f7f0bf0b73269d3ff531918b73	1	0	\\x000000010000000000800003ce082141f55e7ecef732b5a3a7d921344410b57dc329dedd0750a38960c22f81af0eee9ebcb82e1d9ab87611c4a666c2474b4e0dd357cf8bebcd7b012800f33fc543019eaa43144ef79fd7036afadac91cb58af0b8a6d779cdf652ab39c19b7d0fc129512d708c4156c4ff7db6013cafa0dc01165c9fc12bc28343a5c840fd7b010001	\\x9489a7d1b4c1b8dec2f1b250c2b0ae2d2587935b4633c96c8c2fdba4707fd40619ff43f72fcef50aac9b95e9af6bfdd544e3eca036b6bf0cb6fd356f2b20e50c	1666433248000000	1667038048000000	1730110048000000	1824718048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
132	\\x45d1b38dcb1b74bdc51f9d8738d3471c4f16f5f69fd653f192d05251a5b84e41dd1080ac03a857ed8ebc20671bcd8d9a2085f1519378ebd475f40ce5b46eb25b	1	0	\\x000000010000000000800003a66e254cda522f641ecffeede6fd9d61a5a9e5b8cc49d9b5201f1a5b1592875c1a90d0b7920106cd2b2244bc178b5dc3bdb820448dc2fb383547c28a7dd83cdbfd38fd40851253cf713e21d476718d78a2ea44e5c7fa8bdd4dee51ce264890ad952cedf7ead7fe5d66e34fcc4be9c050df34297fea581f43aa7847f69ee8ca8b010001	\\x09a5c8115ae9c992b15194361fc6b1b0410c637810142c8f7466c1ce13a7f57880803149fb15031f749b7d7f8791c684511ddc7342e7d5191b0098747a909d06	1678523248000000	1679128048000000	1742200048000000	1836808048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x4db907d75b4b99ea8eedfc64b0cca1ea76b1637c786a491052906c47bccde1998e158de01f259d61832e0fc81594744e5ba4e11574d39700f55fa279e5e6f977	1	0	\\x000000010000000000800003af6dc5ef963a24101b7d468f3264691a2f493f6ba07563c4163539151dae8821a38ce0db964aff64bfd788054a554be9756bbf27f547be64b21ce6f4a8cffb51510a3865e0e6bd73adc34c39e885e83cc06df9af5341827b50327c815c60b058d75e97663fcc3d60f1d38ce7b453c9dca435b4aa2e29a22381656447604a1fa7010001	\\xf9bfbc916b95d1cc59d01bb6079291e5f4155d8e18a71c99d4a79735c50ad6576142a6f042da53f6509cfec72061ced035b2c3b5016452dcb6dc9cec0fcd430b	1690613248000000	1691218048000000	1754290048000000	1848898048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x4e9991a2234315d7dfab9e9069e66255dbe62a088338a23c9b3e64a9657dabd37e984931c598ee8f060998714c88527c1bea8a2fc68a9f400b14e59d21bf909d	1	0	\\x000000010000000000800003bb0e4fb1ec1214f7df75baba519e23547a176709dd50959f8b99fc0d2c729c15b804c2916613c002d378fddce9c0ea196fee1a061c7244fbfea3332fc3c6d535104065959a4660eb9db1455b671d176c43cd68eb939c5dbbb7d88e07947f8ea9a9ece28121489db07954847f3efa4ed573527cc524856fc12e6531fabf351c99010001	\\xf1a607ed74b46cf3a44a73e0b2848f8e87ebb452b9a01e2481220f2a01fa8a23e9f302a0426a3147cfff766e6dfdada1500e87245012217274a30879203c8303	1682150248000000	1682755048000000	1745827048000000	1840435048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
135	\\x5565cfde3c29a13c08b450c217c50d46a9c2ffcbc67a0bea8c321c447a05f126eb22e07dd86d92afe285cd8b0468f5329587f3a5288925c9152a0c8acaaed3a5	1	0	\\x000000010000000000800003a574015302a011bb4f0b0295b41bea6bea9d924d28230c3c920a8fa998e04dad28ad93d849dbe4f9898a433e87535403690e0485406cb34a1f135f2c04de3fd123a9e7a5679f0068afffe428a99e53f7bc1ed80d915042a379d9d845b7734bbb0a76fcab21c64522c4c4cee670bc1dcc158bed2f0e3f4bfb5166865ba65e9ff9010001	\\xebdee8324052eae03638711685a5a03eafb22f75c383e07e5ff3099eebf2fa2f6bb21a3ee266eabb91e123028196830ae2574000385b204848916c0e27ac4c01	1686381748000000	1686986548000000	1750058548000000	1844666548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x56d927ebd6b66705feed0c866894b768d30c13e8fa382b97ba780c766e19472f78ac9d5ac61f13770a5e2150b29258ec0d9ee8b58f9f58939da5c04dc3b6fc66	1	0	\\x000000010000000000800003d8eadb7729a5aac33588a530344343efadbf46baa86803f57dc0f4da5acb8e72eb0610f3a3e25b129005ffcbb1538f4a7f7427658666fc7cb9ad48be3243b0b7a137a413f6dc834959dba815bcfe5afe417f64cc14eb26566cfc80598d4a5870f046cb68e5c10bab1e8487ce260e4254f5ca841bc9be94438d9c5851bad0998b010001	\\x9359981f1a939444c096b9732b78a8f344d6f8147d28c72bcfa92df7d82c8d6c5522db55a6785eaa5b40ecd4abd5de45c993b429a623e93909c59993a2658a00	1670664748000000	1671269548000000	1734341548000000	1828949548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x5661752ac9baf4dc218ca6e0374f3d5c50dc05fc7abf62777d37fcd18b0c95e8afa2419741e3d4bb6a63de3ad16d39511324b7e1b857e3a0fe7297d39c8da352	1	0	\\x000000010000000000800003d9f9840f1d6411b8eb829a9aad597f1809d5cd2a67ed5cd18f926878846ef3c9871e5dd621a0190d264e2d1ba80ebb3db1b295e38e1d14e11cc41461545be1fbd0bbe1a9ee0a55d3e59898bb359794fc9a597f2be1d3b3b871f6f37206e5310f9cf311be2a7144c716886c4ae4800754823b60a22f9403d18ec3009762d49ac1010001	\\x00a4183bbd4e73d85f412a7eeef00709b4558a5ae35c1da78074be5df24427d2a40fbeda880eafbc6c2b716eeaef91e9baa761ebe5c781d6d838a6d26683a400	1675500748000000	1676105548000000	1739177548000000	1833785548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
138	\\x58b97bc1263d85b77bce98998060e79407535b7ae6be96e7fd95c69cdd13a1c8d28bed8c6629e03363dd00df420d2b92d81cf5c20d6dd95b8b0ffb72d6238d81	1	0	\\x000000010000000000800003a3a4f2c5cab4648cbfa5cf44fed618bfb5d97f707271696b854ae18aa703c7bd390a892ea6a95f9e5906ea52e8153eb9d8d222f58dfcfe4044960dfc70c65e7592aa2a33a8812e63a8f68c3fc484d28232934f9a6b4eddd35a1c3df53a6d8c6dd00f79adee53eeba1b0d94cf0fcdf4f0b1c457a6a477c85b50ae8bfd3bd24f31010001	\\x55db794710076798768b6ef1edfcb6373307027b2b28b5f0b22ff0e368f764e3ab660d06993a477a3c89963a0f7d5b02e0f063061e46f81cb7d7d8582ebdb207	1664015248000000	1664620048000000	1727692048000000	1822300048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
139	\\x5cd9f20ccce9f6b04bbc8fb52b9993af3285bdb789fde9ea2e5b79f2cb149d43d1105dba1b92c8fae4de884383ddd80bb5bb7acafa4007d735417f52a81fb7fa	1	0	\\x000000010000000000800003ce737b5d591935e9eae8334ef9d4b031afdfd4c5b920e3db9e6fc05b5c4d59f3a5001bbfb864ae3d6b97d7ad2479945ce41481aae9b292376bc8a67690d8f2468cbe53f2192d1b035c049a5f684a168732802a25c9b35667c7a779b6ad0c03cbf40c0e71f0dbdae90faebcc6275abe617a0cf7c0bc7eaa8c6fa5db5e3317107b010001	\\x815ee2ef4293d6b04ec5f73d5273b5f2ed3542f6571401f84ff9b9d37da941fb6c975f18285efdccce96932d3356fc586453fc6e2e292e1e24314a8c24fa0303	1667642248000000	1668247048000000	1731319048000000	1825927048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x5ee9a9dfaba1a1aa36230f3664cc7e762f873a03ce68362cbaa4d95426634d34ef06417be4d5f86da08e215ad621731e318756bef54a08da7ccbcc432ff6022d	1	0	\\x000000010000000000800003ab6caa867cfaf8b2759ba22404d57b14a0b99d20091b89ba99ad2911847b76dd9f07fbc34444e42c9bfafafa2f7732ca763ef5e1613f871b7704df2bc1c8779e5da2ae870f2c1073c72ec3c60e10b6202934a88cebd6786533a247db2f6f0a0a235f0a3cdef333c48323ecc5f0d002e192aa588fd1d892b48315b19e41276257010001	\\xc9cdf384b1145112e9879787b354366c0aa92398e60dc426a43234e9d68c750480a2e605e273df06109f94f4b12ac8a87c3596dd8c18af79234ea9565016290b	1677314248000000	1677919048000000	1740991048000000	1835599048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x6635c6524e9f988aabe978a60a4c7450008072b0f6dcab33fae9cbffc77c74f351fb8033603be2697859c7753609632ea82caa7a2fc832b91bf8ee5f5e52864d	1	0	\\x000000010000000000800003adfd34b36746ed3f4bbd6ab37e127b4c12ab0c2263941e18363630f347400ce00fa474b9bacf60b3568f3c13a9b5d28fdc52a92e34dd8ef3919cdacfb635dd6decb03d9240f754d308b1db697ce16e378105d810eddc0b0e36b102de21e9fb477982b91d58274943fd43ec67a29bb017282d6ab99e3e7e08d8d7568c82d7ae0b010001	\\xd526c8f7ea4e20e46b77a8d1d7ecc8a91a8c209a6aa7cdafd0689f9c3fb9e01de383678f11b7af18a4c79e38389311ad1ec47103685c9df5e44acc1252603806	1673082748000000	1673687548000000	1736759548000000	1831367548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x68399bc26112c34cfa959bc475b2547b30b0f63f417217c983f0d688a92142b3600843657f9eee8a7b2eb6b98788cb25c1c6fe0691f78e3c921ed3e7c64904d4	1	0	\\x000000010000000000800003ab8ab43bba62b458bf4e6ccd390075a9b36a0f1a089b0aa649a5b8ab64904a61cc78ed2fa89637165623c1e1275ead24d03a8d8a4a8a706589bb770d5629ead5a438ada3eef37afee4bad7dbb79bf0c620cabde713d40fde8dcc79c972592b371ebcad6251d2d01fdf4b7231582c30cf33c25c8cfbbdc619ef7504b947a6256b010001	\\x45d1d7223bcab4864e9213f133e372bc9d6a699d6a716e5eea40a5b2cf74e768c0e80e6e5f757b945dc937498d4f6c8f029fa8618c94e36e360658737f93f400	1661597248000000	1662202048000000	1725274048000000	1819882048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x69f9604d08a38832219a799199edfc6ec131c06c3d78441ab5acc7f26fa7f89cf91ca4990b0fd6d2a49ea8b1210cb405423271cb6a719da337def4137253dafb	1	0	\\x000000010000000000800003a96029b0f9a09b4194cf95ea0b4025782c9ec5303cf6c2848b378bec1af0b5432d3262f09482330fb344738fa529917e5a7328a55029bec3c041c2007af0dda804b3b4ade9fc3907d2daca1cc817c0ff4340ddf682dc8642f2f336c603ff0164d298218eea8fa50a3c91b74e89d02806761ff8a7cc5768b3a38d2f0bf3f90bfd010001	\\x3aed4fe2cbb5484182de23e0507c27e47de445ab387dac1cfeca23e8102d22f5f34840e685479221b67cf9230a56978f3b560e254c743ec94979145256a17502	1689404248000000	1690009048000000	1753081048000000	1847689048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
144	\\x6a2d75f93d19746a32a1c6fa389216a1831d22159114fc7b89fcea42f87f69bc213c5e772c3abc09448cf0e8527bc16d1337dd5df3287c020bb5d776c40702be	1	0	\\x000000010000000000800003df282ea57930841299507994d23d938041caea74f8a7fab2e76f4f59722ca1d4e0e5d5769f9fe2c668da7ccb7cdc80ef86ba9d9d5d2a44daf2edc5ba852808a97a7b5171f82f5a72864ae42c467b54f04fe7f2d3fc56ce413f7ee9b79bf9c52ec38a41a7c2e3279e9a4c78325a0a831f958795bbe4738a52bcc240bf70ac8d6d010001	\\x071043f0e2dff9fb0c7fb944a17b74fc6dc4b6c58db5e666b6c0b42ea4a936d3e87d67a9d13e9caa7441c3ceb361e95aecbedf95cde13d5f4fd3ca925060e108	1677314248000000	1677919048000000	1740991048000000	1835599048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x6b29d6ad499aedebfb65a12984bc80aa65dbe97b7f3772f7b0397bce49d85cb9df323f793981736e53245e744cee0da8b17354c20e943c8884e2a8e900af802e	1	0	\\x000000010000000000800003b03ca03f895edc5620759d44f49eb0af08be141d1981ca5b327c0580fedbf823a9e7a6bf96fc18d7371bb1d8eb2f33456c0918d7a27a15dd539c77740602dbbed92ecd62d7595350c6d7483a7eff5e2f62d972b23bf654027d9f0166828fe395374624b3f96840001c0ef2e6b3a9c800b97ce5fb8fea0e99fc3ab3ba51a0bef3010001	\\x1b9f3d14939ae652f95c83b8e05862097185849dd69a52ece15b1f3226d96332acd2c061fdce4c8c076d32c14eae86241c0d74f3bc0035e7e24344d175dc780b	1691217748000000	1691822548000000	1754894548000000	1849502548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x6ce96eac0315fb0624d33370390816366355d9c51b49eddbcf2e12c8077be4a9f367866d634f471a2768684b029c396bb144ec54c60b8c9f9afe1bbcff88ef60	1	0	\\x000000010000000000800003dfcca1f97e3c3378dccb0d1560aac63baa461bf8502f0ee937ac735509044c521e17977aa9265174afdf8adab524759c93460002a585f9b39808c88c2e0d8f1cb4622ad97dea3fa243508877783ea07ccab18967e31396f7803fc2a063ccc916c80dc6832c2fcfb77c84d1477362f48edc2d06fe8b65dbf701dacd7d56606707010001	\\x1e7c6b10861ebcee231df38a9fdb3b9323df4f3e196a67ad6c52877ad3b0c9e205fd39837b1de5879e29e7bdf953568bc335ada09d012f47c9787b41de941106	1668246748000000	1668851548000000	1731923548000000	1826531548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x6dd50136805d8d24ffbebf5da9b6c9ca27fc66e454be49441a533122636bfdf0c2db7c477d67932e17f65bad5de03daab2404521bbe185bba2ff5d9677d967d8	1	0	\\x000000010000000000800003aa477e8eca7e9ca2cd6facaff52257f80261a8bdb75b573f83d27a4dd20c0c260759edd5c90298e6e09711b3972ad5ac9961096e532b5e924de3ef3748cbe0ee52b06d160e59971943575726a9f7105d664205036e07fb0c8dfa7cb8506fe0d29cc28bd70a38c367506acafbf650b1f17560c3d7096cffbad34121f8b83beea7010001	\\xf80dc961b6dc4bafc34a4b6009e9f67428d7651b4bce7fc0e0e2d606d8ea218881eddcaf6434177143473674ff5a15523b9a633c817b8ad2e17429707571a000	1661597248000000	1662202048000000	1725274048000000	1819882048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x6fbd11c4f4f09c1f6066420c25b0a8a65811455fa7584e7cecea18bddf63d82b3fe80ca1fa9de0fa12def8429f39c052bd39b14706869e0fccb3e202c92f0d16	1	0	\\x000000010000000000800003e192155fce615815c4315837c1f88b3badb6c6c3d81718d582fb2270d340232d3fb846d39b504099faef7f14cb1becb33e34e154df6aabfd96418b7bfcad8d2198247f5506ef41dde1a5e6eb10d6069204b8fb5bfbb1a8a64cb13dde41597700ab0f255f7817bfb45767b03b099b9225a4814b0b30c845e23fb54fad2729b421010001	\\xfbaa8b02e53a1e5644f17397846b38610de51f4efd74023286a1b29016a549e9d5ec2b75c434dd244a5713ef6b93b4ac56dc26aadadd4640c4f60da9fe23800c	1684568248000000	1685173048000000	1748245048000000	1842853048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x76ed524a0e6e5e34a4cb0a2bdfccb54c1cc10b2fca5897c8af40f5304a835f58175127c95acab3ae4fcac4713b0363f0ca2b17bc4432f6aadd382f63ff202c31	1	0	\\x0000000100000000008000039ebd034f480206ca583c0360030347be9b9652c4e6c4c3b8587d3cff8423da680a005e43632d37a5ddbaabc6beb17a0fdf68a41d4c3076f55fa8d7afbecb21d5f58de56ae384b3a758c83a0a1c4905c22b1e3586787015d553838f6e3df12a7c4eba0e4f25df19c152f62bcfb70b044c03d1761215e1a69192eab3875ce28c05010001	\\xe81ee02a2a1e25718d4026e61561ba6c657fd19a20b9913c33e3cf8a8ef72e06b81ccc0b80ec12b48cd77c78e1d6203bf4735f35d73921bc24f8c3cf91291103	1688195248000000	1688800048000000	1751872048000000	1846480048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x776997d353ebb35e2f6b334a6ec2cdb15c17838e469a78087c4fa745c0a4df1cb8f75faa6b1049ec1adb2f40fef4e1c71efb9a7e9bce34703506ad660b172e6d	1	0	\\x000000010000000000800003e22ea405774386f4dadbcc86d47214f5bc8f0af6e7986a8ba1ec5bef31647b2c4ac0df489ecc936a2f3982ca18c557237a07e9c916ef2d6dd5d7d90eaf68c2cd6f7de50c49f0cd10d6e08bce22023582b8708be5c24f25ca974354faeef101d979f9034524183cd9212eb1fa8770eadf15bd3301c18239ff6bcc8a1e232f3059010001	\\xc17991c8b48bb92e54c6cb5551a20af37967861407ff45b9177aed502d5a42962c184469b9a6506ed52afdfb8297638714f8a910c6094fb3af10a82405781e05	1670060248000000	1670665048000000	1733737048000000	1828345048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x7789551b20916b032956d494c7ae828cf7ceed5a11baa01c4e573da9c6cedaacd1d2438166867956e3ffe847ddd7438cef02e4436d42c125a20f68fe85a54d9a	1	0	\\x000000010000000000800003ab933183bea5678c397d216a31a43ba7ac1bacab572b8686fbe1c2250a680369610338579af3afeadbf1f8bf190e6373a1ec76ec48f3252298d3207da31da0224c74c4ff4db0227772191d3b92a80666d03c4f74009b1fb9f097904b0965c188909bdf39538b582865d276f7e2561a5e1dd9048611e3b37cb32473a0c2ec693b010001	\\x780a6779836c47b52dce094d98bd690e3c45c5ab630dcb4c9483da3f6323b7c7b1b5aba2dd018f9949b4a4a5bcc1c36184b0fd80cf557dcc621513ea9577ad00	1688799748000000	1689404548000000	1752476548000000	1847084548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
152	\\x7b0d29f10049a73e2e0b3be972c9b13b28dfbfb28e792d628b903cb16128c116fd5c5151fb50c7c87fcd7681d71fe708b307d74953db9e6f87398014597322a1	1	0	\\x000000010000000000800003c9426b57ed1386acdb67c38ed4553d5d5e2316701fc12a0bac0fb7346c26db4346b43d50a81768b423db86f008f4e168c6dd75a8edea82298aa093ab33290d56e52bb8ac44c330139c28ee77df1273decff57e5d8a63c32ceb48bf865b445e7cf97847e7ed57b6a69531b7ccd3896da589f3a647e2cd27a568061a3d325155bb010001	\\x28e1ac93b9efb0e0f897ff943b528333fe7bf0ec97c7ef24fe262de3a7dfc7abf36dd8f119facd393106a406ef0c52d944a5d9c0f6beba0c74f5392bff7d9d05	1684568248000000	1685173048000000	1748245048000000	1842853048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x81151105381f6e3e1aff444197864c4a15b1d353ef83b10986c9bc1f5197bf5ec892588e6dad588b3cf7850846a206ab9d4940e25a5ece6aa308098ae445ba08	1	0	\\x000000010000000000800003c6ad46cbfb4646450fdda42503d8c6e3fdc88a15391d7992b1a1c01281076fbfdc85d8c83d31456f6e110e4ab2da6a1531893a0669850b15154ac5d0603a8408c72f3d4a0669eab5b0dfad7e68e47d6bbfea91201402676c0cbcec6bfb565afa4298e42f75482314f367f34929a16fae81893fa40a4a86dd7088083b73c0bd99010001	\\xfa7ab8c4c53697415da06c043a19328b1fb659378fb71f14ba0816c8121c98da77bba8bcac18c2a8ef555b538ec43586ea997afc413544adcf8b362368039605	1668246748000000	1668851548000000	1731923548000000	1826531548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x8121e4ff8c4a6af0f877e311d939d4f666763c7f291a01698329a037af409944e461472314996d4a1e0738682f102945f497b14dcba158561d58d433c87ce0f6	1	0	\\x000000010000000000800003b6895d840609960115d8c3b799157c8108cb88cd67ced3633c40da045ca293fab58eb73a4626b9f6050cc36e343de84cd6832f254342ba73f59ae025ea0a7dc3f3ae2552872aec5d59ddd7186ad90d3a6014fb9521899be5a0b73f232e229bca45da335db60589cbdc08beb73e9df3b707316f15547c260024ee554adb319315010001	\\x58b7037e2f7ea0bc8fd4f1221129fc30631b1dd1294ac7b01f04edc0c3941951ecc70754064a054fcb841ccea2bb27c9c4925a15c53c2f8adca812a96147fd05	1676709748000000	1677314548000000	1740386548000000	1834994548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x8499899fcfcaa77b7db3c7109da3cc7bca7545c891f40afa3de52871eebf5f3fd56c797a583eba8cc2142c607b5907946b00f6114e4c3b1bbca1ec8db1f15790	1	0	\\x000000010000000000800003bbfc2db931964ab232bc649a18dd1dcd8d991d2cc0afd4c9d0b086f092af4aa28ee0e14f5a9d8d289d8c0e6bd872793dfefc721effd669cc5636ebcbc3f6a6115e6b51725adda270bbc00c71115c12224ace5443458b17ae3b985aaf54b96c2ae119adc9dfe1cd4df95971b053a64443b4ecfda8685cb0fb1ee3c1268e38abb7010001	\\xbb9250e43dab0990da7dce002fb0e9439e5877f1418a7f47551a79948194019fd2a8735efd6cff0c1988fbad26b3ef387996db818598e3b3fde68a9ff8a2b303	1668246748000000	1668851548000000	1731923548000000	1826531548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
156	\\x84397112d15935584f0ed52e18564ead3bb9c7050d78a789ca22c38abca889cdd07bb050aa5cacab32063a0e439633a200724214bd3761043bac58c71970dd6c	1	0	\\x000000010000000000800003a8505fada25cfe41a0512fcd1b71fef9d2b308ac0480c4e0c5a34b8ede77cfbfead69c86810597c86c885c15d9d06921a3204e40b83a97679bc5f28a7968e9ffdc592504690a3b017f4a1e38b7dd0ebcc6f98b026d7e2e56ed5fc2c325d9c26898ec1785f6456c367d269e1451d0ba8ab2242ae32169918677026340e8d19f7d010001	\\xcfea78b75132daf69935f1374a192951e396491787fb349ec640c5ad81df108e1a149c4938197201c9c14f2dbd6b84c3a0493172c46e0671f98318bc462e4604	1663410748000000	1664015548000000	1727087548000000	1821695548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x8aa9b1672fafc91b8f8735861f504bcc14205cf65b17831f33104427a4ef8201e88415e3f26a2b8930865c52a3f42d8107ff07570e6c4fc0d79f2abaafb3173a	1	0	\\x000000010000000000800003c0b9bb187dee21b2e98e6fcd5da224ea75fdff2fb0c9e55f6bae549739990afc7e5dd98de320e704b8a44add8426732dc7a917e5edaf1c928c5be4e9052f5c760f18b8ac5132007a5666923b2b81c6caaf8c1d1dc45e31ad3565f6c144de8fd878f6315cd246d35e9eab65e1739adc3c10bacc2f91a18614e382c58e730b3987010001	\\xc66c06a9b933526329582b899f90a2f49a2d886c5fd82ac23e16571e3c47a521be7f8511553baefeab87300637f488838e6d6e151e862a57ae5296c952884904	1680941248000000	1681546048000000	1744618048000000	1839226048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
158	\\x8aa13f8f886bb554c6e1bed166d54995e40dd37cb80fb45dd78e167b2093a100b94be165ddfcc38788f525eeb38660f0caa9cdd14e50c031b2ad92f36f964681	1	0	\\x000000010000000000800003cd102eb59041710a91566b0240fb8ad6c81847851de1a4b4f10277a15e4040e5e0f91ac65f93b3488f3cc2d314d33c06e2f7c710bc3c9a3a6565c9f0dbcfa41a6dc94422b3ca83839deb6fba28c9d7dc87976697a3da4c9cd1a8170d163b9db2adcf0888d26c501620d6873d39a4b410d8d08911186c28eaac56a2909ce4c7f7010001	\\xc8be31d2c510155e3384ebcd1092d7b3be2e7cf13758d1c69434a0c93ae91a01ddbf94fbfb6f538713ccd3c870d8cd5e7da3be7bb709e530781aa6ba205e8d07	1681545748000000	1682150548000000	1745222548000000	1839830548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x8b0121bc2c05e954693e5964a82ba8df7a3b81c9f1beac88956b24f130d8812f2b3e80c16aa74868153198e2e12660793a69d6195735e5091aa650371e248a4e	1	0	\\x000000010000000000800003ba27489b6dfc1dc0786410b8f45e018223ef3282574bd1724968e4a4733adcdf8bd7822cde4f5f3824c4f3bca8135fb26a8624f01a94018f393c5ba33577963e14f2b545ea866c9d37034308f2739efb5c65e1109e6e8ee629a42218b6de8de0f981e0273466820484c38c9caf947ce9a87cdb82c9ad9c5939f7e0b0481bed33010001	\\xdf9e2ae8a20ad5b83dcb7be667ceb181396e951618ba1d3f0733f953713b662b1aef5991adfabdb02a972eb57404857e7bb34d709666399df55f4b63912c3401	1662806248000000	1663411048000000	1726483048000000	1821091048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x8ca943bd4fc6e34dae4b9ac54650aab7e7537644597c1dc8fd0a959a6c5437dbb28de2079fad6944959d1b88cf442abbfb3ed13dcab898cf7f2ac4d8b8da4aa0	1	0	\\x000000010000000000800003cd6887f58235338a355dff772482cc9890c3102f83b194f45b41a239e3b0548d39dab24a20ae8bdce6fd89b2c126ee21902bbb9577390da3202ed43732406cf3ca455eb34d34e0dbac8987bbc6f7ff590e88f7aacd6c54c58a7a8dbdbae3bbdb23e219ea1c3f19e88094af54d1629e8ba86e6aa800cf6ab8c275c089ac37036d010001	\\x020b2ede54ef4a3b5f2b708d2ca04c2643171c67b38fa349ff6a97ef0f4818724da61c8ebe91615d387574871e836ea627b169b5ed35721a8864998ca26c8b04	1662201748000000	1662806548000000	1725878548000000	1820486548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
161	\\x8c396ff4f47ed2e62cd7296f9624a486857cd7f0157ad3159ebddd44073656880a31f07224956168b8483173745e35affa40529847658c4fa7f26f2e9b56d982	1	0	\\x000000010000000000800003b48eb1371dea6955ef7e6a7f1b279e95ad98db542efe931d4be0056df6bb0f630b745279dbe904e3a59baf4f82de2a45e3cf74915b987ef64259fad1be11721d3ea58f64db751e58dc5f189038f57d25d07615e93af6d90683c34cb04df617216ed7343f7ef3a06edd309c5daf804ad3d57989739c30c6d6c814478c17853c11010001	\\xa866b0c2efe0ca4702d0685126e5d1d5ad89e15565f6546270a0ef6b44a58ff786f8294f8968cd263b8deea0dfd898c8555eb691c0f1f2db8d817bb0c5c48b08	1682150248000000	1682755048000000	1745827048000000	1840435048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
162	\\x8d45f76fe4ea00627cad0bf9cd5f59fcb1ccdeeed4d95e1e02b4727ec7d001dd0aca3a2639c77df434aca12cb924fd9261da5b9bcfb3abaf85378f800634d593	1	0	\\x000000010000000000800003a23fa0c01070f2133b08d0c254746546f5b56ad5d11fcb2fdff0e576402e5865ac840f232242c0c6ba291b1a73253a2a1005be1077ae4da2c7a524a9d7bd7d42a60ae8af113ff162cdfe5bdc785e3e621c7d258e65e2d59f2e7aa55ce79232eb15303b8af323f2f5c4ec2bca5b7370f66c7314148c709cf00ef495d35a51c1fb010001	\\xc12baa46137378e5e4cab3a62b5733ec49ef99e27c046f6b90f506217402b1a2ff6937a8a355da40398f34aaafdda383465534074c4bbf39e1ddef292968430d	1688799748000000	1689404548000000	1752476548000000	1847084548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x8e9d95fccd814ea88288c7d12cadf11787b105dfbbb3b0a8420b769ba9013ea48fd273a072be313914f5ff74bddfa6bf9e68c976cf7644d4ddd9522c3bc098fd	1	0	\\x000000010000000000800003c8583cc6361c3dc2611ce6ae2c8707a4e4d33322e9c722333b1ed12ea915620f91e870eafae9d7f3cc0253f08c42c867e953736e8e45b89e4a8365443490c176811595a0cef55f19e129050eb5c50c61f7525066bb59ff442bb593071360a71f1002968f4a2f805564d09f8734457595856bc09c81720d6bb98bb7568c493183010001	\\xf0ea85bc124be8763e2b08aba134cac373c1c29b20b009c3cfe23d50009d67b565d9617790d8cb58a86cb75127524b12c59e0915f828cc8a5a726c9403ca4b0f	1676105248000000	1676710048000000	1739782048000000	1834390048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
164	\\x8f5d20a9e67ecbfe42f2687f4c33e1bd5374132e794f435d0d75584de5facba481a51859321f1dbd2505f316d5341a56281aa9b527b56e6d8ba618a1b622c857	1	0	\\x000000010000000000800003c9b25500bbd111ac85e7537280bae2a6924381e5248bcf1fa914d368f8f6ee1b868f0957c2bc1c8ca625f243f9fa2eb8ee3bbec7d8fd7868747e2d76e3d219e58fcee2f28b13e239a62d5272b541a695d320437e404152fd133f0f0b72fe1a9c8e853c9a3c00b4b3c4b613b3c0e5bf3283c087137bb0e4b224c3968268367441010001	\\xa3a018ab6085be767d4617a19c777571b5dd9839b5cfc60250e492f009223009d6d72a645f78f90a002562d1a79657d199b352c94f9eb11e011563a7f07f4e09	1685172748000000	1685777548000000	1748849548000000	1843457548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
165	\\x8f3165fe45ac434293d9636a690e764246876f7f4d56c1835ab491835e86b5678f7a5cadab6ea7dc4208a4eff6af16b399ed7b0f3c56c32e6cafb95659e7412f	1	0	\\x000000010000000000800003c12c21a278aed3ea6148cdbc782bc8c91833f91bd4a73f0976e0f75e5a8ad9e2c2e9976cf4ff971343c690a354b84daa41659290c76a7a7a90d62238d416fed5d476143b5dc600e3f03c9f8b27df8bb900b7be708911b1889e3ea1a835a6babd27dadd70aae18af7f8df9a2bafe80de8f8101a6795300a87d371b3bdc0019767010001	\\xadecbd063cc4a9bcb34fb622ee8ac43a50244150f7a7858d9cf9c9a9763982f73b7fd7fb22cb42663258d759a70a14c84c2c7d3f5cef95b7708ebd18d7bb080f	1663410748000000	1664015548000000	1727087548000000	1821695548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
166	\\x8f5d36f184e6899fa187991c539514c44be7750e952422632392b8953a797d948cb0cbbd55742336438d7b9648e0525e4329f433b3343c808aee105463b285de	1	0	\\x000000010000000000800003e6ea6b8823ffb6c15e971d2089cffbc2332dc27c479e045d9f61265b0c5475f889b9c6cf80d2816bd275ef8ab09348d42bb761fa62645548ddaa9deb46131e5a76edb7555a4a9ff2aedcc98e78729aa6580379227d9381ab3abf831f6b9069c60e96009191c393657a1f2e64fe389c404efae2917d30c5d96b7d99f81a249a31010001	\\x72ec24d1893e2e00ce4e69bbfd81329eaeb3add6a18a4ca33bb994b41223acc7b2ef1ef9878b37313316c83b105944cb65a7d1052fffdebdb1371620fef0150b	1665828748000000	1666433548000000	1729505548000000	1824113548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x956d65315abfea2355673582dd443c1fc0e94027e9c9a34b623d336b7bb990c5c52cf2a9b8733f7c097421d07b46053a1d144c933f95717ab1af119b617a3606	1	0	\\x000000010000000000800003c04d8859778cb5e915596e5b3d88ac7f5b482f8f9cb20cab4c9301ee9a2506724f5c5c53d1e554e699884be4a1b5dbe5de7102de46f035f5e5439fa7d0684508f250e456fb5280c1ee2eda8599e6d7f40c83dd9e7eb421857371dd479d84b2abec2f6ee0c297c3a39af1fc164bb6f4dc356728a9055d2ef6adba5a62d4998e4f010001	\\xbcfb2401a2e542e6bc7dfa8f06cc6c536f447a26bdf15703bd3ab03308f023a486e0226640c311a9cdebf0f224f9c688148eb580c877258cf686d9b28c82820e	1669455748000000	1670060548000000	1733132548000000	1827740548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
168	\\x9909bf2544a733826404bff4ca18a8962c632ab4e101b9f0671038c570a7db1d484c1161115461c05642e80f40683f2af602f014026d8f08a7dc0d3fccfa68ff	1	0	\\x000000010000000000800003c20b4ba126ca08b781832bbc95259db782e510d64d05437370a417ceafa8b43c0553169bf74641a70116217a8e0d67473e5f1e88bb49d3276c5c7b61d11e75e12e96ebb8220cd87aeec4378b42eed5548224b50127dc701c6812a4ac9b975dff26148cb8ef0d712a0ff108767883a105baa5586e1c66752112c2c0ed00cf275f010001	\\x1546e9d9c1a9767947b689d92e658b0fbba79e911e4c4ec21de0318170bed034002a142b463598706e3d612929c9834c92e1105dc51c4ec9a6eacf50d48fd40e	1676105248000000	1676710048000000	1739782048000000	1834390048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
169	\\x9bc55cea6b008e6b524bf939a2788ae3a6583fefc1ad5d5b63d5e8bb486e88efa191526aaf26a495289df69999cc0c48d0fd94d010846d8571bdffad4c8ba712	1	0	\\x000000010000000000800003bb6c01b7d2f720eda8728fef5f2ac1e9472469e1a709151ba8b4358c793b4635d21de6cea3f75794ebbd886d70cf8979bf83857c86e41f0160b12eb9926af3654981e96dfa22b924867f3d240be244bc44405f816a80a2efdaa1fe15c4236aaf22db95a2fc53e9dee0719cf7301ffa9aa99c2495ab096c5ed7c3567393106e4d010001	\\xc624b0ff277346c302e4d2a317f0463c5ee7a84c7356ba3c7a2e9b75435025f5b0bdaf7c80066a04e5ca5d59b3fe571944ba3088c370049feb6582ba49280208	1683359248000000	1683964048000000	1747036048000000	1841644048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
170	\\x9e15171e997bcf52ff2cec081abdd1ba781de9467b6cbe94222c4b0022df1feccf57a0f2da2ed181f0a37964b3e48f89169fcd4293d3de2fb8d02f90223eb4a0	1	0	\\x0000000100000000008000039fa0416d846235076c951ddb1da09e5e7831aeb0f05a942f3935834b973ff3c2612da14523800933dfdd7da49787791e8bdc4b809c9f34cbc573cb8903dbbb6626f78e11934555265a948dd0b80df27fa596357ec9c6a6f258e146ac940360d96c9c1bb806c46edddec344ee00553f1ddc1c31808a18b84152cffaa4ae7630df010001	\\xf52187c5f413c720dff77f3fe97de884ce332519f1233ff7378b0bfd6c8240e9cb36275201ed2e580e1883f8f36ea8ff28c46cf5d463ca3dfd63129f4960f501	1671269248000000	1671874048000000	1734946048000000	1829554048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
171	\\xa42943eae9bbd285cb6000eee0ee809a40f537ec8a4c6cb4b624a97190bd046a3d57dbec92d6e5e4417660d68cdb92b09111c2b88fa98c21e05777dce7e84322	1	0	\\x000000010000000000800003a85a3339c22ad25b5d4b6810b7cdd91bbd67c0a6c4bdcfe5a48c55efbac4c88c3dc1dcb918b4d92d2c4c38385a155c9a6216cb7bb2ab9d745c8cb8f1dea0b4910094a6e94b7a556f2638c27bf3076b51344c704c5bf06c017c747ae3451b6fae0ed917edde244a79a50b33acc4b0a777bcfd054a8acaa254107505419fd31d41010001	\\x51c9f62854cf984f76e92fc24c740cbf7e46eec3aa124beee607261de1de990067b9cfe03370b6e82878a105c9b9e93c3727477b466c211b00640879bf14f10e	1671873748000000	1672478548000000	1735550548000000	1830158548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\xa525cb463d710953b934770c024dca8c4ea22dcb9f1fc5a29113778e1fca7078693205149ed941893866287db3ae53d38e763783608fbd43a676c1c568a8c423	1	0	\\x000000010000000000800003e431cd2308658218cc37ccdcbc19f9d4767a389f219e685c842430b26be34ecd1b39b9bc8a0b11a1d76f08bbac69fbce476e1db088f48cb220dff1b8d275a0a3ab013a61917bc82f6bbd51013ea9c9142c1b23beb5d394ba3cfac652a9602483d0700ce0a6e7e09aeb7d895e3b0f61e9a8d6cd5200cb875a43b68ffb40ec1255010001	\\x8a8be71061db948b6ee2e399d8beb3ca1a6c0c87ab9541c1a42c1ccd69227e1436d8addb1d1373f7093378d1afd1aecd0fe033bd61b271176819510305ae3a0a	1677918748000000	1678523548000000	1741595548000000	1836203548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\xa6d947bddc3f1a48052dbc90b7b90667cc6cbaa52f8fbed6431f45b8a98ad816ba31c5d2b4da73943762cb2473fff5f0d016c496dd45470350c4b251f3f7c8dc	1	0	\\x000000010000000000800003d3b0fe39fc0e891e86da34ec0d4f74b68a632168ab7d6d21797c1c2701b401630b0bbb8e5522c566bdf574039fb62546bd6c2e712eff179887a39e5c203f8efa9c79217f429ae97a0a99fc4e69b7e3438e800807f941e98e45362571962ffb3a5543e4fe1a37b05e2ae9416c3fd011136497be1bf5b877083a940db51dc5ff51010001	\\x7016c0768621078f4baa9a13ee566ece2d4bf0b4cf720732190ed4b0571f9d74b43f0e905760a8ec65dfd9aa8dfe2562ef77966c9ee1baa25f393f0ba9347007	1670060248000000	1670665048000000	1733737048000000	1828345048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\xa7e11ba1362d34926228028a5ff78e2876ae67f476363e9f9a1e19e2f1af62e25446684fc8f3906207568b76ed335039c50b05f7506b26832081ab8f00c6f7c7	1	0	\\x000000010000000000800003dcef1e26d25a9c6addbb7f64af4c9ebffb198e453d7a074bc8edaf62afac04cd925b6f5feca37d1f923816e081321219b54e65267d17fc66cbf9c0da98ef2e80776ce4b9af4da34084afc476b1b7a8ef1f426e7364cf57bd61b0d0812ebe8346c7b5ee2e245895cc244ca209bebb226f13493d6c1002d0a105fc297d4efc0569010001	\\x65fe093965e7af8043ce0f06180ce4e12d89d8d2c8988f3cd62630ace76922688243dc603c3fc12fc1bb89778eed25c34ebaf52842863a4b5734ddfaf35e9b07	1662806248000000	1663411048000000	1726483048000000	1821091048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
175	\\xac49a94fe027967aae4eda7fc2b572eac0732d514cced4a53e9655bf5a6e138b638fa61c9c70436e041c58c388b6e2eba8fd3a4a0b14ada8628fe18336bdfa94	1	0	\\x000000010000000000800003d2f8fe1285d44542b3077ad64297c2c4d7e595f99d4655634a2998e67cbb224192613bec463a01dc5e3065e0a7db40ae1ad9ca17de38edbff4724a4afcc07e58719111d63ae959a78c98eb4603d0fa20edd726868cad1d2a724845e83bf6c939707bf8aa4af6b3697ebc590ee509bebc4260a5612659bfbbf1dd08fda558f241010001	\\xcef09c560585be86d4fb0dd099eeee3ac10250773c87420a32707aca929557301a7cbbe64dec7eff23f2e5b4e632838deee7ba0ccc510a1476c37680d4dff00a	1674896248000000	1675501048000000	1738573048000000	1833181048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\xacada86a93aad39b26ec59241d480a88492dc024d404baadc99a2b4597ce2739859c7d57835a7b491cb6fdec2334f4a49fcd4c38cdb3ac28dd15afde832c8b07	1	0	\\x000000010000000000800003ce7e1735fcc74d96722623eff3caecc0ab85823b6b5434b4ae19d550ec2c50987bfc790a7597763bf322c4d179beeb95d408acefd7ec5433b4a056680d31c5ef0e1a7a71e253585c4af3cefe87b278c8b395bb063868056466ed78b3dfdc2f3e28491eb80314ce7e316df071466e391ae0d4a6fd2b3362c077912cf19f841495010001	\\xa448973a81ea0543ab80b051deb5e35288e7db154fb3dec24d75998caa6f9eda6e19ef5545e6225ee30ccdb99d390614fb29979198e6f81f95124d2f2f7b090f	1686986248000000	1687591048000000	1750663048000000	1845271048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\xad09f83907fcc05eed07b87d51e218703b81ba7511c24ee09f099be3e5abe4f7c236c3f82b73acf5e6391ab1891d62c1b2e714478a4f76d15e0a44a681cebc4b	1	0	\\x000000010000000000800003c75be97d7ba2467c4308c3e95ae2c309e1ea83ee289a43bf483950b118dad456646c0abcfff0796089387d6246b0a74086857ecb43232cebf19a662c12e29f4a8ec4301fb7f6db1b75df73ccb6cef0649edf646f21ff6c123b366da30fabc03981a62099cdd0c3ea6fd57f0ceb6549d2c7859f9fd9d6b1f21b56c2eb40ecb6c7010001	\\x404f963ef79b0852a99cca561b690371ebe1ae45e1a0fc349cdbbe302141160cfd490a24bf6fcfc91f4870bd045e5840d072d9f800ff18d7aab076792dee0f0e	1669455748000000	1670060548000000	1733132548000000	1827740548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xae9900464514d9f933fc0a203d2d51a00ecb9ee8c7551bd3e6afa5420a24d53349a68af963f1a670e0a39ed8eb26a90b131768788cc41338021f51717a20a139	1	0	\\x000000010000000000800003d1971e2b2fbfef033fa8e57266e7c455a7a618980afb96093834fd90cda0c5cd4df2000215c7d9788e4e4d4d3da8af1ea0223aa691ca025122e729bc0ff00b37c49c97bd60356deb3bd4bbebde454f7253ef4b68de014d5b3ae40a04ffb439df291c9f8998aa87a9aa1f04e5c1270a4f7caf28f425c058b007f71cdd5db1cf11010001	\\x3ffdb27e6e61113f046bb29aba94e2ce504f60f09ab94e4302f23061e1f50907859593e1100715bc6cb5f8e7cda3027e7897d907b6d7fb5a251c247e0e81e50e	1660992748000000	1661597548000000	1724669548000000	1819277548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\xb2c55ca41c949b57cea14f3635210524840369fe3f9fb8bd085d1ad8298b75be949975b9d5fe4b40196ae448b8b5cc33a687aa457f8ea94ad181d1aed462a542	1	0	\\x000000010000000000800003aef45522dc6ebc961a110de1c1f227bc5bfc5bc0cbe38e404ecdb19f27cb2076fc840b4a5037f6f30a1217794c3fa01375ee8fbcd7c12495be4be20e9191964cf7ff42a8e9c3892b67fe0b3cdaa84ddfb317d9fd498c594ce96fadf66d2901f3c0cdc79a74ed34563bcf591e01f62874b29e5819d89318eb6db9c75971139e1f010001	\\xdd310585d394827882bb41f40dae6df3388dc6c2f358917625a59161c3ad7b68c7a38df93b4b350695728ac300fc7a129be9d2c0bb0354f346de4c5338b9100c	1686986248000000	1687591048000000	1750663048000000	1845271048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
180	\\xb641fbdb253abe9c701e17a1795394157eca6a995e5f7ef31006aca3b0fda76ed017334e12cc238f5fc52017047f3c3a6e0a012bb498ec716bfad295e8a292dd	1	0	\\x000000010000000000800003b53f7eb7678f08abd3a07e50063948bebbf1b44b62c392bc46f30b13e956f98fbaa449d834b5fade5fa4de7634ac7e8f55f90e39b049b2318653229094cdb6492df5b4e550a8c4c79aedfaba02813ccd34086ac2507e7d27c036d7e4ebb84ff8a8551c7b6aa83552425afc627ed7b30f68e334ddb04af348a61e39fe51d99ee9010001	\\x1442909966a375353b209df43fecdc262f1e6c0e3e395af6218abc0617712a68adbf321bd6a592d31af17ff54c8439fbdb449f88eea75ee0a74c893dfaedc409	1673082748000000	1673687548000000	1736759548000000	1831367548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xb9d5da8243052c1e5e5927838e5a74ec71bec7324936fddc62f4d7cc84f4c2f960c1de8638e1c0d5b642b99860c0f2e9417711131bafa7bb791d84f3b09784c7	1	0	\\x000000010000000000800003cc1d73257e9c7decb69bd22335bd7f79116b6fc979d4a50ec7494646f67253cb51a7224be960a988414e1c759369dd61deac45c6ee6ec771a7ee90be0b9ed836dd641bf144df1865379910c7d43a084f82af9335345c4e386c83952aa07a6072dd752c187b8a1dea933e78a0af83cf2b9889ae2149d2321f8a05af30499a8c83010001	\\x192acd1c4be79710c557e836776f422ce309b8453e84becf860a7fae1b4a924efc380278c7199bfa08fe08b696b10c9a249cc8d4270c87b448e2fb929a25ee04	1676105248000000	1676710048000000	1739782048000000	1834390048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xc5e5195ed81da7471611e77478693a550a8d53b6ba44988d2c3d309e4360ce129ee03816ee9d2881e4283b1481a3b8dd84f94dda89e728dcd44ece2c91f2d22a	1	0	\\x000000010000000000800003c5dadcbc6724652b7843d37f4ad7a759468b3eabd1e6c4c70441252f8b91b451e094739217ff87759e16cc594ca4c9cef4b7282fdd975be7424cb297e484665486947ae40c4558ac6ff81ae9c1ce5a0e9a4ef1f43e4c0e7280a440ff63f45a5371c41a10d9fd2f3f2b70b543ec3f3cb9e8e0583db6a607f2f94ca681b3dd8d8f010001	\\x9606745ebba338676fce32c9eeeb598acc3fc40e6c23657831902a3ab6b5bd652c6c895405c50ceae40043058cdbdd9683f3753ff9029720d3ca70484e004b08	1687590748000000	1688195548000000	1751267548000000	1845875548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xcce9fb3d298e53af8350a55a38eae4c5ffb8d9d5c204b1e01467384dafa5d766cbf02abd1dd919998b5d571e2c81ec0819321ff719856d637227e7816aeb7ea5	1	0	\\x000000010000000000800003e2b9757b622a2d862607483a5d7b82560ff43bcaef71539d7d41184c0ce4a1e1b49b1c113e784fcde4e79726928ec455b63d196a982c1f17cb3ea73f51e33227a736deb01ca5a2921959b8cd9d2bab798ddb1f7f6b12769fcff2855b77845ecb0f94d83b82ebf3392c02dd5d02ccb02266baca62c53f5a67dbdf93cce245fb61010001	\\xcb3219201a5f0958cddc2225d87c2aa6d562f267b5da8506edb5d05f88cb2fb86d9db1a8e0f28667c93365dfef4e22818d4e47f8823258c92b91872d1160ea04	1683359248000000	1683964048000000	1747036048000000	1841644048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xcfb5d2fad7c039330ff6850fd38d8225e619a1e1618534151be6b85f61cc6112bf2eabd27bd6ef49c053ad6a8a9a3f55f88c1e82c2bb916ca8e91089feb14237	1	0	\\x000000010000000000800003b72dc3c879a515eaf061c141f047f1b6eb3b00e59e86a22619167c2106216c22000b3085c05a1e006c67db88cdd7bd9d6c2839a335801df96a750adc5886a308a462c38504eda1675854c57952d69cdace1ad6ef5651cb3a6ad4ad6370b322201093481f47d6584f61c0fa41d5b1be2ce22ead9ad25d6ca5f0812f42be60c107010001	\\x0ef1c7fdd51332de22c9a0b6254bdd63d9c963cda38b8b02fb9d81cd780b86d8cb363c57ad33665cdaaae6bc8d8a4cb08291b02011a3fb9e7b358071ca3ab202	1674896248000000	1675501048000000	1738573048000000	1833181048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
185	\\xd2b133809282e0c42e6c938a844be51a98f768ce39506877d9b221eb8dbe83b6eb2829986942ddd15f667753d669acdd00c16180c06504bd097308c7be3b8d51	1	0	\\x000000010000000000800003b1e59aeb445191d62beddfa5c1bdf757a7bd50422f0223bd65c5f187223ece38d5de26c7fdfa7f5e45c34d3eb172786f48ae24aadabcc308d93e139ad0b73e3b72c9c7de23559c5bc07b33cade1c13eb7e7695b77cbb04bd45672477b0d6bff37fba256b1d98989f830b0e4cb1c68a8859b09cf7bbd528731f29fc9e5b4d796b010001	\\x8654fc76cf6333788f49b6147d4b00e1b53b5a4db48a0c17fc9a74ce9aad2d26404de1fc6998fee554a9c103a896c88d029028bb3e3ed8ffb75c9a9da409e705	1668851248000000	1669456048000000	1732528048000000	1827136048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xd44d3b73c427c622498872e7354498a2217ddfa4c726e163d4585c3fb585b57c6975afa39d7f7c52dab245ee65d3fd423ff822d291086ff957ea5397da40eb30	1	0	\\x000000010000000000800003ea5111733a2dad3fcfc818bb7eec05d55977ec309c0c89ed83148aacd0986951b20957bffe8266a84c22c4983f09540544994d7c6043a909e29ae64d62e6b1c6255243d11f1cc5d303568e9a09ff92652c97184b47810f577025e19c2c1f1dcba42edba261d88a44a9d61c9a32a87825ec7724fdbcfe0651b022a32a42b0f6ff010001	\\xd61cf25e7c1352326ea14b445dc0e4f4538f33720379e373afcaa80e6113b53c33c41a4f7a312734f733ee1d05d305ffe929a8ac8faa3ebbf03e5c8a0b3ef400	1690613248000000	1691218048000000	1754290048000000	1848898048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xd7e1d9f77455a470da671f32bd9d2eb7372d6274bcb287b86c51b12b0e3c80eaa223b519497295134538c32e316bb7122e27b66241ba2d169189b596c9905cdf	1	0	\\x000000010000000000800003c8a8cbe1483a2c1f107259f6544e35642d2517ccea57ee56c90c54f54f776935eed3692b97dbda2e24de8b1c9d886af4469d0b09b39022e417a3569c70ec0c7bfa3973664148f63bde504e5024812db4c0bd5057df82a897b90e559a389ba3ad898cd9dd46cb8a769475992c6093ef804c5a10a42d434d8d383ef6140fc5121d010001	\\xfb545852de59a5dcd7f8af5f139ca49b3c3271c8e09011838f502a26dc7947bfb2b2b49d6c6e3754a75404f2f7078c9ce715b1e3c854da13274bb4d14affdb07	1670664748000000	1671269548000000	1734341548000000	1828949548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xdb854e908ccdaf311de813b15f7e2e3fc5ac2f5131f3d79c4c6acf225406d47dd23e947e5e027b951eca119173b01320d429940c7b9df242403446c03758e4e5	1	0	\\x000000010000000000800003cc74110e86d27ca4da08baa39a5b6b04f759258323d30cf4fd1bb993317879817d000a43c94c33172c7dcc638781f2e84d8a44a756adfa74f8b0027de281bac91d9a4b74c60fce79ab7a752a14e8ec0def60357fe209828f72e32d03d6d6508184b29f5bc4cd96f5bab7c51a23fc11dd1b9d90b32f949e894ef6a92b1262920b010001	\\x36a8cb872d9f652666a8eb04f78d9e2e38ff9e8c75a29fc112895d008fde8ccdda43d93c2b58f3e86dcb3cd2349094e018e55b892f1e76b071fafc1bf6cf4709	1677918748000000	1678523548000000	1741595548000000	1836203548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xdd85c1d37d68d63fbfc5552633564b65bcf56ddc8a5941bc17b4dc4ae9cdc30c37b98df9555f2387f3dbdfbfae26a70b9485bd0667703b66b4b80e975742da98	1	0	\\x000000010000000000800003e9898a802e9694353acb9382beb68f814c5cbadce02be9935206b605fc79c2ac203fd1c3ca2e841f7fe4b12a184b8035893ccb51be8a721f27c217210a10f5af9f4b9a753da1372b721379db01279734bae83f824f32b333217e15164664fa1c29f8effabf9c1bb917d64d1b282a3b6195dadf31c7c74ef7ecab955d1c4b926b010001	\\x3d7190de85bda42b8a3f4614cfd2fcf7727dd7bb4610aa71417b2562a89be88a0cb8631bfab6b4f1a4f2a5fc18b0a66133c8d5ada73e2b5d76b28ecdcd08c200	1685777248000000	1686382048000000	1749454048000000	1844062048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xdee9530d7b1b593fb7f210f4e91e0148b3edec0ae42302215850a4bb65202725d90ef66dc96102119ac56bf3fb4294d458700afd9f79be5c05af120b0f0b8595	1	0	\\x000000010000000000800003e29c0720a3259524073da2d37960909e2a703e5c769151b87703ee6cd229d12ad803a822c18533216d1ee6fc92b28c53bbf0238b7ba4661eb735a1e0fb90c6f772a43a7fac35f0080786a869a06b04a1bcc39f7dbd37ecba3eba9bb15b7f903e3daeb134051030a1e5497eac30ba75e8094e967544a172bab59591f4081daf6f010001	\\x44cc345f33bb47ff818574b416a35d0e02385e851f9e3f0abcb6773b50a5cca989e275174310f2eb52eadc1ae34437f47d0d412b9b6d8de0b61ae8e55f0e2f0a	1675500748000000	1676105548000000	1739177548000000	1833785548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
191	\\xe475799ef8add194c37585c306805b92df86101bdbf5d24dad452baf01358782e6d2818cf1cac9655fdfcf5a146bcdaaa6ca2ed20ed412dd6a2de24b3d6120ec	1	0	\\x000000010000000000800003aeee997e8c1b83854f834db34038677ed5a93977da721ff13b82003ffefbe953b520800021ea7065ab067b15fac76e0b92ccf84ada82d8e4559a1030f22f2a00228687e29ac951a2455aa0ebea066dbf2492ec5671636b8db68340b0eedec7fd8e587539245e8ea083fb033057ea73696373992249652aa3e2d5e3e8cb18cdb5010001	\\xae00bd670cb24a97aecb08ccc202c1550f2f39c6bf2613420eb6bd6d73aec4dba111f69ad968d68cff5ca0460eec416100a8e20b17904dcafa0ca0ff1eaa690e	1675500748000000	1676105548000000	1739177548000000	1833785548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xe4b15541297b8228f1927ed6254eed95f9c791b02621ccab933edeb9c193b5117887047f64b1165fbb3762cbe161a8e80c611045423c7b62c6ba98c100e842b1	1	0	\\x000000010000000000800003b7f01b38eb5f230ed04d7f2ee9bc3b5f150ee5e856172e1d0c102c33822ba93eabd705bdf79c43ea5fb88b361970ead17299b22f4f9314751fd750159f38cddd539d4b73cd04366888ea5dbbcdbb3eb4f75be6952362a10aa36ed22109933d277d3de7f88f7e95210d1f2be302212cb86afcf67ba4fe49faf69322f312db3c11010001	\\x4a33f5a29f9e38e2c287f29a6c1ec166362203bbd88e79a3d6adda76f897a5e928c3dfd3f677944cc96f8fd6d7e1fbce39ba5687ee8d9dc580e7eb5c989c3801	1668851248000000	1669456048000000	1732528048000000	1827136048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
193	\\xe9d987ed892c0622015b55f9aec1e25a5fd2820c029811de08e6a56bbcaf3c4505c5c20f8d09701f2ed3f27b208c30d951d62601e2c724fd93f967773d188002	1	0	\\x000000010000000000800003c8e28a9904fa54672b771007277e6c912f3bc2d4a7293e9702ba75cc8edbda7ad6c7d2fb29ea31b6d390bad610dfee6aa953a1ceddd7954a7b35d78640316fd44e1539d441164bd10cd50b348fd36ebf89d0687bc17d383fca9616fedfc72628245b82a30e97fdf3eaf9c12179ebbe0f28d747458edab94227aee5f336f2310b010001	\\xbd7251cfb9596c6ce1ea15b32c9f30eef364d5f00ce85abf85c9b8b582d8cb0db3226dc0305ab99eb19516e15cdb8939dccdd6c6fa4c43909b0c3fa553c27504	1683359248000000	1683964048000000	1747036048000000	1841644048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xefdd8cd7eeccb0c4069fc6cec956b72213863448f055faa6163e9ebf2e4f01ae8d4f41e0ed4361cebe538a82dd560365192ca41ef43e5867dc50345f6e833fd4	1	0	\\x000000010000000000800003beec248a7d12def70e1bfc57031109a00ac2cbf66c1029690e56395f4faa9c727b6fcbfac80bedd77ff0cd6bfab486c53a93dd896d6fadeeba9b1ca838e4b842a98a439b69a30dc1c1af004e8309c695b98a76cef02a4b2cb3608e5a504650b9ad383f2f04222cab1aa46f5217ae21a3ebd7107c6fb21692bc9e98444b2bf5ad010001	\\xde40e5f59b09bae8018a3d8c6120610100695012a346d27a149dbe78bb20a54e92f0c605b3cd0264bd56013d1f05f359df02a8c3142938e7b0d5dc3f9aa6e30c	1679127748000000	1679732548000000	1742804548000000	1837412548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
195	\\xefc1d7374c3bc293eeac88910d669f5b49a013c7722931dc026175ef72a38250f93797171d89c6b8d9da47f0afac3afb814c8a78d75f36ad1e3eefd2b1e09152	1	0	\\x000000010000000000800003e1ccc50bcb9b3d8fd6ff881a338afd560593275f211ed53336c1326f89de234482d12b44dbdb043017888ba4ae84cb44ddafc07628ab1365817d32ab76c985a7612a8b713c225668826a6f883b251f8e9b1a434ebd407a391aa0e76723965abd26f036741121d6ea843b82fc08730e493ebb8d4354fbadde1ee9ef343b1121cb010001	\\x75fa06dd9e93b30d168f7eda8df6ca05d022102b43cf497709e06d78b3c6ac06ff4fc16c96c5e431d936b974ae2af17cf226750b0916b92b3c16cc74f06ffa03	1688195248000000	1688800048000000	1751872048000000	1846480048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
196	\\xf0bdbac4e52ee4ecdfac017d27dd3786e0699f89db7370f2baca59740684b0098ee95d1e139ee031263e69347ea12c0921c2feeb75b0674941d2bd7ac299a7aa	1	0	\\x000000010000000000800003c8da254130051e2bc79b78468206c1a010ff5786ac239df4d3eab5409b21fc2581d4bf62dd627671bde1381efe5f8c46881fcafc4f3cecdb908a9b629b51dab0463eeae98f52fa261b40ed60927db536dc557e46cb053a1db60027ffebcd8c5237d6157dc4765065f2373a271ca16fa0f61bca2d82fac240d16b03e56b2cae6f010001	\\x247dc137e624d078e2d0e096ad8053ba6bdd87a4942cfe58da4e40dca8dbfb6986f262b3fa3de9e9b3877ec58f038fa92665da95685b12cd025578c4f93aba07	1676105248000000	1676710048000000	1739782048000000	1834390048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xf0091536c62e924d8a73c67b1462ca7e1c8c20c080e3b65e4a5e3d136d6a87d092091145f4fb3ab37243992e16eceb4e1500d0107ec18e6cf2f0e11256f83938	1	0	\\x000000010000000000800003d91cc8992e7af696afae9b23eb13a380364f790379d8d82f0c57bd768e5c44efb6958e1ade2659750f63a2c16322ce94c9b934c9824acf193082598da50b7959eeef70f8f99f175e67a9e4cab228fafeba4249e0791a14fc0a5d1eab0485d6f86d9d193de903ac398510939f8e71b5e355446132c505946f4d2b2f0aa4166c43010001	\\x9e111f41638411eff765e3c4b4a29887a0f5f0f4f5091eb9ce33b5b487a65963ef9c6ac32def75f36b1a239064c6632a28629c585c8807aed2459213f99b570e	1679732248000000	1680337048000000	1743409048000000	1838017048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xf01d4e16394b5d917354d8037170a24c2b499be92e7f1cf5c73b4326d5ca2ada61753825dc865fd4790636440d188e3ad3a7bf9c8ecf02f1d1f726d01d8864a8	1	0	\\x000000010000000000800003bc257c79aed62b7b9b963da6dc8b62d8be5cf7885ce9b3d7e47fd5d79c554708b9cef0b5dc6fa3e23f431debe8d361cb42546f00f69695676a692e4d09c01dad10ffb4039b30bc4a7d8772d667c280a8a0bbe59a8228c67e7e9b0fe7382b44cf89cea74a46da2c5246e3c70a58c270a650a535b30d6eaeffb47c7d17fcdd0cf5010001	\\xd1f50e66f4d2b36e39507da421be59a3cc02a394d6b147b704f5213bc60510ebd81bc4eeaaae19376ae1f0910f6903e19f79d55b24f0200cc0a763bd092de605	1676105248000000	1676710048000000	1739782048000000	1834390048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
199	\\xf5f53f522fcfb0d3ce0c694954de08e0fdb90f3f2d870a0f156e756519907ff82fa7e2ea0b8a7a07cf7b1e5969612857726cec0fd0dd1695f1bc6360d8a8cc40	1	0	\\x000000010000000000800003a96eb088962fb9347946415e48d2db48e71157d8c1330f2f458df110ef66a8997f46005ab0722b6d34f9b1a196108c152030086e51babb7c01bf0f191a7cf2edbf2ba9baadbdd512df790ef4dabc96652fb8faf00c41f3ad3b181817754cfd7419cc72c5ba1cc0d353e6044903bb3ee5a5c51b020db8c394f10c06027bfaf587010001	\\x991fe8dd02fb541fbd6f10ac53c4a1783ff65b3dcf489f3fbeddb60db3286c88781df5a0dcd390348f220b2633c7d3c50c6e739b0c9f92a0def641241249410b	1677918748000000	1678523548000000	1741595548000000	1836203548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xfacdb3a93e1655dbf1904f3b7ebce14aacec8cfda011dd5150b03582e97ecc57a50cce7ef2b6741bf25d72fbeba97314ec94fc3ce09ccfb0ae38f73a5235130e	1	0	\\x000000010000000000800003b06cfba18645079a068a71356a6c1be4f29b5f616d43ba9c62494c0a5975d76c47581f01595853aadb201d0e225a781bfbe80ce0b5e9626d540183627d745d53aadda26241e086d8c326914d112e7a7872c491d9cab0b956c9b1b4875965e8d1106efb3a5fb5098050b27b149585c1a1b5a4e94bc47c50a3c60999b63c511247010001	\\x3212a6be11d9cbf49a6f0bf23b88ac22f81cee7ab2116fa05608a12e339df2eec6d194df498b244e87846a0c7b411a23cf121675502683638063f538f1749400	1675500748000000	1676105548000000	1739177548000000	1833785548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xfb15e11a397d1c20ba8eec5b7d9729f3947e72c3d958b009b8b7c5e5121e4eb39ec7a25687aaf352cac8a9096901abe3e9c0d77b7aaea5b7eb3bb81fc4578bee	1	0	\\x000000010000000000800003d1acad7b8c9c68f1f37ff2325f20db6f9217293232755205146eecbc70237a4ed8847d1f5233f89f91a2f62c756daeb46363d8a951683a1a550ba814d4919b124464e27c5e1d4a11c3d1c68e5fa07cdcb2c616e18d5f9fbcc8b48804d4c33db8ccbfadb10591ab2e7ae3eed6f9b0378f29cdc884f4a85fb5d583ba015efb1b55010001	\\x6bbc04a97fe1731480e281b43db93eb21397f09db334b80bf2d9bc4d8f8ddeed8c3532a0c76b19df1b08a03c32485f4f7214a87ca2f3ec904a19fcf3a50e4308	1688195248000000	1688800048000000	1751872048000000	1846480048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
202	\\x02ea283f23aa6b1dcf322735159ab494af769437908d5a5f5c71bb17b092e0ac119ea3e6a4c84814e3d5e64fc1cbd0d7b8a2c065e56ca15ebc6a5f5be8ffd428	1	0	\\x000000010000000000800003bdc3f57adffdb7c8ae28f272a47a1494cfb276e6b1830b1c1fede37e8bb1f2c78032ad3f3279157ad218ac2bbfecdfa5a397b49c12e444ad02bc91f53fde9df0d9a727cec726bdc71ca4741cfbc9f5ef0b2bd23c6dde55d86de04f345607cdeee4c524eb4d915626703a5c7420ef800b7a7d6a88650f6b100970f8a52f559c77010001	\\xf95e294ab7731af30ef74218824a995bf2062489021d1f2bee8e36f58a45269fadf79288a118f201ab629dae48f17e9bb7414280134899ff2347ab811dafce0f	1664619748000000	1665224548000000	1728296548000000	1822904548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
203	\\x043ea2248492539fa7c34dc7930de6774b380486caf138141e3e4ec20275985d7f168f85cd6ea367993824d60b668e81fe3d011f0ed1b1029154181cb5180d94	1	0	\\x000000010000000000800003cc50eec936dc9f53d8c7aa9fa98285a22e3fe2c14ac10c920a9ba8a9b9d8005d3b97e060f2208809ae7925305250809ef72a0d4ba99b553a81b376004f4bd0745cb519f805b482863e31f2a757858636fab7381c72581b179527ab2c6b62cff020d244a4273b215f07c661c26d681db6655ae82c89b3d7b026e3e9bf4994f0d9010001	\\x6fae87ab3f16db020fc82dfb4766cc95399bd27fd71f1730f57f84503188526fbefa4dd5dcf53fb78ec1b7430b52266d584aba133e534dc7b45f350f406b5f0c	1692426748000000	1693031548000000	1756103548000000	1850711548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\x0516d189056a4331eae07b86096bcff59f32edf22c43092c6d8eeeb28ecb1c8a9e6cfb8e030f379da85cb62acffd560aa6582548da11523b69d45b2ae9750ae4	1	0	\\x000000010000000000800003b049928b6d7c3acbd84dbcd8bc8307a55dedf34288810fcb0d6c19a58eece3a7aa1df82ba80373e12003b410c48224860a7359214f1ff2bb45d6394020975c75b3491ce57cfa24a2f800f6a3b3866e33e2488b12ea52d8eab24979d38dbf290aeeee7ec6fcf9cc6ba7bdaa969f13d0f91392b3692d2713f97df44f8898c16b53010001	\\x68f4b8b07d73debbf380dc0ae68c57c3adb479397e1ec70e8d3f1b1ea2594f2a2523767b5fb92b0398c1068ce6d73635fb8d6292cc1a4dc91af50dcbfa2d9a05	1685172748000000	1685777548000000	1748849548000000	1843457548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\x079232326eea7ac0bab1ea6ec4b741babcf8e12a40ff6e2433a1d37b756ea74848b174114550640e6fce6bfbba9c250ed948e0d5d8889d78d066179e0f227b39	1	0	\\x000000010000000000800003ab3e5dcb9c58ba308f61cc02659e31279663b9d7a24ad9f1c588f5c38e2d56cfe89180fb549992f905880b0b03aea5545331d9126e9ee250b533ba67132b81d59fe011bcc91bbee073e426bc7ff5566f11db5416f19e62c16a10446c68e6556980ed18ef1f50c225a0d73d31cadb448c3a4a5eff94f26a848805de23bad7b401010001	\\x9b80b0ba067a495a77e904ed89d308a934d380f7832332ce5b54e715526b501618fff1fcce75a53cfdf8690ab36fb4cad4669522ffa1f2638cdd73198634ff02	1664619748000000	1665224548000000	1728296548000000	1822904548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\x0a3e2f864e124371028814dd215ce0fa96545f03e0dd705c2bb894dcc9db6a285d6b9397b7f9b09e8c8fa9edc7040b66f6bc7465de78f0c9c2f044d3ba440893	1	0	\\x000000010000000000800003ba75aa8dcb88fc82d93466117a32acd31350f43cd910fdd6d872eb7bed4ea9db42d4c4c05c0014cd8bdf952568af2312dd0ab09c235beb7054d93dd5aada67e1b9c0a2ef5784dc7a012c34d48bc008fea75295d0ad0695f0690cae83e0b8427cf7ac14076584070b81bb1a2591c0bc3e6145cbec269182f57d7e9431dbd1404f010001	\\x4e59d73656505636cade5f9391275fa1a82238bd834799b8cd73f3393a269a739396371c1f8e3dd5b7a8592c97ff33aef9748d3299a76af2b49d0f10f950820c	1662201748000000	1662806548000000	1725878548000000	1820486548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
207	\\x0a9ec22e639d7ecc12cc90656d16d67277df8e5628d19c21a07ccbd64d061cdec958ab97b4a176ed0cc45fb4cbf57c5ba729d4a3220242a2c4238734da3888ad	1	0	\\x000000010000000000800003d7fd483a27c86d107c630c2b17eba28d647949d0103373a9eb7f0219bdc356a865279a2877a8070c4d897c6a83c94c653d0656ca585f6c6309a88a61e9adf7657753ff4f18fc464b07fd227fb9edae2c7f22febd745c59eb02790282ba0887c96396792b68f6f4f9e6122dcf41f9b6884010084b2f817aa9c9ae5d3d37352157010001	\\xce5971df888d3e1673e2ba8d1558eef4927b6ba6d5f007393b02ffc3fec9def3b57bd95410d54197395b7f6a2e5616010ff46ea5024457a96cde046f3b8b5209	1688195248000000	1688800048000000	1751872048000000	1846480048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\x0b4a1ee573b98afb68039b2bed281a2d086b6fdd1bd9760cc8c730e02c3aeaa1a942cd8bf5a802be0c9670adb818e6b209b383907e84d61a98563d82f781c54c	1	0	\\x000000010000000000800003bff69ad3ed365f611094fecce73fe185001d73b00b44a6578d9a3ad9f5f7433e4ea2d625fa38b732a3fb6934d0ba2c75aa6bd0e01c6dfa1a2dc87d811079a65f5b3e79300899e7c574023506b46f7fa24d2d7f0d3ee4f68e3466a8fe9a759fc8ff4ecdcaf3adb3d2bdc2e6a53864d588c18fb410c08c73b0d702a34bc98ef989010001	\\x35ebe364ac193806b1b656b42a1fae5610040ae1b9feaa7dcc68e832809abc138859718dfc5f3f819c472d3e716fef1666f9a0ee7febe8314150b42a0c99ff0c	1672478248000000	1673083048000000	1736155048000000	1830763048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\x0c3adaae6a6b554632478736c932d10c4566c65b56714875554cc9a50a0e6e1eea42f99cef3d74183e3748197c4b846e79f5ffd9a58bf3be7ed17b4ffa5b4483	1	0	\\x000000010000000000800003d63b72518ee4b187a7264802fac06288506ee2805bf7ea96a72797abf7c166d93f4d3ec18a3a2a11ba731bf4dd0928495f2200a007552964fdabfdc26f9826b56e1d873ff104668d2cab76bcadfa407a13a563ec58a703e0587f08ef30aa747e6457e6681427b74bfe0285081e856287d217cee37afd25a766b71f0ff74094b5010001	\\xbdda550f30c37a094aaab73b5433255955b6637c31379b1ab9fd4a1c03b060363152b907185d11ad804741f43a5d484e7e8aeb173df43bfe2ee0893e244fcc06	1683359248000000	1683964048000000	1747036048000000	1841644048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\x0ecad92f8d60b55aec7a384b8093a80a55a8a231f1813a3144298a4f5b542034c4450451f8ba47c75f8b1279b2d809e56829842c4cfba7768516d306ed3257da	1	0	\\x000000010000000000800003bb50f29912e23c904b331281b28d107e0c56821787d8b8f8714ba6c19dfba77d156c44f593b6e6987fd0d2c8af178231c702403002784e4c7cac7cdc3636d9493268ca0f3976e4d910b8d5ba5dfd0f156c012319878c148d36eb479b53ea06d5026fc9bd273fbc742afdbd766102003e6694f422482b9577d957db3ff75d25dd010001	\\x18a5e14606bbd3f116cb0163218a5b00103783e7e80d6f0b767e9e602c98a3283aafbfd9dd091cd55242f9c24079ef5de5136a8d09885fef13870affed35e105	1688195248000000	1688800048000000	1751872048000000	1846480048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
211	\\x0e82a2a5afc54f7b44100302b8a14ce359dc25fa484ac856bd2bb3ddd529d17de0bcec278d8850e58dc3d566088d33e18d144123749f9019e3be5e6e6352efe6	1	0	\\x000000010000000000800003ba1847cf48362cfbad34887bd1c01f7f332fb7a709db468e71870fddc1ce70def65678adf825ee425d4a92333b27f277b638334a8ea96edf4d59333079d557ee0b50a223f8ac5314ce7f97ea3ec89337f1cd840fab9614da3ca1f46378931d232767fd34f80232a23bdf5fe1486702f088a99489886f8117b2d923aee5d125d7010001	\\x94c83b90be4fcc1289c6fa5cb5a1f53c9c8b995886aea4733ab839da3ded425b0951902d741361ddad6489f004eb96298039da7738cbb46c972e42b661d00000	1683963748000000	1684568548000000	1747640548000000	1842248548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\x0f1e603ae4e0f547b052a4eb7bfc8e24c5d5264ac58fdf1a8cc770dc1fef6c4afadf9a6a61c572a6e3e14f6876333b8e224d6f6f41e54559716ffe00d90e0f8a	1	0	\\x000000010000000000800003e49988e99c317e8e4c10f80dc73374fb6d05c035e01a15673ea9ae60aeaca7f606ccbda179692aeb5661a2863fc9b3ae5326a155a6f8adf4433dfb881c10e915b3f3c111801b9d6b70356f1831136c1887014eba0e5635c0a6a595758631df275f695261277e1fdc8689d883583dbc9a5efdabe0550251ba3d99cda3db895645010001	\\xfd442b1681e01d1dbebe0bcd2f9e744f31c9bd0e72c909f93e9a529cf6f86d32f7ab85c46130e250ae111bad15fc54a60b02e4f80905f76726fe676d02579b0c	1689404248000000	1690009048000000	1753081048000000	1847689048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x158243b98903880834c3bf50688f39f8b83b6821e20b5fe7dfe8d60558578e357bd98b5b66bc19f0297847fb40df82cc97dcd3f473bcfb5bbe6ff5b01b8995a2	1	0	\\x000000010000000000800003c7f2e8dc191859e85eb56d71fdb988efa4e5e9e6335771bb9501a6eadb51d862aae457dcd7947f1fbfe61b17a958e3a37973bf3bc8782d35da3c294b2e72197681fb6cbd626fed4799c003a3811d9b51c06fe6fe777b8ef06c4983749077d60c8abb4383b77b6bd041937c1ca2a55a8fb6004288e7ff8446682c6ac60c652295010001	\\x25d0278acfa7ee58cb07b980f7ce9adcf86f6066082ee79771c69050acf4af51484380e6bd15b7182d61d0da8484ae4396eb9f0a9db43d699458ea1793107902	1683963748000000	1684568548000000	1747640548000000	1842248548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\x1da69c5f705b8e3eb8f7eced410c14fd44ad5504a56caf79f9459bfacdf63fdd0793c8fb28708abd6a9db5bb7f5d21b235e1758b7f2cc08cbc4c1cd07e009ddf	1	0	\\x000000010000000000800003b60d8d750bf1a565dfc0aca98fc3b079960dd42a2021ac5a2ad8a0ac5dc206efb69f9ec24e7b5a0d6a578f167820524f2f80f754b1951a4b4838e3d042ab595d94674c741e75238701881cfb564b0183e9df7ae4fd444eaf4cef81371963b04ef420b73c9475bcec55cc45ade7fc9a0fe3a0679ad4fb34e7177212a0a34bcf27010001	\\x99fbc7c1da871d5efa0eed3a9e1d3c2c7f0c65f80b8420b2d2b4eb08c84eda3f6a45761d32fefd295c4e23a3379d87d0e195510693b4858887c1867c24c1c902	1683963748000000	1684568548000000	1747640548000000	1842248548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\x2106e3260a3d57ef557fbf69bfc11375d2a1af948a41c8f9d904e22f1a89f83a77005aa59162f8b545bdfdc010c5255ecf9b26159e2502e5fa4add9387a5994f	1	0	\\x000000010000000000800003cbb143f2b2e4fcbb6330d39b9acb78ba8ebdb342a4cad7b56ce9a2420b77fed1c0bcd83bf7c16a85de0f66d32e19d85d8f546af017af1da875ab59848eee794a9a48de556df9f66b1ef76da438f274851c2cb2daf2cd276d358c90a8c886feebfee0a3f9b8b53dea0ef1dd091f445f21a70bb84101e715aae1225ac26c44f6ed010001	\\xfa20ce286d838eb9e1d694bfbb4673c73ff65872a29b7e09798b230bfb5174844f6dd5c1dfea38b4552b99b32330f0b54ee3ae953c4fbf75aa75598c48311306	1674896248000000	1675501048000000	1738573048000000	1833181048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\x223aa12a85c42142686d1fc30189cc82306f738c7003183da7af209f5df92b4e99a9be8a0f9702fb75d09cca465936615cc5f3d3088ec57cf0097d2a29d8be9b	1	0	\\x0000000100000000008000039ca748763ef3fe152a01fddd53269891976188e6d8aeb3c88da8e31c4afd4e7b47067b9474dc381d4faa96dc7b3c71fae9f3743b08363bf74b7b243a1d9fab041545582e5d679c279e2f1948a4d681d2c0dbd022d83160b056b1dca46e9adaacdd7ad831d3c74550055f85b52dcccc25d067d75dd458eb2a9dfd8d3705d7bebb010001	\\x5d6bcff490e0a27bd2bfd8c35ff982fc313cf3729ea0a5c365eeec4f02261649bded5b5739ed57f5b3e7843ee12df84a35d57d463512d6f0064625a3b4628f09	1690008748000000	1690613548000000	1753685548000000	1848293548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
217	\\x23567eaa205b338bc3a70130924ab7775f1dd28409b535b5b109d6afbb47f980d1d290363fcdedffd578dddfff0095cd5d5a862d8bc75eab01fb8a2956dbb385	1	0	\\x0000000100000000008000039df6861bdac74b9023d03f9dc39d23a05411d079b2faab9efe6d42d72c95bd8a6c344f428a2bb56e35f791826dcf19fec570ed0ead7959a82528e8ee06ae442f00eee6a6a4d0b616d7e1b5d2c8e6653f438556ff8610d6c2d9346d83c36e17efd6c883e740d0af22548fa61bd3e3b063f381d8c3b976e78d0d9b89f01ba28887010001	\\xf6d3feaeacca546967e51881488d39e251d344ab3a1df718ddea63033d1eb1973f04fac359df8f66e34a96b79318b2c3a486e4c23afe49afbe3cd35c7cc07a08	1689404248000000	1690009048000000	1753081048000000	1847689048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x267641e742cb243118f4b5a041e66e8212bf59e59d295d8cf523a4f24c1abceaeb8381f1b3b135a3cc58f8bd8e0426ccd8418d6c58d312c2aca1a9fa9672c2ce	1	0	\\x000000010000000000800003bdcef24900462b937f34de553030281f119ff1701f7fd899be1ed56919f778f1c40a64395fe532966c195ba3b11439081027416d8a578590896edbad8ca78ab6e5bc57b8912aa276c05d57c3c3289af6635126c04ee2553483d7f84dca2abc6db10284780de84cb58fb2a27e987156affb3dec43f84d84601f197bf99e12f1ad010001	\\x8a0f006d7faadbaff10b169ca2932889ace26908d1828e151dbf9283d2890b0a9061e5eb6d4d041ae50d6be69000b24a9ea3e4504dc0ccabc58a60e478837f0f	1679732248000000	1680337048000000	1743409048000000	1838017048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x263223a6eb4e34a8c7dc745f8112919c99f0b8a6a565158428bd5ed5e538d160042711b248d9737f47d4b4b36efb8bf6c09ec330e001abb8a98ec9872dbb4c79	1	0	\\x000000010000000000800003b734f4096756bdf27e58e8b53fdb00ed6c8d395973f7e2433d4a75f9a2d91e4150cca996f52b4bc6fe2f12244f517da2b856bc4b0595f0e2862174ec70b397384a438c5926b5b56cbf33f064e0dac5be6e9c1acf382340160a75d0aa4a4e3e3f4aa81f06f502c2f75ed7e0013059e09a7aa8ca1478cfe89ea964d05597f7ac6d010001	\\xdfec523103919295aaf38c1761ab8467e230084dacdb2b8dfb1649522a8d10d658e1e68d047e867094d9760640459cefeba19ec41ba017fc4f01ff2b4fd3da05	1664619748000000	1665224548000000	1728296548000000	1822904548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\x2a3ae9816a7cf5951a1dfb5493e617b81abb9bc348161a6c210610d57eadefe3947de8e8d3467263945cd9052c6caeed5d52cc6b517f53d8543afeb79a58cb61	1	0	\\x000000010000000000800003d895fce3fe4a11cce65d5827f6435502e8c17b1a19b97e795d4220db0324fc0f7c150a061db15a81984305f15d2e36677684ffa793095b10f0b95639c65071673a21f4dbb4da6b1ddb726fd65f533709cb267f40efc96bf5d355a5c2573c5137610eceb73fcb27bb50204046e6a798ae960ff1aafe33dd03508bb026ef0b3d4f010001	\\x163184d24826b54bcdd0f65ac221ef558eff6ab111faf8a345178dd702debca94916060d8292d1da023b6502b15c6db3f81d8e7a096c6efd3a699edb167c0c07	1670060248000000	1670665048000000	1733737048000000	1828345048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x2bce7e55a129a70406efbf68a91b7485d9ab71ec60f5d2797dcfd2e0e8d28e449a76651115df86e04ee3bddfa96ffa011b8988d0454b9caabff3c36c2ed9a73f	1	0	\\x000000010000000000800003f5dfc6943807ff13290cd11894d04ae66ca2f24fbc08213eba49148eada77b34428cda3e12c16fdd8697bead371ced5d2e41a15c15fc2732902733f037b1108190407695ea4ee1ca43000a3fc975ffe3edb973bba2e2d31d4241a99df4c2803335d80239fad77fbdd9330d3ea9d12fe28df5baa432f399f8e4caf1ed4bebb421010001	\\x02af3c62bfdabf904b952259428af515cbcd547aa7b446b52b691efdfe392256ba52f7923d73b53f614463024ed920670774a9654a83e0a1495dbe6b35226d0d	1671873748000000	1672478548000000	1735550548000000	1830158548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
222	\\x2cfa67aa03baf55b573656841da80d00702685f86c7122b1824d761063c2a65e0a7aa3b40a77414103e8f2a9ad61305107a75bb4e84e43ee2b5609c999d3b8bc	1	0	\\x000000010000000000800003aac00c07eaf4a91fa114efea77e575c4674bd3fe56e6c428901d947b2c737784a376a2d595a375ae4cdaec4aecda5aa82c875b0e6723c5774479d2c33318496d324277dcef13d2e43640d7105f9e1f0e248b18234291cd43ccb35aa6ecefe8a1b460eb4ef59a50727fddce3bb7578d7c60ee0dbb38316830ecfe00cc72fbf8c7010001	\\x1c1cf06cd48eb3b5e442450ff373d679b4348883e612137b3d5f0acf90deceea289c0c5a14ef2ca88adb0c49608c51e3ea33c834ce6931b02b7ddb870c4d2c0c	1686381748000000	1686986548000000	1750058548000000	1844666548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
223	\\x2f329613f4a6290a4602f3c1d760e9c78a52d312b68f848242fc1fe49e6a911a8713239917bb8165240b3fe023b8604dc40b1f02dc19a67264c2e1e806c7abb0	1	0	\\x000000010000000000800003b3af065221cccac4a1e14861fc52aeb130290a38b578e0506f6006c2044440010d7d6ff240e92d5131477a4d1904ff5d40a94a657a45124ba622ec7edcbec89e053d983e02f42462b1ffcf4c32c3aadb7d537c65de6fd6238c218c56048701d0998e8bf00247dadd423e5315ec3c9e95ec0508cfefe7bfdd781500e11af42a3d010001	\\x8685e4411c8f020a136c10fbcec995121b7e83d8810b591291e4bbb49ed49ce774f5b04a64e71018e55a88bf6ec8aa45c23d714832e84f2c0730c0af5b519605	1671269248000000	1671874048000000	1734946048000000	1829554048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
224	\\x30da912010ca733f1d7943e5339ebeda96bff7475b698859a03276db1133d86fe353e30c782d500bd061e0743ab32fd93d58fd915c48c90526b624cbdf48251f	1	0	\\x000000010000000000800003d20aaf8c09ab641fd7cc10977a85cd3eef53fc8e23a9802396668e39b6d819c8c63a7bc05ad55352965aeefa9b73298094fd2d0188989973ddee238276b033edfe61511cb920442b81b279f5a792290282d7392484fc61e0f6a9284046da924ea051b7f14389141ff7261abe4e605cff1d9f0140418bcac7169b528ada24a713010001	\\x7666bd122945b503946af1f53f2d52c6801e3ae41ddab41a69d77eb6950054d77ebb20fd97613c004e25f6e1cdf6e9e2d1a1f21668d43d57ed78b5787af4090d	1676709748000000	1677314548000000	1740386548000000	1834994548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x313adf8cffd5bf03d7e96eee4d3e5196d98430b8a2b9c56c82f5404a436748e42391db86fdea3932976bcd18150b59c4d71db09c1f188f8214045c264362e9b1	1	0	\\x000000010000000000800003dbc24ec9f04e2ee683daae4ef718cd28990162f0831e0796a98a4671bf112924b1ac61c849265f8a0b10a3b745850e0193c0d42d6e49901284fab6dfca0a791a8226d89fa40f533753582c184b140ddf62c70035efafa6cac6311206c4974321ab3fa93d76ffadc9e5bac821a9d3181d22122249a49afbaf7cadc08c416fe2b1010001	\\xb762ef0c16b9bcac70fccdbab4c664034ea66b0e450ba6c47e1273e5f1e9a1ee55b112e4b6349bbcace8c02362cd02e7d09242dcbbbed45f5f5f9912c14e9706	1691217748000000	1691822548000000	1754894548000000	1849502548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
226	\\x34fafbb39012e2ff557835c285223203d56738c16ad927d7f15c1741236ef0f35372f44a9c055b79e49a596d251d42519fff9b8eb1f44d46963596e38a697af3	1	0	\\x000000010000000000800003d4587b07a121ad81654f6320cb612c6f3ce077be351e43f91d39686d6b568fbeb5776b535d9423742e9c0bb5a33c7ca263fc48e8f8ebbac9c2528c2a40f54cc09fdb132cc5316896b6b6d2aa30c889ac6e75321997cf5ef450de524ef251a61baa3985efa5662aa62ea18704731002e79fa8c2c9f706c404cfbbff2c4d799781010001	\\x84680d93b92d495953680617fef31db47985ad41f1fa8a54d49a9330f5b11c9bc133555948ce923d517731ced375f95652cec505f84e19cb91bec1bc4cc7de0f	1685172748000000	1685777548000000	1748849548000000	1843457548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
227	\\x347ea4b800ae573e8ee4bf0fbf8af91ca3ffb7825db93bb7922a5d1746cea752018063a5476b05a86c89cf8291f48a5501cd1c367d62637d2c5e2ffcfdf4ba72	1	0	\\x000000010000000000800003ad887a7b0313c9d8839a4cd033e21b016904d66a42929eab3f6a71b036229ceef4c027d4740509ce3afa4695b1ff3538eda3dd42647e5e49d017931c26b84375d04b15342c8d0220a47d67ce327c1a5365578168dbd74fa9307964e7aac18d97041b92ae0bf9bb70e73b4d4e0f909e476d8c2ab0b34a3e4f1d6274c75db21129010001	\\x026d57f84faff3760aea7263fcdd5309aceb6efee14d6d66fcb7ac1beb983f5fe0d10a9fe1b7abf4d0136a8985ab70296e4bd01d6213de59c107404929a4e40d	1688799748000000	1689404548000000	1752476548000000	1847084548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x3b26800cbc1b7aa3a2a4bd6356b278843edc5ccd2e7bb215474e12186899579a8e80141c0c88c659fd163cd8164b5cb42c9dc8f277e0dd8e939c6a113c7e558f	1	0	\\x000000010000000000800003b2c258b3b0c0dabd60dc118d9a86868b4453eac4448f07a54932063f06be18b91eee2d4d5621ce9885decb9c9ab36372f93c04deb172936cee02b02eba7f18470d6c5264df4cf228341aac310abdfaae1372e5edeb96f5124f0872f4ebf12bd394782692db3defae5f39749873bbe5ab72f5879d7ec7c3d3ded26bf539e84975010001	\\x93a94d0ae8ab336904521ff550c129f8395a0881f2d994ef69795ef5b822fe193c633fe07176ac22e2862e8d54e0edb51efa3f244408adedff8f1019b1759a07	1667037748000000	1667642548000000	1730714548000000	1825322548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x3cd683c852f229f90153709bc8dbc44e9cea33ebbad1e5e5c344aec06eff3664d95d3883451c14c7bfe1fffd4d742ead89255afeeff5eeca41c58d8a0fff78ae	1	0	\\x000000010000000000800003c2b61b00506508ecddfdb3296a1537bee4f3ec86e3f7df43835f2f2c6e918a6e3b3e5246baa0a807d9d09859630f6c46c5bc3e75266b70dd45800e589b7ee832ce6a50687fd6fe53153be9229d1dfb198f99022c18c2aaa09d8eedea106d00228cb13644eb852f12aeba10ba7069eb3bf6a1f5f17f8d31f535920872aa18c7af010001	\\x079b8582df8f8b23676f2658b71d2448fbce7dbac0033fbdfa18db1e156bd75020de6128d013e5e458e4235bd5ffe2eb780caa7980b9b1aa21abf8a8a6c67e0b	1665828748000000	1666433548000000	1729505548000000	1824113548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x3f06cd62ca8e24ae3993efdc7ac73d8728b667a2634ceb148310e252b6cc5a915fa8903bffb92d35c1cbee67914ac782b8da698f9585697d019dd4334aae3677	1	0	\\x000000010000000000800003980bb69e806bd468f095e63c0dcc7c211ebaaaf9f574545e2a8447a3e31d8dc6b028443ea819028495262bd24e997e95fd3d9768df7245424ac9c887d5312749e476a9543430cc8477ef138e7bed09be995fd8d1562f3a4e652999ada81362689a02824ca674f9d43963cbdbe644662ae058c225c6d37044002043031620889b010001	\\x73dc896bdf727a5bcab2d4366ce2c69473a7d20907f85cbec37e25aee547abc71a1f0c135c7eee0e03b97d9720e3bd6b613612cbd705972baaec4caa738c0007	1668246748000000	1668851548000000	1731923548000000	1826531548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x41c62fb1109e6664134d89e1983ceae122e4106c1e37ec1b4a2ed1993d6a74d789abf2b4d8df1ea8c26fac3c7fd372494b3017dceaf7dc9988e17b4c84b1bc11	1	0	\\x000000010000000000800003ebb3a962501aa1461147e86f18f355e01428b2bbee53e8b3cfd9afd118f38217ea48aa755774e1e1358d7c058601ff03b393565028c34d4d0c45a9d492a2614d161fe38ec123f5121b4d6ef2dbb2ca7bfaa22c251e11b1260a8abff95f8445607dc37f961c1cc4058f96a432e57a0cffdbd0a3821dc00c053a8a0092153e7857010001	\\xbc24a8fd6d80fdb53d9703a2397a5792dc5c8e52ff57c9776e057e5ebc56fee24b2191b806300f9e594fbcd8c550b3654afdf9486d25a9ee8f5c2c02b854230b	1671873748000000	1672478548000000	1735550548000000	1830158548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
232	\\x459e6a65cf80da1a282ab4ba1e53f7a973e1976aa9bd4c1fa1400d891a3359ab3902fe1195542dcacb002f73d6fa86c1be14c3f91f180f9b00dc61a01d2505df	1	0	\\x000000010000000000800003d5efd986f0f64cb9c7a9ba7ba74198e5aee6aaa48bb13b6b5fadfa7e5d98b111cbaf0371b7526a07efa4a8151864d5d3c54ed789164fbfbf8363020dd209790c50fef73a6b22612f0d84e653174ab525d20fdee17810c9fcb0f537cc41bbb03f99508ec208b97ad3ae41a5d0e53b0e4011803107a07ee37dad8e7a20c58caa0d010001	\\x962d75ed7852bcfce7e88fcff1b98865384c10fb992edfb03268596edbdbeed8123254146913d77019d58e3fbe93747aab748c9519c1a68b97bddfa98ca5c300	1688195248000000	1688800048000000	1751872048000000	1846480048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x47a6c0aa67120b5cc930139e446712d333f1f3e7f571411d73f414e03dcaf23f8de6fbb6ad9d16b8fcc440f0caf7b86c0e728c3e4b0a64aedf5ff1886e321710	1	0	\\x000000010000000000800003dbe9d9268ce4c48e6f59e8ff9c4d71dabb449aebba74f2392a42b0de0732fd854969d0114c03d6db9e4e9d69b7c4acb8beb60c10d7d775e2271f51981805307168a404764bdb3c8c7b2830a54067ccd11b689486faa120a23994aee1da5425691f108024cce700a3afacc82c6616bf5f169a7b6f674fd1fb416530be77048383010001	\\x61ed38693016e04bde93adb8b19950867215e9f3aacb4a7b532d2bb0115d1d4b2b0fb82a208976eaf490d7d6d639ebc660250ad1b82e94fd16b75113b9f6bb08	1685777248000000	1686382048000000	1749454048000000	1844062048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
234	\\x4b065d208a355d63e52162e81381b01c25472a8ecba893ebbb05257de4dc60c3e863dfccb24fb3a535a8937b66d8761297bedc52c7cf84318dc210d567bfa22c	1	0	\\x000000010000000000800003a5ee88f8a1d4651660c34bce0b7b60ad59a01e084484914788e7e4ac4a7f58f31de725f26ff73500baa7392a52f8a8f50bc002bb56bba447e9b75a57e18992b8a8ea2483f2df80661dc558588c955f1f2ad34708703d9e3c350582b9781a0f3b3cea33be857964239622988dea16b30b5c81a26d25bd6c27f2dfbee09bd2060f010001	\\x80c10358a6a9f01e3a12ac43263797ad379325cbf1082dd939cc6cd0f3bcebf2c8bd83ced7d4cc10ef308effa2b7961e953c5c1b2258f50b6291aaaf9181150e	1689404248000000	1690009048000000	1753081048000000	1847689048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
235	\\x4f36a63cc646c31bb14901a1c0aa66c7d1cbf8ebe5df81408de9da9cfeef16ed2094ee595deed6f224a43a7389a67cd13eaa98e19264c8560f8f942d558b4ca8	1	0	\\x000000010000000000800003e89c1ce9db8e8feac98be229638afc18e054722a7faa2f954a666a6db8b41fb9a75c4c16913c0faceb21f82ae81d98b3ee0801d673628c00b64b143fffda16f5d680a58e0883a0cc04fddc204e2d2ff5c5cb6d5d6791f0a0897db4cbb91bcfddb0898cf60cc8225bfbd57d123c21caa9b9745ef901e2816e1ee9ccc45d2ee419010001	\\xb79c46546f65ca1f47a287126ebaf68a2f3d2638f76f0a331ea9f8a79b93ceb709e391d3627684ef10246d15d6d0ca48ac0223f43cf4b769ec127244a010340b	1663410748000000	1664015548000000	1727087548000000	1821695548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
236	\\x4fae34ecb18ee1ad7ce3fb5334c61d8006a2869fe0f435debba4e5971d2ddba4fba29cb54f26033ed65da6ba0abb557d9c6db093e55d419576094c1386379ce3	1	0	\\x000000010000000000800003a8717ec491069d186cab2186a75c90c608785dccf838bca22c0126003c45427366bcc2bd39928acf2dac3305aa7c316c9001b3285028cde122a6e46c390d66e6c60d8310f44c0e2e391d41a9cb920cf422fa6a01772abbc1d3fc2afc99b92549415d736ab5f3cf16fb320c5cfa41431aa8d5705a3715ea834032fb7b2c7fafc1010001	\\x8eb3a417f2b07364b0d765dfbe4e9793bef4f690a6ed6bc8941aa214f101f29e997e778812e93d6bc7287ee8033d9b4453d74d3f1294efa8d9ba5d0559942f0a	1683359248000000	1683964048000000	1747036048000000	1841644048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x52266acf11f6822fb64a24258746bc64c0c11e2dc73ab31d044ef720e5173b3fb65dd71a4b464baeedad1be454e8bbc7b09c1568950a065d0a6c67e495bfc8f3	1	0	\\x000000010000000000800003bc1132134b9bc5b95fdae2f56cf33458eb3dbac442dfbefa488f11744da09414c0d5142bece641029428ec7a8bedbb9f0cf71647e975182c6786a5187fd160cd06a0ec9d97a648c38c03a5333e00f3838c6cb9654f29a00b78dc6ee63b55db31bd927f7c099431ac6079e4b73dd24454cb01e3d165666acc820b72b2472625ef010001	\\x32c4a7898a6e1575f39ac87d2d04d99793957e373c3d7c0fe8edf5898590611107376faae84638c366142d7dfb8beb979c50885bd6ecf74da09f5471a459eb01	1678523248000000	1679128048000000	1742200048000000	1836808048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x59a6a1afdc62fe6852e35c9d05d45858db39bb04914b4aad1b3b69eca277e9459a7c5b244ccc5e6a30b899edee0d6130d194454d4423cd4642da496de5ec95df	1	0	\\x000000010000000000800003c9ac06f0cc7da7ba53e60b3a94b91999ec072928d7afa8987db22ac70254ac042dc6826cdaec8d221166a0c40a960b5354da8003d7f1bbab90ed091210dc727c61dffdc85b0417151b7e970b7928d08fd7a79a9567f47c2ca2a844079577d811de80020c6c9f003f87562f40b9f4d043d4bcee7d2a109a796aff186ea731a1a7010001	\\x6804ca33a52e1ca3c46e9a3d31399bf970c0a134c234c9a6467a9d20e674fd2576c61608e19f6d92743612884109fa6976a4681c1a817fc664a4c8391367a30f	1662806248000000	1663411048000000	1726483048000000	1821091048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
239	\\x59de243e13a289f07113a3b8aadc0f60a0a2241e0e62f9e0f3ff88013053438ae979f4783b74ddb39800bbdf5110049bf02e0d60c2331ec26e8a258472ed71fa	1	0	\\x000000010000000000800003bd25caf4633123451f62f40845bc4a79d7598ff37e20bebe9c60630f15c2d0ec522cba8aa44bd7c6c9b23eca2dce116159aab531f437329476a0d2879969b92dec7aa6ee5058d0aa443a2b0a25d2370e41e82afb283d4af921952fccc965c2fd10e6cd838e7cfde0d357e55ab6d3539c5e7db37050d740d50f63ce8791d91def010001	\\x64ba2ed13b0b3f68bc60d2e320b805937126c8725c59cebbcff1bafe05a89e5aaad4cf1cbc0df3fd88731badb63a2cf3e7204abc7cb7afa16195eceb96946c06	1691217748000000	1691822548000000	1754894548000000	1849502548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x5a7ea27a6f7636802ae9502238b0f25fd35be9b9fcb6fcab6804d26f80d78476b638659988d8632f90e0af7ea1902e5c8fe227611655845fda6bf5d42c9e1e35	1	0	\\x000000010000000000800003b4c5482716f624f2dd47f7305aa772b961967d3568876d0d0c53bd9286705f99c9da1001c57b4a29c071ee354f90bd4b7782b2a55e8eb1e79f59f3702084f19dd37dbb1047eeb29571e383041e337f221c1ffc5534d1bba2f7cfb18afa20a9da9b9ff747707947f0206e3a4d92a2d910767114527c01013e58a062cad8959067010001	\\x17ab649d1c3c0ce5c8d600df7ab413c932a1114656af4e7417e5500c4035e451d70e5543c5fd45377f0d69264c9d5426318c965bc7f2a78e6e6da955857ecf09	1675500748000000	1676105548000000	1739177548000000	1833785548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x5c7af5e76622ceae1e841688210737a543faa4ee2b6369cc160dd824073f1201ce12f6abe683c32279bd83640973c9fb4df5dc6fb5a7f921f7c78d90b81f673c	1	0	\\x000000010000000000800003b9850364db5ac7302724c1fd29833ef740d7c501b9a29d98b70c8cb3579198533ec1168dbb0ccc882817ee94f457697e1d307762ef1bc0f36e50a80dc093dbc07e69bd26d2a574fd936a86715beb3d3050a36aff261a145fde3d9320fe53faf32be606733652be7eacdbd73c0bb8fd7a618f3d3652c58192d6acd450b60541cb010001	\\x4b89fe74c124a1c2e6c51390677f802e695f03ba4b1214b798d3310b8705fb16e56e29967acbad0fd067dedbc29fac8861db360cfa085a8b8e6b954210c59107	1669455748000000	1670060548000000	1733132548000000	1827740548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x5d46fb3f6b1df81589937b40d868c37cf34f21eba60ebe1dbc401eaad08107f9c00b8d3ed5ed6bfdb31b134ddb248d9a31ff0a17d9d9b9b8ef346cb1e757f329	1	0	\\x000000010000000000800003bb48f71fbb3c8edc6a65f40b0a46bb3c8df6b0d4e27a60771f070bbb3e3d9198af4421e37499d31b2cb1974c26a9d110a84e106b58378b9ff039a9f7f19b88355b83d7ae9a39c09400b4d1a61d3229eb17972132f50f3311e4af63c16b15186b010af8c6059c0e577c128b8cd0c539aba5ad2aa3e6fc0de31010a351df1825e1010001	\\x1b47705a3f60d62dc44ad150944f23e4197fcc02b9ae02574b93f8ad2b35250682589a986db181cfba414640f376a48b5dce118b43b6435a43ac8d84ab8f9c0c	1672478248000000	1673083048000000	1736155048000000	1830763048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x5d9a0d246f5df873465c5a9045d6fdce5fb2898b33597ea171ef5cd8b87a58e9b4d5456f6e7891effe0bde7db36c78225aba9c2f6b050c0dfe8a37b2a6a69519	1	0	\\x000000010000000000800003d35eedb36576db65670605c70a6e154d0ae331f132f6d5c132c3ef211ba61121e6623dea22844d76623977b5041e5602c927383701ffa615cd04dc5915defee6f57a7eb1a579c0fc25995fe772e76e612ba6936f731de59a3a72f130b0f3e56eb9310e703366d8933c6f9b5be34e5d5f859db18703a44943281ee901f6d5255b010001	\\xf609302c1f59fe0455f788655b2431acdfc546683d2338badead4b535ed566eae761816154738b12c9ce85275eb0c8bdc8c7f4dda324e4ac13c840d764554a00	1670664748000000	1671269548000000	1734341548000000	1828949548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x5dd2fdf30556ef7e484b6d8ac1df5f8684c1b945d00da8597cfd1b12d3badfab0e3b3662621b22670f35741ef8c27bda9b88f858409cbddd89a83bb8b41edb50	1	0	\\x000000010000000000800003d3df5613bd7f34223d2984cd930f61839ac103fb6fc9ebf71bf8d8cb93871910833ad569de76e4199674273ab6434efd2221e922595d0e0462e8b913eaac2c73f79456a0f0bb99877debe2f6897401ea0d26dc602f66909c02672000175bed4e5208a0f672caced817cdff11f5159161d44857bce5d1a913a8faa65d2ad7c9c3010001	\\x2a23116e3f638a344d9f68a7dd9e187f1c6713eca81ea609b5d0e12ccd3b4f1d62bf5e96f1be52b41ec9c9a7299a5eafd97dc3998a3da30298ece576c9b25a0e	1678523248000000	1679128048000000	1742200048000000	1836808048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x6342a99a091a0d093cfa1f1c86ea92f4d0002106e90a80c9ce929a7a9f75b603acc018a101fd3a86f87db6e21acd58d86422d3b5bbcd76acc14739754065818e	1	0	\\x000000010000000000800003d904bb5705a32cedf3ed3d30e7085bda44594007e3cf287ffdf098540249e4907d50d013c6a54b21e56bca78808dd146c5567d739989b05933c16511c92144283fa9cf445933e1ab84a539664b8d1a28d3bb2879917896f75df2c9f7f10d369d031659edf9580bdd7746faf28133eb422c0b4ea417b66030cc2efc66e8ae10a1010001	\\xf57a1aba3fa1628b0f9fc0b37776ab5f2dce6ef00dad778c6a7642c3866be86e5c745562f4474b94440b51e3aca63ada651635a40f1c2ed088daa604d4850500	1674291748000000	1674896548000000	1737968548000000	1832576548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x63be2c3042b3185a6e3d9de85557fa6203c05c5fd57f7655e1dcb5eeb0d587d00ed6a8d57da5cad3cf2419d17c3dd3c73547aba4acdba566213ad4a4166f7501	1	0	\\x000000010000000000800003e412f52eb3f84247be1ce6dd36782a6a97f7685f0c438963ef2cd553606d722092fddde796f393dc552ee57498e161d7a5c2d5685bf3eef70b791c32d6864be1d9628a04859185190e6545232f8fa2eab52982c96e6a823cbdd55341b2b5eb746b70c8279d3faf050d30ba43b279cc9adc14e52a0650f27be02cef83b5d4c7a1010001	\\x378826c99cb128941763754dec03f9827cc206a3b868ffecb6e60c7fc4a8b4633cf85c391aae6bc3de4048771731e41eb2b8dcf3c26bce9982a313ea4e7a6306	1668246748000000	1668851548000000	1731923548000000	1826531548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x64e64230f9f0dfc48ac42ccabec9552e0653bd3130a8a993132d2f459d0d26e62b9e1ba323a481699584258b4cab6b0da104f16c28837013aa538e9a9cd34d5e	1	0	\\x000000010000000000800003be0cfff81f87abefd1c1a193a5c81923911701e048f21dbb81206b8dc61a380f63520965188fddfeea58739e53b6401789aa26fd2f8ba96afabdf568c7a4c6f7d7d8102ffeed67cc0c917a76df029996fa240692d3e3560890ed24e0b00d2dee98f4decbfb452c1d85b65f69a76d8beb30a9e14669120d62f47fbec9df007a33010001	\\x9d98d7adfdd6c66283552b93b9e0ec7438041efa96a0216ebf0887dfd7c80471f73a49c470b2171fc1c1be9866e2e0fcac05e8ac217b2c2becb14e6606553107	1681545748000000	1682150548000000	1745222548000000	1839830548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x6536dbbf8603f4b3698bc34ca312d9ccf020c556cefe1f1ddeafc257e4f5fa176997cbc95f3e135fac0f0faa39b05cd8b1c6f32b3243ac48efc6e6b18a5e8162	1	0	\\x0000000100000000008000039efaa85f324df101a85f8163d89663af692fa2d8978a5390ca6645e013806f66e18818382b1fce0e9a5a034d462a3c807fa9b507181f0a140f8ee0a9bb68bb0818beaaf14b32cf0aad7c33366358d53b7be629c0e46f81c31d703293f44b18d1da5753b927c82e3e265d40e4cc578c1d2a9ee386f325cc11fff971d7ba8c45ff010001	\\xa59eb7a67ccb2e205c7778c9d8e2a9dbc8462ed86816c29eceda02f4e4cf4f9453e2934347adfe9dd579993e06cf7eedeb6d6c490bd5671b65655b979a101204	1687590748000000	1688195548000000	1751267548000000	1845875548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x68ae6fe77d3c4d8da734162fb93014711067d59b1abb38f9ee1e0b09db292e3d10171f55861f225e58591bd866ecaf6139d0212955ac727c5ac429090fa2e9f7	1	0	\\x000000010000000000800003d925af18ef57d632e2ceb996a9c39fe28214cef2f56627c56d3001cc3650f79bbfbabae503300a540733a03a870c094d15957d4ad336058159adc899811de7e212cae1b0eb0ade5cd7927cf8e1b28aa2766d912ae31c901d5f5286460054916776152973ea65fc5e90fe9e917f35e255e4736c910ac390b25a5a3b3f5aa9e6c1010001	\\x0e8cc500fe0552076088dcf8b74a84bb542cc902cffc63b34dee4493f90435f2bd9382683214b4347ea52c7638a9f1802de9c6444ef4c85b2ea3d0f062d2690a	1683963748000000	1684568548000000	1747640548000000	1842248548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x6c96947e71d20fc16d61df564c1946922a52e3d0cd917b5fa0fd75c03b636ad5cb1e528c6a717f90396b3845e963eae93e143d4eb0a93c8e3d85d3cc22ede33e	1	0	\\x000000010000000000800003f96738419a5bd7bdd1d3f9bf1dd44171ea3cde9150e50d4befa29fd6f197217893cd4dcadf71d479724c3854d6304d6813bd097f46072cadb3c745adaade11e934f4ab4c61fe3573863e6524404653006cc19dfe7142a488bc804d092b8e050de9a80dd7309cf8f7fd3e113b2734c0bbebffb74c49c50e43b328ab2d73e18639010001	\\x6b0341a06058b6bdc1a088c1c25e3641fd64472c45a8378c9243ec7f3af86ba3678d6db5edea4c38004827fe3aadb7ae0da805de09079a3bb097e91f8f99b201	1688799748000000	1689404548000000	1752476548000000	1847084548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x6ddaf291d37d4a888b8eda7d45b29b86806113df4125ac7ca78559e81ea70e1ea4f02959990e16a12df950b34b132ad23e276c09e86c1e1791cedeb0fd35aa54	1	0	\\x000000010000000000800003c97700ca7078a363218f90000988e77062594c435e8e608be979a795575b9fa434383a3e121201bede6d764721a7765f46d0d58084a3c7df48902871e7bc8c340f633a45edcefc5f42ade75a5c85ae9f4c75fcbb5613976a8f62a526b47cdf79e8815c2c595f4affb542994ae7e0d2c1a1c4c41a01e5edfeb8841a9404c60e67010001	\\x1f8bc2de8a08108525c73bc144dc66391e68cf6af632e2b8541e9c0404db21a0d0e01271d98fbbb8ef315dd2d35adc4e1ac9648b6f3a8099b15abc68824b1601	1660992748000000	1661597548000000	1724669548000000	1819277548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
252	\\x6f76be34d9a68186ae5218bcce776a739fa27eb1f0624f5519a28d5f2c41dcf31611da0b7cd4ccc4e0a7bff63629a2b4ccf02a63ab2c73f971092c5ac8f8425c	1	0	\\x000000010000000000800003e0796dd004d7f9bae0ae81fa692e555aa962dedc730bb8970a8d0162e38c4ba8f33b50555e579bab015665251e3413b5c7d2be7774a419febc8585fcd1ea12d38916080f08e5e651abf6828f5d68b0418fab55b3159617c8d888a5ec1c1380e95e223ba5e0fc0517cf4c29244fa6dd809a46281916666b01d9894a62c551073d010001	\\xbcbad768cac003cd0d302015b9217cbf455a40ee343c9ccd3b6dc4b8879a5bf6ade5fff054ccd51bdeb244a080aae60f009d26ea830ceaed75d80a1df6358505	1686381748000000	1686986548000000	1750058548000000	1844666548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x6f5e133600c83fc9a4afdf001695da61edafc2c10d5dfff84c87c45b281ee3649e80489d1e24b883b404e96d5a78f2235a062f01d3fddbdcfdd85feaad89e315	1	0	\\x000000010000000000800003b3683e7e9f07b7b7cfe7af4eea7a855b5e6fb7e5ee00030d7e2a997ff32ab35a5a76de5b7272e8aa8528ca508433390eb3c2383e9b2ea404153ead5f4471cc8eb2632d3bcc5fd56ade50ffeed48e1e33b368477c623ea94a2291b8d949b8bd92626192c38306e8302ec94b747fe0122c3068ad0d8cc8bca5a6b87d1d6ede2103010001	\\x0c362e563323ce8377c56b26aad95eabdfcd56c73c4e9cd5ca671b12fee45dc161cdfb16616f11231edc3de1681d38869fc54236afd2307357dbc52f2188d108	1674291748000000	1674896548000000	1737968548000000	1832576548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x75b24ca8617aa6701bd430d9b42b1c73ddbb9b32dd092c7bbb4ecc8e2f5410b65489133fb851a706c58cecc9b0177375cecd8f077fd7ec62039fe9ab3dcb9809	1	0	\\x000000010000000000800003cec74339070fd101e23a44966f637d568487e0e2540606932e13ac15e64623780e308de14bae966ca7b534aacb20ebe30adb5f77a4fc13395b13a6f540b6a021863ae81f1e509d4e8654855305c7135e116d31b87623e483edb2c51c3344c06ffd75c6b3c9568421cc46eebc34fa498cf48296d780047f24d5166f05fa5394a5010001	\\x238580ff600a5e86172e3cedd3f477a301e43d5b7e3fe2a1bb654c53c3e4e414411427f0537e73bfed0b6b9077f46166d3d308ab050ade06761624e88df99006	1682754748000000	1683359548000000	1746431548000000	1841039548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x7696ce0f6c2898c995254bc8670e234be3727919b241fab8a75e371e089a0adea03b70af6e9b5ef0d7bef65553e5cf9f5aa99e6a1c770ff91fd738edb25bf4d6	1	0	\\x000000010000000000800003ae0653208812e003afb30ddd2d7e8ac60b4614f7f2156f2307cc94240af81c37058647086bab11c840c48ceabed3c667c23693ecafcbff6accf1f1fc970c886bb5ac78bf0bd2df909a0247233b6418ce31debc876c96f1c25fd405ed77cd277b75e79833323ea77690a7c3c9d30cd32f3f4198080e93568dab3d21233b0d341d010001	\\x9ec1ba6167dcccc8b65f84bc036e907db5742c0b77912c1aa85a4bab6af72ff8170efebe097c1b2c8e39ee29b69c95a54b70582b4b35adb6814db287a1627f04	1666433248000000	1667038048000000	1730110048000000	1824718048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
256	\\x7bba989883c7b2494dd3f08bc4b70ede0ba4020ae4b03b6c65d45de668a234cfd73b80d3f3ebd1d66a605b9b220f1cdff3bf39bea0083c19a97182ec3ed033e4	1	0	\\x000000010000000000800003bdf3caf59b22b21a30aafe37f25b15c31ec76f7553a58a2af1d6e956d67919df0f8349e1a6c062da5322445ca2aae138b09dc045996e9fbfb9baefe8c464761c93cc6eaaa3e646e042b3384df52baba574367ec3a620d81e175b045fabb8865c04e8eb58ad803b568c7e986545afbc58880c1ae961837634fbad5cfd24203ecb010001	\\x58f4ffdfa0286a4339f0ee6da9c8b508d6485dc1703297282ef8406c9817363070eabbdafa6ac300e6afed9a38632025ee8fb023d0671876210cfd4b9ac58008	1673687248000000	1674292048000000	1737364048000000	1831972048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x7cf24d830782f8b1f3c2baa06e8a365e07721bc21e6e224ecbeeb803d78f3766540ddb246e111f7e56cc6a138f4d0fdcb7cc2fc7056e9aa5d3f6a0951d7716fb	1	0	\\x000000010000000000800003dedc89b8c5f3ea24b8c6c62f397dccb28d02a9303a439fc98d4245777d73acfa4c608ca7b69447e9d7fd631be8e4b73fb09d1ebf30399643537d1e1719f16f44e24c1cf4481855ce2222d131f61a813a1f70eb06cb47617e122e4c9f8fb44ed0e71ed8fb842b6a2ba2b3b9ba9f831270f4ce09ab7405e744d0706689e82b3a8d010001	\\x630791b76a3bb640abcd443d4c3dabb8889769fe1596caed439fd486fb729420795be3b278920d81bc70406858d4484eb691606908808a98be9522b46a609200	1666433248000000	1667038048000000	1730110048000000	1824718048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x7c223b9aa55847db2864a46b92d05d015a894e6e40be94743eb79392a217ad19329d7b5027ae8b63cd8063d2a3cc3fa673933ead5c4be6759acf3b877083daf0	1	0	\\x000000010000000000800003ca97aaf391d59f5edf87c90a45715d369a7497daf9cab342dbe7a3ec880bf86dbc830c4276cd4fa16b0974f3e40cffa21b696e3364d7a020d07a0983a8d47f7cb82e2d4ccbfdd42d22f5ead1bafbae32721f2d8a96e35adc0a78c02d08e9b2edad2e52599eee0af3879fed7301556ab5a51d99c62144389ad2f8e2326dc469df010001	\\xa6175671e7ab2136f378e138f221b849670a7d638afa896413789c6a939ba5c2538951c47f4f16f38b9e356f4c2e9dc71a9e6f24b6b4d4a3af6a74ff7bb1580b	1685172748000000	1685777548000000	1748849548000000	1843457548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
259	\\x7d0ee8c633d418c93cc549b22e1220a4a10c5e659ad749e692ea91540a1321fcd3fc40cf623040d4e179978811cc572b1ce670f164b1600ea53fb664661d115b	1	0	\\x000000010000000000800003a704b11896fb1149518f5ca0efa5088056d6eb8bd9f30aceb4862210a3df52e555d026ba5ab7ee0d972535e3d6af9a42f778aaba540a62c3ac1a67078b2174d0e97fe1c6aa16ee1236083a30371e56adefa107b34e1b6cddb0bfd18fdc2187c939d94b27516c51c3620505b3e6cc10acfa63a75fed5c1c853282d5067bf47ae1010001	\\xb9241a0cbbf41aee3aa4861d3963228bd8875b0d66f6ea1a85c3046ca25bb22d34515d4e9e932b9aef199662c93970c6743f8b89bd98aedca7efb631dcfefd05	1667037748000000	1667642548000000	1730714548000000	1825322548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x81420a308fd1d2dd119209b6538e57a6568dadc28ef44000e256e41c6a09237f63c14c3496ca52fda3466ac2f4802f61d676c674f8894b953a0fceb40aa78985	1	0	\\x000000010000000000800003a5802f91bb589c61014faff4cc0038a213c26563a4fc2fcb55e21b52cd03443e3c93658e524df83a0099b160eb1cba4ea92f15e7ed2f9ecbebdb19bafd775cd500d7f10bad733639c36cf3982f1913d4a3a634d956ae2ab070a539139a67a235a2bd9a309642ab8109c85f2cbd7d0aecc9361f3664bdba22a1543eb6b8814a25010001	\\x62d5cd41bbb54f8cd562ef35c1706295801ef6947915c4620f888912d962b43a837b4132494347181769623f9e1652b404658933107c206237ef9e4a1e332500	1692426748000000	1693031548000000	1756103548000000	1850711548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
261	\\x8136e771aa442261c59938c28c214e818908903eae51bf884b6b74bb9cad9c4475690ffaeb5069220dc2308dee32a2a1c2bb9160f383c198359c0a7fc22530b2	1	0	\\x000000010000000000800003bfa913e6b8bb5627ef6dab94b8a268f3f752e9bd707bb9ff237362ec9dc44cd4450336034a0197e1a75fbde62a42f95f57131a65f25d0d91a04cef878c84a426f01e491e2b5cff3738daf54111c476b8c1fa0cd89e2a8fd07b882f53c9c82b46bf86c2d9e0bd4a8bd3b33e15b3655e8f31051e10e48cb01ee90518ccef516e3d010001	\\x639fa597fed6a2ef3ed2ad6f1addc6d4aa7be9400d1c047ff93a7aa0acdb495a83c1170d98495de0e9078c3305c3ef059e3302c9ce55515a358a922246217206	1670060248000000	1670665048000000	1733737048000000	1828345048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
262	\\x81ba36ed60cd7abade74fe55586824162cfa33a998e7d6d102aad899486da5244bb4b4484b86f2bc7d1cca5109ed12fd86cc1666a601dd8b4d58dd1b7da29340	1	0	\\x000000010000000000800003b69312a7ace02043bf1f9c1291ad8dd967bc6dfff5f10291e63b7833063014ddfcc2d930a6beb8ec70db41a6885f12609ae10db598a4001dd8bd2a1d40b4b24732db932198ec2fc8ac140ba1e30229a5d5bbce7ff32869dd20e3214b7718555bda8d4e633bb1dea0aaf55da8f8c23b39511fee3a09fcefe03af55b667768973f010001	\\xc373f8ee27fdae3849b8a7b0053be9cff265dc601645c0f9639c9ce58dfc280fb8cc5a0ea01d000163c61b3c99bcccbc641612c2dd4183792ed0b9c61409d40c	1691217748000000	1691822548000000	1754894548000000	1849502548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x8312a8082b4be41761042d42f0ea03791311280df0e334ce33173e060a92fd1bcb47481dc22e7c890de5ef2ecc3edab020bccdf8c927f69d3d8e7f48091311f7	1	0	\\x000000010000000000800003c4eeb5c6b46bdee7d93eaae63b7f837180780306a4adccfb9394bb617c3de92db4692adadf6c37900ed0f8c8763ff4cd99b4a14746fe3dad75e9fcc68c49908f96dfffacaec6f0a48072bea1d97a7a40e404334621c08d32399a7dce1966bb720c236db4a595ccb3eff5ca51504db2055cbff4548f55fc75f6ecbb4629730713010001	\\xcefa0515ac675e2eecc63e0f3b2f4ed44104558d8d4d6335177ae4ac58d865efc7355af9d73ee7b508c08c5bb2431d8ffcd8bb7315ea5de6157bd269c926b50b	1662806248000000	1663411048000000	1726483048000000	1821091048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x8426cb65cf71e094206ccb5291a4f44a097ac54f41e4cf795620ca1ea9a63de560df2069289b2d7a3e29a0cc03885b456cd034b421d7a8f7c99cfeba3ae8f490	1	0	\\x000000010000000000800003bec11c9f268f6ccf73d9a1c17438e56a6b694569d90ccb4c3df37dd874378095024ec0b989ae362c43164a01f6bac5f3063fdaf08082297fc6dc182ff7fb9af4b6aa7f7f80c7ca3cd9f86f1023a9e9126547ddf386010d5844e14f0fc21a74c65641be04a5392043ec2ea93b9de86eaed438268d18fd20b709ff229428fb133d010001	\\x2c72e1b59d7a4ebce5b8fe95246ae2d8f7163631c9349f04ead478687ff8874a94548363aa519a92267f85034fa5223b45fac4e004695524fcf7688269b3e00c	1673687248000000	1674292048000000	1737364048000000	1831972048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x874eef6dd4d20d1a56fe4d206eea2c7fdb5cd5c8898d864e6e55887a72b13fea553d09a9c975dc9e9561e2870c890e0d228e4755479456603d818c11a3455110	1	0	\\x000000010000000000800003ae407b5a58b053baf1b11a678e12558dd1d8596bdbc7ba156f7b10a396a071af0d8001f7d900f58bfa7c2518f276e586d0eb93a272a1d9d25d22d45fc0f368b643d860c1c38db1fd68069262708a27c8c32bfe40c541d73c6b47c53c2aeb70dcbfa7f2dca37f7e1d1141f3f9b16fc977ec0a894240d0aefad5790ffe0b7bb8b9010001	\\x83e26ba6a3da662f142a70310aa91ec2b688379ecf1edfed2062c7e6cee759ec7030a27bd7f3f412f33733ab5ecd13c72710c1d5caa2a9fd758ab017e8dbf406	1680941248000000	1681546048000000	1744618048000000	1839226048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
266	\\x872adad9fdea2acbc476f8c2ee3cbfc97f02273277e98ce1337cdf2fc0a18a1065b511aa99d790331ed5e3901b199137151042a2b88fd23b66726fa249d16ff0	1	0	\\x000000010000000000800003cccf656bc2f0c9593796470db7ff3edb7baa68067aa6cffb058f1929eb914304fd94d2b1d4c6d049145bc3b3eb8d35ca034c2f514a23ea7e67dd23ae141fc32728fb9a7dc10dfb3dc758825d37649dfd35a90738f0f49b3c3887f898a5a04235be93d357bb247ddb7fbb5ec0b153331a3fcacaa64aadefcf8ac9df7c6548ad6d010001	\\x3b7a034f626fa26261a24a01aeddbe1036453a4ea8350b5e6f7230128a70f021bbeb60ea3532a0e5bb1a7b71d41fc3033de7b66f6cca50d812ea12e043b3130d	1665828748000000	1666433548000000	1729505548000000	1824113548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
267	\\x8a3622c3d5b6e89d9a496e0bab1314f8acb0991353963875099eda55697947aa63f20c10fe5bdbf6e0e2e57c9b333e39d246cd06a9ec68a03dadb60d5a0ddee8	1	0	\\x000000010000000000800003b552eaf019d66741e65ae6efb6283dd287e45f19ef346c2b0a59aa563aee69b261cc11fa68fd3c23e1476911abc9a3cdc61b73b5595a93f5f8ae37e47f586fa0966d6d97879cda7faccf50e7638259b73b5fb3a956ee29bb3f731c7d3ef4bc99e09921ee814db2f1159da630c4616242c732e9f8a7fea4f6b94b7fc352643959010001	\\x179a99d8eae59e89f896829152cdabcefbad5fbea2321b74c6e2d36dbdc19192908dba4047b9d5be8d48c79929298ef4c56ba116cbef255ff1a148fb252dc40d	1679127748000000	1679732548000000	1742804548000000	1837412548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x8a9af0103de44511ee334ce37e6e67bd1549cdf2142c76ba807dfd22d6d517eee5011dc1b78c91fa2ea066ff817b5102ff65a0aada6df8e9623c7acda1250924	1	0	\\x000000010000000000800003bd0a78f617e9c1ad4cadf7f65b96fe7c1f17cbe4c935646e450786f1b69eda1bd896e72a9582a572a2e48961524c3e844a7246de26f14b5ef07b207713b834a3e01abf0201271ab557b0f7e0fa66816b3e5737faa98ba515376428f903765af623bd641c9921e71ddfbdd42657aac1317570cfb4d52e94b2e8ca0701d9fe7ba3010001	\\x52a9e46a7a7d870dbe8e73f80022b95e6b850333acee0e68452c948348a5bd1f1149029cb99754bd4e06cf2f4ac32001c7690fe523eb4439985c187965353e08	1688799748000000	1689404548000000	1752476548000000	1847084548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x8c824d3e8ab0bbdde271bfa2c98af0369c6b609108529a4a46a52feac3af808a8a012e10966c1174600eaf05d540214e1cd686763532e0cde4321ab6cc925eca	1	0	\\x000000010000000000800003bafa00a149328b6cac0128ab5855b0bf439a76e78cb07f0ef1a74446945f122f242a06911420fa63052a112d12e4fa22861f4c558b68b8254e2cf6404c99168f8f7eff72856ea71e7038a79ac993b8b6be2434234dfdd1a909d8c4d11350d5056d6337f02bfe6dca1570a8e6a7a59e385539adc81c40f622070d086d84bbc9e5010001	\\x28e50557e5650b4546c526e193a26ab4d231a25958e066b02d226f8a10cb4836a57733631778f4be9ac1ed1d8d60db1759808d72d1e8ee251c10a2f414798902	1681545748000000	1682150548000000	1745222548000000	1839830548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
270	\\x8dca93331255294a972324ad01755979b9624c2348d6151026042d2f1cb761f113168bb1df6304e3bd0f52faf5589155d0068626dca5791f06f03e0790279bf3	1	0	\\x000000010000000000800003c45c6cb034a7e45e3e28e07fbfce533a6d61d1285d66d9a2874933bacb52eb59d28037bf16a777a5b51154e65dd3f6f881f4b329a8777d369db2495dc527c73e81bffb1dbdc818fd24027f51f490731db71ffe249078e10180cda2d9f2fa03d20cb5cc146af160e5231d975ec8c7547865a80f729e87a9214e9963ff2c1441e5010001	\\x4294f59bac29dcf288e8dbc2ee3c467539c24b91ef3dec4c4c7ed23ee2c4ac6b8fe01dcfa41099a3f33c6cb4628ea006cbd084a5f56b5f831863cf868ffbd604	1691822248000000	1692427048000000	1755499048000000	1850107048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\x8ee64fbe8683b51c72917c79af2e16f0bbe371dc1279cdf5ffdadd5ed40759b889d2c5dbfd4de8b893704d7fe8ce3154527545e5f099929b145afaeffa187d77	1	0	\\x000000010000000000800003d8f029db6f1724194eca9af31fa6149b5dd536301ed0dff4b60e4d4c22c74fa1f4e1cff103c1c2676aadca32f4ffd3362e8bdc96889603153d9edc2ace8d664c7acb04a1b4cfdd855b919b993a4de0987d84ad498d54785580c792540b4f360cfc85228634e795ccbcf0f7eb34c43cd59cbb4676539761bb3e43a66a08b7491f010001	\\x8084bdbfb0656a6ce2e4be449f81387066638eaa316a639392d0c35f26b42ac16e34c2c75b83c1cfd964f34f07c30b3a0ad3e936002cb37ea82f52fa5beb2401	1665224248000000	1665829048000000	1728901048000000	1823509048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x90b692ac1c235636614fd67257fd07849458c1d34600878ffd844b5f338964701bdf1e37388f2b9b3d9b9a04aca10e6a8974ced1df7ccd0e5dfb1838fd8bae22	1	0	\\x000000010000000000800003c323bd239a72e83d689eb30e704bff005cb9cfc2344c4f5cede4d43649c57d6f744f4d0dcfbcddc16881afbdf72408f9b726a5af2d287616efca9c724b8d87a98e37a1f96d9b510661ff429ae4a903f1211c45f63e6c3951529d523d3d2e07e0b1f43766c0226ea563965183c987b659703233bace80708dd40263967505dfab010001	\\xf22222625dec755a43a109bd7aa69707c30d2e29895365b9f704db5a86b8002dae8900dcff12ce07b009d20bd6dc203b227e3fce820274a3acbfade00d22a105	1685172748000000	1685777548000000	1748849548000000	1843457548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x910ed15d9918841f25cb5933cce044076f826d534914e3f7bfb31378d67442ec213bb3efdf137a88fe6ebc8094af2b9578b754f422974121b82385aebdcf6c2c	1	0	\\x000000010000000000800003d39a828e0454b938f9a5f665cec404a0b70dad3508b715cb027bf470a3e60e108b3f32ff63b8701b753a5d88997834b9409ab655c11fcf7057ed545072bb18c83464047bb35246c66310ce82c3da7e160c7a6080f1f8f0b0fa81c05cf1f7a6c5bd3773822e30c3bc1e504d7fcbe007566980426977dbd72b2dedf5a4354e504d010001	\\x81312352ffb1e839a97ad686d09fa61b809586f87a542fdb362b8dec0b49f9e1671655acff0cd5df1609ebefb7511a8d199110486fea3e9955c79bdf6db27408	1688799748000000	1689404548000000	1752476548000000	1847084548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x96e64d2c8aabb2b252de334df8c99eddb82b7c59bb81be7784e0b0f4d865810d1d75d03877ae1603998c03826c9f4db6c8b5f30d5587cff645cd11963985916b	1	0	\\x000000010000000000800003c78eb52d7a66740f263040baa92edc60c2943b51e76e8876bdcf8bb02f2c4b1c71d90b2f3747a54b61509ec8a49a2f123b51c42b67d5ed4015b4ede157f0aff11cbc00c462d9d80829d07941fd253fe8ca2f19919a2b9582721e261ba594d29f1ba0080ce37e809faafeabdbdda4ac72345c92a4067d1d865881ae05739f3f21010001	\\x63893a57b08c029df175597bb9bb69903afa16373f82ee3ad415999be1abd413245ab4dffb197f7e8e995dad2f6f1a017beffaf1d6a86ac18999d79b57f29409	1674896248000000	1675501048000000	1738573048000000	1833181048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x9e22055af584f5f02d9636c5fadd57065b5e4bc31c5fbfd2a829bd32da93324c0f14fd478df37460bfa43c20a35b902d1ebbaa3abc810c9ef14368f9b0e0ea9d	1	0	\\x00000001000000000080000392ab8205c96414962d1feb20e0746bcb50944d218ac5ce139cc3b91d25d6bfb364f1472c54381153d6d8faceff775ca8952644517cf7983106b5a2a3215fef3aa5d6a5b014589986a04687a5589c83cd955442dcb801424404a460b60119d17f318aefa1a287c7aac31d36f57ed5dee1e396bda811cca3c6461d6d5371c042ff010001	\\x2efe962eef50fac7cac467a28af33d6fe4c5454f3db5dc61e33f8a52af0ecd5f13f5d48b6a38ad0dec49c5adff0f4a9dc0d48dee3d57c510675b88bec43d1f06	1684568248000000	1685173048000000	1748245048000000	1842853048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
276	\\xa32ea153ffcda66402b47d14f0f62cc6edfff6237a4c1feaded5b8cb044039c00ebaf7ab39aafad8bac59dd8377423efdf197e8573a54d4e5af7fe027f0ddf0f	1	0	\\x000000010000000000800003dee880713b001c82594ce10ecdd892f664d249df53b7d436bb507c4e8044f1775e9773ef03be532e37f39c4a4296f5685f0c866ced78dbeaec52c18398db448ca74c46a600557443084c6a720a09b59dda802bc930afcf50593d0ed3993914a9f741415961f10bd32e5a7a5a1e3194b2d7a96ccefc60271ec2234abef784c659010001	\\x81dc1e00cc712094b987e06e7715b17e14162a9c105912b767e30869fbb675d7e860443f1a340f9f363de372970ae9229cbb16f4f718e5f4e6a1dd623be64307	1676709748000000	1677314548000000	1740386548000000	1834994548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\xa3e2f706bbfdc977b8a0b6f6496db09c0919af661effbbd9a0d457b845bb04ab79ec4d6e0168d0d8655e6c995d448e767c5ef4706d7eec82433f2725e2189f32	1	0	\\x000000010000000000800003d8e84436415e9b8904caa09f68526acf0ab0600d322c7d22b8187d790dfcc058a23da4c23e74e9ebd3b8395a37b6d125a7eddaaa40fba20d16acf82f8d970f49725359a16a49855c3365ff02f126fe9a77dcea2684296c9a327c6da7bd1b4e70c3d15729d8dd6e23bb8bd7254c26de12721f3aaec330956b91564dff55e7812f010001	\\x8eda8a1cf7274fe554f0d9bae38f6335e286231191250baa570bfd377b7d1a643cd04c4d1ae3052f5c1f897e778bde3b10d4bce9e875203a7d2496e35e8c8706	1687590748000000	1688195548000000	1751267548000000	1845875548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
278	\\xa4720972f86b1aed51d6baa183bceb64e23cc206a085896ff0267e24f19210548fd8d1dac74f9c4c9b7a5a9c51833eafc2fa4a09ef9ea9da905eba87d0456323	1	0	\\x000000010000000000800003b5bf0d5db796fbf81629dc4ae3fcd06ade427cd0754a54917fe570450d57e713bd8d791478180353ee5cbc932b2183b7a6bef0fec44bdc8cfa93b18654623106ac189b3b535e7fb1b1496863e5826f5325f2d08754aae407c1a7f8ee1e73ac7023631d0859a3dbd2c966818a4b7e9ce38f01483474e272d439b2c23ff898f67d010001	\\x9b01e7ab5d936d69a43279e2d6ca36096c2bd15ddb789c1a99db77f0db94759d35e0e2ae11b4482d44be6e543d26ac0f1c21ee225d0fa6e4cf8f5481c544a60a	1674896248000000	1675501048000000	1738573048000000	1833181048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
279	\\xa692d4640e1129a1318a7cd3df295a55488d0870674850d43d4bd30486b47482181af544600eed202ef902f8cd28ceab1cbc0d4df07f35ff300ccf6d779378e8	1	0	\\x000000010000000000800003ea687a4b641a81ad69f0f82717351555e5724e84e4b04b5c4fdb0886b5d6e5a31ce5d1a837715425f9e1caa747bb09184de4bfc02a8e6b045062fb4c3224ac97ef549e09f0adafa4a72a517382c7b68ce9056b563e6e3077ea95ca737de219b083a4505a0c4f12f5e2a4707ab8fbe451d92baffa00571f1d56bd40b0ed5ec30f010001	\\x00736adb9c5638eaa417304a31610e1e15e046816dce8fa49d9e78ca1ab22744f349cb20ea41adb604fe483bda1a9cfaebdbf61d94db828b8685492a9d77f20e	1682150248000000	1682755048000000	1745827048000000	1840435048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\xa78206a67e391649a485ae3ba58e3b9e8614ad8c7bd1624a160db2c9390b4879d2a4df6c7e859128f7ec15abd6d2fd41273942d6a9ca4889d4f5181561998182	1	0	\\x000000010000000000800003caecb35bb78b0c38686803984ba00005094a5678f5d56672dc8003b805eae82420c19dd6c753a11b6c9da3cf1bd399e79c85feedc8a371ba14f4dcab0e4c2356a134f23e6a1a6896df606b503b48263f3c9ff7bebded028e99a3ab6a55732cabae009d1d56c69aa5c09b7b6fb61ac3dbc14ee6d90b024a96539c4cad4e727709010001	\\x52784c877d0b51d73156df34c887f65634634aeff9c924dcb73f8e8888c6321e35763d6453e298e017edac7c812597f324b584a369f535a206b240bc0e2bde0d	1662806248000000	1663411048000000	1726483048000000	1821091048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\xab86c1dfbb5006ca28887fbb180179aa8fefe37e5fa6b00d14d5900073a15e236444715cb7fdc91fbd7a2af13160a554c53d427e401d5e4c4627ed935c472d44	1	0	\\x000000010000000000800003c280d0cbcf20216bf9f3bdcaba9d3d67c1951331dc9966539250251dbe245a8548dd6b638b9f35fc5b1bb1975c140106c02d20161912cd434aae1e058045c687743e7947a430dc2860986a35d4883af706f6daeb03929c792ce6e3baf88a2ddd82c3c083fb4a9deec15693d7512062c2248b1fcfd06b0ebe65e33ee197b60161010001	\\x5a76042bc34f0ddbdb980151e9ea24d229489af0facf2f90795b539fd50aae0a2e438458dda2b5971e498fdbad57d584d1b2214d2a5e41e31c1b3bd06ab59107	1662201748000000	1662806548000000	1725878548000000	1820486548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
282	\\xb1aababdb83a02975ea4a7ec9f647b88d8a809eed3f370c0377a468b853ae013eafcb8ab19ea76f4a08db4db3b7c9a79ec293ae0aceb9319bf85db8defdac996	1	0	\\x000000010000000000800003a58572447a5207b87d35539b6fa1a5d62cdccae5fc4142134011b1daee68f7c9a06e0975378df36129adf4adfeb6c905f9190ab4502086361b18ff2ce62ad09f5f87b886714b48e559cabd7324ddc0621244db74530c20a1118e946117494b7e12b36c8fd1419650914242baf3e03fe3c455bf9fb58b8ef97bd76b34b496a775010001	\\x2e60dca8f64566d8df408e288b5f0d08dd5249964ad7cf9b689743b11b6b0063b9f3242e7ef9ed112aab5ca520769ea09f305d05a6bd34a9aa19d4d8acee050d	1684568248000000	1685173048000000	1748245048000000	1842853048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\xb1ee28ab375a61bb70cbb0ea8ed23b4bb6a60d43aaea3847bb25c4341240ec1f39a512303dbd0ac0f7ec608d36e2301533d5df6b86d816bba1def8a085459119	1	0	\\x000000010000000000800003f3a4dc1c40930d11df82a6b62b74f996f761b9b3fd132de43cba29d1d92292dbddb1965d878361bf5bb539378cd5cbde1c0c8e561b84df05bfc45951612e360fa76c2fb5c123d0703114b1ba681ba0e6431f1aab9e8be90126272b7934c0895cd2d3117f73ecfb1ab41ddebb71b2ff7502f7097ada92fd035cc33f258f8cbe37010001	\\x903167008a78a55acd00169048e7968019bf00a51ed6e17483d7d9c1cb20ef0422e0a7541e53cfc76d57ac6d011dc0dbb07c12b463a887b7817650ed2e482405	1680941248000000	1681546048000000	1744618048000000	1839226048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\xb50671265744a19b81cb03e016d365950b802f7e40a23dd13a6680e293bd839b15b7a5529cfdad07d04cff52abb573b3d0194770a63a2138b7d1a33441ff5a92	1	0	\\x000000010000000000800003ae7d138e0a35384813c45973f832604e98aa3287ead17d09cdcf425c62240259b48203812a223578ece6f2eec3117e5413fc5dff8cf2d00d6263c395455eb854b457315acba8d900bee1916d9796f3bec851e70d40422e08b5c230283292d049eaeae19f0c05de3cf3df70c51ebb36988373f5eb2a7c54545b7920674a9f0c1f010001	\\x8a0b7fcac7e49d3d87c6f8de07a6d005a1b019edafb478ce92076d0737ea6dd28af466ffa479a979093e6df46b491eedaccafaa0070a50b2e98efbdaabd4be0b	1682150248000000	1682755048000000	1745827048000000	1840435048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xb59acda976aa65ff0a281195841337442a9b0272d279f2b7baaefe66fd319869e4b316312d4b56c9340766e6bb84c2b33b52f6222ccc17ea20e1160c6dd4f1cf	1	0	\\x000000010000000000800003e74cfb5d5e3c57095b4551f110cec39961c23a81702734b474e719a79aa57aa732e89fbb1ac489adab673d27b45db761dc7e7f01044bed529ab391b7eca61ef7aa313cfbc4a6727a47b49985eed47859c6fb16ce194c1f344551ff145464d33d9b4e63b9dead246f31eef854381013fdf9fdbd3c5bd3b317dcbd7b9a5e50920d010001	\\xdb427db6fdf7be4eae772eb70c06d64eb28d46fe7c7b4e4e7ba66a5f806f0d9ca6ef417e462a8b21a13fa39fe3af08b31a0dc4e35adbc8b060d291859af0d802	1665828748000000	1666433548000000	1729505548000000	1824113548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\xb9f2f27fe646918e3c7586f15e6ba5ebc99a9ff5e2cd1a9d891f7e1ce2fbdf6069adbe624b15fe4f76ae701a26c0b8172ceef1a3d93684739e7ecac906660d6c	1	0	\\x000000010000000000800003c4425a709d3a57e1e7eb84f270c2e390878d8e8a070cc5518f0dcbcbc4b2d048750c12aac0655d91949357219dbc8c119bbab27965dffa7ddc53921ee1e9b6f4aa09288719b906703f343c11d00603aeb270539750ddba190a13ca8dc975f4d81e12b28f866f5da7b484febce94b78245bf86781dcaed82f81417765b18fc7d5010001	\\x7a146ea2aeacc9074956bf4e9a38667e236c907b1d8ad9bed104563debacf9ac72e49a3577a5fd2d92feed61c96ef1a618281296832d50ba2129f9c63932f404	1664619748000000	1665224548000000	1728296548000000	1822904548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
287	\\xbd9a94a3fac9d0eb0c8c3c3aeb0328a3021ad5a60790e1d481daa02ee47194b6b7bc6b727fbfa99fba4ebeaf7f20aaf09bc32e597db7891156cdad2f580d10ef	1	0	\\x000000010000000000800003f1470503c739b0cde42728249265bb654016f0c6b4db0f864de344eaf7cd9837655fc637dbbc8119e03dbc8a0aff0e55c6e582e58ffe6969bf45871daac575dd2e6ee45b7d33735a21dd4e67c030341eb51f7edfb6a208df96112d79e7ac9a0ece94e358b310ed81b1efa0d33c6d4cdca85a530b74243d906823b4ab96bd0a79010001	\\x4b1be4784489df36134929652e52d85f991cb91ab074e3dff07477a050e74236e07bf0b3a19141b2bad41de7b076312fec1ccea40e0c0c94af3d4fa3cdba1c0f	1673687248000000	1674292048000000	1737364048000000	1831972048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xc28a5d7c07f22aa4718b6ac320cef3677bfb00f827dbf0149bbc0d24de21ee1dc969344f51b8a34eaf7ee2c2276ef7e7ed4da044b48d2bbd20f2a19e84f08af7	1	0	\\x000000010000000000800003a66579745a55a600e96a433159b3482dc088101559e8d38a04706a02a97f6a60819369b7e0da7c7d6553a4ab5188c1452c936758292920f1eb4b680937dff46925290f430469eaf2c4311b5d61c7020f45cdd936ee1ffb925930655f8180a97c54892a20029a7f94f2b3f360138c3782f1250c3cd5b23c04b6b7562ef0602cb9010001	\\xb25a5a2578d803255cbce5fbe0bbd338adc8b6e8883040303a3b6398e2a19ed647d7d00358f946a2976e79cf2e2234c1365fe88a96daaf665b1f97d3297f2b02	1661597248000000	1662202048000000	1725274048000000	1819882048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
289	\\xc7920000679f9728d889a99bc5a148cc221f6cd22d17387bc26a9c41148dae074ec60b62876f49371b9d4891d203e299073f7de2557bcef021d042c1aaba2b22	1	0	\\x000000010000000000800003dfdc8b1566950cd3d3c60cc018c14a5a70bd833bfaede352abeb70d15923f22481738f9b93f04dab59454f1c45e863d158d00fe43f5a6d52e86c99e9240d8f49c2644f1eea0e0dc6a11531834754a31681fcb65d7c0a19c96db51e6c011ef877789f23ae6172e58f32fa12e3ff38d033eee46a6ac7ce62706f1ddabf4e4b441b010001	\\xfe6db07a328740a118086f8bcc58cbbe280e518ee0995f39efdf74ad70c780f87f8c7d6d1cfd1835d84753b04f204783ad8850a1900b292347b0b7b1c3e4db04	1660992748000000	1661597548000000	1724669548000000	1819277548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xcaf613955cad857f4a3af6a2b613fc4f74214531388ffbe36cb792adc6210d867dde5bb8ee38f7f86c947ff1dfaec937aac104e973996a66b14aff5edab95869	1	0	\\x000000010000000000800003b2b3c6d5fb7b7800527b622eaf3d036862dae10f59e9cbdac25af5c6e650ab4ab0626ffa34db2c02cecf92d9115c2fc92b137c568072f6d6c1a02526a459def6dad9c4417068130ffd93ef51070aebaf4616759a2e60360d93d3ef7b991a99095ef78027fe169a6cb8335c26f188ef05c908559b1991827e3398bd1fc73bd7cd010001	\\xab99f569f8c8e4bc74db032462cc1557c03009e1da4d79626c7baa1a4a8e2d1e1bd25b08f4bd86d3343b867a5f6344328d9d939f04cd7e6d6adc79aebb5d3608	1679732248000000	1680337048000000	1743409048000000	1838017048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
291	\\xcc5e7a19074df7beb1c34db286194f52520d479f753283aec09891cd7edc392917b6f84a4fc2ef50d079bfd37114a444f691a4208408cdb80e51c0656e23c198	1	0	\\x000000010000000000800003b1ffd80e30aa27e563b8b8969c51517f5d6672b550b5dcaf7b85443bf4a9b4f595ac33849e548d646effa18057da4ad2fdc4b612911b83468a337f24cf6097753b536b658da42ce92780e535a358350c30eef94529a47f725096908c78e4a50e805eb032d6a3ac41b4ed5a3c5fbd9dd5e6f9436a81c624534d9bedda704ff491010001	\\xd9870a08f8172b01cf7a9a611b2042e52b35e1bf3dec7a1a97fa87b215e6359270c29e9a17afcb36a6036c1541dd4483fc198a60f6be11f99bb0ec0de7be8c04	1674291748000000	1674896548000000	1737968548000000	1832576548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xce863470d180e6b0da8f1213f98ea71213c30c07db57c06268b79a75e32ee3a0e3a8dadb01eb3c6898433ad3a1b3306561e7c28fe470c798d200f270b2a26e0f	1	0	\\x000000010000000000800003ebd2f178364907df09c92bc28592d1fb8b71cab37ae9699ef0a2f01b6d097b89c4583fc692df61f75cf14db09dc5e8516ede3ca4de1d5522c17ffd42ba0d2c84403f3890858c3d692b19194e9903817ec692bfe880b979524af22908e435ed30872f6340aeaf1be2937dffa5595e796a6078fc424123e0b6609b6c7251f2816d010001	\\xdfe212b8a126a2e3195c894f7ff58fd5cff96613128b9769ac8009723db6825eec5de48086f5a855a5c98e5cb13a32810cdb200de2f09320f6481ef251385100	1667642248000000	1668247048000000	1731319048000000	1825927048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xce164cee404877b549c5946a99a0fbff7480bab3bb64a7edc52304caf540f7b30cbb9ac616d25681288be22c7e5f652b1df9cc330fc6813f1b8be760146817ce	1	0	\\x000000010000000000800003a657de30c718b01b41a458ae614107879824f8153933276aab8ea3f5559e4ac105f9f1ed743b9c63a7665a608135b9a6e6a341ddb8abda806139732fd705a3f9ec05072f9980c4ae84ebd320c2b731d0028afdbff0ecbb487a62ab48b33414fb07f23286cf6960fc829ef449ae2700b3717ffc120e1ae342af18019355476bab010001	\\x218cdf4623e4e00a7ca75d14aa837e696572375955b1a9769bb81c54282a77fb111bf9d3734f8aeaa1e45b1d846eaabb0f211a7359254b30ab38645e5f87d50c	1667642248000000	1668247048000000	1731319048000000	1825927048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xd1462c5e139b9a27f46f1f976676accfebe8659f8fd5e30b838fb020baf37112781d4bd4bdc164492b212c4d5a92300aa439edad93a3d28cd0e59d16d0af965d	1	0	\\x000000010000000000800003bd522647508bf2c8448a1e93982f9a14676662df724133f6aa01f790ff7b160c8f056f7d4b7b25f26c5e7e2fc52f101c5335d89e0b984c551137c907e404a78692bdfc00ec250f4dda6d7251b9eb9ba90ee8407b68ebca1362bbde607163b045f68620ab82fa86e3ac2d9bac6edeb160816165eebc0cabc61c4e1f51b42b8a51010001	\\xbcb9875cc40fda17162c569e265a583c01831702a2daf898c2e617689fb6d83af1c4a00e69205a38bd8b0bfa53b35e2a2859b533cc226875875afe70c8ffc900	1674896248000000	1675501048000000	1738573048000000	1833181048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xd58e83415bb4e44bc0eeb3c9085dff31b6d8b299c33f83a0a0078f2df16c6e34bac62ee07b0016ea9db2a916900fcc895fe18341128c8d13eec347b5ffdf66d5	1	0	\\x000000010000000000800003af8c0966b2f2d698c384d73c95853e477be0367967b78c3786b1af9c67c97beef03cef520aca10e3ca7b27a3a823d83a26764cbe11d4aa6a749a69f263e470985c991a4c884ced4d06493fa48f682efa26fc4700b44040d84b7a92bc8b2c4b9f3bbef57fc764fd36b245364479bc6f41866900402ae80236dff0f3734e066f85010001	\\x7a4d767b5fb003b906766018866932ecdc23497e62f4ca27e317c4b85b4f2b123dc5084f7fecd7f17b5efd1234e2ae44e32490c02cc5088fe51022298767c402	1671873748000000	1672478548000000	1735550548000000	1830158548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xd986cb0dad4ddace4eef35b38ab67156e4d7f3857a01fcc9cd82818a9e7741f0ff9291981b407c2df9121172e18c453127c93e98b1fa0f5a3503b4f997f34087	1	0	\\x000000010000000000800003af37855be564dadd22339974e2284cca639bc3c9fc14205686e827e5abbc2e73a3ece2f22a527bdbb7a859cbb7f58683d35ff67bc0b17218ff2088f79260370c0e5a34f948b9394e4f219f09eced04169dae49d16b4ce26cfc8a0f11c242a5e25564409f7aa295465771aee41bf7d5803774f7aff5e28725fa67c6656d85faed010001	\\x51fd738ff1f1028f475e2ebf0aa4dd791f19580e2bd4e5c66dc375586faa8a6800123b0ea15c694465de0399a8e6eef46cbd556e99fad5f073ee82f566853006	1677314248000000	1677919048000000	1740991048000000	1835599048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
297	\\xdc368bc4b8559e04959e1bf17f604dc9b276c9cdd9dc5674fe49c08e784138f1bc93c860d90b2f3bf9dd45cb76c03739dfe4438b7c54b00849c6b857e3fbfc5e	1	0	\\x000000010000000000800003ccf9b185a572c7371fe76d3543e344f42ef3d0f9952f7ad054e25248cb9a7b660f38258c5ebd32c1e1615f0370b5642fa0349ce20642585a51fc4af2bc351541bbac417e76e4e749fca72d29e428c9f91ef4de468d28c201ad3f193b9248dc98163f51acfa88a03de8c10d44d0391fa2ed1c7a4938ef9438badfbdb6e0caac11010001	\\x46c4b67f03acf232f44afc6a7bc9280fff20e2b52fd1233685c90cd820faad5a268ea91796b893b9ee5e8cfde4f1b6a98976ba636bbd8ba97281725ac791d609	1679127748000000	1679732548000000	1742804548000000	1837412548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xddca16aa585bd2e17e0a10df111666ca1cabe6a5d80bc6fdd71972a93454487df755890f6da879ed3a61bb86ffdac38a2dc4f5afcd824c3f965bc8af52ff9010	1	0	\\x000000010000000000800003ec3417fd530fc9913fd7efe7bd2b4e8e4a14ad67e31892773c8a4a908dc0b48630e1f12fab91122c82eddab91d3d52641e2591cc0679e6608882d332c45f3378eb9ce97ca8515442c3fa9fc999fae89db7cc349b5aa1df14715249516f69b83c004b383e5f58dda204643ac6cbba4b44695795a942d2ff28377be10e5c941253010001	\\x76328ad062c116749485c8405804c12d7f07bd2105481f75690c785731b73a22d3baf992ee124221805994a583401f98d081b5e7d17134227d26abc6fcad9100	1671873748000000	1672478548000000	1735550548000000	1830158548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xde8e291be88a090cacacfad235289f21be300313c121110e6bd0f35020393d4265ae2777db762e54688e08dd93a88b819ef52d1bb7c4eee03e8f96b227eba89b	1	0	\\x000000010000000000800003da4478728ee54696125d2334495ff5ef44f166cf121980e07a1f88adce36bf055856a635e2f1bc70a147e06392a72ca78654a56c7ebede8666a0b3a2dcaaa19dbe5d0e72b5bb821daab00630ab368f7736ca4e478beb8dc5c1e7ba1fee26652dad52f342d62acccd88fcb8037b3c17ea978cee3ac22aece598671663c530ba0f010001	\\x28feecd232286b404ba9dc5dfc15aa8ac3f07963fba776a4744c5df4070ed9df564666b7a826b6e7fcef8c3505789a25a7f6045c48af76aff3752a040a76900e	1681545748000000	1682150548000000	1745222548000000	1839830548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xe16aef9d5a1c80e953e0b19a41f204ec6fed97a5edf78dce283a8cf7ac97f2c6b76f8fd74f6df468dae1e4336e7b7f7bcddfaf9efb72bf003b40e0cce286102e	1	0	\\x00000001000000000080000390e3fbbc40a63f54b96ca2439ed2a428a36dbfd45bb157a6c2c9fcd67b458bdab39c4b6af8b3e249505e5fa341ef9eb2e3e419cd4c85c0cc9fae6890657e3e623ecfd75d8a26a88c0a57b896764fda58426f1b1d1b9c007711381e68e8972c55cbe68ad61fe768f1b8e73c7303dab84dc863bcc5796d59ac6eb41afdd7831265010001	\\x142e9a5a4c0d14433a7d21afe745cad1e7069e07ee48e1d88953b8885efc7e4dac4f142376c5f03371abcf8cbd72e404c41ac578e359f0d3beb55c65d90d960a	1673082748000000	1673687548000000	1736759548000000	1831367548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xe28aea8332629b8a5a66a5ceb7f6f0a5faf3ced17fa8ad1edf47766eb8ddd896532a13d707d1310601afccb0c2c05fad18929b37abaf27365001b1343bfd193b	1	0	\\x000000010000000000800003e6740f701013792d1463630efe042841200158d5d6b69bd3a935728cc4103e479b70d4bb8b2ff977cf8722468833daf251e7b191cb40b468dfb1b8c9ba642149906bb59ab22c744a9e42abc8c3e7b081854fc0276ca66a02e596d01f569c92cb0afa82850ba9f732a43f3e2642cdddae5d93fab9c042951e18e540d4d4b12ec3010001	\\x2f023ca9a12b62e019f91a67d3a7ab367ae133136393195bf1d3576b27c8e0321a3181a900e5e3c3843437a88075eb3bb843440f8cf09d7574028bf1d447b00e	1690008748000000	1690613548000000	1753685548000000	1848293548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xe4c6e8882e9be2d9147883ac6872f16f92588bf26bb0d47521fa3f267fbf7a67a24fb35779e8216633c1c69c70e7a9a3c8daf9d195f5ff9609ecf65b4fe10590	1	0	\\x000000010000000000800003bc4af19df5a10983b985baa929cfc69d2fe2130b5ca1c37e37677bfb8c37658be82b9d6f84e24a8fd7ec0edc0b6386e624e7966e53af26d75328e2176fe06c42b4d9871cda8e0adbb4321e3b1f189f9ffd1ffc22c61edc8f21b128f58cf5aa2199f214d09a6dd1831aa874b3313aaf6c2a6d54f41e6ef44972571fd60a5b6861010001	\\xa72b745544e2a6dd55b17a491d0b670fa8ce7a66946889c9709206fcfb232c98019dbcbde4636f35005b0ef169d4ee74de0b2e0396d6e51fa4c1a072c6e21a06	1665828748000000	1666433548000000	1729505548000000	1824113548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
303	\\xe452c16f67bee9046831a3846ef6d8f463f0752c7e9009b23c016de0e4b775cdd6361e2ae967904e6b786a1bb96b2369e9f147e92df17b55373c3fa20338c59a	1	0	\\x000000010000000000800003b236fb9205f9d2dd6409279a007f91f670b86ec5570e1b7abbeead5631dbcb22fbcad00cd4787fdb323bd703f847eb5f47667bc1ee4e3c2bf5d938771a775d5502fd4f7a173da6e9769ad10678fd2aaebd3799cb711e6954f96341cb7e56704f655c2919adfdf0c7fba8b0cc4b418b45f695340bca4aaa2745ec5b8cddf72437010001	\\x21fec034141377dd451a0a6a30dd04e60134c233ec0ba62a2f19c52d353ea0509da31c3ccb8b7e7363b479467c91f650702c1b581817cfd7f63de3b7147d4b06	1665224248000000	1665829048000000	1728901048000000	1823509048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xe5e60a279d07a874f186b30ed46c0bb7d11894acc4f04b6a8ee95b3d143d7e1c66bf203bc702a26cd80b9f0d890ad6c4f7dc4f77adef0419edc1ed65f8c25868	1	0	\\x000000010000000000800003c7a2e2363ecde3e1cd8cf5ce87f8a7af171dc3eef01e7e2a0a5ae3862fd8b414658c87f1c2faa17b3d965a002eee82dde4ff8b30aa7d31e4d0a50a0a8427a5e6580c63813e1aa3f072ed115b6d53016cac88774cf3215e6fda563897b18e66f17a82daa642c112e56922c44f52dc91f8dc2c7c04389479a82b21d21ca1577885010001	\\x0fc33b2a114d7e0797e688b2e9c27f9cf2efe051dfa96acbc1827947b4d334dc4e01a2b805c74bb6476534006b001dd11b6c8deabdd1c488ceef80527f18560a	1665224248000000	1665829048000000	1728901048000000	1823509048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
305	\\xe7a2b4c940460528589138d2d24c086dec147f2a0e271011a881110477fdb52b6bc24998a946b818db7ddda311c09eed90b18c270b0b69119d086a179658d27d	1	0	\\x000000010000000000800003d7a654d99ad790330a6dbf7fdcff3e72aeb198bfd13a5385152612a3b537384562d61a1ee65bbd325f90e838cbdecc905b8788d637b00a71cac9f17d7dbc0f3ce63fd4806e66cb79c7b6c1ce69949cca527b8cb6dbc0bf489499b550bad784e1dc33924e3ac5297dc75d341aada4425d3eadb8fe488c3b82c1d4fa680a997495010001	\\x4c9ed33ccf916a321eb4d8bee44d467af8491915fba43e96a9b207fd363a158139b5461be4d515da0a43e8f35e3166ea85fd6162b6de5a009a13d3e7abff8102	1681545748000000	1682150548000000	1745222548000000	1839830548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xe8968c6f06ec9b0d4be476c8da09a54712eb23e23deef6ba5b6a5e9c175c4681e9078cb14bc48c52ba944a553106e25bf7aba4aa8fbeca0248494ba44a3cfc8c	1	0	\\x000000010000000000800003d568694b72caf026f0948a913b7687ba0e1615bceb9e19e29d54ef1ada70a0ab4b98d85a3e0e32e9f1627583c00245ad49085fc6431ab4b8b4305677dd70c7d4f20a37316008211e5d6c1f07d4b9d044f73a07b40a023a497aff088373c6b607746601376141234bb7e3a5debc3b598f3d2097c3503d1105a3e08af9e36c7e43010001	\\x48fece76b2e52eaae33fcfda6136d142cb42050aa2a6411165cb0bee32c991fc25c12ccbfd94ecf33abdf522ea05dac43418ee0781d7a7a5f7c8d3fd662d6a0b	1687590748000000	1688195548000000	1751267548000000	1845875548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
307	\\xeff25083226c675aa8dbbf4fb3f23d901ef43f38fe09537544b66379683cc258ffa0b8d2b9cf8315b27f4bedca2f5d99c77baaf20657629a8ac7e00f7a055244	1	0	\\x000000010000000000800003d3cc04ec088ccc56d5d8f4bd16b43503b41e6aeb8f3bf4a695efa9b44292715ff59794ef56af5c19755cb25dd2331c6b67b84db7ef86610ffa2e509f24e5fa5653c047d899984b6cda568b57dff0c6642799c9b5299654d269ab463d2fc50e239c7b3f0a50a7503a761ece77fc460803f0ec5d7aab6bb7841eba0149dac8b23d010001	\\x8b35547f45f3a947208b1a45e6a3119a7ea8c58812d4f7c3d60a5fd3e56c77a6ae5164ba0570ff48795fb660651d227531da8ead09b1c6d3da00f681ca0a5c0c	1682150248000000	1682755048000000	1745827048000000	1840435048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
308	\\xf31e0b91a13a44cd90857d3ec809aea01628a65664eb6fd5a74cd8ff9fe6d8d8449b750abb5fa92272244a351d77b012e1372e7a5478aacc79cf82816c3b589b	1	0	\\x0000000100000000008000039b94a59c1739a96117a4d050998ade246b6a43714c9df5209a4382e674067f839ebf4044d8da630680af6d1decc6e18f21322137f46bf70b74357bdc90e74585beecfadb66afbc9d3bd95ecdd4d8e7f6c25e3337d459e6f8beb670fb76cf63b77dd1ed05ea48c13207b3ae60d38bf117d2632bed2d4bacc91b6ff8bca995f175010001	\\x7148df01ffbd9e798ed205a1b7ed2f900a8588fff8edbbc0769aa0535d07ea854fa39a23a1627145cbf0d54145be158108ef861c897d06215210b94e6c6f3200	1683963748000000	1684568548000000	1747640548000000	1842248548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
309	\\xf3cacee3ec8b820cc91879442e64e664b550c545f7d977e62620c3408b27cad9e084baa2288e7fd820cc2ed818b5b3ef73ad9ec0a94b3b0346d7273627c9106c	1	0	\\x000000010000000000800003c11a80d8990f46b2bf6248282243f290b4a135d0756957c2ab256b4798c672edbc73c9d92648a8a9593e27391a315d7951b81ddce3bb95f44bccdaa2eca871dd5389e2b3f3477d9a6676a7fa1f7c694f80b3c8f3b795b30a6e2cb5191e3a8a20099ee45eee48bd72efbbbdd1f6572a327fe083574d41875a6c2a7b564ca52c99010001	\\x38874d94d3336e300dbe4921fcad016d94b16a83a15db549782ada2299512fb83063d9c0035d55a5891a5ba77fb09153682ca48bf9d37a9a3b5671410482c70e	1684568248000000	1685173048000000	1748245048000000	1842853048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xf5bec7622d07de12295ef78f54406ef29755df9c4f613355e376ac64a16c1d2d143124df7b812bc59902462a52bda646aa333d9c03bbcce68294038b6a4e5a1e	1	0	\\x000000010000000000800003cc9ff579bbb42386b5801e63c46cfe0b28423b0b05ebd203a0937bf1e564cbdab7b4231a9f1f183cb38fd2619d7f6e5e914e63a16a79f7dc738d2f4d6b0c1b35d214acab3ac301140a1d8f34bff998205bc784dd01c7e6cd2cc328802fedbe95a781b8e963f42c9c96d88bc72121282555b84352ea7863a5211e5dc0ffcdb8b1010001	\\x148f85b0e1134813ba428ed4c90a31c4d8af8904fe96d067ef30de88b2740c103f739c73af0f121522fb3026a7083b4cc56c0bc04d8d5b5b4adb47e12062d709	1669455748000000	1670060548000000	1733132548000000	1827740548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\xf9cab6a584a3dc8b91daded202aad99c77fcb83ad6903d271f03ea26fc59789de0bdcc3ac34eb7a7dfa6cdd78f91d364d6861c9c5308bee7e9cb0b3321127d44	1	0	\\x000000010000000000800003be912f33d1e137dbdcd1fceea6b514a0094af979ddbb4fdc51d0ea7487a9f6b36db080de0e2ae6fb187770d4314b3dab33b49acf1af85fd32e24e377514f222b44420a14ba58811da656dc019667a39d9a07a56759d93e221c2d97ff8b976390d90a9b3d90a93503a4319bfd03671d4f11a441461ab82198a6dfb82097025975010001	\\x1c2bf653829a03c2dec0154fda518da5d042baf8ff0f591d1fc408b5898257594ccef6a90207101c76d56d97d413532e2960e2777bbc7878e1cbb0af9988c90b	1678523248000000	1679128048000000	1742200048000000	1836808048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xf96ed332ac06bfb33b0afed61b9816952e416571b104efa4197ad8c5f797a4efccf0b330b942e4812a6a92185892037529f2bb512e2db357c9e0a9eef20fab7e	1	0	\\x000000010000000000800003a88936e5fb31aec0cb136e533eea0dd8460687aae95f0239c13d24a8c89a69dfbd65ebe0f86be6ebd787bd0a5f44ccb363e0ffaf98f1e3509eef575f87fe57a01fe8b0d1b864a858e3bd62d919d6070aa15e8a5f374cc5b9eb2e995c557abc5a7c9e9e4eb0d35572d6fba7654be823e9749b876a13385ea4fbf7e73bc305f4f9010001	\\x508582cc893447bf34a70180be67ae5186043c26057664e37493adf7591f6a360ac7a7fe6cfae3b47bd4617f15524cbf4e79435ee594c81c9815e42967d56506	1673082748000000	1673687548000000	1736759548000000	1831367548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xfc3223d6f0f7d3851611f7554b6a454413d33fde80632596be95bd43a53a0c33f2807a0443586076314c8737ab3655e16c23b866f093e11213985472eb07f9fb	1	0	\\x0000000100000000008000039cbdf875999c903b3d4d0b8939f799a2d03a665705043c7ed7ad9a5fac5ab45fb184475c0d8bf16d362b6ced7fe8bdc86dc1ae6a39566859c84c10e455839cda039673c024054cdbab185af1392af0507b2a5ce28cedd722187953367a39d5320f5351845c32b79e7d96e01634e0e0d932eb50bef226b0416e7238eeda8f36cb010001	\\x5782907b24e96a52fba180902430ce833651b5a13cbeb4e5c8b593a8d4815cb3034ca6c8a7adda13eaf1c9d2264731b95f5f00dd96e4012d15d70b20bc33e80e	1667642248000000	1668247048000000	1731319048000000	1825927048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
314	\\xfdba0c1f9ce22670f9f8284d745173819cd7addfc216ddfa004331209c6d67c1ece59d30c096655375f15ab968c03a9159e5ce93c9ead6b92a23cdba31029554	1	0	\\x000000010000000000800003d08cfa84a127fb7da1840c4b0b923a681840de114688c6a9b1b9336a31ee75923e48c05ede39ceaef4dee1584cc8880ffb953eb09971f72f778a561ebf2e009c3f0a5bf5988debc0e285b613cb075d0d1cd82740eaae4e3af302db29e912d58f4e9beddfb5568a10e6e8aeecef7195452c9c7502ec0e8795db586e240fc87b0b010001	\\x6be379379c1d3719c007aebffa9d164360e31715b7620800c8db7fd69836cd573f30f77d785b3a934a0c8d81886800c77d4dfc6c93f599282a0b393a9b1bbd0d	1670060248000000	1670665048000000	1733737048000000	1828345048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\xfeb2227f5e66cba4dddb7471edbf971b84c7fba0604bf777498f873e1a538a827bc7274dc07126f5637c7bbac3e78209b1b841401d37863968418ed3c0f965b5	1	0	\\x000000010000000000800003fa9074d49c799fe236d645a9d8ae985e259af731954787b435adf24cebda87f01750f55647881b22ead8436a86041984be3095c92a06e3959c6e524f8aedd4473ab612e77191d23e938d83935410133ae2ec76131e6bd2d09f44b9379a84a811d4f747216f9d0b1cb8574304129697880fe90ad67e337a9cf2cff3775f3c42d9010001	\\x53e864b1177a38ff8e9a65cf46a08a1ba4a7d33cc8bcaf56620e7bcf8d0f041fdfb7861c64998d2a10226b0855b806e37bd9ae6ae10587cc513c28826647330f	1686986248000000	1687591048000000	1750663048000000	1845271048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
316	\\xfebe750ecd5f670390272ff480199fbb2b231af889d95ca5f4c7f4b4a360c1e4689d5c7a9ba7eb6aa487837c6ecef344967f1034472f60f8a8dd8bed97bc5f6f	1	0	\\x000000010000000000800003bf38f90758ff4691557ea3a5ebd27af0c648648e1665a7b3095135b5d42cb9afd4b4813d48adabc81ed156b0fd0c3fb0b2ca747b7b07f26aed44168b5c1ff0c91eb414ef02ed8351cb0df08a6e25a3167c8960da9fee2717856334472a4213922c15bd2995432fddae5e7e3ef6c55f8fab6f685a85908ddb64e7447faf7308cf010001	\\xb02b57b5c446516767e0ee756e1877f45635469fc146b2c920bf19d2dc1cda84650ff2c46e0a7b5b6b029a5cb4777ee2c9efe12c8044f60df69b8b9bec23f203	1679732248000000	1680337048000000	1743409048000000	1838017048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\xff6af1928be86a8b70600cc2c1ea532e1884e4080fb280fe6faa6eb6c8bb817230c7b521f863c6dc8e0bb304b1fdaa43a2e4293ead83ec3626df753cb50da4f2	1	0	\\x000000010000000000800003c7ec1c497b181eb89c3a411fab8918a82801f1c3178f71a558327b470a60cd0e65dbc45588ccfc25ffdab1f1f371ad344fb695801fe59dbdb2e8b024c5c25e42efc3e7ec26e68b5c8e812591f42f67995059a023e574580c2bb788f34ade58e780ea86005bc6ccd30ff9bd5168050b0318e5057fc69035154bc64f71590775cf010001	\\x797700b41ef757ea85708cc9446c2c3aa78b1e7e8f757d89df0f711927f6e56779f6d5c480521df764b228e199162ce6e151696ba1ddfd39a55dd6b151bf2905	1679732248000000	1680337048000000	1743409048000000	1838017048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\xff3e6cc829ff4b42aa6daa0f01b763be807bb15734ad0c2cab0f0082c7c2778cdf1182cd77ecba3ef82acc2fcb7cb0e54227fee4d46396894bb37881776e077d	1	0	\\x000000010000000000800003acb18c48dad1e0c033e758edeb3848beadd64e97d0162536d23075280fd417fde8f855e5e3e650cda8d28405570ea5da50a2a7c38d8f424387ff288f7a112ab60ca0d2d335c58dea73f66e5b7e03ac8bed4b7d85bad0c6f880b3ede7c5938fb14c50edda27500d632d928a89276ebf69b1208cf18b82f197027d583f0b147e63010001	\\x083336be52464fe8def6ba425ac7cecc54695b7a088d7d3810c338cdf6525a0a7be0ea1957bb6ee501d93fede5c7868cf6007c0237e00827286cf2c46c26f706	1686381748000000	1686986548000000	1750058548000000	1844666548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xffae9107cad25d8093dc0e0a7422e976b4c15e66320d2fe057bbcf134baf6dd623c3a977459c72e2c5cd40d0a92e7cabd4907db25b9c075915196a4e90597d5e	1	0	\\x000000010000000000800003e3c5c7ddfdb93bd8f608e5c3182e705274f511b08d56378ffc70aaf33fc57c5ae2e6c6c9ca553aac09017b3f2d319c32e78441edb02f1eb8969e6fcbe6f2663536f46381164bd8ae8de77117fddf9811f25321d01ee09a3816c26f8f38347f6452176a7958a85ddf4eb0b86a608a0c01b9582a0d3250b45a9a92c62288465941010001	\\xe770c4e0183a459d1846d5c4faaf2a8675c9f6683e1d518968f6f71e04039354de56793e78b0451070ed215bb649a53a31d4ea49e0c5fed6fb541b7b6e2eeb04	1672478248000000	1673083048000000	1736155048000000	1830763048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\x0387a7ea27aaa3880debcb2d014e579d81aa2eca11b552602ec074b7e53c65a2539597eb1bcad6ef03069887f8d213955d7208ed2194a6c8eed4ba890ea2ae72	1	0	\\x000000010000000000800003c37464fdad293171f458d9802badfa05fbe7bb4a15cb90f380bfae421f8dce24065988cb2e34e1a4f65f3515b1973b052d258d40583f6d7ab0d17cff19281d7d8a43105f4e48f38cd0d2167636d4baac41319e5f79b3cc10ed864ef0422d01914878688f00c6fd5b5af2f73151d890ab840c5df53bef79b3994932067165393f010001	\\x8061b762eb300448866158e4fae5ac0a332fe35524853fd2c6f1fb7e25b66c1159479e48b8af46634f31d7efc714bbd9d3d9892a4b221d9fc6f0f85e87366c0c	1677314248000000	1677919048000000	1740991048000000	1835599048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x063f471d92c5f2e279ededca4b83e90c670999038f0654040d092ca0c34a3b8a4b18de7fafe370e953c225fd132f79333bc17184870a783cd35a1b076a3cea24	1	0	\\x000000010000000000800003b024640f1316308b21a52b2c5f20298098aba4325fcf03efce8185234b1a40b53617a55f74c4347890da11c07be6746ca68803e94bd29acc49b017ffb7fffc6c7f865ff7111939270de4501791cfb0246abd082f9ea1b247911719100209d528154b2bdfbaee75cec77eea564e4ddb3eab3521478a9153cfc1aaeb3356b1d857010001	\\x5984f3bc7856161c506ac0e666a8d35e9ddc12f31493ea04d61467daa606b08654596f20ae4a20bbbb9fa6f37aa35495d3544d4e152f7c38caf0069754804602	1673082748000000	1673687548000000	1736759548000000	1831367548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x0933b3dff34d747e8d718281e202bdfe5c461fc6cc4fa8f42589ca8cf144f5f883f8cf5b851edfcabe184aae1bb61797ed98aff84f140b5be8b03ecfb0e0d7a5	1	0	\\x000000010000000000800003ca06bb2f5de9ebbf83821a86cd18bb272cd1229251c2226fe2e7fcc8f8af35a77eac79012494dcf866c481fb667e3f9c291006b8937d0a059d4c4b15d27c6cc05c55b546d2a67814926c28f2809443f2f18b353fdcabe19c0546692cca5b44a4dae11aba82adee8963136f39a02ec904eabad09db0583595e8ce9b97923c7bfb010001	\\xff94afe1faf9c9695292066a11af1c076842dfbbdf5947bc70376602798467859f8eac821f4f52a5807b31f876fbc86fb543db763a56ea7344e4fbfebfa19208	1677918748000000	1678523548000000	1741595548000000	1836203548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
323	\\x0defaff9d64a1a66a50ef33ad6e4a3f182cd12957d361475cea88a64858534b30c653da4943b0c2674c93af059b9e48a2529c9eb1f4e1ddaf89aeb2b59e161c3	1	0	\\x000000010000000000800003a6e16510a614e3d34f0581d3ac7f1b331d07ffe7f08be976f03ad64a185c8277b366adbe075c170348bdb68cf5b7b8a4a39b174c8008f301e7e884fe9c59469f7c02d9ccf7ce1cd56f0ea6ed8cafa5608e4e128dead1cfdbb9eeefbb7e028df98a478198f48b661d01e59fa79f93e57e56f38493d0e923679792bff13768b2ff010001	\\xa063ece445b373a67516a9f98be6d96c17c178fe862ed7a6a7940729b0180ffd025c20ebed02c307f2fbd0dfc94dc956cb6782acd38e6a7d9a1591f805b1ac02	1663410748000000	1664015548000000	1727087548000000	1821695548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x110fc110ec637b07fae963983806b724d85416b36cda229b8a2e277b945ca7b881a4661ffa868ea6468760b06d02790a0e5bfd94cc126a95c34ccfa379d684a9	1	0	\\x000000010000000000800003b62911ccef99b83b733623599c5ddc85500919948e66017bfa0b8ce3532a855768d6a6777a02f3f377c29244cc0ca8c47c535443050074ab8c85e5e923678d45012b426a453fec84210491cc1fcb1c874c84ebf80bd3f781ef439527bf36e9bee81c1323d09c5dee57e15928ef1b55556bc2bee189e21a9ba8090c63d89ac4f1010001	\\x1ede94125111ca31ee222473e5658b70019bc802ab7de060482a1257bfbeb5ca9d28ead19a019583659d36366a2f17cf0d52e2f8cad0ba911c6e530a60218406	1683963748000000	1684568548000000	1747640548000000	1842248548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\x149b14181880e8e51f3c4c8e9bffd775cc99ee93264f957c5e9bd3f6312251a74f09f297132c5f1849c441518600d9896438e1f6d2d796b0674d62cf76a8b74f	1	0	\\x000000010000000000800003c3529d70734ecf08278cdd8cfed4ddd8e08ecdca4d3c3a0bd324d2cb96ae891cda4980073193eb86f049d1eb1c8e6d676ee821fdec35a4f4da15fc239aa6bf1dc82182c044f3c5a938928ad2cd835fbe5a83a321d32917b6bfd6b43c7501a2bdad28a26b8addef6761b589834e3daf1e1de7cdca6667dd6ed44c9344f99181cb010001	\\x507d80754b59bf7db88589469ae80d67bc25fe9ef007dcfd2da2e605a1e17cbb47f59b168a28d24084f2942577275da7886741f8e5f88ef344895409d4f0f003	1680941248000000	1681546048000000	1744618048000000	1839226048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x2227c6d9754835da5583abc2e86a673b8907413b34f1536ced6f6373acdc0dedeeeb258daf7e86f45bc476c66465bf4f3f4bfd1cb3d7c92c4b0d796c43e2573c	1	0	\\x000000010000000000800003bba1f8422674a2df62e4f26f8e0c2f976c911371047c5cc2cb99917220d2bed6e52700964cb24d30285ae67f1921685183933a1965e594c7b3945bdb3541b6c2c1514f66b44d036fe08180d171fbb27dac911a4ca09f597d80759ad97170c2f4ff39227d8e32195bdfd254202a9d35ee104c28154b780b14504f1ea6d37a1c65010001	\\x83f9b895453991366aa9ba3b21bf9d5c1cb8198ea5922c8510ac75e84f7d7bc50db8e5adba83b43d5fb134a1241d54987c2ed75a7842097bd762e23246263000	1666433248000000	1667038048000000	1730110048000000	1824718048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\x246b5b524848d2b642d2bc759ab0ec7f2ed36510cefe71651c60f168dc182b3f7f028a337c8f7821cc80c073a44de0042c0ff23d87e2ac93b5171bbffceaaafc	1	0	\\x000000010000000000800003b806af075f4257b9998288d8232c179ef5df58d1ff2ae715180cb09eb6bb151081867283f886eccc5390e437a091466479ee6c4e848420d5de2231fcc47cb870e285a20ea77523fd0307939deb4fcd2ee6cd2555493cc575a4ce18c39b71025687e95870353a5f8e59e0b0b19ddd66884b3cff65b87e44529833e17bf7644cb5010001	\\x3e8c54aa7bc3cbf73543c659c7f2d13098d74efc1114de6c196b0d1c7306bb7a3d68b72662be1503217f5746f61c57ccea457fae55533817bf64a872d3897f06	1671873748000000	1672478548000000	1735550548000000	1830158548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x27c37d42e1d7949f9e504be125dde7433c9e474f58600a6b62f53df40da5e190007add972147eb225171a9403d1d71e9b978430b3137fccd595262eb1afeafc3	1	0	\\x000000010000000000800003b3deb080ef1abf19dea92b24ec6791f41a31cc80f3a5aa766d398353e1ba9a08e7cc698d63311794f4d7d2918380595093027ce1736debb1314f48a1f28a27c061a2f97fac069af7d4a35a7ac40b70047c0e44bc71368007409868a16102effd2c0bf05a049157ad39a006fdac06295a6e1e34a4e13b198d66dc89d71643fa27010001	\\x2703320872c7313758554ba1ccee92ec6455671882437da202fdaad131d0ef958ea3f9ef147b2fd349196817cc138b3d573cae5d1562cd6a66faf96da6bfbe0b	1662806248000000	1663411048000000	1726483048000000	1821091048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x293f94efca5265e7d0c6a8bb053e84cc34ceec2a2b9886dec533ca6c3495facce33ccaf6e06a79fa32a05551264dc91f1f1accde174fdd9d323084f99b3ef251	1	0	\\x000000010000000000800003ba68379d35fed77a74be9611fd101398f58477cdf1baf44eaa9015760fafc40da3c95a4ca5484d3f57c8395e2c69eb98fe92ecfe9cc96de966ffed8c028cac0d253df041ec1fd669e48de4f398f8733d3da82f0dc2d2a95bab5208bb38068c2e31afa8d46dcd0e39e99a55ec73473b145aea83c1b4292d37c9da108ee9228247010001	\\x5455e96a5ffafe6950a493e32b9aac9f9935d0861a11243a1fda125da6843770b8f33a61814bda01b87ed3239781ae4409de8e9ee220a2971a1e06bc6e05ff08	1665828748000000	1666433548000000	1729505548000000	1824113548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x2bb748c7fb02a9d876b1095a26ed827b30ae16d64d71ad6bb984a9c712244d1c45d4f5446093d39f35e0cde88595cd4e2c7883eea0ae317d32854249311ee0bf	1	0	\\x000000010000000000800003b1d034c1cdea27d873cf20b8428c825ff97b8bffbe2c37f46ab4a72c7037b4804d3cb74059b6ab1d88a1c116d20829336e38504137ef327ff9baf5f62ddca6129d2d1e92fdebce6d7ecb10eabb9a9d191901ee9744503f23707930496128df4a80c9bda73784ed5f4d6ee41eec35183f07efcd12d584af475e05069cd4f31b8b010001	\\x8b28727488ef863a26819459dc7792a796ffc45fd9b0a018c0d964d57f86b5ac43e66c5efe9d5a0449bd4300b2df66c02972f7600bdb689980a357f19e5ac202	1660992748000000	1661597548000000	1724669548000000	1819277548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
331	\\x2caf427e101258a8e92b4a0e440562e22c60d85f0921c80f423c2fec49d1c52ad86eab5c25335fdd768de81857e3c88e794872bf3c789cffcb1ea61eabb8adb6	1	0	\\x000000010000000000800003a0f74dab4cdd13380ecdd68a010559881e566eda8a02d51cdc0c11dc62210e12c46a959193a16254f7be16a80211ad5db88ecd00ce85bb43eb7e44dbee464cb9fb7306d9d7c39e04a6d7c7a78b1692862f905fbee7182a8d6cad131ae0ee2341556652311bf15fc688cbcce079dc7d5bf08d39dd644591c501279d8920a4906d010001	\\x9f5a2c313712db499d570db17ac3f8c83b1b59eadba8678c680ec2adfefb684aedc070dfe5ce53c90845de6e7cf77f8e6f5c3426abb5968adba1636ca3af4b06	1679127748000000	1679732548000000	1742804548000000	1837412548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x2d1ba50a1dac61f48720fec1c7e579d3d4311cc13b458ec305e481bedfdebfc3141e25dcefc84a385659874113d200389be0c7d39b961132ae8ed9d1613b73ba	1	0	\\x000000010000000000800003b48bedcc7b06637eb7d84388f06429e489f35d9d6ec335eb386e81a37615bc7596edfc333364c6dfcfea60a68b4cfedda43d96bd262a85dfd7c1da22bfcc6011a731f234a336519c8e6817a8d84f88e807c51ce32b9d2ee3b3b75c07d1378ef32976934caaa5f36460ec6f7a62d3fa45fec6e783fa24f41aa78b9a6433efb51f010001	\\xcc64e789156390d57c13cafb8e1b9e48e6f6cafa74b6f20aec5778eaf927630a0e833f820fc89e9048ac3c129df31973b30423360eb8ec4cf37d3264fd0a7800	1673082748000000	1673687548000000	1736759548000000	1831367548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
333	\\x30b342a3145314caddff0d35a4ad9b911c2b3d90dc37cc29596d79d259162731978ac1fb35fd75885bc5a61eca5baa8ef322ae5d4ab83fefbc909c1f130db859	1	0	\\x000000010000000000800003c37fc0755e393aeae027e06c3e3eb218c857edabab4f3d5a45f96ef157af0d9cbd2d09010c4028e5a2df4caee7d7a88b5c73ddbdaf7b74dc5b92e9844d2f8273a8947bd8c4d1173c29ca3c51a98020ebf81a125b6d502ab63dc3278a877362e829574969db5345958963b1c589eddc9a080ef271e92f6cc085140b2ef17f6ef7010001	\\x74874f35005481de0f1365b2007b3e4cc28567ba483289161b9b47375024228a3154cead2456bcfc4a8adefda33c7f52a49574e3888e76b6cc74cd2f8d5c140b	1664015248000000	1664620048000000	1727692048000000	1822300048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x320390d601ed435fa63fd95969436c27ab1b384f7fd854dba04e27bed9f34610bf7a97b3bcaefb4340ab77e256796b432d637ac41ae703865206b57ee8f1bbd5	1	0	\\x000000010000000000800003caed2ca63436aea0cb0cb4ea07623353ef1da88456f0243ef585137823580490b6451c4f63af79ec887b82dfb341b7c768fbdd0d1f8c3fbe5b0eadd12f63185ab01dcb186a8ffc87119295266e8e28e72341c82c788ac4a7a34e35a6bdd7c425754b1d5a8182aa7370511638aaf836f65bc9e578b80886dd2ba8fb58653ac851010001	\\xa8c68a8a7de57abe1d95773eca12a05791cf743d1d4d9f715af52629896080a632680305d27a68f1faf75e0869233c690745d8fa6a6e6e48dc331943864a2a00	1663410748000000	1664015548000000	1727087548000000	1821695548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
335	\\x345fa476fab983ef87f96b727593ef454fcfe08776cda3e65336bc73a7cc4a044a690e7203e829dff82397b80550b3eaadb6f91842c56dfaf92693579c9796d5	1	0	\\x000000010000000000800003a23fa8db7f13e87bdaf62ac0797d06cb82f11b7130c88cbe86840b5024ae73a50ffdc11410afb66ab2f9a808f79a963ee89ae835505235023e1a1487afe84c5d662a3bb77a06ff246cc2ced432405531a47dcf9e99bbc12538e0f190fc2bc656185497674ea320aa582a4914d49ea1e23cba7f09b31bc17d9cb5e448d9a79dcf010001	\\x956f06d7561d00bdc29e2b3bc7086bf4b83d04113bc45f4cfa257793ddbbd7c4c40eb33f8a70b77e99549cf64c0861ee9a6ab6a666cb256fc96db7a9f13b270d	1681545748000000	1682150548000000	1745222548000000	1839830548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
336	\\x3a07b4825f46c7c51b932def5a70066672df75d0b8f4a94ec95b8e7bfd478fc9ad68883eb53d45496e12c10252c1557bcb5a5ecd8cb7363af34070c6c9ffb758	1	0	\\x000000010000000000800003ad9d484baba2e7052cee16d94091ffdb2c79c850d7b9a13dd1ff5f02a9376ad9ca2bbafd4dbf77f4cd669574ed375f1abbf726b6e8700efea64cc8c287975c3a9df3e15ec2388ce68655267d90912d76e3494d8670abfda917d2b3d25945bc56f7320e75bc9f8829abc568ccc9928ce28c37cd9bad088351696ae32c93777715010001	\\xff09872212076284ed070b250e0f50da7f5018c6bb7d9ed36a561f0745788db2c28997e70178675272ef37ccc08a1399b6e2a207ef07041d1fba56ce5c87d300	1690613248000000	1691218048000000	1754290048000000	1848898048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x3bf3b7708571bdd2513bc2b967d81d165879ba3309900450261a9baeeeeddded3183959f0235d59ed8af61b61f1da5a424ba5e943c65f467331df4fc8b3f03d0	1	0	\\x000000010000000000800003ee6c89d529360ee631be8125a4a5de1cca4996ece012c742a9412ce24fedfdba4c7432676fd809e8050419a2e6c8db24c1519ef26ad85e8c371f653725ec772b86e0e0da536fd07d1e4939a8a7737bffc4f85a4f1d3daa3fd5a098c7f30f05722df673772ceeb8b3e082d371f528cf98fc1b84b751f16e967b4ab4cae7f33439010001	\\xde0e1ee12e5dcca6edfee7b7a632fd6ca61e4fe3806572df4c16664445833443c1e8b03c4d00cdccb4dc5a6010afcea9573ecd72b6d878aa940fca045651dd0e	1671269248000000	1671874048000000	1734946048000000	1829554048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
338	\\x3c7342f53d4c12a9a09b8bf88933c8dfffb41409c664bdc3b579d15eea5c5477499b80691164631b87f3120adc3eedda85f07e7643f5225882f7f7961a0d8dc1	1	0	\\x000000010000000000800003d31f36851b9a4622b5fa4a248cffe60c172b44a40b1d93c2d3ca747b6b1cb0c63e9d58de56049a0d9f85f190a9ec8eb32598e71eeeb1de9dd08b4c9eb64036404575ba9a6efa9a9b0c7913e6cf85172baa79ba1c47c9198ee860600d6ac016f6fe8ae5ae7cce7491920c6c8aee5b119a61843c0ce5f33c7725b4b3acd0b452c7010001	\\x88ba8633dc967f1f33e2e2296acac04bc3822a85e366f58e5ece382c8a1bf71f8d0ffcb6964b02e0c893e2ecc6b1712c9992fd6e16de555aafef84caef6f360e	1670664748000000	1671269548000000	1734341548000000	1828949548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x3e877cef2c6210e5432ff248ca9d76aedcea0d0ede639bc6a76773ccaf29eda48556d80c0922bfc8b6f4a5de2b2ab7efbedae1b53b78acffe694a989e60ae7f0	1	0	\\x000000010000000000800003d4566b25ca5b6b75d11b774c6af097f55f46279e76e1cb15781d86a9a34d17b5395eb502ade7dabf972ec23b439c6d17b33bf0c7d8c5922b1ea76ae6a67669de6a43710598dd012dc14083fb70be9a0230e6741d0ec9bec0ef050adb960c7b459073b05db323212a8f87eac92209b2fc104d0c6a5b78e8d5bf52ebb531cf15bf010001	\\x4151f9f0519697c1f57299e4ca6377f5927c3314720b45e57e00ce094c4d7cec37984b791fc16bb3b2876d89df4bb85f31144aa96d16b928e7d9c7db5e3ada0c	1660992748000000	1661597548000000	1724669548000000	1819277548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x3f3741b6d0b9dd324d669b00f58648516e84407ff8fb6b0bbfe5299a9beb29299ba78cd1b8839103760a6aa69adb2b0a46dd539bf64799168ad6e8afa19c4ff0	1	0	\\x000000010000000000800003ae23d86d02442316509f16ca43baa684ed75457c2606609cffe66d4b36b905b3bcf4a19d3c3c1ad1f5b84af64689b1ed515d162c23821510b3296fea38d8345b710a4b1cc2d1acc4f4daba51ecf3d826f31b0af7d067a389821476515319a8f78dcfdc2b0700e5299566eff519d4efa174464fa1a700a3f10f3267df8afe7af9010001	\\xc1ae0381d313f7c072e354bda6d32b97a66331ec1302734a5e8199d340e390c73f1ac237aa549a07a959b339bf7a9f3280e9a14b7f216beb07b430c3c54ce609	1667642248000000	1668247048000000	1731319048000000	1825927048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x40b3eece398c924d61b7fd8f4166a28f892e6a2bb0dba51ed389ba9f1ac512bf4a85a98cc37b535f910b1f07d8697a13e74efd25ad3293983b05507c5fed55e7	1	0	\\x000000010000000000800003a383d27c0acad8733ff25dcb622bd1e436a2281f00dd77de4274bc7202ff2d8a83534899e58d3cd7cbfcddd3dd82f92a273b9e88af5da344ac380908e8c4a8d545e9dce984c770660f048711f69c485002cc509a1e84372dbf2a3439de9674a4200acc482c802ba2d276dca73a4f5b2544034d50ff698e02394c04784bedc6ad010001	\\xea391d4d03951c990973d6ee526a13bcb670321578971297a387c75f9c160c0a6a86942e3a9976ef49c93d40845836ace84ef8aa0dad1afcacf06b6b0818c608	1690008748000000	1690613548000000	1753685548000000	1848293548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
342	\\x425fd9348c7f1ccd430cc0b5f3076ef75495a432d50434d520941442813b60d8e03f0bad067036f0d8382f8ba038ed255807888c1e401db7bb35d75f3b88250b	1	0	\\x0000000100000000008000039169ededdec3db02a079bfa74a9de0d278eb6ed8ec4d39686a65ee0af3796ea431b83af0dcecc5092c4c63e507813869180e8f649b4f847d3dc156b55154357c2e69d7cd271434d107faea7f49f478b5479435c30447a5cd647dc620e0f9f79b5f9c30295f7a78914faef40b1dd9efa6ed1dbc299b1c52b84d531c8727d3ff8b010001	\\xbd270b12e160676d8ceb133d467b749ba249b638b1f8bce291d08de2b345e176e5da9c142927fdea3350703460ee636016de0530b4150f23a37ed8926faa9007	1677918748000000	1678523548000000	1741595548000000	1836203548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x43abf37516a54bd7b62a6827dd0879946cfb87ca64e0888ed57b829401c347ed77050c52c383f817fc7c09f2072812c1d33ab4ee5ce1bb99fd7d03e5ab8e0458	1	0	\\x000000010000000000800003dd3cd95a2f5e121679cc146f374381341034ee58ebe559b448104ee705785ca0cd4075382818bfb6da1da2a028b4a8950273cff1fce146e24529022097b2298f452b71e791d78cc4a66a96d9a5fa9306e672eb7758d136ee151bf6c7870d9efb78ecf2e2ad060edc6663f42c1b5f0b51863162306075a2632cf624e9b7cb93db010001	\\x75f96a7860930b281dce81cb74f6bbc4421d3747e97ad52cf460f54ec01286d08d190d5e3c7f3085c8efae7addf139f12086cc1bd6c4222ae43975ceddebc001	1667642248000000	1668247048000000	1731319048000000	1825927048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
344	\\x458f296df6974a21247a42c64785f4307c25949d49adbbed42fc23140817443a61f97b3e830d926773c8da848f7eeb7e2c5e93585f4b70abf1e992d76884558d	1	0	\\x000000010000000000800003a1c03d5b64681ff6b9bacca2b01b3e6a5e2943e6f9c3cb3b953b323f7114d00853aaf5566deb82966455b1759a835b83264aedb3cb89889f3ae1c8714ffda7b9aab6b31407a2ff477158b650463bdb25d399220bf7836375691e58ac400b2a641c5b78294d5d7de7a7a2fd20baee4be422fd5619bb9c246e1908fada46f51ce3010001	\\x0315085efe19addf4bf1718b4637e6b7adc0e941810bc5192e9116be206e336160bed2bf085632976675bfa5cbe2e730623898df1a8397df912135ab7ec8b70a	1691217748000000	1691822548000000	1754894548000000	1849502548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x471f65d2e238dbac7e58e4f8f429dba23f69d933706f8c1dc084e5c09a29386afa02f9f2a169b2bc5773e0381850ddda1a45a5215302a9a50ead8dbd364b46e6	1	0	\\x000000010000000000800003ac55697d5de7f0ef9aaa074cec9948fc447863815bd4137a1a0f5ea58b6d64c88a876a49b5fb6ac7ae12b2d81af0d6962f9c9ad2f744591faeae49d9502f365d2a29b547c313bd1a40a77d622f021a9e3091665abf91e709163d546c997b35e6b9adc4d53f7d8cd336be4754d1d8e1e546a83b294c5828ce4f704fdad4b36c4d010001	\\x1e028c773f444a68f8f6ff16654684072d366988a59107b67a50ab2b4e5c4a8539f1c215e7f27e4ee8ea03bc156eb0af7a0c0c9b8464835382d39f7a028bd005	1670060248000000	1670665048000000	1733737048000000	1828345048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
346	\\x4a4b6ba8b24f25dacb59a91071389dd3b1b03a140364ae1518b8e5305f036b770b9ed1171c29af460014e3364822e061a6ef0cfca767f4a67e5b1d2ac5aa14fd	1	0	\\x000000010000000000800003b212464a5f48d4695a5a43e77a76fe772c6454aba0069587f9f82fc8699e88b87d313dd261b22c27e1a249d087e96a322edd125a2b616ae964d70d7f0c2ba1c6b5d261033bd4257f66fdf0ade2e7b433c246c3b7f94545db8811b2adc7736cdf6f7b3f16422b55fdc015f2bb21c87ccfbd6c9af19f14c63cb036bed95305a39f010001	\\xe9af38e7d9566687608a4941a2d2a1b3dd8a9ce04ad598d60182a66216ea292570e46c7e7d83623566120a3dd6f20c24c33958f036bdc40d58e9a3bec0d4c60b	1677918748000000	1678523548000000	1741595548000000	1836203548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x4afbdb7910e9ae62113cf507e55910db59390332223d0bce667803b311901bc45fae981333d25571dcc685d2590207f7a786ab0418afdf520fc6a323e2040bd8	1	0	\\x000000010000000000800003e92321c59add3df46427cd60de8d0130d8e207b4e883ea643d8ace0c53d7e708b637dfe5039deff7411f365b93bc49dc0c9e16f49e512fbf11c6749154f67a427d15f80b6e353de6b126aa9b7df4731324ac1ab0b02ab47a368cc0f6f8b39cc4c4e12abb5379da86a9adefb9d79246ef3a3cc73da40fbf0acfc5d8e213f37ab9010001	\\xa0f116b0332d9608c8af28c25fc3ccf1dc0392e4bf1f7a43a29b26d63afa94b70154d6143675b17677698c863df8a72325730a976f63e629079e63f4c98a6803	1664015248000000	1664620048000000	1727692048000000	1822300048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x4de3c8748998234d243f50eb8040ac597195cf051b9f894db94c3f5889250d8b9b36eb1e99ceb858d457836ea401270719a44d6358a4b6013d1a9620e3440b89	1	0	\\x000000010000000000800003b39ba0f1293b1d1872b1c25b9076d0416ad3792ed67c08abbce8cf37dafac701e526adb1489a88451c67e77778b1616d77efcf521494ee762554b2843d72e8879dc20d315d6722e7d6cf701c0687eacb3d746d80d69ac5372eba784eeb02b664bb3ddcc2e5b984b87b2e90811e995812b725ff033e401645d6e9a5137129daab010001	\\x3d9f4bfe44d5281facf32670e318095cc3756ede4867d431725e3a753b5554806c604f6aca5cbf1e6a4aee8ff21e4ba4998a844c7bf45fa53c02b5fae1f00305	1668851248000000	1669456048000000	1732528048000000	1827136048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x4dc73c9e33208176903f610623540eae3b5cca3f485ac60a94f7771bef033dfa9b0101145a4681cc5da7306bd8a42683816d0d9c74959da5b557874d78bc2827	1	0	\\x000000010000000000800003c851fee055a856b9f7ef43abbedef773c50953146350df7cb16ca341edffe44646b704852684b2c105cb88cc0e506b7e66c9399bf141211db6dd6b7a5b85aca7b6286b0a3310b377bcb80381adbf66de4aee964a417646f6ce4084ed89de84e6a33067794d28a9345a29bc07824cba4eb2eb0a58616accd836f3c1725b7df269010001	\\x7f0a0fe063f9362730b034845019ac95c9720cbecfbdcc122667905cb500893af469f8a9c02dfd33ae9239fe2c8b873f4b729a360c9eaaa67c3e37724a01030c	1679732248000000	1680337048000000	1743409048000000	1838017048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x50134b621b9b94bf99047e539b3486d8473c7829aea8ae062b7982bff522f56bd48dd341d6dcb39d6a0d27370b2e6742bd9a07739f76e0e147e3a0b0c132b169	1	0	\\x000000010000000000800003ae692ddee38719d59d47c694609658988d498f647afb0721ba3bc9938c061e1e46cb68d4f6a5c8dac41d29cb68baea54621058873e4121c758f922cdc0029d4ba4390f3a4b46d9d183fdc27b9a24a45251c81600f96bd1605e5fb470f483318b4c2c21aabda8500e7de2e2005c03129701fdcd6125b9a7992cb765381b8217f1010001	\\x97acba07b774ffc0b259b64caea3bd6ad870241547bca0d58f91058828d50e9e7e0985acfb8918fd8c99f7dd59e2cbc687f418fa13c3dcd6ccddaa675986c50b	1682754748000000	1683359548000000	1746431548000000	1841039548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x534beecef57fde2aea34305028d8f50efd5e70dc0b12fe19cee1e16a78d54e4253619a5687e8c70a02d17bc8c3a8ef48500267e92cbc7b2e03bd278c943e2ae5	1	0	\\x000000010000000000800003c5411a4a1ea3fc070358a8d35511c0c060c1b2b1234ae44a2cfa3bb072c4935fa6b8e5111ec28400bb23cd9b284e8e0d1ddc3e81b80b54107fdfd24e984cb2c4ccc85cad827f87d5a3eb0ace1d403f2dc8990d947cc2f7d74f455ee6d5f32ef463ab886b772bf743e522004820e74ba7d9f87606eaae02f76caf843cd1b348e5010001	\\xbd576b5e3c606b8c595cb415230ded274b32192d7bdaf051b97c8f0c17ed777cf1b8b534272da4da6a19536329b35e2a473ed6bba730d137e512e5edb9f4c50a	1674896248000000	1675501048000000	1738573048000000	1833181048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
352	\\x53ef83a442256acc181db6b0e25c652da2d139c9cda9dc0c7fde77e44d8d208a17f40a27ade504c4b9130f50330530e384e0a1b6e796a35b6a229f914f6a40e3	1	0	\\x000000010000000000800003d06db8b279db77b8f216dd353878c5a20873663ff1b8ac06c4a10d13ad247f71ec4eab34b3758849ed65ca21bd1a13c234d95985b21b7cc0b3a5243aae76229d56a8e4ae65caef3c55b64d40bb17841463331166671026b91ac8e1dc15cb80bd0730fe9f128ba16defb1641ecbea97d68aed0586489aeb5fb69e6a91675bbdbd010001	\\x0c4d925a0cffd66a0912095e49a3c8c30048fea7a83aa0e7739a6da8754bd9629f603b7d463dd2442e52ea1922f5228584b729328627624f1d2f5b41e90e6a0d	1668851248000000	1669456048000000	1732528048000000	1827136048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x58e3097544b340a96f08cb4a72793fb4b8186b817fcfc70210eb412a5731d99713396b88891325551f61c6ed3e8a5a5922d401175599b5d94e16e4605c549a71	1	0	\\x000000010000000000800003c383c2d4d06401853f9688ac638ebb954916733a76162361ebe258871bd208c70432b3316e448236c6725d8b137210fce867976e2aacb3647eab26d2db614b9a500b2d924daf667f78f8abb2048928457d09bec979be77d027c48d93c7fe6a90463023ce70fee8fabafc8f702d24c58969bbdbd33c2a938e4bf8c919db1bb7e9010001	\\x0a98477c028a1d23c44984c2a1bee42f1123aa56f7f91a8b585d74a0d66f9c4befba1efead9822a0d71519f73c8f83a5a44724cd957356671a66be577150a40c	1687590748000000	1688195548000000	1751267548000000	1845875548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x59dfc4c781df60f5ed589931a9fb223df9e02de363f8afdd592dbcc1b36526fef65f08f60f804d019317b3ac96ca0b6898158f395db84ea3168029523e728ac3	1	0	\\x000000010000000000800003b9da4008e096ef87578d31ff5dadbad536ff0f0f2e16b5c6db9896372f1282d4f0ee44e77b21f86ff36ebed2b3a544861da76a2757fb53f6bcee0ed31ab1414eec754a645cb9218cfb26949fb37dd331759c5177c48af42933015b183c171370955a66c7acdac05b994bd7aa9d13c5b56bd3b56c64fa1eb3a8166f6f48e944c9010001	\\xa7a533590f92f13f979188fa5f8c7d74565112501ab50a37d825b6b101ba0a49e08ec16bc7fec401f9e386e2d3ce69e93a3192cc0821b8d4d361b36cd7fed800	1676709748000000	1677314548000000	1740386548000000	1834994548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
355	\\x5ffb5528116ff8268a0988fc34ea9bfe663aa8bb9735bd8da1b4c2c249b07eab9fe59ae898d7ce8d5f90065ad0a1fb2fb29e9bad20a450e78def5d5bbd3acbd6	1	0	\\x00000001000000000080000397c3fc2747c004c8cefffa2f7ece54579fe53b8930ee1f997bbad8a50e22d3058b439f4822242afbe358ec848e02ca1e56d68cf038313ac7bfdb1731d2a211d6b39f570c220b0d4fcc9b8da65960284d1d122824d5447844b92f4be1f6d54bd9e4169f2a66dcc2cec3bfb5bc788ef397dfbae040a111777505035844f25eb615010001	\\xe18207e61bae7822628ba9c71ac8b6bc459dc6550a6feb479ede90ef0ed0bf5f167f949ec08172d960c037bfb291dc9ea2f4b240ffd77f5a85a6b5fff81f7208	1673687248000000	1674292048000000	1737364048000000	1831972048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x5f63464b8880b60ca7f3a41189220e104d75be24c7fd9dd20b907b609591c5f9d6ec96161c258c611129b675b430e55dd0853ab697d04f521c2877489f615e42	1	0	\\x000000010000000000800003e7abd2576054f794860929245711dad19e3c3e9de3ba34251430ff5e87a0b0177542e507c2c8bba09750e5eae4c36326b08a6c8db9439e260b1ecca1a553d189a0cc98668603a0964f294af479238798a8a56d63c7405efbd19ed8e4df9239bb61a7eb1b43d8de9874e3cfe35f2499c0787c491a83e0af5ab595fe43b09fde51010001	\\xa6f2a53b035887782f99251c23de436bef2efec819a6c23a700458efa6db138fb5179d88549197314cd0a992191b45f7e8ceec9030e423700daf7c6184ef890e	1685172748000000	1685777548000000	1748849548000000	1843457548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x6073b49129a95cb5eafeaf0eeeb75bcf9f52cdbdf727da27af071edd573dcaf3dbe69403cd5881116deb9bfa85f8af8518ac12e67389f26da1b3a21c8382319b	1	0	\\x000000010000000000800003d657fba441034241f519f46a355e2d642b041c64bb890ea794ad49b74ccd05db6027ba21eaccd4e88ca1ea4d486744d24e4f7df4d9f3585ee4c2ed0f5e3fe37825d14536a2b7dd02387d51ff2b305c56e6f46e3e1d784be576be0bd49ec291d2833a96b8a22abaf2df9457d638138383305689c89fc372a43f150f93307ab487010001	\\x290179100c167697e5fccd5d742efd648302e5a16657b6a6d4be5e426bf88af60ea1dc444003f4c41d4319e0eedb033dd02b7b5374b51766baed75fc1ed41402	1680336748000000	1680941548000000	1744013548000000	1838621548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
358	\\x68032d65a519d753a4586f255d1d8cfffce500c8dbf2d8ce0dbedaf2302ca2e7a4c61fb1398a13c1b45ea87b6c365e195c593021b5d557b2e53ebdf4d6d290c0	1	0	\\x000000010000000000800003b799525d69d09f81f595f84534f19e618850ad927708e0ad9e2cadc7fea1432490efc48420a0dfc6340cda4b0f5b4e5da2724aa9087d0e58be565c3e9f8600b64e21a92675e1f2acee05bf7b95310bb9a0c56adf70cdfab1f5c20f694a22c8466fd27c2748ac237eeed48b867d76217adc6b3091fbeee5019196f6050111b9c5010001	\\x3bf95a92c1fd2710c248e3bba5363083288dfca3b838c441b1752e659fc82baca4e649662f6cd8b0b0a20743604552212c1dd38912a6ec459a8aeaee783d6a04	1664015248000000	1664620048000000	1727692048000000	1822300048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
359	\\x6adb63d80e8eb4178f809be07962065d668b98990ca6bb4ece007cc60e13d2ac3cc74361033edf7df57e71b452f2560f7e0936fd12c367c19b215d02da581374	1	0	\\x000000010000000000800003c5a92b6f601d261b3dbbb9ed047e0e12c8990b91e0e6768fff5d3cdd2c1c43e6960f8de1ee682c541c6c01d06fcbcd44be4930ccd6a5a934715f73d46336124b4e13c2e3ecf3fc758eef26223800cb88cc0efe75fd0b7d0105f79b62a8b6dee844ffe20673032ee4ad1434554db9bb5968abd329d967a69caae518288576ef1d010001	\\x657cc782f3c63f62eef2fce41a872c78f1df971b2257222ead5d49fdcd9494ae5789c64317df83eba72975bce548b23b9a9622786c21de3dfbdba9af4ee21a0f	1672478248000000	1673083048000000	1736155048000000	1830763048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
360	\\x72d742fe2f15e02ff6a492eab12222bbe07d78db3bc29a67dfdd6e508704a6bc9ec70f48cc8a878307d98257098e817c06e20399389328d26fc8365482e3ecaa	1	0	\\x000000010000000000800003c01cd6a6a294bca03eecbc80edb2f65812f390b4543886ecdb56b129b5e3fb313cbe69329617b083fe3b783c8d3f0fd10933351ecda84ff8f85e3f542c7d9a0d90f58dab5f4fea2a027360ad83fac7554b57704409ac2a1bad0927c20af729c683dca3ff769f45db0de615d06ee98fdfe608cccbf17d354f9caa6734cf33561b010001	\\x48a6cf90d24ca1fa8993167c89132ffbcdd8cce67b6ae0a1435b267334fab367c2acd0512e790600d1d102d7f5b4045e86fc7d2b1b69390b0a5d4ea01af6420f	1666433248000000	1667038048000000	1730110048000000	1824718048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x7287d895ba11c445bd2d81994a1d9478855aece2ae04ac4f5fba249d881545d137d953d83267cb7c19f8dc9b8b603d70fd56aa25a8e207b4593340710f26cf54	1	0	\\x000000010000000000800003ca474ef81ec9ac4fd6a005162742a538d5d2d57009f6d8427cc206cae32733442033abe859a248c45df014f069c494e184138698fcd2b2c767b715cff5d0eb016f78cb9dbe7f1c0f78d9b676de7676ee974c26cbc4fb94e5152c2a620c35a049c073ca637290cf698e2eb29ab8806bb716b93ab4bcd637ea296f63e1379f1bbb010001	\\xa68c1d6541f0b8f0093c48159b302ab8be5f85d049d354f967a32d5402c8bec61f38a9023c49b262825949a0d3d7448ffc471df1a738e0c24fe1c93b991c620a	1661597248000000	1662202048000000	1725274048000000	1819882048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x78cf400ac8122a091ac8fe673cb07b0897e10509a32040c8ddd3db50025a6d3b498f119c2a3ed295604693cdbd6d151165a080f74865922d49d410260e5957c4	1	0	\\x000000010000000000800003bdef48915349b2d8407b9186c2e46c1f1c6f796b0bfff7e87a6749670cfc0286ff3939c74a44158fb25a5f7d72b860f7e90bf0f453d3ea580f37d1a8dd8b30508a13d3fb2e60bd6086d36361f17bb693e6581c0143a52c176dc1bc7aa0f7b4cb7532e01138e20cdd53391756d3681a870cdaf7c688ee2c41366f3e3307a61ef1010001	\\xf1132b601d069806c0f6d63f5289c822572b5ab69962c14308e379fb6a2f4b357bc1b7e1b1ecdbbc1e09d87aa3fd312bf1b8508d101cf44e6ec90535f682800d	1668246748000000	1668851548000000	1731923548000000	1826531548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x7f97773cb690b17f5ff5705ee39ec2adfa891bbdfe4fa5cfcdcc73a99c6d2ddb9dcdc400459a9eb50ae433c439c9347a7e1a14030324efd68c6fa51151a624c3	1	0	\\x000000010000000000800003e4ed5a06daac08ad7dfe390f4717169d949360c3ace1c9043f8127350a60332aedefd885b572e27aaefdccd78100e422907d4c4bc051e78c8682e859749369c0728903ebacbb4e4c192fe067bc7e2da0bd8d24c6b124f4fe7f89a71c5f4ed24dc3e3a3d29c80f9ea08fa3d7fb2815fa8df00fde010e582358c61671b845e8c7b010001	\\xfd6527e8134d239c80cec0efdc7ede0e15e1fe476fd53ef0b631c7ccdb7f732178db446c8dba0da31b6f8a8e3bf7c443ca491f5a60190159477040a836104606	1688195248000000	1688800048000000	1751872048000000	1846480048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
364	\\x7f27eb42f6eb988765ef6aba5d1596652581b4259151e948014ff636c74c3d50c18df7ebc9b92525f4426b306923bdd31f4092ab6bfb737a49571e94cf779a7b	1	0	\\x000000010000000000800003aa57e68832e03f260b160ca1938024f573544682c735a2b9a9a3aa2623c77ebd2c21f822438f79562af5f44ddd7299e556cba57ec56f4bed5c0699366abff821efa19f7e27e04fcd8b8add316fad37dadddd14fb895dcd136139db2b584cdf691e998cd82030885651561ba18917934c181e3bb85a4998192f3744853868e93b010001	\\xc6a0b85b734821fa07db4ce8e667dd6b774b7ed0ebf5df502bdd9b8702b1cacaf9c5287c743f056af68db0685b0a144fd532b709758ee942b1637a1c05f7210d	1672478248000000	1673083048000000	1736155048000000	1830763048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x801fc4be134b18f279bd95d42f5dfdc170873d33a82e79adfadbcc8aa5258f1546f45c6bc44db1622489957ca621f2f81af2b3a967c06a95efd83186bb84bba3	1	0	\\x000000010000000000800003a4848d675a3d809f4b601a5086993e054f6c1128c3fb74a989955a3aca902e13e8a5fa2d2359578f32aaacc72d2f65fdaa40a4f8226e02f3616de2d053e08b4ab33b197f5e4b166c96a66fb3e0f060e6491df851ef9ba3293250d0cdb27eedef0f185621536fce626064a0b2d776f00662b520dc7cdff06fc87f03b52374ef53010001	\\xd4027a5064bc33c4641ccb055036cdbaf9fee9f7bc2775f6701f671efbe8a8e12faa60cc7d39dd0c4caca46f4b534b1f20dd14d7f3fbca9c2dda9418c1bb320a	1677918748000000	1678523548000000	1741595548000000	1836203548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
366	\\x80cb69cbc323b9027cc3a2661dbec87ff283ad629fa8ff74d662368d9f565d04777fe03f88d2fcd6b3e88009e686a3584338278529a0902c656f4fd04458dbc6	1	0	\\x000000010000000000800003d54fa2253c850dceb6ff2e2fc08e2b11bcdc5dc4261313203dfec22a59e948e81d33706b3c91050bbbbcd7d0ab5ec9fe09092990b71a3aed4c0f83e1bcfe74712e679f5fcd4b6fae69fb453081f37b99e0756f7c4a82f5857d21213d33d3bf71f0ee5185b12b95c70222568540a6253569979ce67bf9ddf13618c4d462de25fb010001	\\x4e9783463d008130e8c1c921e481f002a45dfe39869c7d53adb005789b4dad45ca48dcca177c857702983d8e83f0ee67431e73b9065cb547cd122a697980dd09	1667037748000000	1667642548000000	1730714548000000	1825322548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
367	\\x833f43c0216363d5daae434ca4c7064efd73ceb2b154ce0b59f9e26d7c17f69ec4c3d73afafd9e35e62813ea0bb834952b0423302eed5a02b1d2a54030c6f94d	1	0	\\x000000010000000000800003a6df8eff1bef227e6afc57041c4d2cac5e1a06fb09ec1ded632f8af48edbc4981b8a5ae09ca710c396727d86801da53b56ea61df4e9de0ea43f3aefaa9f9e2f6d0584619b38ee67e6bb51101bd0c9c64ea128f685c33a66b5a4da35c25bc825a8ce3815e0505bc0a22681f48362677073fa3aaf09b978fba3922b32162b0b369010001	\\x492574bfedffbe8101b2664d44cdce3ce7e1cecb7b8bb3c30f04051289f0357351fb47897fc72ee6208b46aa3c9aa6910041cc1b78147503d5a485171894050f	1662201748000000	1662806548000000	1725878548000000	1820486548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x8577f19920f7082bd8b3accf29c978103a7a63b428fd977b45f826bc78894913e000ea621cfbfd9bab61c6848b0e305a1c8c34623b90a1822d6a9d88ae72d57d	1	0	\\x000000010000000000800003c66c79bc067a887d17da9b2e3c8c91b357ff2a3dfa225c4f6f44152bb0cc43e7ab124476d44d73d6ea27451ca3738c1026a82d09e829011871d76cece36dc033732e52fa604a8727ab8fcaff6f5e42bf4d7b5ac9efbdb5109229c7e04186365d28754a6cb2ff32c5aa5ed6e3a00b08c95dc112779eb452226a5a5dc53815ba1d010001	\\xb5d890a189a4e738565aea1c2920ba6a6759a290c2f6102f07c0ffc5395dbc4fa01bfdf15591daa012099eaecd020ca9dccee1d81a5b276b02dcb3f6c0607f0f	1686986248000000	1687591048000000	1750663048000000	1845271048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x863734a5e1a105f7723fc49a6f34af2fc149da9d06c4a695770404aec6182e7d6ace7c09bbd557cd1e8aff98217826134cf88e879726bc75557fc897bbea4684	1	0	\\x000000010000000000800003aef35cfcf0631bd43b1098acac47a8729cb7d11bb688f33ce99c14c30aef8683033ef910000a68ee39564c379ec9b324d96d3fa6246c2e6dcc997f574f633a844fe02bb4aa39817bb0cea2dd8c607d239a7e4fcfa399cae6f56110a304f71a98897520fecbc14d17e06bf459691d0682234ad96ad847218526ab195efa004a1f010001	\\x9068e5960d5e72aa2bad4d3fbf5d8ebd61e5512ac4d07509331eb4b63113312c04758e8e45780086c60c44d4f9d8706a4eec09e201e04460a2bfcbf4664d7701	1680336748000000	1680941548000000	1744013548000000	1838621548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
370	\\x88eff30927418da4ed149dd530e421a4dcc3856f01202da2c4c5c84ed67aa34ff4087f946af0f2a4c510c9239d08c8bd595ddedb6e887285e17dcc123c82e6a3	1	0	\\x000000010000000000800003d70b6b958149fe2c8bdf0496399a456905bcec4a184535e17834369f70ae6d0b5675134bb198b81be524a4255836acdc527dba8028c2759025f8ec713a29be63f980fc893849aa70ea64fb0e5724b9cbe872e19c3843da9d5b708a062b0712b4afa48dcb58b6da6da255bf3fe326c3824d13a243b86b1a81dd6d0825af41c02d010001	\\x606d8854e31e1a99a1f4ec205d4674113b92fa10274422434b7be4659a3763745006832a75c33483bab1d5f7b5a992c31fc2126ee2d1c36ec1b79f193e092900	1666433248000000	1667038048000000	1730110048000000	1824718048000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
371	\\x895fde1fdafd83d37c9d9018a5542be8928b4a0376b0f9c35071505d63ed785e4b0a1f3218a58a9cc2cbbb2b7fe70fab8b3766ed40d1a92c068cc2d9f181ecd6	1	0	\\x000000010000000000800003aabf4052906f7b81dc2ecfbf4ca4927230f9e3ed434205795fab508d30ebde9da34519d2bb640b375d2d6f671b924a03fb529257267a0fbef74b9c3abb76c8cd0a09527acddeefb77bac84a421642e4111368fa6d315fd787111089951323a4f94a42111c87469224222b709fd757e99cdd628f31114ed45e8be6b9d06e1441d010001	\\xe717557c5381cb86883a04726e70b401192e9db66d6bef51f369860899a66a0bce97e0ae6e2a440519316f0e787bdfba1918e987792455ab9efc70b969b2bc0a	1688799748000000	1689404548000000	1752476548000000	1847084548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
372	\\x89eb1ce592f59f35d013a1e50d41504e411606971860c7736a578162fb4e216eac2e6d5c7c44f9bc6c45d337ae529042644cdc4bde3e6882d81f317ddc3f0331	1	0	\\x000000010000000000800003f3e78e79f6046e688bae5e3ff353e2be818a5a44c5574a99f1fd324e40c60f5a2828880f6ed4567920107fd85164c54d6d180616adf9abeddceb5622f7cc95fbe5313cdc90cbb3b7fb35b0b30c1073ade1f0f49e56f93b202fb2574f22c92b1a029c02e648b107124cd9aeb64305480faf765c7544783db000c55dafdb62d4ef010001	\\x15a3835365aa66f7c69cb829f004e040262a100c3936d353bc74e786c0431d98e53ba6c3e9176b7264f20daac3b8ce05acbcc88611666d2283e5d8f9e79ca400	1682754748000000	1683359548000000	1746431548000000	1841039548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
373	\\x8c7bba529c05e8b820006f53fd2135c9665556cf6b371ea68d1706dd88d55cf76cdb06b60f10973aaf4cc07a893bd75f3f6e39f5126d8b504a92a3f0e9ca0ddc	1	0	\\x000000010000000000800003a0e490a4d656d329b1acf517b9a5994201ef34a67ae5d0dba221a1986bfb2c30a91a0403694807a63b7718cb81ca85aecbdaaed09e0cd290e44e929414d23fff46000f6bd0b1f6bdce7b9df539182a103c2390fbf41683464c254c49c515450a0ff86496030b03f70bbfbe5a11c58c4009917610285ad0e25f6ed459b154b40f010001	\\x4611225dcb81807f403db696e0b3704f7b0154bcb81a042e6dac553db801036314478eb53222ef8234a8c5cb5106d42368492e075ac52c06be632b5109f2210d	1667037748000000	1667642548000000	1730714548000000	1825322548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x8d8bd94ecf03b37a0d98320dddbf9ddce60def7db581c3ce00217fc339f14f373eba34416cd03f7f5b8b464a7a0efd742293b755998f5429d2a6662745b28f15	1	0	\\x0000000100000000008000039caafaae4cf887b4c84335850a3db2f71ee5fe3d614012d3c44952901044da1801013d048bd9ea89d0834841f0373fa19a371ce1a241b2f192e7fe35d2f1f6095b1f780939f6a98ce65532614334f311287a7b3e6598bdc85b9876512f9c5de7b7541be634766ccbfec105c6db08f19d0e9a4fb70f66d3ccf45a2f57d45a4f63010001	\\x1fecb36547a46765b44cdff431381523d5af971895c47799ac97a3cb3024e3b72bf889927480f04b4beba98cc16ce3481264a05325f928b19f996fa9d7a3a600	1691822248000000	1692427048000000	1755499048000000	1850107048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x8e3bbec74de191ffbfc37ba38648cef408081e618d9d5572420b6323ecacb22afa1cc41d7f01994e60f3fe2c5c29351f2c57794346c3fbc13e1b9cd60f1deed5	1	0	\\x000000010000000000800003e1d6bc0c73a96ad9476432d9eef9f204ec1cabd3d74af9b2e3a7416c91387ec707e124ce5c9555494e1ac921acf5d217779b2afa82ea044245ef9814821c5b475e316a9626edf29a3e48c46e4e26b930f093a021c6884d3f48d68190f8313ef0e0faf2308db8097a631f4a1602e97c33171f3e6180b50fd2a1bae2c2e1c14c79010001	\\x1266fcaf7e1e69fa9b14931c06b475db1af5f1cbd790098a221b9b882476401a16242c8ed484e768375790cb2e8a25af186e807db2c2aebb16a553de17a1f50e	1680336748000000	1680941548000000	1744013548000000	1838621548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x8ff3253697f11c0efa7fb4791d07e7b79ac44c1fc6db53a2319d94b8549d1445ab5f90e71e8edbbc6ff5d319e326a40976a0aee63c797313e941d847d6d026b1	1	0	\\x000000010000000000800003b588ceb7f01bad9401c4f3a4eb24b773127531a7e536a994e9672289e70048bb87fe6f95dd42d5d630f3e364e4def35873133e3803e5aa06e92a4cb84ad5e9f52057e519dfd8000685273cfa49a5cefe5118dafdd63548d33ea4e2da4169ff20044c144465729ca414c398f93da2a54ee6a004a69d6eec999cffd8c558e85259010001	\\x63edd9f0a7895115a225f4168ced70724eccf6014d425dc30e05cb0de1858ce74f4dc1b3f706058c7dd9eae527b7ad3a37883601a5253751cbf7e41b0e49de08	1679127748000000	1679732548000000	1742804548000000	1837412548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
377	\\x901b49596079c0988e90c22a5230883c315de4bb97883640da8eaaa331ca1fe60cf3f136beaad5716c3c5c66ebf3121b34a03cc31f0191bbb2ed83e28cfe8b8e	1	0	\\x000000010000000000800003d229e5d48d6c4719a9d5d566cde87af245261744c639aa112f0dfaa48aefa3bd393023515459da724405a6f7e148e49e3cf27011dceea71c2017746ae6f5662d2b99c81b49f0adeb173a079166011a8b35794f7866e165735d45735cff977349961c80f2f23f9c5dd0425b011c64ef44478e25657d768b91a60f581e80056e27010001	\\x896e9aa4a2a924702f8dcd9f58dfc538d16811d186a7c1171edcb1acc0a80de878416d90f2ac9fbb169d4d7355f7f5b74f886696ef913009b66d6f696373df06	1667642248000000	1668247048000000	1731319048000000	1825927048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x934fb490d0bc6e7e880d661b898b68e11c9fe29113dc260161576c0e5e9d3e5024343559f77a126df80e658e2afa6ec2a2e4e988137d6147b8b937f6434052bd	1	0	\\x000000010000000000800003a8e05ce679fe38d0be8327c8fd93767f856f6d57cd0076a4be4fa45a8106c26008b62000789a15e5625df1253be8b0e97cbb3aa6eac6ba2208d3d4a8121374ef4105bf37180e954962f4255833605f013f4b5cf07a6a8b1f637f8e75de05197bf99cfa751eb195bc17ea25b9c4258e9bb2b96c205dc999b0a4beceb432c74d51010001	\\xb24ccd079077a531f75f5c64cc8d314dbab7377203ec403cabdc44e9966df8377efcd3daa639983978f5aa45feddd1d85af4ca3c9dd42c61890a5dba4ac80a0d	1685777248000000	1686382048000000	1749454048000000	1844062048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x94bbbfb93a3ce5bb925671025131103e4bf97bfd41225b01bfbdae5df0f47d1e51dd1c3f8cd81660c240746e8122bc254f9bbdbc94c14da0f709b149bf71f2a8	1	0	\\x000000010000000000800003d7448c7e6197dd1eaeb032141febfd8e04a58b73920cce22ac3e6a9d7a6e62ba2fb8bb53c179fac4be10840c2472531845f785fad74b2e705f442cfb8f46ececb5ac8c64415ae6543effa78800c7240f8546e2cd12263465dad2bd52ff0e965376b7aa592749b2bea3b6656d16143df5aab4e888fb14a8a95b3ccf15bd103ad7010001	\\x687a01e9b87cf4e85194f7514afa79636b6f1a3cc408fafaded900579d662331c0c56d439b1d6f81e80f8632097ef594d32835cfe788a3c7769de4c1d077320b	1677314248000000	1677919048000000	1740991048000000	1835599048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\x949bf8e10cf1f9a6bf47af67639ec42c359f7fcbe4d383bd4e382cabce64a9a2bb7978023a38be217b05ee0328a1f8bac0f1be22a2b8bc665627ce8a59bbd0b0	1	0	\\x000000010000000000800003d8537b64523a84a33e97879aa16c2ddecfba135cb12ab8d874ca449a7efd8b9dab98cffd383cf9bc9542201786bad929af11d40946c25356b37dbb5d3b9164176a4a042c693c9893a7c16d9e7f06ab6c929fd0b0d1eb00c4d83063a223abf87321802aae039010e1df6fcd9f47f6a34465df0adaef19d988b2d6db1658e828b7010001	\\x46165c4882c70149e3cc7f80b25d047eb81d40e134b8129cbaebe1eab53ed504b0a31a5c97bae9e5ccad65f49b996a43cf2db7a012b8ffa24d83c17155ffcb0d	1671269248000000	1671874048000000	1734946048000000	1829554048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x974b574db2effededeefd7d0fb51c4235154b2cbef6117b85b941c52dfc1a8d3071e7b4d6c9b87cb4ac58ddef2a0f1fa08aeb96b308486fc85f6fd63b9b7a4cc	1	0	\\x000000010000000000800003ea7a925daf8fd9695486d11473e5b1c1f2ef203d618e78222a465110cb63c077fa771df9850683fc157f3a08c3f63449176c1ceff60b3945b6fa720bc062cb599ae86a4d643895d765dce89c9b2c3af8d7ca8b0634c1272c8703caf1d146ae2b9dba50e822fb6afb41c883f68547f38659c3e9fc9b9d06c5b994e53f322b06db010001	\\xd2d880989950547f42d667d31c909b3b5c97140ed31d6acd538e873d1976afef31f7af010af93a595a60d9488dfb869236dfbe50ce6a133bc322cc402a3c0002	1663410748000000	1664015548000000	1727087548000000	1821695548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\x98affa9a4f1499bd9c32a7d1b8f79e032c47048baea8026b634620fe5beab5a0b7f0f6ad3fbdb9ffb7d038e5b24ab5da02013579d439e156fb5ba69db4a45a6f	1	0	\\x000000010000000000800003af8450955e55eeae3192ca5c945ae873eb8ea47219aaf2b1e05b6c4b35a614b3116d816b6be10d7159f1dc8284dc97d89f015d4f99961270101084938e00b96834babe189fdc91e3a9b3991f5eee37166c937da5d2b3ee25fd5e54d1b2ebcbd12ca71a9f2a986788dc9220865a676b347fd304f8ebfcb915a401a495e04f21e5010001	\\x2f929cced94ab9c2d58265993954214d1720e9303d776484baa86f450defa92081ab96f6167f02a0864121b0eed286d9f846e0c373d286d9a02ef6dca41e4f0c	1686381748000000	1686986548000000	1750058548000000	1844666548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
383	\\x9ceffac4978e8348deeedcfe726541a3b1fda877f419d648fa047e99637f5cf6e49fc129a0f0dae5904ffcced466eb3abb2fa0bb74e91398b801a7f26c1686d3	1	0	\\x000000010000000000800003c3fa3ebaf73c8474819fb798f811896637981cbf3d9ce12cfed7bf2543466b0799dc69ef756f83c0a141ca95af830a895d2aa2b4e99c07d6a4cf6a47cad8d16d25a623d88a084be87807703d7887f998742086c64a95401f523e9b49b544dbb57a968512098804301f7664d40702e98867dd8df26a85225ba903fcc79382a869010001	\\x5db97a96fd8cebeb02d0aff50e083233792f8cb61f4b911829234dc3a521e724a47c2efefb41615c22d6bfd08bd41753d1135126a41b9f1ac909e56ceeb4ee0f	1661597248000000	1662202048000000	1725274048000000	1819882048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\x9cfb2d257017030b75c747189739feb4b383eef42505d79f76df28103cb8cbfe01345da38ff61213c648b3b4515d807074c231568034041c8a02cf7f14a36c7e	1	0	\\x000000010000000000800003c0b31e02d03ea23c704ccb7c5c82cd6d42cb4ae6feab2da062be8ffd66e20bb16f3e5bfb520c6fbc885b25ec30180cd179d7f74bbf580022f52aff9cc89c6c3eb8fd31a529da27abbd4d17fd36b29ec95ca1ece4c56c05c954dde6beece18d62200d37bbc3b23970830947c2426361f2d4cf6e18b167f7a9db03b658f9357241010001	\\xf1dac0ed67a4b150fbf8063976abd57ccabc1a11f44d875aed892a1331f51f2c8380f3d97e065336a3748fd01a6cec7cbd5b8dd9baa430a3e4a88e1b2c2c0902	1665828748000000	1666433548000000	1729505548000000	1824113548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x9c1bf65e6a8c94fbaca09d7ccff51caa9057a149a633430233f75d2f8f73f6dd3d6afd3f79efefe1c0789b802940382386a0c386f6e4560712544d616d4f08e4	1	0	\\x000000010000000000800003b1affbd391b1ecb5685ab1e6e2aad22c56da5622e0871cb07af4de98408d1ceabd247fec6e38fabeba5a6994f72620d9c24f3c59477cd15144891fd06e28363cbd7d0c9995f21612995504a87f0651b3d95259eccb43772789756e7d4391cb520db98b9bc1138f82d3cc6c992436749a824dff05a555d27fa6eb7f5cf36e2225010001	\\xf23e82508d9cee63882b67d10661ee2a2b55085374eae9337fe98f5232d8a3ec839401c6a0335a2287ec3a83b6fef6693f29b58e3559976ced78d8b74b7a880d	1680336748000000	1680941548000000	1744013548000000	1838621548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\x9f1786d6a959892bfacbd765b9574ee20c2993ac1a0678e1123b585131aae811732b63300dc83ed94a6c8b9b8c2b1346edd4f4190c4059fd6a67b08592fd9d83	1	0	\\x000000010000000000800003c49bf929f71d497c3ef73ac347ce692d853b951669df4791cecd75b673ee8d13438897252f4d87e46dd38704747c4b888243b778f48ea779db02d7e5498725ff5db1c1a276648f2ed2b69e6c41499286fbe10f6b55410d9d337967ad01467dabb9158dc6864ce5e9e12428ca27b4d8bae19fcead7f465efb06961fad207db2f7010001	\\x93c55127b4020d89c12f43ff13fd32e363011378d5144f92187aeb14b06e8f49a69f72c7d41cdc92c09c240ba9365760d359c3aa3c222bcd1fb32c713f1d7a0c	1668246748000000	1668851548000000	1731923548000000	1826531548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
387	\\xa17f0f841f955b0a855a74fe49ae592d1e49aeb2e9079df796325985edb0557274a1a7867c414dd8d958348cb718ae4a0d8022ac18e28d7987e6027ca65dc91b	1	0	\\x000000010000000000800003dce0cc5bca8faccd226dc4af7c14d71447c1c929912b360afadfa5abb0c534dd162ca178b2b90c5fecdd7409e9b20699822bb8d2f1b5a86a0b5a1d5cfd1d030d56634a4ca2aee5a135a2ebb7837a42ef5737f7b3c4358e9bedce06740ebc2574504819238c829a7adde921b134acb83bb1ea143490b7fa658a56d837947266b1010001	\\xe64165ee75721b2f4fc46abdf5e85d41c7b30acf06eded7f4c29cd380132538c75c4f4248e104f9ea5cce56b6db5bca2ab5e9b7aaeaddc5cf6ae28b379c70a00	1674291748000000	1674896548000000	1737968548000000	1832576548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\xa5777302c7169493cc1c28c2ed5f2a1076bc7c3e147e191160143fc5634824075a6a2ffd6e2b788325d54c2115cd27ed62ebc5ed35c824614929c6c5c5088657	1	0	\\x000000010000000000800003c9fd47eaa75236d8aa2be0b1ac709609e1d235054487069f681ace19c11ed0495c4a603121921cb1b2c7632374d5ad67e259254f8d482bd858af662e2c6332b18d04b42ed01ea52193497cf0f9cfd760d44d21f1f95ed287a03ed4b883714453d08200aa1ad8ae0a0148d205827239c868e53c403be8c0eeaab6a35cd0a8b781010001	\\xdf00021da8c4a89c12204957b6c13e49aeaa1b3d84b040462ed361264d072d4af0abc388a031fefaad98f4c5efb247a94a7496fb5fa6a2f24761355d914d6f01	1683963748000000	1684568548000000	1747640548000000	1842248548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xa63f622291f2e1eaa0b915e667218811982d93325e226eba034e3293f4ee173d0d1a346f463bfdb37a4b72caa81c2c3ba727cba756e41c1ea8750923d216f43d	1	0	\\x000000010000000000800003a334af51c87f87e65d189e5efabacd257669f427d1cd7c81aa6b146ed5df90fb61eb0626b6c1d032d61c3071673f215687f70bc5cdbd131d699a6421e29c8f482a3ab664de89de0b9a02dc9a0efdb192360c6d8547422c6eb9fc7779f92bb296628cc1db54fc378185a6560263ecc6049ae4066461193ebd750174234dce613b010001	\\x6616a85a3134cc2a2092c9d0519e9370e02016e896dfb418f60a377aabfbba1f2d7bb65099e7ee5dd7fe53154c4032f64e099f1211e0a180794193cfd837730d	1663410748000000	1664015548000000	1727087548000000	1821695548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xa94f5765008cc94b2d74be0d8fa5e7be541392f697fc8e05818eb9bfdce27520a5362f2a85613df5c6ca9147ea1646b2eaac4485071cccbb31fb4dc9c8dcc23b	1	0	\\x000000010000000000800003ea63705417ada578e48e9d8c08c42b233b333fcaa4c8bd97c7e128be419c966c56e12bc542ca11f7522df8b26dbfb176aa9553b74bcc6ea253ba33198a65eb8fe0ceb4d135926e5f2766d3b9440e26ec1c5ad06218f635754d365fc394077baf2abec86f0b799ef5956509807a9d8a13f5e38a9a3c023a005a299255f14ddc0f010001	\\xb976474505b9c56a683e7f6d53646bc3079f634dce66ec49c2a68ec9f7a4c3103bd9252d5de9c7d9f49b930387fa3bbeae30e77690786495db9a15142660980c	1687590748000000	1688195548000000	1751267548000000	1845875548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xad63bd2429a465f1d546b49f19449772c38eb35a1aad0354e2b07afdfdbf53dee5a5e2e316d1cf6b28f09ceffba1db1a37c0a4a1ba073b929c64c566d8e304ae	1	0	\\x000000010000000000800003c077f9aac7422bc4559cb48355c483bfca814cd31b778396a862b81b67ff04bd81207b808d7fa9252abee7a92d9965fe73100db69e603d5fd031e03b08cca4cc29db27320063f427e319bfe992fec40c7429ecf81f0edc71bc933bd6171f9708387a66ae323f3cce31ccd5a9a1f102f1d365657897049798a244cb2a509b6495010001	\\x1b08c13df5570f35306aa52dd4e82e1d5012335912e8f6e1dcb7bdc02ab65702c2ad3182ada14d89c42e8eb44849d0ac8c867822ea9764a8b2e9220d5565230f	1691822248000000	1692427048000000	1755499048000000	1850107048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xadb72b702a7cc8f9bbb2070b39c19b6d70dc81ef8288d69a22a82de25b8f50d09a28c5444a58dbb9c97fd734522d0bd778f23c9626afe612e5e310b2486ab59a	1	0	\\x000000010000000000800003cec695781455d48c17e6df55e703aecf57fae9c036d3bb371478631112727c8480bef2fcd515cd969c106d59980314fb02bd81c17be9cf79fd9565031f63cf9a1acc9a683d7f20864d57ca5cc764c2a3f451b143a1a34c706b0dc2d62ffde22a30560c2caadfbfa4942abbee0191dfeb75187f16b897cfce45ded66313fc2407010001	\\xaa82f74ef7cc50c8f1cadf9d814db4b35ec388098c7e042f914c47eb64614cfd3ce19cf78ff92cde9c63b958f913abce49b77e6ce0faeed0ef982219ba207205	1691822248000000	1692427048000000	1755499048000000	1850107048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xae6354cfb567688578df572ad245988bea14391707b8c7875f4e8cd59207528b5a7c1fb0c5de3398757f40e39f2d7eb2a8e2304e1557d1029d4f8876ac1ae1bb	1	0	\\x000000010000000000800003aa70979cdc9df8a7fd679ffcc070a6297628e0e8b65fd7cae7aa5308e6c28902e930a7aa8376d27fd40df7eaad765b0be949b6cffb4ea85becdb4edafbe4d6c49c194ceb96bc8052d21f3076932a4b3b08321896736f29265a07c9780b6be7970be5970bfc1edd4361f903952c31b1395c85b3176a3f0821fde7a9fba4533373010001	\\xdf88c69071f9b4e6b607a5b45079be7dff97a061a5746a71affa30067b6efc61e5557672ef0bb6269ffaa3936c44d447b32973c84a52404d78cd53c7e248990f	1690008748000000	1690613548000000	1753685548000000	1848293548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xae5b5b5df2da5c3c19f3f27d42b9311de71c241398ac026f3cb4d0f829e1e6103a062327ce82d007a3832bde4c342357d5eafe20da51178ba3b66e42c5ec230b	1	0	\\x0000000100000000008000039f3a9a53bd7c84a0d08a82b1a73c377793afdb4402e6cbd4abb1bb5cdb79415255a7107bc339022aca2bff4866bb7281d2b002a070df3a8ac1d17fa7d95802727300e7d80372adcaa40e73637fdab2ec197aacef27820f6486862db275d9ee287261b394576295831a2792483e711cf750f8467a75bd4c2a1de43c498ed032b5010001	\\x9d597dfdec99d70e846969f2d62719de25f3e5bd4a48aa2e17100bcf0b92b8edf2a0b1b4ad3e64c2fbc1b0b1cb7a9c23472fedfff72c5f4847b86c49ea54b60f	1684568248000000	1685173048000000	1748245048000000	1842853048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xb2a3f36441c4a78e9c27848b4fc849d4249047749c83cd0a94b2ae60ce2a254302f787b4425c76b864d11267d1fa31ba1e60feafa99365439bad940c24899d6e	1	0	\\x000000010000000000800003b0d044c190dff159738ecfd9035dc362a60ea155ccb8b42b301507c435f65c3ce07e812ef08fe0332ae7e2d57edc2fe685bbe3d91ded162cb6bff332bc64b8aa82582904c13c0c8eb45bc78e1a266204b6c3c31724e9ce0898c3469c89359aea41ee6b5615635c73ccf7f9b95208eb26584d05c993b60faf0916058e78df4e4b010001	\\x1588f269807dc0de2be55b53b2ab39e36b0a6a8271c27b3c97eb9c3a09d79cf570000dcfa4cc137172401ebae3f3a4a12ba214750200e61be0399c4b20577808	1692426748000000	1693031548000000	1756103548000000	1850711548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
396	\\xb93bbb90973ad2ccfa245cbb634987efd136305cd8ba9476040d71cfc59858c73ce92a6f8c38e5fa841bc27032fee682df5978243372b2a2c89f83e3172526ee	1	0	\\x000000010000000000800003ad1da03f31f98e39dcfc71d09052c284eabd12eef17bbd11d5ed10e9e17fd31492b48828dbed86d8e51bd70f7f7e79801017d26425563c4864b77e2ae3cb9f4fdade41915ee12a6ba6167287d0382cbe845726e0a40ba71557d212fa80adbab72b4de3a39c42c765f3f02d9eff96cb20fe406025037f1fa500cdbb216467126f010001	\\xd12f6f6e529ebc4067acddd16de966af7f49ecf199b6092d64556f0034a2e087658d22e2dadf8ecb209479be3d5a8e77939c9fc68c5daab382fb01b240b9d408	1667642248000000	1668247048000000	1731319048000000	1825927048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xb97b0bf041b5365de4149ad4e8823c65f962fc50bef1dfbb7d3648650d8bba75a3e690b7170891a8fb70ed831b397279135c4d28625f548dd396e3db21591da4	1	0	\\x000000010000000000800003d82760080313d9d166991f6d28b0161932d856a1c3e82a7a46ce74e438911257427bfdc06e2fe74ad11c7d558e776b33c49e5ecade06fe9da519e459718ec06898d65cdf9012160c313d977ddd5aae6f9ff067ec961f1c83dd9571ea7fd5180c28e202b5e842eb1c8ce691aec12a08d9432a5bedcc17d753ea7e607d1ca47719010001	\\xf77dd2d7b439f8916681a6e02f77c25795516069d31f13bba0f7995b3a1e8eebd9934d8806a3448480e2870a0978df0bd1ade2ef13815b611a49db2ddaf0f805	1673687248000000	1674292048000000	1737364048000000	1831972048000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xbc37e2e82b906979a22fd93f416337494938477578cf5e799927c5085d95c23ca3194d98be44b58d1ef7ef9789ac92aea4b4c8aff0f1612e662ac7083f36579f	1	0	\\x000000010000000000800003ea8bc62dd3db2c85c51b3847db432c019171763daebf2dffa624f7326a60286a74fb9de891e8d447635059017664a7811c6a0e3bad425ddf371b63075df4f88cdf91c19fe05d970294c53533f80df0f97e5bb465e862a4452802ad0bf46532809479105a49c3397c993e204be620f1817de69fda9e5622cec1c7121c21c2b42b010001	\\xcd858ce1c8258a2e828c7b0ed7cace73760ea828a4708832d58247e62c3a2d7afd8f7371f6a25d600b47496aa87cc7b16e4d49b3994806d0cb6b9e9c3ccaab08	1677314248000000	1677919048000000	1740991048000000	1835599048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xbeafa550a29194120b4aaa624a9b9f648166823eaf23bb74c5a6c5c7b4a289bb5e8bc34d37fd1a7fbc8675ded9bb94fdb51f170a0fa1c404e11d8981fcc5ed9f	1	0	\\x000000010000000000800003c0862e009bf2d4906a08cca87c1acc07026f383c07c5ff6f1fd3f2ee96f5691b4741f4e4fc4d9899270b1bac34e5487c41c80eb9106d3b1d178a65dd1b50f8b4785fc3c8d8f72b0d123ac18ada33ac047f23a223387783ba23f60a68b7481530f20830829d744ecd8cdcc74f8822f5a47748b05e99d76545176c1d69a7b10ad1010001	\\x96053cdbe25239f191456017aa961611e91307901b55fe01beadd504994afdd823b509ddead905b4e5573928c91849a56b75e2e635a4bec6ba85ebc67431b405	1674291748000000	1674896548000000	1737968548000000	1832576548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
400	\\xc15f092a18454a09e6d4efb8a6e11a5c40cbd1633a4fe33886e0894cc7a0b1235b8fdcb9eb558bc77dc5cb79b7cf5fe56a690dbc9040200088f13d4a0ca857c6	1	0	\\x000000010000000000800003f8f791841adae196cb2760ab2e1ddd0e3c4e4ef83d66875a606928c99f78d5699787d5ee7f20eca9e550d91d664e05966bc5db2cfd729787fcaf4a7b9e48f6bb24312b181f7560d849b66e486d72240976350d372b038e9f3eb56505d1d2a78647aa3968e4fbfa2a76b89a72a3c695f16cebc538c206e4ddf637b639e88ac8e9010001	\\xc3efdc3d008bfe30bd700901744629c2dbdc19b641d9987ec803d2d5245e529a520896f15e21eb6fb250d1293c7a4fd34816019fa43c2058642f9eadec6f9f0a	1661597248000000	1662202048000000	1725274048000000	1819882048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xc353b27c61ca0514b97dca7e3849c9f19aed6fa5835996e1b7f0e6c557a3eefd0c0417b4aa7462c7fbb38c5d104584a6dac43c3167f932d4f101671a159bd09b	1	0	\\x000000010000000000800003d47f492ad193f8ef8785d9bbd9bdf5bd06175500a043b0829a33bf002125ac9b5e3f474403d5ded620413c4c0273fab4ecc40dbff03aa4d27330c30af638df696edb4344da4c3103b22d1a2440ba7b5b86d55627f6369ae2161e6b0214795716c9ef0432110cc22c5869d7cd4b0ed150782aae5f915ff7edec4b2e694d24b161010001	\\xbe4a289128b1cd05dec417b3c8226dcf61036d6341655240d824cfb2f02d97ce925f24f61f5b2f4ad9a2e0188c1f4d0ba395855e3a39b8816122f47fd260a902	1667037748000000	1667642548000000	1730714548000000	1825322548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xc5a385a860959b8eb12a37ed4a3d2e48fafca637d880779c1aebf02e83fd8fad909561c372f4a15060ae97b4ff531055a02e34ab76342e53d159303a62acb884	1	0	\\x000000010000000000800003c18e841dbd637cbe4204d3655b6c7935203b50d6ecf966261e900ddf8ba3a8949d2fe1fae0f94a1b338e6deb9d6b1abfa057219fa336464ef55cb302654665d03840e3912f9b24e38cdd9725c8d7167fa12d1823d68957586d4acf30839898236b2500fd38f26bac90f972830dfc78f484e653dd1bc100972697645b9280ac5b010001	\\x16fba0aea6d54356f32cbe973516e36b65640d9ae4d14d1207709c7830322fe4da676ada1dedc4b428fb7eba067ea5c8aa39b0cae887148258128bf6662a3f04	1680941248000000	1681546048000000	1744618048000000	1839226048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xc69fce8184d46c27cf867be838f2b4f2b7958af678ce1dee115e9125e257d960c8863496da1ef4fb341294d7899a7bf4b169b758c7c013738f965422dbac6484	1	0	\\x000000010000000000800003b997fef0990e7c86605fd1919a4d2672884fbd11f7591edd2087c317318ecc72c2b8aa4c7a6bd693d21f373a223290cc77fdc8a765dd4be4c71f56dce6a7cc41f3a72f9696631163816439b02563e8bf9f15f12d43e3cf347bd5a208fef76553ae826ef4843b01bb5648d79d6d4b57e97976cb2939a9a7b8cf533714baf2ed9f010001	\\x5630993442fa8a05d056f4ff2358703a44458a630c32b80ac42aa1aa0bbbc8171358b216b7c10ba63a342517a769ea25d49205739bf362920d6c938b8355d507	1675500748000000	1676105548000000	1739177548000000	1833785548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xc783bf5f1aebeeeb78bd86ac0b5353ca9d30b2b54ecf4384f10cb70d2f9b9902b5a343417817b17b8b1fb0c47b250ac06b32f9913e47d1bd5d401daebc2df822	1	0	\\x000000010000000000800003c834f1b543b1cdb5ccdfda2778995f030cef9a1407bf91dea232814c079e8b2f81482d0cc5c5294f5d5b0f35907ddaceffcb864afe88cedf4a23667cdcc3b5322dd78984921b0dd437fc42474a93d5c0454b8f5a89e5e78e44710498a2d29aaf3d9bb908bec32f3f042b5dbd2628a16f24b29c6aa9e7c512d47a5cb146b4642d010001	\\xf6290bf9558bbd28466e39dda94251702838fb5c4c250ba9706525bc353cd59c12fa3acb668c483003da3f5f2a95116ac05335b1b8e90bffeeb14213fa77960b	1672478248000000	1673083048000000	1736155048000000	1830763048000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
405	\\xc9f72f0437972241d913e64f9025ada0fcf82c32a91d300c95eb7b4506c5cfe61fd4f1a99dae0e227a4048b48b501a26d06e6d2f916e1c0b4e57d3d2982bca5e	1	0	\\x000000010000000000800003e654eb86d9c4b46e994edfc9e155f67c6d7667a8ca60fe4834c8e21766155754d770d2136bd2090a8eb4f16d977b0936f4300d814da2087733c85f225fbe5ef5aab045aee3c6be3e1bdfaa8da908fb207664c6dda12684b4652d274697e8ad4e7f318e5fb1e9e9b5adb238a63c592807c271bfc3544c6a87b08872552ebe0c05010001	\\x3c983a2c284cfe3e8f92a1303e72cc3d5eb2dc93776d4c150f692edcfaaaacfe41c7218f6ef721bcfc80ecce3e4e8d0e97d5cb339b6f06f72a25e80d6cb3f808	1686986248000000	1687591048000000	1750663048000000	1845271048000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xc98bcea349601cc078fe064e5c3c86b739640d398365d2833429f8dadf227b3f10b8177fef4893f2dbd6f9fb79acb69a5a0e21860989fc171c3fc68365553ab3	1	0	\\x000000010000000000800003b795d3231d7162b1009b3ed482ecad494b81e35a698e612920504b7f6a7da85315edb66739776b0d19c6ef8e88e8f7a89bbc864cfbcd4e67ac6e1897575c96d56f8c4e52ed05ab8cec0f40a9ad940e62c84a4e66f70d56abe98db0f6cde5bcf479c1b50298a1bd98e248c11a18ad6ecf209b3b83c578ed7f2e1bfc4bd431bb97010001	\\x36de372fab6eb3bd2dfe91645d2e2225db9879aa27e200ab64e9294792c1f350eb6331162e5e9127e07029a4d1dc7013a8d2971bc6b7205965e0d6cec07d0106	1690008748000000	1690613548000000	1753685548000000	1848293548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xcb9756a7fd2d9426b3d43a2822d27d991ff2e1a79e4ebefcd5f5925d426a9cd6f144244a4cd47ddfd4f417a287307d85eb239bfbcddf82a5f4ebc397e5158440	1	0	\\x000000010000000000800003c064a33a064939ef8a3e95ba441b3cb19cd2d6e68513aeac1f8ea43e491a27d7f680e0f0db8140888c29d3c4785921b8cb8871a9ca7ab0c3883475c6a34f85bf77393680ed1e5d91b5e48bc595fa749862fc730938be9b3984cc601c3c03d1225276a1cf66be3bec2ed3f1cbf58718db9009660a23e9ef0afb8be580efbfa64b010001	\\xe851f7b73af61022cee5eeb25064e65f2fac8d8c9faa4a9f66772c3d0ccd464509a1ea297d9685b5358bf05a433da445432d61640bbd9f4376fdbf09cea5bc0d	1692426748000000	1693031548000000	1756103548000000	1850711548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xcc1b89e12dfeba6c53147078147457a3549f3acf3b085949d055c5331ad272ae3b561ff5bd93c266d5c137d76aa3adf905a3d08067e0289ddfc457e8968d9289	1	0	\\x0000000100000000008000039889033591d0cb5e627b63a7f4b1d08d3971fa02717ab7e683d40e43bf2033a0204213bf615171ac3731b5efc64abebbda5e9a21c47251c2ba9cc105b93feb082992ea2949d27a9d1e583a3cc0006c15d06dabf44f5529bd122490d53c706cfd20c63fe8d7b3ca001fd0dfaddb0992077f7647b0210d6c0b2ffc20f2f28d6e3d010001	\\x152a8c3c1169949305f7b97937e671d9a6bc8a12c9d3c0a094bff89ade3e9508b083b1a3029cb7d146b76ebf3ad622709f5bcb13479c895baf6b15758277ea01	1673687248000000	1674292048000000	1737364048000000	1831972048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
409	\\xcdbb6f3690e5e0cbfce910e0bbb7c75bfb2ef0d8869e07bac245aa11a62e61f55709adf04907ed95d35f6da03572dd6aaeb5536f9264557fae2b662116959988	1	0	\\x000000010000000000800003ec4dfac3d47aa6444bc83ce9cc7d98edb0cbef045fd242159376fd19943b367d8c4e53422752334c99698cfe6305aa7e113de30b78c894b0d8bff3d7ea5893499088a38936ef5e560ebf90b18e111c71b8be7e63e8c23574e307f9ee79111ac9855cc50698188c9678fc7b49ba4e7fefc24b146b113a5468f1169cb08c5434ed010001	\\x57342630ecc8fc9dbefa92c5c9523541c9a74cdb740be53d92411d24838eb9ee99e14bf0fd4966bdcd22a85fa52aef453ffa74123866ebf297ca98e647ebab0d	1686986248000000	1687591048000000	1750663048000000	1845271048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xcf1bde5e510b314e5317446ef6d7d4838bd630ae431539a7f0a2ba32e96b44c0523f8f5bb9bc1c1f7e47b72f703bd2b9ee0cade156e636f38088a79d148a20a2	1	0	\\x000000010000000000800003e58471bc930154c5a8bc040cf1fc28f57aa6570833c9ac0615460a21524562b11ed95eaddb805bd5641dd18eb7bd51abe237c16e4d8a2c0b048e7242822e5347abc7d4e88e20430974212ad0f383af1d0f1ee13ee1df1f5371ffe30daf3b9235dbd44ed32c8ae546810ae9c9a77d3d84c8fcfc9e2fe27ad0d29b3a9f63cf2bcd010001	\\xcc74d23300bf23247f6be8dce45e8a571291c9b1a81043f894b9295ed575aaea14024009d3372a54ece1f0a896836cc5661a500adaeec221808999dcbbdc1e03	1690008748000000	1690613548000000	1753685548000000	1848293548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xd4ef0baed89bb1cfba6e0312eb78d99077a0263506a05b3dea0e1aeef3a5105fbaf9c024dd9c7a0cf0267bc461a727d951f22bef47af7bcb5e7a4f931fbb83a1	1	0	\\x000000010000000000800003d6e5aaa647fa0fd5075ef2cc7b3cf576fec6c1ce27778864f463273f6e3e659824e47edd11c49696e75ed62b840b3a5796c1214e3637b762acda7e7fe1c934bfc9d0f58a20da2743bd10fac40697e5453dc5ffed34d03c8d66c9e84e86e38e3fe41d0a70fbdd0120f6897570a5dcd04d1f9245e972abf80b847fd65322dd2f55010001	\\x0bd6b2da101f30de97fae586100010bb6a3d8ce3b4e4f99bb3857fbdbe27c31b99455aa1b918ecfb2c463d2cf49c2f85ac052d58d855f70a8703e03afbc54c01	1685777248000000	1686382048000000	1749454048000000	1844062048000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xd537aeb38a23ff7a0277be011a2aa638d4f16594caff994680ce0bc9f8e432c20732189e3a9075798e28047f125cf86c3393bf646fd82c0790f89f3d43584005	1	0	\\x000000010000000000800003b688f451045910dec9f5eb474b67f86f22e590ca34255695554c3cd79c146c534acc0157d9a32b38dec909d24bea82f1ab3eebccf2e856a66ff8467af21d3f2e30345351de85814d399cb97ff7b386bc9d0633f7886131d4d237a427e29692aa2397fd7de58ea8eeb042491497120389bbaac05799d625fc0678eaaba23dcb15010001	\\x26be239c78598444283af417b8406090a6962dd618aa7268eaa6e73b993fe5e28424804b6f9bf895a55acd0dc752eee1f521bb01dbc1e0923311835395ee910a	1664619748000000	1665224548000000	1728296548000000	1822904548000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xd72fd0edefbfcbf8f6fdd874437065cf059a2ec7e009c3e39cf5edbba53e17c396c2420f1a333c4358ac2acdb5add8346414773a9020eef356997f60eb939607	1	0	\\x000000010000000000800003e3e69275e5c8011f6977510e66c32aaa4bb77906d7cf5781b3bae38b34baf19238458759df247e92c41b6ca38ae2773bbcb74bbb02c7a1aaa97dfb95309ee8f2043541b94cf7fc726228284fd14e8c1ef617c75f2751b00472cf03d8386ef9e5e812f64291d297a09cee78dfedb8c057d0ea9fbbf87d8ff46665598a292ec72f010001	\\x6b801212eaf8a5a953b4bc6672b288b57f483da4ef26536f22f2d1ff2eb9ce90bfa93b434dd58e7d5d7c65d7540c6f2f34e07d979402e8d63d176ef10ad1c10b	1683963748000000	1684568548000000	1747640548000000	1842248548000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
414	\\xdb872da1c618428636f163ce9ee7683c2682d4e65691d911f9d00daef7a442e1fd25b90959c8472e9bfce241a7ac64d4ce74f998a120fdd68f828d65ec2f59b4	1	0	\\x000000010000000000800003d7aa4859fbb8df943d1e1599b5f95d191c546627783986090120aafb9f9e40f148fd036bf7b55645f4c6c5c78a5db254275c2dc4f8ddd7a16f331e5a1a2120960aed05628d5eb563f91d3bc166917e39e20a8362d7d90e43e02bcfc15572d0280269c1e129f1196bf11ec36ae87738aab18cd0607d3d7fc35e5ad6a5a82abb79010001	\\xd3bde837db6d7a246ae75e110588f46a70ed93c8f9bc403ed53cf4838fc45f074929a05fcb083007a062b624a2515eb2cf4edcae3f57dfbfaa52f9fd03b59400	1667037748000000	1667642548000000	1730714548000000	1825322548000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xdd1bfd0f055dd5dad5733bce5de96544be33874cfdfc9cb1107cc4489612055cd05b6b8f2c77fdbe13a9ee7108a2a0facf2dde9f35c7447c14b641891c99e6a2	1	0	\\x000000010000000000800003de6539a79248aed6fd8b7521c9cbce0d7f31f7cc42102e7f69337c54e25b8e34bcbbb59463d8c4a880420d9f8aa3393c13c003d2bc88847190ec82d7f19e23c2e913635b83e85bbd4329d6c16bd316998a11763408b6f0b203131921f22d4a2d441abbad663858c0e869bd02778d6a1d1ed53befcdb0a700a2a22e4e71fb1cf7010001	\\x86cb5f67467b4488843a088b5bd44e651a69ce2d2210d8cf1b949b085ee37b4f2a33196225a2b44e330e988de3fa90fb33ede45224d9c0ce463274175da73c04	1664015248000000	1664620048000000	1727692048000000	1822300048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
416	\\xdd4b8961e69785a30ede4a74bc68e14292ff123542a68639571c9c4c89f543ae9e48f0692a78a0ed27d7c34d90c6d89a7457423ab007b03fff17c9a82c627ac7	1	0	\\x000000010000000000800003c9ec883b1c06d6c05fd3cc3f897bed5471e8fd4d6ce3a5ccba06838fcecf02547cc30f19dcbd23b5e8a3d9900f72ff23d9a87eba82115a05eb7a9f314d12d318ee1d3c2a67ed66c0821536eb21be2fef391040cf830d69cd4e992a43908bca32a30fc9eb215c30fef5681a1a9d11fd8d09d41c065a9d014e76741c319196d591010001	\\x74f9252765607c1003227b0f93bdec6d8e0e3c04f6f71102e6a41647d4e04b21e4699e9d186b5a5ad725d29fbdde87e17d49e75127fcde2c889eb12056d68302	1686381748000000	1686986548000000	1750058548000000	1844666548000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xe66bf82749c242d58cb0226cae92e3ce4bb017fee34494b9f0383b92c099b43a6bf0a8a3caacbde3a49c4fce27931d160546072be7ffa60eff0766c55fe7551e	1	0	\\x000000010000000000800003e0aa9338907f0d3f0188ee68da35553ee6794ddb78ede94168c7dd8c0f34bbacbb8e3b7b442daeda9f5151a8618d6dc7236bea39ed04b63acf4f115fa2b5845fc4ed26fc745a620685ec1c5c95d05a27bd4927375f354dc2cebd8d053e464a33638ff0c8e4427cf75cc799fbf7be557882f4ed726f77cca32d9b85833cf34427010001	\\xcb6bc2bbf585bf7cc816e3b30e2171f1fa1612aa9323a03077b1f4f4e9baa37499f3d7f1abd36d787db489936ed4a4a4c000a9ae960c0596529ce644988f2708	1670060248000000	1670665048000000	1733737048000000	1828345048000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xe88395c3974f4d145cb930ecfb4b73458f423ddeffb9243af0b3f026e956ffebb799dc8b8f12d2f69dc7f33699d27ad649a491cbf6b633cdcbec3d6e00270897	1	0	\\x000000010000000000800003bb62a968626e448e38d121981fde6fce2ea6671813ae08e3e1b179d4311f7e1040a499efd221b50385a6969df3dbc96d385ebd7c57b49ef1c0d803462152551a6bad6d6717eba97136ef06b76f588b9fe9136fa31b9bce6d033bc1e1fd908802101515943ed92b9178563f9611499ad0be7f0030f502790e08e51d6cb44d1c25010001	\\x78288b43b6c0f8a0ccaa7f25c9794e9ec4858928e1886f1d4f5a3177218fa1a74cf7c3fa00e16aac3bb348ac1bd0e0887cc5a84431fb67ea1fb977e8b3ae4700	1691217748000000	1691822548000000	1754894548000000	1849502548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
419	\\xe82f63ac685d91fb4810bbb5c9eca81ea78028bf0d3f302965914ec02a263afcf932e0e733402fac5808d3af23947bae76758ec1744740494205b240d55446df	1	0	\\x000000010000000000800003a4e6244e743c2cc57f8476a9ebb6e5a65893c86205dcfd8a97fd8d53074ae42fb62edd2ae661abdee31ceaa34a1c729f1e57b2704a782558b2427eda77eba4cf3d55381299438d1c6656a3c6e641d5c8b0b397cb932b07e4c3d3f69a9bce4a315e673703206ed7362387e9516368c959af3f32dc5437834650d1fc9e61db798d010001	\\xd3d8c44dae63a33a1cf19df6a42531b732d712257c33b37e3788460659f9d6d33ba57f8f69c7217ede6a0af746207a8de2066e4eb73e549759333170ed6cf201	1690613248000000	1691218048000000	1754290048000000	1848898048000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf0cf7b89a811f067e127a17362b882e8889a3aab7ad704fecb11f2369ba6dd1760bde2168cc126c0f0bb7425eec7954bc62f0e6b0e3ec462e253cba25fb56890	1	0	\\x000000010000000000800003ac5d6f75d7a724fd9bc7a5db61d0f9b22cb31f53cfe6aa2ec698e961a9be13c78402bdb3cd550671670589876433aad2b4627df286469d7c8617013eaabeacc4574921a501d19e35921dafa2e3f69d3547d92257c9b9728f990ac1e8b5dee0deb363c335bc87585d5b3e1cbc3fa5b57716e47df732f2ca1c6d4ac3517c7f52c9010001	\\x7a88097eed3a151ba2fe09d4748dc0013acba99bec483a26e099a0bee3b6d5ef4b40dbe856120c771efda9573291d4ecc4f7b15d235f18ceb23bedf3aa9db003	1669455748000000	1670060548000000	1733132548000000	1827740548000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf4ebe3c77fb2bfa9801fc1108dcc7d4d65637c943b2838a053535f50df271a0cb7076ccca98def1407d4d6fbdc357313a653322a5e87617d6a7a34e8440b200c	1	0	\\x000000010000000000800003b33e218f22508bc77fb7b1a4a53b6a8a21b8558b9188ed1a028c62ce9e10311ba07f1b9d281de249ca37fd3da0b094b165695c3ebdb6e000ab504167bb29005300e098d938ad33d494d623df50b71e3b9e7c5eebd9aaea3345333117b5993064224bf761830aea57e51d87af6860d7a1ebe693e71f45ad58c9af62f336dc8065010001	\\x0c3ebc33fea2e9f34af33ecb614db9b44f69a43e96adb0730a0965799652f0b6c60e27667446865cb4979f59fe4df8310bd6f31d37bedcc0ae0274aa4363fd04	1673687248000000	1674292048000000	1737364048000000	1831972048000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
422	\\xf7ff370477526cd48206fffc1c31923644b1221ead3918641974112230c2edd0889d6b4a8d2cb6c2058d1ff466a7553b52574a26f80a7a7247d57a7375d5ebcd	1	0	\\x000000010000000000800003e1764c76dda28701fd620d94b5d1ae1db8ea883da35fd99fd594cf94f9b61ccaa921de7081b07789abfa8f98fdb7232f064df7bcefd75f98e8ec613523554a697246f3a55e139511c5ab031407c6d72d40806d4f2cc1ff6be8893318e8689d67bc2e1133cda299bb460f9bd45d8ca44d4295dd352d87df9a8e7ef499d5389937010001	\\xb69bd4c5c18a78e7560ef873fafdcb35020cffbd49a18d940f484fccac7909ec898d453ddb7772bfbe0cec3317c86ca09ecd2360e179d6602527f6f01ccb8d0c	1660992748000000	1661597548000000	1724669548000000	1819277548000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xf8a70cc95a205ec8cbd8c3cf7e026f5e314829524ab6ea33a2543404963389dbec071c5e9ff3fdf6942f00d0f45619ab128294c38c4fc0bfabc16dd0be28c198	1	0	\\x000000010000000000800003bb5773e6090a95d0799352a6cfa2eeac51ac005dd67eccb65d8cf14b503881372a1d59c4b9ffec8aec29936aebc8378787155810477f8f0e8e3fda2ccebf4396fd989a075468f6f299f9a0c02c879b6b1ea22c37c3d4289c58f37cbac04f7c9e153f2b7268701eaa6596b6ff4145d5d80ab7375c6462c42fd953337c93575333010001	\\xcf07bff17d9ba272fb9c8f09236e92b4cebbefac45ec95cc8f63b996531474e5e1cd570f988d8f2f4167d30e6a4546f598ca4507cc4895bb9467fb16f3339701	1662201748000000	1662806548000000	1725878548000000	1820486548000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
424	\\xfc4f57907e816605b04846004bb4bef7e356aafb0aa2f0dcfc5f58f1b55890b202158fd65be336281b9f0cd42ec377b9898919c1fe68e622195c140a959098d3	1	0	\\x000000010000000000800003c6cd311b26bf4f0ffaf8d96b7f8be59e5ccd76e182b4b3e271dd42c3a70937ad027b5aa308772f77f71a1d516748c35c7d5a621ce5194798d137d5550e64c010252ac56c84b97c8f19f50916b81d46e96f71c883c1cc9580bcff9c67997458796e9215d6201a1a882e8d2a556f24cb496be4ba2dc8ab1fe7042bfb7c313f72a5010001	\\x5f1985775a814b5db139217a6c457a35912bac0660b251daa83d2a714643979d6a8ed4959faa29f5fdeab9abd6ca7933dcc8e6f2071f4c44e2874d45bba9190d	1675500748000000	1676105548000000	1739177548000000	1833785548000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660993676000000	888445849	\\x633286aec399616c6bda89d40013c5d27e83e34b10dc958e2c6adade957a00bb	1
1660993708000000	888445849	\\x018cb8d9be05315e7892bbfbf44b376bd4190f9b36956a96302f5d9943eee6e3	2
1660993708000000	888445849	\\x028b2f54b389d85b20e243a97645d85b4122896f343bc22f96e506ce8a053a61	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	888445849	\\x633286aec399616c6bda89d40013c5d27e83e34b10dc958e2c6adade957a00bb	2	1	0	1660992776000000	1660992778000000	1660993676000000	1660993676000000	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x70450b46e592fa22e4f2edcb92617c60e600e1454e9bc52da02397bc862901f139a4ab579932a8810809b880982464c45cb8f4a4c075bb462131c5efdfd965fe	\\x2e8eefa372082417787ce1b4eb14d366920505f3e4b861d27716645a850aaa0c81cabb0c0be90dab495a24f6e5a5c8a04f3be5f83ab5eeed6afc99af122bdc0f	\\x45e24ca67c18b2ac81022211e47968e7	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	888445849	\\x018cb8d9be05315e7892bbfbf44b376bd4190f9b36956a96302f5d9943eee6e3	13	0	1000000	1660992808000000	1661597612000000	1660993708000000	1660993708000000	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x7d0db3dc8c43719af46e3d51fbb65e0ef73d4e4128f0156738aeafc3d59de0bfdb64e63a40804e00592824e4c9c0ed72da900017a28a4f7e30658731044df108	\\x12bca2d6637aee80503434cea8043e1b3e286e3943ee5f653284821fdfe27d6b8ec4fc51822505ca8fa910709fddd20e96ea61a1c3fa14cd26a1f9fc5c29b30a	\\x45e24ca67c18b2ac81022211e47968e7	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	888445849	\\x028b2f54b389d85b20e243a97645d85b4122896f343bc22f96e506ce8a053a61	14	0	1000000	1660992808000000	1661597612000000	1660993708000000	1660993708000000	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x7d0db3dc8c43719af46e3d51fbb65e0ef73d4e4128f0156738aeafc3d59de0bfdb64e63a40804e00592824e4c9c0ed72da900017a28a4f7e30658731044df108	\\x66c8aa28c4227dda29a8d34f23ba960e3a641acd3d758712f50ec7f12ca84292397621304af41b5cc6243fdd1e89103add89c236d2896c74cd2cd7712c78620b	\\x45e24ca67c18b2ac81022211e47968e7	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660993676000000	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x633286aec399616c6bda89d40013c5d27e83e34b10dc958e2c6adade957a00bb	1
1660993708000000	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x018cb8d9be05315e7892bbfbf44b376bd4190f9b36956a96302f5d9943eee6e3	2
1660993708000000	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x028b2f54b389d85b20e243a97645d85b4122896f343bc22f96e506ce8a053a61	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\xa05981fa95898fb68e4f8af2082cffbaebf1f6a4837d28a5b7b87fccdeb4e81b	\\xb65c761900786f2dfc75af4932c019f9e85d1f7ab5d66bf2bc631d39d8a55333b8c6ae41e451cae1992be506ef037381ec5cba426a67aad07898c9095ab7290b	1682764648000000	1690022248000000	1692441448000000
2	\\x8835f0375cd0db295ef92c234d101c532b5b0c199a3944b1ceca758275d2d43e	\\x7f056c949e5b10779aee48b83f05ef6a9f0806c17b81d0194620bb193eac78bf2f8223a95305b373e8aa7595f4ef707adb8d2734a7526ce41ee17b95c47f220b	1668250048000000	1675507648000000	1677926848000000
3	\\xeade5d22e096dc0a4e0f93adb200b5536a2d0fa01a4305ee7fde9af8d40fc07e	\\x9a10ae01a67bf9ad6515cd80d36ad6a36ce3e91ef37beea5153f3d0725c0e627028417bae1950115d2a38f4eb6c1658c17c852830edd2dce07f3b2604a592102	1690021948000000	1697279548000000	1699698748000000
4	\\x770083b599e309e55121b3ff2b8fd442003ea91fad7c5cd3c4d1a02aa7dd9345	\\x98065827feadce308caa3bb9d59ea82ef5f74ff21965ce275df8c9c48bff74366a025d9cd828a6ed8e253548a101f092a4481c494e46c2962c8530fe9a046c0c	1675507348000000	1682764948000000	1685184148000000
5	\\xdadc5cfb79a7b94e6d311f6033f32442d2a4791150799ec796049f6f7772a8ea	\\xc19d70df3db53fe89fe00a8c74fb2fb06f8871ce97ccd812a80b12a9ea181bcffc27b8e365f2d0f97cb34c543741932805a30e72bb6f964b2cf8c0101ba6ba08	1660992748000000	1668250348000000	1670669548000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x23e82a26ce552adeb60fbcf572c2a20bb18eff0d2b4b8850507f1b47257011a351daa9659233d807a2fc083c259a0db3ac774bb27e2867cef4d8e3c055c1fc08
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
1	339	\\x83d1517856b9c095507d199fe07e4cdb4cf5c253789883ae839bfa747528ce9f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000034fef35c3bc5d21cf748ac7dd9a957580baf82e370eeecc4a1d7442da330718ba2475251dafc1e4f686008f2ea01cc36fce32e60ae5dc6098e00a8411f3f4e89649a8178b79f4c3d0f1821dfda65a47133f03c6b78ed3397486cb28c9f95fd1409341e346c02353575a601d884f22375ebe1fae870a73e0ccfc5c308e5f92d90	0	0
2	330	\\x633286aec399616c6bda89d40013c5d27e83e34b10dc958e2c6adade957a00bb	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002069ca482cd64c1b21ffcac7d7b444b3f957eef598056817f0c470f966f26dcf25c7b9a89a97a377948e5654e3ca682c7ee5f758e94f14bd0dced9bee9da71a551fe9f4c2c9568183e2ae9e3e116c10c4f76a7df0e787204c7723feff2eb359821b9440607795278b520170f9872809af24fdb9fe00eefcdfec107e64d94d5cc	0	0
11	400	\\xeb654938c819b0bb14c2d3c802d83ec81f3643500205bfa628f7504fcd881b5b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000be5a6059816f23e414377d6a67b0b62126786d7df52f63327cfe2f4604b8edbc3ec859f367248b5f6cec700f0b9ca7c274cf7cd07b5738f9f19a0874400fb41d22907044fb88c3c9d754486c441e0d4c40cf265ea595cb8de29193d8396bcf552c1586f8534704c4092066961bb9d10bee1d6b5dc37d82801cb3b96275b8630f	0	0
4	400	\\x568b96011861894e719512095d1f46fa9d881b8137f5b4cd0d1ba4cc1897b614	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c5face4e414091109c10290b823a553a4bab62587fae4effffd83c3b3b1807f234f3a0b173c3a0c3a02d306df188c8ac596d88ca6ced76f6ef41d870100838a46aef95a9e599da760684870f81ad42596a813ca348dc32c9518eb7668e277dbeeea559aab90264899871c02c49d3e8f05d6410088260734c08539d235fc043e5	0	0
5	400	\\x7b9259049b7ad18d3577e06a3cb610f83d657d4455432db966f845365ec9b170	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000f15b0de7494f5c1972e8f2c5e8ddc06821880bf7479c44be952fdb4430215d5279b10fca0d6e9f7f245b517be49c608157720d6fdb9ba494703b5b8fce4d352375e33a9498305343704d72f415ab7a802bdf5536258b896a59dfb2eccb7e682ca58280e97d8b7aab2c9a81fadb9f5cd344ff5e7df6298c1a1b16ace4cae73eb8	0	0
3	109	\\xf65e32d3b140375585761111995f378a91956aa4e22b5f345b771bfec46984ed	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000024024480bc1008db4a5c72ea05c3461ed6b67e9b2c372ff02ffd8e306787989675657dca542f96893d8aa3e29c9398d366efff9eee14cb46c111a4e051c6512ec3df013002899f1ee8939dbc036d61e250645bddd722366c3cdfd2f5e37292ac42afb8700a257b808456b5a77d59d90fa74588b95730924754e8e8563331a0f9	0	1000000
6	400	\\x74e410ab1cb0d754d381dc6945b8a39746c3394fddd3835cb652db0065a126fd	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a04ff082485afa4f0d08429287a8f072778ed0556d3f9f7b3ed1359af491398635cd6daebffb13e6ae41bbe38132c79a5ac4cc04d10224413e15f5ab104e11c363fc946606ba32e80accf0e569e4c8c4137b2513af879d1a36c4ae121a1f94b4ba590adde1d00f9ca28181ea2884db4eee10b462c85a0050eb37dc4d9318729b	0	0
7	400	\\x87a848ec66819a7b08f1add99da9b10806a82338c54e8c531f01e185d67f29e6	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c5f1b238f1d02586cad3cb5871c9685b493ae530ff4ce005ceb5fcff5d66290a7578c25d53e063ef094fafa0ce91ee3797c04c4ae314b595e07285fe25d37a72428cca9f3792171ba1d96d6838ce53997f605ac48a2b12ef4df26d0e4726f53dabaf5267090bd2018e9e4d31494dde7c0d9b8f26ca2e92b15e803fa39dd8f305	0	0
13	22	\\x018cb8d9be05315e7892bbfbf44b376bd4190f9b36956a96302f5d9943eee6e3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002c2809199c7f8317dc26af934c21b5ed2d569ebbf468cdcc01030ae48d6438c6f9b1d4402a238e747bae581751f493f289e90b3f9ac8197e2a11a40422c4f2b4c7118a2db32e281aceb5311ee22122aaec56a425e749d2027efc089e389f2c22eb6cc4ea957853005e40f41c67aad236cc77ad24f2e1abda1a9e3c6078c8f155	0	0
8	400	\\xc1a720a32217c9ab419510f58f10a807d5e98d876007be228536defa16aff2f2	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007970b83912191d179f2f5e58e8b14487c8dd42ad0c1bc3cc3c45e0c5c9d58c5307aff0786f5846d0c705c1bab926748368e3c8d822ca47b12852f33f8f5451a61d3508f2a4444be3426f395c941542852b55fa64cd94673d12ad70866a427d7a6d2eaa315e891171929b54d2e2ee4cdf07e64b3718f338af85a24028c9f5d902	0	0
9	400	\\x9aa64614f4f8e0cf09d605454d33bcd5d1b3509e3b463d94731b32d663583de3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006628fc378524e278ce77ecdeae1e698598c0454827851e70c764ac913d87da9600bf4d5a4357bae79503046b6d10ff45695b89f3dc8958a48c2cd5205ab2db60f61dfbfe20db643bf44ab3727315bb9a92cd8575c99f1707678d31c4b881efc593201c2960b24f0f76310b557b30aac6705b385d897716bbd6555a96a366cc46	0	0
14	22	\\x028b2f54b389d85b20e243a97645d85b4122896f343bc22f96e506ce8a053a61	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000049a34b671f9109577e509b638b5bdf9780e6c7880c875765b6bee6188d90177dd25dea3fbb68278483cd4256eda308edeab174493456fb9b8a1aade3dff1743a38bf8e8af53b468bd97f8df64a4d4389d43dc71af453174ae2f12f3e7bc7d9e1d6a3956f4338743178bb10e381b858a55ae4f0191589145f18e8544bc8830b30	0	0
10	400	\\x9b2a0b7a26269cd76a7e4f086712d2ca594c433158ff854d8e65421809042526	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005479cdf66070f75f97b939a772eb69629148149276148c88cb9a70309204fc494c55049b7d86d436aca528246ddfd68bcf7d7df2322f8052dda36ff3407ceb6a4e644653fd5fd1f49264cba95119a78c1530859db8a70afbf93476dbd02eab15d693bc98e8228e3b8d13c0a2a15a38f7a519860a38fb6099524c33d63f1141e1	0	0
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
2	\\x83d1517856b9c095507d199fe07e4cdb4cf5c253789883ae839bfa747528ce9f
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x83d1517856b9c095507d199fe07e4cdb4cf5c253789883ae839bfa747528ce9f	\\x8c848ca86a01892d7dd40116908c3be543e6959e625b295fb04423a39fdcb22f4f63639cc2dd98e761d8a39ccde16d28aa2593984dde58f6f291a6b9de65c101	\\x9e8c6415d4b521de4d66ce6e9334518090b480a81c1d8b114b397ce2a3d1d9d4	2	0	1660992774000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x568b96011861894e719512095d1f46fa9d881b8137f5b4cd0d1ba4cc1897b614	4	\\x5694ccc28cdf890fc43396532096cf0f8b541f3dacdb2dacac86f79ebcef8ba834f83188bc3c89e9c0a65d4023b18466229b08011076e7ace1cca356cdec5806	\\x823c3cc2213e770ca10def8c5239ef95e507b23d505653b53ded08d3f6346d59	0	10000000	1661597598000000	9
2	\\x7b9259049b7ad18d3577e06a3cb610f83d657d4455432db966f845365ec9b170	5	\\xf18a67f231b456012ce4f52a8b00eb2798acab00be23aff43898f86230d0c0cdbedccda9fd9425b84dca795ca7ebc505633c48175af6e78fe17180192b037302	\\xca2dc578da7da75c87154f67376f053aa2f3000cbd6cf44f4931270b81eab5a6	0	10000000	1661597598000000	2
3	\\x74e410ab1cb0d754d381dc6945b8a39746c3394fddd3835cb652db0065a126fd	6	\\xe4f223e60884e5564342cb72e6c4049df1eaaa8900604f71bcae8dbd8a2114843e2e2d66af8892acc5d0b9acc591cf5a51b817d959a5f8fab6c13771ba48f102	\\x6dfe60dc3a061a3e0a58a89fbddbbfcf65207d0a3f27acd9c3f3ce9dae3cac6d	0	10000000	1661597598000000	8
4	\\x87a848ec66819a7b08f1add99da9b10806a82338c54e8c531f01e185d67f29e6	7	\\x542289e4bb010a8328d0e7ab2e71bd122a154b987584d5653314c60be0e7ffaf554d2704b305d70e95796f232b6ef4e0b6fbbc4fd2df19fcf5f03bf37781ac01	\\x53f10f5d4293d2d9dcda348c1afcb27fb4c68e9e94dfce8d1d7c49312020917f	0	10000000	1661597598000000	5
5	\\xc1a720a32217c9ab419510f58f10a807d5e98d876007be228536defa16aff2f2	8	\\x0555053edde7154a8129d22fd97b077da650799f3f2486486bb8c31fe8e1aac3758826b3ae7763278b63a7030e4f8ea11d52ab15ddff9a19102245c17061cf0a	\\xe9bbf13a968fa3244c983a17d29dce2bfe2a883b397df7024d5f97fc0b33585a	0	10000000	1661597598000000	6
6	\\x9aa64614f4f8e0cf09d605454d33bcd5d1b3509e3b463d94731b32d663583de3	9	\\xe3efb6b7ab0d90fbde47a9a2925980730c9d3d5015022bf57c53a5bfe762f63ec810aadac3c915b0a54620d2595b38f0b0b78ebfb139a0e76f605bd06f0aa20e	\\x74a02dc9f659b33b80b647c079c08e53f99751b8cacd5c2db5a80bbd3553d427	0	10000000	1661597598000000	4
7	\\x9b2a0b7a26269cd76a7e4f086712d2ca594c433158ff854d8e65421809042526	10	\\xab65ae97bbd5771ff15eb9af302ea0af273cf28e153de8035bd9834c9ecb25f78ef778d1c4a6c600c7727e38984683d17567864e775eebe0d38d39e0ea76d00a	\\xf95cf9a7df65fb0d2e20378175d5b6ff1cde4ad2448bd7ae80792a446053f9ea	0	10000000	1661597598000000	7
8	\\xeb654938c819b0bb14c2d3c802d83ec81f3643500205bfa628f7504fcd881b5b	11	\\xe677ee18b158a589f0f5ac2bc7d3c457618fbb39516da68a1fc33bb4beb4992ca79b1fe0044a4afccfc0c4b888dffc2b842ac3317624bf9a85e94ed96771f50e	\\xabea7afbc1f9d1ebff5a5ff372e3b7b6017466d2634258f09659e2ce3d6ae2c2	0	10000000	1661597598000000	3
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xf5b652a50b2cac5d9a613976509e0b6468b20a99d80ee9260701a02d64a12b6b26d8c7e4087963e11cab01772bda572a1e9fd40aa4423566ebf2e2368555ea96	\\xf65e32d3b140375585761111995f378a91956aa4e22b5f345b771bfec46984ed	\\xabcd8ecfdaca235109254e4fbb062421f3b637f4a4deb7c7d887723450415d3a8a336d7ea0a67c905dd010148fe49ce8e934ce76e14fe26f5f3ab98be2cd9808	5	0	2
2	\\x2e13e493244753b0a01ce077173be35441dbe3744f39a1bc0c10c8dece5fb6748831dbfd06ab863997e3d2ac82b9e1a569b8545e12c9f7bc0d8d663086a01f70	\\xf65e32d3b140375585761111995f378a91956aa4e22b5f345b771bfec46984ed	\\xbf56b155b7b30ad4b74afff600adbd947070285289cb7c91fd1ff62847b72c7b160d61c9f674e9fa9bc4bec027cb05d821f69336b4c2bbab373ebc931285e507	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x683ec7ab7c7ae19c6949e96224345802454914b9cc5b081aaeee176af205596d36c649304282f0271164701a515959fd9c2a936ffc70a0e966cd00bc39ba1805	41	\\x000000010000010029828889ba84a2a7cf4b2ddd7e32afb9ba7b5d8db87703eabe5b3c0b152cc17fc98b5ec25fe3d92a6f1f751a813ceedb16c6a9ff67771efb1306aeffc6eb67b9323a4a1f5b1b992f9cf43223eee889759d4a7fb96c679646439ad5649b292e46e07e5a75a99b99e15450d96152540ef4c241857057143234533b8836519ceed8	\\xe31fdf73270ada6df19cc0b3c5e30b7f09ae0d384fe256782a857cc13d0be1da26b0b23379c539ebe44d89fbb6ce74bf4a6cc9990799fce6915f39d55b34f833	\\x000000010000000154300b07b75b20763c7435c455c165285c059167e0df685be1b5395c0cb3f1643798fbeb6375d376e5cc002e24ace606a6b6002eb96f754549fb3a72261d0f53b1526c7d717ca3ba737bbc601ca9bf28a1b27ba290b8bcff022f604180ee1ee228e50870f4f742d1c697c26b00e5fc4ecacc689df140846e29c3366dbf7c0674	\\x0000000100010000
2	1	1	\\xe33056de08e16555093f325c8e2dcc1c21e3e29862b28abeffcdf47b3264bde8a7fdf56b4b126a919f748052f88466545de5758abad436dd75f491308f2aec0e	400	\\x00000001000001001b215388b547777cadf855f61d127b6a4cc3466826f92a78796cac2bf93cf0e201e1c9be165782eb5eb67114556c7843da0f45ce729f602ffabcd623780eed516fa3985a666eaaac50b3d5f2fc8e8f645823221394e1cf2951473625cf0ade70d634e231b1a3b8f5cc696765cc13ed443127f47fe4a7fd8ed5f70812b31c6207	\\x0447e15767dfd1281389b5df04e2799f573101b9406732ef64c4b6e36bce9a95515062f297feea69765c79e40eac2a721dc7940787efa4400977dc00d09ae787	\\x0000000100000001ec5b8edf8a3305b62e18d4baf6eed395aedd1047c9cd480e3ac49f2be38bbdfc3302f5ee483d51df8d5dd128d274ea10331ffeb876e3625e69ef3f22df4dee6d8dce572ac3df0faded4e96cc41751b2a57393000378236a8770e73f2597b173b0f4760422e714960c79f358313d8a506951b7b28e77826eede3b804ee9eaf3f7	\\x0000000100010000
3	1	2	\\xb230a36ad36adcfa3259d237681a978260cd0cbcf1b0df4cc215d5a949d00b445e040eb966fb6c89d7c8811981a66d012a7e6bba9336873c3c1cb3be5398310d	400	\\x000000010000010025aaba03db2904575d88eb7d937fad3a38c9ea9c84353a030f4f309c86670d413c04ea2c3bd7f75df3ab2bfdff15c985c0c0fea8bfa0ae4fc4258fcbba1e018be3c465ca50dc5ac83f680581e47cd942ddc019e6c87b78efc24bfe86291bed0e1cc3a9846dfef778e26d6a45c1cd23572e99365848f8d8172b6f861731bf4208	\\x9f583999177e2e5795d692a008c1dfb3cc557053ce6e0a912e1a9ccdd9be3d9d7131f24e7a5398c87d030fbc442696486f5b71cb93766660d29223a5997fbf44	\\x000000010000000190d8e667dc53e3768d4bd87eb1a1a2bb8a38109ed9cb1341cf8a262e3130ccd14a368f23bd1daad4db2d067bb67fe7c8a7f7e4de1f0611a2ca85db57ee6942e2d0b7f022ebe65b45103274fb2a34a253194134bdc4178e7f5c0ad0931e7b8c0d5e1b3cd715dc1fb8c4f9ddd2db335e883b0ab3f16499b50d95437470b182d160	\\x0000000100010000
4	1	3	\\x50eda78de7915d0bae94c9a1ba1c0491b4e765434b0cf9878c4b31141f81e3e018fbb3d11314961639e259bd06d8cf8cd5c1beb91267b69624eb085cb1eb050d	400	\\x000000010000010021f922741c63090d98737f6b4a2d2c78a1b293a448444ad2e356d322df2a481baf300d41b729678c32769ebe71dc235a9db8c93f0d86babbc899ad652ae27830e3025e6875514d09c28997d72b3f7a659a24557bfb2f9f29ecd3415d0feb8be518d6252ef750b1620e90c28ab906e02f1087eac6533c3dc384dc4eef1a240c8f	\\x97c09f88f14935d598c616f89adf23376fffea11773abcc758fa0537a443ce71d3352120ed39f5d6d5ba2ebef4112c25ed6fb0973159446782dbc0f47e02c91b	\\x0000000100000001b7a9ac573ff7326488f7fbc6f30b254c1723d37413e0de9d4863cfa00df5df0acbe671fd1256b5a054ac5b8a1a7fda23e87390339eea0c7baff0349d6ba0fdf023c77cdeeb1c535240019b75b71dce8301b3b23484e949603572c9b7983eca3b17f8f932a5bf7fc0e38dd6a38b5e7e42890c2b0efbc9a020b0cd1e496da68209	\\x0000000100010000
5	1	4	\\xedf0a6c5825490b456884bcdc7edf3f1c9fe0b2b0aee312ff55eecd277ab9c940f382ae00e6dfc68071d7a77267d4c96df28d55394516c0b7e45b807f470180c	400	\\x0000000100000100e13eafcd72bdf11dcc06167ac8a9f3b2a8d6773c1ead2eee0f1b36f0f5532d6e196ddc29513f210658faecdff1bccdf7d569c580723fe584eb6afa174d02fe4bfef9b3d29885f49049224fe763d6f167f0f9adb08847fb0eeacee1b243ca10732820b6bbbc87916e4614e6b6df057b18ea030bc42829983a313582ff53665c2b	\\x78bb42621f2611e1df5cebecd6439b92cd925600c8905804859cefea67b9014e564625da02edbbde25f5b9fbf1ed7fa1164be326c03c013ff96d0f26e99755f8	\\x0000000100000001df38724a896affc1a3d690b48eaf00c6a67e281ee334b050eeb859f491095ac9eeaea08ba8a0173b69a40abb4f451f4885898a82ff1486a06eec498e49dd7e669f7c1cb9ee0b55b3185d336b4e0f6e00e7e7352d166ee9efca68e211c45f74244948af71fe9980d461f05bca99e4aed90331facd7f3933f64e68f1bf4cf3f676	\\x0000000100010000
6	1	5	\\x7d206990ed9d60e4015859b06c4f2b4b9f43f7d58c10a26ee13923bc3882487d2c5f6df5ed418b839bc1d3e12502ed11da919869e88525bd453f8dd91ae6270f	400	\\x00000001000001002e98fa7fdb4d80293d7ac2a14563f9b278aa985e822dcf7d003b48fa4455b0a70b78cd8fea7d4f85206c1d05409cce14038d65483f5c2ac5c4ee6e52e7b881f07da10708ff0087012e582a9b680cbbe8f8e8a997fcd20c95d8471fbe31284693cefc15eccd1035b574cf81f1f385eabb67fbe54847bf1c732690fceb51bb3f35	\\x46634b298bf06960e666b36f24840de5799e5123303c0d211e55c4539119ebb8e7b3681a228ae106f7df883c4d7321c347c66a0fedcd1ea99a2e3cabc9a18af1	\\x0000000100000001b92a6a4d61b6b082506dae95fbe5b0ee88f2b69b66611717394ef4b64fb1ea9e32fe52311e6b7e74d8add273d80e83f30e27a77bcd94bd2a7c4ec06f276e89b33600bac56dd32c7b2a817f023596c3ea58a454e8d029dfcd92ccec13b365652f9f3aa6918a97d99765e46b7f5a55a6a886376712fce8ddb8f428bab99aa1d442	\\x0000000100010000
7	1	6	\\x41d94639697e432cdfdedfafdecd97feb26451a820fe32e9c2d705991c7ff30c6bb2cae84d42860f5b7d0fd790cce41acfec476fca3f917fb3c5a087d22c630f	400	\\x0000000100000100edc97403280506fd835ca140e90878fc4aaa5117e79c74a03cd8ed3eb94a48f1ed3b830cfe2b00fdeb909432c2ac400b143913ccb016551c6a4992b9c5e06cad63522460f1d36174ea49c27d1660f1a2b904561f1a5ecde86729738dcfa86b69d9f2fa1489c9904b1512e8cab455338265b62129253f84dd2ee2accae87cbf7c	\\xb2c18ba8264105ef7fd02288e61ff66edfded7a2224f84116c98237688ebea39586ddc0778e4de1eda955c797bfdcf2dc130bbc4daae1f6dc8194878eabe46a3	\\x0000000100000001d28af0df75b19c680833ba6b88cf0fe91da40d9b10bd134e47e9d0c839f01a99097028dc38d6c56373567d6105a0bc407a06d59127ab5e428a98c21f46226ddba258c03dacca22c20764eb876d753a00644c5ad9f6a8250f4bf08da32f5f7f6a42deaa92d8d631756ae955f2a712bc962e66b63e7302d3a48837250855587e0b	\\x0000000100010000
8	1	7	\\x338198e33e189af91148ac1e64a5dd8074dd7cf6ab8241dd1ad3728eeed0f03d4b46e23e6e01f9429e9beccac9c604acfd1710bcf83a027fe1e2bdd20bf3a90f	400	\\x0000000100000100097a309e5d3745b65733851e4e89d002dd601f0dd94ea9c6d4f8ae2c78277eb006d7c40984b08a290b5b5139abbb38952312a8e42e883f40412a280ae290fdbacb78c2f50021334b1ecbf8df7adf1401a64956f067ea9951def7ead72b92b01e8860bf245945a1d820dd4c220ce03ec5ae3ac2d83a8d0b4b2c27b28b55879b2d	\\x2dc8dda593df6df7e70ffce3c51c3159c35d969f5084d42a845b68c069b5516046a272fba7b9f3335434ef400b8237ab32e1146c227401ec1a257e97b8812a84	\\x0000000100000001e9ad20c3c88bf0f50bf5157c3b90203666c5625a52a7211219f0408129c50c9499958e5ddbd190f4ced1e48007dfc33a897774bdd170baabdbb2cc49bd9c6dfa1be29d9339cdf09090e3ff1723b017e623103fbfc70ab3c71a4c9aba6953e18d668ae375e91da34d67f179db0349edbf4013641b1413d6cae50b560a8ddc04f6	\\x0000000100010000
9	1	8	\\x8e9ed8d3acb8e34af0d9d683d403a1dc29f22c2263d9a20cf3c9da75580f37001b12d5572d3ed36ed291849053b7e12c57501c577784e5f3361c6b405410720e	400	\\x0000000100000100ce55cfcb27dedb6389305bff9dc9bf6dbb3a8ec083fa76fddfbaceb29d95f27e38aeab3dd4bbf6d77e7b3095708ee58dea29bda9276e3a5e01501f9fdc9613e3fac77b50ca5ceaa52e6fa14a49f992f9eac29d6a4b61136368dc611090daff34f2ff6b6f1d14bf3443a37cdde20617becef70604467d903b75f9450fafe51d15	\\x04e884512c35be889b6537120ad40d0e61ab0a5dbde15bc83ecd0c614dba9f0d7ad4c11c5867be53e35c15b988fc1e1d722d6577932b9709bb3456716ecf3633	\\x000000010000000183e8a2c0925e3edfb50543cbc35bb5fc6b283d460ec461f8c4b82152398e0d210aaa8fcb4f248f9e22d1d81a37924141e12fd5ac64c713cbdd458579023205f8f79da37ad6c7672dbeb5252a505aa2f942a1dae413dcaef3b1c11cf3204cb82fe9cbe39a81bd48d46d0f7c1ee9774df67d31328af0bd0878b374fc8e7fe07915	\\x0000000100010000
10	1	9	\\x651c52efa5932585b69f77b5de57cdfafd5e99c7e774490cec4cffb4c83313ba4cde394035f7c76af53f9d595d01ec54c92d5f0de98dd3152c55687c5ae42104	22	\\x00000001000001003bb37758c3ff91db636ed3f74a0040dd2fbbb0b930e5a0d3ecf6ae1f72cd79e3cbdb6ccd3c9cb25d4030b6d6e887870d72fb178b1bb274b5f4915f89e4555d22680ebef646d633a6c1c59d8fb4cd8342bfb738982201a18275c0d118304d8b3e8486f18ec7168bde531157e0bb4852cd8f9210c0bdeb9e90f976eaa2c16c2086	\\xdb80242f37770e7b85d94c0619cc3d3f3e65253f8c7ce150419dcb8228d88761e2c5de61cc92b6a0e016a7d8b0b035365aebe174705f442cc8be05b15a032a88	\\x0000000100000001a66e9edd81c3ea4ed48ca6c5dc42851203a073ac906384990f272c8374ee268c241d2a907767f5ccdacfcc85a6b1494fdc6207d8630dd4a8fdeb2aa842130a4c8c77061964963bb8112383078c39ac7e67d0f1e262096625b09d92557180e114dce7ed2f83733e82eeccfa94d5ad8c2a554600272aa9effc2b7caf14ca9534c1	\\x0000000100010000
11	1	10	\\xbaab15dda6868075c221e5f15e559e60e3b58ef9ae6ca67f8a0b5d5c10aa31bd77c2a87a5466fa3c6756062badbbf76366326313edca5d5a1487d7668343be0a	22	\\x00000001000001001e3975b570c907e044e2c0223b2674438031d9b46f6ba872b9d2ed40e9e5b050639f92ecba56dcd6966d781ef2d47334ae9a451a1a732914841d52deb614fba2aac3e69ac3d8211aaa02f7e83dfacb79c22fe7c520bc3765360f0251d4c8023d5a9651e8c86a57cef00c675f06bf4b7790f772d40311c29f9aeb764807bc0ebc	\\x0708f0f09b19c5481e66bf268f37cdac26a213a1c4d46f25b5ad60de8112ed7da5651ae7a27c8c6bebaf74cd7309f64d22dd2186a2ba267547d2c911e798ee74	\\x00000001000000019412f78c8ac81b591524616184ab82fe4db4f0bc1260ff78d7c6f3c91cd28a8ed4fd8e802c667465f1e1e0a6c9f8f29eafce575ad7371cc6e35caeb50d384aa7ed89fcefa24199432b4bea59b6591b162dc949d389a18b5a00400f5e7b414ee69c1c39d9cb5b2c6cac33a0a64b4759eb0a3a209113075af48a20071df762592c	\\x0000000100010000
12	1	11	\\xa36b9f3f04a9fde35f6e74156255aacc73f1d96739c323f345051d7c32258903846f54f26eddd88cc833b14f746b0508fbcf253663d61b5c9c784933679d9506	22	\\x00000001000001007bad6d233ba6a1761cf08b5f085ca040714a6a8fd7216305255ffd4782e5341029becc4dfb69e3774fcab6076d1531f7fd8405f4d3d832612524901c58d98dfc4d6b14d90ab800939f5c87ccc61793c0744a6ae0d5e86a9552fd81b59180a85febc17251bd19b201971dfb12b9444dcf65900a55cc3fb4407b0790127698996d	\\xb8cabfe7435620063ae51fb030c38ef4e49b6fa4453d5681f2629dee0de75eaaa391f2036d00b1278f6a881d8d1a49bc287ef9f9efaf4039ceb6dd27465e2f84	\\x00000001000000013484722efa9d0273df52d09dd3b83298186beaed244785acb86801a6b2c6864b8f713c86c1784c057271e0b8d5afb4054807bb78a0b0bedddeae96fea857182161a6ed5417ade98e35f10274f27630c1d64060698f60ec8fcff8eed4c2075cf2f01d4a92a2d74218f2cacee759c5fa63d79bdfc9ccc4b90b7949bab15245d083	\\x0000000100010000
13	2	0	\\xed0f299d46ebf70a1ccd012653abab4adb72412f12d0a59a546300efe775b67db8a4b34babebc07e6b78504d6d7326ed5e897297b73e111ab571a7e7cf160b02	22	\\x00000001000001000ac4ed145837bedafe1a2cdb67b45e661c54cec1a90543bbfbec62436fbd6963e5a0c249c64ae07f42d3331c38642599e0b1f190d6360465fd0bdeb525263b76b94ef5727a33006e24b9b63fe13660865b09d298c2bd8ed98c325516424bf87c2045eb30e99fbb9c30318bcf68674a49f0f6aff1d1e2ac62ab288b1d8a15d450	\\x9eb34577a053afbf393b8e206bd9b347bf891c0da8357da837e4b9e94e344b2efe01d4a928518773c58443df7ab67d39766c34bc65f0eeb03b33917dc6d1903b	\\x000000010000000162f7fb888b7a2c7eecb79690a0093bc55b519817b7ee934a8709432bfbdf14946e1939e3c2be1652860589b1691e00d7809b2a4aa9b6faa70e8b9f7e7ad2a806a724738acdd90405ca7e6b0dff6c3886fcf6e8b7bffc05e7cd398fd30c4bdfcd422d85038f005356b098e6a5807d42c6f9e25dd255967962069900d54f5a6ab8	\\x0000000100010000
14	2	1	\\x76539fc620fe718f049b8c9373e3affb0e4d7d5e8828f1f100414118626987a1f34529d18a458aabc015ef64e1ebd5f9b1a47d730568b1c532b7fb478712be00	22	\\x000000010000010080957c899bd98eb358f361af6e45fca522bee291516aec5d38b6abac4f3728c23f19530b6ee526ae0cbcb8353fa60a15bbdbec85ef4708aa9d63de58cc287dca13304e71057e11565a4adcf512d63cbe38cd85a2a16ef8ac4f44799b1e66867fa9e03926900ab04e8b28170f5b4f510c6d039ad6a3ac67885ed1e433fa8effd6	\\xb62aede1148694402aa4e6bca8bb8c39feffcba234f4d6b66519a5d1d892e9631f64a9557035526fb75de0a1181d7573bb20831bd84bed9997d474dead7083de	\\x00000001000000018c1270f570c8dd983b8aafc48b1dd5bfff22a06b6092db2a4342d20078efc79680edb04d9a83864d640560ee2ad453ab6faac95148f9d1cc5f316d8e472892d5ca4b3bd8b2bbb3656b20afebf6e17484946f0d9e8f5e420bfc4ac02d43a85ee378cd5854fde6cfb221eec4ab83d0f086dda9d8f0ab29b88a95a0f99dc53c1760	\\x0000000100010000
15	2	2	\\xb5dd684d643942c376737483311a3684e8a62cb7d3ff6b0795c971c2b75d9fd9f9d4f3bb2a5f04b56b903865983bab796ac77692bb774cd1c833980cd910f003	22	\\x000000010000010073429bfbaa7624a8b8cbfb8a837a22200b5b1a82d8c7d3c1a3ed362120517dc9a0237fe96e8da4320a8b434c9391afa0dcfa13ee4045234069989c4c5f4b46dee1601d29a7f1676360059a894bc18ad3dd1d9f9aa5b7daed7c2016f4f017a9f5796e64fccfd08e221b83a09a2657849895c0fab7302535263a4754b388bc1581	\\x68a25f24d344e2c49dbb26915ecd2c77ea9b7d50b7db43493c96ebc748eed03238be785692f45cd68f8d5c9860a6fcc5de1a57d62dba2a298282459d82944640	\\x0000000100000001a58b1360a35a830290c3239b07339b4c05a27def20b846cd451c17057d0b2c44d40ba48badfffc614e20657c9f31fe5ae979357708480706595e499160a5b4a06d4db53a0d1559b02bea0015bc51bc21644808d696579cab7eb3bcae7f0927c4ad21ce13bf92300086b8d63f1803a942cd5b0effbb4dcb58453066b93746286e	\\x0000000100010000
16	2	3	\\xac2afa303f1c7541d7374764decfe5ff38ec04971e636089513c3b155041ebaad21c0b9354f5cba2a2d4935533e28741d2e44e7544b4d5faff9dc08470092808	22	\\x00000001000001001665d561fd7281c773a43dada8f1e9b76692a8715a266694710538b9dcf36dd679826d4fe18d5649b98c753b22cefadabdb720724a60b4e35f79ab09ed1e2cdda935a49ece8744318b9b6232214702c58f8bf34b7d9cd686bbb7f13657c9c9b8a1192223b85b2193736faffb25922b3a03663e51bff363520f07f40f3a0e7cee	\\x862d3a970139d0fbcc5d9251ea09468224e3ccebaa2d684c4f21761eec78025e6516667bfd6762b07d674480d50486f09edf6a368e1bf7e0b4fbf20d98eb37cc	\\x0000000100000001101983229ec109ad6c21972897b4b32ed3b691dc47b475c09391e99e6b72cd8dcc74d78cf9d04687c6d1d033e68f6d10dfccf471de9557333f89593d043e4cdf51e61bb1b9215522db3516324bb4444f47f9abb61288fc567466e669dbcde684a8741c503207988ca352837930c71269ae3cf31e504c63b9742763ffb3f2844b	\\x0000000100010000
17	2	4	\\xf509ef6c05b221880cbe53d77ecf8040865acc1047e698acac2e8b0926319190b469efd213618ce953f7ed2d862ee4ca342238fd4cde12ba8ff0680a42bb6e0c	22	\\x0000000100000100465f204bdd566ef8b9549a94831c171ae08586910fe5f9cf0b3d0d05cf558999554a4f606a695afe67f0cbec0718ef3f737871c073d3f852504223040553be17b456beb3be3d58d226b1a340f29049dfd3c4ce47661306ad3ad1423de621c7b28d995698e60a085f201f47f8107b086cc062a664e974afa111bff051c045b7e0	\\xe56a06f94b0eab1bc9d4cc9208278e77438884686a64f5b7bae38bf932e27cc8c159a2514e5d1be6ec302e8c5f240f96ad99add0ccc039881bcded25055fa8ab	\\x0000000100000001036f959601b9fb00f6fa2c5898d5b8a372870ce7668ace4ba7e727ba7812b23c85bd44c0fa9ed50901b54c9677f5208f2c22f9367b09fa86c7549ba71af453078f16b18ace9e461bb667c84fec9a2f21d41319a811bb68d24205b8e5cba3e830806b80afb975013e0b1d48a92e4fc1a5715beeb666922fe7d91ae9e8f046460c	\\x0000000100010000
18	2	5	\\x3a266db33948a97c1b3cd6819c0d556467c7ab8fd1adddc91958616c950bb1c00bf91c152df46fed2fa4bd1bd5bd347ca69ff58717961fcf1c25e7d68d8b090e	22	\\x0000000100000100a71ec04c59443fcaaa575dad25f6acb7fde1f229bdcc24c09a36fcd4ea01a91d8798d5b6208be3cc314e088016a874b60d81a45724a4437d35144af97c4ff4f89b3c3e153eb382a25d9bc4b8233a9c0aeee0c1a04be7e428922ac017e1bc5444222a402155a8005dfc921cb49e79a083f54194ecb1d6b2843cb3bbd36215ee3a	\\xe25b701eac1a3f4b8936ec5a7d17ec4255cedc6c941bc5135d29a97a55c010410fdcd651a78bba352b2019a3817d57064bf64b0d18c64b0231af2a129a5006d0	\\x00000001000000014e4dc323b7d588dd042c36181e538a4070512ab4114670dcf6612be61792455bf38daa755a95c92b025804670ffa9e00a54e65cfd29c3516fbd91093183a6a8abbab2c13f042e424a50450d407654735875a5e728a72b7f60472ac2baf0103e33911042a0e23fec07d6270b3b3a824dbaef0e0d6082d92f1184bb97e60406b0c	\\x0000000100010000
19	2	6	\\xef5cb1eb152e77b8fcfcd0ae37715cf85c97ca81896bd54f4d39716af986446191b99c6ad0712a74b2adf174b3beda6603b881971cf9269cd1251d52ab224501	22	\\x00000001000001006521216a3b266a389326bd6a3e40e2006742e6bb83a81543f56e5e8e53571c2d1569740f5dd73f40ab86e70067f6f817b4610c9d3fa2951edaf72bff283c299f8aa707d25e87291bb601f430af94b8d801009a406a07426268f4bbd21d25735b6f845713ebca5427948fe5646c0dad30a407f1df191e3407a054bc214f309f20	\\xad873696a4ecc0ad9941dfa757353128937baeb928b05c71527c90e5ebc2b3ce28cf86ac4ae516bfc18a91cd1c3caa9afe8e43d7a4cb354751b21cf08495bb27	\\x000000010000000199d2696b719bd8573d4f046e66bbf396f44c0b4ef89e917d3c855e2c78a7e9b1382f41e5c8593d4d15c3d949b6159d68d7b8432bd6224df1951411293dc0a3657bfb8ca96183b8ba0e7e43232a87374d65813867b0e5c28e632fcadaa14e1e5b1bb97a8913b85ccf659637e8e11a34f743ac7793322cf61126b481ef5c11f067	\\x0000000100010000
20	2	7	\\x079857cd6242bb58bde12ab30d5fba54e75404a016da669f6cc64f5d98fb866ac0f74b1f6b5fd30be259ec282fae88622c078b6d482af1549f463b16bfafb90b	22	\\x0000000100000100683518d1b52bbe05bcfd91acd0993b9c18f3a84b432307618aae2280388f6042708e7f251f488064218a392d9dc932096fe48ea39107da2206516081a91ee89efa7fd5917c386d7627ef0e2d52d17edbf9ee3a93fe880c80a703cd822d6becadef7ce4beb9104e011d5c4426edd94b9adc59770c2a365bcdd6c7114f04ee7cd1	\\x5f47f7c5990254111dd28abe9b8cb01af485f453e7ea6a178298c5f5f3628cb561238e1c6ebe01b67eae5ab70ee6ed95d0db0f55166d95bb19bbad39c8e29ebb	\\x00000001000000011c47093f61781db6b3eb9b4ccbfd5678aeb541516604b7841dfa81089f65987f26b957e339802e50369998736757555078da4cc6f387dfafa7ce12e8072342516e92bb32e5ff0730e3f69b3a2f264a174be1ccd716b3c2fc42d9c285d2203fc151545186fa64d587e5c3c43d0fa68fa133dddda111dfd5b85e1af092c6859170	\\x0000000100010000
21	2	8	\\xe10b86df86250aaf9c4126b627a993151c54757b129210e86ac35707ee360658b6de2b82a6caa6a3f55a29b00d471aac1164ad6b0e3448a47ba5f0972088ff08	22	\\x000000010000010046f42fa77489b018d3c18d9600ff83e19c9f4f4255a6cdd00ca6d23455436f9742b8d9531b23a6c43857c2c40f84dba9cc9b6d44fcbc4b1651b85dbaa61c2d4d765ee1dc587606e44f61c4836cebdb5fb494318e256b328d627084fc86e9105b69847f2e98e763b57d6144089134e8b8da8124865f0ff41278e3a0144f69692f	\\x64504ce2821669a3a7f81c221f0c1443ddd30e53c959396ae6ec48c219e58c045743703635dc79f0af5103f5be2739108ae873804ef4c327ced80f1a61a27af8	\\x0000000100000001774d3b5201106bf866235b7ff917fa4186be1756e2993391c3a8ceb0e1f9843bc06a16709b62c3796d9e6ac6e126af8b4ccc458a9fd1a665a04ba07860c6f6e6d57da05e39df33bd715c287f54e091f56a0223c16fb00602435b0141cc71b1f3a3f0e3b067d6524901e2cc40bea0bd3758773f04b41e9d284d0eeb6a3de5e92f	\\x0000000100010000
22	2	9	\\x529b5fb8cc74f2de897333ddf6a76eb6c29d865cf8057a8322c9ce2a17af757571f8905c0b73211b5717553a43875035cc02022bc045feec3fe7ca29f1fd8b02	22	\\x000000010000010033fa6dbc742dfac33ea95c9bf6fac006cb31cc670e063b7cc24ae359cca7d9e9956dbe8dc2a9a4178db0c75345bc8bc593103bf1b54f81c2d5170ed5429e3cc033d62eca079271033389b8f14baa7b88da9cce2bfa0e25e755ec3fc3151e20952333fd75872dc4b0296fe91e936f5d68aa468efe5dd398f29eb85ab21be4698e	\\x56b889c0be047b422a22f063ce49609221e65fe14f3951862fd2446b72c23f5ff84edd1c80e8b5b8679fe29a229414dabd62250a6f12a061e51828c0b630e3e0	\\x00000001000000013065c5944b8a2661c678f390d453c119af1baaa2e30d6dbcc841417bc4eb22c4afe9c0f36bf7983eb4d42dd4cadf4763761fe35af57e96a42478fefb7603383ec4cab70bdf6cf99b3f88e0a7818323106b6108b3fee194e8b291846a0ecfcba12dddcad1d77b6e4857d89c120c12aacae71681bb896f275d785024b648c3bb92	\\x0000000100010000
23	2	10	\\x0e951778059f3f2e024a5f0c411596f69b5fd85fd5430f1139f2a98216627b1691dbff3adaccec22e2e3f670134f5e7c9c7f73fe4d1a662111e3b1f6d784520a	22	\\x00000001000001009e55a92051d83f6e34ab5ce1f75255b4d5533e8deb4769cb8e3fbf4ad2f3ef6c4c0acd93ae53aa8b58b15f83dc3b91eb4f5251e7b5e83d1cb4c508480e4e40d64a834f0261e97fd37402dc6cdac735ac7bce889e9a267481c592ba1d265eeae51feebacc57b3f2eb84c6f88942b72e35e440d1ebc2019038fed357715e82fdf2	\\x7ee0d09d7ee1e9ac2696a2e5be9d0da56fc4cfc9874765367df614636581857a128fc7e261ea7b12db24dd9b9520f674623a34bcb1f8dc0ec913492e058516a9	\\x0000000100000001a190277193b1a2eb3d281929e93225f27ee8207993033e28c234a785b261bb0b49aef9c7e1cfc0bda327f1db9171a725d56688d9ff23cffa9d8abb2fe8bd7dae6df1d5c53d624ff056e869d644ebcf2bca3e45ea4940c9fe79ea5d90ee117c665c20ea5a3d65aa1d812017a6f8fc33ed621cd6d7831e3f1e7886a06f2d641f3c	\\x0000000100010000
24	2	11	\\x50a6a0b263bc75204c6c61600749c6bff28c9673075fc41173d0529162a6c2eeb7f4f44621b80ea97f159082eff93fd1cea29b5fecf94b953f1a42eb359d3902	22	\\x000000010000010092fa24c47ded18094a34b9aac7dcc5e48739c3debf47068933bd1f5dbb3c5b03d3b16f4c78a1fed10ccf82eb15c3fec9eb5653d407f965ee2da6451a322abf446124961d573fdf171764326155c326d869372bb870ddedb51bd29de2a1ecf691a70ea2bbc27fe8b9a669b4ee9d1b8c5e9c9ba0b6269e19d7b18b8b8881fa3d31	\\x4a36f103a8cc3a1ea005f3fa8dd5527bcdc6867f6ce5e789d33474eb5c37cb727aed25eb23aab9e1a0f8706a2adf4d510a6c55a724b51fdd95ee1e3a5e284520	\\x0000000100000001309e8b22770243c9e995300cd4236fb83865def6571bf576eaa000b19c94fb85aa4ae17985f7553306bc92e7ff9c49894021ad6dcef56375ba4afbbe57ecb956526a01f63b9b84482aa5442055386a6a6f0b79bf35015989ceb7757f69da62f7150c09e498288b71295c871c6ac520c4e80bf049599ce520769ff8275c5e8b7c	\\x0000000100010000
25	2	12	\\x51db9ce152f3491582f2dcc0e3ef214b63edbe0d2a77ffcd840d674ff68ad36299eaf91ccd0203802d03eaf8f6a4df18427b25f26f6ae2d09a7d3fe2b90c8a09	22	\\x000000010000010090798ef1fe477eee6b4df32a2bccdbf7e70d5bc235e9e9f814dcd4426c679e56a13eccfaeda973fe492686262640c8458d8fd88892627b736ca8d19631dfb1995c36f1a9d1841d5492ecc8bda17441ffbf22565b6779ca92e067975f3142d2b559d9e4eb0f7aa95e6f7ccf94f2fe40cc7f0cdb322d4d9acf8e1e73ce5b122b33	\\x4e7b4ee26ecf7aaae90cf5745978016350ac60d056e649277a5d0494f96595156bfed9d874b33e81fb06bafcc017312818d175967012e72b9c68ac77b95fd080	\\x00000001000000015f6a1fc11884914f9e17230e5cf522a429a3c474130d9e335c89833e4b0d48a2846cf13e941bb5f68c517b6c42403a89a938f6d71360a977843c881c9fbc0eb9b3cb69715d9532e45cd3f710f824382a9b594d895f7c234c35bb8f250c2c9667ea13d38434ab7c1b03d337762a59a609909e379cdae2c77a4096f66c9550bfe2	\\x0000000100010000
26	2	13	\\x4832f8b48c29c684a96c5eed541a7acfbd5b0273c5acd58d4117a5e36f5f71bac4edd78c2ea66ac7b69cf85e937ea27f7048d62bc6ce7d68dbb33458a77a6c08	22	\\x00000001000001006df2a82978878bde26d7241ede13b3970df7bfa8443227e0ea74f1a8ec0490d4b3a9713d139a115a2ad1e26a87bbb1778e24cdcda35592a3e98e36030eee04a2d3cbc3029285ee417d40a32efee56b4f12271732ad279c3ce1c4fbe08ab83ac438fc12bfab92a68dc77a9542d77bcb7e2f961de70a44c6e4368de89e7952a3d1	\\x22828cae07379b9e455a00663ef2cf405f89fbb52e2459e46b3505b0b69fbc6d2c062f17301d712e3e2257eff9608748d4991952049ee04ff699d7a36af02aab	\\x00000001000000010be738a1b27f447026bfd03fda33dc4d3aae02d3812999e4ef2348b22ecb1ae0e0624229c92f856adec6a8b64449b61169527b9069e551883becdec2332d6df452b1a00238b06cd27086230a5dfb0640c9ec5b8ea7165e97ec59db035049b180e964b89611654b7018e0ca35342401944e89c8e006c6d1c25c677bcf8ae09e3c	\\x0000000100010000
27	2	14	\\xdcd7fd3f8ab1eb1d73ab821cec86f584f85110fb3b5ca5f8effe799e118502028b44fd1eb5bf8d515107760f18fa41b3287839e58c5c4b29d40ccd3a7c44230e	22	\\x00000001000001009256faa470009d9c4969b5df209a3829600020ccd27c978943189828fd5d24a1523b2433570263e3542e24219e0df662c83fed8f2b384845b555e23b6692249c18e745ba577518996a2cadd64e248245f88dd90d185ae6e457dac1ef393e398a36e4487623c2f7d238ca1bbf337ac05a8b16de054ce39e026f1fddfe814aedec	\\x0b0b1b0209b50967243d865e51e167ec22d68c1d70c8fad72e65d660c7c80a7e96fe8a83ed3b0aa061b6a63a203a32640bc1953e036cbc8a6d06ed7cc46447a1	\\x00000001000000011fb30e250552d2e6594430d085ba12c410b8a323946069395b502e6498db9a121c1b3950ddaf9717cd45be821b33a718d358147e4c0ec63e00765c50c75638adde329079be524a813296bd79d6f335fcd89d76f95b3db9ba2c49afe789bfd365c17d93e830a5788774eb77b6a3933cc593ce9ed2a9a63e649cf8751a4f12e64f	\\x0000000100010000
28	2	15	\\x4118934f0d104b49e23e8229e4ffd4a26b3abee4359cc57817b01d9770ebb167d3b908f6c881b7bd6f29da2574a8801060de285a1de6c40c659239143e3e9b07	22	\\x000000010000010021b499a154786ee68d04ac7d94190b7e1654c966b0c372ded0fe3fc385c6de0e435725d7ba97301881e81fcce7f2375a86b2a2256f547133be6bca63a4a88e50e547c592babb762ef20979e8e35e80be59f499e2b476dd098934c421a931bfc9e1fc8ea0a99c749a79cc653c2531140e2b5c1c11dabad045684bb17e3adaeb49	\\x8614251cadcc076ac4d8bdec52fc5bce52df9264f864e910ee65a2ef6f9dc86fe65e173d15425321e6a77b9faf855b0b232772035a00ab0345257ab6ecffb316	\\x00000001000000015444f8f7b8de3af43a6e388fea08cfa7d2642f58a09e800d0292ee40a05992e676287b7c3262a92bf0f8ec9d89195fb8a13c1247920400d68436fada7bd13147beb28a281f47a73017a4c6116a65dbf77c9947800d7dd63c53018fcba07b78279678690aa62bd917a66653a01814665cca541a5c659c39eeb7d388ae8d63fccd	\\x0000000100010000
29	2	16	\\x02f764c6b2235bec0ad691a1ee552b018f1a23efe93fcec4f80c55d15185a13f09352493a295780ff90a4367733c6ecf9e467e99bea3c207ebcf1d520fa6fb00	22	\\x00000001000001008ee33c13a8a10d79cadc04dc194edaf166524fb0674cd5a159f90d5962266d42b33540a571fada54c5615b618493aca6e82e8ea852aac09ece3f3fb01395484b70aeb9320dbc5898ddc415ebaa4e5bdf9b6fe95b9e5d274b89c4f1c068d8c8f910fd8315d31514d0d50d56f7fe9ac2951224703f322313fef3feba30a35ca21e	\\x63e4ecd62a4cd23eac236d9cbc8c815ed9ec359ee74fadcddabcc8754001a9910694f9f7bc4e48ef76699695686406ef5c3a8ff71e38b2cab512663df6eb462e	\\x00000001000000012d75e980854dcd8ba2feb0bc830f1de9a3f958111d6e946af45ea3b7ee0d95471f120278cf477b2f6da933ec89012455f1790bdbfd1f02c60393d84e234050985ec60c36eaa9f61db5bc603212eb02ac58ca83f020814ebf5a3b7bfd80086333d1fa2979971d1be04659270ecbcdf7e5e33d09d5e59f23b4cfc74affa3fb3c32	\\x0000000100010000
30	2	17	\\x740258c4f0b0e65ad1ebeaebfc9878a27a3e20fec6eb8ffe0bd55712aa9ea4c9e686bfe0aa257c8143a2f0b32bc7cc99a5d281b0e59088181af8ed7ea40ef70d	22	\\x00000001000001008c99f4449ba9dafd84e1823dc46be83d9281444f8b8b39dac9e7f7a5ac727b89fa5822af596b2efae25063cc1bba3a0947ecdac117ebf137349efc7a61de1dfdeacc064ec3b51a43aac1130c08fc71f5b1def285ce98528b6f46c3aff0ad1343857b4d290a359d818f41694b08613dc4ab8a95573bc0c29c992f53f35d6d6696	\\x04b6efa41bfde3e669747993e15a54c04de5f34ccfe8a554ea12c2bdf6a70e588603cfbb36c9a17ea9619fe51755e309e82673ed8b8bdbd0a22c3ed365545045	\\x0000000100000001aac386758ca085eda4392fbf771079c952b0b43c19cec81b64ce3ee30d8254f2824b21aa1ffcde76b9ab08ac3ee73d8b95aa51c0a05721e048f7d25affb3a78ff5bfcadb10f74a67b8e1fffd6da00c7a76f49aed6e79a50f5b3267e5c67124a973abd44902db33041a4e6ed96237889160dbbf152cba04421e20b90ac3c9acf9	\\x0000000100010000
31	2	18	\\x8133adb49688d83c484be4aeb1c7728e2eef35a58b8732940b0f7c78117e1926a48e9944858735d5e045ca739a4796d4ca74e899a8f5589b576b52eb5dbe290d	22	\\x00000001000001006753a04be638573c6ab8450e0e941669f55eea4507cc6db5049e57bff40284216c8b90a037dab4755793187fee11f83381e3e5617a6e57e740c6fba2da96abbf2397b95dff2eb809545c17414c13cb1286bf65f9592214b2182d532144635bca7acbedd73a30e09bffc6482f8ae6667c4dd0d3d4b99fa0932c747c5cd69b3dd4	\\x12ac8206cf0daab7291602cfeb9cb9a19a8e4f3a3b4e1ab98786c2f917946ccf76ba187b70c86de028d144b9b8ae635b04a4ec82ab14b76661555f8888395154	\\x0000000100000001411366f5b3947b1852cc7cface125887db2735b9fea5b97d417d94a650c3d77ea62db878084bda8b7e474c2d16da7a5e0c30ee09c4205a2c11b1b8d43c12a620dc5c582ef75402136ffd806254885cbd4caff34372b5d0d85ba7089ea13558a4cd269f8a757da2d7e8cff056ca4e574dbfebbe1f3d82b2485d96a4cc54873447	\\x0000000100010000
32	2	19	\\x3508b1a7e0cd300d48916613d313516bd10d854718649453dfa670057f5c30e9d475cb5d67f6d8f8c07f1cfc9e7f9e1cd2dcaee2f2ecc156da090632662a280d	22	\\x0000000100000100484a69036407b3786c07483c3e5bc6cec77e19127b9496d015ffc2d55829e67263de0f9266eab63d49d3e77886bebdca2ccd06b8ad03863d7ee6429b5045f3b004a70036cf34e5444dcbce956352f61c825ef7c6db13cd9af3f76d4f2da21884cd3e4814771d3d1f976b727953b4b4367f4c0c81c4fe7d10d4f7e153fe20b34e	\\x36b30adfae6634c41290e10da1876bfb1f8bba8786579de9e780b7be90691c410270e987abd119e13a7de2b6bc2a8727963b198260ee83476c971277ef6692c9	\\x000000010000000129a9baec465143bd3a25c8c086f7e7ddc43f7f0b1f131aac099d973d094bbc93da8665534a43d0c328d088c47d9321f072541e31feb3b7bde7d689bb3e915075883112886d710e0a8790d4e9e8e5c9751efbe2b97d11ba2395a6c5f0e66d76c96a3c2601088727a2ee9cfa96d702d8e14426a8cfbd0e24fc943292cd2896fd61	\\x0000000100010000
33	2	20	\\x12e3680886dba5b1ea69f6954fcb8787c843c132e4d55410f698a47c2555ef00fd910d75ee10b166331300a606219360a2b774af1f7a229f5c02625034565f00	22	\\x0000000100000100a7280617462a5937134ef8a4aaaa5c7fa39347f5f0f7bc9cf149bab3a21cc25f887a5f46e35f84641bfccae92b10f799d1a9617a75a1ffe64e2a9f41d4c68e27eafebdd68bcb16226b7927fe2b50f1ff6504f4e9bb0b9838a59971d0b34a947fd24812cb92e25b7e8b1da4db153a6b04190fd793c149f27ca6ce3012f8dc6196	\\x92af0ca2ab23220334075d1a34dd54dec9597a4725fe5d11df95ff79dbb4633fcaee09c0d2a1dc817714c20fd9950d1b39a571e628377e183b69f8aa408fb484	\\x00000001000000017c1a4bd7e59015fc4503079ac52e5698d5caa2b240b839b564cdae79ea1d79e0dda5c1a2c6222eaa806538a6af8ff501631be1101af29c957c36dfe97112072cedeaf47a0ac889596a6d82b9e99ef5cb347034f41eb2146f3b5ed988bfed333335778331e1d734c5032d5a25d69856e1f791369edecec1cf9656a09a97f3c87c	\\x0000000100010000
34	2	21	\\xa6a43dc58df84d8958770d5a032cc3ed5c7ada0c4a65618c9fb7daabbb538b19572c09ef421b8203b654dcfed0cd47aa6176df73469758f0133051bb7955ad01	22	\\x00000001000001005536a980feb7af41d3914b95315844d50d31793d987adf0173b6a87c34cbe25d292533cd1c739ac50dcf0aae25c12711ee73ed32bd4c488f2fe86c1455eb457606ea714c2726fc52439af15368e6631432f7e6aa6b84d8b70924c23b0ca2c30932898d12de271c3b01bca799352477cc3a629cffe2b862ce6c8481d7f2c334f2	\\x4d0dd783d1c6bb0e6c98850819a74a25237a2e898d2c63f8bc91578d428f2a441ba43d83886cd6df0ae6ec016385d241a7f1f8a17136ec8cbc21c65dc44a6840	\\x0000000100000001ab5a768bb559006c7797786eaee8bf2604a94b85fed3874da8f16de2f9c5f1bf030deed73e32f1c26b92e227a16a142e91c3ef185bf0dfca24a9d4e31eed8cb6bce15724b97e73024543d8ff79cd7b3eb434e910862d1b486657d87a4927ba3670bcadcba711630ec4e09cc19e3b25f2cd75e1dea0b574d13cd35715f89418c4	\\x0000000100010000
35	2	22	\\x5eaa3410132ea811a1d57d96b8a4810938658e7191c123c5fbcbea34b6ee8db364ce976b0e8663be65400e092e2c8eca4eba68070f07d2194bb3b0087ea5440d	22	\\x0000000100000100aacf8433e1c0197b04fa116084f71fed5955621ec842732b3674b64cff18ccc9ec7dd2af3b973a94f9014ce72f681ca6f00b71f6b84a89353be7092895b18827447d03d41783f3b730cedb7d918ae2cae570ed3704e7bc7478a2b6bff8c5530ea55bd085ccd82d0913212b87be78b83b22c33e43db7fbd089bf3962bd66676af	\\xcd917a0a5b89df663b78503346acb814696c4d90ac4ececfb29956ff477f32f0cacb41e1a074a86030d77f80ea09558870a1d4355c85884d8d62b353c0e836cf	\\x0000000100000001b1cce4d148dd30056756a31a7f605397c593acab12d5a4afbee1d41eb2caf7131f34cc40783330b0efc7075d3a20c1082e573b9bb6c2785abb2d05b878b2564a13895f66ca0d8315841a9e177e1313cfdd959aed2f99ab3af0d06180fa9c4ab78a2e9bc6c9250a38ff6a0b1311f31f37597d6f47b7216059f29a94eae4d8a4f3	\\x0000000100010000
36	2	23	\\x378e267e3eb074c7f4a6c9ad10381cc57d3a427c4e7e65b10ea794e02278c4c0f5672c7720f2fd19743787d0442b4e1deea18378f9443f7a367b5ec95038c60a	22	\\x000000010000010031388c8f8aef76dcbbac5092bbc04de476019b9d5644f3d76d93ee3f78cf918b56d573b85801fb5b4adec92b4425ade0f4e228b6b7a3521f555956a6c59d113a5b6254afc55d95a5da482d2d56479ffcceb19f04ae9171791afde39da15557131c7889d35b455f8dded446c5e4771c743f352ad69b822a534c6ec6b1c500d5d9	\\xfb4628ce02b54c8ed2e9027e0cc3df49570b771c84f6a243b55e6cf5d639a9eea8d6a2740bc658804d53bd7fb5c0011d67df5e5f6fc1e33ce38e8af22eced8cb	\\x0000000100000001338d7cd86168e57040d66eb42dfb406be4de1b3a70c9295dc7e50754a5fbc1e93c392ad2f43d20f62007ecce81b2787bd3c4f36e72af5928d2840f3a05adfc2cd3738785ba712653913098ddbc260566cc86543ed472f77a9aa5c84b2c4acca3147f874ca529bdf1383f21f6c7eae064bb278c47a8ffffd04a995b8b5a97752e	\\x0000000100010000
37	2	24	\\xb2eb635939a20b2c0347e2d30e383f294f907c90d44782f67b9de2b794102bb10b312b90cb445939f3669e503833acf5317ec7b5b78e048b2a749a523707f50b	22	\\x00000001000001003246cf120c5be0246aa12f6fc083801e8512d7c8ec54ed09d306be290d607bf02a134ce4561c1f946bcab3706adcf96d546af5f115b5a0e090da7eca70c5518eb5619884b4dd3fb2d8961c74569686dc2c532c71e9ebfdb12795650fdd99ceff4dc20fed4093d54f844bf1998a6ffeca9155abc5e25f19c3104de57313df1d9f	\\xd6f50744974a6ec8dd1042d516d6bac40c002baa3bd45c35685c1f85d75ebe2dedd10d427e50b2632ae8edf41cae481b4bb53413b772273a13bc5bac049035f5	\\x000000010000000179a2a2810889ce68af46e64eba4b02cd7250215377027e777e1cca1982b12838fd7d667e52fe1432c7be94e3e9f09b0ada5e1c74e666abcf13a8aeb5904b522084410c33f32ff2000ba3ac55a3d33fb5c90b663198d9fa0abc1f0774f40e857cf57e31f17814c87c00af6ab6782096f5c79e99633f9c39edc4ca82eafaa55666	\\x0000000100010000
38	2	25	\\xe05d2694c42598cd4120d6ef593e20cf6017ca817e5bbbe25b9fbe3a67c981e03e103300bf4bd4fa56492eacd2d8891b54f72bbf87c12d3cc4884596b3f66c0d	22	\\x000000010000010097d3979d334ca76c4201d600bfdb534c53592ed15db84c6f6173f79c2f70914360f1b274f7e7afc6c935f609f8774969e646f39cf038d337a15df4aec7b0de2b0a2b748d94d26aa9b1ff580ea94cca1084c63ae258227116ffe2dc4924ad1650a1215757ee1f961473e19a1757b1dce1266a99bd8e372a3a1330b3d77d110c2c	\\x17954e675d148b5352d667d4915a04ca444bb49fd8ee89e2f76694c5110ccb51f6f720d5c1ccb7739787f889fd236c53b44f0b090e4ca28241a23dc1b3d2c332	\\x00000001000000016eac890e545256a55009519223046aba6b728e340b95a033d74350b1994a613ed5c3e6577904f3dd193cde9e463e61d9a2670b4d36c1c3fcdb99df13e4ab5655562ce2dd806eded7ce0696778cd847a9f65d2142a2b65952b532fb255182e2c3eff63c2ff6ae3414cf2d78e109ae23149caac8ccd2a5fee1cb5788e64775528e	\\x0000000100010000
39	2	26	\\x47890f89585d5f8b673736791aff6a477b591876b9f7e5286e223360bbf77e258e7bd99ac99f150b9453e47cad4233d797e52f1cc2e51068c0f3d308b1a3720a	22	\\x000000010000010028a18225c6ff2867665a01495a035b2f49f83846893ca36f62e38a02aa8a2971f72c4d1cc5348868282685da3b3e28e9c4113a871c497dfb599b3b5527795c29054fda5feb28309234d7d9830225d7bd266dfeaa8afb9a6c3563cd8c524aeae497ac20369fe2c94440a803da06789e0d8c18e4104905a0e6f0d16414e34d93ef	\\x2d91bbb7b0c948a624d62beb5240ecae0d934e46e5037ac97ea639b98a35598e7e483da3af431a08e7a9293097d6f7afcd1bb77ebe2c44ea38b0fcaf33eb92ae	\\x0000000100000001432a309ae6d06a64a08ca082cece569648de6d35a113a76506e2b5fa763ba4bb116c8e5a7f525c0d4f59b609dd4692a567af4c27f2d9f740adc6643c7c4f0833c869684e8c8933f1bb4dd5a2167b27e065da64fae8ba9ae36a2c2f6e7bac0a822d0ba90829d04cfd12330f2f856409e63c346a77cfaf56e93b7338466bd2ee23	\\x0000000100010000
40	2	27	\\xc088685e84f755a59232c0783917ba90a77e3047baad88d141a8231cdc80a24305a0075cc1744c7e985d9ae9fb425c8bca089c49147d15778f120a6c368c5b08	22	\\x00000001000001004dd3c43c86f6cf9fd39fbe0ecfee1574f9314cff107cb3e2e824abbf4ab77279565ba23e52aae4a9dfa6632bee56f3db3ae2ebc3953281cc6acdb538a28412f0396c641dde9fb37657142245ea2c253295fb4dc000b9347cb76873a36d80f1a9e4882f72f59ab26498d8dafbbe69d802e261283e0721d348207dd17741416f92	\\x7f25768259be99163c11936e5ff7a60b12a2ba386eb1f10809e6f9021bc2979c01f3b1fd4f62777ec62c194b1ecaa08b139459d7c8f0d399eb800d5422c1a919	\\x000000010000000124c4638586a35f358fb2426bb76bb8c0c4c3530002f49396e4e365f9f0a31ceeb99c16824c1d7de8ee44bd7451df65f0bc5b3b58d6268837c36646a628be8ad5131f03d49a3e3b9ce3a05d651c0cc66a8e2301f04ca6e6c5304ffb3f1ac23e6c8c8aca049456fef677229c8162e3ea3d8302d72da256307d9e72d1f4e9ccb5a5	\\x0000000100010000
41	2	28	\\x110ae190b7be292c54594d6ceef64d143126a9aa119289679c2919256802f9cce3af895367b232c68a38a6f573a7daa418dbcfb1ccc9fe4659423351420eb202	22	\\x000000010000010032ef5644cc974dbc10058ba4d7e7a48c5603032967b81965c607113765c364f4aa419517fa3af1d49ea82d8b97c8bff8a6892656aa2d2dd481336ffa3b172526947d45d6227b6a23a326db632a8e46b8ee8f0ac57e5e27f09e37a0633a3349cb31563c2252da0877f08be07ba910ea638c673d6615331bd10d5524e538cb49f2	\\x34cda5dabce0e0a18fed7a5bef7f3845589574186aed7095fb565ec675d8a7d960613717d3f51e1c021e4c8b5ed26194f5a096f83c241437a3d06a8923604ecd	\\x0000000100000001b19db7effd10e8f4b17723b521ed32a51fc235bf4d1df4b9dd27cfc59dc1b47a4f56167e8f7f3a2b8bc2402e45f44fcc4502c83144a018d1b3bdf00c5ed4f79f9dce66d106063eb7e1f2266bb130f9d9fa0cf77f037661d64514a681c0dc45d57ac8ce2619bb2738f5836057d9ec9dccac391a1e6bf6ec8dd589a6339f26ba46	\\x0000000100010000
42	2	29	\\x07041fe661a6c9c88a08137e2525f71c23c4dae7d8c8c41f3225458093e8753b3f9e716e88fddbe3f863caa098dbc128761b849c2403069bbdd94cfadd03e600	22	\\x0000000100000100660b45c903cbfffcc37dd0846f2288427f6c2ce6a04703f503a791ba037a45cea3f44e0992574bf8aee0d0613fc8be21b9f2efc6a96486e7c7136c11c3d9df62813f7b2db386c1b89dbf5c4174b980d9e4259301b9598fd55bd75d072e0e13e8033d1ac64c9df01fd148b2071dae3217ef1c94fe040ee769df8a5798df441aaa	\\x5b64c960208b4613b4b905de098113e4a9fd83f7ba138222983c0c284317e5ac4044529f2777e4080e1982eb4bc4f285f8a91b595c98629f34a9e13c2265d41d	\\x000000010000000186a4c0a7286ce8bc9a8c91e65a800f035268240a5a2c38fb2de1ef080e90badcc33df55fb0a999b27be66e9f2daf546815f2dc488053a83b9b720b8713f36effd2b07b3b28dfbed3537fe92f056de3c1a3708bba9930471048f4fb3c3f098e4823eacbdf5cc3cc4263512767fc3aa85dc9d60e2fcb278c745e015cd28b097bc4	\\x0000000100010000
43	2	30	\\x40de0a0757d2bc2ea040f9e39d1640948fe4f7cc0944bfbf311047b289559ec043810a4e00b518b759d932411376a111df809a35015b38d9fe02bfc90d116e08	22	\\x000000010000010086ebfcb45127357fb983db3a7bff562b83c99db9ebade362523c95355c120fe2cc425d1acbe6380bd733157a1424413a6ce24b0fe324fa61462f35acfea3c76091f5645367e68125239a496bb1ee86eb26e77496ad86aed2952e3e1ba39a78e9d0773b46c9acb5ac1f1fa087edb557e69d7acebcd6ad0d960ab4aaab7b220c14	\\xba8fd12a267c4bd63a4e146e691f5be5e724e32fe88bb8f1b4f45fee6e34f7f94865a084bdda77dfad77482edb49cfd7391e73fa9732a7fe262aae6af47e2817	\\x0000000100000001501aa5eb46851539a977382913bcdb2e249f7447bf135992a3b34f435f3dc6ef8c7253c95a1e9b2b96d66c8427f96d2c6a5a39f721df9b6968334aed5ce2921092accfc84aa5bbe7efcf9e44d6603a9217712723194f2ece62a2424d7c1829c25b50e952c2b8080316e1d612920496aa3f78d7e22bd0e66c1dd99592650a5982	\\x0000000100010000
44	2	31	\\x32e4d9ac7039ef6aa3969f18f76fabef8ac35b2b86794cfd9953e6bc5ae4bda4fef04464abf7e3edcb99154e44b398f639b6ea55454f4ed48f9dd2f749104c09	22	\\x00000001000001007e7e75b03adff091f52064351dc2f6a5904247ba62382a0eb1aac992310b22bfd345ecaed06e792eec2a7833ea2f2a4f51612d83f575e49aefa08a7bc216537dec275b57501dde28aea84b8aefc7fe366bdd3c47e704a3fa9aa1a0ec953e5f192b6ff8497e6470d97cd89b78643b01f49a2329ea5278e7f96035a2d44e206981	\\x324e9c54ffe3e9283b62128ce6f73068ae7ab7698905af414f165b0ccfa4d9245e08a44a11a455db1390352da949f455089ffc63188f7124d9f4b7a26b331a61	\\x000000010000000158c4a3e8a2c87bacbfb8271f357af1b216cda9b05cdff2b654486831c0048c8fe30ddcfafecba414c0c6f1471936ad236429d912c180cc2d3ad1eb60c62abe6f1cab601ba20d43ad217c88bb1570fb2614fe6884400cb9f17f3c94c081f77596a447025dbfc3e4c2a681ccd24482a18b4b547d6ae09a2f9041870fabb3bf8e7f	\\x0000000100010000
45	2	32	\\xeee14df9a797307ecb7bfa79f39aff59381b89907d13e24132b7e472e2a50a8648d1d8941fc317a1acb25424cc3a29fae4d32bd6fd56d357b59e7969ae4e5107	22	\\x0000000100000100ac458dcbab01e4e6522b14b448ab08ca5ef0b11f16aa0226adcf145307b389b6ca06ff8f3ef22c2de6880fa21dcfbbe0ff0289b3147e659b7b5fcec932c976d5754c506def788dba1621fbac8e831c209487cfebacf538d98821e75bc8b2da72b48bb2e70d3166194dad1756a3bd2725e6ef99c91aecaf05b2a5e009294ec7b7	\\x8446124ec10295de33bd97222b99f3c6047c9ed33a864b70885e588d44ea7abfc5c56ce35c7f7746c69ca0c32ccd48f92983353acbed5fae5042f1c42edd3b01	\\x00000001000000017636addea569b263ac51efdcffd0d15ff082c7e058a73e817d1291f405574d0787ce2a8d44e669c2bf2062bdf2257d749dbe019eda13e1764c8b3298fdf7a6cd8e9a3ea6e20f9ad227f3a4cc1112a80093787e3ea37f5f45298fcec1cb5b6a3465d0f7f4e7e5a7fb985fa7dcf91cb330f0c644ebe8cfcb5f08493e4b0a8b1898	\\x0000000100010000
46	2	33	\\x38814b4516962b37abc6b89040650330834fcad0e925036a18e09e360139b4d0d98fcaecce328e58c6fd6e0ddeaa06747bae8f6634d302057a14c59de71c9c0e	22	\\x00000001000001005be904dcec431b73b63885ea68ed4a6d0087aecc96687e9712e40033be0565289dab0f804747468148422307a662c1380b308a66e56ef3fc2de8186781a2646c05e5d9dd3b52e8b2fc249bdb89af2ca7816c9662ab896661691fb4cb3d2002a960dd11c1cb5e457308a29566ec0963ed1120bda17a3bf11b60ea1c2e8d04030a	\\x96826ec215adb456ba2968b12bbe9baf4f9cd129c9c9bdc0d2819da6dd834e4eb9d294d90ab13cb97b7b083d02433b893e47e61683a12be6f5a9992ca8267c26	\\x0000000100000001a93652df8a5a473a18ef746984f3f1f14246e31714a74f3c85a9a5d81954b7d93bfbcf58cc34a2dd485c94efe385a0f67f2c06e22977521ac92fec5c3054c5acc071a15d8cec1ca871ff159ce7b41761b6b43116a6066a31f38c35ee9e407e39dc01904d9af4630cec6d5a93cd8a79b60053925636b6af44dcfdf60f6b133b43	\\x0000000100010000
47	2	34	\\xad98d4b32ae491728bac280beff3ee25d11b6d0214a2ddd1f555193cc700bf9c4dcfa4bad7317a312dc726277edd33aeeebd1cc24cde8afb31963e5d2d64980a	22	\\x0000000100000100607f0621b2d42a320f4817cee42b4d80834f687612a6cf8a1d1e8481b856172261048b38513798da597e4d139dfa433dcf10603da1e696912c0a44fbc85e8b6a313c0b03aed6866ce89dc9d51fce4c62e5e6055d3e4da377a381581c46145e8cd74bbffcef118015bdba90d34297d7ae3b236013ff807e2fd27c236366435b85	\\x32c0f6c7cbe6ef4c0630f80dccedb10e5adc4b667a99f77082447b6636c4afad88d211e177f9ddd41e919bc2e68262ac990709ac34a47459330b179e477047ab	\\x00000001000000010632c429648ec05526d49ac146290cf281e9180453127a3482a7749d86d838bceab1d17299e850e8a470c12b8200199d812f695c4953bf501893799a73bc691ca6a6e5d2ee51ec2cf6363d141f2fe1efa60516481a115317ff7718800980a48cf4a53dc9edab4f1efc9070e99f92de479d903dbe1045313b6ac256b9ff44bb14	\\x0000000100010000
48	2	35	\\x7b90a6a2cb0bc06d446d9fed2b0497ce749428d1050e3a0c193b58f33b26b463a7f76e23fc1299dfdcb5198deb32e692b1bbd57413a91438f4bdbf83c5ce1009	22	\\x00000001000001000fb0e6e4d97d9520daf1ea32c8e0956e6e0790442024c8882671c7daf6a0a7d9371346ce839e28e270b00860d725ef13fc613703ad31bb5debba2b3c929f9dfc0d28f10a5954428c07d11315d13a385f4300890db5365f49fc4cfa1e8d682e9e3bbf4d77534966a1b82e82438b5b99b7ee161b4f87541af215f8fa0594c17684	\\x4db7a1d82b199af5c5e72d429bec189659555078431d621db598e9a3f7c38bb06fa10f22559ac9206be90a5659ed1e98611c40e3f889e3bb92439200219e8908	\\x0000000100000001165e8db0a4b06c8c89c926f57d4acfa20c890942befc76681f45acf3c733aa9c49c4fea784666edbcc6c424a4c94b6555dcdca24c6d58ad14c4d41391f1aede2b6a5d2615bd0e13298834e4ee0c6b054aacc71aa0961ac8847660c248f83356b6046fd3fed3437f6454c08508b625ff8948492a2031459a75e9c2560e8898990	\\x0000000100010000
49	2	36	\\x0b9aa86d72565217f1710b082a35c2acaae5faf45e4c7eb1e9e03c7ddc4e1bc2ad27602e9d31ff4922b291ea243abb3025cefea384e96fed66deac165baf6104	22	\\x000000010000010048367adcdb2e1af70b0efc1bf2605a289b28872483473cc1b3a44d2a12b9d1dc449fbc51f7f730c8eea65ac2bf2854a11407bd530aeec65bc504023c1bb08a778e64dfcdb1d2782cc802c9401dfa5dffc8d6dad14418d19526a95fa6fd6ebd97deb19f768f86bdd47cd851fcb1db78d590e18c67d6e5bee336cdc12c779c236d	\\xb42fa4b6a8dbc54f2cb2a2c2555547fa711830d75f578fa245f1c59bc62be3e626a21c822da61b3e838e7b7c5f7f8bb14128a81a0700ccf6b6f5b7467a21a7f1	\\x0000000100000001a9309aea6aab01848551f48db040ae574561d5db1a1d0e41753ab6a881eab925fc3192faacf90a01143bc14a89cbe81943e8ff4c46bf146c440f28a41e8d830cf6c1db46da3ddb9683bb0a49aab187958f3f001defba6491826ee1eacc41a86b1dc3a9224c184471970cf2403414809242d239bc6e27097af55a4653e84dd4f7	\\x0000000100010000
50	2	37	\\x0e817affba2c2103dd1d31a2506cd40ff809e24383ac3637a245f95404930a33c9b6977b025073c7c54cd91e225ef80cf43c4842de426bb29b81800f44905c0e	22	\\x00000001000001001a237e8e29ecabe3b3c46616e01a4aa1975de48e2758b027047aaa8199491be0b054502a3fafca899a3cfb45234414ccf6ad93f01bb12d255729447ec70535b0ee84d671a05cbe173f346a978f0bdf0c2203ea1a28e5eeba5611be87bdb6c5ebd00728160d15700338092ddd0c0e89c919fe67a9cc4ac0baa1bae47ad5b24cd5	\\x2739102da43c48cef26f805715733238d34299acfcbb68e0667b5090bea756434ae4f0ff876b37ace21525cd4d00d28cdd530a14ec5dcd2efb94f1c5a2ad7d44	\\x0000000100000001a399b5af19a56c12d99b4341921f4db88ae6595c0e5fb4ba5eb75b17229604cd5a957e389b56516c7ee6e7fbc13f70e447510dd27b57fb8525c21828e4e47d7cb92fa05963a940962b2b17d66c5a2f5ef8aa3d0d155c64f2e3b30fc0a5009c2cae4abcb28cf7021637ca70ad65c3340759827d057fcb20d63806580a69c6a896	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x97f928b7f632a6af5459af6e567054b8c91cafc0509fe07e6d46e98fc3e64044	\\x79ea1503f763e637b24768273d3322b0fe2cec90b152f4d2610cb625cfd915d7db73775a3576c0f9b53deb4856d51150008ed2536a73063a3d505e5606db4709
2	2	\\x8c8f8b1b41af85660c6f4ea19bb2a004bb312b142e6593dd7b03f924028e726d	\\xb4f1dc22c43c64e7689d2729e7d51aa5aeea9b52c467cbe7eec20b397ed025d00a96569ee0d5c844a2a0a7226923455f252021833d30ddd4a2f7d35ba9a13432
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

COPY exchange.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, max_age, expiration_date, gc_date) FROM stdin;
1	\\x66f1f1c6b9ff59de864545ba9aab938d712c94502568fe4a3c4e8a83539f6ddb	0	0	0	0	120	1663411974000000	1881744775000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x66f1f1c6b9ff59de864545ba9aab938d712c94502568fe4a3c4e8a83539f6ddb	1	8	0	\\xf08c08b36ef5c254226f9aeacf25401116f21f23e88262454502f04ad89482e8	exchange-account-1	1660992761000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xb34500fc8edf5df29882b7674f56e953072188c67c19d4a654adf1786ded06cc1ceb15f6b9e0db2dee8a28ee39e1c883c23d590b23a71239f14643671258910d
1	\\x5c9471a343a04727ecd564e84635deec54b14f037d7724ecf936f31dd00029d7f696bb2a6d0e4f7c502765e5137237f70d6538e3fddb2b32ef3fbaead8552bfb
1	\\x130b9e9b2b5602a8d987d9206fe464fb583f0eeb4b3974aa3c534609183933207690d9aa76080d6ee12292c5675f11781f653d468facf95370d56b948cfd5e1f
1	\\xe3a03f877b5fd7fbf9b2e300a9e2f0de642970a4237ae9bbf0237b7829cafc519f2d19acda053cba25f9cef51e578023e899ad67b128ea2219cfe5cf0d7d83b7
1	\\xe1f5e6fb2575ac883d5d483920f4cbba3b3b378d5fb56a01b7e65f4a5b3bab8e3bf17b9666108fda9c030ee7477c6d6f802778471801ff454032894e5a24f939
1	\\x78815827ff949813ebfed5ceb39606e4f773fae131a5c355e0332210bf50efcc18dc159cc8e1755d052749f0dbae9c6f3e792785199ebd2d2b30877b6d409b32
1	\\x6b43aeea7d9465b1a9f27c11a670f044588195564d82559264645f6fe13687f980efe81487db1122915d47be709c256dd1f78638a3c6950d973f186331263b26
1	\\xe13b1d58d95e8cfc44f8f0d1df447ee5bbc970fa2f4abf0a04d11b36b83f0fdce40b04b538a605af83e1ebb481592ecc93c2d4bfb946e6a044486e252eb0632d
1	\\x3ad86c0413001f3337231cf828a0e6fde282b5373193d8d3122e3099f17081e9a74a0c9e675980eb5709dc171fc3ae1d14dd73873952270e198b7a993edcecbd
1	\\x9dc12e140c571806082e3d79b7cb73b6c31e68172c42cbb64c5f76261d4ba9524c80928facde547b9c0b7bbaa8dbbfb081720cab8219cf1c6449a67dab253d0f
1	\\x884c0c54780239bc70686fb440be1fcf380c72b7bbc26eec4d562002ddc56c96aed2be03902da1e4d64cafab77961931d697fe8dc01ed1ea7603216b34a2a117
1	\\xc66679a8d32200ad2085cb0aa3b832fac747ce8c136979504a5553ce632c24023ce70c6cf5b9ddeaaa57f909aa7c9c527d8b91c4764cc4ed404f97ab5fa095cf
1	\\x99275ac6940a82cd457026ce63e67a190fe856b9b42171693ece218f0fccca2655deff6df0eb2b6344046718002a69c9895dd09dee906c86f728367bbc4ec754
1	\\x2176af07aaa1eb67d20fcb79c88e72ad05b94e351ef0501b5bbd596ae5a24c0c0ce7f156029bbb3545c6ff472ca17e21ec9ef3b978e1dafdc3b3c13834635d3d
1	\\x079c14306ec8aab3d40d40d87a4173c0d7a40b45158a3f06ff76e36edd5545baf80af4b0418017d334987970645a1150b46b15dcb0419ba5b6844fe8a6487729
1	\\x0aa581aac107c3de3488f0362bf88b30eeccb7bc99c2830f2fc23efe9c492286ecd0b6664cbaabb1f5058ea31d6f457280022653adc6889745e1f9c4cc95f9f1
1	\\x81c9c6288c615053632caf5ffe476bc73ef376f784b77909b9fc5a0ab6420cabc7c70be2e4b8024d69d357c573f7145cf5f96b11041efb0d4e7a0bfca25e0c02
1	\\x80d50662854428d699f7b55beb620f25ae942fee21d4593a03d0bfaa04dc5ba2b3dc848bc32aa6b92ba39aba0a0708693e4743d4dc2e2638ba0f6fb04b480a71
1	\\x2bb17748fca830bce040fa74069ffec505d91149251313a9cf2934fea7efe18a7cb9b4420df47cdef9017550527ccf1d4f2c061567bb04fff541ce8bc6515615
1	\\xd7c2bb9e68207cc7349605b8dcac35aed0a576e13535c8184b0167f5e1f071dbfd629fc1774ac129272c0708d598142406e3604d17e5f7a511219256339692ef
1	\\xc961d4de57a0fe26dc05d5f25e6cdfc507eb6729ece66e01928cf3d620ebc4e530513c1c4d5bb3aa43c096fdd40a85a18c22dd9581994a6e3115d8d6e031be97
1	\\xcddc8849d6cabea1dbc5db4c9e1f645e0eaffad78d16c04a3fec109b037c88a87d57e5fe5c07bfb42a897f3ba1c6db13a2309a32229e8115ac3aa3203c4e9764
1	\\xefc4c4cc90b6ee7157c423062773cc53b3caafc54798b0ca798d4c42fb26e358f8883f97df585501541c3fbc25b28500f454135ceb08d1786cf08613db80382a
1	\\xb4a87ac930f558e92030de49a59dbb5e5861d9d019e247f76d21cb87f672d9901ee9ac7a1dafa98642201c08c42f5b0ac8a428f84a07ea83b4769ffe6cca1e94
1	\\x6a893b69cbe20b9575b5167be675fdc93911f09ee29f4eaa136a21e5780677dd904815808421cb513e386d516122b7eadfd19636f4a6dd3c4a6cf76d4e93a705
1	\\x8b3ee39d5a0a90b77a891d1b51a72a19eec45354f0817dca03b5a6ea35c5a2899e303a63684c7a304325f94fa9cebbced8ec141277a3bc073b7908b21c2d668c
1	\\xc9ffa0a5b77ba1d934ec035872b1c958ba183619d12297f75968f03e73259da8c2ef9347793373dbc635a8c27f85e96c491ba5a46e4bc837eaa0dbb0e6dade9e
1	\\x0c0c505fb77b3637f3fe5bb1d9b620875afbb81c116021584ffb97376866b93393810554e3594635fb5b0d3b1e4136864e441c98c7848cccd300321d8ec9aaca
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xb34500fc8edf5df29882b7674f56e953072188c67c19d4a654adf1786ded06cc1ceb15f6b9e0db2dee8a28ee39e1c883c23d590b23a71239f14643671258910d	109	\\x00000001000000016e09ae563fa335af70cd6aaeec38b3611565bb482b0d1e9804805f6c7e6c27422f94e07ac63ce4dec9ae69b52d2f9b69c14c1bd986655679a9f888566109a6ee9771984d4f7cffa841671c5852ae1fb7f11f192fc20158d9430ea0472de82c9c598903d0634fe428cc2abc55cc6070b76d81603c9f17692c6054a157756daa4c	1	\\x8bc2167dc6d1758ce6825b32c4039a13c959a22b7d7d09e27b1563c97af0ffb5e3849c37200b91985cc6539138e2fde4cbc52387ed9e66d426878c821dde080c	1660992764000000	5	1000000
2	\\x5c9471a343a04727ecd564e84635deec54b14f037d7724ecf936f31dd00029d7f696bb2a6d0e4f7c502765e5137237f70d6538e3fddb2b32ef3fbaead8552bfb	339	\\x00000001000000010d946009bc3bd36dbc71b43f040ad94ec04240207d4257deb33957c5f276afcc6b36b1b86f7cf81e3ff0b5c448d8e09523082c29bb44bc65d93f667d2f6c4692c5fda4a047e12886c0ed3306f1b2ca4d4002a527bf60885df97d931a2707f20abce737ee43bbcd1a7c75050f160e5ca16eef999980eb1ec2daf0ca60d0e114a8	1	\\x9bfb9a16478641bbd8a9ef5292546aa5dd12ae90823d114d7f7134f5fd058d205567dc1a2dfefb1365dd02f2c096a155715f24a2e6091c924eb675562d1eba04	1660992764000000	2	3000000
3	\\x130b9e9b2b5602a8d987d9206fe464fb583f0eeb4b3974aa3c534609183933207690d9aa76080d6ee12292c5675f11781f653d468facf95370d56b948cfd5e1f	422	\\x0000000100000001bbb6d283f485cef1aaa125a06a9f5d5d5d38d8eba3183735e7900c379532bcfc8033a5257a51c58078a5cc33f34aa448aa5a3e8c59ce2552d90b5e5190b3c66a98da0cb452c6b1fc84e51c2c5104b2e485352341d2ddcabb95d3727a2e44f879d23b173474e548e335d1a6308fb76247a1409d8fcb3eba9f8a5d0b1a66697d53	1	\\x7ab141385f77bd4113f705472c0d542a32056d6ed3446d0f03bd455428e5dff3b1aa9b72bea8f5377b33ac424a29f27d8daead80c55bb394c285ea886b7f7f0f	1660992764000000	0	11000000
4	\\xe3a03f877b5fd7fbf9b2e300a9e2f0de642970a4237ae9bbf0237b7829cafc519f2d19acda053cba25f9cef51e578023e899ad67b128ea2219cfe5cf0d7d83b7	422	\\x000000010000000117dd87644a077a55743b7aeaea2d9c53c6724c5db73379e8f0ee32179c487e6402dbc7a70b91e3bbc4592b4a6ca1ffab2b287237bfac2318d95e44ad3bfbd58dd68acd1c665b9f8e74b0ad72b2dab0cc85fa85d691e46fc88a92a9bd7c4e51cb5a94b99f0b07d85903aadabe9080f9a8ac67f00c83b3dff63c5c109c3c6ca0a8	1	\\xa4b43333b2956055f564b22edc4fa36f924c7703aab15938a1f4ba6cbd451aa75e288ca25de49fb74074cd54f9875fa91f6753def17e56d5cb58794f98b67907	1660992764000000	0	11000000
5	\\xe1f5e6fb2575ac883d5d483920f4cbba3b3b378d5fb56a01b7e65f4a5b3bab8e3bf17b9666108fda9c030ee7477c6d6f802778471801ff454032894e5a24f939	422	\\x000000010000000134e398ab1a888dac53587d23c4aaf1a43f7fdf1197ab4ff590956e111485c491d1b482aef5b6e3ca675e595c842983c98b7b8a94d5fa10f5ed728d7f7d61c4211a984ef5b9164d405c1f575d2276e21b50f35b250c3fa5fa5a1d0fea7cd02ccf4d80d1906686e0e93ab4a279f9b83b125a26cf4085f9e119dc5c0a105afa9322	1	\\xb1bf866637a6cf25653f250c57728af8f54d5728f8f0c6949fe779f7411e4b3a5571ba20b6fcc048e37767ff098cf7a341dc16c6a8402b77927257a42655b609	1660992764000000	0	11000000
6	\\x78815827ff949813ebfed5ceb39606e4f773fae131a5c355e0332210bf50efcc18dc159cc8e1755d052749f0dbae9c6f3e792785199ebd2d2b30877b6d409b32	422	\\x000000010000000172b3f66b86d5654716c343b21ad128df521398438d08c19897da5de076e312600bb62ffde089ee77ec94a7e8f236f0f6e75aca92aeab0291e4cff5d168df454ea572810f18f3db1e34ea4d9067447fd36754d04be5a3469c9106119a5adc0e31e74381af01c9b641345bff944016dee40c3cbc353412db8fa734716fce102b24	1	\\xb5ca44486c0727ca291417a78ebd62e58696187af30d20432c5a03b05046c0d037f52294ff12f73934db2d8df80f5a6f5e8a12f665aa1cb3617f54ec9066e50a	1660992764000000	0	11000000
7	\\x6b43aeea7d9465b1a9f27c11a670f044588195564d82559264645f6fe13687f980efe81487db1122915d47be709c256dd1f78638a3c6950d973f186331263b26	422	\\x0000000100000001cc806c6cf57a22563077d2ff69e64d90c9257fb9b865a883ee51eb93d975875a86abf9d65f753605ad781c9e0f3fe36ea32754a31a63999549ec1febf9085c96147dada575a79f2a6c56867b1fbb2030adbabf56552c2cd072571e8588c373f3ca985c725dd29c6f54d9cfd52b25fc374275d6b7f2dadc99f053a59354724a4e	1	\\x276f870cb2bb58ffb66dd1cc7456917a42fcc2e808f05f9fb565bfc33eaecc7038ef4e98a0392fa6a0cda0df82c7546c1de077118a642f0496119ba815cc9d0d	1660992764000000	0	11000000
8	\\xe13b1d58d95e8cfc44f8f0d1df447ee5bbc970fa2f4abf0a04d11b36b83f0fdce40b04b538a605af83e1ebb481592ecc93c2d4bfb946e6a044486e252eb0632d	422	\\x00000001000000017bdda5f03c0925ef4fc5fcb609280c90269a533963bc31853528623be03a6a61d23c15ab6a41b2879d0c0c35dddda35e2c366b6119d12dc7b64d64237f57dca9ba04e03ce45b7ba1645d10e3cd9b945dc830d4eaf533a7b7edd57570f83e4a2b7f0caabecbc62cc9e888b0562e39fc1237aee8359a431db4d6ef1b9ac2ce7a77	1	\\x56f0240f52cdb6c99bbf6e73312d1db1c7ebf1918d5876889f68761c9d965a7a12347e7ddc25ad613774b9115e15748a1eb127e0581978ef0f30b93c240a4d0a	1660992764000000	0	11000000
9	\\x3ad86c0413001f3337231cf828a0e6fde282b5373193d8d3122e3099f17081e9a74a0c9e675980eb5709dc171fc3ae1d14dd73873952270e198b7a993edcecbd	422	\\x00000001000000014dc83f93e7ee1ff61ac4c251481dcde373da58995d5a0458aedc3edd66fc9817826f6a792af86344de3657b261fa78536789e902ca399625f5942708ad79b00fbb303d9445d11e1b1b83c09cf2910b599855a4afc46ffd07b01106bb3023eec1b5f64fa51249100da5136e0501d94f959c720066b6795200fcddba9c1138dc85	1	\\xd412b65a15bc534799c06e7397ac53527f2a748fa39a30b6e43288a59b4283562d1ec3b0cf46978d418ac44ca781d12fdfcb7359d90bed2f4f8aa017a8cbb006	1660992764000000	0	11000000
10	\\x9dc12e140c571806082e3d79b7cb73b6c31e68172c42cbb64c5f76261d4ba9524c80928facde547b9c0b7bbaa8dbbfb081720cab8219cf1c6449a67dab253d0f	422	\\x00000001000000011f4612661fa2d0b36e08390104d7bac7932d47074ee6fb0488419133ef22e86410f915fc0d00a965e3e62768b8ac9e0e0a0f464fd2cf352b782af7d2bf54f6e420d271f9eef6026596b355f1a1c58f603db3d59b44fb5e302057c76561ef40097b55f19083cd56d7497576fd5bc8dea06f12a07d5070561d7374262a241df18b	1	\\x85f63e07b25c32cc5ce1d535de4ad849d6df522e972e329b08846e78e7d4899ee6287b693bb3b07f6bea7f1b77de6934477df48c9ebc6434e8cefc918e552f03	1660992764000000	0	11000000
11	\\x884c0c54780239bc70686fb440be1fcf380c72b7bbc26eec4d562002ddc56c96aed2be03902da1e4d64cafab77961931d697fe8dc01ed1ea7603216b34a2a117	20	\\x00000001000000013ba190d3673b77cc7ecc601f90eb14f5da505dc39fc33a15b1455a3b5729bdcbf57d231ff5b931a7b86d8ff29d0cc299d8f85b8687f203de384aa719564c19b2a8867be6f18e0b012a24673790e30bee164b557943db219e2c15cacbb41ce6a28b38a5d25f2ee61b26954d458c4946d914cf08537db31f4be60e2c2093bf0fb0	1	\\xec34fa312c0bb0d494d56f535143c4103f6b63c593d0aa280a42add341b4e458429d27c83ca73af21155fd778650d3dd5121efde8ea5ffa2513ba4a474263e00	1660992764000000	0	2000000
12	\\xc66679a8d32200ad2085cb0aa3b832fac747ce8c136979504a5553ce632c24023ce70c6cf5b9ddeaaa57f909aa7c9c527d8b91c4764cc4ed404f97ab5fa095cf	20	\\x0000000100000001b7ef45023951b013ae274a5ba5918412b4aff570cd776a9bc2ae113359bb807480917b101c0332220c73a8693e94d11834d7341f8d733a14d1a368119b4d3b21fc5a7c3483cb634faf54a9304bc771eae3462bf26d5557f66c54eef9bad5e32fec78eb834fb9ee8bfb5831cd2a2d81579add4f8b3ef024dcd97a5af9385b4a81	1	\\x3b208922603ba7dab0bbcd8b2e737fb7d67a77ce9b23e347c63cb7bb2f12f969a6aa003f261df120ced9b6269e85670739b5751bb44b8366a0d481ec45c05c07	1660992764000000	0	2000000
13	\\x99275ac6940a82cd457026ce63e67a190fe856b9b42171693ece218f0fccca2655deff6df0eb2b6344046718002a69c9895dd09dee906c86f728367bbc4ec754	20	\\x0000000100000001089e3284f372f8f22781a610fe05ea84d712ae3ff370372fb9b122d36c3a23ee37569243e2a0e8d848d86fdb6d18b7eb0537bd59ab5f742f300071975aeebf4d1200b0d65818edd5faa8e8f70c97a76004fa4558eabb46ae20837e3edc532d59176615b6162b8d295e0bf3f1c9246f2b5c23901d5d82534de1ef94bf28e13d2f	1	\\x873699af0ef5f07a4d8854c24fd85eef4ee3154b3a29d3a61a10ca8cabd574cec68f79210b59145a84caa1123318a668ebf0ea2f9faa472f7f5262e9700cb307	1660992764000000	0	2000000
14	\\x2176af07aaa1eb67d20fcb79c88e72ad05b94e351ef0501b5bbd596ae5a24c0c0ce7f156029bbb3545c6ff472ca17e21ec9ef3b978e1dafdc3b3c13834635d3d	20	\\x00000001000000017b9188323efa5f1e2a80cf08119d8b246b0218fff85f8f7ba251001d1ff65d3072178a509ef164987e8ead2a4d53ecdbf101513b1021607f769efad42cbda4ee6ad356e7fda47a67ba9f315fc3f391c66636a9648b8eff82b38774c2b7a5fffda52e11567be30f9e57437d2ee4237794f1eab20766a0ee03cc7b758f444f85d7	1	\\xcc891c17d79cbc6081b649fc8b372f90cfa6adb56594dde1f5ceb923aaa86f30d9ba33ae5e3ab54a9e1a2db9094be800b89aad644a901917ff332c079c0a6006	1660992764000000	0	2000000
15	\\x079c14306ec8aab3d40d40d87a4173c0d7a40b45158a3f06ff76e36edd5545baf80af4b0418017d334987970645a1150b46b15dcb0419ba5b6844fe8a6487729	330	\\x00000001000000017ab2ef8e51740ab73e9bcbd44783a91ce1c177685ad5caa68e0f6cfdd33ada04d5f4d348cf9a4393bb78370ef50442327c176abaf2a7a608201f1a8b33c3173ba12fdc469c38b8ca2435ecb8534aebbecefe51ce00d59c65048ea43187bf90a727b66c7b156ceeb2df49af2747d0f3471f24f0af729d0447fe7a42604995df53	1	\\x21973646d83c88f2907db545010f3d927f72845e31135153f56909306d165597ea49d73e93163b1ddefa3790c99f72fcc4fb55e5260c897c28fb26559a8cfd0b	1660992775000000	1	2000000
16	\\x0aa581aac107c3de3488f0362bf88b30eeccb7bc99c2830f2fc23efe9c492286ecd0b6664cbaabb1f5058ea31d6f457280022653adc6889745e1f9c4cc95f9f1	422	\\x00000001000000012318b3f3e78afe71445ee057bf0c515a527315dc8596d4b38fed6108b99f4d6232cb441caddc6e2cba31a062a60720e2e729a43dffa6a26136a1e5137233a6ed2492d72568f63517dea1e68f1dcc14a2f8d843e183cafdc3de933ebf1814c801923be43883625cdf7c0339a89f82a20452574b3445a5a8bd907f2aaa03f3f6b2	1	\\x153379febf2a128f9f4d5a2b600a7b4b75cd69e13cf5d969da90b8cc0aab04952127009c05a7cdf54e5e9f116aa705956c9f1ada31a2d4f04c9f11b704c96008	1660992775000000	0	11000000
17	\\x81c9c6288c615053632caf5ffe476bc73ef376f784b77909b9fc5a0ab6420cabc7c70be2e4b8024d69d357c573f7145cf5f96b11041efb0d4e7a0bfca25e0c02	422	\\x00000001000000015e2f275b64fc65b8e7e40f50685ef30d218d38480c9c4388e37af7163d0c19c929577107cb81db6fe734c75f74b7ed22a4f08f3c50f3d1d0583bd4b71f454749e9cd3ffa24a0418021a4915cc4557e953072e27838f99f75073a3e405dd61fbe97593276a5e2609aa2e9b7c93c81a0a86b47e97dfaab6149d6c881dd14ba69c2	1	\\xeecf172d6bb1ddb88adcdf71836acc832bc862d7101756214437c9ef527b9408761fbc5262eed45a222ca07b1c8c8f4836c7582690e006729fbdeefce222a60b	1660992775000000	0	11000000
18	\\x80d50662854428d699f7b55beb620f25ae942fee21d4593a03d0bfaa04dc5ba2b3dc848bc32aa6b92ba39aba0a0708693e4743d4dc2e2638ba0f6fb04b480a71	422	\\x00000001000000014809ce83227007add6fa641f338e91ace78bdb2ee673bca107a122d13d25b2b209749f86880b485c724d220fe5e5782c9a7db80c393c6af32fb48aae3ea07e6ff34ad079b5b780982d20cf365fb4961fdf8203a09587df9e23e2979b0dd4ec8b90c0401f4b9d0caf0d0fa4fbac630e3771e98e1245266f92f1cafe06dcc62936	1	\\x8f25bb84061264e6b1af365f051ff92722f0e695c2b64d5b47e56f4497a5864fa1b32766443c17afe329c4582ffe2f325bc954e43703bac0ba8d588e6f1ca30c	1660992775000000	0	11000000
19	\\x2bb17748fca830bce040fa74069ffec505d91149251313a9cf2934fea7efe18a7cb9b4420df47cdef9017550527ccf1d4f2c061567bb04fff541ce8bc6515615	422	\\x00000001000000017f7657055662eb6bba99fcad4c7783752a9150cf53e89a991ad2f10a1e1922891c560ee5d2ef6a1cb15f940e592a9949402e953ad36a870f23baff7dbc724f837a8ede8af26ee9eff68469a43c6c10663d490c612dcf650ee6a99c066cc1219b74ea3d357cac24301facbacd8527b6036d086b785745dea4798884af596910aa	1	\\x2270bce069784c4c646344dc344bd2069ba3cbed29f4df8192a93416bb15e7dfd38694caddf0f31ca79a2cb6b53d493c6b1443cec6e56dbdfa1ca1b9ce7de707	1660992775000000	0	11000000
20	\\xd7c2bb9e68207cc7349605b8dcac35aed0a576e13535c8184b0167f5e1f071dbfd629fc1774ac129272c0708d598142406e3604d17e5f7a511219256339692ef	422	\\x0000000100000001359147bed81af6d5c8f4400d0ac433e12e83beba04e0f66c61488d85e3d2fb96440126c3c9ffb7c59edd91650756b886776b7cd81f91374b98f61f355c9ab1a7385fadf91b0084cd53c204dade6f25d22133e662d42bc214b1aeab46ed0150d931574d85c0b1cc0208b137a1a30e9c200a834db4a2f91529d396bb9e337a7b0c	1	\\x474e5acc39c6c217c3c54a3f61db2947aef63d57342dad3967078255366b850f5fa240e0fe484c2d3bcb89c970636a7923312c38595f96d69558f79a6b672b03	1660992775000000	0	11000000
21	\\xc961d4de57a0fe26dc05d5f25e6cdfc507eb6729ece66e01928cf3d620ebc4e530513c1c4d5bb3aa43c096fdd40a85a18c22dd9581994a6e3115d8d6e031be97	422	\\x00000001000000012037f123a65e6d39b5cb21a2aa36498d40360528333ef3bc931b740283ab34bc10e84bf90daa66ecfb3b3e7a08b6192f80b409cfc2f4bfa93054f394c88ba6e2b18b4793b2902f3aec96d81aeedbb8d232dbc7421fc4cf8155b8fb555ef01ec0fbba087254b042938d86944b91db90ab0ffe0271dd5b17d87642aa9669a9da60	1	\\xbd45522fb3989a6e7bdd49e9a216403a6152c1c38b7527ba824f7eadcd6b312837dc144b727ce8a256dc8e6e0f863c55c86027a02c65faef1272d9b0eea8b400	1660992775000000	0	11000000
22	\\xcddc8849d6cabea1dbc5db4c9e1f645e0eaffad78d16c04a3fec109b037c88a87d57e5fe5c07bfb42a897f3ba1c6db13a2309a32229e8115ac3aa3203c4e9764	422	\\x00000001000000013bfe25c8483f13a115f905eae4da860e878423dbd8b6dac91c32e40439a4f690d8ed566f9e6d0ade3b97b88e7dfe6d73442a29fe106495058eb6227b2d28e71c5cbe398216a75cdec29218519bbe4555066c6e26fae0d0fa81d8300bea6ecae45b0791c29af3dde76d3e1a3524a8c259833ca3be5e6831895ad7c642e453f276	1	\\x13e3f41076e6b3ee740d6339d7b7242a29e64d72e6a527be0f8191e4510dc7d46971ed943c51693f8c22e335a4556a2922202bc2b037d3b958c144e49dbb0c08	1660992775000000	0	11000000
23	\\xefc4c4cc90b6ee7157c423062773cc53b3caafc54798b0ca798d4c42fb26e358f8883f97df585501541c3fbc25b28500f454135ceb08d1786cf08613db80382a	422	\\x00000001000000010b9534e7407bf09b9e605c54a98dc5d143ada0092daead51e01a66daa41414fff67b877aa7494ed73b4ff2f5dcc9c46363ad9f1c61e62e140882598d4ee83e6fae88668eabfc0e12cf518559c7cf0ddb499ef890b3caa16b54463f0d09629a8cf58ab859a164330bab2145355901e925f60f5cc90bca423ba21e0ff485fd9b18	1	\\xcc89f3e0b0455553d53d3b35e4eee0f0d05b94cd6ba3ba2f0bd06248b3f8485b3b8db408132cd61ab36167014046cf2bc2165be37ffbd528799aea31fcbfb603	1660992775000000	0	11000000
24	\\xb4a87ac930f558e92030de49a59dbb5e5861d9d019e247f76d21cb87f672d9901ee9ac7a1dafa98642201c08c42f5b0ac8a428f84a07ea83b4769ffe6cca1e94	20	\\x000000010000000195faccc253707749c416efebcda2bf5fbf48961f2dcffcde98912c6024391be11c603b45ed027f1cff17bcaae06281aa03a2bc95da89170dc1a78a1ba1407459d6792153ac1d8571a91e8bb698a55a0a352f660d8b1056bfdef400ee3de491d4b8431b35736dd6330a3be0aeff5b32cf44146b82bb9e73dfdf8a3c2fc2f62e8e	1	\\x0ad003f4451914e0ae3f4b2ce0fb9f864aa6a1cb6dadd36c62a9e3fcc8490f0e62f2b2de132678198243367fa82fec8416b29d70c1cadb77cf2f6dfbac272d0e	1660992775000000	0	2000000
25	\\x6a893b69cbe20b9575b5167be675fdc93911f09ee29f4eaa136a21e5780677dd904815808421cb513e386d516122b7eadfd19636f4a6dd3c4a6cf76d4e93a705	20	\\x00000001000000012b245b5a3ec0e0a458918219a6a3257d14cea81e8678bbd8cf057295a79830a875f5e7b62b21cc82316a3aad77c57c6f35441748514b59f64740995a4b79eba85ea66ca201b8eeb0df9faad26cf12c71450dcd0412d4a70c0079fe46b3cf3ed2babc64e736386fd37a308e575a3d0bdd15167073bf82388935bc76f79fb8ed17	1	\\x3fcaea812d59b0a14e93539a57c1b100e5e4746f1fe9db8e8423ac2b6ec116f80e8f69fed83f511701cbd5509ffc222d37ecbfcabe8672014f91cc68b2210206	1660992775000000	0	2000000
26	\\x8b3ee39d5a0a90b77a891d1b51a72a19eec45354f0817dca03b5a6ea35c5a2899e303a63684c7a304325f94fa9cebbced8ec141277a3bc073b7908b21c2d668c	20	\\x0000000100000001b85cb38dee07f88ee23b76f26aebaaa79f70529d9d5db03390595b65676cc2596c20f5b902d2765b74430735112965960f5f1c5c7fad1ac5ccf950411e81b703ba05940d2ffe28972fe7874c47756c5a1eb4ea750df4dddc15e92077643048c806745c3de0bd76500e9da38dcd22c649d78a4a2a45101dcd83a60d60e2371f43	1	\\x4ea8c01fcd2812bef95a32a0ef6f519ac36ce15a7f7104fd3747d57ae478599fc48017c7ea66d8e3ad41bc78afede710d653b57b755dbcdf91fd29ac603d6203	1660992775000000	0	2000000
27	\\xc9ffa0a5b77ba1d934ec035872b1c958ba183619d12297f75968f03e73259da8c2ef9347793373dbc635a8c27f85e96c491ba5a46e4bc837eaa0dbb0e6dade9e	20	\\x00000001000000016be9b381048823ad28fcc548cb1eaf8c351be75b85006f7a6d6ea44f25249346d42b331b167f905f05ec059b990a727404c7793f807fc8b56c6a61a911c840a85dbf814aacbc68d898e5783f17276103e0338a738e173ee6482cc9851cac9f6c9a1f3bc6cdb1f2c8c26f9b1e67aeb319770727c27bb7a31f9908f35e5cc2943d	1	\\x4fc983bb1b760906cb2f70f8d5e346c7950b8932429f59ebc2d5a8abbda7f524f89418438d63a7117aa68819256c6448ef942d815e8337c6b1b3e17a89a1b002	1660992775000000	0	2000000
28	\\x0c0c505fb77b3637f3fe5bb1d9b620875afbb81c116021584ffb97376866b93393810554e3594635fb5b0d3b1e4136864e441c98c7848cccd300321d8ec9aaca	20	\\x0000000100000001593517398ff143c9c8b501f29a8c29f554288547d367f1f02a011785c4a9a2699618301636c5e8a4398c2b935f4615289560d1960e3c7bdfc35e3205bfbf7584e92a699386ecbf99a497d1aad8b7b2a8aee602d231a45b13b734842092f7db9704600dd6b03dc2b4e9c68297b5b0d5c8c6c0657817e40527ebeb0a09f7f2de83	1	\\x2dcee2941a5452f078350935430c4b7b2255323e3998216fe627155994b5cdfabb200649ae30f8a878cae038817fb327af3362246f2c2a8b4199192e3cfc4300	1660992775000000	0	2000000
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
payto://iban/SANDBOXX/DE221125?receiver-name=Exchange+Company	\\x6d469c6e2d9e07832e17130fe2fb194f15bc9bedd9d1fdbd3ca031d0e8771ee9cca9d80d2bd30e38e2ebdc30d0577b2cc797b3a57a09f00bf108c063fdf0d807	t	1660992754000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x63cc1df9f3c887be5ba29b1db763a39a88398ae1c5d0d05e7122914dc564cca64e686ebee056f782aa578aec0f0c4e4ba9885b5ad5b359b35fd447616f799102
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
1	\\xf08c08b36ef5c254226f9aeacf25401116f21f23e88262454502f04ad89482e8	payto://iban/SANDBOXX/DE020224?receiver-name=Name+unknown
6	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43
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
1	1	\\xa244abb59475dd50543a653bc2c2c6609ab29b03b1bad126007bb99202d5809b37a15c3ad70b7fafbaef55f1efda5375b10fd9b6f890cc2cacaa5e24c3e55fd7	\\x45e24ca67c18b2ac81022211e47968e7	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.232-02V0YS2YVC3K4	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303939333637367d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303939333637367d2c2270726f6475637473223a5b5d2c22685f77697265223a224d3932415144434d4551454e304e3154434d58573547503643324442353652335036584432394730464557533430504e4732444b4638415737424247505a58465142514e4257464656393951424338465636564648343643354a50414d51483452464a4e5a4e52222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3233322d30325630595332595643334b34222c2274696d657374616d70223a7b22745f73223a313636303939323737367d2c227061795f646561646c696e65223a7b22745f73223a313636303939363337367d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2237574744414d475a58374a44565753513458593233574a5a3053514a384131365959465a5a44314b38454b48334730384d324d47227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22533132593430324d3535434443525032414351305757314139414648514d305431523844563041593543374738344e464a315130222c226e6f6e6365223a2230574132524753433852544641314d314e57385a334146385a475a5141594352415248473447354841373350464656315a373930227d	\\x70450b46e592fa22e4f2edcb92617c60e600e1454e9bc52da02397bc862901f139a4ab579932a8810809b880982464c45cb8f4a4c075bb462131c5efdfd965fe	1660992776000000	1660996376000000	1660993676000000	t	f	taler://fulfillment-success/thank+you		\\xdbec92573b535260cae170d0fe436dcc
2	1	2022.232-02V88ZBTBF13W	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303939333730387d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303939333730387d2c2270726f6475637473223a5b5d2c22685f77697265223a224d3932415144434d4551454e304e3154434d58573547503643324442353652335036584432394730464557533430504e4732444b4638415737424247505a58465142514e4257464656393951424338465636564648343643354a50414d51483452464a4e5a4e52222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3233322d30325638385a42544246313357222c2274696d657374616d70223a7b22745f73223a313636303939323830387d2c227061795f646561646c696e65223a7b22745f73223a313636303939363430387d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2237574744414d475a58374a44565753513458593233574a5a3053514a384131365959465a5a44314b38454b48334730384d324d47227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22533132593430324d3535434443525032414351305757314139414648514d305431523844563041593543374738344e464a315130222c226e6f6e6365223a22445a543056414650473142575156385a4247395256475052504d3644443938384444325136323445564e5a335938505956414747227d	\\x7d0db3dc8c43719af46e3d51fbb65e0ef73d4e4128f0156738aeafc3d59de0bfdb64e63a40804e00592824e4c9c0ed72da900017a28a4f7e30658731044df108	1660992808000000	1660996408000000	1660993708000000	t	f	taler://fulfillment-success/thank+you		\\x522469ca670f921bfcaa56f848af7c1b
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
1	1	1660992778000000	\\x633286aec399616c6bda89d40013c5d27e83e34b10dc958e2c6adade957a00bb	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	5	\\x625da3699e7aaf380cf081925b5ddd64134f875e5e7f1f72fd558d37c1490b552f6792cab9494b41c7cceb6747321182d5c9729f1e481286e06ecb60ded99e03	1
2	2	1661597612000000	\\x018cb8d9be05315e7892bbfbf44b376bd4190f9b36956a96302f5d9943eee6e3	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\x83b78bc87cc0a38a4c1ef5b1f5bb69a1ecc9f40e278cf76cfc3d43946528aef9a819b0da55b245f949401af250e5496596b3485c03fa1eb4f52100352477c303	1
3	2	1661597612000000	\\x028b2f54b389d85b20e243a97645d85b4122896f343bc22f96e506ce8a053a61	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\x11b8376a6f8ed143df4bf5aa4cb92b8431b2c57528a3fcd5be3f2a868cd11570c25a7c0965887422bb6fdafcffa7544776c43d45bc772f5985e60ab9fc4ad301	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	\\xa05981fa95898fb68e4f8af2082cffbaebf1f6a4837d28a5b7b87fccdeb4e81b	1682764648000000	1690022248000000	1692441448000000	\\xb65c761900786f2dfc75af4932c019f9e85d1f7ab5d66bf2bc631d39d8a55333b8c6ae41e451cae1992be506ef037381ec5cba426a67aad07898c9095ab7290b
2	\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	\\x8835f0375cd0db295ef92c234d101c532b5b0c199a3944b1ceca758275d2d43e	1668250048000000	1675507648000000	1677926848000000	\\x7f056c949e5b10779aee48b83f05ef6a9f0806c17b81d0194620bb193eac78bf2f8223a95305b373e8aa7595f4ef707adb8d2734a7526ce41ee17b95c47f220b
3	\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	\\xeade5d22e096dc0a4e0f93adb200b5536a2d0fa01a4305ee7fde9af8d40fc07e	1690021948000000	1697279548000000	1699698748000000	\\x9a10ae01a67bf9ad6515cd80d36ad6a36ce3e91ef37beea5153f3d0725c0e627028417bae1950115d2a38f4eb6c1658c17c852830edd2dce07f3b2604a592102
4	\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	\\x770083b599e309e55121b3ff2b8fd442003ea91fad7c5cd3c4d1a02aa7dd9345	1675507348000000	1682764948000000	1685184148000000	\\x98065827feadce308caa3bb9d59ea82ef5f74ff21965ce275df8c9c48bff74366a025d9cd828a6ed8e253548a101f092a4481c494e46c2962c8530fe9a046c0c
5	\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	\\xdadc5cfb79a7b94e6d311f6033f32442d2a4791150799ec796049f6f7772a8ea	1660992748000000	1668250348000000	1670669548000000	\\xc19d70df3db53fe89fe00a8c74fb2fb06f8871ce97ccd812a80b12a9ea181bcffc27b8e365f2d0f97cb34c543741932805a30e72bb6f964b2cf8c0101ba6ba08
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x3f20d5521fe9e4ddf337277c21f25f066f242826f79fffb43343a711c008a0a9	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x63cc1df9f3c887be5ba29b1db763a39a88398ae1c5d0d05e7122914dc564cca64e686ebee056f782aa578aec0f0c4e4ba9885b5ad5b359b35fd447616f799102
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\xc845e200542958d662c2532e0e702a4a9f1bd01a0e10dd815e2b0f0412af906e	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\xc328a6a79570e1add4e4d375834751b4014b07f4f6f44783992823ecbe5e17a1	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660992779000000	t	\N	\N	0	1	http://localhost:8081/
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

SELECT pg_catalog.setval('auditor.deposit_confirmations_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('exchange.auditor_denom_sigs_auditor_denom_serial_seq', 1269, true);


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

SELECT pg_catalog.setval('exchange.denomination_revocations_denom_revocations_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('exchange.known_coins_known_coin_id_seq', 14, true);


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

SELECT pg_catalog.setval('exchange.recoup_recoup_uuid_seq', 1, true);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.recoup_refresh_recoup_refresh_uuid_seq', 8, true);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_commitments_melt_serial_id_seq', 2, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_revealed_coins_rrc_serial_seq', 50, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_transfer_keys_rtc_serial_seq', 2, true);


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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 22, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 22, true);


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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 25, true);


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

SELECT pg_catalog.setval('merchant.merchant_exchange_signing_keys_signkey_serial_seq', 10, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_exchange_wire_fees_wirefee_serial_seq', 2, true);


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

SELECT pg_catalog.setval('merchant.merchant_orders_order_serial_seq', 2, true);


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

