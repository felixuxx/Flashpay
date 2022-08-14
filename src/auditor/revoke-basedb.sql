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
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
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
     out_no_reserve=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

ASSERT NOT my_finished, 'internal invariant failed';

PERFORM
   FROM exchange.reserves
  WHERE reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  out_no_reserve=TRUE;
  RETURN;
END IF;
out_no_reserve=FALSE;


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
-- Name: FUNCTION exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


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
exchange-0001	2022-08-14 19:08:20.578361+02	grothoff	{}	{}
merchant-0001	2022-08-14 19:08:21.604369+02	grothoff	{}	{}
merchant-0002	2022-08-14 19:08:21.995204+02	grothoff	{}	{}
auditor-0001	2022-08-14 19:08:22.116322+02	grothoff	{}	{}
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
\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	1660496915000000	1667754515000000	1670173715000000	\\xa0b53f57e6daad7f621de6b8b82a2c77375dbba27131a1f3f6d5a7b382fef1c9	\\x5e6321b758b43110dc4cb4b810bd19971b9e672c13cdb774e061d18bedb231efedd11148d303946c31c2a99fd8b23242c0397fc3b77aabbb1228c17b3306300b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	http://localhost:8081/
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
\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	1	\\x0bbdb2d8e27013936ac463ba287f0a2e42014a27ee2ec566ce9a289fa71d56c15945822db2f46c07abca8ef246531c42b81c705ce84a29b46482d34c403a5ff3	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x1ca6a1212062637024345e59e61187ed675482c8328b5112c91afa4d332d18908e815a40bb622ca3b1cd7538f100ced0bc307fa89b55eec6ae7dc30e1e27bf12	1660496946000000	1660497844000000	1660497844000000	0	98000000	\\x592137b950d311b054eaeaf80ca91ade5f9f3cdbefd22f60c8d1996a3fd68d9e	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x5a53d49226f76aba31e3c5225d9272607d6dacd03aa9286a227cacf04d94c0a54585823f05fbee39eab71b96b0b47ba12651a2cba7647519aa2d5b2e6b058c01	\\xa0b53f57e6daad7f621de6b8b82a2c77375dbba27131a1f3f6d5a7b382fef1c9	\\x20d42b0efe7f00001d49602eca5500005d04092fca550000ba03092fca550000a003092fca550000a403092fca550000208d092fca5500000000000000000000
\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	2	\\x1f577e803515cd596a820220d12ab80b1975adc2c21267032c44190495566a33083293dad7f13f2208b0cd60d9cabe5d4be787897c2f6a1aa38d7299837a97de	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x1ca6a1212062637024345e59e61187ed675482c8328b5112c91afa4d332d18908e815a40bb622ca3b1cd7538f100ced0bc307fa89b55eec6ae7dc30e1e27bf12	1661101780000000	1660497876000000	1660497876000000	0	0	\\x088afb72460f451eff570191cd1354a9e926d8ba5568c0a957c65558b3f1746e	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x85880abeb84345cdfdb65b70562a6465aa68373c40d3a9ea61037381d6ebf88da6d6a36f93de5c79acbb2994dfa36cc41c418a5f05d72fe8478d74ff15e02b00	\\xa0b53f57e6daad7f621de6b8b82a2c77375dbba27131a1f3f6d5a7b382fef1c9	\\x20d42b0efe7f00001d49602eca550000dd330a2fca5500003a330a2fca55000020330a2fca55000024330a2fca5500008006092fca5500000000000000000000
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
1	1	29	\\x2df36d4f8e1387dcd2f1c5a8675e11bdefb1d26443345a79be35f4ba9bc7400c7fa5ba6edb2ac1011337868d153446bb8dc857e5755821d35610a2116cf5e305
2	1	93	\\x7f21bb69854183ed2b4def52d1f2e525622b655bc07784c9ec9575977f4199d0db950997b0a9c18e0c56802ce25dd01d58705fef9f94a4bb8eaa9b50fed7e00c
3	1	139	\\xa950a0dd35d0ec37164275355a161dd7b74e9b15dc730490edaa07eca39fc8c016c0659a298a2e9d8c30626345cb68debe9bfa98f1405133b23d12a784fc3b0c
4	1	189	\\x7a941df4b68fcdb94da14eff8160e84e46f718e70eedcc4a765b0865ba2663ec7950c976043ca7e8e5e459672ca3889004426ff0cd91c32fd3bd906f0a244508
5	1	236	\\x64242a75d454ab3f99e0447773f5c6feccdb6c8a57ac3c7997a5bb17cac07605f3c5bb4789464f60e8a8d766937f7b45c4852aea928b9c7460e021939008430e
6	1	294	\\xfb49bf7ad09868bfe344f08329dcb26094886107f639853db84694332ac1d5f90d6132c4a4c4ff909d3a4ad184def394c6ff376237fa4573b3db0d5382a95b08
7	1	369	\\xce543cf26db1cb1109d0661283c787cae3a568e518208539ef1a884d250098cb508c94010c6f5d2a4cd34782bc641ecda41525026d8032a9532f6c7868b83503
8	1	222	\\x3f4d7517f08e1e95a951df74c1f92085e4fc28be0390cf1b0d0d57b9fd4550e9100b15d0118671b5fd37b077112320435ab35f3289b34e090741c6c6ea786e01
9	1	418	\\x055bd5c75addb320d7de5e269a9831796d863d951189ef8ab8a3b2fbeb4110325d1922f6ac2d5ccfedc9c0500f3376eaa1210ebbb09cd218f8d0af8d8b83a709
10	1	153	\\x7f3820e91f7cdabc318f6895aa2c463defda1d793c7d9b2a04ea731449ea30dd2bb81503c45935662ac9edd6f1d10f4a3275df1ef167f3a31c4889a7da8c0601
11	1	181	\\xbe60415c469ad7f0edc03f0b34931ea9c63653abc8928ea5200375e9d016a76fb2f2676271588ba949026c7d75c83918eabae618ce3a1c911f8c66318837d10b
12	1	105	\\xd9aa5b9b133b88c2c0b8f93fa0b44eb7b7f78abb3c3dbccda0b8e8e26a9447a9aba05fd4b47443bb07222b17447ab949d840cb3045cb88eba94f170e71b5e70d
13	1	164	\\x9138f77b3284afc732fa8605e07e69ad9caba7200c7513ad0ea2caec0e4092625a556f7b59b0457f2feae351f0a0ddce103d19db7ab87eb5ff00ac23011af10f
14	1	111	\\x55968490cb927de5c2377ad8ea7d15e18eacec97c2c0aeb61c058af8f3ab99768f49eafd96ba4cf08827d52673e08ac10b2f4122ab664c981d2af3ab39e82800
15	1	320	\\x24eca190aaa091754b40711c980ed0401e2e11b740d4e75501a7ff92de59d98ba6e17a872d11795357569302c30c5799b3dd9dffe9b19f1667ae8d5c8cd7fc0d
16	1	117	\\x4fc6785f6fa99f3e793ee148ddc19ec71e39a0599e874a9c5acbe04a39cb4980e98d10c473277cb230ccadba52ec945d34690fdae8cecde7add2c63e48d0cf0e
17	1	411	\\x8e712aee62d096a3c5a2c39723e8998ee17daf1fa8eb4e436078ed1e57871b52d2538848be4a3592021c184f666fe5b562b917e80467ef8ce936e6f3aebb4c01
18	1	71	\\x5b65aef15d8b28fb7d3f9d68286dd3daf04a592c7bdf9bf3e429c84333eb65c71284b71097d816e77639b1adb88b0ee0b194c02a921be7f6d899b8e9eca2f70b
19	1	270	\\xe5c8292f2113c1dbfe88457f7f55693421e6f0b4e51239f11d98e25f219df72ef9f3dda0b4836c8ba3383460819551199ccf0ecdbfe809e0c3b310974b64aa06
20	1	253	\\xba801b5f752e5ee64b4fc54e1ec5ee1170d3bdfd7d738546b0a609d3cbb2132dd5ec8a7a74657841cb84455707b7e4f39d8a43b36818560f2c923d94897be30d
21	1	151	\\x96efd920e92f350335ef97f721f5013f0a5a499d5d6170c6fa63a8851a35caa952f507ae6fbe88d55f33c967978820dc2651fc285dbeb93eab005fba08a0510b
22	1	286	\\xf78bf1e5dec30fc50b09fbd25c6b715a1d03bd9e3b94bd6505a73fca7c8ec532d182d2dc14fea97ad221c23dd2ea562724106e298bdc50802eb1549db824230c
23	1	212	\\x6a3410146b18b083b14ccf2a6a1dfb86cbd3087109b48e5f9c3cd1270d6703b0fafa2a3f6329271a17680f024f39833a67915e973866fec33e2e70bc26962604
24	1	322	\\x40599c48a9b5fe0ba2d0812c4645de45d72a5d30e332c463e0bd80276896dccbbf8381e67c7dcb1cce510a4f6d9bd6de20962950ed9f17fdd7d965d74e433306
25	1	355	\\x66a925d6a62598253f292e2ad7f0ea609b71525ad8df975ebfb4f214945982156af369e756ccd7a88779d9ca84defc6da5e655bd50e16e3932bfb18eca10660e
26	1	391	\\x110f66698465fc8198074f222eeaac919077ad8955f0dc00c1ad3bbfb9accc30836e6c27cc51c6a25b16dfe925ed41055a3304e25225f68e9f702d1214c41108
27	1	51	\\x65c9ad0df3452a6acbe0b2780fa25cab6d090b4a36391f58523aa43492e6f127062e5942c81dc3a41a8f3b3db68eb9cc80077bc1e4a50d3ef6ca637a7658f902
28	1	94	\\x440b77b27715f4042495b20a974482a43304be55bbb0c4a6dac27e5eefceb7e7731bd445f27d9c86bdba30e246534e7927e74bd32e9f5645dfd4da9e1d0ac409
29	1	101	\\x021c9b974592b5ae8e9230a89196b098040049cf759de17a22150ff551a5a5b80b0cfe37dc9360138b2224dd5dd61998748e100523172f41dbcd93d1e4efba03
30	1	203	\\x824814f17b22ccbf6b39c364d1633a7ada5bc737bba2abda4da575ba8d1783a6e8752c5b1c9263be00296a130a14b11b2cde318fa606c3a0e7a9682ee15cda0e
31	1	8	\\xc7d7cc208eb8994b1b2dc223645e9bee5c2e533e127371978ac7166d2f06e95ea585a1b4c3534293111d7594f91cfe697766a2d44508cbdfd482e7edcc6ad907
32	1	185	\\x6d35a00fe79a4ab055a53364cbdd1f2ebf27e841488365fa2bde0d24992924c9886a5b11ceba877b62f8808da282dc1da45f5a065b93961e0ebc31393dd1a60a
33	1	249	\\x9a9cb00c83aa83c2621f097170ef26ac49b85f717462b81be36543e17e5d8caf6b8b90706f35aa8e63a35e73d484331eb641fdd70cbe2e585ed312c5ad75980a
34	1	97	\\x72fc638e2c19140b719831af662a1452e836c916dab0d99ab05a5a7e3986a1d1e7eb003be2d62842205ffadaaf73879834a2396aeb800ba30ac7e6402e724a0d
35	1	16	\\x5565057dc4e55745bca2f52a4c8ef440ca28a9f8e7e449eaf62f7f88528c1a3f84b175ff6b481f7b3f0f033c89989e892223a148dde039e27510971de503bc05
36	1	41	\\x5927ed4be4ce7944b1e7d0c91e58bdf1f501925c0c875bddbb513d5989cc349745203a64888b105e5d9ecc1fb6ab51d2956e4d91074f9b8b85be611c0ab7270e
37	1	148	\\x78dc07977521b7f8326dad14bbca7d44fb19ebd1fe1cf7957ea55729b0f4e453df401f1c6206c6d092cc6888becb92b242c70c9cf23b5b4727155d6d27e63a0e
38	1	48	\\xc4af334bfad6b08d59de7cb434d1b1dc267bcbf0e9f57a346ac6588951ffadd36c44763e0738c378bd63d9257d1f490459ed7bcbb403ef9a20a7b4d3fe051e01
39	1	137	\\x2a276f26cb054521e8edfab0cc688c9592c1528bf57f7e50d431919d9a166087ed6556ae8d773c9e10a417bdf8ebb47055b69e96aa2529dbdf15f4348594c60d
40	1	417	\\x834afc5e76479769477b34dc39317f699734a40ac9d06d87f16928f52c51d31be506993993f3631135894e98c67782c7033fd4543886100f81b3bdeb86dbd804
41	1	309	\\x18b8661b5bf9e223a3d5a5b479cd9bf3e86ee33b4590940a9efd32624523038d84e8c0dab9783d4566fa3bbc1d10c15a966aa58aa0a923c00f77899832d99b0c
42	1	273	\\x25f8dff4517f28ac2da9aa1b23555ab7e583584723e2a016c1d4b6488da30feaef0aca1c13ba897e49f4a32ee444f9211ae9f3560f0c0eec0e5c8806c56edd0c
43	1	260	\\xd706937ead022969ae57b339db847f08f4be63ce1c7e34e4a17bf3aba8ff8ed84efe2738c640e253561fcce092d6260f14d209b7547b43a134f0279a4a831500
44	1	389	\\xc70df0309d82eb970935ba73c300c447d1b5308e365192deb790c3dac9c41dec8d95173eac68d8566371209f92d2709cf63c210bd15d9c1b5c0e437a91f4e808
45	1	152	\\x5b2c621548c5ec81d749c8634034bd3a618969f7036e16b38cdf2fe0d83b1b1de66060addbb064ca1636c5a0738cc4014f5ef382bce5472e27ba68cdf13b220c
46	1	200	\\x797f914ea38e205cc904edbe09dee5f7cb801025f61961b14dbb5b5fe2cb2ff722ffeff20d6aba6432aab9c9da3dcdd260e2eeb1422543a7c8db87651ab7ae02
47	1	18	\\x2edd4bd4e9adec6463071c58802808dc72bf8fa7ad927a1646b8758a82de73d428ee266e9a9fb88f1122cffafc5894dd4af6fa70784ef0b7332dcfe677baaa0e
48	1	131	\\x89e9b2eb126e0f9217ff2fe4b21fb6785e3a3256605497f43782466bfdf0d6fe170e6d8f89c3f872d5e56a7df158cfe324d6ba1de0cff1a00062843419b12f0b
49	1	325	\\x09553a2e47ffe12c827681090e57bf4bd4be8c37660ad4968a335784413f3506f4e6d41d276b89c090352a016f4ce418177093d153d3c3acbcda94f2797b1200
50	1	118	\\xc024c8a46be4decc660a7b7b002aac348057682e3641fda427c63b12d82034fa0a1558277914b3b59b14cd5cdb35f8589142e33ba54b840abbaa5e71209d7f0d
51	1	6	\\xd24a86293baa98ccdd2e56abcdbdf538be9dd253ea4e528e830c36bb5501df6a2a89388d723a1d2d30d628b0805ad335d8c79c10eefa858640c9491b1087ea09
52	1	160	\\x40c2e65683556e7aadaf8e2fbdc5ac32ba8850d099f4b9465972b944baa5e91f1a7872bba503ca37a45338b1f8d65eb504ad4c597efb7417db0568fef6951f01
53	1	128	\\x4e4ab7f31a204bff8e6809a9a3c6a5d3848ee3688df6ad8204171a5964312844fc3df7c3d54fd74a808801d91ce647416a236939e8369977519c7128e2c90807
54	1	34	\\x7054065c29930a9f915b3015fcd25a5e89dee41a214d2af990765a9c9e442c0b18aceb38d0e031f9c231c9821615406a0dfafc032049d88a2d3d5309d7ce0d05
55	1	125	\\x0d7c78e24c00525705516cfbd71f5eef6349575ab598c053fc85197c33a6407baf066ba0d7b71588c44eb1c01dce86dd2f7f9f55ee877e2f3a0f32a445b6c807
56	1	220	\\x36d6dbe4fa0e7cbf9f7b5a59b66b86701cb5dcc95d0017a959e9034bf5171038f727cc331e6d30dd896d3f90fb65fafa03c768d47514633aff782d83b825820c
57	1	266	\\xa7a889fa7867cfd575692b4ffdc2c05b402fe82530273b3e73f6e26f48374dc6cc2b23b414109fd2fb97862d794750bcecf646a326f028c76a6da15dc13eb40b
58	1	250	\\xd65f2390ab9228c2077466c0c1e1d4a648eac476505431371fbbd36d837df536fce0976ee1cd4a42cf7b465cef7ce3da1d0851b5a7eaeff6eb6e335ae675f20c
59	1	410	\\x95f16e860812a411ae08c7d9f95f46cdab088ab8eb98327ce651ee88af170f35c30ac3fa7b788f08e44dde12b015181e9b209086b906044b405d9cecca445007
60	1	269	\\x6e598c1fcb9ca248182a7f2ec1df028ebed8395c815542045da6c1a168083372d987c7e2279d8514dd5d875284b2653b39aebfdcc5d035052d7fd2896c5d9604
61	1	357	\\xea41f32ca45991c329eb9275aad953436868bab36a078e9b30a7cd56049ca5ffac58a010685c301c969b86ae4ddc26efe42647f3e6c3e0d505dba7e1d6993c00
62	1	235	\\x61e3f3f9c3a42ad9132676314fcce9eb6fa1a1dabde351cbabc38c9dfac3a879937127e113476ad70680f71d1210b2c16265d09c36a013f9edad28e0ee01c80e
63	1	255	\\xc7a49515120f43cb75f58dd1e01960b15f3ca176c5801960be752ace6f9f7b6e6d7535a6e796e035c47d89d223ddff0363ae6c43e9d56c8c0ec1b291dbae6608
64	1	419	\\x393dd580a637b836af9235963332d09bee7d4656ee415c3ac966867bc95f0aa746225aa596f851ce63cf24b7784bc07e5295cb5cd739bde8876245a4711cb00d
65	1	127	\\x65eb94611fd078767fed30d7752f09a702f7c6309b0d142450e26c8d86542ecafe3996c86d7391c670f86fbadd55a372a1314952a6df26d537a4f99741356d0e
66	1	13	\\x22714fb9554c589a2185926a7a7646be1a4a8db9c94e4f0eb6b3675434c875140a8e4f347b4982926c980a313781b126b03621ab31cf7649b5cf3b19accb8906
67	1	183	\\xe3427f7f2c0a5dfa2fe6d622ebc3479ebf3d1e55790d6bd523482b80c2554541db856ff2356cdcd14c6726ae39d989caa2e6a3bce79451592a76327bd7df2c0f
68	1	195	\\xeeb255e2b6627ad37bebc513186dde24981b2e54d0f8c1fe3a8191acf6c63ebdfadff4fbcbff4b81e6963ce7d646fe800c62754a15a7b83eb0897cd2c5498f06
69	1	80	\\xb87ff2a067bccdf9995da62a023912cb99aa57066441462916a6db10bddf18e7a1eb72c4c59ac14281bacff3f65328bdf4a714b1c6926450276463434e1c820f
70	1	36	\\x4def51e39c225f51ae0c200f0ef541c50fb9688b004c23326b0c554c816cf6b0b910ec6fdf366effde3583cf45e7f308e40099e05611ee6ca5647f3e829e480b
71	1	91	\\xf1c6ea4689181d524dacca8dfcc8e2155fd869c739e0b7305f78b322fbf3a92638c23a8802e07be508581e3a700d26075c59ec590680de13f7ffffcd628fb302
72	1	194	\\x0ba0f85c025ca4a93b65ea53ca3157facf82c0a07d58631c839de1e46def4cdf7540e24ce94a808d5124fc193cbe544c6738f11ae95ad1209f74fe3372b34f09
73	1	159	\\x191d032e7d38d78be9f8d16ce1f2f99a8f9261b55f6def58f0c8f596b4aec83068e8082441908a68fb5565fa946599cd86f0392e1a541839ad2c70f9ebd8b10e
74	1	98	\\xfa839849115192af874db6e475390deefdaee3e405dea6bd889e57d84f2519021f0e3d50454b5b430551025622881df70f64c8c286d744b1d85910af6464280b
75	1	37	\\x93f91807d9a8f7f5fea8edf0e0aaf8e099eb919a80f0bd1f1ab86bfc7c764bc9528477137036b1821aa1debd4bf870c63e533148f63460102292347610737a08
76	1	30	\\x8c7e0312555baac46a01174ea0c13942d98921bb7b51f4b80a71c05dad6e8c57ace6bed3db7f31e813e752c3a2c84e052eec1b9dd845ee3549ab235f89870807
77	1	362	\\xd7f2265ef0a37589f9ee7004cc8695638f156d8d56f67f496ae7ffbda166aa0b271608fb9add060a882c9e9921446d477848413d5f3b427df385baba7feb9b0f
78	1	130	\\xbb5d57410767f0655756ddccc5498280f2f7c45c246dcdb5375ca5c0a87bee5a181e12cba0c19bf355a816bddc59b503acc2a8dc61c7bdc3d89963dc03db0103
79	1	346	\\xba0da33e0c105ac63b6038649fe7dc78a57f53492485d204cd2741c8bbc345dc026db69b4798a689b6f7dd6aac40ddff6b3f24f91487f53c76fa390364f86009
80	1	380	\\x1ad45f7be16970abf7985c010b6868af4e7e7cdd62312b1e2e3e5007b7bd0717f4663f35bacb582b8134b28808b6f3ae4ffbaa699dec60482167b4ac72b5a60f
81	1	308	\\x53d6ab7c872b6b9e2d7a956dd82bb50e17fe7ce5d76fd8d13625294df58345a3effbc330c435b5a778eaa45679936c39c69c9718be11fe07b9fabee0da947608
82	1	295	\\x17fdd00ac13c353b338afc08479a554df5b0dd7dd5cc695743617e860050bb23813d18b1435e9483222a7fb0d5fbbe53251e748f68d5569074dc964526a1200c
83	1	95	\\xf4aaac968f42fce4d5e588df1e6a906de06889e86018b365736381ca6cf3f449baec860ecaebe4c59896c129ae0920e317dadffa65224185e920e832e129c10a
84	1	297	\\x8efaa71a6980f95932942844031d7d9266c3933b23138ebd3b350e69027e8441e627de6151b1b296f1e99e3b40bd116b52e99f8470bc541d02e921736ed2a20c
85	1	104	\\xe5ee5d747a792b33dc5596ef3dd27257277a53a243a3ce584040677ba72dacd75ddd6b71a11d3dc377381e03c8660fee61c35aa92420493ccd7ce5190a71df01
86	1	311	\\x641ece415c4097d24893c561416d2b35b022826e5e8a298c93cc1028e012f4fb4f514960d260d61dd944abd8aa55afca1f201a1ba09d451966273032f594f901
87	1	78	\\x716499b855487a878420508089030810d4b70256f61d8669394e9a0406442d3958597b9b250cb5a69e50661394b7202491a65da230141df7169d3aba34b4c20b
88	1	318	\\x64cf9b0a90123de416283a0594743b39923a578f8926bf43bdcbce3293a403cabe15410ff121814933964add6ebc8316ea925f41accdc52dabaf498fde84f708
89	1	404	\\x6381a2eb9a73d99e5a44635a5b5198013f1c41f509b5c3202fcb6312e0d078438a083c38c169a97c52ea7f708d535af1dc8b17497e5ef83981e705beccebfe00
90	1	337	\\x245c1fe2905fd570eb69261a31e870112ed9da1bea287131eb18a42b632d0a7d95cc5dda41231c4e3e602b030991f8b20f1b74b91af83e7e07a2df34c1827105
91	1	165	\\x6d6cd1cae86e03cd2842e48abbbb55747bbb5b47094ac7553eca3182630163370af9e6c8b74876d97c937591a99f0cb439b24a5d6c5665c3c178c1dcc0478b0c
92	1	176	\\x0bf16b0f6567f35e750772cfda1067a3bc2638fa4f340bd226778e914ac832dda3a7c6da997067805e07f0dc81b4227348a021a53b52457429cc774882963200
93	1	73	\\xdb78b8e93f11e2acef1528fc051304364f56b3bad8fdd64a4bf0fe84398787f2aa381370bd15b307721922e16742365da815dc118e50d4cbc82114dd69ce9202
94	1	90	\\x371dfc6b833bdb1cfc013dfa7414c0cf5a1237dcd26c02671c9c5690ff4df98a1558a6dc9093d73979c9a858bb013aae698ee586c8ce78f1141e20eedbf32f0d
95	1	129	\\xed3bab47e9d58c92610aa4d71d01c10fddad8fa79d7648af4c9be129658907fe9d6173f958779196a9682b61cca297714f4873fc66e9e4cc9a760e346755b803
96	1	56	\\x3c2d7b772ed6897c636833144bd4438049d2deaf892ae5292a40d3c1b3879350cb93e2ad0325717370156db3c2cdccc0c211e6cab680b6cbaaf0ad9380912405
97	1	219	\\x699dedbdc57a09e61a1345b5c8d230713b4ee375ad4c4f4e8ce51ee6684f73132f7f1c09ea82fb2cdc59d54e57d2c6d19ac1bea1d3dc4089ded89ac6f1e18b0d
98	1	298	\\xee9f2553f366142d9da3402de6020ef97e228091a64643acbaf63b3869c8e5b7c45d392892abd442465de67e413876dd6fa7294676f5642b5de711c4e7734305
99	1	376	\\x2f6d8e97cf5e52fafcc5ce26fe50dff20bda31137aae3f603cc1ca8f3f7c5bd0216317ffeb40f1ae31b6ca050e7f67fa8de7ea098f40a142c343406e0e699903
100	1	140	\\x29aaf116f245a741a8597baac680f5ff3a49867b41dd1fbf5f7bc5575c76f91c1a28ddededc30ababebcf3d4feef8081be027af70fc684583ef3e84cedafd000
101	1	347	\\x978f4eec44bcd2c8dc65b2173c1bb0308bab8e7c123f1f7a0f1e55575e05e3cd1499e414e2e601625a8157c4b23ee49915bd73c1686d2df0751ac83e92a77b02
102	1	420	\\x2b91df4eef115924ac1961c635611ce1049e0400b2bf368f306ef24691b59df22ba61e1245a52d69fa0aee1da3ee38a09a8adec40f199646bf62b8156f36280b
103	1	213	\\x2a7b9c875db9fc99a3bc108447d7023ed8755cf1478b66f2c66a433a7446cf6ebb011d2eeaac28a79aee138b4b44b6003684c361c0cb9aba911f70c889eabc0a
104	1	142	\\xd03c8c0c49c126918cda385b76aba26cefc59c08c52f84662f3aafa6438ee2854adb14fe3bd9d1e0bef55ff3f328d6d5945282bf02c09c50b2dedcfa9030d40a
105	1	247	\\xb3b7d34dd369267bbbe924c57529ce4c3d89d484be0918a4c7a1423e7f5cdf2088e6293e848396cbbdcbacd1bf7f665af98764ca2f1683527b019ae7d3bd150b
106	1	407	\\x304e3d26735559b5ff650e41eea40c9b22af16eef17e18d540a6ada456ff6ba2db7864f23caca39aaae5ade30be0cdef630609759cd67b1d5f313c5dc414fc0e
107	1	283	\\xc6aeddca55e1564c0816d1bd4bc508fe965265fecc351db70525a0b3cbf3fbfdd726017e93d8e92cf9b3e14f465ebe7f5a00f0fbbb61943a5296f6dc361bca05
108	1	123	\\x652fb2f2c984cbbcfd3e8864088e13dcdaa6fbd4bcc138b117e27ec2303b4ba3c5a2c99e52e78a3e37c898ce4ad92114a6ff673fa3a7ece26945a60f6e3e5f0b
109	1	415	\\x9bb75b3e829a764ac362490596e0ab03aeada32a766bec3e5c6dc6eccfbb4cefb2bb3cb9c454b40a95c0464fe7e9792312a3efc406475949109de429c8e34c0d
110	1	3	\\x4781a3d23dcdb6fc5255206701e4115abdabb61e6838f10b878d15bee097b855a5c68b47160b007af95e542b2ca9baf0f358947a0a7eb538d0b1cbd236b7990e
111	1	319	\\x6c42ee0f850af83cdbe927c0e9765c369ac65055fc40dac345abe3ea345dbce06bab82fbe293b8e7eba9bdb6468ccb9597ee9da3627310184d6ed540f8cdbd08
112	1	47	\\xfc423af29fc4668134cb81b517386fa8a3a945d61fb3bf02c2a00faaf311fadead8d4f1cddb91c73e1909910f034b37c2932e170ed5a4c3f33bb5a17e305cb08
113	1	43	\\x4a16d55b3a06ff962bf13e7cb0d4dd45fb324bcde840ac7420af5e2ce760f1bfa393f7a295d85a4f82c1decff3da87f06bdeaec65eb1911e354d0bff3aae2d02
114	1	373	\\x39f6ed7e42c84eb2afa8bb93a13e62d4181a3276342ea1acf11365ce89b7a444c62ac1d3d52d8cfd119f1642641fe9d51d23c97912b49912aee9df8730c8b901
115	1	39	\\xb12f176aa2519e661bd07c1c053d0eff00ae6bbb051aeace5f17de1b8f4907134049954e881abc60b8c5b9fafe13c05c3cbaee2572ae6269910c8b781ff76d00
116	1	399	\\xf95b29aa7002a3a5b52e56305722030a5d10909c0e936e7165f96693e5af38fe97e2b4718dc2517a9f26ef0325f15687fd644508c055d4a7c8f08f33d942a40b
117	1	192	\\xd9f84725bdd89831269c69b24d366d127a69a2db4c1943cf70c4099c048850a5ac17960f3decfc860b458a88ae853333a89886dd9c0e9e6cebdfc640aac04907
118	1	102	\\x990d4311d8b2070c05637997b481ef40fe45c7f82d285235776989d28933cf87d26225d1d15b6d08fa727b3b9bdb013e3dc776fd5752c5214324081738ef4701
119	1	88	\\xe3a4a68aeb86ee7b284fc550d0e8e8c384284b5128762c1acb0d4fd69809d8a8bacf4150320c552ae338ae16947fc00cc4109f1c655d1dc8e68c1d2efba9ea09
120	1	354	\\xf679fc12e0f4eb86248711995bfae718ae4883c76d773a5214e289d0644c50f3f1e7dd22eb779f84a1e58fb4d083541a134b5540826e6f3f08bdb2b1caee8b0c
121	1	223	\\x975a14a7bdbb7cef4045e38c76fc7319548d0827f2050615eeea06c87466d0db3f34a57892dd86c9bd8fcc5f469a632b9175fa0985bfff0fb1e66fc7c4158b00
122	1	19	\\xfe982b6d3afb83b4e8b5f4eb6b4b09e3830faef4072b76518506adb3a02ac77abfc44e53e261ca76df9ea8881994d2c34428e4d5a4bb9c5ce17b51f854032e07
123	1	202	\\x467edcde729903ce2e89c5a23ad07b919d0ce202cea85ba91ecea5674d0cdcc24c06de7a06004814d42b741d98814d29ada7e7e446ded10ecf4d362bc389fd0a
124	1	330	\\x3096b93ca04574566812c7241b9416c72e6b26c4fcc1105052c191e22811fa53c043a62821ba4112e316858d4dbdb83d38f1ce7209010131b5d37555c943a80c
125	1	288	\\x9abb7db979a9c2e4ef37c10d792a13defda67e5ae0aad1afb51087326c59d213f2f0ba77cdfd5112b46cee629bac5cd15efb442f5f326c105a36a67d3469e90d
126	1	121	\\x88c08ff9f356f09734ccd17c0f8c63c7e4b3c71a1a799647ebc9f9af7fd0014ee0e4530952ef8f10950549c7d1ecef0cec39ae773a05bf45c4b010bebf8a1e0a
127	1	248	\\x4955ef1213dcf8d72a29f3e7645455841d7af689614b6373a8fa136c08e5270c558ce4b20b5fd28b4f264a72be729d8de2f606d00457c91dc8221f4651a6b60b
128	1	267	\\x304d3dccaf02f2924402464b16ae546457df5a3a2c7cdb5015aed47d1247506d274c95f545b3f3e5433a85a8d630b2eae69f5d1f7d0d8f178f5a75a152a47203
129	1	254	\\x589bf843072ca4fa7c12140e60a5bf6a2f8f6b941802cee0aa71e1ce758d6a4e4fc78a839cb7f6b24c531e2363d0d3a65eabd534b166f929a7dd68ce68bb5b01
130	1	1	\\x35eab0224fa169c1d4d187a424a928eae75377fbdb5dfbfcdd9987dddc8f6cdef8aabc1d231146d1f2597cd748a6516fee17166d3a36fa0e3ac34082300b890f
131	1	358	\\xc8c6df2003432dfb1491bc413494cf57ffd66c4bb29c04164c12c02a711c38db0b4f0a43448aef6487fd0c02b1dbabcdbe55884515b63eb77d01c4fdd406b90e
132	1	66	\\xcb79d33cdcda2758288eecfc78e3685e5a91f83295141250ee50426ab2fb8284719b1010d074bfdcb46e246abab82184ade2d0f86ff79b542b2e4bdfa4194705
133	1	356	\\xe4bd5a9dc7c9a508129d7aee47eb73ce9dc4beb75c3567ba59428a64ff97fea856f745840404a6e615724335005f9fd4625a0322b48817d9d27c3a3694c51f03
134	1	171	\\x25d64b2b00760694ec525c7bcabe65a79072aff11804f195ca5f3131fb01be14126066bb3be3c955f18dfda0f1c0efb25fd6ab6e9babff48bf7ac20e80d22f0a
135	1	299	\\x33cf015c44f166d3f21d2f0431f7ea8536cd7a0abb656526fff258285af62fdaf1e19dfc20f48b64d189ae9f33c8b96b8c9875188964d5184a59c0733ffcb50d
136	1	188	\\x4d2583ad229d882d59c7bae1393d8e9e581a2618e9e049768e9779c324c7358d7aa220a9ccc09735415bf2e8c140f848b54c7082ece49c6b2a3ce2702fcf4904
137	1	9	\\xea1bfc3b28f6b2617bce1d293d89a7a623de845d4ef9cc78a3388e0b3644bb5fc69f47f04ee3a4c03b2f10e91cf6098555de3f5c2b8619919a270e996a8d440a
138	1	353	\\x261c234263f12f68ee8f2da74e93705176845b33c6a1dfd2a777a53b6d2990a7d7a6cfe4762082a0ef7db55ba261f428edda0d93a6c861179895f176a63ba402
139	1	285	\\x4aa41e3c8bbdc92b18e73a49cf560e9c45d8d67340ca1d57478de64731ea5b0bf9638d936fa0053862faf99d3b657eb0883a744812129d80b563ad5bda727502
140	1	11	\\xe6badb6f6b411cfd738a25d93ab801b35d75050fbc48ae2ec4ba9897d7866564bd5d0fb2a34ddbe3f2d9a19e7597c88811f793040781181d455883ab68a07802
141	1	217	\\xe9b7a0b20806981f834f5a1fea0732e40b1e4b0d4a1ccfa2213c71439a71fe759a2b3c3f080f4ae71584dd2bcc6ad9cb1a62cab1d749bd37e3c7e7e453c1f50d
142	1	135	\\xe36faa73ca2b31f04d6b771edd73235a4a7a05f480f194f3477ebe1522a9ff64b93441470ca63c95530f0d0b876b2bccad10d8cba0575632d9619c11c4567b0e
143	1	199	\\x99e7172e490e169c14eb93feaf71fd02cc8cc4d74a834154fecc6eb2f18a72a328683e5c5c9a4f58f0102247580299ca2404d6e84edef00837ef65b73f37d506
144	1	375	\\x76ed034c4e0fda908a6e204b48fd284a8eaf852aa73a6d80a1f7df90c389ac9a88298e218f22a065a4d56a8e3928ce0e97b1a9c9ff843607168e50bad56d6c07
145	1	366	\\x971db3aace0c3d379b973b380cd68adddaebcb04a512fc59b64ca3d2e5cf4ee54e92f2d20d230e352fc6ce58d400b11fe877685a8589a179e867ac5461d8040c
146	1	63	\\x780e23684ef2ea75274594a345733b853e564cf68e73a4f53dcbed634e29ffb549a2fe0e4968a5c8b14b8dfab8cac60bea8cb5ce2b7766aa029730aa97ee800f
147	1	342	\\x14102569e2ff4786afa6274240c2343ce90a12c1ef256e392ba003406a08887f200e4fd0add9d6eee7f0a5c2eeff922e6ba03f22a49debb3d3a2925f09b07c0f
148	1	263	\\x0a83de42aa83558f78588160432e23359714fff83e71d053a6c99e2e4aa158d7f459fefbdf8ab579f24af4973e847916433adb12a25a799f57418dea1dba990a
149	1	49	\\x362ef17215718961df82fc162d29d25447ab714d129c70953181ac00d1d37c2ccae5de821741abb9882220d3179662ba10c334befb388322bce9b1786ba13107
150	1	141	\\x3f65f81e42419c8511f8eee429b1d9f6193f707adcebed5e32aa90d345eda99298defb48b699f4061f1f3ae78a3f7a9b757df80095497ceccf4c7185543cd608
151	1	143	\\xeaaad5c2f5a7df095aff2528f36e0807ff631d8ad5907a8f8b883576929a49c50bb4e58690ab477adfe2518d0d5480910443e402a67bfc225a9929f5661c7401
152	1	149	\\x21fed6871cd2d2616972d9582fc0508afc71d4f2284951e0770ed92f798e19df2037bed2c56eb9e3a402c629d552e3a4f62724b2646aa0e24f89147f7d169203
153	1	281	\\x3a7e8fce3b9100aae9314f08d76f46fc177f0800792106875b8101e1b6be192a55341130241d468314dfd5f018ed6bff4ac76e105d8e1801e2f7e705aec4a40a
154	1	113	\\xdfdd30136416c123a1ff3b7d01cfee1ccb6f591ecdf5e71c3e14aa1fa5ca8a24ff0410101be56638c6548936fc55b1d47546553254761a31f33b251df63f6a03
155	1	233	\\x0dbbcd7709ea7bc5d0d5f00854c3d9fa64b6645b6c4a5c9cc870ae438f21697715a875a4b58e75df7488beea2a6d2c72e90e758638b03729c29fe8771b8aa702
156	1	133	\\xad9316d30ea00a8f1e37e9787a7ff4ff02ff0dccc34dd0155481495cf8f8f0d09a6f74ec0f15eeddd722f59eff91583dbf68474af2bdfd4d7e3198dca307f20f
157	1	397	\\x5b940663770d54baa64ff6ab705e44907d8c2be049e4bbc56d28b8d336be052f0b21cfd77e549e1ff61db87acbf65cfec486e753dd351bf1b60ace523da0e40f
158	1	370	\\x0f85d3f68639c7b45474eafb3bb6d606cf9723d7865ef231505ff503f54e0f1ad4359375410bd28a4030cbf8abd4bfcbc7f34ca5995904e63f5641b6c3f23f0f
159	1	109	\\x9e33003bf68f2e02100ece30266c61ee45844a7b625b8af4afe12464a8adb327c19c95153291b2cb9518523790b58ba3009ae5cb1ac53b7af7ef252394fc690e
160	1	339	\\x1a68c6572168d0ed13dda375491cb2d31cb588f38911425673032515f9d7f48c9ba34f06b8c3928013c45931676bad4f100a0f2a74c8ad093041031ac99b2c02
161	1	421	\\x5c0551acf8054a78096a35d17655a7feac9f87e6120d7f45d7d999266aba7865c25e1ef44b4165248a1ad3d46c0313f7636933234c1db423aad6786f1b954005
162	1	96	\\x05a36e84950e7a2b4a1aa50ff62393ca242d2b86bb26e7d1033631f51e2a543976427d9e03e4f0372c862aba296e159375e3567701a3a7f949c2045678fdd704
163	1	215	\\xe6c2770e731daf157010ca62ebaeb8e6977296847c3881a092eea15b45ceb0b679c4628f346201e5183da3344f52e43e4783386cfb09817a2eebd06a6b8ccf01
164	1	46	\\xa2a4a87eb9cc1294f6c993b3c4df61763e4d709515a1d0e4eddcf7bfeca628df001e3bce9a391fee58055336c6347673bc0252a574fae24aea26eb07067f4b06
165	1	225	\\xe82419470261816bbf7d5414eb1c6f8ed4b07b66fb761eff711f4739ef8674546231750a6c5ccdcd8be6cbfa72375f9fb2c4527f1979013bf0bb711eaa55a805
166	1	372	\\x01ef3cc828df25eaa200345f8870a23f31c342f5481f1a0e2c61d26720ffd9679c4450a40e3b0a7c9dc2083f604d44c7df450e1eabaccf786cb08b5ce784db05
167	1	345	\\x170d992ea49802abdfc431eecae7ffc15f2ad548f8b0d4692d019321c2c05ea4fa55b6ed83b05463fa81697254bebb6c91061f2a62a231f2bdc89ad7a59ac80e
168	1	31	\\xc75db515351ab3bdb10a767a43f82aa063b4088fa16396b1171534ac32a4a8f17354eaa8e3f411fec68b760525c45ae703d7eba01d7c5e8ad48b00acf6439a07
169	1	77	\\x2025cd58229a394775a313b24f403b1771eb3878bf4cef5c2e4c0998647e73e7fd743bd26e173630f2d80d8a988c73822a86016e69d6470c59f4c011d5ade401
170	1	15	\\x4a7ee90e79b2a954c73e9d1bf6672beb11c07d9a5b4de9016d2bcda1de6e7ce4b0a50c12e7182934b009817489bac2eb919d0d55cc133f1936a5b129af7d3301
171	1	197	\\x7144bc6f4d12f7e1b7aa89bf09ff56a436963e02c1845764e583e0f1fcc7453cbdf5fa09c8ad2865c4e14061be85c3fed66fb0259bc6a2503159b028ff191b09
172	1	53	\\x38e16bd5c96955507025f5e9157bb50bb150eced963b0974fc042e913bb50b5852906d97e3d287a149e345126712a2f0448003d8a7a3a88b35dffbd916ad890d
173	1	336	\\xc3c831cd5360bfa28006eb9ae4945451963776646f1084a92d7a8f51080e5d82be4446f9ba0b9dbe70d5df24c61d5ecf94a711da1adc2e7c35c2037d0395c205
174	1	335	\\x1309d6bb00567d2417a545a6f3f00340903bbfccd479056df32970f9d1f286d28be563b6517f66be0da5a3cfe53af7da15546b5f8c59b44389241ec76a76d603
175	1	57	\\x8f0d766c2568d385ac2732e073ed46f81dfab5af462b8c02d4fbd32a9ce8175d936ac01b2ecf1e91b44687e934eeba9615074a959ff45646e5d25fd74013cb07
176	1	275	\\x298edca83040c0815d2617ee639228dd30ada2b4d4de51caacc63ad4ea867f88beb6fc8524b7d3730fb02c7536b655f185da0f16afb3e633a6a0b8bbead2c001
177	1	26	\\x9a736acb1a6bd265478d0b2e50809c2bf97ea84f56c11fe4f4768710daa6413774832d24e41b42a2de9ae016970e08d420f5aecba09ed3cf664dbff7ba451d0c
178	1	214	\\x4311fa1bb95c5e5e526a8c63184807523f7f56b1c8c34a0309a26b7883948dc147cd2afa06d675aa2482e19955665236a6733cc5829acec5957d749a25c9ce05
179	1	52	\\xae6a04c85e90b69a8249c8269d9affc464b4049175893a013f3bf22ecc96644f08af12e2976edc414dfacfb32829c14dddd3b8422dacff78e7ba2f5b56b2580a
180	1	207	\\x125060bc563da044895b13ae69b5c4799c3a322a8c2819e3b3f569a666dba810cb72280412aaa26f0da486d4443666b247a4e5e7e80b67a7d57ab68c67a92f00
181	1	134	\\x030f47266d40878c1bf87d35642486a1049e1a3b40f40060ca01653c65738cabd1433fcee558f06bd2555805a617a2e073cc63d976e312c822d9c6bb6e00b40d
182	1	271	\\xb18b9512459d9f7da454595b00f5ad9dc4be7013f1bdc4707139a21b8990c7aab06070757b26488fa7569a2918361b7b027d9cf0dbde9d10f203599b1e7d8307
183	1	5	\\xc888329596ecbfb3d07bc3e8ab2225c6556052ef441a1b7c234853eb7e84a3cf561788452bfec8f51e1d0b320a22a607e74857f0feeccc766859015d974e2408
184	1	184	\\x164158037f6a858a925c38d2c95d38bc2bb4daf27b88d96ae157646b53cbf72d1574133671423bc508b239b4b0af1e0c6ac01b943f0c35616889e3d9ca4fe808
185	1	234	\\x7e3d695cfe1e615a27906ee37050468fc347d181e608724f987fd5bf0f32cd2d23a706a100cffef113110ecb67a53bec06acacdb7b44fbad6f5189b818626003
186	1	240	\\x6c8120468a9cc2405562211251664476384d7f80dbbbb7ea16dbd887a6f19c57e0f8193f1f6ca2b99a7eed585ba06dd425a1f5a0b9f9d6642db57f0fecfd6603
187	1	106	\\xf0e3de8191bd895e236892cd68d0ba3609399bdc767e4931388c7df68cc273036a039fcb40a71a736f82224c9d5872fc53c532353241ba7ea93003780ef33d0b
188	1	38	\\x801e416b54d83c1de738229060ba38a4d36c6303ffe04e3a58f3a99e120894dd51739fe7c10e4779fc780606927ef894470fc0972ebbb1121e3bc6bf49533f08
189	1	40	\\x2f7f56715827978765a951f9d5c04acb5ff5d5b5fbde4af6ecf1cf199a6ec368b950787721a9badcf394e0bcc3827d2e76626342565dca4ec9c11bca5a658f0c
190	1	177	\\xed15d32e87f8035c4651f58a22a5f4afc53653101c6f0486e65a428f451bd4e13230acb5a2c0c4955889168f50592a6bdd309fbc56a67f8bf8f9f1e972a90f0c
191	1	147	\\xa1d9865ed21a9a139446ae9292fee596890ec1a556e6cb3172582c7f9c96a6ab3fbf1b8407579460ccfd14558ca3856040bff88c38bda399b1730f4de5a4ed04
192	1	42	\\x738acf182f3f887c98361a416382d88edf5ccf534dc42a17f5067322050aa3681083b11ae775dc8f8933efce8c48d80b85870a83a294ef74a2aed0045281a80c
193	1	67	\\x21143ac092f29bb044ba7ef47aec3148d8d2779b62d7231be2a1c05be9c3d4d91ba3a9730843ab3a686d26ed8405eab562548a73a383dab6d33bc4521f224101
194	1	175	\\x4eea3e21780be715d55881da0e7e0f04ba7af6d4679675c7f619ef412700cde92107e8cef75b529e04fd39fff634bf830b4e7873a1e864d6f120871054b3ea0e
195	1	174	\\x7cf6cdc25f9326c786e8c01c4fe88f83d09befed2e5f4a1bc076db431c47461ed5266aca7150e96e95e6974f6f3df36653664609931fc3e194f9b5653c2ced01
196	1	363	\\xad52475d32e21a281e1d65faab3d6d4931b661cf9e2c7e805f98827786dc27ca20646de7dd71f38db3be2a6f1c59096939b7b62072bdca3331b276562802030a
197	1	261	\\x175ed502ba42c20779051a97b6baef6385070fe09cdca4d6e25d844e3df6fc6c3cacb67341335a08f168b9e1c359d35ad299489673235c964b9f336d8419f10e
198	1	312	\\x5a298c0b3ae3044bd252499bc021e9050a286c7c77f9a8e5f3413edc2056c56d74faa1fb77e2e997c2fe23140e3e73e0d57c69907f0ebaa870ed57a121690d09
199	1	182	\\xe963ad864abcb5c9d0fff8e2e26f57ab550d65eaf04b7bee1ff4a6f490d7f0a9bc2edc99a8e542abfa9c0458b9ff6406f32e000d7a2880aac12a3add03fb6503
200	1	256	\\x6f8d305ccf78a92f7f90e6e67450586dd3d38d197b0657140204db2047eef730e0e5c26a9ab61ebf58b2bf6caa543682b61da34cfb020fa2f3c9f9d87402410f
201	1	384	\\xae8bb8f34200c28ac604a4322d20411aae1412d5fe8dc3c89f5f2d919d089a01645b52028e1583addbd73d5e9a809562e217d2e4897d2c360eb16091a9475e09
202	1	278	\\xfcf9cd99ad5ca55b846c857d08f13884e37615882f9feb541a4fc56db7411f7305f8254306c3c210d28716e7833115a61d8ab3744eb50c26f1c04df646305f0b
203	1	87	\\xed76da2833ddfd7e594ed7f27d7a106b23753f0c56b09b85547465d661559c17c0ad826a0146d121b3e4b834c9eae8ab3059150938febd77cb5af215dd370005
204	1	239	\\x31c5b3c411aeccf0aa62e281cf7e4bb249133d0a1f8115f87d80204dbe842ce7b42a541b605c252f5991ab303c8958307b3178783f59f06a623e742ec9b3370c
205	1	84	\\xce4a249b724d1b79f94da8bdddcb57394f0c8229d964b2f2953c3e50ae8c6ef6f79d7ae61890df3b59428554306683f4268ef7170914643d18bee0cadf18e30c
206	1	99	\\x10aaccd9619014989bf5ffa44cc77dfdc5102fadefafef568f75cfd91656ec881c3ce5ec05b8af78eec830ba88072a60735c98254e96f02028b4e90ce4958a07
207	1	221	\\x1ede24d8e59a2a7230ed117b865ae97a9762081442cfa4bf1152eac4d77443e3f9bd36d77c59029fe7c49bf7c1cff648b4c69bcd8974db4cc66d733611460802
208	1	242	\\x640a7d60c481e224b17186316469ec4d91de7e5a01e0c0d05eb196821a0faae24fed61b2bac03fc88d26e0192253e2c7c81f8d1caf81979ad789891b1b895608
209	1	387	\\xee139bd841d2f94ac9176c261e7b7ac0013cd54e5dff121e9985ad89f818f69d91525eb8597ea692d2e8f338151e07f6f57d00db988faee91744fd2a0a8e7a0f
210	1	162	\\xc87da755c02402fea511e9e7897890f148c57dcadc5176c27d17ea9be2d3c02e2b0a4aca1e8ac6b2cae02d218c72063b5937fc7babe7dd51ada9e305e3087d08
211	1	74	\\x6bd27d83bc391bee4c1b40282e2709685cf9d41789ced415de0864e8dc86c82d1565ebe4847f22eb2b03d738a8434be0de4c43a0904b0743ca9aca3a69a35200
212	1	201	\\x730708fd03a1ef1ee57c440f28fb9768286745052dd9ab58a3b3c2fb2527c1fd861c35f615cd597284c397699e382d971f1c787b8ddcaea767d3b265e0de5e0f
213	1	316	\\x96f825d2824212b2f4786e47a48c3372dad63c644e1d4a68d76abce9dce00a8e855eca74b61774250d10c8f45beedf2a516993584969c54b5110d405b394d703
214	1	402	\\x7e78bb7bf9bb58c52269af5eec0be5a0662621ecf58710f16c939a28b11980a0997193646a29957bea139189308a4f1bae6f6cd24e9fbb09a6b8068ead4b120d
215	1	21	\\xc61c097c5203bd7d1e63623fad566ca5966b4ec1f366c6e4f0e368c2d58c1e20ff860523e3d4cb2b7c02a86d9555e99886932b20c6c6ab896151e8dbd8763c09
216	1	264	\\x1fd9fa23dbc01b5a920544a1687049706ab8448826c75b7fd9eb0065d5ea33668bfad1202b08e8f942ae1a9303ac1a3c7c2255928a0a78ce136999a58357cb07
217	1	17	\\x812976d356dcb6ab994be56c4811b41e0ae1e581f3ee0597f8ef1b8f8ce947197b81abaddfe1a87c378cf658ca2364c374018eceb974c6343b0ee209a0453b0a
218	1	86	\\xee65a3d17a3f18ccf8966a9517b01e6c0206c0fab412cc44528f75e349d3e326effdce57e4ddda3f2f3d0df005ff5c29262ac1c40895aebb12828bfb72a7b406
219	1	27	\\x9c75a30860c46d48dcfa6dcd33282821eee939b8ae45292651a5707b0971dac429d476352769c2372a6abcf55e860871831b63f16348a6ce20f571ac35220f0b
220	1	92	\\x8b9d3e41c456d104d29005b5d251b7a016bdf4f736b3281eb10645ab2d12d18a6a591e2ac7fdf3460dbacba348c2f6b763d0bb1ca736d4ab44dab8499971c007
221	1	338	\\x15cd199d9e71a40a25c6af6815c824733263200dfe4be3e5d62f4b0c31f6c13dfd4c25e417ef6b075772ffd191d1c379494fe86aff581bfe11f3d637f74efc01
222	1	287	\\xef510b871c670f9914aa3529df6f68637eed237bc415020726ee6c1fbe2568c0888f7026e95f56f703de67aa99a12de4e2a3c026d3323d09cab3737c902c5300
223	1	146	\\x78d79e0bdfece3dc8d978e1fd857b9cb8b4b1a418ca32c3bd86cc051390479a156cc5833806023785daf6764ffe5d8c2e67626ee5efe034bba577d28d1138f03
224	1	324	\\x3c3aea552f9544c939f06034a7025edc56d76f30aa1f5c77318e693fd992ea3f62e49f446c364263f06f830aaa602a6f0f728d3ce96726f98dcb8bc5ef10d70f
225	1	329	\\xddf3a0504380580b09d5724bda0fa4360483f0e1adb0eb886525b58a6a6ee8a2c6e0df2e625e7cdc2cca5b0dcd1ea39dd1f7384d0f5125feffb2b496aa93190c
226	1	276	\\x87d97cfa9e655b35781d33a150780b12630c40248db7e6c18973306b2ef3c4aa2f012c2fe769767b839cbad7d48db97f60c49e8702a9ea7751eedfb2e81f4f06
227	1	179	\\xd55bcc5ef2c7013a74d1b6c95ad9c6301837761b96b60568960f9eefb8c63472678da988d07521f26d73a05b07309127fc017fea140dfc015156aec8a723160b
228	1	138	\\x3eaf6b0635bc30b5035f6918790ce221adbb7f6f9cd3d8c5e6bde357cf696099a23d8ae1bb6d673a822ea5df6ead9a0c022a1fe545c623c6efb20a06429c700f
229	1	28	\\xd1ebb06820ce19e2ecc9589a7d285cbd0b7ca87f1075415d4ab2ec462474f37d384f14b0e9a9a3fd031a9534bf71815c2145ca4f259c888eb1be4a1d55be9a07
230	1	205	\\x794e19bdb59b6b5be102756aff37a81b3fef3d225d993927074a5752c693b066bcfa07c0b5f2efaf9a52ae2d3ac00d38c41d1e73ccb10e4d7c384a41dc22ea0e
231	1	68	\\x8479275a8ea8cbc90052fda955079bcf8a62f8a70a3b075720851eb3fbee1b057a7d6283306e903d4099ba6837b37788bbf4f856deaa88b4976badada6ac6c0c
232	1	244	\\x8e721623b1540402fa5db8f12f98dd8aaff5a766c65f8c9d3945d110c9684f937d89959c9216caad28a68da3b8ac2c275dce661f171700b552545174db3b5304
233	1	241	\\xff532577bf208ee996036edfd75b2b6f5410460fae314a380991736e4dccb65b0026dfda0df61952ce11a687d8e44ca907950612f4b57400ffa0c52aaadd2b0a
234	1	150	\\xd77e39f0ad05b048f810f0f71ef64db6827061e2b39d9f79c9dabfc9459e725c0170c75ad7ea4b0a285f949e4ae35aff851147d37059360f68c4e41c49de7206
235	1	280	\\xbdb5f41b53bd772ea2822cdc9adea5a23f155975cb69078f80856619a1df84752fb58428ae9c2be5aeed1b6e8bd27dfa19629bb081adbfbd3502774a7d0ad305
236	1	172	\\x3007238ef1367c3f701d6a554161c09d0c81a9c974cb02963bc6c1bd01149aec65168ee25614bc87d662d19a5fb85a6b99e539b55286de316074752995602d07
237	1	45	\\x5c3ce7e3e17eff33de096ca1a1e8e2ba10ae765a05d88b8d31f53cfbde0c5b16c0e597cf76c1739912b0d6a456b2f8830fcd1de14e3384d1addb361d03af650d
238	1	390	\\x4759e86e608c1eda967e991b1442aeeffd6b0be67134dd5856e5da4aef3dd1a989158c00014aff9f22c544702462ecb0ba7d1930b390be6f6eb0c53fc3f0d606
239	1	349	\\xab97f553639b2ff8233e2114ab82dd9875d630af60b0f2c3ac04bf8c1d7e5053704749e02a4a8eea0e79eebf81a4cff426432387783d8b4571eb67135064c807
240	1	317	\\x956ca3cfad4fab8fcb7bcaff7290b3416c92ca7b89c2ab5886d270870d6b1c70ed4221b7a7a8955064033eeab0abc7d81a966e02f49c20b20571528a06aeb008
241	1	232	\\xfe07aba345557cc5ffcd0fab86149251439fe63fae796d15de11cd0578d421f513c2050e054ae8fa5328a87a6aab2402e7bd0163e5b8502c8251a78bc99caa01
242	1	20	\\x9deca67e787e08cdb900f9bec66671bb3db6bcd8f4f5dda7dbbef7c5d9512e1485b4146d1595de2d8b2d0edd526b22f6007bdad003c7cc1b9a8c197488eb4609
243	1	107	\\xa291695e5908f6e1eda4d9c103cb362b407f57b2da5afb5c7ab190ace977e1e991c0e1e18c1c010f0b5ed8abbde285de93697639d2b0bd1647c107de976d750a
244	1	100	\\xf1b8c5b83b7c13b7d2356b387dad4afb691012f205f23ec7fd4fb826c79217df5a4101553cbc1f75acbf37431e95abd1e9aa056ba1b1a9cd333ad8548445dd0a
245	1	204	\\x03979cb4c6afdc15d1465960a9227e6cb09a2494637a982bdd20dfe2e4708ac139bb5967153d7f3dcb652568d61549f88ad08cef81fb5e5b217cca1bce05b405
246	1	412	\\x76e387bd79b476864626c371e4d86243b93ee475a92751ead06d2b30498a82e1e2284154e4096bf825cf090089ea2af469a7cc02a1094fd5806445910128490c
247	1	103	\\xe9e4de54a8a7688321dc6caf4751f57a2a8bc83bc6c1f9c11a93543e93e16a6d783e2bc81f2bf3e1628f1003ee319d05497bad7a263c19cfa2367205f561320a
248	1	405	\\xb3404b37ef3058dd83ed15c073737d35a9a0979266b5d53a33ae7aabbcc8599aef9967d6ca4fa9e61d68082602782398b029f2bb032b78a86adf149db1d0740c
249	1	169	\\x0d6aec49c9813bf2ecd705c809fb46e30d20836b8421cc6d9285cf112f9eb399261238301c0974ddc165c16e7b4cb548a15aae1389be9b33683d5d5b8995ab00
250	1	245	\\x3f2b35f89315e0ea186e07d5ab5011e07ea8db7c718193142644a5b9149920cbe690121f2be7624711bc6191302b8a601e84140f7ceb1e23d727cc6b5c65960d
251	1	7	\\x461f75d5268e496d6edeaa1682dd790b41e9c540d03f04888aab403f4ee1da33f401e117c602c3662506c9616e2e94ac95b9658ff61496418ba474cc804ec10b
252	1	54	\\x06f66105a4af4f889ff44ac2ee03725894941dbbf3a829a3769ac9343d1a8b5cc5b3ea90737009fb35d0305bf6e62e88c5c22d18515232f2c09f11f64922010e
253	1	154	\\xd7f946ce29ec9785f6d77b6d9e86356f2bf7dfb5f59035ed7bb5b68c59df19b6a194544297ef8db903b42914da1a42679b45f2a1c29cc0291f226d575e123701
254	1	110	\\x12cbdada3e5ec9d9d80cca96b037a249ab397278cdeb944721cc3ec6f906b408f156d36e52cfbbd521b89aa506dd23328d05308ad32ba78453eb9373d4f13507
255	1	262	\\xee304b8fc983d62c5f6f88b7e27715e48aec9e3c5dd96d91ad3e03455d0afa1c0c780027bdc934a04b330f014971faf53ea46543ab2e047a412a87bc30d15a05
256	1	44	\\x757a3254b9e960f410d2c88975598a35860767eee66f641fe9f26cff34ae01640173065e48f8da2ca5d2c1abaee9efedaa5f081fd539b024d386a91c305c0802
257	1	341	\\xe8cc13deb2216daaa0abd343382bc77adfe88bafb9ea95e962241adc340415944d928f615ebfdd4fb685ba6cbd00432d96c00ec7c1a26306868c445a098baa0c
258	1	398	\\x8fdacfa2f61f23011759fb6db3c08f1224abea98abc0b4112e647054691bc9df434562471d502db24bf2b7dd2034fc15072f9133727046dae7d03d4687458f08
259	1	114	\\x482ee29f208634dc0663025ec590566b9c63b40a0fe539629bf3c36e387f7799d300242ca05ee41d5fed61c209301d478751b7ab25df39c10665ddada4f0470c
260	1	173	\\xa050e6a6903c39bf29a7631460594525012c3b038ee547231029f63a361e3ac5f1677219ae4f0cedb8780b054115fd4b584eb4200d6deaabe4235fa22385e900
261	1	161	\\x0af8630cc406dee70c2a11ddda1098d16c9519ab46ad40ca3588427399f8ab5afa60942bffe73a97ed9c1601a232923ee6cb1d13a7352b1ad6eab3026c7b0f0b
262	1	191	\\xea6914993f42c2822b71fef50aba8ebecfdb4d1658b3ff30b9e93e590e14f9dcb2c5b6360dd7c07b8277f6271d1e888bd1486feac89cde23f26a8aaa9c9f470f
263	1	83	\\xdbb58061d689725ec1379e0053c5d38d21b1e782d6ef13e4b71613f9860fbf434f99481562ac12dcb2974c30aeef705a7227aa8e63810386a32c970f4557010d
264	1	379	\\xaa353563cdbb164e2f59a9fb12caee180c40504893a10826f6107e540e516f8b9375850ab35dd1be1d4f7bd5fa4c0b9b7d6226129c436e3a1cf7a38669424902
265	1	216	\\xbb05415564827a11963edcb810670210011a6a5186572a941f780940595854bcf34d5fde110c49f4d452ebaeb3c70680155ea77e09252c7df647e76ba8eacf05
266	1	145	\\x796b39881352c455b9b985816a1fe7ca9510a195ccc97fae903e77df4fed73e3bf592b3f6756041ba37369409e0e07739c486f8dcb46913c02373ff1cfae9302
267	1	400	\\x2e75d6ad4db0d1844af6d8bce91febd5ae7c43a8a1dc08ed078c04fa36f9b053e2d01497ce420de83965090635e3028513ddf50a2c10a44ee352168395ce9b0a
268	1	211	\\xeb6403397bac7a9722cb54c91676a75d33dcc444c122435c7ba38041a705e5a23930c568d14aa1b6591e5472435273f7f7caea45c3d6a3019bd1cf27e3a1300d
269	1	304	\\x65bbf19c89877910b4d3459fd8cfc6ce2068a373659a72bd47b693cdd2f05cb89f2cd486813fe331dc28bb1bf7d187d369500dd3086c839e87591e3af4159a05
270	1	238	\\xf81bd14133fb249bc72ec22d1468e274d9a276ebe7e47f538d79d042c1bc6f270c4332d195032139be59100cb9784717cdfcb81b02435d5abd65fec42f6f9605
271	1	383	\\x467f11535b04a511ee308a155c74815e30f367f365797ecabd23f0a0a49d42433449bbb7e293af37212b8e661db10e8efcfafae27fc3184a58c7ab40b2bacf0a
272	1	64	\\xc54aa6adc2a3b034eb3fceeda8a924c130c551a47942632da9c60ab338ccd705d168385618ea003c842f6fc5ebd70bd3ec17c51d2e9c3096540fe523afc96600
273	1	61	\\xbbcf68a01fbde0ece8b140cfaa7ce7980ef10a091651ed542d7c69680a66c4b70c62eb56e0a0d4ae9be750d650d6e147edf09d7e50338b541c2419444752a80b
274	1	331	\\xef6a3b532a1779974f2b4a15ff2301c13b1dc3ab274bee45a1618980ba359ea9606d6e93199f8061175fd16cdcbd9185872dccca7b0afa1880074bf44e860c02
275	1	377	\\x9fc392c4ac04f805dab603845eb52ba5ced0e4b83a80ac25dd3489d5de0b1dd926bb2128057efa1206a42b3ee1da0fb36ad70bb50e7950fc94756c16ef73ab07
276	1	293	\\x6f14c1e7443a659acdde46067d0f423664919e3b6c4a7965583a54d543a4175ec69094fadd32e3b14e41fade9acbe3436e29dd30b1711166f44f2da8f5ccd205
277	1	243	\\x3df0b2db07de9e5666408d87d3b3c787919b9c86d1a854e6229dd823cd029b980ef41aaa1a54545aa649c2775539c67262735c8c78a8879736344b2b8314190e
278	1	231	\\x4361e8762788fe1e6251342d86e89944e9e5288f1468de75570bc1decb60595d8eed3ca19e11f1e2faa00860d70c4a1db9fd828dc8ed8c01b075e6199dc22f06
279	1	279	\\xf8319d864e553f49001bfc98b7bba792d7951c3ffa9d9ea93e7ec24cc3ef3be64067fd05354913ceae6d7e766268152c336642499e27739d5d11b70fc3cc4b0e
280	1	284	\\x8a720bb78758c9217a07811605b0b19193d62936c6c02322c6e106d56eac193104f9db0685f57cd7515161885760eed31143792e39393ae7ca60c82b4e7aa701
281	1	4	\\x30aa64785822a6705bcae09b148a1492a3a0200480397f4eb86777efc5448df72e590edbef44768fa20b4f4e5363a15e63def23d779d6633a8ad65af51617e0d
282	1	81	\\x599751169934f4582da789e9fc2e0125be30f221c1cc53703fa0ba95ac3f82290678e192ddd5ccccbbad232b81dab0be3aeed938c734a0d2ac7f578bbb00c404
283	1	314	\\xb75bd495fd2f2575a2a74e2e53cb4679a248d47f468a9657ab8530a17616591e8793bacde4b86114e730392b47519c7e09c599983a3d8ca6eed42f0a64855a06
284	1	416	\\x4315340d5417c241827d4761cdafe9ca482e7e7701d8d20fbb57c0c1acf4fb6ea2b5eaefcf3c3331231c7e6015467b99455219d3d83afa8781424cedfb4a7c07
285	1	368	\\xa00cafbfeaab3f7f4027e2f32d24a26755cce696d136e43d334ee9064b884ec8705f11e06592212c8b2ee10ff7245778374bf642a7447f33cc061c163a300502
286	1	310	\\xb2b37e532bb863e3e848d521be9e3953ad693104ebe736e5cbe2ee7362da7a81291e3b101083a9c91f77cfee5a9bbdda414ee086cc9c6ca50d1e714e90d14e01
287	1	340	\\xc407cbb75e253fa9d94a712f87c68cb6c8ec83ed56f879122208f8ef36c8addfbae140551c3045dc6e5260dddb30607b0c787192b9cc84c86804186b2b9d5707
288	1	209	\\x4eeefe26b9b32a180d3971a33705f8b2987a0c50a815a0f3b27205b2ff4a56a6047680b7943216fe2add4059d635dc223e5c4db5912fdd1dfb622b0ce2981601
289	1	252	\\x96dc4055015532a199b06a244e928458e55fa35471927881be30297a0ea9271ce9f0b5c3da7f128c2ee3c1fc98d6cb1e5489530cda2ae2305e56d77675768108
290	1	218	\\x94ded75097df96e92615eae48d88c4bead74ce441214c9c280e34bbe01366efd81ee045df403bf17dd83af2dd3710c5eb9b3917c31a8244eff3295dc22671805
291	1	406	\\xc65b74ad00d709e0f7fcb8796de1eeabcdedd18a15c9f639c3940c7091fd53cb4a15d74a19ca9872a86d97639ad663ca8556732704089f13bfa4163e9929b70c
292	1	292	\\xc19220b046f0d48ee993f30a32100776b48d32b293be3483e9bdf3cfacd61a7d0cd085be5eda2d9363faa15495b11c6ea37cf97677dcf8e45bbbb7443b478b03
293	1	112	\\x734742af872549be1589be8ddeb8fbece9c0627428415e8fe22b2d01bd81ba20f6e3275c0cb315928b53c6b3f0d7bf3a37aacf28804256c389e4919bb3c12100
294	1	350	\\xb5a1d256626645ce43cbcd2f677681be427cfddbc4a17247fb5695839aec1f2cc96d05a543300e88e263db9b754bd32f36bd85d6da11c6cd957b353a50a87f01
295	1	237	\\x7f5ade9655df691cfbc194963cb8a237bd6027e0b6e44029409fac9bb7e09f99c4f0dadae18a4a807bab8b786a1102f97a5942c144b853a5206ba47792b53401
296	1	229	\\xe31ad4311ca4872df77576e90a88f80c89ee29b7c989a36c615f5d6b09dd3c30f99b3072bf9338496ca219c11cba299e4a10c369fb2601007012837cf5a73809
297	1	2	\\xe9274ef9194e14f192122abc2876efa5b49142b2e29dd7cd357af337a1187f83714343dd0af7ae11c5a264ad3e769086f0e5c8e4711f89cc9ad2e48358753505
298	1	414	\\x5c29e8d5779722c9fdf8527e3d57539bd29b8118a2b7c97c3e8543d173222be6be96c1474d693d6a31edca1b956b4cccd5c4c8e0ccab29dc0786bc6ffeb22701
299	1	157	\\x2f37fabfc1b18de293ecd05561368c2b9ba3c43c03b87c5feb4c773bb34b4b9689a8bdffcc1bf8ae0c75c6bfbd155bcd01aa953483a62588cec88d108936e30f
300	1	115	\\xc731daabdc2d15c7a18751125ba258bf8ab7b98829b466d8626abab2064dadc93b4bbaf0b70ddd827e907003592fe64802074257fb9dadf431c234a6e58d290e
301	1	268	\\xca54dc6bcfae350a65f029966c80130116855d2a8ae79043643c025d27a4abeb36546794a0929e9595d06679b7772a071f9cd7bf04828250b3b05170ab79d503
302	1	158	\\x798388ebe86de56f15b4e980f12080f60e4287d81ac8b8ac4f90c0ecb182a679d85d09a680670805ee8826b033487b435be2cf8c43c6c288612652f9850fb405
303	1	359	\\x49a428f150570495ad65c151db8f7d8217ac273609a1c6bf25ccc5b9f34f3c427656cf9868ee298969cfef1545301c893abafb3c77c6ed29b07851054bbc6f0c
304	1	327	\\xd93dbd184b287722de6895dd910f6707b7cd8703cf0a8df12bae458d58aa2099e78a0875c1af5d8331b22721b49a52fbfbf6a193dfab81e4abfc5c0a76c0b909
305	1	228	\\xdae6b0424dea274b01dcb04caaa91559fa7b6c5e7304c212ead71314380bf67d1a553334675fa6f7152a331391917e0789e06808d523cda82aecaf156f89e706
306	1	33	\\xde392f89ef707d71a170852b85637c1dd05406c1dbf5d7da4effcf06b104d2cdd74fda1ea2adbf8c6f559ca056bf0a662a255918866589bacd2b531001a63a0e
307	1	382	\\x0fa817c6d76360f6e88473fd18519166b5e98d6c27c26a8c869736cb04d69e57bc02c4189bd7b139bf5ebf22acf2800f08b4e923c07a853ff61375d6381df609
308	1	226	\\x25883465251510b0465597d824c3ada680c127cb58d4e6a60af09ce62a173962a9bf9ef6178a888f3b4da9bcabc07e1ef0c96f985cf0320ea44035a9f0ab4a0d
309	1	55	\\x7c7e5928be6e619428ad00abfd977a7d33d8cba8eb735ece235f7e70f22a526c54cd88aa9c385ca49d0ed8cb1b7f0c1c352a0b1adefe8de1f2963efd33504302
310	1	62	\\x97c0cbf30add207f246069b7b8cfbe6b385c4b89d39217a5da9c6dd79495f3a44e45528b68e6d7e8c23f96c4119b94e35ccdefe467e5b46ad56255816b735b02
311	1	395	\\xf1e49d79e0c50c278ea38c45ce1ed9e804788d4e4a43bfc6dfa3becb506464b5d7f574b0f1e9a47edec8f16378dad68908801d1b8223f5d0cd8300a7ab2ce201
312	1	14	\\x9bb4203253a98d52e692f567e609280c59c2f6fbc2d903b7f9ad67c979b92eb5aeb80b3fe8b5ccaa4b81ab302246436e5f88f5813d66f180dc96eb6fc378230a
313	1	79	\\x14d7f395aa1963f2c617980cd77f103e7e76956ae393d5cbb39ce1c5fbe292029f292e881eac764c063f15f8627312d5a85387183296d53977aae540fa10a206
314	1	394	\\x20e1ac40d8d22d57ceb5527e238cc827d4894a5bd7aa77263a18b58c939c69327ab37221175072b2efbfe17c3d9005d8b10415945653ed590dc1f78497aa6609
315	1	265	\\xc22b5cb26dc16e29daba3a04f6271d9a19c4fa998c8a5f0c5505e322faf7d3286c29adb1a20bb055ed32f4531589ad04ef88f12d32f37fe715565c885fa08a0d
316	1	120	\\x9ba552152c098eee8424bf855f64def3c62e0dc68efaeefcb86e36146f8ef1bdc3a9bd99a390239cf3ce64a3c27929a38533ded00d2fcbbcdb4290c1237e3209
317	1	82	\\xbe8ac3a8faa778b529b472003246000f39deb98f5c91ffcf8af68f0d488dba2e4f8ce07169edcbe68ca1a0fae07e1e43bf26245914d36a45c280c04102f18e0d
318	1	227	\\xdde00c8b8af18fc263f14d2a2f5739b2c8a8e3a0f82b43ceb52f092a00f7955a40afa0323c67cb1702d1cfe87364bf992b5d6b273c6a49c9d92cdce5d9e1b109
319	1	251	\\xe9bbfc5670a627b7933dbc6cf2ffcfb815362c11f9e9e13871012286f07641b714b677e64126d688452fcd00a5024eab9a7031b10b08dee71970ef194a791a05
320	1	326	\\x5b4a7b80436a5e036b2957a1142e79f91a31e1986aa782ba9c6cbad409da6c64c82279a039eb4843565a7cd8f083cb92aec5cadd23403ea4733f57e79365db04
321	1	381	\\xad4432a64dc9b9561453bd6645e8d99a470e92fe72b07224f7e025cab1acd7c8336f878b4c94c660055f865a68423cf85250317579f4febdbc832e3b5f68850e
322	1	302	\\x5a238a0f7ff1c87a55846bf2c5a24bd91b678e5da5ee87faf79d6d063a66f36c0aa1b57c86cec7bce091c200565fc0d397fa713f407a7d95b23e516ec80d2b01
323	1	108	\\xd6bd4a971364d959b6baebe239dbfbc033fb6aa65907f52d448d697743e271fcd58a62cc943ae90b99f62d88553e1e9954d90e2134c4043fe2136347f564420b
324	1	290	\\x9d443a90dca15748674aaa019a2a2814881254042a10dcdbc6e126bea84a45a25ae428ae04409372fb5a635b7dc3c947cc15eb5974abfbf5b0c07e935f7c720e
325	1	277	\\xd39b171bd7482611fecfa089416c4f0ef93f04f1a005d397a6717c8f3132e7a1625af823617cc9dddaff9f121fe6b3bda1a6276a6e3efa431f6ae5189d02400f
326	1	144	\\x0e427b3848beca7c3f2c6680b0faba6f1e8b915f4f5201097fc6636fa36bb48e41d9acd8bc74122181c648d13e103eb382a2044134396b6cfc953190bd080e0d
327	1	365	\\xe24ba304a6cf2335d982ed9aaa7dcb5ba9216d06f796a990098e84ba4dd7139f0006f916f3fe96313f83004fb070b87e236902cba9f85b9a73a3ff1a77c7f806
328	1	393	\\x339cd7c4c6f99c07c6ff413a4b1470eb68591df12837fe4f948c872ba9261147da22adea1834c6019a2422cc87482509ae7e9aea4a5d7e89f15b785961096305
329	1	282	\\x3f5116a4f58c06e6db766f9b408552aae0a10a04b51ffa763308769e4a7190c73b12a5f383bea0fbc05919c802c7d149ceb3ff3d6e635a6061e181be89c6f20b
330	1	360	\\x7fda49312a82db28dac9867fc384aa117d86c2f87f74c8c64b775f1adf2e0db61f7d62fe46601a51dae60cdfb1e5a54676f6007f2bdeda0f3cc8ff8988c04604
331	1	85	\\xec668c2d87b331d275c5b8e0700fc9de780542b63a04ca98b5c9407c3eeea9e631d0b1614b8a6b1b1647715e1ce3f448d7d3b94b73cd00b97b3c219d2886d506
332	1	206	\\x28003b19bf451d024b294141bc99d52d53c498026b5e156b58445f9633c1d75fb76d3ca1f5c9990251bde1c8aee3e549ce8e67443f6ecd488705a49a12b09e04
333	1	296	\\xa4e94ae44466ffed46e356ac14f298d12d5497ab64f1d612007c070d021677fd7d35fbc9ec8fe1105ae87bc4d9faedaf3be039371fc6c317d8029ffaa82abb0a
334	1	59	\\x9e1239162f1fe8df49262a396aec0d54fda376072f571d9b0a4e24bdefe62d40024c3ed045947f903c228da678cb257ead3fb4c8bd53bfcf349fd5b2adb43c02
335	1	132	\\xc391da66f62437f9b97f6d403beceb406948628ac5d66b1866e5fc2837bd9ac86a3a8adb5cd63ca1885cf8119871d566dc2026892c1fb619b6420f159597df07
336	1	301	\\x5759338cae2025ad0e5cbeb92c685b363f6f22891a6e5bc4847617575e04fcabc8b113d676df66cd0d109d7039a0a2241092565904cdb77f364338f53662620d
337	1	300	\\x76dd2649da71b567acaf15f2f1c6fb1800a404d81ee12d1de7c5fb4f2f448d26261cf76dd55f2d3d53776799508d5cab5d200ee6c5f48a34db2607287e37e700
338	1	35	\\x6ae763b3b946ceeaeb03551f7a9e8eb992703e0ba8da39610d976b8666af8beefb29889438a26ae644a47de3f7902277246b4d1caa80abc44a4a8b0ad309070f
339	1	69	\\xa82c0bad24a016eb3af6938b5257753b2775864c67865ba531e9e706dcd5c4604b553a527823b426f8a9c2b7e2b5b5df91641bde5c12cdffe76621532e76ab09
340	1	168	\\x159ab8d47874e8c66cefc286c37c8d8faf90307752b68b3a01255a944654b8a725c079393db12103f74fdf8ff771f1ed305641227f909dc459c8161a1b8a6f00
341	1	230	\\x38a52a7fda760c7c9bb61d198a4b8af3f8ef33a42f6b99a4e48654581806da0668fdc12e6b0c3319161c216c83eea5f1aa1b32358a20ac88bd9a8e79f02a530c
342	1	274	\\x3e9a3ad50ffdb63ed02e2d14e53d8dd8b0229c7f95e31a477f6935f3e25fd3f01910e25481bf00ada9dee0ed872c4db2185880205e649152fe02ce16701e0107
343	1	386	\\x82bc63aeaaeeb9f2304697056412f0d2e9e36e2622d1ebc8411afdb21eb69a9ff3581b539be28d2c53f9d00edbff33822a7cccfccaea65ea777861a82a8f9b0b
344	1	424	\\xe00939c2180a0e9500080380497b983ffdc0dcc3e5da9740b23e5a848e637b5120d204b4b121ee9dfc8162c1861ff17654779012bca89ee4c55231c8bfde7901
345	1	198	\\xcc5d448dca120fd757ef9f30827e3207a8b6fe27c2f637d43bd761e273912110765c6073ab9f4e205576590e92e5123c247b5a68e93ce585e46716105adc7a0e
346	1	136	\\xaae1ef9611c54af0cbfa62e22a56a658726c4246351ce9cfdee7b70df9e97ba45ccb31d74334be0aa406ab4c93f0459996123010c3c1c620694d7ea44b1f4109
347	1	408	\\xb6d2c716fdb10a840e33ef37e36de4f66ccc50ea8f460c21c76af6ed1ae25671008a251837d1e47f6e6bc16ea3673815efbd031a452a69e09d89c80e50fc6006
348	1	122	\\x76a808e846c20989d6021460e25679a4720f47d3679c19c47981e2fc7ae988294bae36da7f44f7510b9e2112f268af145e1626b171fe6e7a92e1680569a4980b
349	1	70	\\x064149fcf6eab9e36eb8c3af84a74e951581d2aae604976b1b01ce266b9bc91caed74656f4be0f2ce2a9768843462c0ba7ee30d2fe0d24fac4d8803cfca80606
350	1	119	\\x9d09b1904bceb20bd6afc812465b310edbc5bb79126831b1eed5d5a119f1672875b2a95ba48375bf3230170720ba30530524097be77fde70b3c3b151e26ab30f
351	1	60	\\x42dc91f9c2666480a09c2f351cea7056cd17fbdfd2ad9dbd52e47904c087f93de6893d7a786125a7a4f801588e134b229190dd73c7450770f41e51a300825f05
352	1	422	\\xa340350899bb926310c6b62703429191d929c0b52e9c595426bfadc3cab7fe023f6088029256438e1874a337c6dc0092f499823e9a858c92078af32c4394ce02
353	1	170	\\x1b1ed659acfa6cc565a5a8dadfd21ff410d11fe2c434284dee2f161c3407984e247ccbd779af86b189508dd914ebfb8421182ad608ab346c8fa2ce149cfa8a08
354	1	10	\\x44b928c5f5462853f1b6a24d5635504bcb537037479cc156e37fef840af5fea18fe074ce17508a95b532718817e66aae2c5aa3a89e9bb348898a1054ef2de80d
355	1	343	\\x80e1ad549bedb98e540c11b5771aa0f42576e002d709ec6da25c4fd4d27368217fea37b57748e6305f525b3e5a11ffdd1578393accc8f4eee206716b17e7df09
356	1	403	\\xee605aa78349cd6c512a4677e89dea77a8a02165284e4883bea386ae9e5721bb25cb6f4279e74c2efe5c681d60f9db0ba7de038e9b3a85877c05c3485d70f205
357	1	413	\\x3d4070d2e5c53137d9bd191f1f121374a86a5939fb5c807820f408f5d427fe7628114ca9b253fb3a0eeec9daa85b01f8178f79654a8a40d6b4e4396b812f8307
358	1	333	\\x854fb3d5173d1814790b7a56e75f39a321aec8e7e15fb9b9314c63ceb82d1e27af516b51182a92f017347e994058c14911073e3221cadd1eb1902cb4a475820c
359	1	50	\\xd61a480a21c0bf72653b15cdff8bc14b1a37aacaca8ac04e51449525dbaa6ad9e7e28e86db9dea532bbe91cda2171aab25e6074836ed433af8cd9c5e132b610a
360	1	374	\\x9e089da73072abdc811230998b389b7d4c4bd4d5f1db713f921207ee567f12c2ee62478b80613fdf22f7972582035632ff8d5da59bfb2d7c07b548e9c333f209
361	1	423	\\xc071e72012770b26ec580aef263de4a3ef6a6d778d30cda58159834d093bec6ef915bba9dcbd6fb3ffa15ccf441aff69e664676c247c538c05749e74b5ccfa05
362	1	58	\\x34d4d678846abba094dcc9919f281907b0f23dbb61627a4a1d2780ffa88c18062cb816912f1e0c90e38281581cc9950c4a09886377ba85ae7705f191139c1806
363	1	351	\\x5646b7716391c02f164329a1096b7266f4945ca52f3ac382eacffb9d3a707348e9d248129839c697a8d9216e435df2e617fc46a70f105d176032a1b9e4bb220b
364	1	32	\\x202212e550749fd4837c26fbc0d8928c1abc03d63e8576d0c1066d13c4593f55348ce4a335f0214da43613635f3581c022fcbaf10b626ce7226873ee7f3a3c0f
365	1	180	\\xf5129ead625921a96e7f757786cd237587ed0df06a03817fa1a5262cd771c880766ce77d3bb981d37d62b6c2e831f72278608f6e62c7e2cbc4f7e2c93e934d0b
366	1	155	\\x4d00d2d66f21bad3ae8f6efd0aa54299ac4ba881978d570f5c6187f8167fb7d5109102220d104f6479b9be9c0b636d3fd9ada930f2af1e1675e1ee555d184704
367	1	305	\\xf3d2045d4722b4ad5bbf9210b2cf0da50283c7300daad012e50cbbbe32e8946b524d176615f30a40792913e7014362a985bc68d791b99e2766b666b50d2ca602
368	1	167	\\x335a5b17cd2533fd18b816d9080b54ad7764a9432cfdcd0d0859a76fa10ab7d8b8239c38910ae38c8b4714a5b3f5a93b06b522695256f8940eda92da16e8370d
369	1	25	\\x71f65e0a7aed01f2ae22538b0f9e4d8f30c5d71ea70f4f4e2ca536959e193642fc8d2e36be59e6cd84c17521f2487af568e6b78b7f6a7cfff15cae6f03732e04
370	1	166	\\xcac864533375700701fbe62b4ce69a2cf99a68017a303b664e745db424fbaef2eb9fa2738a749402049e986f946c200ab9093b7759e0b9a96d8b5e0fffcefe05
371	1	392	\\xf36d1d2f97827a67ce16c4894ee2c707a5a5881bb57b0cffc8a0d71795f15b77403e08ed203d1bbac12f096c2e2d23dffd356767fe46e2f5e0524a422901e50e
372	1	72	\\x5c7f0a91cd7653b47a6dd4634e51ab2ebc344bd5cbe19640250b16c6fe78888b416ba5e88dcaf5b09389c4b4123b1819a461ce85d2e21549c8a13866aea41706
373	1	348	\\xb82e19d580b0216c8fde67c0e2d266fce928f1e7d93db950f3ecd598827850f598d2c93b01f433ec2cb97879e44a4f85af4cac5235b116a39d1c6cf22eb94b02
374	1	306	\\x26b6deb8958241318c2238646c03de0719bb04202c0c5c9ee0e150d6d040aa415a9589a1c2b629ae6f7a13b7978d64224a6ab332c482bfe08e86c0b66f865e06
375	1	163	\\xaaeb2b667ea6902abf45e370806b5dc258f813717bdfb6056a44dd3b49e22f3d785a7df6f099283bb349a56fc65ebe6e9a37616acfd31ab482f7d498206b5804
376	1	12	\\x1864dbaa646a5b3448b08779d26e2910807bb30c5080127a641a5b5bd315634ee318739d0ac1eb4ba6e7c673f5f79faa894bf9fb8cd6032585a077629afaff0c
377	1	75	\\xa03c80d2220258a1f5bce24c68615f488a3713c94fa968909c29462613362e8f11548742f65c068be5710ae0ca676197214c131e81cc864567edb80b4d827406
378	1	258	\\x1ab15aa38144f3a132e8a5d4cb38020908ecec816111a9a1db7748242b5c54918af2aa39c7a5bd7e33292b2f90e735c7cd7d228deac6934504344e8544ade103
379	1	321	\\x552c31b5247295f9fa19b9129d73c87d4d28e2d4259bfa638941691d204b2013b26651abbaf7c250e0fb5dc033c52fdaf152bf384ffdc1f811f8fbc907d10605
380	1	210	\\x7edfa1b65dfe3aa4292395f906fc3f415484662f74d2904c76ac81dfe618815ba8277942371af3ff4591bbec9ba0d471f04ba0c5e7b2b0f220052a4e0fd8090d
381	1	116	\\x581962d3e3deed02e8c1068445a241e64b2ec0ae423e0abd8dfec3049997cd8b388710e12fb6814841b726a795de5c909df82004b9f9c343b3af8c9de1a5b106
382	1	272	\\x46908037ca34d953316f5adf5a122586ad771f244e5bccddbbbe7cbeaebc6cd307e9acfc1c3091c8fc10a07210913d3b1d43e9d63b47e7981ac074a2d53f5607
383	1	193	\\xd58eb8a68bfd6c42e07b719364bcdadbbadd66621825da8bc4e2c575415d53c25edfb37f6dd48522751d110fefb73ba8de6b8ae0b1d5c99db9758b2f746f8409
384	1	396	\\x68456a8edbe9c9be44eeba0e41edddcb78db79c67fd5e6a96cde6ebc3d5a85de6b14156600c023e398c53a819f069ddd962db2e4259667598d8c6bb1f5133707
385	1	323	\\xf68e81a8a7ff72bb94504171597fb4737883f9d3089b3d47c598d025d5e1cdf15bc402cd8012f84f41626a9e6f7966a603de4b1b2f0307c5d07c71bdecf65d0b
386	1	257	\\xa428721581fdceaa244c5d14f1af1603d04d7dbc72630dfbbdf2ffa0861a3ac8b53b2e1b492aa0510a273a1d2aef079a3f8a47399813b07bfee0086c536d2704
387	1	313	\\x7072a988a9a7b08a7e800c0d7953df335ac878f90d7283de5faa157743d4bb77be605f1865b156165971bdfcf1eefa0e224bd93d10922f89f9fcae8eb096b20d
388	1	126	\\xa8d770b62f02107c17b20dc2f8e0dabcc6813bf5c6b48ee3eefcf6ea72d896c30ffdbb100190c7d300eb33fd59157399769040212aeef84d8468072df01e760b
389	1	65	\\x3bb0ce6e710bcc1ef91f74abbf997d8ec7e9083f8fa8115a372d69e9eb8a2aae9e1119cafdd4ce6e0433dd0cd94081bc1e4f4d736523684a65b87dda5b0c970b
390	1	187	\\x94aad84b6a1abd5ec145b67b29337a6a09b6277f469dc4af20963682428d2f44071ebab90bb6839962db57bb3cf36ffb06188dca042cce7c426c7d6b12458403
391	1	22	\\xdc34e9d2ee811f78c512f5e0ff6c3cd7067620f67502aa06d639fccb95342e0945997789309a2ae5d9af8e3fe3969ef6cbd19220360e2a8a0783b9ef6e629406
392	1	196	\\x86da68f267900034ba3fb4967f457e01f0f8b16b2dad04b6a5c93a95a6bd590d5405f1ef38ca0888b62e53e89061f8e497c128dc930daa65b3520def1b9cc70c
393	1	364	\\x9670a4525d79489b4b4cc7aaabf90f2f7f99ef0be890682bb23004a08ef464ad0be0de732a39e476ba1aed5940a376062ad39a9b9127d12874b32b1233fefa09
394	1	24	\\x943f209a3bcd932ecd49ab6c09fc023f9151d846080fafa42629b45133c91374c6ca864e94ba186724d754adb70213e7984862cb0f457c30774637108ce28d0d
395	1	378	\\xeeb5bd6ea96f00a15fae55be93f3c251dc48fafb1236a7269c53629c3f78f9720d13106118c587e6d0d48617357fa6a0ff3530f4e2cb62759be0970f0176270e
396	1	89	\\xca5c76848e3a006e345bd0f30562306a606a8a542e9e5bb29f68769a2580074d732047215722b1747a258d95b15584c521795ca9f00bb24b5bffe4d76dcd6804
397	1	124	\\xe2604aa0b51be31072674ffe48ec5cc2e3e6aca12925d05250c1bb7b5aa752751b4e38d5450fb652ad112deb51310fe4a5533486b6640e480be8d5d5f0c49f05
398	1	307	\\xabcfcf6eacf9a4dd762ccd81336232152550a81f90fff33bcd290cbf8f51df16a63a89bd42b947d8242b751f8a6afc40ac2daab1f8c82c9471c39ad72cf4e905
399	1	178	\\x6edd9013df013c515582f39b920d3f0444a6324df6905dcb5df12c647d0742885d9cd39f4ab5dc5987dd44aef8368c8e0f955cbb2c9f1403517c29673e07c30a
400	1	361	\\x883c02b085b1ad6ee2cd3d924fb8bdca2bd09a7406470ff5d2ab35a0188821c6483d31a94c830697565e134660ee38ee4a67a60b9bc0636b0af4bfd3deb53e05
401	1	388	\\x78706ce298a85e748321726b7203844610059fe7d38368feff8337a15c4c2846aad37d335e254bf12a936584c095c0866a981f2c4d3e9b5491e4eced2494fd0a
402	1	186	\\x362faa7be54ad4f3b116c769d01d9a34933a60a9d1e3bbdc02b90941ffb78cdc4a4680a58a0dfda2f3b7156925105f247a7d01aa162a0545281801cb15aaa60b
403	1	303	\\x2886b0eb7154d227fa3b68470042473e4ecc52d8b67cbee119b2ae7e52d6a1369bd6ecdbc237d260fff6593b975b08a5669fcb22a7ce62d1a7d9ccb4ff19910b
404	1	367	\\x8e60a180bd111baa56ceaae37027f2e78d60ea523fa297d9415f24da34f720a443912a80596a06c2dcf4cf1556dc6822a8dfc8ff9657a9092c53860ae62ec90f
405	1	224	\\xeafe4cae716ba1940c7a416aacce32a96a53844162295d58845ba17ee20a7e79da03388c682eab46c71fc87ced42804cac9fe3943cebedf5151b0f8574665c01
406	1	371	\\x2c80648c69e1390a6fbc5299512232aa61aaf8a06a459e7a0bcb71d2e7606688c2e0e91141b8138c646a9b3fe0b9df858f6592bffed905807fcc17a81069100f
407	1	76	\\xa70787fd172ba189a0d991d2681f9cc2124a9d2ad4b40b71f4cfc0baf8402f595335186573b4ca8db079cf6210f88d2d769276ad54dfff88950223e04903b00f
408	1	328	\\x375135a0cd39aac0669ae751b451b8ae2c128f23015f24f81ae7ccf7126ecd2330e96caf054003495c0d44d21d98ea57005ae9c7d170cb2d45ab5462bc15a706
409	1	385	\\xdea0bc5dd12d66a1c9cd8f46cec8beee1b60c95f46546a8a108e75335e2308fb0a041c99eb4dea2a01632c35869462a64b3fc5624197d3a0d991f90394fcca06
410	1	23	\\x562e7b8d5b313699ddfef86c8da38eb8a9a1416c381b8ce95af1183c60dc29a71aa5f0db5f52d93bffd0845c5ee6152790284d3f721dbd077c51f2bf1d6ccf03
411	1	289	\\x1c6c0fa64144a0628c643ee987c811f9ed6e79751e5a67bf1dc5d6ae2e94073d6f2b7709c842c6e164645e60327e6903c061e5e8a96122b55ce2a165c879520e
412	1	259	\\x68f2a0308236e8a116fb6ca6d8090a0f7886bf43d9b99ce113e12f10b06390dfafad665954613c3236010142f655af198375b3e761b2d1b64815f7a995ef9300
413	1	246	\\x2d8e502824294bc00f69c1d587c398f4ebc36663928ad6dae375d87aed724277af05d43121fe697df5636abeb0124c81d2584b8c73ccf2663e1c20e4308aa404
414	1	401	\\xfeea0c0892be62f4b01bf3fd17d8b8b73bb65e2ae0642738962608480f03ee26b4b256132d6fcb16dee476caf84ac2c12f50b479220a311269a93a62a820710a
415	1	409	\\x00972cd30b7c0620e43413cb550061956e5eb39a8a23c7847a9690ac079791453423f497762f4a7168782d9c9bdf28bd9b53cb25d4436052f72f8de73bd12f0d
416	1	332	\\xdcd4e316ac013184d1f4aa5b4d324efb0637245d9b3b17a9150cba91941a271db2b860e57f1576f3bc8e20fc44329cc468faadea98668b58e9698b19e903740f
417	1	190	\\x1554634c5ebc24f8fe3c0ee7b2530c2347ad8b01d1056f2ee5d792042d37f988687b760ae6d1a8bf634771606054635ee90de784fe674ce3f388536a34babc01
418	1	334	\\x917573b9c8c2758c576f2821e416c66627d036997c41014822010103639597ff3afbec013b39f1a815571efdacfa980183f1f11a1c678466b9abfeb311df7d0a
419	1	208	\\x616318f190e42c0914f30d52833a1c40160c8fd817434b38ffec7c1f7a02f874554335d201a934d1cce9bec5c5b0324bdffd66eefa550aa3b3597fb2f56aac0e
420	1	156	\\x4987de92be3527600ba658a922325964a6fcfc828f4c2fc486d848a494fc42bec212de9aa0e61d4b73bf7cef1eb64099e42570d3a0d9c539a808780977220204
421	1	315	\\x2453adde86a800a39c3649c6cdbdcd183f5b7a895ba6540734aa895f4bbe5b55f756212467685e4c8464814cd418a727970986976faa0fb32056f092885d590c
422	1	291	\\xdc8e0694a861f259008a40b3f42ea8014d7c02adeda9a67ccf0ff55ddafe43e21365f51355579bee7bac0867ff63f7a2d8db5653c738354dfd10a33edaf2dd02
423	1	344	\\x1006f5efeffc4127791cf50d6bbd391ef98bdd95ac1dc0160eb36f4cc224200a792e25bbcf9947482e8471ace52c384c4468d3e342567d2b2ee1b749be27ce04
424	1	352	\\x949923489f7ebb41a009b4673b516d1ab311666e98547c33d05738b4e587d4f5b52474dc6c3e1777f83e8d2ddfc59778a92a3ccd37283158b0c0eace97d83d0e
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x5923aa475d5122795ddc6c3f5028a04ed430ab726521c3a8eaa26e01f923323b	TESTKUDOS Auditor	http://localhost:8083/	t	1660496921000000
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
1	344	\\x2b18f11e18649b8e4065175bf1f6ec431a9fafb8696b564d3b52264c2d47711ea5ff3eace1440105fa7a2905e9ac25b2c8420155bc9d74ca3326c9155edc520c
2	259	\\x6054ce5b7c9212b70a6f07659518bdf16d1014be30c83960811e8df920488df05b6a37fc2e5c455e08014e405f3869d1c6e42b55ce4aba5228fac6322e27ab00
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x00ccb087d885c52b69b117853c7d44a616344afd1a5f0963a87253dd4d8f7022db1be0d2f3db5d5d42d5a95d7a134f9a61b636011a6168e2c31c5266d9f63eb4	1	0	\\x000000010000000000800003a3be2c7761d894aa3325326623ddb40b70baa2cca673dff0ab95197d751b0d179d89e253d6efe36891f5055e908b1582c7e0856a742adc7cdb3b605139059b127a70fb28f2d111e27c08ce6afbd357f7c73db4aedba3306e13e25a38969c9a9d3c86cb60c1319e6be35be25c5f07cf0e42b3db9e4b69a65403ece7ca42ff72f9010001	\\x85d65cbb34777454a1634e7244672211989f486e8ffa62c753c1e997a431da8b91862c3ffc790d0ae2e2b8f6c6aec4fba29e33eb388211849c8229723cf73e03	1682258915000000	1682863715000000	1745935715000000	1840543715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x043c34f08ef18e427f20fae4974011b42f688100ef428192687fbe94324e26a34e55c0a9938252b4b3ad0a3cce8149855aca8bc6dd2750192d235a15752175cc	1	0	\\x000000010000000000800003e415beb026b8e169cd26e58901b5af314301863c76b7a9dbdd038aea67b8aa0dc86811bac71860f644038199dd0eb8ef049bb1a3173ee288f4038570fffa71799515d4812a9026270b03a146de87cf0afd043f527722c85dcfbc546f8cbedff6085340fb4d8a2674faae69afacc8e14684f9dc3372e132830e107a567ed01135010001	\\xae03baf0a3afc10edb3486c59dc91115f16a6b53044d087ef4208f01cbb6cb6e5dafb6f3ab42e84fcba286b20753f6d8b1ee1680701e141e3afd18430fec6200	1669564415000000	1670169215000000	1733241215000000	1827849215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x052ce7be8605e1c5b98b13f516442917413fd96903312d05ad0bc2fe3e045a9ff2aa8b356aee73a85a4c30d68a46e6392efad7745927bf58973e493692fb4fde	1	0	\\x000000010000000000800003d87515defa815cbaf8a988a416ee8988b135551562ba22e2d52ff070193ec3ebdc8d84195266a87707bd0fdc16dffa054e4eb8d239f1278530c4d92f80b06317899efb8f08edafa7abd6cc715632e07ca0872d79f226c6151af0058e80dfbe1b24c1c794ee6b0b10311a03f06c3cfd4364b6224495d3116ffcc7790494f6b05d010001	\\xa9f97ceb8bafb146d4d124c14bcc53d583f7906c296a5c05b77fa02d810d5adafb595edd381be25953f92e812f101571467cae4a6fb8b863d75c9b20d206a000	1684072415000000	1684677215000000	1747749215000000	1842357215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x08d84ae2e37ff2343603714a1d58f0eadcfe8988b2f0e40f03c78cb11efe495bb93e8fd6955c2ed9f39d404cf99d6ea904f733cfc20ca1379c8ffa6a44d68676	1	0	\\x000000010000000000800003c25253fa36ef33bf8dca3e904095e47db3f5a71050430a98479a8c1cc566df71df613768eabc22b33c69f06e06fa6ab154ed5e742ed1a0b6b4c4e4839a6f32afc271a0563b27df7d236bf4990ae10e67aa847cd5a6035684a9d28b658f6b87f2c9bff92d5fd70f339c0b49c52178734d98c5770be02d99d7d403ca8f41754fef010001	\\xe80f9ebe0e41e43d895608bd1398e6563523d4fa55319f5252a76b3c131046b9e5c486584921bf5339c7e3445c7cd7e3508ae123277a3f7b7a0e63c45f48ed0f	1670773415000000	1671378215000000	1734450215000000	1829058215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0990aef9ffaa9a502fc606385d0139ad097e8df7f43e50441cf7afff71daeb8fe2277a0c72f62b372c5d32f4fbd562334eea06e7278ffd9e993acfc0e19aaf7d	1	0	\\x000000010000000000800003f09829147509336f5b0a5d724c488efb7a15ac0955711573a9288a624f6b551e29a57f8de60849b165b764c30755673e0d48a36a1191ea1a1a87c31210b94c788104b39348b20decf2da6051f8c1a0b002ea2015e25d1b45a1ce58efaf783cdde4a7c6c6828ebc1cfd576db0e73d24734e51b8c62eb530830ab48ab1370fc127010001	\\xf40b634ab21ae36ae25fa6e5a558b461d255073477f459ca9c29b67720b11be80be041194fef5b64272cfe0a835027a7aebce219a2debf948719387ea45b120a	1678631915000000	1679236715000000	1742308715000000	1836916715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
6	\\x0b24c74d92f0f01d890cbeb7802af5d6c3862fe83753319efe4c448c0cceb18b84f9a351342a519556104c86a48d5fd83e5e78a499051769522ee4de01f49c06	1	0	\\x000000010000000000800003c0ef45d6a1008eec3dce91b29cf3a855518e232f138b9ec453bb2c933df973a68ae7db2e1777c9f02c7aafe8316f729bfb3514a15ab2c4836a95321acb609d7a79761172e1dd7d1825fb783380a7fa5d58e16bbb9af83a5ebbe855c2bc0ec73591baf68780fbdad0f6279065284d00e97957eeb1a0f1a59b5ad964b25058cc0b010001	\\x148dcb1048b7a2131fc79682894a18753e46eee1ee47cca0570fb1ac80e3aa00d7773d634a31914f69482da7430a7465384c0093456febc7d3abcd40a9e4d302	1688303915000000	1688908715000000	1751980715000000	1846588715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x0d04721422047432a7a6037aafe18249ceeaf838e4074e0b3d767b5624f5788dc9bbec8a6283ead13c7384d3511fc3034ba728114c17b6f8ef3246364f38c0a9	1	0	\\x000000010000000000800003cdd7df2394b2bc4138fdf1e8d4dc092dd4bfd0be23ab9fa036e5ef1c7ef8c26709045315af7312c884162ecad4fa8823474a9be4ed0d9b3258c23b588bcb374688808b0518ad53b5caedb942980687e4a00b8e639526568f721af2152d98a1f89e07b8101faefe0f7cdf872a8dbf76ebe1970ba50f87ffe93b4bd536f7d13241010001	\\x5bd941f2b1f3b79d8447ecdb575d91a5cb146cec04e4b6dc7d0991c436b4aa466cbe330c9f3462c0e67d726147c8ab8879487af6a57405034e9d10c36c2d1c01	1673191415000000	1673796215000000	1736868215000000	1831476215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x0e0423beb77a0d62a70c84d742dba3f3ed5968f8b01c5b7d17141d06b34728af55364a5a805bc4a33d4672a5fdb0a22a6199dbbb62f9955766f936d58082607e	1	0	\\x000000010000000000800003a51117e8cc5d26f24a43a2765a82636ad25ee41550c325e426f60baba5c6416134f88081dc87359b0a749964f1c4d0bc507ccc525c32a29a50a6e78c5523f2d3c60d6f7362d61ea2d199983777373cba645aaa3a80ddacf660e58b4e4a83cc7160e990a038f376e5d022e456be5a3bc623b38115f86bad2d8dbf7336e63be557010001	\\xfffabfdb7d5550a3d36a9cf66001d90a7b089431c7ed01032e47f0eedb29f0a07d62881b32ba53a2c0dd12eb58dc1b74f1aff5b89ed83c9a498323533e38560d	1690117415000000	1690722215000000	1753794215000000	1848402215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
9	\\x0e004e44e49037ba641a710ad64b2116f11a7682c62f3afa18344b11ffee9afe6db547a378ec0e606bb2f9e64ca4a90c16be1092515f779d7a990982362f10ab	1	0	\\x000000010000000000800003c984d1ab04a821d999669d846bbccc50935413415759fbbc63c0b5f0bf0f295fa85ca475853be4c3945b869d11d990efedf62bde8c618b73f1a5eb300c54fb2225821139278423b93213a92eecfb065eab9b6fb6ebd6f94e59f0620842af94e849a3c36278ac5163b3ec3522b600be20652e504b5a9b5a916ad7a5a9fa6ff46f010001	\\xe0ff190dd511932a59c67cc37523dc6fccaa05f9174f01c426b651d637c608d4c2145ff622345bf19533d85941a66f267caed50e8b71ecd509a2cab399257c06	1681654415000000	1682259215000000	1745331215000000	1839939215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
10	\\x114851d9ccc78ef23e3e74601a568c980057c53b4d75a157e52a0cec7733a969a04647cfcae63c3d112e30b7fc94b863261cad9eb7d30998c9640afd34f03cdd	1	0	\\x000000010000000000800003bf09639e2c52e794309b1c45cb51b48faf4e9833829b2a980894388651e738e2c09049f2eacbe86a74ad2f6103e471e587b12425cc9bb18500cfe647a3fe2465fd1c4fbf203f6dd6b4709fff21af6cbf1371745974c394c038a080740680b914acf17067c4c45128938cc5e6719a699d090198245e51852fec8fc70a9e7caf8d010001	\\xace4e2f4d249602a98c5cba70e2e2045d1ec78750b5fa616960c6361c93cb702fe28a96f1d8683c91b6f5f0f724a2cf79abac6bb44f68d3b7df6d38c24b7c508	1665332915000000	1665937715000000	1729009715000000	1823617715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
11	\\x1a908252964406be7281db1b285868637fc647f24f3551e118311f706b0572bdab3f67739b257091eb6e210ecc4755b46c6e50aa84f56b5e6c9a7ea7500a29c7	1	0	\\x000000010000000000800003b6334e323255ba8a8a9d3c88ba1c4de82a8134ad47a0d3d063bcbb3dd7157d3d651c169d5fe9755453206e54af42696c77be38c7026dc24ff0a9068460e344a2c6983fca1f7f1bdd45a4455107ec74fe8c037d737ee1e2c6b11d33a84c391cbfa49343e681f70d1329b5da4b84db46e535df90f1b7b3b2a98c7bd5a1ce7797d7010001	\\x91ab11a93b39974a1e7915c66ab6e247877712d76626708d0ffa86b0e1f3d93b698bbe06d8d8f3bb5e6b6dc9532b17459ff372fa6ad41819fe7374725091be0f	1681654415000000	1682259215000000	1745331215000000	1839939215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x1b1c4855a6823cf2460530fbd10f62724954231abc7f8dc571e12c3b2cc91190af043e8096eca52af47f1d467f659c4c0c1498ea57c47e848ba62b19aebbc662	1	0	\\x000000010000000000800003a242fba0c488edd1b053093d003858c04ec1b93361392fd6c26985665a70413d113f4e7a0ae5a9cccd28d9baad10a0bc754996f369f33ba3591c81067034295556ebe521449fc17a4415749310a52aa1359a05a9a7da058786789d136483c7f418a7a5802d3b944ea485da89ff9dd276d60d17941cc44de7285564a62630229b010001	\\x5f4721e4d8a49fdcaf28788ac05480e292960fdd1c49111beb4a8fe9b8cb896429bf84d08f5a37e9975520019eca7d9c7bcfb80ed9a395157a74f1c62dee0404	1664123915000000	1664728715000000	1727800715000000	1822408715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x1ce811e8069de637ceac189349a77889faab1050f809423a661f21690d4b1868c46b8e82ed8e979b7f146e7e4af530087323287c43868138789bae2f82dca871	1	0	\\x000000010000000000800003cf95220b5d2112e31778c769d45e2e1b0b0469f1450c32c6a91044d821501be0b9637a2af763677f87d90f6737e62c47ada52065a3686029f1b88da1d605d48d0de3c94e7b94cbf08eac51610bb7ea1b1f5f40610fd98cd98cc80ee31b377f389ef911903a55acc96dac6bc1ab002ded156f9241af494f01b08fb1293932de01010001	\\xc662b56eb307d3431a2adcb54008a9c37a9c20d354be9c88cc8b38e70e8f8f765ef91bbf0f4b44a275af678237d8e08981a411a47f6f696c18fe4ed611f75f01	1687094915000000	1687699715000000	1750771715000000	1845379715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x1ed0eaa050483da8cfe920fea3cf25a5e47dce4286c157602e0c65496ebebfe84ffbd4a16454bcad0a7b8b88edd015ca3afdf000cc1ce3e483bbd13ee497a009	1	0	\\x000000010000000000800003d31ccbc9b88c2fcef495d0e9792b61edf3a5d26887e6f111ac23f8378c39edcf992a3fd77235c8aa142271ed3becdf65b032666f317953936f6a65931bed2fcae0516ff5f8939a2fd94ef34ec5023ea085d44e4254a01fabf0040954faeb3dd93012b8e6120561b489422d5374611b02c582457fa7fe73571b62f0f802ffa1b9010001	\\x1b707e631b2560b74897b7ac4f441f70b19d9c1e85b0897cebee293c824ec8496aa36e0e8eeeb23c54d32f89f0961a0ad0597183bfa374c8b7dba3ab481e7e0b	1668959915000000	1669564715000000	1732636715000000	1827244715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
15	\\x21bcb0e812ec38dc24e6c54318253f0ee9eced80ae184bba9b74f58f04df8215db416d7cd0c7ad10ad3d58f7646f89d90bcffb3920a1608803195d7b8acb3820	1	0	\\x000000010000000000800003d3cef2cf69fd602da25056e63a4428045226e1e51519675a8eaf051c13e413af273a1ce8efd8fae0ddd25506500f006765ce38a72e6e1e3a857f93bead2363144bd4c1edb5e55db3f5baaf1165a7b9b9cddf4c888bf58b66fe675754f377e2a4916348f3bbbaa22dd21402f5a5436a3ed32660077fde6b1a4305ab4515b393cf010001	\\xfed6135269b3e07fca8a2009d88d762771a100f7160e75b5af49a89725011b54117b960340d091f88ca92ce344307cf8c6cf24356aa627f72f79e9aed2c82d0c	1679236415000000	1679841215000000	1742913215000000	1837521215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x229011685b7ed3be15676a78510667f5a76b00d78a0e20304c2299ef6b9bc0cddb2044c91ee982cf524ecdf9314604b5d0548cc2e1eea81f396d5b855ad105ff	1	0	\\x000000010000000000800003ac54bb8c26c429dd5cf33723a6d07ca4bded048b7e0b3cfbad62fa1fe498b5f67ee01900fa1b659cf5d974f5990f2286a9458974e550c17cf5f74467dea43403ebe8456b907cc375cf1b7bc5eb544d39f647a19b7a1b6a406db43eae27552dc345efce7587c25f437055f595f1d810d5719f300665af8538dee881c70802cf01010001	\\xe08cbf8061c60e0b3606b7ba0858000642a060ecb43be29eca2b78149dcb07f48ef57bb207ce2925d18fe465e70b7ca10292e06a1dfa166b99cfd9179ac48401	1689512915000000	1690117715000000	1753189715000000	1847797715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x297c104bf1a5592079a42b2b8b73baeb42eb0fa9b79396feac59ab3f69e49a1d8c72cfcfcbb97bbcd5acfddba3ccf328d020389a8657e90bfd7f4929e226265a	1	0	\\x000000010000000000800003a9544104d49a7f2022773df551401baea07a9de157328c2a978a14a9e2ed8f214edf1d60c2da90b3329ddcf0a97e33f517e94d3e1ab8112bff69d2dc6ad0c8b96efe26d5c5307b3f7411cd29c10ba48e4d5e41d31e46c893c699806733d890db1087b08c0f979d6d433f3ff6f15ef58d4981b07484d5ee1f9fad47d7bd0e7119010001	\\x6cc78a9f2ccafa6b460446b5af545a849757f689c69adde85288d8aa04788926d972604e343782238b57be337a1aeae08fdf3f5531d6aad94763d090ad33550b	1675609415000000	1676214215000000	1739286215000000	1833894215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x2a74e6163cdbfe77a3cfc2ac3ebe0a669ea6c772a93a01f29fc0fdd9f5172329e1ce23ad374d97aa0144bcb1b3512544b1f67bc69bfaa8cc5dd50d0977280bdf	1	0	\\x000000010000000000800003be5b6c239f784f81543eb061b8d4fead2507e0daf0d146bdd0c28e7b6e628d6f3a501dacea51d81d4032135055b328c770334d3ca8655d40e14bc6497d3f1a11710a1a0507f12bfdcc1b01bdf05ef8707e9b9ddc345e53921f2f9a150f703a899cd4de7273a0e66b9d46822bf5ff130ecf63b9a97aba67a4506b130045b2c749010001	\\xfbe680624393eb2865ed770c2451e9e67b1cab16d4c012c888b8acfbb775efe18eb0cb3a364f1b469ac96ab879eb20ae8d3db3e33492320696bf493caa296905	1688908415000000	1689513215000000	1752585215000000	1847193215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
19	\\x2d785942dadda5f8e2c7107cd4274b5e268ce68661859633ab50131e3a8130b992b1f9ad86a468f7490c1437026389360ab32eeb41688e13de081abb5ac1f54b	1	0	\\x000000010000000000800003e15b273857cf27f94daa11630d47b73ddc9a33f71deb969489a08dc32b682867783b15dd200a3b7c132956cad765cae8209762056c23285fad9633c40008cb5fc7a3a776d61552b4c504d0f45dfd775992e17798b7ae720545dcdc51a35b16184fd9d1ac5a0e81b7e7b87d54893b769b035eb32b815be3266d5f0e7b83da5b35010001	\\xc35246cef174ad0d25633bca21e63f84f1c0787c4ec48169b5e6ff4e19eb467ffdf5d25fa8bc63f35e98d0e07315a9b3a5af0292262a0807137761248b01c000	1682863415000000	1683468215000000	1746540215000000	1841148215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x2e94c3d26b5a13e3eba8bccb8c2a3a873c04785a6cb42da8297c6eda83f4e8555ea15b59f7ec4e381320b20cca015831530bcf07fc6b1b6e8361603ce395e3ea	1	0	\\x000000010000000000800003c7b740ecd19be1d7bf185436aa07e1166eccfc9c9dbe02bff0eac3edf5223879234b4193952944453ece4cb03c1837e1ce459bf3d8750de5582b06b2cb482e916d42feab313c60916411640dca3d64741cb9e012e9d206a24540e70f5f9c3fc3180d9997e3fd2b6cc02ed0d5993e3b03659237067ee00b52021dacd3be7a9c05010001	\\x327e16f8422fc93c466efdb2dc8ca99974fbeb7793d60b59687b40ce7cbcd53a5e69c74e4159f5918a17efd34b015b71ee0483f7362d12330732b6507c0fcb08	1673795915000000	1674400715000000	1737472715000000	1832080715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
21	\\x35288632b9ca78d2b76001925b4b2abcfe47111476ea3dd089cbe72f297bb49848b93b94622068e412d4dc885d266e275db49b084383899175d7b81a53ce031a	1	0	\\x000000010000000000800003c5fb941eb2425942d12ff720ee75a50a6e00f48d9cd994be376acc2f383e5ba8a660d21be68652d3237e23dd165a4d99c236805a12f925e2ebb981363534f0a3de52d92b596a9fba06a7748ed19a6de138c2b06daa0fdf9c2913d1dd067933f6e8953e59bcff6b2572fc8e984a1391de8d3fa1362c5c1c35d8bd25802ed9ac33010001	\\xd905c6e917ca08602a2475ddf900e09a2d071997e43f4a7e29d774fa5d4ecdaa3e6951876b3237d2142b32937657f113371ff7eb8b8247a5f6d066c03f2cec02	1676213915000000	1676818715000000	1739890715000000	1834498715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x35bc8afab2ba273fbe921e4b144ce21ce9f5e28722cdc1995736f535b8baa680046749b9e1069436f755b235c1e8c2dcec72914a1fbe29359c400f40b8646fbb	1	0	\\x000000010000000000800003a2ea787090ae99cd8aca46dbc239fda026567a9c96f072f5b97b134b393776be6b55e2c4f4872a82ce539444616e3a51582a932456364b4bc6658bfdca32ac974e286e06e19b978960da1c95557fa153b22d35f27241368f6a53b60964f8e510f66c42157737a7817ebd330bd8840c99ec94883cf7d31ed3dbd0a958c92ddddb010001	\\x414b1f357b35388ac4992b14c3fb6b3b446c58e41c2c645cc026e96fd127f2cd7cc241310f8da82a06b7f30f172cc106d707892901911ac4f6e81e1b7975c005	1662914915000000	1663519715000000	1726591715000000	1821199715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
23	\\x350060920c4d639c958215ada788a90796ba32605206c4c32a01bfc354574dc92be1023057b21ca659c235ed568aa2fc5fdbacf136807264875b05f094cb2295	1	0	\\x000000010000000000800003b212768f78bfcd4fcfe5f610b3628cf3d53b6b74ccdef40aeb014d096453171dc02ea609602f91f18c9fcfcba0cb3547a233423cbcbc894cc76046e85bf7b8d89470d8a4b67bb567e202ee4becae05228f78dc7dede98021ff914a99651c31dddb8720b0b4f2c79679c0cb3c83abf7f723fb1bc4aa462d15b7ed8a3daabe6061010001	\\x3cc0be7b1c7c956a52d95c3a7d3df195a5429f74a29efb789d8b0be68923741ff7a8189f005ada571300b81a3bc7fdeb4bceb14cea3f35c74e92d8f24141d702	1661101415000000	1661706215000000	1724778215000000	1819386215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x3508e8e91456999ba47db1c051b16e209a9df912c66aafa45e843e67ae55b56bd38983c26528edd9b155dff2ac1a45b2126d8f7f58fe47a29a1b7a3c6c68caec	1	0	\\x000000010000000000800003d54c1cad525a1096fcca6735809a92e1b2482ba716a334e69160b081bc8a6e43c93e197cb203a727865abde223cd0edc8665aa6d3774aaa512e717e0055b6d4c453f59c42336f97cf1f0a0e64edb5f0a93b55952e9907077a83ac62777e0e2544cf0d85cddf89d2badd9b84840fec40c599aacf72c92c12bc3740a8157a6df4f010001	\\x497ad03528f02a0d6b3add7531581175823ed5a5a7f66b8844acc0ebd0b558bb666f322d2e1ae863d2445652a96c3a0aa43bba4977892df7e46e13fcfb192d07	1662310415000000	1662915215000000	1725987215000000	1820595215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x3988d1b95ec5dbddde60272bb1cd3f42e5550512a3ad4259fe3c3d3b4934b76fd269d36de8acc6468d94fd709b9a2e9f6ee6340501886c2f890d7f109a55944a	1	0	\\x000000010000000000800003a61ebd023412abb03710ee72cccb4ae8e3320ca517b2c7d8f3e991795c5e9649da1a3abb0e636df48d3acd7f09573a75c163f9f01e1e767a41d8e58168932c6c181d1b09fee5d9f682036e6ede5ccd96fa600b36bdf8377e9efbfda3158a59fa215bd8f505c66075e9e7e59a24dfd313ffe4fcd66ebb209fbbf93de7037adcc5010001	\\xbbbe2c262cd37d5b5ee14eca0d7f72d79229d8f6ae560ebb7b9d3cab345e66c7d97cbcdf3383d899731c0f2b22e340ab4e2ec68b28423f088660f07d0efaee08	1664123915000000	1664728715000000	1727800715000000	1822408715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x3e2c30a06f32c93bdeb83fd7c43ad9d62253eeab21dc86fc62af7c9df8e05c8256698474c84c2e47fe3ff3e946af8d09f9f5fe1b2c1eedc49703e17f47fd7106	1	0	\\x000000010000000000800003ae073399f35c8c4bf4540957217fee4e81bc9ceceb3e7c99bbfcfead97c8939f2be85e90940ee8a4af555dc59b493029723339016350e65d40bdab650d78a15a00fa3e5c4a523f5f1c685e1fbb1ff7f3e1cb2d1df1e0a28951d88103cb0d33140be5fe802db3f94a7eef97c80ead3c796a6fcfbe6bbf9cb9aadf06e2d020f115010001	\\x03fb96432b8614b4b046ef94fcab9c7f42a41518f1b11b79404d0eba2a05911bc84e3f563bc13c155f697a168d6f487e05ce6839349aef7d4f3bbf6da4ec1d01	1678631915000000	1679236715000000	1742308715000000	1836916715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x415c059e57346c4b1ed3e9a77cf237c57d41c70554c93083b484fbdbd2a1fcd73b399039a887b710efcde0b980946d6c2f0c3dbb1344e0c5ed9887f544ca0713	1	0	\\x000000010000000000800003cf3d05309868a964cd1251c8d5f0dec9a9cfdbb5408eedb622c1a05b1e0284463f4ca2c7ba88b9972b9946884465aef7602424fc1f49e37a6e85b691b5244bc958676bd71f16cb6e6f93002382e6b17f2302b2c9a2f037f27eb7be6a3449fad0f3f7bc2a179e221dfda89e071933f9d9bdfe984e7ca8229c3c66ff88cf31e0c3010001	\\x3b589de3fef83fe69280d8ef680d824bdefb45ba7682c43a3b7dc73ba91126a234711133db6d36281e39d1ae19eb0e54ce96a645e643be32ec68274916c2e406	1675609415000000	1676214215000000	1739286215000000	1833894215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x41543a407fb2a7a49cc533a3c4e6338958697e5b7f688f3b1b4c4249798a633ff38d3b4b08207f04d4ef9fec4aa66cb1a30326eeaa18ef686f33fa1a493d06f9	1	0	\\x000000010000000000800003d43230bae68e0c854a60ce56e1839b688cb9b5730d20b3937ee03f9749963eb3fe0674bddde0dd3f2c7b8e1f61a323e505c0b443ba3051ce984358645e4844ff9c0d8b53da7e150a4df3172154da0601c85d8cfa8daae37f9b99726e4d3e916cea334a9786f6e0da9b891f5a9dd742bb39cc7a48afada011f0d5079936f0f063010001	\\xf4b3f77e2852b8153ea2644c3736873fa563aad11465125df744d19dfe2fcabbf49caeac23a00a1d4844fbed8099711fd705f70df1749cadd987113bb7467e05	1675004915000000	1675609715000000	1738681715000000	1833289715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x42d0d8c109bf504fc654fe06f6c7ca8c1640dc3eaefe526170697292fdb9367a10bfb0708eac6892fb05bb8d686b0f16f76141b944f38901bf3616368d9438f8	1	0	\\x000000010000000000800003be4ab6fd7f6cde4431d59b6c459537932f01104d0d7ec95cf7e5e1c933af091e9666458f5411befce77bfc7297163e1c3021c55855958af3cc2a0bb2d3de1775ca36861681cec72dcfc73b251a8ab2d83a279143b303fa8cd3ce1c1ad9a65b851ff79e9570b795c4e1c13cf00504158bb92a99852fd5e53b70e01cfe505f6ecf010001	\\x307e267fdfff76347401d5fe8980550c4da5ffc5e181dac20f7f0b69495c1ab06dcc30518e96aea11e19da429813cef42f6f3c26014c6028ee974aab22bff807	1691930915000000	1692535715000000	1755607715000000	1850215715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
30	\\x422c5c1359c1b3e7be8b91152c780f0736e43644a952b4f551bb3fc3cfd9c8e91354c5f52253cb635bb86640d5ad19d916f5e78cb2a09ae9affa8e8dcb297771	1	0	\\x000000010000000000800003aa59d710981506229905191217952fde66493edb7e5e896ad91c60b63b866acc39aa2721d8598bdd0e375f17273f26b4b5c5de9319dd87322c0bc04be9af920de4ae1f90a05e6b7e192e779bd0b1c0103171b06bd4e7e38e358b36d9c91412ea7f3d257d987d38131959b9a3abc3fb4a4906e590267b05c1ea6018968b65dd7b010001	\\x2a69c4aec108e85ad60e2964c67e79adfa0855a6dcbc1619955aca27d003c3a0d6c0cd60affa3733568e0a6c402723e023dc0e77de9bf1c82f8ca6785710ac0b	1686490415000000	1687095215000000	1750167215000000	1844775215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x42f479c20113db0660dd655732b95a60a4ba559eea2d043f1dc5ac421b812902ea28ae7edf07445d98e07abafcb1c7b4bfd9f8a9bc7a11292cb0358659f73fc1	1	0	\\x000000010000000000800003a3d74e36f0ad3b5cb6cd0582b8077dfd7cbf4e6c9cef415c7ac092975e5e93f81b0a0d9b1cb7031f9062c12a9ea17dbc3867f793bb779c8844d330557de70cb1b04fdacb2ec69a1bc64c5c3e192fe409d7908e2f16bcda8f543d4440c68c96d6d933db76e09e454d478c34c35fd9a532fa4ce43946e6ae787b559089ba3ac43d010001	\\x44e73cbc38e0fa0cab52dadc6c490ddde2cd16cef96fd2b7e5008dc798f9837c86b43c0a070673bf8c247808e461631b1e6db934913c9ca006c81b6688cb540f	1679840915000000	1680445715000000	1743517715000000	1838125715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
32	\\x43d808583dfab4284c2472ed4778a7758c885121b2203e861fd7d626ebc25da54cf3ca4241dce2f0ed354883f1479f686d85128022d7ff5516c522579bc78176	1	0	\\x000000010000000000800003e408760532534dbefeca81a6d5c1ee2c66083f6ec7773e83bbcbf4d689d4ccde13dd35242feafb6fe9dd058b11d2b355e1c2f71085e34b697eeacb427995603ab60145dc100ca23c00bd75a1c7fb79fc0d2bbeb25d896102462ba0c87e138d498dc08b39949aebc71974280afab6d682f00ab2e91e18d9355935423cde7c50c3010001	\\x6524689df46a055b6ff8aab9983e04807459f292d9a3e69967685495fe5cc0f90ec3b1c43bfd577380fce62142f290cf22215493731d3ccfb0b4dad3dcba5400	1664728415000000	1665333215000000	1728405215000000	1823013215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x440cd78edb5750ab0a110a76c4ba49384defc4885b507e1545579dcddfbdf366b92b981dd55551654567f3807bf3e8e0ccc4a2c6d29d3a7209ce5ebf0b8f8948	1	0	\\x000000010000000000800003e65c1c04024f5874e9ed2d6c36ef06028de4572d462bc5bed6715eaf66af89e03b7c6b0090d6c67cc491b26fe0af19da7f2f3ec8c4fc732f4ea2ff78cb7378b44dbfc6809c22a0e088dd1bd2114dc72dbd15afabe1abfbf182426ebecb13b541dbc2dc16e6a25a2046095569550fea2e8b3a25d1bbbbb0af3408e796e50d7307010001	\\x741aab76e1c1f51ecf873c3f75f6d481c28200bc2240c2d38943aa1307c5ce182025b87dfa781434c945dee7baca2e3474a4915599236d421d77f7ceaaf3310d	1668959915000000	1669564715000000	1732636715000000	1827244715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
34	\\x476c7b6f876bf67331f69700a0aa030ce477cda769f12ad78033225ade141634135c62ded33fff92a2a98a282535645a1c4dd721dbee47e0d688ba3e9b39de77	1	0	\\x000000010000000000800003ca7c45d36805fc8048a78d50ee2cc961db5821bbd6af7a8a602b474e9532702649c8b1e1fe4168dbfda4fec4d0bfc13e655e308b2ce38c54446e2b66b66e50c54f05ce7ebb10b04fb236543be266ea4d71589258815d3ff58f29a590340f84e109e30b500c63c84f09e03383f4fc9b571212f7a9aef658f1ed854b5e7561e5bd010001	\\xaacc0eaccf778deacf0bee4cd095838df2c4e0a7fd14fffba8e17ff111ea0aa9f927c3a8235ab570388e6cf66ef00de6612355998892a27f69d22b62a980470a	1688303915000000	1688908715000000	1751980715000000	1846588715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
35	\\x4844dab92ba3f20729a5a0e77238f15ca8fcd5173b3fabd0bc0ec4bea526b427b40dd8976d7c5af857ddd7022fb71aa365f26e5ac44c3491030447f1a837233c	1	0	\\x000000010000000000800003a46c5ea927bed330faa8d88bd803e7ba3e286b6d670c0c7a5f6ded0ca913519c7f8aff9f59ade4b37558022882ec44c5cc43e87661828479a9623e86d83318322c12b22bcb867195b166169ded92043318e839120ec3b12102cd5767cf79e60d7fcbaa71250cb87c857d9288a18cbf59474998c80773a133e625894352b634dd010001	\\x5b37a6b350182601a5d796b68b848bff7818147b4114e228c723e3c151f1fa94e42102332582108dad1ef236c16a6752a9ec175a10cb04662844aa1a3bd6400e	1666541915000000	1667146715000000	1730218715000000	1824826715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
36	\\x4d3ca31267441037421c60dd4698a329aba06cf2a20ba278faf7f4ed1c550041a99f98df01448dd317e15365065b93b6c12cc6c0e4379601439910686d78648f	1	0	\\x000000010000000000800003ea12f374faf7795bfd7ba6cc0e042dda109c025cb85f95ca2e961dacb04d1b8ac3bb2fc1832bee0bcb7651d72da55e49361968214bfdce40449ec2a5f7d7389fd69d87a884fd4b75607e3cd8acf42a8363336b0f9fb6d33a500a190b6c3e109289dbfd8b29ddc77c7d7f1abc9484512ec7020ebfc71630d2dc0efe44d3b7575d010001	\\xe9e1ee694a0f24afd05536c955b5ab0f55cd77be7bc2242b9d4f7326fc54028960464d63bd8f410d9948b81656990a7097ef31919a692a6c69b95a5b07f27501	1687094915000000	1687699715000000	1750771715000000	1845379715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x52440e84624739b390fc7b3dec37442b64944ce4c7e95c53762f324a439ee37c6c992e545548f70b0571babe6ae909c93688334fdc70b9dec24abf8db06a9de9	1	0	\\x000000010000000000800003d467223ac7a821070a13f355d9562ba662fae51194c87a0ccb55709b708b04e5d32eb9e45b2530529624276b80f073bd1bd743ebc4a155c29b91e635935bce3446b98d27e5818828abf17cf7fe2b707508ca091c9d520e58a7aa8eed6178c6237755f55e5a75e76ec34e718ff0002f9fc0433f311919d191b4680053e5ca8837010001	\\xe0cc2b583ce894179e8b557afb781bc4ccc9a186e1c5de4ecda9e67c92f0e845390a6ee2be1cc0aa06ab95d84ded6e01be9222faf15d3f71f569d027494f6402	1686490415000000	1687095215000000	1750167215000000	1844775215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
38	\\x576c6dc97d0a922439404beb93025e2901cd6a6369446af4f2763527c9fc869b510cc981a7a65127fe2cc69e455397c8974bbcd7c91e7c4cf64d82fe86e69d9d	1	0	\\x000000010000000000800003d5b177360d2684bf03661012fa9fc69196dfe735eff2f1451cb726f305d2b3ffed5f8995143d376e0799f91400a9906810b5c5e4a971edeb5abaa5fca14054f990e0297f7f0a2c3c29db6eb704fcd7daaf72bdc32521dc7c7b7c2921d94cf60427d7ee58e3b82c61f13e3e4e73ec0f9da59a0d90a9df5624b0bdf4397d46e871010001	\\xcfeae93b9a024617e9dee765e8a6b21f712cc8d2273d419796c392d779f183cb0b3701bc813c4082351838935047cc1b4da1c42b6d125f017f7257add0ea7f09	1678027415000000	1678632215000000	1741704215000000	1836312215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x57e0e57bc6faba6762702c96242f36d07580f72fe108483a794c7b029caa4c4c1ee36d4dfb357891ebba2fa5a0a2c94aa7c94281163730034b8aaf2595e7bb73	1	0	\\x000000010000000000800003b39f1b3bf8c440d086c9763708772eb61e59d5f1502180a2790dbaa587518cb453ea397dce89ab8d53ffad69f8205172c3abba6e63c0fc30c593d85ee5eaeb8d2313816ae21e7838efe9d91c5d89375d0cddff4c27e1922df670537dd31921e8d5f40b5b922fc15939ad791a8c64315bc54f6768bb73840d8e452e9e63d32391010001	\\xa88de89cc74d654d0c744b93156e3785fbd885b03e5fcf2509ff2cda33a586d21771c1920da7ec578ac145c1d6da65312301fb4458cb816d9fa69e31c9dcd809	1683467915000000	1684072715000000	1747144715000000	1841752715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
40	\\x58c0555c72e4c8e56c274928e7a8403e03b0cf43f98195b11da251acbf3861c4710625700a538507c993612afc5dfae43a6c8d77e06d8ac914e0a19b850e97a1	1	0	\\x000000010000000000800003b932bad3b0e91f5b54edd8ee6c817684a3c56d30cbb0ede1229cd8f5b3f05c18133353092c2dd09d355c8e94fc3050213f0a1c5264585accf4238dd5d8ccb1856ad8b1d31bfe0e185dc7ef108645973e366d9f0bc7bc04b0414fa7795467b9387b239093a9f23d54ed56da0db211444107843c8c897baacde61764a8cd50a1f7010001	\\xa100451b7b67162b6f273d740993cd31d973b873505f47d8bfcd63567b79b1ecb6a3d9b626d9239fd17b26a0a41519455ce514beeda8bf259ad79efb97f95f0f	1678027415000000	1678632215000000	1741704215000000	1836312215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x5bc0d8e161f87a192eef845a0fa7679243cec55760e39d1e99c4424c0144995672a2e56a0d0e9c72721d7bcedf3e6631a93c2f39070cf80153ff2d663b2aa4ed	1	0	\\x000000010000000000800003a363108edbad8b497ac0dc84d9129d51defe78fdc37310c62489f1daf4711bc6a5d70c7cbe93fa1bcb25c806dd6a8ef0751f47a3bb68b433262f51f0614be0e9f03993b7321415a47755f889e82d31c9dea9e6345fee91aa85cea6bb4c1faec1fac1bb576a24db270c0dffbbac88da135e9ee6234cd10324ee07596c1c872b09010001	\\x8ab6e3f57867c6da83fb6503e0b561fe0ea80ad51c40c87962337d757f134f84fb82a2ba10927e17a0308932478475bfc20422e2da6a0a1ffbe5f5c9bae28a0b	1689512915000000	1690117715000000	1753189715000000	1847797715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x5c7477748be58c6c523a4a8728011c984f92d8cfcfc39607334fbe166b7bb3290f9b0ee9c1ab620af32bd5e647920d4cbb685ddd2ac0ca0108c7d70cf9fd3d37	1	0	\\x000000010000000000800003e77d8c82feab0cde51466f3b78aaa41b8df692edd06885b3af580236d2f51050ea97959969c62e28bb85bfa46a6c4fda7704a2da87471525f9754334fa800b97f10481771aef147737c916fb22d42447d9bb6df68364057ad535100c2725fecacf95303131782d153ca6729304d022cdd72ea0a4875eefe63ec5c803ae3d7093010001	\\x06950ea759c61d41741534fb6c4a9674717ed3d98ffe6e3c98b60e43e49aba6453e09e2d3e1cb78defe8e18ee1b96a60726bced55e52fe257fc113ddfe0f0303	1678027415000000	1678632215000000	1741704215000000	1836312215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x5dfcd8bd41db2e65d2d34ff58286284e4966e1512874dee473f0b0ccdb6a20f1be7d697afe0e43f45b84961fa60e8a5884fac3745adf68ad8dd6cf2c7d1b0b21	1	0	\\x000000010000000000800003be85a1944e3c567fda29be5a3a4752ca4ebbeb4c67b87c090e135a97fdd85dc73edd9e059b5b0e420c27cb646d033201648e4f572a69f1190924c5b27b35cdde603bb2448c0d5cba15949375529e3804a2a765fe729ee82426af79e6e9b764e5fe5e9e6d02195ff8ca0d5b7daa9ca22a2327bd6dd5d6f6fd6a1cfe235d19f961010001	\\x08f95da3edaffaa99ecfb31a4c848d1de727adb1054b677b1eae5084026e7880403246c732e27119cd773ab93d2770ef9d9a10a29883ef66f80ecc0c530ce604	1683467915000000	1684072715000000	1747144715000000	1841752715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x5dd48c81af54c7ad50b6ce3ab2869e5314cadb15f5ad518528e3d2969055d5ecc7db2754ddc80764ecdbc7d976164e4e0fcef5375131860bdad3e2521839edc6	1	0	\\x000000010000000000800003bbb57413f51552b4c3d9b15a71057e343bba902a8548eeb098bbfb8fe98edfb4a48d4f1ea8b3b4e83efb15dfe4da8f4900c0cac877e285854608b0094d2b232f15c92a95a2448afb2479b89d67851a300bae677eff72ae407ce2be86fe20617aada8ffd48bd303a2c16ba78a62d66bd44235e511118c46addf34f2c6ab8373e5010001	\\x4de84e73f80d29177f787543d254d2ea96deb10a59c7e15ff7d911b6024c6519fff1062a6e5226dc2761a3bb38a490dbf45cb05c822e9e2db662c004ebd1ee06	1673191415000000	1673796215000000	1736868215000000	1831476215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x5dbc850e1b36919df4d5c9516d276b3f9082f8d0f3e186dea0cdc1119be078651b73f0d64cf59ab8b139f915b585899ad05d4a8644560de4cdf45c4c0e09b3a4	1	0	\\x000000010000000000800003a0fa6f890878a658179733559a771fb29b82e58f4fdb92362e641f6ed37eeb47c2bb3ab2e56d57cf371fa4a236ff133e0f78cd910e3503fcbd4c0223a35090b024f79418d37b1ba5918feec3606ef96b655252012067781d8ae5dfb0710e79a4b307ebb7bd0ea02223dd7d794bd651861dbe3ce93a3823a4193da1551743874d010001	\\x5e886a7bd86ff4c52a30aa7f085e8317861ba9593e1516a0ae500d3e648d2ea67b6be42229e0df2f261fb6e00416d27318261a868b65a4ebfc924289df644d0d	1674400415000000	1675005215000000	1738077215000000	1832685215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x5da4738c893053819958485a9b8756ca1e96d4786195f3b6bbfe53c969900850c3230cb218b93b08558f57151a89e861c6bd3919682311a121c65a8da833ed7a	1	0	\\x000000010000000000800003caa9034b00fd09bbc5c49d8000004759d2bbc8383c03565acc121061513a519118c281be674e373914bd36a0156bebf49a18f795d2e9b0513a36826a21a8bf6cc3b4cbfb96206348868c9bbd5b395789f21047db04ef96fd68130407b59246b9f338231d96f5b6ce787c135489f5dbec257b61463b8d30de11e952d5ca61f635010001	\\x2d0ab57836e86155b5e0d533c17ef7620fdd0f509614392bd089d5e116f1d2d4f8a81bd8db7d8e1189703253d63bb96baee0e079ecde7a98c9050b07dac9a50c	1679840915000000	1680445715000000	1743517715000000	1838125715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x5f6009d4082d6600ec8acbb4db66d51d737a78f7319019e0d0672698283ca12559d1fb415e1279f0b1c744e1a77a3d15faec5ce83640e4264abe7b700a846a3d	1	0	\\x000000010000000000800003aee5a17a5d70a23b0d372825b1f3ae1186220abf40abc37a4865c65a6648deb0ea645bac35ff8b0a559ee2728bc3f3dc6770f249701efa692869660b47cb22c4566a1722053358bd67cb6013680054bcc4645cf26eafe7108e7c40c2da9e678014f9dfd075b99112bed4783177298e54eb00c271512897cf240394c159423e39010001	\\x5beebe50ee07becb8f26c0fbbba364c4b9622f67becc5b2d0299b9dae505d269f737235e0e8febe711c07968e192930c49fd1d8b750bdb2214bba40503de0d0e	1684072415000000	1684677215000000	1747749215000000	1842357215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x6084e90cb474293fd66c1b4a77bad18a8310385c9db560aeb7274ff0eb9db922c100b0beb394a7021e7cdc0a764cef48f8b8645e9f672cfe5c242b752f7a1b30	1	0	\\x0000000100000000008000039f02b86cea19cecfba91d9f785dc2118e5d7b39aa6a7da64fbe500274b351e5277a90f2558ef02344b22ea3d72438615cf3367f341cdf4c29c074622940e5206fc2b9b53df61839d98f6fcd13fb21c2024be5d6aa8479ab71594d8e804bf7a6a0576799f9722e34f055726e8c71491938f1a8d777e773506b76f60e1fb11640b010001	\\x42632571f197232d7bebc5dfe9eced2d3a7f9ec11e5bb7d62617713961e4a622811db915caacb0496ac0bf5cced3761f42c33db4a7ecae989bc6e6d76f8f7d05	1689512915000000	1690117715000000	1753189715000000	1847797715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
49	\\x6138d674a19a92bdd0bbcad44986bc03932e94653c95f27c33a7a0bd08a0c5df31eb149ed9d9b4151a8f7c0169021a99988506ba0275f3cfd924c412b3acc5a8	1	0	\\x000000010000000000800003ee1aded440aa289a36db9ccf86a380f390088014f947f4b0d6572b1eca928f7530d4ec60677f94374315521f3ba574b2c7a8a9d3d7935c227e6c7fb94b6c198816eebeaf328f50d0943263d1d768cf16ef6ab3652cbdf00ffc4f56c134e8101ae019ff007e2b1a04501ec95f8bf7d6588e1b46f3d221e03091a09636a209aa0d010001	\\x66a79f7b352c990a6018dc492d2834927e3e7ed0ca245a72709dc8285d595e5da51166564c591d27ebe5274855a0f27d7e04158eeda4c3da250a4c03195ad00f	1681049915000000	1681654715000000	1744726715000000	1839334715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x625805c1dc6312b3f915aa0b886c09a631011d399fa5ea0aa51a85ecd8fbbe500e5f05fdd34739d529d46a4ad6cb9e524da0bdad1e7bb5e0e184e2d12c971542	1	0	\\x000000010000000000800003cd1639370be8bc3b1b70910fdcab24f19b01babbf96710f809f1996e62bae09d816eee7f71a02dbd4b206f64c9455af439f094a06a7f9bb080fb56c1ed47e24de23508791f30a7e1388b2b195ab4a397cac45df799704791101c293aaf0076fbcdd2f7aab6f1bcf4cd58e6f16886bbd377de47e1388b63889691f2e9c1e95089010001	\\xc5520ae2b7c0201329b8402b695b96ee6afa533a683e90d067c7938bfc18a97c9a63e3f4b4c0349acc520b2ec39a79d8f8b6975fc4cff0771521e44d75e1e501	1665332915000000	1665937715000000	1729009715000000	1823617715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
51	\\x6394b1805cccceb827a857806a05b6bc979c783a54794d126dcc916f56bbfc682062f652d6bc28a9e13f183ea9943a97c58804b303044af2d8d4d4bb4be5a250	1	0	\\x000000010000000000800003d0dcd16b057f0f96811d8fcd75d0fb2b501db708a656401e23efecca3f81a43c2f95b725b2310eb8b8754febbfdf898c34bb838fcbf715420432f2974e351f92ba0bb1b20f6735503eed730b61e320f7f56ff56d90310318d94a4ddfb2fa82c53553f19dfc287444ae89124cfe3e34f230ebd7abec967c8b721b6330274e662f010001	\\xbd9a9dc8dba143e60648f5a79114be9d1e4b5b016f1313c24ce0937199d661526e662d19f717bccd9277d9784032a2f31de6e5ad74e353147386aa3a6149c405	1690117415000000	1690722215000000	1753794215000000	1848402215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
52	\\x68a4048377ee1ff7c5a8ad657b27f0cf842c0193c1d2fd818ff64a7c08c86c1794f5846ba362e3fde8629a398e4e47ed376464f4faa764368c4173dea4dab6a9	1	0	\\x000000010000000000800003c534565b10292ae7b483960597ecce45effb6186f58a4d44dadb10e262a8296d8910c8009e5d1eee9d718e2e5068265b6363d03a66fdf316bae4888d553e3fee69020e92889c4400f542af44c567361ae7cc3fd567a7bdeea5e470adbd467d9d70580f0d9d2763c1b136fcd2013d0bdd8a7a7c6cd909fb9d16904465ed74a99b010001	\\x3a771c599f954e28b8d032f1248cb24427e8f871d9335fdb62eef827f0f6cab675029ff96e172779c07940a8f936ce8cc1213cd26f2d3330f929e9088b498b0f	1678631915000000	1679236715000000	1742308715000000	1836916715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
53	\\x6cd877502d274197996ce3ca47f63a9225e8fb694caa4cb35feefa9e48fbdb6912f55c0b639b45563b6f67e64b18ba9980503340d5a85667c1e81351cb3a3c02	1	0	\\x000000010000000000800003c9033d54da9a996aa8ac12ee1c0e589e3f5bd7f61091582d4171504ae48f584ce3fa09e6e33f1237c3039f2b5574a4396a880d63603525475529e557330b9fa82624deb76054e7de1931367239cf8ebabb49797a6b1f133daf7bdf3fe0ee80c56f0321f3eaf13545aeaaef10b8dbe88db01321fee803be7312f3c714e6072273010001	\\x58c84b7fc33bb6e20bc81f2cf75d7ae78cb696f7864eebe8ac2cd2806a02acc6b3b4e70c84ffd0cd3e546b4a4de04025a4c4e3b4c8a47a2b57a8592178fc710a	1679236415000000	1679841215000000	1742913215000000	1837521215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
54	\\x6c8cf3a6fb649e96a5b844557afd833cb17ddf3b1339b4e2a98851401497418f97bef2081695ac53fea22b88acaee9858251e3e0ab501316f8b2c81b44e8361d	1	0	\\x000000010000000000800003b0fb1e0bd6d17610f488fdab7a21cd565b61b25a9eb78176e9be6b4fe850078737841e214c237f9459d039acf8f1d6f525dc95ca3e7a65936529507174e86bfb8fbdff974703272fb660a2a1e9775d54ba63945ad052807061409c06ee5a7cc2c9e98283e3f7057dba6f0c70e2982934a7f382829966c995089a1e9b5006e4bb010001	\\x5cc87266a0c1ed3e51f52501f01d7a7339909f0f912d8904d3e0b9dc62ff03fd8219aab58149aaf9228e32f3000fecbcc67824e44ef974b7027763a04fbb150c	1673191415000000	1673796215000000	1736868215000000	1831476215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\x6c20c10d1653e963b71d764993c0c6c85d5ecffbd3d6e49e018a00e796708292f74d08f7dedc65d6179f073cc7f5da2d4ec1cf6d1c006877549016a1897a4360	1	0	\\x000000010000000000800003b0cb11ee8b764636f72071ccb33d024812bfa56845698e8750f70bc084225815d4f300fb85a782445ef06b6b0302edcb49e8bbd8761d2a947fd7d9e7400fb30b3e818a3036ccf82d81f1a8e2a684d7924495ea7ec47c74edcc94b51db340dc25fd0b672372a20536bcd980df752f30393fef59d866b7f36b1c4fc4b4383a2765010001	\\x1e43bcbf8c8d66fb4ba7d61fa1c8dcbae764d71f52c7bf31fc861d1d7018a0d9a7682c70e2f9cc04a36ce48ccd0d349b518e101605c6b05a9bed0ec7e306820c	1668959915000000	1669564715000000	1732636715000000	1827244715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
56	\\x6e700a3ec9fd3cfeab37a6e5f38390bad3dd9c6c6615053d2e50f3e8484230b95eb7565c9617ffb8bf9d5c428b6947692500d75eaa48a94cca281d6feb8ca3e1	1	0	\\x000000010000000000800003d08cc7b3a34f24621ff648916c53b9146f7312a044fc48c97b2a0e12cd21117c0e0c570bc87ce766ca8330a3437c8d0a0d81443e5ec3d0e6d27d049e3fc8d65578de46c2cc00a1f9947f4744fd31f7bc92b88cf52170ca144b3f1305e9b747b820f654cb0a09b82b5ceb9efe1b2975f56a46ff1428b7d73e377e92fab6f63143010001	\\xaf32a03afcbb74c8a003267e6dfb42acd14604826c5a53fc99e51412f98b1ed8c762ad7ca7b844ceed0fd6a1669bbae1b95050136ade13a0a59e650c190dc40e	1685281415000000	1685886215000000	1748958215000000	1843566215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x716c87be5e4eaddcce2d9c2ea86da114cf106a9329ffe420e78781b2666a45cd6b25f9b0662aab9fed28ff9bc442cb90f8d61c88ade3465f74bce055a8c555bb	1	0	\\x000000010000000000800003d0e2f3d69e17e138362e7652f2fd5b1bae439bae0e3647ab026802c3a563d78bee3aadd79563b51917359e3dfa6f69bc95fdaf4608331809d8ad2704fd996ab003628b4ce5c3e3e0045e4c20c90303d4a8ee442a87bef5225376c361fbe993418feff5ee1691cd47e137586d32942fa854a71689cc7ffb17e9caf14966778fd7010001	\\x04b9deccf94baaba0983e24fc8f3bbd9d7c797b26cd990923090af1803abe5e7b815422e14787b6cf3d7f577cbc74da02258a4e4bd73e8d3f5faaf51492f6009	1679236415000000	1679841215000000	1742913215000000	1837521215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
58	\\x71e846384ea17b51bcae068347d88a247781ff754c937dbfae6db1ffba7d37275318967c9da1398ecad019483fbfe67d47dc9da033c5e7f5ace5f2cf7bdaf7ed	1	0	\\x000000010000000000800003ca3138a86b07791819bb1ac150da9ec88bed9bf8266a0f3b630d692f374c7f7f6c19b2f9c36958b93759cdeb83b1f1a1c1fe8397dce42acf9c93d1d8e7a925f8a37b74043551861f21b9f3c8c77c83ffadece4667edc80b90b6e1d7fb275d3f086bfdabe65d5022427e34e9e20af8ff89f6d51700164d8dd6c48bd63d1cee331010001	\\x6aae271a4fb73a729f2f8c9a78b7585b49250fefb7f11477642e4d7eb6ca1742f24034d4710161a524fe2c5f968312b6674285d571f1bbdef6fec114249b7606	1664728415000000	1665333215000000	1728405215000000	1823013215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x72e4baa3fd66b9c73b34a769fdfa348054906939e86cfe153163b19eab8bdc3ebbd7448d5b6dda6613a2af921b0c7cd5402ca378aab6e9cc00863511b3398530	1	0	\\x000000010000000000800003a75932139a174eeb7196e8c4c71ec10f722048aa274407fbd149937e8f4f05a63fce3547be5ffd05340c792aec7b6ced58d177e39ff40f8831548f48722ae4666dd44d005e1c944110a603ec2fca62aa5e7f859305d19c8d55e788c67cb6bed3c8346edd7edb1a9da4a954a4fd4ea632adf1d29073dfb1785d2b6d071da11e05010001	\\x3997c590e72dca15f1c4fd18bed43b7dc209f1d4a979b1f6ae1735eac9aad8da70ccdf00a18181d10970e15b4fada54120a5a06665bc0a52287cf7c9a0b6a300	1667146415000000	1667751215000000	1730823215000000	1825431215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x735cb4b4dea6620cad9a124f4d9a5fe8744829b1cfe53bb9bb87d5f643175c2b0aba04a9a6ac629802cad6c542674d97507f71348eeed113cd4b8dbbcc9b12fd	1	0	\\x000000010000000000800003a2561eaf61bc024f897f1abb4344344fbf02533e2fabcaddc3b8d7a4a21cad52a9721f01fcc360805c1a35b89eb6fa9712e39d43abed90e4d8042b4fbbcdd38f47638124e3c3260311f2d0b4bea4570bfc4f43d267ac49ef62aec856b84e51e2c1be04f6e3a51cc8617270818b4ea58772d491cd2352601bd02b0d6365c213fb010001	\\xb5e8e1c57e0a3535d4cbcf635b72c914413ce8ad79bbc0081e9c057858d91704ed81f860eacbc61628c1ba598a22dbb4c4b5a3fbff9e2e55a4b05e0c612ba80a	1665937415000000	1666542215000000	1729614215000000	1824222215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x76e0b32c28365a0bb0c74d0536b3956ca84246c0cb19942ea19ed605ad09ec0c10ab51d5ddd50aaefc89b87a0c76bae3df28ef3b803aef32e2898a9dd6926393	1	0	\\x000000010000000000800003c739b753c65cc0659d592f51bfcf1c56be84635d9c60ce1b6c8477c9b87862df2b0eeb8a3cad9bfed010dd0352523c69235c730819d174c3c0fe99d5260363c8fc881a7c7f2b13742e89af657d40226fb426c9f0828826d1b9acd3ea852bedfd1fa55439820087dadfe4d5dab612a080d85650042e75dc9697b02045061d1a63010001	\\x70548dd08e9cf8e99826a95a2c43804d59055fb275a48762b236d206663a6e5e4ca8e0e95f8453a3a3929b254b0c7873a27e13b2b4d84d99284a6b91e870ed0a	1671377915000000	1671982715000000	1735054715000000	1829662715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x79485549a1d7c0688304c474e78e3081856c4d66f3f06ff37259884e5aba24f6c8b7a074018d39919888e3b8c3352fc711a4bd58335c205e1a8a45715f813229	1	0	\\x0000000100000000008000039b9279f0ead57c68a0b2907944f32f919ca7cf9f85b69f22804e71fb413fcef96d2157847a14e99ee05405e9bd63564dc8bb2281fed66b517ceeeda51ee22025cdc04aa83f63240b14fefc03db942fa8805a364534dc030689725fa36a6694a23c095ea327498b926c8dad7ccb9d11bbfcea2acc4d9569dbb0065390bccd700b010001	\\xf0c3001559f59113f6ac39eae43c99f7b30105b80034b5d619331870e88b13661755c9a93667a1ed1363df3cc88f9ab36499ec58c4f58d9c35995b590f39be0c	1668959915000000	1669564715000000	1732636715000000	1827244715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x7a0c5ebb4e4386fc69b42ac38d6ccc98611beb7db431a93b5af7e59d911d9196e9442c52be7d4e3e4ab21749d86a74e804ae047a3f163ad5dc5021b88d2f0817	1	0	\\x000000010000000000800003cf8a3f6204136a6b0738795a0dd1f7ca0f7249a5a5e60aaa24b685f13d95605a51affb342d7e1e18c11d0da1cdcbf2ae50294913d19e2849f8d26c43da67c21817f7032619ca601d9493ec78c99f8c54a152224b72e01d7836bc6c98895236da3acea26ddd688ca13ed7a25c646e31fa9e9eb4b4ef1f6cfbe8a14181ca6331a5010001	\\x1ec774541944eb7f0c895b8d9d0b23a36d231954ec384da6f8e95268baa9b823199270662e506561f433d9e3f9798f10149c80caf4ff1f766b4b52dacba91a0e	1681049915000000	1681654715000000	1744726715000000	1839334715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x7e5072198c1f661d7cbb69ed9c8efd5f3b053d89d7edc94eaf7a8b3cfd99c36cdbe513126c2a6cc9172d42c2ff436120ee6c3632358856720d3f31c00a1d6285	1	0	\\x0000000100000000008000039f593d040c1c244e07f477a073bb05243427589e9eec0706a7c8cebe6efad4df98429bf2136e1368237cc48a20504f97c0ef4ce4efc7deda341038b9235518ecc705f0889cf27cd45ebbb044f3dc72f9b3d0ae87327151ff9b71e7990287165ad6de3a8e901ff895eb5a21a0c88cb6e3d1eddbad431b3035d82661b6fe99e473010001	\\xd9e156a7836a144b995e28d876f3fd40e176223499acb93b67665b92e8896b992df5f7a6c0fc31e8bec57ded493a4c287bd866b8809e057f735a15a69e59e502	1671982415000000	1672587215000000	1735659215000000	1830267215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
65	\\x848cbb67a128f98e1359dcb33e8c9b83d348a7d83aa15a506084e707419213becf016be1bf7f59a873e3625ec2a95892938c63bb2b4028c189ddc2177e18c891	1	0	\\x000000010000000000800003b7357ac6b2f9e2847fc3c0463ac88169a70110b7f789846d672118a7e0c9301a96e040e466ed3ebff953a1e9d8e40b0d1ccc4066451dcf867aa4f8d9a83f1043c82902eb963bc0ff46b8c799a5a66629aeafa7d15b1619b61d87372bd245545fd0a369f10a0d29f53f1a9a7fd3a184626781f7217d89459563970533ba8eac59010001	\\xbbf4a60b425a519891486b2160e976c5b52496b2a794ccf239981200664756cb41d3152657abb7b82fa440977a17ba12c46431fbd7a803ccf63b1d4d5b2f930b	1662914915000000	1663519715000000	1726591715000000	1821199715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\x84b877acb971b715da8c363f9822b6214b00e476c05ecf512a62f70f7a4cf2dc721161f0353703d57fd83f6836fac057e0a2ab166610c46a79f0471c50fa4e4c	1	0	\\x000000010000000000800003d17dc103ed8d3317b8d49efe4091193c46713aac1cabfb2ecaed0c1900584396ebc8c0e0663fdf3f70ef257c3b06259831899e2aa5870740bf48a9bd4c3eeba32dee3a47938a44c6b57149f107d2ba79df00fba19c5089a19977b3a5b0b3deb8f3e0a99505edf380fc1077d3fd6779d37f4a7d546db7b0a00f68194fe4636a99010001	\\xeffa9205aa4c1ba0a13c06d800ec1776fdf8367c6604a7a90656607720aaf3f0d200e1db131a436955c83d2ae5f15b6cd4e124f1f66110fdf6cf301a17abac08	1682258915000000	1682863715000000	1745935715000000	1840543715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
67	\\x89007d6e976f132a3cad6c75f03d1f35168700eb6d99bb7032c50c23d68b9cfcde9d5de527ba432adf60d041c38e804f2398226bba2936a492c9496dfb2b2aea	1	0	\\x000000010000000000800003e64c112342e2bb9badad7251e5a19896d9d2b6ffa2ee461c16f2a3f38df3fe1fe71c7474b113acbaafbdde90daaf9d80f80a03aed6855a2f1b3d2bb15c57cc9696f4ac9d084759c1b7f18a1a55f7a22ffaafe5e3d93ac7f9a3542623bcc28fd41c4d8fe30cc5663ccb939a06cee13fbbd8d381e687fbb895c6e11aecb7fde3e5010001	\\xbcdf5e22f5ef0e4aedf5d24e5f1f2478b073f2c42764925cbaeca92274048c663c04a30b75609dfa589f7ce4a31277e86394a754443aa8e260d902cb660aa702	1677422915000000	1678027715000000	1741099715000000	1835707715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\x89f061e16beeb96dbd8ea9f9f45c808f54fd1548a27d4fbf3b9429ac967bfb8f1d88469230dbc038d64f6fa301122df4eabdfcc8cca452f7e2973bee6b4939a7	1	0	\\x000000010000000000800003b4d49ec8d3e9f12aa8e8aea4a945f430d7b17c42cfdc322047cd37b99cb4ca0b2cece04f8bc383bf44231d49655d4b519d6cf6ceb2f738379dceda5e35979065f5f272f85bd1ac934b4fa2d2bdfd89aa2a88c163a16fd72d48c6e7eb4962a5e02ab6c809b882686a27ea80faea92d021e95b46c37fdfbe88593e1e4a2519c4b5010001	\\x6e68e0112afdecefa9fc605631b0c50393b6a336a0ba8c9f6c09630183308414d4d4388af28ab560c9f41d820fe493702de76cc1243d0b65e17b2dddc91a4900	1675004915000000	1675609715000000	1738681715000000	1833289715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\x8a94494696fe220d342605a5c72e9ab58fc34c681094f6ab5cc5315484130ad5c802dd5af603a35647b77af3ff89f2360df76b44d836e120800d6a2df02048bf	1	0	\\x000000010000000000800003ead470e20155faa02009083272cf438d7bcf3847326ad06def545491c005e2cb03f150d31d6173ce923109d065d23c612e6c3835b7c10a63844804d804b019d409be65f76e9ad06669b38ec10a9acca112d3c85a066a4ef97eac5549b3db45a8d3b8b0a9bc3eb2e1284bb7e6808e43435a2532d802eb7bbdaa89b0ccd5a26495010001	\\xefcf21f60c698e2d651e33fa8b34ddea2342f4c6b066cee43ac10ba1917cb8ff10bb7e309e1d8033ac068f49b081a9d4595070fec4b0e20fe77c936d35506700	1666541915000000	1667146715000000	1730218715000000	1824826715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
70	\\x8ab0ad3b75d5ec4b7797f0b16a83fa4df4ae9b03ef4043b61e3c8b7571191085e6edd7221d10416a165bcbfb7f8f7bed923cf2b00553189994e1578dcdf0fe8c	1	0	\\x000000010000000000800003ecffb8967606ddfc45740dddc859c6b139eb9b79777995a51cb70301492a61ced5228dc9129971cba5ff0e382f2c878df1ba54ca79d1698526a44a32e748c87f64106733d6b3da34bef7e7cb568858322995864922a3a72052c65886ff094894685d851178bcdac8f141ac4be6de539fd2f3a64e145e2db55093843c0f29ad01010001	\\xd069424eb66dca19d1ec11d23190ca4f7114456cda0ae4e3cda28d1ac08766cf7dfcdfc5517368b9b92da7083f91374168395c0c017824b8d92e44d9d780f700	1665937415000000	1666542215000000	1729614215000000	1824222215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\x8d1cf40d7f1edecdf01531f4c42f11fe98c652c54fa23983d9805d24fcde13e6b983647c2f6e6e92bcf2dcf31040081dcdda1f36142c7fba1c62c65539247cfa	1	0	\\x000000010000000000800003a5fb9563fd55764a6137f6408653cffcee4ff9b4c106ef2b48726571efcac3b4865c17a21371c4f43c6ed0ae20ebf6660403854d2b2184d2aa420c2c9fed6bef9e6ffb3e3f8307b9e4ce931bd5fe06b6c439dd7e381f38030daddd34a4e983f9291c52f905e948bf2936c59919d8824c8f31bd25eacfac3ddea03254ed262769010001	\\xad67a37de3ba0b4bf58cc5d46b73d2c881818b8bee07a6dcfefbaf9395a63aeffb806f76a211965ead52f7e406ae814d5915397bbcc7f1966d3b394fa20c5c00	1690721915000000	1691326715000000	1754398715000000	1849006715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\x8f18fece864b7cc1fb90923df923ca3ef10b41292293daf42db648ee5b0f1ffa430d8b41f39434875f8abdc3c8d251670e4b61d65214232810fa0239e59f0b44	1	0	\\x000000010000000000800003eac6670588f6a9ee3362ac190c9d189e36f1d8203911042e6db6c4cf5042d81e33dfe0124210ad3f22e9dbdc96f35de3aadd3bdcb77eaadc6a224dcca78972275f3ecbd0951ad47484f16d6a9022d634acbe284716498f17b5c2dee9633cdbbb18a6fcad2cd139843c0c434a36ff24e74a7bba436df0ed4087a3ce97512eb149010001	\\x0ba230cf952660c39b7f1d1afdb1d22209da44e79464a6b89f02b010f106b6c70b228282fc80c1715a86a3337fc98ab58a41278f830a8dcd35b3a0a696eedb04	1664123915000000	1664728715000000	1727800715000000	1822408715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
73	\\x910c4864870543b2b0799ad80ac6402869a4bafc0918fab65442320e2d42739bee20e998d2807fc364c62ee4ebaeb519c712216e8f68f75116b41c4fd86debd6	1	0	\\x000000010000000000800003b001d89d7dcca25451ed8db3711ba58220c3e5569cce1d4a7a97708a27524e6c27e100365c7ee317c83ba7e5f076c41e26cfbc6f2ed227d99a0e780daf329ce9f0cfcb2808a13ac96c49b8554f8e75f3c638aa148295619f885a67850eb35bfebc73a5c34660f09edd008cac22b7a994d733001e6a50492f18b8d319bbf09b51010001	\\x699f594f1bcbea7bdcb788bac6c23ec8f29eba2244aadc0e9717e3dac64c942bfffcaecd141b71835d696130e32cd58e7eca50d23c2bd6fd5881a3ba2cb2720a	1685281415000000	1685886215000000	1748958215000000	1843566215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
74	\\x9330ad3ff7ebaaa5769005cd36560a7070cbc3b9ec366021595f177ae9f2ce5e54b081b930511372343a896cf0e4be39673cf8ec682054b0dc2d73a76d97877b	1	0	\\x000000010000000000800003b15ffe9a9bea304d450634f6e9e87d7104ac2827d4a366182be7f52a7ce715952683112afe3213eabba2285579389dc57d4bb2a417a14df3a5d8e638188f4c949e9267f26676a801d364c23d7e169a93a95c5d04d7c9cb72e951eb7399ea9571acb5d81187f6e56997759348d392afe54680ff824a3d04f0ea2f7972ee404e3f010001	\\xcb748722cd5d0c23e4f74cb47cad841d1e818b8385d6a658ef03afff6116e5092401492e282a87f2bf7aab1c6f76501c647d534a40e3bb28d129d740526b3c03	1676213915000000	1676818715000000	1739890715000000	1834498715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
75	\\x9364bff5723e8c0251d9325bbe616c9ccc6514e031cf8a09e2e7146fa31edb64b3defbb91dfe12c37a2c3d14ec6874b7cd3e26a65c40ac0406517722b7582443	1	0	\\x000000010000000000800003e060079b20f084ad6c41639fc453c9d1ddb7cb3e931d462a45bc65add6316a586dd5f9a41c5162596ccb8e7cc447f4038b39141c42452996b0071fe8b92be7873c70149d33b12f9fb6dafb51aa21d850a51275096b911b1891281cf3a9c3320ba2f93e9666cc3782e18efc89d1c3a420540bb9902075c7822dd7e8907be20ddb010001	\\xcf03ea40a1b30114a18bb4e408fcedbbd1ab252a16dc37432614487f1b9fe0d551306571a6311876bb51aa9dbfb7d00f20ab1e04e249a2aeb790faa179adf20a	1663519415000000	1664124215000000	1727196215000000	1821804215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\x95c45fb67125e4d4799e3e9fa7252206e00ff83449ffd87b96d88a6c7c7be4dcd34a8369b60c7035de84a211f7cfb283463e58f34dba2bf39edcbd64e0c1961c	1	0	\\x000000010000000000800003992e8e58fb06f66f58f7000888ede435d451843d8dbbbbd4ac7b2cd0417db8cc95941b99934e714c463e9f40227cf28e0c57fff26539d18939c214178b0995bffccc920128c25cf0878d8ebb0ccddaeb5922b3a7c9dbad37fbd624af049c9bea5ea1126f44118f844d7a705f7fae7f105c54e5f79386e4c65785ec59d8fb036b010001	\\xb363f30ce8f07193623db674368d4bfc3035bc47fb18134a8be1ea7e95ffd664dc130a9c3279c49dcdeb5448ea1cd242ad2202865b0aa023512b7bddec1fe003	1661705915000000	1662310715000000	1725382715000000	1819990715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
77	\\x98fc564c28081641c6cf2838e55ce942bf3a98b35b766c992c8564bf608e7b335721f68de8a66e368ffe0498dd9c73df071a5f606c8a2c1069747d7f24a73c16	1	0	\\x000000010000000000800003d9a048f66a5e418a4baf65c386930fd2671c36f4058920c29908dd16bbb3793b2054985b5a262596cef7b492ecef9997af6a5d88f57af690cfa6c296bc456ff8176e21bcb903f55cf7828795ff66e3b2e4053932e097a59a07a2394a7776c5a111e71017f28e6b3fdb0ea34ee4270db9a8fe49de31ecd3aa161220b34317520f010001	\\xab0b7a6edfe58c77f3e93057f8355cb1e56f1ebbfffb2872f44e9ed2f1d941cedb59f6347ce30febac789912c5517dfc07daabd0eabb1b1167743034edb45e06	1679236415000000	1679841215000000	1742913215000000	1837521215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\x9d302b9a51e9baebba01d9a9ce53b2f0996ac4490b5726534a42c8a82b5e4caac3d45e98793cac862d93149c8e4f364b78086aa3631aa5faddcddd646462f90d	1	0	\\x000000010000000000800003bc9932d9093c12251c42a1bd55c4ae0a96a1613311672a6f2212f6536c4fb06f100d53009d3fa128a9ebc80ee55bcb00b931c697b519016249047ab173d3c088453d58a664b63ecca141108a02af6ee78263779f8285a567a71f10cae6399ce0d7a83f14870efc9bca3efec69880e9cd6fbdd13a269fc62927ad9e831ca8b157010001	\\x7f0f1d5fd5b3a7c7955cf70f20d36697b448a7167090c2166255c44fea43ce9b74038a49870117d860d76e999d6f5eba8da8d9c3b5be4b71ac7681c5220a680c	1685885915000000	1686490715000000	1749562715000000	1844170715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\x9fc827fc1db8ae06672d1f378f77e6e2ee9a3bb3fc0cea1b3aa24e1952bf25ac248d616e91bda2eb5c9d5cd159ef83b73b2aba10a1e84c1e0bbbe37326cf96f2	1	0	\\x000000010000000000800003f4693ee01dd052734064ea6870fcdf23737bfd59ba099c1ccb98b2784815189658fe8c1411c6bfdd808f94f5ba1141771386d1587cf9481866401622ef74c8dd5e28cf077fce5a0028c1917768d2a5c88733c8dd170d5b7f0adb5b5baac79f029a33e23d1d8d26bd7df1efe2fc9194d1370a89bb8bafaa31558eb8fd9af32665010001	\\x75fb3df4aa343e7bf61d87538ab53adfab4f3bd1cd64513f75945208ab40e748abca844a7f4391185e6b69c0bcf04e1f2fcff22df4f3dd88645bb2fd94a9db0e	1668355415000000	1668960215000000	1732032215000000	1826640215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xa1389d4974bf89c9c98105d0eb61bfcbb4e388445422f8cd833b669c08a3bb373490044dce0bc105f58f0bab9e411a7118c8c792d7619f7bd5b4dc11b868417f	1	0	\\x000000010000000000800003be742a202b7d0b01982450974d3916655a12e6717b6196a993a97648cc46bc7a7da85296824ba94a2cb948e7f499f2c9c0948861df53f1c80fafdbb3cfca3e0f6586164092ff652f459d92068cea390c0fd052e0db5ce6603733ef7e59c6ca1c3639918fbceccbaeab3f1d46bb381336df82e51fa2eed68492ab7ba5164d5f81010001	\\xd5243b7b1708809dc217cccdeeabd8c44bfcbc0351183039ab4e2211812dd8cbad9cb43c666697c6c1242f601ca087603fc3cab82b5b55a0aafd70e372180e0b	1687094915000000	1687699715000000	1750771715000000	1845379715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xa4ac1aea11054fbce67e3727189e3594809fa35641d6d35900ae435c69c401dbef05ae11ddbec550c6e58d2408078b5bc134e4cf484bae85c0ee32ee2385bde8	1	0	\\x000000010000000000800003cfac7a8e9b3fbc16ef8e73dadfbd3fa40b1e46256601044e7598b64986817a455be257ec07243bb79b82f6a5de5e51225f2440a0e466e3c50eee802ed8d15cd5e9c228b3b38dde7021a0e69790c232053bf460e1728ba17fc428467ec31ffcca58cb27dedfa2f31f754a2d1200f6561c99c9f91126a2d6984184ac43c8532023010001	\\x8d314d7d6928bc291bec728775d09e403f29229b97b3b7e4d73e75e4b024485ccfb233130a1c6cca9c2aba4b57f9d5a5884e644f8ec94c7ba667ce0dfbeb2402	1670773415000000	1671378215000000	1734450215000000	1829058215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xa8703f6f4aac0372d36247dfbfe92dadc2eb2d1067a02353d0e3bd1b7d877a72e3b5860218401d55547c11b46252768eca19b012203f76aabdfbb452714b0693	1	0	\\x0000000100000000008000039de0ddef72e48eb4a04d73b6ce0ec07ab8115380748d6f7db620d4e4d1733aed46d13414e4cefe90146aadb5c1c011161771f505f6e162a7e5cbb6c9d53ad9f58b0e7f3f193b9d74334be4c9a6317a2d823e0664b45472f4a54031916fb8344480eeb35c7d0de1e25b8e3c8fdb4e74efeb4023e0a32595ce0571f596c3a8e8b9010001	\\xaa7ab066e2ba6638f133cbe453314dc02552fda064558fda6b6d02b05c540645776d44ddbe173ccb3e84429437d14a9471a7f8cbad3bb103308678a3e4904204	1668355415000000	1668960215000000	1732032215000000	1826640215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xa9c8614442c3f46c88df0a8a5f4ea6e85a399d203a732253cdcb84034160f62012736dbc1d6d25f7dca85c0331b958e75f0fd6cb3b61dec1fd311c5964ce12ac	1	0	\\x000000010000000000800003b85712d0693883531379d1c916b9f4e1e986c3b821905649f765d0b1f0f9cdee37261d242f4415471131f00333cf5557076ade15c20dccaea173e6e2384ee2dc4da7afe0c55c0ffe2d870952adf2ab09435bf95340d60e12e536e1d219f6b35ef3add3f90cd8af1b40c7ca30d2ee1d25595b75fca91e172e27b907491b332705010001	\\xfd7b1bc229c64d73a3fed3b4a7131441e5017de4dbf080964367105dbb5acaf2b50100bd3b93aa302c4772db18a6c0ed44547716bade2db5f2248529d5bd750e	1672586915000000	1673191715000000	1736263715000000	1830871715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xac14c1530397c5af637ae96a3b5f09c5ceefaefe44b8fb56bf969ef433831f1033916f2400a296a3a147c4de3523889d284be7aa3cd8ad367682df70083ef4d6	1	0	\\x000000010000000000800003c5c8a8fccfec477371a69b2a246e6c6666068bde0f089897af59be0d45979adfb303f4b35f736d6ad88402ba24647ab4cf6a0d6fc254303a620e59b404ac93a9525fff9d299ceac24c3014630642a7337daa3316a9c29089b1af0797e79bd480f799a3c0e0fe7b6187ed93108ced82db8a384565d87a57bddb9db2bb2c63f9ab010001	\\x676d8871cc125de7cb2d9f178822e8129a594484458ec374e31bc3c197f19d71a45aadf79defd6ed98581b233142f865d0963415025b615ad6e2497a98156a08	1676818415000000	1677423215000000	1740495215000000	1835103215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xae0c487fe9469df50aaf0f3040ebd176c0f92ea44b3d1d6753af3a150a238277813834df938f3d26c5d63f975435036d9dbc20c61408bcda097b090c3284c852	1	0	\\x000000010000000000800003b17dd6784579b5f0285ff8b77b83711b4c4f7e16ac906aa52746f3ca5a7b1836313a9ac59f18caf2ea78c8d49be1c71874622d4b7b44ff8eb48b3532bcea03dace2458fe4e75167882e99dd94974e616c301036d62d97cabc34e95fade3b80d5464becfd97c9b88f49740b828392187b3ce0b2944835624302c9d7d6cd401d75010001	\\x3b16bf084be50050b59111aaa1907cc43b7b916126821522473cf988276c245cbf3672e895f65aafc34befc0e02191375f1c2d90e9ea6d411881a09d1f302a00	1667146415000000	1667751215000000	1730823215000000	1825431215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xafbcf7e352a0d639c4a71765b8325fddd430046a4c3738a5523625730cdd6921c5bd4cb4457bfae46b8728534918443838d5afbad324a494b86a21c175c1a892	1	0	\\x000000010000000000800003cab3e75f931dd7bc60b5cef2d6ed7cd9d39c4b16d69197b1cce08ff0e9f6ef8ad3d7978dc0a5e0596c317c55cb72b8f458a527462662c4de955e8fd172c3cda88fa3838791e37421a1fe4aecdfbe89c56590327e89c76e9fd84d023772bda6c7411ba96e78ab1749026e20b3dfd3b18314a4f4ef1e391d618f7ce31f7ddf6481010001	\\xcb33135ea280ca72500568e49d577e5f138973441aac4d9a78a5cd85bc91f24aa0269d2d6cf6a1553326c1c935cb5b5bb7f92accee518b5974134c21257ae902	1675609415000000	1676214215000000	1739286215000000	1833894215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xb254556b20b9b3c3abf5f40656fe953e13784b9452e3d97af481cce1b7f73863e1de6ee763671ac243272cb2b16244ead09da7ebbc4a5118b79b0ab0cb240c5a	1	0	\\x000000010000000000800003b7c68479ac58602f79148c1c5a7ec61960190d241f779b6be3cffe9c84f09f5286783c4e3b1de54b7aac2b0c259a371f0f92f6cdabf2dbb8e7907a617eecbd33ac9082439f9cdd6bb19b86611d9b2fa0a7c956bfb41a24ea5fa2cc09edcede3a9cb9076592a2bb647844ca36bdacb0848f1e8389e0a1c6fc17fee99354fdc471010001	\\x277857221c71b7b9b2912948a22339413b5da596963b0b419ca73c9e117ffb720ddade57f72e33abc2574bf7c11415862daf86db3c9e8dc73eb496589c588900	1676818415000000	1677423215000000	1740495215000000	1835103215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
88	\\xb33c6ede4d04b07e4a6c6e95209154bc9964ce64183e35d7fb0b58499ea4a482a8de63994c084fc6b85d32a1c3a3cdcfcba0462f5cbe6744671077d418705d76	1	0	\\x000000010000000000800003d9337118fa44606f8db0f29e0f9b15c46f34c9737d9d53f4224d70d2941937618f647fedad6db499dafd8fe28eb58d1630203ca2a82dd482dad4e88b5af5b3daf474af4f072a9ffad2627fb0cc0d6ceaa49da0a169f13d235f3092680b9c9eeff530673c7c9f1e4ea55301700a0db6fe0e50a75ba478f457a9158b73990e1de5010001	\\xce962a63bcc25397a91c5eebb6833d11f05483539adea5d6515136946f0269cbb32e90a9c7be7a770a96f2e76a5aae086ef07d233050cfc6b8c781eff5a1df05	1683467915000000	1684072715000000	1747144715000000	1841752715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xb86ce3f7c95b84725a462858f3c80e58f3e3a8e7b56a23555b02d4a9b8889c67c879c910b67fe9e9f27890bab9972a341d9507403b7e2113f469839b43549aae	1	0	\\x000000010000000000800003f2e43819fdc7b27613a8846d32da313a4b4c74adc35f0ca1616cc214d4b911b8a9b390f7e6c114608c81b859459198dff621dd3f38c4ea9f7c41e4448445939494b04e0203865a51b5961dac3ca0ac6c3f74a0bb2b9d698efbc4efff0884b50070cda18890468dc271e3651024c43382206e46a6b82c9ee86aaf858a6561d26f010001	\\xf98cbd892ab1cb3453cea81cdcb132fb990e077ba86c5ec99a9e825daad0526a11efe8a012665cf44aff4127dab0370e76a7094575c865c7c78058c2e481e505	1662310415000000	1662915215000000	1725987215000000	1820595215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xb8cc4ad0ab6df3ccd41e52dcbdbf7004c1898e471cbfc46f66a7bb2252d522e702b9c028a91abca3ca101178270a9e81fb4f5333d2ba118659c8768918f54a3a	1	0	\\x000000010000000000800003c1ac919eee930165640c8ee32a032469c1ee9cc4452329ee7ba5612e198c1f40d4662adb028e65e908e6c36ffeb7baa58227b203fbd0f7ae365a6e4c93097f19e16923865bd50f601c5e10939933b7f2df23d67c51da5644e74e2e4db8da1e29541360cee9c010f57100f834bd22d7e54b53b356644de62f2a018835bdacad59010001	\\x753df5337a925789a7426838e1587b5df826433845df48e215c2db9c1f1ed8bf9dd01f8b2fe36e3a7d078d2938c98e95ccf6a4f6cc77688a2d3b4245bfd07100	1685281415000000	1685886215000000	1748958215000000	1843566215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xbfbc4b2cbe288e906c01dda2d06336fc50847cbb3563079b216dcd25e27f4f51928a0c99c4e901af793bf01c308fbadefc9c316e387444542e06f69fc7791c69	1	0	\\x000000010000000000800003bced60287e8ad300c878c641ea91415239fe5a83e81b0c68f27ffe9544e89283576d0c96b11a1822cf15d44ba4c177e01519065449f39a17955761a1f4d334f9f93659b054d12cc866df833c287f80195666c20ff8d68ae813b6200e63bf84758d472e1d07f268b1b1be02d89c0658ed50a18e535cfb86e7893b22561d409aaf010001	\\xc452b5661045f03b15bb395b11194bfc77caaad129beedfbfa8cd5cfd9288ac195bd43acfcf7ff2b7022df03bfb4642a98b852b9d677a8d15c6924aa01402105	1687094915000000	1687699715000000	1750771715000000	1845379715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xc5cc5714d8ee42424ec1af0f25dc7a3458b40514857ce276b794c76379bb9b13b3034723dbfef6b2e507c7c3898cbc826d0d2e1984e7fe6f8ac1478e65bcf6f9	1	0	\\x000000010000000000800003c4f2eb16b3b0ca671b0d2666032f81e1b5ccad9520c3fbc1c90964b561d1ae6c3ee3c1e97c55ed169c1fc6299bc4e473e7d179ce61e8b804b27d692198df7546b8e2eb631b76b2a3902aa570d282dc87d6fdf7645ffcffb386e896ba6dbf83e68255f2005c25aea2b1df614b14b42e30158e0400b48ac65b69f090e2f12e29e3010001	\\x763a3e1beb8a574f87b740ce9821818bee3cdce255f3c54f126c1f05e384f1dcdb3ed4d24672c0b52a5c6bac26f75ea0fde74c416a3635c4fe84b897f0419f06	1675609415000000	1676214215000000	1739286215000000	1833894215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
93	\\xcedc0fe036400c6860e8ed26c15d43e1c9cde5304e60a2de751c0fc515391d3f048cfe338bdd5ecdd90904d00394a6a4dcd04d0145a696b53dc968fd430e3895	1	0	\\x000000010000000000800003db90594a2ce26d691a78bc1c8fd25941442ada1cefdef90962841c952b01350ebf0197b75e3496c3777681f7b8caf4100889db175f36ee1ef532066f793a49d3c252956c0ecd16b276bb23e36550134154e8681cfacc5ecd759c5fc6c5e36bf2efe175facb1b06ab4b61a9ddba3c9f08d2523d8110a501bf0f16e9f23927ff13010001	\\x439849c619497f0c0890b48cfb77fca52e54e6901727b217e48ab410f06ee10075b679ad78688154d3653d7919099e77d79c94c2dfc373ca9a2c54c1dedc7701	1691930915000000	1692535715000000	1755607715000000	1850215715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xd2e43c15e7603548e7a3ca856272331cb194ab05bf128aaed3d5b8c3b89aec354be5b6f47bcf9330db716bac350a8a21a88c08f1fc2c882c45526b93fee501a5	1	0	\\x000000010000000000800003b96a51d6d772751d3757ec3aa65e22b3f458e21df0b7e55e515e1d6e8d2f6a20091bf396babf16211b063740499f28240cb9cdc1b541294162a7d7d2dae25b0352563f06f80297a41ef4069e267f9821d329b172eea762f951c4a04b791f828cb67986b8bda5db0e71b5cdcfaacfd66f151284f5f481845c1b035c8d8aebee8d010001	\\x93653dfc5d4471af11d3c466449c346c0c5f3e56078456c6dd42d6896c87d9cc256c55678c098dce216857b776dbc9a66a4d6b5996c5216524f0a14bd6c0ee0e	1690117415000000	1690722215000000	1753794215000000	1848402215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xd3406b9019f5793c9caefbbed3c40e03f86d0d11e2ff2c4da5fc00bb2a560758b0d4b6fce1bdd422144c49964f3a16578ae956936944784bea89b1deda8bb367	1	0	\\x000000010000000000800003b1f1f4cf540e62aef8e6e47bc6eed54540006c5242ae733220c266f14c050feac91ba477f881b3b03482a8b2342ced8123237467f892f07c2bcef3575238b7fc7f38760bc1fca32aee563a14f6e4d229a324d56628a74f48b29af8b8bf397c5aafdf53fa6e6314eab1a75b89febf484d604b967b32d6033c81df6ef1e1b624e3010001	\\x6f155be970ac0c36c4d96ee029895e8e163a22a29f8449b613621b2abece3da3075458b5ab90bc69954fb9fabdcf176364e705251447220007769e9b83edea01	1685885915000000	1686490715000000	1749562715000000	1844170715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xd4bc4a9f48d7db968745f520a7e89b824d679a82d245c8407a1cac93489ab33431b967c28a65d1843cf60bfefb72abc2c2f96662770c37b8d5f4bf78d42bb3b5	1	0	\\x000000010000000000800003c952c61912641eb86585cc3b0f255572a8b4d3bf7b604919fd6e0d7d01aa818a2788e93444cd82b9458fb0bf6cf305dd4ee191254028aacc11b65f8ff3344c51b8542bd2bf0e59c1e32469d2999f7b8461a725b01b3b38ab24cf1bb6fcc534aacd4fa6cb842030e476f4ddc59b9b4b89f652eb64686ef6a6a70bad59cde95049010001	\\x19f6e408aa2a30bb5d33aa7228d16a1080a69e95459d44aa6dd253a259d471622acb049fd1f4e6d66ca18e10e708bd50bf1fd5e6ee733a2dfb198e506eeffb00	1679840915000000	1680445715000000	1743517715000000	1838125715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
97	\\xd50cc9f7504c40ec6698a2215df3e0187dd6deaa1313c0d5fee127ae09ab0fbc90d0fc69190594b0c08b2836bc57a2c95869119b05af3ea30647aac77275dcb7	1	0	\\x000000010000000000800003b51b78a053768cf280df080cc1c0e1c11fefb24c8acb7e66958a32def9fa95388a5d54cfec3866b23db2c3172576f7f9b29f78ba0fcd15a90112b81961b1bf4466972766dce165c0949da4b422f4955587332f369481919d7261e1e8b3b61386873ed4bb8743f5aed09ede252684f72a611751a111743df75d491692e7e1f5f7010001	\\x5ddd03f59cd12101544faa3534b196d3a84508683638da5c1156ccfe0344597234ca2206f4b624e4bb7452666183aca0695dd1b52e46c67e71ad6390a16f7501	1689512915000000	1690117715000000	1753189715000000	1847797715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xda64525adacfee9a1683a65dcc46423fa81cf48db4fbc1dc7ca5f99a023b0ad3defc372be256b915b29355c96b91cbed61f91aff90f14977def1b315c87c85cb	1	0	\\x000000010000000000800003ecff7c5143be6d2df62d73c223880acfaafefeffc4c01e67e9e767e91ac9732dfbfc3dc3e89b2d1a3aba25f7d1904c9778c3ac5a78f9c7d0c7feb715d50b78d8fd308ca38670df125299b9badd77f230b68fe08a9458251a9e85385d85317744bb95d288eac1aaa766d47dd98e8e1ca805e18096ee8d949c25df119bfa41bb21010001	\\x66b48423af9924870d3fdd18448c34ee52dea0db07134ec7ef2fb155d3b178783f7e4b520151b5f07e252019e3735e0767ce7997f31061b4d5bf0fd96743b400	1686490415000000	1687095215000000	1750167215000000	1844775215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xdf3812bdb8a6ba3bbfdcfa97ac5617c8fc50a92da9feb18354783dd4216f1460aa83f4e1c2ca20f3d3168b6866382ef375ec7f7b486253643f08175ccd6b94f0	1	0	\\x000000010000000000800003c2885cc18f7923390c3c6248ae4c597a8d25160c320ccb4eb4b6cc4e627ce0aa5e337a17b88c254c968cea1017652b689b5a077900b55b1ee43bc3c39405974edb3dfa18ff334f8d96cd57bea91acc0f0f6a4cdc2719dcc72f7cbdd9b65af4f1e57dbc5b82bf689ab113db2a9e4e9fa0947cb1437bb156c9a2f03bd10233f0e3010001	\\xf41483dff17beefffde9b7f9414cc206a57684857f6cb1add549d3923e6258e9d3206e6337d8b56eb9218fe86729e0e6af6bd92919825ef05006860c5c110e06	1676818415000000	1677423215000000	1740495215000000	1835103215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xe208a11552d23a683ba47a063aa2c8878c36d570ab8c5392a629f2b8ab572b83a2131db659c096447e88eaa381f28b4f1b65927ce2440764c3dc140f9a709602	1	0	\\x000000010000000000800003efe1956d2aa9d59a810cbca95b65e1a80c3af132d7b7d0d473af10751945760398ab8d15f990b0679ffa8d6366d2d6ba94b30288386ae887d0839812947e36f243bb76cb1509997567bf438f023d35a597abed487c36ec3e7d931a97c9421d949473e44089618c0701a8992a5d1483f9662139a0a63a8fce705b288c787da17b010001	\\xff4a802cc5677e0f23b564600206ee9540a8423fc216cd1791e54e9f6539e38e9ee44d737f6d533c349fa3c12e27be47aa443e04875a93d13720d5f17ab4b607	1673795915000000	1674400715000000	1737472715000000	1832080715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xe318aef5a2865c2baddd627a8c9ffe50581655712aabc9fb0008aadf59dfc02c2545c9be1feca0129b4b8212cdb3987e58167303ce3bb1f1e2eeeee095dab548	1	0	\\x000000010000000000800003b0b12ae1777347aef4a5a6c1352de5764cc3561cbefb35cfabf33f6b5fce6d0d792ae2f87cb730504ee01673f8d23346f74b49c1b28891ae925b4d19d16b22d9b35d2ce35174be265938e2a26b4162178db3592a2ce20d9e9356bc061aefff025947d9c022fe9bfcfcd3a08d4a4c4372c03f1ad4a1d5297a6350a33becffccc5010001	\\x3d93128ba00a79cc75c20f9f19d16c4f1d2b4fe6907b587091ce5842184e7c83988290d78496b28b2c7e87929aafbb685c7c5dff4be4a6ef6e32f346802fcf0e	1690117415000000	1690722215000000	1753794215000000	1848402215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xe3a01bdda14a99b407b9a1e49cb845a8ac551549fcb7273597a69b42069926cb5d735256cc59f3f1d06491a47d83cce887bd74f8885ff3edb62fea79837df904	1	0	\\x000000010000000000800003c2cdea992841707d92047fc22775d1ad3873866463f46e288f6981afed7c48123ad8bd4a9a292e46f8642905f506ada23ea6f4831f11738d5e51454fd290b8e6631b5cdce8dc5eb80905ebaa2afb0c39550854b0877fbd1f67fa1c52e871e3564c49b20dd5833cbb53b148f753b1d36a44a0e568d4bb84f18cb9313fee20b777010001	\\x38069af2b7d9d9b448be829f6888ef71ab71399edc0557f6371e0fb3668ec510b5e7e5738346019f7b05579fb3cb95d1516444d72fbe8c69ee251d16e9c9ce01	1683467915000000	1684072715000000	1747144715000000	1841752715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xe61c948f2954f0bc0884af6bd8e0d1584e3bdec2dde49387b9fdb1a24575ded7dba6a554af04dfef5a62161d7883106c40b9b4eab99f0b77fd722f9909914cf7	1	0	\\x000000010000000000800003bd64d1bb9a670a481761697b932f2a690917d9090b2a6551a4248c07a3a686a8715bb01dbbfef62606ffb6c6e4afe1e565d043c1d05d2ece95f4cbf3c61da50483ca1338b24ecc8fc77bf109936d381c8e8fbfacf94ba7d9b1e62e0080cfc459d5f3c5653de491644922eb5e3fe9cb423f6bc431673bd7b9bd07aa2afb1ff3f5010001	\\x5b9c7e9916c5c53872f543ec88c8edafec222826838292aeb0faa5fcc6ffad4fb551ec21f2a76ea681a6b863ad04e4296dbc6bf15266908e7e44044b35ecf101	1673795915000000	1674400715000000	1737472715000000	1832080715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xe7b0a0d637daa381dcd80c58a7fba18490d693e7ada22d8cac72321921bab3a6869a385d340150777a228578f620b13a739e1a91c9a2dfa01e068abaf5452593	1	0	\\x000000010000000000800003ad1bcdbe6de4ddec6c27fa0c76399fcc403e3c19eb5c4828bf68f59094f81de2dedfc5a16d676163a0e8453c20fcb8c6ed700f13cac86ab8f4e7dc9cdf9192a831e086d7909cacb2fba18b4961302ea6cc147c2d15ac4f34bfa7d510655564e4d2dad36bc7ea47df65147fc3150320142b7ea30363fdf1d0845422f72cf3cc59010001	\\x6e00c93da7c3a50401f5388a8883dc6b2bfb7c0d4f20e54b0587313794b1b5a84f9c73e2e80daf240cd923c1744f384e21843d5407d6ae9ba1f8e8a4caa3600f	1685885915000000	1686490715000000	1749562715000000	1844170715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
105	\\xe93c9fc82218adbe921031f1fc7806e6f4ba8a58c0b20d72a831ee348c97a408f9ec3215450da191219c7271828fceda1f65ce7d7bcffb8491946718fe64a52f	1	0	\\x000000010000000000800003ce99dc90c8d697a9db4e0802b10d36684a39169a57f5b4fe02f0379e6929c124d92897f04821d0a53835e7881fb7a58773cb8b027982144c7b58cd2668353ca75a978250de8a6f69d4db8e63f0e36fbf0f73e9a2edd6858422ddd8451adc582fda45a41a1eabf2f96da6967635cd35cb8cd88d386ee69bc0d3c04ebfba2f2c11010001	\\x4617ffae4e7fee77c77c1f74f5070cf6b1afb726ba74a0b10c6a718d06eb6ff41886a2cfa8af9f30c35093bb183ba16bc1c170957ff86274536b117ce760b10c	1691326415000000	1691931215000000	1755003215000000	1849611215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
106	\\xea28fc23c805bbb8e3c5ababa02f460d0f93b18a1fbf3aa3c2a969baffe0ce282acc458751fc62c9cab7787fd4556bb222952b824654bb6ff79ec0f7497e2973	1	0	\\x000000010000000000800003c54d369954216be3a2bd5f0398c4da3a156c3e8622d9532516a418a5acd12afde35581e2c3a71851f8ffecf87ea6ae4fec08eb875d582c550718597f86629830467c086c341443b997feb842fd5e6301b120bebb62fd1226012fa040119dc1707b74db10913bc2512d3af9acb1e17a66c988a8a04f52a8e16babf0d30ea14fa7010001	\\x5c076b3d5d66d36a2ede8448c3e6149cd7e4ee0b83e06370d1c2f18172029bbb08083f4ddbb4bfbb7f6e11f8a12b5976ce408735514a411c16f6375e4e2edb00	1678027415000000	1678632215000000	1741704215000000	1836312215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\xeb383eeef28b4303cb52425f61227b3af06dd2677ee4e2fe90296c99f11ef7ad621a8fd45a9b41716378602c2a3d19eed9955eec9873a1be7aaad94a40c0d432	1	0	\\x000000010000000000800003cf558f26da0002d52f791ddd9fe4abc589cff3c9d1565bd542480ded631bf6fcdb6a5b7baef8207be19d9a129a4e80cfcc09b30b9376a4746dec4a2b67243eaa47d5ca4dc01d0ad726f0eaea06f62ab4898cafdc868113fccca85160dc5edd84d354b580026448f5a114ba0a0442ed5ab04d89cba60b24eb152d02cb9e8804fd010001	\\x8d4ce88fc4eda67c06ef6d8e40bb2aa61bafd2b40d24a89fcc4f889ecc2ba5826720d61cb0c5b765b980be907b48b4fa668e8df687efca8ce7e018409cc7b908	1673795915000000	1674400715000000	1737472715000000	1832080715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\xf1e4bdf13f1309fb15dfe9270dc55c848205f55f2edf708d8eabc734f207180532115ea92b4007338ef6749dcff28491a9772edd6dfc3d95d784936e20351acc	1	0	\\x000000010000000000800003b62de0941fb1ccc38936ae8e9756b8666963f675df783dc979ce99fa93aef16bc0e2f3c0d34071e69a7e924b5b493a7780526c9b237d4693072c2d3ee55671bf76c42c7963dd75922916092c65f8d78e2edc0fbf0ad6aec3f684f7a8d63d3f8f1cc98723da30773018367590c889de122cdca53842f7797953034ea9a19404bb010001	\\xa2c43dc82fe80149ca332a1d3c05d4730560d67d721e18004a93f4c32d4c3d7256936735a60e610e209d153046bbb5bc272850b3f8a163c5421f864d0b5b790b	1667750915000000	1668355715000000	1731427715000000	1826035715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xf560709b9f0211bd61847bd2aedd3e085099ddef613809f13595b3171ab0d45c5f108af98ef965596c52e0f7ca03a261b7d2efe34036797ad9e79ec267705fd6	1	0	\\x000000010000000000800003c1bfc516d9e10fd6fd5c95672a6b4a96cd9358c1fd0b32b7817fd95a0db17432e8b10d39ec6e251aec5ecbb7c70b80092add80b8f9e38b081680edf0999faf944aff8681d16d6d7d2c135e94dda69b57688c255de7a2e7f92a56fb9a4c740a6f5eaef3c0f637632834c4850519a5e5698f22630b12c4443ec62fb6bd654e02af010001	\\xbac97945384465e58f767f2bac9ed03262d5bee8eee47d37b2cc29a1261aeb9c5d311b0e849fd8df96e298997156fb4f0dc51e6a61782afa0d21773ce8653008	1680445415000000	1681050215000000	1744122215000000	1838730215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\xf8ec3b5ace2231023442573ad0970badaf8807a170d8ad62cb39d736486e329ee69670f1b3ab28a7e3b29f62bb4cf8d5e49f39cd613dbbe3f44425dd9b4797ec	1	0	\\x000000010000000000800003a8e68fd653d1fc623231851f6676b1632843014bd27a8ec0b0592eed78d1906e8506d954f49b761872210bc0fc7be771c37b186754c44f226a66d836238e56caa63066c665c9924d5167e0b6b4ed6818703230015c941796062e33bfc09b039108cb890839c0cd7d643124e5902f6ee8839affcc564d96c036afd502b679d5ef010001	\\xc8c784395285d306eceba8b4d5d42bc20c709707089fea75e2519d0d8fb33cd8da238dc5d054ca64b2d44ddcd842f0de8af7319a3722533cb4bfd4e7fa96f503	1673191415000000	1673796215000000	1736868215000000	1831476215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
111	\\xfc38e7ab670f515e3b0d3ef8e272b56d0a7a8ac1742b2a41b679c66eaa11bb800a678c009d425f7969d2abfc3fb333e7049e55b762a0cb30c9167c42f69e3502	1	0	\\x000000010000000000800003bdee32ab1ec7aad166db90a53fd7d2aa9ae073c534c6aa2480783da56f89de1058c4b6e9e22c6d3b82fc997f4da0849f09fd11b57726c10b228a934b500b8b318a5745322c55bc8b9ad403a48847b0f509f07329cb9bad5a6f21feb1ce41a3c105fa909b809f2b00e30073a4f26da1befb9ea647f7e395a0db235be1a60d68e3010001	\\xbb0def18e24fb7e855f8dea8c4dd2c36b82b0eea4bf3c5a829a899e3cfe944efe8d64eab87b63db73664c24cbec244176cf343518264aafc49b08f6ffb04bc00	1691326415000000	1691931215000000	1755003215000000	1849611215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
112	\\xfe005fad8af42ef09eb9b8c1b3c22f7672a095178113a7f972658879de5d52a72d12c9782e945ab820a626dc4e3f7b074bf82954c86ac93f7ab48b86f53c889c	1	0	\\x0000000100000000008000039684581a84458d1a7d21d920a82090cd7175abec70d076807f088b178a248fe28915c4f48f26a8de473436ee9954b672a8edcda9c1a42621f851fc7457b098a659310985f7f09d1e093d8a82f0ebc8ac70aa9b5e396c46e6da18e8f5cf3884ce4035576d9d9228f5180263b94f85f9f6149ae05c668be99b5c19395c9bdc31ed010001	\\x6fd3d40aa6a0450e3c575e3bdfdba4fde2f8da7ebb2e1f705d0f37f7d1ecdf72fa89eabf31d93fec7b356aab6ebde84ed5151841cd05e16487d4c8fc2eb6780e	1670168915000000	1670773715000000	1733845715000000	1828453715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
113	\\x00751ed636f0c48cf528e41b49d834e84d415c04a71cf6b6d5ad2e2b286142ba11682ad35ddccf90506e87f3fc63ef93c1fa8e9ecb88918cbfbf7abbeeff67a0	1	0	\\x000000010000000000800003b906818d37afc4dde5b2ef4fca9710effc1f6abbc80dd745f2116ca0c170067158d0ffa60e4a0c89f193f4916bd0f16dd1853c212a6aa9564eb12f6a2ba38927bba70ca4e44809d8e0032cca0d10752536e7b515df9251067c9756b459f7945efd39bc15b4342c8e80ccbd61f7b1e4f263a6e5d1d991c287999ab08fead46d79010001	\\x5db07036785e8228d6a10f51de722f483926553656e3d88e3a6374646103851fe9b0de605d4bc3604aa487ba0cae21a1486009e3863768f12898bc021f966b0f	1680445415000000	1681050215000000	1744122215000000	1838730215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x01ddd5abf2b1507004ae82228bac5d1bce4d7e255dfd9ad3cb7112e709c9086af870960d946915a258a037851f9f4edb2bc11863de7362a55645c29f24671587	1	0	\\x000000010000000000800003a21b61f8ff6d4c2230d32bca11d4c929749566c4d4efb4fb35335d2415479ebfe1a003e532ceb24bb411a0820db87a453352c8f0ad813e8a6e7afae7130e43e51343bae9a8c13cf454094248168449a483e9902f541f8954bcc5bf0904124f7c09a2d1716c42dc9f31d9047adfe146294e5ffd13da01709ab0aa9e374be0787d010001	\\xf39d779051b7a9feae17c2896d8a18b704f442f51f52e4699939b0c1128d1a7b0a8ab9f306033142f8841ed9f713903c2a8068fb4fba027740a1a1f66cafb50f	1672586915000000	1673191715000000	1736263715000000	1830871715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
115	\\x03a9d4f66c0d94ecbed7d580ac9479b79005e02eeda571992970f3c33d35b1c4a6f94887140f3d44832e9a78cf6c816ba32c9ed31bed42c2ef1085979d79f4c0	1	0	\\x000000010000000000800003cf9999d81255c42a152aaead1bf618de480051fa754777de7c3fe1193f0c214adeb5df9a863fa972a3fe16bd46be8d7118242df8ae344eecc9f9ca4b7a769154996e51f2b2da75c0bba8e5107ec62729a1fe03ddc577aa2b06278052c480956f2f64940cfd543e969e192299f179235c399a7da18cbf1493916571b8940921fd010001	\\x3a9e4aadf9ff964b4042e52afd3b037a9768642dac0d8867ef897836ba16422a564e7cac1e370f6df8e5e3c94f883d8ffe4d1c386f328f7756251e9e448d7602	1669564415000000	1670169215000000	1733241215000000	1827849215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x034d21ffaeb8ee5f4d1720c7636f0d04d67a964bab89f69a6e7851643a112fb04e4e0d22c1182aee97b52b2675605280e5d31a193a376f1ea398463f0aa80166	1	0	\\x000000010000000000800003ee96500b8895046f8184c87e315f7f63759f44251900593f142369427cdfcc56479cc22be3a65542318b2ef491fdc06d2bf8b9817589b98a1e9cf730248c306a56af5bef1fd83947be82118d3f0495ae33c6a885054dd9ae1dee0ed364e81e10b39a98d36c102124a46e1d6d972812ae5da92c4933d089406752c3ddbe933a5d010001	\\x0cc59ab2e153daa98f61feaa74a799bc50a71249c4d0dfce3d6fa2c9d4d5ac98bb4571999b6f5cc43b9049ddaa5add42c5acfcc40efc016d0b210f85a3508508	1663519415000000	1664124215000000	1727196215000000	1821804215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x05611563c6a68f0265ac0c953de7553eee6a19d09e0a012ce5f01f4f8f3f479448a9b3ec28a8f1f8fe0e95909517725cdf7f903c5dad7e0e6aaaaf3c5e458c50	1	0	\\x000000010000000000800003c571e970d9da91c1d21e537c98384ff39ae0bc81ba89777acb2ac870041150cfc0cef0debfe67e7dec5fe3023119fce28afea1abfb445c469e7fbe3d14dd4e585ee4bd42a00619a06bceef323c519509af1a7b3acc0e82c1645e9d7a5fb587a1cb4759f37d3d421efa8f11f0724f18e914a5aac854d609d4ce8b0736ee42516b010001	\\xe42de2ad0e0c29600deeae13d3be03badae0666baf7185155947a9f380a016a2d9be34f391ff28e54912c7d3bd06bc05637f742544427ea52d65afba400b3c0e	1691326415000000	1691931215000000	1755003215000000	1849611215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x063d59fb9f59d267096dcf31adf32535e7cfa5db9eb9c75e1fe67a061abf66c53d04375166974c9ceb84cb2201ae41b0bfc15c53bf8d3956a3495de538388e12	1	0	\\x000000010000000000800003cf2e1eb11c48db9cc3ebb8dda3be9cb837e054cf0c7af38d97880be976734edcfcf80b3a5d0a01d953cdf03354237333a99f68071e4f4bb6937b23b2f6db5fd1af7fc0c0f63577316ec66143f76baa070174e8731d41ff93383a5547e1443c35c0bd7fba492f77fc44d13fd791a506a5fc69c9c4901a4f287c691bd8a0eb81df010001	\\x430fbda9c8d66dfa8eb8e18fd5c8fa6db081638a0930403407221829e6857ee2071e3b58acab53fd7dcb0deb1f8fbffe4353654d5c6be3957ffa41a04669d106	1688303915000000	1688908715000000	1751980715000000	1846588715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
119	\\x07d5a486a5168aa75faf8998b2dfd56c919426ee045450c46eaa31fd9de79d572a9a863f4314b9390f5ceb95be7167bc80361cbfff24abd4303dc1bd8ddf030d	1	0	\\x000000010000000000800003b4af17dd98867c92fcf1e5525a658edeecc1fb0211c1b323061f8794fa9676e4a09f6be86942a167b0408a8dacf1fabb3b65f48afe4088612225aeec63ed3dcafdb7415c2e9cec435539d229ee2b579b8a7af621a8944cf6e0ba4e067375d830819161c390c650d937f17e099ebb4ffed87d195f071b422e36022016c1c1296f010001	\\x71fcb7bb1c5e76ad74b5b6a3646efe28c26133b73dc3bd5b9c8a606fabcd5fb1c082958adf39f071d3411546cb50da8abcbfdfc61ded1affa7b750f5e75c3e07	1665937415000000	1666542215000000	1729614215000000	1824222215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\x0c297a4f71b72191cd968257f02bc06d2ed4ca6efb1a36689ac7240d811ab1679cde54fb70ce97b96aa451ec432acd43133914e4e7a76ae710fc9a6f500fdd4e	1	0	\\x000000010000000000800003afb4de1b9dc939d7d38e6e02d9b5a3fbf3c754987fe33dd17adbd63649428830ce64202b04273bf1a8913913fc8385855247a5809a62b3165cb6c2039259d5881d2b2125d1ca9893d58a0999fac47a975b6f15afd68a052ab2cff6aa9d719e9ec1a66fc68a5f3c13af1da90107ade0dc19b6f7095f3acef8d0a985bfc6c5f9ff010001	\\xae76a42d35ca4c95445c43cf87a93bd4e1d4a80814bc95e29c0b4a4de68ff921b5763a2506088029b06cee6a0ee7d84bea81b8f7626e30519e4b0505285de005	1668355415000000	1668960215000000	1732032215000000	1826640215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x0de551a506b40cdcdf91f2c96d060985a70126e4d122b832e1acc79371c55265a9fc33129d041ef3c30569bc3bb6b1580863eb96140851f9a9c6b8c495519950	1	0	\\x000000010000000000800003a0bff72d9b8c094b5515acb5bf107cd5ece2373f4d1dc75fb6ba51cd65d379a9b27b19b1748eea4731b8e0db9f40415f97f06b8b2e7bb431a7fa4fc7773686eb3343597bbbba59fc67c39f477c4edd3c2095f1d449a2d3d7fddbd1e0fe72feae6a6966f18abd90d0930f40e6b66e58db5975f2eba1351081f70fd7e33e089ef1010001	\\xb34c30fb9ce4c619c227836c13db293ba8c1a1b98208b7a4bff63f8aa290cc09ab0664df02342ea29056c8dd28202e1bd80bbf55593cda32d960cd2c872c4109	1682863415000000	1683468215000000	1746540215000000	1841148215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x11d91a45bc888e958feb26370c33a072fc95b8b1a908fa4d181214bd3f9e073c9d42fb68853dbe11f7b58fd85ca500b5ee0f61b798422d4c3fa845fe928d322d	1	0	\\x000000010000000000800003abf478067150ce724e415019f32944d4c9b0c61d000f00885fe8df32fb269ff91852251835f04d39c0cfd59ad7af7118b8ebbd9bea30b6a180e930f1fd4277ba7750a3bcd887d8b808060bbdff8aa031d801103b77b55e4b46653bd3b70f3e42ea1507dc9a2d489f49945bcd6494258fd04d54bfb3f6e05a9cdab1075bb74199010001	\\xa53bb0f3463d27a841554c4658422f8cfa89140b8a30e93fbf963dea97216bc035bfea112bc399c2edd5be8c63c33232503af7ea003c477420e1e8b0cc616705	1665937415000000	1666542215000000	1729614215000000	1824222215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
123	\\x112908243d8f14ef3fd1967dce855a6b3a68a7f7dcc7777cb44f168ab470324c7fd62f9387b6edfa262472fec3be038c3aad78d7f9e24b7b39198824c70e73f3	1	0	\\x000000010000000000800003dd806dab7381dd749aa33a826a3da0aae347ac22e56b567fe471fbc0554ba92d02f989a68aab92cb2e65e4e12fb1994f711e7dd4b90f537171e8dfe5a83f6af097ca75dc66709c363f74df19c8262f009401bddda44f76756a6d8c76faddaf28cef029a6d9c5ba13266acda5c77a5923972ce1b5569e526845d9e8d626d252cf010001	\\x1fa5597f9577fa0d210c92b89b863aee3433c4651e5a6300099ea0f236fad1ebeab909595f06349ff4afaff69a8bd60e0bcbfa805c90bc4ead25174cc7f44c0b	1684072415000000	1684677215000000	1747749215000000	1842357215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x12e5c524960f4bcd0561cbfc05a4d6ee7502f2e857e920e41d50810a5a4fb07dc8f932e1f7e5db0c5aaf79392c178c0819d49f662f1b4d5e17de0bdfa460e94c	1	0	\\x0000000100000000008000039a29a5a54a56dbde6151b442d1748b5292fd3a0ca61b20ab50dbde6390207e91f3375cfaa84b9de2fd753713d54d1f311d8e321e5283d96a9fd7739c2754687c5624d03971ff99e2674d6c81aec8902b5ce01c2ab077b49c6551ac9f786f213c42d8643293011a8c9f3c254b8fc5352a6ac08fd1fc4b5054d9ff0c6ec66ce39d010001	\\x626dbc493813f70f4d83ade2db825a34a1029fcccc83e90dd0c78cd1a7ba9e61215121115b5eec3792b5c48198a258c05b9d970884c1508bf3fc37619c92440c	1662310415000000	1662915215000000	1725987215000000	1820595215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
125	\\x1d4511de2a77b0a3b0e12e730967b7e32b2640cb4915270590f3ed6699e8d782b7837515f787fc502fe570cae04c1333e98ccdcce040f70a50d1eb44615ed523	1	0	\\x0000000100000000008000039b8f3bc1e80c94d302978847095aa9f85998afb4e3fbefc417aff87c2dd831df88b03d4f672e617de80fa74b19dd9dcb0bb1cd2719c27824cd4d5e3bb0e13b45e9aa62c27d5f8f793231a8909bf4d7e5cfd5a72c1beca031728853e55a1e7c2ea01784dd611c2f8692d60b82eba3d6d90720d65df4ce8d1375c0b973256724c9010001	\\x2275162d136bac48077baf03bb870f2ff1c880395401dbb9fe8e2a98557e96ae0d166a518a0bbd253ffc68d9e19fbf0a3220774fda8b040592f3a8e0d863ec03	1688303915000000	1688908715000000	1751980715000000	1846588715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x1e655b62fb7efee58ca52e255a04fe218a7687d5e21ee38c00eb9cec61760eff6990335d00d5e2f8075fc16ff26bf92d570f46f12d24caa05b1c469d79b61012	1	0	\\x000000010000000000800003c18ff9d88f1b6901e53e4f88a9a3c150a6ae0d019947b1a96390c6f17692f863c69119ddad7d00dfc906ec535022f99b9b059eb3b35a7aa98ee977d92d7411c63e89bdab2d45e399d210cfa14e84a86cfc0fb16f3e96db5024994a9fa67a27c4b50d4825f15305c7aa7f4b041ca713eca4df0c9caff43e8c7558dcf82ede0d5f010001	\\x635e32748c4207ba071a3eecd722cc1ad28a1155c2dc774a7ec3b6829bd3a98112d8c541594ebef8f727bc5a78bb574145b2d1e38f4294aba46d75f7748ad70f	1662914915000000	1663519715000000	1726591715000000	1821199715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x2061e7363245b0f11393b44d0554794a1ffee60399f26546df4dde1d9cfe1c13d8f7dca46b63ad8fd03978015ef111a4f4b50cc13774463b5b393f7201698b58	1	0	\\x000000010000000000800003d4508173a33ac2d473a72352949c0936fb367441eff2868a07902c1475a01c029c716c83cfac45f4ee846ee1a18b610b8c15a3be2b7ecf681d4c2c8ecc212d91400a0889a75182c6681d942594c075df95b357a84f71627fbdbeefaac154009b3190019c33139d587a989055e3b2f03275e91df60e2962dc499ad1dbeee896df010001	\\x19fbdee9de1d4975c02d54b2823de9937aa5d3af46894b2dabb22512df4a8e57b66ef94d6b86a95fb24b083fcb66e529c5a7caeef313721d23389aeea6115902	1687094915000000	1687699715000000	1750771715000000	1845379715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x2201d6f294e8f933df342967930859c37ef9dd3be86130d7551fb53d72177a51e6f66cf25c0dc469ca685ebd642668c37fa6af700e9d5646b2624c5c5c92cc68	1	0	\\x000000010000000000800003e2a3ae0c7d1a80380f6e6151c004955ba32dddde0e2e2bfdc3a7e7af5548165cb5f222804bfc23da2a7f911cc2c854493fe984d01a6e2947a8298046d8f4c3a856d4029dbd5ff44f0642518fbfe46a5dc4e4bd899452631ef20f96459fa74bdf02d01ce9482ceb7c8c08092f986808fb09680ad9df55bb2fa0cb9bf74b47afa1010001	\\xc7c004194934bffe094bf3d5655c7e70c5034afc671225a1a9faa4f52cc12e9c8f00ae40f3c29d2b83bf16167b63dcd09c90baa246404a7b8d9f611824234108	1688303915000000	1688908715000000	1751980715000000	1846588715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x23dd67f2dd17a96e26caba7b46111497756e642c0d920d5b7219d1a59dcc55c7c7623d46d07538e2894f3e5d10de6a35a6c6b839b3346f965b49231dbd785c78	1	0	\\x000000010000000000800003be1574ba3721008b9583f84df6b3bf849827cc27495e531c00e572bf0891fbab8b036841332be6ac3cc4c455217eb5e822e093909b6ed5988d9d1577f0cbe35b01caa4a21251ed50859d8d19dd9b32424cc2400f2767050029d8d7bbf94c342867fcc99675d3421136adef3990fe810a6fceb1d5217a61e0b028739fdff3e05d010001	\\xbfd62fbce991688cf093fea2d4ab19eece12131615fdea93c58032222db5ade0d8f77f15587d0e0fd39b0cd93b39c0a42e42efd8d2f005d12d94aede74e08106	1685281415000000	1685886215000000	1748958215000000	1843566215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x23d9dd478647cd004f457529f7329fe5758b09e1d973ae08fabf016f5b2525d7a80a6f9e0f2e07bdc522d4b58834c8c49b970c858e39399b2bcface9959b6c94	1	0	\\x000000010000000000800003cb3ae892990bba4aa2ef10152d8bcbf2b95d1dd73f25f94a131a4d1410c8ad3a2069bb9dba89ebc67f4eaba6a86f780121ae20f071b4479e87c275667834dc44f7b0d61dadb5ecd087496a5e2046ced59a998cafc0b9e35d682870ac8c55ff91b868afe6953208568699c74c15d957db6476066ce642ecb9e0588cb95d21b5a9010001	\\x10dcbc35651a322fceaa12c8d8db48c78929c100775ac2f51f71d340d08d5f0ba2db384923664609ebdc93bbd10571b9d5e18a87a5fdff085e171b0f3f67b303	1686490415000000	1687095215000000	1750167215000000	1844775215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x26ed926093ba6d14a1e7c27d22b0d8784a5f51a799d0e319baa5badec17bcf6d7fc17a62c23318869cabee374d39f2f9cb28033237704a4b5e20cb5ff6ff1fac	1	0	\\x000000010000000000800003ba6f104ff1dacfe4de12d061e052938436802dab8e3522c30d90d05c5cf865428edcd2cfab6869ea8dab32bf912fa91a9f71ed9e9d6a89af9d256f8820d61f7242a673d47640c4fd889b6d6b98f666e56cce88040073b2461e85f18fc5bb90c847f4448ae7d3aa8262da8c2cf8a46da321093ff439e85a6cd2f0aee2f9bb52ad010001	\\x3c02703f2749c34e7bb09db93dbd290630078e573b1a5a28213b81ebfaf7c89f5fba403db79c8a0e8dc1703e64a990af18529d2cd55576815751c7037730b50e	1688908415000000	1689513215000000	1752585215000000	1847193215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
132	\\x29699d9948492a54eadd64c66a4af4d8fa9adf52a555a6da5ab37c86228050cb2f5341fb8361b6f7fa6012c105b669bcda4b7932f6ead7b7affd35df1572121f	1	0	\\x000000010000000000800003d1fcdc655227041880a5bdbcdefa382d179ffd92fd804a3136927803e6ed2551a41722bb702aa6248a1efde51194787dcc72957a9c3cfe9531d7fef3da0e73087ae761a6df5dc49aafbffe0737fe58aabe49d33140b7eae73d27a4055138bf7782e1bb5715f746794fd1322d455b8de1593f947ea5eaf719f91e3cce25fdb7e9010001	\\xb7052c25ed2069da05ee497b94220d0d23002b496a8c72fc634f594ee54907cdb7b0a1bf9ab6b75841bb26e1f381e2818ebb613377f533295652ced17320f104	1667146415000000	1667751215000000	1730823215000000	1825431215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
133	\\x29ed5f2ea73383f9dd83ca26ee3710cb8044e858154fe51a518d36af5d6ac13b8dc42fea8514950b49b28bc2caaa9047d11ba43b22b6c7040451c653a3e04324	1	0	\\x000000010000000000800003b2b47f73d0b2778fac2fb800e8760d66dbbd4ece45333b7c640be15b11324703659b02107c237c00c5de72395b0f81c61182fd56f7a86bc3b5e50475e1b19e5200a650d3e57ab67959b7046f78d80eaf45a450d3e313c03cf88b5b9cc0f3416e0d21a0436f6ae1898d6dac656cfe7780ca6deb1d52259fd71579262e20cd96db010001	\\x12568ba7afe269d580ec9ed93a80fbfcd0d7ea495f89cd99c18a3cb78b23ccc9c77f2bc74114134769ad3a9ea69748617324da6557a0efdabfde0663e2f1b50d	1680445415000000	1681050215000000	1744122215000000	1838730215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x2bd51446bae9839167fb1c87d538314b202f7176e932264e562c8e2ebd5dfca2896bfdc4e967dc0f6070c94db8538c8ea71779e8f23c65e866c1fa8c1a07fb75	1	0	\\x000000010000000000800003db3eb86142b61b70291878a874a34583022607bdcf0b871ec1fe0fb8e3689ae5859f65aa983c09a9c8d10c1ba45aa4b2baa67f9d746f3f527e9772ebed5fe7a3fafcc971e8074ad9b186bb14b96b706849efb7695a1ed63de80fa04434f2553687af2ba6c8cf4e2488a9665b58ea56815d2222fe13f85e70d69b991c31996a5b010001	\\x3f1b449e0ef34b4763e8e08ff793a043bd0c40154e2bf97a022fe03e5e9ae0c59b7dee2769a53caf45e190e0f1fd4511cc2d1496b976007271f0df4392fcb90f	1678631915000000	1679236715000000	1742308715000000	1836916715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x2ba57e3f2e4886f92b218adfb78ceb8f96eca988d6709ce1a665d30559dd74137187270246c7a5ab02c8c2f7f271d2c44d082bae2c10a9e1318a35f212e6ea19	1	0	\\x000000010000000000800003df979997020c2b7d0f40329e2df1c14308ddd3fe6b3672932cf2532c9f591ee08ae327c67317949205c19d59de2346e5104ab143b777ed2fdfdcb28e8859b1b17028987ade9bdae99093c6eb139c1c03bd1ca64baea750fe1c23f5bb16f1c75182658a0b66fa0a28ceeb4c0c662387e556ee9c44fb5621a84f9a2b57b07defbb010001	\\x12217f8e83c6a1181d4c191b5c6ad0378ca82de9027c0d7dc430f79fa4432a15d435529c35e986b3e04f7a9dec9e5d009c69dd2162d88a2df54082a0c7fd1a0a	1681654415000000	1682259215000000	1745331215000000	1839939215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x2e9522f96dafa635eec91cf36fdd9a3195757d16dad59ebc4b564c8d7e42341bc40339264d906341e3de65d71acca278fbc45d8c6d3e00df33b0ccd6f2931c7c	1	0	\\x0000000100000000008000039f104559e515addeaeec88b60ab2608c5895fafec0606d14a22766774f2727a790e09791bf71e4eba3ef645c6e814a9212f8219798b045d757c2e79453fba7613dfa44408b4dd541e8638a43643dd02cef7e8beba764120cdf746495189dea6e627cc05b5776d801922ce0b84903d6d067474b214dcd1bfe47349da5bf93c901010001	\\x609618870c5cb53e2b870979a80a0cb92622909858dbd006a37c51be6e4ae92148e67bdff751dd7c45e06df5936a82db4262fa2695b78bdf64dda99035e5160f	1665937415000000	1666542215000000	1729614215000000	1824222215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x37ddd35d1c296d4ef415740b2af63238013db5cd65f6e93eed20e78071b67f72b93fd2b5d28e5694a7d1c893b477c06ad70db47dc527420151e57efac10edf87	1	0	\\x000000010000000000800003b1997d95a9970c993f80e7e6ff1bb2ce2c987e5c5018f8f620351ec5172974122bbf7c9b0a96c3065d3efe3752935297479b78f05ad337341ac2f8eec53cc31b27846f48b7c0927d41b1b08e56760ab829fedac342bf148fe2a4d6da6a836683dcca85a31fbb1779c83d7c9dd0c3709e22cf3077624ac5d304ce909e9006ed91010001	\\xdddd2f47b2a0ea0c37b9887d5cb90836906a99b3a0956aaae31b1d7fe6be9875173e22085b8362e063a28e252a5bd3abaed4f591e3ebfbc49e1ce4ef17a8440b	1689512915000000	1690117715000000	1753189715000000	1847797715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x38499aedf6263d95f0993103be1378e0b2d41c69a36ad44115f6dcc483240f6a550c3a44f9dfc15cce13fde8699836deb4dfb805c425538e4ece93c9a8fba16d	1	0	\\x000000010000000000800003b453dff5b09a8af8b4269a4a01d07e1189719e81a6feb489db0c9d230498f21707168fb98bcd7bb89cf6d358870583112d0cf0389567b0fed000e2bd18dc4862b2615b1ef6e09c5823ce021f37c761f69b76c4b2cec10e9abcd13831cc64e8b3df0876edab6e86b7ab681dd9c5f2a0af3b376799efe173bd26aa083d8cd5b15f010001	\\xa1552e8ca4d67ba39cf725a83c13026c019302b71d1f6eae8914662b0a06ad2dc4a271e617a7ee9ca3227b4e2f16bab96856f7a256f0fcdd204432261d1f1907	1675004915000000	1675609715000000	1738681715000000	1833289715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
139	\\x3c49c119b4eba559ce7c2a921da7e9b8ba676a286dd9a2043d5ca03d1ae3a33c41cb25ca1afad33a5a725064577ffd2723490ed1e73f517fa96b72816e3259ca	1	0	\\x000000010000000000800003bf9f383da4602ba9fbd70b7b1c6e2576afd4e898588ad302ee69f82c57e8bfadbacf70eee67e2d6bfe1cda742f81dfb1c159ab3940abbae742bc11a7c18385a29d4711056322ddb32bd06474cf3415e9f942f0e8200c33d699420f0c8d79e2211a3aafb7397ab466c7023e815f784471ee64c86dbf4f7fe4c44364829109e173010001	\\x9a364eac561fdb8a1654d237d2c00d54db2d0aa84108dd6909e57dc9682258359f927e2122804e2b7d8694198df93a12ed61b927996ce2de38945120bd8bfb09	1691930915000000	1692535715000000	1755607715000000	1850215715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x3e7117b2786e867d68084fb7885432d3ae585f468a49cae64e75d4425f38ae65d47a0080241409a87a47071f1c93b0570b6475cf508ded9c737e8ce4d4c57521	1	0	\\x000000010000000000800003c1878d6ab266c351e0c82ffec3a040846d87732097b3e34279eab622440d9e49585f10e9df2b0c489a678aa5e9cd54259a80130594239da3c860493a6b708b3314869090456bcd43a48648cfdcf58cb666155d5618674b999dee23eb488c4c3c53eb3f39a85bcc3ed361a65e85c60e027acdf8371ce99245f20c80308a8f2ee9010001	\\x17cdce79e16ff3b82921c115be243c6380316df3c5e478b8fca0b654c8d7ba565e071ff264746a6f57103dd11dcd6426fcf3fdcd71384fe2c72d76169622850e	1684676915000000	1685281715000000	1748353715000000	1842961715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x47ad08bd539f1e8e887974d5659e9a2322c440a80019bd34a914245c0a844b1c1ea1178f5670bf9af1192af9e7d069557ed2f95e2063560b2a45897d9788203d	1	0	\\x000000010000000000800003e2a4c0d85c04e35680101a9681ff89f5d58a8892352c66ebeae47753d7af93af0df436b1dda20f4a6fe4a2983b408280f8b7841475f1ab89cf989eaed5576065eb98670e4c062010456cd1d3ec298403a4b65f82960df85b2954452bcc539895840ccf10b2da211fdc8d555355958cf384a5ca020e6f150e35ba47858b90d493010001	\\xe975643b37e125c90699d3d052414171a77ab54e9ddf217ebfb5830282ce5d7dded274103dacb796bca39098e1d35df086a6dbfea0b0ef1b7675a9db16ea020c	1681049915000000	1681654715000000	1744726715000000	1839334715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x495d593d54b42c84abc27218c87f5ac8f6215a4c383b768f3438b3ddac03d33698e839159ead8d14b2cb9cd72a142c47f8507f55f732e2202535cae64ee57403	1	0	\\x000000010000000000800003e5bdf9c84375b11d1d51393a9d22c92e8347b64703b4c8e401884d294564f6cb46c32386b922146fb115434a593c8998b2321f15d8bb65fa7fc573e560f84bf8a62ed0b404921a1add535dd6c8f5fc4352de79d59054b60b20221e9c3f649d5bc9d3a10680144c099c828188936180f1c3b708a68eb4e6bebebc41faa951e76d010001	\\xde07a0b9610ad28b611409b642f6e0a65e1d3dd7c9648d9e8a22b4469fcff61c166f96dbee5cee69837eb293ae97406b092043696891ec39fbeebc7994b1df02	1684676915000000	1685281715000000	1748353715000000	1842961715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x4d51a9f4fe68992d52c69dfc935d163cb71acb2b08e770376193674efc9eacb54b47d4c114edfff36e3d0c02f6b36814b475c44d58d54d6c0f67997c93b55125	1	0	\\x000000010000000000800003cb6787cc99db90f63cd892da30d216db86bd5779bb3bf94aa3cf997afedfae903ef1bbeb5222512c9ae93c2f2e28701e88d391dc71b76be640fda948ef46232fc3024c8fc1228caa550394ef15fe51bdc79ce589e0ea1b5d3e2ca539131afb3202a12cd584c9662f264156c5494ef0bfe963cd40741adc376377cb047807563d010001	\\x99090b05a2f2970617ddb5ca47d93b29ed31c5991de5b48745725775e03f5468dc5ca0a5105cf368a483264ecb61246852e799b4e2940391a258f21ad82b1707	1681049915000000	1681654715000000	1744726715000000	1839334715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x4f6d934896b3cafe7cdfe0a3fb77e7820be2e4680dffe381538d96c98ef8c519667fd85455db3b5c4b85a48b93ef4955601edbb16dd7d83e279a66a4b318a46b	1	0	\\x000000010000000000800003e07e6e04d6d68e10d0c2befb3eb21b042907581ce41b4b29c839e63fff4d288ab6d0ac1d412f187859c28ba13614182892f38a7c45144e16ff6c45d7b9f70c2e16340cd4df9d88fa9211e89c58c91d44b864213d622fc3cd4ed1e66df77931fe8520a0333e6fd2a32af62ed2c04759eac9372038c94ae185eafc696ecfe42bcd010001	\\x46efdabfbaf3635b2323f2181185a04b12aeaba067edf2669df9369a360c85aff5bf5160c55ea07a24b6eae35f33012679f40f356d39b8e59dd6abf82b50d10b	1667750915000000	1668355715000000	1731427715000000	1826035715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x5199a18cffe03b18a97430d36cc3f21692f3d06de484b20fedcd9cc3345f12a7caded56715a4e4d5a77cea08f278d2863721e0d025e27ab5f737381fa6972258	1	0	\\x000000010000000000800003acdb48c9a61ba0a0fa3d55fe833188cf0cafc1cd395a75d51b864746f58dbe586cb1da5a9218c1c3b191feb213f80983dd83a4e89f80c96373dea598d86cc3acd0b2848f6a8a1a8bcacea56b893d527685782af95dda25fab114026c6c302c6629ea086f0f573ae45bf23b892fd684e97e7de2d515dcae584a36ccd01ce9a42b010001	\\x15e32e70803049b60bcc1dab3434078f007da93e51613b7e26a9463629636f3ed886aca2df1317e896ebfb530420b1c3c639fad9429586da6ed389cbcf1b5d0e	1671982415000000	1672587215000000	1735659215000000	1830267215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x53b52af8062e7b9c9eda76f31b8588f176f183a8a6312031e8957f2117a9052618cced3d0f15659c7fffc5f22f7a226018fad16fc326c9261401dd736661d814	1	0	\\x000000010000000000800003ce963214f3ff6eeb30ac104dc216b798fe4610e0d0e55f51d4c73eabc7f231eb664b966a814e2662c5be8eb4247e6cd4de7600e6dc9fb1633171a204968b81f718fc8a3143cd8cb356f603e56f9d9a0cdb55db8b21902a8692cf6e82da65f6be09a019587c9ea67ca528047a87e2dc63a01ef4ff11f1be3cc5e6525b1fa58f01010001	\\x680701eb1cadc96fbe3763556176dfa73347cb7d9295348d33888b2212860e651f91d4436b3a05ff4d64a495a2ab307019ba10b10b2d862057ae88de9c04d305	1675609415000000	1676214215000000	1739286215000000	1833894215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x53217e3743dde18249cbc7a4fdfe0f17729dcaea31e675d712c207df69dfd81d4fd3f77b2c9b2fc8b68d2acee193748012f36278e1f8fd152333970f71b7b813	1	0	\\x000000010000000000800003e209da055935e2bce4ae9343d5f5737ba1d5e43de90c878356eca52a83bfb1d77590d4e1a7199d98c36943edc16d2bfc0f44edb43a28d38adbd84781a82b944d68aa83edf6b347dc91117d80d6c30b8d0b4d4e85967548b7696e2521431cde77e2b99ff4c334b8a4815c7b2a961026faeb87a17424757861fd072ddd09b49075010001	\\x7e872b7bce029280ecb7b768e6f863ed36fbfbf34766a549cc4c8d962956cb16a267761199bfb0ad0eb931590af55f51b936a13fbb89a733276241d8c42ef202	1678027415000000	1678632215000000	1741704215000000	1836312215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
148	\\x5455b2a3f0300bff7e1ec9c98d77cb01aa87035a442027eebf675d867a56870412f591896639046ebdf07fb97ffa98f2b4ee87d5316a040bfad007eb6d3ff552	1	0	\\x000000010000000000800003e8c651fea5a2a25cb677abe8677ec95dc22ee51921c97fcc5e42d4c6a3fc48b2d5117a42dd333a6e3208bcf51658777de005218384c29d0ff869d715a24b4d1bb5025ab3dc4ad9d7a72dbae0a42a0e52b14447ce4f3f91c5a1178d51c0655e797547e468716160f8504b627b0e8e40fb9114941372d2263a2289118d06cb4b7d010001	\\x5fd5668744ab752232ef8d9497659ed24392e8e8029f7def4e0dddf25a4acb631338d33623e0f999b6a9a83bb7398e92d763b02c7687b968228dff9dd0518505	1689512915000000	1690117715000000	1753189715000000	1847797715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x58c1a22577f6afe88d0d2447daf8476fb9b5f2b41b18bee14f8c8579befa849193f0ef59594319f266e64f34a3df3fb9ee57c749eefac8dcd488141106e70aec	1	0	\\x000000010000000000800003debfe2f377c2cf58c2bc6085770dd2533fc40e734b2bf26504e30757fc60836df785fcc1552edfcba4f34ef6ea8b54ed4411df2b899438c11509523331cd6f017da17f51c30aafb0e28e0ac78c6b09e7e12a1d099d64729d758e865e985fc16105f1a5709c59e1777f9ecf2f185a769e47f364b1b1f43b65acc51276a7a53cef010001	\\x3a7e72f284308dc8baec35e83e783aa36229a8f84067bca1d966837dd2e7da534f16b6b2a63152dbd934b2fc1f07b47af26c39c443ea3e7bd851df57067eb401	1681049915000000	1681654715000000	1744726715000000	1839334715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x59115e8fca4084b2252ec8c769abfffd8adbc4bcdc7dcd8db851747c4419f1085cf34516ea58809e6ef51b6999dd1abce499305e2dd3f9fc3a7eeeb7fc423cda	1	0	\\x000000010000000000800003d25031700ca6c392bc0619b6ab16899fd731e21fa2e1bdcd85e104a4be692ee1336ddfa034ce1013a93913a2a7cc71cc619db8a1f690341c64637e8d060d582e456ff87f749a39fe0bba50ace4064639501fc1ebe8dcbd9e4f2838c50fc5c56b51bdcabbef27a1ec919f757d35476cb92b0d44c7cac7bf627ce47f66195983e1010001	\\xfd646107c015316b441af18582918965f36ff698445101d36d1674d286b13215e218146e3469a8b29d81e76b3831107aaac8c0df2ba4a7486993c84ecf2bba02	1674400415000000	1675005215000000	1738077215000000	1832685215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x594521dce0b9739cc28e851eb1dfe2639d7e87548488445cc5c91ec5cad7da42381ed8c629b41d7186ac82c1b24e3b2af074fe4bc47a233ce689120d149bd719	1	0	\\x0000000100000000008000039e3360f683afb829218ae3650a12c80258806b6362a379c2d2d1e8eee30fa1303dadb4b0f317f9fc65671fa440aa6a14235485dd4df8a7696d283ed2953843b6d50f1df7d43491e310f0163159288d9b453509127c86284b2940d5bdc457c49e44a9a9db538f71688759dd62fc631081e333c959821a6e1eae735ef43ffb0d37010001	\\xc963e98482c503562c10066e86daa3e8502497c196e97e1b56f24c79d340ddd66e358c0ba339b2d669229b752f2d328b5fd6ea6f28c26a4d0a0aefd7df969605	1690721915000000	1691326715000000	1754398715000000	1849006715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x5b594f2bdec62f91c58d493313631003de3d4281ec5f0892d62d087a81918773216e68aa019df62fec3414342b6cbad9e6ea9cd5584501e6a7706af59b71a224	1	0	\\x000000010000000000800003ce97610f58a3ea066b20717df6b36b1df2626d07c4f575fd27bf6db9d026ebd6b8f358b3f91e354abdc981f49bb1c4023c96d9a240c1de9822edc3ad1e74d08d31582723a28b793de3079f40ebceeaf499b61d930d1df693f9f991d76af4d265bcf9b1b174d048fcf8a53d2a6bb411cc73c8f7af47cd5378528adf38879930fd010001	\\x48001e0d070d548009104480fd2afb8ac91c0a51be5502bc13d7e17db69fd5b4209eb1b659a84a64b254150d4cc45f27b48b66a4adf175ef7051519a1b377301	1688908415000000	1689513215000000	1752585215000000	1847193215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
153	\\x5c6985d6fd7e6a2ada52ed79e3c5f848abaacff3c0d937a2056264a4e54b7feaf47c8ecad5311723ac666be774566f1466bc44772ed36c1cb600275818a35836	1	0	\\x000000010000000000800003a2e81b6e72b333d40a99ff4e04a49773caa8a9c1548e23b89533baaa197b8cea6b8af948f326df03b29f845c6ac60c3dd37e3569e181ff1ceb3942d205c34f85fc04139d016fb06f863a62492740d50a95b6329ebb741b939603650d8d4eaaf6e3ffa9733baaadc091dee5a5c14698fa7a1276997df06cec5e47a8e12cdf995b010001	\\xf13cdd3b3943e6865b83c5045de3df5ff007f5b3e6bd19444a42cc442fd0c81489b60b0b89e1f3098df2c48c937745491beb41a7664198e47e6d09536d70840c	1691326415000000	1691931215000000	1755003215000000	1849611215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
154	\\x5e45ec2a6cd413aeb3108ac7c8cd7482fc1a1af5469341f38eb53a54218302c717782ef08d092039342f78f07fd5748988e0ccece249224d69e4595e62a479dc	1	0	\\x000000010000000000800003bb72ed88ce024d2b09036536e552cf2746bbe794bf2adba3ffcfea58d98d825465094df3029c7efba772ab266d026ad9f24e8011dde364b1182cd45455aa49d361eec335c1b3e2ddad98aad60f2a23c6fdae8f219051abe4f060e7576e8cd68a3ce96d96d9adebf025e4ddb8a93d82ab70420b8e8721f4fceabbdc4b005c4d01010001	\\xf614068137a4394dc018fec85457f10f925531e3a3fc64a0a3f1333028fd81c19d96585877c162469d43269194c4722e31e2cadc0aa3f13a97a596c6ce0ba708	1673191415000000	1673796215000000	1736868215000000	1831476215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x5f553f4f4333c9cb20f909527939a91c872bf6e8a334a4ca1de00f8101a91130908d85cacad995983c955f864da0114269e9a21b5193d7f29ad1660a67c959cb	1	0	\\x000000010000000000800003be4ed6b24444351d6c16b1f3b9a2a0b814b9b4055fbb034db4c2d3fdb7436d2b75872c41edaa2e739200ccd61647c6513b684a5563744caada2f9c0c754be8834d6a13d4f38ac243fd446e17327f5774039e6366f413fffa09e4b9a67d0e372d75f8bb70e59afe06c9f6b0c91867f3353fc27359c1c6556f863ccbe773e31bd1010001	\\x4d981fcccaf5c7633d667f4b6b770d9e6eac89ead342df3a986de7e504574c4bc09accc4c04f173d0499e0fba690ae7551dfdf352bf099dd30b0b1d6acd3030b	1664728415000000	1665333215000000	1728405215000000	1823013215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
156	\\x63855f08ab6d320ccc0b0d095d8649b914acd06ee8822408fbc57c1b858658f062705e7680f9f3fd3373f1665291b92ff3c46210fca36d8710ebae8dd0af80cf	1	0	\\x000000010000000000800003dceaf6a5cf595c50dda0e8b2b1e77b389b4e35e02253592e352ee59a255008e98f894cd147da82f941af8a673fe66797ec4024cd651bb2f34559ea8b78114ed998f42d172c92a7c11c931c1957d6a644f289509567e73d2980d68b55cbfcb7df8d0a363f5883c42440c3d89cbc3a4e1ad0aa886d0204c85eac41c1a65dfbf429010001	\\x052d5c6f82479176a9f0832b1fefd741769d2a0b42d5c08dcf1ccfdc523f5c6c8b5304927c02fe3424b2b484d5679092dd59f6417ee0d7dac04a97602115ed0d	1660496915000000	1661101715000000	1724173715000000	1818781715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x6465fbd794a490bba5dd5996c61716f09145d339ff9b80f5170b311a46d086456160201e799451968e797a4066ef9f35c9cc1d6ce48da9037ba9cafbb4f5dac1	1	0	\\x000000010000000000800003f60d70bcc5df6e034fe27ea847ef6a1cdf65cedec2705f4b43441347c02e5738786888f23f40182b5e2deb8b70888df623bb1c97482b03a50005b0d871f3e17b14bbf4fa4c06b0ded930560a80510726daf31dc437be7fb180b0ca6b15caff4a344403fc2cbc900c468d09410d53d8bf97421b2bf6f1ce87c21837b0d2bd817f010001	\\x86985e80aa3ce6c793c80a2aeacbf43aeb6630f86439530f67a03a993fb0a1e1053630dfe6d8606d99920dd788e8654b527131f67e83ed69fca98695b3eca801	1669564415000000	1670169215000000	1733241215000000	1827849215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x66a96e9a848cdcdb2368c6d92e66cae7fd25cdca0f29b7e83b1ba147229b682ca2b2763e4ca3434d884e8b41afb9c833f0f82ebc07f6660602d241d441dfe99b	1	0	\\x000000010000000000800003efdbbbd214bceedbebd0fef8b1138d4adadbdfba8105f727429df6c928fb41792501af029786808c2b46cb21b3ef9c0b98d88c55ff161b3b3138dc7abdcbfa83fc56ef7ddb5165b0c2f378a8c2a1e941c20dec0453f9114203a0989aa8fc03c3628683eaf68ce1afa5753bc1dfdd3f4ff7acbb8f9433118cf02cc11ecbefedf7010001	\\x16eda831be338f08765dc0089b186ac2f1f0196fe62aab003c90f6e21c460853574254f38320a7069629f4501198505475635b74bc8f2d04c1c61d280e4b5c0d	1669564415000000	1670169215000000	1733241215000000	1827849215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x6ab108bd02fc1a50fe15e3e078df1426da81e6fcc8211b7a9f839e92685831cc45e1011a6ef9ca400d200cb71ecd2efb760464aa3a0051f34f9350103d86dd2f	1	0	\\x000000010000000000800003ba4c98be2fac509c3c6d0c34f3381d4650af50ca9f969035fbdf1ac83cc94955bfbb3dde177748b69d60cc9def7b2e0e753b914ffc6c938afb431c6ad91ba49f5ee12343c91936e6510870f57374ccb31d4e5d24146684ef6976d967bd30aba92ffea57d69641ca969842e51d137fed09f9f9f6abfaf7d1b53c18b95cba51683010001	\\x0d1382ffd2f14bd5e2629ae323588b38fb11998a8bb5319cd6f17f029dfa5f9b6b2e0da1065efb671f90cf1d903acf28fd43c97f766c31da16262d89f005310d	1686490415000000	1687095215000000	1750167215000000	1844775215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x6e65917576a86a21358182c9d4b6b3f58037656855fcaff22ff139bc272f990d4d1c550b28d13174d612bf0d41652a91f5a386fdcf6ed225a4fa13887b48eca3	1	0	\\x000000010000000000800003d7b608290042174ac4a47e0fa03fd3656eba3a688042258f762ac5ef647ec12a98b908ff5b618b378ea1b7497bc3d9d3034db3852384ca60f746b22505efd660424d4c517fe8c3aa3c3ce531a4d21e176cf5657ef09d660490ec4eb4b7a7945713329e0c80243ee8706afba4525085938f6d85aabddff269825a88aca1dcbeeb010001	\\xb891504cdbdaa2e9aee75b29ad6210b4ac051f82788d654f9c58892fe7cf2103ee533a20a7f0f6d969a4d7e6ab704608ad2ad4f576c3411d2db9bc1ff02f8509	1688303915000000	1688908715000000	1751980715000000	1846588715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x6fc9456764cdf34cd678dc196eed6dd8aa8478f3f7be562e58b4ef5856bcafece972b2dcacb5e1dbbc396d80176429147684ad4fe70adf3679622226fbfe2a3b	1	0	\\x000000010000000000800003acfcbb0cdadccb9b1d93eec747a10181e3de8b501c55b23f2f90b32eb596e5339551b297be9510349cb9e3719d873cd60ea4b27b87f5800be6dbb06bce9890e016c3bd7876e382d78983167c6209017e28133e00ab41bb1cf2ebfcd9cd9b0e6b304af17b5d5ac9354afd2340b18b699acc841ed5a93a1ecac2c6e60a1fb75d6f010001	\\x96f981331f25454cd0d79925449d42db8a96589284fd2a0cc78abd775ed7a4913d27601a611dc0851445e7b875bac5c1aac1aa9c33481681bcbd0a3f8420d60e	1672586915000000	1673191715000000	1736263715000000	1830871715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x728d5fceaa56802983b88fb0a6455bfac671b308b321f3218daba62e4d628ef8549ecd9dca861377957a381933f109d9a4743c9816a5e47e0daa423b04847b20	1	0	\\x000000010000000000800003c8c0c3134f7c2edc81891d8ed3d083f0594a0b209101e39fe0cfc54bf079cb4a36d6c2486e78a840c61835bae80ec74865df953a4c19799f39f4cf9a0378df3be6b695be9a6eb602b4710fccf40a7ac4e7bffbdf91617753aa0a19b5428ba53ce0304fd14b30515ec92e6e1b5c6c453452fdaf87bc05f18ccb7ac76018550271010001	\\x1d460a5cb9017512728a93888015d5400381604fc4269215179127c933461b9b66de61077937b77410464f2df705005d579068745118c9403548bdd74aa91a0f	1676213915000000	1676818715000000	1739890715000000	1834498715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x75ed3f47e77fe621f718babd7ef75e1afdb7350f19d745552c0a20ccbf82285f7c16abdd7a24f4a25c3c425d85111836dc6ae851c1ee11f513f2d334c5c04f03	1	0	\\x000000010000000000800003d4d9fb716cf833347b48470a7fd9b4390a4d7c0d7a3d6cca44d58b6ee9b0a71fd960e660cf8ed6c9f1ab2a5ef2d9b7e26a83b662e120deec25af37d9e9ca01fa184fa3b1af663aca7997e2462276e564e1bde45a2bb788d97b5144d23a45855c189a434d0279454f8c8ffa688a721f6bb821d824274a8266e5fd917b6df76e3d010001	\\x839eb5dce228536e442177d6122b9479d76802f47f634d47fdb7f97ac73817c653a4a7894c82c7a8d8daf251fb292e8a8400588277d5b02e41098246340a6b05	1664123915000000	1664728715000000	1727800715000000	1822408715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
164	\\x76a1c01f0a9855937084f3805d0d9b6a3340c075c7a0b4539abe7ead32a6e391501035ed4fc8bdfdbf4f8d61e7eb431a83474bacc0ca42751b8220c481b31cea	1	0	\\x0000000100000000008000039e320907c0e708efe91f63a8e355bc1fa42a749f9e705d28ea5a3ac778fb11c309e531413b1cee22e464139c0179b706eac1ba013c6342484b25801e7797d7ffa9d0e487c7e0814e4e7f175356975986925c1d6b2fce6bc1d43f242319e2711198af35b146c3a4bab8eecc7ad68fa19c53e206dddd30ba62658b5309d12af141010001	\\x0ac919512453c73dd478571827f636375c543b197ddefd248227022175e07ae4c6176593a244ff9fd781131291c425ac405ece8117a3f49a7a6a7435358eeb02	1691326415000000	1691931215000000	1755003215000000	1849611215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x7641f09990fed18a30ae38b22d043edad7e7d51ca384010a05a0135f79caa2a5ca70e0b02cdfa924ad900e6950a19ec87958ceb74c606ee83dc822648063b908	1	0	\\x000000010000000000800003c3b4b7a61feb9b66431406d461c881d54adafe888042c07ec7d1405b3936495f99ad568be007e961d297073123880ed439491baab42c09dd21e87c6e366c11ee6a0e8247efbe4e871d6b88e3f9be0f22a83019ea7ae16a3c695b8e3190972d50d66fea25f48c89b34497a2a2a5cad05a1620eaa1f0780e3652e02849d19d6e97010001	\\xbfee310459d40bc0280273abebb01daab64b763e84997999f9d21dacb19b4876ff461869efe5634c022a859586e308019252bcf01bd1cdf2058f5739e05b370a	1685281415000000	1685886215000000	1748958215000000	1843566215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
166	\\x79dd74a97c67f9797feca116c621bd321f1b25d8532fc459073bce0494558e85f077f1718a4f2ca68f4d0b328c7cd3b5e942b00a3e665c061c0329be20e19205	1	0	\\x000000010000000000800003c8b1715cb62b85b01fe942a178bddd026dece0ab191b8a1767895fc5dac702c5439f88f1e79ed4d25175ada0077d1dda421a9c4d5164ea9c65e7d5530bca11b8a6340743899607bf65af500b231c235784247d58391ba190313cd6401136bef065d00a2e81ff7e81c56c638361efd214d7dcdbf1f370d2b90da485131fddbcfb010001	\\x90b8236f220f7547c6a9d1bfd70c47c5254b458e58fca3317fd301c6f28402ca2c6cf72e5b8862fba9f34d24174629125a7e6bb32f96141f16ce6d6abc809404	1664123915000000	1664728715000000	1727800715000000	1822408715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x7c593767553ad005744a790c4dd31340806c94b5b29e768223f9bf3080cbb1b30ac59c1faee3ea3373b4663f0d0cc4df8c510b0d2c8cc79ff3a04751cf4d044a	1	0	\\x000000010000000000800003e3a18b2f9719dd58f2167c7da5004883dc00c15f6290d11949ba60502aafde15e6c48a4d7decbd173533cd8abf05e14cdc282c0c8f6a09815cf3bf1615c6563c93a50f40ac642cc28b453dc05416c6db5dc43675a9ebea1b74631cc4272339ca4ef6ada84cfcd64866adc75b5f6d5c52e6dc293f550639fcc7197279523c6371010001	\\xa03e470dd25e27d98f9dc1502e4ba44ef10115ce32a596905dfd0be6af3f6c05ce03439b236223eb085d5a7aeadacd50aba5b827e02b8c081560123f1125b204	1664728415000000	1665333215000000	1728405215000000	1823013215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
168	\\x8165a7a1356546ab4b7bde750d75c205b9db120472d4302cd609473a210a8d78ab5e8fc86f9af663d7cd978c06f21ab843c11435a0bf19bd4cc6ffbe78e210dc	1	0	\\x000000010000000000800003cc1c661260b7aab980cfbb8f915e857f1e26dcd7625889f7414ece1f2b600dbaac87891a72522c3b86aaf0bb94784d6d1b7352a6d4f6a3cb57aad4dffcd6038781f543b02d2a889441fa5fd8a5291c9a5bf9396ddc1c2eae094512aeca32433997b1c08183c4b016e1f5068ecd24988e0ae9ee02e82db2b20ff4f488e5773353010001	\\x3f27dc5f70d214074c44cc6dbc058c480271074ef4ea90eebaad207a8aba9ce47c83318570e83d529790928d19f2412365455aea501800b8422dcda2354a2e04	1666541915000000	1667146715000000	1730218715000000	1824826715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
169	\\x8219ee2b4a577403ca84bb0845748d0371e67e24d2bc37acc35f98ed657b0e8f9aa89acbbf9f32d79995673154494cf55a16a9495bbc3b7f99286c1e146f061b	1	0	\\x000000010000000000800003cafcc417cdfe6559832278c739700f5a265a84a9bcc20964a4acd7730d70fd78f777eb68286175a2a2d912e312dc7070e8be9ff65c2e36e7973d7db51d01794c637da7f709ec6b396af2e0574454493554c7e69fe5fdf9f6a7bee2c9db8331751d27ed2b4821d3e293208fbe153ad635f38036a5c66466e65baa870756e47a41010001	\\xbbb816d956a5032c69acc053a49826f4958447a6e9ae3c6ffa14579397eab709bdbf3e62e63c0915de499175438dad223b91540ecdd1abbf0da99ccf4843ca0f	1673191415000000	1673796215000000	1736868215000000	1831476215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x8255da252547ddbef2b956fa2f99abfae6fe4cb4de189faa6968ec3646d38590116e3c4f11d69b80bb759b82fd7fd63123db041834fd8e269a8a621a22f2aa4f	1	0	\\x000000010000000000800003b685d15512a4f406b8d985e824050b54296bd3dfc1ab379bcf80bcffcec2b1fbcba22f28edab4305b4733d075c176841211e929e0d66859e70a7c5eca9f053744f7a3442d5da4efa48597ced96313307b2407239c47c2c349a1fbbc2338d69b932dd7dfd44e4464996b1333b559c4aeaeba89e735cf06f97229090c384d31783010001	\\x630041df0a6b0012bb5c284ebc1daab6f0e2fc2af33bc54d570d70fda2b241460fdda3e87e12d1255dff320461c7bf051cb89c87a57c27bed43c61bae4471f00	1665332915000000	1665937715000000	1729009715000000	1823617715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x83713a1dfc21e3a7b403b397d11f10e384c3ab6f81b39cdba01e946fc7584b48dc200ad1963b1c6ed5cd2e8eec4d422a0ace21e0f6c0692d51730ac71dd3ba51	1	0	\\x000000010000000000800003c015a65d4e23c1ecc58c417c5b1e801dc66a18f808ceefb28090183a002eec562b66b0ae7cab8f48e6fe654ffd906f74af7631496557ee92161667707c5da7efa71a4b698c84de72cd16b515eb3b18436c70d2a39825dbcdd63f74290fb807a7ee07e3ce7c332e44d0c245035eaeea30cb519925238b2eaf1d982a8197dca6cf010001	\\xd0e2acdbb35a7aa4c6c2cdd53b6355ec21e76519364ec44a7c02fc8377fea11a7ab23a2b783da0140b1258f3ce6e60d2b2e0aa18ff5c88843ffafc384dd10204	1682258915000000	1682863715000000	1745935715000000	1840543715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\x84ad4c0cb0b295de092485f78bf5dc2a8c767b826fb43a8dd8f19292071b894d0efad236fdc76d2a31e99da3cb16fe5554e6be85244b07c1e8039081add73a12	1	0	\\x000000010000000000800003cb37f24faed168127c54b3f0f805feb77996c04c67d6409ce3af027e788e1f49d09ebf6fadda96369b92aeeda2a9d9a93ac9e6881e592b0979eebcf62be7f3da6edcf808fc5a2490b6a61e12aa4ab10664c78a679bfd83c34817fbcf5ecf80e790d29a616e5cc7170a04e1c0c7ebe840b89c656e92f090ea93b60c2217e49a23010001	\\x982fcaa120b2500d3df937dac5718d07d63a8f3f376b6b26adad76e8705f54ff286ed0333c1f5a9651f7ef96bb0b203009de9a7bf6a531c1969afb2fb182410e	1674400415000000	1675005215000000	1738077215000000	1832685215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
173	\\x88e5959a0935211d1ab14441d12007de8cb41d23fbdad92e1347f1508ccc9dd81579ddc0db8b2e3b03f7e59d80e9fe5aa4fadf3e431e6e1d38648fbe23fb0219	1	0	\\x000000010000000000800003ef2397a493f30149c0315360275df450d085330b1fc85b8993c1ea8d10e2ce5e77da7e9e2dce96621393960a032f227bec3e468e49bcbfe00b772b5725d85a7fc1428ea03425612743de62dc5a08f5c5d3712c6c3d4e11738670963035d975008c73525cd7e94942dd4767e39fe4a5301ea35034907f63ff98b031efc6f55189010001	\\x85678bae84cfc771886458dfd3afa6b749df31cc26b18101f7e050af682e4fc278a0a6cccf127e7d02b4d0afcb5e77406fee8c45f33da31c98e02c15ed8a1d05	1672586915000000	1673191715000000	1736263715000000	1830871715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x8cb598f56d9526059395f10d6d00b17f1f88ea84cf00da8691b0dbe63167b06d0421b658803ca5f3b6d592495524910bcfdc39d7b39715899d9171dc3c9b64fd	1	0	\\x000000010000000000800003b1fc154e2aa243a7fc0c0d9f3d4c2089dc95f519b016f99191d6f62b29277cc319a77f91bd3a105b174d8463e421826f361eaf676de18cfbf3e3a845c1d8df408f8e31f120cc27a49bf60dd9fbf0aa34992617d85a7c2802185914a3bb1354aaafc174e8f9267d63617fbb064dfa8957284e65ac72cb9f10c58b74b68c61d459010001	\\x17461d097146e79f1e4dd8e777350b8aa0c98b0d45f7fef5baff7364071264ed26bdb81da8944dd8311fbd9a5daa303094364582c2de366b0a89b812a5bfc905	1677422915000000	1678027715000000	1741099715000000	1835707715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
175	\\x8e71ec089f7053142bf4e05428299d039f7bba030e67f61c861eeb35c0ebe660d9bcd2d035ac5f07178505a821f61f7dbda76c700cef789648e33a896975777a	1	0	\\x000000010000000000800003bb9a1745f05427642afd624773d804b4bc76cde3e2bd23d61e0e2cf69b7d7dc740687fad91b4f38a1a3b456dbeb98b2d67bacbc3ce1a258cf32e2dfdbf53d1b7be2f463f30d681c77ff12efdfb03aa76646820b197ceacb62cf3e9948d329ab3e98fa4b955dfc5d65d06ffc11d88f8e1ec895f749004176406e5b1465a128371010001	\\x9facf175d5d810b13d46ebb31119ac78c9a54c5ecf337c79def17e023bc7aacb755569cb6afbd5bfc6fe4dc2685bbafe687d893e14bdfb748ebe6f241f47c80d	1677422915000000	1678027715000000	1741099715000000	1835707715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
176	\\x8e8592c902218139790fb328eae4643b40cbe654dbaff3647a3f97ac204826e7d5136f631ffe67cee2ec6d0f923b5350ba8623fb64cf8188abe1d1fcdc6b744d	1	0	\\x000000010000000000800003d435d87de1b67269feb6fed780a6fc4fae16cae7526723fc09c08291f09cdbda4c71d58a7cc2f86f5f17ca8002190dbad7da194351c179c03b7aea02bfcf00a11a94cd4a14afe2e4d212d7981b94b69fdec11a67d3c29fef8608b43c3d5cebca2683de9aab8173542258eba3388eadf00eb72988399216c7d33e7b4f238a18b3010001	\\xee641e96757ae52d611bee90c42b6e2e0846266b7eaed4f2c018ae4fbb5a4865498ebbc2c5ca0f2a96331dfe03abcb6bd41ac0695e01e9b92ea7e783df25ae04	1685281415000000	1685886215000000	1748958215000000	1843566215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x903d4cae5a3e00e9215176ef2a6cad41a1c829d49685f0ecaabe5fe1cd404724726cc1f1096092f12965ab65154691b0dcb90e5192b8b51bafbee1f2237f035b	1	0	\\x000000010000000000800003bda6efe76180d14338998829fdf68749d5d6c7041e3b3ece8d56d03d07900ecfc238d0106e0f5a9fde02242fe95a2cddd888436a29f7bd1b0de5b7eb775810c2d4d9addf8d1328b19dfcedf840c4c65b6d076b02a1777822173056b2d5be46143bf7b8f59878bcb88d8eada4dbb0814d5d7e7629e95c009a8fcdb44b5dc32ba5010001	\\x30f6f8c24bfddf0809dd205c9100a61f5e8c4d38edd959bac9dfb728372678938af64b67683f216bd6156319148c3ff12002b74faafda3be886cb650eaf54507	1678027415000000	1678632215000000	1741704215000000	1836312215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
178	\\x9221e9fa50d1b8885a07097225fa3fe02a823aff3607b1055d9ddcdf23fd1daf58754b820cfdcc159748b48b4a725fcc3a46171f15c3559aac2a95f3f6e9b1c5	1	0	\\x000000010000000000800003bc6ad8f0e44d8fe9aa2aab32c9d166f497c091b38f2f41390f3580b6855a8022001106a03b54e0b7a98f591bcf555b41624fa0882d37cadcff3d79c3d5963490e8e6e3906f3ca01ccb658f9fbf949f4720daff2a51c50508a95226111bfcd912b0d14072498036f29bebb1fb4d27559ea419e42dcec92efe050f04b43099b929010001	\\x034cff70a2cb67a5bce4404fb816d118ae56b870e7ad4349af12dbbfa700141e44393536f03a54fa5e9bd33831446c569aee045b9791d0890e3eb3dbb3cb5500	1662310415000000	1662915215000000	1725987215000000	1820595215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x98bdb7afa248a3c1a2a199ac7cc67ead7cafb52e090186e377d40e3255280ee2c83212e23e25654d61a7074222d2545a10373a67d9e520d04fb38f48dd46c1b2	1	0	\\x000000010000000000800003ee16ffea54462863a7a61bde1d527f14bf8df588e3bbadd4550114660031f1560e4ee3fe0e4049acddb447be49371b2d13ed80d065edfbc30a7a77f8d2e86be83e8e8e5c69858255be7add827829d0fb29357917635822d8715fc516a0722dd30f53017ffe71e814d27859d3611ebc2a7b4dc61521ee0781da239f3fb95fd8b3010001	\\x0ca421ee7173391c65713c5bac3ccc6f37d3d187ee34407ae0c57ea906acb0f559f849adbb8d8a7d94f527f4ad9d1eeeb9e67d119204e6a6200c08f7dd8d5e0d	1675004915000000	1675609715000000	1738681715000000	1833289715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
180	\\x9c5590d0b518194bf368895eabde2d17db6190553ffc46f805aa4cc796bed3850faad6dca72fc9a946b55529c51df1e81703629b6b9655e27dc4d3c311d7426c	1	0	\\x000000010000000000800003ba45c860a15ac662177eb1fafb5e9dc24ade187e7d268a8247ea035fe9a250d77262b6517db381725b2bb4ed15e831647de11656f58aec25dd2352f763a44ebd0d8943de8846712e130f748776a08155590150b539500e520c169baaf29b71ca1fee3b645db6cf057d7d4af8c886992591e850ef8f0002f40f2afc2feca1b48f010001	\\x469f2f63f5dcf8f0221806aa00d1072e8e6e51ff0f57ab105057ce1573ab3ae182bc98de18d55cac296a83c6c74430bb9450d3683e6af03069d91e6502cd320b	1664728415000000	1665333215000000	1728405215000000	1823013215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xa37982a3081d4e51959ca1813c80c2e936757e18d7544d917c6a1c05fc6f80f660dbfe4aebd6d9e043b1b7379c3156a31534c17aefb7f999484a22fe4517e8f7	1	0	\\x000000010000000000800003c52399ade4b52ded371ba6bd95f057d7b781cfa5c7427af618de21de24e51ad2c86dcfe6ed83c7ebd9da7b2d6b10a55928d0349d2b01a8de60f79dd38629d601dc0a6d3be6db7d449055800549d527c332f4f9bda029e9e51fc57c7168a67bf2027354e7fa1517abf08830a4affbfb975c1c7c51baef6ae3b837dd924b403ff9010001	\\xb5e20edd4ed65c00d4a59a951bc3f3f9cc2e5d63dd8bc6b555cdfdd075b418a57bf0e4aa0790e7bf04e9027da90af49ae4e9b380a0b80abcd7c3b279ac26ca00	1691326415000000	1691931215000000	1755003215000000	1849611215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
182	\\xad35265ff83ee808ea18b6b99e89330f20b0ce81c87e40e6e6bc9452dc66a68e40be2879e4d3d973efd74275317a46ccfc334fe2a564c6e4f5534a1a0ee7acc5	1	0	\\x000000010000000000800003ca47cb75c83585f598850d869cef4f7573abf8bc69a5f5099fa7c3d961fe87834b302d978beaa524b8102ba9db55eab22eba63e5b646ef5ba81b470c6c3ff198ba7c3a6180a6574ed27facc4fac71a4a67a58e32f86f2e5ac371cc9a3e6307eb68fb493f0bc14a2954992c2aaa98263f2d3fa99dede55366f472155fa7d50585010001	\\x321e7a44cefd483311a5a825e42176efe5783ab0e4b8bc61b395cbde2e37d2a1dc42b8b9f8b941978ea0f72935d935b923738b3450dbffef0f0734d9609b5e07	1677422915000000	1678027715000000	1741099715000000	1835707715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xadcd65970b48094188800cc3de4fa6d048d9040690e993ceb0e4a5da91b8ea5cce8e49459188f32f58d235944c92bb6f9782d975bb04f70931182b230e40acf5	1	0	\\x000000010000000000800003dd2d6c2ae65dae648207810e29029c324997a0710a1aef3993afd23357d8160a09605470592ee85c54b2bcdcd049a2d71e15f4f9b16cbf178027211a16e32ccfd6e141868c241c6d92f6d4424cf1d44b5726d813ad52753ebc51dec44d421bec06d87f8334bcd17c4b03c061465edf1da5bdce891b247037bc7af8da18e21e11010001	\\xffa1ec4b295f96ee59681578c7df1e97e131a946f2244e596e5e39ca79974ae12c144611b3bc2345df050cd35d06fc6414f771d192f8abdbe6e57925e2aac409	1687094915000000	1687699715000000	1750771715000000	1845379715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xae6ddd2665b51d0afb5a73965ba2e6e8a0888e3fbd716551a61583be33cb351d6b264e5c9aa9311794445ec4d45d5744ee0ef21cac54e5c2fe1c4b76950558ce	1	0	\\x000000010000000000800003c294e6e725f740ca57b69e3adb9cf98eb0d64e9728a15f3db465029a9c382bb4c4ace870477c974baee8bd827396df1c316592965bfb4f2023ff834b714e5fe9c69e13c615321bb657be7f2e9900ca3570d7b77042b556ff709c6cc250147977097c1afc7f1c359658825ac11af28090915d54e9ce7a0bb139524c373b504051010001	\\x7d1791f19e780a911be4d551908f414d7ef8c952dfaddfe95cefd64611a2e88028bf81c0cf799565c5d7205af75e867863ccf9df1ad2f952262cdbdca5347e09	1678631915000000	1679236715000000	1742308715000000	1836916715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\xb1915ad51742a5c069d8d1060cbc67ba2bf4e69ef558eec2afe83fbf1a27da8e38cc253a815b600ba89617f7db50eb4b68284aab855c129c164011669920393d	1	0	\\x000000010000000000800003b0389a4f48ce8c5a480dc266de312724fd7a372b9ac945822cdd8af6c3b956b4a404c02ea050146c62e197149b0e76d76a90b4e5555ea2b66a15dc265eb3085e70f1be55ea4598113a7116d7c8471e7651dbb728e42fa5c8f61a3ab7c0b1ff6777ffb01eb88666a4199941eaa24aa6603bfc4bfa23bd3a65d86bd539e6a2529b010001	\\x482bf040934fee6c2ea86930d9c5a0bd25dcecea9f770d1eb2bfcc67ae069dfc4a398fef7e46c9eac3d09214249f1e7b6e03d8da67c5e773dd0582626469000d	1690117415000000	1690722215000000	1753794215000000	1848402215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xb48d5af42db1ca48a91313524f18ad0e1a4982726d2c505900b898cce1b361de8a70d51fff0a496b570045c64c09ea52065f933a90ff9b89ed6e33b4bff5def5	1	0	\\x000000010000000000800003db33e74109c2384c7acb42ab675a5f40046d5a3d395679dd314069b8b58980869f27a62b2bfc8f2eea4d811a80f305789dbf92930599f40ec2b247c7fd0ee810564eec29b2f2cc0f81a5601ec9970b3865b9ea83aaba1b8a94c50431cf8a53f324a1882b172775d4b8d7aaadb502851967abe5783c10081601bbd19e4a1017d1010001	\\xc10731bc6cbd4e0d8018e6e04a42d1c1597940bbad7adef557dc0b8015c32de8ca84bdbcbc54030a2b884f86d89d7b1e74d8bd6d6f51c9039c1407b18b0ff500	1661705915000000	1662310715000000	1725382715000000	1819990715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xb7711849a61a12e5995de0d9c848748d7cbc815cf0e4654dc28f5ecf83e3c9ab9e70965c41d6d18c1ad21d57e6d4841f5d3d6382742170a27a80e0ef615b787a	1	0	\\x000000010000000000800003dfefbdf2422085b1b1646137273ca5fd270b04fc219d3e92caabc9268aa1efee389b3f4c70e08140bcf436f1ce586f1fdc6ccf6af59fc939ae3f2e879998a906ea452974b476cc9d772de26365bf86afe1e4d4401087d6d7f6b280ce732a6d0fab3afdecf5071530433ab29fab51fbb534fc625fd8583ba7d831844f61ffdd65010001	\\x815e96279b60edb6b10df749816916462d22249e63eb480b33d84f2203a052f21b1ceb5bacbc85044da037ca3420e997bebc8533eef7441f17faf0ec41e3d604	1662914915000000	1663519715000000	1726591715000000	1821199715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xbbbd13f89c98294c525320285b90ff978d49dcd84e6072e62182739fef5b7f882ddeb0ed8e06fd1e11bb5534dc9b29072a6411681795f394535fbb50199ec41b	1	0	\\x000000010000000000800003f3aa96cd6f96af42b48b0bf23f411fec1377810475dce8dc71cae992a72c6e2ea5fd252802930deb5019097980e1916fbf37df41a2291bf9930cdeab23d435e20707d8926ea412730c7ddf3e1f55717ab49ad7524a9cc3d07f07425b6e9b62c6f425349f0b36cd7c351b72b7789cf6cb59829e5a12d1c7c16a0b2a2ceb0c2c75010001	\\xa25f2ae9e3e6233ec1fd5e26a83c460be0b5b4a45fc7704b8c41a67085a5331246d9e01b35c58e027aca4a052e0717b2d177c1fb86c27e3023bbbde4c6eafb03	1682258915000000	1682863715000000	1745935715000000	1840543715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
189	\\xbc41f669c4d96042aade3b507e13dc0a8aeffb26a07cd5de27052be4d7a1a3a42273f354797ec7825860e46b13c6b6370e9c85540651611b7172f8fa1ad05dfd	1	0	\\x000000010000000000800003aa3c0744d80aa8799c8861a08e15e5959bfb071e1d84cecc905843b328a3f252fd9cc9a87cf2139994ab87d1bb20e86e4c46be3abad6914f759a1fbca9c5cb4338f519a2d7685d9a85d674b7b896438334a484445cb63206d509dabd4ad736142a2594f0de5c8c1ce47bc8bb036b68fee3dd93d2cba4e7e5e7612a049ff612e7010001	\\xa1fc42f615eb26fc849130809c90883d29862c57af2dcafb3eefa3d5d1cedd771f23f5772461c50d1aa39b33245a7154150fdbf285ea7f663bec0e08a526c608	1691930915000000	1692535715000000	1755607715000000	1850215715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xbd018e6ae8910a4aad19ee195bef1e7fd91cb6f22957d53881a05cbea5b161c84179c26d3381f65d8d5b279bcc680b338554a8548a9e155c040da4aa284b434a	1	0	\\x000000010000000000800003ee49038a948afedc72c2a55962047e0d3f646e2a8f7c9dab2d1431a58c28d8415e61006e4d61775df10c34bb8e2d0b34ea96b35836e277d10ee425dcc882a0b31af3e35faf28f7894489583d8e839411b61b7d7d0b1be342b8f8eafde113eb872d8a02fbf8d044a2af025c65547bebfb107150646d4598a99e8364ba4cd63907010001	\\xf816df5dc91ca13a987f829b04820df9e19256e362b03a890e6be2614e8f24aaea54b5ab6b9804a24d37a4b02b5408694d978ba55bc204d6e370a180faf3a906	1660496915000000	1661101715000000	1724173715000000	1818781715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
191	\\xbe3d14e521b51d191a747b0f8b561903b73ad121fa6f5c17ef0b66cb4fd1033e0644bf12d849c271dc50971a2a362d2d12152aff70c1a42b38048477a6815198	1	0	\\x000000010000000000800003c3f8b70ef2bfa27dc51596ba2fe20425be7662b1ea5eaa95d568d721906b0c511012b7c3f42ea71232c976288f8c64c7cb336f0ae7e906ea2c7d7bd0cb293324b9a2b1b9c67cec80865daee8dfb1a6c1af88097400190417d4237c463e06b488a6e653ab08b9166a741c39aa5821ef76452096da9ea99742464f65ab68f16a53010001	\\x96563bc061b9e936d66d6320eedb5be7be4a577ee542b7ae7b98b3364573ac0717000db17c237263e6289c18e2f763ae0b48665a9b6b85a14bf8edd54d9a3402	1672586915000000	1673191715000000	1736263715000000	1830871715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xbfc1e7b79019912e15d0ba5c5e2b968e8be0e6091b998e2669859699075494ce89a68223040804953ea9af0d8e911685acdd5ec6abd34d04671a65835a568157	1	0	\\x000000010000000000800003b11eed0675369bf472d4c9d5d6c51b4e94b452d49b948ef87c79c288d916fe11c2075a56e75a084ecdf86ec95a0827282c2563710ceb6a15f4d83add05c3182e26131b384aacb8cc01b3663c019e1d9ec7a3cda758f673ce28250c7e112f591ca1c53fce0678c7928f4c2513f1b9046fda1dcdffeccef2759b20a53998979195010001	\\x2a7d0d41f7589bbaa44e9216f1d3430afeb57f6771009212a3a95c3d845a5707bd11f28be5384ef9742e4acccdb43247b713c80968be691c075b787d3c8c080e	1683467915000000	1684072715000000	1747144715000000	1841752715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
193	\\xc1c5ab069cbdc15cc134dd25b13f8d1b618366d34dbc40134d7513e92ca80fb6f3c45b1c26a407278e56bec2f8e134adee3eee2dad83f8c89e413b79712b8c1e	1	0	\\x000000010000000000800003fa8251938b0f5c4e5171d5eaf8c93c93c6b4de45d73962fb92201a4c761c95768284dcf0b31755aa77aeaf62522cc7df02df5dc27379d21819c72d85ed0dd4320129d8b40ee9a05363175eb6f96c11d483abdc2f381ca5f92fd6ccecad4c31b49f003531e871ffff684dac1debf97cddca7641a51994506e587dd73f4216ce11010001	\\x5da1b3aeebc7ddc143c39686e5b9bdcfd7ccd0ba2cef7c4c133144207ce19ab3145f58aaa21a4237e996c62dc541a3ebc8da38b982c0c563a13662abe0bf960f	1663519415000000	1664124215000000	1727196215000000	1821804215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xc265bbdb75ef5e142104c9b3fe7e764f8f56080289be9e2e0bca1676a66b35a607b77af94b9883346ff37b6d7de55c803bcd08f913a5b6670ab86f0f9448b672	1	0	\\x000000010000000000800003d7aed9f68f6a9b7124f83ddd8697b092dbb37c9b0f398bcbd8a2e8d87b2d7a59596890be36c18b710c1a34df86433988ba057b392b05ee83e1512c1b7f6544f548fe5203a87ff55ca60f6a42f727665c374fdae58d48620702c4b845206f01386a9c9f1f339805f71571baeac8ae6b528f86739ff07d79404c887e1760cbb591010001	\\xf31b2e3d1ed0bc2df0dc965ec2d22fc0f059309b1c5cec4d7706868914e355be4a6607cd401512d892345bb00e09138043d60f5570fc627f5897284b0a19580d	1687094915000000	1687699715000000	1750771715000000	1845379715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
195	\\xc2d551770d06845fa7c98bf4c4a26f5f00d0575b4be8f9cb4f4514248f9034615e6d52566e726fe48381e3ef2734218ad7df95be67179e32638498b1ba296a2d	1	0	\\x000000010000000000800003aac25085c3c14cf72bce279dd2c46badb0dfb75edd93bd23c8763c3f87f1f278a657f7fe1accc3099992bb8256bb6b17ff4f5a2875611c7eab2a72328929349ac8c5f5c508c61c189e007575e43e6708929f94dddf7ddd800e25333249e11c9359720a6100a6800145d6b69a8317459174c42423aa1b012f5d6e1ebdbaf47cfd010001	\\x66598bad9b8fe319a8feb50aabeca3cd998fe03c7fcf39561a39faa55fd3d29e5140d61d706e67211260c50f5f9c109788ccad36f9a83f1d0d305bc5fb36a90d	1687094915000000	1687699715000000	1750771715000000	1845379715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xc3694d2988523769b9ddd04aeac1bfe174a1626f09e9b57e75650597d106eb40745c2664d143d0748139d62e9b779a4f1dc5d47ab0f990f009acea5142046cf7	1	0	\\x000000010000000000800003bbece2789dbdb110c4979f9f68f114fcef7d0fdaa8a96dfcb77a5e3265fbdf456d51335f0a2a71e93c6f03bc340c31ad317916b6908269bbf750148314d3d7fb27bc30c82f7119b2320def53afbfc15b1bd2b90e5c4286ef76e25c5b9ec2521ede706c8632576d5d0b55197fb800dea15abe59ebd8e98e8181c058a58a7fdfb3010001	\\x000b6d4844338e30612f46f772b0558b1b2b22eb9d8db8774e4cdeccf990908575213b545f3c8a30f3ee91f0ce9170107889d08e4e07108c1f44bb4e2cb85409	1662914915000000	1663519715000000	1726591715000000	1821199715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
197	\\xc8350c06cc63558b0020d3c89688797da6061b3c3ff5793da7fcd7821f26cad95af248ecf457ef8077cf983731c2b380a5a8a813e2627a84acc90a3bbeab4d3b	1	0	\\x000000010000000000800003c58c92b5a89f45e3afad30ee1116446ebcf38297344f2e988b8e1756993a6307ba13d69b9681a1d6dc6f7afcecafbe290a849baceea386112d017111034758f7d4faf7a927221dc41cf82e04143ad8d3353885bec3b9fe69cbaaff083d8c2b984c8a52989d2c1d18cf5891e0ccbf6ecadd604b0928607a2257203bf281f188c5010001	\\x261b94b08f8195227198cc646ca667b55ff0072f00188ef47a6e6a6f8a080d6760372f9414edd6b66c3f50bb00c569265ee145f0662985f2c64fee10e2d84309	1679236415000000	1679841215000000	1742913215000000	1837521215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xc9c5bc1138c8fb4148139a06f139af6a1e0e9c058eb97543cc610b333364b256df6d18edb2eff886a5ff67b2df88aa53dc3f29100a16307be7306c4443f07f2a	1	0	\\x000000010000000000800003ad361c2d38cb3851b384c4f36859f4ff8d0e53d349657aeb07f96d55ab0fff05c1c5d906349f93ae36b62d57f6ed92e98c4b8482b9c96c41011da9d9abf5f3bcdb667bc232f14dab9cb6f04d905a69df2f55955ab4c952c843aaf50d9aed3f6aa5c4a6e4b083f8fe4ccf7da5f91b5f9d161256d6328e2d1759df58f132356285010001	\\x53ee9a655530b4c4eadeffc38f76c24ca67d75539bbfc41aa267f1f41f7885bbd02ac16c641e906360f44f5eac9f066a5479e6b68e129bad822074bb61b02801	1665937415000000	1666542215000000	1729614215000000	1824222215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
199	\\xd1b93951c4763e701aeefc7d9e1f1465ae8ff9c7bdb32ec058003737a3214e844a40eb5980fba6fdfeb2cc1caeb3af7b83c28c9d3f20201ef3d9e560a3b441b3	1	0	\\x000000010000000000800003aa7deeaaa3782a8a1c859dee30b730e1f34860a5b528867959050b86baf0ba6cc47550fd83fa75b6938eb9ca19d64e8f7d160cebef5f118259f1c1b2f1cbca1ad7b5dc620b05c7e350ec52fd7e8881da7fcc5d16cf71dae1ac5893f0795cf4c42133ecd05fce575a8d315bd62221ce1ac36b147a60a968c472c44a6c1270bc43010001	\\xe392857650d5cb26b92e9d755575577119de61adc884d45d412d810c052018dbfa13c6d3f0e1a6cc5e1d5b46780ad62f8dcd8a1718255c71fbc0e6808ed1f605	1681654415000000	1682259215000000	1745331215000000	1839939215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xd2cd091a3e9a9693dc257f3384135f90214dde0c29b065f856ba6490202fbc5e1758d8c68d4cf9ba7f584e8b34eb1b4a01f99425cd3f5d4a6cca872825cb8baa	1	0	\\x000000010000000000800003dd1c5e36c91b4b62ea796d38091be255487b1023b606ccae16d68123e9c07c792b6147e91218844cb1045b6d4c7283d3f2690b633d6d2aa18f0f4acf83d203ecd8afe7934793bdb74c627ab564ed3092774b5707afe355d7ab0c5b3c1e1d82cecd0a1370d2e7a3a5543cd194f7254ac68faa83fe9ae5b5481098e5b5a66b3e6f010001	\\xc052301f9b86b9299f8751408256d8ba786ec82331296bebc9164285137bac3e4505689624d5e896f4a6344873e2f91dd0f28891a30b8104481f34896c5b870d	1688908415000000	1689513215000000	1752585215000000	1847193215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xd37523e8e47df677d36f14cb5924e6bb5df4f822233d4ec39c0ba3d4cff22a3336d04f734a469a5ba1a982909ab53700ded29c0834f49de97a50e50b46894900	1	0	\\x000000010000000000800003b39b46e558a6b903d01703ce94c74b9ab6b9b9a3d05720ab0bbb8b73b40ea2f6e16db2b90c55e04408f6c7addc1db461c13713f88d505aeb3c0cb286e7f311d890d85475900f5a8675c19d55c3e588f22f0eb05247382cfa0f2f0199f3c7ce63c98350894517a7f2dd9e015a6270f26618e7fed4abeadc04fa6d7b58d4805e33010001	\\xe516caf7dc16158b5dfdabdf8a90745fe05a2634fc3a56aa134feb3c71d79544a45884770826576c4b80a04b72019a8885fd91a76c69f0f637fcac0b9bc5e203	1676213915000000	1676818715000000	1739890715000000	1834498715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xd3397cd1b5aa63a186a2814c6615fed8dd935225248105e28cb6da891e2be8524c55041cbe165d7ca95e1e09592960acb38c4d0e5dc1a63dd4349570fa64c030	1	0	\\x0000000100000000008000039b65598b7eee222abbcd1c8b93e42140e93e26a51c768b72f0473bbae37ab408127d2c8be27ffd176d69da607dcb5d0459a3894f3ffd3fb3413862dd4e4916d449dc827e786c5c8092b16a2d641d9132cbeea144fc8ff15d55a3592d42c7bc3e922b7123b54bd8cfc93f6f5293fcc8f6d9ffccae9edd625ddc5ac32517034099010001	\\x980243f5b18608a3ac0482530697e4873221ff57668dbd6089953ea1492b9bb95693563f645304ce66175269f14357c1467291e628d0dd688c035c1676c6950f	1682863415000000	1683468215000000	1746540215000000	1841148215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xd9f5b44044aaa0b58f1f1e5f0e16a4af12345d3729f10da77df7c35c6bc59def671836ccd6074c5723757509c77bcbce5c0ff97174e9eb361f4ec4805564854b	1	0	\\x000000010000000000800003b0330ffd0eedbc859f0e278f249e1e862fad5837ce0377f60863b63a1cb0dc71c08504f18ba0b7ddf2ffd4dea917efbc49c7bb45315fee58cf14b24917773c86643761e5cab4dd0d039739768f9a5074746865292600591e3014a3e9b2470ec251152e65e7fca7adae79f56f1ef2fbc1af10e33dc8ca01eee3e2cdab82a06927010001	\\xc389478401177da4efd8de0c1bed1b0a28b727b10d14285a299a5898d3bb811c793d3c19d3c62e861bdb5975057b6e22bcbba5a994271d533fb6b3e359af3c01	1690117415000000	1690722215000000	1753794215000000	1848402215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
204	\\xda69d0c7d2d68d95b399595701eb7f8f80689cd262b586dcc6f6f5cca9042358ad17119080e268446e947fb0ad8e0ae8f5fcc2d194f5db29892274b8e8c65889	1	0	\\x0000000100000000008000039bfac76ce9015df21e8dd22d329732c31765db5c2af8622dc33d963b124964bc44e0745ffc493246181e92fe0d38aa03771083fc0328c93694ce76feb29ac469e6d05232d4ee2a912da929e83eb57f0fda66a69c939e8c9f913a841a089b586babba870fa6ec3a4efbcec699faee488a994957c24d11f1ad6b7acb6c0cacd507010001	\\xadf72b9947e0ae0330f04abd06a508c1c2d153859d62a5cdee0db734abc06d82e69eaecceeff186aa41ee99a04af9984276b179cfc5b0c14e20aad78194a0802	1673795915000000	1674400715000000	1737472715000000	1832080715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xdba50c847332ccd37dade0b66bd2f4d053448f214d7e837b896c120a8089921fde8787aaf3f674acffa20e7eae671990326c124d314fa0eab9bdefe83d5c755a	1	0	\\x000000010000000000800003a260e38436a3fa7812a55f02da482154d448b5d7fe845c5ce4f0b9b672d657717b9d19dff32b156eb853f0f4577b099d938eb5688717c24147fab552c8d051acaa798eb42dd0c714dd13c021af401f4eb42c3ec71186ce2b558c29767c7078ff99d019f90ad192d1e1fc833ceea37ba0d07f8d6a12e6f0acee37177554b0d5c3010001	\\x3bf9b409bc2d628af95af701719a4017c0c1cd8002fb8d8100019b44e0e1f090132e48fffa8b26b261eccad35552a1bfd18f76bad5bf13ae8e7fe0e389656f01	1675004915000000	1675609715000000	1738681715000000	1833289715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
206	\\xdb752b87ad632bf98b38645636284a0360142e4c57aff508336b285ceede0275b3955910b50002e55201733465d3cbfd33a81db0b7a8141f6d3023fdf4a63eae	1	0	\\x000000010000000000800003c1dc41e8018a378533ecf914eb1a125cb9f93061d60d4431f8a18e1b75d5c0f573bd4e7ddbb8c59fe3bf4ce09bf7e1c832304d86d435e3cc5bb55e160146b5bde0d4be2e757b2b4780e8083be838d72766ef883056a9420b2e698676ef86fc4dda6b11221b1473eb3ea4fd7f3de109c644756d3aa58bbdb49b1796e01d1f1ea5010001	\\x0cefc1d80f9f1d86d2de778972760e287e7afa5257358c88ff192d47418ad0daa726d0689f568ec7f2062119583488ef96be379d6bd943cad69ba8f57d25f800	1667146415000000	1667751215000000	1730823215000000	1825431215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\xdeb9ff310b3927b49e575881c51dd4e7dec5a7b5d4d162b82a7364988ddcd5dac827e71dee149e1257a88af193e93df030587d520eeaad08e58b179af16e8b5c	1	0	\\x000000010000000000800003c18f3554ef1a9b7548649e4dc0340592eb274a02b9ad9fbacfbf6dd320160e914b0111bf7852a23916a75e55d7e9f4865837ce64e696dfd1fc68eb3fdea583ce5e69f08bdc87d31b5433a715dbd6e3b6e8ff9c3386b76cf44926060b9a8f1d841ec22f7568605e4a2d7c0e025697a95993918c97a443de00ed74ebfee5b0b465010001	\\x749f44621ee12db33dcdf54af736a8532cb651a924d8b6c4b9b998bf4b318632b933fe3ac3f78653bc16a4811b6b39b0bcf428233ae8e5394f4aad7559dae70b	1678631915000000	1679236715000000	1742308715000000	1836916715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\xe14d851a52afd17b83e35055eb200db232d2f9102cb7d071dc0ba39147991f52d3c4693ddf563e2a58b48c1bd1282d06bfd8db3926426b1f082d2f32f12fb56a	1	0	\\x000000010000000000800003b2b662edea750b915680835e24826702840ba924e686dd3654301afe603adcf4914485a2d62c8fe070f49d0bb1a5cb3d736db611fc88efa9715c59d12acf8b89bcd1e07389be7efc3e7f5b8b70a35bc1c5501e795ed3945b85ef0ed0d2b9da66474882a8b1a9cb5413ffb157f0ef8634a0e6e1adf9abd8a3946692d9f6b4086b010001	\\xbae3e2879d7d82a471cd5c25dfdb28bca4e49ebe5d1e61b6f958964b4301f6e90bd5c5c55bdfe0667d675d3c12d923046b2a1ccac1d3f25d84beecef931a5601	1660496915000000	1661101715000000	1724173715000000	1818781715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xe15522ae706852f101f87dbf56799b2ba303f307a134db7936663ebc3d4884f77857a1e4679e96fb32a0a7963ae85d843219dc794b1b1dd4f7caf3c22bad19d4	1	0	\\x000000010000000000800003f43a5dc56a19a84f0b16d078b42fd24e335fd2f3d4190e40c6b5596b35a4895143491233ae80d5cf7e34a60f56f9609119f4f91d80aff7a5c3b855592250a6d233b9ab06cb3823050c7ad0c9b61f41e8dccfb05f868de494142d7a666ad14d5159e5778766c7d5e0d660da9ccf92fac8580eebaf762e391a9be4b1f0d5ddf893010001	\\x96e81766c83eca18e07f6e0f2102a7bb3f7b5877ddbe67350cc4ef4fa83345a08355d26675bcb463aa33d3afa766a505b09ee27b4318a83ef82ae43939e7f802	1670773415000000	1671378215000000	1734450215000000	1829058215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
210	\\xe2b9de06d389f894cae41a56011dd104dfcc82369c7be90090e8027018ae8592a54472e4c16a47809c3f656459b1500dfab4062fab778a70337f2a4b09d060fc	1	0	\\x000000010000000000800003cb4427332d17a4f2fdab2a3558cd9b832230988302ad79564b9de99eb0091331b26ab0ee2064fed081c7aa9f7768da6d65f8620401e1979857e0651a1ccf2bc2f58b5ffcfcc9aedc85928b7a0f4449dbd65c30f074284494a8467901e84e8d570376e507d739dfca1d6db56beeeab211d850e536a6808e2d71dd6a6c03f6f2d3010001	\\xd333e76cbdb74e9fd21684bec1313666d6b48c045b3bf1afa69255902db91de2821c89e00f0b62c014b11cf4236c99bb149cf79127e7406f9d1847dc29862f04	1663519415000000	1664124215000000	1727196215000000	1821804215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
211	\\xe321bc6908c41d3b89c36dd9903cf0042ebca3d75a4455709a2ae5fe26a2cb21e9c66bb55eda7582fcf66abf6e9ff3ed4a47f367fd3d490c65da022167011a04	1	0	\\x000000010000000000800003a9642a75ba40295c504dc2124a559485a52df5f355e0f4f947087ecd5ab71c2ebeaf2611d2ce15b1a665075e5ad0544584b9167fafc30071aea285b081f88a5db689d6dacee8107fa7da45fe3e8054f9602fb632d91fcc14a2e14eaa39b76ce4e5ed1cc50d42124fc777890f5e4b30625b133a69cc3f65f52b399fc365d73edb010001	\\xa598a2e8cce281b0e7389b9826871c01ce6037773efce336b9fc569c49d11eb8fb504050bc2ff3cc0bb0198033cf8a611cf9351ec7be2be3b89ac5cfda81be0c	1671982415000000	1672587215000000	1735659215000000	1830267215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\xe405172b11793ecfa0d98ca801fe22aa591f17ad0e9d714a77923e75a9724448e9a8fcedd2e512ddcc387a6b390f70af2687995be64e80aa630cd47973b9a924	1	0	\\x000000010000000000800003a7b15af18e31c1f05aab6cb96c1576e665e5853a0b253add01b6a6fc62b6e4159b9556ed8315943bc58207a9c74640ae674a79f5862121dd1d3f2e3765b8aec73272f3521166742925ad4ec709f77a0923d648d66e8a07c1540904fe735b2bece5fdad839c02a5d58dac56e5512fad7e6cc23208983fb2f0eab3ee1c4e42a805010001	\\xd0ee9bc5e612280d63b36478f28407c1c73117ceea05493b472385b1ccf5dea0f9aaa22c0e406eabe0aedd9d82da3a6ac9b1abc277a3ccf0a766d44fd9f04601	1690721915000000	1691326715000000	1754398715000000	1849006715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xe50dee477701aea37361f515bf4a7a3942b0de05551e9c986224f8c71aa425f52d83f2dca978009bd9abf3dce02bd4f3d08c48077c1777c584c3135bf16f6721	1	0	\\x000000010000000000800003b4ebce2ec397097a69f412a44b2c9c415bde1ce759efb1ab43a8e5d9c8af7a9c3b2adfda836851e97ed79aadab61fd145050e1893417e2ac51a78da479b38f5817162d946659638434cb1f5f987f10d1c0d1629b9a0b00ae64d08ba62b4ba48d3ea06b795ca036924efede56249884af9ecbf399e196a02695ef3c06a5fdd7a3010001	\\xd75763ef10176a63c0af72ea5e3628578589d1a4ddc6fb2725d868b37b432194fe26814239e749881273ae96e7c2fec458c365ad6ec10297e12651b261afb00c	1684676915000000	1685281715000000	1748353715000000	1842961715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\xe71d95059c806fb05f3c0c57d9836bd31eb7dfeaaf63939ffebb4c19345d8199a66791aceeb903eeb3cc762becc2d0a1bcaeea9cd264085950bdb0d2125f1afe	1	0	\\x000000010000000000800003aac312ce5fda04b5e6d7d3fb2d63fcca899b6752b931f17dad843b0f9a1e010d9212776763f4d5e6199479957d441385c7d11429da4a3dd877bb9d8067af8852e64c3aa29bdd5a6fe2e83a0511c676cfca15a83109eb86fc3e8d307b961ccaf067791f2d3df8ad36a66e248371aeb310d61aaa9b5f7b94fc527f66b2a0ea0f5b010001	\\xb5470190f753c5010443b860f11dc80a174ae01acde956c071938dfcec92a10fa66852393ebbfc8fee2a7d5401669ccd3156a611a1148b330df5fb1540a14b01	1678631915000000	1679236715000000	1742308715000000	1836916715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\xe8f9d489e1ca7e280244ec3656fedf72a487c233b99d69ecd7d730d692be3774e95136f9b4fbbb53e1d72538e64f70270fe6cee64327b66acbae4df32f4ee6cd	1	0	\\x000000010000000000800003b5214d330c63fcdf21258bf52fa119c33b9eb245797ba34ff76df298685ded9f715ee8332d322c0da52868a85c40b12d660ab48ad56e2bf6bedbaba2ad30c10e1c23f8e6987bf89a879a66af39df158216ed26e17178abeaf53aeb95c67fc31191fdce3951bd7a50323ed8135c65a5b23e2723b707e6cc3bc8f9a2948fe80f47010001	\\xb147f025d0551669d2fba578837c63df7784eb646daff024157ee796b886a0019fa6c7e91554e1f6ac2edfd0d73e6b71fbe6bab161daf144499148de83d8bf0b	1679840915000000	1680445715000000	1743517715000000	1838125715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xede92460180cf4e82cef5aea9abaf2422c328534b1e9f5368f2924e05bb784a25f9af02acf09daefdfc1fb94143450446a711c142f40e8734becd2e46daa1f1e	1	0	\\x000000010000000000800003f81ca866e7fcc41222fdfae15e8bd75389382ffc9282c09cfd2cf704b5f2e56212e24e8b39e17de67b51b1105917cb5675007a7e713000b5613f21bac0c45b83d02286d354d05f0acff0bf8e14db42fd3b3d67440eddf596ae0beb2c7ce72be5fe7962e43ea202c36207fe867af96a9723c91b9dcedc9a544d5abac6c269f1cf010001	\\x84e961d8bfcba2288ac6a8e7968abfee4f3803b009f62c646ce52d092cbe55ce6978ad1b25cb06f01007085737d8f549113ecae296cdf8a83c9b7837aff22806	1671982415000000	1672587215000000	1735659215000000	1830267215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\xee49a20f93e7fc5d978f370b7e7eb7c2e6bceeb7e0df09ec05c60faedf686d4ff0228143e18e498b48d6aee730bc3aeffbc3002b9e067f83066ce8a2f23b8eb8	1	0	\\x000000010000000000800003cb1665532392a1e1e006dc7927c79ad100b8752e26404afa556e69831f165b8b434fb115ce8426dd511c669d243173ee40879eaef2ca36f003ed059d06af8896c8965c97223f04927ea73d64bc2252c5f1215cd10927bd5283c8a3e35c43ebf0bb1cb0dd82f96d9b5a3d92533036e3da63ce84a84c1d70d595d886f8ceb2f60b010001	\\x1c12d3a639dfd3e44b5df614351fc89aeb7a89086aab4556fdfc34f79a41093a0028abfdb2c353c775803256bd0293c8f24ceb876d64a4c3bc3913871cf5b609	1681654415000000	1682259215000000	1745331215000000	1839939215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
218	\\xf08dd5818fd4a0370392a7094508fb9621cd4f6626b9f3888dae6653710d909cfc7f9633487f4ff972e0304ade8b423fd00a30340c7aad1cf1da15a0d83a8dce	1	0	\\x000000010000000000800003d99e38aabe39f3d23c2c9314488ab237b99081c81bffb50988418e056e8dab6a0a3a13e71f716c65d117d80d68195659d93f10bf12caf2f6aff54b39a62d51d92efe4ef72f55e542fd90d982771eb61c7949cf13c26992dac7bff5000bb9bffb99cbdd05c76e93b22a5ba58287ac59d8b12d19231b86779c3e6a89a7f72ddb9b010001	\\x93eafc726547201e02e42da177979fa32bd4126861ac38c269aa8c8bb566f36f0000dd6be178bf2ed1232f5591bb173ef0bb53d2526160671ddb28844fd43b01	1670168915000000	1670773715000000	1733845715000000	1828453715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\xf451681da853fe79b04fcc905e5556e61d6f5a211fad71c03fb2850f6691fc4d9934f99975220d36ec37984f6d7ad84687d3bdd9e4789373e7934b596654e7b9	1	0	\\x000000010000000000800003b59404c31f174630a287e78ea991a23e149aabaf1cff89435fe1fed6098d41f2a29ab7c0181ccd5f1065a9cd5b2a26886cc44cb6366b83193eebdfc804d052e963fba726d9d6e1474010bbe8436638b90cfd3d568c79bfde0a547553ec1b553f448263ddf32a14588b00d25421514df02799d9f15078ff1ffb00349b4aab6151010001	\\xddc2053f9521888f47f67afbb3bea22a93f1e18dbeda51d2bc42e3c4b3c5456d0607f55a07a756a3419a8faf08f7248761876cf0a61d6b9cdbac221652460105	1684676915000000	1685281715000000	1748353715000000	1842961715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\xf6953b6339254a0737aea46d777b0098ac6ba8d262a15cb5ab291c10cc3e730727b1bf66b44ec52be1e5a590ec9f80e1062e5a753b97b65cd238ded866a247fd	1	0	\\x000000010000000000800003b244e94135baef7f389b039cbf9a406c5f6c3a701920c890e265b4d0d8d829214684d905a8396a6f4dce040f57d7cbe198e1f68253194d1de38713487a60d08523794561064a4eda3e4b59f72d0ee7148b47f156a4e0bbcabb2ec912fa3a9c5b960fe62cffefe3932517ca5e8fbb10aa4befad7e3f975ee8bd6cef7bb96913cf010001	\\xbca7f0fb35015701bdc441a04480ac66e41990914ceb560f2a4c07999e509e14d0d684742d34eba02632dc8e070e3da506e0e967e4dd8bc0d5398cbb1763ef05	1688303915000000	1688908715000000	1751980715000000	1846588715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\xf8bd495d1924e7a33bb05660a19c9f0bf618c6e73f1c362660e30e8e636c92cd3170f628e1423d1d65974aef75d5400d4bcfeb03feb27ee5ef3c4a977b3c5b44	1	0	\\x000000010000000000800003d24e5ce91cb698d144c851e2aa62c2ca533e2c3d17fa10f271b6e8f733269ed50fed20dfec7c78c90d1086005a310f3c76573e629776539ff4dca75e815599ba58eb9b9e10acc1ccb0ed76eeb8ab1f0aed92dd45f83eea13416e5034e210b1c78dee88aaf2d885b43064c65d578d339ecd2b99b4bcb580b16f4a9c985ee7845b010001	\\xe206bd9c6e9ac677084ea57638e728c9d038c54543668b80706f5c80351848b71eb9466e907ea3ea15a3b2a9fa82280afba2e677126f4c8661bf15fe9f189109	1676818415000000	1677423215000000	1740495215000000	1835103215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\xfae5c9f6004f85dbfb9dbf8050a386383614250def9cf9f6395aac7640845ecf5a472eea3df8bb495d2ce8da33b8706b6455b078405ac3b183e5a08d60c8776b	1	0	\\x000000010000000000800003cc89b321ce03f77bd5bbac01219fb719a043b12df07bc695a0135289500a1df597d933aadea0fb270ab2e1b0bd1214f1547a3d64f4567f11b0bd0a69358e60137e2b853d2fd2caf993245f00882941341b9b27a4bd7a0d7ffa0149cfb6d8a2e815aed01dccbb955fa59e51609bb211b016cd21b3347fbd38978cecc170648ccf010001	\\x7c6fd158169dc71d14f69f2706f0299bf1f9c69937da3f044887a10da4977d7683349d74188df9bab7ca5554ad944b557571dbe85b5fa39369f646c6eb1fc802	1691930915000000	1692535715000000	1755607715000000	1850215715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\xfc259b2dc0fe00c73a068fa9c933aad0653d171019a6500e1ad17dab79a25caf117119947412eff7598168fda2ae26a26f50391b22ac0777af1aecb3b069eee8	1	0	\\x0000000100000000008000039cde6bae86357ebb52ae52239dace3bbd6ee1d322e71e1d120c504e9b9abdaf8776cbfbeec3ce21f23a7fa943d46bfe0fbc0c998346ade574fc3ec2e41a4b1dc9b7f516b4eed1efb1bcc60f4c8691ba68b3e1bb67c98fba3b1594d5beb8bce0d36567a13f6d691c0f86ae36111389570aabb9e2a151b3280d2445bc430478523010001	\\x111db394209e01c3ca6b217c750872dda48e1da298f60ca79c30d4b386bef39fa7f5309b279b10ef4f4b49ed3832a219f241f1a17aedff261604fc231b0db601	1682863415000000	1683468215000000	1746540215000000	1841148215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\xfd054631b2c756a7f520df3dfef07c8ca6bed15b895df9e1af7fd8c0a20eaa5a7aa3b58a2bf5de29974d02c257fb07b214f5ae82b5a835bc611c6e512d25a55b	1	0	\\x000000010000000000800003efe7d93aead368422c0b720d6efdc4d941c4fb1eb3e01cd38ac093522a0109e56814a3568201003ae70984b005e9fe0b7141de8c6e4c7666a99fa673aee11d95a330ea88cdf68996f6d410af2a7cd3feb688af852bc26f9454e6462efbab55ee28c7c35247a833eaed3f6f6c132936804d1fca449dee442648e0adf865bc0021010001	\\x25ebce3ae160fc766f9773475bf5c9c888d58f527952fb432b1b22e7a33aac2053275e9a4eedbe597ebbe61dcb350efaf1b7a6cf71c682266fe1e23c74ce3b05	1661705915000000	1662310715000000	1725382715000000	1819990715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x05dee24174f00f18c2aae61fb237bd8934b31b9e690305dbed440b447f04c94d889f6bc0f7288d712f99d664db79e38937d095415e7451d63152f616856ea283	1	0	\\x000000010000000000800003963271011c44bef7449532f7196cab1d581c777cbc8a53534cffefd0af3453af088b518896752da674c1406cbffbafd6c5881deef908f0884b7b4346e731c29775bb56b87c3c41e7864ac5a64b63e72d2e54a46406c83547c79bd6a46b2578333486ffbfa115ae882d41c27e91d1701848eae984800049ab85c15214a9ef5f39010001	\\x8c128f50db409bf99ef45c573c9652dc84c25ed845f339ce764bf09fe696f04a24ebed739f1bf3f4fb038456aa8090fb931263828e84fe5eb08cb9a42e515a07	1679840915000000	1680445715000000	1743517715000000	1838125715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\x05eed1f7b0088235f138d25da721ddab5feee84df3b227c627ccc2fad346847ab60709cca96f8937af4801eba4aef13d27ad2cbf32c339f6475e6ec9d626cd4b	1	0	\\x000000010000000000800003d7b7b431b54f5c67b87688f32360612bfc0acc36529c58ae79a0eada86c972f6c001e51018f4a8bd208b02d66995f6d850cbf289f592d25a41105d088e9d1d3f8069f24fe236c6f10d2b5a1e36b66c4611e738a43343c0f4bf0e0941e0255cd5e7ece7045edcc66200e2d7be688645960b954b5a434e7488aab9c99ba1a4a1cd010001	\\xc87b21c734fbc123a2b468c0caebfc79b82fc7708a3cdc2a2eff4c8f73b3d4108fdff0376e6b7fd25777f400d590248f66e49a69bbe3178865d2a00cbe50df07	1668959915000000	1669564715000000	1732636715000000	1827244715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x06c615acd0e7bfed23a76766cc6885bd5836b8ea9c72cf6d1cdc061a6283c598ce31bde7d324db5f7786ab1c13be4f7c51c9ca07bd6fe4dfdfdc621ef74318e2	1	0	\\x000000010000000000800003c508a6272caba61f4ef799cefcc9718ce3ee79d6a8c0b8943c1b4f8cd799a508870bbf0201eb14f3351cf3fdeee08292276ef173cd72f93743fbfca222af4f558d01df09b5c9976ad660a37734e5114416d8a6e13bea3c649b2a2a105a52aad7eb57a04da67bf9933cc7f3cb69fe5ff7e5fede234897ca5ff2d149e6af47c455010001	\\x93b3195ba4607c1e83a1fc8ab62d843b9a79f7df60d7b10ae12a67e48e9335f3eb13773487d919c57f717a925bbe8707015a4c0c5680134edb854f3f73429403	1668355415000000	1668960215000000	1732032215000000	1826640215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
228	\\x0746d657b96cf899902baff30727cbf9c8a17488411397a1297f3279339fe649c2592d0abcf80772ec79724a220baead7eb3bd84acdb311510e717887b5f2b62	1	0	\\x000000010000000000800003da05edbcc0972fcc163942a346bdaaafdfa63fafa0de40195d27fc22fc74e169b45f5bf5a83ed1507c2ca3a09eb126958ce65f5ccc55401dffefcd42883a45e6957fb1862f1db8a15ad6bfb0a3ef2c6aa2ac0d5c47259e3f5cc2a42d3a3f9259ec7e5b8a579aeba1e49e54871e3184a6d9fbe567928884129f597ec86c9a296f010001	\\x10862c0e016641f4252d44ca70b3d495517bd6f7b3f6c2882d97f23fdeb272b026fabaf6d5b9a82783cb9b288b4d0fbfbbf103b84d148150a2387ace188abe04	1668959915000000	1669564715000000	1732636715000000	1827244715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x0a7e3c7e1ccea4f02d99f47e97e2a360a31b824d2f3fbf4e1999ebbf0626caf3f77447d6b1281d467a5eda5fe69385b8d0b9c2477b5508b55c3c3adeb37c12a1	1	0	\\x000000010000000000800003dea7bed62dcdf3b812967d1ec136b3d91432cd429e1b10c2d35f5e4e0f540f8395aa8a3f5dcc8a5cc35c7450209f4d1f4383815f7f7e5f9af93ee3a7987b7b5c28da81d141e18d0e28bd79b33582244228ad4af4192e057751710f1e150d4ba11f984f951b4f9958cd7d33030b55ad3cfb89043493cfb40f0d528840bce55951010001	\\xd8564b507c4e7cd9ef63e6615fdc9f30a2829a643ab2f95d4c8ab639f42ff17409eb9359902feb0351846a09697dcb13d9210bf61f7fc7b8f335640b87d94906	1670168915000000	1670773715000000	1733845715000000	1828453715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x0ab666d1fd1924a3df65e13ab4e0dd535bd08d0dcdcd1b05a3f496ea76488ecb72564964ab8d64f62dd98c0d19574c1f51515e37b9c71bd32c18c4dc377f98d4	1	0	\\x000000010000000000800003bda27c838813bab6426ea9a4786035eaef47bdebdc1db772a540f373ffea2af2d4c5066ac604943f4e52d7444d06376e5ed72da0b9d394e990a7dc72ed797e283bd467156f21964d1e7defca67116e4abb7db37c884e8be028827ee632446e54832aa569aaa81fce390bed698e788b1e35ca50577ac487689f811beba9753413010001	\\x6d55425a7fc7dbf4e0159cd8c60841c81ca49cf90dbb5753c993889e068bc2dc2d000c5d2f82108e32f4bb0453c6596a1c32c2f68422148e0c40fc93c8965c0c	1666541915000000	1667146715000000	1730218715000000	1824826715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x0bfece3a287de30f30e7d3d705221d1f05884491c3ae34da953b1e12fcd15b69eaaa4c0bdf5717f99c528594294c6fdd5edcc3b4ff8199aa933be0cd9039c4de	1	0	\\x000000010000000000800003bb16fd80fab6f87d971c06dfb30211f37a141945c6202a70b41af37a7379dff800bca87741f36aad00b89f6e1338f567c213cf5aa0747f4d3ddd5b11acaa5e043dcabaa6402fe027db63a776849c806ecf344926acd419605aaf791276e3cae0ff6beefc31e6c7e605ebfc57f77847c60dce66e8af630a41f496bed95be9367b010001	\\x1fd951055722731c8af7d1924a55e6827c1e00ddeb6b507d8da207e41f6390d269b8623ff57eeaea2e8c8af4d25a3c7f77242267d5c0f9376c402bab9246eb0d	1671377915000000	1671982715000000	1735054715000000	1829662715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x15f24faa9e4d20f7bbf8352830c03a092f0c81a3b1e9e32a26dc370b30ec9db4901c5bfe01efdc51eafa2d40de59a470b8b2c98995abd46b828e88b8a0ba1311	1	0	\\x000000010000000000800003b07b4ff60781dff5fe90fc6faffd031a5382648ae71eaf40ee9d643922f8a0781c3d6bf11f8fb1c48c0ec4bdb5c0b7a8f0b859898d33cbdf7e761b7e0ee8fd597178ce4bd493dbbd149a2f1ca54510cd01bac9688ba2ef07204375ebc15c0d7b09f74e2500695babbac7a17a5097cbc9a0f9fb7afb69182a45a3909515c4f589010001	\\xea2eb2aeb2704e257c175ba65c6af2edb3a78165692040f4a4cbc2b433f7ee85227fc666ce379c98cce2ae94f7fc0514c2ed4afe119b781d0e2346e5299de002	1673795915000000	1674400715000000	1737472715000000	1832080715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
233	\\x17aa32542af09080d2c2040ad2efb53861a8b1700d39f2b305a5450bc3d5b2c8191e6814758be34b2772b0abb80269d0fbc02febc84f7f2db7b7d3816be1eada	1	0	\\x000000010000000000800003a05539e1b61e092478ac8d251bc2fdc27d734f676496a95404a3739b31efc4ddefc880d76a3af5f935212c752375363f324829112f07591d5cb8200261248a19480901fb793bfdbfd675d1974e645ea1dedf694148620c38bfdec0b99e76cc39b9435be9d7a7515e572fdade9aab5a2a9de18eca00d81da7ff4af6ce9f63a561010001	\\xf95b2dd54b2d50d765121576d7e99c9b2b70c6ba64142d43383f6da3f6e1d4db40721950b8e428d7533c083e2878e140bc41bd0b1da6cf99c1a65cc59758b702	1680445415000000	1681050215000000	1744122215000000	1838730215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x17f69241f762e15a8abfe74fd3ea6c496a24d4d126c49a17a643bbc6c4e666002db7eac84be9da162e0e4c12dd9d02f7556f2e55bd1668bf7efa4d395b80f6a4	1	0	\\x000000010000000000800003c1f9372ec3d12c531f1274d7993f4e9ee510184933b51be2d514f355c40b82b7b504f12ad44c5f01b4401ed828b9b54fdb7284ef5e189b9d455b03ab050c8f128394eb3b40d7ddd4ca97cedf0564cc93bc95a895bff23c706d6c0920ded88c8a6ebc44f23f683e53a0faef54689952cac5eab984a47457f00dad501484d462c7010001	\\xcbc78a3886168d63c4f5f430ee1b60ae83618274385a36bfbe568b6ddb5e766ad490b1a1a93c37df450608c44f79f92bf06818f3f6e7379343c73f5dd7a01400	1678027415000000	1678632215000000	1741704215000000	1836312215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x178a76f6b8e092edd8d5f247c264c52fd5838fa5fdd3917e296f208620a9112376d72a5891cfbf6ac930f116035c03d230845fbc350053a9f95dec215a40f615	1	0	\\x0000000100000000008000039610ae6e9d23773499a0b4eee78a6fe3304839a280f21ed03b29017545192049dc6b900ffb2bd49acd4eca6b2772f64d09ca89627af921181ba2d82f590a88fafb13ae7583dc18728d146bb9f7a94af55dddf13434f21029cabd7cdd464b0b73c4891b9a2c6a07e07fb60a6fe6ebd99cc6956cb1ef827dee2557c70126d0bb11010001	\\xfe119a57af44c5ab2e8cdf2c1e62c82ff2649dd383b114a66b63d2aeca7ebc56dce08ff406caa65e00e3bbfa3147b432d96f5d3569ef33c3eb7fc0b0fb42fd01	1687699415000000	1688304215000000	1751376215000000	1845984215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x1942841050d28f50b5b8409b1341163fe8d7a69776fd593f0ab5238af6522ecc32f3440f88a124a02efc9649a900141a3ea79535abd4e1b5a95dfaf9062ecccb	1	0	\\x000000010000000000800003d36076ebffb535b82f57c0aefc77430f13631736d4eca82fec774500c282aae3149164c60aa283237911a6658c383d675cbb338ffe90de81c79a2cd0a79f352f7d4e452d45088b013e0f8773c50f8eed68f469099f673fb376234c5bcbe69f3283de266ae94b41658d17f5a00fbfad9fa79ee50af5b44d6d23c7a4c129905d07010001	\\x00791e5520cece9b8a0cb4d9f1f3fc7d52fc6a0d3de8356e9aa195c5426aa8bef1955dbfb3c606637cbb6f2283476658e8f2163725f4cde863382ce9873bb200	1691930915000000	1692535715000000	1755607715000000	1850215715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
237	\\x19fe8d9c74775657539bdd28f0e532eb52bb481c7958ad94fa429ed90e260f550fc4246dc7c3798343873b66545420485032a01af299885f85977756f6bb7333	1	0	\\x000000010000000000800003c62daa720ee9c90c4278c3794a56f7908c06c380eda99c44350c15fbf11df0508cb8f27b4c66cab11700f1ca7753c4f22ebcfdd27aea5508d220d179eea638c003d2a14f0e755528348de5a5eb37acba8080f2f9fa12614a388be21a01996ed2281ff973f8a98a67b121d619e19423225e93dd51a214a4ab46e95906f47f997b010001	\\x15633805d88c00cc3710fd5b6ce060efd343345e5b6ee9e8dc625a2a6f7f701c00f1c6dac03f08554a4a1f2ebb75a855613febc41c7969db4b872b2ca5af7b01	1670168915000000	1670773715000000	1733845715000000	1828453715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
238	\\x1b2290c0e8f2478d1f8c69f4dbde830649b3c09ef5b4e7032aec0e4acbb60995bf4cfd96e404e50028be6197aa58ff6d29f7f31452a185ec42515e0543833881	1	0	\\x000000010000000000800003a2d00816f8fed0dc60e74fd29abbd655b454f48bdd73f902915e9226a648087329a378c666bf1676a4743f9da6ca7335e199f711f164701fc714235ecd1d155d2cc625be6ab9a8b3b06e67659cb16e282171b9d397abf1c26ada1d76b0434ee4a1edcd811525cd5e57c282d891f445099ec0b625f4afd9af1f9ce94572ccea09010001	\\x2bc2a5f8e09a645b5e12aadf57b990ce8a753bacbd62965023503a57b65fd7354dbde78cec61d1b8179eccb58e2f440704194589723df72d8d1c067df14d8a08	1671982415000000	1672587215000000	1735659215000000	1830267215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x1c1628143c36c10ce4da5f50e4099dac32247dc2fc1c3d3ee8043d2db31cc28f9c526784454abc2848ba2913aa684f235cc7396b9285c835fcf1d1ad6fdbf67a	1	0	\\x000000010000000000800003c60ed8684cc0e3b58a83ddf1c93826f8c6ad388c21c3ff7a94a8863551d33f49ae91976db25b66469963fa3f98532e99ae0bc7288b0377f1e71d267baa08739c97420be2e27b8c8f30ed118fcd108674c435a160119d1cd055183d233496e9ccc49aa631a6fd2d1c497ec5add84bb8fe8e9c22a0dbbc1dbd02a255db01d8d557010001	\\x7488374d06c995e58aa1c4cd10b42f28b1214e1b53cc7e38a284931a1b77ceb7e121753430fe63cc482cf5856c7d191767e80d4843d83df2eb5715c946027e0f	1676818415000000	1677423215000000	1740495215000000	1835103215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
240	\\x1fb281fb621c4ca7c0161ada8abbbe4385eab3095f9453f0ec88e0c1a647344b8e926b12731d44812519140abf8b2d3563f7dc906efc97b116a03e61f90ba8af	1	0	\\x000000010000000000800003e5e1e18811f4987adbd8d74973bdc9874224d9cd4fa425cbcdc0877046423864f3d680054ddda6603ea11aa95c85fe679f61169189fad6648366db539cda19c6607c0c7d2acb16daa4bcb3c2d11dab2376a14edc3a3240cc69a3f6f8e6aa244e1ca7da14c2019bb72730897a4c08ade683ca0ba19809da0b07e1e2a65b61b89d010001	\\x3fb997e93f64129dd12a53d5be17facd88f8a728938680dfc940410f29f91f4e23690cbb34c57631ac2fbfe22d556e775476be97a8799c04ac9de750219d900c	1678027415000000	1678632215000000	1741704215000000	1836312215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x212a7aadbbaaec03f11759a187c866b54cce0777cd5b6bff8574e860f7772ace1cd6fca4745edb867fa8f5734863dd1920f0034e54d7e703334ff1f527404e83	1	0	\\x000000010000000000800003d60e74c35e59b27de517baebc003b2487fb768019d2d489125c2563bed1903bab319ef546a19d98fe40f7bdd12382fde4779585504522a4a650496fd8766d5ac1d5aaab41ef0bef7e5c242a1acdaaa38f587cc42caf3696406214804cea095d01e9f79fa60d5e77400f84d61373358c7bd836df29049cb46eeff89bd78e82657010001	\\x56912c296e39c39b5aac3c3e631af2c0b5b20ac58bda40c1df0416f39f689e646c8600ce779eab81e140a37cf5d3c15c0a59449e86902c9aec059422ab58590c	1674400415000000	1675005215000000	1738077215000000	1832685215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x217a8d94e50b90d240c50d9da60fbcdca0899b330bc047afce33df6ce517155f9787f4b2e041619559de9f1546a949e2e9d6616cd3868181966b079ab876d00d	1	0	\\x000000010000000000800003b5ba9cfa9f40cc85380dd5dda18594d732202abe8875be69a63184d09aab92eb4b34c9bd74d008ffc7fdb9c32fc607702dd65850063732243a231c0d3e3c81f97cc3051f408a60d6bb07a9de3d2c46d234c9e654eef9312014eadec9198c57357bd11d90da0af1643ee4cacba9661bcf065d1d10d9adb82d18ba5a4a730d9ba9010001	\\x08822847b5cfe0ed7cc17cadd3703851e7a54ca49062fc913fa43f696a1fe1cc910aed32b3aa603c6a87c8e9433b437e576b29c7ea3d5d663f8c57ea05ddf500	1676818415000000	1677423215000000	1740495215000000	1835103215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x29325e798e1ca8c07f29bb110e7b60d900b2710d81acbb34f79e5b3cd5ee228b8e584c52eddfbc1971ab9e5d6001928477650dddc15bc39b167cfd08d65a2881	1	0	\\x000000010000000000800003a7b099fd8437a08e2054f698839558d577aadbf9118a410df9284a47bc950e02f67e1e304786bf29b0565e630d47b39829d359178284fdc40a3dae053d696ff5853aad2e3fc079ea2c1f2b11c5daf58520df7031ec51376e93283a094ca0e67830f5f7ff1bec44aa9c11f1aa1fde26ea916e00d5bf4c60d8739955bc01308199010001	\\xc12514470f0dbe0c49d9ada1727e87ccb046caedb773a359883ddd1062a02575c187672dd884f9ed592351d3456a45e7a3e49c5d4b8ed28a1c3ed31118f66103	1671377915000000	1671982715000000	1735054715000000	1829662715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x2b66cde27a0ff639ee463e29bbdf43f5af6a5089cc93f522a76963bf124168e4e3e85816624b78b9920ee79263ff67ba062b7f0e52dce83f2c143d57321a2eff	1	0	\\x000000010000000000800003c75c5ea5084c03792682c85a9a5263180bb432e4d8dec1331e471a051e1a4d04f0029142b8e4919b3de8fe50c4bf2e52866c40c28f87b1c336ca9bb2007eb861a167c5a767f7278f4f10f1053a679d60eb0933a049f1f21fc765c71faed2acc31d7c9bfe6ba2d3edbbc3f560c4ab39ed9cd26eb1e7ec492a3223614e18b64429010001	\\xcffce8f571bb243765426b65d0e3137d0ccc948f34ce19083781e5471b5e0ba1634a3be14ca3561398f01d0977a29bc5fce51d17dd1ed58b289fd0f68d29c604	1675004915000000	1675609715000000	1738681715000000	1833289715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x2ce6c826af9a8d9e6fd9c8ff31b936052b0a75836b23814624e0de8d28e3b326772c5e738c0bad2c5be6704139fa65fc1cea91881c76d8b68a9b3802e1587dee	1	0	\\x000000010000000000800003b48a64fb3a1078b5c1c0919039178d2bb1bb3d00062c6f774810f306becf4e574ed1b2ae8df96a42bcb757e612a943ac82fd88c03bcb8113df4719965a809252f19892af82710b431af19de1e9e28f3315fa3a982c4412d8b15912818982f6959da2f9e2c43af00f5b4a88758299ec6509b861ff74b8f298777f0a43667e8837010001	\\xfc98fe03d4a126c874d46cbb2103371823be382d3cbc418b745d8beeaaf2839f6f721c67cfc9315543c2376754d03b0946bea7f1f1f3b1c6b072b10df9f2dc0d	1673191415000000	1673796215000000	1736868215000000	1831476215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
246	\\x2e4a2398c8c250f24e7f2084e5caa2e210c97875004817e3ceeaa071fc47cb91164d14b0eba61237b6936f229edd3bbbb6d4f4aa53bab2e80abc46fc34067e36	1	0	\\x000000010000000000800003b0fbd08fd7a89716508a5310016f545d7f688e9e415b6da686945521efab4d5995494cce5e5622262fcdaf023d60d113024f22abd8f5f6f6bae9333c1ce3ab33f41ecef122f08430f5644cd8bd0010c320bf5a9b0feae10324f4ed54c6eb6419fd95ca878a0ed422b62c8b69f90d4235200ef51e62562d51d1a490fb2869e661010001	\\xadc1b3cfeb34c872ea9bc183c10315716dc42cac8ad983518deb55f1e51b0a93210bd88013e737ab5165e43ce534b0d6680c01fe05e05518939c0f3796feff0a	1661101415000000	1661706215000000	1724778215000000	1819386215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x2e261ad6a9471de8113e13df1fe593c0d0711cce30f6068c76c38e6d68540a4a37101423670ec9f5f2c372d15fe680d6cb5c3269f22ae595e2c45c29eb33a948	1	0	\\x000000010000000000800003da3b0991a02cf767af22a40dbe9eef75ad01a3b714ca2e10281c717a739bd64b05a4768694f067c153dc224c492ed5aeccbc3a99a5789df5e626ae3ae263867e5690fd6a78968b4a0273c28e6a301174856073344afc850cabc36b222098942d1c3c7992022943a8de85797f49c717d5f3c99d115bf4bed39f44ad7175e15759010001	\\x650db9b4d30ec7f94d690e60c5fabc340dd4552a7eb133d279bffd53703fe922da4f76fd02c4a2b578911d9af484b03327c861c874a03cb6d9b0eec50622b809	1684072415000000	1684677215000000	1747749215000000	1842357215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x33deed07dff0d6da6f161c177d88ff7545a73670e7d49c419f846f2ce5fcbff449ecd64a8aed910c329c5042b94418702ceb4216515659676ed16769b424c719	1	0	\\x000000010000000000800003bff9186fbdf88d7a8a1c9cf28d5746e9f258fda87833e60db41e5138bb5e93fc7c4f7e5eacd8ae0dca115ea3ef4dc59bd3e7c2e6b54101c1b8cf5fe70d577c29734c22f6117102a414ac3f12603317188b06d4e0a9097ff2ec0dbe79a2c99b2f0a2cb1d2c375e3afe3466799b18978c537386493f681a8669d932570443a9611010001	\\xa7ffdb2f4ceea3430da3e2acdcda2616876a40060e2fa04bade6760123f101feeefb71cfb964ec3459a3fcbe1ba0bf5ec4efd79190b17514d522572bfd242b00	1682863415000000	1683468215000000	1746540215000000	1841148215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x36ea3140039b607bc2def53b199836d67f42fac40d26cef19e52566319a791160619bc7a9c9e8f319278ad2869fda0d6bc171ed4843881a3ed118eeb7304799b	1	0	\\x000000010000000000800003c02e1cef18263cbbef585a17ed5a1e33f49edae0363db970b3c3882f16c1f930d583c3a9782b94fc5aa226a5e038d5786bfe50c7cc96fedafdc79e7fc9765c28e60df17e94c2b1317743e4bb1984a67abb2211f3bfc10cfa781a131fe62b39765c96101f42c636f76d07bda103517eeb009394b66587b4f25c58c94091a92c09010001	\\xa0091eea3be557beb68acef4e23232ee69d1ab5ad72db5811545fee57c44d4d2d3c31ca2d685a38ca3a7e405240ad93aca7aca357215bac355ba5d828edffd0c	1689512915000000	1690117715000000	1753189715000000	1847797715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
250	\\x37bebcb1a1df97ae6ecf05512def23f4526200c2cdf94e469c38f7f8e0fa6af2d6043c132a2e8bbb6d655f0c2d9d82553f25b9607f15a404c485ee0bf8bf8919	1	0	\\x000000010000000000800003b4e1ce845895be2e2cf5d62df78601338bffaf1cc9b3c56c06f122f543a7dbd1eb7081daff812851dc605c535ba00a16048a1643a17a568e9aef33ce1225350e430c6a8a89ec4e7de8a0c4b9343a666291fa0cceab2a621b702b6836f2ea63b4a0373529be68f7b7be009374d8b0a755c9b213fa3616a06c9b39094548ec0edb010001	\\xbdcab1d8b067e51e8e557fa150801edc066a12737afc373fffb8d7b1fa15cf83bd3462bbbc15ee61d018fd3f69817792ebd93251cea043dbb2c9ff974489aa06	1687699415000000	1688304215000000	1751376215000000	1845984215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
251	\\x39e21787bd4cec2b346bb617722d372978f9a1d0ce8d5b7c8bb545df3be12dcd933a7c4b17f38f0512cfa5214a65533cc17b0d653bf534bf506486227fcf720a	1	0	\\x000000010000000000800003e6e193239e69a0f79ee3c5e6b991ddf1a5cd30677ccf40e3e09981ee737a67518f059a5a8cb1efff91d490a1bef0804a8614fe35e40a1493e9342b31d838c2445821972b789f2c37f025f0283bb96917ce1ff6ccb5a53354b2681ab3b142e0ceeeba09a6c8eaabce58d27cf627e457f8f24226cdda5ef120a90a1e6dbaf4a843010001	\\xf6eb5962a7b181d5ab611c8b22dffe81c998fc87a77653af030e47292a4ad7f6ee5177d67cad0c6f4a01a3088a32408ae1121356a8fa94764d8c182411b9c80f	1668355415000000	1668960215000000	1732032215000000	1826640215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
252	\\x3d0a6c23a6b76bd8b5a227e0937494291922882453d61676d6c86e2949c3f8f6642b97a4322d633c29998084f839145f94d18509e688434675dfc2a9821f49d1	1	0	\\x000000010000000000800003bb66a1119ca3f4bffab760314e2e43e5a4a7905b333c81a146f6074a13910e3b43d33f886ea771ff700b0b71fc58705bf3341efddf2bbaa88cb61f2e748fc0af5999d344edef9ad64fbb269164a1a9854432e699e1b8fb8f71ff84c59281b733e86bcbbe19f84c36702e475149d94d05daa5dc141b5fac67eb6f9005e8255149010001	\\x82213249b2d2d34a1fb9f9a605400e9ce9af8c283645e65122ed18078612d5c1b37a5e3f25c691b4b9222603adb76d7b1d2119073a4e1f1362e6846f3a5dd300	1670168915000000	1670773715000000	1733845715000000	1828453715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
253	\\x3f36129b1a3ee6b44e169793ef2a502eb80050797114e90cd0d258b2e3e6e46be9676a69ae426afe53fc733792fce820ed2cd5f116ddc68618bdcfe4ddcf64d4	1	0	\\x000000010000000000800003d661519c675c79011353215f0c266d589afb58c90cd6cce0dea8450a66ec0fa6674cd86efdf160e80c9a76f2fe5a8beb95c50461cb30a28d8cd58b540bcd849d278562150fba92ce5a202598fe0f49780e67542867e87ce31a56b471c74b792d06c7d333cd1f4f7b6c9e23b290a01087b82c4c5cdc831341525a58368c3f2575010001	\\x85a9b78e7dcbe06ab4d722791f395f53a00cd2665e58e857a3bbfa31b1cd20a557f93fdad76033553cbd425cf897f5606cd3e1538713fc17c4d87cda8dcbea0a	1690721915000000	1691326715000000	1754398715000000	1849006715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
254	\\x3fc6a127018d01f16ef185f08b49565e531c85c23ff71eeb78eb26cee59af75ede65e5ee24246825282249fccf0499212ebcf1939cfc886785d76b492b1ff178	1	0	\\x000000010000000000800003b44583973955e7ef319d98ae155fef4b5aa7c0b543770e1bf613466033c8e4a3d0e8990b0432101753b0e0ec131a7c797621cf01c621fd11bfa030859b1f8768c5ceefb148a95c9fd9c74841ac65b5671df30b821c1216bbf9b3a999d13065110db6d188805771a30ea69658e5170312006db78c7b69888a63c287fa078e5e93010001	\\x084fbe2fd2016fd025515e39b6a4b2fc74c210e773f331a4e96b56131c7bf4368deadfa91ba53c6e3a40994403b530980bd546b0f986827bb78f4f2819e75c00	1682258915000000	1682863715000000	1745935715000000	1840543715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x40d2b7e7eed894ec736f0987a379b3e2fbdb5ae6de0160f8df31908bfacd89eb1dc417c032163899b5f0e34a10ac05d549e5269d3c8e9bfe4ce4d46e9c3dbad7	1	0	\\x000000010000000000800003bf72c89b6ad54f5f18994fcf6f756a25213945d9626c014065b9f1e25df81f6cbc463520b4c1bff9c90271964531814e26cab77985657be5b0882bdf129a8b76e66231e5922ef0608e258064c9d236994386564895847a080358da727e75d3e190712769032ced31af75398ff5454cd18c731f2196dc631c9ee8100b20040fe1010001	\\x030ad1ad527a9f1b7c0df8898e217d19ffd9da6c96cf4eee8272f2b95b237d4c660deaddb42badb93d6ce49f7cbadd17670d3b842318840b1af7a9d829ad7206	1687699415000000	1688304215000000	1751376215000000	1845984215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
256	\\x4266f81f8a35c31d7f77317c18d968bee5b06dc236809608aa3d5e736176def2a26250e398ab82aa4b1bff367f8640189452998117751aba3b01b6e0e646c7e0	1	0	\\x000000010000000000800003b80d6b20c5b2bfb264c1aaafa9e1b783e732d6bbc278a279e02fe058abf20ecfa0061d7e0cd7e5ed98bc2ad8c2566d0d38212043a18a00094edee15c2b2ee198951786d1d2082e590d487adb8a643572500b1596836cec02852728287c87bfb4e3e9ee6692726244b26dda8efe58bffdcc757ed2a08d1f5990fe7025119943f7010001	\\x6db2268cc73a3e86485656470df964e4eea0512e50d07cbeb76cb21c0b9b0a593a57091f36f6c71aad4bb96aaff2f48259217a04d7c74b607a576972c9a7ef0e	1677422915000000	1678027715000000	1741099715000000	1835707715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x42a2ff5d857a1297d71f535c9212bde0f47e118b1be53fb75b1d11885e4e6d564a28e6550aac55e9986a349b3b597c90bcac63d66f03c8dcfdab7aabc4c38905	1	0	\\x000000010000000000800003e0ad3b9846b5c764d6e809f906c340d075bc3ac84761cc3c27e8926a0e0e1e0390706412b5e1becead27dd6b90ce4d585fb9760d8e2256351bf469e11796a7bfcc45eca8be5a6a69d61cf135bb79d42f9fd7c0a1e782eb95141439653ec43f788b081d86797c8f48521700e38b416224facead90a4404a679060a5e0b9a59385010001	\\x9f497c0588a0fee37519cd31f843b624fe50aa846f1d1c1c8792dc78d31252df6ec8f7a68e1dc1219a54b8087b0795945a8130d51c05b612d17e0b164c8ea90a	1662914915000000	1663519715000000	1726591715000000	1821199715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x474ade4cebbc77cb4463fcc70f95a9a212e77c42a088df6a049d4c4f5d3f039913fe4ab7121a230547838a2af535d387a74fc628d5a8ae0dab8397bd6282fd44	1	0	\\x000000010000000000800003f05efb66ed560fe062bef1e214f3220516323d15f4abb03885bf58589f7c03d3ff6f39c1596b86e1f39141af43f07a21d500f96d577082d1a82d0bf7c2c03585dd8c79920d6f512365b7bd1f02142feaf28a9123b158172fe8d8de1b532f4d74e7a00f2eb6d933c87e4ce929cc584df4ba99513ecdc9652904ef16143dc96993010001	\\x5435fe9578605ed8d78179d698451b3bb5fe0a007ecadf616546ad7da95d4f3a9491d43739a266e7acd9638cd3ba832699a32a4e002a086c284fb2dc3afea706	1663519415000000	1664124215000000	1727196215000000	1821804215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
259	\\x497e29e17f8d350de2e571565adb522e1495ba67fe8d3d06e29809b3de545d19068476d60ee8f3f842631634bee3ea47e411fccd2bb756d17f58e5207ae4e2fa	1	0	\\x000000010000000000800003d590b0c003f758395d1c7a6f402017cc8b06562fb72ce911517f333ed001f9a4e1d9f582cf5bd98bf6eb590cf653b91f33e1e357330aee6bcbe92f306bb9ae689a6145d4014aa43f1d14bb882bf640c314ba41311150528dd3ac264167fe12f3b99b58a5f2f58741d7a645bc3548e45b789509634fce0eb106cfc217c8ad50a7010001	\\xcde2146494b8cd91d2c48b4984c034f6c3b2959efea8b7eca3e4c9079b291fa4d9e332ddc71faafa128f3da87618c45842bc6d091c175b4b1ec107c303959305	1661101415000000	1661706215000000	1724778215000000	1819386215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x55fe4b0c5e541dffde3b03bf42f7a6f572228faca092665d39218ea423502477326e41c0fb61b07a96abed8f38e55fcc8464776074af57319c8bbff9559ed266	1	0	\\x000000010000000000800003ca7f2bb4daa0323b860fff148ab5860a990d1a55593ea8c174306509dca6c1eece7de77a81448291b1636de61152cf6375d3e2aa39c59ec6d7130b46afe954b35ca71ce13acbf0661fb3f30498252915282a828b548811b24f4af60b2a4cdfb773ee25bc95b4da20118a5d6168dfe299aa6197f07eab1f0b3dc78768735fdfd1010001	\\x86af37d1b9d1cf109bf35b541a193ed984318ae065bb90bffdbcbb261992e19cfff11dacdfbcfb1a59e870bbbdec67ea39e04113bb892fcf80e995834b0b9000	1688908415000000	1689513215000000	1752585215000000	1847193215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x55fe469df9cf81ebfa34b9b60852b7a5ded282c26e3b0d6cb999ff1d7b2f86b7849f79bcb153c7700488c8ae734edd8b98405bdd760a01fca9417829d4ce9b0f	1	0	\\x000000010000000000800003e69d52ecfbe303c7b6d8853b1d9b18030ca83439b69f44fb5a779792ba8f502d23c48dae9148fabf0d29da99efad5ff50abf147379ee3f404452c03b759111d6706fcde0351fedbc5f101c91e59617da17863b0e4358d667495cdaee4f69cbf67a279bccf0fe6429e081b22b81d6895c0d6a457fe6287e6a3bca54bfa8d13621010001	\\x755b9850fbbea449ff16c0cfc0e63fdef5ead9dbe9319cc4652e20e1e592a0480a35731b0a92d5ed6f66dd2a559797c7ab2f72fce49c5b3dcdfd3abb5b1bb007	1677422915000000	1678027715000000	1741099715000000	1835707715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x5836f40849e1ea7875b451d7698610310bb19e43d6f7aea524dfed5a20b3ac56ed72a07a65d19d89df2ba7df8a442e910b0916311dff71b0e922e108e611ef43	1	0	\\x000000010000000000800003b4b647b3c0c2aa307d109253e3f9be6f24a3c0de4a9d664aacd4bd2a0c557dda62e0208747f9ee130c0afd4db8b47e6afa3a1393a77c517a629a1736ac54022599229bddfc225168b76a9008cfe94bc401e120a37f6d123cd3e425d0e0263b105d68e12ad4e21792e393131cc4440fcb6d499a5b55f714e381f1898d8f00f83b010001	\\xe21d8198f4a6bdd534851a05ab6b316bbd8f59012f37bd175b6210fe1990491aca2d112fbfba2df58c9894646eefdfd459e94aa0f739f07b822c2cb918e4a200	1673191415000000	1673796215000000	1736868215000000	1831476215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x5a9e6ca6640466a86a039ec1b76c10e6e8f7c45f9d44ba100abbf3714745e8c5dfda2870100437d63dfcacebca6003891eb6be9b8ed1359771ea3858f682da84	1	0	\\x000000010000000000800003ce1a8ae304d044901a9e72d00266aa3383da5dc09ca077ed5477bb88ceca41e54a107f1d86a915c9110c0472bd5f3407dcbe1c095bab6297c0b261b22c13c72d5b72a581ce03cdf2ea4bc08b758a312fabece681aab79e06329ca72852a962dc23ebbbc7d102c546c9211a3e85f93a65fe7a18cd36f41a5928943731ef35cc2b010001	\\xa62e738bd19b89bebb796f94b9ccd15a480f9380bc2611c3b5597ccab4bd53a622721cafdc38ad1fd0994901adf90c2f44494404c5e72d2960f5b7abfe79d00d	1681049915000000	1681654715000000	1744726715000000	1839334715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x5a1ef369a04328065e779e32be2bf6493ced39095e957cf31b718e9e1387e22035599ea4f264f5fa88a241483f56d7fe0c867ee1bf2b577b108e4d7d32a42887	1	0	\\x000000010000000000800003ae65c96a15d633cc8a2f419728dd5ff4cb8690fea804ac1135877db0eed083943154c919528cd98efcc53b89b849743e268efc5c25614c15303ec4501f1a87e1c439e369992e8930001157d53b3bf06adaf80512e049028e6d30640a45698562f4e8ffb575c8ddddd2def28fe977297a9c2eec9c3c1851f40e19bb8a347ec583010001	\\xdf26bd81692d4c73217467001d29143cbe6bed2778216f36539d70617b261b5732d58f9826578f8c2ab044498d8bce17518cd47ef186af9f09f570821cd3fb05	1676213915000000	1676818715000000	1739890715000000	1834498715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x5d42a8ac907af65b4f23bbcfe4a1ab629b81c16f16f12ae435b73cec8c150c21deadc47cd20cbd4f8fc57c5d428c1a76996469bae84e3c6de12cd7df25ad5ee3	1	0	\\x000000010000000000800003b9766e4be2e13446146914fa4cc5570585afcf8962bfbbd425bdc13996f2501625f0cffb1f2fdf67e4478ded0e51ecfe347337486b8edeed368ce294a6adbd9329c3965d37816edcb7206449c426903a9d3d575878ce04aaf43d18a0a1ef84587f09c5a8c9a3c6afcdb47b2f4f5ffda7b0eb04a63bc4728f5f08ef41dc5563a9010001	\\x9959b89a2ea7dffa4a0cd4b63811a0768f40e17fbd00d85b9b5f3acdf03c3163228962ae0717c27aba0f33fc45fdf8763b0b0c51db3660aedaf894ab9bb87609	1668355415000000	1668960215000000	1732032215000000	1826640215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x630aae570c08c72211027cdff98ad2f026c94078386e15fd06dbeaaf2beff208698ffaac3f46ea60e89bfc9232541b5deb7eddf95b5763dc29a1526407f0ee64	1	0	\\x000000010000000000800003eddaeee81b95e043ae5cb996a56499e226f67de9c9c664106dea49f7a0320f02130281198b8646ea5fbbdbdcd71b9bfe2cb738a7f7c180c17cd80610b28be8b128209403b6b06dd30ae33ee6d73df7b3fd2249f379cb045e10f1a47c24f87bd374f4a1d75320335c441d830d0f7cc518ba899576c54214cdcace89222b8ba155010001	\\xf47c9f1b92cf9f0873603c2ab98365e987ff4b598567ced420290123aff208625518272f48f7cfefa8bda8b72a8d3fe2742f462f2e158a0f3336f513aa0c1506	1687699415000000	1688304215000000	1751376215000000	1845984215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
267	\\x6a5a3b96f67617f55164ac1db3b4fd5c3ce3eb875594ab897496db526d89f1224ca0461a6b36ceb2b76f492f37ad9485a8504c7b90642f27f7e3bdf99abefe04	1	0	\\x000000010000000000800003b0a7f01245471f206881450aaabf3db2586e6d3e865b29cad0a56d3e4120b72a1a77e9b241f9ea446a5c6e53b3069b36ef65df7eb67e64988e80cc5ed867da2e0a37a85f2bad8b1d066c79184c3293ce93818e03825116940c9db7133c434e64eef60fe69603259816a0ee8a274897d83683a8dfe56a2537d183f8cc7cd22d11010001	\\xe1dfaaa899fd5bca10eaadc3df8ec48b2482388fc811abb142fbdcbe08764128e996f326e9ed13f39b68a5cf6e84afab6c292cd342beed6fde2d0aa6ba83a30c	1682863415000000	1683468215000000	1746540215000000	1841148215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
268	\\x6b7a24783e31fc38a5e48b18d807390ad39e3bbf000af6a6bc8f4637e5e80c81e786bfa975e7bc590aa15f67c1463685d56b0d7b78e90adfe4ad044fc9c37485	1	0	\\x000000010000000000800003b0545c8fca5c70f352772a762307d7cc722910ddef8a74d0f8520ad16f4d628c0b7f30cd34f1d045d5b4a95d44978e0f6a93ab36bbc1fdf5467347639aae4e4b2f23e4409a45d07892960cd9c39c45f4e6e4d7ffa5f1f6ecd8f0a018cc71a3d7d53af0039aabd4593663c6d7e0ca05bbdd6ff551b7fbcff78f5512e2b8ca2929010001	\\x55f46f9ebced46ffc6f333521be9808768065f5f25a25c15e0b2d8fee23e841a2421326da8658d3076af7d8b66f394a436965b97a708fbb36d34cf58e2d4030f	1669564415000000	1670169215000000	1733241215000000	1827849215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
269	\\x6dce91cab747f1105612822621e3d58d5fe08be4674017178e31eed4a381acabf6c0167fea77e1afdd4d1105a8b54c2dfa716b15c1d021dfff4e9cbf1677fc1e	1	0	\\x000000010000000000800003b97a1c2bf6f09234f45b81c41bc6d666963cc3f986e4f3ac06c67fd8b5c5596bec93c9376747d11b2ad65785cde889bf31f15664fedbe9fea1178f38ba5b30576f930f794949ae046d257307bb5cfd34538955ee83e85dae5554c70b8eca4b08ff3fedee86796cec5e1cc1b40825cfd65b2d698ab66dd82c0ee16253842fcdab010001	\\x3b2426746c7dcd7a803dfedd241ff0e26ae03ccee07ad9f17efeadce931bbceb9853bb887cd36312b9a98ac9dda381dd8b175bf32060edbb2309020c3ba95302	1687699415000000	1688304215000000	1751376215000000	1845984215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x7062e4a13774c59e6ff30fe290755f6c30626686426b7d84c14934150dfa997db8c0fd02bb87ee3f9a7f6e539d47741ef9b0f8c1a1a998cf4f2b0730b00daafa	1	0	\\x000000010000000000800003b716d5f05f8f0445c85ef7d0128507e2eb5056944e8a9b2780cd72f6a568b3f616163233ec3b6a4a7b48815dbc24e61f6106cf5456a20adc4e5d3a68b81ccb2c8927312929a1442e768aee2610ec7890bd4238afd9587e5319731fc194ddc7573deb015b4bce6ade1aff904f0d80b7bdcfd5b3074f71fac91c95d33614ae2883010001	\\xc20a180f1185f63ee9d05932d24a90e75459a750b40944b89f024403ef352cbee8f1009c872b06cb896bcefc959c3fa36f1325a149e695653528c16bbe51e60d	1690721915000000	1691326715000000	1754398715000000	1849006715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x704aed5e6c352855ead14b1949fdd1696888e3c7909ea48f7bedcf0764d5bca5c7ec29d913b994c683f939b7b020b8a390e7df83b23c178c16b7ed4bbb6fb20d	1	0	\\x000000010000000000800003bc768ae11376c4b5472b908eedce6bb228c07c1fb140e83b422d10ccf9543603559d4e0a8c0253aef94bae4ba47b1643afdc49a724e7d9a216831f0e45d6a51c3f87f1d381671e662e185893a96b9efa7a443544822b299f1e12ea4588f406be2edf654d41c156ea75cc555e2fd77415c79c282b154076d672b133c158431e07010001	\\x0b86ccb82e4cbec66150dad7774a92b8e1b132bb3609bfc74ce4fc42d164e6693e5c40dc7b84343f1eed118d6665aabfa759434912f21d598585c5e5233df805	1678631915000000	1679236715000000	1742308715000000	1836916715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x716664b9f18d4dcc71957dfd4db7aaf319338842dbd3f48560afe8f510ceb8a072bb6ca48494db47e4f61c2924d9645327c1fef71621e250d4362ed51e79da4c	1	0	\\x000000010000000000800003c75a0df872a17858a1f3c9dfd1e38c8507be3a9989da6c1c284685b004074e99c6f87f47bc33a310c799f83f2cffab00d4063b6eb7fed153381d74ec9f6c8dfdcb6ffdd5bda252d50e37fa56193c5231d55f5deeb430c5315eebcd8b294007c99be35d871fbd79746a5c87b72e0740590cec305cef21433aff920b1ddc5d04d1010001	\\xd72651f632d03fbdd7292639adf54fd17a43d54a8c3716839ad58730c81ed6639bd73a639e22746e839e3cd32aa474057aae47b08722c7fcc3838b64b63d1605	1663519415000000	1664124215000000	1727196215000000	1821804215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\x73c21bb9301025b516e72b2ba28087c9ae906d8f30b3b0ed05a2778aa9f989bd76276a8ee65486076ae5029be652ac33443cbcbce4c22755fe90ff33a027a316	1	0	\\x000000010000000000800003cc52a0675a334d0006eb8c0c5ada3d4d5037c537bf7c1210b1b2e27e2ace923f50dad9199e707292dfef474573128ea7f31deb1b2ed3f9b912470841aca409317c2deb8e469ac17befad96a4ada8bcec1c84b867cbca0b8f8b58831689dbd274ce55973653b147997b041ec06c5fd1e111988ed82857faacf41a8425779bf3b9010001	\\x8eec3c8812ac131b2e48edbf3a0ec565d4b506d24b438b0d2f5ba959e2da6d5b0227dc06ae4e30691a8aa1811ddc7fb6408c5e994008b103212826191b993d0f	1688908415000000	1689513215000000	1752585215000000	1847193215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x738ae9f3df6bf84735e2ea2e3b7ceba129dbc198ff66734b9e102684100852b9ddd40b9113d06423620b254a048015b0e6eb3267bc43c3a3a6575304947822b9	1	0	\\x000000010000000000800003e80f9412e1c845d056931f4e933ab0c8369256cdea9f1bd344ad40b7b90889f8ffa2c3fbbdf9b08131023c688cc15ebaaa46d4c6fca7e99e19980901ba625f13c3a9707308725f02a5f21d922d2e40d8cb8070b4289fb5b999c7add2bef49fa9f995c516fc6ef78e5aaeca9664633a1061524339a6b4c87277c28fee0f25ac35010001	\\x05b86153be88a978bdc229b691c2c438097d071c2087c5b84d5f47a315f7958334f6afe8c2ccd3bd8f163ccc1b28fae87f4fe82957639d4980e630f55773ce04	1666541915000000	1667146715000000	1730218715000000	1824826715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x7d463a46f3fe45ce6503c2dcbe711a45d901adbc913ede167cca2fcca68f15ae213c29a3344981a7ef4baf6cf0ab9c1c2820ab234363cbe605aeb60dcac17a78	1	0	\\x000000010000000000800003cdbf76507d12bafcf77c1ba09cda6041d93dc85c7f9670e42e7fb56555cd5ae2f38ea262d14dd758b860f89717978beba037f673fc65d8fe23b2bf9c32ed9134739de862e5a0b50e3fb9280e1d7fe78b0f22ccb503b639eb8897c832158f67644a3e37675156439781621619282da1f8d8159737a31f2ec8d1f52fb8e8b92743010001	\\xdea2a9f109468157eb7c808d824b272a9326fdf36037fe99b57f267c0faa64d52d11c9592c6588677d1b1a7305a346ccad105f2a73f64a75acc31091b2951e06	1679236415000000	1679841215000000	1742913215000000	1837521215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x7d9a1af5bc6b623befd8fd79cd1e4525cc371a75959c7994ea78b4b2b524483a6941a04ea4129a37f11c53a9863d2066e77d0e60a0a2ad4547ce5370e01fb3c7	1	0	\\x0000000100000000008000039feb86106e2a98129cd0be11f815cd067d58b742845e04367aebcfcc3cb627ee517c2935751f58546ce5edc7a26c74b2d49f7d8bc9331c7de336a5502a5b148fe80e18b0a3c034364f421b6c32ccd8139043d5573e37e18c87500276d3423e3a2459225fa5ba661987b18976f2fa7c5205af9d747121b9e3e2cc9966c5218219010001	\\xd936f61ace597735ef54f1c199304063457ede484da88edddddd4b7a7d72596f44a4a90c7d222b2095d3282161780dc9f4244cf6d8e26091b7638bc4ca4a6c02	1675004915000000	1675609715000000	1738681715000000	1833289715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
277	\\x7f4a99c4e43b415c2824b0e4189287cc36f9fd51ddd70faeef8fa08afaafdf314c514f966155506edae38bb38e3fe4c7defccc78767cc0a98f9f4f1b81232b5e	1	0	\\x000000010000000000800003cbbd2d484151e7ccb924b8407037f2c19447345693ae54176911c6a93c05a2f0b6fd6a1aff590dd837019748beb846a609791aafb3935a0168952d3bc3f7d50a211cb37bdb18892e93928233c08155daeb13ccb8cdf72495331cc4a4f9c93ed9008ceb3aac070326b4697a05ad0fe7e3e2d8da4688f0aafb817856f84ce9c8fb010001	\\x1e552de09b9b6361094d3a0c0641fcb4da6bbe716a308d90bbe489ec7ee8fb7658dbd8363ad06ad4eb93bb3310941b48ade666b1d2ed7e539a1934ff8f189603	1667750915000000	1668355715000000	1731427715000000	1826035715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
278	\\x830ac9dc263199ad317b6a9325bf02335a42c2c42d9fb862d2ffbce00ac960eefe763b87ba2f2e40ca3ba491800f7824e0a966b87d6cd2a02e25a520d66a288c	1	0	\\x000000010000000000800003c4f5b23eaa7f1ee94ec88d1fe7c8c9da7909c43cdead4110f9d44908e628f338cf96681d51e1be9269b38db46f198fdbc20c1446e7719c59be6663dcfbcee8510a84ab80ae638212f5d6950669903c998bbea9709aae1978aaec096dc2e6034a56c74cb6a1e1ea827c8cf2beab36d6d2982e4e161bf906e904b3333dba280033010001	\\x748351e2c1ccba2f994bea2f6d508198f471cf78ee882a254f7f82a32efa9fd7993e8e05ae592cca11f23135b8ef0a5094bc9ecb430f3acb095a31d2cf4f010b	1676818415000000	1677423215000000	1740495215000000	1835103215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
279	\\x8606d1401b90bac40554f1c49c54e14bd103b69ddc3a6dfad24e7e7bbf2f76fcfed4c6f34fa35adee82bd886704bbe5208c721378afb8538057d97f785a5b626	1	0	\\x000000010000000000800003ce6fea07f7cec65bd5b79fd7ab96828c91ac92d65c1926dc94074fe333e2d3ff4a95770781c6119cacd7656bfb0ebb43773bc3904fef15c9d1f14b73498ad9f76659031dba7bcb86a8f174900ed71973233e114bf0f670be37504ade880d42638a5aaff1c277fbe58a65637bf0237802d0f4089d6e19c2f0b13bb7c385b37a93010001	\\x097b36bf5ca43d32e13e1146c9ea238d13d26eca2f496b691b9caf9bc7fa330d38f1b5f6a5873e441b3b4b93266cfd20095cce141e47ba66c30b5fa6f595c407	1671377915000000	1671982715000000	1735054715000000	1829662715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\x88ee38d2720fff4ed1a29252865f16b06ecd208f938efa7e2d323d83c9fa1d5fedf092a02df5c83d0e4dc11c10b13163451a4f61caa7fe233a9ff9c24850843e	1	0	\\x000000010000000000800003bb0e853c16b2b06bf8c98e1b996558c26e6668f537747183267fa4c039b93a3f146e069403e89814253a0bb343e3f49a858fb13dceb7069221f1e89f747f6f527c1a97d90601accc9f160a1e2eaa2143fec2d75d6ead9051d01a7884bbbe3ec8e45b21b40be98518168fdc56cdedb4513432129ca7450f5b683892d0ead471df010001	\\xc5e07da4056a5db9b471a853192d4ac94695d2f2449fd7423903070bdfdd3328fa2cd904d79b3cf38603b61cfa9d15a35ba526e4e28cba2c952c2ec620c99c0c	1674400415000000	1675005215000000	1738077215000000	1832685215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x8adee3ad5a7d59337edc7e11db9c052a4a85238dbe6b48b4c0737dbd39ff7cec521d07ba01f3e4d93748dc7839e64b0f4880e4362c67cff4a08ec956d717d2e2	1	0	\\x000000010000000000800003a97f692f7f93fbea8180d9679581ad0dbed707fe83601067ae81136338e8f000068550bd7a822089084d78af6d8b1d16a6b73c1eca7680afa8de68a311222f80a505dabf8f6a573d98f719ce435a0d47df0a8032ef3ce26c4cee3ec1ea28bef6f63a72394bb2480891d20228789e149f0adea04fde81b1c718efcff922f0fa89010001	\\x6b95b38f2a83c10f2c7f6222e2a883db9aa603bdeb369b53b41d015bcacc25f757541dd7f9bdc81979938d2489a46269f7a818e9ebfa48148c172f7325717807	1680445415000000	1681050215000000	1744122215000000	1838730215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
282	\\x93da6dedce72a7c1a06c9af5ede9b001be112b9e0a27eac99a17780506f4fd1ca3c5626520e18acb32ba358c800aeeb9ef8c473e2dccce67daca71de4862f38c	1	0	\\x000000010000000000800003b224116fcbd9662e456a757e88718b8651b32ddf1f3632c23a490469b532805dc49960a36a57f740e1b368a3be457404daad2af039ec185e6648650569ff21d2a8b56b2f6772dc8537566c242464d27de90ddee53a3dc1de315eb2e707eba79cb42e6ec5206b9a922b79aeee346fc5d145d788277b3eb76a22556d0ea970e9e1010001	\\x4a7f2aec0cd31aaa6c17626af2b0361e5908308d46c46f6a4127751575caaf1f0891a1faaf7e3e00ae01914894e5aee91e5fb0b5440a0df669cdd3e3d7f27704	1667146415000000	1667751215000000	1730823215000000	1825431215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x999693ac100314c23248951e94811b5a2d5a98bf5a3f8f962cd48dfd9e612ecbbebd0d8244d1d1da5cf46b34cc9c28d21300fdff4de9565d242d58aa089c1c94	1	0	\\x000000010000000000800003c41cae09c6f6768b948742b7aada0af6cf559de6e240f02bc27d9a2379753603158015937bb31100dbb52e75f427638b237c2c6ee8062b72409d08b3fef973893e140a837bf3f7d17b177259a0d99854438c3e54f05a1749c0559834b662f7b93e4ff55fa484c65b319e2d4a3cf9b5308895435c51078d299a7ecce2672dbedf010001	\\x19b089ca127292b0004e48ea7b5237ca7a7c0e2ee0cf99c969808851a16d85c9335de5c698feae7c3607a7cf0599aff1dbf0599335da6fce7a2143fa6a3a1003	1684072415000000	1684677215000000	1747749215000000	1842357215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\x99325c2677a19e002f85ab6321b311aa248384c6082d2417762c0ab1c94968590c4bee0f7c448b4c350f24647c05dd4a529307c4bb445ee9545a1fbc2ec027c6	1	0	\\x000000010000000000800003ccb7a9c9a78e462f46427fd3c61c36b607ca9a057a6dfda2a29438f4342c00fd1df502da0180e4e40a58b7dfcc4d57036a2cac83832ab0ce89d48e42683192c3e07e23855becc454dee7e426e604668cdc7371ada01935396cdaae956c414d77118c3d5fd011c82673505af2051a274fcb9ef21c24181d797fa9d6ce842940ad010001	\\x296506467c4749474cce2eafd9d297d427cc14d8e09333a1757da252ed42655f9e79432d5e4719135dd224e2dace76a9e8f9b2c03c8bd4ddccf47b35446c3f01	1671377915000000	1671982715000000	1735054715000000	1829662715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
285	\\x9b5ab1fc3558065d8b9fcdbf14894e749ac5b52ec93202b6b443261c73066bf08233f5313b5b5370c120d1fe0546195a198982e7a60665932bf6fde4a8664d90	1	0	\\x000000010000000000800003b28763ffa08f3f9b2ef2929601e9d00546f80309d53ce8eb73f9bd6fdc0e6b577505fe841e5ef658a3835587f5b98c2f2a027bbfd905e6cb2d8b6f637b47f052a0f858bf9181301c63f2738d4073a6f7b27d428dde2d2fe9596ebcb077c497ce270b44970f3efd60f325ccc0815b475b5f9c5c3ff0b25b0ba7476832ef5228ed010001	\\x5c7eeba5ccdf433327b20b25fa56da878b6d19cd29ea40fbbe41bd7b9442f432ed01d4edf00a13ad9453a25a91cea8bfde0e48b08f93ce2fbbe3b4196921cd07	1681654415000000	1682259215000000	1745331215000000	1839939215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\x9c0e455e5ea29683f10507c33bc5372023375998c97186c4e482f306f148390bc48c40a3ff25603c9fcd6d82ebe3575bd3f812fc782366a1db6e6cab2941e8c6	1	0	\\x000000010000000000800003a31801f727cfff291fbcc0e1a8db0ce9d220beb7fc5386b4396b5044b789818715073af99cd99906b38a030df150daeb12377631b50dc96ee3af1a088ba7e2dcdc633de547b7e19950ddac7c4c96cccfb223afa6eeb2602f19269c724d654ef705730ad14b55c3d29f25f37907257c7992ca3a4a2df75874858ff31ebfa76a35010001	\\x023f98e6eb299034fb2319d98812dc7b32135d10b0f34425854da8e67dbe932bb2f5fa902f4bc2716dc785cac0c29f792c98eaf4a941944b5979d260851fb006	1690721915000000	1691326715000000	1754398715000000	1849006715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
287	\\xa716f12b710805a4391548de3624ec533023929a803d1b993f6ba7295988469692f748c26f86998479309fbe7f91bda7afe12259a6263a878d9e1f0eca072005	1	0	\\x000000010000000000800003eb416e0d5bed3e668c8236e780b4c023c7fdb918bd0e4b702bf053ed1f56e97a9bde1c01939c7a7275646abc225426acd7e7383fd5d6ab9ecbf23ed3646c1ff4300db0b041410a94501e4034df23abdba375bfb67e8dea8c38d8b747e81bc59d016db1455dca0ead3c40c7545dde90a2153c1cfda862b2d79d47a900cff43031010001	\\xf04b1c40cab0721b235ab042043b83effae11aa0bfab0b64162f8a1d36882c186b829f56d530e1af27206c58c7bffc96eaa130ff38a05ada3f794184949e8607	1675609415000000	1676214215000000	1739286215000000	1833894215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xaa52c99fb5ea945a3591dc82161066d51d38615b80cdc1c69e83d40e8003b363059434c71d9577c25ddc324398f5062a0f58a407be9711418baad591679c2dba	1	0	\\x000000010000000000800003e0acc4992bae19f21d275478a6549f8dc6844e28b40517644fa43535f992deafcb36cac2f5b7a51f78eb92b9b62077413a0c82fa9228cf00e781a3ce5cee8d8b2ace459ac5b9e61e70813cae50026f2f867711e6bd9780672297009f0dff103575eb00d7e6b06b7fbaa3bdb697065e3a5b907542c3f97471d5ed976b423ae10d010001	\\x02a1e2977877942830627dfc1c8708678b4722bc82a86b5796c0e186e549a580080beda3fa184d7ef17d1cfb7ecfdac0ea616352b363fbf29871b1eed0c06c0a	1682863415000000	1683468215000000	1746540215000000	1841148215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
289	\\xadd25ae25de422f59fdadaadabe757b0f4e1d89a58ebe92f46ba9473dc93be14946b032310ba476b0397d15cf74d287b18ad9dd38e93c30b8bed948f6d1cca9b	1	0	\\x000000010000000000800003b9abb45ff6223edff6e2eab7d9739e2b24db54f622fa641ce762155ba9e256b01bad22e22a74fc33b4828ca807e0ba1ba2f2bf11fb11cab0cc5fda68f4b37647c69bacd9d65c10cf23492b3d22c03562420b3bb708b03010ccc884e0c949933950a5754dfb48dfcb6f9133d33897bcd5dae87b44b4e5fecc3f3cd36bd35209bd010001	\\xa62ba8c3c8d098c57859676774b92b292c873babf2be3cc7c4054cae4d8d4ebd6b39988f42f6a5a76020afb85b65375e4ddf2b20ff894c608f8caf0fa7e11b09	1661101415000000	1661706215000000	1724778215000000	1819386215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
290	\\xb2ca8d06f5f379920edcbc7a8b4951738f8f29f391f84d13f58c03c465ef1336e766e196334b118f1157f4b3f75dedc9b004efc369f4e84e9da546a81e5ce8a4	1	0	\\x000000010000000000800003963e1c5a9b0c59e9fa27a34a8b15b4d0f1ca4afcf40b08356204f9080cc5df3ba2c27f4110a55e6e3f20ad58884a49f8d350b06323e2f180c780bfcd3a520de57136afd6aad916d9cb2c3d6fca6fa32383d58a739932f03d297e049ffe61939243c45a5fbe0adb0865f28e2d4db9db325fd7fc906e10adbc0be1b7df6aa4a875010001	\\xa49f3950380c4cb3167d0d8fb9b3bbbe3bf033e6f271981db5d2361374f6c48669dadd8357155d576052177e70d30a1f3a99175257941903b6f6ea9b6120fe04	1667750915000000	1668355715000000	1731427715000000	1826035715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xb246444056b4e209c982a150ac8ee511589450101df7c109ba1fc11ff5699724a3a077578935118062ad1f95f37d082f37614906455adcdaeb5f13ff34ae2838	1	0	\\x000000010000000000800003f43ffdc04e6833ee8010aac05016d50a2df980466a64f6fd0ac7f0ecef7a95d9c598264f8f40c2697b78f2951f9106525d5c44fa0749dc4abc58ed285cfad90e011d04b3660d3b23fd44ce140d558f15898dfa4ea3c80a5c7489c63b4db2cb9407b6a73b5c56da5af1cee70924d913b78872f54d84467057e199fc3dce946beb010001	\\xd569eabbe393ec5e0cfd6c571e433ada9fafb00b2de8a32b6eec1c55cb908036dab5f1ee33ce6c975f56844b1f976be8d5e0af445e0c6adbbcaddcebca7d310d	1660496915000000	1661101715000000	1724173715000000	1818781715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xb3ba09ab8a7b9ffce08191601952faa20dada12e6f88a0a973bff5e3bcf8d1a0c485e5eccf23aaad87f23a258fed22bf0b35181788c24320159fa5be94154afe	1	0	\\x000000010000000000800003cd59c0bc415178d0dc17df117ad7eda8fdd665a986b73eb8620a91c37addd18de6ffaf4de4e67ee3ced6d5c40b97ba37524872252393c6ea439d50be069eb587e44f68a2ec0662b3ddf8418124bc595c9ef9f555a4bee399ad8311a6f54d31b5796ed11a27e3139e9e9fff19f2c4bf7d5077258c65228b35d36eb233c0178bfd010001	\\xbde1fe9ac23cd1b96d442b7f803878088b71f2abca6e5b9cbc906e0934eedf1ea32c8fd7625c0e28703b7944510349087e77c1aa70ba7c8d379f9adaf459680c	1670168915000000	1670773715000000	1733845715000000	1828453715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xb4d675d48b35bd37c62bc16e56746252dee8bb7c29a5efbd4b1e4a91c16de9fbc04f5b692e49a407214ee4cedfb16e1bd5d56c2d15ff6b031463606b462caaeb	1	0	\\x000000010000000000800003d227772fd56a2a0ce7b0b13c0394ed302abff839e1d508158e6d26a03ae5f907e519c77a3c4987f4e006993350e9b2cfdbc10cbeb3d8d0765671812e41d685d495bb75f914ce185ece6956013d4f162b624e19e1759db23feb77ce63b7ec2835c0738e9a9a60bc0e1fbd1345c142482370a0746f5b71dec9e358625d638cc6f7010001	\\x34c36c0869418c5b3c9796f22e53fc6acca0c5b492a7a1bdbfe7485d816d931da009a3e06ac63b115b42cfb9a24e524dbd2e880ba01ed21d9756282b8e12450b	1671377915000000	1671982715000000	1735054715000000	1829662715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
294	\\xb456048ebb33278f2be7cd418f15ebfd43f1e19beacfc6a72f444aaf0a3277d7e8af678407f337f74629da20c45c346331934cb7aba53b5d4f6aeaa736f1680e	1	0	\\x000000010000000000800003bb658bb2318bd8dc293a5e4ad6df9adf42f1fc21b69ea35139f4eb97a8a7ef2ac2298b8c566ffd5f03a19b64e0ac14c799fc4bac0be7bf06bfe7f8b1f17bccc288c8dddba3a9662aad1b71e7a74e7a6aa3ea2775d5ab4b07110f49b892a392360eb695093280bb9f682bd2731b08fc0d9316860545fcf6019968f1c01592ba51010001	\\x526173a798f86803a955704780544551309149d276658cbc722912a8721e1d29a8b5447827b1e2dc33725c10b6c03aeae4d5ff5178eec8c70f06ab8487431f03	1691930915000000	1692535715000000	1755607715000000	1850215715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xb77275273aecdd1ccace29cbd18c2eb0b6c77a8bf4576e26d6847f191bfff78d224b2f42d202f84593684df97c8981f919c0c811583ffa5c2444fcbde65624e5	1	0	\\x000000010000000000800003c82ee4c0a9726044cb5d4525775f62f1b2907413277477a9be4fad8dd2147f2b594c731e8121c2a1fd34428f93ed8916eee5862d918dc9307043a2ab6823d26bc85de964ef6929159bbcd09dca9c8fedf79c3bab7c4af327d4595560ac69b62eb66b474ea34e7a92e78f15b183fca1b40060449465c666ef1f8c98ce1ba9e279010001	\\xe545320d418397ee5455ffeadeef744283ca83b006a028b8ce863a508ca6886b9c5db4e280e354d83e13eccdc0b6a8abf9f46a52ac1ee44629c1d67ec4ea9b01	1685885915000000	1686490715000000	1749562715000000	1844170715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xbe6a84097114f102da2c65f27ca0a0428c25c8a6dfa97d7e91cd2069571776f0c647bd9f42433cf58307856a5138c6f682b97c7ee9964808025533dd5024bf4b	1	0	\\x000000010000000000800003c81801a521bf98dee0acf632ebd63e96ce865b0535f097024bec0929b7da339de0438cc44d790d328cb02dfd255e530d939516c8e0969140052fc000c44ba2640ead5d60978f405a5a8ce1a10a0bc98b161a817793b24eca53ec981fa31ef79b06e04fea2971b06dad870e05f9c2ab36e0c77b04391631f8611bb57abe8adf2b010001	\\x1d4387b70b1b605f52605accb5fc4b150a12130f3357faa5acbe0394ee05fa018ddac438b6dee3d88c702cb8313599c5e3d0caeda7d1a033a374ce586c44590b	1667146415000000	1667751215000000	1730823215000000	1825431215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xc36209afbecfb9acbbcc4c89cf45c48cb8eadb33a8c1246ddfdad2772935a38a1b79b3e45b7c909a8519a2b62f742ec27b93e419e65b79fe343448e50c5d7edd	1	0	\\x000000010000000000800003b7bf01c45dc0f7fb8749681645408c15c9f5c4219549275bd831c4a5610769f66f6f11d5e6c39523e47063e1ce9e791311aec7ffefedbf338abf0b035cda6c826f54d992597d991902f1e1ce3e8f8bcd28430651df73e2a05ea8687e8863c2dc853ac847ad009fbb7ceba727fbe3fb71f35b31656a6ac8a02310b17248a0f3a1010001	\\x70434e62c8b2e3185222649ab0fa8b02dadb0cb3ed9e498aac15f8a0262c0d940a3d11a8d3ed4506824caf0cbabee43dce4ce3daf2a4c8444708ef69cd56040d	1685885915000000	1686490715000000	1749562715000000	1844170715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
298	\\xc612959ae64b82b798eb6b6d8469aeb9c16bf696eff14ff13f8c8ad4295e4dede78d95957d04dd2e4c6f2ad00e0530e24df0f7f8876da54ed7bd224911b2f310	1	0	\\x000000010000000000800003d8c7fa51d1f969bbdc0cd3f9d57d280da3cb0503b65fc7a413e5c43e7a3c3e6901b4da3e8853de8270caba733b67062b17b8a7a0b824789cd9b9bf9ba12dd39a07b74b0cad62860d0e0d96d00d7369639f17429ae85a634b808a8bf4f46b86f00fc2bb38310042d667c817cff87bc9d51d53ca609d7f5232fecf2d611baad52d010001	\\x5ba7f09741b62e1b9ac3c1dc6160cc2519825ec4a9fda4dd35a85e3c877302262de50f6e692e1ec7fc8f9977676c97a80a13670719886d0bdab4a312d53b2501	1684676915000000	1685281715000000	1748353715000000	1842961715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xd1e6a16a9120fd085c3cc5f2baac6d63172746a943fae25c984a86b29fce9064926eeadefd0a398d7280f946b8bc84fdd15fe0d53f064a991995fe05e5f15154	1	0	\\x000000010000000000800003d56557a1a40eb8e15b9df5c189963514c3f5a3d5b4fe04c347feaea49cc1d11c045866b2a5385f1c3a0aff437f6be477ed4cd9419957ba00646d77658f07c21dcb733ae4b6e1434abbb80c14b9920d6e7f6cc0fc3f5f7adc837746d1566c4d51f3cf872f279023c2b3fcc9da36b74e31bd658abe1155b909435aa98b9e4fd923010001	\\xe7824b83e73dfef235e1ec7d8d9ae889de521be9af6cf73945f1e3b6ffa583acd13ba8f3154ac350ea1b6b984b1ae92c271dc9429c7fa0b581f646ea5b5bf502	1682258915000000	1682863715000000	1745935715000000	1840543715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xd23a8365770a8a9d82aa297896f71116f40b994cc4d73997981569ac418ff28bbfdc7a3d1078f1f7cbd0c824997af2f42aebd85a35241bfc0cff93e4fd6cd71e	1	0	\\x000000010000000000800003b80c4062680a906125c0965d160ee4ddca564fdb2f0b799d3fedc629ca27be676290d146d64b55ed2563558657e86646cc1375fa45bc905e28d768d6f35d11655f0cd477675dcde99c6ad4391e128876b1f5276afcb5bd97ba9c026e135dc5437f95c13bda00ad7697ffbd26c1a7781e543e8c4ded27f53fb6842805e141ebc1010001	\\x5ac39e3003439f6d5cdf0e1671e70ca50d21da021db4d595e818b49b934977a381408171b9610046d7c231b02df803620fdb02c290d01773fc19680576d5bb0d	1666541915000000	1667146715000000	1730218715000000	1824826715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
301	\\xd5b26dd62101f6904c68c9b8c9a4b4c6b7f919810c67f7a1af46a2fa3839acd023dcb8453550cf34d29b06d05bd64997a40eebf3525477a70de0841e0802f636	1	0	\\x000000010000000000800003e6b0dd6d8e330b72976bae5b5ee62d88280485db7caccaccfe3631da9a3e1eb4593a12abfbe1042eda6941d8b691aa494d3395c0ab306bde1fc78f99435eb78244ae0ba7aa406da4633b1f4cac76b75b5fb2e0150b6d161567a6461217569892f706356ddaa7df526e49e50c78d3961353fb76b3e8447b1717b7753c8eb6a9d9010001	\\x43bedc1e79b93e457ef7ee25e6ff6c38f30dacfd05b227f923673171302c22062e4aa32ee8aa414fcbf7f8a24d88760b25afd22145d74a8dbd6ede2306f1360e	1667146415000000	1667751215000000	1730823215000000	1825431215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
302	\\xd6d60988e0f5d9831bed5a53862b202311ca4b8c00949913ec4441a33171df86fed48d8e514b82218a1b7e7c99a61177bc074a60fc00146b2d0a58a836dfd08d	1	0	\\x000000010000000000800003bada7bbe3b30345c51e377da3af2991839adfec71bf438929651034e2b9e5f12351fa8c7cf3c6d090b9ea95b3012da18bb89fe177804899c25a430a8caaa7ac3d3a025aec8ca63d227807f8eee75bc1cdb0231375cfe7a252bddcc6a764c45f771b13083c5b7fa10b838489fa73e5a9aa618dbd933be9161311f9a0f3882e5d1010001	\\xa4e553b93a10fa8f92aecdd4a9836318bd5dd9397b377cfd17cea7e5bd2bf338e9e6928646402d8d344f08584fb713550f8eeec01abcd5cf8cfd2bc8f7b80109	1667750915000000	1668355715000000	1731427715000000	1826035715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xd98687cbd2f84104b93b6d7a60883bfe2035542764b107ff531d66a53a166bdc2e8aceb304f6b118250eeb63dc0b1af06bf61dca0420f5461a6cc155fc035d9b	1	0	\\x000000010000000000800003cf8122e9c6e7c08d888a2453b3fc0e899d2c9e71ae67581ba66e17a6b1db9b89133bc2e25db09bc8ea296f0af0ae14b4f8e50dce5ad10d68d1891bdef2de698f3c167a1d37b9fb3995e4afe84c574d56b3bf37a5dee275fcd1b42ba9236d85c99d25f0ce91447ed144ec8f1c4e8ad0a745ff1be45599441ed32806b49ba62d37010001	\\xc8cb24682db29e07309bc392af2b029b890bc6d7302ec179621cbd28125bae0cbb3bf6dd499b1be60387d79260c9a0e2c298f8629d97b11551a7eaef07f31e0b	1661705915000000	1662310715000000	1725382715000000	1819990715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xdbaedbb0d0050079341bd4089b3022879dd363f8a8f88acaf34e8fdbd3ee471d77139ba5fe2d7654aa724e61a2ad22ec69f336ee1e467c18a30f763d8617ca0a	1	0	\\x000000010000000000800003af342ec15333d2540e3725422015597443de6ab9b5d93e67afc44b0db2c38abf49e1f62b7e327a94fc0a146dcfb62badd2523a3e34379aca21a255480b4c14abdf32a59275a3e2fbae4debd1676a1a1a21bd289b2afe4ea21e7353f3023564638337b9e4ae84f9bb62e3a24fea5813b8b3d482bd297dd164d1f914e9c0a4b0f1010001	\\xac7bea9aeb587158a3e49769c5a5f2f56eed7b7433366bc042d25491938033f5c4e03d62438c80ad06df8660f08aec783a4eb4018df528a41858d44042b3310e	1671982415000000	1672587215000000	1735659215000000	1830267215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
305	\\xdcba92fc0ddd99100d88d68951805deb928ce02aabd914de7fea036bfe4a96978d028958f1a188ac3bb62bbc83286c28daba31d3174058b65664ed2f5f7413a2	1	0	\\x000000010000000000800003cbbbbe04dc152b812e9e2e80263b8a306422b71b628fa4301ce7a409fa60ca344b341c83145839827db61e1f695fe2e44d9d92663c932ac03298284e383d192ed53eb8bb0359d900a86b10791c86de621fac948d1bd387a73c0157e0f01e9a40128085abb47972d6eb44868f48b5aa8c000d4edb3698e12a401d750ba47d149d010001	\\x2b0d2ddd0506112c99ac4344718ecaed3ba4a3e3f32a5831d5f84e755f74140d8509a4de70c46a2df0acbbef414ef4825da2dca6a3720b32801ab1fde34f8d0c	1664728415000000	1665333215000000	1728405215000000	1823013215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xdd52d1cfc0e0fc0c7452a4343f730224fef23f012392a67756d94c5b8571b708fe8ea6b04b7278e0780b6cfc32f067895c1dfb8e94be1be2660aec47323263ed	1	0	\\x000000010000000000800003c4c853509ebbf30b01b062cc2a1520c8d7db94c36abb584dbe63c7f615d8a8d473b35c3b670c899caf4df83e52153576429fb6469690f8f5c240785b5f29326273aeb1834cbbee982311e0af772174e02b73cafb8f664a9a8022bf47ca921780572fe3ca637a1213d6b96b942a8e57304e1d640435b0fd6010e45e6aa7ce8ca3010001	\\xd6709c26d46478b9f3d90b74296bbe6d534715d17c3ac839533bd26a04b5640577ed8acc5ffc73e1f44aa0685692cc6ab6ca35dc9413e4a692ff944ea0999905	1664123915000000	1664728715000000	1727800715000000	1822408715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xdfda281c5652f9e2d1957e5ac9a43060b311548f27c1b572e100581b06757f66c114208a203180aac015c3c484235419c1c320ae11968f800f5e33d0bddf7d5c	1	0	\\x000000010000000000800003c25a1b5f90c818800fb1edf060f7a62b80491815bf9d7ad3cc3cf351c67183b92a8843490007aa1f864e0005ff8369851375cbbff66b948bcffed8a15fda3d8cc898e36574d9d004ea3065ba7fc04c5e4806faa0e331e4079ffc183bbd42abafc0bb7e832e41c03435ee4477eb328abfa5ce455102b9ac3da17da5e2ab2f5269010001	\\x9112ad0a2cfc954aa159d47e13dc2098c7a3c5e6b2b91dc91a4d3d7fdf7708cd305e8e55bb7170f473c042731a5a351c6406cb435aa9d69e75c22711e175de0c	1662310415000000	1662915215000000	1725987215000000	1820595215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\xe01ea905fb800507952b347edf8aac3ae58b805487723364e5aba0f260005d5fa74802d8d1271283cedd9278fd82ed5767041f3a5e534fc8d0f6cd15193c29ef	1	0	\\x000000010000000000800003a146aa8dcc73b4b673168c66f154876f103e4113d198091fda472f12de37f600d873bbe4a6f59a580319f11c8c7b135fe5d316714173faadc380bdad8b3310313fa6103b0941f942134efa2184724f4d32fa2e20b8af50c0a6df1c7b9e7c0b64a9ad35ae73ddff06e807ddffe7c6f8dd23cb77fbc36ea46e167ad1855cbde305010001	\\x0441867a86b61fea14cbcbb4207b5eb22d8c0a4cad713b6e028eeec5b5033d9cd137f2c1e876b1f20e858d3bd929345676d23f995196ce1bd15ca10b118e430a	1685885915000000	1686490715000000	1749562715000000	1844170715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
309	\\xe0b6724f18f8c3e5021bbc554041d2f6e924b1bce5090c7b82b76ef881bbdc527365c0787d609331a635705014ff97b42aae2c89777dad97c188620289022bf3	1	0	\\x000000010000000000800003c6e367771c6ab54cb3558c6985f2862686a5c919b30c01857615d159134f3613e62eb810623f859e04425e2780194011be323146b8403e0dc6025acbf04ec3acadf5b671097046535e53c0425f067fc4bbcedd187d5e1ad11b9eb43556946643a24c5bdacf80a023b9198712168ab7a5e7401f204860779f866b9bca78de08b1010001	\\xf5876a6f1da5a4f9525c376bfa996b961ab8c595576053ddf5ef01e22d8e525f5971a7745eaf167060c2bdbd1c17bc462e8f69544a01ad9151c70a086d2edb06	1688908415000000	1689513215000000	1752585215000000	1847193215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xe45a64f1de4a990e03a751da3b40b0d229b719bd82b15c3cf2ade583a79069ba8fbe3d9a55c9e794225d5032247bf5a035f6bf5bddf87137a38f933583a8cde8	1	0	\\x000000010000000000800003d3dab8b024a22654abb3603d2c60db498e934cce648c8547885308bdc23200df8f48308bbec6df9e898e36ca3dd1df6d665ff7bca7a05f94d3a5199e8b1253ab07963c22acfbd0868c908c1521ec71363e913f65d94e42c30e0cff9c43ef04e7deb7a337af558a5bb398bcc4d1d4aa4a0ab23208206a008e48b0110ba5dc9d1b010001	\\x21b8b354215c6b54a15b4e4cf73c16c260c5f02a7a6ffbc9b16a1e8f70b40f4ed29ec986732360b7c83fc8041e58c011fce4df0fc32a2a06dabac67292ac5106	1670773415000000	1671378215000000	1734450215000000	1829058215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\xe73a0c7efeceba55b536f19aaad84a610ac9f5e79edd86c7b1d24283794e72da6e7fd92cb5e58a62a833f06ed1ddd90bbc0fe3f80075a8b0e52863be778439d9	1	0	\\x000000010000000000800003cef5fa1101e96dcf397c35959235f7d7597c6a7f6abcea1dd56cda5664b9c3864c6d008091222501cc54d74fedc94182e0f653671a0a672b3cd71dacdb42630f1fe91311bf236c54012c04f7ffe5dc7def51a600338d99bf5229b37b892d30f7bafb246ec0e9823e7b2e3bc76822aa75f03a2ec85b4fd2fcd7daa563f6d4b623010001	\\x92bb988b1350f62c5fb117a26ad0fedbd3b7541253c9dbff620fbec770e82500134ba4f0dc1fe5c685273718b574d635953802d6d9f290ef5c806d92bed46406	1685885915000000	1686490715000000	1749562715000000	1844170715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xe8bab11ec5f6923bea4c81f67d419c6623241ff91ce264a43f3d484ba370012027fbb1524a2d7f2366787d791fdab92999927a4920171d29b57bb0bd23fa8303	1	0	\\x000000010000000000800003bf43a9843e658e030c29c483e93116b741602b9f6f910642b506692f95217a50d8a0bfbac2c78000ee23c24d46635a3646fd8c4f512f87b5d6f59ad4ca56ecde6248e79569761737ce28272075053216b45468eaa31d5cc39148a2873a81c107fd103822dfb4d09ea54763a3b4294b226b275ed1b33a3858db250f27b913dac7010001	\\x93146b8bacd830d0e06855260887eb27d813dbdf124d34ae23214c3aa7c170be0f156bb02fa00f2aecb13aefb22b87b6fc5db10fa176ff57e4a851fc30d54d08	1677422915000000	1678027715000000	1741099715000000	1835707715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xeaae1154729f8fad927bd9b29f6081f424b77c3ff2aa0c03e6779bb5edf5d2f39dae0b30597f166bbbc366c2aa4186eef295a4994fd1218d136cf54a3d19c72c	1	0	\\x000000010000000000800003c7c32b90f2a842c93d88042863d2f489a7885c1637c38256bc5504912199462d811692702f449df47887ddcb5d8b8a87db85860180b85eacd8ba0e7aefcc7adcaae9d502eaaf3f52cb9fb788ba3113b2eb11c9cc1790fb60ef3ebf109f399b79e5e5f5d3247400514e2473fa06fde70c3c51f2ba4de60b6637dc46a98c061bed010001	\\x03f5eeafb8f00df17e6c14dc1eac02f406e6aba0e71efa12519cca2b10ec4ea5f7aed729fef90c179497550f9d5f8730cab42480bd5eab22d524fbf4f86eee0f	1662914915000000	1663519715000000	1726591715000000	1821199715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
314	\\xea02bbbac84ba2e2089d8843ff71e7f0daea289a48cc453ee7658d42b9aef5534b8d0e082a014d071aafd414d99e15396e809abf3eb672c1069240aff4de1d35	1	0	\\x000000010000000000800003f7653e0e4fa6c529991a4ff42dfded64744a48bb09fa96fcb49fab89359829d6af2d4894fe6eb7b0a7b7a31504616035c52470443d69b497d1ccc9c632e37f79c4e800ecdcef7ab352d80d5d46f7ff8424d15959bb365b9e5c3857620512ecd752e6c02454220b77c77c5999b543eef48d9b30ab8d336613241244b38fb29dd1010001	\\x908605c7d3a6871045868bf76da5b322db5a0c1d655b66a2a21b2b8955f65475c852cc22031e81973d759d3290192e6fa349b86eb101df6cd47e9c61887c140d	1670773415000000	1671378215000000	1734450215000000	1829058215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xebeebd9fcd7802a5b3e258929b64e08854b907b6abbfbe2e17257a05985d190e86a39d178eb8a49d6c15723b8e628b9415e94fd69f804c61f2397c7a8a2fc39e	1	0	\\x000000010000000000800003dd8faf2a00746ad73877a565925c58cb0af38e8c72bd7ac45401603a5304c2202380e326e2f2736e47cdeca16a560f9d373f8a7bd159406fec5ebd5309792b1adf7fa0f7d2f34fb065347a0d4a9e232fbb25c92ec20a2622651e6f4e5169db5eaeae8eda1a1559d335b635dd87e4afb4274b390ca1565a165de2558f0abc4657010001	\\x9c9179e59645d8c82371f8f0c8ba79f71c427fc26e7cddef7ef2ca9d42c73a0164c4944f9ff10a22e08c311b9f15bf2942a7f395f4ba0e171acc5a0875e6f007	1660496915000000	1661101715000000	1724173715000000	1818781715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
316	\\xeb2edc242182e408281a45ef7f6abffa1489cdd0eb1e3b8c2538df7a27361b27ea3260048fc77f41003a6ab96335e74da719ae3af5711820e04b930a5a5bd1f7	1	0	\\x000000010000000000800003bd7fa778aadc4076a1ba26dc5f89baa4c06728839d06116a06c2f490c17139f5e6d89f13181f50a32101798d9666f0890bab1d4cc57b24372c1c1a41af83588f9bebedc33730f966ec7525520f6baf00778d0bcc8e4d59abbc1b2ee3f574fdc0a7b2d5b69240a94d6ef628c99462f683ed44cb90d3fc012d70ee259b5043e535010001	\\x6f4f07b8ce23896b3c21226fb5aee2a30e3891f312d8eded827bd340639d813cc76a89014aa9e069c9d1ea9a7d57f4e62de77c9d3299db7da53892bec2902d05	1676213915000000	1676818715000000	1739890715000000	1834498715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\xedba585bf137b310f507c479933a156f9bcc6a8447472a5b0ee3797e9e88cb2a2f6e853ae41b85d2f8fa2f828a128ae33715dda8fe1fd316640ccfd9b1f42c2d	1	0	\\x0000000100000000008000039de9ea56f25ed40c4fb509c36f311d855ecf526018c79e68d2d5a61e7347852451b1726a862485f67fcaabf037fc735c2392a634473707faac178ad9241195041beca6fa0a9b25947ec12b0e5951331a421d0caeee1258650ca41efb9373c827c3115054634ef49c28207fc9ec602019a65dfc6e772880058539761ceb1e3c1b010001	\\x29191b6d740c6662823cc391b40a7a8a042c5c597c4d0b51edc40559088f05334afc8d6e019668d73edd21c8a5b8b7521b135e57818910e2ddd91f0762e75f0b	1674400415000000	1675005215000000	1738077215000000	1832685215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\xee0ab18a5e3e1a4830a8d3fe9ac2aa27f340e2430a48dbb25f6222592586e32e6d33f48662b055ddb248ba75b610cec6cab5a6ffdf283fb6beff897119a825ca	1	0	\\x000000010000000000800003d9a82b8011652db90e964702540666028856408b2cade81289bd34de5b72fa27cdd674b98369be56334857a73eaab6ce0a173c39afd0f24e433bf7bc47f0003c58b19275d9fa30005f18efff561da1f92191f51e31f475ab0989a9df15edd7c9a799a93ec7a328e1a0fdde51c806ac478651a17b8128207801b4ce00d40003bf010001	\\xf119b40c7b6c31f38af720b4800984bff9fbcee66e5695600d7ec1c36b31532714291f985843f3048d1214e98157099caeaad19636661b0e80b06f84fc0dd404	1685885915000000	1686490715000000	1749562715000000	1844170715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
319	\\xfaa23879bee55ca9ea6db86b85e118e94892935079a3933a9781856f37fb92004bea4537591c5862efa156ea75aceddecf12111a90098c349d75ab82ea404f9d	1	0	\\x000000010000000000800003aee1fed0b5dc3c861dabdbc34750e97a587e24d5f5322a336541ba64bb7eca768ef4ac93fb27ea37dd6420c62a747fcf2378851e0ebf9a62c3a5b137b26add2894667ca2fdac0cf939af38ae0fbf388305f40569075a1d36b400d1969dd7675aad09ad2d5e2022c19774fee38d4b3eca01d7107d167d5f7cf37f7fed5cf3b583010001	\\x0be5d266b7605d7c5e4199bdb0273f9aeb9afaf948b69e0a8caab28efff4daf6fc615eae6adb7a0ab14209d5b6e3539b3f0a75b2de533a400fffbfbcf5afd70e	1684072415000000	1684677215000000	1747749215000000	1842357215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
320	\\xfa8a1625775ca9270f12eb0e4723acededbacbc1ff24c89fecc4bd23cd1f0180a545ab2475b1b7ef9a19efd8ffdc88c47eaf5f3433dbe52ac305a8d52acd2e64	1	0	\\x000000010000000000800003cf355ebdc842d5ac600c9ae6cdcbdc923051a7e4ef15f6189f6f4ba4d983be433a185cde650c7f3b00a84b0b4f08fa156e56cbe0810e1c04bdee99776b4711cf67f84113a50bc6fd465499d72e5522356384cd602b1917aac0d6095ce075036d36668688ddc7836cd1f9aca4b0c144a7bab7418ea66f4f02cd107527cfb86a59010001	\\x6c9645a9ad2995a6c609206c8cf61de45feb389e7127f7221bda84fe7e09400b6dcd3b74ebd9215166ba2e9d224cda90b2c132e2033cbdee479ba79d8f9dc707	1691326415000000	1691931215000000	1755003215000000	1849611215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\xff3e83d8b0ee9580b5beeaf9e76b0f67307f8613d179966c22470337bb3411d7e0e32059ac8a960626a0a327baebd60a015dfdb0b5bc73742769ea7febd1af68	1	0	\\x000000010000000000800003c9874e7f53d43f8fb4667abd0a6f0e2ff6561fa0d5083f49169e0fed15afbff47e1b0eb09f29121bc2c53f93c91c4e3cc53d474e231c2d6dfd46a26c81cbc47072b6708d17c7be33f77d16c1dcc79ab5308cb6c587e8eee3e7584b94d6e5e6d6fdd0cc8e77ac22dcbd1ef18fb1cfbfb640023bea45cf44f28fea55caa688123d010001	\\x8b490a67ae60ca4191e39f0fc4f5bc3d1619a169f1e78fee6eafd388b291264b6a6c4ed7142f7b8c8dbb928a875e00ce9b0115ef6464951909e6c3959df7a908	1663519415000000	1664124215000000	1727196215000000	1821804215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x0477cfc745f3c87b561b03f63ee2865a2fb2312015a09bd96bd65cc67b7d38f3d0da6139b9c6b20e89b93216ab9f4b072d35ea59f063d42c955f126be3a1ae9b	1	0	\\x000000010000000000800003e244ae6f9dca8690275a31111137f52ef2fbfafd66df947653326aba6905d9d0166c01c944274cf9e899b93df7e4e44bfd4275c753d4eb00426a88b02ac610272641c7e5d920e7743ede9272a23030adf1d46569fc468f59e75f68ef8b424843bb13ebe1fc208d0859da1c62085894589d7bbffcc36642899d17ffc13a8aadef010001	\\x0a62b728f8bd580c5120a9da3858e2723fabc3c26c6eaee94647ff838cd3f362a7e2b24b2d314c35aa427a43dc2baa193c8e563447331cc858ea34d9df38fd09	1690721915000000	1691326715000000	1754398715000000	1849006715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
323	\\x0727df69e04a263027722f116cfaf7e3fe1436d905596adbf4fbbf10bf52b632aba9f04d1d74303b7d61f87c162965dd2ef74f1c2a25609276f1eee87503c7af	1	0	\\x0000000100000000008000039473a80b38523eb9fc217a862e1fd5031947506b9ccfc8d176594e9eae0371b8d78cf13161f3bf4b66c435763e82813642fdacdb20c800fd323afda8d018cd903da80369d45419be984fa79037016fcd81839b67676fa785d5dee55010d6deedb23da1bb36a2cc0344c9fc32eca7fab5a93532ace2bd561cad2c4cf233c0a297010001	\\xb9d8810f888ecc945a532ddc931727b79074c0fa824e53ff3254ab28deb153022c0df99e23f349f2f7a5f24d5ba9e5280a87beb93fe3ce5c8af3591ea26cbf04	1662914915000000	1663519715000000	1726591715000000	1821199715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x09db00a952586b124172ab7180015f738bc6eeac378a699715f082ae9356013cf8d8e1c21cc5f5f2bf32657ec6181a0943296c27886b3c2e75d40cca7c726db5	1	0	\\x000000010000000000800003cb2fb1c5bb2701e74b541d69b1138856dd2933dfbf95cd27b1cbcc8e21be3575b400545316a492c602222a92354cc93d4c5a977e17ec51fa5ca49693aa70f21b7536159de9e1ce4151db3a4200d0fe6e5243c1896f7749cf13bdbf711e1d526990012ad844b05363c8f5b5e68282faf0d1c3ec1fa2b8d62a68bfaf6ac272ae55010001	\\x3fe4fdb153efecbf435b36555847ab8188a2f65b4a3425214e58a8c811d2d29ca6d4c1b0ff4ffcff4410fecc2fe1e0312dd0abf8cde4d2d2f7d05951a7005409	1675609415000000	1676214215000000	1739286215000000	1833894215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x12c39531729eb9eda1dfcc2079e5dac47dce3af4dc6839c2e95da782bf47c33c23a56b2e1768aa954d129cd17c82964efe939b0f66e34447be20695bfaf0f6fb	1	0	\\x000000010000000000800003f63f2913e1b1b3b62204d5e27a2083cd3fa661f336b8bb742d4c333af7b95352dde74e760d477bfc959d81024ea5c36c948c6a778978122168793d6118492cc53dc51f1f24ef419a26841a6ff808cf2321fd4ad6c1be65d5da10298c7c47c0977a6e1673e4cf9ee23cb8caecdb904d6a3696ad4add147db22f4ef2644c12c4db010001	\\x3ee0bba761ad8d750c524b0ee3b3f9ecc02dfdcbbc33fca4f29cdb897649599f7d5f54226bca2e682a5e81a68e1a29ac5dde9fba252f167e48532f818edd6501	1688303915000000	1688908715000000	1751980715000000	1846588715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x15070e130c3bf630c31aab5869d04ee775d9b83969d1ccdd49bc9c9e8ad4f4a6280188aac1204fdc0c7f85f47f4208fff82df060584185e6817f373b695c0193	1	0	\\x000000010000000000800003bf8f648df4412544677ed8eef40d2a90c823819ca9c035f8bec10770b45edd1e9765698874b4e794c34cd85aa7e36d12b07ec85f52b718a6116406ac499239cfcd3d2768a245ec8ca824c85449b1b9ebd686bd9df0a49b1fe9217413dee8cac3a486cee7dda7c6888f88637567a7020aebcf8bb34665376c4b9eb366d338d6f3010001	\\x02a56113c2a0deab7df28cb9762651a3811eb6813d16540065648e4b4cb50bbc4e0ad4960724fd06b3503c26f5c4284168e2e94651694c892f5b683729784c0c	1668355415000000	1668960215000000	1732032215000000	1826640215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x16b30e2019c8c88b57a4702395e52b1f6d018fbedf8b02c261dbef16e35baa37fbb745a7ce14d79eabadc552baeb4b5a38cb617bd97f00cfa55deef244fa553f	1	0	\\x000000010000000000800003c6f418548c4a58c6bb40cc8f935d480587aeaaa42c0b73bb65d05b66baee2aa9718c3aadc0476681e698df462c9feb49603de0f5618d3d065e7edbafb75a3f0ad5c3a88963cd44487c903c19bb612308bf44fb7d7a73ca9220e39b232894c92c90e33a728e23f6868ce75f33ad59cb98ba91ff82a380726621b1c02e447df7cf010001	\\x6fe64fc0c556ced5479806e5819e80b2c2e10d7730f48fff6e7d78f13d11ab4743bff1af3b37ed51ba02c96e9dbc7cb7b23b6960f21f2f0f78aa577745f90f06	1669564415000000	1670169215000000	1733241215000000	1827849215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
328	\\x16e7fb56fddda2bf32503dc2f53d6bd77022a568f4daf905d13b95e2eee8a8d1c8cd11d49636c4b580e0336f771accb50effd8e866fcf8996b0e7182e8e351f0	1	0	\\x000000010000000000800003e982e588b79b46b277fe83f40c94f65b9e3cc71f8a971af7f3ef9fc64a15ac8608027a579bb14a6c086bbfe14a58d0e68620e88a2678db612bf99734336c7614fd98fba9f04101c36c86d79ae75912a21592e06285e09d745e22b6a3faf9c541b43f54edebc967b41baec348e5e0a2807782228b556221121ae73d48b088d5e3010001	\\x6b0b20d3b488b60bf1d2a0603467f25e9aebb4e2f7709de20937285df02ffbc70475d4ffe2ab1d6b64e0f4cb780fb5591b9be891038963490cd40a2d0ab8540d	1661705915000000	1662310715000000	1725382715000000	1819990715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x1853536affd5648905a022c8f48b0e65e37bb9e752d9d3b9d68b3e76bf16dab5a93182e7922fbfad28040f3ef1bf330f1b45c9c84d3ea96e9dba1f963923f053	1	0	\\x000000010000000000800003be60dbc53c2a296a1f9f04524a6fccf30ecb7056859f48981bd3820dba57f6e61a73d2869b7e493bc53dbb80a29a7613e215db97a9555acaeec7ce52bc58ed344e3e18f3e284d45914463a564f40c132fc61c63a613de43a8ff41ff786a39f16596aa5adcb7dc0bf859aaa7b0f2cb4e620974dedbfd7ea5f0e3f710c169f026f010001	\\xa5417012cd061bd1239e2b34f3326678fa9d0fee7831141c90e69a8daaf42fba8f9218d4df4362e7bdb3979c906fa90f23013d131444f561030df11eb8448c0c	1675004915000000	1675609715000000	1738681715000000	1833289715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x1ccb7a677ce4321fcd4301de73861d7b9a520b4063107d873e7802ab6a879825dcc044166c0087f77576e353350e65b26d08fbfe9d0d1a7d2e1cf45b8ec003f2	1	0	\\x000000010000000000800003d8aba9e5682bcb033c85637ed1e41ce4dc899745b5a5d05a4500787ae3a671f4e36fdb90d440e4bb2be39fc8769082f1949e540b8812d0d922efe83def356089c8e0c3efa45fabc51432ec7d826c46daed28f3276e49e33a1ea37c799a0cd4972a82da38a1e4aaf7b124eb0a6a3fb02f525a03c80fbd69bcf1fc915c363dd3d9010001	\\xc934730778edbcd7827829f71809c2b6156fe0f240aff325e3c61655f0406863659f4b863ae76f9e3606192dffd5f72f52cc0040abb3d4b17087c810a8858501	1682863415000000	1683468215000000	1746540215000000	1841148215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x205b98346e132ac44b783f76d8f07034d05e5ddda83d422a8258dd444adb064092221578a52c6b28256d8fa5b51f695faa083ca834568b7c2f08b4aafad9b91f	1	0	\\x000000010000000000800003a9fc90445ef5d1f376b3b83ffa526341b49d98d6f23bdeb51c0a7e3f55325bb43bfc57be4664a27c21dcab7d218bec39bfa7fa9fe968bad0056c336e3fe66f29fd2914e23f9ca5260b1b0f5cf9184627e24ba10b27a7dd26599da5d6f76c45ebcf556566bbdeb90ea6e389935060303f4c5b7cd68558ab2c5e200f7f4db9b9d5010001	\\x8f9840ec7278989eac5443ce596f7b420e1451b8c301cf94ac871aa139d50914ab9983f94add03ab1972137c380a3c9007a289ca9b8e6301d9a61c800e3da403	1671377915000000	1671982715000000	1735054715000000	1829662715000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x21db0fff50c8fce21697d18cf475499b26da9e241f191579da23c8b0684b033c7d66e8c4f54f4deafe273979c6fbd5f4aa6735e810f033f4ce0dfea7592c96b5	1	0	\\x000000010000000000800003dfd735b417200f3def256d43f0a7898b539d3d096450f7fd43fe8d60c3f153d83761ea65ebabe80817ff51cec08ac65f9fe117384a532ccae93f6058a7d6c6b2ee409fcd61d5fd6585ba019d4521db2cb8ea48c860b0a9f8408ef01ac6a3d430bc548e0f21793295b7164d9ddd35aba520eb516f00af0c005b07aef8a73a9555010001	\\x3c80d724b2c8c9ddc1f5df90b73e57190dd46560b49a194c867972b47a6223bf7dd344a2451d6b3a5e69bcad0a9115a7f9faff31e7a41ebc2471b09b29cfae0b	1661101415000000	1661706215000000	1724778215000000	1819386215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x22f38447460f61fb889fea45f1012f4f905ffc028175b65b465110a06de3de0851833b361dde03ec6fef4d69b6c4264ce7bd7e17f3fb7ae78d46394f58851629	1	0	\\x000000010000000000800003f1d35dd9b33c79f1227be47ee92ac3b0715a6efa6b4e1ab98c66e97c3ef063f079d99dbe433c3d0232d0c9bcd15167ad5100f02eabcce8fd677b2a58ce95debb47420e3bc27908e5633c071d538d99c9a89fdda3ff359da3ade2e4800a920b84c8f61c37a0c63861853318471c23966f3205b7bb4d517e7676060780d56324db010001	\\xd7237eacb5fac2bc638c6fccbc36ec577850312805f0c4eb3bf0140e7f67d1d2fe8718ab03e7297615cffc12f5dad9b047d1d85aec84db10cd10430289ca3204	1665332915000000	1665937715000000	1729009715000000	1823617715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x23cf18ec7d2b4e182845babdbb2d0a3a6f46d4970bb467f1024f98e1398d715740bda31926074beae0511836556eb0d830acf92f9b53fa31f8bb69a717a6b5ac	1	0	\\x000000010000000000800003954711470c237e57eb31ef12090b9e090a6a81d40e474e8cedb746db73724b6f2e4df0e5d2774de3b2103a40541718d856f310938d013575fba4d676e9f77a9a43bdf75a6aa6e14ea56d163ea1e3cd71276cc00b7b8deb404d707ef25c8062529cf92b90b5dda139dd7b036ed05364160ff0442ae1aedb124c474727826b6b51010001	\\xf25dc075518968a9416114c4cdc7042544b9ad4ceda69bf8f3e97bc14e9fcf8eaa4266df121aacbba64c389627d664a3e2e60eee74fb4724a78e88563671b803	1660496915000000	1661101715000000	1724173715000000	1818781715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x23e76e3c5808bb41f162eff423db6fa8e7ebb60a66989ea6c02142e621fc41e3a5ad87093603b6d10c89fa0f8c8b105ee6ce58b60acf2b5c2261bd6ffa34b81f	1	0	\\x000000010000000000800003fb7e924d08db14d035e31e15856c2bdb37623b95b13401559e80851b223018d79edbd9cdc32e9dee2995c4aec1fea3558fd07b6f9ab1fadb2d6c49b64d3b2f0bf84bb9676b7c5e25bdad11865036c1f5cdbeaa93783883eecb656b8324f897af0353c053aaf86e00b53ebe70ddb02e9db804f9551799ede134c9c36aa0dbdc69010001	\\xc89ece89e93fa378f5100589717eff9c7deff386698ccc273995f289b05fb2e6d9107667cf81d2506bd79c910a4e5fd0922a41d03457f66e55e28f4420a7020a	1679236415000000	1679841215000000	1742913215000000	1837521215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x26c3df60bd07b8769e120169dd87b2b2da7bf16c3e0a7d2d316782a5eb909763ee7b8c5d0276a4533dfd825e71367ed2dda68dcea420c5c69692120b166fae4b	1	0	\\x000000010000000000800003e69020482d910c569fb5a31c070c1ec0590f730a7b1cf1ab523a36106e96c0262eb28a78a729f2d99ef45129b2745262a4d833019df8a7c6c5d5bdd4cfd61344ab7011d5a10377dfe25936affa3625910c1ca248e64b6925d5728604382772c888185104656f8d55d2e87589e10c61dfed8eadc1cd80d6c4f6489e79e5614acd010001	\\xf727073756225ea6e5eba7616c4210462e77ce9cb94e10b8ffc94ab0e701cb7ba0b2f3c08c400c926d18b940c50220643a6728ece0d98cbc80a27eb3539d6d02	1679236415000000	1679841215000000	1742913215000000	1837521215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
337	\\x289b74c618744d20bdd6cf898b791f7fc38451c0654323ce0e86a1a7f5033c691f472ad17afd8fe67dc8bdb6baf40f41deb6da14368ed09156a5e5f32ccc905b	1	0	\\x000000010000000000800003da66b3f0d0f809af02236bb62801c1d18566835d98c1ae217dd82baae345b31dd6cd306a3f35fcac4ceebba369a7da029285ca4149e36d65a0b85468daa83979fb99e422ba61a549a3a12565bba35bfabbfa0a3b1a649661e8a4b1c4d969fab0379685ad4897291d866e541a9530fb3076da5d695839addc6e0649b56c0fcc4f010001	\\xb1edc583c6ca2345e64d5b0393283bc7c0828b069557fc59d3df51ff239ab9da11b9d8ff4d9115c80ebbe43c16381741b740189dc8b5d4274653c54e476d6909	1685281415000000	1685886215000000	1748958215000000	1843566215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x2e6bf2c66a316982901f9ad023bcabf5ea94155bba8618d734a30b6cff87efcc0631474f83152defd0a28f16a5fde4fe3be5e3d219624e604a8bd8495096a359	1	0	\\x000000010000000000800003eea493d9067ab648eb2433d55b64a8255aa3012923fae65f6ce63c7e6bc0489a268dbb2692086fd43c110ca75b48be26f8c377c60662b9f55df09944712590d20a7963072c393e78d7b7bbc0256c5d9d67e1d3cb0eb595541ec80977ea8d84db7d1da440c67c806ba1f88fd88aa93d2b98526d02121968361f3db4ab96f39db5010001	\\x76c919a3c0ff19045466c790e7b36cb61d6a94ad83fa29578f9df06bdda37a946961ab7fc3fbade841a7f32c6729d4cd22d98776df398c659de66785db8e080c	1675609415000000	1676214215000000	1739286215000000	1833894215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x3607b4d7c8aa22036c9ed99b1493dad79b1684670b82b81174cdfc7da4d87730bc01e0ada9970e3d49b10d44f6ecd935950f665ab6f7c8ec5ed24efd79d05712	1	0	\\x000000010000000000800003d16b8feacbc2ff93c28f8896bb7d19e35e095a8dfb449222f45a46604aafd3326d15296ffce18a3df2c6da4a038372709489116ba2a6bc78ae0c91607909be88fc9d2783402b3dfabad31e472f0db3941f0fc3069fed1777409bc33af812ee3d50fb9ab704b9712d773c4c90450954015b84cef290bd7f31422edeac23ecdae1010001	\\xea28d0665d1169ef072c30995b5afbf4c3b6d4c4442a2b76b8535e0e5a8a78e939fd144671dcbbecfe4649b0fced0ec3ee8bfab28a21b42501cc78feab83850f	1680445415000000	1681050215000000	1744122215000000	1838730215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x3653343ebe1601868fb0ff32a6b9c69d11905e29e288d938ec5df58f6a8f8536c72eda6b008b1d21ff3af5e181316bf43e20311a97bd54df41dc15a56f13bb9e	1	0	\\x000000010000000000800003c04c63e5abe53048dfde1aef88cd0f41f4ab9363340653d94624faf9f1fdf03bbf16bc70d35f134820c2279c5a680790a47ba82ac75a46c7ff4b3091aa1674ecc26849697d4207ac1fa948df76897a77b9d72f56e24482bf7ab9caf91e161ee66bd33a87bf2f001cda8fe0c87557d481d6e665e91ab8dd0b4b0333167fc9802f010001	\\xf3e255cd0efe83de637bcddb1868d02a5296657b4cc564f3a222e8e79beb0f033c025915a400ea7baad541adce5dc28f19e31de53f40d698383961966b937503	1670773415000000	1671378215000000	1734450215000000	1829058215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
341	\\x3dc3919ed603043ef765138971a5d14e550dc121f7a63e2532628096121923a4a85b7e7f8535f461ff535f68e016feddb76d8e9003e94f49df7645748f733273	1	0	\\x000000010000000000800003e9be364e78bfc9bb1a17ca1e6cc78c3ebc05708259ed694e0cf44f9b2cd81149d10e924016856554f81a62ab29bcc1f79ea442c28098a2533b16e2d3c08880e8b2158477445b205c41f4fdcf0f75002e40d4e4b1fc0cb86492944c6b13690912deb41ef1f16a26f13688522710ab2411c06bb2436c3311dfacdcd127da6ffc75010001	\\x9383c4937020e70984f4fec30b6ec8ae936d68251f1cb57dbd080389cfa2082a4956b4e552c9a9994580d01695adb1f8c832c6fd36260f67a521e9929bdb650e	1672586915000000	1673191715000000	1736263715000000	1830871715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x429be2062f983adbabff165b879b1bc588039deee4ff27aa3b8181acf4b45f8db1eef1f545c55dfbd23ac001a4976ff0b569e07b5fc2b786fbc2ad61b4192a25	1	0	\\x000000010000000000800003ad197e005559b1b1dbf633d3368fc388c21df42c82b9f2eac11f90a7df7b00b3c8b558aceb7a724469bbf8b6f9ee799701e3ff129d63ec014e664e2a0c121cd1a09203c5740315654bbbc73c159af9a7175221314f232e86ea5b71589fb65e017e07d8d8dcef2d5e4e9f6e0a0628736c2a13d792cdb252b9657e9263a274a243010001	\\x31c73860a6ed986cccb05c4b548e359855fc68dc3f0b8b72149eef0eeebe23025c2bf8c3f4bfd69eacf75a4f0fa565c74990436ab1e46464ebd75836e9cc6b02	1681049915000000	1681654715000000	1744726715000000	1839334715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x434b351851c29ced671a7e9c5e3a2af158d30e6488711d7229f4728d6ec580fe43d8f8e993a46cc41e8c4853aea3c5a114e8af016e95375801d7bdd545d242f5	1	0	\\x0000000100000000008000039a43372dba48d6a441de622e5031a566aeed31f92ad8bd15e2f3bdc16eeee5f94dfb34f201f1096c001dc25aaa34f0909f25819f0cd527e1b979fbbc7558b7954acf9680e8aaec5242931106cb76225d427b41c57636c9403d78564bd1c89aa0c27e0b494e5cd1fde595ac312dea8d98c984af8e78c2f9b5c7b69b4406c2c893010001	\\x285709b91d8e38442915381c65e75aa9c73fc7040d1304724e21d7a2f245aed0abf40cfa9aa92b0e1bccb37e6a6e17b4075aff2c020639ef73aa225ff1a10e00	1665332915000000	1665937715000000	1729009715000000	1823617715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x468383724952e21b841de019c4e22ed270cc3400b9640119128f528e86f9ae310c2622222281e73d183061ef404f6735e59d744cbfc4bdc3c189f8e4ff911e72	1	0	\\x000000010000000000800003e25f5581148cf3a6d2fc7e53c9c5b74b32d28dec342e18b917a9c958dc48db1e5cf04a27d5fd7a1459a87730111d7804b14d31ef7538fbab731159478cff65048d9b0b1b41494a48d963c9e75f3a6f8508987d7a56986c1ac988f3cf71ab41ce3005294800a3de281fdebf1656d50d83f4cc054fa09ad0e97b6c6244b5349fb7010001	\\x60cfdb38f3e34f53308ea9093a5f354f41e8723be7b6c80397ef5519f99f8a3b325f8e706b4b9ecb2a41557b923480a38bb52239e4f42e560c7b94321b22ae08	1660496915000000	1661101715000000	1724173715000000	1818781715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x4ab7049a85dbeb09363fa73367ab0b3e813da87b54b2e5f73b2d5b999fac8a0e0aae0ea2bef4395bbf63f533d8e1fd00ccdd25da245358a7b2d3f6d66c5c8953	1	0	\\x000000010000000000800003bf656009f9c3c5f6da3e18c398654ff2262b61a14ffff24dc8ed2c352f697c1a68e31c89c2bc5b10a6884b3c7b936f6d75f98530b25374f50155c45d04c4034a40f7be8a84be578c137175c0e5adf3d21d70d666afcd898c96034e1df67c127097ce8063ff776b06f31e94590538d265bccf22c9049da16d4fce71a8550881c1010001	\\xeafe94881e318264e829a63800a3a174dbaeed4c3c19edfce4bb0de181b8c0e2023704c1beb143112b094c035653ca7b95ddd69b74b8c49f72a9d138355f2b09	1679840915000000	1680445715000000	1743517715000000	1838125715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
346	\\x4dc3b04d6a489e9b23fd64714db275df4a5538c965ca6e0ba12fe43666fdc7014515564a7479cac672c9827bd5d90496e45d6e9743d36600e6bfd97424927f0c	1	0	\\x000000010000000000800003926c60207c2f0db8482aa0aa4f0768c3dd82745e17dd391be532894e62c985c0896509738cce665e911cfd6b74d5833f33cc6d944d3df2449adb02490f22791b837952614871a92b28be776d1df9677bba646416f5b5e8c1ab0f629491e6287fd90a0ea794f1ab78660082353c402b31d2f83d7886ab076207799794964c01a3010001	\\x562b8beead6530207a97278061c45d993bd9acdadded297274380be9e0d6ecfca1ab1ca1fbc0bdbddf05416312cef031c0874e1b012baa4058b222145243b703	1686490415000000	1687095215000000	1750167215000000	1844775215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x4df3a59853b733c09017d835398a3349023b25d95c3a0bae1f38c720360252ec6f55dfe8eb3a99878db4cd58da45331a34951f22bc6d2835c03740a8d423afb8	1	0	\\x000000010000000000800003af72cfce6500088061cf7cd60ea5141c381f75a3d26f7a690ab883be274563af401cdfaf3be9b16913e9bf6a37149de7294ce89f1027b0b7b1f1a3cbd9e85a1a59ebe580bbe35669963e1d4f473e8c10f9ddb6f912db5e7017f4bb82917f53b6ab9cf324c252e1b76d898862e720df137ade9454ddb6721c8d4101940d08c313010001	\\x8c724fe74ca6cb03a8fe07d089812d2cfee16c0e3047767f5b7b7374b181e3dc05359230f17f7dcced577a62cd90469fbf28128640a28dc6ff2b07e6d1552e0e	1684676915000000	1685281715000000	1748353715000000	1842961715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
348	\\x4e8f212c2b81baf4dddb28612fa24fffe69498fd25d7b248b5ca65ba810648406044e0e9f023e0424e4ee5cddf130b3fe52ef2f5a134afc30387efffdc3415f0	1	0	\\x000000010000000000800003b6e494c4a13a1ae7ac539c6b4ea2b4f9d19d3b161d08d19e3f4a663b227803fd315dd3e02ae17e241f53a3f0bdd6e634325b03ff0476a6f9dd77669278f31fed38ebfbda8a6b1ffe5bb7598230737a319ad59666933bd8e76312200ca118a0e6c3c704fe099bc66b64558b2c2c7cdacb1e7758564bb755df868ce8203aa2d54b010001	\\xe65f77bbef480a83a0071071b874f4eafa81ed047b03b0e82bf3c569c637b168342e5a2ac10a47885868e163e9e25848e694cd9f65d7a8220988ed72fcfb920e	1664123915000000	1664728715000000	1727800715000000	1822408715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
349	\\x52136c5a278a7135396aae4cb866e48a786fcd9f027d21ceb83f7b2f894ff51616bd389189985cf6489810710a526f2143f4bf5c5473e4ff1b9efdd1b9dd871d	1	0	\\x000000010000000000800003adb72f6705391197d5601f6bbe0cd348a8e7bf7f992a230cd97c96b84d0325a2622643724ed79696a405e7512e8dbb06af2cf870adbd52200a896adb3be82490fbf5a8660bf5c81121d3325f19cf9bbdbe69bd1d868ec86b21adb70baaabc1859c1ee109b991cc936e7fe130aa247b5372417ddb0b5b8be2fa8247935a09aff5010001	\\x7336eda9b4e531067380686353c7a8fee81505f67754f5a6c478fab7a6ed69e7ed41b44bf6ab321ab05f76c7b30dba8cf7162adcbc3b7c324c0ac4554d110f04	1674400415000000	1675005215000000	1738077215000000	1832685215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
350	\\x52777c55d10ec2990f4275f26310cad6dbbd5adeccd0633d5cba8d45cfe35ba225e82c2d9a7934a8822a7d59c6684d1576831d009b773e702bd929393f38f069	1	0	\\x000000010000000000800003a6429c28cb1bf7b71b097d0490cea46c427fd91ab5f223b61ebb90d65b60d7c5049b0fe406d40e744a722c08cbcc8387c5fb232b04fdd7a6e27e7e1c65d6d7cb4864099e8c64995be82c10dbe0f80075b915949f61ceb309883aa6445a98779188ad4b1fd02096077c003d3578645aa88a908bc130ab33644f9cf2134444e487010001	\\x4cbdbe2b3ba0e0ed8ea7c5d9550afb526538f35b69d763ee8054a05f34e7ca36fa83e30f351405a90ffb86de85022ec2a039b61dadb071036a5c167aa43ff806	1670168915000000	1670773715000000	1733845715000000	1828453715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x545bd687345cbe5dfb4e15a6fe17978bc266d88a228390187a45a56b2c7c99ddc37a8e5235b86af457d305fe56c3a13d946123e4c7e900193b99191e90fe1625	1	0	\\x000000010000000000800003cee50b186bfdc2cb08fccd79cbdb7eb3f01da060d057af4705e8c6fd272d9c33b1691396e0cd154887a84d960bbd602a0eacae39db21aa02a6967b1c3ab44e9c12e989b929257760de0a836e3d316a5239e3f9f49d5065b5d1f704df8184ea51f264d1aa25e4007c858509eadae02a3dea2f4d4af85a718e60208d9b80215c45010001	\\xe6fb4495c9910975dcad72387f5211856060e0197d22ebeb8c33043a187d3db3c9a946356b77e7fb9c0d9a811f0370644a8a5908052b7d102a14312f6f395604	1664728415000000	1665333215000000	1728405215000000	1823013215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x556b501361303b0577d5e497f8c85f3e60ac8a54a8a78e298a6fff9799b980776d74931b121b40f78120e57567429f31e648a7572577a9b00640d83f05fb68bc	1	0	\\x000000010000000000800003bbf53ff1c3bd9320efb734da2f01acb1a514d43523c65bae00c2d51d7458dfbd45c82a453b036a35bbb5c48e1d9da0224f2f555ecff45c8bb9bd0edbf1b1247408f8eb17412713d45b66907a48f25051a3c9ff2ea6a96fb14a66d5b8f18ff14894f7ee7990ab8ca21c02e93b55cb2420a00f084499ef12752ff00708ea391507010001	\\x8c38e07aada8d41769711d14436d19f5e433a95d0a3e9b2f71280dcba74159baa3833eef5a01f63bda4c727e4e6566fae22b96b6c15fb42b8057858ef7435100	1660496915000000	1661101715000000	1724173715000000	1818781715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x5607945c0ed92459c38780423713686eb73da3f1a284f379b8d31cb4a644aa0a78b6d873066eb147bd1ffa52c5658f9ca531436c262bc95f54dcc259b0ccb8b7	1	0	\\x000000010000000000800003cfb4cdf174e9c50cb03a97ad43c208ce7da7a9190e9a0c24c48f010191b4c59ec8fd79712974305ba1e364c861f596d0256b5ebb26f567763f3e72ca6f6c153f3420acac5e37222c83daa6831e6014d960b932081ec28c1fbbd05274322497502c6c90e84433dc2f0c279404dc4a781ac94b65e74b0942b813f136e1896a8b4f010001	\\xa545efa088e84c771e5bc6740c0f9bfefba8c1c1447d0c5084371728c80b57b86a3b6b2a76d091dffa890855bd62d43775a679d2fbe1a512c2d4d5f7bc1f9004	1681654415000000	1682259215000000	1745331215000000	1839939215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x586bb3467b23c665da96e6b632addb9c8fc4d6a23d37cc556fa5255d740e7a99ba4ba888e34e6cf045a283f73c42305299e72cdfa7f6e6dc5c46e5a4874787e2	1	0	\\x000000010000000000800003a7fcae5b48bb52b895c9944c4e2794eb5340720149ee216ff97db3403adc521c84d339203f9f27eba8e5137c57a6b35cf2c22f67f98f6c051af043d50f782732842abdbd6997095b8468770913ce1a6fe307a2afca546a900ea024749db300599fa88b21561a5bf6870109d8d019b6732ba059df14cb678bc3e14d13359e980b010001	\\xb6c75efcb748bfe7b3abd1f38a330bf6c6d042124179a8b2e88871e20b140937186998699d38da23337919e5ee8480fc704600e8d050fc3dc71624cce0651502	1683467915000000	1684072715000000	1747144715000000	1841752715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
355	\\x5c8795d3739186ad2c15c2c0a94ce5c88e667a64fcc5ac40e6870b5eafa9647e1da46cda97fdd9561a93123df7cf90e84c8c55a20107f5ca4d30fd3d1880e6d4	1	0	\\x000000010000000000800003a4e37331479ae53cd8bb835c0b23ee6d9d52d219f49ec23fe705884720e6077613c4fd43a81fed0ac64f70c6777636730700ba8ed315693d2b38de0cc156ec61df22c28fe02b0f9b3d6ab8f90e5454192c6b53df5be8a8d32194f7e1e8504359fd925428377575f99f257f66cea636f4acbaf08e9a409b10290af2235c30e793010001	\\xf296eb2faef32cae25478e825f6d0ffd78b790a1fe8074e032340aa61ca0815cde76185a9952b1b2e3e42b9e88528efe05ae646d48a1672b9a44e637283f5409	1690117415000000	1690722215000000	1753794215000000	1848402215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x5ea34f80580f8ab20f58e9858d23bb029b2c1812aed3bac8e191c2ee4df3846663d3445621b4686cb2b2431be581702a499a4cdcdbca3d886fa832922cacd629	1	0	\\x000000010000000000800003e970b2452a5535c3590c7971c039b186bfd177057745259e00ef69c6ecf7025cf5acb9b866ab6d171a4b71b638f3d7025d5ff932a84fef91ac8dd3f77631d3db7a9ab413ee9a1b80f3368ad707f97231f4474ff8e05b991dc32fca10cc4d39c28e2a657b6730a1e8172de306db571708fedc7b0bb96c8b796ead9cc8e265b26d010001	\\xefb7f7653a40cd426da98dfe5fcd61d2783dafd7c2295dea9883ba900d28024dbe1bb4899aea6b8896ce7eb598fcc27a6096f5fdbc0ef84c5b6e6ca36718db00	1682258915000000	1682863715000000	1745935715000000	1840543715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x5ffff896bfdf8114f978b68b8819cc244a0b84dd7c433cf00f4890e1bb4d82ea696ba88f5ff39dcd57d27b8e40764b63ad714444292bcb02aae34ff0f3f521ef	1	0	\\x000000010000000000800003e69be363fdc64facdd0edf1dbcca98471947e07e9132b056b1e9a5a30ef6a54e660493afaed34fbac3ea1ccb509d508172a528772a247f7705e93142cc5a1145a58a3e88005b81f47771a922f6d5a119ff1236907897fa439d9d8bec9d85899956483028885a282d6816bdd011a8390027ec1c8374617e9f1d8896ddc94143f1010001	\\xf59a3a52c99b4eeaa74dadfc7c49193dd5ee8f54fe0ba620b21ca1268c5ee81390d77194a9ff2d97147765e6d144ef1589eb7931c718ab511e06ebc09fd1d906	1687699415000000	1688304215000000	1751376215000000	1845984215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x655379492880ba173c1c88d506182e74bc5fed8290b6bc936ec23a867965d42720e49df8a129d70b74b664521a81899a52bd07c3c82e890e3023bb378722bc8d	1	0	\\x000000010000000000800003d8c695e11cb53011fb576ef64d15fff0d5277d492383bc7216b9adaa89d48052811d5c0b2f71f68c01ea29faffcb4e09de65b00a5cf0ff3fccd3321b6a9177c9adc3074d09fa3a4e2b632c3b3ed8137950298b7842f4f1f8234788b131fb2c27253ad25f103856fb24891bebf1fedcab09c5d743b8b2461e251ed07a3dccaae3010001	\\x32a6449ffe1530eb687bb5be8922e43f3128ee5788ab02f1e04bd38d06e9251d4d553639a8ef0ba78204ed5aae37c4b23636b225b554e944285a047268a6a604	1682258915000000	1682863715000000	1745935715000000	1840543715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x69c31960a756a759f17c1f958ccc794532ddc0998269cd0aefc3d0e9c5ffa624a23a30367315392257361b3d57de4a22f11cefc639a01e68ecc34b5efacc4c59	1	0	\\x000000010000000000800003ced5ded8bc89a3f54b95cc491003b176f1204249964daeb76085799bbb55fe3211be8303ebe7e3115527619b8ad0db6da173b7f567ca771555787104755cf0b3b52722f42d91583059e4fcda18a5794305ed04f238e5b3be30e9e2ab8013be8767d85826bde89e1d00ac7aa3fdf712b4eadaaacc5f5da608e884fe999edf04b3010001	\\x47226e47ab5537c871df51118813a6e63f1af2c3e330047dd0515f8001c7622e86bc8e3ce37cf904c5bfc4bc05ab8ea87ad483463a06266a0f9fd6a44b550c08	1669564415000000	1670169215000000	1733241215000000	1827849215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x6a5b9d43507230323e0bcc723c41b7bb28ae67d28b81afca413a18aa4e89ccee3a169ae203c0410a2340c7fb88977a5adcb8c21dda3cac00b874a4ae36b6d4b4	1	0	\\x000000010000000000800003a78a264fe877842b548469fe8185b04013a773dcf3d65e5802bc71e16b102c2c38053226be1f452726d64c5054b65c741a5c48722ff2de0a16b644dda743a67e06b2f2d5c75fae6cf848d2465c7c47752dc13e20ef3b4a4243fa20f8f5a13178374dee1aef15d94279e6ac7b98e1ac53456ee3ce7ec602e04df9629971cc3bd3010001	\\x753f4375e12977a456571496365471d35dbb5c4921fd5a12f51b81a14458bc97b212b8239576985c7a2c2cfdb4af9614178d3141e45aeb8eb13ad8c57282ce0c	1667146415000000	1667751215000000	1730823215000000	1825431215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x6c8bb2579597417c0fd3ec773dc61cb80a4f5864decc9ef5f2055026643797d71f40921d4a2a8455d72ddf16414c0735f33629273689efffc3aabf3e84f25778	1	0	\\x000000010000000000800003cf863930254fb4bfdb879b441e446d242f3e09640f808efbfdb3cc449d9719c1c09facd0809c5ff87965a065b94000effe8b2817248800702c876fe008d26fafc3b89d7421543625f937cebbb2bd67167fd93f953942deca0287c22550928c715a84eed35dcd69df78a66be003ba6f1dae906b2f41ea04b49adf452af16152bd010001	\\x77f8fe6a8d4ede8b19ca81e0393b4b8ae69e6719f0e08c0bf6ec3e5db2d27f6c07b0aacbb9549277a3a28a279700057a4000c992757e4824b0619597d0aca206	1662310415000000	1662915215000000	1725987215000000	1820595215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x70ff90032b024d0c2d0db1b331fb54d4b2fdf142f269fffbfb87743533e4549e83f6652618c976059176b7dcd925250ee61ab07922c451908c94fd2b9ec90e63	1	0	\\x000000010000000000800003dec1f0d0f28d2ce17cde96ab7200bf1d35fd167cebd75419e6be64936a63956207e4111890ee893735c4d1ac8c8e492611107a1c4ce6501889393021211c383190f7e399ff3e4c9124772e445a1306732214af637c8a4270913b043a68d6d61b16bd6b6556145e81e6ccd5adcd54a4dab0625c7bf15128a8f4f257a47ff107df010001	\\x5271ec4e9678e1ef5e5981e35794fd2fe98ea98f078b9c6579600f1c0fb3f101f34f77c5bdffccc8272bad741a92085306643dea11b6711cb5260a0525e0f00a	1686490415000000	1687095215000000	1750167215000000	1844775215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
363	\\x750f70c9a43e812e8ce885eaf04baaba102105e6d997e979c9500c63df0408f8840a009dadb1f04c65b452de5b12f0fa3ef4e3c614510f1bedc37094ad8d5876	1	0	\\x000000010000000000800003aa5c1dee854269f30c6757c84b1c93e6852a44c5866f32e580a576409b682ebea414ae4419a0151a11e2a39144a8a989ba20e65f3e73a932022eeaca95891e7bec66cd22f8bbacd409cab84bac4973e5de66daca1fcffeda22650c6e9931a2fb9a9fcbf781575dfc8496197bb04b19016dea51a8c25e5451faa92aeb924f8cf3010001	\\x82dfaa71b2e656278e25e022210fa0a722855c188fc953f9783e7d39da2c888e62eaf44443180419f62a9452d4fda8324a49d43056d834a1458a2f036795470a	1677422915000000	1678027715000000	1741099715000000	1835707715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
364	\\x76e74075cd850e9716056b8a08cae326d1c7f3bbd9685c1d0677ab7490a3bc635f777733131f04a4bba62e8f2634369a536b9d3a0676dbd867d496ccc1bd4792	1	0	\\x000000010000000000800003bddc2754a043b42fe08575036efbea6f0b2551b4c4a02ca16461fa6792171ee3fc792dcaf6379d21cf99b75382c1183d6726da56e5bad0cfd0b10534d225d33c262519e16a9e92eb27d1bcd7d624e4d30553e6c5d9589d0dac5679a29baa141784b9a34acbf66464601d545fcca7dcc9c99170937cf5a05788c47474fd5ff921010001	\\x9519f3f3f9f0b01eda4db462e652da4a5ab0a8d0cf20e137597f1a7146ca7f67899df23c20214be34a84864defedbbc556868fed82e791a50b92232022f6d70d	1662310415000000	1662915215000000	1725987215000000	1820595215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
365	\\x761f67c81efe51082c70cf485f2e5392c4c7fc5b63b2f4a49c3215a16c8d1b3fdaa35e7fb30616b70c617e485c414149863cd155b09463558b2b90f1381dbe2a	1	0	\\x00000001000000000080000396d54720b1088392025d247b7d9ab1a26938e02f23f0bad093fbda743a5b768b298fc7eb683c749dabe3cdf0e8fbb10d5be4743c6f41d8aa45384772031ce42c51cefb128ba292705214e753ac0f1fa4a7d6a53ca123099e013cac852ce16ea93ffcca901c53488498b8cfdd40f8d9f2e2450cc286b4be5bb3305b4d7ed771b1010001	\\x0cabbf2c05df411a2191871bf2af5397ba894826742b1aad9141022604e054e3141a3ddf8ac7ce7430f0aee760e84cbda6c8e8a14577a9c23ca1a67e23202903	1667750915000000	1668355715000000	1731427715000000	1826035715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x7aff028104e4b3c40a1e221a9aa6b787439632c77e164e19e25f7e7eff6ac62c6ac638496a95ec99a8d208a2a63759484bfe996922870851b0b3358d668e08a9	1	0	\\x000000010000000000800003c61c51022b60378f2ffcd7d8d5de3286cc4a6e04eea6d71531a4ba6506a8c333635700af9ebbe3d02a72bd47f1ae7ca56728235f656b011186acadfdcff578da855d281392e2e6ed17583dc3c16f6e176a2afe9306bad20eb2fd2e65d4db287579ab8ccbe442040d5c9032584d931b1dadd04f069dd51c862001f4eb8dd28957010001	\\xbd4ae44e7e18a94d6229379a7e957f7968c47d3cd4c293a151c1fec1cc70e374e5a7a2df08bd45c6d90e73a8a6d232f1851490a8d3bbe59dc1e87ff8774fee07	1681049915000000	1681654715000000	1744726715000000	1839334715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
367	\\x7acf671e1622dcf5281f32150406519b49f1385808b8d8990b35b5b9f8dff5e065016b10d7f1a2cfd3556a6511f9e0262ac6a169c2522327e5e7c114051fdc68	1	0	\\x000000010000000000800003c52b5fcbccd2108da725944beb0e79544277d83283fcc15d2d2ce56a747ae9b2e4f8cd0945a5deb8947dd304473eeb65f5b3cfee0fd9ee7c61cbf2d9758db73301545240fecef951dc244dcc05ad68dc6fc75894579fb98466de9ec5d879362c93a8e682c098f7cd6596fd13cc79283dfce171b6014fdf82af5ab73c56d7b489010001	\\xe98f56f823eb63802a810a8cbabcb0cfad45010c21af96ad0fe53b54d7210790e2353c1c719cfc814c3b7963e67f4c2a128e501fba065b68dbd672f25db5900d	1661705915000000	1662310715000000	1725382715000000	1819990715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
368	\\x7f2fb22a426c998d4a49b352b89f0836c11a982118ae2cd1c54461e8ed14c4656bcbbecbdf92745c1b4b0124e6e84da8a09e4bef6a649a801b4e5e503541645d	1	0	\\x000000010000000000800003d05e1eabfd2543d4a838a54ab1f80369450a0b3bf4e419d9803eb7b0843be0462d060c8dd32e127b491cd8a65842c271a3f9b7645f0f3a5844c75a89da0018d77b596517c6361c2c73bfd95059cb3f43ca9c0690248332072f85d702b8fda0dbc46595521ce5083e3dc8ee8ba10f43b662dcafa7f4a8f125882ae95d510220e9010001	\\xe8047ad2f328a378aaee3143678c03148ed7444faac9421a5dcc84c0828498482b6b36b58da67e62a394c5fe2cdb36b49d8179bdd310b613ede0400bd8e9230e	1670773415000000	1671378215000000	1734450215000000	1829058215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
369	\\x827b60205a6afbb175ee842de7b3b87b7f593397199190952e695f3b9cd21d712280df4269368797d2c1bba90eee6153f416b1d0158bf8a3a31d087da3912eb3	1	0	\\x000000010000000000800003b60c677487884c513d858c07dbc37ac03fbfdd39544c4da4334b8c7ca4507f881bbff34c7057d736a5d19c4c2350f846d2fce6e7aeaa892fb5de490c1f3110d1cc07a2463cc2fc8f5e16fd28a96fba5fae57e390aa263f60b974068c994b3a1e6af7b834247956cc43461be5bf49dd1789870e14578aabc6607ca0881de08d9f010001	\\x699361171948a9d5417a19a3f16efe559c362b521a360e53ee70fcadb7f735daa1133b1103f608c76477ca714e69527f6c36f19a38685990eda0464f176da208	1691930915000000	1692535715000000	1755607715000000	1850215715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x88b70700380f2dcc2f01bedbcd1febceea0a3004b3d0c71652b31f31c4e8255f9a2ed61718d181953ffd79ff3ffc67cc16d6456d915acc224eea9ca00171671e	1	0	\\x000000010000000000800003bf4e39685f37d6574e0efd9afe6185a95290e7bdf6011dbbba18d611f18b1957f72c9cc36bfacaf315eba1a2e36e79b904f85b81580c22eb022f70cfea645e3004b85cf08833ac1f6b702cc5ef718e462327fd677fb5e3a4844a76414126328ab5f6eb0801fa239b0ef8299482e58533e3448c98f5590e03d62fd8391cfa7c33010001	\\x1c29e513434562622a465f670e2dac73e31df3574edf88eeafbe73115567a9ea104ffd0b6f00ddb3737f201d651d76f1a5e89a24b2c0fff8de455c2399726208	1680445415000000	1681050215000000	1744122215000000	1838730215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
371	\\x8bebd5d7e20c8e37919632d415cec49179a44c63501d1be6b6f2466eb37d50d7be25281cbce74332b62d0497e41f0548784f3c0ad8b44c931a5bfb782beb25d1	1	0	\\x000000010000000000800003aacf4e95063844ab539b0097b74485231df50e44e7307c89b42e7d0cfeff50d9d43d49dc0be9a6b8755f8dac1634ee13fa5ae5c61e5e3608df25f00b79d976305d56f1b8cb8500edae2cadb1ba7bbf9ef1bba3959784f9bdf84cb36d435d512765ee5ccf2e6d138693a7a3686152f561f9469903bde6a01e06d23dccb7aac5ab010001	\\x9d14f972925ba26c99b99cf4d5b92b00ee9142795c80aea7b2daf94137f9f10a333f2f1e46821ceb7c0015d6608c75d4cc9e497ccf077cf34173675957ac4900	1661705915000000	1662310715000000	1725382715000000	1819990715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x8bd31a850894c30d05a8a20c114b3847808bdedcdd02760724904620a5d5a7802ee2df23dc323e94372e7d555bc22fd54429584bb330c51792ebb3787c77caa6	1	0	\\x000000010000000000800003c5377b310f820f233298da5041b3c182028827b1cdc0635036deae6325528d62eec33c1bffe94f8ac9b2e50951fc9b87bf3578f929ec42a936fa21492b672afa2874385ab3223a72402833dd403e95b61f48099c1dc1aee6ea86de14d5d8ea986f66b437f37f1ae3b5b6a835fbc3f0c5b81ec41154552dff857f2206c277f289010001	\\x7e827043dc5b45d5e716e42e84b77d8a2199758e5ee1a531eddd07d2bbfefaeba2be775aecf890cc256d90fd6096d6d9e8a2fd0c45e7af4d5493aaee95953f08	1679840915000000	1680445715000000	1743517715000000	1838125715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x8dd393ad41fe81fef066b6ca1c85672aa388feff4d28d57e961c875949bae375eb4544491cf7243def0973df665e929175cfe1e23aa9d37d6694ffc334ed215e	1	0	\\x000000010000000000800003a054cfade282e1113044a817af5f5d8633b045125568482ccbe6005b5d6f081c9b454739f761211568778932a1d2e11389a6211d1036b61cb9b8ea90d0356bc548bc197f9b253850ac97085bcc86892122c9d4776dd7e6ea1380d1111ed9cbeeb67005acd88d537518b316d0c2d15014d4e1c4b6d1236da01df247490b6cc29b010001	\\x5180c0d759b3167e632db9b43acbdc9e4a299e93e4b805206b26f2cfc9ca5619bb11e6dd4100484adf6378eb1ef86c1d0152fb6afc28124c004c12f88e430106	1683467915000000	1684072715000000	1747144715000000	1841752715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x8e838d5ea37b456fc08cc2019742f1ab0cf0f1f99ad2edac14c8c2d1adc6936cffd883ff9dab4e3640de2b565e6d4f9fb486bb30fae24f43288df1083d1acd06	1	0	\\x000000010000000000800003c43d44ca18baf9d4ad5f0c51e42b32812e1becf0268faf8989fac619b6e43367e83c270a00fc77393be867d8f0dcc3ed1fba65ce11b8f10c30a3d03a5bfdf5eb774de8a31899cacf4817649792ea1f3f0645512c8e71cbfc8bcc3cbc750db71ab2a4ddcf8053faed258d09890f2d99fbff8fe52f2c589ea38a2640d410ff7689010001	\\x155151bd81183ee4793cf8b17e4e58b2844b97b4cac655ae30b560456b97b81e91c7d2a4d578d764d7a82eb0fc6c8d9a655722fee8bb52aef99c771ebbd7cc0f	1665332915000000	1665937715000000	1729009715000000	1823617715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
375	\\x8ea3bf6a71fcaa1f87437d9d7e72b156360ace012a9b29c35e1bcac03a4ca38c86bc4d1f94bfdd23b81c7cb60549dd7157558b2ff76c3fac0118fa3cbaab72e2	1	0	\\x000000010000000000800003c19738b25a0e3796ec235a632d6e4a0554b4b75ff165bd2d14bc00c56fea57145bc5523c38cf4cf06f591632de535180a1cfd6875e57966e7de93777119618fbb627002fe34416e7eca5a28291df0d31ba4cd2445f90fd3ec4948c601fcc8b42b290b6b007c2e46018d2656b68f9af23a43b31f2e3f4ffc50ffc97a761392085010001	\\xa552cc0d4bb1d832ee3224fc6596f6ad50e6c445ebec12ad4780fae35f7da315a51fdf88a5364bca65771bcc8cd6acd615a062340fb6d2c0990f882cab666d0f	1681654415000000	1682259215000000	1745331215000000	1839939215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x9027490b825e39436a66fcb57dcd1b9ab5b15694aa8a3df5c24c3fa87b738e49d197c2a9f91dd639ac9716bbf5dec094e46f9ba8e3dc6deca3e7447be2ea52c5	1	0	\\x000000010000000000800003be278bfdde94828106a49491e0605fe107824a1d29794e3a8c37aa63d1b8a874a82ece4fc64043621f7b26c12d1fe7f17d00e827de020f65dfb10a09e0425a1aa20b4333f4fa5e456f283441c7826faafbae264b533326716c3309b550f809d8fe0d0a0a324b7709b1bdb50c80019761919055ce5986b7e062ea0831e402c673010001	\\x407030d1b1a869466c6d35223cc2e6f691a094cf1255c64fad91de0c0b4bf46fa790df6a67d626157ffa7786f1c7562822c94a3f6768dfea716a47ff0debe505	1684676915000000	1685281715000000	1748353715000000	1842961715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
377	\\x910395236396197296ecfc70ec7bcaa8f6d4df24e94b282b57a7a6bedc91b22d754cd4de2986e6dc4d1de74383fd9f93290f92d54ec1d9311088f684ab8d3359	1	0	\\x000000010000000000800003cf1c3238e4ea07dba8ab0fad76fd2ec723cfed6cfb7bdec432bb7ce778be262e34d61674858709aac8ceaa043f993cbe4372f2ddd1f5f51d47fe4eae99d11a6ccaa764880b970795feb5bc2b1608e533f1a7f6eaa52c234acb0b83d26f19909e1c8ea3b690416a4e18eacdb137cde94a681693cb286e4128683add5fd57d831d010001	\\xddc6dc92e2090f53d1cb4d09be28cbea6869afad8643c8e28836429729e2c7b73ec22a5e7bc73beace2cb738da75e56bc3ae2c63646e8bcd54d8ffa99cf85006	1671377915000000	1671982715000000	1735054715000000	1829662715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x914b21fb0b5c2136f14c23b86ca2d689c27ef759ebeb5a0b3d63a692cebd562d70411d3b1c08683317e315a8f026f41ec2e6fac3f2e4fa83eed76a0558f5ce15	1	0	\\x000000010000000000800003c1f6c86bc60a53f1957b8acce6c771245423ccf842342bf803d950116064b378e333a3a155a9b696daf7f3fa3e6c2950e0cf3c45bbd87a70eb0827e7525a1d81197a7702edfee4d81eabfe9791dfdd1a3d3582755543e244ec42d9697f21a3afe34195d5d325c4226cd399f1295b96b722aa2e98bacd7577fe4d6b8702c738fb010001	\\xe4fd8f85708b6635b78bbccb66b26fcbff19ba36205ebdda4cfae97627eab4564c7df78df8606c0f3e9491bfe41f5d9087ccf661db71b103e883b04372a8f80e	1662310415000000	1662915215000000	1725987215000000	1820595215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x94ab5cf9f40932d2fd8888c36131bccf3f78f1839c5b5324953beae5eff9f0e27fc17aed29f4f4c23f9fe171977a4e62fd80c230ff4949480d550028c6af279e	1	0	\\x000000010000000000800003b2620927ef88709dd3558f91ed37d55cf0ba2f94f45ea461f623a526b1714e46baac3848e04a6652bd75fd516c28c6f353ad5c15903a75dff0025d05dd4196020e35fe9e1df110fd84d9db208abecae3b711b23c42909ed8ebe7595ef52b8b49fcc1be62cc4eb90e8ae4c3c78c88c533c28a6aac3630487bc3f1b74cc90318e3010001	\\x26f59805005083491358ee29e0f96b4387b8d51b2ce70b512b2050c429c3cd2937244a9682a9a4bbffcefd743e015baecc20ba6073081b711e0aeb3218003106	1672586915000000	1673191715000000	1736263715000000	1830871715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
380	\\x99f7fe05fb18d4c9e0d843f0d2565e4ec6a69a9af162d256bc1888ac0bc6e749215e3aa4a9b2283d92a01ceb156223696606849c6f37f0347f4693b2b2692668	1	0	\\x000000010000000000800003c26e4fd64631b3ccd35fec75b959f51f348d063a7772734cc7135d45334befaf5cc6eab2688799375881a333414727909682c500da071509c2243a15354312cd9be796cd2558a92d68fc68d8ea194839505f061cc1cc819a5d78e398eeb5d479ae7ce2b9becc6d4f487622effaf3a2ac79982818485da8830badbb7b8b331c0d010001	\\x5cb66f755b1b118490e230fc262341e94f310e021c026ef4b68291417bdd2bc1c28060c9132bd2d669c7424910bb49c4d990ceaaa0ad9772aa8d876ff5f1460a	1686490415000000	1687095215000000	1750167215000000	1844775215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
381	\\x99bfc19c285798bf28bf43eaba71cc850572106e9da21ff8234935315efc015b7bb28c289c44aa34b00d3aedc69d0a035ac41d073019f3bf37b15525b2f28f9a	1	0	\\x000000010000000000800003c93b8bcaadacb9ef7b2238189452880a873675fc610061f914a985fa841fb84292279a64a085417cb9fd23c557f4aed5838311b1f4064dafda32048e8326a5e5651fed513a15f70de12e203dfc60b0b244b8cc74f9c94d3072f433a311a8ba0bf7c80cc5fde1e30193417f4edbb49181cea205e2808e8d721a51a1e1b2b8e679010001	\\xce9731ac0747994a1acc7d2d5cece82d285ea03b7d7551f5ee0ee0db03dcfe1889d3c7ecbfa38998bea19898b747febd0856fc0fe4e45d65eaf2a5fba14beb0f	1667750915000000	1668355715000000	1731427715000000	1826035715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
382	\\x9a6b2d33f80d8b5d231be7b8c687de389047170809d8a1c4847f272ea3afff17885c2ba385fa967ca203de08617a3ef3dc1c8c596c8dce234f06e83c5b097536	1	0	\\x000000010000000000800003dde9abc90199dc5bd512fdf1f22632f87347abe7d01e2def0076d5335f958e3fb86bd80172cd25a57725b53fcc1f2fed9256fee6307219cd6d554ec129d66d6ddc735b692144ba698ff5b48bf58ad657861bce0a21187b133eacebba9b2395fd3592204f294ab9718ab6c435e803d78f0c5d75cb58b972865729d010b3e1085b010001	\\x7ebe5f6b969a46244390c5b915741e45cf51bb65b18d815672fcf66b970347ef055315f023c0b9da0b4199cd669f85fec7dfda0f8fa1a91622fea079931f790a	1668959915000000	1669564715000000	1732636715000000	1827244715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
383	\\x9a27d07a3702b506d11935114d45366a0b1ed765a0b5eea032b9ca118c870833abb3e5cc979128a95febd6497904ef9eca794b152fcb4dd1eacfd0f8a57012da	1	0	\\x000000010000000000800003e143861f7101db336b6c27be8afac7e92176c591a9194501799f79dd7eb842da08c762203a6d76681c3f8a2522907b54d1b37539837bbb8ee61ef0ae08514e9739aaf3c8965c1b9d87dc29c8a0bcee9c18b5702b077eda137fcb38fecd847d629a677554d85f4e4aece8790b74f00cee89e0441e7d9853e631b8e82a21a67e0f010001	\\x7d6c12202c7f4b73182c4b5614f913b7c0a6ba3f1b2bc7556b87316f074ea0908e2202d948e8074678448559d29100c4a86ec40587ffbcf5b26d27c38d2eb60d	1671982415000000	1672587215000000	1735659215000000	1830267215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x9f5f8ad56772900a2b6e3b9dcf84eb1dbab734c240aace3898087f45957b60dbce95b96b19dfa4532b5469c0ffe48043bb3ce7779df12f55316255932ba5e901	1	0	\\x000000010000000000800003ab53c4784a053df2d7720f39e8b441aea54c670b8693bbeca8d19dcb6d86e036aa3e75bdacec9d1a321b34fa3b83299e32e22b78041181842c5108d9098ec71f921dabdbdb16ca3b24eaec468401c277cf43c892fe782a7c5b9adddf24b4326f795ee13c175f71a9fc369bd3dc7936d5c156739ba5e148f946c69209f8662449010001	\\x86b18dff3dc268f73e80d7312a7b7db5efcc8296b43b097c7471d834ab6dc4fbeac681483d58861c38efdc4230af79dd7ee2834caa9751f6c50fc2330bb71301	1676818415000000	1677423215000000	1740495215000000	1835103215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\xa0e3b07c8af80fb72df0674b5f169c7187dc7799cb7dc5c73ccd2827ba20ff2347b32c2663164d1773579b91c7ae7c9a5bf9a76fb0c8deca7b5c107d6c23e2fa	1	0	\\x000000010000000000800003b2a5762dea3b151e51c5dbb0f9dd3ae85666fbaae133bdb4a73ca595ed0d4ee59f0abb30d3f0d61250f595fd7be3f95e5b6c1dd56377ac7f0d9cbf59ef3186875779654054dda32b13ef1a04f9172266173e9e5026586d14e6ec052e4753d348bb34e7424e7ea3fdc40068630ff6aabccb7f2e59c9caa9cd5fa4a068a4fe67f1010001	\\x7d87173018c13a39b2f12092615dd34bad1568d500c4059a157ff908c72e366d34b1bb4f0ffcf9391606fbb486427662b260008e93e69a5e5776c42353ccc706	1661101415000000	1661706215000000	1724778215000000	1819386215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\xa13b00ba54d7ac26dcbd6ff86ed80b0da72d86e198db46faff7209084675684a1278e795d494b32616839fdf5aba6f7423ec89c99b91c823de3d36af81b450ee	1	0	\\x000000010000000000800003bb55434d423532407fca5ade5dd8a86702c35608fa83c8048019c29d50f9c0e42d02eac00c1bcab9b3e0a6830677ebc45c4c6d7c581b42100c2f493a70486fe98389f5e5f10579b63ae157c79eab826344ed2b079d0778270911f89aabda80cf3546671809764faf65bbb15c7ba7155d3e1da135545add0ecf7a83cc09e18665010001	\\x4242830b2433d8db40a82b3ff00f3113a067c45c211af9bf16dd750f8eac51252b53deadd8d548767e459044c381e8575570e0e80f3a31dd3c26adf99dccfd0d	1666541915000000	1667146715000000	1730218715000000	1824826715000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
387	\\xa337d35f547fc477aeae7048d1aaebb9c5b6e1e414492343305216fd692e3b179b40dc1f076983fc0705dfeefa60a510aacefa09905ec1a58d2747396961b46b	1	0	\\x000000010000000000800003c2fd2c27a48fee07678ae54d057565df602a1d51c2614e656b372fdbff1f96827e2a30b44d0d5a33d837f449542bd88a3c6a125579f166051987170cd35a2605a912e3eb5548de0ba84b64511e25345a7a76061a4aa60ece64e954d50ca64ed4de6017ecc8db7efee899029c484bd00f67b0473d48455944b1b1aa9c7b9d137b010001	\\x449cca9e7d4f4b8b149b6fc03fc0adc521fb24ebb609c6a0625e6b58d997cf876b0f4655341c0ec0e423e5988739d7858e9bade5047a4f12c78cab6a60548c09	1676213915000000	1676818715000000	1739890715000000	1834498715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\xa5f74560c9171a9e4ccc6c5e2016a9ff3ba72598b681d81296e45e9dabce5376722b11d120103dbbd1bde4f1dd71b2fa95bcfef89af61b7c2b2b155c5f0535de	1	0	\\x000000010000000000800003d3e77ceb0d27e945809f86a0ce3b24e974c794d3a38dd7511d6eff5f552cc7ef9a1061bdd0defecee74f74c89414062dbac17ae578205403bcb0a7a244e117c7dbcab432305e1358502bfd063e69a41bdd1b69cd65706829c6769d885d95770c5f29932e407db516cf4b70ab3a29891c7bf44c5a064c6a1029d8611aacb55d85010001	\\xaaf1e2dab8084ce4019825f05ce7bd5f800a0a68216c94a1ad271ba5f52430e9998752278dd61a116c704d181979a46789b18f8aad03994c1f1659340c536b0e	1661705915000000	1662310715000000	1725382715000000	1819990715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
389	\\xad0b62e898c686a0d96ebdf5a42d9b932a346acb169c8632d11005a062197111ab2f7603ddf9e985792fd5df526d1e07f490da74d640620859472e4db1220cdc	1	0	\\x000000010000000000800003adbb81a6c2e8ceedaf1ed3ce4886ec494a8bbc9390bfbe1aff2f3f9e18628e8fa411998605d2cee787d044e4ab8112fec694bf9a364cc05ebeab5947f1d2363db8de6760686cd55baa749905fd1ff5f40a1023234977bc1d02e1abeae2d01da4471e9c77443e371188c0a8f5ea0c0e859837f59d9040f705efd67f72fceab061010001	\\xa995e075fe8478860d8bdc87112e558200ee712c930fb012231ab693f4cd2581034c7e82f511027a690c8a658de030f67498bc2e550fdc2a2a27bd5c06696904	1688908415000000	1689513215000000	1752585215000000	1847193215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xaec7579db45463af7006877b6bf802f097b053f5a86801d6a665e1f66e2770af1a7736907fce3a42c6a6062686dfc42a48323746aa28b6f7d05019457505c76a	1	0	\\x000000010000000000800003c2ef058222f665a96d74607f2b34f60bee50115c03f71c8156a9ee0b2de37e242ab84fbd9af5fca7e909709708dec9d5e3d869f53167b4ef51405661a3e478652d12c082458ee8f4ca260235320aad27bea2e21ca0937b1acdf5a52612f0594c374f164364f6c34fb11847093ecae064bff445a4b51803367eb183320efa6ae7010001	\\xb91cf081ddf7a12248a0b028b1c47d5459deba677e7bb9db9856b60d6965ec34e30ef473c9b549cf43ccd72c640489e96d9e5398aad9d5d69f87cb80d52a7c08	1674400415000000	1675005215000000	1738077215000000	1832685215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xaf4bb55a005e21f907ecab2686bb794c82a3af1d8247e75b33d15336c2f7635ea15540df5468a4afda08720acc75a7ef159242a7727f4f06af13204df5e08f16	1	0	\\x000000010000000000800003cb3edd6bd815bbca499ce66601a93a0c8c034b0fcb369410910da9efca4eed5cafc43fbf9e3636ea5d6f156d4ddf86bb96acf03f65c809c30ad28e381a3fd7dbabf9a7e8378a80e2ce295b482c22cbfbb36ef182ea1ae21b86c02e295ed625f418b6d398785d60faa653e957f3a9661052dbbda229d6cedd57ae1953813022af010001	\\x2379b0acccb7b90adefabb747a3a4bf5b0e0ef55d1aa0374892028862fed0a42dadb8da76707c4b5ae9d99eb44f59b9ceeca42b100b6feb1c2217e96d4b0a104	1690117415000000	1690722215000000	1753794215000000	1848402215000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xb33f284c5212544f7cde20e00baa19bbb9fffa53416c83d4095c4dc9240460cbf5e3d44a2322da8a3e38adda69d1ee8ee80b2b1ed5f756ba6151371a33f87692	1	0	\\x000000010000000000800003d9d11086fec8b17104502fac4984bd824fad504275937819e5b47ce700fa2bc37d18f43a427fdbe06149aa261477bee879b55112d59f56b20eb30951827957ba03c6e0c8b4a756ae78bb8136430c7be3fea1184991525b30c0e993052bd323220fbb7043276355ec5fc5f5a2f9c66eb512c971894b094136650c15ae45ebf771010001	\\xb1ec6eb9ef8e670cc0408ca9dbb7ad58f5264e2949b55e503a860e6c7c1e0f8252ee3f2ca877867c207cbfce80c09571c7f4dd25205f6405e28f2bcfb652a904	1664123915000000	1664728715000000	1727800715000000	1822408715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xb56718a013ecd1516e6a925d535d77e524790175f09f84e67f595ecc4decec24502b94874826645e07c2b448a0ba70fca0f31f2daf5f68db03168ed6be279734	1	0	\\x000000010000000000800003c5169e087d9d31e9f60cf41fab00e1e84e5440cb79696faa3bbcc28db691bba60b7a95543c32522aa38978f7ebb1b80f4edeb22b7170dce44c399f5739af419145ced62eeea2967d158d85c9cc252edd89f0f87e0deac7aa66766f5463b15db8eea09ad43919156a1bfaf6458b9e11c9668828fe9d17dd22d4e3e9a0cdae0655010001	\\x3aed7bb90dc60134aba5261d15e4d38f8b59dc7eee1f401dcc5d8e289589482e5c9be4b0e20e8146ddd357750e3844c530e2133d8a4c3a53b287e1ac792b600d	1667750915000000	1668355715000000	1731427715000000	1826035715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xb92fbba8d1b6398b626b7dba367589b16a841dfba509142faeb60f1fe35ad005c00eae598ef86118ef53928cbec9b868828324176d75cd3f7d12f61c27fd2243	1	0	\\x000000010000000000800003a5e2cfc27e5e4a3eda60000d969e80007dba02d4c20fa693763df500ea3db5929381b59179e3847375417de234d85532ef355553fd2afbc142c1885007e2069f850db11cb23a6b5941745fb33c8deee73adeac89ad982eabe952bfbd859786fe14cb6effafbee9ecb9b0efca84dae52707c6492f18330a8f2fad87bfddfb80cf010001	\\xfff3b8d5470eb37e00719b52200ec07d6b2584b85032ead273d5d10c716b5d4c4b020bebc2fcbf2fdca8d3935450ef1cf9b7dcc952ecacc94419958f8db58203	1668355415000000	1668960215000000	1732032215000000	1826640215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xb987561fe920c80e1e50060b613d26f9622c5e49f031035fa2fbd8437004e516450198b4c79b306a1aaab1f5a7db845f3600e95953daae399fc3eb0c5fd91cd2	1	0	\\x000000010000000000800003c0c70cdc7ff7b6ffc80971049b631afe480c8eaecb4881c4b73c57479ce294b9703634a8579fa7aea08a8e5f311a142be31decc4e4b64ce9964a9884ab14a3b588c11f90527cf40c5372867ce2dd9ff98749ef4c1b05be532184c77f6957fe188483dfac00d006d684ff899671c479627bd4225f55b0d8545f9b584b408e6d13010001	\\x5004d86572c0d9426400f359c000697d6aff0a009b6131bfab17d562b5b2db7635a5e51c0e7375a68bda7a5a1249a907edc156ab6179cb660ccf66b749352b0e	1668959915000000	1669564715000000	1732636715000000	1827244715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xba030af576cafddba59295e951cafc98ca3470cc747896ad422dead7b181c878c6d683ab8dd0f0942e5d190063756a5ce04d15121a60c873690f4865f40319b3	1	0	\\x000000010000000000800003da1082ca3686b5fedc70bf8bbf4c4770f24cd515128449848ba7829564a0319a16c3956ff1ff38250523ed2df3b489b7ab756b3372dd9946f4bb3d1f72d97a1ab2073226aeb6cf0bda346d949f104289340d417f3f2bfa13031fa5cc56d1b287be19ecaad43c95e9be7af833855de15c6c260ba7cc64ac0f653616abdd63c777010001	\\xaa1e9d70aba012e8cfd59c0b064ed8087e8705b4b1a2e87bae8dbeaaa800e90195ccbbb5bc6c63418e739760100f82f67a8514717515c35c699c2dcbd80ca10d	1663519415000000	1664124215000000	1727196215000000	1821804215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xbcbbac00ae1f60f8ef761a71e447322c3895872079db06fb805e348bb4a4331d7be374ae32f7a4767e0260b82556318f724add1de6ee133c995f72417b2b676b	1	0	\\x000000010000000000800003e7a9eee98ad1814e3c37dd5aa98968c107c5afc997293ce8c343752c2ee9d4cc2e20358b5b7d20873071c338a2059528990bd6748783c039ce0ce0d592cbffea10082a2b2671a01b3e9f864509513e2cffac012d0da740731daaed40105cc2550ee71c3b5aca4319b95e392651dd8b1fdc55af192a5a6a69b63a98516af6f21b010001	\\x95e6c1445242948bf53dc2c042c698d3803e7bd76d8eaf8468342af5cd6a90b45c87a3380361f67189b858a8593a7fe0df0932afef909e9d8fbfb4b47b6bc800	1680445415000000	1681050215000000	1744122215000000	1838730215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
398	\\xbdbb4224bd7b9f3a9241341371473f087399700fa5a90e334cfee7858e70575e4fef9dee5f920d1e0cf11f0acfa6915ae8319fc0b43d1da06d7dbac00f614508	1	0	\\x000000010000000000800003ec570059b414635ef4eebd79c515e9255eb205b1720c8a1a375417e4f959e34f539266ab5c21d4e635b7f1afd9c31236368e81a8586f34c9ac21086b02955c2949a600c592d1f1bd70229b1aa55d59afa0eb93cb324bc37ab049b187a9766e2ee6739128a04f841c541288b2f75599ee3a4b6a2e2488fc6f99e711b0f324fa6f010001	\\xc3636ad55de43b0a11c1f9b2b7162a7374177b3c00033935515613c47972367851f386a2345462f28fda4c87b97b19b0ed25f2b256d46127e3ecc00ed12ad102	1672586915000000	1673191715000000	1736263715000000	1830871715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xc0939414791aa3c7fb8d0598625db28b974e64a2aa5e824aa170c815aa887efd55749965447483e1f39a0fcd8ddf21374e25d377abb6fc49bdfc773d222ee3a4	1	0	\\x000000010000000000800003d55dfb6d7c96a16f0776b40f0224c0a81bf7229814f6700f0f172a8a5d02b73aa5290acadce04f77cbe864951c0e6f4cc03d5c1d5eec283e700ec845574342134269f49d285e16a400263ac2df510649927da6d715081af6d19222e241500dad238e8a55f597a98efe4eca55c42e270ad5d268c79449bdbd48d940665658b613010001	\\xadf43d418529836416976506b08b70ebdae95babcc5d909b0a0393fa12a9f72c4f2714161c7b435fba0a5ef71b0ebb5e5e6868a57c2907be64cdf9ce861eee00	1683467915000000	1684072715000000	1747144715000000	1841752715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xc08bdc3569f89b629000069bea98f93e1d51de25b48db549604de5844b0efd7dd0c1b1f43a6fb67c31867085f699dd6d349e2052745f59a7087f85ce5c0df31e	1	0	\\x000000010000000000800003c95a3c9dce1a51ed8ec8593332bca2d446c8774fdc245f96acd2aa52edb86954a6a970dc935130e3e5dc410abb90c30fb6b41c32e031c7800b568a045e6aa2ff641b62087c4a774ffc1d8581d2c47bde8290f76bd20012ad861b2c697f0ff17380a0f6246701143b407dabd8f0346a046234d0d9c7c3874395e8dd658b8a0c93010001	\\x90d2cc3fa12a1b33dbbaa2f5830cbab9a1990aba4527d14998a7338cd685125a32ffc1082fca7b8378171115a05d3580df3a7f42599b5adb40dc1158abdc9003	1671982415000000	1672587215000000	1735659215000000	1830267215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xc3d7bcf18ae2800753c2fd83a2664c5ef4a4e3da34302649ec759e8ea69c06451abe55f838d4712dcee4b15b3ecace1d4176facf24b71f078bb22cfff94ba767	1	0	\\x000000010000000000800003c6f285c325ea2a137710339e8d4757013725b5fca9262c727092bbd7c4f546ebfe9646c0f1133487d392be377878ef08a71d3336856d7e2de7664584efedbb76c8149e4afff899500e8b5043ff4d72fe49513ab90b81deae2288f4639f4f595b6cf24b92122a321cafc8f0e7708d2d9f52031ad985b20c64babab1fef48ce127010001	\\xb9a8c8539216e71b8be39361547aff429736ff52c666951acfbb2a739503753b413f858ff94475e4abc71138e6a3ea12530c47d1cfdeb9bc0c20e97a594cd807	1661101415000000	1661706215000000	1724778215000000	1819386215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xc447aaa336a8bfa5f9200348785f6b7be488f22fc52c816ab169f9d427792e2c96da3bd9943df10d934557c555a1fd23ccc8c0b37a2926b1fe9be4a43cc61e50	1	0	\\x000000010000000000800003e39230e0155e0b677b8d890c459f6cea2b15eabec372445c14189de1737a2a99d3bcaafa2dec74e759604bf4a5154ebc5b36b205be82a27fa96d53592c4c210f7a03f4cc8b96f5f272f62086a5ac275e6e58987cfa42b471442d47705e9b7b93e7eb3b60534952a10e5431efcddf70f4f511d2c4e7fac2b1f5901c9bfb9a54b9010001	\\x218b01ab48433f4697f3c18c51adb34e7e666d79a3eb122ab3db748f673eb1310f34b0c7f63a6072203462b46410bd11edaa12f60ad74d806c413f6359a30809	1676213915000000	1676818715000000	1739890715000000	1834498715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
403	\\xc6e754d74822c5128bc5c15f2ce56a4aacd19d2303640ff232788681f70edcd3ee4b676c9b4f4a1f6081998945d95e631e3d7eec8c5bc408de89dcb09807768c	1	0	\\x000000010000000000800003c99ec0b34d6f0d4f82d89ff4481d8444aebd9138c0983f04e287cae94cebcc3141595a3a2eae36865f20e907f5d62cbea477967bffa3043636fbd2050b50e2a4c732143902df2a6ff9d72d64866769df4f24c23b6173b014fe24b8197c61cebce375ffee7cce5cdd8f9951caf19a3a3ed050a136343e0086fa78cf0812f819d9010001	\\xb34faaf57aee73e39637c830065d75a7ea7047ab523f50ed24941292cf7517ba08cfb5f07fa2d3fb0d44525eb1562729c40ad5adde1935879659ac0abaff6703	1665332915000000	1665937715000000	1729009715000000	1823617715000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xc9d749dceeb7da01911e6edcbcbb9dc55a79e1ab7b0e07a5dd4f8d1294c54a9bb5c3bf5ef2bc40d972fdf1093eea6674fd998d2b9fa66eba4ec0f7de6284917b	1	0	\\x000000010000000000800003c089ad1405202addf4007b03ae7f453d8c643a188f0757974707a410871f536a450da156aceeeb2b65b359a69f8a16717d77d386e00031884a9e38a79b2b945fc242f044aa094de469e3e28aee41e3bb7a8788583fde6ca12afd2745a8a12d794e24697bb381f2c22346eb6be484d283622c9bf43f80155f4ec29b426e6a4987010001	\\x4d06cd1e8f809899e03a9fd10db7636a5c62ff8ec3f79ee4b69e0585a44b98f0daa4ab48b5b49593d76b2999014839bed713bc07f19d3028631cd5e9f0169f0e	1685281415000000	1685886215000000	1748958215000000	1843566215000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
405	\\xcac391372935abbf39129ffe6606e2c4130a14081721ba05b0e69f65b4a432af68a462f7502d03a86fb6040990f2d20217f711976aad9fabea23039abd833659	1	0	\\x000000010000000000800003a0fd90c9ac8606064c762e628cafadb2b318fc465326914ce3c4382b514ee0ecda8c321cbdc9f7fbef1b64605cfafb7c422aa09274da3feeaab3f0a4c9c5dea5e3e6d03628bd3a021c6472336b97b20eb9d3f558edd28a266933983115b5cb8bea9f2671d995e84cd88153c9ae46f943d527f3607dfa2b95e864540a4073abc7010001	\\xa2bddcabb5f171771ad87c37f27fd3fb0917b74e8dea584b6cd246e394ce5a378b6107ea50145b5bc6ad05c7d5fb37178e0a412249aee428a659aecb2715fa07	1673795915000000	1674400715000000	1737472715000000	1832080715000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
406	\\xccb79a7b8f16d572593feeb65b4ff29b997c537e17278f8fc6b36a84a8ea932e1f4554285071198fdc40606289a9ecd11c15fefb7f12692b70e994b497beb5f9	1	0	\\x000000010000000000800003d57618d15c8b07e568b1db20ddaa8379ac95c5fa1aa4a26430e6ba680f6d7edc91fdc6a24c6decc1c34b09eac026975993d2e33f0ccbac0005789214c9d133f8e352b409239813649e587e0318ba55cc1b352a3cbd267c2e9c0d233cf763afb318c68992d3e4eedd2d29c90d84ce0d350fd465f91e383431117caba625cac027010001	\\xa9162620fc4b521327f9448b9ff4f0613e369b7e2e97bee5bdbd7f01774a746d83a9dcb6889e818236b228e47aa8cd34f5c05dca75d1f0a57962117a0d6e8403	1670168915000000	1670773715000000	1733845715000000	1828453715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xce6bb92cd1a941e0d14900be69a80fe913ad4323441e3710a365a984b21eecc1a51b0df62ffbbbd22786dc0ef473fef22935c87a8099885b10dbbe727b5e6b4f	1	0	\\x000000010000000000800003ba4618718213e9769ce30de040dba146548ebb602bac496106c09851575c75a2aa090b631fa5913a6288461167a22386232e3b2f388a10161111089b29243d4f57527ba6657a5610d0bb6127ce1715bcc43ec76dde9adfcf81beadf4373da9637e4a8f85e3def8bd5f71fd2404cc6642c8623cb78ed776501bf4d852763bbac3010001	\\x83d15a91e73e060b025f2e97c4f0af939fa6af095a3f98a3425a385529b798bd733e2d4e6cca1b891b556267673997911ad881569a77a31732c77525b8ab7a0b	1684072415000000	1684677215000000	1747749215000000	1842357215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xd657821b1c2dac8c7886da1373f4f80baac627c4256cad4fa850dbde37e3c5ac93dd064e4bffdd4c0fc33be1523e979f872544c8fad046d70e69ef204279a112	1	0	\\x0000000100000000008000039780b87fda55a3dfb0d9696cb2b997f39ef6d869bbe47882ebc51394708bbe4441f9569952133f91adc9bf70715f67e155c85431b16668572ce139ae3538e483d43f50c427b3402bee33b49f9db49fa67f495288bfaad1ff3213167d635b8ef7e3bf387b437255b7d82694c7d4f1028a43612a907e03cd862ec424384b000a11010001	\\x215a47b9bda3dff35b55850a96735144b78894389694037a34c6089efb6e49a9ac9ec67212a5509c1f15657745d1088aec9a2d6d469bf51fa3ce531f76b22103	1665937415000000	1666542215000000	1729614215000000	1824222215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
409	\\xde2b3d815f709e976873141e16da41da8032bf75d0eb21349a7b254b0b16a62a1c63033e55919717a66c5fea5427e16f8dcfaeae692ba7df50cd16ac74423727	1	0	\\x000000010000000000800003c3aed7dc3dfd04468751362b594374c1bcf8025c6c2228dff0151eabb0b5128a8234d534b96987ec9e7beddb0045e4da4b48ff4577eb02f55a9de6b788739286e74da78747967c8d0e3cf649df7169a2d2295578e1ea6145ad3088576f0c0f1000749689165035070e0099d5dfb8dc8710e0923eb8d6b12ed102e579bb4db0d3010001	\\x60dc4e16e1e1caa862adb72dfb56b84b8dfa31e4112ea4ccb6334de53bc1f3cc48e3c88683341c8793cef0f4475a64d9c5ab11c7d4a2d2dfb025c68da084ce00	1661101415000000	1661706215000000	1724778215000000	1819386215000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xe11b002a303b380d45bda9255fc6176aa5d44581bf85e697b9a078a9b5747692504f77b1196023057968529fa3d3090061ac400f9bb25f112fecec3505bc42f4	1	0	\\x000000010000000000800003cb56a087365bc1500bd40d3821345d7cd249feb177d11b80561f3c569c1d92302310a9e8b3ad407dd7ad70c06b77adb205bf6641b146c7841f30be169ffb986984987fd84a03aa32fb8e57dd44de55aacde430bf426b7b23ceddf42347ba654a03222c36c68139861eada24fc12dccf69bdef52bcd8e38b9cf00bc4028c7c279010001	\\x81f05316d5cb8f10e7d90aaf73769066de639f845e727594b1d7e1f259aef17af17892f5d1a94f2dc2cfcde992d24e85ffd9ef5d4f936addfd5a839d6d7ec70c	1687699415000000	1688304215000000	1751376215000000	1845984215000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xee8b6175881c9195906998582e4545c65e52bb19b10d45c5fe5b7d92b6ef18c8bb115ff624f4afb4b91ef57d27a4a614ba796f44e1fd8808fe795a56ece21cbe	1	0	\\x000000010000000000800003a94b7f3ef27bbe2a9c3043cd70cd6454480b3eb436ae6c12d8a4cafb210ce8096a7a0c80e7a13ff2b96578b4342b871290de03de8ca17f0144fe2b301e7b66c0156b0fdf070afed348d5c1cfcb7e1089d0799de7fbcce7145671688c3d992eb29d68deac87cc1983cee6bd3c0300852fdcf7a1b01854dfc5f60451ba1f24ce5d010001	\\xdf32604c7e92b0b0df313fa98aa642c8434530458f6cb6f203cd15a8f01df26854ed240f198236371d8a2b48319f35ba2e72c4fc8acebc4e1d4d45b0f6fd0a07	1690721915000000	1691326715000000	1754398715000000	1849006715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xee878224a3111b3772abd90d2a68c0d7491c74ce6edb3d41970d72aea4df966cb8f23b504e63158b6c97b66e39d2ab419ad1f9abf5d913d0a3fa1fb29d12110e	1	0	\\x000000010000000000800003ab3e0b9ae1f987dc7793aa12097fade876ded5369907a31b43bd3191aabd7076753316cc9df7dbce5be8481b2a89469048ff6999a930c16b9890bdd380462b2f1733d582763ad42fb10aec9a6271b46c11aa5b5bf38d660ced934f0e435ef2899ea7139b94e0dfbfd45e5799bd5cd3b7ace6ff52c6a4cddf48168c9e4c934041010001	\\x9586b931f706afa1c04ade491da73aba464da9b58d4831d4a9c3521843d848fee20ea0386982a911ab076d7f2d593d918dceb50cacc0239a450c129969575509	1673795915000000	1674400715000000	1737472715000000	1832080715000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xeedfe9f946d381fef730875c34d5517d4f763655101a42517edff9a20438d9fbd3f3f6c63dab5cbf4929360ac1df6754daf172789d85128c1769d0107cd4f1d6	1	0	\\x000000010000000000800003cf8363fa0acf73b6b25d52fb627ee64d27078d3e3001bb50f400f0c666bcaf4d564483451f3708d784ffbec53375d52408d901c2b28f6b92ceb76ea48f3ac527f59558d76a5dd1271e41c06b662557786521a6df93efe1b5b6943790d0f23ac34d2167f227e7a577537e3c20b876dab961816582124f702558a35b46801bbfb7010001	\\x98dbe04a24af39503830d0cff1fbf0cd2bd3be38c8c1af87537c1af3c79afb64d8a2e53920eb8e4e8c34a1e5229717dbc7b30af8a9d7f594c2a619d9b40c020b	1665332915000000	1665937715000000	1729009715000000	1823617715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
414	\\xf193dcc778ceed091d6c2d190d6edb9bf627c028b0bbf9787b77beee29dd8ebd7a6ad5b6906cf3384baf3e92d69e0e23ed5ee651879ac9f9d0942662b0e64ba2	1	0	\\x000000010000000000800003ad0da06559a6b833cff2436037ad9e39ad1ad6217b6b6d7522fe1c494f09067cce57686ad3a7796bd227deae18c73bdbcba4c04b80108c34f29ce02edcfc1d87165164ca01d1600edb0e4eacc51583ce97334de7e51156579da3a1ac99314f5bfbea0d1899ef0b50de1629c588fa73e9672ccfe46d039fd3b240fd084cce15f9010001	\\x5ab5623c46bb30bf87fd97e299efee9c8a9cd09e2e9e24b990098f301d50ac1d798e9e2be02069741054816f155095dbd1b46a5dfca20b56152dba6a87548605	1669564415000000	1670169215000000	1733241215000000	1827849215000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xf2eb30f3a2a6b5456c873968f3d6dfb929469f869431ef579293dc5c8a961097aad86c7e55d3abd9d01669456aa4c0f4bc66c2f6e439cd455c50f1bec8999b55	1	0	\\x000000010000000000800003f6e03f3af86a8a702d89f0b30febe6709316e54886da62de81d044612c083cff6a5432042a055744223ae0ccbc36a1d828fc7fbc58ae0673543d1ad64da74f8bc4eaec4f4abdb447b6367341c286a0cb6867d0ce8409ce1820c178773aa7f13ce46cd5e8c2ffd60c847990c63009e385348bd81fe04f01a0238c5180a8662123010001	\\x3dd7610d4fe44665438e3ff6e30976c9efbb651952055a1771849e139c5652dae67cafbb4c42143e5f56ffc3136b4149fa0fb0c2b2447ad4fb7eb3c84d2f5800	1684072415000000	1684677215000000	1747749215000000	1842357215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xf4ef44056098c164b38f5c35a68fbbfd8d7954c338b6c81d0387a923288f355daa3ceb410766c59f720c9dd184f7f14b41c060e85613621a9f55139678c4edce	1	0	\\x0000000100000000008000039eed7045a0601b30320e01eeb400813baa1bd9221f7e68b78b91887ac029d637312e4be4196599185f092d822f21865478e4505890e74e2096cf292c6183bf7c192e09919bf6640497a47335bf762f47a54a4452b09c9ce4ea2423786b5590398008093097a2ca358cad4f084fcee324fc43c2f29679d0a895578d7ad5edd9cb010001	\\x46194872c46c54fdf2abe48765dadc3ddcac922b1d10291e606a97e6278534b14d6fc2952f63403909b2f3386788516f6049bdbb0c1210f776fdf167ec77760a	1670773415000000	1671378215000000	1734450215000000	1829058215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xf44b99a4e5447609eb74b4a8a0dad3a920e890c3d59469932d9f072bc130857edbe1d4f4b1bc731402357e5bfa71830dd85e78dcf403789a512aa063ccfe1068	1	0	\\x000000010000000000800003c67868139751a15f2098bf9abf84d7ceb7af147ccb8c2c3282726f6b6a75a04e0759943182d8fdce82f2afe7932d16f5afb3877225f037c6685157830edcf3e88472d7c2d2a1554de94cc3ebdf3d0338fe2634326ce9cfffd494ddba0ca29862bd5e0bb804036c60a8725efe8523370e4c06302f0be864850cb92f126cf318e1010001	\\x19d31e05983a2396646cfeda7a64a3032f851036198d13bf7c56df9e8ad8dbbf1434dfae9fcaf8e4ed4415e8fa82bb355faa272629767df4a901be88668e9600	1689512915000000	1690117715000000	1753189715000000	1847797715000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
418	\\xf7ebb53b17261a69d4c58a7a9e4cbc708974eff345ea4202c6a6d1c18467fd367dcc4a00c24fef11385521dbfeffef47b2997c49267638989bf251d6d4b74fe6	1	0	\\x000000010000000000800003b48a7c5f67102b0b5c6108c8d5a59722478a7193b05a936136243334a0a92bc52a0f320f61dddc0d2e819d0ef1184e93b11270dcbf58d044eb0c11563f8e4fad2e8fffe4cf91098544b333f8b86abed8c605cb40633245f666221f552edf4b15b03f01c2823f0739f3b34922daa04e05fb86695c08e275773d19871a8da9e0ab010001	\\x0983af9a6ff4a9aef5b42715c61c570225418c9c1874aade0bf1b951c94f4e6bab876e75298ce42af8b23fa502bf529b1385b27e2c3536e1efe1264ae4929a06	1691326415000000	1691931215000000	1755003215000000	1849611215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xf76b89569eeeeba34f575934187b4d0930fa66a175bcae161fac8bb261df75f9d1f588b505b5508ae37916cd18bb0fef9cc0b97d55c483a471ced0e0fbe395e0	1	0	\\x000000010000000000800003be655a86c9da736edc2eff39ddb210e11a1fb999a8d587a1fd8c47587a1a5b29caf1e3e6650a36138480fea23cf413994340cfc2c221f884bbbd129a1bb663b869cfd0ec1629c7ab959ebdbc2e34e41deda8eff100f839e43e3dbffd445e8de639249c60da30454b407aa577c8b7dbea6c6dfb2f1ec3ef5ccb15bcc82a4af17d010001	\\xacec9472627f56dddc21a45ba2e7ea349ecd05bdd271fbea353b006b4af909783e6ee603982c7c884772dd80eb79fdd698c7ac363c84fc339b86d8a63e378d0b	1687699415000000	1688304215000000	1751376215000000	1845984215000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf743543ab3b899f3ad5e1e2a46d12e631c01b79df6c40126d1047cfd9875622b6a5fcd5d655f94d50ef6dd224b91f4744518b85f441175033cdee21eb637dd87	1	0	\\x00000001000000000080000396e0a9ae53b9e34526fec06bba8a78b18977ab9c05a09a5b446ea95d1f2b6c6bcf82bd344d3caed36e7c262671896f36930b9d073d3e2ff931100f4478d9e0f5277e1b35e794da8c97caaa10dfbacedd9f080c7ef2d0cd7e802837f08cae0e138fdd8040c5734106b0e3bf29141de98c76c27d61271f8386493bcfc3995a9a67010001	\\xe6f6fd630ec5f84605787d9f331fd3b0e9dd17eb475bf1de52661a5605afc6bb2bf33f2aadc047ae91116748f303ddf10cd5cd488be32376474be527fac21a05	1684676915000000	1685281715000000	1748353715000000	1842961715000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf8c3c3ecb1b599e22028f8e78332114cbf8b4ca043f056c62c4a482a80d527987b19864c2ef1cbbec5b7e8f3ba3ed4d187a0966286168a3b61becddc21f16292	1	0	\\x000000010000000000800003d17eb4528585573c3b0548a953eedd00db9693d4d4d4edcbe3e7ee1632b86a470bb92586267aa978c9e171a0656e80015628c05fe14638e288201d170f0d2b96887bca8a5782943e120272e1f6f618bb8a6e76e311f8a941813237f76c8c188d69ad4ffdcb13a3d5869e386c9f225532c82e375a7dcd46850d53998d68cce2ff010001	\\xc9d774b08743169f8c7773aef8389a4dc9842408afc3f2224fbd4cd2e19460bd0e667a80814f878cce9079ce59d1c241baaa995f196237f5eb8dbae0e301790b	1679840915000000	1680445715000000	1743517715000000	1838125715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfa03c77bd1f1cd04da418bce0e5cedb727f1fe46312d3f7f370fc9b1fec7a58fe9eda5256b23c55055e6823564dce307f7aa576d3f035bc9dd7b0ed1309cf29f	1	0	\\x000000010000000000800003ca27a6b57d79afcbd9a6ace8e8474bbd3afc922d344b02ec15bc6c2569a8e1b3de3d9a4ba19a900fa86526b59c7bbeb8f6bb95bab36ea7d8057f7bef52fb679eb9ca2a5ed69916e35c748da9d209f66dfb0bc59368b6d113faac92a1c8340a1ddd5841c06c22fc808a9017c1fdfe932e897bed80ef2402bb5542a81967b16121010001	\\x18ca1ca57dd9c1b650998788d79b30ef1595126396444db4ed8a36c4def1935ec7731f1b4b2b0e2e3dda3b71cb7985139c337b307345494da23a55543b7eaa06	1665937415000000	1666542215000000	1729614215000000	1824222215000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xfacb54bdf8e438f669805c26cf1e69b9f23d796cc033e62853c2ce7e6ce36ecb94f87a94e189831a8622f26a243dadd3c13162f33167c93067f12d91cea9707e	1	0	\\x000000010000000000800003cc8ef4f8333742a31007066d9d014b1355c2cc89943fb631027c01d3918ed76569d6eebc1b6d0233981f895721452b6edbc61f9304761c8fe4d0cc119c05133d2a19adc7a05986f7cb2c87650bddf9a57eab8d3c0f78947d4f170113d0be214c8874a38b9f217c6561de99d577c03c8c957e18a0f49869d92eaa6c09619d1685010001	\\xfddf83be81a116bbb2e36e8149187cdab1e5022542fe95d11369d9bf4a3c87870fae97571500cb0d315cc5afd17a539a888fca56e2ae6db7cc4484b7bdd23607	1664728415000000	1665333215000000	1728405215000000	1823013215000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
424	\\xfd8b31240353a2e289775bd49cada718c0fced4e0a1694fbc9ba85712ea0cbd49db54c03c23e715c0b99c2854d268f48752d5f509da4100c46bb78081907fd1e	1	0	\\x000000010000000000800003c154e4a8224423dbfeacc918464b9a0112853d1943f195d2c07b9263e5833228c47b70bee14d3bcc0586eaa0cdc1493e67c86d796bae3bb8cbcc22c23a171c8dd38457bbb2180a83f54b9c6c814e573f4347ddbefaff4e0dfb5544c4f7e9afb142f2205cf9946ec35b353d1412dcb1edfc5de9354a413ca4a71f2df319ede4fb010001	\\x17ae6b52aa7c2f5ed2c89cecfa64b54d9ecadc3e595ac4e0772a7af0d3ff0335c66b5529df2924eadc6aeb5373afc98ff9591293f42d7834708a0b00018b6b05	1666541915000000	1667146715000000	1730218715000000	1824826715000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660497844000000	1861919949	\\x592137b950d311b054eaeaf80ca91ade5f9f3cdbefd22f60c8d1996a3fd68d9e	1
1660497876000000	1861919949	\\x02817f806330300e5d357549b6007eb148846a90f2b1e26649481d5fdef8bece	2
1660497876000000	1861919949	\\x088afb72460f451eff570191cd1354a9e926d8ba5568c0a957c65558b3f1746e	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1861919949	\\x592137b950d311b054eaeaf80ca91ade5f9f3cdbefd22f60c8d1996a3fd68d9e	2	1	0	1660496944000000	1660496946000000	1660497844000000	1660497844000000	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x0bbdb2d8e27013936ac463ba287f0a2e42014a27ee2ec566ce9a289fa71d56c15945822db2f46c07abca8ef246531c42b81c705ce84a29b46482d34c403a5ff3	\\x170c07f82e6f239f42e4f3cb08d9e29dae8ee9e9ba2f2550239de13802c9c18e82a4b0e68037f1cee6d257659377d275b591865015d583fcdec6df221ba2790a	\\x0fe4af88bf614464920a2b82ed6e1410	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	1861919949	\\x02817f806330300e5d357549b6007eb148846a90f2b1e26649481d5fdef8bece	13	0	1000000	1660496976000000	1661101780000000	1660497876000000	1660497876000000	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x1f577e803515cd596a820220d12ab80b1975adc2c21267032c44190495566a33083293dad7f13f2208b0cd60d9cabe5d4be787897c2f6a1aa38d7299837a97de	\\x87d09db25f17fade0e7a6e0167cbf989bc46559eb3d4332f26cc170487e6a4a3fb55362d309eef525f961a439a29b647cdeb732c87f1a18d23dc83393d954a01	\\x0fe4af88bf614464920a2b82ed6e1410	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	1861919949	\\x088afb72460f451eff570191cd1354a9e926d8ba5568c0a957c65558b3f1746e	14	0	1000000	1660496976000000	1661101780000000	1660497876000000	1660497876000000	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x1f577e803515cd596a820220d12ab80b1975adc2c21267032c44190495566a33083293dad7f13f2208b0cd60d9cabe5d4be787897c2f6a1aa38d7299837a97de	\\x92d1def1b747a9cf4c75def808f392d3b81815316158395203bedc960e2e45bbaacc8d9cdb6173cf1459a01296079a6b1c11c7aa7c10824ca12038ed19fefd02	\\x0fe4af88bf614464920a2b82ed6e1410	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660497844000000	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x592137b950d311b054eaeaf80ca91ade5f9f3cdbefd22f60c8d1996a3fd68d9e	1
1660497876000000	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x02817f806330300e5d357549b6007eb148846a90f2b1e26649481d5fdef8bece	2
1660497876000000	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x088afb72460f451eff570191cd1354a9e926d8ba5568c0a957c65558b3f1746e	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\xa0b53f57e6daad7f621de6b8b82a2c77375dbba27131a1f3f6d5a7b382fef1c9	\\x5e6321b758b43110dc4cb4b810bd19971b9e672c13cdb774e061d18bedb231efedd11148d303946c31c2a99fd8b23242c0397fc3b77aabbb1228c17b3306300b	1660496915000000	1667754515000000	1670173715000000
2	\\x4b5dbaaa88cbaff3a59cf44bf0437f3007d9d0d05e00eba821fecff1268dc976	\\xca817c932a8320816afba84c57950dd4173567b4a8606ce49072be749723d07bdb7fb13fb2a57671c2392fb2236a7d4371000ae78538db77301ed843267e7304	1689526115000000	1696783715000000	1699202915000000
3	\\xae530cbb39e679a6d9bbe4e809aacae480136170495f3a5f0f5e77be56587f88	\\xdd154b53a0ed724ece3d1acb2227802813d915fe3361ee5b6bfbd785f7dfec6b946f37659683a0027472da98a949d0d950595396182efa0a200d02aa72f26b01	1682268815000000	1689526415000000	1691945615000000
4	\\x15a354050eba62caa02531d94662c9febc2da29dadaab41e94da21f5ea8a239b	\\x35cce8c55f02a59e5d99a9f1c00d72ea5ff1f96e953fc227bcd49825a83dae40f008e5d823f5159ba70a0f0d49b77d0edd9b295f2c14aa07775092ca659c5c0f	1667754215000000	1675011815000000	1677431015000000
5	\\xb68796a62a8d633351b508479a183e215ddcd070f61d24de454acac750cc75e6	\\x24a50d06a06e038353668785c4ed439f4abb1d3910fedec108f2c81696773f5e50bdcf040b77405bf3e5690e9ab25c1b6c129b29244f5fa9e42661e40fde9609	1675011515000000	1682269115000000	1684688315000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xf3cc7696928028b83bf5accf73ebc45dcaa4d83bbfdea93993b8cc9e629a4476b533c420832129e70aa59f8789a3783218eb64724f6a0cdd473d90e6ea018100
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
1	344	\\xecf90e8939bf60fefc1b73cde7633efbf508151bda23604561b40d50f214a577	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000146b67a44f1d15e1c8a4ad764083832e093555a36afaefaebd04713764c55abbcd40ce9c0605d184de3e91a9f46c6ebd0bf5b642c98d6b22e62a1a89f0e9ded3be6476f58c6f0edc28f8f2dde4a4f03fe00161930c6a552ebb722e7fc59e9b469ae5bd8904842dbf78981336de313969520e08b708eca21f97976f6631916856	0	0
2	315	\\x592137b950d311b054eaeaf80ca91ade5f9f3cdbefd22f60c8d1996a3fd68d9e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000090ec370b43f93271cd5de3d64174f4a29d967b51d76ccf4634dc6f661f54d570e380c0cd1e6900d071b0a9df5f6189a12c886a5274bf37ae495fbbe53f630cae0ffc00e944e580fc07a2a062130d05b3e5d2ea428b391d4cced01dcd1cee0ee15a527b5a17a5d19b35f7ff829c40150e88142307d150a079942fee7fd3b58dc1	0	0
11	259	\\xeed09aadf5dc85596b5efbccba314ad7af2829341bed79bf8c2431c200a97dc1	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000090dfa8d5104fa889eddd57734b6ca6bd1ff32679fa2a5e0ba8ee0ab278edc8a4632d13c85c23e764b7c014e6202e37efacd5c2f16b2c4f26ca239c6dc8622fbcc3cd7f8a17531b56c7ef6afcec024698882902aa1884dd5a50cf26b8308966cbe673a532359b2954581cb202b03d2ef7c3a87ebe713315e9f128e85e75bbed11	0	0
4	259	\\x358f5ae1481cf28b3fa5e6ff74a6b9296c5ffbccc78c84963e4c139303ca7fb4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000074f8935ef3ad475c4b79718fb0f2af2679e22d343d4862b03165f831de13398a89e9d306b2d9c1a4a86c8aeaa2cdc563d468d7711ccf9f3253273845f20312b6991a17fbd75110730d758329d3cc17e1f91930ababe1d1647f140807e31602bc7be691321bb5604607c16ded7c8145d39ee6737f2c25186bed3e363562719f1c	0	0
5	259	\\xcaf75d24ac55548ecdbcbb57b1994004e2341b18f76f5b1e57766b0e756de921	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000085ab66d2665abd33ae3483fedd3e92cc142e7f9888e6be645a9a30498dede418a86903c10ece024609ce56fd659db604d57854190c1ec03a5120d822744d54ce5fdafee927e481f13c9c5b3a37038114dd72aa279145d183cfe6b4b06bf2ade3cddf23197391c1fab8e89023a818eb708db01db254f6e072ee30a1d649f66d0f	0	0
3	291	\\x503d9a5f1f955dd2f26cf2d4ecaf63a475fb4648a173c75baee83a87689a8262	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c96a8aa2edb5f12691f2cf3aa87a5b1cfc102356d0756cef50a76e1e1b9b4f14d62c127a909ecd41264d0a6f5416b62f69cf51f8d0f78cb6b3bf93fe24cdf9037a7a9d1c660d6530135268993372cb4277cb01236dc5293d5965dbd8b468ef1aee3b62f8f1d1539932d64549d54d8ce38c1c0423b9e0b27b6b9a94f0705ced58	0	1000000
6	259	\\xf01bf4feef33236f67c12749c2b7afac4e3bdf316ba4d4c08602672eab38d241	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000202433e18f6ace21848634b55ca7d6fb5a488fb39c811d5773e04e7b58b8e026300e9ba1034ce94aeefe7ad8a8bc74c81bd0833cca11f3e7ea2497c160865eff208f4770a7381bc1c2aec562d4bca08dc9ae608eefdb5336a8e7a5b1e846f7b86fc059eedb19022ac598abbb38f10b726eba8acc07a000c0c7598e1bda3d1cb2	0	0
7	259	\\x6a7145ee39f9cf7a50e639fcc7072ed784600622ae7b9146d217a564b43e7295	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b969f84fd2467b00952b14223682c51a0be65f6e12fd10e04d3d41ef108e18ffd83c25664d3a9adb036572063ba4a966c9144edec846daf5dc362d003fc6e4ee0d61e2c9e6a69cec4d919e1d7952b512779b1dea9add7e343ba16e5de32c4d57ab7abe1129018a68f5ff3ea8dbdc61cd355dc1a7795288a49b1631da690615c7	0	0
13	401	\\x02817f806330300e5d357549b6007eb148846a90f2b1e26649481d5fdef8bece	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008c2e32abd2a870f5854c0db3fe4aefb837ecdf59b0e2f8b4ada0afabfa303189186c6c6b484f2e927d68407fdaace231991e29d282e77181fa9a40b16b843e2cfc7c3890ed45105266a7cbe64d14f2a583d96debe10bc90d1c80fed9b24d1c0271cc410273f6e8e82b4ca9371c9ddec82c007e2be591937d905357aea8e67e0b	0	0
8	259	\\xce0bf1badac4bea775260a84c5fef75374e94e9a123746d7583281672f7dda30	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000ca0749bb449ada1c341d7bfd5e1ce9a484e6b6d0376e6ee40c3684784b5f96aed0b51d85061836eff677cb66480051aba4d3a1ac5a69dbab0caa3f8e65a93a35967ce11cbfa3c48c0a42f99b91226a8aceaeda36b64a4039338a8aa4056f4b542c49ea13ae8605bf3d1e0ad72b9d40dc2eb1d4fcccf53389aede97798ead0039	0	0
9	259	\\x4e2e0e43653a4e182c5584df3bfe928b57871172f5a7ad74dbdbbe9a7836213c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000288d8df92ccabcd1a1aa42dfbee6584c92f0588f0e814623db9e0f3823068d747afbd975e5a00fb128cee0b82344bade5e8b22d5273def32e605f83d876223dad35182068d9d67fca6f7d18eaac17d6f91a7cdd8c179bbd936dc76019c1a626e795a7c324f07068044ef831dbcc12331a10a13db1c9a1290c841b1f4c3fcee55	0	0
14	401	\\x088afb72460f451eff570191cd1354a9e926d8ba5568c0a957c65558b3f1746e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005e82f41a94c6dfe0661d4e97ec2fdbd6f1cca11ccc5ec9582eecbc83a3c23574d47ef3209d349fb2b4167afbfcb79312eebbb5bbad2352dfa53e3366b0d4fe98882594fe9f4b7aceb47c24de67221437961ad7562ca975eb617f52678ad6cac5ce6bbd971017f65b82fd1ac55bd01776a9aa672b27788a47fc16c12cc1b2dad2	0	0
10	259	\\x57e1d54b285378eea697effcd7591fc7f41313ebedf6d73fc2d2d59cb76a0b30	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000081f444cce53475dd4e07dd9ec29c33c5acae008b2576b2855112391b7bdc74e39d145c3cfa3b0328a148ce08d238918e160dfcd77e0c521ea3b492a4ed8d68f1998f61ea81a6ea71f5ce8bb36111bb55409fefafd7a77ba8ec752d9d8e6de91066dfd6d74ce828e6e1ad86d061ff48599ac8b475cd2d546d31fb95517add6966	0	0
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
2	\\xecf90e8939bf60fefc1b73cde7633efbf508151bda23604561b40d50f214a577
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\xecf90e8939bf60fefc1b73cde7633efbf508151bda23604561b40d50f214a577	\\xda73cfde35ce0ecd8d00d0a59a4fe9776f717c96d62c988b5b712a34790436aab4c365d50e0bbeca923043baec54f5b672f0e5c0dfc7eea561576e4ef0e7e20c	\\x02865437ea6d51b00be67f28f3c5cb76ebdb02cc774c204f66d0ff87c30ca7ee	2	0	1660496941000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x358f5ae1481cf28b3fa5e6ff74a6b9296c5ffbccc78c84963e4c139303ca7fb4	4	\\x3fe3aa6245a993d5227a2783abb2ae1b17273021bde4248c0c27c507f952f1472d4be512d10c8020c840e0a17b6586d49a0886615e9606c89fe012787807930a	\\xf3a688071aeead6a9e107decc69d0f026c73659c83d387cbf454a16b339de762	0	10000000	1661101766000000	5
2	\\xcaf75d24ac55548ecdbcbb57b1994004e2341b18f76f5b1e57766b0e756de921	5	\\xef023b94410c50abb9a39277bc859ace8df1d0cde02aff38a2401baffe313ffa9ce12911de1751b564111e5f966b3ead1eac6b3811f1122d22fa2efb8dda7605	\\xe5eead8bf59caaebfa3169fde07ad4b1057e276e518c2eb2734fff9d07dfed3b	0	10000000	1661101766000000	4
3	\\xf01bf4feef33236f67c12749c2b7afac4e3bdf316ba4d4c08602672eab38d241	6	\\x2026d1be7702cb40246190b49bdc194759bafad1dafb478f63a73007bef7c9431edc2e8450766be0b9c4d94fb0faaab5f8075deca94c5ebe3622350b2357b10d	\\x3a6b06b1236bf2e0f181a03981043be297cea9a2eb2d0160e844238e0b98d63b	0	10000000	1661101766000000	8
4	\\x6a7145ee39f9cf7a50e639fcc7072ed784600622ae7b9146d217a564b43e7295	7	\\x836784e2f773212a55147e690214e46a727171b8d47c9f108124042b53a3e54e8bcfca08c6e6d8b51a7444b3f683ebfef2d9beecd4ef4f9eb04637d85048f300	\\x2fe4a5e4845965b820577f2aa4a292f62fa5a33839e14ff582c5f5efe7539b3c	0	10000000	1661101766000000	6
5	\\xce0bf1badac4bea775260a84c5fef75374e94e9a123746d7583281672f7dda30	8	\\x2f8502865eb122492794e8a2ed50b93ba7e69c82c716beecefe6a0a35c31fb817e90a724a15e5653efa19dd42c779bba8f7977d7c282a53549994b721275b003	\\xd9e598056e622fff70a7f36d692dad61df7654f59cf2ea048074cf7e73256ea2	0	10000000	1661101766000000	7
6	\\x4e2e0e43653a4e182c5584df3bfe928b57871172f5a7ad74dbdbbe9a7836213c	9	\\xcafdd1873cc59e3d305964c7d1f031a181479a01085c63843a884a94b6433288ff9c6710b9d25f8b7a65ffea5f14e8cb91b4b6cead80f9ab5f302d32ac8ca606	\\xe3636f111264391c24833d00d64883581ff35e33c6a2b3d57998d5c055e8c970	0	10000000	1661101766000000	3
7	\\x57e1d54b285378eea697effcd7591fc7f41313ebedf6d73fc2d2d59cb76a0b30	10	\\x71835ebfddf738d836ca47560a2c7bf10eddcb8f7a67d81ec840456f2e2e434a070828d7a704d76d01be89ff1118969b52926da4962778a7e4f6d814a817ef0b	\\xecd560daae0e00dad9456951963ddfa5948023aab3cda3312efad245c2cbef23	0	10000000	1661101766000000	2
8	\\xeed09aadf5dc85596b5efbccba314ad7af2829341bed79bf8c2431c200a97dc1	11	\\x19a9dd8391005e89ee10d791c97b8848cdbee77411d15dd800dec31420e3ab754ada5d1eb5c67225576b4e3d618985c7c5ab6af29424f8d3087dc9b5ec4d0f0a	\\x91526281c781db8bc13e8a61e90993c277449e6db1486854e8a85beaa7887811	0	10000000	1661101766000000	9
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xc15b8d30acb1b7370c0aec422213c5d7276c1ac88051727128471e32d24a529238c24f8fd1a33d795265181012d455e060de11cd538ee895220dd72b5ff034c4	\\x503d9a5f1f955dd2f26cf2d4ecaf63a475fb4648a173c75baee83a87689a8262	\\xef917b61039da49a609b0df2161e04a176038b98aa42a9afcf2666bc51bfd5cb309ebd1ee070355336720899956c5f6345bc88a43e99b36890331e5e661f9204	5	0	1
2	\\x53fa634056194276fe6aa54beba12985f6602c24e32f5855006aa5ac1f724a218f156c5ba7a3da81d8a7de2a96b76da6e60cafba2679d5f6d8cfb7b29c633702	\\x503d9a5f1f955dd2f26cf2d4ecaf63a475fb4648a173c75baee83a87689a8262	\\x4334314c0e8ddf869e985048b7fe4d263b07fc469617d84df2a1a8e19c9b7f584453964068752c3747f3d609d7b4c677f6bf0658422967e11ade1a5468719f07	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x386135aa86150abd51b1b58f78905cc696e261aea48b378cb7040e15e096c76bf6ba9d71cb5211b76ec37389e9f48330fdd4a616faec200ac5aa3100f0f5c104	332	\\x00000001000001001db2a00e7bf98cce4491068b69b85e064f8bd97e6eea0066303afbb823f9aecee6c2b2b8502fd5efd88c3093929f912f67cc2b65dbfa65329c8167cf4eef5e5a89a7d0f1a1c236676aa14b2e75d048bd6c5995f72010b437ae24d0f0f5dd682b934267f7206dd4d583c33a1a027fe7c004b914d7971edd27b0545ae7cb4963ef	\\xa7a0312c4d2f0dfb9dd2fde54a6b6e0313e5aea0b38ac6e5802a33803c8c63817d84f8ab6b963582822c7100fcc1830cf845df6d0fe14e5af8c77a486860273d	\\x0000000100000001453cab5a657bef68ed6401eaa6a5aa01c52499e8d67ce07e088104aa213089d876958ec837cb567d4b87d18543b520faa2ae2a77c2738639ca3c95b1aac7f06067030a8ee2b420da7fde5f1cc84ce9361489ef07dd39513c92ba8bd67460bd28115ab8930baf86919ece37055d95de9394ab6eaa0c7494bcb5ad6b217932e110	\\x0000000100010000
2	1	1	\\xfee8961c3ed4928910b71442e73b8420e28e013378dec5e36efac55775c1dd985e25f08d02f96566ff6d05a219d57b3f847bc33509e68c02d29c8fd8e22fcf03	259	\\x00000001000001002d73da69390a10858e27332877f6ee62ae29ef358023853178c659a5ff00cc46dd66813d1ab7c57ae5233fd219940b9c72162b3732dd565733c11d212c6a0ce065492136915df76c8081accb93b5b8c991331aaada3f80eb67afedcd5efb2807117831747acdb20c95d8d5cbb181f7d023090807cae4bb726936f6eefc409856	\\x4416ae5a8a0f5bf400ac7aff166ec657f090f954a73142b299180ddaaff712cdd4b76693a64476d26d262e123d3675f75a16c687901763add748a2e5bb711ba3	\\x0000000100000001510be169eb58a033b8fb4e8df2f44f38afc4ee914a9a461d3fe83aae9beed5d4908e62ae2eae5c7fd8938c3813855d2a93636273870271a1e6ef8a8e8c1bc175f4d8713461b9897d16c108eac3afeb292552a385cf79b269e6fdea0d5143b5c4010d3ba0a4c3f1d52d844cc169047d62511c5c176a527f553f74995f080cb95f	\\x0000000100010000
3	1	2	\\x2dc14bab8a6c3d9659bff5d56579697928ff3984f8550222cb95966573097ca2ba2da1ba798ce4a64caf7fcbda5fa294850d2d0a69159f7873f70cdce19ecc0f	259	\\x00000001000001006937737d3d705010ec3dc4f1726d1973837ea064358aafd2ad60a1ffddc4d7c4298b4779fbb4cfa8cc7c7858b54511122908c738293fbecba2bc7005c5f7f1046a517a071166f695fa9a2ebce9fdc080cdccf22a359d060b867a44b46e994fe657f0280065ebc0219a4fe5912b5d03994898fedb954e61230ff4e7400b5802bd	\\x2314a9cc0a5e7268e6d6de01f509d26592de666272a12a2fe5f8dde06e05c7efe099905bd7d6d858a403c153862d0eba2aed142de43e5112b6214c4fa7248c02	\\x00000001000000013bece10150bf7dd8a43641af854c89965baab4ff6bf64057051f0da16657fcfe71512b2ee495ed29ef3141a09c75ccf08f553a09662e72c0e5d022e9cd7e092463dbd731744db040e7098c28fb1e7808ed4605034aebdf8999f7c593c227bc5a7eb9950ab36bd65a3f03a68fd7c39cf1005aa1c5e63704515055bd1e65933e02	\\x0000000100010000
4	1	3	\\x2241446afd9469d817b92b08a81cd32a3654aa0933ac8fdeedb22d7c43cd214f79af4d5997c3a6f6938ba67ea96af82d13811be01d1db69528ec19fd87541503	259	\\x0000000100000100625342fec39960f04966ef7396042f297ecac5e69d760c3df8c99e33627abecf6f8d9a90dae29c92d30f8b94e3e1b319a103a6bf068e564f668a47a08dd248de5dacf2e5b76acd01b041fbe64b6f9b943b37448214ff468c9ec67238eb36099cad217337a33789b3401748a76f95f307c9d0de9639e3de706d41d997f8cf88a0	\\x2fe2e60d32ca13a4745c92b675be834981adbb9e611e129814b0d0df4eebf8601e83425e32cafc5aa3fd4b948ee2e5dc3452f9706c5344efc7dee125a82e523a	\\x0000000100000001b2472f32d3d4fbfe8d2e3b393a9445f33cd4a5eae77d00fe360d945becc51e3c128d67675359d53a3afde328d03e1523e4a0cf0e2e31f44844dfc618913813b6647e7ef1234e3ff62010673c2ad17a5706cd78f607bd38119d036101f088fdb7869e5ff465ff032565b44761a9a900521c64e9de39bc9b5e49629e80a8fb3dce	\\x0000000100010000
5	1	4	\\x353f48fb96208c2c6ffaf71d82044d2e08abc709ffc7cb913a9aab31821f71714cfad9bf6290a87a621f340ab4a2646c619bfbba17861b1fdc72ab1dfe1d490e	259	\\x00000001000001009bcf28b0e5d771aba45f43f85ebd38cc32155a51b33ad7b04ce06771edb3bc084d9f152c2d2ddfe9969ee1c8a2e313ae58026cc4615c9b93c900f68c718677ae446a6146d86a46aa176d052931dc28da2aa34785213d6ae501e13a0bf0409c4a14ecd82f26741896487cffa48fa53d44b58ae2c14703b74e77ff6b5a4b5726dd	\\x4c6f77708a4e12003eea01fd1985cebadd58a6c31cac637030f6570c915ba3b5659d5103d6f9481aa58800df93273f174caaecb1845342903d69305324d5b3fa	\\x00000001000000010e20b354332bd3e234bb97ef86fb825882bf8f737ee30e941664287b1bc1875c01e222d6de40578702c1943934beb2c0d4254a8e9d5ca6248eeb91c81483228a8277c50d62222f33a1acef87fc9ac2cd759e9f4a385845a7a1a5967345403cd479bc3b4b7dc478201bc1d83ae54103cb1bdd953019072ae052c1913cf1a11ea3	\\x0000000100010000
6	1	5	\\x1c0fc6249f03e9ef01c37854210dde46b3d31341b36e4b08c77627f06a0f563f45334c72c75a719227786a9b8769d612df234b31ac667f8331c9f44623aa790a	259	\\x0000000100000100cedb879b74e5f66149770cdcb5d9622f4f4fac85a2de38a1265ba8d4797b42d697befec8f60901b1d32e1ddcd11ba88823c9d41652bbac52d59bc8aac5b586305cb3d23e351187a39bef5d5c1ce100fbc83834737fe6d46c2c122368759b0af22843c3ea0e147d391eb7c721233efbbdfe494e6c8765155f8c6350d43450d80d	\\x67218f8d1dadd658795f7fe3b9fbe35bdc5f0efa0db543693aa44f0c08376aa9ac7b2f4709e3e6635edcb9e604aaccced8081317521d5ce44605d9604f354fe1	\\x0000000100000001ad33a3287458c1f0d751945e109c9b452422ba0bdb8d0c1ef33b3847732a2017610cd4d67f9565c7558459ed1d975de42f24566581503fbe97482e151180a55a651bd38f26107b56bff802d48852954a5c421b7b2aba6b5c51f219a0da235eb5572835f639fe83d36e1e0854575bbfdc213b1f7abe28d5e97eb9bc8a163e95fc	\\x0000000100010000
7	1	6	\\x4d8e1806393d8efb81b64e34fe74bcfaf570c609ef34fbede1296b4384cdc51accfe8516bc44e4c7c256d0f6ee20aeb1dbc6220c8ab8d2df67cb58b7a48c8c0d	259	\\x0000000100000100b3da9213ce6b48cdc63991ee35ed587d732edfb5fac36f2c9ed015a16fa92fe3994f6a3b4d3fc474ee47a5fcadfbcbc6a882d58698817c879891d07eced10fd8e3fdcdb5b807fa75b6f7f2c8d19aae668a801b366f2577803c387cf284ea3788c58c08357f17daabbd23604bc7d3a567602d2e680a8e110110c175b0c16eae14	\\xc37235204695bf3062dfc3956a1f1e561f00d51870a0b7a10b414be591b57f5e9d6ce584ee89fdef7edd9162eb725c818de1a2917c3ab6d71ae8b8942d8fc390	\\x000000010000000159acad6cee1ab144892192c5d82ccc063803b0f3ca5d64f7cbd5cf38cbebef330e0c9834da6fbccb270ddb4de546854f9a9afbd0d66fcc4489ef50e7b61c7d9587a372ad7d6ee2339671b04c1d73c129f3203cba1555382a78229cbbee6b9cd536b17b4a72028596b84bbe8dda9076bdb97ea8bc4667d538e55e80417ac9b8dd	\\x0000000100010000
8	1	7	\\x5d855069d3b08cfc9bb6f8093ae73f85db82a915820d1af7893cadd8bf0498e61ab5f79116167d921596c82da5591920dd16d7c27d9940774f483cf1e9948503	259	\\x00000001000001008cfeff039d52fe6e3432072649219f6b53bfa980112a4765470ad0387c3021459e4387b6573a20050bf2ee323fbf131f9801eeb215394faee450bfeeb90b473b4f1663db42d269563b3549b53491eb3d2fa0df2b6582e30b1cab719da6f4c9578ef70e1d22ffb49c5caeb3153f229c537f32c78c17208f44ddc7d0500af7e36b	\\xaf1b810a2da2c62b8216b531fc7ffdc2d9a91b7ff3090192401b5908bc2c7447a734ebff0c15058f11b8772ae028a70c6f6f5d3681f8f3ee0c7d171106a2efd7	\\x0000000100000001bc1a1c41edb86247a5fad14a63d4669ad5d4bd1a49d6ef6f1b49436afb8db5dc53810f5c776f14bc50221348edfd971a90a22523cf07186706f3fb2aa1f648e91c8ba8692b61e8f8d485fa5d1d16a29ea68417da98445172a384927b9f0bb9881e77c95441f950a9fcd8c8fd75d6ef58f5a3de94f7703be551da9c048e922d81	\\x0000000100010000
9	1	8	\\x591dd7da7301f29568c9d6fb6ce51883dfe4ad3ca90875c0c2b0d97913775c0bdb311a320e8c3431436beb401a74f41bdd768ec62008eb3911cfa23dc9c76f0a	259	\\x00000001000001001971f094ecaf82852d561fa3e9d3a57b6d07ce40cbd32f8db414392339f88d34611c4d38055acac990703f7fc39cdb85a09bae8475b25299ab88b98701fb262da3ce41fbbb8df433330f772143b2c712103534675b7ed7483576c701647c58abe7c457c859d3712a41d7716dd3464e2f22b9669e07bfc2e8a356cde78f2465c8	\\x6a3a79b19850b563bc6c79545d7a35d11985f62e2e6c83b6acfe9dcd3a752bfeb8051c4f3a66f00e31d28f4c14ea2e325fcdf4f091f0f712dfeecff70a2f888d	\\x0000000100000001bb2102e4015d7e82e286df771a77f4c90511ae95f3c581b76220f612fb567dc8f83537f87cbeca3b3c4c4e0345cfa1ee26f831dd7b8a2a111d7531c625da5978558581925ac379739a30552088cdf0d0e11afbdefa88e9c1268388d6f451b7234c1d823d1de70a2bbf517f8332b1ff405dc4492c66a2ccee9440ab58ef4bda11	\\x0000000100010000
10	1	9	\\xd1312414da3597be361d40b120e2229e6511916b958889d520684358425588d755afcdb4ef4b715948d84812cba60de50169ad23b52b0fd25f396031f9146009	401	\\x00000001000001001c56470962432fbd63b74463ce0d22aab5aff30d62d9b026472e1074322b4d232e180c12eca84c071db350289fb66ed37118149f869abf7b53bf59020fc34bef127930dd33b2d478b170870ea21ba4f7eedc61264dfa3130d4e663af8195fc7f8fa5ac8131b6277cdb04190b25a49bb6fab127b88d9b4fa54982d8b7e20fa9f9	\\x0723dce9f31e8b75fa8e162dfda98f7c96da042d095dab6e75bd9f4a5ed0710338123ad8acb66c7ad637e3de65cc88f89f21cb40f19de131257062266f1c17f2	\\x000000010000000127daedec4d05962a4446de6bc46578cf2ff6e603b415ba5a6021d01d82865133181bd7d9e3d65655b917a6bff34aa5184aa1628cd15b3cfbc7cfceeceb057f51881a79bd821a6142368765dea93d2fe15e582f75db87295893fe62eee2aff8d477f76cfb829f15ed68e7c47a92343577fd4fa340da5a3fe90935028bcc282660	\\x0000000100010000
11	1	10	\\x7685d3bf8916b51cc6e359c0090d53127ad0938e4c7a5034ec3d8fea6bb1739ebd42169b4d8449b747e84810a74af624a1835e1319070b89addb12b61e53ed06	401	\\x0000000100000100878faa0c9ba6cd1059785e7eb0a052ae46cc22ab6386f3c3b7227ce00c5511847162856a01d33667eb9009516304b81a5524c798ed2e12752d7e66abe42a38cd68a437ca65f354463fa0d22a9582f48f00b0d3923c698bac304f7c8c92a41d011533dcb3e59d1e705c73c886a114509f16fb67fe7beabc47a4a75d7e5bf8388a	\\xa22e068fd82f851ab89582f73470dca467cd6884ac9facdb3d1c753fc31d69b01125a1c7513a8b07f45c885a1410fbb7c3137e94c7bb9fb98fdcf179d024f234	\\x00000001000000015b5b3ed7aef4f07af0e7884aad6aab4dbfbbbd51142674a1b51beb9f35d4a0b5e98ad39aeddd87a469db259aba3656ad123671e140881706f84140b4e1efff5a737789fc744e16629d819317acea0c5cb304f9778ad34e18343bb8ec80c813d4a60cab65dade833a0f1be595dc85d9e56bfd7d4ebb7b672a9bf60b5fe101ae33	\\x0000000100010000
12	1	11	\\xa8e3d0b51d180ea4679e564bd5ceddcb0d1ac0359042ee97c6298fe95ef5006c6cad7cd3d4aa497e19c8e5f73f6d530751496756a2c9ae047bb1155cebc19f0c	401	\\x0000000100000100923462dbca8cb9858d5bf186d40bf04b9c9ee428fe1ee1dd6e9ada11eca8852d88da3e4080f116db97ce1f0df216f97dd7e23db69ba905c580917186460757769136b0a7b87b0eb89dbbb684a48873c77a6862bfe62f5ab35447620e740fca4af6521410944398e8decaab13764a82c9d8086e88b57d1db40661310a157fcb26	\\x564c1bf9af8b3411c69ba9e9cc0cdeea9dbcec61d0dfa9439fbd06323bb0d513fb6d384a15a1e80eb64e8ae6e6b8952501dda6272078b1ad874f3e742e5add81	\\x000000010000000138c404cb3071edafcc41bae994d714b2e7878a1038a50af0b9c51d153a233189682c42254698da4e27098f7c03477951ca6562c40e4e75618790146836b2a53ad893584b03d66ec3a2ff61f283522e10f21177feb7cb460d1d106a8d521b8a5b53c5d17735e75eb1fc7fbfcf5b426d178c9395c5fd38819d7ea9b4624276ac0d	\\x0000000100010000
13	2	0	\\x34738b753baf994537cc5fff0624f7eae5376cdea1b5126fa33dc93158d499514661a42b1e076f90b9d0bd8a4c9ce973988ca6cf106fcd5bff530bfdd797f902	401	\\x00000001000001007c0c95b16f82c0dc5f3f501d0107a097379efa4cf975471fe0ca0fc4edca913150ce0cc9ab24cfbe69e1f9ea4c170d2161835dd4e5b71bfda5a1bb659159fb1c7d3281d20889283ed7bdba0da7fcb684da1afe50811ad1973d1a8e6409b211ac0b18a7fa0aa00040e5138d7898e09d33d4bc4aaffe8f976ba0a6e93f823028e5	\\x314c73d55bcbbe51c1a8c6cd7cb2b078a8dbcb34f7e9f9d29658f7a22e95a3a72c3437aa2a6cf0d8011b07054ffa762e67e00959dfbd7a3d4281cb7f7a9b80a0	\\x000000010000000148f8dbe4cdd6784e857ea532f6357f54bc0eb768d127bcfa0e800bbfea27ec27296252575d41f5cc7f76bae9251b287498a6752c3a662e3a175cd31f4990d92834ae8709e83e67584bda7805e150fc5b345ab1a0f5c15c1de9d49cb8f849d7c3e82cb2fcf3fb61e20a1bacd7718fd0976a1717dcb55212fdc180ba1f928e7d3f	\\x0000000100010000
14	2	1	\\x5456d42d5e79b6cb01cef758f20441d3887d5e2dbda51878b9f9ce53a7fc675ef119a012776ddd0a848e7b782f40216c0214dd0ac8fab538dea2b9b8f2b2360c	401	\\x000000010000010009aac6713d65f1159fc6bb4a477bf6b294b754bb106f393a374dbdfc1fcb13fb9d5e0eccd1442a8e4e7648e071b630a35df68754ca8109b9dab5acaad517216abce9c8f6056b6a47055151c8df83905d7cc4b838a8eefc2e2c13a45f0cfc7f08699483cfe535bc058b80a81387f4deb1cda82c6746d09ec84988454950442eeb	\\x968099b97aba21cc60bacfaccbc67a607954f7881557174b321825afee807e58bd8d0a45e9dc59f94cfb3ff992c4b6f692d2e9bb33429b8fd80d22ae5d2710ec	\\x0000000100000001550f9ef2f228a5495b9d54974ff872f4b05fb96e7669999847ef5c07819e124453a52dcc2fc9844f38e571454b5763e8debf43cb5d7c78a361ccfb0355660c81b0f50f36c89d4c1bbc96e3f179abca09368e9037097cdc0d6261f4aa3f62ab1eada32fd5e6e54ce23c7d31f2638434f43553644a73db431c5f3d2b2a4b9e102f	\\x0000000100010000
15	2	2	\\x40de83b355de20a7a3f36c536d5b399bca9148ed2a00b12935f35fefbca1b480e35792514a5216a0d1608430d66d97aa47e7e31162ae53f742a0524741247101	401	\\x00000001000001008a7b01f9420a551a7d2f383a67f1547e243720687bea964a5312d277f344ca48c129903cbb66e04217af0706b8bd356c181f95bb6e14addd410d06de0bd908a18c4041155aa33b4be6a5c4ee5a1b3aa70a5bf825424631f3fa1f862c53e3b48103254986e408af4e6bfb09386ec70eb26160108157c4152b4124c1b72b2acd2c	\\x74e6896783c43f46e80d8e32ea1c8a9acf2c0c77cf1f656cc3e97ef87ef7722c7edf769ed597cd9cb759cddd463dc737891b116057374466b86d1c63490b3971	\\x0000000100000001954cfbcedde5854d8b07072dda1ab45e868456de7b90a6ee0f615124dcaefc3cd2a5bb03541bad674f68467a0a44c9061d46c914efd8bd3211d3e6da76a50287f0d5c46b118b69351c700b53fec8a930bbbea64db20204b91d1a674d3b8fb0e7ef95f9a4c3c7f16d4b84f317bc9f4522c02c08560f2bf3b42cd133762605529c	\\x0000000100010000
16	2	3	\\xb4c2b1fcb3c16877783b28844b136c4ae4516d50682dcee449784e15aeaa52d25ce70124fd91440e08c69f63c1b5857d628abcf34a4353a3eca9e1b3fc079400	401	\\x000000010000010021bfa47fc209fd1dae13537649669bfadc767dbc56287f910e6e00bdfc951fed65dabc7169899268018f65593cb3fae567a4c403d4d26f4db8afbaacb6be6794f4fc07c11463cb1de3b5fb491f7176e53eb61afff123dc70e3f45448ff86677a1167f61941153553b60576280edec8e31af3a6d40d47cf420804615981cf8f6b	\\x08966a8f5313af0b56ba16dc59cc694fb5d4c23a4c4ecdbfca413a0d2e9cc46b4232c6493d889a3bf0d36180d422a1a5d164917f9153a6c48140622eeb147c9b	\\x0000000100000001414598615462e3ef0a1012de9027ffa3bdac8d40be13fac4f2c1de7ea6afa2e677e6dd93af2ea6d28c9f1b5ef85eec7f1a1a2dfd738ae1cd394d2759dc8cb1064d43e3a94dbdfed4e6932e6d5e59d5100a21d0b307ad1be77a38e8ab7d4f5728caaf7c2c142d692b7050d0f9ccdedb40e2461118a7d2213f41a7d7a7fba8e7fb	\\x0000000100010000
17	2	4	\\x8286a2e175e3ec957733f8a12d8f6b6eb4601a594bdb91d4b9403fddf3fa9bd499cea4ab70e647e747d35ca064a803f665a70a7be3b03f740829985f4a804e0a	401	\\x00000001000001003cd0aa6ee20818f7c8acb5c4ded431efc06997e7b421dbf6a85886e1c2ab19bcf03e743e647bc44f078ba8b53fc12fda91a4f029f4399e593f370c3df5cdb4eb933d8ec877d5e20911d4b74560d1131c481165d71789958a80b61a02d5e8e1459ee87c84c8e174dac8958d303e1beee27081632b4106b5a2e3d6b27df34ae5b9	\\x923880e887d00eaa21c6072d283ddc775eac1a98872ee50e5cba87a0fd341ff05c03a017ed8b40ce1850fa8f4b4c5ad1db5fc11109873827688fbd744566a911	\\x00000001000000013a9bbcaec23c33bb53424a8fb61b624c4754b1c3af26eb956ccbf323a849e1e04679fbe9a8808e75312ba48861957d10363e89fd2618b3812a365eecef19d1974049c9d0027f9e0d8521b850d7f97307f0ab26d3e3af7c8303f0bdb53c5d2bf4213925431b0985d3bfa3292655f496cc972cd890ce112998b92e6aa441cd86ae	\\x0000000100010000
18	2	5	\\x1e41fb8db9c70fc640c3b7e20e06bd0b781ecc5c09663325eeb23bbf57081ffd27d62ac80dd31b4008439cb9fee0adf9121ae770f4b4207fdc414d35588aef06	401	\\x0000000100000100bae0d1eaa84383110719b9002d91663dc4c31a841b27b2c4864a262cc43342a134a833a2cae4b1bfcc01110dad8574274c6fdfaed16cb9542a8df34686d1a2b60f659da06e5d24c2229b6d1e7eb520f8cce65120aec6503d22e610ee479570f0835bfb3d77524c0da8400873beeac09964f0b22113dc62cca8046787a741e2b4	\\xb2ea2ae4eb700c345d98092f0d76e47ab21d93ea088810e59524cbede06b0629d5e7e35a647cc6a006f700f2233b320f41ea624336d07208799d95e2f7e49b76	\\x00000001000000013ae8620fb75a480ed628ea623bd99cd247a5720aa0822b568174dc2bcd89ea3b5716ba6654ed43d7dbc0031172f3447850ad35ab68e2a040985352407e8ffb58b2d75e0bdf3f8c68764af6fb7a2be144929dfbcefff747bb5056cd829daab30289893501b8f963ccc99b96ba8fb72ba85c61788e7b904782e7d125a324c39da9	\\x0000000100010000
19	2	6	\\xbb231a40b69074acc081d51add1e43de270012f658311119ca3f10c9383176cf68e8aecf0b1985081d75009d6f91723a6aeae0ca67d699c8ea35fe58c185e00c	401	\\x00000001000001005bf5897cf91d35a8c8ca302bbd8ee8471d7aa7aba5326169b9a7377e4d1e2cb7acdb3a89a9fac4f9f0d802a55770c14edd3acf13a49f80e7ca886235933ecfee9e943d3ba90bccb29c4fe5a4683df220329063780e06dbcd81d02cd969a3821fe539b9e07b3dbd143ecd5e7601c582a2a10dac3e91b17372b1eae0efe713b3bf	\\xeca302b4dd8aeb9e833b45ab4d5a37bb3a5d12cda3c52624dfae64e02cbdcfadd868f8dd46b72a35aa9719be002db77b1d8aad05967e182ddcae1301c89ba8cb	\\x00000001000000016e3ea8bbc79eea525c461fe2943c1f47db19718bb18e6d031a972a5499f367c794d796817757af27bf3949b5bc475b20d7e1d1274b9eba0a39d95bae74ae0e6a5b6129929910e01e72a08465edafdefe8a8e62c94311e67cdf09557d6c403676ac1db131c4ca32dea811897190a88c7d5e37397e0dbe6b548d69f382a9a9e5fa	\\x0000000100010000
20	2	7	\\xbe0cf54c3aba064c0e1593fe53374506515b82c7da6a59d387e6c5185b02d66ce7440cbfa286489d1dd16a9d2dcbc6121e29f281f10d47568691054dc25af302	401	\\x00000001000001001ef4bf7785fc77a9a8d4af65c8949469773de1253f8010224b433ee7fb68721367d32b15bb04862da29676e13a00a881dd0b508b3ea08664a19b4b7f380e91feb5ade90f0606ddf89945ca028ad1e07eaf64548f8c93e462f987f8de32ebd89d644c697ad67e307b5da673f538a7f81a53c8486122f279b9d615d230fe32707b	\\x96b2e8b4adda9453dffd793f91ca3ea681aab0e6af1a5da6ae51df8eb91bcbc54fadd678dea4dd0e9e9bb72231797a1c5eb9f200d6d637a9bf35bc92196ca743	\\x00000001000000013697cd5cbcc82b5991bc2479c68c188dbd69e94cbb1d8abe686fbaaf61365a8d5ea445f9eb7f32f8e972cd718fc76bd8eda990c8406ebbfe1487e48ae87236a6a948b30d87ee9733556fedc206da19075775ee4f1a58a9dfadedb1928644fb090dc968ff5dfb041fec5addceb18898bbd6c7e5da74e5ccd2dfd8ef43da84bf28	\\x0000000100010000
21	2	8	\\xc9409002c76cc75f2a212c076d14b9120ea74a83f4ba230381862bbb0431b738c577cebbe54fa50e01232ae5c9f83944c65ff4df5eb23c0bfede7375b68dbd02	401	\\x000000010000010016cef5df335d9c16de1f2972918d8bcfc1bc35349251d652611d3e72305711dcee1097844b32b76a0a1988e0b43b76b6a7b50f88dc747d7f728f7dcd78c005c51292998f9a563393deb3c17577ac9232139a3a99eb6a4eb74ac7d90c43bb5c2fd17a43bf482457edfc88a1bbcb00806c6c12b363d2e8471a0fbc5abf0086c1eb	\\x4c5f04732b5681923d6e1308bed8d8d738efe6b4ab594f24fc70100cdcf19d720c49f3d82ea3996ce121da9310f678e5915663d91768e08856df4538bba1c9a0	\\x0000000100000001429db4fc3dfcda7127d03273abe4ce97130512574e0ad7c459fba25281e1ba4b0e82dcfe424ab2eb6c8fe59148cedb36f59c91a4da926245619c801360654596ab695201745dde003844c292586a3ed1bfdacbb0740007f1b6933d4d0d7c07c1f5620de4337989e0d7a9cef17c7ebe484e723b2a0d1a537bf2748423b782d1b5	\\x0000000100010000
22	2	9	\\x2104de930213124ad1a06c78508cb9f4dacedb5dd602e71c68b39554d007b58841bad07182c00269d7f6c30bf849fd0ff4daac9e1c1385d779e3e514394d360a	401	\\x0000000100000100a4de60c095a3cec0aef89ccf727c03fb222f1075a6f39972446f088e811b35cfd95d695b61e5db29564a74d9021a0f444b41daefe13e949595cfe074a396bef1704c223cb003488ec0f2b5018c6d9e625a1d758d8a5707a07b2fc41c523a3ff21f387699cd00245061b4c8c1d5295aa3e5e50b566b482cc67d922913e5252c93	\\x866efd0fd89841b1b8e4854a264b874654d1ae92c8b8678fddfbdf257a94f4edf3da8cd4750c156c645eb190b8c045e817826d686a1a2b9d751ff4b405493dde	\\x0000000100000001987f3bc4bf0cfafc96e4b7905cbb13cca7e48d743e0a11f58b688299da27f1fd8d848d475b3b20be8ddda8322fd03664d311dc5a60468a3d19136389b745ec0d437426ee32a5a2c21a950f8123881399b3775970f1e8136b2c348face81eeab746ddc0e0de7fcc5f8776df847a08c252e3d586ec45e3486041385780c89e5944	\\x0000000100010000
23	2	10	\\x7b04c54804c4e5cfc59e17fbc1d9281f424c8a475786b820a7de2a2e7191470976c6f4b070564fdb9de7f78024421cef82b85edd438c2d1413e3c8def86a5807	401	\\x00000001000001009ca4ca637db791610c1ecdfea38e1b90b131c61dd33ac87ceb0cecf0af56931b832c57460d2a05af3841d98b45c181430808af0f753026c0fb8721eb472d0427d8296c69700472d6734129d89fdc9a8feec1b83f35d451266c0949cc720acc105e3ca8d90723e795bdb03fd4da7b65e0d4bee9d3e05c59d4e7a3ca8cd2012525	\\x064f45503a7a3b79bacad0682c1b9ce9a24a5b336a217e073790fc2b01269f1e7b4a414ae95ba955f4eb6f58d866d1122ae5ee0b29acf0ec9d4ee8ef99630191	\\x00000001000000016394abaacd486ff39c0d41d98a8e524e73eec4cb8fd203a0d89a5e624a985279cccaa24c41a0cf9bfba0fb635b4a31baa09946a69211d611065b6d279ec439384b062d0930ea3eabc37a75051790e334a2e2443b22c2d0e36656132d0ce44caa21fcd2ee030a6d4de9aca4d7e17da8b426ac9d42324831db72907e60cfa45369	\\x0000000100010000
24	2	11	\\xa182dd5da730a47ccb4f0763e422a2b06ecde05efc7a2fd98fa40cc27b161d2aa498f03b604ad02e04de5d707d16336868602f84f1b69b89474e6e608d9b080c	401	\\x00000001000001007aba01515793c6bebd16753c7f59829f358f2790210c474bc61974739484807273c0518b8b0811120856287f96d771718fe74ee47096226554fe4de6a45e515caf5bdc1f91791120d4988501ee47aa965bb20a766e954832cd181b4bffebdb5ee6aa3b03b8dc90317c815eff5bc4082f1ad7fc7184b959557344f24a7b00adb7	\\x07ddad7d4c84e3551b1eaa8a91e310dbcfdde1d567335471a420b9afab4fafd984d73914fa6ffc12d2119ac98d1963648cb0993b5e243f7a90c4bbb87082b303	\\x00000001000000018bf5b3644783c7fea34f1e97920b728d531fc03be4f6ec624c163311d71049a45386b411eac0179e0f2a436b2712b1153812c17230749cd6229a8e6c97a15d0c021b441c80af87df38c2bf4b7033f78795c809a35eb38aa80b1c34664ed2012bc96a31bf53dbb5d4e1939c684fbd2ebf5817a78525aabe7d37ac5d3ca42fc805	\\x0000000100010000
25	2	12	\\xc93152b58fafa704ff47d092b55d931b04229e7ff4084e31b8019ac844172fc82dc8e781455768c4149c78760583f0ec6eb5fd4c8ebfed8b2eb046c5cc7b3a03	401	\\x0000000100000100426de8269ab9217c37903cb9b46ea0ca6c9e4287f8d2a8cc57b6db9fbd9ec9cdeeef4f6a5114bec4b2a7279a19005fa6cf73fc0b3cd1a5c0d6d8c2af496523ea860c03789770f800dc7e9b070d9f1fbc1ce47bd96f495d5386d463e349cfb8582c29f3e1122aa83e62463000fd0343bd751ee83ff345ae9446ab2bd9731f1ec6	\\x5679e45548265058a8fb92435be83fedd07bcbc5e322999f91387f986d284f7eb4faa6f5fc7ea9aafac95b605ba983f06f8c3affd611708cb2fbf2879c73264d	\\x000000010000000108fc8273d840a09282150d4317485f1760f31dae96581aa119627b176628f648cbc1fe0ecaa9d9e4ff4d8903b7cdef155b7d38042459b187ec9131fbeb648a756879b543d5aa8d273f2f5a35e2ae0d1efe5b3266765cbff1eb8d7f46c281965cca3f59f59710010a1c4771dd676301463d26796dc457c5902478bbc48d4ee467	\\x0000000100010000
26	2	13	\\x0f62f0bcfeaf0efcdbe9e19f8301921f70043de33855fc6ae95cff67d2ca3288ddd9cd4cfe0ebf3c6a5f05690512c283aa1282adde38e3c1ea810e852d94b808	401	\\x000000010000010090286d048a28ed68d85b1e260f6271fe0a7cbc879e87494319c453fb0ec1cd637b3aa54d5db8e2ff85a65cb225d55fa631cd453ca9ead3ecc766865b232041e8ed79b975598fcf50b906dc619268801a361149f400fdfd791ed2c937f8f8c58368776185844b0c0b8d6c77a7a0bd11a88bafd5acd85219ffbaaa14357b93ce9d	\\x415f51536d214a8896f09b48e5732280090ed5fff1e93ad1cb18b1409cd4014fd751889f5608d472309d5e8a3e4531b543235ab1aa5aba4dc48ba9d5b7a4ae13	\\x0000000100000001421ed73b322ed55bcda2bdec19b62b28ea9e7fe7d766b35495bf075896a2432c0e66a016541397607d04ec48e458a70afef7adbb3b473c2822390038819f2db4e7d1c6b5fc78ab432bcecf2ae9a20ab9e9e5bf2ca9439bbae738ca103a33c7e1bcc38890087b1a6b26f94b70d80c3fc5ddcfb79f8657ef4a529cda054fa890ea	\\x0000000100010000
27	2	14	\\x026b7bc28b5ca52b61d12a6f8dc24c644b2a590422d51ff9f793a253e64240d4b041fd8f03660996cef1d71df065641013d587d8d9ce912d8a53442cc500d709	401	\\x00000001000001003ae177dce56e51101918898e1bc22586948de4befd02224ff0d5df1e349601c55453c293b73afba246e62422705c75b0e3cb2faddfcf440ee60d9a817972d2ed515e304d7b143d49c1391a4b30d683ae89530e7f746b8302e69f373efc4ac5f08466b627ed89932bc485990665daaf73ba78f578f9b8f8b7db8ab45a66d97984	\\x7808dc8e78dba53e79dc62ce74c4b0c21e1da6b62c66bd820e0c1bdd931c1f75279381182c1c46cb3117ac3276d96b8eda1086a779493d28eca891dace5e433f	\\x0000000100000001185d577fd7082fba9d7774561322d310a5bbb1801cdadc669a897bcffe7f55da57d8a4a5d6cae1c5a34e93af9822f947db43486a8dc3b6ed6d2b9067a04c3c51e9b419fbf6d2ed877244672fe57e7b460b5179284c996893d50d7fd92575284673d0c8ec70b7e68f42bd711361c6d51772fe1a8677116de6a5da895efef613d4	\\x0000000100010000
28	2	15	\\x7abe2601bab26d4aac1df04a7af36a99ac1e4015e9617ba1d6f4e0a606059508de5de7017541b5b6252e87f3d9b33cbf7497fa9aed11bfc585ae960aed4b4f08	401	\\x0000000100000100a197ff8781d4933722060673b9662905d5e84cab8ce82425c96a63bd9110e18f1782f4727c39c453502a3e426a98befe3a840ed4a02fe09c7fddd10b8207a407c1dc50e7f2ee20ab0c7e4f64790c7d507045195e6d61dd1446f887c49e5e471bd22fec00e1c1cc172ad5421ea2782c7d8ddadbd0af1b128e7c2ff56103cb667a	\\x7bf851fdc3a6bd114d4d348eb1e3af76adf7051339e753f54dfabcc4d83250c8343fade68b0dcd340ed59d3d749b14f68c8ba5c399f259244f14cea10a418f0e	\\x0000000100000001b89502ff3d50ece0abe84c607cb733c38e0b7e2f2eb7d3da973affcf215e3a44cf8622a4851ffd1c21a4061043dd156b7908e28ede69448384c4975d5563f60eaa8c2ee20faecbfeafdebbbef71d448d5efb0ebddb2265683397fa20ac0c4206b30b53dbe3886a6363b8fd3e8bf051e1fdf76a510ef1ef3bf9d12ad6ecd36de3	\\x0000000100010000
29	2	16	\\x1595270fae50ce80a5c48ad3af9936ec4998d0ca9c7644151878ea3cc71a22c84c8cc3a83bd4873a8d8a460bae217a049767352c7f024b7c1f9eeb9d356a790f	401	\\x00000001000001002de988c18deb6fae2c022d5821f520fdf9285343e6a5c222ed67b09dd5d44452ec7904c30a032dab426f7430592c8abd4dd26a948451dc23f71b735472ce886115657ac9ab2a134fab72f369c83fc6b91469352cc19d8d8109b9969c0fe2977838cc45d7f93e49b23c592e561866932b3ee2ba02d19cb8d84419a87627a91d07	\\x341958686959703fdd437d91110c9b05ffcc1113d422ebfccee60fc8ac053cf63db98999e7f23418ec7d9391fed50c9b195a9052a951d94c77ba189978d150dc	\\x0000000100000001ad738fe184b19108eb2445ff2714122549ae2fb31167f4a177805db1b13ed5630f8300255935075eb0b35bcaf78fe3d5ca32afa9b9660f966915e8a166257f4449d40e52a54b36159955bbe6b2e2e2a2c324cf4a6c85920109187b06e65804ff8ccf87790c35043b0fd321943a702c81c3e5df2b45dbf2f0880428714e57b91c	\\x0000000100010000
30	2	17	\\x797c61b6ca3c960a1f50c2399f1ba1441962bcaaff6c5823687cd266337ed485b3bb1c0532739e14de804a24848675785e8e3d286df7e7b64854e0cf9d3fca0f	401	\\x000000010000010052c6fee80cbb280d6d5ef564d2d8ac67c3f64121bc6685ce22f1d11f1f6eba135c45eb8d3890afe9c19ee9683d5d52170816c44abd3c51acd725eb601a287a7a328094eb3c09a3d987112d25a2999acc64fcbe88f36bfc2859168c6fa702e397e521cac42fceb60bbaead62ceb352f35f6d2c7b313a32cf0dd82c07f6a79103c	\\x1783c421d84976af029eee3ce982e3963c7f8b294c90d0bb38803b874565cdccb2ae76f4e4efba7410c7694abb5c5199d02c3f8f96233925b0cc5bb5b13ce064	\\x00000001000000015b7b0389ae3ba1af509f427376ad7f55bcbdd49939158cdd5a5431ff32c602b31d183d48fc9d3b85956e0c834213f704cbe97e70f0d53d6373c94c2cc1350a482520768cbccb829a73e44a6b08062f6d059ba19f93cb1b779a575df92753383ceba0d5b7a02b80221e2858049a0c285410832e8aa326bfad080936eb950c23e2	\\x0000000100010000
31	2	18	\\x77edfed1fdf0151c5528eb99102e4b80fcecec44130e906a1c62ce16edb7690d566fd300eb6793a96a393cbf41ed34611dd018aabaa8bf7de0c54f2b80b0790f	401	\\x000000010000010049b519ccd2bf66685f810d6149a139c59d2c4ba01764318bf1c77cf790390f83b505cdb6d09fe4f1dfffd4aca5ba84e42eb618d59d22581f09a02588dd6f1a21a104019fc149bf7813e0185cca49881f3d8eba51dac90f8d21276183c9aa51a0eab03dbf3c01e8442418366330f2dd4fc0f79dfe46c4f6228a13781d971c6483	\\x22127cacb268dbc4b3579d547477b840d293fd042607c314e28c1f222ac2e9ff815dababcd2cb0600fd6e559ca6cd94db7726ad2e655c0033e9aef5d93de5f30	\\x0000000100000001994cfcfd8a6dc829a1cde6a472ddaed76533adfbe79bccd29c278d0d6cf9776e3a2daae4310e637b2b734510d7ecfd63347dbf51cd6358b65e106cf903796ace6ffa60d7456793e32c5f1c2e06126ebf76ee39c1abd54cfc2a9d5add447eb8d2994cba53e428d1aafa7d39833d3142845073c6f2c178cc1b097948065cbc5cde	\\x0000000100010000
32	2	19	\\xce585ed69c4448a43d7c87ecc31fec44f02b8970b1705597eb9f7f7b8f216a0755686bf9a829a1ab538b071f756c51d55141c0f22e0c50637430bd967fa0cd01	401	\\x00000001000001003f2024e549aa41ac157e997ffac12cfa3c1e0966a79d385ac941e80000233e9b39b78e7931055017a16403946f47d476932813a167d3f0a699b1381626c3353e9bbde018085604e244cd562796362ab01ee41f113be43ccbb08d5f18585655737faeb389a87f2cf99fecd4e0a3e6ef2d6a1368dca9c130a49b4f37831446a75f	\\xcf511f4197b5d85bb3765cea06499e899e557696979d63a250297252d9b6dfbac2b0396b6c840ed2bda436f8393126101792064f7fa08f839f4ebfc09acd2752	\\x0000000100000001c44c6e4ad4a32534b98e69987f74b17b1c4f549829a15c73023bf363d4f2a644df96e89db97e098b3ad53f0242f0c97efe06b3fc21ba5afd78ac987180f3928cb5df39018234d7aaba43d14dc2141f500629e4493a9f3fd4a855d65c6313a1969ec5d89a27af1fb30fb2492ea6ef7409c883247c5989f64dc6bb73ba0b6e8235	\\x0000000100010000
33	2	20	\\x40c7891fd3388c8b29cfdc04c8c3bf4dd7cb1b991d9a53249f811bd5fa712561d014d612e491dc9849318df59fdfed82970257de146ba91660819b7229d4fa05	401	\\x00000001000001001635c8b05eec0f9963c61fa68de1b1d06fe75b6e81695dc1002e09126918e2d5d50f78b68f9a3354357bf0e43bbcd5b985bc1210f62ea6bcb1b68f05a638393cf2abd96e7a6f5da30c876d7718888bd99cdc82e11f6db8fa3cb30fef239f5fdc94a25178fb24da2a81965b111b2bd90d91c02a3bfbcebb89346e0059211edffb	\\x5bc3a437565a7e7dec660c3116d3db845a20a42134b5d2086b69ed038355dd8dae1b5d4bc626ff45cf933adc420b1bd6cbab5c74147f6aa53a50808928eb659f	\\x0000000100000001b9f157b9b6a507651476ce4d7e6576bc43e08e2ac690c1b10cfd0afe154f77256308c9a702d727740b5c31d8290b3bd10215ccf4f7f154ca475369e82007c54559a8564b9711a3f883a26ce38edd7750ff707deb31128ebb5e1ba268fd8ffb3af798c4c175ca9ceaa2255f74f835d9837491a04389a6599200a5442d67c88863	\\x0000000100010000
34	2	21	\\x41ff408381bb967c6bccbb73d822729dea50be27bcec47617ec66740b1f6f5d6e9cf9d7ba6f97f5da857e44f2801cc6c9d53b1194eba6053725c45b71a11cf0d	401	\\x00000001000001003134de73da9d8412253a0b2d685d629e875b064c5dee855539b9a018abb61f44c654ddfb34a59e1e925bd5cdbc36f13f661e670afa715d404427d3ce4069945f9ebfec6b1b737cd95abac1f828a5aca2c4eadc40333255474b36bdf6f2e3118c6f76edb85b262be59ef995b4a0bcc6bb3ff38e25221027fd044e2e51ed8d6ed3	\\x1ad31852c57bc1c9848e22f80bc9c72acd0bf836680fed9b11f83d9b40654688fc0f0a7c34b8a5155386ab75e2db0e0610edaf48968fc976dd2898da87720302	\\x00000001000000011227b9c75c64efcd788b9a89053d702a54f493e888de7763ae0fedc47fce13618587527a01d64dfd4f7f22c5aca468059889f5711b4e86110d56479adf6064b86280cbdf070405aa2d14982784633718a3cc45d26ea3d1ab8559b4406c96affdef3962c1fbd8570138b0c49f9201661d5351608b5b5fc2c4dfa52f682ca59690	\\x0000000100010000
35	2	22	\\xf0bac0fa44205a10960c6055dbd481370da6b5f9d6732379a0e9fbaf82f44b2e2b864b237844247c2a02058d436b264c4be7b20f6287953d57efbecb90f4b502	401	\\x000000010000010037afe7751cc9bb6605b6175ec25511fdb244ec9bd1bfbf23e732a0f114519fc1a2eb843b412d28957725f8704194ce0603ee3e667a6dc42b10a83f4e55f23866ccd4aaebf7599f2505c385addc3745cc23f3df6410e98af4aa5d3a518bcf9c45690e813210e7336aaf8da1dd70d5c94d95a9c080c2fc29583d97b81f78a9e236	\\x22224aea9c236c93aa2290c9a47f481469103b290eeb0bfdf2ad239bd96c294af55f0843436ec45b00604828868023fdf23762f8060003c86ee1da1c0ef0c89b	\\x0000000100000001c1b23f95bc65f7efe7a9ef11d18c5c3f9a5ee8a9ff27107b9f497346414d2b4f56fc4622ff323567f2a89ccf0ae0c2b4c3b7a384a3962527065a4701f353396d242b925b672399cf660e4fe0a5453d5fb989398cb58051afb5fad747ef77cdf045d0abdb518a16eebfdd59bc462390387cd1d7a115dfe9b14993ac9e07b23603	\\x0000000100010000
36	2	23	\\x37b9767b8ff6edf2d233979f10ea7275e33611c2275bd9f3034f63cc2b7dc036f6d093ad7012f6b5acf51ba5a619a0bf59a5520e38eb95a51ec54b6f2acfcc00	401	\\x00000001000001006c9d25053a69d8538af742362394536bd5117bf704e32cce16b13304a6cf75de0cd06c3e20ac8c8e7ceebf772c71f474d92ec48a0352c69f92a476c5b63978f8f9fcbee6f78c2a7e217cc539b8f328e9dabd8e841f72d8bd163184eaf94f5f78c4c678a1e44e664687dfbcda30badbfe4899e2afa54b1af3375d0219651578f3	\\x0841ab606f4dad399e5c35bbbf3086c244b7e442db222ce6848437066dde23053a5db3b25f20b6179ad62d9fa7a13ac5f1a187431bc95a1fca91df5f4cdbfe76	\\x00000001000000011be5344b7d7ab342dea77d357bb5b3c413a375cc7b4a7f0245b77cd8c2b3dd080bf3169e9ee032e401d4a50be3012e6b9bfb533c528a0febd0fdb3e9ca872d6b0d514b7f93bc25c8761209399bb4009d139a5cc15cf73341bd387b42958e4f919f594168b68020b1f70d1284d932070e2d7057ff419d6097eef86686e055de2b	\\x0000000100010000
37	2	24	\\xac68e541f257e41cfff5ea4e5f9c9d149fdaa6780a64b0b1541854a4b4b93447f771567384ff35c0e5f4c24eb81ba6d83ee4779cc153cb9033172816c804940b	401	\\x000000010000010053b4233dc2782869ff6d2f5dbb4c687f73f1cabc64ce8381a5fd506a119b68aef2e4c4a61078785324dd681c64df9c3cf08b9d180895323353d1b74c144745329dabcc3b836edf1d92537d9adf0a36aac5eaad20c67acca75a233db912f9202c863db48f70595b169e5e6100deb9065bd67604ae6d3374af70a7d869016a6bf0	\\xfb0fc601f1afa29a98ec3e8a06a2e4c4144856c5b0739b4ea93ac7e3160745b2317b12e9da6077cb4cee3c2d1be054f2f043592e61b2fab02adf785070b7584b	\\x000000010000000157a3129101fe706844cdd6b3d7ca1406a11b24f9143b223cc4084909e323eef3176b11e1252312cca401dd38bbcbf42eadeeb84f52e02ac7539db05be61ecdfd05d768602bb024e7ec8d0570a9ee1f3811c36e95e2452881d73a25a44bf120d2c4fca4bbaa429d0650c28451f366e9bf8e4fc88e6d22a8a695777eced34a971a	\\x0000000100010000
38	2	25	\\x43f5063a188a88a9267762b95b3f53e92f5312e0177b6c385cfe8457f9fe094ca472bd8b8be87a07f423330d0e10c4e6d58285a24128538beb35a93eb2aa6707	401	\\x00000001000001001cdfc41af7807d32a3091b904e25bf758c61cbafba3bf31662b7d797805ff9bd095f18847cd5ac06f996d597f3e17fc964d79921028a5b804a81ef0eb5cf5d532fbdb332b0195833f1a3d27d34c8c347b79bf2b83f946b1690248f9d0b3c4c6978e10b3e6dbc751b160a7791b8d2a84de2b161f757446cf516e7fec7444792e9	\\x4b5754aa5c010b0f3c7edca87b7b4a98d78d348a93ea678c659496214d30a5ae12b79ac5d0332eadff14579656b3530980ad20931a2a62be2273f2c81d7a7e3d	\\x0000000100000001ba77c034e62a10ed901b03feea0119e74770c5f5ded54ae6bca4a1428137005e8477fc93e9d7e7c7bbdd81892e0f5da536cb4289c0d2f8c545f037fefef3f2ba148f8b91af4c8b6a90d87651a4bce6590c611f987c54d063aecfc7ee82bff9e2fd0480cd2f784ffc98a8a12a102934c65d9fbd0de105441f0db9993cbb265f3c	\\x0000000100010000
39	2	26	\\x3001b89773927ecf5804f4206414ba369a03b3eb3a6ce4019db6c0957bb8d279b2d8d82478eb723dba364b6684f2c6bc5dfedd7367f55ef546a785a468c2fa0e	401	\\x00000001000001002f0e78e2c325f0e76b25ee57f859d20a8a5569088dbce66756a92294957390edd706caa3356d6b513a9d62de8a94f16847d7b7572a603cd846646a64baceb46da189a0fdea53d2a344cbd302a921e030e70992c06a998787254ad9070e9a6de10374e207991c291d0ae36561c1707bc94ebde8cc2c365f793f6fa586932e0ff7	\\x748480c03120c66c501ebf3340e239010cdf907c82638a8d2703d5893b94f158868c00cc29ee0d12c8c30f5d1fba31a873930b0264991ca48cdc5deb445fde7d	\\x000000010000000101080c76681934bf29784bae1a328cab10584ed40226ed89424d726a22393b2774acf5833dfdab5237617e54f8fd035f6f8201b3016db34f83e2bc40c027cef735609d50eb37c899bd3a5ebb27561eb6f0ed7a9e3b4c8bc3066c728ce9e902b841ed6073d75190ab06721b0ba7faa15375776006eec002a180d7244aa463732a	\\x0000000100010000
40	2	27	\\xa7d9d6758c122f536c21fbb6e9dcd8a951505af0a55541cf5a687596e7bad2a265f4f83997fedf82e20919fbbb5e323d5e5833c81a7b6dd0bf52ad4592936e0c	401	\\x0000000100000100bdfd0e9e80a989b26410215a3267c4c79181d66868008bed50a5665fc7599c26dd9b98d58a56dc66c60c89afcffab9e214e0a99daef0f8ffe21f03843cdc51037b3c4a34e08587d6bd6eac22a26583f6f44f81a2f6da171d6b1250cd1a365096eae53fa22f771bfa716314d71d3202da45cb802fd8b4879c616e7a8977415cc6	\\x55c291cb409c59a3c98e6e588a0529744f0dc9d9f18009e77f31c7d7481133055c410ed8ffc7ea3bd44ad251ae0b6bdfb988e8ceb69270cc81d0b2e8d322cb14	\\x0000000100000001b9171825eeb1485cd6217740f5da03487300b58814a9013e579bc592baee2dc776723f2fa6b32173964c7cdd1cae2ffea7212bae15344538b78c1967ef0ea18d85167b565c8797c9c0d5be63f3e9cc2dc0f1cc1c185469368fa1e90d9e822f2425fbbf6a2173316d3a561998f555a8591e12a4c17acd076f0473d1e1caaa5bd0	\\x0000000100010000
41	2	28	\\x3867b38c0822d489d0e35455a8adf83099da634b02ba95a5616482d5aea5f9a48159abe0e8ccd0fa2d81a2e2550bf53e0492ab178697a0ef8f27c7672a2e8301	401	\\x000000010000010099c3a5be08b34da19cc51af0c1e6239d914fcef5f760fa406980a13e01d64ef06508633838af809d5c248b1009e29b3961e10945d3f506656e822c1206d062564df7984febfb171eb2e35f7d99b1ce634e6b53996092b48c2bcb0a5dca7c3a9173a29c0d13f135e76ca6f1c9f95755adbed1de8cfb9a0120f56eca19867436d4	\\x234915ad3bbeecb67856e5c815d1c9b096e9506c31e2628d2093fca0ee8a28b09633d22121cd436b6087d1eb269f286feeae31645ee6d19d69c4910205a5a621	\\x000000010000000191b7551eebdcdf4593d8d0d66f702ca791fa5a1752fcb1dfed5416ae76a87ff4aaeaa70a43553f2aee5bf78f92ffeafd3c9c6d9aa2092d5492b9642ac13aa99268e67c2a1be7804dccc8c01ae997a413b5971a45c72a57d92e657f76f2c692a4ce1afc8f99c843eff4e82e38a3d3e0984744f85c802265a785186e7dc024d46b	\\x0000000100010000
42	2	29	\\x02c98e2a3c40dee36eac2b41461ec18c64043020fcb02425813df0c349aa3e9484c127580f14b3922c948a0396a9b26af335c99e98f32f3db0ab9d5d1f6df50c	401	\\x00000001000001006e5c688e89d5439e9e9ad5c20dc43e10c234ccf5282d94c7dc83b12a06935aa220dff0ddd28a0d94715635969de3d1cf609e83d0d7203359fbdfef721f813c2e605ad506785f269180d971fc984615e9f3a3dfe05a33e9070ede530f4f8fdb4de54fde22bac6c403fb11e3af47ddd54e096e40ccf1a25ad2e067c4ed9d413b03	\\x3e5b23f1446ec0a40c0667e12560e0b666b5b073f242abfc0ad5392f92560df5715025b83682cc5befdd9b0cd521a70da851950c3d17eb7957fd39c239a917bc	\\x000000010000000190d2ea7b61fd56ed234a1f8fc5250234072b1ba1be6e2022f9ed6cc699ef32297f02672bd91f9c70bab0db48622eb96466305afca76083823bfc10211de6f1d8bc3f406e83c49013ba52027057fdd6b723f197486ec287a224dcf37ad30a3376781b721556c4f878aa8f8c7cf3ee0565769808c3a06f5c9bbe09d9596cfd9cc0	\\x0000000100010000
43	2	30	\\x0fe56b86e1e540b7f8dc1a4f60370a9eb5c2e4edea0237c87095023f3c71c1dde6a8dad7de4a8c8cfc67249c12d9c276e3d73aa677d72096316bb726867c4607	401	\\x00000001000001008efeffbbf19d7fb29e01ebb010c2953509795a18a8066abbd8fe81060eb2950530aac7a3a32df368d4251a028bbf97934575e9bec0f8d154e026eb2c54591224d929818b7161042743d7f46aef0a44f17ed83e14941929d65d1c1cdbe5541b67ec51594d8bea3593cac4478903afda704178279ed36eec0d7d62362619c09e19	\\x684e0c475cb2879cfbf0b58dffe4de0a2b74f5a3a34b06775334867c1fd1120884a90b086836eddb794b03345fd4e283fa2f880645150a39cc00fbee5dce5968	\\x0000000100000001383621798e1d59a3e0fbd7fa98556e808294beba3b54bad03d77bae56185c3fa9d217e2415ce5c6382ac5bde6a5731c69824311eae4ab491d5e2eec202a66265b69d2feecb422ac1674637941878db569fc319ed07ee691d761858c6dbaaa79ddcd32789e5d0c4dc2fa056bca96bed143adb68f5363e16f41daeae25026a010c	\\x0000000100010000
44	2	31	\\xffad39c510b2e910413785e40f50dc6431407f671caf5093bd8f4eccc5eef35ea46ffbe5c58477e94f9c66c290563b69209263eafc3dae8b1a49f1e3eaf4fa03	401	\\x000000010000010066fe7e48c6b701abab109412c3f6c4a996537cfc6851a02f37ba5659c2ffeafe9b516685bf4f515476198240d41210740a5d77abc4175952ab60c54fce967a25457667936f457eb15701555ce75008ee36424f506d6471f1806b8454ee464341a678df5f29ed9a83b39199917457578ae93a0e1f57c49ce4ad13065471c15f44	\\x15f495e5e6f5b61bca0c8a73c3e439e2937ae0b2fbc5209eb3956e772411ec7a8d464302bb61144278781eef3e3b882ee2d33d75eaf22d15b32662d4b8c9f3e3	\\x00000001000000017052ed312b2695633775b56c096623a6f59f32e99d55717eb7e1c0ca4045f3846f7aff68203d71f9b3668288e204dfa45e9407b9cbb4bc85c7a632d699c8914e2334badcf95f09be42b04e5938dad96c1534cc682ec1e74cd6b2950e776d83618dba72868c7fb465694a1acb87309a652a47ae5694da5a88ec9fba001d858943	\\x0000000100010000
45	2	32	\\x08d9c034a00762f6720d7c87db230fa24052f5a53bbd6a08f5360bd24336687c21c72d7e06fe3b785dd0380a41c5496eea68b0fb2eb95d52f503c628d29bff01	401	\\x000000010000010066e1ba4d34c55dd210a0d08584fd7725ef6a2856e9ecea95df98d0ea892038a85724d4da77937415df702a3b6a3bd1771babcbd8d49ca3284939fe7a928d3c1f2272a2ac2dfc5bbf173ad429d34d5e2948c35ead9efdb4be00ad31f585fc8c91ea4b16e37d3f1f4770001ba5ac99a7aec6d338ca8991458b4b64e36238a4fcf7	\\xd73ca0ecc59af2266e357fb5f5648d519aa68b960cd427d558d9a061e6ef9eeb8e14db077b49e74363577ba8b195785af3ed5b6943297b2b6a1110252d2528bf	\\x00000001000000012a30e248095d3785421c2a4fa17b50e89bf27f0fe0caf90b683ce6dc31cc88fdd737ad876eb8b693546da71f13f10a43d0ca07a03327688f305d76ab4272d05afd8d36138bbb70efa7ac18e808fa0c18ddc82be5399ec5c02703fd2104509a2e52367b78924301980a0e03106d5a35ec4a762846c5841eb00240f2291d704751	\\x0000000100010000
46	2	33	\\x46303fd9e836c4d1602a78c620446790d4437e6704ada051eecde8fe1294bc85b28e1b2ae32b1ca93342971657e54d1273a03edba33b76cf6899f542490b1903	401	\\x0000000100000100bf3d956731a55fba8ce5218c8a825634ce2052bb64e0d5d518731d4dcbe18c345315cf6316bd76184802118bc73b1dd204d8bbe6427631311475a330890343f0ccc51fe032d19a005f1aa86a44809f85a3a78648619e7a5843462cb333ccc844284978e4d5adf58f25de8a91f20b6b37c8bbe7956424e3c905dc61ad403db9bd	\\xb6f21773bf0803b39dcc070133d2fd60cad7d2a08be5950b87571e64586a1451d89b660feabe27a0cd8e482122b961b214dda8ea2d68c8837d3eeb257a4dd213	\\x000000010000000184e5734fa2d2c49aadaf120a5420409c71839d72318cf1c09132d839ac2928f0e46d44e7909962379865f1cecb548a3f859c67e7318f2c9cf11a962dae8b22af10f45eeb6550cf59b4e611ffacdb8375777f17086799c96d6c621fba116e78e2a57af1ef1df2a02f5c7f56f2eae831948b002bd0c6c7b47932d43aa3d1821212	\\x0000000100010000
47	2	34	\\x1324b162cee9e07a3c1cca8a739f9266f10e24a93ee310f8f69a5dfc8ef6556107016f46aff6c28594878f8550938865187be50e13930e0cc38b61536f074a00	401	\\x0000000100000100ba9abb0365b55335046765f9d3d2e304cc6a8cbaa4312dbc1993369d22940bf2b5a5d242d12f1cc006ccaff2f04aed7d392059f886c1b04d184900bb97d0a67c73dd909686a8a35742efa73bb3252e0b9e58e199c1e6b9eb21e2c20bd13ce0ce5632fb20f22783369f9d8c82d6618396658c000ca19f7e5252864325dfbabfee	\\x6fa90a68e07232d8874bf71ebd2854dcc2612c7461a2f2353b0f4fad2eadf4aa7e1e657858ad9eeb6f996e533c9f13547fa4f4a1f507027c58779d545f86ff2a	\\x0000000100000001578e67f4242b1c6b592e3897383bb6dce59bbacc08b0c1cce5aad203a260d545cef71c68a084f57ca118472d55bf5c873f7c0e73fb1eee3f1e1f938a492018ae8fa990637a2a1c49a9aa386166cb82c4ad9377fbb812fb9efa26d4e32fc769af5af4499f62d1d610c2b9a3f244db150f06071fbd4086f04ffea6b017b2b9c89e	\\x0000000100010000
48	2	35	\\x017e77159e78b7216ad3bc015040e63fe32313bb710bb2d27a1a06de7f4c0ba413aee77bcdee3a4d63e47b3250154d0e2a9f654adf1b5f152ce22bb4e3ca6909	401	\\x000000010000010043740fe423be65af93d1a661fd42583782b94fff7d0e6b6437e244c626a9b4e62ce8026936a0d180fe3e43ea382619e2db464ce8341cf087ec9ca6085214fc5ace14778c0198b2bf2194e865f550097fe855725757c859ce9c6138d320a4390280583c89526b4253fb493b5d8ef7af2839ab890f03917a0d10255d698e0ec8e8	\\x975657c481a18e0222edad452ddb897fbab55e5b41e1b8aca678635b8706782a94de141ef2857f3c9e7bc6a5c49734061bdf5997c237f61f0edc9ed669ebcd0e	\\x000000010000000185e60911cb40042b43e5901a7f75707668ed76e6f04e15df58efe64a7d8edebd42be2a6e3da8c356228316888eef276e147f5af04109a96a678fcedfff6ed84bdbb9be0f632aab645780a99ab5f0d72815f00da2bc2cda80699ddd732d821d5fbf8f7c1d6a3c05f8cdd78ab539bd3c05e0a6a252addaab8bbea13cb0e0766664	\\x0000000100010000
49	2	36	\\xe1bde8789c7f8bf4c8ef06c1b500cccf6633d6ddc1a4fca3cdf56a3f447b0b3ce037e96ede6766b3a7bd92ca750ae3cf50160c77a6eb5038635e299d2db4ea0b	401	\\x00000001000001004e8454be2810711b1d2f08dddbd7bf1b453017bc1e705842684d4660e0bcff66f211808f9ae6521508482457ca2783422e159ef683f905c012bf6c01adb9e5e3cbafec67729cb4cc72cb5a1439d10254afca3ad9be8840fffeb08a53ad4891eb323291039345fd82d3f5f76688e165394c043d81b56b4c838c04f334af3a5603	\\x1241e8e76ecc6f409bbd78f6f6a36fd3ad3fcc3d260028519585a8a5f5f76b8d76a0429be841dde44b6e376b90b725bc4ec5a78ac1df48cbe1854f0e4190c3d4	\\x000000010000000149afa4c0fc6e1297636160804085f01824eb48cc6e5840270ec0f72becb5bae5a006568179e9090cd422bf24cee948d421edc537f45a171297093590076516087d9c8c72e326754fcd80f331b1aefe847878cda7fe5516c38d8ae5c3f48e699c35f68906bc8cadfd97262d86fa42466c4ea1b33411c216cb78c7af5145d0530e	\\x0000000100010000
50	2	37	\\x6c8bb1cc272d865ebdd8877cd60113cdd99eea892ed85194230e52c6ed202d7cfc70bd9ad7d5c214a6629f95a183612f3a1ce202b1ba049e7a607bffb626290d	401	\\x00000001000001003f82a777ec46d5c82481bca89d1a80d45245fd9dfadc365061d0f063138ccbf6c3d2258cd31638b58b19894cbad841e824cf2253be00505d723987abc51f4323e1e80c580cc596c4515ec522f72e949eb300822cf27340a05268035975292efcf3f79aa9c4fe325f25c597a767f50ea50ea796505d1551de01bfc33a03f94800	\\x47a1013881c0fd0bee865463fe672b3c75caad83b8ad4332020c8d134f8b15901217ff0f8253e841ffb5095a06f6cef001e1a0247664c49dfbcbb24bcaf01368	\\x0000000100000001a4becb53f518be954142882acb76b912733912c7b1254f31261885090e94c0a6a33101010d30696463da5a849447bbc0f9e42b5162e480b31910d625c4c7f8e54a1b51caec6c57f2d407c28e6b007e2f7fcc78bf47e801fd7eea52abd3d073790098060931e88b1d1fb7256e23637e86da264fe60db6d089a11c7a608c042456	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x8ec3b4999b409f5ef487eca04c644ad964488059b24a14ed83635f8a5f99f44a	\\x165f05a4eb49af876b2d7e4ae6ddfff985dc283be84a72df6107ee64a83c94cc146ace919e1c67f60152517863aac60672886fd92b6e8422a4e3e46185a12f8d
2	2	\\x9e89aedcd3264cad24bc22a34358becacc45a70e9d84798447bbd4af8f66403c	\\x9c46a827e7f3d833254e77dae2ab4287a34397a65d5d8b11862c69d5c02ca032dacaf87ae935bed102a072de5631dcc63011aff09aa0449187c4f2982cfc9a26
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
1	\\xdfda4454c0f9bb0df3b96d12e26a74e7c9d2ea3b7113f36c9223d4e4dff02864	0	0	0	0	120	1662916141000000	1881248943000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xdfda4454c0f9bb0df3b96d12e26a74e7c9d2ea3b7113f36c9223d4e4dff02864	1	8	0	\\x3ea060af2de1c3ea9d3271f93aafe66a3ed5ab7e1c7844ae0c2ab727ccb9d787	exchange-account-1	1660496928000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x43dd8f09cb355034d87c04b4575e347416f66e191a77ca6f0bb50399164479d2ce1e47104437d470f3b6cbae10b032e5feecb5cc5ddfbcc639d61875b4e660d8
1	\\xa0c12c5296879640ccfaf5f8f5b254a473bd7459caabd849a9fc661c8d9759bf6dd8b61ed53d8882beb19b73f00ca970c38852de3b01198d49348a14172cffc7
1	\\x54b13243aa05c3abc9d03c38ddbfa7a9273ce992185ef95cd279be50ef5590f637e5d195a4730ea15fb1409025bcc534d6df287127b67476338d3087ceb0e9a7
1	\\x1e3e22933c1e360eb037cd8e4ecac4b84c7e5565720784dc38b4a859f00f886c8430e532176de43ccd892653ed91733a3b46dd13617f091f14d55a904ee0d6aa
1	\\xebdf00db88b22864104dada165b0244e97f3650d1f64266aa6dae25f9b4057492ba4641dbb66146b87d63d0573e97513601bc63cda5f1691ec03bdae61eed130
1	\\x2332e7947adda29ed89734a5049e30c64aaa511042f3faa06f75915fd7499e02bb5e8afa26dbf198a393845af5e1f28ca6096a85cc26c4a68e5c9b4ff46af521
1	\\x79f15e09dbc95a1d44adaaaea7deed3ba4fc256f251520ec7ad4aee60a2c1be50bad602c102ed35dd7a9b993ff7369e8626c5ec7eb952a9fc0b64c1649072e63
1	\\x566bb4619dd67927faa19de302610a891eb8bf5a4b1fcc8a0333fb173aa355dc52b3ad840da8c8868352007e8d21e6b84d0a97582c965fd1fdc338979e222e0e
1	\\x8d1a0332eada043c5b0d0ace51ca2db127c2b770ea9765f2dce4c2bd892e0b37dd8b600f84edb0152e8d1a9f4fde89533ce6c70b6ae155285b3bf10a4a7ecc40
1	\\xc410d0129c939db09d6d60bc3841bcb3497cf4a0238781f0dc40882f28fc66bc3163fceb0456ff46faa93b645626734db60ef9778ccfff3d3810ca04decfe30e
1	\\xf73270ee69dc79ac4545f814324f16fdc75efb7ab2f95d62b48ad0f935597d71c22f19f90e08dba6ba8401dd88e731031e19d547c1dab479caff6272cad60252
1	\\x3e347121aed6ffbdbdd96b66c626c8fee1f8c4ee803adf5b36e83a3302bff25c0f21e747079c955c68959873e148ead938fe12eb9b848543aff3be33c9cee4bc
1	\\x89971a483a94979233a7b0b28a9090cc04111851ad9c79e2d8c1703f36d1f27cc7ffe9b358b61620fc8538e7711b94bc74b3969ab892b49cbc75f4015468b883
1	\\x3ba72dfcfdf34412c821c62ca8560dea81fbbf3514e4ed68adb9be711d05336242610eec481825ee658197a725a97fd1f73f1c87fc945ea1e717275825a262d0
1	\\x0bb3ef14a0b9094163260a6a7b7b692eaeb0267b68f478a2ec7fffb201bf9faceadabb4b307ee4c2f86ca3f17b357a49c0be7ed726a1b65dc78d48b0604d1d69
1	\\x05709c52efd0e0a2c46d6beaf88260d46b14a01d51d0c82ab8233bdae8a9beee37cec8864bc725844a0a1f724ea04feede0c5a9164cd580a84592b6e7b08fc37
1	\\x2f28f5d8f825639cbbb8bbb5ace7c79680c9661ccdfe23c87c42d1e2a49f2853bf171fe1525136897449a38cf1a769d210db901cb1856fb2eb92461bdc1cd54b
1	\\x917010a9f7c296532010c58611587f9d3430ec92d3bd5b52b10cb27329ebcb49d6ae27e637105f198b9d04aed92d825a62d0ba5faf9d202cb93492c4809b85d2
1	\\x3c25398a9c03f00971223ff5d30220534fe667cb8bc990a751d032b2014e18f38b6f1ef31333cb5a87cf14cf7559f67d1b80a451b8e74497e41f576d79ac3db1
1	\\xba04fe88893f32f3bc1fca56515c687fe8cb7fb9ba1f1fc9d96f9cd2d92678cbfc9ebe803001008ad6e4c08f5e92fe37c68377886f875178a8ff9e38cec5f571
1	\\xf10401ff8179091356d38d67f9cb48bb4b298bbce54bff3cf4091ba3078a6a803fb8f96dc9f6090e5c5643d6c524f7176bc27d858b7e5e8fb242b37c8710e403
1	\\x3ab0d3c6b407a508cabc174745218636e53f9e6a1ff113904720731e84df1babefe223132405f9dcd7f0a1ead596e82a18db1dc87ec8ef878ad6850d6400c6c4
1	\\x69ab8b63d0a8ce9847d9b77f47213ba92452f312e03407b3a37117a8999eb7c76ca377bfe299ff02a86fc17ed2157f356ef817778eb44ef4c67a201a13f3c253
1	\\x55d26efea040ee5b18ffbe371e95af151ff43594bd60bb075a0b36fd97356b802ae1811e1e48b7ed793dad2d6ce79c136c5b00e0557db56f331798746b3b21ec
1	\\xfe87604530984772cb3e5d5cb3e335f67dae97879e87a8d1a60def019b8e2a370035411bd1207f8cf94216d25a2ac597f70caaac4551c351874c54b1de0f8896
1	\\xdf62518c75d50c353dbe27430a9db5c441f3bd6e18334b855a932876d768575f48d970249c0fd46a9fed1b12c48a7035b3684e2414b70162b847fca29a57798c
1	\\x580e0da65e703462b89f9d756a60ba18e4ff73b71451fdb51f86ef8ae3accca717410078a67013947e8874be3856931a48228c196d4c546d722ac91df77228c7
1	\\xb30c6d01ddcc07f8259420a3f58ae1dcce570b4993b8eb7ca8b3ad5a7e6ed660a9c3a5a04f7394880c40ab109c0afa3dedaf30b55e3ff351dd19ced12b28baf8
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x43dd8f09cb355034d87c04b4575e347416f66e191a77ca6f0bb50399164479d2ce1e47104437d470f3b6cbae10b032e5feecb5cc5ddfbcc639d61875b4e660d8	291	\\x0000000100000001b4abf606ec702b1e78b36b31e679c2662b5cf369edc06e821f51887f33b0c4a02cbcc383364c40fba9c4baba2b0fd033006984008099d577da249453de142bfdfefe581a38c919e6a26948e436f1522d29b4ad6ca1075a128e25174f42e7ea2806b1ece0781f694f25686205adad281a4b2009d4946b42317991b26928716a99	1	\\x4a0350d04fcbfa1fb752b5a4c61609622726f6bc46a05cb11700bb1cbba5700a16d18e36db192f78896380934d3048e2e9b6939c441d180139a6119171864908	1660496931000000	5	1000000
2	\\xa0c12c5296879640ccfaf5f8f5b254a473bd7459caabd849a9fc661c8d9759bf6dd8b61ed53d8882beb19b73f00ca970c38852de3b01198d49348a14172cffc7	344	\\x000000010000000106556ddd81e734f281ce60f7ac96b256af43eecff11189e79c75a40fff7e952c481049be855d9a5f77dc4152d10af3c20746a7fd35686060723ecb7178b48b042dce3970652ddbc8d7fc05ef7f8c3580873cd7f474dcc71ab39acf277dfd33ce0d3d0d8e1865c8bc4ced1f8ec60092ad605bfd8b37ad06abb6eea8355c8c6296	1	\\xaaa2cccc3e22c59dd0c5091d84569316469b0f8ca60ee622bb4bd33f04f55427735d601a8f21a27f5c64a2765dc52de7e192b41ab9216f2d65f317367d2c9905	1660496931000000	2	3000000
3	\\x54b13243aa05c3abc9d03c38ddbfa7a9273ce992185ef95cd279be50ef5590f637e5d195a4730ea15fb1409025bcc534d6df287127b67476338d3087ceb0e9a7	334	\\x00000001000000015d79b6baaa7c48cdd341c91bcf9cd9c4666028da687887f18ad4cca8762703aa11b69b6db5dd280080b9db644cfccc9ac2c8ab9d7efc9a1fa2d14dd2a0d88997a9f311c97300d5c73d367ac3541f27e532d4408459cfabc0a62933caa8b3df49172d6038317c07f00549aa383601dbab952de4847869c3d1a0f1f3ac81289c8d	1	\\xc5d8c9f10c8ceb72aabc17af27555c8e28cfe49917ce80280ded581b981935b6f3dc15bddd9d983f4bd8eb22061c3e1137e7f91b587e24b7f980586572cdcf0b	1660496931000000	0	11000000
4	\\x1e3e22933c1e360eb037cd8e4ecac4b84c7e5565720784dc38b4a859f00f886c8430e532176de43ccd892653ed91733a3b46dd13617f091f14d55a904ee0d6aa	334	\\x000000010000000117ddb404e1cc18f07257ea027b167c5fefc0134451b7acf5a8c322cdf9e074cb19e9e2a80a1c54c440a4e191d84ab9ad8869c8a8bb8902467e5420e88790d2dcd297f9d21c8a50b5ca8995e87d74b1f699bf681d7f5de684aa763a2c4f079bd333762e5b64605b9593c26f7abeded3b12dbad0ac249eee5bd43c9a30b8374d2c	1	\\x3e72b8eb0865343aac54de7257023152dcad67a7b845df8baac0f869dec273029ebc9d4c9c33f0c1c3f1baf5b2865e9e11717de8e3b21fca102f7369bf39810f	1660496931000000	0	11000000
5	\\xebdf00db88b22864104dada165b0244e97f3650d1f64266aa6dae25f9b4057492ba4641dbb66146b87d63d0573e97513601bc63cda5f1691ec03bdae61eed130	334	\\x00000001000000018bb74b4300cfb733d41acf59dd8edad456fc244f62eb20b00ef1f8176666bcea708f928c96ce104bf4da70adba65836c350ce094a9688ea4f73ba25f8fffa540f27158043ca6f35684bea1e9d386b9e729cd0f1fd1472396cd6ea964f19e63c2c33f7fefab72ebd3076845f3eaf188c9f19bbe5c52960580ae4cbd8c29c748b2	1	\\x2198acc597ff871c8501493b921e88dd0d9b56488f3d36035bae285c8fea21b972104a48b5b26c53baab7507f724d21580dfdc3762dbaed97b4799d457639b09	1660496931000000	0	11000000
6	\\x2332e7947adda29ed89734a5049e30c64aaa511042f3faa06f75915fd7499e02bb5e8afa26dbf198a393845af5e1f28ca6096a85cc26c4a68e5c9b4ff46af521	334	\\x0000000100000001412355c8f50e0080ceebe45ca79cdd7493c725846f01838ddc5ea4dd74706dae08d43a09f1513821f40d1d05992899aa98d6be10c58357a6996f43ce59f2bfb63c79cbb04076faa46dac9c35d4dde261a0d4fe451650845dd85aa5f22ba3a85b7ed3b1867371db6275c1c74bd813e73f4569ed3cbe09f3ffa51b9fed991c5eda	1	\\x76d4d8baf750444ec7850c0dc07e5d21014c613bb9c0c29ec44d86b65d4671ad9a2455fa637d31e93d9d80df246f7eda866fa02106f7acaa6f0eac55f4706f0e	1660496931000000	0	11000000
7	\\x79f15e09dbc95a1d44adaaaea7deed3ba4fc256f251520ec7ad4aee60a2c1be50bad602c102ed35dd7a9b993ff7369e8626c5ec7eb952a9fc0b64c1649072e63	334	\\x000000010000000115d24d6da9b8d6297047a69af930ec848a69e856c7bcd68a5e3b8c878dedc65a8a72dcecfe2c41a91301b7f3bf959cfce1fd56eb85102b1f907022012c3b9c906736163228a41f8eb71f2924d507a3a78ea7175036d33e7b2fab447b45fabaadf22bb1272b5b702d4e2d5f3e648618f672faf53523cee084eb672a23a9fe27e2	1	\\xf3d47a39f6a84e58517aed7e994f5dba2cd8593c4eec6fd7264a85c6b164f17fad447b7e8855484f054516fa91dbd19bde69bda2f4bbc9d665ac19a9121dac09	1660496931000000	0	11000000
8	\\x566bb4619dd67927faa19de302610a891eb8bf5a4b1fcc8a0333fb173aa355dc52b3ad840da8c8868352007e8d21e6b84d0a97582c965fd1fdc338979e222e0e	334	\\x00000001000000018f4e970abf84ef32245e96da820fb2f41d45e2e4d76863ed3e85753f0dbd80df9526962afcb33296b5315065b5c5bf514eb57c18b044fdfe46db487203f17e6dda92ae87ca39c2823ec47c4068d310bdb761e7002b120d14dc75f0e888ba5152eaa99ee537a823cecc18649be71b91c14a8f2a9a03b9496fdb6c78f9125ca9ca	1	\\x0ec749abdb375c61f750fd33e6a0a940a6efd2ec7c4e24fea37e9b930096e47d5acc42f24a9f2a24b3444269a319da40a03b3656aeceb00904dde222dccff201	1660496931000000	0	11000000
9	\\x8d1a0332eada043c5b0d0ace51ca2db127c2b770ea9765f2dce4c2bd892e0b37dd8b600f84edb0152e8d1a9f4fde89533ce6c70b6ae155285b3bf10a4a7ecc40	334	\\x00000001000000018faf6dbd10ad698a6e168fb8c80fa15cf870b54f4f322d6053c4484e5e60a72e8f90c8a9d44d1a64fb088c1a30642ee69983b6adb8cf91bf13a3179fd20ca1d0c2741758de9ce4456883f2005d2467b63d20c9dcbe3c4b1355ee9cc2282d478f528a5dc02643d9faa9b2bc3eaab960a82317f4d48dfaa0bc2e923ca236ef0d59	1	\\x65f5ca6286356507bde52298f58777762e724e93b538b716357c2422415ad8c8dbfbf3219ea68e00897d6d92af6aa161a63f25d26039943e1c8580a7040c3d0c	1660496931000000	0	11000000
10	\\xc410d0129c939db09d6d60bc3841bcb3497cf4a0238781f0dc40882f28fc66bc3163fceb0456ff46faa93b645626734db60ef9778ccfff3d3810ca04decfe30e	334	\\x000000010000000103528a9a42e73d5a4df993487e821af60bae8bfa4bf70d860579e92bedc0e3c29495b312e5804092c4cdbcdbab39c82d2f1c247819edbcaeed0004d297282bfe708a65a601d8b9ba0968aa59ae801eaa9ffa0976381da86957c39d0eced9321db74ef14d072523aefa0f5d4243a7f3bb8095758da5da7c66aa9bcdc652577d8f	1	\\x01e432d65316080fbd98310057f8a3b591a1d214db37047639ecd72d1e33f98acc1349a6277d8a36b43458c7641b9d7a986f07cc04d0de67251b3ceaa0371d05	1660496931000000	0	11000000
11	\\xf73270ee69dc79ac4545f814324f16fdc75efb7ab2f95d62b48ad0f935597d71c22f19f90e08dba6ba8401dd88e731031e19d547c1dab479caff6272cad60252	208	\\x0000000100000001a4ea9935b113d64da785098a5e401cee7bd9e1eb16c79b36441ae83f064c40a7e1a97931c5e1d6624265b43047003ab8525432df853b91f097bb3a62bd01733b16107cb1c6a545f63a50c061c0bed1d49aac391fd3806a0dd35640bcd4c035b496bb679ed39de8b659c73d8185007daa28e7adf73ed269633c502fc1591c0c85	1	\\x0ef9706e7ac8cc1ff9113ae3ff71ef0ac8ebc1bf75dc923216ff52e2ddd265e0792c1cb9a6aecc1ae7ec42c34a071efd684694c83f44a965d0284d99c7d0d403	1660496931000000	0	2000000
12	\\x3e347121aed6ffbdbdd96b66c626c8fee1f8c4ee803adf5b36e83a3302bff25c0f21e747079c955c68959873e148ead938fe12eb9b848543aff3be33c9cee4bc	208	\\x00000001000000012c3d3219ce49362e788c3ac6f8452d3bfff54526af318d6d210ebf47c5e3acb402e1b87f99a5d2d638a141c14dc15c1a755172ae4ecaeee5660ea5598998a63ce38a6287333e38502f48083cd6df4ea22072080cabb35fe174d9b427071a80fb466ba96040ec2a0816d24a33a88eb87495ed5c0aaa7c3fd27c3d525e894e5ae6	1	\\xf775d20d52ff22a5da98fc4528e98f67f8e97c748442e86b09abca0f57436403d02c49048c9c486a9e0203b9b616b2c9461fa3799bdda1cc558fabdcabfbf002	1660496931000000	0	2000000
13	\\x89971a483a94979233a7b0b28a9090cc04111851ad9c79e2d8c1703f36d1f27cc7ffe9b358b61620fc8538e7711b94bc74b3969ab892b49cbc75f4015468b883	208	\\x0000000100000001a203323c7e844a7ddd9cb12ae3a5afaee06845e546a7ded877bde3ef126e6ea56d8f96ee4702fe4e30bc9ba311e23bfefc59c88444a468e3e10184cd2abf8d23f09546ede71f94c96431789bbf0f9c42adad4794f99925cd61452cb50f4f7f2970ed013f5d59cd61f89d3d3d7abbaf85d5bfa5685b61453e8ea2a76500aa96bf	1	\\x7bd3028a1c1565e2f105a8c801323388295eb3fa6367ea95364263c68287ad76571ccb16ace4b368f702ada62674d9be9dee642acc451ffc441981a5f0d32f0f	1660496931000000	0	2000000
14	\\x3ba72dfcfdf34412c821c62ca8560dea81fbbf3514e4ed68adb9be711d05336242610eec481825ee658197a725a97fd1f73f1c87fc945ea1e717275825a262d0	208	\\x0000000100000001163d9ecdb780e41817fd2d2156efff205413ccb213719c6b1994ba98bd5645ca04e6b8188578c38a53b65e5c3ff90ce81cbdb205e3f2ae4e8acf7d073b24a05c517fb96ab43b6cfede4c7e57732fc91d628b795c28bddd67f851487d1a9cbc9e0147d36c0ce81005ee84ee74732fc11a90ca2c36ca3353d0436e8c1cbf5fff27	1	\\xa1d84103bdee7ccf9b8f4d14c0f5169ac30f20dfb4d087862e46c378239933186ffa8dcce41f1e777f9c80cae11b0b62dd4cf7fa3951cc3ebcfb97b4f3bced09	1660496931000000	0	2000000
15	\\x0bb3ef14a0b9094163260a6a7b7b692eaeb0267b68f478a2ec7fffb201bf9faceadabb4b307ee4c2f86ca3f17b357a49c0be7ed726a1b65dc78d48b0604d1d69	315	\\x000000010000000176e2c635c8ce9d9219ee35d659df73b31cf9d587a052b89fd021f14921231d1d709f54b35e813d1c398343ccab4caace914f00689770819705fbecdae1224abea22aee7ce4de31dafc8fb9e8e17e83ace5eb8cf248774d2a714b5e39c09eb59e23b337a098f7cbf363733dbf9e79fafd6b14275fa5a6255e9b1f2af77baccdd2	1	\\x2b410673fc8cb003e3748b2b00dc3528fa142d59bf4c0ca004d5fba3416ddf5da0e260d1c51bf4c5cb41db784a0f244076f3529784ea77feeb0d83d83d3d1a0b	1660496942000000	1	2000000
16	\\x05709c52efd0e0a2c46d6beaf88260d46b14a01d51d0c82ab8233bdae8a9beee37cec8864bc725844a0a1f724ea04feede0c5a9164cd580a84592b6e7b08fc37	334	\\x000000010000000172e2f37a1535ed94d5655c31ab34bdc86853957f1d615ba17c03557aa55a4c87968a8843f3aa69518fa6d74dbcd11ace89d802e9dae6cc11d218e14565898ab38664ed0aa38d01b973536d3aafb2cd27197839eb3bb1d842ab80542ddf67d04dd444038355f0356f9ade2fef88e46af2aa5aaa0ca0c54d4f30d404620c8dfc9f	1	\\xc916c2423433b9632b5537868e128bc62d44828a62b290e3e64746ecbc54a1d16bb3e3448a4e1dfdfd08411b0f8540732921afc92cf640db829c0bba21b2f302	1660496942000000	0	11000000
17	\\x2f28f5d8f825639cbbb8bbb5ace7c79680c9661ccdfe23c87c42d1e2a49f2853bf171fe1525136897449a38cf1a769d210db901cb1856fb2eb92461bdc1cd54b	334	\\x00000001000000013055a37392fbd1700186e4961f27d01bf72c1685459cc745fb6829edb614e4e14ed4632e2bd9fb314d5386c07abfd76d09ab737a251eac11067a129ed566084c8605ab264f963699d98c67d8908be9ca0901c645547e35d28d58f59409d4c0f84e17920ca05c200e334f9105ead20b2bce03ab7238e4559aa765da4d1b5bfec1	1	\\x557278f545fb6da6fdb3561d853bbd8adb699dcf121bbd6c6a54eb901cc451ba4b6c738e52b2e6711743d1034808997658095a4cd68ac9c4e8c5e4f001ce0104	1660496942000000	0	11000000
18	\\x917010a9f7c296532010c58611587f9d3430ec92d3bd5b52b10cb27329ebcb49d6ae27e637105f198b9d04aed92d825a62d0ba5faf9d202cb93492c4809b85d2	334	\\x00000001000000017799a4235fdf5f9eeb142bdebfb2fc6de1f5dc35c0c900490b0b2ae307fdb93fcceef253f787cdf1b72b9742fbb1742c0bb2c92c2bb36fd49ff3847f4cfdb7333b2a1b746a384377e5a1723eeeaaa644a868abcf65400e09dfabe8837caaa970c792713d09250d20275b6975ec97755d3cdd23ca261e129258e33a454135144d	1	\\x34ee906fc661d1a1485121aa20177dcaff27bd1155b28d54ba1f257918d6d8ccde349a8c35d24634292058a1fd9a3d754b17f6f22db3b927c8d613a106c7f409	1660496942000000	0	11000000
19	\\x3c25398a9c03f00971223ff5d30220534fe667cb8bc990a751d032b2014e18f38b6f1ef31333cb5a87cf14cf7559f67d1b80a451b8e74497e41f576d79ac3db1	334	\\x000000010000000110449ba7d638760fca30ef93a5753b99a3b3c6709d24180fad8ce89160687ba762969f558ab457526dc5a606c2f1d875e824ae1ba10a7955d4350275ab1887de14badc92a4384414bfd7afac1138929fbaa37ea4856fb95fefc1ced3afd659e52ab42bb4d273839b1febb13cf6f86b928718a173009e04cad80dad177fc3e8eb	1	\\xd0e39292e06bd28ea6da1668d265307a960c70f484ce62a5382098147cdc31e3ee92d981c87936bee81b2d49bffd0c56f094f6fd0c804b9cb103132cc0488f07	1660496942000000	0	11000000
20	\\xba04fe88893f32f3bc1fca56515c687fe8cb7fb9ba1f1fc9d96f9cd2d92678cbfc9ebe803001008ad6e4c08f5e92fe37c68377886f875178a8ff9e38cec5f571	334	\\x000000010000000189a256cdd7f533f7a91ea19bfd74b44e48ea5449540b764bb12f930543150011a9f3d5f828f91f134818421ad6890ae4b738a1cc179f15d6b492abef26826c56cb11dcfa8d3c3b20bae419095f4fdf29aeb8f74cb9c07b163907a7e9c7f5c2aed7b5353b7af3e72a918c1258244ca5b4b4bfa5f9b78e43d054a5f19b84ead8f9	1	\\x0069188e8b981a91032ff99d4d77d3c557215a780f89804605e5b03ba65d619a52d4788bb0ea735a22d71107cb942167380b01551eaee3ff89356ff550a2ef06	1660496942000000	0	11000000
21	\\xf10401ff8179091356d38d67f9cb48bb4b298bbce54bff3cf4091ba3078a6a803fb8f96dc9f6090e5c5643d6c524f7176bc27d858b7e5e8fb242b37c8710e403	334	\\x000000010000000106105576c8f7080ef2e94f4a738c2287436751adeb3f883c1bdd74417c60b7e9f6addc717bf2abf9de2eae3059e3f1b88f5d6526600dedbfcbacf66bacdf112728b74302810f047cfe390911ca2abfa0623008036751c62a13ddcd5d9e20cb0ed697a6b7649bc60016acfaad9f4a1233fef2b36f7419247ea1f71cfd53fa1cfe	1	\\x56ecfae303d2b64291cec1213b2a18ab5072ba47aba98512cf5ffc9091548fceef8ea6352d2ffee3e2ac86a4af006be43cba121f6c9bea54c7a8a6aa0b181b0d	1660496942000000	0	11000000
22	\\x3ab0d3c6b407a508cabc174745218636e53f9e6a1ff113904720731e84df1babefe223132405f9dcd7f0a1ead596e82a18db1dc87ec8ef878ad6850d6400c6c4	334	\\x00000001000000016fd9c77b75497caa30e39b8218a5475c1cc4dfcb8ff0dbf4731f76a73063347f37b3e1714fb94ad5bac0cd64d6fdd150139f146f4848b6e61125586ee0a6a31bac434dd7ca4071ef81a008242b419b27ef52ddf0be8af7a3bf475a5eb39ccfaadd396cd1a67250f95f21dd75de37f22d309a08475f5fd1f2582f5f2d19167fb8	1	\\xf9628b7519ae611860508d97d3594996fc87575e159d8d60470ca0be6252763b4d9c40c0d72ad8c3a7f1f358e5c9f980b13dc6b868d0715c3cc5b378bfb0d207	1660496942000000	0	11000000
23	\\x69ab8b63d0a8ce9847d9b77f47213ba92452f312e03407b3a37117a8999eb7c76ca377bfe299ff02a86fc17ed2157f356ef817778eb44ef4c67a201a13f3c253	334	\\x0000000100000001185dc9498f810812095caf067d09e00f2c19f95d81aeecdd1afd8984d8222013c1a944e5f09e0f984cd06996da199902197d3c9f6f51aaff211723b9241e197fae4a0dd8080ba6f41985580c07f3def912447577893ae7e2fae37e6b71c65aa28761215376ea87f8691207f723a0dc7463346e2fecf74d970bc8c77bafedebd3	1	\\x51152828156602e0e4c51db9c18952d80568ec67a3986f6bb75f2800e2affc54b9d2d740c33ff585b39b34d7290ab112434a945ddfdbb51cca0f53c9f456cb0a	1660496943000000	0	11000000
24	\\x55d26efea040ee5b18ffbe371e95af151ff43594bd60bb075a0b36fd97356b802ae1811e1e48b7ed793dad2d6ce79c136c5b00e0557db56f331798746b3b21ec	208	\\x00000001000000011a3be22c8b515dabd0f975dc869e3a33ca3c2e96b16651f59b500af79787136f380d1101ef86147aa3e3562f3fe26edb4e6cc9edaa21af2de49ca538405b3e0cf4840e33c12d1c7243576702e409d8bc3f45baceab9ca45b659103ba0164ebdf1146c113c9b15993750705a519993171be7134b930397a27f654cbc2e45095f3	1	\\xdada592201bac8227a0fdb30e7ecafbfda624c266747f07c0c0325343954b0855471f9ae5323ba4d07d1ce9080d2d1731e3b7e43bd8d0d33bf5f1615292f8500	1660496943000000	0	2000000
25	\\xfe87604530984772cb3e5d5cb3e335f67dae97879e87a8d1a60def019b8e2a370035411bd1207f8cf94216d25a2ac597f70caaac4551c351874c54b1de0f8896	208	\\x000000010000000119cc3b2fade978bb4f77d02ae743dd4f22d63d19d3251a7969be8061c7aa5f3abd01a74a408ba64a86ebc4b837711798563f2332fd0ec006058bc50b0077d10936d44e1754d835bb45922ea8d200661bb1e2a9e11e6e777f0a6275db4cf904816addd33143f5c08690e62c61a5e8a1eb460c7ac83eab38daa900893d43a5c83d	1	\\x1c8529f8cdbaaa151a3bfe45347fcb41946b2575f807f7f32f91881ba0ce5b63146dd76351480b2680958f566addd25b7ed5d1fb1bde38dffd5694c73562610e	1660496943000000	0	2000000
26	\\xdf62518c75d50c353dbe27430a9db5c441f3bd6e18334b855a932876d768575f48d970249c0fd46a9fed1b12c48a7035b3684e2414b70162b847fca29a57798c	208	\\x000000010000000176ba5cc7e1d670ef33336f281d7bd5ae8a8c1090a502b69904b21299387c34e534e01279f1a02efffd043a65e90e9534c63c81fd23859a6e9563fa5abaf2bf5152400041b691b3e99cd8532c7614f5b25181e51a64a2dcf59f69cea227804d7818ac76038192697b54b25603aa7380bb477114ce6dc6a8b6b4f0109a1b88d27a	1	\\x83c0bc3ea5449d1b93ba4aec1ef3717ac429ac143dd00dfd121ad0298b12b3fc151e5e784a2e0d687623926e79b2b8efe0a476d6df65372bbf7a27c7e6aeb709	1660496943000000	0	2000000
27	\\x580e0da65e703462b89f9d756a60ba18e4ff73b71451fdb51f86ef8ae3accca717410078a67013947e8874be3856931a48228c196d4c546d722ac91df77228c7	208	\\x00000001000000015dc19d98141d25cc6bce260970058ffd5ae921fb108bc25494ab0e95b4642666258762837ddf77540bacec19cc03753da128c6e1489f22ab9e77f3cb2b1120f1b252f3e155206c03f4c872ca753526080762d5ef38ffe585241489102c890fca9fe8db02705216693e7be2a34ac2f199f11efd5f9b89d196e24f3b26a3b62c2d	1	\\xd2225eb4ed6e9a7ca4e34c65926b73a91e5b0538fd54334a1fa524f0d204048b88624838613da615bd7034663378ffea87d29b968b4e09ec9ecbba5fad942305	1660496943000000	0	2000000
28	\\xb30c6d01ddcc07f8259420a3f58ae1dcce570b4993b8eb7ca8b3ad5a7e6ed660a9c3a5a04f7394880c40ab109c0afa3dedaf30b55e3ff351dd19ced12b28baf8	208	\\x0000000100000001448ad041d8d6b334b18316cf1882c0f96f7675237b52459871c02adb430c3e1693a2e3e8ebe48c39dbbbde6f125980362866657dccd50744c3df1ad4c5bed26db139742078519ab24ae5c4673bcbe748db698dab315ed684d25a2babce0003095a2c3750038e60d8f111641150f643e1f3835ca577187a06795744cfc9905f34	1	\\xd09a032291c097dcfa11e821c642cb475768c10528bcd9f78bf8a88edaf3daca91e9af091235fec82854058bb58fe20c59810693445c7ee766ccd9fd6bd5b305	1660496943000000	0	2000000
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
payto://iban/SANDBOXX/DE895351?receiver-name=Exchange+Company	\\x92e9922122bdd4008111faae1e3a8fa7c1978bbbf24ef3e503ad0efe2a735dea6054f23b8caa3f11f66af9dfd62353ca540085f866e08edba01dc624d87b8004	t	1660496921000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x2e20b95cccd90dd580e72cb5ca45fa21474658e684c6bc6df8a6024604a9be7447196703ba112db3e7d9a2532524b2365ea61b0d8b9daa733ed847ad95d4b709
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
1	\\x3ea060af2de1c3ea9d3271f93aafe66a3ed5ab7e1c7844ae0c2ab727ccb9d787	payto://iban/SANDBOXX/DE964837?receiver-name=Name+unknown
7	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43
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
1	1	\\x1ca6a1212062637024345e59e61187ed675482c8328b5112c91afa4d332d18908e815a40bb622ca3b1cd7538f100ced0bc307fa89b55eec6ae7dc30e1e27bf12	\\x0fe4af88bf614464920a2b82ed6e1410	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.226-01627DQRMR8NP	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439373834347d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439373834347d2c2270726f6475637473223a5b5d2c22685f77697265223a22334a4b4132383930433948513039314d4253435943344337584e4b4e393050383641354e323450393342583454435344333238385830415438325850344235335037365141453748303337443146314746594d39504e4645525451375647524533524b56593447222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d30313632374451524d52384e50222c2274696d657374616d70223a7b22745f73223a313636303439363934347d2c227061795f646561646c696e65223a7b22745f73223a313636303530303534347d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22564557414534535459514e3937573056474858433453455842463133514237523859525653514d3330354b485446385931565347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22453952443559574d573551533857504638465343414d52375335583142585244573859365654365a4b445a544646525658535630222c226e6f6e6365223a2251574645454b53543245433032564d445130585932573232323344305635544b5a3438585341594d4b5750543533575646374247227d	\\x0bbdb2d8e27013936ac463ba287f0a2e42014a27ee2ec566ce9a289fa71d56c15945822db2f46c07abca8ef246531c42b81c705ce84a29b46482d34c403a5ff3	1660496944000000	1660500544000000	1660497844000000	t	f	taler://fulfillment-success/thank+you		\\xe130b7545ee190ea721635038f8791d2
2	1	2022.226-02ME36MMTHR4T	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439373837367d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439373837367d2c2270726f6475637473223a5b5d2c22685f77697265223a22334a4b4132383930433948513039314d4253435943344337584e4b4e393050383641354e323450393342583454435344333238385830415438325850344235335037365141453748303337443146314746594d39504e4645525451375647524533524b56593447222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d30324d4533364d4d5448523454222c2274696d657374616d70223a7b22745f73223a313636303439363937367d2c227061795f646561646c696e65223a7b22745f73223a313636303530303537367d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22564557414534535459514e3937573056474858433453455842463133514237523859525653514d3330354b485446385931565347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22453952443559574d573551533857504638465343414d52375335583142585244573859365654365a4b445a544646525658535630222c226e6f6e6365223a2233515135483238393042334b415233545738503050374b53315145463156334e5132534b335333413134574e563436464e345247227d	\\x1f577e803515cd596a820220d12ab80b1975adc2c21267032c44190495566a33083293dad7f13f2208b0cd60d9cabe5d4be787897c2f6a1aa38d7299837a97de	1660496976000000	1660500576000000	1660497876000000	t	f	taler://fulfillment-success/thank+you		\\xb7b9accb2ec4761c176d2c1ce08b0836
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
1	1	1660496946000000	\\x592137b950d311b054eaeaf80ca91ade5f9f3cdbefd22f60c8d1996a3fd68d9e	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	1	\\x5a53d49226f76aba31e3c5225d9272607d6dacd03aa9286a227cacf04d94c0a54585823f05fbee39eab71b96b0b47ba12651a2cba7647519aa2d5b2e6b058c01	1
2	2	1661101780000000	\\x02817f806330300e5d357549b6007eb148846a90f2b1e26649481d5fdef8bece	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x8c17ff575df74dc0619c938fabd8955243de9e28fcb7d54abb33783e04aa04e62fa35717412d4ef0887cd6a27d898d2a7504e941d49ae19eb38beaf70c726509	1
3	2	1661101780000000	\\x088afb72460f451eff570191cd1354a9e926d8ba5568c0a957c65558b3f1746e	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x85880abeb84345cdfdb65b70562a6465aa68373c40d3a9ea61037381d6ebf88da6d6a36f93de5c79acbb2994dfa36cc41c418a5f05d72fe8478d74ff15e02b00	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	\\xa0b53f57e6daad7f621de6b8b82a2c77375dbba27131a1f3f6d5a7b382fef1c9	1660496915000000	1667754515000000	1670173715000000	\\x5e6321b758b43110dc4cb4b810bd19971b9e672c13cdb774e061d18bedb231efedd11148d303946c31c2a99fd8b23242c0397fc3b77aabbb1228c17b3306300b
2	\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	\\x4b5dbaaa88cbaff3a59cf44bf0437f3007d9d0d05e00eba821fecff1268dc976	1689526115000000	1696783715000000	1699202915000000	\\xca817c932a8320816afba84c57950dd4173567b4a8606ce49072be749723d07bdb7fb13fb2a57671c2392fb2236a7d4371000ae78538db77301ed843267e7304
3	\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	\\xae530cbb39e679a6d9bbe4e809aacae480136170495f3a5f0f5e77be56587f88	1682268815000000	1689526415000000	1691945615000000	\\xdd154b53a0ed724ece3d1acb2227802813d915fe3361ee5b6bfbd785f7dfec6b946f37659683a0027472da98a949d0d950595396182efa0a200d02aa72f26b01
4	\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	\\x15a354050eba62caa02531d94662c9febc2da29dadaab41e94da21f5ea8a239b	1667754215000000	1675011815000000	1677431015000000	\\x35cce8c55f02a59e5d99a9f1c00d72ea5ff1f96e953fc227bcd49825a83dae40f008e5d823f5159ba70a0f0d49b77d0edd9b295f2c14aa07775092ca659c5c0f
5	\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	\\xb68796a62a8d633351b508479a183e215ddcd070f61d24de454acac750cc75e6	1675011515000000	1682269115000000	1684688315000000	\\x24a50d06a06e038353668785c4ed439f4abb1d3910fedec108f2c81696773f5e50bdcf040b77405bf3e5690e9ab25c1b6c129b29244f5fa9e42661e40fde9609
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xdbb8a7133af5ea93f01b847ac265dd5bc23bacf847b1bcde8301671d3d1e0ef3	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x2e20b95cccd90dd580e72cb5ca45fa21474658e684c6bc6df8a6024604a9be7447196703ba112db3e7d9a2532524b2365ea61b0d8b9daa733ed847ad95d4b709
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x7270d2fb94e16f9472cf43f2c55307c97a15f70de23c6de8df9b7fa7bf1bee76	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x676303d6c45c7a0ae5ada56fb8cb17ecaa63abbb19fc7162e07409770262173c	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660496946000000	f	\N	\N	0	1	http://localhost:8081/
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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 19, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 19, true);


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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 22, true);


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

