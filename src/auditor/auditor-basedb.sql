--
-- PostgreSQL database dump
--

-- Dumped from database version 12.1
-- Dumped by pg_dump version 12.1

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
auditor-0001	2020-01-17 22:59:53.803908+01	dold	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-01-17 23:00:03.929016+01	f	11	1
2	TESTKUDOS:10	FYP39XA3YFRCDD4SWVNNBF8DTPVJVWK8BAG1YVY1Y9PT5PQ8CY1G	2020-01-17 23:00:04.050734+01	f	2	11
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
\\x287d8be15c450bebefddda4a303188df4bfe7bbf51f7872149325cdeecbbaffb05810ab25b1673d0536eb5028102052e6ecf77c85b89c1ed7d037f965437280d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1579903184000000	1642370384000000	1673906384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b92ae9b80e2beee0f317c20a471d430ae0b0a8b9d4f75e51dafce9b41f194d6659964ff3e96867d6c18ee0b51b28b98e479f28b05f975edca189b85e8e5ffa3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579902884000000	1580507684000000	1642974884000000	1674510884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f6cd1e5d8a7d1b929441334a6b22ae9dce8cc77d3581f4b1eaea7b209d80821841cd190ae2d911eafad4df12e765b41e33f24fddd06ceef5e780cc6035074cb	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1580507384000000	1581112184000000	1643579384000000	1675115384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe2476d2cd60ee81f68ae0e50c50c28a357c0e2dc0c82d2dfea0135486b08a7e9d238556fa727a5cef17a78869a7320b57c2a1adf209b211bc469ce5db562e365	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581111884000000	1581716684000000	1644183884000000	1675719884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e267eb62e76c71936846f1a4b789a556c1cccb27997df621983b9c5b8418e13c667e590398a74af0eef7e1cc925207005b789091832381b95b6008dc71d9863	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581716384000000	1582321184000000	1644788384000000	1676324384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc2e366fee5ad9726d4c7fcafc64db2867922a562e7097c7f1ebd69b2ba32db0a649a809bf2e64c9c5c67d0df8db89a59133280409a8b1f5252241b54a9eb6bf	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582320884000000	1582925684000000	1645392884000000	1676928884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4ffd1f257c28ec0392c8b5be96be6a6ec73203a69ee15011c96cbbe7a9685674eabdcc93dfe8c63eeb1907f4ade6ca9089babaac2d084054a50475f8de1e3b12	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582925384000000	1583530184000000	1645997384000000	1677533384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaed3265f8da1b35aaa9651cd4246458db4ec1b7b1d164931b2893648a26044d2c9c309b7fdb1673cb74cd8178de22676a274b4c12e2bc02314726fec93dc1ae3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1583529884000000	1584134684000000	1646601884000000	1678137884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x279aabdbb787c48d4d7ce1906d1694d05635c7d0617ebc796f14dcd8f41109c569e11e1aa74c38f3cb64fdbf5cd59bddd1908fd72794b146253f09c3afd40a77	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584134384000000	1584739184000000	1647206384000000	1678742384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x542d40150f7ecf49ffaadb54082ca1940f6a4c8c5368e8428adcc30123b6db25a9d9299ff70d1248257c9da565aa4e2dda7794a719ab116dcb48f7b417d6b67d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584738884000000	1585343684000000	1647810884000000	1679346884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1bae01da7217f0444381adf24da4b9cd03fe4fdf305cb19497e82fc1c572261c182afb6508e5b3452528fee22edef26ef91b68fdabf0e9a2a24c2dc7634f95c0	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585343384000000	1585948184000000	1648415384000000	1679951384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7825a984372b8c92da4990775c8ad2ac59731dc8c47907a33326d2a388ce0a90dd545f19128c742ed81e15073a5c88ea0b549846c90d4d93b1c1c8091a1abbd1	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585947884000000	1586552684000000	1649019884000000	1680555884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa842423c5656a496b8d20cce7d649adfe4498e2e2ef69530ded53a2aa974399519cfbe34f6e1a834bc692b9445666cdde1f2b834456206ad1acf247c295fbb95	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1586552384000000	1587157184000000	1649624384000000	1681160384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9cdfeaefa28a341c38cd3d18006e5cd5fd0e074d078731ef0cee73ac578e696465670b61815b56672727b135b831359201937be95dba4cf047d9ebc6a7a8644	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587156884000000	1587761684000000	1650228884000000	1681764884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd4d3fe1ec4dc9c6fc15bc79ac87646a864d5c608eca5973fbb2bfe3c603002e1eaffd139fc3625d16dc1c22391e117e5ef28afb5120393de813f0d7ac09c709b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587761384000000	1588366184000000	1650833384000000	1682369384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1d226594d693b3a56fef86270fb74965bf755761eaaeff399884aaac413f463171080075e2877c299472b3165e240a029c16de452d5455843c678372bc82e13	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588365884000000	1588970684000000	1651437884000000	1682973884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9a2f31dd9f8720ad4fd541aaf82a9d4a8ad1f0d2d653095ed829171e870664fb13faaf1907acb521ff98115a1233bd1d9632c50ff407640d1bd640bbc366691	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588970384000000	1589575184000000	1652042384000000	1683578384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d1c1c04bd6756609dd44974a56bf695ba0474188111519ee85d085e9773233a23d7f9dd39efedc2fbe43de8ace1fbce98e9afc22c47de87feae9bbbf7641a26	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1589574884000000	1590179684000000	1652646884000000	1684182884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ca6d6b23bb8a6c2b3a782e015b8ed592ac00456f270310f53e40484aa86f810d6d90401224c5b6f530e9f222a1a0a93638966ce04d1b761bc31eb8cdc3f7111	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590179384000000	1590784184000000	1653251384000000	1684787384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x601ea53f309660d9d64d31c501a14c366f005a7af97051a3834ca86d4bdb7afc30a5ba44443da874842d60240d0c68a7c5c842e9499acbe8a0b2070f66bb78ac	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590783884000000	1591388684000000	1653855884000000	1685391884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8fe7a6869788f8d8d013fc83a88eabeafa8a1324c40fb1906f7d53487646e3019adda8fa3134dde8db0227f47d234f3a5c84778381688852bb61a22d6978d20	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591388384000000	1591993184000000	1654460384000000	1685996384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x56696dc603b35245b51b231cb6bb4c7b85fba768a5ec2bc1fa9a628603fff2a82f3fc444379b3ee678eb573ceb5fa1572904c2ed6e1a7b0754a17d74fac3fea3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591992884000000	1592597684000000	1655064884000000	1686600884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6480e40ebfb8665683dcd5a79ded07e226db539bb261b4ce86aad61d45cd1f17d60ac119d214bcb0787eaf80597eabae97820968d82a67fa6e15541987a908f9	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1592597384000000	1593202184000000	1655669384000000	1687205384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c9f7af48dd7e601c001f6c8857a4229ffde15991520b286235dbf18cf01bfbd9c8bcc0c1050f710caf2e1e05f24f75710e19446da9277c2e4135e8ef3f5b776	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593201884000000	1593806684000000	1656273884000000	1687809884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33e8b27ca53bb3d0c2373cf9752990e5a47fd1fc0b075dc064f0f07c46ef5d3ef95176d4e47bcffbb166099d52bf849c4a59ff8606edb7c9ad743f9fd7d15881	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593806384000000	1594411184000000	1656878384000000	1688414384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f3cdf085be682f218b1163f6b942c0ba836b007769cd972d71d21739c6a954918d98b47774729cc2b20591cd5560bb26ba2f882bd073984b8f827e3c898c112	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1594410884000000	1595015684000000	1657482884000000	1689018884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d684abf15b8c8c8fe8cca4e8fc9d8ddc96dc1ff0bf3952443d71047c2e29d99e1a6ef4ccaf3e0f274cae151698573d55f30f4a623a36e6b44336b472f042385	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595015384000000	1595620184000000	1658087384000000	1689623384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a7aa85f8a9b016c97258c764de2a0797d36a3a4daba88683d9e76c742aaa0edd2cb662e07c6e888dffa4f242cac537b1d187d1f12ff1792708a2bbde97cdab3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595619884000000	1596224684000000	1658691884000000	1690227884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x872cc1a6eefba8aef82998d09377b3f52fc1d08b334d7de9e74a2889fd41bd66bbc09f4667af779f30e98fbea30b1a12527a2d02952605120b47fe16a5d72764	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596224384000000	1596829184000000	1659296384000000	1690832384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x79f096b4e966289626eadd991886afb6ffbd89c59cef60c5ca6cc1ed14a419f225194a9e4b76b4c4269b83c907d1173f97faafaa2199b5dcda02841594164c24	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596828884000000	1597433684000000	1659900884000000	1691436884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf0696d18c01cfd6d551431d7d95f0e15e5a64c3e7b02edf56dfb032679d042be0c15db4c460e94a95d0cd4c927c9edfb062780dd8d6d48537da874204c438145	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1597433384000000	1598038184000000	1660505384000000	1692041384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5e59e5da83b0e57fe11b7213c44bd5ee11d23d8f6dd774f25adf2cb57283df903eaa0552a54e78c72a1207a669bc0ba8bf0c24d6b6b008f7cc757497dcc888f2	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598037884000000	1598642684000000	1661109884000000	1692645884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xda12bd369a5a6d4b4d21fa9094202d1ef6991ee688931d6f7ca68608b2480a3bd7e06c480874aa58c0ca3454ec8503e80ba6f71428edd79938301e1beadb3de7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598642384000000	1599247184000000	1661714384000000	1693250384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01bf094c74f50f7d6ba8e68eb6742916f83e6417762ae1d7e3db81f2c5af22f1640b8807b31311655dc90826d946198cce1745650dfba54e1b50f90af18feac6	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1579903184000000	1642370384000000	1673906384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4b2356f67298901f5b1d9f9f724adf3148fac35b95540fe71a7c3a5a0057fa95622db502126298d93a3d5864ab4bac09d293beec3d7dbbdb6ae4e31fd1dde93d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579902884000000	1580507684000000	1642974884000000	1674510884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6a9bf0765ca4fd2f4fbcdb51847d99af39501c3766ee7c5348e41be4d21a941d1a0cb5a0efaee09eb114c38da75574c88d74d4babdee13f754e478a4e2e92831	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1580507384000000	1581112184000000	1643579384000000	1675115384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa02baaa2dc5e2d61b83bc60ebac9c61426c7262f97ec4fd6c2f608cd6b89c70ef756d34c816563b7da39949f33cc43fd7fb6f3d56b82db1ef98b01e418316d36	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581111884000000	1581716684000000	1644183884000000	1675719884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1a8d2021711afda69a8264a696909181d029c609193d791d02c174a4f18f1279f2eecafc0fa7e69627fc2bd2459498d2cb870b03ff8e3c8d3c04ad79765b40c0	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581716384000000	1582321184000000	1644788384000000	1676324384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x75909a45d565cdfb083eeb0ce8fe3167cdce54c39cde9ebf8f68f62d790a4e2f266ec60a660feec1bb01e24d34791557c71129b62f6067140fe25cb7ce78c85c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582320884000000	1582925684000000	1645392884000000	1676928884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9d8c8e70a88abac7d1438379099a29e3aac3ebf06f36d53a108ce3230f889c5178efd7a715d4fcff2810aebc6d54e2f2b55a597dd2af00d9ebc123624e09022b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582925384000000	1583530184000000	1645997384000000	1677533384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3e9d50e8bdc34a862579359122adbfe2d2baf4bb15039beb179a3406bf7ac18b7d1f3e11f0c343e25985bc8399846eae523dcad78bf552cb54ee46771d11694a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1583529884000000	1584134684000000	1646601884000000	1678137884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7c01a3a5afb638f65c799a5b2d5184136a5e7ff1eb525a828ecff721951fc68d9e2c9bc68af6fecf7effe62297b8565392706c995e5debb82cd8349b6d8b7e64	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584134384000000	1584739184000000	1647206384000000	1678742384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x617f1eb73d8b89504da639bb12ccc726f4b8afecfa0f6a9bebd1af8f0aeabad66471b4870ae64ec21ca09bb51bf3d34a3473e2551c5e249ae3381131f1ae84da	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584738884000000	1585343684000000	1647810884000000	1679346884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd4cfac969027e5c7f17c74b69915bd2abee27ab5da6a2b99abe421f339c4f771b390d7f78d7d7d8a6b9fa9176eb349821e736e05559416b0db053941ad948a68	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585343384000000	1585948184000000	1648415384000000	1679951384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x734ef562b6b10f2c296dec0edc90f37e087536d02f7b3fc69712f4ed421ab68236f7f6f87a977e3cabd43c00d56dfa94683b1f3bc5815367d08f47dea85d9844	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585947884000000	1586552684000000	1649019884000000	1680555884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa963339b2b25b26d4eca5124adc27d4d029a778c505600dd13e772128ecebf9f42bdc9af6708c7bd73e988a02c9a7ec0a14cbbe64c16905c273d1b8432cd88de	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1586552384000000	1587157184000000	1649624384000000	1681160384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x482fbafeb77383cc32e8771042265c0f4493dfcbd7bef0c83c77c6c868226ef44fcdadd027f8edaacde85904a8e4820dac662aacdf9b493afabace000b27045b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587156884000000	1587761684000000	1650228884000000	1681764884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe44da114f9074050b4fd3215b47a3a37b430e6ce3446fdb4f20d3327b7d6b293d97dc51aeee370a8446206c1aca1ba7176b2833b8eebf226bb238ac615a7bb72	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587761384000000	1588366184000000	1650833384000000	1682369384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x872b7e7748d08e73881db2f5bf7d90f6a4f6b27ed5953105e4abbc09b827678e826ed160c14e673049327addd970185847669597435a3dd19dc47550b4e26f84	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588365884000000	1588970684000000	1651437884000000	1682973884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6f5c103b430e19938e6628eb9f4a3b4c0ac9439365b0d386af559e8d72ec23dff4ce22d4dfb0a0931335bd5fd6a3a3de22115c57700334c84b5380acaa48d460	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588970384000000	1589575184000000	1652042384000000	1683578384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb0eca1948528289428b8855954701d2127b5463e4e990cc44fc3689ca0042fab968f4bab3c79ed08b4a062ab95c1ffeae300de89c75c8d3d7e264ccefe6564fd	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1589574884000000	1590179684000000	1652646884000000	1684182884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x241c40f2893367d24f43f361785624e345a2be367fcc604adf0e159332af30dce24b16e59810eddae87ebee72d87a90b8b661abd3e3edcf11346d7dc46610296	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590179384000000	1590784184000000	1653251384000000	1684787384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1b13db5c365e0cfb14544140874ffffe0c52d4b15d5f213ee230cf23f51b761162555f65d89375404f03f5ff1bf81372af3c46b0143cea86a9d7318716bb5b79	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590783884000000	1591388684000000	1653855884000000	1685391884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6000d229fa362937687c8b157820ea407956b8fce2d9ce8f42814bc84f5ddf1fcd1bd7c16ec9e7410f5677dfbc7bb693dfc202c8d89347591bb0a1124d3297a8	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591388384000000	1591993184000000	1654460384000000	1685996384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xde5df5c110902ba840249b68459a2de737ca14f7fccd2b76d14da0835e382a8cd2e8cae2186aaa9fa50d71cb15cae126eb09dcfe26975ffe917ae9286d12a4ce	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591992884000000	1592597684000000	1655064884000000	1686600884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe38d0c006f6c9213565f6f2f43adc190e53fbe2ca5652e0c4bc9c48aaca202103fa7ab79a67153c474e22ad99831a169585e4944063a54e4d886d9c24d570936	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1592597384000000	1593202184000000	1655669384000000	1687205384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xecbf9ee3fb640624478a5e1831c8a5e11f03df95cc332f2c5d8916f428bb7008f24501f5a3ca19d06ff7e7592ec3129c37ff65c1e4099abe24f878a772d56d60	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593201884000000	1593806684000000	1656273884000000	1687809884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf4811e2089541bd3d4f20ef85fc7fe5a2db53083dfe13d4fdac02fe22bbcedc137dba88aa4c5ff667ccb6e3a7aa7ff5a78e9bc4868704e07a9ec85e64a5203c7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593806384000000	1594411184000000	1656878384000000	1688414384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x61f6e71cfe3512c02f015b0a5b7fc4d19cb2c468bce35ff2e3e2db6b5949747c65b372554dc299f2926741228ff8124f3e0ccc5009f130da6b68c4a37fd4d69c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1594410884000000	1595015684000000	1657482884000000	1689018884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x77ed5bfafb4aebaf70e61e9e826995064842e848b71b52babca019e00ddbbb7867f74a3a134b7ee02b220731be7ee06beacd35d094dd20166e5f72186f5dde1c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595015384000000	1595620184000000	1658087384000000	1689623384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x07ead3161f64c7b6434bf6ddbb44491dc40a0af36612c3874d3e748e789caa0fc8afabb617f3b26d3d2f362e41a48e7b4a1c307c4686a91947b2f8778a6ad832	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595619884000000	1596224684000000	1658691884000000	1690227884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfa079c76264252e1f3427269c97b1651435bc8fe4615134baf868d6176da62e28520bfa99f78fec620fd88490ba0f8b4c796084a2a938e5a67baf9b40df7fef4	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596224384000000	1596829184000000	1659296384000000	1690832384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe7494304f99701ebd994a9bca5e39fd4bab6725d95c2f2a1b46f4586a6be1382678b33bb15a288ce4ea08d62497f67d92413da6945a200676ff5ca2e89f16d43	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596828884000000	1597433684000000	1659900884000000	1691436884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x45ad4fc383d99fbe220d04125afdd01432468e81a5845c1fe941ea2e44767bd81b18229182c2aa6da2c6e89a11801e2cfa5e55afa28893b0615750a62198f167	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1597433384000000	1598038184000000	1660505384000000	1692041384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xec5078c30c8df11cf622888ab4d048f4c818f9f58fb24caa984a17dcfde08385d3f0ff21c230b7d3ab39efb2b9abcc53eca41846dde47571304a6e5131b1d0ad	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598037884000000	1598642684000000	1661109884000000	1692645884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1edf19b0f04c515a374010e36ec59112b576431bb10e9372d67d405347b51e88e9df35746522ccc53d993666ddbc2d813787c488b33f0469e8029e73f1aaa857	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598642384000000	1599247184000000	1661714384000000	1693250384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8a3342a13e5b751fd9eca8b0eed42df31724c15c9d2ccb318762088eff1f627fff7acdcb5df0a2139fb63c7769a8bbd0f935219169733acde1d9fcc2af9825ae	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1579903184000000	1642370384000000	1673906384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5131d1b4e61709a198ac8c98954bc6b26ec1d87fdb02737009c21c4af077ff092d9f336d8432a64dec108b52381ccc10a02604beb71fd54e63fdd35cff79f36	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579902884000000	1580507684000000	1642974884000000	1674510884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0de5ea6a4dea6821f7f5260d322d97a0d4323caf18eb9b8729cfaa06ac4b8cb8623b3f11f3ec4c27f886bcba1a3d1014ec4216c015f26c2a2e34dadc320d2114	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1580507384000000	1581112184000000	1643579384000000	1675115384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x509713f433e39f74857a0d334a185180c8a3e059002b78324beb4a4cf23ebcccaead962c4063dc79ad2e5c19f785d7ad985c178580cc354c2fb42a63f5a93bd2	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581111884000000	1581716684000000	1644183884000000	1675719884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x07aacbe96b8567a59a271c4e0d1ff901887daf0366ef29ef5f51e405b65d4f0d0d697f4fa992bbca51f3b8dea18cf3aa9a323c3232ee227766f2481a8e79afcf	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581716384000000	1582321184000000	1644788384000000	1676324384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbba3e12121671e64af974019a6b2fc3b0641023f37ee5f5099c8d00ad2cbacc6b0c4c513162fd7fae20d66eb596167861f34fecc8d2991a6b5fbcb8a9d339950	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582320884000000	1582925684000000	1645392884000000	1676928884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef0617ec7e53b9b96a5045c4237a70679f0aff8d72da23bfab77f686f1d3b8afcdf3bdb78274f52b9634a0bf70ee7cdb6196224b9e69a0213f2c78a670eddae1	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582925384000000	1583530184000000	1645997384000000	1677533384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd3f578c47b8d82826e8b43f849fe85338250fd0afc779e19c9e955aafff18a20893bdfae0d6a4e663aa25a3c610319998f2693d9228f75fcc704f9f681bf0e50	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1583529884000000	1584134684000000	1646601884000000	1678137884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x08cb7cb08362ca3001978a1e3797439b58ffa103136b869de7f2834a222b99d1c34651f2e0aac1f43970867eed2fb0db583dcf643690ea30943972a17772619d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584134384000000	1584739184000000	1647206384000000	1678742384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1af765038b76b9f454541879fb90aadec7bba2bde978aa7034567fdf284bc25b9338458e6e24a8d4b750106939632ea7a600cfb8157a88d1612278e8d56460e9	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584738884000000	1585343684000000	1647810884000000	1679346884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc357eb507f2078b7167743ff4ce12c5920bdd91b051d4a70cde5ca2ac8b99f19276df63e3d03ff82e911085baffcae623c4adaea0184e54735eea4c390851069	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585343384000000	1585948184000000	1648415384000000	1679951384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7aed18357cd5b1b759444cf346bb55437797d8315247e73fedfbea223ea113af655153ab303afab06f2df237a6c1d848236a2c482f6682d6a71768be7a8e1cc9	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585947884000000	1586552684000000	1649019884000000	1680555884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc06837f9c360f1f6f54df909a41b673d9abf9457b67d54adb23f2d8d75312a391f3e795213e5c7c97048a92e4d861fb7abdf295c584c9e5469714ad0f5ef0aa2	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1586552384000000	1587157184000000	1649624384000000	1681160384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0554acd05e0aec72f10ae830041a9efa7ef86473bc17ab47b2dc5bbb9a3d4b49fd933243a7d65f0650bb3fc5a525213eb6030acf307895b688c45808784c6c23	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587156884000000	1587761684000000	1650228884000000	1681764884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c14805a019a49910e5186eb8e7a6055e9fbeaa84e1711a52bb91055ceffc2d4d472e4d19de3363326aa196243083f8eb54a2afca6b7003d7040943f216a0f38	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587761384000000	1588366184000000	1650833384000000	1682369384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x212a7ec07f78c8df1b9554b18236309e7e8dd8bdde57cc928c737d395d1527fdb78e96994d07468a25c82e2cc96b15c1649422585af344d7972770f4d1ba93ea	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588365884000000	1588970684000000	1651437884000000	1682973884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0cb1c802d30feab46771b230ba26321cffa28787ae12cffae129fdfa0b020bd76272585aab7737659818abb5a3a390be19a4600d96a0a068a7ca511ce31dc1ba	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588970384000000	1589575184000000	1652042384000000	1683578384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x855e8e37a3723691ba0dd049cfd088e952726175d3e88e7734c1a7043df7b138937b230fbe88af24da0633f14b0f3918c7188681055f64169c2f246ddc31c14a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1589574884000000	1590179684000000	1652646884000000	1684182884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x412b1bbf1eb8948bcaaf7d7e16e006fe2b30a6bfabe2db6b818026c7761f42922bc17a2537efd92e82386dd1a1ce739f73c3f096322f41aeaf4fd52e80a243c0	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590179384000000	1590784184000000	1653251384000000	1684787384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48b3ac04250fee05cbf1170d6a3271be8ad1fb98d4718b42eb1400d16c967dcd51ee6b45ccc8797d742e55bc210b6061235f5269a7119a80319f48fd90f7f09f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590783884000000	1591388684000000	1653855884000000	1685391884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe234e5b172042e7a9ea343b82d923911f64a21c11bf18eca8e845b21dae2f20fc62ca53a10e6c817a98e8bb2a02d4c68d0b4b567a267b1e6a3b0222680650cdc	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591388384000000	1591993184000000	1654460384000000	1685996384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdba99ab67f08090b124dac1aae0bc4c247f2d0ee2aae8446c28fcd87804480a52bb5b7640114be7a29711161abf23f947526cf85d378a4453094994a0b642a5f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591992884000000	1592597684000000	1655064884000000	1686600884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbcecac4169a0db7688266a71daa432c443f004ae9a278c028f8de94a770a6e6d291f83ea077a90daa75a9f48d594382278b3c57bcff4c32d03c22763441805d8	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1592597384000000	1593202184000000	1655669384000000	1687205384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bba2dd8685a908288a9d4ce1f116c68e81849acf6c84027c83e0cbfc6e5452bdc09a33f9f7f472fd30827315b662ea35cd7fc960f6f6dd701c9532517fb37ba	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593201884000000	1593806684000000	1656273884000000	1687809884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x761c501d14a55e829b8ccb306ef64bb47a5b03726fedc7e235a728422779a6fd1fc8a96b538e7f8a682536259ea074d171dfed3f363814f802f54e5cff1d484a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593806384000000	1594411184000000	1656878384000000	1688414384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f55f74f6a30bb1fd937abb6c2ec60a6ceb078904f8d3e1895f9018b8c3d1bd32880aa41b253f7f13e04928693474a2549c146f309ef16ef997b9483997f180f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1594410884000000	1595015684000000	1657482884000000	1689018884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb1cee5044fb9724c0c28168b53591ad3f98fd566aaf59c5ed1ade255d29d8401d6b512b7da47bd12622fc63e4f638340e9765cd237ebf297ae9c8df96b5d87b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595015384000000	1595620184000000	1658087384000000	1689623384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x474c10d55450ce921ae75b3053d3fcd4bcf1a1c906b20fffbba9069bda32c502c9a10a8bbdb2f12bdb5c0da31719f806aae79018ea43cea2893159f9578f7f6d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595619884000000	1596224684000000	1658691884000000	1690227884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb00785159362c488554b4657f42df0e627d03ac368c21d93124e0bf1d00d48cbae2f08d5c3a57a80521c0cedaff312baa61c52e73e8ebda7dad92954ec3b52e3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596224384000000	1596829184000000	1659296384000000	1690832384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x69396535811c03f61c39e8967e419c1efef7e703b7007efc1559909efe27ef1310ad9eff28024332c8627daccc69b6cc3adca68afd3fcf0247d5bdb6dbf6a42f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596828884000000	1597433684000000	1659900884000000	1691436884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x647b764b60a0ffb72cdb1da2ccdd9dc0244ab4fba89d7340513f63099b7268c6d9a3e153a0effac80642bfde4a4039ad832d9e226cb81d8303bbff556e57d1ac	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1597433384000000	1598038184000000	1660505384000000	1692041384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x08b070a2f0f5a7fcb6572ac4697c50b9ca0dc2191a64e50d470c58e19c83adf49adb5e971a8eb28c16a4cce835b9f075371443c00fd0864956581ccf0b3ee3e7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598037884000000	1598642684000000	1661109884000000	1692645884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8d462e116c771c5360ed1b8031c76bb5ee31d85c725047a22adc53bbb069012899852ba49e28c394043f35b01a6820db92a3c351d434fae1227c5d6812c2a1f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598642384000000	1599247184000000	1661714384000000	1693250384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xec0d34e4a035b58f36212af25dfe36290252473c0a12099782b546a0ce93e8c2e310ae63a78c9ea9a2bef3d89d893e0412c3fbac3f34af1ef4a8af36644101fa	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1579903184000000	1642370384000000	1673906384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5fdd12f9de7877e0cf98372373700b0e9e0985687968ae6db88a22d176673dcaf3555f4d122f0ead8596b49165b963493b81b046ab362796d0501f2ea521e101	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579902884000000	1580507684000000	1642974884000000	1674510884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8acb986603b90ebf9ab15c34e0b7cf942fb46fb73ba1cf875abced567d81c132463787e594d45dd74ec4f42d96d6c23a6ff8fb97df517c27a968b93cfbaa4c3b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1580507384000000	1581112184000000	1643579384000000	1675115384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x33f4987ca257861bce6c1e156889aec938d7fa4c84a2b116279271b7910c4e7d93a0e70d8e433ecc419a8545c53bc6827780616ff808a9816f52bdda14e999f0	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581111884000000	1581716684000000	1644183884000000	1675719884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23a4205696142c729d194abdc40619c75a59ee9a70b7527d622fdb09ccb01f67f14c538eefe838af5fa06f667c658ddd07472f331ef1274c05c5591901e55bbf	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581716384000000	1582321184000000	1644788384000000	1676324384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x78103460dfc20ed436f656abbea70d7b2ddeadb34f546ab5eea6f4c28453854b8d92d3166ef033ff58f7f8e9ff7d8d8d1e93ff287cf6f05d399fbd9bed8b2cce	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582320884000000	1582925684000000	1645392884000000	1676928884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x36107baeafb5c9c28d982a8f694103fa9501e33970249023db05948041a051eb85727bad693a9b99a37565ccae77722290145376ff95ed969d40e21e102dfc1f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582925384000000	1583530184000000	1645997384000000	1677533384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x563f29d03cd695486da6b34cdd7ab46bda95ef7caecc28b0da4177c9330f8db02a333fe9557a1748f7ef725606c12a945d92ea7580e10bf2d547e6eb0cba0741	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1583529884000000	1584134684000000	1646601884000000	1678137884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb04de6d7917d42969dc8a8632da23f733523e75db5aca06e930cc3629779187e990ae43681d4fe80fb28c71ed20251ba27ff42de61a1a87a6f8a81841adc4d20	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584134384000000	1584739184000000	1647206384000000	1678742384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x856ebb2e3cf4cea7c2ec053d004aff9b2080d966c64177c1c44ad811c70f06f7e46ce1d4038c01411f5fd186a65b881697dbf686be109131e1396cdada99ae0a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584738884000000	1585343684000000	1647810884000000	1679346884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9c4fac63b175a5fb4696569ac56c3c6beaf1ac02223b778fc8545b5be98d3106dd3e775b9774bca41e554e172814b59957317ae648dcbe762ac163009b1c899e	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585343384000000	1585948184000000	1648415384000000	1679951384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x89ea8a22fb9e474e807a254aa83bd2d786d396df8904954efbc5f6637ac1ca7a808739f5eb293e3a6fc30605794409a95aa274fe0f70a055b17d4129e6e89e3c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585947884000000	1586552684000000	1649019884000000	1680555884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x975963ba2d40ad90f56a356cbd0df572d7a05ff2ca15a0000fb648173c2b1dee09d51e2910dd1c9bc0c18ff139d01e4d8032bb3f096e88c0872717d79e97a23b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1586552384000000	1587157184000000	1649624384000000	1681160384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xac7549e2232258804d36adb8ae79ccf42a27772ad7d97aacb67f5565cecbd4a09a866739c6ad679b9380bba57e8d5e770c01a5d2e6b3f889a22875fa8f1be79d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587156884000000	1587761684000000	1650228884000000	1681764884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x16199c26287b5a7c5c6407ffacd9c051cc0e9fa48263fbafcf5ea29dd4b20645ebcb2b01f9f9ba02dbcbd1fec6de07282c33afce95bd94f54d14dd48e31031a8	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587761384000000	1588366184000000	1650833384000000	1682369384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0a409dbdf27eb79fb2e7a85950f26788abd9c97485012778e18d5262953898c1ab5a8ff4d0dfdf310a7114614c67a361746061313a3b652c0bbc3b2cecd4f31a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588365884000000	1588970684000000	1651437884000000	1682973884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4895b63d4f2e1f05ff9ae08ca6a47f0d59fb0653d507c7b1fb93193955a5d0a6aca093e184fa771966a8028487d1a6d675034c7f27a5e7061ec3d5ac8923411a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588970384000000	1589575184000000	1652042384000000	1683578384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa667770eb98b5eaced5c3d7c30419988321ed928bf8dd27407d9af5050faa1e6633ad31d0c26e1650239be72d9464a42e78f131ac2fe037b864b3440e0598025	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1589574884000000	1590179684000000	1652646884000000	1684182884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x10e6bb39823f3ebff8caef92a74041be2c31593911dcbbd5c1b09488d5ffabb75f46bf9072ece362f2256008b8f3e69d39423b810fe419415395c5559d306365	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590179384000000	1590784184000000	1653251384000000	1684787384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0900b6e06d52aa65c42ba9e7df514bbd66d9679e8af980b9d90081d9c028bff60660e0e52e1042b851869c1254d9a2400c9cc3af75a83f38bec9ae628b140940	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590783884000000	1591388684000000	1653855884000000	1685391884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6fee0c41c6284ddba8a75984bcb2af6eda56e1e0e261cb1eb501d4c32a3f959e9cfb8dd0d24033168ba7c103ae0eae624394f5469bf93aa6716de75cf79b35ae	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591388384000000	1591993184000000	1654460384000000	1685996384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdf708810a2fa21744ec5ccf23b0a3972e443098a1a1125dcd7f50ba217c37f2beeed67e2f271edeffa98ad8647e0a87b684486b29ec3786fe1a828c68cb89f6f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591992884000000	1592597684000000	1655064884000000	1686600884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd26d42cb70b0369c3c2f4043e26ceed7c1b392782378d1fdd583952f6e25990c510c88883c6a994d61797de4665aa047ac88f8e0b15445ee9c7c965e2d46c619	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1592597384000000	1593202184000000	1655669384000000	1687205384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe64b5f2729c912d9342be9d75458c8e7fe254ae9d8bc2d470969bc398e2b0dab914c5aacd4cd24c7082290e543109dfbbd9750e2b428173425ea069689e94878	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593201884000000	1593806684000000	1656273884000000	1687809884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x33b01c36549fcdd0a81f5894d6e87903d8d1d1c24d3e1d485c3a253bab0086b86f1fe4b33d24501bfeded7310594a46c8ec954951faa00fa6b16328728e2a280	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593806384000000	1594411184000000	1656878384000000	1688414384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x455484dac6b0bbbba98492860ff93384d8877c0c9c887932b0b5c4f69e576e7f0ca91727b6da5c863ab3bb363c473baeb5bb8c333c0ea08479ff1d5f1aeedbd4	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1594410884000000	1595015684000000	1657482884000000	1689018884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x26840566144abb0c35574ca895ae0331fd8cc43b284b98b8978987b1f06def4d063b01cfe892fc9219af2c6628cb8e8429ea9e7409260d53d1dd4c13b76fd5dd	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595015384000000	1595620184000000	1658087384000000	1689623384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4cc04f891d657158b9f01751c5d8595fa19674a83034e88c44c6334fe42f7eaaabd504e25c012caa7047b0bd3ad0b80bdca49b5503ddb54d01d81a106f960190	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595619884000000	1596224684000000	1658691884000000	1690227884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde2ef7c639d841c02d0c16cc4e8d4b1b90756ce9c6b269c8c1534b0bb7a866526f50cbf566a0b5d6ccbf5c6f616e38075a120218830a4a28ba397e14b09b9331	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596224384000000	1596829184000000	1659296384000000	1690832384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc6ec565da5a0d243877cd0abd57d9b5088f34fcba29c4caa070abeeb8f3996e3a627d95c29886cb383e28c7759647ac5931c639d05d8183ba74db345aba32da6	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596828884000000	1597433684000000	1659900884000000	1691436884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3dd1748de6b57a093f6d3ffdfb3af2419bd95513a2a32ad3ff4dfdd6229ca1c2d9f56b43289dac75b612f3cba956f6da9d46235984d31264959c99f1060483b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1597433384000000	1598038184000000	1660505384000000	1692041384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x06488e9d05388c37c479b4fc3570ca93ee0906e551a9238043e8f5b9d4f653721f6d3145c37a024ac2baec702fcdf075c21935abc9729b2d396644bd375e6a9e	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598037884000000	1598642684000000	1661109884000000	1692645884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xedfbcd5bccb18446692f17f40a06c2293a5b57c22262cc8306dc99d76be609c037232a2b2207fd03a8df6c4b97fd7ff4e8a37f86f1d4d1837e8c915fe59f0dd4	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598642384000000	1599247184000000	1661714384000000	1693250384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4861d3c7f5025254ac4f88dc2c809f8fde25916f178bea78f37c965b2d75d266520e0bf0eb67c249d5763514c677d682fc989dd4d00f22ea64beb512491553e4	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1579903184000000	1642370384000000	1673906384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9387f08e6a7464850cd38dfb04e23d468945df12c5b6aa3ce4a54e5656ddcde9b0c248d8c0a1f060ac6ff64e1e429e0ee219a598f21f6446e72a1042264b3bf5	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579902884000000	1580507684000000	1642974884000000	1674510884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95718b02e35d4d0cb308673a6460a300c15a694f57ab9d2bb47c32e58a99837853142c407c50eee7f931d7f8d1c38951a49b3d58f1349fef5a80116e537dea66	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1580507384000000	1581112184000000	1643579384000000	1675115384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcf50f84ca735f0abd43c17c0f153c090dbb4a0f5f5e83c5ead50d15edcfa5ba39db792bf65d17c9c43039e3a6a4dd1212b3a47b797c6525ee416d0e105ca6f2b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581111884000000	1581716684000000	1644183884000000	1675719884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b3be61996223f8faff95fe2d2393d486320a56242c38a7f39114d90cfaff923253ba186be45930e9ac821a8d7a4cb066c4b7f3e2c23d07d330d91b1f2fa1101	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581716384000000	1582321184000000	1644788384000000	1676324384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x383eb23a49a39c938f08968a6892dd3dcc1095b0a51ce9ed9ad48631ba45d58ddc89321b1dea276d7fc8d4c4eb6217093e2f307b5675e7bad92cf3d256ddcfa7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582320884000000	1582925684000000	1645392884000000	1676928884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfec63856e8554a5a185c8469e4d70093be88ff3d46bff2397439233feb0be6575b2eb1b805a64e4c1ee9f1be4e0bbad8a4a7f688d20526efa39880c6a84c51d5	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582925384000000	1583530184000000	1645997384000000	1677533384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x955d940e825ef4708d9ba4bac9f6ad0fe8b3967c4e901ac2e8df51474c0dcbeae4c5a7283c224763dcaadae35e31d625e754468199bf00418ea8751b33414ce2	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1583529884000000	1584134684000000	1646601884000000	1678137884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc844f163356984aa9f78678279230510ebedf13390931e6a31cf3d8803bc73ef121c07117777c69b7ef2bde387c8d520a16b26a201c6381dca375667fca0106a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584134384000000	1584739184000000	1647206384000000	1678742384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x04cbfcefb567a8071d9c9581a0f30aa1a7d6a9da8fcd9428a5686bc7e27b441c41b767dcdce8acbe7b6aacc9e9dbb8b0ce37369a00c605fb92ce23869b3cbeb2	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584738884000000	1585343684000000	1647810884000000	1679346884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6b5852878aa22d45ca919078a969002dab2c083c860768b79c49f6fb02be9ea47760bcf963a5039800ae3b242819ffaa3be760dd499d13eb3eac6308f075d6a3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585343384000000	1585948184000000	1648415384000000	1679951384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x81ac1bf3e0a6d8b15280618fa52c820092dca9b795be6a04a3327af3d738f324b5d897b3570040a8983520714c526eb32d1438918a29986c85ed2a8117fec81a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585947884000000	1586552684000000	1649019884000000	1680555884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf4ab6970beedb81cf28d66da3570df78bcf6b1ce8eb8d4324907a6c2a048f0b29886520cdfdc75c078fcde0f586df236ca3b8a87e39bec0048b105e0348a5359	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1586552384000000	1587157184000000	1649624384000000	1681160384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4058729e60b2617d5493b3e8cb28bf4200076c483145fde453c5eac7b0fad2a3e4bd0222fb6ceb7ac9350f05e8a0bcd9bee0c116ccfca62b2a93662aef03d4b3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587156884000000	1587761684000000	1650228884000000	1681764884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x79ee64a1ff3ac56d8d6203a9b99f6bdd9b84762743dc649c75e8341337f0d21432f313449bcaccfa48e9d6a90ab24f35732f44b74a5705c859ac41d8b95faef0	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587761384000000	1588366184000000	1650833384000000	1682369384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x11091de34dc7d52a18913817d7cfababaa698c2c2a79636097a63b980d4a41ff4c99108df2d5d72ee16cdce7997c356db090ab87425ae84c1993c4a1061a21f7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588365884000000	1588970684000000	1651437884000000	1682973884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x649ee095bc08d38d42db0e453ceb0f2d4f6db943244b62d05ca5660893ad8b6f2c3761173f81eefe4d3220cc65f869d05c5d6e1c0f0ef67916d2dbf84552feb1	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588970384000000	1589575184000000	1652042384000000	1683578384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x48ac50bb70446128501e16aba57628723fc84c9f5a52958f02024f32b1191844952ca7aba2671212c669a9659e83078d45872f95f3582cc47a95166c1a614917	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1589574884000000	1590179684000000	1652646884000000	1684182884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc67c2a40fb6532094e72035710d3652f8c926060678ce48cedb8f8e59b525cb2b01aa8eaeb4d5cd62f11ecac507b9fca79ab30f0a14f487d14e63c64014ceb22	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590179384000000	1590784184000000	1653251384000000	1684787384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x393e79ceebcc0a44581bff94985f625f66e349873a1e2b288e8a57eced512d46015495ff52b865806a312b58ef16ccc2d66489076dfd511d41197b6afd8186b7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590783884000000	1591388684000000	1653855884000000	1685391884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x88bd1ebd3d7653e5476aba036bf7ac35e52760dc0edb6984af3cb77abce62279f033146f94928585b086bc2709e9916b26097a0c57f73963271814e844aef5ac	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591388384000000	1591993184000000	1654460384000000	1685996384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6fb35c59aaea8aec49ad45985fc3725e347882557594786ae833452ea6b09399fd7740453ccb651c8494a621b9304883ccbfa9c385857590fbeab10e47068e5d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591992884000000	1592597684000000	1655064884000000	1686600884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc25666529f3d2b35ea087b60525d67ffb4ec4a52513c201897bdede1b89c3e2c9f3ffcba9e36e7f9abca0dcfe7c90c3cab6862894061fede2e42ae79d3a79ca	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1592597384000000	1593202184000000	1655669384000000	1687205384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x06b97f66dc74786cf16d02becbcb7ba3fd84a76fb9db7fb37ba5b4bca7901a98934a0d6cf2b53714311f37aba8d2976bd53fbd5acba8716888ec5aac775144b1	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593201884000000	1593806684000000	1656273884000000	1687809884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x267377c6f7d4e77f426cf17de65aefc2e12409bf02efe687f0aee4e410f75cc1485fc457940eaf877a88a7bb7d34d40249c45431b15d2d38f61d42327cc6bb7f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593806384000000	1594411184000000	1656878384000000	1688414384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf1f6633da52a1c2e9e278ebe7f9955a920b9e1064ebe2aebf8b4e2a9699666e7a228ae2933bd38ecc8e54e540da496728078284c386d97379ea98dc396d7908d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1594410884000000	1595015684000000	1657482884000000	1689018884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc08d89c4715cb1f776ae3f48572f15f9ad34319f592a16410eab0c5f73411ab5ce6c3eeb0f4e1c09f1d63745a68f3b2c8d7e0bc0e7141f63cf24a593c1f42a32	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595015384000000	1595620184000000	1658087384000000	1689623384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x191a4cb0bee07fc757ab0b1a086f69abb789db169f7724a0119ffddd5ec044633298021bc8d7f9cd14ccc706d27c9178930bc9e5b066e467c156ee402dabb83f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595619884000000	1596224684000000	1658691884000000	1690227884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf9eb0e64de8a04e87bdee68ac9bbf004453ce85a9c45bdf2d94f8ab237dbb913166c63052aa67e08789e4d24643698cd480eb95220ee5bd3a511369f7c3dae9b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596224384000000	1596829184000000	1659296384000000	1690832384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9057f11a2317bab0096e848485c0e48b29034ab2991c282422f3fec18fbdab92abb0e70240e46687651e9cae76e7c4572d3df0466020a2f2004b6095bf52d1d6	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596828884000000	1597433684000000	1659900884000000	1691436884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1610ee558660569788f970cf7cd738dc87751103c7c606dfea0c1a5ee1f8a0ddb5ef229df6e27f1657e43f84043e3f5b59fe0d67ae9d90190c2c43f090d12da7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1597433384000000	1598038184000000	1660505384000000	1692041384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x10632fb6d12df3a8b02bfb9018b95cc0e7773fa40dd16da7c06d5614552b976571161511fd4828afed8edcb451267327c72eba3b097460eb07d0da91331195f7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598037884000000	1598642684000000	1661109884000000	1692645884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9657774b106c0670ad1c719d3c20c60757f9ce371cce7a480ab942f16cc5af369c652dd5263547a2d61b8eae8536cf97c7cdc3bdd06edb589788afc3bc9fee96	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598642384000000	1599247184000000	1661714384000000	1693250384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6929e29a51aca46e32d9aa33d26c4be299f77fc28838d4688d0439552ccd74c20cba974edc66f3dc018980c6940e32f15f5804014913a06656e83ada8136b34f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1579903184000000	1642370384000000	1673906384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2aef3210bd447b5c42f108cddf46e8e6880e059837124b9fe58af7a865e5ccb6d519b13e1ffcc69769939b9c600e4c04812890a1b9e28c3840c856516762aa2a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579902884000000	1580507684000000	1642974884000000	1674510884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x71e9eaa4bc4515a10f4948b674b9f60ed932c82675024e854aaa9c99dbcf1c6d44417624438d8a0bcb71347e623be4ba2a842878984df0057bdc6d68d701329c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1580507384000000	1581112184000000	1643579384000000	1675115384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe31449442aaf419121016e01efd3881ec6a21acf6acf323930790b5bd6687daf2f848ae4f7a19d511179ba98c96eb4f7faa0b1b62a72773a32fd560e18cc058d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581111884000000	1581716684000000	1644183884000000	1675719884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f2dfb8827e70cf9dada1ef30356a5001dd647c8296ee8f2fb092a56c7cfca3926d727b352190c0ee0ceceb52218f668b1750ad4077c1b7b57b55adbb3db140a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581716384000000	1582321184000000	1644788384000000	1676324384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7f66b83b6516ef25fa6f8b12793725f186cf002094a13ce14b5b24128df6b4fcf6de5c9ebc1a2bdfe88e1ea82006a8558db93a034fc881f16b0b23745504f237	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582320884000000	1582925684000000	1645392884000000	1676928884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x47a76f1ca4dea0b551001891c1bc3376aaa5de14009c83b42e0e5bb5db241893f68d52f3f651a705f717678931c9c1bf0aba84febdb89d20c17687685fe847b7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582925384000000	1583530184000000	1645997384000000	1677533384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xde5cf42d6983a408bf3e1a4db91d5b830a3543db550c66fad8b2a8a1cc15919f0f0959a361612bc9aad604391e3992a582ee0646874290303138efb56478ec8e	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1583529884000000	1584134684000000	1646601884000000	1678137884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xeadaf4acd85d35e287fd39b16224d20530aab353806571725790c1412db0ca582b06bb24eb9d7114df7557ace213d7cbbd47b76e0d6eea506e99a5f2498a11bd	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584134384000000	1584739184000000	1647206384000000	1678742384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xec2ce2b74bd08746cc3e2420443a1bc0697f94c9ac70c08c5c53627391978b7ce43415fa808df1b017d71f52ef61803a0fd660fe81a67e3c3641ea3016babc2a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584738884000000	1585343684000000	1647810884000000	1679346884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xce7e682889bac6bb7e29a49ccf7bd1f103c23bb188b702330177baa67c779058f4685ed03850f3e09d1e65162748006aa1df03e9621a45f5bbd020dc6eb3e096	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585343384000000	1585948184000000	1648415384000000	1679951384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8209fe10dc642af844743e19c3f9db08fe7e00f2b5da6a8525d5626e3d3ef7750a957a9296f0f1b167612de497f3d0e654817090c0bda6ed7e031a6aae28713c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585947884000000	1586552684000000	1649019884000000	1680555884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2a6338d45ba7b46fd0c487adda8ec69a9c1a5bc8e7075761ddd001960036b1cabfbac04a76e419615b61ab0a0ed665873e8755694bb9372041939c25693c2b8c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1586552384000000	1587157184000000	1649624384000000	1681160384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2573eb97d93c30758959701fed26c3615256de13774e96d445fd5ebc3a14cba4ad641fff87cf908e2011fcd01c3e2434b99710756b731e383017c842cdb6c0a4	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587156884000000	1587761684000000	1650228884000000	1681764884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f8f8181e04c52b26764d39c3bee7550f155ebbb6812c980ae220cafc20799a086a652640db881078577e0d6ee496e20930c46efba8bcb53eabe9f98bad54604	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587761384000000	1588366184000000	1650833384000000	1682369384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2930d7b59377849c601a5bdb1aa60ca5fdfde1e0a5f4a2e03542d082be7c363153f14a1e0eea9045d920f3bfe8dc5609a60cb70c0dfc2aa93958ae2734ac9944	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588365884000000	1588970684000000	1651437884000000	1682973884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8e043143099a11f7ad1f60804dbdb3bd8b0cfabd180fe9a126e63b0b52a8fdae6027f3e210cd98dfa056e97abeb37f7c684bbfbd9215fd3d3bed003fe10c4550	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588970384000000	1589575184000000	1652042384000000	1683578384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf235bcc245e000cf1ed6d4bce92913d79af902f525f43033d8e709cbbc7765a44be652273f8eabc8738c287de19ed4f42cbf63833712cf366205ef00d2996c2a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1589574884000000	1590179684000000	1652646884000000	1684182884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf911fb54d8c9d787c1494b4c35f652a0a29b7bfc82effdd084a7c876d8ce0b53baa2c99599d2cccea403306f7699f227c171fe615c696fccf6f450ee2b1dd7d9	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590179384000000	1590784184000000	1653251384000000	1684787384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x178bb6b11ac19d2b3f501da36481163ffabcb05304f5948a26f69297e7ac52a2da30206ae4d6cbe00b1cba99888e47f993cc8340c042d69f7bdcd018a808da81	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590783884000000	1591388684000000	1653855884000000	1685391884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc661566210358e0176f9e4950b3b5ff3a2977cc1f122bc6abde3246674a6ed8085584ff9bf6ae75b8a9d564fe763e5ccdd365b75629f356ddea7543cd69afa17	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591388384000000	1591993184000000	1654460384000000	1685996384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x751049325aa9ac8cc8128011f5c39b3aadbd346b52e8f975d748260c78ea0056238318788aa209f5e8cc9683ee1a8f3a5b31aeab600c54f2bf6547de16236668	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591992884000000	1592597684000000	1655064884000000	1686600884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf1fe63b00ad881cf34db5524a4546130fab745261d812ba725d151e652b5954950a7e423862e66a75e60f2d217f91e9e6d144666fc4a82966119467bf3939182	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1592597384000000	1593202184000000	1655669384000000	1687205384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x109f90e13817c333c1207d75d64fc1465847ce5f890630965c2527f9504fbd27f19d200083ddbb88f76288f800a02a256ca051a19b2e57343b23d317b8e69c35	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593201884000000	1593806684000000	1656273884000000	1687809884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x580f1a1f33db189c33e0f241e9c3bcdb9f30a4e9f48b390988129c24182a25d185f87164f57aaad8d2d9e7d405969a3b9b44120408bb457b3075c312a9fa48e3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593806384000000	1594411184000000	1656878384000000	1688414384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x63f4421c65bb7640d759500c81a53bedb5f9d5b77d11ec57ebfc3344f3428972decb40309b11d9288ee64eaae4034fc2311ac1cc084cb226aa3baf4c363c3d62	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1594410884000000	1595015684000000	1657482884000000	1689018884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x871c725aa59dc3655eecd23cbaa8d1e86524db3817f8577fac74f81cecbd22c18445ae8c61cf7a9a91a4a92d547ba5c7ae2441cfd1d2ff9123660847399c1025	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595015384000000	1595620184000000	1658087384000000	1689623384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x99d1fd5cc445ad1850900f8ac74494d13d9809654c615e9521c959742df8a868a9dd7496d0af9fb5144cb826574f4570739718e342894e32574f04b5287adcf7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595619884000000	1596224684000000	1658691884000000	1690227884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1efb1f9181b92219e8842f99cf3149d9594e5d70347714fdda647e73a44c24732ece64fd99a8403dbc6805c15597538c073d9dc47f98f1a625b3c5ea5eda76fb	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596224384000000	1596829184000000	1659296384000000	1690832384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdfe025768ddd3206892029ea1aeefbb19836a485db57b4873f9e0ec698835e73d1a9739dd1b24590d87118ccbc962209630e16fe4f702d198ee001438115a8c0	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596828884000000	1597433684000000	1659900884000000	1691436884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x46130fbaf48c6cd19760cc979913cdabf5eec68b7b19f18d3f9fc47238d96293f17bb3ce8fa62f4a0b1672c07e87059f219a14b7ac25deaaeb912d2eb67817e5	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1597433384000000	1598038184000000	1660505384000000	1692041384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcab999048516a5a1a7bf40d73b746fb4434fff950867d6ec6ae13a0cfcc26851420add58f8339486c08fd3cb1db651a24597cec44ecd7e345929ff2ea6ea5ef2	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598037884000000	1598642684000000	1661109884000000	1692645884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x982f5534df3a8e76c6ea983776afb0e5415958497611d36ce56cb7e03cdc17a6408ac67a47690e89e50e98c5ca6be57866da61e05e908b306fafd54bb2f76534	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598642384000000	1599247184000000	1661714384000000	1693250384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1579903184000000	1642370384000000	1673906384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x33b3524bef2c852a132928d898086093522980d0361964de892ed086957def8964d699fddc8144aab1a371f542c20a40ec8356ed518daf2920c18df696df6fa9	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579902884000000	1580507684000000	1642974884000000	1674510884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d07c76c28519c6c80064238b2903d742219b2e861b5f2f95514a2caaeceb242bad33cac392bf9ae454364e8819f0d8962d31a60c8b7366991b9fa397237159b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1580507384000000	1581112184000000	1643579384000000	1675115384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x85b1a6d79c2b1e4a7a2c80d1ca8c0b273c718975bf87c16e5006f6a63e739dc8da140be302dd9777de719122573abfebfb328de24c42ded421d8645f5d702a2c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581111884000000	1581716684000000	1644183884000000	1675719884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7724e51f884f377cc74806f3bc6f2105aadda07c18658a8b2529a8d2549f01affeef719d208da9e5dbd5b12a3ea5d0144dd48f1cf5deb178065d1ede5983e101	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581716384000000	1582321184000000	1644788384000000	1676324384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x09edfcbfea00e20c2c86724bf6de8763582932ff95c8026b8f811076bf1c248826f6c31288584a27a083198fa24bda2a83a6a4686f6c695d0a9918a9464320d6	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582320884000000	1582925684000000	1645392884000000	1676928884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9601f9bfdb2b0066d31a45130366ade8ad3f717adbfce683bf6caecd052e744b6e456e91ee6e0897fda3aa19730085cd36eefd4559bea2b8bc20b15445af713c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582925384000000	1583530184000000	1645997384000000	1677533384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x433bf73d7fc4be445800200095e56efaf14b810d3e41e1e4b074e3420e9d0788ae2f3fd77664091afc08d73442b7115ea0e0e458d2133ceb0d6775d873f6c95c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1583529884000000	1584134684000000	1646601884000000	1678137884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x87573b7cc7c802e46d5605e24d9d5abe4856e6d2ab4cbd48e7951f7951bab3c23461eedea188a7e4f5a9181eb1437e5da2c314ffa1164d8ec2e7abeeaec19e2f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584134384000000	1584739184000000	1647206384000000	1678742384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x48515946a2ab775f7f85db878c03f29f61d709ec9e91a41b679db5771aba470ea442fabd7d7206538b090d6218502c40b7527de4d502adb97730ff3ee2a8c2e3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584738884000000	1585343684000000	1647810884000000	1679346884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x45ca16dc645d1a000adbfa43a69d7868d3932031e0c08b7219bb82c38a30fa6251a87da6b0445bd6c37d9cf5856adcee0e5ca35831d2bdf5e74d8d95911cb15f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585343384000000	1585948184000000	1648415384000000	1679951384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x446bf4e192d9980883c21308aa0d01d7f7b6de8fe9813ea13b3717af422d32b492357095a7d46a9aeb0cd6c3aefbe3d1cd0034d1088138ed1f62a61d333c8086	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585947884000000	1586552684000000	1649019884000000	1680555884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6652ba05927d28aa0fbb1f1b8e81dbf901a94455f309684dff97c6443313a4f7fc65a95fa0b9be8763da3d47dc6739ef07033e36bbbd32f5e45a7d56ee49ad81	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1586552384000000	1587157184000000	1649624384000000	1681160384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4408c425ea1d10cad93eb0bdaa79551b7011a9f655a3999ee8d2206b8751e2770f05ab16b97945035ed856dd223ab6f155c44f7187558d3ae930984d5cc5844d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587156884000000	1587761684000000	1650228884000000	1681764884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5947561c4d91131ca1fdc793a5a3b94eb17c12a20a5f88e553b002c8a7c8bfc1e1d9cc94e759d416f38c1ea4807a81021b9ca6386e17e9a1b2f84af3fddb3406	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587761384000000	1588366184000000	1650833384000000	1682369384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2697a65c40b4f7ed506474b4dee2fe4e07763887b54a31769410abe511968a0c4e3257332f704519ac2564b20201ad85cdba2c7f0d1269bf040fa4d9878ae305	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588365884000000	1588970684000000	1651437884000000	1682973884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xffc825d048fce8fede3b07939ca5e7f621431bf36cfea29817747c5c17484851d40ccd9731b6fb80221802516f737ce99532fdeb37dc7b1f1b0f219295ec9e61	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588970384000000	1589575184000000	1652042384000000	1683578384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe4f946534583c4173daae7a9f1aa057b5639aac9b61fd153b58a5b39cd8364a2c3946cd90a840b2af46950a699a6c2fd2b823bab1cd8c041b12fd16995216071	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1589574884000000	1590179684000000	1652646884000000	1684182884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7228df36f738da413ff6f6440cbe82814b5993ab80bfcb01e67aa4181f90753375f2ce40f8db56e7cdc1f4c757c001dceb9f23f6cc27b2a93b3f2e83085b919a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590179384000000	1590784184000000	1653251384000000	1684787384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa15087ab61ed5d214a271a34a508f741a57fbd18af773f9ae05199f50bb0c33729d9aaefe3a7a18b46ecbb2da3f1349b05ccf7118d3ee1287475537deb761b5a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590783884000000	1591388684000000	1653855884000000	1685391884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x88eca984471212b54085a0c5fbfc663ec9c5e700de964eb372adf0b34ca7f9132ea584d17a321f9e43fddb7ddc07afddfc28d89027ad1455c918133a716c081b	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591388384000000	1591993184000000	1654460384000000	1685996384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6dca7404680843cceabff367e3a15036523bac70749c9e78eb07682a36e89d59f0a07fda0a60da5ec8f7b5d7258ede6455323217f9283911706d576101473762	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591992884000000	1592597684000000	1655064884000000	1686600884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf45c912fda4003471e9335aa3d5fd7a8d598dbf2bab3c2e092d003d254e8e622094241a76dc9a22d79ffccf631a6748480bd3cfaf69572afb3a7e5dfc314d018	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1592597384000000	1593202184000000	1655669384000000	1687205384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeac7ccf6530cb861032c757c311b6c617c8904084d8d66327465ddb081e649788d90f9c0d761ea960ee4e327f9f701a872586a19a1ca2dc5935b4fb139956f6c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593201884000000	1593806684000000	1656273884000000	1687809884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d122451065e484a497c7f3461d4b84863794a72f1102002babd7724350aa8c3e5340213d62aa807a790bccf215d2af4a2dc717b2a45ace68a939a4d70dff237	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593806384000000	1594411184000000	1656878384000000	1688414384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x73d6f37a4fa12f847001feef4b8bf045976ddcafec11cd05257480a38d23c30f9f8a33234bd08df74a125e5cf2ae37f340056a17e94515869a0cc2020bab916a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1594410884000000	1595015684000000	1657482884000000	1689018884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa862f8738249f26151c3141e871d1edcc2cc1e86c9b88b66ba98c91306598411f4b9f1383884528209b5904e3e7e4ad94d0bdca9fe3a37f67b397f40464c5303	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595015384000000	1595620184000000	1658087384000000	1689623384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf06d57bf549634307a3cc00dec24695bc4d37d75fdeae228804213c84514ac7f4a955cf2e2837c0ce3282178c0ae7ea59d8465e4ad9890e1873d802d5f317516	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595619884000000	1596224684000000	1658691884000000	1690227884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbe9fa43e9397b2362124bd883d018295f2890610a824f05694c286e6d174756d458f1fd0d026144d83cf0fea66f0c3efa4f27c98382ac44d9aa3c1d842e90d18	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596224384000000	1596829184000000	1659296384000000	1690832384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x979eb6a0553025ea7d2bb24387a4fe4108b9679a3a92cf15aa148bf4a83c67ff67c83a57a071cfefa7f171ccfa9534721604f0884650d5d3a63e47f0a30b199a	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596828884000000	1597433684000000	1659900884000000	1691436884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x76b4d2670f9276ba50ffd10935212fd24ee921ddd3e63ad74b9df19ae5a5ab62ad7284cf159224b8e0a5b3f14bf438d188e47716f3b475577c6c9dc84477d71e	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1597433384000000	1598038184000000	1660505384000000	1692041384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2328ef5e5b5a0e6dd9197b9535073f5f0001edb9b3143797b6fe3e4c91a821adf146ff358554f660264fdb99624041843972007ae62f7f7b79c5441a3c5b100f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598037884000000	1598642684000000	1661109884000000	1692645884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x307bfb280d5026aad358b8c85a616d9760fa99899b3184a0a1d49b1a57fab4d343388cd1db61811462fe6d5185fb28f73cf52a3aae04531c1e14265d31eae117	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598642384000000	1599247184000000	1661714384000000	1693250384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1acae0321cfce758697d91066f1f73beeccf5b7b870d60365f40d55dbc8c71136e098b7e2475591451f6980352425ff16fe7daeb9808d7190efb77dda21d5e8d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1579903184000000	1642370384000000	1673906384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdc2ca6948abe7ab739176fde8a6ea8045a6211d5bd4425f1fff75e201269b97f48276cecde114a2100ae5b19eb6eb690de70be8685eb63d964ba9d56a0714b48	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579902884000000	1580507684000000	1642974884000000	1674510884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2a417149ee14434d047830a8f0bd62d008e790ffe77cd4fab5b3eac16d811ec08b1b1288f4b4fc14e397a62ebd0cf454e99a9cceb4317555bfa575455915f1ae	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1580507384000000	1581112184000000	1643579384000000	1675115384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x92bc616a47eb9f925f9df62e8937ccb6fe2e046069c86e2b6916f99b5f436f3110175c9731300fb8d079e6301dd3791ab9e60b23fb34346882c84d85029989cd	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581111884000000	1581716684000000	1644183884000000	1675719884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa2603afdfcb25c549cbe5068b216a1ceb410bd7d756dd8322e3edd3b891d39ce670956058adb007516c800abc262a666d3b545cab0e55e409d10c9ca22fae176	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1581716384000000	1582321184000000	1644788384000000	1676324384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7ed28c4bee2971853cc2ad80d71c1f4ee81acd992b0e583423efdd7275bb8da99cb193e63d76d176d976457abf9df4a4da38c46d812408865fe80e1a5e33151d	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582320884000000	1582925684000000	1645392884000000	1676928884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa92b31ade610290bebf72dd0cc7e850e703bc5cbde4bd785d1a54d02aca70ad72348c320b632466cc8375abe0f21fe49bddf6066eeac02e282ca0f90447c3dd4	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1582925384000000	1583530184000000	1645997384000000	1677533384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8365408b57e241ee42283f987aa3abed8b2a999590c837e519a818d2d0fcd554e18b11b1786827a36405b5c5514c543f98e523145440d00e94b2fd14fd3db10e	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1583529884000000	1584134684000000	1646601884000000	1678137884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x86de8660162755d124194b4cfefaea96e52ea6c644c4692d2b5f025d52bdd45ddf19c320dca2eb489c5ce2fd505c0575146f39c3a3f59632ed0372f1bb4feeac	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584134384000000	1584739184000000	1647206384000000	1678742384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x97c5a98fad4eea3b02ba9dd1d0d4c7c2f66f62ea8287005aabe6ed97df6e330764d4257a2e12ef0881dd370ec0e4241b44778be8c4572ff3cb76049880c75146	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1584738884000000	1585343684000000	1647810884000000	1679346884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x26116f5f3c57ee4a6bcc889c7459900bdc2ab7a19197705bd4ea863e8e879ac1ac9bb28de41a25195753af4f4b79069fd4f91a107f9ee977246f1990bed598fb	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585343384000000	1585948184000000	1648415384000000	1679951384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6037e9480d5d6713db238c109824797efcb2ce1ecf85193729ce75de21647e7b0f68593ac5e22f9fe2b9ae6257ebbe353a1457a79a1708efb819bdb665c24aed	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1585947884000000	1586552684000000	1649019884000000	1680555884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe16140da1d18e7a4c443de9f2c46455730c0d947d3ea4fed916ef626a995d350ebe465acf9a98177237bc6dea46117bab5365cdfb8ec3115f6869713043a8ae0	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1586552384000000	1587157184000000	1649624384000000	1681160384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfa4068d927d624e87d20be5b02cbdf6dca20bff88ce78faad749116a3ad222a08d1e1d2de0f8b6e4f51d172b218abdff01da098f0bad2e8ef1f080b7f11c1ae4	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587156884000000	1587761684000000	1650228884000000	1681764884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb39aa3e2a0ead8952276611f567283bb68b7a7f208a3036951c613e5ff2a9fbd29d0a9fbd2788c7d632a134802f57eb2bf391816b7cf579eacab8b9638e3602e	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1587761384000000	1588366184000000	1650833384000000	1682369384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7f752a773f013ddb40957b23ceb49dc5d532f5fa32606517ccfb1544a578146369b3fb91f11370adc7074d2106c7e2b3f282a972b267ef35e6044496780a1daf	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588365884000000	1588970684000000	1651437884000000	1682973884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x455f0179c20e36f5df4663d139b0597885ff932f6d0b48931078faef22a70fa25fba42c56bb96d2af723e4c4bb625fdcecbf49a932d050ac2415a39dc447c9f7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1588970384000000	1589575184000000	1652042384000000	1683578384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0ebf5c6861a339bfdb189d2de063d2a6a36fa13774d082ba851b4c31e6baf40def34a1586958ab6fc807fe72a4cd83e6f7703ae764e117e132743766b45a8e7c	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1589574884000000	1590179684000000	1652646884000000	1684182884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x31425f3db441641a146d3c68a457dfd7393d8ab2091006e0396b50a7df537008ccac3bee27748e3b032149e757cbd54aff92d5d677e6e2425e8295d740bdca79	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590179384000000	1590784184000000	1653251384000000	1684787384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc48388cde0debfc8b5c6695592c8e1d82a1042639d67f237d93caad42c31e9ac7f81b8aba35936f6a692d54afaac2668dd75cd5e8b5a11f112b71689300af2a6	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1590783884000000	1591388684000000	1653855884000000	1685391884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd2bbb86137f1eac9c700cab0a1f90b563285bd47acd0d20251de55b112496b836a36f65b910419f47ec94484519af6e02e5273bcadbed3e260dc632654cec1c3	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591388384000000	1591993184000000	1654460384000000	1685996384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaa31f19b42f4371f30a66d96e876add06b31592108401c8d3e47bf33b415a22e2d37b332c056f1e68475f96334cc1759be3046cec45c12b9cf9a41980988cd82	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1591992884000000	1592597684000000	1655064884000000	1686600884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1c50d63e592f0ade8444153bc23f8f1dd669d1373e8fa2f95bb3f6c253ebe6c4b3f217fb82fd0c948ca933f9c021034aaebcb4ebf8dc24dd9d38bb443153f71f	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1592597384000000	1593202184000000	1655669384000000	1687205384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x289e642bd76293bd1cff841aa4464efe6f7bf933b20092bbdea9d388786eb5bf46a42aaa6d1e53ab9ccc9a2fb8e2c92c135602af10fdb97db19cbe713baff0e2	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593201884000000	1593806684000000	1656273884000000	1687809884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x806634a139f96e85bb73c9c4c8471d69d23a26aee0010635e37b3b37007d33eb13b94bd9473b304d3f0bf82f24741008e9d2a89d9c565f4a337d618bd199a6ae	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1593806384000000	1594411184000000	1656878384000000	1688414384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe50193b2a77b22c4ebfce71797bfd4e8d0f6eb8eb3d8805b89680b1d4cbcd8f1fde23dcbfb57c450a70d0ce17859323bf46abfd8a3a502c35978171bf7da64b9	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1594410884000000	1595015684000000	1657482884000000	1689018884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa2665c07ddcc3872921e0219aeaacb41df24c519ef2da57e8222ced3735d859429e6e55fc7714fc518387a94b64ca9bf452b674a8a7dd8b538e90bc552900bb5	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595015384000000	1595620184000000	1658087384000000	1689623384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x93dbbd2e07811bb245be09fc361d9b8c4c2a987bc9ef04d4d6b9036181369d04573d245014ff051f9b49d84967297b04917e406134f302177ffa37d3d23c3810	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1595619884000000	1596224684000000	1658691884000000	1690227884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6f6b65b4e9876017e6fe9e818135d0aa041e0ada012b588435663cb9d3a65fb09c3d335c0151d069d69ee96ecc22c5d63df06b4ceb176afd1b72e3188776c3d7	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596224384000000	1596829184000000	1659296384000000	1690832384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb42da8b3c6a206c15bf32fff23a4bcf25c3c4e31ed4981d7a8da360b4f0cb98ed4d20dd86def183c01faec859055d010fbd19e06ff162b8dee4a0e2fb0b5f318	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1596828884000000	1597433684000000	1659900884000000	1691436884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x66eef43e8f43dc2227c77abd0420fb42803743315c6323d30c69e0d4b31aa476bb5a401efad66d2a824f97c63da2ca851e1c3e562a628d86e6ac3f4035f54987	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1597433384000000	1598038184000000	1660505384000000	1692041384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x96d56b728528ae0a68ae0e3120df518c7dc379fef578ed54a7bdb1d46beb7e2865485a13e06df1e12f39d9dc6913ae5cdbd8091fb9bc6e1ef79386d35f89e8d1	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598037884000000	1598642684000000	1661109884000000	1692645884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x16b33c40b07e5236ad606171749138680d122af7a80126c5e6a387e86512f3ab343443347df699125dcf00a337e46ee39066cb565f3d2bffa766d0a574e834b8	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1598642384000000	1599247184000000	1661714384000000	1693250384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1579298384000000	1581717584000000	1642370384000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\xe317bdb1dbb8bb821f8631df4eb79ba952a6aa406afbc832af2d710b49467b09bb81546adec953366643707b3e266209c36b4e766c51e727ee90601a39875506
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-01-17 22:59:58.454776+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2020-01-17 22:59:58.628257+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-01-17 22:59:58.761032+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-01-17 22:59:58.886791+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-01-17 22:59:59.004722+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-01-17 22:59:59.122026+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-01-17 22:59:59.238994+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-01-17 22:59:59.356221+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-01-17 22:59:59.935112+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-01-17 23:00:00.507155+01
11	pbkdf2_sha256$180000$H1KfIe2du27r$G6XmhiwjUSzELu+E+m6qbR4cLCPv7TgcFTF81HlQ3kg=	\N	f	testuser-ggYai0m7				f	t	2020-01-17 23:00:03.807227+01
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
\\x85b1a6d79c2b1e4a7a2c80d1ca8c0b273c718975bf87c16e5006f6a63e739dc8da140be302dd9777de719122573abfebfb328de24c42ded421d8645f5d702a2c	\\x00800003cb7743a5cee52d61d59c97a2a63f7f3abf0f0fa5ab814a9556b1bfc6c33ee67b3e19d1d28364fa67aca7ee37c76ae1eecd21155103822a3abaea85610a040f4846e7a62a178cb9feae49631b01eeec1441bce7b95f90e6c11f9c6913eb73c66c6fe03ae05bd69192659bdfae6c7551e8c6a52ed16c9740b0e9ac774f1043fc87010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xc76e382fc7b103ea282f762a2061b06e1e4258aaa3f6a3956b083ab825c95ab792c0828d6906c7b43f1a07c70e722202e6882039bd4c59f9b4df62fd547d0009	1581111884000000	1581716684000000	1644183884000000	1675719884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x33b3524bef2c852a132928d898086093522980d0361964de892ed086957def8964d699fddc8144aab1a371f542c20a40ec8356ed518daf2920c18df696df6fa9	\\x00800003c154de7308c2ee3006d2b4910370cc4b836f627e92e8c49911e6b23412f8f5c5aa6c3f14fe3fbd7a9d22ff2cc75542e68701fabbbb3028ce0430a22c5e9b910793c5cbbe73b9d725e4c0e311fb094d7c9ba7311bfa0febb6060bf6aa480bbc0f3a2b99895043623c212546cfd8d0825b988aa23b145c87bb1c6a6f14e0754465010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x4a326e253c650db555e241b20dd26ad37a2a485ccb35ca1eb502f017e16471954cff3af7f522924a85c7485cb3f1dca4badfa4eb5974b5be614ba34e452d8600	1579902884000000	1580507684000000	1642974884000000	1674510884000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d07c76c28519c6c80064238b2903d742219b2e861b5f2f95514a2caaeceb242bad33cac392bf9ae454364e8819f0d8962d31a60c8b7366991b9fa397237159b	\\x00800003b8e866d1bc9e13d0ffce5295941ae6a7f38998763196d4ead8d31427a9a0d7e38e69093139a96527c17375c67521fecc604868b9a3d02e0c780284e1396f7a304a1aa7e49e09f15c2a5641890f8a85ad654143194b6027881191b5daec157573520ed7a50eba69edcfdc694dde8782fd8e9951d9c3d21f578e329090720a08bf010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xe172706718d21355c06922787583155dea30ee43da7fbadb94aa11a9706fe5958074559e1e7383192a50446300eda2af1a6d39005d30703012d80f1aa78d5202	1580507384000000	1581112184000000	1643579384000000	1675115384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x0080000394cc1558bad0d189c96918b5e9fbe57f671931007f36d0eae1a25a5e46f20b3112da9d9edc744c40679d0abe27e9fe2ec03c796c585fb497f8ebdf8d22bf35c0dff03d171d11cdba509e3672436982328ed1752429956a9025afb00bd17974dc591efe09f0bba22212aeeb54a0a1418eac154e60c3816238c9dd19a980f96e05010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x951ce93ad9d28ce887f0b0756eca04d6411bb3fc892ba486a9e779681a3e159a31316160c1d29fe4dbbdca336bbad47187ffb5aafb2272402da94c95d4859500	1579298384000000	1579903184000000	1642370384000000	1673906384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7724e51f884f377cc74806f3bc6f2105aadda07c18658a8b2529a8d2549f01affeef719d208da9e5dbd5b12a3ea5d0144dd48f1cf5deb178065d1ede5983e101	\\x00800003f859108497ae406503d3dde6c1066e8663529f00566a838fd37cc917c4bc8dcd0b1a164ee5c8fa47f7f028f193471eb3261a4861a5181e2667ec44be8dec4cfafc046055d7599d1d456d289e6eea069116f9180a801d667270a7d72ea1f4a74038135d1aad39b273ff2af25a71e88c8a3f8a83974ed1949399ef4bc4b04e98a9010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x1b4746213738f0b3d2ef56e8f212d4c73dbf85081c1cce506e19258d4f00e796b0c0b90c4f87de9faef8d48118c22f46c81a252cf0f6675f7499480c68098908	1581716384000000	1582321184000000	1644788384000000	1676324384000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe2476d2cd60ee81f68ae0e50c50c28a357c0e2dc0c82d2dfea0135486b08a7e9d238556fa727a5cef17a78869a7320b57c2a1adf209b211bc469ce5db562e365	\\x00800003b8b5922dcbc335ecd8ccf8c0be78984cc2db04cb1f96a783bb712a6e5b4094e921880b23aeec67b1ad1c8794d8fb1b00e41b8ce79aad5fbb669edbe8145f6fe36d18f81af257866a5016c9f5c5f71ed66f08c024055e777580d5aa10885c5ce59b646b0f232da6759c8efc34f148a2318a82a493b49fde8925a7e83e502aae4f010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xd2d6e4b487c8fc7eaae4cb72bac4417c63935eeba866aaedb348571857f3c556878bdee10a0f94333e542ab0a30e28256812f305e6ed97d09aef24433810bc04	1581111884000000	1581716684000000	1644183884000000	1675719884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b92ae9b80e2beee0f317c20a471d430ae0b0a8b9d4f75e51dafce9b41f194d6659964ff3e96867d6c18ee0b51b28b98e479f28b05f975edca189b85e8e5ffa3	\\x00800003f280169a1d1d6988dfd8cde16b1ba534a773eb7abfdfc2b7758167921f70bb3ce182da176fa8a52e6c4d19a42d6a19328ae32122cae15bda26fa927a52f739d8d0433dcad7354c8bb19369bb31a80950f5db34327339fbe48df193b6aa710d07d849c399b91fc1005a0f331387a80d65991fd3211da3553a1d6bc5ecf98c2317010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xf592045c5eabc1bba8d48ef1c99ae7366a442413e6b476cd30dfe769f81045bbc8976d223b434e510b9551f9091ad66c9943614c1529e2f8732c049465339009	1579902884000000	1580507684000000	1642974884000000	1674510884000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f6cd1e5d8a7d1b929441334a6b22ae9dce8cc77d3581f4b1eaea7b209d80821841cd190ae2d911eafad4df12e765b41e33f24fddd06ceef5e780cc6035074cb	\\x00800003bd994be0279546ca53f1c8ab1e47d3d3300c3ed39e758ef57180ec006c81b996fa8707b022b8e26924bf1af5b5e6e6b0fc708e42d501e88de1ff334cdbf55f2314811ad042e52664060570e4bea957c7837949c0a5a7a0719805d1f69e522635800fdbd0ac213ca802f7c4c786407a3c8d1fb24848b25ea90c5998e645cb0daf010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x233b6dd6baadcb34fac8a2d85e1b0bf969639a183ab32277b12e16a488a29fb84efc0f0b5b6d242c5baa0a33ebb98c29af203cec08eba97baedf44f441222407	1580507384000000	1581112184000000	1643579384000000	1675115384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x287d8be15c450bebefddda4a303188df4bfe7bbf51f7872149325cdeecbbaffb05810ab25b1673d0536eb5028102052e6ecf77c85b89c1ed7d037f965437280d	\\x00800003c11f2731e003fec567674389d6391b1cb85ed24bc8236f2719fc623e556fa8a3f119c5bc9a6ba396604a2fb2fbc5a4998b2df8cc19eff0e6336d38c95f91889940dc56dcc4d5c16ddcc412f393ae11dd32e514db702fb80fa4b845ee561663e267de6067b27e6cc241f45e0670dd1df06d76f959a62c71ffa07408e482adb2ff010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xf280587c14d832706afaf79adefb7c24476bd5978ff64be3c3c6bb8cba077ae814966cc37bbdde189bb72ca410684053dcc84b11701a8c33993f116d558cf709	1579298384000000	1579903184000000	1642370384000000	1673906384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e267eb62e76c71936846f1a4b789a556c1cccb27997df621983b9c5b8418e13c667e590398a74af0eef7e1cc925207005b789091832381b95b6008dc71d9863	\\x00800003e148cce68f6fc9addc7aa540cb158ad19290afeacca6ff3311d46f8efd2831e7cb643c60b70a8770612bd603d9b44df2b2b82109a2d02be8f1d95d828cc36aa17cd6437ed3415382df3018d717c2d70b9cdb9a2db04ad139bd659a8af7bff7e7a5a897e26a50035c7b3fb58c56238e4bf8a22880164d1245097a7b9ad55792df010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x5709af7bcae983ff2d1fe36b846a93a34afcfd02f23173c28438a187d72c9e4149d8dd514016cc66d2be52be2120f0a8b7756377dc8beb9e6dc9a09ae18eea02	1581716384000000	1582321184000000	1644788384000000	1676324384000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33f4987ca257861bce6c1e156889aec938d7fa4c84a2b116279271b7910c4e7d93a0e70d8e433ecc419a8545c53bc6827780616ff808a9816f52bdda14e999f0	\\x00800003a1e36a5cb8bb3048741aee08073365ac5f68f1c500dec9b13745956dafe10a5b60a33cb8e0ae7e56e4f70999b5da31b916fb0264992107a0656f5069fe2812efa55487973705fd3dee0701ee94c6c24912be11f70d40e31f51e5d765e7b38db97c3bfd85a72788e1aa8f17ce5d8615a06c41c3567dd4c43f28a03f0e2530019f010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xed3a19e61f8a094c63f277328341dd4a470e94ab4d6d632dd669924895ac0db366bef8de737427863dd3e5c7a890eb154f849eb09c74c25443f26c21188cfb00	1581111884000000	1581716684000000	1644183884000000	1675719884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5fdd12f9de7877e0cf98372373700b0e9e0985687968ae6db88a22d176673dcaf3555f4d122f0ead8596b49165b963493b81b046ab362796d0501f2ea521e101	\\x008000039ee5177b0818bacf348052a61e78d0d3a5598b2224382d52a5d3ad5a7b3b5935be1983241fea8baacc147aefb2ab6b1b2a7548374ec9ae1498ee3dfc86d2721d5f79cf5f2a59a7db7feb89ceda0483ef3c871923dd0ecd0bd3c95c405f90f93cbe7dbfebee3390e4b91ea8024f88afcf74601cbb129514cc19af5538cdd977db010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x161f7bb72a195f8b79fea1a1b282ba14d538fedfa20c45e7da49b8189e85d823261ac7b3fc70f6af728452fa1793c40c70f775b4c39e9325e0b906f57d09c309	1579902884000000	1580507684000000	1642974884000000	1674510884000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8acb986603b90ebf9ab15c34e0b7cf942fb46fb73ba1cf875abced567d81c132463787e594d45dd74ec4f42d96d6c23a6ff8fb97df517c27a968b93cfbaa4c3b	\\x00800003cdd94e0399ee40a386f025ff8141d47fa8c2629d99e116757c9c9e9ccde5030e484a9953c3081df0dda6dc514002c9f0c6577eaa0f51002c8716d13ef87ef987e23dff8b62ae1a88a6efd3b1585c89b340996509eabd4a40e74e104650bdd6206a8957efc5293118a270ec4aef32f67a394c066dab48a5d9bc422e3a46d4a66b010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xeac4d22435bdf9ada21d1e42829beb45e2d7464d843070998966cdf256f2da3059226012cd474784691e89fb482f79cf3f863b39287190a2051b3e76ec63ef08	1580507384000000	1581112184000000	1643579384000000	1675115384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xec0d34e4a035b58f36212af25dfe36290252473c0a12099782b546a0ce93e8c2e310ae63a78c9ea9a2bef3d89d893e0412c3fbac3f34af1ef4a8af36644101fa	\\x00800003c1135ef6152a7edba7307b4e0dd30f0eca8342e50219f9f9d5cb79b2e8d11cd803e274a64943b01e5bd9c55742cbac6ce40fddb982a168e5acadc9c6b3f3127e53ceb9be01d01ac7ee00ce7020532a93fb22ee9bd03ee991648af735696a77fcaadc7e1ac10fc331779dd07d6af95c4926efbe815bd185052d824f3f8b776539010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x3ef5ddfd6a9f7520c43f768c0b748d6218cf478337e178be59561c7b3236eeca41792c7d07ef01359ecbda0d232e077aad8292abff071f96da33c2a5d23c0806	1579298384000000	1579903184000000	1642370384000000	1673906384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23a4205696142c729d194abdc40619c75a59ee9a70b7527d622fdb09ccb01f67f14c538eefe838af5fa06f667c658ddd07472f331ef1274c05c5591901e55bbf	\\x00800003bf98aa9b9785ecaa6d8f8cd43d6597ae60297a306664cb9a255e6ac3b3c110db8c0cfca1098e1c8b21e8bdf4733af041e129345a44fdbdc03aabab3f6870418b98aaa07df520bf1b82a17ec78ebaf3076447e14a0c77dd79afdc737ca7b6e94201695042ef5616ce22f9eddf385ed80e60fb25c900f2378ae1785459193fb74d010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x7f68403eb9081774c4c8ee921255cfa0d9574db79c3b1c58fb7dd281e9cd6a6867789dbbc13de2067def98751a5a3f64e95a30bc6371318814706bac12eb8100	1581716384000000	1582321184000000	1644788384000000	1676324384000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa02baaa2dc5e2d61b83bc60ebac9c61426c7262f97ec4fd6c2f608cd6b89c70ef756d34c816563b7da39949f33cc43fd7fb6f3d56b82db1ef98b01e418316d36	\\x00800003bbb06a5eeeae3b125ec3b9f9e311f64ff02986ac1caefdd928cc41f860899fe4df37430efb703bf2c91c91c98ef29ed703ec34d511aa5a8b00e9294c93f5be70675b02c37abf3c2b49a090ba769db3671a5d48571a5a69e2fe08c92b26ea74d11a9310d698a34150d955857e3a854e69fbcd59042eb028b7adf171a11b619db7010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xebfbfc5c9b6641406221c81cfc1c3e00992cf044ac8a3dbab55e345563cecd4c3bfb3ff9eb3c2138288fac21d5b643e67906fa49caf20c11d74469ca2cae1b0d	1581111884000000	1581716684000000	1644183884000000	1675719884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4b2356f67298901f5b1d9f9f724adf3148fac35b95540fe71a7c3a5a0057fa95622db502126298d93a3d5864ab4bac09d293beec3d7dbbdb6ae4e31fd1dde93d	\\x00800003d95e2a0166a68fcee6c3d8c2f60e8214dae8653dde16050380862969f7a26741ba7220905099b7e08c372249e5da8ec669663a26eb477ecbe3ff3bfcf90526ac49f4a76e910def92bd1738180ee987cde9259082b52fd4d66dbca3cde15ba448779fe73f6f33d51378bd4c222f49ee583d5fcce571d15fa3aff47513054e2c19010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xe96cd91dace9e83f325571507a100ec3220b2edde4eeafb0d3ce538cf71884a0cec32d23abaa185d8d463aad527e837908a286a5629474ae5b687d641bb9e703	1579902884000000	1580507684000000	1642974884000000	1674510884000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6a9bf0765ca4fd2f4fbcdb51847d99af39501c3766ee7c5348e41be4d21a941d1a0cb5a0efaee09eb114c38da75574c88d74d4babdee13f754e478a4e2e92831	\\x00800003af441bd0bdf180f7b14b52cd336b86de942738f3840bda62a53236638313a200471eceb08e05358cb3be564afe2728a3338b7ea2b16799231a3e6a12a7bad360d09f063bb10b3eacf66c1e37dd5daa711ad7ace67a5f340adb20fceb34a1adac2d8b8e23417fc76f86f653dd9b9fd6010183600531e37a1127cfba8fcc8373af010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x890e8e6f4cebd8de6a31f67c6246793653593fa98e594fa2d7c12832ae1eb73180eb658e8f73cde16d879f7bb84aec05d42c62314994235ddb281b08e2291b01	1580507384000000	1581112184000000	1643579384000000	1675115384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x01bf094c74f50f7d6ba8e68eb6742916f83e6417762ae1d7e3db81f2c5af22f1640b8807b31311655dc90826d946198cce1745650dfba54e1b50f90af18feac6	\\x008000039efe3571f62d7776caee05bc71aedf317cb37d824b4be86179516fdcebdd5f229d0629048362f24f44916ce140c19dc997c030a4add4691219b81eb1ca8efd00c0367337842b55835c74f8a9b94f3751518c6a99ba39cf75ab62ac2de1efb7bd0edcc6f2ef8d55c463dfb9cc6c2913b00131c10070164aac27513fb990648f07010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x05505af21ad2e2bb2bbf0c320579a7676d610c234e411d9b3c9c2914689ad76cb503e73caeef6c95e9078a9e650ad29e3f2451ef009dce0543172e1558b3ef07	1579298384000000	1579903184000000	1642370384000000	1673906384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1a8d2021711afda69a8264a696909181d029c609193d791d02c174a4f18f1279f2eecafc0fa7e69627fc2bd2459498d2cb870b03ff8e3c8d3c04ad79765b40c0	\\x00800003a2fddaa4b4fd79d0695b46295a7ae93a423053046dd76c7528e21989090e4bcd48bebeb7c4b487c4500b5501e9138f18c94c5301ebf777a86503a6d4243fdde964e1770eac49d59b6d0d2c111b227eb6aba0ce84da9a3f63acc57b81e3b0a5c06f1897830a3f6981fb2f9f5508b676ec90c05afa457531b3ff3376c8982cfabd010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x65f8b0963a3e797ad2047bcf34f503b5226455a46196c43d37d4ee1a6038bff11b1aeea043d75c8866ac086a8867de95efc74357e38f4073a4de5a4294427003	1581716384000000	1582321184000000	1644788384000000	1676324384000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x509713f433e39f74857a0d334a185180c8a3e059002b78324beb4a4cf23ebcccaead962c4063dc79ad2e5c19f785d7ad985c178580cc354c2fb42a63f5a93bd2	\\x00800003cbed82587cb714a92c0fc1e6655aa2436a250f36215ce525ff2b3dbec39696846200b0d9eb6999b3411a1b6b9f7f036f3322f6bbd60a8ef0dae43b111f388ce80db03b4bef9a8a5ccc0ff9aa5a890416c92bfd6344c2c6a9ecd2085f1362651eeac43684f6838346250336f47e997a76f2a8531bf0134c3b75b4c95df504194d010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x1210ef91e37d3a0070085419b89198453ac2587cdf42d67f8c3fac92e8ff2ce01d5fd8bcc687f57a5fa0e4dda1cb014f8f405046a88b3c212fd3a73c5df72e0a	1581111884000000	1581716684000000	1644183884000000	1675719884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5131d1b4e61709a198ac8c98954bc6b26ec1d87fdb02737009c21c4af077ff092d9f336d8432a64dec108b52381ccc10a02604beb71fd54e63fdd35cff79f36	\\x00800003aa22ce7eee46143e9a80ed2537b888470896dc08987b5f6014800e71d8cdd36ac1deb9aa61da2d78ddac1764d394fa6099257bb07f9ea06fd411e9f1c695e00fd8465c8ef5866798ac4dbe66c7684e37e021d915636c4d57144befe0f5a9c179ddfc8abad887a024b7606aeead2f43f6d0d0d22928402297c50f12caa831b9b7010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x570175aff3a48d343a64ad6d24bbf8e6297505018580487c96bd2608b1c045e2ba03daea6f30f9f0a7471b6e0af75790dc3e986ac2cec5133be7928d0a255c08	1579902884000000	1580507684000000	1642974884000000	1674510884000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0de5ea6a4dea6821f7f5260d322d97a0d4323caf18eb9b8729cfaa06ac4b8cb8623b3f11f3ec4c27f886bcba1a3d1014ec4216c015f26c2a2e34dadc320d2114	\\x00800003d0fb98ff4721cc3ce3fd0aae01f34fabb6e91928bea702d891cc2d4ab80d421e6c0852c42be45760da37a71696b2d19663218a5b4d93993243e58cc2adb54898f26dc60355e10967bd70f5310d5eea4e1c8d9a28bbb3e3323b27f685ba8dd4bc59355e7ed75ec1b8441f8dfb3a370fb5c111eb10113ca46f35fcd78594dad1a3010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x2f4560bbcb202528ba1d1cf21bac6a25fb60f252774b56517b24ee8999aed92b0bd88ae78ec4542500da8d68d86709783330f157a4b197a5036c137729445205	1580507384000000	1581112184000000	1643579384000000	1675115384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a3342a13e5b751fd9eca8b0eed42df31724c15c9d2ccb318762088eff1f627fff7acdcb5df0a2139fb63c7769a8bbd0f935219169733acde1d9fcc2af9825ae	\\x00800003ea86cf1d9c6453c05a3bdfe144b09e2c9dce6c789613d56d151d66b4490ad603b6942f9c308ebeea61708f556e8c615fd2bcab47b7dcdbbce0521c8ca5a796afe8320130e88aa2fade904cd459f8c7f080aa5852736f7099c386b9c633b406b6a2b2c74a5d78c6ab223e2757ea30bf91a17d22f3671e3eb7cff2890f51e908d9010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xb8a9e2eb3be21ca604577a2aa06708c3f080cae2dbac4310179a277678955356ea47b6a8684a579a2dd6e3dcea5b307af58240cd67bf2288e30ee0dd778d4807	1579298384000000	1579903184000000	1642370384000000	1673906384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x07aacbe96b8567a59a271c4e0d1ff901887daf0366ef29ef5f51e405b65d4f0d0d697f4fa992bbca51f3b8dea18cf3aa9a323c3232ee227766f2481a8e79afcf	\\x00800003c96eec1d661e1797bc70758a3807cf99fb58b587900aadf8518454c5bb68da60759b28a685c315e6f01aab754d664945a5c32e7612492cc49c418bc7db3684d6ad2b3046203695ac36fb049f4d080d72d059136e5be986040905a03b438a3a4a400505a89f5b054a8bb11326b412535143f9fa6ee94c9c0b54c3fa4729d65305010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x05c8219ac3a4393c06994e754311d1956d29a27d009bd234c82b2b56be52b59d26caa4fd2891c48238c263e2f5f17eda9e2d98e2fda5486216e7f4dbda6f430d	1581716384000000	1582321184000000	1644788384000000	1676324384000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x92bc616a47eb9f925f9df62e8937ccb6fe2e046069c86e2b6916f99b5f436f3110175c9731300fb8d079e6301dd3791ab9e60b23fb34346882c84d85029989cd	\\x00800003bbab2e207780614fadf82a9a262c9b56f681be085d667effdd9526502395090dff7c4b18526fcda8f705e0cfd4c3e4794365020eb5104b3d402aa22546dfa2b2e8a75013043fb27563e29ed76d5df351991ced5ef0b18f804a249e8a698b47234c3e0aa550cb1158250babf119025c35ff40db1d2a43057ca725753a54455007010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x43aef6a8bb2bec6cbc1c6e9fc3b878ea53d9a368135935465177dda04fcb1376891d337d7b4b358adfdb428fd682c66e309ae067874425c6fd78d4b75ce9c10e	1581111884000000	1581716684000000	1644183884000000	1675719884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdc2ca6948abe7ab739176fde8a6ea8045a6211d5bd4425f1fff75e201269b97f48276cecde114a2100ae5b19eb6eb690de70be8685eb63d964ba9d56a0714b48	\\x00800003bebd84212bc658015d24f8efaff358232e47c27a541d38291a8066c97b03abac83136ac06d7142f9fec1be9a76bdfbbd78bd63c3bcd56c220d6d88b52a84be0603e0b6ed058d0a204b2052db1d301b80661fb17f86b5bcef165b02cecacd3517771f14039f12c7435bc1354e1f1be4c0cca1048c0ae6baba07ab8144eda21c91010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x5281b36f68f1ec67c0edd826c32f206515e5190a43f496ff3ea8fba41285d1d89b5d3ff932a8f22566c3f9644ae9626fb5b0e1abde444f171e2632750c257b0d	1579902884000000	1580507684000000	1642974884000000	1674510884000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2a417149ee14434d047830a8f0bd62d008e790ffe77cd4fab5b3eac16d811ec08b1b1288f4b4fc14e397a62ebd0cf454e99a9cceb4317555bfa575455915f1ae	\\x00800003bef68eb4195dee938015574a5cc7a2753a61bf45cabec169c4c0bf670be5d698b10820d64bf928332f306c118ea45dc8959f194f4a4519788f82b80d5cd73ac7ff71ef1b0d30c8ad303cd09b000bcf205506c3838801a2bb9f573c86ceda6f0de35a5a77ff18156af9e7ea61353e1608aef019fe4af4332119e146603d2adb27010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xac3bb8645065fe116d6b9be2a1ff96a3480d426f93394f6d9b49ffaf545449fd2af8adc2787c383b0add9c9922b34b886defbd246b10de54569284452369d307	1580507384000000	1581112184000000	1643579384000000	1675115384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1acae0321cfce758697d91066f1f73beeccf5b7b870d60365f40d55dbc8c71136e098b7e2475591451f6980352425ff16fe7daeb9808d7190efb77dda21d5e8d	\\x00800003cb0e3ae1c186e6b0719c91287c3459eb4f8d79ecb3fabf5e361fe101ef199146ce5a857c22d861b27e9c5cc81df76fc5d65cc1e95af733f70b6df81e8594cf7ab137f0e7ce2c11d1c3a2d1c338d746549122b601c73dbe6f894d8d8409649fd10eca061b49c4a1748f597f5dea2752e6f9d18c48936d774040e0866fb9ecd38d010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xeba009b8862e04caca4a73158ca18bd5a794bf3504fcaedf86b7f11be497c938285a0280fb6d90ccd8362270d256628e0b9319760a40bfe43012a57409005e0d	1579298384000000	1579903184000000	1642370384000000	1673906384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa2603afdfcb25c549cbe5068b216a1ceb410bd7d756dd8322e3edd3b891d39ce670956058adb007516c800abc262a666d3b545cab0e55e409d10c9ca22fae176	\\x00800003b2a5a12e25c715ca35bd5745d8872f6b3b7d793e8c04a8ed4fd45fda4cc1861048f403b0c9bfe3cdb4a451369f5f4060c319c572395a7d5a158f7565c30bf5a849116964faf3ef8ab17307c3920dbf589082cacb05a7d9ab9fabe826938a59bb7408a08f0a7512c0081b52cd9abef31d59f34d29e2ad0512f763b88fb3dab11f010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x5914b1068df317529fc0842b82e94b9d915faf0e22c52f6375f37a502b3d79ffe4fc2b582e8ac1cd392c7eabe55d9b68eb8b63310afd9689bcda73812cb76a00	1581716384000000	1582321184000000	1644788384000000	1676324384000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe31449442aaf419121016e01efd3881ec6a21acf6acf323930790b5bd6687daf2f848ae4f7a19d511179ba98c96eb4f7faa0b1b62a72773a32fd560e18cc058d	\\x00800003c3365b899d29aba93527b842959732f425d7ab5f5e5bb47503b85ccab4957fafa3a9c704dba5f79ff85a5c79e9f90de3a3f5628b0a5f1b197ae3e54ee8660d828001caadae7c94512c75b45861f6d363ce7417401623fd0c866d0372682752cbdfbfe9394be6cef189314c50a2aa4402b646342a888f8f3ba0a03853fccdbe99010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xb73b659948b67b75ae45fe1bcb284d00ff203fdad2f2e72ea432af07aaa98133f1499596c79993caa4b42da16f2658526c4447cc92b898e7fd3288fe6ff91b0c	1581111884000000	1581716684000000	1644183884000000	1675719884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2aef3210bd447b5c42f108cddf46e8e6880e059837124b9fe58af7a865e5ccb6d519b13e1ffcc69769939b9c600e4c04812890a1b9e28c3840c856516762aa2a	\\x00800003ac62bd56e3a563bd4b788da5bedbaa4cec18af869a1644b77b080753f1bb9a5b6106fce0450f85d735c4e6159e587a08ae5a34686429bfb1214f0cdddca8a00b6e64945025a4bd8c9feb0b0177ca7eace1934a71d1c9e57a5b6c84ab0894fa49e074db79e7bb0ab67bb07fe5476a91414862d798575c63c64d8fe2e9aa726cb9010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x607044c363ef145dcd649b6d925461c6e878b1d221fac3eb2d0a5a7e531f46265d27ea9f122b1216fc41e4d8aef73d86810ce250572cc3ec82dc0eaf4d0f2c0a	1579902884000000	1580507684000000	1642974884000000	1674510884000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x71e9eaa4bc4515a10f4948b674b9f60ed932c82675024e854aaa9c99dbcf1c6d44417624438d8a0bcb71347e623be4ba2a842878984df0057bdc6d68d701329c	\\x00800003cdb6b5a58d780b249da619ab35e9da10997aeed8d9b570bfc435f86b7aa09f96bfecb6bf72048a0ad3892c181a43691f7f018ccc819a89967ae24a7783a0ca6366665eea14d5fcbe3f30188bfc5967f65f80b648a9f96786d9a1b739a786abdc629f1b628e0d7e1032350d2a3ee2eb2210d88edaca4743ed28ea3236499586ff010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xa5095ccf8ee644c306d978189c0fc4d2f809d934f87c5ef9854a16427dcfdf4468a403fc67acbcb2b4b87fa91bba0f482a75fcf73a2940a77a41c0cba1a5410a	1580507384000000	1581112184000000	1643579384000000	1675115384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6929e29a51aca46e32d9aa33d26c4be299f77fc28838d4688d0439552ccd74c20cba974edc66f3dc018980c6940e32f15f5804014913a06656e83ada8136b34f	\\x00800003cda53512404ace2a2ccbe12d08226e3aef1894e337d150f3de6446b1b770870d0fe3719cab75397f5c9d6d970371c7e0625c7e4a25c7f01a2b704d26dbbcff54c6e67a1420a4beacc0fa0b0947c9e58aeccd2b2ec76a95e2f23ae1f680a7260afdceb86bbcc3845c3b7bdb1662423ef2c409d05bb007e5efea469e888e68e473010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x24865d8d162de2909e637aa5a770dd0d5612a8802d6cbd1e225b75a8944cb1a63db81bfc0ca512bed86c362ac5d40e57b54433bc87e6816d2aebb3a92794dd05	1579298384000000	1579903184000000	1642370384000000	1673906384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f2dfb8827e70cf9dada1ef30356a5001dd647c8296ee8f2fb092a56c7cfca3926d727b352190c0ee0ceceb52218f668b1750ad4077c1b7b57b55adbb3db140a	\\x00800003c1bafd7d1cb70d898235720ee27af1b9ca2db23493d1239a8e064875734e1d891e934b29ac6da5b51fcf162e97305b890a56156f061397704aa379748fac70857d8414afcfe664d8fa11529b86c6549e0209ce4e1cf35edbfe783effe7cf2d4f077566a0f2759e3809fee029812d16236e489825250dac8d879e6c4c6fbafac5010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x22b65c2f377e1634e5d309f86e92798cbb2c48466fe10950337686225672bde3ff3c68df8aec495fa15f7b5382157d423d7f2ea07ffa577a9842d66c6370ab06	1581716384000000	1582321184000000	1644788384000000	1676324384000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcf50f84ca735f0abd43c17c0f153c090dbb4a0f5f5e83c5ead50d15edcfa5ba39db792bf65d17c9c43039e3a6a4dd1212b3a47b797c6525ee416d0e105ca6f2b	\\x00800003aae4dde7a0b0678fc4442c4c1cccb115b8adfd42482b1a32c735f2491993e5dd1e9709e39508d2ff4bd4e95257bf4bd23866e72873faed675b409937b57cfc9372f520f1adfd21abdb0e261ac87c401f805bca3302656cd0d9d97e9afec8697f3b255943ef3474469d9ec698ac914d07e5f093c4db4b8f60782409c9fed729d1010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x513b92f0581a4c9aa5be753289cc1f8d0b08b99b8d5fafdf77ff50f2268fd2f47ea168f7cb96d9e1e67e62e3946c7488541ea9582adac93d0513d7bad6a7a60f	1581111884000000	1581716684000000	1644183884000000	1675719884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9387f08e6a7464850cd38dfb04e23d468945df12c5b6aa3ce4a54e5656ddcde9b0c248d8c0a1f060ac6ff64e1e429e0ee219a598f21f6446e72a1042264b3bf5	\\x00800003bb9b6b22c1d4f1de220cb67b61f0454d1ba335fd6bc8a274a6a67d9bd4ef2b4ca0b91d5657eba1fb7fc8abdbf144965818651287d0427b1826b7fc3f8d4992aa8760e98fb46f9d612480dc2fd0783bbc031f9f2a241c4ebfd8630a5a6e9f447ecf8e79c2120d46697d5b7372a59d6647cd68af0b29e54b6e7af33484c2bcf5fb010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x7badd5ae7fc747fccbdfca8dae0a09eb93ca3b62fadf5dac27753f56d229a374de367b644a89c760180874efad1125ebe7c60112d5cbad6a7c8fc4efadb7ed0b	1579902884000000	1580507684000000	1642974884000000	1674510884000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95718b02e35d4d0cb308673a6460a300c15a694f57ab9d2bb47c32e58a99837853142c407c50eee7f931d7f8d1c38951a49b3d58f1349fef5a80116e537dea66	\\x00800003dc73c108f251fef7baa97e35039591b705d849fc99bda6b5bdee766992f661d8da296647b6361c8182b4a3519a5cd61addce27eddc1dbb4fee9895f5527f16ca2ef54f96347f0cc27f54d291e478a9e36b8a5fae4ced04270663f1cdb3715987b62a78ba94b9ad59f921381473151fd49562388574ef97c86cd4c50670e5883f010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\x833e3c90c398111b7450806839d3bf51344ec48ec1a5acfbabfbd78db44dd5c23ea23d2c371fcde4be78af7eb9cc1364e874d570152e7bd29d5b1bd496d3d10b	1580507384000000	1581112184000000	1643579384000000	1675115384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4861d3c7f5025254ac4f88dc2c809f8fde25916f178bea78f37c965b2d75d266520e0bf0eb67c249d5763514c677d682fc989dd4d00f22ea64beb512491553e4	\\x00800003bb946dab55e8950a4f68a2c14bad041488d04fe77019fba1774a943b25e326a8d5919dfef2ae0d883763780c1c6e0e87fd2f35e7470e63fa24fdbcb231226100bbec70f0d0cd6c30ea139ed1f077e16294d98fc1d9edd75a53a157d9a3743c96a11b63475777d653664fb3558d1774c40b30be7519657829c3922d019e583df3010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xcb1f7c26020ea313b72df848b327e949e9d7448d636155ebbe7cbb0f9d314d329d34f845e0a2219866c8ef76848a03d78e7bc855a346edcb420a8d12c8acc708	1579298384000000	1579903184000000	1642370384000000	1673906384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b3be61996223f8faff95fe2d2393d486320a56242c38a7f39114d90cfaff923253ba186be45930e9ac821a8d7a4cb066c4b7f3e2c23d07d330d91b1f2fa1101	\\x00800003ad5fdf207c2ab14a064438b07397e10af7dcde03ab4d4d57ac95f7bdeda95559ef9d2f1ed4e48366128d51891f07648f4ce319b2e81d6679bb24f6d72a1c1650161c1be59156aa0bbb676ed17e0cb34f302b71def92274d4288d1c68129e9debf929244c3e4d374d09c1d14cde5e584d070bd04c470baa87bfdef6519d9e4e4d010001	\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xc0b8cd8ebcb7a2111a3a19eeb24f08f30b56807f7aec267921cb641bf92a45fb770f073c06eb4fe974940896422bd86cf023304380ec99dd14f0ca3661e5ba0f	1581716384000000	1582321184000000	1644788384000000	1676324384000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	1	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	0	9000000	\\x00949d20f997928d04cf2a8eb703733e1521e84ed64c30c38f04dd79145c122a	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xda76b63f311b4252520828907ef080e8859254ee6b90536b0d634cbb47f973dbd3b738fce317f182b5e4108b8e8e25afec6899e96c6619ec85fe25d318fa7906	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f0000407343572b7f000097526c5c2b7f0000430043572b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	0	9000000	\\x79175d4be997fd5d677a3608e0c2a60719316f54e5b4ef431f74bb006624a9a5	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x39008e6a569ef1be30f00bbfcdce7a7fb44fc8e8c15336f29bc7eb3500831c805ee09e0a3b69fa2f8cdac3edfcc8a297b8e21122317bb3ab16802f0517edb101	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f00004043c24d2b7f000097526c5c2b7f00004300c24d2b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	3	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	0	9000000	\\x92462a4eab2cfb68ee65c1701c0cadd4e6111fa5158f43c14025df2392954180	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x622012f4d734c72ac0d9df2722fb0786ab42525b93464acecfaf1e414e818010e22f777269143f8e7993cd0354ec5587e6c6c324f372c049b63be23408d3de02	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f000040c3c3592b7f000097526c5c2b7f00004300c3592b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	4	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	0	9000000	\\xf2232f616dbf5a6f308d7d6738a4fa6d461d472a6cf3c2b4b375849ac76fbbf5	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xe20b32daeb1a3a19df16f0281b1dbf31fc06bd0fdb0b72f4eb2fe4c8a3400f433bc36ee76c8e6f77b2b4305bd702ed553d57e0e5c1d70f73363b527468027d04	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f00004083c3572b7f000097526c5c2b7f00004300c3572b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	5	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	0	9000000	\\xf3191db962ddb4c6e35beb8c448a7a6afa4ae570d9346b206ce8052ab0e7188a	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x44e58609e092b38a4a1fc5b2fbf59c83b7b050189787e0548d0b9c75b873085df4a0384dba27ad62b9cc919f719e9750f25aba2834898bc7fc16c4bf7a06270e	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f000040a3c2502b7f000097526c5c2b7f00004300c2502b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	6	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	0	9000000	\\xab47f0f383c03ec0890a1961bb81e91ccff8d11d466014b84a729ff48679b3d5	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xc50ed3bd6dcb2905cab74327a4143305656106b663bfe21df6aed056a12fb1bd0d91dad4bad0b426a2b3ffc7833a701a5a9490dfc72222c2d7198a7295204502	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f00004023c3542b7f000097526c5c2b7f00004300c3542b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	7	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	0	9000000	\\x463cfd9f595bcb9d08a8c82a66d3f537a66c57640b00fae3d483491fad2e2ced	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xdd64b26f4a24134ead8ef36fa1f931b66e298e669108a1fdbf987f68952669d3c0d55c03a29f27eb950e58ccd43477f88ab21b6e2b26ccfa8b6ca424b73cf703	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f0000403343552b7f000097526c5c2b7f0000430043552b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	8	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	3	18000000	\\x1a781c8120e3bbd44bc1f14798b104679a82162eda76944431b48d985ba25715	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x86596a4cfd89bc1870d7454729ddd9a95fbb45a284e77a7ddb9375e7d76ad408d3c8847c379cc1afba742b045760be242d2481a0445e3c499292f2b4c4ec0f07	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f00004043c3552b7f000097526c5c2b7f00004300c3552b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	9	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	1579298404000000	1579299304000000	0	9000000	\\xc77ffd47661ed3397de85f07fe6d62423263806c2f2f77d263dcad995851dc6d	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x21e65f22492bada0b334778e467a6d56359b039820c2c9797c6d5f0bce5334b2d9ec7aadc68dcf30023e545f0d080a685a419b548b127f92d4f9170cc037280b	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x73bc815c2b7f00004043c24d2b7f000097526c5c2b7f00004300c24d2b7f00006f516c5c2b7f00004c435f4d455353414745532f676e756e65742e6d6f000000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x00949d20f997928d04cf2a8eb703733e1521e84ed64c30c38f04dd79145c122a	0	10000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\xbe5605b63c888bbe57cfb50f0719f814091c9aa2138197f4329385c658e9682e0fd807d17104cd55816c28066ef8467ee0533e2a5262cf894b2ce431ee5a1e0e	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
2	\\x79175d4be997fd5d677a3608e0c2a60719316f54e5b4ef431f74bb006624a9a5	0	10000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\x9f46d7419a6bbc9189a8a6205c636ba90f0458bd225ca1abf32ec57fc27fc5b78122da4de3f57df7fe4aa8bb52cd4ec746e97731e1fd8a69b10c0210d406d301	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
3	\\x463cfd9f595bcb9d08a8c82a66d3f537a66c57640b00fae3d483491fad2e2ced	0	10000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\x181be1fa1f668836306a9fc485b68767558c14a1b520472b386a670b76e4e869a9caf40ffac417c80556ab55f1a10edc5c0f5eaccc02f58385da4d41eebf3506	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
4	\\xab47f0f383c03ec0890a1961bb81e91ccff8d11d466014b84a729ff48679b3d5	0	10000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\xf28b21e216d711412caa8392f3ff4aa15d18325671d38f8da9c9483fa8a870db4219ecf2ef2954df25ecc158cf048a9279231c86681ccee31bffecf852375304	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
5	\\x92462a4eab2cfb68ee65c1701c0cadd4e6111fa5158f43c14025df2392954180	0	10000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\x4ac267da0e7737c1cf42793c69a3f3241da738c87b1818fc40dfdd97e0ff2e769a82a23ef78d86345be69eeae6ee6459ce64a3b7186aeb0aa414bbe05ed0cd05	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
6	\\xf2232f616dbf5a6f308d7d6738a4fa6d461d472a6cf3c2b4b375849ac76fbbf5	0	10000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\x7d0704cdd1dd0305560646827b0ddc97f4104c0c8f061d6f4bea78e205429202a0702c23adb0cd7d7480e47fb06ac6dcb138f53895e75970c264ed176160ee08	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
7	\\xf3191db962ddb4c6e35beb8c448a7a6afa4ae570d9346b206ce8052ab0e7188a	0	10000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\x391978a8915088baf5c766b6b7c9b23e47207f88346f32fdf53b0ef970c65ff6ce1bdb35508d5a230ba74b9ba6f2a80e41565afbcfe7f9b2e8ef5ffa9b526401	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
8	\\xc77ffd47661ed3397de85f07fe6d62423263806c2f2f77d263dcad995851dc6d	0	10000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\x56de3e7b71b30e09657f55375e2f8c998b274afa0495b28c04bbda553fdf1b309f9123c593b07b4ae3b46ffa00c3e846afa056b9449e5e6bf2173900f2b7b802	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
9	\\x1a781c8120e3bbd44bc1f14798b104679a82162eda76944431b48d985ba25715	3	20000000	1579298404000000	1579299304000000	1579299304000000	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe62665cb6a4e5d7367bdc415091bac6df2ce4c131f2de6a3ba7c39c35481c4591cff961ad5eaf53f2ba34f851eddc52833258f7a0722cbf9b5eee7a22434c775	\\xa151630108d4cc30d1d83af405afe521bc07443fedaab4759a6513fbcdd1a34d64b60f2ffa492b8fc69529dfbaee7b06d702e3d236d2fafc643f2d47ff7e1a0d	{"url":"payto://x-taler-bank/localhost/3","salt":"NHQA9V4CDSRER8VP859PE5MA88QMVP8YYR4DQDHYDDQHTXGVJPZX26F92M3AQD41CHGM9C0922KEKRQP6CXT3MT6P5AA1R4VW3REMYR"}	f	f
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
1	contenttypes	0001_initial	2020-01-17 22:59:58.035553+01
2	auth	0001_initial	2020-01-17 22:59:58.081917+01
3	app	0001_initial	2020-01-17 22:59:58.194099+01
4	contenttypes	0002_remove_content_type_name	2020-01-17 22:59:58.230483+01
5	auth	0002_alter_permission_name_max_length	2020-01-17 22:59:58.235925+01
6	auth	0003_alter_user_email_max_length	2020-01-17 22:59:58.246125+01
7	auth	0004_alter_user_username_opts	2020-01-17 22:59:58.257154+01
8	auth	0005_alter_user_last_login_null	2020-01-17 22:59:58.270403+01
9	auth	0006_require_contenttypes_0002	2020-01-17 22:59:58.273463+01
10	auth	0007_alter_validators_add_error_messages	2020-01-17 22:59:58.284235+01
11	auth	0008_alter_user_username_max_length	2020-01-17 22:59:58.300067+01
12	auth	0009_alter_user_last_name_max_length	2020-01-17 22:59:58.311088+01
13	auth	0010_alter_group_name_max_length	2020-01-17 22:59:58.321352+01
14	auth	0011_update_proxy_permissions	2020-01-17 22:59:58.332532+01
15	sessions	0001_initial	2020-01-17 22:59:58.342599+01
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
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xeba9bf9ea70620372573573e55b0689decac11b7f6dac7b414344a17ac36a2015565fb0d587b281fde964df60c5de60b7ac45c71428d8e0ea9360416acaf0d09
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\xe659977277808acf8fd97032eb358bc4079061b096774b52b534679360fd53c1ccbb67bfbef33a398a11a7bafeceec4def3fc205d24a15f1a5aa675257f29d0f
\\xacf8be23e5a850c6453e93a012451382fccdfffb16810d7281654f2bc9d3bccc	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xa53363017a3401fccd9f8064180094f83e234c0256a7da0480c2c5bc5527890186b4ce8830910d127e332a360371b18bcd52f966f64e65b3415313cb47a8830d
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x00949d20f997928d04cf2a8eb703733e1521e84ed64c30c38f04dd79145c122a	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x9483d6401c4b495595fb44289b3b88ca12521d785a7860a17f8feea7797402733a1050546527714f166a1f9afcd48d9a45b5f0a70612eb64caba7d58889b846b4f763ba4584c7b4c95bc6cf56ae4b703fb199996b955b0e247eb5c0f719305a9e1514c01f2295e5b923321386a49c00c60c77fd6a908fa8d758a314e938cce6f
\\x79175d4be997fd5d677a3608e0c2a60719316f54e5b4ef431f74bb006624a9a5	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x6ac12ac5a2447872b4a2e4dfc2b2abb02904903dc0a5ff759c5c366a62ea295199570cffa4c072e8a74b030f22ee39850c4d63bf3056fb0fb6636218acba3a9f2413d7185573b5b066abd4d90f8ab66614bed614c54e6a7f8a4084b977bb7d6741164fe6c120b13ee3692b5b4efa1d0bc7eadbea2563ca37d11dfd7f7b7570d0
\\x463cfd9f595bcb9d08a8c82a66d3f537a66c57640b00fae3d483491fad2e2ced	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x480f69a2e15496977a362252626e1edd1204bf50c2845e08cca61653a12e0d87b8ec2badbdccbe4b090d64c9cc6ec5963ebff93220278215474587d211d144d8637997722888b46df9f15c1d40fe6513601acf3ef904cf1890f71d65ed988c9d728915ef708a5d95bec45394e3be477cba0571a4769254b08504b25dc3cd414b
\\xab47f0f383c03ec0890a1961bb81e91ccff8d11d466014b84a729ff48679b3d5	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x082346f6dde80c7de92936bfd34150b994d84aa5af1980015b3c992277b37626ef9aba53292908cb4a0bd1fc59169f79188a2367002edfa4ec4e90164a2b645ea6f8ee067beb281aae1a3d2499420993ed741f04b5c54f42430a763df52a21c7e068235e3baf8f25c14420cb5f55157aba54ddc97a40c11dd5ec7d0c768e1322
\\xf2232f616dbf5a6f308d7d6738a4fa6d461d472a6cf3c2b4b375849ac76fbbf5	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x5793c5ccffa7a21399c5c32104c8850e69721645b2adf34628dfca84dae24355d8b74ab614065d7cec96d025ac84e83ca96dfcac10c7b330fa1d26355a2c45fcc4b65c0c37a261259aa0c66a6fb51fcdc7b4d92cea080719923147a308a74e456e49bda5d964a030ff08d336ec7f3de55c49e706254f351cb21ddbf3eb68ef74
\\x92462a4eab2cfb68ee65c1701c0cadd4e6111fa5158f43c14025df2392954180	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x554f7c2ed375d2965d4df9ee44d41067ce385d534e6dea76870b61f9dc3b7bb02d5d8def8eb9c6913d6e1208abe2706f96b5347e83545feb4314de9e601ef0c75e3b4facc88a91fd9f5efa290b7bf6b96f402d6876b2e94e4ccce869c35fa5339fd8679f6afbb3921a2b419b3442aefa004d57e388a0c9097a898b88f3c3f19c
\\xf3191db962ddb4c6e35beb8c448a7a6afa4ae570d9346b206ce8052ab0e7188a	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x4555a1cd44576a4db710fb9c308764915498affac83f29c680fc1b52a115cbe00673766182bdfb959d63b06ab9957a3f5a4b8ee2b78f70a84acbe48b3815a010842874210b8b752d5f8aa7281c5b130c9e3954bf7bdc0affed3880df7c6af1ee473301f36103e6303aa68cb97ac9c3853bf8e2c67a721eb96a4bcdce1c2add59
\\xc77ffd47661ed3397de85f07fe6d62423263806c2f2f77d263dcad995851dc6d	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x2d3bf18ab5d81144306cdc9fc24baa820c7cfe750311d5ee214c756f9ab5712a037a7f80fb6d7e628c03a26abf41bcc5f6a2113f8c028d95d103045fc18867df2b635a6160e96a3e4dd3ee372e566d77ed01b2c8a677e32be720ec0044a9bc2247f80c8633c9a697304d029b6bd991221b2e2200a7e8cd7d61ccec22f59a280a
\\x1a781c8120e3bbd44bc1f14798b104679a82162eda76944431b48d985ba25715	\\x01bf094c74f50f7d6ba8e68eb6742916f83e6417762ae1d7e3db81f2c5af22f1640b8807b31311655dc90826d946198cce1745650dfba54e1b50f90af18feac6	\\x86139bbc7351a147843996bfe29f5b648760a64db2c345626a0f9f8b415d5abea981bf41854d21e3af6560e5b4c198ca9eaed0c4e02395de492cd420b0527b83fbb8d0c99fbfd5d011a077cb412453eb8b9dc988bcb27900b904a24a74bcb0ed113262cf5d0425c0c99907f700fca0256c8cd2388259031b48c6690d297911d9
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2020.017-80GDE3RTJ3NGE	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537393239393330343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537393239393330343030307d2c226f726465725f6964223a22323032302e3031372d38304744453352544a334e4745222c2274696d657374616d70223a7b22745f6d73223a313537393239383430343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537393338343830343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4b574257385a354e313843434839594a4547313448384b47425943565a5a563254304754574d31434e374a514a454b514b3630227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2257524b36424a56413953455136535858524741474a36584344515343574b304b335750594438585446475757364e343152484348535a5750334241594e58395a3545484d5a3138595651324a4743533548585830453850425a3654595853583234475443455838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a225745343241333732535843593041444a5656383353504741595137474448433837303336505a463645445253314b4e414a5a3930222c226e6f6e6365223a225a363430323037394752455641444e44315a4834315335585a51345136334d34434e365646334747474834344437514554525147227d	\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	1579298404000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x00949d20f997928d04cf2a8eb703733e1521e84ed64c30c38f04dd79145c122a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22563956424346534833443135344d4738353238375857343058323253344e374544453835365452444344364250485a5345464458374453525a4b48484657433250514a313132574548524a545a5633384b374d5052534753584a325a5739454b333358374a3147222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x463cfd9f595bcb9d08a8c82a66d3f537a66c57640b00fae3d483491fad2e2ced	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22564e4a42345654413447394d584243455944515433593948505351324b334b364a343441335a445a4b315a504835393644373957314e41573045483959395a424a4d3735484b364d3648565a48324e4a33445132503950435a4135505339313450575946453052222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x79175d4be997fd5d677a3608e0c2a60719316f54e5b4ef431f74bb006624a9a5	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223734303857544a504b5652565743374731455a57564b4b54465954345a4a37385235394b44574d56525a4e4b41303433334a303558523459313858504b594846484b4443375646575332483946453732323448333259584b4e43423830425235325a5056323038222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x92462a4eab2cfb68ee65c1701c0cadd4e6111fa5158f43c14025df2392954180	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224338473135583651364b334a4e47365356574b4a3559523747544e4d344d4a564a4433344e4b50464e574634324b4d31473038453442565145394d4838465745463639575430544d584841524653503652434a4636575030393656335152484d31333958573047222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xab47f0f383c03ec0890a1961bb81e91ccff8d11d466014b84a729ff48679b3d5	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22524d37443746424453434d47424a4e5138434b543835314b304e4a5032314e5043455a59343746504e563835443839465036594756344554544a5844314431364d41535a5a485733373952314d504d4d4a33465745384832524242484b324b4a4a4d4734413047222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xf2232f616dbf5a6f308d7d6738a4fa6d461d472a6cf3c2b4b375849ac76fbbf5	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225738354b35505142333858314b51525059304d315037445a36375930444638465643355135583742355a4a43483854303158314b51475645575850385756565150415433305059513042504e4146415157334a57334e524645435633504d4b4d44303137543130222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xf3191db962ddb4c6e35beb8c448a7a6afa4ae570d9346b206ce8052ab0e7188a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22384b4a52433246304a4153524d4a475a525053465158435747455656304d30524a593359304e3444314545374245334b3131455a39383152395058324642423251373639333756484b54424e31574a5451384d3339324342525a59314448355a46383332453347222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\xc77ffd47661ed3397de85f07fe6d62423263806c2f2f77d263dcad995851dc6d	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2234374b3559384a39354550543143534d4559373443594b444152545350305752343331434a594257444e4647514b4a4b364a53444b5633544e513338564b534730385a35385152443130353647504a314b44413850344b5a4a4241464a3552435230564a473252222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\\xbd861d69c47b106bb6e55a8fc4a71b7d30ca365764660cd266547577907598cf5bb03f96b188501858922bf5d706e93554da4e2e255a89aa3f7288ac2dad17ea	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x1a781c8120e3bbd44bc1f14798b104679a82162eda76944431b48d985ba25715	http://localhost:8081/	3	20000000	0	2000000	0	4000000	0	1000000	\\x94307566f937bc079f0254c44d434675b6f93463011f020bc16ac12e22e84fc1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22475343504d4b37584836593147573651384e334a4b5145534e35465650484432474b4b514d5a45564a445459464e564154473444374a34344647565353474446513954325031325143325a323842393447364734385148573936393935574e4d524b5030593152222c22707562223a224a475237415351533659593046375232414b323454475436455056464a44333330344647343259314442304a57385138395a3047227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2020.017-80GDE3RTJ3NGE	\\xe388250ce2cf59e029b2ded03cda0af5cf06c58838066b7de6737190ceaa97d2	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537393239393330343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537393239393330343030307d2c226f726465725f6964223a22323032302e3031372d38304744453352544a334e4745222c2274696d657374616d70223a7b22745f6d73223a313537393239383430343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537393338343830343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4b574257385a354e313843434839594a4547313448384b47425943565a5a563254304754574d31434e374a514a454b514b3630227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2257524b36424a56413953455136535858524741474a36584344515343574b304b335750594438585446475757364e343152484348535a5750334241594e58395a3545484d5a3138595651324a4743533548585830453850425a3654595853583234475443455838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a225745343241333732535843593041444a5656383353504741595137474448433837303336505a463645445253314b4e414a5a3930227d	1579298404000000
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
1	\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	\\x1a781c8120e3bbd44bc1f14798b104679a82162eda76944431b48d985ba25715	\\xd2a13ec0f783ed228199cbb4cdf9b69bba6da8c4edb26379ae5a3e5857ee18df36a094920bfab4114b91173738694cad4548137c0179e4e56482239967639704	4	80000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	0	\\xdee90c43d989d5d59cd22afcdeb96b4f0d6547b461fa3bb1dd307701a3ea5ec0f81df9a7cad9ef9dda1a430a168261a69b35064c32705637f7d2a2de9a4b1b03	\\xec0d34e4a035b58f36212af25dfe36290252473c0a12099782b546a0ce93e8c2e310ae63a78c9ea9a2bef3d89d893e0412c3fbac3f34af1ef4a8af36644101fa	\\x576dbb4c9627d5ac87c647d15f17239cbbbe5c2adfa7e61cbad4e0ab40d25d0ed6a51fc539de4e688667e765ca2a50262af5b2fc37643ae937cd9f07b602d6cc4b99d4d3d2c4f3151a40e93f3086810e2e687684ff13d5778dfe2d40303e8d430e2c5f97ff679110d2bd35aa65b9662b670e2ca60556dd52b2aabde08019f55a	\\x6812a83459bff3021d936553f93094b925b45e7733a614da84a05bc1efb1d853dc89c38c96aa38319986b066418496a65cd09ca87c16ff94fdfe7db18b0bb785	\\x09f9b86658491fc6c135fcf57b47e3daaad2317b19923d71740585d36db002b76d9c5691832270db93e4639f3073866595760242d09d5dc032c706831e8fcfe7eb9f9e193bbaa8fae3684a26fbb14b1748f0eaf320ca30642a82e5f0d0d062e954565e277bea84a30c3a37447392c1e8e873491cb7c8d6aa31556b42f6648083
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	1	\\x24365d38a12f726393be2dd398747a5162f3d70e42d644e30d021c82695c3ccfdff84b594b65a8ccdfd00e74ddcc6024b34137039413747dfe89f802646fee04	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x313ed194a16b140fbb62e7b5bf87338dd034e5ac198807e147fc74ffa43bcffdf57f30bb8d68453ac6e5aa56b98d31d4cc8a3accf4dfc72fccf027173a0317397c102ef8bca848ad9b698ff0aecf636cb9cceaf1e8c9a8c5d40147f8cd7b63fe44f507edb25c7f82886d61b647999db9d9c9deff7557eb5b5645e7b3b5d4f158	\\x6fdb286e6c09bbc99b362a9f65d2879bf2a7b02303fa845fac492e8869cfc09947a063305acbe703825065d17f1c6fd1ef68469bccb252c1b7fffb0fb8323df6	\\x44bf2dc9df43f58eb318a8729f652fd56dbbd4e4b87761c37427de5271f26d5c495fbb17e49c877add315bcaf3cf0ef5c0d0c1476692c18388927cc92c280dd2d03d27feff74bff2a72d4ee3b4710e73a543356615533498620254d21bd18f44c1744e130a80e6afc821be331b83cc2d6f396f3b722a7f907d5ae6adfe7f5824
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	2	\\x6c68f80d2f75439311345fe0f9837d71e580cda4d2169dd5bf9cad3ef4b6b243b171fe136d49f90829b08a790602a277327e12e87facccee58ff7bba8978ff05	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x8e24b3e557974ef891b4825879663e5b3f2d331041301d7d6f2373613b5f08a8873d0ec37d69605a0b0acda33ebb9e40b8da6efd2992be0760a5709c5eedafb6d17b22a145223aef817ab7ad4c2c3a70c2a50b0c36cacc368ecb6fc110d724e11ff004df43d470aa93a528e7b67eebc46eefb2025fc3725db50d1d43ad67dc50	\\x0facbbea9ceb431a73cdefd3faa55e882c5f15685fea39a6ead02a9653d2ef8707256cee61899659e8c7df32b7dab181345cc32e197f48d74c9bb46139c869c1	\\x46f8f9ecc274873e58486c07b0fda5b4b4db3162ecfdafe35c0fd001f39519d027be5b00f8814c21048439a4d42b5c1917224a2664cee7a39b1f9bc4b4f587d0bd73d4c02b6d2462d95355ba2cf74a812a6e5e63ef3e66d884971b9aed648b9dc2da1082cad8029fbc697a6a9aa5d19a19178af42d74fb83d59bb66b9cce6f24
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	3	\\x9c16133cd51750761403ff8cf8238e78856e187f00e4a5e17ae11b912bf7f5ae26327993590d1be9e1c0c43097d3e64d07c5a9dd3e0849587ec689fd86625b0b	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x1f4c55b71cd7514d3658cd818a19d01b0799f978ac9066da368cb45c8e21dade36867d7dbf899701ff00927a0a0284b3bdf721cb1b6d7b4c02f820c2789d209aba064da543afe88d28a9ecf6a519a69faad6b91040f675ca8454ab1a48c04ada79123fff0bd48dbcb8128ba7a212f9101133f8462274f18876f8c9f4073df119	\\x1aacf1a6d50e8a0de295691b34d9b60500fed628f8b9a323e4b472c30cf96b8b9f8a4d410b7ad2784c2aa7d83e5b11fb3d08f50793f65ba45d816ada82472df6	\\x2b5e07729f3f045d0ed33b6f007be5f1894484b6155fa27cfd5f383056ee969a22eda279a9477e72692e35b08ce4a54d832e41baf4e687a30b3a0c0930cd4c31a4ff77b28a49a588bf3055ee5d386a9ac7303bd286f603b6d1667ca6d95c35f5aa814b644a132af022b4d5bc09a1392ab6d5f81ac2ca52cef07dd55f9f2e7f3b
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	4	\\xb23ccbe9dd793f28ec4de97fd0c9582ba1f2afe6b44855406448963bf64a4b05c3b5cf8dbd2bb0d07a6434bd19c6b1a8a533bf55d15c30b4461bc693955d2704	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x4c81de45cdcde9f24d4da106c47213b7a2ee6b12f3029a6a5a756a4a8c943e8a117624342a2d96738e3fc57a03294cdf08b3ba6663d3849b91fb3c1ae3717cf9344943b67aeeccd811e7448562e000cd1030fa76d0b9c2d38be7744ea1014ad44a0ff0a44cf2586e6d4a044af3e5dabc8a90f29d92baca3a711bf01eb7f08418	\\xa8a01dedf2b290fc8b318d9229bcd0a0cc51c88bfe19acba26c216d05f1d42422770672a80f933e46572c3a6d892244cedf6c4759a102bbde210d2f9c2e29ddd	\\x36e984bef83a715086602291ca44b1c2d311608a753e6fcf19849a4483a4df06323d223d23f57b5e08108af9b56045f1b9c0212d39e4c77bf1b6f0d64de1c9b7673cb462f2aa65ae4ac191f825e5e1f6d235be47380c5e9f760137e9f207288d927f97581534aed1776e447115b09f62adc9957265670783874848017ab58c55
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	5	\\xb0f8c917a00c8613e99cb2affe3d3f3b7f99417bc17b017d9a46a037613bed0715ac0f159fbd810f1721b0d4cc6fa8e749ed8daf747c2904fb630f95bfd01006	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x21e0a08fc2bf3ece9e38e5d2cd5ff4dfc99fa4530f7f75b288915ec511e8765edeed8c7295b58cfa2be622a57dfe5f200f54c11a5c8f1cdc43ab969e1177c4c22fba607d65c0832b66a94f2c019275fbd17f8fccb7688fb12b6f5c985942a717c53efb8c8cb7ebfb6904b33a18d66c7ae5f26e7e8ea60e1295b7c8d358288a68	\\x7a1a11904b533020d9964d7af25db0f69f8a7f703e6a500968c5eb17988983247eaecafd12d82afd9138e96155ca9d76ad3adf8f885acb1e9495c3c25ac7ed96	\\x033ccac7b0b31cb3e5b8c32cd5e02c94a6dc8b0eeb01d721fa85335203369b56bab077d9fd44917b3279b2fdb9b77924981815458a57057481b24bf9e0f20a6c8b0fe7ff5cf3221931a725819afb40de75b6c6a20c60894ea1308ea1a49b7de30b4a84af1fd027eabc549d063d34d902ea2787f81a2341d8da054aed320a611f
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	6	\\xf713d8e6ac9ce9e2425dafe72084f10633db8b4f4003ff6d30239d291da713b78c725398c753b0e800980196d6c31ba013ba6d2bdb4807ec59ef9554d685a204	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x290a6e2ff7112138fcd6ebdfb642d7727ae38504b3468ae0d2d922bbec0272b2610910e4e1692e908b0b8c9e19ea8858119ca60f85ac97152127a4f313d35aff1eec60dc6071b35d50fa9a186d24c4566e74c87cc4c7b554a215a5ab7cc4d541e9ce8067b90cfd0d512a0b6a85b9b823476b8eed60bfa9f0c521757e05d1929d	\\xaf8e04ebf7899846aa5ebee674e9f19c912d8df8b85017aef175648b87d1226ac893af603ddf0dc85f411a2e78b80cfe292f42937cee4ad53a68c4ff53ad2271	\\x6e207f940abd4f3350a2ead94bf660e3ef4e25797b40b1ea0791ce8369794ef1bdb7b3151f75a1c76ddd12b9514eac51e30cbe5bf198f3f07657ee21b1f7c68d9b7c4bc654853f71d982d5e69b14060f0d56ee278ea6ab51fd1b308963d68e0b0b335bf74e3027dd3330fcc0ca26df5d6a558567561b460ea8a5131f101f7f6f
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	7	\\xdeeb876e603f45b9fc651e69356401681193c638486a13c40ca7a64ed983107e8d59058d44a6dd3edcfb8c7e6bf6b5d0e78e7cea0147beab4a76045b1d19980f	\\x1acae0321cfce758697d91066f1f73beeccf5b7b870d60365f40d55dbc8c71136e098b7e2475591451f6980352425ff16fe7daeb9808d7190efb77dda21d5e8d	\\x6c68fdabf38218738c407fbc3089c25dd3424ab0932b368332e10107083655b4cbf918d92be18a8de7c99541daab608b441820b81a07174f5d7a9e37bc2c6f05e0416aea35bfd9b784b2203d0e4fff909156d7740218e49a343d9fe50fa6ddc8741a133fd80e869cdc76bcae6f77c87279bf33051ce572d3c5fcc5e3ec730ca1	\\x4176dadcd71a5b06023b994d4bbe1c5dab9e10cce31b740bbb362fbd7bf6a309841ef732fac52431e42c46c1fcb5b8f2d1e0e2f9de27ff470362e6a48d5e318a	\\x68aad040ac7c32c95b6c1313ee6456c3c29b910175f7e3975f99f94e5e5991f432f16c78150d25cbdb32ccfe6bbb8c957492372d3eaf2976e73ac84ad6d0dfa214834c46e5b065d316732fd56533b47ade832b11c34666744af36492ab5ee5faca11cba5fef817831cff48b1ea7688e70674bf71c9e82b84b4bb7b5b9e63490d
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	8	\\x5cd66fd9893395e27e758dd0329a71ade9066e68abeb273d975205d59dd127e78666e89671b09bb9081e1d391e8df57d3fe70b825b6be181e7b22b8222fd9b07	\\x1acae0321cfce758697d91066f1f73beeccf5b7b870d60365f40d55dbc8c71136e098b7e2475591451f6980352425ff16fe7daeb9808d7190efb77dda21d5e8d	\\xbcfee240dae6073a2992088073a47500fb22fd53007e362c155d4e48268681b8c865c4987e3da8ebdf2f312ca169a6febddcd5918e485e1bb6a43fec316c085e7932e86967a79cc19f726cd15fe092b197b67847b277bb122edce63c4cdb5cb7523cffc2997e03f72ff7a4b1001e1e1cf19df882ee35260a0031c4daaf17f8f9	\\x4ca94db51e8ae46a89ea5238f76e51ed3df86c2e5c7db2c7445298c513f82b25fdc338d91da8321c4a048eba62ef98acbb7564061121febaab99990b1d035da7	\\x4b9fe1a0df43237f67cd594ddce4ab714655e38809090e20cf25ef93929b4d0e43fdd47e678af8d2260e64883690e0576b3935b22f16b860fc13f16737d95140bab2756d68dc6c5144ea1db7d7ae740aab4b3643795f584e41740764349e97bd3c7f37a2f3104265ae81eb959e2bd054a07d8aa135dd552d3d47441bae9caa1c
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	9	\\x91f2deee70226b855fda81b9d965aedc819c8b9401d972839ce870428586d4cabd27017257d96bebc79c11b1c5167e1f1a2d522b24a9e57a08ed49a853944802	\\x1acae0321cfce758697d91066f1f73beeccf5b7b870d60365f40d55dbc8c71136e098b7e2475591451f6980352425ff16fe7daeb9808d7190efb77dda21d5e8d	\\x048e3a42fe96c0986d390e6cafc61d3cdda88d55ee66e67d166dcebcc5eae56a118dbae8049ad4f568eca878ccef9d89a1caadbb3f68bca410bfe754bccd4392eedf441359d4c2e120138f219188b05ba547c7a5a0da3c78013644cabc57f15a757b302c05c6ee8c3e5145b56a26f598c4adfc96b62e2c81c480a7a0c7152549	\\x2e0511ba33d434a3692a5dcb7e3cc2ae6232a3a77e6a2eba76860cca6b14d00d0cc37a4f920bce38cb5dc97197cf3173994fedcfdfc26f5d76a67d20e995ce46	\\x7804646a8e6b4884f15678a4451e802409a97c64c709786b3fa8fb0e55efdf9b7a38ffb0aa1d463af02ac01061bffd214fbbfaab148b20e5351b5419c220cd187e61b8eb2a635ce816154f12a3ff7b8d867966daffc2546842a30850e1cc9f5dec95c264fe6bc72b29cb87f294d863b0be4d33835ed11a192ddc39e47afbdceb
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	10	\\xb969ee332ee2c04518992c033e216badd01cc167104b63b99e96bf4f98f67906a09474f913d1d6c51d989a61094f7db3f313c1abe4ec77eb5d8a8838c0580408	\\x1acae0321cfce758697d91066f1f73beeccf5b7b870d60365f40d55dbc8c71136e098b7e2475591451f6980352425ff16fe7daeb9808d7190efb77dda21d5e8d	\\x83f2149589372ddd49683ad1bd90738fe1165c3890d7786f46e637c8492038d965cff6fff906100ee03e04107ae2438b8fb9ff9d643b64f0c380e5446ec6136254425d7c806aac95d3d89f197f33b219b213b9966e20e0d96135b64d5c833dd47473437f2a0d33ed345b3f886cf42c8e1e6083e9c975fc893d67776c38e2aa22	\\x9886382a9b525aaf5dc55797d7c4917f15c534f88b3eab67e4bc567f3d22bd96c82640905bab393e31ab8bf394a6111797cbb6e1a6ab654c698b1575a87c3484	\\x9ce13691f05f675084f076c74583890cdb6f264001e2c1bee10114ac43c500762259c284ff9340ed1d6126ccdfd73adcff5a0f7703a1060fc96f41f320e2da3a9574544fcac9beba1ad84e857cd9e4eeb53de6a8a108815d338a8e704b7f764dea1d9c20af79e7854574baec9317fcb0cba38cbd59667476c29d2dbc3ac10695
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x806ec747ed2f9636f8e8a5217c868083b659a75eae368413ab4b51f4c9fee32ba7666d1ede4caa7b55170bc207788714a064b0a3a3fc43f9217e50d429364c0d	\\x5766a055834b5d3e0bb214baa4c00affdbe2ae2ea08804499cbac921930f434c	\\x1b3f05bdb491a5d47c320d3c21e65c1ccf06e2a2892624d6e631d72306f9da1cad33d6d759cdd1e14f0c60ff88402efed95b04f80b7b9245dc739fa131a54579
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
\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	payto://x-taler-bank/localhost/testuser-ggYai0m7	0	1000000	1581717604000000	1800050404000000
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
1	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	2	10	0	payto://x-taler-bank/localhost/testuser-ggYai0m7	account-1	1579298404000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xfb0abfdeea3323d11bceee4c284f1a35b51995b1526beabf539cf3e0e7776fea404d0cdc6469da77d1b00ea45d9988886c4e70eb26b2d79867592d433bd94d1a	\\x01bf094c74f50f7d6ba8e68eb6742916f83e6417762ae1d7e3db81f2c5af22f1640b8807b31311655dc90826d946198cce1745650dfba54e1b50f90af18feac6	\\x8beb184c41ee2c941742adc1675ebf9c2274063110b3f2f8f7380d9963f2f80f72917564db59c0e579684b22df4346d0ff8e2f21c3f3d614f3af355da6ccb6e6c25b02dcdcc70635f47cf4fb6fc907dc20df744d6c1d6dacb14929ce2d4a814986c9b92878528556da769ef17b200b2274b6a96a775f40f291808a72d128b1d9	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\xdcc43a6b59d85c9764acc5662a79b32e9ad9bae1e820e13246e5e32561c8c1c698c9d9ea39f812a32290b273a915277ceb346d60e5180bdb3f11f81fdc78a30a	1579298404000000	8	5000000
2	\\xe9d5a8a30c9415bddbf3974388719fcf377fb8f02d87c1bc329c3578262d4f0637434eae3b515dda3f96fc24a216d2df82004f82320ed0c54b68960b73eeb1ea	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x0186e285043def2668080477c29eebf4a47fb0d39d9c3ee17239e5287ac9b50c75737595fdd0080fe82e6183498b62be1e8d7752897e60a4ec6945c9979edad6ba432c519a39c5653dca100183a57153351b0c119ca5a5d9d60a9fa46d498dde9c0d50d3561c86e9b18fe20fb0b5f27a1b385af2d30e5a2c5552dbecfd9117e6	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\x4c004d0855fb2aafb4668c0ddad049ae91737fedf535e3172a1ae31f0eb67f3830d669be0345d7674214bad7e1d0e1abb0f66d54abb6e8908291c7faef1e9e0a	1579298404000000	0	11000000
3	\\x048459e4c75a746a66397a6f3ced11fda77f6b4d3a23e593d31c046b5dec5c825407186e07cd14f50f1ab126c0f5e966b3985a4fc75dcc845fdaadd5ce7aa28c	\\x6929e29a51aca46e32d9aa33d26c4be299f77fc28838d4688d0439552ccd74c20cba974edc66f3dc018980c6940e32f15f5804014913a06656e83ada8136b34f	\\x56bd5b88b00ea971ce9311b2c672f01fdf47488bdd8aa4d664c0786445641883b1ff48e1f0ac2e37962b9568306c242a7f70de7adcce2d82037e74ebf60293513c2702441f4c8557e964b67f20d0fb9294b62e0791211bb9cda1f3d0c8b1d992977fb9945c30433ba336066d9b6fd20cce73dfe9986d7cd7d818e6640bd2911e	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\x781438249655909e319dfbf7bf5b8a48ef1929e8942ff01efb06e03f6faa5836f40ed6f723283483680d686de3ba57941d407e4555cfb61fe604850b8e93dc0e	1579298404000000	1	2000000
4	\\xdddce4dde2ddd94ec2d641afdb50a3df0885f1be47762199fd9af765c73c8ed474787c0ca879c028a8d05d50832da14d480cfbbe5672aebeadcdd3665b26a4d3	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x4e85afeceb2443db465430288891a7f3e582480464960f2259b22ea1e145e0cd7ddffc8442f6c00c9ac26acc1e2d43ee33e3822fd29484f59b23fd31cc36822fd2e08fc1e1493c98a89f3d724388633ed0b7670fe5530200d3502bcfc1007135f9c12401c46b366b3396d53c9e31d8670103c281d1c244a6ef9d038378c871f3	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\x38eae54b612e43f415f02e334d7add89b256ab5eb723e6974fd8cc24345055d4b7adfb26fe60c6923002169ee428ee0c60c15c444a2d304dce251cd4fd17c309	1579298404000000	0	11000000
5	\\x928edbffa439124977679eb1422bcdfbd87bef9c90495605fe3b158feca0d0b21a5959a3b024c455f6fa4efcfcddd049c346441cbcfe641d310a5a10f7f0eb0f	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x6942e4ba0f1d3bf503deec0c8d98837c13f8e3ec3f236ba10e3045029295c07c05f707af43ab377bd009321d383986ae3631ccb04b9bfdb62a6d8a678fb963da8c99a66ad58871b01cfa55a6e3e0363b090f020bede395c446008b4ccec35465ad357a3389382641690d2a8336b4364d34bfb8b3caf69a3466d974dde09cb1f2	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\xe9faabf5cb2f3ef967e643dd547c0a8414cb3af47a4f0746a841e308db68ca4ac9e1856db4d25b6d4af4b0ef62b2554217ca9b8dc2a4560846565f9e2c3c8107	1579298404000000	0	11000000
6	\\x4e0f517fe6c200ad2b77ad0e73adbe8d5d2ea9a0bf0e7b5bad3a2dcafa019475238abda49fc19943a02d6c246f4cbbce516384a10f33b250254c3021fa6e0ae3	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x5caa2d349413b3c716c2bb03e1d55bdb49fc52ac70a92d3482d96e8dee7cc13ff3198d321d00edbb9261701a21d2d0e0136612f73e8d1195f9b01bcc841f23ef19a8e88f787246bc5849501ef600c0615f26d583726ba3aa218afccfb4658a21681e05bbca481e7ea0aaad6633c92dd17be4e1830995c4b098e33283e93e3e43	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\xe4f6b2b52c0e9709cf8d40bba78d9b31e061cfc3466645c45a7a2092c560b2cf2662134f1a240e8d3c4ab55ed2f811a182c874d3d8ae5c15effb34a7aa1f670a	1579298404000000	0	11000000
7	\\x78a60b32c326474365b837c0dfe1b43b10d8f6eea80734fa1b568e10749ba6f84907b3c150166b4ebd87e02805aa74bda6ce12b8741791e0156fdc3b175018c2	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x8199f6f7505b2cf99e256e4fc98b1fb35f2123540cbfcf157a969e0ed783feb929736dc5cd166ce563d11ae8a9df16645026194b05df2126f4546a5f1cb836b0e255b793adf03b6f74394d6eeb354f7192cbb58185d536486ca71f4cc219a23ffc2ede076ec233d08fe37fc5aaf79e0d878ad675986fe22ee256cee7ce8ccdb8	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\xed165a9c8ef017c8d0e3ed50c787d3af4091bffb4885d210f12360861c09268187c7869d3b3dffc468784c70820fe0eda473ed70a3c6a1c130782127d1b6cc0e	1579298404000000	0	11000000
8	\\xe6c431b19a7185fa9ff0eec90643c3d56197f104d88f22e8dcc180b3257e9922ad5bea923add39deb4b1c9238d2d3e3834cf55fafd8554ae2d45a7c3b2e69301	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x0557d413793b8739ac273a77d38819e5482b1e10ad730e8ea555841c22d08d0e538c3951b92b7b2aa06844d9a193b7ab241b98927642bb920e8cfabcac182997158e9f8f392e4a5cf51abb2ec6844f917a2fbd9845c4ce09e6a5af586f15d8a1666a21a63515aabeb225a15e3b8fcbce462c193e424708b038fa7fbd81e0ba43	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\x3f4b8c158ba5b587a55acb06255f488d9f152fb4d68dcf2e794e85e4e4c5ca4816fb7c16cebe875732e34d9a45de78a7691a4248298568c6db3c1164c554bd08	1579298404000000	0	11000000
9	\\x685501794ba8bef4b2497969b42e78a2925c86c0d96832501fc3bcf10d63a784538987faf7f3ed9157f36444f1322b5c84e7f96c8ac48d6ec503ca0fb113e856	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x4e29c48df0a29f2c0824ffb5c6f7e50120fccb3c6ea04af0de61b33d3b360a3a1202c67de2566720d5aa48f22470676d951a3c9e9fcc8fe27959ce60dfd4e0fd2bcbf6cc602bcfb166c3f903c5e5a444a5122e5f24da7890155121d9d0c9da43821c14ffa80780239277eb701974f88a8b463af2559d24f64bf58671a5f62e34	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\xcc37a1a45f66ab789b9828b2f42e4618272cfbefc8c378a11122d941922d88cb5734cb30caca0ee48532417f0b3070cfd0243bb0e3640cec512bc9a2c2aacc08	1579298404000000	0	11000000
10	\\xd6af2c78696b52fd82bf768dac248490b39eb4d633df925a63edf3376c3ec20b97f2843d3dd3210a156894476888fedf9fddff415175c0ceabde6dbc445984d6	\\x46173e4d0c252aa05108a4944a145708c42a291f05ac0ec26705a22e67fa89e26f0937cba15baf1ecdbe5fe5bc1169f038c6527affdaa877f8c0ea1f31c8267a	\\x72625ba40c28f830cac90beed68775562fe732865574a9b1d7d5741be5c4b8cc71969f9ade681d750255a0d71c5c5c546a2b11092068d36ba3dd1f3a308000a04914fabac6e6f62b916d9cd2f21d52bf24938886b49fd4cdae31d7a16e9c94fd7c8faca41650d00a124ebc2979c8c83a86f54a9ca72e9d51e8ee367a897377bd	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\x40e322c947eb250a90606554e5a3756d45c7efbdda86dae9061d6a8b4fb0adaff9d9b8470e58aa7658dd77e141b20de9c1633d35d638479b05d5269b000d9f0f	1579298404000000	0	11000000
11	\\x8b5e3014a07a4f3c5d5f28c6de85d2d893474e8e9aaa7ad98a0d066af9e4a59c020e07c72fff36df7e10ce6d770dee529e0c338e1a2034c2d78d9a6263048f7f	\\x1acae0321cfce758697d91066f1f73beeccf5b7b870d60365f40d55dbc8c71136e098b7e2475591451f6980352425ff16fe7daeb9808d7190efb77dda21d5e8d	\\x2c1a12aa5193bd51a9cd24406de55f7b9abd1400f865407b841213eb153325941ad66ad0edec8c6f12182f2cda9a56c69fce8917f26e38aa47023b1895b290726fa95a8372ae95d081cb93ce7bd205ecb3b92a58f99d0ee91030feffae99ec2c193d960b1d2b2fec4ab241931e85f1e331dafecd12ed3ff04b62f453e3e04df8	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\x95a8270109623ab78b4aa014b3218e6f2c671508934477cae64f3b16f3bf1d71996d97eb5593d2e1d299c2bea3e13a970117766422874ed6a393453a100c8608	1579298404000000	0	2000000
12	\\xc5e602e9682f384999d427e6a1c33860d1e8adeecce0514890a922cdc5f2b22c8b48ec9690bf483adc5084830bb295146e12076a483aee6c06c27363ad884e1d	\\x1acae0321cfce758697d91066f1f73beeccf5b7b870d60365f40d55dbc8c71136e098b7e2475591451f6980352425ff16fe7daeb9808d7190efb77dda21d5e8d	\\x055649f3831457c78622448010e89f32d6e818000ab83206c273ea1b21d6ce57b04a436d48ffe0c5cbd88f5e6e5fcab4b2e6a85f483969dc9161fd30980c73bc237811523c35b62b0459f2975e3cb7c0b83f773458e55be78156fe4c373fd8311d4d797887ad394c812cb14f01b060878fb33ad3ccada4dda071c1d67ed5e721	\\x7fac34f543f3f0c6b499e6eb55bd0dd5b72df2685aa01f6fc1f26da2dae86783	\\xac031efeccb55c78f8313e84f00fcb1b84b532bcdc0aef3f378e9f531b8e7f0c33a40cc93a9b2c98b9540a3a30acab86badcd9f7eba70af0ddd1139630431306	1579298404000000	0	2000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 9, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 9, true);


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
-- Name: merchant_deposits merchant_deposits_h_contract_terms_merchant_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_h_contract_terms_merchant_pub_fkey FOREIGN KEY (h_contract_terms, merchant_pub) REFERENCES public.merchant_contract_terms(h_contract_terms, merchant_pub);


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

