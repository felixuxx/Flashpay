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
auditor-0001	2019-12-31 00:00:10.96057+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:17.911571+01	f	11	1
2	TESTKUDOS:10	AKRR6WNQN1F14DSH9ZBFRT67XGKKCBADRVW4JAQ739J6BQTJPAQ0	2019-12-31 00:00:18.005063+01	f	2	11
3	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:20.970347+01	f	12	1
4	TESTKUDOS:18	3S3NTBS63QMQ62J402JTEJ4SCBVX9XBGY9DHNQ0M5AJWXJ9GSQBG	2019-12-31 00:00:21.056878+01	f	2	12
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
\\xd2edc4e40daed8637e70e4a18ce45c3b827ab46c6d613dd4b82a3c33bc8c5b435b1c89010b4606e4240dbc9e4a44b4b5891952cbe3c45cde0948c8495f6c8c43	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1578351603000000	1640818803000000	1672354803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a462de35e8b908669cf386b510422335126e42b90b6f5ccca5347248373f4e2138b881e995f3ccaab294b00250bc2f956553d09a3a8454b8c8fb59a05c6463d	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578351303000000	1578956103000000	1641423303000000	1672959303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17e5bcdaebe0c9b3208a4fc302c2b3ff23edf0acdb2c81886ae5d52e2bde569917c5e71b1f0ce1222e34cf502bb70c2a9b30887e779f78ee1b730e5e2b111635	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578955803000000	1579560603000000	1642027803000000	1673563803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x35feb2937bdd4f70fc446e6ba3342388d61ecd1821b1d512b391001136ecc9dc1b9e0b70904950a29098abd7f623e28c18cd6d819c1f36c27be44cab4abccf83	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1579560303000000	1580165103000000	1642632303000000	1674168303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x602b9a8aec9401b2113b0b5ff53af0c85e9596da76cf008d7baabae821666eec84bc0bde0476be051897b1f17b866dae938387512418ac92a30b693a4e246203	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580164803000000	1580769603000000	1643236803000000	1674772803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd98135fd2d26907cbb569029f68a3a3c4c9a3b940241037af508ae55002d4834e4869cd42106fcad326efbfaed16fbff2b1b9f59304854de42943dabf34b0a6a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580769303000000	1581374103000000	1643841303000000	1675377303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b935d9029483138935479f52a7d3ae6e3f856c42dd2713a0fa5c7267a8ec4340403ed62c2fbdd0aae27c72724bd6e14849aca9bf6b75a15970c3ec32d177167	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581373803000000	1581978603000000	1644445803000000	1675981803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1331a9b7f1b9905278b16bebba7ab77c2849e5510fb942b3e041b955c61d12eeaabe24bdcae6a1c11ec1e21a53ac67fe0ac7d2a01e6af4cb8a1997f989838437	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581978303000000	1582583103000000	1645050303000000	1676586303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc8ce7e07515f58649e9dbaf05315d8ef4a97c1abff0ff454a6b99cf4314f127a8d19bc80522ef725a3b2aae9b2b08a560151b84dc236c8c3fedf16dc91e8770	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1582582803000000	1583187603000000	1645654803000000	1677190803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf60d1045cf59e3538e9b8f613ba547c8b4fa9a843c6ea06c9eb2fe97cb1d083553d6a29ba76b36012d274454ead3a01eeb48d8a732f868fc9e4262fd423018a1	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583187303000000	1583792103000000	1646259303000000	1677795303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbdbab643175a7df7a7ca6de339a3982d29f2490bd2391263088cf1eca837c90371409cbd2e4d16e1f634b7a8299804ad97970fa2d37deee43a6df43bca8c043d	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583791803000000	1584396603000000	1646863803000000	1678399803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x441c50260a6bdccdf3f104d857c8eae8ede41f7e0628f032be232d5e7d02dc9b0ce603ad83b58791afc42db122ff62bd4fcfdf0903971bdbbe6bb1c5d9ffa7cd	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1584396303000000	1585001103000000	1647468303000000	1679004303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x65e04647a96053abc5390124f0245abd44e16cd29e76a4ff10209079c392c2a99c36ec2c0a8acaccb8737a05b75e06c9949607b03a457208121fd5f4db554640	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585000803000000	1585605603000000	1648072803000000	1679608803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x21d4e0be78b2e0aa11e0fb3a57a5a7d5695b6f951384b5bf623f71bc80e8aefab25abbca0cbbb06b7fa467d95b11c42ed8e9ce9e1350e9d5f6547f6d6e4f0e04	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585605303000000	1586210103000000	1648677303000000	1680213303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7dc224f2f7e285a067fe4afd1c93bd9bd3078d2049841f3bfa0dedc6c50c42ce31e27ad60c9cd2528be9fd7573785b0516ca61a267140bbf4bdd6e47bb80ea68	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586209803000000	1586814603000000	1649281803000000	1680817803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca5e208fd05bc8924addeb2a953cd7bc60c5c96255e6d85ce56eb21de0da94a3db910faa74a357c6432fe0205c804e282d9ab2b17ad10cddaf19e2dcf94bee38	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586814303000000	1587419103000000	1649886303000000	1681422303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6483988de2ceeaa498cac59a262b313fc2d6f607a8fd3830a53a8161335e3aced15768979a3275df8e916ed836f8a6cbe4b090f8a1762aba003cb4df8dae4ef	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1587418803000000	1588023603000000	1650490803000000	1682026803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e7bf849cf09a6c2af156d663c4aedc01f312a88f9d82de1797a1b52ebcdc2203f6d883576d84b43f2e3c8f955422265c58a0ddd192550642a2f502fe9f3570a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588023303000000	1588628103000000	1651095303000000	1682631303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a63e4e6d8cdb0cfe3e2c483a63a7f89bb8cc7ddbca0749d1e56017cd3a06a5583741bd40e4d4600bf638b2fefd1bb2b6a984c44ba070dc8bb57d3e672046637	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588627803000000	1589232603000000	1651699803000000	1683235803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9d68ad94aac9130d3f4e07e71bf53378f16f6f7d41cba568abe72e844880fdb7ef0e08aaf3c57ee2337aa7a3b7620ea023129bd2716a482e55f452d2e51a6d6	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589232303000000	1589837103000000	1652304303000000	1683840303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca012c13b416988180daad0f7a657f990584126db7accb1f9fefe246727f56817be6d7560f2777976202f7d5b85683876bdea1c63fad3ada212514677c1959cc	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589836803000000	1590441603000000	1652908803000000	1684444803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78d3a8fa576b463a081505cd22efe11fd150a53bfce308d8e80b8a51f513f0066972475be1afb5dd91ba94e8838d9527189cd00474d002f789c2291778d46f96	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1590441303000000	1591046103000000	1653513303000000	1685049303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe744d6348813d53c214d75f09bc629cb572e5c6f43296419d7ed9c6a140fc893cc7b03ca227af04a3e3d97f9d6156ce2a6d32fc7db126954041c3f2b7d7a977	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591045803000000	1591650603000000	1654117803000000	1685653803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7a3c92d6aa7f348e0d8c6d0886dc18e4e6ac3a8008f601abf0c57adbc108696eeaf491fa570f83b28b2fa2a292691e3251c4e75b0b1e0f7157a34b2c18d2ccc	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591650303000000	1592255103000000	1654722303000000	1686258303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd6fa117d29973ef47d5773e8d76e9bfb9bd8e88a4596ff29b37613b479199fe72d3bc399fa5c8fd27140797455ceabdfed9e9990f74f695cbb1aa82f5026bb65	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592254803000000	1592859603000000	1655326803000000	1686862803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x90f035b04bd0044dcec599e372d4b7324e20a15ba9fdd9725823a4d8a5e16cc2332401cfed52c5f212134a451ecf372a4c63eb02944839681d701032996007c7	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592859303000000	1593464103000000	1655931303000000	1687467303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f3f3b0d829d9d326e0774afe94156b111e8cbc3882ac569fa599f67d3b677d41783f06e9694dfab610aa476aa31738d042f0e72b03c3d5e959e9a9ac83012f9	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1593463803000000	1594068603000000	1656535803000000	1688071803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x530a64f3cbc77eddcc2e9bb42c622602c71faa8ca792446a0ba6a51056d76edbeb3d262ed3baac82808a0c3cf821df28b06e944fc5e2cebd002b1ce2615d17d0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594068303000000	1594673103000000	1657140303000000	1688676303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x93d10928250368c833a5cbca4b3668febb1fe8b85d0c4eafcaa3b33504d8169d4ed0b37a24f97044f3fabecfd1a1c7dc82c4d97a9e9c04f99fa0246b263bd399	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594672803000000	1595277603000000	1657744803000000	1689280803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x129fc4512d091155d2bd9c708209b3575458c52eb462f0078c889e0fad9b7a160ff7ebd73dbe1597a25be2515e40211907848f2fd442a51cfc3909ccb2bdfe97	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595277303000000	1595882103000000	1658349303000000	1689885303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2dd0d2bf16e9a9509167d62d4eced4aec7477534dc9d6900988c2ebef7f6e424f9fca9af7bcde6edf7131d3f05b66fd48592e657776ddc01dfbc6faff3e7abea	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595881803000000	1596486603000000	1658953803000000	1690489803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xada296a483638128570155dfbfe60d1a096a55663b43e9f480ffa4bf03af855f064932617eb407a33f5b4b952f41f045e559aa527dbc2215cb8437f6407aab9e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1596486303000000	1597091103000000	1659558303000000	1691094303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3216cd79c74dc643752e155f9c72274271a033c6569b77c730e73f81f8afe6e1a5d99f5526d6cb11bb6e4cfe1c8c715b307b664316ad9905e65b105780085cf	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1597090803000000	1597695603000000	1660162803000000	1691698803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa804b3cea4b878309c41e49a9bd755f08598bbd71a0785dc267717eaa40ac13fff6cad9114a08e5668514d6ced03dbc6dc7e0b0ca2bac2748893e99dc32a8b47	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1578351603000000	1640818803000000	1672354803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaa9274eb903575b9ef831c918aed1332b826e7c84012fb07d6aa53418c080e9371c7673b55c7a1d883e7d4bb5c085086565b621c969c780e6da1ff9bdb3904e9	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578351303000000	1578956103000000	1641423303000000	1672959303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9321c35d686d4fc92fe8c0c1ad2c375ae854b36048813f589c4dc133788e2bccd2c465fa47689fc2315bc43567a49f0f155e8ef0b4a5b1a1acdc383a92057cb2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578955803000000	1579560603000000	1642027803000000	1673563803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa2c8ce1f094747befbe01ce454845cdea5b0df9a66ed9d43e4ac95982e4e60a5d5b62615aaddad469c29678c534229436ad02a4c083317b981e1cac6666bba40	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1579560303000000	1580165103000000	1642632303000000	1674168303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1635aa5f65f58458f90fc40d2850ad229171f0aefc8d5b1dd05862e53694dcd0556f73c1f4087a040795f4b2c4a2ffe3bd8ac197976e343bf7cef4c8b6d8ccf2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580164803000000	1580769603000000	1643236803000000	1674772803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9c947e0f6b78b9be3db8a1a463c0bbbb28c4a2cf646b74d10fec00aac755a6328c7e3915be2b38fe6b78e41de76b9bd179a1597f1d087de1437a21fc696ead0a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580769303000000	1581374103000000	1643841303000000	1675377303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc4aa24942e84c90212e491750870c9404546ade883ff2853519ac948afed38fc5292dafeb52d6b701a683288be803c97deab2988ce4490c87aff3cb55ad074f7	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581373803000000	1581978603000000	1644445803000000	1675981803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe889c072e725296ca47310d74052803610bbb641a1011134cbbd8afde40e9e94691fd87d5909b82f53d322eebd97499b1064fc94fa0a07002d4a510c9ebe4d5a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581978303000000	1582583103000000	1645050303000000	1676586303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1ebca3c5b6928d3f4b1e9a8b645a7633a40ff594b15785fba73df2382f9fe7a52c74281f941776e06ea33da9c5f3f15a20faf90afda151fbddc8bb8be9590c4f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1582582803000000	1583187603000000	1645654803000000	1677190803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x851cae33b94ff9945fb4ba839353e758632ff6d21a457ea51700246d8dc9d99350d10538edc95aafcf2990531e6afe79ac7d585ba7563d1bbf77998b518debaf	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583187303000000	1583792103000000	1646259303000000	1677795303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3e468730cf45e2db671a6e2c3b252028cf4a8d949486a49603bff697f13afbf5b90cc4c038663bb59868234d02bfba97f02deed700c855b3070be6082cb60077	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583791803000000	1584396603000000	1646863803000000	1678399803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x94d43767c3db102f066eae459b4bd4e47859e856f4a5389494f7e035b3215815dd52ad8eae7437fbf9b3e06352e3f903e9ddcacf5424e8e1fd963fddaa9b0a33	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1584396303000000	1585001103000000	1647468303000000	1679004303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x412f1859550f5a83ac614bcf63c4a92c5b842afe34152cba90ecab4ec43e5969a39f84957c3e57f8b49d6b67805a2f2649ba668f3571cfad8ab199da8170751c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585000803000000	1585605603000000	1648072803000000	1679608803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7ac23bc9bf4d493a59164be905dc82a6c8729d81c75c5897a5fbe3678674ed0b63029b2dd47dfa5940a364fcfadf091f3ee1ff56e619e988c89c631294a57a28	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585605303000000	1586210103000000	1648677303000000	1680213303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x22e404ba897a5158260f02e923621409d5de679ae7301066bf26ae392f059a44ee633522a37822b1e647f31ced72efb9e62e3a8926086a6b4c6ee72d26ca6bad	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586209803000000	1586814603000000	1649281803000000	1680817803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5702df4855dbd2b0bead304b56b31d01b2b4bdbb1f30445f65d2608523ee8ae6988304712db4fa9c9c446d1113ba7798ca0668b4ef0e8a107171b834a1ad6fff	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586814303000000	1587419103000000	1649886303000000	1681422303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1db9740c18c3f3abe47343f35dc7ab166c130f22ad513d345fa7cef64e83af3edf3a7920630d72cef395448c7f333592a1e80166e555e7ac9aa73ae09faa0c47	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1587418803000000	1588023603000000	1650490803000000	1682026803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0eda252f3be7d5eba3a90d2b688ab2cc0b65d9421083fcf49aba85dfde1bcb9e5d9ebe949cb0d205d2918a2b2346a77df89f559d634abf00a3d1efbff3c20459	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588023303000000	1588628103000000	1651095303000000	1682631303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf24b74825daa468d32b680f421f9dbb1918a2145c081c024e896a8f4e206962c59e6ca831be7e1e7a5e49927104a03b7e813f37bb07e18355f1efe22aeef0fa5	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588627803000000	1589232603000000	1651699803000000	1683235803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x925a73d0be6327f55c987d17a8f8a5009830bba2c091de89616491fc0ab9cdf9fc8c98a2f188a4f4e979da9ded1c71b3636368d82c5408c85f4c3d4cf8a226c5	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589232303000000	1589837103000000	1652304303000000	1683840303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa18b838b821a7a8d81f21791cc8de8a4704fa04ca0952109f08aae3a67f265eac2d1b3f6197f4fd0d7e9a76a78e3b5746b463cf9c496f78cd6f8b695e658cf63	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589836803000000	1590441603000000	1652908803000000	1684444803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc76e789c1e75e87ec6c6218c1a07995b290e52cc9f2160441ef40d3523d541ce5e78e0a427930f3bbe361144973c15dbd1abe8e19bcf0ebc50f64b6d8ccfdfa0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1590441303000000	1591046103000000	1653513303000000	1685049303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3b3e3e53278fb1d8b95ebe52b207a90899c82e502e56543b1a67e32476a21731791abc2a2f71a51e1bb7e83a0302bb6fe90c4c27e44ce0aaea869d843ccf8cde	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591045803000000	1591650603000000	1654117803000000	1685653803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc6082d87d585aaac1ba459c8049caeeba90cf649386dd3776a597f0d60d7ccb6c8264dd835625519d18cb4035414a7160e008496a5e32a19c8b7f96836c14784	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591650303000000	1592255103000000	1654722303000000	1686258303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x437a11ebec9514224d9e19f50f4ecbfe986870ea3fd567a111cf8374d0de8aa90c9ebb256f2600aa98d1c463c5656a81db12e3cf90c47a91acc496f0d5df8edf	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592254803000000	1592859603000000	1655326803000000	1686862803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2e70fb0078d51ec8e6c7f74c3bfe6c20d42313a500ff53f51988b3b680ac7355b0e360dd1ad694ead8a6ee6d1605a6753a1f5d1953d02f3fd9f7a0bc078ced5c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592859303000000	1593464103000000	1655931303000000	1687467303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaa59e3dd7f518cc9ea4a182dec48fe1fa371948a2ef25390c7c0cc44a4025300177837e5252767ada1354134ea9a167353083bf5521ec431a6b36eab60161580	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1593463803000000	1594068603000000	1656535803000000	1688071803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3b974f19e85e0bf07391ea65e911ccdcfd43eee4be423a4e2a5011f9620bea9ba8715c9a26c332f817bcf681b6dee31ebf8b4e7acf53623321a1aa028f7ac079	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594068303000000	1594673103000000	1657140303000000	1688676303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc3e136b952145573ea4ff5bb2e13f5b570b4806f3c1927a1298d724b0c9b2ceeb51a49cf0af166005c7dc146198527d3ef0544a0250e8ba600be06f510806585	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594672803000000	1595277603000000	1657744803000000	1689280803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe79a61fa86900945ce8c5230e6bde5854b8db751a8d462708e08cd6877bd445a56ab004f9eb0d3fdf47c5cb8f2bf29215b4fe68a805263ddb98dcb2c15a114f8	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595277303000000	1595882103000000	1658349303000000	1689885303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4c3bf120448d50c554978ca4eecf7105e7d237bf052c052f9112556b8723e168072d255878821108f31ed719bf2348692438f064871bdd3f4f5364b4cc50998f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595881803000000	1596486603000000	1658953803000000	1690489803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xac76a41bbbe4e408a83a8d1877eef0ccfb2a7c63ce02bc1fcf74d9f283622467897c0d5eb50825ff7cf4c53cb0219c8afd8890f6ea81622fef9667601ce62e03	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1596486303000000	1597091103000000	1659558303000000	1691094303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x652036f6985ef78292ea9a67508c662062f8202e660b169e13dc4740d024783390b6391b8ee8e6858c7dd7e8b44719be704428287db3c2d5b2fda9d957d7b17a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1597090803000000	1597695603000000	1660162803000000	1691698803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x024eb8c53815d70be16003b1a9c804339a53c69c5813cf66d8ff1e691368dfa737baa4a874217706dfdf1e9e18d59fba7cea1d2e534abaddc68b69df090ccc9b	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1578351603000000	1640818803000000	1672354803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a8c3db73d00b00d31b44460e03b01e07d1ed643bb020e1a745561351b6530abc869ef493687dbe5f35727208b5d3ec0557b55657991ec4b0b0a72fd68c7e70e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578351303000000	1578956103000000	1641423303000000	1672959303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x08997d01ab8fa10511fc0599b099e014347442d2e3604d60fd80ac999248721866674e11d1ae2608b9b3eebb459c22bc739a9f0129e1ac7c4ce7fe2314aa6c16	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578955803000000	1579560603000000	1642027803000000	1673563803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7fc5d42874a49b1438e0dba96f86ef2c54ef0619ba334933cca8e94e5d346b42d80ec7f9abadea76509e62039ffe3ae766684de850c688d3d90660ba8690b85a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1579560303000000	1580165103000000	1642632303000000	1674168303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa944eb68b236c4e914751f26ecf4df7e4ebbc4e10421737963054b6f497692932299c63a1125fc5e208e0178b404ecd8c02f3a93ff575537757171e0b84748e0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580164803000000	1580769603000000	1643236803000000	1674772803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d1cafad695ccce9260b171ebbb34a4947550c8d079e9e36e432d9b64e9fe1cd2398b45e7f677c4ee21c4913ea843620db17a1b4cfe581de4bffe050db21a4b2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580769303000000	1581374103000000	1643841303000000	1675377303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x29736c347fd48f06d4bf997a70dba43f1b4565434b862be29f0610918bcf9677cd5408ff5396de9e162ca4cb9ec4c6a8bc7d0e13040502390d15fcd4ba303f62	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581373803000000	1581978603000000	1644445803000000	1675981803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76e403c04eece0252e97b49615ce9d5e3bbb03da10a835e7483ffd3c472110f22f381523e337a47fd59affe81cf9a3a79edb70f2b525fc723efcf427cffb0a1a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581978303000000	1582583103000000	1645050303000000	1676586303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3cf5ead16b4a62459b490f8aba9114b8c6e78aa69829cd7652e39870f0dc2ccf3b11ecc3afcb9775a3ec8f93b1e7fccc81ef0ca86203549f0e0367d68ac02d2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1582582803000000	1583187603000000	1645654803000000	1677190803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e505f70d961bcb3f2e82d90ab1df77a8643e9fc11d154fbe430c65872896fb66150d02a7a860f141f92313ced1f3a0984c6a2b8aa0fc544914c83a5040a9555	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583187303000000	1583792103000000	1646259303000000	1677795303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb88fa4605ad2db0854eff7de456c90f0464a778d3c65816d88507d8df803d280a7e622ec7532b6842ab8ef25dfa72cfdb90e790065d888fc709dbba90124d88	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583791803000000	1584396603000000	1646863803000000	1678399803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3633830294a330d83bebc497d17298eccb6e7b9ded415569931c615df3bf9f781ec172c101fda70292e4e5c54d9a9fbf0b8898654abef7763de080743a407f5c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1584396303000000	1585001103000000	1647468303000000	1679004303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5aa2ed9753945bc51e7f659631015b71eefb4aa19c9f494e859a9fbbea9dfb814e67230f624c68ae6e4289d4426de6922f0d461d4458df3684a1a79028a738a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585000803000000	1585605603000000	1648072803000000	1679608803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x56b29cddfbcabfd4d56af8876a08bfd9376d83336a395e2a80e12ea2aad77d7c8c3c721c9125d061ba06f979986430fcad91d3c7c86cb68ce18fdc3ca5f635dd	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585605303000000	1586210103000000	1648677303000000	1680213303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd28bcef4c2905e124ec5c57f923d9eebfe23cec917c03cca244a2ea8f52be68f747ccc7a1e4a8c885a92cbaa7372189091a4a38e56b687a91c073154a89941b0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586209803000000	1586814603000000	1649281803000000	1680817803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x935eef4faa5288f93bf46683c5b6325408c88d87c1dc66578a86f00109accae0ea1758d0576503127ffd6d5f4c203037451713fb95eb672fa84c740188b08241	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586814303000000	1587419103000000	1649886303000000	1681422303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x275df131de9f77e990020911446a2dca405939e15e0a4a0f3231c254364bda9985b69ff7d70ebcac2f3f08b913ba3d0f20bc2576445324f1d630eb71c1327473	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1587418803000000	1588023603000000	1650490803000000	1682026803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01426bed3ba0efeed534d2a68a62d143ea80f163310c36b361bd518f506b70229dce2e3024755ee2a17a2808287fef01573af19546b60d42f904aad472a19d35	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588023303000000	1588628103000000	1651095303000000	1682631303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x052e0d8f0855034c0754f44db0b619de30e0f08e1cafce29429a5c4bab3c5c1c4e885f14a838c57dd3926678be43da1fc6da6a853145da19b2dcbdc9b38241dc	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588627803000000	1589232603000000	1651699803000000	1683235803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ef07573a029d76039e107e11a4f736ed4df991f3ec7637290bc02ddc66d7fefa0936dfa175f4a1ab2975c9f422575b7819f33b6f712e1c5c16ff718679444bf	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589232303000000	1589837103000000	1652304303000000	1683840303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x686b23354897befa65c015ea92efd2b1bb80708018ec67f6cc1996bc27ca2707df8310184f4f428e08cbe5c431710d742295da8299430688e2713256d64d0fec	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589836803000000	1590441603000000	1652908803000000	1684444803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xba66e7d2f19b97485b7b6ed81067cd74f052b7f978d1524be128798cde09233423f1986963579d3bfa192271d1b503ca96700b07c473688238c4266b4dea8332	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1590441303000000	1591046103000000	1653513303000000	1685049303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca654efdf670aeeaaad0c3394eb1b0cf7eaf7c8c001a8a4527aac4a15b07c1c49b833ca235fe1e58615060e8c53c8530660ceff75b276636105bd76f2117d467	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591045803000000	1591650603000000	1654117803000000	1685653803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6a3461b92b909868006513189f6e48f9d25c372b0bb95e4bf72fb0f27a3048ebe410da880e972c7f722decc9f452cab814a8f507995b0de73d2e8c401179000	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591650303000000	1592255103000000	1654722303000000	1686258303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2812ad232be5d1d75347b613b3da6b5d89d0c21f09219a24ba987aec8deff1c76677f4a1968159a318dc9870c855eacbedbabf0ad867a408b4734f9fc3eeeaad	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592254803000000	1592859603000000	1655326803000000	1686862803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2f6058955a8bec51f3b5751fc8424e6594929dfc96768b2fc965c6fd9371880b7e344ec1e8722502aab3144e8cbdd8c596f4fad360917a4241fd5b76dfbc86c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592859303000000	1593464103000000	1655931303000000	1687467303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x286bd3b3b85814c15c82c7de23630444a816dd66874d8f67492f0b4c73722fd7c6a66f2f1ba95d64cade25288c4a7a20b9a342d57b7c3bbf21d1f04eab553004	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1593463803000000	1594068603000000	1656535803000000	1688071803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xee26f861e1abdef143535e7b47ad97f8ac49c0a9605d2c800294c357b34ef3fe17da9c1474c64476a8b5b915cc0be5aaa7261e09f7b24c95efe6d493681b9307	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594068303000000	1594673103000000	1657140303000000	1688676303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x31b86fbb193ee9d973c445052e4f62afb479824e067303a50d9ef5226ae0c81feddc419ce6f3745ae83152342b2980cc2dffe8725e5c15040250f036b578f3dc	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594672803000000	1595277603000000	1657744803000000	1689280803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50ce82fe6c7799dbcf90ae1dfa434ef82c107373ee8b3d43c35ec2bea6bf1b2c5afba3db9804b74d7f5cb277fdd247313c762eb782c9adfb5917598807d53bf9	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595277303000000	1595882103000000	1658349303000000	1689885303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x07a9fa6b45f014d7586142d1d92ef0c4277e0327ef2f0e9cd06d22dfa363f227e11bae0248c377c09ae386a77ff8ca2a9b74a951693f5c12aa10dedbcd61ea12	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595881803000000	1596486603000000	1658953803000000	1690489803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf510024bf764fe64b81ed7b7d356d41c4fad7ef3416c72b45e06423240bf8bd8de97f7084a219c168619566a93aac3c4b44a18119e2c5a14caf3b745e8da0d1d	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1596486303000000	1597091103000000	1659558303000000	1691094303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5ff63c94c840c6293ee6e4ffa66675bf82f003252bdcffa424cef9166bfb89528c11a2a3bd64c3671f4fd91cd1285aea26d22f88eb83d5aca1e1112054a3ea7	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1597090803000000	1597695603000000	1660162803000000	1691698803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd512824dcd70069abc9e340517758f56efaca3d13ac5d73b45d787a030ad233ff0198685a305f64cd6f7d87533d65373644b4e447583f09882024d20c752c7ba	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1578351603000000	1640818803000000	1672354803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7902bb0cffd1e434af5d06339863db32237609f04c7822eec6f475ce0134293f6b803f5a51266974b6aa567fe47c0ca963f0ec31b8e8ebaf3442b942c1cf8d14	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578351303000000	1578956103000000	1641423303000000	1672959303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xceb4a6a7a82f59813a0542aa8e0b6f66ac596934738d06030eba2525658561e8088e4c2e895807ab9a5cbd48ef68ef42f77c5507aa760f41bb84c66b75a375e1	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578955803000000	1579560603000000	1642027803000000	1673563803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a128e13a216f2b31d1d8f43222ff231962480e3017b5bbdabf0f612d85c496534cc3203e426bb624b428a591d5464170974c7a32fa514f4090cc0d8581ef7f2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1579560303000000	1580165103000000	1642632303000000	1674168303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x15383835d6a58c0a61cab167e05b0189612eb908f0ac7067b094ab568aee4702a4f81b695db3b39a0c30d8129cfedadec4301cc2b4852e78c5a3571afb77c49d	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580164803000000	1580769603000000	1643236803000000	1674772803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdcc6d23021e7ef264f035cb324ac04bbbd739383dee5a067b328025353515a753055751b7496a28ffe56d06aa83686d4caafa2db6f8306f572eb50b13e2a72e0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580769303000000	1581374103000000	1643841303000000	1675377303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x76116bb3decfbf2e6d9640fe2f6420c4633072fe90e2f05e4da3da13f427c4660863d27956f9576994b7b29a1beb4c07eb278db9387c917873e03d068550e0f1	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581373803000000	1581978603000000	1644445803000000	1675981803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0bca2e51b7c6ef0b09e17a201002e9fb9eb5f90da78298d2bc5815c545e60d2bf22055da8304666320c105b2537b88dda08565f4cdd27b3ebec67b386ba15ec5	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581978303000000	1582583103000000	1645050303000000	1676586303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfc738c1ed360b1e7b2d3f8de15d25fc4533c2bf841159da179c93bb279112df0005aaae87809d4afcc65280f76fe907c9c3f2c996147e7ab14930b6830980763	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1582582803000000	1583187603000000	1645654803000000	1677190803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa6febacc4cdfbe1d8a12fd7beee6fae6c007a9334f7c2590f5e596887607f67b3068d03c62333c27ac62d5b55b24dd35d2ea16abf7ed4911a637225aecf01e3b	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583187303000000	1583792103000000	1646259303000000	1677795303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4ab71add65a3e9948294342caef355182349a111d3658253e5651c9295e2902d12a69142a4954b5bad01df5f7ad2e27e9cfc0481357338b787785f85ef7be20e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583791803000000	1584396603000000	1646863803000000	1678399803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcf5085ff040b086a05c0d59f0a88712d7b2a144364fd4239cadd6b6fb7a522202afa6244ec012af3ee93f52f6e64e4a3e84b9347f3fc8e786e6917026e2955bb	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1584396303000000	1585001103000000	1647468303000000	1679004303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4e4f52992ee2cbe3390515e6bb9e2791f93ba2cd482570c5bfd845f6bdf7deab0b3ad57b19cea69a1961140487a7509337069ef0e767355bb5274aa9e3d1c00f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585000803000000	1585605603000000	1648072803000000	1679608803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe1b0671710143140b6e884443407a214a5cb8c12ca54e642d9372a13c58f663f1d7728d3f9a0372f7080b67dce7a5369489d5d93707fe5f1c39342b19496f4f5	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585605303000000	1586210103000000	1648677303000000	1680213303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe1edd70b9f3a55873abe961e7d9296ed11e9dc81c955ca4e537804c0887caa2d43a0bc99d68c3b5bffb6b8dcb05953e117a615a9faf599ede5349e2af89f6402	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586209803000000	1586814603000000	1649281803000000	1680817803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6ad36c45a2c90347e73080090c5a0769c54bcb7a8c9fc21c82933f0f86f2fed7225bc7bca286b57faf0d40d750e0b348d7b7267af3e1be2508102b118154a74f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586814303000000	1587419103000000	1649886303000000	1681422303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x84a7af9783c286e7e1974c84864b52880de4c024db321e8844580fe45ad724f977907ef72735d0f2f16cd038af1529d69f12af7deef3f47fcdb6f06986484475	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1587418803000000	1588023603000000	1650490803000000	1682026803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa84536b274256a192f9028ecc9cf20051cbad37071fec68671dccc780cd598f8ede8132b1ff0ed72e94f479e4ad911d48ef1ae9136ddfbb06c0ba1fc93d399fe	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588023303000000	1588628103000000	1651095303000000	1682631303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c83e4065aa51d889109fc79e7df1738524ee95047e343375f4b7d752a20c200e5d352f1f11de8d71f5f50ffd258c801fec32aa846400c3910fd41cdbc13a90f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588627803000000	1589232603000000	1651699803000000	1683235803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0fe6701b16a893e54d0d5590682b2728667a9df119b060953f21f2e0f46fa14c8b972b650f216bfe74db874879c4d2c54af06b39cb6633cafb55c111f6b553f1	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589232303000000	1589837103000000	1652304303000000	1683840303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb733e2538062343a0344d0e9765836dcb73432d6a39c787cd6580b68d32e5ccfae82df1ec258adbc987280ed62fde75441923da5c3a855b24769f2f330b56363	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589836803000000	1590441603000000	1652908803000000	1684444803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x005b590e1af797aa684dfcfa00ebbf35c19e7af0dcbf8b495d0f58cae27f0f93bec8cb849cb2a39efd37c811a6bd049c2afc1ee32b1c602ac8de9d21554e174f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1590441303000000	1591046103000000	1653513303000000	1685049303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9fb77a7ba0d9c865fe727fe765291b4df277a8623a68a1916a635998e481db52a1cdcef85cb8fb2e4e14aab649713b50b48fde6b94eb706b3a48f893267e2b8a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591045803000000	1591650603000000	1654117803000000	1685653803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3b7ed03bb40e260b0946e3678c6818b0e8c6ef51f8bd6f300221466de1c85a938316fae7e02d26129fb43c63b16672340aeb9ab6b5c501705c59a39c8663dca	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591650303000000	1592255103000000	1654722303000000	1686258303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe9f67adbebcf269fdce1b0d810d9a909d8845d085c7c81f2668211940a9780bd879207c7eb8a07f4210af0783b686c65c988bc7dbba990dca2a05375d54ae625	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592254803000000	1592859603000000	1655326803000000	1686862803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x01f76a6912ad88bb1668953a23eb2dd0cdae1720d1ed72e419482a300cd946472df17300dbc447ccb93bcf517fb0d2d271345df4bedce50c782b03a7e10bdd22	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592859303000000	1593464103000000	1655931303000000	1687467303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf1d5145e23a6363189cb2838774ee79375259c5b5f4fd6bf28cbfb86e3c81bb391ba89b969d23366dc28072972c4b67482e6a5ca32b6d81fd64ea3d8780e2291	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1593463803000000	1594068603000000	1656535803000000	1688071803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2d872717e9d114a35dba2f83095802bbcf400dc4ced8f4161720e97361ee4c36bd3a4d02a584def686359bc0ce6ef826fc1725da86291baaa4c8b4928651b931	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594068303000000	1594673103000000	1657140303000000	1688676303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe092fa38460ad0a272c7d5c7edcd2e9850e45d7cd203c2fdbe82e757e1b5215683aa16f3814519982674328cef1f17557042371ac86deab6df6e58bcdf41cc64	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594672803000000	1595277603000000	1657744803000000	1689280803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xac4fcc65458d393bbc882f11e80d61c69f7c942865f8907edc4e73cdb60dd8ebf5b34e5da7b9c2cfb987bef7ced438c9b232b522b0539266c99ace3644b864b6	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595277303000000	1595882103000000	1658349303000000	1689885303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x58596dfc53389c6d25e8f9a5b5e730d3bb008bdca3cecf3f05157fadb914e76062204ed68a0029d7caacd7f980c9f3e8be0eeb2015a1972984ef99dbf1be19a0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595881803000000	1596486603000000	1658953803000000	1690489803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd1d4ff16680c9222df355df6c1e082202b9a345c33cf369a0e7fbce4f777682e221e4d78b6c89192ded2444ea1efe7ff077dccdd233b05cabcaa363816e340ca	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1596486303000000	1597091103000000	1659558303000000	1691094303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc9b1583b70cf17ccd4c074e4393e970d4caf2006481e61fcac0ce21f4939f80f950e3d290381202b770dc421dd29b269d7ddc6953884b241a388781ae7e27622	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1597090803000000	1597695603000000	1660162803000000	1691698803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf0386738936b450f771b9aa68cdf3b34d05edd2c09e1ea60b54157d95b40284c025c2e16b80910513bf56378f9e7445375c3be84d88e44f6fb9fc87dc7b8969	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1578351603000000	1640818803000000	1672354803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdb6f17fea459894e17ea78dc4548fa3224599fca59c89eb3801d00d5894febb75384d367f939ef2447dfc7bcaaf44242832ecbb3aea4d2b067351883fa5eabbd	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578351303000000	1578956103000000	1641423303000000	1672959303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfa2362e23ee73fed344157f5851ef5271d701b9df9f08e48e6b428a456a655382e7388e64ecf30b646ada3f522ec1380512c6e7d0f54b9ac11203d103166dbba	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578955803000000	1579560603000000	1642027803000000	1673563803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa4e2069238b78d5154b53d4aae70380fb80213182bf88591e5091188c301b02b67b2bfcecaaba11a97b0d8881d0084c065ed74a7064c2642705847385954948f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1579560303000000	1580165103000000	1642632303000000	1674168303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f6b1bf90208236d1ff8969f214809ff10ee78a38a315325954eb3ca397924838922a3efb7435ae2cdc6a4fd81cf22016369243163db79244359f52ed68e9739	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580164803000000	1580769603000000	1643236803000000	1674772803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe74979bffbf8cdc01b1ca824cd138326310311d18d42333ceea9dc1d339d5bb3a6a483308c987acb31dc927d7844311cb0d4ce00c9f6a2d2734451da794ad1c7	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580769303000000	1581374103000000	1643841303000000	1675377303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x65da3f2d45d615e88641894885cea9b8a5b59448a1fc473a3a83a55bc119c3ce412abb6f62f3ee77e6d92e52750e1ac5ff436a4f890fea9aa2527ccbc54c0ef3	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581373803000000	1581978603000000	1644445803000000	1675981803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x53340a0fc5acec106b3bb75ff37178ac5b02a611f5b107718ba5c1040755b1f4b4f3d2da05e2ecb51a75a24c972a38b21672cf5a6ff8e5f40b16bf8464e55d16	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581978303000000	1582583103000000	1645050303000000	1676586303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f4a0dc2729cb2e077850a713f1952b5c32540d860e0a10d3829bbf10860caa63181bb708910c6c23e835dffc5e598f52680d6d77d02fda923fda801d49294a3	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1582582803000000	1583187603000000	1645654803000000	1677190803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9819b2124d30197bc967f496e5731d8e53d0abffecd7c5eb9acd5789065bc550cff6265b8babed5ad9dd79f42b6a72c385b04fac6942f2a949cab1e3df7f081f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583187303000000	1583792103000000	1646259303000000	1677795303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc6b8ebf821ad60927f9ad19bc7ccff46276664418b33710f3bb95272ab1e8bc94a90b464578ea9cfeb971f6834e72c5a7e974f61c0d697e25a0b420a5ad248ae	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583791803000000	1584396603000000	1646863803000000	1678399803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb8c3f66c2f224c6484894614f067d1aa13fdede17129fcb84f7fc89620e048257b26915c58f28d06bb6c022831b8114a800e40c845b8f9fe7daf13a009d366d1	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1584396303000000	1585001103000000	1647468303000000	1679004303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4e8e6f0c243482c630724ae7c40856169288fb6a982bd635e81de360ae757479249f1239a0ee40941b4f364b841931014e67c1ecec03503b1b6c80ed67e44f73	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585000803000000	1585605603000000	1648072803000000	1679608803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x088c8a4ec62415c2b06e3c9be56c160a31d1d0c4ac767db5bd084670afcabf814399241491deb5de59c0b31e91e809244483a873bd301d9f44e7181f4d7be4b7	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585605303000000	1586210103000000	1648677303000000	1680213303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3117e0798529a522ed69fbe40e2d1057cfcd29483a8f2c332776d3b3c77bd38d8329bd69059e73d6b6f7b256fd7426a1b8e7f7eb5a2eee6ac7e3669fcf85b55	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586209803000000	1586814603000000	1649281803000000	1680817803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9471a92ead262756ee60af15401306cb8f8313e9071e3015caee95fcfc91370adca991b7b3671851ea7d01d891db2375ee2dbd10d7cc0f41e8c6736b1ba78790	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586814303000000	1587419103000000	1649886303000000	1681422303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd569658c9aa5429044476271658395a959bfbc2558814a80affc47a04c191821af7b21bdc98ad2ef30ef71cc0a6e8155b7ebe4cfcb6a0cc22db38eb867667d8e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1587418803000000	1588023603000000	1650490803000000	1682026803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x183427329c4cc9b77a202bd53e17317f4c817d54bc5f53ff18eb154753aa1d502c05e3d140ba11e775d17422376afb69fa8dcf4e3a28645da3ec6d736c1198e2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588023303000000	1588628103000000	1651095303000000	1682631303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbbf02a8828f0fb480e67044f96303194042549484f9b9ea93b3d06bf2f3269ad6b330212322b578b6dc14def5a3e0fed1e29f76ae46d4754039befcf3ce7b3f0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588627803000000	1589232603000000	1651699803000000	1683235803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x78e8ba8b54e1655d845c48c84cccb6dc2030fa11b037cdd2ce4b4cd08486e1348ea790e8192a9677335d02299401a9e09d917d1a946f522041e173724acd4a82	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589232303000000	1589837103000000	1652304303000000	1683840303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe7bd1a7baaf53147f4a4120217fd5976b0a42ec779f6218b936b8c58da9e08e55e7f0beeea88290bf0e51fc8e0c2349d7ad8e4ab463d31446cb45173f3aff702	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589836803000000	1590441603000000	1652908803000000	1684444803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe525fbbf4545e08a9d88b2d5737c6423229f7531f3c6c668a233df403297e31733acbfb362d1867b1adc22a41a41659743d865fd464595a2c476f15324f4e108	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1590441303000000	1591046103000000	1653513303000000	1685049303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3e81c3343b9927abea01c0a8e9e932f64ccbceea74e001512716d814ebfd63c8224a28883f7f13f6c90404d38cfd11c77b4661d7c1cf58a0f8fa2ad22345bcd9	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591045803000000	1591650603000000	1654117803000000	1685653803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd43f94209211c0c03d1b801671a9374de4448842a5dd9ea32857ef7e74509faf4e14aad534c74ee3b7dbf78a36238bfc13e1295b47b5fd3b963336551ea1fd8	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591650303000000	1592255103000000	1654722303000000	1686258303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeb8db00fc82c9a141a3111df63700d52bfca8c1b2b08e8a98ac5df37e2d99622f2ba1cd23c4f138831ba7a3520fa4dcd35bf0924dfc0049aa65a818592303aa9	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592254803000000	1592859603000000	1655326803000000	1686862803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xea7f95eea68275ef022d126d4c02d2e982a0fd238241badd6f4ade885dfdbcfc839673f412b7923829e4cf63307e538c89ba45cee21e164641a162b9cb625a9c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592859303000000	1593464103000000	1655931303000000	1687467303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3c69b62a1ee0781dbf647cbdf77e5026db330ff85c864282ad157c8c907855a576f2788a7dbba7c5c99d47ea60d0a3f5b38d85674b89b8043e49e86ba0c7427e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1593463803000000	1594068603000000	1656535803000000	1688071803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbfc133a15e354eb73f8eacd21d2c70b7b8697f44e16d8d579875a03a5d8f8f953b0710b331efabef9222bf315f20e691478d9cc49fe7cb9e6e290d4599e333c9	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594068303000000	1594673103000000	1657140303000000	1688676303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdf01916221bc736f2d4eb4dac0b8ed285ef8cb15bf633b43d2531598569aa526a6d534f7355a7d865efb190c80764f7b3316aa18fa3dd22d1c9fb4bdff00f2a8	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594672803000000	1595277603000000	1657744803000000	1689280803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xee2f00a273e536b5c78fc49ad7a606b8ca62ff35a9d20d22163ebd061fcc76dfc0973d79285d7d4a59bd9c9bf2a4c14eefa30e70d1722a125cf8d97073314ad8	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595277303000000	1595882103000000	1658349303000000	1689885303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb11987a62f95aac8567dc37a41f97637860712b8aee99fe6a90489397f8bfe9be23ab416ad1d0f4b5df59894e0b939125230decac60a0aca676644c28839a36b	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595881803000000	1596486603000000	1658953803000000	1690489803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x455d554f4ec1300078f94bf7195c566423aca07bef992bc9a9c7fc4404436087a5eb30e2b2daa97301660e13c0f076e780e06ae763164ff01560e42dbaba9a3e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1596486303000000	1597091103000000	1659558303000000	1691094303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6654a9131cc079b4bccb4130066967a58fb0d48dd2c01c0631ef5423082176d2b558d9189ae5dab002d870e54657217a42a3bc69fc198be64ffb5f0b3afdd084	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1597090803000000	1597695603000000	1660162803000000	1691698803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd0582b959cf1753a76535822e8ab015b8b651b095d32a6e0f78761c5bafae62a5919bb088ae18028f13ab3ee03b50704fd1282344526b8da4c78be9cbbd7fe19	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1578351603000000	1640818803000000	1672354803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x006e9596e7d61459b8ac29a9435917d7109440b9ff473c2f3c4ca076e3b7221962ecc5af3dc57d9f627fb072a87d2f476619707d37c26b8ff61311734d39489e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578351303000000	1578956103000000	1641423303000000	1672959303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe749c8393f7e3335276025ba4076dab65b1a44690129e55907b29172a2043da5f9c367a37a336886c42f24228a31751e9c2fdee72532cc339662deb8c4aad631	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578955803000000	1579560603000000	1642027803000000	1673563803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4eaed474cfb7726ebd685f3be08e81d20e5ae7930c7d0f24fe955c564bb9f07cc72ed32d4f32001d468e88f5f0daf54c23f89ae57f49af310ec7895b06f8c008	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1579560303000000	1580165103000000	1642632303000000	1674168303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x289a340521eaec2125bdcc4a9a7982f00b931f5f7b2645d3ca8d4c8284801adcd493266b67c24d33e850d5695d88234a5858a924871c1ee1b2c4211adef5d78e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580164803000000	1580769603000000	1643236803000000	1674772803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x782337e38c8e97e6ed7387b3e34a7ed179691f58f37532a19c469f0528d2d999332df4c502b36cc1305918026f259cba4eb4a83aa87f725a75efbd0409ae96ac	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580769303000000	1581374103000000	1643841303000000	1675377303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4faa5f0bfcaef9a6d269819d5bc915d6daa01ab34f188be947c730b572b08c55e0980bd38a39547d41d29b8f4ff1be22405c44979b8c18459fd86e62fcea446b	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581373803000000	1581978603000000	1644445803000000	1675981803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x574bb6166a068e1a4cc35ab22dba38910b04c43acbb3c621696412f76c5e29bb8f10511a655e0fb0272fb51dcc8e6d4f33f529911e8043139d22725047c0420e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581978303000000	1582583103000000	1645050303000000	1676586303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6625331534934bfa9ae82a8f38fa74495417230d97147fe25f412365f92948fd92c9478bb08371f2a02a1a5476c87eda88fd00911d912f160911ae8cb5bcca2a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1582582803000000	1583187603000000	1645654803000000	1677190803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5accef7692b30cad217419cda2d9917e125030f85f3738a7e91c182bae8ef8965d5c147fa67c9e4f39e57d1abebff71740ea3701110138ec7dd1619d2f0b85a8	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583187303000000	1583792103000000	1646259303000000	1677795303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x268172838b71c57e8e9dcc75ca67faf00ca9967642397330602e4b2737eeac6d9d2491aada13a548d12e784f065e3a2370af225b7f25a00ee7c5c27f971266f1	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583791803000000	1584396603000000	1646863803000000	1678399803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc84443cce4b581b555aaa4a0d3b09580009ecd2a1ce0e6cabe0df7426905a5e6aaa66ecb1af9388e94945be7cc288ee71e578cf478a67ce5dfc098a0470a3a75	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1584396303000000	1585001103000000	1647468303000000	1679004303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4657e6834cba4c683b15ffc12845b96def843da844b064552d4001fcba68d98845b1558fb8a13af6a1b6fa679727eeb950e7f4621bfd86d045a208d2d69429da	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585000803000000	1585605603000000	1648072803000000	1679608803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x897de25474512054b841cd183b9738d8e9a9068bbaf1ce8cd1600b04a3fa51c28f5c6a33b5e3d4777a23d16a7ff187fdb2e2c30b4354b6eebd81f1ff5ec33a66	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585605303000000	1586210103000000	1648677303000000	1680213303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4dfdcabc95758f926975a7cb80880f811c259391651c27c886db36cfe9528e056372f39443fe5bce233f98b3aef520e652dfa3e0c8b337f75939cfde9981a329	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586209803000000	1586814603000000	1649281803000000	1680817803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7402c78ccda862c8fbf4059134893bc9e9f70736e1cc72af5e56581ab688dd65f84d5c611018d59904cd6216af4363e5f63aef4767f8aa486efb11c6471479d5	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586814303000000	1587419103000000	1649886303000000	1681422303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x72474c888420d39d0aff914be559b33703962fd6a4e114c582dc28e0303973ceba3f6e0e2501c050c5be4296909e0534e8e3c336b1b549bcb28de543b6b43957	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1587418803000000	1588023603000000	1650490803000000	1682026803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf9ee412ea27607ff75aeabdfa395c22dcd981fccd3ba345186763461079cd8771cee4a2ebe7aa75f7af78740b5fb8b0a1767d511338148dd8f53637c726c138d	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588023303000000	1588628103000000	1651095303000000	1682631303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6065acefe0917dd228795974aa0b2ee7e53d7acdeacd235f997eeeeebb7997179e8902d3715cf42ce0206ffb29a05cc88325b992bce4fd9ca2ed9bd3d6ee4608	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588627803000000	1589232603000000	1651699803000000	1683235803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6adada7390bc0c86cd2bea57ca30a1a569a003bb777a3a083afa34d01d3e53f88f73c44e5b7d1fd5f71518b2f8f1988f97c942bdf94c2456f9a5993a1c28cc8c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589232303000000	1589837103000000	1652304303000000	1683840303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc77b5873d4ea21ef98a03cc7becd19f9d67307f089ef8e7c51cf88659c78cd5e862d8cc6145d51325da2d5db787a66601631eebb9122cd98c4b30e6092f1ee45	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589836803000000	1590441603000000	1652908803000000	1684444803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x237f9862cc0df03bfddccaec46614b5e854872cd2ffc3127c822261fd6b96b95b00f5e9850419e7f88b61b78abf5e83d9e391698fceb6f656536c8d635df0424	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1590441303000000	1591046103000000	1653513303000000	1685049303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdd8ed28dcbc39db2304a0c8d70c910899ba445ffbb5a8d99cf9766d42ee6a3e18da572a1f555b86b25f08fcf7c4166f1757a773d19b70038580c1684eb13ce10	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591045803000000	1591650603000000	1654117803000000	1685653803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x29f6289b9c5fe977314902eb6458e291aa319ba631b12b7ce03bb213b2dc36375fb42ed5194b4de36f6e6966df191f66090e0dd63611399a01e64cc8a3846b0e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591650303000000	1592255103000000	1654722303000000	1686258303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6d18433aa48042ea855c4e9fae5435245a2e33dfaa6fc3d2173b49f7f7de11e1ffe17256be8bfa47ee8f66abad2400059f95a59bc78b9a38b33d1c2845986eb7	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592254803000000	1592859603000000	1655326803000000	1686862803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf8b1eb8c3f6503205ec552d674e7acf526b46c6352d762a5ffc70a27928ae047c69ec2f0b48229c7aa96717c3f326a781c1d73a582bda9d49407879aaa2b2466	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592859303000000	1593464103000000	1655931303000000	1687467303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfa8442d7851372b851f885bb7e08c294d48141735f85441ea3390032e4cd332dc25f1fa2cdf7432b6dde7c4b5d36d4c8995acae15127bc62aacf301bae273584	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1593463803000000	1594068603000000	1656535803000000	1688071803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd1beb98feb430889224fc6d18f58aa3879576b1ca478890e6bb15a72eea8d4526bf927a0571de99801a0649efe12a4264e13f7c20916712ef4450cb0c4dd7f3b	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594068303000000	1594673103000000	1657140303000000	1688676303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa65d661b93ae3242cd7bdb281083e34faecb3cbb41e2ef324786a2a867ddf12f90b124a44b7079606554708c9c8b2919314eff4f117d829c2bf2dedd74546ac3	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594672803000000	1595277603000000	1657744803000000	1689280803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf1829a4612e83154b9ebc812753e38fd1d0fe16684abe9ea6ff5f782f9a506caa31d7742d7b57f0d66253d05ebf4d8181a696154d6ed3dc48ece979ed40ce47c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595277303000000	1595882103000000	1658349303000000	1689885303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc676e1428c173a7067aa6ff9b2999a33c575f6588a809116f04af6b63b309e4977c77a8a921ad6be2ca11494784d4d2b365822ffb07db0651937d69d398eec74	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595881803000000	1596486603000000	1658953803000000	1690489803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x127441d87b1ed81b588c84527115761840307a90b65f08f1faacc73b0dc26ff6b9b5e1c657f9028fcb632595190b5c6dd85c690eae62cd2842477652a1bfaaaa	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1596486303000000	1597091103000000	1659558303000000	1691094303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf63ae864099bdc62ac3274378210c400ebe3404d9bd7037b853e4065db72188561911e9089f41a254643823724e100ec0c48635de17445133e2eae5df456a911	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1597090803000000	1597695603000000	1660162803000000	1691698803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1578351603000000	1640818803000000	1672354803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x97de1aea377a8dad7e3ea8be281db0aa29588c8da16221f4ec1481b1505019362a235b9017de3777093093b003d828a348fa8a0e95b3328798504889be972c55	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578351303000000	1578956103000000	1641423303000000	1672959303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c4d3f14999c37193148c7f042bf55e4ca2672a3ca6ba09783167b0a68b8372330516fd46470b6a1e0ac54f5a86c4d37e07b287127fcdae1a3753c4f21881796	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578955803000000	1579560603000000	1642027803000000	1673563803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e9aaf95387ae09fc763c32d5ea615169b04074c5472f0b4b3bb7698a91a92f70d68eb84dff9e88b919c80b561c803f21dd523246a1513f1be41a8c0907fc7e5	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1579560303000000	1580165103000000	1642632303000000	1674168303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2fd55aa16c0dbaf06cbc6f942df0b7fe2e802a313b424b25d0b1686b737f63ae751fc613fd7d8be7e8e4f8e32d42555e525b2ce69df82808e73a754bd5aaf9a7	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580164803000000	1580769603000000	1643236803000000	1674772803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa73a1429d1f92b0f33c9fc446378aab5c40a1db66cc33f2e3163e4ed537b1f52ee73dfb12256dfa2feb65a5b768c4952bb23c9c4c175581649bf930e8669c060	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580769303000000	1581374103000000	1643841303000000	1675377303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x169a5590fcd1442ca848296af3661b845397d6af0d125584c6c198b132078cea003760c10ddb0b7cf24fd831e462aa711e38c5c431c6a0de6af491634c040d4c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581373803000000	1581978603000000	1644445803000000	1675981803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d7f971c399514f72eb500cddcd65f204cbe1d9bac1a9a144a386708929ba72209d740204e4908f75c8f11ad64352c55e030b9237cb134a4a2d554bec471eeb3	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581978303000000	1582583103000000	1645050303000000	1676586303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2b53e85f3f8bb40383a9a83c604a33244e70fad6ca0676e14638d5956e4585e73487a183a76d792f2ab5c18b573bb95788bda97bfbebbf63e3efeae185d39cfc	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1582582803000000	1583187603000000	1645654803000000	1677190803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5158e9792cd938af85d8d81a0dce1940b91ad70bc146e68aedde23723221c27a4760e1ffb0548cf32c14a1d0936803f3f0c75954081814d11d5720d82b58232a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583187303000000	1583792103000000	1646259303000000	1677795303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d2dfdf21b4a605c7f8943d72a74a647f31d041fb043e219973790c3dda371dac413d8c7740d8905e58379b46a49d5e037435291593d982e3b7d51879547ed89	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583791803000000	1584396603000000	1646863803000000	1678399803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcfb8c3b5e5e72d2d15bc4117e8fcdd3359a7844aea1dc1d041b127aa6fd9ad6bb7f7f03c3080e300edb3dfe591b6f24af17c4bc2c8bffc4c987c7e4cb40acefe	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1584396303000000	1585001103000000	1647468303000000	1679004303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8c868fcc6e8d29da7baf9862976439323e47e701b00a989002f96796575a2fb8f0ea1a3af673fbce7c93d43f2d31b260b68a2458fd9b7faea5bb9d20c860116	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585000803000000	1585605603000000	1648072803000000	1679608803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcce2dc04e736b0d0eb97d2376fe8407080c985899741e9447f5cdc4098e5cd3a39ef896dde14fe6c2d09827f09d4bcbfb19ee94ca743de02592ae911a2f11349	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585605303000000	1586210103000000	1648677303000000	1680213303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd513539dfc7f76507d93aef1fdac420b44c5d9b959a76387da9aafacb247ae0a1aa940d6abf78ce6d6df1b387fdcb6c11fd298f5340eb43dbe268b8c3358e173	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586209803000000	1586814603000000	1649281803000000	1680817803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0a105ba412136a011e9cd3c8d1e66eb231b0eb0d941a4635c5ff716832ddef9bf7cbbe62d8eff50eaa7601f507b8eb63837010a0929ff8038e4d3f73f642d28	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586814303000000	1587419103000000	1649886303000000	1681422303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x573fe3249080608c52de7dff6188c1d3d6b4481f478646d0a48e22efbb2092d3e2f1c7b3ba89cea55ee0628739adeeb1ae6d9155a28da1e777ef29303bf6449a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1587418803000000	1588023603000000	1650490803000000	1682026803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x536c6a30027b6b672ac882ae9a78695c3c12b79380352599cf6905a3d200edd568180cc1e9ed9556024c8e28222ddb676f96c408fb1b419e0ac233cd11379a64	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588023303000000	1588628103000000	1651095303000000	1682631303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x66a14ca142a86733a56e4b183938a7364f5bc64a3789db5909bd10d182287ca691e0b85a2d49275aa852355769d361844e04f3f675c4ac9ca2d525ab9c8618ff	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588627803000000	1589232603000000	1651699803000000	1683235803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8866a9b9103756525ef626bff63bf6447cc0cbd5ce9cb0e3492b44cff843139727f86eb3a6ed1a42d67476c17a922a5e386c84aff35c8224abc736b5673a0561	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589232303000000	1589837103000000	1652304303000000	1683840303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x879334b96d1e14e229f124d333578cf38b09d68d178d9b57ebb91881562b8d71d84150789f2c1e002119536a0ed99c7e7c9e1b043033689cd8ed34a42dea7628	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589836803000000	1590441603000000	1652908803000000	1684444803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5e460fa5223434d54ccdd582c3fe0d5d1c83b9b0140aa05f3a1b83daad906c0bcf823d8b9c91ea5d8bd13d2b88222c185e865849a9aceed95e1856ee12905b89	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1590441303000000	1591046103000000	1653513303000000	1685049303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd71941a73b1cc0b1064f666cb2b16770fa8108c3044dd6309b92a98003d2decb287efcee3571b713c17b404df6a030ea40255d6c0407d8add338cd25927bdb17	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591045803000000	1591650603000000	1654117803000000	1685653803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6cb79748373ba845295a80e9446d269b0e10de5ea0279de1ea052c1dfa70a51035c4b3301249cb9da7b7b50910545f908b18331aa6d4683652c1c6636ae156e	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591650303000000	1592255103000000	1654722303000000	1686258303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4484091fa3f62c20a57a3a95051d0d100a2d511ac9697a8d42696afc0abb01b018fb705f97aa47f8d4dd00414793059091ad18e3bd922f475b9ed1009d3f929a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592254803000000	1592859603000000	1655326803000000	1686862803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd77c0ad6e10918cb13bcb2537e38b5e3c1fa6b6e58a26e6d00de06860affdbe7453d65a80f33a4ce29fa85a4db22c3a7fd84954930f4d12513d8fe5acdfe0df2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592859303000000	1593464103000000	1655931303000000	1687467303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0236a85658a22070235a8eee8eecd19aec2de8d0384ee10a6bace10dddb56f64e6d132f6cb057d9cb53e64029fd819513e22b4611ffdd614d91c71622b05735b	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1593463803000000	1594068603000000	1656535803000000	1688071803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x046678c65aae054d806190a64a16fbcafcf9319ed6423ae89833a9b4969c7cc25d483599d2d4735a7c176643d7d84199393c773267f61ac889c629630b0331a2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594068303000000	1594673103000000	1657140303000000	1688676303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3c655f3487671936ce772037abbbe675611741984c85c534f87d17743e96d84d1d4da3570c2eb7af3dde73c35705decb31b55707cda156d96ff4de317ae62ac0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594672803000000	1595277603000000	1657744803000000	1689280803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd3676705a3cb136f9f9aea63830343d93807119b9c95fac9258eb43010a2c9c7a809d75e13ba4b1e89cf17225b83fa61724932ee2681588dba6684c27171067f	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595277303000000	1595882103000000	1658349303000000	1689885303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5069addb8cf2fd41fa2e591e1940807bf76859cd4bc493253c1e280e3c2788e86355a5e459e020cbc921d6aeb986be0d889cd3a8448463f2e72b26c7fccbb941	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595881803000000	1596486603000000	1658953803000000	1690489803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x05d1af0f489a815c7507ed9f31fc72d53edb0515006c555fa795bfb52da02ba43eaae76f42d9055c80f3cc225a261da5d026311032759af885f75f1e9cad86ce	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1596486303000000	1597091103000000	1659558303000000	1691094303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c7c6b38ee758c509af969e207d5fe8b23e93431362747b63058f7afb03c6d6f0dd64e198e91e1f69bcb7329b4608e45ed3f5417e0e1400453d9583d58be64d6	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1597090803000000	1597695603000000	1660162803000000	1691698803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1578351603000000	1640818803000000	1672354803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7cdc714505b0e7fcc7fd7f682cc9789420decd8ab3982cc4376135597c23f201e7cce9da921814d39d52473568d67ceedf3f40cf606441c9906938b1e7e3a2ac	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578351303000000	1578956103000000	1641423303000000	1672959303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcec21cd95caa25a124852315119e845c33f40741a59a6227e36d858fb7e994629bd9b45556d79505eae43670fab9818be99ebc65142c26d7ce12a706d60fd005	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1578955803000000	1579560603000000	1642027803000000	1673563803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x63975a1e6527e124690a39f62b7ce71d0b587b48c020779861466aae61333956b7f4eebc5631effc167053f5a1f2a035f0dc631631c8bfac5a55a32b4a84e116	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1579560303000000	1580165103000000	1642632303000000	1674168303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x17957fe1218590c965606112b6ec28ce5f55d13c5f2c297edf3b11f20a893bbe4d6d85dc3a66c1e7a49bd3946a510685b4dfb12a6f4e23fea40ed652d48c3ad5	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580164803000000	1580769603000000	1643236803000000	1674772803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa99eb3f274d0890f49846ca7bca6d06022d156262b47c1def4e42953a4cee3f5dc5f65e72498050297289056506dde0d23c2b3da01d49d0b252829b4a946059d	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1580769303000000	1581374103000000	1643841303000000	1675377303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf39356884d54f8c74129ccaf4247b129adef4dd00e49ddd5792155dc15b7d501837e1650d68071d4b6a89a84fcf630d373ecb19018e47bdf0ad2aa8792582aaf	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581373803000000	1581978603000000	1644445803000000	1675981803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf8ee2db57802bc9f17aa3969926c1b654c128b66c17600836c43656c6b283466c55af76a3425421b0a54d7224f143d93b2131ec41b033d4a0d57c676c65fd372	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1581978303000000	1582583103000000	1645050303000000	1676586303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x96a570e58c2e0b52049db4a3dd94b3fb0e4037f384eddeb6b973183c65dddb5b84ea6b9008727ba370294801a28b6de0764f6c39d1965b5e83299662878f8de0	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1582582803000000	1583187603000000	1645654803000000	1677190803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb549d148e3de7b7151f7d9e8e14b4cc92950cac590d41e31f141d9b5b22a67b49a0062ee554a1427e5516a1f649583d1d6bda1e5885e7b96f9ec6ca14c0405d2	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583187303000000	1583792103000000	1646259303000000	1677795303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5b3dbc2a170356a8cbaedb21f9f8c473dbcfc2cdf04d20bb7a7a7b1491010596fdc1213532b21e12dbce75b5aca2648f6691e206bbcca7ecc18a07d87c92d540	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1583791803000000	1584396603000000	1646863803000000	1678399803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb5fcf3ad9509484b037e59673cb82b389bd9b7d78edacb038c9570e84c570e28d66718ace0a17da3c3473ef564c1531a0571103f10f38e52beab0285425302a5	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1584396303000000	1585001103000000	1647468303000000	1679004303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb43bc7c5aa8a2e253fa22b2f8021d8f2698e707574cc73ac58413f6577c5ada76df83aa912f99d57216bd3a5e189d4ce6d1c58dd858d85e2854114f9bc76402a	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585000803000000	1585605603000000	1648072803000000	1679608803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2582c18bd44456c95c9fe2de9f6242f934a544ebe7001078a3a4ed80a2ccac290e1d9cda5b04c608ee76c0957a69980f3832f3f6bcc9b79b65df1f84c8081f89	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1585605303000000	1586210103000000	1648677303000000	1680213303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc2fc5a55f4f52d31ee9b25e3cfa1a9cbe75863e1ff87f1506b88d38953968f8be58e02e9d76bf4b46bc418398f825dd01bb3046c0162d9633c193df7f2244fff	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586209803000000	1586814603000000	1649281803000000	1680817803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfae9472e66ec24bc63e5a23c8e42c9524b233576b150eed879314d1121428e5dc57ebc76f5d4a01f9c4fa6a5162b4ae24b547cc4933f68d7d7dbfd36d04eceee	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1586814303000000	1587419103000000	1649886303000000	1681422303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe2124d75221c3fd5d76504387bc7d800cbf88a648e5142b28211092abbf08eb9aa9703abb27245eea8096563ac49573df7e03278003686826ca04654a9abec20	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1587418803000000	1588023603000000	1650490803000000	1682026803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0faee354d0ef15553dc1fe87242e6dfa6310568e542ceecd5b730d5530f709c652998219641f8570d08b323ba2d976aa9eb98cf099609a87bb8c2bb5b0191fae	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588023303000000	1588628103000000	1651095303000000	1682631303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8a8ff0f63889e4e38c1e491d671fec2cef525b9da701c740b052bac54b3ea97abda9bd22d1658930a117236cab997a3e9ef5cd108144c95afe6c7dd47d520148	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1588627803000000	1589232603000000	1651699803000000	1683235803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf6cb9abd6cc85878958b3e8bdccecb8ae99a1bc297f1c37a3c877d659a2a9a36b2a1d1528930629185e3fc7f123819809f9144b0bdbb21eea9da73143df727b9	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589232303000000	1589837103000000	1652304303000000	1683840303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5d80e2c7993cafe8ae185fd07e11a6cde0e611aa3e34490f41803ff1c0a4e333322e685ab3fc47265221ca301590758b1ee3c223b7ee9854204b11112c702e92	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1589836803000000	1590441603000000	1652908803000000	1684444803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x519e7372260f1dd5bcbb5fe7c80b67fa932742de2bac0bbc2f06fddbb6f4ed8bd3d756ea57841bb06b1fe85217af8a6b0bafedae4bff5d71c64f05fc102c2b15	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1590441303000000	1591046103000000	1653513303000000	1685049303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xac43cd12ac6a4467aefd5346cf825eb796fb93614125967b494414736092d37a00475ec15b40f2c90efc0f15ef2e489777600e54ce8e3baf2fbb5303dedd0396	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591045803000000	1591650603000000	1654117803000000	1685653803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1cd4d8a6f08352c2ae7486505808d8be63da9f547f9bac45196cd563fd7876d33cf4d678565b027ee314fe6809139bae2ff8aa2d208ed0338e92aa78d4c1fd40	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1591650303000000	1592255103000000	1654722303000000	1686258303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2ce76603e5034680673f7a9f9789923f9e2aad33e44549f541bdddd51ce996362eaae05e671727f5568880838d00e4b6a55970e9c0d4bde30ad58ca468b9150b	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592254803000000	1592859603000000	1655326803000000	1686862803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xddc3eb5af6cbfe515d4ce7a64a8d7c889d7e7ab435b0c33f1ff17179d009cc874db531f0b3c3a38f7a123a15a5af2a56473f33593f43eec6ceb469337a24aaee	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1592859303000000	1593464103000000	1655931303000000	1687467303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xafdf5abda59e62696ebef07420778671c4d7479efad1d91402fddfc00463d7d249e88a3d07a239077d15ddd45c16f5605be94405548213fe4d08e9fe2d190590	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1593463803000000	1594068603000000	1656535803000000	1688071803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x41ad978fd956ae4fc53404e3887e81bf1afe101a80d85bdd7a10540d33eca429813cd88b1f1375895d620dabbf491d612d24b5e3913dcdd5e9742684924c0400	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594068303000000	1594673103000000	1657140303000000	1688676303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8c2a10bacddf27504f8fca33b788df922c47ff49969ab662d22d77a6e12984cdfd60be4c99cd3abf0760805d73180facc3941a85bcdfec7e6cbe1d2091c30544	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1594672803000000	1595277603000000	1657744803000000	1689280803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x158e404715fe2663f81920c45c1aefe4b52f7978ee284d453393620432826bac5ac37dc1f1587e0ec42c6cfbe46de1d6d8e639438c95b58fbd65820b3dd2d4e4	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595277303000000	1595882103000000	1658349303000000	1689885303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x40c3a4f21936ca0752c14a27f09a58f494aeca0d60fde72e89c9ead34000a67c2456d292bc39ae3239aeedea87a0f52fe7c1a9d958d7f3f9eb4e3ba48f99629c	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1595881803000000	1596486603000000	1658953803000000	1690489803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x87c3b5d682d27c0ade74b059e3751a49f21f48c921a8fa433f8687efca79599287eb3fd704fdab91fb8eb1dc04ccf30e04aa14b8edc036610fe1353701445f85	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1596486303000000	1597091103000000	1659558303000000	1691094303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8fd2e0e7b19f47a51f453b5b8ed8f7da1069e9a7fb6f5d8d072f672d5dfb4d4a63483830f06d2ccb33a461d15206ac16426c554e4225bb2452a0aaa650a74f74	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1597090803000000	1597695603000000	1660162803000000	1691698803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1577746803000000	1580166003000000	1640818803000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\xd1f30ad00d39b79c4fa8a56063470b8ad6961a6ae8c52ae55dca28a851ea0a9e569d268e02377de17622f3b0102f9574ccc0939ffb40601261364c1ed8bcbf00
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-31 00:00:14.863747+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-31 00:00:14.94166+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-31 00:00:15.005262+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-31 00:00:15.068533+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-31 00:00:15.130613+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-31 00:00:15.193279+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-31 00:00:15.254534+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-31 00:00:15.317014+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2019-12-31 00:00:15.740285+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2019-12-31 00:00:16.172011+01
11	pbkdf2_sha256$180000$JQtM1sZco7W2$UDVy2D6Ix8onrGXkoVdaLXsaw8ytf1ehCNZAUH9nXm4=	\N	f	testuser-TrKNHGl2				f	t	2019-12-31 00:00:17.826697+01
12	pbkdf2_sha256$180000$bF9xnQDNVF5Y$5yZCj5hyvkI82w+uf8m8Jw9gOSNhGRhDf63r2v/SIuk=	\N	f	testuser-EdBw07YB				f	t	2019-12-31 00:00:20.898463+01
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
\\x0a8c3db73d00b00d31b44460e03b01e07d1ed643bb020e1a745561351b6530abc869ef493687dbe5f35727208b5d3ec0557b55657991ec4b0b0a72fd68c7e70e	\\x00800003deb87f7db281dff09b3eaa652443a4a675c8ce8f57140b6b362dff61e45d1c75fd7a505cd3e6345a0e4e164b739ee4adeaf8c078aa0ced7502c80ce747bb9ed5d78983ec940a4b07332c435e31a38467ab975c7d2feb6536de386bb417440b682776423ef5aba96ff7c75427aad8d07b2aeed458f791f7b8733acd812ae5c31f010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xcc630ec86241a2df6a85a959401aa6a4b7dee19647f41dbfdea885e1b2cd56ed4eb87d853fc876e89466257209964619ae9fe9e23ca58a34ac65cc262bbed607	1578351303000000	1578956103000000	1641423303000000	1672959303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x08997d01ab8fa10511fc0599b099e014347442d2e3604d60fd80ac999248721866674e11d1ae2608b9b3eebb459c22bc739a9f0129e1ac7c4ce7fe2314aa6c16	\\x00800003ab025ad5e158e70733f220ccee1e8224dd6d2ca6f0c6b0189facc4f069d086940161f704cb8a145625af58c32f3b3dcf3513ff53e41b74bd1aa69ed1605bbac03953f3e8934015335d223f9820737e59f4fa914a6a4a282c5cd987eb7e5a54499ef5376ce5fc74380502c21ef5d58759f64d8de6d9094c16d2e77e7b7092dcf3010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x149577e14f3b434411ae62524ce2485bdab3828ca2fb4cd0ffbf4caab1cb421e531b62bb51a374a6b4cc1940ef9375b4807e69e621832a3f8b50ac44878a600f	1578955803000000	1579560603000000	1642027803000000	1673563803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7fc5d42874a49b1438e0dba96f86ef2c54ef0619ba334933cca8e94e5d346b42d80ec7f9abadea76509e62039ffe3ae766684de850c688d3d90660ba8690b85a	\\x00800003e6e4fd13d8b2abc8a6be952245719596738a4000445e0881b7367495483905705a6a0b3be15d9ce4cdc4e1df3aa987441e6fb6700e154e15810fbaecaa319981940f6425cbe28abafd8794bbb88d250338f4e07124dbc3e53d54d84be2722db62fd66d6569c82efc5eda8a264ade17077d95bb9ca9ce560aa309f1f63a883a5d010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xde91537ea1ab7c167174caaec4b4df699714e28946eb256c97038f7c81babaddc9f026bc7a694c0eab666d8bef77d54b611e8343ffaf482fe25aca8c800dcf02	1579560303000000	1580165103000000	1642632303000000	1674168303000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa944eb68b236c4e914751f26ecf4df7e4ebbc4e10421737963054b6f497692932299c63a1125fc5e208e0178b404ecd8c02f3a93ff575537757171e0b84748e0	\\x00800003e4cf0d18a0aeb338a6fc09ece6c5cb098565d21c72f5c536682163e57eb275de9f8691ce31bcb6c23365d86163daf67e46aec13f2c229cd8da80a9cce2c9f5f354d2f8ebc6a2c7aa419ad72f36900064b1e6c4f6e26fcd13e7821e64908343117fd3648ac5b61332b3b4834bdcc99643b908f661b3fa5856fe82a8add903743b010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x432a8b51a95e55633c20b508b6e8d6e6f18a5c0dc71cde08e46b276d549754491364f00a911ae07b98ae020e66a02fd7553bbbad1e3a7ed7ea9ae98b955fbe09	1580164803000000	1580769603000000	1643236803000000	1674772803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x024eb8c53815d70be16003b1a9c804339a53c69c5813cf66d8ff1e691368dfa737baa4a874217706dfdf1e9e18d59fba7cea1d2e534abaddc68b69df090ccc9b	\\x00800003e3ca170322f4b9ac2e2b3c38671c61ca5614967df66309ec41274264c41e8d669074d34f73c55db4a859d9921239cd9a7e49c32e4309f589c542d9ee11cd857ace126b5cc519901496a778ec9a06991b9fc77c66602950f1d91f8d89605f6b491c2cbb6a30789f250cf90a5b0632c74b180a96dfb9f5179b508d269dee0a51ed010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xedaf0d2b2db5b8dbbeb2ef874904dd3a4df40f3c14b14d799acd45981b06815950baaa6c1c0881250236311a455b6fd2140030d0ab64f6d7514fa75c97834d03	1577746803000000	1578351603000000	1640818803000000	1672354803000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a462de35e8b908669cf386b510422335126e42b90b6f5ccca5347248373f4e2138b881e995f3ccaab294b00250bc2f956553d09a3a8454b8c8fb59a05c6463d	\\x00800003bb5a0c897b1cf66cd15a374516bf45bbfb1ab5544b4da01b6e003ed4f54c24fb286e35cd1af6de22328639306c6687cb0a56b425e33357ffcb7c97d62a8376f37c17ad93e929f4b59f9b5cc123ce840a90fea0f285cc430e9a02e8b2bed2a9f6496ed143096d19125b7eb3177a5e361a8adadc31b1cc274274f66c5734028ddd010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x77e376e0c05376df27ca4766fabdc637b302d3c6c43e7b6309c1e2558d70afa523c56994012347f2d3d48238e471565ccfa1e7a7f768275b2bf9e3c8803a240c	1578351303000000	1578956103000000	1641423303000000	1672959303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17e5bcdaebe0c9b3208a4fc302c2b3ff23edf0acdb2c81886ae5d52e2bde569917c5e71b1f0ce1222e34cf502bb70c2a9b30887e779f78ee1b730e5e2b111635	\\x008000039df3f6985b36955141439f290ee88bc2a6c4b58604c8a2ae9b9f60bfd5fb847b6986d1543594d4d83eda59b671332114ecfc5d022692ab92fca9813bd855c4ee74a58c88ee5067d2f60f8527757ee79c8ff2da6f4fca6787fa3530c3700690d34ba1c795e7415e67851dcd1ddec636f2ac20b21b89cbfe08c82787420730d20f010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xeda4865b603df88b596d3329a37b60de97d5be6abc610802d4a85eb257493011688ffd0c7204c0f7171abab4a9c3fe571bea8d27687f1028d6e20951e3cc710f	1578955803000000	1579560603000000	1642027803000000	1673563803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x35feb2937bdd4f70fc446e6ba3342388d61ecd1821b1d512b391001136ecc9dc1b9e0b70904950a29098abd7f623e28c18cd6d819c1f36c27be44cab4abccf83	\\x00800003d7568d1e81e785659a5bc8e4e33709d919b095ec6959de86585adbcafa7435735c7466f5fb8dbd6118621c90ce9039beb8617e92173795d7cd6bd4e1da9f54518bef67c23a2c3aeb1bb8d58ad8413ffcf32899a5fe98c6f0d716e56dcd0b165486f60e362fad0316ec2ee5dc9525b6de862189a938c8ee1aa0622a3f1e137629010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x4344cd0427f24cea0e7ff8e93577e40b5f0dc065aa82c0864305bd38814c1c7572517a91d661861655e735b85b1d4f30655bb40ba15e10feeb95934950712209	1579560303000000	1580165103000000	1642632303000000	1674168303000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x602b9a8aec9401b2113b0b5ff53af0c85e9596da76cf008d7baabae821666eec84bc0bde0476be051897b1f17b866dae938387512418ac92a30b693a4e246203	\\x00800003c26c977e6cbd72973b66fd85b977638536d6261d26bb0aef3d11ec41765b4bcfee48e539eb4dd3c063339d1902fc57df8c0dd2fce3f77136911367ec3b971f3a977617606f1482baba437e1b1b90a52b8c6fbaa77ef4c891407640f88f6648320d5a1e6ef875903732b57ea0f1332a80ab18ff1c5dd2e00a633f49a0138b41c7010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xf265e47ee1a2dda4e5630b93e131d95fb14877fa63ff3c32e73eb0905ed600ed9d532ace067b73fc4c19ccad83de0f824024b33a647f85ef11730f51c254d40d	1580164803000000	1580769603000000	1643236803000000	1674772803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd2edc4e40daed8637e70e4a18ce45c3b827ab46c6d613dd4b82a3c33bc8c5b435b1c89010b4606e4240dbc9e4a44b4b5891952cbe3c45cde0948c8495f6c8c43	\\x00800003bae619e6887eb560d70196a056a862c85db2a60c165b8195e58394c6ea454983d76a13d0238bd678745ef322a6f9f5de195b38920802b28ffd8f2f5e0320d9f66de06deef6b8a984fa751a5aee4bddc12a8f08c79e564c37c79e2b5483ffec40b73dc034580681524581b7a615693f029359da13f847446e7c3d560c1b5a65b1010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x0094deb8c32c1bed4aaabdfbd6876ab98fcafd4342380efa668d6bf87072335215a00a2fadf7cd77a28881dd0098dda5b46f5582c19e4b18a658ce2c19b56105	1577746803000000	1578351603000000	1640818803000000	1672354803000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdb6f17fea459894e17ea78dc4548fa3224599fca59c89eb3801d00d5894febb75384d367f939ef2447dfc7bcaaf44242832ecbb3aea4d2b067351883fa5eabbd	\\x00800003c4a2f9cbe6cb68996889160278bbb51c9c4b92ad77141c6091a17986cfb1cd0e8c6a843d9846132fa1f98a28efe5c0dfbfbe0034a8ff88b2de3d5c5300760c0e257822d939cec57945a85de3ebc45c093fd4a68e15c2c474b632672e8a1221fe5d3a7b249575e3f65f07d8dcb63455468db29ea24c6c3349890c3846802528c1010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xbc33349c246d85ab0345ade0bc3e762de9b9f5e12768247b6081b832086c94651e770e547c7216a127e89405361f13c9bb358702c83d654bbd6f94db4098420c	1578351303000000	1578956103000000	1641423303000000	1672959303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfa2362e23ee73fed344157f5851ef5271d701b9df9f08e48e6b428a456a655382e7388e64ecf30b646ada3f522ec1380512c6e7d0f54b9ac11203d103166dbba	\\x00800003c936be85e044157b7610b9ee246b79fbd0ee11e476ac368578e285eaa640792953677a743b36512eac7926c7e0cfdbd752091db8eb9afe4a06059c60d25154693b22a8a0f0c3de5abe8e1ce444a9f1d02df18f7d2cc6dbd00f741afc48c27388f178dda83eb02d58b91bc33427330e0164c23c0d903ddc488dda95cdb2cc077d010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x66637bfe0034e417064443c713f4e6fee653c3acf8149242ea33b5c7a2f3f56dee729856dee46bf72ee950025803e44c0d804c5fea42ff9d7febdfbd9e14400a	1578955803000000	1579560603000000	1642027803000000	1673563803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa4e2069238b78d5154b53d4aae70380fb80213182bf88591e5091188c301b02b67b2bfcecaaba11a97b0d8881d0084c065ed74a7064c2642705847385954948f	\\x00800003c98fc8c3b544d80be791f434a7e13fd26b330c7879e2143cdce6f73647402eee2bb240995cfc5038f48c348a03c7f54a8eccbc8d325d815fdc28d5e510691fdaf6f0895c33824b9ff8277ec037b56e6c1aac9cc4fbaeb71d0c20f4fd3ec44f968e777e9c3aaec34afb47e4e299167858e6e87d9825dec02d4e725079e38815d5010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xfae735fa2b6a9fd51a586aa9535158fd65e4f2faea11c8014ad81983ad5c8edb7946ac09ec54ce586e6867498d97ec6938cb9409ebe53d8ab0345e1e6a93ce0f	1579560303000000	1580165103000000	1642632303000000	1674168303000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f6b1bf90208236d1ff8969f214809ff10ee78a38a315325954eb3ca397924838922a3efb7435ae2cdc6a4fd81cf22016369243163db79244359f52ed68e9739	\\x00800003ae3c85758869298722451ae445436dc5441f6cf15df2fce9ca53a262d7d6a7a1001e7c8406cc8c122ed95a5b38580edfa636746d4535cbef9bc9d61162f28334bcde457b277d832c173d1dc0785792bb7ff17e42079d2d809a906ce101eab41261842012cc1932c937981321559a2dc6c552b1a94d3ba2cb48c2cee6ad3b9555010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x8ecbcf51be2a3bfba8b3c02494193d3fe6624c235341324a6af0cd7f147e7d54dff7756870c922242e06dacf2111d457d36676889cc105bd5a01ea2478595e06	1580164803000000	1580769603000000	1643236803000000	1674772803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf0386738936b450f771b9aa68cdf3b34d05edd2c09e1ea60b54157d95b40284c025c2e16b80910513bf56378f9e7445375c3be84d88e44f6fb9fc87dc7b8969	\\x00800003ac97c13b22dcbcd29fe123feeb27bb0acd1e93d3868b4efb886b7b1e42c9fad219c81f193057c8055f9f17006f7dabffbc5d40b88fbd45df85613137078903a99e16b7b8dafd3cf4ac88684bf5400614e7a6308daedb747029207341f01cba1b77e68362473a91026e132bf646f23b78329b3992dd6f25bfdb604e0a03bc58bd010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xcac6eec51c37be73de434d3196bc65fe3be246d6c246c73084b66eca16ce70f5f70672e2d5c5d6e74d31f2c458135e9f53c8ac0ad0ed99507fdc6a1834bd4e05	1577746803000000	1578351603000000	1640818803000000	1672354803000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7902bb0cffd1e434af5d06339863db32237609f04c7822eec6f475ce0134293f6b803f5a51266974b6aa567fe47c0ca963f0ec31b8e8ebaf3442b942c1cf8d14	\\x00800003a52297401a7dcc50e8fb7acc641b90a7c7c7710e4414a7054b1594be5dda4f147c5ad56c570fcc78f16f65d00628fc930ca8fd0e130a042c26c8483659d842c51d7d48254814a053958c8d42d498bc3674dab4f96a0e82195d72d4a14e24f4fc69c5f296b7e4d9b5e3368d5b90c9cf3030f6d968e4de05a8d40b2e5709e641a3010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x84459210ec778c3cf58c8701d6857063b3cce96c3f5c02745f6df24ff6d80245279874f9fc15b7e64de5981e0126b396d4c60be6e3049faec46108da0554cc0f	1578351303000000	1578956103000000	1641423303000000	1672959303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xceb4a6a7a82f59813a0542aa8e0b6f66ac596934738d06030eba2525658561e8088e4c2e895807ab9a5cbd48ef68ef42f77c5507aa760f41bb84c66b75a375e1	\\x00800003d51e4ba4b4aad009faa98af4d7b02aa76f5de6dd2f4256532b25bf33592c715871c51433c2a2bb44b078068adc86d76e2645343b978b0a8afd64a8bc76fd9c14febb03199d4f75d0f6077d563233ea1b6bc3f1e013b42a88c72009a0ce4589b0e56cdd178cf440b37ed72b5c72bdcc66609f9ab80eaccda06763730b1583409d010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x265b48e29b54cafa380f0c64ce2647f7fefa4dd76b20d5709802755b0be5a2d7c9990c90c446ce2ac443d4bf57d336c8c067ab3d8f2c6692b8ffed6f5da0950d	1578955803000000	1579560603000000	1642027803000000	1673563803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a128e13a216f2b31d1d8f43222ff231962480e3017b5bbdabf0f612d85c496534cc3203e426bb624b428a591d5464170974c7a32fa514f4090cc0d8581ef7f2	\\x00800003cdb238cea0a8e74aab6192eec17eb1856d3c69697b2f73eb157c55fc8831036c29ee9baef1eb7ee3849cf274b036133f6fcb780a3506ef0d1e1f256d6499fee4a91c582fcf4a4040d2f8691cdfeb3095c673081d7a77d5e9430cae3b0347707698269b1795ca36d66157d517d78756ea041daaf84b697d5f1ead8e23219cfa25010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xb9914bd563aedff59c078ff4fe3ad915831d90546de01726a51d0a53acc206da16962d20c7ff169bc7a242e3481f184b66b739e6f33788efb1192e1092ba9e0f	1579560303000000	1580165103000000	1642632303000000	1674168303000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x15383835d6a58c0a61cab167e05b0189612eb908f0ac7067b094ab568aee4702a4f81b695db3b39a0c30d8129cfedadec4301cc2b4852e78c5a3571afb77c49d	\\x00800003b039138f19f76f719880edbbc9d7f22f5631d88801fa19d6622ce73d0865d0031b8053be12bfe2c189bc3c40a553fa75486f388a8555daf6985b0304b0d34772e3023e834e9d766ab5dca9a48f8352fc1d775138d448a01d5012534b1e9cb425ab931f10369ccffd4bd488b892eb27d2fe2d282e0d8843e5a0ca490121e1bd97010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xad4d31ecc9b90894686b2774dd42ad5f048a4ad8ea04b5831fde3b526e69564ff351747f195757d236882cb2a59d76147cc602c235fa704b613bf9233450800e	1580164803000000	1580769603000000	1643236803000000	1674772803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd512824dcd70069abc9e340517758f56efaca3d13ac5d73b45d787a030ad233ff0198685a305f64cd6f7d87533d65373644b4e447583f09882024d20c752c7ba	\\x00800003cfe01697247d99cf990b9822098e2555ca7bff00a06f3649d2e803630b3073574a6150fa0c04e50a3a672d6094be6897988ae1e361f41666492ec21567b9dc0991dcb9b7567a02b6bee25a9dbb47237f3f0c52197dddbb7eff65f910ec390e25ebe43cbe6a5be8cfede8cb1325a153c08aa60486bb71d2ce69ae9c66b1775609010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x092fce9d2b73d89762ea9ec21e6f871285981df6cc9925113e4c02a989b37c1edd16456819004dbe3a30ac8a01e34bccd124d6af2e027e31ab3aa885b2d0d602	1577746803000000	1578351603000000	1640818803000000	1672354803000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x006e9596e7d61459b8ac29a9435917d7109440b9ff473c2f3c4ca076e3b7221962ecc5af3dc57d9f627fb072a87d2f476619707d37c26b8ff61311734d39489e	\\x00800003c6f6ba950b0cd89c75e4fab452311b9032a4bef6ca60948be1853a40adf8c57790ca28883c07b4f032c0087c2c26b318ce16ffc908e6f53dd973065ce663a5a68d7ee038117c90875badc8bd4e42a70eb076d52a1b201f2d91ad93c6a04ac5abd4603fc4520f01475a0e12c067b47484d1e1733f79e15ed4903c998be3e9ab6f010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xc288e2dc513f550e47dc6506502f10c10cfa32610e32dec2bf5c564d3d6583073f6d69e65b8bd1cee032eb47c3610e14e8f883ebb9b443134c0cbc09c53bef00	1578351303000000	1578956103000000	1641423303000000	1672959303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe749c8393f7e3335276025ba4076dab65b1a44690129e55907b29172a2043da5f9c367a37a336886c42f24228a31751e9c2fdee72532cc339662deb8c4aad631	\\x00800003b2c3e4c39127e437e7dd0ee02fcfeb7d2252d041ee4eb25867602985623fb732a29870e7a0d9c0246c62b8787840558448f75ce45e56d6ce36572f7472e691704c6edd5a73698e4511d289ea71bf93b9220025e0a53279132beaf5e5035299ae0aaf944f0a683b39d3ea831bfa6141299c371306ff51d4eec4fa0b9da1d916c3010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x252454cd96ed0ce0bfa21813fb21094c4f94ef256d45cd099b3d4366bb0f2665618cf68a5ef53d47098a63733e4740d3d9b09cda1464f059bd03cebaf798ee0f	1578955803000000	1579560603000000	1642027803000000	1673563803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4eaed474cfb7726ebd685f3be08e81d20e5ae7930c7d0f24fe955c564bb9f07cc72ed32d4f32001d468e88f5f0daf54c23f89ae57f49af310ec7895b06f8c008	\\x00800003bf9cf6abce16461056f0166af980f86cf1b581594352f017493314d265c70c033366fa29987f3448748b528e71e137f4422ab2abccad14bf22aedcf199abfdc4055394be107c458a0f085a67bc2735073f74d66b08dcfe4fc76b0c079c52bf738e2ce04d92e922ead1121c059c4da27077064b81f580165b1b95e07db2ac2a09010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x1ad4cbda471c37aa08c497c383a89bbf3d2f346fd654c41c9002565fa8d6fd44d1d6f6f3b581aa575e054755d9c8ee617efe4f3ea1d8c7e919451ba148b26b0d	1579560303000000	1580165103000000	1642632303000000	1674168303000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x289a340521eaec2125bdcc4a9a7982f00b931f5f7b2645d3ca8d4c8284801adcd493266b67c24d33e850d5695d88234a5858a924871c1ee1b2c4211adef5d78e	\\x00800003d6d1cd44c8dd9279a8f4b5e4d9d601b54c0b7b19114701964da2b731c9bcd58a6c423869c5537e8e1af7db298c506ab986844409594d895ceebec21426f0af6201e474ae77306cb33b1ac5d1b9d7b93b8e6576d4ae1d3ca96b146b3a3041a8e75e2f603ba2e6a9d61665a340a318c016385e409f25dfe1e84595582e2e0e7967010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xebde617df1b35c43016355c9de79f236137fa37592b0962e0418dab0152fd27bf50796540a5bd012c0dec45c2237b3e38e7471daa2c7723e0fc8a0e63271a306	1580164803000000	1580769603000000	1643236803000000	1674772803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd0582b959cf1753a76535822e8ab015b8b651b095d32a6e0f78761c5bafae62a5919bb088ae18028f13ab3ee03b50704fd1282344526b8da4c78be9cbbd7fe19	\\x00800003cece777297da2b31c8f12ecf6d155c0947ae8972c96fbd375a690cd033d87ed230562fdb6e8369d0db18f4f219ddf33572c8370678d8165bb33ec87d847a0997edd905dcf16ef23e91e19fba867542bd7487e2411683ab357609b7598c9d8bcd079937541413b08c7dfbfbce25d9be619b29e268830f382594a38ecea247a5cb010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x762fa3527de1ad67979ae9cf228bdce0691b482d188cf2e6ded29f0bc9b92b18a99ba6fc58d1e182497468f528c889d7f55c26e36bd8cf18ac5a6ca2cdb0ed0d	1577746803000000	1578351603000000	1640818803000000	1672354803000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7cdc714505b0e7fcc7fd7f682cc9789420decd8ab3982cc4376135597c23f201e7cce9da921814d39d52473568d67ceedf3f40cf606441c9906938b1e7e3a2ac	\\x00800003f0076b3c8aebc2c687b84a891fdbaf3729ea57d823d3685d893fdb5b34ea02aff872dfca29330c75b851881cd8f2f1a7e4f7270ede4eb7fcbd8e7e30bf97d1ad137c03fa2fb6f07b510e90eca29b2ec812e4e2be4a454435eb37ef3d5f034b48239a0b3a2cb157d2a94cea74349ec19b219549fa59abfb56d0bf845f370c870d010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x4a7d40e61354a75f4e065b3992cb703cd962d414a858b30c6dec053bac9d37874cbb90268b119fe88d898926decbeb4dd84bddf6550419fd05c78e82bf474d0d	1578351303000000	1578956103000000	1641423303000000	1672959303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcec21cd95caa25a124852315119e845c33f40741a59a6227e36d858fb7e994629bd9b45556d79505eae43670fab9818be99ebc65142c26d7ce12a706d60fd005	\\x00800003d6f0750eecf8e63ff2b85d14fbbdfcf33b0b323c1329b58eb17d4791ff4362a1fceb1452aeb3adff45363ca0ca95476356b05c763c04701b1633394aa854c38a4f0a06443c59a71d9aa03cf2e1e846c1dc965a6a1c9805133cc9baad716c74b3c3a54f721631f337f62d823ef123c099e9ecf44309332a8d907f36a0f11ae8eb010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xdf1f4f2c2a3c2f3d3c2222181bd17c652841404b5f21a852f1e5aa80090a28ccd1defc9e9ab3ad007029437803991b978782f62e011c00097f5d04fa76f21e0b	1578955803000000	1579560603000000	1642027803000000	1673563803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x63975a1e6527e124690a39f62b7ce71d0b587b48c020779861466aae61333956b7f4eebc5631effc167053f5a1f2a035f0dc631631c8bfac5a55a32b4a84e116	\\x00800003b091b06aa7349a1a9eea831d326d586b70227f20b1e19562852f5c225b72562eeb9667bb31049625f2be368b4e53a6948c98b101e29bc047b886787421d8bf7417a6981871a8866ff64d3e942e1e0ff77c1c509e04ebe0c148f287ed77033323ef72f9ed441341f29970202a1e4a431e3aabfe727e12610d7e1be72522635769010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xe88fa7c8ae63b0888abc37bdf0c3780b2b6c31791c1a30e8dfc3e242469567d740c511b70f93a9033e570aa937c3ad72c3bac8854b3118c1a31385745f79350f	1579560303000000	1580165103000000	1642632303000000	1674168303000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x17957fe1218590c965606112b6ec28ce5f55d13c5f2c297edf3b11f20a893bbe4d6d85dc3a66c1e7a49bd3946a510685b4dfb12a6f4e23fea40ed652d48c3ad5	\\x00800003d86a01f61443c511e79482a9c9ae912be319789de63d5d6b358bf61b9346332f19bd25d41bd08cff045c1414fb8199c54f079d2f2f907bc99b7a7dd7efa84b023b0e9344ca083b9b1df8c9234927212dcd5b0cf854219b406d6a59d5aa293c3e36974884334dd11aa1102dab203fbccd94c3e7a0d2946c2a7d0700053d7978a5010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x7c2e8c3ff1e72bfe65908117e87529ec3b899f55c52816049de19d857d45c53a0877ccf9f1881f4b7da87f837a4ceaa61910fdcac9aebd5f3b8ec08efc75c401	1580164803000000	1580769603000000	1643236803000000	1674772803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x008000039ff9d315ba8621f494e9b6c6107ffc6e797c8a38048638bad9c4ead0c5f90f4610324b29a9e169b1a2eff5a21d7447af10dce0c62bfae6cdf936454203625f057fdb8f699eb70996c4905187a13975056172c344385154e573548bf2ac14e69ce848eab2e05917c74b05e3ff4ffea6b3bd4ced207ca545f4885f1ddf0daf3c07010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xbc2357e8514e8a07436ff21268a83bb4fe09cf0dac79a8328fe2daa800b535c3ccb1c5d88946cf76d5ca6683d1798bef29479d635d7bf08bcc99af2ab34ff800	1577746803000000	1578351603000000	1640818803000000	1672354803000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x97de1aea377a8dad7e3ea8be281db0aa29588c8da16221f4ec1481b1505019362a235b9017de3777093093b003d828a348fa8a0e95b3328798504889be972c55	\\x00800003bb87f4f5701f5821e8fb0dde05d4570deea3c9da30a0be73c67d32cc2071ea6b34af45b20293ae84325b35e6c52608971736d58038ca92e4a79846c0b496f8355b721bcbad9ffc89af4df5994393ba24ac624cfbdf71ff434ae648d5b049a998ea9ce71ed6de6884de0d1e28727b3c80a8243e90646afb47dd4df7543d52aa4f010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x2222b454c0e6c41895bce76b4d58dd3426d61eefde923a08c89f60b36be385b928e7e5d5596aa24819b390bae3887eadac6f4196d2145a605c102c0eb1ef4f0a	1578351303000000	1578956103000000	1641423303000000	1672959303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c4d3f14999c37193148c7f042bf55e4ca2672a3ca6ba09783167b0a68b8372330516fd46470b6a1e0ac54f5a86c4d37e07b287127fcdae1a3753c4f21881796	\\x00800003c4fc3e89852e9d66db50ca4333b92aec5d7ba34ba6fa068d4a2a424ee0b87f2bf5ad98b3859741f9f4aab6f3f459b4ca64eed36f778bb6329fc693c5393b8a461ca1b1192700a39d03bb80432d4842ed973ea8edcb20362788c2a63ff616ba96f2eaa7fce245fa0e94865f3c4f87646cadc9406086dc64aac9af84ab5a514baf010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x01ee9832e2a941e12fcb6948d2ffa59aa499e0ad63c3272ca7b9ebb9440ae4cb93d672df01ba263f0be1a27d6c87a6e15b8cce4c6efff1bc0acea5d5afda340d	1578955803000000	1579560603000000	1642027803000000	1673563803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e9aaf95387ae09fc763c32d5ea615169b04074c5472f0b4b3bb7698a91a92f70d68eb84dff9e88b919c80b561c803f21dd523246a1513f1be41a8c0907fc7e5	\\x00800003bba4eec4ca93df3c937299441a9400ad0a10ee04b40bee0bd37f70c7c32d7fa9301e591c9ffd3af00d45937c74572f1e8bf7c3ae01706248eff83330e73f8edca9f14019b9d3493d2b160540c3014d370f1ee76724226e4ad7d0ef4842922c8e51cb578d5640aedf1ef008a336ac51183f1445b5a7a3964ff5e0f15a0ac44b89010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x4a6e385400e3b932eb00bdd9c2d7d0858ba6026b3b0a4b8d72f55db9fef2103e5de06431e284b0eca24df8e6c62b15832a1b60b8629638a58353ea312da4cb04	1579560303000000	1580165103000000	1642632303000000	1674168303000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2fd55aa16c0dbaf06cbc6f942df0b7fe2e802a313b424b25d0b1686b737f63ae751fc613fd7d8be7e8e4f8e32d42555e525b2ce69df82808e73a754bd5aaf9a7	\\x00800003b9e60d0e6b5973c4a8bad6214d6938f6c524dd2268164fba735d2384e467762674164f139a4d1ece3fdfc27d8db4c4b8f55cb37dfcd7efaf32232e541dd61762dff3e8acb0ed8e7bcbe200372bf8d471e7679db52fd05355502a5c35d39fd9167ea2e6c1feddfba486e17b084fae85cb3d7d13da1eb6ffeeb9c0f60b2f78d13b010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xfa3cf45f9767774afb9c879ec9c8fa4ceca722d954387ff2cb66b0ad5449d8c135c8a5c629a1a8484cb8351f19078fdef302ec35d8c84edfc51dbedcc82a0f03	1580164803000000	1580769603000000	1643236803000000	1674772803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x00800003eebf52497c20f0ee82cd4288bca3684f32f95778fb5c0c90fa7d7874e9a57adf4cad0749f5859f088549c83ed609913338bf792c12ba45a2e3f96c2aa587e3451b6b9eea48a8354a80ab1ef03c8af2ebfe022b4056c383b47a781555da84f0ed226df7f7b2d4b53b36ef50a6c222e6d1e9c60f11fe4479d09c48c16bdc6b7a5d010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x3fe0d1ca38e31499d5c74475ecb4c19146bd336335cfbdebfd132d1a3ba502061178c587e4b8adf9db2bd684be3b3ed90eb4a2c51e58714c02e7875c77b4d006	1577746803000000	1578351603000000	1640818803000000	1672354803000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa9274eb903575b9ef831c918aed1332b826e7c84012fb07d6aa53418c080e9371c7673b55c7a1d883e7d4bb5c085086565b621c969c780e6da1ff9bdb3904e9	\\x008000039d96a8d1b364289689450243cbb73229243e3664f45b4fcfc4a8c925f31e49ab2f3944b6dadd138653f912183b575eab1e8d512cfc684d4f9e442cae711d80ec63302a4402983e4aa6312903284df50b2d038d44fa2eb3bc2402a8b19f01bccc21675a0033920e0bf4f50d5f971570470df77613181f175a5ecb7783db950c8b010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x4ef0c8cb57b3ef83347e90f22e33a58f2f90641580f310061d910ff607d015151e8efc9d35b71ceda714aa4a1f6956fa50844e48c9e2dabd9dddc0c36f46ff03	1578351303000000	1578956103000000	1641423303000000	1672959303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9321c35d686d4fc92fe8c0c1ad2c375ae854b36048813f589c4dc133788e2bccd2c465fa47689fc2315bc43567a49f0f155e8ef0b4a5b1a1acdc383a92057cb2	\\x00800003c4fa4a071a91be7a09428ca1f2e632553fd9d9f3891236f1e2539661509af5e2a0e78747f6f9196a10d1eec4067d8b0a9a7171ed9a97e75903b21494fdbd3b68b24848d14ed80e59aa1e0a4acbed9c71c0bf4698c988e3748a159cf08087a5e1a1f01c383a4bc2bcf07985cecbc826e69357de4acee7d394184317276fce4429010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x9ed42acff25638a7b7847b94dcf6d8d20b6ccdae7b5a9d69ae2ac9a4b5152121506448ada9639b0c6512b294363711fb4cbd8b62e8080bff460abef41dd1930e	1578955803000000	1579560603000000	1642027803000000	1673563803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa2c8ce1f094747befbe01ce454845cdea5b0df9a66ed9d43e4ac95982e4e60a5d5b62615aaddad469c29678c534229436ad02a4c083317b981e1cac6666bba40	\\x00800003a6501fcfbda56d512142a8a2e7bbf5da64612d54640f4a71e774b7e2c5729ddbcdcc7593fe8b2468294a924bdc4750976c7418b290ea1d4b4f8e672d2460414064ec8c460568b403e0971cec72e2c41c86354010b6318bb672acf9046439a49128eb72e4d845dc71154cecc56273672448edf0772079a6e183050f6f701397bd010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x59d710f62237f57418920a03511275fce7ff41eb050be953c34936341f482f8aa3c7a0b160df25592f07a97c7382535a07b53c5cb9dad8356f2c43bd3e492608	1579560303000000	1580165103000000	1642632303000000	1674168303000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1635aa5f65f58458f90fc40d2850ad229171f0aefc8d5b1dd05862e53694dcd0556f73c1f4087a040795f4b2c4a2ffe3bd8ac197976e343bf7cef4c8b6d8ccf2	\\x00800003b190e38b1533ff6d5e7e334c2bac04d82338b15fc90234c270da1473c7fff9280cec35c980de11994afd082ac941680a8562c653b8ba30d3dea8508557b05c292d7f553c04f51caf1b95ef499fd769620a4f45a86b5a4be5bf3e394fad3362edc69fcddffb0aa91662a9ccb7f57f67dc113bf59cba11c9cdc4b20128022cf2e9010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xa7ac7721b3565c31fa1c0d49a137894f8a1b79cf9be2233cede2ea6ddcfc0482874d38e18a637f9b672693b6ae840ccdd45c62e3fef942a8554dd20df58fa309	1580164803000000	1580769603000000	1643236803000000	1674772803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa804b3cea4b878309c41e49a9bd755f08598bbd71a0785dc267717eaa40ac13fff6cad9114a08e5668514d6ced03dbc6dc7e0b0ca2bac2748893e99dc32a8b47	\\x00800003dd4bc32aadd59242309fb18bcbc4a1c85c79818e96f46cb7b56e8ec95370dcda0f73aad5f2f0983ce823af452b79e9bde337279aaeeb914a379d49e9a1d2d48fe27e0835423f773a12ea0419d15ba768aebe7e128540a2093f9354f99daad80cc31e423692f44d86818e3684c7317f9ef7ffa233650f3a6ee9fba4a74859a0b9010001	\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\x9e7a67ecdad1314fde9fd9f5178e8471c4789a1ed2d2b05b19e4f3c73b746fcdc9a637bb1a2dfc8a7299af30041f12c0a293f05e025dfa15f9a3c6122352b70f	1577746803000000	1578351603000000	1640818803000000	1672354803000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	1	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	9000000	\\x29607e0989de95e7a96b5f65c5d522f858593a77dbb4df982144ad18a4a61dc0	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xcf1c92afa0c165924ce4efaf52e2b3264e4d115c3280cb1420ccc233c32720be7985ff6eda611969c06573f568c8dbc0dc40c017c51b19d28acc91d22d788705	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0d57fb7fe7e0000e9beffff9e550000c90d0098fe7e00004a0d0098fe7e0000300d0098fe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	2	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	9000000	\\x157327ad8b31308f9f46bc97ae84846d80dd116948f692fd02d8a07916a25bc4	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x260b00a284d831e6c537f67c9c91b7a4d085c93820234cb90659e479aabbedecaf63f7c23967cb46a49e842a0eefb20d29dc6c2091a3c304abd072fb69906e03	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0d57fa7fe7e0000e9beffff9e550000c90d0078fe7e00004a0d0078fe7e0000300d0078fe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	3	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	98000000	\\x02dffb26ed29c2390bd780f6b5b3ccad2313a3ace8967b06c4cc032d89253443	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7063d239d9d9be29711eb0886f6f28e32abcd60f9717543e1d7966c8ac5429b4935188c5d6c61eed671504b0fac0d11f08481b2c5107771d739f5dce1bb92505	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0a5b101ff7e0000e9beffff9e550000c90d00e0fe7e00004a0d00e0fe7e0000300d00e0fe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	4	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	9000000	\\xfbf94d68d28833aa7c38fb25389ab7f9de0fead6cf0e1af5b8a13771f6f4c831	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x4b9aec5e810c7d4b7dbe0c6fa7c022f478b348068fcbc91bd1be930c76616f0bd2bcbb9f5c37819a4dd4b2a4125bde2f083c3c56bd60533e56052f5be462ef09	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0d5310bff7e0000e9beffff9e550000c90d00fcfe7e00004a0d00fcfe7e0000300d00fcfe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	5	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	9000000	\\xc45ac7588d71d3103bddc0f81452bf1cd834cc2b86624c26bb2f1ced85aa1f36	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x9672a6a9637f82f533159d57dd747e3931091180340eecc4a6ecaeeb6a910e773ea76657f5dc3d47f707028a95d7db047cae788b9cf87229dce764c3133a3c0c	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0b57fb6fe7e0000e9beffff9e55000039a50088fe7e0000baa40088fe7e0000a0a40088fe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	9000000	\\x46c356971b4eb6c2ff0cb52b46a6752a472fbb136eea37edd468d1dbeed579fe	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7179b78d1cc2d3c996cac8f29fb022f2f0d24f520d0a99dcbb7a628b74a29c126369aaf15707fd4043a75de52a2eceb589d7b2da0f0628ba3ee1700890f83308	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0c5ffa6fe7e0000e9beffff9e550000c90d007cfe7e00004a0d007cfe7e0000300d007cfe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	7	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	9000000	\\x6d3620e6549eefb6848cf9337e55861c5d2ac7319b2fb523e6d1d674db038ff9	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xdde0d4f3e15885b42bb2523601e8715c9f83a564918f3ea9f97901b976c54fc46f6b89dcd084b29d75b6b306b0c31389a3b8c8d2e244307327a1341746b1fe03	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0a5ffd9fe7e0000e9beffff9e550000c90d00a8fe7e00004a0d00a8fe7e0000300d00a8fe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	8	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	2	20000000	\\xca42211a597cfb949505abe80d8cdc4b6af3e272bc4e7602f11d7a3a6bcfb946	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xc69092b053366b0fdb9373efe4143307b696cff68d233ccd9a526d682ec75c82e44abf43139aa283aa4379dec38de77d8cb703ccbe77576ac811fdfeaedd3506	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0b5310aff7e0000e9beffff9e550000c90d00ecfe7e00004a0d00ecfe7e0000300d00ecfe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	9	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	9000000	\\x99349e5294d2a1eb148a630c999b0d43495a7529ed219e53cfaa708097043c05	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xda0c70c5cebc95d60c7aa354cb51d3c8e966b8b499baaee66fcbaae8db95f0488b4198b224f6a827f09e85a5de7391966ee7efe1d657616177cbf53ab2eb7809	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0c5ffdafe7e0000e9beffff9e550000c90d00b8fe7e00004a0d00b8fe7e0000300d00b8fe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	10	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746819000000	1577747719000000	0	9000000	\\x7b67c19fad65b46b671d41cbe811f597ace1dd1bca0713960f0b91d9e0fe1199	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x90398e4ac5f517161d3fb18c03b70d0957a85595050b2ef7156b76822f3ab6c9b699dc0b9123b572d8ba85bc4c4b2099615aa1b857879ea5a813dda10ab9bf01	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0e5ff03ff7e0000e9beffff9e550000c90d00dcfe7e00004a0d00dcfe7e0000300d00dcfe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	11	\\x42b8ad014f7dfa280a058ffbd50a7ee8cf4568988b76778d6d408d9627d688bd033fb683fa3711fc15622b46d914cb29056a8955850efdbe695435d8d4e5196f	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746822000000	1577747722000000	6	99000000	\\xc2d6e7d589f4066a2fc347ae4ebbf4ca3553ed8710a54fe2eaef78c48109171d	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xca5c7f70e6cce7ab1fab3fc9dd66a5a7ebc7b59dc5ed14afe4441d9e8a089e21ccd1ccf7ff24e2d5bc2cba9b931ae4e9f9d99dafaac178239c98491775013306	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0a5b101ff7e0000e9beffff9e550000794601e0fe7e0000fa4501e0fe7e0000e04501e0fe7e0000
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	12	\\xfcff7193a6e1cea6cf3a55c4f351f1ac0d81024e87fe5756deef7bbd2de7f893c7b7253f9e6da91093998cb6b5d6189118fc400ed9c1c9116f7f7aef0a9d0e5f	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	1577746824000000	1577747724000000	2	99000000	\\x365e8c0d608f4d326e686e06638ff05fe4fd47933961a093530ec44cce25e032	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x483d4bf6bfcf6ce57096e4a9fa0d977e595695dca4c35d78ed36bb51c246f856e192db84a8b4fa652f1bef0c11afbe19fbc94d9357a89805c4166e66778daf0c	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x16a5d10cff7e000000000000000000002e16c60c01000000e0a5ffd9fe7e0000e9beffff9e550000b94501a8fe7e00003a4501a8fe7e0000204501a8fe7e0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x29607e0989de95e7a96b5f65c5d522f858593a77dbb4df982144ad18a4a61dc0	0	10000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x702f78474a9ef9e2def286b6efa4678278b115b98999490df62a8d8e7030fe7bcbc789f2d1f860e60b68b6127010001fad0ca14380b8028cab5a9fc445590903	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
2	\\x7b67c19fad65b46b671d41cbe811f597ace1dd1bca0713960f0b91d9e0fe1199	0	10000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x976267ad61487dc314f353daacfd82a41231408428aa92d22080dafb9badfb8b2db8244aba64f4c96bf08eae234c30334067460f888b8533aa7a0882badd1803	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
3	\\xca42211a597cfb949505abe80d8cdc4b6af3e272bc4e7602f11d7a3a6bcfb946	2	22000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x7dd8e9917622b721abefae041f608237bac61beabf93488f8e9f6b5143c6f340d8b00708a31bcfaa0b766a10d256327ed52f48e4274403b7994c5e86e1766405	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
4	\\x99349e5294d2a1eb148a630c999b0d43495a7529ed219e53cfaa708097043c05	0	10000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x3b1052d13390436eb9282b77acc5729e4b05ac5dce2f0f7b97c8541e984c14a54c3c5831f456c37cdb7613ba591ca544d58180a868e620f7fe3b34b59158fd0a	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
5	\\xfbf94d68d28833aa7c38fb25389ab7f9de0fead6cf0e1af5b8a13771f6f4c831	0	10000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\xec5c9247aa79a41e6b361978bb88af555cefedda9ab13e59dd21b2a30aad901b41fbbef919d7d5cc123ca6b70e001dd9ed6d68b94ad2674291d0531af409440f	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
6	\\xc45ac7588d71d3103bddc0f81452bf1cd834cc2b86624c26bb2f1ced85aa1f36	0	10000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\xb5e983f9d448d2ffafc9bfbcf8f209be81d8a3a2abe104e5b0b94753005fd13ebdf87e1b5a725d9ebb356a2d4a34c5171bf2fb5fc5f6a7dead920f7da66ff506	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
7	\\x6d3620e6549eefb6848cf9337e55861c5d2ac7319b2fb523e6d1d674db038ff9	0	10000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x2f6125f4186d59dc511ef057d562797df53b0f8854974c8a5c59928262e8150e1747450ebdb8711ca2ac802c140bd0f9bb87a6841e1bb5a22369779e5b95a80f	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
8	\\x02dffb26ed29c2390bd780f6b5b3ccad2313a3ace8967b06c4cc032d89253443	1	0	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x7a50569ac58313edefc2239ad6abe6609143713b4f16f7b2f0bb417983e380983dcee2c7950ee3fd498ea0821311ae90b9aa74c3b95b75e75d89ca957de71e01	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
9	\\x157327ad8b31308f9f46bc97ae84846d80dd116948f692fd02d8a07916a25bc4	0	10000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\xfc2f7621cf00197560c1fd670017a0f03c92d8a9a64e76ca49eb2cb7aad0431b503af72ae742a4e8b2bf0185f253a7f7eda1ceeb667e7106f3402cd9c7474000	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
10	\\x46c356971b4eb6c2ff0cb52b46a6752a472fbb136eea37edd468d1dbeed579fe	0	10000000	1577746819000000	1577747719000000	1577747719000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x8aebcf62d12753fbe63212af343d5875b879669c8ab63a0c80245da2eb9aa1b1babd9b95d42b20d64b67e91499fd8665169aff8ffb0f40b868b10c49ae1ee704	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
11	\\xc2d6e7d589f4066a2fc347ae4ebbf4ca3553ed8710a54fe2eaef78c48109171d	7	0	1577746822000000	1577747722000000	1577747722000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x42b8ad014f7dfa280a058ffbd50a7ee8cf4568988b76778d6d408d9627d688bd033fb683fa3711fc15622b46d914cb29056a8955850efdbe695435d8d4e5196f	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x1dfbc73af1d36a61403f27d81fbc937acb3306f59a42a93ee9303f4c490d5117707548159626155e6151365351836480302933c7bb4e75bb7b807ae8fb8faf00	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
12	\\x365e8c0d608f4d326e686e06638ff05fe4fd47933961a093530ec44cce25e032	3	0	1577746824000000	1577747724000000	1577747724000000	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xfcff7193a6e1cea6cf3a55c4f351f1ac0d81024e87fe5756deef7bbd2de7f893c7b7253f9e6da91093998cb6b5d6189118fc400ed9c1c9116f7f7aef0a9d0e5f	\\xf6fbcee37955e5ea8021afbf7a555c5b41c5d0e08487df016815f0785a64cd8cce35bec80501f18922b887eec76138b145aea607bbeb15c2ddbc0b87f7d3cde5	\\x1995104c58f666b0f72346fe5794843aafb52a369bea91af6067f69a48af6a1485a4a55ac7444e8fb342958e443aa2610d221738147a043cec5dea5d5cdc2b0b	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"D2PK76518CTR71MDQWSH5AGWHPK6590C6R6ECAYSNNX02PJFPQ1PCTG88M3Z38739X7AY3ZSGDMNAJ5PAWXM4MC4P5S2D68EMM97RMG"}	f	f
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
1	contenttypes	0001_initial	2019-12-31 00:00:14.642347+01
2	auth	0001_initial	2019-12-31 00:00:14.665782+01
3	app	0001_initial	2019-12-31 00:00:14.708258+01
4	contenttypes	0002_remove_content_type_name	2019-12-31 00:00:14.728154+01
5	auth	0002_alter_permission_name_max_length	2019-12-31 00:00:14.731711+01
6	auth	0003_alter_user_email_max_length	2019-12-31 00:00:14.737705+01
7	auth	0004_alter_user_username_opts	2019-12-31 00:00:14.743526+01
8	auth	0005_alter_user_last_login_null	2019-12-31 00:00:14.750471+01
9	auth	0006_require_contenttypes_0002	2019-12-31 00:00:14.751805+01
10	auth	0007_alter_validators_add_error_messages	2019-12-31 00:00:14.756978+01
11	auth	0008_alter_user_username_max_length	2019-12-31 00:00:14.766172+01
12	auth	0009_alter_user_last_name_max_length	2019-12-31 00:00:14.774954+01
13	auth	0010_alter_group_name_max_length	2019-12-31 00:00:14.786777+01
14	auth	0011_update_proxy_permissions	2019-12-31 00:00:14.793078+01
15	sessions	0001_initial	2019-12-31 00:00:14.797552+01
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
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x6fcaee0a5c8c70c14c67e6df24900c461be544afe201476c34ee8a20e45723dd950a4351633713be159cc8bb67b3af10378e6d6746a28b14228bba4b020c5407
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xfea6d3f62b528a161cd8e326ce872c959adfd1d2e92cd5e9a70f8076996a30420faa3158dc008b0953eef9c48ec1a15a74766e0cd685ba0dd662a46e1c6a7801
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x88588b54317fe9cd3948f86c93c8a8d820a996934f5cff3f24bd5a860431f76a96f27a5a6f3474f6a5aaa92c0bfd4ce0e1d6ee8853013eb61820f9acf1beed07
\\xcbae3f68952cf02270577229707bf9195bf9184355b7935636285f24f98318de	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x505722f3da7c72a0555c667b25a04e8bf74ec377c29143bb9d7856646d236006764ae762aac9f983a98b1cd7b43ae2e36cb83440003bebe695107fff268fa30d
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x29607e0989de95e7a96b5f65c5d522f858593a77dbb4df982144ad18a4a61dc0	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x61ef95982b211178b1ad920ce945afe2dafab1fe17d6ab03e93b018cee040b1c2f624c13aacb5ee01bc652c7122b53986dd88c7557bd6c7537b23ac2c10c0a7deb991e094bd4fd5e0dee74d240b1cce5de892f874af86cafa098360f6329ef22b684f229b51182fb75e6c428949515992b52def29eff5726d1abc2c946aebf6a
\\x99349e5294d2a1eb148a630c999b0d43495a7529ed219e53cfaa708097043c05	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x493cfaffe6da9d941d13d7ada349a79b1d641d40981f4aab5305b0bb7a0cbd3556ab1d5d347a06fbd358c0cfc9b1065d1e77d933d5e1f928de1a801f55a2ebe9f1751cf10d7e05b1ae5b2eb389e01d2b255b6a68885d9be652eb0b83403b2dd7b36bd5abb7522b3494e65ac9e24445d8b3a9ff3d09c31f672803ad0b7e078394
\\x7b67c19fad65b46b671d41cbe811f597ace1dd1bca0713960f0b91d9e0fe1199	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xbca083f63989bbbaad2c130e68b6a4b8e1ae587d6301b98882d571f19eb1a07e07aadb57b91803aacb714696a2ad95542205b968bca1dcba803ca4e1dcc7c79f3b457994f87db1968cf360dd9d678d93cc3a50cf6e966b7ea8de4203968ca1eef27841485a0bc57e7384ca58d8e4a0f6e4a6eecbeaf0c28b7328d714e7692e70
\\xca42211a597cfb949505abe80d8cdc4b6af3e272bc4e7602f11d7a3a6bcfb946	\\xa804b3cea4b878309c41e49a9bd755f08598bbd71a0785dc267717eaa40ac13fff6cad9114a08e5668514d6ced03dbc6dc7e0b0ca2bac2748893e99dc32a8b47	\\x0c32ce4924b106ca749da25cba3e1fafc922ead779e1ca0bbe5c28562736a0413cd680afe48262ca3941b2ecd91baa2c35e18d06ad5d75dad3eaa00dc82d2c63729bf7dfcbae655c64c82083a319b74144d56b093424f62e512199c2e1465d07d1c1b4670437ce507c41861240098bbbe89c3e7df2f640bcfbee2bc1b3ccc408
\\xfbf94d68d28833aa7c38fb25389ab7f9de0fead6cf0e1af5b8a13771f6f4c831	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x496b425adf7078aa03fc84b6fd42c7ad72f9e57a08448afc71fa4165fcc94e6d966d39df51bd40ca8713d94f5d53d9ba2bf801e55f954ad04f7963cffed1cd65de7a384d1331d356fe7d0d6b42429a305b7ee9096d8d81defda21748ba69e9de3cfd1bc6f6302590684d7742eefe4bd6822de64732e60d44cc945c9d1d5a7de5
\\x02dffb26ed29c2390bd780f6b5b3ccad2313a3ace8967b06c4cc032d89253443	\\xd0582b959cf1753a76535822e8ab015b8b651b095d32a6e0f78761c5bafae62a5919bb088ae18028f13ab3ee03b50704fd1282344526b8da4c78be9cbbd7fe19	\\x328b8a5168ae9e0854eee5f34626abcb36e6f25d2c4a8c8598adedf1eebcd9acb759457be28bab202a304fef2cf38d3171f644c73c3c8f7082d094b5aa2ea5c586fd15a79c59e68aa41fa8745f90fd690617f04abf277461a3b39e5de4704ea65b9ab7b81a8b9a7cf7f0d903c6cb9d90af394d56c097c42b2c256b7f0d09cf4d
\\xc45ac7588d71d3103bddc0f81452bf1cd834cc2b86624c26bb2f1ced85aa1f36	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xc643d9ecd05f29aa9ea778870e90b0ac5f9912582a7f42f03d25243c21fe97e52caac13a80db3d7695aaaacdccb43cb8c417f26b03e4091f9dcd15ccfc290541ca3328c8ea77c63b3b2f79db83124e34761a057fda9c6301bd46b655b5113da1c180870b7109b79f963b6000c1a522d750e7faa37589bfc4789ad3e7ffb1ebae
\\x6d3620e6549eefb6848cf9337e55861c5d2ac7319b2fb523e6d1d674db038ff9	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x116304f015e92a1da753aa13f9d0a64b11743abb35e10f7fad1e3080027fcbf0d22be12c6181e4301360fdef5c26a24985a4ffd5f6ec0392afd0bba1686da4c35063c64e4236871ade765ee3a5127981abaecdf7af1fdc8400a054aafe837d0eac0081f02e8d898199871e60a9eff561c1970a824d436b3808ef3e12a74d14bd
\\x157327ad8b31308f9f46bc97ae84846d80dd116948f692fd02d8a07916a25bc4	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xa2bd0b91be3c186d606f3e09b9448ecc09f0d1f98c65e01b2ee0aedafbda7bffaebd01c538f9d395653e33c9c6bdd85719478f550d425d229f65ac85c069b87e5232a41a1f312249f4dc8d7c86f74d6d14dd087ffc9a241c20d28cd3d3c1e4ce64a9ca42f72d584490386821df649a5173604e6f1f1551f00d8f46a4d78adabc
\\x46c356971b4eb6c2ff0cb52b46a6752a472fbb136eea37edd468d1dbeed579fe	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x2478fea40d3b50f83dba13beaa1d99f4059295b0c48703b1bf8e3a534ea60d5c332d3581054e9a989bc9bf02e91124603fa67b007ffef165e7470812c5d8fb6a90314d058750d43ba271c27f7c7815253f13897d3e256e7bc364913dcc96c919aaffec9c483c622afbff4b1e143643ff7ed283f5b07247756d0b8ea4aace8238
\\xc2d6e7d589f4066a2fc347ae4ebbf4ca3553ed8710a54fe2eaef78c48109171d	\\xd2edc4e40daed8637e70e4a18ce45c3b827ab46c6d613dd4b82a3c33bc8c5b435b1c89010b4606e4240dbc9e4a44b4b5891952cbe3c45cde0948c8495f6c8c43	\\x7273dbae275927597908f64e6272af2c3b1c71b66035923c7df4ff4a2a3f784ec82faec320dc90d92a671d9e2741d676d4eadeb8db35840e55b7a914d42a4615e0e8bee745b95915bc9fab435c8f4b669a5a5fa778fe1da42615992782a641bb989cedfb7ce3190d52f3ee0508f67ee9df2d94d752d817f878b0a89a13d60e98
\\x365e8c0d608f4d326e686e06638ff05fe4fd47933961a093530ec44cce25e032	\\x024eb8c53815d70be16003b1a9c804339a53c69c5813cf66d8ff1e691368dfa737baa4a874217706dfdf1e9e18d59fba7cea1d2e534abaddc68b69df090ccc9b	\\x36bce10ff4551c048e7c41ed329c55481744877a0605e50f903a2261dd706e0b1b2b0ab76486ef717c53d42357da2e93392b8abcd93725a7eace6fa97a55743512c63ca9a36ec83f1d69527121c2aba01f1ac6cf7826a4244e3b0f114b10d875c764c73c2e650b463d862acf021789e5a85ffaebbd3bc0bfcd948dbad391f8d1
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.365-0143HZGK48EFY	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c226f726465725f6964223a22323031392e3336352d30313433485a474b3438454659222c2274696d657374616d70223a7b22745f6d73223a313537373734363831393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333231393030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534551335954344e354b52323457325145384d5130595a533335445a4a36323341505653364e48503531464a3959433333334630227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22595658575852565341514a594e3031314e595a514d4e415742443057424d3730474a3358593042383251523747504b3453503643574444595330324733574339344157384656503743345742324844454d5233565154524e5242455652325737595a3957565338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22454b4533473953584542395841453354475a56394742353438575444595652543335353835343154434738454a47355631375630222c226e6f6e6365223a223358594d58365a3352365a46473044414e58325931474b4e4e564b424b5151395834334a32305433304a32374752375043504e30227d	\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	1577746819000000	1	t
2019.365-03W9PPNQZH6TT	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732323030307d2c226f726465725f6964223a22323031392e3336352d3033573950504e515a48365454222c2274696d657374616d70223a7b22745f6d73223a313537373734363832323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534551335954344e354b52323457325145384d5130595a533335445a4a36323341505653364e48503531464a3959433333334630227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22595658575852565341514a594e3031314e595a514d4e415742443057424d3730474a3358593042383251523747504b3453503643574444595330324733574339344157384656503743345742324844454d5233565154524e5242455652325737595a3957565338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22454b4533473953584542395841453354475a56394742353438575444595652543335353835343154434738454a47355631375630222c226e6f6e6365223a22464e3142314d454e3837393137475452475345353831504a4b47564e383045365a504e544b383454414754394842414758325447227d	\\x42b8ad014f7dfa280a058ffbd50a7ee8cf4568988b76778d6d408d9627d688bd033fb683fa3711fc15622b46d914cb29056a8955850efdbe695435d8d4e5196f	1577746822000000	2	t
2019.365-02CB3FRFSQCDY	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732343030307d2c226f726465725f6964223a22323031392e3336352d30324342334652465351434459222c2274696d657374616d70223a7b22745f6d73223a313537373734363832343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534551335954344e354b52323457325145384d5130595a533335445a4a36323341505653364e48503531464a3959433333334630227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22595658575852565341514a594e3031314e595a514d4e415742443057424d3730474a3358593042383251523747504b3453503643574444595330324733574339344157384656503743345742324844454d5233565154524e5242455652325737595a3957565338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22454b4533473953584542395841453354475a56394742353438575444595652543335353835343154434738454a47355631375630222c226e6f6e6365223a224b50595a535442503357573343485737515635323654323036585a4842423639314d4b3636453644444535445a384e5142304447227d	\\xfcff7193a6e1cea6cf3a55c4f351f1ac0d81024e87fe5756deef7bbd2de7f893c7b7253f9e6da91093998cb6b5d6189118fc400ed9c1c9116f7f7aef0a9d0e5f	1577746824000000	3	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x29607e0989de95e7a96b5f65c5d522f858593a77dbb4df982144ad18a4a61dc0	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22535745393542583052354a53344b37345859514e35524e4b34533734543441573641304350353130534b31333747533734325a374b31465a445644363236423952314a513758423853334457315132305230425741365253544135435334454a354e5738453138222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x157327ad8b31308f9f46bc97ae84846d80dd116948f692fd02d8a07916a25bc4	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223452354731384d34563052594448395159535939533444514d4b3838424a39523430484d5345383642374a374b414e565851504159525a5152385750464a54364d4a46383841474558595330544145574447473933385933304a4e583057515644363836573052222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x46c356971b4eb6c2ff0cb52b46a6752a472fbb136eea37edd468d1dbeed579fe	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224535575646333857524239574b355041533353395a43313259425244344b544a314d35394b51355646394838505835324b4739363654444159354247465a413038454b4e565339413556374242324551504244305931483851385a45325730384a335733363230222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x6d3620e6549eefb6848cf9337e55861c5d2ac7319b2fb523e6d1d674db038ff9	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225651474439575a31423232563841584a4138563033543348424a4652373942344a36374b58414653463430564a585035395a323659545739564b383839434d584550564236314e47524339524b385852533339453448314745434b54324430513854525a573052222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7b67c19fad65b46b671d41cbe811f597ace1dd1bca0713960f0b91d9e0fe1199	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a305752574a5035594d42484337395a503636303744524431354254474e434e304d354a5858524e444456383442535450563456443645573145384a3744424a5632583842463243394347394a5241544d365735463157594d504d313751443131415756593038222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x99349e5294d2a1eb148a630c999b0d43495a7529ed219e53cfaa708097043c05	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225638363731484545514a4158433333544d444143504d454b53334d504445354d4b36584158534b4653454e454850574e593134385047435250384a464441313759324638423945594545385343565137585a4758434e5631433556575158395450424e51473238222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xc45ac7588d71d3103bddc0f81452bf1cd834cc2b86624c26bb2f1ced85aa1f36	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a53534144414233465931464143524e4b4e425854583359373452474a3443303647374553483536584a514550544d483153564b58395636415a5458524641375957334735324d4e545a4447385a3545463235535359334a353745454553363332435833523330222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xfbf94d68d28833aa7c38fb25389ab7f9de0fead6cf0e1af5b8a13771f6f4c831	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223945444552514d313148594d505a4459314851544647313259485742364a3036485a35574a3659485154394752584b3144573558354635564b58453346304354395141423539304a4246463259323157374842425452324b375342304142545657484845593238222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x02dffb26ed29c2390bd780f6b5b3ccad2313a3ace8967b06c4cc032d89253443	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22453148583445455356365a324a573859503234365956533857434e42534e47464a57424e3846475846354b434842324d35365439364d43385251424343375144435741473943375452333848593232383343503532315651334e5353595145453345574a413138222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x0f60856e1f14c87f206f1d2f7b2906a203e69372b59db8759fd64d68c8098c02eca3e112ae7adef5a15db20ada1891a5c7bc2924e10adb5e21138501a72248ba	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xca42211a597cfb949505abe80d8cdc4b6af3e272bc4e7602f11d7a3a6bcfb946	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22525438393543324b36534e475a50574b454651593835314b30595639444b5a50484d484b534b43544139505047425037424a3145384a4e5a384339534e384d334e3931514b51503348514b5156333551304636425758545144423431335a46594e56454b413147222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\x42b8ad014f7dfa280a058ffbd50a7ee8cf4568988b76778d6d408d9627d688bd033fb683fa3711fc15622b46d914cb29056a8955850efdbe695435d8d4e5196f	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xc2d6e7d589f4066a2fc347ae4ebbf4ca3553ed8710a54fe2eaef78c48109171d	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225339453759573736534b4b5450375842375a345854534e354d5a4e57464443585251504839425a3438474553583247384b524757534d4543595a5a4a3952504e514750424e36574b33424a454b5945534b5051544e47425234454539474a3851454d304b363147222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\\xfcff7193a6e1cea6cf3a55c4f351f1ac0d81024e87fe5756deef7bbd2de7f893c7b7253f9e6da91093998cb6b5d6189118fc400ed9c1c9116f7f7aef0a9d0e5f	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x365e8c0d608f4d326e686e06638ff05fe4fd47933961a093530ec44cce25e032	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	\\x90e6e4c8a38ba9436ea41bb2861e291abc7c973ea42fc306fc3aee6ea419a266	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223930594d51584e5a5358504541573450574a4d5a4d3343514653434e443545574d4b314e545937443654584e33474a365a31424533345056474a4d4239594b3535574459593330484e595a314b5959393950394e464134523051323143564b3645593654593330222c22707562223a224a334b45394a353348454d4d36564e34334553384337483933415937533553594d4751573631515737425136583930534d394b30227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.365-0143HZGK48EFY	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c226f726465725f6964223a22323031392e3336352d30313433485a474b3438454659222c2274696d657374616d70223a7b22745f6d73223a313537373734363831393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333231393030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534551335954344e354b52323457325145384d5130595a533335445a4a36323341505653364e48503531464a3959433333334630227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22595658575852565341514a594e3031314e595a514d4e415742443057424d3730474a3358593042383251523747504b3453503643574444595330324733574339344157384656503743345742324844454d5233565154524e5242455652325737595a3957565338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22454b4533473953584542395841453354475a56394742353438575444595652543335353835343154434738454a47355631375630227d	1577746819000000
2019.365-03W9PPNQZH6TT	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732323030307d2c226f726465725f6964223a22323031392e3336352d3033573950504e515a48365454222c2274696d657374616d70223a7b22745f6d73223a313537373734363832323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534551335954344e354b52323457325145384d5130595a533335445a4a36323341505653364e48503531464a3959433333334630227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22595658575852565341514a594e3031314e595a514d4e415742443057424d3730474a3358593042383251523747504b3453503643574444595330324733574339344157384656503743345742324844454d5233565154524e5242455652325737595a3957565338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22454b4533473953584542395841453354475a56394742353438575444595652543335353835343154434738454a47355631375630227d	1577746822000000
2019.365-02CB3FRFSQCDY	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732343030307d2c226f726465725f6964223a22323031392e3336352d30324342334652465351434459222c2274696d657374616d70223a7b22745f6d73223a313537373734363832343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534551335954344e354b52323457325145384d5130595a533335445a4a36323341505653364e48503531464a3959433333334630227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22595658575852565341514a594e3031314e595a514d4e415742443057424d3730474a3358593042383251523747504b3453503643574444595330324733574339344157384656503743345742324844454d5233565154524e5242455652325737595a3957565338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22454b4533473953584542395841453354475a56394742353438575444595652543335353835343154434738454a47355631375630227d	1577746824000000
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
1	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\x42b8ad014f7dfa280a058ffbd50a7ee8cf4568988b76778d6d408d9627d688bd033fb683fa3711fc15622b46d914cb29056a8955850efdbe695435d8d4e5196f	\\xc2d6e7d589f4066a2fc347ae4ebbf4ca3553ed8710a54fe2eaef78c48109171d	test refund	6	0	0	1000000
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
1	\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	\\xca42211a597cfb949505abe80d8cdc4b6af3e272bc4e7602f11d7a3a6bcfb946	\\x692cee2cd8c2e46295094f59e13b9b127c5184947b1d6055c23f60db1880459305dc1ddcc90c953b1bee0f4cabcbc1e8eb32dbf1dce9bcdf64e2bf9c554b690a	5	78000000	0
2	\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	\\xc2d6e7d589f4066a2fc347ae4ebbf4ca3553ed8710a54fe2eaef78c48109171d	\\x571dbbbfa15c4200fd7526d075340e03ae30e5a2ff20fe9d91e4c3a6cfc3112c75b6df9fef247d1cf126e207016e8cbd47b5b2763de52c3f17404edd79c9cc0e	3	0	2
3	\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	\\xc2d6e7d589f4066a2fc347ae4ebbf4ca3553ed8710a54fe2eaef78c48109171d	\\x69bd40f024fca5b3bbeb75c23e059bd975401a0c58289dd0ba5869e02cc0c5f60c14bf91c6dff75e7f7c9a52bc1d3e5a7d37997e906b086d9e31c7a87271110f	5	98000000	0
4	\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	\\x365e8c0d608f4d326e686e06638ff05fe4fd47933961a093530ec44cce25e032	\\x9b42d3c645f0dae71dcd50b2848ac526ced2342eb3d8c5189ba62fcd4d8bc69a3f26ec6a9682fd5f07ff5ac1f3e6560647a80718691955e2c6cb7f13d3d05707	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	0	\\xa86687e6fbd0acb14349f68d13bb4f7aee7681c2d7aea0f8323c48d4314c63d2cee5b0ded200caf96a5da313ed9c1a35327cbdb8eed4ef690086b8f20e2d7a00	\\x024eb8c53815d70be16003b1a9c804339a53c69c5813cf66d8ff1e691368dfa737baa4a874217706dfdf1e9e18d59fba7cea1d2e534abaddc68b69df090ccc9b	\\xa748c506418c7696170ab0f4cd80fa0b8aca54fdb36f36e402afe8756d8fe38740f194efa33e5c43ae32e6199a0976829d04564b19ba169ae02db5af8a3728816b4d13ed781dbd57074968b10c4f33b5a5e4214268236f48f7e7aa41dbd3a4f56db99ab9c5b4719b33ec88e14abe64b46eb50b57d575ba0e6f933cb22fb21554	\\xc5cb878eea51613af0970a688df6e16cbb585a63e605e49a2dd42efac5c5cfa529a2c7a092fb552737efc087c95e40d680e0c0a499461d0306a88bd8159c45a1	\\x0bc54136fdf9d9042579e3d055cfbb306631e38d41fbecc647bb651c46158f7e25058d407da272b1509bf455d2b248ecc70642dd243196ca3410a28930c905da1bd0aa309dfcddd8c3c0b50cb1eb8daf9a2171071f646d438207f5c10e0979ebd68aa76baa358b15d2fe219563023526c3944d4a8df49ca15d0755629cf2ff16
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	1	\\x264a5b292ae7fb0620d9196464d976fcfe08b0d899933349fe68626882b5bf2ff745d0be81cd8660834d9757c779aecdfb194608926544b894693ad4c21ae801	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x8d1786a68c50478424d44ea2aca79f0d880d6662e954f07444bb5385f5bb3c269aac05f4f6415e401b9e591f1e1ab265692b9d47554096fb71569a121f3467798bf9a95e6b5eef7968e8f3f60edf9335ef922457214c6e8cbaf77aa109ff93892d45bcf08961bf26df4e0ebeb703bfbd3ed52066a366bd33c52f577150473685	\\x5280e6312958e844c1e505d292030884ad9b22bf038b9798df907722a8c1f7565b0d8a3e9b1f7b4cb3a6375c44a2f32d10b140528279fabd7bd9db3e41803264	\\x38499580901e5898b25f72b2ea9947e41d6a30d8148a51c84534dd020a411cfcc6681a89ef19e2efce929a44b0ec17de80a9df87badb961ad81599b5758c943c58491be62ce6b7881ae9e24201e69e476f1fecec2a07a505932a8dd87cbc9092268e7e0a8cef44e1bb98278fb18666129b58479c775ab028f77531a25e8133bb
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	2	\\x4eecb45a25e456cfa0887019b95d67f7571a9103ac554feffc8a4dcdfde2c01647b113466da97cc10d621f4bc68731c29e33b7494446782cdd9c9267e45fbc0c	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xe0951011f3a086649cf4ba41de6f86dc2c373ad001e11664652fee908acfe0750c237e734ed5dae5743bdcbd82bbaa632bec1b8a672d928e03c68d3abdf6b642e2c188a2f7a5434ae6c32ac25b481e80c4f2fb575f5afa1d89218089fc7fbc1978684da4f33537a1966cabf56d78c457ff0d803f985a41c96bb60a0496b8b0ec	\\xdc908ca739fba461ad6525e91b3835d3af650eaf434c3a0355f17437a037ae1bedc2938496a6d33e7cfd695c94de459229fc3d9d45ce5106d43314f113b25db1	\\x6e53e92839abce0b58880bf7c86d9035aa6e3af75c8138a564a37139d546600b2b534161d57391f537dab332c6712df4c31aeb0cbe6eba51aac090973a88193d38003bdd6f488263a89970ac0b6ee28e6a440df0846c5afbacb45c520bed2201db8e6288b02ea23fa0c443f0d0aa3952aec05ce96ebf4ecfac3ef0ea028d76cb
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	3	\\x39033a9c365b5b73547a306e03f60bd96e6a276e775ede6709ab9a5ee06c9666ea44c62400e6c334dba53978fca2217d41cbd34192b95f275a87c6221673160c	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x713ef78ff670da5f8d488b631d5381a11636db06a7880eca528d48766115f78752ad06b70181e00bc253572dd4fec9bb8cb313cf155276cdb36626a24698e31c8c4c68541aca4ba9fa36a8622d1bb1819456022e6df0c4f5539879a7b55a6275993e5728f54f6ade87bf817df22062fc820bc24d6590d72b6a266cbd8d97ccd1	\\xfc7ec251abb14548caaf809b6cd0e2a9570348a19b098afc86f80b2215f0bcef782fd2a98b02e1a6f4d32d387931d51e463e131ad8380f710b4444b648377993	\\x81faaeec6862b5bbee414c6e2086f08116d8bcd4b7760852d241f1a79c39c91d0b99d11bf6e4dc14269a25509f859edeb8bf034920629b135eb093661eb062dd1037fefd79546507034d74148a4340a044f280eac4c97873b4decb14564d2cc5005da932216784d0e577c67716ca9e083ac4f515a27b9b8f493685d165eac446
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	4	\\x97f3c4d3d9e10542c4ef26f3eafecdd30aa6d54c2c2574d0bc8d3bae2b34fa3800f297c78c752d8ecddd162b54d0818767b8c4969532364d7f52b406d1ecf60a	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xd534f62b6472288d18554091d099948ef9fba33a2c085865e1b0145c92122db5a816c3d8695cc2b326e34a7bf391a5b9fcd4eb05434874890fc7cf4e273c1c5a4b961e7a6df3f9849ad0246a2b988802eaffe9cd5277e3c3320322ba42fe94ebf7ddaa35f8ddfc4740626bc1a572f24b85058a8cceef9d8d2aaf718ea830d1ff	\\x20c73d3d64c8203ddae42eb7b69ef56761f261c912622e1074fdfeff2fdbc5b1659c10898df12459263c4c0e224bb0f7465800b4f2224313b0f66906328d1b19	\\xcb7f96ffde5d500f8647f0c16dc3c86760cb097c58a262c91235ba55325a5531092abf0fb25d0a16af2508118d5c8fb3ca9a4b053bf28b999b270ff658a0813491a2d5dc98928380452785c68eb97a6306a8007d0f683acb25c1c6a3df6b0f269fa5f4cd529a0ba9e2922b4dced1c908c0957a4405a76cb1de157f8bcf14e808
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	5	\\x7a1aa3ae6afa1b5d3aadae947714c193b9ca85fc690358cf16c4499b7225f72b63dfc1046d82af4a16ff2ccee83b1436936c8597892f1399305638c8247ca908	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x81beba6939c5416a01defa37d98676d61047e3bef706a2371b965109bc8f495357fb0f77641fedd84f7532b22beafba2b3c1fa261f9d46653e2552b9ba39e1aa5867379c78b4ecdba497d28b146c2c1d2d9cbeade9953062422b7de0fa7e56e9c0ba4964bb317599ba16471866ccadca617fac46d18f2f7eb55204ddd45d2129	\\x4a83371346d4a8f0c12db37c5b73c036f8895cb365950d8b5f3958bdfa5ef5bbcf359029d4a26ff04892ab69751149a07a4423b7ba5fb589afb6482cef881509	\\x2016a90dfabe0afb341000b5259f09277e0794b98cba1d26b474d4f8468bef8bc8f541fcbcfb6aab53091f7d2c367cfeba6511de4c776d0a100c37381dd2d9bd14301fdfadbfbe706d1eab0790e60ae8ca0a3fe2e01b30338a3c916b4e71f992e801fb226617e527a51c59c2dc5537e2a02464fdf08ae7e6a1395bf9b2f0b085
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	6	\\xb0251c3d4f73c5e82b877535d3b83435159ee52f9eec65f4c0b454cfdf0f72f66a3ed6f0b72d076af22290f4ce684489190abdd1299f95a0f0fababb4a22610b	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x896805f33b44dfd97caa41ec2dc8f44f539c5e16050c2d67fad0df054a32eaa7b9a3b7306623aca143bab30f74d2e9220b93edf15910ab22769f402da3c386150fa834d6f21d28ca84e744dde2e6496c38e8abc9f4411de0c3bd57399bae014a2912f027c1edfdacee2ac089398669eb9d67da26d1b4ee48210bf27465c390eb	\\xf795429da80422d77b64139a7ded4c602292a7372a34fc705953269bf7077dc1578c06e02895d17b9bc2a72b329ff1f5dc0138e1493c4f54768174e8da08c346	\\x2003a80cc2d50c6d3de6f6bcc44133ff004b7f9fe4e515e15ffff151f6e6327b6281de4d8b1f03a47011c3a21a0d3a2e0ba5f9fb2634366ade7d0f540f78cefa3bf23f1bac97d3e759324ff26823baff6a8418515f9484fc2b3fff08601157e146b4e3d9e996634aed36747ca3675d1d60291fee20f4e3481dc9ab72f1e59180
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	7	\\xb4c3d9b900af30ff190bfb2d5310cac8296c42202498b294b2e3ec01badf41b8d16628de7186d49d46dfd9b6b1c20f9febeae67d6f769fdfcd2349cbdf78b307	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x90c1685cdee6df57cd8025633e1b9694542c6295ddc85f486ede4958ffcf524309cd247087ba3732443855d4185e95c4fef3c7a2e8a81bd456b789163eaaecf00370c0014ef0fbd94dfdeb579448ecca92410e36676f7f9beb85f0710d78bb2b3199586834e7f35d94806236a3eead9ac25d22f55c99c5d94dbff46718d33072	\\xbffcf58bc47cc3aedc6b6289ae41b18ebd19c1164f074cd223e75e36a9be129ff0a48561a2140bbb28ea9013f0639170ca8bd5c3cd72d6634007d56cdb0ab38c	\\x12b06b8d11053b9308d889dedf4b285f5998d5a26931c9cc3b584e97f1b899aa7ab8cb545a6f579e5539e96883a5d7764e8251f31472897087acbd51a305621febe1f686d5ea851ae0548b83d8fe4845b2493211673d1e269a87bc4ce6af8c27ab78e356f52f319a347b860dd75b6b7015528ef9e8b525620ea9550ae07cd67e
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	8	\\x430880be90d3d0a4f88349fb09758baf89376e46a2847ae5e60511e01d9118ba3e98e6433e6b713b6b925fd9d5ee733c3c1c5bbde13beef0c647053424681e02	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x18bc0e6cb0872dc8c179c3ffd679db7a9558dc07c7b3208479316f3f2daa42a76612182995b38bd0257048179ba683ec301b42ede2e43abc943a2c5435ba3220b8e32dbabd4c893501206936d32b4f49056a712a6c8bd3fe8802eb705025c23ba91f7bbbbcefa5746a8a67a81061fb8659190523bdea2e9e3c668e1626236b2e	\\xccf8babf24f949811a06cc302d345723f92fc63eac32079a911c46c7ab500b69157df3fc5c6e2cf270cc811a6150a08263333b6592b1d986c1729c725c742be7	\\x9112b925109c2696cf43650063c40f3dce6c487525c5cc12abcbe34d629e255c95d8500f9854090a52864cce8582ca92dac0bd4834efa83fe24f4b5301208c33c5ac26e6e3818061ab5c28409106a27b721db728a77b008344878f2df50852d028be867859d54037906ba8c01e292bdea319977e0e8a3945a04f6df644cd9375
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	9	\\x59792ce30f4d277db36bfc4abdcf25c82858152ce4bd8acaf9226e18476807b2ec70ddec0a5565312ea3eb5ffc2537400e068d7bbf501e7b5e1855a1c82b790a	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x7e63b14c5e876521c1519e5b9c7d1c68279113558b17bcdad20e6288e8a8466e7d9ef6c08d67bdb65a88906de58e367ea18253e340bbab84a2b35bf7c5e7148216c576cf4186313888b19c872e4a3e1aa295d601683c6f1febc125878de18f9afb4f21eaf8d5957c2394e619451a7a8fe3273bb56060c4dbc85c7d60c38a8be3	\\x09ee21b3a928e28e1a5fb39e449ecef8146a9efa281e9b8f30ee1afce14ad1e43e899cca6a3399cc3083963d36b41ca47e59647a7076985bacf35a3e7b1e9f9d	\\x7552427040f2090efc375a95ef234c87e03c56dc056bcc15184013d5e147aa9bbcf44f18c3ec5108564f71ed544138b3e20b5c654eab881763542061546a0619c0fd986eadbf5f7dfebc237be492147ec8013484366bf179f64e5ff3ef92ad42d0726b1c7ffd0b31c8a50deebdc426122814d286d04721e4351b28c58e2b247d
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	10	\\x3abc23d298210315af941caaf558e7aeaf640cf5e2efdd73901e532a03fe088e13f8c83cbe94be993d1ad094520bcdaeb284f097fc6ec7050cdc370d07e05107	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x0a86a039dd6401f2a23bad83adcb1cb539e4fff7a578f59fb412875b6e8ebe9b2928ed087316e754010b1e5b84673812d41f150e82bd2646364a9f0483558d2ed0cb0494706a09d60f518250deb543e7eff921ed4fbd627a73ff96da528afec643f72dd5f7555084a6c48c83c8ca30cc2470c713493f0f55707d1bed144e0c6a	\\xdfc1ec6f55dc842b420f6a831918feed177a0430a68fa18f4405dcc46516598b7b7dc0f8bfd9021732ab6d7af10b9505f79acaf7f819188933651fe2d7f69d5f	\\x8ce7aacecbf5b74dace0c90573ffd08722117b8b23b484dbb8a37d7411ceade1f83dcf4658bd4f7d25681f636cbed0a1813d82f55cdca1052b80678681376ded3aca8a20dee89cfab849fdd24b66dbf6befce3b54a5438c32ac8b551357c439eefbcfc4a0792536c6e5dab1c5f18982ed5dca263000d431a8bf48faa640484c4
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	0	\\xcd51faf2e0d6b8815b8f73b5fbc76eb8d55e6389c6dcb93db27296bfb1006e699cc9b07d600883ffef5df60794e20741a4b9abe5f11b9065600ec4238894fe03	\\xaf0386738936b450f771b9aa68cdf3b34d05edd2c09e1ea60b54157d95b40284c025c2e16b80910513bf56378f9e7445375c3be84d88e44f6fb9fc87dc7b8969	\\x6b7ac43ff01ade31dc033dd56691f80934cefb861bd2af2c58c59127be21364091f8b857ed3b9b8f6636f40aa27c1514956e2679ddc497913dd369abd7177f2cb67cab70494f6cb0199c04e2b536eb518bb6a1a68a69ea4732535302e750aee98931a0da36c0f8ebe41cd1978481f7238b1a885a44789ebe81969bb06e19a6e1	\\x6e3e81484abbaaa61756be4eafba15a7d974752370349c14c00fe22d5a6cffedeb960a08b1d0ce014f1c54da38d6f60d642a12ee475ee14eddf2ba94ed659baa	\\x714cf7dd5581a64cfa9ecaa8d0653ad4046cd50e18ed7030cd322cd824b19d4f87fd5cfeff01f71ef5b279cb2bd7131b59e75ec25377f6c6943c7bbbdb3b236222109113837c24ec226f5d83807c2d135e6f7e7abd1dbb2264c3b74bedff3b04ce22aeead1ff0f6f9ca9a9144a239afc37c748fe466fc44e3986d0f7bc2675c3
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	1	\\xd341e858050838ce4c34ebdf7fdd5c9f494ef4e9abd316ee2d2e3b4a2b9c436fe0d63d87ca3388b450dfe54550f4a142e7d4a9e885e99e00d54e4b5d4b24680c	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xc445c1597e0e0d064d0ae3e48a9480764a088ffa605c0fb798f5a120e568ef880951f176e6a18f7d39d41830e5f2de56288e4e56789dc4707812c554bb9adb607636c72578760dea3a913d3252a6119b58b8d9502a8c44fa093c6ef11cd0a86d01b8d4d3ce0e9ab6de11662f5d9d91b7b7b6889e94ecbc3fb940d5982e9e96c3	\\xb90aa620da092bde271c40701c659994751b0585c84a21f160a98f60f0eee4b32fbb53c7ac1fb801a0957f13661782f8fa0fb4b89e73d7ba6effa8b5921a35bd	\\xb345872040112238fa41ae93d8b9ab6d24958b2c58bd737d2f63edc8f75a698388e8c0302542b532f044599eab9fdcc4b85e170eca61b334ccc3670a6f10a09145237e8dd648fb6fac53532f8ca2baf80fec9603dfcf3ac596879af7b25bcd0d5b903cc09bd513947d9cf4c0f0911256128d185a569897080ab678ec1fab21d2
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	2	\\xad3ca5120bdcbb70b5a298c4e022fb5b00a2f0cbae70b3c6fa47712f646804c02aba1bc3b8ed38b48b9a205ddd93dd41abb2e692841d9e9c716bffe0c7cbf50c	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xb84da9d6b2bf6756a71932006abbcf4f5956d4eae25393cf20fe37aabc1a7f107c8945d6c52af596bb2d1658757b0ae3f6850c9f31654a811741209bc21a1d3842f37c8a789c33a54f729403c23643ebaadf8b8a3bf481bba033c225dcb00ef6970998c4028fc3bb1f80f579043a25b941bad84a1bc922f48707196757deef19	\\x892005cea18372dfc7ac1c88c86c8a9b90c40061fecf7772bc05a459cd8fed00805a932a69235a56a0287c13cdab538d2ebf486877d72ffcf40113108f765f85	\\x3a171ece43b581d7009f58aac5c4368a599a52b060143b9726d89bf1d56e9cd067c33b99494b196347fdfc0110c023683b5b1f720ee665fbf0d4fcb9b0b9871c05ae90e8594e8122dcce2a6f287eecfda1f0417547898f8318b0cef819ecee23a9c505c7bb46e6d987899460832bf6e0730a51c3396b473fb5a63e002e71eb2b
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	3	\\x4fa3827ed85ef467e860afec138494fb3fb1c4d99eea11ef5054160619e9e680df119aae9befbde2e70e0eee924bb4d9cb2d993da7c8cac135857132adb3f201	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x7a3f030eade2850c31025eff3054152dc5e47451c2fffc980ba781b4c4b34590619271ff657d324c4519ceaf246f9a651acec0808bab39f0870e9e4a71bb98a0ac384bf1b5e19a3fdb7b220b9c2fbe2dc5e2fb68069dd11cccafd117aa80c635cc10488b1669095a03e26ba7dfc9015d85929f2a65b6116bc14e511d29eae05a	\\x3caf088db13eeb22aa84a91dc9d227ed9d29f3439447ec94d354eabd32c3d90c7f61c9569bd28a23327c37efe290c4fe46fbdae8082b3c7fc18d939641b48b9c	\\xb28a69138e5c39be906134fd007785a28b5380da2d903dd311664e7818102c28c6db1d806a2505d229292375a86d7fa3f73295216f6cb82851ee5bb01c750857d4806589ca5705d4842c0ed91daca0d6e425110379b13a1a2fa525fabf35b51eef2ccc7ca3357f297daac6f40b57015bbad3db7bbbc0659b272f499a47e8d235
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	4	\\xf00b688207466abc28e322aa7ef7fa48ac7935b2c7fd870406635d55767b0dc7d1a340b3f8f6242640cdd0afb11b17967cb724140a39f86647016588d5c78402	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xd6580a7206a12a491f985a021dd3845f103e74aae5517f7c08e28c3433d036bd40221dd949f24a3ba6d3efe488840623cf263a03342044b5b938b63af866b0d3c29100a4fc013cd2b69facc8888481691eaab5f2fd67b99145d8c4f8a1adafcf16f0ba52ce8e7b06a28d0b2a55e073167d304edb7fd46c3fb4fbff4bdd2aa045	\\x26952638c1e71f6d611ba8c4b00c4f0708e4aae7596e98d063a777fcbbbeb4a45c29304ea97845f55b2764bea474b10468b05931a1aa646ff713bde9b2bf0be3	\\xa4a86d09e7e9e0470550c76865412a4838ec0df845e50d7ff9e6c92cd9fd7f3fe8bb24080f730b95017459a7df3659f6a672a4777f69c7e8abe6f07abe5c2dd5a3aeac1fb9b95bc1784ca3e8324ce52dad5e0deb6b7a3233d7a4da988608c93931f63bba21b0587698af6d83d4f57bb4efc81be8f67421dc294d5a4a13920428
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	5	\\xc55b4f1ad98dd4bf44884a9d2d193e437f2052396ee581392d8db29326f2c397e451521417749f144056c21ffdaf59d9b83f3311f9c83572372d66187954ec03	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xeda94783d6b79f2595d9134d3f467e2d75a32062f83421c25db2dfab503ddbe6cb7e2c4e6cdd357ee398818959393afb6314a6653e958ff72510bce10847da2dfcdaabd5159da4d557b9a1a77943304d4c5368e79235d293541301a92d3a9bd5fe46e1757e897dfc17cf3c4ab1432c2bf9e1b51ade7737075223f3458a16060d	\\x2f7965f8f6ddb97452730ca0c12b715471275cf8151e5f30984e4a01d6a7bc11190a82ba209df13cd2101a90a62a3f66e967644ba9f34c44e1862d0d9209ad02	\\xb39fb29a843fc37eb8a3e383eae85dd63eaa5bc8147cc508004962e262d9182861f50368fe766603d6374d9fe7922da3068e6c43b81f03be320e3d689f21f60080e1ffccafec2c65feecc38afeb9c5c444168ef4d51cfb62be1000419d475137e7663cc513edc7be719555b402654d8ba602726c2ec94c8efc683376fb50d189
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	6	\\x435ce0cd8cbffc2a804fcc1d51a99d12b147d15a273df022ce73ca468de46fa2ea55f03cfc3eae4b3d2c9a9a6a4f437fd175882bbeefb3e2992f3fb29c2e530e	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xe6f428b10e279b20de5bab9478d199b725f61cd35183e92ee25c29b5cbd2ca7650fae2531dd9952b04f4b9205f13c40d9075f204ea66131e2865aae1d64c8f921525530d5439d93bda1ddda0837ee020bc361c975399971652ffcc5cce92fd50522fcba869e710ee7a7d16c9ab88aeaeec02d8f547efa175fa620a6e1bf2bd3d	\\x19c0a186776eee628f2297c7a603fb5f0ac43ecf53a94686354ff6a2b9a8ef84828fd203ece29dcc96e87e331daf43414a33b38b9f910848c830f68d811cfd0b	\\x387b4257a6199b1e50a87d628c1b7f4f360a6b58795662a5fbd50c5875f42f70a78787858cc4ee9a26db17024d0b1a2d4d2c307746e23789adf9cabad2c741ae02f736896b6433ca71a7489049594b90fec68d9b1ab5256b7cd8e21488ea8b014044988ca3ec6eaf130dd4f00374c25cb80f0281039076c93fe852fd4392586f
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	7	\\x09073da3fce0e7c7afa3a5e03647c2d389d114f0a735b080899a2162dbf5a7516eb7b766ca00a79137b99e19f7bffa0579b82c8438276cf1f9ee852aa4155704	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x2a0988541a136c6be425fa052905df02717a9f04be9bea557df03faa5b31f62dc120a66b09685b558d3400310ff838a7d7daadc0a19b9523a90669c3bcd89ffb6229e58eede7e105aacaa86ea7989d236ea75df89071162e40dc464e145e8ebf546900054497e7ba2698ef7184e564d225d8736b53886bdde31a7f2ed687570f	\\xb810f03c39f42ec649e05145c3bedb4f46dd4dfcbbf93608c89c322018cbc99641fb7c86f133fa2f773744fd73f7c7f603ca39e8dfe1908cb3a2da589f97c8b1	\\x61143855d6bf40b61604f3d0d8f73319daed4d7102232e744a1de7271b2a4a6711c8634929e99265b9c1824e6f83188a775c904b7ebb7ed563f8901a2d0a4bd6518a9ba3c3103e0fbbb03cd1bd253af19c3e8b26d0a9e6b07c444c3abee8b6c254dc05d6f737223cd2ad14d75cd428225f4a198c7735a57ce74dcf525fb9ee8d
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	8	\\xffc12d9683f3c46d344eeff06fe443d6d148db23a64e6e65dc7d7662df0001f6615fb898672552232f5d86234717bd5a1d42fc1f361c4d1ce8c006f146296604	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xdef41811d59b87c57b44fcfaca8820ad1549a3607ff29ae00d902bdd3823d1253ee23d28c378d7317f786f7697a850c68e1f68b262e59e9d903ebab3ad04bda7d65c00808f935301095083b95812aa606d7e0889a4289b0a84818e1f63a5efb77ea251541e5905c5eb235a4c2902cb99c8a12d860d6ea6af9b1fe2c422cd323d	\\x90ae42c74d581b8ed624300de22f1e0ed5ad25e998055cab92ecefbddde7e3a065075e7d443a6a586f6612105b4b1ed2f58b44536c67095570e1b77f34f33ba7	\\x84425bb2d7223a1a715de0564fa4c2278227f3f2bec7501bc74df32f0384a7bfff3aeb48b6af1a245ac1234422f1c00dc09e96310131a5805b465c1658308cbc320cfaa10a78013ac21510f7df329646e9715ce9c19198dfb12ecf58e04e4e72e08f072ca23ea9549d55e1c6b910b242f96683f4816829dfd521638d5a5b350c
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	9	\\x8135eafe1583454063936040e695ec2e2b0738df86c3363ef553038dc375f242544b493901e8a34aa081ce1b1b1668755a78511a2ddbad59f9b0aa4a232f4307	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x13f8f6539014ad9c3df6f5062f92f1ca2ff90eb6ec9bc0a332e3993c0a0e8e321f46cda4473934e6d1abf31d697a40243c2c38760726ee853b66039c1188b2eabace8e34744576e5a5dac09ba40bf477149b93500ef1688452d7fbce821a1a954638e26585e30ca63b7b994384e52b493bc73f929a2f276f5ba6369aaa2ddd0b	\\x1a7afe7554465f2fb5c56932a0cfb672fa0675f33491800802a8c9786e79d403f7393390016021d5d6a64385fa06e2de9799ec17e534d1ace961fdd32d87a0e1	\\x131fc56fc11350e790bc10b45fdaa64f8b76b037d73f9f6d5e76981b3d1984ffbed62302b7dc84701091631f0b25ff0c4ff25a421e994e272bff216160e09a4dea33ce75f34b5ecb91e4c4f8bbd33f533f0c4067dcf0beb0b084f9f2a2c4467f789a10187b79546630dea83ec0ad56c03038527f46773146e908dcc641d973af
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	10	\\xb13116f9bb4037a5bafad2e1eb6832c249e177ea789c7353cc1944dac34de73dd49096430e8dc388e469b29035ceffc15bcbffaad0aa9f5cfa712c1625a01c04	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x6e2c5732ed845683e9cfa90a337fff9212c46efe2b465380cb88f18960facc201dcca1c3a66101410b924674d31e316519eb41ed4288743ccbbed9fa3325d301be4fed09009a35b1bdf77ae410ffab5b16a41094596576d1898971547f505086540a739bbfe8cd49b1bdda26397616d8d46a859733ae8b7208cb467b568db06e	\\xe1e583c495c42f094d43c3d9a09f8422e6e33f22e76a8d9943804d5b098b408ef2634bd2cf5d5a0afe61d2ef0719fe9cd74cd60f2b8304910e7b5a352804c542	\\x95eb986ab862d0bb3ee0ffa4d66f7e82285dd14f8ef1350f32c157a390a74cb64dd6f2c01f9eba97a8da1d08611a15b4028ca5de85e9dfdd5322b63516e1fff38f6f7c7858a4f6ba68eeb6e3b72fbbb2a0f772baaa73efdda0293762e517316144a4a342759fcc3c995e7ef148491d72e95a7eb23eeb3b6930d97f9fcb5bf347
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	11	\\x10a346189083983abb6899d4b1113c86e0cc96ad01c98607a4170fd4f4bd71fe4e325de3266ac5756e445a230ccd155f1da242acf7617ca6fccd12d398865907	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x8f3a9b5917e5783d59dae3240dc34360a1d224e6ba803f64e71df6f275f2aaec6d93102915adf03f6a481c693a1c2780b78606a8f9607eb1b4820d3c4bfc10d2f4331e4362705b889c853033fad69edee1f8abcfe22e5c93f23087fd8993d9e8d5a6c361d0a66b27a08c4903e92b32e61515123823a346023f064bd0e8cf1898	\\x8af37728d92d19dc65c5eda2d0b85bbb882dbf86a03bb43f4ac04ba6698bc18b61a3866d7751d181d2216519b6005274a612c8da56a298ee63e6fb0e345b8140	\\x41b191f539ca8fe6a1c4e2e626925598a6b87e3f6f4bdb458f61d7bb15b7fa71d4ae04d95510ff136da046436965d561080df577ae143043a66a643843e386e59708961b59dcee05ca6d3ec4d13ce023f4cc541a98c70575518cc1bf034d78398109eab6b70500c583da09e4dbee203c57683f4294dd1c3b1842efc562777168
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	0	\\xb2532237b3b2f12d4d97418eb048e4413ef8d4fa61522b675cc417e8ab7b454b10c3dd5e0d1bade914a7d722947cf9b81c9444c91eab57d13e6e4d8ddc7a3800	\\x024eb8c53815d70be16003b1a9c804339a53c69c5813cf66d8ff1e691368dfa737baa4a874217706dfdf1e9e18d59fba7cea1d2e534abaddc68b69df090ccc9b	\\xe2a33cbae7102772da197e5809ca9cc151456ded0720189041f6be404bd670225775b598d05124b151c9f62d50fb4f1a02b03e216caa31064ecfca7075cf157c406f3442eb1875940e7951f613eaee3e03dc4a52c87306192510fb77aa429d3d0afd8dd8086e6ec4f7e430de27c4ee45c027f2568eb783f8fe586d6e464a6aee	\\x230c302782beb91332ab5a561101affb3ceab3a510561bec2eb25e314a8d0bf5466d36f7f2f1e04805929bbf617b75e870e4a6046ee4a24f8483ec383bcf08dc	\\x1549835b1d45096a45edbc1723eec60b00135ab72249dbebfb37cb86c6a0fdcc3fe622588b86ac9c8fa82dad2016b2abb71a19cc6cfa1875049d2a9db5e1df95c446d6aace2a511489c4e742d5001fd5f11f676667c1c73ecc3d809db5b295218ed31c42eb61c8ebbdd72cbe27a649ca575c20e4f69ebf94546d2b0f119eca0c
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	1	\\x337a014414c134280b925326c1e5c9e067226607b17f1e21b7c389601573d73b0edd24f9c07bd18725f41e587040234c1f57c8930752a1a66cdf6b15b7875606	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x40d2706085b0da986add4d54eb3fe76577ee63b6aa13ddf98eabc9c977c067ce33396fc4ed02269f5d5ec4f9b7ddcb7bdbde537f2521ed74e334fc14fcde06f8739eef0568f3d45ef7ab67948510b39be62c85786cbcf7dd0e90c3ccced1e424f5b62661e2478d4c97d7c120da8492e931931f74ac613bb2468d0dccc216d35f	\\x3d486ec19e23fe93c86c8db83e438ac32a195296c950ab449518dc82dee977e0ca0897d301911159d49aa0c31a18cd800c9fc5415b49fff0200c69d77f3045a6	\\xc20cca4597108d9aabc0d23570f9725c30c46600359102f0cd3585a4c226d06607dd068c568804d720008a8c6ecd6b810b03fb2d3d2f2b04094f63f561b0eb09d29579df917705fab421a84c9e00b69391f7f235631f574ebb9c640b071917a2eb61b919b83f5dc98a980b15d8a330b7caca66bf0bcff778999dad9a04f07d0a
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	2	\\x9884f0c0dd7e6756f566d16426c1cb1c6781e86cb8f78f604ff2315d91b058d3dd903a0d6518c6698c4c31494b5cb8006b9957b427ac76eb39f55bb562269608	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xeeb569174fd36504e1c2beefe8917729aa9aa5f390790ccedb18f41df838e2b6e0d1184e89887a661102213c1b4b8671b6c3eaec7cbc08c5aea00feb17b500abba08c9c9179ae62d246c46149dc561d92b644dcffc7a168cd90ece6129763b944b64f0a9f523f2ba5020a951ab13ccca71eecdca7cb60765d43b42ac4587f3d9	\\x852c7a0b6c2727ff500945baf4af897939c716d1a6b24be2e42da28b8382ca494b254cde8e0abb5743390d9b2b3ab24fa82065b4af06e271b36a6605ece90410	\\xd1ec1ddc3e9ee0b340d0953321f4003f99f6a5c96aaa125c0f4470dda8c9d674048a2c4ad151df07674c669ff1d1d59a326e9af7cdab8cb8850736ca1849b1b6ea2a4d07685266d38f17f9a8fa032b59dc144153da2586c1bdb30751c3b0ad82ad156a24eb94a7ba40ddc92f7ddd2eaba4874fe520a59beb9b0375a6992487dd
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	3	\\xfd5bcfe0d7df3981d2ef7b260788f7308c89e59a94d6ec973e989fd5233a6356359ca1db7111f355dc03b52106ca3bd4027239b17b4f12ee5d5b1e4b9e97ec0b	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x7e3fe94338bd6e4f71bf82baa2c741986a389f95b1af93a5baff14d079db4adcd98b9f66f7f1c8b53a0893adfeff2fd3f31d8c57a0f6fb27339326594560221bfb9613f5bd4e818fdff3044140d92d70f701981a9e3e75268b8d73f01429f3b9ca26e2335ae5753640474d2df5a14623c98d7a816f4d1b07b1aa3a1976a32e6b	\\xf2809f347d304427bc20b9f442d61d88e4e720ade4768b87957ab214940e24019a334f491d025ce25f9e78952a198dbcdc43de3a8ce8ca84bbd9c2058bf32f71	\\x9525260db38511ae034eb692c1ba7d732c44814e59fa2fca260f920797e164edc15afcc8d3c6d27c7ce0a8f209cf3ac998ee4a294eef66fb1b064a162c9beb4f6b7843c6e6630d7444a20b74cab5f69b679274a2ff0e161353341621f1731cfd9b24a576a20efdc60b610f51cb81446e81796b1dfebd01751ac542638a97db5a
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	4	\\x8efb695ff80a907a5cc7fc8c5a0191b502cd1d0f7e9424c0cf87c662e519a8d73250101a9517cfae06dce8e52fcf01ba44e9a6dd49a7e2ce509f090fc3a55c03	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x12e27f1b8a2508c5299a11af4fea5b7bd7ab423150606ba6fdf2362e475ec4326a68abbf29e0661505d67f7decba78e02d421440a62d0fd6c43be03e89084c7f9718e36dc71d54291f5dac1064403fcacba5cc05e0e84e3c41f596a66643276d1ac6f15d194ce0c485501051b0f82825fd09254fef6b1f3571aa6550bd420fd9	\\xeb4e62100fabc48c16d3f9912e100fc4c09c4fe1aa257ad7a027b5ebd3c679760470ac6342ccf352f9e2557af766fc86cee1e1ae65c3beee4c36c89600258366	\\xb6160f62c2bbf3d1b58376bfba195cf061f7924d9b67608b71ad163371317e5991c93f5044f52ee769c4cf0487d3efb772a821ab17eb5d17e810705e79314763047eca46e35da07a2ba4334046d792f5b436da14773dbc2a8f21ce0bedaca5eae5793da5bdaa8d15579726aefe5e13fc6748f0e62f973e6245e9904cda33b048
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	5	\\x13b7ae0b1edd3dc368d0805cd8d10ac30f3667420fe2d5350ccca9c41de7735b869202d73ea9f12cfb5c6606209718518440669b95cc35cfd88fa54898a70d09	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x993b75299414a172c27a3e9a32476125095cdc5483fbff03f8bccd90bc119efd6aba482a9e084e3042af2cd753e590c2016e1c8d559b708b6748181dcd83b74bfe2b853c1f85ab7b154e2c907ff24492171234842cc00e43d8ab07c446f91090891bbdd37b562bd580da734f47e0379024e53e967456e8985844135bbf62f3fe	\\x8572a34367fd16104b7976dede9ae01d9fa19955d2da5ee4bbd6e387c1741244914c59d522c9aca1f5e9ec4a2dac9b5fa0afef7547684d6d29b2e7c789a055dc	\\xa67188855b989b54edccd9d18205c9a6b766879cd1f49d920f9b2f1ba23151758f2efa8e547be5779fdb00c60ef595482c062d283a63d05e3c3331b5e8532f9a9b79ce998c7a9841d6bdf897fd7e7d3f10e11f6a2aa75b7355193ad7c92b983d6f41455638969d36f8e3d7186952800ab02b84bda25f0daddeb8e7760b31e573
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	6	\\x53b76f3d300fa8d8980dcc45fe22d2a79e282f3f5c5967febb6ffbb037e0b741dcfd6d11f980a2586ec1e3e8fbadd7bd89723c94d666577d55d858f6382f7108	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x7260d93d1b8c4e6955971f2043fda1408a9a7c3313026f17cbfb6f20430011970c48839b0d3c90dcf7b458eef7d070fbcbfe4311b3320496bcf307e2791b33152623822d206fb469b249fe3d3d11851e0165d3f66cb9110b4b070883196ae30500216ddcd67486f0768ac0c421bf035aecb1e950a67ba02adb710de144d4a0be	\\x3e6c6983ca66335b24f5b87c754cbc6dfa7c3fde351051d7235f71eb4950b1bfba7d9b43c103edf04d2184aab693bfb95837e5ec15c96a9d921d7b3a1a74986c	\\xde9a0e530399d772bab9de4b681fb1affd50b046f51231c416de75c208123d86580ef247fa8b1165285284dafa19f859bcc37cf609f5313db61d6917056a77bbc09f7589ee42226f2baa5060af100d2650686727af0259cd410a3ca911e5dd4d7069de27ef92dc1151440cc269ab531fd41893e5dc3b09007b278bd9219ce113
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	7	\\xcf282119c32e22f4725611525de5c16f197e15a5c6c2b0d8ce9aa93fdd2fba4fc47a7e933b7af92f957bed18e1eaf10116e7a866cb090d0f6b526bdc472cbf0e	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xe832e573b24f2b23fe1fa2eab8bc954fcd6cd7acdd680fb68e001f21cb5259284adc570a6c4f5714f1f548bac3074357f4a13a9043a89e73609e0ba802abeaef51705124805cd1f464005e57fce50827e28c127d220bf6421c93d6bf92d1e984928ad126c7d17a8c8bb635e85799349ca051cc0c650033b770235b79f5f464d3	\\x4203917c499c1992a8ad96e83262f7f07ddbf20774d30aee769987e54f88a467367eec767a8da44fcbf283d91114fd9a9226ef05819601a7766e04063abe9977	\\xb1988b5c5e5c5052c22d70ef9a198d3f08772619a0a279511accf1f3f41c773dc6b4a1c855f60c87885e47785756707d90dbadb35a6898446d47ec36a93d6974f2259219a5227b8694fe94231d896a6cbe21e0658ed0ee86f69bdfe75ef08978143b1a7abf9ea1c8ddab2b24cc1097107f19166eea6761b5da56ac4548ec398f
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	8	\\xe96327c64507fdaadcc373c65f82020f210911dc5e8ebee256bd545d672b85df4ae13d436c8a773b6de4326ef1c0c4c7621ae30113e6101f675e7c5d89154a01	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xa6f6431d16de159a3caa0a602b34653b4b1f1bbb240046b447c54bd69cbe9a9b62d12d37cd321d82464dc95160c6cba7c860df949294a00e3464f43ae51990f1a076fc9b62f94da8793998bfb050ca453cbfc9940113dcaa43134b38a0b0cfa22a5e3aee393a98e0dc61e19fa52a80298af1f437af3f242fbbaed14ffce8ac26	\\xf4061e5d03ffce589780208b19c70df71f43e4871f689e8fbbdee2a28340a4c38355087c3d280b6e8ae85e470c1abcecd93ed773d4752e5520f7342c83775388	\\x4f63271ba074596c60df62092540cadeaa0acf166be4a23d51e631057172d6dbfb0532b8ceb6336f0994236dd7ed9629863fbe04633662f5b41d488eed2398f926c70da3d672f94268058ebe677b7538a7136c9cc1c088f06088aa150806928baf0e315408d7c6226e7d19ffbc294a64bdb542565a25f1f1bbc83629b42cfd74
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	9	\\xcc07a79cc6a614a9f4d74bbc3ed843180c0cfba9e6c2fa9356c25c9c4ec5bff4325341c04e620ffd9a2595a9befbcddb0662bdab8bfbac832222fb522d83cf09	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x993a7d08a5ab395aef5d0efba7753bbb477eb6add489d2955653a4a4ffb2f124a03b4505fa0f2d278c9569ff6645ea69560d9ec6fbea04aff5da3403c6d3afc9a63ca566fd003cd53c7ff5148af18a21eabfc48b8b79df43fac7e3a8c2ffa076d5ef125226250264373145f4fc863f72fd5e746c122f02860697ef3d31849df3	\\xad7ae90f98a1eabba78930b119fd438961668ac097881e28437b68298963e154595fd0148a9ddfa071c1888657c90c51442dc410da0eaec800c1c74d160ebd2e	\\x556e3bf60754c3c029c06a79ea9a6c5863160713b6c214a41a710c45bd1cdbd1a59d4f0fbf0ed3d59ecd44d048f3db5366d44a26c9939b142dd4b562abcb6a75faf04e375a2d02b55b0695f207e4c188a9455dd71eb28608fbba804bd60672360b2bfb1fd1d3dc03d5d89f484842f5e9eb45696f5f0c20705fa08883ef749ee1
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	10	\\x63f1ed15f90b0a24e38ec38d278fd9db8ea17b771b19381463f39b9ca98690cc0ef974e8d5e2eeb8bb36c111fe4bb1a718152419998fec3f7ae8abcb55191008	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\xcc8cd6ade94a02baea445c11e40c6fba103b9d6fe110cefb959f2c8a3e380e52e6ff4ac1914e2ee3545af281ea8f24fb8807d8660bd8e42c9cdb44155de5b8186c494201489fd897601ec595956d3c65a73c3810a510626b872396d6527345039b7968e48a1fe5ecaab71c28ddc73a76f200d918bec104e669203996852fc4	\\x4ad89102de75f112cc3f7aa3c19831dc5d1010d5a2d7c553e92015b0362d67bd6b5355f20c95c956a201ae1e35d7c03682ae177246486b27371136004e15284f	\\x944be7e47385a9da694dcceb148c452d588909f5d2670e6fcf0169309b5285fd437e86bb28c1f2a97b0005c3e6135081de9d905c509c8c9a948f6d9429522266e20ed9cc39cbf6ec5c3af4dad341d0bdb0b1ed4d11d7a55aab3e361569a6c70edf6e6a5991494dac3c82017d2416cec97aca014ee670b295bf3f48e84b58f8e2
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	11	\\x49b0837472a9520f5bd394bc6cd85ee6d69be70d4122ee60ab45f54a4cf891caff8dd9a73c58ffa543e487734d88514fa7f8aa2422ebbfd85299cb47af10870b	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x8b17fa7631af949ae7bd427bc732ea02b4b0bafff2a5da88ea05bb5e862072eb03fb4e8753454c408a19091febcaa0d398c0034dcb19f7d20575064eb03db324613940824cd55e68c7b1c5078ac856e8025aebf89e72bc47bae303bc683ab84024e74df25d9fa407167d5a8f9194ebc4e88de88b6494f4c176f264dbd64e6e7a	\\xf6d738e872a0ccdc786ca58c185a92a3fab0876710f27db37cc2cea2d0027e126ea42f849f7903289fba086ec7109be78644be3accf1c574c8329e3aba7be52a	\\x7e1dc3842f2aa6cc81b10153efdfc32caf0a57669c7fd0e0b1e6a38e2ea347dce0837234fbec3db0a93d3b8196bb22a9797529a1003621bda1fcdd1d7ec0af7c9f00f313e92837e32cab7fc3da862066b990babd4d15759a2a4963f4dc50092845f40dcf0a4acb9b883764182c6bbd71cc7e8e031d3bfed0348a6274094fff40
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	0	\\x70db5d6326da6c4aab73284891151490fcaf86ba30ff2ef5a5b4272535e2d1b12f63276287e50902a395f2046604b5544e927730e25ccd69bc9b71ad833dbc09	\\xd0582b959cf1753a76535822e8ab015b8b651b095d32a6e0f78761c5bafae62a5919bb088ae18028f13ab3ee03b50704fd1282344526b8da4c78be9cbbd7fe19	\\x595b911d7b2be5bf3ba4e5f0009917b56a9ad1235d32f3ee8c2887674bb788fb2c9b017661c5c06847524951ab6f38af68080e4e5465bd71c529d294a769bf90f0f1ddc56386a13f651c2552d04ea32e8acc08e65808faef0e6e169624fb04a28a71dccf3b038e8b9890086a96e6068c524921c8c980e6b02a077ebaebee437f	\\x8f2eb6dc34651c180a3432de2b8ef82d4dc70d257e9176351e32bcfbdb8a08b57e49d57ae7e50d9dd5b2db99d2a35f2137654436403f7bbf6d4e4e3fb84ffeab	\\x4222e6491ec4ed513d29568bda53e4eecee4836ee8c97d500dfe857f29676655a4f71c8ffba8ad982b09e04f10f41e3306394648d5f7d6262b713c96fa94de29e128108bd49ac81bc25987e844f2a271d1687739f123a8fba4a7f9224e048a258af0992110e5f20d2a19eca6b2b8dff558e7ee14deb70c4b408168e3100e0d4a
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	1	\\xb5f9ff611ab63e60ae54b9b63b66ff62a41eb7251bf1ca078144db0cd4c29e5f84ed7281375b41a663ec7d72617c9d5b2afd59f21c26f47d5586e042354dcd0d	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x11985e56d0f30ba34679ce68878dac23657c1254104eee93ce0a1e15ffaebd194a5f158bee8678fa7b55b66c6552234fb59279ff75a8358cc738dc02068fce795f033ba1894d11f74c70d47a92e0411d2c2f5ff14487b2fb7ed713c04ee76973b3dffbd8911c1702bdf451f41cba5f44a9198910d6bfc2ff6b067c37066f610a	\\x1afd1cf9113d5c96630caf5a0c66e8e15a7039cf24c38b757c1a55a98ec53a7a70e89b614b38cd6ff5f02ab07eb0dad3cc37e09484bb75a5a5215a019a63842b	\\x1d8b13cbe8ea095d90f92ba288f12701fcfe6000109763dcb250710a596b75918bb1b403962f0db0411f39bc0636bd826c6c031b389e88d78ebac518c6c1e99a2be691fb5064b9c66180732a05c31ce8cf542b289d186588bf44f14e0009b22c22f3cc3f2455c6486a5bafe39be5b804a987d51771a21949b52d1644b8859286
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	2	\\x1ed56af00a4af554775beaa931ab049eecf724fa4a47a52136e2f1fd544234093e15929937513bf4bdea5afa91ddb0d78ef14c705f64a655b3fec97ead251101	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xe6fe72490e65310f5d4d5285ab8725dcc0c7c72e60da4a17c78cc958945de17276d35a9c80d03d5fd1418dc251333d500fd86d3dc46996fffda7efb43428d31d49221a97ef39cd45bcc931b3a1f37240696fe85a9ddfb247df1f71bfe7b48bbd5441f01f9d51bc1f6d52b046ebf4b2d241efcdd10acc09650c1a81137995ad4c	\\xca2bc6375beec2fcbd8d453492b29eb95c4910fc2d90ff27b3dbaeac2c76ef0d27db1d8cbea2e0d4d95cdaf6c60270e26f23c667afeb81292cb60794480c270e	\\x7714fee474969e7e2221eb7bd3b4ffc1d47848c664d16cd15487a9822cff770b801c4b2bcb8a0ab11ff3b0fabf3a20473c191bc16bb6c0c8595c2c707021b01e82253e61fe0cae1188bd05d5c36ca2f6c1aa22e1954e3e39751db26d7305a4f2dad4d62c6821b05b03960066da8ee07cdc48ae9b6d0f641c98528af0c7b7c0f7
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	3	\\x20f939f9f6a21157c39423c13d828bf83980dde15e447fa0e45758baacaec7fea59dcaace4465626701ffdeaa0fe4dac0fbfa7ab34feedf838b10b44c3ee7b0b	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x4394988a47c4c6db66beda705323e65fee0c739d101cfba0dd8a35b78ea34ca66926ed71e8c0724217874dc036ce613362c0fb7eaa14dc33f6af13d5b539ddc3ae8d29bc4460aeefd37305ded596c0b35f00648e063155de391f22ced364c4b6ffcd3007a2b7aab567f9510087c59d16986dc4c5ee580b75dd1acd4aa12ce708	\\xb206d69d6cd893863730aeb305ebfd28e7d4355f9690231ee2ff1a9c44dda45721db73460dff4144e70f05b7cb489b8158de6868d687a49e5bb43b066111dd54	\\x92685284ee35a08c14dd10dfa0207786c43965cbf67aa993f2950d3c43ae3b6524b3458640d2fad322cc5ac5e09a3c1671bfc971fe6a113cc8413282ece9c2563c399bbb21d81bdf97a91311f43b40cc533796e63bdcd97f7945df30fc874539de6154db694f728fe7b579a1f7bf75d3ed9530371f95916d5705708dd945d937
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	4	\\x6da9f2c29ff514d79b23c07cccb7bd78dc029aa5cf0b34da9ba615982d783fe67f581fce003ee05f949ca49b91e56fdad4a64da75a55d8e0bfcdc1f9c6479e0e	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x3d3063225b65c7f33c6370564a5fe123ad9f699647994a6afb485f7628bf65f6a856993ab022dde9301bb9bf493954e7a7954926c9b142f0670a4667bdbcfc1227452fed405291c1f8db2b87761d41e399078370578c81aaafc1b845c288774f318d0c51af1b2a0f61f487ef1268f40b0cf199b4c205171f51b993da45300632	\\xb96457b4cf19a77b33ca4af5f731ec6f8067240abf5f9316450c7cd0c1080fc7ba4b44c518942b1dbb3404ca7d5a4a2b062cd16864d8f512848898e928c19cb1	\\xa9996f26c1a3bef78ac970fe3ad643fa6eb4a51284ad7b0d9ce410c67e48cc0e4d3290dd7ea21955576fb5add1ea4cf3bb09366e46cb6fcb9ea59ec753cb118140b5d21bf24fc0db7ab5f9b563bb410b4fcab19f970ac49ae7f946b1f3d52334aaa70be1c6f87fd0454840515fc61089673ac19608ab5fa19d897d14c51cd782
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	5	\\x22f9c5755ac742c91401fed6948d8131122dc0afecdba503447e4712aa1475180bf25cff1765768e734e1e5887db463bbf633150c009016e1192f59d03f1050a	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x1cc091f05fa57196ecd4880e27b3dfb410f3eaf3d418ad99f647249e0802a7a7235e9cefbaeacb3b630d3dba205eddd54a9379385dbe1bcec750f461f56c4772e612d4d6913c837100def33c91f099bf3753ad690571138ff7ea0dd4a6083be2bc97c94c76c7c5ab9e5e8316dc162aa8bc08a16e0e3fa031b877a5a10924d94b	\\xa71042d11a0eb7a5ae79883dabcddbed60a049b4ca58bc1bfdbe7ec48a617479453f3decfa6f36a6978f3b177a914811bbbd944b1c8ca1cbeabd6221b1b73b47	\\x2bf16e0855b00139fa6ff3c0d1c97af1929f3484f68cbb04e37eb705d0ed337c37c0b0ad09d14f83e57b1237f1d9935268c915fb479f8ef69911ffeee81e46fb39d1512d7b1878824bf4d086d1a8c1c7a3dd2df52169541fa6ebe72a9b95d92364d9af775d579fdbdd0000e8e20406ce89bfe0b30385770c19a7217744d44886
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	6	\\xc8ed358a2bc3457cff7593de5cc54a166821c2c80555689a4155677e222a66057b439e59640a076cf5997a74abb5926c4ad77661b3903f846777c547d6bd630c	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x6570a22602e4ac129a299836a5e3ed5f58cf6d0176d4bdb80eca2ece52dce780faa8d207006927412e31359ebe934b24aae9cc7b78023f814e8878eeaaadbb719993a147f3dc79b136c889fda17f055009092f9554fc1a33c3ef34f11db28e1534511acec2c93086b284a61f3d46900d06302ebf5c9acc4cecd05d752911b70a	\\xbfb09ca8e3626ff648b53a0c8e8f64319b203b6edeff48f3203002eb211f7c80d5cedc96ea08b445f74445b22dde79c8610f7a03966640d9f7ab516a604453af	\\x7dec58cd4a55269727b10726139f76aeb0c8b839f73dc369dcdb4f1fe484468b9a541fe795f496c6b3a0d248012a75aed3407ee9adae7ff5411c6e2c6f9cd28f88ba960647e35df05c63aca1d204e436d52b356f4188a03048407012d3784dca4def12e49ac12cc326827bca8bb09d4c7bc2b3d202eb09e4c276e927a8db7b04
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	7	\\x20066f230cc9e8a3bed66e9b4dbaf5e139d0f91690b90829833a2aee71e66cacbbffa70dfcda8aaa6a45bf41116dd957bc1fb376a8ff11fc30ad9f6843f3320a	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xbe0bc6580f05651d875c7b37e81702567a59eba327f9f4e07295c8c63be68f5e5b384f3f646f3fc8294a8d06aff879c02c00f2cb70c46ec31283dcb23fbed069c8c9a671c88bdf98541b0a204ef792d7f21c556c8d146d700b595070e44d45ae22136525c844681232235705ca82257b4224d1db32e5ef30f694f3b4ce5dc725	\\xb03b177d1a3f8af8d47b41b5a4dd4544d13ca7add821e762936d49af31143865a50ee62585e889836fd5be8f444c989b48f6458af33895560688a40668f122a2	\\x7e621716791ffd3478334c3e9acdd27a888bc5de0689ba66bb3792acd7d9dcb20764cd94941a18d4083827a48d64fd10ff8da1c785447b8739558ae11bf7e845de03511ce65bb0961948e90981b533a7383cd71ae36a9ce3e867b27074ca985486440b47a45f4ed670c15b7d450f99dd1721bdf62fbf33f6aaffcbf113107120
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	8	\\x30b343027f5e55e46ed67a2083a8ea099adfe62df2acbac6909701aaf8e75af1dafa9b962055ad02c95a751cd339c7161c0cba6d44f721d613738f5129afd901	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xe2d66d772349011b41bc74140ecaf14e5556812617ef878d6598d6a56cae5bd9d8c9292dedb44e5d9b08313578627780cef0dd8307a3d444b95955daedf82f7f8587b175159e95a86e8d3b1f96e49b87c551e57ac4b39215d7c5b6378decfe9ddc65a13bc700b78bd98fd5aace778fc982e5868c96a1bc334da30f7266c52ff0	\\x71709cc85c03891cd4cb5b5866263ad4318045909d7528d74443c0e27f73c272b1e845b6c767336f3564d8ca7c60427c3e74a0546d2f50db667d6934328a19e3	\\xc2eccb8d088d5b1301508d175f29252657f0bf702447b863d1e8d8cb4773f6022d6705d270b35f9ad1e2f767b9757a4024cd57e53882ddfa8f3350dd2ea4c6e9ac4f1cdd2f7e3846c41664a2955a0fd1a9287cba2687dabe0284f66cbb2fc200fb30714c77e59f8db049570c0df5720215fcb2e8de6629c49c26d875e40de052
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	9	\\xd96935a43c7326652cc75b490612f54fc07e491fa97d460db846923b2b65e45218b3305fbcec40d892234dfdec1764b6e05a1ffa8b2f4b0088fd03d578a9b80d	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x924fb21055272e1280d25fc4f5cc72aa149b95c957ec33658ae5564252ed41a24b92340eee3950bf0469fc675f1d7b65eac36acfd869d623719040fb8b80e674f71a41f6da8fc45162c4507f6e49c209ec17c7e383e32c6db2d699bb96de967197f16afcf945aed9ff3d2c40b93b0a0481a03fc977052cd83a9c922f9a38faed	\\x58980f53978096469541d708251a85c1c2183bc2e83c01faace63eed9b2bec092384a19149883ee18e151999c909c3b1288cc7dc86775d1f35e7b5ca023c4e3a	\\x659525d9ee36d918cd422e4d32151e651f58470808fe2d1d68930e96e07c232b4fd88205ef8642987a3bebda5bdc5043705e7c0651b9c575b8fe864eeb9a8ae0125021946ca6b3c3a486ace83babc63e855849590846afb10ad24706e74b54a824f8f63424f2468aa9e4551590586ff0651d50518f3676b0b06db1008bdff4b0
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	10	\\x23115be1ba8e78bd006f990ac14eaef8b944454c3cef66fa9ed4acdcf963ccc27e2945a2e93dce71a1ca09bbc81414a0e211ad3b661e6d3a9152814147519405	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x0d84601b7b148696b79c602d5b66b3181b97a926b200489e0678d5d714cfa1242f95fcff5d0ecc9e87bac6e450cdc586cb41d051d426d717d1e5c7a7fcdbb7ffcfd2b2a7bdd7fee504d8da907913d4d9ef4c00648573b7c21be192ab69e59903e445576fea89a842ca538edeb1343c3f9b362368853c09887644914d7adedb46	\\xf987bb36169c790913ecf6893d8870da1d8855c27301180f9b4c65f9a4fc61180371e3bb88644d0d91fd4320fdf50e1e65d3b8e95808998a82b1646837224bb4	\\x6ac721acace770c8d7b0d1943aa684fbed94876a7e8e7b8e871855b652084066a37f3a847fcc29f617541b0d4425f876dc49a67737f71182cee54b907b460017cacc88121c9100166b1a6abf896d8bd9ca9324ea0d2d9475c4b0778296a234f5487486486dd64fed0124cfbfa7c270a352faa23b8c1c4d3df2f3c75c3a2707b1
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	11	\\x691d140b7723a645d542cff7b664954038f2079bd2b8a5b719418aebb69364087ddd7968b6e4b3665f47e798b46d82bcb6958be40f96fff961812ec4c342ff03	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x10bdfe3541500360e72b66fc8be8a5e2533a630e6d266e4063e3b36fd165a55969ddd639471ce9287ea0e632734f0ab7f21e466c9b466cb0e582e88f5b69e2cab473dce2a061394a9cb161904e650f4d3275b562b241edf206285a5ea51776b18ebf812fbc6507f673da5af331d5c085864bd3d5cad6258bc8b4e9c400609618	\\x16a5c73bd4de89db68bd282210756e69e251c9a1d531672806dc8c09347741265e44455b92c8891bf93c03986e32157e3fec2d21efbfc04dc79a78522bcdc11c	\\x3c85562ec99b2c1adda1c2fabefb2c8155487015283165594bd61262420f57d04d8101be55b2f4510d729c01191668cf0c0215dbd3a9674fec80878e57e67d039bc4e1e755c76256c46281cd7969994225de7caa973403ff725784ac7fa5d2b21ac15c773ce4905a2b6674cf17ba352b1d0ae89e4068ec29a8d6e100f4af62b4
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x0db0fb355d054eb821c772b6aab52218406c1fdc4dc9b6c469ba47d4914f41eaecd81bb72a07e27c3a05b80515ccdac58e73f7b7d2f6a8b0ca1e94671b727302	\\x6b0edf3f9caefde3a0bb1cae8178836596f4b197d1ea7c8eb176304330a79c27	\\x270248e75c5d8c63fa226d16e774ae9a40eb43d1ecb02b9ba31ccc9f46d40624214645c5cb4897b666d5abf9017512afaafc47e4d3c52d0bd12e9bed22c0b6ca
\\x5b904df1fa625669ec584a4dead7d5a469a03cf82ffd1720532f254ee02cf94432179e5902abb3dfcbc87c7038d0553f61b1b4db39d4d670ce35535f0f4458e1	\\x7f7a1088a0c99e1c134e9003ef0a137fe4c0afdeb0bb6c08145ce48cdfd3931f	\\xc2f7b57c00bc8640eb1095a0b1278f00de615bb3d4a55542c16438fe83c21e0cc6f8c4bb2df868a4464e7e08582f84220420cbbd4d5f20cc7e986794ee6a521f
\\x90f819db012bbfd595079391d034a16430ee63a57ffaa5d4b765dc20032bf250667365c86616d86abefd27eb6c12109aec1e87714e399910b58bd4f8d6ef6b04	\\x4a4d82313e11d8834888a332e9581830a53fc7e9e666b1d270e5469652d74e2b	\\x6090155ea1f340acba75c6bb69142f9254e66b8cc73f23c993cb18952afe80f23a555a93d265bbee4234eb8d6fe0bb03448f23803b8292fcdc4ac6d949ef7c6f
\\x8345cfa3a2211771a95708767f74c2b99b630d3f6ad7c61b22e314b0eecb187057c36c12477e86b303347ee0088ed9024ce2cfaf2f8325c737a77d5022e951db	\\x516580cebfa431430474d6a313b9af1ec83e2124ff4483ede0a4ed040f631466	\\x6c199b6d984f2100024a6dca717cfc46ed1f35a25f2de5e824accd61847e20901d220dd32d9711fb80e7830f06772319e7bf8a4372093338677395fd39af8c65
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xc2d6e7d589f4066a2fc347ae4ebbf4ca3553ed8710a54fe2eaef78c48109171d	\\x74dc38273d72d3d5387a87f6982ca44734df6f1a194a82903a6410e940bb09f6	\\xf87d86d641c618160f17150aa3371a76d3327eb10572375c54770c911ff0101ca1ebbccbfe3c1c0d1efeef396ebe9ed2ee9a45d003167d23b6f1ef1cc9604206	\\x42b8ad014f7dfa280a058ffbd50a7ee8cf4568988b76778d6d408d9627d688bd033fb683fa3711fc15622b46d914cb29056a8955850efdbe695435d8d4e5196f	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	payto://x-taler-bank/localhost/testuser-TrKNHGl2	0	1000000	1580166018000000	1798498819000000
\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	payto://x-taler-bank/localhost/testuser-EdBw07YB	0	1000000	1580166021000000	1798498822000000
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
1	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	2	10	0	payto://x-taler-bank/localhost/testuser-TrKNHGl2	exchange-account-1	1577746818000000
2	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	4	18	0	payto://x-taler-bank/localhost/testuser-EdBw07YB	exchange-account-1	1577746821000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x40297e501dfa0c5261e3df08375325205085ae10964e54fad68c2e83e0b52e08c16dcc1d2b6d38230a70196adadd519a5fe9abd927803597c2249be259a66479	\\xa804b3cea4b878309c41e49a9bd755f08598bbd71a0785dc267717eaa40ac13fff6cad9114a08e5668514d6ced03dbc6dc7e0b0ca2bac2748893e99dc32a8b47	\\xc8cbffc1458a416c963b104fbbab81c2f6dd0b7dc306c753ed5e3381087b77e715efc9f38c9bd7dcc1cc1b7206d51009c0e5b0bd567f06d20a5fea38f760579150cc534d7078e5d8382cb314fd0f9af206b7fdf6508dfea58c0b3a64186c3fcee4f893bd8452ef2f76db60791901252be245124c8049b94ef6945c735cecfe8e	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\xefa1928d81cdd060558ae40483121c0dec518c5d531c8eeb8d2126a0ef345847fc5236b24a6ea7c9fdabb405781354bbfb601005ff45c3cf91b5fc5baafc070a	1577746818000000	8	5000000
2	\\xaab69341934fd406b64dcf4acecc4a9a3c03aa419f7ba953657bebe5d1859d6c199ad191a199dbbf8f6739001bf3088e5ecb91b0268496d8b92f1c6b856856cb	\\xd0582b959cf1753a76535822e8ab015b8b651b095d32a6e0f78761c5bafae62a5919bb088ae18028f13ab3ee03b50704fd1282344526b8da4c78be9cbbd7fe19	\\x5293087506fa70251e2d35b394e313e8f93288dc802856fb1ecabd5ef74daf2c304c52653b0adb9159eaa65eb88737c00dca20718bb8b482923d04c30bbe9e9a8857009770581d727422e6cfce923fded4d9a71ec951828cef3310d49c81935b57161971262071fa324202e8185134b4d3feb8e2d634b9da09cb763c81baa2dc	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\xae0818c1c9c3860e968bb22996b801d72b83dd32150a262b88f5c018b7ec148530df947a746a78aed78077935ad603a964fa1801e30ef99a1e8df8ca0173730b	1577746819000000	1	2000000
3	\\x784df5fcf9fc4c42e6a234e339fd4ed55c599d60d9852cab99f15f3c93abf24425f261fc17ed5f8ff4e9e11789c351deefad51ff3c2cadc668ef2a523aaef85a	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x210fdd3b74f981e490114907c3ca91cb3c94aec33e5da89d70a3b4102b8940a9ae9d5c2723b176c1801331fe9f254a939418a7e9c017bf604d11f3479cb23d4471656f6c72d9c7d96599d4a6a2f5c348be15c2573cd9f7d85e1a5f4f3d450b8dbc30c39cc6b7f12cdf3434b616b99b8b7c9d3ba255e3fc20a13cc46eb352d067	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x31439b4b2b109dbfd80f7e0f4e23ae680b49b06135742452fe8570879b9fdb7513717c4eb660d23ec19fa0ee7a4221b2de9907a7d5480c38f94e4604345dd205	1577746819000000	0	11000000
4	\\x5c0973f5dbd1ce69467c199df688687e4383d207b204ae43bf3a461ac4bf163b34e3a27a4f70b66de9b414180b82d1af3e947e76677f6885e5b5f49caa89762d	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x75b66d17db6511002cb261c7eb8b5cf59aeed1728f3537c1d18dcb2aa1b42a0713debc34620fd32e0250a7655fde08abad451b96886a2b2052842bdc0b00d4e8bfd136aa5612b119fa1bd2ad8d7e0dc6f541337055e021dc1712ea3ef1763961040a92c4d900d6e1edd78e4c8f582604466e53d3ed188ca4ba41d97c65216827	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x564ea1f30f550182d25661ffad3395406f8bb898e3678e849f3fcc4f09b7cb60e056bba0bc5b3cfa579247c20386ad97d166abd172cb93c2e440444025a03b04	1577746819000000	0	11000000
5	\\xe2f97ea84fc3189db219a79c2759384ceb197b8eabb8cead244ea8339598e0c504728d8a105643e2e3852546b48514e4ef317223e6acd8085288977f40babd03	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x9a2daf08c4fd375d60109aa6b5aa6cdf021b2165b86060ffe1dd5f4c7cb2d10dedd9ee4ec98629e213085d721bebe2ff52a9aa3af10cc423f3a76f81a01ff0cf2f3d1593497609b1e3459a21fe225b0f2262e019b30bac785a4227ebb893307292aa1c80f9634538459cc13240144c147c1033148d1cc5d9caaf3b7606375598	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x66e04fc3b0e8e720b6cde62c88b7ceb6db284814f0d6b158d525a588e9d40de65853ed7b09285509f2db80e2c3099722a6c6ca2d4d96e0425a6f5e00df4c170c	1577746819000000	0	11000000
6	\\x3a848930289d65a5f94acbf5190176bf4cfa0ea6fff0969cd2d08327f3a8194726575372242d1fa163820f176d6aedd045afec6550a6b61d53b3186165ad3d12	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x889d7b5e53aeca1ec3e30a8260fa72836eff7bd079bb115685022a76d55dcc453a51fdafcd1ad8478f46323bb0dc6a430b7b9897bd09f8ac709671976ca577f7ae22a301d107f8bac036b70b32199d60a7978003d5d4fb48d12d8aa10c95de9de8cc369ec6b7b9d1377e508685cfe3957d9d6979e57a83745806498fa1d178c0	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x5cad039a337c2dce7d05333b2855498db71a884de98f2fc27875f24cad4661a6c75babd52acce6a7d273d05dba74eba2b1371c958938bd9985433be7a2817800	1577746819000000	0	11000000
7	\\x11bcb93097b5c89cf2358040c6ecc0516f4c870ca6123c4859842501d4398e472e1a6a284817fa6723c128cdb9e3601fe10b171ebceec74b22ea380b104624a4	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x22adb07c01a9e2bca08075db36550035fa1120d96a299ecec6c57236dcac1ce9a516a52b78052aa827f3f57b9efb6a6e5501f9f21873f9e96e57d267f35e6e43d517e1c0b213121acebb60bb4bcc05124f27266d84a00f02d308a2a058cf3dc35b913c8571d78f9c7daed3bbed50bb05e8c5fcb862e2cb602ebff461e355d634	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x91b9a2b14a6166743ed752377df37a217bc854f8c04a9eecf6e1421a85817b19a178d3d14d17114d6cc242169fde507cb7cb521ca7e9a5e8f335be1a75947300	1577746819000000	0	2000000
8	\\x148db4cf090663f46a05767a6ff0c9671597736e4aff8c396bff4c315bff0c31e48c55555d748d4c8db783b878d0b5351b184b4aa3e88c2ed4cdfe28b6a96177	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xb80519a7d3939a523968e890845fbba05c3cfbe5138a7e3ea3ea86bea4762b1f92e7bcc57594a542e0eb30c72a229f3ccb4d5a10d48a3055f2dd3903becb3670e622bbbb2edf93d6b544740db010a66676150430bd200ae9e252b5066f32b5501ea05206b6c85d4c4e7be96e2e83ff0b8052a3af8822ebce704b338aff44f7d1	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x2129d6c73c2bde24eebe220bbebc990e11efb5a6d3c0a6060c97c76f9b47562581ea6ea0310bdf4713fc4abb05a8fcf73229755f8f46378d96d7141d51a3cc0f	1577746819000000	0	11000000
9	\\xa8cb3153f5920294ea249f7cf40db9af94b373026b27117220e94e1e8a1fbfaad8ea7454a3bcc562aa9cfe9202a89ace537818992b9cfbe8dcf0a7d076380f1c	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xb1721b617a5843f5adc73bfa65844277b2762da6981fb899e47ef44b8d715de61fe566f8ed193696687cde8aed710f0d8ce02dfa3f6efeb88197122404562caaa37d140f2fb1d7a9151446896d7420401bf6d63ec6b16e4bc0bf7ad4aec1002cb748b23087542127493985f58f3aedce2ab284ae4ed75e774ced9a3d2058dbd0	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x3a834713b8a22e5980762a021cf7c05a56939fb51d70a53bb8125416495229e5e1edd5efcd5b4b24953974404e90fcc4f6918d01c9c7e77bc77950ee31744b09	1577746819000000	0	11000000
10	\\xc2c288bbd0306bd0abad695b08941ccfc9820dcbb8632c7cb2b44dcab9ef9fe23c5fc26257d9bc68383c2dc793df62c150125a3eff1efe6f76f8d3e38a0be073	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x321a1e92a9ec133f78125b7840ea8eccc642bacd1988389d97369f26852ca14802ba48aa67f0c3b62bc2ea241c07cf1f465c463b857a9fdf19a1f75b2f962eaddf29e7b65eae1e464791687551d7cd501d834b23bd5543573fe2cda0c4905938f6eca4c04398ec5e8346833e3789ac60ec2abdb94b07aed1c601576b0878ed25	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x1e57e7c55789127d0ca3d008e275aa043424d26b02c99cf81e34c9f7e7bb1b9fa81858549d90dc0da0efd44159433d07d1105f00188ae5a2a126babef0ef5809	1577746819000000	0	2000000
11	\\x37538fe7a2855ba23e32838e8e90def4b3c5d33e330aaaa34021a51e73c8ab58e13c8dd4bca8df2281b5de6286ac3f34793abedc761a14b07eb8e7564f456d6d	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x32aeeaad2e4a79f45d618423f1fddc2fc2483c5256720473eb275fce954af615648e520e96a2aa550d6d91edd75c44cb98b9244fbd31e6177e09ab54acb3eed4d73f7bc01ec6c49c11c0e429d9a6a949a5f381b56fec280b1a4fcbe18d84f36ba50540431ba798dad1affc7d28dc98ead87e2c9f85a772138bb747df7f702dc8	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\xbf47821579376b6146c63a0efbfeb1db5e9cfcda0eab2d1e14b95a33729c96189db5cd7d127eaa1c8adf0b99bed58cdd5fac101aebc136391ecf5f1ff354520a	1577746819000000	0	11000000
12	\\x75c8f9d5f3e5b7b9ef6a6708cd1dcc74d55d83bf4eaa094c6ae4f075900e3668f0406435c679744a38b4dd60e59478ad19ea200d2c45b4d742bc4b70a9a40e0e	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x63311ba7bab765b3a58e15c26705e24139394559f297977553da24d3cc2b4c005fb1196dfadf8be56558c6ce939f03e71b2ebc6d8c5d1c7d1d9c46e6f2b566d86a955709b71f31532a9fda8945910b5277dde57b008f30b8d9485593674e139d03a8c20709809d9cf7c516512b3abefd3744076c2798b8502915a04464474ade	\\x54f18372b7a85e1237314fd6fc68c7ec27362d4dc6f8492ae71a6465df52b2ae	\\x165a82257d38ad4c09b4011006e37ca13a6695f78fd35cf1809c939ee77c736b3c964c1c67655291275ff79c52729370edf298f0ce90503d95462232aa36ab09	1577746819000000	0	11000000
13	\\x25aa2b18d8b641cc9a7396fa45aacfcae2859fa5f87cb6401d933c6f80431ca4287f7b1a302d9f519b9bb025071c09e7f5118e6819bd97bb2f5df9a2410f2d93	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x67a168c76cfe2b47fd9e36b1d246d7dfabd71919c93ae534dd8ee91e0c4e9f207636bf76694db4d21bd9537fa37be28fc612488d1c929ee35afd620b1dcc7762987b32fc73e276e35f51670feb39b3b4436f384faf6406cca5cba4116863165beb2a15bb3d1c81a578d0cf29c8a0440945123da671fc21c48ef4db5f2df2ce83	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\x5955ae2d6c35a993f244c6290b10b11b51decd5d2fcf9b44a7f3eb809be172d0f2e93d2895e738be5d02df77bf828f1829f31aecda29b7294967e8aacd174909	1577746822000000	0	2000000
14	\\x4de6eddaf95e9a45e5685f974558bbbd88e11265ec416bf2d4ec1978f146001a4b4859acf3295ed5fd0b5571598ef569dd63eb5e2b23dcd7f1f444b7ad44decc	\\x024eb8c53815d70be16003b1a9c804339a53c69c5813cf66d8ff1e691368dfa737baa4a874217706dfdf1e9e18d59fba7cea1d2e534abaddc68b69df090ccc9b	\\x70ba61b4b92b1d94fec779576433edac52accdad2009a12b15f9e4741f52d72061c00508f792cd413432a10d98c73bd53738b2d117a7c1899763d8ffed60f73ab7e66f36b09166521283b6702d8750039646f7f74cfd36dbc03eb254ca229e5c17e0e4056928fcf038118ca47c382d1dec4fd176824fea2c0beb19ce063b0949	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\xdbdf1dfa4a095face7ce99128d5642a1a21c1eeb50eadeacb440c4a5d9bcc3634794bf9fbe87911031403c20a5173683b1d8842f22f745f38f5c7805c8cfc407	1577746822000000	5	1000000
15	\\xc94662d55a672966b1ae76310a39efd2aab8e32187036d2b0540165cca6c369c9265c6ef042097cd8311b333a2d1f0d2f009e7437d54d0eec4538b932c2e11ac	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x2d3b20ea6c5620cf93de6680ea4f9563900d243558825d3cf82a5f6de562b02cf2bc91948bc9124fdf692fc3234ca54bf0716d3c7a206c5bb2d7b3d773ff52645f7dce3165b945833f0f4b2bfa3fb3ca88215df23353c00e63985aad806890980572f3c3221e141dbec3bbb8d326ef6deaee81cfdc8df2f40725428d7edf8940	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\xb08d389e3ba43daef635906677c7b938a051b5ad22ffbd2aa20bc3fc60670f623a84505587e182e1a7983c22bb29c95440e9ff5db2e900f4fdf4b3958a936c02	1577746822000000	0	11000000
16	\\x1a82122826660da23ed5be4f3ced05fe6c65e0916a835e77657080054a51ebe412d33b7aa96e04183882755a76e05500118e7bf4f0023a47bb1649645eea80fe	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x7c73cf7312c67018ff949c8ab858effb79c8f91e7457257358725bb9747edf10cc0cc6d7bab578da14eca74487538687c8c0236e0c5f2f9d1b27a1b710816fb2cf81844ec349caea4a28d2dfdb5cac0777dd8a7d0433ad0fe71b4b0d6d6d40e43f50beba66400b27873429dfc6bf6385a60dee9ad0d4f853594713c4627c9d0a	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\xc370837ef1233265b38cb70f6f5f72fe84ea68f3f9494dad43dc6da6ed61577c0ce7dd2f581aff4aa5ace7fa98023115187deff4a57b4cc2b565929adeb3290a	1577746822000000	0	11000000
17	\\x87561a9ce23ea937c4f7be76293b7b013d9c49fb9048dd061c10b79916b2c73cba74f3e35794e9c10488fd2ba6abd25254dca3b5793c829fdae4b3cf3e9a85dd	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xbd340aff0624cf249df682c79cb250bc80491cd4ff1beef123bab3a6f4f8bb7a200f217100f1389bf760e8c9c99cbc079672eceed307f74a81dea0ef6e1221b7ee856062a7cd7f9d241d46a59b4a1cc89b6ac6f36aa9d4ca9fce99fef0c5ea69c8223f46de70195ac500fa24f582c7ed2772a746e156a28ec30fc639b4bc2c7f	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\x4ecc0283d4c4b729a30eec0fd8c051de31a3ec21be2d3c68ea81df6a1a292c5b10a7a83318065cbb2d87f8ecdaa2a4e4e7125087cf7d8176991e3fd1b03b690d	1577746822000000	0	11000000
18	\\xffa55c873b203aff0c72c57fa0146278cf569ab6b4691a84a063e4ce2539e65760d99447cd9511e1d15f113aea4e21d12f61a4e814fc531788264399e0299fc7	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xc2c8b1fd7fe454f7175e54e79515bf9cb3a30bb4351290d621949f3b847cbf8c93314a1a97d112177a09e7988ac5fb99cbe7f76d1dea992ac98eae7cc5facdb012256d0dfdc3808d955839da4e1179d675d9facccc71fc5281f47fb7b7bcd527a8d698ab8863319a65d7c16d63138942a566ad9a2e315205a27b8735e7ebd988	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\xcbd21770b84c24d78fc5c6b6bfad7717cfd4e778c2afb11cfb00a631b37d08c2ba43f46269ac9426837951a2a8d7f057422f9181b32c05a093f6fa85647fe906	1577746822000000	0	11000000
19	\\x2a8c190ec06c3cbdb59b2e966c607c4f82c3aebd1ce3603e90d44526780ae24cbe9eb351715f9d7c48ae471e4de0728321804280f98463ac7816eefaccfc324c	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x8016094e641d7f8dd9e985dd02c650a0e81c672b29b50e76ea5b62f7b4417be7fe40677d27102d27605cd4ef01f615a828d253ec1ffd136710f04025c6c96d5ef743990e8f0b8bf38dc22e9366005e6c2b9ea988013d3db30d7490913d23d0dff038035ba03824356892a2377249228678f94b875a266400b4d8d8f02d08448e	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\x2bd5ece26f8f5b2cac979c3710058c2d25efa8ea068b4cc2131e14299f615759e42849082c2bcc563889bff5a97f3125564bdafdd50ab845b0098a292a0cd704	1577746822000000	0	11000000
20	\\x7dfd2aa3a83c8422db5d3cd761a47c2d70051382151aefb1defb1b9d2a8854f3ebaccda21ca6676de320dcf83c3155c517d4b515e281be0b023cd1c84c63dcf8	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x89f5c2193324deec08f10fabe2a1c001aa595499258dac1568058e66b327d01c949047199514699e10ab2d46b8daba036c83bd12d7ce330b7f5cabe926a4aea76f96434d36feadbcc724d972dd52a170359665236942ff187e10d1d4531c2fb38d9af7bb4ebc9f4ee6bebfb774da836f9f1386c86213d688a9b9b07a8426a1ba	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\x842f1f6c9efb4b569723a664ba2f106ca39918607cb1d896857c95e19805a6edaf9c928df82ca3859c4963e4f58d7c95898e46c9fef43075dbeaa1149ab53d03	1577746822000000	0	11000000
21	\\x8dd77eb05358e2f206079069e2911b8842c7cd97ced3bb9434c1372b80a4037e2bb127532dfd7a16604589a6d36e85b6316c62cfe701d6f43d3bad23e741b8c7	\\xd2edc4e40daed8637e70e4a18ce45c3b827ab46c6d613dd4b82a3c33bc8c5b435b1c89010b4606e4240dbc9e4a44b4b5891952cbe3c45cde0948c8495f6c8c43	\\x62ad059f420a1b1eeea4d5f7a765d1e2ad470e6c2cbe0f011affdad094c11bf0f4b7ccdeab4447ef8f2704b558e482cfe04bd768414f270a1d4ff0208cd9c53b59a1e32422b5c0b99e40f97e7e8e1fb7b43b841760e79bf72c89683699d8bb7ee27f33bdf0f2f5d897a4927dc84a392c7c59e7acd96731ad74bced5cfaebfa4e	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\x610d98b26e27e44793359de0bc23cec1ff9f1996d288c9fc6fcc2f53167e07114db47b065f84b98c351ce13d0a4f8f1808180899b43d71b5fc0bb97ae63b3004	1577746822000000	10	1000000
22	\\xe0e218d72e926c44c3a7e75982e499f16d748592c5bbe650d43a10fbd342e87852eb6952e744543b63b87ed13c655b59bb7b92d32dc1606670b91f60995e123d	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\xe3a662ae38d816a456839cc055385bc67014e2011d6991587878944d0a3b75972653074a5111c9a1535f6913819c1b529387fce714482145392248b1a49ec4330b80868248fea29bf77375ea150a11a3c35e0290978b10a095d8c3ac11464475ef7c4557855512abdcec14b856f9205f6420735b9af34fa3de6e4ffce07313c5	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\xe7bc8acd4c13ecac1288f150b82ede180c5271cd32d6c3caeb3fafac1f94b51d3a8aa3e0c0fae264ed7c7f0c6cce8e1e6043791cece4ca8c7dbafbad204f070b	1577746822000000	0	11000000
23	\\x210aaf0978fad176b5d1f7b4e8363a93e7c81541264c1cc4accae6ce12f6a49d7b8b907453451f988c98f574aad3a923ebf4f21d991139fecc88a3dfd2497868	\\xaf0386738936b450f771b9aa68cdf3b34d05edd2c09e1ea60b54157d95b40284c025c2e16b80910513bf56378f9e7445375c3be84d88e44f6fb9fc87dc7b8969	\\x40d7d26c42aaf80ba90d3c119e4575986448fcfaed6b1ba11d829ba0ffc74fab8e74581b5d1d4ba823ededc1311ba9d35e1b7ee3c0195de70b6c7709f2d7f64dcf313cce57b58882692b4e37b958899c080673a5be31debbba7aea91e2079d64f2ccd48bb868f6ec76e995713c1356c0caa0c5f77e61bec76ec63e828dbc9380	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\x09cf2091b91c92968aba7eb2cdbed242d8de2afc2aad877883a72341cef4f607155b7418bf5116d0244c133f1a8b130b35bf2485527ecf10c6db20767b8aa109	1577746822000000	2	3000000
24	\\x3d26c30e70c420c7794bc1321e3a712c6ffe6a708cf2999c770713d81003129b60726ec83f7f99e775a4497f1e473285bef9dc73558211fcc0f5f0b98e9b1893	\\x444536554085df33f99ba8dfe9580be1861200f08650653a3daff795bc4db9f123f9213c50ec82fce664b13fabd2f0ebada11145ea17c9537aed3df65b76c50a	\\x444a22e6b7f8fa38ff0c0c4b29333e3f6bc337a78bc7a3b3730917d2a2e660677274706e9737802826bf79c5290671b20baf158c6dcbe2fbd2f9dc7bd2fe576d5b3a28fece34f4657a90d9c70883a2bcff41053d3b4f2dc5aa598e9c39f43dc926980551887dddd78447896a6c91015c279eefbdde3a7e73533182bb4fa12802	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\x2750ce0c1a9966ab00482a64894062fd567d9bd07d42d20bd0d0904d7b5889101bd04f24edd42a35a8a247de80217e803c3259dfd6b0ba698c4624ad90385901	1577746822000000	0	11000000
25	\\x53bf56f215154f3b8f873849bcbde3c8d6048d367852d984889faacfc463677be5b1ad21ecab2977e384e6246a9527ba93bde2ecffb743a1a4dadb061310c0c3	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x3e4d52fc098c2cbdb4b9af642376b85b1cd42f8af729b3a4d50772e8433eeff7207788b051a9c0d30f80e0175d9dff098d9850dd35e3f2e8e0ae69a56c27910893565795a7a029679e7e28924ce38ef5948e40c083919911771ceb4bbc9b6d5496adab83898ad25857235c1a214cf52a72a07b174263f1dd6ea8027629b3ccb1	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\xa0f30bc19995913a86a12fd75de598d430ecc94bc2834f9164cc1aa4bcc10224549b673f90a5a50285351e228d657fad1d93aced4d60fcce9d7f52fd005e080f	1577746822000000	0	2000000
26	\\xbd494e4ab0169fc52ef2b86ea10ff6f04ab6b3cbe2cd3f87fd09de04c74d549b5a2a59c6541e955f4ba413c25563672a81e02d9a45798c42202af654196314ac	\\xf5e696365bea785975c6ab3020ad0aa6d63ecce27c6e2894376292698c42a323feabf36957c0248f004e1b205d73f4c7a16cc7d883727729507036ddabe0393c	\\x46283f49c64944bdb12be7796773416d0ca50f4a2706f4a049def5953e2c78545c9ff2f39c87f5224850b69a0a28c7796f9bba9b996b2c75f66295e95403989bcded50dbb686c7824f100c42e876f6618cd6c52b4969f80c866e519ae295caa584ad8b066500a3c97c66b0b67eeb42b48bdbf8fe892bb97fdfd5154f3c27fdcd	\\x1e475d2f261de9730a4400a5a7489962f7d4f570f25b1adc142aa5cec930cdd7	\\x63d58f8b41279e5cc6ec6e5e26efa6be772f885d45ca01636be477195f9de218c64d0f9e30a25475e44c43acf2cf3883bf4574219200ddc9aeaf901f486f7c01	1577746822000000	0	2000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 12, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 12, true);


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

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 4, true);


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

