--
-- PostgreSQL database dump
--

-- Dumped from database version 10.5 (Debian 10.5-1)
-- Dumped by pg_dump version 10.5 (Debian 10.5-1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
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
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


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


SET default_tablespace = '';

SET default_with_oids = false;

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
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea
);


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.aggregation_tracking_aggregation_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.aggregation_tracking_aggregation_serial_id_seq OWNED BY public.aggregation_tracking.aggregation_serial_id;


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
    id integer NOT NULL,
    amount character varying NOT NULL,
    subject character varying(200) NOT NULL,
    date timestamp with time zone NOT NULL,
    cancelled boolean NOT NULL,
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
    withdraw_done boolean NOT NULL,
    selected_reserve_pub text,
    selected_exchange_account_id integer,
    withdraw_account_id integer NOT NULL
);


--
-- Name: auditor_balance_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_balance_summary (
    master_pub bytea,
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
    recoup_loss_frac integer NOT NULL
);


--
-- Name: auditor_denominations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_denominations (
    denom_pub_hash bytea NOT NULL,
    master_pub bytea,
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
    CONSTRAINT auditor_denominations_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


--
-- Name: auditor_exchange_signkeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchange_signkeys (
    master_pub bytea,
    ep_start bigint NOT NULL,
    ep_expire bigint NOT NULL,
    ep_end bigint NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT auditor_exchange_signkeys_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT auditor_exchange_signkeys_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


--
-- Name: auditor_historic_denomination_revenue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_denomination_revenue (
    master_pub bytea,
    denom_pub_hash bytea NOT NULL,
    revenue_timestamp bigint NOT NULL,
    revenue_balance_val bigint NOT NULL,
    revenue_balance_frac integer NOT NULL,
    loss_balance_val bigint NOT NULL,
    loss_balance_frac integer NOT NULL,
    CONSTRAINT auditor_historic_denomination_revenue_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


--
-- Name: auditor_historic_reserve_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_reserve_summary (
    master_pub bytea,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    reserve_profits_val bigint NOT NULL,
    reserve_profits_frac integer NOT NULL
);


--
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_coin (
    master_pub bytea,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_reserve_balance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_reserve_balance (
    master_pub bytea,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL
);


--
-- Name: auditor_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_reserves (
    reserve_pub bytea NOT NULL,
    master_pub bytea,
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
    master_pub bytea,
    wire_fee_balance_val bigint NOT NULL,
    wire_fee_balance_frac integer NOT NULL
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
    id integer NOT NULL,
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
    first_name character varying(30) NOT NULL,
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
    id integer NOT NULL,
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
    id integer NOT NULL,
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
-- Name: denomination_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denomination_revocations (
    denom_revocations_serial_id bigint NOT NULL,
    denom_pub_hash bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT denomination_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.denomination_revocations_denom_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.denomination_revocations_denom_revocations_serial_id_seq OWNED BY public.denomination_revocations.denom_revocations_serial_id;


--
-- Name: denominations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denominations (
    denom_pub_hash bytea NOT NULL,
    denom_pub bytea NOT NULL,
    master_pub bytea NOT NULL,
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
    CONSTRAINT denominations_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT denominations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_confirmations (
    master_pub bytea,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_wire bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    refund_deadline bigint NOT NULL,
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
    CONSTRAINT deposit_confirmations_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT deposit_confirmations_master_sig_check CHECK ((length(master_sig) = 64)),
    CONSTRAINT deposit_confirmations_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


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
    coin_pub bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_wire bytea NOT NULL,
    coin_sig bytea NOT NULL,
    wire text NOT NULL,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposits_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposits_deposit_serial_id_seq OWNED BY public.deposits.deposit_serial_id;


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
    id integer NOT NULL,
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
-- Name: exchange_wire_fees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_wire_fees (
    exchange_pub bytea NOT NULL,
    h_wire_method bytea NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT exchange_wire_fees_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT exchange_wire_fees_exchange_sig_check CHECK ((length(exchange_sig) = 64)),
    CONSTRAINT exchange_wire_fees_h_wire_method_check CHECK ((length(h_wire_method) = 64))
);


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    coin_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_contract_terms (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    row_id bigint NOT NULL,
    paid boolean DEFAULT false NOT NULL,
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT merchant_contract_terms_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_contract_terms_row_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_contract_terms_row_id_seq OWNED BY public.merchant_contract_terms.row_id;


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposits (
    h_contract_terms bytea NOT NULL,
    merchant_pub bytea NOT NULL,
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
    signkey_pub bytea NOT NULL,
    exchange_proof bytea NOT NULL,
    CONSTRAINT merchant_deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT merchant_deposits_signkey_pub_check CHECK ((length(signkey_pub) = 32))
);


--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_orders (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_orders_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_proofs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_proofs (
    exchange_url character varying NOT NULL,
    wtid bytea NOT NULL,
    execution_time bigint NOT NULL,
    signkey_pub bytea NOT NULL,
    proof bytea NOT NULL,
    CONSTRAINT merchant_proofs_signkey_pub_check CHECK ((length(signkey_pub) = 32)),
    CONSTRAINT merchant_proofs_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refunds (
    rtransaction_id bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    reason character varying NOT NULL,
    refund_amount_val bigint NOT NULL,
    refund_amount_frac integer NOT NULL,
    refund_fee_val bigint NOT NULL,
    refund_fee_frac integer NOT NULL,
    CONSTRAINT merchant_refunds_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_refunds_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_refunds_rtransaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_refunds_rtransaction_id_seq OWNED BY public.merchant_refunds.rtransaction_id;


--
-- Name: merchant_session_info; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_session_info (
    session_id character varying NOT NULL,
    fulfillment_url character varying NOT NULL,
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_session_info_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickups (
    tip_id bytea NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: merchant_tip_reserve_credits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserve_credits (
    reserve_priv bytea NOT NULL,
    credit_uuid bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserve_credits_credit_uuid_check CHECK ((length(credit_uuid) = 64)),
    CONSTRAINT merchant_tip_reserve_credits_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserves (
    reserve_priv bytea NOT NULL,
    expiration bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserves_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tips (
    reserve_priv bytea NOT NULL,
    tip_id bytea NOT NULL,
    exchange_url character varying NOT NULL,
    justification character varying NOT NULL,
    extra bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    left_val bigint NOT NULL,
    left_frac integer NOT NULL,
    CONSTRAINT merchant_tips_reserve_priv_check CHECK ((length(reserve_priv) = 32)),
    CONSTRAINT merchant_tips_tip_id_check CHECK ((length(tip_id) = 64))
);


--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfers (
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    wtid bytea NOT NULL,
    CONSTRAINT merchant_transfers_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_transfers_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    type text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prewire_prewire_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prewire_prewire_uuid_seq OWNED BY public.prewire.prewire_uuid;


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
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recoup_recoup_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recoup_recoup_uuid_seq OWNED BY public.recoup.recoup_uuid;


--
-- Name: recoup_refresh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_refresh (
    recoup_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recoup_refresh_recoup_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recoup_refresh_recoup_refresh_uuid_seq OWNED BY public.recoup_refresh.recoup_refresh_uuid;


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
);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refresh_commitments_melt_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refresh_commitments_melt_serial_id_seq OWNED BY public.refresh_commitments.melt_serial_id;


--
-- Name: refresh_revealed_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_revealed_coins (
    rc bytea NOT NULL,
    newcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys (
    rc bytea NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds (
    refund_serial_id bigint NOT NULL,
    coin_pub bytea NOT NULL,
    merchant_pub bytea NOT NULL,
    merchant_sig bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT refunds_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refunds_refund_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refunds_refund_serial_id_seq OWNED BY public.refunds.refund_serial_id;


--
-- Name: reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves (
    reserve_pub bytea NOT NULL,
    account_details text NOT NULL,
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    expiration_date bigint NOT NULL,
    gc_date bigint NOT NULL,
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


--
-- Name: reserves_close; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_close (
    close_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    receiver_account text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    CONSTRAINT reserves_close_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserves_close_close_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserves_close_close_uuid_seq OWNED BY public.reserves_close.close_uuid;


--
-- Name: reserves_in; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_in (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    sender_account_details text NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserves_in_reserve_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserves_in_reserve_in_serial_id_seq OWNED BY public.reserves_in.reserve_in_serial_id;


--
-- Name: reserves_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out (
    reserve_out_serial_id bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT reserves_out_h_blind_ev_check CHECK ((length(h_blind_ev) = 64)),
    CONSTRAINT reserves_out_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserves_out_reserve_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserves_out_reserve_out_serial_id_seq OWNED BY public.reserves_out.reserve_out_serial_id;


--
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_account_progress (
    master_pub bytea,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bigint,
    wire_out_off bigint
);


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea,
    last_timestamp bigint NOT NULL,
    last_reserve_close_uuid bigint NOT NULL
);


--
-- Name: wire_fee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_fee (
    wire_method character varying NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT wire_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: wire_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_out (
    wireout_uuid bigint NOT NULL,
    execution_date bigint NOT NULL,
    wtid_raw bytea NOT NULL,
    wire_target text NOT NULL,
    exchange_account_section text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT wire_out_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wire_out_wireout_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wire_out_wireout_uuid_seq OWNED BY public.wire_out.wireout_uuid;


--
-- Name: aggregation_tracking aggregation_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking ALTER COLUMN aggregation_serial_id SET DEFAULT nextval('public.aggregation_tracking_aggregation_serial_id_seq'::regclass);


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
-- Name: denomination_revocations denom_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations ALTER COLUMN denom_revocations_serial_id SET DEFAULT nextval('public.denomination_revocations_denom_revocations_serial_id_seq'::regclass);


--
-- Name: deposit_confirmations serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations ALTER COLUMN serial_id SET DEFAULT nextval('public.deposit_confirmations_serial_id_seq'::regclass);


--
-- Name: deposits deposit_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits ALTER COLUMN deposit_serial_id SET DEFAULT nextval('public.deposits_deposit_serial_id_seq'::regclass);


--
-- Name: django_content_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type ALTER COLUMN id SET DEFAULT nextval('public.django_content_type_id_seq'::regclass);


--
-- Name: django_migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_migrations ALTER COLUMN id SET DEFAULT nextval('public.django_migrations_id_seq'::regclass);


--
-- Name: merchant_contract_terms row_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms ALTER COLUMN row_id SET DEFAULT nextval('public.merchant_contract_terms_row_id_seq'::regclass);


--
-- Name: merchant_refunds rtransaction_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds ALTER COLUMN rtransaction_id SET DEFAULT nextval('public.merchant_refunds_rtransaction_id_seq'::regclass);


--
-- Name: prewire prewire_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire ALTER COLUMN prewire_uuid SET DEFAULT nextval('public.prewire_prewire_uuid_seq'::regclass);


--
-- Name: recoup recoup_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup ALTER COLUMN recoup_uuid SET DEFAULT nextval('public.recoup_recoup_uuid_seq'::regclass);


--
-- Name: recoup_refresh recoup_refresh_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh ALTER COLUMN recoup_refresh_uuid SET DEFAULT nextval('public.recoup_refresh_recoup_refresh_uuid_seq'::regclass);


--
-- Name: refresh_commitments melt_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments ALTER COLUMN melt_serial_id SET DEFAULT nextval('public.refresh_commitments_melt_serial_id_seq'::regclass);


--
-- Name: refunds refund_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds ALTER COLUMN refund_serial_id SET DEFAULT nextval('public.refunds_refund_serial_id_seq'::regclass);


--
-- Name: reserves_close close_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close ALTER COLUMN close_uuid SET DEFAULT nextval('public.reserves_close_close_uuid_seq'::regclass);


--
-- Name: reserves_in reserve_in_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in ALTER COLUMN reserve_in_serial_id SET DEFAULT nextval('public.reserves_in_reserve_in_serial_id_seq'::regclass);


--
-- Name: reserves_out reserve_out_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out ALTER COLUMN reserve_out_serial_id SET DEFAULT nextval('public.reserves_out_reserve_out_serial_id_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
auditor-0001	2019-12-31 00:00:13.204659+01	grothoff	{}	{}
\.


--
-- Data for Name: aggregation_tracking; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_tracking (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
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
f	9	+TESTKUDOS:0	9
f	10	+TESTKUDOS:0	10
f	11	+TESTKUDOS:90	11
t	1	-TESTKUDOS:200	1
f	12	+TESTKUDOS:82	12
t	2	+TESTKUDOS:28	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:20.348176+01	f	11	1
2	TESTKUDOS:10	M0KQD1A8W4YQ7X2ZTV4S3ZKTNRH15XVT81MBEY7PN4J1NQVAR8R0	2019-12-31 00:00:20.440903+01	f	2	11
3	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:23.331043+01	f	12	1
4	TESTKUDOS:18	AXHZZ9FQERXXE2V2EX4ZJF5R485KG1FHHFKEGX3DBKZ7WWXSWQV0	2019-12-31 00:00:23.416486+01	f	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, withdraw_done, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, recoup_loss_val, recoup_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\xfe4a384b29d332e3d9d303aeea2c9fef4a3f19ee33083ac64e0acca3e266f811b9a1f8f05600a195d236a0091016d131dc9250d9d9624603c7996da36655a650	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb66d8b3237a0e4622c32a0745063b5552537c69bff25d37e7ed93dbe53c605d8df70c8a6d9473905a224a8a92d0ed4caadda30f1ea4110c6da4198bf08650e31	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9bb0a0edf95d2cbdbd138250be0abaa26b7ada3a6dd35c1f66a71ab4d1046450070fb6a3c78fc2ad14c47567471a149d612f485783ee4c5c311cefad641cf09a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578955806000000	1579560606000000	1642027806000000	1673563806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa541d9fc1a18f27e774d2b1d9369b0cf9e37df3c3db27a8feb0245610e027c52b6e003013965b9aebdfe5d260b44f9eab9d30912e99a37941b913d09347872af	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19b1378cc646648ca655f084b262136038369950454e69b0cb8acf10d137ebe58e81b504a545ade1b48f281c9d7e2da88e932fddb311b106d8cc59768b1011f7	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x165db6d9d6ba9a271a80e5e4edc5963d0c38c49d2526ecc8885ac4bfd255cb5939e66ad26b14e4e6578b1c36a3d2eb7d9ffb918219c8e3e26f1120ab262bd783	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580769306000000	1581374106000000	1643841306000000	1675377306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2760be9c5f0f66eda9c72026b5af737941843746040217a3dbacdb45be112a54413af9093ebf6fb0ec3811ed7892514448c9dc9bf603df2ce6916e2335b0ee93	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581373806000000	1581978606000000	1644445806000000	1675981806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x94e1cafe5a7944d7a8879b7d8489c21a0a301d95bff5d50d269446a57ac713b70587589331a99b6be3e6e4c410d767667b429c69bc105855377caa7803e77542	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581978306000000	1582583106000000	1645050306000000	1676586306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdfebce3e4d39938fa080a5a53b91f7deb3f01afd4a24c43646e3336e34cab45af383b97736e0368895056d801fef91f93ec5861bd587af67d2c38aed7cd0ebc0	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1582582806000000	1583187606000000	1645654806000000	1677190806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50c69af2b89d3685fa525bf88528b306d8cc20c04d431ac3d3311cce8631e4d07903a7cd62b4ef4862a2778b596bb7dd643f68e11a4b5b941f811ecf6db023ac	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583187306000000	1583792106000000	1646259306000000	1677795306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbcd143ae33a5fcac0cc782208a32380468aea01da6d2552f01830f89e5844ea6d063d11e149dc274e813b9ae03ada52804d16cdca5b014db8fcf34c6e8c59182	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583791806000000	1584396606000000	1646863806000000	1678399806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3da5aecca372bfd35e376c4db87c7dcc6e77627634e3d68050613a565da91320d4251d0895b880dc803b5622c200eda9d2941358bf0ac5c1fa5ece1ea80e2953	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1584396306000000	1585001106000000	1647468306000000	1679004306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x951f3bb99e8539ab0eb5592870429d7bd4d157701f139338c16ff218137c636d80f7cb9b4980fbb8b1a7f91bd7811b82dbca85131d1beb151f277d77c257a04c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585000806000000	1585605606000000	1648072806000000	1679608806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd23128549ede4dfbca9be547b5280d6ef7471efcf88224581e3abf2beadb7559c761f00ff8ea4bdc492cdd348dcf41cffd734720b383f5eca52c9a190d9374e6	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585605306000000	1586210106000000	1648677306000000	1680213306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x23e97df2d089bc5f9d00d9883f4f912c90fe206a39c8638b27833eb2c9d63b92b9c9b1bd0985a34ed7e7f55edc6f586b58042cc6c42b2f88ea74338ad3e16908	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586209806000000	1586814606000000	1649281806000000	1680817806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd08e10483162cc2e803a8fc017dd3a9f209e6d95cbcb308fb54e5119491727dbc6d9b9fe62c0b0f42a14b97ac207c4ee8ce231c0d4c5aada43ccf41f03440527	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586814306000000	1587419106000000	1649886306000000	1681422306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x471aa85e65a943c56fc91e84b16464bd134d61b812e620a3951a4355b32fc970f306b2f98c83cf99592714ab6fba6f568d292fa4e80d41854e967f66c25e7043	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1587418806000000	1588023606000000	1650490806000000	1682026806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcfc554ae14f2a704873f5b32fac865df620cdf5512a2cd9e5fc1352716151e77c04941eae676dd3664b7e508e79f32a9d3adbf55ee60d730c71736a60245ec01	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588023306000000	1588628106000000	1651095306000000	1682631306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x38ec5ed142680836ca1e11971ce45ad553d88ae84e21011bb2927ebe590be69fba0bc8f7e8c4a53919c72476bec573c296ef2fea971faa6398a11765ce8a8b59	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588627806000000	1589232606000000	1651699806000000	1683235806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8aef338e0d12c05e2c611da31b833d2f23af74d951e88101fff77f8ec97568f97706110c92ee6191c1bf4f6ca74a6fbbc343e28feffb49539e3b44dcf3a2372f	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589232306000000	1589837106000000	1652304306000000	1683840306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc35d705d75a09bb9989f190b53e2594b846bcc595d54d8ab87ab2a4bf828a8d919f683747414b807073e8843b81f7ed58d4dc308aa5f7669c72b370792b2d89	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589836806000000	1590441606000000	1652908806000000	1684444806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf6a080a26d8703c90c0983f9dd3457423cb43d2948cc04592198425c5967a2caa4776078a56b2f94de1069df97fa297730bc717617fdddeea6037c048a970404	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1590441306000000	1591046106000000	1653513306000000	1685049306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe1faae443423e1192fd10df08f4339e51fbcdb8630f502681a44c723e68646408966396328a13ea4a322124c888ee0939a2756133f278bfc902d3e0b730434d3	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591045806000000	1591650606000000	1654117806000000	1685653806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x90286e436938801764b353d8e1e980d8f584ba72e48ac8407ce06f5076e1b8041413293b0996b726f3f36ddf8e3c0a5724817a5a01c2779d3640ea7a4f0694d1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591650306000000	1592255106000000	1654722306000000	1686258306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b2e9fad7cbfdb30bfadca7578ecb22169ff8eb6a6af9172cf5c780fa5271abe6dd6f770be293750da3b076eef6cdfd3fd39a6f67cbfaf85e33cbbd2cb3ddf69	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592254806000000	1592859606000000	1655326806000000	1686862806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe73d4e7746508bdabe5fcbfeb4f150db5baf2185177072965f33d6e4ee0e3088757aa9f65a80acfd1cfa3905b883eb2c3ac7b74feb561ea8009a2db3887de0be	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592859306000000	1593464106000000	1655931306000000	1687467306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86c6725be5f2cddd4105274ecad7e11b10523bba0d361ecb1b76b4db2bf8de0e84ea6af80ae9b1e66a53886816cb26ec57f8576df79ac04cfec5ac1a80ce2350	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1593463806000000	1594068606000000	1656535806000000	1688071806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7459d45f83d895aee4c209856f935c271c30c536a0d1c380ee18ed6c1e0d90d7b5ac3570fa72067d47514ed8f2c07f45b646450cbeab4b558b09b9a1fbd97cc	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594068306000000	1594673106000000	1657140306000000	1688676306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbbf01310e09bd87cdaa72edcbf7bcd0a49447e77f309c898c504f85ac1064010216f7dbf87f1e81360f7e7ed3b9079faa2de0faf60934fc82d305a30493b17e3	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594672806000000	1595277606000000	1657744806000000	1689280806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4315547085a97e4b8ddd0e5e1c8bd60d906272e9e01265cfedd8e1d4b82c0112e50ca3bdd3f0e1e8a47f54d6a22ccc105fa2de3dbdea6ee49df0ae89b2e73249	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595277306000000	1595882106000000	1658349306000000	1689885306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x165544d1cfccc25144a3c65c72a1af687c0948c150e6dca9246ff46a852d52f9978f274c9bcfb29d302600c7b64cce8f8cee3dd451b9603eb9686b87af042221	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595881806000000	1596486606000000	1658953806000000	1690489806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc72a140c8cc10fe5b70c16918ecadbc0f06ade7d96954c4bdd95603dc96f2c66334d32d527c9ef76544464a4611e98120ff17a5738bb73d40f38f0084b6fca8	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1596486306000000	1597091106000000	1659558306000000	1691094306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xceebb9b2b787b7cb4b6ebca3843d4f461a566a0f1bd3698ae43454e6650f85084084b1efb4f761be95096e62d9fecb03c21565715aae41c9d262bd932787674e	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1597090806000000	1597695606000000	1660162806000000	1691698806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x864764cd850c74f7156fcbc0a578f6681614f08e491a3af2019613e469c8bb1b8c5e0cb062f2f834e307ee4255c65a54d83ae2b74aecc7a38de232997e1686d5	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x55438a14f98b816f8fb2db8357fe65485821d7c07e17e33d2576702c4822bb0ad9c376ba465b6dd57100ab963b3ff18268a0ff9cbf047b2f104eedb95519ca55	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x09e20e6b01ef85d9b7bb6dd508897838688c7caba908c0a0eb2fbd363ac320057b195e4b71c931b48ef5d3720a56f37aea42cd0ee232e41d6f8a6429a3eaa658	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578955806000000	1579560606000000	1642027806000000	1673563806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x154ef02802d2365cf9a2e591a96898f2d519a3ff375825c746a116a891e7405f868f43675b464bb32e19549b26d57ae13ef1af79b2b8d1df143883a3900576bb	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x221aff14cf68c10438a093b36d559a0f162eb91aa70566ad452f7d821279d9f525515426247ca25639664fbcaf7c64c9fb3ccac65531920590dfe44937aa06fa	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1cf73f1da9b3b5e30cf022b557009b6e05844b8f51d783b92b42e7adabfb609e3b341298b437ecbb7df4d19e0b36b1d026f274feb6f650650df6976026026a98	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580769306000000	1581374106000000	1643841306000000	1675377306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2eb6da7fe9f265cd4dd86a608f9030b99b6ab388b550c75e8176742364296d31625f49955e721be9e0b84bf272b1e58d736c174664475d350ba610ad4688051b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581373806000000	1581978606000000	1644445806000000	1675981806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcb21ae0402575cb009c0115e3a60a7580871967e874e5cf33f32a91705419272b6ad6c4b48c83f8ab38962fd74aeee592253732b6d21234b469b4900b0424ed7	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581978306000000	1582583106000000	1645050306000000	1676586306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8b231522605ef3177ae862419ef28bac2c13c8b5f74011aaf7a2c74c6ce7002143c207c01e99c29609c2fd1b49b846a85e2cce60ca0911d44d66eeb57adae425	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1582582806000000	1583187606000000	1645654806000000	1677190806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8cdf09e50d41bbd3606d1621c771426ced00233f275b6361ae12715544dd748bafdd19c062490f705ae7cb1714199f77849c7d1c61054771bdeaa9ad99840af7	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583187306000000	1583792106000000	1646259306000000	1677795306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x66d84895c95ba25434b0603467e531f3d3def5e2b92fa5130ab6c5639999b0b4131953e45e97b5db5b27661eeb4c60fe07cebcc31378fed0cff20e8b07b3f567	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583791806000000	1584396606000000	1646863806000000	1678399806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x08a9cfb631d873cc483aa7639f98bd21bc7880b4104d3b98c295adb49446acc37d85e1863a11e584c8a90ca6e9451ffa60a7caa969dfe17a162b990588bc4f8f	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1584396306000000	1585001106000000	1647468306000000	1679004306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfda2d9cba9c5480e0bb8cb0d1b01cba15bbfd34cd578ab0c0a4c4ed80850580ed021f6eeaaf525fe3eddbc737d7bf7aa6a7c4628376e6f25f09c89f12086ac37	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585000806000000	1585605606000000	1648072806000000	1679608806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9f842c93f2d5c69a362707c6671ec7dff4f3c6bf1f1a65a7bd8f40b3f20559edeeeef371fb066ce845d772f22f73b016485ed7fc1907df5be51744a890a80fba	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585605306000000	1586210106000000	1648677306000000	1680213306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4543ed021169c18ffa091f6f209bb93be2475c3f86996381b7fc8050a39a9e8c2d8b0e158d32f47f0ce73601dd1722e7ccc207ba56d9eaa3106f441b18763c9d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586209806000000	1586814606000000	1649281806000000	1680817806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x89b0ded0c3533b0851a3a861ba26d8c0271dfa95f6e7a664a779356f7ee46f031c0e137edc07f9e3b9da000b71d72bd585e2f9784c711178a823f8c1c13b5b1c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586814306000000	1587419106000000	1649886306000000	1681422306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x84748db7a170c9d67f5a177300370523de5cdf6d2863ac8174be4792cb42a3c354700b4cbe917369babf8573d4c89cd318ee826e8ce88bd05e01f42e8f828397	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1587418806000000	1588023606000000	1650490806000000	1682026806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbdd62b4bdcfbfa80374f87eab25219d8dab146b3ee19264d54ce2f7adb25e8984398d219ae88baa5381d71fe96520623d3345c2c0e42e6b7e776bd0abeaabd77	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588023306000000	1588628106000000	1651095306000000	1682631306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5d4f9c865daff057b43291fbf6e834863ed9d90921aafce0a26be0639cb372e2a0788ba04a2261c6018da97b012979efd36371824d30dab0121fbff134c36cfd	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588627806000000	1589232606000000	1651699806000000	1683235806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x801a412adc3b82770066209501e68fdfc81d4b2ac200b14d7e6188881bbe1bc329bb29a6a10d4192790d7ebf8c54b09653ac51490e884a0fad11f6c86b4aa761	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589232306000000	1589837106000000	1652304306000000	1683840306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5763769a536610fcaf79d26a767b8b78d2a7874a540c3175cf6ba937678d2e22605291dc77050b53523b6c9208abb45b45bd56a2ca697eb063fd2103bfcd0d37	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589836806000000	1590441606000000	1652908806000000	1684444806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa827aecc044849d4c7f060355a632b7c8edc581278ba0749f1cc25fa595a6610b9e551d44bf4b4fe4c50bb1856691363abff9eb00dea87ad6a20c1246efde0fd	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1590441306000000	1591046106000000	1653513306000000	1685049306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x53f56f58faa4875c531416025adef45c729dce5828aa03587ab2eeed1619e479687d000b2c5c5320fd5096b01230c39aeef685739a06f5582edfefe73bc0cbe3	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591045806000000	1591650606000000	1654117806000000	1685653806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6bcbd712ac212ad34c37e3a3bb83c6cf2483858ec2cb8371a975d93588af536816d32eba90b8794cf6bae9f6372c174e86fc185c8522be4b89bb63a955eed7bf	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591650306000000	1592255106000000	1654722306000000	1686258306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe327afc171d021822e3b1658f6c2ba278f2f44118234934faac4691a23c5ac49969a36030744f4f40cb94840eec9bee27de303707c832059de8414f1121fd3f9	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592254806000000	1592859606000000	1655326806000000	1686862806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe96fcb79c8d4d49fe0dcea86b3d95d3f02242e18f00cf791a508b7b77f54628491074edf2665d36442602f03a376d48665328ef339453602199437027267ba32	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592859306000000	1593464106000000	1655931306000000	1687467306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xceb89560175ca3a60eac117ff2dbb84cfbfee35aebb84bb8a929a16cd2e4fc034ca32fb36948f4223c3b7e1de688b4d8a640c5bf0e447428dfd1960fd549c395	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1593463806000000	1594068606000000	1656535806000000	1688071806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd25824b037330bb7ebd98cac8a8650e8ab47d0286632bfb449fd06b742137ddd7ef90fd6c5a0813c7b6a190f593503854997d91bc29dfe67571948f3b480f92a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594068306000000	1594673106000000	1657140306000000	1688676306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x79b9f243473a82e97f37050de1773e7012eda11ab0386c5d1f56705cbb53687a2189d1daab6ce73618eb9d0b062ede562431d8e111ea419c1ebbe054a5216171	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594672806000000	1595277606000000	1657744806000000	1689280806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbc1b14ef98c4d7101dc7a023d4a71922b39b8e28e090a0326585c73444965b1f3b6c52d03d9597180ea3c154459707e6560afdc421d3eed95ae8317dd8a98230	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595277306000000	1595882106000000	1658349306000000	1689885306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x92e8725851f9401903dca8e698f115df48ae9435216a466b8ab692b96ddf7b3c7a88dd0373b6d27398b7375496e04b51018ffd09f39f3c53c4f81ec7d26f491a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595881806000000	1596486606000000	1658953806000000	1690489806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x86755dadc28084a3212cbbd9aa5cfaa264f78691df2407162ffbbf4eaea8ba22030322d5dd15304da8ca523eb5ffd9578775c2dcf7f03cc31b51a8bb36ada379	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1596486306000000	1597091106000000	1659558306000000	1691094306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8499c85027fbf0238976bdf3fda0b4ba40c75fcda9bc197058af481125b170f332854c1347f64c14421e8e7f4184a738fa00fc556914ef9c49f3cbffc3b4ddd8	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1597090806000000	1597695606000000	1660162806000000	1691698806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x999b45838354fdcda3ba5adbccd528273acd2415d1d568833619c3094a4b7539edc30f1ac7cb879ff24c27a2eeb63490302fa03a7063ffadd5e9bf28d0b59c0f	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf52accb0184b419f21673cd79b2e25cd7c0b0b209c40dc6b49577bc2001f248dcb3b72ec25bc99fd005f0da0f1645ebf8d39846372c8e4e2124e8d4b4c4bb1f	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd73a52d87e71c4a0d223f343c6232e2d8e834a32844b81a3b7e667bf341f855f394b4fff4a1a4f4607f230da510bc17c4fb51ca3a1fe929695fa0ccd870d571c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578955806000000	1579560606000000	1642027806000000	1673563806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6761edde947963741f22971e70c610a54fdb12c67542187c639579b33a32770666969540aadc764ac60a7cf77437a13935d202290f8b44ba64cca2ec8847354	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb468d854cc75c3bda251749160103a85039d7f9090e0a0658afe2692a3d97179db4195708461ec30b9e0a0f3e4aa0505132aef2a02336647306838d74bb77373	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x52890a87f3ed19e64cd14bd9f46e9f559c9e73b852954d4f3c661929efcfa491294d5a62eb942af05e20bed6bc519962eb20b159ece17ebafda9804ea0bcc1ab	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580769306000000	1581374106000000	1643841306000000	1675377306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa767a791196bf0872f96162a4d78c0f96889ac1cc6a62cddd98389a49bd20477413f97a27a2e9d47675c0fb9b6cc21034a9daeaa7789d8a0262762857c66e47d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581373806000000	1581978606000000	1644445806000000	1675981806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0eb511912a27c74709353f84c4b7ce35ec37443202c307f84a682be8cb498a1540ed0b4a7c4b7ae99fc42280c5e52a2d0b0145197eef728eb681111b622b942c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581978306000000	1582583106000000	1645050306000000	1676586306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa313832ebc5f7ea4e1798f7176e8b1cf4811864f679458102dc4099431a69dd46e7da84d428a1091972bde2d83419fc753f7a9736373274229839bc35852af01	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1582582806000000	1583187606000000	1645654806000000	1677190806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaee4b25274992afa67bc91e81f13270de2042b79c2437f0b059d58a002b61a9fd218cfe47dc44158c0520b17127d3c5f7f6f2fccce49c23b48f8ef38b2a753e3	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583187306000000	1583792106000000	1646259306000000	1677795306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb0c968c209fbf16e4657f3726d83ad1e5c6503f370937a399563ebdaa2ae2b978fb8d6de3385143396960c00bf5f017dcd7c5c3dc1f8d9444b0e41be84b49bb9	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583791806000000	1584396606000000	1646863806000000	1678399806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd8f297a84b04280863beeb012085caab57237b7ad028ee7924e983103942f8833072c5a7fab3bc7503f666af7819761440bf560e8e1ef20c3763e3fcf97a68b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1584396306000000	1585001106000000	1647468306000000	1679004306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x88f5a3c7277045f891f6c4bccdad32ccdd240b6ee48c9966ddf2a65e9815663760b563db81d51a93fb65d6bb6761b3a0e995118deae1053493713973e6f1b8b4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585000806000000	1585605606000000	1648072806000000	1679608806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4957bf401390c2897abc4f4add8b30318fb52139bd0b2187eba53ff5d5b493cdfda078a30d72ac7960a76e4a663e7fc1f41a6fb4a40c6d9a28dc751f93b913b0	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585605306000000	1586210106000000	1648677306000000	1680213306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4821dc5ac1d601307f0f78c05679279ad21555bf4b33dbdaf20309f1c0fab60dc3257698bd177dc0428203925036ec728fdaac36493ee25f711b0a4195cc3072	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586209806000000	1586814606000000	1649281806000000	1680817806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53ea6efe8193f1944da41cef04b8c46c18e753a5af7137afb3f950ff7f96a410fe588c449f88e5c0ef398c61b791f4492088e977c18b3d54cb490461198f4e7d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586814306000000	1587419106000000	1649886306000000	1681422306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d98f70fa4f87682b4a742d1f0031feb68ea3a8f621754bbf66bccb1cda1463144e46630f7aeb782360592659329f75bc21f37685a7e113a9c043be4f80c0f0a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1587418806000000	1588023606000000	1650490806000000	1682026806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd61f91d447084e782e4d87544e7dd4deeddab7b3a953126858a7c291e81a7d9d35092242477491a39521e689c5ffc1308c5968af530fa3df49f6bd276c93668	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588023306000000	1588628106000000	1651095306000000	1682631306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0763d5b39067053376e50a1af5cf2cf8e6c26e6b5f8b47288fafa00f5194552976ff650db08fc98d0f0e7b07bdc788a9e7f9e310011e3ab2da0e5888ecb74006	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588627806000000	1589232606000000	1651699806000000	1683235806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcd1afe65d90337b816ec3aa174f0cab533b19ea4548bbab7a65eb7554fa151e6a570a1658d0840c8fb3f167f50bccd18704f29c3d8e091944612362f798842b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589232306000000	1589837106000000	1652304306000000	1683840306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc6ac70162fecb17c8e2bc9badd778b199c489f5bfde06a2a21d27adfaf0311f1e840fadce48548ae7873f590a669919624705ef2ec9b22093795706746af939	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589836806000000	1590441606000000	1652908806000000	1684444806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ac71726d1c09459a511536ece004a6560b39cbadc80e2b3060de3d580ab1c5263c0336d3962d767516f84b7c7932dc0e1f7036c8b937c163e29d0ad8fb390f1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1590441306000000	1591046106000000	1653513306000000	1685049306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18920a8ae0b4669ff84d2654a68dba71f867e0887db382917566cbc94c2190d30d917ca3b7d1947a82d29309018cf1b1a86ca0c755b9a478c0de6f0f2144dcba	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591045806000000	1591650606000000	1654117806000000	1685653806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x418136560b02bbfa4d141037fd31b5fdba67183825114b7b37a99d227e8dfd10a6fe8b51d1395f11013de2da48c0544aa7a7c6af9db2eae8ff9fe563d17143f9	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591650306000000	1592255106000000	1654722306000000	1686258306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55a1a7fba389950ef26e6ccbdbd899e00f9241b1c275409585442a58891f489d5821789b756fd5bf413fb1d4c07dd96bd318e04737e2e074aedb6dd870ca793f	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592254806000000	1592859606000000	1655326806000000	1686862806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb11c205b91b9e57a900b9b431d51b86648adc09fe7c3e9caf960e3fffccd3df3ff13e8f0bfc7e9a103f48569a94011fd4c0a9deca97c1fd52dcc051b305420ca	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592859306000000	1593464106000000	1655931306000000	1687467306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x88b9b833198e3144514d93faa45b57744e2b2b0304712f33cb50cc493be03194a88ebbcab92b0c1933bbe47862174c72623459926eb7303fa58c2fed0f94dadf	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1593463806000000	1594068606000000	1656535806000000	1688071806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2b20dd4c1a7cc90dadeb1992bc48a9cbfde7a8a631bf2fa53bfb4d842ca116138c952bca4fb1c139304c92bbe8f8917bbed4bab67ad787ef3388218164b51325	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594068306000000	1594673106000000	1657140306000000	1688676306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca3dd487285792cd1b8e5f76056b29750551c6fe7883f35b27e268f49ac028e971c9287ebaea88e699c0da5a6ba81dba6fa7bed7f35cb67aee38190450b89c7d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594672806000000	1595277606000000	1657744806000000	1689280806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0dc8cc93ef8c23bb8dc34252f05485292a76da6e990aee3a1879850e4e87e30d56450123b1766c0bb51bfe905a22990f97f31bf24d9f270da9b51486f40f1b58	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595277306000000	1595882106000000	1658349306000000	1689885306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc6e66d66310734cab58fd8f20c49bc1c6c9fde65a264310af6d94880ca2fab6bc7739fd3dd4088ca5ffdc6947dddb42737ef11b488b302cd29f4140e7bfbb94a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595881806000000	1596486606000000	1658953806000000	1690489806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01eab415848c75be2d21f2333d955779702dafc444383c85dd495cf86496de8ff3326ac5504f6f18fe3133dd9b67fce57da110053563c25afc402aff26a822ee	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1596486306000000	1597091106000000	1659558306000000	1691094306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa33a409c4b9ff59a9782f0cb2aed405e4b9d01d46fa69f29cb0a7ec6c4d155d04785900acdf44e6e2e8c146ea704020360b67158ad4090306917881b4092323b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1597090806000000	1597695606000000	1660162806000000	1691698806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe88490a0a4038764bdfd141764e7263f5f55c904a540846dc7b6fec3277de25b29f8dd46762404ae50494156e830394fdbaa50032337d2aba2c09c3706d11efb	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xecee586dd62f06d44465b45898fe6dc1ae56379ab1d8621a38dea276f84e27b2d3c72f4e759956869576281ed5e0cd442b580b93dc449186635706c93d440c5e	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x128d32926ab450ef81506bebdddc3fff6751fb8eb4c89d3eb93e81b3e2ca52955d9666f4fcea12c7cb2248e98bba7ae5c8330c70270521986ab91ba0c7e1553a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578955806000000	1579560606000000	1642027806000000	1673563806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6333f9e7e670bf30b7fbdbcae33cdc6df82045ab27782a63021d1453fce13dd2f134fd3c7baa9a7d88df861945e061723afab9e8f491a8cc9b2308fa6009aad1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5484a9964ad1e7e1161c897ccc2e8a54ee516ff99ba3f40ad35c23613d5c8dd0f4463de960854d2a11b1ac41c8c7916349d2776e9d4f5746e3803f289c2e8340	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e5a80f3fba9cbe83f4af7ce9d081b7233584397086414af099206f6af79eca1dd5181f50628a24319f18e7538c9d604e991fbabf64fb713ab12f69e35c114a1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580769306000000	1581374106000000	1643841306000000	1675377306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfc9694afdd6663eb9e614de005bb9097d9af24815678651bdf142f5b1dc9c57e86076c90fb47d172a36c769932dd42444a11d3d819789956706c4093d888b85c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581373806000000	1581978606000000	1644445806000000	1675981806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9791225823814a1e947bf9b65b150021079b6d12a5218cbf8545494c0541ed43671f5a83cafd54119181fdf0dd0e67804da86c56fabfee7189e395ee0cbb2072	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581978306000000	1582583106000000	1645050306000000	1676586306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe6a80d0469dc88aa31cd952b9df8fa0002bb18a1d7aac0f38d00d7a1773bba6cfc45e81439db3021ada875892b5e3ff6df8c16110b8cd46c1ff94a2225e46377	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1582582806000000	1583187606000000	1645654806000000	1677190806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd705610a881b678acdf74d0fc8c246cd45d9e2fa5bd02a6086f06fe7917b4a15ffb901d46fc3221421fffc9762271738e84a7d0a378d17c683c26b75300aa5c3	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583187306000000	1583792106000000	1646259306000000	1677795306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2d36da21d72e19f7fab30d0879da7e051925fa6b62342dd2443776a1ecea6b37f18dc3494e728593957802aee7d877cb2f20bc1e0f4a09d3526fb489f5f352e5	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583791806000000	1584396606000000	1646863806000000	1678399806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x34e179285397929b17bba0d1478b1f3a6dac87e1cf5b33223b907ddda9b5475aa705c7cfd9ea1c16d298e7c48512b34c810720c553fec338f8f6e09725d7f3a9	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1584396306000000	1585001106000000	1647468306000000	1679004306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0ae993331777f1f5dea1d69beb98ad0b0d637f19eef77a8030fc159bb453c4f4085baf007ecfb9a1dd5e399f58ee566897a21c77be8080b562934617f09bbcb7	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585000806000000	1585605606000000	1648072806000000	1679608806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7dca51b107aa4f4ddc2ea79b9a4fa610375c0e85601d47553ec8b4878e5192e34f63eeac2443715a923d11fd427a1f75f4bdf6a0fb3d0292736abb413dae467c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585605306000000	1586210106000000	1648677306000000	1680213306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb1c4c22e9b5c070624418097567f14711fb4daf97385aea64515167991cce2c0dddba372361336296e774fac6107e0058f72098e37a6a46693f5ad944b1656f8	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586209806000000	1586814606000000	1649281806000000	1680817806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x025e2ecbdfe0c271d4b39f0c5ca9f0428646e2651df8e2d78d63ab01fd9af8159a7c04e3de19d834e90fdfb5e65933138a89c3f57b96bc60d2b7299c6111ba8f	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586814306000000	1587419106000000	1649886306000000	1681422306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9c972da31ad2708608fc0fe73c167f2409a102ae49732cde448b875f6b4d2362818d3fb2f6ec6a6472eb4a42abbd04177dd782ee35edb9ca00a28e083264fcdb	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1587418806000000	1588023606000000	1650490806000000	1682026806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x32d3d8cadd04ae214124d1b5fcd8e81b6250e0097d3b5bd2d740cc30aaacb6d10eadbc9b3ddcfb49cecd67ce84d58b9e42a93d87c54732ca3eed131c3567c4ff	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588023306000000	1588628106000000	1651095306000000	1682631306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe16ef9a45f74fc22951d3633be668f4f8dfd4527886e934c4f270272eb3abf3ab7f1d1bd4d74c076e43bb90f98b9e68a02adf4db6a1795abe684ed31737ee1f8	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588627806000000	1589232606000000	1651699806000000	1683235806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7f0d15ccb7f361eb998af5de98e033fbaf1718a44f33e841a9e405b23add96b6a3e51becc478fa0bc822e4dbc98a00a26f3ca410f2019ee1a9f53d003627a27a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589232306000000	1589837106000000	1652304306000000	1683840306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe7fdcc98994afe4b381f9e3d270be436dec2b319fb7e563d21c67c834b9bf0825cd8ea6d3658d8932db7b6520b76946c1438c6aa3ec7704f179d9c8687faa0e0	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589836806000000	1590441606000000	1652908806000000	1684444806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xda8ba49924bcdf7c3564f465e4664278f1529c361b42b732020d7c9d53364f621ff206ab4f0a74474d6f83b78c4e9ee3ef576ebf17cc8cefed61fac273c4e96d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1590441306000000	1591046106000000	1653513306000000	1685049306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbd1f7b21e648b856760d97fab405f5ca7ec126f0bb47564c6e1eb931a66bdbb79a81cf6b773dc896015f3276f58360c2a1270534d933a6b51814f62752003127	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591045806000000	1591650606000000	1654117806000000	1685653806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7773cb000483878430a5248f230f2596bb88d337ecc889e17af5cd3c166436671ff93691c76a70173a610d52b1452983d39644306e304214294edc650563607a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591650306000000	1592255106000000	1654722306000000	1686258306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1635bdddbbc09094ab400c518a9697e9981dde52c39aa4e15737c01956acd3f4b4b6b0608b3b69a052f65b0e601853eabd52e879ccf189f35c19301bde6fcb97	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592254806000000	1592859606000000	1655326806000000	1686862806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7965ebf41d7678ed183dfdbe5a328482b173978f8d64fd34d32ae712fc02eef59886d4bbecd016229a4704d28f89268382cb88ccc0184d142cd6ed08e43344cf	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592859306000000	1593464106000000	1655931306000000	1687467306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x14d85f27c3935505d289d82e07d9a516fbc5d0de88a8a8737b5c36522b4e0be7c1a6a3f3da7449b90846b795d914f6ca55a21bd212e40acc37db6b5bb1a3e876	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1593463806000000	1594068606000000	1656535806000000	1688071806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad67186d7d565aa9913065b29b392a492416767aa8be4d1d8efc56f2b57a6033f79f90466a6cbf0f6224dd8ff8c896a2f2bd94a3d032f9fce25ecc1db6655f17	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594068306000000	1594673106000000	1657140306000000	1688676306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9829c166571883765270a6b95d3905790813a4c32ebf4aedc826a098f81bbba1458abe022ad606639ddf66fcb267ec2bdc78528a25dc7c7cf25d621345c62bc0	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594672806000000	1595277606000000	1657744806000000	1689280806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad18ee82b3a3ffcce1ba51d74fd4e950219970535d0bfe936d34a5c68bb92df8ba5ff38b5235b958b48c3f1cca81368cefca6e4c19263b3e3ae4cdaf8a22c85d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595277306000000	1595882106000000	1658349306000000	1689885306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x468882814d0bba6f213d823e33217e15b7b70f81e03e92ceb57763a3cdcd3e47a72e3e72cff4afa74b25ad4f393f77ac58346e72ee209d91b969908cbd7efe93	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595881806000000	1596486606000000	1658953806000000	1690489806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaba32a56b54df2aa3038223b0f5ab36e2d37f6aae5731a9b485793c5f01f4d3d8270a367ffadb7dbf9493e7c0da5e4b1ed7dfcdcaae7ef7b6a7afc95342a21c0	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1596486306000000	1597091106000000	1659558306000000	1691094306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4f28465b5036a3ca188661e555d146b186a71cb47556d152e690d9b7314d7c7f2c960aa7e1ba089ceb94f1a90ca7c0fbc6a42a408c0c88b5988760cf69cbee41	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1597090806000000	1597695606000000	1660162806000000	1691698806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x689cf12eeab4214b767c5f4a789167bcb8dbddbdf8b18fbe707064bba64162ca099666d3879041aeec6abbe36bb3bf95534c1a12e2b9d1c99d78dce681262172	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x69847725a07c82dc2ce4e881019a96d2791152119f0c1bfb93edda25943ffce869667959b4dcc7b9d6548322c0a1456b899c4538e643505eb558dae47b166ea7	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12c6d2e1a6530cdf6602191aafbbcd211703b1e81bcb386bd9c2561de6a615911f099ed0205680437a2e8b0e44dc6af1f9ca1fe844504d7ce58fba702dd81178	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578955806000000	1579560606000000	1642027806000000	1673563806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f6a21d5d6d3d2a5dc879dde8b9212e1212a36a4651fd49ca2a41cca6ff0c464258f57e00a6cec13e000b50ed9158d69996e0bb1d294e000681ab7313abc3e75	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6fedb56536c1f8e8ea796667c0c313138519bb7b1854d0094fe15bacae902675e78a27a6c87738a20aeedfcb1e671f212d89653b62db037786df3a99b8168332	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x988002f8e996daf64956fc68310dd908d0876b16667e98ed9ca44b8264cdd58613132aade3fe677e815115e9624f02b01958b6fc7d77248888023303a5308b78	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580769306000000	1581374106000000	1643841306000000	1675377306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e5b4af2e65b68c7589d3e012b56c95e7381a924f5be7edbd674c6ff4ad0a1dc81dc38624de5dca85b5079abd3a96f96e528c454791fc2df2fe2c3960027b82b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581373806000000	1581978606000000	1644445806000000	1675981806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x896bc79dcfd606b13638d7dfecbad121c92866abb6f541483313e87870ced2ddba2ce3afe2bec18478565aad772906a0e0db7a0c29a10463a3911b7a07e613cf	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581978306000000	1582583106000000	1645050306000000	1676586306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x72811fa51af2491c2b780ba87c1a39c4290460e77be52d35e0db78de4149e3769072de03a2912dffe8809d18f0417d20ff47474a0be493dbcb135558d1bfd7ad	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1582582806000000	1583187606000000	1645654806000000	1677190806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdac38f15e7962c144293216cb6e62aa9638969cbc7a0831153c004ffeebee393ca9e7eb9e3c02fbd5d2e89f7d8f30f1e29556c17bfdace65d7b520114e319ff4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583187306000000	1583792106000000	1646259306000000	1677795306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12ffcd38877f4cb74721c6996b5818931d7cd49f16bd5f905d68528f2a0d4ed41516ac788f7e4522993d3dfda6873fed3037965334c0731f8aa94686062b2304	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583791806000000	1584396606000000	1646863806000000	1678399806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x58fa49de7d0ae80e2bc9871fc162e75f8a824abb5a870e4a1bb50e2d3aaa7f9a6e36cb2b6778e4b5521af05e7432c3e8ccf9c5166c2e3cb94e174101d08cf580	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1584396306000000	1585001106000000	1647468306000000	1679004306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2f013f7bdc3893636faed37c1eab587a698abd1e3aca93d28a4db2b2a559e6f66324ff295254711c47c10a1eafc4671757e6607be8e05f9d26c68a75316576c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585000806000000	1585605606000000	1648072806000000	1679608806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xda6ead7ca18dd9085159911ce79a4055dcb31cbb0eb6c5d3d303527e2564e9fc158e464cb4796d7ccabd403838b7e5490b0633444cc795aa62f95a8c54307b20	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585605306000000	1586210106000000	1648677306000000	1680213306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x855850e1eb0c75a2ba8483b7be61c0565f6a5964baf75cdd4b0de71d1b410f369acd5af0c2c2a06fdda179b998ef7aacff28ac05fbf6e7f8eabdda73a5933d69	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586209806000000	1586814606000000	1649281806000000	1680817806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x00407eff387b9084fa82d41b0c6fce14b4db0f759111f42b77f87e1d5fb8db3b9de4c14f26a4a8b1d9f9804f71c00e5a5107e3984f526f30f8e816a08e0607b1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586814306000000	1587419106000000	1649886306000000	1681422306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe4aa4881ec0d6a57e5fb013d52dc857a4b939c1791f0b246c42a645db1a24122adf663a9bff0fd07e5a2958db84ad66bdb3cf232aca4f60fd640b10008d126bc	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1587418806000000	1588023606000000	1650490806000000	1682026806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x959465df059bad376c12e49cf6947b4db6d14fbb05947c56b531908cac7e24e30b78125f1eb9fe05b604a20085b07f8989152fc50f598f480537240f7d966b36	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588023306000000	1588628106000000	1651095306000000	1682631306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x93156a5f1076777fb440c67b37e693a57c69a98e479098892f717a14f9cdde66abb1322aef99e7b7f39fec8db09aa164fd7aea423ee5f2f78a0452b12fbb3f31	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588627806000000	1589232606000000	1651699806000000	1683235806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcbe94bc7f14c8acce8fcfb0666926093cfd090e7a5ac6bd5285e3a4068bad494aff5232e10ae799c29c1904199a4865f7deed05fca514d12e1747cd801ab76eb	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589232306000000	1589837106000000	1652304306000000	1683840306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2754b7d80f39f326d10138b5078a35e7ba96ac0ab577e882d76eb4cbde643b04201c50746e28410a1c41df14bfc32c0f1c79387b80e07b717160881d3d7be2ca	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589836806000000	1590441606000000	1652908806000000	1684444806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x79e6179108fe326f881a82659fd8bf9ba1871e61296d4b9ad869dcb05c3319d9bdffabd545f736adefbc053b84b462ce9d7be52314516d3440225ecea92b08e1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1590441306000000	1591046106000000	1653513306000000	1685049306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc2301b39e05f4ec2442fe9c44439b3dbcdc7d579c34dee71aecbd7b7f591586f674312f4437e10791da27dd4fd7460d3964f2fdf388abd09e2ce2b7593195005	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591045806000000	1591650606000000	1654117806000000	1685653806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc54f1c2c5b35f7b0324ed304a6b037b554784490e8f3727bdb4d84383add82634f815252bbb9f0679888c77a7a04660b63636095b62d9ca06d2b1c93c5d9347c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591650306000000	1592255106000000	1654722306000000	1686258306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x659799921b6a0cdf2c3df0085d8c30eec2883ac1a8154f62d5bfe5ba7b1ed5dd7dd4081171dc17c013621eb4ece1791cb87721b5723f28438841aaf38c920d22	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592254806000000	1592859606000000	1655326806000000	1686862806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd337ac67c05847204041dc4e20af607cfdeb2f097b35a8e4d2d21ee4963cf34b269f97008401e2e9f6468559ae1a15946558283e05a9496717ad29f8dda0927d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592859306000000	1593464106000000	1655931306000000	1687467306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95b24b30faee9f1432f07ec500205e8dc6c7a2fb26c73efead1757ba4f13fb625ef10449851acd5d9ab3cb0db66231d07a549273de33cf69a80db2f51b8d056b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1593463806000000	1594068606000000	1656535806000000	1688071806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5d7c30dda42bc15011b315d8be91f7940e22a059a509edfd6a1feeaef86eb66b6652dcfeb205269b73117d2f9f62fd11bd3ca98280cc64fffb14cfeff15d5a00	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594068306000000	1594673106000000	1657140306000000	1688676306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbd3f2aa62b86bfe3b28453620b5d316cd2d378cc555e9858eb3b8ba9115bedaebc4d3233f76c85b05e972921297d8420a9a62c8b3266983514f825190a86713e	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594672806000000	1595277606000000	1657744806000000	1689280806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xce8d9eb3898d795d4702b3b4061a313eb0aeeec38d55edcd437c7cf83941fd9d37092969268faff369246eea09bb5a839c634c605af800db4224add7396bdd43	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595277306000000	1595882106000000	1658349306000000	1689885306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x76d85fe54a6b87c234065b32cc185816e1fbf17fe64740418445f054d702d8042750a8d0c97e8acc753cec4ab73416ac8d310c33f79aa68e20a3d2350914bd96	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595881806000000	1596486606000000	1658953806000000	1690489806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5e3bfaf0b5c82395dce1a04fb3521a491d950313bb6a19e2002e92d33e0b676b87e341ef6d7f25f311181174c260a50aa16396e45bfcc51e1b30749726f26623	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1596486306000000	1597091106000000	1659558306000000	1691094306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6f5010ae2e2e8ec69315ec45e11f60d64f00e964ab60a31041e7554733362609255f87b503e4c79381d4198b377f856f4a0b813131b44f826d1c5f7f5a8d95f6	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1597090806000000	1597695606000000	1660162806000000	1691698806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x535ca90a5eeb58999c713ebb1b8de33387f9736bdef584767dcb73d0827ff784075f99f18626b9056a89a3a8a2db0cf88a61fb869f09331528999eeb09579fc6	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x80710331ef5f0e361dd6e549351f52a2151d06c7983109238cb6a3797abf3b20a98aa42c94769485185b4f67a17a893ec6a5ba57d2bd80aea564ddab0a96808b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc39b32f9cf86031fc57f4d07fd1e3556bf85f8f155ff2d4e748fe790f922bdb14ab70d767428c0ac8021a7528afe7d7b76c94a89b33cd73b7ad2313772b734d4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578955806000000	1579560606000000	1642027806000000	1673563806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5d244f9257036d9c0959e71b33339b26aa9dc4995cf07e9948456a85cd319cacc6d09d2fdfa33500fd40494e1b089dd7b472fad1c80e9d649a47d39052427fee	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9ef1bac14efd6da7591b0702702b93bdfa77c79fdfc410306bfc6da029e86b16f43378dd2310097b5ba5e94b1d2dcf3d4f7c6070aa0411906f53f5f6862177d0	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x955941a4f1fd4c083354d4e6816ce0e3fb936b11131e296d52193acb05b33394415d8e4a7177dc7a5a69699afcc4d26a275d5e4200917742fa416da2f5d53550	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580769306000000	1581374106000000	1643841306000000	1675377306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3d7a3640d43f5f7d25cb30fca2ca1ea04abd634f73e5aadb1ae2aff849562ccd1691b7725396d24581dafa7417d16308f5d32ac91f0dd554975c2522a2573793	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581373806000000	1581978606000000	1644445806000000	1675981806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc67ee219ba4504abef816bd35100be234d077699ce2b2bebfd336a2e3e89db817c178ce4c0ef9ac64437eb60ef3a13fff58699c729d898f4f93373f0937209da	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581978306000000	1582583106000000	1645050306000000	1676586306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf5e5f5c3cc36afbfb60252857533e03a637e903004690eeb383cfd3cca279985e3d49fb3475adca5a9ae9d49587e4977e0d9f8c6cb4f1f63a569d9206b7a18ba	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1582582806000000	1583187606000000	1645654806000000	1677190806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x187d3d420168e01519ac6aa5cfe4823cc856d7cbb83ee9d15ff789c709b3f178d5cc7a18bc2d2e18de8df4de1aa0b36842d0e7f378e24482cb65202b4f93ed78	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583187306000000	1583792106000000	1646259306000000	1677795306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x51683506f9501f94283e1d64f53898efd22466b0ada817b4e1f1786a6cd0b1e3120e87597295768e5bee14fb10ddd3fc92f2b1b32326d6e029cddad87b8b090c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583791806000000	1584396606000000	1646863806000000	1678399806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc6f10d5b2cc7c2933b84ef78066cad7ef35cdf8e838730098300ec0a5a34d1fd16bf6cde107cd28b9fe76ec77c58fc09c5282cccaa0af301d77c93953aa55621	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1584396306000000	1585001106000000	1647468306000000	1679004306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x46eaefbd3b9414c85a8021c0ec1a7b05c94aaa43eafecc2c5044e55e5467166b4d832e64959a6765a444ce7f1c0da0cffae86b639519d4fe83e63a9d4bd03549	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585000806000000	1585605606000000	1648072806000000	1679608806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x810e4c16f664cc7e267ca5c7ae6d151e4413b801b6e03f846d52736812250587efc2cbb705f307cb877f01655bc5347611340be04826b4b2d2d8ed880c208c20	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585605306000000	1586210106000000	1648677306000000	1680213306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x97ef591d1b1cf18239aa081859ca9ae93bf29b0bd65433004dfff35472ecd33be2ba35320c37c72d358193a0b986d9c4187c5b337a2f4dc9b9fb2d14d9247228	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586209806000000	1586814606000000	1649281806000000	1680817806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9c568fd86e9ad7216c0fc2b2a217057f1afe9517c07ecdd9cc75fa75febbac1046a6ef7c52b246da7664746cca1018ee93ae3ee339d7f006b4f8d4747ad41a59	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586814306000000	1587419106000000	1649886306000000	1681422306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x878974304b0aa7c242a30d8ba454b09395cf071e26255adbd7bc2e85228e72ae577d19213712bcdb58831e2a1d6800dddd1c25bafa07abdb9700e928d4bdda05	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1587418806000000	1588023606000000	1650490806000000	1682026806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbb8145c33e5d78c8b2d092e1b4a8c632e11f161fb107edcc030f5e2e26b27114660cd94624f2f541386982b20d549deca28b172532b4d3ee2deba162391aa3f3	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588023306000000	1588628106000000	1651095306000000	1682631306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e1dabfa36eb55a875f7bcecef26724362962e0b26d4823f6baf72df8af611849ad28554e78f8187b53fb69c0f0bdba7e3bf377ddbc55543c89cb8d4739782e9	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588627806000000	1589232606000000	1651699806000000	1683235806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8ece46082776579c5f66e476d843294f61613fdaed2614a8601d6ff7eee1849fbc4b82ad85391a97b47998524ee44d8c523ebb405b8d0ea479fac25508bafd75	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589232306000000	1589837106000000	1652304306000000	1683840306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3a28b72222a0e834a8806aa3ebb255a00ea3d7a06022214d668a31a20d41ddae21f60525636031f9204a92e0778b90bb9922406941f0b8efea981f5a1919671c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589836806000000	1590441606000000	1652908806000000	1684444806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x540a0600cf56c0c22f88c9e21e291f1025144f38687e8535227022fada77c1f794589b6fbead8424ff2c09b7a9a0dfb993d63ac4600ad2b4a75a81872fab771d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1590441306000000	1591046106000000	1653513306000000	1685049306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdb48df1b7202028757042ec3f2826574c2c94bd201544472613a97aeb6bf41165b70725fac0e05cc4ffa94539cb1252371ce82b83a5c7ec63ea1ed95f7554734	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591045806000000	1591650606000000	1654117806000000	1685653806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1a47bc10c27c6f7ceec83f417c3c7064144b00932dfa26e3398a36e8ce7927f47d5954edc36a12702fa5aded48eeeebe7eaaf1f02cb9aead1c3dc17443ee4b82	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591650306000000	1592255106000000	1654722306000000	1686258306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe8fad9b2052da0fb6282d92acccf19e98af56cd6a1f9c086f6a78d836bbfaa51196b84a804cacf76707ae198a81210063ab2341e201a5b6e73e440e98581366b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592254806000000	1592859606000000	1655326806000000	1686862806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd4c959cc13c517a8b18c08ef42f7774defac7c8afcb63fadc56e03bf4335f4846c6ed7ef35af47189d5e2d8cfc2759406349bef77215bba3f62a65766a76d267	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592859306000000	1593464106000000	1655931306000000	1687467306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6fdd5c0880473493961054437454d46dbfea91fb8c3fe7c4c683c093e75c9be94d5c9575de9759d5f6c222d53ccf3f8f8eb074703f9f4ba03216bc6f7f20a045	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1593463806000000	1594068606000000	1656535806000000	1688071806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xecd69a02d9eb4773e64e5565e09ba93a9ca765b424b5571e9d2f2cff5521a412e2635237d1b5981152fa875ca9d41b058ea1bc477afd8c469f6d9b9646a4e47d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594068306000000	1594673106000000	1657140306000000	1688676306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x60d76172ffac1ef27694c6f0274ba581f128b1d85b675a832773d81c1118845f06aeeeb748628145a2dac31b13632d6dd4147c796f5ad5fa336fdfdd5b046d39	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594672806000000	1595277606000000	1657744806000000	1689280806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9f96c874e2900335a09b0d3f32546ac5f17b8f820deca6323c29db4347ebda753ad61001ae527c3510e25e8f74877ec6969b6adfab50add636fdb08fb9bbddd8	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595277306000000	1595882106000000	1658349306000000	1689885306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1eb35077a0b3c5181387ab87a9a7fbcde4e68d541bc48ea27191ecebf966ef9b86a6e5985e32bec7d6cd8ba380ce6ab271db416a98c6abe328c950a5d0b46ae4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595881806000000	1596486606000000	1658953806000000	1690489806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfc39a2e580b4862b0f30a379f5d4554f530846b92b14021919b88ef6089e6bd573a5a42bfdd43e7a99b65ffb144c5826ae0c0ba359211af8aa6f91c121ec5533	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1596486306000000	1597091106000000	1659558306000000	1691094306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x53c16b4cdb298580d0dafdef53b56c03d080227447b9d9118b9abaea3d65523d825af56157f4679856c25088b6f35867cc821045fc18eee3e404c30f49e0294e	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1597090806000000	1597695606000000	1660162806000000	1691698806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x80fb0cf527402cf880c9872084309cf822442266853101e6fba250cbe7d599e3e47f1355522ca0cc2d6aacdfc2588e158eb4edd770e697ebb32d44a580551f0e	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d6b0baff05b0c6948f95f1413a4fcc0e99355a727e2f324781e58d8e42f6d23d927777d913b4e08d3c04c112a7284e8ddc1e70b5561cbb450a4ec72ed5478a8	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578955806000000	1579560606000000	1642027806000000	1673563806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x413ef7dde28a92e5a07c6a5d4bef7f7c92600b150c8e06be6814f24bcf96c6bd7db06f6cbbc8dd92822aa727d4f68c9aae5cfd1272f874cc900ec7c942ac6363	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd769523d2c04636796f19132afd6426fa751082a85f496ba40383221845dc61fcb124f7bb9580cb0e7f86a941c7322466ba723f7717c324e8da04138f008dcb1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f060897924f88104d02e1907c2812c462f363163843ffded2901f48181d8e1995f4153e5a24f9829f28dc71ade37618b29d0f7702242d789f99674f830ee912	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580769306000000	1581374106000000	1643841306000000	1675377306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaabc4f9bb2f73852357c25fc820f31344d2755dd4029baa4054eaf8c8830ef68e85b491cfecac47fcf02cf7dc0519d2d265919633bfeb1aa0d6ae6d9c765fb8d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581373806000000	1581978606000000	1644445806000000	1675981806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xacd37ee3951339a3deeda527a2398ed9b13b49b12816fb7c853e3eef434be1d8d89a3577de291000e41dd747f054bce46eba187a26e39d199b4fca37ed18c5ad	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581978306000000	1582583106000000	1645050306000000	1676586306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x024cedca9d474df4ce91e50ac3857d5b1f9a1935a23e75699cdf3d0ef8f97fec5bde9dbd610f943e3cb5b29e0dc9fafe6e9d9ed46efe70d4501c7bebc03141b1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1582582806000000	1583187606000000	1645654806000000	1677190806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a94d9e30fb95634f3986f1237900645937cadfbd59f3a41293c858ca9546e8d07b05f58aca23dfb2065a80ca9264810cd93fdf3a9cf93f65f34034a3c9ea29b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583187306000000	1583792106000000	1646259306000000	1677795306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf4dc2ce841c6921c6ddc80f2171643b5a9b7093247a504f169f6888a706c86af117d9ab10d0464fbe4d80476c9e7b90de0e88a21a82653e5da3125d54c923b25	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583791806000000	1584396606000000	1646863806000000	1678399806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5863263a8b4b16474258e42b15e697e46dc4fbc60f6a35121b4d0a193571b2bac4ab13b7f53815b6558693a0b5eb647faff3d9d17e9cc98c46ab42172c6c91c4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1584396306000000	1585001106000000	1647468306000000	1679004306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c6242d1dee7412212889da4c034417bde34c09c3cf375fc5360863ba4351121f2b266e62fc5215246af46dc159e3f14ca411cc6e1c8d4c269acea15a15d62fb	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585000806000000	1585605606000000	1648072806000000	1679608806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x59fcaad5fb7227c35b3904b9a394d6960bbcf0a0b1b6dab9642b1ea3a7dd5305aa173159d6d973eab1645f5660a8b51e07439da57013ae395316436e39257b5e	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585605306000000	1586210106000000	1648677306000000	1680213306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e2421a6347752093cf6c11c6a5b67cb3acecfe4815f9cd1f4d8440e6513af5c40caa451e3aa3d083a1372d701fdbcc9a370a0a50c7130c16477fac5bd9cf7f4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586209806000000	1586814606000000	1649281806000000	1680817806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x50c9f18fe6726b879d8151cce4a11b4af9ea15beb44f66e9284c00fafb5044c6c49de7a493c899b404d173629ac807be2cefd7b78d52dfe1fd5bcc06631878a2	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586814306000000	1587419106000000	1649886306000000	1681422306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7d4a45ad22deb6c1e409253c3e9c2c9a568cbaf1f0856878e33aabb67d2075ac47bc928e5ff12fc4e5315702a2cc3a0dd9f2daf8a75e94e542c2d3b094c97c4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1587418806000000	1588023606000000	1650490806000000	1682026806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2de9c4e2ce0f6c3803f163a05397bc18e0913caa4b5ca07c8f2d3a0ac3abbac4b6b6faad2a6bced20d3422b063fa5ed19610e6ce727d7751a854ba63d2ac27e6	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588023306000000	1588628106000000	1651095306000000	1682631306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e4c006ab93692df8b9b5b1cc7d6527dc9319e555df39aa8f7c37ca658a055121e46426481b286bed2c142d587030ee8c3b5e176e7cb45162caf4858c026b1a3	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588627806000000	1589232606000000	1651699806000000	1683235806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x22a5b40973ed173f198267de4f5627a0f48903047d04a5e4b08d48d961bfe907fd68f65663b02095256f927619d502c88d38febfb4804ed6b222b63d4c18c2e8	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589232306000000	1589837106000000	1652304306000000	1683840306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5a78a1670313b72c6eb51bd2f42ad3947824a6fecb302e2439b591e0e33dbb9017f6a9debc9d37d2a192f9830961a479331fa2ca86d6a91b0cf6586cf9eb4a59	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589836806000000	1590441606000000	1652908806000000	1684444806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf91b62fbdabd1890f4df502b6da3e251f17d816cc5dda9cc4fda40d443e7df213db91a2883d91db28a68c3e9aaff09dcba12442cf9a17e9511d98db6a93f8fbe	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1590441306000000	1591046106000000	1653513306000000	1685049306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d4a8aa301bed817e329e9f9905e227ecdebb26cc1f819103386b74bed40a2955a07df235d8b956a5a15b03759497cf4ca6eed6812e65d1d3219bda2c8de725a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591045806000000	1591650606000000	1654117806000000	1685653806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x601a7c14ba2cb2c5be6e1323b453cd3a6cc5f14f86e3af8fb875562b61a86515f9a061c9745f82ddfe39dd20e0fb80272cc2e509051f01ce72938fed5b0d1030	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591650306000000	1592255106000000	1654722306000000	1686258306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f72d77f1a7a7f93258c3d309a7a6a4feb071dc80646d86786b8431636c1e1fc1977da3748a6fd459a69c5b43ff3bad05200fcb948e559bdbf792bb540144c0b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592254806000000	1592859606000000	1655326806000000	1686862806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x693183cb540f28509f59f413898f41454e9c44b21fbd54e0bcfa72d3c6226feb3c96ce4e2cc0a5da863716135e812bab939d58c9904ffc1f621857f4096c16ac	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592859306000000	1593464106000000	1655931306000000	1687467306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5cd7a3e101b8e583ca9accd8a23bee92596d4f20c3dd7ef88bf5899f36b23f18bcb17311cba4a359dcb2f8c0d5a5bee103aa36f0055b8500d7f0b0ce725a102c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1593463806000000	1594068606000000	1656535806000000	1688071806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x95a25cc7a19c658bf3391658f0c391e38bcbf06be2a6bb9cd417ec2f00306fb113b8886469c31710304a09ed12e53cd1342175c51407574b026ae0c94b785618	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594068306000000	1594673106000000	1657140306000000	1688676306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3b4737bceea5cf6ac5420eca3a52e703688bad771d4f00ba1cd4ebde97539eca462cbc07c8e4c1b0ef2c8a9089d4372d4fc2ec6b6b82651cd46b7eae9cff4e3	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594672806000000	1595277606000000	1657744806000000	1689280806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x980273b1cd85e5f17c78a2dfb3f59cb66b325c19bae702dcda7c9d021b05e10afb36e94fb1b7c81d9a42e0da2fd9be6452dff4625377c1f29b5159f10bed2d99	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595277306000000	1595882106000000	1658349306000000	1689885306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a8e661757191ef61bf70882209e4bf11c440242f70c5c525fa29b3636a5e2f27918950a37c11e2028fce8b3ce9f77e47115663faf263516f81e37e54b207d08	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595881806000000	1596486606000000	1658953806000000	1690489806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7b74c845570572ae45ce372da42f5c376bdac03be94f8115eb27aa8f1ecdb9cd1909c762409ff59d3973f4d10a1f5a20027ef01728b147d4373daa7a187c8ab	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1596486306000000	1597091106000000	1659558306000000	1691094306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcfd4913b23e8cb0255c3c0f1a5ef0781a8f5134d65772ba25f93a32e37dbd77349a6caedc7280715104f166100dce6da11c29df940290ac7559d52967b4b01d5	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1597090806000000	1597695606000000	1660162806000000	1691698806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd5ef5e6015754956d456f963a12dc49d118ac734084e23b92df82fdd896153173a5c568df8c743202efcc9b1ff59a698f58f1434f766fb6710a8adafacf4401a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdb0d92f5b573854274e28813553689564a820db0fb501b67470f194083409dd6deaf7d0c05cf9f959bc0faf62fe0c4f9b0e05f95015a67162ea5aee636626089	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1578955806000000	1579560606000000	1642027806000000	1673563806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd3771706cc8ad8d92f13011397285b54166af93b635e140cc9287b8be5752eed214e7a0dbbae9638ed8052bd39a8ff8891a07578c87a477c8fc5ac497824d09b	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x90b28b4d10ee3aa9b7f68e3421da3f6bfd6d8160a755d3710aa5627ed97dae01c9e2dfce043be63f0d9d6f1deb3fbbdc95d2fb2cf0bf52e870ba78527c212470	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfbe912f7246713012054ece0b1abc508332acb3ea0b585ef1209f9a1fd6081679a3a7a3179e239a6f6ccd750f43d0800955e6a91e2bfafc217386df8590a7978	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1580769306000000	1581374106000000	1643841306000000	1675377306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x046cefcb9567dcf70caa0be1ed074bbe85b4c6f21ddd23822dd9220715ada85651b0fdeae5fda60f7773c350ced308c6c3dd80244b640445da3c6f14d68a0ed4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581373806000000	1581978606000000	1644445806000000	1675981806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd8bfcfb6585f094544fd8057e2ccec2bb26d35b6f1a5d6e5aeb9375f2464ecd51de13c549f9f8bbd2463dac36fcdaa157c9fdc4693b0e4d82d0d76ee44ff39b4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1581978306000000	1582583106000000	1645050306000000	1676586306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x142b05408c68258a46db5b84c162a52c0fd69c805c8d1d9e9df17c798338b1990fbfffa6cb9917dd4eb19403593918946efa9b3b7a5610086499af6b21aadbb0	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1582582806000000	1583187606000000	1645654806000000	1677190806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd678e8c173ff4086d731d8d99a6b02a1364c670c08182c789070b325b806be0e5aa82bb754fbd3321eb54ee10bb2ea0a2786a4d7295197a4baaf102a55c0730c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583187306000000	1583792106000000	1646259306000000	1677795306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x31aac6d14a9f80439d674a8d77b10efdb81d9636c7c57e48c919b5e90332eab5713d49fb6592ca15816ba6d776b8ac87759cb4482924a84af03bd6e9f7bf76ad	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1583791806000000	1584396606000000	1646863806000000	1678399806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5a67377745b3e2da01868da5de0a285454e8155c5961367a4b0ed51d688bfbcd1886d7c7ec671c78e8e4c792520fe8f1b427b7d71708d863d599b14da8b7b80a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1584396306000000	1585001106000000	1647468306000000	1679004306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2c14a42412e22d1f02e4c5ce5b2602022410f4b8c45031ae2c50a706ff6d940a6d479770a864e51528d43b17a52cf098128c0fd191bcf0a1d4cdd9d736fc455a	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585000806000000	1585605606000000	1648072806000000	1679608806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x19cd50b012da51e25cb22c2ea460f80e8f560ce97f283372fb5e0007833fe530c6871e115eb8330560dc67c29fdb8b2df4d3148a438f37f23031eb68bac3bf09	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1585605306000000	1586210106000000	1648677306000000	1680213306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3e19c75740ccc0bdea374e41ed4879cc669f17312fd32cf5dd811abd0a9f17a164562a7404f683eb64e5c60c86c9f3955b61526d9df94cb74acc68e7fe740514	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586209806000000	1586814606000000	1649281806000000	1680817806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0742553f5c5d3df9e6a1e445be95435eb6b47b3a181564b5b7cc377563c34b624c71302832fb62de1ed037c745d755119eb5a0ed1867d66152554c8b3432dee5	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1586814306000000	1587419106000000	1649886306000000	1681422306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6c04213cdd546c474b8c011bb5090253b086600088b1d5a245dd87dc6a61c8379abe0f0e8dfb51fc9771eff525bd82ce827fbca8ff27d82b43f604c1e0b3e888	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1587418806000000	1588023606000000	1650490806000000	1682026806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x200d19b472b0ec761cb6dd9f169adcad1914d4096956778c0c8a4c01e430b832cc54633dd688a0887aaf674f53b9cf36c646f7d40a19eaaafb472a95081a6cec	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588023306000000	1588628106000000	1651095306000000	1682631306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3a5e5f97cf87a0dadd93714196b99d0e843bfa7d49c333a39703d817c5b635666e743e218f819c812077fa19e380601993e8c37ee9ecb460c7ad769028de14a6	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1588627806000000	1589232606000000	1651699806000000	1683235806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf7f1b8db0d64ec78e3a5d8a3ca3ae5eea8101a4b91f1131213f3f9d99f08d2cda07cdc8483566c5d6a8fc11d4dc3917364a52f25f86ffe7541ce80990116aa5f	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589232306000000	1589837106000000	1652304306000000	1683840306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x50c4d8b9fa961ea47b3647305e066b94835bf08935807b287c14fc548addeaa7fa4481dffb0457484d497f300c6875e3ff7e34e8bd7387af7958ac00d8a0e0c9	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1589836806000000	1590441606000000	1652908806000000	1684444806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x322583b37bb90dadc2888d3c77ec9b2bb6e423a5ea3d326fd1c7f3ffabbbacf13748b6cde016ea5711ce816848842f397e1c7e1a0a7a06c124701a98f96cbb51	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1590441306000000	1591046106000000	1653513306000000	1685049306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc87eb97768b451a37c20e967c445f436ccb8f98558de1bdf6d2a4aa10749c4fc60a56a8694632c1dba042f003a76ae367ac5933955587005a7f559c0aba0d3f1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591045806000000	1591650606000000	1654117806000000	1685653806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf5a933b6aa14b14cd920a30fc332a63a87c810bb53e8a9aa1fc37a8f09b46cb776a35564eab81b5eb80ac2d9380128c75c8d326e541ac7151fb1262e4e7b9b29	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1591650306000000	1592255106000000	1654722306000000	1686258306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xedb63faaafebf77b6cd220c857e19466f115e39b05249092229e668d3effdc053f899143a41f0f22f333e316918381a122907aacb313123aad7912810e0786c0	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592254806000000	1592859606000000	1655326806000000	1686862806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfc34465afaf526e8bfa2ef71784bb0ffb2d1e7edb84fb0c79172660ddefe92d05807bdeda87a16488c4fc01eacacdc4c34949427251a6565e7040a2fb3c0f5f1	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1592859306000000	1593464106000000	1655931306000000	1687467306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc1b90b1fbe4aa6e45f92f8d16b488f1bdd70e4440c3821f6f8f2cca87184510b54f393b9c7592e86f2774ce3ebcdcaf58e657e80390421e2c6d87e1e28078b28	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1593463806000000	1594068606000000	1656535806000000	1688071806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x67549bb55683f77c2f6e7f299752312f0997380e90e58262820e2f4388fd26db1ea3c612a65b888824452bebc3983a4215a78974efe609803d68bcf9f2b6c4d7	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594068306000000	1594673106000000	1657140306000000	1688676306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0a3693c78f895f19093c5c7aa24397b827cb98bb20995337da9293605d4504ce73570c92a8ec4030c84187f5038062c8d91f74b5ba7ada989c8308c04e735cd4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1594672806000000	1595277606000000	1657744806000000	1689280806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xba5b37d7db61de874c7cd1a4b3f315d56de955e5beb6869ddd32f4a8342c07faa5436211b42cbd8b99f02445c3dc5f0535b00905aedf4d8c0d3612642dd5b22d	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595277306000000	1595882106000000	1658349306000000	1689885306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x72fa4c723eb5e527feee1ea4aead778c478119beab2a636a3f78dbcc0e05a41151c13d88f85706dbe3ebbc63bb671e13c50a7792f907cb14e3d1ff41e1825fb4	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1595881806000000	1596486606000000	1658953806000000	1690489806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5d5d1ddb1bae5042976538da2814d5cec8041cbf546dafdc198df5be13f26d71ac915b220b4d92bb6e402314f7d82d54705ce6cc08c353988356df7fc7f146c7	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1596486306000000	1597091106000000	1659558306000000	1691094306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd4103b531834fdf32c77bbac1487a63e1ef7cda4a0ce4379e1b9defc5df494482baac2a41f70de5605e1601604ff774293bc552112cedf243d2fa158a3b25e3c	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1597090806000000	1597695606000000	1660162806000000	1691698806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1577746806000000	1580166006000000	1640818806000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x3723cde943897a40bd21fa342e4b84b7b4e722a18ba27b7b09ff366e686f59348282721569bf515612ee39541cbc2805fc51bfcb16a864676ae1cd0f7324c302
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-31 00:00:17.326382+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-31 00:00:17.398219+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-31 00:00:17.460647+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-31 00:00:17.523657+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-31 00:00:17.586517+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-31 00:00:17.649323+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-31 00:00:17.711708+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-31 00:00:17.771412+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2019-12-31 00:00:18.193673+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2019-12-31 00:00:18.621526+01
11	pbkdf2_sha256$180000$zM7ZkBx0pV54$yU1cPNvWZtLzMnBdT2GRYcrU9SiZ6e1im4c4MKP4MOY=	\N	f	testuser-u4NBhcNw				f	t	2019-12-31 00:00:20.264729+01
12	pbkdf2_sha256$180000$1DQe562cCDty$8N271g8bZL5bl3dPZoNaXWuUP8C+FUTAyr5flxCIuMA=	\N	f	testuser-PQ2heRYJ				f	t	2019-12-31 00:00:23.260286+01
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
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denomination_revocations (denom_revocations_serial_id, denom_pub_hash, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\xb468d854cc75c3bda251749160103a85039d7f9090e0a0658afe2692a3d97179db4195708461ec30b9e0a0f3e4aa0505132aef2a02336647306838d74bb77373	\\x00800003aeee97f1b6b8e4dc5f1e0301f0ee658edcb533e0f09ee2d79db0bb672bad326735171f887ce282096ba265d07d6c27543503fa383fa0b88f345f974cbfad4c06211d018b420aa32bcb976ca2d20e52d930ac04c9f805bc52ca9d1f7e8d19826e89c4cf71a2bf23a44bc7eed04289f9ccfe9b25d7d335417142895143bba85665010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x6780c42b143611e8d9977223c34197b65403f2384779d8c73b4a7c33f2b1266ed310f46ea9b1e6a1e4b0510a9b2afb961d8d219557c33aecfd3a1747a336c10d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x999b45838354fdcda3ba5adbccd528273acd2415d1d568833619c3094a4b7539edc30f1ac7cb879ff24c27a2eeb63490302fa03a7063ffadd5e9bf28d0b59c0f	\\x00800003da07fd7ee6b093f176b6108bb49411fca53792678ee9e4d0dde425cfe4fa0e63243c54696d51cc3f50419743df16d1486a2e2e94fe7664a49b674670865b702b74cb61c1cf0ed5dc1b449ab9456362ac810db64b17ac4f3b67d795651175eeb614f12a7313d1455234ef4dabd95cdbda69cf9647e3d250482f06a02498c2b543010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf4e5552d17125a103d69999a37a0a163629288c5980135817bcb4fbc2592e6e50a2183f3d5973659103760c55f01b16a99d95a98ead2709cf8eea8bf89121601	1577746806000000	1578351606000000	1640818806000000	1672354806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd73a52d87e71c4a0d223f343c6232e2d8e834a32844b81a3b7e667bf341f855f394b4fff4a1a4f4607f230da510bc17c4fb51ca3a1fe929695fa0ccd870d571c	\\x00800003c2ed81ddaf4a5918f8452204f342acf87d07e1ffd376389eecf5e7328751ff181e5ebd3ae87939b9e4940f1c65c6366d38ff99d3cbd3b01587c55f2e070a0decc70789c69b005edfb7410d5db33cf96061cb84a698125f30bd2d38d450ec657d77ce5a133a24c742bf5a4146cb4860e5c522b61a6998a0190e957b6d9d8eb951010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x04fe9a29d5df2da387c3b8f7d605cf871527cd95f31d8ce060e195e7bea5713205bdde8890a56e33b1a429edf99897b208d170df0d29a7cd8954e093db08f104	1578955806000000	1579560606000000	1642027806000000	1673563806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6761edde947963741f22971e70c610a54fdb12c67542187c639579b33a32770666969540aadc764ac60a7cf77437a13935d202290f8b44ba64cca2ec8847354	\\x00800003b899f799bb3d1ef1b0576b67a574996f2bab6ce6a4ff59fea3b323bf1bcf8d5ce8f915656b9834de9847cc36f8bbd65800bb5a4f82c509022e97981117f3064d1b1b560308781ad0067c13a62e3e121dd5a15f714bc9892c87047dadd88abb5227a442c3efc019d5217550ec65a8891ba9eb25c5c3b040f7a0e26e0ddb1f26b3010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x20337c7bcc5186eb9f14349ba46f7a43b5edb61850c62588d7c46bbe4c8d759aceb1131273221de5f48eae56d797e5c117aec49e608584c2129a9e230eb19a08	1579560306000000	1580165106000000	1642632306000000	1674168306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf52accb0184b419f21673cd79b2e25cd7c0b0b209c40dc6b49577bc2001f248dcb3b72ec25bc99fd005f0da0f1645ebf8d39846372c8e4e2124e8d4b4c4bb1f	\\x00800003c6669477bf55b6f5b69ca46cc6abdae280d68447e91dffe6db65d20b0a9fb95ba07f364951fe5e57a387d6518a1491d9d1efa81bc2896909e0b12526d429987b6b2a9af39c86d1bc2d4f6427a8b13000731308658bacecdb67d20f5d5dc14568a58ed4b651cb8a0032e81a6070cdd972ee0e4dc8cf2750cfb2140846d2ecfa65010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x7b57e4f3e8bcccba91294b56c22cd7e6224d56bf43be3e2030154a128b64f7a348207a16cf1856e962442848ca773b652e7624fa925facaa62e4682f6c771f0d	1578351306000000	1578956106000000	1641423306000000	1672959306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19b1378cc646648ca655f084b262136038369950454e69b0cb8acf10d137ebe58e81b504a545ade1b48f281c9d7e2da88e932fddb311b106d8cc59768b1011f7	\\x00800003996a0c29987018fb4da87adeb529d5b2c779d8406d92a74177e8133e32698a3053e4cf7a99509ec3e9751edd1279752641d1f072dc8191825d4a77ea8284610aa711aa75fa444c15a8b1cabfc9b8dd3db4d159eb4a6cb9197714b37f98a3f311fee9f8ecd3930056778b86889d0d927114dcd67b7e74e0a2b89a1a673c44eb47010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xb9b313e85e84c66eef445c218b4cb4202623449490f05f030a6293f96c697c59df5bc706723eb248e51d3b6ff8d82f3cf5a4cc818ced1792e5e577d49c076001	1580164806000000	1580769606000000	1643236806000000	1674772806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe4a384b29d332e3d9d303aeea2c9fef4a3f19ee33083ac64e0acca3e266f811b9a1f8f05600a195d236a0091016d131dc9250d9d9624603c7996da36655a650	\\x00800003a92830cfbef6007fd903658134ff9422bb43fa4c45eef80e85f4c1f1954ca7e4a6d09220eb8a834907f3a60e1b365f4a0c7bc9cc689466ead9b8eeecf039d30a422b7d75507605e5077f1ab091810d6db88e6ab85632dec2919de9a9120a7233071a6caad91bbef2e991865782a872218c73003b000aacd8f0fc33b0f70668f7010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x28ffc6c6bcf480278f06fd5186e8f999bab0688cc74b2440bf5fb5ffa9d034b87432370949d162dcefec4dcc12dde8497468b7e4aca5dcc6f6eae5da4fec730d	1577746806000000	1578351606000000	1640818806000000	1672354806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9bb0a0edf95d2cbdbd138250be0abaa26b7ada3a6dd35c1f66a71ab4d1046450070fb6a3c78fc2ad14c47567471a149d612f485783ee4c5c311cefad641cf09a	\\x00800003ca8b1a38126b0a5c23b317bd1ed3779c03213e473a86e0592153e97d1f3b8f0b97a42e2c34ccdbf9bfd64c7f3c03d5490a2bb492b6ed1558eb67f69779f78858aa8132bcbd3160ac793089ae2c2ff57a052ba40d5afc2ce1030caa3b738c6aca7ca49312946ab66c59be9005495753560b545b9c2bbc3e5cf113d83df0aeb8d1010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x858fd8723dddc358382a4b68fea48683d08b88c5376f485ae87a7476201d5bd83844b33c96274abeb5f1a23a7d9a6c831113be205bcc9ef2e5182177f18f9705	1578955806000000	1579560606000000	1642027806000000	1673563806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa541d9fc1a18f27e774d2b1d9369b0cf9e37df3c3db27a8feb0245610e027c52b6e003013965b9aebdfe5d260b44f9eab9d30912e99a37941b913d09347872af	\\x00800003d9a182d343319e25aa145d9f6aae9f19c809f6494c190582082d658cb57566a69fce3a3899be0a30548255a8c1aa1086544e0b3ee0bc4d4677a511ab18bbd12f07e7b67ec9f9f262e00d74f10629a6692040b3f6d13de40684d26d406adf786f2a53fed3736d4be04e9338c02ccbfb6d1fc46c2f3a2f390be360a6b1ee23f189010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xe4cb918ff8069ed763a4f53e752c54e091a6ed47eeae7d7413a83a08b8153ef90afedb8b2fc4647f5f36d8d145a4de053a99f04ec94219cfdde99d9c14df560d	1579560306000000	1580165106000000	1642632306000000	1674168306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb66d8b3237a0e4622c32a0745063b5552537c69bff25d37e7ed93dbe53c605d8df70c8a6d9473905a224a8a92d0ed4caadda30f1ea4110c6da4198bf08650e31	\\x00800003cecafcab0acdd9e78465c58d5cc9e775f896581aaf85f90891c92bbdf51e6a7bb6e3ae86f286669082e536f980de06902a9c0543c913846ae2a70c8a3a563b200db239a3cb9918b75673c1802282cbf62c9a0408e16d75c69655b2af3f81b85a342653f0b8fd25cad94b4513b999377178274584bb002e4a511715f681564dd5010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x84ff11a9bca688b121eeedb8e06b6f450d1bf5777c7508b96b6712c4a5d7539d376eb76bb3f252687a87cd9076f8dc96022cb5706c65935317f0229f26eee10b	1578351306000000	1578956106000000	1641423306000000	1672959306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6fedb56536c1f8e8ea796667c0c313138519bb7b1854d0094fe15bacae902675e78a27a6c87738a20aeedfcb1e671f212d89653b62db037786df3a99b8168332	\\x00800003d406e6a64f3dbc09e7f97c9cb85be844c55a98a2cf53ad8f5263166ada8f0086e993a9bdc91a79c22180bc2b213c6761bf1bc8950e843ade49cea3f6c1b04b87cb69b8bf4974f190cbb9532d5849a0af8a5aebe2eabc503f91463448f031c150472ad35a974b1ab7b00354bae317f3974dd09870616cac5d65d585d4198b5d41010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xbb504f91b98147c092888b630db37d979aa372ce06c65b29e0e33a69f6913929402f36653c672885b25ffd2e356a688c1bcd820f6d46b820d5ced20cb56a980d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x689cf12eeab4214b767c5f4a789167bcb8dbddbdf8b18fbe707064bba64162ca099666d3879041aeec6abbe36bb3bf95534c1a12e2b9d1c99d78dce681262172	\\x008000039740ed9ade953df3d5023fca8aa010eca9e7c6e3397a00343aed147b94f43d8dce582d34a6fc933bf885aca91b679a409f18c10de8aaf238f1e3543776bc45a2be6546e6b268820faf9afc97c94f5bbeabed9c525c782fd057ce935a1c46ad65fa3313d0bb2a3b7a15de6a8626444344c6039483425b2bee5088a97bc4182b35010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x2f1d4c26c1818eb46760cc017f56dfa5acfffbbb7268791492ac9f3992ee9618f54a21740701c9b3a595be6ce340c7f7e873997905ab323b6fa8595308977102	1577746806000000	1578351606000000	1640818806000000	1672354806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12c6d2e1a6530cdf6602191aafbbcd211703b1e81bcb386bd9c2561de6a615911f099ed0205680437a2e8b0e44dc6af1f9ca1fe844504d7ce58fba702dd81178	\\x00800003c7ebde00afc3caf1154805fc321fa2c570063286d21c4b97664f1e027bf1911d6f140363da92efdf4791a9bc79d4c3a609e538497e342b57a79e38bf734e2f8ec3df09f8c1ebdc5ab2c555c515726d03f470e93548022798aae783c5b6b39e89ef17fb3ecec6b812751b37a37453f2252345612fe02be503509a2033ee40f333010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xbfdb27fbaac55ddb7b41ef955b1ff4ac6715eeb7123de4d48b3d28a379eccd4caed57c88804317252c1e6b77521b1c6aa9ddb5834d9ec27de284234e9082d305	1578955806000000	1579560606000000	1642027806000000	1673563806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f6a21d5d6d3d2a5dc879dde8b9212e1212a36a4651fd49ca2a41cca6ff0c464258f57e00a6cec13e000b50ed9158d69996e0bb1d294e000681ab7313abc3e75	\\x00800003b03da34e51387a332248cbe89fd9221a23914645aaf1b7bb42a7308ebe72d82a9835cdfa9250d88ed8b9d1b1bc641d579fe8eb582987385b9f750d775ebf94f9a93d8c1cf7740d21fb655489810dd65b9233076821546e9ea4dbfb2d917e24b4db452e95a14142e78a2fa34f51b1d473c6724c36cdc3c86ff5cc85b85326cd9b010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x41e9ab0c684d2dc4e81c4de70f1d4357f4a34e0c16e0207e65e4363c2de4085ae48fc956873a623506d7fdcdb5bd9554151fb0c43cb0ef94c401f709e5569509	1579560306000000	1580165106000000	1642632306000000	1674168306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x69847725a07c82dc2ce4e881019a96d2791152119f0c1bfb93edda25943ffce869667959b4dcc7b9d6548322c0a1456b899c4538e643505eb558dae47b166ea7	\\x00800003e8922c5aeb8167367530bbf6eda5bb749c5fefd177916cfa0e463d5ccda65eb98a1ed17aece8eb08cc54b866121a6df5110ace5c746eb8be23caf800eab8d6d075116fcabf60a39919d6ed84417ab3b646d7c815a7a6801f0b2deef12022beb24ce74f6114ba662eec9729193e4d074a93a2a63b0b151a4e5b1cecc74b4f74f9010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x7e0801a79a11554c8196565218fb36e18b0771e97107f9cec445cced3e4c6ff75c21c5f3d8adf175eee72e3d3e34731eb31a7441b14308ffc8b153743864ee0b	1578351306000000	1578956106000000	1641423306000000	1672959306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5484a9964ad1e7e1161c897ccc2e8a54ee516ff99ba3f40ad35c23613d5c8dd0f4463de960854d2a11b1ac41c8c7916349d2776e9d4f5746e3803f289c2e8340	\\x00800003a0c408a7633668f27a1813e8223ce5f17911f5b15c46536cd18c496e4e09d6baa58285d535fe997aef91d2e6c294ff10cc5d15e29c9f73795ccbae280bccbdae23c8d109ad5f3e9b193368500bdaa47a1b5c80f67be7f08ffe46d69bfa0dc61559b03bcd15cd8da077c90e9ca524f7792c3ebc80144c51890ba0b242d0f1f599010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x82b00a881c0bea9b408ffdf2b538de95d2cd89c3c05e22adfe9cf916fd209ef783b698333bebf863d1e33db21e892a4173436d364f4d2eb2e62e97ca8c45810f	1580164806000000	1580769606000000	1643236806000000	1674772806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe88490a0a4038764bdfd141764e7263f5f55c904a540846dc7b6fec3277de25b29f8dd46762404ae50494156e830394fdbaa50032337d2aba2c09c3706d11efb	\\x00800003c863af5ad6c51ede56474ee61d7cd924910112693be62ed08270991d452529cda75766ad4ff4e4058983de61e91d594664cb52a4c7d7889444601b106e82842d603ec2c3569f2d992d3188aa9957f5cf3433ec46268e904219bfae0a7bdc9f0c081e3a2924e905a8fdd7b6c12591fb54fdb7dc7f9cf01808744aea48f87db405010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x10ad6c7dbb0dde6940e44a340a36bb346743eac0dc2ada482e38d6863fc9f52ef2b521f67f3a4464e0a0386eb49e83b2c0a34ac0a3c9099c7eba8e3d0d38240a	1577746806000000	1578351606000000	1640818806000000	1672354806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x128d32926ab450ef81506bebdddc3fff6751fb8eb4c89d3eb93e81b3e2ca52955d9666f4fcea12c7cb2248e98bba7ae5c8330c70270521986ab91ba0c7e1553a	\\x00800003d207c8bfffbc0397229fd82fef475d055f4039e756bdf98138db7ef6ce39473ca0b05b8bbf71eaf90c87d3cf81c09c581371594f18cd0f736183ec441f5a6b79b526700344c253f356629fc0f4cce5e7343d0f62ba7ae3ae96a7e8302dcb20b03bca081bc27a5bdcf9aeec9268baacbbb20403be81d1d089f5d3040c3ea6abfb010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x54494123226ac712f45d881f125f7a103e68e2e4e4c3c5007e4e5e81fb7823976641ddf275f87fabfff1dd5fc86d04bcac946b0fbc10bb25f752d63c0a119903	1578955806000000	1579560606000000	1642027806000000	1673563806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6333f9e7e670bf30b7fbdbcae33cdc6df82045ab27782a63021d1453fce13dd2f134fd3c7baa9a7d88df861945e061723afab9e8f491a8cc9b2308fa6009aad1	\\x00800003bd23a2f8bfac28ed4574cfa7105c48485b52671c9f4fdf83d0064db636a918fc05ebba6d46d24c72ba5b3a39541f1c99deec4a62ff24eb359fd483e3816203e335b0fa10f4f2b6ee558f22d37fe5de983e6d7ddb0f729cbb6d9e9fb8814e39bd926ffc5e588a86474759c4a680fe341cf90edc945afcfd93f4dde13829154059010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x3ed9f9f59456c7de63ac4601cc7c998e5d764734fc1e4c8f87d7dc1292e1eb472bc43365235f608708b934e2ab1c9271403c1dff797e75876af1d3f9b29ad802	1579560306000000	1580165106000000	1642632306000000	1674168306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xecee586dd62f06d44465b45898fe6dc1ae56379ab1d8621a38dea276f84e27b2d3c72f4e759956869576281ed5e0cd442b580b93dc449186635706c93d440c5e	\\x00800003a3a9175b88997ac0bc558a5b8920096432acd91b3e013fe2d2914b9ca86f75da4fd1ce49559df624ee21b240acb60a533525a8cf5ba6f2d6c8a9d453a8ec78c6d22edd1ec5c33b21d0176ade2ad977438ce70c0de2886d63aa84bab965e996ba640268915b773c5f78a1926333376ca807e4d1a7b999cf0f456af6c9b323f243010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xd84bcccf7bfa992c622bab9ed9f4f489551a6d879b720fe14677ff76350c421f34a327d2818f32c9c757a375cdceca9f29d30dbf0512ec1b98b6a52b437c1c0a	1578351306000000	1578956106000000	1641423306000000	1672959306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ef1bac14efd6da7591b0702702b93bdfa77c79fdfc410306bfc6da029e86b16f43378dd2310097b5ba5e94b1d2dcf3d4f7c6070aa0411906f53f5f6862177d0	\\x00800003c4df107698c9b957a00f54481fd95601d6c72378227d4765a7fef2d688cbc28eea4c2a205e4f04f5b3923b28d62c21361476269ed2b01df0abdb0a9fb82d70239cb4058963e2af4a592e8fa87a6b9afea81249c696ee607c919b1f55f6f12d11f1fb01c446bee2dbb5b334aa3263c5b96162713bb46f48397d3ec3f2bb5ae7b1010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xb5c4691050dec1544537a42ad1dc9b13f565b4c705c7d67bfee5a326c9a419bb4550a31cc54a80243ba9b1d9df652b171f8d085facba6542b6dfcd84b49bcd0f	1580164806000000	1580769606000000	1643236806000000	1674772806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x535ca90a5eeb58999c713ebb1b8de33387f9736bdef584767dcb73d0827ff784075f99f18626b9056a89a3a8a2db0cf88a61fb869f09331528999eeb09579fc6	\\x00800003bdea74eb9da5dc6c00caab28355f484a611ddd7b43abafd2c4b242d72189fab3ca492090962b44978935d1c29ab664af99b1a9376af7fa16d05bf151ab2cf50af546be1d862c6424daae387ca31d5d685b1cb14f37228922226d971563b1d156da22090e3ea901498f485bac5ba2e10bf337b815a26e9174ad72cfc92d8ad1f9010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x792d88a0f8e8c76406c8d956663c0c5e60623331112cbefc55f09b19a0ecaf120410b84b83002f93d7f12a79d333a5130efb18a12c158db681684eb8a1a5ba02	1577746806000000	1578351606000000	1640818806000000	1672354806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc39b32f9cf86031fc57f4d07fd1e3556bf85f8f155ff2d4e748fe790f922bdb14ab70d767428c0ac8021a7528afe7d7b76c94a89b33cd73b7ad2313772b734d4	\\x00800003f30196d2c9a64ee35d83123aa957fcf1e3cffc0bac65b2a1e8e067ff712279ad7b0c672deaa78d955e0c3d5b8d16ced10e1bf20e558abbe76faa840d28f625d167b637a051d2d4edd1795e10c384a01d3780b5f7993db5c80a57a60684b5d6cec999100903daaa1e3f0832b15a4658ee1bfb9aaeec3600eee7d11f29e20da959010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xd60f32f27f5c8f754576cd0befb2d05ea63deac8dd7cc6ce8db2f64eac908b446e4a8f355d9957713fa321d2fe74c4c8bdc8340fa262a27c6b78724a5227d406	1578955806000000	1579560606000000	1642027806000000	1673563806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5d244f9257036d9c0959e71b33339b26aa9dc4995cf07e9948456a85cd319cacc6d09d2fdfa33500fd40494e1b089dd7b472fad1c80e9d649a47d39052427fee	\\x00800003b97f6293877e9f5f328f6004bf7fe22eecada935dfcc84ac640befa655d1ed6446d633f4d3d2c03e5b81524db55056ed26987236b6203d51f955013374fa2de104f27757d0c750f9e09f6fad3e48423fc7fe3ae54e7e5e08fa6176b72d896b62779e4780a79eeaaa1a9b96609b59193ed3f389daef40008399a1b50d865bd43b010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xff06881962d25eb4d8ab7a1b0a3d5f55d8894c0228a6f54a5e073605af88aa04d8ef3b8ea906a39f9ae672c0c249638b8a61f881ab261a9f55108a88696e7105	1579560306000000	1580165106000000	1642632306000000	1674168306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x80710331ef5f0e361dd6e549351f52a2151d06c7983109238cb6a3797abf3b20a98aa42c94769485185b4f67a17a893ec6a5ba57d2bd80aea564ddab0a96808b	\\x00800003d2357238457f6027b739d760e6446f7a5b6afe0dd34394a6eb4e630b43d95130ef6f5713d4a5b6583fd4df667af66754dd867b4805e03a57f037160a888870eaa715a8953d5de821cf3b2e699b7bff9e1bca7f4e7467357f39046e01f110e8471af4a3ef8b50636da4fcb31068d1978ca980fd1bc9ce1829ea0bb007428310cd010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf0a5861606e87e91d9cc4edff9daa84747b7cedb362e31dd6bb4ac4bde489bb9870294932a71d4861b07594c58fab4c2dee713208969bb97f8a715fe475c980a	1578351306000000	1578956106000000	1641423306000000	1672959306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x90b28b4d10ee3aa9b7f68e3421da3f6bfd6d8160a755d3710aa5627ed97dae01c9e2dfce043be63f0d9d6f1deb3fbbdc95d2fb2cf0bf52e870ba78527c212470	\\x00800003d3809dc1a170da65dcef30efd3b4779978e1703927046ca1b95355774e045907802401c04aa00084d398bf5c31f87a5c4d3dd73a5a8c126dd1b8ca8d99a77c20bab24b73e2801b5361a7b88c6c8ce06677e8c2b905f27e19fc24b6d855d9fb805f6562ad7d1c4611f9eafd4d93e2f3a01cb4757b0267ea3a8a0d2bde6e8b1af1010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x851401d3511f2ff614f594f568e3757eddab14ea036e46f6c08b9b4693b974b5e20cd6f32c3a6636e6c071be1c8695ddeb5cd241bdd5e401207a0cc2a53e7301	1580164806000000	1580769606000000	1643236806000000	1674772806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x00800003abfc59845a2c7b77cc036c16eaa05e6fd5c67c7eda1d90665f29a6112f7a08e45cd9ed3443b883099ea0d76d919b745c8a746b89659d06892f3d409b760254c04b60e1583ac496fad73e990a67d1fa7d4f212505f810be47aa2e88e6929d8f63a33769284ef0158bdf382e9087cca0ee6645bda5adf9c7298af02f26d0ab9033010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xbc1afee911932aece9d9a7c088ab299dbd16aef9da9fbfa6cb20e597cb64bdac308fa1621e764c396cf63d15332742daceaf581ca452c6d619ff38dfc0c7e206	1577746806000000	1578351606000000	1640818806000000	1672354806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdb0d92f5b573854274e28813553689564a820db0fb501b67470f194083409dd6deaf7d0c05cf9f959bc0faf62fe0c4f9b0e05f95015a67162ea5aee636626089	\\x00800003d26f38d7118eb623de535ae5cc7129d9933bedda105682005744785f2127459bd41c2ebb7f7139e0ba53441eafa37bbc08553fca1c343d24b2adc6a2fe19e7fd820841d0351dac3773f033b85567f08b29e73e867286fb86292464ee6e5cb306448630cf949d815f981dddd007c539259e847a22fc9afec8900f0390996db2a1010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf959f1bbb93263522c896dd4c4c4aed94f76146107faa8b234eff55d1a9eff4c075b68dc78d9594f2f4cd7fc3fe8e95aa411763612b6310f9b9d8d2807b2f104	1578955806000000	1579560606000000	1642027806000000	1673563806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd3771706cc8ad8d92f13011397285b54166af93b635e140cc9287b8be5752eed214e7a0dbbae9638ed8052bd39a8ff8891a07578c87a477c8fc5ac497824d09b	\\x00800003c30ce74b6f4b6c7ff4a6951354945c9d2944d14eafca7674bf36270b21b1ccbeca196e0caafaef93649a511e8cb154054e1d6a499e73fad114e81d0af06c613e1c1447e618ce96ebf3e0803662b523bbb6d69e5877195222005fe5b12cc5ae1c5e8220199e362225b5d5edfc78fc8912b89415df287932544ca33ffb7ed6bdd1010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xa12a0e412cc535dcbd82b33d40777838284e7df2ed8ac76e8b5b940c0a2f4b92ef3934b3b1ecda3c42c317874806e9278308b37a19c4c70380b5507b37af2d0a	1579560306000000	1580165106000000	1642632306000000	1674168306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd5ef5e6015754956d456f963a12dc49d118ac734084e23b92df82fdd896153173a5c568df8c743202efcc9b1ff59a698f58f1434f766fb6710a8adafacf4401a	\\x008000039bde24b1185cbc544e5e9f44db30802128a4419d71ac1c4cbe9f60207375ee6365a3dbdb285c8ea016343c519c78477a2644145787f713335fa8045aa852ed2c20dec0fa2a7a90b60b04f7aad1fce47cee4c4a2ecf505ae4cb0e189f9c20c2abba2bd431924aa4440072716939e4f12003496f0b3b7b6aef0aeb20a53690a3d1010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf6e0261bdf0753a038464a19a45a5beb80beab0299495a991dbb6eb4170a510aad00cd65183e8b40adadf79b72de4eae2ed5e9b8ecfae1b087d196f51c34bb03	1578351306000000	1578956106000000	1641423306000000	1672959306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd769523d2c04636796f19132afd6426fa751082a85f496ba40383221845dc61fcb124f7bb9580cb0e7f86a941c7322466ba723f7717c324e8da04138f008dcb1	\\x0080000399212336b0dc421a5610dc7997def9089519ec641dfbd28e0637a6b980673ef7a089d874f89d520a123ee4c73f42030eb0aff73187d244b075c72afc36682e4e7625be822646cddea772b25355f8dd9c82cb67f29ad64df8001e17664b8f5c8fffae33371453ac4ecb3255fbbd6e32ecd2548af967e1100ef75c38cca01e18f9010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xa97fc2d63a3f45995e31f61a3a957067fa589548b0df8b681c2f008f339e1633cac885cc578751d3e979653826ae23153fce72b09d21b7893297c1a9f6251b0d	1580164806000000	1580769606000000	1643236806000000	1674772806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x00800003c30fb1859bd82c75a266dccf2c75bc43e9d12f646d9a57f56a58464fbb3fd01957b4438395833818867cefb229d521433e0fa1d0dc47a4fdc2c2f68d09419a5e1a73e160fbce0c0cd7b452a8a0a49f77d8c808a25ae4f47b6b16108bec60e9945e8ec674cab2a60e8768c33daaaaaccb748f75fbe45f4463cd45b579811a9d75010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xa3d6fabf14737107f9f3fb21cd6ff8cda77b9f137170b8f60b2e00bc83a5d74c712c0fed2cbaad09af3391700ea07ce8403271a07c243b47c57f0d51aa20c10e	1577746806000000	1578351606000000	1640818806000000	1672354806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d6b0baff05b0c6948f95f1413a4fcc0e99355a727e2f324781e58d8e42f6d23d927777d913b4e08d3c04c112a7284e8ddc1e70b5561cbb450a4ec72ed5478a8	\\x00800003c1ec346d1bb742992ece398e4369fd2275cfc6b76ce45f67037b20f0c2fc55e12239f0a10646ce3df962045892b34e4a122992fc6d9df7fce437ad65eb93b99b6870de0614fb87eb4c75d4e9948ce106c42678ad442830006dd3ba21e61251a61e28f5dce7cfaab94fe3b9893e55f9a6f52b94e54dc6d20b94071db79f8f1cfd010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x83b7d1beca0f1d639eca55fda762173f0ad29405e6f9cbf416915f3e245a07bb088d93c7b5836081248226ea5f555520faa7258d695c3b0f3e6f36f4ab3ddc00	1578955806000000	1579560606000000	1642027806000000	1673563806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x413ef7dde28a92e5a07c6a5d4bef7f7c92600b150c8e06be6814f24bcf96c6bd7db06f6cbbc8dd92822aa727d4f68c9aae5cfd1272f874cc900ec7c942ac6363	\\x00800003cbceaa325603f2dd4fcaf2900f0d521f2c3bea144e0990d0f7848a3e00a9acad68cd8bc5cef8ba9033f8d299fd3de9231536d3735df74b530725a3c3d1d318e2ff0b790466b9c8220ecea275fab48e997401233dad47d724a770a1df2ecaf7920387bf3e31d588ff40752d385759b4b26d7b8129ce325b2919f3d48fb1925fc3010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xfbcde6fbd2eb98800f9cae629d3d9e0d31b212d8b1a5742904fa11b367db1189aa0de3933c6c1f4c66d1f01197dca41e9b4633173cf7ee4a303e7091a370af07	1579560306000000	1580165106000000	1642632306000000	1674168306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x80fb0cf527402cf880c9872084309cf822442266853101e6fba250cbe7d599e3e47f1355522ca0cc2d6aacdfc2588e158eb4edd770e697ebb32d44a580551f0e	\\x008000039e06f847094d96a5c4c5c316cf9225d589ca8bd4ecc56b1acef1424992f8b6b037a72e5163b7860ba7006e390f2b1f9c3a2cda2cc4107c122bc5b6f4ea6b5c4c32456b65015e1cb2764ec1cda0ec6a40fb11e6932f7816fc71b15720da83e6874112095ae2be0b67b5f4ed348053cdc37b41bdc2b55718a0c2c809aef10ea811010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf9c02627aa0955ddc9795e0aad8e57894a27383546237f9f9bcd397a8dffd4e781d795b91f2dac5f52806da21a025ee4cb1fd6dd717debec4fe7af923785270b	1578351306000000	1578956106000000	1641423306000000	1672959306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x221aff14cf68c10438a093b36d559a0f162eb91aa70566ad452f7d821279d9f525515426247ca25639664fbcaf7c64c9fb3ccac65531920590dfe44937aa06fa	\\x00800003c1ccd0d4a9c6ebd9fb29317d1a3015fc32b9b5a4a2cc2703dc70b812ccf5ec9744dc6cc7a952a667c777212a537614c291b66bb828ae0c26e7c0984f281184d548f132b4215604cb33fe7a5f79e7b36c913d7e18dcd736080960b9a71ccc4a043686b21738c333e4e630023f700bf0d3776ce8cd13fa25222d42d91141e53f8d010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x33f09aae38a939eb6bda4a0821d1562f186b9ca72a59a6b59e96cb5b36aeab0628bfb30e4df5bddd2ec122ec6611d40584ed8e4cb0f2ce1212e72bd241cc4e02	1580164806000000	1580769606000000	1643236806000000	1674772806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x864764cd850c74f7156fcbc0a578f6681614f08e491a3af2019613e469c8bb1b8c5e0cb062f2f834e307ee4255c65a54d83ae2b74aecc7a38de232997e1686d5	\\x00800003c6f59130b77fcd698a12073ef26b1e89a76b173f778a3252caf27d95d0f279f5a226e12c4e65c58862f268cec7bf4b980f1eb3c89067ea6d685c00a875ff230885be1c8442846c425961961cb56507b8ffa7b3209e644000756d320f8eeafa9b0fbb316919309feffa85f45cd9744382e1424f7d1bfd3af0ff8bf0937097ab05010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x344ffb9014b91b04991979763483a7c7f56c2fd18cd615eef802d5f848a6e5a996a45c242b2b337e2fac5cfbe0efa645cc99d395dcf5e9977dedb6d325168e05	1577746806000000	1578351606000000	1640818806000000	1672354806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x09e20e6b01ef85d9b7bb6dd508897838688c7caba908c0a0eb2fbd363ac320057b195e4b71c931b48ef5d3720a56f37aea42cd0ee232e41d6f8a6429a3eaa658	\\x00800003cd7cc1e98fb39e2e72cc94c59983431565193fb7bfa83a3152823f57da5b73f5983bea70983dc81f09f6a81369f3d9af676a4f2a794d46678b1795f187e687da67e24ad9528256fa77857ddb3871c1696eecb094116b4ad0a1691fc6cb2f1edaab2f6f6c37ed6317392b099b3224eff503a1271d4dac45af268e2df75843375d010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x7e7d5954215517cf05f4488d8ec03bde23f15f36faeb7206e97a6809377ec4d33f9660defa16a263b71833e2e39db42b9ed6f09305a0c8f4c91dc0b2c6c24406	1578955806000000	1579560606000000	1642027806000000	1673563806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x154ef02802d2365cf9a2e591a96898f2d519a3ff375825c746a116a891e7405f868f43675b464bb32e19549b26d57ae13ef1af79b2b8d1df143883a3900576bb	\\x00800003c3943ffad2784767d2879b3d422144a241a2d577b9e826aaa3ac2dbc0b9814309530bdf1c4d043a9fd6610f3a0b33e888f9f1e8aa86aa4637c80c3048e910f7806c8a75a6fc7dce5ef2a9865742448c9c1a68749dc8f7ee6ea2238357fadfdbf2202a072441ef9c7d954cd2dd643c812c1a109e96e162cf5fbf1405d598f7e9d010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xa2ccc9c71c374b04166cfab8a909ee12e1313402cad40b13f7dfc09f3093a716b200b0d67319aea5de1eb1a8219ad3d25cd29f6711be526071863e9a36337d00	1579560306000000	1580165106000000	1642632306000000	1674168306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x55438a14f98b816f8fb2db8357fe65485821d7c07e17e33d2576702c4822bb0ad9c376ba465b6dd57100ab963b3ff18268a0ff9cbf047b2f104eedb95519ca55	\\x00800003b6db4eaa94292a66c103c40cf13070c46076dca0a804daa386178e2a9073f6b443c8d9b76e2adcbd687a88b16d6eb58f2f292ad20fe5143695f52baeebec12ad08a6204303b6fa7b982cf522338415c3cced3eabccac62405cf66134bb7a29d391820c78d15565fa0e0d7d6098f2b65d2406f2b4bc97b401bb842f633d7b6bd3010001	\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\x0ed76658c667fcd405e5fb47f6472bc05152ae4f0bc7e0dcd56c4504b81ae1912329629edc7c36f6b74f26d5bd322db744d83f4c49cfecd7659cb7806db14c01	1578351306000000	1578956106000000	1641423306000000	1672959306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	1	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	9000000	\\x2bf1fc2bb3b737fe61b755cb54dd578d63707bada855331ad0cd99c2bc05b47e	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xc5724a885ae43f2fe4d2812b500c9e71d6dec74390a11a132fc05cb0d7a112f695be34315aeb5bc94a2867cb445815430811d6c35db0154323a6f04511d33b04	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0e5ff33df7f0000e9ee3fe4da550000c90d000cdf7f00004a0d000cdf7f0000300d000cdf7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	2	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	9000000	\\x3217321387cf78866eba6c7f2d2d23c280ead3f6176afe07e346116efb0d7282	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xf32de6e6306304192fd22c44503a0862aacc7966713f7125e5da06120ef70f0baf1ac74f6c25a3ddd9fc335396988cafd391ef62ba805ec095acbb26d7907a06	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0e5fffbde7f0000e9ee3fe4da550000c90d00ecde7f00004a0d00ecde7f0000300d00ecde7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	3	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	9000000	\\xc0c634931e25fdfe269e615122fe58a2f3718e626d837389dc666aeab8fc3411	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xb60338925b2caf63a5d5c9ad13e04fdee97d34767fce9849e7a2e56c2aa3600b40a067750c66db7af8b6d2c75abbd35b52de1b54a4e4ecdadcb816cad8d5c801	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e085ff30df7f0000e9ee3fe4da550000c90d00f4de7f00004a0d00f4de7f0000300d00f4de7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	4	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	9000000	\\x0644f9875c80d4bd92e4a226ef36674868331f656afa0e17d60013e657784e75	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x123210b7090d848703139fc34acee4ed91dc9b7558775777a8812cfb1375d42c733bdfa9925f71b0a03b5d262acaca3053abe5de159b22aedc80277b7a3f2b0d	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0957f39df7f0000e9ee3fe4da550000c90d0014df7f00004a0d0014df7f0000300d0014df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	5	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	9000000	\\x351153e4fd3d19c6b894e4dec44d2afe77161d7f9d1ef0493ac17af74f35de4b	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x814627cf7eaddd8b0e15a473acd392a37218f7b223226ed1aa2fa8120c08b5adad00e66c3a893d1b8f558b45cd5e2d11aff1f0a653f7222947bec8cc5db5750c	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0a5087ddf7f0000e9ee3fe4da550000c90d0058df7f00004a0d0058df7f0000300d0058df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	6	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	9000000	\\x4f694bb1a39ad2c48559237652fa9d9497656d1190ecd852894e45ff0b7416c7	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x8fcb7e96dfc13207c1dff914c72e0a7fd2f3a09c82de35f1fc09179d683afb087e372220cdc09d91a9edaa45b697cb01d2c5aac78d325b012821202f06214d04	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0b5887ddf7f0000e9ee3fe4da550000c90d0064df7f00004a0d0064df7f0000300d0064df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	7	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	2	20000000	\\x43a6aee083d3ee697612f674904e4ae18274236466750e09f0e76a1d7649a6ea	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x836423f05dbd3f09b7321612e8f2e09ec4af03c3991daac69929ad5d6aa2ac1b7a0399e6b2bce49f8630bbec0462c8289caa3b37c7fcc81841ccfa242c236c0e	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0050980df7f0000e9ee3fe4da550000c90d0070df7f00004a0d0070df7f0000300d0070df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	8	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	98000000	\\x0cdda8e8ae9903f6e48590ff5b8c107e285ff41cf7e3330dfdf8ecf216e80adb	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x0e2744075acc6923cbefc394c1227ead98cc03787c07a8f21c0aff630420dfaf882413bfabd5fa27c501d0fdfb818c3e80ce4c2c65b8c37a50327c4fc31de50f	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0d57ffbde7f0000e9ee3fe4da550000c90d00f0de7f00004a0d00f0de7f0000300d00f0de7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	9	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	9000000	\\x6275f06eede0bc333821791674da99a919b51d60454b5d14fa62d9d478492fda	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xfceb54c1eab2513ed55780175d2b565989e16787cbbc479aa6753ad694265fce8bbb4290efd57db41b87c53956b69239de22c6886c6df7232474f6efc4562e06	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e085ff38df7f0000e9ee3fe4da550000c90d0018df7f00004a0d0018df7f0000300d0018df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	10	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746821000000	1577747721000000	0	9000000	\\xae7ccfd567a0e57c22a186e24b348da84eeedf84e8446bd7464582a337ecab89	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x6957205fbce09bcf9c4ff5e091edb717b6e592d8954dedcbcf53726db0f949d5e8b755a2992f44c245e90c1f5902bee2f6bc6efcfd03f677c837eb2fad8e8a0b	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0d57f3bdf7f0000e9ee3fe4da550000c90d0024df7f00004a0d0024df7f0000300d0024df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	11	\\x0c0f5ef25218edba85dd831f3e84586799b4e0e5090ed2b34fa439a8c54b6b43bf14032644d976eba79d314265617a8b773d58c17fc0142d3c0109690a8ca5ca	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746825000000	1577747725000000	6	99000000	\\x798ab2df54b18d26c7e76ff6d39d1e3a09c537804358e62de34699d99e93770f	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x179e53934519454a762ee9d7d26f5ea11233a4a14e1d39512882df70853345df814a057dca8605a4b180043dd1cf813490b0456d6079869380bd7f9c312c5704	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0b5887ddf7f0000e9ee3fe4da550000c9450164df7f00004a450164df7f000030450164df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	12	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x4147120219b6e216b2be0cc4fd1d55409e69cdb30c26023041ee799254b98b65	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x2088ae81a88afa69eb51d237e420f839bff04dad55fa4f09bf50e3f306f2a520d05c7ac7b4af584350b959afcde4ef856caab95c8fc952a4216936f9ab037700	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0c5ff5edf7f0000e9ee3fe4da550000c90d0044df7f00004a0d0044df7f0000300d0044df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	13	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x50e27c170bbbc7d545030af0c36111a48735d9fd2ab07494248f63f588bc47dc	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x2e17569b7d37ffb15fc8d92cfe6877cabff4a2c1dbf83917b003a93236ecf7b979b078a5b88ca05d8b3d4da8ebb9a10fbf8d128faf1f76bb66a09af5968ff908	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0050980df7f0000e9ee3fe4da550000c9450170df7f00004a450170df7f000030450170df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	14	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x75da54eddb2a74badbb3666c2db3d7b4d97b4880bccf8291f84924d8f64a7e55	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x66c9c6dd1c7cd3090c25cc7bcf59736ab3eaae8144c6a7c5032724ce30e0e3e33948457ac63012aca60e062fab02a7bcc7382ff5a6f265068c4fa87569ca3d0c	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0e5fffbde7f0000e9ee3fe4da550000c94501ecde7f00004a4501ecde7f0000304501ecde7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	15	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x6daa906243acaac13aefc297dcd448d203d0f3d0b1ed241683c4402b8c9061fc	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x6ec7dc4d431b496870b17f98a743e772e33eea6946550db0dcaf4a65076418adc01ae55aae0a25c51860663b0a9f851e53adcb61ba5653e012497d1da09d9c0a	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0a5087ddf7f0000e9ee3fe4da550000d9450158df7f00005a450158df7f000040450158df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	16	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x15f9c15a8d4a017e62343df05ef1a6951e64b24a163969e4f0f9cc1355dc6c29	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x18a3ec3aa8d1bf0e20ccd759c12db11cf66f47304e31ae0d4d778661141b8e62a17ac19e6dfff6ae065868ffcdcf05ab3dc6c5b77d623b1940040db3187dc300	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0b57f3adf7f0000e9ee3fe4da550000c90d001cdf7f00004a0d001cdf7f0000300d001cdf7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	17	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x418451f141ae53c28f98cbcf84b92897857ceaa06ea072791b70d697140792fd	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x61544a4328699a68e1f9aec01edc4a124e0ed46f8cd4784a22c2659efc7554d6a15aea4b96de04fa8a5d755a1b4939b5ff017bd3ff133122d8ba5bd665487400	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0e5ff3bdf7f0000e9ee3fe4da550000c90d002cdf7f00004a0d002cdf7f0000300d002cdf7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	18	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x8aea23add341b86cf2cd76f3584e92eb7572bce2a0a33ffd5b03b9667f93bcb8	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x9e38ad9c7ae6094ca0db4b4a5a09fbc9d71a3b8465d700de0c60fa755ea43fb740e22da4a187ff3fd268b8e0bbcb3931fb3bd96736842fe6fe79674147822606	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e085ff38df7f0000e9ee3fe4da550000c9450118df7f00004a450118df7f000030450118df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	21	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x7e81c0507d7837b68ad08a844d2bfe5480a5ee13a7eb36b59d0cdac1bd1351a3	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x1ea98e9cea3fe55427bf6cd5f6178b2e9189f61651e7fa51c362da5f8e9110582a2e260d277faadd9bfba0ab4c15c1b9503efc714ade89e9e12018417bd77805	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0a5ff31df7f0000e9ee3fe4da550000c90d00fcde7f00004a0d00fcde7f0000300d00fcde7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	22	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xf883c1b65badf2fb3376effa31ff72f7dd4fd15e023a589a4af17cdf78b7433a	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x8d7cf06d43b10266278ac0d847860e5c68d918f5ff810859b56f46feb0bdf30f13c64183dbef280cac9515627257d1cc6c9c47ecf765251a521006882c86ba0c	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0158980df7f0000e9ee3fe4da550000c90d0078df7f00004a0d0078df7f0000300d0078df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	20	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x30d1ab646204ebeb457f748cb1d88bee419532f6228841d84c5e286d1f318d88	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xa300e20e695785ba1761f597563a16cf9093e65f7ba1239c78feab0ea0ba6e43490af120daee752e691771f2ab2d3737cd7dfb9eab37d306868d1f02f0b68d01	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0b57f32df7f0000e9ee3fe4da550000c90d0008df7f00004a0d0008df7f0000300d0008df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	23	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x599c0535cba807e252f69e51e88ef370b431d77a353df93daa5870aa6bd82521	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xdeb8facea8a7d03934b85e27225dd8d9c364ce30384496fc270cf240cc28be111fef7d98f05fc161729a3d478d5b17c3d55e36d19a4b3b41eaa3122bed6d4a0d	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0d57f33df7f0000e9ee3fe4da550000c90d0010df7f00004a0d0010df7f0000300d0010df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	24	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	92000000	\\xa90e1e2327ba3302059298f3064a2f661e3fbd55f41a3016061a22771f22fd80	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x92c47ff2e184b613391b5fbedf37052e2b54567874c32955c6fea02c0e65169493a0c72a5ab8946d44b2cff3e3c7019c87d49310bfbb39a806efbc65711d9a00	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0b5887ddf7f0000e9ee3fe4da55000039cc0164df7f0000bacb0164df7f0000a0cb0164df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	25	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xd7ff384a2f8111f4cef8053f19bc394a1569197f1b63770bf9064fe22cf053b4	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x8c899462738953c9ec5e5359136914d1e749de940817d634fb9d3f4922fc735297dc0abf789f681cf0ba86368c5665296b0db38b29e8a5452f6bcd73bf3d550e	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0d57f5fdf7f0000e9ee3fe4da550000c90d0050df7f00004a0d0050df7f0000300d0050df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	26	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xf9df322c5455a8d5678ebf99d3fa54d975dea70edab124d200d67c81d0b3f681	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x6aad209315e1512a17fc6fabc16d0ead55c8000cf9615a8be8e77577ffbf083790fc257c0f96164e9475cec38c2c9babbddb31c8532e73c54b99302cd5038b00	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0d57f3bdf7f0000e9ee3fe4da550000c9450124df7f00004a450124df7f000030450124df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	33	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x940bc5d2e379e42e20b2462a3b1c6983af34eb84b18cab89551aa66175ba61c0	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x5c55cf7740567ddd7177feecfeaad7750d5b99ab041ecf3e67de01b3c34d132f3fbf98a12105113b37a2976fec1e7dfa616909d396902af9a13a9e639997e409	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0d57f3bdf7f0000e9ee3fe4da55000039cc0124df7f0000bacb0124df7f0000a0cb0124df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	27	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xb6c67fe1f17625d4dbbfd443fff3683ad7ba06da17d6ac8a786d2a40e30e0fee	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x799a37dadf496b52a514d001cf6c21f851aa3a69635ebe10f952b80af526aa1a9a30bb55cb093e763fc4724dd9da862a051c266623eed9489a97da0102921c04	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0c5ff5edf7f0000e9ee3fe4da550000c9450144df7f00004a450144df7f000030450144df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	28	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xe3e5fbed48a1d621bf9728ad84203e9544f50594fdb4f0dacce132cc35f78032	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x671e2bc1f6fb10596a20f422d9bd5f31ebdb0c7382cd0bdbc2cc0f21b589ad81015f4a1c0b72d37924a4120d8bc164a34a3e204b98c50b65d5d5cb6d68813108	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0a5ff39df7f0000e9ee3fe4da550000c90d0020df7f00004a0d0020df7f0000300d0020df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	29	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\x1e305b23bcce5d8e247e31abd191445027e5444c20a7bca3032c88555f0b8709	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xebe61ab4481d97e95f029916004a4a10216148d924f05735ad4debf4e516b20aae6766bcfa0ee02559c4a44960fc14b2a3134ab8a16a7f951f52c21217210704	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0c5087edf7f0000e9ee3fe4da550000c90d0060df7f00004a0d0060df7f0000300d0060df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	30	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xf07051f49e218da11cf6a962cedb7d818fcb3cb4e118d11e7f521f809d45de89	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x6b48881ac2d4d9b58d4eec0748f14ca38f084001005ddf5798da0d77d658bf9c88c080435cb0efba1ee643e959209a87c0c560704f4003f6097dd348a1ac3106	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0e5ff5fdf7f0000e9ee3fe4da550000c90d004cdf7f00004a0d004cdf7f0000300d004cdf7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	31	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xe26077bc7764119d1f1e834c0bc15dfd928fc72951c20735ae4db7b7fd34816a	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xa0f1f90ed14e2242fd7b692e7ce9f6eb2f0827720ef6a14a2384ae1ad6411de649988b4083b3fc715f3e8f75207bd912490162c2810cac2946c47a9961dbc50b	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0c5ff3adf7f0000e9ee3fe4da550000c90d0028df7f00004a0d0028df7f0000300d0028df7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	32	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xb851f027d8a5a4ca00944fe9426fd89362601b34601664c65031100e648ddc3f	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x75ebfdb90832a6082ace66b05077b496722645c933d3268e574af1611ede7e504eb686b48b56f14249f626e93d803a0c344dbd78cb6f47a593e15dee6adee309	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0a5ff5ddf7f0000e9ee3fe4da550000c90d003cdf7f00004a0d003cdf7f0000300d003cdf7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	34	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xb72a2c932a3e8bf2de668a4055052c83538b90c6d8151ef342ccb6930aa3049c	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x02755e3a0e96137ae55d0320dab94cbc6e56ea42ae5fb21c6f3d2953c95a8b62019329b3b0fb47d870e202bd1a6c81b9bdead646fda92236db6376710cdc7805	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0a5ff5ddf7f0000e9ee3fe4da550000c945013cdf7f00004a45013cdf7f00003045013cdf7f0000
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	19	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	1577746826000000	1577747726000000	0	9000000	\\xb167c9f8e9ee8d816e0d2718787dcd783eac8f8079115e07217cb2501ec68cbf	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x73f1f36c09a6e3e1c380ef191816ad02f535da4f87fc6fc60400c8fb60f7ea62002e63a3f4f6fcdd011f43c148486fcaa182c64bf0d45eee27fef1d30effdf04	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x16d5a881df7f000000000000000000002e469d8101000000e0d57ffbde7f0000e9ee3fe4da550000c94501f0de7f00004a4501f0de7f0000304501f0de7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x2bf1fc2bb3b737fe61b755cb54dd578d63707bada855331ad0cd99c2bc05b47e	0	10000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x08edf9e0f9670c2294899ed4ca677dabd37680fcbc0c6905eb3e6887f4985b58cb12f3856adf7540d514de4a710528d69da1c71e99c22b8c112d8bec443dc30c	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
2	\\x43a6aee083d3ee697612f674904e4ae18274236466750e09f0e76a1d7649a6ea	2	22000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x1078469c671580bc913ff0ac83854d15ca7d2100c844a7d17a2ecb0c9054eb6b27d81dd18415b42a9a532c995273bb2b3156497cd6c30ced9dc06273d992120b	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
3	\\xc0c634931e25fdfe269e615122fe58a2f3718e626d837389dc666aeab8fc3411	0	10000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xb9212977db2c1ba2c30087536a94c8df02eb261b2309d703f4a959ab47b09968e21d644eb622ce7c26f13509a2c36746bc256421bc2b98477a907318363fd703	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
4	\\x3217321387cf78866eba6c7f2d2d23c280ead3f6176afe07e346116efb0d7282	0	10000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x53f3f6bd3eef092d1f6a4d71e03818852ef7e2d21830e003c07bbabee6f5cbbfb86afc7c5f6cbd0a9d6e270767d9f7c7f86581eced9c419bd7d6538d63e88309	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
5	\\x4f694bb1a39ad2c48559237652fa9d9497656d1190ecd852894e45ff0b7416c7	0	10000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xc1dd936719eb2bf7b36b911f6cae1642f44771ae847ce9548fd94fc47b2f770985dcf1fe3ea7cc4d304b42c4946c1a2fe3210af0a192b24ba9aae78a4200c70e	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
6	\\x0644f9875c80d4bd92e4a226ef36674868331f656afa0e17d60013e657784e75	0	10000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xe10054ac9cb2be84d6cd308e9e1408744de0f16013e94902d88ad733ee76676f322a5d454aae03567d9b5ae19cea110512b20a3d7c5c4d906cc248fafe5edc0b	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
7	\\x351153e4fd3d19c6b894e4dec44d2afe77161d7f9d1ef0493ac17af74f35de4b	0	10000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x462075471a74cb4a44117fcf8fc2902b5bd5b5c382ccb38b054f0ef58a859b1fe7b828313a26ebcaad8267220fcba4f100664da527ad6718f49c8caa368c9c03	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
8	\\x0cdda8e8ae9903f6e48590ff5b8c107e285ff41cf7e3330dfdf8ecf216e80adb	1	0	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x87921f815ca45fdf84d85e90ee83c588fb45bd0249accd079f90fc0ee7592466703a40270cd5f671cd00663e1993c7e1f88bae9c044ef741eddef553e83cf208	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
9	\\x6275f06eede0bc333821791674da99a919b51d60454b5d14fa62d9d478492fda	0	10000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x0e8b32b3ff54cdbd00adc403df802b9be5c93182b21e4bc6863b5672d13d7949c5ece2bbf19e533b4970b3d7f7628e91b30796c0067a20d3ea710268b6405a01	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
10	\\xae7ccfd567a0e57c22a186e24b348da84eeedf84e8446bd7464582a337ecab89	0	10000000	1577746821000000	1577747721000000	1577747721000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x19e2e30624bcf3cc452853887aeefa1f5e1d6bce85d605b36b6ac6251f448521d83b86810a76e0b022351cabc3048a11e6c247ce5e32c167c6ed09c38998710a	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
11	\\x798ab2df54b18d26c7e76ff6d39d1e3a09c537804358e62de34699d99e93770f	7	0	1577746825000000	1577747725000000	1577747725000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x0c0f5ef25218edba85dd831f3e84586799b4e0e5090ed2b34fa439a8c54b6b43bf14032644d976eba79d314265617a8b773d58c17fc0142d3c0109690a8ca5ca	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x1c1d2d0b1049f0cf11507ed8e172418eef9240fb64b1ea816b2410f02d648eaaf8bd9c349be5071655fa5adf39a25ad2917d4bbc2f51cd7a329c7604865e5e0d	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
12	\\x4147120219b6e216b2be0cc4fd1d55409e69cdb30c26023041ee799254b98b65	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xfbae90033a631e8712746ed53964259f0a330a6f04a26e37edb9faae84f82b2ad03ebef2a7dcf7dcfafb2776a1f1b266da26092d4d52cc03a71ecf0278ad3602	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
13	\\x1e305b23bcce5d8e247e31abd191445027e5444c20a7bca3032c88555f0b8709	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x4112edde507f908cb3dc60deadcfac26f2975f74874cfa8789c4a686d65308b29c3631eab693dceecdfacd055dbd85a244fc0a4ddaa1e0ce45c8d68692d1fb06	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
14	\\x6daa906243acaac13aefc297dcd448d203d0f3d0b1ed241683c4402b8c9061fc	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x3f22b23c6872d64fdca4265dda2dc1baaf14ac1fc046b03669416671528c939b742f439e050058ad7881a145aa6f8b1388fa8f2478460f0de480dfe35a8bfa0d	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
15	\\x30d1ab646204ebeb457f748cb1d88bee419532f6228841d84c5e286d1f318d88	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xd80e4075b61db1901a7f294a0d16d58b82d72772d4256675c74945a854c00bf543b67a93b7465bc561dae1d58facf7df9f357b3d40680f4f1963ac070881cc0c	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
16	\\x7e81c0507d7837b68ad08a844d2bfe5480a5ee13a7eb36b59d0cdac1bd1351a3	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x42e48fbdbfd954bcf3b76708891d586163f8182cdc194c853cdededb79f847d06657c9c5e77312e4a7ca1af67daf45fca3dd438fb068e0ec19455c56c1b2370d	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
17	\\x50e27c170bbbc7d545030af0c36111a48735d9fd2ab07494248f63f588bc47dc	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xe12b38fdd4efb7c55b59fa954d547ecde9a8b21d40f10806b9946b8b8e4ae03ed4564b7b09cc4c1b7401e2006508f624041d44d339272f6da13831cf8017660f	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
18	\\xb851f027d8a5a4ca00944fe9426fd89362601b34601664c65031100e648ddc3f	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xb79384b9e4fe2c243fb76b35186d5570dec7cbe2e4d0e194490f2ec7538a2cd27eac90c071a7108da9c12aef86e63ad49a9a98e6d4e13192c1ecee7171a6bf0d	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
19	\\xa90e1e2327ba3302059298f3064a2f661e3fbd55f41a3016061a22771f22fd80	0	93000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x7d087faae9131834e37d69b806dae3d878173f02f8b88c951c9268dbf930de48a8971d60e8271140d3feacf37525a96b686d03783aa5992ee5193042ddb88108	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
20	\\x75da54eddb2a74badbb3666c2db3d7b4d97b4880bccf8291f84924d8f64a7e55	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x476e6c4c48b143d5db19a1466638620498187f91270be4789858b2c3258d4394c3ed85462a6b50fb2a30600bb16e9ae330db546473e4cdf28eee951ab95ccb09	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
21	\\x8aea23add341b86cf2cd76f3584e92eb7572bce2a0a33ffd5b03b9667f93bcb8	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xf5f4484b4e96e3e69ba7f5d3a74f252a0ad8c5a6f48393ac4ae30034dce3173bda0d744c920d48be7e7553ccc01aecc59afe50853229889b1881256e997e4b05	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
22	\\xb167c9f8e9ee8d816e0d2718787dcd783eac8f8079115e07217cb2501ec68cbf	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xeb23c8ecb4fc1e108a430c09da0d88c6af6fe51dc80a5fa410676b47a39e29eeb43ec5a49a6f5c7b2023590f05dfff30f0adb44b886e31cc67a8ca00778b2700	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
23	\\xb6c67fe1f17625d4dbbfd443fff3683ad7ba06da17d6ac8a786d2a40e30e0fee	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x2a88336e5fffe2dd79e23f3180cde989d8bb2c52653622addd16d65373fd295121de072376a783463f0586035a64aa85114109b1537118fa7474592fe85b9e05	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
24	\\x599c0535cba807e252f69e51e88ef370b431d77a353df93daa5870aa6bd82521	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x208973d4dfada076f7e413c356e53c24b33bf0c7f88e4b5fc55a7724bdb9e7c23c3bff10de51aa7499b0760bd653a1b235611f0d3148e64e91b5362dc5c99d07	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
25	\\x418451f141ae53c28f98cbcf84b92897857ceaa06ea072791b70d697140792fd	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x633787ba13caf79884adee197ff89d88d9068cf1c063c0968c2a486d39503e515c821d72a4c78d8b3c2f9284f04e1c41c72415b7c6512497637d0245ea86d10b	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
26	\\xe26077bc7764119d1f1e834c0bc15dfd928fc72951c20735ae4db7b7fd34816a	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x517e53767218fb5808dd4f67f33cb45747488ccc8fbb5cf4c4c9e18db134a7d453131bafcc73860a62642eb9727e1678990b1fbf45b5972231f00d89a37ab704	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
27	\\xf07051f49e218da11cf6a962cedb7d818fcb3cb4e118d11e7f521f809d45de89	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x66d6bc5a2c5e04add81376471dabe281298c2380d9151461e9793d8270239e1e54020fad5b0c7557ad5f76c91d23f94df7be1cba2f7163ca7040a6a356a69601	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
28	\\xf9df322c5455a8d5678ebf99d3fa54d975dea70edab124d200d67c81d0b3f681	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x7478a40f63b131378d2ce956fe16315bcb48a080d288b6411964ab81ff56cf30d14685b453a05bdbc586160717672bcd5276a954a84e874a7e45f290216d2902	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
29	\\xe3e5fbed48a1d621bf9728ad84203e9544f50594fdb4f0dacce132cc35f78032	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x7f19114e6eff60b02397ff403de54813a0d38a4561534a3d16119ecab8cdd110994ac57090f96b1b30f2a524d788c8c40735c4b4ba2383118eef6af65c4e1607	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
30	\\x15f9c15a8d4a017e62343df05ef1a6951e64b24a163969e4f0f9cc1355dc6c29	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x9bbf19d178ae726b1cbef11e9d8a08061d068221c6a3640aff2add1b04b9214284278d67c4a579c3eacbb08597990d740eee0c87fb3bd77bad3a543e88ba4505	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
31	\\xf883c1b65badf2fb3376effa31ff72f7dd4fd15e023a589a4af17cdf78b7433a	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xde6150af7db812c3e2b98ac845c6b347f5f37b20587bfa9e7491dd355a4555052bc71aebd36ce1cba043b77a708dc871dbfada07286e246c045ced62820a6107	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
32	\\xd7ff384a2f8111f4cef8053f19bc394a1569197f1b63770bf9064fe22cf053b4	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xc4f97eb06446882f6654290740491862e837b4227d33e77abf87500be88a10f3f65054025b11212cdcaf6de7ab0a9531e51940782b87b60b04402f430dc8b707	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
33	\\xb72a2c932a3e8bf2de668a4055052c83538b90c6d8151ef342ccb6930aa3049c	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\xa0e651dc91c0edc02f32c3f21655a478d092de9b3b9537bde74623dc93a0ebf61649b091d59634bea60123a50c180e5046085169af86321861ed2aa7b98ad50e	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
34	\\x940bc5d2e379e42e20b2462a3b1c6983af34eb84b18cab89551aa66175ba61c0	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x2936584ff40ad1a5219311aa3296e5c80fa26373e338e0b7522bc5742fbf81b04c1721086106e0f80be05bf39dcab793a5eb47fee74dff2bb56cfd59ccd9e851	\\x7822864620ef338a14c305bd8c763363e268bc8df624a07f4fa2f96d7608f9e7af8846e0c00ee61cc18d9b9ec4640634224e652ab99aa477cee525ff6b516f02	{"url":"payto://x-taler-bank/localhost/42","salt":"TS04P5A9WB1Z0BZD37VHDFM48GYP0C67V6HDKDT5ZZ36BSPBY1HTWK69YAXS2SDYXW0GK7N8EPSDW4XABAZ5FRKQWFREK3RSW7NCJG8"}	f	f
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
1	contenttypes	0001_initial	2019-12-31 00:00:17.111932+01
2	auth	0001_initial	2019-12-31 00:00:17.135519+01
3	app	0001_initial	2019-12-31 00:00:17.17737+01
4	contenttypes	0002_remove_content_type_name	2019-12-31 00:00:17.198839+01
5	auth	0002_alter_permission_name_max_length	2019-12-31 00:00:17.202296+01
6	auth	0003_alter_user_email_max_length	2019-12-31 00:00:17.20814+01
7	auth	0004_alter_user_username_opts	2019-12-31 00:00:17.213922+01
8	auth	0005_alter_user_last_login_null	2019-12-31 00:00:17.219952+01
9	auth	0006_require_contenttypes_0002	2019-12-31 00:00:17.221275+01
10	auth	0007_alter_validators_add_error_messages	2019-12-31 00:00:17.226591+01
11	auth	0008_alter_user_username_max_length	2019-12-31 00:00:17.234724+01
12	auth	0009_alter_user_last_name_max_length	2019-12-31 00:00:17.243287+01
13	auth	0010_alter_group_name_max_length	2019-12-31 00:00:17.250204+01
14	auth	0011_update_proxy_permissions	2019-12-31 00:00:17.2577+01
15	sessions	0001_initial	2019-12-31 00:00:17.261863+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x7069f2909fb9ae843b9518d9530a6ceb3d8a576f8e7714a3a8329b988d8a8e0041db0e6b721b16d1a5fc2bba5bfbb886903c69a5ddacb5bdf4954a9e15bc130a
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x91aab0d3fdf1b75dd149c2f0f969ade01814ca4652f819c7fa76f6486419b07f3a8074f133515b8a6b6e93b9db149200f744d6e91ea54a9ec26e9bd43a3fd40f
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\xaf470806c3e3071aab029afff843554f3edad504403a74c53777f4d6b1115fffaaddbc049375038a659583407d80148a9de5f6a5ebb6c72f14fc5fa1e1bde900
\\x2954b655f71846e6922d91d9775b8d28d24e706e3ce847bb33fd5e18cf9c255d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xbebdfde08c811ff615435947ec5f3de607dc5888024b6c0a7797819c96267cdb99277092ff24a3b13e4d840ffc7e25bd3b9bb828cf39ab8ab9639372ddbe9103
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x2bf1fc2bb3b737fe61b755cb54dd578d63707bada855331ad0cd99c2bc05b47e	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x89920b3390e5a81f066283f09bfb3bd4486c7c5b0f28db2b4bbbe75c60196c0bea2606f2b395b695a552a9b26ad172d8b2a9b8d944f4b9800b8326b57c1abb88f326b2a051425df3c9c5502cfd90e12c3a710a36011d7895b991f3034805752abfae96172888330f1d17395fe335af36a6697595ac0a8f5b28a062e8ad1351fd
\\x43a6aee083d3ee697612f674904e4ae18274236466750e09f0e76a1d7649a6ea	\\x864764cd850c74f7156fcbc0a578f6681614f08e491a3af2019613e469c8bb1b8c5e0cb062f2f834e307ee4255c65a54d83ae2b74aecc7a38de232997e1686d5	\\x48a7e5b93cfa371affe9ec0b185b4776941c4cc08d1020a0639cd96558bdaaff3c98d2195aed297db97cc8b129bf0ba92274898c3ab62a755c2f44c43003fe3b546d7f09d849f90ff852d5083be0f35b8466480c7141c0387333ca02bfd2225b9f9ae532815692d03498042ab968110ec94abd21bdc8d90856e9e62a82360d12
\\xc0c634931e25fdfe269e615122fe58a2f3718e626d837389dc666aeab8fc3411	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x3abb3e3d0396401310d9e46c611c902d5869c7bdbd1e3c397eeaddbc5e4c805175313787f71e1c1cf02e74624a196141b30100af598ba76a6e75f52398e5a0e22685cc61cffc2334572784b942d6fd07d5aa9bd775a448b10316b5303f40b8ff0591def16f3c6a3c0bb9f7b6911b7cd357532801bc0ce2d3a6e4556b8318393c
\\x3217321387cf78866eba6c7f2d2d23c280ead3f6176afe07e346116efb0d7282	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xa0bb7c83d506a0e4e483681a74c2a666ce702c01c64cb72bcd8d71b12a2232bb01dec6636b0bc1fb99c2772a0cfab3d2318a78914a550043dfa0b828ad818daeae01218f13a1f0339cb64c98248273deaba67102cc9f4a8a4e29dea5d054c8412509230be6ec1b937e92cf090a229fa202a39c396c096621e282f19a13c411a5
\\x4f694bb1a39ad2c48559237652fa9d9497656d1190ecd852894e45ff0b7416c7	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x92ffaa71636f865032a3778652c929f63272605fc63240bf757e6b374beb10e407588f486ca9d335e2cf46580929f0a86a3cf05c6eb721ae264b7d13bf1526297008595a3335ea0f14be461c0abe6cf85ae171d78df5dce5545acc6193737c76561c067a592e4911443c2b2d6c75c00087fda798260b915ffc35576dd517214d
\\x0644f9875c80d4bd92e4a226ef36674868331f656afa0e17d60013e657784e75	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x9bb3252675c284a5e2b544a87cf4d8fef884b2fcfc540a4243bd2b4ef7dd3f184f03916a10207e589f973d3ccf2f99e1e336322854058e8417011dade8d3ac4a6343c2197b813847d94b62099a65d267d0a348265e24b5ca45e72f609e4405af49fcda3e75e518895cd0397bc46ddc5194189a4938236515abe7a1122cd0636e
\\x0cdda8e8ae9903f6e48590ff5b8c107e285ff41cf7e3330dfdf8ecf216e80adb	\\x535ca90a5eeb58999c713ebb1b8de33387f9736bdef584767dcb73d0827ff784075f99f18626b9056a89a3a8a2db0cf88a61fb869f09331528999eeb09579fc6	\\x96938bfeaf0f038ea198acd70a6f30394a3476b92611c3fe743290a49a566a4e146801cef90d88e3ad30ec7f1333c468df8d92f86126d64f9457840f5106f7772de8d4694bbc0f2d32c27e4abb58ff6fb0309108d5fa3665e84eadac3911f21258d7bb08112ccd35c9680c2239f865af76d71d9ccc061dd46f3a935a2d8fb6bc
\\x351153e4fd3d19c6b894e4dec44d2afe77161d7f9d1ef0493ac17af74f35de4b	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x7c57fe80cc575360f36d258b3bc4ae2b08ca09be152001e8d4857f9ae5b09fba853dfeaf514e98323dd0821f6aab75c1c2188cafbc130b28206a33c86549fc9c41a812cb2c258dc26b8e24d213f2ebf9ffb0c6d8a1241b64c4c2bdd2f87db684d4649fbdcaee95f49ffb48e2cce32947e10d6aef5ab5bc8a6a2ec0f398e34749
\\xae7ccfd567a0e57c22a186e24b348da84eeedf84e8446bd7464582a337ecab89	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x201186c6079d79f058df7818f2eced47e0d2ccf5f78b197dc9564a9b4b93ce1cc760a14dee525a943424972afc774b35b2e5591070fa8d3c4aec347de9ddfe4b2676c07dbbf2b45be8103e68f9dc6837a15fced27c19843d6f54d4fbf76fb0e45c8201a485a47afefb4f5c35d2df8e29a6a94e4b5101f00cd811b37788f1afd3
\\x6275f06eede0bc333821791674da99a919b51d60454b5d14fa62d9d478492fda	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x6d975ba163c680259f1fbc1dc535a330f4232f46037a37fda5291e8c53365289ab109d24abc94cf7abcad31251399fd62f895d7e46f845ca4535464ae8aedc0eaaf0c12982fcd4c88130556e4f348e43bb00f91c287e0eca944ed4303367c1116d39b26443c5569a2e13deda2d9531462d8918f03b772d57482e36004c94f2cd
\\x798ab2df54b18d26c7e76ff6d39d1e3a09c537804358e62de34699d99e93770f	\\xfe4a384b29d332e3d9d303aeea2c9fef4a3f19ee33083ac64e0acca3e266f811b9a1f8f05600a195d236a0091016d131dc9250d9d9624603c7996da36655a650	\\x20ef1ed9cc0e80e4be47ab92a5ff6b14c187f5563ecf7b67f1cb88afaf9480ed1db057f754ab69e92a67c0ea6127b5926f68dc3f7ce34a2c21cdafeab7aec2b4bf7dcb971eec11b166f7f2bb57928458f34fba1b2674852f311063f6c312f666be81342b8c6842c874c873bd00d58f6962bf9606c4a4c871cffff4a314c21680
\\x1e305b23bcce5d8e247e31abd191445027e5444c20a7bca3032c88555f0b8709	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x72fdca23c27592998d21aed7d44ac55145ccccc0b9ead837122bc87aa91ce36d2f8b8a2f1e3d7dfd368a836661cce385581cba4dcafb90c21e1c8aed3bb2ad445ac7a4a11d9470c1f914b98d07730a2bf0aca1bc2d318807b9e0b4b0c39c699cea526e436951291458052a3c71d5354ec7b8900e623fda1194e770ac7a14e0a4
\\x30d1ab646204ebeb457f748cb1d88bee419532f6228841d84c5e286d1f318d88	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x06638242d28df14ffc7c62c8dbe8229466ea89c7ead472ceea9c166932659e5bc935404f1f059b0499e22582a823cacfb684cba716efdbcba8f9522a1b2bd125d9cf30815c89721321e1b88310001ba4522531cd5547a76100347e53a32e6ff97f34425a871b0a209d81eddcc675a2f857e33af6018c68e32fc94267d5e03fd0
\\x4147120219b6e216b2be0cc4fd1d55409e69cdb30c26023041ee799254b98b65	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x42ea91d108f8e6d496a99d64657a21c9cd58625476643e9688cad30e8aa9438205055f51144b16f0cedea967e31cf8d928342d88a8fdea0741cf98cb625072b6a8ef289804e4b4c188658ff810a24d452c2142470259df385f1ed879c45f740fe8aa32b6f1846c5d25652aef4d8e9d2f4cdc318f35dd172cfc500e097544677d
\\x50e27c170bbbc7d545030af0c36111a48735d9fd2ab07494248f63f588bc47dc	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x3dfb5d250ba91e006dc87415d07ae513386d1921d188d0e2982e906c47ffdb571050acc1862734cb2d977b5c9d38e4d3e9ae77d86c93cb3a8bb1f816062d33e6939dfd3873b1f662dbc41ccc9cce8e0c33f3dba8503e161d0f2ad53ad6bcda5095bb26e02722e3154c72a04df97ef05a5b0d6598f85483829516a4703f394fc1
\\x599c0535cba807e252f69e51e88ef370b431d77a353df93daa5870aa6bd82521	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x2e8273c89224ef88fa6040cfd9049cfecbe9ff00ff712c962649b16de304d020c706adb3e407b4c291a6ada4233a247e3c5faa1acde438cc10122c6fa20873db16b1e470b9b6330cebc479db47d9d13d7d74603a5c1b99d2bc429f5e68f3ca7d70543fba4f98cea4f4224a5d77d431371ddd28a1062352c5ceb4c47846ba261f
\\x418451f141ae53c28f98cbcf84b92897857ceaa06ea072791b70d697140792fd	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x490802b6c0f837d335570873235ed5d53d243dd9fd3b59c370c149bd709ecd71877e0bfd207f858d9c3ecb43273b09dcfc3f69463a6f91d7aa914d23df07bdc6f2a4a46e592a761fafa0af3f7908433b785f0befdb43e3c5d32ef69a9a7acbbcbaa62ae1fb9877a77302f90321a180954a179b8a6975b592cca419886eb4592c
\\x6daa906243acaac13aefc297dcd448d203d0f3d0b1ed241683c4402b8c9061fc	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x4341c38163a024fc30b0dc553f0c92894e0ff1a4410ddf226833f1a8a3dcf333d4f117d567b2c288889319912f6717041e7c428bbb573345e22473b852d10a40217e050d6028dc07c4b5a7142563e3b5b7cff2c8157abc4875520994baa51566a29dcbfd9419c863d301d532b8dd1540d2638ec340689ed3f0ecb8587ef3c39d
\\x8aea23add341b86cf2cd76f3584e92eb7572bce2a0a33ffd5b03b9667f93bcb8	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x957221568144dfd54d2ea58143a39ba270d64f890f305d12c5749fd8e9134dc088a654e0dde393974550a4de0a145518d8a9f31382435ebd2b12d71d6d9f1e71de929186e5b4a8c331e7703f8020959b685e2ee5ad744886ea37775e9a77c82e871bc35c7d53b8a36fdeca92466e76b84401e380e79bc7cde2bcedc8bd8470d3
\\x7e81c0507d7837b68ad08a844d2bfe5480a5ee13a7eb36b59d0cdac1bd1351a3	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x8f8a485caf7769ce7455a5023548914a457c60cf63b3f9ea9122a43a60a854c460ec9eb9141d548b4a1ccbd5c78184ce3646918643efde42071d3cf2085ab9a279c72485fc3b85c476401c893a4630eec34cf630d8802ee8c661a833859bfe44c2acfa66d3ce44398e6cbdce85c1ea02828934d2607019f906901051b31420f2
\\xb167c9f8e9ee8d816e0d2718787dcd783eac8f8079115e07217cb2501ec68cbf	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x1325ded0544eb89ca54d84a364e437413e026f96efacdfae7f94d0da786e70463b2f385049dc53bc29505dacf4121cf18a22d05f3784e52f58e89160e1d65a6065cb396a65e3378422867fcdb89b747c4ecafed5445c159464136097d6b402e82ff8d47c7ff1fd5d592541b9b8541dc7db5ba17d13fa9fa0b8a3385c0ad1844a
\\x75da54eddb2a74badbb3666c2db3d7b4d97b4880bccf8291f84924d8f64a7e55	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x5232fe442f6626d6c2bbb4b00e39bd06a124c63b22f89fc8f05a1a7b5fda0bc7b946b7abf93a01938db49edf7b40188807b3c54668833966899a6665fd4ec7a233fce61737ccb704fa59750767878c7d9e916ced46420883915a3dfa9658cc97db89ca1aa882ed7df24a0c4115d8f463a5cfc8f667ba54806a1413196273bc33
\\xb851f027d8a5a4ca00944fe9426fd89362601b34601664c65031100e648ddc3f	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x1868073f0385440119a4f91d61ed919990fbbb2ac5853ce6b3616fe37a4df1665a36d779bc4aa880f901ffeef42d654d44fa85bb704fbf756d7c01c594da11ce74efc2d8839b5ccbcd8479091b2355bdf66c4e46351c4cffe502fb6fa91ae01e7abd0bea75cf932e84fdefbbc0eb7278ca9ff1cef15437de57cd5f2b4a76ec00
\\xe26077bc7764119d1f1e834c0bc15dfd928fc72951c20735ae4db7b7fd34816a	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xb37fc0aa4f5dde966c92355d16235375d8a35a370298a38ad9c5b24bb94ddbaa00b505936e4161b47482efd415a93972c3572ab7503670e2860b92f668606f07c0394fff22b7c3c8b9188c4a69586a5bee74af25af487de0c3afe4a83b7e51a4c76af3b76b3151f765d7b5ebba7c9dc800a833e8cad8c65bbb69b01420b82989
\\xa90e1e2327ba3302059298f3064a2f661e3fbd55f41a3016061a22771f22fd80	\\x999b45838354fdcda3ba5adbccd528273acd2415d1d568833619c3094a4b7539edc30f1ac7cb879ff24c27a2eeb63490302fa03a7063ffadd5e9bf28d0b59c0f	\\x669945a7459d8775e79cd54b779185b1a18128e7f704f15ccf413553e197d3398667cdfee8362f409d03f4c9cdc25bd7d80a8bd29d8088eda82ccf02ad6f308e89d2df344cc46b46db66de33e9aa3e1f52ce493c55818366625c0fee766ac700bc83edfa31f52983467cbb4a577e1f9d955f1d6e03db85a9d10499143f1484c6
\\xb6c67fe1f17625d4dbbfd443fff3683ad7ba06da17d6ac8a786d2a40e30e0fee	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x3a307ac84c05e45f880c958fbdedeb441b06f429e5951ac1c9a0b8b92f195a11a5463ed0ab16a05174f35d2decb19980b060c940a273bec98d78ed4cf7c65971d911e67d53bac0b2b083ae758f5a578f27de8f262cd1b510d29332768c56a6954755dbcb3e52a7a59d7a069b75e90c3324dc39b8c1fb06fc22ac6a2d90d88984
\\xe3e5fbed48a1d621bf9728ad84203e9544f50594fdb4f0dacce132cc35f78032	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x5d271e7415757aa9cb5f0237282d474ffa4b695ff633f45a307c3a92571962b406f3aaf7b002a4d3dc56e5d36ba06156dfd889247bfbe3f2f824225d45a70b9c2641455246c97f7eae0ab281fe3d21ea04a741781e66881d9aa2e301eab8f3c7cda59db0759053668fb1dd8e6607d68956f7f4eab020432f54831a465cdcb6be
\\xf07051f49e218da11cf6a962cedb7d818fcb3cb4e118d11e7f521f809d45de89	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x1806a187189bc54f1e8bbf622f712170c7310532d0f78c7c75634c08ad805c84a3462afce1b068202a6a4dcef1cf389f3d65aefa9f7b658a24ba82eb5d86cdb8fd23812125ca352c4ffc80a2f79951fb52dacf4f1db1305fa2eb5e284f25ccfc0a8263a4365ee1fb397d1217feb65880da55bef84507d62884c40510210086b2
\\xf9df322c5455a8d5678ebf99d3fa54d975dea70edab124d200d67c81d0b3f681	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x7e608488015ade776a26d34718900dcd6ab9e21d91bfef3791b7453e91b7871737eb0db245241acfea7817a58b00267c2194c761c1a973e91daa09d2ebb553bcc9b3780ea60ca5fb04b7588edda957f174ecefe783da07e4169e2151d4a2c239323e0ae3e1b82353d3280228604db22247b2ec68705bc45a542b43f0255b3afc
\\x15f9c15a8d4a017e62343df05ef1a6951e64b24a163969e4f0f9cc1355dc6c29	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x5e31198357d0149864efb20f9e338fc110cc09e2ce6e82d0838bb47044d7d5cf46af38d97120195aee8ad23dc64b658decbd90201061b3efb4dde1d9d63c87fdf4e98f02d0e14b17d391eb27045a43e127ebd4aec858be128de39703e8b54158bffac6fc69e3956f3c3a0ab70e28f09bf439e1693e6b4ed7b0444dfe102bd81c
\\xf883c1b65badf2fb3376effa31ff72f7dd4fd15e023a589a4af17cdf78b7433a	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x1ab8b96cd257b16dd5bfa4cf4b6627c458036b3fdb6bbdc112226d7fd532efb2ee00bc01688f28f55ffcb131ee000b06edab66e9d498944a3abc3fa372432f706134567e1bc3e9bd4795cf4fec25967ada2b3a67624615d8b1df9f3aa3c3cbe961320a7acdbce201747a32a728cf72e7f5f76957cb39c45acfb83c9b0a2854b5
\\xd7ff384a2f8111f4cef8053f19bc394a1569197f1b63770bf9064fe22cf053b4	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xb1c52f8ec53ab13e5ca4c8e145e43aff743cac0746741108cc3f624ff5dbcb4a748ef52b55ae09710b24d491db364848c7708c0f828a32fe61334ecac6b04b536b07c0a0653f2f7b6508d2b41ef32a262f864fe6a44e2ecf229ddf6ed465ee1aee02598a32b7fa2fd70cbec6ee935def2ded7812658213daf4bd2ff0fdcff2f4
\\xb72a2c932a3e8bf2de668a4055052c83538b90c6d8151ef342ccb6930aa3049c	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xad9ebe985f95a8f60f6444fbed16a00d60b718ae870d1325f7f388b7cb85dfdef6870297bed4e55b61a1d1155ccbf1ddc72a40ac31d3d8b8fa42f713e2e0b750a1249b6306fcf7764cbd975adedab068433dd7a428bc630fef30e8d60ba0e4c39a3b359fd2cd8f9b75b9544f9cc9a3b35af8ffb890d21770d6fb3ba9680b1219
\\x940bc5d2e379e42e20b2462a3b1c6983af34eb84b18cab89551aa66175ba61c0	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xa6962b03822e684b1b400c8170f0c4da6f7043bd9091d167616836c213c8bb2f2b29f16eefdb96d529b60058c5346601ae8ea2aec626f8d1dae80a637b1c68b7e3c7dde3f49c238dece3f6f14ff63ac0bd9bf77de18401698a7cbcb9631c1b922a06fcc66a9d33b84bb943eac0af1d86d7da91e5446378203d8c102d34fbdade
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.365-01REEGMTPXSJ2	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c226f726465725f6964223a22323031392e3336352d3031524545474d545058534a32222c2274696d657374616d70223a7b22745f6d73223a313537373734363832313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232313030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2235354142434e465133313345443448444a374351455057443533393457573345374b4d344645534b5a4e4631484b5757344e4547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2235345635474b5a4d314238544138434b32364e3335355135533037543452564b574357453144544a354632513842585a4736523452355331313147474452375231464735515757585341565337394642385a5a45454b465a35455450535a4153534b4359474d38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224456415054563538473537364e4236545a585250334d3435584d39324e5338545947305041344b3657304e47363559474b515930222c226e6f6e6365223a22354b33384450503554454a575a534a41424e564443504b584739344236573657485a4b45444a4430485735324b39344256393530227d	\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	1577746821000000	1	t
2019.365-00883M7PH106G	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732353030307d2c226f726465725f6964223a22323031392e3336352d30303838334d37504831303647222c2274696d657374616d70223a7b22745f6d73223a313537373734363832353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232353030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2235354142434e465133313345443448444a374351455057443533393457573345374b4d344645534b5a4e4631484b5757344e4547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2235345635474b5a4d314238544138434b32364e3335355135533037543452564b574357453144544a354632513842585a4736523452355331313147474452375231464735515757585341565337394642385a5a45454b465a35455450535a4153534b4359474d38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224456415054563538473537364e4236545a585250334d3435584d39324e5338545947305041344b3657304e47363559474b515930222c226e6f6e6365223a223851564b4a464a4b4d3242335736384841423636545451313643473945374e4644563734584a31485a325257544d574a56524330227d	\\x0c0f5ef25218edba85dd831f3e84586799b4e0e5090ed2b34fa439a8c54b6b43bf14032644d976eba79d314265617a8b773d58c17fc0142d3c0109690a8ca5ca	1577746825000000	2	t
2019.365-03PESNETEVV6M	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732363030307d2c226f726465725f6964223a22323031392e3336352d30335045534e4554455656364d222c2274696d657374616d70223a7b22745f6d73223a313537373734363832363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232363030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2235354142434e465133313345443448444a374351455057443533393457573345374b4d344645534b5a4e4631484b5757344e4547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2235345635474b5a4d314238544138434b32364e3335355135533037543452564b574357453144544a354632513842585a4736523452355331313147474452375231464735515757585341565337394642385a5a45454b465a35455450535a4153534b4359474d38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224456415054563538473537364e4236545a585250334d3435584d39324e5338545947305041344b3657304e47363559474b515930222c226e6f6e6365223a224b4b5138563257443530334a39383046313246423245594d393650524b30325450464e41465658465638343954344e4d35595630227d	\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	1577746826000000	3	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x2bf1fc2bb3b737fe61b755cb54dd578d63707bada855331ad0cd99c2bc05b47e	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22524e53344e32325457475a4a5a53364a47344e4e3033345945374244584854334a3247484d34534652314542314e5831324256394246484d363544455050593939384d36464a54344230414d363230485456314e5643304e38434854445732353237394b503130222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x0644f9875c80d4bd92e4a226ef36674868331f656afa0e17d60013e657784e75	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223238533131445239315032384530524b4b5a314d4e4b5134585038585336564e4231564e45585838473450465034564e544750373645595a4e363935595744474d30584e5439484153423533304d584257514631423653324e5645383039565646385a4a503338222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x3217321387cf78866eba6c7f2d2d23c280ead3f6176afe07e346116efb0d7282	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225943505944534847434332314a42594a354832353045473843414e435259423645345a513239463556383331343351513157355459365037395850324238595856375933364d57504b3236415a4d5748585848424e3032595232415453455336545938374d3147222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x351153e4fd3d19c6b894e4dec44d2afe77161d7f9d1ef0493ac17af74f35de4b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2247353332464b56594e5145525033474e4d485354534d574a4d4453314858584a34434836584d444135594d31343330385050505454303736444758384a46385648584152504845444252504833425a4859324b353758533235353356584a364342505451413330222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x4f694bb1a39ad2c48559237652fa9d9497656d1190ecd852894e45ff0b7416c7	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22485a35515835505a523453304647455a5a34414345424741465a394637383457474246334257465731344253545431545a4334375744533234333657313743484e3750544d4844504a5a3547334d50354e42335254434a5630344d32323831463052474d543130222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x6275f06eede0bc333821791674da99a919b51d60454b5d14fa62d9d478492fda	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a4b4e4e394746415039384b584e41514730424e5441545042363459325357375345593446364e36454d584444353136425a3738514554324a335158415a444d3345335741454150505439334b514832525434365256465134434a373958514652484232573147222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xae7ccfd567a0e57c22a186e24b348da84eeedf84e8446bd7464582a337ecab89	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224435424a30515857573244575a373246595147393356445132595645423450524a4e3659564a59464144533656433753393741594844544e4d41434a5948363238514d475237545330415a4535584e574456594654305a50455a3433465453464e5037384d3252222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xc0c634931e25fdfe269e615122fe58a2f3718e626d837389dc666aeab8fc3411	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225052314b48344a56354a51503739454e533650483752324656564d5154443350465a3739474a46374d424a5052414e334330354d31383337454d3636445056545a325644354854545146394e504d50593344414139533743564245424735504156334157473038222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x0cdda8e8ae9903f6e48590ff5b8c107e285ff41cf7e3330dfdf8ecf216e80adb	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2231524b4d3831545453484d4a374a5a465245414332384b594e50434352305652464733544857475731425a5036313130565951524739304b51594e5842594837524d3058315a46564736363358303645394750364245363346393833345a324652434559413352222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x17af00216bdaf8b331de54db2df0e903dd0acdc49d6b8590c47abed3b37a55d47ab6b5b3c1af5f6a146fd28141631e211081a6ef54a3ef25113dd7ef1ce1a52d	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x43a6aee083d3ee697612f674904e4ae18274236466750e09f0e76a1d7649a6ea	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2247444a3237573258514d5a474b44534a32523945485751304b563241593059334b3445544e484d533536504e54544e324e4744514d305753575453425353345a4752524251563034434234324837354137435657465a3638333130575359483435474850523347222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x0c0f5ef25218edba85dd831f3e84586799b4e0e5090ed2b34fa439a8c54b6b43bf14032644d976eba79d314265617a8b773d58c17fc0142d3c0109690a8ca5ca	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x798ab2df54b18d26c7e76ff6d39d1e3a09c537804358e62de34699d99e93770f	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2232594635373454353335324d4d58484558374258345654594d343933373935313952454b4a4d3938474246513131394b38514652324a4735465135384331443450363030384645485359304b39343547384e5050305943364a453042545a575736345035453130222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x4147120219b6e216b2be0cc4fd1d55409e69cdb30c26023041ee799254b98b65	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223432344158304438484258364b545448543856593838375237365a5a304b4444415158345932445a4133485a3631514a4d4d47443051335452595441595032334132574e4b425944574b515241563541513545385a4a414a4d4747504a4451534e433151453030222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x15f9c15a8d4a017e62343df05ef1a6951e64b24a163969e4f0f9cc1355dc6c29	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223332485952454e3854365a47573836435458435732424448334b5636594853473952525457334144455933363235305648534841325950314b53505a5a584e4530534336485a594453573254504645365250565154524856333530303833444b33315957363030222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x1e305b23bcce5d8e247e31abd191445027e5444c20a7bca3032c88555f0b8709	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2258464b314e443238335042594a5152324b344230304a4a4132304750324a3653344b52354544444439514e5a395338505038354157535636514b58305852313542373241384a42305a4741423538524b3941574132544b5a4a4d464e3547474a32574747453130222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x30d1ab646204ebeb457f748cb1d88bee419532f6228841d84c5e286d1f318d88	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d43304534334b39415932564d3556315950424e434547505359383937534a5a4645474a373733525a544e47583835544453314d4a32514834334445575839454434425133574e42354d564b464b42585a4546415044594b305433385437523259325638543038222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x418451f141ae53c28f98cbcf84b92897857ceaa06ea072791b70d697140792fd	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22433541344d47533844364436485246534e5630315851324132393730584e3346484b4137474a483252394a53585a334e414b4241325051413945424457313754483945514150475639345756425a52314646395a59345348344243424d505950434e3437383030222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x50e27c170bbbc7d545030af0c36111a48735d9fd2ab07494248f63f588bc47dc	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223552424e44365658365a5a5632515938563450465754335153415a5a39385031564657334a35584730454d4b34445143595957514b4333524d505738533832584843594d56413742513647475a465744324137545937565051444b413136514e4a54375a4a3230222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x599c0535cba807e252f69e51e88ef370b431d77a353df93daa5870aa6bd82521	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22565457464e4b4e384d5a38334a44355242524b4a3451455256373150394b484737313239445a3137314b5334314b3138515238485a5656584b3352355a474231454144335448574442434257374e4159365638534d4a535638374e4136344842584e504d4d3338222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x6daa906243acaac13aefc297dcd448d203d0f3d0b1ed241683c4402b8c9061fc	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2244563358524b413333443450475735484659434145475a374542484b58544b3938534147564336574e583536413156343332505730365135424151304d39453533314736434552414b593248574d5844534447564d4e4a4b573039344a5a38584d324553523247222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x75da54eddb2a74badbb3666c2db3d7b4d97b4880bccf8291f84924d8f64a7e55	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224356345744513857464b39474a333135534858575950424b444153594e424d31384b33414648383334574a43574337305746484b4a4a32354642333330344e434d5237304342584230414b5653485352355a545444574b35305436345a41334e44373533543330222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x7e81c0507d7837b68ad08a844d2bfe5480a5ee13a7eb36b59d0cdac1bd1351a3	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2233544d5258373741375a4a4e3839585a444b415a43355742355438524b58475041374b5a4d4d4533434244355a334d48323143324d424836314d4b515a4150584b46585431415443325130564a4d31595a48524d4e514d395837474a3036323146464251473138222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x8aea23add341b86cf2cd76f3584e92eb7572bce2a0a33ffd5b03b9667f93bcb8	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224b525741563733545752344d53383656394435354d324656533742484d45573443514247315147434333583741514e343759564d315248444d4a4752465a535a54394d42485235565343574b3359535656354b4b4431314657565a374a53543138593132433147222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xb167c9f8e9ee8d816e0d2718787dcd783eac8f8079115e07217cb2501ec68cbf	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224546525a365630394d564859334757305857434847354e443042544b42504a46475a59365a48473430333446505237515839483030424b334d465446445a36583034464d37474138393151574e3843325253355a314e325958524b5a5857454b31565a58593130222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xb6c67fe1f17625d4dbbfd443fff3683ad7ba06da17d6ac8a786d2a40e30e0fee	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22463644334650505a39354e4e3539384d54303057595631315a3138544d454b394344464257343753414157304e5839364e3844394d433556415135474a464b50375a3237344b4553564133324d31385734534b3237565053393244394650473130413931523130222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xb851f027d8a5a4ca00944fe9426fd89362601b34601664c65031100e648ddc3f	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2245514e5a5645383836414b3047415045435452353058584d4a535332434845393646394a44334a5139425250323750594653383458444d36504a354e4457413239375632445439584730583052443244514e5743505654374d5039593251464544424645363238222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xd7ff384a2f8111f4cef8053f19bc394a1569197f1b63770bf9064fe22cf053b4	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22484a345338524b4b483539574b563259414443483654384d54374b4d4b514d4d31304258434437564b4d5a4d4a385157454439394651304151585739595430575932583843444d4341534a4a4a5452445045354a4b543535384d5150514b424b5157594e413347222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xe26077bc7764119d1f1e834c0bc15dfd928fc72951c20735ae4db7b7fd34816a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d33525a4a33504839524834355a42564434513753544650584351474739564a31565641324a4833474a51314e4e4a3133514b344b36344238323156375a334842575a385958393046464348344a383143423138323335433535334338594d5343374457413252222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xe3e5fbed48a1d621bf9728ad84203e9544f50594fdb4f0dacce132cc35f78032	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2243574632514746505a4338354a544830594748444b46415a36374e585033334b47423647515059325347374a334443394e5030473251544133473551354d5653344a4a313433434252354a41364a4859343135534848384243514158424a56444432304b323230222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xf07051f49e218da11cf6a962cedb7d818fcb3cb4e118d11e7f521f809d45de89	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224444343847365032544b4356423341455847334d485741434d4537474747303130314558594e575256383651464e4a525159453848473430384445423156585433564b34375441533432443846473635433152345947303359523451564d54384d365033323147222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xf883c1b65badf2fb3376effa31ff72f7dd4fd15e023a589a4af17cdf78b7433a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22484e5946305641335034313643395741523343344631474542484d444a36374e5a5930474750444e44583346584335585943374837484a3147464459594130434e4a414841524b4a415a385752563457385a5046455339353339393130314d38354a33424d3330222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xf9df322c5455a8d5678ebf99d3fa54d975dea70edab124d200d67c81d0b3f681	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224441504a3134524e5735384a4d355a5744594e57325638454e4e4157473030435a35474e4e325a3857585451465a585a31305653315a31354647375343354a454a48545758475743354a4454514645563637343536424b4b524e35534a433143544d3152503030222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xa90e1e2327ba3302059298f3064a2f661e3fbd55f41a3016061a22771f22fd80	http://localhost:8081/	0	93000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a4232375a575131474a56313645385642595a445944523535524e4e384e4b52454b314a4a4e45365a54473252334b3532544139373836373539444248353344384a53435a575a33525730535331594d4a4338425a4553534e3033455a463335453445534d3030222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x940bc5d2e379e42e20b2462a3b1c6983af34eb84b18cab89551aa66175ba61c0	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22424841575958543041535958545742515a56504658415051454d364e513644423047464359464b3756523056374754443243514b5a4657524d344747413439563659483945565a433353595a4d52423931373953443431415a36474b4e374b334b364259383238222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\\x705c13fce8ac1839ab781a269e878478298c66e6060b82dd1c58cc863b7b6acb10abf00530c1387c8506bfdc16356556cd5906c322352c7a5222d2d034b2eb62	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\xb72a2c932a3e8bf2de668a4055052c83538b90c6d8151ef342ccb6930aa3049c	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x1fce2b675acc04dd3bd89edfde7e612eacbafc8f3d1a02034c62d6f87eeabb23	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223039544e574547454a5239514e534158304347444e4541435148513544544a324e53465634373346374d4d4e374a4154484448303334533950455246504859524533483035463854444a30564b46464154533346564139323656445036584b48314b4537473138222c22707562223a22335a37325053545453473244544559524b564658575a4b31355450424e5a3446374d44303430544343424246475a514151434847227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.365-01REEGMTPXSJ2	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c226f726465725f6964223a22323031392e3336352d3031524545474d545058534a32222c2274696d657374616d70223a7b22745f6d73223a313537373734363832313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232313030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2235354142434e465133313345443448444a374351455057443533393457573345374b4d344645534b5a4e4631484b5757344e4547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2235345635474b5a4d314238544138434b32364e3335355135533037543452564b574357453144544a354632513842585a4736523452355331313147474452375231464735515757585341565337394642385a5a45454b465a35455450535a4153534b4359474d38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224456415054563538473537364e4236545a585250334d3435584d39324e5338545947305041344b3657304e47363559474b515930227d	1577746821000000
2019.365-00883M7PH106G	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732353030307d2c226f726465725f6964223a22323031392e3336352d30303838334d37504831303647222c2274696d657374616d70223a7b22745f6d73223a313537373734363832353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232353030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2235354142434e465133313345443448444a374351455057443533393457573345374b4d344645534b5a4e4631484b5757344e4547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2235345635474b5a4d314238544138434b32364e3335355135533037543452564b574357453144544a354632513842585a4736523452355331313147474452375231464735515757585341565337394642385a5a45454b465a35455450535a4153534b4359474d38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224456415054563538473537364e4236545a585250334d3435584d39324e5338545947305041344b3657304e47363559474b515930227d	1577746825000000
2019.365-03PESNETEVV6M	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732363030307d2c226f726465725f6964223a22323031392e3336352d30335045534e4554455656364d222c2274696d657374616d70223a7b22745f6d73223a313537373734363832363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232363030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2235354142434e465133313345443448444a374351455057443533393457573345374b4d344645534b5a4e4631484b5757344e4547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2235345635474b5a4d314238544138434b32364e3335355135533037543452564b574357453144544a354632513842585a4736523452355331313147474452375231464735515757585341565337394642385a5a45454b465a35455450535a4153534b4359474d38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224456415054563538473537364e4236545a585250334d3435584d39324e5338545947305041344b3657304e47363559474b515930227d	1577746826000000
\.


--
-- Data for Name: merchant_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_proofs (exchange_url, wtid, execution_time, signkey_pub, proof) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (rtransaction_id, merchant_pub, h_contract_terms, coin_pub, reason, refund_amount_val, refund_amount_frac, refund_fee_val, refund_fee_frac) FROM stdin;
1	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x0c0f5ef25218edba85dd831f3e84586799b4e0e5090ed2b34fa439a8c54b6b43bf14032644d976eba79d314265617a8b773d58c17fc0142d3c0109690a8ca5ca	\\x798ab2df54b18d26c7e76ff6d39d1e3a09c537804358e62de34699d99e93770f	test refund	6	0	0	1000000
\.


--
-- Data for Name: merchant_session_info; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_session_info (session_id, fulfillment_url, order_id, merchant_pub, "timestamp") FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickups (tip_id, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_credits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserve_credits (reserve_priv, credit_uuid, "timestamp", amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserves (reserve_priv, expiration, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tips (reserve_priv, tip_id, exchange_url, justification, extra, "timestamp", amount_val, amount_frac, left_val, left_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (h_contract_terms, coin_pub, wtid) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: recoup; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	\\x43a6aee083d3ee697612f674904e4ae18274236466750e09f0e76a1d7649a6ea	\\xe613367354f8e710fad41b92ec8b4ce03b14d6bfe54d795828157cb3fb0edfa864f044541525e8e24cdde66f71d23fad53b727c79d63f117124da53499956802	5	78000000	0
2	\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	\\x798ab2df54b18d26c7e76ff6d39d1e3a09c537804358e62de34699d99e93770f	\\x0be995d52ae8cbe750686a2e405763d6b2050e98b3eb9ccb9367d85df1ec3b0c39e3d854a603808ddfa1292d4a8e1bd11fbb856dc92e6e11e1510a016a901d01	8	98000000	2
3	\\x9f0232e4c5d489a72ecdbf6b65c1baacdbae7c49781c5f7025dc69cbfa4a3afa23c6ff13d0e5612da2243ae0d5e1cec2998ed6c64e017a2a7baa77f0cbf83617	\\xa90e1e2327ba3302059298f3064a2f661e3fbd55f41a3016061a22771f22fd80	\\x624f1f9ed511c339db79e6efca16bd7f65050b5ac9cbcb432afaf7e97bd213b78f154f921e5f223716948217da168ee19436d9f2d5510947f1d560369f51ab09	4	6000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	0	\\x248071246b3e518dd3af76c275e0e6cec6525ada62bdca50f988b8915b720ec2c97ec74b8ad6ad417ff028a37800e6d216640a9e9142d1203f45343503e0b607	\\x999b45838354fdcda3ba5adbccd528273acd2415d1d568833619c3094a4b7539edc30f1ac7cb879ff24c27a2eeb63490302fa03a7063ffadd5e9bf28d0b59c0f	\\xd343f71c66c09fc3f4f411bfe750798bb3defeef7791e2fa9213f3435f546947803e5b974e218411e1a020437e552a037776719a3db163b545df1a364d1a77fab983175408ce4ae265639bd8120108c15cd9de9e822a3ddbf7300bb05ecf74c0977947a5d0a4f7b0cfcc3f4fe159d5c39a3410421de921a07ba9374f58cd19ec	\\x8930b86d91720f007acb4ebf5b7cca9cdc80768d54561ae0ba935e206678dc4f7f26a95d64117f3d3322a106983d8333825e1f924280182241447dc17ef43d34	\\x0e18b65f402640ad6ec863c5d398e979c0efafc7e2fa8676b08790e6cc4d80963d25fa6a8b6f9f60a2175dbc6ca5a89f7e32eb8ea45481e4d1e71f8fe2f21a1a82f04d7e56eefbe1563ab6a9fa586c993facffccf9facb154d2f5f5baf607d4d839e75c7dedce24e7f0e436c109ee520695d01850e5f0ec9c92d70d737667172
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	1	\\xb6cd3ef1f9e0235acc88b88cde064e722a0b871535feb03c0ac8b24b1dec651184871800ff16b3b8886bfe58a5ae109f3ed7b087aedb24cfadd4f0a7f95db406	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xa313ab151f6f80b1945520974d5d4e35f4fa0f2e48950a00d68c9ec5c4aa4a70f5e41cf970a941aa89921f978a2f2de349cae7f4cb113be69b740cbb3e408353363bc5eea37fc40f67f4fce7c75736f59de505a1d71c0216b57d811c7c71753f9042303fa091578664c202b6e6d81f8711a8fa49c7099fa4aec9b62b29e0c814	\\x1fb70168030d0b20df1a61e1343af47af3afc5de8503218423ce9f39fd68650f3b103671b178a40d88d7cd02f1e07832c6bbc29872e9319a26a30dc9b7efb073	\\x283eceff7f670472f60831f9945b677aad6ea6f6d966077f07beba932f929bbd79e19bcb6f5abc034793866c1f90d391edb7506cf4b748f3872c5120d5f82f20e9e5fc09329f4c7481815bb20903fa585ece172cf91701eb169e38ee479b741ee852a2451664ad43ae88c8049e7aaa1e8c267ce790807e80e87c43334f5291bf
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	2	\\x3ee47d36b7df6d7ed6f0e34b5be342c41f3d51324ccd89bdf22ef97459e9aad8692a18d11bbc8cd94a9771f4e8ea6dff4afc10ac2e9e2493c72ccddacc66380f	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x953d6c346850eda967a3177fe93712e2e247488e8bcb4e8bd996fb8dd04231c404b23b6e16cd935d05c5dd8d41b71fe3059b6a0b5d05fc80b69ae54de0121cdb69ca83dbe9e1769d72007928e49ff54948a2d97a62bea4d6bad692351660fe4972ebb10a47e31567ad0122d042c611061a03ef347fc68dcd9cb941d4e6f71311	\\xb6f48ee8436f329501bb012a5dbcfbaac32dbd4993ccbcc49e13773f65db5c0b7c0c8ed3f95c6caeb9d149eec8f6e38bb9afbbb03cd4491ea7f3fd40d23c3df8	\\x390a31d0b0c6bfe1dc1c00a902bf5a32264b2546fd67e43af09f37da9b65084cc77ca349b3c7204ebde341a0a8c0c8cdbe167d766f6dd13289c1c205f2317c86a01bddb39f27d7d38291c64450ba489f214ee859f8216063dc23089f5832b8227bd0512f300c9f9c3cc0ab3d9a55170b2fd9b0ec8cdc81cc6c787f11e4dcd9b8
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	3	\\xd19e8ff66427d542cabcb9435d3fdc2d4d11b89e61e65669df33fb342b04953321f8ff19519594c75177490c77d28e8f51f7dd7c3067aa81445be351b9cc1907	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x532200eac422ff7172ccbaabf0ffffb9192815c9d5872031298f9b8ebf593fdb48585ea1b297412e9312304ccf8dc982bcdac9c8e14b228f4fbc4f4568815c8f5b6697754de41a958fe0843bd27734bb91d29e7353a232f78f37cbc9b3e7a4023cbc3965d4c17009ddb8e16af8fa42bca37280edf07621a5810c7307203cf5c2	\\x120a6247091e5ec1a21e6ef50b85b0ff31c83999e0351f313535f562b8298635f7d2a597602c6376ec3c15a280398420930dca84e2a1b6704458d809e0b757a4	\\x6e411ed061d96e1f5f224a3484301e1ef14f35fa70074b2f6cb5985d364744ac448f849f93fdbc7c39606d6c1df481e7b6604b2aa13892f4d96d96b667f363c9d67a1b2ef661fe27a05a404b5dde97560c49e1efd53ecccd6912ef27e1afedd9cabf8b333df79bb7027f106a196ed85c03e585ee3676ed23e5171b14c7ce7d8e
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	4	\\xda3bf2560bda0a9830c005c89645e8d4eee3a51c7a0308cadf082c93f386e8468afbb30f00041bcc31a62ae7993ee205bad7b42d57dda0a2feedf15dea3ae501	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x14ffc0b16059b5a1812a2ac8fdc8cff2e91a471bb63443d4193aa8ea851a49ba0ec16b68ab04e0e791c91f6c8d90e4a79f9eb602c6e656779e58b02f8650a80521d031b4658d3de57372e7305a1590168f30b0345c289771db1fc6353b71b28103b8588975fe57df29ca35b16f5dd242af2f8e21780b142d720fea01f8ae2756	\\x0101708a0f371b362bbb8236cd9ca6f34dd99ef20f4b609c8122c304d7c82ab4b86c1156c356f050cb835c882765e0c491b0ffe7aea1e8f689d0a5de4561868f	\\x5f376e00da273878ffdff5aa4eee9d2eed5ca06e9504ca90525f8b785333cfdbe2148f73875fb29e39bbebe638cfcc266bea6a1593b4ba9a858727563d3058864e39bdcbbfe2ff4851daa1780abc14d46d91674ebb59b196e16e7b1d4ce339c2b38d38b42f554a829d6a99fa6a4c93c7c4d0449fd3ea00b3681cf8d992f18679
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	5	\\xf8a8e96a914f6d553870c2171fb2f95a4df6d8a447c3f201a11132a5a0d33f72fb0f523ccc43a95a7388488efd8cd59ed18e151e3ea3e1e5112a96fc6ce2f30b	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x7ae8dc52a7886e130231122aa25d4a7f4a03e3597bf0f04740d9c2e30d3fee3f1659d1d900757a65ca357e4907c35b39401aec8155df28fbec520c26ac763217895499f62007b72dfe3f4242458ae5c197ad6e919cebbaf5d04aa80ff9dfe98c26b35ddf69edb98951bba227f3bb647fc5c8975183e4973dcd5b875adfcd1602	\\x4ea797385d64d6f67b3301615d7c19140be4cf522580467feb949e55903fe6eb555bd8b5b95ecb3329178b7ee606f7dfaaee4d8dd3995fb7f82c23d4d0dcf557	\\x0517927a1e340ccef11baa57df39579b6584116807b20ad4efa16b2496c0483629389da27d062a94820a03733fb394d298e7d851fd8c434cff3de737062b018090d07950187b5f2f39d7a146cf4a575b295ee81571d34405368d468bd3e08e229b40a5e71aec3c5e318ba94557c6cde5178e4eae57df7990608cc17b1ff2d5c6
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	6	\\xe9b7aa48bb5a0f4f401571b21fba8dfb9331e0db2dce9cca571eae71ced1d73fcf6ef7d121e3ec73f408eac52618bbe0c80d7cf308d951fb031af9d41933f900	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x7a392b8883034e95c5c932a406cdc13f8c5a0f88c327351c06edaa34a48aa4fd112c0c89d34d4db891f4a9d94924004cf3d9bb0014a765611322b36bcc6c42450bfc4240c131802441684dd20881db5b4efd1339153b379a6faff0382e23aa5171b6f045c8e4bb685deb0ea78ec96798ccd4c6f3348d89f8cc9c07242e692415	\\x5b15f3f8c5e046faec51f2e99ccabd6b61f066c07e281eca28282e68f9ba18563d8c24d25fb4367b66be6d373497d1d7c1e36dcb2ab66255dd24bce3e606abb3	\\xb2ef142b4379a62865ddf3bb3019f8f5e434e0533d822c6bb369975568c3de6aaa00cac53bd8500ab132fbaf1a5c5a71ac96faa163595fc7033cb4e9ae3ed0df3cf4cb19d6ea7d679411f516b1309d71e6a9c85bb46bcc447d823992610fa8314b066d7027313bb1a499c577cf8023ae10e5d0de3fb26619bef6cd1c3480946c
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	7	\\x1af7efec413ea6a8d420fdadc64998df3996e4f400d59f83aef26a5d3b0f6904f4e3287b9ccf1b0faf07263fdc3325d488dd30f0afb736fa12c99ca834bb2005	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x012b71477ab26965327f4a1f33c84a1d36bb20c6dee2700eb39f28f95a9024ac434f9cd26400c9426abd6063468f9a5a12a6fd056036d900ea445b3d53fcff08b0602ee2ba95a1d53309a8a61c602ed65052ff55bed5dd32f5d96e4b393e4c76ec3eef13d2e6c13a3e8a9746026f6b7033853673c17ff2e49e57d7c89f4a6aed	\\xd601c7a4f4f15b5a0aa8ab3505c75c732e7580080ac00369a2e401808f2a5e9cad20e02dbd5ba2eb0f69e0a440326173dcd55e3c386bafea1ed878423b4b2a9c	\\x2bb897b815024a2712a44b79db5945ca9cdc240ac8efebc5b77dcd5154502ed586cc17274b00a2ddaafdd5108181a31bc2d25df0decdab6a8a000961da1423f6fe3c341912ce94f66321d7d99e834f3e02332777606387bef51e593977068d866648b03b70c81434919d58f6fd3e023cad57ab2022e80ae217319e27417313f3
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	8	\\x9c7056f4bac553fb8739bcf9989aa5c25821b53cafe521f9f79475c81f6154a5bf415fe0cdc58d72766dcfe38adc6924aae6d39ba5032256aac599a9bd16590a	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x670a68fc8b2b65cf0fb1a2d1d73d30b907198e86cb01285fcb9a70b3f0ccf4e9b8a5be2d189351845f492c24be292c047498919f1e3fb40129f2811bbc037a8936ae59d984bb4c9a1ce13f751e40ccb8b931220fc06c86c1c4586cb7b26663541373f195327017e35719ab33d26303b3736aceb694f4ad136cae13389023a97e	\\xfc9511139e63529e1a7359ecb5ceaa689049a0e154c5d902b623ca47d96fde4ffcf4aa64313c3010a314ba1dbbfe8c2b4c91a2418c905d9779c6e5186a419af5	\\x3df9a29e8cbd21d8a7173f2b63d34149be46925cb6ac9698e9e31e542ab952eef5eded21c49fdbf9d832087efde74487912b2ae4c77179dd7452d9f38350d738fcc92382c6c88d26888c44bbaff0a279596c822e7e60ad33f697277c21ac438030a1f1c2453d799487b5974fbe7c2aaabb59f10de0eb680007d1b14e8e4625d1
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	9	\\x2bc1fabcb9a028e6870c2db25c7fd93e3849834a17471f53afbacf15491d5a2f877faec9b58239f94933b61068caef31b1e1f8f951b6a2853035305a129d4800	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x0650974ac8d166935e7c45fadd7b122d3c5976d58ff6a7380ba9d1ff5b752617ce872ae5e72b269b150bb28d868526c94fda91475ad224cdf36e32959006879ef6215054124444c3d45165e15d1f95c8921247e8853e0ac9c0e824e2ae80610a696ca9e164cb14cc47f548a988ad64fba41cd93c5ec23bf68cd6b14f4d1e235c	\\x8a96dbf1cf9c2304b153d972eed3f0da89a95bc04b5e43ff36d12165018fca8107b89f75e77e5ac9d83543d0ecafb39e047e3dd603fcb571067a974e702b8186	\\x6a6280a83b328ea2ec65b4de79b6af11f098b585345e0462cf863e499e5015c87c7fe213e8ee05fd25075b1d8de48fc275a2f7eb4500b341ed17269c904999f56ad78a630f67658f910010aa105234817cbf4e6468e316a1d4b051893adbdc7bc3056cfed3016556550ff1e3d033aef68c30e6d29209ea30c22d723f6fd9c2
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	10	\\x139a1e8fdb59c452aace8760b8e939d99204230088b81f0ed6fa19f62a772d515e285cf65453ba4d71f94b4a07080a37d3cebc290fb59bcb2b70b78d2ee0810e	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x4c25347c99a6155c01f8765e17da5a139b666bf4e4f090b3fb6e0a3c0f715cb189425aac7a92285718a42bb9ba251ac20ac0f6dcd84e6ba886f469763360d7444e9a3a1d3f9702f0f9dcd205dd8ea9fd6e9e23b6b9ffa5efab07aa4240995a4c0997ce60e6d2fb9f79cc97bc73ca1d71bd7ffedeb6fdcbc6f8fe9b8464af9a7b	\\x7dc811fd72060b01c5181b8d80e22d472141c3187f33ab0023a6e5304a1b5406f27341cd5dab46860f0190ea39a60e4e784ec5673e3b60c2f3db0190de2125fb	\\x5cbe03c4212d0a4d786f1c644c45a4c4cdfb16432ac6f9f8cbae53dd90a586682ce7f5af7ccd507b32f0a5ca06b18a6582f7c8634267764ae5b635ae412a290b1ba614fc49f0dc7b3c03de36853de11754be00e0fb24807ad8af9c2261c76fbe499c5e234c8281230c115a53125f8b191dba3ecca2bdbbd253c323fc8c3d2d6e
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	0	\\xc60ed5933f2ba32599ef6e52590f24060fb0d871b325b8e524c5f7c0a74c1126692af6b9d605b3f46b357bc2974d722e9df161195b229c809c0ba6cf3075ba00	\\x864764cd850c74f7156fcbc0a578f6681614f08e491a3af2019613e469c8bb1b8c5e0cb062f2f834e307ee4255c65a54d83ae2b74aecc7a38de232997e1686d5	\\xc6ecf15526fdf9172e5e2ed94583de37547a183f2dbdfb80aa11bfabbe2e1df390a0559dc0a0504b263c745bc2d42f511110525abdb40ff7ab7984ad1d846863a39a84fbfd64602d79379c6ed0ed09235d73a9b0dc99bc42a9219b9ac8428165d181c6b2e53482368709563f3294331f106ee45a8da62d9f2044900e7bb9f32e	\\xdec89ba08f1480fe98b525cb891228cbdb88e3a936040c44b5d94eb54fecf1d1e5219c482596167fc082c9d6607a043438f1342c580b9cde624b6748a72fe096	\\x91593419ba5569e70788b3ffc0209a24ec93b8876d29704e56b42fbbff0e7157267bbb08a8d4b5168fedac1a740d8579afc4285121b9ce25450a1b77dfe28fcadc5e9cf60afa3404367a19a66d7535c7e4580a36792722e1ed16cb365c70f9dcccb31fcf934d3c7f9ec8d4f930363b924a690ebdd5802bdab570985ef6ba77b8
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	1	\\x63430fae01a5c4b47b6eb671d8b111bbd5440998a56a144879226fc3bb4f5698043163ee1899d059ac2f219f0eab536b49fb758b2f51f0e3ea199428887e7d0f	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xb569190dd0e09b3bb05566e0123b71b0f3484e40214fbcb8175a5bd47f7431581619ff64c67feba77a27a5e70dbc45ecb9fc571a7df2e631dd85039709235322205bcf5f3ca1c080db6482307da0a9bd388c47cd489256673c538caca8c37fd34e1f4179ce0334d4ac5675fa11a2ba7a7fc4e841f7273006b2a3453f9fd4b1cc	\\x596b9996070679bed0bd7fd9908665c58820fd646d25fbc845fc3931a7e3cc4402218984ac1fa8f4a6299e53d4e64cb6b217531e20317c5449443fcf922568d7	\\x0b4b2810b5af984ff4bfe121fa8b59fb8377bd897ef1c0a53c85ea9f06d93de0a16db631915448548cb22467b2f1f38bed2a6690890fec9a560fe20d63f30f60a3242887f8daf32c1c6fa62986002209edb3206db0340c8b803d088601c773b29f951a59d4636ff8fd2328dc2cc86f927f13b81a4f19306dbb060a93f4524035
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	2	\\x6c4dddb75def058db3dc2ae4feab923df6d44a3d28a39c7561754f080a33db148a6aad5eaa6d0b17eca4cbbb470a260fd8b7c2004c69b344bd2533c6f17d9b03	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x705ff3807d7913ff6c5ba12eec7cad9a6425714e1e12f845396e0e8098e1ae62dddcb4625aeda7ef927e0c66243c3fe2559374e7edd92124c00b3ad2cdda23931788c0039a83bb6fd444b3f397cc67b7da5df25ea18dd66202a7bab2a22a175d3708bd6bbbef5a42510d25f6c2e16201b87417d7030c2d1aae16608a12ac164d	\\x2293ce3a8dbfa3101af20c41cd255fabb212ce3b629077d3f14476c84c46bf7e5b3bfa58d9cf484459063b25e96c1b5f0ef751131ceb957875c7aa97bbad9d49	\\xa178d441cee81e061ad8c6648cdce953d19fdb4a2efc99312cc699a261e3947cbf06930e21ad19b0e7fa3f4d97c8bf497356fe7ea7f90d3b2f7d81f225084e0a189f02440789d690eaf0aecc49db3da9b25b03c717b7e3f30cbbba17aab42704e14acccff3a386218c0f42df5dd1dbc4eb313cef76608537d3ecedef85c13f96
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	3	\\x16c34e9491995b6b941028a107b29802d9f7925c590bd4f44cd177983720e07fcc5710a6123acddcc22a3aefa23c6e36217be5978a3d0d8978d2b460d754ac0c	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x534e767826bc313ac18517207854aeab03bee144a492898decf02169838209126edf4b94c5810ac941c9f59b189ec885ce3783394a2834ce851157907f0c960767f752b3bef949ad65b648887b64b894464273c4c013d0db2152ab8bc020b4f090a8c8fb399d2493505fbd04811e82da2ff0c09e1203831eae8a42c3adac3b7e	\\x73e6ce05cc9c9b0f66bd84e5785bc134d0e0a1b2896b8fdb3b9848a345a2270c89f010c5cd96979017df4dec0092a7962a4743b66466c58851c41c226e0773ea	\\x840ecac542fd88c2908b35f6a3d053e68416097611642a9cb7f618047bb7065f8a14106d7d254d76572289fb9edb337f161525731c3bbea56356f9f6d4f0d20d57f8f568ac30688875f74c3047519a61f1c64f6d655988b5753fe82ba314d93959c54a8b03125398ef89fac7d28a060fdb61da656b3bd40b39aa6e2a7048239b
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	4	\\xc7704ac5c4e096a562d8b3b8b2aee33c4e567645f4005fa0db8c65cc356ca630e7617d99ceca8b1ddf1d26a12fb342fd08e9a3f3b37a366326d4da153958ae02	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x9f402a2348a63daf997b54e1531073a72e25b0a9e9f4037981c581daada2188e1b849c450e6c90bd66d9b443d2f5a8bb2bb3e85f97c21ac3bdfe484ed0e49758a00db18f6941c42440583c88385b09f88269eb7c128653924263839991f1c8ee88155b0b5474571809152523f18392ddbe85d24376d8252f9b17e18b1036ee51	\\x07e1513c0cca55c093ca3da14f4bdc9065daf3b7b927754ba93e29a5833d41f0adc73f3cea14e67a34feb7ee1dd48fac25607881bf5a35bb3c5fcfcdc9e2aa6c	\\x8b5a82e394df4ec5686a5c35e5126b066f9fc0f82269da27a5677dab4d5343dbd3853edc1e115868fca10f79065d1549e76ae800a055973cbd69f8baeb85e1886db6f7cc73784ccf710fc5c4ce23bca255788a909a415b7feeeb269d25735f2a6b06cd06507c21593c5fd7e0fbca2484ca194da30a9fa9d2ac91e574225439ff
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	5	\\xa8638b709e9de564118786ba51d1b16093d56538b6d4d38981f9954f787e1f1ca05ef4b80894712054fadd3c81977b7e644aec7df8438e599a7a5a5e5e4ca303	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x3416687519374f7ffaaacb268147ff786d1d00a98a5b91ce6972b67e43e671e5f2790cb87c3f54a6eff6654397cae905a573b2b688d57d487e32d25ec935578f7e60029198cb756fe9696fe4204964673f1d751cc302063aa2dbe0687d3ff01f657b1c1bda19a2f6b0a5434ac98f3fa57fa02c322e3bdc7cf16f8eb155c24a73	\\x9a0ba5593631c93bc69ec377510e3a6073c9da8316c549cd8648b448bd58cbb697c23360eed5e3067b56681ec8128d273e2f9a5c8b34c8221b2162f3af046f69	\\x42c5b824cd4c3a4e629b4e1e2153ff5eb395a4d2013efbbc98f8dba6e2b22f8b4fb0703fbbe745d4b24794b695ddd3b33c57d1ce8e8427cb7aef970a4d9f93d48346c0bcfb4bc108f26485bca282200de0f6aa46fea32520afce2aba4fa0070b0774b944f3169575d24c0cc8f5b69623add79bb371fc1e8ae5533c5c2f9932db
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	6	\\x9deb14c0bb6c2c37490df5b8d716895c0c364946346273df02a57f46f00b1c85646c62710f9c65fffd214013849092d63917de3da82e19b5d635ceaa99c9870e	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x23de33759b6eabd19ab339abd5b5c7a6169fb9c763d8de49a2a1e2f1510fa04364190725d3c323b45e56d9b54c3f284c14895e31bd442227e7b33f9c0ab107a0debdfdcb873b18e49f1c76d9538fc5720cf7416a8590a8ccad5b598903dd58255f28ac6c12c296280f5f60af5971634e58ff0e99b006a92b0bd144e120087370	\\xdada83780ce19f641cc9c8d217a705f5dff8969dceb1cd6e9b063b083c603a1794f496a0f675dd7339a8d63494ceeb8feddbee4629a851a193277645d40dfc02	\\xae331fe7b8785bdc930706f0ef71e238fbb588f6a4f3250e592ff06309d675f4c63df2430c757bdda8f60e5954cbcfd98c1671a534db62d57ac6d863f82d3cab1124ac08e3100539c8059dab1c2cb60f95004d6eba4e9856568c134129de0cdc7e7bd33d6d3eb6959404539641ebd1bae0fcf706e608e23cb8e524dc2814efdb
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	7	\\xa713d1c3126a21211c93a05bfe1741124531b6e27a1eeefba02faf1549ab6823017fbe9eccd5f5a4ef3f43636caf81d4326cd77aec22c831dd6fdd38063b230b	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x9a7c45b1aa0f8ed1bcfc6238b58d14a3c86449ae3a705cbb0f8e04cdb958045fd1b550a6098ec929385db56bf55ab9b22f9da5ebe6a08109ba84f3929ee2f5f3e31c61914387764c4a38bfad44578a6a1d6ee297a5e65e466050c9ab9c2e7b81258ec1f48eede39d1d50490fe0a73eab0736cdd340301eec072bf807744e593c	\\x9ea47bf47babaaf99c2a990421a5730e933eba1073d8cfb00ba90e3e21365b67f9363a500a42893545c4cf2d6e0873d85dca0d3dffa5e3d0f7c2b6708c45fc34	\\x936e748d6343cca1e1ce621a64b74ef2e078905ecd9b106de471c3ebf7da141e9c95cd092b380638f701aed272fe5f73f45b876587756d8febed204edeadf2199042174135f0ed41d07918b3ec7ab2f1be6831d4af3f0d378a9c21fed0621bef3789917e3d3bc979e05d0de4369b2954437a5a1162e1810fbc216fcc2357eaf2
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	8	\\x96d4930f2e8d2411f98ab00493e44f937559ffe885762104c053c6719cd499b546892cb90d49486ada6879cd4843384b02a6cf9be902dac13ce06c2dd808e201	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xbb2ebc7120d42cddecb4b4a241e8c01837acc96d0624d5cc687d6b07f660a8405219659262c66dfb123b2f15c714923d07c2cde2a7dc0d0418f9dd01995a3dc2d3e70ffce7f8973bc817bc1382534820106ceea7c70483152332fa43a41d3b6683f31aa453984592b8ff52c65d1b076ba53bd5455b3789de28a62a0890785d74	\\xfece8381a8072dc63d981ad2857cac311820f68f318083f1397e28a4d7215a54cfa50d26fb21d2b4ea336050c1ae63933a77bc05515ab7fb7cccaa6c14221e16	\\x0782bee83e8e71c2748f5eaf63a8d65409ad823024b32f1f81283352b3fee47223375425a7c8a0f265cad0ca73e0203105f6fade54046b900ff9bc08b1e59c029c5466a07b365d467933790e8c80d705cd7c642ebb9d8164945259ee84de2045585386395a98d867567765c793f95f5c9af606062d202c62bf29b117c441ac81
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	9	\\xe74f16842c2d826dc84f5870c8df94f9d1afbb271072a2cfbc24a0ba09a6d69bf1764bd5ca950721f198644a10c42ac2e1731bf723b0b1611f24fdf3a0a36108	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x396253658e428b7ce97eaff77b2c9dc74f77fd69e44a0b48cc7c6e7514444bedc00c9e64688babb6f531f7e994b481d30c2e369e956ea95c68f2ceedbac21c219d28da92b0d4feff2ab8be0d6f697392e840be6468322affb3e01e2ff46ef84b79a3e4534740da98df8f7764b123e5a88b0f7309df9d948d8d58d262faf8fc88	\\x060eb9ff07a1192054324f62536de80de2e64f13de61f178ba755a3eef4fd3f333243225459bd64219b33da1b7b5caadd2974b82d3283a5af11bd7ef11aba414	\\x617d098d0124dd1de3feb41127bff93b2b0658d9865441be0246afb1f16dbf501b6981cbffb728bf19ac479efbf51937d2d51cd9fbe294cdac85ca33fc95e0e80c57ece2889cd53fe7e7feb050313590e43ac3b80276cd6bbf183097ca896edace8b5f086f0f853c24dbfdea02a80e4b87951d451004305d9b44edb7303023fb
\\x9f0232e4c5d489a72ecdbf6b65c1baacdbae7c49781c5f7025dc69cbfa4a3afa23c6ff13d0e5612da2243ae0d5e1cec2998ed6c64e017a2a7baa77f0cbf83617	0	\\x0a2cfd7bfcf703528046af1a70aa2651f1e262c7d2e7021518906544c3cf23ab70d5a32eb46399480d0c75a8daa0d4a489ab88e43ff5bd5174b02e4d62b77f00	\\xe88490a0a4038764bdfd141764e7263f5f55c904a540846dc7b6fec3277de25b29f8dd46762404ae50494156e830394fdbaa50032337d2aba2c09c3706d11efb	\\x547d10b260e2eebf9995bbf82842c3e65ef0f0f0f091165303c4c8782701b70dfc434178948894d0cb24e65c96ad6bfcc5a628ed0ec77dc1aa63be44d0b0a0ed3420324ec7ecb237a01adf618a527c9ab5d521f9bcc6c7bfa064d08128f2a4d9f93ee5e229ad7ee6b0ced512a551649d1748f0e75b29d7472aafa12c852613ac	\\x775cea52e7f0fe0fc6e7a4f72b94a5cfadc813791b91aa6d88bf7d1ee7756cab56d2adad8589443e6fb66caab0479ba6a78e41be58611e87f8c02e40ea95acb9	\\x78671259c086e99b70d44c13ab40849307d6922aa2dcaee33e8b835dba2f3e2cf1ccc0f97f5c906dd2cb21f1722f056f943c9f26efb8bffbf4e95bed1f1ae2d392e392a920910818ed0cfca207bd8fc94bf3c2eda94527f75a17e78a3b52b4697aaf1fb506d0c06bdb7ddc0cac76cc364377eb4a4f334151e141e26adf733367
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xb4677dbf4cb43a2bd89e2d557499e0411749c62b3d1092a5b7eee3bf008fb94b2f3573322dd7d9e54e1000eada84f8941860ea4dbc8cfdd926d6e15eaad299b9	\\xd6a93e80bed100b56fe11510619781cca61f92cc6f90ad98db12e81635dac100	\\x919d8f6c91219c78783e74af4443fe143f42859385c899cae5db64126023649414456f7baca3ff210f056f7585a38f1458dd970ac6d71e699ba3613f2b6f17df
\\x0bf71c938391c27e62b5647cfad6d736671e2f4dfae77ed663c5a0ded4869c50aaf8469d0f6600fd82c6f53d4d5c2c4908b9c74e0f1a7b78989a006d99783c47	\\x8ab20fbb4f64d5885051ccf212498ec5e40395a2e6b2b109374ab40018140266	\\x8904614d505a4edbdce4454592b4ca6d959ee9ee8da7f6153e5e9f7f4010a83b54288f463752e4de420974953f891127ac8bb9d4154294dd08d0270b861e2015
\\x9f0232e4c5d489a72ecdbf6b65c1baacdbae7c49781c5f7025dc69cbfa4a3afa23c6ff13d0e5612da2243ae0d5e1cec2998ed6c64e017a2a7baa77f0cbf83617	\\xb0080974b8fe0069313f564686a8331305cbc4c995b7fc52c55029c1854f1c61	\\xfbbb39cc46a8abea91963883aec1cf1fbc65f9d9878f85b10b02c31e6da3d93dd06eba6e0a06de418d69a354bf2e1f256a5fdaa40e372cb42721c9fc2f3821ac
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x798ab2df54b18d26c7e76ff6d39d1e3a09c537804358e62de34699d99e93770f	\\x6ed56d6ca8814e6aacdaff7161d085ed122ae51af401651266e02b0317d09dfc	\\x855a959adaaa5144f40d154cd0c372623bb61ebe088bb6f2c49b40bf46d64b6a9d4eba9f9a0642af9579832157360e11b1909a6500b9a4659a6d4e786cc91004	\\x0c0f5ef25218edba85dd831f3e84586799b4e0e5090ed2b34fa439a8c54b6b43bf14032644d976eba79d314265617a8b773d58c17fc0142d3c0109690a8ca5ca	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	payto://x-taler-bank/localhost/testuser-u4NBhcNw	0	1000000	1580166020000000	1798498821000000
\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	payto://x-taler-bank/localhost/testuser-PQ2heRYJ	0	1000000	1580166023000000	1798498825000000
\.


--
-- Data for Name: reserves_close; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close (close_uuid, reserve_pub, execution_date, wtid, receiver_account, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_in; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, sender_account_details, exchange_account_section, execution_date) FROM stdin;
1	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	2	10	0	payto://x-taler-bank/localhost/testuser-u4NBhcNw	account-1	1577746820000000
2	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	4	18	0	payto://x-taler-bank/localhost/testuser-PQ2heRYJ	account-1	1577746823000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x55dcce3a1782d35b9e39269dddd4a97a562730668130f29e9164dc22f23c2dd8558a96dd16e310ad6b5d0ae0cd4f33c219808b7dcd318e6e85185ea003ffd938	\\x864764cd850c74f7156fcbc0a578f6681614f08e491a3af2019613e469c8bb1b8c5e0cb062f2f834e307ee4255c65a54d83ae2b74aecc7a38de232997e1686d5	\\x1b235e77fbe3e0b4cd54fed3c7636f72d7359995930dc933b2b4777c81a2782e8f2fcf6e75e988323262b95e5bf5a50862aefca193a999e08ddfae0a70266d063088cc296edea692736506b1826828754dba7e1ff3f533ba629339df15594327d9ca4096f5e8d9d70070f683bfba063db2745fc7cbb5f922a558835b961cca35	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\xd601b86c425475275b56f1108efce3b27bb68aaed5a94015b3025e38efb6c3c7e897fdd45554cd436b3a3a013de9af5d3d160387db94b8b13fc9affede32ed09	1577746821000000	8	5000000
2	\\x6349c3b4bbe52e6d08293bc2aaad28ac04f35f5d712f5b90d1ee727d58043ae8172b9c87f7110d78dc60cf37cfc0756725565ae223ea67ce1dc5c43f49ed0806	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x878521b34c67719457b29271049d17250fcd244ff777384667c7e57d12b4dd22d02229d820f260897933707570744308033e40b17958b43605c6d3e8d9a150ee6ee149b1ab0691f137288c8c42ea6032ee4acd84b07d1013dff4ee8fa6627cf28a62dfa1bb12162ef2cf00ccfd5e25d298e78168e7cfde62bb8f7db6d627b8f7	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\x44c1636a61efc3ed1556ed4b3a950660fb9e697c873cbf60f95b9133be459405b604ab3aa1fdad9f454969b7469ddaca5aa517244c4e2271e997663a0dc9a80b	1577746821000000	0	11000000
3	\\xaa56fc1871ad93168096f8c77931bcd4aea5097633401367722a8b5184b3e836484503dbef9d012967421d6de913c9b8a499ca964d5f45d77cfe849f64e39c8b	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x1d3fedf7815513cc4d97dfe05046ba521c5add3e42ad5a8e438a4a13ee4e079359c9610f82983283eb897236fff95b199cfd0a523f0581c50016ea43f2ad6790c0de41380d1d08a4f79655f3075392c657852be541a0d16776fd850b75010d054dedabf8a7e7e37c8ed2e790f64e3799be33bc7e12bc9ace5af7ae57654fcdc1	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\xff059226c0d7504a0b25c405a05aa7558debc68ae57913c89aa892d43b2126b5e6b1af6221b404e5ab9847f13836828fcf85361cde2b0855cb0368f3132b2c07	1577746821000000	0	11000000
4	\\xa17923319532eae0698123c98185c405df4d2f0dad6a8219e514b208b278ff53e3f8e85d309dbedf70441db200777df6380381b858836f2dfc283528dcb4f6ad	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xb45294110b90a6c22792442bf7c2d1a11a80c7a0d3fecedf8f4002099326fdc2dacbcc911d89101353397dfa01a73dc6c603a42a4ba18f7eead3d02d561dd4075c3208a216708d264e9f02020eb347915cb0b85b81436b0fefc47f6b87a5db22b1a71e28fa7f2297e8c6250a66fbe26fc2afe47db139e991d7a52abfff733683	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\x02a847145e25597d64524cd74e4706adf830201efa90a0b8c7f8402298d07dc5f639943a3180e56cd352b1ef8cc5b5ae8e12bda3242465d2c2fc4d3c5262bd04	1577746821000000	0	11000000
5	\\x7285503b81aa22316ad24ad0af6f6fd3f7598481f1e08834c57303634308ddd72b226fadef44aa932c62edf401a11269ca590161bbf6b08d3f974c4c9a05510c	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x5a7a6184cadea6317c296151baa49133125a80409950a05d72c9d126262b7ae063eba6c1af77ec894ed76f90222674ef670b384cbec28e480453563c1eb8f37713485ca71923b492cc062a5d1a9d324ea661245676ca520ec67b19daca10040bfdb1e025e29d9e55ce869f1450705c72eb3f0ae085a046cfd94d5aecc9bd09aa	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\xae20a67e67a5c4375c1adeb099a3a8a4794d6b018c2415a94f67b13a786ae0a79b2e81eab87c90f126c78c410e3269b3317096277dea24e0476822aa79b7c105	1577746821000000	0	11000000
6	\\x50f72ea70665ff61aa8f09a5b97cb7b3e196fa9e02573e315012259b44bc8829f8ae8b8ea66a91d0e066219b9e17c45a60b46ddee391a59e872f63beac9f330c	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x82a5b25ca1a501dd6352ae978c35ed5c05cba8c377387a74c56c2950eab3a916db6ca3ec3907615020c91cd872d3f153c10b69dbc1a477f7874417c4882935e19e5ed7225833c529af3646209864a11767c509793f112942b2f0183472c4270150d11d8366a46e733f99a6ee95c6da0f3aa30a97fc8de54a0bfbdbccc5b7b609	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\x732dc6693a0675ca6a8702ec209859903e5c92cace4b040c0d8866dd4876af851342f55337b72ac3861f48d25e4f969399b4e8354b43411e00e22224abf40500	1577746821000000	0	11000000
7	\\x9abf5bcdca840587761c68771ca7e5430924d10f2f0d922ea84ebae007f708f1f65bffcc11862cd750b279d04de410de7f983164630c5d67506e1f1912a03d5c	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x9a9017ab81e4a5f4970dfe00500efdccd953502a763ba663789ec28d5a9f321ba352d8b24fec88f5a0618d22f5ac9605b5de957bfd74b018bbd6b2ce56676738a8118ab27dbb3136b603e68b8acd25f01904ed866be3bc36569747092011ca9320a759b27d62304b2dcfd0028437df4db09b8986463cc7e20f608aced092f667	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\x02921626b56d164bf521950984215ced1f8e5694c7bcfbece84ae46f935ff4a750ccbcb85829747b88f7bb9dc7d4e7d0e7258ae533a530a349675829641ac10b	1577746821000000	0	2000000
8	\\x66399bee99fc9788b5c6d1e70a2e9f3ed5e09294e15b888d350b56b9b8cf71eeff7ff1228221d1c5fb0d5a629d6d941fc3797ebed591da819ce4811db146787f	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x699ac5d70818cc42b758cf7c7af66b2bf568288e75530216bf100743657fc2be88cb3fdd94bb75656b37118895c640569351699ff15bb46a606767e7bb5cb89f07cad6721d2ddb7261539cca7d43a6edea176eb521ed92df54cfc6b17085171c2323dc73b9c4f957435458f7301759cbed0471c154c045ff3f634b3a07725f5c	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\x813976231f91e6781546d0bdf4e6b6814c6a028faab2b3c20444bf455bc9c37b1654f54dce7e35dc7165b67dc613f2802ab7b995a1e2a7199abced0760520608	1577746821000000	0	11000000
9	\\xd059a7cff1205ae7f3ab16e76737bcc6e6ef3eba6c6b96520d9a52af942e7b30e39d0414ddfe2e5077f1390921c290db0468f079550e611ba8bc4c97ef106088	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x679d1cf83a1923c9eb50ec978fac34649cc9cccdb5d534f596ec4715a32534ac221a5e6ba7b6a8db2d1f5e6e3867c4c637e9adccdd047812017998b840177d82a862c54620ada97a93f0d8b6bbdef6c5b2630db219fa186b7e20d8e4548a48af82df6fea7ca44757f714bc3f42c0734ab06a5d13f065c43813bda4b57e7bb681	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\x18c070b202b108bcefcfec2f42fb0bcd9385ac4180d172720817621f77f8b1d116016b14acc60d77a0b12bc98103f65f149b7920d00531ac48c2f9ca99c16e09	1577746821000000	0	11000000
10	\\x6b699af9a9c555be20700630c65cbf332f598e6c4b5ed900375fb4b8f1223d7250d6d4aff2068c3a4adfec2b6a156950c5cbe6539cc492e0049ae35ace96d19a	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xb255c0dedcf78cdb244d60115972839feab10ee0f66eee26b0302159a0e287f56de8586ffe2779aa92b52fe5b5b8803f6d109f08330d75fe6df69d031e858e9b4b182a9c67fa4c18130eebe0787bc63153e3c910965ed8f7807fd8a62392b94e57794d17455529642da9b6830b58345b80ff20ba67e417e1c703eb9cb55d872c	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\xbc1ae4b40fb8d5bbe00afa4367b243d590f3b7f58f1688071ff880ef449fa939fd30c2a826c5d36495a4e5a8348e24e3e881e3b3ba30e8dff1835084494fb100	1577746821000000	0	11000000
11	\\x86dbb9eb7e6f68bb01b9b0c8492f2f38e960ac156fa4cb739f04be467fe8f4efc5a99d969525a26bd1ea18b7635040cb824e6808ae112296e61fbb25ebc94e6e	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x314360d8c183d47c20dc003d60c1e19259c13cd00551671abd5a5f9db453b02382818a05913a864fdadac7743d311daadbf8540095da0d6ff4b64a8b181316a8032e622cd4e5eaa3453eeb69a72a6c3e2eae1fc80437926cc6e67b1c5fa92c7b06a9c0fdaff65731c3dd5d9424fb8f6e25c0bdfd1c93f24a9d62e9f11602efde	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\xed689bf1dcef2cbb0fb0912ace505341bfdc4b295f1740f08efe38be8e8959f2b0f26202ddf005c91841c2e51723797d84750393da065122c9327211759dc909	1577746821000000	0	2000000
12	\\x36a1b82604f0efb0472bd18ab45f5f718308a99d6545c57af6af96ce09b7bd1ad98e67edd31c634cfe0e96ac4186d628dc7b40035598b7824bde24a41899efe0	\\x535ca90a5eeb58999c713ebb1b8de33387f9736bdef584767dcb73d0827ff784075f99f18626b9056a89a3a8a2db0cf88a61fb869f09331528999eeb09579fc6	\\xa1f622c0e44d5929bd72a67460de4804d9063d114e53d89289c3d26e2304216bfe4c0fff7bfaa57c480e9e674e617fca09c3e4357ed3d3eaae3694240a16cf9552b629ff51bd72dccdf885f978940f5f2cd27f96f61cd92e838213a02f0bfb6763727b53edd730e6dea422285306e15ba2dbbd3ae3b1432a2252a0c80cc8a2c4	\\xa027768548e13d73f45fd6c991fe7aae2212f77a4068b778f6a9241adf6ac230	\\x136485d29d63ba9ece7537630127fe6ee7c68ad8d50fe0011c9b681d348d9c8e226429b097ece6f3f47506cea3706956b69619981e81ed9568fe0f675444bb0a	1577746821000000	1	2000000
13	\\x960557edd2ca0ce0f4a36ff07bc90bb72817721b710edfa31f22f381545cf4b62c4625a5282303f140115d5a6314a1576a75ed3cd9b312686754da6bedcd3f6d	\\xfe4a384b29d332e3d9d303aeea2c9fef4a3f19ee33083ac64e0acca3e266f811b9a1f8f05600a195d236a0091016d131dc9250d9d9624603c7996da36655a650	\\x8f66e56ed40755db277af121c4ce41aa4ee94958d8fd28c892a86e4c6adea810e00a0a4c1ff2db87b6eaf7d3ceee1dff7e675d7e78360ddbf9c770009a348bab2518f20ae54de6a309075ade3c74cb10fb2563cc0d4740b4906115be5a2ba3a76accabc40f48c8ddc521435221a2de7c54df782b5b344856d671ef4b3617b1d8	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\x046e1d4a91a27e1155155a1ac60d2c30acc8c6a3d9c46a8253148543276949c5c4fdd914c5dad8485ac0e9670119c5b0f5e07153dffc523d4301060b4cc0d30a	1577746824000000	10	1000000
14	\\x836c17f27112a69b107b32fe725cc56494e4fcc87628837d1be0be6f69ef0dcd2a8a137aec0a9e2e38fdf3c6ced513e798c19acadfbe91b646fe767553b67a49	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x252e164b87227c7fd87cb6745f273979fdd78feec1ba1a0f8ec92802de675976370fccacc7221dc04789b1bce4fa76cc6ac1a941977503c78fddfa94a5ef32f86717bc213763a6e35b62fe7933e9ac6563eb16c9443bcb3a848c2c58ff7f38cef215efd944b9b125c1be8f9042a21b32f20eb582585a66e291e9d99c1a701991	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\x87da30bd8aafe462077580e5d4b8185014c4163c4577254d6f0ae981dcc2f83d7534f36ee323420c8d1b597c8be46ce9c6a1dbb9a1082b5e2b6a6e5240009b06	1577746824000000	0	11000000
15	\\xbf0e1aee2b7e3cd14ebd72422953080577f901e343b433bb70d482e9235c3f7ac64882d104342d9ecb1382cc52e8d270a42b1eb61f1fefd4e12d8d6ba1d6766f	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x1f78044b31a680c047b68341af6638ba1c8745adbbe520de42ecc6c2d558f44ccf6fdbde23333bedc596c426e49df7d85492bd534ccd327750352eb292bba7696c2483c70827bab09fbae6e692e828ad6881c8cd28f4a7309ee5edf774b3225efe28bb011ec7f344ad954505512fe170c85ff58760f705b1ebe7a715e8e3b600	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\x8686f5b937d1af5badcc629e7f28415b7056c27c05b1c4369e9b4d675573fff59ddf6a3b554209e4b8357d181747c5d26cbaaf88d750db7c9a41800c8002490d	1577746825000000	0	2000000
16	\\x5b294f1c14da07980098bd9ce2ef7c439fd8e058443b8e749c51bfecd07cead67a9435e040d00a627346f794467cec1beb4b5320d61a850bdc09901e8fed340b	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\xa5122f65f289783ca74bc23b386f96fd80a324b74ba39753d14be1cf4da59faebabe6c2a2d2bab873518916f70723090ac34ef441be99717c609a4855378df5bb928b9500bd7f905a8a7b0a1845ef5acb4250d1ed458804c149ad2919407361e86507ce036a2fe24dd4435b31a678258dcb25e7cae9ab555e71a40cdd66efd54	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\x04cff41f7ce21305ea4803e047cb0ed2f5a8be645951b68ef339358138bfe45105063b383fbd588c99bf25c5f1dd8d9295f87d9bfbce5d6d5b76f2e24b185e02	1577746825000000	0	11000000
17	\\x415c2665a538be5c4622aabfff1b3f5014a994e00ac63b39c6d85429ceeb18b80746e1b79344cce4224ea786387862f6be266eadaad94d197b2983768e68281a	\\x689cf12eeab4214b767c5f4a789167bcb8dbddbdf8b18fbe707064bba64162ca099666d3879041aeec6abbe36bb3bf95534c1a12e2b9d1c99d78dce681262172	\\x0fe03455b68dd6f9de84b6a7c8638c7f202730531b402611bc130067e0f42a48df61a9837bfb46bf775afb474446a95bd872eed4f8589e83f821a8b363aaf0ef7f168229dd1ebe218760e9eb0ba151c5dedcbae30a7a71e8fbb46297102d94c162c436556c7cbcada537bc9ebb124db2e88aad8b4fea9801a1e776c14c4ea8ef	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\xfa7ba5fba5f8ced07de83bd0e8a952410d96582983c5ccc19964e191c55aa9e3aa8f686c3ca4dd67f8cd0475e70cd1f8d20df171e6b4a7090373efcf76bd9c00	1577746825000000	2	3000000
18	\\x6c8288c8bb262ad1d15962230c5db7c5195408f7485a0d17f6a1349f8f0e1b8b68368dc98bfdc2a5607a8d1b4e073f5cd87e67027f1386e5eaee4976cf8b196a	\\x999b45838354fdcda3ba5adbccd528273acd2415d1d568833619c3094a4b7539edc30f1ac7cb879ff24c27a2eeb63490302fa03a7063ffadd5e9bf28d0b59c0f	\\x196bafd3a0aff24ca1158d1cf91c0e54e8f9957968e7b8d8e63368f3b5266db49a5ab6ff042814b51d65c386897aea2f4cd3ce160f423669a725607515a859e57004cb91f8b2e86b817ca242abd0cf059a5f54e4471c54a9ee09fa714288a8734438f3c598fc4c718a13246712a566952b823a9da617abb46e980f8d0e1d7e23	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\xd571dd6ff2e8bd9a3fa44f4d13fd529cce19b29c0f727538742e93dee104b31c65d1a662f1af6f7817fe17bddedf357b746a361da1a98e06f15ac7b96f2e240c	1577746825000000	5	1000000
19	\\xbc592601e2b2600f236fd33b242bb0abfc0857a896f3d3309fa1ca2822abb8f121804e164422371c1ce4d59779c9c6c7c875f77d14d59367b33cad6dbc3b9573	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x1b3de8e040c7f8006ec99c51b29ddbdedfd029efd9bacac98d969dedc488659f274aabe9bde4b5d0c8553b1b4cda1272cf0b3c098514ec04d07b5ddb5ab08adcb93318ec4106589a3d6055758344f37547b14146530aad825d8445cb7329887b4108fa3af7fc51e4153fb4cb7450a8ecc4caf15d67c603af273f0aea654ea5c2	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\x2ebc2a36c1e48c569158ae330362a9e9b2677dd6cdfc716458dd5a15cd6a8faaa4abbb697e8652429b9f29e1c6345a4a50bc0c1edf3e457f94bd08f64c13cb03	1577746825000000	0	11000000
20	\\x9b27e80a02c1e924722ff66328bbd87d892a7d2a72c19dcaf1f555708aa78d7acfb2413c7ef9131df8a561bec224656c550efb153d97183a4591f374db0c7fea	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x897d9bf26364660909b8db6464595120ff08735f98f5efb1a9b4c0969d1de7a7bb1e2c662e50a2fad4688c1a92527487f25e1b34abba725d316e166f6605e5d3e7c394fb62037191d72c6c3509bc48e79e79a3ce25a59db6cc02fd48de1b85042d41b6062b1e9c3fdf21b60668e969f9de89277327a5a938a8a15de01796601f	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\xe48a59c6492c71acf87cfeaf7396ee8804b97a29ee1fb63d9a4abc09b2215f05b384b6641d04d9f3f06dda3bbcc2fceea4e16bc3fbc4b1b24323adab26e45302	1577746825000000	0	11000000
21	\\x54777c4db16ccadf5fbba10334ca5fdc405ecff7da648f928543edefac508d7f484d05268f77888a49cc2937840c4300b7885c08902e7858a9b903a7dad6ef83	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x1adbe51b66b2de54f30764aaea2d0616bc7ff5ee8c26325b476e505fd39fad6db461ff8e8d0d71b142e32034ebf053987a2646564d357642847afba84428343497f9f29bf96c74c349176d35f454a044a7f39b98c0584b53f215b1d5a2d4c0499f7438e8c910226b28a25866308ee5ffc0e3e4d9aa4a92caba1e1d82213cbb24	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\x013f0d02e40587e0e2d3ccb649ca635a5f04c925c321b0714f6df220b2c043ad205f8178ec62b8a29821ceebdf90baf1fee8c415d14489ff3830d9557be3c800	1577746825000000	0	11000000
22	\\xee9f10dd4fe3cf7d6b919e314cc5199976adb9944f0c0149c3c3a98eaa4f83cefba13b8d1bd2650bec2c514fcdbb5886e145f913e39cad5d24248572870dc2af	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x9223563c4e3eab323fbf29f173780bbc08112e93956c1a41581dd41ca50fdb6b01d1600ae95a1c6f137c377c4379bcdea4532c0d651a34437f74e0602d7a16fb4bc326b55093b0f8b9c36e59888e32d3aff17c82f36fa9375f1450a22dedf24f28dd87c0a213ba9c962324d949830728cf1c6048980e0f4bf2cc476165bd196d	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\xc53ffb42db4615325a08ba3980c340f08f29e3d9917ffb23062fd2b07b10311be5461d3dc82dd23f5592794e3f9b63ad282ce9839700da58380ecb2588553a09	1577746825000000	0	11000000
23	\\x69a39a887c97c0d615191e81eb32011a2259e882ecd55b543142eae82cb9842e5d4daf218919a0a277a0fbb7938123a0b25698e28fa8bbfb024ee67b0ae1c5f6	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x5601fa430c14c0b1974f90f14a49e754f3e7552d60a71394b30d740caa1ab2a389a7d8029c69a3fed94ba6c5dbdcd161b38d38d9f949bc12d5926da202e7b91bb8848ddcd8299ccc68d47d51a54ef3b4856e91b1006f8b79577edada634ea41fbd2d09f61bc35493380584d3defbc341d573026f4eb5d9294004b38c6b5d074b	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\x542aa38bd8f6b3552e24c7eb4d689d402edd27a323d8738af658caadca65bbbdf430cbcb1ac205264c09c139fcb2fc8fd25b4499de2f9a9f13429e462441660e	1577746825000000	0	11000000
25	\\x2de8d7cd1d377a54453c88a8c6372fead7552195dd04e49e71954d75b6353c6719c9566a589a61c1fba514b26bee6fe65d63bd9ec79ed1acdb8fcd4bb4d3e20b	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x324af7c4153051f2709cdcc6865d83e0095d187504c3f5560023af772b64cc45a8eff23a4c7729353c3338c4c86d6f0f8a775f1abb568538bbb1220f80f69346348770ec5d6683e28a2c54f0911c2521a07e7d9efe0f9606d5a02f341867b8ba746f85c98125b21fd8d4eb1c5f6d832d7c3c7e3348598d0537e973f35f85dc54	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\xae2774286c63fa9311971aa30bee31b05942e61fe08d400b3bdd66009ee47a642f3d59a055767f6242e704358e5867f516b0930a503767d5504cd3e329275208	1577746825000000	0	2000000
26	\\x9b3532ad4378766674092d5e0e3ce98e976ff5215aadf70f0b9cb987fc01f5b7a21bbec85e56cf19576eaaa4f77b244c4c390c6a12a57993c4356528abf344e1	\\x223a7f8133dbd1cbbdc4f80ae31a74e47a60dc8db6d8ca5f0786ba0937a76c6c63fa249ad7268351a5c5f0968ab3c1e2fef4b2a0e4c103bb8145f1b47c2457c9	\\x0e44608f0de51637e8f06d41994536c0c716c6f760d622f3ee3276976613b542f28d1b2ed8fffa580719d875adf0af61901e9559bbed315a865a33a1c7f77d51036907b0906c1b6ca8fd5d9637774d3de180107eae48a3274d5529d3d641620fa790cf39a2b1e4de140cabd2db049086e750d4200a3fb88dfb26df11373c541a	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\x00073cffd3b2b8f9865afa0dd66785c4ece828ee8eca01f948ac6ac61bc60f7290dfd9c51f212d004b124dfd5913db1914740a2b26773d9af477c1a98c51300b	1577746825000000	0	11000000
24	\\xe44ef6c818d3d5ea33bfe8195bebf362c2015d1103f2d0ff6b6ea6247a3483dc931243615934e41a062005eaffe54ebade156beb82875e2685dcfe24fda68975	\\x2a588621e791b8b7cc141ddfbba344535bbc17a39c1863b229868a29158f42e7a0dd13d86273acc84d6aae52e0f94cfd50d0f7f602906f9ba74c8b7bc665c65c	\\x68e7d4cc18dd05b7e466e264649a16d349341adce744180a7832959d4518440c754a89813bae4d1c4960b6c8a6d91b3d568ce52308e4cd16e449e5a3b7249c164e7982236956affd90272d7ef018ac8307be8e948deba343ee67a6ca7423ca3f2ea9e4123b3e2237fa21d3795f24d48d5762acbb7ea1996d5cdbf8753bf05cb8	\\x5763ffa5f7763bd70b627749f93cb8220b3805f18be6e8746d5cfe7e73b9e5f6	\\xe4ae8f4953ee3afc5fd2f7e3fa5fcda8ee1a55fc4c1da0bb7084f2e96b170f82af8f79a277ea22db5026a00c4385bacbe8b6502a3df48c8f6c0a7f42789ac80e	1577746825000000	0	2000000
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

COPY public.wire_fee (wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_out (wireout_uuid, execution_date, wtid_raw, wire_target, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


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

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 4, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


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
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 34, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 34, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 8, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 15, true);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 3, true);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, true);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_recoup_uuid_seq', 1, false);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 3, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 1, true);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 2, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_out_wireout_uuid_seq', 1, false);


--
-- Name: patches patches_pkey; Type: CONSTRAINT; Schema: _v; Owner: -
--

ALTER TABLE ONLY _v.patches
    ADD CONSTRAINT patches_pkey PRIMARY KEY (patch_name);


--
-- Name: aggregation_tracking aggregation_tracking_aggregation_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_aggregation_serial_id_key UNIQUE (aggregation_serial_id);


--
-- Name: aggregation_tracking aggregation_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_pkey PRIMARY KEY (deposit_serial_id);


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
-- Name: app_talerwithdrawoperation app_talerwithdrawoperation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawoperation_pkey PRIMARY KEY (withdraw_id);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_denominations auditor_denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denominations
    ADD CONSTRAINT auditor_denominations_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


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
-- Name: denomination_revocations denomination_revocations_denom_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_revocations_serial_id_key UNIQUE (denom_revocations_serial_id);


--
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: deposits deposits_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_pkey PRIMARY KEY (deposit_serial_id);


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
-- Name: exchange_wire_fees exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_wire_fees
    ADD CONSTRAINT exchange_wire_fees_pkey PRIMARY KEY (exchange_pub, h_wire_method, start_date, end_date);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_h_contract_terms_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_h_contract_terms_merchant_pub_key UNIQUE (h_contract_terms, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_row_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_row_id_key UNIQUE (row_id);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_proofs merchant_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_proofs
    ADD CONSTRAINT merchant_proofs_pkey PRIMARY KEY (wtid, exchange_url);


--
-- Name: merchant_refunds merchant_refunds_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_rtransaction_id_key UNIQUE (rtransaction_id);


--
-- Name: merchant_session_info merchant_session_info_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_session_info
    ADD CONSTRAINT merchant_session_info_pkey PRIMARY KEY (session_id, fulfillment_url, merchant_pub);


--
-- Name: merchant_session_info merchant_session_info_session_id_fulfillment_url_order_id_m_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_session_info
    ADD CONSTRAINT merchant_session_info_session_id_fulfillment_url_order_id_m_key UNIQUE (session_id, fulfillment_url, order_id, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_id);


--
-- Name: merchant_tip_reserve_credits merchant_tip_reserve_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_credits
    ADD CONSTRAINT merchant_tip_reserve_credits_pkey PRIMARY KEY (credit_uuid);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_priv);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_id);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: recoup recoup_recoup_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_recoup_uuid_key UNIQUE (recoup_uuid);


--
-- Name: recoup_refresh recoup_refresh_recoup_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_recoup_refresh_uuid_key UNIQUE (recoup_refresh_uuid);


--
-- Name: refresh_commitments refresh_commitments_melt_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_melt_serial_id_key UNIQUE (melt_serial_id);


--
-- Name: refresh_commitments refresh_commitments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_pkey PRIMARY KEY (rc);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_coin_ev_key UNIQUE (coin_ev);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_h_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_h_coin_ev_key UNIQUE (h_coin_ev);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (rc, newcoin_index);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (rc);


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_pkey PRIMARY KEY (coin_pub, merchant_pub, h_contract_terms, rtransaction_id);


--
-- Name: refunds refunds_refund_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_refund_serial_id_key UNIQUE (refund_serial_id);


--
-- Name: reserves_close reserves_close_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_pkey PRIMARY KEY (close_uuid);


--
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub, wire_reference);


--
-- Name: reserves_in reserves_in_reserve_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_in_serial_id_key UNIQUE (reserve_in_serial_id);


--
-- Name: reserves_out reserves_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_pkey PRIMARY KEY (h_blind_ev);


--
-- Name: reserves_out reserves_out_reserve_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_out_serial_id_key UNIQUE (reserve_out_serial_id);


--
-- Name: reserves reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves
    ADD CONSTRAINT reserves_pkey PRIMARY KEY (reserve_pub);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


--
-- Name: wire_out wire_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_pkey PRIMARY KEY (wireout_uuid);


--
-- Name: wire_out wire_out_wtid_raw_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: aggregation_tracking_wtid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_wtid_index ON public.aggregation_tracking USING btree (wtid_raw);


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
-- Name: denominations_expire_legal_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX denominations_expire_legal_index ON public.denominations USING btree (expire_legal);


--
-- Name: deposits_coin_pub_merchant_contract_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_coin_pub_merchant_contract_index ON public.deposits USING btree (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (tiny, done, wire_deadline, refund_deadline);


--
-- Name: deposits_iterate_matching; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_iterate_matching ON public.deposits USING btree (merchant_pub, h_wire, done, wire_deadline);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: known_coins_by_denomination; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_by_denomination ON public.known_coins USING btree (denom_pub_hash);


--
-- Name: merchant_transfers_by_coin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_coin ON public.merchant_transfers USING btree (h_contract_terms, coin_pub);


--
-- Name: merchant_transfers_by_wtid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_wtid ON public.merchant_transfers USING btree (wtid);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


--
-- Name: recoup_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_coin_index ON public.recoup USING btree (coin_pub);


--
-- Name: recoup_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_h_blind_ev ON public.recoup USING btree (h_blind_ev);


--
-- Name: recoup_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_for_by_reserve ON public.recoup USING btree (coin_pub, h_blind_ev);


--
-- Name: recoup_refresh_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_coin_index ON public.recoup_refresh USING btree (coin_pub);


--
-- Name: recoup_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_h_blind_ev ON public.recoup_refresh USING btree (h_blind_ev);


--
-- Name: recoup_refresh_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_for_by_reserve ON public.recoup_refresh USING btree (coin_pub, h_blind_ev);


--
-- Name: refresh_commitments_old_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_old_coin_pub_index ON public.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_coin_pub_index ON public.refresh_revealed_coins USING btree (denom_pub_hash);


--
-- Name: refresh_transfer_keys_coin_tpub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_transfer_keys_coin_tpub ON public.refresh_transfer_keys USING btree (rc, transfer_pub);


--
-- Name: refunds_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_coin_pub_index ON public.refunds USING btree (coin_pub);


--
-- Name: reserves_close_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_by_reserve ON public.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_expiration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_expiration_index ON public.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_gc_index ON public.reserves USING btree (gc_date);


--
-- Name: reserves_in_exchange_account_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_exchange_account_serial ON public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_execution_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_execution_index ON public.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_out_execution_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_execution_date ON public.reserves_out USING btree (execution_date);


--
-- Name: reserves_out_for_get_withdraw_info; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_for_get_withdraw_info ON public.reserves_out USING btree (denom_pub_hash, h_blind_ev);


--
-- Name: reserves_out_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_reserve_pub_index ON public.reserves_out USING btree (reserve_pub);


--
-- Name: reserves_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_reserve_pub_index ON public.reserves USING btree (reserve_pub);


--
-- Name: wire_fee_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_fee_gc_index ON public.wire_fee USING btree (end_date);


--
-- Name: aggregation_tracking aggregation_tracking_deposit_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_deposit_serial_id_fkey FOREIGN KEY (deposit_serial_id) REFERENCES public.deposits(deposit_serial_id) ON DELETE CASCADE;


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
-- Name: auditor_denomination_pending auditor_denomination_pending_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.auditor_denominations(denom_pub_hash) ON DELETE CASCADE;


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
-- Name: denomination_revocations denomination_revocations_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: deposits deposits_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: known_coins known_coins_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_exchange_signkeys
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_denominations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denominations
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
-- Name: merchant_deposits merchant_deposits_h_contract_terms_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_h_contract_terms_fkey FOREIGN KEY (h_contract_terms, merchant_pub) REFERENCES public.merchant_contract_terms(h_contract_terms, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_id_fkey FOREIGN KEY (tip_id) REFERENCES public.merchant_tips(tip_id) ON DELETE CASCADE;


--
-- Name: recoup recoup_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: recoup recoup_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.reserves_out(h_blind_ev) ON DELETE CASCADE;


--
-- Name: recoup_refresh recoup_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: recoup_refresh recoup_refresh_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.refresh_revealed_coins(h_coin_ev) ON DELETE CASCADE;


--
-- Name: refresh_commitments refresh_commitments_old_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_old_coin_pub_fkey FOREIGN KEY (old_coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_rc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rc_fkey FOREIGN KEY (rc) REFERENCES public.refresh_commitments(rc) ON DELETE CASCADE;


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rc_fkey FOREIGN KEY (rc) REFERENCES public.refresh_commitments(rc) ON DELETE CASCADE;


--
-- Name: refunds refunds_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash);


--
-- Name: reserves_out reserves_out_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

