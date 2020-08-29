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
-- Name: TABLE aggregation_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aggregation_tracking IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';


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
    request_uid character varying(128) NOT NULL,
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
    confirmation_done boolean NOT NULL,
    aborted boolean NOT NULL,
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
-- Name: TABLE auditor_balance_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_balance_summary IS 'the sum of the outstanding coins from auditor_denomination_pending (denom_pubs must belong to the respectives exchange master public key); it represents the auditor_balance_summary of the exchange at this point (modulo unexpected historic_loss-style events where denomination keys are compromised)';


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
-- Name: TABLE auditor_denomination_pending; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denomination_pending IS 'outstanding denomination coins that the exchange is aware of and what the respective balances are (outstanding as well as issued overall which implies the maximum value at risk).';


--
-- Name: COLUMN auditor_denomination_pending.num_issued; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.num_issued IS 'counts the number of coins issued (withdraw, refresh) of this denomination';


--
-- Name: COLUMN auditor_denomination_pending.denom_risk_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.denom_risk_val IS 'amount that could theoretically be lost in the future due to recoup operations';


--
-- Name: COLUMN auditor_denomination_pending.recoup_loss_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.recoup_loss_val IS 'amount actually lost due to recoup operations past revocation';


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
-- Name: TABLE auditor_denominations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denominations IS 'denomination keys the auditor is aware of';


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
-- Name: TABLE auditor_exchange_signkeys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_exchange_signkeys IS 'list of the online signing keys of exchanges we are auditing';


--
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


--
-- Name: TABLE auditor_exchanges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_exchanges IS 'list of the exchanges we are auditing';


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
-- Name: TABLE auditor_historic_denomination_revenue; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_historic_denomination_revenue IS 'Table with historic profits; basically, when a denom_pub has expired and everything associated with it is garbage collected, the final profits end up in here; note that the denom_pub here is not a foreign key, we just keep it as a reference point.';


--
-- Name: COLUMN auditor_historic_denomination_revenue.revenue_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_historic_denomination_revenue.revenue_balance_val IS 'the sum of all of the profits we made on the coin except for withdraw fees (which are in historic_reserve_revenue); so this includes the deposit, melt and refund fees';


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
-- Name: TABLE auditor_historic_reserve_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_historic_reserve_summary IS 'historic profits from reserves; we eventually GC auditor_historic_reserve_revenue, and then store the totals in here (by time intervals).';


--
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_predicted_result; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_predicted_result IS 'Table with the sum of the ledger, auditor_historic_revenue and the auditor_reserve_balance.  This is the final amount that the exchange should have in its bank account right now.';


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea NOT NULL,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_aggregation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_aggregation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_coin (
    master_pub bytea NOT NULL,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_coin IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea NOT NULL,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_deposit_confirmation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_deposit_confirmation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea NOT NULL,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_reserve; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_reserve IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


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
-- Name: TABLE auditor_reserve_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_reserve_balance IS 'sum of the balances of all customer reserves (by exchange master public key)';


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
-- Name: TABLE auditor_reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_reserves IS 'all of the customer reserves and their respective balances that the auditor is aware of';


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
-- Name: TABLE auditor_wire_fee_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_wire_fee_balance IS 'sum of the balances of all wire fees (by exchange master public key)';


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
    first_name character varying(150) NOT NULL,
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
-- Name: TABLE denomination_revocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denomination_revocations IS 'remembering which denomination keys have been revoked';


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
-- Name: TABLE denominations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denominations IS 'Main denominations table. All the coins the exchange knows about.';


--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_confirmations (
    master_pub bytea,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_wire bytea NOT NULL,
    exchange_timestamp bigint NOT NULL,
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
-- Name: TABLE deposit_confirmations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposit_confirmations IS 'deposit confirmation sent to us by merchants; we must check that the exchange reported these properly.';


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
    wallet_timestamp bigint NOT NULL,
    exchange_timestamp bigint NOT NULL,
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
-- Name: TABLE deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';


--
-- Name: COLUMN deposits.tiny; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.tiny IS 'Set to TRUE if we decided that the amount is too small to ever trigger a wire transfer by itself (requires real aggregation)';


--
-- Name: COLUMN deposits.done; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.done IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';


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
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    known_coin_id bigint NOT NULL,
    coin_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


--
-- Name: TABLE known_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.known_coins_known_coin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.known_coins_known_coin_id_seq OWNED BY public.known_coins.known_coin_id;


--
-- Name: merchant_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_accounts (
    account_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    h_wire bytea NOT NULL,
    salt bytea NOT NULL,
    payto_uri character varying NOT NULL,
    active boolean NOT NULL,
    CONSTRAINT merchant_accounts_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT merchant_accounts_salt_check CHECK ((length(salt) = 64))
);


--
-- Name: TABLE merchant_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_accounts IS 'bank accounts of the instances';


--
-- Name: COLUMN merchant_accounts.h_wire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.h_wire IS 'salted hash of payto_uri';


--
-- Name: COLUMN merchant_accounts.salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.salt IS 'salt used when hashing payto_uri into h_wire';


--
-- Name: COLUMN merchant_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.payto_uri IS 'payto URI of a merchant bank account';


--
-- Name: COLUMN merchant_accounts.active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.active IS 'true if we actively use this bank account, false if it is just kept around for older contracts to refer to';


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_accounts_account_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_accounts_account_serial_seq OWNED BY public.merchant_accounts.account_serial;


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_contract_terms (
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
    fulfillment_url character varying NOT NULL,
    session_id character varying DEFAULT ''::character varying NOT NULL,
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64))
);


--
-- Name: TABLE merchant_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_contract_terms IS 'Contracts are orders that have been claimed by a wallet';


--
-- Name: COLUMN merchant_contract_terms.merchant_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_contract_terms.order_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.order_id IS 'Not a foreign key into merchant_orders because paid contracts persist after expiration';


--
-- Name: COLUMN merchant_contract_terms.contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.contract_terms IS 'These contract terms include the wallet nonce';


--
-- Name: COLUMN merchant_contract_terms.h_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.h_contract_terms IS 'Hash over contract_terms';


--
-- Name: COLUMN merchant_contract_terms.pay_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_contract_terms.refund_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.refund_deadline IS 'By what times do refunds have to be approved (useful to reject refund requests)';


--
-- Name: COLUMN merchant_contract_terms.paid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.paid IS 'true implies the customer paid for this contract; order should be DELETEd from merchant_orders once paid is set to release merchant_order_locks; paid remains true even if the payment was later refunded';


--
-- Name: COLUMN merchant_contract_terms.wired; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.wired IS 'true implies the exchange wired us the full amount for all non-refunded payments under this contract';


--
-- Name: COLUMN merchant_contract_terms.fulfillment_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.fulfillment_url IS 'also included in contract_terms, but we need it here to SELECT on it during repurchase detection';


--
-- Name: COLUMN merchant_contract_terms.session_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.session_id IS 'last session_id from we confirmed the paying client to use, empty string for none';


