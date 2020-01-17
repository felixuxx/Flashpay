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
auditor-0001	2020-01-17 23:11:36.598994+01	grothoff	{}	{}
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
t	1	-TESTKUDOS:100	1
f	11	+TESTKUDOS:90	11
t	2	+TESTKUDOS:10	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2020-01-17 23:11:43.466444+01	f	11	1
2	TESTKUDOS:10	069JJVXE40D948W2S933NBWCM0FA4ZZ53YG3MNW7EAECB18VN21G	2020-01-17 23:11:43.561395+01	f	2	11
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
\\x5acc3bf567651f044f7e2a463a1eca4425efbbee2ce390ea165fa4d6f400a787abbf95ae340d939295a804c4242eb7ca29e270c06cc7086ba3f672d9e2a3e518	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1579903887000000	1642371087000000	1673907087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0007045d7a0a8ffc5840f5eac7f7f1132613e10c34db47f4d352ec28e309c9f586bee8d594f81e5dff4f858e98347c89320870426e438e5b91247b00b9bdd0f8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579903587000000	1580508387000000	1642975587000000	1674511587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x52a4e40578581ab42e2b6476b5737c05542f98037a7fd6aa5f64e26f8d1cb0187bd2fcb36557b4b2fc5ea8e336ce0ce2b70c6d5bb866d0700a99767390391084	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1580508087000000	1581112887000000	1643580087000000	1675116087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x85cc69aa202f5f03689399f75c3191774c889f0cda78c7b5490382a64dbc913227e0da469ac97160200768a69803e8f2102a689c1e63569a1248aa359a04e19e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581112587000000	1581717387000000	1644184587000000	1675720587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x15c862f5eadec89b73d671c1b86ef88369fa8a1d92adcca567f8ccbbbc4c8b35a56dd950c163109e068aab1ee3d7cd44061492026e81185fde3debd197375952	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581717087000000	1582321887000000	1644789087000000	1676325087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdd6c91bcf05a672149f4b430c8db3c0b4f365f51a3447f67aa24871196c78573703a102c7f6a5d802d6652e944206fa0a448e5b785db58577ace65768ca0c548	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582321587000000	1582926387000000	1645393587000000	1676929587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e41d721088bb3eda0e5854ca17907d284248ca294af3d069fbbdea57921609f9f88c63facf3d2478b042c12691dc66e714c5c85b11e2d056558ead83f2f3d5c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582926087000000	1583530887000000	1645998087000000	1677534087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd21645a9a4417554096a4164af4f4b20fb34993be968151e7d1034619b09f672febdfaed1b4074862c9765a206588996be30d5030736bbaab9486e1bfa0c4b8a	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1583530587000000	1584135387000000	1646602587000000	1678138587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x99432448fca69fa54406c26e3f586bacb7863ba8aa50915fb303ef9de05fbc64a1966226b124b6373195995903d7e462352cc190b7db01dd292a0bdbc3827bab	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584135087000000	1584739887000000	1647207087000000	1678743087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ca8cb9a098b9917617a3414afc007052e477023ad33d26c52197d1793a2dd93d2dfc0e28da2082fd414b3c6a11a058f6b014d580b3b4a8ac7009b2a4c127155	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584739587000000	1585344387000000	1647811587000000	1679347587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d68ac6b77bd42b7fff2162a6c53b848502f6e3b38e275a9eccff3a5fdc0ba054b9536f5eb25207e11bf5e808caa9032697d7bfa26142534325bc9947ae8391f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585344087000000	1585948887000000	1648416087000000	1679952087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe78d6f31690df7df3f546112ae9ecd3bcc94e44aba7630f6ea6c72766aeec67359ce6db029fd76db5ec0ffcb0a9bce8d02e966d2faee2f6c0a697395a976139	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585948587000000	1586553387000000	1649020587000000	1680556587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd504e95111a1ed3eb122cbee8e5159f966ef116a52da53c679f65c132dc3d51f47a7e490cc335054fd2ddbd0147999d1c3a48c21a085966d60bbcb768b0437ad	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1586553087000000	1587157887000000	1649625087000000	1681161087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19353f882bcabd89f9a53767ee50a180f6fe2acd30f1b154a021b73281c9b97bc9e1cc760e99b3ee5f7bcdc5e2e98bd45943599e5ae99e7102972d02e543d67b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587157587000000	1587762387000000	1650229587000000	1681765587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x06f5628f573c75bf488cc058b362c84a6fcd70c2d31640f12eaf889a2ba3952f76f74cddefff3d7397696bfc0184932a7150cdee5ef9c779826dce802f1a5547	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587762087000000	1588366887000000	1650834087000000	1682370087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd80e44b66cfdc523a6feda3d2371b35af6a896d38ea03e1ae605dbd20ebe5e478e192f05d1c39a075af1375f7c890b9cbbfd644d687a3b8f97b1444a6e38fe76	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588366587000000	1588971387000000	1651438587000000	1682974587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdef22e325378fcbd70e40c2e7d068806c9fce1e6155a7c854ee3a917a0fecadf58bd178f47fae0004e338d573bca2821f8b72093b17affeb77b4b3b6ef671dc2	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588971087000000	1589575887000000	1652043087000000	1683579087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd81da77b35c3db5fa92fbfd592f002e75c4267a90f08917b37e4618c6c091f7e385388844d50c7021084d433887704a3a545255fdaead0085364f95a1e843693	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1589575587000000	1590180387000000	1652647587000000	1684183587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd74b2a4f7793b6b09f83c55f222fa5840cb8147f44e5c5254472074d0a35168961846a47213476d7333c9e7222b66af1a9a9a5044819f405b47c2b1040d3d532	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590180087000000	1590784887000000	1653252087000000	1684788087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0370f47ce83a856627c1065be01235073ec14f98a45a4234c9d64e28e3671d2816c8ab18b48caaf7acc64d3f34fd53dc92757fa7cb26f33130a39411ddb7b4eb	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590784587000000	1591389387000000	1653856587000000	1685392587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ec41047fdb4e66f3fc8b64ad3e38c18c2ce1d3be00b2c9e3872b3860fbb540cda12cb7d0e9da406a8135689d75d67eda126a7287371ee5f7b165c256ac75fc2	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591389087000000	1591993887000000	1654461087000000	1685997087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ba5088bc2e725332c91a32f39ecb5380d2f352853ffa67571cb419e9a4adcc4f3e8f9ddcd5397dcf5741ae1f34ab2c1addad96369017af1cfe6e170e64f500f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591993587000000	1592598387000000	1655065587000000	1686601587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa26e580ff2436079de8b7082cbdf31cfca1e981145422078ee422fe778c9990fa32631961dbf511bbd7e916ffe0c6b3b513b2910414eee55b161edcad3bb35d7	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1592598087000000	1593202887000000	1655670087000000	1687206087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ab7f561b15338b2078fbac1340046d0dfbd705d903e2dfebe71318e2008dcbfa7652db4a07be5335a5e519aa833bf16d8eaeaf3093d6b9c22c05c3b4b155f5d	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593202587000000	1593807387000000	1656274587000000	1687810587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb90337eb2b449affb7f908d20bffdd3c8e33c063f16ef8ba0f920b515dc64921ea75d1e88661bab2db02e359687f75404c962636d403b7f7200b13f0a8311207	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593807087000000	1594411887000000	1656879087000000	1688415087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xba9337971c2a2d095f42c6f654d4824b3a518448768328f68994184eb98c7575c29c4050e0dc63d82ea1cc36ddad5da8f8430d14e1911ef8bc9a4afe2f0448fb	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1594411587000000	1595016387000000	1657483587000000	1689019587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77b9cb25545aa82a2290c87e8090d0aa733b9579e09240d9db05eb4bb833e44cfc04e5cceca8798c4c0b8eb6f560c5b5a6a47eca7caf123dbef48d3860f2c4d0	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595016087000000	1595620887000000	1658088087000000	1689624087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4724460320099639814fe015abddf55cbce5686458079acda22bc003f35888609c1d760a2c60af462f793041be318d3cfc5ab0945d96502f40b1d9d3d5c5c22e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595620587000000	1596225387000000	1658692587000000	1690228587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf34cff0228f75aa8a2da3062bc4200560dca6ec7541b09d15e1bf72e77ce1ad0f1d79de5373e55b3ff47d7c7daf84ac79964082e62e274a10c1219c153ca079a	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596225087000000	1596829887000000	1659297087000000	1690833087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d8ddfdcf7ee6e7ccf7f1a38dfaad0fc642c8b585457cb7ea381dc83364334e64389f90a33d62457578452373ecbb0ea5b1de525e8e7da7733d475af02ada5dd	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596829587000000	1597434387000000	1659901587000000	1691437587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xec67f81756856742f834d34f0fc2d41d71bad24dd503d01b09c9ae756fd027cc107a70e58ec6be6b2f1c593d7bcd611b255cbeed2a2bb138ff47fd5ce611ada6	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1597434087000000	1598038887000000	1660506087000000	1692042087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x675f2d4ba5fea57c587e9517b05b1c9ea6e46faa7ae099f42377af511503667e7fb333b1a6ee732d98e0072e9a3aa4ec1098b49c5c6285203b4d8d3dc36b8b9e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598038587000000	1598643387000000	1661110587000000	1692646587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77149d2bbe72d08a304f30c1cd5eb67e47dee06e7e02733737a8cf972e90cb9a7db17233d1ba4a1f95169e781b18dd820d0e4477d8f2625374bbcf69b2ddb182	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598643087000000	1599247887000000	1661715087000000	1693251087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9cf82166e19308568ec964e4d77e2c2ee5b1b2efb1c32b0231e50a05910035a1ecf4d2e9b823351083f822612286acd2aaa0815cb822ad3332032d9f6797cea	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1579903887000000	1642371087000000	1673907087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8caf10994e162e7e58adb2274b33cd400f73a72d7512736d3faece59be7a59e0f24aaf82bc93f3277b732ddd71ef62a6e346294970f5f36797ab32145b76f263	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579903587000000	1580508387000000	1642975587000000	1674511587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf58603ea8aa79f746dc1b3eb0281323887c0d1df84fd8e489a93c47afd874e5e8f8572a554aba59e7a2d05fcd1d226907fbc3648470504ca997fa2e4c55965dd	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1580508087000000	1581112887000000	1643580087000000	1675116087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1119bc1627be568a22e1731a6d724682bccd82877b0bd3e306cc9c974e9188b93081e29f8283796e1e251705d8c07867d4bbe578bb7ac3a02824715f56eea841	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581112587000000	1581717387000000	1644184587000000	1675720587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x025f6e8928bf234406ba92110d99846516c2cf71e0a9745e005a730036b6d2e8d382591a70a5c841b9b0007029fb2a312392a634cc0a2a898a4764eb7429bf2e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581717087000000	1582321887000000	1644789087000000	1676325087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x214246a8871bf9410312b5e483defbf123205b60b08f89053681897a2fa74154f66317a360f8c5f883b07254aa134808b9b78fdeb14d64230c333a3167b809fc	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582321587000000	1582926387000000	1645393587000000	1676929587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd0db2f2215feb0f7e234f08ab87ea054ad1975b667c045966553dd04f4242cd49764cf92d7b5a5318022e1a10ab17622aa52887b67d2e7bb1520bd100f39bd98	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582926087000000	1583530887000000	1645998087000000	1677534087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2a31fec868b77efef56b88a294c75962ab6e24230c1f872489eff6cf3d30f3be8166df11b72d24df4c91875b32063d2d1646226cd5060bc8158101d2291090cf	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1583530587000000	1584135387000000	1646602587000000	1678138587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4b8a9ca98ab79c9eda3582e101efe4e8b4aa75cf3ee823134796ec0ae76b463ae4eb7583320adb5147c53dc9b41734fcb4eb3739afa06d6235f7edad3ed95013	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584135087000000	1584739887000000	1647207087000000	1678743087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2f0ba7638282cc5fc53948e717b111aacaea626ed13ccdc884a6efe8214313b84ec5948618fd485ad04cc9b30f9d427c0dc01447825d2d578227dd00d236f96f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584739587000000	1585344387000000	1647811587000000	1679347587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb48a9de9b67b7441b9d2a0526881ffdc21163ea50409d46ccc7c006055de3df88f67e4c872bfdd079afe4cc483bff080e094a9536f9463b23f9bc7df9828bb6f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585344087000000	1585948887000000	1648416087000000	1679952087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5ee07c3a8e2201df654a008bf35771f2148a5e0983c229c7c564190c42dd6edb5b1d4c1e9b4c89d19098f5aba6ea8e9a6bc97d4652745053eeede05bf5cd05bb	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585948587000000	1586553387000000	1649020587000000	1680556587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaaf4c5dcf461089df32e5a78bfbb6f2f500253a0978a705a489642ea851a948094e3ee239c087b9e99ae7d7247693b0a2f98476af75cc4e3d1e5965c172fa26f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1586553087000000	1587157887000000	1649625087000000	1681161087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xff3a405cc164db604e3c743dd48a05132ddc5fe551325a11a8c73541e01a195961eafc71b750bed74ae5f655abdccbaf1d8ba3e5a1b43acbd543ce6cc3a638f6	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587157587000000	1587762387000000	1650229587000000	1681765587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x256ebd039889b9908d668f754be719b13149e158d402a0760626b17f1143576268f51c69dfb95db1c78cfdb9e98192c5d976423bf3ecc0ba87ef9c5b5e8bdf64	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587762087000000	1588366887000000	1650834087000000	1682370087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe99ad3bf7f38354674015547a51ce0cd3bc6b4196d56e68bcd936a7ec6f797dc391f3360230de2ba0b5fbd4f7d26f67e1c3cb60f67b126cd7ab911a5ae7e5108	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588366587000000	1588971387000000	1651438587000000	1682974587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf987db5409a19d1ca84bc4cba3b4f347bf073f80286b3a84191f4c693c390f34364a1e2c6db47933125e5aade729f20977b6c241b0986899dea70e15b418fcb0	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588971087000000	1589575887000000	1652043087000000	1683579087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8e6dce5939ebe3f3e91d261d97d9f50a939307ec876a8e0b0148a5f5dffe4280ee0f3a29dcbfb3c1ffa8aac7d102c5b0c8e1b736b17e5e58caf1e78fe2f7770a	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1589575587000000	1590180387000000	1652647587000000	1684183587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdd2783a3f8493ecbf60da82af72dbb8d4769f42d325c05da68f061a90dcf839443edf6c59b4745b02bd6655a10daaf0711daeedf2aa0109d38a38fbc9b1b2ef3	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590180087000000	1590784887000000	1653252087000000	1684788087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf26367a95852f3110cd4212eae0f209ae063fd27faaf1db8a5ac139a67dc3baef606dc7e7254dabe09454ba0225eece1786cbe9e9bdd9f77f478faea9e9686d6	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590784587000000	1591389387000000	1653856587000000	1685392587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6071bdc8f795ca69cab74e82efeb239e94adc36f2ed04624df5a69a6e9c5e8ea7bb8997726089539018dee9072253e8bb9cbb7deba4099e7b7d4e78682a9149c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591389087000000	1591993887000000	1654461087000000	1685997087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x08c9aec16ca191bca8f1adafa6cd40faf00b97713796c16ba7ac1fc9bf06411795fca013d967e7482d942877d1091ea682725f58bc90fb32fb61285b3e886562	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591993587000000	1592598387000000	1655065587000000	1686601587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x309181d3cd94d7f9bcfea6c2366655274a245702f086b3f96adcecdceba46acca9ecde1f51c013c9dded3f7a5bb38055ea823495a900d5f5e12f24a0c1f9a1a4	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1592598087000000	1593202887000000	1655670087000000	1687206087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe978423451b40c4f305ca39bc94039a261299e5ac7de8bef46e486f7eaa8cb2ad299c56add78dab6daad3c3b3365f07d605d3625f6ab963c6046292496bbc6a7	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593202587000000	1593807387000000	1656274587000000	1687810587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5fa0e003d86f2b44d60a539c718b8448653874d239c8806b5a1eac77787131ef267113f38285bc52658f670f32d3abd609a2ff801885343cb4d8bbf4b7ab9cfe	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593807087000000	1594411887000000	1656879087000000	1688415087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf6eac3956d52574fc9f3fa432dd66a1ecf520a74158cc5c98e8d118adc711ef27eca22c797ee89c183b911e153243d38e3ffb74f33b5d0a411ae320c87b083e3	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1594411587000000	1595016387000000	1657483587000000	1689019587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x65dfc5be1b41ecc16cd10b93767973e062510673bdd794b40f9042e8f708978863c254c600bfed3b9ea3ebb6cd68243ac28e4501fbeee419b1a05f552938d29f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595016087000000	1595620887000000	1658088087000000	1689624087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0c83a63dbe876d8cdc17fc3da508e8f4e1af0be59a05f8b193d235f4e08e843b4d9ea04bab663a2f57c2b1c087dd8d56f056608b842c73eb2c152f5820f42305	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595620587000000	1596225387000000	1658692587000000	1690228587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2be9cc40db941928e11d6a31032ddb220fe741c276e3519bb0f2177d8cbb4cececb578eb7b7d67e0da54c657722cac08aa5c3adcc2addc14b807ad6f042488f0	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596225087000000	1596829887000000	1659297087000000	1690833087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x85f12fc3951b420388eec248bf3b9b60f5745369ae90809efa7f8c47a1362d1ea9ee4c37832ea7e44a5b0bc7100bf20794fb9971a19f9bcfa4e5492209dd7536	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596829587000000	1597434387000000	1659901587000000	1691437587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9fa80821aa5dd0f765657be74d303ad260386c0a54c8eb043791e800ff3f52b06a447eca43e40bc1ba55bd56b8f3f91c18baa6a088dd03e4833d1560dd5b2514	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1597434087000000	1598038887000000	1660506087000000	1692042087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9c93c6547e1f8806d550eb7777b6952c96521a92bcbee415cde1c6627cc6190d416702ba69bf1043631ccf2dd6972efda77cb05be4a4c37a9f4dd4dc3a85aea4	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598038587000000	1598643387000000	1661110587000000	1692646587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa42606fe1cb2f3eb37a3e298aef84c3d4b9fc1ae04ec0f72f4b5bba4ec92697e2b3587e231b51e94afcd8b4701637ce50b90037882a8dabc4d62f3a08b72db5e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598643087000000	1599247887000000	1661715087000000	1693251087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x295e467a2b0ecf360eddda0ebcf9da228097b67e2ee62cee1f0afd217895beb4b0b23fec2f9d7424958ffebe23d766a064f0df87916f01faec8929d51ce4bd46	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1579903887000000	1642371087000000	1673907087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x13f300832405dd07f6e90cfc9874081d4ccac4fe07eb1b06ac613de1ccc3a6a9a0cb1ad7464d12fd8d69b7731d163423110f9f61901bfb60779769063c0060c4	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579903587000000	1580508387000000	1642975587000000	1674511587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x06ef4fb40d676d73dfa41fdd7f7e73a6feafc3f5e6030f74443a93a88329e2d90eab82aace5ab3816ff451d81d797f6ae49155a5457a42384ae95e6794f34cf3	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1580508087000000	1581112887000000	1643580087000000	1675116087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x050e2089e522de99e2c985d886d93ff1577cbe1497f6b6f8f4823820646af1dc79da879f5c6de370c98128db2f3f295fb967fe9c907fe176195415754761a0e5	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581112587000000	1581717387000000	1644184587000000	1675720587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c9791e05c2e87a73b438daa2d1d231bd14f5c9e614479ece5075075b20cc9279e0d8be5864544504193c055b62e3427f057355b1cd73cb1976c8c8ab407a16e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581717087000000	1582321887000000	1644789087000000	1676325087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1f839c1f1f4c4e4824f6edb168aa531bc6941998cfb7a626000d684da408f4df418ba282a9c682bc5de6eb93baf3a8104150fefec6be09e86bd6c9a3f8dc6511	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582321587000000	1582926387000000	1645393587000000	1676929587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x03de355148220a29d221cd4c7a4c59ca3faef9777bcc9859c388570b7a3c37b6f542b8e3f1995e3a9422cc4b5bef2404425d1b4782757f1b39d4f14230b97d15	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582926087000000	1583530887000000	1645998087000000	1677534087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaab093015b813fafe1047b05f7b6f93ca2167f04f6eedbacacb5c5889e569f414b9ab92fbed7ead5673c14976d892ad451e181a25b20956bf170e30f5256c096	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1583530587000000	1584135387000000	1646602587000000	1678138587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6934d97776061f30cb1d1a049813bb1c9f8cdc9c68a24b48632f18508b73d75417ae62e67f8bb485cc63cd1fe41fc7b016cb75d79ac14a2e6e907cd300471ee1	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584135087000000	1584739887000000	1647207087000000	1678743087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb4f60da9c027ae30e73c6b4cc65ff736dc5bd07ad7f217e2892d0fb724734fa3eceb66be677d3f75f8cab7e6d5f73dcde6a585adac4d24a2cff2d5f2d32d1bd	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584739587000000	1585344387000000	1647811587000000	1679347587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8ddbdb9c48f947b0e2f6542d242c216765459ec5e69c3c0a4928c2b1237cfd16160481f45454f04b4564d0e555cd93c3996497bf8ebd1d21b1d234828f30dcb	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585344087000000	1585948887000000	1648416087000000	1679952087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2e8ec84d67c6c53c1cd09d0ee5b39a49e41f16b7a6a3e562d9acfacc9c2676ece1f405da515094a3f593bb52675825060f29e589b2e4d71c81dd2d395cf866c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585948587000000	1586553387000000	1649020587000000	1680556587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa1fdbc30d4e6731a57a4cd4c4f6a88a4a1ba0ab8f99f22fa464bf11073abbc45f94b3b65c7467cb61c927936a463c5fcf77ac5e1265483c496872ca5ff3e482b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1586553087000000	1587157887000000	1649625087000000	1681161087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x997582760cb8447176dd19ebd5d263801c5835c0eb080b31ee64b852c21a574fc2280e4add26aaac0ad734ed4588e00062955c6ac24f5f3bf2a419a9d496a534	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587157587000000	1587762387000000	1650229587000000	1681765587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa38f6d7110c824941410775e696b3067a890202832259706fcf838da965c999b382c91065efc7d5ff0bad9b82120d0eda3f49ae8e69d7601fe0973661393f1f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587762087000000	1588366887000000	1650834087000000	1682370087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0894488847a8bfe160446b95cb7751f7620291715d3d0b1b9e08d2fab9de854bc1b61cf45dc57c4707d8be7f1f4c36ea131aa00de99b95b5e0d019c0f12b5c33	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588366587000000	1588971387000000	1651438587000000	1682974587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x66d7cd07abd4c65ee87724fe7d925c320b57be73eda21e3a8420697eff520c50b6d5e67a8288289477828201e3467b0557502512f8d7c2c3c6ff4ff938dcdfa5	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588971087000000	1589575887000000	1652043087000000	1683579087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b5ff56961df46da2dbdd0a485f74cb95f7b7f56dc6aafdd6ca19211b1d88c979342785d7a0e5efbccdca9cadf77e80786334d3842790829b636c2526261b741	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1589575587000000	1590180387000000	1652647587000000	1684183587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8da34a6fc0e79282a254330104225be8d355babd2dc42b8efb3f5b60e6d125c4ef9ab2500c9abbc7d22b459450c2fcc895cf91e00b0e8eddac03b60dbd9f0b59	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590180087000000	1590784887000000	1653252087000000	1684788087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdd7571c4d3621f5270da0d3b689f1d20d20e9d6e6011fe661c9e845dcd1ba6136cede95c68f339ebd0753420a5b3b7033793e598343ac83285ebf81fb430357a	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590784587000000	1591389387000000	1653856587000000	1685392587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x276251ae5210a54bd6469184a259143c6c3a823b204ce852e75e4d17bfdffe23dbc6f804b9639030fee99162894cee275f671dcaeb4123028aaa02cbb25f757d	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591389087000000	1591993887000000	1654461087000000	1685997087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x30d11e9d9767062c83b9993eace3981679e3863e966658fab97d83ba37f95ab9d3323fe0ee8ab57080e899cf25b93d4883db668be31f77a3025c352609b07e70	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591993587000000	1592598387000000	1655065587000000	1686601587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x57d26d81d4b282071a1ca478302165ae686f63c769078927be82d049f4b027cc1ed7ced6e097618d04fc62142a652f9b83a3e9341f704d6783c2669e0260978e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1592598087000000	1593202887000000	1655670087000000	1687206087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c4f644488dd30725c7d241e2b073eeec018e34246e2bd2cf60c1c951acc5d270c1dad4c75726195cb6a788e48ce7acd91f86d30daabbb78e5c3953ea3f53b95	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593202587000000	1593807387000000	1656274587000000	1687810587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1877eebb3d42b5767e6fc3c42933fefb32e3bac26e57f42a50d29444635fbebdfbd4095d0e6404248a84aba5cdf11013e814ec5b111dc13a1f29a7e9705681ad	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593807087000000	1594411887000000	1656879087000000	1688415087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb443cb649b80bf0006986520487512f27fff380d33296688827b0def620e1fe0d53d25888695fc4c610550abf146fb17dc087893dcc471a657f90e2c86016ab2	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1594411587000000	1595016387000000	1657483587000000	1689019587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6fe94ef861190025713687fae434821dda5243db5de1fb4b612f64f9f0e0ea2b164552928b8fc8b0040fed9c7de430d8b11df25f727157d710555ea8adc1b87b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595016087000000	1595620887000000	1658088087000000	1689624087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd82c98478612862b8ca34e1cc359ea31a92c2d0b4a08974d055ede8568339bf0310c8adb7def82abb9515de0424c0ab8416ce7e52cc1442ef95a17a20c5d8586	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595620587000000	1596225387000000	1658692587000000	1690228587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfbaa423687705dc49a19329485dd9fb993d419efcb8df00aff988e348a38a2d36ecc29a5b59dca39ce5a81fc5f9ed55a129162db4dc6640bdaba5c97a8754c66	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596225087000000	1596829887000000	1659297087000000	1690833087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1fd88b8328b614b151358fd3341a3ce210fbd34d650d29f9ad8d60f1deefab6fd3fea8c501df1f17604ca1027b005991411d305db08e3c0b7001167e214ec507	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596829587000000	1597434387000000	1659901587000000	1691437587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d1c214dc2981b74b46b6189ec4201062cb458470767791c68963bf420cb20022948c31231b7d1027138c67f185cfbe249caa0303a33f6abfd03bbdfac3caf7c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1597434087000000	1598038887000000	1660506087000000	1692042087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1aa4e91b7d22ed0949663b87161428f6ed054eb38f89d2e8a752655baed1511d0c2d64bb259a139f92c4f2209fbf30e5bc39b7c0fd9c4deb6bd980a37de027d1	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598038587000000	1598643387000000	1661110587000000	1692646587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x692abe861aa7e5c09d7287d2d18a0445c6ba473b4f816faf66b5a1766d76b80e9b94c21b0d8ea92ce363262fe09bedddff82bfffd676adf17021c7facf4ec1b8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598643087000000	1599247887000000	1661715087000000	1693251087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x534c398f7d6ab48aa73f26101aa54475f09703a0eda6917f0b9b4182a7a2233afdb827e021744790f3e46839586298f17a0f87195ac58fe3e8cb4e821ec62e65	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1579903887000000	1642371087000000	1673907087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d86cc3a618d24ae15f5f42764275adb465e638d3b44ada532f5a10ed602db6e545a2cd5d7b76f2d7d342e614698a98f48e5810f45f37aa84893dbf1666ddfae	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579903587000000	1580508387000000	1642975587000000	1674511587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf05c1e1219b5615e1dbd3f9639f08f2b05aad82c8e4e43d2953366452ce8727a5f09c4e55272cabde2ddd51cd73f5b6089868e931f7baf2979788bbc31c1bce5	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1580508087000000	1581112887000000	1643580087000000	1675116087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa90b4a1f98c68ad279bda4e8c0eba67aecc4eb2f603c0d0113d8fe5f5200daa7fcf3945cfe4d1c61a1f7328649236ddd10d0f18e90d8d4d975eb0d23df9b6ca3	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581112587000000	1581717387000000	1644184587000000	1675720587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x32f7f148951539af64223b8b3c372f8b7d14f4c4a85d28e544858b7b524a6a4ede2fd445b6963db0d0498872ca0c856c0ef60e77e58e9538fd8ee498d2a2800c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581717087000000	1582321887000000	1644789087000000	1676325087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x229be5831c5e5decfdc710b081b69c11f5b614f8b7bec7ee634f9fe79e73a4090112d8d23266314fc05530c95e892e119ac03bbb3c6001df37f172a34ddfd21b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582321587000000	1582926387000000	1645393587000000	1676929587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b537f9da816189b5c0bf4031e2bb6c2c4256e0ebbf9eba6e19078080a4946f9d53f2c0b1a8091db407af10eb5b12d946cc5222144a537353c670d27300670ff	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582926087000000	1583530887000000	1645998087000000	1677534087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc1b63d3671500f7ae15e0ab6e6617977f6ba791251f0f23ad5cd7e86c2c228afdb288eac2b017b29b266793cdd08e42152f46d4da01f1612d772980ea7f5e90f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1583530587000000	1584135387000000	1646602587000000	1678138587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x252e25d62a0f04e829dea14c44f4f59b1d1dfb8217c9dc6136261e1bda0fd8091d42c3fa9d15688e03f49ffc8b353bdd52592782f29d6cf72c1d57f2ab515af6	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584135087000000	1584739887000000	1647207087000000	1678743087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0f36baf1da61ca22fb43134b22d277d8fa94b6ad1c671d6aed11a44c775f1a271dcbc8541d9c14cf884be82236afcd62270e5a503c39bf9981eb84c9402760f0	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584739587000000	1585344387000000	1647811587000000	1679347587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfd13f2dedab4a5ac29bbe01261b50d44b0139a88b0ce12a22f7c64f679b4af27d9ef98ef7e38e5574412d2cf56490cf535205b10069579cafd411fd8218c3b82	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585344087000000	1585948887000000	1648416087000000	1679952087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9d780587fe906824a7909dcfcbae52854c6de5842ed2e10d6d2eb34ddbfa1108e3e05c34f9188ddc9c27d60a12caa99e345a87833f9c087a6417d0fc0a691af1	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585948587000000	1586553387000000	1649020587000000	1680556587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe8f70a302ed31fd9f97c7b5e1cddda836e60130287635ff1f3379b91b833cdb2ddaae1fae7d23424219213c41e7ab830272b5e6ba16a03b077d72371427f7a06	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1586553087000000	1587157887000000	1649625087000000	1681161087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b655fb4d1fd71a40905e3f85d87554af93827aa99337a7a3f784c0ec36704f8572c1f3e26ea9b573cf508e93a46efb155f8c21868c16276d3e7ea59e5b151c4	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587157587000000	1587762387000000	1650229587000000	1681765587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe8df145d8cbe7513afa1c00c1f4357d6935ad63eda490eb5e91dbda05ec11ed90a4a9ec58b7ded895397ea72852c47d1c60fe9c4e2b022c781603b0196cfaa63	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587762087000000	1588366887000000	1650834087000000	1682370087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2bb06af49631cf47a3e33846370b88b99635620a574fa1f1dedec0e92e3fb90eb9373f6cecfb6979d8838fd986bce8121002a9da4f0ad63dd46ed56330475c29	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588366587000000	1588971387000000	1651438587000000	1682974587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0b3789b26fd611140a190cd6475a02bce2cad39a41cd7a35549744b2c0788ba3e799df0281017a1dc55c16bff40376af6821f752933e8f29b549c0f3b5aa13ad	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588971087000000	1589575887000000	1652043087000000	1683579087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa96d97cc5bf147d556cb9ce6b45665d8984ea76edbd2501d33a401b782486e443d9b6cc0515e5b1f9ede31270470cf78865bbb0dcfc6a77343b57045f5ac0e10	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1589575587000000	1590180387000000	1652647587000000	1684183587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f08c829b8eb5d771833c9bd48e49e26f3c53407f0579d93c121fd88a3e0f413cabb10d988cc0b6889332cab6147351a813a7898033c06c7ffdb65340a7a5f3f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590180087000000	1590784887000000	1653252087000000	1684788087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8815fd0a010da07bd68e9c65413430e655ce431e60597362eab8755db55a55f32c6c7131cc4edf68f0211f9067fbabbebf78e81ff97f2198b66319e362003a6e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590784587000000	1591389387000000	1653856587000000	1685392587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x69aee3fa989984b1fb3730f5d96e9b41bfda6315b5348b48e4a52cca1f9f5102fa172e2bd8b0f450ec081817565bfdb4d31a2aca1d02a13d8a1148f61105bc1c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591389087000000	1591993887000000	1654461087000000	1685997087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa27a5021bebd77515901c91b37463f3121fed997131d5f676436a63c0e261551bbe05b30569b02f65bf29e5b169209d61b5f5c7c7991dd9042015e6052e87f6c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591993587000000	1592598387000000	1655065587000000	1686601587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x34b44d9b3f6beda702635b981768cf40d3c20ffc792ab17310c3eb9192d73f03db59fb0d9885871ade4591b3bfea2cd42134b1d815e2f35bed08def832fdb873	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1592598087000000	1593202887000000	1655670087000000	1687206087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12386cbdb4212ffb7ca1d6600979dbde04b8f2644c44701bacb6e0ad4b5c0cf6ab9c6b7db126243d206f6cce591e6b0b0972f36ff32435dcde0f56c42f851806	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593202587000000	1593807387000000	1656274587000000	1687810587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc89025d9ff1559ff9098dee440a3df2907d659df421c4945394fe3a67a22581e9d226d86b3e431cde77908fb37a4979b250c2870ac68e87abd7702036b0f2603	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593807087000000	1594411887000000	1656879087000000	1688415087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe7223826042b8bc91f13de9f444c3fa61a25892c7b40cde86a48ed77e49008a8a3405a43fc8cc777c33afa60e04b3109566a4fd65ffddba6197eadecac969e33	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1594411587000000	1595016387000000	1657483587000000	1689019587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0f791883b0b9bee1bddf2eb2f4a4b98695848a454c153d8936371bbf99cd87e5c8c60b138c58d0a596f7e9beb788d23dc20760f260269df9bec5658af7004d25	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595016087000000	1595620887000000	1658088087000000	1689624087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc55ea4742964382b9b60edea53c6b8f6bb80b71c240592956a31f1df9e39b44345b25ac28d901b7696315894a0029d796e02293ec3dc0092cc5ecce52dece531	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595620587000000	1596225387000000	1658692587000000	1690228587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa49e311107ee1178b6f974bc1750981334742983e5e226ab3b81256739f4ed7d1d72a47e187fd4bfce9e33fe32a78990b1bf681261ecd145062d8ffc701d07b3	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596225087000000	1596829887000000	1659297087000000	1690833087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5e59c1a79d19426041171947177521ff1d07795c0f9a0cb4a0973182665705335d60d4967e5e9155d891ec6b04fb3858b7429fe7cf072efac7a4d16b69923f89	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596829587000000	1597434387000000	1659901587000000	1691437587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd2233b30248442c2ddaefc8b0b4237fdddb8d14d9989b69ac454ff80f57ffed749e86faf44d1dcfd8598cbe62453ea789cde6487c7bc634c9de02c11ff2b187	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1597434087000000	1598038887000000	1660506087000000	1692042087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0a9cd00402da595ce95d1ba17157d425d691e2f63132a22fb5d0e7c927f25d4d86360c5f03e3b1660a9e1c490d677e13c54c3471c72df09353731184d4153b0e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598038587000000	1598643387000000	1661110587000000	1692646587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x82933ad2b5dbef6debb55d120e1e1a633d341da4d7efa9e1b522e0b7881b85b4eb79db77838b4872f6fdaca0c3a57eb320b856b01bd1efa88986c6456ba79b7a	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598643087000000	1599247887000000	1661715087000000	1693251087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde246cea3f178b33eee63b45d6eb38ebcd5fafe6456c2f429c755d97c4081cebd0e2f9d993dda73b8efcf8becb8388f349fa8fa2d11bfc94c83ed01bffcd7fa2	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1579903887000000	1642371087000000	1673907087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c8d174fe9a1d2db2df18c53a3c24859913fa490e16b4f606fc8196c9d6c15a49a9b9331c0be950fdf47e2118e4d0017b0f299c5618d7dc9bebfd81fcd411d68	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579903587000000	1580508387000000	1642975587000000	1674511587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb23a523aad5e1a00829b748b78a014d3602ca4b84550155373eec5c25b68b3ca347a061638ad17a90413d8b77a2d481704c3e739de64167b9cd038d8c9bbe9d7	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1580508087000000	1581112887000000	1643580087000000	1675116087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6d912543e66214903fde5357dc3f1d375f0863b5d10214436972cfc6ff3ce6ce0210930500a1c58bad0b0f5d5ccae17aae238a56b1734a80bfa9b972f9cf0bb6	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581112587000000	1581717387000000	1644184587000000	1675720587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x39481f720a191e393cbd4e1fd48622a96724d0ede3fbbeaaf113e8bce483525aff4d45bd5f3c1f84b41e7f449f6b1989acbe86fb166843cd392117de6ff30f97	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581717087000000	1582321887000000	1644789087000000	1676325087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7efd3ff5934edd3c9513b722c1884931272b1249a4d72f60063c7f17b4c94e1b3d2db9aa9dee85792ae189ffe5d65b5bc6b12170efb61bbd6ff595b208f50cb9	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582321587000000	1582926387000000	1645393587000000	1676929587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6b0f8cc0989f4b08d817eb76c301fbd2aeb6d27f9a0e7e41ac22312264cd8597724f61eca6403a402c9ca9b5354426cbcdd42774b223e8ef1600c01226a94304	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582926087000000	1583530887000000	1645998087000000	1677534087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x99598b6a9e774ec075f2ee8246ddc70394a0765f5363e2123f1b75433c2fd955bd45eb39fbfaab27bc952264ad3ac691124fc866172c5f18e30c2952cab8d00e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1583530587000000	1584135387000000	1646602587000000	1678138587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a01773caec4c48e00f142e2eab3f57880b0ba14ca6f8be86ccfb4e10812d67c3f24bffc22dc792ea3c021dd5d94078dca59e77ebb85e0f48b6a9c26680022f8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584135087000000	1584739887000000	1647207087000000	1678743087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb4d76fc1fbbe19f43129add63c0c0308c6d27a1da69d914f109f7208666a47df698f902b5a7fc6fa683c49ef336110dfbf0a7cf23ad869c60de24bc37a9762d8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584739587000000	1585344387000000	1647811587000000	1679347587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7fb4e0253ce91c91c02f60e41b90fbaf74eff6e487121afec51c579c609489a41fe49b84c8a4a895fa8873da4d35516a3bdd83e9da7a81b00a7cfff03d5cbb53	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585344087000000	1585948887000000	1648416087000000	1679952087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0bf55e6c2797b5ecde6948e70d67d32295dd3074bf291dea1ae149e6f10dce7aa0eb66b2a36bec525496157db3cd32751bb53d84261cdcf7db15142de4cebe46	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585948587000000	1586553387000000	1649020587000000	1680556587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa051663185d1bb771214861f3313b6bcacc65cf3ecfa6cdee27c18dd44eddb41e14595ab8393bfd4505ac840277ebedeb8543eb290e54446d7e9ef6a1541f8ec	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1586553087000000	1587157887000000	1649625087000000	1681161087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb0a5ca55977caaa45c6b1cd5862fe58bf110870ef16525733aac4627b6a8d41ad5c9a852ca69ad0ca8af205e422959b2512bb3daff1d9a62d66622263a4daa04	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587157587000000	1587762387000000	1650229587000000	1681765587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdc6eda48efbe59bc21225f76de4e919d21c0e442411d4b37140f54511ee632972c2aba9beb7fa9f1f778fc01ffb78086b2d4414f3e762d824abd209302e67fcb	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587762087000000	1588366887000000	1650834087000000	1682370087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc68e51e0c87270e678cc914660a15b33f348f36dc2feb146da1eae51ae31e7677830f329f08828b242591fef53a07e397fecc9244ba273f24d5a61846d1beb86	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588366587000000	1588971387000000	1651438587000000	1682974587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0f0b422fe22b081e5c1794cd10983dec3eadfcda470946303554de34adb6aa700b15d3fd23d7cd94cdfc60d67c328305a47b530d6079574bc931a1a032d476cd	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588971087000000	1589575887000000	1652043087000000	1683579087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc2c25b47f0615cdbfffbccedd54b6b3e5fca78ccb689c22c1e322520b56e2de8455de22eb4970362a1eda958a11671b0a071b60b3aacd8845202c08eb3c31c02	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1589575587000000	1590180387000000	1652647587000000	1684183587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9f38496b5544e36da83b4c7a0399fc456395998543e6d06cdd3cfb5fac3cb833ebc8b131275604b9a9d0befc03055696be7edbddec1710a0a1d34f631ec4a2a3	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590180087000000	1590784887000000	1653252087000000	1684788087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf0cc01a026b9a18ae26d0d10c2dec3292e50b42dc0bbadee65eeeccf88714cdf695e5710571de38613b432aace140acfaee1fb3f6c9fa3d5104fe0191d130342	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590784587000000	1591389387000000	1653856587000000	1685392587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x444bb714b7b769375a89d73e668abaf07bc70208a299fbd8e25ddf6766f8050d3d3a27ed7b3e5e0bebd492269eb533bb61dc309c045871ffdfa0ba85d229ad89	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591389087000000	1591993887000000	1654461087000000	1685997087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa447ec9ff7ebf11c18c7e8b5e475b37028e8dd5bd36f585c57a5eed735a4c5b8edf15ad4c935caf022bfb2289d5c513a41f6636a5233dcb997abe94d152f02b8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591993587000000	1592598387000000	1655065587000000	1686601587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x349d15ebdd974273eca768d06cee4fe8ab8edbfda0b30bd690a21be7bac41d8a36c63e766ca7eec49355122468cefb7c071cd930fe196d88fd905bb2de9ccbb1	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1592598087000000	1593202887000000	1655670087000000	1687206087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5da35abcd01024638535a9efa5dbba66d15e27729c9097b94676381fff727389591955b73ab3937b7551f0ae3c0009f637e4e1103c524f0c8a6addace63dc197	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593202587000000	1593807387000000	1656274587000000	1687810587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f101dfe4199858fd7edb4fd88be8f9f8c7e18bd2052cef08bda9bf7bedd5e91373ac28779aed69af0f34296716cd900e50e98f4d52755f61ebcd1c235fc8bb5	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593807087000000	1594411887000000	1656879087000000	1688415087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe829f88012398d1e338eaff4d51a8a278165fe4847784dd9ff09559ec8ada52bebb54919f5eb53fd9d0b8cc4f621f3ce1916edfaa062064306da8b2db52d5f4a	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1594411587000000	1595016387000000	1657483587000000	1689019587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24d8e71e6eec86391ff59742e5bcbcc2e5945c86775f611e5d790129a9e16a2f03e485feec71007ed5a67e132c5efae06fe95f8f034c19a2e37418a9193d7e96	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595016087000000	1595620887000000	1658088087000000	1689624087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc07a25204594504e5e4058f7ffb919e0caa898cd5625eac114d83dcc2b2407280ac8d9413bd50dd9d4f4f2d20e9a16ccb13e2294f342f201b387e24b1f3bdcd4	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595620587000000	1596225387000000	1658692587000000	1690228587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9c369ac0427ba0ec32133fb71051c4377e6f74bbc359cd6490b4a1fe10055acf38795468be1de753e2813a7ac7b195bf0eb0962fe93fdeed881e6011afd82d8e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596225087000000	1596829887000000	1659297087000000	1690833087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x019360e98f4f22b1db217b352ff6a7596b45c1ea59a41cdaea19b52a81f0e7acbebae2f9a54affd5b1949c4291e745dc3e07d0e247b8f5d593162ac2729231ee	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596829587000000	1597434387000000	1659901587000000	1691437587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdc65b1aebcd4bbd57256fc4f4859e24d9ec5e570c4cc8c96b85727cc41608984d1a161d4ce30d30f037688a4e35428863777a1d56a6f71a3fe6e0aaa52f32447	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1597434087000000	1598038887000000	1660506087000000	1692042087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x94408b3e7a927eafd925a281423210705c23f3f5600b262b14fcf151df56704d3aa5333b819483a892e4dc58a8b3639d625a4dd1f7c35bccff310eeb2f83cd08	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598038587000000	1598643387000000	1661110587000000	1692646587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x01b169ec003cba71401faa6d1c164b0f30cf0e3db9ddcb3f6f7aad59f0b1a027004943778c3416dfb99a0319396d6c0da2568d40f8d4647bd5ac565436578744	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598643087000000	1599247887000000	1661715087000000	1693251087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe4f111e3909876e4337dc0d1083141ae8e0817937cd476137c1bd405b7ff63b7a1a09fa46ebb1cc051c1b4de6c82e0bdf4375bca038f4aaf3c52f1e81b15e488	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1579903887000000	1642371087000000	1673907087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6fd2db5d490aa6be37fc980d292af272db7576cd04cc1540fcf5561c9a01e3a010ca1bde7ac1c7b4666f54f6038414af9f903e4fa90dbef2dde4a5ff342a4d90	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579903587000000	1580508387000000	1642975587000000	1674511587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4f5c2016be8d885bd19f05bc5274110e4dee06a8a31bf2711cb85faadb32242cb8897aa4824ba92514432f7826a34709c670acdfbb44743e2c98cc5bb87b1eb9	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1580508087000000	1581112887000000	1643580087000000	1675116087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x634f335f995ec038ebf3531d44a758999efe10cb6685b04f06cef5b6eead3d10fcc60e3f6f64b8ca9654b7207631b2b546aef067208f1ce5742f328b84735b83	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581112587000000	1581717387000000	1644184587000000	1675720587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe3e17207147a78a319bb0e78f6d6a8e22e30e4c96a6cd82622667347b1ad1814785de5fafd90e03b3e7674e1ef1b637264c22c42b6b1941e11aec646ef2685de	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581717087000000	1582321887000000	1644789087000000	1676325087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x310eb2f50080b051d70d0809d9b43161d44c623ae7cedc29cd80ea38728ebf8583bc675988b8773d05640ddad613938b9b774060f3d15e8dc7afe61b87b64be4	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582321587000000	1582926387000000	1645393587000000	1676929587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb1f011d6bf23eafd9d0d9fcd168d4ff8db5b5bd36fa6c47a0257a2c49d215e28473a11ce406afae48f8baf9a0db787a603e21930368ccde4bea8eb86b81e941a	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582926087000000	1583530887000000	1645998087000000	1677534087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5b4781e90b686635da1e7aafc151268c0a9c511fe945bb7851b5cf29aab253206bb47af5abba8a66b07a85469348da632215773657aa8e64ca7ff68ef0d1de5e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1583530587000000	1584135387000000	1646602587000000	1678138587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe8964f9f3c963dd03f66cadeec2680a14e44bdd39e13086cbf7f874a7da735dd5db8b684e2b8d2df313151ed07a354814662b260eff83cbb83b9638383dfbb50	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584135087000000	1584739887000000	1647207087000000	1678743087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8cf76b444ba5a441796a95b43ec1b1b61b4f397705d9e043b116c85d8f104c6860b021465918f42a6102c49f468490b0e70bfcb5674cb474d96f970940859b9b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584739587000000	1585344387000000	1647811587000000	1679347587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc0888cf4fc66793521fa16894bdee8e920942d18a5812342a17331c58d797ef4cbca9540d2fdf927f77b75b266639381a3852eeb52713a367c2a8a583d5f1684	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585344087000000	1585948887000000	1648416087000000	1679952087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5cd75f14b6cd1b7eb41d573a1a0c8ca50579693b8cd5205cc59dc293835e34c0e0422305ebe4a02065713d938de8bf0ee8d13d9b91557c8e72ce445e1203347b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585948587000000	1586553387000000	1649020587000000	1680556587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5f1350d32de1cdfbbb714f6030d77c00acd56bf55891862648cd7c089c80c4c6c7f9decc11e13d5ba45f207fe181a85909546812fe424ef876ad96f8dbd60884	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1586553087000000	1587157887000000	1649625087000000	1681161087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x99c744d0e0c2f26ccbe1f0d1ab719b7b4e63b4ff1526ee9d8e58dc92f74abd92dc36a0a2a838186f6023f60ac5c6d177934d5eeff7ed6d22a85c8d0ea3d05387	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587157587000000	1587762387000000	1650229587000000	1681765587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x83950bbff27701a1f3ac3b3f7e64e667eb0f417ff6271d8696ca8d4e293328d8085890ebfe3842303fdcdb311028ad659e28fe870d3dd28d6482d7d291517f90	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587762087000000	1588366887000000	1650834087000000	1682370087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x27deebde6dbe3f749a4ac6d071003328b7f3850317d4c3b603ae8e6154c2f9bb12efa52c7015a5290772f5b3bdb201273a62fe6e531f9b269107a9da8d6f7624	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588366587000000	1588971387000000	1651438587000000	1682974587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x026adefe6700d8a4213c79f238ae593f395e7e31deed2ee6d9bc33c79a2e08d838acc302098797f1c04d8e84722c84c30671de792bdc5eec9e26a9cedad8b9db	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588971087000000	1589575887000000	1652043087000000	1683579087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9de2ced0f8a7fd53cd0d09511f3d2505fcacae808773ab3612513b37ec30a4cb09df04c70539107f4aeff6f5e39de83292eb42425117bf7c8e4f3aca4d371508	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1589575587000000	1590180387000000	1652647587000000	1684183587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x541ae97a504193455cfbfa35a3d97014bee66dc266af9a763a3d7cad2bb4ef478ab87ce3664c6242bd6a728af48fcee27f18f1ef97e5643b5a2c2802a2f8cd6d	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590180087000000	1590784887000000	1653252087000000	1684788087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x315ef9c0f8f479bb80b3e62dcf59c5cbb7c1b1b0f057087f013e990c2cf18e64667153ab5fc5873ca8e2b2d2e535c72c1e7433499ea76fc9cef551ff2f9e0261	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590784587000000	1591389387000000	1653856587000000	1685392587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4ea8837e712d398206bdfc6838a514cf118ea0e0e80417f366d98ed3e9d6febdf5f474aa3297ca3c6c9373380904e4770d302a6ffe16d5a7d1754ba30506e567	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591389087000000	1591993887000000	1654461087000000	1685997087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4be9fb3c3850a714cdf98d46a7746946559dde4f82d950a3ab8a0cc41b1d40db34a0112bf1d4c2cbf42b174c2bfb76c065de1ad12a2b8a8eb6488c9959e03c4b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591993587000000	1592598387000000	1655065587000000	1686601587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa3a8a07f694e92654d06c3a58fa891c1a2c32546666f8d6e9e07b32a9867df26e206d390a0d49ab0fa3b3829c2b4971ed36ea70a5bdcb8d2cd460fe3146e72bf	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1592598087000000	1593202887000000	1655670087000000	1687206087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe027840fe8863cc4a76bb6005ddb57279d3f977bfecc3aebd239e891d54a1ad4bfe444c2f1a5717f5f9d09c106ff7d1155758c30be22a3796ea0b82d77948857	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593202587000000	1593807387000000	1656274587000000	1687810587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8b30a70affae6629cfdbbb008b7e26d3f73a44c593066828be09ad9b16c0f1546e3ce644dcf066728786dae96fdb7c1bc4aaa7fc75ddd2d518448d2c7c8c2519	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593807087000000	1594411887000000	1656879087000000	1688415087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c3133e70f8d71f64c4cd1455c7828ee92fc2cf55884c96bc7a758693dab64250aaaf3e819c88bb34010c236f58c5f548fd894abe8fee15282316ff16ac4a991	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1594411587000000	1595016387000000	1657483587000000	1689019587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb20fb771d0a82827b4a7a146d0a326b8c97c520bd66c94cf634ad13a5c8a3c24c53d66ec13f40885c15803d23ba864dace936de96c1011f8f7006de29686efd7	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595016087000000	1595620887000000	1658088087000000	1689624087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xde1bd5fdebba4ded55acfc559cefa4170c3742deef29ae3aaa734db7557dc2974e3b1a6873f30999da21688e08d1a0df0e59df893470353f8b1e282fcd98b5c8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595620587000000	1596225387000000	1658692587000000	1690228587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x778674d5a1cc39829222cef0a099de5c452a6d61d00f0d95817412e8aed0a2930cc4c86d96416103e705aac09c202531012abe57538b629bb8d39a9b244fee1a	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596225087000000	1596829887000000	1659297087000000	1690833087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x13d65fd1a5c5e2bbb0a090bdac20f49f512945fa67c8e640aeb3bede976f750d33fa436dc3f6c97de579ff6c6a2cf4e3f56e0d5d46541b7140ede7a067773182	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596829587000000	1597434387000000	1659901587000000	1691437587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x239188b9686680351d2333a2d7394d4fb49e6b9f77307d0554bdb4eccb0b3b60acce9afd5df13b6b24d739bb9d9139f637323ce7dbd64f19217c4d7cf5d309a5	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1597434087000000	1598038887000000	1660506087000000	1692042087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x94d7256081fef0ef822a368b58d3cfbdb599ea3175566c57828a0528e06a4db8165e9c549896457ebf1b65736f6cc99f0d8344d1217fd34b8d11194fc2629a86	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598038587000000	1598643387000000	1661110587000000	1692646587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1cdd9536ecbc75b3fec45c16bbb55668a436aeb633f53397d8f4760dd228ba07ab103b7f0f25c805b1f89083060202cc6b30f9a075b4aa370cbeb59346249468	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598643087000000	1599247887000000	1661715087000000	1693251087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1579903887000000	1642371087000000	1673907087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd56ec53c635f96594b84f7afb4e9837abae77bd044e775c469af98ed8378698e6d79b81a36f3c304216befa523d4246e1fc50df68057d02bca70005cf5e0bf08	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579903587000000	1580508387000000	1642975587000000	1674511587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x15cfb80ea679904a3784ca94ee4f5f7c71de596df8f8bfc4f2d9fd2430f7395a9b53d12e5c2b842cd51ff0b4cb522714dd0c532d0898d37bdafb6cbc2d4e972d	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1580508087000000	1581112887000000	1643580087000000	1675116087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a3524c01581f1c57a80e9d1ef10315443fe0c9165ca332f474ba26032a9cd75d879b29830e252ca8ac0e00bbb30b1708e9f36b8707a1baba4ad39e715bc25ba	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581112587000000	1581717387000000	1644184587000000	1675720587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb528f868e314d48da7281f9b7e775f5f73ed17592a5fc567fdf1ef3ae6a5e07e5279b142d683af41ec5f81a80c252bff072866a5cd97532fab157b3c416ec6ea	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581717087000000	1582321887000000	1644789087000000	1676325087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xff2db0de7abd71a05c55f6eec18cf8b0baaf221bf962590c5df405d3c1e1f2d9328f973e2d02d6e5f11bfb7ca49774b0e3ffb3b57c3bbebf9517dcef44d51e56	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582321587000000	1582926387000000	1645393587000000	1676929587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa54716afab4ee77871b7fcf0429a17b1e50e3206c448a62063454f4bfa9c167fb962eac481059195f9a8f96c381971a0d5544d200a298099300fc1bc13932689	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582926087000000	1583530887000000	1645998087000000	1677534087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x99417a9baf5c272ef39ce71b32c90fbcabe18f6217674693888c92993f638032034d2d8224eb77667584e9fdde078ab215e6f67cb04531ea560b399c88d8a860	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1583530587000000	1584135387000000	1646602587000000	1678138587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x65c1f8977d2bb4217b5b7c42fd9e2bcfac6c861255083ae93c1a1b1bdfd01fecfc07bc1f6fb0137c9ad919d47d93efede12b0fa72076941c3b553e30a70dc1ac	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584135087000000	1584739887000000	1647207087000000	1678743087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8f0a6947f56c281381301f3bd125e8a5948a89252b960ea6fcce4ea51b1ed36911c7edb13c78712df7b1b95ec2714ff15cce6f987139b89d6b760fb7b8f5b77	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584739587000000	1585344387000000	1647811587000000	1679347587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x820ebc442aef5262f3445ea53b1214a964f8fa60bcb94f36ddea67be0e06a1d367d717f456e67a40e287f97b9efa8a9d07370b0da767c7d31a330d90183c0d55	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585344087000000	1585948887000000	1648416087000000	1679952087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x99d83a56a665dd52181adb62e47975e0ac4856b27497217722ab2d9849cbfb2e36cdc1f75d0cdb761942dd0b82e2da80f83da43d4cc6b8492603dfbf94d92240	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585948587000000	1586553387000000	1649020587000000	1680556587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x91fbaf71f94fa33ced05d4e126de3d4c59fb3ef234e892c1d1df039e453a97a72a937a2e857ad2f72e78e8102576966c19a66dd68fcdb0b77fe40eb576507367	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1586553087000000	1587157887000000	1649625087000000	1681161087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b08b79e905fcde359983ca0f5ba2f52edf8238547c21c75a6cf35c67c723a1ae94dfcbabab5cda412fd3ee23956ad97f77e88004e57e045dffff99f2f594340	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587157587000000	1587762387000000	1650229587000000	1681765587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd6fe7185d9c72a3556153b10c26d427fc18b41ee5746b601b2f3c35a7f27440d6c8d0707f3a187e22ffd867e33353a7675b9a2cac24d16ddc9ee82e032963a77	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587762087000000	1588366887000000	1650834087000000	1682370087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x358717578a762160edb7f1e61ccf5872b753b4f7643c720ef0fa668ba647f4616f159aad6fc362c3b1571bca1c75379d39455a4e0807eb6e99f996479e10afe4	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588366587000000	1588971387000000	1651438587000000	1682974587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x550f44eca47fffaa91503e7a767898b2305ed322a12414a07b2f676b70bdbf2569aa4b130d9b4de2a7fb7f969f1661d1d36068885f66f1595a1332cfb34364a8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588971087000000	1589575887000000	1652043087000000	1683579087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3cd4e1edb5c48388bdd515a70ea62802fe693a407497ca5123d688b313d12ed79c6e6d29875ad04c653c05a1df282724136e644083fba06aedbba14f0f20a0c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1589575587000000	1590180387000000	1652647587000000	1684183587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ad1fe6a25ee836b609ec22d0f451b8e588c9022256b863f51ad68dde95418792fab05dbb726a1638afb2de1c6ad376f8e2ba6f75592e241208758190c3f638c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590180087000000	1590784887000000	1653252087000000	1684788087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa207e9e7e3de8ac09dd00a42c8f07c42ed31838e1e3a6d5943ede5ffd406ec9d3bd20621cde99ec813962268e7bf92ffa1c6c57965338ba47f651090e555a75c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590784587000000	1591389387000000	1653856587000000	1685392587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e603ff2fc01aaa8634cea13b9df4fba314027a5e5b894f08a4b617b9295874f6bb99a010dd1639fc911eb95534cedfbcb9193e411a3421bd764c4f320f6b55d	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591389087000000	1591993887000000	1654461087000000	1685997087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x710ea2046f596a7f538647f6a692d5cd62d6518f657ebc8131042e8671b4af07055a28e9402c58ad4a2149f1818a2d17c08dfbe3830c681025b3c2effd33b845	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591993587000000	1592598387000000	1655065587000000	1686601587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0492dea10c2c9e5930362395ec3d9bcf1274c9f6fce1deca1643e0b327a5a2e7b6c82dfb9e3096170e76e829f811fce2853db0a644b65e449743db5fbd36a9f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1592598087000000	1593202887000000	1655670087000000	1687206087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e0ad409b476d30cbbd9d59ce80c55fe5a98b6385934f665917ef4922324c702272b825fc5e7ae2e3723c72a1154605bfaf62d2af3bd58da873f60b5352f871b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593202587000000	1593807387000000	1656274587000000	1687810587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f9c2b3d49546c8fcb0bc3d8e968c9d35cd646fa0e4d222ad6a41685f34516b11d21d04dec0e29406bf3ba02b4be5ae1837fdee203337063717f67eb0bf026f0	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593807087000000	1594411887000000	1656879087000000	1688415087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9800d988be91aa9b13836d0edba0535be8c8d0c6e5ce6ec261d6c80d7120d32d4b8b09f9ef79ad617dfff6575bc3f5e81d47f0268e0c381f8daf11e79e2563a2	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1594411587000000	1595016387000000	1657483587000000	1689019587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x295db680a26638022b9570c17042dc3f560e9ad5052eb4aa2d1d3be4135e4bc469c978481bd03fa4f20afb5fe747755dd36a60c2112cdfe60a5689ad0bcfcbe3	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595016087000000	1595620887000000	1658088087000000	1689624087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9712f3910cf946d819ea46b4a1968cda3c41cf23f4ff1e57f77d95c5f8ce8bf5c4c26b4eaad0e5a017a3db94aea625de1e24af235e5aa6866b777080c3504958	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595620587000000	1596225387000000	1658692587000000	1690228587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x03e52d6af9a26e358db953ac26c0289f0244a916fe69ca1305101d3acb5155119c9905a654def819de7b34121880949985277d328937b180390794263aaa5b75	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596225087000000	1596829887000000	1659297087000000	1690833087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd4c49e1837c8d273c772a9cf7bb117b661b29b4fff117f905adc2180fc544a5c5728ad77ca5e1ac306ad8af57cc469baff72814c11519425dfb18b016110e503	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596829587000000	1597434387000000	1659901587000000	1691437587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ee9df42b8a90531296066491e5e6109edd0fb03ba333438c5828fce09822f6d5c4a05296b595de8bc526d6e269f6a6168d0e0972c990ad921c31daf97aba6e2	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1597434087000000	1598038887000000	1660506087000000	1692042087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x099d0e2fac12bf4138be48a5e3f072af8c1b2a4e36e74319bb484c271831473162ac5b193049739c30c6acb4f0f5658c15636e3e3270580b6de24183eb30d539	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598038587000000	1598643387000000	1661110587000000	1692646587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8dbe5b84e51e2d6a5eb7e114ea1abc54be6992ef37b345fc59e537b707d459dd128cee7b31c99ff8733c18ace963915c0d97183e0490f80a335400b81deaf9c8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598643087000000	1599247887000000	1661715087000000	1693251087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x28aebf96d858e7201c6652abe628f3d3afe4cf4e93c04e84af2b2cb077fa72c0b37fdf7c0e970ccac4ef3c6c345962a26a0a219987102c39aa3e9b1e19567332	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1579903887000000	1642371087000000	1673907087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xba90bccd3666a3392a2587e6e9cec8213d1a96efdd9cfd5433caaa7a3ea5e04de1db1606e62fdb0e9531d53890b8134066908088bdd2bef463965c7e2d802082	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579903587000000	1580508387000000	1642975587000000	1674511587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf82ae30b6f937f6901e4cd22b068704259cf1c2473efbe7052527d7ed5b6a510417185691567fd9b087ad2f548db957f6ef4add8c217ce5abe98e4d5494d68b0	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1580508087000000	1581112887000000	1643580087000000	1675116087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x26fda93c59e71ce293abb3a37d92d6c61d49d4232fbbb9fbfb41a33a8a90ee6087a4208b0e2883faca38523a7285fa7fd85cdfd978dda4fe2c36dcb3bb6cb36c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581112587000000	1581717387000000	1644184587000000	1675720587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbede0bfbc9357155923352cd433f6a134979b17b08fd77bc1b680b037531d97c95176721fc2be1e65e881e03150abd66344cc0644e5cd5fa993d6340ff2bb37c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1581717087000000	1582321887000000	1644789087000000	1676325087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7a02357f077d439543316f8f829c5d9510377c9b3861e80c12c7755bfd777309260e6cadc3215682c65243e9f60f752f5ed5ed91937262a8d2a153f5418496d7	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582321587000000	1582926387000000	1645393587000000	1676929587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf7df77ba96dec671e13ab2aa19a634f058047535c149874e8eaf46298a970d27682a1657634b3515be708875ba75e328de603a93533f4ac49f27ae6a75f0d69c	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1582926087000000	1583530887000000	1645998087000000	1677534087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5d733143b3d38a057b79f137696cb455939e7441dd0fc391d74a3f2d4754b0324b21544c83221356dd140a2e2e7f0dc15c697029789266bdde04b7b3ed521f19	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1583530587000000	1584135387000000	1646602587000000	1678138587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x41846f44bc25038c9382d0e1848f4211fec6212e15aa4716765d96e0be300fe189445e78f5d70bdffb12934746936533d8544b701d92eadb09044282ec1391b8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584135087000000	1584739887000000	1647207087000000	1678743087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe95b4ef646f74fdf84681bb7f13895f8c2b823d3eb7acfa54ab6c19cb5e43be1a272c8079477e90f29fbec67f5186d5cd6dd615641c988a564f1f4dc098e2d56	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1584739587000000	1585344387000000	1647811587000000	1679347587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x08ac4fd5a83bedc34d1cc4136adb3dbbd1ccaa905415104ac59675ba4e87c28972a96e91a1d431c40225e0a5d14d40c9d96618fdeec75907637e542cfdaa5b3b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585344087000000	1585948887000000	1648416087000000	1679952087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa4ce8a476d2983d4aff032aec5a4f95dfa854c8703b68cf776d5c5659b07ac28c1eb45dd6148eb5a315cf31ae8e052f4f49b2032aedef3ce7b8126f003abe955	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1585948587000000	1586553387000000	1649020587000000	1680556587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe131e80e50919f1bd6c2a4e73fa74e40e44c0f2ed5967fc1e845060d837f7a6f811a254f761aabd25b4b6be9efd7ff80096686e0d5f1155a1675d2e3a1ec2050	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1586553087000000	1587157887000000	1649625087000000	1681161087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaee05c85ecb556bcf7a9dc403584e999a56b6b0c89e16e9fdabe660cb1531f062bcf6e9fc40a74549091f7893281b4bfcefa93dafe024ae1f42b75059f134793	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587157587000000	1587762387000000	1650229587000000	1681765587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9239d862f6022bcbed73878015c15d7ad39e49856e87de54f75e41080ab7b82181251e596d40184b5d3d5b9269adce1e4bd7259cf19e8d6db376c3b7f49e79fd	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1587762087000000	1588366887000000	1650834087000000	1682370087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdca5ba805b13ad72cab7d19e4b9a2c5ad855bb6dc99aa173251a0acd73ea02138892ce48ebc178ce1e4af8952ac773a950f13133a54e5a8849080525ecb5af4f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588366587000000	1588971387000000	1651438587000000	1682974587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2257c9ceede92f8771c303848793f8e2dedbddaff1545f08f965da68af601b975cd09cd5cb572c593b63677551bd276b700db057dbdfaa8ca4d07e15ada602cb	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1588971087000000	1589575887000000	1652043087000000	1683579087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcf8267bf8a22d063e6b367975ba68234ecb2824533298410551df872d579b8b449b394a937738464dc82ab7e0383c5e2799d723661454e148b8607b300622410	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1589575587000000	1590180387000000	1652647587000000	1684183587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa20c8b88032770934514dcd1a9fb1cfa4e6d5c827757cd9c02cd2443c877f1ed83758e4b135b15dcdc44d628a35a74ce71e732a076bd23a7fc6df9c16a03d882	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590180087000000	1590784887000000	1653252087000000	1684788087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x597bd3715e707193303181d47181b1f0a31e77abf72e1be551e015f5db5fb7c1160aaa0aad076b04bc9ff0ddd5e7896240046f389f433799b1c76ff57fe9529e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1590784587000000	1591389387000000	1653856587000000	1685392587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdd3892515306761f9cde53c55df216edb3aaf1553cc785550332dcf7dcf1292554bd23b5f31e1e46d1a29976230f8cf70eb8395930faf4e80d0a701752965bb5	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591389087000000	1591993887000000	1654461087000000	1685997087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4b0c4ace8d19e1b9a9ddf826a6b05f7364a73d8edf027dbebb4adfd1e647e5f42f02935bbae0f210a7e670d11f8bc309d0d6b4d4417faadb77b4ca5b6ebd1a87	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1591993587000000	1592598387000000	1655065587000000	1686601587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x47c0e027513a56a371358c89974850c984d7fac6b03459993821961f9c29814b766d50252d600a74a2c0bb536eac124983b2f98bb7469fc4d0cb1824669ac891	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1592598087000000	1593202887000000	1655670087000000	1687206087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x151b2bebc893cbfb4b7728f99bcde364f81078036d5385c33f5d899db037c7f5cdd9437c071b04683b1a8d46c952b9d05c5d23afc15676283a445993a9b4d4c8	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593202587000000	1593807387000000	1656274587000000	1687810587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcb041f9a19a4320a14d5abdf0e104c5543a6355f7dbe5586abbb4d27172b444114fc123f319e04c52b5e6723845f3e02b53ba86e43a103a76a997cf9916cefe1	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1593807087000000	1594411887000000	1656879087000000	1688415087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd6c934cedfec7130ca8cd359144337d379db7c96db308a61e0b038b70832ed2909842d9845a52174b53a7e55b79765725d3afe7ddb5298e469c65622eafeb1b5	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1594411587000000	1595016387000000	1657483587000000	1689019587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6abb466a7ed275d153e18a8a1181cca96492dc8bc1402a3264ebdfb2ba5ffd2594227d87014cc22c9ebaf9aaf0bc842cc38dbdfbb2f2f9ba5b76a127fcc8831e	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595016087000000	1595620887000000	1658088087000000	1689624087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0fc661e90669d6a41de4c61ec7c9e77d2c8ed75132534c174dc170d4d7de81307da688a105bf60e674028ea95dc385a9266c543bde49baa61e3f1a691310c953	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1595620587000000	1596225387000000	1658692587000000	1690228587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5b77ff43fcdf519d065b0b265839c065c620dfd3a79e105088eb98c4a780769def91afc7906918d23af15da53de5414613e20a9df1a56767c2ebbe87cc8f6b3b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596225087000000	1596829887000000	1659297087000000	1690833087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x92958d107a3dcd1508fcd6c2d15737f38c1f3a714edacaf79ff5105ab454fae4c1fc9c89bb63da65140c132ebfcc4744e841ab35288a72f505febabf53489a5f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1596829587000000	1597434387000000	1659901587000000	1691437587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa225c3ca97cc64af232a39473efac762334bf29f25d824f70ce61423df4ed86ee35d63a85168dfc8ea8427100b977f950ac4723f0a884978bd906ca9f3a7f581	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1597434087000000	1598038887000000	1660506087000000	1692042087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x68721c278558c16275004ef34c9c990e99c5efeea9b0988d425641ff6276c1897395484d552f1304c13c6f86a66591df72c8dba1e9cece39d6473bbccd96aa9b	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598038587000000	1598643387000000	1661110587000000	1692646587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x128a1a2438fff20e6ba0f54353034d2ed431008acd2b5da9ee235404ead77d8433222897f47b39e52a38bb593b68a82b0e06a6c7d0d1164effe6fa171412522f	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1598643087000000	1599247887000000	1661715087000000	1693251087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1579299087000000	1581718287000000	1642371087000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x68eb87e2d9be6eadf9cf2741e4bba16e60c978c10e8c63eada62de023fb2eae9471385869f799a514b72bdd3913e7004d13e83095e9ec136d7e05422930f7009
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-01-17 23:11:40.449749+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2020-01-17 23:11:40.525865+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-01-17 23:11:40.591496+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-01-17 23:11:40.660547+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-01-17 23:11:40.725957+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-01-17 23:11:40.790989+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-01-17 23:11:40.856046+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-01-17 23:11:40.919974+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-01-17 23:11:41.333658+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-01-17 23:11:41.757103+01
11	pbkdf2_sha256$180000$ur5QJDFc2g5e$CYqfPz9zwFaPlUesJ/BesA+IVgULxidNLR/2N+bcobM=	\N	f	testuser-N5IcqiBv				f	t	2020-01-17 23:11:43.379535+01
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
\\x13f300832405dd07f6e90cfc9874081d4ccac4fe07eb1b06ac613de1ccc3a6a9a0cb1ad7464d12fd8d69b7731d163423110f9f61901bfb60779769063c0060c4	\\x00800003fc6f2a89eb3a3246fc57276e3a18f815c6acfefae8460c0e17e3ef20eb804ab356017eac6fa7aa9fcc742386c856da8b470a7d69287766d5b6e5689b86005ba8b17da17548e52ebc44e4fad07b9c454eff475ab6e756cc437559f55c0f26a5df01dcb3105f7d272e7ff02586fe2f60465d5028e7f956823dadc659940c635cc7010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x7b35686814d63aaeb7d6b0a3e4a0596a92411b4bf9e66ce2013800354be5c7566291b4c358673bbfaf26d4cb7bfa16f1478a02bb1702506ca9be33a4741b6a0c	1579903587000000	1580508387000000	1642975587000000	1674511587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x295e467a2b0ecf360eddda0ebcf9da228097b67e2ee62cee1f0afd217895beb4b0b23fec2f9d7424958ffebe23d766a064f0df87916f01faec8929d51ce4bd46	\\x00800003b90885e786ccda0ee822bc5293fac3d91d356f8ce01d4035a46874248363b7340780548e325b886dec7a64df9b32dada517811bed591c0c956308fa8bba19b459f603b490b129c6b95f29ffdb63d95fbf8e9bfbbcb55a00726ab659b449c574b8340af0de6586ab1936a6d718e4d6ba601218d19f2bba263094051dc96367627010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x5f541405b3acdda09cd7cb214482966ac196a644ecb58f38c00d9abbbda091a09ae9d90e22a4031e2982cc925f44cca6981384d47537257a3d18a0d753794a0e	1579299087000000	1579903887000000	1642371087000000	1673907087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x06ef4fb40d676d73dfa41fdd7f7e73a6feafc3f5e6030f74443a93a88329e2d90eab82aace5ab3816ff451d81d797f6ae49155a5457a42384ae95e6794f34cf3	\\x00800003d85b8cf0f56ee12155fd4a2b44e77e60f5e4053b4ee9211ec1b601fb99f9b736eb1569bf8d9ce1c5d905ffb606f56855a89146cb7500da45b5edf2fbf3321abb7de25de459d2418d04b7257a3a356503452b682d65aec7551a32b90d3b8ddab1a3e3ee7c0ba02ab2f14048206b5552ecdfb87c255293d4f1df1b3a416a43fc07010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x531abf2cd11685ea43a4fce8b9117654a492fa821928111fde7c738e0cc2a0d6737be3330be1068a01ce61e21695f5361194cefde9ce64fcf81adc4e85c0ab0c	1580508087000000	1581112887000000	1643580087000000	1675116087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x050e2089e522de99e2c985d886d93ff1577cbe1497f6b6f8f4823820646af1dc79da879f5c6de370c98128db2f3f295fb967fe9c907fe176195415754761a0e5	\\x00800003d77e7b47136149be760337da6c3eeb66b93e5ff1063dc233e3add5693cd8dde4e3721aa6a32656fd2f1894fb30526e76071ea7c94df9c9ac55f95a7c775060021004829e422b17d06303571800db3b608e7f9b42a6f1722997cefeae44109ab32ffc2ff70ffcc0cfae1841c42537d73a4d18cc6cbee3dfb2a4e8dcefd71da44f010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xfe14cc5daaa93d2af449c35b7518b2f01e3e2b1d9eb69c2070562f2a52583a63de7293f429297a4b6d2a4e10936713dd54ba960fbf062c0e160ff9f621931203	1581112587000000	1581717387000000	1644184587000000	1675720587000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c9791e05c2e87a73b438daa2d1d231bd14f5c9e614479ece5075075b20cc9279e0d8be5864544504193c055b62e3427f057355b1cd73cb1976c8c8ab407a16e	\\x00800003cdcd7de43646a3ac15c550200246efd67b06a27bfcddb9bc2b3873bc535df063af1b201fac1575c0b9821b6854a1494eabc39be09c73a3b85136edf3f49585baecb52d042bd283998ccbe418cf46649247eaf74a224c42ea50362ecce09dfcfb3f20e88cbd6eeb9143911886bbfbbfa67172e20236fa2f69e39c78c2262b5eed010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xa81a7ae97bb24c0b16a8d16c541485abef736ce68e40a24470e828be5809a3081b15ca4e9f7a9fda98235f35dd096ae5bf9d77473d492767db697ddd3d16af01	1581717087000000	1582321887000000	1644789087000000	1676325087000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0007045d7a0a8ffc5840f5eac7f7f1132613e10c34db47f4d352ec28e309c9f586bee8d594f81e5dff4f858e98347c89320870426e438e5b91247b00b9bdd0f8	\\x00800003b1c7598e4464d13a9bbc596158475d3daff5616299393e0e3e78f6e0b9538699e79ae7c85b613bd81f1fddf25c9e7337e5b1c1fb21342efe59e1f6ff860323b479e618bbfe707a1405c11505b7704cb78e3d6b6a40b2d13634ea90c42e49dab70f9a94275e26c1c9f0182b0a9b77de922ab1a405f7a9910f0b0dbeec41978799010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x7d47b79bb9b9cb402ceb8af4bb06fc7f1ac49d3cb93f5a8b0fc0cb50ede507e9e6d22021148e225013da6e8c947be7b46b326ca9f4738880c2692e7189bb2402	1579903587000000	1580508387000000	1642975587000000	1674511587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5acc3bf567651f044f7e2a463a1eca4425efbbee2ce390ea165fa4d6f400a787abbf95ae340d939295a804c4242eb7ca29e270c06cc7086ba3f672d9e2a3e518	\\x00800003c24423c045babac8546d301119184df754a93694a095dbe7de9c58bc29711650b012bb7dbd32d05bff1dcffc890e898b467949ee5a28bb6b9b0dfae1d5242d168d0ef229fe4a740bf19e1398d06faf93ab9a353e48bf5705ae2584e74e9ac57271210638d404064e3fa26e91d40d44a0f82fb9d9c4d894e22604530c5d943d85010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x7f76d75a0a07fca5c982b24b1593adfbffe744bf7082f5e0a49a1c7b18dd81c42a823f539a35b2cf08f8fc394bf99b162abd66ec08009631bf34c03dc37cac01	1579299087000000	1579903887000000	1642371087000000	1673907087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x52a4e40578581ab42e2b6476b5737c05542f98037a7fd6aa5f64e26f8d1cb0187bd2fcb36557b4b2fc5ea8e336ce0ce2b70c6d5bb866d0700a99767390391084	\\x00800003add8a9b7da2b7c5733b127665daccc7518cddc80578895aad1f718cd4c459c09d5f473b2a26198df21b1134206472a23f6f8c2432b034a504fc048402ab85b23667e889c9bd090a875e85f8145224950720add3db1a7417cdd18cdd490af9cc414e246a08ebbca36510ad4485377df319bfe348c50f6e374a8dd20c4ad77a5bd010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xbcb19252308f3ba0ededcffb7324e6b1b35c442697d14c8f08ab441abb3a74685fafc94277b645d557280fc9429b1d44ed1b814d99586c39a3e2c2d3bf0b2b06	1580508087000000	1581112887000000	1643580087000000	1675116087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x85cc69aa202f5f03689399f75c3191774c889f0cda78c7b5490382a64dbc913227e0da469ac97160200768a69803e8f2102a689c1e63569a1248aa359a04e19e	\\x00800003ca802c75290fc65ef0730d87f679002ce2e8a71cfe16f079e9d4e3df7078841ed3a672d960f05d5505d4e42f95beec824a9b2bcf543311f9e69a7923817bce46b333bf92a740aa3405fde6036c3b38ae32717e9ea0e1277fcf65ba47d8ade5e38fec85a2b981577d7a470a1e3ff9ac2f9c489e28c3ba3697071737f2f55513fb010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xa7b9047a2b1db357e59e813bbf0a91a4ff52da94354454b94443aef27c970be070b30711f601397c0cfc1fcd5e4a8cec30799e9b8f3ee6234b3b35b0d8281005	1581112587000000	1581717387000000	1644184587000000	1675720587000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x15c862f5eadec89b73d671c1b86ef88369fa8a1d92adcca567f8ccbbbc4c8b35a56dd950c163109e068aab1ee3d7cd44061492026e81185fde3debd197375952	\\x00800003d6c384ebe77f84381be9bf24eb5b71b41422fe9e2c3734e34a7e1c53e3634b1532274dbc97452605047748928957c34a02aec002a3be909e4c93eae451fdd578f780d0809fb8a69e7982a49f66d074378cb0d543f144f9a71d6b734fc9c17967c17aa3b6e5b188bd588c67cf0b42b68dbb10c2835e38f9e29dfde66893b16adf010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xb7d3102f1756a49281f87c0b7cc103ec19a7fc038b20d4d49cd722fae6ef42845bc3d64f436887f660d10ec1c1d337f27b972d3bde6bf77f593c07a53518590c	1581717087000000	1582321887000000	1644789087000000	1676325087000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c8d174fe9a1d2db2df18c53a3c24859913fa490e16b4f606fc8196c9d6c15a49a9b9331c0be950fdf47e2118e4d0017b0f299c5618d7dc9bebfd81fcd411d68	\\x00800003f24e7cdbd255fd96088257ceb7262f64f7b138eff1be5cabfe3db46457cd3ecd39ec5231a527aa8d13a844f9768db5af5aeec1418f863d50e7383be1ba5aad1cdc674d2334caeb9dd28ccc5ef64ac825f2aa22231bba30d45f0bd0dc0e11a9a1584d1f071a9877472b4da1bfe818ff4b3c463401a1042c39fe46fb53664247b3010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xa0b364bd030f99a0f23eab003218d9038d7dc6ccc659322ee82c49001d9f19a6be3082923e39dbe821c2163ae8828d17795c82754113180fb629fc0ef65f3e0e	1579903587000000	1580508387000000	1642975587000000	1674511587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde246cea3f178b33eee63b45d6eb38ebcd5fafe6456c2f429c755d97c4081cebd0e2f9d993dda73b8efcf8becb8388f349fa8fa2d11bfc94c83ed01bffcd7fa2	\\x00800003df00b23879125efcf880dfab685f545620e12f086d65ff88a5ac45ecb0910de4bc39b0ad48895a18bac245341c14764c575550eda2f71ed9964f9e68c29f8ed21ed154bad6b3c21022f3ac38711cf3ebb2cacbefbacbff5516189adf52e857af7fd1dac43f000b2892986f919a31a8236d26e80f46abadeb2726da91d2b0adfd010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xbc9896e80b6c0f0a6afb7492b2c4a273d23160c328479ad32de107df5a97cc94b2a9cb0467c2e098a55168b149132cd94ed9c6c63dc4acea89a91e070097050e	1579299087000000	1579903887000000	1642371087000000	1673907087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb23a523aad5e1a00829b748b78a014d3602ca4b84550155373eec5c25b68b3ca347a061638ad17a90413d8b77a2d481704c3e739de64167b9cd038d8c9bbe9d7	\\x00800003f3a9a2d0ced7b3974f39731458e62961598be7c65a591d0096ee3f7f3ea7cbf700c5cb46b2a5fb3958504955d95844d84f3d50e58190340efc07390b361d1a12c3b1d5ea54a7aa6c15b3dff40400903aa57bd5300baa3067c5494412277328548fee8b490531680cf95e40bd9b268550797a28cea17ddeedbe34cd6cc5484505010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x14be6f56aa6107821c9f34ff79af0fa58553b753298e7e9dcd6cb8e73bb5c6aaf5c5f304b13fe7b8d5a163d64908c05cc8168586a76af36daad2442ba4798c0e	1580508087000000	1581112887000000	1643580087000000	1675116087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6d912543e66214903fde5357dc3f1d375f0863b5d10214436972cfc6ff3ce6ce0210930500a1c58bad0b0f5d5ccae17aae238a56b1734a80bfa9b972f9cf0bb6	\\x00800003a348564b1498e1c67d197e9e9c1438e2b8fa038a549442aa1b221e65f570b392a8b0894e9bda4e14d45f9420b16ebf8ec24ca355dc2a5741272f3ccc7d22d1c2171a5af2799669bbafb7f2356e8471053e5252ef94802dcb3c093a73d85a15acf1c658c6978bb0fcf895b220cd98dee19ae2a6d7005482d75094d7e517b001af010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xb8d64776b8037daab5208180fa79f3765603c127d71e20669910235384d6a5331562fdd0bbd2cc4b9b2d34b39166ec94d539cd6b5beb36c1ce09d0107697ca0f	1581112587000000	1581717387000000	1644184587000000	1675720587000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x39481f720a191e393cbd4e1fd48622a96724d0ede3fbbeaaf113e8bce483525aff4d45bd5f3c1f84b41e7f449f6b1989acbe86fb166843cd392117de6ff30f97	\\x00800003af12581d73dfb090be56c70735749d57ad39a0ec99a6719a014c388dfb70ca677a8fd938547c2e257d11e195135703d19a35a394b81d3966382218839a85427ead1fd80179e9d6a7a8ec0b9b6ae3776e838def60626151d01ade8140c44139e7f5c3aa06d987bc13b70edb808f34dd0626e68fb70659f93afc8e763d95e72c27010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x9908a58767730ea97c50f68f7231dc782809efde984ead7d8c28174625bda750ee7965f2e189326c855fe9ac41f4b62b8e008abe1132478de762178729371406	1581717087000000	1582321887000000	1644789087000000	1676325087000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d86cc3a618d24ae15f5f42764275adb465e638d3b44ada532f5a10ed602db6e545a2cd5d7b76f2d7d342e614698a98f48e5810f45f37aa84893dbf1666ddfae	\\x00800003ccc2dcfa3268c78e399b270909ef70f892e217ed16bc1d8052cce719412ddfe8806ac277178d12f7884db514e7b780820e3cbd8c9a6d6bb92550edd7b0575b14b18bee608cd948deb10c0f9dc2d814ff8c82184fda659643c6abcea93feb04a5bb1e3b91858a7c0aa7cf9eaeb53afb226aa0495c082cdabcee74754752566901010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xa91db49b294854f825e7b630250433734b1c3283b1803e0b750533d72c2ea0e271d629db90ee4f9eae6397cc3667912b01756e7ae60c457c81c578528484fe00	1579903587000000	1580508387000000	1642975587000000	1674511587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x534c398f7d6ab48aa73f26101aa54475f09703a0eda6917f0b9b4182a7a2233afdb827e021744790f3e46839586298f17a0f87195ac58fe3e8cb4e821ec62e65	\\x00800003ccc0cf5d947b10ca62cd4a6164178fb69a8d1fa917d468e6e138e27a1169922d4c67ef32a96d9b676df771d74a623768abfc18555fa5d7f9f514f9a13fd1203718354d97cdab66e6585d08d36fad9d23f40a32c66431deea7435a88e54c49b2af7552fe2fdda3164612cdb9d637f813b5e4077b5824fd7133fcfef6c60a9fea9010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x844843d8c7cf5c2506c8c8ed01f494f5dc58ffb6eeb001b26cf83a9c5ec8ca2f760e1fd3a568e712fbe5c3f10d95c65a919d1610fe8d8c6ff79a8bd8e2b47901	1579299087000000	1579903887000000	1642371087000000	1673907087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf05c1e1219b5615e1dbd3f9639f08f2b05aad82c8e4e43d2953366452ce8727a5f09c4e55272cabde2ddd51cd73f5b6089868e931f7baf2979788bbc31c1bce5	\\x00800003b88bb7cc5b59ff11378ae9fd46bd8337ffd4279462163990b3bf372cb7f8fb52d53fe4e40a6ac80fb41fd2baefe760ca9ae7d8417dc641c1998759bb711c20844dea58416cf38c782c69e14d628bab24aa1e949d977a566c69331a4ddba14bf21b26cfcb223894eab1ee6300081021f3c3c0b776604b281a88a63d6bdda2aa2f010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x0640f53d3240cc4390c180879627b5cf0566af4bf1838bf1f8f72fbd6960298a4ded0f6f2c107ba0ca527c90eecb64525b45a4c6f5598a9b4ed11e2987cbff0c	1580508087000000	1581112887000000	1643580087000000	1675116087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa90b4a1f98c68ad279bda4e8c0eba67aecc4eb2f603c0d0113d8fe5f5200daa7fcf3945cfe4d1c61a1f7328649236ddd10d0f18e90d8d4d975eb0d23df9b6ca3	\\x00800003b78865f6823cea39008513a1da1a5f85f2f1f51da6d15d4ee6c3bb4e70b6f92997e658b529ddde5accdd150a555538ce64995e67038868ed22dad2309318da9475852f3889ebff513858688f920aa149c210dc229f377b8a0b61f4e1a483643d654dc2d09eac8498c156c988ce587d3fa112a88e4609d48be93056e197450e11010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x45925f6122c6c274373eb5de20c144a1cd3090a5dc3adfc7f488d91aa3db5049e33c9cf9a698c9f8fcbd13f208861a2ac877df38cd950413e67af76c03b77d01	1581112587000000	1581717387000000	1644184587000000	1675720587000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x32f7f148951539af64223b8b3c372f8b7d14f4c4a85d28e544858b7b524a6a4ede2fd445b6963db0d0498872ca0c856c0ef60e77e58e9538fd8ee498d2a2800c	\\x00800003b7a07a18ede21b967ba3052ba294c035b12581ee769a770cf0c91fba911e3daf0d02e14162670ab5253b07e030274ad32af8b499de116051015a6c0deea4a89b14c0be4303074ac8d517760eed4ed105d29586324aac3fd1be5e53628df95e52a485b7e2dae4def588643e828dc37bead29e9e63a9241b76e0d1ee73bf33d8f9010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xf0a0d6c75cef9295117ab5495567b7cbb5b8f0aee8dced294f62c7b0b57dbe6d0b458288156afd79a934f4e6d097784783ab999bb72fb4a4f726f60dceb1130a	1581717087000000	1582321887000000	1644789087000000	1676325087000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6fd2db5d490aa6be37fc980d292af272db7576cd04cc1540fcf5561c9a01e3a010ca1bde7ac1c7b4666f54f6038414af9f903e4fa90dbef2dde4a5ff342a4d90	\\x00800003d284d111f0b4fdf61a3d8784a7c81eee86e3d20f00f34a2bfe9df33ca6a5129ead00f1323a89a357eca725de76c4aacecd3bd83ffd98be6e79a1aef6ac0108803ef4ca7e0b9ac1a709601091aeab8b55315f08723e83e4ae60dc520415d51c16472e401b289cd86581c4894db651167c2aeb67a485559ef7dd93f318d8a7fa8f010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x56c6e963a7ae45203c4bf71726aadc0a2959bc64fb33533a1bd15797774763d24ce333ec063a3be088b5a638a0e5df1e3d77d6b4cfaeb7ae065beefb760a6c09	1579903587000000	1580508387000000	1642975587000000	1674511587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe4f111e3909876e4337dc0d1083141ae8e0817937cd476137c1bd405b7ff63b7a1a09fa46ebb1cc051c1b4de6c82e0bdf4375bca038f4aaf3c52f1e81b15e488	\\x00800003b78ee647df41f0dab28f3dea56cacb909a9c3e7e615e94ad1d9248285e64760834c2398c8e0522ce3efe23cecc4b254e5bc6232a35a6092adbcb6cd52169a56f404a3810bab430b4a408cc53fe270517aed04e622581fa9d78cd3d1093dbee7146151d1ce240f7f6a5136b365c11322bbc01823f6c6d37f348d059b9c9b962f1010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x6c34625883ae58f37d11b00f7922be4fd5ef1d1f7f511c3f65a223444ac0bd5001846214c28eddce36dfa69b767a1e4879b63b43117f8ede4829f75217283005	1579299087000000	1579903887000000	1642371087000000	1673907087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4f5c2016be8d885bd19f05bc5274110e4dee06a8a31bf2711cb85faadb32242cb8897aa4824ba92514432f7826a34709c670acdfbb44743e2c98cc5bb87b1eb9	\\x008000039bc0e6c686bf796483544d8ca4ed47a8fbd1d430cc150bea6e77d168f2ff6c63529bab5306f9c18cb22f1678ee4d49a5bacd9b1039ee76fbf362dbaa3d4a875cf847db0ee0069b1dffa68f9b2ef771bd12edd3231fdfb184285b3672f0ea18c3619ddda2fe99762c885f027ccb1f9175c8cb1250d87784cf380e9972e4642579010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xee01d5e51088daf7294a566325e1c0a97643aa8af2d4838c89a2ac884eb20737a2166a5dc78bf25c0774cfc05fe2661a769c198484ec0548e0f50ea9c967ff06	1580508087000000	1581112887000000	1643580087000000	1675116087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x634f335f995ec038ebf3531d44a758999efe10cb6685b04f06cef5b6eead3d10fcc60e3f6f64b8ca9654b7207631b2b546aef067208f1ce5742f328b84735b83	\\x00800003a7b1d6b8aebd164a5ca3c93bdc3cdbf4730586915730a639469d26668d29d6d84e4763f2173f75da9b6f26dee568cf96c48e4a6566e44348dc1693e289020c0aebca94e3383a35e3b050bc0658a53da0b6fdd49e69dcd2c48f97cc367bc6d12883a6beb44a7eebbbd7743eeb2bc5bc1bc2074cc54508f281702bd78f75967f23010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x371d499ee151743846c3daefad8fb6e08f5935389c64d26c5f5f031e7e0e8f478f5810ba5af9ddf727d549968c12f9114ea6fc127b3c8b4e61812a1d8794f80c	1581112587000000	1581717387000000	1644184587000000	1675720587000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe3e17207147a78a319bb0e78f6d6a8e22e30e4c96a6cd82622667347b1ad1814785de5fafd90e03b3e7674e1ef1b637264c22c42b6b1941e11aec646ef2685de	\\x00800003a9afd7ee038535427a5ae700ee74ef519bda137208ff173950f426626a05609a22447691cf96ba34b9b4c2f2bd4dd220ce2029ffee4c3b4abb0ff98bb50b050d50ea912276253901caa306780ba632d2084867d4d326e94ac2d119ad4fcf8644e7b37c353f945ed51a5f031e6f96e0a82e59b75774d95da00d1f2f46dadfb31f010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x367ac9cf0fe8f74013a341593fc39e20131377444dbc45c2f9d32d3c0ba2dc313ebc57c38d095ead66bba444e044d1004b538b9c4f488974f1c46457a8b85704	1581717087000000	1582321887000000	1644789087000000	1676325087000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xba90bccd3666a3392a2587e6e9cec8213d1a96efdd9cfd5433caaa7a3ea5e04de1db1606e62fdb0e9531d53890b8134066908088bdd2bef463965c7e2d802082	\\x00800003dfbc3f9e03a8508bd360e4c14356109c8608f43bac9024099301eb638d460ac9712774f43cb79f16327dc5e2c31ea650f5d01ff73543a7f1ebc37001d7876797e72b82f4d1660d90c3687974d0f0073935bf9bf827efdd9696caca7421d97e567f06f43472b1d3c9707a3d180a997698fde473effe3b3cf49c3c2b6621e1a021010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x924d3ffa41cf4d556b8a937fa94029418396a37335e59bf00a3d8a565d6eb05d4fb84a9babb49e38bfb0ef93dd9fdf5923fd45b782617784f1b4f9c88f6f3c05	1579903587000000	1580508387000000	1642975587000000	1674511587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x28aebf96d858e7201c6652abe628f3d3afe4cf4e93c04e84af2b2cb077fa72c0b37fdf7c0e970ccac4ef3c6c345962a26a0a219987102c39aa3e9b1e19567332	\\x00800003c15b7512bdaf01bb2ec8d02705a0ad428d93d0a737a24361574f75e3ee2bca0840093f3affd80b470c1da61c0949d114170ef9b0f2159c40361e3dc6c923fe5f356a74bf16069e1dac74aeade3f17395ff4585555c6c898feb76f9d83b5fc10dd845f2cedeb54be81a9018d7fd45c4d570977bdb5a71b5fecd45dc0ee8737199010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xe1a6635db55764ff274a8e6091b5ef5b85ed90257edf683c9f14714b947d43650c63783538ad04e10342242e589ad26a68e7c9d3e246dc1c6edbf4c29f2fa50d	1579299087000000	1579903887000000	1642371087000000	1673907087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf82ae30b6f937f6901e4cd22b068704259cf1c2473efbe7052527d7ed5b6a510417185691567fd9b087ad2f548db957f6ef4add8c217ce5abe98e4d5494d68b0	\\x00800003c8da4e09b99448702d33452a1047ac53eb6ab1452b56c2c1a4899ea5be788a3fe0e895a63f6000fa801ca7ca5f3965fb922635afdc602809fe2f34302e1620bc313d0e900930ef901931f3ff6a62c18d77eeac2a9aab8ed6b28625d98df4e986ad390a922485b8d69dc7749779273616cc5b10eb316b10a6f5eb33921071a13f010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xcdd2b32954688f052d930a0ec1e64d213041ce559ef6dfd572e9e0e4399376003515beee7ba0ec16769971cff993b9486e7736e9fd42f63f669810f1b99f9a01	1580508087000000	1581112887000000	1643580087000000	1675116087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x26fda93c59e71ce293abb3a37d92d6c61d49d4232fbbb9fbfb41a33a8a90ee6087a4208b0e2883faca38523a7285fa7fd85cdfd978dda4fe2c36dcb3bb6cb36c	\\x00800003a4b47f6964a805a3b42f1ccddbcfd8b7a6f8116effd1e86b0d909a3de06d551db017f47449ae1113fcb965f67e59bd90bbe7d93d85bccc32103c38482672de0b1c496fc6b60d1ab9327f7fd9286774c720d22e915cb24ee4713cd7809600eeaaf5660f027e209fddf3b3e4733d80e68f27358881e730c8c3cfc8492edac9a3fd010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x5f28716c42db09798b89771f8171685403417021984179967a6802f001f51e93e2926741358a836c9948fd6f0b2e9e233f08cc8ca032f3a6a85997ec31c6930f	1581112587000000	1581717387000000	1644184587000000	1675720587000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbede0bfbc9357155923352cd433f6a134979b17b08fd77bc1b680b037531d97c95176721fc2be1e65e881e03150abd66344cc0644e5cd5fa993d6340ff2bb37c	\\x00800003c6b738132f3ceac2be4360850ea90cf6845a41fbf0b263c84dc2505a1e43df88284a2c1cc84989f91518f64d1f01736aa722276e876a849c6ec20e33e4efedfb51e23417d7295258dac625d316550a0e97a91d0a1d2a4b0add2ae3b78919b4df850a42d778ebffccc18125d59866bbd991a22333b75fb1db6d2c265c349dad3d010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x4df02c1fc9b0c2226cf359a8845e31aa34d749b8773a4761034b1031e2fce8d67b18f3cfd3f7c1a8e9043c0f9bcd9873c47cdf4a687e697e7ce516408fab520c	1581717087000000	1582321887000000	1644789087000000	1676325087000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd56ec53c635f96594b84f7afb4e9837abae77bd044e775c469af98ed8378698e6d79b81a36f3c304216befa523d4246e1fc50df68057d02bca70005cf5e0bf08	\\x00800003f0f8acf314c4e6a0c3bff733a62c1c7443b5aa427d2cd145c3f0d4494630f1e18fbe4a4cf8a673b958075e20329d43a1df92a25745f0c49249a242e8b9e4c473ccf5e9fff33be67ba3f3e4547a1d491f66f8c0a0d21509f11d75d9575e7eb79245550adcfe22b7e9594383bb97ebbf3316db4c465d35932ffa7bc659eac149fb010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xf5ac5df3cbad45b169cf1d9fda999a5e5af4a0c5e193ab452b14eee06eb858b7a6b7a2ea7bb364132bce5181b3e5b4dca32b1fa4c7a39adf5a7c2074cdec3e0d	1579903587000000	1580508387000000	1642975587000000	1674511587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x00800003cbc291157ef1f2dc40f881685d5cf03ae44b96f018d984a18c564e55066a058d9ab13494a02f001c9088d504e9a37a72c10bc9c88722eaf75f990f79261bf0d10d80521fe25ab2f34b4c164953b8000737ccf1654c812c90b3e2119136880544dcb072d01298feb715f31e9864b002fa8b0f118f71f59218cd6c9c68803b69d1010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x3e26566ff8c60e149f6f09cbb0c75753903f59583c19b4e1c6de81950d699156d9b47e1ab65c07fce2c4bef40e8b7e2ad9820998ac4fedad8a848058e3df0903	1579299087000000	1579903887000000	1642371087000000	1673907087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x15cfb80ea679904a3784ca94ee4f5f7c71de596df8f8bfc4f2d9fd2430f7395a9b53d12e5c2b842cd51ff0b4cb522714dd0c532d0898d37bdafb6cbc2d4e972d	\\x00800003ccbe76ba9abec233da7cfd3e86d0b69eff988ccc545d62a7c778d0f7218da8619a02189e17ff02a54810d99de5106649a4e03a72fabcd4c0da316387c124544f937c7f6addd49c0af968f54c10a1dc5a73bce2b5fbafe17d5ded9b9a1b57f9a72560244fdd7c5a71a7f7429633c5944a34f5f673eb5a938d84ce767f54febf1b010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xad997711ff0e2a8bfac6326462fe5a5a0df9d693ed1a797dbd87b266e1998178e3498089a84f9325498bbebd36341cbe06ba755a8fab04fc3a711638f80c3902	1580508087000000	1581112887000000	1643580087000000	1675116087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a3524c01581f1c57a80e9d1ef10315443fe0c9165ca332f474ba26032a9cd75d879b29830e252ca8ac0e00bbb30b1708e9f36b8707a1baba4ad39e715bc25ba	\\x00800003edf813e8e43c9f55bbc7d656f2fa8b4ab1ea07a888a83adc473098fe32e593688618108427b5bd02898ccb11607ed6b08ad0c7885ef3015cc93724af6d2f199c2f86334fbe2923f6b8440950513aa940318211503430513ba36205f188117043746dfa247e5da2b94824b15f4ee83c09d1d65b0f3c25e73eee037651413a5399010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xa59b5b9488dc09debbd5403ab4957fa942a80bd32a79d311bc0693ecf5af4a2148f43fa77a47eabbda13cb0494376634963af8f94b2548205257e03c340ce50c	1581112587000000	1581717387000000	1644184587000000	1675720587000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb528f868e314d48da7281f9b7e775f5f73ed17592a5fc567fdf1ef3ae6a5e07e5279b142d683af41ec5f81a80c252bff072866a5cd97532fab157b3c416ec6ea	\\x008000039779582b30a08c9a7bb85f21b3165a7c9b9186bb92f2eedbfb4c91baa6c12c0f5e4aed2b2f55dac416ebf38aa6008837a58e603c7cd4bcd31682b6c8e9f8e49bf0dee9a2f3f36ebf4588327cc0899a3a6dbdfc329062ca2ee6acd8f533402d2d3cfbee88917a9fad9ea44a295b29ccfa59d92b9146a93763eebfd8905e04406d010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x0fa31bd0341a1f7caa2d980826034b85b3caa0d18d3f3a956dde1a8b4c768ad37b9b5aa1bfddb07ce1a8ab72a3f916088a908aa492d0d1cd12ef2f5a75f3260c	1581717087000000	1582321887000000	1644789087000000	1676325087000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8caf10994e162e7e58adb2274b33cd400f73a72d7512736d3faece59be7a59e0f24aaf82bc93f3277b732ddd71ef62a6e346294970f5f36797ab32145b76f263	\\x00800003f6d2ac2e8db6ce0f73426c8a79ecc2b13a0785687995272ee0b251ec185fc9b27d6d8182ee446108a9e611eb9282b31da096b9732d39a0845131628d622011b31e38893994e30ca8421541f45112aed99bc92fb7d8a0c8dc006dace6dc08e0ed8b6627ee5ceb80ddf2fd1a51e5d1257a1e5e634235194a6b81e0d92144d8c92f010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x5de42429100c8302a2fca3c472c223405860a50c4da0734648b82b46c3647fa2403e5a2eba5c15feb78f07664ca319c499b70eda16a77e16496aba39b64e050b	1579903587000000	1580508387000000	1642975587000000	1674511587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb9cf82166e19308568ec964e4d77e2c2ee5b1b2efb1c32b0231e50a05910035a1ecf4d2e9b823351083f822612286acd2aaa0815cb822ad3332032d9f6797cea	\\x00800003d55b72814bee7c8c829d5d03b3dda82380002a0815cb130fc0a46def0503e26cef3110de1b23938f8e67aed9d344f7d96efafa46a5456a3b2705785324672174b64dbca3c53be7ce084a5940c5d23afa8b322c8958cc7b2831fa4a860758f3bc143633662382af858c84d1338c2637ecd08c0fcf43e66ef3349106452e6fb9c1010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xeb550f7833c79befe4ea6355e9a09589e41abf91010d08dd18640c9bf5fd5109b69d671e3d384af850f6a89f95150a184cdda381a78e2690a00a2ceb972ffe01	1579299087000000	1579903887000000	1642371087000000	1673907087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf58603ea8aa79f746dc1b3eb0281323887c0d1df84fd8e489a93c47afd874e5e8f8572a554aba59e7a2d05fcd1d226907fbc3648470504ca997fa2e4c55965dd	\\x00800003c6d89bda21e80bf2c12e9f00aa21e3e3d4c9d308e945b94283a0a43dba43247bd3199cac405ea73f10f8d61b0939d6f521ed480bfa27beb7c417b2e32ef2f40bbde88c7c9b753e527311fe1af84790078dd65fcb9263b4b03d0e0c3486d71191a0cd006111e1c5e16fe860460182dc87b2e30ee1b606bcdf796e21a54c694353010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xf8b989f28b12f938814cbed8a4f02dc4d14dd19f2a6f7ba5355b28769f882df94195233a57edbe50945dfd24235b263e9ac53d03f26a1cac56f57b5b3aaecd0e	1580508087000000	1581112887000000	1643580087000000	1675116087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1119bc1627be568a22e1731a6d724682bccd82877b0bd3e306cc9c974e9188b93081e29f8283796e1e251705d8c07867d4bbe578bb7ac3a02824715f56eea841	\\x00800003ac1022511bd7c152b2dd674e4e4e8c85125557f760e220d1cf9ea07b0932f2b0d571606ed47bd7d345256286ef3d948f586176d8b948a5fbfb8fbfce5958535672882246861b572e49119df83ad921e28de6a203ad1717d0692fe22f83d8a967e106a5fcb405a457612a6c76f6ec8adb64098e103527e795e1573088bee04a0b010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\x4318592ec9869c1d2b8e95840f512db04d43a0ed1a5106b4b3ec336821f4c4413596448ea42a6d8451cdbd6f639440184e91e7047b7d1c6bb80217e772fbf006	1581112587000000	1581717387000000	1644184587000000	1675720587000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x025f6e8928bf234406ba92110d99846516c2cf71e0a9745e005a730036b6d2e8d382591a70a5c841b9b0007029fb2a312392a634cc0a2a898a4764eb7429bf2e	\\x00800003e19c11a3c3d2bb67eb1fe6e8da0d3695efca8abd262ec4d58c3d6329cc0f57fc6b644be8162821cac93ce4778315a88d482ccd9ff0dd3279860626e489d1aa6fea8e1b6f79a143b2e7f09567c9d702820ed7af16280cacf377eded1632f948b1bf99c581b9aa28b8845bf16ff47843e504d9f9a0af1a5b17444e7fed9212eaf9010001	\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xda92ccd1809bb2f20ba0311e5b3dee3c3d76c2c36b41423ea22b85de7f5dc4c1a0b062dac974a32f669eb8158c13d413fd2522654d4bdcc688ef17e06b73b900	1581717087000000	1582321887000000	1644789087000000	1676325087000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	1	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	2	20000000	\\x82dc8ff628603707320c30dcbe7a4bfba2fdc2c7b83c9f80132094ce75108478	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x4a757958ce834dc21ceb52859337bad00f5b5a8be212e75fa5e983c42ea77d9e9bac9d95d7d90a75a6a473fd54cde0bb598db3968802bad7b632deef7d24660b	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0b57f5a367f00007098bf4d82550000890d0044367f00000a0d0044367f0000f00c0044367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	2	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	98000000	\\xf05253f90a6b6719a9f20e7ff5e1c3b4f7e268ea70436084c473ce513b5e1c78	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x5b2b7df939f5ddd1a4c1605303576cfae201a43c26dc4e50543985c58f7d4821bc0056b8644a6eb6adb1e3a2814c1abb17e2b011db38270d2609c0785b57790f	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0b57f76367f00007098bf4d82550000890d0064367f00000a0d0064367f0000f00c0064367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	3	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	9000000	\\x3e973dd11efc7927327897fbbfcce8afb2efd98c550bcd8bfc5bda095a3694cd	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xc89cd38bda82b2adfba76e3d2c7810bfe56f2cf700ff9533e56fcdc368e892fa0affe03d19b6923d2de141d6a5714f1c0f5a160ded06fa79cb15ad069852540e	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0b57f36367f00007098bf4d82550000890d001c367f00000a0d001c367f0000f00c001c367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	4	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	9000000	\\x9d2c79ef17b55055697b49fed33aa404f3350b2ff8b6bc2dc4f11eab3281967b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x2aef5ef586aa3a33eda2d571afe4b8a3d55703723c0241d768f22e0611abf4ad2bceaf28b81211b11665a0ef6f5e79f9540b5e3f5eb3d3eb736a00de66e3ac08	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0a5ff35367f00007098bf4d82550000890d0014367f00000a0d0014367f0000f00c0014367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	5	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	9000000	\\xbdb6a401bb67e53286a04aee1e942e80cb724da5cc0ffda1added1610d1d36f8	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x7098773f6b47f2f75f09c31a3999984f89e3b1a98c2938a059f6fd80a3d7c1fd186747b48377677d752ad6a234c988bae56469cc1c75b0cfa506ebaf3da7b901	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0d57f37367f00007098bf4d82550000890d002c367f00000a0d002c367f0000f00c002c367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	6	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	9000000	\\x7713c6109467de2b0e0161f4086b3e354244d9d637eea172ccc27373b554a454	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xf88c5c4f111fbe1c9eb8c2bd2d7af28780c64bc1a5799c52ff7131dcb1e3a6916a96ca3c248c7e4c906085fe5114334932fb999cb1c6cadfb45edfe5a9d8220c	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0a5ff25367f00007098bf4d82550000890d0000367f00000a0d0000367f0000f00c0000367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	7	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	9000000	\\xc40a3af5eab102b62af7726fb5bc9cab9003d7023f39dd03575dfb7370a8c62b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xe0f6c4e6928f9da04e0608880f55375b3f7f366940b3e1046312af211246da10685731cf06185d710e6372d24b363c040d062f3bb9b2872e07859d2f56981f08	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0c5ff5a367f00007098bf4d82550000890d0040367f00000a0d0040367f0000f00c0040367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	8	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	9000000	\\xa04dda28f6f817ce1565e86f09882f04d226328a88d537553d1e4960ac6b3dea	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x27845a7011519d07a70b1da014425f9c577502607527bf69238eb480c7f70a54534b28ecc84093cf31f545c9af5aed1ecc2114976b13d4775dee16468b2b0b04	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0d5558d367f00007098bf4d82550000890d007c367f00000a0d007c367f0000f00c007c367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	9	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	9000000	\\xe32e9b55b07b5359a1702a35baf9b1f3db5eb17349962dcd94a8c8b66bc8136e	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x7b03f7ad7f2d07a6d8940d800810a85a5dfb0755ff61211ba4ec740cc514328020796a3a9d39678bba4d0220fa36f650272ce13f0e3bc512eb3e23074abadb00	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e085ff74367f00007098bf4d82550000890d0050367f00000a0d0050367f0000f00c0050367f0000
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	10	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	1579299104000000	1579300004000000	0	9000000	\\xdb659cfc36b50e8e17cc1e0cc344271e365c15394d409097db220942af36f992	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xe7d6707af096a67744609b0e80fa39e0fe68d77b50e7c223b716c24f45827e086e42c1641d5b33057a0e29d7667b6aad6a8968499c59aee463049aae8b25ac00	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x16257790367f000000000000000000002e966b9001000000e0d57f77367f00007098bf4d82550000890d006c367f00000a0d006c367f0000f00c006c367f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x3e973dd11efc7927327897fbbfcce8afb2efd98c550bcd8bfc5bda095a3694cd	0	10000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\xb1829c94dd036c6142bd79d0afaa3c656659eabf086453abf3624348a775b91cf6d9bd198903a886690adadd256bc8bb1eb04a1eef9e9ff34e633d1ee623f609	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
2	\\x82dc8ff628603707320c30dcbe7a4bfba2fdc2c7b83c9f80132094ce75108478	2	22000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\x1bddae3f0760519d67e8513bfdbc688c85ff3f59516512c327c38d99d8490cc2e969219c0afa67ce5f88d24e499d192718ed7b8c1ed179fc5188ef382a533600	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
3	\\xdb659cfc36b50e8e17cc1e0cc344271e365c15394d409097db220942af36f992	0	10000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\x6f472ed5710d1dd7665de75291fef6776b8bf3a6ba9ec08e39db0aec94d242fdb53585e612fc91c03347ca48e9fcca7ee1a7713cafd93d52858dfb5e3b2c0e00	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
4	\\xf05253f90a6b6719a9f20e7ff5e1c3b4f7e268ea70436084c473ce513b5e1c78	1	0	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\xa1b8c397935cfe6610bead710800cb1e5fb56888d53cbcd1d210a6c6ad9772d2388cc82814ccdf8b54ff07af1c4c1c8e9c9158a59c2ed0dd786d3d3f6e83210a	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
5	\\x7713c6109467de2b0e0161f4086b3e354244d9d637eea172ccc27373b554a454	0	10000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\x53cb7b4c51166eb4a17eb01c2b8b30dc04d1919b00e6ec087b538f1ea2e566b6bb595e76234483659811d040a31f4d6beb49bdbe698444617d8fce836b674a0a	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
6	\\x9d2c79ef17b55055697b49fed33aa404f3350b2ff8b6bc2dc4f11eab3281967b	0	10000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\x88e4098ecd2dd516f2f0ab2dc6d6445a2fc16fafe38e92c4808d2c47635d5549e56a1b0b8043aa31865f354290ca338dbe712ef8515be172405e85c9aef17206	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
7	\\xa04dda28f6f817ce1565e86f09882f04d226328a88d537553d1e4960ac6b3dea	0	10000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\x1c91f68e7957e63ed894281c9b05fba7a6fbf2d72ad3bf677c2915cd4ee1251b68854102fdae705344b7bbe3119fafbe4271c7a4e40c0c74f35ff38da71f5408	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
8	\\xbdb6a401bb67e53286a04aee1e942e80cb724da5cc0ffda1added1610d1d36f8	0	10000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\xbe495298fc4aaaeed3367254c8ffad87b4a44a7d0a31147d45785067b103e774759ae62127014d1627e0e53251f2962cc4534336d00045907e613697c0e75303	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
9	\\xc40a3af5eab102b62af7726fb5bc9cab9003d7023f39dd03575dfb7370a8c62b	0	10000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\x6205dce39223923b04a483709dd1b2f4cbb47a3aa13431543738b8de729b5d275cd43260044541692ce2aa2fd716eaab4ce055d3f9bfd721b169aabc5a7feb09	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
10	\\xe32e9b55b07b5359a1702a35baf9b1f3db5eb17349962dcd94a8c8b66bc8136e	0	10000000	1579299104000000	1579300004000000	1579300004000000	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x872e7f0bebca0164af4d4b9341282ba36feaeb8a5b7d55e5f9bbe5e46e391002957d244b399da929639ee0048b922657cff0d19baf6de22bf32d29188d0fd10d	\\x4ed2458c2168a57e88d26eb362f86b03179ee41d7eba39726d53a68d11efa2192b7cfa5662d7e1ca21e9d9a1f5badd05703411067ea8d93f7a7cd3255163a003	{"url":"payto://x-taler-bank/localhost/3","salt":"9H6AX6VR1FQRXCKAYE2Z6X27RPG455MCDW68JHY00S6WA9BAD8R8CTZTJ848VYEWR56BWBKPAQZWCJ39844VNJZPM6663PCCGPFGFBG"}	f	f
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
1	contenttypes	0001_initial	2020-01-17 23:11:40.235601+01
2	auth	0001_initial	2020-01-17 23:11:40.258446+01
3	app	0001_initial	2020-01-17 23:11:40.297775+01
4	contenttypes	0002_remove_content_type_name	2020-01-17 23:11:40.319706+01
5	auth	0002_alter_permission_name_max_length	2020-01-17 23:11:40.322807+01
6	auth	0003_alter_user_email_max_length	2020-01-17 23:11:40.328581+01
7	auth	0004_alter_user_username_opts	2020-01-17 23:11:40.333837+01
8	auth	0005_alter_user_last_login_null	2020-01-17 23:11:40.340032+01
9	auth	0006_require_contenttypes_0002	2020-01-17 23:11:40.341816+01
10	auth	0007_alter_validators_add_error_messages	2020-01-17 23:11:40.349211+01
11	auth	0008_alter_user_username_max_length	2020-01-17 23:11:40.356648+01
12	auth	0009_alter_user_last_name_max_length	2020-01-17 23:11:40.365678+01
13	auth	0010_alter_group_name_max_length	2020-01-17 23:11:40.372071+01
14	auth	0011_update_proxy_permissions	2020-01-17 23:11:40.378505+01
15	sessions	0001_initial	2020-01-17 23:11:40.382804+01
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
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xcea5aa7fece7ffec70d443d4c5e173197f352b92cae6a82cd6b9abdedbc5e1e1dbf137ce932884ef2aae74e799c6fa82e2353aa15c4cf663f163d05c93a09f00
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\xd92a5f70424b089020d6f41c9a903b6a0c68d48b1edbb24feaaf9846a122277a052568e05bf4043fbb7a954c7c689174ff0688bfac866e788440126633546805
\\x48a074e9f0ca045478fc849e5e5c5aee9998d328ea4fc3828f766b931c2db872	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x3d2e34cbd921770bdcf9b1cee107029076e875906e27f043e473cc59b671c5b19fac648637bdd9e5ef0dba739d9d199013f0557860453223e20b3aac1d48d007
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x3e973dd11efc7927327897fbbfcce8afb2efd98c550bcd8bfc5bda095a3694cd	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x2008be10466bbad9b29ab0cf838182f693dd3430f6cf0a610980a7e9eb9d09397dbde747cee8846530b2cc65f307d227526b13c5bba761501ce1861016aa2d996abff45e5d6cc4c82fde1d9cf41b633c02e82f810c9ea85146c9e92caf47326e584af87d6f194bbe56b1b4f9b7da7f93c05b5ae0e31e9df9d338188172a440b5
\\x7713c6109467de2b0e0161f4086b3e354244d9d637eea172ccc27373b554a454	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x651ba36f0e1717b7ea173a1808a00d750c432cec8132f40674717a6175e5b1c254cd8901f9822f2a4b5bcfc4d00b1419206bf17ea85d4301f6e1bf8c0fce7516a291c604e08b18bc164cca5a5e739e88fc601e5292c9d2ecb6efeb36bd7993b00f08cce05fc5f079c79f0ca1d5864734ca5fdf4f7d550950d950b7f89563e06b
\\x9d2c79ef17b55055697b49fed33aa404f3350b2ff8b6bc2dc4f11eab3281967b	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x1808dd4797f75dce85dcde43d2de0e084dac5dfc6ead5df341c912525080ec9bbe515245534f14a7b5560a0b5816e5e6f320a61c93c69d7c8c3476132c23f5c7e2b8c8c70f7a7dc9108bbf21b9882e5c67f78caf74f1a36807dae56e2b72a77841fe6eb4e17fcdb809aa43acad178474a2583cd5f536bf402c92314b4679694d
\\x82dc8ff628603707320c30dcbe7a4bfba2fdc2c7b83c9f80132094ce75108478	\\xb9cf82166e19308568ec964e4d77e2c2ee5b1b2efb1c32b0231e50a05910035a1ecf4d2e9b823351083f822612286acd2aaa0815cb822ad3332032d9f6797cea	\\xa921614fd647d3f014f41cf97d3f230286aac6c137768a42524d25825e8981f584ee038701fde4ee0e5934bd2d7c535d97f277dbafc506c8cca24742bf973fa94e9ceaaf2904c784e8e1ff4b060a4f2fa5e8d3a8aa2312449c8ac6d83e51ad45f5cd2d61f67e9cea13e687037fff6dbc74dd309f845cc841e9bc001e9ff21a30
\\xf05253f90a6b6719a9f20e7ff5e1c3b4f7e268ea70436084c473ce513b5e1c78	\\xe4f111e3909876e4337dc0d1083141ae8e0817937cd476137c1bd405b7ff63b7a1a09fa46ebb1cc051c1b4de6c82e0bdf4375bca038f4aaf3c52f1e81b15e488	\\xa5bab329b19fe3ccfa388409fb025de736bda6d6f1bd3c645b161c3037899c22ccd31a84b289dac706d54edc9dded434f96ed799580a97bbfb8b35e79b60494311257f3762f67f98a7e7b5f022e71413847cb3fbf544cf2029f5261edeeed816bb6b39fe831792d22e01edaff53e2c483b9effb0fb896fb40531f90de6648560
\\xdb659cfc36b50e8e17cc1e0cc344271e365c15394d409097db220942af36f992	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x63f3cec15dc2f11558babac476673d3d4a485bace1260fe5fc73e220821dfa2f548371ce0d9a3f8e283624164d78ecd8d1fab3fc32ce5fa47ae0394bef9707d37e0e1005a7a6ef7aad70e31e6646d929e16267396fe2876ba107c0397f6be5a8748a114601b081379f89bbab0bb87aa611b4516dd5f78cca088369bfb691a494
\\xa04dda28f6f817ce1565e86f09882f04d226328a88d537553d1e4960ac6b3dea	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x0563d92322add08c8443899185e92015aaaccb899b5b8c548d5edad68f12ccb54fd2b829224e6bdb3af6a3f1bb67a81f4eaae773f0ec4ab37a905b360385da2893a54f346eb6b1e2b502b504230305f69b843fd625a24778e60b2abf27541d772a9460a58445d924d7fe5724f04cb8a2f7abc8f99f46baf0b936c65679469369
\\xbdb6a401bb67e53286a04aee1e942e80cb724da5cc0ffda1added1610d1d36f8	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\xa03bbed6d8623e75fff3140c98ac3f9ba207a0b48925f546a89f2a71b410cf76b7a9b467cd4819dfc9019de82d1054f38c359be324a0a0a5e06a0315ff5a8e742ab7f91859acf60a6c8cd239ed9dddb330bf826f1688c4beb965fb0f5e90e56a28a8a3e7eb8d912bb344312b53451b4dcc635e0cb4e43ebb48e52feb12dcee58
\\xc40a3af5eab102b62af7726fb5bc9cab9003d7023f39dd03575dfb7370a8c62b	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\xbc3cda5cbc9c4f29ae4cfdafec88d62fcbb336f9e6351882a98eaaf51d5dda634c3c60958f9bec00c0ca3d6f5b8809c5a01475bffea4983ab1738b6884ad1f9d06fcdbb7799751816d4ef1f001c533a49442a13ae0f6282e0ce5423646b06a1dec0828fa048956ee12afa87fe93fc89c85cbee40e6f824c63316d1aefdf08563
\\xe32e9b55b07b5359a1702a35baf9b1f3db5eb17349962dcd94a8c8b66bc8136e	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x6d31040c05d1999f796ff268a4bb1211bf96828e622bf9957378ab3abf9ba01051c1cf011eb93c079b0861c26450c3f69d2909104d20adc9cf54bd9676cbfb85162856b2784c7dc896a46af82585dcb9d12572802ec113cdef0486cd2eed7da79ef908e6a84c5a0f0d0db71a982ff075c63fddc897e3ffbe950b2d813d2ebb69
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2020.017-027PR92A8WV14	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537393330303030343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537393330303030343030307d2c226f726465725f6964223a22323032302e3031372d30323750523932413857563134222c2274696d657374616d70223a7b22745f6d73223a313537393239393130343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537393338353530343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2239324737395446475338323538593757474a46355751325458544353484d53385839375737304d4645534e533637314451315330227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a224757513759325a4253383050394254443945394d324131424d4451594e5457414244594e4253465351464a593856485332303139415a3934394357535641393943454645303134424a384b35464b5a4754364454595646323546534a54413852484d3758323338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22345154384b534a4e444446524d56424d41305a4e4d425a4b4a454244444a434a4a4b52395a4531324630514d4636305447345230222c226e6f6e6365223a22414656395a53514156303441415833455058595935533038335650574358584d584d32373251414d4d3850433848443248575130227d	\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	1579299104000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x82dc8ff628603707320c30dcbe7a4bfba2fdc2c7b83c9f80132094ce75108478	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22393954514a503645474436573437374241413253364458545430374e50504d4257383945455158355836315738424e3746504639514234584a5142584a324b4e4d544a37375a414d53514742505043445045423847304e545459563335515146464d4a36433252222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x3e973dd11efc7927327897fbbfcce8afb2efd98c550bcd8bfc5bda095a3694cd	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22533245443732595447415341565958374452594a52593047515a4a505942375130335a5341435a35445a3657365437384a4258304e5a5a30374d4356443448583551474d334e4e354535374852335454325236595431515446373548424238364b313935383347222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x7713c6109467de2b0e0161f4086b3e354244d9d637eea172ccc27373b554a454	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a323635524b524833595a3153374e525241594a5459514a47593043434a59314d4e5753524d515a45345258534346334d5438504e35504137474a38525a4a434a314738425a4a483247534d4a4351564b364542334850415659543558515a354e374332343330222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x9d2c79ef17b55055697b49fed33aa404f3350b2ff8b6bc2dc4f11eab3281967b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223542514e585843364e38583337564432544e52545a5335524d46414e4530564a37473134334e56385938513043344442594a504a514b4e46353257313434444832534a54315656464253575a4a4e304242525a4e5843594b584453504d30365943564854523230222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xa04dda28f6f817ce1565e86f09882f04d226328a88d537553d1e4960ac6b3dea	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22345932354d57304841364547463952423350473138474a5a4b48425141304b30454d4b56595439334854543831485a5131394135364a5338584b3434313459463637544d424a444642425048584b3131324a42505034594d4558455957354a3648434e47503130222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xbdb6a401bb67e53286a04aee1e942e80cb724da5cc0ffda1added1610d1d36f8	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224532433745465642385a534645515239524344334b364352395934593743443948474d4b4838325359565952313859515237594847535437504a315145535658454d4e444438484d533634424e534234443736315258444753594a474454584637504b564a3038222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xc40a3af5eab102b62af7726fb5bc9cab9003d7023f39dd03575dfb7370a8c62b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225733564339534d4a48594554304b473631323430594e395142435a5159444b3938325359323133333241514a32344a3656383836474e5348535733314751424831534851354d4a423652593038333836355758564b434d37355233524237394641544331593230222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xdb659cfc36b50e8e17cc1e0cc344271e365c15394d409097db220942af36f992	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22575a4237305951474a544b37454833304b4337383159485357335a36484e565641334b5734385851325631345948433246523436574750314347454e50435235463837324b4e563646444e4154544d3944313453525044455748484739364e4548434a54523030222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xe32e9b55b07b5359a1702a35baf9b1f3db5eb17349962dcd94a8c8b66bc8136e	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224643315a4642425a354d33544450344d31503030473435384239455a5031544e5a58474a32365834584854305348384d36413032305942413741454b4a5357425139364734383754365656353039534357345a475745593532424e4b5738523739415844503030222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\\x53bb6a463fcbb818edc22be9e974824febe3a95ba5ffd03994462359fba9db3e49e5169d0af9e77f39a58645fe7abbdd4bc25a720bf2005cb9bfd2eb87e5331b	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\xf05253f90a6b6719a9f20e7ff5e1c3b4f7e268ea70436084c473ce513b5e1c78	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x49b16b55be108fb1af1ec155fbd6eda5ebff0d59fdb42799953824c822a77bf3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2242434e5156593953595145583339363143313947364e56435a4248303339315734564534574d324d3736325742335658393047565230325051314a344d564e504e50525937384d313947444250355a325030385850453137314d4b304b473352424442514a3352222c22707562223a2239365250504e445932323756334252595235415a514e51444d514e5a593341535a5054324636434e37304a4347384e3746465347227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2020.017-027PR92A8WV14	\\x25f489e6556b5f8a6d74503f5a2ff39396d6c99294f09fb822782f47981a8130	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537393330303030343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537393330303030343030307d2c226f726465725f6964223a22323032302e3031372d30323750523932413857563134222c2274696d657374616d70223a7b22745f6d73223a313537393239393130343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537393338353530343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2239324737395446475338323538593757474a46355751325458544353484d53385839375737304d4645534e533637314451315330227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a224757513759325a4253383050394254443945394d324131424d4451594e5457414244594e4253465351464a593856485332303139415a3934394357535641393943454645303134424a384b35464b5a4754364454595646323546534a54413852484d3758323338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22345154384b534a4e444446524d56424d41305a4e4d425a4b4a454244444a434a4a4b52395a4531324630514d4636305447345230227d	1579299104000000
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
1	\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	\\x82dc8ff628603707320c30dcbe7a4bfba2fdc2c7b83c9f80132094ce75108478	\\x12806ef82086d75333dbb02bb914f0fe80a555dc62992e9bea9152b0df88ddc863ae36a8cb976cd6a735e26f2db8f3d65500e6b2af69dad20679da464dbd8108	5	78000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	0	\\xe960a607c7ed87b5e40ff075ecf89302ba1ae9741e1f0c2e3a2b8f3ea20b727666ab3a0a57cbd92474fbeb1a4589797a9fdc34f671974bdc1d2517a5696ec60c	\\x295e467a2b0ecf360eddda0ebcf9da228097b67e2ee62cee1f0afd217895beb4b0b23fec2f9d7424958ffebe23d766a064f0df87916f01faec8929d51ce4bd46	\\x8b19b0d1266401ab9534cceb5c44c61f749e589cd8e288d14b302105dae3e82a09bd853546bda78d82084be6e9af71a2a9bbfcb4b9492e5754e162443ca0e7755ca4281bb627101182515aec40aee8ee0428e5b3fc8e50c12afdd08f9f3d2c59c6f03cfff7e8bbecb7d47684847f3f169d82203ab4e717e4782e59c75bf79625	\\xb3e2284d214e5e14e863320a832bab1957f477cb5c4ed1d0724fb8714c068efae2f23a469314680967d208100cea2e43e877690cd53e6194804bb737b0d46399	\\x97bb546ddd306defac9ad714246ac1f26391c550cc0050ccb57ac2e6bdf1e0a473d60bd82d6f79580f9da3236dd55ae83904db1680bf5003277aa8c0c0c27749cadf33daa4f0d140d8ea7b36a1772d707e86f563ac539214d6eb3252ea01e13b8f448d9c40cae7609c15684b5b36073a21db35c02a60408c710cfa2845c4b1eb
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	1	\\x27bf84707dbbda080519544799173e2650f664d3cbe6f6a1decb0099c70dcc7867838b90081372bd2a736d699852ac024019695547cf5e1f380fe8e2b4cf2806	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x6a9d4112068b2f17b43bbb45d4e091e4fb1189d0be9d164cd80dc510707d0c6d95663bca1328dd0b3943f931fd48ca03f54257c41754a2f3de686a8e7f2e6407f1971f283dfa7c93a235d8da1d652ee0bbf9f06bf2aeedd993f4ae9fcd0cd1ffcf4dd37ad19eff61dfd0bcfb321c32ff1c624afb7000b7a5eea187d1794b47bd	\\x196680032c316615840be25263fd2da0cbe7f21c236bd541887ad2c174041c4e5edbb4404118126e8c30a83dcc71baa5f5a8698f561815ef5a27b0ce365e4fa9	\\x37aa189331371512230957385f9350c10f4dd897523baa8aa2fc60d20ddf06c59e9097182dfd194ff26e2693b4ca432a74abbd5345949a837fbe279d2484ce6007f3aabaf6bc4aa6e5c8d5b1479efbf91adbcae45c6823f9626cbcb8d4fc973beaf9478afa5f2f8c223073f6fe489789f13573659398961acb99ada3c7ab1d24
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	2	\\x8a5c2bc512a5a8524b5e963f377e87b1b30d307e5ba722d07c88b3189fdd024de19b1be3ecfd225caa9c0a49c510c5436d80b0b3b6c6e38d8e1d13205b0d520d	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\xc71686c9e62f0b4077ee5bfbcffece470561ce0b89fbdaacd1c6ce9cd913a5d89f1eda16f63d02b40489a165d28d2689dbef04f544a2f81eda0fafb785b548bac89be4ad27e11bd88803a3499c4016601c15d4beea136df5ab112a8853bfac34df03ef9900bbb31221e16ab715c3e4f2b41960ad020f0cab9f19aa76761b6915	\\x7fe100344ac61b0dcdc6ec81754098c6eed68956432cf226d6a534c55ed90c9df945e9295a983f517032182e54f1c7734e6c60010884ac2579b4449b46ecc455	\\x6f829593c66828e8f0e942584e0d59e8e94d2edf599f618b4587a7e76b2314c3c5ea3885e4eb51c1994cfe16257a32726122078306284d679f53280e7b1236b1154c998352701117ec8fe7ddb513562c53e91bdd709a78dfc1fd627fc94e0eb47af7dd3f421b471c8ee793f5e6c285f80700ef34f54da89927719e311586ddef
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	3	\\xdc9180d879cf12819b5a5e22cefcd35c4831434e64c57c1584972e04d0425abc6533b04fb1b91099202d8d60bfdfd774e0abe4c942f60d5f03da90e32222d50c	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x06bd63b3933d59d557a08c2209b065ccb251bf004580e2a53f3044e430bcd4c4830991afa6de7bb1d4f01b2ad96e74276c6dbe28a2c2bfa77d1843a9420063673ea1d76f29838c441049655e7705c4eea7a9bf3cd012c3df9b73219a079e44bced5d3c571aa96ae29d5689b8211e0fc44dc46fcfeddf9b6f29ee098d86917ce3	\\x1dcdcfa3a4fb6c712ea561f186a1fb0f03ff852d7e4bf09b0619a0560dd89fc18de14bf255d27cb3e9c9b8b041d0034d2e46ff35b5a7f7aa3e70a22d78c22af6	\\x5227c3e42797e4346a545b1f460eb14cbc6892e83f32f597f18234e9d3c8ce249efd570aa7329faae3581e47436d20336e61eeb43b77fc56652b46ed755d883f862a9171c27fb83a4e5751f45acdddab1fa9c94332e2c77193d0d2acdc9800b04835fab9efc4863005ca290057226d39d72b8622e3b89e990378eab19331b91d
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	4	\\x872c405a7010636ce6df47646d3519e2e840f016c43b2a50af3a5116612413b8d82ccb0a81a630651672a294e79bfb0b450d263c96d9c20bc3eb7c08f958840a	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x0487eaa3855852f43818f83f162912e32302747bf356982e03c9669f90df73a9a149b53a5c6e355ff771f9ecbcee4cccab6dd0f453929fb095e6abf7ece22b3cf25f148a4f770f28d58b11f492c08e9edb2b5b23964924d69e249f3f32af30bd39f92e2c02564c5d643017b84b58835f3bce94f8aaa201b922e451fc7d2c4dde	\\xaf1454007589e3f459da40111a844cc8de4cd1aa8140b8123f176eb4ce49ab10f47b1a681cc0de88de58db600deee2460d4ee2e30e567d19150fbf313403bcd6	\\x8355152d5d6ce7393247c9f10b733fa392e7b21761f2a5e70518e0debdcacefe1b8d6a5f3f072bb5dccc689933740afe9cb8c44eaf1aea1fa9699b2d00cb2506eb5d5d10b735c3e796fb8ce7ef3d0ab709207700c4f0ea4753cb9c5df8dcacc7eaa583a71145064cbe80cb44d961c00687e264a5855d97455297ba8e4b4ad672
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	5	\\x7a7b1cd6a13ad46f249defd49fe10ad3a6dec792489bae95c29d8ecc9ca15b118d1d2feca691083a801fcd5fe59b786495979e8917ea2adab1c29c0e193cd001	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x2e7bd00b49fa40222123e2ec0627b7bd72ed22daf462bebaad9c4e15f3f7440460a58b331ab470692138f7d7bd6e60dc156384b3442be9720c39753d72918106b37337466dcd90900ccb3692a9ff9bda001636d173826cefb048ca772e8206f18ccefead6c22921702389e42f7418ec9b54289f634bfe6f2590b0b567710d580	\\x135857e4354a72022b1cca3ca343a2f9beeb685af73cfd087bf3e87d8a3c41263779485d4d34c215fe0ba02bf39a7f020e5ccb69cbb3651987323ded706ca7ae	\\x3e374e9c856939101d91bd034ff6212b38b60892f4ddf0d78658001b67d81e24f4c7aa80821c4a8e0faeaf10bd3537014b70a32a6b489d997f920473dee056c37188031d63b0ab9fff19ae1fd8de44450e672a8922165dc39ea6e264802d030f83f705532884ed098dbb9bb6cc45b3b48fe77ff2f9e2a5d49554f2fd0b242c21
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	6	\\xdc49fcf0d5025a71597b6a511e5c89450f879605085778016341c61610aefce26800e0893c14f148c650a552e9e9b5476e519cbc3836e793e0f8ad064bb4ca0b	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x556a8c732434a04df8b165bcc4f9a85d8b925130b063be4185f6ec8a79913247286eb743d000ef2f6752afb0c5d981ca4c33369e335f149b73f69e1665ab20b8a04f123ec189eeddd68912d56b9a8a74d26d2dcdbaad992c5ccff77abbbc1138fd433aec40c820e37b3114f169d88261fc677c13378d6d94a5850bf55c882911	\\xb80badd4391e8531422e731639e48995ca2a39b075d5da81fe8eca43108856da8771b7c1ab569e35b0a0302f65787c24c5dc97fd2c0c2dfcc0ba769e07b800b0	\\xb25650e63a984bd71831632fc0ec04b1817316ffe9ed94b2a584014d23358f723ee78288ed222e91a61e0ad27640e9685099d1ea5c6953b197227e859625e3e144350bbc49237a68ad4e0eda2f398e0172502e7ffc6bed199517bebb106cfe0bd42fe07ac7c3fd194ebe7b5791b11132ba4a25355c60f54f1a39ed5b1d3f8d42
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	7	\\xa05b109b877452ca3b0f7db358667f2b715d31c605bd5c32e437f55dc1bf442a5e63dbd1d396bde26a3d365ee84f269d25b51f860d7b15d0892cfaf0259a980b	\\x28aebf96d858e7201c6652abe628f3d3afe4cf4e93c04e84af2b2cb077fa72c0b37fdf7c0e970ccac4ef3c6c345962a26a0a219987102c39aa3e9b1e19567332	\\x58098020d938f246f5e4e57fbe118b1364f97d62b17953effdefec11a8d8ced5a9aaa5e247fc91c4b2921a620f469e5b4611cd8e44d7ecbeee0e2862349805d0e1759237faa34794d8636d9e4ffa5cefd7ad78e827e9be68231ead9a8f6df20ed2a8d30f90e652264a8992923231ad20e1b45e2ba42c6a72036b6e6b44250da3	\\xdec52c2425641bccba2a3f183a52c0384a0d000e7f0c66c8ae54b30f0cb292f9cdd5ff93195ef7494dd214600d3615ac460db8a09e4efe4dbc59148bb94e5ee5	\\x142785ef07943e4f7451885d1e6ea0e63ab44fc628b69aa49f4933e9993f60d19c25640ac9d6290b434d331a6f65bd242ae1f7a2d0aca169045fc740ca24a6b4ebab3e25eb7817c3ae725c4f2757343337e669497939a468a206e2db3cebe746cec0798d5adec7e659e1cdd8c1ab8e8275eebd5a491f9f231b62aa730498ed37
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	8	\\x85666caa7ad36e9b6307599dfeb8dc64af069dcc734861bbb379dd4f2080531e4cf4146d6db2b334a44187e69d5aa4877945d1b0e2fa645a4ae844a747d0a005	\\x28aebf96d858e7201c6652abe628f3d3afe4cf4e93c04e84af2b2cb077fa72c0b37fdf7c0e970ccac4ef3c6c345962a26a0a219987102c39aa3e9b1e19567332	\\xa1d1c2ae79a2292483ff73a8a930d001f375ec4ab9e43d83f7ccb1f8e7f3503577bd6ddd3385ee846c47aad368f127e4c85bbc7e00971fffd887d93abeb1bbd7483e315dbc6a6187556e3f0551178fa2389fac6da971593dd7190f511edd455be78028ac0d79d652ef3cc6049c67bfc4eb76b872fae0a2cea7b0efb9bdf13369	\\xf77ffa85f64f605676e23212215fb551b74a8f0b334f64f7fdc9d900149945240f725be338ff2c55f678609bfc23ca9af18efce9e74188977771035fca8cbc03	\\x25220873588c164fd533848787c1c077671ff3f6e937e733bce914374cdb3938f553e7617a61d55c3851d0dbc74368202cf139d591c6267909d76728bc79a866f480733b3c90cd1fc2eaab4ceb9f74fcd4f0e219303148723bd26382b3663f02f91fe1e6c5d999d9a38bef9af57e4d687302952f24569e090db6fb1df8138585
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	9	\\x3195f304bbc1826bff9cdbd1b498bd22df8a42b407f20791f0db2a45a9ae9f0595b80d20663078cd6b792309d36bcc0cba48f7fe80b5cd695136aea8258d4500	\\x28aebf96d858e7201c6652abe628f3d3afe4cf4e93c04e84af2b2cb077fa72c0b37fdf7c0e970ccac4ef3c6c345962a26a0a219987102c39aa3e9b1e19567332	\\x56b1fea6c95f43388aef1650ac2021e6ac982bb37ba8b1c8165881770c318674c6a2eb7ccb4f60d1c1998f93c57887ef5aeebaea24a399765714afcd739e2e0a3b1ef6c614874a72bf0758b7940c00b21820292906a5493c869af35ad15a2f9495741e5fb1ac5bae9fe1b6b55a48a4d08e083fb8772d454243653221a652c542	\\x55bd7ec9a4bf8416427771123cfe5bb8565a023acfccbe8b20e6ae1ef7642423ff27555ba8ff4fefb47b14e347c77d96229cbd275708391720aface967f68852	\\x71ca73d5c86005c14b93daaa5f5480df3643dcb55583fdccc5f1d5553d0d776976d1dc81fcc3e099fe9a3d944de42469d659e61d12015771f4cfe62e20fc3f50f84ce57597e44569501ee000c3158425fbab0d07b8aa5d086b181aa76dad9e0ec3c60cc034e641c150e755f1745d5fb5ef492760c472abb70d8f87a667721c10
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	10	\\x11ce46a9229ef8eb08aa749ded5ecc3946eb46be295d54ddb6d4ec465e5a43526e4bd2e36837a174d479cd3c2116acd1dbf59ae75f894aa282152b802d955d01	\\x28aebf96d858e7201c6652abe628f3d3afe4cf4e93c04e84af2b2cb077fa72c0b37fdf7c0e970ccac4ef3c6c345962a26a0a219987102c39aa3e9b1e19567332	\\x8397b0b3b15396e01a3ac7cf57c4209ef26b7544dfb15a4536f4f080c3e7cfcfd0a97a1c809b64ceec8773907450523f285aa7e8f6ee314f2fda85b1e061cad661d2d68527db7660d09fcaabfc42a0f395e7f4b0e21ae3b1a21df8d03bd35d10b314f86a3832da539767a3a5a3920190e69d653a1bb132f38eb29dab7b485f4e	\\xa5a05f2bb813275a281e976f8a06f20521529938a878d8ba172a446324084fe3aec95e6a65039983c5dd136dbcc109f5b1e6077dbe213cd490a390b31444eeeb	\\xbdbf5df770c0357241fb35e856ae360d8832f1a19b852c9cabee35fefc6b59faa1a1c92003775e67dcfea2ae1d66a06169a687ea3b9b4655807c68c2b9f4c71367723023a0e7d17f788ee8ab17746d00dc21c825ea6931d284baacee8e00a24863c688aecf439bda6d4ee9f121a7af7850497c216caeeb10c978c68aa71ff1f0
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x2ecb976d4064c289b2f7a96bc647d33957d7861b85c817c3ec0925dead11691e6b77fd057dc239707028fa4f344924b8f85a5bbd3c6fa236bb73d41678fcf8d3	\\xe95c47c238eb641e72ad7be10fdd99c3e467dfc9dbcb0470a77ad3d00c54e05a	\\xc3a6f2de12aceab39970981b717140845ab78b783c1b803ea7289ae50729a5eedbdc9f253ed49e612d8b48b9369b3d3457b8e2cf70be1c66e821161ea571ccfa
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
\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	payto://x-taler-bank/localhost/testuser-N5IcqiBv	0	1000000	1581718303000000	1800051104000000
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
1	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	2	10	0	payto://x-taler-bank/localhost/testuser-N5IcqiBv	account-1	1579299103000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x2901ebc7bd8584fa784b8bff8e689e9415af46da7a760f80cd228395bc9094e51649c2d33f3cead238b58082df7bdc59060287162a450a6a4470d49231858432	\\xb9cf82166e19308568ec964e4d77e2c2ee5b1b2efb1c32b0231e50a05910035a1ecf4d2e9b823351083f822612286acd2aaa0815cb822ad3332032d9f6797cea	\\x0533346e38d87a974fe29f5ccb7cb1437f871b9a0744bb570b53aef83d9da4367325139adcbd9f5274b387f53c6a09fbb912c2621ccf6ebb7c3ac1d53adc16fc66235e3b484f3f6c33a6e9123125dd42d275b1c4122a3312c4e0660e9d3030dc39926c3333ff7f569487f4c0d0c04635a01df2b717ebba800888946743e6ad70	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\x5abfdd2df76f35b326f59cfdc25c4e45408e092dfb5e1f199edde8982060644a310b462b59da39fd278bfcfed4185432d27e66c4d73cdb45aaec32b6e5d4e10c	1579299104000000	8	5000000
2	\\xbfe9260499d25d265f83c319a8ad1b46967b3837c36abcd6bbd31b34737712546afb08ed39e5718eded6049fa639f17c0965e3db28c1de1f58501928dc0a0b9d	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\xc6c4025ffd5aaf133ecadbb9bc03eff4a20baa59c1789b2df7f9be954f9d12204fc12b84b17459d076fe4c7be3fa195d3c649fa3e930bf95d14476803a8536323baf5f4b5ac7fb673fedf17418d2fb744063db0e5b7f4d9611463f82a938af7f533d57dfbb66a2e1e55fefe1b140b769201d9cdcc796d2b2b8fe4fd3bd175b83	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\xdc10d35c4d30700b934168d719ac1da3737b3eaa396f0e4b7e544df0c45317a2d7358de1080f516a7c5af50d92e5bb9041f28c62a7eda340719ae8eba79c1c0e	1579299104000000	0	11000000
3	\\xa05ec3a7b23fc55569113d3f125f7291105e152dd1b797088f836cd521d6d5e54d43aa197feb59b18e049a8e520533bfc29ae65e9437abd46cac6c88b49d9f83	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x3bf8f15030bc18e5354a8424bef6b77fbf4c57bfab3434f2bc1d6a5b52a16a173552a18cf8e9db9ca0d95ffc97cbbbe4dd0a6c20927b9503d6d41712267b4b40c6f2cbdd19b50e090f535ba89439967f3aead6b38f5a8a1d4e70164d8b266c249991354174a312caf8bdbde230be60f3dfb0083bba8a2b575c1726a9c31c576f	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\xbf12c90302c5a2b30a5760dbbcc2ebe9819e2aa802efdf6ecfd2e0ce88b25f8d0a9511bc9ed6f16c517fb0265e613cf5a107dc71c0395414dd94c3630a1fe706	1579299104000000	0	11000000
4	\\x65b505e2c80c9eaae98c0a06178f158397754967479f56bee27557effd6b6897876564b18550b5b9f8496242b93632ed4164d0877c3602b277fbb1e786dfbc29	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\xb9e293cf44a7b67f93a5c4c6ecdc3186bcef7567332e5df28e3bc149650bc66e6a33c8c058f037c3f654bb290bca3cd43f2c7b3a4d6098e40286e327182c70f1a3a4ceb7320c463e53452a6db19b3f43d949cc273bccc4a98931309a4db82b6cd52230cc966e285d74c1e2b6eba2ea5370ca0738cad8d45c4f3434263ee867b5	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\xd2407f06b37c109dcb8bb4ed7d10119d8037c058e3e3d382a9c85e991eab41a987c021c70a79e021a0fc50ba388d068dbfa1944bbb8a6bc6bb57508abb44550a	1579299104000000	0	11000000
5	\\x5b8af6ac420c23fc8571ef04ebd3a4ec761b5396295ed0fd7825dcf8c2712c4f1a3aa2bbeb16a04c0ac87b2c10844588f0420259c3d131a409411deb85761311	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x4dbe35922a1bd3e17c43883646608f90062f8d3e5f1300df193829e0a7efa55233c6b08d89b3f439c9c847aa252651920d88b97708fba95ec4c24d90eaf7e90407ea6edcbb0b5c8c6f24b429b7d7a5e7c07f7e561552279d94908954efd0da19fdc69c8a6c7b5e3722e18d289cceeeb98b9d251860febed7e51cd640f5149ac0	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\x47b63570495f4d8528f8d9a0caedb53034fd7ae74fb34777c6735106f4c665e81e160ec399d5fd0f168c53137b9fbc5cd03281426a69a893de345b14bbc49603	1579299104000000	0	11000000
6	\\x8be91e01e8fb03fc1777cd4eef296862b4dbd4af5217e58c137f5ddceef349c11b9af7d60cca367a39eb3745642aa7e0803ef11b8a011e8674e84839830e510f	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\xc288aeb2a9925dbd03f4d28cf293b4debdbb9a9c9858a19332417947d97dcb3f6b3a7d4fd131a60a7345722041a28f93a4e6f004cb3771f7808bce34f693782b0cf5d9a42da62856bb6c7dc7579d0b6320c4d01be6439287e9fbb59824740f88fbb312700ae4dc9afa419582637793cd53d65fb6860f29d84c3661f1c1a53691	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\xa658868220d8e6f9fa32a930e077fffc03a28a5a9efd3224a906f0b22a4c0df34bc7b77471b1b3bad05ff7a02d1e44e8db4efa6763b2949cbf62a39dbf081401	1579299104000000	0	11000000
7	\\x01647c5108272a7dce7cd34ede39ede31fb28c6aef4170d4e8255cb1daa7484a7648b6f83cf2682b319f842aa9f48a4e18901424a64d4bfe51a4c974c8f8dabb	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x6c4eac4e836a2afdea4635a89279d8d7de11ef368a585e8d5e48eeb675e08b0607c4c95fe7a783b253439a444a870f1d724a4c685733dbc16d44632e4874985b3bd6591accaef6bc5bfbb016a07a1db14aec8f29fb18a8a41cba5f0eee5da600ea300cfb628952a77d059e5af708bb9047576eba78acda87d0793a41f1a59e23	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\x93cda79c33b4f1027a15e41eb8ef49a887c1666b5e4a4477a3d6deffb0395a03de0d5a799ceeb77be9c1a7446da09fb5cc1d7f85385747b9ee5094958009c709	1579299104000000	0	11000000
8	\\xac73055b9c0f27d33bf06c25c7f96167dcbe7093ddf1793d6994102c7798ce7b50d369047abeafa86cb68d67ddc4ac8afe3a8e03ddd52ed4d760c16d218d6f54	\\x28aebf96d858e7201c6652abe628f3d3afe4cf4e93c04e84af2b2cb077fa72c0b37fdf7c0e970ccac4ef3c6c345962a26a0a219987102c39aa3e9b1e19567332	\\x053ddd05febc7ed4e5ae9578369d84415f867f185f2b838c4f0d97072434d8abab135576864a6dbc7f50214dc0728438788e7e83de203f03943f53e21a478effa6d030a4454e1747fd6200a63c36fc608d76b123dbdfc979ee6f099fb11865bc4d9a9f3ff45d29dce067ba4121d16293a895a4bb2ee9c4351cffd80033a46947	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\xf1ff10272ce9ed6025e9991602a1f423e47005b3683b5ffe95a835c377d56767db6b62f9881de326393c1442c6113a5b6059dbf891a473493922fa73d83be20b	1579299104000000	0	2000000
9	\\xa7ba428ccf842052656caf26366ea076437f2ea5e0dd2cdf5482b63660c45944845fa278bcefa288cfc3400cb18edb17aa32f9b70be05a25ab1a4409a8e5f35e	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x2a9da5eab2326aed3b7db23eaab5b63cbfe9b9552ca84360ea8363575154d17241a1d4979ea03a607b418a87c67ff0377affe9eb5415196a1d3e45c8eab4caae21d71f21183e65bf4f4cc937bf4e2d0a8233eb23e1f5debf704cbb013d8950a0d59e643f964dbfea9d112131b6ad527bc1c12012db12aefb183320e853676624	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\xd4d12807e4cf5e815eb402a7f6bc5ee320ed66dcd0ac47f5bd96623142ebf843fd09e106c2ddd5c699b4a84dd72db3c21c7416f4c6807e33b11a9cf78018ad07	1579299104000000	0	11000000
10	\\xfabce0a20fcde06d230b3f67d65169e95a19ca3994058bbe3e1597aa26e2a4c5ad0f641d4d2b46e7ebc1e6b32fc99f96786cf2bdc04ab7899ef7f51fe1dc2eb8	\\x28aebf96d858e7201c6652abe628f3d3afe4cf4e93c04e84af2b2cb077fa72c0b37fdf7c0e970ccac4ef3c6c345962a26a0a219987102c39aa3e9b1e19567332	\\x2d7725fcd7d3cb58fd23c5dab252903837d5c260f8d4393192f850ed7bf85a86413c2a0a613a0d84d9449afa565bbd0c5f4d27e6ab1b7de7062bc77a593fae9642077408bf357742e12953a2728c748f0c421c0844118126a694b9aa3cd22c7e56965b1c87976b940f23bff240df33f0a58e7bf20b6902502dab430eb5fb26c0	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\xcb16148b2bed3fcce5f41736458d342bed6bf3bcd79a462b6a59b2de6234dba7c766eec47eed3c7a5f5f4ef00c58c345269e122255d559679771342421bb8703	1579299104000000	0	2000000
11	\\x1e6b832b138e0d26d8974f9043b6969c5d12caba66d05c903eca7a26e396ba2c63a64f9c3c38ffd02f70b92fd2447543e5c5996ebef8a7c23c4541d91628ce6d	\\xeb4aa1c8a3e84ce36d04e7f7cd4ec72ec04eac3b89d1102fe6052d0752665777dffd7ceae1d76986cfde13896cd5181c4afdb936311fe278f8b66cbf0cf6df17	\\x7685e9cd682850fed43a95d06132a0dc40227f640da6278cf7e9eb700874db7958465de9537030713c43c77fa303df7f7a027f64be5e82fcd22415ef5b5a357e70dbed3b0cce179c5fe4321041c9f9220843c69da87c2ee7c79b7297ed2afc1786829a4b17e95e306edb8da4f6bb8a033e762acfd761c1a241616abb36bbd163	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\x6607aaee340e342a894886ca628a3391bee56fd0a27513ebed7c59af427c57efc70c552a1402bc5e73c576b6dd7b07b16600fc870fef63179f81de8f1160760c	1579299104000000	0	11000000
12	\\x3b57a8d1fa50811c876dea1b48cb17ef947088939a22d976e333bd2af3cdc6b90cce3af3228d8c0b38be3ab2ac09f8f1f17dfd97e929f2e935ad25db339ff37b	\\xe4f111e3909876e4337dc0d1083141ae8e0817937cd476137c1bd405b7ff63b7a1a09fa46ebb1cc051c1b4de6c82e0bdf4375bca038f4aaf3c52f1e81b15e488	\\x531eb71e3d34cdf7e2ec9bef4d4bd9a475af357975944a99fdb3cd736958d8a1158a9df96d2fbd1ac7ea00461b1f3976c7bb704861a05764f18c1601e56c0a2b4efd4baaca665722d1df438a73f1a5967c92c0d47f4c1170b7614c8f1bf63052cbba460c5075508afd598d533c3a692f14dd4282942e9bbc7d3a7db6bdbdb456	\\x0193296fae201a922382ca463aaf8ca01ea27fe51fa03a5787729cc5851ba883	\\xc13be0ca47499dc96a5568a1a1b3fe1549e81f87f0be079995eae63ff0b2ac6295772a7f13d174c3b6dcde3c80fff371152259d8987a334a067f54e105f8cc07	1579299104000000	1	2000000
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

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 2, true);


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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 10, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 10, true);


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

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 1, true);


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

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 1, true);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 12, true);


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

