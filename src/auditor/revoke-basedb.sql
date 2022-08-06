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
exchange-0001	2022-08-06 22:25:18.321421+02	grothoff	{}	{}
merchant-0001	2022-08-06 22:25:19.337015+02	grothoff	{}	{}
merchant-0002	2022-08-06 22:25:19.744397+02	grothoff	{}	{}
auditor-0001	2022-08-06 22:25:19.894959+02	grothoff	{}	{}
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
\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	1659817533000000	1667075133000000	1669494333000000	\\x19b026192e86210d7bd624c42b15146d40f6d9d2207abb39467a3e2df1fbd8c3	\\x37603a74b5b99acb8da2375f6433fc77a138f70c3d0ca91e7064bd6e0f826d34d7ef8a68759aa0d591b5d3109ebd37faca2b5258dbee094834e6b2af7fceae0b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	http://localhost:8081/
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
\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	1	\\x2de737819f8baf63a95663c198a810df7f20c134387b0be01de65ea4d5664e5a60fe0bc145452459f7e7a6dcc12dfe70b97d86739a50ce512241d06b1e0f16e3	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x010a5729b6443d64cb9ebce9827a4b795698dd90862151c8fb507c2cedef307f91e80d9aaf34f7d7f58170ac6752f66364ad44aad55115b71da93022e394e769	1659817564000000	1659818461000000	1659818461000000	0	98000000	\\x194d94de25dd873d26fc7fda67c97a6ced3316d42b4273027e8fa181217633f0	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x3ae6ca4ca266b290645b2758cd0cd3ccae63025760aa79dd109fc73f53ede990435c12cfb766d2c694b7593b7b089373988b531d646da3b3722a050a739cf405	\\x19b026192e86210d7bd624c42b15146d40f6d9d2207abb39467a3e2df1fbd8c3	\\xc0d64861fd7f00001d591a0eae5500005d7d7c0eae550000ba7c7c0eae550000a07c7c0eae550000a47c7c0eae550000e0057d0eae5500000000000000000000
\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	2	\\x9eaad7f119786d9f713bb34bbb888917c023f45140599e3921c02db0c12875e70d01b1161b8329e7d166369a930e8a1c1fc33c0a1254f67a5e162e59346b2fac	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x010a5729b6443d64cb9ebce9827a4b795698dd90862151c8fb507c2cedef307f91e80d9aaf34f7d7f58170ac6752f66364ad44aad55115b71da93022e394e769	1660422397000000	1659818493000000	1659818493000000	0	0	\\x00dd2b54655002edb099ad6f6c85fee08da543cb60e79bada10a618421c7e24a	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x4b826cc6f0e0a7b3c4f36ac1735ee0f36506db1c05df8e90bf129bcc5e5d3a331b77245828d260f017f9affc06ee05d299472a7424535e5fc8640efa84576d00	\\x19b026192e86210d7bd624c42b15146d40f6d9d2207abb39467a3e2df1fbd8c3	\\xc0d64861fd7f00001d591a0eae5500000dad7d0eae5500006aac7d0eae55000050ac7d0eae55000054ac7d0eae550000807f7c0eae5500000000000000000000
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
1	1	7	\\x58e6a7bf6b4856ce23da0ddb9ae8ec4bfe83d9244dbf6141c64a3bef4d1c2d2f17b3cfb0b5d8a116b77906428bc7eb7f4067073b9b9f176fedc27e62c27e9706
2	1	61	\\x212aa7b7f262f21c4ca0521640e109c445fa32ec5315de175c63e3265cd89fa0728bd5fecb97cac9632a1631198a8c63e10c67336edd987f827f39daca7aee0c
3	1	315	\\xbbb806f4527fa570cd950be3a0f2a4c5508d230b1a50d92bb4d38d5f2e476ead17f6864ff786d192e6ab34d6085b2d7c5316c6b48d85c254eeaff00f4a58020e
4	1	265	\\x46f34f0b3201a8a3d1609c2238233c8e1b4cc0228175715c2fcba61926845c7771b4e9a209f45ceb3cb9dacfa7c0754c5b7972b44b6e5638d56ab8cff4e87204
5	1	417	\\xe57cec78463e37cb51802a1f65c4cd48a85ca38298085565a0f34b187a7ae4976f03bdafe0093d6cc39b0591386e7f5438cb0348fe6940ae6eb8332843b7640c
6	1	63	\\xa5bcabfe9fa7466a6f05d85e4556662d06cad3929f0ed05c54cebaf42e9144bd0b32b25228107022c37b4e3242d84956a63da9d6211259e4a1b6a9a7630f9b0f
7	1	290	\\xf18abda2907312180e32da9e86907ec5f2230dda8ae3cd4c78f7f3c850a314fa64f1e363eb9d80e892d270a0ab2538fbabb2f2088251ea8df6386ac1f00dc907
8	1	73	\\x7751b68c93bcd9356bbe7625979a398d7acd1cdeb9f1dc28be5cbb2326573f85b84ac78a7585e748d8870ad03c3ed33aee8bc882cc563f280c4971863a51df04
9	1	357	\\x84bd137dc07c70bf46c3bb69cda6d3f1a5d34e103baf6c6daff231b2b521ea9cbb09c935f6d4989cc26cb87f85ea221e57309e4cd150bb2cef83f8e6630a240a
10	1	223	\\xa7fb5f162825611c2afe7e40edd8c9ee84305f0d42bcc79fa1ac861ad6ea3b092bfc9ea69569954ad33deb10457d06f833e12fd7e4bc115392a3aa4c1496600a
11	1	24	\\xdba8d972ed86d86ea65978a9831a4e339aea13cf53aeaa41b95781b2afd53ade50f6dd5198b26d17dc402997d5d1757976afded60ec2131bd912e9252be4f505
12	1	230	\\x84c1e341bd480adcffb0f0f8ca0bd5afc6fa8813a5c35eda7979897cee9d0099d48c0e174d85cacd6319245f318bf34cf6f31d053de7f35d04ba54dbeb9e8602
13	1	270	\\xe3dcf1338b1867f2b3692ec7660c31bc942837cbcac62f8cd011682df37834d027591a31694c3e69593a3ef5781d070afbc8b6d75f79e932613725def8b87603
14	1	234	\\x2beca89334026ebd95ca6a846b5dfe68578bb296eb90e7937d54dbfcb90425146c8349a00b47825493ac19f7bc55623db404f52119c4bbbcc09a5a159e84a70c
15	1	259	\\xa7bb55c1603adfa8f3696a3f5db0e4f6aaa2a53e4df6c4d34e135b98b6c1bfdaa4cc9cf27e589e89c016dc474268201e0379229d87dd386715570ee8b2dfc60d
16	1	287	\\xf2127afee5f949266cd8195b647ca507cbf362324a2d6c710a3e1de579153444744273ced272191e04a7f7f4eeab3ac83e42c982ffccf26cef8b73b889f8fc07
17	1	307	\\xc1245d7e5e62ad9e82511c6e32e9a6908d578bc55755e37333f9e0dcde8001ddaf49806095623654c7adbef554e9983dfc31a970e599f44fa552d21c7613a102
18	1	15	\\xd86a895f4df0ea15db4fac38b39b3f40eb9f985db0ac0b04d9856882ba3d5fe1a1084e405ece75bf23917aa59a11d93d147627865856fe8e6bf31c774c9d5c0e
19	1	35	\\x87f9146bc8872527fea25c32980c40088e60c00c40383bbbfa49f9a0fd9fe9d2d184119a5244d25097c8b5e9e727a2c6e0962c270fb306d357a47328664b910a
20	1	397	\\x97d82e1a26be76526e6a78fff5bd7539db4dd040a66171e2fc645517c34a291ba0b5b948f295a18880ec26906aab19f2a30020a0a75633006db2c27d30bf4206
21	1	187	\\xbb24977e804fdf9b1c4003c1d4dd0e1c9f9cb5f690f27b27e068dc1fff1f5030af165b5642b5bfc101516292a47f8882f56e6c0760b0a4b617f03780e2967c0e
22	1	41	\\xbe0fa3d580be0cf6397fca8f54fc99fd6558d95a5be0de6b45c7e07247e46ef8404d11cc5bb03d1540b6ce3d01bf02e0d3b6b31658ba2449c3b42fc2ef383103
23	1	375	\\x069a02ac7b01c0fb8a8b47ded45d1e2df4d1f6b4e39a086e1d58fab0dfbcab9d52316f51ac12df3979e5b4af6c43fa652b3434554e4a07c95b648c444a4ce00a
24	1	332	\\xba8f0c95ee10deb632b49148cddae301bc32f43c7c5b7e92ebe40d304e1eea6e330c343413d366531a5b71814a772420a09779bfa2f4192101daafb6e42c760b
25	1	93	\\x04dc255fa030feaaa3f91cb72569088e6737c6d51c1d7615531e3801e8ae73d72a00329a0cac7d9a307e8e9893ebe2a5c1f902e02f0f18152d8006afe66c600b
26	1	373	\\xdc6539fa3b76d2629483b2665c9da4bbe5015f8dd4e0a60d98ad928527151f0e856fe0c871fd87b20d6cef0501f62ff58e9d2b8f99b3d089cd3cbec6e63b430b
27	1	168	\\x6c9dab5831326e0c950f8dd8d3c0a7eef09c768f889bf2755d3140ab8889f611cac2b4b936b88cbff46544a6d333f840013d341ef8f0be5e24f182ddc2be590c
28	1	6	\\x2754dc6c29d5731274276e65bb2e76a8b788717594402e7bd5d8278b761080418182595e843ebae6f83b4c14eba10ec6bc67c8e5bbdfc6c097d16926f58ede0c
29	1	243	\\x24984e56791596fc3fdddd23ba0cbe3343e03021519ce72a1ceb285b60bb326785a2dafdaef238ac0e55b57ba1bf4835cecf5c7206568757dd2d59009d1d9a00
30	1	113	\\x5daaa0efa482484cbeeacc7ffc3d5e45f2d51cc24dbdc1dd0b1b1962753abc0f4b10f850581c53b2a08c8634186a82b1aa4d2a57cea7a00ab482f16c259d4d02
31	1	139	\\x87311dff156ec3b2cc8927fb1c84c0d82412381a5f791d53b73313cbfe8c880584d0c44b5d9d7b2f6182845bbb8f00e78a6134d40ef97c72238e884fe377740d
32	1	387	\\xc1350fc1a49b11995a67526bd922ae9244b7272b3292da4cf50c9a0b303e5a1b4c5120422a2f1725a75a5a4dc377a13334ceddf7c072bd2c0b36e01a1b26120f
33	1	393	\\x155fa1de9363a8b44aca5074309906db791fb7b732c30888bf523cf922bd124fcda032ec55a42b4fd03db3104a86f40ddb45de8b57efd30c040b774f533d3c08
34	1	46	\\x26b6d34de7c6014d4eb2dbf57111837c17c981250a1ed5d9b4d594f2dd25e306c69b0e0b3cc78c3166bb04d3b5348ce1983d96278fa273df1e66228c4d409100
35	1	53	\\x731ae9109130f6338d0fc5f64a43a5bb759fea3084b2651ad2b406152e54cb625c5f08d8c006b1189b966d5e44d2d1e4791f4008364e5e8720cd73db3db7360a
36	1	219	\\xe06522013901209bfc311c26f215cc627369e3052457acbbf667b6da6435a6e1f2987a8d0fe81c93a4173549b9c15f5dfaf5b24847f8776d61dbde3232e8b302
37	1	306	\\xb5456b5528c72294e1f76a3d9c9bd31284d6de61a71195cc7bc0d41aebc79f6b136abcbbcb3e50da28e14ecf9995ae9a7db2cccdf9f077893e6b11f5d1414e07
38	1	129	\\xea11838a6862393e74b0af79e7e6ff922aa7c50a83e214763b417bdf1439255580d3110ae52853677baf2ac5eef9faa51c545dddb81bf3ae05a8b3bb98ecdb0f
39	1	321	\\x62bdb008d7da2dfe163fab8de4eefc7540bb53fa16b0e730f2b08193d3b09ab359a4e26f849faa991a428a91410c182fb5eb57fb132a208199dad56dada9590e
40	1	344	\\x8972d7b236bc03afdb96f95455370a13ac011937e873af7177988340ecd47a6845dc464ed85963a69981e45b4bd97dcd0d14c940e445bf9182637c53caad8b0e
41	1	298	\\xe307a3dd5fcd72ff3629b7dbde26d339e3014fd808cd0033cf8a6a69c7ff6dc3f154e0db4dddc7ff6206840377d38e45715744c55d1da998c374eaa3d993200e
42	1	138	\\xe5e0c6839917b3cd524465833e82c27b2c85fea9851cbb137582025a761a3411e30a68d6e3bc525671e66f4b0addf4b615c6c5f50f71e0cb24c8ab7d1abea009
43	1	379	\\x8f377a877548fd76bc99e1430d27dc138f20569f94fd40cb9d582738a0712c143c8797a0f3374a5788fa79f46a43c42d687ba1d0ed5e178fbc31ac0e8a3bdd0f
44	1	57	\\x76a5a1c80a45bc13d24d0fba47fa28872cf59fd99179d37155a916e3e66d1866444330db8a85f463f131cd1ccc7bffc3e382501758238eae63a1e437fbc4c70f
45	1	4	\\x84c51c57b335f59716dadb872aab581d576384ae6171ad8c2914c6f3c81b8bdda4c90f720e4dd7e6e4bc0e7f8ba997f8b9fab1e78112bc48c843559a6f0d0903
46	1	191	\\x30ae45b563a0d0ec13721565347200c5ec3d977ed24d4e9ca691b182c85ef13752bee06be763185c56731a686bd1a33f01ef5c8c417b13709457cc7d8e73210d
47	1	9	\\xb621e023975c578a14cf428423215f41d3e5d2c6102c84a6857aea96251f1cdf307cdc5e9748eac46967d07e96926f01e28309cb63bc36402cd5c34bff678d02
48	1	43	\\x5f79e53f7e27f7cce4a2aade18af5d8bf28a5fbff050bd8e43646c570e855ac41dc7c96aa13a0a61cc46965f94b4c1799e0f923476cb321f8d7832cf06bf0f00
49	1	123	\\x1a0896ad031c3da16a11306ef7bcfeeff9465c9f92159e4adde96c22a0390eb163018cd9b5fd60c93b3c2fcba1bf2dedb4ba79f3113c2c9b1f10ba5bd1a1b105
50	1	147	\\xa1b91d6bdb58e437b00e4abd1e781810f40c2b1bbfe12143852f370730487e3fefe4e6de89125fa1c04c4adc462275305766111c973d0dd02734a0a51fbe760d
51	1	361	\\xfe8296c841253518f4ed1c36093374ec8c78f12a18c31b02fbe6e64b5924c2faade5a0697c934fc7252ca50ba538fb6f83544efbee414506b312b55493026904
52	1	293	\\x2b1e9019e80fd0e8154ba923451bf5db92c0f252a6a435bd4a6816808ab32b24439205be7fbc6dd97eb627b0ed772c8f9910ffeb888ed611a2291c43a079c506
53	1	95	\\x6040aa75bec7f7caa174aaba87ccdf9868437a6a0c884125cc5e487f36c830ea463302fb62132928350c79ceaf34534bb2d812464dd1445377a7cac0fe4c9408
54	1	205	\\x9cc548c2002111731f81b8ee3fd2e4bd714edc1bdb4ad9b6149e068aa512a2da2e4e9d9a9a572cb9c1cd8ba28d54dd4bcca4efb07794dfb8d184fcd8cb574c07
55	1	368	\\xddcfb6e31f1d15675a4be8c3b237a886cc3c1719e5e76f83154da460555ffd6012be6ed6f2ac0b2cdf684fca0731b3dba9e4370c47fe8e6758e19d2655fa8c09
56	1	49	\\x8d69d12441f26b253f56d9ccbe4076950e4af4b7a5d736a3a243dd66afb818af316d1716b7b69b205eab49cdd7749783bb40e9f14a9de465a9dbec5e371f3900
57	1	29	\\x5f81963982172a96861e31fae34b871cabe8c1ed25aabfa51359141eaf1ee70b370c93b65050fe0c24ef12c58d447fafe9c26adf56927185fe7dbaea79b6fa06
58	1	257	\\x3cb0bb374a6de24c61132588862c885ac6ac0edc73549eed0cdf04d55d8a975e37242a183ba2c8458fb14e206169b3e871c86b3e9835d3b13846ee5ff0818507
59	1	345	\\xe7a7c55c71ad9a6fb0f13c2810809d27303c6d7c4a8f535c24b33f8b6896cfa58b5a9fffe0a439b47adf7c679b93ce6035a9bd286ba510df127065d6d4ded10c
60	1	369	\\x7c9d3303222c42ed440bb78cc8161b7941f652ed6b385f7ccc354e5d747201a391b4e28d5d7d54eae3ebf74a82a2c5071d42c51ff502cebb9bcf6b56130a3e04
61	1	150	\\x94346340354ef5f3c132c6d8fe6afe100fdeee39b172efc457d5736c9a2bb1b8b8648bf3d9d1e0c150919869016f680842edf614815523377046b98252e6f30b
62	1	349	\\x7c7ac1bbcf636cabdfaede19b082819a424b44a98ecfaba6d93c0cf7fdfef1330bb60a0849273e1e947ecfd9956576ac9519639e74edc6ed9ad02658123e4e08
63	1	195	\\x1203267d3352a90e6279f64b9728f859d2a69f94b5d5e0fba3ed79cdedf79bbc1c41ed578d0b95c0bbf8da2a843fdb7a4ef6dd9298051d9561f613adcb42f805
64	1	285	\\x3bbdf5f0eced0257622b9fdf14ca7cce14a4685cb600d9231da1f091a8397224bd29f307ef1e7eeddb4885799857772eeb68cc8c0c6c8f0007d5b617ca8a7b0f
65	1	207	\\x082ceabe25d775b5a6ca6e5aa3cdcceca6a9279d8aa2a92af61b607bc629a505257b1bf7b0fbfd4b8402155306cce83052a4a5560cb51b7899232bf1d0c20403
66	1	44	\\x721cea818d45e578e291ea8e81a636cf2b8c4b626563c52bf53796f3c7c13daf8f4a7033d9d6e38c4f0d0091c01da50fd0aaa268a3f53daacfa5a2e5a8403106
67	1	322	\\x9074e530faec87148e59cb67b76ea3deadf0ff02d4a17b865ef4a3b92b57943b088de276fa09ebba24c4f4703c0a58335fcc9e51aa385979c370bfd23f99520e
68	1	55	\\x022a3b57bed22bbac7797b3a71ea8b1b918365c92269560e2b3fda837c71bb06668ad94200a021ee07a087bd1298c7c33a3c6062908e7a469412c45a784d5c03
69	1	13	\\x511c398c4400bcc7ed4933e83c06e4529a369c1417093dce9755fed009f1d27a50d1e270ff884efcfec92847b21eec04d9a42b8d12511cd51af5760664040f09
70	1	20	\\xd0c248878c25d44115996f72d4ca558bed1bebb8241d30c6e73312dccaf931941663a8b30abde219f0b3d4d3c5570f0c75efa2884c0eecd791e3a26754cd6708
71	1	204	\\x253c256e1d14fb26649331bb908675f9c02f67280d2a516956402898f3903559016033de47a16ad4b4415bcd358fbdd3ba0fcc1a11cb89bc185f83082021050e
72	1	248	\\x67bc5091610c2507ac0c10286080d09adff8619965d84f9785322592ce244a160c3f751acab8c60858314c02b65ce4ab1f10d68abef853c2e0118a6fef3c1102
73	1	75	\\x7b78fb0535bb565700311afec0a201d9d1e8b4bce559e0c127b1403daad98e83521fdc3764b58dcac462e31c16be3d7798a407b4d673b4ed3d1a4d80fe51f90e
74	1	3	\\xe2c9dae6c35dcd468ded651c0057eed3ba8a0984263ceb62bdce72e78d44b96e199ae316ce300e00c9332d3fea2957ea558f1cae8113e476f568014f56b15e01
75	1	99	\\xf62999e2c98028c4018076727b58259e9b42633c8d886aa711e127448421bc8ff47f7af4e9c8d2778ab2b2575fba95b4aa9650548e8c2655299b0f04683bb008
76	1	310	\\x13796432f13feb8ba8677b85e539aeddaadca66c02384a64895fbbebf62d2a050ce77c2e0bcb8a07408ea4cc1c2f7f2dc30aab07c1146540a6b5887accd30e03
77	1	119	\\x0fab01d113f67c6dec800b0aa9456aa914b56ee3664aa01f566153a21609b508e40af455f6292b814a7ac1155a830513f0b807d00dc2b28a58cc6336a30d8505
78	1	169	\\xbc7ad6bf6aaa13c93519b8cad51d161066584923d5a5335d0e1aff75bc6e3519565b7ebb4e561fc88fde8a744133834c95188d06706364ae97e9c96f5168c20b
79	1	406	\\x33f332b92994092c388024e76839db316a3f58dfb1e11f3d08154a449db0f6054243394f84a8a571c9581fd65e338e3868964053df25ea293d328cf148499e03
80	1	329	\\x73bdcbee2485d54909b5e789a5542ccae100165438b6559d234cd14ae5a4517126df61563f3e4fc923e9de33cac7672287af1b338d7e29e3eadbd138a9cbfb0d
81	1	300	\\xa759f1f735d2bff777271c7431bc40df01f0e8e2e5b1d52bce9d9670274ff35044e005e0dff4414b2b10f1304e5fea45e5586635321fc299926fdb3e510aeb0e
82	1	122	\\xe8ec16460991c071acd0c9a3e6cca68df7573c884082fe4dcd2a10b1823b61613ae7bdb40eadf1e24eedb39d0a4a54118baca7a492e86ccbe4faaed222dc0c00
83	1	244	\\x924e91a5124cc47f0ee7cc6b7f174d4f358bd9f62366bca95d5cb3943883f96cad32975638243beff478bceab91a62269adceabf01c8975f5f72f50b63d58b09
84	1	185	\\xc807ffa17c18da3e568d3362fa9fc6cc7dbd086b2804d88ab46f3e5a134fed0f1fe2c79405eff7530edf4ddaf12742d48d140c68d40b1894601c337067ab390c
85	1	145	\\x7f531e113bf00d4c9ea2819c1fc24203800418d3794d4d7b6ee47a24aa4a291fa0f9bd4bc30c13f0b0d9247c2a4e5e33f3d91c071838f0549d27e8f5d1727306
86	1	405	\\x33bd6659edd0431b4eee4a023ecb38935e6d826e526646238d5e345b33e2d689b97a82cec819c6ff14710ddb532a3832735781c9c4d2b3b3c0adf42658db8900
87	1	377	\\xf7d988c7d27c3f06956800021417f2458bdd59ef6fc6c83e68c784964225806494a4f5e92d53e5b266f0ed5ad4898a7cddcee8a890875ebc6ad7da337198fe0a
88	1	423	\\x339ea8bd987d771685e60346683c3f5108bf7f5c8b65d44ffe16ac0cc201ad6fa74c4c6ffc8421532bf2e5c1cd2278531fc12f63ea390c559a6f81548fae0f04
89	1	282	\\x08959a2d21b5c10b9cf403f4bf78fa593dccc35a726ccea9a5d4ecc933880604f654e89e5d089b7ed5c3777fcd39ce2e36b172985c90de97f8d347861abc4d07
90	1	391	\\x7f73e4e17e682b47f83e3b35beb2ebe0ffbcc1e784b5316c127bd75602b310b14a6f32a4987dab29592865de5a73e12629209039c5db0c64c367992e6f8f7902
91	1	420	\\x214f8150479c1407bcdb2ee7814a89b72f7768e4ee4d222a051f1e59647e06e0f2855d7feb59415435c97d63e40ac136903e77765e33793917aacbec018eed07
92	1	101	\\x303c710433651111762a93fb3b0713879c1f11397e60c1cfa9a167f5eb67662078b8c09b3ed40fa4749bce1db3856e0537af81f8fff1f1dee28dcb36bd1aea0b
93	1	54	\\xc120e94eabd15017882615a46512f44cff758e3b6528f1f5ed473497018ed07767f21c5152584cc266a0a2c869ee1517760324b702a1a7a96f74fb248a8c6d02
94	1	351	\\x3da75ff0317f7761332c0f242419f882e0594c3e871928e33162d7be606960925aeaaef610615546de62bab2c95cfd2fc58e40709ce0e7a6edc619dda32a0e01
95	1	389	\\x8ee4667f2da019261a0b5905f11a209c3376ee6314b0803e379705090358b2e7f12b1844e3e454d138f6a3c6309c5e3d33497cc763e9f0d4f4cb70636a0b820a
96	1	100	\\xa529c6c6cf8963d1b89a396e4c87452d45e2daa0bde17a0bb67552307301c009987673a9f0a336717dab40da2f5802e3c74cf45742c18f053774ed171001ef0e
97	1	245	\\x80df9a84ae972ee773757b18bae53ff0e37d163541ee1d5cb0187e6df3e0898aaa85297b3a71406a22e92f07f3f400f1a9fecc257207156582c12e2d46d08605
98	1	8	\\xd6f5b1fbaf2336f4e3a35981be30313ca4b769454d2d466a1c8feb9fa716196029596207a7c08d6bdba3507a5f1fbf948ea3ccfd504c469c640cd0aa7d584a0e
99	1	413	\\xc4073b8c2dd7f38ac58ae0771a7bd29d2c55c4a498799799e3d777a5943c16edc85eb7717e491f2ad91703ed6eaff01f5625595e40a7bce530635d090358500b
100	1	342	\\xf5e529fb74cd2cbce0aaffd86d12d9644db04936eca9a7e9c9d325db8e586ddfeab49bfc891cc81b01d00dc2c3153c3ce3c79671cf40b22277f5b5c1f7fef303
101	1	370	\\xed484145750ff8fcc7f7e0e132a93dedcd74ac17c1cafe6979e427bd49bce97122b3bde091d815ef3bcf3aa18f98ad7ebd29271f9866aa0d1f200ffdaea63b0a
102	1	424	\\x2a951954ae022420159734cc879c96df5c3ca272185a12f07db4fbd517e2bf8ffff02184e067a6121b52c0e33dee4294bcc90d18e07268b8165bcb988bebf609
103	1	394	\\x6d8bb493279927333d49f4e5fcc2f59ad9a2f558d99197141befa5f435d27980ac0752c79b720d4a2a47e994793da70afe43b18c69ee192b74a3de1cac712607
104	1	325	\\xb1b21e694322f0f75f5cccc4d0ea20ce35848ef213c528ef6b3116c3beb3797102b62f72d5cc0a5ad152d2bddaf2344c102db4ff259fb736d84fb5af9eded10e
105	1	167	\\x0c58352ae554111a67f9f4a2b8cf625afac196ad3844d64fef82a479ac05f0e4616b0a7f01a329af142d37aee89ba9e9e0b7c71e020b1bf12a24e1f354da9e05
106	1	200	\\xdf86498408af194999cedff01dff5f1a22afa945fa814c5f8d8639e90473e3c20c960e8b697737c79834e81c5815401340b1305f0f80888477290badbe0b3b08
107	1	378	\\x02e8d2793080a53d1385656c1e333e42f111c6782f6f8b166cb975dbfa4346e450fc4b6cad6588029a3b0011e9b2522ddb0dc45a45d2ef7629d2147303f5c70e
108	1	281	\\x34553e26b1ea6f646a9099f52d47128e1c32962962143a6f019095be80481272e9200d9f8408360b47a97afb0c38565b949a0f97a73de979de4755d5863ca30e
109	1	181	\\xdc2faa104083c9e322d440d5c470654266f84e0704450da84881b8e94b779e21f5b90948d6b7c1e8e1f69cc66ac829dc27df50fe2198dcc5bd8fc26d880cdd03
110	1	94	\\x53ae499254133c140b394d1907d1b06c96eb5c79b8352fa7a799cb188aeddf37209f3ca8bbacebb98cb843c63bea9e37748144f977c049e8e60292bc06905e0a
111	1	104	\\x82c154508620e5405ce6ac668072081f87cdc19d67f113a4dc081ca0c527b35354d2df17e775ef591a59e85c242f1889f3f86640221582b9fed1d7c5c9622700
112	1	11	\\x53539241ab6de4ac1e5235da2df92eb87520898cb2386f4a2e0fb99e6b32d38120e5ec56961eb9f1ee77a10ae67f9583cc2323f58c84738a8861f5eb7657fc07
113	1	222	\\xa13d2c4a0be0047eb26f34f01f2fe3566aeab0dad9c01279aac70702e0872612f628c9a2a4d342c3e94b3b6e58d891653e2a7fc152b503a3d24000d24a2ccf03
114	1	36	\\xe032f2230d1f3ce577dbe841c85ac9380fbe6865a18660cd8af432e1d218c7d49ccad069838faa764e83001370091e49f78d08464f03ec6e382d174d91566200
115	1	194	\\x99e16f3e4ae2ca24e948db0acae51313228c8b6dd02e32427c51b37ba1fa7d9983a56e9a63f62a25f690b14c5d7f7a9a1ec542217ef5945e192e196041536f00
116	1	266	\\x8368b7572117766bc9c244f8e0bcc12d63e60bed33b4ce09859c9e96284686820f13715097ab653f4bfd4abcc77ad579cb4115032f4bafe6300c72239c365604
117	1	163	\\xbbc29780a938c85312b19ec61d8931fca43f894841f9c61da267e351e98c16a16bb80c2f7147be92ff60a4a3d05490fe7e605080eed27a12c8c0213ed3d18e02
118	1	263	\\xcb2fc38eb18ecae018d7856cc6a8ce2cab77cff8a9f0af1faf410703536dd17773bc0696430eeaf626d73021d588c66903756b363a421e7a4913a3a6e9cb9908
119	1	279	\\x34801c5539bffeed344001f96b4d6a45491bf8f30b8451a32f4a9f9ef19cb37064a570f677ea839fed587135f91a44433b2d6d4e68e45fa55f108e6019cc8a02
120	1	242	\\x49cbf91abe5a62c43526d85f2c71c1b8f7dc88a8d4b2275d0efd41cbe7631b2886270f62bf122429635354b7d23740a4a946b23ca039361a64f19426f6dcda0e
121	1	128	\\xba4d05c6b187b2a992be4a1590b67490cba6a4dcb4644915ed89b8962d1c86940a3599ad3c7bfcce9b5960773a1a9b17475b2a74baa91a5eabf72c5509a2a40a
122	1	264	\\xa0961490d3545211241e89fdac75a1fcb337fdd7d009020ade68dfb8d1fcf808abccbf2806d13b6c3bde68654c2970ef0961dfc03575115fb0f1e84a49f56f0f
123	1	117	\\xed4f7cd0631b5ebf042eaa5653681fa60da24c108c1c6bf755977fae04edd45d25a92315dbbebf0c3852bb3c3efc4415372468b4530eda75d3ed7f35980c0d0b
124	1	229	\\xdf5bab19ab168342f9f02caa14272a1f3f48f1ec6662bc886b9637fa75bfd104c1706d33d09805b99fd7207ca8de5de8a8d28ff69986066cafb7b279c61f610a
125	1	10	\\x048121846a9e04c37ee1a1ed7cc80a679afa48c75a5b6a65fdf9a4d10539ef85088f60348874ef5fda17adf258716ef5e2cb5d5593726382483ed98f25370509
126	1	338	\\x5da2504e63ab39f258147823ad3a58f98d3204135145c2430b8e49e0ca38c9adf87555afcacbf5bf56947022e5ba5dba9d1294f6e14364f2ae9b307ad9480307
127	1	148	\\x995162eedb662a0e18d25d660a8a9f4c2b6b86b5060446713a5af2b86553dba23a28467d7ab018623fb72bbb08e40eb955762fcf68df7cef479913ecaa8d3a0e
128	1	238	\\x1241dfcb26153856a3edbf822f69df4cc244877bb4183cdeab0b53fcef83bd053b82d084aa47a848b42585051350c678d44244be2bd6ee1acabbc8c0d470b60d
129	1	144	\\x81124eed32aa483389ccbfe27daa0e8dffe30fb3663433569ed86701f11749fee21e5f3f0b4af1a7708935a0e0a5a875270aee16d8c08bd0b1fca00de59e7203
130	1	280	\\xb9d213ae0bf4c491c820f0a18491439755852008468142be5ae50ce5fd7df6b48645af9cc4a32216a54297629369349a34ab0913a0cdc765c965d787cf04110f
131	1	209	\\xb73868b5e6e1ef2f9ddebde1c6ba28cb9fe240c7ffc9c1e00650c9e86a2fb3239116e61c88d9335fde71928f0fd3effeffa97c169e4bc4e66f6b43f1fb8e3606
132	1	132	\\x5bfc5a267ff74048c2ab1e4db2766088f8af17527e472e5d1c1cb115ecf0c10d86848bd54a4cb0f30048a2c9c1402520f6952497eb70c1f73a39da93603c7207
133	1	158	\\xcecc5710abbbb2232634bf8b361e162eef89835e944959608537d91012934e81710c4af5c8eb4c4ae14eb1e2b3c206a7f6037b476314e835b20dfe66f7e04909
134	1	267	\\x3f70c7cf0565fccbe3f5a9049555792087d9fec26aa4db3169d0a7ed2b2882386043c918a946f2c6e5247d398b579c64d46abc37bc15f6a78e4754b40a8bff0a
135	1	284	\\x4e3aa139ee3d93f960948feff4924867efc362b09682118c47fcc279a05ed55c026f127b75eff176a259bec72327f762679ddde63a0084b33fb5de39eefc8003
136	1	237	\\xad2a826b0b5f0f514043c40d12faffc6cbbc0164ec1d7a548dec3531a4fc674830aef19d342fb2258c3f57e4fd5a560f4a6076e3b6ff7f2ea3244d7468241000
137	1	30	\\xa3de1c1598f644f0588b8e47bb78459bf56c2a2c943cdfa5d3868bb67731b100cc957560143885a4267c48ec038b2807033e13246056390d7bb945fa45e5df09
138	1	297	\\x3c22f62004cb90139cf8a879ee59d19def4bddbb7a040a60e76dfc555b3d3d6fcc3ed2c6b45b7fecdb2ce83aca1919d3184b8da4677c2a033322fcc1e3a1f808
139	1	133	\\x81e75fe9b5fa5dee237948267bab5d75e03c301ec5515bcc914f195cc83865ec1e7b6e7c9ed85d984780a158db710f87bded2bb6dd809eafb44fcd303d87f801
140	1	337	\\xcbf6040ecf7d62bff639c72e8db63c5cb1771f965bc07c7b2ba835ecd39cf715a63884b1104ae6a6cc7215b7796c41e487fe7f4be18ff14b00f5420c2962f600
141	1	396	\\x9e21184000dd2cadab6024a1b7a25b34d5effeb5144f2205adf5b326d288514e08a3eb3f3585b386444c60bbff225c952d098b8a8e402905b65d2b00e4008c02
142	1	202	\\x2c7392a72ce00b8e6f2194dd1668bd400525531d5ddc5700e955d31d33e6c941b3159a9b236ded66c77ddf9ddd361a5c17b49a55318d081d7b68f019d67bb300
143	1	152	\\xda5e7b4e8abfacb2ce586df830c4c831de2abc1e99cb0c8cfa535aec8440312d52fb4b88ba24026b6cf540bc036733cfaf48e6c9763385aeb3ad77e267d78e0d
144	1	1	\\x9e8a2065ed5f4e04f0fcbbad804cdf89292616528a700ff422123eff7e6e9df004d304c58d1cfd6fc824bde29b4e7bb917e262e782f5ca53dfb8b61c98952402
145	1	312	\\xecf95d5647b7a62e96a6cdf3c1eb9b997a15a04d52b006ab9e880b891f351e83c90566c2b77320ac4729d51ff0620dc9827a9cff6e97700271ba67941fb8310c
146	1	292	\\xb0a559ed5cad00267d06083640b78e994825606646af83050f0321e3d7ad73e060e2bb868e09371f5c8c5945ea5450120eb18032917b7e3a119c863c2f97480f
147	1	410	\\x5c5bd10269ccada1150bea963a2ae6ff4ef5e0f4956cbb5fb2b308e6baf85ab47b1fc84de527a30d2fe1767f2635dea736280a1c4e4328d660dcb77a3df79105
148	1	210	\\xa5fd562e9340814f9279d5b90af7538c492dab87d8574b799cec6f1368042e29359c6ae9617c7a4eff80ef3961fb8125a22bd56e2380365189e3ea26d0819407
149	1	236	\\x89ad7157621ef4737dcbc9d78ea56a3681c59d68cb9742035c7f00ff35e6c7da4d8ce9ef7a4125e284c4a3d8a133fd5a374300cd45f95b35b345aa267d093609
150	1	157	\\x650daf90568686f898e9e025a161ffff0c2e4d71325c41ad4b9fb356d3e0b6a559e2f424c058df396295b187f666b0920b7392ca019e906dede0759a6d49560e
151	1	153	\\x09c26b277ba0ef7d83b03b6ce67e7503c9a4b90b020eb42f5d4631c7a9a3bb3ded879cc6618a09d2f0fa0e5a0d9299ffcfe73df1c345730de644f11d18f2d503
152	1	247	\\x58fc188ef66e13bbe72f13c8939dcbaed678b523dc479aede4bc31f8a723031a6899414554fb43df04e4fc6a5bc469b5bea2f9555edab25b35de62b7fb6b7906
153	1	343	\\x794fce36dbfee53a688d994026ddb343a07fc87b4981b131726dd8eb4b3384c1830368313552c156187faab11fcfba8cc6a0df488b568579b5b04e82a2765105
154	1	91	\\x4a23ded176fb329be13a3b80a22b7469b1d40204e05d843a938e79c170460a7d99b4b7a6dc989e70762c55a3453f9c8362f43c711a3bc8c4d0793a8db2d64602
155	1	12	\\xe3205d84d23babc3a1b4fcc64b8af0a11e574473eed230288f011a5f11d9734f279e09621a614c4f7f3ee88eaeed59971a003fb2bedf864ceed5325a49246800
156	1	58	\\x51edcc4ac2c1103372577ef497645caa4457b865b1eaf29e71483f004a04b1cbaff641e55b1a74db10ae606f6987ab4503adbf0da023cf7727976ea183fcdb04
157	1	131	\\x9137bd03682715693f0954058f6ff4e358f18bf14fdb80918a4f7581a1080d194b15c7daae6ba4f1b9ec691f5b64147f3d104fecc7c3b1146d633bb9ca580b00
158	1	32	\\xc7aa8c5c6cd37d1d276f2e39824cd4e6e975dbe503ad0ce750f3ff8406aa68031859c986b67b11fbc0edf317cd3273ed5b24625f6b5aa90083e5cb7731a2dc0f
159	1	364	\\x08df2d552a4fd82c64bdbe5d1451475aaec1c0c025a66c2a000d4c86d0f010d15c040f173ecc8604056db1dd409b7b22925edc4fb6cb28c387c6bdd49aaeee03
160	1	177	\\x49e6cbd65725215af856843ce9e9eedaa34faeed6e5cb2b32c5cf0a9de9182ad7ba7fad91f97c03a58d295038061c131b33e4fc4608a28925766aa919c729609
161	1	160	\\xcd052aff94c2e5c4b3386df5003e559712178faa9ff9af72b689865e6ac8bfe361067c67406fc366eea09591325545f7ba21f429df29055d9fe5df648f909f08
162	1	381	\\x71c60b6663796c2caece110196c40ef9b8a9144d4a18ddb3701221144a231843bf4deddf4dabe3dd59c10e2292751ffa257c894e69b9d7e3ce55ab3ebda7710f
163	1	31	\\xfc9b2e63b5ccae83b0e8a2666d4e29f97f12b7abe906fb60243e8a80d81e66eb5187ec025b70cac07a7d29e058d0a6adb69ad1fc0c882d33f47a17c4cf291605
164	1	111	\\xa2f39e3e221e139cfba62373d8e3a2a6391cebee508c9226dd03bfcaf51a3728ea24fba40064f75e9325a9e692c68e2e7480795afccce3710e6dbdbcd8957d0f
165	1	336	\\xed09618234f0f49d5f6f4bf0ab7e4c363250eee14b89a9bab36780ed67c4ebc1d3dd51298cf9b0f8619796c8ba1ccf13546c331ca59f9da96086fcf5482bdb04
166	1	71	\\x89b0eb251af2ddd2daf0014192fc68dcdceee3cf9a38414c806b3058281dbe782aa2bcece24cf457bb93d86aac046b384e430c7c328de01ae3564f7b0655bb0e
167	1	251	\\x92d104f986a5c99ac6242b59b1cc223c3227ef055b364f9431d37e75f7662d3e497c9d979b92323d6f5218050d4c4d318b481b338d46b011f969ce20aecb2109
168	1	232	\\x163885b088eb5b4c8f1bfbf05510f25bb38ec34f15be0fd0a0414b58f76b5f12a635df3a3452e7f54a1471f596027190b4e357c6f05db081049a05bd7e78c706
169	1	86	\\xbb58cc6539e15899a764cf9ab77e8775b42bcd0ca8bbea1f75a0b73d96a551678daaeb5afdcf9441fab4c529ca6c7bb3c07c3af89f82637541be638660efc50e
170	1	231	\\x899507473e92109b83fccd95011745b6583ca03920808eae61ac6f2892aef8bb752c213be12e358bad2e84c1a9e96a3c0edf9f6f8cb6bad16978ff1fca240707
171	1	302	\\xf79a4860bd286657e725558ca6104f7cc4e48579b126a5810e1255c5913c40170bc1d4c98f47a2cb402e24485c30ba539d5aeca482b564ee866fbf078c886004
172	1	166	\\x04052d2cd49010357699b098e6e0a9f095e792712ba359a57202a3aadc0a54c00aa26e8e953590af4c2adb8f9e0d25387380b968a2900dc730e2468f2f9a9c0b
173	1	69	\\x31a8c14edbdcc927639c0e1f1f980ede831bde0ba175806bf4bf6b3edcdda98376fb7c030f7ed854b840af971e1dbd43ed1e4dea2d16dfc16867bf8c91c77902
174	1	228	\\x532408b869b7660dc4c414aab727da3fb65e0d6a43f215ed615aa3e9faa1cdaaa9a15586068ea740b55c88b4a437b86facb8a344056404ed90bf54a661461306
175	1	294	\\xe981f1a086d0b45b08f7da3010b5a1747050d900a0d84161183e3b7d7587a6713a870f78ae8514c4733a336ce7451926de02e8a38b97e7e7a0676ccc8a2db208
176	1	363	\\xf3e7db01068a4e6df02f48c1ae0131ff9c6a20a2092f553f512549e1ab9b5a52358f33ff98c29c93aae8f7a95586bd73c238a31906384151eee04c7d6305e904
177	1	140	\\x94709e5db333e9bce136718446f4395cac137ea80f304e4078d5ec339c6880a0cd902b7c79cb833ec829890149f12490569a105b79f0297207262570f668fa0a
178	1	21	\\xc227bc0797d48a174f9bf487833f0d92d10a93eafa59b856956bb5a5a99da0071f33ddfa1bd063ca79b006c1b18ede89dd89232869a8851ed03bd5510067d80f
179	1	220	\\xc6d9f72f3e2bb6159cdbb0f3ecf47fb3429e7b60cfbfa381546c3f8b266632b673ac27098d241d90e7d271086ae9263237dfe644177fef8d5bee3f99e8f56a0e
180	1	258	\\xa6ac2b5df92c0f72101c32ee96f83a174e656b2eb8ee569c2a3906da56fbebad99d7e8d86752bffae7d6072b31a53e84963f1f087a93e59e63fae2105943aa09
181	1	183	\\x0e0eb44a700a7780c8d6e47c81037f1dc87dec225bcc2ded4404e0ec38806157dafa9e024eaececabbb4680d4399b7e83e81dbb7b0a7a090c05e0ec1cb612306
182	1	155	\\xced3e0103256da210b8924a2db6a002a8bbbebc3645bb3509f1c89559dc09a1d3cef446aef6469eb35599388b6ed54763565515caac20a0b0304316512982d0a
183	1	14	\\x094d54e4e586c59f1e81204ff32027cf033d79e39d63dda531045de74bc262667ff23ba67d5b17a6ed649c884a89849803007573d18d70b5f1bddfa2ec03500a
184	1	188	\\x6cecdb5bee92662d62d8c8abc135b1062a17198f80e810bd0be5fdf2a6c679fbd9b5be030cc1472f716d934795a3c55c8c1e51f9dd2e56619cd9f8f578a26c08
185	1	374	\\x1a57db567547cd050fe5347a704140e15e3c5a89636cbf32c5bc0aa6719b3e8ac6911ffada556aea5019a1d5879d8eee8b410df6053c8ee08e933ed0dd22ab09
186	1	422	\\x1277ec988270a1abe0658bf277bbe9c4f7ddde3fa4ddbfc71a3753d64a509deef0c22867afedffbd2cb230870c8e69c0c1bd730e989333b81158c0c56c9e8106
187	1	211	\\x7a039fdab3bfcf0217870655cda7a0a9f77291f8b5307653d658e46796f8c79131cdd8217c26587b1d5258efb65d24106a9f0ed085839d052d39d0d5487e9308
188	1	112	\\x8c393372d9b905cd439f87f8cafec728c744c55274208f80882fdc5b0b80f5c85039f33e32902991c7d0900f60796ca09b88ae0b3e6edcb95ba47417812d9b0a
189	1	74	\\xebda6662a2ee391afb888feb15b61f319963772e264637d7a9751f4dfc918e51ac4391eacde39f00896b91c7f01013aea1f6453d9ef7a9eb487265266b475902
190	1	260	\\x96654c5ed0367191d6a2257eadfa8d868c71d4d223efd925e85b252fe6b762477cd719eed4f171383dad6988df26afa53bf0e631772ad393d20bf1df84e35b07
191	1	314	\\x1e6e0276d3c5961b5e43a7de885c6cff5b0c873da8263b54bb0c3e08c529e5efc1b72fe504454b9c5f4a17bd3e5c1831d2fa8380022998ec0e3605aff87a5b0d
192	1	277	\\xbc0a3f530c89886486180298438308facb0cb376b3ab4b33f671c8f398788210f52c50ed79a69cd7341c4a7d6f3f9a2ae1b92e5fada299fb1daf8b6069fa3806
193	1	319	\\x9312ad83a48c9886ced861f6e6e8f89869e846438677205b8eee6447ce387fc6679f091637e454a3dcfbc33f4b5985b10e7b4b2a469e8a0527126ba876fe000e
194	1	208	\\xec31dc7b4ac7cce90f4d0fcebe8481ab55da043f41009d95583bbac09410f8848cb67df3fa979b9cfdff7d66e582a241868ad312460d9254bd392067613e7301
195	1	193	\\x8a3f3f8fbfc13cb78b1de5825e69f1de7c8ea7394440d00793b3e18835f9828c32c8739c8aa61af0216dac2a0ebf2feefa5551b215dd05cffaa8a51d036e730e
196	1	250	\\xb43e43b17a26f3d4791ae73a9c92f4fc7bb208d61693fa70a8f16f2fd7b0d49f3477c46ba2be83d0b2d178ff38be16543e0e8f2b2f1909ab15115ac04614200e
197	1	254	\\xf36b4017e157d0922caec9b3eb67862f3d7735e5e036b3ba5e8defe64b1777e39bf767a0fba3777083b153b9db28544d173f0f70440147e582e6b291a7e18606
198	1	151	\\xd90c57dd838549b0a8cd72dca76a16df7935c87e36344d660724cb37c4615a97b3918733d45bff6d963fdfccd299e40e032f3be9a798fbbe847441be8469d301
199	1	383	\\x8c837a0c3fad7e3196398ee380ccd9c689f7282b269ad2d3ab37c07f9c65cf6262d08cb9dadcbc4e384d834fea4046932cacc9e4ad4479813c0150f42b19c304
200	1	196	\\x511eee677ae35e35bd0fcc979e6b6f76e0f19cb92845353dace8fd1d117d27474b2f2e9b58082935fa22d9e0317795fdfbca05c4c0d0481e3f79d7abd6c05806
201	1	305	\\xf4d05085927182ce1a9c4d2f7b807db1fe7254667a32665c131df516f2546bdf36223d713620da427fed096ce846081ab7009209d74f8a3e07c38c8dbbd10703
202	1	142	\\x7fa83df66c3e7b2f36f6bea52ceb7808d9e6388b34df7b2c4a75d251d2d2a5eb9cca10603fad49df6f9eb73ca0353cd8de9b27895cb463699a287182a16a4302
203	1	362	\\xe54ffe950943ee4cad146efdd5cddaf536f8a70d21e0fe4e732fd673394326aec6d3a54055006816ed1c6a6995114d8df8f4d016ef283d4dbb774d16dc5ea00c
204	1	275	\\x7738080d2edd22a5296ef90e06fe13e6021e9328bce0ff7d76382cf698309bef3b9243528c9e82bcac4cfff7b5f80a2b65410871795a7bf76b929167e384cb07
205	1	331	\\x7095701fd1f798acef7a74fabd01e58f583f0746dfc64af9ce373b6c95584ee54fc416f914290c0eedd358e1f61e5f0f29ab1ac079b8a5ced7c1adc4e5a6de05
206	1	358	\\x713f800ecaa7ccb7519986178ab52251a469a2f0f88b2da541c3debab3c4abdc0810282c48df01775882ad7375ff7cb9e81070c5d9a9a8cfbce9443c997c6908
207	1	38	\\xdf0d53aad8bb5aa073bd1c43b787e0692bc89a6827c017edc082c0ec7d9d00a6a6c848b169ec01212b619916e1e3fc08e6fcff54d04b16bdec182711b03cbb05
208	1	371	\\x146a12a744f543e3a9b25fd8f0e47145d45eba574de3ed9184b2d4ae96959e391a898cac2c80d86399df3bc1dfd3867b2c2cad6236af1669f16f57c5c46bcf08
209	1	62	\\x785eedd9128da42e67e7a6d07279c4c6afd533b66f4ad146b6739fb1febe8a56e9f0823606f22530d4972297f31df4f991f8b417da383932222f77c8fbdf7504
210	1	416	\\xdb3e671bf2e018a6f8b5ae1337150c30583e347a1123431c357b3fe76b95651889e59d6ffa5635b775a2dca2db0a3f9b6136d14090460cc1b30204bfac82bd08
211	1	388	\\x0f6b1b9041df754de678c8045e93a4ff3aeb375688618c48f957d06f8021dc2fef8acab35d35353353dbad65c6cb06e18e13f11d2ac8c4147e95270cc589170d
212	1	16	\\xe2241bf551bbf8f0024ad5bcc3e4aed38e261a7f966c32eecd88243547b16f46f68b7059f6108ef9d4338e1dee1a3707d49695472c9426ce277a19c254157409
213	1	269	\\x99283476c264d270f8e36e4e7f2389a47491126019fcb9ca488e358e4d0542ac2040e7957de7d106a78b6a3ee80428e726f9d601dc2261f36c6534443b949109
214	1	149	\\x2d80df3dc6c578f90efb7de678f747f171a832da81cb001126b175bd2d401cde0389c124e463a783ce6bfb403cbaf6d104300201a7d537a1dcbdc67727f4da06
215	1	313	\\x27b5b79d75afd6bd290683b555a0b30adfa0b279f5b70bf015a5ec1a65051b0fdd0a718ec30b31b12e44bb47b3e237753ba701d6a002d4f6b5acecc06df6600c
216	1	326	\\xe99f203015a43d80b2a4f5a40136adc68569f8b12d93e70ccd739f3a9f802a9bd1eea060444a6205bfbf24e3846d9fce25bdf6caaf60f58a9576a7a223c9fd02
217	1	365	\\x423ff8c9d3ba88cbeea6a2840a0a00491d2388b3fa60c033cfc3b13f179f67d50b643a016f95bf46657850646bcb62b2df5870586a15633787cff7143f46530b
218	1	77	\\x63e2e25f5da866d7bda3a838a17667ce6d1fc2f26f84c11989dc4e4998aabdceb232f1cfa7aaf5678efa5ccfcb32c40d5233fcbfe4486dda885f18e0619a3a00
219	1	25	\\xdea1fa48f1e2ee8542510df72cb82a59ee1c1da8cb8f7fd4113b84d18a75c00fd8bfdab9ef35dd9595dbbb6db33b00a527681f7c1bf5fb51db0383d2ec41800b
220	1	255	\\x53063393e34549cb55badff06bcad3d0a2e518327262f54d7d489614a256abf031ecbeff376d5898117ea0d46ee99f162a0cc0718825d46adb5e75d4f043d802
221	1	409	\\xab84b77923f348322c2c7889f57f887e7ebea24cfd29500093a92f8ee8df874a4a60ac569430ff63720a55385403a6506caf1948954a2e14de8800e3ec4a2509
222	1	212	\\xaff20578c7d8fceba6af9e9885f8e5031c40d44eb2d9bd0be30610f8e33e8aa95db96ec700afb9b3034e5d77fa1a62d4d2dd826828aa9cdd25a2243eb108380d
223	1	81	\\x95c95226c02920e240d205c03e6efb4595717153b5a031ac8eeb8a0e230c07d5313160692b8c6ef82c0806bdb0af3b400d59cd4d08abb178c3c972bab4292002
224	1	87	\\xa115bf784dbd1d9d48b96be7bd1b82648fd52119448b151434d2fecfc1142688d56897ff9937db2aa29909bef1ce0f963d8c190b7e2137b9381f95f42e422b0a
225	1	79	\\xfd6dd81a0a9eebeac7b30b7bc710323311d6e3f93ecca052a02032b557238fdbdb37fd20200f6a6f59df392f43dde29ed89d7ca302524898aa13c456996a230e
226	1	146	\\x7cf096ebdf287566fe5d1915dec1c0e07adda8e13471da0a5200c5382f7e50a208401289102470a741ec4e5a0f565a1de57c339698ed87f61b9b5e0eedded70c
227	1	88	\\x5a70af736af5be2f0f2aa8c86c6c8e0c154dd2712437394788c700b0e7126c26e5f49164dd9f301fc1f060135b8396add4d9beaeb2ee36ba7bbcad4d125a4f0e
228	1	118	\\x616148ce3d795ed4f341580f6f3920aedb230d25255a8e25a17d35285ac4d53af803a7e2a469dacb75fbb48809c3bb526a71252f42422e9666a82d5baaa3fb04
229	1	50	\\xf499d7f2c00ebcae73b6b1f7050c197e0a93b7cb0f9aa7d2cf021972f8709ac4ec392263eb13ee045158ff77e577c0f6c03ead2e79cf1e0c7cee2e55f99aec00
230	1	385	\\x54a4653e1b52f9a83bc3f7e234447b6cede18dcdf1e19009bc3324d5b2cfd420e251feee2426f51d31639804ef12f4da4ef4fb1bbbe307e609df07c1d65eae0e
231	1	18	\\x4c911fe00718f96fdafd2831f3e5e2879c669b351fa76110b22f92b82ecaff5c999e4a1a79022c280e50de2fdd9aac8e7a6a217045a5e37d7c8c3646b4798f00
232	1	399	\\x77adcda003e14733736d0804911e62229041e97e749fc7e349b1976bec25fea5a9441e9f17d0c3718875e19f4cd0f56374ba56ffd8846188c0341edea8253006
233	1	190	\\xdf9af028c302b114d866d76d737297c7848e65bbd1557a190f97b38d4f55c6f1b6f26d33ffef532bcb4fa9c303d599a3d2b9d0262320b0c573e483cb616eac06
234	1	240	\\x6229bfb4486bf0ca929624e24c5436df78f1d15397e9483ace9c92bf65dd8c5fb0812b6707982acaed1a287e5021aed741121ab345e4d4f121c0751ee0bb0007
235	1	5	\\xf7681a82e745e3663d1e753d4f9bfeb54b7569d72b136068481eaa92437d4d97c93ee905ae79e1c075059efe11a32d5e611429c160df01a311e7de53c5784f09
236	1	110	\\x4012d28d60bfecaffc789f088dbe9f04e41ac4d956fbc8504356aae93a35a740fa20d8a9a3b9f6719c9c01dd08bcfb153242d83e60e33e10ca0423e5fb957407
237	1	156	\\x74f7aa065acdbda60bb8610d2a9600181331c83436f763c494f41fdd6ed926f4e614750c6d7ee4efe1c0c7dbbaad9291ef8618e80d7dfb2d0a4f95994a57090a
238	1	309	\\xee8f72094c35a365a791eb96b57ef93672893847170b468ca951d026b157a16ef4c45f7c8d68e612c66b033bdd1db7819486a9a9285418109829f749a810bd07
239	1	395	\\xc250d18e15e1613df26062710a10bc3377639569a5534c2e73b92dcaab89bc6b72dd27f3c706a247b5891b1eec00d5484e16b31e0ec095e2b8c6dc6c34f5ea02
240	1	346	\\x18489162fd640368841dbef0efa3e2904eee9c0ac6c6e97c032e42eef9739074ee010c27ff08642e6ba0e3180514c88777b4e39a58aa3dd3d769b8357aeb3d03
241	1	134	\\x04f6928b447b85e6342e6c3738b5ebd203b7916fa3c3664107042917da9f808e1221ca54daef104773701ec4c83eaa51b4f9601b5a0952adc5661a03b2d19a01
242	1	376	\\xd9d79106215cd1a115d6619fca5be5e0b06b6e275c677b6f22a79ff87528342094354c34e8d8ba1d5442ccebffa00774ae1d728c00e390490c4ff165c8869b0e
243	1	34	\\xdd77c57c4b5ead0e065d89856d0c2f0dd5060ad767dbd1bb61ead4760b111c8483f2207b94e5a8c4f9f07587999aecb91334b9c06677a9335bbd7c1be62eff05
244	1	352	\\x0abbf3d08b0d7c22bd0e0048ca07cc7ce67272410320ddd2fc367a371852b2c51ce41ba5c17e86a6f088983aad3a4d739c4ee9099aacfbfb9ff1da893349310d
245	1	241	\\xba6623e14c6065ae85f40b2b27f1430e6a423d145050d65213d9503be0ae3d4335a67bc3ac436e0c3aeb30ab680d65fc240cbc762710800ac16842a29bb0b602
246	1	341	\\xe8feb7d7bcf2fcef32981e30cc6e94285454e2aefc941e83e9b54f1e3b48fbef92169d809b20dc522ac30a4c2aa927ed894b92f17fbf0ca2089c2da434b9c20b
247	1	235	\\xca3a0ae3677db8a657e02fbf2efd925793ad2342812e0998c5e85ad8a8a7792cf5498918f7f47051af398e1a58b10942dd135d3a9b96c0aa08b31db14a280c0d
248	1	268	\\x3ffd8e8cbbfd4e04b16935d1942f93aa7a31b717273d2328cec0c51633f92871d37ea0dbdc32da5d8e49ae42432c5ee9afcf5209ab06b298718408882abef706
249	1	17	\\xe3d0d4a6246ab52868bbed3788d0b62ff78adec2cf9bd974f71c2d9ad24ee5089593b6934b0b3ba213dd931796f64fa6fa1a41b1a7fef10c315c206429b1680c
250	1	246	\\x4c374dacbe20fc2f2c7f14e83e6671d4feb0c9e123ce53c7e2bdb6c4ac1349c7d25ad86fb132470cccee7747cb273dc009f5b4edb7cdaa50a62e332866811e00
251	1	184	\\xcd9238efbdd091e94b67ac210143170debca16b945fe465acc099c2e296eccfd76f527cfd26b02d8acfe978baa7269668ba079dc878f737505cfea078b10980c
252	1	372	\\xc18088ca26e78925e9bbdab54bafaf323aeaacdcf24860b103c3694fda51655552a6fe8f84abffbcde9b9287913faa8f214063dfd35e80d4bbe0a0cd43fb830d
253	1	400	\\x0429cbd918b5dcf99a3bbf5461862a3ba16926f58580d934498e4300b27c0fdddb56d04de733f5d8d0f882f84ea7ddda4940c39cdab31b85c9fae3ef5fa50e04
254	1	39	\\x0002c55e30c8305a0bdd485d61d7b9cc331471e8d7f07b1ca27e93a6f72a740b7829e8b91d38e034d0ad355326f632b73aedc8ce51a0cba9c4462bfacb447b07
255	1	350	\\xe4043ce52e5d8c035917266919528e7f7335273f0952325dd8f4829b390e1d01e1482c6ed7cc358ec4a874ee84f4db8a3cccd1d71ea27b4c3036713c0fc67005
256	1	2	\\x860774f0b7a3d8f5a63edf029ffee0e571b2a00dc585056eee8622f3d49dfd095bf4ea45a4edde1e97757b519101065eba5cd838a1d3f3708b1ef1dd6e731506
257	1	301	\\x21ae269e4217663b3fea424a08b5aaf2d23b00640343d429175990077ae3cf2195412505094751556e1f196639d33a5274b83ac82e7844c419735b525a01a707
258	1	126	\\x043034d4f0c8225c5e0a0f64fc0554bea328f164f1523b72d288a9674f0615bca26a1560520c1d68177624a17b418a599f80d37d53d0694b3b06272700f0480c
259	1	213	\\xca0441469cef012c7f3a713e71f770b80e714f0620f4206303168ca89800c21bc445247f6b05cafadbce5123f9bbbfc094b3d53e1bcd88d27d3c17be43c52002
260	1	175	\\x8ba8f4a3df725cb8cb51b85382dcf037245ad0cf6fb1f54f2a3a148ec077f679d8d542808519b3c1471ca984f3485b2dd0ed0cf339ed0b20151a3941dc194e01
261	1	418	\\xf3e3421e74f49583aebd23fc33971ad47753bd9b7bfeeb2b7cfbaaeb84437ed61dc77e45a29edf449cb841579fb6f46472af8b53e995d73fc90357ba5fbff609
262	1	179	\\xdcb5d3b2e805a815df9bfa28eca2ffdfdbe109cea70d2ad17b3e453b7a1558478c2e18365a2680beb33457e825af46c464c9cca67ac3ba6d5dcecc6717987c09
263	1	90	\\x0f07665bdb8f78e337814270f54fc4ec1ff21c980661f3e47ec46c271c2926a6a344a0a2509ca62f352231316202fcfe0e6fbe6a94d37f663e2584c4f93f4604
264	1	173	\\x2e9b0c1c82b8571060afa22f334b80e20640b24f5c3f1e038539a56a8b38b3c62988b125637d8fb806c7d10907e315d9fae8df4652f1e0ebecfabd2dc8443a0b
265	1	72	\\x63bdd948fb59fc39c47c59f01bf20a3480005b51e7cc86c9c76c4d8e5721897a81df72f0722cd90c2bd8bd6f532a092a5671b404e015c9e5ab22603ac2993e0c
266	1	278	\\xb5318998dbc6e601d6e4ff024ada990b000f52e5362f6b96cbcbb258666fe0142d800d956136e52b1552dc2848446386a58a501eea9154e3b7ef4423c3afc70c
267	1	178	\\x369499793587eb6f82296d437d15a561634905bc64c4c8a451cac6f00745f4f196019106db985eb9eba900ccd128a2240f4055d388de7e13c6a5bc7ba9255b07
268	1	40	\\x80ca57d1e35d32e22680640d05f6bb22cb45d00f72b1a2664c5c4a48d8c7a24f2007fea400dfd6dcf1d7056a9587def6e505c78e39ef777f807b805c74b6d00f
269	1	89	\\xf1e1f84252030318198c3683990b64921ce550cd47cd0299ab1468b48f667f173e5439161f8d650aba220bf86d88d645aadcbd13636fab1a362f1a7545eee00f
270	1	60	\\xc93347fcdf18a71215dc7e9faf04e6bff897ae56cec53027428591173c794b135066cb60e9a571cfd6eb105d1ea6dbb20cdc30aabdb261048f9daf4f715c9004
271	1	97	\\x070428534cc0fe8b0be514417f5d08309b907d083b7fdd3b1f048a0d1e95d87779c57d392cbfdf64ec3a7f5575a2c2f14a03bc36262e7f4b11aa00025143af0c
272	1	103	\\x6f7b5222f9a31d7f7584245348022321c93f3cf2db8266b23b16bc73cb41f4d234f709079be95ed3047090f89c1160ccbd7edb43ce0b5ccd1cc16e47b4359904
273	1	105	\\xfe7269394a65a3d452c0f747b37615e088e42c38427189b86c7c5095e5153cc7d98c3bebea2804abd4004329593c495ace77027c8d197e5d98dbb42676d7d40d
274	1	380	\\x144b13c9b33cbc0006077904f573e38d438fb57977b653718b7d9cd501ea9c03e057853c5d7a4d36f3ef89d074e8d8eedb3582b80c9c4d8b08be571f43d19c02
275	1	125	\\xf985b224c742517b5f4dbef8048282b9ec1aed0a800e5e803553ef15554423f2d9f758809433666fb8cffa07916be28bd1f5c0cd75a2046600ece5e41daea505
276	1	127	\\xff466a9df34655e6367276556f61110fb57e7f73aaf1cda30b241e96ee37739090138b17ddb5566114a81e782e487a0cddeba99da8b8d5b4a120e631612cfb00
277	1	130	\\x7101b77a14054ad22d5bc82fb099a1ff69f83a6eecddf4117623e439ac0d68f20c3ff9db5858c6fd28eed52254fbfb12145b99d502518ae24f14f9f4982d850d
278	1	271	\\x7ea3025b415ef18b66cde8b1ea767aa4862642dad2beaa38abba9c0fbb7aa8b7ffbdb572943ca295bad834ade14a8758f708d3d6744292e3a949024abc312809
279	1	330	\\x1ccc79c0287c5d715e65a36ed87a4cb94ce24f55584e3deea0ef4b0002fd52a386c741409e37da68cdf76cd4abfa4ac060c44d191d13cce801eaedc03deb300d
280	1	414	\\x25a71704225cecc7e8668c52b951c7f31631e94bd4e06443cc0c1a9b65b6348746753f7d9159c870b7748bad79d31f5ca19f05499e5160f7d6b93b7aca274f0f
281	1	48	\\x0ecfb209b910268b9bd35e5b891cdcc69999f52da47be35613a8b4f72ac6fba2de9831b6ea8aebd85f9f5e1a2595b5911c49965cdaff36ee2a7ab9eae23d6c02
282	1	348	\\x909ba624484442da54e0c604071e9e2d10a6e810a0703798d35dfab71c64e916aab8bd1757aeac898b1e4d4e0ecb228d177696fda63562f8b5dfc741ca3cc609
283	1	382	\\x2a9dd23282b51ba9addd8be4ca4b3b6256bfedeb4288aa1d2083cdb970b640138163e7d4c3e6ab9a267941c5c12dd4c7bcd9cadbb08a3454a8ac108767511604
284	1	51	\\xb1f81e6ceac3b46cf9681d152309a2d115bb1af1ce77f701a5f64b33842d76bcef8120b798b088b6cc4d2aa7e5926f8727007a68efb53ac53e9c1f96eb865903
285	1	304	\\x87a8c934e8510e5c3a4f36558a0bee61d566dc6fab9e64c757e1772e32b8b4ab35903385b8f5a083e7b0010fad836bd044ed973804369b73cdd49e7d5a842f0b
286	1	108	\\xdb1713736c1f43af4dc3b05a0ecefbdcd06866e957530ea3169d8702f84afa83692354809216e8eb3bfa7a53937ecc4ca5fa4ea0df25814b4e67f22af5f21303
287	1	164	\\x4d25a36dd2edda18bb578628ef02d0fdf8a3972e1b8d806033287e743f884b311fd6f912db5f38d5e617e5e572bdc7295879711a3358ed24422ff0a0dcd1150d
288	1	78	\\x45f16e72ff623347c25cef3007c3e3b74da8a29ac489aee8ba35b7478ece79b08d84cf3f5ad9aaeb60d38366b6c279b3cb16112bb9f5bb6a566011fd76883b0d
289	1	272	\\xfbd3cb8a2e6afb543086054c70b4ba076d59c72425acf809ae2e7fc440b867ab7f491d761ca6d96c1255004899edb1e8d899b373c9d0c395a6b4b9c04c29a90f
290	1	227	\\x5b0800cb11b42f9e36d475e9295fa2e54162b2c9cbd42c4082ff742401f496f2f6b2ea2747bb6a6fff3b56a7f05b78be8a57a9763d1942276c883f37f7662b0e
291	1	288	\\x5b4f8a7cb9940f2d1624e2ad173653d99f409fb89c67ad34c70790e7db0a5af8f31a29b7ad573864658d16a99ff63f9b06a366c5245774fd9be44dc5e044c70e
292	1	225	\\xb31be27e2fdacf56f740a05050b4e82db3c520c92d887b3680cfb7d022eb78580c27cc06d5ecb0cff7521c4ce72fb18979b3a12db9b5b744a892b0ccdcece105
293	1	386	\\x4e764cecd59480b08d8d4692b8d0f1d9e10290e76162059e076022a02ccf07a9b2d56c35714ec05477e9dbd78dfbcce0d45a0473b5db1584f0eaa4226da02a0e
294	1	52	\\x2228fb7ad58c9c5258ca149708e3e1d110d4ab1a7f9e6a6ba4b996c45633558c62dd68ad6d912b26446918a40bb312529105a731ca0b9c1e8422839d2f6e9f06
295	1	398	\\xde8cdb94189f666ac38ae8379f203424165ba54bc6260319f2e0228dae2b9bd89ec5532b87a99fab3b629b7535ba8e8103b6506bd43e6518d999e00b4cd0de09
296	1	203	\\x7d321c01aefaab8e04d316010637118664f8d5ece26facc845ec719daea6ad7a895df3d9551f85415c0ba909de37c3ab8310446d265deb142f4f7331cbf4b907
297	1	239	\\x0b4b6df7f3259ce0e4613ec2faafa5fda03190470ac617dcfadb1f87f6731f523d9de6a84897e9c55848fb427f372ed8a94c53a18a7a302d839a429c34464108
298	1	401	\\xa2b7d29098a1011d57ea8474f761aac7022d12450817e2dc570f7aa826a716bbbbb1ca22af48b4499aa2ba9f46d957cd95aef9cbd4c47442c99057492cca3c06
299	1	106	\\x0be90cdc9dc721bca5c71afc59b41aced94778c5a26019c175862baa8dd0ca6209d24fbb5792b88d07a306575d1146a95e7eed2f0ec7186bd4623c6c5ca1ed0f
300	1	356	\\x601032f2028d2aedbfad3f7cb32e282f1421cab34ab72073feff9c4b91596e58ba3d884c71bd3cfebab1de73e621992201ade0bda8f65b0ae4f3a7221b61360a
301	1	355	\\x2110aee40317200b5fd9c7135b8d26bcdfeb0fd5a9d063fa63f0d74e22e47f0cf665f2e258a9a627f19b8f03431b70c397c84b653b574a1f0a76991b4e32030e
302	1	159	\\x718537ff19d88865b84721950a7e47afb1c3801a0d7659373b613e76d763021dd5315d6a6ce8132b5000d97643f9be5a5e0ffae7b3f5cfbfc985605cb49cbe0a
303	1	320	\\x0bd2ad549f83bf435eebfefeff753731f9cdb860788b888272f3a2ed05d5be0c7d2cc42ee579326000236c24af97b483f78f8be856feb2c66446b55965d04b01
304	1	82	\\xf33875927bf21d0b7c9bace19b504a1bbc6ed7726c9749265bcdbcbd921f741351f11559eb7533a6b24f2c30863e66b5dc3f54f03fd07cfcb583059eabd2fc02
305	1	107	\\x95d039990564e853379bc03e86ee8970b8693f1d60bfeb896d8033a6a7f7aef8161a4ae64247a7b55afa977b033aca17e1b304938b921f669f604ebc31075e09
306	1	256	\\x10826d884345e8081df1ca2281c0f8590f853a4c91e9ae621cc317b84f35dd95ae4416da8748fc75e1c8839fc817021669209e8b0ff690e2ca91c474f792300e
307	1	347	\\x52d7a67f6bcddbae58f5c3a7a2e5735f6f8183c0d735f8da3cc6aed4153a5f96edfa07fe6e63ea29e3fa56c2adf9d1cf8c4bf3f742b97688247f801d435f200b
308	1	276	\\xc28837efb474032a7408f5f61c0898409da98c717128a85111da0cab895db693c2b30f800559b95cc5a588e50d6e40ff74cb514ae098a838230f18be1396f20d
309	1	98	\\x456dfefee9ba197f504ba14363546957fc90c60195ddb27d3bb90a7f2a798ed13aff827a95275b4504ede890fc8740fd8472bbb2093b5e34c3b2d9d9566ceb02
310	1	124	\\xd3bf5cde82882788f58275a5d81e71380849745f1ef06cf0d5b6d30bd573616d46cf65453763e9862e75379bfd6c3d20a94df3ae8c316b7f7ea1b86422695f07
311	1	221	\\x2fba371276a4d733063e1ca65c951e9a90aaaf6a57290f86de1e1beafde756b742752804fcde8fe305049072bdb56b8a4e8e3c45a349c8cbe8dc17215ef31b0f
312	1	66	\\xed09c9e44c9e51f5d909cd5ea2791b48490acb68964b9570e1dd7e5a428eb6cb949500afe2203aa2819d09d2cf469ac51ca1d805dea272df5288f7986be73701
313	1	174	\\x689adbaf2425efc816caf53da1092f7db9a6e82e2476705746fe635245e7cd28a848f1b5f9146f2d59b341044c0ea627ad6c2f85ae492b837dd9352e34bd4203
314	1	22	\\x97965c8f74e4155b6a56c77f279e54c1bc05b39a78a3d767d45a5cca912af38ce99458f4c108275558a4b569c06b1ad9ae3c33fc312a28095eee6edadd0cb401
315	1	23	\\xe6ed571ef259694890f1b286019c8046e1bf4ee0668d3ee1b8d720a9e4b373fe2fa3c60057d65caf84c8964e713cda64b613e721b5825a888cf16b503d9b110c
316	1	199	\\x19b72d52b33f977b833dd6772e77b856ec0eb906d8319070c6fee3518313ca60d218290a2cc40f58aadb91908032ce6ceffd91c44f009347141056548a59dc04
317	1	189	\\xd7a360bcfda9c7e2bc06407db39bc2269a32cd7b3c78ff9e8acb2cba8fd2a3f3e3bd145239728785f73c091eb8f5b2ff8bb1e29a362b3105d39a7bf4ab836809
318	1	56	\\x6886e206595d11c7951d12270c9ed11ecd893688d59186a860d7137c50e3f7aeb6a5dad2dfb84a1b5fd453611256aedd7af2b5efa3fc3e560df466fd568b6609
319	1	216	\\xa07b42a2c25c6d048fdefdd7331c1293f39eabe6f7730c836fcfca6930c1ed706d89b001269dfd1ae2c0a25739efd491f3952b4c99add07ad93a82ae87f55f0e
320	1	85	\\xb3d05ebc84fa083c40af61c8a1dfb91df2c2fb609757c15382cbe52bf1069b9c70735095359bfbb8ffdaed207fa3e05b241c842fd0ece2c6f2c70e520b91170c
321	1	333	\\x9b70fa6a3811872621e9aabed5d2f55695509ee2b41691e275b3922d0bbda95ce3de16cc392380e5bdd97b7c939663db2f8d3c80519c58a5c90e032a175e5809
322	1	360	\\x8015a8eff3e155948b82aaba6208a2473ea092423f449bd7e8f4ce67b72ad96087548b97d7d737193d734eec46de49bfcd4f30118ef81efeb55fa491a917ad08
323	1	214	\\x6cc2380d39e37dd6b8909ab405c3d3a472d797fa2c108b7dfdbdf1332770947dd41fae68378ab6fa3a910e5e4ad1861e92b2405df14cd81dd2d7846ddd83a008
324	1	136	\\xebe10267156a0a9b56d8a8b59564c7792aa9243c1f493035a6f9a813b6c254e3b9b9e3c76ed7800bacbcc52f14bc5b26c83347fba3603af5143edbd6c842360f
325	1	45	\\x17e6b53caca1effccfc17842e332e9bdc5da4ae014fda4b4850b948034472e7806906ebc37a810b339ee87bdb08c07b9c79b12b070b48277c2544f745974370f
326	1	334	\\xad51a17ecc12c99428bba6f7721fc456eaa55f98fc4dacd086914fd529bc9f0f156bb03217221526a91580ada669392fde7eccb31a8409a0f28b3bbaabad230e
327	1	367	\\x01d2e7742657cefd82de86494c8bc7a732f6c0f7be6cc7c6657f5247f1f4e305a61c0772ba12faa08f84832cd675ba76624c8e0c93c2f247d1eafbb232c5760a
328	1	65	\\x3941a485ec2459f4a311dc64bbee2c995af468c722eb2b39db387bc717a365697818410dd45c51f169f2d6bfd55c312f5bc96fbce059b83da20959ee5641dc02
329	1	141	\\xcd0d162dc9c61588dc2a6d73795168282d4e1c54dcfd4dd6329965d633fe24c30d4a20c3acc2821ac8cd4d4fe0224c00716c75517de3a75fec84b463c5633c02
330	1	206	\\xff8deef622da5f90ed199548d92822196faa1158cbc42166d3cfe61c767bd299f2701831a95bfd2af403d41e1044d78fe389d07b9ead2e3ce0c761e3e3216907
331	1	404	\\x3b5b7b4fc3c4724a56e803594c3e9ab9dfd11daa083e5dcac897e055e7d3f078607ef259e1e24a61015006139cabbe7729a81a5de37b3bbb475b0d70f671c203
332	1	84	\\xa9933ed92aa8e9e827ca93173f89cb068322cec4522b882a01a7e84e22494ed35dda909ede6a011b3b728cd9760b2f0f08f72c8116a3aecd3b7d089cbad3ba00
333	1	170	\\xd7dd6ad95cc1a86be4cefc00a0298b29383f434bb9599584e204a908d062bbfc91412ed59ca0808f47426defdd2d60472e67bb03ca89f608f91d3b55ca8e010c
334	1	115	\\x4afbefdbcda77a046efa482d2c4a2a89c530a759059e3dd82a751500e2711dc60b623c2e101cf9e72798ceeadd2a84e5e5c6fc3a89de1fc3551936c4c97f9300
335	1	120	\\x619b119bb907761899ca25f22d3820bf0542ed70b12e67332db32e1df0884b6cde98a89a335dce5cf310c0be69ce7d24edaaa725fde09400a2c3de3001db9a09
336	1	92	\\x45e4c5fe9687779889a288dbdf225e9c60a1fa4ba6116fffc4e6c7cf5de6ef4e42141696dff5a10724eab5d4d0fb5787bbee612706afc1bf0e7f0865d317c905
337	1	116	\\x53354e4580afdb9982e388c8825c137f2c6cf1f5abe3f1259d8bf12abbaf1fb505bf6a64eb768ca0d2aaf716a8518d6465b27a99e75a8d21a50b6d0de1b84c0c
338	1	162	\\xdd9e6e0d19b9967738d4bf871f98b44c29aa83a4a6d9f3cb737636d633f17447d2a2ac0478fc711abff731534b2ea8344407cc86d4179dcebde5723a448e2d0c
339	1	197	\\xdc21ad3978c60a432b13b91d6dae6581f1a1347aa0f8544e992cc932639e2e343ac85bf546036f431d382be07e5f3535cc7a23e241db67fa8555bea6177e7009
340	1	392	\\xab5e8298d0b6bff2c3245fd4ac4b5ad58b9ea12dd4e844852b1b326f1316f727312914f6a22f408dcf55d4e45465fa410a217a31d5e50d73ff1069921de91806
341	1	135	\\xa43690405ac2f6c2f9dbfd2593bdae0dea89d1a755ef016f15b9620601a13dc38d5219ae3acfb0004e3cea41e61f4cad40643bccef734085ac29c632f4d2c907
342	1	308	\\x23a7669e1c3509b841ff94d1ab8e7e9f69115753b134fde421ee2b036a18206020a44fd97411ec9da7991e42a12cb7f9e666cf4a78c05a73b1ad35abc12c590f
343	1	289	\\x81d33cf77a24c8bed73a203e810346032e5a0f11308151c2c52f366cc8aefc85b4ec72a3c99ec9e8e1a1567c1668bc57849c43b4c3438e496da7cc4b7600ad09
344	1	201	\\x38379ceee0b16769fe30074673f93281f731a84f518a0c6e168abf51bb15b19256c2936fa113b9e11993bfa6f0b983291e9b9af4e02cd9ea064d398b184fb60e
345	1	291	\\x7ff15d9342aa0b1bbbca87af7cced96eda4f66af652921d3e889d86f6543b35bffad27b6b2413a3f7ce31162a5164090ac5002cb52ff77673608838ad3b63c00
346	1	324	\\xe29ded0313722b9101d8157fbcbe5e82e7c276ab3e7049bc05cb308a22291ffad42bd769f7c559d76ffbf5850cc4a43c828c5f8293cca6fe94b02d7ca71f120e
347	1	182	\\x493f3ea51c0d80aa53050f57eef7228f72d27b5be8fe0d75942bd49399c5ce9890489e34d130f5a71c59c5d7d9180b220b7ec6287b3c9d4d75d1d7b4b9203f0b
348	1	109	\\x3a369fa685e5a916350ec36ccf1cecdf99a3d15b8d4353934e822d69a05f157d991b7f8fa699616b77111a124f444a63c0b31cd5e3f17e63c6f2c4e8094f0902
349	1	102	\\x3c76f5958241d2d614b586a2ee27d53d368fb5c4bf208ce7022f2c0fa8631626bdc2f24b0b96e791035f11846fb796b0d52ccd6e06b8619e95436dc02f9bd603
350	1	273	\\x6c82a56181f89ecf681eb08661cbfebb4e217302d017c67228e8e8e2a06fd1018cfad83f86d448737b7789622cc9f4588e3d0be4860987d8e7c23cb468525f06
351	1	172	\\x1ccbfd2f7ffe87803b04ab68a706f2eb93f3dd550f8a82061bdd78c77c81baef81c3989fc8dd0d83422c1f42073abad4cca346abc3c789063f19075c447a0507
352	1	340	\\xac5ceca6765a21518a1ca62e870d68be00272dcb14bb4401cc383c5f05a2753976f99573e2ecc8ab7445f938ab44a1adb3f8acab594bc3b10c86174bd77f850f
353	1	154	\\xb92f7fe71959b24ec8ec727a27330adc90afc2a999d76e36c36e6aa9f609b2c60a83864403136093167412523623f837890e57c6ebc10acc76d987b3babb9c06
354	1	299	\\x20a7a0bb59c1723ef4c3d5b980af88c03e01c49893c954655b243a009ccd51de928a9bc1855ddb08beb242a00cbbeb0e0308eab878f57d85efed5d4265231204
355	1	283	\\x2555d0426aeaf871f9adc395a734e2a28ae5042130bb8f2d44d36252c3760ce930e91cc15f7c61d764a60d2e5b7a70db82a08142bf13c62f36de37908366230e
356	1	419	\\xce4c9eddc19c8ed9f16f2991bd137b1d8f7e7f57c5b9aef1ba430a5b22835fcb58cd23c5ce774effb035e58face4d4424e6fe1f834eabef6e6ee966f0fd0f404
357	1	316	\\xe5b40217af18752fda00bff836684767e0e52d5e7a8147bf038f5888f984439df5a6421b2dcc8a85532cc6e4f4078fcaa58a8aac68bff3618a9540851ce97702
358	1	80	\\x9fa9f5b5cc6459541e9ff7a5307008ac47fc87bc0f88dd259b10cf2c559b1ec173a1ccad8e5de1b8507fae7cc8f3fb00ef8bf1b715c15597227c4332d7414c0b
359	1	121	\\xf95bec9aeb063da637e8d8b442ff944b65c7651b7363d57ce22300a021d53117ead3446b7b31088fc87ffeba4ac4d4b2138ccdf4aed0d067864796c584970c0e
360	1	421	\\xa6717e81b96db31df916d6905f139f6913fec00277928de3c8c920a91f287397a7585391f8ea6d71d58d129afd570e9f3db8a7cde92e58c11c1d5d0858eb6a01
361	1	27	\\xd84041c05f7ca748c659a29696919f6ebd384a626e0708a897f17aeba1b175b0052069e42eb984770bd815ed8e6643cedb2a8c17d77911e29cf83f7662db7f08
362	1	143	\\xc6ee25714423c5adab4145fff8507bc0483747035fb90cb93f586b289fbdb3886523230e81e6632a7bd9dc08462c6ef86ab54a7056364ca5457c1d08a9081601
363	1	215	\\xf2d2fe7933198b43dd08b8fd7de6e6f56777bb86382e498719e76564c5ad7be17b06af5f69ad01be699a10b9823d9b1ba059b4293ed8fe4ebe4ce5d235339b0c
364	1	411	\\xdcefa222398f1c9ee529f1efa052f0e6c9693aa98b9edadfc85a1d7d2c764dfca966608976b1c4c09bb8aba6d24108202bdcc1fec835735553204de1f7506101
365	1	42	\\x378e432d8d88721fda001a6af8d41568e95b90ef4ca21aeb110d87c0f16ba80081a7f6d7b42a80e8dfe981223b00afc56ab9b5a1433be083d4a20d2f0d2db50e
366	1	180	\\x5b185811e21f6ebc7fcf885601ea5b5edddf83a6f543cce86839cf98edf556451c06bd6f968a19b32f4c06c102d21238b132cd406d4926d2c5ea74fcf6f14f0b
367	1	303	\\xcd562566348617b53caf1131d395ce017826fcc027f16e2e75da88e575b11ac1b38c83202e8b1997ca39077a7e96d279551be7b422d74ea81d9f9b841efef200
368	1	70	\\x19848aebfae439e8d7c0d2ea45250f52191c7be0d65e4563bb17c843f4dad4a8e51c673a54f3796b809781e5eb1646e62dff17b561162ebc12ddf01ea715b80f
369	1	176	\\x28903c8cf50a49e39f45241fce24684162d07fc5429ce91427b74db7b92312520d446385566d16f2394d2c3e6282434fa2e940a3f484945a88960ade7066f508
370	1	137	\\x62ebb96c4c83d9e1d266f8a8a7d4b2387a34e1cc266b1311a3fb93850444575d077911b622a23dc135eda21996a979effe832f83f32c24a47ea0a715f19a500d
371	1	233	\\x3979ade4e8bd35f0c6529a8edd48002dc7a1559a11a4fc4f3937b2b60c6c9aefa1dca9d3ecdf0bf75c96782c69ba76b04f2919e30fe0772dff1932789e379809
372	1	412	\\x247d3c6bfa5dad2232fc58d9ae769bca2cddc94fd149eac397e7ef7bd9d3576d8989b88178539bb96727144dd0df2ab77e89b185d041f29bb1a2de9cf1e6cd06
373	1	68	\\xf8efd919cfb4a6ba3f40b9f8ee24b96e7b6f563af329d1a9ea3629b74d36f54b3fee7ec4e6ce61c9ef4490a27cb65ebea21491a65c73c773dbdb6e863d46e40e
374	1	366	\\xea44f62fd7ad0f96010d0d673f4b3aa3c4999ca210fff548a6623720a512cfd7037d7e3eb04efc88293047ad4a052960f34fe43f00ed682db8d4bee743c2d606
375	1	218	\\x8958bcec49c95a51ba52716ca3c6368b9dc549ab07a46b80993d07cdb294406705bdede97f30173abfd342bd12c36097ed71017088d230669d9034ccd9c19009
376	1	253	\\xd61a1a2362d1300a0272b68acf2efee1119eace77b6b2b07aa1afdff866330381a0da9e709644b8f58a39a3a60336289936003cefa8f20fed6b48a4db1fdcc0b
377	1	353	\\xe858a6acd8ccccfd7ae626005c7e99ff466861fe38ce094167971cea39faca90954198baba3d1f2241f661007f3fc7f79a5e68d9faab188aa70bff1ccd20420c
378	1	311	\\xfa6f806e45af309d8118b12f7b48a21199d61d42ec9d425e4b53e92d3def38465b39a76463fc47265062894e4a6fcd74969d19c0a5fee1bf17578dabae0e1901
379	1	161	\\xe1aec66b1c10ff3080157945447d6195856c0684fb24033cfdd460f3e54ccaa288ad95d3bc1a5ba1e38a6e2f6f86ee63c8e3e5d91232026a737e8782d1eb4705
380	1	83	\\xd33bea89438633b7d8d7787986a59f31fec4ea40e04a8e0a3c734ec2dfc7c91af8302fdcd748c3dabae98edca7cc9f7df133949f5482c9c2970da0174f232c05
381	1	261	\\x4870bdf1e9c2597cf74cff7c7adc943635eeba04af6c4e391bb9cdcab866b747835bd7d0f3e4edd413df85d402709ba6880d1d2c51d029ead4711a147c4e7503
382	1	359	\\x22ed076017fb59b0e28e0f75b766a4426920b5525b608b4a9971f076f671e0844453f8bf1aaccd6adeacf466a5ea84082a73c98c0ac776c76d67b323282f7103
383	1	318	\\xeab71173e1636cc0cb8e40f163b667405c8d3abf27f4cbd66d9ff8c0c16f8f01bfb194ef13ceb734370d7480bd313823649242473853b4867e7c9d7b088c9804
384	1	28	\\xa07bf0aece41d933301b1db40cf83b251fa27b5e52e6a1a9f9ccf9d1ecd645cc322865b51bf414ba60ab4d4aa8f3520794c272640c036ff3e4b1cc10ae7df306
385	1	328	\\xb258a6d6bd32076c481daca275c3357e3dfadee7ef8f1691ac7b8377030f1dc682fb0a068a40818e82a07d1a7ebceb9d04c17afd292fc4d8a5591c44bf2db808
386	1	64	\\x050fbc912f81628699e8c15732c97c36fedfbc063e72dadecc0f87479566fc7630608d7943fb41d9c64b86176e35f8192490ae26dbd6104b753e7e72a0fce90f
387	1	192	\\xae273bbc4ed978358f14be0cf1354c437b210d9eb39f468875b33e68d783d8f9722788996220ee776dd4e24d54aee44e7e746da7638360113034b881dee7bf0c
388	1	335	\\xea47ad60ca74fb0186557892377325557de4f9c0c8e5a78ead065d03d88877d257fbbf8350a93e31246edf16ab6a8a4e0dafd422f265a4f51e9de6344579af05
389	1	408	\\x55f6b60d1f9bf62db471d8584b38d281719cae403a67d88357d43df67833b1182303f3fdfb46f92e3fe0a86e9ac620a4d480b7b7072bb4018d495e32eed65803
390	1	339	\\x1a4d08e495417f22bb70a0834e18202a9501990ab828c5d33704452c4686e781a56168dea17016f7702d37d28e432df4ef9e8ffdd063783f81be239c6625580c
391	1	224	\\x95dbe55ee0f16953b99a6600c845b6dc66bb2dee892ba6dc28c53c4136ac1c634909774c876eb20daebe9a62a41309184a7dc8c2bacc0201c7b3abe9c9078404
392	1	384	\\x4c45a0ef8f71d92ba65989fb9f94bd549182de3162a9c1fd4803dc54f99d106779bd4369cf5cf3fc89db4370ef9a9386ecdb8596f7c463da8c47ecaef6e4620a
393	1	47	\\xe1d297507f1695c49ba0f81772067fdcbbd46f240fde48829f6ab7e8caad2860d8cdf8aa6b603cd51f7bca963fd92c4288be0a4d70a61b5eb7c9ca01f032e501
394	1	317	\\x54f0888e6dc48d2f4666b0ebbcb592fbb2fe1b009ca45e56c2886b62b3a6d7637af00928bba7c0898193aa3edf0379ebf10aa239567e61961f2b2e7810323202
395	1	252	\\x132a75557892e371ff0d2434129aa94fa3f3093518dd3db79d67bdd389cce3ccc04b917211b1e0379727a4121287e2ff093aac8b292baa022d3d24ee08bb7f0b
396	1	390	\\xaa785476c7997b227f06877e8bb46425cbc5f6f9dbbeb11b9145097060cfe3dbfb2787e1c647013ec0536ff2429d56cbac58341699818b67bda12a64e00a5806
397	1	327	\\x938a5e26dbc5b0960f0d90b8da2e33fc924b6cedcde8c7505cd06add4eb1548ba78891d0c62840d61d85077c916953b040601e357d4a06477eb9698cccb26304
398	1	165	\\x9f7a740489dc7cb6d361208abd9654188e8da92315cbcbc3e57383099d3342db5984ce621225270fcd8038e1c77d5a95976e8f3aaf5cb47683c51dd2f4637809
399	1	402	\\x484b5410c7ec4def4e173b1e330f327e0f45fd9590945d09acfbce437b5735221fd46e281bc7cfccece12e41a974c98cdf4c588a88f4443436ccb407d3484a09
400	1	33	\\x1b5342901a37eedd0250f6a5fc3a6ad849d010460e5ab7a65758f247aaf532a28bf46b01a2ecbc1fe3b5831ee194a2f0490105d1603dc551efac265d71d55f0d
401	1	37	\\xd58d494442f2d28e36d0abbcff4529c0ab03abc8658c57b79a5b088b56666a5e7db2af4ea446227ae689a38f954ebb02ed3a481faeec761b162d4364dc88b90d
402	1	274	\\x84f5e6004aa5b15189969158f893ac3f5d57358c5671b3f39fc5ee0adc3d862dcf0457d4e15b181e5b16d8cbe8671130285c2971e008bf422ca388f0f44ca90e
403	1	67	\\xa07cb356784a6723464e6428357a791e3283129f5d746153fcad4982115c682ce23cb67c92bf2f5a9db5cf90e75d71f4cc0c16fc7e99a8a666c1f9b80820db0e
404	1	323	\\xcdcaaf8fa4ab636d4ca2559e610f1ac03d87bd31349160c1acc1b9d656bacd547fa706fd5c2d021275110c89271cd8ffe3d9961823d7d7808b1f780701bea809
405	1	26	\\x3637e877a9723d56ee23ffde48da1748b21ffb673d116b4963805c65993ed508065001f2f83107ea06ccea586e63b584ed80d96cbae1292aac54b27e2c97df05
406	1	96	\\xfe99dc60c6076ba307d2260b8b8b7b49983445445292ef5d039f78df508ba56d5da2d7cc9b86b0063731a3431bed70dbd4917036c82db7fdfebf6a1f7a0f9d06
407	1	407	\\x91a2deb850175cb5eae8a7a69f294a628e2d81c5db161e3cf986324bf3a45daeb3f3cc1ab04b3b6f58d9362a483d6c0fa801798d9c1cb5df756d285ca866cd07
408	1	286	\\x781b87b7976f30ab2a8df6bae04e1db36b9800d9fe626e4e0315bd90e89f3e99192111aaeb273c8e378e8943cdf00ce90af9f3ef425df17d6e8440833be17b0c
409	1	249	\\x281eeaec867fbf2a5416e721a9eb5231414624d9a05c56e36339c2c714982987ebfd5928e60b9601f85f2674b06102207f009e7400bd100aea4b9eadbcd0420c
410	1	198	\\x606bfe2d392485d97d7768af11df4e36d2c760c59ddc4840cf6e232752355fdde054d881de66cee9616163ec2f8b68e72fb4343ab1ac3c64febc4025aaf6ef0f
411	1	296	\\x0bb76139ec13649854ff3a65e0ac2571037c8a53ea3836d87894673f1a67b9222be8c5cc93212e95dc6939c2d2654398ae805f2205b15c8e8d8b60044efdd107
412	1	354	\\x1d7abc9db0b2830108f428aafb90b6b3830732eae39c82f8756c16c7ac51c3a175463097c90df84037150a19c5e0bed3c24419561af30e097eff7b9cfd5ae208
413	1	403	\\xb9e0489fbb6bff217a43371676d405c6e87227183f6c611a995f3d8263874d8f4b1f2a7be18fbc99b3900536bca2e4e1c3e3caf25847d3be9c4ca710fbd7b508
414	1	217	\\xea9c3a7b36d2d4113bc6e70b3f362c3d53f992b4e5c673aad199854e235c24a2a2e8b084869057aa3c13a84d8cd807819ab2ba58aa1e99f5b7d928e8150daa0c
415	1	59	\\x965209eb4226d8cd50cee684bf1f5f026cbf8f9b3656e67a6eae5d8de9054aa1075e6930dc0557f2dfd0692efd9067c60c92d31ea6b030666dfdc434af090900
416	1	114	\\xf7adbbf18e6f1b40113f89233552e63e2852e63fcd38619aa5c95b5d1955db861ed87c2efa8561480df9499c8b4eee0647c01f3bd84e1c3e519b747e2669c003
417	1	415	\\x5ac9a27fad7a822a0f3f09b6dc357c337c46a23828a02baabc6c0ac959d6cd23bdf6c4f66a03bf25207d533d08a5e38651cb0143fcd2e10e15a2f508c62f550e
418	1	295	\\x8fa7655aa71bbb530b1761e7d42b760271679cc0bd8852adcfcb1a2e142ac8f21d5391525ab1d1205c758bbe375c2ec370ce0ad5ae1322d7640b5f45e990d70e
419	1	19	\\x9265ad27fd6a128440561535442696dc65aa026857581698d1beff254b8ba6e5449ba2bfe234ad5a72c17d79d96f9e5a0a249f617d9a16f6d3d3dbcc6af1610b
420	1	226	\\x319b470611d9668e0d69def2d915809c3ca45afb80f2121b91c215535017cf543420d8040961b093ebdb4c9fd79b430870a2e23263d04d1c66f18b247bdd1201
421	1	186	\\x9cfe616bd94ef3932e9a54fcd9e7e316842b5ff29b844ea4ce5b6e4302db6210f8302e49f60b6b8ef5d817520f2b824cf8f6703b2ae0a61c4e0f17688e2be209
422	1	76	\\xfc8a032e7eb799269fa47654cfffe73e575b47e0033df65edae51833e1a9398e9d07159da826c7bc69eb5711ed0398ccf7ff7218819bc0b978bbf42d9d9d1e09
423	1	262	\\x08aed8e7d9b438c2a98240649fd557e592803a09753c36b35af9ece1af5c9dfaa2765a7c74858c9f507298d4086f5e59293dfaa6b3be7ce8831d0c0a21ca5507
424	1	171	\\x01b1264795cf65b69f107fde086a5e4e0fd6f0670cdc6431fdb92207fe69ae438e314a2c05ecf925ca45b6616f134bd9a0c3572c9f49c4ca36bb53719519d005
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x33e884c427fd6c1769dbdecd4b05e0179ee808de4dd1689be19ad79cef9e63c2	TESTKUDOS Auditor	http://localhost:8083/	t	1659817539000000
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
1	295	\\xec98bc5203f1e87d8d8c560ecf52f416a4d325981ac5304a08a847cc855b47513ffffc25b687db32a7fa5b63cb8b5c150fe94bac7c60fdd188d985d2b4746a0b
2	354	\\x17bee6d56c5f22b97a2f367f020de23c845b6af2821d43b692780617868b29acd025727cdab18b33a6c4acd4e788dd66bfedc25c36a8ac069ad094dc7105c700
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x01fcaf0992936fc03a0b93b181ada64f16ce899f119aaa827f10a6a8c94724267a9d987350e30cfe3bdffecfb28cecf0472298fa0b0d9ea5bc53220e2969aee7	1	0	\\x000000010000000000800003c91d7f3dffa660b8c39505c3629f5f8e85ef45c6c61a8e263d7bc0147e5c90db81615ea159034ba23f80a4b4f9e865346a06538348791cd959b41f0b75c44e8945e01403bd1a9d8a289459dbed65fd63f641719ddabe44bb0236e8fcb7f3a1d8f5e5b2226723dbd0bb7714f0a3dea0cf47f6101440895b0051a23f807fae5f8d010001	\\xfb2ae2ce6d42cb546706716eecce863e3c45a1b40d0935e051f89331fce4d66182392d6298f786ea6a07c2a7535ce5183417099f8e8f410374a32eca47155009	1680975033000000	1681579833000000	1744651833000000	1839259833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
2	\\x0178355699f9a19c41e5af5dcbb437f9d4b506285efe40f4c3aeaff014baf42d4f61cd98c8ede8098ec09947f18932c84da187f25141bbaf41e31d9ec35d8ae2	1	0	\\x000000010000000000800003bb972ee15a843db5275212686b7ec8fe0399c64ab48ad43c07c58f63d846ea334c3e7cfe8c29b329806e98890dd1614641d5982be4d1e1f34a1814187eb12ebec063760231b393603836c0d138c551f60114bd312ac02169013114c9bf193337a4b24cb3db1fb0b29ac5bd6a9944775252398f43e5869eb822c96424b25f1083010001	\\xddff6e8b7eb728a97da156ef01bc14774a37f18cb34fb43553ecd33f7ce72e1eb420b26b1a57451e6331312cc5bfa70a49eba0d4e5ba9e531a54b229e358de0b	1672512033000000	1673116833000000	1736188833000000	1830796833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x034c33f6d7f17e0d817e4f344aea67b1b23204f7b198300bdd292bc80fff568fa0825098c3f42c060ecfc4912b178d0fa1d9b361a67c7569dcfa3d9aa51ded3f	1	0	\\x000000010000000000800003bb7e946ed5805b415e0592ce1ca12897c141311e087a401863a61c96f65abe003d86ed10cde9bc6d9114ce432f9422be59d45a77fedcce451b432549014e4dbc98ac36fa3bbbcc352e802b176183f5972194aff5d890f5d297a5dceb9cd169b7a7526b27d62e6e224098342ee15556815fad3a65c4eba1c5499dd314cdc7e43b010001	\\xc1d89341bafbc78b48763ac22ddc1af9358ab0b682e5b75cfec399f5da3ddb2d6c4761bf0d9d48a6fee17c9e49c0209fc40178038bbbd9a43e24e4deac56d60d	1685811033000000	1686415833000000	1749487833000000	1844095833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
4	\\x0b38aabef812576a000f3d96e9f8b6e58b357a9624f2f2fcec77af12afb554c6810e7bae2dce8d93be16122daa4488f3168bccc24f32a0d041f9e21f8c1a03ff	1	0	\\x000000010000000000800003c331f4390237be06d3bd419ab0d2ddeda6a0dbaeef379a7f5a6a3d3f246a21a44482cfaf4a71bb9ae9940a5c5a4cea67dc3e18419fa52211f9f81c91c376a648bb0a5cc3bb2d8b3e43debc5a6a3cb50e4f1f9484e98a59de13bd29a6c1e6a2ff17f528d770e1983afa54b33472db720ee8711bc4325d172cbd352206750fd7f3010001	\\x7d05036ee55559cf58c2a54914429bf4a67364456cead79767b2934fc808f1581c908bb11b42e144c8c4c22f1134cbabb7ac2631d24cbae5442eebf335625309	1688229033000000	1688833833000000	1751905833000000	1846513833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
5	\\x141473f69b6162a657033eacbc5c2dcfb2061104010214d2dc3726fe99663f0495e381e469f74d4abbfe4b902d583ec6ade390129430ddda0545d9b380fe0dc7	1	0	\\x000000010000000000800003c1756a5d29714c9bcd40bf8a5affd0614da23c8bceb2f00b4986cd659bc56ab288483fbe4f86d1ca4209d1024bfbc4c25354f599a7ed4f507484beee746069e5a031e6105543e878e2a0f9f13f72a4313724a8ab0bda35c9325930d1e1bc8a02e94af6fb5f5af7e261b7c43d154973790a88b6b45622d584bfdd2152dcf7c7c7010001	\\x34859540f1c79be1d8c95d9de43a860594359f41af8051e0b89e5e799d65d10f7ca0b242e4828769727eb0cf972097a97edb262af2c0a9a741bf3523d9815505	1673721033000000	1674325833000000	1737397833000000	1832005833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x169cf9e3a7ab8fbc83a16e989eb19c0bab591b6d04bb2059ba98de209f150334f7d537e376430b9ba191716d4a5a21a16897b210a054551557c4f6e8e9b76b35	1	0	\\x0000000100000000008000039e85fb145ba5b38dc7e62a7d65c2c63b01fd4b486f44bc9bd1c8baba144fb9d96fdc986e979ccec495b1d44f0530989537996cf3ef1336318ed04c076270e98f7115bdfe1ed380ce45db156e7dee901c253b3887d3ad7709563cc387c886c7de4b1ac797b1502ef4bd56d92c50fc839a7371b8153feb4945e42ab9c5f6250f37010001	\\x8af0cb53b6afbfb69ff4921ff98bcda12e216e7bae430fedf5ddf8cb316ff7f556de68d388dc0b66c8606a34c5109b2429a5ecbe5d7e69a8c2dbc2269700450e	1689438033000000	1690042833000000	1753114833000000	1847722833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x172c5ad31e18d3642dc673c877130791dcc640f2eb640d00e6513ec865b7fddc9ba5ec54e173f0392701b1288eb18f58eff763aad482a4151c5b82e83ca02ab2	1	0	\\x000000010000000000800003c5da7595bc0837fb5560673cc24c28cfc93f5af60699a9a2e4495f75a943aeb9bb212d7bb97453208ebcdb33cb38d7afcf5e4fda7f8ed3e6d5ad00bdac03e2bc9cb3426c8e09b41c729f22f4cc70f57cc4eeecb7a450dad268d5b62b8778da0d08c0c60c4289f71d36962bd68a72524f3be40e27fe17dd3aaa89e5782b7c0ea1010001	\\xfba33d38eaed393cda6ed016b978e1f243cceaa2a8af548499581c9a757591d076deec8678e094bdfc99e295a35fa0e89f02ce2ecfd5729e6395e7c5a1beb203	1691251533000000	1691856333000000	1754928333000000	1849536333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
8	\\x1830844271bfe3ce8ad73a84e7601d3d05452a0ed7002902d396f4de6a9af87af9e29e09dbde167253df4496714e77508380ac04f7a6fbcfa296bcf4c734ef15	1	0	\\x000000010000000000800003b307b2fa6b3acb64050733be25d9d8faca571c3afcbdf54dfd562aa5f7e4bc0e96078b23d100572b3c3a230da3af98c9b1f1cc01efc10ab3335c2fc541d26b0eac2302af06746ca2152cf39d42e56df37cda82fcb84f8b28a5e39307088e912563a6430ea8f330ec705ba950d3e81e613e378aaa4a0072a9bf5a0926e7f36e27010001	\\xd8c50d1fb5d6fcaf04f8d19b8f298178b3c69f42d53f3678a52bd84c6b9c7393036ffdc87cb766126b61dfcc5add6059583f17effca70e992712f8ce85c60007	1683997533000000	1684602333000000	1747674333000000	1842282333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x18fcb7f5481c90cd0b9b5467ef2af38167d828054700682ef0903bf514e278e83905e1b72736d02218c9936f13151998704b9884160cdce2aa97f982a484941c	1	0	\\x000000010000000000800003bffd825cd3952dedd88b54bd3e78136b741cc2b8a041a9964adea2b3670e3e41dfd72a47b49adc76c5d09444705a8e5ef495905931e6fcb7dce54d95278411c3040d7abc9ddae70f548bdfe9d1e817524c93698d09087334cbaf0799deec54fe085f74e34285de4b276f7c29b82959d2d5f3cd17675ef9132c1570c63752807d010001	\\x92aa7b6d85151f8af9ff2bb96dcd3bb8aa1263e1a72d24b097ad60c2cf4d40ab71aa9c4ddcaf2f1070004109d283dd1fead784d37980c354deba9c3e463b6e07	1688229033000000	1688833833000000	1751905833000000	1846513833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x19788b7d743cbd4400771bbc7b2613497cf761b86a78fcd4df6fd9e743a97464aa53a2fcd47f0e95de39bfcdad6dd5ed5e9c5f079da30c3898bab9a2af2cd5f3	1	0	\\x000000010000000000800003bb048b919e05957bc2cd51b6a698b3e93bc52bd5906cd003e8a9db58a4a56d821f84131c6d72a599e9f51c7a8b16f5cffc9d0730338884df4e357aeb35a5772038a1bfbc9721b0aa065d29c21635233d89f0d58148ec1e0393348f41c33a97601979076244d7ef7de659315dc5dfdc2a98eb4da263c9112549dc0df65448dba7010001	\\x01dcbdd7a7626a4f35a290fb1353357ce3fabc2f6900707c065d94beb4b774709516f25b9e0bea223919f7bd99df8ac70f5044d60a87090d6634c4c63b6d2502	1682184033000000	1682788833000000	1745860833000000	1840468833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x1bb8f6e5998f5a5c09231f10f40f2f43018e3f32cd12f1b67c421a65fe57a6818ad65905a6a253fd36060d8dbee65648837ee4c221d6ee0c2c3ce287068c95c8	1	0	\\x000000010000000000800003b5e28883f2fe31d791ca79ebc5974b5c8c72aa3f9dfa16cbddfa10e744c46b4b2665d679520fd0c9f0b5f03feed88cd75e1737e8fe5ef0e0caa3226dfe2ce83975e297c167062d555fd15900b7d9592d13d3fad775208ee23a8f3788b35267239d98996a9e019915bc54b53259c78c0e02b12c004a1e7ce4587072da99ac5835010001	\\xd3a476bb33fd5c55bda239489c0eb0d2e163942ed272e577949bb283b8b1239c03258e42b2ece40aeb77482011704e98da4e34f5185f27114ef7786123a05707	1683393033000000	1683997833000000	1747069833000000	1841677833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x1dacd97783f482c2a341ad07329bd2a3583909a31b108f8462a8abf537920ebd051e1b9db3ee4bc3b5c4106416683a2b00f8aaf60e82ede39226418194874630	1	0	\\x000000010000000000800003f02f03b500a5bdc068ae5d3554862d21f242628df876dcea32cadb3106edf39a71b4f603fc0f4837341dd34cd1538b5e21d6ece70054c227398220953c2fce2bdc6fe502355e7075c6f05c7b44c1974981637a049af53d9ecc7cc9e9ea26fccdae17c10edc0520839f8ca463e4b7eefc0288be5914797a4607686f82719efc55010001	\\xaaa04a943f34faa0a54625437de0d34bb875626676f152c8c966f315ac2467854caa0a9d139bc7cddb996fabca26b48e7392ca7f2d3ce2b0ea49af8b3d7c3c09	1679766033000000	1680370833000000	1743442833000000	1838050833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
13	\\x1f8c993194dddb2c4227af3b96c14dcebefb3adca937001ed7a9020d3473419a61af76d70bdcc44a0829a447317567329349ed039fbd14c41fe6f674b2afe0a3	1	0	\\x000000010000000000800003b9d86a1739bfdc584f4a18a2d5e64ff798aa1760283b2131df2731a211ebb29aad9a1076fbf0d652e2c885999672a9ec2100d9e89fb84734ea7b1230014ba12e74f9b06c3fbe0bfdf4ccbc37101602759aedee4d09069ba82b44192672cb370066402a7cd6435a21c35351cfd06465f476b3063263ddf1d32aa58a4773d61237010001	\\x2b5931647de308b57c0e866fc944b530a35a0dfe769b00b562cb64b26d77eb25615ec6c515a1779e690826c0d9b5b457374db89fb4344d3a0c5da5359e5f930d	1686415533000000	1687020333000000	1750092333000000	1844700333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x231813683788b7d532257f749cb90e8e66890c694ce95d55e15dcfa08dd59ce6ada4a3e066f825c20dd089ff8cbcb9a61191d0b1bd8b154ad4ab34912362a8ed	1	0	\\x000000010000000000800003bd55e378b4ddd8acb3ec16cbeffa20514f5b839007e0f6d5c34b27b66906e31f0761b4e6f05b5017f0740ce4ebae96c3ba8942e28008bd8285d9d140b2f08741a19ff5e1f97883336589df19217995bff453742fdcf09012b7da733019df6960b2ae2a2342c14d553d13bca0d2d505d7b29c0a7c8b6df4570807119caed828b7010001	\\x5878e8a7d67d476a99c9b8dc2460abbbdb42a22919cd95b5811fbd959aadb74988124c8606efa588b5c10211ff77662a33ad266ea45b617a62eda03a5fe60c02	1677952533000000	1678557333000000	1741629333000000	1836237333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
15	\\x2784c45564522a87d2ca1ccd3f48b29a64fada605c5c8c3cab11361433ec7c44f0aa688945e52d971ec1d60cfd208bf540e30dc3597e6677e0b343ac1ee28d34	1	0	\\x000000010000000000800003b8dece06c76dc3f5a12a7b45c41ca466674d51f4cbb13ce9f308e3b3abb8ebb77ecd9dbba516dd1be3465614b8bdf1eb883a4120ba7dbb130eff4cc0f05a0bf4915f23a3914ae2662057170c7e93b764d1af0597cfb4fdd8d1c7416e0a796a4d6e5885a4b5889d3603f54132fb730e1ccef7f32e9deef572077d319f314ebb7b010001	\\xe15d384507f08a3d0f0d62be296500fdc0a553a157600d79fe3aac3e9eeee338dcdc4792e8c056a97ad42f918fb623b4f5587041293c324768202457d23d4009	1690042533000000	1690647333000000	1753719333000000	1848327333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x282c17842df06bcde91a14351e44a1d7a3bfb64f837e902b1e36742fc0b9431e170ae440cee32e5fccc2517e4c671d9f19a3460091c2d7debbec617857614c4f	1	0	\\x000000010000000000800003b3b26c2ad01ac052ddf4f0d9a8ae685bfc40af446a88dc595bd1ef97b2e0b738233f83250b0c6169c39c179f156f0a819d30d776de4d7b93ba1d617b0ac9e39ee3e2b3bde9bdf40d7d5ffe9214f6c33a097c6eb9dafeebe7f58affa1a3d6abc80624113f2b4f1c89e1b550482f7f9509383b5ca50c2a4bbc1ce2285595fd1f39010001	\\x2bbb6ba04fbc83b88efaf9fe07315d27e2f241bddb06080c3d942fd0303b116dcb8561f64ddf0971477d35624a4f0bc371177e5a2c2c59a6d30d73eb6a9e6700	1675534533000000	1676139333000000	1739211333000000	1833819333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x28208f961dda0002b25da8695d8f34b80e46892cf995e2ecc8cab3bcc133f3d255137b66b9bb2a7456a1b28fd060e60e2ed250330959187ca9dad4c3e686eeff	1	0	\\x000000010000000000800003bda49bc848da62242b98b70cf4e81f5227344637dd4718f2f0fafb6fe5584f1655e19895c95e4f4c395b214dec398cd13fd350725d32c91729007fdf5852e092d2a05c9e36e5f2e81a9e901fa708b67516679b770ed05ed8b76e3ed2334b2e77f84b8de684c04e3acc0e1b7ae8a988b863a985919d81e19b6479282bfc39041b010001	\\x037c1e373cc39d0739a302730e13002c261c145e7e6207bf23dae6a233e78dc649e37d4f7df7039ba1f392f49b0c03e5369fe4f8522bbadb0bbfe481da7a3706	1672512033000000	1673116833000000	1736188833000000	1830796833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
18	\\x2920a8e3d797d219c20a8804b3ea76c760e64c9c8b9be9e31b15f3f4ef525e49b165bf097d26ae42fa79586beb919a94273d824135983fd944cf3efe5f06c8ff	1	0	\\x000000010000000000800003a4d0efd47a5047541f9159737116e5b6542368debca6104717076af9e5ae74c956a31e88d08db6249f0c7da1f33215f61df742daec601c83bcc3c63f9b89ecde28802195bca5abe6685c8c0919eb93d50cf1b8ab1b8c14327cdd31ebee59470b44f3968a5cd99ff361265126f2ba53541ceec9aa75782da232bc17df887372a5010001	\\x90753fd7ce37233b37ff914c4916d6e454d75b50b03af2142a25e69d15ff3f4c6571bcdc3afdfec339c020897557a59a0f9fd1090f2fe0f2df78cb0113f49901	1674325533000000	1674930333000000	1738002333000000	1832610333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x2a2089447b3fb8e00dd5eb2c92d48b6451c02924db1be8bca77222a0ed53f0c43848f7cf70e2aebc989cc086a787f544961c32be2d9686d62cb82e1a44cdcfc7	1	0	\\x000000010000000000800003a78d70d00e5a43ae24be5b94b91778877d569b46370941a10f6a6a8df999cab60f9e34673c33c0544775dad2ba948df9e8741caf8d62080d21eabed2fc389c3dc8d04f9303fe792af173b5715f95842f3480ce34d97820d7eadf1fcf12192c57b6d580cd755f850a1725f02b4ea0e69ce4119d8af95fe65ee3d96287a00952ff010001	\\x7871404af42c8bdb8e055f39527b5cd547ace73ddce56f11cedc8e45a915d04c6680b42027987a0459ca01a4ef256f51e1ebab659b35c5b03504dcec10bf2009	1659817533000000	1660422333000000	1723494333000000	1818102333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x2e540114b53da7cdac5476595d2c7d275b7ceae834dbc1b160de49fd4484ff4e2cd62f106ac1b14ecf52b8a62c3fe590bef1fad736a676717fc6672c61d0046c	1	0	\\x000000010000000000800003ccedb348d92e526eeb85d8bc224b723c3107c872f73b772645e5461ced05492457b4ab5473f75d961ed108fc36c5588d500fee42bec95f442755dadb7c2562c3dc46c473e946fa46a365d63a88d98f8a8f465f80ecb4c4690a6a54d1e0193afc31709dec44a10bdf3e6ab59dbcebb170c13a511d57e0b4d4f36d24f300685c2f010001	\\x2322708656e51a946b997496b4ab5f7eab4d91f67d50dcaa5f7dc207b6b62ac6b4510f9e8119392d88ff6763006751b98580eeae78f020737e2013a6c642d806	1686415533000000	1687020333000000	1750092333000000	1844700333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
21	\\x31345a404393fdd137745b43ada8a85f2ae01a94011381e0602999e35a49d9f922e172055fe819244d5840bbc7fca4fafda467e1311d1d6d62db8bfcf1054105	1	0	\\x000000010000000000800003c61358162fa98974c13af8e1495baeb12e866a70a1e1c0b8237db11b5e94564028a52a75f6228579e7e92c7ae9322f49a4dd8caebbd3fd53a6b4ec02a1c111d4db2a77b1cdcb39ac69d6c5168e400b026987c17342c4be037dd5da4c670793322124bb46db3e958cabf89f79532b34a8b67e2a67caa14cadac58c34930790f1f010001	\\x12ea70c359c39714cd994bb9a88258ebc6390ab420ed7f6a42b0d90dcac9a49e4122ad332052fb8f2b0df5918de183da7f3fd34509d233045c22d49c37f42e05	1677952533000000	1678557333000000	1741629333000000	1836237333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
22	\\x31fcb56ec7a95543daf64c12a242f0d4a922f686605b078151eedac34de6d86d9015ce6c2682e42c689ce96e38bd9b3ddbd789e9ad7fc95d47b540c8a893acc4	1	0	\\x000000010000000000800003f22b0452b989b83cdfaf9cc438792108290af39cbd54741693b6fdc17fab0d3feedd6ee644717bb83f65e0479623a79f4af3a820bff751ccf22abbfa3baf63623aafecd86a85808a3a2e404d5a3e0c8d9c7ad4f13ace42433e7a335380bf5f059e290b1bd48a7f1f5555a3f1b323342bbf3f21dce54ae472b6d07fead7defa93010001	\\xc0b889cbd751c59bd24d69b598c233522d34462dcd4d787c318179f19dbcb68ff579bdc461745fac99a7cff2c6ad0502976a412f702d1548353fb999ec9df30e	1667676033000000	1668280833000000	1731352833000000	1825960833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
23	\\x338c185f96e7f672f79657b3717de7a7738b67770712187b742ea56b7f1fd6cbf0a948429f8b39c9249e9a4737fd59ed63a8a556d3ede50e1589932a85c7bc00	1	0	\\x000000010000000000800003af8fef553bfd833475ef0e94739b953dfe6d8b187d737f2690bf3ccec6136328b2084449ae19a4145b11125870afaa2f8164748a4b8e4754824487046e58b595c8ebd445ea717068b6ef6b640d3ffb0dd0c48dcc2d6f2f5a8768bf341f0951945d0e3cfc57b55faf3c4a400893715e78d9064662ad6a56fdad2c8a852079b559010001	\\xdd57f399f9a44e5e2ed7b0697c5ff1e9d9bbc61997d228d6f1a9dc5560780ffd0057e9b32953e6e1c367e5caa5809b8341db15b9040bd262d3fe2b344a965804	1667676033000000	1668280833000000	1731352833000000	1825960833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x363c70ff1aa525fd3aa4f1585731d35d01faa10e6a4bf5f2ac43c138a7caba971330ed916970e5df53b892a1a6c7e08ba95407cdbc5b28f3780662a9cf497e43	1	0	\\x000000010000000000800003c0342a4c0af6febf457de6519f78a3fc0046df5519797bba63c64a7d325f7c2304e49d5d941481221df590ed01218c2373acca2526feccc8f0efa53c815d123145f8e514929edd067a9ec109f56aa89cd9bf39ac360a34a283b11c83a50dc3bf33f412ad0ef959477bee91f2e16db796d007e199a734655de90eed1306b42193010001	\\xbd1c8e2396e772c3c408b6dfc3d694add8143a3b55edc8d84fc9daf01f92d5e3807488a35a51bfb26fb434d2a46c72a82f3d432f34e5d58f6f889dd64a65150d	1690647033000000	1691251833000000	1754323833000000	1848931833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
25	\\x3a043896bfd0829b49ba85afba49814e11f7efe5c25c642cf22c7ef62fadbde5eefd1517d7f04b2fa8377c49eafe8a0dad15f3db68be2f9e1af95644539980a1	1	0	\\x000000010000000000800003c966383ca1e6b62ed4039adf87cd34d4606f3cd589f4b2e441c30600825e205bc7a8944b008835069291eca7aaf5e589750dffca024505afa645d7c1989b747b8be7bfca2680283b923007c43ae774e889470e6a5f0d843971acb8835d928c22f5c9c6631f7e777ff95bb809623cb569694c56e59b21792e0830773fa8d8c2a7010001	\\x949604e8e8828caf6b3397739e039729d211afd953f9935e267eccab92c44aee761af660df5aa00e8b7312de7ba6a9ebe54bd40e86fa20b1461c467e89468c0e	1674930033000000	1675534833000000	1738606833000000	1833214833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
26	\\x41ec7c79f7c7e2d600ea5395f21fa22b8d91ce6aab7131b96aefdeef89d72f338a961f6202a53b68257dc7942975b442259b19c5637e38e15e2b563b6151be95	1	0	\\x000000010000000000800003cb6c37bbd70d846efe37d311fa0f6cd923841cf49b67f0dacc8ca765c55ba440cd95e0a0e8c56758f0e7ed628a2219398c6372a51d7f2ae61b91420567163c40b1cf8393e4d7207623304f4c78e12348ef1b84cfceee5db761ed9467c8a1c0211f4169f88c844239dcff0051e1bb8b8477e56359d8a08f20b332c9d47110e65d010001	\\xe781da15bd4c10cc43853fb262a83ee0e9fd5dbd6766cc4cad809904a86085100eefafb95deaac71904cac367b2dd088e6228e9c6f73631e79abdcb9d931ca02	1661026533000000	1661631333000000	1724703333000000	1819311333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x42cc3e6a942bf243143cc2ed2340a028b9e91dd62a1b8033f8f4254c0a049f29a5a4d0cd2c6352a9dabdd2da07746e7ecd69022b9b21194e2a982b8c6cac0954	1	0	\\x000000010000000000800003de44716e0d80254f4c7c8c4e9a0d534ef4343961ef5bb37e4d99861f4ee3173faed68c60c734e7e718d966821cd4a47c48634bafa8856362acd06ca55dcbccb6227bc0cf74ee1968e4510104c4304856c56ad27da91b96011b094117933010a326b322600d8e1eb66e5e11e91d0259c0ec3d88bcf370d24793c1df657d6a01b5010001	\\xac6225af53d9c25f96180d455950127001f72248eb2832973c43401d29cd9890acc1b565dda248d8b0713e688294ea27434401005727d0136062554f541dfd0f	1664049033000000	1664653833000000	1727725833000000	1822333833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x465c57b49dfad3eca4db3136c634140f386abbbfd9450bf639facbf4a1da93a89534106e780d9684e426e9b6b13c1c36e2dfcd4f0e36cb4dac989aa108047f57	1	0	\\x000000010000000000800003c228c46379affc6a67fc88d10a5c6ea73ca50e58a34b9b62614d7869a715b4b11993518061190834921664c6cba4a082d49775e3f9c33fec355438b8650d1cdf611e4a343866c61a5efe3970cbd1bfd4c777d0d4b491f6cd84ee1cef41e103495495e7ab34c911a315ec6ba4201ef1afc9628181312b2194059e10ba0a05cbd7010001	\\x3652aae0bddc5f8c84c0214df51cd21ca695d11fb88d28b5bcf2245ce4a49cbed89fd10eca7002d874ad745c7914d17a7b36488416a0a2efb8efcc418911ab0b	1662840033000000	1663444833000000	1726516833000000	1821124833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
29	\\x4748c1d511880c3d910dd72b4f75d4932cd88aa78c8a66791e05b223910d9639f930a37cc49a7e2b022cf3d38e8fc45d7bd447d3ea0aa6387d272af9a57a8b6f	1	0	\\x000000010000000000800003da89e1eedd3551b439c293e8fe36e2fed14c9ebb828c8aa6e04d49c8dc221be17e6d125613f70fbb264b7ea6e0d68c7b02e0fae71cf5eee21b33323b7be4774f756627646c4dc29fd043eebb556926bca2ff6c095dd3b644c88d0d906715911ec5c4a1a70ae5c9fb210151aef52df8588c4a4861d4e06ea7218f48d0f2b0fb1f010001	\\x05f3470d3a9f1219c5424bebba8579d20e3941016912feb2f8aa73d85d3175b2ec349e58c3a8c78ea70150a6ae80ac8ca794e0b3aa3d68a920db04af18979f0d	1687020033000000	1687624833000000	1750696833000000	1845304833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x49842b009ef0479ebe98b0a2553b9f3b9267184496f1ba55f03334fc9b14ef9fe27447e211d3f4c2caaa69af8426020b5753d907277e25cf6b0150e1cfe96539	1	0	\\x0000000100000000008000039ea6dc998ee8496f64f866923ee56eb6a61f745544c84487d9f03a8852737054d8a30f8464f5d2464a870a58df6d93bfdb588a28c84f07cec06123e8a6cb28b3b4d206cc21ff6e4cf0d1343ee4aec634e8ee48e514f333a39ab7cc38593732c495e6fca7044dbda79c0af9f0ad35d7717385d30a5e92c701a9829fea0b830055010001	\\xaa0e4f85058018a1f08f1d3d18f98163e35fd4a8839b987d703b4580274907be9b309bc8ecd7c75f4f6cd597918478a02b9962bdd36ff44d3b3062b81922d405	1680975033000000	1681579833000000	1744651833000000	1839259833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x4a1c77b5a036806dc38c8c6a3bc35a76b10493721c8ed03025f2a95fce3ddda3cf069fe8a7032977a4532b5e975dcfd1795998da02dd32b6d64a2904e29aea19	1	0	\\x000000010000000000800003cafb8290d64bf59b1e00a261d0ddf18f386fd3d5510e991256c245b939b5b9514880a8a1a7a4bccfaf87365517947c350970c2c595d98acaa40da866b31a4c235b4aedc634ab7595668816b96390c2a2b35445ede7332a56c1b222d1b5ae9d1f53bc603da671a1704eedd34d699e5bc0f7d737b4370d40f26343ee3d8dffc347010001	\\xc8a8ed206a68525b84b6d7f07d5f8500e8ed1aa5f86c167fdf1908e415195cb6d95a31ed3540a0a682ccc7f71f836f2f9352ef6fd551ee9fb5c13644836a2409	1679161533000000	1679766333000000	1742838333000000	1837446333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x4ed4025fdd36ed7b463aa01e15b30f0dae4ea00aec84ee5051906c348730223b2bddd8cf5e6e371adf157c1617ccc06bdb230efba8955185758a408233612138	1	0	\\x000000010000000000800003bd10a6c238b8401a6db8d89154290be6ddda2ba22adbb57b4bf658851d1dec902c421314cc318ee5c1b26b9f342a43ba2dcbcae2db668eee2eb082cd8ea2b30c8304d93a21c861f0a019a82c5e90625b0df2fe509e876ffcae9ef50078885a4e7bfc2429d1b3434b1015869054d11f04911b68e99fa9d3782271087150691cd7010001	\\xb65f9bb98bacc017b48864f88e75cf12883ca030720a67e1ec11e19e139f435dbd1774754517bf13a3b40b29dcf0f8b0271a6e7695c1f9bd05c34554cf583e03	1679766033000000	1680370833000000	1743442833000000	1838050833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x4fcc6377987a91fe492b2c663aa5f68b29be0b6cb9695210b7e9fd97317e2bf4bbb67fba94dee20720b4ca984ef6026d22a9fc66996b1ef118dded65f78b9e41	1	0	\\x000000010000000000800003b8f9e1cfa2af007587ea708377b3d7c5c283eac3cc8a87e9aa6b556b8107b87f5ee54736c3054902342f2d557c08c15e16b0cbb526a7e44f704a8195464d0792c7c41fbec46178b623f389dfe83566b9ca30d6d9a8223ecffeb0858829d835f91175a11c8488a4fd1f8a86a33f6df56a65eac92ac030fb095128e5ab472ae573010001	\\xc169c5682bb78f089847b2b94e6d8d23c65de74a67890fdfca9c5aa5e9572730a2ee58d172f04f9db0e36003aa394e50d762dc7078690a8b4ec962103ad3c30d	1661631033000000	1662235833000000	1725307833000000	1819915833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
34	\\x50542a77aac7d3d6d835da224e37c4e36692819d79ddb0bcb240b4cdbafa93bdcc253ef4ef34f3566cf8871bd63e537a7fd5746800a55d33c61fab02b48980d7	1	0	\\x000000010000000000800003cfae93c319526dd20623e86bcb2f08c3d3fc6bd47bc326e28f85b99cda9703ae2ce770b7af0e1d1d5dee0850e817dc26b2187953a0e93648f7245b883a525b9a8791dbd7b0e9ce0ff7e2a61e18a853707b03c85cd221db4c20eef921ba60af445b8cbac625b532ad3b54a785cdb14ae0dd9f2eaf880ee5384ae54d0263b87995010001	\\x8c926506ce842a9100942f185d23b7cbc370eac640d09dd34439c6987acac083f8a227476e8604f2c200dc966d1ed4c73ca0c933e362a5b74af7d96667bc2308	1673116533000000	1673721333000000	1736793333000000	1831401333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
35	\\x519c84c99e42b2d8898ed412768efb388ed02dd777a5823166b560b2c673a3984e7c79e9c654d12121e6f89f215851577919f70c66c03c20346a3a5fc9e6728d	1	0	\\x000000010000000000800003b4c1c163a200e9e98aa4ce83df8ae27575259762288155dcd3a31c77c88fed69f99f327f58e4408c8aa2ca0f61fde094f71979c7f86e103575706dd9e9861b1f44684b077529afd9f3e17f50598b71be1f8348c7347fd4931b42a0503d851a8460d7af5ec3f64c625908ab642f07c8ae4e0724ccc8312662dcfc05c9d1c78e51010001	\\x72d1c435cc9d81815693c238ccd0513036b49351ee82f940229affa24af6e79a24fed42a8569ec2319315acfe0cb64e7de778a7cf8565b91454620ee623c5b00	1690042533000000	1690647333000000	1753719333000000	1848327333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
36	\\x52bc8de5783075df60b6d91b25fec3dd02f02807adc4e76dc65d1c63a8ab058541de30ad0e5d5250402b9e85f9c09e14864b35a01b26f9051a0160fdbd8a8ea1	1	0	\\x000000010000000000800003a36a61ca22b5124b6f13dc215fd6b1da06edb3e4e575e97d9eac009602bc92dacb8ad5d981fa720dbddb8ed9240de92cdd727cb6205c4ed5473b43dff5c1de73a41a233ae563e3a59c39983a0d9e21c748dc5d592513a0b223ca86e0ac593961e8b21006a8d049a314d49d549b9ec493282c3e9a31cb4a12462253309f45a089010001	\\x9e672d1763287121b4f305f63343ec1ca34cb8a03df6b0504443a7e926477ff40da8ec9cff4df19b360026c2c55a718925fcf4c589f70c9a35d53e611d28040c	1682788533000000	1683393333000000	1746465333000000	1841073333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x540882d39a80ebef8d595148ff78d1f8a5dd004e42305d332281f9e621ffa1efef2d194ddf366131afe961353786a5c582b2a8825427fc7eb0ba87bbc996a574	1	0	\\x000000010000000000800003d77533bea070e881a38176a0a816fdaddd872e8f1e4e665c1159f5300feea0a7f14b2aa2e8c3ed442e69b7f573e294dff51538fb8b4d84aba8aa8ebd46bb47eeb1992104e86f6eefb9af727daad695eb6f12ccb532e1b886bbc029eebb813d5e0e87ea1882c1c0aeaa133040ac216fe7c8fd8f794b5d4ae5b472067564f348b9010001	\\xe22a2f2b02ab25592551c1d92a454212081ad9aacf290aca8e911251717eb988ff562bb2be32ea1d1533d9905f110e721b38fe34d58f2e3b4431524c9f7a6e0c	1661026533000000	1661631333000000	1724703333000000	1819311333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x55f0ae6a36ab350a372aafa751ebfd14ffcb49ebd16c03e8878697013d4ceacc516acafdafeeade214d6ac68233c21c08d6e8e818696cac2741c3944b0d93ea9	1	0	\\x000000010000000000800003a0370b083f7c9bb85e245770ab6c75e84b9c69f87cd136401ef5a4095944dc3fcb26ac2dfee40e6102c8cbabb1d70db301a8b4405304519562444cce8eeec6f6120eb5c9c74300b1918e9c7494f971db5ae5dc0f651d4c25f4cb4485377bbc97adea72d8194e5b063d1b8959f6cc4f62665669adabb2960b8e81939f2ef61193010001	\\xdd6550e76b6ee3bda5740aae59a2418001e0b266f2e912c116804fb81364941758ef8b0420458f05f642dcd0b74bb587332f82f325b8e3ecb5b8f98e62ef8001	1676139033000000	1676743833000000	1739815833000000	1834423833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
39	\\x571cbe72efe34d42f0064a7b09c1ebb39e6a2b403e0757be41262fd89953d4b74518979f0e541c361c9f1c9159bc020ed22c5dd6e1ff32d13a73be2654b34b74	1	0	\\x000000010000000000800003b7e0cf9e86f5faf9bc3a6dbeb875677fcdddba35f88548df4e39a644d8e865443e408321ae74b8a943011c1c73cd0704e1fb1892a8563f982daf7683fbc6e2ae4505515cb7a57d7aa7d3df972a7943b617ab39d56ec1f1ee12c3f8578fed6fe361a080904351320d667677f999dad84bdad6e31fe04855e010daf394aab3ead5010001	\\xa2bd99a099944b2bdb11a740f09758f9bae2d58361773143aa43cf67d709954842cfbcdaf1d7f0b430e815cf92fa4d0bcf2218cccd351b2ee0fc6ba6b5ed9c02	1672512033000000	1673116833000000	1736188833000000	1830796833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
40	\\x599c1c402ae3fddcbbad1c30053eaff852cf91770c9efcc0cb90d0c0f608f680a8f42859df25a4487fb37a31eb3ba0875488b5a09fc81d95ee31af06d7cb8af7	1	0	\\x000000010000000000800003af4570bcd786650183145686ac24707a0e181fa49d53c35647baa98181d12fda528ef35a6f035a67153f9198d39351b10b86a7fb0453c61d0ad15fee316f2c1638eb9414f3994a81c3e7fb4d5617e02eb5d8341ede25e33b3da5e778f976a48f1e8c6a4a50de2acc80e2f7a44668541ef2600dd3ac045c238a20f4a5e5422a05010001	\\x6aaa4942c2562b2661148a1d75c6b78c81b3a22debbc2d1baed2e794816e517902108f457ae75801f399cbf683a766f511cd44fcddf4272056e6ebce05235301	1671303033000000	1671907833000000	1734979833000000	1829587833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
41	\\x5d00b6714971f1565056d0ef0760ab3de540b1ee815da01b5e17b78855e98c00c5689549a294e02e30f0719f5565d778f8a3d43782b854fe9d487c234144f87e	1	0	\\x000000010000000000800003dc967b6d29025a3c60e46cd0d382c769981197498afb05bc99651344061336a4ba3f28ea53634f8a11cf6e2255d20b64c234db0a7c905cf0819612e906d1c9b9553bbc9f519662032635ae91dbfa840e8c3a824ded5c9db03a88195d2ffeb04b74481899846fb8bfc920af75ec12f13dc7974e3e57cfc6331ac6efba57044d7f010001	\\x951c8d5b29458b7d98d4b1bf012ee4b62e84b6f3007f7ed24e56167d05d7437287c3f64cbd686550392dab0c68b32ec3a3b3a0c0f2682b595584f441c3fd9602	1690042533000000	1690647333000000	1753719333000000	1848327333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x5da8de6f7f462728af6b858395d40ca3b8af95777c89eb438ab24ae7920f4b18fd6597aa2990ca5743e8cf5d8f7ed5a130a765859222802f5bbf312154519f56	1	0	\\x000000010000000000800003b2352919fdcc07a467e95dc12f01b6694d3e317930d12eda9b5d4928bc9401c722128cad7838f90dfaf0e8077473588786136a4b2a06caeeaa33638b43c36f96051c5464dfe9135602233951ade95468e1e2b3e2a5c7ae1355236e917c1ead2fd2b7dbca1b3f89f04bbd2dee1276db42d4e5440467fe61347e491bdd39fd08e9010001	\\x1064e21a49711510c10bea2d20886bdce3fd2abe7290987abfa5ef251d60cc046c9ac1546d4ebb03ea382a190c3f764499f711c6161eddad4fc85b238ed12e00	1664049033000000	1664653833000000	1727725833000000	1822333833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x628cd3e18badcba0bd01618f7d4a0447fa32317609d319790c27ba59d0346317c56be99f1136ee01255fbe316455adb5aa857f63584d15e2dae023b344a69bb6	1	0	\\x000000010000000000800003a18aa743316496f5725fb47000c377833b36c6456943bd0e271eef54ae16c84af32ff93342d85ed6dfc1a0ca649e244639426a13b074f77d41423d64a58fb5a21dc347061f5bcd8642370a30eb27eb6a8deab2a71fbe41f62285ee42cda20b56b461d9b9d6481b43fbf4f19259615361b595202a20430f08a948640043248147010001	\\xca8b01c72e866f38812e63ab0261f3aaebd9c4d889fe474b534c630d842fac0090964ad50518323c5a0f23d30f0e67ff50b5096464e56b6d638fce4c9b5fe806	1688229033000000	1688833833000000	1751905833000000	1846513833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x6400d3beebe2942011e54b3d95cdba32d7c2a0bc40b7ff0c7f05f314e0fa8ad8d352ab9b7b493d8dc521bcb8fec2b789a4b8fc6dadfd1923bfcb4eb1ab03f5be	1	0	\\x0000000100000000008000039eb82c14f47a551ce1cec895f814630f2d61cf46df973bc6e098248b43b91b75fc23d8a0d82e2ed7f5188d12ea6e390f34b55b6e057b103d50720c2eef2692697fbe5111b1d5b1a8d391cb39a0a4af86f551cff35f6a48dd6c09ac3ce2500c507d6dc8f16bd82b0a5be8ee4f1fc2fbff613e15c25f88c449f403aae0ceba6a95010001	\\xc8163e3cff024059b9837278db9af82653dd88cc0d497d39206bd8fd56ba17e644c49a79ac5f87b31021c8495ddd51b989c1b6583f55bf8c1b32435c2ad5010c	1686415533000000	1687020333000000	1750092333000000	1844700333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x65e0b6e4ab55d72180d4dd8cc1628f6b6a73e1f97ac88b5fa323496a2aec8a70bc50589855ff85cbe6adbc8f92349c717cc9f081d021954f1e58a93306a80e2e	1	0	\\x000000010000000000800003c0b7e92d8f01f01cc06f413496db699e509519208448cdf5f90c4a214ead4d65dd31ed47ea26c95ae1de48a1ec262b87ec6de04fa95e61b11e85b1d2505150bbefc77549898286631a3dc7340873088ffc759d2b2888815dc668d5465de01f90e0f25c3b0136025efa8c8e07066f8384a09290ce843b829d014e64a3fadd4ed9010001	\\xf4198737c433672d368a5e56925c5dbcc0e88a180d3b1a7ac90a52eb34d4783abf8657aa4ef9cfdbe20cf553b1b13ca97e9d7206691b6336f07ba67bb4cf890b	1667071533000000	1667676333000000	1730748333000000	1825356333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x6c9c98467ab821f3ab2646256fd1f5c1762be2a4aee919d28feebc6ec4828bfe097dbc0356a79c7153147f7606b31c33ee18df71bd60659a2684733a10885d8a	1	0	\\x000000010000000000800003dbdb1025fab0f718cf2eb8cf89e96b308c6c4c7b145df96142560354d964262721e0bca468bfb2619659e7dea0894292875687e63790195c9e02c6b35c42d6072da983b50d9e67793c1b4208fd47cc5da36f5aff98b2818aca8b82f0f007f3d9de6d863f873c9cc5adcd1926c7f7f72bdb55225cfac88d12facdc119d084dd69010001	\\x8c4a0fbb19bbaa05edec37e1c8b0d34b642293c739fffba5cb4313369d7291b819960b1684befe964cd732de15913906412831e437118ddfc3bf24baf3b78a00	1688833533000000	1689438333000000	1752510333000000	1847118333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x70588c661362e553908c3c8ad30e4c9b127b22fc0a11ab633705e2cefbc1b51eba8c42f1470249a3d0b93ba73c57636f8fdddc190a0514c2b5f7219b64f996de	1	0	\\x000000010000000000800003ced35466884739ecffa57dc9666edbfedbb8b3eef30992d5d964ed9ecf084d492de6950c4b293cd546615088430549ef7131bea07acfec4dde470acb06a647519ff5b19b28c07251c8f8edd0c391630462b0498ac8aeb01b421869a022a627d6e68c36f3ceb4e23b5499cbcea5cea18b2ca899eef90a9e0d4ad22f97cf2d7a17010001	\\xad6d64cef57eee3d0a70da26a692390df24148b26522dd19200503512dc6ee0f7c2eddd106355eece67e19a481f46cf6093649656d2f86cf94f011d98567b80d	1661631033000000	1662235833000000	1725307833000000	1819915833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x73e09bb65728263fe9651df8b8994b856f30c8ad97e15c05bf29370fc28b5068180f2728f1d01c683d123b0cb22792d103ef687d9d30f025ecb93e05c46479e1	1	0	\\x000000010000000000800003bf000134a3db543957be0d67020edff6a9c72b185a6561620297a4b3879a5310a884181fefed9d3b6015cdf3b928351c9b4a156f9d04c09025ac168e0ca7f3118575c12da44ec0223bf8dc9ca99edf6bfe66bcf77f8ff3cf6343f827247a7fcfd5bd767d7ac9da06615790979286d2659606547128d9ad922faa90e26d0929dd010001	\\x600e62b6a59ed6f1513d33f2a89a886ef88671d3f5248773950c6d0c52c928a2b0c248a7a0af837f7515c5fd3dde384756626270d7c1eee3bc75e06cb5816b07	1670094033000000	1670698833000000	1733770833000000	1828378833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
49	\\x738c7f4f506bc115f5d534d9cd2f44b8632e3425844a3cc4574b199b623c2fef480fd225bbff0361cec19bda5e9bacf8cd2d41684b2e5848f9a83a18faebfcb0	1	0	\\x000000010000000000800003c2bbb63707c905e3abf0440bcac62fb0f63ddfe76e2428c090187e9ac88b7754d2fc1a84d7b1200ef411eee310224eee4e6242e609f58e93cc536a3cc0e1d6445fc3c75d193861f5148ecb674a09fef8112ebaed1a13e04b52c5607e141e92df7b30b033f9246fa2307b66666b77ba2c8aad83c535fd2b2959434526445b58f7010001	\\x3942cafa478ccf05d3e74905888442c45c76bd639aae5b6bcebca463cc0341bbb04ae71e0d2efd51f8710c53bd7c1b225789a8c1bd6fcdf7316546cf843f1f06	1687624533000000	1688229333000000	1751301333000000	1845909333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x7a142ca3fe16c8d5c7b137477fb3796d3596136d5880731921587ff76322e8a6c26c94a4ff1f76618cf3e5c09d77d8a781312fb43a7827eb911b2fa68e1568c4	1	0	\\x000000010000000000800003d61e3ce76bacd4640cb3c716341d8bd2cfb244f53eed342a5ec33865259480467d065ba53de76596078c1a85e4c2dec56d89189222ec32f6f4757c92682ca03aa6869d91dcf114a957667b8c93786042cc5701006747b6a00473a8e0cb4b740af70d3eefb4a0bc87c463299587c324b1ce2b66328399723f23cdf93e9130609f010001	\\x28b46ae90ca00a08d5867a25126c53dc24f37dbe8ffa20e8ca9854b219038696585acc81fc7e021c304e9c8388dcdeb398af76d1379151e7fe8d274d3601ad0a	1674325533000000	1674930333000000	1738002333000000	1832610333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x7b50b80b83a51c828752b3517a4c229b98c162d40c3861ff1ccbc2fbd2eb8a766b6285cdf9c2c2f2abacfd026f090e5774400384b3ee93e0ba90a6d18cf79a9c	1	0	\\x000000010000000000800003df8ba4dc7c32e3937db643cc87091464c5d1d5a9cfb1ab1761a1367ab0453c5013b778e902c91cfe4c0f5a30c7a3c11ea9c7c575c2ce6bd457b24d62a279833ed3274c4adee8c6a63d0092b69fe5abec4ca0ecf3842fe581d6ba95795f82128a15ff5bd0c52aeac8335f7a0fc002db51923a9e93cb45fb930958c83cece439e1010001	\\x68b1f30ab3133dd581a7e74bf8921826f87873c581aac00c0da47ed3da51b0c4adf980bbc7349ead98341747620c594508e72e76acbf5f193e7567bf0525360e	1670094033000000	1670698833000000	1733770833000000	1828378833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x7b004c7d0f6229a5b68db84b5a56c402c08f8ddd2f8d4adf333410c8ce148841c3f7207d8b6365296047137f59348946a06c4197c15df5c290867ccc96f1e63d	1	0	\\x000000010000000000800003b5498f2b4fbc89b51d339cd1c02df293d6efd3dd580dd8e8ddd3646a6bdbb0830cdbbc8bf9504b7d7f7e693b77074ebe43815a5e94c770240fad329e5e73802d191ecf7408415cdc7267554943f939a6a62f2c42dd62964a1827c1c57dfcab86beedff7e53465bccb70392026b44f3859320ed451d71f31cf1135a63b1b37549010001	\\x8aa1ba0fad4b47cc3d93fff22746c26f5a16630f2730a3bd22eb6840030b5a9d64987a9f35330a15283babfaebc45eab5900229ff04b69b8413186746d5cb40a	1669489533000000	1670094333000000	1733166333000000	1827774333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x7c0c87ba235cee4645aa20be576c6036a236b92aacbc85971c1428ea1d84b23a5f275525e3ae319ba72a44736efdfcf52fd6356b7c01e611b013013403bc49bb	1	0	\\x000000010000000000800003d439f86447140d09515b406a1817aac98f5b4f25868058d384662fc7d19cbdfe598f0088b8269612204b5735f084f1eea6dbd34a3d743d1cf6aed10e0d400f11414dfb3d26ca15c1281254b12e415a5d1d39deafba4f2bf1da1cf36b57e5168be897a843691f615a4c1e62f89e95c83c9d32a077d5004a550d83d38fdbcecdfb010001	\\xd5ab5b1742fea85f063c991ec7c8dfeade3bd8dc824f215e372879780a3a0a76357171e21c68266285b0273be5699ae22bcef8acdcda6edc5ac142a109f6c80a	1688833533000000	1689438333000000	1752510333000000	1847118333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x7d9830e8eb17466be2596e0fb6dd10bd1a614b7a716ac9a12a4bc83d8dcdd675065eabaf56c09a8bfd7ae53cc02c57c743901b4897d0ce5a111311f6937b8251	1	0	\\x000000010000000000800003aa9829960edf8ef399981b54207d75d323753fe0ba0c75c2ec73153d724b8c304b8f877b47a7e6650f65c3120a737ec3191fa48bc2514586f0e8fd48406aa5403487bcdd5b220aeab39596512e0305bd199ec63af41704c1b32520fd37b1ba59813da30d4762f2078933c8424d6c826e996ec53379eb8e3316ca23efa36cdbeb010001	\\x6711856513ea7e75ebd041a7d7db81273a779aa4e423c182123d8f7a48dd399e3f695adbfd9e20f2ddd75b12e9ed4923d3519f7b871aa4a4dd15106efd02d50f	1684602033000000	1685206833000000	1748278833000000	1842886833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\x8030bfa8ffc3686bad4a616b9e147999af62b22df1ac958f3ed884b215d6d4ba69edad9836c45064767ecf16baf556eb1fa7d296e9147002d78d10d3a59bbd78	1	0	\\x000000010000000000800003d603054773977588b07eac55ae3240129fa6612b8ac93c20ad345e3cd2f70b4e17848901c500732b7142bf13ffba908e3be8b0f5b3ad8beda1af178ab7f7f383f1a1f228189dbced40626b6837a273ea2ea7f056a509da53a8ddab5252aedd6000bb77acebf9f1ba9aa9ed9e5e1ea5218bbccb979cc3ad199423cea508465117010001	\\x6b705bfbb0d315e859f6a579cf91ad8e6d5d728b9815b3edf66c254657fba30d4ae6d7a4a5df1a9c07961c94db554450c55dcc28a5188abd235a8283ee558f03	1686415533000000	1687020333000000	1750092333000000	1844700333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x814cbc35ef56c862a27d050dbbbb4f9bf982814f814386e0573d1605053c14f60c228c4525b4aa97d2be7e341f2be97cf03319f9d7d24ad3b0655748d032cc42	1	0	\\x000000010000000000800003b8c516a81920d19e224cbb100b183c2323e83e0d443d78a1e3e6f8ca39ea60a6da3d2c909c1ff27081d8b2dd42557e39c95e8e49c173c9cc8de7ca9f214e9c10ccb96093346fb6dc0bb8220f7c6d07023929de5558b35cb027513cbe1c58c879db5f18eebf83803358004cd7fe4b070a6e1a88707efdf7e8ea9f8cd021179bb1010001	\\x5069dff98f6be68a240cd1aa65fa288f922bf56887618c28417556ec8200d552b19021f41366ac793f2c37182ed97fc38938443ca05aef1f0ca337f4612fe909	1667676033000000	1668280833000000	1731352833000000	1825960833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
57	\\x82388e4361b108b253906351a12943db5d54a52128ef42c2107b772265bb51196d6596f4841fedaf88be24ccbd8203df8e52a75844a261c6811835df99995233	1	0	\\x000000010000000000800003db26f503eefcd2106dfcc62cc41c7feb571b684a6e77ac2e448e9bab208e09da6e7d165818483d9743b3438dd0b4049df2376db0febe5d814c3c8de1a19c3d0c35db209dd284609633b7582c69977eda911f6baf4802cd299aa7f57754a68ae08ef2ddc171dc3fe8da3980543aaa4da7fc2a3c4b9184e619233fc2f5a30c6bbf010001	\\xd384d147811ffe48b4548e9250405c78539aecf952d266df58aa3a0516f5e989a115e882a4d29967e0f943bb0fee760a091334f6dba076b002b505203c918403	1688229033000000	1688833833000000	1751905833000000	1846513833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x8330898ed9894f425ca2990632d280e4d05960b925ed2bd55c5502cebf0947fd6a830b5459df75129a8b84420acfd01c2d0e765f3343b899605b2ad14efb42ee	1	0	\\x000000010000000000800003c0262abe106a62c9b7616603f356523305eaa1771f051cfbf35d5b31102aca8fe553c6c789521855419b5491cc862c91f43af732b309fb9e01127d787440d8f1e45065e32b3bdf160f21505c7c66ab0e24bb7a1cafebb5547cfa57ed400bd289f50ce1664120b3417a7f2f6ea944ffc258ff610bc060b095f417eb5a4d82ec85010001	\\x11e8ef0a895dc866f211b3a8334ac868984b8cc1a833cc5ffa81c2c1fce973c37e36570082487d45d3a26a30a773ceb2881b4404b3682965ae74554ccdf72e0b	1679766033000000	1680370833000000	1743442833000000	1838050833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
59	\\x8394be0452db3123852c738af3da2df5c72037029676057378cd272d01911735a51126fd0a17be91698f4a702c72786d8c5637aeca33d45cd8e911d59ebdaade	1	0	\\x000000010000000000800003a0eed3c7fa3a4f1d68fbdb0b18cc21b8bf866c7b654fc3add33b0a9ff849331b9efc48566f5f63c004d0cc725e20568519d1843f8530716e2484df38e4b47c4b61b4406a969fa5b4d549e80cc83c728bee19ed6ccfe6ce771990f541f31a0c5356735916ae1a7cb6bfc017d3b58e0b425ed90890a7b3c42c961ba677e18df631010001	\\x27cb33830b29b76e9e651c48a0f7278cbbca7090c61a7ca86bfec04030a6425b69baff0ca22276d656e6c3a036265c3c777286d19d219bafb54d1200fe2f710f	1660422033000000	1661026833000000	1724098833000000	1818706833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x847411ea7a01b98a5bfbedb75a5ecc7ffea646931c7cebd76baf9ee41cade446f956c892577bf01c3e6c225aaf4b1d967ba23649072efb6aa844788993b85d6d	1	0	\\x000000010000000000800003e3ca6294a33e66a799d562dd7cff2e70c44bb32c76a181de257b3f4cb928be7122bae8cd805b4e14e452e37ce8952b86466487fe3e6067edf0b81b13f831a302da41a9b41509fc2cc93f39d4596037287bfca0924c516500dac41be7b7971622209717f04748f2f1ff34accc0d7aaf9b3787a2649cf6cd20882e2d24f57f536b010001	\\xcf3a45f620e15b750bbec9d1119305cde406dbb6bd92091610c987c8455fefe76756dce983a83231f49c90a0bdf75673758117f319befa6f6fb98728c56e2b05	1671303033000000	1671907833000000	1734979833000000	1829587833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
61	\\x86909d9024d7765cdaacd908edeedde9038db52142f61670e00ea71db956af79420c2fe73473a035cbcc73be12e3c245a842bddbf04cad3f04f7d918969e59d2	1	0	\\x000000010000000000800003b4c56e8020efe92a0b812fc5a8f27958c0593253fd1a898325aa6721f5c61fa00042c9689a44feb4dc1172f72635ba3c3bfdcc52bfbcc20ed9159404713afa0bfb4679e502e8cbb62473cedfc51b8a29978f23ad9164b94d7c894569acb94ec159d817fcd149234dedd94db92af39d73594ce3a98a686c959b6b2f701515ad53010001	\\x2204085234b31d3c42b01efbdbac49e64dbce44c9e81db0d04859f1c29d3fd50f60d1f4bedadff89d22ff48653cc4f05a87e99cd67d3f0b4e6e7c0a88cfc100c	1691251533000000	1691856333000000	1754928333000000	1849536333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
62	\\x87a4e73e0d5c1832a1bac63e9bbb75133f1b088b3d0cca2c0dbce7d81ae26a6ed8e197a68eb78e5369f2c8a29787fcd499d4767ff94664bae7c25b472b212075	1	0	\\x000000010000000000800003c00d9d3d3cbe8a3989f42130b0d3468c2fbf77b722b668f82ef2b0a56376107c3646e08f896ddf9e1c1d4c1d45063488e2dce3f9b5981cc357801c0b21285dc803cc593f37f6cf2e502bf62a3f9d2896f5620b14d8186a6f8fa7ea873cfda8ea592c0b512d444165c1d7f07a6f542259bbff78000392858cdd64d925a68a4f1b010001	\\x12088523e4262c92e039a00efe54af6db8af83b6ed25d6526558eac6916f8e32deda1f39dd368740816f5b391014a668d8b5dc38b8d465df628551558794060b	1675534533000000	1676139333000000	1739211333000000	1833819333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x88205b23b61f78dc61bb5a5814a25fe664233e77075b281811582e42b3d0fb2efd8cca2b0c2b1b45a8ed171bccf24de8320db1f68032c114bd20bcf8af4d2a21	1	0	\\x000000010000000000800003c2c9648f13cc6a8346c7208949bb09681024e24aea9109b5fd3e732aaf315437db8d0edb859af7bcec1dc2d61afbac4eec7d5a76010b55704471a9121f1ecd597b25da4a8bc4a6fcb932791cfdbb00810c86795f687854593cca83cae7f55b0410db14e44f1a4633c23763e8370f5346d4262653482049e83ea490c5d672221f010001	\\x9870efbca373f9ef608b45acda850175a97197d2ccdf70f841035db936d5a33d23b1b6794203e1a1df25fd54a56b52fb0a531301ef019f8302c30cf6be700104	1691251533000000	1691856333000000	1754928333000000	1849536333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x88389b56dbc6ab5bc2ebdf852cc636651b49cfe19c34f36629fc86e83adb1ded755cffbfe8beaf042cdd9536736ffeef19fbbed7ef64a5a1d465ecea3052ddc4	1	0	\\x000000010000000000800003ea9881770aa0b92c35e64c497baeb08cacb5b31516a21c1770012b9799263718dff92816e0210e37eda87a3485a32951e9a912d499956e9f32eb1cb2d45de470d7b25141e8add1e9ff71f283bea6d1d7821c086e3e01efc94875ae6721097fedb2cd7aec662c69cb92cbb66dab8315439e52abe24893eb26b84eead41f418145010001	\\x930b813d013b1b6db0e892e71d5c07f8f232ef71d8d04349fd58ce00b65d5a3b72d367e2bfa20a3a9e28587956a756058bcfbaba07229fafaa78bb53dbb9bb0a	1662235533000000	1662840333000000	1725912333000000	1820520333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\x8a2cab9373b75341038ff693ee65fc7668c64162da44461e1e0f6cdbd15be0f3eb65bcfed2737ae15abbdb98b27381e58412f44dd71dde6828923d117a8b2b81	1	0	\\x000000010000000000800003bfbeb860c236ef4d69ef20f5e7818f21bbccacf46d4a85b20330e44e47cf43c9d6b04e1e42241fa17c8a9bd0799dd0c70046dc4af903e98ab3713d67edbba4e5686745fa2943e11009be3400fd773061259d6f585b08eb9043f774797ce8cd306f6762f2601f3ebecfe400e8ab7460ee4fbd91f461b24852475353d4ac223f6d010001	\\x5df769c373b6bfb7406e6c6d88a9eceec522497369e61635359a8f5785554bb3cfcf8d8e979ea22a93aa4d0a3ac9f162a8777c001a8f76c7b7dad3162f978b01	1667071533000000	1667676333000000	1730748333000000	1825356333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\x8a541fa7ccf5152dd0ed3e09b701955356d4e9553663d99986a1662a1f53a6e2400131f465decd03be2f2cc174bd9b21ec9b03c04223139153fddaf63a9ddc99	1	0	\\x000000010000000000800003e40e2668c86e129e66e49688ca8bd354896c22ebc6caf8a63aeb098d75cf7d4eabc26e779ab303bcf3efd25a1d08c62365a17e0a60c80a4966b93bf35a3ee2db4b60d0215863876d19fcdb5f38f96b5c0e5c57dc8399f909b7648c2cb3b07409000d46b08622755dab0e7dcb6de5ff8219f2f9b212522b52472dafe209e9090f010001	\\xb43f9c2b2be1a8e77efb0ffaa3d66e1aba7e201020d5b6ae6872374f468276e05dd2917d40059a506815a7f2c9cff9fe3a048f5634f9d6f09cc3a457d781ef06	1668280533000000	1668885333000000	1731957333000000	1826565333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x8eacbf0885be777bbcfb75cfef5915a41a1e7dcb5b365678d126fc1ef517042bf793ea909492753f9f5ea74973e3098d8e0811dfcc840a921f60d0a425f80e31	1	0	\\x000000010000000000800003e98e6fd85755fae1106ade7019b00f632071f97666a037cfd5062459ea08b4c0df033a670e5ba0f968647f5660b59e0c9892f2b317e2f45e40cb8e4dfce3b0f234b10bac9d2671d4f4c17fe0090a4f532bc47ecc236ca417872794162060d5b72f35f409feee3ffa5b42282f4af2d0370de2e6a89c75c6e3623c84553f4ee6c9010001	\\x461cf2e386805430ab8e916e9826b48dd368309d7b6ec5fc1117df4a17620a356f13bdbc8fd54a8c80c1af14834cf122c46cc626a0b4c6b9e5a4f531373b5302	1661026533000000	1661631333000000	1724703333000000	1819311333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x8f8c68632652515ea0ef659b12f1fb45911b2d20dd76dec231dbcbb3b520e814ef43a01c306a628fb5928696500439b7366c80a221cdc2b2a44f01e5ac300b15	1	0	\\x000000010000000000800003cb3fd9143ef176776180ec8de885e05bd6d49c074b51f84edb3b733fd6a632b9506fe47d19dce542e8a200fccec16b9c6bc0def6ca0807dc8c7c85b977cc8f95772e7c34f08d9ffc07100f97742e9780f635b70dcaf8c2e6b4dbee6f6c5b5624b72dfae61765ed4e892b19092517cc9c7d54f67a27f37cbad135d628e53ac70f010001	\\x5c7812889f2cc379797f4c5e0dcb83fe9d1303723fe71d803ed4677a453ac4c423d7d44c1d7c9d2ec9840ce1816ee15975155e8e7f65db33847b6b13750d210a	1663444533000000	1664049333000000	1727121333000000	1821729333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
69	\\x905cdccd423677b9bac20f788041c42cb6b65a48313857f1ba690719e0856a7002619732d332dd7371774f98cb608978d3110dd28b059ef5a1b7a84f8fe23dce	1	0	\\x000000010000000000800003ca5e0503a60e644142209788ee62ded609192628ffdbcabb6220576297a54c9630dcdf31520f13e7bca65ec7a9c83aa80d4f6e6261d3ba4c927322da5de66d3fd3d02fc26760c1bc132e94a68c7dee7939d0906dc5083be909ba1cd47df042e81551236628666057519e4cb25e0db6d7a4f4924041d8cea97655eaceace7ea47010001	\\x8601c89d1ca7e5eeb4dfe72954b0bba826b69b1860161ab5d63ac547fddccf20317e33e6fc35bd5d87b6cab35b0b66a225c7000c78c690e0a5216da8dc147602	1678557033000000	1679161833000000	1742233833000000	1836841833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\x923c59fd77371c4a90c5c948eac4283944b9de559f49d48fa563e9d384b9c57e939ca73b4fb9fa917c3b28b6f8367e65d0d31087fa39616981d9ba3705d9d28c	1	0	\\x000000010000000000800003c6d33e76f1cdbfe2dcab8d7c93d1fe75ac552e5c8c1aec8dde5a8cebabe97e6817212dbcfc250a50fcd8ec58fc3d27ccf9b839e601f9789ced470a6f896bfa13604d4d1214a55fd61da86c25fcc2b1295a95fadd38a6571bbcb713acd246b3f8ed3fcf720a2ec8cbb74da15bb53b8c25e8415299ea09408e6091d623faa7aff9010001	\\x2345f9e74963f91ee35396c3337c0c8ac6cc1b0f4f995b83e6c82fb6a264d196c932c23adc495a93c752c5af5d1640a05e1c1d292fa0658adf59b32f91b51907	1664049033000000	1664653833000000	1727725833000000	1822333833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
71	\\x963c01bef56fafa4661b28e3289698267035cea5c797dac1923a9a4ff218f2d4a3efd271e4c7e1bb84b1ca7aa48e7d46cb5cc10a56d2ac7cd5828e6a00667bb1	1	0	\\x000000010000000000800003abfa7b249308f300b61ae0e3ea2ce5810bdb35b02166ffbf7d4ebc7f94313e291af75359bc4640e19711a8bdf1e0e2b70ec75a3a8519d1737751cd64cfde377e3d621ab0905a575cce0b8b65ae6e857a5845e1626eb562749993683af87829b4a73190cc7d835d8ad3d457312047c99f67a46419e78a4cb4ef0f1b828eb5bc3b010001	\\xd85f0746cb2cfac33f0512c2a27ca576212c5f07fe5abe2dc148d8fe4d6dadf772f06e1a71783c2f5e1e75b597846406d382193f3991e1ed4a3151a8375f2506	1679161533000000	1679766333000000	1742838333000000	1837446333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
72	\\x9904825067f31204ecfbc8959cc5a4ed1dffa01520ba239af3a2f3235eb0b44707746e053be9452e2742f22109d0c12603dc52407b7501fe3f2a4bddec7ff148	1	0	\\x000000010000000000800003961e74e3959d2df21daeb94938c5c5cf0d150c4e2daa2932145714f7620eef4104550f0688ea0afc0107d7884254e4660952814b1ae9152871f0275dc79d9d2cfced572934f2a6406e444a13408a62a457d1dd755e215915ed2c29523dc2313db9582ccef6696238d1d2e5d190d2f32f83a10bcfd050fc29a7509856204b327f010001	\\x8afbf7b018a7eeeefcf1f491bdc9be72b4c1d46186b2cfc6119726f03b097c24372a7c71feff6817d9ee5332d904a4ec63f5702664360e267aaf30b494d6a101	1671303033000000	1671907833000000	1734979833000000	1829587833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\x9a3463c919e707133a880e904dba71030200ceb6a8d72c457763414f9d828b6b61a1e35531d347feb5d17e6275614bb7c8c46fd8e5a9e884626e22736884df2a	1	0	\\x0000000100000000008000039eb38ccfe236d115f49b003117d9c27d11985550ec5c34c41d4805654743117f4202f2a4a5220284fc21b504e8099d756a38f144c3e128637f979f29b05b4a3ae1ec57c7aeb49c21289bfb6bd593d66ddeb43c5246d2fa8d9806730941061de18b01439195eac1b7612cceeb1d493083e7a80922a498caa8623f1bfa6d7471cb010001	\\x51cb6266db8e07889f8441a455a0d4304e7f190f4c05c823665b52923984392e70c29f15222729252a469fbfce94c4a62ca0bf1beed1a6c7425ce685d9d09b03	1691251533000000	1691856333000000	1754928333000000	1849536333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
74	\\x9a7c4612e00d97163a9cd0f3be5c51001a212a05c1807c7ed79746e7e3a4c59bf75f5b8253255fd0011abb53af54fd1b72e2a8ae2fdee32b3c610982eea8d0cc	1	0	\\x000000010000000000800003ca1be45d406e2a89fe86e7ac886006888cf6d943ab3d492387047e2491082669820db77e993fb55fefa303e4fd3f0cbffc457796d2493cf5f78bd513d6c5df144cbcfaa13284c1a56979de60d0de02a4b8a339c10d459b021723bc45dbd5499918c6b6717fe734414229b504f7971b1fdd02ea1e998e9d99e905a9cfc7589d3d010001	\\xfc7681e5fbfadc2014d6f2563430a67371a1e2bf84972f4815e2ee779129c0848b2cdef7969caba032dc5b4dd33d869a730e9f3cf19a91235cb3ca6b98cbb409	1677348033000000	1677952833000000	1741024833000000	1835632833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
75	\\x9d0cd8340012e79c2611c0622993a0f075e5cc79b911f4621e835dae2554d0256f174fca4afb87bc941274faab3a1d1901d6211a083b54f65d5eef720d4c8371	1	0	\\x000000010000000000800003aadfbad933f5c8a8e338d81eb2e05edbbf075b09478a79055e37f0502bf04c2d05d72a7c21ee22f86188cccc351822bc657be9d9ca7c4abd6f94c3ed90699afb5054d9e0810302e14d37f413d3bd270f182f2cd0fbf243e2abbe9f76c0ad8b9b11f4c5d6a978b3e21e47ee57096db4f6296c31ebe3cff5acd2c1add621e8112d010001	\\xa69da0e81ed072c82adc475dc6f47e1b16fd1420fd6ebd6c21440d1dd311f0927088e07e329a59e6a92482ac703773c845922c7cc15fe5f5a3491d2bacaa0402	1685811033000000	1686415833000000	1749487833000000	1844095833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xa5b070c157510da74b8e89bc111d1fbd8863d168fa7188ce45529f3807a41c1a3d86ebb648549ff1f352b61d0830a0bc95235f31130ffbe6f5192b975e67a24a	1	0	\\x000000010000000000800003b6a3fe889e5451b5626685e595189a5240339b693ff161f1a64082a5a410e6e6228cdc5b37f216894f8ef69c2ee3ad6a8f8a1970ea35b9957d2a676dc45e51172205914ab1858da1a2fcfa41e9d593ef0078d27357d0d6cbfaa265427277428b6819cec5cf3bdf3c1b7ce7177cf99a07bcee6acb20e811f4c51d6524965c5f01010001	\\x82ea3af3f60ea25f0129a4addd0c3ac5f2a23ca76469c77224b697f308697e851d1bf434ef76208c422ce61db118e8d04e35e369dbb9b2602ba6111c0363f803	1659817533000000	1660422333000000	1723494333000000	1818102333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xa7f003507d2dbd6e6fe7dbd59e8a7824622dc34a73d1ca1a1e82247921b27d7b83cf94edea36f5c7b9adfde17b70d99305b6c1a617cfbcadb1f0b4ad36d798ef	1	0	\\x000000010000000000800003d32afa0d15abbe4668d86b59cd0004da2bf7ff60ada300c422c1df849fa2482298a754a0e18c37d3b24a2f4469a13e8792902ea5e1fe279a6dc7976f569db5bb7b22638d2dbfd5907070fc9228f0c67eaf25676420a894c28d38a7069961963b2dd064d0255d9c5f393739b154adcdd28709002b59af2a89bb6d241a9bb77edd010001	\\x260099d4cf8d22911dfa18f0408688277e03ba311de329d834a749722186b8f3488e1d4a07dba63874023f53fa1f5761823dab421cb8692c9a182a5dead77b08	1674930033000000	1675534833000000	1738606833000000	1833214833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xa7b08bfe6017954d0133ab418bb455a64eeb6a562ed83971fdd1fdb0b9fb6d057f2d36517587033dcb99662d4e8d785975bc4f22dadf2172299e0f82514a128d	1	0	\\x000000010000000000800003e48e191cdd82bd60f0e2f5c45be8f66855b3043f67a921bb3a300b0a00923a16394f2c389efe54fcc127da9711de90154f77925c919910d9f714c133694ec0b3d673134fdaf1c984a3dff223684818b29adeb4f809cd33928e8eed06dc0e867d1a8a54cc2a3dfd9c0f444a0ea5b122bb675537d17c491dc7601ed356881627c3010001	\\xed461032d560ada119243ed02e3205b3cc44482b3c5937b98b5cbdd96ae4e2ba627043e4aa0e0167a87233317fcae61a92537087e80e858a388b26f66c1cb20e	1670094033000000	1670698833000000	1733770833000000	1828378833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
79	\\xa8ecdda2622c3f12fefa5f1ba0e0c8305666879930da26e712bca53613331792c7fa070a6e031e0ca7bccccdbe8addb01a3d331b887dfa684ea2efc1b0944fad	1	0	\\x000000010000000000800003f5922694c25c6bc51d394aa29e78e7e2affd80aec0d6ad8c0b738add3e6788c72ee6f93912a05b452e022d6ac27943579331973aac29d5de2f86965a159bad03ecff14722581e12dedf15b183be9c8013334ccbce96567dfe05d8c349c3860174b8b066e92b190474c84109527f1d0a6667097d74dc9b3dc5cb51fc484b45cc9010001	\\x4feedf86659aa8d587f618147895019ff0eb100516fd072a192a7d473981ed2fb2f72b3d157b3c339f58f0f6da8d996720cc48dab44f1a61d514c9dff9171407	1674325533000000	1674930333000000	1738002333000000	1832610333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xac10610b0e31bba8dde71bd0f64c523d51d28ab9c48455c3379be634cb8e9140a99b79502dfae460b962a0e8d81caf0a4015e7685bc58cc2bcfcd81af919ccbf	1	0	\\x000000010000000000800003e4436cf6b3c3d20d1c1c12faa7c6f79d34ce5d7707b76acb152f9c3a5e5fc6c4a0b58f58adffc5250ec33afc12979854c6f9db13224acd81bfdfcd106de11a28ddccd79a33a6a0b50d0ed9df2fa2c314015a80db1dd0706f722589a472caa7ef78c106936b8af613ede12ee3a7a64371a1550ae177558a8a9eb96b16983d95b5010001	\\x35ad6798a45d49f6d6c5461f01267b45e16f605cdeefe070855094155aab098e830328b65f4573a7e98bf654b48fe2975cc0a02988e26fed46f6677e7078b004	1664653533000000	1665258333000000	1728330333000000	1822938333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xad0cff62b4f7f7ed7b929c3d057a17f6ad12d7485b602ee7531467e2e045032a234fcda2a1e1f7b0666df33b831fe746c9727776875e2bab11ed47e31d87e9e4	1	0	\\x000000010000000000800003c4d46001b2e78c705a25551ce9536f2cd86b764bfeb1bd480c34fa1f56af5d0e0e52f82c05e3a7272744d5d9cf82ef6835cad37d0634f7d518b5a26d162c9eb27f84db8e24b327a21a1a836405a445af35002654b7d1fff72d2579fcb0bacaaf80fedcb17295beb27aab2217b52e772968ac4265216f71b6fe65c21973608f9d010001	\\x846e7713025cb59560cf4a174f1b8175b1eefdf68f6bcd5062d25696bdb3025a3a8e73bc4cb734c765f84f89618a543cf5634dd5d8be34b8051c014ce026e30b	1674930033000000	1675534833000000	1738606833000000	1833214833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
82	\\xae78d8cf96f8a95a62ce84bfe4197e0913d67e286031cce97b0abb475b59881a43e1a9b93937d41dfbcef786733712aacd6842a2b6f211653b365be8eb5cab9e	1	0	\\x000000010000000000800003e284affb76e3e0aac5b3cb140f0a30f575650aafcb4c663b02d8e47c501bf2e9bd8b101c5860e31636515e3fb401810d36f7841f2938193798c6c2ff6bb76fa5ea1003d4155bd50b130f21716e5701f484bef14d3e5ed9407707bfc2ce25294f5faad032dc1f7946ded8198014201df1abb8461d7d219672614d813c8a31390f010001	\\xd215d4fc6ef9d9181ed5714bb46828a29dbf2074d9ac1adce63485219e991c385f3300d3ea34b95aa3e564e3f108259b2c88e00d4e302a92197ce92b3762e905	1668885033000000	1669489833000000	1732561833000000	1827169833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xae88e96b0670ca30190884e4bd93a580a4d474de48ab84a756bc5d1ca3b782664bdde909211da13d3f6abd24e933540589172d703737c2a707db54d6f6ce75fe	1	0	\\x000000010000000000800003cef160b77b67e9ea0bb8d283c42c0e861776afd08b5aead07034548b648068e8ab0101d40dde66ea13a3fdc9a04e41412e29631e521535de0bfd588225a45191196c0dd3a3f349e22f99f2a70a812f7cf61449cfeb032973cbf214ed3675438a2fa74cb42b89efa0face6211677387cf5d556f215113f0b24ed048eceaf3e09b010001	\\xf9a2fb98747c69ec9bec4441a43b7f315671513c2b5f9a649039970e6442383dc6c0e0798b654a37634d82fb19259e7cb897a03163d02f9f3f6d923b2041ab0b	1662840033000000	1663444833000000	1726516833000000	1821124833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xb47ca7cee89ac91c5139dd2a07ad6b7bc80d465f47256399db06741f29da43541e6f58ba6bde1855c4ba2a45fc1adcfda96c938a0f0140772438db4fdc540a80	1	0	\\x000000010000000000800003f83d070ff52b33f3c1b46cb29ebbfd43b2cb8383b306dee0ba8773dde73516279a6b81cc022f3dd634e78c5b1e8d86469d50c8e7518a84deeae6470cf509e9e4b950dab32be6ef80a1633fd8cc7a02b022770e11ea9e2d8e6e67c34401390b9c96f10b6fc1c4705f974d9a2163e9c56c4b8f85ab2a575d34f43c00bf2484406b010001	\\xb46193715045e95012468dc67227b6560534751baec5a98a12d0cd2d8b8a0df0c2b823ace4ba4ee40e192e27113ce609270d0ab054d65785e70c712a897b5400	1666467033000000	1667071833000000	1730143833000000	1824751833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xb7106b4638a25eccfc08aaac089c21a2b3da00417f1234df22a3a9264631e02385b38ddebb4c95052f462b2790b1d9f4a504548887b35e3c17274e4d0e4cf81d	1	0	\\x000000010000000000800003be0c74f621025929733ac912946d8a31327f915b534025881e2439604ec7941bc604705bc253a4c5bdebb9ae88121867ac741adb392760970e862bc4ff6bd274fb2953dcc3b1a5c3875b8dbb6d862344bbbed1e895e8397a8251976ed9b2e87f159a3d3e1d47d38f747799d16e0fc6b78ab02bcb6f75028663af1bd339cac317010001	\\x3111004316ee6db8970539cc3d8afa952686e1ea57af9ebd8c6a6107afe0ed7aa61d7184cabf49a806f076757251a86f1cc0c2f88480515dcf9d25163074e20a	1667676033000000	1668280833000000	1731352833000000	1825960833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xbc882ee38d27351d5822c57089876710c1925dfb684da0ea0fd4d886f90956a43885459ec53a1d90558728ca9076751e5c93202842734cc6f822aafe4f0b7afa	1	0	\\x000000010000000000800003d93a9a846d5851d7f58d43bb7043c72899ebe0253bf5e065a08867790fdca86b7493fc14e319e9d250010dbcb11c47938e798c7d10c580ef2b5f2c282bf5dbbade9d0c7aed260a0a22aea91af40140b958aa73ffc97750a94a4bad2d24f3bff655ec51dfde415b00e21810f488241889c0b0eeab41bddcfb86c1f93b84e7fd91010001	\\x2df891aa34b005a12f279f3015470e7df0e63e6d8ee482af703d30bd8bd9506195b57ec8ef9ebad79954d7c6e70d97cf36477764d81747d0a156e48d5209a000	1678557033000000	1679161833000000	1742233833000000	1836841833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xbf6c016528170ea5f2497f5adfda11e4a10446f996030f8161564ef3f524834795b25747fff774024df0ff8f55aa59e6887598ef483ec373d7b1ec2d3e179846	1	0	\\x000000010000000000800003bac5521fb193f5d8432ccd516bec4dacd891bc915b06bb33697a438ca278b5e4534e28e340fafe37a27aa5db5678950cd0c197089aebe7bd24fd3035cf99049a83e3c916395259c5a088c66fd17ab5df574f9a15a7ac3b957abaa0532fb738cd61fefd90a99fcfe3217d81dd0ba1f85cbec43ce0962392a241ddd8f1cf430c3d010001	\\xe12a5ec5f27fe60d247b2a2e97f629b98755de6ff718e68a0812415c9e9d3f546215f136eaeadbbe7582857cdd27ea2d97bbf855cbcf3eb8c3a7b90809a7140b	1674930033000000	1675534833000000	1738606833000000	1833214833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xc688de1e276342b5dfc9e1f1faf256fafa49852f5eadedcb66269425b78de34d106c6868547637ca2d1708d2dca464039f3e21b3a8fef945aa20edece0a0ec43	1	0	\\x000000010000000000800003a56c7b4727a71f593fcfe6bd92a2bedd0c668233e516ae4d0be64b749b8426954e9d457582da352fb2f6c94228ee1dacf2645400b5a547a8c5d9f911b72a9619e1bbb12296c80c43453e38f578eac5e04587643b49a2e7633b9ee19076f785eae2c427acc060ceebca4c7fc1ae6d8c4457dd2af457f06543939f7a7e17a35937010001	\\x61eb191493a2cf51a41db00deda13072936f7ad5d2e0d261de66597cb5b95eda541867907de9e7d4542bc44a9f2e402692e34f08ed30482b5f66ba6b21d64200	1674325533000000	1674930333000000	1738002333000000	1832610333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
89	\\xc7a01e96f1cea516a0a35eaabc13605c9d53e366141e44a5c8234dc860cf6d197073fd83b17dfc98324a2124b82b20c286c6cc1708026c9371f3f99533cbb072	1	0	\\x000000010000000000800003c2baf9bc3147f74968cf6d0bc987de060fe485581b0909f26d6f5aadb0f700a059841c798bf6677d6aa94adc59587238ba0862104f4931653c285f489108dbf06e8a58ae94f2fc004f3f039bcd717e6b7fbc147898fddd785b8bf0901d47acb5483c626a4ade37cb2f2fea61b3907cc8eb5bfa044d14a71343932363dc0adef5010001	\\xcb9ddfa7d71170d51f7eb9beba8d0769759602b15838cb6b279f17648ae1cfcc2cd8854c2f2c90640069cf1b6f201d6fd402448ae2fcad1aa7554aab494afd0b	1671303033000000	1671907833000000	1734979833000000	1829587833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xc730629af75608c22f8cb26afed0e1a24cff050e881972a0eb3924e3c7fe2b8c3ff8e9333013f26e7849bed142d7bc98e2a48121382659c2efe37d0940b6890b	1	0	\\x000000010000000000800003e03fbd704f1bd1dbaed0048697a52bacfc5ba9d249be76662304d43521519188086089b8dd9e459dd033397caecd5bddd306ce71c57f8f34a1377838a89f0245ae48cb1300b0eca0bcc07e7c3a48d6271796cdaff984d0fb0739dfdea8eb17241a7984f25b6f7cfba7d09b5ac08060d75d5719a9c4c94c550f717048af34545f010001	\\x16c249348b4c9d74d8a1fff1d747772f2148d1a37d438fe242df320922c954c98e3908061409ca586915fe1f351762782139f410616643cc2fa62d9d97586606	1671907533000000	1672512333000000	1735584333000000	1830192333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
91	\\xcae0a5adba4ac689696290b52b295e7a7fa223446e8e90d25e8ca0c70080fc7bf63e5d1d7e4248ecdb319a4d62b04b0deaecd7d3736478d10c2f09e50c11214c	1	0	\\x000000010000000000800003b5c4f6390690d18136d89334687c72d88d7fa184285fd894614f93c23f1b567ec8aa07e5a87538c47002951107630ffcce615ab7ec41e7b546193bccf24fc6a5df634d478f7176a6560abc6d57547cc3b3635a87d14e63dc3765477c75018e226d6bc215baaadb848fc736e9ad5297c4a61bbcdb17708b01c086198073cc0e87010001	\\xad88212881e6b027c25afd902ee2dbefd2483688defc5e3c616a24fa1006f92b28af5b9b6ddf1f2d559aec99a8ef10f162091a4cc6adf86a31dac8d80515fe0b	1679766033000000	1680370833000000	1743442833000000	1838050833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xcbbcc86a76dd914dfdfd5e7e389543df28d30031e52502ff59d7d1bfbc90a1b3b804f5f1895cf37d7379c20bf047e87339457c2545896427b4486a6ebb54a473	1	0	\\x000000010000000000800003c4aaf786c31d25ed93c29b703d29c5f6fb32ba60b88e08c7e72a3b7cef1a730854a384095cb5ff6dc8883963731992c93d81e634655b258d82dc8e47124c8b5b579f81d3ebea30f3c490e4ec30aca858b2672d8784966e1de5b275a80298ee6cc983070b79a85aa7e9afc75435226ca97eb46a1542b2cffa802f4cd39a8c90dd010001	\\x234d465bebb07b4906504685d89aebde1a97da7015ba2aebe0f92210afc45cf30e9a7e7213742b19564a5c9a03b3863f10f84da922dab51738fff40bb2019205	1666467033000000	1667071833000000	1730143833000000	1824751833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
93	\\xcc3437f5df62f153f0db7d268aac4393987cf9559e019d98ea3903da918f5edd16aeba55798144ab6e4c237163a863e1945ba9495106ad16714adb61eabed6e8	1	0	\\x000000010000000000800003d61c88e6a87797afcc72f96345db61e613c19fa07c4d396be87163812bac8fd752b48928afe114e6e3c4a79a7caae5758aaa24f8121455761d76f2de1319322e8e4a7370b646a4dc3398e02177f73108d758b675967dfdd87c906f47d84cef03f827e18980df93798cada94ff67a049908e03f5512923eaef518913f138c7bb7010001	\\x524a32737abcc7a983060690e99e6c776bc47e08e034e15574089b80cb3d93285f1e19f717a94e409853687b6605c71f03451d6fcfbb59af9959e9bbd881c400	1689438033000000	1690042833000000	1753114833000000	1847722833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xcca08243446caf1b255865d546dedcaa8789530b493b86616f6f06d87e301cce5ff0f733cdd893401124292d540a25cf620f82174c936e7fc8b8e5df7f76d758	1	0	\\x000000010000000000800003adf3e66a3b2be5389ae3d9f1e1acb204739adb28f9f57e02c43147c0eb27df1ff2b134b297efb8a80efdf8ee536ea1598f342d07e21251fccff0518b0ad1dad8c84101bc1236f5589f29b949f8f8374227320a2e751fc36fa74f4cebe5dabb319d564c19cc4b63e89fbc6269c1e72f7c63bf3a6d7de546304fe782e97c8ddfcd010001	\\x9d0ee85d1b72fa177b885e8736b0d6fbf76c6228c98cc53f6912b0ebcfaff380f926b1f7cd70f6677756de8f981bbaadfea75b58a980a1224ed6cf9ed73add0a	1683393033000000	1683997833000000	1747069833000000	1841677833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
95	\\xcd00896276d4b9e9e90ebd1b08af4849ffba415716d746be0bbb1d310f002b19777cd34633854d2ddb5f9f02b8bae8f78e012d8569a31177eab6a29e7a6ba504	1	0	\\x000000010000000000800003d596f5c18effa5b3c3949f05c31bb88858d76cd0f535e54a1c75fccae202afd135bf756ac6706977f9d510aed84d7187cdeb82f3d85ee81e46959d7b2a45b54976d11b6cff4d2d44381fcae54f895c16ed240e069094ea074270fd4be26acaa8a5b1ac42bb0c382a0db5f4954459ab7218f78cf1d3c9f0eddaf05b59aab059e1010001	\\x31b3549891f712fa4206e9725b4413b5f7d6c33e901625f12c495cc226a835308b5ce7cfb0b5cfe3315c6b4f8300fbc48210944171b3b7f0e28b2eee2b58c808	1687624533000000	1688229333000000	1751301333000000	1845909333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
96	\\xcf7cb03f4f5c8ff09955f31f988302ad984fd4117b293a4019b066ba8f7a9b6905dff146ea1c459d6430e97abc2ab77efa6ca1f3342aec20cb3483785f65c97b	1	0	\\x000000010000000000800003a47eb22334adfecc51ee90035731cd53f2b2f555d74d6d362994ab2040e9290968f11b8c18d7c9bc2dddf8e855bc1eb829201afc87ff2a87d3e36f02b04458ec2cc5beccd2bacdedafa8bf8ccc70b35b39f371ba8db93e46aa36db644536a587e94854c514804db9f1c2d9119f52e21853aab553249cd8d296d6ebd76205ba49010001	\\x5b022391fe4aad1861b0c068162f66d50f19f1ac85c961a7f18f427a5ba04e37c2f06c67e041716e8549085b6703052d406ce67ed6d992e1a6a323948efb4b00	1661026533000000	1661631333000000	1724703333000000	1819311333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xd0708f16fe19237b185e6c2121a41c28044f645d47f03c2b15b3497105c165aac85f6173f787038b9a823c4a9696aeaec5cf4af133b55ea3c1674fd391a55d81	1	0	\\x000000010000000000800003b861007b77483b743d3889b74d5febdade7bcc8e11c2f790965ce7a532c0d5a0aef83301258dfce3679342f903b5a73a0a389258daa718b66150e8b7fde0fbb7c058b8d3a34e5a1935a4efbd3a8679361c247b7de5ed122373fc28a53f62fc85995540f6253afc46ddb27cbe3e4c2bf00b37f4632f1038bdfd26214d16d4bebb010001	\\x73c5c44098b578cfd7089b1fba0722c3a9c6ac9fbe4b77ef610fe74eef456d5f6b45cea8a28fb7de91cb08d68cba68175de70a2fbf97ab80f282a0ba78aba308	1671303033000000	1671907833000000	1734979833000000	1829587833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xd1bc9edb1046a3a9a1ce23f89a96632ee2adc88c9e19dc9545b42e774bbd6d22efe505289215f2b4c8cabc80f87faf0dd2dd08c532ecca47bb560476f13b9a68	1	0	\\x000000010000000000800003e52edb778c5af3e99550b95260013b58143a52c03462cad60112d95b2300a7c276346b23ab4ff618eb1d16795cd676621af847b155642e0e3e5bacd1d715ae68f146f9af5ca94b2892516eee1979f659b8145d55530bc774740529d68f4d6738396ef13b7f61f3e561741526f17eae95fc419fec80b1f1788f67128a248eed8b010001	\\x461ba1bb38e39cfa7c2976deb2b8c3f126481dfca9d1abd173741417bc0be47b007368ed879cddec95039bf80050a17ea307cc16426929402ba7deb256e3f10f	1668280533000000	1668885333000000	1731957333000000	1826565333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xd814213a1a25bba9ae268593b592d23f4b1b22c7c7c7069c7baa878a63f0cc45e7876afa178a875cf85e73baa56e80d1daa201f5278ef4dc3e3d14f17fdb1e7f	1	0	\\x000000010000000000800003c891f3a334ae906f16519e855303b3e47d70246bfead748da791ce7c4f57b561b89e10e77e93f68d5ec7153b1b947ff8fd480487aa5dccce38d8b1bfca266a7db784a95236ead11546b23af9519cdc078af01d146562d1c0d4cc06b7f0f245c794f56107b6f107207c282b0bb30b0f66c9ac666ba9d9ef519713c6eb0a581c15010001	\\xd34969daca9d0417c8780a0af36904e0e2d4c18246424bce878f98b87aa22e2861f5aa11cf989373098b6069c18bbb5076e4c05accb36f5dfbfa7ab55e1e7403	1685811033000000	1686415833000000	1749487833000000	1844095833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xd9f4524e6e037bbe6f142b03d4fd74855bb02ffda48dd7fbbb5e2e19328784839dff0d563c48d6515dc2a0b3667813c94eee013648ba3754278337defe2a832f	1	0	\\x000000010000000000800003c5bd8756eb61f75dd01b1dc910133b6e19b45ea0c4a6b726d0dc963b010343d4f0eba0c712b26591db908dbeed5ab97d95421be221a7ee325f38de88f1cf2762ba87d139e21f37fc221daa7b03589514785c6260d850051e7c3554d1a3f69652ea0033d1b7ad242345a450ed9c1870553d511f7f33253b144c6a2e0bde5b9919010001	\\x3cf67936bc8eba8262a418514bfa0d56a45c28d3cd26fcbd6e769d0288e2393ad3371ae1a87f08b1f2ae19b8a6c146ba6326f04ae83e09564cf524b30f8fe00a	1684602033000000	1685206833000000	1748278833000000	1842886833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xddc0a03783e78483f1fb573eb11581cbbd0cd9381c3e43a2ea91537a788ddd03da870526643f9fce1571a6f1daca183e50cdf2ce20ac789a36ad6391a58ba3d6	1	0	\\x000000010000000000800003f061570dbb1712b289246c9bf9e74a66ba51baa4527d7bc0af2b9bf16abb9ab73b9abe7a76ae2210a268f1d5ff21dc3759c2049e50e577d53fe7e05a194b3ee61831ec59159405f79dd01469ac43379dcae899d5c5df5cb98659c46e88f9072916975fa8fd501864e759e1ded714d53f6164b7443f109122f53a6acb269d8a57010001	\\x7622cbbd9fb3e947c17fcc4d14755cf061ef13d1a994fe3019aca3aa940b7400d5f2f7c6af455b0c2b88ea3707ec3ea689484bece3a8159131be06fbfb35ad03	1684602033000000	1685206833000000	1748278833000000	1842886833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
102	\\xe1143a33a5962d5c2559ee11c7dccf80aebefcd9953e77693c357f0f26757650a4112f7e39dc02dbb15dacc93308e961b50cb7e00e5c738d999edf8462429695	1	0	\\x000000010000000000800003b884c0fed541686ee77999032cf150f92db6f5aedf50d8fcf378b8e5764fd3cc74abb66e6d297e3e0941be39309864a27613e88f7bb055adcde1ed5e7be4392b89fa567162698052a70a14fbcbb83123f84f1801bcb0fdd6df831eb80c4778ce64fbbdfe25f54253b5683f7a2205f085cc18480c0b81d0eb948ce24aaa9649fb010001	\\x89ca5bd67ecec42c03e69ae2cf9909e104dbe375fcb233d3da9addb826a3d681248a061305f39efa4ac3fc41d53e2c61c6e5d81795b699497994263e1100d008	1665258033000000	1665862833000000	1728934833000000	1823542833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xe36862153f1068b4bae26584d62908ef8ae74ffb10ebd96d21fbd76c771ddbee3a3c11bcacd6f466bc1d22423f12632a3829877fcf3232ab2ee66dfd8b02680f	1	0	\\x000000010000000000800003e612bc8fa7cfb7b5d9b8d8fe62bcd820236fb9a0879ab2cb8dbd195dce3ba2597838872a5c1c26394d10fb500ef35525a470688ceb694d7845e08de64e7892fcb150d1cf71a87fc579a018e21f683bd9ded1c68d0aaf20c959fc2f0d19e8da688352c0abd352d4709c40954f386863ac4afcd555c5ef98ba0885d2234d698ce7010001	\\xa3a85b5f8523725513caac698fe7d06b60df027896162f2930b0e27ad3a8e86b76657ba5ab3bb7e0a719340254d5ea1bc696c6509364f574f5b7fa90567d4501	1671303033000000	1671907833000000	1734979833000000	1829587833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
104	\\xe4a4874f8f361550a758a1b63d7aa4dbb0f054f42962799c1fdccfb15cac6d31742a7969b98f358b125aaecf69dc8bf68141fc8698272267d76d7ee79fa65a17	1	0	\\x000000010000000000800003e1303d907341b6296c15dc8b6ac6a2d24237d73782a98b22f4d419aa1b7df648587bb2f29d487bfd39b95a4ae3aef2419319ca21a9d51d3c4e4758dac278ef87233004c84e8bd26eae0383cbf2520d180f4ea33364bfc78fbc685ba7307c4c8971c80916f4d3c64abff5a85fd85f1b01c7c884844889aa864b541efd8997b613010001	\\xd793db0a7dbfcd7b566f00ff56563fe53e5e9932b6a84abc7f405b37e534e97c991234a5f87fd541075795fb7aae50a5da423a1d1a805234e329908252044d0f	1683393033000000	1683997833000000	1747069833000000	1841677833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
105	\\xe80c816cdf4c745420c2217fcd6b1b2758e1e8ce37fc22a2069613d46a0f12ebecd5efb17e1125fd297838a3b5b80242b26679c16c2e1c21470d748691bc3649	1	0	\\x000000010000000000800003d14295ae15e4da448eb06b107e870be8c2981c88a7e40a4294a1f1595d2f42dc8320ac3481567408e7aa03c8860f653f21171a7274be3bd88729d99f3a4a0a7216d2e2cd7ca62e0395d2a988b53ddec0478ae21e1e5fdfebca15fa25d5e4dbc4fccb21c79771c551eeb41d65872590b5e74041e429bf53d38b47f19543287e37010001	\\x4bf43f75cb39d43dd472df2e589ce95cf33ba935e1cb6aea688cffe032b8c1bda000501ceade9e5e963315ac8ad636d98e68ee055ff98a1c70d947703058df09	1670698533000000	1671303333000000	1734375333000000	1828983333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xe94031cb1963652593c28b06b4c7c27ce167c16385566e0893bcf1a9e829089be6781a750df5f9aa19567180a5be64bd7313bd4005a1b4e9597e40a2e67f45b7	1	0	\\x000000010000000000800003eec1eb7cb909b8c21252ea604a853b54c351bfeae262dc3b123b821688bfd1873ba15a801fc6b7dbb3babbb4d418f8f60a8359981aebd5d092a90bc3b93d5bd91c415b3c7bf98863641c3ed0bca2f95abb3d68f07dba7c602442bcaf41f119815ff8a39f3d356b0f0d80c4ec3783a0be0abd8cb86d304d20b7ad7e8fd10f2795010001	\\x77c8eb14d030d705cf47904530cb15b4ad9841a26d91cb11a8db98cdfb311e19ac39dcc07bfa4d3c11e47c8a7c338e806c81bb8c1bd51a1ced06053c8f469702	1668885033000000	1669489833000000	1732561833000000	1827169833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\xeb346edc2305bcacae1babf24818355593568aad7918781106acfda8aa4834402c3a4730a2272826a05d3aa935e70fa414b5a0b55f621098773fa40b532fb33a	1	0	\\x000000010000000000800003d54e6736cf5f30619ab5745828975e25d75d6a4fb20e55f3b6adec4dd05cadba6c5aeb0f4e83e7e368d63db4e5eb54be52414145e1bc0987fa3b2fa20bd54b02b2bf9c058311ab671fcbc05b80b67a7a40d63ae18716ff43c4259290cedb382c5ca1b1869dd410b5a1b1cb5bdca4496fbd755b4c50dc808a6c7b807c7dac184f010001	\\x049ab39e1b52c335b925d13d507a3af760a935cb8ff91cc58ccf66a268df29cec0426fa158fa8037f62201aee1f9306c87593c64af7c2011d35f335c9e26b70f	1668280533000000	1668885333000000	1731957333000000	1826565333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\xee00f477eba1b54d202171315e9268f40a02faf5fddf503779d08feda8312669edafdb1e6082a0f79360f213242341e3ed8d245f7d4d6e22749ac23f1db8b1da	1	0	\\x000000010000000000800003fcd662b084ca35401d6a1a086e6b537417b77a271a30c2c0cffca88938ae6ac46aa0415789dd4369442f52057a5737b033210cf37c16686e04c9b7f54bd4a5ced878b478571495e9d5850f1e4eefa51984909862290eea140cbf55610cffd2ba3881972b5fdef411bd73c9f68ea4ea26df21c80529f89aa0ce02c93cad54568d010001	\\x7cd1dcbae315ff6ae76d90cb2d3c2145e35152a9026112da63937536a60a12ed34de53a6fb5c2e644d0445d1151240991d32c9131f36af9737c52e1ea20ad308	1670094033000000	1670698833000000	1733770833000000	1828378833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xeff8605a42b517b21d79597fc77ab055d3c74f1b9abf1a56f4d4ba62de7ad81a417c14f526e40cda9c1cd0824cdbe6a58e066dd0dd6c4d8bcbdb9d1a68161cff	1	0	\\x000000010000000000800003c76d6a1add075a2adf5537d82bcdf7611ef01b7e5bfed302535ece491fdf3c32e29c1b18c1c92d47a9e3206f0568d615402083dbe177a715fc94629627a3d5e3e8bb345ff7bcecb699eda8f582d8a98123f7f2045df7c705cd578e62d93383b9a316aafaac4fe0c0919b95739adaedc86cec7e48f66c8d63e870bb6a0fc790cf010001	\\x56dd1fa94530fea31e21cde5c1f792f2b78a66b822e6148ca17dfc4743fc3f905823d43f07f85335663f64a7dfe8b518011379e361e488923ecc39da05a03a09	1665258033000000	1665862833000000	1728934833000000	1823542833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
110	\\xf1f89e2c2d392bf307b4243dc0c59947ebbc9e2539cccacfe127b58127aff3830c75bc6ccd3f8a43ff54cee55d5ccaa9c622968e66a166cc97029f100371b3bb	1	0	\\x000000010000000000800003ce0b1225d246fa464dac789ad8d1341522ef0758e3dff9676d6978bb7e4e79ed0adcc0e6b0eb2ef857a40e87914e97cd5d685087e0f54d280f724571d0d7c8732bc3d231d71e8b93f36a877e339e1e4611b7f74e74025bd1adfbd53df9613f938ff240a2a3350d557038981199176a1a97255fe5a54391d7c657103da7193301010001	\\xe70fedb114264b42b65e3cab6bb96327a6987992163a92bf1da4377fe41f9da2c04ee8869d716024c5b13cfeacef6966c0ddc092f65fa812660c828d2f449708	1673721033000000	1674325833000000	1737397833000000	1832005833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
111	\\xf28ce02439d2e81285cdd1355aa85aac9035a75945c386a22298b81fe87ecf72e79e4244aecb96c8aa3b3be22940af25863ea6ec20ddfbd21d75bb86e04e1504	1	0	\\x000000010000000000800003cfb0d2705fa0dd8d0650019aaeb826a761383fc2b7a765c05c3808455e60200e8860505e7f5409e0873e80f523e0ae97c27b8c4b7648a492db57cdaa2eabb83330165f14ba78c4581d0fd7046b7fab2efc695056e9a01f2ccb2c1e261933c3ab16532f307c93d943ff82c9cd7a1825059b738f6f3d58992f8d17a650440befe1010001	\\x1087ed57300d05e57e5f2d15bc9899e48417b13ab0e88099b6da5d180059f1ebcbd0474ab3152cece3d01096ad766e9feab1f5a8f91213251a66fdce33d17901	1679161533000000	1679766333000000	1742838333000000	1837446333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\xf48c01e403c89fcac5e93ae9f67006b6c492d1c5dc7085c44748fa805beef693a0f25e99c816fd586f55594cd1ed60f9ab3865cb98ff2d12a70264c236693f40	1	0	\\x000000010000000000800003b5f2fb5a5780800038b3117ac91345e59a7397421ae4a88ec8d622f515bcd62128faf53876c90e4e399c29350567b81db5a1508e0ee8eda752bfdb4bffb480a88694eca69fb42bf43655bd22b7f3d61ea9f1756606b098b8b0308b040187f7d4bf4c2e94189d46fc3aa803c3b365d85698574ff29aa96c5158faa65566ae66a9010001	\\x0b1f3024bfeeb86c86c6896fb72cd26550d177fe5e460e9fcd7499561a6fb5c6bec5934da1857dc1f6d5b6f89fe124a1640eb8a38ce8fc6d86fa782df28af507	1677348033000000	1677952833000000	1741024833000000	1835632833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
113	\\xf5e453570c37b0da7eb4340af6388b55eeda602e427e1359896aeb5a40ffa0ee6e42b9d812152fbdfff5110f3ecb652563de3710c4b9646ad8c149fd7181575b	1	0	\\x000000010000000000800003e67e8cc6d853d43a652f73da6cfc1ca876f0f198834a9ba5b01d5d7d88a2c88cf692ed9ca18dc9392115ecdc2230e939727700c75ae2daee7d17d158866ab18fa67a382acd20a4e18452ecbdf732a09c45bd08c778f1579c0debbf42c54bcd39825809fc9f7240407266dd358675ae5d7de2d9a3a222799e7aa04ef7d3c90e63010001	\\xb3b504029ea5d36325cc12ad33f784ec9633db43c1590487dccdf600bcc605715441c103f7616930ecd44caa4149cc010418ca7369a112339c69b21c57a7ad08	1689438033000000	1690042833000000	1753114833000000	1847722833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
114	\\xf6a4f19dd54e24d9aeb58b523f3f53d682ce675f57523ce2cb678a70aa5d29dcc2a0b54b6ec3ba65853a77d55df72256d5ac2e68bf7473eab16174648a49b88e	1	0	\\x000000010000000000800003cbc730855ebc5205aa909616045cd836c1a0359794edf4e42f0eab083dd5bbbbd47ea7d2ec116ea6f030a0951183134094a1a667f0f82d01ad6286e45d4f4df17febc0c941783233c6d132d2f25680fdab220229669f6e274e7e094a7e43cbba5cf7b91b31d9171f5d39b76bd14c84444c4980c0e539c6018d0dab2aee6c0f0d010001	\\x68c5742020eb48af6bc66165a51193b75a9166513e5d81a2b06bcd218c21b48ae2f2369c7031bc3967318ebbfa1826d14073d70278ffe82c75ec709cc299f101	1660422033000000	1661026833000000	1724098833000000	1818706833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
115	\\xf674d7d2ddfa9e7960994b7f3b9194b5ac7004884d36d28709e3c8f2af51f5fe87faec272b7347edee79981ffcdb3c24da2bad9f57b8b539e2bbfe12ad56a6ac	1	0	\\x000000010000000000800003c5d2224e476177d28526fa9e986d624bd8985bbba68e516e2d8c6380be236ece7e4a0448ad61e3849ef2f58099ec8ce5a95450a5d166cbe3b14177d79baa0723e328d8d8eeaa354be16b46359850327da20f96b8da77fc7ed34c4b778d4f1bf17c4cb72b8d7de696465b5428b00926434e12dd995f93dc025dd7d267db6f8cef010001	\\xa631da3065ba94558c717e4272587b269f9a7134ee5f2b8371fa59385b9fdf7b966fdc3a157121013b9300850d12224f15bf44a4289f88387a4df2b4eeb6f505	1666467033000000	1667071833000000	1730143833000000	1824751833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\xf6a09cb628268fa3040521afe03fc0d3c70e7fcbb61b334ce7d835d18db8146dae0d321a8af643af082dda48ebeaff296f62df2cff2d21f1e773c40d282d4f57	1	0	\\x000000010000000000800003b4a9ac24ac270519c032881df6d59741eb8d9e6319fe5240a1923b418d59cc1e06cc0fa93ae02d47b2a34a69e32c8dfd5a67f083640f25aa64654e58c9c60ce11f848eb46ae66f8426aca62d3076ba6614476cdf5545777d18cf0265666c4e9cbf544538d7d8381b527ed7b5fcbac95294949d6f157e71a71d19b75646512d8f010001	\\x3f2cdb7de81a47343fe310404ad928e65d7e2adcdc69c418f947a0947173ae27b85b9e1a616034c74fcda348729f8daa6bd1d1ec4725b8e6fc5fac7f92e48e0c	1665862533000000	1666467333000000	1729539333000000	1824147333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
117	\\xf730671640ebe19ff0896d213e77056e75adb162032ba5f27d39e2b064d3426862df074c0f20957c34c421f78b2b65635f721b27b6a636d4c05c4f5fbacfa35a	1	0	\\x000000010000000000800003fa842e5b7594c20f43e97c05e16a8b0be8cef269d059aac5d1ebe3c3cef2245ba06a656fe7e75facbe30ae95148bdcc32431099d9b79373f43a149cee13255816c62663486debe327efb0421187e6ab2fcb2e213b9605f08e294f45b4172df9528da8d1c675f90a93f1f34345fc59b39dba8412fa238c068720005603e8cf113010001	\\x6777bde311906e801d9285261f339a5436c9f7d505f00991937e7cd5865d495738b191c2c5cef9e7057bfd851ea1796c5149198208e25c0c5686b5437ba83802	1682184033000000	1682788833000000	1745860833000000	1840468833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
118	\\xf8340e98ef1b757b7549855f3e0de270af03dedb43e0571f2de320c59bda2277ee96ec1959545407d172317d89896ae24917b396dcc52fdd106a0521e8105890	1	0	\\x000000010000000000800003b85f3aa795ba0e3ae9bf97282ad0f1eff9160ac1f6842001161aca91837ea5782e08373407c904fd0e04d8e049ec2ec4cd5d8378d8465939177992ee250fcce6012855bfcadc435506e720ea5b88657957cbb29296cab404d905a6562d748b7231cea1ab0b27f004829cc6152b00bde259f8e1d08dd54f154f74d3825b681db9010001	\\x6dfec65ae1334bca8ca6319e3d0232b51a02409e40414b6cbcb8533e165de035e9c6e01e2d120322e1c6e825240156184916770d2cf1b23f2f91b627a17bfe01	1674325533000000	1674930333000000	1738002333000000	1832610333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
119	\\xfc389853ef9a1b5748b3429776d5080d86a5073870cf5a25e65488c87d5dcc0dadfa3a619a15ee2f241f30f05d1989f81e2f96fcdc94cf2c62c51daedc75cc98	1	0	\\x000000010000000000800003e4fe0b1d5c4100c0b277d078abfea28f6761f4a514c8ca7cd837d8731753e58d216980163f292a3083e1eaeaeb8c96742c20f9d37139153960e258129b6db18d29f5d4a49fdb6f404071fdf7a66f5fe43acb96044f4d015bf792626120819052be8ee18bd501b2de76d2ac2d1c545cd0aed3c124e24f461d178e82624571d9a9010001	\\x953dfaf9f5a594f388352cd394cbf3f48e5768a6333df74c58370c6e36d1aef324b7c0472013d68c606083453359048024ad13036b51a01fa07256b6ec9c5706	1685811033000000	1686415833000000	1749487833000000	1844095833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x01b157ec95e557802923d61a27960eb6a59f6d48bc6a321bab92c57875e418c706b80e78e2c52b829cd4b6147e7763e84b0a79527d70c2d470b588fda44a1013	1	0	\\x000000010000000000800003e11b46036afe86b58e643cb1592f4dfe3477921b67d4bb7137563e3c7fbd05686bca114e17e995e6bed92469e3f1995326c28eadc54759339050e47e600428e91f4458db5365b45e9cee222d8eca3b17e9dd30a7e209bf4d9c5e8bf37cc01471fabafdeb79e3e314da7083dddccf3711d706d9534193d9e2ff54a70bd744a979010001	\\x04703c96b62daa6088b38356d3e6a3f21fadb6683388a226731713eee698b2973832b838d029010f54dc6f91f9c61ecf869b81ab2382dd00188ccc846803a60d	1666467033000000	1667071833000000	1730143833000000	1824751833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
121	\\x013dfaeee6e23f919a3c0c3622e4813a98d9121332ad0c183ce83af4522720757775609cbbb30cb0824d533ce129e19862c15efd866e94710bc70acf1221bfa5	1	0	\\x000000010000000000800003de349adb237166d37783a203ba595707ebd2608f6377bc2589549fe79c9640db5aab977d3d487a5da7b54f9b1f3ec38127188c141abb99c3e8d3396b69a94c43bac549e8267b57fe093ae0c55bf2938b494f46b4cbaa6e163caf3dd9862c41eec302c16c9836251fca8fb93b850533bbfd41e7f9e372969f854053a6f2e24d79010001	\\xf83f861352c4f481e8c88a244986014952f2aaa3a8b4fa4ecb040bdb54b4939df13c31781de65307eeedb04270b2cca732d74aacf6293f6bcc0988f9a10dad0a	1664653533000000	1665258333000000	1728330333000000	1822938333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
122	\\x026519fe330c5101886d2be1902a44fda7e190108be5024ebd2ad8c452aedfc48cb3e968eca2a95568a54256cc3d743cdaa2e3169db42dcf45917bb253de913b	1	0	\\x000000010000000000800003ee75ebad380b244380185a70c767204aa3c181ce546e1c6de88b2d56848d5485f8df75359d432f6d06ac41372e47ef0beabe23e86ae0bf2e643bc7937d5eebf4282ec487bbd1578d3759cae89ab7a5783bd25fe5b0ef900b747734a6dcb377db0e7a070d7a54463c6412fbd7de3a724a3e936d81653e6d3c116f380110491e15010001	\\xfde22511bbba91388bcb72a7041c4723933a4f72975fddc42a9ffbc9452f69e2263c388450d4731cfd7670c81ffe2177d182d47b645155ea4b2d74f9e92ffe01	1685206533000000	1685811333000000	1748883333000000	1843491333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x033909e1f1d186bbdbbad6bb93998125e0eb520a57b0a4e1ad7f2257395e5eb6b23ec07cdfed729ba519041729379b7cf39a3450689e072e82a213f0672e10a0	1	0	\\x000000010000000000800003bd9b1d264a42ceecd8941dbea603c8c1ba6bfe58d74e53dc3d451caca0953a80e690c44fecf43e79f415165c01e2a2f8ee7ac9728d562283c244b3eec87b62d099ef6cf474538856fbff8a8df4a9125d628c044f5d29319cd5777e8f49414977c97e76581622cde47f70c5767f9b5fa713c2210b642b64701be3769466b54f85010001	\\x133a6244c89c9392a463a9c39b94f7b7094d984368f7780a588d514891c6d2b0874f0b2ba4f72316c0e31ea947a03f170b710c6e5da93b626fd68d9a4b413e07	1687624533000000	1688229333000000	1751301333000000	1845909333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x04693d27686a32d5aec7f03ba7f0579f8bf1d2c85ec19c3f5b865af7f6adbaf9457ec92370f0c0034e2cf5866e2b887965e87c7672f8dd11415015571ed297c8	1	0	\\x000000010000000000800003de36d9f1e5583744d7b0617f02dc378353a537617beecc58086d4a260a5b6c60241d54f026e42f91e277e5cfa8b1f1e13428cb202a3efa6c9110950f638d5a1b5ab6605ba9578fc2db2bc0651f910b5391fc42938c1866bda1b5e1ae08e7fc9b89722731e4d297bf46477f85aca55dd989c4a6e13f20f2e84238b4f56e2785f1010001	\\x31038f965065d3110f6d11f91ad287ae24ca5f63380932ef2203064cec56a15deb131db19629b51ce86cd7c56c8b9e08a3b699927de7731a39d87f43cda9610c	1668280533000000	1668885333000000	1731957333000000	1826565333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
125	\\x0625f284acefb1b522b7a4148aad8cebd12cfeddd308c47f6a93bfff281380bb4b8b26d4bc91430b5a49cbb9f21d80f59137230bd4317ef39aadf6e286a73d02	1	0	\\x000000010000000000800003a7e8b8a78b7009d5cd023598a512497ff096d4ec98d464d3b7401a4526dbdbcebcb69504ce1c8d6337d0411ac36df17b54ad906fa8e166e4bb31e1777ca78f1027f5ef675ffe7f35d4b858031cff06480fea7d36fd583017d13a0daa24d239ca9139ce4a4fbe5308910d5e7103fc0ad2cdec2f5d6492ae85d54299270533785d010001	\\x86ef07066c1b8bc31db050a32c1872ac2a65a234bb2b95cd33bf411aaf5bddba201381e054295ea2fa7cb179a3e4425d0270e525ff20b4b960dc7a6a838ec80b	1670698533000000	1671303333000000	1734375333000000	1828983333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x07c1495e11b49d58af5d653cebe013288438a1561986cc36a027741cfb07b2b5edb92b8a2156f78196d763bbbe43cc89d7e5c018f9763d3f2dc722f0526643ea	1	0	\\x000000010000000000800003c41f7711851d4833646573416feb2e68ca491d48cfbd6c58a41a709205b57b2fd1b76474e8e218576946f676f8c0eafecba7cf0212a810052ab8474572021e69aab1a4855b8caad8ec138d696b3825592dd95fd74ca41982fd1dacc2823db51af8193d9757d5f63302ba73e0e8dece538243b8331a787a41da308002b3afabf3010001	\\x01e82defc1b2c9ea8d6667bddbed6efa9297bd32b9122a415b69dedca4518a032219354a618da6843acbca49f2147b362e514d142cb726e416376686d914b80f	1671907533000000	1672512333000000	1735584333000000	1830192333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x0791326c0c37c2d1dca79fa5ba39d9177df85891c774bc8b1743b750369218232614ea88f5f1fbcadf60ad468a03ea1e8fedbf1d9494d2b00d2a77bbbe5fd223	1	0	\\x000000010000000000800003e44b4fe5a758c48c2c858bd979016ad9e88566459d70e3692667a3626d7703515d885ccb7518cc565ea345cc766ec9d6bdbe1931440d8e88736baef1bc97d34bf83c71a74b14fbf9cf0d9b082468f83edf5c653be36fae384188d63f7ac4c4f226aa8a3a8f5b0cc152add67eec7eb1f73b447eec47aacfef75367111013767eb010001	\\xade188c9627496d02c0881367a3fcb5056d46f40cd742db0560729781a67b055c7465a40e21868cdc9b46171e28a2f1176778077033b65466e3511c08e38d50f	1670698533000000	1671303333000000	1734375333000000	1828983333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x163db6c72be005cdbc6414b56f053aaea6f01a33d93f4779606a16e07ffaa241da158bb052f3b1fbe34fc581c54c9cde3099e027f10eaab370329eba8ce76ee0	1	0	\\x000000010000000000800003c34fdee65f351d1e5ce945780f31da57373460bfce65360aff48f8b92d4904d59e19dc0503f39ec472a0303d94a856f35f234105a577b091e8a42b1e0c0f8e323e53239f7b3d661c5f1d71c6bde96a8da2002ca7bf3a12251d82f7207206fd6495749fb18a7dbe62855abfa412248195d0c55b213999aee8f486396d2ce03405010001	\\x18838572cefdcd84ef0c16f87e8f0e8e3ff2311bc783c56805c5ad24c805605249de99a2566afa3fcf5603ed71b74726f2b0a8a6f54e1854f29d34e05ceb7106	1682184033000000	1682788833000000	1745860833000000	1840468833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x19358e546024b8dd9b39b341b69ce9b62f6df78f1864020b6193565d2a0dcc3221439949bf4cc8586061c5c359185696eeaf6a78012f55a1dccb2b73cdbe9f9e	1	0	\\x000000010000000000800003e3587002dd2abbb9805b1ef0ba7e224899bbabcc0d7229cfd253bec47a3a8f969c813c35d929f5b0cc896da22bcf92e590a0409296a40697be5f27a922c174fbbdf768ecf69b0b375f770171f711e1da8b9530b86087b075c2d97aec48fdd83216c79dcb1b7327913a5fb16715aa499b45fc5675aa9a287ec2741e47383f60bb010001	\\x175454a401e41f92500fca87efdc1b1e7f4bfaa9c4e087df9a59dee2ef40e04a065739c09db8b22669a934fdf3b3a7642e08cc3f6ad13cd301076efa23539c06	1688833533000000	1689438333000000	1752510333000000	1847118333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
130	\\x1c5d749faf7a5249d18a5f0190c351555f35ba28c6375e91b8e9b9c2f12277ec75ca91963a7c7dec1b16f543a1344c6a367c922bfa49bc3d0e611b32b9219749	1	0	\\x000000010000000000800003bfc801fc0680f4e874002f46260ce1c22cb8b721cf1889107b04a87810f3e2f0dff0a6cd45915a1caa7d07131836516c6d8cda111f697f693246fc80b429efaa2a4221689c5ed8e952fd0b6ed2eecf36ef5c92eba528d6dcc68f5b830ff6d3c5ca84365c94522c54144368fbc4010ff9d44052d1ae91b717f002a64a493edbc1010001	\\xf134799dbcbd11984fdf8934b721c77394ecea39c351a1396f85034b1a7d2e9088243a366d405fc243214371317698d2d18e06704a659e0e0f5d74ea766d5d0f	1670698533000000	1671303333000000	1734375333000000	1828983333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
131	\\x1ec9c98a5f8c183317537e0cc3b0be2f61f55a891ce24f6153adbc26eb559831cfcf5bac4e7cec1f2a4d50d1e2ee336d03790b4047e12fe6055bef389346f9c1	1	0	\\x000000010000000000800003b911365aa8d2ff83b20a9ad746b2c450ac5ae49c67bc4b8447cec93f209ede4da660df13a3e399d653801a6a74060025a0b31773dec42c400933c60b7a8d02b80972ff1981bc9a9b5aa72a11a5a407e78c206ecced5d904e92bd87108bd694929c512e83ea9f7cab971218ddd92a32ec1fefad9618246ec3fc87eb2774a0d159010001	\\x45c3201f46206973011f004d7b5f39648952e597155e36fb53fa4ffb6186c3e8d600cb12aeeb4d2df4e42b55cd3a2f818ae550fe332634721a696e6c7299b401	1679766033000000	1680370833000000	1743442833000000	1838050833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x1e4916e6f09184b8b9b72e65e4affff9b0739631a851bee12330b0ec5f3e3b1cbe9ef68e80d9852a134b0e35e6b86fdade0b26e61679df4b0cbf275590a3849c	1	0	\\x000000010000000000800003bdbb317f3b89610159f37f3dba6720b23ff3d4753cb4c8581870187c2b0a81e78dcb3eabcfaf7aac09c6984f7322468604faf091eb9b3a11e4c0cd1786362cea547c89af394f6c32b32a4865f590dc6ba7279f28c9d0677deb3c0c1b56404bc20713b9d9cc246a4965a1458bbb17100c5b7402daca159cc6a7be849f65ee1819010001	\\x6727b5a3216e6cae4510d91d23154b276234f960283b84b92b174b71e76b3949b23dcf00b51bdb0ee55e224d8974f6dfaa9a5f4c22b8af62702eb403b1d85209	1681579533000000	1682184333000000	1745256333000000	1839864333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x20398ff113c91031b3b13221d1927e000d0d0e960d8c2bb4d34434b3129a00e567c237b99fc4134e3ede66a456219a4b15f3473be4ba2864d088417f0d243034	1	0	\\x000000010000000000800003b4866b78a38f770cac1a5a65de6b879257e766a5dc67813a0e772e964a538b903c572b0edb970c84d716f324d4c8dfdd43d76befb03c28fbbcfdc8aa4ea65801a4e54eda3c7fdbb226d3ab4596bea0e7b604247281608e009f004e8fb80b18186a96c2a15a42cd5630c3d82788165e8a0ee1148d6abe7ecde768b34a9cf3cdb7010001	\\x28c45c0434f555056aa4aee7603be5b7ef0803e7d0f1beadaa506f28cb4272c797fd1cc928336648fa044903763ad93cba1deec69aa9ae306ed2c05b02392802	1680975033000000	1681579833000000	1744651833000000	1839259833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x229549ded437d8b08b48e0cde70bc6f52caf6c5585814cc4db9f2acb8bb7fa3095ec1cc83fc6669401e5c41fe5132aff83d80e36027f4898b6f103b13000c623	1	0	\\x000000010000000000800003f334984129dcece4cf663c68348bac6956407da979940290aa94d5b5c41af38e90d6c647944c59ba4fa3513e6ca205971a11b340d2727ffbbf9f6c4e7348c6cc0afbe903c0dddff0241459dcde47847480344f72bb6fcb6ea45627e5b2c24aad59bd39508a753341dc09980937966299f3ffcc3e079da74a3aac2ce58a41b825010001	\\x077f057b250069b6bcc7742101e2cd435eea4c726def528d733a2fa79b75faae3ec2d8cf11d3b876529e861fbd12785e2258d586447a7bde4301e0fc2fb57506	1673116533000000	1673721333000000	1736793333000000	1831401333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x2639dd20c12d4a93e3f115b89f85800fd4d5cffc30142678e06a089b396e56cf16c7225b02699bf18901b3f7e1aa769c88551838b1dbdb5252620d4ee4df68dd	1	0	\\x000000010000000000800003c414703978c22163f460a80ca8899d22a5414a217bae62720500380cec9a46e1ef33470368e19ff4bbcbb39ae64e7127ac4d45f8d0eb356f1466c79531d72b8839c78c1187f47b433b754f21503105ad540e5cd2f2fea12d86c2d104fa211f688f4b57d2af51081e02612177db6ee191de9325204fa59050fdffc957e5b83687010001	\\x33ebe48713cd0c1fb9df35040b644d6f22cc2cc3b9eda4f0ae3da43813b00e81023106cd11fd325297187085f03972d0b04393fac67e2e2ba5d9f1d2cffc1109	1665862533000000	1666467333000000	1729539333000000	1824147333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x27f9f5799a2eb03d21fc5a4bd1ac35892163f386ad32d530f71dbfae713365b83246929613f35b347449787f0b2bcbaed1189b48e3c850db0cb7e76b96343048	1	0	\\x000000010000000000800003c1a3ab071cb8487c8b068b9f2875e6b59c8dcd668aee22752dc53bcf257f0c6b1d5aaff4c248312502253c69ada1cefca502e6f7601672142939e09f72c86e7ebb527f0d239eacb745947d78a26c3435755f5b3d4d6523e85571fc4de8de004cbc9aa392257d922c275287557208602dfa384c1602f6a438b61353a34ddbb115010001	\\x202a567361116557d7c84ff634ec9ae8f5387c4b5c135b498c34921666ebe8384807f3a5ad42e6243b8e1ea19e41795acaea27f0c781ea94ce29d5dceb559707	1667071533000000	1667676333000000	1730748333000000	1825356333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x2d498a6e212ec17e80866ae72382e46a2b1c31734c11c363c1c2cce420f0c52a60aa30aafd519237f9288f526ab16b835865360a48e492f6b99095e0c3b9f471	1	0	\\x000000010000000000800003af1fa502c3d87af2c9b808050842ac0316ba0fdba0bfb7bd8c9f1b907cb9d98e288e95c34654cf19ef70c6a7923fc7680c424b3898d63f015514008affd7e07680337013588135936a8dde03711e10443789493118bf08ee98931a10bfc0721f05189bed59608f24bac087bf4b7c2537c5ae3fc381c6864d8ac42808da96c07b010001	\\x0064d384b68b242cba2192626879fec0efb3e359caab7dfb2675c645eb9d335112b1abc3b3a9be6bb2e44792675e90ff074f68f8486e94681c936ed41d50db08	1663444533000000	1664049333000000	1727121333000000	1821729333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x2de9c65ec0df758b46f07cf8336b4d477028a67212d7939654acf5f254b34257bad31a7796da76f5dc9ead4cd90d269769ae290c844109a8d4759451f548f39f	1	0	\\x000000010000000000800003b45bb7ff8999eae4fdda7947aedb456d0a4c499001748c9c35937f5eb884b1f4d4696763929b14951b05e26d2984e3327d595e36ee9d8a4c89227dcdccc5aeedf6d177f936bc6184d726d1b10bc3563e9230c556d803dd9ccb75e316539790210a13b59568a8df9ea0660cf1cde795f859628c6dfcd3e5a8c6ee165151497763010001	\\x456d26bad022ce7d8adbecb5f8b1ebbc92b62f99bf5ff3b11bbafb46a61dd8d9f1593c90b062df6a57049a608c28ba5ce956630ae81540d3b518220df60d200b	1688229033000000	1688833833000000	1751905833000000	1846513833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
139	\\x2d65ce75e0f8d6bee070366164784e8578e9fbf3f23efb14ed8c0360c198d9d727fa6561ff2526b75ca21f2aa385ae73c583570fecb770f004711030591e75e5	1	0	\\x000000010000000000800003b8e0041ecb1340d475fb2fd5dfa55a7acffc6ce4a573516b69311d39707534d521719d3b186e47144088fa1fb0fe069f1b7a9e54cc7d17cea0617a2bf33faa7a51badd085f6a8ae94d5589a7d176b272cd57d74c2fd8d60db8454a8da9b03f56ebabfc36757f30403254d220acb1c38ac90ecd9abec157890c400b85f0a74659010001	\\x3e468f1a37c0b999ac4f8c26e624062d23d2e42f10ac45961991746f61b765128964d35fd0eba43e52860a7bc27520559b27be8858c73fbd19e0aa24aeeab207	1689438033000000	1690042833000000	1753114833000000	1847722833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x2edd289faef39960e82b8fb32b33894c82b98324f0d765d85f80c97b7372fbcf3ab67d66b639178a9d82c20cc8b7498fd36eadfc7f00fb31c11f4dd30e11575a	1	0	\\x000000010000000000800003d881eb649cf6f724af3fb1494d1c34670d8a83fb52a50fa0a238457f541bf4c7b4694d2b740be250f448ca2dcc3b7c450b21852c87bab5164590d119358cda8a6f143fb2347b1090b965301159a8e22eba841755a91c845d85c1bab80f8efccded6903e6afcd56075decdc338fcb0e468068f75a8fdecafe08f8a3d2a920673b010001	\\x1f33f8b1c70394de836caedfb00b9cba95f297e30768933367de2e509f436350271b2c6d550818eaffa30b6b559444ff01d7744de78338ef0712d3982eeff00a	1677952533000000	1678557333000000	1741629333000000	1836237333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x2fc9d6f317e687b8d59360cc919a951b4529c66f25c217e63e0f9e27358ef784f349fef4a9b2cb3e7f6e91512a6debf6c43129b2a215923ee74df9ee5e92391f	1	0	\\x000000010000000000800003ba54ca28432d6fccf299fe6e4ba4e94a41737cafc01aab3c4af1247e211f8dc473f7041ea729358966171e0f127e0c10923f06da804f71e1073921a5ad8a253bda3d7bbd1097a9841ced7648d6ed14bb8865e09b389e633f824e79d8b97091d76dadd516e2214df88c886f242937ceb82b9faf7961cf42389d5e13c063c61e73010001	\\x2939061ea12b0ad3c9dd6878b5adabd628e24cf153ce084e56f9bc29813f1ecddfae74dd23ba05054b0a7a2b6561068895f5a9362a04c1afb8206bd170ae4302	1666467033000000	1667071833000000	1730143833000000	1824751833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x315d8aa6ab7e04df30df9a56ad63474a4cb75202e75fb2f155ba7adb40cde36a825c98f03b4cf4f82808a35ace189a653e65f3aaf25ba737624cef115bc277b2	1	0	\\x000000010000000000800003c5948fe12eb4ae8e0b739ec3e1162075ae9c400b2dad2f8a5d4110af5b05455023712b1e2326a844ceadbeeca86f31ab76b744a36865c144508563f450f57d922f708a179b99467698f3e9f6d7a26a964997daac75df8759db038497f82f33c78abdad07cc91c905c5bc218772ad15b5f7b5ddb8fdb5334cac2beff0a1dc56f1010001	\\x93234e3c77b6ed5b2f6cd1d3eef7c5fad7c535cc6a13835f165b6e4f5669443f9c8ce8bf6e9f6c121e059841a088c64994810b7ab31b70d6572c54435568230c	1676139033000000	1676743833000000	1739815833000000	1834423833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x343944a70690beb97a227a602059268a80712637f06c9f843041c03463b3fecff61e41aeb976f8eaf7459699cc34317f7c2abd889d2677bdfe560a6931fc3163	1	0	\\x000000010000000000800003c526102025d86cdd161ead313e5e0f053c19d27c19f2961d197b70c1de94ab252c9a234355df697dcc32c6242428e168f72dd2d10690f161371aab59e5db33144db44d2597af9c00653ea4528cdef6b2c4bcb83b28919e6f2440867f8c5d296357b2f22a6d51d74cf6f67f10565cbe05fba2c9f7a55ac408eb991fcccfb0039b010001	\\x80b5a58f4e9346f8dc3fd6d62b181d643f70e0e8ae6139c687df0493fcc169d9343c395a566c674ef475558ccb5f39e0924f41cff9880f9caea6f86184533503	1664049033000000	1664653833000000	1727725833000000	1822333833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x36418d970ff1087384d73a346f7b8fe7c37eb9dc1a4739ac0b9572889e20339b4158d14ed1661fd3c84eeff2f83504a980d20638fb7724bd9cf91cc4e858d4e5	1	0	\\x0000000100000000008000039c374f26862a86471de80d57875327fb2f453dacf16e59588a9a2f9be336ce078554f38bd98320616cf10edc456024af1e500d75f01829455f814131ee325c40c4fa9c32ce1c891d876bbfbe1877709c13dd4828805712e8600a3f62e84ab392c28e241f0ce02f526b376d73cfde0cc9a0042d9de99129b8dd3ccc2e13c574bd010001	\\xc2fc13448f870e9636ae44f0c549fc8cd58ad494a817ec1ce5d7ed087c3b358574110ba02ff1ade20c3445c5a8256a33598a50de769936aa1fbcef7382482106	1681579533000000	1682184333000000	1745256333000000	1839864333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x3a29d6a338bb60e1420daa74b0bb345a498e00f5a4b4cda7e415092429e8fcf82e112f326a0accd6fffdca6c862b5c369ba1277df60b49e616874f7d22e3ee61	1	0	\\x000000010000000000800003bd2edd9e1dcb922a4f2ee8891084065f4304b6d02b8bdad576fb33283f3d763d35dd9ff811d17ed1f6cfd1b31d0b1d963f2681f443b55d955327b843f0b2de187037e9ef48d34c3fb83fe0e43a3499e5589c66ab23a1408c377901faf79727f6ffe1a074dfe74d625cf0a03bea2cfbf0f220013e42561977cd5c68e2b2e3d66d010001	\\x66bd9b6fc82bcf7a651a73fcb049dc50a50f8e45e8a7abab0cbb332b96cf63930beef985fbef95d17d85e8eb1637c1b12c99555c6dc1c42d828f106866c1680d	1685206533000000	1685811333000000	1748883333000000	1843491333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x3e41066035d88d11ca426353db4195ec6b580cdd36d2300475e6f9f2ef157b50a3be98793485a4ed7b0d535ac8125390dd2292b5f2fd7be3fc16b48914edae35	1	0	\\x000000010000000000800003cef24e77ab8f880bf982ce06f668d4e005a456e1c32e13803c46369d7da42b37d50734d5573a8a6403a2a833d7ef48d34ca439f39ab202ddda20913df49fc36a87e477f16dd66068f57cb259820760d255e61dd25bb83ae638c9403e90a92f3d2a28c17e4fcad814570f919b758326c2369ef6dc4129409ad294c61ad08bb29b010001	\\x5179da9bb5ded40c40847d53f35e9ca5e477b4d62aa0c30258738c71859d5591596f084c22df024eec0df1efabfb1636d7c045b859973ac5fb8a4c6859b1120d	1674325533000000	1674930333000000	1738002333000000	1832610333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
147	\\x429924e3d996d941925707cb2c80ef2a74ee4db0bcd42a326618446d875e8bf201b0d72a3d0f15e5d2d1977312d575a64f62cdf8573905550bc4fb4e5ec25b55	1	0	\\x000000010000000000800003abe8bda44c3c2ca043dd9d134195e046e947d14a958c8ca3bfc738081c4e5cbe288cc72826aa49be3a885d11e077000a86ae1a8524285f8d5dee1900ebb147756b57c78db0fdf5941d8beb0c832638bd3fe4e88333cc82a2af21ffd529f35b67f231aca81af7c6c6be9bc5bc702cf8c95c5a137126276fa6d0ef45a855874383010001	\\x541613d4502998fa1243f9e273298ab111922c48b1d5f72e387709dd7518512afe39cf20a2d210a59da129eed69c7531fcd87b6fc3b66a8a2d5490f9e578ff0e	1687624533000000	1688229333000000	1751301333000000	1845909333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
148	\\x47bd6ca4fa00034a84c56331a9c203daf5889c2b9aefcaa51e0fc0345c4ba4df20858ea083a399f032a22d4d7002a4f9f4bcbe2050d05b99148a0a2d5fab40ad	1	0	\\x000000010000000000800003b53ce5ee10c8d207b920833a1be24186e590efa18d7b23a10bfd4db2a716491e2ea8f128b1718a6851e3a8aec3235702b5f7048db3f8dd2171e1522792ab9fbf5aed52b5e5055a2baa121feca64717af79181ddf870f0abad6402f5e7320e51049ce6ca49a7c83525910741f5fb8ceaf26975eb2db4708ec027fe73da1c9bb13010001	\\x8666bd97f88c977bbc12dd2b61ad6f21956874cbf40af6c9257e521697406200ce810e8e0ce2d36dde5c9ac41ceddccdb39fca752c143557dc583c2e9223b202	1682184033000000	1682788833000000	1745860833000000	1840468833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x5015afc654c5c3b7fb33da4d64af095b6e41b62aa478c8d959e61dee27ca73f3156bc4ceef57374765707f6a205ec9f9ed93f6ded6b54b6296e4946535c5d219	1	0	\\x000000010000000000800003c60b5a8fea2f20b20a1a3052526e14221a292d7d74592ceaf3b00685980d5cc7ccfb545161d7b55a4389c42363635df32b15a6b12a9071be27f1b65bddfe3cfd8defa93728abe2a7acedd0ff5f61d0c99feb7365a1797b0bb3f42e40de3c04fc16c13e02d3456538261e4bb036e8a614b8d6ff9e7024fd86a2d5b1033f6a1063010001	\\x3ab41c7abdc3e1c69f1dd30d3b4fcaeac4c03637f16ae403627b78125bb41b6b96dc1cc306f029366e30b24673c0199fa19f3c06d2d0996d8b1e6079881a7908	1675534533000000	1676139333000000	1739211333000000	1833819333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
150	\\x56bd9e30190600159bdbfdfe6df8fb5d41c6a469aad53c594cd40a69bce9e32a93a2eedc4b9a593ed5d87a11c3c7025e7ac4f4813337e59a1eb9e8eb5aab2d20	1	0	\\x000000010000000000800003b0b1acd3a6b5a051ca2d8f1f99c3998a087b68616a5772e6842740e853068d1b3f2ceeb73f344f00b4f64ab4d456d179dc6c7e71f21a0c6bfa72b819ff2e65f546e653324d564f537f2f290d662487d4fb1061f202ccab1b0c20208ac65b97812bd0dcc3d3c814d8f78083bc558c4282cc3c59e416cdddbce314f12cdd8f04a7010001	\\xdd7ceab2a0c1f169ecc15448643f29503c6adc4254f0a68e12536f5d88262309f93c9717eee7e03518607d7a3b42da5d8efb4ae667cc06a959281fa6d991cb04	1687020033000000	1687624833000000	1750696833000000	1845304833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x5735d8978c428fb4bc9de7943f46b43d4f34637a80c7c542d8d0abe8a8da2c06ed058663dc718fd8237632516b8ae1eb43b6374355ed4413d7553ec97df5b5e6	1	0	\\x000000010000000000800003b2f9df6446f7ca11138a8f62cf583bde74b3ac85e173f3d30a3dfd18b54f5e763c6f01e9dc053fe186e74b426e33f35b2b2a3a0f4ce764a5780f49f2ea4466179a8a020f3bff7eb566b4f8994a097e15f311339939dea0946a54814949fa9cffea60b4f9189d928fdb31879a4185835872668ea816478a1712a2fce4d079bc57010001	\\xb4b1e63af987d24ebb9671995f7961d181507a10d3bf3679e5efeebc0a4daf81e0c2c8846b88248888db8d106175400474592e0e8bf42af0c57b9905a6796e05	1676743533000000	1677348333000000	1740420333000000	1835028333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x5891363f9e70098fcee22ddaa0a00bc4b020a6e0ffb40fce4b802094cc002ebf2da5f284cca4a4a21900d1a23606815b0dd0cf7adc59421becbd9b649219549a	1	0	\\x000000010000000000800003b0c2be65eae20a6da00206aeb907ffda5ae985a4dd7a2a43fc922b4ba9909006b409355d935a1e2a6294a34dc70dc542d63ea9e527b3a1f5a2f55dc58a83543005c3d2064482d226d21eeeb46b2a9eb5f14ae110aaaa390ff82bf9da10cb46f18996a1d0489ad896e403c50a1e40c5b23a0bbee839726709f6e4ff78dedc3be5010001	\\x7f028375592427a2ccaa02d193ea8fd9b8dde287b83a7170add4a9f4cf5b34d382ffc5acb506ac00d8832993081c6a000770d2c53fab78af095ecbdadf602b05	1680975033000000	1681579833000000	1744651833000000	1839259833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
153	\\x5cd9af3223a43106342b950bf34d6175b17b857d0cc38c4e19229c389e2c6f21144ef2122444a6ec3a2b76bda89af98a6140d91890d5e62ad116bc8cd9571366	1	0	\\x000000010000000000800003a6ac89d685b59d90cc31152699ce5ff4a581930a58dc33c90439c785722e45612b2fbaa4837beb4c79dad66268bf7c71a00478bd63070a8e56cc05da83cd5646c39f66b9c4770d6f193504e71589a310c8d75a21e50b1aa49c4d8cda8a3551907ae0c7ebd1f0594f35df05742f3a7e9eec34fbba055cfab7917a0efef41b06b3010001	\\x3b3efc21521166614850c4fcca96d435eb9e865a1092bec02a3e7cac11e842be5113c747a407563c00caacf48adee3abdb640dc983064d5cbad31af3c542b104	1680370533000000	1680975333000000	1744047333000000	1838655333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x60edc3583565ca25937217a95d91bf235de28ee1775e54856c20b1bb164e8fc251a914986e61411285782dd41edb6d922b72dafa6980e68b73b678fd32d91093	1	0	\\x0000000100000000008000039264e35efac5aeab7503d8fff4ef3cf8ffe2345d9191cc650b5c4792df4ce47512471716472c54977ba5e1852cc60d0bc3b3f15774a40d99c51fcba3f290fec06deb97ac2864c748d51590a48972a7869ea728c778766b3cbcb2376754f93a3daae6f380f39d21929c8626e38104658f9ac329c063c99e739681617882f34d7b010001	\\x1afad6ef46f8eb940f7d1f3415e4e641405af2e2bf9e394b3e01ae83ef81158b16f9fe7bbcb6fbbd5fecaa77443518b09a0ec220da17bcbe8a313e6297fe1003	1664653533000000	1665258333000000	1728330333000000	1822938333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x61e9414693f28e3d1eddd6322f03f3992fe3d3bf70b21996f891e88eee41bd021dbbb63acc2860c178660eccbd1bf585d5604417010b4627694800d50f96fe55	1	0	\\x000000010000000000800003e2554279a7560fe8abde90e8e9b3725a17fb1de5069501edc4ab987edd77e4869be7f11f62f2b64485089f72aeee20f8f94564d4fa4c20b25e91814a6edf1d8cc8fd887a1365428bb73fe2d7be02238e7f8e3fe59c017dad226b925fe24440f94315e50157dd6ed18dc81c15eb5c41b984b9e125cada12c85330136fdfc73c77010001	\\x24d036168864f59efb1a7a42e74a34a6792c746c455849c9cacfbdac9e17a409bbe28553440796357021eabdbaaa2847e98495e4014998576f435240a11f5c0a	1677952533000000	1678557333000000	1741629333000000	1836237333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x62bd6e72a00b995bb68d6922fd5dd78e45523ef0f9b66c6426e3d443883a0065cf3eb736689ade8f7e90ad036376188b296aa4e49ca344ba52fb02ce59bae856	1	0	\\x000000010000000000800003d080fb5de09d882704e31753d8b3e58745d7ef58726f175da2710645be79a23b9c75ff4a8c218199e11f076d72cd8199bfae55ce822932c3d8b2f5c80a4e0c2f604c8c4c07ddb8c284422665713475b4e101d7bdf0360bb3d7f4ed1dcef709ef8b98752068b407c6bebe062c32db56aa49f92893faa15512bbc978a509909c49010001	\\x71d91bc21e9a135585115f680c7000e518a08183cf135625c8dd9b447d8535f8bdeb4c87c251a7902f4bf257ef121eade874dd2e2952217799d6eea301e8ec02	1673721033000000	1674325833000000	1737397833000000	1832005833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x6481319a0517a542c2232c21959a0738a1c199d25efa5e88a71f88628c4b4928247233666149e664c530000ab7099a23dd33be05a065b41574308060a0b1ad2a	1	0	\\x000000010000000000800003aac1e7c313a31e154c0b3799f85e1c3b0776121d44b300721f725abfa4b728957c87305a6b1ee87cac8930b3d4c56ed84fa710d061f1d701fe6e4ec77c6b0be82b411b83db7a1bb1c8b3d2040500795e07d1259839a3b538f94c52316c87571b7c2b97cc2b88f80efa6b158362d92523abc1a04176577f8a51f3a833d79bac29010001	\\x3d55b5ee8c0281ba27a680c0eee072325f21f3538628dfab489d3a8b685ea06b5b4d39a5df0a7708279bcaa6354c3dba7f0f574f22da9a4507bd3cd627d53802	1680370533000000	1680975333000000	1744047333000000	1838655333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x6531db3389f6e01a5e15b39b33467d658e39820932edfd3f333aea09d06ddfc15ea4d5f5def346233b30a4dd48036d21d21e5c35bebcbae8f317e560409598ba	1	0	\\x000000010000000000800003bc81e961f6f145babc139612fb48c16a9a8bc5c65fbe462a39fa46e3db70dcd9506798beea9a558237af501cbc200c53b8c7b05127680af23027a39d5b8e75e8fce09f0c21d95fcaa2c8b8949070fe2bd468c76fba7a2bd872e95681b6b33202356ea32553d5b5b91054815a71e390fb1c79ef5d48f654da11d3b338134c76d3010001	\\xc6eae5e31b0e0352f5373f28a42c062130ea5514d852f21eb400ecada6da102e168ed6ad4c09134100d9dcf4e75258e955c8ff38673220611eede32eddec2f09	1681579533000000	1682184333000000	1745256333000000	1839864333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x69d19ee2730839aac488ba5ef692bdd17f6781e3f5aa2d350d8d71566c641ad2a31bf996ae4cc67895e92c7a8f622182ad8a3f97746e0bab8093e966051284aa	1	0	\\x000000010000000000800003d2c106ae79ea351be758c91bbfb1ccc7dafc1cdd591a3781898a7fc09c35eb1d4a099ce6046730c481f100b34ec65cd7e4fbc6d3c83e8f1fe4350696ae2baee76a53af76b8927b11a6d1d2512b4fd98798b022e652a2501bcede25fba259746392f4aa7ad2309c393463ac06b300c4434306907795c67dca2c7142101c58d0d1010001	\\x11dcd4d03ff60bad5506996db7aab111841f52c38f8d631a8da321e412f4764219eacb643cec1e93e21c3d17550c27e07507588c84842ac3e33b152a75ab8101	1668885033000000	1669489833000000	1732561833000000	1827169833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
160	\\x6aad2a6db3633e75ba4456d2e9633e141c8e5d785b46e889e2e43cf6d699b7ae1955c371ed9085b4d519c61b00e055998b814933a15c8f8c42bad44e4a012114	1	0	\\x000000010000000000800003f6c41c90a401bcdcdc416fe7421b8807696f8f875bfa45b85321bdd969e1353387ad4b863c8a9681f901c9e555f6a75696170f90a15b923311d779be4c4b809b9ea990842b24102e2fe241468c6077354a44222301f7c73e316f6b5d9d534040dfd58073937fbaefb8260d42b8c1fed32c3a31bee08747892bca0c8749ad9c2d010001	\\xa2ac6ef5343224f2389e8f981cde202b7dfc20778ba52055b89d71b0e9387d9f9af3637d9ed8e4ee3b8009e3d302db2d5ca3073f676e9a3b41f7a9135acfba08	1679161533000000	1679766333000000	1742838333000000	1837446333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x6bb1ea5b54e76304393034311bcd62e9eaf22847944badeb8b15cb778da71c934508c9f793737f94b2b1378f059ac956217151ed58a57642ed00606b72d89fb5	1	0	\\x000000010000000000800003d18de13c03d14a5716546b263d36ebe4031626ec9ae0a8d42307741f1a236e05408f7b010ba86b990b19055bf27a065ccdd4fe8330eb7aca526517b886abf803437e26f71257fea278193461cbcbc1b3dda4fd861c58366a6f66c9b1c3fb5cb681e77a8edd9f1bf19982a0c045450e7b18349abebb870a830114a57152504a7d010001	\\xdac8b8800dab9acffb643e60a8e798b7e1e7b54a6f2f5a4b473a3902e8d99caa683d09583679b8e6ed7fc06a3e0fa25ad214f5208e1123750b119e83edd38804	1662840033000000	1663444833000000	1726516833000000	1821124833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x6bb57bb875bed5ea47fb83910415147e816e38cebe13306c66f188f141aba8ed57bbb25572a3bd9fedbee9206f47a09aa212c28cc31eca078fb86821ee907334	1	0	\\x000000010000000000800003dbdfe650e3ea75398a10c92aeeea7743f1328bc0b0f8c0275d3039b348a861502d942f249ca6742d7245d9c2c7d9d3bfffadd3dcf6df6fe4bf17fa02b31bf7b0fc830166fb571b5906492eb93b1410b0027ebcfce6de41b5c9b573bf82d0e395f00ae080a3a48384b24826267e5f2b39ce36266629cea6dc07d73df5a9d9095b010001	\\x2b7eb5253aa94e3d64ae5bae6ca9a840e147b644c62497ddad6a34eaef5c7e538b43ad7410fbd61f59807e138358393865adc6075ccdfbf725be187167109e06	1665862533000000	1666467333000000	1729539333000000	1824147333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x6b8def52a0f2dec383d26f758c81fd68b319ad435c385467f5bf67356400b17c7307f50050100d0b203a909d8a0a926df72b56b1ede45d08927440c236d1a723	1	0	\\x000000010000000000800003c636bc0c9a6b86cd952f3dd9f3912cfd14ff61c0d465d611cdc1f1f7a5e6076c6842402dd48c44162883c5d6c63ae923b3f418d9d2f0301d69d88d6aecb1732d7cfab836ef07a6dc154cd895d19d2b5ff62b7757458608b0ea3011cc98c90c61732d82f116d2f9bb5765d2856b840ac2b48fc75bb45ac3b70a44f8ac0db5dab5010001	\\xda6155b5e174f44a405907bb5e0b71ff22517dfb6a31ca9453b08477f25460e0ab0829150f74b611f17758f6adc6080d16739d8ba5aaab38ed9b2b763d6c8603	1682788533000000	1683393333000000	1746465333000000	1841073333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\x6cb90fc50715d18072b41495127d86e0ecc863be79eae7bd364c4aa7fc9da991c1316a67a885c82ecba99f0a3abac123953dd73673efd9657730728556fbfb9c	1	0	\\x000000010000000000800003b3dbbb3416c53220aa9b40f77ff1468e1d3693c4991b4ed46aeb72acc4b530d92cb0ac33c3a638153bb63e561e14b7c4c2f9ebea128232cfeaf897c2088ebd26e04a6c387c78c1cca857b5b4ec7819275ce319177b15ed7f95a5cde2e5e292e3927f563a494bf8e980f6044661574276b468407ddc6c2f04163f338ddddc073b010001	\\xf2daa8bee4011b41b867802eac687fd19f5d7fcc5aa2b45a6944cce44b7aae626c29cd91fa9f9af28f33801926a6659e5d8f42194d3c07096af1547df856250e	1670094033000000	1670698833000000	1733770833000000	1828378833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x6c6d09d0ea4b7fd3901182207c3cb1c551e610a344476c16ef47799d2e8a9eab6d1282c213eafdc8897f587bee4a6dcb2b99ea04d801b8717ac26c84d868ceab	1	0	\\x000000010000000000800003e7764d8648a43ded2f6466a58fe80012c69d6b110eb4db1d238967233bffb11a23f19dc314c2afc8b9167b311c6b296cb404ed38b2c94822ad2f76ff91c6c14e4e1c2bd67cff570d830bd06d1e656f79a042ddbc0b93c3734e875cdb8ea4c8d243242e6583770052d55c15a2ecc0505bf644c6879b53f9de6abf7e32d380db0b010001	\\x1643f6e84f1831a0020d29ab03e1d9c163e57994f015e69606193d0555326d0c7e557ba0e01c9740e83ae2cfe6301b70cf1ec0eeee70b10ec58f3ac55936bc05	1661631033000000	1662235833000000	1725307833000000	1819915833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
166	\\x6c5deff5be06b6a9ae3beebd3d521ffab5c9dae06b3b920a34ec29702f7614170566c91da585b73fccb156ec8e74487e868113e506e63c4726398a099c84b5cb	1	0	\\x000000010000000000800003be4cf8ddcda93f99d19dc496951e2ecccd57086311e45900fd63b24aaffadc2595787b5dc02b0951d64a136859ef1a87ea7a14d6724cb4b77b7b44863f472a9fe905f40fbd94ae76f1eca922a77cf1bde1a0a134a4a3480196ad0275fc1801197889c0525bcbf37534fbca823eff800e9a3f378f3500523fe777527d4a9edaf3010001	\\x0c6e3e868e87c62e7b98cb30f1d6e3c4c6e59251300d7eb1723acda0d63af434386333d259172948b872e02b7ebc19e4cc5c9af4dc8397179c6439655a1afe00	1678557033000000	1679161833000000	1742233833000000	1836841833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x6e1d7ef913f23bd0643c0471975d069961a80d2ea257d79b32a2486804133ac042210f1982e0aed023e59a55457f59ee9b46264a00ebc4df6337c0c958499744	1	0	\\x00000001000000000080000399af9d70a840dcb2ffde8c22455ecbbabaeb8446268039598832f178633db01371cd3ed8fc4e5cdc4bef45ae659d2b3351b668de1c638a7d1e2d0d7763cc3be4a4efc0dc0b486b355a7f4eb6cb5e1ac86cb823c8c4658aa1ba4983dd245c2facb2d0b78bb2b293602dd1d49cfac6445305eb2e5414beaf99073aeeef6bcb94d9010001	\\xe88848491d97e1e5254d51bf654605fef0bc5ca3774dbe0662996c63217c6c274d48cd45ba70484ab962448e6973085e100c627a844c8e3402bc5e710e1eb90b	1683393033000000	1683997833000000	1747069833000000	1841677833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
168	\\x70090fecef39f393f06bb14183f49e1c58ab74bb2da02b1c5d79c1f6a0348ae8257263c0e8fbd66108432139fb20dcf3c023171dea1408b5aeb1047e6a8c6487	1	0	\\x000000010000000000800003c85656196b619a6db90c71ed3a199b58fb4106d78767b5d653be3a1da40717a015708e11c7adfabfd96f70792e39c466c5400d26adce179646c30d7e2227163242bd8d15665126f23763015d6000fc98df740454887dd4560426718ad46532d0a5d95c7cf6118925b0560d04d0358a4223a5bb0f3f370291f83821e69eb34cdf010001	\\x6d9f275c1fa45a55b39fedb4a33b14fb172271467729e47a06246826aa8ca8b6d8171db32a4549575fb366a5267697dbe11a419632eb94d603a7f0ba92e3c400	1689438033000000	1690042833000000	1753114833000000	1847722833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
169	\\x73c989da4d84c9da194dee20eae53b821fac2f3f6e3baa90faa476c4698fe30fb870b344d5499de3e675081d1d79fd25cd8efe5b7f36c7dfbea77dc7a16e609a	1	0	\\x000000010000000000800003a6af5b7147e5b81961915ddf847c57abdf3beb4b6b9338c2dcd276976b8c70bad75374e73942c87fc14cac73c844278012938cd82fe526c0ae61da102cf7f55192e1cc8313701f7b4693f73473baaa680f03347998c3b53f6c352a1a8f8fc646ae4dff544e238995706850768d220b58a95149b32ba90afb27577ea558971ded010001	\\x0607bc2a916a4792c926649909b3b0888a7487938d2e0abf93f29cc4ae63a92bee73bc434d1cb6e540c62db25bc7925c7005dd55784ea182e474a8382d279f08	1685811033000000	1686415833000000	1749487833000000	1844095833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\x778d00e42be7adde28e9be86d36562a7f112dd18643b775c567d705f8fee6880563307050ff448d3f85ca3ab188bc0246bc2a2035073c9bbeb9e685636775f92	1	0	\\x000000010000000000800003e5aaedc250b16411a9319a07286989a8abc36970edf458655d50ce17792fb90051cdf21889bb07b54f90bb655892410c948b18b23438c42a3f2c2bd0ae0136fdef3f182ded88506a7b6816037cbb9745078feb04acabd293e7757895d48a92c5a48d1186aea796f6a22e70181d0e5a92d67c79473ba0a6cb7b86852b324e9537010001	\\x4a6bb7d3598e2f2aee5014098eae68f031ac2ab197810dfde300482a239ed38fd71413e77e54fd20dca2bf03125a0b3cab14c386e4a9810437b35eb6dfec2200	1666467033000000	1667071833000000	1730143833000000	1824751833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
171	\\x7c41a88279d8f6a432d38be9f0a5c04c876a3eaf535bf27123f26aef13a480bfbd17e924a5b48ed8db00fc8f6713360128daabbb62f8bb10ac9f40d1bbee1a43	1	0	\\x000000010000000000800003f33109d08220f86ea4c552dcb0b39852a7395557a42c0ab8876292cb297a6d46a4a815dddecb37b8eab5488242b9eec1d9d5fbe089d630e51ef81ab4bd31cabe373cbefa53f82003fb5e3a23533ab9c0e8432571b71d1d1d4738cef14e7ff7d100bab5e98488237392322158fce70ae25b2d17e4d76ac473b614a5b580df9a81010001	\\x39c87869043b4832dc5db51def019e926924d873504222224e7e07825661bed6fea83a2f079cf7008fc5549739fe29547273d0070d82d13bfc08fbd75af5cd05	1659817533000000	1660422333000000	1723494333000000	1818102333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x7e855ea1892f05f92fd41844b009020c3632b00a586d1e01090d4f9889eb92716556c05a20fbe105e8a5703030c13802a8756ae34fd12e5a84fdd41818c0721f	1	0	\\x000000010000000000800003d44c5c102b50e49303630fb406b3f6e94b9e60116b67e5b16623617a7e2c5b496e60f06976f47468018287d115014ff1dd7865e4cea4eae2df4fd658d6a8a17027667b54c08aaf7ee2407a47ad2ec2e0cd300c241c4612c63d839ee4005806430d32455bac7602246cafc3d7da901b4eb29d73bfb3eaf6821cf241c152736565010001	\\xcee2c012df4da7f6ca30abe568f1b018ae97b814ec0174bf9d20ce976f2a1ed20a33a2f9d319641af67005d24243a6e32dde9b1ce2b96518ddafc1aa6fca9a0c	1665258033000000	1665862833000000	1728934833000000	1823542833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\x7e994d41a9c1e2038324f3d8f5a7051f10aad4ee0aacdad3ef6042fd142a70e603c6d784e070399db2c32a40e4746f1a0ffc18eabf5e5f744898fcb6be30587e	1	0	\\x000000010000000000800003ad4eed22009a22e96eb9a4b09d2d243af7b7ebf880e81da364e7c965a13caa5735775e6011a609fb54ea4ea4fccf40046e002d28d10dacbfb2418698bcc4d4c9fd290050af0b8075fd07453c85dc28dcf11f53029255de65f9e239ce0a12b8b497896976ad667fe40a04f91a11b6c1f2b8a935bb281b642b27f6cd45bc32e8eb010001	\\x3a47a9c50134030e05a130a8705063f09933b6d47a8f87573e19d17b56847959bddb7dc668612394f4ce63e830ebf81f52d68a9a38a04ca33b8f52a67e0ce10a	1671907533000000	1672512333000000	1735584333000000	1830192333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x8051f7e980e5332fce1b9d4358cc576b9441fcbe8456ae1900574da57ca33aa11cc9e68369e93b86d708e7d565691107c4fc5c2663eff0d7bd94bc3a972d3ae2	1	0	\\x000000010000000000800003bbcdef9dd363675e77536e42fc1bee71f9f5a3552f9497ed858ada5911c7e3ad57079876d0a29224cdcefe9e0c33a063b795a6966b803673d59bd2dbd2e7c1d76517b3bc49d0bec5b8b635bb9912334c06f05b6153583e39c139c917297618a745b78ba14e32082e7ef41e539c0b38928534b074dbad57793ef4da8c8cd59503010001	\\xb1983139e5a0bc76895c04fe2881fb062a0c1627f33187b87aee0190049153c225df3bc9ed73248c3193905fcdfffecb9af6c847887f184a6a7c4ec49a86d804	1667676033000000	1668280833000000	1731352833000000	1825960833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\x8125955b0f205c284c10f57cafa4fdab92e748b4a136b051e0edfff183b084a46854481d29d58ccb7ab1ff5bac768faddc520a14b6750594c38461d2cb68b866	1	0	\\x000000010000000000800003ceb2d226625ac8501908e67558ac8b3fa15127027a4797b7a6d988caec4b04e4938820db51c995cda4a5a545c92668375ab9feb393e58ac0b5ef56173da149c3668e6a181d86ce4735cf6776aa24fc6bc6ef6c786b11cd820f15b563ac7f41f43801718c22880d0d2b6393eb3d3a177e3d588cd9c2f87cbe9d53fc8d55236889010001	\\x7bef3411f7c734878d88a2fd1935e3ca782f3df37fba12acb11ee0181ef6a536dadf3a281c176842b0d1840a986402195f2c0e5d253ee93119161b3342739207	1671907533000000	1672512333000000	1735584333000000	1830192333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\x849d4be63f5dc6fc49cf5797a6cf3f334f3cbcbb7aa21076e63a4d0ba55aa297044047dcc7db60747b41d0db7801511049e0f51bb1530a143db6e663d3981c89	1	0	\\x000000010000000000800003b25415338e9e43ecb4489a9429e10e56e68e7bcdb5563ee7eb9296a55292b8ca35f7fb4f3fafaef6c37132f5a92a84680ad052b1c1ec7271f162b41a4087dfeaf2bf46a72a6b1185aa670be7f8172700957821ab37120df8d12a385401a5f8ce67de45076600d0ff8654813cefb8cf96971b8da887e1b94cccc177eb8dd0d83f010001	\\x1224c6b1954048fb0cb5a87c52fec1235e0ee6f5588e0482ceeb19e50e0ee005a9c08845eafc143525c1b7fe91ed5a31dc1df2a2380dcb9e6e1792bc8db4e90f	1663444533000000	1664049333000000	1727121333000000	1821729333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x8bc9364df932fc147426494bcdc687c10f45129d61da6d262fdf3686d0535dac5c8ed055f1d719fe8f8773d03a6dba5b4d19dfc0cae859433f80885e0fa3949f	1	0	\\x000000010000000000800003cb50897440867800e8c8b436bb1867549fcc65b847ecd6734af47be305de034c05a937921e5842c40ed0f766b90e52894087218e86add5d90d8d8af99013ecc71ea414529917208c19e92c67fa36d889c9fff43e0a67e2bfde7bcf3cdaf33692fe2bf2939f9e20169fbeb72bf9b1e9e0d8acf925769ec38194e54373963e2587010001	\\xadc20bd58b2a8fbcbfa536e734fe85ef444a28347a5ad746f242bd34874cf05b7dee9bedf6b199617b73e8eb0b48f08ea3b593f2a3747b85777a6bbf509d0504	1679766033000000	1680370833000000	1743442833000000	1838050833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
178	\\x8bcd4546036f4c080fb31ef8dcb14dd1f596295d957bd75a17cc1efc1d9e7e561b9bddef5106b7ffffec925c5fadedf44b12f066475f9106c02fb890fd463d2f	1	0	\\x000000010000000000800003b0a1267a1574995174ebe07587b9fc0b969c646764cbd0d8e17d16d95f96281a1e25f1535c2dc35ba1c3fb993cae9c6dbda63511b171611a2f38184cf4b8008f61b46d05a111b14d7af4fdd3c0a320b56b4ce74f4ce20baaa8d11aeedc60e2ddee03186843d6a4c10d859bfa4aebaf85bb848aa7a927f879d0b365bf85b3df63010001	\\x4a3abfb77548da41acc62eac7eb620e61ddee4fb8256385575e94d1f2c3a6112708b700cee66d2a6403d2b2be96537d27d169a0430185fbcc4b98d948cf2860e	1671303033000000	1671907833000000	1734979833000000	1829587833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x8c9d25b52f7e3c2e4742c2f70915e770a9782809422fe63da79e5d0cf5f07637d1aa866bae373e409c0c824d81395be6511c1c79fc402846b9330c85de7a4ac1	1	0	\\x000000010000000000800003df7eca7794cc3010d20e30b9bee0a2b8ab4b059e9391eb1c4c7ad275cc875e789dd62b50f25d214de310c4aa813b21c1a94ad76084589dbee1cf52fee841f22f62000608c18efd49d1ed026064604e824fd0ba96fc20c6aa92d6d494002ef203d80e6241cced5b62bc30147eca9363ff08cde04b0f2e2b89c2505ebe692e0053010001	\\x0d357aa221781c2cf3fa670904045e3becb5b75793b445a5b2fe8eea53a7967a1c66ea1097254efdb62544b995af1a4e150e72df564c0031a91a37a78cc3de0a	1671907533000000	1672512333000000	1735584333000000	1830192333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\x8f0d14b496fbf3fc6f0b527c83c4e9b0f74894760c12119955e9b955c4e69ee556de1cd33458b17ead84f3e8f0ee9be9ecb9cf286895c7caa231d1ab947760ba	1	0	\\x000000010000000000800003c2cb01c8835eb2bfdff3ccc6ae8d5cbd76075d27c56659135a563da29333343968276fa0ef23554284fe88a209e6c8f3f9c2fbcc5b350f5a5b7c047907d69f31888630f4593c4484a465de792cb84ca6d4221e3d1d7a0423ad786309d6542f322c9eabb93537bc4ad42872dd71afd9f111d1a20ac17c040a6529ad4c8e2a0ecb010001	\\x9a42fadb850961c9847b4557244cf977e0db95ade45f19bc72b7e29f18edfd8d6cc668cac497817083abe04fd46fb1f9f226527ea5a60ac78146a3c9261e4400	1664049033000000	1664653833000000	1727725833000000	1822333833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\x923973f170832327e485887f4f963b637c5bdb313638541118ff703bd745388fe9fff53b34554419da16bdbd543b815983fc335ce2ab6cd7fca45cf708923414	1	0	\\x000000010000000000800003ddb22b426023230dd62bb65a5c4d8ce45fd06dff152d5cb430a5906eec63b828a5cd205263a6f17625ec56cf64b3cebf54e262c6615f57e5678db9ed2426a5d00553421a659b8387d1a65f5bf23e2142d1dafcbd04ef19dcb469225ff5a3280df7d4c16bc1fd611379041486bc60dbe36405f46219c03b248298e4b3978ca437010001	\\x8db69d23f723e128d46fdf70301428178bee8fd376e441f8029f8339df74512ca5e218ffdcc366c5114b7f370abe333b5045c003d8225a3de6b3148c26f22207	1683393033000000	1683997833000000	1747069833000000	1841677833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
182	\\x93bdec366a11abce9687535b5a17f1b3c148b26537f7abbbb8acddbe4ca603d1eca6f858faff7b8082f8c69a7771860726f67b5d7f313ad3d5a3e32d0ba47627	1	0	\\x000000010000000000800003d6f96e7d4441c7846a99023d3b5ca02a97636da45834a319df6991a78d61711f24f32102f10f7ab4bc7ced650dc4a7c7b9663c71dd3e84b9e30ab88819da6e316e6250371b5708599687bc7b7bac4a48d73b8471c33ee20970d1f8213c51e23854b0c74d2e49d23cbec196e48306002f24c24df39bed264fb66600b050642631010001	\\xb92676056bf4a5ed7be8717fe203c230d11361a40f43e2c3d6ad9f7fdb0bc8a48f3c08a3495fe51f80eb53919b51c1c665ca62f283dfc645496fcc6744971004	1665258033000000	1665862833000000	1728934833000000	1823542833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
183	\\x98015e821b5b2455395847c644cded114baa9298d0592230185cebb04d9e746db12d9ff5cbe36aa3ac3108b6ec2328673d257aaf15c0ae41ed510994dd33a9e3	1	0	\\x000000010000000000800003a5efea1291dc3ba952cd44b981c839a9d289e811407a4d47bba9ac2bdda20cbf5fd8bcb5a0f2afd74dbed2239bc8778840ce39be6c1014c38850edccf2942de462463d6ae8ac60b2a94aa313b04c7dfd109b78e11a118b8112cb08a8fe14869e6f07749b3ea64ffaf0b61eeb1d07bf419a4131c908e4dd778c412c9e7756edd1010001	\\x458c9e35c872d5b6344719c47b373a46f8d3cdaf22318078722f61cbc860890edb66816e6d79011449e306b088447f28ab6ae83f8007155e400ad3b8e2aed200	1677952533000000	1678557333000000	1741629333000000	1836237333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\x9d41f7d460556c7f16706e85f4e5bce2bac26f80fea684f02d974c4c53d350318f234d7a014d6fdb099ed17b16dbfc8008378cd6755f20f91ace95d5c0c2c5a5	1	0	\\x000000010000000000800003b2ed651c7af6ec293142a4b9673ed0d87ceb2c10aa7a33b066c5962575f2860bff899937f30e8be7a3d059207582a663a4ae22c51c70df034860c4f2f78a739cf837d1c98ea30dfa4a2693856b4cb303d0cba6166f22ca238d807f17ade76938bdea6990b490d2f91b412f80659bad6bdc29652d5691f97bc5ac658ec176681f010001	\\xa17b3481453f4e2815cadc37701e3f34176c21fa213aecf344675c3c80ece6697752cd3f3c806c6221cd82f039c43e04d2d6470f58763a572e32961d3632b406	1672512033000000	1673116833000000	1736188833000000	1830796833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\xa11d16a230bea584a5539ab83117255c39670ba64988019f0becb2472c31957e51bb1fa2c01b56dedd99cf404230c293fb96ba2b68604ef40131d4b1d8720415	1	0	\\x000000010000000000800003bfaee3e44c583c51b3e5752e11d0cfd57f55de1b1bfb8e0e23916a9fb80b7930a027ca17cf1aab0b33a208b890a0c7a05a24d20b8bc1706846e14633867668b6e6817b8f0698e780e8713a660121da25c6d276c55e417744dd6e3bb08056d28c05b6b46c4dd913dddd96caefc187d62e9e1109fc0f253ce8587d1904ac1217f9010001	\\xaa055e3deffccfa625cf095a4c946ef8fc8438c1433ef0de5c4c9c6cc69ad15c4cdee209017b476f83c4c6b4db6e00cd14e10cded0d8bf58729dba9a726d8c09	1685206533000000	1685811333000000	1748883333000000	1843491333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xa1a19b52bc96f0956d1e1111f108195a725d86e9c4e9fd34f34ba2c375b3966c0a7a2e6683c73b3a48f8db732a7b3c1cc4a748c4f46a9d9ec1b7edd7e7a6f481	1	0	\\x000000010000000000800003df6b417a0c3f53d0741b4cdc30cd550412e2106eda9922c6e4732f96e77c017352490eca3e160b0a5d64e4dd64b0e10eb506eb28869ca44aadb14d87937e11f96559d76ae647eaa4e3846a7fa4f12b7d6a926817ab86ad28685ac9e6469f8510b393d7cb01929288e138ff124b1a828c94b2d50d394b30233bdb151f80eb57ed010001	\\x2c95d5281a2525852433d07ece4b2651e4fda663c2924600b3491a9d7102e0db0fa2655b447a0e55f018b73531efd63207e351b0b8152f057fe39259f17d660c	1659817533000000	1660422333000000	1723494333000000	1818102333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
187	\\xa725799c30f97dc8026c7945950f0d47202610ec954964e3f18ca5f463826b686a5e2024da1d88c22fdbb32723c3c0cacb4be8a7554b2875e656e0bc0b056ef1	1	0	\\x000000010000000000800003d31ee0e8340fdef8d39e05d20d4fc21eba63af5fe1122903572cf41ef4e7285e0626ee44aa60ea2dde78568f1c7b675ceaae6dd71424333a2a97c8c20ff4a9614a85f907f013941536020a64bde992f69bc2320b160a3421271e09fe5c475e968601cfeab8628d3eada966751d9bf84788e894855a77e11fc0c032129e3bdd11010001	\\x851cd9280a1e3fd9dd378888ce32df31cc3c899ee500d886b7ab5701c24d945d9accb3b746866fc15333b10083265fe8000ebdbb28454894496756ee4bd2820c	1690042533000000	1690647333000000	1753719333000000	1848327333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
188	\\xa799870adaa21eb3165b11719451afaf39274409cf9705b5b4487a40987016d3755cbb4399ab36bb1e71ee90a8dbfba232d64635971e47ceb35866b08c50bfba	1	0	\\x000000010000000000800003afc9817dfc459b83be082656f763d43fe635b52cad4d44a2f36d4772f9bc673131ea9b5d4c3d87dc6c61d176ba5312fea29a74e1190f08914e51208a1df43947f76d4eb6a20a971395fdd6e07b3f48aacb0e50e2c5f20d0684533f6eefdf87292dae9bf0d6afc77fc536dacd3b9b1b1f63f8b37563ac0e5100bfeeb9aa501953010001	\\x56dec3e456a4a785203b18e68551aa659f283bab372c67e7264998d8472832766e2e18d8141994af763994b37876585d27051c2159af47c76bfd1f213c435b0f	1677952533000000	1678557333000000	1741629333000000	1836237333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xa7252766209e4af27d029bf03c10d7c18403af24055b4096dc442dd8f44c07446eea5ce26fae061656291f2eec38a87f80ad9d1ea06a26ef83d8ce7dbf61e8e2	1	0	\\x00000001000000000080000399539075d4c84ba3e4b9aa3b6e534be6d996362b10ed205f36fe7dddbbdc11fdc2028b4578c3ee820d6eb11890a4561566fdd06f134d5c142bb9c042dfe52d0f845fe95f807a31227c9beeff77226bab0d7b3c42693ab865cdf02d1697b0f0e106c1d12eeea86746d80b745385c1a181c1da7511c2efb10d897193d208c0a1f5010001	\\x3d70969b856fb0b5e8abc77b65e862f9361844959e0c44143156fb96195827ad223e74fadedcb318486785f9bb068be30feb258d92de08f512f4a7c5a2908707	1667676033000000	1668280833000000	1731352833000000	1825960833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xa7191aad5c462a82fb3b072354504797f1d4bc194b998c3b77ea7285530a09730a686767af4ca879c13c730340047592420531988efa4974530a4c4f336a22a2	1	0	\\x000000010000000000800003a47be768ffd1eefbe58d747f6e90a9854597a0636b3d1137b3fc336fa63eadc35aff8123c575d81da1ecbd47fa31c4f3cc847fc5214cbd9e2773256080c06dff19bdb08b615f6478dd7b98090cfb614bdff023b02f9e58f834b355fe429bc570d31de73348ec4397ae8946c91ea2315d22fb5e2989383f92e03c94a245bf5b21010001	\\x70a8bafe1cdf7b932a6d5a615737d86c3a9f00af1c5f85c87451359784a1f7380c5dfe9975a1492df18e9d6225e561e3c7d0fad23ae435e3b5d3fff904ca7306	1673721033000000	1674325833000000	1737397833000000	1832005833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
191	\\xa9e9971ac95b3ab961485b2e4190a62ff075f95bba66d5ecdfb1773d82d0d48e79bea30fa0877e795554f1d6c5558954bae5030d82ea5622937fd0e2ac1e9fab	1	0	\\x000000010000000000800003b49ce7e94332522b76b925467ddb213cc7801e092fe6811b0cec05cb762d7b1dd14c5439ccf7570c9a4a226204ebb0ba9067ec8f2a5a5a11007eb72a5489954f2d313a70a5e6353b6a9288c4aaff1395737ff351ca31ac868b3b29cb1a16f0627f5d17f4bf356d08f2ad55008dd750b5a431c0180fc4cc330f92465a59686083010001	\\x16d9e1b4410dffa08c58a2cbd441d1991cf2446b7307538f8f18b741b4a776dc871227d979611c25840013de2bb2b4561bd81d54cb22fe2dfc301dcaa91e3109	1688229033000000	1688833833000000	1751905833000000	1846513833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xaac9b4a357ecae05b72ba446d10e6f791aac8c1538b1c2e62bae1adaed7018b8f61a184b22700ecf44730e6962364e609ede42073b3e4926dd5e1389f8d1282b	1	0	\\x000000010000000000800003cb1ae17b94f8e09aaf2a88890aa329b19f1ef418cc83c7cbf59ee934a4092e8c6ba4ae9f49b703b16cc7e53572c1662ee3fa3a439d5567dcf07e2f65fb88c68c9f30f99e5c315e988ace435180f89d694ac05328e8842d242ddb731b1980a5067a51172deba325b2b06046c2df1f88130a3ba0f7f2007a0777692a5e88447c75010001	\\x08e429a5dd4b874f9fddfab64cc3d5e2798d1dc3e9ff1aa24f68668f635f5e55ba69089d8133e96ea52a85277e825b2aed709d1352523e52bcfbd9e4e4b02304	1662235533000000	1662840333000000	1725912333000000	1820520333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
193	\\xac2dea758f8d3a14f9c31f3e09d58472ac84ed359db830cc9a07d036570488431bc7ff5e0fd2d821dca7a83088a8d863a481c8f91b21e3a7ffc77dab8c121a7d	1	0	\\x000000010000000000800003f02c83246583af72e02bf48d5e6e3893811986a5452aab254a145f899f1408b2b799724d299a81a06eb713b6953593e987b0285b5c6e72f16c686f1d7b0fe6c7ca449d498fc8fdd5d99829b853af6e389400e94cf0c8f0b57211615e0b4680c08de934e3aedb61c2fe0975b2167da98db49e73e551c8af9334865a68107e0629010001	\\x4563aeeba822e20e1261b6725aba6293c65fe573ce96233210d816d670b82726eae3b247c6e7322e6087d8d59a9ec113eb27c221749c9ed8e37f8a23f7501206	1676743533000000	1677348333000000	1740420333000000	1835028333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
194	\\xade1744b3f0b39418dbd8bffbb66560a621b7a179e44ed699241e41d535b7763fefcf7c469946811d0924ee7bd3e4b339816b38c8e6145492e7897ca197fbd75	1	0	\\x000000010000000000800003c08ecff8d5bd875b7ef1888d19dc40c950cd10cc358686496ec31fc85c6efbb2410dd4e79bf9cf7499c208ae7972405b4b7bc169851e5dd8a96a6f6c6c577a4832ebf47304f2e83f244f786be7c92e0eaa8f1c9b107026f8e828b7c9ed0399cd159bb015dce362a4b2e2546773751935f82ab8c5b5247b8bbb2d57872d529159010001	\\x45090c2a50b8ad307bf24ca6f1d312b21a340c2618d9b447e201a3de709a44eccc35862aa8d594ef44a321d3d7f25748281a95a670e90ce80a9c90b484fae30b	1682788533000000	1683393333000000	1746465333000000	1841073333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xaf1586661579319dda6d61fa265f0cf7ea7253a37633bf571f68c28c5361c51fd88a9cbe8760ec7a0da0cdd8022a6cb24268c2d1e71d1b4f64865cdcc0d590b3	1	0	\\x000000010000000000800003cb632e77ccf2bb19c12bfd21e27d225095e58664ebcba953d2f21ffc3e4716846a3a5a08790290169b71f5f537e8f31a6fbafb69bc674b6d2c945c2b121876abd281b5b1b4b7f2a35b0601c40a8c89c2f8f6fd54fda2ce4af1c5ebe622ca86130f5b79604a7c57ef14808baed28fb8439d1cf7c6e2a640fbd9dce42cdb15e5f7010001	\\xa076851efc8cc0172150894592ed32bc15684ce75b3d5ef576f66803fc9b8c89a1a65015190db1ee846aa94097e4be5a306102f13a06fc27523dd655f9bf4409	1687020033000000	1687624833000000	1750696833000000	1845304833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
196	\\xb0755ccb5cd749352373e1e7a0847d105228fb5d97a7a314d74ec8689122b1825f1af0548534ab2959827c9b92e74ea41228b49e04254523e2bbd9e726ed8d6b	1	0	\\x000000010000000000800003b2ad4e62469d2a5588e76d3e6744a35845a6fd029fcb999728d1acc1b8b016ae1bc9147a16ba85d3de6801c9375ea2ab5dbda711992fd6782f96a555c39aa55af7800428d7372eb10e3e5b456c28d4f83bea39e7eacdda8e1fb2b68f44e7bedc6de6ace52a626a7f54f465d1b5109fae221922a28f5d7d71d13a81c17db0803b010001	\\x3d9b9976d5b02ef871a4e706b20a0cc11cf5792dcb9ecf03a3d49838b856dc9e62c29568550e81b22340af98970b3bc93e8e15e9ef9e4e4d38d42c2024402607	1676743533000000	1677348333000000	1740420333000000	1835028333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
197	\\xb685f078f55381020ae14a34e67d57df063cae142bb35389f00936bf36b1a74c6c25a9689e0d999a7120fcd7f7c4ed7f8e72d6e4ae3336003f945266cd799ba0	1	0	\\x000000010000000000800003d2c6c1d660d49b4a43845d148eb491fae2c19c22e4b2e4599e416a995f2d8259abc44a8deb9e965404f2a4a3e284d9d57eca95114e57be9a716e499c8327ad0c381ab5cbb30fe771e80ca17198d1180ec9dd7805579fdc495ba63587f6bfc2cb5d8505f248d1827ca1dca92bc7e0b12f61d183e6f1dcf285e2b6a1f55d82e3cf010001	\\xe0da8d6c3edd17b92ce4932cf10d707b95cfd056ec33f27fa69cf6623036d74946eddd1ee5db8abbd41c91808a8f27051e166226eab821211e9ac33879e35706	1665862533000000	1666467333000000	1729539333000000	1824147333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xbf11d05fbc174a33d2ff2ac7ddf03dea4c18bd63539142968deb22539074b6d403c74f6e9ac954595825dfb1f44807d43f6f4a96d0fd597eae8290cc16ebfd2e	1	0	\\x000000010000000000800003df365f17bd2e39aa23a41e884782cb83fc77252965f4e73dcc43fa5c1bb9123a53377107e14cb0ce6660d8c4fca9c57797befd76a4682a0800ca9a541043cd268840cea60e918470b7591f3314af107f1a79479d8546507e2c28ba8208fa7e3a6b40e497fde0c296a70dd767bf5b741e11922f31142b2b91f4853a2ae2cde6a1010001	\\x27e5ffa3b74932fbedbea6ec97d0165ad125001fd08385a73d50d32dc7a39990ebc6a63c1b6531370b79cc983ce9d0cf5a153111135b6632c3df09f1ecdf8e0d	1660422033000000	1661026833000000	1724098833000000	1818706833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xbff153c89dc3cc64955c84c9d77758ab195d48c45909515a439607efda08e7027d88fde504d4dd54de74370e58e3b8bdde3dc06a4ebf35f56b077dcd00e24d86	1	0	\\x000000010000000000800003f53b7cd2f915203a1f595d1154f8173f6e82a2aef8598a8aa60068a6d7b9a5e79c1873dce90f133ec0f23af58bdf4e7b46328a89c881da3bece03fa6bad66dd33b1dd7f9671117661fcd551a69cfc73f1eeb0789128c4a3db70c65eca0b89d8c3db4f60392a82d93371b5b3fc41bb2041e7a87d731518e451f39e90c13027ce7010001	\\x35a2e97cd2bfa8cd41808db0cd52712397810a146918f91caf3c30ddbb74bf645aff5dbfcf9b0bcf97814b73eb79254566c53977f24bd4a6ecafed889d16a109	1667676033000000	1668280833000000	1731352833000000	1825960833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xc401b00d63079a3f04976a670a6246a737d1142a74326950e6574cad4855207d699d402e33c0734264b58f91b8e466969fdd93ef85a9177baf044ee96e56de41	1	0	\\x000000010000000000800003e645c62a0f5f84e8f064b0ebfedcdd852843d5035b6fc61f2d8e86c3d0a9531a2a7377c226e101248c27fcc73bf2d83c22b6c72336639eef7d1b8e89f19eaa893430bba663b17ac0a46c7c034a67bd1a54f24272b3af02e561ceb996e53c54d086e57e16f14522423246885f008ec8e7db5d48ce443f07c0be0ef39d3a54df59010001	\\x17ee4a42a46ac46ff955b64401e37c2d4aaef91cf45f877429f09ac64f492a0aab7aa012538cb223ab9307ad5898cd197d46c3bfb535bec7f18481186daa1309	1683393033000000	1683997833000000	1747069833000000	1841677833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xc9a185bd72a22a39409646c45b41662fdb7b4b173af17e8e47cbc9d07c683be9dc5f8f374d128d76ce89da8d572e8d3a57a5c2a36ae1e5e4a9f5ef22e3aa66a8	1	0	\\x000000010000000000800003c4a53e697140dd26fc19edf09401f610e3c7c96dc3d8aa94850f4789df3d5709c272183e7f815f9ddd4f8fe9ca5ed40c7944b865b6a4a8a8a974fd8cd4cc8c2cf6544d27a8fe0990eddd161c2d19b37d02057ca66bbe8b9db3c3dc13600ff1656dc978552904cf4687fb876f0c97b0622f15f5f87532817d209dcf4ed3129e67010001	\\xfcc7719472a1a9be8eb6a2b03c18099bc16e825c262698b8e4d93b18e2421f2e5f0e5568da7a2765c0ecaa735fed7fcad6a0f5c9c5ca9c9eeba726dd80115e00	1665862533000000	1666467333000000	1729539333000000	1824147333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
202	\\xcbc1c273543fc64e869826ec9205ff705be9e333eb1584c47da7140fb939fdf091353cd9791be79039cb4dfd5f195cd68bfd861c0aa9c3fb50c6db303e697c5a	1	0	\\x000000010000000000800003e5911898d28e9a749f0fcfbd68b4ec224ddbeffb9d7f010faa89068b0e916950be1db6f1376a085d55b2cb49b24b40d1b82a38d00da2dfe8959ba1db91548c4db809cae117c9e0d0b901cfcad473c4545af8f8b4bbd7d9f016fe4b9830fb6b10a47780ef04b24644b539df1a6fe041164001902f477c7d222f01018e0336f379010001	\\x0dd61d1ebd791df54c2b94299722afd476cb18c196915c2643cd431aa271389f1a905c59ea8f5b1499f1dd309d2c955f83520c77f2bfb996f72879e0d466650d	1680975033000000	1681579833000000	1744651833000000	1839259833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xcc8d896f97d7779c18591a4b72ab10abb34bbce3644b715e9208e0fa4608890c96e1b9a1e6f4d2e45fab3347d8c2d402e056fee6ee68d7dc1e589c6814f4644a	1	0	\\x000000010000000000800003cdf6fbfe6ed41420316f774e1220dc2534480ef88679d591ea11932f45b2e5d23b27725dfcefeb2eb05f91924c9ddcebfbc2ab30231b7ce29668a4d82f01aadeb3a41c40e502d3d1ed8dfbfa37bf715f1d0516d9abaf97bd3861540d45572700ab1b32dd592e913f834b305965313686580efc3d95dc405d7e600c0f59a4cc7d010001	\\xaeaf08e1501efc21112231ee7af60cbc03c9cb5ddcf63890540e83465542465099e5b18799cd7cb46390b8a6514d22ecc3caebabe672b6dd0f30462b8990fa0d	1669489533000000	1670094333000000	1733166333000000	1827774333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
204	\\xcc718a2938dada4ee4cc6fd3d9d636abb4e29f3d6fde0a75ab3c7ac8cb66714acf8abd857dcc45d8f61fa02b2f9f703e20c871436583125ff5daaf2050dc8765	1	0	\\x000000010000000000800003bb0be8026189910d330de64400c402b0147d0eaa7cb19a983aabd450c0933ce0d271597dadf5003c9d6fba2b1764d265392501705ccc79fcc708b514cc181d596567c9df09f05bd20bb6d69ca28177f2345a2df9862061ac67c58eb950c75ec77455fbc8c4ca328e1a3ea4bebd9c1c9ba1fd521aec9fcd69fbe6c3d8e567ce23010001	\\x54f63045a96d106c502a9f6edd385a184fc06d6228a8a08963971734602710f29ca77c44a29765f723467e4b04161ff87eaebe5563f92767065a29c700e4280b	1686415533000000	1687020333000000	1750092333000000	1844700333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\xce89c404b14296f31512c3c5fbf76422b6b0a28593b29cac64115f0fdef60795c646d29c9c5757748e177e1352f47a292ba5e3c1faba860f022a2b5ff7930378	1	0	\\x000000010000000000800003c096ec5edbdadd25b0ce70d6140a7d09b0f974c74818fcab4917fe52c2fe5b005be0229c8e25b7d87f519213acab1be696a0e0f3bb4e39f8918c4d671738ce044401ef818edd7396c9bbecc6f28c422671b19bdd4ea845cb399c1132b6c7f6b4fb229dae92ac6d523e84e62179a7d1e5f24528b594d04712308a2a7c89fb2d95010001	\\x9040b192fa0637b851805eb4bc5069b41208e4545020d0e66bfb950a148e331c3b4c1afa6bd3637b742ae8228b79312fd8122b860d4ca553789012fb26825b01	1687624533000000	1688229333000000	1751301333000000	1845909333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\xd025ac03fe6081a7aaa6e2ee68e25d6a526bb4e827424d98815d9f306d3a2a10a2f22647f7d98bcbca4306f6ddf9b6ad520b79c680ab72f09fd4ccb5a8822993	1	0	\\x000000010000000000800003b8190ad1913f5bcb938fcef3ad3025a539307b9bdba68be9c17669edd9ceae127a3b7bbc744cd306743adb8bbe4f9aa7a21e4e9114d78f611c8f348ed7f304ba5e759e651d47c7879ff84501921b4ff2a49222737b9fdb9d1b3cce0f3c76c72a62d194adac4117f62b64066511925ff9bbbfe73953fcf6a45c9ee5f4ed12c0bb010001	\\x598e5d206b56db1b5008a319ca39144a6457acb098d23398903b0edfdc7d6057da9f902d87369b6d2337aca2f385e48048abacd10f513b121196325fcc11f604	1666467033000000	1667071833000000	1730143833000000	1824751833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\xd545652ffca766895db17f7cc4e74ab564f328993bccd4d7080fbfd5df99ece8b568d862d0672ac9d3bb71856c7daf3a843cc549135d0ae1b737035b849e5def	1	0	\\x000000010000000000800003ca53ba5e7edaebe9da57912a1133d097c1c6595660a9782132216f4263a03b3a7dc4ab02c59b734b9fc77b8a79b544ec0362d4cf7d97e96d6bf1c544580190affb4b07d54353cf65b46ad706e02e42455a7783cc0acf2cf1be13c64418efddbb20f5a2cd4867bebd3f6f24b8f2c5ec226a3ad55125a7f51e3fedc4d1f701f007010001	\\xc2bdb6654e3be8acd8d32a1f9c20c7aa92550d729f6d0869dfb90d7d4cb0c64dab29bcd51d7b85179f874c472fdb6a722c281b1fb6bc0927395210c1f15fb10c	1686415533000000	1687020333000000	1750092333000000	1844700333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xd829a059fe4cbec8ca0453d2e5d1eaa3e2388c2b745891b41fd2cd800dc568e2de5e94eb04404a5683efe6c300938132c8c24a2b7d9ca3dd0c27c0c94d82ab5d	1	0	\\x000000010000000000800003b2b67770daeb7d05d7ed3ec5e5d0ee979bb33f43e9f843c0bba92cb3b22475e138522ff091f7197fbecd5c986676fe15c0d996933b8416346dc755944f3281815452f0ce10912e096f0c163d7e30722d820784456f507d02732bb2ee4c43a181e904b1048a286a471a2b0dfc91b61eedf7ef4679939c8256c050f1ed0e634889010001	\\x6ccb5c715fa1c7c45645821911b8f043c398200eb85d367c19c0e1807df78f94f8b8246e7504dc1f87fa7c099ec21ffe2d52809ec1d27904caa1b2db41ade00f	1676743533000000	1677348333000000	1740420333000000	1835028333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xda91ce233061335873383c896f2cff0879191b824f4c192a8f887b2ba03aa94ddfb0eecdf6a4ffceb34ddf54fd51479c6622bb07870e94d5700bf76bde6c5535	1	0	\\x000000010000000000800003a584e483223fa55b5425e3788cc0dac07b760fc16af89c051ea8fd30385f32349d0101d12d5dbbefa4ce53b33d4e26bf1cddc09394028a7191d745671152823ab34e4a16c98398e5c3e92eb3871c07ca7ff6b23b288ddc234c4d37691ca39788b48530bccb33a42bde2e1fd81eb525d4ed23c21bd374948d0f727507492d8c81010001	\\xc9fc95c66bc59d5aec808b8e6716307e0084d15fbc6e51383b1ff428de7d6f264d669eef89e4404f49434d05d719dbd40e0bf4119889ec6654a07f5fd092a50c	1681579533000000	1682184333000000	1745256333000000	1839864333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xdcb941368ce5fc2e472f21ab7e5b331a27d553ad0d95650debc00b1b9a297ee3b1209cd41cb77f7b424f2a38245e221c84e32b61d865a262d93e12a82e276a55	1	0	\\x000000010000000000800003dd4a31c497a765bc0d222c5907394d85145e4253499fb51775f8ff6b6e46bdd463859dd4cb6f81bdc3b703a1fe939e5adeb34c5b692c8f4f5129ab1eaa96a1669c624da6f0741d67935325f219c0b952431eb6b5558fcc558d7941ba1a33b1ecf30ff5333827de9cfda896a5c1b42de7164553aa44646726f950a6f52ad983ed010001	\\x9146772b047d380bd654c8e1b616c6bbbd64d6a12353ca1febc8aedadae579ba8e6cced98191e442e0a487a70668221cced70a66eedec2ff87386a4e6a5f6f0d	1680370533000000	1680975333000000	1744047333000000	1838655333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
211	\\xe14dad96e74126e2b9f68573800ea7bcfcac54ece3c714b9b518433a8828e969d102bb45a100f3fd6ddfb072abad7b69f29feedfa14bf4aa8ad7255c0b6fcc07	1	0	\\x000000010000000000800003b4c1509fdf4775cce3098a2fd7635ad7edf12ee2b385794b30b3014420609cafa60721cf6b07c779e16ca9551b5036853b339cb8b323df9de3a51a86bed11db19d98404f3f95c9039e05e8cf628a80697db1923bdd982f42a18096ea5d32d00d0530522b87d8d8efc1878dd4bb94c87bc6b7ab2711bce08ba5ecb045edc026eb010001	\\xac3391d93b4aecb7b60176eb2b1fe974491d12bab78eebfca876a6ec28119f845c6bf30d56fd9359094d77c49c63a76e6858ce9614b96251ab8ac52cc2f3d70e	1677348033000000	1677952833000000	1741024833000000	1835632833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\xe53d16150c5237d07ab48d0d92a34929f4fd8908719930ec24186c429cd768b152cf9cc9abbdc41cfc4ffa7c92960f53e6b27814b1debcb1c9ed0ec0342803bb	1	0	\\x000000010000000000800003df89ac8fbae197dec2abdb4c71eff850763adf6931e8005e4707f1895e7e8d7f5340dcd6bbccec6ff32c1bef5adbe4052d4d97b906c7cd21a8fcde99921c507af486d26de8e1574c0bc37c06f2bd0c7a78ce39de7bce8895aac8e71842e3d9f30832ee8d2838c52ee4917a9667d3755418ff3b4a5f3891dcda0cea0004cda199010001	\\x2141f78113ffe2a3d846f26eb703685d0b8c22e505061a3ad378a42aa552feb3f2d195d125be41aa34afb3618c77b4b14600c4d19018f9ff97ae4b2788205e01	1674930033000000	1675534833000000	1738606833000000	1833214833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
213	\\xe6b93802f8eaa29e121572a0c22a453c2da76235afcf3067a8f5607d5bf969fe0eee081d9574b149216fd0242a8a6f08ca19fff6cd9e590bc378da6849483d50	1	0	\\x000000010000000000800003bc494489b16b9e8c9328e42c8f70cef4a95a2c19a362a64b938baf3ddde14b7785f96865a2812afb2ee131e78b64cd6fb696592e14b623238002a2f7fc088135409ed6e225da7543aa7c9265c0c65602a4017bc63de4847fceda30130ad81b02899acfe98f4a020117c1f6be293eff8d7a9cfe9d96bcf530cc404781fd3e4899010001	\\x0d05b107e099694949cc7346a0e6e008455dd42d837cbdc2150bb546d98c56a4dba451c089ce06fa1ec2b0f0e9b13ad3d3d45276e06a508e9fd3fe3af2c49a03	1671907533000000	1672512333000000	1735584333000000	1830192333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
214	\\xeae1fb31865884598be1917ece689baea0ba88490281cab358b1df6b65f720753a1ab1149121e7789efdbd85e12b6aa62b9f02d10c361c3465d58a7dc9606d6c	1	0	\\x000000010000000000800003bf8a2fe7a0a4b249d48774f12418fd1788156fb3666703a9b8550b7046bd7f61110540e50fcc98db86dbcebfdaa0c743343cb16c440fee4ddc651c302c7375dcf2c6b649c3abe64d1636576012610c92690eca4144bc2f02ce591217736569d6854f970d6bb320da8d20497208b5c8208c9d84a7e7a85998d52ba625b38569a3010001	\\x00e241ad16f2afdebf192dd03ebe4e71c946cf02e8cb4505c4da0a85f02559ba160a32a3b83455d1f924db0dbd900bc3a817390892897b8de4dbdf30078c020d	1667071533000000	1667676333000000	1730748333000000	1825356333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\xeb4d8231744cf124ca7f5e387658abf912108d60582e3987c10bd907ac3760b9b416d11217f5798665bd8ba55c8dd4748f1fe140f234147e547bd156365b88d6	1	0	\\x000000010000000000800003ff57da6ac1acae13fe8d7a579d84333ca22e88ea7cdd05193089fc4713ecbb19b8755ee62e7c66858241723b653dc1469d9072aaca4e12a63d8dbcd0d265df4566e3db3d2e7ec22b9c5ea9b7a3578f20cc359ca25739a3c61f3b41feb3f9f1cdd150585fc104f692f8790b530f8549546954d093ae9b47c6fc99921b79a7e35b010001	\\x9d57986b66480b70839a9c98583a03e93d065360a6108d6beae948b97dc029dc766b77b10b98932f24e0cb84f31440b02dc5ab6091dc78124d6c2ccdb2581e01	1664049033000000	1664653833000000	1727725833000000	1822333833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
216	\\xeb25b8062139b560abd704979e35f342664488e5d654d7c8de026dcfdbb3d8be90ccdc106c5573fd4154b172ce48e170681097d88a117705d8ef8d119155c2b7	1	0	\\x000000010000000000800003b00bf4337181a77afbb9b782a7a32ce8a7947c69d3bac26a75f2659b605a8430eff89cb90ca8e7bed370c7bd4a607fb3dc0c32e74d94b21196e0fe65e2f65ea6016e9db00aa2c63cdbee7ad73901caa0657ad4ede8ae8ba9cafa50a9e505e9fe4eb04fc13c6b0e65619b76c268c1febf08572d0dc7c6464b9d3566028972c9fb010001	\\xc3dcb5ac7bc6a1881c8c935fa7de66a9e8b88723bd7cc1801b383e18e8f428f8fb246afb9f68c08f510d259bc921a3d1895f60453cce84b0c38a281c47382c08	1667676033000000	1668280833000000	1731352833000000	1825960833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\xf1e960d0cf2fd8aaee69f52914f100dfb59efe62ecb09347c1c4bcbe82642f75d122baa490cca94bd538230d12ed7193ca1c31ee1bfb74480d8fb334d1fb17a3	1	0	\\x000000010000000000800003bb548ff320eac071be129fec5971957af6aa78b3766175ee58b2f307a7cd09539a94f65c94b70109a720bef7287d6cbdc79e57596635bfe5ca461d507fdca2ca5bce1aa5cf36bb0e4834d2c78f63db03d6032a6591e0029d85a5b9fb16353da0df9413987aa2633a4e5ddd9e5e0a524450b054c537e6f35ddd5e8b2c68b69cc9010001	\\x803ead3704bd209a712dc8b18c45d4126326c5efbf063d183855e69c95b9f4c66120932959fa9a4140aa34236bf2216eef983fb30541ade53f5f2ba4e2a12700	1660422033000000	1661026833000000	1724098833000000	1818706833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\xf1f933c597849c0e27a4e66a9d19a8dff8bdd7f4e83eda7b1f38a7c87594c0bc1eca184ea6e7ef640f1db5c339dfabfd6709c6d66ea2d1f95eab23f12a365414	1	0	\\x000000010000000000800003b7759952d74a285796dd24d781010777e758e2e8b101e74e34d6727b7bdaf758a5dbd95c927fa9e65864c0d2ff5b1bb1f4ffd82daa2a5922f4fd74cfb32c787807e002262777ce7cdc4f2f9321a540614e2f6b4f633d4217bf47fe69342248cc30d06920246af96f7c67a28bbce0e4195a77b7e42b1227579de8e7dffe8b6ce9010001	\\x6af9422d103d7153634c828526db06b38e3bc5335ffbe3f809479472fc96523d42b6fa4065db55c60513b625dc00036201f4d7175fec73b4f045fa561ca01704	1663444533000000	1664049333000000	1727121333000000	1821729333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
219	\\xf56155b92562502eb876b7f77d8151d0ab97ab048bb3c0fcfeee3c3dfdb96f4a9a47e42047b43e6018d3cb4e803a4869c590aed4c9c5a841f85986faf9433df4	1	0	\\x000000010000000000800003e7103be1c07dc3513b0f20e3982c6b8e14a1e8fb9cfda7a76ccec3c054b3bed291bf5ea658b2e5f310991cc974a687e906e67daa54fc8dffc155c39df8412adbc478db45b63da08afb003dfdd243a0b8828521947b7737422b142bf2c7b7dadc19ec66dad9986a832ca873aa160a8907b19475e34d9ba554cbc24a302bb434d9010001	\\x492fc0489d7d09013c180bf70b12b9b5efd27263346c515a90fb2146dae0d54172eda001d9d316eae1dbd6ca8fe07315cf7efa134d245c83a3a73b255390d003	1688833533000000	1689438333000000	1752510333000000	1847118333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\xf9192a4f7879de4796d7460239c42381caea32d276ae4fb893bc5db4411f0af33c9808bee143dead4ff88ca21c13ccc7f2c5c331c8543f64fa9917f5768f8e48	1	0	\\x000000010000000000800003c956bc8ff356f1dcf1de1a8e7b87d552571ccee5a19f43e14a50a4abcf5595783461eff41db10dfab97704e6bf51401ac7aaf29a56f26f5a3f2d8373163258e88f2605a2fb6747d7ad8af5089859c58aa8157638aecf4f92e62d9896c56323497bf4139355f622c0d4dd27284a079d039f10d4a601a6672018b38fd1fdba4c6b010001	\\xe79c89c7f71ae139c659dd362adcd320d08994a2da04df97c84f6b51dcfb5a6ed11449df0a713f13dff1f1a0bfcaca36bb7a4e82b1fbc770c5b740453360d30c	1677952533000000	1678557333000000	1741629333000000	1836237333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
221	\\xfa21a15de388a48dea69d6e517f276c2f3ec730cc84868c0e1e1a89a8fd668c999d34ec027d65f9fd94460d7918c98ab46dc0a000baa090850856231b5e44390	1	0	\\x000000010000000000800003db21b49e8f2cbd242e4b949aab4fc50c0b0d5d3455f1c654d060299cfb39583992749df6408e6afaaccda3a91dfb6ae91db8000147fa0a1436b3ef1dc043ea64eeccb61490337c0ba792ef0aebfee13a47cf7d8451bfbd7a6d3fe6ebd967f40792afeacf63b893620633efdb15a36f988bf080ca4389951fd668be69d4f6c073010001	\\x76966503a3e47fc640f01db71e9af2006aa97a4ea12ba97fbb0ce554305910af7189a06613c4ef11051d8a070736cd4eb0d3f34c17805c996e44a29394631c05	1668280533000000	1668885333000000	1731957333000000	1826565333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
222	\\xfa91819dddb33d8ffafc03975cf20f3f99a2fccbf7ae7bf5d70ee2559c20c9c9d916e62a1964fb6022fb4e1146cbe1d37b2e2edff383bb34cfdf1f9a799e18e2	1	0	\\x000000010000000000800003c89a3e013c512e09cc53e370a8571afbcdd5117a1653750e5e3a4d84e3e1a9dde7e8db48e2f3fb4411d26fa2ba22eddfa612aa9862704d1ac6339936471e745eeac8823db22f7a83e1d17db5afc1aea6147344ecbcd15c70c400d16a239b61228a2621213cdc2dc4b4695e4c1bd04670e30630c8e41239c46c2be3849e26c8e3010001	\\x5e145aeb8f56f64ad8466863791deeb5078d69d13b383736995a2fd46a9d42b301294d82a46c7050ca952c08ec84e5ff78290a85ec9fb5a69f81b7e4bcdf2001	1682788533000000	1683393333000000	1746465333000000	1841073333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\xfd152ac4649b2a0c08860038018524034529ab5841af65f88fd4c6ae41019775a2148a60c76017ef2bd8bddf35b168af9e496e518af70d2295e235e1d5d0409c	1	0	\\x000000010000000000800003bca363d311ad1c745ef02613656403199ebcb7b86e4d09ee28914fe7fbb30b0f1fa1974cab7ec9ed008eed6758dc33b0ac6398bfa914e070c262a6136358509f5ef15ab8440d33a716770565a50b9c7ff1b44a70d7ca5622b2750c6e38a34383b824a6d268279fca666d34dac635afdade23ac2829478b06621f46ab1563564d010001	\\x7b4b37069273c4e41025c7a3e33049d70750d0bb9e2dfd75fba238d1f22630673f515b442ffb928c20677e615d0b74caee49c53977897b5040c418f187c9b108	1690647033000000	1691251833000000	1754323833000000	1848931833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\xfdc13d93201085190c8eb269ab91dfdfb1367617b826c0f86bf7571a860ae0c5f7adb4aa13f94acdddc6ea927cb840118d144a250476b16986fc35bbcc269e20	1	0	\\x000000010000000000800003e03b5f33e9766ed21e46ea8c21a1a04084d8160fc0b842cc693bd285535ae99bf6cb5652c5b193128ed23707f9e788156e08662841d98bbb253a40de2c76b2ebb6efc4507d3ec66ef3d7a9912384b01054c784b014501918b12e50de22f20339507931e209e595b072907aebc2ad2d773122aaa3567d8119d236d3d2ad607f8d010001	\\xa43be784e33b8b10b6dd9b664ba7b00bdff46bd19781d9e696a069a518faf245828dc151b095e7d81ad5bbdb2229870e215b1d97d44e0d440423ffeda4cadd00	1662235533000000	1662840333000000	1725912333000000	1820520333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x003eea6f7e5f1b5af6bdf8dccf00048eeb527ca0ce59fd74439c35aa1c6c3651c8aa7f64fc05310dae3618516d9c84b4e57785b231dbcbef89866c5b1cae8686	1	0	\\x000000010000000000800003ce99d35c38881ff7779fc82d361be7c67bf6a9dbd7ae14c1c277ff01392b75ee833aeaf24027c7611e8472774a626eeb3fe65c2cf3a9846f27ba6d6d8e158d756b712eb1bf47c6a9173fe0751aeac6ff6846c01f8af0b9bc2524545c2b075764139b8dda6093f6a3e290a657a0184c98761b5cdf9a4b3ef8345aae5b46bcfaa9010001	\\xd8bc56b7239584e0ac12069627caf85a80784026b605a90f2a6f87961ff60731a720ca08d21bbd360aa9fd610819169bc141329bab5e6ec9f082ea0740b01200	1669489533000000	1670094333000000	1733166333000000	1827774333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x01a6dd607bef3bf206dd1361e585a0fe751ead847c83f0f19e8e5215f31bd7ab1bedf982863fdeaf80002b1b56a5db1e2b0c3ceff391995b9ad54bb2df40aaae	1	0	\\x000000010000000000800003a77101c2aa75cdf9e4f16741aeb9023c775a53041f9c155f99f408a70b3ef0154969f42d13546aa71efce5cf1f79e44a1fbfd712274997063bfe6d40fcb5d5254ec1572ac2c57e8d792613349e5759fa026e1ce4ccbc2c0e13ad16c11af645873f4612f97ebce3bbac3c4e3f3f18e382c36d585072b70e1a4edc0a2a22a7491f010001	\\x53213467e38d261348c58ab2ede4be00bacd4d1b5311b61e90996a5def8e29e9be418e7beaaa601258b4cae0fa05db4a8b40d29c1ddbc607bf0075be53cf5e03	1659817533000000	1660422333000000	1723494333000000	1818102333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x03ce15a6bd063469254a0ce1837804a1f91b48be62ab3bd51411198cedfd44a8acf6e1286507b10fa8d99ef0bbe7dedc6f2767e6ccddda74f912000aff41eaa2	1	0	\\x000000010000000000800003c55065e2f2a9dbb7b849ccab05324070d7b5368573c8de6043d18b2343537715c8924c4adc54f5d67d1a41267f98860beb1fe5dd1eddbf739f2adbc23a69f44789793ddbd4a7789ee6c27893592e4b94330a01f22aa87f07c342f1a58bd280632f3103b21f11ba1ec0f041694cf7361d5b032c15e40a61da6188513c16bd7543010001	\\x38cc885712ffb5f1eaeff76c4996b9c73a44d849822ae4574368b30731a9211c991872c9efcdb12352fe441ff5050b370892a24e0752bbba96193fb0ac3c6f0f	1669489533000000	1670094333000000	1733166333000000	1827774333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x04fa86ba824866e041c46b2b0e2369212f3c860eaf475ccf5e15e60a42b7b457cb489115c2d017ed4d3d1ce0afd8b9b437ae30c480a959b4d8d73dc49d0688e5	1	0	\\x000000010000000000800003b95b7d6fc422b39387e3f459fcbe31aaf4f83ac1d980df459fa6c43e712ef39ad2047d8995249067829316f1663cafa3d6b86d18319b821171c6e1fb5935d59ace25106bd1ec722d1c95d30230ed611d1459248c9caad28433174e2905664bcfb5fed6372ffd0f9a87fe8ca9db64b2c1fbf04092dccfc6772dadb98b186d5109010001	\\x55f0626a0ca217aec531484ea362f215ff38b45da6916211b936735d0d3217bc1616624f93c8602c8bd5643a82de2f0becb9e16f9724e4ecad1107faee960b05	1678557033000000	1679161833000000	1742233833000000	1836841833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x07a64bccc8ea0d8778fb42c334c6235c552b4324444f2a0593352f631c671e517a9fe6e8a2c9a847ef0264fff56b69cc58d26e70dfc9d33834cc5b3c302b889d	1	0	\\x000000010000000000800003b50c9ca2b44374144eb6b9f5592b04a6d645abf94f839ba948ba909e77b6e4b70e523d0f6289a5aaac3968623138fb32d2b6f5a713a621b0a211084a2dcf094364dd4e8c2a7c9903cd3bc42a4856e99ecbe3869e06cc8c4df49626ff6d146f1dae3435537a9246b8a0db5c38800314753a3162dc92148090bb4ac80e983bc1d9010001	\\x98771ea783e1ba3542907cbfb69299e4c4d637e0d2a99188b6a88bb3bb73188aa58cac16607e36d85cea9284e77c5d55aceb694f3b5f0ec4cfa9eb0d569a1a0c	1682184033000000	1682788833000000	1745860833000000	1840468833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
230	\\x09e224ccb464a58108741cc67fc468bd580e990dd78dd6375844ac98270ad1469262f333b9150001ef91bc269cd8ff0fba5ade9629f18d3f1cc141c3afdcb030	1	0	\\x000000010000000000800003ac993441c4ff15aff918886e202b1d9105fe8c0b348bdcd83c35fbfa71b4dfe17c0070f448023a4075dedc92bf781253d03d3d532bbce3129727a26e6dfe736b7489820d402115b425d2876228638e579da64d2aceafa8b85f67615f2d7175dc467a148abeec66efefad05da53127e3de991507b1ec8b491d41e1be85396996f010001	\\x918d4da608205000b9eceac3e026a9d2b320ee236be615b3605cbc431a271e4facaa67b813d1d30e5bbf59359034284bc0d5c030499d0d8362eba0352fe9af0a	1690647033000000	1691251833000000	1754323833000000	1848931833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x0a864e484c02f7459d2bffee0243b6b22b738f70f6c8b9f4fdd0a9624e2d901739ed3fc04e6a0568ee3e1de63f892db4384c9305982df98252cea43100741eed	1	0	\\x000000010000000000800003e4ce92ade15db73879381c6844dc4a90f457226fd597a519db34eec63524fbd851c52f9d3b1c020c753007fcf61c8a3ace906b54c001d1a9c94bc0079519e2835d30181c9b1987be73acaefbcfcd1c145da0b04966daa725e3b03d1c5ff125ad1663ef687c219c6678838663743ab2bb3717b2b35a71af19a5c860afe5569bdf010001	\\xdf7143b11fe4e9a9d5af87468d1c94fdab49de2fcd6ea691383035a6d291033593b4c8e6b37dd9e46069ffd33a05fcaa3dc07452495e4100bc5c61bd4ea9a605	1678557033000000	1679161833000000	1742233833000000	1836841833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
232	\\x0a16d7d977f3fec1f81374ed98e0d79c3ec32e3c6d0fdeed24ed4583fdcca68c0072610326f47b7184ce08e5fb5f7b0e01e8db01ba9bd02f3456f9dde0f484e3	1	0	\\x000000010000000000800003aff722f1b9d3988e2dd85f3ca05a9070cd86b45145d8454ae3b12275e6d5f47368450d60a77249649ec44f0136008e59776215743cdeb2b8bae146eeb3131d165d9c20391e137c88f8c0c3956a2ab5662471b67a7c8e6a738c5a5debd2377d5203c2961883b86e3fd30c3ef68be6cb37875ca95fc379e6d29c46b79a635489cb010001	\\x2d361fe73dc949aec2609f884ee8683c3a4969302457d358d50b1bfc05a2e0fa556bed847b6b43eb8b81e6ed7608dc00c4e52f572a4ba5dd088b8d70289e9e00	1679161533000000	1679766333000000	1742838333000000	1837446333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x0ddeac7b954d6fcba21393aacaad04ee343dcec93c149c8f3459e0bb367d0ddd256b509d8193818f92ab301995ca92c0a52af992edf6bd25c97d35c37ff82987	1	0	\\x000000010000000000800003be910db43cd6c2e8e4d368c5566963b3b4d58a3d35dea6837235d899a8d2e01343cd142ca91470aba145135f32ebc50749f93c3390750164e67f765bd285a9f1606eabc285e7da778315996c1b4b1a06b3d199721b9f3d9c1941215e70e587b98f3624049b0434a16448dcd944796b4490e69af31e9ba50d389ff4a66f47a16f010001	\\x1147b8694fbe10ca0d663cc95e430aa77a9fc8ae697ea0b13d3db13e8514fbf98aa8a78d10152b27cfad1b6817a75d5964790b01a112beaa33466b962924810b	1663444533000000	1664049333000000	1727121333000000	1821729333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x113203f2b8c934f2411b2c418f780f47adf97207006ea2a581757f4b8539a05fb2f1f00489627d29929c918241313c7147d0570b683ab5472a0405843687b407	1	0	\\x000000010000000000800003b0e3823d7475b68a4ac5250e1098985ed897841c234148376be7e2c451dddc026774e74c43245bbb1b2df583bf53333b7b41868d421f8b5dbb8b7019fd1555bff82ab6b30690ac50c31022b8fc75c713eece08070881a77642b490834e22d6a1dd28f3f55b7f25c3f0a606b039bf6a1462ea5920074f5e9bd036f832b2ff540f010001	\\x5299d7ac96a37e28b1066ce926051d09a46768e8218a7e5c7df92dc28e9be98ec15fca54ee58984b728cfd4c07a372d5925eae016e9388096f4c2bd8d906e30d	1690647033000000	1691251833000000	1754323833000000	1848931833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
235	\\x11ca8e96d9bb267d5b01b6fab6ca382288d647038fb4f769873cd9992f5ff0e927ba91f0779781a1de4c212779bfa35c68e825e63261c5fe59a93c1c65f300c2	1	0	\\x000000010000000000800003d692ba83e0a8282f7f9c350755b7a4f2f3dab76167599d81df63885a80a986f1889aa6edd7d69c88f1b1d11387b1993e22c18923c5b009458f07a7c4d8e714d8fa1a8da8c889b102eb3cc07da6185f6fd480a9aca95f1803f8addb229f41a26aaff9ba5a5adc8438f67d80fe6048ca8d4ed0cd3c9e98526ecab96fb07dc9d2eb010001	\\x7954d3e5b5e824e3ae424da7b88f9e27a997e08b5bbf3785fe587a3567e9f3ea04a6dc88ef08a3f5c6fe570fe932934e9baf07449321858d8773851324dba907	1673116533000000	1673721333000000	1736793333000000	1831401333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
236	\\x12a298a745606fc5cbed9ffe8440c0f9d0884e836f7afd0655e5611d89940de051c1a92a94e3045f7ff480d06e069383743444a89cd07c809e5d30121ac84dc8	1	0	\\x000000010000000000800003cb1c8606d6eaf72c836b76c3c86261bb4a2d7ac78d8b315c2ba5fc7d9970ed48a1af0886b5de10a3f4f70d34e2a6c40d68beecba6bdddb439ad10a596b87f5d30b1b248172139f820639965c348fe139a206c55704888100bbf72bda8b7c32bf7050c2a65e2877e4ebb9faad1e230df765e1827ebeb08526e5df93baf688a3bf010001	\\x3c3fd40e82c5167823a8a9f44714385b4285829717be9322d700515120f013a3dff1cbda7dee1a158af3d6fa00fd8d497ae69fb5b1b0f255f6acc6ab74eac803	1680370533000000	1680975333000000	1744047333000000	1838655333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
237	\\x127ad9983f28395aa8297db68a683b7a2d7e37d1fd321a77284ecf5532ef186ae67cd0fb379574ba4c2d45882c224cbce2293397348fcedc57e8e73a7638c8f5	1	0	\\x0000000100000000008000039216a9d1f4e754e57744f974b1d402b1dc915817f0b088814f95e35c8aeded06b4d3acf6c3e22d35d2ae3fd1420077c38c75849bdd6b511ff06b6191bde0ca88cef25ddc6f8e06b7e8f66b111795e897fa2a3854bfb039d5019004a06406d144af3a48dd2a1c487656a8c3866c1897ba0dc36be33804772c1b2dab42dfbf7433010001	\\x78568bd973fd14ad9e648b76335fb1de0d2557035cdcb7c8828f56439843ea2f29fefb2fc0ef1f69d6422613d73fff8db6443dc4f6896c35cb3a76abf3ca080c	1681579533000000	1682184333000000	1745256333000000	1839864333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x1212d27a46b2cd3ee9ee8801b363e9e2cb04890f862c1099f12d94cc75f67a53e6ab2548856c222f4cc0ee0e9d00bb611dc2e0e94a2978957a82513253794823	1	0	\\x000000010000000000800003e4a883e8317c347a32e42a8d757f25d491d3c8d90c0bdaae03e6b499a8e6dcb2819b9ca4cb8d4912e1213b020d661e9157abcc698213840efc71c96d6fb54e7b882ba07993c73c76b3e3fe48b6d58de122079bde3fcb7c351961a2812be32306acdedf64c39aacbc23cafddcb4428f4a340f0e624029819f5b643e820ed0c28f010001	\\xd816144ec282ade11451032846ce84113cac354fe633522da8bca756454c06587f0e4c1e505f04e3ef75c69f7fa416a33050cae624b78ce7680a8f6bf24dc00c	1682184033000000	1682788833000000	1745860833000000	1840468833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
239	\\x146a6882e3b3cc08bae7db65a3b3e04b5170ca581b7d7dff50a1074a4a7e1ad37b70be8d10feb0ed8db3ded9d1007dbbc4e8a7c78cd9572c1c56cfd70e08d3f8	1	0	\\x000000010000000000800003ad428d7e24722139ffd046bb3e6783af5a12195c0eb51889644de3635fdbf103215369e3408e5798a88bce3230b35ce23504a8cc54d71a5b9b7c93eaf941940c9c0ab748592d38c802966d49ef665fe11619f2793adde3bb02881f90785f198255bd9577d3cedfff8e216921a6dfb69b3a98ad4f629888abb66c532171d4a9e9010001	\\xdffa4795aa6205e7ce57ee9e7f6e414c660a5329eb1e9fe367d2850d34a03449defc8007a3379b42f656254a50f545bb2d0dbc3f27b3ff4159609b9504d06c0f	1668885033000000	1669489833000000	1732561833000000	1827169833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x150e5e39cfaf745e97ab62060ac874763c586451084dbd2b5986becd99952ca41dc79ab7151c0d5b0c2c4d9bf04a01e643e9a254720237e28b060f2fb36907ea	1	0	\\x000000010000000000800003e1142ca10d5d452d37b845d72f0588cf199b77dd1c287c046095c4eb82e0eea2adc99c2d32b0b782625807c6eeb00fbe21be43fced9ec492d3d1de0caca4e0e5baf54f72999f24765a5a7235b4ff7962e965f5e7ad21535511fa74fa17282eadd9df11e5940c5f979c9c9deba691fd57eae03345b2e20b217dd863668d7febf3010001	\\xeed5fe533988957fc92e181a5a5c083b7794ff3564e239aabbd48cb3c9d1d31e0ea1a94513e4d8a8812d6bb7e6379e6c716c55e74b571c26cd5f6281851f9301	1673721033000000	1674325833000000	1737397833000000	1832005833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
241	\\x168add6849ceb5ec27ed3f3dcd29cfe5b34c6f6d04d482703481c24b4363ab997cfe3fff3b2fa85bf3d909980eb419f7d325d2c0771b3f59ab714333305a0197	1	0	\\x000000010000000000800003dc0326fcb0ec4852808a5b254b704de57c2171d45f51d8cecefc4690c4d0f51e7626b9d92cf85deb2955d6a4c6aeebb712deac1e29542933a3a59f1ffad0ef3ff2c0ded5e23d783b16b43fc908edb6952f2b4ebee9f946d5828f7736f8eb024f13a2c2132627c270fb2ce07491d01230a27aa2b2192be13f32caa24f2a47e91b010001	\\x78e89d3e1cb7b8d98dce719dfb8ec96e8f880177cefc23e5240a615933b979658435f03111510394200b5889f65eefb441e5109722a4c13f103bbf18c7becb01	1673116533000000	1673721333000000	1736793333000000	1831401333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x16569b6d675b926cf925655613efc46612fcf6e25ad29447b8808274a64ac5a1908018a5aef4fdfb9faa4e194594705e0815abfbff395e37b2858b249390493b	1	0	\\x000000010000000000800003b38e6f6a3106b2ed73f7afa42125c20626d6fe15ccd9863ba72594f3a4fefbfff618626fc185cb2cfa33386fe47b58fc002edeec7e6874e75ecb49b57ac78fb3b2f85f9237afbc1080c52c1011fc918b72b12051c560dd142acdc13e9820fcbf3c74a0eed6c585ad1f925a15d147fa6c0b4124d696739878267a75e119957327010001	\\x921ae24ef6c389816523aa05ad5485d6006ec022182ba1a193244b8e6f5d9efc7a92eb5595ca5dd8a9fc145c45dc93053ad1e662a01b67f9015d159abf7ecb07	1682788533000000	1683393333000000	1746465333000000	1841073333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
243	\\x17de6c87ceb4d94a2ee6573525300b08992aa97d075ab24ae605acf04e2b24d78425718aa72c91348707abad4380c0f1676aed81776fa73ea04e99548a85cd44	1	0	\\x000000010000000000800003afd3e128032b5a98b4ba00c64cd7af25387391c6677a31e0a96ebe9e408f8546ac4145df62313683c72b1e9012cf6da91555e494e3f00dd977e3a983c485ea166e81180b5a78d9ca348a5b85b57c882e985f6b87f0a0883eda7fc12daf6f1f6d443844f42a7b097da529f6db180cf6a9af4718f82a16693033691087bfa06893010001	\\x93e036bfa5b2b98fdb0db3533f9f92cbe833e8b8efcebfaca7dc350a039dea402016071aa40c6f8bca5a47277f51eea55f82b995e74319b808ddd93e28c2740b	1689438033000000	1690042833000000	1753114833000000	1847722833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
244	\\x1b7249191021c4ba12dc1b212fac4cab333c470b595abaaadd827445c5a65333248a5ddb5d2433f86856ed25445ebaa1e2df91ec79f9291d578b54ea04bad0c6	1	0	\\x000000010000000000800003bc722caf8f25f7410494eb21239e4bd5b600717186e842840ffdf1fd68ddd1282fb3f3b9e50fbdbff860dd1b2ac31235dba972302e7cdd8695edd8e7cc3d86a545489528561d4f5d1f08b7a40e8db4c985658e2fefd92e30cf66342ebbaa42233a5e63517720cf6907dce5db555da000111fea2a938bfb442fbc21ee2e446331010001	\\x7b1f09eeb77cb255cbe30fe816413a2d21539cf037234d832d7b0473249f3600f25d1d01a3dd10beaae8315a520cf83b9055de186847de10e431c545c55c030d	1685206533000000	1685811333000000	1748883333000000	1843491333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
245	\\x1e7ae09760b7e60fa5c36d35eb1159f5d5f1eced596cd348c9a4f3cc005ba97e9088e71c887ae4e2e61ff5a8107f6ed55b8db975a8fd4e37d074b19a93dc207c	1	0	\\x000000010000000000800003a42f570aaa96456db86ecb8c789849f90957a0d2d309fb67bc5f7ee7cd14c084e168dbb95d9b8c6960b409c4e24c9ea126db79a4a4eb6668bd828befcdbed8aa35f1eb6987ed802bd120f72eba56d96225280a7d920dfd9585103134d15fb63f98136a7d7a3117fb176fc4270511b4ebc9463daacb4854e4d5370bb3801225a7010001	\\xa3f98cfcbf95307caf8dd20a2c576f42892c8839d45599756b6292206357f0a4d227a9ecb755561d0f1f5afa292ddd9a21c26b80f2f178ec2fb5b67bce63fe08	1683997533000000	1684602333000000	1747674333000000	1842282333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x1f6646b5f1b906cf4a3202d17e88b1c1c8421cd2a686c5fc239b0cf14a57210d00c04e872e511bdf533ad1d44a5ed5eabc69da0c38c3a1e78a86e35fc90c4e08	1	0	\\x000000010000000000800003bc3eb0eaa7f8a8ee9c4f9208ec486e0bf184b396e23f129ba0bc911aa54733086f44d012fa21080c74344ed2470ad9a15ef0456eb39a404d5d89048f0878d7fe3a359fdd7568aab764bea6607b4783aec916ac06715d76821d738a32b6fc5bf4eed1166e35b00a10300cd3f52912ad158494adf9fd985fcd2f22fd16319929dd010001	\\xbca6c390ffe1ca98e928ec5d985fbba96656dd87a42bf9d4a1cffc17f352c957524c7d6496f7b89f978264b856c7f2d00742f94db69b52d96b1b6fff4b98b305	1672512033000000	1673116833000000	1736188833000000	1830796833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x22c2e7db2efa4180dbb25a6c12ea45f8dee6dcf278ca488376aa484308486ae80f3b8ca8eeeec56061a69a8b66a9a421a301df5233c22757f429c21c87d70af3	1	0	\\x000000010000000000800003dc18263efedce3c631f0570ef8c237a18c51fcb8a24d9a130685f356c389cef82838c5992fdd4e1203cfa72a4ecc40dee89c428ff432675210c21dc617db11ecf64c7c29b2642fed5d628fdad1ad265552e70d7abdaf0e9da7dfe2007997aea12bfdda49ff5a80b06413dab8c74653f2cc644dbff8da7ffcc57f7e5f31fb2ca9010001	\\x745cd506df148481960b6400c188ff2809a84cf4b7355066513669823c6543ce96666a279642db40ce5f3b8e43a0ca68987daa827003b56270254e56c0245309	1680370533000000	1680975333000000	1744047333000000	1838655333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x24fe017a973fbdd7a92f4b8ca83045d85e1806f6a0a638dca58e8622655d3ef1a9abad7192cf474bc5af4317f68e1c7280d5a953efac63804fa7cad5fac964d5	1	0	\\x000000010000000000800003cbc6bad7ac28caed07312a1eb295d0a468593a72fb83d80cbd7f49dc304aa46ffc8e1d6d39c5d80f6dac27a52a8be28b05fd6dc521aab6e3bea59366ea50c5ed0f54b684db0ff1d98010c51578df5a74718dc19229d99142e88823c33bf5fb8aec4861067d5bf6f4c0fe68cb07ce83eb62a5246966b52bf69bb72ee16852a575010001	\\xe9ccbf4798a569064d30bbfcd223b5e556c46b1a5d2e93b15ad2d14a16b449102937c609320ebad9644cddd2f0f012e8da7c9d5bf1da51349524ccce45fe620a	1686415533000000	1687020333000000	1750092333000000	1844700333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
249	\\x26f26a6de242759266be3e996eb8b247069090a2c4eb341bec388395fca96e2190b2ec370121d4672465dfa18dc994bc0f66c41e10e7d40a4ba75570b0636dcf	1	0	\\x000000010000000000800003b735524e9c660796c400983e3ea844a39595b4e485667fed6ac5a8c182ae241fe1fab58486b49c75a6de5b2fd7454ac41ae343508e2c707c540b8712b98c196bea5cd73390a8c69bdbeb51c25d6cd79818efaa4531924357335051718d8fecb3c89047a09bb93013dec192fe9a2e3a0fe17f9a86642720390309cb983e990167010001	\\x1f002cfd2128c94e33c97809c5d3e67445a20b5457a07a94585af60aa887901b25c225f58885c6f73612f0e541fe6b4200285d50b82009fb42315e7f3514180a	1660422033000000	1661026833000000	1724098833000000	1818706833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x28325f83dc2b7cbe52b785aa2d336f2c36bd43b5ad38d0c12c89071034138e5a689aef0d9f7c8e518b226b2d90468c8e8667ee8739d7315f1c97d7a3f1b64ed6	1	0	\\x000000010000000000800003eba790063ebedeec9e2631907b37aed73f9e8c77de60d7e9b110f7d4897f218bab6084053b9bf4315ecbcd62bd8aabf9d45dda88aff990e7fd2faf603d3f127d42e20cd24c428ce7519afc6ce55fbd3d14622f6c5c05f555e7b761b70490fe80ffc354a2e8030d957f0d1674ce09c85d248d1b97777714cc0fe0701b60e6e81f010001	\\x418a2f37b3758c8fc158fba9ff367cd0417b0fa1ded6a2e1adda15a38696bfa9a731b54c3efb3f052e05c7a3b2c28495d0c1b8bf5cb4b657df0228e1b6d52d07	1676743533000000	1677348333000000	1740420333000000	1835028333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x29d60d494f0e1cc384775e2f5f3b2deea28db20dbd1e179eb1f9d6dc01965b154ee40f0e035904bed80ca1d47051658ca7338fce8eb6ef5e13cd7ecb91a9a110	1	0	\\x000000010000000000800003afe3c44fd920b97f90698afd9cdd3dbf1f2a4db82fb21ee02bcc4710446140e3cf43b54e57d57f111bc063bc805c9ac5eab0db02e6bfba8cd53f3714e261caac7f81ab3be163b391924021a94fd1f24a5872a35e0f7af99b8c209c548d96d98e0fadef3d5bf604a1fca5979e9c06d2df5d2acd71332112652d5cc01794be26fb010001	\\x3b6a99c63b5fbd157143ba2afbff97d5abad935ff499b1786a2aa187ce61f6557b5f171b615917e44f9e40af2b730d6444562ecdf71d31a7c3c8f86bd116870b	1679161533000000	1679766333000000	1742838333000000	1837446333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
252	\\x2a7ec7683e4bdc890bed325543d35b23e87c2c19e77e7f64086342ba31df4fe558e8fcc240ad6a7540ee7492a8766bf443b17b51cba1d4fb0736cdc35962966a	1	0	\\x000000010000000000800003ab380cb44f49e4220752f7b572d59c94ec6e7204806d2019b68aea88d8b6c2ba40a36a8d0444e98703ebef24c8f870fcc2f299357ab3a5956765dc94a46c9bceda4c7a0bc7aa406f199192654dc00a41eaf4f63a469bb96b70c771d365eb26a1be18fb7560e168310a13c1aececcbc6d619251c55db51b9c3727df3265a1eac7010001	\\xce3b28b39c251079b6f8d47a2f76dc8422a467d5b60f9ba7437a5f7c36892d29ba1d7f19fb4acf0510860aebd8fd6c6e53e30627f78b86a00aa6a5bf405a890e	1661631033000000	1662235833000000	1725307833000000	1819915833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x2b321ab1d382d7753a33a3fea386c7c023124010ba4f4eeb8571b20f07339e8a35a676250e1fa60bebbdf119240af7e9715ac24ae136be8b2f3fdcc60c06d6f8	1	0	\\x000000010000000000800003b8ad5b5481cb2704a3d1df85081920b0dd09e6273162bb425a8b4c50d32d2b11af544c48e865b0bc8e880a935298abdcb9f45436b84eca2e6f37ce6e148fed4ccb6f3efafe9eae8a3852cff58c9d86290e0744c1a3c072c638a0f35683ff410e61e8f1700e123e0ebe1dee5b4d9b4ad5ebe3f9e95bd3aaf719c289b84beb35b1010001	\\xaf5a799cb31f55b0dd8850650fa76b469546ab2e0999bce39de4943ea3c9cc6d4fb921c73f80e910c9e70421b5dedcfc0d6cd4efad1d1abf617bac1b0a4efb07	1663444533000000	1664049333000000	1727121333000000	1821729333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x2e5674e7001fda1b3e0bc4a9234127114802784a8426a286fe5d57f845acb81ec0a4f4a6ab0eff7547e83c7f46caa330ffaf91846ef28d64525160abe39867eb	1	0	\\x000000010000000000800003a874ccf519cb5ea5df2fcfdfb36bae0e225aecbeb15a5fd9b09cce58f88ca25ccacaf4cd69f8492b2261f407482606831c74c2f161033f7e25da1642d14ecd7740faf9e7f0a23bb47e81eeda8c99c7e9585fb4856d78e6a2a557eb067afe9be250eb38a4ea1c3c9df0622ec6d0a4438ad0c71c57e5215b3ca0a16c8828dcebe5010001	\\x49c2bbd5cfef2c2cee0060126946aad3632f0ca2d3e5512e77790a99653c506a07c144aa76d9e3b81dcd8969893d52dea9628f20112e22fa56193bcc2ddb4509	1676743533000000	1677348333000000	1740420333000000	1835028333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
255	\\x30bef7df5521599a9d63e946f5e41a2fffde39be734a09deebf70200151cfc58ea61cf021ef29126aaf40d356a4ded454f316a1f2384a739edab21983771712e	1	0	\\x000000010000000000800003d228fd288ce439c54562afe7052e33b6faebb3ffea916f4f4170aeb7547f4d97dc70b710e1358a64a9fc6aa1222446698b40c720fdb64ec9538d7d9ad80b79ecf63b359099b45014a2015436d4c2d1794437d26fea44a3163db9cf81528cb7d23a098673e0b8b39dc5e70029ac9b2e25e8efb882c6d4dc01b4377f68a462f85d010001	\\x7553ed91455c92367435052a66aa21bae5f1efae4534cd7ecdcb5cd8dfbeccfcb43bb5b58de707a596daf952356fb7666d961b8796227d04c1782a6947c8650c	1674930033000000	1675534833000000	1738606833000000	1833214833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x32a2db8c8be01c85f95075f76adb0fd56d85cd35de63bcc2f539a110af484bd8f4fbc1578f9c2cee9bbe9aad8b2bfb4266b325f63f6a21d4eb8b1f0a4075242c	1	0	\\x000000010000000000800003bc52a93fe1597fd1d79404c220b0d79e54a9e25e62ea087a8fef68f90e9d6a3f71ed000434cc1083d94345702728e0717558517d391a016e3137ebd99aaf80bd35c931ce8c2a6a2840c12be9775bc29921475c2c1bd85fe1f22609620a058e012e1c9a54010cb8208be503314506d7bbaa3510f14c842b0135ea2eee227902e5010001	\\xf1c6e62cf8d3b6c903234ecc1aaf45656311cd535d001d93bb37c29e54c1dab91ceded3d31da51f89a4c72fe0357b906c002a241e3d4f11f647afb57e464b202	1668280533000000	1668885333000000	1731957333000000	1826565333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x3206a2dede64f7f26a92327bf5c6f3c531acbb30accf31a2fc83519a01e4384ec426cc97493a975886d25bf3c71d386c4566d844102a725a74daa99009bcd7ee	1	0	\\x000000010000000000800003bdf1b6cbef6d64d08ff107d03385cd5ba69201d6ce14af86890ece4633bffa24d4e18547d9eb7727662ed9249ed0733ba32d495690bc6814e81dfc93adcf6a94a3582f2334ad8dfb9470d96357ce4be33655970ce687a34ffe714f4b183d300aea46c7373240bbe4f139d9dfa965df2c165b25d9ae2b93a0a6a286ac0d76138d010001	\\x1d5f323a52abf3322b07edb66bb79f641543daaabf9aae0765121187f7815f81d2c6253d84b8a0a992da378b67a51e788ceade9241bfb1e7aa6a31673a039d05	1687020033000000	1687624833000000	1750696833000000	1845304833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x33beee7bb0ebea19cf994e24a06f067a24d194c5870eff1cd5cb79c0a00d8860f5c7161f4fc7a7684c4ec87e0aaff2d4828f7a2e674d4209b47de31fbb4d8b75	1	0	\\x000000010000000000800003c57e9eb0de70da63daef0dc316af1ec72af1ff24b68790a7367aaef6643e2b6bd3918efc02843e9bd323adf10e465a9c24e0d87a08900212697db829a956379769f238071b2e95fc5e56477e21cef3f68b8d69aa4d2eec24cbd5b708b50d941c7f4025034504aec3a35eff90568e8025eb1f17d5e3d7ae022d5bc0c51b8e3f7f010001	\\x66c217560633f957033d07aa32c7a1aeb8cd77706bad2586b0a168e46d63a373d9629e7008e673f0271735af8807e3e51d0499ac0646ee12d5ee67f14ca7e107	1677952533000000	1678557333000000	1741629333000000	1836237333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x34bac07ca026026dfb96a8075b89e8d2c0f5fd47fa7a2000c7195aed7fef70781e94e8f35e8b1098d368c1b6ae50ef40826e46b04d5b1e8d84ca1a5519d3985f	1	0	\\x000000010000000000800003b2fe66ccecb292bd55033798bddd16a40422df5df06f2cba64b55371e1e5c4bab6d6a063a436018687f065f34a9a642449e9fad3caff5fa38ee492681a67fb9934acc153737d06bbdc29afa0c0c4af3b75a532fb519d1c1240c583800da8490c4f5345e5e76717fa60651aabb7860e740c81183ca7aebf2fc00a0df1e5420e03010001	\\xc34645484c80fc0db98db5085f569f86ad1d4ac76563a613722fe8ddf6e5a599e240e65f22ab774d75adf3ba7a4e198e75f1ec8c6009ab5095c5d68cbed71a0a	1690647033000000	1691251833000000	1754323833000000	1848931833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x38bea5188bf2fe573c91643424fc516c5f358b8f320d680b3096f69feb669cbed84cb69a4a908a59232f9eda6ed8bf93933801ac66f38ab2b1dc00fe52c83878	1	0	\\x000000010000000000800003e76397b1cc80377d6f945bda2e98d5f47fda3f8ea14a6b0def171132a65ff0d608970be646ec8b4d029ec28e139f9d6a9813576d0ce116233b611deebb4a38bccfd099ecb866053d540cb6621a4bdaa4a7efa9b25a77bb187e1d0228f5398fed0d667dbb6846a0b085ba6e8b2ea8f7ecc69380f25e065b3bfd574342673addb3010001	\\x80178080d95156a6cce6b6371ffdc92fcf584b40291f673c4c3410675310c546f527b39ef5040f8d84c00c5502e453d98456212af6b002fc129c5c2f32fc6e0b	1677348033000000	1677952833000000	1741024833000000	1835632833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
261	\\x392ed0a824e03bbfdda362ce3542a11c5d68c7c4f5acd032a7565c1b910ee363eaacc1b43a2cc04d60945840a668567477655515367eef554cbb7953f63831d1	1	0	\\x000000010000000000800003b8667a403d2e7e355921cfb718b61ac0715188e7f3d7a8036e5d32a7ccbc0fcb938dbcced7211bfcfd565928f9d171682176932cb04be9e832a2594c2cfb23af2d7f2759e64b9297c0e67718a5c7609ef822ac4c2829674a584c14584985c2a5d125886beb31c2184f069beb64024ca7f1ffe8c16b7c7260a4220dcb6c398d9b010001	\\xa4e523aae3afccc2d172dac34b001eca5c7ad542cacc152fdd2a4fa27d4da5c9832a2fdc5b0b0e307d904f70b7b30105a2d3cd00a13f3d63ae8faffd009aef05	1662840033000000	1663444833000000	1726516833000000	1821124833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
262	\\x3aba3e17c04f17799f00a3a55bf1c2f407862e8a4c027e3d6b9049954b5f8019ee68c1f7d440021a15e6403768bdc38a97a6bd485aa287885c56417701341497	1	0	\\x000000010000000000800003e2b47bc426b404a449e19e7aa97eb2e4e169c11c10c4b140151b93037187583db8f220d25843352ab64e7ee88ea3e74fb76b5d52ed7675b3cf9c60d31fb2e679586340288f9a76f3adda9cb4f1e7c4e1103382e6e21b321bb7e2965634fd0e56cb033813b329d99d78cfa4f530c5ad302e621ca9ff34406b012ab561bf9db5e5010001	\\x582f59a0a4fe9954a4cf27fef4f0a28544cfb8b67b77068782df1f14006021cab847c48acd0e78794fdbb4a93f3284332ef246facc9d110fa0c618e6fcb56f0a	1659817533000000	1660422333000000	1723494333000000	1818102333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
263	\\x3e0e27ed260589b94a1e1598d6c75cf73c0446411590a6bc6bb7f40b7d2551bceb08a9f93ae32f907c7201b09fc004eae3192dd4c00bda8572c95ba66985a681	1	0	\\x000000010000000000800003b359b211826e7ceaa21d5d7b1228f5b7736b6d4ca98c07969590f8e5c63028e6f577be8f172b6ac9517eb611fe8232c75c8f7222962665e20e46dc987e6f40a45ae94eb75eeef66c09f8d9b0ed097d459091bb5e87f23429019f4d92799f37a5619b0591cdfda83b0b28e42c955105325df028b7ca5eb42b95a896b126919bb7010001	\\x47d739b44da4155030dcef68911b8adbc750d0879a3d7d7056ac458c845079e521a2d85916cf9f8828b5833ad9122dcb0bf45234ea784203e9a244caf88f9408	1682788533000000	1683393333000000	1746465333000000	1841073333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
264	\\x3ff2dc909290fc2b3b52f8c23706bd3daf9724b788cd67612a7b7899c53f28810ae16e3d44d9bf9b4380682b9628a03d4f9e68e370e614d523e12b38b3a7ec00	1	0	\\x000000010000000000800003c126cdd162cf359f5aaa60e7d0d2c47f964990cdcfe21e53f05f4829186dbce1e350b8efeed8e8028b5de21be0d959cc56b41ff66cfdfe4b0703b403a3604304cf6fdd3a59cffcd17b12b5d93955878247d8dd26a3f6aebbd95db4ef8d48a9c68f232568675e657238faf38ba26f9bf47f947af453061d5e62afdd4c10004cdd010001	\\x0abcb64fc3a26383915338d6c86d3f5c6c563214de3ce5ca3eeaa657bb95947f8afcd0c7b74b88e3298e17783a97ce9400640fb52833c400df1d80dd3d243e04	1682184033000000	1682788833000000	1745860833000000	1840468833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x43baee8a14382710c51b6681c4b22585e5d9c53f0ad63b8d06e788e1e9e0de7a59aa71ed73d16bf21d71e32f85c0a59fcbaeb003162295890ab73aa9c98f29b4	1	0	\\x000000010000000000800003dd1b5de1e0d8a20ef11f3c13aa6a3d70bfb9376bd840449bce311686d1dd15e28d4e837cb4331c6aa2efe4933364026780e14ef28905955254852c01c2fcce1b9f477a79820f74e8f6037f2f6bba425eb2f96be201561836ab09ca5607d823600c523c1d3e8699fe1b28ab47ac987814a643d31d29db5a228cfcf6834b747d41010001	\\x15fe537b4c9debff98f89f2bba10a4e4396f6cb54b50da2ea39c68295cc7af2b27f729d0ca55969ecfc7eed647f71d397bdc62f7682b5a7bdabcccb6129d340d	1691251533000000	1691856333000000	1754928333000000	1849536333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x4e366d4ff0b15543c416d404c4637834f1210c5a428e99958feba27a2175290442d845783d86b04f801d5a070473fd603ea66e6724bcce8747e44bbb4a2456f0	1	0	\\x000000010000000000800003b22a8771eb08fc3840505cbcddb68c162b34db191d7dbb2df9222b2cded4b2440f51d22ef71bb2009db2e6d8699aa15d8b1944e4f6d2813f19744df8ac18cefb9f6b7e6c1a3c251958c13d44e1bc7869bfa58bd6a8e20c0b4cafeab51de32352385a4a4722802c3284ec370b0120751caac9bcc54971b42f7488b11b4f56ce5d010001	\\xd496e7f6dcd7bb1a0f820799992bb213c44ed4ef1b58628a6adda1c4abbc00c3cc491ecdcc77bd36a7003ae24895df0e0666c7156ce6463efb449d6a9716730e	1682788533000000	1683393333000000	1746465333000000	1841073333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
267	\\x51c204cb7a57b49f540d7d6398c89449dfeb84199e582870a2bb8ec097bfc7b8c2cfea3768773455143a7cad8616ed5d5c0770621189b6885aee3a5467a59ce9	1	0	\\x000000010000000000800003d90be44ad70e26b2b1ab33d5a9a74444abd96c2eeb8e1cfc81699703e83b1b5ba02a6e8024adde12e4702145a107b7a3557c09da22c649067a8b5288e3fb7354af019f212de6cb1f2370c1104119d54d021b2f3d1260d7acbab1d5f6f6ce8fb7bb72d5fe00f7568618790d6548ba3a5465c03c2b51c9d26d2446f35256be93e3010001	\\x1bc579f27af2195072b6e22cff397d0de5299173996f4384fd19e4b6b1977534846929d163b2492c08e178c4e291d7332c471f27057f28ac6dcf08d5803bb20e	1681579533000000	1682184333000000	1745256333000000	1839864333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
268	\\x51d608ef0c006599aeaa0199d2ee9c03661139c6a0ed97300b443a4e808144c6dcaa627a3c63120959989d02ec87921960d686e3a85e7ef9f6107ed0874854b3	1	0	\\x000000010000000000800003b069705e5528df1710da03f57681986b57e00eebe4252615eb7d36d2873ea7b4509425c4148ec5763a37b5ab781eb7c82b4780f8db671ddc2acc6bc74aaf7a117b78ba8814f118a50dd535f8355dfed5500e45ccb88ee10f05bc4ae55d2edff87268f8f8a4b4e55376e57ae475336e6494f87611e811ce6d89cb223733a70ef7010001	\\x97aacdd2a78c9f3311f1fab83fb7f30cc99121cabb087d0af8aecf0e4d8d15ec07c106238277c5f73b7e3b252ac39a000fea63fba6f07f8bb39305f141783e0d	1673116533000000	1673721333000000	1736793333000000	1831401333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x53fe18467c9abb37264fa63018ba9d4e52cfe506b9f1996c27110141055cef09e4323c01efa8aaa8a7acdd2c73d90391dcf9455fef9dd4a22c237a12134d72a7	1	0	\\x000000010000000000800003df4efe840b255ab54e8bd7688c29d4c6ca9d10343f7cd1891f6845bdd82bb16f5dcab4204ca8aff6ebb10caa1c8c712324971d5d27a09689e4eb03b66a7c2a6538477eed92bd42cd32d44baf9fb4e2d88509a6fbca12513c13a3d407fc45059a6beae87fc1e2cae066c6120cf04947d27dfa5cefd40890bd39762df431e16203010001	\\x428d9ef27a4b5873112a725df116b0bcbaac8176f0e18c055f2e0737146a4fd9684dc1b5528ddaecee3de04522cc832c1f1137bc374f019454f829705ffad00b	1675534533000000	1676139333000000	1739211333000000	1833819333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x53a24f7c73d7fc8381d08044aa3cb6097951b3bac6bc2a09d465b3a6406114294ffc8e9c782415eb9290ee8a0054d0cea3b4010b37059d9e4f2e27d4f6cf64d8	1	0	\\x000000010000000000800003f47476fd771033e4bc334613f34a995eaf9e0b8651cfc6bac357167d8667fc327eda7fe7e8dff851734edbe5307964ca0c8feb9f114c1092700bb9dd3e86a03962ca5291decf5adf1b3d0bccd138b290956af6d7ffc12951f9ef58243b1a4145360292bde49bb7566d550197a35203140dafe2e4d094f638628dae7c216b8cfd010001	\\xcfe9f320c7cedc64de03ddac8860c4fc4f0feb86a4cd3100705ad7327354c35c8b7f02f88215dcc6405ad6f29cda30a29e764f8dea1a127562390df79a140501	1690647033000000	1691251833000000	1754323833000000	1848931833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\x534215f7785e628942ec5dfc48ac99ab2284b4497b6170953ddb77aeae90fe192007ed94cbceca4af3418c57a85fd711fcd67b712be296c82d178fbe6305e0a0	1	0	\\x000000010000000000800003bb0e7fc8229f9c676b104a2ee1ee6b447efa7608b3482758185563dbd845f6804e09d7d525a2ac2a2fcf7c393e1b69676c7fef3654f7aff749fb7eed51ea3935fb50a493042411aeb7eb3e55555830be4e00fe42ba4b4412125a0cbce932423f5476bae8bfc14cba6338c9bf2662fbd06f64274efec5f607f43f23695c77e409010001	\\xbd37ce954f85840d4fe2584570244ffb7b5cb530ec57a2085e2beac5ffb07814c7245c9b024f3f95802764a9ca4756429e7930210ade7c418f97f51ee2042202	1670698533000000	1671303333000000	1734375333000000	1828983333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x5426c08fa34adc7820be0c11354aec8021ff2209372d40479502eda1237c0b2f30d3021be791b8e2cb9e011cbf8b631576ca722e0b9a06604b0095b308c57689	1	0	\\x000000010000000000800003b9414805a60ce314c57f270ee90dd2aa7da2a813b9dc3ffdfbccc781bf91fd6a039a83933e800f05f90fcb79fd5924962c600dbdfb9f5cab633473389342fb57997ec15e62182e06b5d9fd3cbda64f1cf6604db043205b213f857bc1f6529943023a41f48a536c9ed27f93cdd590b3d5da511ec4af48c540aaf83715783eeccd010001	\\x5c775b71ff4559209282f009a5ff2ee1f2c3d3323326e5f3d5d4c9ac9fa79776bcaba99c283459278feadb420ee5552faaef4cd62430dc6b5faf9c45f7ac8f0a	1669489533000000	1670094333000000	1733166333000000	1827774333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x55fa8a12472586dedd9070f946b06105d6e3b6ace58cecd626b6c8ef59955940d703a76678a7f421044bdf1dc928d12ad391117d47246decea5e77c69d3c862f	1	0	\\x000000010000000000800003bd342c098fe7a2d2415898e51a9a3dede3031a95f88a9f1e75b7bc37b37581fc8f7cf5a70ff44d42adca73a3cf503de3e70e71fb0531573a4af332c149ea2ae60aeec8362c3894178c1dc719ba73514bff612497508e577a49c1816e519392c580d1bcf92168adf7642b4aabe0a4aef90cdd069b0c4b14d35e9ada3b7ba9d7a1010001	\\x7332867af9f7e9f8ed9b648e0ff706d74907bb6c55a48f2cf85a5e4041a3c28f0bec112985cffa3bcc34624101294c2a5e2d3d24c5370dd6f3f7fccd63e11403	1665258033000000	1665862833000000	1728934833000000	1823542833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x58b6b7985d1deb9fd225a56e0507de724939211da3725b93d0725404f49a7a16b7a4aeb7ed4ee8a792bf69e1afa53ba4035c842ab383d8038e66ef32ed31b25c	1	0	\\x000000010000000000800003a8f24ba681f6de47b0fe0873584441676c110918471bf8b42e24ef1fa7ab8f325525c04fa0f4b8177e221ef91104be0f02cb1e77fc1dcc870478e7b6d92e76119c069deacd559ea2b50147da164c22a59fcdacd9e8fc72ed01714c097110290499adfdd904e420509d42e386983df543cc5455e0da5f0fb220705bfb534bb5e7010001	\\x064b20e96491aee3c299d86e44c01d6b31822535ff02cb0b700258ebb700777977f264ad7cc03fe7fa13fd84eead3814922b0a12ff4e9992b8d9d91ee0d3af05	1661026533000000	1661631333000000	1724703333000000	1819311333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
275	\\x58c2e96a21efec232bbb5ae69ad1085852cee99334add7daa409c150d4b424160e433a8e4541088265d7e005f15ca280862f5f370d683762e1950aee0a98a51b	1	0	\\x000000010000000000800003cbea191224d73caf76494c1813bc300ed97c79adb922e0b7c625c81681362e582af59f35e6654600233a927adad0902ceda525b1469e06e044e7da4e5b87651e74ba10e6e4c50d9f6d18f45b1e01db93d8bd5e924aede0fb4a53ae75b3b12be5f106521af6b07717266676b21b2cf95f658e367f077d6a336d3fd18aa52ab9d3010001	\\x8717778a0a4c2b08b4c39c926729a7a42e6d74c9cbd07ede425febdfe2a9d5b4846e8abd645d38e8aad801fc495892be8ae83fef04dcefd7c983c111ee617c05	1676139033000000	1676743833000000	1739815833000000	1834423833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x5a5226bef884ef16b0e8452fdcbe6968138be1046a5d425a2d0502d5942c2d7383a0cac9f349e8faa767a64c444ab5ffd5ab08c275cf90ee714629eaac756b17	1	0	\\x000000010000000000800003be4c3a052e9ae594fc2c0bb29bdc462991b5121c49de2a9a14d94d9aeced21b3a7b6f1e2459a0e00270a7e2b30b9b80389048dc012c8f09977dc11105db5f6f6bd3fe08d051d7817758cb7d13380fa90544dc4a9415553f9a911f1d13e7bab0e9597715ee15fe8ce1f20fa4adf661969cbb1242fe5877b8aa1a8486be466ccf5010001	\\x7d1a4e35fa3ea5f291766e275bc79ce97b1ceae5348f17166fc7b2512e8ac4049efec5c4d262652aa4efcb4e3b6aea9a94b60040a0d2090fcecbe25f046e7f03	1668280533000000	1668885333000000	1731957333000000	1826565333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\x5ae2e03c76ee4a5780456b51fb5e91f5b232b53dee207be387ac193e09cae6ae38fd7b021b018b71929e671400932944511eff694d1e50f44fa86e51d14c0c1b	1	0	\\x000000010000000000800003cb2df5504d3e6987a41a4b3bebb5af416bd1c8e9b674530f6fe88fb9559763ffa424ae7615906befd91b7c1cd5ccbc45458fad675879890c02bedf6c6c4ae52c6d71052bdd4f627a039ba2ec754fc4a9687b201a902b950c222d4d6ae9487e57986f7519668a1b7e9af22e2bcfc1277a8e0aada7ddd6f2cf2a448f91130f5ab5010001	\\x1737380c7d820756f1e5cf46a5f58325236bbe9b12108cd1623d04bc279ceb2ba8cd8411814b377a0c445653da92ef9572ef4981252769e1c9de073a2218470f	1677348033000000	1677952833000000	1741024833000000	1835632833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\x5ac6c9e5e63c113eb01a1ffb4322436787d37ca0b4d2e0974ccd8704699bdaf9a3909c910f36b7e5c41ba494c53e61c6209b0e987a8e49231f482698369dd97a	1	0	\\x000000010000000000800003d46fcb675a1fcbcb2a30e7d1e7335bf2e6c529c3d471b7d1315b028a067cdd8994fc6965e74acbcad7a001e9f88c81c73cb649c0698e0d19fbac3442586cc58ae2383d138189656c2815a9825af919fb40e82a965b6fcd923bb786af316d2a71665663c68b11d8e0cad8bf25a2b9a00ab7574a268d121879a47f5a1939bc4a47010001	\\x0625c3e6d710e8876fd75fc1c3f8618909bd73670d893b43aa86047d0c360d105a4cb5e416e72fafc4d15b59b1aa30091aab03ac476854b0036da335b4ec6a04	1671303033000000	1671907833000000	1734979833000000	1829587833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x5efa0bf7b1e6258b6585523e1d1be84aa6961a6d03a1945ffc0188c3679112b02d90136958b4e44f27319fbb5c504d15f8b8b745f04ac3ce0987cbd2d4b2fb12	1	0	\\x000000010000000000800003f9128db34b814d61c06332ea84bb3a85588007c35778b6f59e943c43458606bc4315303b9739dd4eb1112f70736eb8c59053750241e4eaba1076266517b0b7fd2756a2fabded2dce16d0196c22308ab3a5afda24f2e263521c8ea9f304531722a8d53774f736668aa2535e2824e28060be7be2091fbf1cd2adf2be12d4d7422f010001	\\x03c85f22a400243946249485e17ecc288ccadcf82813494f4c325630bd1e1efc7dc95123354dcc6e853bfcc822d2af126b7674d609d63d68018f8cb447944809	1682788533000000	1683393333000000	1746465333000000	1841073333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x6176e3724142beead9329f026e57b0f773bd5a4a1f0801fa69878519699271df513e153d9a6694f0785ef915b2ea5167d5517c08d398ca0437c4c2b141d6a531	1	0	\\x000000010000000000800003eb7732f89c2e94db8b4b1f5997630ac70cba2828f7b9ee92925b3084963fe72932cf5916494337ceafb6c48e15a940f6eb190e08c2344ea8273355861aa585765315979673603939b5a63cd41c2224c431bc0937af87f5841850dd9a70393ec7afa979c0185e6f7383acb52193c56af6c46422c67225c259fc7cb0c819bfb035010001	\\x3e17829cea36b9fb89827d5fad9aa19ac7d01b9a89cea560fc7f93715fd4ac46add2fc0da7ea79f4fc559a1f1b723befe54d74afe2894159d45272cebaf81a0f	1681579533000000	1682184333000000	1745256333000000	1839864333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
281	\\x62ae6b4730275135c7f2f03466d7e33a20e962d2a988c375245083595fe0ebf6c673af6a179310108e7814f31f129f0f93fa638478d3504e29ab43ecdb671b6d	1	0	\\x000000010000000000800003a77a8c942b2276538ed7e340534cb347f7e1ac607ae0ef8af0dc47a7dd82d9f622ea95cec63f06c16efbde93c8fd289d186bcea8360d81240819e0dc889d913b93435a95470a6c4b77bba369e069c66db3a1c276859a3d13a785909276c6c981ed0925cd801b701c863894d5d2c1b0c22d4cd62c9195cc0963282b7a0c3df987010001	\\x14cf9c8688678feb39224ba513f6637deca0aca669996e4ae70802b4e7a5fdc82cbceea8710d9a51e415362455114c7b41ae6d1eef987701ba24f05235c5c601	1683393033000000	1683997833000000	1747069833000000	1841677833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
282	\\x6646cdbde2549549338434d6454ab05ae69ec18c3fd1e71544852c84e540059261139225b02f4e5de1feb0a091b687d2a351007a5cb54b9a8549ce873f8fb2b4	1	0	\\x000000010000000000800003b0358a97e5e9eda91c8abeed50134db93b0e7d440a4bc10c0db6e05701f93def458eb12e3db632c0cef8532fe14e6f7fced167ebb96eda2364d9b603e4e6beb3ebebdcd6e5c0c2cd23c05714b0bcae3f525e80f8a267cd6909d8d62ac2c7329800a55efcfb327f59db7f8da478089769664307a52b8ed53efe2554abb04816b7010001	\\xeb9fca74d0c4ffeb5376cd991820f3635bf36d711fee10070f94fc35f7eb750ee70859750f1f6793b8eeca5c7c473e20bfb20a9fe0a3fd73db0f0587b41cff05	1684602033000000	1685206833000000	1748278833000000	1842886833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x67a67a67071da3c69cd43ece3e8e410276f0ab4e39379c3cb066dea06f94122c6af859528f0e79c09bd4c22964486dc5976e1d22894d8895b0d00dd4ec45d1f4	1	0	\\x000000010000000000800003e12bf55bb990af53360060a81d42c210af26281447f541d30ed900bb5e2079d3d2168ced52b8b4ad78fdcc32e6b4751ee81f35e67f1927aa177577e3920df5926a415c408466fcd806a6f44497f420cda245c642be2a0bf4c1dc9b12f71b52978933b345b882f7da9397be9d3234c3216b5a1240e2365d48910f887927605763010001	\\x80d1744ba777fd42dbd954f08036e2b9611846555b4f1bd16d4fbbd5be91564eee2a95dae411fd120e2840501d3cb27653f1a222d918cf5b64368cc379c30a00	1664653533000000	1665258333000000	1728330333000000	1822938333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
284	\\x67420108007c2b16c9b8afb6b4e811f13a01e293d8b3323c687ba004f51221fa0de99c1cf723dc147f1bfa1702b559ae5d6834958cf66e1a1d15ad3455318b31	1	0	\\x000000010000000000800003a1d06245009d796511b73b7e8a407f2e4b2f83e7178cc1394ef44e0a34d02a83356a098cf181a7a52d49ab78e2cacf9d3b7675b7107d710a3dab8b08a73343866f5967e07f521858be9390a1745eb0eee52be93c85516f9848cfaff5d5bfa34169231c0a4f95a23954fb53b3822c7f32df68c1c02f9b95931acff919337663e5010001	\\xeaa8b1f75ed28807749e5e2ff51a160356875c876028e2d32a2a8129d3131ba9645b907c3311a94d2d4ed9d0ca868ad523a3e41427f364029a85c00146c91a08	1681579533000000	1682184333000000	1745256333000000	1839864333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\x6b4eb49e75cdcc1bcf15a4a400a4285697ad33421d65501058c97c26a4fb29fdf9a494454ada8c2c031698064eff3e7c6478460ea6a49fba3806c3afce11285b	1	0	\\x000000010000000000800003b922a29fe3fa65cb1a595e0061a4b36b86f156f866eb2f2b0bf1e23855d3d9b0fff3f232484ddab45afd149b6b6ff69b1adff325db6728c1ba39e81b294cb729fb4d61f579a6b4b309b3e21559800c0ac0bcd044991e210ac205170f777db90ea1d5ad31652dc6eac2ec9360ab17bfeb23ef763b3db556a61959be8535d10c1f010001	\\x9ca66912aca1ab59e927159c0cdad5e8b6ede48b45512564c4cac53993f423465499d5a4f2b3c64f394adba5b1a4caed12761f9ff50268dcb63fb95403257e0f	1687020033000000	1687624833000000	1750696833000000	1845304833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
286	\\x6b42313f63c1a3b5b5c682418e307d63c29be1857ccf9a8ceecc93adda9bd23ce51d7e148570828230b65466ff0ccc37d1e0b43adc27e37f1d0a1c70b9ac38fa	1	0	\\x000000010000000000800003c5f9ba82d4509bd657ddc02bbd766b2ff9c9f5ceee02ce8c02bccb9cef9e2bed701b04d45023482b20d188696896e51f830d91a7246b81731503236f79ab5b15d3c14b43615ff7b7a24186beaf6937274ea16943d36f1f425e4ae7a479e484ad6a361069723719937ff70010d2cf2ee7b8922899ec12ea03d38e540bb060774f010001	\\xfb400386be04cd05cda12327b31e5b32fc05a25b263207147efe42b81e0ff7301beeac0fd0a114ef61a1b462e76c49f7ccc890f4dae44a29f916f19ef18e530f	1661026533000000	1661631333000000	1724703333000000	1819311333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
287	\\x6cca92227c66ae11863b24dc4505837758561100f09de7c3aa082e370dfc03652bc8cfff21dae8ec6a0bdb9d8389532a2c780bc676d3959a9723a207dbefde2b	1	0	\\x000000010000000000800003e2ceb432d4da0535f33bf5a7512eee7e636a0584e56dce1f1f31e66ce9caf81bb60845391d8421701a963ee142314438d8f877a42d7607d21ed0a1da9f1ca040031b6d5f50b01f926a9de99350403a9c87d55529b2b37668b96eb092b5884969427b5782303fd2964d3a1a7ca226a6e5f68f38363d67c2f757d22af50f0023f5010001	\\x660ac27b6c34c60995eab498ffa91733d7b86c9022e3bf3d55bc57489d9ef7995764cdc34014407dfddd49f538c456abbaa5e4d7b986a5dad795ceaf854c0305	1690647033000000	1691251833000000	1754323833000000	1848931833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\x6dae020f7277daa044e7aba8aa133bd4bb213b778ad2fd4e285b963531f381f8ceb0bb98bda23479a06d4032ad2519445cb91ac59302b41d13e79c956d3b1d88	1	0	\\x000000010000000000800003d86bde8c2b084d839d9d61c6fc4314a9939e6d6c70e364d0361b655809b1c61c56295531709c00852e5b3f9770edb012e97328a60c666637a07ae16384cadfc940a5ed03e4a53cae3bef89e17fcaaf4ccc372e881c04182fd63fe0ebc059d98e9b497febe69083de1862c8559a1b03a78b163d8b9f0f85f06dbb0e6002a3494f010001	\\x128a4188c7dcf1f002868998d534716ecd65bc479560aee5b1ad8c3cb3443ca23220996e53d42056efaa0b7ed474af8a5cd2814e597fa20eb2b7304873c11508	1669489533000000	1670094333000000	1733166333000000	1827774333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
289	\\x749af160072fd335c89fb0297daea9d461c6295d01131ded0ef060bc93a12c022bc8d558088238536352f194383b79a25b9e4887125b2abceac472791dac46ec	1	0	\\x000000010000000000800003dab55df1bc97a0f8c6794f09acb69d5e02ded4ef3dbd88e110b506044d86605f2324219027a0823d9c3e9c0994bd1f9c18ddec6a3c1984a8755d8ba8c9f6e0c090ab021055d753e5b06157a432279bb7eeabf922261974506bbeee74c0ab4f08cd0bdf33d86dc5fce7109d8b4b282789116e9373b73ca46efb1eef1ccd7ba985010001	\\x5ea1aefe249d15a24bef0ceca22914adefffd9dc461950acadf3c1cbdd88f3b464b7ec9adc907bd41b50eb9bc0326c587ebb502f6f89bf745213d7ec1167dc0a	1665862533000000	1666467333000000	1729539333000000	1824147333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
290	\\x7506426c98886761447339f1e3b7d4205fa89ab1fc1b9861c60f359e79668b9651d9d12833c24970e5d82c20bbbe20ae86e4eb8b7ccfc9c95fd986d7a5b1bbdd	1	0	\\x000000010000000000800003ca9f6230a93df2cd5fc91d382d6840779337f9f1765e0021941a37a2bfc5aaf1fede7352083d746be166fd7e74ecd2bfe68064440279219ba636e5b0474282ddec96caa3858584c073216d0a13c81f004c1288b5e1c7447b2dabd5e7edc3018d27503935386fc7e418fbfbb6104e0b98705e07c7d697b5f0e94aba374690245b010001	\\x901c5f8a841ce34fdd6d2d706d802bbf2ed6fd12af016ce120df14adf0cafd21be4c3679f34b3c31a4b3802ec09f0a3e975d3777ae8eca276d01567c3014ea0b	1691251533000000	1691856333000000	1754928333000000	1849536333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\x776e78495a81e4f134cee769788e52e174b3932d8d2b94857e21064e6f4b89d23b68c16c2868dbfc3af004c752599acfde6b3750bc56c00402a30c66b11b40da	1	0	\\x0000000100000000008000039f47035c3a2b81b65a42fa9dbba23d073c089f7e132e78b2f55c37d55416b1d12d9fe7d16c646429bbfeb361073c9cee30212231f663f9ea4f8644d801769fe05e54a2ccda0ff22e78f144a0a9c76d7868fff92949e0c350fc60ca7daac661c17f9b0422b69bea978afa66ae05ba9f9ac872a1014d940e12160136a843331823010001	\\xe9f2fb41a28bf1c97908f3558f7c8bc22977ab04a5e434748cd5850ac47ce655895c6efeb57406909102b4d55676c10fccb3b56f7f38d9e4b78bc7fee9085309	1665258033000000	1665862833000000	1728934833000000	1823542833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
292	\\x7f1e7cd8f46bb8072dc4011fb77e5ad77be95b6e4038f79c7e1c0ed9509a27fc22ff9f75f1f1bc6b3d2386adc136fc714eb3eeb148d32f460c1cd3e9772a95a1	1	0	\\x000000010000000000800003db7dada925c9f64b416da6bbb55cb95812cbc04a28a56b959c546a81cc2b67ae70653d5af9147e60ef332fd645865306a90ec83fce82c24503970b4c091e8c71473d90b386bf9faae29d77af984cc87d46530264ec06a177cbfb3f7885dd9f70ff2cf8be97dbcd2f44e94c61ab0c5829b865682108936eb5ae3eb65fc225192f010001	\\x7d4f63fa4dd34affadcc6426a4cb11dd81f1ffcc7eb8647ffb38df924323dee74a7664ee9c22fac365d2d327fbd0a317ceef16381adfe77bc4836f4f34f9de03	1680370533000000	1680975333000000	1744047333000000	1838655333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
293	\\x84c263a4fc63f0447971d9ce9a6df3ffdeced12fa1c8be3289e9c81f11f13e5d16078d4a4e380588567014464e7998f4ec63b3d8ee573af66702c9242b5dc294	1	0	\\x000000010000000000800003e353ab87a23a2e15fcb4a7b2a692b47de25638ef60132b31ecf7c445e028be706a0c684df172269225339602867ada7719f4ea918acfc84ac886e0f8291831215d0e318e0c6d2e6c610d2cf0831188f8e56e233689f428edc891065797c8cb419e4b846eb8cc4acce5158b5e3038369af3d77c8f6094dca4a49438e338725c5f010001	\\x2062086bd371a79c8d6042106bd599485a22dd81488c4d59d1c01ab73e4a380773c95b54d5992c89e20ec9318da22d95b1e2558907833ae8bd7734474687c10d	1687624533000000	1688229333000000	1751301333000000	1845909333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
294	\\x8402d9a946c653a12b08544441d9b249a044013b7b42a0dafc3c918e512f1a0dde3000bad80324e21f0d6e25c4af2eb296ab986f3abdcf73ce2b3f516ffa3a71	1	0	\\x000000010000000000800003b1a53892b2b5275d286c4984c5db825d4f3229e183aad34ab62333db9251e3cfc86c24e172a2d8f19f4806bbbb558cfc19987dda8176cdc897173af4e1966e4b706efa1f58c283df63bbb16ce54ce7ea91e8c13b7b8e1f718ddbebcf370ce2cfc3434c82c92584d9b96e272bb6492b92e6ef46fda5b8cda995f874bdd7dbf43b010001	\\xf1f9669867f17d729917bbdd833d0565a8b5d168703e4c2df7ac2411122e42864d580585806bb58843263f714ecd981ae4572bc78823cadfd5127fe23ce1ad0f	1678557033000000	1679161833000000	1742233833000000	1836841833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\x8592899d729807e19dd41c9e6accdca2d101faa03478338381b7a72c1e9a48a3d4e4d9e8ddcb269cf655a80b78e353940690e5e53756137dc241508511c15bed	1	0	\\x000000010000000000800003d0083e6d549518100799f3b5c0abc738aba4a4ec0474f67a8a1bdd7ebd88a6b211704b6cabe4fc1deed9265baa4f4ac8ad19226c05b9e6a06c6342f417b0dad2c7149a11dfdf36c555e880205ebc89902bddc762c46208abde091bc72debc25e472454dc66ef8a2a3e5643641c90ed472325b1d5c0019421d80c47d1c57b5e7b010001	\\x3e013a665e5274cb1877130aeb424e63991f92dd09e74acb712cee2f8407b49ff2f6324efd912dfe52a067cd7f789ab56f3b0e72685671d3d05751123046aa0b	1659817533000000	1660422333000000	1723494333000000	1818102333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\x8bb2a2b348342cd378b70147239e1767fea7e9459a035a8c8a4b61f147ff16aa4bfec277918475621ea7c545e3af8f64d57222de53d80465765f14ceb0823f44	1	0	\\x000000010000000000800003b56437b532411f38feeb7860a3a876a307ad9637836f20624206d7aea1944f43e9f507842a3871a5f535a55c390ea03b74ac221709f21f9e25fb0c58161e47db3906bbd04e38996ad7e4c179b84128e6bee26d72f0063c7766e0a6360873b304879b1f187c78c2cd7bd749962fb0de1094fa6ff976bbb2415ae783b933364d67010001	\\x2e6bdf8b2c9f21ce7149c4d1eef6277cfeb6afec09ae1f9ad99d054477f4ba46be59b59e360227bdd650e74e03c5082297d43335474af51b0b50ff5bc0198d02	1660422033000000	1661026833000000	1724098833000000	1818706833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
297	\\x8e8ec13b6d7f21e0ca259a0799cca752286a411741dbd7217fede22f41c8dee65e422ab023bce86dadd598313795ab1461759e3084385e2ae82a3ad087a416ba	1	0	\\x000000010000000000800003d6de33ae824d6a79fb7687b1ff2cd774d2717cf8dea7e5f46bf8d6e075f360811198c7439890e9961e0af99706e22943fa7dcc343afa582ee006299365bff31d6b4df89cbe05403757c39ce265abcf6b9be0e21f296fadfdf1b19fe6069147ded369101518cd5907ca231da79bfced4aeac9e25d7d153e2b617cc3cab4caf32d010001	\\xac20bc1f3f86be8de2bed4cc89b1aaeb0f4dcf3d52b7b5d42510c393390d498e3f4f2ea6ad2b5d4beac7af5297fff7070adbd84f6834494f3fe54b3ed4c8b506	1680975033000000	1681579833000000	1744651833000000	1839259833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\x8ef29da77905716a3ee2ad23fc4f6167cd97aae3c66cdf2f4935866bf32ffa83b92657f3682164d8328a3c53195eb3bd9de8724dd9585bf8f2dcfe681e0e2455	1	0	\\x000000010000000000800003b50e524af7e40c82cff033b6083d3fa67d1acf581f05b2d1fc48bac6731f914a540b033b52102d918a08c1921828202bdded13f25fa1c3c1d133a0b683b599af9ffa38f9f59f9e103d752471403ac0d1cc8f7541b3c3a8de73921dc6f34265eaf67add0e0a57ede1453d9243f4665f2b5111dd1712b9d418321e6ba794a4cb35010001	\\x45df60f6f43a517a7b44a53bb5cfa362c7d8667d210e802a0be270c2011d71aa20c0bede98be5a29f4a3370f54837be79c4b09e699ab439956334c5c6c6f5f02	1688229033000000	1688833833000000	1751905833000000	1846513833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\x913e088f60d215a947dd85ed3cf052650a2e3cb3c21ad0bb39d8e16d8a0162c664aa095cd000f3ea31255e061eb51eada8274bcf2e425cd8ba5b9ce834750ef7	1	0	\\x000000010000000000800003b467b6aaf9d364bfda8741463cea70eb5cdfa7b4743719523e41aa7b618da1441f391d7dd27f58757d7d18b16a4235f35e0ffbccbe026702928e4f68e7a394ac0cc79a11034577457c596bd0e6a7a086d1b1288df813363cdf7d057fd5bb56f86e8c2c811369a605d972d2e4bc385445d38a2e4c47cf2eb202bd65dea881ab9f010001	\\xd743250a48b14f0f3bb1f96d64fe90ce62498beae4bd05e4da4cd73066f3011774eb8f6b6086fb36eb8c79a5e4061d04045ae4683cf6b6e54790413e05b7de0b	1664653533000000	1665258333000000	1728330333000000	1822938333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
300	\\x945ec8807929518a981762312f36512cc33bd04c010a7fdbd461987974232c0376ec76a0a943eaed09be50661371ce3f5a0b93c5ef53388f69aabe465c03bdef	1	0	\\x000000010000000000800003b357f72ae6a9098ea283d5052ffa06db9f61b02ab1ca16c3a0c3e08b3b3a0de16249a53810f4b45c4c0ad1775196ea620778489ecb978089c3a97e04e107fd625b554eb89fa223059356a8c9693bae360d4bc0cc8e3cbd4f3af15586e560c480c5b591d488e22bd5fe59c7c6988a727889c08dd5e2182a87f59ce13d24b48ce1010001	\\x600ba9777f1e3c42a1fa0b445c43d85355c5d1c4a3037cbf84b34f95316bdff47a7668731dbce5bdfcbb5520913145788c71b28edbd67792363734ecb6726e03	1685206533000000	1685811333000000	1748883333000000	1843491333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\x96bacfe7ada2675bce2d5eb36f2833c6726e6a3c888963e7e322b3754b1a579c2b7e4a50e857ba496958ad2b3d0ab32ae0deb5d7e76cb079463576833280533e	1	0	\\x000000010000000000800003c9c9d9baad3ddf95bc0160851531971be60155ce082457af86cb83d1c34f1be312022e4ae92755a37189db3f3cd99590c42ff924108b182bfe358acc48130800a120b13392ec0d0012eb7f0001892443180b4c174f8d22f03303fe1a58b11946adf6b578d76f04256e96871e5eb2c6a65f7102df6d7a619f73ad8634a10b6469010001	\\x803123677daa6902f9fac0829eeda2e35b5028b28fdcaa6277cfc1cc0eae83d92632386850e6b2bfad91250dd1379e8d4ddc5f82be3a9490f4505c5f4788310d	1671907533000000	1672512333000000	1735584333000000	1830192333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\x97cae73901007a0a846d3b5349b26c284bd49601e9f464b5b3365cead8c72d001b058deabb83e32a7e8bbc893f18ee10e260114abca16f25517ae02a7a1cdff5	1	0	\\x000000010000000000800003c283c6f1f85bd16657dc535e0e33533816b4e8fafd2cee249c5345856d430ffdcd01a71326796c0d17b47ee7033375219ac6367efd95c798e076304ecfb2293d4252aac4c9e8d8c65e4fd3e4b90e4c8ab4c662479439147ddc11ea437107e5e88bd488351f5c909905ff2fc4efca737a3c3cf6d844d3ee1967cd700a93f879c3010001	\\xb15011226b552e59c1e142c913dfc930f6546fba80d7d308b11ac1286684d751368e97ccd69174874f4b787160ee780dcf74b4ce5bf9ef8fc625042f17360307	1678557033000000	1679161833000000	1742233833000000	1836841833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
303	\\x99429e898cc7c93ee4447fcdc99692013169d969a9077c91aa2bc886e9547c5ca5803d97daea656793ac671b03a0f667209d6db70387f113459bd6f1c9def910	1	0	\\x000000010000000000800003b3de991d2e3727e98c662a23e766ff9d58a6e58cbc5a3e05d8dce5f9de93185f6ec295699a96b75a82f89ea7c3bdb9ecb5f3bdb0b433c14cf17fcd1546423f1359fd601ebec6234bed531162cfedf4e9ce179775d6569ddd62f2c7a4d09a051347e2ecacf54abcdeaaa1bb94d0fadcb8e31fb81959475ed437c28f299b883f25010001	\\xde73ac8e0c3c7e73e2df6ef0be2d71e61e5a175f10b0d8f69c47694e729bc44735cf2398c9c564f37ca905ad4174729ef5737f42ee36da33cae1e31e4fa25a06	1664049033000000	1664653833000000	1727725833000000	1822333833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xa3fab79be4aa7f6feffa714adef69cea66ec580977ff11c105ec97271267a9ca5f22d9e847c5f83e61ca6f01ae35dea4d4f10cc20448ece3bde4b24dd8551f0c	1	0	\\x000000010000000000800003bfae9f99c4fc7f1f38b8de1c8619c026b5fcf271fdcc2bfda393ab795575b484d3b2ef59410f698e61a78c3c54bc33d6a2fe73eb37f015e311c7ed84f787d09a3d965f3ff08c624b23e13109778fc660991603a17f351a2292851146c30a93fdcf63aa49f19bf0c6e31419ea2f6529f91ba4c37d2550678a7563316378dae459010001	\\x24eebe8aac6a7b05df3852417d98697baf4c72854995f178fe683250c6876ee68737bc4e4ff731fd19eb89c8a0540017f589f71497b9b957856c8a655959bd0a	1670094033000000	1670698833000000	1733770833000000	1828378833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xa49ab1a222c1f445ecef043fbd78a308624c00aeb649adf742fc2d62b598ad03267183615a7a60b591560fcd8318c3b9c7259d53ddc9f1b6f128a93d17569415	1	0	\\x00000001000000000080000396e9d954041ec7504eb315ab1dce5bafc5345ffaba6d889ae26b94ff64bb5b560a1aa6eb0f4ad6f6baedb06a3412bb0cbc594b7b520485c8af12692e2b1865315e85f68a895f36981e4873e0ec28eed454ebbea8a687448da490130ac1b6e40e6a85ab6f04264662e89eb161f04c39e0ad5b699a299b0e9d374bdb9b87e444c5010001	\\xfefbff4dc88640c89b23fc33ae6cec0c295ba870e1c70557c627955c1bac8ee8f01a7e1557d9349dae6ef7ca1de064ef0161d995e4d579228c8ad0d1e7874700	1676139033000000	1676743833000000	1739815833000000	1834423833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xa7c6060b26e7d8e169c4e227fbb525b491c9925f61012ed7ab0702194b7110d009af82ac2fd7fdeeb6f2044512ad95bad1969e95256820a252c403c33fbca41f	1	0	\\x000000010000000000800003bed6c9969f27ddaa832c1aba50059835e535f385a1dfc11a2297ac46e3d93056f990b85ab79d337b3278e86d46f6ccbe85ebc9b5888e71e3696e19862fb5f280eb9112f1edf4a3a24f6babedd7aba177c2f8a178deb7fd8ab2d114b8e0a91f0a6eae8d4b4ed1626209fc0a4c43eb5047c9ad72af98df9e7507b880eacb4e6a5f010001	\\x58a0b74f0c4bb7ac1cb1bc06d9920df1966e65d9294e466128f1b0cbf852886b2c5c8d3fb2695e71f7dd702cc8e6806f46362db9bbadd058f76341d361419500	1688833533000000	1689438333000000	1752510333000000	1847118333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\xa966a8b56a2e48496048e9bbd7ee2e4349f10fdb647596a140a54b766a3c6260bdde1ef81e82b69e99f7fad5b78c895448e5ca656cd05c24d7987591aeabbfbd	1	0	\\x000000010000000000800003b7c189e4b5d41392744e228343e8a173db37c1914228989c45134bd7bd4aa4cba247737ae535098686016935d972deaf5c6f1cbb2d192a72324a09ee9d87c54c03b72a89e874020f6602ba0dda086e0fb6e7ca2cac4c266aa32fa42ddec27dcb559bd0ad7ca77c75b4744e4de0080762b8e8fcd97c3031e1a93dd1300ec23375010001	\\xdc25eb9d4fe3cba9c50cd3523b797e876beeaccf2aa5c57bb80b2eee000d8ac21fcbed79c2c9946a707e8c5fd0e56f11071f718154027e8498322dbe5dfaea0d	1690042533000000	1690647333000000	1753719333000000	1848327333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\xaa4a38f979a15af8d1a6f7304f1250fdfb6498f8949dad7db6dbaa4c251f758183d803a06781fde0de86e77da45b85faab92fa0f8524f5ca6d6439db78fd099e	1	0	\\x000000010000000000800003a4b98091a18c5fd77e0dc65858b2bcffeb88155f4e7d52432a574bc648b0e4f780483dbdf5cdb1c4ea141f6e31e5cd327202ef415453b8789c1aeeaa596b11dee36dd6e41cd9ad0975931431eea4f3ba9c58f34f3180d4f116d6ab90efd0628c4a47b978fc47481f8a7c7cac7ec2f88332fe244997e8a914d0ecf10a5905c275010001	\\x1b8a33d1c5b48cfdc758f1088e1fea8ca84c657621888061d6ffed6cc05a82126129217220131e95bda5c886396ecf5f135a523432f7b5c1f4a3ca1ea9d92504	1665862533000000	1666467333000000	1729539333000000	1824147333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xb0ae973d955f3759cc81e205cccdfe2a9d1e9528c90807ad0bd313935abdd3ed89b26072cace4dd8e1a31839b6a548bbf72fc18c8bf954b7ed69eedf764a70b9	1	0	\\x000000010000000000800003b01a14f9e7530cedec4c2898b0fb536332111d858f908fff65bcee0b97cfef898032ae7a596bbb0f6a221c1a0b8f2d1c070a0cfefa44cbc95b0794c244689397e72436e0f93278bd85d9f25b0b22269d12cf4eff611c85894902382e0fa7397d389d7f0da1bf7b4379a73b7f3bb0bf81c83494aadc051c959dba55432fa6ae89010001	\\xbfe0ce4ea309e3e6b24887134218b18c60dae3fbe2905edde081b2016ff07b1593c0bf46805ab340e6781bf7628b0387af9c724dbd10e617a00f8525a68f4707	1673721033000000	1674325833000000	1737397833000000	1832005833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
310	\\xb1f2da30756d51f9bd3391856d7e2d048f258516b3a279dbbd44f093200aa1160d3124e4749849e120227432d3864fbd6adcf41015c03b135cdf4bb1f5e8cd6b	1	0	\\x000000010000000000800003cd5abc9b6aa69533cbf8c9d5013ef4d722ae4dc18938b9a28dd292027c27aec0b7cbfed32b97c028b031d31a5297ce4a8c9152beae2aad6ad206bc26b492386d36c4575c2e303ee14145b7b1a420a7b8831c9838371cbf9efb72ff3146dc1460d8c2ad916c7f54a42549fe6fed4c704ba4657674e3fe0d7ae15b9a5c4d43728f010001	\\x7902b654c2b70d28769852b81ce252db69427006e0f202ac2996095d8e57be610cc9cce583a7abf20f1eff57a6484f1e70bbc53fb09e659cce62f80ec274b905	1685811033000000	1686415833000000	1749487833000000	1844095833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xb2a61774398c112e6089cf94c0f656b8a5c4f68354b3b49f03987c91493bf6c84939b9628017258e77f3850573e186f253af4c34c353c8438213b0c06a7b4401	1	0	\\x000000010000000000800003c8011c5e047c2e5aedd0f7eaf9aca7e13d79951fdbb276688b94dac737ee44f748da53b0912520a10d53c67490dbdc39bd3be0280ef11422b6db07a32009b48f99c3ec3dfc46aed9942387370d0dfc09d82bf2351205209a9a5cb103aa0da9e62fcefb24eaba6b5cf1404086483d72e7d082e062efac43725165710d7a659abb010001	\\xbf370bb6485f486f835a2e071bfb62740e1eb6f7262e30c6de447aa900a2878fa775da77d1a2085bbd434f9ad9bfd4d8e7ecc14f149d4e7bb5f5bd4c0b5c7900	1662840033000000	1663444833000000	1726516833000000	1821124833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xb37ea522ceb8dafc7abae5d9804c236d881f1e84b4b0168c77dcd84518c3984e8315cc31e8f62a91cf4ab3a5d298d1f84d06279a84ba717ef91941fe3c953596	1	0	\\x000000010000000000800003cff5fa05c910b6615567f42fca37d9eae081b2f856a6715f5c786fe072533cb9c9fa6997e100cbde3f3e4270ef5c94e01c22ea9a4d849c67344e94b7dbf68c82ec78ef87dc4cf648f469a0bbd2bcd0deea9c08cba79155db984def49d42932388340e4aa8dde5ce38c56b8725dedd2cf6e3c5f12780e9f4eea7497c2fe20073f010001	\\x03142b132d6eb39f029b847c3326308270684e6de75a26e6e342d60b50799d3b47b80e3b8a0afccc13386970cbc4f49fce6cf52e93251bbc11197a59be67c909	1680370533000000	1680975333000000	1744047333000000	1838655333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xb31a0c97525b4cadeacb794bbf5a41688434d788a29df762d1c01650f5322f025427a3635821199e2858a0dd36f41a5cccdd36eb19b0c1f23469e9f88e40636d	1	0	\\x000000010000000000800003de1bf0caaff6d18374c5868a8db389209fadc6e9235889f8776f203d4c20c0cdbb7fbc38be35f1fec81c9edd48a8d0deb39b61dfcc3f7b01b9f0b2e7e142aeaf6b4853926db0387edd18013ee33a4eff2feb8aa1cb27278f73fd4b7dc0c6b4df504e167adff33378c084d2926b72fee1e519cfb166129731cdfb41f14f341d2d010001	\\xe6debf75b79455b24dd4d817919f117e092f03934abb9bbc642e98b726733dc3fe82103a4894edbc015b92b889b52edba90e4be030cf6386f2287012053d3604	1675534533000000	1676139333000000	1739211333000000	1833819333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xb84a981e24f730d768f3c901735b043220b496831e002fcd5d318b4c724f5f70c17dd183b8c30b9a7ba58fe8c5d3e6e009a278826abc3f58f3e205a17d0aa840	1	0	\\x000000010000000000800003b99ef3794049f4689f5b4b57f65aeb8abb5b80fc8561c8b479368b1d49b11ac994008249213d036cb203340d6b67cadcdbcd25500cbf5c2c383a5595e1682f1140ebdd98e034d22d09a2e20009cafb4dceb0a2cf53449052858ce3360ceffe4a3e045d9a877f16ed506563143690ecd1f99061604e495eb9fc38a03efd28ee03010001	\\xbadec6d3fade1b322731f2bf3b695f664fe0d2d5c2c25375e8e6ce1cebd6868b122470313b691f37dec13b386905cf2d281d47cdc27a52ab90c6fc4342673f09	1677348033000000	1677952833000000	1741024833000000	1835632833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\xbbd2325e7cc4c37534513880b08df2b513fd1729b63e44f2f979713b752ce419e63aa8e3bafdc8586bf6bfa6444b75fc449c75a8fa7babd0e0ca81d1ecc995a5	1	0	\\x0000000100000000008000039d5a4fc42daa7bf11d25c3a076911c46c01846237e38e5df93aee9bed92ea89eff8cee60672d7738a7835856074b7ce0b7bcbce00963a8d6c6daf18352106384330b08557c9dd5597bd1aa6184bd29bfd0b6613bc2f2c1e4b89ea6bf5be938c025b7611c5bd4e4c808378a97fbc9193ea547876127b30bbe5bf9e687a90e5663010001	\\x6a0112bfbf3a5187a0404e13386116d00657d00c45d6a147c80cff0cb12aa8890d2f71d438450a2372b9367e2bcd8a96938920abafbcb61f4e57288d9293bc03	1691251533000000	1691856333000000	1754928333000000	1849536333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
316	\\xbeae03968bd96f92cc451c62166972a1448a111f023662df94e219b45b47a4b0eabe39b9d0456fbaa46375d950019e9117b01804dca549019ae562dd27c743e2	1	0	\\x000000010000000000800003c3bfea0735e3f999b8b5edb80e145874864de94afa075ef8d3069968d07410bfe7751cd79106a40ddbda7ccabc43e30349126fc6148057ef5c13b9d79e459b2478132cfa1f202d483724f5200b04c950d44fa191440f747c08ff64b5c1a39a1a56e8021704efc4cd3110d3a95ff6d6afe47ca8613d264ab939a997747bc5f1e9010001	\\xf9b3eda8d36a034683cf7b0b58c242a8e57407e3b031cc5d3f0b81330b427fa359adf82e0a9c6ab51bdd633661401fde20a5b8c5894fdd46a5ffb0734d39cb0b	1664653533000000	1665258333000000	1728330333000000	1822938333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xc31253ca4cc9bc3fb6a16bfa114419ccbffd6883a4db91c0da614a2695819de9e1e7061a74acf890dcd04dfa02497598f8e28131be3c4229e2d63bdfd108eae7	1	0	\\x000000010000000000800003e342dc6a99e0ed916418a9a9c0c1ab9665adaf0ebc44e977dd60ef975f78b3217d421f1dd9b4172cc55ffdfd78fd66f01c3b0c39c164ebf4b872625bbb477b0620dc1514be00cb8d9f8e0d1e9ecf24eb2fc34492816081351f90001e050f327598dd41d275929b1c5ef7b4750d965dd7671e2fd5d0667df7a7b3233e7cd7c865010001	\\x4c5fc44c359d40b29a1abf89745dc90122d85d937cdc958678332617eda1d0293e1e4d221ebf77fbf4bed1bc04b96677a49a5c4708cf857db960285f1ec4f70b	1661631033000000	1662235833000000	1725307833000000	1819915833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xc422f3a9e6f558b85729820e576704b3492dfec04b9c62d633298f063cec079e19f9676677b4584e0e9a5a5c5d14fd15b3cee55559450b0e0b993a5c50bfa5a3	1	0	\\x000000010000000000800003b3ca94e75a8904b597b2c549d75f71e279a531db0c475529dcf96da0f03a96d1043d525f666997076f04017ee39b250b5d641b81b60acc4efefb162f9296a49b255f434627f30af7367ff7469fc12683b73da1a1818b61c0984ccfe394710fcb4cce15846b693551a64176a93ea3e4efcdb8658df099388f1dd67edc9733d533010001	\\xfd487d137343cf1293bc747672cf7db3f8c1e1776874f2678b2b6811afe37e05823887af884720853006f95fc70aee3178c38793b3554636f0bb64305f321d03	1662840033000000	1663444833000000	1726516833000000	1821124833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
319	\\xc72efb98ef59018e920beadc41c165812d896a280a0a1bf62332c5b19d457bbe2828d3508694fc4a8c48cfdf2cec1c1d25bec1bd6acae82affeb87a5deb5c6b3	1	0	\\x000000010000000000800003d6707041bfd0f7c5ee9f9d4f5f2b9c9bcbc4ca1ab8f9e1b60089863f4f09f0c666d89980bf1bf8893c29f75efb938179017ff52986b9eae587d46f8ebdd490ed1d55528d3758814c63be36db6e198bfb365fd003ba8032c24105229ef9be300d0e8437110adf22b64c0d621416f5ab1775652646314e0696f1af56cfdd313b71010001	\\xbe78e2edfe2772761a88835539d7353efed3019d37b8ab6688c7fc31b00809706d6508fd9c5d739701382180217f12bb1c9eb6cbf80da3ca8aca736f7864fe03	1676743533000000	1677348333000000	1740420333000000	1835028333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xca1676e89f4fa1a196116bfd58ab6110b8d86a6aa6b26329a9279bb44e623327fd7e140b3de312af63e048235d07ef729377e3c5f2e247e2a3c948a676ed1c3b	1	0	\\x000000010000000000800003ca63a07c010dbd0cd02324b4eb8eea51c1aef541f6406b34aa8b7299ba55345bbe6c6720f3851da866deca3e7dbf93d8fbfdcb6a3b0b9c686eb242a8a4314b8fa41d7be9d4b7630e076b96c7b3faee446a4ea0a99146060926167158c757f45c22d4e8494f28956c8e24af10eb029400d8b9481eee8b24dba582f22fd37d5a2d010001	\\x6467cbfe804495b7a5c8dfd062ec28be45a73352c16443eeec5c5bc6dffb2d9ec4bf6e43f75f8b2adff0ebd2eb1bce96e24d738ebd72de3123b5824e3142f506	1668885033000000	1669489833000000	1732561833000000	1827169833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\xceae98bc9d951179f6218ebb52b7ea559ed09e4e33c42272f556df71e8d4e19712891e86a408a26d943e1b05e7b5ed905f89ec9975aa8a0376439a2878f5500c	1	0	\\x000000010000000000800003bc2dac8e1bbcb56f43e85f230b17a1de6a98891189af9481d53f3b9469737bd077e4004fe5662ce3caff7b7fc18df0586011cad94b21084933c0fc36befcc8ce55b7e5e2f5aa52de96c8e4dbc809df5bc2e81ef61010a77ac487e5ecfe42e5ce92a1dab331d205411fb9e326abbb10fa90097d3c3637dfdeb66dc91bc0687b0d010001	\\xa8642e4a4487803c2f0b6d0f5228619c954c11b256c6b24aa6a53da2826450c03b00c70dd84879eb7846ff2bf1dd459b8b32f2af5405498d6d25edce612cca02	1688833533000000	1689438333000000	1752510333000000	1847118333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xd4828a223b4942ed43f3672ed7d377e5bff0bd64ff1b891a0069a287ecd56ab72c60bbaf58a94055fc20c079a0abc41c3e462d0661ee6ff3e015216dcdb9cabf	1	0	\\x000000010000000000800003e0f4a5597d2848459343f1278e64609d4f172280c65c705518dc8cad9d862dca9a38b2e368b1349fec88146106773cd4656817567ed2cfb0e47ef5efed9dd8885798fa72ffd0fe73949d804a9626ca2a5288c98e9da1d2109d305e853a95305ac63e13c4571587cbe11272297c893b08dbde0ffa56be8b196cad948923788337010001	\\x7cc9fdf2e2d6dcfe5fee66cf183cba0f90868c3b2bc0c87bc224d5f4407d14259a7ad773db20c49e07f593b72fa72d49ce2ac5c3a4888d7b26ff48eb8b5c5f0f	1686415533000000	1687020333000000	1750092333000000	1844700333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\xde320b621e71aa8b07976a11117d2c3626951ee096aa81190e9711579b1ae4c3248eb9e9dc9d689eec5a951633987e40e97e82c87deb80d7998ac9163c4eaaf8	1	0	\\x000000010000000000800003d6e67754fa0dfec71102e9606859f63e77aeb0087c2d179100226fdfbdf050767aaf564abc693d6cd26744fb5e27e2b2f78b6592c9ffe6cc4cd671487cc1f07d61cd832afcebf5f71a9dc3cc93869a2ee3cb271d574722451d71481fbc143aba53e1ad4638ee0486b9da3920d37f4dbd90ceafbe6ecf125f11fe6e9149efbeed010001	\\x46b1513c862cd81372a23dfb866f00851d327176164276757458bd5c4cee6979934c99a659b70dd83d077fd182003cc3d5ad230da3f4e01dc975406f14a27f05	1661026533000000	1661631333000000	1724703333000000	1819311333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
324	\\xe0b6c4df6437e22306d982622ba6d8fd2e0e229f759478ba1806d19271f490032f26b6bcb33c0e69c1092db6476f480baa8e14b2bfb61595b64000e0a649ecc6	1	0	\\x000000010000000000800003b424bcaf159b442ee6744e0fdf424373542c6a69629b488cb4de8ed2e9e206799c2a72046cc5e9ce8c34b42a5919431eb5237b037c19f6e7be316e4a8a08d49df5fce648573b71de667058fd78095a08b5af5a46d5e1e5fa05fc90dae723fa778414139c160b16eb4415300d5a7341d4a75601884e7f66023fe54d792e7bd46d010001	\\x886cac655e65bb7d320ac9bac65a790043522eb72848102226376318f410caaab6bef97915e7ff036a5c456cfa24e25110fb3b0c6e02249ac0201e2d816cde02	1665258033000000	1665862833000000	1728934833000000	1823542833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
325	\\xe5eeaada5d0869a557b59ee5493b43e5b3bd27e2a69abaffa829848ff2a64fb471ee1aef85acd58ad3b8c822b0e57fed9c7a57b3f5bea9d77ed81af10527d039	1	0	\\x000000010000000000800003c0cf00045dfecf9b65fa6fcae2e58f8695b5b1af357dbfd63ded479af8196862bba83a38a6390e31c36e91a23c692daae9d6a975f2919d2005cdcbf499bc152d59fd47c65c2d6c70f8a7ae6efbec30401aed2faead5dd152ed142c2c168ab23d69129d5a81379ab4cbfa468e5df0985c81a02d8535edce57a2d605069447c0b5010001	\\xfb0771af402189feebdd81dd2c29fb732022f59682856c408572bb51300353cf9d46b5e283ee937bcc182250684e16c26767f1a4692bf61e8fd49806c1936809	1683997533000000	1684602333000000	1747674333000000	1842282333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
326	\\xe606a52058e2e78b9d4eaf8d2bf86e47e09024d4c63abc6ea55f38d8a863aa2ca435719176047bd5d60d9b2aae929ffd109cd57c6e191139f2986d4c87122f5b	1	0	\\x000000010000000000800003dcc6c36403955edd99b8a153e089a31eb796739d7cc554c7c3c25138e5ef6b7d30b671c0a5e040ec015fa24c6e7588e9a9fa2519c9147af3543377df3ee0de55dc8e1945623b27ab7e3c66b7aa7b9f1beff6ee3bdeb2a996343bcd8ba1efb8742e5c1099602e06c10584f99cdb4aadf9247712b2645123c8d73c375a10ecb787010001	\\x03bb9093a5ec360e566d1627520ba1a79f542e36d72fd9902079b7416fabf02698eaef5afadadbbae167b7af9ce21bb2dd1d99e8ceb0fe2751053b5d2b772308	1675534533000000	1676139333000000	1739211333000000	1833819333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
327	\\xe6629c58a8a171f77a742f9fa879f96f7c075ccf4e6a548f5938a584f571c17191167f58b878cd001b296170acaccc1148f2dcd234f0e6028417457c4f21f02b	1	0	\\x000000010000000000800003c6d82b5d450f0682797fdad117fd12833691ec69f787e07a09c5595711f23f04267cbc22c3f81463e3272a23f468c827a774493e9f462251b547b8ff1b3bcc19467a0e59f7213c0871a4c07f4c9e2b9860fd607723e3c4202c769af1b0e9d1688f1a1335546a8eada8d9c926711c05d3c86c04c7a9e5c3eb1bc46a405f371e07010001	\\x7f76452602431cfdee254b2f6020abd335f648d54c861884e9f280146e48f8bb79c972e93e227f4b33ddb8bb87219b51eab4f0d8d4ad9fe0684d2af9beb92800	1661631033000000	1662235833000000	1725307833000000	1819915833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
328	\\xe69a96ff81026c1f829a8c275ebf4b59a0251e2c390a80f83ee14f85625713cdd60d83d43d151a562be9bb044e20057bb1094fcf0fc963aea307dabad05843df	1	0	\\x000000010000000000800003ccc8d67293931a3be667783541418b7a9c259d04105f356532b141909a70410e09c400095baaac3113709a892f73f982c01e71bb9428879ba7c23b2734397d42029bfd4e59e67745e3578cc905947f3823f10eb5ff3d60e2af6fbf6100ba76eebd45775a4130241713e95e0bdf3aefb59df961c8bc1ae482d6cd417da3df87ed010001	\\xab5d87159ff657ce1c466b98538755bc73b6084c713a25b05ced83e017a97a17b49faf9ff8c89674af44e7923be259d58ae1e5950e7549935abeb8a782835f06	1662235533000000	1662840333000000	1725912333000000	1820520333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\xed160c18b4306154e3bc9d3ff4b0923831de86660699be47a2e853ebd8d6973e526715de7100ca7ffa782d404bb83eb638124a211ec2922c1c2db605def35722	1	0	\\x000000010000000000800003a4618131ed6abc7313fb2d50f394b32c3f4c6473d8a3470c1ef920c2a7c0ec364588172ea7e77f55f4be98f3e5d162e3135e263a955574c3d74f24234132c9d031c20cde11a7809aed4d13b107bb690b8fd19a4fa41a6d09a90770af143f6b3389ee146863e6e070f4fde6db875e7a2fb9ded735cdaf658db86c8738cf56efb5010001	\\x1ff977609041fede5e1d27845a2010046e9e8b326e6d9aec06c344ea3c48ef6baaff0497c8e16ef89845948068d457110602676f99222079ffe70c380fb8a201	1685811033000000	1686415833000000	1749487833000000	1844095833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\xf06efe1b02a0531516585e24cc3dae7d457db647e5c69c165a0cbdccb5af67fb2d1f8f0c59f71b17d98eedb225e0ed0184b6af7024e3329f15e16d7072b61e89	1	0	\\x000000010000000000800003b633e340df233e781e40a1f5efc0f07db39d45a3c707df8dc7cd8362a00d5c1d0733d14116188ebec759e26088f3f7f9af9bc6b0e35dc84ff353815699524cd8395b8fe0bb8c6565ee3508d4c21263f58cd53118e281bbb91240957383f035e88fe867ed93381284e758bf4f560fccf9166ec0fe2dab593d9304a6593310223f010001	\\xfc4e3c3ceb5012ff4d7a3444610f9e594b4821e467adec63d8c42eac990b47c0e6a58b9388cf4ffd55e0f463e957186954212f49b2250ec0c9b1c169657a3709	1670698533000000	1671303333000000	1734375333000000	1828983333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\xf60af518ea760a68e3971cd3d5e46139871d478dc9a87f06c5c51edefa56ecd2dca29891272eb6b7f02d874537699caeae14458539ee2bc7a0e77c48a86a292d	1	0	\\x000000010000000000800003c9353701474af91fbda9efc21ad2821875a62c4207f8918d09f1f50f023e4ee9b941027c79a445069f8045c18c0144aee83df3deeaaa05aed097095306fa2073191b2707cdb17be0cfe20d980a6d433d4e85a936d6f37ea64d542bb8ae710c7fd42c2b39b0f318bf40aeef6475d308e64fceffd70aea984bf768352bdd7e4e85010001	\\xd5d75d220d0e89c87bd90ee1fc84c705b459e93fa87683d6371247b125585ea81db63ec148f1ac3ec55dee2c2d9b9c5605ffd755045a6b0b6d2de9526022cd08	1676139033000000	1676743833000000	1739815833000000	1834423833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\xf7be5b4d81afaa89090dda9925e9f6491f8604b2a9dfa5ea465c97ce5675e9d11f52bc4145012c0d5c9fbe1826833327071d7e86c72eee82d145c186b2f94c00	1	0	\\x000000010000000000800003b3e772b0d320e4ee898a51f4ad3561b49687dca921e3fe47bbc836f67d3c4926d0cab31630d04088009ae02b2ce382aa07c5070ebee43f69ceb893e9ecde64004edef024c6b78bc81b3d0baa638a5920bcdbc1f1e285aff6e995e012fd98ffe05b377d44ef68b915b8b3a9eb79cda39f8932d83bdac0e5c5df9e68ec97fae163010001	\\xb4689202311771c6efd31e87f19fa4f23c901b26b3f3450a9f76cd18abfedd165e2896d5763175b90d923cb0ab2d378c7ab1f5485b363b415daee3128a9c0b06	1690042533000000	1690647333000000	1753719333000000	1848327333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
333	\\xfb368b04c200bb92f22bd746d0b653d51d58c8cad19dda267a945c1bf301b1ff6cebdd0aea261060cac2f7de507b5e9e1a0f50b3b1917df5dcca7a7f8e5dbb3b	1	0	\\x000000010000000000800003ba568c9bc8f00e50c6382b6ea98946300feeb7ab1dabbdf36bbc947ffb12bc350232f132e5972bc666613beb4d6a8577cbaf05e9ab489323e0785c21c49f1415386383ee7f68fe3c5cd8777f8eaeafb33d1e5bec2ad5ac5379273821f92396ad312f1234ecf8149dfb128481875e5f841b4876dd34290894c6c775fd7c762295010001	\\xd7ba667c1cafe6e55e5b449771e72e1ac4443be6baa9ec1f5b35bd0df8ed18b7f7a98d8f0467cfc82c7a677424c7ebe5760f53b7ca699342501c286098b1a303	1667071533000000	1667676333000000	1730748333000000	1825356333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\xfbba9d08f441dd3a8041dcdeacc7f434bcdb28f766dd6144cbffd957a88e10ed2a02ff263dcab225c1cea34be5773ba368cbd04acf215b7543a85e703bf37afb	1	0	\\x000000010000000000800003d78ed213a854d5b68907942e93a482499f88248599c35213b80db6b0c0eee2ef0bffab280139ed464d750ca57e751189d0968eb006f2b9afb7a71773d744c95e7d503add159ceef0934a2c70c230697b6a223f71b7a9a44580fdd31db1245e404d38e04d00e559666a55e22f563329de3d796d6d8468d813f495c3ec3deba387010001	\\x890d17ca951c898b14f010e9b72e5e3222d540c37529daa3dcaf6397c3b3c3854bebd59845fa86bda62711cac79ea4ce31e7da1a4266bc73734918ccdab48706	1667071533000000	1667676333000000	1730748333000000	1825356333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\xffba29fbec52f31c9f82dd25092b9d879f1e12084367a2813c5cfe8f881f6477e57d99c733a97db2f80b39a82ce73598db8d911c3a8eb475f563cdcb520025d1	1	0	\\x000000010000000000800003d853b4f9644f91482dc9a3aa17dcddbbf42481a0ec2711311b8f1f8308ae0aaadae117ce639c4e624d3b3086c45664293b09603b1b9494e1966f56482ef9e78b83b7f5a33710c8cec1efbbb5532a6b706bd6f3c316d17ecccc5a636214d9c978cfea0e4d949de9366842a9ac49cf95b4c989d223cb71248f469c566facfaa997010001	\\xabc493d0e4691e4b2e5d9d6f7a5ca6ea74f429fe27c54acef395efd90a373ee5763810b763db613445bb6cfe494b9d05a11fefcef4e1bbcdfcf116ca0b9f6708	1662235533000000	1662840333000000	1725912333000000	1820520333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x04dfff8259e5818a945d405fb1ef7b3ef2261a2411f3bc78c723ab37cb7cb1d778098fa9506e397c6a77b0e17b33ec43f8371b815bbabc497c9fd006fd049e09	1	0	\\x000000010000000000800003c45fa6e71bd4bb995caf7229ad467329870fc4379aa7316d6e5e823f513041bc72bf9344218aa2e5d1b7502a17b4c62f810bedf7c6ab82ab0f45f938aed18c2c7b30b1ed053da7ac51d00471e8e59fe9ab4c35b910f1843b1735efedc94a3f468a607529dfb7a9d6dbf5f33020fdc8eb4a9689a2d3508ac338c2d249bb814a63010001	\\x3caf8c167c78147070140c17096130097ddbb723bad0189eeefda99dd7b451f7e3bb641bc62cca34a2cb6ea3a143f6c06d1ecf8d33cfdbb38e736a59687ab104	1679161533000000	1679766333000000	1742838333000000	1837446333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x05a797e0fdcc00c0cb96bcf0c1da0820da1c969b1c4548458d1ff928769d61aa227de2d65725b23d71ff2aeb08a74e2b2cc7f9d6304d14f798531b78bfb277da	1	0	\\x000000010000000000800003eff47b0584de5fbf34536b52292d6a490af5e7c682c89b7b3a016f0c3af2bdc52f300a679495cdcb8e2406552504ed70a3ba8dc21c3d10649fd62370a7033aa99a55518443b03afff6794b6e83a820bab1c2fda063d88a182fe7216a51fc551d8e8215d9bab01fc0c03f6d1b024d4bdaf3b58cdbf4701bb464d41a049e59e833010001	\\x1bd4f009d9d8d2e5069c646cd42548f5a0554ae0652846b4b577f481cb0cc82c1923dd447a88175d0f352fb4745dbdf2fa36ac4e512981522608b30b249d480c	1680975033000000	1681579833000000	1744651833000000	1839259833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x07535c9f1bfc65e710e29082b019ef4ff4bbab6a56a5cece3e9506ce08165ca90c6628a0b25d5c9431c33e537e1b20ff791bf58fa2466e6435304a99632affd7	1	0	\\x000000010000000000800003b716ad517501da976cb7dcefa7dd7944e674172a57614beb7a949308300ae5ba443b7b9168efa90c0a5bbe71bb05dda60a2f8bdc5c1e7014eb5c7ee48e5d4b5229278e64a7821d83d2a2d59449ffb1f15a3fb323318c3dab01ae2f4661aca40a3003ad3d597d9ad249be323168e62753e902de3a8b1ded691a5a092a4657b423010001	\\xd6ebf38a1d9423879e292b82f6478d293cb674e4ec2cbe76aa910bc082480df9dc7c7c6216ba4ae09510786b4e0f8f38b82ec81716c93c2b47555215fcaffb07	1682184033000000	1682788833000000	1745860833000000	1840468833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x0afb0aeae0082def22dc1163f8142749b5c2ce261f5e8aa8b28a30b8fd7d9bcbdb0453cde5546ec498eb8229dd864a81b28b810ce5016cf154607fc08e6f10b5	1	0	\\x000000010000000000800003be1d020df6b9d174c0f5d397f4a23b86a7715b8afd30e7a92e31f4d7edb9c1a00bf914f9d0cd0882bec937ed696df05d75ae267a7a6802e4010d50ff82a764d4aa90276a19caf763fdfa0be91f13a8ad3c4618be8e7d95b3323d9303af45aac6e966509ea3d9033b88b71c33e024915fecf95c6350fb9a51dc82d5da4aaca5f3010001	\\x4e63adf4aa3dee8b7051cff5ed80be3869b4306d33f3b581130679cf52d8d77522fc9e8c1cad908f4e3536114ce7602807487ffe7c84c2455874134dbdf0a701	1662235533000000	1662840333000000	1725912333000000	1820520333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x0c13e4233b760ba2ff1e39e16442565c95e29b82ab983e02382e71114cf9a7ff412fa84cccc31fde171b7ddd24695079cad94025335d7af294706071bb473f05	1	0	\\x000000010000000000800003bdd9271d3728a4c606ad7db2e181b38d40b80cf0f359db0d5df42030d72a94c03cced3571fd03ddb6c23eedb27e9a9571de5f37d6cb5179656dd836f0bf1015a2a2f69dbc0c10240f45aa21697fde732c906276223669bdc6a98ce9e73bbbf81fd8d6ca19b8e85cc77cdf3c980d43107a21fd562763c1644a649197ca3d7215b010001	\\xf5bea121e9cbb5e9c7ec52c30529f8804a171b78c62fbf1c32eae27c0ac2d7b61d6d1a1789d0a4edb092aaf323f848b82900cdda2f182f2012dfde50e247a108	1665258033000000	1665862833000000	1728934833000000	1823542833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x0d0b6a248ac288204a9dbc372a8fe0b272ea9966a00e20b0c39af50d51be602ff2ac84d6c3ef015ad98e26791a136e7ff23074b484e48ce765b4f07f5506a7a3	1	0	\\x000000010000000000800003ae172f3f60b283c0cce9e578a6c6b4b11f7dd2e79ce2ce173c2dc62acc0e0b925bf231ba48ae99464bcd63bd49fcca7b71ddebb51f97242b2c3fc793400b96eb225893c9f6e4d02f45b0ff96d33ac41abe44e37aa5e116a92b58f0427836d23398a8c21437165587b078aba61258862c24f28386402f286fc4786d39e978667b010001	\\x46a689a69291df99283d31042b4dc946e66ba650911a0bbcd34b82011c37e2db6d5f372896317692f2a51f6100f97da3dadfa9f03768084ffaa7eb613ddab903	1673116533000000	1673721333000000	1736793333000000	1831401333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
342	\\x0e4f32ddcc53c1098587f0b95b6c207a88f9162c9e72f9052bbfcb16093b514944b8f631f5c3bb24a137f934b40c4390ca27abd027b5c6bad837f60004860104	1	0	\\x000000010000000000800003c860ef1ec714632b2aadfe966761d7a5e4ba8ea6e642224e89ddbfa980d2e1ce73bd32653b5247856987180f166e154c00c810e5184ab1c27088e5e2a013743d17496dc6c0c9e37abf1883fdc7b1ac56f51f12901633eef1ee5a264b4721c5acf49947413a6a3822a0f9feda3850a5860278b4823144f2af2dfa761e26066cfd010001	\\x81d6038e7c8393d4857dc778378d392267154437048d7a9e9aa063a845fc3ab87c71fe31af501c49c62a348a19a0fb7c7e9df67bfafc6873020f7dc3102ee90d	1683997533000000	1684602333000000	1747674333000000	1842282333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x0e4f5917e3bbcfa1e7d5e401ef91fbae767872ad877a11e6873bc6eaa7bd4ec3706e584c46420b3e39c8f29b277f5a6acb67dd9299d710dcb6d8a60997062083	1	0	\\x000000010000000000800003c0d8d998338f7430eed603ec5fceeb395b9796446ce5fe552a76a60af0226515920400569ff53693881d019c0e8e9886270ce1775ed531ae8beb42652429ee497dabe6057931448284d7f6d3686b1d6f7bf33f615edcd7e6ee78971d3b83f8c5a15a8cc1615416c47af6b14ceec5ecd698306b2995fc810c3edc51f8b3b317d1010001	\\xca77454251095af9f64667c186e8d9d7147ddd5a5f61c2dadcbe7b078695698e95c640d48e779cf9c7e4570403f2c311b60b35429827a3ba4a07a3e1de291d00	1679766033000000	1680370833000000	1743442833000000	1838050833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x11636b0d1330e29fcdecd46940796a30b9b7a47ecfbf919663b21d36c6804233ffb3e9257ac01179adb0567a33f4bbb33f9248b89a3da883db2e7ee312ebdd57	1	0	\\x000000010000000000800003adbb77110564709f6d8f7ea1826651117ee510bc8305e444e63db57b94514a197063fbc2abbd0e6d5484cfc6b8af59028fd62b47fffd1eeb6e57fe4a2b6a4eb0654f9c9488a9138448fecc499803d5be008e039418c0c7422e5209a11a7cfa9f5d7c8e7dbc307e4fe1a1d1dce030601e266cc064f9873fa8165cb4a297cb277b010001	\\x3a3b404b8abf9c96e94f4225a9bfc3300431dc8a1222a5e1007aa48aedd04f8b5ac666be6e1bc35c14781ccb3b390517db0ab4f6dfda8abd40174575562ae90d	1688833533000000	1689438333000000	1752510333000000	1847118333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x11b7327a1dae33fbf5a5c04a95d20ee7d0c16cb0b8445bbddd2bace1b9e202b056a68dd7b570a3ca2c5c162a4e22acfb7e0bd365a1206d7775ddd7ce1ffe0630	1	0	\\x000000010000000000800003da918f984bbeb111c4a9120e246b18d97b05439cb29cf6edad3b03ab7ebc87ab527438e050d94a63a96547dee09cfd490e5e22b6bf2e3676db6b6f4841ff06dc8dd4c5aa4bd9c6c4d544b97a6bf34be28e97a31e9036cd76bca4bcff996dc4a68edd962aad024dc6ff6ce33d4a2c4ca2930233f25dec59d534d1ec7065de061f010001	\\x90992b1c55ad542f2637bf9d5cb95c64ea5801afc3a9b90b53711aef9b7be77a19a009edc802fa52cec776ff41e0837b1619cb97b2ecc56d6e5d85924290c602	1687020033000000	1687624833000000	1750696833000000	1845304833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
346	\\x1a0790db21712a3fca348b9caa95ac384cd63cbd17cd7ad458b48b3c399ee411c402a42d8f5d8d5d37cbc9119a92fec64d52eb6ad5931c5471a57f2982fc3676	1	0	\\x000000010000000000800003a85e4de27e05683343307213b4641d2d13f0da7ef991da042f1a7f234e822c527ce4a43ac5123e5bef4bae999632dbd8401dc6f8f050df2ac33fa284a1fbac0e01d9351d228ba56bedbb7001cc05a7974f34318ca31e42de6befe0cf2b6de933b542ea37cc420d4c41096eb57692c754c086b28299eb8c408d71c25c16c42267010001	\\x6c5751ca4897ee4c0dad54bac43348dc63bba10b6e1077103a9ab4c9fdc523a3b54db99d3069e33aebe4514b9afa44fb68e855a013e362f6dee405f0a1018c0c	1673721033000000	1674325833000000	1737397833000000	1832005833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x1ecf61be3b07b21f5e22fbc2d3e6feb806172445ef8cb5abf016720c0347d0b6395320cb84134d0393706e4ae5d659fdbcb82004a9e87e7cbbb8e0377fd99663	1	0	\\x000000010000000000800003deb125a293d63600592b9d8d0f2eaae3b3c5d2aa375e310b1bbb434c3fd46b75cb49ecaef2e9273d7d60fff0367c4f9e5da16debc7b7c4656a43e06f051f9e663d8b84b5958dcc4a3068fd253767902494ac8a56b16a5973aea89a3b647b3fa62ea0af216b20cd9b5e93ee3302d39b95e8c4d7ca90152f22ea53a2f0ba624ecb010001	\\xb034436d9359825a7bf889e85939e81c6ed34ca5a70dc65b4c2e4aeed063a3ea8ef3ea996b3bb27ec2a7f06346f1a366c2a0e47640548b2c920530b366fa3a0b	1668280533000000	1668885333000000	1731957333000000	1826565333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
348	\\x1f8b75c2a24c8cc3749cc4baa73d738662d03521a02c8f6127d1f5401eb045bafa2981e32d83a35e86f9fb9b9d99e114b7df2da3c5986bbe644f01cdfd322d11	1	0	\\x000000010000000000800003a88777bc3ee43255244d2c4a8edd789ad0d49a8446bb172a0989764a93d28969db7f66b06a394c318590225ada54c7f0ea0c88a7354fc9231c39b1f426083920b8bef74561689b517feb2076cb7a57c27d519d93896d80eb94f783c1ec2f344b202432c85403f4319303c0602e2e16726fcf217c952f899142bf2044172f425f010001	\\x9bbad15e14c17f95538599feac623b37e1c430e4cf55eb7333b589b9156311ce6553f6a4fbc5d7828b5f67edc9b92f0836d396686d98c0250dfea94fbfd62b02	1670094033000000	1670698833000000	1733770833000000	1828378833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x2217ecc39087100ea41eb6d85eff759877d6622a94d4b97feb5fef1dd33014d7959b8c87266fa90d5d5414c91f33bb2104e401a95731640c2c521ae7e46f3629	1	0	\\x0000000100000000008000039a475f3cd87d9dd25814e765d77d1e7affefd7d1eff25a2ca9cfb3fb07e981712b76e3a3739cd6398ddcacf97378647ae00a27afd600ea789c790e3f5f35180db7c0b6d7336ab8327032ff013e0c658152785f9d68059af6b4d25f23e85f70a1d65a10069840489cd5ae3262abc7fa9b5e97f449b591b69d8e7e03463a906f61010001	\\x981adcb4b48e88ec8eb326d68dac78baccfb7fdded1c6e0ebf9ad503da8627ecb82f06906f8b0e8dab126861219c46dd9479008032451330f6697838341b0f09	1687020033000000	1687624833000000	1750696833000000	1845304833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x25df77a7c20d8eb5387f39ab6b5922bac964bebbb05b0e28071fa1bf4ebf9f79bb2ac92a7925e051fcae5aafb83005039145420f06b1229f58053ce88a5bf774	1	0	\\x000000010000000000800003b0e3c21c7520f3369e0bef116b2a04f2d25b85dfd0af4150412ed8c109afc432dd7f8e7060c6d4ba26f5b232b5c6032381e4de81523b697c0d7bd2e2022efcba44876bfe2490c9fcb9b6832526cd9334bc4a2b70fabf8f62405b2735671bf037e5bcd22decb60a4da9cc5480a49da1bc9c2948523a58d199dd58559c60ad497d010001	\\xa5627d06721d53e13f2f61b453ff73856acdba02ccf4cfcb074cc30ee99d296fc7f14fe654162bb1eb0823a4454f1243699e0b88fb9245ee38974f78d9effb08	1672512033000000	1673116833000000	1736188833000000	1830796833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
351	\\x266bab3e8cc47758a3c4463a1af38aa483062b11d2e69a427c10552c922a3c05b50e18aa1a9519bad9795a4d4a861ffc003ec5dba2d427afedcd47b6531b43e1	1	0	\\x000000010000000000800003bfd000256daaeda7b4778de3e1c803394577f12719d5d7ae89d5eed2c165cad0e2f6c64ddb0b60ff531f2ff95e2eb6e4c0f7e0414dabdce68730f21bbbb221093a8955b2af03f6cdad9129e4bfcf69d81e049fe734862617b03c42c1285f4fdb2096e070c6b385a4537a04f62a9d61ccf3cf7f11c9967561dfccc34803f9c545010001	\\xdae94855f6e830d40a06c1eae7e2649e0296aab7a11fbe56f759cabc149cd0d0d91ae41c5e76029c4e68a1d2b710a2606e319c8c9aed731d32e1d77eef283209	1684602033000000	1685206833000000	1748278833000000	1842886833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x26ab33b5bb8e99fa2e4682ba30e715bf97e6f887fe9a318e26b8477ce18bac5ae8878465ff3b4355a46e8614e8b592e901629204e4b4b656ed71cf35d6bd0b81	1	0	\\x000000010000000000800003a2d658dd8b70524c9c4a0de9b9a61c126bbb932bf678ff212c4717ef33d2221fcc27a36445e5232d90a3f8296ca96a25b08b80b0d55186a6234ab3623159ac4bf1e8cc24c35ad945b8fdfcde1b67f721998a32228a2b183207c0e68d421e2bce605577a192a90dc377794352601133515a15f10d92c22a8ff7e5ca605ea22543010001	\\x2dfe6c5dc585d91894b2799b5adb84aa9e6f476dffc478083f0237c42656f0aace2a290d4353dd16cb75f2c21ba68bd13092d5b616250231361663dbb610af04	1673116533000000	1673721333000000	1736793333000000	1831401333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x26d391e8cd7ce810ce3fe5c349912afc7a7ba0d2f453439dfa3ad0b199b1fcd8b593015e3a55cce1b51943de7d49b6b86adfd63a4025c7fc2ce76fb171a4e81a	1	0	\\x000000010000000000800003a7082c928aec99f6ff2ab6e46a631ae4a6025fd30a3ed4ebf5403479ad0e7bb1df4fdc9f7e877ccbc960e9e49af897864ccf2e8dfd9346698afdb4d3b2c589894e944e40202e536696372afff3e06ff75ff4c2530fff70070833a698bb13f215bdb797ed9c84eefc3546b10f49401f2bf4b69e612ce698afe6930456308a7cd3010001	\\xc863803d316e889a4f6931f9fd9dec10c4df9a2116fc61289bb70765e08481dacd69b843d3387455513b0007ffd5dc897dba1ca58529a51d4136c00960e84309	1662840033000000	1663444833000000	1726516833000000	1821124833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x29c39553f7c2d8bcb4a5dbde023a5e3d01ebe85da8a516994d2e781efe53ee85c0e620e3f7809e487c84df386fddee3dead451691574124c3f6736f42fc59062	1	0	\\x000000010000000000800003e95e0f591515f25a41e7e7acc17e0a0c78b96eb850d049012e33f1ba50e0db043032370d43f556b5fc36586d358d33e8cac752f9a0bb5644da81d05b7e9a6cb0a52257b04194452c94a24d25f7396fdec9ea9522b1348c25793d31c2201ee43f901dcefb40db80a1149785cdc437472e9adc4bcafc43d048686b124e38a6efd7010001	\\xd9fa16b90eb84c1660e7ad6ba3eb6f29d65808f7b46ff2e4a168d6e4fe42275372c39fb415745356e12340f10e5acafd42002d74efdfb092cefbb5db80060e06	1660422033000000	1661026833000000	1724098833000000	1818706833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x2b6316c285f4e60cf8069fc1afc1e2f7f1b6d5c9dd23f42e13948b3b72304db060d0e507cd9c472e9e9bf4e691f60dfae02916668b24ddc1d2a7ed2c768c67e0	1	0	\\x000000010000000000800003bd1df84e43455b3152d6fa179df298ed20e78aecd269f768ef8f9efab15560146270f6c573ffffadc108a09f7ff6b21dd373b64588e44e7b529b03945d2d2c90eb78ff7e5507642c0e192807c6addb4df9cfd13435b7170525dd5d9cd39f37b7fcf260c35f6f5725829aa42fdd5fb7a60a56e244ef3c0614de12703e9c34f5db010001	\\x2fe9b22535bd6e5fc18fb0ae5c963f3ec12519325a2e5c2e27e50447e3e744fd81dcf3694b28563fd3eb17efbc64edf799796cf5f717cb8f20096154c6d6a10c	1668885033000000	1669489833000000	1732561833000000	1827169833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x31e77c9029deaaedc2ed4ffc64ca93c35115d5491b51f2824cb777c68694ee6a5b9838230fecf0dd76220b988c14229c1b314f2002361bd469f4c914eb65df3d	1	0	\\x000000010000000000800003a4419989d0a0aade54845f873f26103b07d83c217ddbd3a7c49db58bad8764d79d7df59cb1943483cf9d74a2563f25943a1c728024412784c7dc0b72a5eb005f7241dc1abc7da4c9886c00fbd18f46daef5bf4cb351b371b5e93a5b1e26913899c3b5ee1b55edb4cdf655054d1c3471354c6cd6e64bd88f464105efd145d9eef010001	\\xe4562e3918939fb9833459aab135235d5ba4245bca51e1da6132bd5d3427f1f1418f67f3100966004cde238a9aaf6003c80136b65b7fa39bfe4af1cc3ed6a90f	1668885033000000	1669489833000000	1732561833000000	1827169833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
357	\\x338fbdba0f8d04a38fc659174f977f2b5426afbc67776f6d868c80d795f97c8bd9676da8fa22d7b2c6661b2b1c88556f2cb881dba8503e08aee0104513d774b6	1	0	\\x000000010000000000800003c19bf86fda012e78edceb9662ad54bf1504a3df4762b6363d59c78442c9c1d12f0fb0dc1fcb64d9773a8736d94da029a3ac86eb2e25c0818cfa398806851d839e7f8aac5002ebd76f9da92f43fe75d9bd351df9573f45c45b43e7e26d7683dddf0fe07b5e71d68fb64ba8fbe2a00ca12d23ff09a2fdfc38e85f16fe3aa2d551d010001	\\xc273a628e8b79743ffcfa8b2f825e4f1333f3eb5f94b2279fc548e0becfd926a2553d4d42c4075084c11c168f76b433538538621c7b80389b96b9aee0faed10f	1690647033000000	1691251833000000	1754323833000000	1848931833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x364b9630d855894418a9d72c1318f5a3fe2c291da0ef8b3ff3feb18ad4b0e573829be0044188c0dc870a2eb2f99d8cc2a9fef011845609181ddc946cd9177cd7	1	0	\\x000000010000000000800003bb148174d94fd5a215607ce28df6b8fdb9a566f894f0058d9c186c0df4a641d4e2514225681b9ab39d60342b8a4e9dd3e24a699811067ce802052f76857188b6eba3accbdb36cc3fb6f654303883525e4c1ba212eed7d47596c13d9a5e2798bee73b1e9f7775146b132a4a59805fa145d2186aaf0704878531a374ba947283ff010001	\\x45c3624e9c443f6af89f43b732de2037e5ad6d7ba4a98060507cd8f55509eaa44c179562c8f7059c2742d61214bb48020820dac84840edd6e007dcdc52eb9f06	1676139033000000	1676743833000000	1739815833000000	1834423833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x3a13a1800dc5d8db62d030a1c2a8eabbb5135756281877a77088b6c3d6743691b65ddebb5bc5d3dadf0b7fd275f9214b2c95f7fbe4154bcfa4b85f768b57f272	1	0	\\x000000010000000000800003f675d8a77d4833ec74faf50cfc69790f43cc981a5caf7774ac7ce9a08b8b06fd1a75eb4bbce0e65c335742181f38ea03bbd6546cabb3c6473ddf99608c56094b9fcda4ebbd28b86178f8dafe5a21aa6631e72febe28623df452f9095e9047aa3c3cc50056bde72ce353b2ea139afbd4dbd922556dbb755802279ee572e80cb1b010001	\\x81120197d41a35c220204abc9cdf3a7884214b42fee69bc26d92c7d44df183c0c6154eb6abcf346d144d6aa94451bebadccddd863444c55a8832cbf4ecd42f07	1662840033000000	1663444833000000	1726516833000000	1821124833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x3bd3f18794c00225c9efe8d4ca76852f9e94590a9c64a28d49240c3319a0867da12f9c7ca7e512bd6fef0675d66b0ea93d27e668fedad4663958fea24ac22eb4	1	0	\\x000000010000000000800003bd80cfc958afd35c002d11676ffa8df13ca0e3301a9d35dd132268bee98aee337b64ace7e9e2b2706408a36361a5f437b372c4b64ae40c9ba5990d63dc4b505b6b6aef0a504f1e8a91f8902a991e939eb7c3c67e8e4ce131c23cbfa7c52b081262aff2a7e13bf93fcb74d2bafda0f3d27c592f24c1cf7500faf705c3533d35b9010001	\\x90167f34f7edccbf5d47a842d5977d419a262f9cfb53268095790c7189c5c41653d6b0739ab11fbfffa0d8cac6da1abfe5e0fcb76557bf57b6aa2a47e87e1f06	1667071533000000	1667676333000000	1730748333000000	1825356333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x3c07d82feae562a5dcf4e909cee58786e0c97a5849659589b178247b066475694a54ae9e2bcc0444914cc07b65ae1065a2ad50f27bc20fc6ee2b15e328a57d0f	1	0	\\x000000010000000000800003b10e16bfbb9d34490c0f9dc3b3292c8c0c21c1fef2aa33e436d1a2df211a775296123b3ff112cf9785a9964f51bcb1acf476f3b771386c7fe19d0a5537d4d32ad41a5c250ef5548fd0696643298e27cd2a462648552a068fe6a8dbff78b7d7ac13277fb9c0c4e15a612fecbc96f0c42613be10a079ed6b58507f6dc72b9f90cb010001	\\xd608bbf0d8bdbbacf53e19cb9803e83ee3ff38772685f26094acd52e2fcfe30499bcc803a95c0326dcc3325b409528ce6e3e99786eb012fafcb68c21b1bdf400	1687624533000000	1688229333000000	1751301333000000	1845909333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
362	\\x3f9b699b0784cc94a8158105667dbfd87a944907022a21aa944a09dc28497f08c67a5c358d39412c63e85f7104c055d2f76a59f0b3809d0be99e13c951088c8c	1	0	\\x000000010000000000800003bde44f89c6aee1bea775a11b94aa61f262dfcae76b564b59cee5ab2495c633a5fc54424f13a3b0989376411a4ab2ff3c0acc628acf562c2bda9fbcb2f82f672354cfcc79d5923575dce1de4f4089142c6dcefc8474d37c97410a51bdfbac785ef0d530ee089e6b59add67f918efdc9e0e02a2f387ca71556ba616bc2fdaf65d5010001	\\xa1f641459c7e837615b98717fc9057fea33ae9b40b2eb794e0f5eb76c92ca0f04b4b4dccc0a56e6557f90410f92bb978976c2889e3dfd14f8e3970aaafee7a0a	1676139033000000	1676743833000000	1739815833000000	1834423833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x4033956c0c1091fbc8475fa9cb93a553d958c65d8aebcab4dcd0b182491bcab6b163cc5e2253b9be943e90f2f47e030564464e42be7324fd49d7d622fc74c226	1	0	\\x000000010000000000800003bc133d3e88234a070c322e6e72db05667bf1a0cc62363126ada65bc4310936433ce2120e9010d18c48f8eaf897a61624e0fcd2835616599a7ae0839d07434477cec2e80c2bf09779897a4ae947c16585f6e8eaf5e465cab79adba6699715c258fcf8efa99185a7a2a37ea095244ecb5d44400aadd024d54ca2f373025791645d010001	\\xc5691edaa0c3154122ee88547e023e50e1a1d0f7590c46201940dd2e7700f7a4fe4bf990952e0c3a3db5d698f77053092a0d4290f0df7ed82b48b9b58df5570d	1678557033000000	1679161833000000	1742233833000000	1836841833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
364	\\x40e3c1e19d2b2222af457b1eb7a3759cca6de117ce9a5acc0a51244701d7854f6afc083bdcf853267a34638088e8cbe59f72acb48186b7228c7f4c4b934bfc1e	1	0	\\x000000010000000000800003db6685b2b4b95e782b59ccc4e7f5d437b876d88934824b1f7a8093850666dd88d5b592e44db0cedc0a8c2fd49eb7af48017ec8738067c0176805f95eb854a1942c663af0dcf7ab8ffc77f2ea9a6619b75d8dc1cdfcab99b9451618a32768ba8f420546b6e558c799b82f13831ab745f177f9797135a6018e587b4091ab08deab010001	\\x3427d44ac9bee0d7ab5e7ad09f888982af90fa172ae1812f857805f5537981c3383244cb3b776f44966eab494946549ed9d164bd7aadd720256ab835b770fb02	1679766033000000	1680370833000000	1743442833000000	1838050833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x421fa6f922cfe6e25f5b153e60b5d083cd18bdecf57dbfb75fd022d250f2e1c3bc45c7205c6dcd5a6f6a28f1a26e0b8c19641268dac522ba0db2979ff2b7357c	1	0	\\x000000010000000000800003d95709bc43a146bb09ebd04f3cb1cac7a15feb250632496179e17868fdf295305dd5f085c85d9198453542c8161a999f42f126103ecff15a09d7f991d54a7df537cc65130a3df71a456cfdda0846216e70c33e304b2aa54e2bdecb7fb05a24d391b68f74a926d663695d046f6188d877f697bbd7a12d08f2c5b0d65b61169c3d010001	\\x521a9ad80e9160665b4ff92ef3a12fa3e068362ce0026bd1926ac0fd78895c6ee83a974cbb0a705b7e1e5f37b1f38e3aa8973aeac0698f4d2d7b787c1212dd0e	1674930033000000	1675534833000000	1738606833000000	1833214833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x439396498ec7c84946c3882a3d678757a5b33464bb706ff7cd815ce689b97c3ab3130f6bcb9acf2b9ada9a0fd69e627b446f2c3ec0c3e33682b9a44c866317de	1	0	\\x000000010000000000800003f116f492f95fd97ed4979be43d8008affc2bc80b00930dc7e9bc1e8e633f4e4127d27ba0cf4464b1afc6b651de66d669b6395d7c1ac5dc6b5f09ae2eb7eb7ab779fc2be162e9754814a5010dbe7f167e92f3ed561d825b6469f8876add99bf203873fa0aaf52d44f9ebe437b9a6f0cbd6609fc03378e282c8589f540ad2925d1010001	\\xea2a84efeb17ed165116fc38ef4602fe11a48fbfdf3af9a63a9f9b81abd342e07a201653ed96dab79a34d64637fc55f0e3bf80a373b90a7990193aeb49af2105	1663444533000000	1664049333000000	1727121333000000	1821729333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
367	\\x444b29ebd22f28b959fdabc5b5947973a103c09c50ae7b3c055ee8542be2616e3b16a39bd427a8090070d86b05957da314507789f05651ec301db76a0e675965	1	0	\\x000000010000000000800003ca97a0a2085e67079b083298725b4adc5cbdb8f6167eebc7ca9a8c167d491cbf6b7a8f9637894ef3fb4efddb89e75a652d6e5626ac262b336c7956facfdd42d0ef48e1f89b0c116af878fd646e46f760bdc2895d1b8a58f4ea7f3a2c4f74412998b5af66fb05b51342ce061e67d2de6641b280084dbf1c5c781fcdb8fd7ae3fd010001	\\xb7644104842af877def9df9db6eeb2ec8a365ec012a68ca0c3055ffbc6cc4f447f990bfc153aa5ed121d5d49769feec0280ad818c474b7669087e064c5ce6d07	1667071533000000	1667676333000000	1730748333000000	1825356333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
368	\\x4567979d49a1da482f110689a6d211f26b7dc0c14a66ff62a67ddeb7b35d5819264c3c0bbe6b1fa9224c9e4889c3ef32e30b3416e5337356852975229de9badf	1	0	\\x000000010000000000800003c2deea0ff90eaba134c2623fc2ecab7c9086fa08ae0e0be1f1d2c93a0a08d5d7fc3a7a9709d91c12d0bcc913d620a0021eadaefc6b7c7783e0dbd7f8de2040ef42b9c2a4d27d4e70f9e6627c6a1788f82c13eb048656e81603643dcb0d136d6f6df2688dae9a43542a1808bc74c49a5a2c58be05cd4cb0b2572a4f5c9fb2cedd010001	\\xc2ae64012e71377b7f934196984844ee5a6f3e02ae6e0fa138756c9e5ce6b3d6ef9f96eeb4e3e34f9dc0d1dcb331dd6903b930e20c5008c346a67eaad9139f0e	1687624533000000	1688229333000000	1751301333000000	1845909333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x486fbf917942fa5e11809203c9af237e30bb0e82dae85c5897f9378a8f51b82d85b7c594334f5ab3763af6b1bc98b4e5d13d62da23a5014905c14f6128f9ccdd	1	0	\\x000000010000000000800003d527978991423e51405b0b216759d8522480d65c4a148733654ffc8862e5b1c3806de512a6964f70e6ece9455d98f0dcaa4b7227279465c8957906efa59e3bc2870284d20b4c86fb98111f7a4b4875df4ec22ee9f729919d6adfc37812904b6115bc7fdb372913e83db5dc07558f7c1ed19e5949e55d0acae6a0623d77813ef3010001	\\x15a246f70f01c76e129c9259f54a4edc7bfe9293518b1d69062bcd80ede6d77a44d8f3aaefbfd6dcb6afa57afd592c9862378804d25e7caf9c620fc2394bbc06	1687020033000000	1687624833000000	1750696833000000	1845304833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
370	\\x4cfb8b253f421c37ba4af0d9a13b54d9576c85e3b82ab790b8913fd9dce1952891bb6413aa0a151d80418cea0ff277d0f0d968ab7f169a04a66f88b80add17c1	1	0	\\x000000010000000000800003e4cfad206dfb2012067ffd4270ce96fd71c435d6680c011fba3dd3be45fa3965edf2720db61b5953c5b782782e8e9d2b68654da9d7bef5a2319228ecb276b7f4f096cc97651971a351e501984a49f0f29588e854f41482a21a38fd83b52ce2f5f23efe38cda7a20ff696909576f65abdca9b6582158e258917a675b81e2d203b010001	\\x03976183ed5b013ed82ea054748055be933d637ad1f551727ab262157f81e1992107081f54a6fdcdb946e58b90fa86866847a87a44b542584ed8778e13230a06	1683997533000000	1684602333000000	1747674333000000	1842282333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
371	\\x51b3a28c4acd282513745b2c4beb23b34338d38e634c0e94ceb7d7e19efe676ee69c1f8d15a6e777ec98079a2039f06b12fa56ae68dd902b38710b9958444c66	1	0	\\x000000010000000000800003d12831ff6d7f61dd781204c309c2b6a72ce3beb804a1fb13b5f3d2365601c134d6160e4b00a99bdc967d4c32fc4c76db62477c61ffc2e90cfdfec1c51f4fd3fa8977578b76da820b83b4af9e614e36c02addf8eff0d413f74d59a377a585724b0d0391dc1c0c943a403cabc10b375e88140ed4d13544073d5a539a08391d9491010001	\\xf3be9e3d9b4e893f2f2416abc4d050e1daeed51156d77c8ab9554cc38a732632ccd9ecb917b3ced096769db9cc49f7163eb4066dc685ae90a8d5af4f214bed0b	1676139033000000	1676743833000000	1739815833000000	1834423833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
372	\\x51e3e291542ecd4f8bb209bbe45e4728b3415c47922ca6f5b90003339f3001afb9eae79839cf0e6f0c7ffb385a1f34c6c36777e1c9056a9d55b7efe9c2c1231e	1	0	\\x0000000100000000008000039f65ded31c7f181ea482cf6d590e86364c29b66585ec3f2fddf05180cb6c4a8988f5c4ae46c24f0291256f5ca59aa64be6057e7e44cd5ba535e56812603e55394e6c93ca59de2c6b8dc0edbec61041e651e892f65dc7c74cd3a704c8b9fa4f625edbb0627b10277542baf72d72b971dc689d8b55579bd2949ac3d98be2401043010001	\\x0a6bfdbd267c8cba3f4ee7c7042e9242bb6782bf4de51506b7c8c7621f780edd5e2fe1399533fe56ce3466eb7d50dcfb56af8fcfd38215a5a9a7e4f7ef7e9f07	1672512033000000	1673116833000000	1736188833000000	1830796833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x557f17a63427d4c036bf58e82857378e508a4f96d7a67eaeb70e58cc5f1c34f04a0a5ffd4569509ad561693ee5932138f17d27a17fb124648193431a17f0ef49	1	0	\\x000000010000000000800003b4d89cfad1c356007d7ce7d2597dcd56465d5b03e67f00f9fa8739d1b0b9a5f48809e48bce06be7ce9e7820d13e9c83ca795ca3ea912943bf690467b3a5c50717b07e1e5719057da2ff3dcc4a619d53b6413e99bcc1ee9698bc09547ef647b5852a23f3aeddfdeefc625b3737ddef628502b7f9dd48499d99dca5a66dc81e36d010001	\\x4afd8b6de0b905dade7363b1978c6323fb34af188bfb25fac9ad1708848645dcf9c9a5b0231278760524cb4d99377c2125e120b0e7cee8f44e4179f065f6290c	1689438033000000	1690042833000000	1753114833000000	1847722833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x550f2ed2ab0150ccc516b0916f5659da8977b4481dde5ee60bf89c8852e4c9897485550e7a274237451108d29adac9baf86203fd9d799f4dd4126dc401e889ec	1	0	\\x000000010000000000800003ab5ea5fdbc9d8ca096bb364f3ed82c2f543d392436d48d940c3c2ca03ecb759304c85cc37d71344e8742e381437da939006212cb472070e5c814456ed88d6ce7228c79c47c6d190e972e2c894eee6714013322b54adb22633c0cb461af1cc9aab18e472c6ffe7d73055680003e399858a3d42a0bc9e5c0d427de82ecc1fda8cd010001	\\xeb9f88a583b6d53648626c304446fada11ae2ba3b94adcd1d3bde55b07657b109b815eb29149f308d43e85dcd6b0fd41bf4d422f865858eca60335f8ef676207	1677348033000000	1677952833000000	1741024833000000	1835632833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x58bf914e649efe1881bb2f6eadddd2676c37f7849340dcff192d0d412c43abc4a825f9b2bf3a6fef7dbf0f5ff9fc1ec300645eced57fcfb152c8215aa639af29	1	0	\\x000000010000000000800003a195dfe9ce9528cbd5f2903f45376d0e701a2288cc3904524c7e05d3b4795e070f1224457445d4f5256882ffc0d088ae35c65f6d2bc5a4b8bb5f688fb50f63172f3d540ec2dd3d7112313ea093dc4520c198c79625127abb5fad4095bd9c322e7ef631df78e013e5c7b1ae0d96c174312bb9796876b5124382238c52c5c219d3010001	\\xea69581ea512313e057a0c8062f556725b96ed4089726ae3d3c0f12b4e97dd1aa493b26d7ddac0cc5aeb0066baa86601ef9a3958bdc2a769279738c456d8c70d	1690042533000000	1690647333000000	1753719333000000	1848327333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x58f34c466fb188c4450117014d36cd7ad03e2de5cbfbcaa58471b4f39ee9964800b41c6d3cfb0e9a8a05a7b1a8414e51a7f54920ec1ebed17eebbcd969d0479f	1	0	\\x000000010000000000800003cdf3de9efc2c97747422fb628fb227259a81f287e2a20daa3aa25641b6dabac10c2dd3fe73e0e947aa84168ac810c7a4b0329ac92f9bbf07295a34c7062a41c59f46469095818d6ffa62f3a969c0f274c4af25668b56f93d7ba6e63d8881d04dfe260fcfb49b6fd56dc75e8688513cea5d047397677cb2bd1ff9a72c7364cf33010001	\\x76cb4849309bc57a649e270404719dc562ddc5054e8ea3f9f9ffde585baa1599ac9fb8d5d4e9da4701937b31a243b438683cff75c00b3e789ef9b91b17d0240c	1673116533000000	1673721333000000	1736793333000000	1831401333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x5c2363a104f36f008e32f6b9e363714681d74f439650107130d33fe531e4d9a3fc62c4ad493badab0bc94be65f4eceabca2d23299ffea9a3c39e77d4a88e14af	1	0	\\x000000010000000000800003b86930572e9f39319715fbe14cea2cb530a6041f9467b85cf2fb23ae5313312b0968995a92e867e72d25a6917731dabe0549f7548f78c3184d68d2678fff5f44aa4bcf208ac052bbdbb71960315753c3db79cf7c0d9b235239c701610fb7196948616eaabaa2a2c1d13518a32fab6b8026406b2fdee4588106d2a14e9208c18d010001	\\x8f06c1d803db834f24ed6949fb5fd0e7ba47dcc9eb4939439c99210860e10e8ba0738e4c905413ca8731cc79c43b9611dd0ac82f3a1c8a374194234818153d0a	1685206533000000	1685811333000000	1748883333000000	1843491333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x5f8b5e6cdd72fa3db095d7213255c44b0a2dce21d774bd93129b766ecce5c691be65b32b1adb103fcb84c8ff67602350b73dd63ba451b2d10de27011af4662e7	1	0	\\x000000010000000000800003a1aff8abc51eb2cc2341e47a369ee552eaf91e5e571e7824c170eab406e46662e1d2b09bf401ab5f286717801b9126f3f4d907e8de7513083e72db26db50368a27ec3e758a86672bd8737525d523f735742bbde8e1c798a0cd1ae751db150c0cc7f41f4da842cc31153e803f99bdce23ad6a898e555fe5f81c9688eac7db0ba5010001	\\xa98d1922f7da38b197f90c0b794193c1a737011510d824c08417c1344b4ec1e96289cab004854cba230c75e618b46bb868ebc038f1a7aa2cd108791d92191f0c	1683393033000000	1683997833000000	1747069833000000	1841677833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x6283e1b2bc81ffd9c427ee2c5f9cb41011fb66f465c8cfdd5d8414d95daf27601034ef7f3faff010db8b39ccd48f2f517fa2493b1362d7089c5b16c8dc3e982d	1	0	\\x000000010000000000800003d6c36239a040765ea191f9d7d520c1d70a9afcbfd280c37cad245b93e156aca7ad1e7072ee57a01137845a8bfee1bd5c17547a9f4f1e63965eb178e19e3d1741a1f09b8ecb128d91d412a0444da547e600b33e4ef73104ba0bc1fcd3340ef88f8752e0a309f1680a510f49d3af72999ad25b99b5888f3601b7b4e1b264005f2b010001	\\xcbf22e7767215d354aa03157311d1ec72b777d9224ca28677f2bdf9648d5f2b241a2c1cf0ee0d7fe1ed8c0d137ba5d40d00bb96064d12dcd9d0df4772aca8e0d	1688229033000000	1688833833000000	1751905833000000	1846513833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\x64c78a2eac05a556dd2d76cfa018d29361d86eeb953053cfadc8e9c915f3c2be8fbf33e1a1583d13c60cc6d5be20b4df2e39409d2f3c3bfc33f2157c1702244f	1	0	\\x000000010000000000800003ca3a489385bbeba8c350337d8decd0b8bfaab08030cf3e7eda0f1b66b2c7c703d22d16fe026e92bcdd633f17b0c939cd4c8dc6eb06ef657b601d969984f35fd96c710979551dd4dfd28586454eefbfdef3495b4d4e3fb57d0b62f5a4c455aa8e4321d60d37a52778ebee0c1577455ede0b95980a367fc7a31b76cd90e8fcf26b010001	\\x4df0c34227f716e20e6349d3f8e15d8003367b9786bf783a165a03715a566dfe8d5aa660871ecc8d4873f2f4693ba2e42b5abc8c1745a2e61686d1926ee22304	1670698533000000	1671303333000000	1734375333000000	1828983333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
381	\\x69a3523df795da7ca1609722ee2282c9f2bb422e3288ed271a237fdce37ed94c5d86732007ec250c0483b2f33efa4f4c0bc61836ad0d26872e68d0d61141e920	1	0	\\x000000010000000000800003bc8e9d0d358c7d7d7c2bc7bfac571d7dbe736a73f9d48d5ea57e799292024d16cc8144dde39ffa9bc98699040d23598d05fa383b4c50876c33270bc37fad2ef36d80358f74f55ebc50bd06561e48852f7c75b3b31dc0615513b10269820cf34c44376677ad96addd6c1d629b40be42e9d831a1a764d0c521104f63c131b3c8ab010001	\\xac6429549e1c5ef6e37b39c2e0cbf0f51abc4083b15452aa62a15179ec916ee14006e835678021ed84d4271608790bdca1c01ba4775e44fa8412226673f2ff0f	1679161533000000	1679766333000000	1742838333000000	1837446333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\x6d7764e63938c1766f7883d2541b4318d831b27beff9a0cffd6334197532ebeccee962726355160b540cfbf71ef6bad180f985f714810c22dbb496b5c0de04bc	1	0	\\x000000010000000000800003f978ede4c20e5305d0dc4b42398ac349e92db24e0c4c48bb00e60c2fc0f515830d862ebc95383947246b355f3fd14861323bcb2593260f5f2f807ea96f8aa560a69c22ecf766de9769d74f715c8f817c7743586898fe00581257fb3167a02c16ba641a72bf3a3023c4a350a7d61445023436851545add5c9b3121b11da363b99010001	\\x2048a51da87556d9fe9a0211e4341d8b5f33ca29b3e3e968efd0ebf559ac76b304dc7d90ab6fba30d4b3f6af971b57b7c10585fc7f01a25e42f0f7ce3cb2d105	1670094033000000	1670698833000000	1733770833000000	1828378833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\x70273553b02126f9c37a79669e8aa9388c827b681265a7eb0cc31e276d99834bdc794ce2ada6458d455a719eb779892a86175c4791ade8a1666e1ca6f5aed12e	1	0	\\x000000010000000000800003ef51828d7596fd1706ecbbb32c03ec62bd7cba9fa0647d37989eee4c6ed028aa48454d8ec58e48dd5b8cc8fe497cf94432dba46bd55dd2888a752ca7942cfc9f14a7187d2c77019c180401bb94e370ee66d2b254e598aa7d903d93812961b70727cfba6c11cfe44707899e3cc6472a1f6645c0bcbec0a83cb8586afce350354b010001	\\xb35e05a94a8808585e1fef91ab2553e0237054b897022e8f83bbfa8e93be8f6fdc1d0e022ef7a61db6106b0ba20944b5232a392eb4dd82e76c9e3eb232ba4803	1676743533000000	1677348333000000	1740420333000000	1835028333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\x7173e147a494d75cc552ed42fdec4376f87dfbe91a49d0d459ba0a0fecbcce29151a3af607b66277869e7af659013b2f984be0495d420f9a112b8c9389bcebac	1	0	\\x000000010000000000800003d4c4e0b427fdefa473efaae7aa034544136a3baace180be405cdd51189a74ddeb69ed9d10b9bdea2b485c5ee4fd15059584016dbfa42426514a77ed5e06a77746939021603c34e16ba5b39b97b23f4abd90a6c3348bc3c4014eb000c7d7a2eb4831dd9f198f23c1f32fc9f85566e66f84c086f586f6fa1fe64981b3bc6b886cd010001	\\x5a3fa61cb02a49d99e135a6188e0a8baf8a4ed5a51084af0e19ea8c1d13a74baa51bd6b6487b12e583a0f999b2c6fbc20e3047b231c9fff5dc1db5c0601cc501	1662235533000000	1662840333000000	1725912333000000	1820520333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x724b7a77953777d94c64a405587d852678974c9886afc4b1ee97a3f9e9a5bc9ca418004869181188405ba469ae494caae6daff900f0295dabc497dea3b58b3c4	1	0	\\x000000010000000000800003a83351f16dfc903443a7cb9ab171eba3c8042cd60b69cfca4c29406b935886721a82317e6a1785567eff7c819f4e27d02a032c57c5bfc626e223602f48a6b8f954ed07d123465b55f21d4b6bd446e39d8fe84494d668c945068d62d2ff26a65ca9d48af6b0928df3f2c2ed24d0623c364ec8b093bfcc46599cad72ce23524891010001	\\x57ec3aca484f68735e7aa2e24a3b3129b599a3830c23cb55ae526dc317704a2f707d0c39d08365445a95062de8bc249aa11d8dbdac7614d810422086521d8205	1674325533000000	1674930333000000	1738002333000000	1832610333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\x75b366290c54eb3dd10c693aca542565371d15481336d79048f241449584c7fabc677d5fbea2628365217921c2546a2a136725f425164d55cc41a2254526a728	1	0	\\x000000010000000000800003b780a0bb162c3471b3ce3608573109a7b7980af4e1915ef4b0d34f6906aa96720bb2cc22921ee1a8d08876449dc479e6a9652be03440788e5fb2dec0ad3ba4205a9bb83b4014cf4a501b624a822b2e72712b8fb0a8f0381b9ffc45369bae2c353a667bc2127d51f5731bb5c46feed1c457eefa87c33de53fb49ad43b1884c65f010001	\\x8fa88f9da78bb28fbf54e05a158b14a378d24c8e8de64cf73eaf1d90fd5506a9c8bd2011a0411d8b197e2c8afe1cf3c6e84ca509fe30cadb66c93a6ebb212604	1669489533000000	1670094333000000	1733166333000000	1827774333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x77bf3b5eb3d24938b139869b8701751d8ed360f30b0a1805c16dd7ce053876818726fa3c56a14ecb18a3565eb2ad99925fe43c7d5a21fac6a42aac20daa23df9	1	0	\\x000000010000000000800003de4ac4e093eb6ec4b32ad372883c01f0dde973e4ea0de10f846eb1e267cc4e360c4c2b55ea7955402c2cf04dd94647ced01f187e29af1f80547115bf4620b554138e004549b6e38d00fa4fe4155a4ce388de073bb8b13ba0dc1beaa6c80c1130ac4000d958f909bf644f5b6f5fd11e7bd1a8fcaa5d8dd95cb6caf51fdcbc414b010001	\\xe0ffaaeb7ba5981ce8744557cf957d5e76719bf704b6afe85190b0dd7e8f32b8fc13f496c00f172a6edc500780571b193fd1814a42f2c5b60926e344f4bdd200	1689438033000000	1690042833000000	1753114833000000	1847722833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x796bc171be05f00e53785642d05537cdf8d9b9b79c871a8ff9526e91aef93258d08b102737ea0955151f1c25f868cf8ff0096af9732f7452417a3c89b69673a1	1	0	\\x000000010000000000800003ca4587dee2529a527eff11309ddc4d8af95b5bfb9b5ea8f285bac33d5b17d48a9fab816ae66a3b2b3a5915c496ed7dd107693dd2bd04af5acffaf4e1bee7bc0e56deba8e821b8d2e5eedb0332ee2d9c00d1d43bf41b466a4e4db4887b3bd574b71fdbfcb9aeb9f2b2e13314d74179038edefedde966fc07d69421116e934b66f010001	\\x14f10235520fe99d328355071f4241d47e3dba343dcb4118d9fe06c18095f97dcd554e925c0bef5c53ac16738959e22d68546adae5e94bec6bb2c82275e36706	1675534533000000	1676139333000000	1739211333000000	1833819333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
389	\\x7c574d148bfd04ea838b49551fa0990cd24ecc848c6ca071e312bdba3dfbaadc663e240fb76eac3ced639676faeb7941502fb98b7afd0de74b2074d10a26a9bb	1	0	\\x000000010000000000800003bf9dd89ee08a8a0e4e0f05416b32c2f1a059f11e211730a3de1511f42b18f73ff4ddcba8cc4cb517e449c316ada4d4a29941bae461fa630758da1883feb9a2488235b2e45e19e90ce1bdf64a9cfb254840d528d677d1591b1434cab1c06499d547e367dc94cb791c21640232cae21d755dcc7f18942cb47d57af43407f4c49d1010001	\\x0440ec3d4cabe9564b04b9d7e282f63d3de0e1a99b7bb53082b58fd824be7d3dcf08e79bd7e66ba5fbb1a1a8a90d071a439fbb0f99aadb2036c1114427169c01	1684602033000000	1685206833000000	1748278833000000	1842886833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
390	\\x83ebbfa022c3a29c7af70f0dcc2632271a98bed541fbe32fef2734f937418e7204accb86fa43cf7af08b7f423552825ed54ae69db97c786c0e9afd22ca03186a	1	0	\\x000000010000000000800003d2c2bbc2a0b01363d4973412910fbae2399dda48afa4702b744a0b74362e840edac881ad9d57c6fc7465e4a1433885b52f35653497f132bcdf69e8fe04e85333ed83a1d0d76db2a18356d503f71751ba2a33d46f51ac8a8bf1f0ae6615881b1b490837fa2e6de57040db53f975591a3a5f323412710a61d521acc41b17107989010001	\\x8ca180942ba4c27ce88db18f35d0d2de846634bd5d3a2b3ea22133648fc1da70faefb92ca53f4ba941cb78861d677e9b8eb01e515be7ed29e7e96519b8885501	1661631033000000	1662235833000000	1725307833000000	1819915833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
391	\\x879fbbeb563549eba2a257464a15ca7baac62198ca1c83d26ac234539de14a1c6d8dfd2a1b6820520a42cb9e877614d77ac891a4cb8caa68a08989df0fc78918	1	0	\\x000000010000000000800003d4d64fdcd321ae4361aa1446a2f383ef5cb02d6aef5a28111e82d9da81c53b0c775a06c60f56f334ed6ab3a884930e4cc70f4dfdcf5175e8f0d328f8ae4c53538ab880b8c97d2e526060430e22af87deeeafc65d7ea4313ec26a75a9b408f94efefba7f9aaf7c4bc8b31f196469bbbf9175a0139f21c48970b942a3f0e1cb9c1010001	\\xf5a1112b4abea1a1e9e583a00d682b9601ec256ae29b3fc80bbf17effd5088280a68e34e5473d6d11aa5df1bf9cbb448f90072da5452def5ffac3777d316ec02	1684602033000000	1685206833000000	1748278833000000	1842886833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
392	\\x8783dbbeb606103e550fd960838b3ed1135c94e7f026f08559cef0dd988a8db3bf9d617e8221bea2dcb978df925abbd9591ba09d9b30269ed4d908247d359142	1	0	\\x000000010000000000800003b092f35ffb845ed7589a8973813f27715416361a5d99c70a07de26e6211228b113e992422e40393c4733aeb39eace09e8b46b7b2d836ca37c57c2cbced6a479435d4ab9a738b3484f8bc2cad8624ac6d0357f77ea93a5019e679821fde8b2846c25e75cd8e2713f99d489438662065772de2b1c21f4eb3cc4b164d7177dde3df010001	\\x817d78c88125b7084f624a547cc8dd2b636051528d0abd6ae7fa2d25948fb9785faedc814c6638c6482fb0e2ed9d76cc6502c59b41d3761b70684822cb1a7d05	1665862533000000	1666467333000000	1729539333000000	1824147333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\x8bdf6f40904ec0c9797f16eacd2fc4c34fc0135ead592522ccdbcefba71a69f6c84ff3eca6776ab1b5ee663c2c3683320c1e9d5fa97692d601cfc3488f7cae16	1	0	\\x000000010000000000800003a525ab9fd1eb1fe75e98c02e62283264494a7fb1ffa01a18f5d159427e4296ea2b166521aea78d15dabe7feaa7d5b8eddc1dfc48bce10a96b7bd7710fd12d5034acd9775eb6cea87d2b2f97f46e0a0a0cc929d7f0f170e57f5ba16d1a3709800c0490b7aac148de409c427bb6acf6fd6a9b373a2613dbf4de2e3174630208ccf010001	\\x827545427fc8e9b201df76cefd4aca501ea6d03a56d73fb7cf67083b9a5f91233c0d226dcaf8d98515afc6abf1a2cb2112e88c64df53360f76cdf7c837e60e0d	1688833533000000	1689438333000000	1752510333000000	1847118333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\x8cbffc8747739df0a726ceb18763ed42453dbc45b3dd66b7b98fd2cb7ee3743c0d4b5ab3748e4f3653e20d5d6f8b264f7fcae6c5891a36b5492e4f6a6a2d3663	1	0	\\x000000010000000000800003a12f68131f4b2a888427ae35b17906a7c121754d19cb2b2933a01e813713d7f340415264819c06f72d68304b54bd8187e5f54a55f8d036504c0a499514e202ce1471d8c875a5446e1eaf01ac193bf3ea00eb16bec2127b52271e3c366f1bd4985c458b7589dcde3dbdfa57407dfb8c82f91f1c9de8570e47398c52e7f2f6980b010001	\\x5703213ea94adf967064e36631807b205cf0e0b4aa28be2dda9492c931f4710bf31f016e9926e6c46ace2806d32c75e6907835409cfefb79f4c13e3135660305	1683997533000000	1684602333000000	1747674333000000	1842282333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\x8c37ecbbb39d892f6669faf62ad0e6c798a69b21fc86089992d14f55d00b8f8a7ea55f1db87f0f0855b51b3990fdf48ac012ec98692ee823b16dd4cd9668a340	1	0	\\x000000010000000000800003bd1961ee7463ba81223ab955f985e32905c12136df4a8ebee012d05974161fe3a4c8e3ce6a52e421cc9bed4645c39b606852af8824b4104727f2b3d0152134045df5eda4faba0e256376369e82182129a637cef8da24453097e985220f29148af3c7b7a4b34a2451b2f075335187ced99a4e0debce1a47207a489fa7267df3d5010001	\\x378eabb25895930cb8007a75668a58d27925377a59411b864abf4d026eec85abe53fc523c2370988e97e805c0d0965b1cc0e863ac65efc9db778bcfc02cc5f07	1673721033000000	1674325833000000	1737397833000000	1832005833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\x8fe74e6ba40cbc0e86c97c5416b63d310904fab84aa4a3043e5f2130850230869417f10d959bcb2e129a014dbb5f3aae690d3b2a5f20146e4826e8a75672fde9	1	0	\\x000000010000000000800003cc962c3ed3893b34038c7e7b29c1cc0618d33b00085eade2ccb4cb159620b1e40be2f69f4dc9a1146ab6862542566ba0b862c5bed930b2d48960399ab29a2983bc4fd7a956aae2417ed02360b242eac879c11ac303548c139039c46d2f56a655c7a3325ff5c7aa26615fd29946f0371daea82c3e6f9d4eb94334e0c7c15056ad010001	\\xa9023573d7d93d683c947c8c70735cd90cc0783de3ecf9cf73f97ec9d81665730f440de2bfc0a817b3445d5a5cf01cea5ce0f047651e3abded4e403d01618d07	1680975033000000	1681579833000000	1744651833000000	1839259833000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\x915bc4425303fbd99a1ad4f0ac2aee78f8d4f07229e671f4c7823088a240b0c6181dbc2dab30b5078cc66dbd007eea143c63ef6a3aa6d027a1582f31f7ae9958	1	0	\\x000000010000000000800003c8e56fdf770fccbd1394780327fcf11f9be7d4cb6b7a34f5b87c3f8e0a71e909e7f094e3d7b7a0724c0c43c18c22b486fd1e46ee67534e46bbd53de6045bd4c727d4666f0f5343a47300f04286c74b7155b6d343a11f39597f6bb0c23079037ad78439401fb6513883dff6451e8c622acb7c7f8020caef8ffb3d07b8efd96763010001	\\x90d79a86439545ad244cfb842f45485387c0f7b1f41bb9887ed1dfb5c09ac7bbb5de7b9d33b0a491f4018224ecae6859a29a807ace6216f2ebb703160a7ba407	1690042533000000	1690647333000000	1753719333000000	1848327333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\x9a5b5f6e932519a7c737cf01eb43915811fcff63a24424d0d3062bca45133d46de7901d5afdeda892cac19c114b699327afff0b89c0b184004caed10eba59905	1	0	\\x000000010000000000800003998fc20fd8ee6dc48cef495cc6132baa7149e9e10882d91e02f7aa19c2da84189684d44dcdd8237e630ae635295c1d530e6a7ff718efc5bd852dd604b2126f705aa09b7e67a778cc17ddf2d2e28a493e4ba287a37ec4fde413a85ff07b059875baaf33743e17fcb87f1ed6829904316470df0b4d5183c73820d3e8d041e060d1010001	\\xa547f2f58d3e34d63f0f762f6d3b516252c7ac3cf4a401bf54e34390962b3880883cc9bb40101dc73082fee27659d7d99e62bc77f406cdcda1b5e1de8b377b07	1669489533000000	1670094333000000	1733166333000000	1827774333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\x9debc525999545dad31fd9c70b00c2838b9f57d35360c0426f7e20a1e4a59f214a45561ec27ba9942d297e35110b93aa76e1f51e9412792c0880e53bae5ad079	1	0	\\x000000010000000000800003c889a593b9cce4ecfbf68421964635afd80d89cc84493a7e1415dc6af9462e0488fab2218e77fcb3744047ddba80b11eb3462e05ca433b5f5ce35cf997b03f9c337c2521f2c7c0f31a210440ed19f8fd532e3ca0fbacfd87f1dc8a7642ff95cd8a0224c12f61ebecf85441dc2ac64c537868d0dd9b32a263d1d47f6fb9a1aa93010001	\\xb3bdeb64b273c0dfadf59971bd38162c9e2e4f54e7a66f6d8f10ee4a78aa28290c299e2b134232cd3912a6c2bc6fe895bb577df9116c4e4e8784684b5ba5f80d	1674325533000000	1674930333000000	1738002333000000	1832610333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\x9e1fed523fd36ee0ccd8a71383701376e71380c39027c012be84caa6e0481f5c55324ce2f4e43ebbe9125f00b3a8e64dd2b75b075c97f9630ab45d3a2e3d7b70	1	0	\\x000000010000000000800003b55bb0d53e983a5a88add60a32556854a2943728607c8032fff15a70733e21bba60f2a60493761405a091906cc707d66039d0b5f5c1f86260a81d99e576054a50ef3ded4b36662b5701b01b62720aae910e54e3871ec90e41a307fb3545b41839a2a5475129c9be414ae1e7d69af1e554592179367ff3b62eae42dc370751cfd010001	\\xfee090e274b1f080f457a7d24150076dc26c86234706328e8614835d12f215cb35227eb63a7a740f0e9758276b62db10fbbd10f68a693bbdcd312af5f4866a08	1672512033000000	1673116833000000	1736188833000000	1830796833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xa1abc698fed674445bf5120423f326a58c1fa123ac9578080f03a2475d2d9544f27e27e1af12f3d4ea9b4618b639381ce5ec143b5893a00b3683fc3789cadbc7	1	0	\\x0000000100000000008000039707fbd1acb76ad1de7ec170b255a57b494bb23080ee55d5b89fea1fc56007ce2cf9f16a7eba2fee9ad71b7ff092d43b1a64abdf9355e379e5dea4d62740457e78a0ebf2c8e9c3a2941509a86bb5135cad6ef1fed1ce4f6feb30ae3d61d9f1dd9989091a5eecf506b589ea1d953e3089c73978285648f8f2285ff29b0b1b0e21010001	\\x26ff6440a6031c939b2432413f0589afef0148e0458b547ee889ea4f4894f4b48061779088a32d4223f88e072eb7b900a0ced9a3396343f83c45418699b72e09	1668885033000000	1669489833000000	1732561833000000	1827169833000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
402	\\xa1a7abf4974d13520e7c47b261d6e9a722886f5ccbf9ed534072da1acfc40c8fc315c83b6ca338753a4f394957ef0fa440a3f2764e12eee65b70b1cf775b5102	1	0	\\x000000010000000000800003ec7b1aa3e9995c715713a5b0ae35e493a0c6c8300e7b4ed5acbf4ea3e1c9292462ef537109109e2143f50ad58f1f3b13ef075ff56134635e0e01fea4ac9880c177b9121892e23531b2291753ba108e8bf7dbdf5a5decd0c58a68dce1e1427a4b43e5704bb8feadf6a841a1a1511121a9d68d4c3de67657a3a95a6024ec03acef010001	\\x85aaea7ad3975ca844aa30ca34981f5bf23631cef024c2bb6ee156b78d3dca110a61fd46bc62cef6e1d3dac94f432f0e430cbf9a1e50825f532f3c086f087302	1661631033000000	1662235833000000	1725307833000000	1819915833000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xa3cbe60a53667dac7bc2e3efa3d7ef72ab3c6dfd99c8bab5ed1471cafd35c62f0cda47f070a696c7ec63d9fc545ef1d5eabeec8f82d42d66fdd03bc4e7c95806	1	0	\\x000000010000000000800003bab01a1c1a3392e3c4bdbb11cdd4428d736663b0c48767a193ccae737c4d8e7f30914a4d6f020bdecb4e650436b7b9ff2c963b433e9a61ea51bf265544bb962648d38706aa89c06e9c18689d5ff9cc1bf64f17c310e3b97fe2ed49fd451403f1dd63f5bcf4e5f4c926edf084d20bbc7172bf30795234f6ae35dc29daf19bf9f9010001	\\x408dc36217d2540ce5468c4109d92b08bad29d1f0451985821a68e9d25fcd9b494fe47450b3dcf0def8def31805c3d0343550de48bd841c4c72b73f2276ba708	1660422033000000	1661026833000000	1724098833000000	1818706833000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
404	\\xa46bb3d8cb44cf0f2955a1e30519ddcf7b405c1758fc91f695f0ab4a0c4ba50d47dc6fd1df74dcb1af66e30cb5f3e8fbd6d3e57537c45231e5d01364beddabdf	1	0	\\x000000010000000000800003bad815f54fd0c4ba0e43d710517024c1ffa27022c03a4eeb2336f1df545619ff69d5ae1e721a441619104120af6431037e35ca97dc72605666372fe5d3f5c8d04bc3eb3db56101a48946be5bd763f1bc61e54b154dc6fc5cd0f60a3ae7e12e8a5c5eab313cda79dbb75d5064e4d9a8ad0252b4eb54604a92c4eb3cd935cad173010001	\\xa2faefe2da732c492d2a964612fe67e678ef9e9e4381055f48faca55f5343886d39ec25f7166a089232491f1739ee751b2bd2f97a01d6151368993295d6d840c	1666467033000000	1667071833000000	1730143833000000	1824751833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xac9b07bfd05ed7b5ef1296bad2e4ae6dc4e9cf4baf108af1f29628a9f04587df4018fcc155a12f5dfc0422b425186e9b8fd941ff6a9a1eea00c8da75ee2265bf	1	0	\\x000000010000000000800003f7e6d0b534a771543f10e435efd627072baf78eb46eff446bf19f598f935be6d2d2d9dbf618014301fce1f5e5c6da658749858b4ba4fc1b818d4ec6f0875bfe36a91347dde0530cbb5bec6250340507b6168a25f644191132a540c057ad537051568cf146f856a4d2430518aea976031e917dcc6182f111d7c2ad3fdaee91ca1010001	\\x4fe70c934470dc3244ecb93465214398e2b59e04f4c7ababc3f85c570307e1e552b402af07fa93f7080e99bcb54a38358b3e67cc81791729d5a30c7985f86f0b	1685206533000000	1685811333000000	1748883333000000	1843491333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
406	\\xb6eb7def087cef6cfc981a544bf205ada611661712ac64d09722e1699047eeb3a3da7c9849a97d7fdc2a9a81ec16318a9581cca1bfe484a5b3d64ff51b4dea1a	1	0	\\x000000010000000000800003e32ea1118b5da9b57648489a159f4e272a6c2d72454c60781a027de5aa48e898faa8bc97c217b377414632ae74507e0e2c30b4cf6214666f63d975f40fab930a0220e16c5f8b345c886f96e8d5ac283f68b1e7c1e76bc5167a5b7340d7334aa58bafe529d0d55e4a86d36e56cce9947a371b21dcddcf591b01301e11d28391e5010001	\\xac2356e1f432e4282ebd94d6f78474b9ba8973b22edf78a6adc7091a68e0b419a6407d5684d01e713e8946bfb527c97c2bfcf0f12a67eed64832074e6933630d	1685811033000000	1686415833000000	1749487833000000	1844095833000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
407	\\xb727393a63a11cb7d521eee6ccfbaec544f49d4e93439d22d8490c63b74ebcdbca3d3d7cfb77218f6b1a73ce1430ac50ccdcc718a6eec0eee194fa01f6926d45	1	0	\\x000000010000000000800003f4055f71cafc722b509a5d7df2530192f1ed4ee69a25e0128e558e24c0ef4b9c89abcd55dd5e6ab6cd9e981ca4ad3c7d0144af89d7491ca897e014077daa4aaca6047decf47b9621b7310431504232455ce8789e795f22f169c29182e9fc12193f04ef4c9236e2cdbbaef7db451d7a905a56869f40177224e0db6158ee58612f010001	\\x2e51d5473eca482ca41accad4fc8b934f5f6ba94b04c58b0aa4f96bfa2cc4bbda2e4b7b004bc6d466dbd175917872e02321704cc89c342f6fdc129f2ce94470b	1661026533000000	1661631333000000	1724703333000000	1819311333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
408	\\xbb03916dcd655422008d04abe7c460e5add6acf5e0164c34cee032656f52d47d2bdb15a680398fb7994e3fbf5eb06c8c47759146b1130f062c2fc784bc06a056	1	0	\\x000000010000000000800003bd03143991284ec5fb74106d8797adc319f5aa5cc11be227740f60997da886659517d6f6e7b9cf54da911c3d5ce7cfdd79f214fc1efd687f7456fcebffdb219e94f6d22fdd295c22c408c1072e4255cdfd76b423b4aba5cc6a0ac41c098310163f98de2c608e5b1b62c4d6d3885c692e3fff717fb7ba5ab44cfe4292c2117597010001	\\x3fbd8b26696d40e58c41f0f5b0086317fa1ef83e58ad2719d8fffbcffcfc22cdba8149932c7027fe04c22e0e352f991a6180c77be2074bc6dff2d68aeb6e670e	1662235533000000	1662840333000000	1725912333000000	1820520333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
409	\\xc7fb4f6b16a5254721e6db3626aa48e80d36bfbbc105e540f5faeee2bc3b46f4a4724eb2f9fcbbb6deab9d2eb57803d9e8c8fcdbc7427fcba5a7d2a89b81dbbe	1	0	\\x000000010000000000800003b04dc5d136593855149f8f69e813a8457246e386fd7163c7fc81e64049c0b141094515b73d3561848a121b3951f24e3aa122607c760e4e2cfb07e326d6a3568b88c1b6c18d8a23826888d4384cd61f897f145f67e34a7273f594fb7002390e3e409e89d253ffaf33b101bb3a23d1d3c67b524adae384145b3aeeadc74bde8c29010001	\\x2db60b71b9f0ba446d75aac87c68579def63568a6d266ba4f5d8e84f0177b95893545eeeb5918171d04f32acad2f6be8c64929258e51dab2373d1091297bcd0a	1674930033000000	1675534833000000	1738606833000000	1833214833000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
410	\\xc8fbb894a857070fccef1866f75e2d34fb8a32ad345db449db5ca3ecbe391e8fbdebd830bb822b47b1f339f2c70808a732ef880bef4412c45533cc3df296c8b2	1	0	\\x000000010000000000800003bf3173cc2e4c6d9618fdc632fd90a565b02224a8038ef8030f201f7c783be1a71dad9f9eb7f36a7e9ee50ff58d357a690972f23ec07462883fe9ac340f8bf1d8a4a8645f9fb8198c9e01e9027998b0cec2ecf11ed1b1912b15ef62232a390f3ef0ae87bab26a06f5b4c0d1b10253253c6c72def32eba4f62c164cb63d3d04c59010001	\\x3839bed2d66b09caac35840cdfc4b3b9ae0a8e80f830f4f4a9feaa869d1b661c0752ce2809fec363872577290143bbd416ae57d860c4fed8b751ace0d971ed0b	1680370533000000	1680975333000000	1744047333000000	1838655333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
411	\\xcaa3893014c87397dd2e0bf8755cfd5733ba4e999cef85ca0c07318943e94ce681e36ee8c369470e03db522472d67b62ae856ee3ecd0a01016d34732ec88efa1	1	0	\\x000000010000000000800003b37c927615bf92df6a3b0cfa44b657019f3aa2ae26d02e698f63eb84791f0e9f9d6d5705b43182ca35e048090c308c37579f2f65fa7a4068496b840cdefed21b8e3b70964b46732d31f63e7c6d16b3d70ce6ece273e1b17ef73aa33e71f9288dae4b95ef992ff40859a6ffde53471a48116a141ef5560623875f3a2f0c938bd3010001	\\xb7c8491b6c139aeddafed8a74cb2c740c0536138cb3d6059e8af8484f8d0ffc9d75dda488cd8cf8e04e958e22805ffa57b6b6e55a76605a518d8724248ac8906	1664049033000000	1664653833000000	1727725833000000	1822333833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xcfa3b4086684fe668142e21d064156ff835b66e9a8545d4c159967af6cb4c5717b3ec3524290cbd8af12ce1e1206021a26ea47bdb4c0a2711d3e78923fa23bdb	1	0	\\x000000010000000000800003c1d8f138ee30187de3f6e8c3940b5f913673e605c56c1c0c70cc183153b68e0e21ea160643971afd94d43513735069b078c8203f3d08c9845c50d24d60bb4b3f659055ac0e6b63ef53a1fd09e545014cfbac121bfb1fd66da2fc0b69ccf9e152c2e52d462c057972c9529e976b6419aad471fa65d80f2ba1cb6cea17a8bded07010001	\\xe796a3823a4794ed98620eee3aeb1e8aff73e733f6dc47b686285f261e4284b6724451abfee19780bf6d2680447920a89b582058ee06409af4cfe45db90f2e02	1663444533000000	1664049333000000	1727121333000000	1821729333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
413	\\xd0430d605539aaef3943bc906d2f9b47be9a2bb327759db26415ab73c1d5630d1f3a95036fa985f49298400b309e4e8555f428c7675a128d0353bda135ebbd77	1	0	\\x000000010000000000800003cda42d3aacc860ee55c408876c57c9c871f67644038f1e3c4dd4208c09834f17d458701f1d4745f6153b369aed783f323625fa6f67139c1f5436b03f5ffbf5be622cf28ced8cc46ef3d6e821e18de9c4340aba6d6d0b9635b3faf27408a72e95c410b087459cfdd3d6c25e16e09d8cdaa940ff2fc2062b0451b02606d9253cfb010001	\\x4267e80c8ee0abf69de9f48c995d45bce81003e1d7fc2fbcb710875e381a64bed1cf21d779f7f0f070d1d36cd975c7bfa96af0a78118d65334a1fa94f1988a0a	1683997533000000	1684602333000000	1747674333000000	1842282333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xda8be4d3977f6d952bdfa4eb87303b3f19c3e6ee168c02676a6a9174cc7eef008fb0b06a06dc3474d51c7e6d900a594a28289ad3cee009de35c2ba96812abd6c	1	0	\\x0000000100000000008000039bb6e85f35828404705b67965e949d985703144af36c23aadce2addf0b4e2f16450219c8927a2fef11cfb9a88517cc7d247c75aa8fd42bc470269c3b0302872bfce912939844d4909a49a146376565f83ab461773f3076adc80c2504aa1253804fdc209b9ad279a9ec9c8bc07aa5d0e352e12206e513979d2ff6fcb113ff3cb5010001	\\xc55794d6babb3ddffea9e9d5989588928635bb9978fafae19e773c0bffdedcb28b53933f75f090341716822055465d10a9fc03b781f4295de8c191a1da5fe20f	1670698533000000	1671303333000000	1734375333000000	1828983333000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xda7b1e65d6a6723755b95df65442dbff0bec8d016a839190612e6229e2b8b1fbda5a0ef4a80a3c36393034c56f0509dadf8ac2a79e9c119cd52c91e78d02112e	1	0	\\x000000010000000000800003e8a73a6efa82c1b818d0fbd3980dc926fe5c7aef099d44243311b430693f7bf1244933ae4e836ca0139816638822ef2b780b00a3e4b8dd4b09e2d465d8da3bdbc5b37de1d2010439b3efa5b12baf794977afad58618bcfee77426f76330189d42996f4da68bcf825512307cca0b2a5f22d90626e5f2447be91cef127d8cbfd2f010001	\\x829a75c47f960d2e71a55d617fe085e16df5d659db97477427f5b66ef5e1f306fbf0ecc941d477d75b43795c5611077a8862ca56de171b13179d7c6f06d4180c	1659817533000000	1660422333000000	1723494333000000	1818102333000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xdb175e624c45d7a02b5eb7818440e8f8385fbfdea1cf09feaa2384a212033d9726551c458e6e7f7f8d1ab47e84d09644f8ea77bf77d1f51cf39790dea37e4fce	1	0	\\x000000010000000000800003d33e63430a6c659c13b8ff7524e4f95bb19e83efef5f12a08e5faf2ee4550bae935110198fc3ba808af9afad85333fdee6f081b817710f2cede203388d073994b11ed20267ee397a36c2921edd5eaba3df997d89e5f925178132bc65f5be0ec188c92389f4d5337f3b459f5051bce80a10992bb2dfc313c69afc14d58eb69bff010001	\\xd60a76fa9d5fac9e6f425668a031560ab50fae3d1caea78baebac19280d12998363004e323fa6ec241be84c99e3fcd218240ac20d88248f969b359e4dd20a002	1675534533000000	1676139333000000	1739211333000000	1833819333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xdebb8195d607e066685cfe55927b1982e478531d686f7b9a56461c059ef8a8365657f44ccde5c417a7d7670c9224fc485c642eaa54a5c00c968417ffd0748be0	1	0	\\x000000010000000000800003dbbee3261134537356637d951c0f06e4c475b39211b7e974428d6411d409234c0344e0dcb3fefbaade8ab86a10eac4aa091fbe23378a93505e33788799bf6cb3abb0ecd3fdc0e7012384009f2fef31c0947b4f59b827b3e5d6e6d8ff3c6187d0572def5a98ee748de51dbf1ee5122ab4f575a8807a46a8a9bff4a755b158e519010001	\\xe71980af540ca1bd66f3d548b21e9b25a3ebc8bdda8e4e78d4e3bc513ba8a3317d173f1343530596c27f0368fce85853f0708f07e3b7b5fb4305ec7f4225a302	1691251533000000	1691856333000000	1754928333000000	1849536333000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xe68745620f0aa6153a29c5d79c5219aa87ba29af46120ec0dc83103c518761abe16547dcad4fb677a8efb47bba18d05d0ef9c75dc8163256408590ad38d1d90e	1	0	\\x000000010000000000800003ac9113730b7e2eab734b160f7fff27180137ece1337b3fa9aef2b0c9b68808b0224ef58b69a29da435534e1a4f58e430936187dc48d3a4f25cbb085b51c40d053f59ca583f5d8bd004e68e718d29f885a0aff5c8b7e4a15de204961522ee485c9a0e6d38e780ce7e0a6c7294875b15828b590ed0dd8e5bbd9f5e9249ca6fe58f010001	\\xe3f6ec68bb0779b5fc26e3468c3e7ea9f6fb6722da02aa658cb4ab1200710317be3e0fc4856b960bd84c7342d52121fc0f954c8d8b3c2f881bd317cbc92a8b05	1671907533000000	1672512333000000	1735584333000000	1830192333000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
419	\\xe74b0d94221395f0b04ee6dd86a569915aee2179962a9870e0b1bb236558bfaeb958c77fce169700e407a0d642709fb5712f4f5f4851ae37deb00a9a65f14341	1	0	\\x000000010000000000800003be6b6c423b9e05b4d0570e9c1ce3a4a4e023e8526332e98e1b77190be5a9a9490e162341fca1c0aac4d279d27bafe3acd759bf3b9d8f4be8c8a0abc9b283426e7e79a4895714eaaa4745787e7d4ebe9f419d1b77a0ee4448cfdda12672acb8d701b41be6bdac1eff5957712de5590b2ea5bab00647c9b07cdc2ca822cdfcecc9010001	\\x754fbc031ccb8980d1a941d89060f4df7ce1f1cdfe1395855e24f247d3eeb666643b2f8b745c8bcf7df1dda8d440694e64adcd162f7d4b578c5999ac205ab30c	1664653533000000	1665258333000000	1728330333000000	1822938333000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xea23a95da7269187f943d2b3214181a1185ad6fd0744453302b3155b85897ae74c665d9f389cc91c585608879c4b44cf83eb51cbfddfe45b4722cacda62e39dc	1	0	\\x000000010000000000800003d3c1e5dec853e6af821d6cd42eee45104a12baa81286c1bc02dfa06b2867c64f3355e5ffae9957ad2d15a416af34c8be35eda0296eb8bde6807d7f44955bf55bdd3eb2e534ed15323ed3047bc0cef6cb331cc18a481f1dd5319dc2e671b43760dda0cfd6c217d12ea5b6f42232418f927b254ab6166d3f04a8ff94af87d60c15010001	\\xb6b111a4239ddab728bbd7c53be6738de7abc6f3102f90bb1f71c677af7c69e166663151e60beeb6c3ec845a8ec1b20eaace87e6afc1de19c52c6468e6e5920c	1684602033000000	1685206833000000	1748278833000000	1842886833000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf10fe2015965a1943613c75bee0845664e5156a0415236393e0e9247b65a555e199c51be8f2a652277e5ae093f532ff8562f28149cfeb8df3d5b898bb8a0b6f9	1	0	\\x000000010000000000800003ba93822f10229d05d7c9006949e80eb0f32b501123f36bd0bdbda4872999902c0af39c010b61fbea2b6af39c10b304e861f970353fdcbd89832d30c1ca44d7b01ec636a8c46f4343242eb8c870267bdef2323537f3d52004cad9899f40787be704513f6640e160f7ca817977e2a21e5c27999ae5b02e80330cb3332bbcdf8a49010001	\\xff59d4f8b19667a115efe582a0a46f4962f72cd6d06f8ec277c6c52b4ad0beee472a2c3cebf5d34e924735f46c868373ca89c5874bd56fb27820386935cd2403	1664653533000000	1665258333000000	1728330333000000	1822938333000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
422	\\xf46338cf8924f96ca4f827cf9021d8803ef2f41f1d05413ebaf5bb947a327bb06e0bd725793369d7551aefe8b05cdfbeb3710e4e8030e3254174d33a46f4d253	1	0	\\x000000010000000000800003a5be8c4358db4243c211c503d22dcc14fc774fd47f7c47fd57e48b7a4a48db63b82eeb86b89ed28a96c56145018f4558ea1f98b4ec52ab2ade94498ff8c4bec9fd3955d55cc01c69e1a2034455a3a63c85d017a5054de81ecde8a377c32ee528a35d42556d1801cda1c8f472a41614e8cc550b235849dd7f3b104f4e90bbb141010001	\\x42a016e324013eaa5f58a8f058018899a6f3354f193430d1d3f2dcd29c25840fd9ab003c0d6f7a802cfb3fc785afa7686c29c11abacca5dc777af184fa01a807	1677348033000000	1677952833000000	1741024833000000	1835632833000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xf63bc12d275cefecb1b6da96dbf052877dfa6f60df816429562cc173132f40c64839e3470cfbbd6ccdcb86c99e60a6e3adedc900ef9f1953b687216128391409	1	0	\\x000000010000000000800003abf376eaea32745183d9f89773f3145797fa030c9b0baa66d919bcf247303ae46cfff3da02aee53dc3a6f0832675df9c4194f3b46ff16025c0fd717abd3cb8dbc921328632f1b0aa058eb0d026e76dff5ddbac401ac2fec804d37583476ec418cec0270d600deafda02429a4bff06c57c7b72a4c375faab62010f9f5a8375e91010001	\\xb05429212a7bc7a87f57256c632c57dd373e657ffed4855d5057ed0da8ba01e07cee015d4445b45febf058850ad5b2e51bfc2da3b26fd2ab1d891a777fe50500	1685206533000000	1685811333000000	1748883333000000	1843491333000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfadb76bf004fe7d451588f0779688216764283b811b891a396f70529c52118c702d887f19ffed59c0aa74b08889cacd45a0d12501187603a36543db253165e04	1	0	\\x000000010000000000800003d39c5e32a87cad2a786120806726c3b0a1c9e4d5c6c6a7af557532b180b821cedcc939b9989b47469c00daff3c523ebf6a424d7022d4615324183ac720e9095bebd7c105268d667fb34110fb4de18731556ad8766bb9ffcc62cce4f3e704320ce33af6a7c5a269316708e9bfa719cb86f4b442f1674f715eb3b9c6567fb204c9010001	\\xb65a93317e642cd18eb261fbc6fbf20a18191c741cc6db9112be27132b95497ea74f8eaf78a985d543aee09131a4ec66c2778f3ab8109571f8d339cc2bdf0a09	1683997533000000	1684602333000000	1747674333000000	1842282333000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1659818461000000	1334984701	\\x194d94de25dd873d26fc7fda67c97a6ced3316d42b4273027e8fa181217633f0	1
1659818493000000	1334984701	\\x00dd2b54655002edb099ad6f6c85fee08da543cb60e79bada10a618421c7e24a	2
1659818493000000	1334984701	\\x21971f2108925a61a0f76d27d88e18109c87ec556155a74f9051af16ff7c5946	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1334984701	\\x194d94de25dd873d26fc7fda67c97a6ced3316d42b4273027e8fa181217633f0	2	1	0	1659817561000000	1659817564000000	1659818461000000	1659818461000000	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x2de737819f8baf63a95663c198a810df7f20c134387b0be01de65ea4d5664e5a60fe0bc145452459f7e7a6dcc12dfe70b97d86739a50ce512241d06b1e0f16e3	\\x01a1b03053f372cb2b8a18844a354d9aa8ca27812164180da9c3d1271f80b0b63ca37ddeefdee7c6494a9c3a91c7817d0bf3094c36743cf276ec7d479267e30c	\\xbaae8de8ad47a209f3598197d35acf8d	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	1334984701	\\x00dd2b54655002edb099ad6f6c85fee08da543cb60e79bada10a618421c7e24a	13	0	1000000	1659817593000000	1660422397000000	1659818493000000	1659818493000000	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x9eaad7f119786d9f713bb34bbb888917c023f45140599e3921c02db0c12875e70d01b1161b8329e7d166369a930e8a1c1fc33c0a1254f67a5e162e59346b2fac	\\x5c0f81c4aa06832d5276d372dba0691adeeecae66e3105b33ca5ee07e6bbdbe68ce9b01fdf1755cd64fbf14dd438b359a8a3c724f160b95490e4c941902aee04	\\xbaae8de8ad47a209f3598197d35acf8d	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	1334984701	\\x21971f2108925a61a0f76d27d88e18109c87ec556155a74f9051af16ff7c5946	14	0	1000000	1659817593000000	1660422397000000	1659818493000000	1659818493000000	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x9eaad7f119786d9f713bb34bbb888917c023f45140599e3921c02db0c12875e70d01b1161b8329e7d166369a930e8a1c1fc33c0a1254f67a5e162e59346b2fac	\\x1578c384491782f0cebe1dd1d7b08d891dcaf5a82b51715aa1d468dba08464c1603fcbaf6a9b9a61791acf7cfbea51d08ee8ac5341bd4865c55fe6214a3c8e00	\\xbaae8de8ad47a209f3598197d35acf8d	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1659818461000000	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x194d94de25dd873d26fc7fda67c97a6ced3316d42b4273027e8fa181217633f0	1
1659818493000000	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x00dd2b54655002edb099ad6f6c85fee08da543cb60e79bada10a618421c7e24a	2
1659818493000000	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x21971f2108925a61a0f76d27d88e18109c87ec556155a74f9051af16ff7c5946	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x4d3f90e8697e563044bbd857f6abb8e5de6090d11dba44e755fcff295b77893b	\\x7d093fb005de848fe001ee9616785226be41ed75b1b62470c63bb214ead7617d8fb5cd89a1f66fe32dd1131731e88f3ac5e3cef5de8d03f4adebf2acd887370d	1667074833000000	1674332433000000	1676751633000000
2	\\x3786bc2f2f3f49e81f0883c385779b5cf5d8e48d915fbb624acb38c579576956	\\x740fb5690cf37c44909ee1d9079d7923dfa8901c383ea583a1241f85c81d22eca81167cdd32a5a18d9622fe5c7218c1547f9b1e4f3a37af1483fd0d14fa1260f	1674332133000000	1681589733000000	1684008933000000
3	\\xb83a4a17cc4ba6f0af832c8bac59e099b9e79882b5b2bbc51e91855a49842821	\\xa5ae771592dec9ede3d4faaf6627e5163e90cc4522cc3f84f823e248c6f3439b2d0ac4689555a6eda65f300aa89a4498c297ed9af5a7118ea709e361e06c1b05	1681589433000000	1688847033000000	1691266233000000
4	\\xd971fa5c5446598fe40fa1966ef0c9e92b660f113ecd4fe082b3f856d19c2aac	\\x362cb36c9178849da5a2f37f7e6f495502c66c55f6d20af8f7246c9fe37e2a211d45c90d9dbd456402974c55973b62e0fb656d67def659ace2fa2c663dd6ba0d	1688846733000000	1696104333000000	1698523533000000
5	\\x19b026192e86210d7bd624c42b15146d40f6d9d2207abb39467a3e2df1fbd8c3	\\x37603a74b5b99acb8da2375f6433fc77a138f70c3d0ca91e7064bd6e0f826d34d7ef8a68759aa0d591b5d3109ebd37faca2b5258dbee094834e6b2af7fceae0b	1659817533000000	1667075133000000	1669494333000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xc7529abf41fcd1cd4834b3f1db1dc97c09d845e4fcdd443e898962032f34ef04858903b87a6ca6bf7f3ba1e749274b8f315333c7084db0f4b537e3f2c591ad02
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
1	295	\\xa1f86082a991e5360da8a6b0d58633f974f6ae6a5b41de9c45bb64a12b622179	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000090d70035984ac46611d2eea7290fa908c7d54c9ae803e2cb507f503cb2af4b4d277d3f4ba1cb83ba69e1036de2b416d15dfa5a7b280e70db57d2ae039605cd16098e990eeeb13c884d5c49d3784883f9cca03eeec4021e4b01f54382140ee8c6da8fd806bce56c456fd9a7da85cc1c994781305c5bc6669a495194e0a00d3f6b	0	0
2	186	\\x194d94de25dd873d26fc7fda67c97a6ced3316d42b4273027e8fa181217633f0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004ff9637f1bc800a271fe69bf29f57e46a9ad7b181d71c2f7f7473da01ab7a3b228bf1b10a79857333d1dd568267fc5ac4848e668a00304831d61708a9db3b74922f26a7523fc50e22e95fb61aaedc9217d5de874dc31015a8be7c4346ba057e2d2f93f11f37a8c7d833b8741539f364be91f510c2bccd71172f224f9fe682879	0	0
11	354	\\xc39d8338941d6bc80c809f87f5b94bc864c34687a08e637b539f697265b6af3c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006593bb199bfb02fa801c7a96b0f54d64a8000eec76683c15d3176461d611cfb02b81455fa6c354391a034e0170033bd26130c7ca1435f5d19504bd95d0c5a433393b44f321755a05e8041e543cd5fcba4e209b1f27d6defb7d83b0014118d7560a0e1c1b69ca83b152bbd1e262a4f51c4ec153e3b4ee8439ba6394dbb0c6fef4	0	0
4	354	\\x1c270e433d68e1324b5188b22425e74e27fc1142de6d7970cdb83fb58aa920ee	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000119f510e0a0d36d19dff2bbc3b3e4d0c5f219577f69d64b2822627bea871d6f319b326e75fa55db8e27fb089d5299c340c52d302fffa09567ee6b9952ab31808c7ab6f8f9e6adaeeb5348a276ff236fe31b5a839e36b970ec958d48c62aea78827ba1f0d81418792b57d5e79aa7d652e1854cd3c9285d00d22577a254bd02403	0	0
5	354	\\x44764cb98d8d74be476a50abfbb73b27e51c6ec29b93b6fdffd11f6f1be28627	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000808309924c882e382998498b0c4050e12e198e91a171e26ddac68f236a47382702a2b6f5efd838229a0c7beddcc9facac3b345cd6c8ad0950cd59fc5e00c6ec424a3321313ebe276dc50eecee8f8dfc841da64305e5a86ec9a28119ce3ce477adc72884028308c90fc01e26eae0a98163b0fa0ccda8c0a30090180c89a20b4d7	0	0
3	76	\\xb0a0f2b47652cbc58bd293ba56b7b5a4e8c25106d10247f207dd1246e0ba4b90	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002433347ad45899a63bff7d433c3c6deb5022bb612850dbea56e29068420605e40bf1885ba17de891fe96cb6938c3f674cbdd198d8320ba8e8bd1ffad70245c8d9cb625d12305af8e9477f85234ac4d6fa566fa658cc3e3232ee7f420604af8857857344be524dc94ae2a297c2badd94317f952947808eb3fbd6801bdfa34f680	0	1000000
6	354	\\x60fae054dcb65fa0110c92bee9e66ba7d5c57d0b32e8b66f3a74033b12d1ea02	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003a94f77a3aebfd717b68cfd9c26bfa2803b6de59bbe7bdfc8a9a1df8ef4050327d55e97e3c59ce5fa758449a69b3f70b9a73aa56bdd49e3973ace15d2a9491a1c8041296ca8af1d2a9d6e6522b51e3b7580a0003589cd9263e281c303c31a682994949783dc7e4d47e3e641d9ed7e6872e27722a2286bb4d03e2b3c8ed086043	0	0
7	354	\\x2e1162ec1b8c9a9bd2ca485172e294261c142a454a178c32d968958f2ae375b2	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000017e6fee4626a94c5fbb233d5e913b52399165c2d738fb334836298b7d7027d631d8999db5360900893ea67f6080670adc3e3647adc8b76c312557dd4921cff58583bcb57b73ef59a7c2ee9e9d834aff63f60c0ad8f37d9b5b48c54d206a13405a4944ce1cea228e7c07953d674f30ac0eafd1616d8bdef2d2e99d236f217a43d	0	0
13	114	\\x00dd2b54655002edb099ad6f6c85fee08da543cb60e79bada10a618421c7e24a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000021b6d0da15000d26441951b47379e3131e0f859bbc63c87774dd3fb3f2c95d87caaee1a715b2c08aa7740093218db7a92e3a9ce2711ccb13221cbd0f1ff9f79bcd2a6093cb5fdfeb893c456de86d2a271dc073d96b4570dbccea910fa2ededdcd6764cb4d260ff8dc0f6a2a5ed100818c03a8fed4d976d2ac601edfe6528b9e0	0	0
8	354	\\xb82df57a5e25c72a6378290f4198b2c40d4b58e40b16527297a48042638ee325	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000c70283d7e14007539a0184984c501c6556a17153935df70741252022c4d8fd4293e0aca565204fac7629993e04a45bb1e38401f36b49f8c49ff5da2ea3c8d8fd7aa781f3c0dc4ea8b77efaee7096e39f999cfc36eb7bf228019297c9b1c2a63ef43248e92eb224f4908deb656f550b667c59bb0031fbe29f9bb7dd8e6b28c0c	0	0
9	354	\\xc20a86f69c274c2d722897444c1fc48d5b5421f5482e429f504d08347fe7c63f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000020fecc05961203d14d46488846550d99270e01c0be6083aaee35b843f19b1b0a408311f60dc0cec2633e99b3f19a567333972ca2dfd0fb692ed987e5e699208baa4dc31d1e02dcc89bc6d2012992abfb004cf7ead75a81874af61179f247245e7506ebe213710e63fa93735594ad2f0f01cf587414c75dd65e813ffb97ad5fe4	0	0
14	114	\\x21971f2108925a61a0f76d27d88e18109c87ec556155a74f9051af16ff7c5946	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000bbc103d9353988a6442750e70a68567cfa30cd481f1b6ba77f00e723bbfcddf5caee2404fc49e7f23f64932781cc05ad6522ad3e18e21093188fc4388789050fc7336a6da446e8fec3d97008e80e5ed47be8308f462f8a48ec33e52363202294bef9ce6f79afceaa5196ad63af15d35f133de80761264ccf26f7cae4333afac	0	0
10	354	\\xe6014802a20e0a3c64fa0702452bfe1b80013cc04a1e2f2e92f5e2d1998581db	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007ba91dce139b2f5e5abee683b9992ed4946611dae82dd2a3fddb9cd49de0a018c9f9217dbc84e4aa74577148ff91941e8bd0949ff5fc83804a980a7074d4203cb94a74933bc221f053083c5b3d4619051f4c63a2c173c64380640d3e0429765305a06281c19e03337f11b23557f9aa41efaa71bc25d7938a27cb575c3635c31d	0	0
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
2	\\xa1f86082a991e5360da8a6b0d58633f974f6ae6a5b41de9c45bb64a12b622179
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\xa1f86082a991e5360da8a6b0d58633f974f6ae6a5b41de9c45bb64a12b622179	\\x61f8f4984bf4169c06808b4f0d0c8b25c353732200394b7437ef29ddc5988ed92b466d742a01d8082de771908e274b2b698c4558a7606372e60f93ddf56d500c	\\x86ce6b3e562ebd814bdf263f4976232d1a2c7318ad4b3e05f491786e020c8d0a	2	0	1659817559000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x1c270e433d68e1324b5188b22425e74e27fc1142de6d7970cdb83fb58aa920ee	4	\\x607745170b5146002f89329606c553bb800387c52ae0a59d4754864730b89303725284e8db52a21faa65fbc9c8b60e547d3eb6f572d079b4c6873706b534cc0c	\\xfd9538d97f8c4bb3c4024200836e2960e337a6abd3a689b69d2246420dec7f3e	0	10000000	1660422383000000	8
2	\\x44764cb98d8d74be476a50abfbb73b27e51c6ec29b93b6fdffd11f6f1be28627	5	\\x77982dfd813cae9509719c5cfa25f0d111efef64861eda2157e781f3d1dfd8256c749acbf0538b854e51b5e4956e0b28d8e9fdbba97d716caad22a8d6dc62e02	\\x99fe72c61733fcf79c79ee3319be20cd77974208ae0c89b302179491fcf7ea1b	0	10000000	1660422383000000	4
3	\\x60fae054dcb65fa0110c92bee9e66ba7d5c57d0b32e8b66f3a74033b12d1ea02	6	\\x1a57c5857a8005b832cf9d0dcc9c7a4acf863e49f807035a3a62ffb175f4cfd5ca9ae63dc861851358ca63a0236e01b78ea5238329fa585ed7553ef2884f0b04	\\xff9939262d9e84d4210ac6723630db70f65ae5f72d12b1bdc3c9efa3f4a62bc1	0	10000000	1660422383000000	3
4	\\x2e1162ec1b8c9a9bd2ca485172e294261c142a454a178c32d968958f2ae375b2	7	\\xd55492abc2adb96a22bdaf29667d099489df73fdbe66a0e4e0ab44fcd69ba558cd7a24d977ed9c2b24b3f5d64033425b9ecc00f0a9bafffeff5c4223032b9b01	\\x30bcf0904244358d48c410a5b90100ee0bcbdec3a42d5aa73d9c3f3e29dc3545	0	10000000	1660422383000000	5
5	\\xb82df57a5e25c72a6378290f4198b2c40d4b58e40b16527297a48042638ee325	8	\\x345dcad79bf0b593e6d18cf0e43024e04ba29073fa635db3e734704feddfbc6dc3e08e84783ba1cf9d9a02505ce138c44f2d2aef6f7c6abadee29fa8aa2a0d0b	\\x33e0f9d95d9c779354157c8c5dbe432d1c4ab289f4c0c70f8ea4fb353d6997d5	0	10000000	1660422383000000	2
6	\\xc20a86f69c274c2d722897444c1fc48d5b5421f5482e429f504d08347fe7c63f	9	\\xace5c166d1ac6063d634a7efb7c176c4066b60ec1d34cb8c7271baaa39929293a1a6504d078c5d18fcb19983cb948daad5a61d3bdd9df591cd72207d9f28c00f	\\x552145839762dd9d26d16d0b1b399a4c80cdc1d0b7cf2b2c12f5e425aa19173d	0	10000000	1660422383000000	6
7	\\xe6014802a20e0a3c64fa0702452bfe1b80013cc04a1e2f2e92f5e2d1998581db	10	\\xb0944a0686f04dda887efcad1bdbd52d06fd1d8bebd9d381345cd5cf021ddb6c506a11168a73c053f0f7c04316992960d98cbe0cae27e4a5976da1190412800a	\\x07f4043db811371c73d3711618d1d81a0073232e71dbc52420b38458af5f248e	0	10000000	1660422383000000	9
8	\\xc39d8338941d6bc80c809f87f5b94bc864c34687a08e637b539f697265b6af3c	11	\\x886c7bc84b7fbe217f640aa9f8b4fb7883eb68801f8cbb3a6bf40c1e0f8c6c9a53851b5ec706840288cb4beae953b699337459ca0aac9e8841e40e01cc59ca0a	\\x58384a93d5b8dc4ad2a3b9f21d9155e06509c225f64e33866ea1b62d82f7acbd	0	10000000	1660422383000000	7
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x0fd98ff7c745cf6ff8497b9f5c4e07e27cd2f44e1442fec3e0597cfc18def8c3147470a07145582ffe6fca4bac65491aa4e92b1c94e6d9957ae5a2757bb05a24	\\xb0a0f2b47652cbc58bd293ba56b7b5a4e8c25106d10247f207dd1246e0ba4b90	\\x82c3041e78cc183f64b6d5b6be9ffdbfa5e84af34e712dc585ec635991634c3602a1a04c018b0151995c58bc1f7fdb45b7db004bfb0b5e06f0112f5ceb74f50e	5	0	1
2	\\x5a454beb32a4e5a537ff766d48ed8bb733952fe13dc38b585a73854361794f07a36accd17daf7a6ac332be80c59c4836351a110dfd0dd9189287ae29c24b0543	\\xb0a0f2b47652cbc58bd293ba56b7b5a4e8c25106d10247f207dd1246e0ba4b90	\\x2c1578f3474b6eea19e9008081202dbf265ca39f38cd546c13a5f0aa16a50f691117f2f3dc7cd48a0d10f7d1715d66c8736f6c2946bbeb2e8a8c9c8995f7480d	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x7335db30904dcb0151af59f9e57c2968a557751e2eddc8e6c964b6cd3039e9236a46dcc98bc4ae8911dd39a71aed4e4f78ee842cb62ee289633f7861a4f26409	249	\\x00000001000001002ab083ae3e7126dad86626fcab669ddf22cda1bbe96508cec82aebc693234c81d2a32468937d17df86438a5cf63bce9bc7ac0a950ace4358db793ca4704a94ae59568c9efbd71107587006e83b327a4dae93cb7f94ed5cf340503c1a72e4f9fcf374c8b1bd105c85362238df7d5347b2bfc9f71eb237fd72f3e6199f0ee56e48	\\x5a959c6f27bdf6a6968ac81a8400d7c21afc8c5f002c4f5b29aca17b4afcc610f2af30e6a33bdf814e928e356b311c9ab7127a0e66926668f00c62d4232b6025	\\x000000010000000124b6f97a9371b06777f2abdea9a111d0934bbada5955a730c741d10752b9d6d92623caed450491ffe97f858f4927eb7dc5dae0e0b69d7dabc63c7337a95802a69d48fb23007d73ebb405b9ee06464831654eeea886991c41e496859a0090aaf7040955a825fae155a9b85eb7dbdd30fd9f5e731ec2f4db112ee025cd6550739d	\\x0000000100010000
2	1	1	\\x814bd13e1a2198d2e3e5036efafe6b8cf57e97898ea2d9c12f1a7f4ad94ddaadd8f117daf6542e3c8aab3b1d4de00f867e13cc9ca4588085495c49db749b5a06	354	\\x0000000100000100ddc82d2c7b3a8d24056c81661223b848c2458fb1deb70c5a6e17ef9886ad4c8893c4c7e4ee2b302ef3c428ae518a5b3cd20fb7aa6913b17bc93d0b07b4b71396aeac6152d8f2867abfda398ea07a21b848b7a690f1a108aa3cbad7c331f09ca52bdb2838e4b3cdd41d39acf5adb37d67f5f3c897500770a04d8e8c2236a4eeb2	\\x967a3e8e089ef7f0486a027055b9c2ff27a2838a25e98315f86c92393ff3411b7af33cb89a2161ea18bb6789793faac3c5fe8f0b879c54ffd6451e2471e8905c	\\x00000001000000014d8283ff706b6100f1bdaaba6452401f35e646f9838e7f44d48b605b063bd09cb763ac462fd84a56935102ff5a04ac1d3b1b54945644a73fddcc78595fffff6db655aa563df5cbfd9f4c6077f38a6ae0d7815c1cf353ce16091d13ee6b057e985492d89ffdf7f430d9c01c5271d1702626583387b85b2d2e3ea27fd47eeeeb5d	\\x0000000100010000
3	1	2	\\x98b413977575b87027da643648e4c679f2dba403fb7256dd110c425ae270d94dbfe551ff050a8b78781b4226a3ba9a28b6b53cf1e44336703eb838bac29c2802	354	\\x0000000100000100a561fc24e2555be115831c7d884235ae156faf34e6e9c2d96247173d2bce07cdd98d54d1fe433a8f815ad5616729775292fa03e321d174997b158899ede731e436fd7baec0ed9cfa7ae8a092a69361fdac5c6039da6a588e56a5511736c0434fbe37328b636b3e73e1672bcc2b1af7facb35b741c6d89c519a5fcb0548d198fd	\\xef92b0da23dc7b57ddf4c63649fcd9f34024cab9e8a4e87d6a07856cf22649383b908c6a920f74d53350e55d18b0571130582824214efc41880afd809fb1872e	\\x00000001000000018789796ad6bc7e571c78ae19211bb3ba3f8d58344eb0ffa9327ba1e9a3647a80c9c51d8126998b8b0ef50898251459cda1e75b155a76107cc9d8eaea443f017b4915296e9169374acca8957c469ab9a92a47da4734f979ba36b22deb47086e964498749c5736d02456028ba9d537e28a2ae3577123cffd8c412ad73d5f1aed49	\\x0000000100010000
4	1	3	\\x4b84c5d3477a3185eb1eeafb97704898fad7bb497ce0d528fddaac312d8565b8cedaaf149c28a377c716a27840c77d75bf028be9bfd0aa46b8baa60974f64600	354	\\x00000001000001000459052db2a9d71073c4f5d16aa5001d0de9498fd6633def7a7e067c2c67ab69036d9de93c286d77b2ecb7b01fa2e4f7362c6bfa065aefda57334eb80e2a80cd076f129996b7a9918b7290f75dd4305141f63055869d968ec95ca5bc6e44014ccdb54b6f2d2920310a8e2e6c678f2fd3eb24418b80e4371eda49b723f01c5afc	\\x94135ab9d5d808b2ab208b07cb7a178099d03fecb971f170348f6864eb85964662ab7d91642e8b6c6795f8431d9318450bb75f1dfe1491c4495449337d3a2dbe	\\x0000000100000001047bd7628206f319540e97392e931ae60c26c197122e92e4720ea36f831d13396e2c2b3c2a2d76cd789e3c8c83589836affed7a265eb10b77540b8a9ca95c452ab7b838fdd27d3195b221ded5d0c373cf46238043ffb42e7b1692e069d110035fe84331e2cbbc8f82ffaea912ddcac64dfd343438080971af35ab5db4baefca4	\\x0000000100010000
5	1	4	\\xd22997ed1ee95667d9d774a492386926764dfdb1d94941242ebf38dd5363c993cd763fc0d501734005c648c78a8afbcfef2417479ec44b57882ffff4c6e10b0f	354	\\x000000010000010002b465a1f7afa35fc9f13c57132446adeacfda68f0ae0febe6d333e523e8463e84b45b5059e5c362ba429de1969c34e3564b90b123f6180eba146353dd360dd62b3416ee7e0bd74b5d8ac5de23f961da0642cb22b53527de5e7c35f84137bede4147e3f89b8840cbd2230e65b544bf469cba8a97a3337528881eed91912cda31	\\x763f9789ed0617ae334bd5b87fe73422cf8249242b9a1a81fcf2faead01a90f7c894330bdc852ee4f5ecdef06190695ab0ed8231bfe93f7d802f162edd7d317e	\\x000000010000000124d488ee612e43401edad2270cc109bff6264db1bb2db27eaea59149ec5c2434531696ddc688c6064300eac23051b20a54cee5203109f732ac02b68e36be5e527ea487e78354ddaae1a437427967060a12e991afd2d51fbd18c82882814bb5be5948501f4902b87abe7342a996901a58f19c4a52af6d495ef5bad154670f90fc	\\x0000000100010000
6	1	5	\\x04f2729d2b68a2b2fc6f69781c769951f02335001e6c7953c2025b4dd2c3a84e3c89b7fdb91f5eb686118b4c985019a07edb1499374ba3a5c5195448ee0f3a05	354	\\x000000010000010050fa3ec57b328249d79dfdee0bcf646b66d3d482c21fda0fdf3fa020f130607b70ea305c63e4afc8706764d65f97160682cafb7fd74dace279e314a990cf1862e207a3dd1feef9bb7951178916d2e88ce7fd99b3109e513d2d465931cd9a367c7145acb965d3a2fd97b07f097bd427e6f550d6aa8e657da9c4916ccf4ee5c633	\\x7115993921e9c1ff4808808aaac4fc706b319039b52e35e0203a5a3cd4f273f0d6e611a4fb74def5d9a3cb356e3d315064bd961787a5e89e496cb3d816bc3d1b	\\x000000010000000106cd4c812652824918d4e982f98fba8ded147252ccd051d62795d7a0f8919b71ec12e512c317486d4a14bae61a2c4f186a7e9f296f0c7e977c7b3ccd2fa4fae0924354041a7b5657083bb9d6969ba408de4092c45123d8ab10064e94bea8d275c4f7599fdd1528aa4ad79632393063e9e7ff3faeabb4a091eab5ee30815e68ef	\\x0000000100010000
7	1	6	\\x2c16a51390c0af93999a6342b0df9692a4dc1b7cf1e91cba69438837ca30123db5e92e385ec849cb79160ac1745b3afeabf9bbd7fa652ca3855ca8ffe96f240a	354	\\x00000001000001001d845e92d788e79418e20da6d7fca3aeba6dc6105fb9950bf1483489bf39dc9129f47118bafa25836b131316df78c16099cd4704d77588523e605c3747082e0fac79a30d1aa5c17e67e9f7c9a08718a8a760d4fb5d07c1008277d678d8a52c91e36f8ef42b2060bffec7f00253c26480e9e8f2d5cbfe86c93e7edf12be83e429	\\x57d152ce694da092b5fd55c44c383abe620a2be7218375c631d1c0ba06ca3656783b2e6f19cbff2348006a1ef08a05e8724f390c265454860809d2ae473a2a12	\\x000000010000000140318b5e448fb4ec9b1ab82dd49b56c81ce9b4b56c2899d7e53cbadfd7b383153b109e02bca7c98136a1ac0f915be66c9404c688bb40f1256a82a0ddd52072818caec1ee3225976fb5b2b975693911be2b875db74685e8b7b9ad79692ec0fb62ba0282761896c95158d664afb31389293fd04b97b7944aa797601a99be84bfbc	\\x0000000100010000
8	1	7	\\xd286cb1dfc3f5fca5e06d6e98df4c8ab1e35c9d2e021a759cd9ae2de705787166fd8b06a997d12ee2b3e9dd0a7922ec9dc8f3a81c2850b5aca2ea6e24de20d0f	354	\\x0000000100000100d6b44d76b3d06884c4cec0eda9386e1e766217096d097a352dc65458ba1f7c1bebce63170cbac0f0683ab34d58154361daaf667b845bee9414c9328c55dea0cd21e920822a8441328b56f9e2a5092f519f694fd7abeca218aadfb260ca3306717c61badf4bb24f40f49eb6c350dbad4bb72445cfb22791d528bde34f7abe99fc	\\xcafbc820a646bb90c7886d745ae10ac0d3fe2eede68740ff88032ab5dc9a01b05c5d1a0c36e6ac53f653bcf8d42dec938950d4dc2a1c4d2a7a9c1a14b2ce7d14	\\x0000000100000001b5d3b7759702770feb25fdcd432e960baba965db5bd99e2093920eab2e8ef2de5c86925606e1e0d5201888a76ebf6ff015031ade3bb8ae7422a1caa4de37cef7629c512b1ca5e6c526f372b6d7281dcc6c1f2baf4c8251255a73dd4ede1d291ea7654242084ebb79aadef38f39e631f8be6fb8369914b34150041e7c5e299b75	\\x0000000100010000
9	1	8	\\xa57d9556e6557e455275a1656df154f60ba27eb6f52acd6e2e0cbaab03493e225b5bcc8643578446d7e28a0b2cdfdcceaebce81e0ec29530e070501608100801	354	\\x0000000100000100c027c8ca64db049ea9a128b6a50925f873a4130115481222664a44e45752cc9a69414cff740904f92af4bf806c5bec3eaf839eec39ba2252b0f296213d29e02413c8328fb23003223a40e4d50de83c1710f9a0141e12a79e51669967eb97c5390e151b2c5429db83b70889610bf776309ab98e5128cf0d25d9ded7f1cb559e8f	\\x3a2124902c646a18f0bddd16abad9839b6b39e71666390e19e12c029584e0f05e36059c7de496b4e0ae868a9e4f3c17729748c5f5ec009b6c15b40237081aa14	\\x000000010000000174264cbf38e0f54ca2a452c1a89f2c811d28e82b99a4ae3754b729abbf088a8059c9c522348c5d983a46140b53def9774e6e67f72a478adf42e02652e1c0cde73306d596023246872f5fc8e71239d56246bdf02fdcaf33637f33a011f24221b541e9dc6fe459cf29b8d91ea8807f594b90b670e817e9a73727a7eb2d50474471	\\x0000000100010000
10	1	9	\\x4aadfb294575a41f31b02c5ae12a4d6fd85655e4d2ce7b4263ea1f02546b272c386991fa74b6a869a48caf4b6acddaec94369fc9d9f6b0fae80dfd5e0013ad0b	114	\\x0000000100000100318c27336289fcff5e8e11a66efca0a2d1a051313a929d2c093aa05d2891277b275d4701fe39f4fcca6af8f5aa930cab21b75e25d85c33126aa4c8dd4a2ad695162c03e9dd7fcdbf9cb47910bbba4eff3e548ee45f968d6827f0065f71d2744c134097aa5e1f85083f05048fb5375124e15013d05d3add52f110455068a520d4	\\x57a9bd847001855e6b05ee29296b7b1d060f00ed110d0b23e3bc7af619291d63d64f6af6d8b2e861e39fe213a3f55daa19255d5c60fc591a028147a547bc2183	\\x0000000100000001c67eea1f146175c0ae0411117566ab0228b6f456f45658ed055933e32831efba8f4634298920c02ce3ec20097e9b5764fe15432d22d37513d9a41893546b338e5bbfd88b6152822b4312b4adec3cd198cdae417943625abe9046bb121c610498ea7076dba0468f95a962cd0a81541aebe2012d1efffeacae6e126c19142a84f6	\\x0000000100010000
11	1	10	\\xca21a48e35fd0dceaa90fc3fb85d520a3047a5ebce9cca920babaa6f2ebef41f7c68dccda725abab82a9f152dc33a2051e0107f045550c7b3b7018cbc44ff80a	114	\\x00000001000001008caed27c2f234c632b523525e87d5283425db59b84b14b8eee0104e4f1b9c3f94f5b158e2a9835a713bdb6b6160380480cc19c78846e38f59f1c50b545ae807627da27f13017d4e9dfc58ecbe6a8db57511a93ced72eb09f1e2b066bb61619c10049844d5d2c83fde9e21424b30d0916ebd72c23f35ee780c7bd66994cf4a05b	\\xe1c8793971cf8f5de99e0f4e93992a42399d951f31fca5bcddc923f58c3520a860870b8b61f610206905313eea8dc6e0b8efa31fcd8c5fffe562e38e8f4207a1	\\x000000010000000125f62dd7d85d1fbecb68c6d54a6ffc4cf4d6a3ad2995fc803b5b0accd38bdbfb23fe72bf24ffa451f93041c419bc66364e19f8632daaf84f165087c73d2de6074916275ea0f43a7efac7e6a8eadfe845246c9f66d5cf2c6c34880c4c3b9f29a4d860efb99bdc26bdfe3afeffe00fd9e0fcb961ab56e4afa5570cfe42bb3e3080	\\x0000000100010000
12	1	11	\\x465a261c8db63494f316c1fe388173ae4b24172641521208dab1938bc89dc3d16551c1944d3e438debc7eee84fe802b0e1d30914652b515e1bd678fd6649fa04	114	\\x00000001000001009538c853eb8d75f767fddafc6d218dca3b2c6e8ad66548ffbfd6a806a1aa1aa690cc330e43c94af57159d055bccc0d9ce2d3fce96b297c8dfe2985758b8df8941765ca4f81a19c1ecbe7503a9238899442132b83be8416fa95727e66b97471cc60c53fb87cc694982866d10d5af00a5a82bc44d791e91ff1e90b232f96f5a3e8	\\x13d3423ac78bf096f9939a5ffd19fa0c2c5e02176cfd0986b3df0cf561897c441626da9ed4a0ff02a29dc1427f6f9b4e0aa02fb5656a8c3e4d8618fe8a8d719b	\\x000000010000000103e224252a26882e6aa6d44317bc17283ebb43a6b63bd1814de741df118c76c47cb33e5bd38f9da94d6e8779ccca247505156dbba6b365923ead69e5ea940711e19df9c5f45149dbe78028d95ccd36a6a658b5e7079634eb56c0c0a19101e2b215390dd9db9cee1a6f7b499924b2de3344c6b0cb8477e40350c119c80802d286	\\x0000000100010000
13	2	0	\\x693e2840e97562d444e13771e50a40a1ac4bfa48eb4cca00694fb776f740e1e59ea612ccc5d30140eb33f6e394eaf498f60805a7be8f4ecaf8d7faa6c9e29b09	114	\\x00000001000001005f437543607537a0ada085294e5ae3d62f0291d1acc276eb71d13b3b12fcbae03dc30867c581fe2a7ac117ce493c16ddaa9352e6d927188e43e602e5b2551a7436b6b29339f63a7807a57c85502af6254d13f00793708f77efbd54c893ad5fed08d4ba78210bd0c04ec74f740041f43ddecbac919cd17a01aed0e44d008902a5	\\x881ac03bc07cca4e8aa37ddcefac837d349b49adf70e7c91aa7828216905403dfbe0e16d8fd6ebc4533674c1cec4ee9e326118ab0cd7285eba4ea702a22f5439	\\x0000000100000001357d5b591480c7440aa209c91c958b4a6ea9f53a85235067805a110dba3b79a7615ecfb7d1a7247ff55a8f0f6e6dbb681133eb45e11137ce9bb55179f397330a4d5fe2358935deb425b081f2f1dc236770f69deef68f4ddca2d100d764a4324e61e393ca03f5042fa70f636fa4551aec0826851f7f162919571ac2efb89f47bd	\\x0000000100010000
14	2	1	\\x18866e0e80595f9748073a87cdb89aec0337e72654c00a199cd32f234d330b77b52024ada1724a9fcb3f19de154c1aaa2856e9675b05250010015d910f9b2e0f	114	\\x000000010000010027d03fc703753610aacc3e44c98176280b5ff75eef144179e8ba52d437daf0405b25ad8a7f5e549ad8968c2adf93f91507c75e1d6957487321e30a424f1a1dce80906e799095955f76aba2cdd628cab020da7bb46f09c30970774f93d7f6d02592d1ac9d3bce504b5532746c6b6d850e434430ad8a3475d9a04a41df8df78aaa	\\x9716a7b413d3f210aceeb18bf754a5fdd062a7db168eca3360517480f4ca81e45f15be8e2fa60f4b9fec5954e680bb7d2cb2981322e98c5164267cdc8f53378c	\\x00000001000000018183b59d9f0534e913ba602d424d6b8cba899b480b6b6ece1bef4409b0dfa8bfc89bfdb8e00d0fe3bb52ae7a0d76d9ca570995c4139050dd21ece37731f8e9004f1404f6c7de2970d121f9b957d818b43d49f5a67f3230f868cab1d538b6c29200bf5fb15ad3f8fd57f0d551d57ac6a48a3c79d953b7489aaf8876321afd9ba9	\\x0000000100010000
15	2	2	\\x70e194652ca6954b09b9a16dae82c60d384c663d06674d2473cf79f0180fd9d12a78ea3523b6ec1c5a3c0b5a6ccbcbc351f81904eb8ac1f0840cf1a7712c270f	114	\\x0000000100000100866e9d2f073786d42e84a0dfcb83122a19773dddea9563494453eb70243141eba6ff27bc48060764338a51779deaa6e1a06c632b686d5cd391b8f23519e9e69957dc1b928772b76deed84f5a44f7a34535e7891cf9411f53fc2e9d85a5f37b442f5f618552b9c584d05857e0fb6ab3161d50e8d332ce83f2ebba3be0315f440f	\\xdfe2df8e3f2aa9a080e745d0d32af2672efdb893a84665d1896175a0d66bc53d4be6ab84ae5321bf403a9b89447a16bab438a449c5e56739c231231632a30a52	\\x0000000100000001a34640fd3afeea9ecce2529e77d921646be7df11c78e5ca1a1e4f27066b8e920e8910bb4cab57b671eb5f2d26e5ce859577b410c84c6d9eeee6fa495d9f8f6b6bd31d54695f285138c76e2447ee8694ddfa4609dbed5e05862e9c69284b9629fa6d5df328400ed602f91d648b3f9bd129f96dd6eba44add8fe6d2080da073be7	\\x0000000100010000
16	2	3	\\xb99de1ca445b750b369628a6007392eaa7637d35fd75caa724d8055cd0e6c7cdfff0d92052c3b021e22ac1c8ce3f243606f46bbca873edefbf322cadcc6b200b	114	\\x0000000100000100b452b49dd0b3489681084ed4dc853b55b2d2ae4731d3034f7abcb4ae91e7e61c83086f58e8ab77d48520d56c7688e5803aaa5d85adeab3ffa543ed2dc8dc702abac9798a088a861ae620fa51d1044b6970cccfff649836736b1054ae1cb4abe14fbe613c51abc2cc6ce845d0035ed3b1412aac019792826f26b1661edb72b33f	\\x2f0c66407ffaae6fae781c38421f915700c9b9a02a0cfbe96100fcf9c01803864ea870797750d4e27141d57b0914dab40aa3c7706e74a2e32ad9d39fd6e28f34	\\x000000010000000104119ec7ff2f098bf3ff87b8ecc7e5f8c4109db70c3ba08ede6d0c229366c144efc9152a68ed472b052b078cf0c55dcc822712ee364056822be7d0a0c9f4fdf88931b98e61bcd699989fa65820f7317857c8ec9c2c6583303022f1186e96acd57932bd4bfc043943db5056c0cf3678d1e220d71c46a7a6efe07ed49b79b39172	\\x0000000100010000
17	2	4	\\x26e538a6b5a0b2187fec64e7354a978e3f2388ef6e8947f5c3a8d764607ef6c847f666a89652f0945fd7f4a34c98fdd049d94e1e7f6a27885bf672e3c129cf03	114	\\x000000010000010056906a42d7b771050c3383928c6a660673facebd151ccdc381a3e21102ba059ecb6c5a7f9021ae3ad3a127d7d0db0f7ed40b1689f3bcb9ba5686745ba64710ec9fc67653ff51db9810bbf32842f8ec863f25eb27761847e3d4d0866049464483cecf31971667a156e89d97fe135f6c2b9643fe58c8392a52b485d64ebeac89dd	\\x53dcba640450e2ea21f100f073d549e0886856f6efd8f9c5524a6263d642eac522a43bc8b4974505c261f120223a5328253baf3f4c39a18eb6d01aca223da94f	\\x0000000100000001328485b7ae2635c4570bb0a6e27516fee1bfb84ba3cd9c0d634c2396d63ce52cbf56fa61d635e95a39aa247cd18dbd8e3922b56a4d136a6f2506034863fa9bee6aad71a1d7568a9b399c3ab39aeb3c83b7471d197edc0c27c5177006c5893e784996c3536f0baaf9e6bd38304556dba7592c0ee4ab2125d29bf158ee34218f47	\\x0000000100010000
18	2	5	\\xd68fa6b7f2fa2b902910d73d36c694ba52daf69601adb72baa0d9c92cf1c111b920f998e852fd3e88fddc2ccf9a1ecbb52a6dcc9cc2d2ff93850a44680b0cd04	114	\\x0000000100000100bc6e43ae895a5860f86e8cafa2591edb9b29a088314cb8798c917731e9d9d2388ba664ed854f600f586b95018b4ab59781a368d5ce16ac652ebf856e5ecaf5559972b76958f59e86f7b40cf72dafd5187d3dcd40bca14850067928ab9c66070a8694176e09dbe5a4f7a039d221fc4ca3198c4a294c3e425dd4565cfc09bd8004	\\xbe5e5cf9921fc23893361aca987e71bbfcf541f4ab904ab7f0a52ca53da8f929c6df95c9aeb8b59dd986e5a60027d1b0626cb997030be344ce1ec38740b02238	\\x0000000100000001bc5a297bc8ee24ac7dcfd4d71cb769ed5a5ff51873448487d07ad385aeb4b18f7877f7065ad7c8d9803d8c44c8edc2b009cb8011306e9ee9a9104df72eb0cdcb9d069f87972269ca6ad142a41e8f707c0dac95b1c3e7c0c1bbd764c532d57f78f69227ce6e9d1a83399f7ca8268b5d2b95ce63c57e8b5bd60a2ddb8d76b1bf0a	\\x0000000100010000
19	2	6	\\x418b214127b549e3d245e43cb9d73a314969fcaedd0ec639de62b1fda5b2e74bbbaff97c34727df032114e5457a99cae755a453da04534f369d78329bf11bc0a	114	\\x00000001000001009863d11361cb572fc8ce35c4d5710df3e2bd852fed4fefd1261788b57e24406ddf4d23ac1bc9275713899b3786bb6a234bf7f03823df6f3e137ad5eca167dec897513454579cc8f8c700919c38af5cf4bc935ab5aa13a8111a4bc288ed31ab41010ca9ccf83c4f33535379f0f1bb5880663ca1cf80d8821441af340b3dbffb32	\\x3ad6fbeca38ac86c9bba32d61fc1216ba72cf6ecf5beb53b2b186f013117266a2519d85f3a87237bf15e2009f99268c304c1e37ad095c8b427c009e9e9a4ffc4	\\x00000001000000015f67801ac347b5eaf9574da5a9e26c9d5aadc05d661fabf0f0597ba27bb7b3ad5d874e813d17d9a5df7953f3d73e31f964fcf8b62bcb8c4cf4275d314c65c938919a01c90a07b7ac131e32c861b3aeeb193a9687b1b3b2ed20b2f13e3919737ad42b2529c509b9d119223c31f0857e65f81d6ae41b235980dd0ce971c83d5e6e	\\x0000000100010000
20	2	7	\\xd16e0e68a30f46dbc89ad108eb95e0d13db46117c73592283ec6a5ebfb1fbbb2ff91994417e4439811b2c6b6bdbf185b4972ab5cf8ef88b07efbe932bd834104	114	\\x00000001000001009201ee36587c7088d161fc79217b2b4229367eadc9550c3f2efe67de0856d2be3890e25889bb8c804fcd161cb0f0abc4e4e9285f34f8112ab45f5021c262afdc6da2c39b2a51de94305a586a1dc93e1df4ab3265d58d1b34fb96dc0d9cdf88f357789f3c4367e81a66d37a4a1f95b536ab0fb9fe210de4c44a93fa059842b1ee	\\x41f6e8b3b9881ab164bf3594620c4db6745c52bd81fc4dd3ec6ff1aed6504ee19942c10bc52882ecdb9eaf06e34fc855bfe6f3cc6be467e92c5fb0691870e934	\\x00000001000000013f58f933ee31a459348282148d3ebe60e860c839d133fa701104b211da8d602654f3c6f4d7d4009b1573e5c1a1eb9fa862d054d75115d08a90e79f5108f2361d2f4410948bea9ed496f96fe0d460c73a80b8e6bee21b475e75ea031dd98094c0032b66934e7eb00113628b9a97b1f58cd15b4c205c9e052a386328351be3aaa0	\\x0000000100010000
21	2	8	\\x219ac4f6e2bac230d1cbd4ddb75c731c8efa05f27d60260085d933e45e09848ff4eff7f52eceab05e534240eb229edb0c8ffdc907cca92c348440a877ebdb005	114	\\x00000001000001001847d72b117152067df20b650976c751d277f675385a13eaae8752aede55487c8c70938509bd81d66ac8afe05d7ac67aab05973a13a375f4f45fc60e61aef153ed02ddf607f6335a94424ce3a7d0d9264f309fd405fc9d78d9e6aee9705eeca7b5880a863b09dd05a5bcaf98a1167f744b0636946d341ae4bda2e5bd750b7681	\\x9ccc61e27ea462c240d19b83f6e3cdb29ac8ff41e453e7f9b6cb64e53d07eb0e62571b29aef80ec5d305e9fdc9a1ab66502339f33a719bbada46d8a32498cd53	\\x00000001000000015b45ee308d30b24e62d7dd2b180e2039cf74954690d01448c68bdc296a36677f4918760eb9f79cc9614ce40bb89c06f2414f87985377e2daa818d736b9b5b0a1dda65fa37b5e580ab8cbe1ef0a8f57d5c730055dc106674e23a3d262db9264d1caee0b14bd0011d8b2cb049f785faec5a3cb4cfbe47251734be29f004650e138	\\x0000000100010000
22	2	9	\\x57a15e68293a21681cdb8ccd0b56a8f53ea4d26550c93796e456a38de0111709f76bc7b5682f67c15f1264e40c367bb18969f32904bfdda96d9750bddc632c0c	114	\\x000000010000010058bb0fa65a4ff7e38a704c232e5422d7d5719913284cebd43b09477e83a147bb7f6d8b689d051237fcb8551150dd03e864c614eef93d2e4baf859495b4c4e3d6e30781ed21a710e4c8e6105ac0c7bdb1abf704654afcbca481788d7d70503707a6ea76ad31d197757b3a8cc1e98c1bec4ea5785c0efcd9aad1f8933ba0527ed9	\\x2ebc7ea6bfff21bfe9c99fd79c461fd7aa07dd1e6ddf42dab1ce15ef79a8377bd0eedea455997e8c28830a5f6f14186ad9cf206865f6f1fe7cb3116335f84b8b	\\x0000000100000001b383b178a7ebcc2b95c104ae5b8d7c3927685cf72ddba52ee66a1345578ddfde0d9729edb345f5d37470c0bc0731d87fa7d8f65c2c9a2bf446a009e0533385e9a891bc264cec69017e8c14443cc70b542205f9cbca7d7765dd73362ef10869f9767e20c5377c89dc06318d372d39c59113b2e94216e459f254a6bc4f30bbf44d	\\x0000000100010000
23	2	10	\\x039de5790a788cd4c69f01530c6c9b8f52ffa18d7f224d0557e2cc26bff817e7cd419e874e1a3656b031d53a1929ce2772226cf516fc34ebadbd91bbb7ca080a	114	\\x000000010000010053446b730c469c2060f8343cd071729079d29563692276c03d55a1875580ea8963c06557cbb9a6a62aea1268f0e69e1ffd664af9ad0a1694c2bcc4020a5520513d0320d166bef52e393c78292935abc4ff32eea9061b4781466bdc31404c47c5e650d8fd9536b6df4746668b28852991a7d4f0a4b3a0016bc09fa70eb70ae553	\\x930db16ef9448aec639d73bdba0c00f446bd249fa94a72a1537d49fb8d7971b1e29550307003898e54c2d715f03bb6b4848596b6026432354eef36b28a3b47df	\\x0000000100000001680fe59db25a9f5c50c3b96b3fb04462edb38dd8420ea728caa3f5992b8f5f3c89c2eb6a9a3c5037e317baa0c7dccb631a2aef7d46a49a63db2423f4689b088f43c873811737d1f5ec8fc3b5bbad5ae525e0af58b1bc2e4fcc17617a9d6404f1df3da371a923d2c369503dbfa21771e579cb91dfd371c99e3ef829625beeb667	\\x0000000100010000
24	2	11	\\xf665bafa8c8911b2cd572fae1e13c2e597859acb5137f792694e6a92bc28956f08e3c317203b3f315d5161b7839043616f8a58340ffd0816e828bc78bd4ef607	114	\\x00000001000001000525b2d266dd8d686f99ff130af450ae7e119d9a622a9c7404d5c889d1958808fe2224f83ac8ea0545bcf40cfb3eaa512c5a70f017d4541a5cffadf5acc6f304b22872046583641ef73dcbf558f3dd1016505595290bf58cd1e08a3121f19a811edcda01948e0b2835d6e13e3b88ad834062e70ffd161cc144497338ae565a5d	\\x426012f62b02999a8f1679946ade9fcc3617986b1f3d496514c2f697dc7d425575e2f06af6da8049d3919cb7b20f44ebd0a558b61dcbe06cfac78b50dbbad2bd	\\x000000010000000182a6e8a1d839d5a841a7ef9cc02fb4ef1da8496557afcf2e7dbe3b8d53a3e9c552f26c68cf11f0a11a395de53598adb18670d987023b6505a9152d2f10a32da64705d11621a67a012c72a6d720239703403fbd60a7ec9cfc0ef69d94f35f5bf6c7d36aa7a5b5b3c1460f2fe488501c4e57925fb6541afe09e64c3313ba2d131c	\\x0000000100010000
25	2	12	\\xb8c9de4795df0eed4907823fb7004f0cd75774843353e5077b1953e9a7974f3dc3ae749db6c8bb45ca7f227ba56fcc7ced4404b3017a054b0a391887dc202505	114	\\x0000000100000100a19b634104430bd06fd39977c1315e977bc155aa4c5cd79d97629a6b0ceebdd32eb61ca240bf3205dd16fe7d145beb43a3ea6c00877521c25a08a5dd56d2616b40f1e36a332ce07f2e643ab207210c38004b1e7041595e2f5f52338fb9b31beb23b6683ec2b62abcfe50c9545d4f4b4573c490de1fdcb4ffb7089f7704292f7d	\\x987be26dd7774617dc3e579d84d4fb11bddc2f5d43ad0eebea11c0333c736df34d085bd4845d3d15edd2857b4e3b8862e2687ebd15f722da6207f9ddc7a63725	\\x0000000100000001b5201a8c97e2274ed1cacda39344ec1483fc9a16d4ec4bcc28cfe24974f4ad39dd5f3bac2dd0e06b76880d22bca87b3e93affc48be977e5b67d06dc6da816ebf47a0cf153e883b1f5d1c9023e6e92c87350ba036ac9393160e9e98d98599576c494514c3e7a6c0bdeeede76e0ee1800eb3bf346ae3e3510c2153358b3d34436c	\\x0000000100010000
26	2	13	\\x23f154fe5dd62dba01f66b24aaea2ad06038ca982bec5114965060923576b5ec4dc1a9e2824aa60b0ea9699155755e45ec2e8980c0cd02a60e1f986fdbc4c005	114	\\x0000000100000100756d45cb3fc39069e3260ae11abeca36f1387f3a09d25d3c0654c12ce8bee0c89619a6a9e7f3fe3847946231556c0591cc0fdbdabc0b7a7349d3064c687d4b39393baa1d6964476c34ae0a1adc97dd6636a272173d744282a7213a5df68bf4647b1703a893e0b2a2c9a61938f83c97fde1a988ac8b6dd8d810eeddff52f37076	\\x9ccc271a0de1a3c6114c963fb08d8143366b886732e0f7333777313b19fd3fd38f6116fe18e6ea316b3439105f4b5db2639fb8f37ccda3ec09c8928301ed7a19	\\x00000001000000013c43feb4c15fc1ea9c3b17f3296aa05ee640326d70f0b9c3ba378e5c053861058a92c3f0f1aa515992aca0b400f9b49ae2999bc39e5bc1e2df7a02f0cc180b452a4b13bf42a8890ae99460c53c17a487e11245296c3c6c244a943ab5209d6f04ec24547e86dcd8bfcf87311e7780727d0a4ca46bee4beb95c69df7f6473838ee	\\x0000000100010000
27	2	14	\\x280c3053819c92144952371e210d0d923f01009571a01bb445a2b43b17728a70262793dc21114933d1dfeff8ce09cefd8a23c8df1c4002dbeafe9633cd6a720f	114	\\x0000000100000100b47fe606778614e23d41ba63dac577be6dd674676edcff6e8c71b7fa41338da9925d58e3ff7cfc54c33a5326a4e9f5aa41b5e3f4b1da45c8f993670fa194f89469fdd449ae97d10dbfd3be026db14332d55a7237cdbcdec8d4e0bb0d7f9918334f0c3304116e427325325d7ce00950f3da6d740d418c861786cb58ae7ad4e5bf	\\x7597e40f77f7d73ea06cb606e8d295b2cbce5dd4de9a4ebf0f1d660cbfb6e03495c566bde7cbd8cc0c57fd94b42df85dc3081db3b01721f52de801038b8ad6d5	\\x0000000100000001c95a2176e6e60726751e746720e338592341f8da78d2d680c1891f38ec22a5867c72589ee68cf725f63871789ebc499202a1954f7b89123a9bc926aa3f43492a3c8f2ce9359934196fc603c0e4aec2e814a7c4550b2a6fd660ddf27310b00db6cee44c7e1fd4b87292237583d9b5d2f06bcacfef8406ad319d915a2376228fa5	\\x0000000100010000
28	2	15	\\x8a7389841343b195065e42311da801ae180083a669c178fe001b62b1c44dfb55e80d5903c37fc9efbd104b803734e500cded92379a80825d21876a0d3127dd00	114	\\x00000001000001003e90068f75aa804f328ba4371d20e5d83b7cbcb42066b586ecfcb985d1eeb2c4353e4fb04b978803fcbf1c67c989d6fcf7544bf08d033537d2c097f691dce8cff7adc8d3a686d7ac2a8c2bfd3e447ed52e61aff52aa906c885feee094cb43a0c5bcc83f478d11bd645b677ce929ba0bc1f01fa3c4d9fd1a3d7f51ae09a8fb6e6	\\xf815453743c73896b7cd854deb7a7144cd8edb9ffa79c18afbe12f7f946fe5f91b4316beb6ccffd012a3c7f9b8b2b9c31ef7f1e8bb3420046706358e7afdd74b	\\x00000001000000017011ede2fe4e5ac0a0062201e76c7b2ae2454219aa3517c1efa8192dd6155013690ea80b1274f6d5a07a09d3ccd7aafb1754058c5671ec3523949b37173f5bd48559a088eb57494a3788270c0de5a38eae45229886a5307ba7a3cac84f6f881c6c047ad9f057c36c09e62adc7555e48817ed5aa2e5930d86b130ead62529b189	\\x0000000100010000
29	2	16	\\x7e07017a5156dc9bfa78b2926c3d4642cc95f62ff5a89de910bc0a191358caf5613309e34d6584f2e155bb460987583c53ab453f67a9e2d6492e0df4b351f50c	114	\\x00000001000001007fb47f61c167b811d2ed85aa41cbf1bfb9c8bde6010938f9434087ca2d926f550694ab1fb0f042892d82fd9d5716385e5a31cc741d526dfcc2b237040d8ce683300cb8e3ccbcb4a4cd59c15293a63c3c6afc8f7e0834adbe2022e515daf2ab01acccfd671dba836eb74bd93b1092938067c19c4b2e5fa6f2ed988b4af5ed3839	\\xd4fd462120972df6047ca9ba08f1b17f322ab3e1124a8d5bfbc9e6680b112946aa671b96556ab41b44f999924d21ee5d6f7613f51882fa51c94392fb55df24df	\\x00000001000000017d25af0acd1f25887e428e80edbd87d27166bcd5aa0f969be8f97edf6fc2d7b0eed101c90b40e737fa7b9332265f0b062b4b9ac9b8e2880faa3dc0380630d8de4e8aa51d7bfc366dd6c66c912cd47a19ac51a5af480344a7b7e3f36cd50be4d11036ad0a63bfdc5a49ed0e8d51880cbe0e04d9339aeafcddb19a1fd66a1f0f89	\\x0000000100010000
30	2	17	\\xa9063f963b5e3d857fd4ad0ca561bbb1786438c3caa4793a68c9e6235fbecd5cedf3a35d45425e46de3213294378e3539c83c57c292af1e78a7253a447a2420f	114	\\x000000010000010064148f8d32ec06f279d5a49ea688168d416ed47bf96c7b20b099c2147dda66260d9e160e4ee3c7964f69aba1dee0642bf37c4a18cb785744f097adef367836d679941b7773e4d7e5aabcd24a54fca826614eb5aff82990e016bddc79c160d011af632c50a29ebb3bd191829f508b20acc7d837e2090663a23f9ec4fb6283c998	\\xb6e4018bb7ebdc4f931596954179be4b70c97b3ad4ba95c19b5da329b973424479d46b416c9b5c8d45fa536d7a5fd9f9d002c7aead612f7928c909c89f846039	\\x0000000100000001666f2bcec6d1d8918af9015b5cd0cf377d6e3ef2d9a23690aa7114e818443efe0d02723eec215eacf7de9031a8d93d8365d658538673d603604513b4c927a279c21bd4285c411df871b4b5e4366f3b81913f6a5eaf3698f0406086dd1e685b7c24b22aae99ede369f969ff2df527e893eef103515d2a85cef1790b86dd88c945	\\x0000000100010000
31	2	18	\\x6ddcc1f50c0cd2d9d7710fe3be614865f7badb65f02eb1515fd3b530b3ca8d0e5e8d2ab2a9a12e5ca3b2970c976e3ccf667654e76811b8a6bb7ec1d3e1fcce00	114	\\x000000010000010084b346ba95b7bf6c6c2ccbc73a7e9b1e489db1b162d5be90622bad1b53eb730307bc64eeae3641aeccf705c17f118a9a2dd889d7c3584a8cffacc6b8659fa01c0ee3f66f2e9cbb2f8a9f84a704068568b3907cde4e92907c72fbfa43d22799f279f3160509e41b0ccbb693bce3f9dde952aa8bc256a437e2efb7fcb65cdb7194	\\xf59e6a1b3dd3d37059cb753043231dbd5cf86c03d589a5d9a3e30632ec7c1e4e1ac171cd78939e47ace7a1c56d4257890ae5991553b581a4de18ee613cb1dab3	\\x00000001000000012693b5fae4e93ac4faf79472ed1e9a4c1fd9171afb9e8ce5db49598678bfe5364818c97befba0af9e4379e37460338201e6912475f5b941d0e2b26ac4604743db0dd8c77c6d275198f169c11d92ebda458d634b0ce233c8dd884993e2ae33859d9e1fc51f47596fd0e6e3bc7541cab7e713d1e5ce9b52958a3a2003740638961	\\x0000000100010000
32	2	19	\\x4036b46d5a248a75184f6cb7fcd5af88d2cccd0e0049289dc6418ee5d97298c959df91272763ebb2ff3d0b64bae6f8993fea8ba9f8c377067b3fe689a24f6902	114	\\x0000000100000100408913429b475bbda05c4ec5289cbdce8f3c48683005ca41971677e23b308ae7ab5c5bce1671d62b3bba7757acdcaeab566bcdfd2175da6a1147d372a1f84f9250a0ddfc4621a8d1c486f1503858f5a52a92d050c85286d25d93f1162a5cd15de5bf0b5698f83cc73250a26ef1df37841a15d5bb9b70c869308e4945451efc1d	\\xa8ec150278d66a61e1254881d45500c232353977fc506e26c3f2a46b274a460e1473462e18db90ef3096a12f54ac0bafd56d5e2fd559f1b8cd0f3c4ea49b3cc0	\\x0000000100000001c904c66da5c8ab4488439f76abd7a1f8a323545810cfff7cc48dedf8210778c8d52b93f35d333f9568ec76f9fc697cabdd8700d89514289eb8777d38256dfa514c94572a1e18a59fff24ea5216b4683fe1faa76c4d06d912352e2eb5a4576eb6a86f9bc3131684b7bba0ed5c387bec80d38c690c80e95ed8e20bcdd9eef54d84	\\x0000000100010000
33	2	20	\\xe7ccbbc5e2365b82f4529b2019ee010c8cf9e45b441c8e5fddfd5589ad2dbcb775a7eb0a7458bb9d981c8f01872e13fc321577090a4a602a2852a6fddc97d801	114	\\x000000010000010052e2797e4ff8fcad74617043fd758a0983186db2f39731ca80f10dff87a046867b50ebd95824304611c8a2c3bad476c282fb2cddbe9d52801d2016cadbf3f84102396c8ea15cce58b7fa35890f8bd37d2ddb5a885e539a15d7b51c49dafbbfd524d556316b1c70766d6ada5ff4e26679db7e639161d8a8187d2f9f91dd56b1d6	\\xc5b97f5979e264676f6706202bc72eaee7fb165e1f2040e7b9b78faedf6b13720ae925e3c6820f71fbc9e702c0b8df0d28ac917e3ebefff5f4a71f23e430f3a5	\\x00000001000000017eb432abf3f082fe72f77a20733f5dc0c359b4f72eb19734aaa2ce68e88627c564d27614c6a11e9b8a9c4c452e112e088061e8a15db2f4834eabcf913f47180b40885749ebf0d3a85a8f0d1df1ba1226c3c82c9d910a14ec2b4f7659b86d426a6c4f3f4175daa5e9e17006ec9533f3ddd05d4aaf57fb0dc27ded1b89f0be9a50	\\x0000000100010000
34	2	21	\\x9e23caa8399bb9aef88b598855dcca53ebd26306912887c2d4c0a628be52b0209bcabbbe501dd751e72b64b908aa6ad143f93f5d85840d0c7b2d5f14afb4d505	114	\\x0000000100000100ac5e4347c486cd0392de67c09471c1923d31b3d2a91292264857717a514b5fcbc9e5679885d9bd7b767a5cf0b5bd794f36cbaaeaee5761914bc77529b2975916e875de1e3fd11447e5da1a7fbef60cd72e0e2ddd036e120cb26a8f145c0d77f87f120a6e2df576ee13652786e6d272b3c2a79be73e07040b6f6e8966da830206	\\x50139152b01bf2babb16fad47b6b85875266e0e3dd78647bcedf9e5cf00f58ec70fb107efaeeb620d4f5068d2330785cc2a72e689c77b6594992444fe706742b	\\x00000001000000013c7bc7cfa7abead34f2e830a7b2a056833a9bd0b0402800f37aabf5c7623b7f3175d456e85cff393da537912a105021b2274816be9ae3c5038e383c9c208bc47dc071a658e7ee0cb3f4d4049b1f978da63cb07941743126385088bfac9e11789cb4e168a38c94246ab691ddebcba59177b9209371f0ea9628bf45cc42e549e1d	\\x0000000100010000
35	2	22	\\xdf7c368dd68db288645e177e82255d561e23d5bd4c519e01f53883990774e7529a563cf7aa5e2727b7703f25e70fbb85dba8668ded4ed24292c8f00be7c8c203	114	\\x000000010000010073cd6fe0221ddd73c9c007e2172f323386fbd9144b5535638ba64fb277cf62965cf967a33ed10e8c7ae21daeacc60ed758bb0aedf4dee709c2e4c5e4aaa6553de4762f47d3ca4894bcb28ab7acfb400c4df34c881dc61556cd84c9605cdd400cb4ae16bf83c93d7282a596bfad9136de869a2df8480d74644224be68514c0328	\\x52a8535cc5385fae57c000252dd6356105424173bc4523f71afbe0917d259baa40384a1fe5274b49730e37f92a64a52ffa5cfcc5101864f416725eac5c55cd45	\\x0000000100000001c2ff2039c1be28fdc7c4851305b084498e9a2c9d27318d71f74198812facd1efab7e4f3cb71ae82c306fe83ff11d52caae9e1d541a250d95a992bca01ac405e24e0a990959ec41f828df123158a7533ef8ead46055cece2cd8db16f71efb67d78266b8b705a010a736f8addaa9885cee09fe94bc14c99058c2bad20c751c3288	\\x0000000100010000
36	2	23	\\xd9945cd58926796eb2a067d5fbf37aa17064e89b763c839c07e1a8d21d4bf3e87b2396f0ab270a729995324b381641a2a6f649815f7449a20da3d5ada9440a00	114	\\x0000000100000100634453bc1a097249baed6ab33b0276f45875cded43eaad34c3951a731cf0aa27d54d12a3c460ffcf33f5f0a5f6979fe117847d5b11bf3e5d381cb3df39d2485a126a535ec7568f0a4416e5a289b466ca52931379b975b3fa7215dfcdb588af7d912c30d2397302121dfbae5f7c19ebb04256abbb003d3050653476504e08130c	\\x2ae75d3617653db5867faa98c60286ef23df174b3b3769f7fc3943c611b4980ef3232e03f2e08440677d5ed09e48efd28d98cd4b5a84615a541366ae25b2c9d2	\\x0000000100000001b3076e4b65f837160acbf0e833b5bd15891495088599d4487be8f8b66f89ff20faad1277b299d8ae163e2d708588e62a46888ae896ff2a958600aba47ba01f8a57b81f9f4dcb20f43ceefbe27560bc4735bcb840f578cb3fa6c686a268e194bcc70ea343c21d8a5ede646f18c27a418820743444efaeca4787f606ce9c993f5d	\\x0000000100010000
37	2	24	\\x84122b3ac2ac86ad73601aba748557d3e727ff6c1447243ff5655d52e3c28b7350d65cd4ebed85d46755027d245adc41d6ad93682578a7eedcf8508bacf87509	114	\\x000000010000010080cf63a50e7c63db98fba47c553c4ea8b843b1b7b41bb1e59d09c0c661d8690ab7cba9eb04331a03af76021b1dcf53531410f43d1d255f856abe1af53ff43ab27e18fceeafaba4c09e02be286945e8b189735fe60978674a5631805e30b4daa181eee0f2e599ffea1dd3fc44d21b0173d03bd0bedd3c6813c74813c7d7abab40	\\x09b120858bc0d0baafeb2d6b8b7ef59238781c7ef7bd06a919d27f80377a2ef8645147c459bc328aef264eba5ad55f69a27b9a2089270debe550eb4041230b9c	\\x000000010000000176820afad0a7cc0df6211753feddfbeb47f9d11e87bb654ab34367f0eeff89933a0ff4414512a270fa11235b7624d9551720c092f5af1aaea01a5eb6d148553d462cf61635f0bd6532006829eb2e8362fbb5428fa39ddf107bab0e36bebb3c9ecec55c4e04408cbe8e4a89553071442b11886928e3cbda4bb65311211cd4f558	\\x0000000100010000
38	2	25	\\xff0f06fe4c61c3c6b0d0e5b7369c8edbe24b18f3ba33f335904597398c9074c339dc377370d394d15e7b2bb13fe6045ff030f22d9fffe5ea381e85780537a600	114	\\x000000010000010008241dac9a80b7d0ba79563f278a773e174959649073e4710c67ef1b912654085df943d51bb7f9e5fe1e4ef4d2dec0eb49b0a9cb0a414709f3b8458a8e2ae7f87e933b4688ad983aa05ae4af5c7dcfa2dc7770d6f67aa8493f375dd30f3d5ec980ac6bfd40234b79877ea66aed39365d98f3ff0396492a951dbb70db876542e8	\\x502876c9d6b5242b446bdbba86fc465fa9be095104cf045be703103c80873c28b08625a50964884c9af7ffb880b4f9ee7eee99a8f4a0dde7a4dce6f239845ab4	\\x000000010000000196b9f143b415c1ab4f67797b55ced4cd20975ac9572f0af5e15b9b1df235d164a29e5cb1f268e77fcdb08dbb3eb4547974487f7aa24e006dc1039c9864676aa375b5b95dee2991ad6b4c31e300cb1575c09e4f69bced96bbc9df9b2d0d91be1de0935cd791b4d0d23271011a5280caa7033c77a5d1b737d1f9070428c40a7ccd	\\x0000000100010000
39	2	26	\\x3d1a41e32b50badda1fb3267d95de5af57209c44cd6637ebc1558ad248e47879de0669503336ff8cbeb64b0d10e9a87561016f8a4d84cc8d9667b5754fcfc904	114	\\x0000000100000100aa5e77d0816fcec75f29466b50020aa96081d34110d227f2de6e9182870d89afa8bfa7f0afaa54cd8301a9daa9bfb04ab3f17fc7c1a96ec03b6693182ce20e95f2fe4aff1c0556b329071a48fd0421e58467bb7dea877155338773f7444bfcce8495ec6c06f480e9f3063d24eba52f047e4cb8de4060e4c11ab85d6cd2eab930	\\xb0638b96b0c35799787a08826cccd88007c81a13221ed63dc21a28c87fd71c4bd5cfc0cca38a3294eb939a1c133b83775c96b19353ead82536fe9db7a44b0ddb	\\x000000010000000129085169dd7f4cb4036ad7b5f664752a8c5878c3c496507b35eabf67c993ed584a3313f2b4400a0ce1bbd37a4034bd272d20e1e7c1e3af09b26dedd9d60c86ca0d9ace33eeca0f94e6761972893456a61c5e7b9444ff7f39171100227f06c6eab666aca3d2b11d105ead31e02726aca70f259665993f0bac33620cfc58a8e622	\\x0000000100010000
40	2	27	\\xe13872649c847d4ea1f12d86f8c1490ddf77c2950c7022f1e5a09bbf0ece831bf5fa1f9cd9df604ff95a33ba0e968958128b0459af9479e9e00889c245058704	114	\\x0000000100000100b896f9447ab50401d6dbb4eef21ee040b060682bcf32eb1338dbd2e4d5fbf49d44188b82200fb82f5b0451c2b8dee8258a88bbf6cc81333bebca63aad3d29312b8a308594da9643367972c96f2771dca9f204039d7338c43ac07dc261b28553ac4285cc5aea6ac483397dc530ddff41ef754c02165d9e7c567ce0133592d669d	\\x64dc6c1c5dad6a43eef38689e852e0f8d6af84f167f891e1b1518135ef0a2d908bb1bb2981646032c7bd561e35ee657bcd7e4747a58651236d5afa8470573eee	\\x00000001000000016f403ecef700154507aa97c1c6b0f8892c6c8269733d9920a85260739ae79f6491fff892f77148ebe4d0171a28ed607894533546e307294afe3b172ada12c23f04c61d56df272a99805893d3fcde20dc95da8083c1c2c77db9ebfaacc9b88530d1a63d466b88d105ea80d59479eec3f81b721d2b1db8719f6c37b7bacf6f540e	\\x0000000100010000
41	2	28	\\xc41df1c88d08721135cc0cc8c1759b61b60fd917e316bba9cd9e17c12c152e83f79934bb0f4bbdc86604d7b7ee0a1e0d2515bbcc9995bda9ceb0649109819c03	114	\\x0000000100000100a482899fc15a02d6d6be1120a80ebcef5818bccce07c9f78cc66e7fe9beb8d85762764721106f4e1ae734dbd95fae8755a3e5909b1adcffc53542e37b9d4967ac0d114c4809912ba78329f89abb707e08dc42b635a56648ba4b161e9687af0ff0f289d33dd6710d1cd0a70aca402b7ccbf613d5c80146a9c5589691cf8caffa1	\\xb38a54702e75cd83454fce130475dfc120f1e54a937640d1be4aea0af37482e7cad279c5dfdff6e23ec6c0bbe9f7f16c81e9117cc5ed3b55e6c03a477783a8ac	\\x0000000100000001452fa53b3a9e665839acadb6dc5ebd2f09f674ffa83cafbc46f3d69da5348996148e2c56f1f6e5d8d90be23e3f970cf538aa1ddb278e655b3af87310f61cdf3c1998f5d1cf09f709c63154cefc6d99a2cbbec681e9da46359d03a7b8b4c45750bdafb950ab6f257e9cf4c56b01f88efef6a742856b196e04c1af25a0936ec801	\\x0000000100010000
42	2	29	\\x99d03feb87197ea3b54b4ee868bc3710e5cecfaf51797658c8e5a16dc51475a74fa38d09877295d577a56d0293c3851df7907ed7886233f74bd5f83d373d2603	114	\\x00000001000001003e06ae7da8339c377556eece53c9251bc55f47af2a60807e529470698659b9c69d5aacb3685531658de199a1d7bb8fe62ef95af6fb31d490710617a20854710ac1aae46b46d28096ccc22bb7d1f805ce025b3031db0988551e2816700e8f801d4103e9ad1b2301e123a6b4820c0a482e1fddd09e080d5dd4becc6f74d79f4554	\\xd2a8d63a1ed974eab01f2de45ceb71786d9a51ae2cffc652c9f65ac9beaa51eb1b1f7b43fa26e870becf8b9a8f3e96df8ad695840e7fe0ffd248cf2a82bcb7d6	\\x000000010000000138b6e8caa687364d30c8c693c1841863721c9a1fe18134a47eba56ef7509a4eaaff4bc8b230bb8f9dc25c12f89baf5660d4d17a2607fb4429aee0f237b4094819ddf118eca40361ef0c00681fde784ea1ecfc00b001be85348e382537240c3f32a0f47a6fb75f9a01887d96180b57ab58a2dfc29ab9e44b10062e16d8ddb5032	\\x0000000100010000
43	2	30	\\x3d63eaa89c68dc8b6a5ceb72a2645bfa9d19b3c09e37b649d9f6a82d43b634db1dada9561cd63470817ebd19ec661522defb903c1ffcbf837bcac74cc670cb00	114	\\x000000010000010014acfd34c4c09d86a60d1156db88df09f0ee6b04833f24a38c07f824aec794143759d1505e7f77315e3cc82d7051f85335f2e4c60984c2f0062f56346716ebc605da8822e0746b7a9d896beaf522663636a093a65b7ac4a5b6d93c7159ecceba57f57ea1612f52026d5bb05ffd7d2c8698cd036880cfc0d13bf3717fdc8f79b4	\\xd8c89d84a1253fe2e9f76708245c818d6c806d9c9e2e4e24535b9c073cd5a8ce06c4cfc17c547cccc6a47c5439647fde18d0dea5f0de27f7154c13f37123abf8	\\x00000001000000011362b5aaa9830a4559998dd0fa284bef900ec5b7a9a47f3d5d72122d7c16c5a825b579b7ca6e979f61f5349b15074544d5b4e3ad3fab48cb4e597c79f89b7044ce42b019d1aada4fc96711c88a6df079cd438b9da26b46bac5e746b64fa8a8c5777f55586a69b30b4a5705730426177269abc73a4020a948c1e15eb1fefa33e3	\\x0000000100010000
44	2	31	\\x52e449cc7d6ec6ba33166e8ecd8f446368114c566325c1c79787a5017156f8f49676d2427c3fafafc8805d8ff6ba161b758711fe66236d76ceb455e64a882c02	114	\\x000000010000010015cc7453cf0a45097dd00be16aca662cd47f3ec9168f066f10d411cc1d8a5d30e68dad63cfb340d29b514e422f626eb73ff1020ceeddc27da64ef44b5397226ca8462f707aeaa2bd38fdfd10ce447bee1c744a9ca57a3d6c152ff21db7571290473fa713bdb43363d0bc01267bd5e01867e3d6f92dffb126c569cef9ab7e4303	\\xef56330ec5d875a64b07183db06eb69f26a24f8550578f987328b35977b64947eec78fed2eb6aedc42d77cf964b145b2a1494dcb2cbd57141bf2a6b671d4b4b9	\\x0000000100000001ab1dc5ce1006937de3abd36d3935f394f2f6bb33def785ba11ab4e6428c78734fff1d4f8d4a955ac5d3c7a7e6628c46a1bc2d42f02745547744d6e432ebf5d27405337dc1b8cbfabfb22fcb7aee3bf352dc48d4500fc25c658bb00c30dd18ad63f8583f9646c9b1f1d8162d43b489101c776c92acc885c713c6a1e75427f920f	\\x0000000100010000
45	2	32	\\x4d66f7ef1d384e3ed19e1e3f6af053d25aa071030ef4b147d0d2cfbb62d978f2549ad4cb123d1a05dd93a31d4ddc23d1bfe5cb7e5bc604b56169bffb5af2a50b	114	\\x00000001000001000dbcdcc34529532bbb0341dabd1a35c1a65ade9411019a9fefa7d8bfb3472a1c305a4cc933b49ff438ba2ba771b0703263b52e92005baf4c685bae1cec7989476174f29e10d4721bb20c71e1bade07d1d72f371bf7e6184e2586c0848611546ee8c650705464e6adc5db7bec1c81a6b211752bab6489add9d97480143c5459b2	\\x6b4cef985cc010d994a31886efdef163b46bb5f45d6c906db6c9fa187a2d64d1cfcba786aeae9bdf34f602611357269560ff9e330790e6ea018047c463aa7750	\\x00000001000000014a3f85ecb5f41e9c5b95b306b2d3220fca17691f0a6eb3d0760af7bce2ce72046a9ea159d2dcaafc39a778ab9d1058d5049ab9a198783d2b778d1d48cec3f3b8f59bbccf6b25378bd88f6f9329b62135e824f9138231cdb4548a181a09760a18198fbec39ebd201455be6080208fa6daee2fa8c613b191ca284c1f50a59db71e	\\x0000000100010000
46	2	33	\\x7cc0bc4156eb39bb8fc8284858ccec9ba2e2afa28f38e3c2dad214b7d3304b35f0176bf8a8f798cc4f6c311984c94ccef5215eb6bf891ad6e0710a3c738b7f07	114	\\x0000000100000100b8a132f40a92efeba778d8fb6e1f53f0089b350c0f781ed65ef161a8fbf25c658568fac789a0c88e2ce1c4df9051b61c2e8dff948f65e79303eb430f32387ac063b5195f1e1e6e7f763e1496e97f9a7197ed846f31274903acf097487c8006ab63ed3853cfc2b71bc90b4746bcb749e27f523b1666c03c7e0adcb88f90e2d41d	\\x20897f6615f0217a7210e519ed4e0d548a2dab16d9dd855e4eb741520de90e43bfb4fa77cd3464dd7e77036009220afd76d1429d029ab6f47f6df515dc8fadc9	\\x0000000100000001311e8c5795af05a26b8091514b98a14e70c6ff6c5b36bcbaf65b0633d781d7cadf0bc9f66063cb319e5b530bacc452ce39de5c6f056b5f0268b6646aac425164fcdb0af883efd937bf11add714f901cbd30b3aa5da810cf514bba226600a3b52c9fcfd0bbad97239de540e0953b77d676dbb6c6ba0d8c0c644485815dc6396a0	\\x0000000100010000
47	2	34	\\x795bfd7ed0838c3fb75353948fe713d4a8f995ac571fc38b7b982e5f52a6591a6058e3a6aadbfa5fcfce85be8f19703e0cd56e9cd3275ebb1e8bede3cc9a130a	114	\\x0000000100000100bb2a3daaa6ca7b4cb8782f15686eb156beaf7a6ee70885da77e3d23989270959d27332d93f5c3e86000d314ca1d7733feba7fb0d7002fa5bd4e43ba26c46a327a08635aaa874519a752855e41e5f13a43bad97767428193c4c8258107545c493da946b733663805e8984b1f784c5829afb14a7285b1caa8b6ecf553174ba06b0	\\x47cb578a28f04ba749377c670735f8e0a20bccd93353fb78339851af5a7191064a68df93a7f62f3bcb0515c6a82c594ab96335862131a79dd192464974152850	\\x0000000100000001242361bbe084e92fc94697aff1450189349396ba1b6839243a2e8fadc7b5ed3fa0ce033ae6d0b9889fffdff4b25eee8eefdf0021f998a0f9232599bfcdbee736ba8c141858896bd3b7d5a3b82a2a6a29af2b108637704cbb9aa656bcad8de50dcb472a7626442e201cdeaf46823ee681d9f3256549489b478f6320c17f311647	\\x0000000100010000
48	2	35	\\x02f8019157d8c45490983b83b5e71a2c9e01bfbb2ac4328fa7d90ff508b0eea9586a7ac6e3db51c11a2dc160eecb32b319e14cf5f554e799ee0a5e4ae0e12804	114	\\x00000001000001004078270b7fcef3d562d8089501b1e99e51c2e7c5cbf84b837f75f4c2fc85f0efbdc920750f6262f6e1752f73c72dab5827e6bee02336e6c77f51938af0f4cf9ccc6f36f841859bf190e89fa2516c0ac46017bffdf1064788caf873e34c3096af08bdede1479bf2389e92db147a1136b23e685671c271f5375b07e783b7b05250	\\xda5f0a6c4ac224eeb77e1c977805124dd5691eb4c92601e89bc086e64c66d30463b50a819e56000095dfcc92a0bead49409a87b996f765b7c5e087c94bf92d49	\\x0000000100000001be7f2b15f7f2db6e95b941ecb9fae2a0eefc22dd09cd09543aae9716431cdeaefc585a65e19431cbdb3b4bae1084f82965dbf95a7ff60344963063ea165533a662407eda1ee90b1ff846e56aaf235422bd9c51bf11fd95190cda213b3a48f6d4ec025f10e2565d9c0776b1a736eaa9d6c06a3c5c6bd2e145f6051e1bb46e59b6	\\x0000000100010000
49	2	36	\\x74f65ee7fe687fda3378db033a170c2de61c9c1a644b178a9b1a08ff0062c9d70cefef5eba9254d695272d85b4cd41dfe79a9b7d3e2571faea1e48b50e989d01	114	\\x0000000100000100a53f9efa24436df504c161b17f423ec274919c451afc4d395378993e1a908951a153b32335428b8a5bd6cc8ad96c22dddaf0ba92177175d73490ebc90c2667c6dedcac6ece860ed01343540b57d259747b46024eacdf1097ccd6540365a7a8277e20f931f08ce44ff69223cb6749a9385ffd86d2df8bf90128f8a63c1bc55453	\\x89152630831f55edc32458b6290eff3e46059762c8877e16e42ced1cab7498372486dcdcc0724ff6cc3f50f7fb6778d8de5e5c121bc1e970f995089007a41659	\\x00000001000000014d19e9feaf1d01075bfff18d9b302cfa1317704f11c392c5e8dcaacdc86c59bbfc30bd45188adf3177625fc343aad58bbff37f8d4a9fa08ccd69eeaf645d6edfc9eac7b9a3053fe9ebe70de0781e32a8fa7d97901ec03698883caf02374bfb772412b85d5b3e984b197f565afd0c12f1fb2de2c4864db98432feb610ef0d89b3	\\x0000000100010000
50	2	37	\\x07b861fc5ef991df4461638c83227a6d79279810b3720e3efbe753522b244fd2b35ed9c0203bdf314d0a6c3ca77eed73b75f8faacc003cfad66ff3a6674a9f02	114	\\x00000001000001001e1404cd263c3eaa7a8b846f2850491a9646dc3608058c8356fc2749b451c18ed3cff51b3b0ba8626cb98ba76f0928c76c8e7a8fb75d1dce5983a9a1f148afd3e8b0b0904dc346f23fcb3c64877827694bd823074d2b7801a9d2563767745dbf8498f0ea7a6be21bd3188b498472e2707218a4ed295b7c47dedc218305ff70cd	\\xc9e4a4a5865ddcd6bded02935a03ec9543ef2b5a37fd24185e9978728bdb80fffb031b1924feacc07d73fec85723fba76c53b8861fcf7b84e237114a0fdbb798	\\x00000001000000018987c3320a976807cf65df23c8890dd916c2d9f85a7f5e7787c10260810e198d66c6a14a034b739c5b135537a902438f8ad01aa92072fb06b12e9515a01876559325320861f6c77312081a9142038ca0d5cb37deed17323b72f8e8009ae14acc5a7e9d1a3624f116b1c85a4de08c0ca0a2d242224c32a7e566e02982de50c553	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x004408ac6803fb9ae28c6b6288566943284e2c779e3dca643e9069f6369cde6a	\\x0e2e6f75627b3bc0317a0ec1c555b33b95f57fe4042ee24bfb2a20b7e9a9c15f95535db6c369e3974fffd3f87698ed935b3007744a8b0f856a44c21c46459983
2	2	\\x14741c9bd1ed3b1027df7e5901e0619baba308b02dfd92085ed82b49d7985d13	\\xea416f2a73d954ec6ab5f2ee20ef87aacab37f3d3d43eefdd4746e920861a8399d37c26158a531bb23baa3f52bd83929e0aa1ff72837a8742ca283a9b36be8fb
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
1	\\xa51202293391714b0cd5f76e4dac871353efd7e16055350852137e5f5c4b7011	0	0	0	0	f	f	120	1662236759000000	1880569561000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xa51202293391714b0cd5f76e4dac871353efd7e16055350852137e5f5c4b7011	1	8	0	\\xe952c93506bfadc5b8afed63d7f3bd11642d56b8bb655554efb7893c47374e9f	exchange-account-1	1659817546000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x769ff7cdea038ff95be76e97d87833c4b4b707e14cdb46bce6e2aac38d160eeb929c578ad68f364943a6bf51b3c63cfa11ac186562e03c56bb645dce7d44e66c
1	\\x33d9ececd8c86881048c101a3337a01995c01ccefb58970931916137b4ad46890d20c854fea5cad1c229b24ec9f21a9636a7c3229f1af31aaa0e34b2fdd9d869
1	\\x756b13c8205e0870d9427d55bddacdc3c52b0e352d2eace393f02e78bde8d34935e2bb1ca8a36ad62c5922cc14da855cb98dd8ad43f915996952bbecf71be475
1	\\x0e993a949a7c5c859207bed349f717e95a670eb682d207cd53d77a595df116b99a10eac7d89d1859b73030709ee1a09079e5102289b7a183fa035c758d42d19a
1	\\x01e2303cbb601ada3d486a885fef5e3f42dfd01f31cbb536bee70c9aaae3f550bbcfb8d656132cbb0149fcad769a7b431358e80873e8575f25bbd0d3238d8500
1	\\x6cf4079b8f514bcaa5532c29c0aa345ba1625078dff95cf9bfbf10c597273d421750ad8b198caf7f9c20cb10f1ec4331af1fbeaa78423e57ec0899b9c7b87338
1	\\xe74900c4b6911163986c7f6f3924de83b402169f56814bbbe83491f87466fecb20fdb9420c8eb19c2a4501c497a8a830976da0890485dc433b6c732c7283399b
1	\\x1fb98bf9322b0a0cbad97d1735d0f55ffcd90c10f1878b213309905c3babde0e1e4e755369234db1465ffddef9f0fe03c426d56a3437845ef8fa21ce19dceb42
1	\\x633c2642a104399048860ca5a45874350f94a9e3141f3be462de87c3c1e76ecc5728f7fb41bc2ddc679fdfa0a9e51aa1564dfdfbbe681fa9387ad74e15b03fcb
1	\\x0e859292995081d85eb374200b16547fa50fd842714f94a851c641fe01e104664fd952cf2fbe5944289b81180f72fbafbf406271a97caa389246d80398e9ef68
1	\\x927fd1da41f3272b2d0de7a5ea3732371f72c2d1952046b4f354d661921bf63c3285248c35e4a5482295a78c74aee729c38884a9ef4039c72448f96ea78c0fb9
1	\\x8f222d27d7194354cef06ae032fb13b295984638ba70045c575763e137b277614db465a99846b65802624625b7fcdf8d99cc9ec07195312fe5913c01e8d752c9
1	\\x1f95f6f1955ea55b6f5925093b78591f5283e343acc1cac8dd481952e97f4a18bae27a03e22c552a0f51b8b409301816fe30ffb800055968d01385fd8a3e314c
1	\\xcbf623f60589ad6c471eaec817bca5308aff25f1a9013003c804eab8668d210462e7edfd69347b400a0cda542aa12ea536118da933853ccf4cec5d9516ec73cc
1	\\xcfb5d8ccb68dbc2772189009e23a2113797f10783812cf77fe19eff8931d62d05098cc0d475fe188c6fb352ce13fee356b58e381fd20a36d08826be169a3962d
1	\\xaf4d0f72783deb198b8d6887c7fb5246f5d7d7c469de57a57c2ab948880dd7f284f90374766b76e116a03b2f2074e30e0225eb1252a4e8b2f03dca0194f39a90
1	\\x61ec7ecf00e075591f43864b3cc797937322568371b8ff18f9133d3c12653db677e9c954694a36c0c14abf82aa6a1bc6bf547626f382dc824f31760b6f862890
1	\\x32fba2fc05c26c731d16bced1ee35168d3709968acbf994ba94704d00b1e2ac2f1307f0bc3c85b519c2718a3f5c11087c729da43c54121c3b13ebf741514702c
1	\\x2365ebffbfdae5771b4270829db053d9dae4ea69718401c4329c38a47179eb57b3ec2150da414417b411f8e31641ecb83c9682f9337b294076f3904087f593b8
1	\\xd398f728d1418f1399a84902229c3a5b0560478a818718c99cedbf0d5e060f90fe85e8c370e94c8a4c3415f14d9de664b608d3e2bebfabeebfc2c3b9fb79f932
1	\\xff41e7f44d98c3b9984aef76d08f02b9c9fad7114ec12f5b42a7de7506bb65181cc6d312b28f08b6dc47e523aa74bd488ab165e89a1aa3d2c8b0e5c056cf8860
1	\\x372bed265448a9ddd414ae30b3fcee202c3fce13187f70e19b5248db1dcdb3d612c121c91df326a2aa69e0b7a071d08d7266ec1c8fcb14ec737fbe9a8b8378d8
1	\\xd14f763cdc40ca3a04f141a99df052851f7b8742bf764beb5c37b4cead253b2f9aac63a6cb4fde902618096690f35cb58101acac177d906e388b840bf82247ac
1	\\x9ab003467bd0cf9befc40a4285424d4437fcc4ee615df125d8e654dfb68c460eb18d4bcf7e522ea86ba7f49dbd9d4a27ddc25885c8d01fcb0ba3ec4e52f51a01
1	\\x33ded8e286d4bb4634ae3c422f41257bb7ed233c17fdd80e2392711fd661f3739e37ff82d0983c307249bbff847808dc9f25cf82a14d48db28fb55ddf816cc91
1	\\x485969dbcad29cbad1d7db1ec056e1a9c1f4505d8370f170a9daef261810339ae2ea776899090c2b51c31dc3590d762bc47390504ee6903601d167bf64641550
1	\\x3e39bf49f644e8ecc79dfaaaf800ae7cc4c658c08deea24bbb1c15359e2f27d084e7e626532c6ca7999b6ee937708be1a2c22cd98bcaa8b455b3e2ae1099bc60
1	\\x8f76db71b9d3f7ffe9fc02480dc3cf848a40fcebb56faa5c4b895157b120eca95966fb4f027cd413514e1a78653db323fd7fd4fdae5ca088724637fc93553158
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x769ff7cdea038ff95be76e97d87833c4b4b707e14cdb46bce6e2aac38d160eeb929c578ad68f364943a6bf51b3c63cfa11ac186562e03c56bb645dce7d44e66c	76	\\x00000001000000011669709dd6f1929218968ec32e1eeb2a473626701c42ef828799dbd0e2a5f5da7d5cf62a2b7cd6c182d25499021e80a7f47ec36167508a41c18ddcc6d2e3ecf17d8865b66ac5d0a0b2a796c68516cc07e37d533288224e7d53ee3a57dcb838fcb75bbe61e822108388e9f2479c1dc239e6956959e5fd807895d72bf301494bd3	1	\\x643db1db45c1cf772a8503c78f7885aa5c21d398528a401225311f2f2dba7b546e07e4e76c5f33050a086f8d1ec9f2d2b5fe5d48289d4fec56c1cc82fab8fe00	1659817549000000	5	1000000
2	\\x33d9ececd8c86881048c101a3337a01995c01ccefb58970931916137b4ad46890d20c854fea5cad1c229b24ec9f21a9636a7c3229f1af31aaa0e34b2fdd9d869	295	\\x0000000100000001104b42bdc2dc35008f7642917277b95ef8e3d5d979f76bf398afbaf6fb895de58de0f0fbc9c3dba12112a90302a7d92c2c615b121bd14d35330ee635f63cad411957dbf371eecb776dfcf6e9d37b19f406a97d7a895cb8f7e4f6a6dea8922d106d2822151fde028688510d17b0f0d97f9eb3ba0ca5568820b0b46aecfd556b95	1	\\x9b7a0a785ccd0f4306529ccc162cbdba118198f15fad73dca462b966550691d290e1a4ea2cb2f9403790d7f1053924fbcb335ba09d6917feb91cd50d51400605	1659817549000000	2	3000000
3	\\x756b13c8205e0870d9427d55bddacdc3c52b0e352d2eace393f02e78bde8d34935e2bb1ca8a36ad62c5922cc14da855cb98dd8ad43f915996952bbecf71be475	226	\\x00000001000000019a58acbb94e9496e088fd5b24ae590d219a27248c9e2b571268e19694c5fa4cf21d8d09a8c2012e884c0abb924dec6095a8689a8daa8d3a70a4cb449ce68d7642fbb226a5844dad46ddecea69152ee4f8350a39eb92f6751e804f40524d00a66958254fa34c672c3507a8599683d1aba16dbbc4f1dd474c94553c3b7a43a962f	1	\\x6c3ba5328cff5f3d6b2071e71943404b59b2dad3be4383f89a8f45dd2a1fb5c2ff01097c86bb8807bff4ddea33e9a76767a5d1bb68de6c18fd60f1b5e21f700f	1659817549000000	0	11000000
4	\\x0e993a949a7c5c859207bed349f717e95a670eb682d207cd53d77a595df116b99a10eac7d89d1859b73030709ee1a09079e5102289b7a183fa035c758d42d19a	226	\\x000000010000000128df6bf9beb2e4d735e26c96f56de01ff5ad26628d046c5bb054cccdc61705204247f6516e5862ecbb378e8d462783a9859d43bfd74442f988c9b89feff0248f87baaab7164a5d33951d9073f883febb57ff79bc475d737a169d3e0259b7d2dfc1568323342966aaae3d013d58e46e824b399cc1ebc488045dbcd922b927f22d	1	\\x90263bd9ffebfbbda38a31f18135c3dcfacfb6add3c8103e941a827596e6350aae3250b67c3826d29e20640017303aa24fd2d67a81f278954f0cb68979fe000d	1659817549000000	0	11000000
5	\\x01e2303cbb601ada3d486a885fef5e3f42dfd01f31cbb536bee70c9aaae3f550bbcfb8d656132cbb0149fcad769a7b431358e80873e8575f25bbd0d3238d8500	226	\\x000000010000000145b37e4692cd33e7bed568917a8a44a2a684fcde24a99de747e6c4afc074b7879ec6ea484df4282a3b4a8af242ea012941f9818f26ba54d04a5cb759372f10f6726c5650a2144efb8db35216196644be9171ed2b3f1c986daf51fc41ae6de37f30322f6cd6ff1cce2a94c702471847f335c2b66f9e77be3f3d3c0dd225a97259	1	\\xe968d7e7ba61ad426d53d24f3bba4a1ebb3fef1853ef2441bdab4c001f4d3f7351df8dfc12c32ef534fb489a8f5ceac55bf6b4edfe02049fbb3d10d12bd1360f	1659817549000000	0	11000000
6	\\x6cf4079b8f514bcaa5532c29c0aa345ba1625078dff95cf9bfbf10c597273d421750ad8b198caf7f9c20cb10f1ec4331af1fbeaa78423e57ec0899b9c7b87338	226	\\x0000000100000001139946fb92f635651ec1dd418329b7ff32fa36b64b51fbd6a88b3f45405c9d5cc17ac2010f25b5f1b1c61eef14b95ebeb1ca8addbccd9233f7b47caa0aa9a49539104924b25edde8c56e6ff7be33801fc7fba3b69ba0928c8f72e4e2914adf76f1a95cd82b99f39a6a593f7531c6e28a9a8dfc1ba0db84a34a72ad57ac7a6413	1	\\x082790cb4308aca0114c34774d183d493a865a70e192d8afc5dec5a40766d0e7dc8f661f441a4359ec37e1a49f8ef184bf2d1eeac4bf1c44a9b3861cf810520d	1659817549000000	0	11000000
7	\\xe74900c4b6911163986c7f6f3924de83b402169f56814bbbe83491f87466fecb20fdb9420c8eb19c2a4501c497a8a830976da0890485dc433b6c732c7283399b	226	\\x000000010000000143ee795f16996ff0e86fa75098ca3a9ddd7430d2806ea3b87e3b33bde3cd6f01ca902ffc998a298e7a2671a18ccc8c30bcc3fe1504a49d60ad71291e741499cf20f137a88eff4d607be84fac5dd03fc220db5a7e87ad052d75aba25a765c2f6ef2323555233a09cd1e606e725e8a49c4bcfa4b2d3273144bdd3d5f8186070687	1	\\x9090b779bea88f397420cc8611daff463bf11d046447e220319900f793f7aab9d8c9aec293a055f315f2965ad96410f94d689966d5e857c36e2a40b65cce1406	1659817549000000	0	11000000
8	\\x1fb98bf9322b0a0cbad97d1735d0f55ffcd90c10f1878b213309905c3babde0e1e4e755369234db1465ffddef9f0fe03c426d56a3437845ef8fa21ce19dceb42	226	\\x00000001000000015115e1bd4e62a01421babeb3f8928666388b06b0b7d2f824d7bee084c91429a289379b91ac441eb839b1bcbf8b8978b596697aba19d55b22f1d581c739beeb61a2fd63e91ae715b6fe43f3066f8467705d643f00dcd5761304616e96f4ffbc4c4676fb7ae7776bc95d589fc7beae24bb7bf5dad4efec2036fc4432fc8b8bd2d7	1	\\xc4d0218e10e65b2b3a74286111b4e0255cb5db23c9d9f95bdc4c2c1f3ac86695fe54341145d71253215ed91709952cd88fd0e3b187e5c11e03a5b8bcd7662f0d	1659817549000000	0	11000000
9	\\x633c2642a104399048860ca5a45874350f94a9e3141f3be462de87c3c1e76ecc5728f7fb41bc2ddc679fdfa0a9e51aa1564dfdfbbe681fa9387ad74e15b03fcb	226	\\x0000000100000001a202fd1c9d00b96e6d32e8440050b2f494b1d03233afecf9c8a7b80373630d319b0c70c1157dd3967dd06075b736c1357baa55d5189ca4ce909dfffefe3b5cc26ab147bfb992d8f51dc07d655b9d47c888fa83edbcc248b3f8b34defa6c6b1fe104e72ee7827bc5f9a61e2bb9ea3ef07b21ecfcb8b33b90e846cc0a275ec8135	1	\\x5411c564493260ed4f6ca7065261c296ad3b3e09cf1472963bd76a0bee93e9162a5096823e19173db3840462a14ef2cf62e326cbdd10e1762b0833cb1a71500a	1659817549000000	0	11000000
10	\\x0e859292995081d85eb374200b16547fa50fd842714f94a851c641fe01e104664fd952cf2fbe5944289b81180f72fbafbf406271a97caa389246d80398e9ef68	226	\\x00000001000000013c4954364cbbeda40c42a7981373422f7653443d3e08856206885f39bd7777ea3d7b0849dd4d0ace18f26a5f434222f7c06030eb1a6a8c1bd3c1e99bd38fec6a7d3a8ce8fabcf25c8893fb72772cf3e7533d9125f044b1c5e27fb2ff03fa5a831ae41934248096797e867f327825f9f4f848763d3f5270ad16e39fb2c2039bd1	1	\\x2692d6d2e28cffccc7bdfaf2323773e428372886541e67ab59d5dfd0ecb241962eacd9827289f8d229bd9ff62a1f9e8937ab01c1c67fc699315dfbd7b8a0d909	1659817549000000	0	11000000
11	\\x927fd1da41f3272b2d0de7a5ea3732371f72c2d1952046b4f354d661921bf63c3285248c35e4a5482295a78c74aee729c38884a9ef4039c72448f96ea78c0fb9	262	\\x00000001000000015d0b976a498707c1655017087afc4081c7bd9936c81cfdcc19a9ae64993746dec38bd6d256cfbb99f4a283298626c59b6f63b576807fadbcd1c3063bb0e0467472b5a0f90e3cd7894da03e0954c2bec9cfc6a0754abb9ac38643f9ef679ee835021e6bf8ae848a9dd6233af16dd6a87c1ad3d5c45b47ddfde176a8d2ba39e08b	1	\\xe7a3765fc949a868b2f6c61c289b4e3b35f3c7c148a040ecb7a58613e12817587d1aceb28ff8c71b64ee7cb9bc6ec167d75bf341035d09faea96ca4b3543990e	1659817549000000	0	2000000
12	\\x8f222d27d7194354cef06ae032fb13b295984638ba70045c575763e137b277614db465a99846b65802624625b7fcdf8d99cc9ec07195312fe5913c01e8d752c9	262	\\x0000000100000001610cd728ee2ef7742531da92ef1e011f5fef70492b58cb02df5bff464428ee9e86810d1f52d7504e862a6be0c587e5446252d1f2d4c5c8c35f670c90a138d8c686cc9a8eac947d6b74d5bb186f076410be8053e99299e45965ca392f9b791daa4e917bc0a8995913b183417ba8b2e1baa02bf52ff9db67df44804378deaeb426	1	\\x6a794b3da216b942d0ec86011b17ce35457a97c3c01ec91d0607608aca2183a4fe00a2ff624cbd50efdb13cd3c9d40cfbafb5195e51f7d2cbddc2cb6a15f550c	1659817549000000	0	2000000
13	\\x1f95f6f1955ea55b6f5925093b78591f5283e343acc1cac8dd481952e97f4a18bae27a03e22c552a0f51b8b409301816fe30ffb800055968d01385fd8a3e314c	262	\\x00000001000000015f54b232a76ab0fb9cec49551705124fce6a691a334679b392e80aab7b345c1a86cfb325557fe8b84cdec55350ca01abeea88a5fbbb453d36d26d2c9ede9c3d100f9d7cf28f8802b0b34bc019acbb3f486e588e1530b10422a6072d81a3e41d28803a033cb14d2dfd40bb00a775fb6a1985175a466a944d69f8b76afcb460f76	1	\\x51b8096b4b03b10ae8593123da15d25ea57e6223666b209090e319a8fbcea2f5868cb959c483a60cc37b03d7c69752441a102b9625a5d4a53c86366a708be40d	1659817549000000	0	2000000
14	\\xcbf623f60589ad6c471eaec817bca5308aff25f1a9013003c804eab8668d210462e7edfd69347b400a0cda542aa12ea536118da933853ccf4cec5d9516ec73cc	262	\\x00000001000000012c2cd325e77990d06fc1d8f5dae258da445e862836ffae055b690dd09adef7922fdb0d06d922391b14a8655ba5d1b1e739013f4b26aa13b1c69af3839cc42e4029a3741ed7164bde6a35680e876529dbc12231a1b7390195f6a4da29ca9e1feca5c4092d78df720b73cc0a187a414ab3404940267c3cd87970be7e840ee14028	1	\\xe4905f532e28b3238ce11dbaf55fd56d87e9af319574c4e78231b6753570f713f0ccab15d0b2fd80650fcaca868c6d3a80c43b8bde69165ff0ce5f5ee424f804	1659817549000000	0	2000000
15	\\xcfb5d8ccb68dbc2772189009e23a2113797f10783812cf77fe19eff8931d62d05098cc0d475fe188c6fb352ce13fee356b58e381fd20a36d08826be169a3962d	186	\\x000000010000000157963c4fd26e0289b3fe0269dd4a426215dc8ba9b6a1799a9ea2aba8aa18a128b1c84d9d4a80e12d8e34a9aeaaf35abe6cc83a15f06b79d06963810ed18b711dc80aefa5e955eee8f4472e128e21b041ce93f6d914c54ee0bade457d96534f4cae06776848614b01cdc2af43cabeecd2c43cf71b184cb657ba8c405c8c6cb6ce	1	\\x441c83d84f6fe0ea7dab10092bd00e6a127d7c16e9f201dea78d178fa2415cc54a0520d41dbd06247443c7e2352b94d1ff355bef0eda8a74edfb8e3c5635ed0a	1659817560000000	1	2000000
16	\\xaf4d0f72783deb198b8d6887c7fb5246f5d7d7c469de57a57c2ab948880dd7f284f90374766b76e116a03b2f2074e30e0225eb1252a4e8b2f03dca0194f39a90	226	\\x000000010000000186b598a86dc25dfbe2407833b99fac6cd76e5cda2ff89665a212037e90f6b8bcf61dd002258a31ad746940508fd4af913f521651691be5848e5964d76c015f63f6263ef4d325e3b56249f8b36e8bd52c495a44e0bfa67dd1b49896ee21792d358ec0d9c2331d9bf465ac51ade214afdd3948f90998253ef8c9487e54541b9b5b	1	\\xfb19309b5dc5ed6bd73b655529fef833f15ca7d8c4b1b7d5e19019d46745b6725819781477b53d1da28f4eebd2a3445ece54755c315b85e8f43905a7102bb305	1659817560000000	0	11000000
17	\\x61ec7ecf00e075591f43864b3cc797937322568371b8ff18f9133d3c12653db677e9c954694a36c0c14abf82aa6a1bc6bf547626f382dc824f31760b6f862890	226	\\x000000010000000172ee2d453b0b272c565949fe49f76f51e12cd7f517239eb1937df6216326f05f077289f8427d5a03ca704a193c204ff4bddef0cd1eb9a060268a139705b72e60b2407047d091f2fdb2513f33ac88d22f706d5f5a9d16ed55020bc697ab8f20ba71c2f4566f131f503cb70cf50454b784a45e81802994e63f48906feee239d553	1	\\x9693bd40e56322263ac5419489e696a9dc27c58eeb2b8880b7a6e474488ea6f8a8687e40551f010f23d7f60b3f8597e729897c897f83431520fc27aa0ad3620d	1659817560000000	0	11000000
18	\\x32fba2fc05c26c731d16bced1ee35168d3709968acbf994ba94704d00b1e2ac2f1307f0bc3c85b519c2718a3f5c11087c729da43c54121c3b13ebf741514702c	226	\\x0000000100000001302e8e749e675d9d03be3817a21c7210d1d5619676048c4f2a4e04cdd1170326be426bba3bf1b1b49723977326f3acb2be24023abb5b5798e9b382ae3c776e1cbe7afed4cdc9c8799b7fbb88b8064bfee847c32e5b98005fab2b21742b41f3b94dec8ae6c2d1ee211f966e2675ccb5aec83368fa1c2cec444985189f5b0677da	1	\\x328727b6d0b9903ac4f62819cce9e6cebec19a0598a528a8a7da3b9776f70f6f3ca457339a232259af18e74aaacac9ef2d99f1fb7e0c77b1be59075da593d50c	1659817560000000	0	11000000
19	\\x2365ebffbfdae5771b4270829db053d9dae4ea69718401c4329c38a47179eb57b3ec2150da414417b411f8e31641ecb83c9682f9337b294076f3904087f593b8	226	\\x000000010000000187a0abf40e4ae294112638f3eb3805f956a4c01b2f9fe506fe06df30998c1d887fd22b69575f4eec7eb3e87c760705d0c9ec376f2b3921371f026a62b5dd32b003fda7186eff45bcaf8e45286037f443f05a397ebed5ba8531216527a133d28758a95ed1757498d816c5f28ce680afd7b8a7ee2c8b562e7951f9ec44cda0e8d0	1	\\x4974eca2939c9b465b305ac2761992451047140314453127c805c89f135241ab51a42da21af913fc0b0cf1f4bca669cb39e56d25f242654bda53ab5b6cae060a	1659817560000000	0	11000000
20	\\xd398f728d1418f1399a84902229c3a5b0560478a818718c99cedbf0d5e060f90fe85e8c370e94c8a4c3415f14d9de664b608d3e2bebfabeebfc2c3b9fb79f932	226	\\x0000000100000001560ceb76a56898887bd78267fe1a421b86303ae3d38ba1be6d2b1c193ac783b3ba87dee62c0d63cbfa4c76b5923a233c00586311362d8737b76acf8121cd1acfc08a23d162e1f7ba1396ebc724ce56431386308d053dc713d6f24e43d7cf1fde86b4dcd3ae43afe4a2c9c0db873b822a65711f8856c4c45a95dd0d50a67b49a8	1	\\x11f63218582c63177076bc486af553e8de510f85c75886ab2810a13f70f1a0fb24854944e667f23f4dca440a629a41f69216cfa5c71331637d4875ff102f970d	1659817560000000	0	11000000
21	\\xff41e7f44d98c3b9984aef76d08f02b9c9fad7114ec12f5b42a7de7506bb65181cc6d312b28f08b6dc47e523aa74bd488ab165e89a1aa3d2c8b0e5c056cf8860	226	\\x00000001000000014be914006fcec8aa0204b1c15f4a94513952e1b3e76b2844f6f38202bbe0aef55bccb7fb584c1cf8011cd77b19d72c7917641125b73925b6bcf7b48d96df9ac46c896ba9c19b7fa7c819cbbad47d552e0e969c23762bba16acb7ce6265d5ae3131da018168109292d366f7af675207fab8d3efbc209772b05caee9f655f5d81e	1	\\x7686d8561bf7a1d86b3f2964c5869838849e232162a300a2f2e41a9fcc4a11c88347c7558e7e73d3031584ae9750f1106618a5d68d322824e846d6941fc7d206	1659817560000000	0	11000000
22	\\x372bed265448a9ddd414ae30b3fcee202c3fce13187f70e19b5248db1dcdb3d612c121c91df326a2aa69e0b7a071d08d7266ec1c8fcb14ec737fbe9a8b8378d8	226	\\x00000001000000018c686394b4a10f18ecff0a90c92799de53301fdcdf7d8003a978573f602979925c2160ea03c001787072eed9a28ad6d6501eac2240ffda10f33162ccdb3641bff0794ca06b11f123f553e94f7fde799c4a1bde4953360e56882ec537dfe82f98aba3aba123d0f6db3164df6e18b05e83bf9a2dc0c5947beecba67787c3119eab	1	\\xd95934e4b445d98b8ca8bbabf805cf69b95e383f6edbdc72123da18c4f5af884492c707999f5ef78b0b3ca8d6301ff5a2fee5b5f6e887fcc0719047ba93a230f	1659817560000000	0	11000000
23	\\xd14f763cdc40ca3a04f141a99df052851f7b8742bf764beb5c37b4cead253b2f9aac63a6cb4fde902618096690f35cb58101acac177d906e388b840bf82247ac	226	\\x00000001000000013d9813126416a8eabdc64d8e4547f73870354098dd6e3d185f76df95a5731034bfb974e889674b1c9c9c5de6eb55b47f731c91f32c6955a2807243f1c2eba9eb8b00bd2e40fa20f898730b609a002a706a3e79a260ca66e6734e7f5d5200be86581b61df8cc3f9765a5d22d2af11a7630789cc561f341823c9bea7a17fc03e41	1	\\x0c1af5e3abb0b18738bb7258b98611cf21c7d0a16ebe6320925d6ecea6a6b677fa9847090631f547e99ca90edd6a9db566bdc8837d38639dc76b2e9e268faf06	1659817560000000	0	11000000
24	\\x9ab003467bd0cf9befc40a4285424d4437fcc4ee615df125d8e654dfb68c460eb18d4bcf7e522ea86ba7f49dbd9d4a27ddc25885c8d01fcb0ba3ec4e52f51a01	262	\\x00000001000000015fce5c5d91a9632357ee223c254e4701895f114019810868d69831f1bdfe80e8febd00fd9733da46c163e6b989054b5028d795b92f62f1e9350d4133e45971f983b49273db518fcd757ac2dceda1c4724b17795fcaf8ab35281b1b057b8940873c7c6e8ddbd677f4de24e3ce3f1acada3182be15adc2f49f670294f85acb6e07	1	\\xaa3e9fae6f2160b239c1a3304f1edf8fae73160fc7beda80a3aac7c5296c83a2dd9d9dcb0bfc83c852c1e3c460dc7165fdffbbde39b64489eb5ed92de6406002	1659817560000000	0	2000000
25	\\x33ded8e286d4bb4634ae3c422f41257bb7ed233c17fdd80e2392711fd661f3739e37ff82d0983c307249bbff847808dc9f25cf82a14d48db28fb55ddf816cc91	262	\\x000000010000000102555d2cfc69fd756de0a2c34ba3c2be322b75106400113c54d23071e7d5d231fc08b472b046d4bfa1fef6062f3ed1b2591e2f1e115f911659cc6c5370b701c67544a8470410cd30d2bee71c1e3624545729424adec5149ffe0af59b809d4a40fe1d3dac82ed9d512e720e8bbba6d3e25aa5b5a96e8752ca5555704c3943fabe	1	\\x5b183184ae93a2ffcab60128f66dd25a6707b97bb8cb6c3b94a4591e5222274311236122f5c86a238025062fdbc23b51f1b8fd4869792ec83a923068da97e607	1659817560000000	0	2000000
26	\\x485969dbcad29cbad1d7db1ec056e1a9c1f4505d8370f170a9daef261810339ae2ea776899090c2b51c31dc3590d762bc47390504ee6903601d167bf64641550	262	\\x000000010000000129f851406509a402aa9c276f949b292df8b28f69ee7906a3a430b7f971614d8ac09c5571786e5b9f50d240e434843cd7189197985397423fc5a10c8bf892551a3f618c8f9240ee687ef2b1aba23d191d4cf790152fd8458664634cb83397ff8f009b2ac9f9a2fc44eb7c05860ab99d54c7032bfe7aaeef49ab620f34e29468be	1	\\x431066522bd71176cb319f251d9e978b135042b7d21aa05446b7e102bdab94314c89db0fc0b782f016f13d714f60bcdc5a018abe78c08acabf25ac2479752909	1659817560000000	0	2000000
27	\\x3e39bf49f644e8ecc79dfaaaf800ae7cc4c658c08deea24bbb1c15359e2f27d084e7e626532c6ca7999b6ee937708be1a2c22cd98bcaa8b455b3e2ae1099bc60	262	\\x00000001000000014b3c1b1c48ff17ca16c66e70c921651743b3a1aa01bcad7952ad73d3e8483216da077366e3821cd56a2754f9d19f8e1e0bb40c81902392a6146cfdc0431183eeda6efc634ef49b3bf761e2662560e897437d732ae2a6019e44448d8f6207abc67e43e897f886b97be91534bd3341511dd031ebc2c4d928fd5469610218c9644b	1	\\x5f820278b93672fc055c198b61b438c08a84ea40bbdeaf544d5380d60268f20c2f724ceb79111ca019031c196371952619c720c9196b83ab6663502bdeff340b	1659817560000000	0	2000000
28	\\x8f76db71b9d3f7ffe9fc02480dc3cf848a40fcebb56faa5c4b895157b120eca95966fb4f027cd413514e1a78653db323fd7fd4fdae5ca088724637fc93553158	262	\\x000000010000000110a5a0c63df88505fd8b1fdefafc25ccee5128500639fb1a304aded08547fcb155332a741737b10d7ad69b7b25dc0c742d55b3cc5ffcc61e52511fca0cf90b4bebd40e82bc124a662e21daa31e89882a9e2f3b233676ef0a29bc26980ddb89bb3adf45faa86167facf9d33e7335736ddec32011da5d2f970b6dcb1f1a05cd6f9	1	\\x2a9fff4aa1cba43308f692d86f57a29c95527048e12cd3da47decc4b43e89effd2920ed72f64946965a9306802b2da15344837325efe8bc7577f9a939bc40308	1659817561000000	0	2000000
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
payto://iban/SANDBOXX/DE315037?receiver-name=Exchange+Company	\\x679d517cc3ece04bc3d9bbcbf326d6ac48aaf4f78ab1509e8086e17d0fdc87a45d02fabc8f04ebdfbe972e1cb3a36a3603c2faf85109d9942cca9d7ad0ad770d	t	1659817539000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x4c8ca7524ed85d71ceaaf6d5eaf2b5ee6b752da71fc26214640ee810f1f28591cd231a69ee1412bc1a1917d02a650b9b3cee55fbf4cbf63cf28b66963a135806
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
1	\\xe952c93506bfadc5b8afed63d7f3bd11642d56b8bb655554efb7893c47374e9f	payto://iban/SANDBOXX/DE739907?receiver-name=Name+unknown	f	\N
2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	f	\N
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
1	1	\\x010a5729b6443d64cb9ebce9827a4b795698dd90862151c8fb507c2cedef307f91e80d9aaf34f7d7f58170ac6752f66364ad44aad55115b71da93022e394e769	\\xbaae8de8ad47a209f3598197d35acf8d	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.218-03W92KEKZQ4AC	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635393831383436317d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393831383436317d2c2270726f6475637473223a5b5d2c22685f77697265223a22303435354541445038475950394a5759514b4d5234594a4246354239485143474752474e334a3756413159325356464636315a53335430444b41514b3958595159503051314233374142563636533544384a4e44414d384e505745544a43313257454145455438222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3231382d30335739324b454b5a51344143222c2274696d657374616d70223a7b22745f73223a313635393831373536317d2c227061795f646561646c696e65223a7b22745f73223a313635393832313136317d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d473633594536314852444d4741334a31514159444435475a53304e5234594d4b4a5a5242545745525451515059594157443930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223957393437464d5457444e384d41354443575331513534335437355846444d563543363433535a53343947525053585343505447222c226e6f6e6365223a224842384656475834324848435a5a434b504e5059545058304131434e333859355a3959543950424a3948393753433759574e3230227d	\\x2de737819f8baf63a95663c198a810df7f20c134387b0be01de65ea4d5664e5a60fe0bc145452459f7e7a6dcc12dfe70b97d86739a50ce512241d06b1e0f16e3	1659817561000000	1659821161000000	1659818461000000	t	f	taler://fulfillment-success/thank+you		\\x1a069a77e94b3c0f0fb4a021c91418e6
2	1	2022.218-01TD9Z3G79N7W	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635393831383439337d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393831383439337d2c2270726f6475637473223a5b5d2c22685f77697265223a22303435354541445038475950394a5759514b4d5234594a4246354239485143474752474e334a3756413159325356464636315a53335430444b41514b3958595159503051314233374142563636533544384a4e44414d384e505745544a43313257454145455438222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3231382d30315444395a334737394e3757222c2274696d657374616d70223a7b22745f73223a313635393831373539337d2c227061795f646561646c696e65223a7b22745f73223a313635393832313139337d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d473633594536314852444d4741334a31514159444435475a53304e5234594d4b4a5a5242545745525451515059594157443930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223957393437464d5457444e384d41354443575331513534335437355846444d563543363433535a53343947525053585343505447222c226e6f6e6365223a224b47304145514e45434837593230543730374d3239443454463648475247524648463248474a4634374243523946573356414b47227d	\\x9eaad7f119786d9f713bb34bbb888917c023f45140599e3921c02db0c12875e70d01b1161b8329e7d166369a930e8a1c1fc33c0a1254f67a5e162e59346b2fac	1659817593000000	1659821193000000	1659818493000000	t	f	taler://fulfillment-success/thank+you		\\xcedefa400e80247c406216d5660b9e1b
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
1	1	1659817564000000	\\x194d94de25dd873d26fc7fda67c97a6ced3316d42b4273027e8fa181217633f0	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\x3ae6ca4ca266b290645b2758cd0cd3ccae63025760aa79dd109fc73f53ede990435c12cfb766d2c694b7593b7b089373988b531d646da3b3722a050a739cf405	1
2	2	1660422397000000	\\x00dd2b54655002edb099ad6f6c85fee08da543cb60e79bada10a618421c7e24a	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x4b826cc6f0e0a7b3c4f36ac1735ee0f36506db1c05df8e90bf129bcc5e5d3a331b77245828d260f017f9affc06ee05d299472a7424535e5fc8640efa84576d00	1
3	2	1660422397000000	\\x21971f2108925a61a0f76d27d88e18109c87ec556155a74f9051af16ff7c5946	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\xf1a3cb0f2c5adaa5aeb704a58d60825872d1ea82068b04a1319b54f7c76524d47e6566512c5257d1858f4b48794adf37b1c8870fb449ec2c114429b4efced40c	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	\\x4d3f90e8697e563044bbd857f6abb8e5de6090d11dba44e755fcff295b77893b	1667074833000000	1674332433000000	1676751633000000	\\x7d093fb005de848fe001ee9616785226be41ed75b1b62470c63bb214ead7617d8fb5cd89a1f66fe32dd1131731e88f3ac5e3cef5de8d03f4adebf2acd887370d
2	\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	\\x3786bc2f2f3f49e81f0883c385779b5cf5d8e48d915fbb624acb38c579576956	1674332133000000	1681589733000000	1684008933000000	\\x740fb5690cf37c44909ee1d9079d7923dfa8901c383ea583a1241f85c81d22eca81167cdd32a5a18d9622fe5c7218c1547f9b1e4f3a37af1483fd0d14fa1260f
3	\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	\\xb83a4a17cc4ba6f0af832c8bac59e099b9e79882b5b2bbc51e91855a49842821	1681589433000000	1688847033000000	1691266233000000	\\xa5ae771592dec9ede3d4faaf6627e5163e90cc4522cc3f84f823e248c6f3439b2d0ac4689555a6eda65f300aa89a4498c297ed9af5a7118ea709e361e06c1b05
4	\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	\\x19b026192e86210d7bd624c42b15146d40f6d9d2207abb39467a3e2df1fbd8c3	1659817533000000	1667075133000000	1669494333000000	\\x37603a74b5b99acb8da2375f6433fc77a138f70c3d0ca91e7064bd6e0f826d34d7ef8a68759aa0d591b5d3109ebd37faca2b5258dbee094834e6b2af7fceae0b
5	\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	\\xd971fa5c5446598fe40fa1966ef0c9e92b660f113ecd4fe082b3f856d19c2aac	1688846733000000	1696104333000000	1698523533000000	\\x362cb36c9178849da5a2f37f7e6f495502c66c55f6d20af8f7246c9fe37e2a211d45c90d9dbd456402974c55973b62e0fb656d67def659ace2fa2c663dd6ba0d
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xa40c3f38c18e1b4828720dd5e6b4b0fe415c13d49cbf85eb8ec6af7b7bcae352	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x4c8ca7524ed85d71ceaaf6d5eaf2b5ee6b752da71fc26214640ee810f1f28591cd231a69ee1412bc1a1917d02a650b9b3cee55fbf4cbf63cf28b66963a135806
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x4f1243be9ae36a8a28ad67321b9483d1cbd7b69b2b0c41e7f922618b67b965b5	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\xe2123de12885c7121d96529e23c3e638ccc669f7fb379df9187870e8bdebb2d0	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1659817564000000	f	\N	\N	2	1	http://localhost:8081/
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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 20, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 20, true);


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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 4, true);


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

