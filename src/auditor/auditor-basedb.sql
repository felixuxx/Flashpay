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
    irregular_payback_val bigint NOT NULL,
    irregular_payback_frac integer NOT NULL
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
    payback_loss_val bigint NOT NULL,
    payback_loss_frac integer NOT NULL
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
    last_payback_serial_id bigint DEFAULT 0 NOT NULL,
    last_payback_refresh_serial_id bigint DEFAULT 0 NOT NULL
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
    last_reserve_payback_serial_id bigint DEFAULT 0 NOT NULL,
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
-- Name: payback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payback (
    payback_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT payback_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT payback_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payback_payback_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payback_payback_uuid_seq OWNED BY public.payback.payback_uuid;


--
-- Name: payback_refresh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payback_refresh (
    payback_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT payback_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT payback_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payback_refresh_payback_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payback_refresh_payback_refresh_uuid_seq OWNED BY public.payback_refresh.payback_refresh_uuid;


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
-- Name: payback payback_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback ALTER COLUMN payback_uuid SET DEFAULT nextval('public.payback_payback_uuid_seq'::regclass);


--
-- Name: payback_refresh payback_refresh_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh ALTER COLUMN payback_refresh_uuid SET DEFAULT nextval('public.payback_refresh_payback_refresh_uuid_seq'::regclass);


--
-- Name: prewire prewire_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire ALTER COLUMN prewire_uuid SET DEFAULT nextval('public.prewire_prewire_uuid_seq'::regclass);


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
auditor-0001	2020-01-17 17:20:20.303823+01	grothoff	{}	{}
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
t	2	+TESTKUDOS:0	2
t	3	+TESTKUDOS:0	3
t	4	+TESTKUDOS:0	4
t	5	+TESTKUDOS:0	5
t	6	+TESTKUDOS:0	6
t	7	+TESTKUDOS:0	7
t	8	+TESTKUDOS:0	8
f	9	+TESTKUDOS:0	9
f	10	+TESTKUDOS:0	10
t	1	-TESTKUDOS:100	1
f	11	+TESTKUDOS:100	11
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2020-01-17 17:20:28.301015+01	f	11	1
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, withdraw_done, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_payback_val, irregular_payback_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, payback_loss_val, payback_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\xc0a4cc60cd1c3199884faeb58168d6a1caa58838713c3339630e80cb61e78f0ee6e742e7d3ceaad1deec91f4ceb1622cd3a116ddd817ae5e430b8992f1c6aabc	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579278013000000	1579882813000000	1642350013000000	1673886013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7199f4d40c78b821d7b7a053bd641b044a8aa5b4e069ddc7c9ba18c21d4c2089aadb86de6893df7905f647cf5f23ccbf7b982f4cb10079f04d36f1fa960766f4	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579882513000000	1580487313000000	1642954513000000	1674490513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x946aad5c0db289a803d2120c7f5b0af0784751a89af26a362647dfe0ed661346387fe72981f5fec8b9a1228b64109721a37a7ec3ed8bd3ba03496210df77113c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1580487013000000	1581091813000000	1643559013000000	1675095013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b5b04501e3177de9dbc736579c5383880d47869c5d9e1e8742a02936c4ef2ddab1bdf91d6beeea4a9af9b05ee780669821c8a7e6da6daa93bf7e8026b36cb47	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581091513000000	1581696313000000	1644163513000000	1675699513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6f89f15d916e7af9477cb4eba29a5db52f43a49f85de54d2c4f1411c1813ffaf062b24b402d07c89f0cfac336d73d4a54b9376f9ee46a30be41f0edcecf28455	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581696013000000	1582300813000000	1644768013000000	1676304013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9d6c22d942f02bc626825e281ab842d6ed2385e169bef481f2db6ddca1581db48ebe377e3e967649020a4d3cdf9d878c631c3492e0df0c38f126e01a60d850d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582300513000000	1582905313000000	1645372513000000	1676908513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5daebb7b1f8b8b17c00b33595db4758e33c0e5d92b536656681ca6840d0bbfb8fc2b11e1f32c31a762b111101fa28970d0d07338058c77b4ae34adbd3f7a9ac3	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582905013000000	1583509813000000	1645977013000000	1677513013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b3259157369edff85cf30fb9b60ab6f7167c4ca0ac28b0259e60a481da86d2e605ad27e44845d99abba8288053b9b55335886689693768ed9df4aad8cdcddff	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1583509513000000	1584114313000000	1646581513000000	1678117513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xee414acd04f9d40f39c64f3a65587fa37c442c2667c8ea027802b0306cdac3cdab5693c394cc6c4e4f24e8680fe1780197fbabac8bb57a37aa6dbcf9278f5835	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584114013000000	1584718813000000	1647186013000000	1678722013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb81e5303ca35d3b8abb7f93474cd3c69af40cfdb5a7290da58e173eacd258f49826a2291d384ea1845fc12317954c51e6958feff73bf28a6ac1f7594a0278566	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584718513000000	1585323313000000	1647790513000000	1679326513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b83caaf6bd6db2aa8ba1cc42495581b79de52af4e831f36d72bfa890164e42af2b9065537609f25dba9d3524a404bb3fa773c89ef030c17ef52abc3d8c7160f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585323013000000	1585927813000000	1648395013000000	1679931013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x84d5891f49a4dd207ba844e76b9e634dac2bb841dd6a4214ce0e97a8fa91b80bed4cfdfb7f46b8b6b3b2ca05e749837ddfbd714fd1b06de8ddd1f24e588f9fae	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585927513000000	1586532313000000	1648999513000000	1680535513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9076c659900d7c3c0190b24bf8c7005739bac299e04554b3ae4164b96e4c1a8cff50f81f89ecf9bb48e1886057f8682afd2d19f9513317ee32c15d7ce4e059a5	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1586532013000000	1587136813000000	1649604013000000	1681140013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6689286e0976a44f7a05e27ed0cafd72f0e45d345ec9f2e64b24c1ae8f5406c103d8446400a897762b200ecb49ea13071214b2a43397432a2c81d121fc9468db	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587136513000000	1587741313000000	1650208513000000	1681744513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33bfc7c8068d38eb5e89def76e2eb0736a891ed2360aed0d0c4307e949ffb3c4b851a3023996a91cc37b4f54f49e2de567540e478bb348df436e6cef42dc4635	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587741013000000	1588345813000000	1650813013000000	1682349013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x004453efd39dda910610b389d1286e4d56b89d2812573d2a93ca12e1e87fe0f4b07903b9623cba50b13bc1af4abe1d0050d704c7c57810100b80dc03a2a0ad45	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588345513000000	1588950313000000	1651417513000000	1682953513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d4dd53b5811d0b56bf861b8ee116be1a9554ff9f0591e97d96a18d14276c2f1bde6b8ac5c806fa9c77a0f7322bb68a54ffd133e171f2ea3b14816e28354eb8c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588950013000000	1589554813000000	1652022013000000	1683558013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xda8164cc7e5fdce4aad848355065e4a00121c584823bd1a10d1d3a52553c4fdb6ec5090f386154a11ba32d495121daae7026aa4d1837c25d687a4347295d8bf8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1589554513000000	1590159313000000	1652626513000000	1684162513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe1cb7d87ba4338395fae30133ff074f2e6c2920027c53722b95e0865faaf9b124a4dec96f045856146d4f750da9abcbdf016eface156301b1459339fbee6ce6	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590159013000000	1590763813000000	1653231013000000	1684767013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2fb5a10cf7ea5600437d069994c25f81e2a6971eb8e454a33cc06cc6c6448baace151c953d016028571fbebc8b1fec1e57872a23d80863f07c94ac66c5f959d4	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590763513000000	1591368313000000	1653835513000000	1685371513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x75781d0fdc007ec92d93af400ee09a52e6fa3d8d39bc19b6f5f05b853d217437c34b98340f14cd50a0509fca7557e8ca0216fbf11c87d7faf9e93389b0d85d24	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591368013000000	1591972813000000	1654440013000000	1685976013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x04c0b3c6fdf0dd5d1e8aefe12eab49bcbb26b94535c48fbd896305000d84d51aeeab50eebfa6aee03a103c3e3f7e04e80943aea43686e2b2c526936a350395b7	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591972513000000	1592577313000000	1655044513000000	1686580513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca925235b8445219695fc33a7e18aa689a47ea5319d19f45a6900d55e3d8e75f25f73fdea8bc32546a16ea7925beca49a7d022aba783a59aecbd4a799e57054b	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1592577013000000	1593181813000000	1655649013000000	1687185013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb48af619134d958556e3f242f0be7629c1879ff29eac31a1cec20c438349f1cff8a91b2bb4db6300b7fd7fd1c52614b3141e59ee2442896eb2a02965fa917e1	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593181513000000	1593786313000000	1656253513000000	1687789513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e4a8bd91276876b5a1833e9e979726a6573e0b06c57e141c5d1a1bc7ea2a556f17e9043e38ef405ed2f03de7ea465118fce01d6f845947ce7ced3d459aa3965	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593786013000000	1594390813000000	1656858013000000	1688394013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x05cda1832563e70de4df363cb0e514c377889ca39cbc4b25616a538aa2b82654fd42f4b7b153f874b4f050011808c377699bf138b4e8ceef2d2e568854eddd98	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594390513000000	1594995313000000	1657462513000000	1688998513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7dda4de668e81454eb8696b807d9f1b195270b4c4b3318072375be5352f4b9abd6e869fee8efb77c7d531f5f87ad81ea2e431776bde7141aeb6885c313d36b4c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594995013000000	1595599813000000	1658067013000000	1689603013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa885cf445e6c071c860a7f170d6622797893bedb5dd03797f8eb14b5e94995c4fddc41949201cd0aa7050ae2df5c483d62d8ba81a615e22e07d9b135b2204496	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1595599513000000	1596204313000000	1658671513000000	1690207513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x203a38b7fe2bb50579157a40c972f55fffae395615c25684c61c7f1561d495112f5f5a05ea72ecc98b7bd5d1cd563d0cae79817fc2bbeec56ef46890373f0115	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596204013000000	1596808813000000	1659276013000000	1690812013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ed49e07adaad6c5d5e922ee71d7524692179b5453f63b9417e9ec9929661180ec7c0752b1aeaa2028373272ae27313954abf29ecada26ae1933ae503f83aad6	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596808513000000	1597413313000000	1659880513000000	1691416513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f3558d7c22fe817ccd6feee4ad8c357ac0088f256d635e72fc6a0dec6265acd3240b3ed3f4a0180b703e38cf566db03448a1daad8eb7c57316c442cadf22a18	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1597413013000000	1598017813000000	1660485013000000	1692021013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x249c55b929bb9d9ba1f38a6574743e5fe2d989f8d174e71e3dc2b5e3e36a2d44f732bc291ada2de5a057b5199f04d6666437016271a835dcde98489792ac1c1f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598017513000000	1598622313000000	1661089513000000	1692625513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x110f4307dc98896f490f698b062775db76f5b580793ffc1afca945b82df0d6663a4a2afccff1d18e404ee1af0ae0205a3407649a3552520d133bbb7329fa9bcb	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598622013000000	1599226813000000	1661694013000000	1693230013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2025dcd60b83518bb1458bf0e29b4e99eac705ad76f5ed755038896cccc2cb57a60d82515ed37b008502f212b8142bfc191d7a19b048a734060d02111efbd62a	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579278013000000	1579882813000000	1642350013000000	1673886013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x164795506d1092a8aac5bfac433af1db9a8ed12174428cdc928444e81b2c91ce50a21a212fe7946fa33f69227324eb46d6c0f677b6799b33c40ff54647fb2340	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579882513000000	1580487313000000	1642954513000000	1674490513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf801b473310c753de07efd34e2c2f53343381ba90954131b1038126225835c3862a412c4f066943613101737fcfaf85a43012c900609a30a3d427f09c8b213d5	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1580487013000000	1581091813000000	1643559013000000	1675095013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x12b9429ea20364676f0d81c18795542163ef599354021213359919294cea476eee7174ad59fb3f8744a18d35279a958f19bb2cf7ac196d71fb70581583d650b1	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581091513000000	1581696313000000	1644163513000000	1675699513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0f173ef0f70749b795c9abbf916367354e17920b76506b4e5ed73390f3d59a6776af7e365ffdb6e9be71d70746bb0989af644d4605871cae19b42dc6dc3f2403	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581696013000000	1582300813000000	1644768013000000	1676304013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5835974715e2a724ca934628abe5ffd4fe0bfe7993af448e34e6bb152f6e3169cd770d330c090c34a92d042d3dec2183ae94d7d66d72da15784ca2ce65efb9b2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582300513000000	1582905313000000	1645372513000000	1676908513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa74370c723ed7fee52c7ff93b53aa59fd0a53293c5b14410f98ddffa60ef44679ed5d5fdc6bcd1ab00c2776f88220210f4e2303ef0afa1252965d34c5d0cfdeb	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582905013000000	1583509813000000	1645977013000000	1677513013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcd5f9772f9614c36e67a3e7a71faefa16309c9808cea19e67a805d781dd5218b6e97eab3ed35113185826bdac1ecb0b2c58a465cf6559373e009354d17564418	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1583509513000000	1584114313000000	1646581513000000	1678117513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xab7a53431e2820976ad02c1bde28d11c23e605cf18ecfe709d8938986eae659ff5c6392194e04056f49ce40163d6956bc8f1fd07bf265bf0c0549092746c6080	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584114013000000	1584718813000000	1647186013000000	1678722013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8b61c2308fc78ad0fdd7344b9e6b0cf7d1ec2a73ca8bbb829778dc9474420b4e8f87b4903429d4ec76b0e76ec85f728a243b337b27b700fae0dd744e5725b8ef	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584718513000000	1585323313000000	1647790513000000	1679326513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf0f3e966f92588b81ec6524fef30768960e6786cccddb06f9a0e378c4e6e1899ed5349fd49e8c3b9bb0e89e169c6d8440c8c2ccfcb70e59789d1970a927a70d5	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585323013000000	1585927813000000	1648395013000000	1679931013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf439d33b93442aa6ae278966b3f4584339331358385a323ef89ff1ebdcfa9b18ef1dc5d094d55f2685b20d2591311c1627f6d8132b30ee535fbfdcbdf0b9f885	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585927513000000	1586532313000000	1648999513000000	1680535513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4dff650098b85f7e841666a81153b9af4a8b361a5f5c637c616d52f0ff4827f6ae05eb0babd1427c0ad7d3bef2729f3fc2e369cadecee2dca9717e23ea99a207	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1586532013000000	1587136813000000	1649604013000000	1681140013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1b30e27422db5e6d46709487014d781af47f91aea8863e42366d294151c10e2e0d6455126f942f699320dca9265c9a059f03fdbcb76a0c68f844cdc97c40e6ca	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587136513000000	1587741313000000	1650208513000000	1681744513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb93c84b0166cb88dcb951cb47ff29a880d5728ae0283025ec7f16fdee730f9fa293c56d1c411b0e4f143c488e54e3bd9e565e2dace4b0c5c8d9c775e28884165	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587741013000000	1588345813000000	1650813013000000	1682349013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x49b0621460fc33cce19de38e6fa05dc7bb9776318caca12444d90edbeccf9336cc7e4c4ba996440ba75d2f49eb698b0301220b8e5b97afc299cfd97f33289e63	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588345513000000	1588950313000000	1651417513000000	1682953513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb2f72a7ef7049b6532fe6fb6132ba7ddf8850f4c0740111b8341b1a6dcb5ca10942a82c851a592e6d61dfa1dcd99899471b43d027130723424108ab4fdac4a2c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588950013000000	1589554813000000	1652022013000000	1683558013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc164651afda19ec426e1121d105489ee30dd7347cd302324a1c5d21bea6b0e036e2c36badb8350e3814ffd145c9f7dbedf4d8d315a4149e183d110c3dc411238	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1589554513000000	1590159313000000	1652626513000000	1684162513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6d24d98c365cabe83a56e8ef1fdfa8534c10bda487b0fa9e7030ed3f3c2698c7dff0f4ce47a82a02f9c0fe0d4e9ce8316a7e89de27f26f312f3577fd7a4b4625	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590159013000000	1590763813000000	1653231013000000	1684767013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5ec54fdc51ffc5c026cfe5a65e79d8be0a77e5c90fdf61febfda0b7aaf829dab7f73a5bda1078e0d0d1b4c7d822508c1c1e6eb159a0b3659521a4968aec5efe4	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590763513000000	1591368313000000	1653835513000000	1685371513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x858faf4614d32682cf68b7b0b509a79d9e58db77d86b185d5a4099fde205ccf38476fb0fe40f58e43bcb17d7e04cfaa9be48cc79be3f406bd21e5acc0b04ecb4	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591368013000000	1591972813000000	1654440013000000	1685976013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4e212717874855a75747195d065659c0335404cfa72afeda91934cf7bacb1c9e23ad1834f974654de70f48503c2ca9c7c5bef348ea380f7da0121c73bebeff09	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591972513000000	1592577313000000	1655044513000000	1686580513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x48623e896241d3fc55ccd058438c24bf0c6f2df883da567e5007c38c9df352d15968cb6e169011c59aec96be8b34f35fb908f4f933e30611950c8183c1781d8b	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1592577013000000	1593181813000000	1655649013000000	1687185013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc17e9d03f944a351226b86edf9b11916d74dad32a2fff60ad8a204ab954cdcb134dbd2d5f96a3674b301f5e21a92086d4d69e8db257994b94dc77dd11cd333b9	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593181513000000	1593786313000000	1656253513000000	1687789513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x166c1bab903003c743dafb711f83836460335646a40e88efe08375d792ad1ba64dcdd06ead4bec40aeef91ce2e628e357f31a83d04f5a983a10dcf97eb3b4ab7	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593786013000000	1594390813000000	1656858013000000	1688394013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x966f1dfecdf8d21f6a2dffbcb623a34357a1dc9521589fb731212928c1007ce59ade4b2ed066f8e96c9b95f7979bbdff4473351b638f42a9e3acaf3fd2161d14	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594390513000000	1594995313000000	1657462513000000	1688998513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x47999b0e0c58bac323e08f39c0ec1019c146412b350fbaf06f9de5785e1ce7682b081df418f2ea0d30b802ca5efc04424be3161f85e5a79e41ea118ec6ac0e0c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594995013000000	1595599813000000	1658067013000000	1689603013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9495aa386d399d0201424dde4802e1a8cdc07bb43dca0ab026dd9b7b66ad1b4ef78dc1e7d00dbba4f834eadd192b8e2c790e175b3edf2c344cb252e977f57133	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1595599513000000	1596204313000000	1658671513000000	1690207513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbe9745f6dacfc21c7f7514b947501fb0b4ab4f16e8f02c0734eaaff66df69247224b745ac94e1b9712fd3abd0161e134487f5cc6aa4504f7146ccdb9a5e60833	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596204013000000	1596808813000000	1659276013000000	1690812013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc30ceaeb458fb37d16ef13d88238480715327ac112f031c029bbeec8aeafaaaa084ea816ae428791f35ff1eeca753a05eff05ce96d189a83632d951a0e4d7cf0	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596808513000000	1597413313000000	1659880513000000	1691416513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1df880f6276347ae2edd0905d7d70f1d3a9511beba6d80562188298ddf03c738d83a14041e5f4203a71c3f0614976c13b159b5b4f19e99ca4e22b7437dbde241	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1597413013000000	1598017813000000	1660485013000000	1692021013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0e6c37a86b643cabf7cec4d99164d515076a5bf9ae6103fcb2d3ed13355ff08f9136bdd94af54abcdd6492226bcd934448df0ab413112551a5b46421222a624f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598017513000000	1598622313000000	1661089513000000	1692625513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4eebd3ee0179adc86598f12546cee9cafa0b6ce58467606336a5ff2e4a6f3718eb8e738401f2fda1dd0057fffb2224803262a8aaab63e6e798645a20e4b07dbd	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598622013000000	1599226813000000	1661694013000000	1693230013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6ad7b1dd2766e12135211541fcc37aa4a1cdb2881d276afa538a1e7b88a4397a6d65590048d8744bba37a3519ad8878b5e9a70ba88e46c003fa05444f9e0d345	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579278013000000	1579882813000000	1642350013000000	1673886013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4ff06c6367725ddd876379ac8df92f270b096c588157241f3d0addbb0b37f2ee0662c34bc94356dfc0fd947eaca37bbfca1e5de7fceaa3d59c70cda2518ce94d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579882513000000	1580487313000000	1642954513000000	1674490513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf366683811b32bd5b0b3e6f485bd8db26194d533b4363f6fe38775ffdce53cb979fd702c240fea51a02cd3503d5b72ef7f814ed9b93ee29176c7088004e921e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1580487013000000	1581091813000000	1643559013000000	1675095013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x907906173059e50a23e944694aa039f7a355c1f9e8126c05a53dcc36d5bf63c4315cd7a0cc54beac31cd3148fa7568c27d3a67247520672bbe67297933a9f477	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581091513000000	1581696313000000	1644163513000000	1675699513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x080614b1f824417b253241fd17010bb1d2e974728382c1457277e8e1eba95e0328819671e6cf631f94c4dad1289125ad8e0cfb1c5111c2847cd3688f1aff1f14	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581696013000000	1582300813000000	1644768013000000	1676304013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa8eebf10341fd4e062ac3df5719bd5907ea5e451bb8ead98c0be7b056a63d4caabc133f8a4401e02b53b8ef4aecd5b901603b01618968bea2b40cb11fe1adac	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582300513000000	1582905313000000	1645372513000000	1676908513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd6befeca5bc1bd4feababe1519bb047e8b1baebb97fa1fd30715f78d289daacb52c99a3c4c06553a5cbabfa1380404f9bcf32cf25e82aa7da121c0a067d06f6a	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582905013000000	1583509813000000	1645977013000000	1677513013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8562ae3d89196f7b5848cb452221af076fc1a67a0fde81bb505badcedcd181a40588ef3dae88ef647a0e018b35a2a5a768c331bb26c43bf2132813d7ac3c78c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1583509513000000	1584114313000000	1646581513000000	1678117513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdb173b48494a8a6c9a19e51be8eee39bce21db9ead1197f7b8036e7302dcb1323730c97e1afea079d6d579856ff44a322fd24b60b22cd4bbb75676eff162572f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584114013000000	1584718813000000	1647186013000000	1678722013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x67dc457b2b48ebe1dc7a9025646a8d233663cd678166c642a4d22360a0a6c8f1c4d8bf6be67056bb246958f090f18fc3fc06c995a9144a9a4f828b4045e3f976	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584718513000000	1585323313000000	1647790513000000	1679326513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76ff55efee357cc1bc87c7e2a0da31f887813fefeaf5878c53b9abcb073b43b70ddd888d0226b9ea8a5fa0b626f394e7bcf44a703b69f722fdc15d74edf63885	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585323013000000	1585927813000000	1648395013000000	1679931013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c444b110bcc36d9e5b3d41590293d9d9edfb5166befb29913bf480334a6fd3d5c49cacf2bf4eb308481dc40d228bd5a857d4dd329403703ce62f36656caaecf	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585927513000000	1586532313000000	1648999513000000	1680535513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x05be3c19e581f11e76f04a14973cdd38ee18d9e1906f3eeba187ea710f6a93f69d7f5189ee868736eff2d1b5e8ff02096c2b6eb63ee726185d4bd726425f5112	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1586532013000000	1587136813000000	1649604013000000	1681140013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c2cd476ff80212884ce293fdafaf8c7bf144933caefc62eb97eee385f0ffecc1e704408f1226341cbc34c84d56fe8353ea41f18748279560a06ca525a5bf86b	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587136513000000	1587741313000000	1650208513000000	1681744513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b0d53764632303e624802adb7b07a05f4006cd0cca3b7ed0bcc9c88d39cd43dd6b4d9edd2faa24b94880325cf09dfed616921a0b99499a38c5f90904111b181	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587741013000000	1588345813000000	1650813013000000	1682349013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e0318b6807c41dcbd80d2f7d91489c41e9602cb8a76e42f56305aa4e368614fd1dc51960b025e53dd57e122eb3f21ebe4900766c0e7b2c8522bcc5b6586aeef	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588345513000000	1588950313000000	1651417513000000	1682953513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ba6a9bf4078811d460f6bdebb7af4af74e6166a1853b1c12ee9c69029e37dd3da111e374197910c634bd68356bedbda53f871a764d2fc3f59c63185d187f538	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588950013000000	1589554813000000	1652022013000000	1683558013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x844d86e5f7e1f92c507c5750485eb905fc23a5f51e21975355d17b0d8ee93b146b425f3802547c78167e91af5e5140498bfee5ba588e2adff19fbcf00fd38538	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1589554513000000	1590159313000000	1652626513000000	1684162513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8301f919c79e03120463f727daccf47748fa05f5765931bda553317e72f0828a501c69ada577aa0e75a69162ef99b738f8a5a0ceb6eb2f1b2dc0486e870f6f7	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590159013000000	1590763813000000	1653231013000000	1684767013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0aac6fce47dceddc4469b2a954174724649167a08437679931a08d127c2875942afa8b2c056f743d294c4915ae3992eeb9ef04655c9e6619304a11835594dbba	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590763513000000	1591368313000000	1653835513000000	1685371513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ff8afc701a46e2777b9059fde81bc106bb48d7925adce003027c441450667660f33d7159e1eb7c2f4e47eb9fc70aa5bf6d0fee0d82ac801864886d46e03d554	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591368013000000	1591972813000000	1654440013000000	1685976013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xadf8745a086202ed8f7da9b1ef5657e742db7ceb06772fe8547ebc83604a113c9e8adc69f610a05720e3293497e642735d62a2655594830450d449bf6911b1e5	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591972513000000	1592577313000000	1655044513000000	1686580513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc964e05e3078aca4aa01613b99a0df0c9a9d8b202b4fff629684e047ef2261bd671856acbbfcf0c24a8fa168363fcfed81bda50fa9bd03a911e2be2f29112510	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1592577013000000	1593181813000000	1655649013000000	1687185013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50f2ce495e15d185a87524d6e0d53265332d9bbd9bb907a1cd8fcc72764ebe4d0792584413541fbc1cba0ff359a4848aa0c35fb27d2fcec7fa1ad37d02cd608e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593181513000000	1593786313000000	1656253513000000	1687789513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7c1ba60bb5f45f0ed4cf49c72d5bda4b767b7ed52ae9fbf02bbe8dead9aab6b1ceb054b45b30d97bee5a129385b474ab8c9cf3b22f386dae630881198005374	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593786013000000	1594390813000000	1656858013000000	1688394013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x93d6127239769e47a8202e47badda8dae2f2ac7cdb1ef26bb1f20b37b13b4f41be7308a71f97de5d75fb0634605c9a0c9104eb3ba123fc789be816fd6a06e24f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594390513000000	1594995313000000	1657462513000000	1688998513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bfb4fae0f60e94821c458d732b87442380c9d3ce6b757df5f097fe44a9f8f09337a1b2f08393017a5aa9eb41ab1862410de3508867e679f7d23b5e49180704f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594995013000000	1595599813000000	1658067013000000	1689603013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2bc3df7abcaf02abdec08c96ffef6c3b3ded03be36d28aee5c4ae4b35dd70050194847d089d750cf6428f742c80312e22c86d9ef6f7ceb2a465560629eb41922	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1595599513000000	1596204313000000	1658671513000000	1690207513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x43fe86d3e900ba8d08ddc2d4855d6b3fec43ba2792e71511078a5c847432f7fd267e1bc46308098662828c4af775ac48b8d07db40d7ee55f2e1ce356ee5be9ad	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596204013000000	1596808813000000	1659276013000000	1690812013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x34a98b291a5dcb11a832a2e22782de06035cd9b1a0253da8636c104ba287bad0f6bc22f43e6b4cada34664ca233bb8290c8eab554d1076614fe44b21e2b0c4d8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596808513000000	1597413313000000	1659880513000000	1691416513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e41216fa56077c1e4fafcce45dcd8f818813dbde31f50326de33cd05eef94c707e3f31c3a4d503b167127db95fe0a4dd3c4d87a2ac69e141256802f13975542	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1597413013000000	1598017813000000	1660485013000000	1692021013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x49411671063c5bd1f5e36ad282076be596918d0e23f6902853b1ab33527834541abd26b85d15a1fae43b7447b8c7c59ef970b322c566d20127c77e7f640e790d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598017513000000	1598622313000000	1661089513000000	1692625513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9dcf7df28be2ea9b3eff94c00927c850d0680998dc0de9e3e8a3d18a7246050b8031d316eaf72c151b354b2796206707fbf56ffc07c09531132ea89f78fd9ba	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598622013000000	1599226813000000	1661694013000000	1693230013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x044ae13c4b2b9817abbced7150b38416a6e4945723ed27d7c68316acf8c52ef33e05e2ed66072f239c64215c02801e9b2862793ca0f5cdec5a352cd5d43790bd	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579278013000000	1579882813000000	1642350013000000	1673886013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc86839aa386bffb1ec42fd9f000dcabf16c1604668aa1c2839e2d411935bb245757da9036ecec879191b5d2c5e083b6831dec62fe39435fe53acd7825201e788	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579882513000000	1580487313000000	1642954513000000	1674490513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbf72aec0845e8baff66bef070712176a31b33d5af25a2864853e587ecbc93f3e5ceac0d17c9852e6123d4304c115d0af4068bc5b07bb8c6937b560466a7f8d09	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1580487013000000	1581091813000000	1643559013000000	1675095013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0c009267341470b903487c4c008a5847723e40ea3ee2d8f848417b10a754b98e9f2724f9023f517b5ba2799ef9603cc28b40dd7c4cd575ca67a7fec136ec6c1b	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581091513000000	1581696313000000	1644163513000000	1675699513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb3401ed87343dbaf374b554905bd859a7aa302d74da814bcbb420293099bdb9c048437e665e60ee76070762b6863f8667a09eb29748dda79e743aaa06a7bf93	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581696013000000	1582300813000000	1644768013000000	1676304013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9267b8718146b2ade31a2d27f5138922617ec33c6b6743b9ad1f5897253114550920049684099ce11839336dc5aea6c3935f9837245280aca10cddb947d10874	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582300513000000	1582905313000000	1645372513000000	1676908513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x94b6bef952b8dfc9684adf70e92f02b2e80901bdeb085c2a3e48908ae1f2361fd393fb56526ae379e05a94da11db44ea390b36e4b12869ec2ca312727e1bf676	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582905013000000	1583509813000000	1645977013000000	1677513013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x600701ea8e8fa84e6bd64dbfe01f3d7f7342728dbc33a4ffffa3e38d5e6cade987d0f5f6224bdcbfad2372c4b3ac0424c228ede6768b36bba76156bdae75deb0	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1583509513000000	1584114313000000	1646581513000000	1678117513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x38c521a322a48f597505b3c3d7f79dd5e27c5466fed85e7986f158a5002e28194b88f4c0aaf3f8a6c24e56f22a7b426717f4560244920bf7979f430400a2be03	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584114013000000	1584718813000000	1647186013000000	1678722013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf5c9ed9db87f58556819cbdbb0a307970dcce0a9a03d4d4dbfc71003337380c1462dee16656841b559591ce215f355df8ffc3d1fdc31f895a9a1166cde2a1756	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584718513000000	1585323313000000	1647790513000000	1679326513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7de69f8fe3fdb4131c4c025916ff6b8e882ea8e4de2a6c9d6b56e9ea45d2b1c2af674f5d1f11c62d16881b21863b69f37075563d33a410535cb510b6471d54a6	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585323013000000	1585927813000000	1648395013000000	1679931013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa06ea98b9ebf0064ec0bfad08aeb8956a253f93ff81d21368ecdaa0470243f4a915b9f85047f1c95d0785888e092f3efe5df3b88c2baed6b4197cf85f9ed1183	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585927513000000	1586532313000000	1648999513000000	1680535513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd37aaa9aee93db3d83639d1fc1a759b498bc132ddc9672c4155358e3c48a2b2c9e7e6129ce6c83c464626150b6b21ff7dea8a8bd495b2d1fa468822955982189	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1586532013000000	1587136813000000	1649604013000000	1681140013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e57469427252d8d8f63e6827c7dc89e67008b512e5912f428160fde67edb43e07af9bce02e1a41250414db753daf0a35c6d45b9d6c85ad3424753a0e32eefc0	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587136513000000	1587741313000000	1650208513000000	1681744513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaec8911a5eaf4d7044137d606e9e132888d3dadf89ce134a667d5d4859d8a923a9555d0e7f6fd13a7eb7d9bfc127def0f0affed2e79f0d388146065cefdaf5d1	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587741013000000	1588345813000000	1650813013000000	1682349013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x49f5f2bc1a9b69316c9bee9c2f6afe09415408c57e4492a118e914a2921793c7f32d410de07e427301fae5529b682fc2ac40f910c7c83ce784a664cc90ec9102	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588345513000000	1588950313000000	1651417513000000	1682953513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9bcaea4521b2cae996e9f2ca8cafd9c7d663e5f4de2469714db7d39f611752e7813c858ad7224886bbd0ffe01d9d46838b11120e44c22b17493d300d29d1d192	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588950013000000	1589554813000000	1652022013000000	1683558013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e83aa254d57687c92ff64f53bfe74975be6da76a5a1069d7a12efbe6e73a385a7d60f76d6ca194992bee9cab1eec253bcaa548d1ac0754a32777e6c9372b1b2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1589554513000000	1590159313000000	1652626513000000	1684162513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x229fb1f056302849040bdf4b310598413624b607b6045214e1d04dd7979707ca74650eab6f41753e33797c5df7accab7a31de80859c3d379ba4e209f61bae010	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590159013000000	1590763813000000	1653231013000000	1684767013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x46b388d59d647ea8919f4e9e044224ed26c438770277a8f48ac827a75a82d7b582bbcaaf09b3768910d902536bc3321eeb9a5bd9cbcb268c09c072813fd5c9db	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590763513000000	1591368313000000	1653835513000000	1685371513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf59d63228228e624c30401982cc7e3b81b61cc11b0c3f6e10485c6ba2bc2925968a4f3ed30eeaa950851d178c3dda593ef4e028098eaea003f9572fe7b9931a8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591368013000000	1591972813000000	1654440013000000	1685976013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x237ca6d24f2f25fd473a0d2bde90b4633b7f102284f58805f1c9a6f6013c6a10c122dd30bb5aeac821d6437951ff4410ac7268b4932ca7ca46a1bc9ea92728a2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591972513000000	1592577313000000	1655044513000000	1686580513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x908977e3c3170c8ff409fd511c11a7be630246331930deddacad4c196a162b5610a9723b00ae306d3f74c09b64a0fc5e999e19d7fd8c36021fab23ab0393f2d9	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1592577013000000	1593181813000000	1655649013000000	1687185013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa859cf243bc0c90c2ef2c5d5d3d7eebc1b09a6bcb269a008db8d2c6e7aa77b519be4449bc43cc185ee9b0d74e9ded8af8a7c2f60431eba06fcc65f23a80080fa	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593181513000000	1593786313000000	1656253513000000	1687789513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8c4eacf7588d6743d3885c9f0b2248cd65244e6678521a5f48be096bd25ca6eb57347f73bb434f3949806472cdbf1ec972e27a733e69875d9724ccc7b1400b82	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593786013000000	1594390813000000	1656858013000000	1688394013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a2d89fe11a3cc0d59015542b844dbe9162bb185fe05a511a40fa85d47b667ef4fd2e9a22a3d7773a7c906f9a918d19e5d4766fad785a0f84e119e2589679b12	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594390513000000	1594995313000000	1657462513000000	1688998513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24d7d177659ad86b35690ee40ee436bac7c304dafdbe0da02b209502bd60444161453563632f6421d1c340e447d940c26e5873eb400e0ccdc4f05841d7e07629	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594995013000000	1595599813000000	1658067013000000	1689603013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaac7d4b1e1cff27da82279d7b76a3cfd16505c37d2cc435f69f446ff469563a4b371bb94e50bd0d07ca9899cfd2c14fdc1d9a2d272ce8d73edf4d2081d912c37	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1595599513000000	1596204313000000	1658671513000000	1690207513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae37abb578f3f43b0b0bc4672da7a5164800e9d229f22d2305d1ddc7bbcbde1d0233bd54a1033de84e0775ac6a68565040c9ec4f22f88a737ece18aa6bfb6657	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596204013000000	1596808813000000	1659276013000000	1690812013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x94898e88f9ee90d0e6f275e2ccef533a8fe7bc882c0fb3cacaf0eb903f6b1f3c631663458e51242cbec13e923aafbfff25f328f8d88df2df64e07a85e72bcb96	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596808513000000	1597413313000000	1659880513000000	1691416513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x814c52248a87bbf9c91abec74089328887478e6988ec072f1d0235b8abd117141aa23c9cf35656c8d1c348bfc79f5075bf48748e4cad9df8f3ea4a91cb09df50	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1597413013000000	1598017813000000	1660485013000000	1692021013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb684d1c35d1394284598413b2c9ed24308a91d6e760dd15490a40091c0d26e7668a918ee5ea7c4b1ff03b2435a38015eee188bb51f3017093e37e7cf08cd082c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598017513000000	1598622313000000	1661089513000000	1692625513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd54fee54d334725860cc22b8306fcf730db18ef57be35bcd07ace6b3ee61feb65b75d13255a5aabdd7cc0a8a848c4ccccea79030eca2dc81c3eb0c88f219c5bc	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598622013000000	1599226813000000	1661694013000000	1693230013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde864a53063f28b6c6bcfaca1c2c1261f3132500905e3aef1e3ab9a8317cbf7d25cc11b06537e96efdf58fc93d88fe9a0cb0eb4cc22198ac9952a85810e7393e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579278013000000	1579882813000000	1642350013000000	1673886013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd9c422fe3c836064b21c6cd16c31478492229610a367c2776b2281fa2b29f04f4a5f75c2f1e93cde2ce87c6d1966c5cb8b8032fb332e9dc7cb08ab6fd2495a2a	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579882513000000	1580487313000000	1642954513000000	1674490513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2898f07055f40779921eec7d266b22689e5322f6cea609f42645ed29808fcb85231e0afc672da1fb2922cf80cb154e6b31830102b9e61855a5b8f9992b7e3be4	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1580487013000000	1581091813000000	1643559013000000	1675095013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x46c1b621cfe02b2758bad9d379dff705a8158665f22043def65ed6ddcc471546d21081904bed4e8830ea214a0fefdbacbbdef0bf4c6385ba3157bbab60728ab2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581091513000000	1581696313000000	1644163513000000	1675699513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa24990aed13fed912bc368506c8d1809aafbb656a8418d9616b7cbd633418ad4156bd2f4036c7a40dc8f18d6f1528cb466ed3d16687121d6ba6ad7a2218731dd	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581696013000000	1582300813000000	1644768013000000	1676304013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x17bf7bfe03c03cca2987aacd5f86a6304500901d9662948059b7cad864b8bf4dd43cb57b80693928fd54d584b6185b9124fa83bac8995e1148beda2acc8931db	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582300513000000	1582905313000000	1645372513000000	1676908513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a2bc9aee40b68f2dba995f88da00d356f1665153065c83b26656e02d2519ec3dfdee90c6bd809c66be6933c7d2795a697665285a7c9c19f0202be1189485758	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582905013000000	1583509813000000	1645977013000000	1677513013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf626f343f8ec7eca0523343ab38443998d4074072f5ca4a0c69ef22823f5ff7fe919aabb6f9f106b0b74fdc9f4025c375f924d77b25aab471e08cd3d64e8dd60	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1583509513000000	1584114313000000	1646581513000000	1678117513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfaa55dc3b4afbf26656aba1eee70e35d23dc24f83ab5ff86307d8159429fd01c2c2af1a8b899b3eaea0d25a114feea8c0a31b83e24b763aaad4911a48c98006f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584114013000000	1584718813000000	1647186013000000	1678722013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc8e0b66cab215e61103fec231bb98ebbb9b629915ee2098549f177a51993e29d5cab71c337c9def5454d13df71828d9d034236d6941a35c76a2499b0d1b192ce	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584718513000000	1585323313000000	1647790513000000	1679326513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x11a433bb21769e9d28f04ded28d2572482bbb048388a214841ba4394fa305b44f5b9866aa49b4a0ea2abf667fbaba1b8e940202030ffdfedb9de1f977218342f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585323013000000	1585927813000000	1648395013000000	1679931013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf98cbb91313eeea402200fa572133b7a2954f1ef346c92d6863c0553336307d4fdbf87d59e1a841c4ff8e323b8fb337c2975d1b6bb19a1c649f28e3b708cd574	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585927513000000	1586532313000000	1648999513000000	1680535513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6e62177b1fe6d9266814a76c2a902a08cebc096928e4758f592d0463307e7023fa2b4a6f0c1948ebb17b323ea00e21864ba8ed1817f42821e2edf0066bcad806	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1586532013000000	1587136813000000	1649604013000000	1681140013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4c21b98b906bb509a0714c282b6b93572b548bbfa27b282dc0b5dba5708fc47a7a00856567f2d0133707b1e8d9b103512c983a4a722acb35b3b20ed9dbc47ab8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587136513000000	1587741313000000	1650208513000000	1681744513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x45527d3ccc71195d1d22290d2d48b02460bc100e5ca273b26f9f6a8db7927d079100d1c3135395caf81cd9410b3f2b7650c6f1be01b9d49437168d138df50336	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587741013000000	1588345813000000	1650813013000000	1682349013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb04f0a23d41eed7e46961a0765d1f1386786c843446fe2b919ca93b3e9e207a22f1098dbb95a1e2373fff5218005dcb6f6ec5fde008363b259818d63da419244	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588345513000000	1588950313000000	1651417513000000	1682953513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8032a38e9f00bf42d55c4a107a72290264180ed311f1605f0ed61c59e6b3312d0756bdb25a7c0d0ca9a526a0904898d8d0ccf6941c794742fdd2d932c15f6f4d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588950013000000	1589554813000000	1652022013000000	1683558013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3f89e35f22ec70f207da404bd218ce704cf2076bf64a140ca8b6eb8932d2fe18d263a937b1b23256cdb15c6e153e3c7e4432791dbd5016230047a10b1c77f3f3	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1589554513000000	1590159313000000	1652626513000000	1684162513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd71f1f912fdfc43c87dd22ff6f11fae53defdd52316360de192109360e683f4e86e191f0222837bf09754211564ca527e0e3911ad006157281267ad94b1d0174	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590159013000000	1590763813000000	1653231013000000	1684767013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x282e19e71d4709b474e6e34e1d5dd7ad6aee5fac4c51892b098c6a147379786e8e05b076013d23ef9bb30fb59bd2566a337b6efef5c3256cde781111df92982f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590763513000000	1591368313000000	1653835513000000	1685371513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x50f39aec32746691efd1c1bec9ae4385fdc3fa0f4557048ff6972a0e93dde760b215b70d5d176dd9f4fac89d7dc6e1418aa0fbf5974f8775b16693ede4af1c69	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591368013000000	1591972813000000	1654440013000000	1685976013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe612f3f5a770cabca351acea8dce3f0afaaddeb0c5a2233f9569b6e183a83e99c21aadb721c9d12d3516f002d8186c63b25ac8dbb70beb60947211623cf9f9de	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591972513000000	1592577313000000	1655044513000000	1686580513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe33151a84fcfee643a39ed8d334cfef6ab46cd1f304214a8d190d05ad1ed3b82f4eab167e8992d507e2f10f6450d3f346dfaa0c4833cb14bc9291625044b5f3d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1592577013000000	1593181813000000	1655649013000000	1687185013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc7aba409dcaf39cf9c3e6939f24c3322ff95f9f5c6a40cd5d3de301fb1d48b275e1137b5358d3517496291f910d9dba3b07396dd2ed0eb03a59e557b262cd848	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593181513000000	1593786313000000	1656253513000000	1687789513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8740a14ae6da7e7b587c25c562d3147888d842de0f9cd70d076a891a07b368daec77344801d8dbd30289122a3c76d6c8f4eeb5268073ec6236d38c6ab6269e5f	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593786013000000	1594390813000000	1656858013000000	1688394013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xef06ba02270230ad0a65f5b63e86f67bae9e084175724d215147188ede555fc24626a4aa092cdeeaafeccc3ef11ca02e4915149fd2a6bf4fab909b8fd96c0762	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594390513000000	1594995313000000	1657462513000000	1688998513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ced7656678a32be615100cd03c49765a7ad7d49dee99523ceea528b2f3ea7d08955adc8935b09f79d465c043bbae0059d9b962f4596cdd4a9e421a5bd7803f7	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594995013000000	1595599813000000	1658067013000000	1689603013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x81fa69c64de90b338822d5b4dd0810a4ee444298289411de8e9803bc4580c3a82b05a8582df4360ce0399e1c23b70d790fb0c3b18ec893ff3b5bc438a4e9ec32	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1595599513000000	1596204313000000	1658671513000000	1690207513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ee250db34b805627b603fd5cec10781c76621e56645e928dabc158cc1aa44642c32bdeeb9b9144ad7e8fb937aeee744cd6116a5d114bb6ed90e1075a72902f8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596204013000000	1596808813000000	1659276013000000	1690812013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb0675acf4dfc1261c755e60c89941f3b1626497faeda1e856d77228221f447c496dcd68ebced612fdf9f6dd4c984770581ba618634526e57e7b26e7889e59c71	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596808513000000	1597413313000000	1659880513000000	1691416513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x86166fe6b822934dea7bb50a5a2d49f85d9660764f6d6688016e8be9ef71c36e6e23dbdd9f6b5c04e0fb661eb4fd552eefa9a9734ef9dd48c8d8adf09a03b4fa	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1597413013000000	1598017813000000	1660485013000000	1692021013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcf38ca741df0741eeb159cdb63cf79adecc263418bd1da8b1a3f473638b65791d079c9cbb039ccd54055279e8f7864ef078b5aa38fc08f6e8bc5313d1d1c03fa	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598017513000000	1598622313000000	1661089513000000	1692625513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x425713c038c9aa230e6627d71c27b4920eb8dba08971272ec22615a64e7be05ecf5a328856cd49d0bb988bd97c81da324ca116db07ba9b29b082eb06d0a91933	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598622013000000	1599226813000000	1661694013000000	1693230013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0576b16e912cf790e4902bac7eff372a03466faae32f5eaf1f13f61e6840c621e44f72d19d15e2e06187755ce6043db597aef33e2a66aac74070da3964e132d7	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579278013000000	1579882813000000	1642350013000000	1673886013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb8f68f73e0e44cce6208011b81cbb1be78a57c4e37538b1ca1c400b19cbd316ef6b509105d709b53e32642dbd14bffdea416ed61d05b558f24324559178ba164	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579882513000000	1580487313000000	1642954513000000	1674490513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2bd3a2663d9194b9d953cd3514bc65f012fb112c3def0cd8e5c2339341d1ab4210c95cd3d9323c88b49a8b198474f5fd6c43364ecba7fde0489bfd02fdaa8123	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1580487013000000	1581091813000000	1643559013000000	1675095013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xabb0bbfb08e03a3298e27e72a180535679bd5a947c35ac10ba9c8aff8be1760871ebe8c495398788de6e90e72c9dc93803d57a930adfa94c83f2347d7d080582	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581091513000000	1581696313000000	1644163513000000	1675699513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x50ec37e2e97fac8adf4e671b880335deb82c629b7eecf2704d4a1941d11340c61c37ae1283b8955165f6d6ff91bba8b3d05f8414708afa99dfde841f0ce5efbf	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581696013000000	1582300813000000	1644768013000000	1676304013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4c69c374d4fb0f9ef1cc4d8d49654597fd6dd25dd92a358945147af239ee482519994d3c51c9849ca2d9fa504033f5cbf7eba8e4a8243c05f87d78586a3455c0	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582300513000000	1582905313000000	1645372513000000	1676908513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x60d577d02d7189a4b128cfb81c8444fe90b538265beb5673d42f2d620938de797e9e83136de10f3823ff4474f15c43542cce1ef9454dfe5219f575d393c41403	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582905013000000	1583509813000000	1645977013000000	1677513013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf184b1756316ea872425094db9f2bb391a72b648ba91b336edfc82a0bfa5f1e0fa7faf6a7eb8dc33a58231c2a05ee93733de0c69d8c8af586b27414fdb9097c2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1583509513000000	1584114313000000	1646581513000000	1678117513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfacabbc829fb0631f91effa267775dffcb4548449a48c59be70ea73d726975a186c70935adc6089528cbd8019c06e9f0eaf67377a2afff93b713bcc0af28fefe	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584114013000000	1584718813000000	1647186013000000	1678722013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1cd5d326e836f92f05eeedff6274f8ba2b49325de830b9824ec735b990bf13ba76a89e78825e818465c8c7447a5474ac15c4ea34a652cc2356e561d1d6337acd	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584718513000000	1585323313000000	1647790513000000	1679326513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc745f106dc83da3de46786bfdd3bc72b7e615dc24e75c0a504fa17cac4bf8147db361364cbe936d8f58c018b1221de0442f0b357cf82564ca4b446c74bf51fc1	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585323013000000	1585927813000000	1648395013000000	1679931013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5829a60f377b1eeb7014b18d25d6e9db06aa3bf5e041a6000777420fd9067fc858045cfaadf38f6cba54cfe7304c4da90f72aafbdc37a3de46abdc23e60d2fee	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585927513000000	1586532313000000	1648999513000000	1680535513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbb20801a42a33a2b6c168f1664368c04afffd41be6879a8fcdd0f0a008bfd56019396b53c8ed079a377d0892987c4d4da57496ccd98f1cce61cb6f238f0c5bac	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1586532013000000	1587136813000000	1649604013000000	1681140013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x194a52827038bc4c153334e68db1088b7f576f741b7964f8c053ce536fdf7eaf80727859423095ca0e1a1bb1db7d2b355bb0784e085ddd2ebef6eb023eb4e63a	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587136513000000	1587741313000000	1650208513000000	1681744513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x43d2a0c3a3ba226b13f64e106e3b9158f64923322299ddd9831a0ff7ea71d4e54e05587c3d32d528174cc9a9efee1fbdff4fc0ed19a1c344ed580be9e53a1f11	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587741013000000	1588345813000000	1650813013000000	1682349013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2510156c1df74afa1aa718e788cd5d206a06d345f9ad344dcad0deb667ba1382b5694bbc819ae422869d3f899dbf9311d22aca8f01f7a2bd783ccdc93e415af6	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588345513000000	1588950313000000	1651417513000000	1682953513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5f5c7d4a1d92807b40039d88d5a0551996720039e3c0c76f457850d429f630cc4ee835a7751660121472380934bfb9ba10b7e55e7ace1a17739353c531611a87	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588950013000000	1589554813000000	1652022013000000	1683558013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb3dbc6bb37cf54a35d3dbd0179cf2342cc814bd51f7db31122c3b94989578d5fec6f30e10c4bfddfb322c8e1692312c37e378dce439581bd4a16c9ae3372cd73	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1589554513000000	1590159313000000	1652626513000000	1684162513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x87bd7c35fec3efcbad15885504b8cddad5c5e68cc91eb7d7150c280489489910055a01fe82e68c62094817d8194c9a0172c88ec65f100d6034515c399b42bc54	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590159013000000	1590763813000000	1653231013000000	1684767013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe830d826798edeff6927df826da28328a2373be0a31685b43c34703e2d84c208d006df693577b4b5676d209e49c319fd103e38d2385a82e16acd007341a2c44e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590763513000000	1591368313000000	1653835513000000	1685371513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf6d9d2518aaaec2214ac56257a93ada5c54f8fb834344bbb98026c6e29da2fee5504a48bb5c0de42e79297c6ec46320ffa131d2f9c06e3a20d69ad99bc4ba8e5	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591368013000000	1591972813000000	1654440013000000	1685976013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3268bb2e85dd863328aa2b39ba203b32319ab2eabc7ec391cae95336f65f9921635c475fd1e10847d1a8fac3f85a56dd83fc4277996b1195f9cc129aafb997d2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591972513000000	1592577313000000	1655044513000000	1686580513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcfede2a920482343f763034c2653cf6e76ae28e047f15761aeba85dda7cf3885ce1740b70ed5dad1078483b80f7469924228f36c5c8030982146dcc956ff5376	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1592577013000000	1593181813000000	1655649013000000	1687185013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xacf1a56d59848cc91982fbd32bb24c37d71d11d268399347e3cc925028d36b520523198cc53b8926d8b991c3dbca4e1178b8dfed03d5f4d2853b96edc937f98e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593181513000000	1593786313000000	1656253513000000	1687789513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x59c1a4b71a46310b865a501516ed3fcff8588c4b417c05c5cac69483e799089bb7d37e3bff7901502527b95f26799a3eb09ef86698d0211d83d07552aa2f62f5	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593786013000000	1594390813000000	1656858013000000	1688394013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3d7a0102f18dfb89609ebf7125687124e241278935cec6c19b64bea787ae2d1565e11098694371214792bea52128eb62f7dd12c3e5bfe2eea96b4b2ba6f42191	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594390513000000	1594995313000000	1657462513000000	1688998513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x83d730f69518b7d2dd54a43d7f5238f536ad34f557e2b54bdc072dcc1efc6573dd71cd13a28009806beffcd42a4d086026fb3bd8bb19d2e9ca5f5bcc8f799182	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594995013000000	1595599813000000	1658067013000000	1689603013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6c84f08d870fda90980beedb7ab0d4f2cca41be71354b1a35fc2dbc2ae5a07aca0c84e96fd9ba93ba70177b796950cd0ec3f53b8a2c8343420a07ab7e29f0797	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1595599513000000	1596204313000000	1658671513000000	1690207513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f5f1020bf0499041fd711c716f51fe371dd8aefcee01d23894a40c48a311594138dd2a1b4e6f3070f018cba4ec9290b8c1061be75cf2c49e277a57d92cb5963	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596204013000000	1596808813000000	1659276013000000	1690812013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6b9859e40488621c59879c5582a8b7926d0e9469c9077a0d65852e7d6cdda1073cfa5711b64657048e29f35ba72025c9734f52bbaf5f547499796a73a511506e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596808513000000	1597413313000000	1659880513000000	1691416513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x09cc7200aa059740b3c1c954397136fc1c22a05aa9a681678a1348cc3eb832bfb2dae41f09433f09fb4b7afd3ada56d86d7b15d7ed24e982ab84b625663baa7d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1597413013000000	1598017813000000	1660485013000000	1692021013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf3c073763058e7d759eaaaff9d16436310d6317933006ad6cb10048cbd5eb11eab1883654b9efa9cb88be456e09c3541eacf38b370f38edb60cb73c28daf82ef	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598017513000000	1598622313000000	1661089513000000	1692625513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4143209b460825f47ff91c1e06c1ac6287d375e2906f79c794d74d59a996ed6cfb30d9a6f6a4b0a7abfd8a96c14c1b5d8d98f707c199a8e14e8f57d5e7763a60	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598622013000000	1599226813000000	1661694013000000	1693230013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x87eb9ae908ea78ed45c4529bba457a907b3f39ba78a2bfb330114d2df93756431061b736e3920331180b23cf0c9a0335536af832583d342ae37438593de74935	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579278013000000	1579882813000000	1642350013000000	1673886013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa9d36057cc5030c5f9e9d75bbc55457d1644044f33242db51b9cc4139313de7fd714aa96aaeb426b8e8cd9413a98a3d45aab6182a54863ccbbc1219c446f4b78	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579882513000000	1580487313000000	1642954513000000	1674490513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc26eb7568d4293a8d302ce3d6c7cd775f4efff039926137f62d7adfd27199adb0cff109b034569700afe2169d72f5ce0a8456f56e359c7b28a57ad42b13872b	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1580487013000000	1581091813000000	1643559013000000	1675095013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x274466184fbd9549d31cf562cd5a238bf99ab23cb777b350696252938107b3e441fc896ae5f3ddc5e52f5e30cc1dcf6a6af4023d67c78e3f8b9f9510a8a72fc7	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581091513000000	1581696313000000	1644163513000000	1675699513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x947985c74c0984e4a260bb00592cf4a88eda15e0bba72adeb6d8d0b2bf1aa382fddaa384b9b07847244a74224a57f578fb3b8826354be15f47cae76ac14a264e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581696013000000	1582300813000000	1644768013000000	1676304013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e95c675551086a90beb996a69bddea2a85186ee96190e7d64924ee1b026a2d410aa8798dcba1ccb6085e0baedef80e6711f95948b95e43d323171332497a403	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582300513000000	1582905313000000	1645372513000000	1676908513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x69adb723e9b4aefc1384f2c05d6ffa3692f894e4585b6c5cc07ffaf3948fc5e3339a5ec0a7720e655c1a972a7b9992d5aef0c1aa302a38c33cc05238b172ca3b	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582905013000000	1583509813000000	1645977013000000	1677513013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x89a5397bb1d85406486e4cda24dafdbedbdadc70b0f097f9000bce50f0eac0a2526266975d626127d6f00f250e14556c244df26d72e4b8153651fbad55dede53	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1583509513000000	1584114313000000	1646581513000000	1678117513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x59186c3a0a8a3b62f7f4be5a00adbb389c11548403c956ed11447d130b05f3bbc0591bee8b764c4ae8bfb9546426ccbff6f43626948ca6b075dcf4990749f313	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584114013000000	1584718813000000	1647186013000000	1678722013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x61ec26d7d60b52c661a05e34c979133ad283c33a5aa10b2f821406a7815d5a0c8986f500f33ef861a2a2fae61e4350e24439004c980b1da2b8855ab7fb73d29e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584718513000000	1585323313000000	1647790513000000	1679326513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8d952b24bf606152a42dcb19d08cd1a91a302aa7a93335160ecbac7bf44ee2fd999b8511cbe9f2561c0df8b0ca91e56c1d1c514814484ea4bc49faff6aa3560a	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585323013000000	1585927813000000	1648395013000000	1679931013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ea8ee3f5f58f8429339035494ae3bde4fcec67e8e0090adf3eaa243eda0d59e350f40206275c87b4c1cd47f4eac9419eab83778ab9a866bfa3f01ca14362b13	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585927513000000	1586532313000000	1648999513000000	1680535513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2311b71182cf0f58f3486065f9d313b37c45d0fa4a7ddcc0a9969997d6c731a4d81145c989758db8ddc5d046ce7865a963a80750dce1a1cbd7773f669672b9d0	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1586532013000000	1587136813000000	1649604013000000	1681140013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x35a68a9c5aa0c2263c6ce7748efc40471e35aa9dac20c16636b4361853806d12f90f7d5114ccc30a9a1e10a17ac809afdc58de898ed9c04abef3431e72b90442	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587136513000000	1587741313000000	1650208513000000	1681744513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa72385d1b943091dfe5ee316a665c75692ab74c94a8209a86ad2e837f189be91309d5e981e7109ae6299bf1d7865b1539d59fada2996c2a8e7ee7f62ed20ce4c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587741013000000	1588345813000000	1650813013000000	1682349013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x674708dd6a04eeda3b9f7962539f30806985a8dacc9119cddc0bb17190bc332acd947831c536f00c8189978dca0fc5b33dd1fc3e4db0afae88456575724d673b	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588345513000000	1588950313000000	1651417513000000	1682953513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x53b3071af481781deddd1bf026c8e7b0751f5a97ad686b52404e0f60e8855e13adf657e653f2242543aab3d4dfb6f441bd7c12fdff411e082b0f306853de7c25	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588950013000000	1589554813000000	1652022013000000	1683558013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x313667b9f00ed41918eb07c33c6de08318c8ac686d5d1648c1e224b90c50465c7923e70f7229919af2011bf1d449126bb37bae0ff5bec5fd2fa769d68f8572f8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1589554513000000	1590159313000000	1652626513000000	1684162513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaaa986b1ffca875190e9b097db400f2fd113d208e54f9112a394bb5a892e10c1967a0f94fc059a67dd02ee7db02d98e26674426e11c65cd8dbd419e2aa69bd73	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590159013000000	1590763813000000	1653231013000000	1684767013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c36efe6203e12fe0ae8c546380aff921857a019aee0b969e72c2b9abdd55a163f2ecb14873e45e56f1ade2e49bafa466a54848cc01e911e76cd26aeb1a337e5	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590763513000000	1591368313000000	1653835513000000	1685371513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb4b5e46e2c70d56317d7805c4c58f620bdbe3b2a301dfebf5ff51169807cd9088fbd7a1f31108ee6b783ad3a3d097117f1a9f31be2560a044b020596d6b15ef	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591368013000000	1591972813000000	1654440013000000	1685976013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7fa014d30782737cb42b3b3f528f34f704518317634d0679f5545744b2171e38609cdb1d7c63960c28159e4132bcd049618cdee9516ca49e6d2880310e2e692	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591972513000000	1592577313000000	1655044513000000	1686580513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x13d55605b82246310817bba03a8694c5e68da728e55f00c45b8c1c44e6a4072e3221980f2e974674545957b676ec83b8bb803514bf1e48cc8aaf1cceb95547d7	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1592577013000000	1593181813000000	1655649013000000	1687185013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0bd14cabec54abe8eff238ff84e86fad5581c580508d1d560a06a1b65a9642ae9b937ad6ccac058d371fa6806a8945f176ba689ba7f197f83c1c92e2860503e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593181513000000	1593786313000000	1656253513000000	1687789513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ae043270b1dee4ab10350724f9b5a98fc60178aa0ab706d4b299ed510ac4c16947d1ce68a14905bc5a4ad7e0f56f6447995b6bb9bb56e7f856bc076cb7401da	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593786013000000	1594390813000000	1656858013000000	1688394013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x59fa399547b28ee61f2731a6f79de8c6c6f85c3845605ba13184f3569264478eed35064b6b4ca97f908e39d5f2352fc78688a146c88430f1949a8f834fdf41b8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594390513000000	1594995313000000	1657462513000000	1688998513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d5d4fe7a67fd4e131d36fe026036edf34cfef9fbad5af41880f4ed31e6f56228b589b8228040849fa31a81b5dc48b76fcfd1903ff5261f33f0982a0f2c1c1ae	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594995013000000	1595599813000000	1658067013000000	1689603013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf4895165a64326cfd221afeb86e14a5ae3dca9d546b134dd0469051411eb307e30e4a5eca716f359527ca40fd16d6769c8a4aa7333c8d0748193828c20847407	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1595599513000000	1596204313000000	1658671513000000	1690207513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd7a934fde62fc1f706149d7c717846924499de1e285ab6cf314a29cde497b3754f75969d086aca1f3d079915fcfc184c402e7bf4c3c06a2ab54a2c707b094983	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596204013000000	1596808813000000	1659276013000000	1690812013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5394c22a63cb74ef43be90cb5794e58c3ecf8752f36831008f6ff5eb34c0d5a68595cacdfdc1a67c531129b2b8c77150cff299e4d44ced9d01e40277af45770	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596808513000000	1597413313000000	1659880513000000	1691416513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xee89c36db9903b1bb6f9adf3ce4ff19b2606cb041dc10059e59d8d25aeb1589f6129e28fb60e4b4c5db5456f8c1b44c4544c5a773eac26b30c69ff8703f23977	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1597413013000000	1598017813000000	1660485013000000	1692021013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x72eb29756f8211dd16c7afc0660d30d99fe44fc906fbb256e814b7835066ba92116620bf8c2ff6304600f9e47f10ea16b29da7748f9616d561ab5254bfc261f2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598017513000000	1598622313000000	1661089513000000	1692625513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d777caa6953c29a139c7efb9a471ad89b4dae3723707222fa157a7dc430c8b4c8323e3871fbfd9509e20f0b94be373c93635854b97d62ef365cdcf334d00156	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598622013000000	1599226813000000	1661694013000000	1693230013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xee462aeb1c7c5f640288cc2ac3b9f4ada9b20fd5335aa61239a1564e491a692bb3c4a46299398fa2f543d98dd97de62026ee5eeb3d17badcabb3ce2066399242	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579278013000000	1579882813000000	1642350013000000	1673886013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe3997ac41b2166973f3c8521a1642c4ae3bae9a4489d23933dac722d66df06ebd90c024f0ddfab032e409b981db5d52c38d1e8e528eab1f52afaca4768c6df2b	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1579882513000000	1580487313000000	1642954513000000	1674490513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6f3283cdcd5cf16734b192c1a4ec5d05725e679a1b66b7540ed31761c0774564c110fbefebf262dffef4949c88f9a69c5bf6b23e91206848c490208a9b6d2fb6	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1580487013000000	1581091813000000	1643559013000000	1675095013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x28078d3dcac94109c9048c92442c122e76bd3c96e741ecaabf2d6bc7defe699e3eca9b6b00ca25f06c9127db6c029e0c7851ccd377b5529bcfaa701e373bcb17	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581091513000000	1581696313000000	1644163513000000	1675699513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1ebf706b9e541e1a5cecf4f1f65df898e58dc2adf872bc886e9358e5e37234734259e44cc808165f0b50bfd2934f3d0b2839ef05cba5836cb4eaf3ecbf078388	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1581696013000000	1582300813000000	1644768013000000	1676304013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x17a1be09e0838b01da5758eedc47cc7b94201d94edd19f5ace8c1263b5b1719761753311dd13284449e2490bc22ae76130b6291a6627ba8301fd4324f8648742	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582300513000000	1582905313000000	1645372513000000	1676908513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfdedb9a60fd6114fd3181574f9d742eff10fc3bc6c6fb9d87e3651a93ad2e236ba70960ec02ef284079588662ec5c25da647e407440be7a272c5fc1a1d9b3d23	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1582905013000000	1583509813000000	1645977013000000	1677513013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8915395f683305019d7d521ac8920b1caf8dbb4d2e8145803cb259fce62f7ce90f520c5aef504ec558dcfff7bc71c880021011e6b6af31f4a5f7d1c762e3e97a	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1583509513000000	1584114313000000	1646581513000000	1678117513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb0815aa01158e904c242b119df96f93cf0702aab8e1dd6a00a3eccab43a875b0921b5f6e2b8c6a0cfd44f59074af902b322869b727d5a647e5400312b4950fc8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584114013000000	1584718813000000	1647186013000000	1678722013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xacc7dac6d3d7a62f7a971e6897aea6a3e639c5cfc8b8a9930afd550ae762198ab49da2c4495614954a9e9d2915e61118ee2aef14c29b7062b02810ed5b65b0a6	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1584718513000000	1585323313000000	1647790513000000	1679326513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4d04e984089572b23e4d49b6a3e13b79eccf7f8c5bd7537395a3a0bd63e64823f33aa5eef14488ebbbf4529d931de491bbfa11ccc4d1ee90ede7a735c15b3856	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585323013000000	1585927813000000	1648395013000000	1679931013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x092b9a9ba2b231e4221ce5e688c97e912f3cf38d3116e932e95dbd41a80520a1f57904083d5c604fc9e838ab6fbbc95bf13089d8d19fd2f14a3970561f7b0b2d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1585927513000000	1586532313000000	1648999513000000	1680535513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb2dd48b9ab523ab4d01cd160b25c84109a2dbcc051d92e4bca86347e20db71f3a28177707c8158dc4ee4dd235cfbd55da7dd160becd066087be2e137899cffda	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1586532013000000	1587136813000000	1649604013000000	1681140013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf7168df54fa1944d6f6ae90ce4bab38a6a7d3da25f2c569b631a829093086705117d402e938dd1322dd4eb5376e041d10d6255b6d1701fb7e5038aa94c9e9b06	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587136513000000	1587741313000000	1650208513000000	1681744513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf3ce6758f9af6c73f6e8540753a69722d26cbb738f75e2392941aec956d9f29467a077d85ecd6dd42304379715d3d26d443acda5284a6954c785155bebe8f3be	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1587741013000000	1588345813000000	1650813013000000	1682349013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0e0cfb2d072547263749cfd85133cc7c084bf10273f88d6869684718bfe86c3f9428c1ed085d2cf967f517138972c45d6f192e04bcb1c832355daf0825d5627d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588345513000000	1588950313000000	1651417513000000	1682953513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2025e76542e8ba2f2419e918d796c6f77c536fdee54c5632ffc31a65732e5dfdf92777534bb4f1a4f2913bd40c766ce553c0169087be62a13b07743162f1c1a4	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1588950013000000	1589554813000000	1652022013000000	1683558013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x03160227eb20f92a0217a723b378589e056c3d811a23b9049409a9d3dab14156847fd36322941af9d9164fc77f1e7d86b293716eff2633576a872df8af2b2d3e	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1589554513000000	1590159313000000	1652626513000000	1684162513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdda1c1fc942c237fa0ea5bf4ab729411fb2b4e25e06d3888e3fa2d29e0454fe2de364ae10c835a8204c9f84a76c6b8121b019c65782fa6b072f455d0af62c2bd	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590159013000000	1590763813000000	1653231013000000	1684767013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3b2257aa1b01882945ca599c35589b89f9eb1b405e692128ba3ef0467c079bfdf544d7fe9c0973d6a4cf3a185a464904268fa2a4fa7a10567d33b425405434d8	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1590763513000000	1591368313000000	1653835513000000	1685371513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xba8fe22fcf081d75cf219ce1868cc7a37e7b0cee0e0c4e48580322d922e939d5a5eff7502eb0c43eed4e20ef796ff3dab6ef4b4b49c632f130b80f8c0c29e2cc	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591368013000000	1591972813000000	1654440013000000	1685976013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfbe6152d1f5c4e71f12d7ea928a5b4205262f006737ca0e94d1250c9ad27ba8d3b784e6b8f25e5cbe7232fc020b28a0dab9cf968ca4a82d356c8961f9ed81b4c	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1591972513000000	1592577313000000	1655044513000000	1686580513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3f325e894252fc2c8e3aa9c7f092165d35988c6651d54145443f47a45af8c7162c8d832069c893f285b260151d40ca2bd4580f7cc0868d015a82a8b4a7b89893	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1592577013000000	1593181813000000	1655649013000000	1687185013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa304f869bc92aee7613f0ae6fa59e3af7a0c516404119be143573481b60a82f455615c32d5631e79fb3b6dc5a387e2055bfbb6f3263a8f2e18b40515788c6533	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593181513000000	1593786313000000	1656253513000000	1687789513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfeca48ab38bdcc12ac61ad9716686bad0c5ba372deb4db5561635e302d3ae24f5d45dfb4d4b689908773d66ff8155c3faf9e91bc98fd58968fd36fbec7a6cf03	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1593786013000000	1594390813000000	1656858013000000	1688394013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8a808d7b44ddb457e4f770088445d3f58076a04770543c81c2451dfdef493e6c406ec64e2e30e0039e23ac073e0afe9d99f93420d647a263355afb75cb688a32	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594390513000000	1594995313000000	1657462513000000	1688998513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6acea03c4cc3e478ac36400386ee23d101204f717a7f00c852f825ce1372dab10bdec77214689a8291c2d2c227bdf58e2d8e29e43dc05746d281cdf4412ed6b2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1594995013000000	1595599813000000	1658067013000000	1689603013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5da24b5fe8f60ae8f09360dce26dad8c8b673a20a95de43722e3510e56a0c50fe7c743c365b75440f4dde0d8c0e287f57ee77d92d981992127d1c3740d4cfe71	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1595599513000000	1596204313000000	1658671513000000	1690207513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x72621cee650fa31b48e3cfcd96a69f9ff91f7f81a5f4dc75ac91ac23900aa3d24f9ff02027c18aa1d2b3be8e0feb7b02cced3007520becc8fd5a8ffbca71004a	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596204013000000	1596808813000000	1659276013000000	1690812013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x28092db41dba8c1ab3b519b682fac98c792a5599c8db0e5bce4a13e840adfe3366b03139ce434238826d37f7b26c76dfb2f9d766922f478703705c6725883b25	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1596808513000000	1597413313000000	1659880513000000	1691416513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x02014708b2c4064f96a1ae52904ae90570548bc5b82a9a063365ab2c71c630f634ed2caaca2e48887a25dd2db010143ef40a1a67bbe433e29d17ff0752fe1b9d	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1597413013000000	1598017813000000	1660485013000000	1692021013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9868902c06e085c46b0bc3cbe8bbc9ceec3a16bc9523cd9bc5818a68dc3c93fb0c38d23d3b1b79badcf145250d1a9aa254e706ff9a94f9b502d70b36fa3cf72a	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598017513000000	1598622313000000	1661089513000000	1692625513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0ecdc2656fa0e2cfb3db85585c506b9264f7d00711ae9fa9c352217a8416602d5c2513fba6017d5408edc878d12eea60ffd5a251a2185d3542ce0ce7a44b64c2	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	1598622013000000	1599226813000000	1661694013000000	1693230013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	http://localhost:8081/
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

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_payback_serial_id, last_payback_refresh_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_payback_serial_id, last_reserve_close_serial_id) FROM stdin;
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-01-17 17:20:24.238609+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2020-01-17 17:20:24.311159+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-01-17 17:20:24.37393+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-01-17 17:20:24.43619+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-01-17 17:20:24.500048+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-01-17 17:20:24.562444+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-01-17 17:20:24.623816+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-01-17 17:20:24.687135+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-01-17 17:20:25.114536+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-01-17 17:20:25.535047+01
11	pbkdf2_sha256$180000$Rzs3D2FR0uMQ$1wyiVZC6reDdaJ6HGKEokaOK1EvedZ3MEgiDGY3SaTs=	\N	f	testuser-TFQv63hJ				f	t	2020-01-17 17:20:28.214505+01
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
\\x4ff06c6367725ddd876379ac8df92f270b096c588157241f3d0addbb0b37f2ee0662c34bc94356dfc0fd947eaca37bbfca1e5de7fceaa3d59c70cda2518ce94d	\\x008000039d5467ca563ba31368a95fee3cbeff3442a859615d7cd6fca7daf543d4944d88e687a6b8866d1daa9abf1ad24ee912c2bfcdd1a1fb0643864b19dd9d7ace31f1aae059907c18e3bff0f24f3921b9dcbad621fdb5bc3cb13cc0769f050b57b9277527631810945e71a5db897cad5550f3b053f5bb369b7c2e6dbaebc3eab995c9010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x279e6d9ae8d98709eff465a2d33e9de2b130bf1f28b78f75e892f012049f7c417fc58ceccccbbc82af5bb216a60f49b9dddb4c4a005528767051165808048601	1579882513000000	1580487313000000	1642954513000000	1674490513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x907906173059e50a23e944694aa039f7a355c1f9e8126c05a53dcc36d5bf63c4315cd7a0cc54beac31cd3148fa7568c27d3a67247520672bbe67297933a9f477	\\x00800003ceec8d4ba48660b22ae1586f845cea26cf5f8418f3d7467fb4c51151646fdfec007b4e8b5235e1f6a308ec1101d772c4c155d9d188648d416437d42f516cf4f534517a8fefbe09381993394870348711e0be44200149bafa9d08da20d07d127d290cdfe6af1d593ff3be250555279741adf5662363423a453ef7a26814aa00fb010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xd6c3fe83400c3be36be0f96d3cb4afe0b8a1a05e597dcbe80764f35346fab5dee91864759b7bd148960ace1dcea3d2eff6ddb86df4e78e103d4ba2ff65f3730a	1581091513000000	1581696313000000	1644163513000000	1675699513000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x080614b1f824417b253241fd17010bb1d2e974728382c1457277e8e1eba95e0328819671e6cf631f94c4dad1289125ad8e0cfb1c5111c2847cd3688f1aff1f14	\\x00800003a8b87c5b3b65b93b301b6066bcad7737f126ffd08907784261878eb3b56214993070e61aedb4f904a0e18b587955f7cffc7d92de419896d32d1646ae88ca40b72a272e6f90d6ec9813a1fc964dca761923b7334c0e29a788a140ff12f20f00e09ab6305c22343413ba983fa7d73ccd9b9cf431130374c6312ba603ce8d043e4b010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xc11d257c336f4164b38d859255ba014a670b502a5c482a8fc8990dd283877cafc6690c2edbceab20081e9d29d60200e7bd2a44c80754928236f0ef83c708f705	1581696013000000	1582300813000000	1644768013000000	1676304013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ad7b1dd2766e12135211541fcc37aa4a1cdb2881d276afa538a1e7b88a4397a6d65590048d8744bba37a3519ad8878b5e9a70ba88e46c003fa05444f9e0d345	\\x00800003aa40999eb050263172c96cccab96129a4442e55f4cec24ce27d99d186207bda4ae07717916e28306a2a08e021467ae2db49896f6a69858810fb669cd9e20e812ec9f298152fcc4a8ef99ad1fd45b5135dad26e7399327c3c024ab6eaaefed97dffcf85b4ecba3651552236e973fe19e43d849087cd74bcd04c4d13904f7e316d010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xbd0fa4446ebe84881a3af48b214acb75ed40fbfa7aa50ca264007474c1b47eea10423aaccd98c50afa838d825aadad021099f50496b79477b4f798190a26c108	1579278013000000	1579882813000000	1642350013000000	1673886013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf366683811b32bd5b0b3e6f485bd8db26194d533b4363f6fe38775ffdce53cb979fd702c240fea51a02cd3503d5b72ef7f814ed9b93ee29176c7088004e921e	\\x00800003df86ac17188be8e1e12a0bbe872ecda1a7f2302d6815b714673f178595ac47287208dc2c633c57f3c96da3d8097f1b2cc20ae321c67b184ed2a9ff38b866e6709057ded3244677a06d71190a18b064b48248cdcb060e591b259087fb16bf4e68684b26ea2564401d4f261c0c156bb6f39b22cc50222b573862465fd1dab64c27010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xf10b34c08ba515205979597e36f98a0a5d70e5cf3045ba2fb3e85068dc159b340ab7c3bacbc59a46bbc4656127b041234f7ea21be2835c3f6cf89a4dba044d09	1580487013000000	1581091813000000	1643559013000000	1675095013000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7199f4d40c78b821d7b7a053bd641b044a8aa5b4e069ddc7c9ba18c21d4c2089aadb86de6893df7905f647cf5f23ccbf7b982f4cb10079f04d36f1fa960766f4	\\x00800003c9b416c9ce01533e39a1b844dab4edfc7773fa38b55dc56fda836047a64c018c359c88e74fc39aa07fed7f25312d33d6c014d935fcf00f74dad021f00608c8da862bdfc5496b52633e86c05116559a62afa4657a8cf04dc02d9c4fcdbff667d02781d9630e48e7f596c5b1e70011e6ef4853512908f9299835e04a4867a936c1010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x26bb33be2562b577691c39fdb211f3eb9539738c9b7d9bf577162cb8edcaa24b95078d85bf1772e08d5104156032a350050fe60f113bde70c1ac4b41df2fa608	1579882513000000	1580487313000000	1642954513000000	1674490513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b5b04501e3177de9dbc736579c5383880d47869c5d9e1e8742a02936c4ef2ddab1bdf91d6beeea4a9af9b05ee780669821c8a7e6da6daa93bf7e8026b36cb47	\\x00800003b89be9cb509cf90554fbd133c1b230be310cdfb0dc84cc3e73da4cab77dcbf5c4b8ed6850e480f637668fa71d5a11a98f3905a9774a36127d4ae026e4afda31b83325d44843ab4867ce083f328d7fd0eac6d427fa6dac2555a01048e6067428626a1eb94979f24d99933aeb0576524b6087a338881f789d781a8e83e1b7e7ebb010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x825782009f3788933ee9ce197ae66c492a6da277f6f5fedbc69c61190eb3ab778f5fde55411ef66318648c53ca2792beb888947ddc023612751faa4768c4900f	1581091513000000	1581696313000000	1644163513000000	1675699513000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6f89f15d916e7af9477cb4eba29a5db52f43a49f85de54d2c4f1411c1813ffaf062b24b402d07c89f0cfac336d73d4a54b9376f9ee46a30be41f0edcecf28455	\\x00800003bcd512b26442a1dd09fe0e27c24a115dc488235297c92e4e73825b594402fe2118ae8d350bfa76e20525e9a2d1763b1bddaf6aa7a37f0500678d9fc5a8025528298f18708325b5eb89d4f64f77c3359fe9f36eefd3b32401b7615670de8d9aceb7ab86ba252ca3d06fb4a6ca9e31631065b9ddac62e3f3a53fe8cbc9cd7a4baf010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x9a570549693763e221d6af78c13beac40373fb0edaaced4d172d5b46b80a12b59279fe30a767cc62f56ec156a3ba712ea7c347a5adbe4e79264727904dc4cb0a	1581696013000000	1582300813000000	1644768013000000	1676304013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0a4cc60cd1c3199884faeb58168d6a1caa58838713c3339630e80cb61e78f0ee6e742e7d3ceaad1deec91f4ceb1622cd3a116ddd817ae5e430b8992f1c6aabc	\\x00800003b5229bdc52c993143f660df8ea5df9ebaa5574e4aa5fa6fc1ecd9ed66caec3e724594af8185a66154c5bdd903e33bc59af8361f4c926b9b8adbc46379667a2a423b096f71e631beb877039c05f4cd71ebcbbe43b1a0ea42fa663ccea65a9695b6c6d7eaffd45d8118fb3c834248877b9955ac7deef73f86d6ced222c6336002b010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xf01dc073fefa5f45cebfbcfa1e2e419241cf5cea9a927bcd3371a4f5e615c8ec01b6d72aaf8c45f51dfc46d2571c2f1bcbcdce56340ef5cad4c82ec45dc1d709	1579278013000000	1579882813000000	1642350013000000	1673886013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x946aad5c0db289a803d2120c7f5b0af0784751a89af26a362647dfe0ed661346387fe72981f5fec8b9a1228b64109721a37a7ec3ed8bd3ba03496210df77113c	\\x00800003d0a259b7eaa71172e17c54ca99197b4bcc1c2e91f3faab5d6c499b3fd87473c911602a57b7b953d9cf4fc4ad3643537481de63771cd7d4b2f5e76dbab10ebfc451d0f40bd5f2c83a1eed4698b1d5131a74fcfb265e6899e6aff78103f06435e321f652a3056fc3f9dd9d6a59fa4dbcb5c548d80070d7e156eb7c07bc77101ea1010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x5699a82643baf541a1537977f9cdff7f2a5f49284b656bb2bd697947c2784b5e5b02da31644ee783624ac02072cbd550902dfbefa5b59db8e46f6e8017a7eb07	1580487013000000	1581091813000000	1643559013000000	1675095013000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9c422fe3c836064b21c6cd16c31478492229610a367c2776b2281fa2b29f04f4a5f75c2f1e93cde2ce87c6d1966c5cb8b8032fb332e9dc7cb08ab6fd2495a2a	\\x00800003aa7a4ea9d81008313cd62577e2c97e96f2e72b416af37c3320b4ebb0b05aecdf5919f129d7c6067f6f2efe1474ed59262846e7bdb5c5cd74cd76649df5f8440fe6d3b0d2b260bef3d3cb469645fd0101486e08598c375abcc9e56b7d8ca99d4e4eb1fb55fa80370d2de844ffaeaafac2a57600d5541d65aab61a59a0b0a0648d010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x5ae3e04408273564ac4f25af9424ac2fdb125858be4fb32ed47874fbd1d72625db662791a16b25190a6e230dfe33258ba220de0437627e98db6ed2820b9db70c	1579882513000000	1580487313000000	1642954513000000	1674490513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x46c1b621cfe02b2758bad9d379dff705a8158665f22043def65ed6ddcc471546d21081904bed4e8830ea214a0fefdbacbbdef0bf4c6385ba3157bbab60728ab2	\\x00800003c7205465059d981c5cebdc8b01be192e7f7157ecd3c6883b7f6b4ab2463c6de61dbb4764d2a4b101226eae7a55a5d5eb2d01ec352fc2b5d3ac1d974ecea24070cbd8042110c479f2695f52542e296eeb1a8472e6d0f9c3d7b8caaa5a79a0031504bd5a1f0feddf7aee24446240b3e199576e2e724bd914847dc52b8a25408b33010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x5919116d60a5f4d2000d0a8ed4ad39683bf0f724982d7fc4d530b8412996893124107405df557ec9f33bfad6f2b2125fc431d8cccbe58fa8f727e90bb1209d02	1581091513000000	1581696313000000	1644163513000000	1675699513000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa24990aed13fed912bc368506c8d1809aafbb656a8418d9616b7cbd633418ad4156bd2f4036c7a40dc8f18d6f1528cb466ed3d16687121d6ba6ad7a2218731dd	\\x00800003bf3f3729323e53af59d30e4ca5af8a540228ee75caa1fbee98cfa8da5afdb0646d359e5135be47b1a5ee62cf64d985a670ca8b4156f26fc7279a9820c059da4f9e0919b7c1e4e291e42cc2e896dda72282b48cd417781c0678c440c4e6ab59560c21b45cc087d443607f1151d9254c104d2c1360f3c88c1a9d20d2c16c8cbe93010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x687f1b106ca0dcc6856e31eb179838fb5777e97e5be834ba7acc6ba1d4e5ed788459b8cd43a2ce45f7b08df1dd4ae90f852ed215d59d5ba81c3973ef4ab92e03	1581696013000000	1582300813000000	1644768013000000	1676304013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde864a53063f28b6c6bcfaca1c2c1261f3132500905e3aef1e3ab9a8317cbf7d25cc11b06537e96efdf58fc93d88fe9a0cb0eb4cc22198ac9952a85810e7393e	\\x008000039d754a4e0d4b9e2bec57b51f3f193a78ae522a6366c0ebf1fe3227267ff9029382d9fa9a1c5ea890511af77ab7b315c1b82be20a75c6e914abfd518bf41f3e4a35fde3022265ad2affa345b15e7c15a1a2df6116e4e1ff9361f4277bc3738228ff11b83c4b9b645ee0bac4293ddc930baaf5285c4bedb6a7fb454899155b089f010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x8ed2cc2bc17ea7a6f22d9901fe49bf3be5debf3add7c96b0ab3b5064b31775a96fd77969fe8eccd14492657d4b432bcfa504bb9f5116926f4cdc921fb8b5c10a	1579278013000000	1579882813000000	1642350013000000	1673886013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2898f07055f40779921eec7d266b22689e5322f6cea609f42645ed29808fcb85231e0afc672da1fb2922cf80cb154e6b31830102b9e61855a5b8f9992b7e3be4	\\x00800003a13888caece2bfa25fd1f7d486a40e588890fff8b4f6ff73fe11fef756d8627bd692bf2ade5be03db89c37d9b3ef254fc663c57c0ad9bd92aa423643e0eb66b253295539cc195fe320b202093a8085478d88465598336d82a4bcdef7764fdde9b4a251bfef635d00947f8bb6040b12472d7ef89f7d4b9d3e191676750abc6739010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xde5ae73b5658c5ba354d9669bc43f16edf9c12f44357a165b59e33310d9b0d598832eef129ef799d24dd66450bbb7d5d3afe81d3f7a8b299c1a7acfa8eb52a0b	1580487013000000	1581091813000000	1643559013000000	1675095013000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc86839aa386bffb1ec42fd9f000dcabf16c1604668aa1c2839e2d411935bb245757da9036ecec879191b5d2c5e083b6831dec62fe39435fe53acd7825201e788	\\x00800003a6185a833b7991122789f400bc9beae08f006627f844871216575783342a234803d7d76d2d675a0c4c7b4313f82de808cd6e9222daa6ddf206f44a79525616076ab541d5d1346c66b1e5949026c7ecefc7089633f2c9a6adc2bef057b4cb06a0e02a01c96476ecadae47bb3ee30b321e1cf0187700f7f31ac9c11b622697c085010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x0fcccc1d882e113e129858f707951dfc7edd291f02388be743e8dcea60c48138f962c3006188afdf0ed03f096736b111f8588596043ee54fd792698fc92f9d00	1579882513000000	1580487313000000	1642954513000000	1674490513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0c009267341470b903487c4c008a5847723e40ea3ee2d8f848417b10a754b98e9f2724f9023f517b5ba2799ef9603cc28b40dd7c4cd575ca67a7fec136ec6c1b	\\x00800003adb5b66ad43bdf0095b5ac93e00d191d7e71266212979a6b520286397ab8b77709b7cdc07f0c194cf88f77f403b5169f52408d5f3cea293b7f7bc08878b91187221485cd9169916dfb3eba49551a1295c079bd5bd1990a60e4848a5d42d58fe246da172c1ebb52f8f38262f3dfa7b3e4e5eef159c4379c7a8f6cbfb0cc98557d010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x5a230be7f49a4cf1a94b91d6e599595b6908e396661664bcc3f1ed0f8d8e9d5dc755bc2ba54c759eb57f054fe5147198675be8f8e40eebd538e071791efe7a08	1581091513000000	1581696313000000	1644163513000000	1675699513000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb3401ed87343dbaf374b554905bd859a7aa302d74da814bcbb420293099bdb9c048437e665e60ee76070762b6863f8667a09eb29748dda79e743aaa06a7bf93	\\x00800003bab4c17f845c27cf83b21be78aac086a4d80995b953dae215f72e292910c80792b9c12b10bcd3019fef2092a016b1e757b46d844111cccf476b4e6c56764f4ae5ecce0feed2485f9c50c6672a2942593bc0017deec99a3e19a0a8da8face1ea86d9b4b8f6f174272c93767d18bab019cb2ce14f6a2db5b50f8609984c1f3013b010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xaf1340a8b47117cb50662e4812f95448a8c4b5e1f7aa10081ce1a4b9bcd238d8cefaee0880dcd9e746fe8661b06863ee50176c849c45ccb030c5aaedd76bdc0c	1581696013000000	1582300813000000	1644768013000000	1676304013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x044ae13c4b2b9817abbced7150b38416a6e4945723ed27d7c68316acf8c52ef33e05e2ed66072f239c64215c02801e9b2862793ca0f5cdec5a352cd5d43790bd	\\x00800003a52312ab810dbc63adac2b80e2eb0064127297396152612327bdd1c592b075fc96ce1c3d2cd3fc46c99b47890a24a2f25df03991686187fbf51af68acdfc23bd6eb5d57f53b5fc625257ee69fe0da1603a7c6ddb0f48f384a042c6869b7d3b7b38de55537bc269701d9bf3be793b77fdc5fc2d9ddea9bdbac16926cbfd369145010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xfc92adb29dad07c46c623b1c822b3477078e600a7c03979f79d92b893cd16171675f1d8609f8eb2887dbb246f7ff4b624b0556d199798f298a44612064a32c0c	1579278013000000	1579882813000000	1642350013000000	1673886013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbf72aec0845e8baff66bef070712176a31b33d5af25a2864853e587ecbc93f3e5ceac0d17c9852e6123d4304c115d0af4068bc5b07bb8c6937b560466a7f8d09	\\x00800003d5cbe99e44391925f31d0f084bfea85dc447aa43750f5d6e4a09aa48d2c17db3770b166890c79f2d7e5e311379d84df2be3eb5c359572d580bad479714f8097543089904628b5b4e40c1c5563d557f7699d17cff746c3ae166945df4a63555556c3f20c5a05cdc04b09128ff0283df185153b1ab6cb1c32d3f53d11c6be69463010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x086d0f10456220cba2b7b5951f894c458f540d3ff9c88f1bb63aee6f415a0d30510c0477fac300be564e2fe5db6662afc27459fdb2ee82ed73a2e9ae1f559006	1580487013000000	1581091813000000	1643559013000000	1675095013000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb8f68f73e0e44cce6208011b81cbb1be78a57c4e37538b1ca1c400b19cbd316ef6b509105d709b53e32642dbd14bffdea416ed61d05b558f24324559178ba164	\\x00800003c68a32ed4547b34a1a08970e9d764a492cd53e783820a7b36ccda9c5492b05eb1d7ec19635c859eb8167ec43a5d6960aff2f878e5dddb7309ea9eae88e73155f3a6801f73bfb852ced316fa72481cdf75517519eafc77c454442f9c7549c47cecdda48352da62aafb772f54a011430a9e8a6208b10dac07b2ae700cd71c6f60b010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xc285a559ea0465750aae224298fc349be2a1dd8dbbe238a0bf68894c7848f80517092ec3ad25ffc593c06e5a76ecae9a4afe844c3117426a1859d16e7449cf05	1579882513000000	1580487313000000	1642954513000000	1674490513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xabb0bbfb08e03a3298e27e72a180535679bd5a947c35ac10ba9c8aff8be1760871ebe8c495398788de6e90e72c9dc93803d57a930adfa94c83f2347d7d080582	\\x00800003d699c3aaaded27c705d773ef96afc640f61c5a39ab7df34cbdd9aa5a8f2004694c9454d5b5e01880bddc4e7324bed658e8afe3bef19feb258b19644aec31a20678667899fbadaa939338d013e6686892bb518688e7c0dc4b5e71def297e060d255ec8d9a05a8c076f517e73a83131b72dfd41176b86aeac73b3cc5c2d8726b45010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x8dc56d21458e57b96d575c7dc25b963d170745d6534089cdd0370e7fd7ed101e6f68716bbe065886200141fa43ea77db7c14e57cb661f5abd44737a91403b10f	1581091513000000	1581696313000000	1644163513000000	1675699513000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x50ec37e2e97fac8adf4e671b880335deb82c629b7eecf2704d4a1941d11340c61c37ae1283b8955165f6d6ff91bba8b3d05f8414708afa99dfde841f0ce5efbf	\\x00800003c2399955aa89ced22fea6327d93b53a31b1e800b9bbcfc2fcf0de18fc892476a2e02cb78b851b204a1690ab137ef94bfd5da2b901adc14a9a67e20bc25c797904059e577b4dbe438fbd20238ecb94d0694919919d5d78c6c547782ad0db34378ade135eaee4b58885aac6914e4ece442cf2895bc272f19167bba3951248de18f010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xc77d3dc924895d8bdcfc04aa9c3aabcd42751f04a618d09059046303f86da8d8c3f4110fb721d0b45364bd2f20a067997c746633810149cc5461e93096587b0f	1581696013000000	1582300813000000	1644768013000000	1676304013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0576b16e912cf790e4902bac7eff372a03466faae32f5eaf1f13f61e6840c621e44f72d19d15e2e06187755ce6043db597aef33e2a66aac74070da3964e132d7	\\x00800003c2bc54ddaa3b3127e4de87739d4297265b5e0e1e9639bc4cbd086b95e8ff6a51d5ce600fc36ce2518d429e23bfdb60fd383f6157036b64037c0c5260893bd8eb95a1b69eaf9e1395054bc409d1b9f4910562224ea3fa1cebe79902c5f81d1ac0e1388b15fb494c2920e10845c197d63ae089c13cee27c74f3c469bec07fe92a7010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xaba6a83ad0350f56dd4839acf466f7f1f5016781f796f1e90e78a7efc0fd39b1f8c01c3ab7bb04ebf2e268ffb51b7ac531edee6bda42b999f789ca82275d6a08	1579278013000000	1579882813000000	1642350013000000	1673886013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2bd3a2663d9194b9d953cd3514bc65f012fb112c3def0cd8e5c2339341d1ab4210c95cd3d9323c88b49a8b198474f5fd6c43364ecba7fde0489bfd02fdaa8123	\\x00800003b827d97983853dc9022b0b0505d3c27f239ca64a3321db164914d98eccb8ac9f8f5aadc3be618c9d0a76cb18f08bdad16bd39170da4bbeac16c39f74596bea5c5093c46e8fc8e3079548d268fe5996490bc016c8ef5ab4e00af5250c82796b55b656eba684aa5e018d2682195adc733310009fc3a8e330fb8d5d1ec36b802c49010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xbf3a9d9cbef1fffd06b713e1c42332b2e07614ffa72ba6ab7e14c9dc72daee851a4fb9271bf205f8168e9f0c99d5724083ea3bb8e51091022f75f30dcff2f10f	1580487013000000	1581091813000000	1643559013000000	1675095013000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe3997ac41b2166973f3c8521a1642c4ae3bae9a4489d23933dac722d66df06ebd90c024f0ddfab032e409b981db5d52c38d1e8e528eab1f52afaca4768c6df2b	\\x00800003b94c5d8e7fae660b852cdc3d33021c5dbeee0c4291c266bb38c021d261ecc96a37acfaaaeaa7e86b877ff16631041fe727d465df6e2af162d050a4bdc6bf4eba4298ab62f5d2c14376ebfec8c583bbc63bfb516edb2b986bd1b84cd6291b2331c70ce51eff48f6ac4571c7dc29b8d2512bf2f60b4a0930c29cace3db3856ffe1010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xf48f407922032e6a586192b1c43e08b891527ea7224c7e46ba2ee02b446ae48e1c533034e5d730ee5581d66915ed4ee5e04777b9b5a8c0902c4abb9b8da3780e	1579882513000000	1580487313000000	1642954513000000	1674490513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x28078d3dcac94109c9048c92442c122e76bd3c96e741ecaabf2d6bc7defe699e3eca9b6b00ca25f06c9127db6c029e0c7851ccd377b5529bcfaa701e373bcb17	\\x00800003a564585104896fe4bdadd3e1edb4374e0ff1dfa0228e14ba86d85bd6f6da273624feebeb71e0a3db22cd5afc5f16bc2e5a120a0616cb29f5152b4f0869dd41f095427c66af1973619c172e74d806e86cbf5b520d6810e4d823eaca44c95342859129b0376b3549af1700d7426ff07f39a6135e8d0607322bc718edd377ace0b7010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x9266e2c16fd51dd505e2ae6b3b03dea515772a04d74e6f44b704da4c5569cdb51b094725af4f1410542f6895c182895448c60f184f45627e5e66f6ae72efd603	1581091513000000	1581696313000000	1644163513000000	1675699513000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1ebf706b9e541e1a5cecf4f1f65df898e58dc2adf872bc886e9358e5e37234734259e44cc808165f0b50bfd2934f3d0b2839ef05cba5836cb4eaf3ecbf078388	\\x00800003d3ef2938c4ac9990105bb8762b4e4c3895923823cc1037c1818a3401d39e5cd07b37d20e49f5b51d69b96d4a246b57c1b60c43fe8b798f639b1045ba6c90eae51a6ae6f34810669f534ff09d80002ca34c6759c3fab8af8de720dd52a4b8204f5819e7cc8ebbc9a05a37299df87d0093775bd6e9a1ea1850493b99d68e5ac031010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xc52e0c8be985c99ce6b7469528ec54bfdaeef669147b704506635af5b4cf4d17e2ea97ea0fb9f905103c804569c5eba1ee46897afa28b33979ad6be949bb9a01	1581696013000000	1582300813000000	1644768013000000	1676304013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xee462aeb1c7c5f640288cc2ac3b9f4ada9b20fd5335aa61239a1564e491a692bb3c4a46299398fa2f543d98dd97de62026ee5eeb3d17badcabb3ce2066399242	\\x00800003a788751c9a2f9c638d78582011c97627431f46e80d21acf3ea52f8246d670c8b118bdbec3cdbd2b3b0f69cfcb4e95be38aaadbffaaaf1da20569180e4ba56ea7a67d99db38b130deb9dae328ff7aa548362e7f70d1dd1486c9572194de566fba1dc22452b0003c6947fded1924502ed67e5e5ee15a1978cf6978e264ef542a35010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x8b053e95feeccf28b6481a7e5cfa9e1adf8b801bfc5ab575ad51ea38c4f833c6de5fe4a78e5032e51041d669ae82983922e88c89317291da172975b9f8a72c08	1579278013000000	1579882813000000	1642350013000000	1673886013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6f3283cdcd5cf16734b192c1a4ec5d05725e679a1b66b7540ed31761c0774564c110fbefebf262dffef4949c88f9a69c5bf6b23e91206848c490208a9b6d2fb6	\\x00800003a3d76007779d11491cf9eb81e9e4e3f4bf7287d723e9db54556d8ae53b18693ae35fda0e9639bcfa858a6671ac6122245d0d004540ced35bfd99a744f9734f7034dde38115d5f1046cb6400d8d2411c3ca8173176095e79a9f6b5477ae21650e66e3e076ed41e3c4a1bcc2d088d615f3fc7af530dbe09011a793893dc5e0232d010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x30745b7cec8c6be73d4b9c85ae878dacd2f7b04f0e6b03558ba916ab7ff12e5ae262b20f2b335c37b2c895ce2af8f1316da1288d68184b54be56b83429042b07	1580487013000000	1581091813000000	1643559013000000	1675095013000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa9d36057cc5030c5f9e9d75bbc55457d1644044f33242db51b9cc4139313de7fd714aa96aaeb426b8e8cd9413a98a3d45aab6182a54863ccbbc1219c446f4b78	\\x00800003aec72bd15fa52c065cbbbf0e3760c9e51d2d7e4e37fb415281b834fd6b382c1a82e7f26f1596e5192b70ebe4c38ba1a1aa21e6c4a8eac8de24c0371978098b517330eb680ffb4d59edf41dbfc949ec092f0175e0836cc623d59555b28763e20205346e1f1b233e3d964b71b11b9354d5e2cf11254bca48e68a6eafede72f9889010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xa2fb72781ae93ef8fc480492639baf9b3290aa5b368a758fa330ebc41e9ce9464caa3d82a6ff88f7f22a7495b123adc9f48949bd5c6fb6723f2ea2e6ea5ec704	1579882513000000	1580487313000000	1642954513000000	1674490513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x274466184fbd9549d31cf562cd5a238bf99ab23cb777b350696252938107b3e441fc896ae5f3ddc5e52f5e30cc1dcf6a6af4023d67c78e3f8b9f9510a8a72fc7	\\x00800003df7af4bd74fd72b1bdf86e6f050f1727575824f13dec55373402789ef1849228b90c622402136f1c53ecb1cbf5c22bd1f2e1b335c4bd9207e7217a3e2473efa259fea4c619d37f38262be7fe7d529b1c1ed3955bee74472f47ddc6d0180dedf74b789666ec600c16f089b545aebc2a8c13656a2d7b875e7194531695718b8aad010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x286198a971654a9c13789a390ad02b23173c57953339199a8ecd5d34dd7d9edc3f789eeeb8a6f14b7d02a672b813859b5504005282e0acb7dcaf913b9ca5020e	1581091513000000	1581696313000000	1644163513000000	1675699513000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x947985c74c0984e4a260bb00592cf4a88eda15e0bba72adeb6d8d0b2bf1aa382fddaa384b9b07847244a74224a57f578fb3b8826354be15f47cae76ac14a264e	\\x00800003c401e491f7f486cfcebe2c61f678746fbca538cfb989790a3558fb5571411b372424448f47bcc1d8fb5de03cfc4fe3440ed7f7fec2e4270cb33a00f2970f85e60752721df8f5f1c03e5d72915a21d2f1af6ef6911817f97111aca981594d5442e0f2714e98e5b0f220a0b42cc54b80288910bc9b910bc5c61315cb56aa4b2637010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xc0bab179aecba7ce83eae741db34aa6601022088886c4ed315eec860b930f23738d838fc66ae68b4b8a95788deadd63e59f32d2db716a4d567ae6162ae15600e	1581696013000000	1582300813000000	1644768013000000	1676304013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x87eb9ae908ea78ed45c4529bba457a907b3f39ba78a2bfb330114d2df93756431061b736e3920331180b23cf0c9a0335536af832583d342ae37438593de74935	\\x00800003b9f70096466650f505e40a151bcc3e469f7c9e9f34fed05692bbaf6cffd9846a702db7e48fa6ddf54095362419d361b2ddf62c43834bb9b040384f0c13085ee2400fc90ecb789bdc25e43bef2ba1b5d0a7546fc621ca3f686a7a888083ed0ab95b4d0a8d799c0f1d5eec5ce802d21110ebbe1518bc5040c11da59c10459cde55010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x281f2f16c16df68d73273e7a4e5c0cab21f97d122598a47f3e70573a4e854da6fbd8012a757abe42e0fda80fadb78d79e7963b8070245ae49506c9d8b3a2670f	1579278013000000	1579882813000000	1642350013000000	1673886013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc26eb7568d4293a8d302ce3d6c7cd775f4efff039926137f62d7adfd27199adb0cff109b034569700afe2169d72f5ce0a8456f56e359c7b28a57ad42b13872b	\\x008000039d1bd5d368bf22ea3120a8dfbc76e2ffc50dacd058ae527300b4edb5cc72ed7edc9e7963b0bd041ce9ea8ec538f28e077299ee60af02f5fb04acbf2b69e56d548a26e1fec2cabd570ba3aa5b562b0bba7442b9725d83e7ec85b4c638c0f9083afac1475f0bff76226ce31e017e45c1f46be73616eaeebe22146f88bc4590bfc1010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xeef6ca4e47c9e2d491a09a387c6d5b54aea355faab118dc1b85522efb8a1fe4217799534b894d84f04e50bde3dda20eb5d210c53094c8fa3dcf5641b5bac6c0e	1580487013000000	1581091813000000	1643559013000000	1675095013000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x164795506d1092a8aac5bfac433af1db9a8ed12174428cdc928444e81b2c91ce50a21a212fe7946fa33f69227324eb46d6c0f677b6799b33c40ff54647fb2340	\\x00800003a81560dd64f017d189d597555a15d65852f754765e984be19a9a1ebc2645a10094b7aadd6888a66619ad56ed1285576d68708b1199b05993eea25486947ccf56abacaaaa01705cc667d97c148e27bf218ed3a25719172785887bd5e136896a6758c54418d102c1d38bd886b366ff21c499de8dfd6e6255d74de63571ecabccb9010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x4a02db2b8a175e73fae0af86bc38f5a603a0e07d311db87b1b4e9d1a91d819d95ac26e39b16b6834527e27cc8f550b4a08ec2e3ea04929fe087cacb854e8540f	1579882513000000	1580487313000000	1642954513000000	1674490513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x12b9429ea20364676f0d81c18795542163ef599354021213359919294cea476eee7174ad59fb3f8744a18d35279a958f19bb2cf7ac196d71fb70581583d650b1	\\x00800003abca4915935f463fa258ba76498eb0cbdd5a7f3e20b5a7ecc4125c09e5ca2ea46fc444f158073d066850bb7fe46efdf04371c558d31fe3f0afde00b6a182a42ec264deaac623eea286d8f399c922bf737318ba774348ea2c96d138c009a2766ca3361b975f53a3e86ebeb04164cf71e45786dae08c87de35d9ed409897bb8fef010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xa52642f074669ac328af4cb88488406a8cd3161321096eac214b784ce63507d425932e55e8a287ac44416df15454624a73e20fe27d9b47a6bc112b7d6e070001	1581091513000000	1581696313000000	1644163513000000	1675699513000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0f173ef0f70749b795c9abbf916367354e17920b76506b4e5ed73390f3d59a6776af7e365ffdb6e9be71d70746bb0989af644d4605871cae19b42dc6dc3f2403	\\x00800003af30559f642fb09adc8be480eafe3e884da079c8ef144cb113cd0d3296472a472df57183115afe736e78e8d8b223b5521aa0da2d47a992987c70c92bc76b6dd9d0e7967573c4d24ab4a800ec88bb700ea90d623bf5e29e44a0a5048e9a025c4715fc476e262cefafa82674815741cc67485e163857c076f2d1af1325710023bb010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xe3950facd1561f24527d3a22406e139b7b0a5324a3b928ad5f0f33bbae60e7cb258b56c7c25a7351200b1776a9c31c1f0f043228e9ca599020729038ff13fd0d	1581696013000000	1582300813000000	1644768013000000	1676304013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2025dcd60b83518bb1458bf0e29b4e99eac705ad76f5ed755038896cccc2cb57a60d82515ed37b008502f212b8142bfc191d7a19b048a734060d02111efbd62a	\\x00800003bc8db44e6814c3b0120f622e78c5e64f9a751b98406dda0c4b282830cfc7cb2d5aba1739d6ce2b515f95cfcb0a24644d734d176cf0232474714dffb8dac0f3e8f8332fbcb89f1aab0b3dbfd546b583fc6698a5a304997a9e85212ef21c744ba3c0c5ece466e507c5c40f620f5c6e0c2fc42cb8ef435943da042c245949cca555010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\xfb16136920ea0e487fd22b2f1174494679720a3c9c31101f2e7dd305b8284b0ae10b999893aba483569528847a26a2369854a82f4eb1e2f3bcd3b876cb63e80e	1579278013000000	1579882813000000	1642350013000000	1673886013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf801b473310c753de07efd34e2c2f53343381ba90954131b1038126225835c3862a412c4f066943613101737fcfaf85a43012c900609a30a3d427f09c8b213d5	\\x00800003b91e77578a8f034f743938aaf108f32c9399357b0879f81dffaa181ab5985343c8742e28ba9d219cc351af52e02e38bec896f65b9238256f9ae45deb3280544111f6f0240d0cab49264cda48f5e30e094825898244cc644545293089f5811fcb2d10b8a9470aadb44122353754dc8fe2d58a25dcb4066d0cf78ec3d583dcc159010001	\\x223a6d67bd67c0f32543f044fb76940e97922b72419d73c2a99d1bf3d0157bd9	\\x0303a09e5d903825ca26e2916862462759500cd0151e2180642517b8b93f4cd571714195f96251ac983ac3829bb00c51f3725b6e30df5b70e947439f625d7501	1580487013000000	1581091813000000	1643559013000000	1675095013000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
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
1	contenttypes	0001_initial	2020-01-17 17:20:24.022012+01
2	auth	0001_initial	2020-01-17 17:20:24.04547+01
3	app	0001_initial	2020-01-17 17:20:24.090221+01
4	contenttypes	0002_remove_content_type_name	2020-01-17 17:20:24.110024+01
5	auth	0002_alter_permission_name_max_length	2020-01-17 17:20:24.113183+01
6	auth	0003_alter_user_email_max_length	2020-01-17 17:20:24.118582+01
7	auth	0004_alter_user_username_opts	2020-01-17 17:20:24.125634+01
8	auth	0005_alter_user_last_login_null	2020-01-17 17:20:24.132842+01
9	auth	0006_require_contenttypes_0002	2020-01-17 17:20:24.134164+01
10	auth	0007_alter_validators_add_error_messages	2020-01-17 17:20:24.139532+01
11	auth	0008_alter_user_username_max_length	2020-01-17 17:20:24.147327+01
12	auth	0009_alter_user_last_name_max_length	2020-01-17 17:20:24.154592+01
13	auth	0010_alter_group_name_max_length	2020-01-17 17:20:24.162279+01
14	auth	0011_update_proxy_permissions	2020-01-17 17:20:24.168301+01
15	sessions	0001_initial	2020-01-17 17:20:24.172541+01
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
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
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
-- Data for Name: payback; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payback (payback_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: payback_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payback_refresh (payback_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
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
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
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

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 11, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 1, true);


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

SELECT pg_catalog.setval('public.auth_user_id_seq', 11, true);


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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 1, false);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, false);


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payback_payback_uuid_seq', 1, false);


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payback_refresh_payback_refresh_uuid_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1, false);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 1, false);


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
-- Name: payback payback_payback_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_payback_uuid_key UNIQUE (payback_uuid);


--
-- Name: payback_refresh payback_refresh_payback_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_payback_refresh_uuid_key UNIQUE (payback_refresh_uuid);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


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
-- Name: payback_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_by_coin_index ON public.payback USING btree (coin_pub);


--
-- Name: payback_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_by_h_blind_ev ON public.payback USING btree (h_blind_ev);


--
-- Name: payback_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_for_by_reserve ON public.payback USING btree (coin_pub, h_blind_ev);


--
-- Name: payback_refresh_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_by_coin_index ON public.payback_refresh USING btree (coin_pub);


--
-- Name: payback_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_by_h_blind_ev ON public.payback_refresh USING btree (h_blind_ev);


--
-- Name: payback_refresh_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_for_by_reserve ON public.payback_refresh USING btree (coin_pub, h_blind_ev);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


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
-- Name: payback payback_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback payback_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.reserves_out(h_blind_ev) ON DELETE CASCADE;


--
-- Name: payback_refresh payback_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback_refresh payback_refresh_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.refresh_revealed_coins(h_coin_ev) ON DELETE CASCADE;


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