--
-- Name: merchant_deposit_to_transfer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposit_to_transfer (
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
-- Name: TABLE merchant_deposit_to_transfer; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_deposit_to_transfer IS 'Mapping of deposits to (possibly unconfirmed) wire transfers; NOTE: not used yet';


--
-- Name: COLUMN merchant_deposit_to_transfer.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposit_to_transfer.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposits (
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
-- Name: TABLE merchant_deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_deposits IS 'Refunds approved by the merchant (backoffice) logic, excludes abort refunds';


--
-- Name: COLUMN merchant_deposits.deposit_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.deposit_timestamp IS 'Time when the exchange generated the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.wire_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.wire_fee_val IS 'We MAY want to see if we should try to get this via merchant_exchange_wire_fees (not sure, may be too complicated with the date range, etc.)';


--
-- Name: COLUMN merchant_deposits.signkey_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.signkey_serial IS 'Online signing key of the exchange on the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.exchange_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.exchange_sig IS 'Signature of the exchange over the deposit confirmation';


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_deposits_deposit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_deposits_deposit_serial_seq OWNED BY public.merchant_deposits.deposit_serial;


--
-- Name: merchant_exchange_signing_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_exchange_signing_keys (
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
-- Name: TABLE merchant_exchange_signing_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_exchange_signing_keys IS 'Here we store proofs of the exchange online signing keys being signed by the exchange master key';


--
-- Name: COLUMN merchant_exchange_signing_keys.master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_exchange_signing_keys.master_pub IS 'Master public key of the exchange with these online signing keys';


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_exchange_signing_keys_signkey_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_exchange_signing_keys_signkey_serial_seq OWNED BY public.merchant_exchange_signing_keys.signkey_serial;


--
-- Name: merchant_exchange_wire_fees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_exchange_wire_fees (
    wirefee_serial bigint NOT NULL,
    master_pub bytea NOT NULL,
    h_wire_method bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT merchant_exchange_wire_fees_h_wire_method_check CHECK ((length(h_wire_method) = 64)),
    CONSTRAINT merchant_exchange_wire_fees_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT merchant_exchange_wire_fees_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE merchant_exchange_wire_fees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_exchange_wire_fees IS 'Here we store proofs of the wire fee structure of the various exchanges';


--
-- Name: COLUMN merchant_exchange_wire_fees.master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_exchange_wire_fees.master_pub IS 'Master public key of the exchange with these wire fees';


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_exchange_wire_fees_wirefee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_exchange_wire_fees_wirefee_serial_seq OWNED BY public.merchant_exchange_wire_fees.wirefee_serial;


--
-- Name: merchant_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_instances (
    merchant_serial bigint NOT NULL,
    merchant_pub bytea NOT NULL,
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
    CONSTRAINT merchant_instances_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: TABLE merchant_instances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_instances IS 'all the instances supported by this backend';


--
-- Name: COLUMN merchant_instances.merchant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.merchant_id IS 'identifier of the merchant as used in the base URL (required)';


--
-- Name: COLUMN merchant_instances.merchant_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.merchant_name IS 'legal name of the merchant as a simple string (required)';


--
-- Name: COLUMN merchant_instances.address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.address IS 'physical address of the merchant as a Location in JSON format (required)';


--
-- Name: COLUMN merchant_instances.jurisdiction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.jurisdiction IS 'jurisdiction of the merchant as a Location in JSON format (required)';


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_instances_merchant_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_instances_merchant_serial_seq OWNED BY public.merchant_instances.merchant_serial;


--
-- Name: merchant_inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_inventory (
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
    next_restock bigint NOT NULL
);


--
-- Name: TABLE merchant_inventory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_inventory IS 'products offered by the merchant (may be incomplete, frontend can override)';


--
-- Name: COLUMN merchant_inventory.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.description IS 'Human-readable product description';


--
-- Name: COLUMN merchant_inventory.description_i18n; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.description_i18n IS 'JSON map from IETF BCP 47 language tags to localized descriptions';


--
-- Name: COLUMN merchant_inventory.unit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.unit IS 'Unit of sale for the product (liters, kilograms, packages)';


--
-- Name: COLUMN merchant_inventory.image; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.image IS 'NOT NULL, but can be 0 bytes; must contain an ImageDataUrl';


--
-- Name: COLUMN merchant_inventory.taxes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.taxes IS 'JSON array containing taxes the merchant pays, must be JSON, but can be just "[]"';


--
-- Name: COLUMN merchant_inventory.price_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.price_val IS 'Current price of one unit of the product';


--
-- Name: COLUMN merchant_inventory.total_stock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_stock IS 'A value of -1 is used for unlimited (electronic good), may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_sold; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_sold IS 'Number of products sold, must be below total_stock, non-negative, may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_lost; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_lost IS 'Number of products that used to be in stock but were lost (spoiled, damaged), may never be lowered; total_stock >= total_sold + total_lost must always hold';


--
-- Name: COLUMN merchant_inventory.address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.address IS 'JSON formatted Location of where the product is stocked';


--
-- Name: COLUMN merchant_inventory.next_restock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.next_restock IS 'GNUnet absolute time indicating when the next restock is expected. 0 for unknown.';


--
-- Name: merchant_inventory_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_inventory_locks (
    product_serial bigint NOT NULL,
    lock_uuid bytea NOT NULL,
    total_locked bigint NOT NULL,
    expiration bigint NOT NULL,
    CONSTRAINT merchant_inventory_locks_lock_uuid_check CHECK ((length(lock_uuid) = 16))
);


--
-- Name: TABLE merchant_inventory_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_inventory_locks IS 'locks on inventory helt by shopping carts; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_inventory_locks.total_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: COLUMN merchant_inventory_locks.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory_locks.expiration IS 'when does this lock automatically expire (if no order is created)';


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_inventory_product_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_inventory_product_serial_seq OWNED BY public.merchant_inventory.product_serial;


--
-- Name: merchant_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_keys (
    merchant_priv bytea NOT NULL,
    merchant_serial bigint NOT NULL,
    CONSTRAINT merchant_keys_merchant_priv_check CHECK ((length(merchant_priv) = 32))
);


--
-- Name: TABLE merchant_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_keys IS 'private keys of instances that have not been deleted';


--
-- Name: merchant_order_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_order_locks (
    product_serial bigint NOT NULL,
    total_locked bigint NOT NULL,
    order_serial bigint NOT NULL
);


--
-- Name: TABLE merchant_order_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_order_locks IS 'locks on orders awaiting claim and payment; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_order_locks.total_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_order_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_orders (
    order_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    order_id character varying NOT NULL,
    claim_token bytea NOT NULL,
    pay_deadline bigint NOT NULL,
    creation_time bigint NOT NULL,
    contract_terms bytea NOT NULL,
    CONSTRAINT merchant_orders_claim_token_check CHECK ((length(claim_token) = 16))
);


--
-- Name: TABLE merchant_orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_orders IS 'Orders we offered to a customer, but that have not yet been claimed';


--
-- Name: COLUMN merchant_orders.merchant_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_orders.claim_token; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.claim_token IS 'Token optionally used to authorize the wallet to claim the order. All zeros (not NULL) if not used';


--
-- Name: COLUMN merchant_orders.pay_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_orders.contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.contract_terms IS 'Claiming changes the contract_terms, hence we have no hash of the terms in this table';


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_orders_order_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_orders_order_serial_seq OWNED BY public.merchant_orders.order_serial;


--
-- Name: merchant_refund_proofs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refund_proofs (
    refund_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    signkey_serial bigint NOT NULL,
    CONSTRAINT merchant_refund_proofs_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_refund_proofs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_refund_proofs IS 'Refunds confirmed by the exchange (not all approved refunds are grabbed by the wallet)';


--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refunds (
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
-- Name: COLUMN merchant_refunds.rtransaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_refunds.rtransaction_id IS 'Needed for uniqueness in case a refund is increased for the same order';


--
-- Name: COLUMN merchant_refunds.refund_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_refunds.refund_timestamp IS 'Needed for grouping of refunds in the wallet UI; has no semantics in the protocol (only for UX), but should be from the time when the merchant internally approved the refund';


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_refunds_refund_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_refunds_refund_serial_seq OWNED BY public.merchant_refunds.refund_serial;


--
-- Name: merchant_tip_pickup_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickup_signatures (
    pickup_serial bigint NOT NULL,
    coin_offset integer NOT NULL,
    blind_sig bytea NOT NULL
);


--
-- Name: TABLE merchant_tip_pickup_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_pickup_signatures IS 'blind signatures we got from the exchange during the tip pickup';


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickups (
    pickup_serial bigint NOT NULL,
    tip_serial bigint NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: TABLE merchant_tip_pickups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_pickups IS 'tips that have been picked up';


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_tip_pickups_pickup_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_tip_pickups_pickup_serial_seq OWNED BY public.merchant_tip_pickups.pickup_serial;


--
-- Name: merchant_tip_reserve_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserve_keys (
    reserve_serial bigint NOT NULL,
    reserve_priv bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT merchant_tip_reserve_keys_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserves (
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
-- Name: TABLE merchant_tip_reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_reserves IS 'private keys of reserves that have not been deleted';


--
-- Name: COLUMN merchant_tip_reserves.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.expiration IS 'FIXME: EXCHANGE API needs to tell us when reserves close if we are to compute this';


--
-- Name: COLUMN merchant_tip_reserves.merchant_initial_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.merchant_initial_balance_val IS 'Set to the initial balance the merchant told us when creating the reserve';


--
-- Name: COLUMN merchant_tip_reserves.exchange_initial_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.exchange_initial_balance_val IS 'Set to the initial balance the exchange told us when we queried the reserve status';


--
-- Name: COLUMN merchant_tip_reserves.tips_committed_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.tips_committed_val IS 'Amount of outstanding approved tips that have not been picked up';


--
-- Name: COLUMN merchant_tip_reserves.tips_picked_up_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.tips_picked_up_val IS 'Total amount tips that have been picked up from this reserve';


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_tip_reserves_reserve_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_tip_reserves_reserve_serial_seq OWNED BY public.merchant_tip_reserves.reserve_serial;


--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tips (
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
-- Name: TABLE merchant_tips; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tips IS 'tips that have been authorized';


--
-- Name: COLUMN merchant_tips.reserve_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.reserve_serial IS 'Reserve from which this tip is funded';


--
-- Name: COLUMN merchant_tips.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.expiration IS 'by when does the client have to pick up the tip';


--
-- Name: COLUMN merchant_tips.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.amount_val IS 'total transaction cost for all coins including withdraw fees';


--
-- Name: COLUMN merchant_tips.picked_up_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.picked_up_val IS 'Tip amount left to be picked up';


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_tips_tip_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_tips_tip_serial_seq OWNED BY public.merchant_tips.tip_serial;


--
-- Name: merchant_transfer_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfer_signatures (
    credit_serial bigint NOT NULL,
    signkey_serial bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT merchant_transfer_signatures_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_transfer_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_signatures IS 'table represents the main information returned from the /transfer request to the exchange.';


--
-- Name: COLUMN merchant_transfer_signatures.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_signatures.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_transfer_to_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfer_to_coin (
    deposit_serial bigint NOT NULL,
    credit_serial bigint NOT NULL,
    offset_in_exchange_list bigint NOT NULL,
    exchange_deposit_value_val bigint NOT NULL,
    exchange_deposit_value_frac integer NOT NULL,
    exchange_deposit_fee_val bigint NOT NULL,
    exchange_deposit_fee_frac integer NOT NULL
);


--
-- Name: TABLE merchant_transfer_to_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_to_coin IS 'Mapping of (credit) transfers to (deposited) coins';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_value_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_to_coin.exchange_deposit_value_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits minus refunds';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_to_coin.exchange_deposit_fee_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits';


--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfers (
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
-- Name: TABLE merchant_transfers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfers IS 'table represents the information provided by the (trusted) merchant about incoming wire transfers';


--
-- Name: COLUMN merchant_transfers.credit_amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee';


--
-- Name: COLUMN merchant_transfers.verified; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.verified IS 'true once we got an acceptable response from the exchange for this transfer';


--
-- Name: COLUMN merchant_transfers.confirmed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.confirmed IS 'true once the merchant confirmed that this transfer was received';


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_transfers_credit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_transfers_credit_serial_seq OWNED BY public.merchant_transfers.credit_serial;


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
-- Name: TABLE prewire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.prewire IS 'pre-commit data for wire transfers we are about to execute';


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
-- Name: TABLE recoup; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup IS 'Information about recoups that were executed';


--
-- Name: COLUMN recoup.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.coin_pub IS 'Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


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
-- Name: COLUMN recoup_refresh.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.coin_pub IS 'Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


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
-- Name: TABLE refresh_commitments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_commitments IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';


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
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


--
-- Name: TABLE refresh_revealed_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_revealed_coins IS 'Revelations about the new coins that are to be created during a melting session.';


--
-- Name: COLUMN refresh_revealed_coins.rc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.rc IS 'refresh commitment identifying the melt operation';


--
-- Name: COLUMN refresh_revealed_coins.freshcoin_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.freshcoin_index IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';


--
-- Name: COLUMN refresh_revealed_coins.coin_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.coin_ev IS 'envelope of the new coin to be signed';


--
-- Name: COLUMN refresh_revealed_coins.h_coin_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.h_coin_ev IS 'hash of the envelope of the new coin to be signed (for lookups)';


--
-- Name: COLUMN refresh_revealed_coins.ev_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.ev_sig IS 'exchange signature over the envelope';


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
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


--
-- Name: COLUMN refresh_transfer_keys.rc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.rc IS 'refresh commitment identifying the melt operation';


--
-- Name: COLUMN refresh_transfer_keys.transfer_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_pub IS 'transfer public key for the gamma index';


--
-- Name: COLUMN refresh_transfer_keys.transfer_privs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_privs IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';


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
-- Name: TABLE refunds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refunds IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';


--
-- Name: COLUMN refunds.rtransaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.rtransaction_id IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';


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
-- Name: TABLE reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';


--
-- Name: COLUMN reserves.expiration_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.expiration_date IS 'Used to trigger closing of reserves that have not been drained after some time';


--
-- Name: COLUMN reserves.gc_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.gc_date IS 'Used to forget all information about a reserve during garbage collection';


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
-- Name: TABLE reserves_close; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_close IS 'wire transfers executed by the reserve to close reserves';


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
-- Name: TABLE reserves_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_in IS 'list of transfers of funds into the reserves, one per incoming wire transfer';


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
-- Name: TABLE reserves_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_out IS 'Withdraw operations performed on reserves.';


--
-- Name: COLUMN reserves_out.h_blind_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.h_blind_ev IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';


--
-- Name: COLUMN reserves_out.denom_pub_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.denom_pub_hash IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';


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
    master_pub bytea NOT NULL,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bigint,
    wire_out_off bigint
);


--
-- Name: TABLE wire_auditor_account_progress; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_auditor_account_progress IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea NOT NULL,
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
-- Name: TABLE wire_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_fee IS 'list of the wire fees of this exchange, by date';


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
-- Name: TABLE wire_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_out IS 'wire transfers the exchange has executed';


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
-- Name: known_coins known_coin_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins ALTER COLUMN known_coin_id SET DEFAULT nextval('public.known_coins_known_coin_id_seq'::regclass);


--
-- Name: merchant_accounts account_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts ALTER COLUMN account_serial SET DEFAULT nextval('public.merchant_accounts_account_serial_seq'::regclass);


--
-- Name: merchant_deposits deposit_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits ALTER COLUMN deposit_serial SET DEFAULT nextval('public.merchant_deposits_deposit_serial_seq'::regclass);


--
-- Name: merchant_exchange_signing_keys signkey_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys ALTER COLUMN signkey_serial SET DEFAULT nextval('public.merchant_exchange_signing_keys_signkey_serial_seq'::regclass);


--
-- Name: merchant_exchange_wire_fees wirefee_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees ALTER COLUMN wirefee_serial SET DEFAULT nextval('public.merchant_exchange_wire_fees_wirefee_serial_seq'::regclass);


--
-- Name: merchant_instances merchant_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances ALTER COLUMN merchant_serial SET DEFAULT nextval('public.merchant_instances_merchant_serial_seq'::regclass);


--
-- Name: merchant_inventory product_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory ALTER COLUMN product_serial SET DEFAULT nextval('public.merchant_inventory_product_serial_seq'::regclass);


--
-- Name: merchant_orders order_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders ALTER COLUMN order_serial SET DEFAULT nextval('public.merchant_orders_order_serial_seq'::regclass);


--
-- Name: merchant_refunds refund_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds ALTER COLUMN refund_serial SET DEFAULT nextval('public.merchant_refunds_refund_serial_seq'::regclass);


--
-- Name: merchant_tip_pickups pickup_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups ALTER COLUMN pickup_serial SET DEFAULT nextval('public.merchant_tip_pickups_pickup_serial_seq'::regclass);


--
-- Name: merchant_tip_reserves reserve_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves ALTER COLUMN reserve_serial SET DEFAULT nextval('public.merchant_tip_reserves_reserve_serial_seq'::regclass);


--
-- Name: merchant_tips tip_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips ALTER COLUMN tip_serial SET DEFAULT nextval('public.merchant_tips_tip_serial_seq'::regclass);


--
-- Name: merchant_transfers credit_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers ALTER COLUMN credit_serial SET DEFAULT nextval('public.merchant_transfers_credit_serial_seq'::regclass);


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
exchange-0001	2020-08-28 19:19:22.273457+02	grothoff	{}	{}
auditor-0001	2020-08-28 19:19:26.000803+02	grothoff	{}	{}
merchant-0001	2020-08-28 19:19:26.221154+02	grothoff	{}	{}
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

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2020-08-28 19:19:29.445357+02	f	d3e8d993-7d5c-4edd-8329-b66b9c1f78a8	11	1
2	TESTKUDOS:10	F6WAE598K89GWZA0WSKFAQ2SSPD51838H7PEFJJ5YENEVPFK28HG	2020-08-28 19:19:30.739041+02	f	6e1b7ff0-19b4-4543-9ac1-6f606f4177d6	2	11
3	TESTKUDOS:100	Joining bonus	2020-08-28 19:19:32.708082+02	f	55430cba-1e80-4bfd-943e-34cecc083742	12	1
4	TESTKUDOS:18	CCSNAVDZQAZ6Q61HTTXV3WFTG94930JTJ6DBBJDF54YS07D9HY3G	2020-08-28 19:19:33.243523+02	f	a1c84521-ce76-4c97-b492-a10594bd6dcc	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
e1fc6e62-0a6d-4bb1-be79-605ae453caf5	TESTKUDOS:10	t	t	f	F6WAE598K89GWZA0WSKFAQ2SSPD51838H7PEFJJ5YENEVPFK28HG	2	11
456ec38d-ffd0-4cba-a7c3-8774e0eea658	TESTKUDOS:18	t	t	f	CCSNAVDZQAZ6Q61HTTXV3WFTG94930JTJ6DBBJDF54YS07D9HY3G	2	12
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
\\x7a03a3ae909f1954488bf99c2c524ef40810ef2baa989a5150de161375a73d1d6a76752732d538de535ceb059d946e6e5565d55951bc31e11d47d51c0a81bcf0	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1599239962000000	1661707162000000	1693243162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0846c00fbfd3489a3393cf435375bb836e0e6ec6b1d3759743eb134a735f8a4e43c9eb6abc62ae221cba1ae3833729d2246e9fccbf57cc786e5b5be0dcc07d8f	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599239662000000	1599844462000000	1662311662000000	1693847662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a46a16dd6b16fe1347775e0b041fd39cccc360e4bfe998ec9818b98876fbd5a97e5a11e3c4fda0d8af421a26d184ac7301bcc2a8d337e832bf87e2a5f3ad6f6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599844162000000	1600448962000000	1662916162000000	1694452162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3185c80cd8790435b01601ee8a639d450a86c3d652ef2397dc55f789a12cdd67d6b8c60ab9ba836033940c8f65886879adc2d87e2eb1d9a95875c9c9a0ad227d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1600448662000000	1601053462000000	1663520662000000	1695056662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c3b5a1e598ff6d312d3515d1eb9f47b83e0e144f22477d6f7743cdb817126c1b4a7aa7f4a0a77d191a1eac217d07efb6c40c05e3956802c5c1ffb119b90528d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601053162000000	1601657962000000	1664125162000000	1695661162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e6caa1aca35e12417b7da8cef0c22788204cf8b8d61ad7c33fbff11978273bf1ae73f56e0ac464aefc085130a80f7d4285130ebca520625d86bbe68208abd75	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601657662000000	1602262462000000	1664729662000000	1696265662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d596bd5283987771794fc7927540bd9357efb23efa2439a648de8f56d296e8bf3b645bde2a59e1cfe463ec29dd3415e96abbb8d55ae374668b38df3049cd67c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602262162000000	1602866962000000	1665334162000000	1696870162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x616c93541738ae296a924c97f11431698ad734d84b06a02bd41ca4b41ec9c072256b66025675969f31f74987c1fcd0b0840652df5adc376cd65dfd21c686140c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602866662000000	1603471462000000	1665938662000000	1697474662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3777cc0827135145b91408c16c3188e4ab0b720e7ca14d4a128b3638dc21b378cfb032b19655a019e9c7bec2627e0fb89b63f6c181c672bf7b42d6a6d35810cb	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1603471162000000	1604075962000000	1666543162000000	1698079162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x88d5a6c6933ab1d6e31742378a42a86039b775ae2fdf2f0e985dbbbd1ab5977d9a9634787fd269b88b929a676c13de36d0407c1731644501173c2c848d1bc6f6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604075662000000	1604680462000000	1667147662000000	1698683662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b0af3e94ab27ec390e89063e0b9d6489b43eae5ae37f4cfef1b5c4e73a6206600359cc625bd78c93947e7e7609d2d15f629f24e4e855cb1a9248c7f58c22d27	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604680162000000	1605284962000000	1667752162000000	1699288162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x316fa004d552e68e9bb0acc342cfebfe9324029539914c3637761f684117036703898aaf55933b7305ad2462208c4f132fa816cad943eebc3229e63029502d31	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605284662000000	1605889462000000	1668356662000000	1699892662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2bd6b4da302495e01b2bd40187553a6e35ffa4efb0f8944e61f98d58e643fdc32535056f56ba3149428943fb8571a3690315fd3cd137ce93ee8649eb4aa7f356	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605889162000000	1606493962000000	1668961162000000	1700497162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x37ce05c4e51c67dcced92fa67e7a6335b4d4655e789d11d67081f9ff683811e83c5533bfc4d3b31968790effffe9584039e307bba2b2fb620feb836c63e00d71	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1606493662000000	1607098462000000	1669565662000000	1701101662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc3587dce12c8ce3ef32ed61f95904dd7e6651132459ab3fce61e2e95975053b44384c97aa44210135eee96ed7ae383dacc32fcf273fc1d2b0e67072e2e6b44c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607098162000000	1607702962000000	1670170162000000	1701706162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x267be7a9f21e472c340d87287bf83444ab2d2b22abcbbf37736ba4f5fb1dde0ebd25d816f57fcc63ca85f3eaf2bb4d9fc7fa7efdea29811d826c67c5820b76d7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607702662000000	1608307462000000	1670774662000000	1702310662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a457c5ee3ce3d7927e3d9e78b866c7622dfb5dabf1468bc0dcb99d01dc47d252aaa55d7766bc58ef06e2a82cfa277f02f5358c6516296c396db1a162b194962	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608307162000000	1608911962000000	1671379162000000	1702915162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01fca78caa1b1070ee754e489d19cdbdf7111cc674fdfe2bdb2cfc0916a01bdede822dc97ca5a63823c0748fa0e3856c65e1efead4beaed8f330b0f85ae3ae62	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608911662000000	1609516462000000	1671983662000000	1703519662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x11c9f090f27a021e2f97a892040ecefc27f928c50e7f6bc842428e9a498f973e1c0a9c3adbdd2d7ffa94791f3a4911423cde5f7546d42a13b1d8060383382c2b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1609516162000000	1610120962000000	1672588162000000	1704124162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x62def3e732984a2ebf5b13cb8ec83975d3b9ef5368e7c3133c0d29b9bfa6204a58f06df8c7c04ea00f99d0476679c7a5eeb159f6625b499854e58de8f63b1333	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610120662000000	1610725462000000	1673192662000000	1704728662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcba20f466ae4e0d3c9efeefb20933d11030012bd9295ad8d98433ab81ef3d967c7f96ae55dc1276de92c314a5138ab8f1bf3030162da9fa6cc1dda358b1499eb	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610725162000000	1611329962000000	1673797162000000	1705333162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdce6690e2aca413ffa46a293607044ba4f5cc197b882987a95a1c5359260f662d27b0bfdb08f80df05f3c1e3be13b6bed554f5342314c35bc32eabf5f541f8f0	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611329662000000	1611934462000000	1674401662000000	1705937662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x83e4e039d1b2573aae857b33f0ac669bf078cec7f8b222f827fbb621462e3a9e2eeeaa02689c51f319db6f13115c0a1958a8c9bb51e908dc54addc48e9dbd0f7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611934162000000	1612538962000000	1675006162000000	1706542162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x67191e88a25c7745dac81fd349b58a35ca6cbe5e8804015e299b93f54d1587afcd488d46d26e63460655c4f5ce91d9a15fbc9cd7c84b627aca8dca4003f39d8e	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1612538662000000	1613143462000000	1675610662000000	1707146662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa10459bffd0feed45bcb01fedafc7779cb0586744395ee3d7b95bd656c498d9efc877c57ab561f6ebcfcb94841006166bdcd5468e3fad8e67c4c3bc80879a09b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613143162000000	1613747962000000	1676215162000000	1707751162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ef53d158eb55001589b4bec9aea30f75863d532a30a9b3938e22604a39a0482fbb9ae6205b1651054964577f88ca3ce8ccd96d673f7e7d277acc6052ca55efb	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613747662000000	1614352462000000	1676819662000000	1708355662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xec8480cbad17bb5b60e15df91237f0f5df48985d35d11e682f97bb25a36c1e0311f9fbaf1e31e95999f66b010b35ce7e216eaee0cb277c523b569d276f9e6aa5	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614352162000000	1614956962000000	1677424162000000	1708960162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4117e7ea00da44740b912a8fd7fd2909247d90cd6c3c62606336899d4d819b988b9ddbdeb8c87bad8b246af4ed04d834f8b51100ad2773a698ed6844f7b29d68	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614956662000000	1615561462000000	1678028662000000	1709564662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x57f85ba085414ef78c62e437a60f49dd59800e8cb9cbb9e06ff560661aa239311b96ad65e264be374a64f80e05a4d6a9cd5ee057d3990af7e7daa5dffe82795c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1615561162000000	1616165962000000	1678633162000000	1710169162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa45b0c66dd39571a05b4b6d5fed07def41c982370c6b1c984b0fd6bcaae5b3e57ad2f4542a4130f10e63523d50f8e4a3e8fbf9c983f131b19a45e20e9aa765e7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616165662000000	1616770462000000	1679237662000000	1710773662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c4911bad4deb0f713abff7988acd12a0bac0b60fdf6261301016d8d12bb2a59c02b446bad227ef65a624fd7a8b73fc84ecddbc3f09123f063a1bd031473878b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616770162000000	1617374962000000	1679842162000000	1711378162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53f71e0e0d9975f852fcad3ec8ccf62d216a1408fbf0c9494c2ab5664ef03f65aa22e2bba5d07a5b479727d80dd6f9fd2e0b85bb5816519f848d3b9678e9b6a8	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617374662000000	1617979462000000	1680446662000000	1711982662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef69835155c43b572b034caa14835dbf1ad28ab4630b0ba4d311ca1513f197e84458916009c0cdd0204fb05ba4cedc20204a81e9e0fcda8cf78f90ca396ad061	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617979162000000	1618583962000000	1681051162000000	1712587162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70ec0408bdb4fc9dfddb764988fc519361870d8e1b257110b4ed1669149428fcc2cad887df8ad9926266deec3137d5f565374b7881b83bd80070a892d1ac8845	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1599239962000000	1661707162000000	1693243162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf1110020b6f14636995d583a206f8844efd5f23630f29d8ac23cd00bc5b78e7397e0a14fecb4b0d75f4aad4410c8c85f58de865ac811146c3e526fef8f95273b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599239662000000	1599844462000000	1662311662000000	1693847662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5bae646ec391d8a580dd067bed7341c449c4cfda5c44e996c0143f3d1a8be9f1f5eaf9199e1dcf026da0631cfc8c091f7a5f39126ae331c506e806e9ae454252	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599844162000000	1600448962000000	1662916162000000	1694452162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa7f0169e04b4c4474e32f290095d2ea90b8a7ecd2fe7e4fd2e5dcad5c502d81fe87d73d3c45ec42690860c6a642ec11cf7acf8d6bcfd8e5cc1abd3139c6bf076	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1600448662000000	1601053462000000	1663520662000000	1695056662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd089c5dac8d238dc2949b7a9fdba55d9e407307a7da04d447c674a80f52f83820e47b6c657a4bba452e9db8e1f6526b4d3e3b21a6712144487dda63929e06c52	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601053162000000	1601657962000000	1664125162000000	1695661162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6e8e78d5f876933c8e7f142b1db14f8dbbf2eb3acfa049ababf319354586124df0cf5d122bef37749122aa0f615e24f4e48a3cae8c533fa3edc2b566fedefba2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601657662000000	1602262462000000	1664729662000000	1696265662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x03c1356368efb2de04124769afca7ae3b05ef1341a799fc74c5dc956cb397d1be0fbef3b1907ef88836050febb3f52ae9df15eaa7b16d302b583e32b9ecb1656	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602262162000000	1602866962000000	1665334162000000	1696870162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6d5d2abc4a12b9e935b82e580ccc37231a90d2ce48ba821915e7572d41df7d0df6567b8ddee09401a775f00a0be0a4ef65c528e040a4d126a0facf9daedea352	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602866662000000	1603471462000000	1665938662000000	1697474662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xef92d2c308434e26b129ce099c9c7f903e9b7822d0b4f71340b7a4ba4d50c1f8c233e67f23ad8f6209274f922831528a7b417f799c2e28527154a5749bad7364	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1603471162000000	1604075962000000	1666543162000000	1698079162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x180994ea2baab6487226faf2e4dbbea63f2ea5a2508d0e577b0c24fea47aca4ae3b52ded3f99a623e11986ce1d7a93068b729ab4eafdd29302a90bcd81fc478a	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604075662000000	1604680462000000	1667147662000000	1698683662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xda709630d693c51af3f47ba82434b5e6f972ceb41914820e1f124e3337ca4223ccbd45dd388a86e95b3ae585820660b1f977ccd6856e0532aff80923600a6b80	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604680162000000	1605284962000000	1667752162000000	1699288162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2cb5f1ac0f016d9e0c09d9d4280a7ddb8a170e488492240f7ed872b642533039441ad83caa2574eab1bba8658bed70a0d632774d996bc703189344d4688d253c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605284662000000	1605889462000000	1668356662000000	1699892662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb798e937f77f1332efb4e967d477253e7d980df3511f5596ab9cd5aa4a5cbdf8d8a42e1cbac136960e6ef5604fc4c3ebac911e108cdfa6187411870bdb8ff7d8	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605889162000000	1606493962000000	1668961162000000	1700497162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb16e5b35dba6b6bb78503710559c6d621a2c7c2bf24f53404f5684aa13c3ab7f05027654147bd3c6d844a1bbb852bbad7681fc69ad51fa7a30b25b6d4f91c246	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1606493662000000	1607098462000000	1669565662000000	1701101662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2f65ed0591f12c41cbe05ec88c8e89042bfc678faad83e3fdac95a136a7eff7ef349694a7532f06ad9b6216d70bc43852959320922b24d604232c262b070da43	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607098162000000	1607702962000000	1670170162000000	1701706162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa8ab37866af8fa5f13f8ba1e940973b59909380488b4ab3a5201ca056d8df7f3486c9719e08acc4d0c8a1b50697d3441bbdd979e2b35c0cad90fdb8c42466b3b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607702662000000	1608307462000000	1670774662000000	1702310662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6d6e5b16b9955d2ed75771a28ac3222b7578c5671027c47c7d51e30adaeca9a8506e4c4bc46f82dbc8ec1b304bbd4a1ed545602268169394ed850281dd00312c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608307162000000	1608911962000000	1671379162000000	1702915162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x96ddb1b21e25117bb9ecb4f7cc4d49a53daaa8fee547f1b9fbfe2f10d7fd67247f6fe8b84d5e90b27e5cb3bfe87dc0049b9a612a5914851218f91087865f5acc	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608911662000000	1609516462000000	1671983662000000	1703519662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb5743fb88bc52549973256bbc2ce6123f8d37a690fb7cab36edfc65a4d2e0a18d1be26e36d3a832b59e6e250783c34af46bb2de0f92c90e5a1b75a7e5015ba4c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1609516162000000	1610120962000000	1672588162000000	1704124162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe6745a762090c5b58437d2001823c45f50b771686a69f48b4c04c8a4e8e4871e50dff278ef3598284f7d2f1ad023d2cd7478af1fe0f541ee76c33da86ea9d47f	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610120662000000	1610725462000000	1673192662000000	1704728662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe91f423767bd06a113ee0f884465f1549e9541bda7b330844698bfb8c474ff7a96dd9a5f78f501e75dbd73069c0e9cb8fb9b7fff7493160e4dd4891e35b6c27b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610725162000000	1611329962000000	1673797162000000	1705333162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x606802f45a07b53f22225472aac1f8b6d640da3f8c29bd3fd9fe04f55814e4b738da573ceaf441f3a3c6313756df96afaa8483b6f57881ae17f5baaaa32d8019	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611329662000000	1611934462000000	1674401662000000	1705937662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x898f1803ce8f25a0a37dd0dbd762d57b94b271d26e344acb33aaa5affd1abce4eda4cdafd25eaf87b59112873ea52de0fd1372dfdcea617f86fc7028d8399507	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611934162000000	1612538962000000	1675006162000000	1706542162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf8c8a154db8c0158cf024645ebbbfcb786ebbe60cb82ed29e524b0f00c1115de286f82a5dfc4b674a4df0cc51c3d319c30005812b286391ce42df0447477cb2d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1612538662000000	1613143462000000	1675610662000000	1707146662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfee05bcf035b07a6ed15e914e15d1846378283fbe1b1b7d5ce87c5c50f7fad6430d7d91982fbea49330168b74735129833c6a6075f9fe3116281c676679d2697	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613143162000000	1613747962000000	1676215162000000	1707751162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe238e96f609deeace46f33289ba8f5796cee4d6e8b97fbe9ed178f7906bfc065163640b0c2f3082ad3fef9450bdab67d5aa1536ff0903cb65f3c405ea753194f	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613747662000000	1614352462000000	1676819662000000	1708355662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xec33fe20a810dc9dd77dbaf70f5717f0f963f9a716890e7991ebfe833c7a4281b559a489048b90588873a3c21c3723f3a212f6194c782f4245cadf8bd1fc774a	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614352162000000	1614956962000000	1677424162000000	1708960162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe923cc6f3305b7acfe0e9c1ff0c873d90cfddc2bab6e22aa9275a86a8dbd3c72187a5b2b6e344cad25f054849afa7e55a3ff2d01940b82b880b63c7570bb7c75	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614956662000000	1615561462000000	1678028662000000	1709564662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2df068d2999df4aec3920ab8ae72fe6e32db85845baedea80d2556e355adb958d54000416e9be610c97cfbc7d95ad0f14fa5e2a815c3ee333ccd314072680259	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1615561162000000	1616165962000000	1678633162000000	1710169162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x41d7a243ce577537db940cd7b2df3d0f7a41719b4dd2700664ba4f4f72449ed8c02f25e033dfc9486ffc69226adf244f859cb894caf9d8e39967d75aaff2551c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616165662000000	1616770462000000	1679237662000000	1710773662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x071ae9873136847512b242052cb971c626434bba6a20ddb3a1510830b9a464b100b6572a135c80c614c0a0d79d69231d259632420da9549e638d21c9901325bf	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616770162000000	1617374962000000	1679842162000000	1711378162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6dab06ff19b076670ff35f71ccef6c27480727b7b711940de213f02619a58558ce84b92d705e94b88f91e51ba03d9023c57da5883042ded0d0c4b406196b7f3d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617374662000000	1617979462000000	1680446662000000	1711982662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfee388bb31f583f912611c8ba8bc8bb0637f007c7d1d0030405948825445dd3f62043f71e9d57bea51386a81c62e53c89fb618e3dd3696bd8043da4b6a5f57e2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617979162000000	1618583962000000	1681051162000000	1712587162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x42d0f6a215c182209d58c0d04efae56fdf3a1de408873375550fa84fc5f80622c0a1a01b0f7cc64663001615d304ba884d95511dbab07ec3501f06140205d920	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1599239962000000	1661707162000000	1693243162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x72db9de946f5c3792fbe1e3c98ff4fdd07a1cc08198002ff142991ea9a8b70cf534518c550cc31c4c639b33fde18dde78a229fc7811692c0cc7656701bc438ad	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599239662000000	1599844462000000	1662311662000000	1693847662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x450425b66f3748925b4bfb545b02198391a1e64452b342c10182949d706c06f5e07d050ac9b1f6cc4902e5e7b150ed86af3d93dbc5ba1a33520b86d9293c81ed	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599844162000000	1600448962000000	1662916162000000	1694452162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x25ce1e89bc410eb117ca087dbd652a37e5df542d309a7e77f0951bf8d547597d5bc2d0a80d9f396699c536ed42cd737e4777ab903b5b3fbb14672d7aab390394	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1600448662000000	1601053462000000	1663520662000000	1695056662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x713af7730ce50ba080a3f39b6cfcba0c835c51315690eb92a69fb1c5f051343db00c0f119491063569aae188f994382dbd4545c999a209424d6ad2e582aec791	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601053162000000	1601657962000000	1664125162000000	1695661162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6042f5d46f78e88ec82c8709534ff5c84faaeed60b633e701701174ec9560b0712d818c3ca1aa212204324f5af6875e6dcd97a7332b988f86d142fbe2cab7714	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601657662000000	1602262462000000	1664729662000000	1696265662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xae31320bf79b87e487c167f1f6f7be58f85acfd707962d3d45e48e316c76cd6d05b27f52a001137814169391a3062e153b4edf217db647a3aa2f784003b36e2b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602262162000000	1602866962000000	1665334162000000	1696870162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfea273666715a46a5eeb7d8ec6ee58b015dd5dd87c97b18af445e29f22cf40bcfb95f00544f88135978f79b76de65857627d5956d1e430006bf77dcf63d783ed	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602866662000000	1603471462000000	1665938662000000	1697474662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3fbf7f73d59b8938b3365a65730641189184acd754cd3d3041deb91757c2750a9c8162f308c7b9141fc2c85a5b5e11ab3ef13da48b37baa2fe1afbd56ad8eea6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1603471162000000	1604075962000000	1666543162000000	1698079162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7ceb25a196c0b92e3337a631187cf120cf854b32efaa24cfcf771d47a6aba2a52c8fc6f89de2347dce72e3b72c896a3549ad05281c1738e3a4885e04164c913	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604075662000000	1604680462000000	1667147662000000	1698683662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe84ed3a7054c5fecfcbc2d8d5f9f7353a7abcc9cc2b8f385bcef924d86cc32e46a655ddaec87d7aba6632d4b8658ddd0828932166a97c2e6858295ed8d4d554d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604680162000000	1605284962000000	1667752162000000	1699288162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8352bf2b2adbad501257555108a55f03b5a05ee0066abbe4197276a4bdbaa59c6ec755e917ebb4b44f405bd4b5136eee1a374869b805e696851a2b3bbb8e2b5a	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605284662000000	1605889462000000	1668356662000000	1699892662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x74cf62a9a7b80720f4938b7cab7f507a5c1fb936fae9a624640666ab125c6c0f74620ad5e5ec183ede5f7ad72971ad7763bca228fa616dfe38786af8833fb475	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605889162000000	1606493962000000	1668961162000000	1700497162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeaa7ae577f562f4d0ac0092892291848d4c3a4973df32bf2799cad30b43f2c9cfcb432f774f12e265e3382c21f7932956ffeb3075eb896b7becd00bcde2dfa1f	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1606493662000000	1607098462000000	1669565662000000	1701101662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7da481a02e1a84fa62ff9358aabaa4e6e747d3744fb14aee0aa882e204b1bd0d13ef87bd0061a4a2c2f15f978f0d5f1f1d74cea58cc3e86479848d8c05a24268	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607098162000000	1607702962000000	1670170162000000	1701706162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x276eed5b1b8f11b8b0a16e775d5f04ba6b1ef848b46123b78a1a8bd401af7912bf209f16cedabbdaa943fdf426a14f458904f72ec68b4e63bd7df7d1399220fe	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607702662000000	1608307462000000	1670774662000000	1702310662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32290f461e119bd942965ccbb3ff0c85db1b4e0e650f77b5ddfb664800c3bcd56454c187fa8bd5ccb6c20002e687683a670060f49cee08b46ebeddab4fcf3e50	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608307162000000	1608911962000000	1671379162000000	1702915162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc94ca77ca552ee0320821c0a4587fc91792c6fdfc450b8935cd296bf1773803ef36340e02a3dabf457494f777db97e8253e10acbb964a50385085e18c513e0c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608911662000000	1609516462000000	1671983662000000	1703519662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3cb970d13f18b36484cfb5874ff0d3522bd86a3bd0a76a28ac5fb5b8ea0588a184c0bf36a4517d62c44aa66c780bd23487d029f19889999dd8bf0f237741621	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1609516162000000	1610120962000000	1672588162000000	1704124162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3851a7fe685914fd009bfc75e7a9ed9fd1fecf20fa5a05a6de7e8e65654f559553daab01048f8a6e4169cd43ffca6790243006e2e5e67e4cda6bbff36ac55015	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610120662000000	1610725462000000	1673192662000000	1704728662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x92c39712cdcebda7be8361184f3185c049caf0f559b4b29bbaa121724a06e408c4589e18cd1784e50df0095a5c6324fc6b7e38f2d28dc2ca5fe6a8c9ab0891a7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610725162000000	1611329962000000	1673797162000000	1705333162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x637fc3c9f007569009280788519b6078070237f3c7d215f83a55fb1e6833019aace5b72dc20dd25103120e747719ea245d8cb12f2c42d755f27485369468cdea	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611329662000000	1611934462000000	1674401662000000	1705937662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8aa7edef65b36d146a6ee197ef2cc01375651cff5045b09884f93fdc9a538fb873a667e6bd1df7d2ac64d351eff7204683eb39746143ce24b8ebb051755b9d10	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611934162000000	1612538962000000	1675006162000000	1706542162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x356ea0260b2932faae99c38141f1ebd6278f6c9e4de3672a926eaa8c5c43043656685b92e191d26ada302b461e17db0ed69691e281f7671dec2a4fb96d624986	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1612538662000000	1613143462000000	1675610662000000	1707146662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fb3eb55f75e1a7787dc5e52ded0d7e24901ae72d4b69ece2abdbc07b9cea6d3cb13c1cb37644a2fe5318639ae0e79be2fc993c62f3f953cf7ba56abce17dbb4	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613143162000000	1613747962000000	1676215162000000	1707751162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x684f9f2279f59b7d4e3f4a546fda7bd9f1dc500db12e2c73802a7c1cd43b1dc166dab2170151e5097a2da95d0b6c9418275ae7221f942c1b26f6f6c5c17fe7f1	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613747662000000	1614352462000000	1676819662000000	1708355662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc23916c79ce308a173abea00a3f22205640a3a4450b241105328bd49dbe84aa5d3c8b42d3d86760a748bc7b6a0716c790758591cba64af495c78214ede662a3	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614352162000000	1614956962000000	1677424162000000	1708960162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbfc785772f9335472ca05bc71983fced54514c196d6704ec8a8e7cf232d8896d9c028fafc07c45c622fa98bebc52319394c820d22c74bbda1454a2ecad215e29	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614956662000000	1615561462000000	1678028662000000	1709564662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeef5988fa0ba5ed845267db4618a06479ff8d12587c6626d3256eef3bd3df6334a6aa46cb763a680076fec1c3fe64aca6e657745f6d02f213b54eed03bdb2a04	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1615561162000000	1616165962000000	1678633162000000	1710169162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf8cf7321e3c8e88f2aa3b2cba7931215375bb341d9bbefecc8c955ec7c95cb924252f9628fe3abd2c6bf60a1bf58eab940a413a5cbb24f087c9975f773a28ac	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616165662000000	1616770462000000	1679237662000000	1710773662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x822c2e27350f92c25cb57be6c19cd83dfe53ae0d16e2fcfc28c0e39861866c83b98e97b822024b4f4167db7099b3a77b3ccdf163e8472aad4c497996b7c5c215	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616770162000000	1617374962000000	1679842162000000	1711378162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x599c92b2839fcf1a782017e07fef8d01edddbc6e8a106c3e14459f46182db7391ce8500cf973899a30b61f0a371e6de0680d6abd72cc4fd00ed1da76bfb112a5	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617374662000000	1617979462000000	1680446662000000	1711982662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2c98325ca3f836b5b2977bd68a49f8e61f86f723415a7749d0d461b414929bb21a25c0ea65bd920e114873ee553c85d1dbcd4fbe1d4ad24808d839b57ef483a	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617979162000000	1618583962000000	1681051162000000	1712587162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3485796025c9280ff8fc063da1fc342e4ba405320ecfe7d7d31fa2dd320aab7f6559768da4c5d7e2d6e8bd3ee1d70f1f9c199077c40947f5850dfd46e8a273d9	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1599239962000000	1661707162000000	1693243162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x768421921b629bc2e89d44c5086f4d08569e864766199c9486d2efabde82102b4d57efecb1bb8c0b9eb3f13f225cc6ee5c638b6e50c8dcffefd93657280088d2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599239662000000	1599844462000000	1662311662000000	1693847662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5d587ff61bea017ee531ef57161b0ab9074b116882304a3b6182867a1c912899f047a9295cd38705d938034cc3e1ec43bf115c836ba87280a5710e3b1891f207	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599844162000000	1600448962000000	1662916162000000	1694452162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e5c98fbb4fca71cb6d83a466839251da556ce6e679c645fd2644dbd2ecfaa69a15bb2db101abea28bd64dd696e677c9f36b11f9952a94c19a12ab75b15601b5	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1600448662000000	1601053462000000	1663520662000000	1695056662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x19826b59ee4441f05ecb726363c87ce5725a72801ebe9944355ebdbb0b8f70bae0fd8a78428dc697dab3b44fa29bd86cfb862d0b521dfacfff4d4440e185855d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601053162000000	1601657962000000	1664125162000000	1695661162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd0fabf3089acc3f32a19a30d4425264e9f4e06782fd69a14104e7ef17c13a1dfce588d57d6636ce5e6c3f7d0ca586106e63a4e28ffbc50d2b86803a84fbc469d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601657662000000	1602262462000000	1664729662000000	1696265662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x859d4d0e8bd6434447338497237f1473c8b36ada2d9c51bf93606e7201a556b700abbc0c19ec262a31e400301ab97d22e845b8e8b98d9ee3f6a8680edaca4a07	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602262162000000	1602866962000000	1665334162000000	1696870162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf8d69bf4235e83e43ee6f03b20f83bfdc9bc40db44de625759a4417706c47a1941a14e22c9d5cb1960cb1f8c9f901a8a5ded9f02dc7cbebe2a4d7ff9c6669c64	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602866662000000	1603471462000000	1665938662000000	1697474662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x67bcb97dc9c4613a325f968bf98168bf6e0b69cf3521acf1b6d142bc0d278af3b3602a24700c955cc4b8d90bc9c05435bbfbd81ec2d375be19f06afab12677c3	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1603471162000000	1604075962000000	1666543162000000	1698079162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe734caedbdf616c0e70619616a3e0315ae3f82527208def332e43f0472bc6d3983940c3c95d99f534ac5e54d30041dbc0172be86ca8909f27f98d36839487f21	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604075662000000	1604680462000000	1667147662000000	1698683662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x365f767a480f8ca9585d4608837f845fc1e4206c0324f2a3a496455f9f897b5197073db64ed7fae0bd625d329f024627d001e31f63961adbd78702f6f4bb0a43	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604680162000000	1605284962000000	1667752162000000	1699288162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0c558c3667ad3292ec7b5491514aa5d27b9d8523ab880472398fb6e13f194584871f3c2b73c1a2f687ad4a620fce74ebd8b8050b5f62a1b0353cdd6c7af9abed	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605284662000000	1605889462000000	1668356662000000	1699892662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x13d28667b53fe747f5dc89e5c0b70b963c41e142adcfb75f7885f89ac1c6aada0531f792d70b5ce1698d1fe1fc92d2338b6b49f9d9d6e6df7a55c4192808e0e1	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605889162000000	1606493962000000	1668961162000000	1700497162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a0ae3ad9103f57233dd6bacecec569dee20f667f4f81bb30281494f7ba0ea7b3ed9d631d6afbe5efadaf972eb971f7a67a48d6d5b8c1e59f95c53e76ec8c7d6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1606493662000000	1607098462000000	1669565662000000	1701101662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd9d7ec2e59eb578585c89a19b7453c3fbfbb71587efb699e6a6c27b67c48f726d6c079159f5ba2be563d2e9b0b6c6359c1e3ed2541e4c99170a897dcb3bb89d4	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607098162000000	1607702962000000	1670170162000000	1701706162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x22dcda823553acbb82034869058296a407af30311e7ed1dd91a605b8b4cda704bc1245542d8dd8de4da947008a9126dee8a2346ebc3922f4cd5b0456ec1d818f	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607702662000000	1608307462000000	1670774662000000	1702310662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x705935cc4a672f77f771ced6dd3e6a772505fc229fc993dcc54288ae1b4f9c6aaf84e806f63839a0ee4204eb13ff06ec725a77efae8218d740a3b3bb76b2bebe	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608307162000000	1608911962000000	1671379162000000	1702915162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2181fe476fb915dc29f5b6bfe1a1c3d67456b8f9815c43c0863c47d86106354e39fd8e490e5c08f9fe806d0eebabad09430ba857e1fdb1188aac671378dae90c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608911662000000	1609516462000000	1671983662000000	1703519662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa132f1c938d55ec167c1499e007cbb4cba2a41dff916c976a0610e240ee7f45e7f4ee925b03edba22cc0ff5c88dbea8b8cb72554d7c05300d7fc1ccf64d11523	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1609516162000000	1610120962000000	1672588162000000	1704124162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x91943c642be47c16c7431cc0aed9c8d4117334766202aa2d251831834fc569d3875b1098c4fce892427274d7808e9c7ae57b763e86fa2c0e2f147b1dd418d5f7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610120662000000	1610725462000000	1673192662000000	1704728662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa285f2ff5f18e321d664c8ce97f2bc4279e22326578c4f77b5e59aee53ab01cbe29bd7f4bd72b32b2680864f87c5f30621b243cbb46a543b6cc8eff5a4dd0655	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610725162000000	1611329962000000	1673797162000000	1705333162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8afd4f1aba61092e9d6d0c7f12003d32fee36b36b5c51ddc1a8deab5eaaa7cbe497ec1324af7fd2eef890117a27315eaf1ea792c59fe45ad7158c611fa849816	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611329662000000	1611934462000000	1674401662000000	1705937662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x30322812ad5ae9163d0b45226a1f1e501367796c1b53d5e814df5939de7c74ed470b26f2cce4dbe93f4db8cf6864e7304506da27bbd9be90b74bf0a4bdbe8cd0	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611934162000000	1612538962000000	1675006162000000	1706542162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85a1a11ac5af9b6a7c89879afa7ae5d00000f897d19505f1d6da9fb41abd5d4b4c761a3008f0c3c4076c0ca8088c76c949500156e9247043aacce1d420b0ac43	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1612538662000000	1613143462000000	1675610662000000	1707146662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x181190095d44e301c4c49ba38646fda8786ff6e94c45889de0efd98726d91a234865d319090eace6dcb9256d619c64ecfc9fafa600310489a6c2c667c34f77e6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613143162000000	1613747962000000	1676215162000000	1707751162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6526d15c8efd39d21f3fd93738f09dfba2724b2654398c925a82cc4309eecd52b8d88d94cb4e40193198d6c46d552227e018b9a8a95a44d90228cec25fe514a3	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613747662000000	1614352462000000	1676819662000000	1708355662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd531865d655fdfdc9a7da0f89e1b4128ac59075a97ec4f21fd520c8d5a1b57f6bbc3105baf449909582d5ee3e2cdd91241afd6a9dce8b177db32aa9a7f00464b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614352162000000	1614956962000000	1677424162000000	1708960162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x59a58a4951c4cb1f84c1528495cd6a6f0901a177ed095133a0bb90827cfc5561b7644d7d48ff3582bf5d1aff5c4c01cf204be0db6234b9b02a3ca140b10c8968	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614956662000000	1615561462000000	1678028662000000	1709564662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb46ae1aa6bf0a743b61cf2eefdbabe6fd7551a61c2d58ade67412390df48b5fdcc851644f3267bdfc001378a5aa7c24a0aef7a61af3254a6e26b36d84e92c995	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1615561162000000	1616165962000000	1678633162000000	1710169162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x502ac9779853e8192e586ab1e77351f3cb3878f7ac19b38cea3eefe62bc46db7a8a3eb4aad5f584ec2302000be9309cc030ad1fdb7772cd5d2d5346646a03352	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616165662000000	1616770462000000	1679237662000000	1710773662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x53c6673ac079fac971c6f13dd84946170cfbaa674c0fdc7b544d02dae0e156646fb08facf1f468632cbbabbfb83aed96c39a36b871f81514ab07a3e903a7df4b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616770162000000	1617374962000000	1679842162000000	1711378162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdc7aaaa7825d43617ed5a05575c592a254c483fa9d1bde935b6ada895273239b20dba1e2f540b5d8c863e1970543b574d0079f61f54cd1e70dc3aaa4692144a0	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617374662000000	1617979462000000	1680446662000000	1711982662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c08171e2db4f926d31b65b38031d66916146293e020a38fc02a0cdba703b14f21bafad00edc1144b982e476138c94bb96b5c3a710eeecf77e5895bd32b508ca	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617979162000000	1618583962000000	1681051162000000	1712587162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xff092c594bd0d9f73a4f8c6ca6b70f2a6ed62f4e3af63f5b8cefa9a8f42678f989e52e225e5f51c2384761f653e69eb3cee8d2e99412b1c0896c3a5363032ff6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1599239962000000	1661707162000000	1693243162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfc22c52ad9e316063d6d8d0b0601c24af791f71f044eb42cff7e5d84b45d4c21ebbe42abc0199e09ff6df04a1e65a638e161b04bd5fe23215060c63f62115fd8	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599239662000000	1599844462000000	1662311662000000	1693847662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x71a17aede4941db169931d55e1b31cf27f00f28e892518b76e0721b4717b9ca4132f54cf5b1bae8b8b7bbfe2b034fbd0becc2cd62b82f5b0d968d9af348bac1d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599844162000000	1600448962000000	1662916162000000	1694452162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x365e18afa0ec12dc197537d77650032a1252ed4cd547a77d7882c76e660bc6f1236dd412a2140559c737b13dc7d4ce4d524dd62d2126086b755b8e81f9532ecf	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1600448662000000	1601053462000000	1663520662000000	1695056662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x013110058a2824e43133164cf837a67ac964ddb8336c6b77dda7551d02f3ef867e7ca105615e725d5c2921b913a241ead98a4f51c9166325851e4dfdf2718842	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601053162000000	1601657962000000	1664125162000000	1695661162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x89147b4d7acce685d86961fafaad68b57b55f77c6c2c23656aea5a85c22399b8f20dd5c0e2ab069025c9cdc143284434068ec9b35b8952bcc4113a2c0565f0f9	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601657662000000	1602262462000000	1664729662000000	1696265662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0068ac54a1001393269d74ba15d0194aa5fd4258be4b82594ad63291f673dc90c78d9ad4d654bf296e6971d1f14a1d7ad62b73780737aa584c1e23589c93e081	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602262162000000	1602866962000000	1665334162000000	1696870162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1647c5936d3d20887999ddddf3bc88f1b2fd74379b5178e70ddbd7bbb84dbe9c1fbb57a941ae6aad9d6a2fa0189c1de89354029d4d918f914f327c41c573ec27	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602866662000000	1603471462000000	1665938662000000	1697474662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd1230947100ea4c10f064eb3923637ce5043f05106de569a1038216450cd6555f69b5fc7816ec69b7442af60eb34668bf11b67fc5f481cb87e014cabd572f9c9	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1603471162000000	1604075962000000	1666543162000000	1698079162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2ad84fe7ef87a972710ca54c556a2c18507fb669781fcd9a50477da65691a1832f9972522144939ead50fab5802d21238255440f62701da36de31c2240a7546f	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604075662000000	1604680462000000	1667147662000000	1698683662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd3d8715315e37560dd04c71c19bfb15811b4accf952ae89dcaad38442748e01e37bcc31a733223b3731d69f56d6ba39eaedac2da05caeecc436452ac9fb46176	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604680162000000	1605284962000000	1667752162000000	1699288162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfdd30e58476de01242abef24c002cbf39a7f7b92519c3ad3f1a804c4a1486526ab53c7c93df53188efbdd46c3012c192619ae33bd0989d569b454dc7447ed86e	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605284662000000	1605889462000000	1668356662000000	1699892662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x867fe33c56f9ac01525d9d088b58e43a50c7430769f0bc83a2aa8110fd939c5ffda9929c5a7c3e8ae99f35fa6ea599516729fc5846cb21c8143c29f9ab83ed49	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605889162000000	1606493962000000	1668961162000000	1700497162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x340334759053d5cf36e606067b1ed9dc118398336a1bba655186a3b3bdabb181938cc6a54057ca65f4b12af9d2521e21628bbba989a9ceff94235187882915c1	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1606493662000000	1607098462000000	1669565662000000	1701101662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x40290d15bacc7d69091a912abc1468748951ba9a4c394950db99c49425345d1b8bba0bff2cefa300be2ab6a776197256e11ef81430a1a091e63db97daab8149b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607098162000000	1607702962000000	1670170162000000	1701706162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb64e8ef254ba32cb81b345e30bc3e6e75e5a7744892131a39707ae5356fb72a7f9102a6c334000fb28c292d15dec5cb9a78bc4819b36d04429af9a4cacdc2d97	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607702662000000	1608307462000000	1670774662000000	1702310662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc3379a9e2a2e0e6649f2906522252a64ceffbdf4519fea10cdd7967d610e8fce95d4c299d7e273f11c98e271b5aaf15a0e992168cb28f5f50b2223d06f3bc723	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608307162000000	1608911962000000	1671379162000000	1702915162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8a59d7a07ef8adebc7cff53c68bd8c74da89fc1e7e592e26996b7b64bc8d1b37e1e11d782cdfa7c4be3cc627f394c7f4523e1f4ca9f9f068c6392c31af56836d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608911662000000	1609516462000000	1671983662000000	1703519662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2f6a954c1291714302e6161ce3a61ed64b0b60f06d619d992c0840f3af8ba685a63dea4605654c220ca1797c9424436fadccb49b26a11150f35cc22e914ae24	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1609516162000000	1610120962000000	1672588162000000	1704124162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x098dc2a956895a4ee656dcd67769fc4d5967f69771c374ce4c8cde8bf19c3303487bb5e6a44934967457bd0d345b02c0bd82c6c52a606ccabe4b9deac569fcbd	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610120662000000	1610725462000000	1673192662000000	1704728662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x174637edf386fedfd656131e64444e4de68539bd8d5b4a14383ef65680c73161085b58c6161034239b58e6e21aa9f8d99046809a0d9d598f309daea62c41adff	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610725162000000	1611329962000000	1673797162000000	1705333162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x078a6670a2535793fc44a8b780ee028fbae2dc08bc74467bb390cf22808bb0234c5a2142edef7d3b6eb2dc77f6415a0a219b2c547c2b98cbba315b07a78fe197	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611329662000000	1611934462000000	1674401662000000	1705937662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xedeb939babb4cb26ebfb73a2b7e543f72745bd3c52ad681332723495d72c231b91aa3ac36e9a598adf3f12c3a0728f05b4f2597062e045ad2c1941ce14455354	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611934162000000	1612538962000000	1675006162000000	1706542162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe4c8b18b6f03f622cdd98f7152b78388cbef32cb8ed91f8202f748705e561fe97efa2e5cf8c0b9bb16acbd2a49ecf171bb40053b6257dfc2e6431f1bd071f863	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1612538662000000	1613143462000000	1675610662000000	1707146662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x21aa79d7701aa97df973920b178e27e16e1304cc335650471319b61d3440ce04b50efd76a99f82fd3747c3c8c8ce7c7e94a003a0bceff6473f1230b0034ac599	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613143162000000	1613747962000000	1676215162000000	1707751162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x143802786edfc316e6a5af97af5f4edc7a735298f5f36b2703c27fac70725101189af172f6538224c14a066021d938e968f9c65189fd15d67f6963b6dc8e484b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613747662000000	1614352462000000	1676819662000000	1708355662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1843515e04dc4403ae6ff5675c10fc8b377965d33e8122465df4db9fccb93d9d6cec6362fec3333437cd3d051b8d4d28f3dc75e758086f3b54c60e3a93f689f8	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614352162000000	1614956962000000	1677424162000000	1708960162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6213dc7766ae381f652e420e9d150ba0fb064c84db8b2b02be16a7b16a1619793a08ff02d5a1017103fb8fdb7a7366690bacbb1b2618def57d831480ec5fc4ef	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614956662000000	1615561462000000	1678028662000000	1709564662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xef05a9ca2955b95572e1ba1d163d95e26b1cff10e5eb576ea72df1f1043c11f27534b1435d33a257893c16c861e41a42384e34754ac759ee1ef0776e743a829f	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1615561162000000	1616165962000000	1678633162000000	1710169162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e22aebbc1af65f0f2024cd949e8478c4f83008aa46f069bb610c1cf570e699259592e5417a21f3b9c8108004abbfc89439a942e7f2c27f560dde95d23255bef	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616165662000000	1616770462000000	1679237662000000	1710773662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdf89886b999beda5be84403a7014a64e04f85d24531380bf38360604bd8afa15b033c53181fb8d2579c99b1e75b7a96746ca3d8ea3a223cf305d58b0b169e753	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616770162000000	1617374962000000	1679842162000000	1711378162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x28e21d3f94d5296261a947162c6f4d42add2e7c63baa384ec5e0ab5193a069405ff05c872540cd2f12cfcd8879e82bcc27fa449c98fb903c1b8630c09211f8d4	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617374662000000	1617979462000000	1680446662000000	1711982662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd03f21b4f8256a9a1aeda36b48abc2519b591983869b5f81b64a03ddaefc03930c69a0303c73cafa89e548599d850d3426107f3d21d340b75ec29088881b79f9	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617979162000000	1618583962000000	1681051162000000	1712587162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x542a1d8a0f8d1cfe6b90fdd17077ef337ce1944384a93083137fe72fd8ac8fb37b02f701dc3f0fb3800f7915b05831f8cfbcd786e2ef9c668f309adaaf4456e0	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1599239962000000	1661707162000000	1693243162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0102a488ba3a406637a8e848a62a5b41c3543957003c5df7400e8e4f38bcee9baeb1703d8ca9440d0bf98640bcd1a85d231b4c66821b7054ee4858500cc0be00	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599239662000000	1599844462000000	1662311662000000	1693847662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd9279267ae071036658c185fc3df47cca9648503eed9c51bdf294e28d94aaccaca2beec4acc44aafeda329d7341d4f491d1a888b7a5be9eef07a7dc05d33a135	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599844162000000	1600448962000000	1662916162000000	1694452162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x12821a2e7f66a445f9bb8b640e0dcbfbda7f276ee232ba66fd91552fa5db04cac3cabe1664d24a0518a19e742801a1071be57b3bc46ac3afcc16ad19ed6d7147	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1600448662000000	1601053462000000	1663520662000000	1695056662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x926df29efc673702405258732387a58b720660b30ba8398476819eabbc15d316aa84bffec50bb755ae9a47d908e6e03471ce7760a2516c867a00a1f80fe8f597	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601053162000000	1601657962000000	1664125162000000	1695661162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8d679b9de6b4f0fb8d430e1cedf0062ef3de03ac83b7bc0d5854d4590896abfeff77f4bbda20aaa4dcad2204d04824ea151e6a57c96ee9b1535ceadeb4fbac39	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601657662000000	1602262462000000	1664729662000000	1696265662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc5e6df316dd925a6cba6168de2859c9be03cca07fc52dcc0551a63ef47a4295aff3c7be0a7a6b60331904ce4a5a2d8b781102a1d2083584c733c13644fde9f91	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602262162000000	1602866962000000	1665334162000000	1696870162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c4f908710fef598a49ab52f8b82604f7be04af1ca1a01eaf7b83e6b0ffe975b093e24f13070483e7b892999267c3c7aa60b0038f082f09a6665cbf88e06c413	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602866662000000	1603471462000000	1665938662000000	1697474662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x15f7eba91ad3f7c4a6620b7268fb144542d10cf7dee70201e1c2779174fafb933839e7adfb50b52f8065ba98a3ab13bd1fa88c4bf3499d9ae5e662a2a78ef038	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1603471162000000	1604075962000000	1666543162000000	1698079162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x633bc321d27734a688d4c2afa4b0e6700e49dddbad953bc2fd933740c876b26efd0301a5df0a37946960f377ea766b54a0f293512e1bea24519615b0d573171d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604075662000000	1604680462000000	1667147662000000	1698683662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c8378345568ab8b1fcf5586d213d22f7aaf3e4b425110d13960ebde8b4453b08b3fb8f4c3c84566e631d53406ea84a2f7394cfc5b11ebe7c1636b74df2f48b1	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604680162000000	1605284962000000	1667752162000000	1699288162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0bf275b76d65862cdc35b575fda643102c451a8979fadb1e68dc761233b63ef1240d6dccc0cc73afffd6e4061465cf1a4898b9ab15c0fb3ae10605aed6d171f3	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605284662000000	1605889462000000	1668356662000000	1699892662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdcd009108ae0d58708c02c93c1fcf197963f9155dad7c6ef92ceb128357bddae13e8a88e17c1724d9f264c7905e9ce520cbda793eb39a30e4dde7be5f11e4d26	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605889162000000	1606493962000000	1668961162000000	1700497162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x46ff4174767c22804b78d432f543c39131c0438248a8aa1db030202633b0b23b1bd646445b97f2550c422857161dbe6e419ad3c1a4b667f3a04159a1c9d314a7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1606493662000000	1607098462000000	1669565662000000	1701101662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7d437cf818b96256cb2ff2fe3ee79685ea20c1a39b3306b1be97940d2a08b4d91e57e60eef76b502f8a9539e6ffab418fcbd65e6d72a152d672688fff6f200dc	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607098162000000	1607702962000000	1670170162000000	1701706162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8e385c1e302936cc14574bc44c20f18b3b503bb6318d814452e53d65a338b5ea6b3f54ca10b857f7ac0dc7f837e0198ed783ec454567742637275bcb21f622d8	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607702662000000	1608307462000000	1670774662000000	1702310662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1af17b44864c8502460ffb86308dd0e24a5f5031913309634786b84ac40b9850e0264de3d9be736f8b6ed8cbb1b831835a7a00e9f06437c38520d376cf5a4287	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608307162000000	1608911962000000	1671379162000000	1702915162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c74667eab5ad0cd5feadbea3a346131d9b7551b1688d50870b9f89c7381e3038d93503689e8d4176948279f84452244091f2917314fb14e52ad7c394d72500e	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608911662000000	1609516462000000	1671983662000000	1703519662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xec5aab96ba3f92f1d48e7fe9ffe79dd4a7cbaeea7430c136b9bf4e8b4d5833ee9138a95aa6efd305f84aa5891d64307c4658b33620d90999bd9627ef4cd36c7b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1609516162000000	1610120962000000	1672588162000000	1704124162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb128d2d75009abbec99c353c53fa21319191e950ccfc47e2651d85f0d36a99a2945b800d312df87458e705412dc5e778f2a48a5718701260e227714fdef93eda	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610120662000000	1610725462000000	1673192662000000	1704728662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5117022b818879034d480b01747e33226df8002ae3485cf8dfde9b8a727a1a4163c445e7f06fcf0248abffb60b940afe21da9a42eb74d94a308a79087de152e5	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610725162000000	1611329962000000	1673797162000000	1705333162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdea87d8ce02bf32cdc40af99968e7190bee010520e863d498e35a5b516ab90ec9a8f315dabf287466bedaf67d5360091e1def57e8db623f7e99e8617bbb4af12	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611329662000000	1611934462000000	1674401662000000	1705937662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9cba7234127cfac36113acf501ffb09d3c72f744418434957709661cf0b7f96deec0b5a9a51ce59a2f79f2e37ba3b501ecd0b44ed3d5243dc9cbe42d5c6c0639	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611934162000000	1612538962000000	1675006162000000	1706542162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1b01c75b3268f90065e72062777d7a85f5d01fad9110c622c775bc13408fa4c7a2e26395822ac816758c6d5e72621adff00d49fd3a9c83e94a578dfff5437a1a	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1612538662000000	1613143462000000	1675610662000000	1707146662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x138721e1d1656e9a4c73249e2230c8f2c107b06fede33a824f4fed861adef150f336c70c59436190b8b5f6afaec89a8846edae0dddeac129adc65e16fbb1cd21	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613143162000000	1613747962000000	1676215162000000	1707751162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xda48e9b6dcbb86a8a2267bfc6fef7b34f9f98d07db6e5611c34541215dce2d032304f561556e7aee87e94f7f7500595fadd3646083ca3d579de1770a4c75bb53	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613747662000000	1614352462000000	1676819662000000	1708355662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x366be0a8000ff0cf13b623d44fabb0038d4cceff616d539eba995d6395a203bfeb13e794c6f5ffac5ac400ff67425688c1bde9d76bec11e15f1db390534440e3	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614352162000000	1614956962000000	1677424162000000	1708960162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x469dde33c076fdddbd3d6abe77e6cf3b301bb5c77cfff457c94dc11dcd71eb8b783e5e9da7256a08b3c433aee82d1b13cc680c2bbc2cb2c9577fb80a98588fc2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614956662000000	1615561462000000	1678028662000000	1709564662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf6f520aca8e6d284d79523ee1a2abedd628b642e423871c11b3b8274b7e9223dd5a2159dac22c3e55796a1dced5ec3e6f8aefa2d471bcaed611eb2a1d55f3f7d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1615561162000000	1616165962000000	1678633162000000	1710169162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2e2101399fdfd83099d8ab4a3d33cb833ca878f895081d5644caa06a00200eebb8afe831efca4b4c29c82acc6434e1603476646eac82fa6954c7a779942971c8	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616165662000000	1616770462000000	1679237662000000	1710773662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbc586059437090b7a5c4135c1739ae9743d9ae3ee7f0e81d43bf523c06bd47b5a1df7110c0fb7de6edc1217f73a110d9579f87fdc195fe069449bc9b890226da	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616770162000000	1617374962000000	1679842162000000	1711378162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x731ab9dcf0c2542fc535cd1966e3754a4b8e0af1e2e49057b0883414a399091fb39ab129c0bee570c52afd759ca870d8d2b65343c89f06ae97d5685a1ec36ca7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617374662000000	1617979462000000	1680446662000000	1711982662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x98b3fa0d20ee7a9408f9b9ed4ff7951444aba09c8c64b2cb2b870ebafc2c14b8dfa9a3bd5a0054bea784095e5c0e9a89b15de3b70ecc442ba62c14263ff9d831	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617979162000000	1618583962000000	1681051162000000	1712587162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1599239962000000	1661707162000000	1693243162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6caf2f7d82437982eb34695250c8cca444a3e32105ad03803bee173f906fbc27ba73d206ed6bcf3210e72d2809408151525a64e46f19b64d7e843526035b2b2a	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599239662000000	1599844462000000	1662311662000000	1693847662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe813084b08942107c1036804b0a66f0064fe72c974a9774fd01aa81c0d4e3a2dc0c670b793ba462bb74c7a33d824687128b1ce0812f9b0d9e06371487c7ecda4	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599844162000000	1600448962000000	1662916162000000	1694452162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5bd2f3ec9766ce7bf14ee04be8428c7a3c984f216a45c5b051b4e2056e4cda32f776e7fc48cac4e9d42914b51b8a0ea38ef73725e503a5abaab89914dc011c6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1600448662000000	1601053462000000	1663520662000000	1695056662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x987338831ee3e41817447e6e2692de08b442af98e76df7b9baa7c96d1ef3491f08ba129ea8a69ad2bef03068e37bbb89fa6c30cb56b8ad581123411dfa62d918	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601053162000000	1601657962000000	1664125162000000	1695661162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x96192269867c89924cd81ac712604ed288eb297c8a5e550fbe537cf695d783879f2238b9378485c3ae4b819797e550381c7e96c3381238546ff124425ea34e6c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601657662000000	1602262462000000	1664729662000000	1696265662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe850d183dce8e8a765b8be3b18e0b97657019779d6c9d148f51a7d5fa7e13188deeac23a43d95bb5314082a4cb5ed4ec3ce6c3a7a5b0912099c802b7bf7db81d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602262162000000	1602866962000000	1665334162000000	1696870162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa591ea73ff8e09d0305add27de09b373a8b386f9266171e49aa3f38929bb5bc5f18b690ee41df712a1491947574dd7de06c78ef3d251aa4c3735d6f0d8a73548	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602866662000000	1603471462000000	1665938662000000	1697474662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2edac2e9e504abcfa797c73507dd195e7547f266adab7a3d0e8da8b7c3521f67db8093fbd59ad35c197bce82403ab192115c4288f94d084e5bb319e51f53d46	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1603471162000000	1604075962000000	1666543162000000	1698079162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x97b2e86fc7a8c3d83f5a6facf4b77570144913cc17cbf74851b506441730a234b00d3a5fde09125a9a8f103e55b1e1d618e2c4bf22decaf0bf0bcca978954fd2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604075662000000	1604680462000000	1667147662000000	1698683662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8d6c926a7ff3d364676bfa583d909b56f4bfef8d58f293ae271e9c30f6892c4bb7fb051b96f68259fcc7b68d52e2a191625c372e8e8414721ff8c82dbdec64c5	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604680162000000	1605284962000000	1667752162000000	1699288162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9e44de77cd7f3084dec2ee6049ecaea7f525a9ab8ad8086117a45ad39657eb56fa0ed3b7c7d960fdf0066c0286c27ba9eda5cae368c06b8889de41eb57f5904	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605284662000000	1605889462000000	1668356662000000	1699892662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6888f2787b0244fcedcb3ca37f88521ed931c03230739bee5207ace33b573afac022b618f1a859413f3f03ed904e9a818fabd739dd115722381ab21f78621a70	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605889162000000	1606493962000000	1668961162000000	1700497162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x12acca40e3c175a098ff42cf68341bb77d4aa2d7b35b94f001ca5d74999cc03fbccf1b27b4873d35f8f85d542be205fab6eba9602f1bbf0fae6bce731b94b802	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1606493662000000	1607098462000000	1669565662000000	1701101662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x07c6f9838fd661580efc96c03b612e9185535d81de5b02a4e3da6ed81117423bd4161c9e3df82e571df5e609eeb06672d2e1a99fe5bffd1a1d676aca9e37fa6c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607098162000000	1607702962000000	1670170162000000	1701706162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3650b9ec598ff7640f29efc07080830ad62b8fe56c70d1ba0a3ae4c6e22fc9cb84eecb600a476b0bf48c7046b4250e139d19c867b54f3b255e0677c41eb6285b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607702662000000	1608307462000000	1670774662000000	1702310662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x064df1d96e2f8e453d01daee8d06b25bfd79b53b5b9e1a26f6d61c35bf0869dfa978caeb43e9ec599190efd8096f97ce534a682b0c08fd359bb381cfecf07064	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608307162000000	1608911962000000	1671379162000000	1702915162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb71e5f56ed5e79b1866c72a0105dd18b58ec4a9490e8c8e433568f58dd151129cc39c72588c35d3d4ce2b64dc02897f9772bc289f23f36e8e6fcfabf6c80c29	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608911662000000	1609516462000000	1671983662000000	1703519662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x757729627a1c8e4b12f2b90b4ec8d782e603d7784c4929c5c983c3da643c7fdd7ad3673dd0d2256cf8e17e2f1620142ca6a89a6710641212258245757adbae5d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1609516162000000	1610120962000000	1672588162000000	1704124162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1efcb1911e2f2fb2383f67c63c6fd73a2f88178bfbcc81cc76ee7c4d0d63bb630018846235368f1c645bf293ad1323e7efec3d59289a2744a88b48e286e7421c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610120662000000	1610725462000000	1673192662000000	1704728662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a85067b4a1c9164b3ea47528caaf522fc7ae38ead6211d1cc9ecad334e9d129a99cabff2d59762251cf623d07765f6e85b6822bacf7fba79b3c87c36638f25b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610725162000000	1611329962000000	1673797162000000	1705333162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x54379f597afd4132aead0a5201c8551a5e0ef0da51d6d873094f4f5a86eea77c0277c07d315f7e53c69c30dc40f1b54b6242bab28611534f9b6d030caeaf8bd6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611329662000000	1611934462000000	1674401662000000	1705937662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2f51a6e7b5b71f39b0818779588cbc8203e500c8b5b56e315f69d75d8832427fd8e326a8465a54870dbc8092bfff8e984d00c348a36c786f7c77dc92626a270	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611934162000000	1612538962000000	1675006162000000	1706542162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b7c2bae6331367431732d9819dc55ed6f2cb283f1f90193f32fa0c25e7d6def5a33e659a09f61fe3ef479daff4a5e550baada8b1470ad5ab2508956241eaf8d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1612538662000000	1613143462000000	1675610662000000	1707146662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8d53b8c41db0f94bba3b76e251c57a06d8caa50ca747ff2d41f4843d8a63cde7292522df8f9f208e26595e45976a7e4ca8ac6b71970d65cc331695f46f10ed16	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613143162000000	1613747962000000	1676215162000000	1707751162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5943735b62291f32f4d9c73a08b95be8259fe6a84203f086843287cbb4084ec7652b3e3676f759535eace79060a8dd7f6ac14a2c482fbbb89ea36a9aa8dd00b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613747662000000	1614352462000000	1676819662000000	1708355662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e82e7c6a2416ba001d6ebb73dfdeb6cc69da85ecca11b8e9e0f57591a86af60a5962d778b1429451c151d06f9df18f52a385ab339775ba78256492fc67e0231	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614352162000000	1614956962000000	1677424162000000	1708960162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3713cec1334eeed187e60424cdaada646660f7113a0f1fd51ccee4daefb8540badf697de1d016046a817f1777bec4149f1a2d6c781391751737ffe8a53c28f55	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614956662000000	1615561462000000	1678028662000000	1709564662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c061a9fe4b756f90700070f9d773854dc35a58cecd216d44bde5b2730ab07d0571c43c5fc30bc17c45cc478003ecf143b85918ae214a423d91bcab0de5eaf0d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1615561162000000	1616165962000000	1678633162000000	1710169162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f16b22d9e84d8e4fab6f54b8ee4eaaed57f8e0aedcae0aa1401dc005ca3220fee15231a8d3ffc9b3e64bde0f4569f519672555080aa48d8d6f89cb9ba0ca817	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616165662000000	1616770462000000	1679237662000000	1710773662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9afbb43383df0629427bd141092a2cb73ee6f579a7dce1d8a77543c075cad3746d37c3bbaeb1238d9d8459b341bbcf974a54fe4099d5640c175c65400651a7ea	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616770162000000	1617374962000000	1679842162000000	1711378162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6f9f1aef92fbee143fbde01befccf34792a69edddb65e765499c4df7e239f04074c3e8ba617c1d75627139383dba79ce84b29174e90cb5fc8910f5cf4cb27ee0	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617374662000000	1617979462000000	1680446662000000	1711982662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc315fd069648e7bb64e2cfc2bf3840524a907a69a988c22d0442b29563f4639c362d19ad137a71957ff9dc713e2099f7256e79a443f718fa9cb71269c0693e9d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617979162000000	1618583962000000	1681051162000000	1712587162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1599239962000000	1661707162000000	1693243162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfd29fe15fa09f7fbac913332aa59929463308d941d8beb0d2f95fd9298167183766886e256bde0bf68306b65b68caf0b489102c13a4e4a9c4b71c2c58d4e427c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599239662000000	1599844462000000	1662311662000000	1693847662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x66e2df90f6bbc0ed631660b96dfd660001e8f79d0d639aa6c7b9f1d6edcfc64d4b2ed211dd1dff68d60a2f340fc83464c466cdba9bbc18bf0ef0bedc3d4218d6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1599844162000000	1600448962000000	1662916162000000	1694452162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x82a3a9b89d7a024f894e8a4a5fb9c1c66f9ebc0be9714b2b0279b449c1d8acc84b714484d0cd5750401de94b72eba7b184d887ce9eeb277b95a04f34db679a12	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1600448662000000	1601053462000000	1663520662000000	1695056662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9f147d39598a36b76cc6717d35a38132cd90f47665ba29328ea82a2dc302dadb03ab2875dc9466d731007b2e9884aaaa2d955b20440079abcb89af9ae4234585	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601053162000000	1601657962000000	1664125162000000	1695661162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa251a4b5b81352258e49a2448bdd780209f42c4d1c9b402380957805f2a7800acc78e504c774be4cd10869a4c8183e3520a57177056bead7f41240a265024e45	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1601657662000000	1602262462000000	1664729662000000	1696265662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8aa7235206b0b4fe420bb4538cc8d5332c7538902bb6519d4b91d44ff73ee501761dd757dde656e155a76b7195b80ecba17c9dec019073f5ca11e34e30a3412c	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602262162000000	1602866962000000	1665334162000000	1696870162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf0239b2f4614492a7dbfee57e88cdfd7626d58fd3a8cb3e7d2466657575de4a5fe7f2049369282cc06728e976c5babb43c9154b640f6bdb7fd01f1bcda808ef2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1602866662000000	1603471462000000	1665938662000000	1697474662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3699ef958eb6e118e4f2b665962bea4037168cdce82ad6ae8d3e7a15960f3c05e3c6268ee62d1b1fdfa95fb727d0f22847da7cb04fadf4ada524dfcf12149276	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1603471162000000	1604075962000000	1666543162000000	1698079162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x94853c699d14e618db0a5d84bd6a28598a2196363a141b3c03988f31e6acd70afce9ce57e8e44dcde112a08b6fca60087c9fdc9f44f3b25fe70de9e76ca95251	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604075662000000	1604680462000000	1667147662000000	1698683662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x69c68f61de4b5c87f7d774a7124cef084a09a6fc5e70b1c55c229a6a6852b8feb54e72a783f450bcb1786398c6e92801f90ca950214de83823096fb526ff36d4	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1604680162000000	1605284962000000	1667752162000000	1699288162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x323b4b11ea8a8fa5dbd0d5b871c36adb58192415fd72feb7dba9c530e5333c4b05b5f69ebd66b473c3b4b1e2731ef9ebb58db2fce3141f27fe80fe79c98772ce	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605284662000000	1605889462000000	1668356662000000	1699892662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5b33a20951371a2f734c9181a69f02d159cabf74e42422bec54186f5215fb18d538461c0f4796d25ea1f5cfaad5fb24d8228c91552942d7ba43d983d8e162865	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1605889162000000	1606493962000000	1668961162000000	1700497162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa8a1b3326a53e6d766d2f66a17f59153cd0fc4b516dba4d2ce1afb44339061e2148921fd83b911b86eab85d3a8f91efc3b9ef3c96654274204ab597e5cff24db	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1606493662000000	1607098462000000	1669565662000000	1701101662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x387c5e517bb6d5bf29a7444687bc31ad461764cd194610a47c93093aa31af96914023748acae391444179e69e5969ff07f75c4c2a71a58ddba5650e5b32f5cc7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607098162000000	1607702962000000	1670170162000000	1701706162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa892d2166044fa6cc628837932082402d841e03b79d51257a229387b64d229434b9c55b4cfde213c5a645ddd1edf4eb4adcd88d84d9c55504ecc1ebf32f1d7df	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1607702662000000	1608307462000000	1670774662000000	1702310662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x48a1a541c6307ad59040c8763ae951bbc663abc65d9fefb9ada61f51bb70e915bee7d017d6582daf39d4c5b8420db691e2ed8e39d99c445590c41484d88925d5	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608307162000000	1608911962000000	1671379162000000	1702915162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbfbc45f397c8a7b0f99c2e695fb06e03f13901d4d42064398393e2e9338e3dff1d78b4e3f93c6cdebf9c42a6e656b5ac1e843b2776c440f99decb744e1bb9ce7	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1608911662000000	1609516462000000	1671983662000000	1703519662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x761e148528be1ec1d524e048e702f2843481568672105607630e9830a19908076b89b5dc98335154779f047cbe36d8ec88d6de351b752147865380fedf0e9878	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1609516162000000	1610120962000000	1672588162000000	1704124162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc574a3f9cd784a39cb87ba10f51379b9d9e7ac3c620bf334e9a643e7a303db17b909618c3998dc8f6fbfd46b65d834ef0ecaac0ff312b7349dfe37da6fb67976	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610120662000000	1610725462000000	1673192662000000	1704728662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf2512604cd673f68d6a39fa93f5a96c50616535d324cc81b3ef24d09c28c7bcf0668c85baf1530618c810db2b2336175b0b739619e693dd63bec244f7a56de02	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1610725162000000	1611329962000000	1673797162000000	1705333162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe54046f051ffe17f96c8dab3946f2d6982be6c7f2db629f2c4569134ae6118af24c520ae3c0e3c641b5f6050f672b91e6299fd14f1096ef359aa4c4e4af645de	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611329662000000	1611934462000000	1674401662000000	1705937662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x11f1d68f2429ac07a03016cbe7ce2b5334934d9a51764ba67f543ea0e71259d12f334728f664123891b3f3cb1b4384ea529c5872d37cf2cceccc98c521d5146d	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1611934162000000	1612538962000000	1675006162000000	1706542162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x939f7b7cd594a264755a8b7e8053994292868ba012e11179f6fe218a66b9c95a4dca1d3abec1a5e04dcbe136c41cf2822d75db71ce03009945aacc39b186cbb8	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1612538662000000	1613143462000000	1675610662000000	1707146662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x06abebf07d2c05a9b410f5d0ccea4713d3dd731006a5e9248383000cc4ff0d9f6cc9344b1f1911b6cd42aa650d106f92ac1208f2560b31b1c9c8f4e9e80cb2f1	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613143162000000	1613747962000000	1676215162000000	1707751162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x19add123399aa76baa0da9c72228cc261da35fde4cb71fd8c6b01812089bf2185a9fa908b6ff4c479196356ee8f57a94d8aab0d035a1f5960974f86abfe17b67	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1613747662000000	1614352462000000	1676819662000000	1708355662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x46c2aaf853adb143997fa0dcb7dc8a0f7efa00d3348bf33e2c7984d33635b3f12ad1e252ae4402ffd61bc003375b62ae0159211344dc4e1153d202a3b38da8d6	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614352162000000	1614956962000000	1677424162000000	1708960162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x78fdd25097dcd79155bd5979eec638c08a8aa6c5145d0c61706a4112c8c65c9d44d8110fd8a1f70b60114625d8a04c7293d18281b668785ea29df8259ea4e2c2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1614956662000000	1615561462000000	1678028662000000	1709564662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x09f54bf9ab51a12fccaf2e86abb850a227dca179e208a47bc2938a62a68480109563738ff1878b975f2bfe00a6c9e2ffee0182c8ce755b9f0a6364fc84b554a9	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1615561162000000	1616165962000000	1678633162000000	1710169162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9d7c045cd7520f74dfafe5a2a85cd979d66f2ceda3e41dc71c637e3273da9ec801bcef44eccbedc78707af23290d589b9e8cb9481304571a1d1acc0673f91c18	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616165662000000	1616770462000000	1679237662000000	1710773662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6bbe4345086769dc1822c61f8e470f301572b533046fb636b2476bd0a57f3531481d1080d91cbffda681b2171a4a3196e89d283053a4798750cdac3614112364	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1616770162000000	1617374962000000	1679842162000000	1711378162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xce4abf35629f73c118198749639ed327aee5afcc096b674d4b0d313b3fa0cd86329b059888b455fb0ed1ff016a77f42d45bf04712879fb4fbfc65334590ac1ba	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617374662000000	1617979462000000	1680446662000000	1711982662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4bff4364970c8e8ea4a753543db58e61d95241000561fcb1a121cfa8ea7293973c2c7f45626a8d6c6606164c80f36ffef3f311747fa99f918d7641dbb715be95	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1617979162000000	1618583962000000	1681051162000000	1712587162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1598635162000000	1601054362000000	1661707162000000	\\x4b79f521d8ce5a20453b2d58e7149fa2899ad14e7f9af951606376377be8ddf3	\\xf093443b40ba959acc8e9193c11236540df71e8395dbc3ea2a1838c0b02647748ce779c8ae958d1b80c314bf0bd0f310e4c1f82d983279165e43ad0071e5aa0e
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-08-28 19:19:26.664501+02
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-08-28 19:19:26.834392+02
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-08-28 19:19:26.91219+02
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-08-28 19:19:26.992903+02
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-08-28 19:19:27.070275+02
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-08-28 19:19:27.148794+02
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-08-28 19:19:27.228853+02
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-08-28 19:19:27.704938+02
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-08-28 19:19:28.198964+02
2	pbkdf2_sha256$216000$02pq7lxSYeq1$2Cucdbp7kaxQmdgERAn3DhLb2SQSd/rII22/MDET7H0=	\N	f	Exchange				f	t	2020-08-28 19:19:26.755571+02
11	pbkdf2_sha256$216000$HlrJHv2WwZzT$wIAy4IfOSrLI+DKndwSX9l4GghZXqpSYMIuTDgi9EA8=	\N	f	testuser-tlrOFF9Q				f	t	2020-08-28 19:19:29.350308+02
12	pbkdf2_sha256$216000$uMqm6fbESu5G$pWI+Et7uVyAJ+Zh7MAAnJMeRMsfYoNKwcJC41OCdBTM=	\N	f	testuser-vvxS70aF				f	t	2020-08-28 19:19:32.621732+02
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
\\x42d0f6a215c182209d58c0d04efae56fdf3a1de408873375550fa84fc5f80622c0a1a01b0f7cc64663001615d304ba884d95511dbab07ec3501f06140205d920	\\x00800003b45093e996e1b93357a9338d5b4fe279382fafa19191ef7ab0b4ec609e538fa07712cdf50f9eed39b4418bc4789143b70a9e06b1c57a075cc2628ea862699c844f143c36591891f62d0cc90ca8f1af4a7f2794f2e1e732a0246a3bbbddf1412020ef2e73048675c352ba797e2e5a6ce94f7888a58acd2d263ce8f008be61410b010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xb4312d75977306af5a3b48aadf9592cccd9ec4bb9f63db1b609729293513783d9e01e9fef394b543592d4ffe0e1131fa04e52c8ab3151226ff04d900317afe05	1598635162000000	1599239962000000	1661707162000000	1693243162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x25ce1e89bc410eb117ca087dbd652a37e5df542d309a7e77f0951bf8d547597d5bc2d0a80d9f396699c536ed42cd737e4777ab903b5b3fbb14672d7aab390394	\\x00800003b681f9c6613be07b163018817b46338614a6884a8b565d90931c01409592e73cfb95b61993e529666f3a380b8a3c9ebb826ac9190b06eba6f0a23d569306a344b560d434d29a817f3daffc16c2c0e6525a5f2d000e1dc1a3b15e9c594b7257129bea8adc22c8852bb1f9dd3856e8f28dde88f627e8a6bd4dab3f9b38ff75d881010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x00a1fe56265211df8341b6a68c6f17351e02aeee7b4be59d54454c18326ca7fb122b6668c459b6fafd4676f2eed4c6b82fc9765134f0a2da4becb7b14b53ec0b	1600448662000000	1601053462000000	1663520662000000	1695056662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x450425b66f3748925b4bfb545b02198391a1e64452b342c10182949d706c06f5e07d050ac9b1f6cc4902e5e7b150ed86af3d93dbc5ba1a33520b86d9293c81ed	\\x00800003ad4b46c5a30ed2bc412fce9d2adbdae05d81b7dedd754e27f83610b5b914e949f75c1c8bf51e73d277e4a42991cf14cdd2a16d77c7b71c1474e7b677b1682b956d13931db5ac78a70051706e8d7d1e8602ac45d70a647b11bca7218293049cb155ad67257099a89594ef382bd6cb9e270f9fddfeceb35839958a9b77247a2e5b010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xa5f0900eda1ddd15d934149c531a0c0da38e306af66469ef74c4328887eeaad3a723b4c49bf903b1de2e97ee4322d7a6dbc3c079575e65210ccb4c946a647109	1599844162000000	1600448962000000	1662916162000000	1694452162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x713af7730ce50ba080a3f39b6cfcba0c835c51315690eb92a69fb1c5f051343db00c0f119491063569aae188f994382dbd4545c999a209424d6ad2e582aec791	\\x00800003f048d19a9721baf70213ba4565a18dff2ddb0edab87b5035c63c1ce341a1f0947e3ac49848d41a9c28c8c0a45148befb8052271ea9a9df13671900d3a98802c398355f0f6ca6c17222cd8a81402fdbee788799176f86ffcdb3aae3c37f76445810d7486215c6093447499b93d9f399fc8187b5a04889baecc8b069e743a0c063010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x6534774a36f84fc4832ab2428be71b5b6d502a6a6aef8dacaf4facf69bdad021b3ea376062f9d0045932caae9c3892474e616d63190635c5925f862f50d75b0b	1601053162000000	1601657962000000	1664125162000000	1695661162000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x72db9de946f5c3792fbe1e3c98ff4fdd07a1cc08198002ff142991ea9a8b70cf534518c550cc31c4c639b33fde18dde78a229fc7811692c0cc7656701bc438ad	\\x00800003b8ba29dca28c5f2b2479ad1655797bd41977da70be89546780da5f6d7ba10cc8aecad45933cccfd6bc7a8091c67c7271035c804246effc4157279e14fa38aca1444036e9c46acc96fd3c5b31374b9b53cf7d47f246ccdc67853bff2a8e3e81c015f8d3249768a12d14561821b7d2527a3e8dbeea27c46efaad51aca212a04bc7010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x752f049ef241a59625828d12a225cfb254d1f4515b79da15024913f8462aba4210ea08f3eaecefc6c68f82d1fb9befa0a266711c49936bf5c6648ff24cb9630d	1599239662000000	1599844462000000	1662311662000000	1693847662000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7a03a3ae909f1954488bf99c2c524ef40810ef2baa989a5150de161375a73d1d6a76752732d538de535ceb059d946e6e5565d55951bc31e11d47d51c0a81bcf0	\\x00800003ab98676d7d1c52eb9b050537d615aa1bb8888cba6ac9de1d9b89e85c088e61daac88cfbb8db6f05578c0e00e41829f9f6ee1c2e53f261b9983be6308aa12044954e184e49a3611f4db6019bee26af50f02f2b0b526170c77450a24b171724c3e233b44c4bdea08bd4a120e86b64ab08102fa3d0adef7efb04bd8be3ffbfa0655010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x22bf8bde13ea0847f6f0554b9566a3550a8c4d5949cdd6ab77978e5b0397215b1232e4badfcb622d5e775079dbcc388f5ce772734ccbb430bba56532fb9da30d	1598635162000000	1599239962000000	1661707162000000	1693243162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3185c80cd8790435b01601ee8a639d450a86c3d652ef2397dc55f789a12cdd67d6b8c60ab9ba836033940c8f65886879adc2d87e2eb1d9a95875c9c9a0ad227d	\\x00800003b56f1dde0c9659cf3c65af8ffa42513c7a4d9f2a344ac05a26f6606f4709bf430c8508b8763f63fb0524b264bbd24728d6e5933d242e882f8aa33ee07d8cc8bb4cd026182af5b49bf3d943cb9b2759f45a8b22719cf12fa2e48ffb9c2ea1a184aabee842ece64296165318aefa3256876e347e09546b0e2f778319dd79eb27c7010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x0977b45f766ad819f20622656baa0c1ac79bd975d6a24d39054e74a3a4b9c9e074cfd6d493cd5eab2d6e72827ec672588cdab69e5fbbcef6e3a4cc04af266a07	1600448662000000	1601053462000000	1663520662000000	1695056662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a46a16dd6b16fe1347775e0b041fd39cccc360e4bfe998ec9818b98876fbd5a97e5a11e3c4fda0d8af421a26d184ac7301bcc2a8d337e832bf87e2a5f3ad6f6	\\x00800003a6784f8d8224400efc1e18cb45149da281aad96e8b25a9ae9865387014df06c0f3fcb2bee536822fcac138316702685db2a63c5e6ef62b28f5e24fee937a30fab9a8b9383c78707a6d23933744702261e9879038a07f7b0f81e2bb6bc1d30a808097a9c50ae76290e4606a981a684b27141dbe7c8cb110ce6eaffb8b223c4ad7010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x76d7bf87e190a076c6d15eb71849a37c200d420c1404d3a348004bafba4ea8611f7f8b4c365747f784ee93a6ee4449ba49c56e883fdb11fa16f901b176153c0f	1599844162000000	1600448962000000	1662916162000000	1694452162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c3b5a1e598ff6d312d3515d1eb9f47b83e0e144f22477d6f7743cdb817126c1b4a7aa7f4a0a77d191a1eac217d07efb6c40c05e3956802c5c1ffb119b90528d	\\x00800003a667f336fc859c4ec8508ba54f7a0d177fccad8031d09fd8af20ec4693dc8e6eb29e7d0cccf4c0535424abe44e767b09c4fb846cdc385fc2e8068191ba61ae83d4458cdb5e959a5cb928185a1a74707a6d7e70ae34e97f2bbe4d3247379281c15d28351eb9332480110f5cefbc90316a36a5fc11000517ccd2f79cbd0371dce3010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x9166715e3a7e6c610dfc3f8b130d72a1451682742dbdfc6c5302dd59ed3c72313f529a1b4dbb265c25c657f1a0ee2c3e0f7eddff15054b6f6df10594ecf6e00c	1601053162000000	1601657962000000	1664125162000000	1695661162000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0846c00fbfd3489a3393cf435375bb836e0e6ec6b1d3759743eb134a735f8a4e43c9eb6abc62ae221cba1ae3833729d2246e9fccbf57cc786e5b5be0dcc07d8f	\\x00800003c97201235acc530d8c96587143ca58c937422c235cc660a093a6900160ea0cd5b83daa0dec3ff2b986367f67818484aceb3de976a8983e2c9363a98ef82359e9cffc5206a58f2c962a8899504ffc96e87eae675f3db6624d1860caa348f3be8d47d5e27a26a8371f8cc184c3521735743f6a163b33eb7748b38052ba1865a0fd010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xc5df89c03b507ce36fa063b5a98431d96b653400d86f4bbd6990623fedd58335c77f606ed0b09f9dc9990b6d561e0706848d89f1bd663c5587d6959811cbb700	1599239662000000	1599844462000000	1662311662000000	1693847662000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff092c594bd0d9f73a4f8c6ca6b70f2a6ed62f4e3af63f5b8cefa9a8f42678f989e52e225e5f51c2384761f653e69eb3cee8d2e99412b1c0896c3a5363032ff6	\\x00800003b93415a6d11f0540c4a1366d0062b05d60ec9c8815ce3387a4695d147afca40cba6e685d23da6a69fdaa17de0059077436eec974a49bbb1f5ce56c9c1cf40d32166de035ad9185f98a02a5ae9e58cdffbf97ab665e18461abd69336b32af2084bc750848640a54ea51c6d598c2743b85a74657e3d470c683cb467a71df29c53b010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x45d33ff20abe7d7b1460d2d9cbf34788fef973a693e086dd64486c07efb6c93e3c15f5456fa7d5a7aef8548e9b249868fd3e82f611e6e2885bc80b505f69ca0e	1598635162000000	1599239962000000	1661707162000000	1693243162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x365e18afa0ec12dc197537d77650032a1252ed4cd547a77d7882c76e660bc6f1236dd412a2140559c737b13dc7d4ce4d524dd62d2126086b755b8e81f9532ecf	\\x00800003e97051d9877d6071a105c256228be871b4a3f1160b74f5bcce86824a51bb2441eaa8b2ef480c5280addcf93a2f6a7f01704994e3caded8dd8d3b45b663b4d4484bde12cbb3df03cc51e0f59b05824cca2bdff2d751cf43544db264f599662fd28a31bb9441b908aef63ded5e090517dfef2827a8a892158a5a93391ce4fc5977010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xd4f5e9b7c3d2145e7b0df93bb721a7b06a31f0dcd802108c3219f33c02cbf105b411ed8027d345bcc3f3c1a86d4485a6d9eb3ff223dab3f3707d46c780af4005	1600448662000000	1601053462000000	1663520662000000	1695056662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x71a17aede4941db169931d55e1b31cf27f00f28e892518b76e0721b4717b9ca4132f54cf5b1bae8b8b7bbfe2b034fbd0becc2cd62b82f5b0d968d9af348bac1d	\\x00800003bd1ee71e47d24932acdaff80db3efd938334ab4231a5dccc95b4020e5ed7e1fa06d9a93a2ad775053dba3dbbda72d3dd17bc55677dbfcf969e8f9fcbc53519787f0d37d9c744c09892bf5107c6b6c150f42b5d9e10d03bd8cb45b0fe023c742cecf271074dba9a3fcb8c58fad6609aac40881ec9b628fe57fb21dc47bf72990f010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x2d03701036f1528c33f0c5e2df510c8ae1fbd408930b9bfbecec53839c4d6f142eb42b69593f760836de21a5a1a331e816bdf44cd49461bcd26621796d73df05	1599844162000000	1600448962000000	1662916162000000	1694452162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x013110058a2824e43133164cf837a67ac964ddb8336c6b77dda7551d02f3ef867e7ca105615e725d5c2921b913a241ead98a4f51c9166325851e4dfdf2718842	\\x00800003d2fe646a70fc0cb98e680f67dbe62c27ffdb4b7d0c82a74a0abdc4b591572108885917c7c0b501ba34b4db9f46e2a92569e03e7295bb903fb4eaae59141bbdeded85ec92aca3741d4bbad26e59a68c59aa77c15c6cf3a3785e657d8159e9d782c261cc77cc753af374ae0307e7b5dcfb5f13bc4242234b936c86e78abc1330d3010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xc2367847da8da3f24b5b34a0b1cd66c53aeaea650354c65e8718c575a422a5885f6f139a54b0a7410f2a032a89e308ed70681bfe0e5e26c4726517c3e82e000a	1601053162000000	1601657962000000	1664125162000000	1695661162000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfc22c52ad9e316063d6d8d0b0601c24af791f71f044eb42cff7e5d84b45d4c21ebbe42abc0199e09ff6df04a1e65a638e161b04bd5fe23215060c63f62115fd8	\\x00800003b8d6d3d073610018405a85b4deb06bdc9dd4f3b96787396af55d4fb1289fbb9deaafe90018923f7fa2f46c85d02d59f8d30eafa1e3ea941533da948266f34199a7bfb101744e90b561031e978ae8aa53c067b7ed581a5fe7ed9fbcbf10608926d50e0fe2dead1615cdd118553705b944899b28d2da114573ef535f0f262d3329010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x607a94068279d50b05062d4285df894c8eb2c37240da76901afca0b4802c4ca6231762820bdab486f5f6aa9199d995d471c0c52feaa3b1b58d208b9c5621a30f	1599239662000000	1599844462000000	1662311662000000	1693847662000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3485796025c9280ff8fc063da1fc342e4ba405320ecfe7d7d31fa2dd320aab7f6559768da4c5d7e2d6e8bd3ee1d70f1f9c199077c40947f5850dfd46e8a273d9	\\x00800003b62d0cdee0b47a80c4a7418bec5203eb5996a7982f9e5e8698f76ddd2e626399faa21c081b494720215bb7adc95192d86a534922757945ebb8b8d9a5f7969d63fa6531bac3038fb33c110a27041431fb870a8bb1a1e0aa60b2abf6756fcdefaf2cd37350b600a46fdf76f01a29e0aea09df6fee36c0030b69a6f9a2ecfbb60c5010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xfe4f9b350533f5ac0f8e531025b3489fc419b2190f3d6a15e6013e6057a752322ce0f36d2253e831fb75fbc04a04240330111b5085fb3aad9249e3b16792e700	1598635162000000	1599239962000000	1661707162000000	1693243162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e5c98fbb4fca71cb6d83a466839251da556ce6e679c645fd2644dbd2ecfaa69a15bb2db101abea28bd64dd696e677c9f36b11f9952a94c19a12ab75b15601b5	\\x00800003f25299e8ec43ecfb6e6fcd1008afe06531493b09e650e8409c5deb6163f23527f6ac325588d72dfea3168329159e4c63e089207e4326f5370232077963c2ceeec9f2eca6a244b073da4bd6f42c15f55e9ef4bf5c6d1a324e5f1761c8e8197d1c0f316fab2d2f0db3e4a8f250879a5a57cbfdb953ac25e37205fb8c7769c1e5df010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x3bf4197db5b62da3a2c49fd225339c77879d478bc8f1909e2d2d604a5e63b5a4f8fbfec10c686fdb3e76202f0d5d19cfa8cead6a748b02c9bc26dffccd167400	1600448662000000	1601053462000000	1663520662000000	1695056662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5d587ff61bea017ee531ef57161b0ab9074b116882304a3b6182867a1c912899f047a9295cd38705d938034cc3e1ec43bf115c836ba87280a5710e3b1891f207	\\x00800003b6ca66f0cc585bd0ba41d6c121294e3683eb2de56a53e953dae5eaf6cccebb6075820031285bcbfed7993feb81f71f947a35f23579519cd57e3c15b791d37454813bef865cc7519d466a1bc94a10897b80d7483bfb6d237e9927fcdf7daee236dcb8b902f55ac196b7b342ed98f63f3a9d2da13a63aa395c33b58be9857cb237010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x4c46cae92cb0e556d970ed8fbad1a4ded257fd37cbba6f6a9893101c1aed5afbcd2beb20c795b7ad035db70cb88c7b816c288b6367869b32d337ba30c9b4840b	1599844162000000	1600448962000000	1662916162000000	1694452162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x19826b59ee4441f05ecb726363c87ce5725a72801ebe9944355ebdbb0b8f70bae0fd8a78428dc697dab3b44fa29bd86cfb862d0b521dfacfff4d4440e185855d	\\x00800003fad806e12358206dcd2e2696c2b19b78b53d73adee4d39a2621b82bb1eaf9c0eba856b65abe45301f3a76921df94298ead34258e193da707088c0ae61d318b4c500f451c71336d2304e25f7d8a65294912d36f53a7535a5ba2d221a710098afbea7fea33182066708980c082b550944126cc24ee06bf3f2c909528ee9f120e5b010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x6b1c89bca6ed47dbe1245590100331ce597279998bd41bd58f421e06c8faaf134efe6ac6780ec967d95ff82b102cf54db2b2391ea76807a9836784ee742ec60c	1601053162000000	1601657962000000	1664125162000000	1695661162000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x768421921b629bc2e89d44c5086f4d08569e864766199c9486d2efabde82102b4d57efecb1bb8c0b9eb3f13f225cc6ee5c638b6e50c8dcffefd93657280088d2	\\x00800003b84da8f80c6deeb9ec780db6949a9a973d7ffbf72433d44aa3b0864452c7b6c123f65e1ea5c8ae45372bdeacd00a60e1ee7a4070814c9003afb4fc6a59f365a6419440f0afc97949c2e2621976ee7be8324032a190214e9d2faa0ea2f213e6e43fdac120d56775e92b3cc5e10f9d40aa31d4d49ff71d07cb88874084cd5d35d5010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xae8520a38dcd95ff3623b60666cf97ffde32503c3b6d25260b86baff7b2a2566d96f6cf08784276513e08296f5848fca5528ea689e6681624e53d043738b0c0f	1599239662000000	1599844462000000	1662311662000000	1693847662000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x542a1d8a0f8d1cfe6b90fdd17077ef337ce1944384a93083137fe72fd8ac8fb37b02f701dc3f0fb3800f7915b05831f8cfbcd786e2ef9c668f309adaaf4456e0	\\x00800003d13fc9ae2904e588e14099bd3eb72cca3b53d51bd59b84c3369af3d9112cd7451ae0e323f60c1951f1ff6490de9d1eaaf6015e8d0f238bb45ef8ba7be4874ebfc463dfd6509d916fcc2beeeb1fba87bb6934c0da9ff19ac3cd4f16b2299df49615d012083bd24836fd6689f22435792128b8db02c11438244724a67a04c39701010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x2e4ceae2609cff9165ac466ac68d90dc8672b6e71bba1f279f49fac1ff13831d7ab49e27280f418d5ff59b4c743249d1c330175fff63e69b972d04ffe411e407	1598635162000000	1599239962000000	1661707162000000	1693243162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x12821a2e7f66a445f9bb8b640e0dcbfbda7f276ee232ba66fd91552fa5db04cac3cabe1664d24a0518a19e742801a1071be57b3bc46ac3afcc16ad19ed6d7147	\\x00800003bfc2a34290afaa66b460865396e51afeccfc93bc128cf3418e9fcccceb4a7ccc47519af6af7f8d9d31df5ccfece3e7bf40fa9346489cfbf91820765fb19f04086e7e37aa0f4147d5fa824674a4a4d40d382e89911f0aa7ed1dab287ed877a2633f9883b572b9e84db6ec78494259c59a39fd19bd482a47d061f082a3f8b967e9010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xbf20befc326d95bbb5226bb3a099e158b66d596c42522fd9261887a7b81ba0fc08cefa4ea315f1bdeec829fc0f25fda1d5dd81a0b991d8859551be9c33ff6f00	1600448662000000	1601053462000000	1663520662000000	1695056662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd9279267ae071036658c185fc3df47cca9648503eed9c51bdf294e28d94aaccaca2beec4acc44aafeda329d7341d4f491d1a888b7a5be9eef07a7dc05d33a135	\\x00800003bb62a167a9e4bdb61e422bc62d7da14b4aa20fbf4c60be6c455b81f2fa4240b1b82cec34ad84db19381fa4fead868b5970908a67b30546f78d181ed10141560454c277576eb12fcd400d781553a91c91e7111082669bc4d103e0fc6af1c2441bf2c54ea1160ce3241d631aae90423f4b2cf472f68387fc0be82792c3f378eb3f010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xa3b61cf7cd693c17f972e49bd96c21a5222f47c00eaf37909c66ad411b6984a275118fcb49060ba42216dfd33ee197376b7c835c575c45b7a45749d2a9f68209	1599844162000000	1600448962000000	1662916162000000	1694452162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x926df29efc673702405258732387a58b720660b30ba8398476819eabbc15d316aa84bffec50bb755ae9a47d908e6e03471ce7760a2516c867a00a1f80fe8f597	\\x00800003b2e7af99b7e91f73a51f9fd91080d482e9a4d69faa05a9c90021945b703bbab45803b3d3343f3026b54777ce69adbd77aaf9762f78738c7ac60fa8a329343d9944fe856802f9a64a09199f847316960991f134db6c7688236524b178839eef7e87829ac49d1e387f22e0952463f44ec7f5a0bc33113baa1501d043069192fb2f010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x553ae64b8c5c2f7988cf208d7a7b947eb044f83a90f0ce9b648e04199a3b39117318e7852d4080c39a868796fa0c821283ea9046e7eb0cf04bd43e7f40bba201	1601053162000000	1601657962000000	1664125162000000	1695661162000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0102a488ba3a406637a8e848a62a5b41c3543957003c5df7400e8e4f38bcee9baeb1703d8ca9440d0bf98640bcd1a85d231b4c66821b7054ee4858500cc0be00	\\x00800003cee0408118855ade51da6ca671df7c512245e34e7852b6ae0a766de51d034d5caa2b5fdd98d8e98bb22737b371946b86a0cafbdf76d1b4dd03f409612cd10ed1d21f75a8afcce58a3a11289dc9e2d53efcc63df0250a7a6fddaa10d8beacbc3e40caed5a0fcd70167f8cc6c54f3a959e7ad2168afedbf73fd296d4dd3e46b4cb010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x9c6459b3a3c5da1948c1f5f8bf14eb6be12fd361f0c158df591d6ce959677ffc4a3cafe5d31fbaa5348863be88c24301e5974cec177906da22653ffe6448cd09	1599239662000000	1599844462000000	1662311662000000	1693847662000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x00800003c0acfad401fc110f93d6480fc05e704b201e3b1a098914310ab5c546d9091e1a94fd1ca0d3c3bcd8ddd735f0b4af9dc5c47b8359c22b49fcadfa5c856fb8f34bb0d6527d193ec518052db35df3e57d4bf9777692fd55ec64c669ad0506e1a60e9420581c582403f728f9f71c7b444dc909500f4170bb95718796f25d8b1c2925010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x952c2e85766e3424498ee5c1d133d961148cc137d2c5e0c64b47e91da2d31143e18d443dc0a0175ea32a0b86b5dc7e3b9b06bb822f38baf38e7e3d9caa2bf907	1598635162000000	1599239962000000	1661707162000000	1693243162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x82a3a9b89d7a024f894e8a4a5fb9c1c66f9ebc0be9714b2b0279b449c1d8acc84b714484d0cd5750401de94b72eba7b184d887ce9eeb277b95a04f34db679a12	\\x00800003dca2a2760a9811fca5b95d0b74fdbf986b76181627736aff67d8f0757cce8c7a07fff29e0706c144566595ec0749335d53c5950daa327992a6df7f78d0c5bad3c5015831dc55fc7250008a84e05cac74a1633b24901d0dd3e4f78d05ad0d2e2b2e0eb85017b5a780c8ca18470e346092a1552c06800e9acdec9e1b456bf9a747010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x6d3263db7f3f1ccaf3a42a494416a512eda7c1704c1503c27df65cf7ac265d58481284b3424be04d9f38367c3527b16c0cfcdc63dbd47fd945ac32e2c1850a09	1600448662000000	1601053462000000	1663520662000000	1695056662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x66e2df90f6bbc0ed631660b96dfd660001e8f79d0d639aa6c7b9f1d6edcfc64d4b2ed211dd1dff68d60a2f340fc83464c466cdba9bbc18bf0ef0bedc3d4218d6	\\x00800003a53f478738163a5d3a6f7ba78f4977a92d2fc325ea3ad86e10d482a7db6e2f8c78c087aa7e4f94dc13e5e62eb4b3536c5c804c696d1773b8d0be2e8eba6c394ac67624615f18bf0bc1dc58f62051408932ce2ec24b335d40eae414c699ec157aaa2646d9ecf54aaf6ccee482c6c6a1f9d473a0cea7a44c4fd7ee164fdc46a34b010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xb44e70a3871524a683b2d0484eb726fd62561c733b39fb6785fa989d0c319a315e991bf1ab0fc6cc550b99761b1ac435b2ed741eeec205f8fa4a3c8a1eaaa506	1599844162000000	1600448962000000	1662916162000000	1694452162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9f147d39598a36b76cc6717d35a38132cd90f47665ba29328ea82a2dc302dadb03ab2875dc9466d731007b2e9884aaaa2d955b20440079abcb89af9ae4234585	\\x00800003cc9c432e517d634bbf046e036a6235ff248c84d2bfba71721df63bbaf8bc699ef41c43fd01ad309e3b4db24b083ae524d6ed0e1b9f40af20a11ba58c1cd4616794db653d857b63af9c2992d3c491cb4d19abd47e7bfe7157d0627ca7de84b3c923cfd23f0d9a1c9d8056239b8ba8ce522bc531a4e59a6b218f4fd5445b802401010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x77677d5a9c86c93e560c18838d31f1d5a6dbb776c50fd7bb30a4aaea6bf3a5df5a500a958cddb49a6e70209a9c742f390e949a7333b9a2d01751bac372e21203	1601053162000000	1601657962000000	1664125162000000	1695661162000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfd29fe15fa09f7fbac913332aa59929463308d941d8beb0d2f95fd9298167183766886e256bde0bf68306b65b68caf0b489102c13a4e4a9c4b71c2c58d4e427c	\\x00800003efc4cd25ba109d9ee1c25fd915f0cf76709c1653ae65e3bc3e3ef6a3a8d15be8d8d730bfac79a94206f54eaa10103aa1d3f496357524702643577f1394c7618d65791d0cf680f30c6f6969544027d5225ff182e943eb19754067acab503ee67971e82f7c5dbff3725a1a507320b6fe6ffea1089d21d62701a3c2348b8ad0b8dd010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xebb675123a8f56ea23d3c2e9914f421ccb0e41c35a3fd22bfeb802c23f95a4ae8eedae34dfda0a1934ee1af7e35d5125d181e531766f032319801575a30c8a04	1599239662000000	1599844462000000	1662311662000000	1693847662000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x00800003ef7578fea6f2ed2c8ac536f74ad78d5feb493028d814d9b6fb7ea463eb38b5a37a11c0eb522388b050feab13e027b6703eeca59d398d9fcbd89f6c2b2034927492a782e28ad8a12fb0a73ed9a0081c14c37aeaa6451eb834238bcd3880dbbe8a0e3d8eae4bf56efca0f7519b8124396051939aa67b5d84bfd1cd53a56a39e9ad010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x6eb9684f59d127454a1f58c113550a9cbfff39d7a91ae9374464a20fe1effa10ef549dc5bdc5d9b208f89f5ded17a32546f0f5ff668777226270629fa3213f05	1598635162000000	1599239962000000	1661707162000000	1693243162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5bd2f3ec9766ce7bf14ee04be8428c7a3c984f216a45c5b051b4e2056e4cda32f776e7fc48cac4e9d42914b51b8a0ea38ef73725e503a5abaab89914dc011c6	\\x00800003d3287ba9b93b47cbc0057d2f3e22f2f4709763775d2a79c86dc2b5be6de80bb2186fb8a27285235fdd8c265ad29dae300d0ddbdea1449b8e25c971b70ae822353e3ef5d4c73bfc3326d1da15a75873c1f8d600be4c4ac49bdfa9217936696293b2619a26353265e510cb8f12c5ae8db3e440f4939986e3c88281de21336fd05f010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x341e8e44083ef7a28b7d2e38a0667428e2d27637bc74f23caca402b5b845019f2290a45530a81ed7a531c371604ae437e5dba78d220ebdc599885c09353fe40d	1600448662000000	1601053462000000	1663520662000000	1695056662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe813084b08942107c1036804b0a66f0064fe72c974a9774fd01aa81c0d4e3a2dc0c670b793ba462bb74c7a33d824687128b1ce0812f9b0d9e06371487c7ecda4	\\x00800003a38a8a81a2b51c832d9a884bb9640d42d73b2561ca4c66d82e0b3d356579b050b954dfef0ab284a1eb103143cfe41a4a9818734ae09aefd08954cd1707451ba2d88c97019726b864f03410d3ada62752a130fadcc7b7f91b8d91158f2348b1af3b61209a8c0a2806511296ec20dc0b5a8f070db4a5d4105fe962f743011f68cd010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x79725ceb2e65026d1de00e5adac10f634f64ed1ecec205553965abf53945b04e5cc8aa72f595be8566662daaac9fdc618af74e2ce8bb4ce8814a578fcfcfc00e	1599844162000000	1600448962000000	1662916162000000	1694452162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x987338831ee3e41817447e6e2692de08b442af98e76df7b9baa7c96d1ef3491f08ba129ea8a69ad2bef03068e37bbb89fa6c30cb56b8ad581123411dfa62d918	\\x00800003bca682915c068d8bd0c1f4d917c31cec40f7ad0ac38bbd66511fc7a66c0e8d843af969efc3a5a692bea813605b1635e9d1c8ac90d7882f81355d36d12fcd693809b99284dccf06c26c6043161c0fb4fe82b1b0a27acd08cf42fdb3d3cca752865917a30fe40a0ad7ffda50b2835bcb1c5f462c54a091e952edfad68d2b7e620b010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x8568b61824d7cae19ed06c983d382b8ded470c1b2b611e653f23d1b5e0f4e06f869965ebe5ba1ec1d6ad6ca486d60035f6825414af322cbc13fd8276f26cce00	1601053162000000	1601657962000000	1664125162000000	1695661162000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6caf2f7d82437982eb34695250c8cca444a3e32105ad03803bee173f906fbc27ba73d206ed6bcf3210e72d2809408151525a64e46f19b64d7e843526035b2b2a	\\x00800003b1ec7bb39aade981bb6fe468d4665efa31bccbbeaae1b4d5675889474397f4b15437992e69eef55229ee83c7d1be3266c6afae3d72a7bcdb4e57e02512d100c3788bc8ec78e433b8ccf21b083832041cd17606450bff2740fe8c773ac7757b6fc7d7731269b64420547a45306957e68badb428c989670849c4c45f115d89d345010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x5cbb26bc5dce2e7f4014b48ca763680e3d4f495f3861b5ff73debd2066c298162d4d0a7e2a981183eca1f50c70b96562da817d28da0a29bfd3e19d2c5da4990a	1599239662000000	1599844462000000	1662311662000000	1693847662000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x70ec0408bdb4fc9dfddb764988fc519361870d8e1b257110b4ed1669149428fcc2cad887df8ad9926266deec3137d5f565374b7881b83bd80070a892d1ac8845	\\x00800003c001c2f4c376729720c65255fc69e8c2123dcc125eff7ba859d6da77b319da11f0b978bbf34a4ae3d8892ce6ff07f3e06fa84e956a9e65182809da916295cd2b4e968ce8225b18f2e9439314f09dd382e73de44f48b215adff19f660c3176923134317839da3b7619b42f4e5d365a38e3f5315d82495bba30f4e485137b28a15010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x93810081c4ae3a92109b217ef15bb316617554a998ba4f749fbbf7b7e4db47e2ead16be5f9f9cdef60e93583bf8fe0e212cdcc1c31c15309614428616bd5bd0f	1598635162000000	1599239962000000	1661707162000000	1693243162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa7f0169e04b4c4474e32f290095d2ea90b8a7ecd2fe7e4fd2e5dcad5c502d81fe87d73d3c45ec42690860c6a642ec11cf7acf8d6bcfd8e5cc1abd3139c6bf076	\\x00800003d4a41754c47c7b46bd6e5c558ac8e620c8dd4cf14f5b520fd8920eb23a2eb04a21f93eef9c86612a1c4529943954153e1471b0b8685b9d0d069ec61eecac3e7b81fb4a6cb2938d6c2161d2bacbbc725d940d8a5db2103f575d62062ddf11ebe6e6b20088cabb731bb381708a4fda1d17ca586a2beaa39408652e197e587b1843010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xabbd7406554e641bc7a0185d9f277124511266272b7f8736a7214987a64c9f0766f3d105306840a8997166957a105bacc7c71b4f9d96d1f084b9b025f400dc0d	1600448662000000	1601053462000000	1663520662000000	1695056662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5bae646ec391d8a580dd067bed7341c449c4cfda5c44e996c0143f3d1a8be9f1f5eaf9199e1dcf026da0631cfc8c091f7a5f39126ae331c506e806e9ae454252	\\x00800003c845236bd4b112bedb828985a4fc3f76a51496e0f1a7ee993389b4e552d5927b918012a44345b08cd1e62989f73443dfbdc450db0478a9309c5281b0b74efab5e4734e77658efdc00929505ed37067d02c911368aef481daed0ebe71c84e6f542b85e349f0caaf1b2e593f2bee18da4042b7072af5b4774afc5a2b98a164e57f010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xb30ff92fa106a29f413f748e6a71094f73c9acc7ef6c4b4546f97b19b908efee7e8c268ac2c6b668c1f1a770d426bceae6cf106e3bd004487a50c07ed42a2806	1599844162000000	1600448962000000	1662916162000000	1694452162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd089c5dac8d238dc2949b7a9fdba55d9e407307a7da04d447c674a80f52f83820e47b6c657a4bba452e9db8e1f6526b4d3e3b21a6712144487dda63929e06c52	\\x00800003b7ca40745a0ee99737552a17199c835f11cd5a9fc7171525cfa70cecb90684adad89441a662d57c8929a1b88ebe54d5639eba6cad0eca3a39af749791f36027f34b32d2fc571594fe190dc707c33d181c7d3ff93e5e5c2ff56d9f38d14b1b696b0b905acc99b09d8e83961d5f4ccb03ce5e3e487efb529c8b8244c9cd155b333010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x97d8f6d6380c2a40e0ad9eb289ab35d9e39ea909efeafcb48e82acfbd0513f2a740bca2b989070db286efa6b15d9c517a285e5c2b15a4c5d5b4b5dbe025f330a	1601053162000000	1601657962000000	1664125162000000	1695661162000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf1110020b6f14636995d583a206f8844efd5f23630f29d8ac23cd00bc5b78e7397e0a14fecb4b0d75f4aad4410c8c85f58de865ac811146c3e526fef8f95273b	\\x00800003e3877774cfbe8e4dca4bbf4759018db04fd8ded4711ba6ed9e002f29c1684b50ef0b51e6dcfa17791f34be09e9912b84d168044f2c2cafd19ef1fb8cce549069aa42b5121fafc6e77a225addd4cf19f84f0f2db25405c48a7e680cac2ce9f8a3a037f1e70a19a83462891da56e6ba2078db8cc39483d95d7fbd8cde8a6d40d4f010001	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x528ac4330243ceecce09d51474ef341834a8d0747b36dcf9b64d5915d7fd102ae8d704b23e7c3a79037b7550489eea06c21ed1d237b34121ab6651d8af52480e	1599239662000000	1599844462000000	1662311662000000	1693847662000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	1	\\x91039b684c689ee45c83ecc539bbad9118d911bb3b447a4202dbfb40bfaa3269d9d7ab3b4ddbd5090c550a40ab008e387cb16d8969856236be5f01cd0653695d	\\x867d31b47b98c63081dfadfe085cae786efbee07f1d54752c7104a4536a4e20e61494a06ddf39f8b2c074e1295fb626972e5e93cf3783967066a222bbe87ed6f	1598635172000000	1598636071000000	3	98000000	\\x6369a61219d29362f64781b3bc1a8483c9b88975a093d98fbda6757adf22e06f	\\xd5a926d1816d0b3cf1e7ac84cbacd9c845ebd4989ed26ebcc2c810fface80ed6	\\x16a091809cfcf2b6af60d06908ac2dbc6b93c586671b0c79eb448d13a36e4ee5e7ce5b339dcb1b2d6999bd05cebf0f47d7725b11efb762c908c23aa38fb5da0b	\\x4b79f521d8ce5a20453b2d58e7149fa2899ad14e7f9af951606376377be8ddf3	\\xf90cb2bb0100000020bfff4ae97f0000f31d75531a560000c90d0030e97f00004a0d0030e97f0000300d0030e97f0000340d0030e97f0000600b0030e97f0000
\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	2	\\x5c925a7e6671c9f6fdb8723ebbb425c6d743dd73e9ac461928e53302ba8187e398de2cc17401160dc0d4d8d91a0648ef534435a8647e703df7a2718e47a254ac	\\x867d31b47b98c63081dfadfe085cae786efbee07f1d54752c7104a4536a4e20e61494a06ddf39f8b2c074e1295fb626972e5e93cf3783967066a222bbe87ed6f	1598635178000000	1598636077000000	6	99000000	\\x717a8922cb5539cfcf990345b5c0195808a63c0d04c388c4946f72d605b8f4dc	\\xd5a926d1816d0b3cf1e7ac84cbacd9c845ebd4989ed26ebcc2c810fface80ed6	\\xcf17ad5bff1b4e8f2ebd7b3f2d9f42204563b7d2de3212d0849e1930345babcfea65d926662e4526372ad196ad6bebc42bf4b102fbff425bdeb99c4dd4d9b503	\\x4b79f521d8ce5a20453b2d58e7149fa2899ad14e7f9af951606376377be8ddf3	\\xf90cb2bb01000000209fffa9e97f0000f31d75531a560000c90d0080e97f00004a0d0080e97f0000300d0080e97f0000340d0080e97f0000600b0080e97f0000
\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	3	\\x68f42757a6505901b6a6216743a7ec3d1f4ecada4792aa1a30452fd9dab94fcadba7001386dd0cee10fc161e4bd870b07bd8cae0ba47d78cb43efa79894e7be5	\\x867d31b47b98c63081dfadfe085cae786efbee07f1d54752c7104a4536a4e20e61494a06ddf39f8b2c074e1295fb626972e5e93cf3783967066a222bbe87ed6f	1598635179000000	1598636079000000	2	99000000	\\x00412df4e7476b0896a8ec6627162a02b78198b7a86d19a394c7c96612e67ac8	\\xd5a926d1816d0b3cf1e7ac84cbacd9c845ebd4989ed26ebcc2c810fface80ed6	\\xa48e5eae3f16d9b659352102d63e20be013c96abad5f156b47818e41a0bb4998ac3a535c52e5a3aa6bb03a6457f660a0233e71e174ca9d395b80896ecf4bd206	\\x4b79f521d8ce5a20453b2d58e7149fa2899ad14e7f9af951606376377be8ddf3	\\xf90cb2bb01000000209fffa9e97f0000f31d75531a56000069430180e97f0000ea420180e97f0000d0420180e97f0000d4420180e97f000030410180e97f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x6369a61219d29362f64781b3bc1a8483c9b88975a093d98fbda6757adf22e06f	4	0	1598635171000000	1598635172000000	1598636071000000	1598636071000000	\\xd5a926d1816d0b3cf1e7ac84cbacd9c845ebd4989ed26ebcc2c810fface80ed6	\\x91039b684c689ee45c83ecc539bbad9118d911bb3b447a4202dbfb40bfaa3269d9d7ab3b4ddbd5090c550a40ab008e387cb16d8969856236be5f01cd0653695d	\\x867d31b47b98c63081dfadfe085cae786efbee07f1d54752c7104a4536a4e20e61494a06ddf39f8b2c074e1295fb626972e5e93cf3783967066a222bbe87ed6f	\\xb06c475ec561d336130b12b8c83daf623c6e84344076f1e99bd666666722dc0481e6a8298446147ef149ca17d1fac3d3063ded7ae88e7c1be7f5e949e2aae708	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"R0YYARVKJR337V33SVYG8B233FY2TEWC8H1KE4JXB66DE6QRA4RMZREEG4G5W0RT6AT4EZMNP98P6F0AQY62CKAEPSG2E3BWBEVTJY0"}	f	f
2	\\x717a8922cb5539cfcf990345b5c0195808a63c0d04c388c4946f72d605b8f4dc	7	0	1598635177000000	1598635178000000	1598636077000000	1598636077000000	\\xd5a926d1816d0b3cf1e7ac84cbacd9c845ebd4989ed26ebcc2c810fface80ed6	\\x5c925a7e6671c9f6fdb8723ebbb425c6d743dd73e9ac461928e53302ba8187e398de2cc17401160dc0d4d8d91a0648ef534435a8647e703df7a2718e47a254ac	\\x867d31b47b98c63081dfadfe085cae786efbee07f1d54752c7104a4536a4e20e61494a06ddf39f8b2c074e1295fb626972e5e93cf3783967066a222bbe87ed6f	\\x414c8affd6928fc9bee4e96892cd8f5acf61a12216430cda70fc83bfc76b4430ca736828fdd3d501cc6c43697f3dc17c7f28251e42e99690fed308d28291e207	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"R0YYARVKJR337V33SVYG8B233FY2TEWC8H1KE4JXB66DE6QRA4RMZREEG4G5W0RT6AT4EZMNP98P6F0AQY62CKAEPSG2E3BWBEVTJY0"}	f	f
3	\\x00412df4e7476b0896a8ec6627162a02b78198b7a86d19a394c7c96612e67ac8	3	0	1598635179000000	1598635179000000	1598636079000000	1598636079000000	\\xd5a926d1816d0b3cf1e7ac84cbacd9c845ebd4989ed26ebcc2c810fface80ed6	\\x68f42757a6505901b6a6216743a7ec3d1f4ecada4792aa1a30452fd9dab94fcadba7001386dd0cee10fc161e4bd870b07bd8cae0ba47d78cb43efa79894e7be5	\\x867d31b47b98c63081dfadfe085cae786efbee07f1d54752c7104a4536a4e20e61494a06ddf39f8b2c074e1295fb626972e5e93cf3783967066a222bbe87ed6f	\\x3cc6350fe4a982a84c43ffdde4e82b4419e4e99b64574603852d42e0b310c4e988510edca26cefec282d5ab2727ba45dbc119c32b050ed47258d8c18f0452404	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"R0YYARVKJR337V33SVYG8B233FY2TEWC8H1KE4JXB66DE6QRA4RMZREEG4G5W0RT6AT4EZMNP98P6F0AQY62CKAEPSG2E3BWBEVTJY0"}	f	f
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
1	contenttypes	0001_initial	2020-08-28 19:19:26.401144+02
2	auth	0001_initial	2020-08-28 19:19:26.425386+02
3	app	0001_initial	2020-08-28 19:19:26.483115+02
4	contenttypes	0002_remove_content_type_name	2020-08-28 19:19:26.504767+02
5	auth	0002_alter_permission_name_max_length	2020-08-28 19:19:26.511579+02
6	auth	0003_alter_user_email_max_length	2020-08-28 19:19:26.518194+02
7	auth	0004_alter_user_username_opts	2020-08-28 19:19:26.525456+02
8	auth	0005_alter_user_last_login_null	2020-08-28 19:19:26.532237+02
9	auth	0006_require_contenttypes_0002	2020-08-28 19:19:26.533822+02
10	auth	0007_alter_validators_add_error_messages	2020-08-28 19:19:26.540743+02
11	auth	0008_alter_user_username_max_length	2020-08-28 19:19:26.552537+02
12	auth	0009_alter_user_last_name_max_length	2020-08-28 19:19:26.558903+02
13	auth	0010_alter_group_name_max_length	2020-08-28 19:19:26.571567+02
14	auth	0011_update_proxy_permissions	2020-08-28 19:19:26.578265+02
15	auth	0012_alter_user_first_name_max_length	2020-08-28 19:19:26.585213+02
16	sessions	0001_initial	2020-08-28 19:19:26.590106+02
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\x6369a61219d29362f64781b3bc1a8483c9b88975a093d98fbda6757adf22e06f	\\x70ec0408bdb4fc9dfddb764988fc519361870d8e1b257110b4ed1669149428fcc2cad887df8ad9926266deec3137d5f565374b7881b83bd80070a892d1ac8845	\\x1eb532fab3248ce95b8d5fb67c75e065aeac0fce2166f8460574df762522e2cb5f34023a11179000f7635854471c87548264221479b3288184bfac7272249cd0785f2d051782483ab7b7f3b8e51a3d51f5712c16abcc5b0fb0745f2469ddc87a012e586bf12692fb223fa4c1c76748bd146c77e01cdbbc807094a61102cb8b3f
2	\\x717a8922cb5539cfcf990345b5c0195808a63c0d04c388c4946f72d605b8f4dc	\\x7a03a3ae909f1954488bf99c2c524ef40810ef2baa989a5150de161375a73d1d6a76752732d538de535ceb059d946e6e5565d55951bc31e11d47d51c0a81bcf0	\\x587613f0a8617137bbc0402f4597e17b4e4828442697aeca5554ef08ff5e94c5d78f0cd909db3ab5e9476bb3b6b2abdc6b9c5bda12ebd52fbba8395aa0a846085c0180a1b0ec7a47e6d11c683bfcf29567c42a5c45d210172dc6298d52278618b7f4d9ffe28f042fdf0e275b23714e3797ef94b2c63276ab6f596435cfada1ec
3	\\x00412df4e7476b0896a8ec6627162a02b78198b7a86d19a394c7c96612e67ac8	\\x42d0f6a215c182209d58c0d04efae56fdf3a1de408873375550fa84fc5f80622c0a1a01b0f7cc64663001615d304ba884d95511dbab07ec3501f06140205d920	\\x6b5f9272b4fb91d2a5adf49af1034f2379da92ccbdc1272cdb9db4f9ad887e083c66570eed45481f206132732a0e49a9be9849d5fc8efa5288222c54f0db6cbc516a008a8b50ccb6ed1b46873cfc14f722c27ebbe212706e871a03ab6b84a6eaa3349ce88cb9ca9f60339b03790f941cbffcd83e4582d11e2b8cc8bc3f642640
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x867d31b47b98c63081dfadfe085cae786efbee07f1d54752c7104a4536a4e20e61494a06ddf39f8b2c074e1295fb626972e5e93cf3783967066a222bbe87ed6f	\\xc03de56373960633ec63cefd042c431bfc2d3b8c444337125d598cd71af851314fe1ce81205e031a32b4477e95b251633c0abf8c264d4eb660270d7c5bb7a978	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.241-00VP84VP3ES0J	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313539383633363037313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313539383633363037313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224753594b334433564b3333333130455a4e515a304751354546315146515647375937414d454d50373231353441444e3457383736324a41413056455a373757423547334d57344d4e5a4448364a5751355834594636593153435733364d38484251543359545652222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3234312d3030565038345650334553304a222c2274696d657374616d70223a7b22745f6d73223a313539383633353137313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313539383633383737313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225053575442484d42453648344b394a37335854475a57484257345334485a535138534d4454465952454151575833315a36333030227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2254504d4a444d4331444d354b535746374e4a32435142365353313259514e34524b56393658463632533038465a42373831564230222c226e6f6e6365223a22585a4a364e3132393052333032484e484857303948584452323538485a333251515a4e314331485746413832444a523642383230227d	\\x91039b684c689ee45c83ecc539bbad9118d911bb3b447a4202dbfb40bfaa3269d9d7ab3b4ddbd5090c550a40ab008e387cb16d8969856236be5f01cd0653695d	1598635171000000	1598638771000000	1598636071000000	t	f	taler://fulfillment-success/thx	
2	1	2020.241-00E19B9W1P55C	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313539383633363037373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313539383633363037373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224753594b334433564b3333333130455a4e515a304751354546315146515647375937414d454d50373231353441444e3457383736324a41413056455a373757423547334d57344d4e5a4448364a5751355834594636593153435733364d38484251543359545652222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3234312d30304531394239573150353543222c2274696d657374616d70223a7b22745f6d73223a313539383633353137373030307d2c227061795f646561646c696e65223a7b22745f6d73223a313539383633383737373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225053575442484d42453648344b394a37335854475a57484257345334485a535138534d4454465952454151575833315a36333030227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2254504d4a444d4331444d354b535746374e4a32435142365353313259514e34524b56393658463632533038465a42373831564230222c226e6f6e6365223a22584330453848423232523944324d44455a4a39414644324233584134594d515a4545563050425854454a4e5a5636473656514147227d	\\x5c925a7e6671c9f6fdb8723ebbb425c6d743dd73e9ac461928e53302ba8187e398de2cc17401160dc0d4d8d91a0648ef534435a8647e703df7a2718e47a254ac	1598635177000000	1598638777000000	1598636077000000	t	f	taler://fulfillment-success/thx	
3	1	2020.241-03KE6YX6YBRKT	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313539383633363037393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313539383633363037393030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224753594b334433564b3333333130455a4e515a304751354546315146515647375937414d454d50373231353441444e3457383736324a41413056455a373757423547334d57344d4e5a4448364a5751355834594636593153435733364d38484251543359545652222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3234312d30334b45365958365942524b54222c2274696d657374616d70223a7b22745f6d73223a313539383633353137393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313539383633383737393030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225053575442484d42453648344b394a37335854475a57484257345334485a535138534d4454465952454151575833315a36333030227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2254504d4a444d4331444d354b535746374e4a32435142365353313259514e34524b56393658463632533038465a42373831564230222c226e6f6e6365223a22565954305444504e5043504b4742324b4a503253364d5a5857314242544b5248344b3737375a4842433450434450435139543030227d	\\x68f42757a6505901b6a6216743a7ec3d1f4ecada4792aa1a30452fd9dab94fcadba7001386dd0cee10fc161e4bd870b07bd8cae0ba47d78cb43efa79894e7be5	1598635179000000	1598638779000000	1598636079000000	t	f	taler://fulfillment-success/thx	
\.


--
-- Data for Name: merchant_deposit_to_transfer; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposit_to_transfer (deposit_serial, coin_contribution_value_val, coin_contribution_value_frac, credit_serial, execution_time, signkey_serial, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (deposit_serial, order_serial, deposit_timestamp, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_serial, exchange_sig, account_serial) FROM stdin;
1	1	1598635172000000	\\x6369a61219d29362f64781b3bc1a8483c9b88975a093d98fbda6757adf22e06f	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	1	\\x16a091809cfcf2b6af60d06908ac2dbc6b93c586671b0c79eb448d13a36e4ee5e7ce5b339dcb1b2d6999bd05cebf0f47d7725b11efb762c908c23aa38fb5da0b	1
2	2	1598635178000000	\\x717a8922cb5539cfcf990345b5c0195808a63c0d04c388c4946f72d605b8f4dc	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	1	\\xcf17ad5bff1b4e8f2ebd7b3f2d9f42204563b7d2de3212d0849e1930345babcfea65d926662e4526372ad196ad6bebc42bf4b102fbff425bdeb99c4dd4d9b503	1
3	3	1598635179000000	\\x00412df4e7476b0896a8ec6627162a02b78198b7a86d19a394c7c96612e67ac8	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	1	\\xa48e5eae3f16d9b659352102d63e20be013c96abad5f156b47818e41a0bb4998ac3a535c52e5a3aa6bb03a6457f660a0233e71e174ca9d395b80896ecf4bd206	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x4b79f521d8ce5a20453b2d58e7149fa2899ad14e7f9af951606376377be8ddf3	1598635162000000	1601054362000000	1661707162000000	\\xf093443b40ba959acc8e9193c11236540df71e8395dbc3ea2a1838c0b02647748ce779c8ae958d1b80c314bf0bd0f310e4c1f82d983279165e43ad0071e5aa0e
2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\x63c1265191d48c82228a51822d72da7885697226debddcf2d97bfb88758193f6	1601054362000000	1603473562000000	1664126362000000	\\x391dff4479861a45282d38fd9591fc82f7481e22eb4c7ccaff928de7e45dd19b05e61c437d4b36157bc0dc41e9d344464c60cd582455726451eef1d8f8e1e406
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\x1e36bf5230aa604cf51afe920c187d65562fadd3ccb5537fd0253cfc18352335671fd88dcfd16ff03237389f7c7a39cf7769f0ebbd769919720f0e6aa795970d
2	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609455600000000	1640991600000000	0	1000000	0	1000000	\\x0d275aa9e1378f6d5f0b0228d8a175999bd420352993426831c218533306da44bfdb0eaccdaf22dc0b515dc5bc49888256e9f8ab03b1c59f27fad3dfe9090e0b
3	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640991600000000	1672527600000000	0	1000000	0	1000000	\\x74048bcb8806cd20538feb00af3c9da53f78d2e87ebaa024c69d85587d92c24a21055712173298a2d123596e6bc03fdf9849824700084d1f8b27e5b94a12c807
4	\\xb679a5c68b71a249a6471f750ff22be13248ff374668dd3fd872afce8c3f30c0	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1672527600000000	1704063600000000	0	1000000	0	1000000	\\x828c5d2fb5317724c28f86504c657f615a3ec82fd1f913a7a2cacb71c185e5cf81d86718188ab27ad05f8a073716eeef72a3733b108be53525a6352a0e2b840c
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xd5a926d1816d0b3cf1e7ac84cbacd9c845ebd4989ed26ebcc2c810fface80ed6	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
\.


--
-- Data for Name: merchant_inventory; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_inventory (product_serial, merchant_serial, product_id, description, description_i18n, unit, image, taxes, price_val, price_frac, total_stock, total_sold, total_lost, address, next_restock) FROM stdin;
\.


--
-- Data for Name: merchant_inventory_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_inventory_locks (product_serial, lock_uuid, total_locked, expiration) FROM stdin;
\.


--
-- Data for Name: merchant_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_keys (merchant_priv, merchant_serial) FROM stdin;
\\x7c2bda66138a2db951ce61c878803acc2eecd7258cd88b4e67f4920197587ff3	1
\.


--
-- Data for Name: merchant_order_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_order_locks (product_serial, total_locked, order_serial) FROM stdin;
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_serial, merchant_serial, order_id, claim_token, pay_deadline, creation_time, contract_terms) FROM stdin;
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
1	\\x2bcef5a6d6d4b708389219a83b4b69f40bde39c058fdff94e69c24ab979e0c02080850ded3f436124318e7f1b44c4c03f89d07d48be28dbae8e0bb3c4e442e00	1
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1598635178000000	\\x717a8922cb5539cfcf990345b5c0195808a63c0d04c388c4946f72d605b8f4dc	test refund	6	0
\.


--
-- Data for Name: merchant_tip_pickup_signatures; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickup_signatures (pickup_serial, coin_offset, blind_sig) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickups (pickup_serial, tip_serial, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserve_keys (reserve_serial, reserve_priv, exchange_url) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserves (reserve_serial, reserve_pub, merchant_serial, creation_time, expiration, merchant_initial_balance_val, merchant_initial_balance_frac, exchange_initial_balance_val, exchange_initial_balance_frac, tips_committed_val, tips_committed_frac, tips_picked_up_val, tips_picked_up_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tips (tip_serial, reserve_serial, tip_id, justification, next_url, expiration, amount_val, amount_frac, picked_up_val, picked_up_frac, was_picked_up) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_signatures; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfer_signatures (credit_serial, signkey_serial, wire_fee_val, wire_fee_frac, execution_time, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_to_coin; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfer_to_coin (deposit_serial, credit_serial, offset_in_exchange_list, exchange_deposit_value_val, exchange_deposit_value_frac, exchange_deposit_fee_val, exchange_deposit_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (credit_serial, exchange_url, wtid, credit_amount_val, credit_amount_frac, account_serial, verified, confirmed) FROM stdin;
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
1	\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	\\x6369a61219d29362f64781b3bc1a8483c9b88975a093d98fbda6757adf22e06f	\\xbaa3fbdc4abd69b2351a05a5d81968f9c143729987361547792d6150c35c3582bbee65259626af901dbd5e00317700e4aaa824555ef0050af51e65189c790004	4	0	0
2	\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	\\x717a8922cb5539cfcf990345b5c0195808a63c0d04c388c4946f72d605b8f4dc	\\xfc4c93a3dc677524589d7ebe62f1027f7b708fb2d24b66efa01a081473e279f813b7feb083d6fe4292a2d7ee64d67200b2e8993f39bab8b7497dcc7bfa3d7203	3	0	2
3	\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	\\x717a8922cb5539cfcf990345b5c0195808a63c0d04c388c4946f72d605b8f4dc	\\xce75249b98d451ea61b8d2f42b72fc881b157b7075d3d47db16785a7ea12001c67b3b3e9ea3fcaa79f9382c73b4342af9b513da8efbdde8e8bfe1df4bc581605	5	98000000	0
4	\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	\\x00412df4e7476b0896a8ec6627162a02b78198b7a86d19a394c7c96612e67ac8	\\x421d0346b96c5785ac457e2f2fbc4078e0e35abd8e2f9f0cb0e91351dac374701eb5edaeec998d4ecfaae4b912fbf7e5426db3f1dbe4e7edfd3e04d75c923f08	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	0	\\xd086dc689e5202fda75db395bcd724926ed39fb4634c2dc92547abcdb395f403ff7cb6237355901e1395cc0e77c4b5cad75456847ec741f6ceb3ced37817c201	\\xff092c594bd0d9f73a4f8c6ca6b70f2a6ed62f4e3af63f5b8cefa9a8f42678f989e52e225e5f51c2384761f653e69eb3cee8d2e99412b1c0896c3a5363032ff6	\\x0e2a243877cfd092c3c59242c90b8426d80995baa2c512c2181b9f1fe2559244ccaf0c74e606c5a09a7077ff568dbc2d3a1d648b7ec593a13a0c44129aa1275ed4d031e23a7c94a9711917849afa4de383196ac11f3b424328195732bf7d33579f54bd98319e8d43503e8deaf43f661801450dcdc681ab94774e252e073696ed	\\x7f606026f71fae9b8cca5256e4722740de975914110d74263f5ab172577f094df5438f460e6075f6d2e55598fad167416c0bdd8f60422b595817136a8e2a8c8c	\\x6a971d9b9d309d199f4b82bef41317ce7518abe3f757a908dd0d033dad76fc35cf9767625c38ded0b0a48d0433db2d4ced583c57df6023f572bf8b27cac54096dcb17d219a399cff5371b5ba50ebf4ca470ee1915dc17fa36c4ef009524a2fad3789ab2976c111723a688383715aff98c9be15d6fed8122bb47fc27761ea8566
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	1	\\xe02f0d302583244463eca2b6ffa49805a9b254cde400743541887e0cc5d80bb62bf212800e6a0c1b4f2452d12742a3971d7dd3456cc3f7183a4a604cee565f03	\\x542a1d8a0f8d1cfe6b90fdd17077ef337ce1944384a93083137fe72fd8ac8fb37b02f701dc3f0fb3800f7915b05831f8cfbcd786e2ef9c668f309adaaf4456e0	\\xa21afc4fc1e4e8cc00a19a1472a578d45664689c490a5df23612bb685f0d9ac28b33373057139e30a97cdeaee8318c4da0ad5e538a735511f122c71acd2aafbb1864bd103fd36eb388f775f459442d992483aaaa1595e3d6f6e107ad25a193133907328e0b9973dbf46ae81c083d7a108ba600e3ddce44784b17c2c7500643e5	\\xf74098bf81cb5e72f9e22dc705de2c8089d547958c569ed171a2fc0b39eef5cd8c61b6f81ad12111b3b8cc48781a7cdff29e1902ea03fcf9acd0a9a388129f79	\\xba9c39973accbe4663391006ddb55e33eac1e50f7b74e0f675cc5f86e3377817741d21625c0fe90cce6cb1be609e4fee5093dc100c52c0dd22a705d385535fa8f66761af9db4bc497a9408a561acfeea9aaaaa0a3c5e26b77ceb99c961a816aae4f8a1bba30f2db626b0e129fb33dd0747369b0ea4b1bb91f88f52d542eea5e9
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	2	\\x0d01c2e16304c04102df81afd68be58bc38bd0ee20718422ae02e2ad1647d34d9d3bfa306fe009e6b5ebf3719f659c6f68e41b8bf610adbe842a7ebeef72250c	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xa0faf74178f5d8eee4126912dd7d82bffb7d699962123b0cbd26923707b6cfcfdd4997bf6c7cbcd7cbe047874ac38affefcd65b743e2109f25462fb3266a1e1cd74e2a235b5b843f83d703a366203ab330fc502839017140e901186b4ba5d60effc46c7eeaec6acfb8a658b269b6b3628dab4abbfe09725e425d09491acd01d7	\\xf056e79a0c6778ae3e29a1a17b77e6719ea5173c28b6d1fa59175e3817514ac2580fcf77d5bd6a0c89f2e6554bb69b14c8daa1a940ee3c4d0a1d69072ce8d5cd	\\xea797dbca55d02dfbe99599f3acf4620410d2c4c400f8c284f6937a58f2e18fd1876a658085465d0b74f742d558667357782c445431cdb4e2380e2ca4bc4ee928a27662889c435cdfa66d9a8ee3017cc8994bb16dbf73c30f175107d8c1e21b49c114c76732ee8ba4fdab7bfb975dc299fd0e8ab0a745ecae7964defec6a9d5c
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	3	\\xa0d547141b6651885426213a0141f73ae006a3d42b42da3a4922a194f972785165f2bc4033b848a8951c2d4735e189e41b299db610e8214fe84e0171a6b2b506	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x0ef4ef51c24ed26cfd315ffe617a29dccbf1bdc73272d8e825a14c09f0b347b87480d51068af7f8f3d88c1d5a206b1ade083959f425ec9ae22074ba0177c6b84accd9304566ea445699ac16f25ff64af79f1007625126189d6633284d7e71c0502f29edac4a3f581177b5e41eb4b86b70eef86d3f8bd2e23be54d28f3b0b32c8	\\x6b180bba2a437146a6715753d60b785d41a7af9cd8f24a2a1f4b05cdfce47b7dbe7ce8b24aa05557578ae72038479a1df602a883b1dda5645e12c285e8f2a20e	\\x5611804284484ec23cceb2fb18a8ef4d6b0470f35061ebce60e670da86e1cfd76aebbaea0d86959f3d6737dc016b4ea965380a037683401bff9387cff8746bb66d60987d564d6153aa813f105ee4f151169c840fa65afb2434abf772f1ca7128fce759b54229ef6d7826ecf33d071aba6329a22aaddf6ef340f06cb2186acb94
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	4	\\xd4bbb4088b96e9ade01616e12e9d8096ce9b0679ba385a5e264fcc391fb2aec2d02c75b7bd3baa9a2bb9d7613995bb2ce6c1ee73e83300ea248d878fabbc0f00	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x2e5ae1772b20ea39ea95569b0c7eb91dafaad69cb53da9b296312611a06f5a23e03ef83fd3c2f7147027fd4194f8d91fbaa95899f487f3acab3ec45a47760d82a3da07e4e5a9cea1567789984c45b2ef2c3c002a4501c20e092b650a28a52c7c4584875ef7b0baffdd21e6f58810f3197ffcd173322251b9cf3904db4a111241	\\xe5feff28d7011eb5015e5d4df6dfeec01f5cfd44c4e982f98df71023fae469c1e0b2291cc3f83ca7d94f0ef6b3af6f98a7bbbc5a7307c010812825340a6a33d6	\\xc387069298aaf2883a1b4db7904b0c328bc6080c99e08d851b46a2b4769f51951ece3d58bc27180decb146b2c431e803f84c1f49ac07fb18aba0dc2ceae4083fc2ab9159804fba0fbd12b39fb53868833076b822ab50c09ed0e099a6c107935ddc335cee252e4dd0d05d4b098a64b0deb95ac1babb6999df0da5b04c2317e8b4
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	5	\\x4ce2d7915fc44d4990b4dab77e800afac20577cf60aca966a7509f6a7b5392b213916ce0b2a518a50d374bf50b4bb72b4612f4b8906e48b2b5ca69b303731b0c	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xeb7264cc07132abebb044deb6b32fd131536d1b944aaa5a2f7020f539300c43010054ffbba93af5d809a11adc4abfbff66371a9bcfc785bb44af1af33bf51c7807c1496d477de0e28066d8f6ed707fb7c5dc573a14f46c8e9dfcaf1f4ad2c2940d13dcc52e7eeaa6e94be52cc766371c7e51b2c9a7dd5d6087b238e3fdf95131	\\x076dd1e76345d0f83d20e3fe37d333f2bfc3352cff8b4c435f8ed77ae0d644a0e58711b3a3fbfedbafd7946a410683c691a54c448c337b8a34fbb5cae73f756b	\\x6e24856357502afe77d4c3f7e095479183591d7edf418ff2051ee382c4bd91005b6777fad66a1e3da917644e57789dea86ab90b1a7ad3733d3a8324210a7c5381d2400bfa909404cf25bf7f0fc601a427079528ff3de63dba058130d90ab15dcfe8eb2dd80be359ca446a3c1e2a051c5f4d0dd824e10cc1fc3f8fa2aa7cc3ecb
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	6	\\xc8628d9fc55f9d14716245202e64b59e59a61d72a2ff3d8b2b6b5f6161d09118c2a1921b560d1a8319ba8af605db39b02db8262f3d39744533c499b9e422a005	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x4ad33a5c8e25c742820a7242f628fcf19755fa29999dc2031ddabacab0d4ba219be7412277d44c196e470e9025b0b51aa56b2a46ee3f7d14d6be531b879f8b6059f5093399f33f447cce6cbfc698f01a6d65106f7e96f42c87b2f993d3d0b7e90618e79c1bdf45b9baabb718c661757807b2c82b162d91703e6012f59a5bf928	\\x4aa5f20b0289aeeb37206c104ccca4c4b18885d2ad70d3f435f97489e4d72b058b47528064f26d2ab3201b21fc0c3858673ed4e6d21a8ce3f8baa1ab6f77a6db	\\x61ebfbcf0255f65dfdc0269f921ca2fa2e7521a4732fdc627d9b33df97657d2781ebac690f2d7e0dd2b9a36e7a65f9855978434547ed7e7ebbd0c421d1a2b429b7428e0883ea35b438736966981cec9130a9380f883db712552be8a7f7597289fb43170b4e3fb4b0b7c5e388fb6713348e6da356657ddd305ed2528e8ee32816
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	7	\\x28704b901ac3759718c6668dd6998476381d16751ea84f366b9f3bb11d7b82a725ce6e19fe0500d38f8d1af18db6d3e77bda9e7db8b40c7e239e8e4191ab1901	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x7b03328ee0b157f5ff145875ed9d2b3811e1aa7a379dd16a74b223a14137587fd2c7528825f109eaeb498dbf9e90cf94e935809398b620e970e5a46f4cf571af307e7bee0a90ef910c61cc867d356cb57b609c698104acb5f206914d7afed0d44cb321fb45ef4907c319e5a7c64c147fcce7a27031974e9b69de4850b31f914b	\\xecca0279f1b0066188c557504803c93fd3f11d707d03e775ff6014fcb5122ce9cb2c8eb71c06127f585a79e20833a6db5b653d3b72c74d90503ff18f85571622	\\x109022cfc5766f95287430f79c1b77f9e9b1a1117fc28b28e494afbbcfd758ac067e48747889ff09defcc2fb0f4cc2b88ac0ec8dbe55883aba109a714ec00665f6a9216a8872e0c8dfa40d48b380d46572a803804e376c33e7b7d4792d7ce3468d768fa93a44f2304a8bc8134c03c913753ba94fc08de0f05585db9598fd8331
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	8	\\x74369d935c78f683b09dcf7c68c5c162814aa776228139e8eff34eb6eca23dfbff34ff30127794420c0a74420f2be603756e5cf08bba7f4752771f08719a630f	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xeba3d964585a66913e96b224d0f91c5fbdde86aa1a4524078e618d55f797e6c255e1307ff50f3dee23e9c4036bde6eb2673d13bd195e667e4d54dec98af1188b8be538fd4d5f8509f7b77b974ce4315ad4cffcde146e1983c65bd4f135c867db73484db298153497cd17c3ac858bf394ec2955a38170828f01c0ba78f48c54aa	\\x0da75312b22fb9f3285f9b06e64b07e1e1d82a0d341922180b751b4a710a7a3ae0b39472fc2dba0302c7a88cfafeaab8863d860543540914724d6e9035ee0cd7	\\x514727a10f55841b300a79f71f058cb86ca58e68dbe12cd93a0913b2edaaf470c97823884704ffc857fa0730affdfe0eeaf7d9d99f172079f90390ca71bcdc95496c6cd9ceaf47e9b9c29e488d08df12976a8ebcdd72157ec067310588f5ad54d1b7508da994ed8d631a26ecc466b022f00f93792f439e23281737075313d784
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	9	\\x0b33b053528e9c83f9b7979616a3debd1d4d4a96196062e5d3af31755cf00a369a09719ffbb54b63446e89502822c1967afac3d62ef327d2707c124764a4410c	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xadd3d131401639503507fd97073cda2c401f819f3dbcf693d11e52fe8c698ccfba6e341e4931e8fd450f18fd0739e44f1d04c08ad24c843cccdeeda9aba0ece39e6f9f92d1a2933c677b00538a46afb2e0b193081cb46ca36ad72895c41b5eb8258a96a1e34ee0666bd27c999aef4644a349aa1dbbb71207ff5199bb562ebfad	\\xd35234c8e46b777ba8bca088c0b85e76b4228d6a049d46f02ceac3332a431f8da449c5ddd220354e2be2aa8664da484775e1c2459139f96f8e7d490e3f8a82ad	\\x1568d97b4aab024df1e6c67c583df44fc0e4e83866192aa45d7fda97d977d7ce11b945098ce33f4ace56ff907ee7b106138d03047fa8ed012467590f2d3b548b2049d439c21b1401e685ab916fc1dd941af9f543d13b98373acdc9d3ed2f595db2171ea3f8b8758791757beb5235920a279f8409a1e92f7a29c594ca5aebec91
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	10	\\x5bc05e30228fe9462e1bb38b40335a7483cc4d706a74f2df3da8485a84c59b5fc212057527582356f25b7c27a5976f1d95e331d1f6eab5dffb885666d2698200	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x1c864301b2066c9b70b0c3d7f025010692e8173d8319592bae4a7f7f3a31a271b0ab70194761fe86e8d8a086c2906b24a1d40c8020eaaa955da1f7d86f68d9cdcfc7e450c65934b9d12939ee50e6891395d9b48405dbbcad87216c178fe8c63e5f23ffab001a49370f025c3a72620c19410a7eb64d01e5356f93cc518d62328b	\\xd10e2dbdb384f1ecf0e331583c3903fe00bba46731af63289ee0176344f328746e713cbbb0876c18f4b0aae11004af521cda23430f10e312016b9f3f22038be5	\\x2e8863b9ad4e1ef0b778dafadcc06eb4b417fb3abc2159d2ad06a71107c93746ba11e50b75dda1494a6d29ec82939e3e0b5a576a02e49bf05316a71ef5b306f180e25aa4b296c3c0ec09b91b89fd3c254ed511fb25d22c81e2bd64fc389af3bb18c30eec8d9723e5e5001537dc370e93b45293d991b59c0eb7e0a60762a34cf6
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	11	\\x1a5776d49fed277f879b77a891fec0d89efd216f8476876899515442e325fd49648c9e4b7a990d38ae3ca9b0efcfc983c9e37e00cbd0f7d15ed5c5668b82330d	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x9205520afd4516e148b0cf0b129ccb71a6eb145059a518ff416dd56ca8b07c3e8440f02f01bdddc00c90b7b35981c75718d8487aacb5fc926d73ef3632df7be7311a36833576b29d8bb20659ddeb1d8d3b43cfcbb6da7adc48a96f55ed484608bf3aebbf33c5f42105083e78e67620aa69815d83273032882731074fbf7cf5b9	\\x08fab731e5e89023abe7b091b3d49392d841212caf4dab19edf92ea73792279b793222babee1962fdacc4d332fe7425bb09b6ba07f2e5b7f3241a2e7b6984fa1	\\x9401303c5711d61a91755ca31691da3909e9c26abe994641c8b6f50c719438e0a3dd3ba863640fab165de06d41974f003a7f658db46166a68cea2a0d2e3c83a950b54beff4e4e9a7c5b3d9a224f4f757386ff297a6eb494f9344642f00ac1ec8c8bbc3f517229439d94e9cf4220fa3168302907e2223b9971ef19a6959124c50
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	0	\\x1ae67bb880a91e5f54be1b4f21acbe84c0e5d303288a8c95dd45a23a7f6195fd4140c8bde4e31fc6e8f79c1d1b940f19ecae3475a70f6200c690aa4c81c04703	\\xff092c594bd0d9f73a4f8c6ca6b70f2a6ed62f4e3af63f5b8cefa9a8f42678f989e52e225e5f51c2384761f653e69eb3cee8d2e99412b1c0896c3a5363032ff6	\\x91a4dfa89e9c7d968d1ba7285c1541d19104dfd983a995d52712331b4ab0a3a65642512956a760be2f866819c295ecac095dc0d19c2ad2bf75a7ccf917dd77194237d238945460cd8f4984d22f91912d16f553411d6e3afc79f2a64d84aa77e40518847fc7eff54f503b4ef8e16114e0fdcec775f0022d0af7c4b4fea9fcc668	\\xdeb5d1824a1f66ec43cb2b03932b9d11fb8cf602bac83eccd0f015a44a62d005955dc181307b95c821b4d7645d11cc435a995583e242dd0836e722c555fe32e3	\\x62232900c6a2c2169eb2fff61f3ad520e0e4f748c6209c1f8e196eddc23987018552a676c3dd8baad8d18dbd57af6fe13c74b4134028506a109b9106dc0602921a306166715159453a45f2767a8fd697dae7840e4e0c4fab7365a26a83500f41e8573231be0882c95944d9405fb629c51dfb2e0f7779c307d089e63bf37a6117
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	1	\\x52831f1fef75f4eb48b2ffa790e420270d99a4d492bff8d10407fe8d4d435e1343f8410d10bf8b7e5eaf11fea5ef49122faaa21a23cf7dc194719869e2816906	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x91559a219700997717a8b2c926c0ef7c6903e87ef7dc7a7435c8908a96e5bda86819986ab0e16c8a52c638626d974a11d8146d078b4897d6181ad568d8ec67375bd829a9b075d45db09830bbca4f35a5947f85fb2b16a5763da572dc7487a22268d4af6479c7b0de95a54cc7119100928852c72b7310c7339d640a7b1780b63b	\\x608d4d6b634feb9d7ec9ac4d728fb957ad05dfad027962b31966a1f87afa154cb9240f4d13c8e6b2bdf283945be744a9ccc7d509b635c3b2e67900ad4eabaee5	\\xef22a035a729f29f0681f1c6e955fb3f757782b72f3648f2e462ca35de936b7e4982858f9d0a039124127aef9f051124ede6ca8a096aa60b704c2c8855a6d53e2d68382e6704b72371d773dc80fbd5dce3d9eb7e0a003815f8b099dc97e434a0d2a380ffa7ce192efa6e497b1f59b3c00f504c57fc410e630829dfdff151f796
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	2	\\xa449b8aabb329c0e1098ce8d4ac861ab3834a5aee7d56d70011cdb197764e5d4de5c11ff974ccca9a073a8c059c9fed9acd5818589d1d329259a2ee99f0bb603	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x921eecaf7de8ebfa48f74660f0cfb35a6423c2b76fe12c34b841ccae90928b004fb3183dd0a61104139c00b01251218459883bb5b38b737d4a53640b7b9998e62ade192f7509078c691038c0629ac5877ad8eabd498aa8d014991af74d751a0a7872a4c4b8e33ac45accccb2773a8cbb6b64cea537fdc6389b87ffdf22f4675c	\\x6274953dd4ef1a4b4ab683051856c740a3b9db1badf0e95b5e64d958a119eb33869adb85461ae4db56230efb60c2f7669d64a379962cffe22a0beaced36819a1	\\x89c5dd2a66ae73b1e3d3b60952f032378c53121c6fb385d64b92e1b54be3d262babaa5d5c79183f6fac5e785eb458e700214b991dfe150f8e3f0c26531de1f91f2fc8a53644d968e9eba08ae313b2cc0d0e6a6dddfd7ecf78137030adc00995271364969d995177b80da493352ddeb8c0a327725ccf7751c664b88e38bf20d5f
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	3	\\xf4f2d351e309d772935eb193e096eb266f93fb9ac45426686fcc8367bf2e774ffb20c3e1b309621963d0a6529122fd205c69cde7233edb90cb5c9c1e25767b09	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x222c76c0687c1f09182909701914186b4f65a4badc8ba4459a34822991add42ee691ffaff631fcb1bfa5c5eb7a035f1533664e9f9cbe605dd50cd8d041c7b8be09e9de989e1d9db7ec8ba8e709e95f8b24a94526a4dec271f06a31a1b4a03682006e064d86bd00e3333282f56de30114c71a43fbf0bbc5578e47faec704feb0b	\\xadce6fdc6aa4ebbfc9423bb818b56643b12cf5ded87252544a54e41716b38f8c0765683dd0ceae660f9763f5a2e925819f76c8a617f3f79ce2924404e567a6d8	\\xc4a1bcf0487b1d3af49f8f4e56d01b2ba4b37654f6052e2b8bbdb5f4315359f348af15c390fb8884c5405b21d25068dd0ba9f529a38a82f873ffec4df5fa4f0bf9309bf8b2a176f8c3cea261ebdd95db42d6850a85d166a81fea97845370f122d13c723d38ec4f96f9a4b77a6a874adefd8d2599197b2b6763bd5418fec7f8c4
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	4	\\x3ef40bc504a9824cee80c32476176cf07a732d43dcbbf691fbcbee01e58e6556c8831612d82b89f9ded59f9ae5b03dd9574d6b8ddab2b6640b0d3cebe53f150b	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xe330c55256a69495f6d9a316f6a501008587ef83079e92470ba1cf51ef4adb0f3a77bfacadd2236918c0b0df1de010fa10b19fdbdd16099edfca3b9517278d8c173abba4c00bcddf9c2a592ac80601a3da49213c7ce04f03bce7e4224091904bd90caa48a8b0bf33f232c6a0f3ff540cda1f260b52a891e988b98b3b91dfafd7	\\x4adec975db2bdfe7ca7b5768d7d9dbcbed28cf545b21af39608ea4ee96fe010a3c65c19f19839bf35bba4772516881b6edddc935d8bb7337f0421e4951773292	\\x233e3b8882bd6924c51d310cc34891d2b26127a5d53976a0bff8043862c6e9350d0199120962aa85e2ac66bcc93d65c207eeb813dce32e362cb5bd5f47cdf9de624ccf9d51ac3db6f97d5a4196037ab9ee6dd3fd86bd805b25111c74d54f76b8666b88ca8c6b730110176ea74eb583492307a0b4e939bcaad29d4bec187ea8f2
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	5	\\xd48d54aeb4857e5685ed52d684a83183ee3e9250471bd54eab13e54a1883c1baa20549bc32b17afc743834f4b8ff471868b3ecf3ec969acfa94a130cd8df3509	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x10f23521593974cb4f64c75dd799684021baf8099b7314f1a68023e9c8de2a78c79f293fceaeef57dddd19d0d75b2eb3f700c2097d422992010608d2d36b86e89f421e454d60540fe50bda7b76f0e0b90fc1559511a0cef66e7e46def718b7126beba984f99a57d5a3e65d6d36aec6d6fb5f3818d51172ace244389e31071694	\\xdecdb9e334a44dd3e605716da954296ab547687a740590f241b2f76ec29be4a0927be284e5b3994e4730c87434ad4d0aa7e3c61726617e0129baab12da1da86e	\\x91d0970ab26c3301795434f43c3287a4499a97f78c58be393eb7cb5b0ddb4427d2e0ad358c3bf86367fbed7383eac3ba778960aa095bd1a719ba8887eb797e21d18164aab37040a7bf0b05a418659304504a3448b7fc998dd832488e1bbf0e1f67ad601685220266fe4360c8b58dc73ff4a6de4c4648b8a41356f303a859291d
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	6	\\xc4c667195c786e1e0d4436e7f61c97f57b81bb6dd8c4a961d24c0e812bdd76c42b3623057ea70ca591ce3c6feb17f5fc4977e43ed130b53e72154886c9c3f70e	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x22abc668ba20daaa88f79dbb9c297b230e8973ecccd7914b630d8671195b2937146eee83162c8c8ade26884aea495515edec437f8d9aca51ca205c9826cbfb02b41983258e2ad66d38a24c494062d6000934f74b1a27ea85f29c919edd36d3d1dea5f275eba6481264995ea98500e27ac55dc10f894949b499898d392a80a43a	\\xc8959e4eae262fec12e32a95ad180396034871634f44793abc266bcfa0949b921df8f785404fa106e2af600e66fd8e2f66cbb8602319a203691fe58ca8a8e03f	\\x3e08154b049f777f4facbb143f922d919ed97375fe6eb3ec1b99e8cce12d8b8877f8cb4f6705ddd00c271de5d37628eb53e8a802b7106f5a3627d5330f4eae9ec452b26c0b59fdec03152231d4d56412fde4caaf0326b044ce24d0dc3696d032da692fbaa8cdd8a4f8db8492d94acacc3242648138d60686c81b463af7da973e
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	7	\\xc7cef203de964d4eb5cd51376456b77a98f8f859429382dd89b86f4c75fafac15c6d8b956959833e83cef7663401c78a8858c98f5d0397ac9bc6d283af771706	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x3c78d91655322e78605fa924c5cff8d6ec0d65606b3782a8d51c5fb3a3766e7c5158514965df9e8c8ff94e1236212cd225a135c5c7ccda86e6c58273f676a8c0fa0467346fcd9ab0383d08190194ee89600a3f5228fcf11aa6410ba5a5e13360fdde7cc5682f24ff232ad970ed0a73939dc3d397180718739219283fb7e0a7c6	\\xff5056352c7f4c37f612eb5e50ced0efc7c37475cfc8007683a3bcca0f30dba9ad878b1aed0a04a032f05d9a49c12edb274df917c4454405709bd31e38f91ce8	\\xe5d97dec2770a9eed96ee56bb0d02254c26a12bc4f7b3c5486973c8fc1407eac6c3314207da408fbaffcc801d716a912b9f7e2303fc02a7e3c73568f770ee27b75785b086c4b3e509bcd0d3c03c4b2d2a7ca4c4463de8faba967fa40b8cb3d2677170652dd0171ca3d1a00b5d23213db74af926b0d7bce29fe662eac81b6061c
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	8	\\x79a7aca71e727c92cc969fea2092240ac7f78a85f61d55d3482fc89925051aa966287ccebd5ece34a3f388f01d6ed55c551a95b37a2f898ed32b683311f0d102	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x2db0a64b96176b322fb048affe1714fb5957cdb51b62b604cdd4d3ccf2c85bcd1f186ae66ccbbe721e71cf87d53696586f7947c2a5d20d7f9bbf27edccf33a81910d6fa78070c7b9986d4a520743538ac05192b55ef897e020c3da5a290d269ebe969fbd1d5b3830e053eb86ad1942a05a6873c9a44405476f28f045fa95019b	\\x9a0f0e999470b7641d1036abac732ba90b5a015f0d2e541ef2814bfafed85fa4ec2dd306c78ea6b5cdcf73146be926f6dd6bccdab0b03276a209c7f2a2938d74	\\xaececbcad850801dcf3ffc75169054bbfbbd5994abf9b8410cf94b089d7b3f90b67636251cc84ef5bea09f4dd14794c9db081b40718603a2bc6f8aa43351398001abd49ac3464c1427cf87a1f3fc04ac4732962145fb20676442d6e8d78708cc37acec736a6d29489512c6bfd121707430ab17491ac0ffa38ddc62d55e5c88b8
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	9	\\xecdf741ef866c8a7ead200cdd8c855e58ab0e9b3b8a5b885982b7e81fdd54f86cbbe328354790ff590d60a4db1c233276e2fa7cff381be4f8b1383659462a507	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x12d48cffb82159d58a7e1155dfbaf4ce0e43927f5fb2786e614a0cc3033c5880b2a4aef323b3a02344ac0c01280fa652b29d29e09923dde8e81798cfa917f44614c17341458059110f84d04b2cffeab0809c9ddb245cf2f26bb28cfb1cc5e4728662c74cf3aeca0a13e93515f416c4b46f31fbb14e4fee64e234331246fd59d8	\\x658d8b45b418959e045c692d7adc06203ea9ce791a8fc1026904640c7321774cb2b0371a181688f433874a96b980f2fc68e687589ca8a873477257ae76751831	\\x03d9c963af686e38ffffed16f2aa7e2d3652040f39e3ba527ed78c282913fd6465e62a1f2a5d8cae2458e307560d3e92282752dda1cae0c8f32af4c4202fd9c0eb0a0b012a0b09b9498c7087767cd254a37cd572ecc6ecd4df24bca490126935ea593a75aa1ff35ba3abc1543f2983e7de3649688501cb116a4d89e8c3acbcee
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	10	\\x0c6b6ad027e5217f4427e17b8fff478807e01064be1be452f13a4cdfdec0f27839d1e078ffa0e7f5be3e2c9206efae57b716ac4c2ecdca2d1cdef626822ba006	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x0460df9a8ef4064244e52731bacebd07faa9fa0a5c65964f9a0060dfda0956f456bac935a4da4b18c845bf5533b707fd25844079ea92ba540358e0c94edc855314e4d745c81d2e87f632504c0984889c085ee875e994266f53374c4bffdc78095b3cf7c5faa99b2dd35e181079d9befa023061dd179708d7b745cc822b0af5e8	\\xf9de6633bfa22505699215ef055e58ede12221531ee5727884c88bf384a0912c67f3c645e313684988511187398f9bc73db21c401dee5ba92e4f69ba1829aa4c	\\x9f84ddff5741a2f5921cc9502213e9589bb2fdfa7bf482259fb0c1e85ffcecb124f5be97d2d5a9cb8dd0678abfbd566bcca0284de31a220f24c173cce36888b67db9c385f5bbeba4e0fe2831bcde5628ba0c55b9fa304fa0844b34c9c857483fb30f7084b15be50791c77b9088ccb7842a886cdea65ae1d768652dfb7c27c865
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	11	\\xd00efa37b84328d8a8ec409fd256152d7a8e7d760d0b795679578d62c42241a179eb6b1592db7a837b468fcc3092f5cc633e7c5425c7585b0ad06acbf8201904	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x5ca0480e1e4abf3fc84a2a8a4e1cb25c118d7925255c5b835508fc8d934388638e4dc7af3d071d710a42ec5b7104f28bd176d3ee83d34343c1a60884cb60c78946f90323fd108fac5b7c9b6598deb2ed63223a4c9d3235064fb26dbc55a704f94dcce39d1742936b4779eb731d3e65901293c3980c646a20b108a6392878f736	\\x915d385639c289a681e6ddce4f22c7c54b246615156cdf4de7764985a10956a0f00de32afba26295d6bd90b17aff1c4a7349daddb50da333ffab2856847210d2	\\x797841dca3a1c0076502fb72029c8e973b7d22f1fd5c538bb73a30c90563016544566849af26318a677f42724e88fb1d5bb0dd2fdf690ed3d271ac2dfbee5bfc028542c13c9258756014ab83b9680c6543dea041a1f2623377e9cfdfb3b0e07367e3827abc6798cc4809271fac383b2721809e4d0110b4f879c191b7792f2474
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	0	\\x6e73f6f52452fc0e3a1804dfa3f8fff8947f35365688e19ed1d579bc030f687e7a210810ddaaeec0d8fd58e53a5877c691337685417fdb8240810e5bb180c103	\\x42d0f6a215c182209d58c0d04efae56fdf3a1de408873375550fa84fc5f80622c0a1a01b0f7cc64663001615d304ba884d95511dbab07ec3501f06140205d920	\\x1a0245b63b74a07e20928cc21f5916aa7884233c2439f1be0861b869209f6031d1c12e806c088f87b2ecced12837a6990da71985417c75879f76576da6fa11edd1f6226e0e9596e27140830f61ac9f5a4ecc6e2021a28077bb44931b4531860aee9b7862f6b2077f574b0fb71e387d057f7724f40ce9c9bda45a1fa7f6d4030f	\\x7ad9cdf9cd3c0f1ab2473a76e30086ee908cb119b2e18ad2b13e3572ed344edcbc8de439584c361f36da81ef9cead622fc5360f53fd6cdf5809a683d658a94dc	\\x10aa58e4dddc3de579b246a0ef117fa90286f0bfee9be5f2f7b560c87482af03a6d0728e1d62a622483f1f851d40110a5a18645bdaa8a6c2284836d73894331f752cda57451a956098fb99c647f5f700360bd60c4731e4a8fc8156566212a562abcf4eca00354bb49053ba57f1def8d1ef43f40b9c477e42914c44c6f3b0a4ac
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	1	\\x4b770291efc4c3da92dd37af14f23be3cce3a0a21642a24eafbfaf6492aef02d549c31f7c241e528c91a6054284b6c89fb640fbc8e1562abeb732a3e9996b506	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x6ed294682645cbe40e1e97ab8e0bd3031f5ec7c59005b48c06eba6a8dfe9b7eca9bbb43ad1e0a8eddb4feff9890ab66bc062137b1f239b02ffb0cd82d95a08b8960e75a2fe3b969bce769b423c4672355e30e965cbd2cf8b79abd74f49f61769f886d42dd90844dc2ef450ef0845cc712612afa5214193761f6bc8ed1ae1ae8e	\\x01c30701b49ef056d28cdb477d4e9fd48fbcd5503fa917cfd4f6021f8f21a778becefe75e5ffbd4400f2699737981e1baaa3a4e322f7aca139fcc75de3e0c4b5	\\x678207d13abd99bdb650ee4c964f09f258ab5d0febc7263e6a6ace95175762ef29d0b22de3c3c0fcab6159245b96bc73a2c768f50161396376a0b456a90dbdda460a94a80c1bd1acb10bd503c550864688ca40b1fe6a497bebe54c14868fd4f232833b1c3e3c5ed8a4170c13ec7a905a45e70cbeb524e343226e3486137078ee
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	2	\\xadfbd72e932bf56dd9047590fb446954ffed56c549a2706acf9986aa68bc78f9535b5548c5ed2ed725a5b8513cb2daacf52c5c01dfbf3569072956eea9995203	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x82c81147d06d2aa4cf9378bea78d4bc7bf6dde824c88b891975b6b9754c5ff6da6c42c822340d9963c8ec697b5f908245027d7b15c3b0c7acfa9ab55cfe2e09de270b09925d9579501580eea896adb033639adfc2c99fabebf24fcfe578663cbfe5ca3111b6c9cb2a0a2137ceeed8036b021a7947716f34cea0b1e69aa447fa3	\\x829ee166560f6d513b4644d8e63385297c76ae440081f27cff9fb7aaa5ed2be391b7f11f66fa0892236083b83836a60a48b6af061d7aadf3514c5ece242d0beb	\\xc621910284668c5eaf9c07a93ac936b524d367259e9da9f6d86d199d15dd43cfa8cbc12b45a6160a03f800a1024f52cc739e9626cff414d87672e62af52b1cf08a7ec7f267d2cc79c40a5909fa417cf797051e21d7496b3e456f8a017a6627c3af312ab9bc1c3ae932a39e5ea94b13077f35da4f729891451d4db85589c5d80d
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	3	\\x02eb970ae148fbf352a7a7038a063927012581c7a0c7af75a6d062d7f61676247387cc46494a55d7a0406449d379a33a42b36763caa21446dcfbc4fb2aebae08	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xc3663e80f5125615007760751ff6e2b4fb7e4b4d850e6691348aa263d892a273e7e8edcd881b56d0be8a8f655cfce65e2b2ea7abe3fbbfe6fb1c2c282bcd52aabb922cdd7e406b6adf72435cfd7e1055ec59bf0e9d1554d4fe87ab70297a7426fbd48838e83b3c0ebc8d1b98adfa05414eb7e741094dfd00a0e0eb96646eba97	\\x86074bd8355eefa2110121b849e54a87db3d80849533fa6ec92bb5b34e4d1bd83c9d82285a6db376728482d92d3d9415d0d0476a641f066356168236352d592b	\\xc8cf7c2600674df8fc839a2c02ee18e7ddb490e869888a65bfa91929bdaa1976055b27780518c14b85c1c9559ec974c4b3d41c25c017de9df33dd22722207167e0db3971d8b1f3cf15f26989c9c006afc5d03ca5ad1ae5d62b29b85dcbb6a66b47fca8baa1191778697bb26979c03f7d243170f4814f480a3efc18015dc35441
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	4	\\x8bec43459287db44459f0319f4b6da1795af7511126d0cc4a494e9b3de4a582b65ee0f82c200feecfcfc49accb1de8787c2192961aaa7ebf2d535abe72c1ea05	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x44c56cc18cc7df1f00ff558a46bf397df7813f8004fdae90ff46ba4749d0b339d7fa45eed964402ff0a83742bdffee79710b57316c6241c82ce0f2eeb337835f70809e1459d05c1f68181095bffd312cda099b958d0df09a29d160d1add0d097222a66a99d10639d7e8e4f72819faca31bbcd659beade084b3c635e780d80feb	\\x75077e779c80243dbd6ce33ed787bbf45ab584cf9f130a723f9c784849937af55dd71bf8f1a01069101cce22a82188b2ccc13254adf082345948718cefcc9a6d	\\x33438878c38aca469c3df828056bbff16e66bd2571c7de105db66bcc38400a91593e75d5507fa2f3c80a1ac0dbdd836d4f69bcb7d0437f7c68543ec653bda212ffd2e61c7bbb7f4b70bb3dde3dcb17436d85833ab146d3ed8fac3138e20a2c9d00700aace03952a02a75385b0bb7123e5943cb0795e0353e88904444738a3b1a
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	5	\\x1de2d935a6050f1c0ac58cb9a756d6f7fdf370b4898ae1f4ff8f0a76bf960cc2df7597efa25c766b8f65ec6084b106743150c6a0edd118ac24639b65aea1aa0e	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xc668432823d2e906e924f42698d47c312de9e2f5bc033c575ff85577eec74ff2da63c55b909e538799885ef4dc00cfcd66cc1d4e8bb71f6e1c3bcba327ee44b7d79e54381ec0ddfae7a0104f91633c8a82114bd5d6928dca26abf0c028b913db71a72dc36347d7ccc5ede6fcb06299deeecfe15e0de23d23b507cfcece776c5a	\\xdaa41a779113e45f4d5af99d199787988d3f89a5c5418385f9defbcb6339f0c5a194a7e24afa09e420400e649869c410ff83659a1b45b5cdc75b98c3748e9ea6	\\x3b1a7f1c14959344b77acc2db8de931d831fa555e2ee38db23da37bc020deed43380bedac353b345992769e8e20dcdad6c138cbf881e769c97916493514fee5c1eb73d3cb9f258d29d0349467a71015deeb7bd7dcd15460624b46248c675becc384ca713890acdc420a702959d30b5cccbf086285cae2a23a47c1fd4bf52c8d7
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	6	\\xa996aaa086346b3b9b77eacc5e7af53726a9e7e702d5c2e31690605f94f29004311853b4ec5c2423b78a7936ea13231d2e622676b1df3331eb67da0082968c07	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x2378f52de7dd4402916e61b12ac6e67ed1f297886e931fbb4a719fec1da33ad95a8dad0b0a54790790a1508a15fcf5e1e4b48a3b451514575547f912dc99fad8737fba67f7e814a8bc0471875715d7b3f15fe2384903c7727658f5e5e6d2c1014f398e2bbef71a83359e1f3bc88fb753baa2a27f0676fbefbda08e7a173f813e	\\xa3c8210fcac556f644c1bf34aba95376caa70a025992d15ec566313c82a608c69e4ebf62604f468e01efaa6202f220686393a3fda77c4c5fd6e21e829efef3fd	\\x7fd3313894079f64bc8af07d0e6d0f0f6b1919e953cc752c7cf18d5e24725fe2a19e67c363fe92f79f9b077bbfa93183ece9748380a6361a605bf69d9a756688a8967b232f131a97a0f4d63a91769433ff0506dd3c87da4b7670e0a2f2c5f9cb9332ac920a123922f09e8a12cf382639c5cd4c66f5115308106c3482c271783f
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	7	\\x26a45e5b097a6aece11c36a9b8d4f78c82299fc18ac62ba9e018c5d108ba95b35531c86f5aeea002eaaa82bb800fa8917e06917ad3e92fd0eff482b34e776d09	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x68f641c6bdff1ad82f08b70a28c5fc129f68e264901f5ac5879e2cb09bdb81383aeec19a1e1e68dc3d4e19365e73e34d64799d4aaaf69be565ce15efcc469429c166fc0fb13c5aeb9d2560403115bb1955fbf2a955515a33c0c6ca6a5992b3eca6f2780220e447abfdb836d07ced484228dad8b2c99da91c79565255fb705644	\\xdd8c67b9caef00d91612ea88d381a2411772192535c6ed3867996eded0ba0e245cb6bd36ca66ca7bb9183d1926b513452fd82fae92403f7fa6f3334de5f289ef	\\xa52dcd5b62a0e2f6c8e394457a970a73bbc7c1fbf395648be52f0832fe48483dcd9a3797fc75df5ca7942061e7a27f252111f490a0a784a34a7dea7dac54578ab387538b850a30ec6d7b208caff92a812ab99da0e011b2cd03cc07fc6b0afe6875a909d4fe2e10d54cd1e294c89422ee32293a17479fbdf2d60b69f1babef66b
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	8	\\x01ae06621f0de3229f3a5d26c96c65f74fc5a4fd582c169af9a0037f91ff57557c88aaa1d0814332d6f23128a15a5f3a04d127c7ad8dccee0977f6eb29149d05	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x79add648897016f32d2c4f03e6b2c9344ee982577b659e46f88e2bac5a546fb1cb7581b8ad8e939c657bbac9821b94bf841a1330b99d341fd32269c26bed0722a981b194a371e9f453612b6c903b33c1ee6eb6d39599da65487e985e1dc349a76269a99ec735ee7da897d9cddffbbe8067dd5fd0d937d8043eab345f9fe03c60	\\x83fee641066f85d555a42c6e29e7cbea23d23813f534dd489b031f18d6ab1bae499fc5d35044fa961b6badb3de3f2a169cb657c75f583543b915d5db9b0fbb5b	\\x58a41c786e3b123993453f2d12479ab18f768d81924f15f5b2060194ab08028c30e1e97cc141a7a77bb3aa648286653c9cf6ea5e4b13ddea127a17dd1b7569053656965bfb08c26083e0f598916c57ae95856af2879d7730e6897988a6bb6979b93b543d3f33a88c81bad7ba5355caad7a764e9f309e9472baf6870e5e47311b
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	9	\\x224b32b85775a021ea7bbf383952e6c45e0bdb34fe2c74fc4f14f84c1b020e0df1ced1e2dc995fb682e05f3542382623e66e719d73a7e0a36219ca25bb72ab05	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x51c48eff9a64e91fa68273b303c5cab215494f38da5b2749d64c56e95cea26e84dc47cc1a64478cebc51d17ab06cf22c20fbd428bad9e9b40dca0d92b231dd78edd76bc93c475a3e1a3cfd5df93c07c5d5e05accb63477eacf6bd3c8d8282c5abdccab5c16d7017545e87a2bf39e0ea85c8e09aa8b2728d90120298cf61dc87d	\\x27af6f5f98c17faf940f5d5b74219d89e9b3eb69c3dd594d9aafdd30ed14640dc42fd5010cd2e2ee7999405c62f3aa633996b783ba737dcd7a96a36fa69ae207	\\xac103f27fe551891769bd850f1fe27480eeac0f0ef30d1152c281c65c02d7d03c6df1e2bd6f9dd4d045ee5a95ebe8a6ad041872f01bc4057c974c725f2e23df547ad5ab6ae64b573753163131b4e2db6fb6887c34d415ffbe55d75157a1d7b4392d233bc4d27db69b176938e3006f32d02ad930b4e30b85e4e423d08cadcf48a
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	10	\\x43ce655a1df4c3ae80b9afce9eeb4a443cc124c581874e4825db2bda784ad4d462942082a96c2140be79b3e71819c59997ac0822ed552a1f890a6b31bf824907	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x9d1ec6a1c0305871667969fb7d0322421cccc34796235a5b5248bca66f704a4055fb07640c8f4b1ec59ea2a0c9cb2530fc5b051699dc16129f73ccefcf07118c4a4001e386e2270403653c8023c07d0cd808df3080f9547c11f1f72363cfde2af22d2f345bd229e342fca10d36f41d7d7c2243a8ed0ddde5874eb79508c98f97	\\x3d8b9f95e1f22678312b5503df6b86a472999614cf515a6cdfa0b75d2f5c20d1d7f549e7004bbded6fc4254ff4861ba9666ca6ec06a9b5145b49dd0577d52c6a	\\x9a2734a407f93ca19791a78aa07d5f97a6c1ab1a5e9bf19825a47783f1a4d0faa23af385f7be29dffcd7519d0714a65ab16663687bd3f9e0958bf54dd85665e49fbb5e76f9945c4fada4e17c853e2bb8ad42490f68f632d541a75f5dd40f7fddf006cdf1f7ccd3b0aa0d3cff77efbc1b2d2ef32188a3885aa100b52a6138adae
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	11	\\xb3367378c13e27119c118be8f0c98cdfef3f42dd23b9bb1716a850c92038c4140553be5a6ca31ee6369c1beb920bb3ca31d21db9f94e92f2d4f7a6e99ebff103	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x22f83ae0af892fbeaa693def6db883e23c626bb839859a225fdcb34e44c2eac6d359912c892a0763899e691927693ce4d205ee1804d701bb276795cf953f0c7cdaec6a00c6477fd3f2a7b16648e55632058b48e22b248935f6caebf622f63d5ccb141fd65db66fa6f2302c8a98ac6bfbba441f00cca9f7dbe8242a0b1541606c	\\x56151d985a015302c57f2d245a8212342893d86080fe08d75319c7c69da826a711142b5da52c078a7df573c85a21abff0ce16bfd529f3c32fb302b38b049de46	\\x71098557452ac91342e905b7eec22070fb57076010239812debabf14557cd97471b7d3b8eca886841d320a7eb8e37f64ab860356719eddb9543b737f0588f9a2822dfc2246fae09bebf96264b4c567172e6e4ee04087b5790c80258906da53e14f49b9acddbf3d918baccfbc7b73f439bfeec6896ea888ef33d43bfd692734c1
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	0	\\x892e6c793b90784b28c646f325f8a6a9cc2e2f6affa5e2ce5ed03d934da8599c9b45633a022142864ab31c5ebf9bda626d51275bd7123c1f110a74ca608c720e	\\x542a1d8a0f8d1cfe6b90fdd17077ef337ce1944384a93083137fe72fd8ac8fb37b02f701dc3f0fb3800f7915b05831f8cfbcd786e2ef9c668f309adaaf4456e0	\\x6d10ae86290fafc228f250a0b188031b3f844ba3df1268ab8d8b2469ed2da6a57f7a795b803eab27510c4490601569808cbc66bc2cbe31c8ff385e8014634dcce321e6684228eb4458649ca044489159183b46c4ea0cd4ced8beddfdb6589c55bc2bc676b2b7e86b821431ef145f6ebb477a554816de3196dec3fb0540c51ad7	\\x7524f118bf26b793ad33c38c43a281b8100bc22c9808c36d85d464fa4e460c5c61316f3f6aa3130cda8dfbe18e7b44ceaf103264f9aaf54335a283a8ec0a8d12	\\xc76f730f0ea73cb3750f88dcf6de6ddc75a819f8045cabffa4813a5fadc2c59457f8bbb3cfd5b48a4728054a7ec5310de2654b99a2323356dac9f063127b534bf1b05758eaf2f3d9310e234c32d065e38471bae62f9aea4adaeafbef6d48641dcec6b84b7be6cd27b184258e75699430b0a82086aff34f91fb8a978b4fd2a5b4
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	1	\\xd492efe67d2ea13fe0e6cb453afb569b0eb5d871b14d0742f009805a7c90ae77c31d17959e20fe4eefb77517c1aa77e78a6709f94853e6db21958e2ec9ec3d03	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x48ef054ebb3a6a2e0f82b1d53364eb9be92607f0e7ae856b5968f27d5ef12f7c7bb0243d82aecf913b68ecbf74bbe0911a1ae7985c35d66c113684364ff945d8e1c635773d15a78ed5c1748fff0a28457cbee2e61b8bae49b1f1b08ad6f4ac4b206f5a007d6cfba242e1e58386e9dd9471a98240834b2a579221ad4a9df2076e	\\x079ea807c4d5ea35a63f14d7ead1fdbee18b4f284c244f13b45a39fc24e39b4d187a1baefcf8dd565fb4ad4ded921e12cad67386d03f09d647742445abd2949e	\\x3d42816d5d7f676818628e4e0d5b308115f27186fe3448e1fdc06ca1288b769cea18f55b3368ae1e8c3e2197c225153682e3e7d890ccfd12f5752f05ee342c0d1c60c811d5722f0d6f78540d8c1d0a409c561f09b772ba2aba9e514e6cdc4c0955114a6020cf8ad1da65b059ca0ca0563cae0ad072a47c839ffff3d88bd5a9e5
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	2	\\x7e56d57f357436fe333fa8c2d8c101ddc1cb7ef580a580d543627191ed1061362b88572ba6dbeedada5c5e5f838c169dc2f98d63cdb6b2e0a8f9362c80414d02	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x7af2d3b9c27ac9dad2599825190391a741e5b412e133506d0266738108a0682fa4cc4ef2031f0ac0fbf0f065f3a4e0a142e0f6c00064e985cb33e7b871ab664a5df07329756f5ed06120e3dad8b4fd6ce37fb5d490d7306fb1ea88eaf65d0f420a41cd495a35141367f4797965c5512dbd50f083149a1f16b627d300f3f999d1	\\x52a658c058a72319fc82f3666fd3a2abc511f173525a8093f5e510bf32c375cc8b9345b33ebedf204c968742add455398f06701c9d39d44d3796c60f5ceb7336	\\x8bd28a397e4224c0ba6bbdae869e9a530ce9ac96868b08d0803033d2f3a5e368a2ac6ccb743679ebd518e99d6c1bc50e750010d405c7af696983945dd984a6aa2f1bd86fd475952c9d6ab6f9ab404420d35ca6012d353390132f6089df3a206a5d043e3637673d51d2442b67ebabaec026bc1a5aaddb61dd0d0df5436b6e9b9f
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	3	\\x1a37ab27b1a77f640cd07388b6eb613b13a40a118b1dd1b28f992a56ce0b3cfb6b3e4f894f37bc2807b052a02f0e950abadb109e94d269aefd05852985e87c07	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x810c17ac789e9f04ff7fabc6f7a3857ef829ba320a3279cb976b96a870827a34b570907b0a568e4b254071c2843592ba78dd14c1407bdd76249961f46f5c7c1f0f0ebe8c954902ca6c409bb17237665fef67c76c60a7fb455cf22f8652d602a6c9f21be7879b5037ea0e7786071d8979b68a0fee1db5d652feed00cf7c20db9a	\\x1c26469f457d4234d166997c85ad357932ee3ea81e8e874af0349e43aaa4a5352c496e824beaf24598851766c32ac5a6202d143bf286e2204d21e3351169fb2d	\\x0ed76adb871459aaa8bf726e0ab4b71ba19bc3287c15c8f9eed0f8ecfdd2a5043ea69c5142ba0c45a3ed4587b668df7992093f3852236e227317f2190b4e1a4b399eaba9ee4264b92275c7128a90f26f9755b4fbfb695d50c32b46c01761029f7d6c8cdd972e393a171ba6566188f1a6c80ac1d9e1481a84ed4e07e2e38bc1d2
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	4	\\x4e8e68ae19c0018544f3104fd298cd287a7f59c1df8ddd8296bf01308fe1817e63db8a45413bbe366b88a932faa52e2f881035d7517c0667195679124ed3af0b	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x8688081dd1f61b3a73049d3b14d75fc7189a6720cb13a8d1dc53e011d797ba9cdbedf97d3c47689349697c82a3fb079389ff4e7bb8e7040e36c77ea360ad9354bc27e96b77f4849861c26f2cbe3088ff3414797363a39648b2d4b8f8c0f7f67797d1b228d3ff36a77cbbbebf894f146fd4bcb2285d1d9f5d7c1188c3e5fed9bc	\\x8d14360fe89af137327bd5414281c6ad555f24589a7f18d79e21021edba8a8d44c2c90e7ffd8ce90f7551c38290d3fb5dd5edc8b5e84e14bcfe31780ab60c1fc	\\x9abbcbda2fa1bc859ec170f0d4e3d4ad35098de1d0a926b9c58094f22ff9c841c0eaaa21f11cc5421be48b84c03b358da99e3b0ba076126c8eef5c062b8dc2526472378e86326ff0f7c742956d586552b403d8538519451a144f2f74166ee77aa886f0f625d316a08a5982391a59409067291a87e3ed2c6f0adf331720b00917
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	5	\\xa561f665748a8ff820593626af8e1c6e94da02d8868a2094b2976a4eb1cdb0de642bc1c7fdb8861ed4ea615b9052d42b18b3d5f3d11c8f668e71fdb4d7202c00	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xe4780fb28a8957b9cb5b0ad490ffe05fcaecfeb65499993c900f4ec644bc39ccb5869c0eac5d9c0ca7012912be7934bf5e19e19418b6f59e0a0d48c387204116a0c9472c9181ad755b167b1b771372ab6457484705786d7d0626563ff9fda9a60b968e435a4316a3dba174294569e54917427e8f3ea53f9362d358c5009eec0c	\\x4baeb3e0084a9c986530d6924f9907a2a3c4d043fa8e5867efbe444f13e48d52560b0a5435260fef54b16e8ff215cd7760a799a9a99b9a292f0db1bcbe7d75a8	\\x0b00a29ffdaa10f49d08e71a3baba81ad5fc1cdeb8e0b7d1d3e298fdc23fc0dcead3981dbdcbc4624206b9a1bbdde510a52ade733833128b812f4a84ca476c3485559f9eb3e9841a114fa6842994bb28b5e4377f426e28376b080ffe93d7c00927328b993900b8152e06c5695c4abe3c5a6a96694de2ed37ca8f91a193dd5d06
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	6	\\x056f86ab92db83d126cb449c1e0e44f250c3c0808df3ea5735f6d39b0c3ada1a3b12bde5e7369f8f5c88b739403e5235efd6e6290263ef30d4338b1d4cc8b60f	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x437c793df3fa7b2068d55145b78b26c922d1760c30583d34dfbc3f7d6f258261a898794345260cdf336abd5c05f2d4a41f42ae5343a6dafc6f5555b5b7c1475523bc93fdccec329a56e557659b715a2aee3a1990b2068e50c5fcc8460d790527f5b0687e1c39860c9b33ccd16ea2beaa725773d03f8ac27d9de667106ecce44d	\\x404e9ee68b7684378cdddb15d162e0c337dcbb80488e4344449250f900878380bfe084bf165fece15b839c46e19bb84fdac6cb11aef91e9969779686bf0af02c	\\x9cf58e743ce259b872850faa4891bd276f7cdc2435db4573ae70816b18d6c47d4a919ef3b4e9fa2fc7602a1a6cfcc2ed916d1092912d521252179472f04af9a56acd4594a43d7de4a5d35987c0fe474f3ac3328627d69f543dfba039edec44b1195ad58396a7d12352865bbf383577418cc4c58cb571a2883822565bed2a524c
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	7	\\xf60b802ea7c001498c7d48cdd21791b02617b25aa7a6ea4ea72e21d4c0f6695f8ad6ee244a68d5f7ddf1fde21b22a52d23de6763259f1e71b2226d7401b8680a	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x0654f4ab54aeb3daf96da49dbbcd82c1e4686a6d7565ed1ebc614d01273680a374e9562c205057fd63c0e57baed23e54430559947d5a1fa647aa28b3851e973afc21c9f6d018fa388e3b9c632f336b1a7b30233c801b607bbf9186a77f50be60d5ec6791282f7ba63202fef049d310626007626bafcd756e67c8adaaa42c06bb	\\x96deb8eb851784ff90dcb4f285b58b15bf0bba99d5312d6d95cc89ef1ffd788cd455f590c17159c4c226430aa59f9815da22f78e3883e3634cb0350581ac191c	\\xe7fefba704d1a75b4308d9a652be5545a75229f9b4589cb1c25d22039e5176beeee6b95acabe5053e1c8d24ffe82327a8a91c54f95f0ad33afc0480f5a69ffbae90edcfe07d334884505f059fa6261a06857eaf5d20dace7e83650590f51dbc9675d161d9eb0e61750d260e2eb6314110b04dbe2ef149c0021ea30c0701ec619
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	8	\\xe9aaf96c03e2c5e6fe8c4596edce65d1f632f6ae67d1fc11f631643fdbd00dcc871c5fbdaea5fe6c4039ff1c5d29cfd41c8a3b89400ab7df20d1bb877cc71e04	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xb1c257557b9c201eb5591f92a17dcfae48923534017f2efee67845d00d7840bde3aace869910473bc48e04f44d94c29f56cc15f3bdae8fc436af2216879042375413d110b22e1a7c9a4b8bb5c23396543fbe59dae7258ac585032d972b9ac86aa0f09fa837a3fb4d61ccbcd23ae6b46249b6acfa287acb53979a3a5bee6ddeee	\\x39abe66cf4ad116112715c8111835ce246e9234412530342e208984dbd749a09bc0f52218aa4839c125c552ca532bea097c3d3fa44005f612d7fa8c93b662bdb	\\x0dc3597dc08c17bf57a5d90025c6f3b44de5868df51c87544c127c54b6b2968092d0ddfe083d34e36d9ca965205dd1542f09475d7db449fb2e0d850a5cb72dbd871f834c32c3c45de1a0efce38a03021a42dcae3fc11bdb764ebc78ba4cdb009527f9d5776fecb8a63464da848a69c5f54297fe609de88eba44dfc972898d9f7
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	9	\\xb6b688ef38bc2da47bcc42044a0cd046508649007b13b74a4866ed1d9a45455bd084a2c9063c1bba184f607eb13aeac4cf0ad269948459a557d3a8117b6b4204	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x8865d291a3f574b9af9bda3c4e05413d2f469c6b9e1a570a38e6f3f7de5ecd27382ea0cfa97efb33517d12ce9e3df9157dca60de32200bb68eb38e59adee3cc86678024229276f5cc9df14fd198df3306275d414ab28b513f1795a344ef356522b307cf91057e7e1ade2faa211bb0de4962129cdee4d9f7faf9bafe58cb95c9c	\\x9b13213c9c21381333db01d0c1c07518746067acf5c4610371d1519a18a75f3d0623e0995f32139a2ef9819d41817809d021b2ef93c7f3aa7776aed3c3187e4f	\\x60c7bf8ef5c97113f3f4f460c7c096556993624a0e610d44f28377f63f839c56be1a84b86194e412f53e2dc7bd55c3fe2aed0eeb6ab8c42aa6f5ba39d8be6b4f382ad4fde4f5841f5a233b61344103cec8601f8359e65224d8463170108bfef2dd87105aaceceac8950e92fe0a627361b85263e90a210ccfd47762b4a6af1732
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	10	\\xfe4a5b8f964ef8f4a4c04f7fe79067b6c6f62c164a8b4879d8008b8ab65feb9df9cd5f627e0bd4303c8bd5455faaa15d666a5d85c1f1a22922346083259b640c	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x87684b983b8d3353b0b09e435a5df71c0ebe88b8ea6962f44fb0731d51d0059f2e7777716f105f0428115f324dc3d345bfdb9b11303fe0fbe23a7d7351c51372e582494e4a44378b255088cc9f8fab7e2dfb6ad77a8f3bd0c9c1957119fe06c77920dfd1208dcf05af26cc90e2cb46ce02f47d60b20e5b97878ef27858c26a3d	\\xd8f80695514e091ea78e39af95494883125c78717d5321067c5b468ccb991b94c06ed38f59effd865cf1e752dd5662118010877486496294027a8b6240fce01c	\\x8908938e2b896a756c2035f26d1f1fc710672af0d6144e84fee60a4af3666b15d72059d83ea6fd68ddbf8104e731684ac38a8638049ca8a12814e06e1361a9c12f39fcad67d3772672be31aadca4a88f71556becd77fb94adc4cc2f96c50ae07dfc93e35f8ab32a7815421fee7be4bce509777f13a8fae50a846550b1a93276f
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	11	\\xc548d4091759bc7b9cac83125fff60e5f3055cb06b2fcc1c2088ab58327255434bf61831bfe8987f37c4ba1f73eeb7d72139eaf804e73b1c6bb77ddbb2c3b20a	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\xabc7039da5fc6fe2b20cd6969f35dcc48265156846a90e41b8fddfe348214026104965a453e3e9e1854b9d8b2f1d2ffdebcde807302ab12ccbdfae0eff5eb312ce4f2050af910396852d47340df9774a696072cc459824c08de53ad207215534350fa101801521a468443da9a6b0a1be9926df705c6fe24cddbd39be1cbe2297	\\x30d8ee089c484240688ac221f1e1e78ecbdfb8e50a45a37dce1de7ffd7930ce0a12cf479e81b7b8cb8a3adb8a55e0eb91eddc01c4cb134c3c4a96e4939778947	\\xa95f89522bb2ede3906670ef9ddead22a4452753529358ab18a3b9bf05f3395f76fa14e022bcd0d3cec16a0a5bb700c899c6e977e54f40c4e5bfe36cac193b6a2cd9e0c9c466e0df91d34732f204a0defa349a4fef0a340eba5037d872188075556be98dbdcce449595720ccfd5d85fa1260ec67f2b8cdf6aeb8483d31f0d19e
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xa17727931ed87a6913eebc980a4540c3bb6fcd60b7ff8e836beac9bc7ec532f9d86a8f7fd30d5d6f4e8ca685d2e82ffc50d0317e0d0dd9e337ddebcab15254b1	\\xdc613958893998ad4df7404bd152cdbf33cb779047dd6af047e924b092b47536	\\x313e72ab5496b6a44a8fa1852ff03f97f9513a7046c4cc7b08b9eb2255d70be05212d6363839e7b9bb978f80f1a7f9c018528e61465f3223bec2d2a6706c0ad0
\\xff9637de9aeb6e0a228f5defae6b9d2e69df0b7990d95d2f684b153e078bf1a0fc1e38838d628d965c7a7aadc40c19ee7cb49a4308aefede5032dae60d8c9294	\\x203dbf4a117be6887e89b118965e9ea4544ece17b02355ccb9412f478bf00f22	\\xf0de66408b09b0c0e480ab1037dd84ce9de7fbce87e0614f57d345ce8491ec7906e7e55f5b21947c33c2a6388113d04b3e409ecf0bb23d639fb6164ae1ccc09c
\\x249f950a5cd62debf0809cf0a95b81c2f08ded3d72281224c990f3c50303099f779899e725d1e54b4b56eb496f9a959a5ac9fc379f4ef1024842b4f945180102	\\xda49a324ff141f310c3af2633c8a88c7f60a40d7a0b24705decfb4fb5b2b2332	\\x4351b44dbab1dbf4ffd5275b2ae19710fdf9fe221e5da0c3030347b5db6a576ce5612d00f361062c1a6b2928564317703a05d9ca7cd366f64f62970dcd65dbec
\\x6c4e35d0b1cff61a8574b94228f0ee300d428a8b7402026027f420f252bdfba03cdb60adf2b1cf6607850ad6f33f8a0093d88e3c65b116cebe4c27c5f79e9ff8	\\x72821bcc57f5db9a6a8c2879292d7321ff2f9d1b77e99418b3c3c87a2bfca460	\\x3f21db813f4cb4f71aa416741bfb43af7dd9f689c9ecad76c4df0a63d7eb8a9dc83662cc40944d17eef92be40548bbd3f488ab58bf7758ae41075020ac687a0f
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x717a8922cb5539cfcf990345b5c0195808a63c0d04c388c4946f72d605b8f4dc	\\xd5a926d1816d0b3cf1e7ac84cbacd9c845ebd4989ed26ebcc2c810fface80ed6	\\xd49fcdf5bb7f87eacf790cf19aba85a3de5b9ddf7f6ab673d175e6766b5370f6e64ce45faaa5d228d999c46dfc71682670dfefab9608558a76e06a6ae3b89701	\\x5c925a7e6671c9f6fdb8723ebbb425c6d743dd73e9ac461928e53302ba8187e398de2cc17401160dc0d4d8d91a0648ef534435a8647e703df7a2718e47a254ac	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	payto://x-taler-bank/localhost/testuser-tlrOFF9Q	0	1000000	1601054370000000	1819387171000000
\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	payto://x-taler-bank/localhost/testuser-vvxS70aF	0	1000000	1601054373000000	1819387177000000
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
1	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	2	10	0	payto://x-taler-bank/localhost/testuser-tlrOFF9Q	exchange-account-1	1598635170000000
2	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	4	18	0	payto://x-taler-bank/localhost/testuser-vvxS70aF	exchange-account-1	1598635173000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x9a21b1672c84c30b1ae7e3aaab89fcebcad0f912003bf773ecb223fe3445f0bec9546833f69135849b5f56819ff8acf755f7bf864fa421cb322c36681f03525f	\\x70ec0408bdb4fc9dfddb764988fc519361870d8e1b257110b4ed1669149428fcc2cad887df8ad9926266deec3137d5f565374b7881b83bd80070a892d1ac8845	\\x50937bbb8921d8bae5be5ad06facedc419e8ce939f9539c94a13479780d9322e23e24cba6a68b5fddbab4bebb99af91c7680806ab660dbd6822eec656066c012c5d3837bd6290b92bf125592a10fc02e6ac3f9250aff3ab93f82d00351bc06623769eaa7db403572e2fe18f5507f7e7585d69f0355c5aa4bc436d65514388780	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\xcc52c687f559a36b39277bdbe19c1e5bb6838d3b8db841635199acde539deaac5f29cf5430dfc6c51c51da0ee06c0e6348a563433cf2d88b9994c76181dcab03	1598635171000000	8	5000000
2	\\x98cd325f4ba71d5cdf6810deef123385de39db18a9b5e1630f91d946b94c73cf3c99d9002b43931d18f0f272a43aacf8da91a3ac6b8a6dc28f9effbed42978f9	\\x542a1d8a0f8d1cfe6b90fdd17077ef337ce1944384a93083137fe72fd8ac8fb37b02f701dc3f0fb3800f7915b05831f8cfbcd786e2ef9c668f309adaaf4456e0	\\x4e3a72ec15c9d030b2b8ac869496648743ae5970eb36ed17b583a8ff39eff80a47ed23b0aa25969901827bd930a0a458812c6c8b06d18a7d26a19e6c5373c1d34eb5528b05c1a917b2ea8eb0638524a073eae0067701c3101161c697fbc90bbd7bae494b30407dcac613cc61f273082af024b614c4181c5db99cf647c3ed5246	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\x09edd6b2867379e84a15e4cbc32624f4a8f7aa36d3bd611f7c548075397e3b2e27dcd7d7c8cc7830aaf0c3092dc098289196b4282ba87edc5125eb7a894dfa00	1598635171000000	1	2000000
3	\\x9fcbff6db423f9e7a3afcc81c4976690e256424665b8931c1c345a3f9354e7fa087f88a257c0ad7934f732c5afb55a00970c98bea5cf57238e41c476d3894df6	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x37255711f421e739c2358476d0b64adc30b88e3fe588546e266b29ffbb060273e376f79bb368fdf77dadfd0410dc533efadf7d40a2078f7bbcc1f81c023e897a08f6f90f2d4556d8c0dc97cfb1b986125efd6993ab3a9e16d1c1fa25e6e231c6bbcda4ba5b4d972157918181f69d5b668d835a6db866a14c42dfa0e136393e13	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\xdf256c2222b0f1b0dc6e06ebee0bebebf0704ba5b0859e117650302fbe67a7a1b10b3ad8d42a594c71049d6f4c9db62e61a65e876719904f6a19a5bffeec400e	1598635171000000	0	11000000
4	\\xff46b1b0c9bfe7fdc5ff39e861dd1025dc67ac5bef7dc19a0d6250803a10e62aa4277878d23a98318eb2d577f29e2a6cee00076866c6332c3800175050d9f888	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x6faee8a9850a2bd336b440c85ec3a9521234d4bb3132811ac3a49fa66d2c7cd5576e9b978ea841617fd743f8e153741dc48ab08a88b6b0730bafa09512b94d07174b95d72132fde9efe9138a005b8306069fa36cad0ef1edb81238963e856d66e05525953489a58e0367f26366af017236e41208080af0cf387ade1a0b578a93	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\xecdf3d4a6fde5834dcc1c07998098aa5cc17856ded4d27eb310180ac3b636680858d1b61e54ad486949eb789320d54008f4a96f278a65b80164c123b4c9e9f00	1598635171000000	0	11000000
5	\\xb18ea7552a8a12754616e0adfbf6eb7ec1cb6561f83cfd4af5c69e08294633ada56b2ae88f875c49f3fb7c6c283ae8e04e45fbe8538ef70197dc4e388425c606	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x3ea5420e8eee9fd544fe7c43b9ee5c979fc29eb984a129df1a1aa10e3314dbe048ce6935600a6ba897d25b49f92b1bace0ab37b9b6c630a00a25b28bff78fb14602e3c357779bc6fc9d3269a46a24505619830a84094193f91c62ec95dc33a20e7da2ecb8c9e29316f5c3532bd293217874c6c572ac448abef6da7d26d44b76e	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\x7b09903db2a645de775db90fb09fa129727af4a7818a4fca61e89f96d0381d5179f5d12b92c0083cd0b557df71352e22f3c2de5934e67f0cb16d12e95d4fdf01	1598635171000000	0	11000000
6	\\xb48488a7dce722ab32d3f109d491087bc8d72a040463f65b4e12138def63b4a92570a1540ff9f6082737fa54177208073ca653b05969c1c8b4762cd6dafd5969	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xda7c856f9681a81ce9d7b5a591cb2e7cfc8660d18a043f3639d0286451e152b12747b2656aa87389dd2c67d5f4bd390599c803b47596925dc3b19d9c80dd45f96c1c4be6da19aa307e487b71e2b71fc5f1dac875c557d97d192450f22d90d9882dd3d5cef1d25b94bcdc87719e16272e2317f18ae5ab55735c7d35553a976a13	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\x69f528bff05c10f9f5f45feb14f2c4bfef69b54c290ead729e82cdba4e767cd7ad49e1c07cc4ea32f987b06542b7632e8d8899a081f0ec6719fe93dbe0220301	1598635171000000	0	11000000
7	\\xc46d476b5fdab3d645fdd770180d916577615ac363a5222c6639f650486da36ae6d1c0becef313c0a5382bfbbcc0b6ef512f5fd9e7871161467cc40147e05fe2	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xbaed30747daa4f0b41ab84184d8eac0e7910cbf4034af6b41f0ecdb25dd2c2dbd53bbfe90a0f8944e92338fa1d24639523dbfe867d16a9626409c313a6a704d0604777549ce040dda3a2b4130588d8cd57e0b509deaf0f17370e535decfe70dcf8de6271128af47bb3632f7d4cf5688d5f99c56d8d683052e9a2cc3370b7f637	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\x006dcdd1c3380a98c5287ed448434bd9b55b31bb79343be517fbfe88f15e83c40f445f8d5db0122f500a24c0f887822cac13397f8320890321b7702dfc59c605	1598635171000000	0	11000000
8	\\x09036c32405774f5725401fe0b0a39f0751e10ea776e59caa3881f709604103bd013320f4593df569505374f133402594c559f7d79bcb790c805ad298d811b84	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x8acdaa4351830147e4cde072590effd4eb50ca626477b7e783ba9b80963e93f10489abb856edc5e8030976c7339778fde7d0df96be2e3b1fe5da72ac1adb456421e0b1f0d53ad82989b775a711a8f69bb0edd07d46cd709b4e8cc6c37af82064cdaa4e787a61fe0854b935e212232d0a9990a77fc8b9a572494023a9cd08e454	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\x8d3dc5281ae49c2aae747f6957896b39240521f3862d73333d7ec9dfa4ce5c9c6dea82a4f97acfdfa8cdf36c9dacfad0cc8eac4ceb1dfb42037cd62f043a7b02	1598635171000000	0	11000000
9	\\xa9398d36aade59de23b66701bb527bd79689728326e58d81a9870da0363ccbe5607633bedc75b777991a922ddee0db5e7a08f0178c1e7a80ffef4731be01e7d2	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xce86c96e200fd4d74f18ca1850c68589c9a35bde1bf0c6fede46eecc5a80ab23fd89a0ef7d681e506810a3b94622581bbc98103a2dedfebf38b37e977f3c92d63fb024a12cb46083864899fb062807d6a00b59e5ae3512865bf44d2ea94350def6f9987c3e7927d5fd6f55db08fc627c75704c7887e8e3fd8a14bbc553b3ef20	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\xf3773dde4f7a8095e20445d8307132cd1887f3ecd78b2891ca41e747c302b10f844d7f120fbc837bd893756b754798c65a1685592b5e76e34b609de2dc93a70e	1598635171000000	0	11000000
10	\\x8987a0155d33f0f4a718b1cd2f3b89d772c25115277add5e90eb56c2242af926089076749a71cf4a3a42066200683364a215a210ae99f832e2b4d5aa743cf4a4	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x8ee03e5db29208e02cd8470017484274b481399eaf8edbd04951fd24806392a0a8373046a1a7a2d25abf5feb240f2a92661889b65d62f73888e68ccae71328a6782c294905c3d1d73cd54fb6e34e456cbeef89f081d13a94096b5accab1c189c343ee319cc954c789c94edfaabd0c86bb70ff3dd7d283367eb1de2b1fe398554	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\x9fc3d570c0bb01091b5a07da3e6e41a3fc578bd2674d8e90a98b5ffdbc79fd8bb7a3e33cffc4f0ec75521699bc9b99de3f46e6786ac19b1f2d84d463dfae5b0c	1598635171000000	0	11000000
11	\\x3f069ec71ac01fa7bb98c080b2266e443eab4c8c907f337783a8dd7d8818d570406562c588f96ea7fe10801dcdef9ee8928bbb77e452e123d509f3d50aabe220	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x43215360db4a8cddc7924bca400d9c20789a195f17a3f3332809977c8a8e8ca2f75827b7f0214e361c57316e109bf84e19152c9199e7afa41ebed4520e7ed2efe0663789ce6173c7e404aa832e495add9676f7d2afd673687b26a657f9a05fd6afb89df5cfe2f4ccb515b09017340197912f9e43e9a3e750aaa6b65e82a37ab4	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\xfc8b585926780508a25de9cef799cc8424d49ceb1fa0c4b6d03b5b34978e35fac13fc88867249fec529671a194059c58f5cd4265a584a22757af7bc224358d02	1598635171000000	0	2000000
12	\\xce0e09650f4a3e8fd53a6f9e4e53ff37158aebe9f05717bb2efab672b0daefee877dcd1fbd3aab31801d01fd377f8dd1899f52b6274feacdd260247833e9bb3e	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x774cf1e45cfa9b034c2f50a8b0119e0e2ab0cc345785a3f2c0092072743b2b080844171da01a0dace419bde6b767cf115055539646764b84880d10fb9b227b91b9eab5bad6eb20cbd2b9095a22aacae79d1f120a4aa4027bcc8b15fd675149727d3468c64073cb69a5ac20b802753388b94019fd9e2fe4c3f12fd723875156a3	\\x79b8a715289a130e7d40e666f55c59cd9a50a06889ece7ca45f3aaedd9f31223	\\x8f833453ca349b07ff1d45b2d40e9a6699e954e3b5eb0fe4dee57397e03ab75ad53d3bdaeb32e4c1a72a80fd479d673776f431a29e53c613fff5eab83f7eef0b	1598635171000000	0	2000000
13	\\x4affeec3dab73035ffee29eebff42d5d18559cb0dbf189ff10bb83cfd232c5c14544fbca8925afc4ca1485ce8eb30831e822a8b3049e1b3bc2f9f438dcdc4744	\\x7a03a3ae909f1954488bf99c2c524ef40810ef2baa989a5150de161375a73d1d6a76752732d538de535ceb059d946e6e5565d55951bc31e11d47d51c0a81bcf0	\\xa7782ac348dbef2225af82802c8be3467a5d74a4575edcb2347fba22f8aef1cbd9c971db6cb2efeabc64d38da69bc03835abcbc348ab6d61c4e6f9abfea50415735edd93497c838b9943e3a79637ba4034d81cb5a5d3f307319a7d014f3c8da6108951ba7b9e07b0c791ea76746da07ba15150310fae28efc21aefc5ee9dfbb5	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x617567d1481153b8832f6b613b95b9b26b4162d3da0371d3261ae659624e015891bb72937bedddf8ffcb2c9856a39dd8211903a0363ce01c09eb0d78f194dd06	1598635177000000	10	1000000
14	\\x4794c90285b3993d7aa89a9450f15d68d73c6b3b566d56cffe96a09bc1cde4326ef7ec5a1d98dbbc869549a5acb4bc183e731118d7778ed296b3ddff7b9c6e81	\\x42d0f6a215c182209d58c0d04efae56fdf3a1de408873375550fa84fc5f80622c0a1a01b0f7cc64663001615d304ba884d95511dbab07ec3501f06140205d920	\\x708ac72b0429c7fc0ad5ec3ba23099bbd37cc1a3958e14bd03e8533048b38cd73da965b30d47dcde2fc0e912730758efb6b1455fe05a25d09bb389874c4a13f45e64301a06cdfd87da2c11ba9cb7a1a05c7fdaf1b0ea6b0cadd679ab5df82bd5259fd47cee4035dd035eac05dc7e2ae30c8772febb2b35ea3ba53363d0758724	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x31b4016b2beefa5470ce0e71b708dc8a6014486f456ffe571ab1fdda68bf7eeb8320c4eaf459b1d59d157000e8091bf76ccc1230fdb3c1c1fdeaddaa800d4009	1598635177000000	5	1000000
15	\\x9bc634f3a728e9b082420d13875f4e538ea34a4c432249fa018b117dd89c691c114beb5f6b07d63cb6e83dc2d67e814c31fcaec3f2fd8e6e57f6b8b06b53510d	\\xff092c594bd0d9f73a4f8c6ca6b70f2a6ed62f4e3af63f5b8cefa9a8f42678f989e52e225e5f51c2384761f653e69eb3cee8d2e99412b1c0896c3a5363032ff6	\\x84967f1a7b90398e1b5e95bfc3baf94b1bb6dc4400a8a2185ecddb1397dfed502dd5c9ed93115a68e1e8909c67cce1abe495b54f29629dd76cd5f3284502c57ef5f0ec6a7ea1f6f52c993951ca6934232dcd6132df3bd4a2af58c85cf62ba4d3b10bf0b49cee2a3b91c0aa684a14ba2e8587943ba4141472f8b325059be72b57	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x19a3124dd19a77882fcf13250c2178b01e75f2bac454f3e80177fd8ba5d77878aa136494c8123f8a0affb0cb525e50a26e419b8f7774a08951adfb0bcc8cba06	1598635177000000	2	3000000
16	\\x88dac659ebe643a837d466409ad630606e2e1a7c7d4b57d93b9d53904a7905327892e77c3217997dd36fe95bad5aadce486fb820a198e213e8b09aeb66230fc7	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x886ac95f21c6b8ad72e02d793c093d74ef626bfde749bc10efeabc23fef5f63475a312ad1672a299eba58d7281ecdb9c1bd67b87a6b115f37c2a0f7c971b21b83dfdea5d50220ec45e39c440dc598f70cb3c5400fb08f6d49fd6e3c3d0610e0183e93605ef4f94a2c448d58872ae95f70ba9782e5a210451668ac40feeba99fd	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x8b55cd255317346944ac6d440ccac7ef32544d182e7709711fde2c30874c3ffe27d55fb3f41a77f937d320fce2cf675ab36fa78da2241c3340040a3bdf8f5609	1598635177000000	0	11000000
17	\\x5d8dff36042c220624fa81acfc13eb0fe27642ac54395844052ae3c28f31549d111c14a5e98481ce3e8f419d9296e9b017ba80e9133ae37141d31575c935b855	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x0634e3e853d22ce4e59f1a699220d1e2171315a44af461c085453342dd04f96fe2825776056b0d02899924d40833817f44f9242ecfa50371e020463c45d651c6b1cf6e4db388e1b615b8cd1ea22e5a853d56fbc7d1befc5aca27bf72d379d6b6878efe41e22a034a499325a0f57599b9b1aade8f8a5d05d941390df9c8290da7	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\xc750f6fe6ecbf7a35b8a437c0281ce8ec62ef5a6843843a4fce8a32acff597e6c2540816fce918cba26139119b80fff24cdc428593fdd2986c98ec593862f501	1598635177000000	0	11000000
18	\\x0610a226e1c958dafe63b501151aeca6911b0cf3d3f97e788d3e53b3cea1ac0c6ab3123fc4c47ef7a79a95c71fd3407466058aac9b53fc91d34c999e8c106532	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x6879ba9fba7bed050e111f2552b802a3fce9e50223752816efc4e3b4ef5a4a74a387305e78e882fff6c93d3d328b1dcc25672ef85e08585883d1ca026a3af1dfb3b315f615f7c9d703507745664d6710844b29f9323b3ae93198dd6e36fbb32581fdd3ebfabc79a10afab3c2d6783c0d593183482ea449b13ba71b34dbf7e4d3	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x55697fbf3133309b66194d4da585f86c5dbb8d2526977edf85344470fcd2a7bf201fd0ff5ff6fc8ff7a5aa0bceb879f83923cc0f21e0641a084971470201d80f	1598635177000000	0	11000000
19	\\x967af1d4c15b77cea975ed54aced9d13c407b85aafff2e82deabd1fd84f0743fa7fe73456d8ff5c10ed951ef6a4c212e1e90ddfdf7beb2fb62e0932ef201d2f9	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xbcf0106d7c84b4f57da653dd04f7d600a627f8218d7b8f0bd06ee67d43bf5a34cf3485c152e16772063211f3f999ccb37c88bd82c4a9fb78847fe9ca32d653bac358276a811bdcc589f15a77bd555661a70bfbff6642ace4c3acceeb3da3e43bdfa564749ea18a16abd7b1d2aad242d9098be826d6da91f7c861beaca0ddc598	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x7704ff5409c5e605593202228e16c519a55c5f66a84985fe0afd79c7eedcc00a81f0c6184297aab39d8f63653160b5712344941f57248b038bcabd30a973f103	1598635177000000	0	11000000
20	\\x488253f4a68a66fc044d7989e8be58b21f104566d6b988b4783ef61e1a4d4e7e47cb804442d74c81f79c8af1be3c4af73e6ef39a62db6a8318eeac51a25e5f0f	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\xe7cdd19aaf9cc270cef5d7de66c4c7b7d4c01c22b7f71f0852362a4f543a85cfc3645634ef62f97d5cc0c008e68d9bf076e9b3504d87508b7c38b545e709ac83a7ee691e33626271c98fc329910e2216b650aad42030400f54e9b90540875fc8e1d562ac5d74c87c57f5a16a58d8a46c0fa6d8d0dacc0f6c1ee9fd1d3abd6706	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\xa27b59f04118eea8b2a8db4128065429ed13a80edbc6d9c0f6948ef1f5819bc7f3a031a2052434828f130dd9865fbc721fbc5632c1f1c1117bcbf58da864450e	1598635177000000	0	11000000
21	\\xa81f8e77709256586b4276e0f039b58da77e8dd37f2b8a2e1fb367d3da526db0ee7b874c319dab0abf23397d48f6552715f449ab296adf3eb80e2084c78b0aa3	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x77d77284a53957d420eeb8cd201520460be35ff51134910638f5ce671296aad82290e972e5fc76449dd1fd40a5c8f9dcf606a123aeae9d81b538d373a03cf5ae8cc6eb434ae252c1e18759a1b9492167b91bd8baea25e198f1c47ca4ce095ceba1b5060e9361bcb2a1ff6686a6269d7cde242a2fa9f8efe4a737461e9a6f4471	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\xf08e4f9206f00361b73fb622d914c756cc05733065a6fff27d99a8c9f310a7d2efa2829f42fc61a02195bd6b01dfa1949bd61e737ea6ae8d72b1156bafcd9806	1598635177000000	0	11000000
22	\\x7b261fb9afaa38cf5a98ef9b2184352c263c40a3ed45c54dea4b46fed19aea46905a2d5856b009998589f55c51aa4941840fae5dfc6c851e7243a1768c46c57e	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x5c321ee3a660e94403e53561d41795c675ff843546b106c3bac9440d185f6341a8cc7ccc4992c96e7587a23324ae70071f69004decaf877d4dee32d689b86fc05e5a7b08c39c842382f85c2e62b48476a7333dcd57b268678b7b4d24bcaef816559fa06a7301bfd4f8a3834058e3189f1c51aca95a50ee58c5a570499d66b260	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\xd51cfe39924770f9e4e013a67e7db3c8615f57c02d0d7754bde42b345077190f13dc3024d884bc46d32e47501cff40c3f58f14635d2e920847c5a4d02a0a9903	1598635177000000	0	11000000
23	\\x30002f5ae018bd89a567b4a0c94a80010ad106540d300ebb4e6bff666b5cbb4d212e46b68a0ef2025481c8e0846e9957880d1de9e13f9d161dbf618f13389acb	\\xaf390e9b7133ce0a3d596409e549a864c7f37f651f609aa40f8168ce9cffba705d7342e069479c599cfed0c9fca0e80438a8fd01855edd024310e0892675fa4e	\\x86c8962a7aa9b75edb377ec837370f2129eaaaf2eae7a3be957511539f173c10c66000f5ab2d4db7668065a0674ac2b442ac3f7fc759566978ee27365d0d56b89f9df2d1ef8aaf13d5e04941a31c4bff69a8f129c5a742b058629336e8d0f36ae96ab60778e07dfc59f658cbe6b927c8100c4b2807fb6c59f204c50dd3bb599e	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\xfb311e32eaef9b6894c963339583f6c2fb902ea8e8ffaa3d1b1b5544d2c5b055d3ffb1ec62439a09016bd8a166e523b763f44590fc9dd9c18452bc10ae27cc0f	1598635177000000	0	11000000
24	\\xbf33c5679dd264c25ade564dc819dadbb1366ffcc3dc59d5818f9938450c60d125664312965b67b4e60f04483f7a57b642eb7ce78c79ec7b6d9baf96988d3620	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\xba9c98950632525a782273f482369611a464e7eade33fe8abe15469b26eab566dd0a4c9e117858d05c6ec75e9c93f6e5770963fcf3a28afe67118542ab7948155f3198ef75d7796d4f8429e5f9a9d87b98acbc83505eb7579f6d61dd62e8c973b6c1f3bfaf82563a5b1617c36db30ecb3ab28fea82545bbc353eff631de1d6ee	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x62ed5e462dcd6cc7db9ff4e0d510c01dc0df517699f0d2559fa35e56130ff5d53bac5b70bc804bb49aa15c56fa0bd4d64c60ad8e4f887fdefb8c18aa76a0d502	1598635177000000	0	2000000
25	\\xa2edb2b8da8e5e68fa6beaf0484fbb7790491f9aaf6bf2f3b3097969a128212dab699950d473751d89959cdf8a8f8b458e38de7e32d204ead374ff4eefefd60e	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x35aa3119c6d7778c348c166471ccba1b4076b3354560f80b349b268d1349218d2679209e7908ebddc1dbba305646a9128ccc85585c980155b1f5aaa70e6ff307fb8a2a6c6aca83db43c16f555b047edc14f545a40fe8c969bfcce5e741192ae8ae39669301b663301b804c49d0592f815a4f79f4cab5d0b5120d300adf0bc71a	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x75a05eecb268777ff94bba05ed193dbfb67ca80a21da07bd9ce82eeb61a24f92b0e45da0134a6863d7df160ae461b73d450e2ca828fd2f98b664fd78ead00d0b	1598635177000000	0	2000000
26	\\xf0df75323ce4e1e83446d12386bfa044009107f6ad4ebc3dbaf379b27ec866483e3d3aefcc67edb1effc27e186eb50ec869bb5a8959b2cf3b62b6e05c952f259	\\xacc4865e0cd58b167df1444a0f206a8a18cc177a5916d8f4c74804a341695bfc4263b1f107680c93b9f5c67aa8f49ef9bccf594713f8bb4790112b6da5871b0b	\\x37e3cb79e79c05a8f1ba48c753fd9a0a0395e96697fa69fd66aecaedfec7431e91ecddf60a91f63eaead8d0749e7c6f352be2318c5204b22776384bc59155db964eefc1999e6386e34da175def02bba29979faba4b8b43c2fc049ac326ba79f8eacd2fcee13cd8027f2b63d9c4aeed9490917365775346d6fcfb4d35f459f673	\\x6333556dbfbabe6b9831d6bbb1f1fa824891825a919ab5c9af293d901da98f87	\\x2a2e75dab4efbcf5b9eb4b72c2a7c01310fa1ac9529f7809eb093aef5c00c417ef733093300a2803e95c480559c79bd3527fc1556073d3ee5860ddbcae08a909	1598635177000000	0	2000000
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

SELECT pg_catalog.setval('public.django_migrations_id_seq', 16, true);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 3, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 3, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 2, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 4, true);


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_instances_merchant_serial_seq', 1, true);


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_inventory_product_serial_seq', 1, false);


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 3, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_refund_serial_seq', 1, true);


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tip_pickups_pickup_serial_seq', 1, false);


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tip_reserves_reserve_serial_seq', 1, false);


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tips_tip_serial_seq', 1, false);


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_transfers_credit_serial_seq', 1, false);


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
-- Name: app_banktransaction app_banktransaction_request_uid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_request_uid_key UNIQUE (request_uid);


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
-- Name: auditor_progress_aggregation auditor_progress_aggregation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_aggregation
    ADD CONSTRAINT auditor_progress_aggregation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_coin auditor_progress_coin_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_coin
    ADD CONSTRAINT auditor_progress_coin_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_deposit_confirmation auditor_progress_deposit_confirmation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_deposit_confirmation
    ADD CONSTRAINT auditor_progress_deposit_confirmation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_reserve auditor_progress_reserve_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_reserve
    ADD CONSTRAINT auditor_progress_reserve_pkey PRIMARY KEY (master_pub);


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
-- Name: known_coins known_coins_known_coin_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_known_coin_id_key UNIQUE (known_coin_id);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_key UNIQUE (merchant_serial);


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_payto_uri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_payto_uri_key UNIQUE (merchant_serial, payto_uri);


--
-- Name: merchant_accounts merchant_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_pkey PRIMARY KEY (account_serial);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_h_contract_terms_key UNIQUE (merchant_serial, h_contract_terms);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_credit_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_credit_serial_key UNIQUE (deposit_serial, credit_serial);


--
-- Name: merchant_deposits merchant_deposits_order_serial_coin_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_coin_pub_key UNIQUE (order_serial, coin_pub);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (deposit_serial);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_key_exchange_pub_start_date_maste_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_key_exchange_pub_start_date_maste_key UNIQUE (exchange_pub, start_date, master_pub);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_keys_pkey PRIMARY KEY (signkey_serial);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_master_pub_h_wire_method_start__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_master_pub_h_wire_method_start__key UNIQUE (master_pub, h_wire_method, start_date);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_pkey PRIMARY KEY (wirefee_serial);


--
-- Name: merchant_instances merchant_instances_merchant_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_id_key UNIQUE (merchant_id);


--
-- Name: merchant_instances merchant_instances_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_pub_key UNIQUE (merchant_pub);


--
-- Name: merchant_instances merchant_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_product_id_key UNIQUE (merchant_serial, product_id);


--
-- Name: merchant_inventory merchant_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_pkey PRIMARY KEY (product_serial);


--
-- Name: merchant_keys merchant_keys_merchant_priv_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_priv_key UNIQUE (merchant_priv);


--
-- Name: merchant_keys merchant_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_orders merchant_orders_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_refund_proofs merchant_refund_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_refunds merchant_refunds_order_serial_coin_pub_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_coin_pub_rtransaction_id_key UNIQUE (order_serial, coin_pub, rtransaction_id);


--
-- Name: merchant_refunds merchant_refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pkey PRIMARY KEY (pickup_serial, coin_offset);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pickup_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pickup_id_key UNIQUE (pickup_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_serial);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_priv_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_priv_key UNIQUE (reserve_priv);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_key UNIQUE (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_reserve_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_reserve_pub_key UNIQUE (reserve_pub);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_serial);


--
-- Name: merchant_tips merchant_tips_tip_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_tip_id_key UNIQUE (tip_id);


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_key UNIQUE (deposit_serial);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfers merchant_transfers_wtid_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_wtid_exchange_url_key UNIQUE (wtid, exchange_url);


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
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (rc, freshcoin_index);


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
-- Name: wire_auditor_account_progress wire_auditor_account_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_account_progress
    ADD CONSTRAINT wire_auditor_account_progress_pkey PRIMARY KEY (master_pub, account_name);


--
-- Name: wire_auditor_progress wire_auditor_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_progress
    ADD CONSTRAINT wire_auditor_progress_pkey PRIMARY KEY (master_pub);


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
-- Name: INDEX aggregation_tracking_wtid_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.aggregation_tracking_wtid_index IS 'for lookup_transactions';


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
-- Name: app_banktransaction_request_uid_b7d06af5_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_request_uid_b7d06af5_like ON public.app_banktransaction USING btree (request_uid varchar_pattern_ops);


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
-- Name: INDEX deposits_coin_pub_merchant_contract_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_coin_pub_merchant_contract_index IS 'for deposits_get_ready';


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (tiny, done, wire_deadline, refund_deadline);


--
-- Name: deposits_iterate_matching_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_iterate_matching_index ON public.deposits USING btree (merchant_pub, h_wire, done, wire_deadline);


--
-- Name: INDEX deposits_iterate_matching_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_iterate_matching_index IS 'for deposits_iterate_matching';


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
-- Name: merchant_contract_terms_by_merchant_and_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_expiration ON public.merchant_contract_terms USING btree (merchant_serial, pay_deadline);


--
-- Name: merchant_contract_terms_by_merchant_and_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_payment ON public.merchant_contract_terms USING btree (merchant_serial, paid);


--
-- Name: merchant_contract_terms_by_merchant_session_and_fulfillment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_session_and_fulfillment ON public.merchant_contract_terms USING btree (merchant_serial, fulfillment_url, session_id);


--
-- Name: merchant_inventory_locks_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_expiration ON public.merchant_inventory_locks USING btree (expiration);


--
-- Name: merchant_inventory_locks_by_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_uuid ON public.merchant_inventory_locks USING btree (lock_uuid);


--
-- Name: merchant_orders_by_creation_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_by_creation_time ON public.merchant_orders USING btree (creation_time);


--
-- Name: merchant_orders_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_by_expiration ON public.merchant_orders USING btree (pay_deadline);


--
-- Name: merchant_orders_locks_by_order_and_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_locks_by_order_and_product ON public.merchant_order_locks USING btree (order_serial, product_serial);


--
-- Name: merchant_refunds_by_coin_and_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_refunds_by_coin_and_order ON public.merchant_refunds USING btree (coin_pub, order_serial);


--
-- Name: merchant_tip_reserves_by_exchange_balance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_exchange_balance ON public.merchant_tip_reserves USING btree (exchange_initial_balance_val, exchange_initial_balance_frac);


--
-- Name: merchant_tip_reserves_by_merchant_serial_and_creation_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_merchant_serial_and_creation_time ON public.merchant_tip_reserves USING btree (merchant_serial, creation_time);


--
-- Name: merchant_tip_reserves_by_reserve_pub_and_merchant_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_reserve_pub_and_merchant_serial ON public.merchant_tip_reserves USING btree (reserve_pub, merchant_serial, creation_time);


--
-- Name: merchant_tips_by_pickup_and_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tips_by_pickup_and_expiration ON public.merchant_tips USING btree (was_picked_up, expiration);


--
-- Name: merchant_transfers_by_credit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_credit ON public.merchant_transfer_to_coin USING btree (credit_serial);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


--
-- Name: INDEX prepare_iteration_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prepare_iteration_index IS 'for wire_prepare_data_get and gc_prewire';


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
-- Name: INDEX refresh_transfer_keys_coin_tpub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.refresh_transfer_keys_coin_tpub IS 'for get_link (unsure if this helps or hurts for performance as there should be very few transfer public keys per rc, but at least in theory this helps the ORDER BY clause)';


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
-- Name: INDEX reserves_expiration_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_expiration_index IS 'used in get_expired_reserves';


--
-- Name: reserves_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_gc_index ON public.reserves USING btree (gc_date);


--
-- Name: INDEX reserves_gc_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_gc_index IS 'for reserve garbage collection';


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
-- Name: INDEX reserves_out_reserve_pub_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_out_reserve_pub_index IS 'for get_reserves_out';


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
-- Name: merchant_accounts merchant_accounts_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES public.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_inventory_locks merchant_inventory_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory_locks
    ADD CONSTRAINT merchant_inventory_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES public.merchant_inventory(product_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_keys merchant_keys_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_orders(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES public.merchant_inventory(product_serial);


--
-- Name: merchant_orders merchant_orders_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_refund_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_refund_serial_fkey FOREIGN KEY (refund_serial) REFERENCES public.merchant_refunds(refund_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_refunds merchant_refunds_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pickup_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pickup_serial_fkey FOREIGN KEY (pickup_serial) REFERENCES public.merchant_tip_pickups(pickup_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_serial_fkey FOREIGN KEY (tip_serial) REFERENCES public.merchant_tips(tip_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES public.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserves merchant_tip_reserves_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_tips merchant_tips_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES public.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES public.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfers merchant_transfers_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


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

