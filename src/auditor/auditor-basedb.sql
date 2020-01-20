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
auditor-0001	2019-12-31 00:00:11.272045+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:18.246468+01	f	11	1
2	TESTKUDOS:10	P5RQPQAEDJ3XZJY1XF4TAETT3C6R3FB3586R13ZV3ZK4Q4T8MMAG	2019-12-31 00:00:18.341094+01	f	2	11
3	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:20.710457+01	f	12	1
4	TESTKUDOS:18	83G2WBMWTHEAPGMP989P763W2DH9AQP2DZP0HP3H0FAR6BYWHGNG	2019-12-31 00:00:20.793645+01	f	2	12
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
\\x762d33943a67beffa523d57266fa2a18ddd1d4fb4b4868813ab4f6c93985feebfe232964f23db1b18f6e1f7b39be4e7b58b951833cf6554d47ba33c83d89010f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1578351604000000	1640818804000000	1672354804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x96b2d8cb6cde09a83b5c8d013966429f8b240b34084544eda4458a0549aa6655fe8f582d9d549421089dc5e1b01d35bb7ddd6c80a4140a416b05bd041f2e6c29	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578351304000000	1578956104000000	1641423304000000	1672959304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1eca55e4b24aea387fe0a16ec9042b5c8295437cbaa10e9795d822c8ceed5fe3ce58dcdd2664193d6e92fc4636d69fcfe9a9109e4b6f84dbba70e5cb0bc2a41c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578955804000000	1579560604000000	1642027804000000	1673563804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7af9a3eeba12087062f84dfbf59c72e1efe6f521f9465719d6729e47259812a26c332ada3088ffce55e40e441f52fa81bb539826a3eadfa2047c90f77e369170	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1579560304000000	1580165104000000	1642632304000000	1674168304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb08d104264f8477148e9eb4a356fabc9b76ad083c0057416d878656e3591a8be5732d173804d738766c27438680f9ddf773c2415578325c858648b5636a8643	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580164804000000	1580769604000000	1643236804000000	1674772804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7568776d62eeaec199e9b07b43a4f9619edad0d62ad4f3f21aaf6f9e889ca9432ba4c3970fc036a0f3a941ef91160fb3b5e216c6eb803511f40b69de215b2d47	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580769304000000	1581374104000000	1643841304000000	1675377304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70abe197e7f586f9a802fdec7852dc755eadc539cf28e3d430e1c85ccda120ed1e55b9a4481069d8919170cbb38dfeb854a0448e5b7a4770ab57d2d3d7eeac83	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581373804000000	1581978604000000	1644445804000000	1675981804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x07112373550e4dad0f4b26c793af97df4cd48d833139708e658c5aa00682b302140d66c783ff0357306530c069ce82615377cb059ecaed0978a812d7a4c6c72b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581978304000000	1582583104000000	1645050304000000	1676586304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x363255c91f3297cafd91816d851f43b18d9e5288cdace66c243952f7273c69387a6db121594a03c21ca0b1cbd16044d7b3a79d8f7ecb0ae4bb584bffd006eaf4	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1582582804000000	1583187604000000	1645654804000000	1677190804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb443cf5d190caeb52c0decfa842ae04528f684f4b60eb1a01fcaf0cfde5e8dc83c6866cda70755666c5756c59c37bda132c28e62fe470c08da5b8191954ad44	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583187304000000	1583792104000000	1646259304000000	1677795304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc753d0aa3d76f5bf71e44191db4b2413de7bb393a7cc2371195306c39e2acf39d5cc37d047d181991f96696ce5222d94918056529324dbb555dbed2d7caeccd1	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583791804000000	1584396604000000	1646863804000000	1678399804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa1f030f24207b0e046ed4c02f63e3a8d38b5f3e76814cff052a5c63d48f88841fe83425e5eff01dce6426475c19903cb2eb01152125dbd58e6c14edbf062b34c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1584396304000000	1585001104000000	1647468304000000	1679004304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa7b661ef282b06b07e79baf3d919b524969a41b63aacff74a0c76131efb064a9b45326cf89636039cdd30e60327c1b7d04dde75799332bc12668eb0adabe7eb	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585000804000000	1585605604000000	1648072804000000	1679608804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb52d5ecd72a5b574fea854e0cf30c49caa7120e68180ea7a79882d2e26775aafa0e96eff46407cdace0549e90291434237cae83fac4f8342a29d7202e76ca1cf	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585605304000000	1586210104000000	1648677304000000	1680213304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0f521836b2ee5ac77e6e1cb14445c27c5fa0637c611ad2939564ad905192ff0b604724e3963d2b9b5a8d22715d816787131e09df883148fb64d408361be91921	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586209804000000	1586814604000000	1649281804000000	1680817804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x709a5c05c930e9a2f755b7f718e01725c656bf4d73c0aa196196236b495309ebc03ce0bd8823bb306a3aff63d1b1feced084eec66676d6b95d7451b6d8a47904	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586814304000000	1587419104000000	1649886304000000	1681422304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8a7778d2b5a536557e8d24e67ee478cf460f49d14cfedbaa9937daeaad3fd369d552fb082b51843f9ae861d110c8e45d70bc5c00d40823c68495a2d84ecfde8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1587418804000000	1588023604000000	1650490804000000	1682026804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbeca26cd1c9a877afaa3e42c314b60d31424c04d9e157136f26b1c68b79a4fedf939e6d412cdce2c414a0bb134526891363141e4aefe59e9c1fbcfb6154e8b42	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588023304000000	1588628104000000	1651095304000000	1682631304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb152c09ddd2acc6d9f9aad2970dfc7d1f14cbbf4753e420440e2b76454247649eaf52cfe4eb23cfe9457918bb7dc4822bd5de23c05dd732429cbc641bb03e8ce	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588627804000000	1589232604000000	1651699804000000	1683235804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2362a64e348469ec23bda2f9ff931c8f18f8aa129408b05a2ce7456688510659ecb39e56745cf2daaa840f4956b22841f886377be25695bc7c1ca4dcecf20148	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589232304000000	1589837104000000	1652304304000000	1683840304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5818f3a1d63d1741075b156015f65888f705d434334649c781aecf380c2c2846558f6be59d912fdbc98775e65e5dacccbe8d52a0e1016cd9ad7a48658b8e1fc	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589836804000000	1590441604000000	1652908804000000	1684444804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb6256f8251f659f0448b215a96df61524f87dcd383d305ccc08b6355dded68d16b50ef77f238a9acc8771c653b00cdb1cf1cd7e9d3becacd5cbcf710d12a7a3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1590441304000000	1591046104000000	1653513304000000	1685049304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa36e8cae89a07921082cc226f5ea6ad0338d301f8d437b13e1179ef972dd7365aea0d7c3b41f04a82f0b5f38066b68ddbac5656acdd108192849ce660b47e853	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591045804000000	1591650604000000	1654117804000000	1685653804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2655dd09ba307025dadcc2ab9855997dfd9278fcbc399ff826346e83b8433cf3420b4fb99c3967721b55bcf08ee78ea18953c2084dc3a24c57ce3aee44d038a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591650304000000	1592255104000000	1654722304000000	1686258304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e31509b0ca50f4dc1dddbdedaebe299f0caa0a547375706268b36bfca2cc8099f6fa3b154231cb2ee1104dbb71cc12da66c7d8d7a304f1be191d7b198ba47ce	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592254804000000	1592859604000000	1655326804000000	1686862804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3bc4f10c006010222219754516af30ce32b6897e538b3a04e8bbc8a93b31ef3a82e037528b9801ca2b616e679264cbdf0565fc3ed012f1e5e616cf3f90a2fc4a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592859304000000	1593464104000000	1655931304000000	1687467304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xafd0945d118d00c7b7a781719121bbb861de70ca8ed770631a36e4783f7041dd34a8146900423caa938fd87cc5070fed8b4a83223320d9e33d16c86e56a422c0	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1593463804000000	1594068604000000	1656535804000000	1688071804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb665736f60d2106cd4ba869685807793d003cde792f26ddfb3e410c7437e34498f97c0c04c7db1492f881f92ac2a430e3109746e62b5aa3b94e8bb2f89d60687	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594068304000000	1594673104000000	1657140304000000	1688676304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1be134950b4ad894fc8decf4c97470192af5c88f643137ea5aace54200b13e2927ffebcff3a24af07a15376841300d90071b3dea332dbbd8a8c83dbf353b237e	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594672804000000	1595277604000000	1657744804000000	1689280804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c50b00ccef64146e4ef42115295c1a61c5b4c287a25537cea5848afe89315486143224ef75868196785f5779b148292428d7f18e684545e768fcf6b90469b34	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595277304000000	1595882104000000	1658349304000000	1689885304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x786df393c927f913c83c7951a4b2a5457e7a41659340b640cefa9e3b8cc95d01bc21156817760afe4b581b4a52075c82bbaee7e49ab8397220a77d6d27104550	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595881804000000	1596486604000000	1658953804000000	1690489804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x25013dd023baa305da6d48550213cb2850b9d522ecd3fdd4fad6c21b97007665db45a814188d05ccf57c3f6a424824a85e7408fc07664afb5d15b172ac528efb	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1596486304000000	1597091104000000	1659558304000000	1691094304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1cf362f7ecfe9b5b34b44cad91dddc664df95a365ccbe96d6fa42f848b3f7bc9a26209da5d98b109212db7581701b28445eae12eef8d2294a75df2d1c3201762	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1597090804000000	1597695604000000	1660162804000000	1691698804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2107cccfb64078d70a5f05193acca64c78ca4feb0d960d7a946381b054cf9188e64012490b5bbcb4ced6efe12051ec283384a508e0d7a77c1c3e6b8b1e60e438	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1578351604000000	1640818804000000	1672354804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb030ac747490399e8c98b5a97cb28b143752b492d8921d846936c58c6896d42e7b693722977af5c374ee5f43774b391acb91782ed3a79d76466c9ad3e986d604	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578351304000000	1578956104000000	1641423304000000	1672959304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8bf4cda06fbdffc61c9d1ac24229e3e446d66ca5c24df21d7d3cf164ef719b2b1611f23adf8062ee459492d40ac5e40392b825b4e1d45d3cc0e5649fa14de3fe	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578955804000000	1579560604000000	1642027804000000	1673563804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x10102c26d3310d9c824c07af2196decb33a565f533b3184d4a22fc9901cac5307231572727cdae2c47e9e1743db057a13ebfe59af9d212526dc265ece435f56a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1579560304000000	1580165104000000	1642632304000000	1674168304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xed68b4f94f5362c58f1913523da3ae39d9cbb4f98788ee599f4180e84981e7d53e2665cb520b5f08e916f7be1a2644f41cabd1823762460284ad21938d882819	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580164804000000	1580769604000000	1643236804000000	1674772804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa2ed0ce478ec937793623f0c6a2a0d01cb40d5f2107ff92d316fc7c610eca0734b8ab1c149214f1fab18d9829fd0690a828ee411f2318a08d902cb01ac446dd2	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580769304000000	1581374104000000	1643841304000000	1675377304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x08cdf8760627c75bec5d0b6dcf8405868fa64e75881a4380c1c04c32da739fa9dd54997c0c461392a9151cfd7033c37ddf762e52ed9c161fbc808650e9d01c6a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581373804000000	1581978604000000	1644445804000000	1675981804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x093b68885bf3c38c1e91694656c9b4923d338e25d5391bf2dbfca81e7c4d2c4f984da8b06458fdd90356afc3e29dbdf1a16c89c52533d437b2d6c3444494b4f7	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581978304000000	1582583104000000	1645050304000000	1676586304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb4bfe072383b8e26a27bd48c7adc24ce44e8f495f1c6fcd558022d8d769f829b931bbeb037ecffa612aa1968468ad732f02a2771fd83eea5d6caffb688c86898	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1582582804000000	1583187604000000	1645654804000000	1677190804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd428f1b722e87f0ae647364f7d25d5f981500a08586f809506d35430884ae1430fcfdb886e94622ad86223db87d3318b3041728bbab70a3845ab22764025a4cf	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583187304000000	1583792104000000	1646259304000000	1677795304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb31579992aaea7137b676f77ad33b988244b8f09ef7fafcf596a3b2372762666344f7c47a7436928738c61b1a398a6e586a686de074e7989fdee599b99e5f41f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583791804000000	1584396604000000	1646863804000000	1678399804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x921c275df36716ba11c3aac1575332290636a15a9cfe5f2d37352d8cdaea540bf7e4127cc9c1e2bb4f38f069bfc74f9d9af3d60f5c989b5707737163bc9080ef	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1584396304000000	1585001104000000	1647468304000000	1679004304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x36e6585461edc03f352c339f2a0bf04188d4f28783a597827524123fd4563780ae5880373b10760705395cd1f237ad575175a0e99274dc40e925cc02b8d76b78	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585000804000000	1585605604000000	1648072804000000	1679608804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x53b6a09d77c6907570f83913b8612e25b57ec140da97ce025ba61ad5f8566c7124cff1da5a2dda1f018de74e91f2048bdf01388ad0293548687cb90c7d278f59	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585605304000000	1586210104000000	1648677304000000	1680213304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x04e964a02b57796003d984e102adc632f671b097eb3ffd23ddd798bead1adc6b156c769c137bf44c1474dd13ac3bfaf4c13ab1259f371548d72955d820aa15f1	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586209804000000	1586814604000000	1649281804000000	1680817804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x27c3b5d199a918cef1459ed25a59be41ffb7d9cf77f7e7a6b803e05292df45ff1edacc5d89afe2a5b19f731ba41ad586eb405106288f4b5dee7c84ef975a38a8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586814304000000	1587419104000000	1649886304000000	1681422304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbb944187f5ce9d6133b76b7e1b5e8c413fd51336ed8170b6861e524c54715e38a35061a19a4fd58720375ea6851a072e5f0687b6dbd4f3649655ced183cf76e1	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1587418804000000	1588023604000000	1650490804000000	1682026804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x437c0dde7c558c6a79b54f2c60dbfa524b0e934221729f59bf161ddd677d4b51e48fb182711bf5e099868add5e70140c9d5bef3dbb3d14709ad8e070454352a2	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588023304000000	1588628104000000	1651095304000000	1682631304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6c9888280e562811423d872ac8abc9c97177b67693aab6a785a949c5b9b617be37552377d8674230214b7b934203a620151da0df0f00e13e0acff8770ed6ddc5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588627804000000	1589232604000000	1651699804000000	1683235804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x773f7dac5c0aa636431be25d74120de96e01e3fd3792e9b45194903600170b4b14854e51b44399f9db5d301df7accdbe3cbb3c98fa95c061322dbae23f04f0b5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589232304000000	1589837104000000	1652304304000000	1683840304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe09dec37665eb6491e3940a628b3410636b42170a0f0a4f50aca1e541615996908cf561efbdda8e321ef413cb9c061e81169529c1e15ef6269acecee92252140	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589836804000000	1590441604000000	1652908804000000	1684444804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x381e751d4dbf4b18037460d845ec470b97344af5c3b476bf5947bf4c76ce4a280c951cef8c3b07b2da23ac01d301dc38353801beb05982ec20f8626d74d96a7c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1590441304000000	1591046104000000	1653513304000000	1685049304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1286d46e8f710a5f475985759782649dcc040436c08bd34887cc59203434ad8de668d1bd54ecedae57edfa7ba84f9a4a97a68429975a7348434a5b8bf20462c0	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591045804000000	1591650604000000	1654117804000000	1685653804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7ca0c00796fe88cbb7438183b0f49b5b236ad75c4bd75d1b965d910edd64829746b90d3fcab0a4bd774926d81be433b482b26379d50c30e7a3dc2ea2450c5763	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591650304000000	1592255104000000	1654722304000000	1686258304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x15cd4be2574e75fd0acce304abaef4201292e0727273261b11bfd7b6cd36fc46fa60bfc18d256ffd0a52cc900bb8043fe391935c999f94a097ae6111a179d348	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592254804000000	1592859604000000	1655326804000000	1686862804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x84ba6e0b6f5085430fca4a3d8e557f4c85ad4b8f9a8fd85b960943883259481a5edfd39e298c1d795db5d83f29f1d48832dea0538204f0ce8622fc9122df32a8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592859304000000	1593464104000000	1655931304000000	1687467304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3b109c041995d1fe522c4d55809ebd0781b53f1e95b7a4afd0f61c42fb93a046a8ed8028f420847f3972d6506bb50cb9d2d8537c604338692dee5bf230c6931f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1593463804000000	1594068604000000	1656535804000000	1688071804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd7ef260f75fafc7ad7104e26d1c8ff232d37b5051c27f5168af1619914094a92add774bccce01e26544b0d55c7e625c2d6e2ca0e49fa945370588a0acec9a031	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594068304000000	1594673104000000	1657140304000000	1688676304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd84e8f1a431d0a2b1f8be0003ae78c70305fbd28ae676504cee1897c2dedac8501e872226fad5a93ebc2273f36cb8d250d1fc2e909b80334e4b3336540666191	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594672804000000	1595277604000000	1657744804000000	1689280804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2f7a3e72578556ef5742bd94fd9d2abbc9d338ce8f1f679a1e4efeaa0560e58bf4dfb8ede819c72891c89283c846e80974bfe75caa44f6b1d335e6c6ab542369	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595277304000000	1595882104000000	1658349304000000	1689885304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7278ca99c4a0ac717c569d4fdcce7ccae0ad9f478c6fb1934472868e92f8c664ed348bf16b3bfc70a02fea4a5b6cff7746e499d4cf485c081b46b72f201d9112	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595881804000000	1596486604000000	1658953804000000	1690489804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x881383bb66b5e076bdc6bc7ad9b2a7b9f95f545e820ee2a364ed18de01e74a4783a7c4196c0c325edbf3ca8c21636d198358053d1bc2962036931d4500bc949a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1596486304000000	1597091104000000	1659558304000000	1691094304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4076ba344c3ef4224ee1fd02a0bd64eaad77528ade0be056650cd94295a758bd9a38436f887a73caf0e789540dd130c8ac130dff760fbe19ebd8e748e1a47805	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1597090804000000	1597695604000000	1660162804000000	1691698804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x93a4d6fcdcc731fa97d39c1ef135c76fb597e8fcd5555b606064a53ed91f0bc89dd0dc30a97f0e93f21907747e9859076e59fb0c22a96154fe1cec7395b1730a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1578351604000000	1640818804000000	1672354804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x09e3b17bb9abaf7fd74633b31d9e4727af6890a590f9a613a9034e384f766cf5fd55220669d1810143626d05f9b488f0d8f27127855b5c526e6abf9261677876	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578351304000000	1578956104000000	1641423304000000	1672959304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8bf4cbba06faabbcd9db091cf1f691146a8b8d7f19506f666748a97b081d996d90a0a1edb5d2a429cf2614b0942ab6bedc0966390f8fe5065cf8fce8890745af	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578955804000000	1579560604000000	1642027804000000	1673563804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x253c7aab54ef1933f4134ccef151b9e5634fe35d2d689b7d6810c999f37090bb428da38d2597d56e44f87193c4536393aaa1f759bd2aba9651a7a7dc40ca31e4	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1579560304000000	1580165104000000	1642632304000000	1674168304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59808885fb4da07d196d1d11d3bcb5a5ee2cbec6ebcbdc33d8b0d8ff5374abbc765248625f501b93d174e0613644051ff76fc292ff020a6a82a6785fdb20c7c0	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580164804000000	1580769604000000	1643236804000000	1674772804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a7fb0be1daf37de6526a9ec316dde9d3d25eca46854f38dcc39359c1f0df7fba3d1b688e33d2270bbfb11c35337e0de289c5f28d202a2a514554420abfa18d5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580769304000000	1581374104000000	1643841304000000	1675377304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb7728d643e2eaddd198f572c4c5e4f060a7886ad345afdec2893545cbcc255319f64dc57f1fd94031db57f18d4668984f6b55168c6034a4181a0dec82cbf91ef	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581373804000000	1581978604000000	1644445804000000	1675981804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x28019651741c46a12c1e65cd559222f290cd5f5e14f9753daeeb689dbf5f64258f5cdda1e41d2e98fb61b860e962014c92f76f4eb711012e1726109f299344fd	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581978304000000	1582583104000000	1645050304000000	1676586304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2431dec9a45e62524e785d6cd39f3a64e3727b77431fb8c6a8e02ee3912b9e00096984c8841c6a1512ff4596a9dbcb6772dee2e3e59dc716fc93699cafbb5dd9	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1582582804000000	1583187604000000	1645654804000000	1677190804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc9b78ecec11396e90be8089b43b6ec1c4c31d03e47cf67c727b2104d699fb0ead220135de0c6969a381b002668b4119f0b36b52fcb06e151d8725ca42353f132	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583187304000000	1583792104000000	1646259304000000	1677795304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc84ed75af755a5f0c0475cc043f37146ddbbccf6cace2d3bb21cbf3cf672e8b9016a1e0bb2c3405190288899b5077f6e88dabb7299d47c6ec01df55c0f461bce	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583791804000000	1584396604000000	1646863804000000	1678399804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5df35737205eedee089bcd6d31012b650a4e789e9ac10a21c5922c2b06f5af518febba48c8d90f69df8c89eea7f556d15406912616fcdcbdf0463f4ccec07a43	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1584396304000000	1585001104000000	1647468304000000	1679004304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x61b21ea0d3035d2778c602b5fdc2735df3c38dfaff411ac091cec89c8b50051c899ca1257159685a4fa34c7821681882f31ec3a5b1bfa356b3d0f5bdcd2a3577	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585000804000000	1585605604000000	1648072804000000	1679608804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6241b447db79c38414120967af1f269e6a49c7af0b97b7ca784b453d0fb899ff12ca2afad596f81fb6dc799da4f49b503c07d94dd36518efa81689502b9bd6e9	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585605304000000	1586210104000000	1648677304000000	1680213304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33c56220d9ab95893ef495d92ac96c70c97c35bf1f8fcc4faa1eeb3eafd7d52b0ec896cc85f3f74c3867261ded0660e8854cd32761132174360bd67b277ff43e	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586209804000000	1586814604000000	1649281804000000	1680817804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x572c30a8b2550c867fb2a026e114b8b32824142961357785c7e82c0dd2ceee4aaf0c6643c914a399960df9250b13a0bdda02e46a9893e7cef04a3d7e9d7ff962	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586814304000000	1587419104000000	1649886304000000	1681422304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd34e09483963c3f086c368fa347dd031e489a551bec8d78ed0162e72677a003c0429ce2c653f2fbed33a7bb9072dac852763288c054d5f640d884c562af77641	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1587418804000000	1588023604000000	1650490804000000	1682026804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf51822c145f30c978e2f780eb1a1e72248f2ff63b3d2155ca2da16737ff23f270912bdcfc2512fdb5711c7ea84934b1cf5f4c04d661dd61b7facd9ce8fd5ba00	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588023304000000	1588628104000000	1651095304000000	1682631304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc79a592662940453bc912618dbde5937fdcb2e32a274d3a54064156ebd6d9e6be987206bde39eeb87bf329cce79f231b81af39ad5d69cde077e2c0c4e9d33cb1	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588627804000000	1589232604000000	1651699804000000	1683235804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x62b8079669a0ea3b513c6817e400087c96d50ceaed00d081c8796a9099d3b34c095ba92a5f20aae72b7ac1deb495d5e7bfba4f4a3e6cf843bc4e067b66dc153e	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589232304000000	1589837104000000	1652304304000000	1683840304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f0df4571045fc3ebf39cc856ed7a16071164b91c125d65ce936bb4131609b961194744bfa473fb0856db5cb6332b539150f225792329b4827311177191f9ec8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589836804000000	1590441604000000	1652908804000000	1684444804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x25d92eea00310ea3b1a1a69bf4d36e6c7199ca9ac1db8dbae35ae595fbf700e34f40a41e4e2de1248297787ba00d99d9d74f26bebac242d414304e1a183416c3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1590441304000000	1591046104000000	1653513304000000	1685049304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x755939493d974195222baf42190bfed15777051912e19c6f5601573749773f8e35da43134af2aaa29cf1ef5fb63e45f2bef45c9084026214b94572f72685b852	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591045804000000	1591650604000000	1654117804000000	1685653804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b62a9bd8b2c73f327a8b786844905b00c1697fa8febf4daf8b1d60da16c2896069d7c93c2e7c044633cc225b5ef372f2247b0229a1a22964c6d1e1df4bc0dd3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591650304000000	1592255104000000	1654722304000000	1686258304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x268aefdc28abab5dc0676d10fa73e54336c376b6f0d0cbbd951d72e8658f75677effaa38231fba298e9d57c17f1c015c8a8c06420ee36e1625f0ac882ea99397	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592254804000000	1592859604000000	1655326804000000	1686862804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22438f6640ede3eb6ac40f5c845840a17e1b56408c560c861c9318c60e269305873fb9f90e53f2935036cd4dea5ec1cce327c0829c8bdfbba8e27aacb66d8d7f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592859304000000	1593464104000000	1655931304000000	1687467304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x43bfd0bca7a97536f30b82bd64097e131130b6fd08bd38b47721e878f4e605fc5c1ddecfd4d6922661b353944a86537d3aaa2743fc9609ac024cad2c473aee8a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1593463804000000	1594068604000000	1656535804000000	1688071804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c748eac823eaec129c79ca7405cf811bb0f666892069d64766194f7c321514bce0c317692aa13b60c88c97ee274d82cd4337ef5bbafcb0d523bbc4ada3effc6	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594068304000000	1594673104000000	1657140304000000	1688676304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x79ca000cf1c5a739b5dd1e9a4745ac97386ebbf9535da019f9f317e703bff0f37dfeb1188b04c5e9fc9f029a23304bf632e7f1d0b007fc7ed47774b4b39dc397	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594672804000000	1595277604000000	1657744804000000	1689280804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c9aaa1f916db065d974d9c6661b89c9719458efe5ae25d6ac46dec44f960481f7bde890d090d585505299183b23846dec65549dfdd952960235b51017b18bda	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595277304000000	1595882104000000	1658349304000000	1689885304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fa46507a49ff651cef0d148544be9688123b7bad726e0aaf1d8085ea2a9c05b2e13fa7faa390218da5e70a2691f8c207ba6ef1e646ffc67a6d72473f7dc2e4b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595881804000000	1596486604000000	1658953804000000	1690489804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x909ff5e3990f1d3adeff6903a680bb9e44484fda95280f4a753688e4a1f92989cd88b36f0eb61b082bcd95b8672ae6f3083224c4a79950d9f673c04474e5bed7	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1596486304000000	1597091104000000	1659558304000000	1691094304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x26bda28ba8134eb2bfdcef636d862e8b141bdfb99f34cf7d705f4278052b5428e42ecce482439274b3a87c8915cdb9a9388bf62b31d0bbb2e4950a374c9cffed	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1597090804000000	1597695604000000	1660162804000000	1691698804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c484596323aaa5e72d70eb101878f5184dac6f5b24d4ecac9d3edfc64497a6066e4dcf89895fef6b4959f833de8189cd9f8d7353cf097b7845feff61d36f7e3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1578351604000000	1640818804000000	1672354804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd636269488545690e6ec28fdb08716337d32e1f750d7950b5bd52173d2900db2e4ed4122c52b51fb6e0a94baf0b56118fe66c66517c06e775bf22837e69a9523	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578351304000000	1578956104000000	1641423304000000	1672959304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x21d79b215412b1f218b163180f9a95427fcb7bff4b1260ff605949f97574b2f578e68e30e5a0fd8e2845ddedaa6f890002ce27b2d28b76663aab0eadc5cf7b89	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578955804000000	1579560604000000	1642027804000000	1673563804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd11c711a3c727b0a94c23f3b7827f555140e5d0a91790a088a25c6a62e1fc103e4922f20acdfb70eb5ca8cfdb9b5014e461ce30b01af30677344dff99228df16	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1579560304000000	1580165104000000	1642632304000000	1674168304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xafdcc403075a74946b1b6d0dd3b61411b81f45fecc36438e8bc574cf2df6b84e5d0388e37502f117118b03974c7a41af60b84617f4f0cdf7c241aaaf3708b334	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580164804000000	1580769604000000	1643236804000000	1674772804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbb63b5c57c5c713885a6a7a432f7c6417bb4ed40d9ec8ee282f28e0b4cd1a8481796875e16c5914309368a366dddbeb76460d53b701386d3ada585012236fba3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580769304000000	1581374104000000	1643841304000000	1675377304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2a2e86820bc71eb6a326663441954c792124254f3965451bc2b3e918f8f20a77deea65f8d7ee687148d6b7c55ced35aaac6d68a2cb54753a7d7f1e9f99705c05	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581373804000000	1581978604000000	1644445804000000	1675981804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3682b0b45643d4d0badaeb0db2d17c454de6f7e416a159d7c9e8b54ef7eb1255870f977c47c01abe2f4ab8168a083b99e32f676e4e940b941743d2b2d32241b4	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581978304000000	1582583104000000	1645050304000000	1676586304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b82334adcdb0b185c0538bdada30a0ee4b098f0f0d34551418acaabfc93567049d60f6a9e95e3642b3ebd5e6a8ed1a002a195d3d61b659fc0fb5785fb3151a2	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1582582804000000	1583187604000000	1645654804000000	1677190804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xccafe75f289e89dd68dca32ee27d2488449b85938fb5560c8d663998b0752a93e00d9f0a9bcc17e5c221256c75210930c0c448b22565537be8008a55151193e4	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583187304000000	1583792104000000	1646259304000000	1677795304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6993e7df749c103b01a650c2cb7dffa67517d5669d54f551855b731f3219c60406b222bbe013057d38bb3407871772dd36c67ded0890eb67687a9e2a4c80d337	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583791804000000	1584396604000000	1646863804000000	1678399804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb38aa3556e6bf0534cdf351800805630d352597d64204190a61bbbf4664e1204e2001adbc4a3d8b7fc259ad24b6e301dc3361e1db86dae7f8b60cb8f4de45cba	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1584396304000000	1585001104000000	1647468304000000	1679004304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8bf2f3acc0f846da0fa66b7cc8acbfbccfd08ef0c4733482995f65bb06cb948544a9d8e93d6f2ac610cfb6e27ef84471274f418ec7fd8bf6b6e1dddeb23ba375	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585000804000000	1585605604000000	1648072804000000	1679608804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbab7bbe0d4ebda1d4f186aa30395570f46974d9bd542c0dd8060e0233f4ba9fdc09627ec4ab7882b5dac37a58b96f7505535ea0455fb45baefc9583b588dc290	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585605304000000	1586210104000000	1648677304000000	1680213304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d56266f8692bc109931024c7b610d1f35263b82cfbe1bd10dd264a6fa1eac3fd048b8a62098475ac9220f1104d6a6922422ab0d5aceca4efd71a07b0120cf79	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586209804000000	1586814604000000	1649281804000000	1680817804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0445ab50161bb5854debdcdf7588306f39716fd8a92d66cc680b3d68e7d5db532bebb607dfe745c7eba49721df14845997fc699d9ed63625224e18d147792c13	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586814304000000	1587419104000000	1649886304000000	1681422304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x00e90c7d83ae8cd52a0346637817f76a80c0514a73002e9437254fa058e3efd084c8ddf06e537b21b05178522790a64b463ce970f041a60a2714e299de94ddb3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1587418804000000	1588023604000000	1650490804000000	1682026804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a9bf10471f9ff7ff1156b95d7b44ea6072855ce6751038de0608131c6a1e974574d5e55ec02a774b01da3ca8fa50984ec35501029bc571719f84c3a6112b9a2	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588023304000000	1588628104000000	1651095304000000	1682631304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2898604907e2a6f8d767c34e7bccdc215c0d86f3405ec3e2797cc0dacede0e3dc466bce503d67b5863457075b646d144e12e282b16c1f7f721aef493dcbff289	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588627804000000	1589232604000000	1651699804000000	1683235804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa616c814e1f62910a7cc00b58426f821b31daca0833af58324eaadd3e56c71f586d6729d655a3c99f2d33c79c29fb7f3625c46cd344977017647307c4f96fbd2	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589232304000000	1589837104000000	1652304304000000	1683840304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x84c0b8c013f328d8b0931ffc0652797e04ae76a673b8fccea0988a4bb4b3028aa91387f3cbb070d6baa6aa1e1ce4418aac9d0ef29bb341c32996e9bdde1e4d85	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589836804000000	1590441604000000	1652908804000000	1684444804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa9677ffb6091053228c31388db744e862def1713fd54c5ddf1bce899822400dbbd84f612a7cc6991e73c800d43076c90426dab66a177d365e52a3d3dc782593f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1590441304000000	1591046104000000	1653513304000000	1685049304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x63c04b8c9876287b5616fe9ba48c10b1dbd5924bdc7457f5a43132c3d7531e8f5d0fee34fb9f65264f6bd5667a1810d363e0c24aae69bf8bb286ddade79be354	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591045804000000	1591650604000000	1654117804000000	1685653804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xed98b81bc225135a5669331d4737e0efb043531f272d680f049a2e294de2eee2060b68b5eec51f222c82cb079c18e49b57fa89daaff08a9b84ea9d0efc99c412	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591650304000000	1592255104000000	1654722304000000	1686258304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1735ad2c7f9be36f1bb8c863c3ff3ba250b2cd720ef1f16d1adc05929a2b75cc03a5434e1e50071c84dc00e249d970d4fb93ea2e95144c356dfd0b9e8b389e08	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592254804000000	1592859604000000	1655326804000000	1686862804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4645723441d1e8cb0f14615fb972edc8be8c4f9684d4b37bd63d5d4bdfe550f7f5d6a4141b4c4575d947503d9fe72ff94ce610f7cd6506b36f95602d32ad9cbd	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592859304000000	1593464104000000	1655931304000000	1687467304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa35c245c83d88ec382877a534378792596ecb80f8a426163c8914a2b36b3b1b4963c6999e79ca47543b829d0fead6381e383ca03e17575c82e18483fa772d183	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1593463804000000	1594068604000000	1656535804000000	1688071804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x00b71c1cb2fd7d5fd64414b42c84ba7cf20f9615552f6ef34384a610be6299a8171f7e3628f1e512bec7dc219dd8fa5576e7b6c44c8e1788ff72671f0b157c05	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594068304000000	1594673104000000	1657140304000000	1688676304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa4b43796dcc488eca3f023f5fe3602cab71afd672484815062d3d01b6cca207f12fe0bba4f4e7edb44591aff889b69d0dae12790ec981317a407da41c7b86d8d	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594672804000000	1595277604000000	1657744804000000	1689280804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x52ed9305fa222753c1cfad0bfd425cd57cbc8a84f9772aea96505ebf7e46cc941fc702f52f1959f2b651e6640995216a159e76eb59e5aa69c65ba141f2db97d8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595277304000000	1595882104000000	1658349304000000	1689885304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x87ecc7d3a208de2a6a767204c6db076433b0100ba8df9a535a307d8632b35dc90efea9ce5cf25564ddaa62a2b5346ebf99d2e3ffe5f436d6f2d8cc8887edc922	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595881804000000	1596486604000000	1658953804000000	1690489804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdfaad1ccd391d451c797b745f62263a7eb39c2e711d0135f75c1892069fd3e9611381e645a35c10ed53b34efd0fd96d86f0c417e37c4823aaf43f6e35ed5fa7e	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1596486304000000	1597091104000000	1659558304000000	1691094304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x55fc66919fa7c70189e97a346ca0d5bb8fdbb920b37c17b236291b1a85ca3f6a441c94aee06e62354d5a1f17fd4190aa0208eb073897c36750a80995bbfabcdf	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1597090804000000	1597695604000000	1660162804000000	1691698804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x661b14c509048ec3694fe0329446689320b932778770f7f0027b67b69ca354c225c258fa82f624b782df0d8f72768e42633dd43dcd9664d124e864e5563d4e36	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1578351604000000	1640818804000000	1672354804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x37fa793afc45755fde48fd1b1387254202326451d1a96aa806bcb7ebaf14d4c8e8156ad7a7069ab00d3f88c681939dfc17bfe513f7477c30885e9ae40b33a650	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578351304000000	1578956104000000	1641423304000000	1672959304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x719c7c0c96f130a28aaf72f9f370d33270f33c66949e3ddd2ef7d01d6a95928e02cf60224c9acaf6b3dc0dc5c7f75f7c761f3ef2d7b67c1902a826d10d88b310	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578955804000000	1579560604000000	1642027804000000	1673563804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x83ff978af9626ee303e7ac926065a76b276f993d1d5004373579dd6e2a1be5b8648b279438b0fa1cc00832e0735ec88b16f70cda3abb3eb27a32badcacff2ebc	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1579560304000000	1580165104000000	1642632304000000	1674168304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x917f2e275e0fd5f4b9659eb6cab8c416aba67a1317bcb7b7bb4cfeded9ba47630f368a02c8aa839303d9d72533b7f8be6a1639b6ca26796e7307cad8c1ea9c8f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580164804000000	1580769604000000	1643236804000000	1674772804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5a6f493cbc8282af434a8bb1d91a3caf88cc2ef4f6128803376ad5f0410dbd0517da0bf770fe07172bb64102ac3bb71fd35e424183c4e861ab5e4310a4e825f8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580769304000000	1581374104000000	1643841304000000	1675377304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8cc79773734cb93790ec1961c9eff3b7c51ab70dc64219116d0280722e292ec5750dd11e861e573f92ec54faa352aa52076af396dc7975e46bfb8c17b878b891	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581373804000000	1581978604000000	1644445804000000	1675981804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x27c6e22d2eeec4bf9e5657b53e4675c6025e1bf1a3d68ac6535ce45b30aa50ceef947385557a72c1a7487ef46bec191c8a1228541d71bcaa80ced3978f6f2635	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581978304000000	1582583104000000	1645050304000000	1676586304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf5f93a4ef753961dc9c4e87bb8ba8cd591087a4795ba9ef311f5a9a1b88db826444a7ffd997eeeb0c5d6ba84b6dbf8ce5ec0190aff7a027972adca9b5e860dde	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1582582804000000	1583187604000000	1645654804000000	1677190804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x34a7c9ec4e58fe042a4795e68fd493daefedaf3035f57ef667c45f25d337d59de4605ff584529ce2d027b34e7c80e375f48fd745f959acf0a38cfe1a20b5d3d0	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583187304000000	1583792104000000	1646259304000000	1677795304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1e7edcefffd3516a44d8d67913242bdcff0fe953e2b5a256547e21db311e7983242ffc9511275b7b92dc29a7d01238a99de0654bb4e2c7036ecf44a00700b48f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583791804000000	1584396604000000	1646863804000000	1678399804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe3bc3ff5fa4656e792e05097b8707e87d66836da5dc3174e59e746eb79dd9a81588f498ed8870b419349ac24b89c1bc79d1e570778f993c828167c79d787b700	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1584396304000000	1585001104000000	1647468304000000	1679004304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa9d2cbdf5aee3d0392080d49106d0ff2fa813ccc8bcfcfb623a8c3ac62d205258fed2a47b21c8abfc67213f8a168bd956aea32118d084b17b93dabe3d8388eef	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585000804000000	1585605604000000	1648072804000000	1679608804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1c3b7941096fced5c5b3a1c00a42a522357e37c70d372d183361f0582d28eed962f32ada21ffc3d60e9ab2ac59b3aa08354218c00f2ad0c7cf31ad1615ea59bf	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585605304000000	1586210104000000	1648677304000000	1680213304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5833a9211b41fad04305f1df675d2ec4e7390cbb5a4b6cfc53aeabd06ea62666ab66db4e4aee80e5f064241de543c53dbbf13dad5c3ac3066dbbe670c611dc38	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586209804000000	1586814604000000	1649281804000000	1680817804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23bb9fb0ad82f325b2c8f5be11a0755d1bbe9a7700a36b6e5d39d9fdef0935ae6039c528e6eb0523d1b93efded003c4f1c6dde784171de6dfd29692cbac752af	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586814304000000	1587419104000000	1649886304000000	1681422304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08e544117eddb81dc53d18e05823d5f6042fb1ca00e5d5dedfc10c753e923705e7f3b3f6621a54ebd53131c5f3e150177d386c586972b09c2bb92291d34271eb	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1587418804000000	1588023604000000	1650490804000000	1682026804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb27a32e12c309c12996e20bf6bfc9e761e157648994e6eca9d344d43dde3848c6b922ab8cbdd1a964ddd615c6a7dbdc3c88bcc9b76dbcf59278b9397510751e1	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588023304000000	1588628104000000	1651095304000000	1682631304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f1eab179f37e4a944a3404dbbae7be3ce9f624f8d47258d04a4d801b77b3693a1f1e470c5e5a27e1725b5aafb3124cc150e72f1627a94bef5675a337a30a454	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588627804000000	1589232604000000	1651699804000000	1683235804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2534d5057fc43af48b31ff3d8eac0f0be0694320bffefa5069f451b96ffc8dacab2073b99b7d74d69d28a5a7504e87ee7843fed4ff42b92ce5ef0a4a9b0cec6b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589232304000000	1589837104000000	1652304304000000	1683840304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdb9676de839adde192a4e616dfe72cf66d2e2e19bc4bb2d87a581f4d8124e5ed0cc12be46f26144ae507eccb179abaad38d8498042e64e85cecece0507c30753	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589836804000000	1590441604000000	1652908804000000	1684444804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb7ab3a76ac48de2e38ec328c536cfed93abd0f4aad454bd28b2c7ffc5b8e017039bc65f1055749fe6bfa1e8802805c158dffac3c2221c0c0ac76e0cd5c5c591f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1590441304000000	1591046104000000	1653513304000000	1685049304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x28521782bf0ca9b91bc6c94417ff39f1c49c1baf87ea2d701f573b0b0fe58ae7810c9907426fe8fd45e79d1f7e4d24f804623716f9319ef144a143c0053904b8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591045804000000	1591650604000000	1654117804000000	1685653804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x632bc41f915590648ebd18a17f76276ee28619d65ecba7634815071ce85f3a14a6f87957bf03ffd68d4153e41ec52556c56b91698b564d819dc9af34317f6d79	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591650304000000	1592255104000000	1654722304000000	1686258304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4f6a47a88e65695f353c6ca350e6ea8c7fa62f6c499163221a3a01bf0686f0b9b0c198176b38b43f68428d67953cb830a6d44ce3221651583764ae32cd3ee45b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592254804000000	1592859604000000	1655326804000000	1686862804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0355dceaf493b4a1e3898d7168408d941f017273e1313f3417656c6c924c44a642a3e34ffbd7cc5a33eeb95bd7dedcef6304b72c52c115976d6f03c0a28288e8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592859304000000	1593464104000000	1655931304000000	1687467304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc2c34b5b5127d68921cefcd7e03c8f73e8a4e62ba6c3c7b45b33a3abe10ffd7ec8b7b2734aee0bf76e4cb5c156fd588e7a1a34ac5cfcda3c4e08551f7ac7cb77	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1593463804000000	1594068604000000	1656535804000000	1688071804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ddd23b19321a7218c58a01c22f3d74c9d6481c98b9d3f7b7d36ce1fe61da6135e9e96a1d1b1d5f442b85660cd822e336bf70269569057a95947787056a061e1	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594068304000000	1594673104000000	1657140304000000	1688676304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7d94ecf3e0034a6fb0e59ee8038f3c4c1d474863d82ea7689b27efea13584638d566c3540366abd54ddf85fa7f62a6ff43cff7854e49cf8ca413db57b14bc233	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594672804000000	1595277604000000	1657744804000000	1689280804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6dd9f9353a76959a6ed4f9d8143e8266d02be2689a7c3c3a8f65746316c5312f74c1f242edcde5cd87e14f2f97332cf39e7373cd99486e53d59ed23feb34aad5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595277304000000	1595882104000000	1658349304000000	1689885304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb835c94444bff008c15114dbf66e04e585097ffab1688929fb4dfc023079ade4846a11f633cbca34cdf5daef5bec954f084117e31b4022782d63b672732f0e1b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595881804000000	1596486604000000	1658953804000000	1690489804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8362edab3a04858ce0ca21ebf98e302162aab3d6e369dd1310d909009473771164176b7f3392788198a12a8c802c2038d51bc2f99e86b0a12de8ffb015039a53	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1596486304000000	1597091104000000	1659558304000000	1691094304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95852b7eb144f85dec1a1b5706765b7e9e8c54f43602a72455045af918fda9015002d386a65d2f73bddfcfa5a3332250a5c37655b9f703484e6773d6568f0850	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1597090804000000	1597695604000000	1660162804000000	1691698804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4d51f77f9139f8c80fa05f98a6b7b343c5d7dcc682eacbd6cb54064f68e8fc20b029b5fe4144e22df1132ba4d35c39e07f4402b6bdd0a8549bd724550bfb4b7b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1578351604000000	1640818804000000	1672354804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7d7f9de3358433f3d19f7ca37c5c616273b492483538dcbc69447f80d009e9beaa058d2cfddace77f5ddc2f9052734bfb2d4fae477b95730e67d3c8cce8f7a39	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578351304000000	1578956104000000	1641423304000000	1672959304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c7b69407b2b006dba3868d8d4aa30625068d7a57e919b082eed374111af6e0b88835ae23a54e4918d51b85bb58f20b3bd81e912c960f57754501a401fb76dc3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578955804000000	1579560604000000	1642027804000000	1673563804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfff765b5ee08890ba864d1bfa067fb78bf073f096b8c0205ee955edc1d4207b5da00240fa46b2c61bc4538ad8e10381cd9e79aaaf4cdcf304b5c3e84505e01b8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1579560304000000	1580165104000000	1642632304000000	1674168304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc682447fbe933380b31bff8138968a63efed96f89d1e77b9078561e84cabcf6a8cb8fe0c334912bcb68b45120db7e8c4bd93a1a26d7894872d87838ed7046190	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580164804000000	1580769604000000	1643236804000000	1674772804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8db17b99e9a6337492ab19f077425af36beb80e8ae3f7c1a281e835100382928d7521ff4739a16cd579be17d9b48867e4a3b385e4c64d295947270828d6a42a5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580769304000000	1581374104000000	1643841304000000	1675377304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x64ede5a6387b66be51b183069bf7f2408f5ed279d2f9f10a4b791736dc86c4a693900a44bea916e9b4e907a334ead23626c75ca932b2ea5d57cb5f1b9bafcb43	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581373804000000	1581978604000000	1644445804000000	1675981804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc61241f0b28009a6fc0fd06d50e06648c10bc682265ece2f3fd8234ff9b942cdeaea32ecc2ba19b61fc39ea095c5d72fed585bdf6621b2dd9fd93852116490e1	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581978304000000	1582583104000000	1645050304000000	1676586304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb5c9ff07f14df52a9209cd719aa47701cf70627739edd961876d5f50e5f6124d1498a03df1b3bd92256bc10ab783ee8f179c681747bb95c7c1a6ca340219fa09	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1582582804000000	1583187604000000	1645654804000000	1677190804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x094fa556ed5be0f7846e2cde4a8575e9b6c695ee8067cd19bf12d22060e6103fbbd3abf7d8625e16b31a1825035392505ec2dcb05349a186aafb78900cd282da	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583187304000000	1583792104000000	1646259304000000	1677795304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1cb6c28cad6e59b6b5729fa383aeeb30e7c1cc561311d6ac952f548bd2c8ba0f6472917d0f7868f2913562d036e14fb68df1f5a716ead88de896e9ecefb0ddc5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583791804000000	1584396604000000	1646863804000000	1678399804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x854117c2a803c5159784344076a74acb192d7e151e9b13cf1fe717894fb691b0e48291c9a6c4a603b98610eace13fa7543b8a7dbf68d627a6a2a4d93a46899c5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1584396304000000	1585001104000000	1647468304000000	1679004304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc13d5493db5010331188fa986787da4048527d0ca46251a92c457e1a12245fccbe2f4ff30c3f7a313c20ea1e45c8fc31a719246fc1b911a170f7af9afd2ba3e7	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585000804000000	1585605604000000	1648072804000000	1679608804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbe38a7b78891ca03863baab55eb4471582246c112602812e2a907161c83384d83e7d823ddb9047bfb7f16f7176a795e26c911e4877c11ad1b24dab6306269225	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585605304000000	1586210104000000	1648677304000000	1680213304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd7051708ed45c87199ecde07417d7ebf584b715756e8d0e6caf6bb6c93e835274902c887338edd3f0d5ae0570215726d8ae10847899b6480e6ce7d5ae786440d	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586209804000000	1586814604000000	1649281804000000	1680817804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4491c98f3d343bbe11cf393d55e557c6c9ffb4ad4692fbbbe80aa9948c46924d453d862f491858a5a08c4077cb512f2d8c580be8950eab8666052a6d6db16e5c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586814304000000	1587419104000000	1649886304000000	1681422304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1dcdd414566db70943e99c3e42b9ffb1fd8029c147ede015e5958b75f4fb792a5e4abcad022b9140aeacb9319d8fd351df396e51ab802980bf14ba0697a5ed52	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1587418804000000	1588023604000000	1650490804000000	1682026804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6f2c8c660b0f5a56c630fe6985e358a55f7e8c635d5dc70f7427ece83d851ae051f365df2271956c54271890469b3dbd8b1f14c2fddaa1cfe0d5d9068935694e	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588023304000000	1588628104000000	1651095304000000	1682631304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0335e8bcc0773677a6efc37d50ef026cdaa621bc2c7f87d875f6d649820bbe748f57b77c857f4ad24b61b5b2ffe90a64351a5f6d85075ea9ae231ade365899b0	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588627804000000	1589232604000000	1651699804000000	1683235804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf8856351ae7c78f6ca01ca6c9484828cc9311469fa097ab2d74d923ca91ea9768f8d2675b4b15cf3ef484daea853e75ee85c5d4796d5a87a8d07e4043ae78503	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589232304000000	1589837104000000	1652304304000000	1683840304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf594bc19f0a8eee3605fb2560c88194c592c0153aad654234b18d1eed46a16342e2d0ea1c72750f9261acba926e804a4ec3741810d564bf139c1d4a589eae7b3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589836804000000	1590441604000000	1652908804000000	1684444804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3f2eec20c83cf4cf6a9b0682c5a66c0497fa355df2e753a1d3d3322608822bbc0791af3edfa800762e104c3b4d036431f5dfae9563a30dc7194cafc1007cfc94	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1590441304000000	1591046104000000	1653513304000000	1685049304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xab52df56f3ec34b9bca460a5ed3c2e247cc7c9ca501fe55ee47f7de7c6e6b4fc4f07d6f13751d71d6e764fdddaf7825db01ebb96d9140aca8eb1c3276cdf9ada	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591045804000000	1591650604000000	1654117804000000	1685653804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xca1738549fd69a1ad6721d9a3642c835972b8f64167fb6cec93ba5efff3d6d5b5ea27dd4329b0bbcd68e9537d9ab8a93a289cc3f36ab3968591b7f88beaa6cbb	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591650304000000	1592255104000000	1654722304000000	1686258304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xed10533388c59d88fe70fe96b5f8a853a9650af955934c0fe67196b9863c76148dfb785c2c10e89e9fc485963bbd4ef3eb8c7a022f51f2e50cccac9f72545a33	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592254804000000	1592859604000000	1655326804000000	1686862804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x62d7274937d513d15908e6bafd6a9989991acf108df7b7f2bcdef81ef229fdad5418c6e5790c369e7641fe9df27c4132a878e37861dc4b57d05b14855c7f6c76	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592859304000000	1593464104000000	1655931304000000	1687467304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x59b741114c16856c6e32ebeb67d920237e4ffadcd5b8250587d3d38d77631ef17efe23263a30e33d6e83efcbd4afc4ca4edf7c67997ee1154da70705c086ad74	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1593463804000000	1594068604000000	1656535804000000	1688071804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc296382bd73c3856aa5f9595d783c4a600421807fd67fbcb4743602b756521843f59a0246a1ebd56c4ac19a8d28369d29e29d23fd957d1c23413847e178b7279	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594068304000000	1594673104000000	1657140304000000	1688676304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5c94afac45fdae1ded0a531bc77e3e5a4e5ea98f311d4f10dccf3cb7388c9c789454bedd5b6b84f60eade42e51d606891715c147d49fafad9774dfee0ad54e32	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594672804000000	1595277604000000	1657744804000000	1689280804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x04a7ea9b0e804ab14cbe3d027959efacdd830ab2f6817700c64a5bace369a8a36702918a4fc8a132eb5c911217878813ac8b20ce14f7471e1c0773b2fa5e1ba8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595277304000000	1595882104000000	1658349304000000	1689885304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8ec8e27dc2e8774cb0fbac21fa110be30a499187e59096c94edec7077ff647b7e1fe21af0560747e2364a9d408dedfc8bb028893b65c7294a27f150a3f120cb4	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595881804000000	1596486604000000	1658953804000000	1690489804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x57dad536478676c41da0a31920b18254443984458b5dcad5a999e86f41ec8bf74909a1fc8ed289331bb08a69ffc4267771bd675e34fdc377b749c15669f5e87b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1596486304000000	1597091104000000	1659558304000000	1691094304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0630867cf35531d7d8999d55a3c7500a0ef96e4b30ddfa78ba596f1882ae6d59ba74e4905161872bd6c1963669104c578f26aef10f205628df63b20b40cc52bf	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1597090804000000	1597695604000000	1660162804000000	1691698804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1578351604000000	1640818804000000	1672354804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x476d3aad7ada10117bbbbed43e25deec97ae7271cde0a3cca4d797d22ed433c13425bc18b70bb8e99ab3a49697ceab19c16af9a90cee61a685afdf3cccd5dfd6	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578351304000000	1578956104000000	1641423304000000	1672959304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8af977cb3c7aa28bb92f71142d3873e7590d42610ad82db8834e88c42efa7302acc6348bc554e23308bf5f43affdefef542ac85a62e2341d70cfaa6b25c0d702	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578955804000000	1579560604000000	1642027804000000	1673563804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd5dab022958a5f06f7a63c2745ef8433546d5af7b6703625dac4e511b9adac43f81366831d9c520d24ee907ff0c74f47386f0ddec4c3560a4cc74b46849b6e0	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1579560304000000	1580165104000000	1642632304000000	1674168304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7dbd56e2bdd85a6f5e83dbede979e26c6bc483aaa0ca8265b75e32353b193cfba0d050a5028b6d1a25d57e0738924c04136a141124021b1b6b3f282a16135799	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580164804000000	1580769604000000	1643236804000000	1674772804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x10c8077458ce532ca8ce58a5a1fd4e66300ea83748b4fd6f10442a4645a4f338a7f085436047e2222c9e15be8bf8e844f19a6d2e6460c70acc75913e46168983	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580769304000000	1581374104000000	1643841304000000	1675377304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xddceb29b5ae6694c45e59ace163fd87cf8d2eba91f6f13aa1a08a6cf59fc503eec55bb41740f5e2a2e55b90ef3da3cec96af10b0b5bcd74f9a4a7a063e964549	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581373804000000	1581978604000000	1644445804000000	1675981804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x024958359ed1408fa18803212fc0e84eae3330dfdf6572ef00c7d0ad4cc9599d66de963e60d59e934d5565cc52ad9fd08b99fe4e2c55425a0965edd30a4d960b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581978304000000	1582583104000000	1645050304000000	1676586304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1be8520aaca31645aa92977d1889e45ba117a9b442762f592cb68d88ef7049e61f3c0aedf7ca4dfff88da785c1a51be55b3f8a81a54ff3151eda586cc1e978e8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1582582804000000	1583187604000000	1645654804000000	1677190804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc1fe6e473e0f5910f79000245bc898305d726307475af171d4e3d85f99366c0051e834400fb61b9426014b85b360693c1b101cfb2f4c08f7ad2a7a57854eb3c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583187304000000	1583792104000000	1646259304000000	1677795304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2e1a9e28292c4bc02eb719a560fd94b935a2b15e1abea290e3968ee7cdebe126d761eea8b36f64192930be38b44f1240ce2f88d4c1aa096d68792256e82ae49	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583791804000000	1584396604000000	1646863804000000	1678399804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa9f00ff4093d99b1e746dfcda3d2f8c6a7faccf886f44969c039aa682672a471309450cacfebdccb4147e52471ab1e9aef0b39acb5e93b74bd1a67d5a9e5536f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1584396304000000	1585001104000000	1647468304000000	1679004304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x91ea72bc6da2fbfea84a8909b91d8d3e72859afa470e8f03f6bc70a7f4c54b94c096c70410f4d33296a8f591653d547f03e164da113e59b6e1f560c5f4c9756b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585000804000000	1585605604000000	1648072804000000	1679608804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fad572cdc2a2740a0479ebbf2d4e41df18bc2f0728729d04094ef0a450047b2b954160825b0a9d8b737880df193791765112eb48367b86ef580d26591f096b8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585605304000000	1586210104000000	1648677304000000	1680213304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd869583e784b90173510660a4a6440f21aa8fd0d0f396f855e2a004b395ebca9fc58aeea238f8c3584f830f7bd5ae2e96b126cbfd47973977e31e494393d136a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586209804000000	1586814604000000	1649281804000000	1680817804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd06472220dd65e2007ad7c6159f496c9c806ac0733d208701f82bbe30b531daaa806d9adcd79de305fe3845c647b28eecad6b2a88021eb04e2545cac2c001a77	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586814304000000	1587419104000000	1649886304000000	1681422304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x683fd8048306f51cbe2d173a973f1e9570f212ee90f7bf5743b1c34d325211906a07ccaceeb5540a0ef72f245cd124b926c7de765026389f6706226ad707a6ff	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1587418804000000	1588023604000000	1650490804000000	1682026804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7323a4beae54792e990a541312f3f456665e4874894015bf673ba7a2c667bdcd58ca24e0f899aa6cee1152d5cc17848e55f905b3e6d5af1dde44c6c4339e6ed5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588023304000000	1588628104000000	1651095304000000	1682631304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c4c18afc1dc18404df8d0bf7cbbb448f3a4ddea0813056c31ea709c01f788da3297054c5778de3098d37da2e033544d0a115ae37e27825071434973dc4c3df1	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588627804000000	1589232604000000	1651699804000000	1683235804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd4736bd2aaf87661152e51ab925333f955f01401ed096fb5502a382d82e8af3634591a612d114845211c2890f415b84794e14ae7c8548f73b2063a6f0f2b380b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589232304000000	1589837104000000	1652304304000000	1683840304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x403a7f53e00833992fbd7a13f7a28eb6a16ec2ae14bb8a121782ba8164fa37e3e7031935d73b27291b570df30f2568558a6aa1f9e216a2841bea78d8f95f2f14	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589836804000000	1590441604000000	1652908804000000	1684444804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa875a55c8fd15b717a4b7faa10bda759296d6bcc9ae1cac6b102dd8fbb6afb7657e2af95b91b49cb527838d383bc35e33533ee0b995ddcbf85f7321c43e529de	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1590441304000000	1591046104000000	1653513304000000	1685049304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x332b471b1302c7e9ad24ab2e99b9b506e758235077a50315ec00a099438c3d3af6adf163a26ad2d7be566ac96354c9bf4f95c2137e5ea2004f9df6ce769029ad	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591045804000000	1591650604000000	1654117804000000	1685653804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x94895d66df9f901cd2cda3bc16e7696ff0f1dad3bb0a6baf3f18647dca72d348d256128e09d73ddee6537ec2ff4123084352bfd4da7df8254bfdc5b09f48322b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591650304000000	1592255104000000	1654722304000000	1686258304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd43faf9513cf25412b9d329a7428cc0b3efc5cdc8f2d071025d244d20a292e3a68af93ceebba227bcfd4bcf5f430299d2449970f7946ac283bdb733cd11cbf9b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592254804000000	1592859604000000	1655326804000000	1686862804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1443b34295fc19c47207db0dd3aa07b1e2dd23b859f0fc781ab886a992fd03e00e80dbca1ff3d2a4957a8097838ec6f9ed3f7216e348067f89a45f439bd1852	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592859304000000	1593464104000000	1655931304000000	1687467304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9be47f56c33caa90d404d89811f7d17de9307674fe44996a38a9a993292f8569a4b2c2e2724fc02fa7567400dbb0872839dd994dd0dba6ab25090de23928283c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1593463804000000	1594068604000000	1656535804000000	1688071804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0f58aa3e3460a87b5397d141c8ed6efface9089fd7e18648a16b4db0ddab3c8a463b606ebeb769eb5b6c427b0d3b3d323c587961b2ffa5856536f285cfd96022	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594068304000000	1594673104000000	1657140304000000	1688676304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa25fd83d81f2d35426e6db5eb452b753fa056609780bb55a4421f9ae75baf3179e0380a051b35acf846c396af400e75f3d72b3cd95b2a8accacdad2ca32f642	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594672804000000	1595277604000000	1657744804000000	1689280804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a2a60fe0e25fadd313a8df531ea7b3d3edf3f21b351688d48ff632faa071abdb702201c3524b2c0484bf67c51f39d968729a1758eb9c91c682a1a3ac199686f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595277304000000	1595882104000000	1658349304000000	1689885304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe94fd94260595b2cd8901284a210e6d06fc49646213fcf1606d1f9591c20527fd417e5f76fddddc3654ed9880eda4f94fd648b24f268f5b2fda3cec843141717	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595881804000000	1596486604000000	1658953804000000	1690489804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa09d9e067d21621ab6ca2ae2f1ea8f81fd953d8f7efb56f386dbe36cc854888d4a8a638b7ebb75ad4bcad51290831613be6ab1ede7964db664a2df46b66ab20d	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1596486304000000	1597091104000000	1659558304000000	1691094304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x393bad8f04e30f73f90b9dc8a0edcdd4b94b4def82f1a22abf3e206f82dcb1f1274436594d9e9f8b221f08bf671db40179e15f7478297cc13759cd4f099c71a2	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1597090804000000	1597695604000000	1660162804000000	1691698804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1578351604000000	1640818804000000	1672354804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2e08b05c9291b09c3cd85607ee7a3876aa81fc8148cd1bf2f0a2a3be714802b33d90f1916ebbc9bc386a077758e87c27acd8afc1e4cdbc80fd7194a371637559	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578351304000000	1578956104000000	1641423304000000	1672959304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa7f6487984af2db227f6172b44a39b7322383ad01c9011ca30c5f3bff4ec6806b6269f3ebe5b3907516a9a3028a315994c910c270cd953760916903591e2be7e	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1578955804000000	1579560604000000	1642027804000000	1673563804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdd9ece836f25baf921204a121362af4671a21f5b48c7f80b186a8a4ee9d845386c88a7b16eb9cde9efd2e84c5725feffdd52c6de91a1e7d33a268925deba839c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1579560304000000	1580165104000000	1642632304000000	1674168304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xeedfa49fc8faa7a7cfdeff19134ff28f3afa8aa8cf0526ce05a31e35b88e92f044aa2545b380fed48fe0e3450a42454db359bea8d59718e5aee9b2cea7407fe2	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580164804000000	1580769604000000	1643236804000000	1674772804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9a613483d3634ce37ba4bb8f38429be9e3f51b44baefb6e2f0b1afe4b737661e539a8f6f986787cd921741f5a00c1d98ea3313aa48e0a29e13bbfa1b4916b6d4	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1580769304000000	1581374104000000	1643841304000000	1675377304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x16963acbf47138642702ba1654cbcaf416578c8679b5e07de8761b95508d6dd416196fb75943098ce33769af40a89cb116fbdc030d0c645ecee9c3923a66849d	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581373804000000	1581978604000000	1644445804000000	1675981804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2ec961a3f1cead343c0d66d0f0fea3a0bc48b638643912342930d6d4c0a13f7a65edf8032f6547543744108663f734e0727d17c80249671ac8c2ba9b7168bb6e	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1581978304000000	1582583104000000	1645050304000000	1676586304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd530f2397d6456e5f9b1fc9f2b3c05a17cfc3049230ac356df37cfd62ebac8831d148432bd09978c078c462c7b390635af71b804a0ec09d879e8987d187ba86f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1582582804000000	1583187604000000	1645654804000000	1677190804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6df681cfda5c55fe42626ac32b2b46633afcce535de77cabb9b3e17e6da9dc7c558036fd4ff43f338df0f31931333f3fa978a044dd3ca0aa70bf90df9bd2c4c3	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583187304000000	1583792104000000	1646259304000000	1677795304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x60b7985e3ee58914afd3f31e68870fc427baf4b72b04f04a4930821b82460c5e36a380f069df1eb7af640f93c6417e7f3d210665db7f0a31d37da6663d36e323	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1583791804000000	1584396604000000	1646863804000000	1678399804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x19cf5e614862cd9e01df078db9d008a78fba7226a0fc15b4ae19d4c01802bf5edd948bae7b5b58f4fedd425cfc2ddb0a68e4fa02773f485ebad0898a9193c12b	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1584396304000000	1585001104000000	1647468304000000	1679004304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa69c641d357278eea5ea3c405b908d979319b73614e4a2928887162b625151d75b010d89dbeded3571e607b8c50753dd85ad357db30f1b0f9a6a931c64feda80	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585000804000000	1585605604000000	1648072804000000	1679608804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x756b7aab6f194a28a6ed5536b9c8b7420fe6dbac260fa6b570aa34b98d71f28845958332c83ca046a6692a0f94d85a0ee1c5519b964fae04a8a5dd2a8906474f	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1585605304000000	1586210104000000	1648677304000000	1680213304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbfbf83555a2cf9ebf993b151840732532413daae854fe50ce4fe049c20c5f753fcb14e05ec2ee4daba52d1b956f3d8a8dd46cb441ad0093423c01ae59dc3043c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586209804000000	1586814604000000	1649281804000000	1680817804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9df22ca29f1509b7bb8128f37546b6a8d2307e21b0ebe04659cede30a7ccc4049dbc58f66baea9fa111fa72845894f516a18a1af7009e627fdf8351b6b0955c8	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1586814304000000	1587419104000000	1649886304000000	1681422304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcc63f7f943f419c0222fe31aabe445234b6df897447ffa3096f0be1693a05c125c2232c0a1a4a3fa889a368157d815657839608af1d819ae4ce2df161f48dc27	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1587418804000000	1588023604000000	1650490804000000	1682026804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd4024a1511ae68d712d59d8e1bf5f5c066d591739a9c958a2474cc5cdf8116de1d06f4ebc37c8694c56fe697b5168b07769c904b07b0c2a4b789a6ccbb437bd5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588023304000000	1588628104000000	1651095304000000	1682631304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x028292b85863b6809a36e14aeb274870689f6e3207584b218dcac3e38a2d58805062c87c620d561986ad9e6fdb99a3bf7d3100b427b8cf3e29dcc68d12c3ed71	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1588627804000000	1589232604000000	1651699804000000	1683235804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2a4ac9c32b99f2a892c9f202b8acecce8aa33f2135ac3ef5b5099e03fad78c1321488c1b8d50cf0334ab54259625c7986794dc9b59ce262940db078989c8cd12	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589232304000000	1589837104000000	1652304304000000	1683840304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6b4b0c8b4f086aa7aed723a9bec27b257d2420e4e443460431ef7cf419de5d3adde83bb4fd90157abc3e6146b3894df55f9fe219ff838323962f750fd06ae76a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1589836804000000	1590441604000000	1652908804000000	1684444804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x835bd17c5d2e7c3fe6bf7352f0eca252e529de9e9056c6be706fa2c6594b84822623bba5c119872a88b47d8105c5628addd7345d9ad0b72b9246522d53fc62eb	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1590441304000000	1591046104000000	1653513304000000	1685049304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6687f6f1f7ef3fcf0e96760d8a889ea5de6bf449f3a3217dc3ae11d752a4307c174263356983b83f49e426cb8f8d6cd886239e93553a8574226dac94880663d5	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591045804000000	1591650604000000	1654117804000000	1685653804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdc18482d77349a7522c98b3a0f712462ba2b522145c127efff629f438c2cb95d3285fe08a48394a17b124b17ca4db078becbf863bc1049eae28ea9a9b1f33781	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1591650304000000	1592255104000000	1654722304000000	1686258304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x35de28670a3f002ba8dd0b340edc50b813ddf2491b6c6b9a2d313052cd36f22b9ecf12881f8b95289469d05bb1c960807e808d793062064bf507a33a30399419	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592254804000000	1592859604000000	1655326804000000	1686862804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5254da76926c47c49c0738c714e04e5a30444329f6563acc52a843165c81c3f1a7db0616b8e2288daaea767c09a979b61aa97332fdae6169d82201be060e2d7a	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1592859304000000	1593464104000000	1655931304000000	1687467304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x104b24cd46fabe647299f65d2951fb204c1c30cb66af68db00b604a3afcd7a9e1e8800fdff733d55be170fd92375b99564ec88558c6a389433e582e12bf31e59	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1593463804000000	1594068604000000	1656535804000000	1688071804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfc2244c0c87b8cda6b88cb6d6e49c336c4f3955552ee5b1d1bcf672ebef5b0076218cfb687f1e3f0d1933a59c1d6c33207c25ec9f506c8ba528ccbc3365581b6	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594068304000000	1594673104000000	1657140304000000	1688676304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9dad9884b7c301c7a0bd4ffb233d2331690eaf73ba32185aa797dff3b07e7524e79e47a6db9068d7e95244204d68c9c98a5d8442856d25030a624b884ff75a85	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1594672804000000	1595277604000000	1657744804000000	1689280804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x03186f3d5a1bb5ce45ebbd060be0d029ace9025d179f83db89c1a46cc58ae2f07f44726a18ee53c5ad4c921b59ce4fc7f31b5ae5156de12e9ccc2be86d67867c	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595277304000000	1595882104000000	1658349304000000	1689885304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd415931884efe9a46a92530e1fa3a0d2742f6489e4c9357f9e45737b4716074ed8bab668afdf34d7a334a0754746b0ea79f4d831d987e6261dc1f3ea949b4259	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1595881804000000	1596486604000000	1658953804000000	1690489804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4f081b25a03bcea615cf72cd3074b91264ff49ae33406efdd1d80a22ffdc72c3bd57b276f68d6593a909f5866ce1583c789e8b482925f7d49fe72320546edbc2	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1596486304000000	1597091104000000	1659558304000000	1691094304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xeef66260914d236b1a47227de0da792fbfa8b19043e205cb309adace27cf8580a7bdc0ecdd628eb3b7a25fde4aebfc2efec91200abf2cc3ae81679ae24978d91	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1597090804000000	1597695604000000	1660162804000000	1691698804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1580166004000000	1640818804000000	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x5c499a721541890568790b6775d232c9cc8ed182f5ef1c37be91d353689b6846d8a43fe00383ef2f678c9fa24b2f729d76fe23576f391bcc950aa7c09a7d0c0a
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1580166004000000	1640818804000000	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x5c499a721541890568790b6775d232c9cc8ed182f5ef1c37be91d353689b6846d8a43fe00383ef2f678c9fa24b2f729d76fe23576f391bcc950aa7c09a7d0c0a
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1577746804000000	1580166004000000	1640818804000000	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x5c499a721541890568790b6775d232c9cc8ed182f5ef1c37be91d353689b6846d8a43fe00383ef2f678c9fa24b2f729d76fe23576f391bcc950aa7c09a7d0c0a
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-31 00:00:15.162246+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-31 00:00:15.237377+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-31 00:00:15.310515+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-31 00:00:15.377431+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-31 00:00:15.444381+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-31 00:00:15.511055+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-31 00:00:15.576048+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-31 00:00:15.640758+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2019-12-31 00:00:16.079668+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2019-12-31 00:00:16.519795+01
11	pbkdf2_sha256$180000$lTBkOdGz33So$iYlX+tgYA0J4sBgnwA/25ZFY1hnFiqsb84d34rmVzR8=	\N	f	testuser-OBM0P2dr				f	t	2019-12-31 00:00:18.163715+01
12	pbkdf2_sha256$180000$8etnNrlsi4YU$YCFajAwE1rv/re4Mk8OpfRLHdNzIP9LSmQD+z0RW+XY=	\N	f	testuser-6lleWuxf				f	t	2019-12-31 00:00:20.642487+01
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
\\x253c7aab54ef1933f4134ccef151b9e5634fe35d2d689b7d6810c999f37090bb428da38d2597d56e44f87193c4536393aaa1f759bd2aba9651a7a7dc40ca31e4	\\x00800003b5aa33e09c4f4079f60a8b434ea653ca5d1c176b17f1aed70245328753cb59a82c78f589b56864370438959898ecc4d49dfbf6b68ecfd3287adb0cf1e9d631850cbebf3e361a8cbcd6c98d8faf6d858a4e5b12b828fdbf9458c16eb928c93b82399c97b626f6af7620f7979d8c36eb2c5b887db32382567ea00f67fdf22ea2d9010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x671096d73a746aa35c5a510ec50d02f1d963e6f2f599e14f7d3c3acc3bb67d4db630a4e2540825e3977cb9cc8810cae081d326f5d683b8fb509776e69c70d10a	1579560304000000	1580165104000000	1642632304000000	1674168304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8bf4cbba06faabbcd9db091cf1f691146a8b8d7f19506f666748a97b081d996d90a0a1edb5d2a429cf2614b0942ab6bedc0966390f8fe5065cf8fce8890745af	\\x00800003d741408cbd4fb67e4387692cf5c075adecdd63825c0c3123202524092251fd2d35c5feaa8d13758581543508d41b88c4d75b03dfd06d35f62a722707e206982f2ed8a9fc6a103a6073177bb2aefb986ef468d328ab717afd8c6b3c04ff1fe69004d21cb846f739fb1171e633866d2fbd99615495fdef317a6f536b5cc426b185010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xcb10f0d7c79954b2b50c895b1341b876943078351b50d062d551ee8f5d4e8d60ceaba0740d50add0be0aaad4da6e662ff836fcf021acf386e15225ddffc78500	1578955804000000	1579560604000000	1642027804000000	1673563804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59808885fb4da07d196d1d11d3bcb5a5ee2cbec6ebcbdc33d8b0d8ff5374abbc765248625f501b93d174e0613644051ff76fc292ff020a6a82a6785fdb20c7c0	\\x00800003cea52b2e0a4e41f0e5d83607c3de4f445e431124abc4b53e1cefbd219cf58a1a5011129e16e96cc0057890d0a2f89295755fe48b524c638304a4b5ef41fc67eb370dbe69b97bfad3db18990f149f3922b3cd0ffefa08e317bfa35b20523452935bdac979645008780a52282b853431610a846279b3d7f7bdfebf59a675485d85010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xbc95ad5216b773f6b8f3681454ea91e71970ebf3ba6ca313bb0bb0aab54e3411ac74fb56426da235878962c602f97ce9fbed99f618d0451051f3182e4a4dac0a	1580164804000000	1580769604000000	1643236804000000	1674772804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x09e3b17bb9abaf7fd74633b31d9e4727af6890a590f9a613a9034e384f766cf5fd55220669d1810143626d05f9b488f0d8f27127855b5c526e6abf9261677876	\\x00800003dca35864f02321e04d1601286ac7f756dfd7dd4d611997e078a357cc4d0703f190ee36158fedde6ad34cb3460a46b98986bf7ee59c379982085dbfe1becf53a0dd0de1d13ad979b659a0e99a4435a6f0cdbad970d88267f3002063056f686a882976ceadca36edeff40a1761ac29b29594e94555b781e8a9fba18d6483a4cd93010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x862a485b198349682c9a0f00eaec80f749733a91d4a76a5fb94c7a3a887ec157ebe88ac1dc8a083e1ce9c692828627dac2bc7a92cbec0ebc566083a4a0bb5b0f	1578351304000000	1578956104000000	1641423304000000	1672959304000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x93a4d6fcdcc731fa97d39c1ef135c76fb597e8fcd5555b606064a53ed91f0bc89dd0dc30a97f0e93f21907747e9859076e59fb0c22a96154fe1cec7395b1730a	\\x00800003b48078dfddaa13af97ca38a5377472378bc67e616e988f70672de3db024cc546f8442d3003fd6468a05f237075c78603956a335b4d27f2b0e181ea25e474b3fb815c3d2717d6411cfe79e8f5da555576578aa17d6978e346baa2215a70c4c0031fe815c0126ab8ead4658e37fc6aa95c7b99b43303f267b4b0ab8a9bce56f65f010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x376b09b1a8b5f91d90cc81caf515b8fd85ca227bd01d4d949a1e967b9e5b97354f4c72830bd356374a2d713eb37755e05434e211ab62a8750708f171b4fd390a	1577746804000000	1578351604000000	1640818804000000	1672354804000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7af9a3eeba12087062f84dfbf59c72e1efe6f521f9465719d6729e47259812a26c332ada3088ffce55e40e441f52fa81bb539826a3eadfa2047c90f77e369170	\\x00800003e53a1ae055d71ced3727c69d6a6f84b2474484107f12fa614aecf1a1885b36ff32ca806f79a2baa6f8ea8c7c65f8b189082687d9d88f95ed8310a9f79bb98534db5cab8cc38491858291234c6dce79bcf6b65d7f8ac6903f305c24a4aecf9d33fe50ecad25379f6268e635d28bc9e0cb754b6e6011efac7b58f82a2c0204f701010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x3fd5f0f0291382c140d86e5c7ee0f86e7819cd8a66b3c587eff71d262b1dca8b63385999ace3fed30bb0abb03dd56854dbb262f3a169bf509036ea64b23fd209	1579560304000000	1580165104000000	1642632304000000	1674168304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1eca55e4b24aea387fe0a16ec9042b5c8295437cbaa10e9795d822c8ceed5fe3ce58dcdd2664193d6e92fc4636d69fcfe9a9109e4b6f84dbba70e5cb0bc2a41c	\\x0080000396332a37c4a5942818c8e8dff575796452aeb11afef200b1bcf315f05df7f73ab6fd58b5ef711c9ebc84ba8a6e1366e627ef958dbdf9d12c0fad5c8bd0967490bb226e05634a312309a8e6da34951ecb81d4180bd5fe3c204169679df15bd8cfc0417bdc2c18e189c923e76cc7d1aa755dfd702a8ee3fe88724ad4ccba7a868b010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xf15557ad09ab4410bb924e1fe7b2d17a9ec5a8c627c5f6c86790f370ae01abdd107992e16d4a40020a4f8cbbbaa2e72639a8538e4683456c3335c58049268c02	1578955804000000	1579560604000000	1642027804000000	1673563804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb08d104264f8477148e9eb4a356fabc9b76ad083c0057416d878656e3591a8be5732d173804d738766c27438680f9ddf773c2415578325c858648b5636a8643	\\x00800003c5ec47754504da319b6f6f9b2bf395777fd403f05f5359e14770892fa3769073bee6bc92588067dd1ad709d37ad856297ba2e6aece020bc5392390e13d2f710155723c65c60160585bb4d2baaee7ba6e40e4f878b1fc284c4c5f2d6597c65208e3e22a2e2c7a1c7183a7a2ff7346ff846f9cc9804fca85e74ec7df9d6fc5e7fd010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x1082c25f68c361e5c9001b83de8e7ed2874765349c3128dc72d7fb8fa8b86dfd5a541f1ed6c9909a063de80a73f9ab1afac198d8922bb102468f37d3f78d1700	1580164804000000	1580769604000000	1643236804000000	1674772804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x96b2d8cb6cde09a83b5c8d013966429f8b240b34084544eda4458a0549aa6655fe8f582d9d549421089dc5e1b01d35bb7ddd6c80a4140a416b05bd041f2e6c29	\\x00800003c3ff036e59ac6e8556c9df1977bced11ac3c6a576a579cc4f0879b6729b45ad2f059c22af7c65d61e9a85117a0d157305c4a34b799123226ccdf8182cc70c07893d2c5af9e0d3f21458f3e2f2c6cbf1e7e010cfb088015ac64fd203ba0e9170b0dff52aeecea6ead8c6f235109664654fa4f2b0ff6e0405640c30970760cb49b010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x313dde11fc46f3b216f66efad861f29ca8c878ee9ef8134e4927f6e9c91df0433f3eb1330b6dcd2ae6b48af693915b8fcf2d43a198905da1042dfcaa5b9e3008	1578351304000000	1578956104000000	1641423304000000	1672959304000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x762d33943a67beffa523d57266fa2a18ddd1d4fb4b4868813ab4f6c93985feebfe232964f23db1b18f6e1f7b39be4e7b58b951833cf6554d47ba33c83d89010f	\\x00800003ccb16f8b6f993d0adbdcc1a0d7ac1029ee8a8b8ad57007cfd3eb1417e786db8a6cf2c2e3ad765bf00eaa7b6cce19ae1d4d6cfab2443f3e5c7a5a266329a14e7dde1d1652c7507e6ac1ce0ec17831436d7fbe9ed3d779c43fc3f8f12f700f8791e48c8c0f0c91cd353a8c5aced0279093628133cbca11a46884103006f8370e63010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xdfb210134d9d79523b44637a3c0244768e039643fe0bcb27208989c716c91d1d82e153261fb87c94853e42627c082648fe48358887584762b6f17c7ff2b1760b	1577746804000000	1578351604000000	1640818804000000	1672354804000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x83ff978af9626ee303e7ac926065a76b276f993d1d5004373579dd6e2a1be5b8648b279438b0fa1cc00832e0735ec88b16f70cda3abb3eb27a32badcacff2ebc	\\x00800003cca9200ee527f704d6d08dbdce1746f79b62ec17dd1681c081355bbcaa434fadc4f129cecda835b9144255ae842e29ba76667dc9a75db1fa39e60b3d250a0cf9ef24c0fa24d95de996c94f6d2db88b4981ee2cf3218a8b4dce7396d14ac97e21a1f925aaeb58d5c701b59f3182a07863362584809bc5caa1a8368be171bc9dbb010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xc876656923e9ae107bcd56637aa4ce7bc5a28a52755b404efde16e268ca2ad0d0c9cba21ec8b3bf4bf4d4ac4ab7aca6ecf6bc81941413d9fbdb16c7c6fb82606	1579560304000000	1580165104000000	1642632304000000	1674168304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x719c7c0c96f130a28aaf72f9f370d33270f33c66949e3ddd2ef7d01d6a95928e02cf60224c9acaf6b3dc0dc5c7f75f7c761f3ef2d7b67c1902a826d10d88b310	\\x00800003d52c76ae77e1552b484b1435f6aff83b4de97c711ce217c391dbf2d66cdb1585dc9a91ac316a040120f575088f3cb673da57a705929254f9337aafbcafb2c577d1f45bdc731f14ca7a33a91476b6065ee58e6efa6eccc6baee5ee46b59b0155c6476e7063269af9d1566259cfd0856fd6fdaefe08996b8b93d153d741f7184e7010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xa3c49bf71feb7f0d6462cd1157a6ddf9251f053752bac92fce7f551002fb1aaf92bbe096861a5136675203802053e9f64209c4163cfb8b20da754014bc22250c	1578955804000000	1579560604000000	1642027804000000	1673563804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x917f2e275e0fd5f4b9659eb6cab8c416aba67a1317bcb7b7bb4cfeded9ba47630f368a02c8aa839303d9d72533b7f8be6a1639b6ca26796e7307cad8c1ea9c8f	\\x00800003d738e8cb7e8dfc382c70d62741f2afd958da6dd8228063c79ce57a803a9bd68400ceeb3b97510bb1438233b2bf9c3abfd6c6968c7bf5fb007c60de0a18cd0d3e4d1e5bb7be9ff16f7d34570be7dba8166410bbb66fdab2e6510dfb96205e36c34d39e0a22e4aada9dcf7fb94a76aa25e8925b85b0955ad21d3abf02623a39bdf010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xd6e5f2d0770a82474659e2e5e4958dd1fc5bdc9e10b833827f09a0cf92268426e46ba86587369f67e49324089bbfa4957c91f36f6fb46e4ef33fd09942504c02	1580164804000000	1580769604000000	1643236804000000	1674772804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x37fa793afc45755fde48fd1b1387254202326451d1a96aa806bcb7ebaf14d4c8e8156ad7a7069ab00d3f88c681939dfc17bfe513f7477c30885e9ae40b33a650	\\x00800003d7966a30e76cbebdcb7d3035ae093c1ebf7a78276692e111928453db89d8d51e1066155e180bf8d12cf45df736d149cdc38d6af1eec32b6632abc4f8ef9b1a7ecbe82f7dd2119059f23f88ab73c58ff6fb0db08546483b28b5af0c7d082275613822cc7eb96f7146ee4f2c606c53c9f7c1e3cab432713f3a1e6ca9071a05fb67010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x04ac2c351ef7bd1866c60dfcfc6ef35ff22dffd0aba9dd7fcf1a5628c00f538ae674d13d310cb88597c608e5e49a8ac05bc1522e322dd10589d9072a29a5970e	1578351304000000	1578956104000000	1641423304000000	1672959304000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x661b14c509048ec3694fe0329446689320b932778770f7f0027b67b69ca354c225c258fa82f624b782df0d8f72768e42633dd43dcd9664d124e864e5563d4e36	\\x00800003a5e26f870d8cc21264c68ec0a9d7427183e890bf91dbcef181e5a99b19716cb9b7fe8c17574f95d410ca27efc7253d6bc0e6dc78ab1eb49e902a72299c7be47ccf67e6e578b10f61485a39382b2fefa31c7bcbe926bc3e4e1b10eabd6aad6803a4b8f2c6cd5dd36c24cc3e77e4b3f48fb74508b26527fe390967796476cb6013010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xb92506f39eedc7885fb5a3c828315521857fc83662ffeb85884f061b1260aabe4a59fc479da3f27c202ade1e09badbe7027ffe9803945aceb10346dfd189b509	1577746804000000	1578351604000000	1640818804000000	1672354804000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd11c711a3c727b0a94c23f3b7827f555140e5d0a91790a088a25c6a62e1fc103e4922f20acdfb70eb5ca8cfdb9b5014e461ce30b01af30677344dff99228df16	\\x00800003efab138baa3cb0af4f69932e0419eb8f1a449a09d298629d8631d5fef03a47499c7580cbb1b633763972a73deddf6a8689e76fd4a6ae852a40ffce59bbeb51f5c7a7df4ef7cfb8fe7e79c23c12f2b8ae4db23871fcb03115c664a2fa8c83c9f70b78592d6b8ce859680663082811d983f298b94cc20be14346089c3293528625010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x8a3b287be1a1fe11a127919744976c6f9f099d744a360fae30e85671f87a56cb6b4f1f019772b6e27e923c6e81f79d4727f11553fb89346f76faa39d6bcb9402	1579560304000000	1580165104000000	1642632304000000	1674168304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x21d79b215412b1f218b163180f9a95427fcb7bff4b1260ff605949f97574b2f578e68e30e5a0fd8e2845ddedaa6f890002ce27b2d28b76663aab0eadc5cf7b89	\\x00800003b92ef5c123491d143dc471793a1688f39208a98949101b02a9cfcded98e130d8e748080bc1fa863136c138b0b0d8da7bb3db78353b1fea90305a01e303d75dd7052ef71bcdbcbcf6ab8912949f7c97414d227eaf5df89d75d001b4e5a96a41c24d732c6f9cb5d090bf94570d78a41460b125a0c690c11cde4017e41689918f53010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x58b4289cc3d8c86e9e33087d772c9581c6059a30d84bfffd4560bb647554a7fabecbc16126ee4c126edf8b3c663d95292dbc128c1c097f27d14f46eb81cf7705	1578955804000000	1579560604000000	1642027804000000	1673563804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xafdcc403075a74946b1b6d0dd3b61411b81f45fecc36438e8bc574cf2df6b84e5d0388e37502f117118b03974c7a41af60b84617f4f0cdf7c241aaaf3708b334	\\x0080000397780ba1211d3d35b08fb7db4c9d39ed588f137c4c5e3e0c9ef567b3617b8ea959b63ec16d509b92c3cd1fe32b045e8f905625164d14aa4866398df591a50b8906d33231c4b698b6fe1909e192b41c1a2e55f77b567b81811c7ac2795081baca6abab7f73ce12db583ec78263befc06a84439c802d2ffbd93f1d388a70eef18f010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xdb149c2795c0cf8475c60225d844834914ca3b9124ec7e60d2e1b81c16cb6e982869d285d44ce22ac2a2d89199fb41ffc7c9d8f61606e92f4671cf52f6e9be0c	1580164804000000	1580769604000000	1643236804000000	1674772804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd636269488545690e6ec28fdb08716337d32e1f750d7950b5bd52173d2900db2e4ed4122c52b51fb6e0a94baf0b56118fe66c66517c06e775bf22837e69a9523	\\x008000039c4f63585946c4494cf3df3ebafa4965bacb576568bc9e174d540fd19c1a786b7bf0cbb98a305b0b28b6709d51e92ca899c2ba60c65caf9e1a37dbd40919e6bd7de23403b447c6256b42555f9fc1634570c60453815373ba70d6e870f9ab10ba22cd097effdb85fb750ab1d97b0b0cd21cfb97308714c1803f3d168ae3c5b5cf010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xa6534fef96da1f08fc299572bf7b94fa7bc05aaa7869aa1e52a5a8bb06e84441d9202c63be63bca9c21f5b0a8bfdea1ec38578e0227b92782752cc46caee7b05	1578351304000000	1578956104000000	1641423304000000	1672959304000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4c484596323aaa5e72d70eb101878f5184dac6f5b24d4ecac9d3edfc64497a6066e4dcf89895fef6b4959f833de8189cd9f8d7353cf097b7845feff61d36f7e3	\\x00800003c2fa662adf98153b0b8be4482cd4458bf6ffec2d8964dba02dbf65b65b2b80af4943f08017a5fc4be68941ebb6d6090770f6c06cf7f1762c0d0d96010b0d2415a5b5183bd006e15de81553a99606967d1490a9db3c3c884e50e0b6a92c4880444f4681e7c31cbb82d8e23632fa8547469e1f224d2234119409b3a067272d5369010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xc45cd06190c9d25f3f27ea12268f8456717eb29f1b2c3aca3882a825c6f336c85594ab2c752bad63222ff41bb29b8d697df69513d55e5642f44f8d2f9144850f	1577746804000000	1578351604000000	1640818804000000	1672354804000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfff765b5ee08890ba864d1bfa067fb78bf073f096b8c0205ee955edc1d4207b5da00240fa46b2c61bc4538ad8e10381cd9e79aaaf4cdcf304b5c3e84505e01b8	\\x00800003b66808d0479189b609983d7c841099444d162941cd4d39111cff052716a0c1993264a283db0a6537dd3b6d451d5907e875944e0029aede23559cb286460a38303a6c35278f614452e459080f28a119e9ab3310d8724857de5f90990265f49fecfd96a713b7659c8f7c35358fe451898a99a88a780c5d968e21a6cc984fbdb6d5010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xb3448e4595f81b1dfe0947f0e1188fc3a90a97203a6c092ed51903bf0fe08694080c9c5498563b14cedbadb4db643cfb9e1ddb06dac7790a3d15a942de4cf50d	1579560304000000	1580165104000000	1642632304000000	1674168304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c7b69407b2b006dba3868d8d4aa30625068d7a57e919b082eed374111af6e0b88835ae23a54e4918d51b85bb58f20b3bd81e912c960f57754501a401fb76dc3	\\x00800003b3a2291c6a90af6fc418a5ec1a54015f1475feed9632bb50dbb665d7ef8d5560896ca79eb9e37d75759d21bd8b1ae981a2d99b442d527528485f77e1f683b19ef83791ce7bff8b9f8f56c2e65ec72f8f2a9c9b0c01ebf8dea08b0ebc4be0006bd9d90ee14a62a1d15473f5cc27027869e75a5b2df9c7930e2d42e647f36b5517010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x4029c473622ed8d437ca5abb72da518149e5538c3bc844201026eac5f97bfefe87d8f30ca8cef0d0be43fad85fd1e4d59e78719a50317adffe32270097dd3f0b	1578955804000000	1579560604000000	1642027804000000	1673563804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc682447fbe933380b31bff8138968a63efed96f89d1e77b9078561e84cabcf6a8cb8fe0c334912bcb68b45120db7e8c4bd93a1a26d7894872d87838ed7046190	\\x00800003c7b259a7fa270347c0b1a088b7a426d8fed7783100db51ba88308b5d16cf53c6fefabc4b7f47470ba79fdc55f37e082cb9840870b5d9a74c1299b11f087729ed13f4fed383ad9b7cca943727ea2eb9e6c9650cce8b68f0d070d7d993598afe4cbd61a57ffe66c379fee1b00d0dc3f77b88950b688fe028b2a0a66ce80a496ae7010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x6617c5f704d0ecaa5464d81d9453db9428be9f7be12898f2e20a571de4f0aca4ffb414ed8850d0b48300d281d546e047299d9d3ab2fd048096bb536b0ddf5a0c	1580164804000000	1580769604000000	1643236804000000	1674772804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7d7f9de3358433f3d19f7ca37c5c616273b492483538dcbc69447f80d009e9beaa058d2cfddace77f5ddc2f9052734bfb2d4fae477b95730e67d3c8cce8f7a39	\\x00800003cf8be15d29f784dd1aca830b70d74740e755ac493a3ba8c347b67f7b71f857934dbc8caddbe22d413ce694cb4fe6883c97bda6f8ae37d4f84669f8643161f418db4a6514b264e97da5fe35c6f2d12e20cabc1f5cb510cda49d70bd297bf03afffb1ca68e14f808a1bfcaae91e1a7981b515184f87a7dce15fb30ad6fa9ce0b43010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x15be361df14c71e17b874fa1d329546687848a2dbc8b9cefd37198457b04e38d61cd9624e8d2bd3c3edcefc925d9c1338667909f36c5f73cef980d9c58108107	1578351304000000	1578956104000000	1641423304000000	1672959304000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4d51f77f9139f8c80fa05f98a6b7b343c5d7dcc682eacbd6cb54064f68e8fc20b029b5fe4144e22df1132ba4d35c39e07f4402b6bdd0a8549bd724550bfb4b7b	\\x00800003bc6942df5acddaa9337317125e6f730ba00d9e555178823bcbfe08bcce27de207a22e8921c544815b6dffad2dedada278c8df715f379acda68ff9a8d73fa5018dabb1f3a8ff3115ff641c6e65e36b93a4641f8ba2bfae1e7ae4f613cd4b10300ad20a8b3cd94b806639f0d9ae041f96d836a8bdf5f395456ab128db919609f4f010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x5225accd194b54e56c002ea98dd9292c910b1231ead2cc9794fd2026b9f8114546c2165858a7826dc0a49ab6b2f1fa2ac5d38d5ce658998c8f3449c864fc7502	1577746804000000	1578351604000000	1640818804000000	1672354804000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdd9ece836f25baf921204a121362af4671a21f5b48c7f80b186a8a4ee9d845386c88a7b16eb9cde9efd2e84c5725feffdd52c6de91a1e7d33a268925deba839c	\\x00800003c2e99c11da7f7d34ab8cade955a9037d2af0f9f022bc00c6187a7d0f1b09dba4945ddd2af0044cbc1ed517a8f03297ddb65790fd1dc411f38ac696e110ca347aeafba9de3e5150c9df59e697efc6f6b9d97b28d7f9d511e25723a4084ff643ad75cbdecf5c7cb101828c920527e690a7432f450b70743af83ac873f5d1b44287010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x40d002b3c5bbf329b02ab7e116fb8230e30803c08e43e323b743302ac362db7d735e4263faa7873da987b58416092d5060cd14a12c0403511172674f8930b60f	1579560304000000	1580165104000000	1642632304000000	1674168304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa7f6487984af2db227f6172b44a39b7322383ad01c9011ca30c5f3bff4ec6806b6269f3ebe5b3907516a9a3028a315994c910c270cd953760916903591e2be7e	\\x00800003bc01c40059ad5354538ec51cb367380dcfd320a677a760515a2238bd8ec8a9dcea1526da63b7a885d5990970dc48b9f72267cd01984bb3a625906b6c8d6f7665ec60bce3cabc8c6ad188529277d51c971f545d32e0fe1a59529314026479a8012e17111225c44251b9f4266a1b67585fb8665f8ed087aa334ba1e79f686a11a3010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x7f21aa1ce40605b5dd94e0c0fbf33d33d195e0ec3f9021bdf0523d91fc0e8820c2639d5fde5f4e954c42012c25ad95a0a5e38faa8573a1c9dc3e1381b5cdb90b	1578955804000000	1579560604000000	1642027804000000	1673563804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xeedfa49fc8faa7a7cfdeff19134ff28f3afa8aa8cf0526ce05a31e35b88e92f044aa2545b380fed48fe0e3450a42454db359bea8d59718e5aee9b2cea7407fe2	\\x00800003c9eb83b0efa37d4fc7bf517a38858d19ea5f29d0ed82188f6dc2e42d006e225bec8d0b10e1d0f0ac0a019737d20e2a89dcd291686f1a2fe1be91d66f7f05930f2f7072475ab97d55ccca2667b829940b80a4fdf66007027739d8922c8fa41ea41c2066a75b74076aa7cd14c5a6cd2292a3b39a9b72a9d7eb5fc52b75749bbfbf010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x73708fd648d00c0b41bb07b7bac811a1342fe08ac963def4242b1247b505f95e633332ab8087ff0cea7fb201d1b013099ce47da3c0bd3c62e224c7e0af8e8304	1580164804000000	1580769604000000	1643236804000000	1674772804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2e08b05c9291b09c3cd85607ee7a3876aa81fc8148cd1bf2f0a2a3be714802b33d90f1916ebbc9bc386a077758e87c27acd8afc1e4cdbc80fd7194a371637559	\\x00800003bbbed2e7aec48928f03c0cf61ba9ac5cd6175a3a653579362dae2d85c06938adb85b6c0d099e6f4d7c57422d7a77025716476ed41a1f70be0e227974d7030e60af89014d027066bd37325a08c69572cf6dd4af846ce9b6c0a5b2281afa028a8951626223ca26259a486ebe94a1a1f74738ef34ce44da294927f8399b63e37189010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xce7b5ec599bb318a3849e1543cf4cac71c8c8acbea0005d25ad222fcd82edb7919fca705e5a974587171f58bab1e8cc93e4c9411d595eb6788e9cdf10972090a	1578351304000000	1578956104000000	1641423304000000	1672959304000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x00800003ac30a36edf34d8b7906c101b9ef89ff0c05f688e6e2c3f23e3aaff26f03ad8c9c23a470009adaaf42bf2a844a6c8f2ed39d9a61d5db0aa1fd23a71660010de827400aceeca08343985af8650e1df8c3f418a6f543989370efbcc3d8c677f916ac12070b3670f9805e6517512a5807a13d1c28bfeb8115e25d464f3e04673264d010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xd5294b741b04a602de6799a18c9fef4825b512682618b4ad9fd8f68027cd8fbdb6e7845f3015a68388d04cc2a4c4c33bb12fd61fc680fd213a403da083a1a905	1577746804000000	1578351604000000	1640818804000000	1672354804000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcd5dab022958a5f06f7a63c2745ef8433546d5af7b6703625dac4e511b9adac43f81366831d9c520d24ee907ff0c74f47386f0ddec4c3560a4cc74b46849b6e0	\\x00800003c0510b4a48d3e802097d41ef0849101c4d38a7aa4e330ca528ad31cdf96b9576142917af601042851a7aa58910478f2b4586b63d84b37812d981170f85e53eac7c57fde07049d41effd1c8f1795f24e6312d049def79bfabae2f45ba55a184ca99b4da4d68f69391ce09a5d57dffaca081d89c9a4ce0d5f7e05789fc46bcb6bf010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x6448ff29094f4cc68c486adc4633f210c25d56c48b84a7fe18f6ab8e52a9c1fd59af389049824672694287158a9e2f7d2a566af5c81624ac69b213fb74d7ab0c	1579560304000000	1580165104000000	1642632304000000	1674168304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8af977cb3c7aa28bb92f71142d3873e7590d42610ad82db8834e88c42efa7302acc6348bc554e23308bf5f43affdefef542ac85a62e2341d70cfaa6b25c0d702	\\x00800003b34b6239457508bf8158df6eac1f608a109f5d7b74e2d7061baeeee9b560418a7319ac3290b579d3da186337a7ed72156e996dc9ac87709e72ab4f5567d6e41b0fb78c622bd7ba0094b0696971b0e4e7e243947c65dc15771aaf39a77362d2183840efa6d253a88639c2d0b5ba0cae842ba1f8b66a42ffb0d79e93b0239716ab010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xfdfba7b2f6f8c9258cefd136cff06d55fad48e1a76b78c0ed1dc199980c6bdde2f882dd693b2d5736bbe519e227ac1152ab4096ddec83fad79221020d5ede105	1578955804000000	1579560604000000	1642027804000000	1673563804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7dbd56e2bdd85a6f5e83dbede979e26c6bc483aaa0ca8265b75e32353b193cfba0d050a5028b6d1a25d57e0738924c04136a141124021b1b6b3f282a16135799	\\x00800003bd81f83c2181546d9993297d38b44bd5a6f6998049b093258ac3371d17f417b367d4e4a6e27a5a3d6680d4b5ea7ff1d4a6025d99b99967f5c9fba1152d37d00c48193d20cc2b9077163529d225ab5294739f1b98c4d928618744b162037d371c410b40554a752f0b89144aae7da1dffd976e82cab63ca0aa69615fd71309b1b5010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x289d70f59fbe103e8fdc23cbbb6ae48b028195f51fa71ce5a6d4ea32d87722533f7b057c5026f7a19a350a9965485ef4f0615abee3cb6154b51a4407c14db700	1580164804000000	1580769604000000	1643236804000000	1674772804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x476d3aad7ada10117bbbbed43e25deec97ae7271cde0a3cca4d797d22ed433c13425bc18b70bb8e99ab3a49697ceab19c16af9a90cee61a685afdf3cccd5dfd6	\\x00800003b2227e593df24837e13dd412d3dc8b9b2f6349ffc821d41ffd7fb1961f6e7e1a1c9b08e271ee662d43c5d808fa4658b7385aad4f9eb0de0abe53b610c9d399c0b45ad19c6c652a0ed49df83759c807f548a422732bdf025acf2d64cea94e298c399a7570ebe2a941a2f04689244dc635187e981c1261b47090a12cd9cca81b55010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x62c4b5a90cf0c2db8fe318d3aeb577da2a98992052ad27d7718ee1e08d44d0e5b3d8a125b97684b05dfdf3e9447a3c933bc62e4f0c2d2d032f9c97ef2c3ec201	1578351304000000	1578956104000000	1641423304000000	1672959304000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x00800003d36782161244562da384b5a398acadf69ab5c791853f84d28c9320a9b35bf51e1d82bcaec2766c7990b663768bc45291fef4f77fde555532ab5a746759d616545d6f7432519557782432d1e745a50c0c7f1b8418284595604cc51ad31a703d3080d4f39066560775547e6717ce5f2b3321501d34ad4a33e8b11ca509b69d080f010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x0bed321a823c6bb174c9a119ee8b73b400ff71f0177f0dac2a3aad612b1a765a0e6fd8a0bde02f5a03b47c194183b14ac399d8651545e8e0e0115c59f494990c	1577746804000000	1578351604000000	1640818804000000	1672354804000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x10102c26d3310d9c824c07af2196decb33a565f533b3184d4a22fc9901cac5307231572727cdae2c47e9e1743db057a13ebfe59af9d212526dc265ece435f56a	\\x00800003f6b81a7014409e3b8706923f4f9a37e79049dc959037d912724dccea19628073b8f00f06970d25466effe15af85de0b83e41c0380e2fbdbe2dccb87b031b025cd849141836e3f2daebf4f12e0d5e76fc33e2e95c41bfdd16758f6251a983eb2ff4990360e69bd0ada39ac6ffe0fd6b8787789452ac82c2436fd1d63081ff2deb010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x3c32660c148a1f45dcc1aff03e53c4010538bac9ece9d84385a98f4b3cd3c01757b261b27dd25d7505313cfd1076e499080e4f047416b952cd10073fb8c7f809	1579560304000000	1580165104000000	1642632304000000	1674168304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8bf4cda06fbdffc61c9d1ac24229e3e446d66ca5c24df21d7d3cf164ef719b2b1611f23adf8062ee459492d40ac5e40392b825b4e1d45d3cc0e5649fa14de3fe	\\x00800003a5d0c6eac1c47d8eecef28f1faa1f4402b0f9eee1b6908862e827507d4dcbf5d1b06f1e5f4aa0ae136a7c8ab62e7d64c8d617be60eec5ecffaf9fc73713b08aed248b57e9b2cd0bc81d8a3edce68a688e81a6c8b993007e976af969befdfe5b01f9a40f1b620dfb9df19c7238cb62fe242601ee4c94f147b17a32aef442a3327010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xa18efe349b89c00d501ed2acebf9c3b1a77f2afc810f6557dd6d75d786dc0a3995f2892d1e899c639a32f80bd7ec2b6f6445dba5cf8ea84558678f0ebd734803	1578955804000000	1579560604000000	1642027804000000	1673563804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xed68b4f94f5362c58f1913523da3ae39d9cbb4f98788ee599f4180e84981e7d53e2665cb520b5f08e916f7be1a2644f41cabd1823762460284ad21938d882819	\\x00800003b15475352cd99bc81f82aedb2c8acf51f69adf856d00e96e3f1965f8f1993c0949bba9e47815de84933bc8c007ba880bfcfda75d9de1427351d4cf1379c57acad47db7f6e99ed781876e9e2e06f41e429d670b3aff8978fc3fe5bd8a81f6a8337fefbc08a80e03c7e73d113552970fcc44ee49b2c387532e8cba3b8fd02dae35010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x505c2946d86f41001becd1fdc6066269374f1aad045782958174472c4c65baf8cc1c2d7345d0149fea93e1887f90192f3dcc2fb58a981e7e4ff6e646919c5d07	1580164804000000	1580769604000000	1643236804000000	1674772804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb030ac747490399e8c98b5a97cb28b143752b492d8921d846936c58c6896d42e7b693722977af5c374ee5f43774b391acb91782ed3a79d76466c9ad3e986d604	\\x00800003cd4328b5072e9a8ad271763e1c81f13d22a01e0154eac8373f1b40489297f7d042c5e909a363c70b154ea4085bfe974e89cea4104f567d54d6c9edb842f8664c031f3c5b5f2e14bca8e80a6e13b2b9d42a28d724c5dc4d0bc064e6d02f38317d0d4868a71d9273c815d9778a35001a072c10dcc037d5db43b18180cc9d13746d010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x3d675041dfc7c8951c3b443165b7abb96f969b3fb066c0b73e7d21b10496b11338f22954937bb43a8a0bb93fa04aeaaf0bf4ca3e48e4f9f5a46695467b2ced02	1578351304000000	1578956104000000	1641423304000000	1672959304000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2107cccfb64078d70a5f05193acca64c78ca4feb0d960d7a946381b054cf9188e64012490b5bbcb4ced6efe12051ec283384a508e0d7a77c1c3e6b8b1e60e438	\\x00800003b5e7ee66b8644f9bd24d829936dffad3ea0bb828ae8467ca1074d39369d43a39bad9cbff802c12288ccddf97e2f491ec70467a8c30bfeb1f4a8f63d7bf5fada45b860059a6a7f478d087bff2db65935adc194eb0423789c98a3c22e94c27d8d632fc84be8ada9d60f0c278bbfcfef4873110f8ec71d2d15a05838544fdda6d23010001	\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\x2ce834efb8abe1c0a1c7dfe7a8d14630d12ead1b6e014ea7173120ad18f33a22df7aab2f6aa6b7e33a414f574c7947ca443a44c7fbeb0ee6256b9e157fe4190a	1577746804000000	1578351604000000	1640818804000000	1672354804000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	1	\\x6cd8d917771b6028c46c85b18eaf64cebee4b2de7364ea48dd6b554350e2721225b4b9d319bd833b4a0779ed3dabbb163760c28f8cb82a2d381391c90ef19125	\\x38985498fc0101b65f3f9e30ec477dce548ce5442e8b0499a5dbed1f3ad5a0d21d3a588707f7835564c616e2894a5b81089fbcf0d040503db6a0fd8946e585c7	1577746819000000	1577747719000000	3	98000000	\\xe65a821efe50a8793b5926260f36f9316ab6b770c6e11b4210b31aafaa8d191f	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x803c2b6fea36a31aa1398204c2a9593fa89b895932c84694e1be76e6383cd633ce6e58ebaaeb7c6b1732731760e88de54c03c25caf65bd97bca73808d142d102	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x16c5fcc83b7f000000000000000000002ef6eec801000000e0b57fb63b7f0000ebceb09e5d550000c90d006c3b7f00004a0d006c3b7f0000300d006c3b7f0000
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	2	\\x3a22c143424dbe30d8bb44e641decf80f8de7bb14fe32eeebcaa8738b8be22b56811c0a20b4190cc5edd072880f24f56e496200ce023b3e40613f8c9b9219114	\\x38985498fc0101b65f3f9e30ec477dce548ce5442e8b0499a5dbed1f3ad5a0d21d3a588707f7835564c616e2894a5b81089fbcf0d040503db6a0fd8946e585c7	1577746821000000	1577747721000000	6	99000000	\\xfd05002881b1d7d130be6ef572de8afb930e2f599ffeb4881ee781ce40608530	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x806ae50b7e774f9fb6406fd24f8d5a847d6f95da8a185f7398f4b601629d186628ac525d4fe89d6fd022447744cf92220a8d7c79ef6c86679a5545a775b45601	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x16c5fcc83b7f000000000000000000002ef6eec801000000e095c8c43b7f0000ebceb09e5d550000998f00943b7f00001a8f00943b7f0000008f00943b7f0000
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	3	\\xfb43f81ff75637f7ea71b851ea8abeb6dd4ea3f5dc3db32e988b25802fec30e8423f593e855d533dddb7d2abd2de8612ad49cf1cad782b3228ff8f451d9f0a41	\\x38985498fc0101b65f3f9e30ec477dce548ce5442e8b0499a5dbed1f3ad5a0d21d3a588707f7835564c616e2894a5b81089fbcf0d040503db6a0fd8946e585c7	1577746822000000	1577747722000000	2	98000000	\\x8c7c8913297d6dd39a9aff504f9e4f05752b2e12328801b31f9a389e9e722f74	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x5c84368365f522484db4817c77111bf9cf97ce6a875e5f84ac98dbc95aada6bc0c21a25cb0d32e0a18e89f970c9628c0d1005d9079d6ac1a15309ab87a82f405	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x16c5fcc83b7f000000000000000000002ef6eec801000000e0b57fb63b7f0000ebceb09e5d5500009965016c3b7f00001a65016c3b7f00000065016c3b7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\xe65a821efe50a8793b5926260f36f9316ab6b770c6e11b4210b31aafaa8d191f	4	0	1577746819000000	1577747719000000	1577747719000000	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x6cd8d917771b6028c46c85b18eaf64cebee4b2de7364ea48dd6b554350e2721225b4b9d319bd833b4a0779ed3dabbb163760c28f8cb82a2d381391c90ef19125	\\x38985498fc0101b65f3f9e30ec477dce548ce5442e8b0499a5dbed1f3ad5a0d21d3a588707f7835564c616e2894a5b81089fbcf0d040503db6a0fd8946e585c7	\\x6287323988142e3dd7e378be6d23e697e6246bcabb07e570919ac98a5393f97060c940b594eaffc94d6b0e3de92c987ed7ff02eb05bd9eb9932cf0f9be9c3c00	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"17XRK3BCWTXR3FYJJ6NBGWX7M2KEBQM0QK1AGNE37SW0RCQ6PFQ023JQQ76ZTN2SKCBTPM44F92JXN6K2XN8XMZ1AZ9HJBD7BM28VQR"}	f	f
2	\\xfd05002881b1d7d130be6ef572de8afb930e2f599ffeb4881ee781ce40608530	7	0	1577746821000000	1577747721000000	1577747721000000	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x3a22c143424dbe30d8bb44e641decf80f8de7bb14fe32eeebcaa8738b8be22b56811c0a20b4190cc5edd072880f24f56e496200ce023b3e40613f8c9b9219114	\\x38985498fc0101b65f3f9e30ec477dce548ce5442e8b0499a5dbed1f3ad5a0d21d3a588707f7835564c616e2894a5b81089fbcf0d040503db6a0fd8946e585c7	\\xe35d95563684b3dff2ae7a3c952a4d9619cd971e1c1fbbc53d5c0b0de3a7d397ffe0dcac85991d38e721c6e9fc2083ea76b5be5b00d5cb35df981e902c065005	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"17XRK3BCWTXR3FYJJ6NBGWX7M2KEBQM0QK1AGNE37SW0RCQ6PFQ023JQQ76ZTN2SKCBTPM44F92JXN6K2XN8XMZ1AZ9HJBD7BM28VQR"}	f	f
3	\\x8c7c8913297d6dd39a9aff504f9e4f05752b2e12328801b31f9a389e9e722f74	3	0	1577746822000000	1577747722000000	1577747722000000	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\xfb43f81ff75637f7ea71b851ea8abeb6dd4ea3f5dc3db32e988b25802fec30e8423f593e855d533dddb7d2abd2de8612ad49cf1cad782b3228ff8f451d9f0a41	\\x38985498fc0101b65f3f9e30ec477dce548ce5442e8b0499a5dbed1f3ad5a0d21d3a588707f7835564c616e2894a5b81089fbcf0d040503db6a0fd8946e585c7	\\x9d835309b1b4bb85782c9e672c62abf713ad2396c741f11ab3899120b97624cebf72751c2f2a5923dc53ee3689f373c1890df10f1f9f0d79bb33410e11cafb01	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"17XRK3BCWTXR3FYJJ6NBGWX7M2KEBQM0QK1AGNE37SW0RCQ6PFQ023JQQ76ZTN2SKCBTPM44F92JXN6K2XN8XMZ1AZ9HJBD7BM28VQR"}	f	f
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
1	contenttypes	0001_initial	2019-12-31 00:00:14.95178+01
2	auth	0001_initial	2019-12-31 00:00:14.976104+01
3	app	0001_initial	2019-12-31 00:00:15.017616+01
4	contenttypes	0002_remove_content_type_name	2019-12-31 00:00:15.03842+01
5	auth	0002_alter_permission_name_max_length	2019-12-31 00:00:15.0415+01
6	auth	0003_alter_user_email_max_length	2019-12-31 00:00:15.047115+01
7	auth	0004_alter_user_username_opts	2019-12-31 00:00:15.05291+01
8	auth	0005_alter_user_last_login_null	2019-12-31 00:00:15.058276+01
9	auth	0006_require_contenttypes_0002	2019-12-31 00:00:15.059436+01
10	auth	0007_alter_validators_add_error_messages	2019-12-31 00:00:15.064457+01
11	auth	0008_alter_user_username_max_length	2019-12-31 00:00:15.072573+01
12	auth	0009_alter_user_last_name_max_length	2019-12-31 00:00:15.081207+01
13	auth	0010_alter_group_name_max_length	2019-12-31 00:00:15.088423+01
14	auth	0011_update_proxy_permissions	2019-12-31 00:00:15.094436+01
15	sessions	0001_initial	2019-12-31 00:00:15.098776+01
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
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x17391897cf1a66aeffb71170cbdc293a12ca3d39a13286fac6ea162b4a1c662121a8e792038e8ded4678952be677bd98cd04c63b9e2b84b31704fc39e4ff2908
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xdaa462ee405cf6fe7bacff95fd7d4b4f0796f7ea1bfb6fefa316f4ddbf86c5213151889d17153305683d68ea5b85b084fe9c66c2b3dbcccda4dd94dcc7199a01
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x209ea001addf7f612e2cb98b83401d0a7f64a27692c7f47d46d3773d68d12b3ff9f398a49de8e70300244650159aa52531ba0eee384a9581b935b71fd081830e
\\xa05dbefa8a15e31d52ab612594416ba793c53e7ac672c2e26d2f15bc8d14ed13	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xb25c3d583e3785eeee6352e04816d6ebc66ed0873d86097cbc4d5dcb8453d88fa69424460ad1cbaa0e2a03591b9655814d3a027104d7e40025549dda5c1a070d
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\xe65a821efe50a8793b5926260f36f9316ab6b770c6e11b4210b31aafaa8d191f	\\x2107cccfb64078d70a5f05193acca64c78ca4feb0d960d7a946381b054cf9188e64012490b5bbcb4ced6efe12051ec283384a508e0d7a77c1c3e6b8b1e60e438	\\xb20c509a68bf69ab8a2d176ff7c2bb22e77b1d1fb4056bfb6b26f0757f57947b69c07056680107a50941e0cab697becf4f188a70eae00dc80ad958aebb9014b4e4089a4df7f343b5acc0be65f04f7246f2ad6b7e146c7a73f7c44efa4a5d38723492a47e85cd0142daddbd7ea55c514fc6aae3ff3df6eec17db8efeff577e133
\\xfd05002881b1d7d130be6ef572de8afb930e2f599ffeb4881ee781ce40608530	\\x762d33943a67beffa523d57266fa2a18ddd1d4fb4b4868813ab4f6c93985feebfe232964f23db1b18f6e1f7b39be4e7b58b951833cf6554d47ba33c83d89010f	\\x363e43dc0a46e7f7a2ccd67245d9316ccdba205c72b33ce4fed9b5f99f06deb706d9db016f82d12371da05c5d64e752ad0c7a38bf589705b26d6de73bc82fc00f8e0a4a643fd29aea218a4ce28f830b58add5bb6bc5ee92b24788f1235862960a228e68edbf4fd924ba69e2fb9b9e93508f629abcc31630c65f4ad87ab632976
\\x8c7c8913297d6dd39a9aff504f9e4f05752b2e12328801b31f9a389e9e722f74	\\x2107cccfb64078d70a5f05193acca64c78ca4feb0d960d7a946381b054cf9188e64012490b5bbcb4ced6efe12051ec283384a508e0d7a77c1c3e6b8b1e60e438	\\x06e14e2e9b777bf5cc64253ac96d2959f31c74ad0cacc74f0822065409abd8ed2db23b89077c4a711c3b9954e389aa3629a19620544e5ac20f7365fdf2f1e3d369488ce8eeb726dad54de6409b22d4e923dc03a6c00afffc55579a5baebf7cf6846e424de6d426c8b0a2c239af16759d3fa8618dc25f6a731af428a5e5535e37
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.365-03CF8H7GDDX24	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c226f726465725f6964223a22323031392e3336352d30334346384837474444583234222c2274696d657374616d70223a7b22745f6d73223a313537373734363831393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333231393030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d31455658594d4132514848544d4e4243344a53384742424d59395741464b545253534335524b44355741565333384d584d3947227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223732433539363757303430564351535a4b5252455248565853534138535341343554354739364435564650485945504e4d33393154454a524757335a4630544e434b333144524d39393944523232345a514b52443047324737505641315a433938564a52424852222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a225235534b514b45484733464b573847573730434a4446354b515039473750314339364d414b43323942593345374156584e365347222c226e6f6e6365223a2257474150543350364e5a46383053374b4535304641313931375246473854593838344653344132524e4757544d35534b4d363847227d	\\x6cd8d917771b6028c46c85b18eaf64cebee4b2de7364ea48dd6b554350e2721225b4b9d319bd833b4a0779ed3dabbb163760c28f8cb82a2d381391c90ef19125	1577746819000000	1	t
2019.365-00G0ZA54HW3N8	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c226f726465725f6964223a22323031392e3336352d303047305a4135344857334e38222c2274696d657374616d70223a7b22745f6d73223a313537373734363832313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232313030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d31455658594d4132514848544d4e4243344a53384742424d59395741464b545253534335524b44355741565333384d584d3947227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223732433539363757303430564351535a4b5252455248565853534138535341343554354739364435564650485945504e4d33393154454a524757335a4630544e434b333144524d39393944523232345a514b52443047324737505641315a433938564a52424852222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a225235534b514b45484733464b573847573730434a4446354b515039473750314339364d414b43323942593345374156584e365347222c226e6f6e6365223a225045334e4347304e3353324a56524b515748583232423051435a593434504e5250435235545132393258303651564a304e365330227d	\\x3a22c143424dbe30d8bb44e641decf80f8de7bb14fe32eeebcaa8738b8be22b56811c0a20b4190cc5edd072880f24f56e496200ce023b3e40613f8c9b9219114	1577746821000000	2	t
2019.365-01C4RNSX5PKAP	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732323030307d2c226f726465725f6964223a22323031392e3336352d30314334524e535835504b4150222c2274696d657374616d70223a7b22745f6d73223a313537373734363832323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d31455658594d4132514848544d4e4243344a53384742424d59395741464b545253534335524b44355741565333384d584d3947227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223732433539363757303430564351535a4b5252455248565853534138535341343554354739364435564650485945504e4d33393154454a524757335a4630544e434b333144524d39393944523232345a514b52443047324737505641315a433938564a52424852222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a225235534b514b45484733464b573847573730434a4446354b515039473750314339364d414b43323942593345374156584e365347222c226e6f6e6365223a2237514254444a345744514b363446423837354354463230444635414356475243393657584e44363941344a513034373942534d47227d	\\xfb43f81ff75637f7ea71b851ea8abeb6dd4ea3f5dc3db32e988b25802fec30e8423f593e855d533dddb7d2abd2de8612ad49cf1cad782b3228ff8f451d9f0a41	1577746822000000	3	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x6cd8d917771b6028c46c85b18eaf64cebee4b2de7364ea48dd6b554350e2721225b4b9d319bd833b4a0779ed3dabbb163760c28f8cb82a2d381391c90ef19125	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\xe65a821efe50a8793b5926260f36f9316ab6b770c6e11b4210b31aafaa8d191f	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224730593250565a41365448484e383953473832433541415337594d3951324153364234344435373151535645434531575452535757564a5258454e45505a3342325753373635563058323659414b303352394541595344584a5959414545303854353144323047222c22707562223a22485a4333354d565334363339563542454a435648365330414d4b3945475659514d4d3450473133354d54453250515a4b574a5147227d
\\x3a22c143424dbe30d8bb44e641decf80f8de7bb14fe32eeebcaa8738b8be22b56811c0a20b4190cc5edd072880f24f56e496200ce023b3e40613f8c9b9219114	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\xfd05002881b1d7d130be6ef572de8afb930e2f599ffeb4881ee781ce40608530	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2247314e4541325659455837535a444a30445a39345a334154474859505a3545544838433559575752594a563032524d5833314b324842324a424e37594837424654304834385854345359393234324d444648575959563436435944354148443745505435433038222c22707562223a22485a4333354d565334363339563542454a435648365330414d4b3945475659514d4d3450473133354d54453250515a4b574a5147227d
\\xfb43f81ff75637f7ea71b851ea8abeb6dd4ea3f5dc3db32e988b25802fec30e8423f593e855d533dddb7d2abd2de8612ad49cf1cad782b3228ff8f451d9f0a41	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x8c7c8913297d6dd39a9aff504f9e4f05752b2e12328801b31f9a389e9e722f74	http://localhost:8081/	3	0	0	2000000	0	4000000	0	1000000	\\x8fd832d37921869d956e933713640aa4d2e86fd7a509680465a69c2b5ff3e4af	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22424a323344305635594d4834474b444d47355937453438565a373753464b4b41475846355a3135434b3344574a504e444d54593052384432424a52443642474133334d395a3552434a524d43314d3830425038374b4e4e433338414b31364e5246413146383138222c22707562223a22485a4333354d565334363339563542454a435648365330414d4b3945475659514d4d3450473133354d54453250515a4b574a5147227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.365-03CF8H7GDDX24	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c226f726465725f6964223a22323031392e3336352d30334346384837474444583234222c2274696d657374616d70223a7b22745f6d73223a313537373734363831393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333231393030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d31455658594d4132514848544d4e4243344a53384742424d59395741464b545253534335524b44355741565333384d584d3947227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223732433539363757303430564351535a4b5252455248565853534138535341343554354739364435564650485945504e4d33393154454a524757335a4630544e434b333144524d39393944523232345a514b52443047324737505641315a433938564a52424852222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a225235534b514b45484733464b573847573730434a4446354b515039473750314339364d414b43323942593345374156584e365347227d	1577746819000000
2019.365-00G0ZA54HW3N8	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c226f726465725f6964223a22323031392e3336352d303047305a4135344857334e38222c2274696d657374616d70223a7b22745f6d73223a313537373734363832313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232313030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d31455658594d4132514848544d4e4243344a53384742424d59395741464b545253534335524b44355741565333384d584d3947227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223732433539363757303430564351535a4b5252455248565853534138535341343554354739364435564650485945504e4d33393154454a524757335a4630544e434b333144524d39393944523232345a514b52443047324737505641315a433938564a52424852222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a225235534b514b45484733464b573847573730434a4446354b515039473750314339364d414b43323942593345374156584e365347227d	1577746821000000
2019.365-01C4RNSX5PKAP	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732323030307d2c226f726465725f6964223a22323031392e3336352d30314334524e535835504b4150222c2274696d657374616d70223a7b22745f6d73223a313537373734363832323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d31455658594d4132514848544d4e4243344a53384742424d59395741464b545253534335524b44355741565333384d584d3947227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223732433539363757303430564351535a4b5252455248565853534138535341343554354739364435564650485945504e4d33393154454a524757335a4630544e434b333144524d39393944523232345a514b52443047324737505641315a433938564a52424852222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a225235534b514b45484733464b573847573730434a4446354b515039473750314339364d414b43323942593345374156584e365347227d	1577746822000000
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
1	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\x3a22c143424dbe30d8bb44e641decf80f8de7bb14fe32eeebcaa8738b8be22b56811c0a20b4190cc5edd072880f24f56e496200ce023b3e40613f8c9b9219114	\\xfd05002881b1d7d130be6ef572de8afb930e2f599ffeb4881ee781ce40608530	test refund	6	0	0	1000000
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
1	\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	\\xe65a821efe50a8793b5926260f36f9316ab6b770c6e11b4210b31aafaa8d191f	\\xb729b85f9149d8d7d79c12acdafbddd26f1ef3ec021d8189cd8fcc14a3a3af1b52691cb3ee3825fa26f2dbaea5bf8e65b39a7a016f89e675afd7cb76d932e101	4	0	0
2	\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	\\xfd05002881b1d7d130be6ef572de8afb930e2f599ffeb4881ee781ce40608530	\\xe9f2b68c5f915b8589847dca4230837a8d59dff46da263c28c670ffc6b86f45e67060765b0aa7304baadf998104957cbf26c9ad7ea50753383e71cd5e1623502	8	98000000	2
3	\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	\\x8c7c8913297d6dd39a9aff504f9e4f05752b2e12328801b31f9a389e9e722f74	\\x2e706e987dc0b020b673738fb49f130960d5e3896194ede9521a42f27303831e57140279f84166124a936428f84d9f74036064bbea040119f85ed152bd7b5906	5	0	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	0	\\x7e4cb6c5e8cc4b7d45bb760411019083c1f5c44c640e572c3ee9a3534e1a12d4c3d836327ae7c3db4a9e8704a24dacda9a8e9fe035f6fa7213149e186b202201	\\x661b14c509048ec3694fe0329446689320b932778770f7f0027b67b69ca354c225c258fa82f624b782df0d8f72768e42633dd43dcd9664d124e864e5563d4e36	\\x4bb5b6dc1f02bed6def324cea67a04566c3a712d5e2d871b98d644dec655351f7ab6985a061e44e65e4656bd20f7a58c667c366f6d6c5858be4b083b8e4d1c9ccfa12087d1db6bfd51f11a516551a366d22d16359033578648a9b7253d9e338c139f2edfe3a26fa60425f50332eb4aa9c6082dcd5ad4e2378ba1d1feefabd452	\\x56b838d2702b7e8fe7d02838099637d1c81b08f0be7bf0b98a646fe28185d356f348d75a9faba975fed23b7aa44ffa8f7f897230ca720a779ea9240b4a027351	\\x1b79fb5fa916e24b4470e8c625c1bb931dd1c4fc3adad884a47d760ead2ad206fe03dd058c0d93aa210d1d8908e8d3dc87f9cbc56ca800ebf0aebb234e711d8ceeaccf089f2d0e2232437de3eff86b6ea7fa2e6edff4d89335775bc5c1f09cd7133f69bc9e77c0bbb232ea67b799de9305960d4ef3b77379c79dd67e9d782b24
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	1	\\xce0b0cf61b663555617c5ecd849f572c9e056506ea9b7b6c1b57e6bedeb118ff7b77604598d6b4050f086c5c11e35c560b32dccea21e29ede0135b5ea3c4860d	\\x4d51f77f9139f8c80fa05f98a6b7b343c5d7dcc682eacbd6cb54064f68e8fc20b029b5fe4144e22df1132ba4d35c39e07f4402b6bdd0a8549bd724550bfb4b7b	\\x0bf732e52aeeb3611d0bb967c0ebd4623597df6c7e5c4f0457aa0327a11fc9f835735dd8f40063ce6e6d03428b4b192a063d94a04ce253ec00c978c5d3879324ce0c22053d448a8c799e65718c786e35399e17bc8c8a4bc58782d8ee2ec7b8c069dd95269ffdc8b603ef0786d16e8959b13eb06a06a21d6cff6b165bd729476a	\\x10b68ac61be42231f1ce75f3ec3d895bd008dc46d25d2c8491e6c79e130feb34432fef4c5effa3e56c177774cf25e86e8fff26164f937bd4bbd8f78451a47440	\\xa5224cd50ec32477468bbc8f8e9524af7fc420da0177ef8fa4032617d2870f618322a29074f6737499b49e3f270ee811cf1efbf4929cb4be61be867921535ae80a7e901e2692ff4b6c0b74e58fb7ce907491d268955d0fde1c0a8ad08431658f74c2c93eaa3c4579a8a85ec4e34dfe1583dc304eabd30233a7ca64e5202e5e47
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	2	\\x2b6fe212d973c201c464ad94b82d82ad8e30d4060204ba67a9f096f6c002a4ab0e7aa5c65a5039a13951142a5aafaa781b1b4a4bea41f8aeefe0304598dcab0b	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x7ff00b0aeb3462f89309a6f35b8019568d42231929a0cffa9c0e73de61cbbd2c42aa547bd8f94a1e71f33474e48966c4a56f73d25eabb81696fa3e6759db627402d5a26f284269b572bdae24c4f8cbc3c0553ca77a3bc80980dba39784161ebf943ee0344c822b523cfbd33b93ac6af22186872568254161df8ed80c953b6edd	\\xc1a40b4659c26d38b36ff7b8ff86bdc49878e4911dbe4c0681d4466380ab7bf049998393d0043228f4a7735ca9d14d4bcc0f172c4a193bf99b696e0a6d0f9d63	\\x0b866f6d0512f84f62c158b18f703cf3b3db1dc6baf60d8602b337f77614b005194faeb0b502213497466042c2c057cf1fcffe9a06b9fc7b638000cf48f7857660b7503f59c33737c3efa7f42907e92df61c62536b1d54e4bf0b8c8f2c95fdaa572754e79e62f3fdc27d8bda29d7812bf565aa3f13e0d31815508fef2266295b
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	3	\\x3200260643a76ba832a5585df1ecfca91a6119cf620422bc1308c1e3ff880a856ac7a9ed32ed4216b8f96c63e06c93a97127de8b3ba1155b9aad6476c919f10a	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\xa7e9d503f1043f5dd2c1b95a2de59f631471c2be52035689ca9f01a1faba0ce39e11cff2930ec7fbe8b1f034b874b285003f36d3996316202b62e98e5b5cb9ef5ed882faf7a1d7101fce636bd3cd7e787ef8f695dd3d153d4b2f157e82d6f9a1d1d3def91fa47541788195a0a7ed86b2a4d64305685709d70ee965d9c0669010	\\x2b4faa520c877e2c8f9e1d9e76577e021722d21f27a8a55aa1501086944273d87e1ebf3d4577a94e6e4d46c871912d049eddb81eef37e2410274fc69e6b835fb	\\x6c714335d79a67a555d183ddc9148d8b556123eb4e3c8f84b9c8d8f757b1dc2a6a7678e96cd36c5b66311f8217ee658329f4c6688d7da19f1d9be16bb4b091add2c755ba5d4ee27e38a564cccf07b29da55bb557b986fccb3afe6263456881be8b2b4f7ac39ae9a4410651da0534d76f207e31cc2034750058dd178548316946
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	4	\\xb40b0f847274d9023743f270eddb807d491d6e757eb7c15ee834ca20b499034715f635f143afd102a48a92d3cf16e97be3cf8ba5ee58f58fecf0e9e2bceabd07	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x1d7359e8ec15b8b19d64aef8584c08e39a0de55e69e7e9bf1b9c6721940b5d955c7a31a038c541082c020b8bca679e61ec0a217705970f4073f56e22dc92665c7aa8ede08caa38ce96ad72f5ef5015a65f75147f4f9c9320d8a8daa58bab8d7afb72cff8ba5df15c34449c3f1ede4454c4a81a57d8842c279d421878d41c880e	\\x9c1e0c2d13f2c7c8c9d1934545a5c8f9bad478351e889cdb1cc907b2551179241e196321c716952cd60e3fd7df61bf9858fbd4ebc95f5c5c2c20aae41eceb162	\\x2d3be82c54aa94b0a5927cab0d6dca1ce512447deccce688a0c7737c75e0be82cb8d9a16aa2786631c4dd50c7e6649b0b7b969f7380ebdd44c36f59a32cbab3ea305c1a2ab3ba8854acd9df086e0c907969e21981c41c6568c976726ba53fd593e2a5ea6ac08b2f3144fafe07f04df71cc4d47a5e6d6b1be0948cf6431c10be6
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	5	\\xa47f72a4c80a3d96615ebc94ea329be33b0b1ff48cdb9ad07a96ba3cfe5db233ab0044fd0b4d59a69ad7b2d81c422b14869271607caf84c57c14fdb6c124b50e	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x8b8fb67e0aad4cc8d2a887af36be4fc750689828a6d9d93d98cabf64da21c8aee7789772db373854cc929aa47dca229a7abe5868b59aee9538c352aa2d29742597277d8343d1f2156e8f82dbad0fe8a9ee923e485e6e9debcf5ad0150c9506e77a2479f73036350ca130142d6aeaa5fd945f63ea06644b7bab8e79ea415c6d07	\\xcf531299051c18b2f66ba1727713453cd2bef9af8d4575ebe68a09b2854dd39c9cc8ddaa7a544972d9fa76cc21326c0d3221d60b12915a7b8e379270036f84d4	\\x2ed671b205667925d55ce03d2ee3bc58e36aa38dc897a08f964d6e3acf32720ac5666d241eca1bc9cd33c583369e62470707b68e940567180a6786353e16a385a6f2d9d5444aae12ba26108859f4fbca07ca3e2d16c9babfb066a6206907ea7a6bdc72fd69096baf4a57875c99673987ef3a080fcf46bc8c36336ab82a8d0674
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	6	\\x03633b197a635d432357fc56d749ecbc8191ef2267516acf72a05b5c6c6fe4134c417c2a3b8f3d52861fefd35212fbe458ca6650badd9cd0c18de0fc90e3a708	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\xaaf0910966f455abb8a44edd1d15161acfb2b7783558c4435d43ebc66e9aa219978e493d46f760ebfebc70031f316cd325400b143ccb9fca0835e97f9e202ed7e1f01e861cb5240fa5d4dd95dcd957ac6002359626de0913165ad29d807c766e48f438f53bced23b529fe6f4c0726851560b16afeecfc5f49c1937aec2c9b470	\\x7ad3c41655b062040aef7a2321bcc30aa1f2be714b474148afb16ca1d897a7ff07271d5e8e9f948fa012b75e3c8a2fe663307a386aa9f52e3ec1a675999acfef	\\xa9147f6c0bc324aea31274d19be7faef490a616a08694209574967694df1c68c36917559b810c70ebaac70e76d6df18678c7d9fa6de594a57584fce8a5bf71ce24dbec4312d37e6221fe2e73b4ed5e75999701fa34f3e8ce7c5044a0c5e9aafeddfe2f50679e8def8ea195f396bc24eace8aba0a57419f959dc998a133f57fbb
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	7	\\x9ddf30e19b63dcfc6ffa1b7a0df4fee41097aa5f79e4b8812e573ea36ef7d7b5dd45f05c93ad8a8d68566be5350fbaae275b2fb7c1a16873bf79605aa8d1a903	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x5dc6638fc6720ea7c1aa39236111e660f7dd8c518bd6ae6ec19d394aa204c2c250b3a3debf703543f63df5bedd856e30151ed3255a841d50087fbe3e2052a21330553d3792b97b8321077730a83ddd4b59641c450986ebf3564902be16334626ded0c2afff9817170683675d265295e920d3ccc2cfbad73bb994a6341b54ae8b	\\x1ed2bacfc710444aeb67bbe24f60cfc72da6cb05731b62bd1ca858d2cfb8125e1f201d6fb723b76be06536f83944dc32357de385cc79cc261af6d5675948d921	\\x130ae8f9bfef513727c8d228145a19b8c707c7603340dd644eb77a8a45a967100b8a138e01ca59890a7be0353c54a0852afd6556a2b9c104ff572726788f69a1d3278b003f2dd2f4771e6a69c7f04e4e0de121ebee4db6594e769a31d0e1af70b76c6dc02f1556b3abf0bc3a7a2806b239d95be75ffc3a77f1df67ea73897a63
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	8	\\xc68a5d59f44bec32c196cb230a35c79fe8298ef6b5dc0903877679cedc82d57f1de43ad5b0ac31ab78883fda6f8bac3035c5c6e74a695d466c9394b2ea4d8f0c	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x439887d0db60461c387d738e67cd6cffa87d81a7bf5d554204c589551433a30f4a948183a61f6a8b1213b8b8c6e7208c30e49d0e557a3f1f69fa0a1534aba77b0844ecca8d621045dc6cb6bc134173a7a536d93e9f7ea46882f9cc6d2947c7086e1d8577b25deb2f0277ff39a6afcc81ebcd33d57eaf89f10cafd09d6f18739c	\\x32bcd9fc0f36c11d1fcfd46e003ecddf5a7d156da0ea87fba53247cdc6bae6dc05a85b3dd75d3b741b008e0217c6d1553a42e1476e8ded685ad59e5c490596cd	\\x34308a5e346f3b326862a13388c49908a3c92e5bbf69b086066800df3914c5bad615cb2a9578cf988d9aa00fa53b44ccf2b45eb5c06ba1e13d859f7aa7f7c97afef51827c2e59d2db338dac6f1346832a8af4a8897ff1848320b7e7b7ff3bed4db41b7d63b87cd943b687c1ddfd6f1672811706f95d4848176ca9e64e6053082
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	9	\\x3a135e8bcb984f7baa1c030ecfd56a0cf56b2898194c395adf077f4598bb1a353d2159a25e47c84cf0c2dc5c9be587b1091915ff311a54e03cef348ebd938d00	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x7baf88e123342badef9d4cb9b291694fec5912ca3dc09db48a92f0f0ac0dd3254c14926cd57bc40423eb5138fc633b6ff422e929fac0d45771ee295bc3d32bf10133e96900bffeb03cc142885cec8810fec38ed9c63c32588533a240dad0933a68fc986557ac7ec6ba574503b9a58f42035e5abebc08714c26dbb61436d68dde	\\xd2eddb2b0768dc7daa752f69947b1ff4ccc19c6978f39c0f83577e12b4cce5483a7aa188e27c09b337a9de25b9ef3a4602a5fffae09329cbe8ddd6cd19bd1651	\\x6bcb54af19fc63a147487a06a7cdbe45201368d4d076df26faee6a571f780dc0c90e401d219b7effe6269ef3dea5e4ef9e734c13c50c33b24e8329dc4a83f76170ad6fb992a06e186ac99586eb0ebc08afed35e4a7ab54207787c7692bdf8e1afe7404df1e611c03c855c7141c56a2a39f2b55b477749250a693979a3d37f0ae
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	10	\\x5b8f1de38b967de2a6ca9b3860918c4f3545809cea84b31db70c3960a381f29a0447fb51be59449b3bc36828fd5b6239b8ce1119ac6451719e36256d56ef1a0d	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x8271827c367a0be3f6eb351a54342261d3bfc699b5442124002495604d2648692e608e873f891d846382a0bf6e6439370404e7345f4f8377981b1bde91b415c08e1798c77dad04f824df7bacdbbb645fad1cb5f62179b306baa901c73eaa60dae91a7926cb4ec7ce96be63a1dae631e4fe1762a5664e46f8d2bab70f31d59ca8	\\xf48f13a7d0d28931b99af9f87887c197925a4faf4a7ae435e7aad8251bfe4650d93f4bc705ec9f0a2aed2197f98a67c3f1e745c912c621b6c4b98cf208b4b445	\\x2f37335ba8f1ce4de6948030db40ce3f581b087763b796c711a38bb0e7ef00034ec3da345b831b1db808f85014434f89ca1503c58968547f450a48f0c0106f1fc7321eba71c84853e70fd00e3ccfda7373f7a70eb7a9b5341a3e5314db5c2d0ab27c27cac96de59bf2125e22d4149735e2e8ea53d8b45978a948754b73687a6e
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	11	\\x8df61267e3b6cdfeb173221258b830a1c72e96c3122cb6745ddf95d0e27271c7ecf3a06d90d8775d74567b0036a5511c02b6f29315132312746449cf11413502	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x5277fbd34e2632dca3ff24290f10201c60a6a13f2eceae809c2beb784a638e3831bcb2db1a4fca8470db2e1dce920891254d80b51634624ed6a21b64df46f41153b99cbf661efc9437fe1460fb07a146428b50c1a627b91e2edeea8674270b5497525c91aa1db30aeddbca200f79a679a43ae2122a86e8738739960f1583cbb6	\\xc98f9f38c1357a679fb1b40a87d3de085f941a05ab0b6158ede208123b366c274e290590ebe13f6afc79c16ef30d8cdd14fc3b19a8c840ed69e58524c2167c48	\\x174a15d18f61aac81bf8c0b4254832d70b197111a04e0439334ec19b864e089c99e9c4c7f8baf8a04c2b35b98f105761ca5852526aa13991cdb05b833712a25e1bdbfb77828a0d0b26e3d7dea682745729ad07c8d4373786583fa5cca3b12815e834e09fb9691054c62b8dac960511af9b2f1f39dfde3097bac53b937e6aee8d
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	0	\\x71a3f7eb4eda064e5f6ea96c424c31e2f417a1490d451617938a83113822d99fe28e6c3ccf84b28b82dae5f19845d93dc919ceff8ba5d5ff435b00c6e40df206	\\x2107cccfb64078d70a5f05193acca64c78ca4feb0d960d7a946381b054cf9188e64012490b5bbcb4ced6efe12051ec283384a508e0d7a77c1c3e6b8b1e60e438	\\xa4152406649412d32296c8a2133c21a5b408cb82f3b95c46fa04041a169b5688e083f0d93f43b16df2d42cf49fa47f43d9b2bbb63f7c83c39033d5513d10e7864b3135efea13afc94e2bb4f6a70b6bf7bee5445149ea3ae1ee037a6e23773bd00e7b2e14c2cb9932af0b9f541a43363115d5f0eaa291acc47739092b8d76c485	\\x653b9fe3839d98e28882d2b5a678d09796268a5f7a402691148e1a4d1439238f5cb7eba612b3c938472c0f18b8f588de70e8a899c784a7fe5b493b1d27d67192	\\x4814991285f5f8483950d281b7c4aeac48829785247d4f19d99fe3837bbc35b63a9b124b85744ab919431e5ecb0ab7212be27771e4fd14566de53066987aa628aa0d454e431caeea9aaa594de3b24766bab5e46868ab8d64e8e9fb99ae39250f72ea2f4e96058f5c981b274c4bddc325421560ce0e83a2d68891b345fafbf6fa
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	1	\\x10a523d4f2b866602592255721e2f8ffa3e953253cedad36160d6ae68a96aeab040eb00b11481feb8d050bd1e5c0719230483c4fd511202780ffcfc26ea67300	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\xbfc4881a0520ff7d4f6a4f76c453f69c16dc75b50787a82eca1e273724f0b7ca46fb327df915e780d8246d5acbe5b5a47cda6dd615cfa6772a8b14a07cd7ad0bf6d487f4d98d5f143a87ec0daf046048ee5556e14b16e627da0c3a54129ce477546523a7765c7386e31b3906a9cb74f90973faf9c78c794cee58f1bd8f95a89e	\\xddcf59ea9768d3d0ff226153d195d2a6658f1e04d1aac3e4ba04c64f4d91153622db2f3d4a9da85c256df8951f5e3e23394c756f3fdffcfb28b63c11d823874f	\\x5090bffb8685302294c22a7bca44540b1b048f3c455dc205dd6b6acbdeb20e7af6ec3523066f243c38b5975722231aaf32500178147a38ac7feff80144bf2424ae8978cd666b4d8c78594bbc47cc2eb361f2d1f3f4c95138484142beb4feb8e53f34aa37d176e8fc943e76d8ec57588d69af0f279353c98b081e488b888a7229
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	2	\\xe243a2f6de84dbfe3a17c6f6c6ac3ee0b234f9c2451967d81099dd8b1efba07567339123e04623d50cf9adc74f17abf335999c51af99be61625810ed2673c104	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x2c3f61068e05641bcd2373e9d6f2d5ae207b5913ba1bcec1e4121f174b05d68449a0914dd16f90a6576fc3fbdf52934dce201962fb0fd7d58bc5f60cf163e4c5ade173b3503e607d30793bf0ed46b3bc5317a5e0d343063bdf3c6213aa012347a938e96ffc0ae6fd4dad1e5052404049bea7565a407a00c6f1f8e332b3543bac	\\x58245b087b7522893ba1dc3df2f456cd85344e8299ccebf9bd19cff20f4babb4188797d4e652344d7e99a2151ad2203887a9d3e47480b61d566fefd9f78f0574	\\xced30bba94d00a96fa0dea87ce35bb6aef8d02a234cc47ac6c6e3add38cae935d9b008b826596d66490cfd68bb2439c1c73d6fbba06926e9b98a98e18cdb6eb279f49773e6485b55b7322d53b020c0061a9c1aab8e4daddc4199cf17ce4b9d0f271d01adf5e2e76a47090d373607f796384b06f4ac8f7c70bbc92ec31c2b1694
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	3	\\x6b5bb1f6684d252b5016728428240dc55cda8c5b77659b471766df2a43193ab8980ddf8ebfee69674b53b828a838fd9751426f167f27ebf587a43db631eacc08	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x7b9b1a43ddc5e7a719a6669e58f5ab4c05228446820487eefbb614a0e67f2a112e14a003613efaee4f0e59d7de7df8dc361274517b4ecba1edbb9ee5c42fa77124914df88ba3e348565f005d5bfc867a33b49526d40cd68ef6bc591de4a8761c059d26dfc7ff6ad20b877bf573bf3517e2cdc79d1480224f17eb4fdda329ecc1	\\x03e252c1ad024e102627e80aac5875570a6ca619d8cec6a57dc117c822003526a8092fec269cc2d1ed3a9de3217cac2bc10037706feb6133be7fa79b787c3a26	\\x8e015d27c25209dbe4935cd492b982230887e463e7b02eca8d457bee0db960a05b91d6da5c686b34efd1b0150eaf4328c657872a509966bbae20e2e48563bcefe24af7d7177547a4b3e0f72ae05f6d4370c608ae37b9b00fe7c36849ec2e5dd1026986180e9c8611429397565c527110a110c61b2eef9c81bb02cd6bcddefbcf
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	4	\\x78faac2150d47114e71adc9d8661636fe9163bc7bfa53c9d6c8ad6aed65f00e6ecad8b2d2a87450aa86d07c9ec8be3c4b3288303b8a25767b0dbaa7cec3ebf0f	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x948bf138cb112a8c02ad43fcc3618cedd1a8842195fa94772cc7257679f349c3731195fbeb17bdcc22b6f06191e4479c203c38f844b3f00e389c36903d395f13cbafeca88454db5930073f23697a8eee620492f28ed9ba831c611517b11be63033503c8e2ef99aec46f2ce2d781505afb0767ba7efea606f14123039900b0a00	\\xa85a34ef6ffd95fe630d38b1d2112b18828bea7dc9aa20170e9c089b00be796ce960a0dc0092087ae9df2af9f6a7fc1b6c659b1f907914d4ea92ecffc7aff550	\\xbb0a1243db357b40a1c80f9f66d281a0f718c1d898e996868705f067eef2cf5020d936bb309a0c72da7ab92f6d62836006e6d0d4574d7c398766f0c64de7662aafeb4971205b3b1e545c177bec017408e258591b53099ca9a346ab31e4f21eb6f2b02cf3c496476f082660e7dc91372de138f02219e6490da3fb4bb2f980da80
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	5	\\xbf5ac851dcb2bc45579eaeabce3ee5f7393721e439d2cedbe8401e5e1dd4df6dfc5b6ff5e412d71fe156db2a0ef33fef6b2fb983c76967243351d5b38bc8aa0f	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x44570986b305f9327e1181bf084d91f5a31ff0655c9d96cf6a1f2c837a37058e11e7875d26c55d5974763874663cfcd52b5f496c1c479ec328476a61fec034ad2c9e4cb3e61a7cf018b50d45d3a82bc881646a153269d4070485519c65d074b59242669e4e9b9625dae4495147adf6806f0b09a94e85483f5dd08b7463a60db9	\\xda6061cf3f6ca9e5bd051fea4d407abae65ce8eff4dca6858958b057751071d885843c087d764094d1b730898ddaf798401e306a7c097d6174266f4a1396b978	\\x85adb07a2c356e4f6ea39c14dc77b72f4db08ca310a6518a3d529530fa7404470b3b1a1fe901109e4b02135d4509b197d887cc8c296d51cc0a9289df393f7f109afd8e3c88a239a12f5816737481d8a5dac50064213983a1923123db3d247c49f6fc2028c8e45f069385336786bb9f25c85edab711ebf9420c362356c5107dc4
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	6	\\xb76866da16f11e76e25440b9d9897d9141a935d5d6de5e89625a2cdcbc9ea97fc22eb3b078d72f63267dec810cc42c1278c76b989f4cc13ae367cdef2ec11a08	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x67afef73152f24b17a58a74c679f36666ec4f147f561cb54fc7d7e7ea1afb8319da7551bba9a23f5053a5c86af89f24fa3edd4b6e8f12f08cae51714ecd6e2a2caa91215d9c60738fde641fe13f6aa8827349e73253a54ea7d10af3fac7caa598f6e818a3ef32562831c800b655d5f2ac31877a6717243f48fb951544be0705a	\\x15bee26db275f958556f6a296fb62c2b99119d8ef274ea8b1d90a07b99a91ba9892f4ecaedc836166b2d9fe5df531e6b93a31eabab45b446e2fc5f28ee7c7c09	\\x78305fd8e2fd444dd80cd25408f65cd3798c9f212e24a99d961e923788d1e092d2db41e7c9e03b065db9f6b05a40422fa0d6097943fb60c602088afaa63444b6b329042ce77e8e8dae11dc5d7955d90e2b4ab834b6a7fc9d9280cbf20e4743bf23ac6bb64ff756c57cc7c951fd9d4d11d0658c3bd5d4e9e53bd8b888cb5de521
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	7	\\x8e781ff0900d946cd8a1c9bbae37b05ce82b813bd64a7b6e63e0fb0c53dd674719a620313ce1ecbfc8c628a4ee5d6d1d5753e6f73b853a94482aefe6d15f1e08	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x7084647aae6f9b704c71188b1c503fe93f2c1ecb88000012160fd81bd9f18066a07b0c7371e6655b3599aee1c4393d073287ea87c50266c84c42591c41ff32942e4a681aac6154d15395e301f591714f7ecd3f543140c36de89cde8ebf9699ff6d7f0a03773f19937a07bb12e4a4ae938eb31d1ed96c0591a516d1d8813fb997	\\xa78445ff1106e286e9f08ee9392250e0b01481d72faa05b41344afbf78afb9763aa34c902622daf8fc4d8241bb899132a9904231224717cd0f3773dd1cafe41c	\\x9d3dd2697f08f61dddc47312946607c2198135c3727a7a876c45906fc851499fb0d4144dfce8587957d49a20780de8579bb5463ca9427f7d15624e1d7c5d1ffdb60f11cd1fd89d2e2c9ae2d9c86809b8e583e92d975243bc1cd4764d029bfd89ac85ce1bb2561ce5a83356dfd744a65af4664e7eefb8aad69e73937d165af144
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	8	\\xdce6fbea25d789e5df7a730254d4d26e58d80747e31a7905443229d57a844b68bb985e78ed97fa617afd56758284810c1d89b1c802ed8610eec4d04ddd613c03	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x2c3961f8883952fe49370c44365d07261127722c1e162097c12d9269af99ccf8192aafcf9850add7034547af679d3de894dd9930bde8d621a0141fc0a5d78666a924e3aa891a54cbcfedb85518ed7fdf068b437c26f11007e4051ef2c8adb75fe5ad316e96c938fa3b404a7620b97121e1e949f17716a7c79a81458e073d8c58	\\x200a86d6b2eecde53ef3938d1ad5b5c0d18142d6b594a43528096c0e6f135b32fe87d3118febf6c90a8e9d8c54bb4317138ec66e218675a40f2558ef280e340d	\\xb5fee80a4234dff019f0f66d293af2a3438732e9e0041161d3c5a13422ba68026b4fe52a33b6b10a9dcc54f06f50e81cc727844fe02cf12d2acc6bc7cdd147ce89cf1a25260482f8246083e9c16b0db0d64c8e8832e838f03e658e196e411e95d3661c4b41268589801fc9d28aadd62abd2bdda52476889e86b41a6dc800e4ce
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	9	\\x919f55c0013662e930b2be441f6dd073f9179d35ed14f99b06c609fcc16200086e3c54f0bf52cf231f87a5c1c0cd5cf5d44887f634c9fc96676d0d4f0865d309	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x55ea5d30281466d55954590ca444c4c35eed6d1f91dcf7eb063e2b8d8e9ffcf0ba49baf8ffc477777b22f17d5ecfa917cc04321663dce62153cd18a3dbbd55c94a61b05979d7a19a1a1cbe7033a546ff43924dfe9c13cea467b0ea34cc1e4e384079ba495a51274c635bfdfe94e28658f856d62e2540502bef20b1880e6ffd7d	\\x899367826d7709e0ae2441e529c45f49b3b7139f50a6258e189cf1c5e7d8cfd686b16df15886b03ef78217a8739e8d4096f62e615a579da8f11c89f59abcd0d8	\\x37e4d520bc26d490e09b2c788cc5786cbc5d9b77b80b69185b0ea742886b657e722041d52dd6a2a611fa6d8b32e758487d35ed7da67bddaad109d042dadcc60346504ce4410deafe1020efe744c61f3398c6c335a8f40ae20c5563e9b7e010f069d6595782120e695f6b610f8f3437271347473b5d73e72ae898c5823d32427c
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	0	\\xc8f3eb2a4b18334058cbdc6ca906fb3755f7ffd0c89ed57d9908dad5ab700627f344caf09082f988a398d28cf4ca4515b321682e53295c9f76780d87afad1700	\\x4c484596323aaa5e72d70eb101878f5184dac6f5b24d4ecac9d3edfc64497a6066e4dcf89895fef6b4959f833de8189cd9f8d7353cf097b7845feff61d36f7e3	\\xad876a0804b2a368c5f6d910b1806e7ff30d240fb71a84819acfc1c020db71f45fdd497cbdb4a66fc4abf93760a35683e2e78d07c953523551541adba6b8503af32ce79a0901ab96e5e0bb3435fd50a9506c6a7b9b007a3affec209dd52bf78b994c81d6f3d895c930a33712fd0978e82d0bf5d5f4732f292d5a5a7a09d496ea	\\x1d49b60f529e1bc1228c6b8e61268571bf1e610db4ddc41c914ab536ad6b985827c82e66d8949a5a429eea2a5fe562caf073312f2bd929834483bc0d89d88b7d	\\x50248b15c2d65c448d0d3dd2520f8a47ae35c85ab6d1e23f13ffbae98e67e4d2ed703edaf3ec97684f1b2874f85f0a652a2948ecf7aaac71fcae2e06c6ae2938e9f26d6a6116e1ffa3e4e96a57ff97b7ac994d78b67e2c1368b7cf232c5b5d679ad35437e419b38217798ab26c80791013b6909a54a1f5752747b6a16e9e7829
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	1	\\x59ec0b6eced2ca046dc430355812dd8ee4e975caf5660e5afa8afb49ee8290be151648e19428b28d1e4b4504d67f32985d94e0a0aa714090d9847c84e805eb0e	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\xc5c843ee661955daac0c4cc0755eb41514f2c237b80a9d96cc2b95940d970a297bf130bd0cda522e3a9483c8dccabf64b21f8edd70dc73730b651835877335624b14b4a01c67af1787b97bf8a8028dba97003b56902b6cc278fa4e2a8ea3d6138e9132e287ee3ba9d4076ff08e81a934bb39f3ca5cff9d2f59fefdccdf28d019	\\x8008f9ef84e1360ebb07af06c884244109d7abbacf72dd807bce45323a902b0626b8de3f829e035bb1332b17bc84f12cde1bf7ac612999b3f87d34a2a13a5b98	\\xb05c2f5d530465f7fe8c7a24259a52f31747e3e561fa607af2cf0b7c623b7726b7729dd2da689dec958604ae6e4b09caed99e0748fa894132ecdf79bce7e973747c389167b07792057c45a99d9b77391bd177e0e3f61041636c54f1cef0cc65786c3d7879c26308ca5d2199008b7925c16c0d8cc906805236263625d327fa73a
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	2	\\x8173cdcb20ee3c1d76506a106128088a389723e2ef802e2cd27e73b3796672f26a90f6a298cd59aa9fc9b37b87d879d3b313aea4f499266c4fcf43c6bf9af802	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x8cd9abbf8054b5ece1f76d79a119fc4976c2e7ede792784e5402b5c1cf9ff17a7610d7aa914c76b220c8e9ccd969a89549c08599ccd842dd7b22ae5dd8bcc633b773913780b1fb30789bf654583d91be848373d42d9af767b00cd8d859e1870dc05d7a7683c1d332e63c75222de6edfc444fe2744f22be905b3fc2e848f39df0	\\xcc4e8f6f304e26070df9565e916dc3792a8bde74dbd1971ca5bcfa353f123c1eb84758eac4db90b8af459cf37e7e161452994f18a2dbf265fb33210afc65daf0	\\x1f23ca26b2d2fb643012e87e9ab38eed59650a58def3e5d87e0cc76da475cc9a595770685d184142142f517ee529eb1f7e3e5ff517365bf38ad2c1c168f0a9169cd82c45e16cd627f4e68444200dc8778501251dfee64b22403bbdcb338f832728f2b50f5b2321c47d4edb25f6089adb301984f722c9f4d5912ba811341c72b8
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	3	\\xf315635119085e89ac40237890c0e1ec1cb31b693506b108810ad3e6253accd499dd24858de6e273016aa06ff720834dbb2ed9bfd9bfe14c521c8692c7357d02	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x8c7285e0e1f23db6debac515df0eed027017e6d711623f763b6b5aa7a8a41c877aa35d8778e56811b663cc1bb64a1d4af80164ce322f20611a562b5fd990ba3fb852510a10945c113939b5b8cca5df3da5106b0a8deffb989639b0c5e6e727466569ad7ccce5f4161e8e03cf0ad882e4f63dd8128df1003543fc87935551b907	\\xdd335bbcb5bda310679bffb3305240962a7f7ff2145733ec0b7f2bfaff113456ff570fa850fe4aeb06ea5d0cd2b18f8f9a91e252999feb14dd4f662357bfc1d1	\\x71b7ac0e92f8db1bc7d94a8f6e4922acdf2453219cfca0eeb4a3fb4a98d1dff750790002cc482ead0d6bc5852013ec6f35ecea7cfc356ab679e27ea4c964f9f3691d8a7002c1b57b467022cb98448e9087246eb8341784e5368c43d502732129d7b881dea45502fed8c457f89239fe9e4adf0db02113fcb15670967fb5f8edba
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	4	\\x2219adea4035f86bc963b28ba428d1be148ce929811d1e8db8eb002166ef6299947f8f8fe7a99a5ab00294943d50f05c92b65b7192b7de9111a5030500c1f508	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x397def48760364a74ccaf2eeb192a6b46367c3d10b1bd00f3b50ff03a4dda4862d4a0aff2b9eabb15e5c9786e422e0bc99eb57742c87ed86705ebcb5908c0f3c6778202527279787cf7c0f6a287f76b1a2e0726916c31653a90b6ae48cf988a8a04d0a1f924f846961565677977e9b3b563c6f7e65707a9c514040007cd2e4f1	\\xcd36e0282d3e3a998ce8d1708b9fc222a73934067a76615d81e37d34b38103d5be97fbaa25c5b4eda51bf8c6cd985dafdc063737cccadf12587f8cea35057e90	\\xa541a29a03bf760968fb33c11727f946150cd8052ee746c868d6ec0c996102bfd7ae793f95f018101e34d0280770060b903a092aff7ab4640e362f88187edcecfe818b70d0e5cb6993203beea0a98c2f7dea1d1a113dae227d6fab7e6e70a55e8dbbfabc2d054dab8aeea544879ea9f63b3b7e0a6b0538c2615b7fe2449d8f32
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	5	\\xfe250626e91a0f82a30f5ca9116dc14f30e72f1983aa66341896a687515d0f518aa3716177c4062fa3a32bf6b971c056671f26deea88ada8c48a89f0dfba4401	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\xcae3bc495708f0642bfabb6360f99834735c2fbdefdf9b470126b825819bc845da37e0fe199e4342456aaa597229c3904e341a40713f4cdff45d2b90fea57c32f5e864a86b4243b4ffa0422206a6d1c635ccb96450a077206146742d961099651b143fd5f8a95dda6603efdf223c8db50462d24148cfc9c2d0eb24a02caececb	\\x0d6265083d25bf919f998ebabf1ceb7c987b5235b673a79b68989fcc305ae8bb66dfe29a28fe7bcb448974c5b68c6d9b7ff9a3f022f1b118309a9a2129cc49e9	\\x397581e9a36b597c42ec94e54ff029cdde43879382a3d37a6386232ad2b5e205fce948ba805bca894d59b7f2500bcb6e83cdb61944bd39edec69226ac6024436ec412ac65f5b969d6b4c5719cad85503ff9005361e08e52f80d89db913fee718359f74cefc6206d0d1fe26df7097134c5a6e6fa9b1a012d013f5ceb617b83e1a
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	6	\\xc7125a0cf4bc29941876e3012bd6a7798a9f67d1f85278894a687d3b5fc331085cd8fcf0ee56e76c1ac117497e1d19f168dcc4a767f16fffa7bd3440acc4690d	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x69f3fc646d1ba6f1829aeb3f298508cc8512722e6d2529d222772873f2558cee0a8a719f399337205b15890f91fe7b8560dd5ed9aaccd7467054829fa517c80b194cedf05c8e807324e57fb046d0abfe5fe4f257f3ec8628cdf69539aa05c0dbcf5f4b35992dfe5e177bd3f0e9dc634301d4d7079b31c389b5a1418e692d3db9	\\x06155148c9ad8b0157f8cb17a66bd546cf63f7ecd5cc6c6800ba9619f5a967863b65c976277eede9cfa9ce835d92f1951734434d4ca04b2bf33ffed7e4f1ff51	\\x0631661422522d686d12380d5a2c0738171e0d039c6e28f2c6b991e2f1be0cdd53aecefb560f89f0bf2a16d188736f62500780c613bfdc069ecebad37d0347da1cb88fbdf2803167abff7541041275ba304d0f950a6e511bf8ed22842ebc234d471ef03c1a81541caa1f2e734ffbddbf2100997ee5c77b28bf3209a94d60fae4
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	7	\\xa93afff9cdd09fe9d17183777d2462cfe417cf57a0f784abad88f3856db67888c342576a1fca2b1d010c17b4ce82644dfd851210e56b5ffd3d6f68e949356508	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x262c37def1649bc9a6827c70704775359ea43eca7887180e9f1ae9744cc9086db0c93f4f157483838463e077d5bb73f0aca24c5db1d8d42ae0e77077ebb9fb8c17f15365553da31d327b93947d89e16a7d2cf9c9383fb15fd8333d60b59b73923ac61fd2f221e9f6099284fed6d6e1cc92a2b93e00ccd25e3a6e826bf54209cc	\\x588750987ac236e4a8c227caa2609e1088263be0204354ca97fbccec6ef8cc83b0d8dc3eed2965153436341a025706eda43cd59b44a2e6582a207ca1c5996970	\\xb8db450a697c277ada38c00293dcb47abd67593121a5522ea9200798327cfbc36b8ea987a828d58eff53abae7f1662867403db19021a8b1123125e81231a52107168812ce0593193c10867607db4b4fb15830fbe8ef2638da9fbf2afb630c73d921629974a8dcfb9965bac2509d6591437ed9a9f46630bd3aa4a5804c21c7d7b
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	8	\\x545ce904d2b0f9af3cf4015ec570887c78c0131e916824e6d4119f9c1d55adf11de8a11f6389dadf58f071c41c21ef6e25d85d90a6b175bf16680a21e6e85b0b	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\xc2ccb7880f8636c9dc81ca0cabbca9e01a6c0fc8fb3a3c2a4b0fb778a7b36d41dabc75298306c7cf76a101b868024c5fefa40b0a47c9505b9ebb313157dda64f936a507910e4b635be84d34132dc454639551c5ec2ad4b61f7274abd8f6393177ea91ef15feaf44e8bee3dac5154c0eeb07218eba4a086ea6b52744c503a66a9	\\x0eb6af95edc270a030ffc927d14ba0691f37d1d3ee5ae3cf1381433a0edcb5137dbf753645d6e6d6c4a97f4fb9efb471ac6c594e70d19c2845d3294089ba6438	\\x3f00743207d1e711c9ae9330b82bf4a9e10efe14aa1f059e7b80ce7e1d57e44ff481b3735d2d3c0ededc21c607ef783dfc54cdb03e99abaf924a4b7b274cd776a26d2cdc05712836c6e41c8589cdb5b429c7440f2800471b5f657d0d5beb37b5d3a64e88fe16a99904a2d412f28df931f708b059fc6e7e16944151de5b4a96c9
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	9	\\x07f332cbbeaa940a77fd8a1c4b6058dbb4ad4aada57a9efc99079affaa265ce1f227c60b29b98a40f766b5d6003663b7ac6d19b9e9dacca6ad6240bcc4868e0f	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x28dab9effd27fcef7ccddaaea5636d5ff6ac238fe6b2467404eac0b6fad481e16289dc56ad7d5a5eb43b005cf96e5b3c313cc19f9312278ee27d6b89b910d6c5e9d353783294e7aa8f7ab1a4d1c874a6cda1ef992d691c4e2462ee16101c4dc3bfdd40ef5519d4139543538fc82a1705c9399862e9763ab59e84a67fbcb03b64	\\x36b4582029886e613e4659b7b6a20ad9b0d3fb869e0da15206ae3c7a54a626e9f1a9ce673f7cdfd3aa845d13f52eb96b1e7a3fdedc961f255eb709dbf710a0c8	\\x1f2ff36575d9a1442ed07c199cc6c577c2f6128b109d928801df6f2705b41399672ae878b359f4fdf33cbfdf8e60c444fd66f3fc09743f7ce5332b3520b1cbd2dbb412bc53efa5a484ac4db272a44b893a727bc9723e57628999098189c6aff735c17c1e7abfe1ad3f8e99563ac6a2f45fe7ca9dc46ab88b9d2b45cde12cad4a
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	10	\\xd1ebefcc7b54a3a9dd0d83ef8a87536c68755b6de821b13d488dd45d0a68eb4c74c459fd39a993d560b9f671459d3540a87956a296bc4cb1360be28cab7a5109	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x9edafb50436357d0a7964109f0654cb7a51d5c9d1d9de91b875a5dd9428182a59f99520a3fcf0c596ec1b5660fdcbf60eedb202a1322b4e746ace316e3a9b055abd26c68147843b5e196632db284c4dea24ce75e98217145e5a1f83a9c675c233ef766e3ee415ac6e299e532703e9771982dd54b6f2086652bc39c033e45d173	\\x2f5a59f0fa35721b1ab8cc7600463a6b51004edf11d4f67a1c69a35f0e4357b9c76235b20ae5c9a2976a08043939d2da2b5d7a27ebab05690b8967051c79264d	\\x446eef65aeb9818db69173fb6b89cb99a1bfa62719e632c8b1a258bb543194dbafa1c5b240b050677b26270ed97ea4fffd3b5182860fd8f4b73ccd13ba67ba8ce1bff169297a1081200ac07b8785d84817342fce6535fd8a2a790d488a1d34d45a4a8cfb4fe6bb87413e7c2ca8c27f5637cabce57b9ac5fae97bd8da92cd2390
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	11	\\xa358f9f163bd1d1c68f39996224b766bd6a12a5d4e9b864787613da569ebd07b2ad9ef4f84d387628e664f76fed6b4a78de9587cb8a7a6ca4f2ce3a797f9850a	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x130114d72385c3222a18671e1f958a7f14f19f6ebd6b6e5ff62cb1a5b9fcc9072e9a10ae85a87dd135a46e2293342171999df1d9b3f992de121b94ff193f4cc2a5a3322c9e8dc90c7e6cd9953ff57a904ea1e3b0dbe8f4b55aa62d9ad60d6d6b28915c8e5241c631b5f82ff84b65f38b5577b9ed7c9e96b2985248fac5096004	\\x346ba7b63d5b3d67cb5b6e41d45504325715293b797bfc5fd6d2f50756409bd4fd6a57acf03a5c9f46c967ae0711f48ff41c7700ca46e090090abb42cc7c7885	\\x83c64274931d3bc92b0294709cd2749d77b3c0e4c82acbf163b045c6992402b441a2ce63610b89daa10a3b70f30343dad9351a938f4ed8826da98b9bb07d291f03170a69ae4367e25bc88ff546f3b0a373e61cc306a1ff787db0662aa8ae64e2ac8ef03a925782abacf4329a747fa055c9e5811ed1c045876d32bd3ac959e48d
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xf1abe95f985fefd52b74c064c092badc6e3bb7ee3083ace5bb5ea8a3a4bb84ece453e43aa553fc1925b594a492ae9f956ca553ee0b3e3e3f1f55f40788fda968	\\xf1185e668de5d0329b0a8fae49f93cca05a1cefd07997d6f4a0f882fd5fb6d26	\\xaf8ab753f276012a2e21f48f8d50f4e0c03b41584941aa7d91593ba18257684686325a7ce7f22ff4775ba857f128df40a2e5260b6681eb1117561beb88618567
\\xb9e84a41cca93742d4328722a90d2c10a24344ba27da97f086be19213900ed057d496912153107ae3ac98f31e876b7e5adeb8927f4fda04dbe21062f4866b114	\\x3621defb558dd1124457061bdebf893651c8be33cb6b10e25ba5bd555debe534	\\x83fcb0b8aac9c923687d869b2e9507557cf7220095c8fa4f964ab9dab650d10dc199b9159d96a965089f6ae6b0588b5d43d1b0f9fcc9ec5dddc72ff5c589ae94
\\x1a32638b79d48cb852c667f186a7646eed87262ea95d452613c56333b012a8fd83d27e53c18a0744cb78658001a47653e0629edaeb63da39da0d03ba4232a2f9	\\xb0d7b0719254ef2dd212bda3d02d4d4197746029bade37bbf5f0b05238529d3c	\\xd6bf303c0e6fe097cc64b80307896f28bf6a19f9ca206d218f63e9d1a67b8836917c7d5044dfa9ed2453d3e3d2c685da94168ba51165618c5af52a7f39fc118d
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xfd05002881b1d7d130be6ef572de8afb930e2f599ffeb4881ee781ce40608530	\\xc1733bcdd180df3e221c381926bcb3bd9303d82c49a8a9b0495f86e3ab7da9b3	\\xaf4742286f000a5e3fc70b67c008362006ad461f9858970847188efe426478623ca8e902e8b3ed415cfc5ce7b2d2896067bc5882e56731ffa018622dd4aecc02	\\x3a22c143424dbe30d8bb44e641decf80f8de7bb14fe32eeebcaa8738b8be22b56811c0a20b4190cc5edd072880f24f56e496200ce023b3e40613f8c9b9219114	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	payto://x-taler-bank/localhost/testuser-OBM0P2dr	0	1000000	1580166018000000	1798498819000000
\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	payto://x-taler-bank/localhost/testuser-6lleWuxf	0	1000000	1580166020000000	1798498821000000
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
1	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	2	10	0	payto://x-taler-bank/localhost/testuser-OBM0P2dr	exchange-account-1	1577746818000000
2	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	4	18	0	payto://x-taler-bank/localhost/testuser-6lleWuxf	exchange-account-1	1577746820000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xbb09fa71c0e07274fa3672ed9d1f1030e68b1864c35457643f1abecc3c14dc4ac527d397c007eec9b274b2693685f312248a9952e1650db0c60cb3f350c1f407	\\x2107cccfb64078d70a5f05193acca64c78ca4feb0d960d7a946381b054cf9188e64012490b5bbcb4ced6efe12051ec283384a508e0d7a77c1c3e6b8b1e60e438	\\xb404c29b59d90b0c43d1e93a9ac1fd3388386cf4c93b4efbd129abb50ac006c45888217e8f665ff5678e88f5c7708f5bd5a873e6bc1093392133e62be131bb1653e0efce30559451d48e26bee018d1f83dfc8d3ae5b6e71e1ad99c1939f0fc5005b6aa8a243dfe5d9dbcabf1e4f03108e029ddf3e3433bb0f644573ee79e1d37	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\xf84d223712c3575b6b76eb0b01f62e86dbc2a4803c8a3bed99ef4b69e36fe40883acea90a200c85b12996d45b1ad14bd62de1103d8fba545c4264d9af98cac05	1577746819000000	8	5000000
2	\\xba83ecaa6b76fb3d86ca45be3aebeb5a09c7238649310cf1bf08a10a7ab89343fa88a1c7fa2e175d34f31c5f63641b2928d78f062b8d6cb6f1f35b5a5e6cbea1	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x335d73be32e590ad3c94e1e888a78789f2b61c0012c7eeeca6488bbc059362aab4950c7f986744e8b8f1dc7fcc46c1edc133f6fc721d31cf00fd6c4cf204befaad60cabf68f779d3ce58d46d7f8b197c463e4035742d707059d1e84041122464d795b9d288143efba7bdc988d570134882249f8b514ea822690d59a37934b409	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\xe7fa83aaa3479a18c4e6b954be29f03f4465cb1cb6ef65fae254066f4d73659d710c7abb2738625a0d87c6dbd45e401ebbf5b38bd262e52ba65e22afad5ed803	1577746819000000	0	11000000
3	\\xdb17902658e6b550c8a7c12ab24eede0bd6955aa2e6951438fc3eb7d52c0130c1703c3e28a2b59b0621bd21ec1f1186ca887f9439f5cfb5c9b2d1155302e2fcc	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x5ec456b71c588b3c0cacce69371c851b8d64df7460f9d41b12d29c801d35d09710de72bad4dcee272b7cbd7e948a797de7d2783ebedafd170984162673d6a698b295e4d1e643ac45e1acc3dbcc3d0465bac556c2266a21d7a12c48df25c76af57607d36cb3994d1f49888fd37529055049ceeb0698c9b6b9eebbf75e6c494db0	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x3fe066741ababa1fc287a8d7fb9718a0f58f25c3e30ff24e29a7813a557869327b4467c2d879fb6bdf5a44e51fbebd68a7f4ebe0ec5908e605ad9e9619cb4304	1577746819000000	0	11000000
4	\\x48b1298ace09573c009ce2ab6980c27ddc0767c3cbdf1228b6c0c649f41e801a7d87b6f6b1bff2b454c71f71ee29ef726b456a179663afaf2659e884cbfff44c	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x1a2fcc664c9052492d2b464a02879d99b00479cb3980f4d203472e37393921f9578966d7e6ac66ccbf54d009aacc4c76d02cc339972306ac6ea26d44b02bcf4b7a2679d0badbfc3e524a715e2310037b674ea85444457f364d09c92c72ffef7eb5598e9d1ecda2ffa286018f496fb4e8c9c9f333ee387340a57c492de39bf9fc	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x3b9a4315f6bb5c8bd5c628b26c50e71f6fe7df636c51e6bf07752fa147208c6d8fc748e51b5f497a124fe636f6502712d3d6baa9aaa825c31770f6ea77bf4705	1577746819000000	0	11000000
5	\\xaf77ce3e6a6dac2c17b288d5ad611109344296edcefe7975fbf1f1ad46542d964af61c9fc3fba29c82229305ddda69c184f1f12439273b97b22f2663d3161881	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x64175cf820ba827bf6dac2e3fc1d3a26ffde76bee4832fa30c317f177c086323c25a448e1abba1b2cd76b3d944cb80c77a63d665f16811571b221eb0abb9eb668929dca7cd7033638da4cbc1fd0c77b6880c5400cc982a58e512f93a25b2292a9cbcf69abd035f0d447dd689268d0114e903677f4f2641518ac2c642d12356bf	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\xf24df2f3261a4028973f169f6c07d79365bdcef5ded27f32db97ca4a6e0452dd2c0197483a8b6d8a9a020fa765a21ce5e54e99c786e2c057ec655a7ecbf05206	1577746819000000	0	11000000
6	\\x1a923a7333b30d7b596db05374ca4561a4d979c6ef3fe94353ba3f3b7bb9903b0889d55b9c6a1f847ce6f9ebf351ef4fa9a0398bf40b2ddf545f09f06ffd2276	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x624b04a41248962b625927116c88b25551f81fa3c8298d33700c52b8bb5c3cf3d0203879a49ca79ba2d4d6d05f7efd76d760c9d824c485b3c80798f96766c8d298d3b3b73c7af0985d210fd056ae3b402b6c23a2cbe94f3b7e77328e8c50a834ecb8a4cddad5d979118966e943ebaefa505e85a9d954c1144b19e0474772aa6f	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x2cf643642ec5ab06144d054cbec49cba2a50ac6f815aaab4e3f1ae739ffc70562c8b60a222c8d3aee07038034959e410a574bc0a067ccbe03ca1548b3be83e01	1577746819000000	0	2000000
7	\\xbd2233ad8f1ea3965307210efbbd1e363f5492660d6c1249033ee15832253778fdcef9767cab55d83ef2405fd6c4ce5f9a204f29eed5e4dade9be02b4b6db631	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x4dd7d42b4184e7717407d09d9abe233a9cfb10ccfedcc243e12c37788b1dca6a02b03f92ac81ace6d97b0d55bfa8db116cff0dd645deae05fc114edbc6ba98a8483d251e725affa25af8003db7da70cb5366803dda57dbc4e426893e2dc37ab0763e62ad77a55ea4ed321699c1f83a73d77b2235709117d2d39baab289850d20	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x15c817ae03d6464cb024aff1f06c8fd1c08b4dbf7c5314546c3bca2e0e1c00a44bcd203d46e028b9a43a59a08e92db9c1e6c9901932fc5c4902ab92e8da18d0d	1577746819000000	0	11000000
8	\\x92f4691d2f8b3fba8473d68cd4c8eaa6e69546e2cbc4b5558043c7c996ed6cd20cb2cbac3cb999463935c7c759e7bcca925dbf77e802c8c9b04029aa1b40d437	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x9d5714e06e1082e89226ff60c5cc262549220b5f992bbc62f4c580fbf955a686a8726a3718097c6f0ff5b458ec8eece1f10eba0cc3574f42f35dbd75bfb38f94b3336bb7c6881a5d4f6c79d96201a488f706dba0fc3228fea19cae0d76de7ccc9f6fc6129b0283fefe4be3288c386033c453daf5515f11570449131610ed0fa8	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x876585a4516f7ee8669c320bda44f88df0e86cf61058bdacfa62b4af1a43de2b4560bce2d3f2df26c5240f43ccda320935bd9da0fac128e8e707037f72668004	1577746819000000	0	2000000
9	\\x794cfdcb57888b9e7bf08bd58a921856d924d7c7e22cfdb9e8dbe68942d7e910fdb37a5b666cdd7b0167c6122bbe058f7d67fafd7a1c2cfc9e3f553c6697d996	\\x4d51f77f9139f8c80fa05f98a6b7b343c5d7dcc682eacbd6cb54064f68e8fc20b029b5fe4144e22df1132ba4d35c39e07f4402b6bdd0a8549bd724550bfb4b7b	\\x1686737667e86c28a85d075e13000d30b86e6c6ad005121c8cd735ae341fdca2446c522f70bf43dffbe37fe9b952378f2f53a2460aa93cdbad08249526f5b6bf0c8108ba1d47518e9bd8f6bdf30bc43f7e9c32f341f4814f6cfa38d84a40038c6a4c639bd8566f0e06691893ad20c9f9b570d0aa7beb2c57260d2356dd2d70f2	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x88a5fd24e850e424a8df7294106b1f7adae30243a2150f52a26542a4590092424e2e04a0993e99236ea81a9dd7ad46dcdb114b0846563dafd7dde96e9fb0180e	1577746819000000	1	2000000
10	\\x3d6fd06c12a5b6dc367b7c380c297030c50895dc8d2300677cfade916c3c94cdd25d0258d20c6645a5aef8647c701f0370c8451bf8dab59f216824baecdfb15e	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x88156e6c627a566f4dbc8e0fc12dadd40f6843c66280938bf01de9df981cccbba0ee1f7e441fad5a2332be0dbe4e723535d7c789acd301cb1b48032e5e4f898194ece1e21c1224882833e069cdf0eef246c54a2038147fb8b8fda4a042cff292ed78ae9c950ab2cb8075733e8c726a31dc2e76bcbeb96a506bfc7ff6f71f5b6e	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x2768f07b03bb90c347f1de6b19ff934532417098468d58803da04f6960226c11272a956687e0c3f3af6af11c580a8bd29f1bccd10ce9bca1a26ece67d7d4ec09	1577746819000000	0	11000000
11	\\x32a921a22b6444d384de8730c2332274ba253acf4d227670c15e3477a88039fb6ebf5b37180bf5022a9a9cb57d7c058edc0b3d1e0be0042e4582374d8f925403	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x06a6b90f7f16dab1d3fa9ea8c2cfbed24ba27af43f518e0fdd6df9fd94e153aec310eec4034908833d0402e9c8d910edd0850ba32c32b3297c795a3b20aca96b945ed20c39673257e34819f7b08fdbf5a0ce593b47acf5eb6d8c69dfd4910a6d1927a5c8f1a425331fb2f39d66458251335644b0e6ac0df478833bba75543eb0	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x39228a8660fa7b8008fdda378a215d417a1f734f477a214e1a7fedf86e7145502be8fb871631ea1ac78211677fac1b01e63d6b69478d0d77a54b78697d26cb02	1577746819000000	0	11000000
12	\\xad3132b094768b3d1c3d157a28a07059f602b3cd5965cef0cad74e829a64687fca6de193a0e7a592d6b88ee1d6ddd2387a10b0654bffadf575aaaa435f3de8db	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x320ebb8da0b9049b3c21106695b5ae1af89af1ac2792c9f793aa5ed29713f94d73847740c2a188ac9650472f82d0c1251d123049c45ee1377c9dce233bd2594698f971afd7431a24f111ec58916906f3c9ec8d5e7d579f1d95e622837da0e671e7aa974df44a16a8e01980aa309087186b26bdad0e94dc26f810e1de5000a782	\\xb1717b5d4e6c87dfcbc1ebc9a53b5a1b0d81bd632a0d808ffb1fe64b9348a515	\\x25b0970f6702918ab4a37be7d76abc17caf8c8d06703c712dde5ab4fe9d712b43333054b472c0581f0045f59b81fb79ce2fb15b762b126424145450f8e98ef0d	1577746819000000	0	11000000
13	\\xd52a75fdc910c46a54059ccea2b72ab4bb8eaeb37a6d7c262cb245e2b6218407666bda66377631f8e3da3e1e88c00dcc7b14e9bf8afeb2eb045fe96f8eb06e74	\\x762d33943a67beffa523d57266fa2a18ddd1d4fb4b4868813ab4f6c93985feebfe232964f23db1b18f6e1f7b39be4e7b58b951833cf6554d47ba33c83d89010f	\\x8d3801a5fd12ec2a0c0ec362cab26dfdc194ecc69b42e548a5508ef44791ed0ff70da154f5ff5bbed16e01f8826463a9263ba4effb9e8a99794179252b224053d242de280a296ee3b1faf739ceedae6ae7f8ce62c6a67b65df3e0d1f5e720c59f38f9121157b35ce6b6364bc3466d507a8ea9dd07c1206b9a845ba2303ca09d1	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x80fb9d969143b4d83493c2affbe4fe7c76d9d212f4ce1b317e0c5b251fc43747f00b553301c00d55285d4391f155e9e742322c19c6b4483e8c7999e4829cd30a	1577746821000000	10	1000000
14	\\x8d70bbe0c557a8b74fb3c3af77d98c1366b40885a920c7497405daedae9e8d28cfb37e853dec8a53c5903c10b5be21ebda2f85e209362fcefc4a80531e00839f	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x66af7150edd8db8edf173debf4b5638841e0acb4f9393026d7ba7416ee38af62fc893a4e597ad4964d3fa8b707e0bf69f194afedbedfdcf49a250474b18f744e39141dc7c332e16cad5eab9c60685e1107c05036c669895917cc46615cbfdb1e8c70566c159028f744143628278b2d607672bda033e7f1b265428f882bbc63af	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x5b477ca430ca7277df6d665823190c70ef573a5dd3364548045e0886d0c3d3859004c3cb67a76e594f1a01794450b382009e139ab9024ba2caa24c114f719405	1577746821000000	0	11000000
15	\\x0079da73149ef61afd6dd4a6b19b8aba9423f92dc12e286bb736442558176ef9fca1082b098e5dc3da10c68394be67dd16e01ad6cafac647d604b6d71cb2b42b	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x22afaf94a9c39b7f42e6ff5c3eebe5635f4c08f60ca875c0e305d8b29f91bc9f16f9dbd5ddb28beea2dbe6190a104c31c8419c94006b52dc4397653c9a52c421b0214b1d0c9cad3f1f0769aac45d91db4dfa867d93b5a8f8b9f41368407d2715c9c3cd9042951ecf9354ef0be9fff267f9b4c62150499a53c56099b8ea0ee9b5	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x7ab26a46d1721c30b107df4e482556edecbd9e6b9aa02f64755c67f27897bf5c782deeb2f760b7342de6ddcd6ad6d322c80fdd02389d490d144e7929e74d7106	1577746821000000	0	11000000
16	\\x6eadbceb0dbe64bb8246d08dcaf6a17fa10bdcae831d9fe71bfcd466c843aafa07041f4cd80550fc49c9d2a9b8816051e42425858b3c65fdbcfd9ddb6a18ef09	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x360df8c4ec0279b689b5610f3a18f0757bccb14a4e97e0e21a3605563eeca1595ade451f058a587d2156fa649c6f9548c43fc1a4762eb1f910ff249b65e5decb1a0d341cdcbab496e9ec1496368368f27eea12a1a46e7dc3b5b08b904107dacdc6a001b201910047cfab303b4f1979eb6c76dd0101788e674993dae6156e83c0	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x258a7ff001152d9da3421139059bfb24efd640b14a9bd3adeb20e580828e8cc9e65cca5a0093a842b0e0c6547184981993cb3fad19bdd3c080da7968d507d104	1577746821000000	0	11000000
17	\\x87697bf3b27727abb48a7b8de275126583755987c41a44b1b890acd059a5c26e132a843d3d554138e4e254fed2b2a20c72e07e54b86d0ee7d64ff2f857aa03e9	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x95a8f8230d8121ef427418129f1bd142c0beff77a01782464e83014a0efaa027e11115c83245dcc02af63601c0bf4f3d96959a4bc7ffc14156e4f290426f67cd028bfbd66e7c5b80eaa93ea5af3dcf2891c98fffb403e26d00cbb37206d7026d7419c965069ba3ea9045c5ba8eac10a769d1a89351c2442e09085545d7b1e642	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\xc638b8a1b57f58776fbad65236d02176158311e089a7f640506d7e0ea7b25978e34a40ddccbd25be715da099c2eb45b7df2034a14548b0d4e3794d17ad6ff803	1577746821000000	0	11000000
18	\\x4daf884b85e81d0e7277a8bf73ea27c10dc002ac32da2936ca7d364a5c144fb3810549248c2c4482f6670bb4397f66323add278e8361c38176d035ca7c408413	\\x661b14c509048ec3694fe0329446689320b932778770f7f0027b67b69ca354c225c258fa82f624b782df0d8f72768e42633dd43dcd9664d124e864e5563d4e36	\\x384a713ec71417a1d10bf046ba31a9d1ebc17d88eacad988f32b9fd35b49e0054ef37acc73dab3f62b3cbeb36bc316e067cbed248dabeee6abb1c23fd3f2a1f3e8718e8850f3d01f6f74df8f0f98c788bfea3ca917dd0803665481fa97a8f3c50f43afc61eed8e664955e9b159dbab052c567b2c0375ca4371f6a0d710713660	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x4a93713e841945d4ab1cc13ada42719baafeba7f3dda25fe7386012d6d2d7212ac68fa056c96359d2dd9517aba5fe7feb7880ebde4f20ba9c3be27fb4551190c	1577746821000000	2	3000000
19	\\x194b74a28900b6e6c2f2d73fb26205f448d4850894c1ac9c801d9bdfe94fac439fa803f9b8a905443ad6ace84aeab93726bd9d3478bbf2b528d8562faced16f3	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x135081a6a3788952b034de59ce77c080ce8ae5ab345465ee774e13a13fd4f1abd4bb261a39ce159efda6eef04c1c858b1fc4b2806304e07da27b52d364d84bf155e93337ee25adfe10de0b70301328f148c49a6aa46ec86f48c7ca274cd6aa38004edbc01b5b6c9cda795baa655771375905f691e97785bf328fd734cbc858a4	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x30fb2eea1bfe04fdf79af90db535c92d92a152c6cdd2a70262ffd4d1de9cf42cb1131de23f398c2d7008d40d57cdead2a28904209bf5fbbc7bf35a0b599ef10b	1577746821000000	0	11000000
20	\\xa76a561cb94aa481fda77df7651570a434ca8bad19990e187578d5dbd7bc90b340e996e621ee2e7c0c2608ec4dc1ce09b604adc58f91a06599127079bc7cf0d9	\\x93a4d6fcdcc731fa97d39c1ef135c76fb597e8fcd5555b606064a53ed91f0bc89dd0dc30a97f0e93f21907747e9859076e59fb0c22a96154fe1cec7395b1730a	\\x1f32eea969e7aec459442e30e3c681e593144344f7fef303bf617d1001362d9911a2344d217d5bcc9b59c6fbf61c187837c3eb473603c63a72f6fdc37e3d00a679ef6d91499aabad658a1b0a1dae27219ab1aa3e30534e67c1afa20bcc19788733c0fc0da577cb015a2cc4a7178aaa53b9983ba87db7826ce197b4b633b38984	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x8928e98a7d68eb5a4d001b1546fed3fac4813ef0b6649697b2d45c28f578839d2df7e7f7560330fca2fb2e19e4c48fc5352351751418e92d5c7925a6f0346c0b	1577746821000000	5	1000000
21	\\x87d8d64c5a47d11922cd48dd1c5b4ff6cb48dba74a6813084e9e892ecf03a0557bb8486710c2a202e69553df6fdb9e6efecc5f7714b4632c0f1e65b1289a40ef	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x680fa4a73cfdf29326061730a3eb370a357ea0d0912ae9142c139b5c9fc8067c68acbb70ae18c099c2d28b56ed1e45e443d9c97553853ec9c27de807f78da95d634f9889c2fa78bc1890049669fc62123cbbb1bb7d210cb7db6c34a41120be8015f4810e89e21f192a63af9b195bb4f2660d57a4042e46e4b9f815b50ca99fae	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x424c485a1d96ea7d32c930c027048cbe0160e3ee12a72341d695d942303f9c5327fe46b2b1065faf7517c8eada5febb7d360450b64ad033ca1cf344cb6ee260a	1577746821000000	0	2000000
22	\\xfb8c8cc15919414de57b100ff83a65e86315dbc71afd70b4519f05a3b7a115c6c61270da7da2e282a4c2ea4c02ba21648c3fe478cb94f119888166f7aa4009f6	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x6d4f7637d14b189097ecd2b9b0c54dfbffb59d44c0f83658fd4969c9adeda0977273a84735be8c5c4ba7e4d951862793139c3d3f11cfc4ea93ae0cf992243339b352d015105802d60d29da4b7760794c0aa303f76efc127c465a2855c9ff68b3a0a00f564338f0d6391e4bac18be1cd38596d010f01f13e21c9afd17882259d9	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\xc35124204e87c0fca54d7940c6de839620417684d74fa763fd59b831aa8170394e9cfb7023e890861782951c854c90a6c9ace777e32e54e877905a7a3675640a	1577746821000000	0	11000000
23	\\x6333f75dbd3199a653ec73a007d92dad2ac07eff48736d71a118f490979d1a8c4f1b79271afa79d4bf0131c73ae22b8ef5cbadbe99ffb66c13e2dbe789f5aae3	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\x4ad3156985898d3606d95f45ba48cb3f1f01e9efb74a3c5607831486e5c7a255c9f566b2b1164bb54726a637c40ee9c99232a6e9c7d3bbca55c197c31605fe1348585b52a8a576c6dd8a37a33549b958f568a625ce66229a734ae3f9ac7aaeec529e5ec827ea229cfbf5de83f912a9125bd43073ed996cf462e1f0261d6db5aa	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\xdabf63407e93858217113b9780531286e62b45c097c639794a5f0bb56e82f39fbd89d09ca600dde76d4ed5ce3c753837036d3a333bd36a7ac8201aef2b13200e	1577746821000000	0	11000000
24	\\xa1f04619a4c8a7cdbb08f8e66422b09bb382db6a651e8e8ee17b8166e03cf4d7f4cc7d2b23ae586e5d6c25e42fafc473243db10434bca11a95235141f79249dc	\\x23730a2b035f77af5f0a49ac10f4f81955c87ef796344dadcf29b6ae86a64e180d400ccfe6b5abce792fc6ead7482d0df61f60525da561f05d697c8b61ed9d4a	\\xcb7ad5d5918139e2128ccf202c6ad4be9d03ca224f7e0b0c023060b92b8e824a40226ee0b5b13a9ae604af802297e13a1c04fc903970f75b5296b2e4e990d035e8acf5bcb4ee247c9630c13f2872d275265be460c31d95b5a9d796e952153c8db2071188268d0fed3a6e7578f193770ab1445444884d9e7b465e34e31c68408c	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\xcc34c60a30578a020587eafb9a98510de7e98891260d6a88b47b7eb13a3ab419249cd54c76277246ed9599992f3ac22eb42b8d4913b3a1d5e11a70d68a8cf90e	1577746821000000	0	11000000
25	\\x92c2f39425c23d0d748a24cdf22529996ae71e49bdcfa82ca69f4d8df9884ac442236764a0ef879f9195b7338e4adbed0964907a5d40c0564a986639849cdf1e	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x271269f176a9701192d190f1613825acc678df8fcc552e109ed378b39ca98ecfc691ba3b3013fb23dd9a25e3908413b03bc239c1a3536ca922424afca9bdbd3d11ffcb3900eae1542e3881ebb07a2cb2d722310c55b19e279310fe2015e2755440addec20e77a4b32289f6b94a22f28de3a115fced1f080d06bdd4a96e1ad943	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x34bcc38152d419d12e075d962b25ed0f7a5df2ef12793ddbfe56c1f4d672aa3246bbe70b617258b7c796ec9a027a0049fe86b7d44b8c94248703e87760909005	1577746821000000	0	2000000
26	\\xeb0ccf61a11b37b2ef598ebdfb1704f8414c87fe928ee350793f29d4697bd86c5d59c25bdbbce0c5a2e10b4916163a12ddfd474d90d45a4ca60eedd4962daf0b	\\xe8a92979f36a32ba4e70159b704ea626a8bab1f1ede0eb3355f4d0830facc9f192e55fda1b988debd352cde3df2f5d68f923dc97738f851245b9e9db3e9a3691	\\x665f4782a3fb9b87061d61f7ac16cdcfe7ccf6f7d58dffbf0f80b57746f3d8942528fb340144b52438d35b884c4eca4cc8d2886afa8597d9d7760df0aadd53f25e4c6f2dd0178593ebb7bcb5165d68737161d4ac86980dfeeaa7e48f4681a5ccd21f103d744ce8dc7781a39a08e2174b8d8250e7b7b694193ff431d2302d8411	\\x40e02e2e9cd45cab42964a1363987c1362955ec26fec08d87103d5832fdc8c2b	\\x41f7bb623d33f4ebaa436886e97461bbe9cc282e4ff509360d3f8740914eb5a11d80848790c623cfd4cd29b309e8838c2c1721f349524b70bcda30d090ae310d	1577746821000000	0	2000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 3, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 3, true);


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

