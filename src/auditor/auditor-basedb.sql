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
-- Name: TABLE known_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


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
exchange-0001	2020-03-13 19:35:27.122355+01	grothoff	{}	{}
auditor-0001	2020-03-13 19:35:34.389994+01	grothoff	{}	{}
merchant-0001	2020-03-13 19:35:37.767017+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-03-13 19:35:41.187705+01	f	5e24163f-5331-4629-87e8-40fb8715a0c2	11	1
2	TESTKUDOS:10	HG3AD5KPDE27RB7A2Y5WZK9K6GTX998K05YZ6C4DEC2RRR1J3PT0	2020-03-13 19:35:41.278467+01	f	9f36a88e-3b60-4e3a-9eba-e990fc231631	2	11
3	TESTKUDOS:100	Joining bonus	2020-03-13 19:35:43.794597+01	f	ad97b48b-6d1c-4634-9b43-7a130f35dc82	12	1
4	TESTKUDOS:18	RT4Y2C6W4X7SX0Z064TRQ4H2ZZH1GD5E7WWZHMJQ9WM5F5KGWQ40	2020-03-13 19:35:43.881571+01	f	b0223db0-35f9-4a33-958c-321d1f96deb4	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
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
\\xa96d1614b62d8a838b7ebee977db7f3d3b7c3630c8d6aee9c96e848c5b4f72200672fb3ffe229bb3c0ca63fda38757550f42170cf04fa8c647342d4d82abee67	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584124527000000	1584729327000000	1647196527000000	1678732527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb45dd1f40b446b36785e2178930240f1407da65a34dc2f4c39b527838e014ae2f5a5249a5db28ab0a64c1e37608fc7345508132dff6c135fd8c1bf651248dac	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584729027000000	1585333827000000	1647801027000000	1679337027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff062da42a2041b151a9a116837e70a11be427656d0e79ee440386edaa31181931fcc88667cbcfd1a47dcc382e8f770d897807ec2b0be258ca061eed3bee85ee	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585333527000000	1585938327000000	1648405527000000	1679941527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9cb0ae54f9c698ebd27e4de1c80894794ba23e6a96651809bd62aaf4b09fc051248a210d11f632c21a9bf60eb8a81bcee79dbdf8827a522774beabb2e17f26ba	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585938027000000	1586542827000000	1649010027000000	1680546027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x73cc45fec9836dec65d8c0d9b9e0bed91b00a855f640a7ba5710ccf9f83b592660711f7fd27ad73cbe9b36ac8c934b3cf8dedb73a816a2e99338a600d171a09a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1586542527000000	1587147327000000	1649614527000000	1681150527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc17a45b79c699f6706a467b28baf97c8634266ce019fefef7f949690a6630f75c34a1dcf8793ecdb44eeca1ec4b4a599ef40d8bc93bf98ec92dbde5a02b4208d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587147027000000	1587751827000000	1650219027000000	1681755027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xec3d9d60b61b86944f9200d17e51f16f8a3da2f549078d93fc666ac749413eed8b8c81c933f4571cc6f5133125df4ca44d4f0b2c9df66b695f61c52ecae31b72	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587751527000000	1588356327000000	1650823527000000	1682359527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e7a9699d1a4641f86dc5ccdd6905dda424bc97d25763b4f84a96094b549c657287dfb95a9a3bb8f91dba3c8e60debdd67caa97bc16fbc7c649981a935d60834	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588356027000000	1588960827000000	1651428027000000	1682964027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xec63e694c0183b24220e53ecc1b0edad4b82c6603faefd6e22973ba7ef86630f14c53355c235a51c3a6ad91ce2d58e3b30a8dbde6a1608b432f4daf3722ab05c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588960527000000	1589565327000000	1652032527000000	1683568527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0722edfc399662ca7faffec24979257e075cd88a5a87f3fe146aaab3edd24553e8061fc50edb8976dcec14b7084b0fea412031c4ac384f42929c8751725c7730	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1589565027000000	1590169827000000	1652637027000000	1684173027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa028ba1a8afd9a5617714699a85418c8374ce17bb6772c38a34a1f2291c987fa27f9153d24d2dfdcfa88fbd8cee27fd2b6ab2695393faa6e0c306899fcf8779	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590169527000000	1590774327000000	1653241527000000	1684777527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb09acb2b6c52f00344caa32cf7c22a4096f6f9f0e49c2e5185f81bca35cc3ff0342f3c592f4c3eb98f58425bf14c6a46b19f7c7e8e2d4c82bb05818f8cd72b0e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590774027000000	1591378827000000	1653846027000000	1685382027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f86f18e72a6fea2e535ef6ab4ab220354de7513b2178410bd107332d913f609908f7dce6525617cca313271245f74a52eef4910234425a276fa3640ed585361	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591378527000000	1591983327000000	1654450527000000	1685986527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6fbada069741a8cf3c0a0b0af5e673757cd38cc2b09c79c40e2fde238d41c934b97ced29394675359b44ebb9fc97e6808c9c4538b510d5df6e304c2cdf4d7eaf	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591983027000000	1592587827000000	1655055027000000	1686591027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9e17b1050c939d2dfa1e1cf820114c83a9d368c9b9273d853e29525467fd8561edcda45870c0f8364fc4242b2ba94eaf5729e316f4e9c2f4bc45f4312c08f5c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1592587527000000	1593192327000000	1655659527000000	1687195527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7683d3b5ba7e7ebc47c07fa128a5dbd2f165d74c8ce40db5cbdfc5c4c4c2f2929be11b643153d2359bb2422ed50e5c6341f03f770ffd83118f5a4711e15cf61	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593192027000000	1593796827000000	1656264027000000	1687800027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd129a8de5bcb9a417ee3384450490aadc6e96d4c23a011412abc9914135b15c8af62b3efe2fc1bffb38fe665bf006e8c818b795ef1c5c0d2f8e9a5544abfe7f	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593796527000000	1594401327000000	1656868527000000	1688404527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a52bfde8f794fc3ebe4c5041fa82a3a188dc7e80f30e3920e89728af6aa65e63b8832b14c346898a64ef0c265b39a13a296e8831774e60f4a9b955903d00955	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1594401027000000	1595005827000000	1657473027000000	1689009027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53f73b67bdd0d71a3272f4f75837b1b78d8c9b7d862005b247977f6bc8d632112cf09f2755b805efaf06d1f09f10bba629a03c0f9520be15808b8b982d040b6e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595005527000000	1595610327000000	1658077527000000	1689613527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x05e4e536ac90d31d6d00eab4e4fe65d0ef4a104164d9d4df273161040c182cd71cdc9e1a589f0ea506259f02331e96d718cf9fdb32de1a0796e3fddf75f05f7e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595610027000000	1596214827000000	1658682027000000	1690218027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x43d57d44225a1fe965beec829a7cd3d8d7bcd486a8cee33710595f5e89b8ca8b6c71072c3c6e7a58d3a99e52da89f3d1c718b9b8107d8f297ca8959953b03b6d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596214527000000	1596819327000000	1659286527000000	1690822527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5dd555b83b7c8249fe58aee8a1aa26b6abec1bb646c08468bbb5dd8bad9631cbea25955cd74f260593e0d8677911bc956e7ffd291da0922caed2fe7f3ce900c7	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596819027000000	1597423827000000	1659891027000000	1691427027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5fdea21d65de4a8375054fa9aee4ffb76cd37732ae433536fc04e8e0605f68979f0aa816d8c1c6bd5ca9cc7eba9e86f2f6a76b56d2b246af7de357be35ca8b6	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1597423527000000	1598028327000000	1660495527000000	1692031527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3700f86633a517f3d477814161e960d675e76fbdc106d38cc223593a757fdf7ddab5ece025c0ca61b8d5bb87fc8de6cce0806edaf64c0e7822b3eb589dfbd220	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598028027000000	1598632827000000	1661100027000000	1692636027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77aba628bce3de6e7d1f56641a5b8f610d075503ca1825e6bccee78917b29b05ae675d54a5bd45a2e36aae4abc7eca6c2dcd09d885112d83d886bc3f58b0eee1	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598632527000000	1599237327000000	1661704527000000	1693240527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d6e598e2b72549beadc9fc123231f322a589282d7058bb2b5e7392e7c2bba6c326d964acdccde37f906d5e27a11f0336792d0782132d41613f6e39ab7ee3404	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599237027000000	1599841827000000	1662309027000000	1693845027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98a9c9651e6a672fcbae9a1ebdeb1a98b6aaf91b2fbf22274cd02411e8b18af0b38d2883785bbfd7e8aad783142a1218122bf52354cb4f0c1e6cc7e3c9588697	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599841527000000	1600446327000000	1662913527000000	1694449527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0691299e9a38d9baa96dfc372381c15795e578416f4661251ea0a48e93d51dd3e7e107290e867903defd1b631a287316e7ff02c0a8a06f56bb1a3ee16c45c1db	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1600446027000000	1601050827000000	1663518027000000	1695054027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b59a5bd355465d9bd76bcd0b3fba924d23e4991c8173bf4c2d659ea7456f92eeed8d9f98a6dac8b3e5f99fcb15f17a1b7f3a9a9251ce5bd4f3b15db2f67150c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601050527000000	1601655327000000	1664122527000000	1695658527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c58c604e312745957a04c19efd9a1a01f6a02971586571b7149f9cc96aad9acd5768c15110e73004a0071a2e654d38e095e5f0c8e8e4672af83fb3fa9735934	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601655027000000	1602259827000000	1664727027000000	1696263027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d5ddafe2829d944ef1dce238b01206c4bed413cb867e45fd9daf153ab91a504c003d00a8f4fd209664bb7f62f031dc0e67d7645c3a703e093abff98175d723f	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602259527000000	1602864327000000	1665331527000000	1696867527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x65cb9f2c483b19fab8014736451988c5c33285933f8dc64ff3cf90835f2653cb7041712e518839354d5485e97ef4838c4e8e5d98b67dd6f4e77ea84a9f26f683	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602864027000000	1603468827000000	1665936027000000	1697472027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x209f39ddd8564e30ef4957b75ab3caceef0c1525f7ebdfcba8e241c2b43cee69a1aa4c9efa26c46a1c0f674e36711873ce2b7d8301cec150d8673432c3d81ad7	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1603468527000000	1604073327000000	1666540527000000	1698076527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe2557e383c1c3c019681c2521d415a758f1becb629a3a75fd9dc212f0f2e802aee81e71db725f0f9913bea0f913978bd7d238558712aa957d80c4e1673292b13	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584124527000000	1584729327000000	1647196527000000	1678732527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x89d632dde6b67bcd5496434399229c75e8925653c5c952393a61131b03f941ba1ec3de4e210861a730b85fb87cdcd7ccabc26317cdcb823f83d027ba8777324a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584729027000000	1585333827000000	1647801027000000	1679337027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf5ec27a33faef3b0da60b8403beaebe30e385c3bbb0849372b164d26b8c73265914f804eabffb948646a8ee0ff18ac8681b5014adb983dbc692a4406791ec1f2	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585333527000000	1585938327000000	1648405527000000	1679941527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x736fae372040bd5d2d9c97e454efa630d0ca6a01a277602638c998af302418885e017148f4ea7cbb144a0c29a463c8c922f3c527f0ff63add38f64292c69f5a4	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585938027000000	1586542827000000	1649010027000000	1680546027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4faae841605109e2e8f43768baf54551b8d2ac29b16f601799c2ee260b9bcad53c8b4e5ab2352bbc1b12bc28c53df0e3ea355d61227430edb4644cdc4546907d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1586542527000000	1587147327000000	1649614527000000	1681150527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6848b532bbfefccfbe4fcff80fe6688ce482d891673965e64c99c2b363ad9d30177f1ef45d2abb9c947577f8e23e3aec2bc2c2e38d113acc13eb6b808fa5bb1b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587147027000000	1587751827000000	1650219027000000	1681755027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x198bd5a41044f28606f048ce59414508461044ba74ba6abd7555bb91c78b750d594519eac6ade5e9f6a25cee0c3c0a1a6c6d3e7c42d529e68478802ca2c0e3ef	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587751527000000	1588356327000000	1650823527000000	1682359527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb2e527f7d2180fa33a36f84d4a20d7d1a7a8f3d816634ea9a568ef8a1ff446facf89ab5bd01a585c8bb40c6088dd255f5e6bc0581d87b1bbed0194fc3d1f3cfe	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588356027000000	1588960827000000	1651428027000000	1682964027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x294fdd3e4e9176cfa35ad3f56da2f9648cb1d0a682e6b72e195fe46d9c792238d9dc663e30bff65c08cbce3caabcb9a8211e3888a5e5347dd50c6f05fc3afbc1	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588960527000000	1589565327000000	1652032527000000	1683568527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x678dd52ec4a7d4b4c2106cd3d83e14e70155bdb22497ccf200b25451c65e62062f684bb0acd1494bc7281c4e73f7539976f757456452831d6ff1a4438f87aded	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1589565027000000	1590169827000000	1652637027000000	1684173027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3a98d8ef0e0a1e94e4703d14db2fdf6af57e8ccb0aceb3bd1aaecf747a45ff42fbbc82cfd972e863d7276f35b9b0bf5b1045a2055a4447f1b2de890459122718	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590169527000000	1590774327000000	1653241527000000	1684777527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0f4c04c2c2ac57229cca630b90f8e1cae021a5fe6887d0e641746cbb6afb7a4b4463feb403c307625a772cb9e144d941f9a2a5354418cf649ae23012cf9deeb7	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590774027000000	1591378827000000	1653846027000000	1685382027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2c8e413cd938e04f542bc9244698a4846cae350be51a4b96c23dd62328131d9f52c55d59461946268e76de4b73f3343797905bbc79e43639e911c1dd776062e8	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591378527000000	1591983327000000	1654450527000000	1685986527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8132c0e0e925daf9425ffc2a1f19b014d3e5eaaab3f0dee040a88a8fe49e796ff7086f55e451cc3f89f4db290f650b15541ab9433f6748bd61740d997a173e87	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591983027000000	1592587827000000	1655055027000000	1686591027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xad283ca32be3327f8be03fae2f76639bcc280f2148545efdbde8f26a4d78b67c5142d3ca173bf3ff8bcd8d0270002b4eb6510f0d8bc6aa047409dfdc2320cffe	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1592587527000000	1593192327000000	1655659527000000	1687195527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7bdcd195530ada526322c2b2ef1146ec3ba338b9d4e24c00454d97f805e46535512248f8d80ff821673f46464f9a95867f03d8c63d269582609b9599d46bbe00	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593192027000000	1593796827000000	1656264027000000	1687800027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x08410df47dc40825ad229bb0cc18c2ff1c378db2f44d688f808b15156935c759c3786d00f587d53826bc5981eec8d0714bf6bae4ebd6d5f4e46c9bfdd37e086c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593796527000000	1594401327000000	1656868527000000	1688404527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3b422076450dd388ec63cd304e3efe3fd8e63711d3b53b78b9edeae4f75aaae1d06fcdbd807507ee6e47ac0bc5a71d61dc2b321e211077bd9f845e5974cac6a3	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1594401027000000	1595005827000000	1657473027000000	1689009027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x310e1d0c6ac2a8aec9f821935d6c3fa9cc881043931d1c151401f0ad2e7a9c210768bea8b5939a3236f99a62a140f6055d1b74967143eee4f072f6bc9c247016	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595005527000000	1595610327000000	1658077527000000	1689613527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xea393ee266fe343fef6461d76325f099fb0c365ce0518cf1dc8150bcbbd7f3b1cb2418d9e4855dbe9b35d0647a31141a181dec55c80b7b3ad2d93ef4703ed749	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595610027000000	1596214827000000	1658682027000000	1690218027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa724adab3e64fd5d7710f9620815d6ef7d631382af62d43759103ef6a9b689c66cd38fd669fda2dbd796d8221e06f91868556bbdecff3b356d52c9df988d313b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596214527000000	1596819327000000	1659286527000000	1690822527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7c2400b641bc05f2d2be2bfd2a5d0af2a811a8b3ae6c66ef760d47c250e9020460d28de2872c17cfd6b1016ad6a6e28c62b5b672f46ab9355af0ec149f7e9aed	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596819027000000	1597423827000000	1659891027000000	1691427027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xddcbcd710d062c8bf0493e790bc001768d60d000cc064b33ddbfd4bc71417c7657953766c55f33247acb905ea1ab69656d8cf78e384e4f0510ab0d27fc69f0e9	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1597423527000000	1598028327000000	1660495527000000	1692031527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xffefe5a4137034b1f91b954e42777fbdd0a7464b37e83335e1a6d0ae19a05879f1fdae0d375befbcf381ab5378cd514945b27a5e83d269b8737000d302f61bdb	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598028027000000	1598632827000000	1661100027000000	1692636027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x63e58e0daf3f9a2676fb1413859d980b07ae3731edea601ef941ed68a24d941937785701009fdf58db7ea87344afae343070d34e54ed403e094fd3df691f3d47	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598632527000000	1599237327000000	1661704527000000	1693240527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa0741392a26e9f5d7780e740ed710ad8407a71dff1c23fd0059a6b759e8bbee8eb6962b67cba3915178e5640d68177e8b8de599f249656b98d3e1caa3875dfcd	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599237027000000	1599841827000000	1662309027000000	1693845027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5b797546d8bbf3313e548256097eca0000f18e136faa339a89c81f5e9bed6145caf876b61d9613a1d2f2aaadf8926576e491c6224df6e8b87b5e83272fbc70e6	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599841527000000	1600446327000000	1662913527000000	1694449527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6a09bde9661b00281d3ce948af500471cd71903b50b11eeed970a6e00144909ce5513cddc4ddf7a5cdac6211aceaabca7b17595508ed5458eaa907943802600e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1600446027000000	1601050827000000	1663518027000000	1695054027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9cecf3582ee4c71272074227936e90e689a8296bad1b2524e0410882454299f6ba39743b80bb714d1b5ac8e765ed80b0103bfcefdb884bad6866f7aa45d06b17	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601050527000000	1601655327000000	1664122527000000	1695658527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd2e957c9d5b7a9815cd99e61761688441323293483c12903efa2329e5bfcdb8db2ae0dcedf0f773920525bcbec0660a47bf7cc5fe8321f7a0185f49c52c2ed49	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601655027000000	1602259827000000	1664727027000000	1696263027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x58de8f1a094ef83e0c2210ebbfaef4e4f6df9f6591d15b4d77266f264cc40c9d347ab3f462ea31528c995875cc0b3f8de66966128dde4d6107714a820644ba7e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602259527000000	1602864327000000	1665331527000000	1696867527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x63ddd1b71fac8f9dc59893a23d001670c1db9840a24dbbf1e6b2bb490864070fa60f37766e45b02f56f7d558f4e694ef57743ac6b2477f7ba5e1407a001ad465	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602864027000000	1603468827000000	1665936027000000	1697472027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc1df649c58ee62c06ee0db1d4bc3aaf83c76b5fb180b52d2b57249478d5900b845050eca79bc7767d14993c58bc4730f9e5dfe8f793fa404a9bcba5ac79d40c1	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1603468527000000	1604073327000000	1666540527000000	1698076527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa6576c13e5143d56edc29a8c4917121a1c3917f3436c26f3349de6c226bb96bce029469a4b627b504a3f17d70c4ad7e6c015b4873e98c87238c9b824018f461b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584124527000000	1584729327000000	1647196527000000	1678732527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddc88ee65b9d5ffc9787a9154065eae790812d277640692b9de92d2ccbe417d95f649de7208d63a5b8dfbe9df3215c1c61862c14863168507078619eb14921a2	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584729027000000	1585333827000000	1647801027000000	1679337027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca5e89c144df5f82fac1329f3c86754b0e0a105f7cf27eb9412d20cb48db7eeed585252b6a25a99c85ffaea656af87336881999a8035b50d7917c12f6a9b90c6	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585333527000000	1585938327000000	1648405527000000	1679941527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb13be79e272cf95452c46fdc192d07d16f24c0c0d9638bf2ba7814146c195272bd5f6a308e5c53460c4e5adc12c8116170bef14a542ceae0379dd0862008d868	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585938027000000	1586542827000000	1649010027000000	1680546027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19d70de23bde1e436057b52e826f99bfa483b84ce088c89daa91a32eab5edd2edfa2aafa1714e1cddfc6faf8667574e76bf139865720b73ac9d6d4e6cc04c5e0	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1586542527000000	1587147327000000	1649614527000000	1681150527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b6569762ff8a11fe0faa5b32c40ac6c89dc20727a792995c3edb02d0291e5489c43b196f5201c04b5cc6ca3e5e165e796e1e6f3b7a4d1a0f523b5dafe9df2af	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587147027000000	1587751827000000	1650219027000000	1681755027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3c8b25ef11b8de1f79bd681cb42c8c77abe4b5c446173dff907bd71e0b869c456fcb6f502ec91599746ee4a8c2fc8b8118d8a09017b09cc12b1af700a296750	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587751527000000	1588356327000000	1650823527000000	1682359527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7fa7641cf151fc60d8c54c9b5d5df0d654e2f23680d45b1b143b83c202eaa3a99f9b2e61bafded652492052f8748394efe5a0fc800be252a47b2ee9b2fbf947f	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588356027000000	1588960827000000	1651428027000000	1682964027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa58ee51ad47a34c26d50a4c911040fd2991f2bc728d24bde2543bf4d26bcdca6f48dbe2a98cf874fee4064fd3d47f0d89a6dda4bbd44af9d5ee6dbbf4cb17fba	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588960527000000	1589565327000000	1652032527000000	1683568527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1add4a9cf6ac98d872cbea41c8decfd34cb0c21ac0c9c5b864332733396093486204eefac6fa25f5581fa2fbc973464324ebf00cf05ab5e74d768cc2ef74945e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1589565027000000	1590169827000000	1652637027000000	1684173027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1c70468e1436c7742a22cb3fc1ff0e69a5549987dec101c448283338d35ecaf15b09f447d092950500b47c501c15ba33dcfedbfc366c370728175c65c9df943	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590169527000000	1590774327000000	1653241527000000	1684777527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc651df9bb6f5ecc41fb359bb0c4adbdb269da8ae2538c6a5b899c8ee1061767ffce29ff897ef1384fcacbc51301a64eb2720c796cdb1c809e7ec2605589b885	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590774027000000	1591378827000000	1653846027000000	1685382027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa6e3c35c16c059871ed81afea3328e8c971332ce564e7c13baee8869242f512d8bcc9ffb3ea9fa2c3f87137ef729aae47e145f1518fc3658440a5dc910e5566	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591378527000000	1591983327000000	1654450527000000	1685986527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xce1f1c37056c63bb7f60accd955972c2193d48abe8db245a2b5698582c75f24c9c5ecade1877d2056c0ade564342626091500c990144a32fc20876ba1a9ca534	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591983027000000	1592587827000000	1655055027000000	1686591027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x47de80930d0b79ef1bba526d1eb8e0d9c97e06e21b4a55fc6416b550d8b243b725e5debb43921d222521f9918694573c4489dfb50c3710652e318cbef5cee304	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1592587527000000	1593192327000000	1655659527000000	1687195527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa14dfdb030aa65c85f65af028728f3ff1de427cdf8d44fcfd07e688080c38ae8cef65442f6a5aa861cc7fdc10e3cf5688eebd77433a1356f5564b90d9cb0d91e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593192027000000	1593796827000000	1656264027000000	1687800027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c30c000ea26545d5dd5df051cc7d9d45c430d5d63678a04e3d562ab68af69296f7c5dcc6a8caed61498a63e0a9182ee2192afde46115b52775d25577d7ca8c0	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593796527000000	1594401327000000	1656868527000000	1688404527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb9a25d8a80d60b3431403195f50f71b28bf1fdb608ba2ecad24b6e7a02dd3b8d12b26eb4cf840c98bbc1d629b3b12853d91837f410990701007b7901ab49900	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1594401027000000	1595005827000000	1657473027000000	1689009027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x831f49572c67918fa6d843a59a6112a90ac74f72ad70ab5abff60fdad26c2052d34a973f6f2529aa3e7d8d7c579dc77ea40b4c1c012250869290da3dd0323311	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595005527000000	1595610327000000	1658077527000000	1689613527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e1b7933018618a7fed22ce2f841214c4587a7fa2a7d2a6f6e27aab525f8ab25a53ba878dc62c2b9d7722594e2330621962467d268770361ff277fbaafc89060	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595610027000000	1596214827000000	1658682027000000	1690218027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x467df6abe3205708661cb892fd45bd4a024542d59e2d5a4488122f2dd685c475d9426e23285f9b868c163fe52be65d42f9f963f787014b60fe091ea8914fef30	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596214527000000	1596819327000000	1659286527000000	1690822527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x27f580f5add0226f18eb385d280be808a59a0872d1da41b054b1dbb822516c5f82925d607aeaecd6f10451dc6596884715c425c71be7f2f769d1bd394e308296	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596819027000000	1597423827000000	1659891027000000	1691427027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf072c12ceeef24628f4543557914e0e6fd8d2386da229ca52793772ec7e00e8a0cf84f1bd96dd9b6e535ba0890558b64ee00ad0862e6e077be545b22dbd76ea5	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1597423527000000	1598028327000000	1660495527000000	1692031527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdff34e92c071b4022a12c51446a58ce0de6facb1a5f86eaedf30e6965ad8db665ce1556286d1a554e36d67af5079ef22f90f21a21a09df2ae8f7c5d7f436fd42	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598028027000000	1598632827000000	1661100027000000	1692636027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x091712f282d74bb33f903c23a11315c414a2e661131632bf49a7cc841bc8ae65f9d10a5f6144557beb1fbbfe00785a00df098296360469f048a906667c289770	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598632527000000	1599237327000000	1661704527000000	1693240527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c0e2f8254fcf5ee3ee7cff5baa5dc782565af7615117a4247486f87f48529c407acbd078df27b266b28b157eabafb108aec4d15706c9b704dc8e1b5e0672c64	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599237027000000	1599841827000000	1662309027000000	1693845027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17edfe6a00c0f73775d2b1cbcce3cf2758e45d9f12a889f0353d57ca71fdc50ef8b989354967d3e3a4a19d561097b233a0d172d3d479c34ab741b4fa15f8c4eb	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599841527000000	1600446327000000	1662913527000000	1694449527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf1b4524f05edeb81b92c8a1d179ff9dd58a7ae91204e667f5e06258a962ae14f9cdc293689569db1cc38b882a0a2471b52164ef4a9267db30a928ff5b4a4340e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1600446027000000	1601050827000000	1663518027000000	1695054027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5540668fab2a27f8ad6bef45f727a180a01aabd28c042fd6189608ccb636188bf7b24b3e5dcf16bfcf49588dfc0131c028a2745ad31a988b14d95ea47dbd2de	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601050527000000	1601655327000000	1664122527000000	1695658527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcf5c6d6dca58e3ab6a1304c9f088bcd8dca056bd33448029dfaaf28aac36bd7cef9e1f83a67d10fab0fcd9e81d7432ea8cc110dae534e38a95c4c1db30b87e2e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601655027000000	1602259827000000	1664727027000000	1696263027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8a7c34086b833ce093ccb1b91802fe2e9f79f23860e91ba3036d7d68c5a111789480b749f1100451f971556598adc53cd6bc5e22988cd0aaa4c001147f88322	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602259527000000	1602864327000000	1665331527000000	1696867527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c50cea43b2a9d85633181c8ef2782c2a796ab638122d9604738fa8478aaa5e0e1199a9c587a2d3d15de108dda8047f4e1b4155e09c8c0460cbeb22bbfdcec85	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602864027000000	1603468827000000	1665936027000000	1697472027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ff91d9ef771cf4c9089ef1a742292bd887eae63c50ec766d3c27571bf92618ee49267e72581f097a1740e8a2a67d63f59685be0a44d2a7bb0f91aeec4b9f4e9	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1603468527000000	1604073327000000	1666540527000000	1698076527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x597a8051c87010b154a8dfa6643279b0c166b51539c69b9cb19af986ab521ed59877b3868c0e56aac00ebbd6f1f3036a6b667403fc032e32b5589ddb9c257b8d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584124527000000	1584729327000000	1647196527000000	1678732527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7246fdafe0cfad50a1068db61dcf1717abc01a6197db5fb2fa5bcf482d90e5071b7f670f10b9309551a53978bfa64481656854e7484bf6f867f3e94b8383d33b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584729027000000	1585333827000000	1647801027000000	1679337027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeb874e306cba69263f4ee7a1cecb2b7649b54a1d1ccd427343a838dafd4f8f2d97b828bc65c9557f83934e041f8957c5e7e28c3bad7e79a984c7a24acf57f803	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585333527000000	1585938327000000	1648405527000000	1679941527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcd70779a6f182bbfffdc0da52269411a478384f9844eba7897009ffc8ba92c52ebfeaaa274564177ba77baddb77a7ea16d5f2327d6e78cb871f52f7cb458765d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585938027000000	1586542827000000	1649010027000000	1680546027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3b6d21737bf0bab81896a28cce0df7b6fad9718ed09fbcc0617c6f1da04d7806a9e7ab60bb2ede861246390a649951c74d210b12f5cccbc7d1e2539911bf585b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1586542527000000	1587147327000000	1649614527000000	1681150527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x54c2564a81f88da5548a49c35edca0ca631c5d801855159e92b2d7549f2269cc3b939f72b13c99943008afab327d0586b561584ee1cf0a099a08994a7453402b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587147027000000	1587751827000000	1650219027000000	1681755027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd70f44b6a74a3fa01744112c45f1908a1a448d19347cc8b972ad88c70be8e04deeebd4f7d2c266f6432b1b190b30cf73332e5005334877ea340247183e304bbb	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587751527000000	1588356327000000	1650823527000000	1682359527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa0f8b3d8cc70612760d8fb5d88e7f5f5ef57d5501aafa3304269be86ee0896bcd44e46cd678b27ebcb95e0fe1c782c87b30f935321f686371dbc1cf1bbd3bd97	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588356027000000	1588960827000000	1651428027000000	1682964027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x82adf06d497236bc505e9e907efc5ae1481d749600b7979423f8eb9bc4c72a62f97b5adc9f0cc69c052e1eab3a73fe15dbc0ba02c7555afa749b2fa70db79a3b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588960527000000	1589565327000000	1652032527000000	1683568527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xabd95251f9ae32a208eceb957fc394ce015ecb98cb20711f238689939f7ca9aac028fcee070dcf38c9dcd8ba631d1ad708a2a19eebf5cd88534c7e0e62996a67	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1589565027000000	1590169827000000	1652637027000000	1684173027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x71f8874cad42e50a4477f00de15c59e721c5528b3785528ca8ec84f3f4660efc6ed472202bf2eab37f2379440d64ade01b03cef107a4dfdbc398bc1674806c17	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590169527000000	1590774327000000	1653241527000000	1684777527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8bdeba76d758bd1faface814b4fb6c895d0236fc04d073ff25ceb4f5be3613521865b25fda61f6109f8c994dfb1cb21aa93aeefbb235885f300a3a510b952090	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590774027000000	1591378827000000	1653846027000000	1685382027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf0608e0448c58a93ec0be344191f06ce313513be1d317280126faeda910cbdcadaef9add0b88bd526fefdc8fc91351dc80e366f053b33fd4e69521a1412e4af3	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591378527000000	1591983327000000	1654450527000000	1685986527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb9b3d31175f4c977c18e742e6b2d444af91db6087fa1b81fc693c99b7715e320ea602a84cbce759261772291e0165dc57f0af52dae54ef39a2291191900deb10	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591983027000000	1592587827000000	1655055027000000	1686591027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeebc5aa02919f853f75f78fc702fa7a9484d4ddafd3ae91ebe91ff2bd6383a1fd883ab12de4bcba8169cc9ae7de167f32c7f2cc4dc3ec146726bc45820b98abe	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1592587527000000	1593192327000000	1655659527000000	1687195527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7d8e9387284f9c8597f20827bc4bebcbff97c770892d7ca6bc46ceb77126a104e0924b97406f70bfada5950ba16de2f6bbc73a59b63727be6885d4acf8b0f425	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593192027000000	1593796827000000	1656264027000000	1687800027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xca057129f7ea605703e8194c49fb73b7728a0dac8e0cb1aa74c0399306b779cf2616a7bed50044058447a4e69303d294acc8a8163a5d02d7a3738eb80a5183dc	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593796527000000	1594401327000000	1656868527000000	1688404527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeec6c2ff5c537ae5087dde8a8cc2466de3c571e589fe6ce26b5384b9dcb334b98f828e4e255e15387257fef093998cce104585849a5655fd26d9eaccfa0fd11d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1594401027000000	1595005827000000	1657473027000000	1689009027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe194585a6a21ea6ef6d6c4da87c950653aea1fad8755818f0c6ca8500802618f384a8b78efb0c487f27981cf2901457f5c18a05df30b2f83554e89c2a87a74c5	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595005527000000	1595610327000000	1658077527000000	1689613527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xea3be6389edbca88905977f3975ff68bc8fa7c99d09a8d7a9f86ff717fb49e88c410e1f8fecfaf5ae87166453ddf479be016686cb804e56488b0af99dd918ea1	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595610027000000	1596214827000000	1658682027000000	1690218027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3527980fcac602204588e0f9aa5f8c608d3a023418ecec3439ebc5f0aea358802c6e96bf0b6a7e05cc926ad4f17739ac456ca7a46bf9cf4a64c334ec9e13363a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596214527000000	1596819327000000	1659286527000000	1690822527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x17ccc94df1731183e8d3977169afbad2f54c9e3624d6369134cc96b5097d36d53864f676ebf1cc7ed94c9bbfca232a02bbcc447005b7f5fb6407ca24223d3f38	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596819027000000	1597423827000000	1659891027000000	1691427027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8a7b6fa6074351b69a4fbb08c139225066f91ac3673bae447e31663c0f29174e8ba1284aa3b58078e19fa8cde0faf000db681ca36f9c1415b4bd0592c9cdf01e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1597423527000000	1598028327000000	1660495527000000	1692031527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe81c80f69f6d546234e5c4af547a8db8287c00423856490f177bc2898c5eeae1228f4e54596a579f5415e69364319d6e629ca942d6c7605e90c5254d76989df2	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598028027000000	1598632827000000	1661100027000000	1692636027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6ebf441db55cbed32bd1a9eace307fe8a354e39f879d7ee35e17d2b4d531503d5765b8db81e1d76039957f00e609cae35ae003ed9ac6253ceb9f8ba51bfe046e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598632527000000	1599237327000000	1661704527000000	1693240527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb7312854a7c1160d7f3d2bcf627aa143b8789af24016aee01082c8c7095add2a726a69e3ee2bbf35fdca7c1ba0a4df857be16949dede5fe2de2e0176e5974206	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599237027000000	1599841827000000	1662309027000000	1693845027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb54852bdc9304bcadb4af920c36d2651381ea2c36686293d05f130f5115993a7d4fce63620c722f13663c198d92a9d12707d90fcf779719c87712269c84374ca	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599841527000000	1600446327000000	1662913527000000	1694449527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8be470be5403c1ae0c0278238d097ab0516233ad5620ebf5c8b0eb94190b2ed63d0b2529bb4cc6795c6486ff6b9127d7041942d8143e07c5a26cc10cb304268b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1600446027000000	1601050827000000	1663518027000000	1695054027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x839c05ded3a73edd5631ec93d0f461d7adae76d360bc75e24a678d5120348230972d0e45df2f8a59fcfa24ca012f003c99d645b8084ddb7b81cd243f7c015c08	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601050527000000	1601655327000000	1664122527000000	1695658527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfe7826d2f2bb375a29375d6ea026fcfca525827d667c94d74e9e8b0c4f7cb5a9b3c284aa6c31bf99fc00ab4e6fe625d12e197bb5b99dee6e6a1a03ae24ec76db	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601655027000000	1602259827000000	1664727027000000	1696263027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb0ab62dc4cb846f0482e71066eec379ecf3657bd806b4d797e125457b4eba59aee76872724c048597818b4125f388561ab1bae031355f4e8d5df2ed565ac73b7	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602259527000000	1602864327000000	1665331527000000	1696867527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x62f289752f1c3eceea483fe407b8ddde976821c0e2ac910394d191b6761aa4e41fb995e8360930d6766d68013e5b340e1a9b06ac7108374b14fa9fb378098b91	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602864027000000	1603468827000000	1665936027000000	1697472027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9bd261f42cb7be585884414ec175eeaa7c446a0d3f26059cbd121a45adca55d377aaba48798f5d3c5094882194eee811e40bea8d5e18de1ee4393a6316b2eeb8	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1603468527000000	1604073327000000	1666540527000000	1698076527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1e5e384e59ac0bdd77b086344af2985d8a5b1d4e58804ec47824d3d37a5927e0cedf43c55ce4051192f089480a1c61e31393185862e4781e563659684ca9d61e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584124527000000	1584729327000000	1647196527000000	1678732527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a1e88834aae2945a1143238e367ee63ac473383553b81e78b903246fc2ad1e20a4ec6fd6c9400c30ec0883bc0c4d0bbc6824cc3e155450faec74144070d164e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584729027000000	1585333827000000	1647801027000000	1679337027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x440ecd32fd5ef557cd02a53e17d936a34f7ec084e5aaaad521cde1ac77d4a4ac094eb424e8ee25d7389cd27763b7a92ec1522d637b8f953b59c767b789f6ede1	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585333527000000	1585938327000000	1648405527000000	1679941527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6dddf8715186a8eb2a1cb88c6b31becd0205db2956289622f32f055a4985070b230996e1ed5faf8db243ffa3fd9e784e34c0e014f232b4e29f8a7ab9e2f22caa	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585938027000000	1586542827000000	1649010027000000	1680546027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc1710f64ac6a6b8fa3d25387cd064283e52e2f79ae6fc6ce48df855cf7045634af2f1162119c48925ecd8a483b36b6545886deda8757e3b18cb79aa77ae409ef	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1586542527000000	1587147327000000	1649614527000000	1681150527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x29db9458faff8b21df3e0b3f84c92d386501a1071dc4c3d8eef767cf0c4578d3aa929be60c01aec4575c79886ee1e174384b7265d1c679dfaeabdfac33b7acc8	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587147027000000	1587751827000000	1650219027000000	1681755027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe95b5d5f7ef71a62977150668372acfa9bb3418ded88dfba4d3e4b392d3cb5e9c757dbf8702934f96e785b093373ee10e16988d6a894c43c50b4be34c0287f05	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587751527000000	1588356327000000	1650823527000000	1682359527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3ba78adafbae2851f7e89e251f96446b3f07582968708786333b9fd72f50c008b29a474b6189140e71ee4aea2a7b2ee056e3684162096521afd8efe97d6449bb	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588356027000000	1588960827000000	1651428027000000	1682964027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xce3424320907bdb4b3192f3c384eac349b1c1262752839a341ab7202c47d4f78cf8b8ce590ede72cf1d755a2397ffc26e575e04d9de5cb024892e2954f4a72ae	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588960527000000	1589565327000000	1652032527000000	1683568527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0ad8cdeffa1fa20ecc12fc359a7c9ee5dcbd86e3c9e45bea047b00a3a1d3d93b643a053c76f06c6e20f8fcd36af54c2055f377ccc98592de6bd1093009a1e296	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1589565027000000	1590169827000000	1652637027000000	1684173027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c7918da2db6cf0d50baa637a5d6334a9348cffff793bed6775c1834f9768f74d81386eeed55fbc9ebe3d97c52a797c6946d069fde4272cfc9c555394fd7965a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590169527000000	1590774327000000	1653241527000000	1684777527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe70d5534d31b0542c9c4e020d5bbf140652d0c6f36aae26fca18ec4accf1a7bdf82fdca08140c0719cc40d8153ef52d6c6cc53dcf55e6369c416ceee888d93de	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590774027000000	1591378827000000	1653846027000000	1685382027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x99ade2cd19f3699cd23d31ff44f55f69e40bc9fa0118304d17011871519e035bb0ff14f3fe045539f4230d2aa171ac6d0d38a717cdf60645a906c8e291ea8fd4	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591378527000000	1591983327000000	1654450527000000	1685986527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd4fd8e4a9c5bb20e021e9333a1871f31b78e12cb92113f248bcf303ddd3285c184d5704969caba9be0226b4e9ce222dc033cc491ff16bbcd6b2b1039fad3f9a8	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591983027000000	1592587827000000	1655055027000000	1686591027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xccb767410225a0a5655d3e5852e2b7a3014676365fa1f8b2cdbd98dc9c39015a26da313c2cdfc8bb3c14fd6aff08142eff1d4c250a24c1989cf3fc1b1a89741b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1592587527000000	1593192327000000	1655659527000000	1687195527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc2e39ed6d084ee01e55815c586e056c98be19e0eb1bcdde16299b310bcde1cb34785cdc11ac318f2e0cabffe9b835bd3c174da2973f35a1badc423bee334d13a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593192027000000	1593796827000000	1656264027000000	1687800027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b691ba37fec3d24255cf1ace52e36a9f288b36244c0c61d7007cffd45513d0527f5f3c05659b4f9fc8a3185b24c04b626cf0d751ef0b77f02d1506a3b7cce9b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593796527000000	1594401327000000	1656868527000000	1688404527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb5807d51b5e20742015336a4c2208a8928d91c1a1ff2aed45d73689a6030ea41acb940321a45e02c25b92de7665387de7bafaef2db8bb29977a711ff3e1e4cd1	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1594401027000000	1595005827000000	1657473027000000	1689009027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf5a7447d8227068a31470b1b3c070b6ceab3bc63e0aee599ee753282ded24670414ac04be069d26f885f1fb29960e6e9af0846460fd220a3169869f83fe3d825	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595005527000000	1595610327000000	1658077527000000	1689613527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf8dae00595714666ad8c7881ced4755c6145c730e89738e66eec4555cd64003ef9080496ffeaacb3af335ff988807c820de0865be9c36074a805aeb22879ad5f	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595610027000000	1596214827000000	1658682027000000	1690218027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd3ddd0f005e026cb906eed33c0bc4dfa1ec62697788deb415584b68ed7aabc6268591f853aa36f8d691acbb9863a56ac594c358d060aeaab6e8d4cc5571fa19e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596214527000000	1596819327000000	1659286527000000	1690822527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbd5e2204e03e457b19f62dc7ceabe1001a964248bf6840a19639ddffc9c3510b8ece27d12cd0f54c3bc58f27fc8bee6dc9b141280ff6bee9300716ec1e80c6a7	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596819027000000	1597423827000000	1659891027000000	1691427027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa71dbf87f15110e37038bf5621c50a5bce5c4a1337474739bc4c42f0f40afbbc62c90445f30959480dd8d66a9c5852b0e93d8d90a5ac10023bfa3a7b65dd9291	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1597423527000000	1598028327000000	1660495527000000	1692031527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x29d6d00d949c4790c20d59ec73676e15534cb1c146b0916ed20615239fb4d712a0e0807fc9adf6ecb41615c28441c225ab32b3788fc8d4a653a0a7462cbecf19	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598028027000000	1598632827000000	1661100027000000	1692636027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a9e6a85a27507bb16676c418d12f3a8bac940b55e59109239fe063ea03c1cbfb3f1c1ead34d8a68437ef59e2c24fbbd72727349d928e368be80d6e3e23f28ee	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598632527000000	1599237327000000	1661704527000000	1693240527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x353a0d013b2aaae6639b723315e74a47f2549d602e3222007f254126a6db8fe8745c28adb772acbfbbdbc7548783fc3773d1f28f1a5a72d3c5bc629ae72dc23b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599237027000000	1599841827000000	1662309027000000	1693845027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb351b95acb03de7d85f73635aa79e54a3e72b9827f249c889db3a98b02129fd37d77552daa366c8c81c27df9a443bf846c9a1be996b3141da2111e83b8192856	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599841527000000	1600446327000000	1662913527000000	1694449527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcc6425da4bc0b5708ec1bac6f43f6e3d96354716b6e969672b159d56a94bec8a7384b96bc11fc0ee08d463f42003816cf1b243315ac8047ddb2591e040891a87	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1600446027000000	1601050827000000	1663518027000000	1695054027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1799d4b35aafe948b59f3d0eebf034d61c1d45732367a54d5811d8d694edc58a2034262a822a83e14e77e13d4d332bca71ffb284ba012cdeea1c9d321d5f2dab	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601050527000000	1601655327000000	1664122527000000	1695658527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcbaa0317d27bd90dcc9c1fadb0bacd291128775a01a14e719f23bdff89ed764aa4783ddd0f3ada1568371f0318cbc172721de0f4bcfc4ec674b295fea79db61d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601655027000000	1602259827000000	1664727027000000	1696263027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x689e5487355ee63b3fe1fc74f6e68b846cbb53c6698d6436d2cc602f2b689ac03b0d9f0b3d2e3b007db10b92b5624e179861df7daee64361c3a1757c1b94798a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602259527000000	1602864327000000	1665331527000000	1696867527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7978efb03620d4808a5eb9ebd4d2363e1d2a28b5464f3650832f5a8a5f96e568aeb26febb57cacb2e4e097000ddf987586ec6078d4d459777b9fe23d959172a7	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602864027000000	1603468827000000	1665936027000000	1697472027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5a3ef191b4f27a6667f4c34ff8794136ea9b3e3a29e7dcdd6475be15f8b1ac09c3ad2a8007b46bdee3b3196ffc864a685373888e4bf35a3c8f9750d5488eb008	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1603468527000000	1604073327000000	1666540527000000	1698076527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdaca7cdc05a7e781c04ab1e233ca2664bac59caed67e4d00fef43e31f191487a7cb91d8b862d6f9329da670ba79e6aa599de8896a6032249796f50870eae3933	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584124527000000	1584729327000000	1647196527000000	1678732527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x70e1710ad98a6a196e28d1fd5f47e3efcd1b8e7b2f2c3a827876d2ac95f522849d4d310447b76c798fa99b8c2d2f778f584ea1794f9a6bd67e233f9755d0fbdd	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584729027000000	1585333827000000	1647801027000000	1679337027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x026828646242d17763289929b2e79e08ed0af6ef5e94c2e96ba2ec22fe38c4df3557ec2b99d7e6c1309a4c63f830548a86789d73e7032b7524d9b686be8f7db7	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585333527000000	1585938327000000	1648405527000000	1679941527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9c46be3b92d42255ef22a8d18d3bf65d2600fb7b034d2f8d1c09dabe5a345f2e05322f6db09e8c70c0a52fd091ca4376405e85e6393a0a3bb7ba02894bc251ad	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585938027000000	1586542827000000	1649010027000000	1680546027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb1dc83372de79855773717f0bc277c05909631a21672115b41ec805552235854229edd90b3b8334e1bf0eefe781167440f68bdbb61a482457d7c526407527eb4	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1586542527000000	1587147327000000	1649614527000000	1681150527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf0dac394e0c22dbb44052708ed32560413d530b0485b238c5a92e02d5020516aeffda52bfaa95a97038727f0e3679bb64ed63e26d46c3c14bd829add29c6e339	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587147027000000	1587751827000000	1650219027000000	1681755027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9611496044ae44b36d15c142db917df55069befb21d6f7edb77727028f7342abeae8c7a842d0f43620b54d5845f1e3ccc886326c1277d7455e406e6a026cc5ed	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587751527000000	1588356327000000	1650823527000000	1682359527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8254bc93c919dc2e169b97e6bcfdf7bb16b466cfa7a6c047248d37361ac31df661165e9a9f633b39922da22b6121d65e0f9f466f3ab48da861728defc26b0793	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588356027000000	1588960827000000	1651428027000000	1682964027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x22687bb7f5689e6cd945fa27c438e9efb41ae3984aa990f6b10940e780c410d380735d6b13b3f5c4294ea2124ea5c4e935336df23e84e0aaddec8325118a72a0	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588960527000000	1589565327000000	1652032527000000	1683568527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x701ca07967f0258f55a69ab005c59a8e830b6d0a6cc2b057754d60c05048ef5d391e708719cb2b5b7e3a331ea0c382b19fdafe20429f6f17dcff306c7bcb6519	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1589565027000000	1590169827000000	1652637027000000	1684173027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x94ad0c4fa48c6d19e1b1712c4b6330f5f156303a6eb3ce17e79320df4e5dc42641a09aa349271ed6341fbd3c70bedc14d1759136cd1dbaf34cd3c3883093af2d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590169527000000	1590774327000000	1653241527000000	1684777527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc46aa522338c44a61794946022c7aacdfc177cc056a5ba686d7304bac4c99309c8b053a3d47381d1550dcf31370485d393bad7cbbabd2fca5dc0826659e1be70	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590774027000000	1591378827000000	1653846027000000	1685382027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf4646cafb8a856272b8a6896df96dda4f6f4fdcf3d799be76930af7307b88316f4cba350a06755ed97c6105a40964c29db27b60f85e9d883185ea90237eeef09	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591378527000000	1591983327000000	1654450527000000	1685986527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x20fe9cc3b1cb73bef401048d55f789dba305380277596dce68fe8bb983840934520ae78da7cf22a760bc5281b78eca6f88b9f56d47bacca513c4aec6c12daf44	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591983027000000	1592587827000000	1655055027000000	1686591027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcdcf0e88cf82d3cfd0c3abffed069072a54887fcfb154826bc23d3749d748d2e17c9bf873af4b315efcd2c1297b77c4850b7e76f84455a1443217a0a358775a3	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1592587527000000	1593192327000000	1655659527000000	1687195527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfc7567301d3779518ec847800b1028fcf15f715dd717bfe3c25a3cfbceb2c04450694f1864d07ec6b1c47d275d2fa486030342f6156a1f83c2b6c24859594a47	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593192027000000	1593796827000000	1656264027000000	1687800027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd7ec29922a2ab2c75db8815c37639811b54dcaf790a7d647d88dfd9381118d0ccb0fc131d56639e07eda8160d43ef211ebafd16980d8aa7a71d140fb84072daf	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593796527000000	1594401327000000	1656868527000000	1688404527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x425b7bbad7b652b7ee98590299f06e4fef593b4a3c190c6f07e2def0fce849b95f131f8be12a7cdf6ae0f4e4786cf73d71682727b9c896416f73c41ba974e7ac	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1594401027000000	1595005827000000	1657473027000000	1689009027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd001bd79bdf26801b8c94490190f35af5e66d7b55e5c1f69e92e71faaf590b05046231f1cd1ffd3d1a1f58d181f5e2aa9bfbce128b7c2dfeb8ca9dcba2bfe911	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595005527000000	1595610327000000	1658077527000000	1689613527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc5fe89ff0980ec18e88168476f477efb0933742a44091aaaddcc97545e078e8c385600a70041857fa8083394b0e8ea6ac0000cf7a03cb94ea97b45186929d824	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595610027000000	1596214827000000	1658682027000000	1690218027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdbbd22a161dc28ebeb39c8c19b62c24a477399c6fa69a4cdd3c405d9dc4fccbda2c244b66feff49aa7eb7b58583503f34a4e73e83e2f6329d54c59df811a2dba	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596214527000000	1596819327000000	1659286527000000	1690822527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x45ca11e9216ea067d43e637c6a1c915afbadf21429d7e704e5358239289024b48c9c955e3d010b9ad2bba0b2c9fb493c3248ea6bb5065bbd6238eec1f522e005	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596819027000000	1597423827000000	1659891027000000	1691427027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1c3c8bc7b05cb996362e2b4f9d4d02942a55f168f82ecd4fd91226f4d00420f2fd1d74331490962cce588c2fa593584ef247a4bcffbea9fc6219cfad974cf7ba	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1597423527000000	1598028327000000	1660495527000000	1692031527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2320b1ad58ba388b2c77dc68b3aff1c8a190e1956867d0e1a205466e830f2770b39b545fed68dbe24ae6ec2782958f263a225814f5fe0c2e09ecffaeeb617d2a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598028027000000	1598632827000000	1661100027000000	1692636027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdd15cc1ccbc9e88271efb73fed0e16d0f2f6e49fe81c105facabc5fbeb53bee1305c3eef89325a735dd0f9bb7d3a4bd9520594e6c9e5e41b5163c24c5127b09c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598632527000000	1599237327000000	1661704527000000	1693240527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd1b124342be72b23b3e0e68ffb9f8b538e30dc828ce4a582c32e8f78aa39ee17d7f939beea0078609f6e45ca5f78a596709c2f98ee0a714967ac1be79798a29b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599237027000000	1599841827000000	1662309027000000	1693845027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9c4af6f6354aca37595ef1deaa37e5e7cb8bd7530e635e3d395e6902615aab6ea9fff183823c20d97e76ccee0b82d43571e2b2683fdc4e913c71bb66ec162036	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599841527000000	1600446327000000	1662913527000000	1694449527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x89d7ac9dd5b2f6b576b754f28b1c52f4cd7ead3bb2186edfe6235528b7250331f2eb4aa460e66753addfff4b1189ffde244472e98c9b6caeb7980db71231699b	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1600446027000000	1601050827000000	1663518027000000	1695054027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x99a69e5e26e2f8e5f83104c79dee072ee6018669f8d7b0f0c666d2e2f775db3423c0bd186facb12f9eb200b78a84afa21e7f06f0c95f0d42a916973fd0f2208c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601050527000000	1601655327000000	1664122527000000	1695658527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x582a8c78af9af9a6ea680ab0ae51582123676c98a2eb206d2f5e9b023e448ab6e1b07702740fce88e9cd9fe3b9db8a107ffdbbcbbcc785e8f79052a4cfdfc206	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601655027000000	1602259827000000	1664727027000000	1696263027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc1c5873f0daa2d7876f25794f58f81e01f33de23842c7861a02daa8813ff1ba8b8657cbd5f97aa9ae80f1d6933897ce8f6bde911e2e80b06915d319b4af03528	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602259527000000	1602864327000000	1665331527000000	1696867527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4a70b8ee6a64968de4911cd02ea3c24fac7c5c6d6cf1ca2b6f1ced96073258c5cd7e1fa5a6c731d9e6ec7a282f457eaa49027756fab56bab60c833ef9230575e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602864027000000	1603468827000000	1665936027000000	1697472027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaba6767e5fd7e407e88a1611419cc2493fd0855029fec7b8ee354db11c25e5e8ba3619d469789167a1cc31c2bf989237bf84addbe22e2e21839e4287e29df2a2	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1603468527000000	1604073327000000	1666540527000000	1698076527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584124527000000	1584729327000000	1647196527000000	1678732527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x219e13f4cc746bd69a9e42d0064f18f01df10a300f1e7f0eb6b702ce609c1c298cf79cb314ee6e6355b34e9683d010cda9feb50322f30f47604475ecea87ae51	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584729027000000	1585333827000000	1647801027000000	1679337027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x38a6316d7733d9ab22dc1ee21ddeec54445ab802265704f2cb1886424d2c71c9e01282bf1c7154bf812fda1515eb61b0e71ee6d3594a099f5e2ad3b7543a4256	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585333527000000	1585938327000000	1648405527000000	1679941527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7129214704224f28016e13a81c5580ec25d516481a672541353410afc1eb28da038fa5429f2e324e95f96022279f8099c79625d3136b4c574d485d4370130a95	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585938027000000	1586542827000000	1649010027000000	1680546027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7ca973d4625d38421b350ecc2681bee151fa3890ffc4bf01ca0dce134ec798249cd9eaff9fff59833bcc8acb740c26d0535989dab7c2dd1aef9a68641a7fd2c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1586542527000000	1587147327000000	1649614527000000	1681150527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c8cbbbe4b792c026532ee2b04eead7061235e2cfaf6640e4ca3386b5b86d01ab079c357186c5072e4a1af19c1b7d7fc5424d5b302530513605e36d6086697cd	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587147027000000	1587751827000000	1650219027000000	1681755027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x932b578fac6c518e2b2d9ae8590e67b3a5cd16275f2413aa545435f0f243f1b917cb8b99543669c5b075ea339b5f65e6d3bf834c1f379ae491b3eaafed97fbb0	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587751527000000	1588356327000000	1650823527000000	1682359527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x599ca0bb385b935f35c4954295ebcaa36ca4266987a715bd8aa4f6840267853c82cdb4f3b8065ec2c75f77c72f01417acb92a427a7dd1eddabc8f587ead09e60	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588356027000000	1588960827000000	1651428027000000	1682964027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1651117a6ecb0e06b992727774ca18b3c6b74af6e6f6a216403a1c50f979712c8936d34b4689746e7045bf6cabbc1376b78a10154810179071efec0002fdccda	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588960527000000	1589565327000000	1652032527000000	1683568527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xab36a85522f86017ed676eba3e5edd2cad851339a7c2e6cb25e7810782b05b4e444e98f60280faa29c71f41958455b75ee271a547b2b257b3a12d2ddb8f1a1cc	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1589565027000000	1590169827000000	1652637027000000	1684173027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x224f0386a1b2de9542a2a6fc46c670b9aff12adca237f220e485e3b6a3fe8daa048bc09feb8d5cb9c3aac9653a58bed33a3ad39395561c2c99c20cce471f2b56	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590169527000000	1590774327000000	1653241527000000	1684777527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5b9e014d272f57e4bd324400118d99854f12bb448d4f7478ce986fe8bde7bd9feebed3bdfd9fe2b28b36cf398363d7b291066f21ee6e601dec05a56aeaec91ef	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590774027000000	1591378827000000	1653846027000000	1685382027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa380b56b294a436a4b80f24016b5d0eaf28c92d975b399fc29bc3aeacaa7400d0dd3cdad622c4f8a2c0a15dec3601d6f75c45df3306a7901ce50b95af5fc4fbe	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591378527000000	1591983327000000	1654450527000000	1685986527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x42b90336763f126f6144297aa83afce12f9c6690c7c1e2866afc3497cf526d997338399f92639c80e2362ccac4e4de71930aca47fa7718d0bd74f49824308a3f	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591983027000000	1592587827000000	1655055027000000	1686591027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6576b9dfcd7d9e6fb5991cca26a3eea1584637a0dcdbcc892e5ae5580cd542723c313ef89571eb2269adc40633c938e840c2e32e38c816d3c4e8ce40a18e03a9	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1592587527000000	1593192327000000	1655659527000000	1687195527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6b81af3384f1a3402a8cfe1bd9635cb5a45e1394cdb9008d01a7db888201456dc3331c344cd246c48e216570cbca93f1b16c5831d9d6c70be25659cac679486	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593192027000000	1593796827000000	1656264027000000	1687800027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x574f9fdc3ebafb73ef88030346728d582d62a8d942cea38a11812f97e578af30ed0f29b893b3e23685864380fba443a6f302e55660fb23f3ad424a8ff3c30bd7	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593796527000000	1594401327000000	1656868527000000	1688404527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xff224808ff0ad42106d317584aab3cac2124212c7b06e6bb51209a03259f5c9cdd7e062b959342e57dd4d3c6d7e41556ae484bda9b6883d29f565ba445b08356	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1594401027000000	1595005827000000	1657473027000000	1689009027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5b928f1516a891672a807fdbdc9161e69d3e8ad738efd8984f546dfd7af15dac67481882daa25a1cccbcbe90a5f95b8aaeecee7a67946525991aea83c87138c4	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595005527000000	1595610327000000	1658077527000000	1689613527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ef1a5d5333fa440ee46dd5c6e1b8e124a5f1bada7afe420ad600ace26657de38696e805900892b7d34b623296bc8af8748f9339e9d3e4cb5651999927cf4bdb	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595610027000000	1596214827000000	1658682027000000	1690218027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x20d2d6aa2894eb8ed375f6e0b39532f9ea83fdd5ec7f6615c270534b27d6538f0289fe486843da523cd6d59783677447ea6fcb914945ad85b7133db93d0d52c4	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596214527000000	1596819327000000	1659286527000000	1690822527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdff6d8d844938fd27d142a4dcc0a5e2b6ee848cd0657b8b9afab2e6d2265b6f66c0638df55d387d0a17b30cb9d7283a9b64476fbd0acb4b95cb86ade59b42cac	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596819027000000	1597423827000000	1659891027000000	1691427027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x62af1aad614c87e4c7211e2e1a6d404259666145600da2ca69d2e0a4f3f0ede9a7ab84c8b8a54e973eb59418df7a35d3429368f179c1e216704c1069028e9de8	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1597423527000000	1598028327000000	1660495527000000	1692031527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcebe8de4b2897b5e3f52d99278dc0fa28b5f3722e93183a1755739d4a779c137d9399acfe7893966a45628b4ceaecbee88a6b4b9280b9f60d41d48d943da0677	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598028027000000	1598632827000000	1661100027000000	1692636027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2ac1920af6289b24cb867bf6ec8b70c8b3f1df824aa936b2c383af03375493a49184525d4ca8702bb7dc4f60d414e03a0859053d0d36dcfb5889c543da59759c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598632527000000	1599237327000000	1661704527000000	1693240527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf00094b35ee43894327f7502174a5ce0b3a6d04f7469bdb70b2f7793710a0f4e34c088d939b2b1c4569e39b3c06d28773c6f7a091e7419fb6d64d321f55bfc1	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599237027000000	1599841827000000	1662309027000000	1693845027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x930afff580a3d98056ef09d557c0efe2696c28626e926f163442084190781116a2619da31d57905e5c07b32171a11be861c06c0cd032db27f66337652f6b6dc9	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599841527000000	1600446327000000	1662913527000000	1694449527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf427726927f6deb2496e0899c5126ae1ab5594e0a9b4cb9c2292d822b5e6bea9c1204c96817ecb6ff19283c2e08f77f174c9719f783db029d1008ddf014539e3	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1600446027000000	1601050827000000	1663518027000000	1695054027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x82bc94f87de76b23d6d351dd5df662852d2153f116c7fed549834dea6cb58ba7d1121bf71dafe295646ce6657e1b73a38e218a701bb542215922dd7a4b399caa	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601050527000000	1601655327000000	1664122527000000	1695658527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe61c2d268d94f57c99b3d4b82cd2b9a83aca28e1f3d7597245787e6d3cd1bf9a0e33190cdf12a7b830c0a5e86fe0a7133b442e2f49472d1c3c2ea3a401d34c29	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601655027000000	1602259827000000	1664727027000000	1696263027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8973c5a7102a6da989320dd6bacf6a4302c2b58dd2d4fcd41d6415eaac1258daf3eff8b5efd2c394acdd2dd2562f8c84efbdf7aa6c1597591579a672ffe51948	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602259527000000	1602864327000000	1665331527000000	1696867527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8fdbdb6b90c53ca421f9bdbcfb7f0c14c5da59b2ac010d264aa76d4c0708f095794f57f07d1c1abba907a8f77ef9f8d41ef19661d993a1196a9771a93fea98d5	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602864027000000	1603468827000000	1665936027000000	1697472027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7dab82a9348a3ef8616de6b8784ffcfdb5e4fdf47783a0c60017ec646b24e7f28034e1550a7c705f0e9ede1747f3fc1a8bfd77b3cde21187325094b3d274dbfb	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1603468527000000	1604073327000000	1666540527000000	1698076527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584124527000000	1584729327000000	1647196527000000	1678732527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x20c978f9a2db37186d61ff11d9e30dcda92b2d8e29077bac309f9db9be570a75f7543935dc75f976443cb953832215fb2520cdfb3f06abae1e9e74c45c0fa589	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1584729027000000	1585333827000000	1647801027000000	1679337027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4883660d80ed5b9651c06a467a913c5504940fc360d607fc922f5aabf1ef0e7567d952eba4764dcb1a3ceca37e42a5a49e86ec724240789eb6955866255d0c7c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585333527000000	1585938327000000	1648405527000000	1679941527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x22348d1ad408d8ca6fa6d65ade4567aa687645a75b7e697af05be4df8fd8e5726b859aac44b6d0f6b589b105eb645842e17646881c31e813ec54f98de11c1194	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1585938027000000	1586542827000000	1649010027000000	1680546027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5ca639afc97ac81e65ed5a047ec4039c2f01224fd70e58863a382a7f9af580d27d0e70e217a37976ef3bbcb29f9b8aaa70dea6c55654a4674418e1565b7bdfe2	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1586542527000000	1587147327000000	1649614527000000	1681150527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6c7ed8d5009908068dbc107ed5740591c2934c2b20a17db1a5b5c4cdacc23864187a7c24e3e02c5a51a197e3121ab4d18f27f1070b98869f4b8f1381328a7c96	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587147027000000	1587751827000000	1650219027000000	1681755027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf68937d70a7a1b3c9eb5932cd8760fdd18efd455b6f8e881aa0be1188466573f5b3d295045d07bd65d197dadc310484bad2d8fdde6dbc7c429aba29b8a696d84	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1587751527000000	1588356327000000	1650823527000000	1682359527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x12f79d30c267ac4f4c96d9c4a7a3cc20b0344ca6fade34c4d2c101797a84fdc49552f9dee0c56a535f36fec2fe81fddb9efb2a78261b357229c0071fc7685b46	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588356027000000	1588960827000000	1651428027000000	1682964027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0f1f0d0a5cce6e3e7351e308f12554eeb9636729232575e59b315577a72f88be32e0ca83c027b4a69b98e02aa52ac88816d06e40b7a98964ca16c13cf8037c8c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1588960527000000	1589565327000000	1652032527000000	1683568527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6f446b124d0ba3d24fe2b37597dc3771f2f3f8a30a416f799b113a062b61c1a02282d66b5dc3552739a8f4f72d2e0169b0ce4b241ecf6855b43cee59517e9b2a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1589565027000000	1590169827000000	1652637027000000	1684173027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x48db11bcbdc2695aceeb3bf99b43975521af749f0c0798117a3499db593094423e2c585d2fc605ecdb1f540ea9b7c46e74d5f69c8eca106bcfac840f8bd136b1	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590169527000000	1590774327000000	1653241527000000	1684777527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x12c102dbf4cb63761dce1611e278a075b617920bf4ba837a584dd1d55ce02423e2a3dc5632cf7b71671dea5b723a499cefa86e8b75adea0631ecb7d4c283dd0d	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1590774027000000	1591378827000000	1653846027000000	1685382027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd2e2e3cc32b8db5ef884246990dfd5fe7a739b021db8f764a1dcfe63ea72f01cdd61ef75e51eeb4804c7620bede23ab72ce7b70ed4f6a4c61e33580cd3825ae2	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591378527000000	1591983327000000	1654450527000000	1685986527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x981de637694002caa02c2d44d2f9ebd56a9c3bb4df9a41ecb00a0fe5d7e587a456c35ac5bbef24165ab38db6a1c5d7e5586a0df332f3a01272ff7e52813cf237	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1591983027000000	1592587827000000	1655055027000000	1686591027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1ddf58992df18cc06f19ead407f8a67330ad63dc896b981e907010696dd30f3866b57eae146946582b609e4d64089c7a88bffba4f66b8719e1482495e4f91a7e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1592587527000000	1593192327000000	1655659527000000	1687195527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x76c4a304399a29a22602a7499dbb603a98f59f75c62c07a1ca8c62de960b2ccfb4f8558675ff5ca18ccbdaa1ab6ed55e1d66d7422ce790c250646cf03d9d957e	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593192027000000	1593796827000000	1656264027000000	1687800027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4e496c18160552ad02b3074d1a944062573ee32f25f62c5f2b803be49116d87397bc9e5f0f131c08f7914e770e4ab685ec98eca9216fe1ef668afd20e2fc43aa	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1593796527000000	1594401327000000	1656868527000000	1688404527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x71dca7e2794fd0d21b785e82f27fb351ebf06d4391a74a6feb220ef03632fdd61bda97d28cc3b4a039affebbc02e1532c4546eb5a7c1c1990ac5394335a910eb	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1594401027000000	1595005827000000	1657473027000000	1689009027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x789c55f97b0f830327f8a85f80307b590aff4392ca3f6ae98ebf7838b54d293d74e8ef9163a32b07f0a7288ae515218276cd66cdbc9e95ace31cc34dcd93c012	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595005527000000	1595610327000000	1658077527000000	1689613527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x007831ac13fb2fd91a3c534f21cf7cdea6d9780aed594c42b15d7fa86c119636db27324fc66c90523ac3e34f711f7128cafa8842e504acf3bc26d5fe3082ac7f	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1595610027000000	1596214827000000	1658682027000000	1690218027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x854d619f4d4e057244a431e6e22819f1cfde23c714d2dabf7b090736afbcbce1ee7140ce7b56f71623ffa83d50d7681be685d8b2dd5d34e388ba2fbea0e85761	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596214527000000	1596819327000000	1659286527000000	1690822527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd21902884a8475d70ca341e11cad968081041a221797074b1cd63327806802c8900efa115d3d851895d737c38d7c709b1807b3332c43ffe1723e25181b1d724c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1596819027000000	1597423827000000	1659891027000000	1691427027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1dbd8b1d3a1c032f0b833ec7bf3f4848febe6489449b8e8e9ce8e408f2932ca6b6951a7cf2f493a99751ce064b7b23029da1c56242a9a0639b0fd8ae93d1212f	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1597423527000000	1598028327000000	1660495527000000	1692031527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8f7f6d914a70f57e8480f65b732478cf9eb808ec794d472d9159299c41fab8674e97378039e21cbd79ab67b1f60cc5fe7334c584e6fdd53255df8dd2e1234a4c	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598028027000000	1598632827000000	1661100027000000	1692636027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb02bf813b2db03452be8bca6a75245131e6e815a34fc0b9c807f2d09e082ebf20e103b9fb0262808343bdd495d11dc1fca022a718fe596514852e46ebd30ce7a	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1598632527000000	1599237327000000	1661704527000000	1693240527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8a0f9e4fde53bdc1493c68daa3868b3168ba7b65a8ca10733eaa57af364d14331b2004632e253f4b0d5f722a2240cacb3edd3e2c799d9f2a30d110af6dad4209	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599237027000000	1599841827000000	1662309027000000	1693845027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc1f565b59b68e91567944d3920f18b0342f22cdc29c8caef2e565a62a7cd5e6c408ab30e4eee68a3717eea9856e51142510a1cfcb5f2ba7a71ae68cde062c3f8	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1599841527000000	1600446327000000	1662913527000000	1694449527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x355c36c58f56c0639b6f32cd28c7e6f55bffc12614e1fbe7521211cde17631826e2ad632c9eeab6fb74385aeb600d61c342d8ede9ed84613f024006a460c6a80	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1600446027000000	1601050827000000	1663518027000000	1695054027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xafa1af804d576aa34a733bedce5aeb778fd7afa5123668cc30aa6ea5740a3a6cb6a7bc834c471ea17e9a0b867926d0fa73cecd85a70a5d6dc6ef6aec92912010	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601050527000000	1601655327000000	1664122527000000	1695658527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6a0249c2536390e37c24462960e36c4f1a503be881978bd2e634990537a92568f6fc6490aa100118673ff64a200e0dca758ac2c783115eeb8e7df36bf0db3b27	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1601655027000000	1602259827000000	1664727027000000	1696263027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8cea8ac77b34e19673eb0371460636bdab438dcba72fcab2fa302384fb4e15d48b63a245949e52dfb4170566a14cc4456a73896b7496fcc24115a4d3a31a00c8	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602259527000000	1602864327000000	1665331527000000	1696867527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcfd79051d789a6c52ad31cd300b0f89362dc008da611ce6b4a9fec830b47060a963ab5437c5154969a53b62ce4a5f9bd1e5e04e538b8195a3a8056cf661a12ac	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1602864027000000	1603468827000000	1665936027000000	1697472027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcef49acfd01ea30db38bbe6b73d15c1a56ce590a58f77cbc6206373c247989835391be91ebd15e00c1ba9249b08bcb0578588ed46fb908c03e19d4fe34295366	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	1603468527000000	1604073327000000	1666540527000000	1698076527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
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
\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-03-13 19:35:38.157863+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2020-03-13 19:35:38.237327+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-03-13 19:35:38.302998+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-03-13 19:35:38.368415+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-03-13 19:35:38.434473+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-03-13 19:35:38.499854+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-03-13 19:35:38.567893+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-03-13 19:35:38.638836+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-03-13 19:35:39.051866+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-03-13 19:35:39.469868+01
11	pbkdf2_sha256$180000$dcFtllevXo2d$0ihEIW62H0Cp7cO5hW8wZT0+Vgf+G61Ihvam9R0vUa0=	\N	f	testuser-LX9PpmbM				f	t	2020-03-13 19:35:41.106028+01
12	pbkdf2_sha256$180000$CAv2OAXaz8qe$CwXlK4qnwaN+Qr4T0BxPSaMlgxNztPkv/rpNI8i/4TE=	\N	f	testuser-GlcUdYmc				f	t	2020-03-13 19:35:43.726736+01
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
\\xca5e89c144df5f82fac1329f3c86754b0e0a105f7cf27eb9412d20cb48db7eeed585252b6a25a99c85ffaea656af87336881999a8035b50d7917c12f6a9b90c6	\\x00800003ce4886caec21e05ee1abe6f6f4c8d81dd0ac85ca353471a839da3750ad17f281673a1c29bf91454c595c6d8cc14aa335bba13c6ca6ec649f5df6a89335a6aa1c01f6e01fd45ebeef59d5c8d985c9bc92d524b760a3a256daf6f9a96465621469e31880129962b94fb7cc3c12571879f30e4ba3a27399d03913b12357c1fbaacf010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x87fd4d25c4af04e885408429b31019610af8eaf3378ea494ac0fd82389d2b93f8a1c27bb1903f7b0218d08ad85d0a3a1840f84dce9b3e659e4f6c8414e11c20a	1585333527000000	1585938327000000	1648405527000000	1679941527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb13be79e272cf95452c46fdc192d07d16f24c0c0d9638bf2ba7814146c195272bd5f6a308e5c53460c4e5adc12c8116170bef14a542ceae0379dd0862008d868	\\x00800003e1a047301ab6f248378b1625136bb85c95b482305e46666861fde22919b117b8880145d62bd6e8f2475f2e01e0ca8c2cd31f385a9cd770b075fc75341d84d5b915f390db44ecb110538004c1595217fdf37015c474f24f55476f33a1df7007cff712b195ca54003b83d19680201631356e18a467eae4a5d3c8a0da68c39f7c65010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xcc734296a398733a66af965cee89886370b8ebf0a5194c551f371e1c97e62cb29e1b516b41752476b4e0dcad4bf3c8e079e0713256c01e67d1bc25f48d3f7703	1585938027000000	1586542827000000	1649010027000000	1680546027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6576c13e5143d56edc29a8c4917121a1c3917f3436c26f3349de6c226bb96bce029469a4b627b504a3f17d70c4ad7e6c015b4873e98c87238c9b824018f461b	\\x00800003ec4d515927a5c089ec4bbb1c3307282fcc3688aa855a3ab3d7b9575504aff6a6260784b77c32b8768d7cc5a01568a756397d4d2424bd54e29ba8e552e7abaf77fc232bdcbf9df532af931724ed3ac81f738e15513c827799115d19ca130fc81163722970abc9a964dd5534b03415d9102a899d0aeba8e1fa47d5b71a0eee75e5010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x9d4b5be1bf25df041cb98a504324930bf13328f1088e23a443ed2ba0fa2ceeff6fcaaeabcd1e8e9cf0e63b8938d88ef9f4cdcdfb33a22ed644ad30730185a10f	1584124527000000	1584729327000000	1647196527000000	1678732527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19d70de23bde1e436057b52e826f99bfa483b84ce088c89daa91a32eab5edd2edfa2aafa1714e1cddfc6faf8667574e76bf139865720b73ac9d6d4e6cc04c5e0	\\x00800003d98f24063131deea0b9040bf7454597718f6f948fd144072bc6f13e7ba1dcd390b527dac570a543f4839dab9db73f57f8d0d00e7b3e03e3a1725268420feea15491262b8495e9c65fc16f5de4422efddcbeb6d1f3efd8ea2e9c851afff851e1bc5de62b1f2a7853edf8d2252d219c9ef6783a944266d40354d02a44e3b6c1b89010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xef6e3cd3c60c0cbac51510ae5e89421542ac21195a5694dbb446cdf3d82d49a25550c24a2e0ef1ada2bb1c3c34e04ffa7f111b11e766cfe95aabc724267bfe06	1586542527000000	1587147327000000	1649614527000000	1681150527000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddc88ee65b9d5ffc9787a9154065eae790812d277640692b9de92d2ccbe417d95f649de7208d63a5b8dfbe9df3215c1c61862c14863168507078619eb14921a2	\\x00800003e1ee0243d9f85b5479929948af7e82c0f1b9c951cfbe56360ceaf4d71477bed24d39f12c3b702fb62340c87b7103e82ea4de7b865d7eb027ea35ac848d04386e973dbfdcb2dff9cac33584eb64790bfdd68b56be1c0c58b7fe7db494aac8fe547e9ec92e5dc1c67cd75b3c0ab1085e4b0098a1e1c15fc00b040204916bcbf94f010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x765eb874c74dcf41c9633a9a63ffbaf8e27a2738a02ac04db3f7c4b487b1b41b27f9b2cd6ddbf5120bdb8509ac06c61fd1442b5ab9f1e82af949da50b5d1300c	1584729027000000	1585333827000000	1647801027000000	1679337027000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff062da42a2041b151a9a116837e70a11be427656d0e79ee440386edaa31181931fcc88667cbcfd1a47dcc382e8f770d897807ec2b0be258ca061eed3bee85ee	\\x00800003c41864e17885d6a72358c7eedaeead1158d641ef6e21e406227bbf64371f897c657c658ec0f5380bf17ddd48900c081246962ac89705cf84fc0252552a70a3cff2b5e732f874f44018d7ac5b7fa19c6e661155ebb191798198e0cb365b61cde26c5cd795881d8099db156911752678c3bb308dd5d2d41ef6caf75b0802e634c7010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x4d07eb9010978ddc6299024f760ca338a13d458213bdfb32928455026dd9cd9650114776091369eca1d87a7935dd5363d9d9e7f7a849478ff7d850ef66c5a405	1585333527000000	1585938327000000	1648405527000000	1679941527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9cb0ae54f9c698ebd27e4de1c80894794ba23e6a96651809bd62aaf4b09fc051248a210d11f632c21a9bf60eb8a81bcee79dbdf8827a522774beabb2e17f26ba	\\x00800003c803d6a8bf9489f9545c3c199b18794e22313602b2e7f19b74df47a987c284c1887ec33d14ec34c1f25b22c8ab1a915b16a446018b7a15fcc4aefd453cb13b27e28af23fa21dc325f2608543b390d41b27dcfa2dbbe27b6aa9f230e13b9124225d1538b703059ab6a003435731ba7d2ff9137723f0f17f8d77d9980ab8c7a149010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x15534bb923b552015ec1be1ddbc523dd49e8f6f55d0a817e8e9e5c8e75cea9ded8d0cf62d973b58f12ac55e1b90953a2057ae58e5f518a07b08b2a8dabf52407	1585938027000000	1586542827000000	1649010027000000	1680546027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa96d1614b62d8a838b7ebee977db7f3d3b7c3630c8d6aee9c96e848c5b4f72200672fb3ffe229bb3c0ca63fda38757550f42170cf04fa8c647342d4d82abee67	\\x00800003cb92954f616154a0ebe5c193a06fd3018035f879bdc03381d2a83d43b6f287e3d4cf4806523973118374ba31f6a8a71a545c1fca5f1026bdc767db8f3eed12956599b1cc6555fe388eee70a61e8e795df3ed48e6c67ea7b88ded6f00f0b4b1550fb2493031bc553374b63bec73c348b0a8e761f1c1275deb5d82ca1c4e613c61010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xd86f56888547205c27f966130842c59f30dc2c78974d2f790e9db5a87c222ffc0dcfeb5c2ba337c148a1b0692835071233221e5a49a3feb98d7e41c1c20bcb0a	1584124527000000	1584729327000000	1647196527000000	1678732527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x73cc45fec9836dec65d8c0d9b9e0bed91b00a855f640a7ba5710ccf9f83b592660711f7fd27ad73cbe9b36ac8c934b3cf8dedb73a816a2e99338a600d171a09a	\\x00800003d0556420e2c659389778fc16e0e3d5fb2b49a56cca48126bfd7930f4993dc9c09ba31b0bbe576ac6c4a5f5aad846022d9eeef2889123987cf273867a2ec2c36e2ecf7f0ca08d4a252a6a8432eb9dd399f7a135948caea9edfd0ce3f10817ccdd5999bc75126de2431f616518fc75e4889ecfd726cebd27e8e114c3976a87df3b010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x3f477a85d8436d200c6de9edf4bc47abedd3c669939cd31b855e0eb54551f91b141bd8abb8f0cb5fd0fa26a1672d906214d9c9af9948f5a1f864f1c75b0d9405	1586542527000000	1587147327000000	1649614527000000	1681150527000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb45dd1f40b446b36785e2178930240f1407da65a34dc2f4c39b527838e014ae2f5a5249a5db28ab0a64c1e37608fc7345508132dff6c135fd8c1bf651248dac	\\x00800003c8517efeb52d4907be3df6b94345049dc6d8fad031a444feb8e90a320b1b1d91060b21fdd71ca7476a8cfb204102ed44413ca2a40e59a07864e2015207a392a44ddef8546fa47fab665976beff3674e9acf3e179c3c36f1246740a08f25bfcf88d775776911aebd57082730077f1fa594e265988388c2505a4baa4174265022d010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x171138cc0d662433e6f66bddefe985e61e68e0a1fa88d2a0d951199b14ba5d750a118d4228558dfdcdd03281c9149637c86c74ac68aa7f00afc384a2f793870f	1584729027000000	1585333827000000	1647801027000000	1679337027000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x440ecd32fd5ef557cd02a53e17d936a34f7ec084e5aaaad521cde1ac77d4a4ac094eb424e8ee25d7389cd27763b7a92ec1522d637b8f953b59c767b789f6ede1	\\x00800003cc1ffd73de7dfebe1c562ce6a9ce5cfd3146ff33ab0f30492a72f1a6a742f324577025a341379715c90f0c04dbd96d07a27391a3325a94c0f175cf6d6414f961bdc6b323cc1207143486a647f1c3be1be501101b73129a8e5c4156026fe37d8ab50658d3c29eb7af3e53dbf5b34fc2043e18f12d97b04914f8b2caa01f4f0473010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xa1c8c14005102e08c0eddab19f6b46ddf7d00d6e70efb0a56a86490d24606109f5f92a4f43fc70ac966d6ad4fa5096b5b913c41e5b25f8b1f4484223c4560609	1585333527000000	1585938327000000	1648405527000000	1679941527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6dddf8715186a8eb2a1cb88c6b31becd0205db2956289622f32f055a4985070b230996e1ed5faf8db243ffa3fd9e784e34c0e014f232b4e29f8a7ab9e2f22caa	\\x00800003d2172c1f2cac388f4a262c5c6e6f829e56fe426714aaf5d3554dd0b212645aad03b746f5fdfa51c63d19bb4da228c4df158463ee5fd115c515c204bec75697c3c6ebe4047f385d17b609aa8e4cc542d9bd77e076f451e9b7ab4168fd3a81b4e4c94d166f6569d9ec2459bb9f08f8501583c58abbfe1cb45807f5b94ba5263b83010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x595814f099c431e68f9f8682b751688d645d33f7918f76fb28108b67e0630945b42222d49aa9d446f0247750f6fb036618d07849482604757ba3bd50b2ead507	1585938027000000	1586542827000000	1649010027000000	1680546027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1e5e384e59ac0bdd77b086344af2985d8a5b1d4e58804ec47824d3d37a5927e0cedf43c55ce4051192f089480a1c61e31393185862e4781e563659684ca9d61e	\\x00800003b9d0e89e0464cc294a4b703cb0916ec8f101c199c0913ff6b89889b34921e5370b0ceff1a645e605e0df0b2e76e50b676672bf6dd30ef8c69c2f54e9ea7d4d8970399edf6c1825908a3173df18383cc0a167684553c523acb9aec5cc6352355e856d273fd73b5da3a01aab35e85df41477312a4c75b085e624f38eba384c9aeb010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x304650635cac382af2fc1f54a0fc2f55940f9b17b5ccc0f1013352fc9b9edcd80b77d238a2088db34557570db54cf8e5793928ce2d980d13a45570cc3c23c806	1584124527000000	1584729327000000	1647196527000000	1678732527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc1710f64ac6a6b8fa3d25387cd064283e52e2f79ae6fc6ce48df855cf7045634af2f1162119c48925ecd8a483b36b6545886deda8757e3b18cb79aa77ae409ef	\\x00800003ad5737091e9743fd02b05911ecdcf921459b8b5a15dd43fafccafead79069faa43d2aaf9a70b983a37bf75e0916e5024ca8bb73a9d2836027b6dbfd29ce3d5b20724b76ae6b86d8fec4f4920600613478f62bc9035cef81a43c78e4ee250f64c17b5857884e17b0d169715f78b30d94aa6e997e389c128e4ae4c3f49331ccf47010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xceca691d7178b57909ffa6ba8df774fb6436bc2bb9f165ea0bf1c1663f8a1df188a5e12a92a28837cf202f4ea36d2f8719d92679a97b96fab3aad1fcb07d5d06	1586542527000000	1587147327000000	1649614527000000	1681150527000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a1e88834aae2945a1143238e367ee63ac473383553b81e78b903246fc2ad1e20a4ec6fd6c9400c30ec0883bc0c4d0bbc6824cc3e155450faec74144070d164e	\\x00800003c591404b33727f144ecb7c99cc91486002e1e7ff0117fcc13c717195c82ea114c0279ac87ab8a3e4b0a618c4b67630e31a0d4aa8de2b477156be1b3f396a51d13934c9f81b377c09e465f76a7effe7509a1fa44fa3f623d0d52c6ecc94dc2a5fa63b3c054f60a25937d7acabf9fecfa896b40bf9e8a50699cd1b00d4689adc8b010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xef4431c1d9ff48d083d38d7fb3c56b03179eee3264f3758b604ad3f39de619519fcd977f1e5520b338b43a11b2a13ab8db4596afdd26f03fc03d48ce73ed6907	1584729027000000	1585333827000000	1647801027000000	1679337027000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeb874e306cba69263f4ee7a1cecb2b7649b54a1d1ccd427343a838dafd4f8f2d97b828bc65c9557f83934e041f8957c5e7e28c3bad7e79a984c7a24acf57f803	\\x008000039d401132681791f70513d712f0f4b19241230afb120695b8a250e1766e06fe82150635cd4da217d182c1e3624a08312970e70a533a06f05701a23417b243b6e42d9dea9b1d67cb1f019352d19dd8afb4ca1773451080080562600af5d49ade612754a6a827fa95095230f1344ffd931f480fb1303aa901dbe240acfec0451847010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x5a499be00f19391fe05bb8d37ce15894b1a5686ce53ee68c8824c022ad1b4186c305eab089533b5a77a4f33220b9e80192192bcfa08929ff08ae8c2f19511603	1585333527000000	1585938327000000	1648405527000000	1679941527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcd70779a6f182bbfffdc0da52269411a478384f9844eba7897009ffc8ba92c52ebfeaaa274564177ba77baddb77a7ea16d5f2327d6e78cb871f52f7cb458765d	\\x00800003c47b94ccfedae9656f4b5c8c6f9524418a356d254af754e22cf6520b58da9c537c3be39e81a410f9e5e04c58f2733928c7d76fb10cea441eb8c3ca4fe35f3fd7e977e08c649bfdd0bb480da9443db0b95bf2da14476aab5c4bb6a459f337b71cc9959b37c242f684d9788835bdf90bd54cc55460d6917077b5caca4043905e57010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x55285c088ad40c3ca6b2bdf8b55a371b63d0dae62da7ba72d8329a6b8f89364b60d237796091d01e79fa4ad45fe9d372c3832bfda5565efd2805137fc90a3a02	1585938027000000	1586542827000000	1649010027000000	1680546027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x597a8051c87010b154a8dfa6643279b0c166b51539c69b9cb19af986ab521ed59877b3868c0e56aac00ebbd6f1f3036a6b667403fc032e32b5589ddb9c257b8d	\\x00800003d9d03d2b9b09d7277ca24c5231038d49a46d080c8bd7671b665c39328e6b1be137953fe40be4a3cc752cff25165b08ad41a9d49707bfd49601d0dde0bfccfcadd64f02320c253db5da792606a53f8da11d1e9c39b9f18dff9ddf07c40b11ff235506da19b9e5aac9b7f17b02ad6718269a95fa48b7a5927b9b58eadf229750f7010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xba8ae58e0b93543fddc3e09efd7f67a32ffac7684627ab54fe1f2ba0b3429fd64540871b8d5a2d2b54a9c316c589828d54def56ccfc90ba999e8ddea9f38690d	1584124527000000	1584729327000000	1647196527000000	1678732527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3b6d21737bf0bab81896a28cce0df7b6fad9718ed09fbcc0617c6f1da04d7806a9e7ab60bb2ede861246390a649951c74d210b12f5cccbc7d1e2539911bf585b	\\x00800003b41bdc5e3f58e742601e474858b2c7a6c55e078c74ee175e71a4804fe0d774f9dbc503bf7b00d491ceac3a43798c613777d6c2cd86169ea8bf41395b6695baa3b0fe4fb56e561cf7479c3c3fa725bc095e15fc4a3620734e1e26e26354401db4c53305044bca0003e578dd9b77428db0fa36c8bc0e9751b2323e341b6fa6d00d010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x52a44f26383e8b727c7a1d3b2e74a39da18ffbfdb2888715438e5640281046414c66a60bfaf6f22e41bb43c9d54f5873120de03b6d2398a467ca6e8b3a35b401	1586542527000000	1587147327000000	1649614527000000	1681150527000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7246fdafe0cfad50a1068db61dcf1717abc01a6197db5fb2fa5bcf482d90e5071b7f670f10b9309551a53978bfa64481656854e7484bf6f867f3e94b8383d33b	\\x00800003a188bc13744a4300c1b95817c396f9076e755a0a09f403f94380db24b4a16bacbf48852a2d8753aae1a71727daa3bf6561b7a940c05798134066b3a367aa3c7fc286ef31368cbecb1de36b2e0ceaac727dadba705a98024ce98e2b07ad7e7820798192769c8f15262a30cc0c98ec2d4af730bec1cd16fe7096eac035329c391b010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x98845def777f9c9309519c4e7e2f3a4acf7cd8f4c09f33a431b3a8d97af2711e967490703f7a630d687921dc5207a0f30cc596990edd86a23dec3c5bde969e00	1584729027000000	1585333827000000	1647801027000000	1679337027000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x026828646242d17763289929b2e79e08ed0af6ef5e94c2e96ba2ec22fe38c4df3557ec2b99d7e6c1309a4c63f830548a86789d73e7032b7524d9b686be8f7db7	\\x00800003be4a7bb6192c1aa5e29adb2e162eed80bb207610b94139364156e901ae3a902b5f3188230287e0612dcbf9cf91a35e03736abd6f209a7d29faca45a4d55efb0c4b74a52cf8be1f9c0db0a4bc5a6b7d06c2170789fdb5dd7960628e3ea50fd1b2bf3aeae6c0eca4c7c7116051ad5edee47850dd811fa569e54eee2d06dd5f0231010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x5b898f41af054034864c16433fac04d8939b372b715baf27e947b515934ea9c01f4c5956d65b36dbe9962d84bb54efc505f4c5aafa5a9aa9be9ba8cb325d0d0a	1585333527000000	1585938327000000	1648405527000000	1679941527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9c46be3b92d42255ef22a8d18d3bf65d2600fb7b034d2f8d1c09dabe5a345f2e05322f6db09e8c70c0a52fd091ca4376405e85e6393a0a3bb7ba02894bc251ad	\\x00800003d5e49296ba82cc605345d6467a826e8b5237de416c65607b4da81bfee63da4aca78b8513b26de0e87d841b252c98d8f2e489aebf9841c515d1eb0793dd32a11d14b6cec67741dd1b18ca422df9fab85f23fe61db1b5bfcef5d83e88bf975fe84eb03e153cd5045b77eade82bb71a5083301c89c778b62c199f386fe5a867a87b010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x968470a358909119f81c95118798aff002d554228f39ee6bb4c616b3d19d7847620f2cbfd57faea0278a62fcfa21a3172f8f0db4b2d82934e2fa96a1a0a5710e	1585938027000000	1586542827000000	1649010027000000	1680546027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdaca7cdc05a7e781c04ab1e233ca2664bac59caed67e4d00fef43e31f191487a7cb91d8b862d6f9329da670ba79e6aa599de8896a6032249796f50870eae3933	\\x00800003c09b6a69e5216256944a4647ea9b6db44423b35597fc0c4c8918deef59a930facae82b65e54e9e5e76d3b2fb9608844a6ca8f9a28a8380b3f43be1ba3b523377475fe4a60e047cb78ebc09d979a48cc271be31bd31dc10d638d29e68189de3b3bec2e3e7093a48b2e11614093ceb8003f0724cee27330fbd995c193e3a0a463f010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x834a002ab74ff3a7efefdc0486733ba7765bb5419c41990e846ff6c267e8b9246d4fb32a85771522adbc49602cc916ea89acde35ad0cf6d103c7a213d8863f0c	1584124527000000	1584729327000000	1647196527000000	1678732527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb1dc83372de79855773717f0bc277c05909631a21672115b41ec805552235854229edd90b3b8334e1bf0eefe781167440f68bdbb61a482457d7c526407527eb4	\\x00800003d902ed74e57fcfdf691130afce1819a1556d3eb5e71de2696c208fed60e8eb24da71e28c33d15b77299784e42ba181a84f35181863061fb16867ce56a1f08d2e936598ad89ac0162a5b0357b7d446563850b07fc2ad9a151a45edd93bd3371777f4eeb5ba0c265f8b51efcd5261eb61f8cb48ef3d83d2aa05330718190f4d89d010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x7d0c4621b3e8df3f408bfa853e0c3d0380fd560472e3d4bc5535d4abefd832f5ff48dfeb07798423e84d24593f50ca22453d1a0a051d9405cf0d18f056fb210b	1586542527000000	1587147327000000	1649614527000000	1681150527000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x70e1710ad98a6a196e28d1fd5f47e3efcd1b8e7b2f2c3a827876d2ac95f522849d4d310447b76c798fa99b8c2d2f778f584ea1794f9a6bd67e233f9755d0fbdd	\\x00800003a9b87263fa85ab87cec1d6f4453dce53beaf85ee2260f6533b16738adb0edf2da3704af15ef730b7aaae3be3803fccea699c1dbab23a11bb2892e9d7c0b0434d3f8f05467361f818f4038c67d7dee0fbfec836a4993dc66e1890749d38da26b014b69ce9e1543f0e8ba81622304be9f90131f31a31fce0fb63850c60bf6a65b9010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x3af07bf48c1ee872f8fdb089700a39b8d4958598611979399c6d0123080b1ec10026ae2026717eb8294669d5b1b42050e8053f97e13f044971285c1b1f9e2c0a	1584729027000000	1585333827000000	1647801027000000	1679337027000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4883660d80ed5b9651c06a467a913c5504940fc360d607fc922f5aabf1ef0e7567d952eba4764dcb1a3ceca37e42a5a49e86ec724240789eb6955866255d0c7c	\\x008000039efb9e5e59ff102939f6ca0854e42d3ae1e988f5a9477bb7ff143245e5cdd40b1730c6c0b2c5d6b34839e84c6768d78928f290154d88f589afbe7d219fb7f63b2cd2cf0dd5930e6d0c01c3581d4a4cbe72c3f26095ffdd8ec494015a613c02240b89acb5381e06e72fb949c002ba1f887b39479cc6a2fbf864c2437c1c8d0b7b010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x89d3f7e88b73571a8d76d50000abe919eecc577a5b101c19c520ee98105748630c8e471a204acfdfa71ba317f87a4513b12fd414796baa70478e06e61e8a4301	1585333527000000	1585938327000000	1648405527000000	1679941527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x22348d1ad408d8ca6fa6d65ade4567aa687645a75b7e697af05be4df8fd8e5726b859aac44b6d0f6b589b105eb645842e17646881c31e813ec54f98de11c1194	\\x00800003d7272bcbf166e1aad6c5b95aec6043986528265d0416f1e610aa38b787a9ba80a13f314facf4b1357269a5f4a2176a4ac1477bddbb39fb9143c85cb11f53a289b75b448334c793bfb0f602d599977c3a5a252ec48b81807481cfa97c2df0b366111611f65bb1653d604da3403f188fd804f5dcf1f9dfe41977ade0bbeaff90df010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x640f14fe341fa70cf1fef1d53186dd7719d11e308a338d4cb7ef827891656e9ef57b344310fb604d96534fdfe350161cec3e0f52348d685dd6516b3950acbd0a	1585938027000000	1586542827000000	1649010027000000	1680546027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x00800003f83ed03e7c128662173fa86474e21137a372fda811106ad733002b3e7079f6711d5e074ba962bf825f5753483681a6c5654705e5c01d390e9a4a8fe928e6ad0e4a34920df1e00b4d98d8c73e8d83b5caee590700a4379b8171a1b23e82fa9baa81b2949f57361037a4956c2141a24c0fc0add51c6769a90a6740f25907a0f2b7010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xb5a03c23f108414d33e97ee29c9f03e46e8562e418404ea368bcd0ece18e234ecdecbdd19bf2f3665486bed4596d4c245cc764489a4861bf229d33f0d0d1f708	1584124527000000	1584729327000000	1647196527000000	1678732527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5ca639afc97ac81e65ed5a047ec4039c2f01224fd70e58863a382a7f9af580d27d0e70e217a37976ef3bbcb29f9b8aaa70dea6c55654a4674418e1565b7bdfe2	\\x00800003ce25fd45c8df7a0d851c43f314200887fc8ddbe39c98f93559235dd4d69497a4b66f7cd808e05543c53e454a6f5b88f57e60e64cc7424e315563ebaac7ffad0e20b38cedccb2606584fe1f9473500b9286a9081d283a42e9554cfd3426a6b3f511f2aa436d6139957a2e52cc521feea4ed9bf8ed26326cd9a038f6b9a5f15ac9010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x96ed3ed03dbf7257d0e8b7ed6a58c5cc5b0f64a3cf922aa4f9b20b46ddd2b9291f425ba5bdbce3727f07aab1dd192cb99cc30df39e1a0b12fbe835c04027d50c	1586542527000000	1587147327000000	1649614527000000	1681150527000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x20c978f9a2db37186d61ff11d9e30dcda92b2d8e29077bac309f9db9be570a75f7543935dc75f976443cb953832215fb2520cdfb3f06abae1e9e74c45c0fa589	\\x00800003bf890a83bc06473603be6aa8561026fc2cee10cd4a14869dcd8becd5bb21f3fddd3bf8bad62c4eb6d72c951889e636f599425d5cf2bac1b96e2f25f318acd8703f60a2adeb4d6991ce0dd8b3ce89b265327cda0c70554c56a97a8482dbd9e3aaa311872bdb1419571b6c9ee6aa1e7bd562568e3d849bda4f064cfb8fdf1c3a57010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xff0ea7bd5f77ca3212ffadccdb47a41bdc5a2a9f67cb5555552a40ee35878d20e209354ef9b0d84348b75453d8b06cfffe9f0d9d9114db1e02b74a1ebf62840d	1584729027000000	1585333827000000	1647801027000000	1679337027000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x38a6316d7733d9ab22dc1ee21ddeec54445ab802265704f2cb1886424d2c71c9e01282bf1c7154bf812fda1515eb61b0e71ee6d3594a099f5e2ad3b7543a4256	\\x00800003dec4ff80e64098b7ae00280b357ce5563a98441c172c7c385b46af5b1be3e08d6010ff046bb2f94ac108613ffb7c3ddc9d325e722d28df0c0f9e0ab9ea2ae8ea5db847ec640b22c15a0eee77226c15192851b34e3c4e9d7ebf99e08a424bf88649201b225d02729d3c3cb227f1a94a70c45b85c30c6ba1f148389ebbaee92965010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xd7658085054adea134a5cbefca1bb0b730a3ec605b28b523735586e8a9eeb0693b287e3ee40b7975243514438f02d05117da9598689ddf43536d8b37963ca406	1585333527000000	1585938327000000	1648405527000000	1679941527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7129214704224f28016e13a81c5580ec25d516481a672541353410afc1eb28da038fa5429f2e324e95f96022279f8099c79625d3136b4c574d485d4370130a95	\\x00800003bf60e5046468a2871409663abe71406c795bf1eea7324d766dc7e371038b3104238d08e3c79d92cc8176a4361d78fb7616a2201bf98e70553a5a79fcefe47ae4c89286be08aeca35f5b8e64ac51c17ab019def36a72d0f5d3ef68ef3af454eee726c01d8ec342fef5e89419d2c42f1c822e2aaeeea314ffa6c924ea9c780f4db010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x32670ec806a514e69ea969d15a6a914f1c9af8472c1dd37dd353ff798182f05f12d0a2c428550ac7af433b165c60095a7beba870ce0be458e40dcb5bcdc77907	1585938027000000	1586542827000000	1649010027000000	1680546027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x00800003bc3dd9c22574bd250fb58c4628dd8ad4480ac88f76602c563234ddbc06c7610b9c32ce137acf9c458ed251108c4e098fcf4aac926c7eda1550a26739f6a51800895c660fd01066518101667a8aae345a9ac839c8c6ceccc55127d668ae1fffebe0792228b6ceef327a60ee45e2bf642d17e1b3f35fc41614478ef863727cac87010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x3b4f830a3f7c7fb749abc4e04373ab71cbca0034a447cd3aebd15de0b88d19f757fa75f0ba692d8dbe75b3c2edcd2a67f2288786b48375131dbf64c5d02b7e07	1584124527000000	1584729327000000	1647196527000000	1678732527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7ca973d4625d38421b350ecc2681bee151fa3890ffc4bf01ca0dce134ec798249cd9eaff9fff59833bcc8acb740c26d0535989dab7c2dd1aef9a68641a7fd2c	\\x00800003b50ea8f56d6483194523f595ffd5cdea47d3c5cf662f35ebde6d914f060952211985ce21a33ec2df14e25a1684a6e54bebab5d150735a45080659ee32ff1b4b0ea31b22cb9ec7b1db49e15b2b4e9bd2317f78467a97a9b44646e8fd423f57a7dd28f28dc385ff58f636254c645bca3b5d9dadb0292056835a2cf9da897699745010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xc5084a8e8a01e4667e5bc865edf053adb3444bdf088203b69924ce9f0da5d78ed39cf9d677728bf1a2d494c8d26295211d9aad05f7dd1d26df37b681dc588803	1586542527000000	1587147327000000	1649614527000000	1681150527000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x219e13f4cc746bd69a9e42d0064f18f01df10a300f1e7f0eb6b702ce609c1c298cf79cb314ee6e6355b34e9683d010cda9feb50322f30f47604475ecea87ae51	\\x00800003cad11e9222a9db28e0b7cb83c3471e00b7d165c9c75fde2bf3157952ab20d569f7488082fb24dd48f342b8e46cb507fdab6b5d570f30bdbd25a84d6b7b58b2cfeb49ce3dc1f5b5611142cab5459a91a690ccb71229efeffde04aed806e7d0f79f82e9b3fe776b9e474212a5134f85c2740939807e1457c8150860c5ec4c5360d010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xfe63aa058348bb8ec0dd2ffcb0aa88b23c835eafee0ac4022db6465308443878027271a989fa176073ad1a5f60e799cf4e803263e76e6e4050601a7a12a2070d	1584729027000000	1585333827000000	1647801027000000	1679337027000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5ec27a33faef3b0da60b8403beaebe30e385c3bbb0849372b164d26b8c73265914f804eabffb948646a8ee0ff18ac8681b5014adb983dbc692a4406791ec1f2	\\x00800003a3aa7255ad8146f08166581ffb0485e0f7151ab33ca42bb49c5a5cb713acf170f4a41caaec47093963d7d96e8b70208b7f946e87752011146a3e2687ec502df89295ad24c9f0c6a0de3cebce5beff56f29a2874a2041867d968d93dd72200773fcfb97cfc0642d056c74a69f4b8de44bff6ca0a31066a77d8bae36f3172ef491010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xc4b621489acc39e1fb0babfd152c9cdeb1e730b69495d01ebaf3bb69a98aed4df80b7f01fd37aeec2b71661b5ac7ee0024e2714aeedae8225bf952543e95b804	1585333527000000	1585938327000000	1648405527000000	1679941527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x736fae372040bd5d2d9c97e454efa630d0ca6a01a277602638c998af302418885e017148f4ea7cbb144a0c29a463c8c922f3c527f0ff63add38f64292c69f5a4	\\x00800003e295a2b289c08db64929f3358e797b79bdd1d47a5fdf8fd2311ae251a49524c2e5ff73c2a3c8e3a9e1ad3a22bfc85ff50d52e8e0b4a71203fdc33812d1f0d284f11c964a3d9045050553bff210b055beaaead552c8fe254dead414ae74e8e1059336af45d9b103c82cff12c48251d2e376d75b459f55ee07b6519bb25d9b3455010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xff0ad2fcc355f96adfc980b0d101cf1767078fb86d025614c3da24f0b3f9f9621bb8f28b549c14de96688adcd836d85e3de80fbd0765903b5e7cf3e96a92f604	1585938027000000	1586542827000000	1649010027000000	1680546027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe2557e383c1c3c019681c2521d415a758f1becb629a3a75fd9dc212f0f2e802aee81e71db725f0f9913bea0f913978bd7d238558712aa957d80c4e1673292b13	\\x00800003e507725bcf9546efceca340ab3e26584112e0ef76dd658530c8c49d533cdfa99eb4b15aab02a9688b090c3d41524c16017367e68dd16697ba7378d107bb2847028738ed00a6a9c770503b8dc738b16c780fa27d9e50b355fd977ade1ac8c810b454d6c5fc387a00da8b67ff4a501bf90e4cd055ae47f3c3a091a1fd4113d9565010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xffe91c3d5d330d8614a94e6d6a7534aab3bd6e3b23b7b0e9e00112771662289a437237fcd2bb442b7353e16fd73fb855247025a1de099f6053084c75fc41f001	1584124527000000	1584729327000000	1647196527000000	1678732527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4faae841605109e2e8f43768baf54551b8d2ac29b16f601799c2ee260b9bcad53c8b4e5ab2352bbc1b12bc28c53df0e3ea355d61227430edb4644cdc4546907d	\\x00800003bff0c91b4cb35659641e0899c62e521f645d152916158343a3317d53558dccca832301e3f870efdd7a9df5247a37583b13a4a2e5076d65e0b2adf890857dffd58666b1ad707cc32441d51b15aba2339a41d7e0c1e43b51c0ee088ac49e402e849e869dc6c49c1bd85d0faa341e5680e770b7a06f9f3f6122f50393560277ee63010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\x127896e38a662f166503a6c75946816e76dd587e1efe1dfc9276c2795b62df909bcb29358ec76b35a9037ac41a991f74e137649e5f5aa42cd8e21bb5a64ab809	1586542527000000	1587147327000000	1649614527000000	1681150527000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x89d632dde6b67bcd5496434399229c75e8925653c5c952393a61131b03f941ba1ec3de4e210861a730b85fb87cdcd7ccabc26317cdcb823f83d027ba8777324a	\\x00800003a92dd9345bbf84d519201c8cbad3783c48f9e8c5039c4a827183a0d002b44c08a9651d1d12859f314caa2e91a28ffbf2abddd4d0ab74ac03db2407680de5cf19dc3955f6b8cd6b6ae1cd4846c8b4d3a8d6fe0b24196ea1ffecf157b9523f60227d776b3b351bc060bb0220136242761cf2a548c1c657a0687d4fdd53ee3d8327010001	\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xe88df9aa6e98cfc83a6af6116e8134ec82d654d9611ecb3f458db053bd4391e96e88d752179517f61be798823b626a4ad0f028fa11d1050602df228ba6be3e0d	1584729027000000	1585333827000000	1647801027000000	1679337027000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
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
1	\\xda43e65bcadb947221036c387da292da2642c97961f450027820d0d9d5ab1a0f	4	0	1584124542000000	1584125442000000	1584125442000000	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x61043073e65af0221d1c95ca0a32917de5241b89f81678577db4df852e19b5545a11b0b1d5f786917fe0df200159864d78c575ce57421112e58bdbf0e1b90672	\\x137f048953e22f0e5d28fc42089dfefbf9af016870a369a489f99c2b7038951e3644106d64a0906a06ef332199c006201be7c37cde19d3103b41394b885e3f7f	\\x642576f253e7849a632bf7a61c38a5f3a538bce3a7f56f6d65a324f083c16b0644bec34f1a4741471593013d2c8ad439e9bdab29f3dc905ba097095968a49900	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"NR2Q644SMHJ19QD4534JZH52PS466JGGGV885PX7BSPHXSCWCP6X75X090E5XFK04GSB85EKFJAWZDRGE6ZJAB6BXCWC3WZZ3WJAPW0"}	f	f
2	\\x9c73b669f228b004180fdcf3a9f33afdd000fddbaf12688eed6e3f4c57cef523	7	0	1584124544000000	1584125444000000	1584125444000000	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x06c4c1f2ee5260b7fb8bb1542fd840107b046cfe46b05923d205a5c03f03a3d19c367ff4c642be00989a36d3dd48abb6b444a7566897902b5d62e6cb01e10edd	\\x137f048953e22f0e5d28fc42089dfefbf9af016870a369a489f99c2b7038951e3644106d64a0906a06ef332199c006201be7c37cde19d3103b41394b885e3f7f	\\xb47295d4d8bb784929ca37c74a3ab62ac3964ed241192c4dbeec9197d5ce41f1b8bdc468a7e126f8dfcefd1c475631178b1aa8f0c8778a6af8a1b8aae63ee007	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"NR2Q644SMHJ19QD4534JZH52PS466JGGGV885PX7BSPHXSCWCP6X75X090E5XFK04GSB85EKFJAWZDRGE6ZJAB6BXCWC3WZZ3WJAPW0"}	f	f
3	\\x0b11cfd1ebfd067d2cbc26e663f2f814a8b5e9a387667adedfc15006b5531b0a	3	0	1584124545000000	1584125445000000	1584125445000000	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x2552601dc511378133958937eaf4e1c6cd934cefcdfb1645774ca60278e386acbfa6dbfa6062e0c55dd09af197ba578ac715d74f11015c95b51904fe4e5adfcd	\\x137f048953e22f0e5d28fc42089dfefbf9af016870a369a489f99c2b7038951e3644106d64a0906a06ef332199c006201be7c37cde19d3103b41394b885e3f7f	\\xdee39e3e40bd23cb375afd5c8f934f3e7d2faa52eb616fc75ceccc32341d15b2cd1497ff908d2d87177010f87f86f488f167ba6174456ea0b3da17bad64bbc0f	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"NR2Q644SMHJ19QD4534JZH52PS466JGGGV885PX7BSPHXSCWCP6X75X090E5XFK04GSB85EKFJAWZDRGE6ZJAB6BXCWC3WZZ3WJAPW0"}	f	f
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
1	contenttypes	0001_initial	2020-03-13 19:35:37.942029+01
2	auth	0001_initial	2020-03-13 19:35:37.965921+01
3	app	0001_initial	2020-03-13 19:35:38.006049+01
4	contenttypes	0002_remove_content_type_name	2020-03-13 19:35:38.02578+01
5	auth	0002_alter_permission_name_max_length	2020-03-13 19:35:38.029156+01
6	auth	0003_alter_user_email_max_length	2020-03-13 19:35:38.034873+01
7	auth	0004_alter_user_username_opts	2020-03-13 19:35:38.040331+01
8	auth	0005_alter_user_last_login_null	2020-03-13 19:35:38.046473+01
9	auth	0006_require_contenttypes_0002	2020-03-13 19:35:38.047897+01
10	auth	0007_alter_validators_add_error_messages	2020-03-13 19:35:38.053184+01
11	auth	0008_alter_user_username_max_length	2020-03-13 19:35:38.063052+01
12	auth	0009_alter_user_last_name_max_length	2020-03-13 19:35:38.071748+01
13	auth	0010_alter_group_name_max_length	2020-03-13 19:35:38.078775+01
14	auth	0011_update_proxy_permissions	2020-03-13 19:35:38.085658+01
15	sessions	0001_initial	2020-03-13 19:35:38.090129+01
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
\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xac23892c002bf8a985814ae72efcc892c969a76146a4e678b8baa39be9a77aa44b6bb38061f0c7e5b62af0dc80a90d90269a9dcccf1f20dc970a7f587e912602
\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\xd6a6229b7c19ce8eff9032ba6c2a10814419d915130c18ff9b9f5ac2cfcc356df041b8490216051ae64aa70f135aef569fe80611b89e08f8fbe0e8119ce75e07
\\x5f4749c40e0facf00ec1d0a04ace9eac5707074c154b636391d0651af58313aa	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x0f71224698bd93d8ae632f307f9693057a631930534fc3ca30d1b8b6bfa9d8ec4d684b9aeeb156f02ed1ed4d7c7960b2960f06351c7046341c0dc035ce70bb05
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\xda43e65bcadb947221036c387da292da2642c97961f450027820d0d9d5ab1a0f	\\xe2557e383c1c3c019681c2521d415a758f1becb629a3a75fd9dc212f0f2e802aee81e71db725f0f9913bea0f913978bd7d238558712aa957d80c4e1673292b13	\\x08075ab603a3dcafc04dda6808d30c65ddee0027cd08cadf3d73d7ec9c6458d92473ed0532b389dc2f1877d86a9d4eefabd08db7e6d258d9de1eebb13a3974db1afcaee9d1c59f0d18134c0738e26e45ea06c61302e6494a4c76a80e0742ea68c063b2742250caef0931bb2d2dfb5a4c7addd70c0ec45afeadff9288c581934b
\\x9c73b669f228b004180fdcf3a9f33afdd000fddbaf12688eed6e3f4c57cef523	\\xa96d1614b62d8a838b7ebee977db7f3d3b7c3630c8d6aee9c96e848c5b4f72200672fb3ffe229bb3c0ca63fda38757550f42170cf04fa8c647342d4d82abee67	\\x5bad81f95c0fe8de6a8e5994526ffd7d511bfbfd37f43cdce2aff542af08c9c5a08789da0d31d5404995db7296583b8a32c9f79cce2bbc60238e1874caa107c7ed1d9bba2f9d2896945f3db6d8ffe23af7fc1dda85984ae7c0d12d961e46d96ac0f1ae1835f757ba98231409b9efa95b369b30d6f4e9663b0b03917c69430b1b
\\x0b11cfd1ebfd067d2cbc26e663f2f814a8b5e9a387667adedfc15006b5531b0a	\\xe2557e383c1c3c019681c2521d415a758f1becb629a3a75fd9dc212f0f2e802aee81e71db725f0f9913bea0f913978bd7d238558712aa957d80c4e1673292b13	\\x8e645e50b8a904c8d36ee6fb9242a49ba189395226d4a2fd995e77662acc4627fa54bdba1cdca91d6dffb908e18c3eda66674cb7e4ae7bb1b3c63d57b337bb408691d90e96200b89d0c1edce84670794755203cc57971034a544910cfb43f31902b32a1261df553fd18a9e75ea0d5be0d7f0fc7501b00fc97f45502d62d54a87
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2020.073-03CD47SDDBMRY	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538343132353434323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538343132353434323030307d2c226f726465725f6964223a22323032302e3037332d303343443437534444424d5259222c2274696d657374616d70223a7b22745f6d73223a313538343132343534323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538343231303934323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224258334d4b4830453159504630335031543247344e4b4d594e48424745315443324e35503652574854314a484e58433332454e30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2232445a473932414b57385147575139385a483130483746595a46575459304238453248504b3934395a364532505731524a4d463343483047444e4a41313433413056514b363843535230333230365a37524459445736454b3230584d3245414248314633595a52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22395a44304b4b5157304d39415453593435365845484b5352534250434e443751585a4b3944384e31373532324b59464448434547222c226e6f6e6365223a224a3152594e474e34545845344a333553474e443733534748334d304756454d484a4d475a324b59315a5157504a4d33434b4e4b47227d	\\x61043073e65af0221d1c95ca0a32917de5241b89f81678577db4df852e19b5545a11b0b1d5f786917fe0df200159864d78c575ce57421112e58bdbf0e1b90672	1584124542000000	1	t
2020.073-038FRAPFCXZ9A	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538343132353434343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538343132353434343030307d2c226f726465725f6964223a22323032302e3037332d303338465241504643585a3941222c2274696d657374616d70223a7b22745f6d73223a313538343132343534343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538343231303934343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224258334d4b4830453159504630335031543247344e4b4d594e48424745315443324e35503652574854314a484e58433332454e30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2232445a473932414b57385147575139385a483130483746595a46575459304238453248504b3934395a364532505731524a4d463343483047444e4a41313433413056514b363843535230333230365a37524459445736454b3230584d3245414248314633595a52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22395a44304b4b5157304d39415453593435365845484b5352534250434e443751585a4b3944384e31373532324b59464448434547222c226e6f6e6365223a22594d4b48523146334a50374d4232525839505757424b475258364e4d354b45524648425452414859304d324b3538535752455347227d	\\x06c4c1f2ee5260b7fb8bb1542fd840107b046cfe46b05923d205a5c03f03a3d19c367ff4c642be00989a36d3dd48abb6b444a7566897902b5d62e6cb01e10edd	1584124544000000	2	t
2020.073-00M1XHBR2J7P4	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538343132353434353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538343132353434353030307d2c226f726465725f6964223a22323032302e3037332d30304d3158484252324a375034222c2274696d657374616d70223a7b22745f6d73223a313538343132343534353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538343231303934353030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224258334d4b4830453159504630335031543247344e4b4d594e48424745315443324e35503652574854314a484e58433332454e30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2232445a473932414b57385147575139385a483130483746595a46575459304238453248504b3934395a364532505731524a4d463343483047444e4a41313433413056514b363843535230333230365a37524459445736454b3230584d3245414248314633595a52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22395a44304b4b5157304d39415453593435365845484b5352534250434e443751585a4b3944384e31373532324b59464448434547222c226e6f6e6365223a224737384d5741435750324d424a5a36594b5339444e5a514546333248323232365742585a5a5342593330324a48364150574a5a47227d	\\x2552601dc511378133958937eaf4e1c6cd934cefcdfb1645774ca60278e386acbfa6dbfa6062e0c55dd09af197ba578ac715d74f11015c95b51904fe4e5adfcd	1584124545000000	3	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x61043073e65af0221d1c95ca0a32917de5241b89f81678577db4df852e19b5545a11b0b1d5f786917fe0df200159864d78c575ce57421112e58bdbf0e1b90672	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\xda43e65bcadb947221036c387da292da2642c97961f450027820d0d9d5ab1a0f	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	\\x211946babbc3b7f23a87e5c3edfaf2566e556437c95ca68965a69073edfc07be	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2242564553504b415043395447594d584e504748424b575245394d47344e3542423643434b31323456363958565a385435394841584b44485352465734375930373734433833564a4a5a4b36374853363458304658573050595043433159434e5037353434363047222c22707562223a223434434d44454e565245565a34454d37575131595659514a415351354153315153354541443242354d5438373756465730595a30227d
\\x06c4c1f2ee5260b7fb8bb1542fd840107b046cfe46b05923d205a5c03f03a3d19c367ff4c642be00989a36d3dd48abb6b444a7566897902b5d62e6cb01e10edd	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x9c73b669f228b004180fdcf3a9f33afdd000fddbaf12688eed6e3f4c57cef523	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	\\x211946babbc3b7f23a87e5c3edfaf2566e556437c95ca68965a69073edfc07be	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22465450344e434e3431344d42333942564458413833564e4846375a3334303752364d364a38534e4d58563546435046583647425736354348325957473434513130474237585a4a4646413942594256384733565145514653565834593038535a35325457453338222c22707562223a223434434d44454e565245565a34454d37575131595659514a415351354153315153354541443242354d5438373756465730595a30227d
\\x2552601dc511378133958937eaf4e1c6cd934cefcdfb1645774ca60278e386acbfa6dbfa6062e0c55dd09af197ba578ac715d74f11015c95b51904fe4e5adfcd	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x0b11cfd1ebfd067d2cbc26e663f2f814a8b5e9a387667adedfc15006b5531b0a	http://localhost:8081/	3	0	0	2000000	0	4000000	0	1000000	\\x211946babbc3b7f23a87e5c3edfaf2566e556437c95ca68965a69073edfc07be	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2234393546534e3248533635484d323352594830534b334a56575856415939505759314733545450385750465139534252484b5358303032414b5253384e574a4b3432464350414d3745334e593830313857314b47563151324550515347574156374e3659363152222c22707562223a223434434d44454e565245565a34454d37575131595659514a415351354153315153354541443242354d5438373756465730595a30227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2020.073-03CD47SDDBMRY	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538343132353434323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538343132353434323030307d2c226f726465725f6964223a22323032302e3037332d303343443437534444424d5259222c2274696d657374616d70223a7b22745f6d73223a313538343132343534323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538343231303934323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224258334d4b4830453159504630335031543247344e4b4d594e48424745315443324e35503652574854314a484e58433332454e30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2232445a473932414b57385147575139385a483130483746595a46575459304238453248504b3934395a364532505731524a4d463343483047444e4a41313433413056514b363843535230333230365a37524459445736454b3230584d3245414248314633595a52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22395a44304b4b5157304d39415453593435365845484b5352534250434e443751585a4b3944384e31373532324b59464448434547227d	1584124542000000
2020.073-038FRAPFCXZ9A	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538343132353434343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538343132353434343030307d2c226f726465725f6964223a22323032302e3037332d303338465241504643585a3941222c2274696d657374616d70223a7b22745f6d73223a313538343132343534343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538343231303934343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224258334d4b4830453159504630335031543247344e4b4d594e48424745315443324e35503652574854314a484e58433332454e30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2232445a473932414b57385147575139385a483130483746595a46575459304238453248504b3934395a364532505731524a4d463343483047444e4a41313433413056514b363843535230333230365a37524459445736454b3230584d3245414248314633595a52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22395a44304b4b5157304d39415453593435365845484b5352534250434e443751585a4b3944384e31373532324b59464448434547227d	1584124544000000
2020.073-00M1XHBR2J7P4	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538343132353434353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538343132353434353030307d2c226f726465725f6964223a22323032302e3037332d30304d3158484252324a375034222c2274696d657374616d70223a7b22745f6d73223a313538343132343534353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538343231303934353030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224258334d4b4830453159504630335031543247344e4b4d594e48424745315443324e35503652574854314a484e58433332454e30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2232445a473932414b57385147575139385a483130483746595a46575459304238453248504b3934395a364532505731524a4d463343483047444e4a41313433413056514b363843535230333230365a37524459445736454b3230584d3245414248314633595a52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22395a44304b4b5157304d39415453593435365845484b5352534250434e443751585a4b3944384e31373532324b59464448434547227d	1584124545000000
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
1	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\x06c4c1f2ee5260b7fb8bb1542fd840107b046cfe46b05923d205a5c03f03a3d19c367ff4c642be00989a36d3dd48abb6b444a7566897902b5d62e6cb01e10edd	\\x9c73b669f228b004180fdcf3a9f33afdd000fddbaf12688eed6e3f4c57cef523	test refund	6	0	0	1000000
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
1	\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	\\xda43e65bcadb947221036c387da292da2642c97961f450027820d0d9d5ab1a0f	\\xce68d5436fb8696ba93b63a5e41189bf086c7bbd5df1e408f78ff92da88b8d7d171e46f8bfafa4ea456fa063248d2bf13bbb4f8274fc9f08b6067b0cb2425f0e	4	0	0
2	\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	\\x9c73b669f228b004180fdcf3a9f33afdd000fddbaf12688eed6e3f4c57cef523	\\x86edaa88e64050d9c970a86199ae8224a5c36af4593c12f1e3a141484f10cf0641dfdb58fedaf60a548674b3eb1d458aa20d6ac0e7d1e6f50cb58d348b66420c	8	98000000	0
3	\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	\\x0b11cfd1ebfd067d2cbc26e663f2f814a8b5e9a387667adedfc15006b5531b0a	\\x5288dfb612ff514caa7494a42f652cd3f0c829352f313d8b83c3f5bca01bf4aaf0377a81ddea348bf2e10b5bb74fb42afa8437cb1f26451645cf1169f2602306	5	0	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	0	\\x5d757d8ded464cc535bbff5c7e06cd72001e40f68dd4643b4ce5e331f57de481e7de40e2d3820ca75c023d8eb3952991d2c3d096756d4ff461190dd1f401060c	\\x1e5e384e59ac0bdd77b086344af2985d8a5b1d4e58804ec47824d3d37a5927e0cedf43c55ce4051192f089480a1c61e31393185862e4781e563659684ca9d61e	\\x29bcd76b9b306ed48e2aa57d2a247b4ee6b655212eee8d51674523a880058369d03480bb7ae91c3ac1bd921ba3428c8bfc0941d6973180a3757591b8e488758a6524da8d73c3cd70b1cfd7a31109d57255f6d9ff55a59440c3705caff16d9c81e7228122201ed160fa78d540a9aef1a60e2f026a8796a0f1ad483cd839353ffb	\\x6616e66ca7ed72a7130b14ec3ae6775edc4edd2f673cf4918aaf9b243fa96abf7581f081a1ce31b6b6d1d02448d8916300d11d17f957ce1d8897edc5d5387848	\\x813c329cd0cf659cc7f2138499735913c63060b37bdc9d43af40de29d5101b2ab7f138cca79a97c2acec1758a3086dc7ef876c514491f97b83da03cdd37ee54d802689cd917207200c498430e76fa1c6e7a6352526c4efdfed281382204a8addbcf12e8c01633c22bcaa1a2308944de05e7f2f24fdb52b18868ab4959cc65b07
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	1	\\x5a56609f221a13e60c169eda62547c17010f77a5e28cf9db0a260d515ebbde3fac03012aa569dc2b2c18a450303af9439f16c636c6172bedd10b82e4a3e3c000	\\xdaca7cdc05a7e781c04ab1e233ca2664bac59caed67e4d00fef43e31f191487a7cb91d8b862d6f9329da670ba79e6aa599de8896a6032249796f50870eae3933	\\x67b94720ae891e31b0587e11758b73ef6a50b08088d791646eb814a0870d42157d7ee2b83f32f0ccd6d9ee48b55907d031f4771f0a3f5eb35e914c1e52914055f07d2c0ecf34bb1104313b039f815fa571f121b953ca9a6a35de2de48c5efea3b5f0d3f288f55b9fd133e23408f5f3e68a1e77b2a5c2450bc2b2785b8afd9123	\\xc113c1a21b902881c40078d022f793f7f40a3a39d85aefb8e93dc9b9283f151e93657ce69691f22df8941d5597ce6ead01535e48167a517c9614cd4dc7a03567	\\x937002743c47155cf5efa898ea9cdcf1745b4cdfe7c9264abe20ef21566c308a86221310ac6b7c90abb3ee8a7470ade95817c7bd092a7c41c4d74d2ab982ab4393803df9fd00b38d5a68bedd2255bdab69f5a16b62ef18ceadd3f7b787c4837e5ac10f94b5e0fde331eade3dbcdc180f2e382756688eca813b691f2f23c18762
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	2	\\x85674d5a1d5d66204adac4f41b2587397c8ef91cbfc73c1926774250bf62a357274b87b34baec80fafcb1e6c5b5afba69b18086836a98bce5fbcbf025fb0860e	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\xb813ebadd403e28c505f9b36513d5a719c47930c86dd26728d2385b5aba6aac9c73a9598cf7f8c54dabe11fafa678c43735cba362c9d6a28cf6262babc87e27a44a0ef1ec5b6169ac27af1803e9d7af346afe48ea090b01c1a207ef810737d74ff8dbd653a614bf68eafe246f7e0f209b86d2ba5dfc0de51f1c0b10804e0d26d	\\x0b633e3e3c57b1aa53a778331f622a144c9411faa4db92616a172bb237d27fb2601826713c7edf589e1b573eaae8d0df538cc5ae1231a4c2c82f2b544f11ed5e	\\x9a3ba41a035d440a040278495296e4baa3bb3f40513a224e70ffad2a1b286c298b6aae912b73e92d59a874ec1269e3e30f4c62711b6ae3d213e263b9f5d1f6ab046681a53809ee5783c9fb1db30bdc156a5a858bbc413e9f095663ff8fa7917c6f5c3cbd64b3ef3558cf9467d1c217ce125e021abe951055a5ce75d716e7f3dd
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	3	\\x762c3c9e4f32274b6b4a50fe2ca43f0b99f9e3331a9697021103bc7ca3c96a51c8c8c7c2b01115f75572c756a75298f2ac54541585945fc471116615ff39be03	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x49c34a8f419206f64259ac19130400bbb024dfc05c9c5fd2f1038d9cb6d11e2da3611fe1bb6201480f39dd85931ebbfdc43884c42a262f67418a33e1d6d807f5f137ec3b0ea1671dce701cf18b01e1a851261a306f24a94681f14755e93d7f0f43dceb94876c51db027c9b8083448afe98214c8cbd3f9bb5c41af96bd19a2e8f	\\x8e81f8caa32e728c1fedd0d22595e13fd1c9f0faadbc544a59eb04b2d64e0a99b87b9fb9a157224eb32bb62ef19121267b35c88ef3f063ef869dc5dd8f3d9f28	\\x63d615bde1ff8d67b1d23cd41649329b5ee86dd5ccb12cd15e5c59f53f2565af6fa73591946f970c6b5ccfba8a3806582b99c944d7ebfe53494fa6f007d0bf1e5508803835c625e8cb6ebcca58827dcd72cd9fece97727688f4edf86ee3aa8ab0c3c324a78a69304e5bddbdfe06a00dc1e1e3e436a824569b001905c2e9ea33a
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	4	\\xc3fab254b784fc6083d1b358dddc5cb55f9df8896d95c7111dc607042d0e31d598fa7d97c66c576fa4d7de6b380634d84487f7d15689f9113d5fe34635ce080a	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x7ccdf86b1ed6fac9ab765d37b20d5dcc607301b69f451af8627faec8755c40824cc65ea79ba58d9ea124a751543940b4d089019d63e621dbca6132f4e448dddddcf12d785d2a843045dd12881dc864a8b0e44e022f3ecbbdf050dcaf8ab695e26c17357e6c33e9f34f3840f5b44b410aa9ac2c26241ade7d4de28525ae877f44	\\xd13c9d50fe4cf8d5f085705ad6817c17b496546c1fee4bbe340bd0cafebd25d5850786829e6adcd4e6538d7cb5227f16bb73aee4105e3a7eebe4a26d94953271	\\x44e9a725f8d033946cdf68ec332bfbfc04a1c0aa48de078bc94a6455c8dc912f1788d1470eeffd3ac68e39ab414096b0691005d9d8c37500e33d452319f9ee23443e88af4542cd5daf997b0ca54d825ad0f31ca85b075e214c6efbe04700fca3830e791036ae7206b60ee30bc4374eb0cfda5f4c5b5e10fde13be6476b6af248
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	5	\\x1e925b8f0f7086d88f720dd36f5d0992cd7c0032169e83bb35a0c4aa204a67990ddde826e3449eeb13f2ae9488aa0352d04dd72236c12db04a5f66f9dff1c007	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\xaca3449e8ef650707fea1fcb024ed31d0347bd9a1ee7e950b24b9d455da4e13a4a6b5fbbe0c9bea099c75bf59260c51c5dcbd81e136e71ee4399b81509ea679e2aac44ecaefe72bd7ab2d350d8beab76857d9652ec3e42edb846689153504c9b200ea30030163ef54b2bf42ab7de88e1cdc5ca205e8161b8ac85f9684f267dde	\\xe74e6977f80f40004c0444cc367b2a477c41f741b3aeb7a51db1b0d430c3de2d363dee86280f89d0604abf7e7c1c8f06c81b62cd592d427d155f219547e657d6	\\x391d8fd2c23c32ae8517902229318cca11afa486bdd8d5ab45d1b6521726a0e5eb70116070a9a09827a1183be23cd58b7811383f1b68ea430b7667a8ae64f90189087bf485e648590c012eac2434fe024a512e535ac324a455d74eef0a5e97fd8446220a238670403dbd46e85933e083c128530cc5afb803b3271197d260e8f2
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	6	\\x1a45b240f4826bc117cc1e6eb40b336b335ef0a8e9b39b0ac80a86a9f51f8a32da55e62f4eefb9da93d58d7b8f35741f15bfefd9cca040bafe9efdaba1b5a404	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x5a997181b752affc30a943efc6ee3796a7f84d32f0448d8095c7bd9bdc270f3171173feca5c8f2a864992db02d2f7e5050c3b612d490d6f07eb84f03d22780b15044f338f56234f371ee900f121e1fe5f56172b6a513d24c4a013da9d9525bcdfc3aca7d300854c996a941f2b53063cc35b8115066fb97ccedfc284ba8a823b1	\\xccd35d9555c4d3c62340f260ea2cc6aa1019526b2a188cfdf82dd4f4ca98b43d6837c7ccf043e6666fad78f61177ee6b060f74897edcd875e82343a4a000ed65	\\xb9dd00db9e450f9414bf0db6b8847b90652f5ee9b23f95b2f89fad6ed273aa0f6492baac411a1444e8482c99515231c98f877b23d67e19496a611bde932cf3d780fc1667977c2c0fdb44cd2ac4bea55fd5cf2a0b2416c5e8a19480bb8f5f1c80a4077280b980909f240e9eadabc733799a789fd9af5f3319dc1cc5e85bd1bc79
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	7	\\xf6af907a7221099d88723bfe887b5029165ecb3175e7e7bf0592f2d017b368ac207f26a76bcfcaa6c5aa613e4c5413bc0f6111d85652113d3927b631a3cc6105	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x0795e25daf7c8630e893af5d3cb36de449fcc969bb617d356a5f6b6f26637ccb696238fa45c637c7598e088565f89deffb960532c7ecdbb7ca405539eac0f69df9840bc23f8ab4d65acb3157ca933633ab6159727e38f49e650ccbee7fb02387c6fbef5175374b045c6522f461beb67d1a844fd0c0dc402068b39b2b1bd8646a	\\x593c1dd249d0c95de7fb89a8f82e3571a37a2ca12603563b572fced2e7d250cfe5cbea656e1fc44fc2fafeefb7d62f44c4d84ce86dff43cbde0341b4849d6e50	\\x78b8279654c30b9eaf590a7d61770ffeedf31022196e1b1b982432e294c745a9106148fd13a5f3720b16704c6444e346504707fc5502099bbc56d11219b5037039d5c71398ee2022488e45f1a36ca7bcb25a81daae100d6e01165ba3b6efddffc4f01ccc0116760128028884005041da25baabc99f061c0b2a8ea16a7e0a369e
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	8	\\xf3b3ec15b3624c6cf4aa0b508210d5a63543c332e53d554773c67c29626e82cdf64b310c4dac0abfcc227f90c8d4b083350f674011dbe2323205cbb885482304	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x1f7bda798f2113f9e3c2f7df93509c54f1c9498313f2bc7406ae27bb4e08416eb0863360aaf2f0392d4fff868fea77d0954830eab1baa1335adb59b9e648922b17fd2571e237ed13f7d6e39c6723e234355776fc9f23a85731737f0e4ee3e443b04a02f2e5d9da9a0788f6c49d4f575959cba410d7d8d9fe17035a2f8755ee1f	\\x523b80fea69dec271f1095be5c9cd09c0ade706bc4e99f16fb38fd9604e6b79339d984bd2f28d5a79465df66b84556e493da0e066ea2a6edd3e2fc065a8f228d	\\x9d751214a04e11737042db7d5d346bf03d67c38bf1feb8190c17beca528d9c888c40909b4dd818312f51addf9559e59f62d4181418f56fde2dbfacb1912cb68b00ca154a1a096d3f4061df700150f658d240350c6f9e004f67bfa594f5805a51c13b0486670e1b7f31e5142e28d2466fd1e0ad0e6d233bdca22368dbff9da0ff
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	9	\\xb3c397a5aeb2e185aeaf38d987c762c68dba30bc2d0bcb6a7c43742abcb14e520530a8f4bc38ccd69e63c0be75d40b63a50ee18c765b5d82e86b2a4ebaec0704	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x6c5d135d20d976b2171e6158996e4367b1b79b8fc1247844f28cf7b304092b432d207e1dbb89dcb8846aec027cc16dacb6ddfa4aecd06a9bde62b86daca93c6dea6302e8411952682adbdeb6440d03383703060912a6d8841aaa1b973090bd9d0d46fe6a0c126ce3e73e45d328769ecca36c570e9b5484d4515b50958157203a	\\xdc3ba1114d4d37ee8859eae0b39197808c2f8724786efc79c3b80ae9e0b27f551b8334aeac0c5cb0cd2d3bf539bbf1f3d4d512efca724d0e6df8788cc42056b3	\\x831167b67506962bd9af02ef40824f13d66035473741b58c8d3c5173dc7866104395ae69e111e50b9bf330bb65f1a028ca4f0af60f90db17ce60b19ee2e83c6f376259809b7c32b3d26178f767fb7419a83558370ce53622314913fe5a6ad2abb40fb52a424b70fb85207dd9e3a4e8ec9dcc4d85584b19e8c85afc9a08fca339
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	10	\\xd8c58be2dd15c706938af45b65705e2d94456d96fe1f60a47670e32beff58b45a8794aad5cff585ff4a5491c467627efcab483b06a303685b39aeaa1be263109	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x253df068a7d6ddbbd71bbc424427cf86cb5ac66dfbabecd85a45a3d7f55650e696774fb74f972089ca301ca8a21c123dd960cc3fc4866d74997b148c7d49f1867ed927d5c1899322558f832fa6bd85d13c880bc7b13e4a2df137f943db7195e64291e72933490574a6cb3f1b0bd51e5cedd9e81636b0d7f591ccce2c423dfbc2	\\x55bf93f053184ef6de32a6f183d00748db8e9e737252beea1060f865ae823a5a65b5344cfd537f8dc07ded828924de37d91b9a58a17c23de0cddd0c9eb95f7e0	\\x06a64fb64c50fc57ac5599d48da5712fb04b70b62b92ff45f9b75bea093b1398e99a1c682ca456ac14ecb8c9ce89e75a23d61a883a1f4d58793d611330bd8f4992fcdf023d3c36b6a0d36be28b879070bb60f43b36b3d237fae5c51862fed6142276db3e3dcc2655b64fc5b1088c6b2b5ebec364c81f070d0c042bdb1321d120
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	11	\\x058e8f11a5662c2e7ae39919837587018cfd2d2c10f01d7814f9353367a44a3f2f161e35283d3186e6177a34e4a5a23045518cc7e6de2d68d7dae663858b530a	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x5ae1ddab42247a51044a37095f826fef1f525dad474a8fc382698818da05da0bb066e03375c5348d062f77f16ae8337e50a67e7384ae1d70e5c88b3ddf9d7a903aa497ced46306fbc64141ddfc76a927277c3a595712e75853c892cccdb844ac03742b8d4b44d0fa75e3fb85970f1ab44dd441101b014c8602f823e1b82bd43d	\\x98da81e2bf94b4e213e09fa1aed0a4e74b71f785f04e04cd1b6f70efeef6d1b19d1b70ef18c78540fa48b1e826aaf9a1cad5a5db129ba91c0c63185a4f6126cf	\\xe3d4cc0241895a1953cfc5743a42eb7ea1fb8e183b2b84288604ca226e02d3645dbffdbd2126446ac93a91be93fe33d4ae3140830d7e21735c2ff81ea2af38dd214d41d866be6477ad2300123b183ccef70b8d97aa711f53ad9b64c74a8972b9ac9781f5fe86b4fca174afa644ae0a49b35bc01dd4434dc3adba491030f6c926
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	0	\\xc9ff941f9cf7caa2ae2630dd1ac6bd69e6e9ab045b00294722e63988f787b9a8c2fa90cbe743cbed4fb29f56a1e08c9ccdec641599bb9842e0f1275347a2ba0b	\\xe2557e383c1c3c019681c2521d415a758f1becb629a3a75fd9dc212f0f2e802aee81e71db725f0f9913bea0f913978bd7d238558712aa957d80c4e1673292b13	\\x67c6c2c7470fbdb3a65f1950d19738fa6357ad7cc86edb4498a75267ee149e143486cdacf57323aedf52d1740606c2b600a866f8c5390d2102e4fc840a93789eb97104d82d85fd184c5a58dfd096b7c06b18d1a276a33c4b42aa568cb81e4e359c5363c5537429048de27c76fabc8efccde75b2cd3826c595cb4704f567e003e	\\x77d2a3315f90ab944aeadd12f955de87a3510f2164fd8087a2a6c530a32b5f817fd7134454bfc8a8fd858d104c7897da355f5a9bf545688f50d9543b6eaa4a0f	\\xd251081b412026ba4e8015422435172c32289b6aa8db52f0c4b7deabb15ee2c6f153dd523c1eeb336cea66102b9bbd868cd8ecc0ca321f2b4e8c20a31f53f6eacddf8839ae7161ace6623800d55c41ada6130cb38ad3c9e44560d5193cbb4bb3c1f85cd94aae047282606a46e714964f8532d05c32f7a46959206e3cb7b477b7
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	1	\\xc81d12035061e98cca2e6982e219d8a98b093e91f27557459fb8a031fce1d90c94d1fc92f62eb9a4c4ea349314be1094908422d8a170ad780c617c4f484f7f04	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x19998639e81429659fdf6c006399c0a0bc3272af6d34ff18b6ae5f416c30676fdbdd9f6042b43d61d69cf6eaa2d38c41d0d1322c9bc38e9ce0b757ddb48f0319b82a543c425f97faa4087793d6bb83d006ee443a413639a4176cf9fe87d2b7483c08256e09a56208e74e0dec0db436dc354dcfe89c9ecaf2624bf62533c1789f	\\x488d132f2097ddbb675192cb4a0b96a6480f1daa81ebd7ce31cd2f83332ec65621b1221051980d8dc534c4794a27ea0062a2c02a26f633eaabb947e384176398	\\x43b74f01008bd3e324d40b04935c8efe421da4ab5f3a10d350705dd539c17e5150177e66282c35f0af207bcf61eccbb77883367f99800c1b716ca2edb2db5d5877269cd7a799365d821255ebb8707669720f7d571578902d899eb3830aa34242a6c4f8c684fab58df05632ded73b8acab269628972878c97574ef9127a06abe1
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	2	\\xc48ec00804a5b6e7f974e85a497b68bbf961ba2db50d8435a16f8a38c3500853726e3d38e81df367e50b9d502147fe7a269cecc6dda08a72a3ade01b5a877004	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x01c316b96b8e85ef2d716d93f6f58d3a6b1c5e0935638bb58c3a2f10338c2db42227ff7ce32d83a71d7b3de756aa538b47208c43a677cafeee0cf7ed0778574b439dbfa70990bfabdccd1b019867fb5d7f9475cd27890b9e3f9d430e3dd194edea54ef86a83aa2e7e6c771f317ead7a9600b78e620068d4549bbb7cd76e6e5e4	\\x5bfec2432c2819b08aeb93fcd5f0652bc042f26a50c47816ca8000d4548dd4166615fd7679ccff250d5a5e8fe438f3c1f464ea25e95e217ced771f9e09cdbc66	\\x770924e6b4cfe15ba6a8f12e243034e0c34a7480e9a2c102f652b5ccfb54f6827eb754e058da8c8f263b2d323d5bfe357b06ab5414f8c1526e4c3fe1ebdbebe11a405ad6538c6d7a41ec2860b2c1a5e316a1a551733f61cd9ccb558948e31de8b692d2e006713aac924a0f6c4ab3a42ddf2b54cc3a37167c5c6daf65bdbd1731
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	3	\\xb02923008152cea2db5d14b6657990f533808cb8e1dc67e345e3244d604502d17e5a7ae7aa3f2ade4d1de0a92a6de8f959f6e757a7bbe73115feb83ece591c07	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\xa3129304e20212998064a10be845deec89ac8854459aecf29d6f4aee90bfa9f5bfe3dcf47136fcd05034e61edb572f3296687e407a44fc1cd45082b3494e81ef6e98e5dac00a10293eac9071ac0244d63e6607db8769fd4ad328c852f11821d7145c690950ad1390d776b8f896aeafc55399039f22adea9de225371f28167c49	\\x9d18240f5cfa8d36f9dd81e63c425e55185f73557c9f04313b2824f0bdc047477f9f7f0f03ed2f76f2fdb80ed59a77be3ff8934cf2844a7cd8f413f4e8408ca9	\\xa2c75e553ac34431a2e10a29089e048ca8b2352d7aa4d592f82bf6a2c5ab0264ca3661d5f18c2c8c083fd4b573d33117d1c75dd5a130c3359b5b678d5666610259907f9cb4944db0c7e472c068402373cf1b20dced0e648578741d0f2093a6fc867d7d431beab2e039af4b0fb1a8a71c4213bdd635f9cfe4b4043656639496d6
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	4	\\x1148ec703f3836d250f2a8f30d20d3fc3cada4cd62dc95ad4d51500f4173c7ed0ac60d2fcabceeaf61ca5dabe94e3aecb4f769676c102d2f3fe20ec2172a780e	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x0ee06d4694680c476c6e10f89e8a736d74e3013726ab729aee56881c8c438ef2bdb429a87c81f9ac6f84e6d8c53d9684306a5bc0bcabe02934056d32870403fe04d735e42bcfc72669532b9aa9e7cc4dccc9b7bd22062d170753177fc61109c4dfbd325931c4f63956833ad543370500145f3c4eddc1bf6770ce0a185605b56a	\\xf485cc75a8b25d075aadb7e6d4f90310bf399214efc3e4a01a8e0b650b5338def8e232a46ebe227eb6171eb360113b3ff43a938c3f5d761d1cf2fad6aa56bf95	\\x8c3055cf0c8dd2033f83461dd48424a325f5392fb55206196dad27659fc4eb3ce2c99819bea4b084d475ccc2a51c869ba9a983c9e86e5eb3451171edb7fea7984dd50567f810a0e5669011f763e1cdd42971796e9170111fb465f5449820ac86cb44f6aa5695df07bd9c9508dfd0bd184c961c4de9809d8972f38d1bf8127077
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	5	\\x5d0f0b223586c45ba70b8ffe37220e26b10253ce8b46fa0c3de51a15bb475fcabc29230f626dfdc06d81b62b1ac492a9ab40f411587a4a47600f3c3f098dd102	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x2a102c4fde797a6d31e30a8053cde824c71d7cf000e0cba76403098e7f7278b90df4435ac0b44c6549d16d9bfc40cc2d85683873bc3647a07195f62f5c8a7618ea14ab0ccf57a85e48f456a68738c1952327d26b47f08d610db602c033a54b11a14e8ca02405bee0f1a4da3db1da17f8d921c73344bb3ccc8803d06861e1a253	\\xbcafc6137c2d5cede85e09c4378b6f83e9db89ff8cfadee7d82dc5c81763bb9cf491fd79911209e8954e6af885572846b94f04c6b942e7f20febcf2bbd330e18	\\x2cd00ba24bda8d8cc8862de83f4b8d39de58f8ef929304eafaf2f710c8f32e4057de9a25a41597cf3c3b1da713dc125c4b55b02671d89a4791ac4b05bca092283e456b0e1cad4f73616568cc9fa0508a9fcd16d3be34b14b38c7a22322b636faa3c0c05abcfeb151623e45d81e43731d09dc025475a4b71a5638dce09e2c4e57
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	6	\\x377e84c3960755fa37310a10545b32c6c7d14b7d321c36b269e45d3785bd3b153af776b034283ef87d522d3c2c79b49c6d46a1411a268f85c942fff9e0af9f0b	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x6c8f89a681a8e4e50d7db49c715837dc65d3405cf15d45e06043ab5376302a1f2bcf31f27ecc574c84ff1bd48d32388177314cb5a0fad5184396b5e57a3d4a02c280b00f0828f5d6525095ef82c65f18275fabaf4bd444c59baba42906e89d03a1294c7a6111ac9ca1bbd2a61a52c0188b4b7d5e37f5549489eed4d48e56e3b7	\\x4d0e88be5f86ffd76ac4f1e76bbad5a32a3df48bb331a2b21766b0190a4560a439278361e71a6865fe49051071940afd9224830b051be9af64493387f839ff48	\\x0949b533f71753a775ba4a5cc9565f594456c69fdfb50fa913dfb5eb05862afe0c17729d14bb88c6dddd4b1b8b95c0e946d041796caa28ebe9bf5efb335db20d19696deb4da7c603a8f212fc927fe48ddebe600bcb8615b5b2ebefc5392c1cb7554d71421b4355adc6cf27b6b2a070b316bd7d3dac5352ff86a5acbc0ee7e055
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	7	\\xd3db6a16e4c76989683799a647e8ef5f9ef5636ff0d368dc9c0a002cec75d56b804f1ca0ae62cee558c588a99a81cca36d67247cb37cd299d30974f569465804	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x5c20d8aa919a3c79bfc6b1fc79898670ddad6e7dd6e1952ba3c15c45709764824b74b32b50ce3b52e1db8cd7c0f38f4c7844528ed1cc69a39916b418178eab68019948929f340a24c86d18dcf41a35c24c26eb354a1d5c317d0d24461c470c64fb63421db8066145cc0dcf7debd5a5a208f0ebc7b8f879817e2d2c9983a91384	\\x7ad2c7d0f0d89029119eb3728aad827ccbeb8c8738a9d0348a63fb27815e2dadbe74d76d2b6a9d652c3ca7ed79c6726c8b89f3f550398c42bfe53dcc4ae8fa2b	\\x6061d3fa816c4d773a39d11b76bc6a7792598d3eb01d6420c7bfeb1d203cec297becfd8df4ba6f2a7fa2e2786776fce0905412a381c1a27ebb8055c148b2930fb0d1856885f1c3e5fd4381e5cd6800c86c811e4249484f5922c902bb367166dd719dfbe03f56861b8c801f011ddbed10277b01ac49416299ea56233482d97ded
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	8	\\xc4a911677931b7be2587ce7253a2c3a87c7478a01714ef62f4e5977f84d5d676a0680d3eb7ca36cf3c34882108e9d553e9cdddfa37e08c1b6fde1ae8d150a70c	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x74a0ffe9db28559cc9a971e507221b13caa7e99f9ee7a0d935c27a4db017995a92f9a10fdc6eb84fb9d1dc80c2406ccbeeafaeedb4f0ce0a8acfc057e4f1d1e5838804f2c57e485a52d66121ed5d59efc9c030e978840a850a6f16e783e1b28b09a7dfc7e25f0da96d1bb18a18395419b458fbff83c85952a93618150a0d6cca	\\xf93c5e0eb6091895f3d13a8f48f726edf3183263524a5d97188eee8fadd345aaf950c05882de3e3d8a146f5dafba3a2cb26059b820ed0290d7de567d90c27dc4	\\x7999670d8a92a93a70124505f0d1a1f159996555b52ba58cfc1ad830b729f339a21b7ed0da6ba8005c2ed889476d6ec098e9478fa0db449fda5dacf42d10bbde11e92561eed5425d4a2f7608856907f64a9fe9ed7bf431bd5a0504cc4230ec0a2131cbd91a749b42adbfd4f0c677dee03d02f03bcf1f1e00c56981b01b5d9728
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	9	\\x9fe022928413f617bdb339824f2d7163b18c783d2e6aab345419c62bc0971ea590945493743cd191fd6f5f8319971ecc09c753233fa9c9be340a1365312f0509	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x56cae8204b13e2976d516b82a3d79099c4be2441bf4a6be89262c2db2dfbddd0f1d519c5a29495dbf822833e094d6211323c98b9d3ef9649af597eded1830d461a48b5fe44cf64bf8527885352ab0e262c6db3ce731bc331cce483869bd9701540e0f774bf35d9a2bbb7415e1c05ccd7cbea5ad50573b7bb30afc322eadfb532	\\x39bd91206804c8aba8c59f9593c86aa19b569afd2d62a27e3b91fef7736e95830493f7afd6471286a767fa1626069d7b6546a9faba69648e09da86c617f554e8	\\x193100c193a302acad57caca4e3598b22061449dcaba7c6c0f6ab6363fc8aa3001442a19b8da368aa59532d6f1039e24405df14deeb95f0005232b488ac70f15d901d0cb8d7019cfce969aaa42a9226a49699a5e0229a9829324022416e1b2647695429ab1c6f46fe19d0ea526235c91b24c051d912b82544c3e5764dd667197
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	0	\\x8fa015f01274a235d1ae6cd2730aeb05af565c05b44516832868f09acb5c8f96e4cd8c75f16c616a9b0b94f3a440f5ef95e70ab23a423d21a149f2e64a0b9909	\\x597a8051c87010b154a8dfa6643279b0c166b51539c69b9cb19af986ab521ed59877b3868c0e56aac00ebbd6f1f3036a6b667403fc032e32b5589ddb9c257b8d	\\x3c513ec4c410ddc6ff8b8de06e8ce94349416c4f274049bf6ca233acf24e4a7806bab05842c7f8937be0c6404a4813914990c14a78d247c2b70e6533bc90d986d8e9ee33b9b0c6e6f08651fa09866505d161ab26808cb0d0a95d517935523cb8b5db5fa1151e654cc68e21b0b8cd00b39c3069fd379c4b409b5f6d38d26f3282	\\x98450f9a486dceac8195c251510737fa6a7b7e0b69ec5b62715639794857104231751873ddc43dab8e906befb5885c77544272bfb358a223defb7bdc76d928ec	\\x6ac58663cafbac9207066b555496370c01113fbb69707bc9272df6eb27bae5c965b54821f3a731688c9e7befb3a432e1050d9fcf45570f53002ee3e4b1a85f398785fc19405b2beccb76655011926ef93f3315d2aede7b32ddbf4a7420e5c034efa6827f42f7bc194ab5c66d049ba38d2ef688adba382a1907397d9ff294f795
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	1	\\xe78b1b4c9ebbb700f6b93b07aa5a1113e9ac6c47d91155592a4349de03d5fb5c2f1bee591d7d57f9791795376d5dee6b4d1532fdbe41995a0e5c137108e4fd08	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x5e2d10765c803b815492fcbe61ce4c4f99a2cd3fb8b9eb669a0bf460897fab5eebdfb80b315a1e6ce87e3ce37dc8182183a2c1139d66dbf06879f164994a13df530d5759909ba8e2f76805788c705089476ea54373631432623e98f21e687550d6cdf9ae61cd65804c1f527eebbc35c818654efbdb60e954f6391506000f30c2	\\xec4c4821a3b34e733c472d4aba6c998ad41a3c29290008bee1c41cafb8227a4bdf8810b1f086fa45300f2bb5eb0db0440c122a0c3a0f353e2ad971c926fd49d1	\\x61c6639071a155fbf0a2da44c55099342082e7cfe633139fd92ce79c44f042507d1ea53083b756243c04c428c538500173759725b28adda3c96fd729921fa683f033931e08b30e07d4cab3dbd73c5a8fbaf2271bf97fbabbb7f2e630d44687b2febf2d08eb7bbb86bd065df4d3c5fd9649acf74f397a7163c3b4c2edbd0b264c
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	2	\\x22d56c30bfb8a46e93b88ed3e619d8a9cefb25e81fc904350215bf12ed9e472e64278a9c081542f221b8d7b943d4ba701efcb1b28f5bf8e1344d9d94f8cf8e08	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x87e08b409c650f96fc5f44b709f89d495a114b2dfaef2cc080f80daffd31b10492d730c1ac53f4fcf0c6e38eb85b2b0c2aac33f901098c6f0272cb358d875d14e2bc11c60801ee2d5a2733c52d4ecf5427fb4a8e611ddfc20749f0f6c88ae48074fb7979967e9a34123bb5a2ee3fb37a1ceeb06d2fcdab2af55088806679c8e7	\\x894fa356c00c1b7d36add8922df3880a9fa6d709a4e533e0e29f6903ae37c0a6f1b616882b6e675b16cc1ec1208c630ee3b0920c59c2f854767374ea8f0a2a77	\\x888be3ed5f97e10aee99e9f73c2121372cdcd45cb261c398dc0689b0a050e711c165b83a8fef0d931908900e70841eb4a1dd29d360c6875efb3587b6eb6fe1e7ce71293b5a85b7e11f1a1ce98fe389b482efc185570d10fc45d8b7b9286dc14f703a24252cd2c4a2f99e9313c14f9783c724d58d673da4b433eca1028d4903cc
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	3	\\x6eeb50565e1868f5f45eedc4e7c5c374dfdb0825a05a4107f3465aa04aea4f998685cf83c251040404cf119e0546f514253d633a7d412dc7814e93ff889cd606	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x5da5e4b8d3dbf9a0e213d9f0eba615b775163def1dd2c2ed86183bf2c680ea0445200bc1d5476dd15f94a281b3d84a642c52a17039cf4c78f9616e357872eed30969280721f230253c44bf8819c63628f7c2fdd146c268d9cecc976283b85d3e081970e1fd43463660e331bf96d64186a565943a3427d90511ceb565a6ff76e9	\\xd0830eb59217cc8158b8554fe2b397ef262a4dd95368f773debc5cbdf2714399a563ee47f2b10cd3f115aecc5501a6a0f2cb6fa4ca2c04d7a75a4fb5bb140da1	\\x09400e3eb9a45cbb85bddbf3d5617a45f19f96d74f722a74230f2092e2a35ab527aff2dd75b82f84a56985fccbaa34944de4722a295c94e3623e7b8a87e83c676e9c5001f853948f5a91f704017ecc55a6cf10957f177c163d45136d49d202e238ced69f565394045c0555c612d434a32697a7b4d6bd2a01c0652d96207940e7
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	4	\\xe5cf825054ada349d92b314f08b9a30a1cb11946656ba9908ff384caab4832e8933e4e62431e49fc294a32df3eb8b41c5a18ad17ae12a67f0443f3b04b6bfd02	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\xbaa409153fca06a9ef78260005e4f0c3da914d3a2428ba497a63df4873036c9e939e70cef5b5c934e28680a9f6b61b8186cf39b52e8889375d8c61a6a146b1e068bb6f9be5777ffeecae1b52d9d04382ec9cd5d5e11af9e2bb1006242e3d9c2c548af21c7cec554908082ac4ec42015f06d7996829fe4bf561bbd1d81570d54f	\\x3c76952dd67078593583cd21f2712f67fea0d9f6b7eaa5381ddd38f88d8cc048b87b7119acd1e7935354a05e6bd2de8e777d2e929b7e037a3d94f6000f96dd31	\\x68f553e5260beb10a71e40965cedcee5b3629237c5fd216ceab65c2c51ba2bbac68da670e9f99f094bc2f1ca34cadd4965f5c9e6a9e7d4ed35ce29ab00b7e6d4b59c1c5e24e18c9370f25c81504a54015c25f852d3d596f92a7c33c9e895ca01a8b7d888e68c7a712a784bf39155f35968b239dc2e9a73c1ad8f6397399691e9
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	5	\\xb5dba95165bc6fe856a37e9dfffae9812aa24eb8980e1ab2303ae801f385a8246da19abf3cb36a355965a6dbd14b3c6daaa2dec660477b42af9aaeeb5cdb190f	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x8f7755289e434a002683adc94e685c1eec5c86f5b4e362861ce9ae3b584d866d512bd6172f66f0f40b16ca66c54d9807a0de2e82bae12ae8575a718cfdf463b782ff249a3f1d84eafa3a2bd1b8d2df9a99352a08df5a9920fed906c77cf1381f88d50c11f1479a2fa3e061a4b81cacc89bfce1927901dd7e4f987db4ccc70105	\\x89f61956325100f9ab2528d9f9aa25445c83cf7159904602a4060233e49929b249087415437f08f37f1d34dec6c4a44e08d86a0984d0c304ca35d35ff523f47a	\\x241c8539b2469dd43abecd44e314fb1463283b863759de8f753776b4dcaed21b26f257d66a327f1382c375eea55aaef815f5ce7842a7e9bfdf7cf628568db2f2cf62dd1951e489463bc62b28470124ff2721535cab1041d40af7156485caba6044cfeb8dd5a8af6f6f67f3333525a256f1595be2a9bfcd28328a7cc8d19ad1a7
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	6	\\xfa28b91161591dd94f3391f3e60e2703028183cd45466e8443e5bbeb906ad1b1da778b9db001073f6fe143fe953693b6e2c293727019c90629dfa5028f321d05	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x97b90952c9f6fdf1f2e510fce2275f50f9050050f1fbfc6abd19ef429b447cdc010618793c8ca869e7b5efc6214f65f287615fb5f0adfd2d9dc0c247c37648069af93c12d7e12b0e559d170c486a110839ac4da9a21bce9ecbc0964ad2c909677776db096bf13f852c977dbb884e0ef50cca9e90a3da92e240642ef7e61ced02	\\x817d206e490344e0a99a23b05fe4f6d1668f60e0e03875e2311aa864c16490196fdc05a33dbfa36eb570a2a1a616c47143cb093f22fa8c65e18c59ae460ca29e	\\x748dd54e3b4ff3147fa2e99b9de2348e62cd724a54d8f43e13a3d49e063928e08acfbdbc8466de754cbe6d62f6fae6613aabcb1bad9ce023962818069d6634c32b2ef69223cb84feaa4ae51675b561c2573342f5177fe9957e1157c27eb5c9053f65afb64329c0d696cdb23b653465c7248e2314dee787d51b2d4a7d8771186a
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	7	\\x40f3c6bc97286e741ea369872937aecae9c8517f4f18d4527fded7c0eb271b8a28c3d08e3d1ab662c4c9bb55160053698e5b2af1ac5149762835dd7921fa960b	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x1c7da343e189ed46a2a02b89e8e7eff4825e9cf17ff4c824cd6100752c01fd1330b90002e521aed4dc6d290b733872998a64cd9b2ba2a4dc4fdd9f4348004eb7fcc4ae8872d2f39dd185be2a5de24c53d8bb419ca2807d09da1f06509759cab4eac8c0dbad82cff448714e13952fa8d7566ce623963a40feba967206b4a8e94b	\\xc6dc28835406de1daba4e35c3bd08e1e19e42a2fb46c02c9da1ee5167981f4cd9dcec457a1f050d005245ac685c609b275bd50ab36794bb7e88ed93ccf027a19	\\x66836e8ab3031ef27bab368f3eae8a132d0a7ab81853f502ea31750ba2e6427dcb37459f4f1c7c6fc489e561fa479c4ce969489b06957c6074162aa31ad736ba75829bef7d412ec4c985953ab7027bb7e507a1aef3c93498b83f8ce49d88d5159e083f90c3cbc4a8c36a0864b532d79314d97459c0984622e4d137c5aa1781f1
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	8	\\x4134b5fcc2deb08c0f5778192d47dc68d9375453f4cb86cb3c439a8fd921a5611b9af1d4d3b9738cc4e22258bfbbedcbce4035b58bfdae72040b4c7033993104	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x93628a46344628353fbab35846bf6dc8cc7b4cb9ecee206050b94172d310146fc3a33634853e164d901f85065bb35c5896ecdf70836639ac383dec117bee96493223e2d90c0b8f77a280d37e567aaf6d86855e4b71d094340ae1a20b39b055286509d8403d93696cf03f0e34734534b19e90414333836f90edaec2f40a592b3e	\\x9163deea375ef1879cb21df95088f266a643ce4080dffc7e674d3e43d8912feca7b36cdc6c20b31746ed7da784da79310a7091c5e0b533ef0e386df6c74be5a3	\\x758946da3129941f324533a9beb0843a5097839dba688ffac2646de9d72d9289aa3d19d74de8b8401e0de9edc66b032514f37a914a9d37d0d9a6d63767395a040ad017791d7fc66c596754ff8288dd544eaca221c72c9bbd8fba6cea1faa2e5caf940624b0384656c7c132ac038ccbc31843043043b62104fafeecd4fb74b131
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	9	\\x96dcdc4c56449144f1540bc5785649a736ee6fa1f8a77faf55e2ddacc99710921e959dca1910893f20157327fd7acadce2ac4795a58a744cea7303fc47a52608	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x7631553a86c25f673faa46ba1a43567031115b9ef718f80776f7addc330e257879f88fb2bacbb6f6589e70f58702108b3bb0c0ef53fe7f39635f6ce5a8155c973bbf349d917c91d5aa5c9e9620591aef9a7a93fdc28d088680dcd40278b869ab79ad748e5b51b02dd66546eeb7a8fed301e6ce56f1ee9fa00d055fe1f051e86c	\\xc7732719d3a305748df74ca5ea958ec46a56eb1aa03ab7f04193263238be3cd0e97587e7cfa7a33cb66028bba7a5c3071c9d4a6d11dc0f61a2bc39d85e24b214	\\x7b87afd1dd242a0405386fcacc91e296852893066c25360f1d4910f3c5f5196beb50c793fbfa1bc4e53bd8c35a4bc4cb5f1aaa83f3f5049a207244bc5d0a9b89ad84c49226d9664f9bba0c1b44f7b9ddd6edf975421b49ee61286167b3d06e07b9e92da4ebc56081aa03f0d68f31ec6a1659e3bbc0b74eca93cf68a39d5312bf
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	10	\\x0321a8bef7f6aaf41a94b11eecf9fdbbdbb3984172c299e8a4fa3dcc097e6fcffdc0977d514b79d240e3a3248815270227393990a48f3d38a529501b40a14c0b	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x3ee67f5cc03aec02327e8cbbdc823160971156c76c49faa92d6f283b42e6f2845059e4913ffaac4736cfcbaab1a538f781ef97e5d6f6a523e7b8db1e1963a01a66e63f278bdc47a76659e03d936efc0ac31f206c14108f0ed5bc7be6cda784c469940ae832a6df66d9197159bd0b77cb95f5a8175ea84e8536dd770910d22766	\\x6d724f2ed0479f5b4655a28ea8ff1c35ba0d5cbc92ff527cc8ddb55181ed19728b1f0c47a86fca2c50f79c387bdd7a6a53f74a447b89551048237e1ffc6bcd29	\\x04be76c8fbfaab27a49b5a2f38beb96007786dc12ffb1a275c10c56929ed9e2dff25acbde18705ecba719281447cb4d458c9b2cf7a3388389c3b7375ba83df1aeaf0310cee0d4cf09eb78056320c22679250346e1600f9d6f66cf1dbd4b6df0a56e87c57b0c5fc66e4323bc2660e439d2b4cc97e107733d92e1fbb70b554b670
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	11	\\xfbf7b5b7a64fbe3d046d1fa1142dbb4b9f5a54c1bd3f7f6d84049db375ff57b7a949248fe236f20ad84727d8f41a9b19151e6ca64c59bcb145f9aa5a415c220e	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\xc1e1703786ef733bd2e1a7d034f328a7652c3189bece90e09cef65fe4f6029ebeb42f10b89dfef2eb09ade2ba6c43c653e1da051a62c6b008a4fac8f7a9845f943455e732e677c71532fb1f371e449704e90e94ff94c6aa7c975e2cc76fe9e755c8ef165732e8495de79e3da227e01134494be7403233b02de975c7db4c5bc69	\\x20193cb0e0a2f2f58f74c30032866287637e0b5b49b882522425cc83221cdb65c65c01687f8730da9eac2f1e2799badc6173b211fe2e90a3b8e237e4aa13b24a	\\xa4db8f6c230121b237876082e117aad31ba4e92568639a3d658a6a88940ff0d0a6eb5ced74038297bb5afd8c92100d0996d98b875b0b28e63515ff0d460ed4628ee26ac5bf5b39a4433f882f2fe57e139e37783d22db4fcd810352395b8de6237249990587fc061b2f72be1b8c1898d6d88d63a2547df1049ff4da0762643aaa
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x9549429543fc07348c349a52ff48729b79be84d2f0179b246badd57fe175ca0380623da9bc796586062a0d1a9e316db948b5229dde43fa382f1e485bebab9fa9	\\x8ffae84ace74029e161b0564f6d1b6e2356669016cdf5699b2688ee402f2e104	\\xaa122988f1a74af7bd81addbdc49d43cc0087da441f9deb5f98e4f2d77aaafd84d1b77a563f097800f2ee5a4389643ecbe49a79792905d007cddeaea35880d72
\\xa2539fb2b22358903ebe61138e60844461b396a3716609da9bb0e1e6e034f2469a70c53480769ed38e70f6b2f47525f5a7315e881883308264b5783bbc3da4d9	\\x2ce2660435ab4541ccbefc7be12c07bb4f029808d5730c0b18341dc61c326c28	\\x61eab7022cf30cfd36cf91fc697651fe07907e67344cfe53c11d5d2516889e80bd1ffa2641bd388d9006756bb32ad40d7eab6561f6e18aeaa7dad342e3df0678
\\x65488fb18fb61b07f9e57894cc6c25458f91fa6c94989273f5c0752d67982872110e2091c7e6275376878ed19c3eb18c4c2f95c1c0d714a42b410207be061313	\\xc9e688e1ce02b452c395921c47dfa754a63565e5adde18d8587cbe009b3e5538	\\xcfb6b57252f7c3a20eeb5bedcf36e6993d4bc70cac62c21552f648a61fe736d75eab6830314b1c01737c5e050751201c5d5f886f7eb36fed069c5cc23e674d8f
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x9c73b669f228b004180fdcf3a9f33afdd000fddbaf12688eed6e3f4c57cef523	\\x4fda09cefc0512ad67c429bae8cf38caeccab4f7efe696a2a1394429f9ed8b1d	\\xd3d48cd8b734e55aa411c2f7e941b82ffa5758f0ee9fb41419e1548607cc64a30fd9c77e0e21067d9adaf4d8ddca8e377d374d719a8528f876a8f5ae60016703	\\x06c4c1f2ee5260b7fb8bb1542fd840107b046cfe46b05923d205a5c03f03a3d19c367ff4c642be00989a36d3dd48abb6b444a7566897902b5d62e6cb01e10edd	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	payto://x-taler-bank/localhost/testuser-LX9PpmbM	0	1000000	1586543741000000	1804876542000000
\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	payto://x-taler-bank/localhost/testuser-GlcUdYmc	0	1000000	1586543743000000	1804876544000000
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
1	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	2	10	0	payto://x-taler-bank/localhost/testuser-LX9PpmbM	exchange-account-1	1584124541000000
2	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	4	18	0	payto://x-taler-bank/localhost/testuser-GlcUdYmc	exchange-account-1	1584124543000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xfa1b86c56993a05a45f37483320bae8b4b2348ffa0be05f91eabf4c5931f4bfb251c3a76d0edc013d9eafe465e0e5e37a9972afbd990f3c7d072b77e9e94ac00	\\xe2557e383c1c3c019681c2521d415a758f1becb629a3a75fd9dc212f0f2e802aee81e71db725f0f9913bea0f913978bd7d238558712aa957d80c4e1673292b13	\\x2f5305e1e1440e301c58ea6f8987e0969851c758340411ca003579edfacb49f6ff8b695b49809c5c9d974a42bc5613656feb0ad6fe7cac42eb40bd41cf95cd0238018de9c871d9708e18f5db0867cd787cfa7274c83dee612008e3300b960973c7aa50be873e543928ba70d33ea48d95a80da3e4dee2d899e945e20fc871f0ac	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\x060f575c9e1c26c934101bd1cef93dda2131e7446874048d672497f54c296722c70297b85019faa97b200fa064bfa26b2e0d6dc9e064126310c6c1283986f70e	1584124542000000	8	5000000
2	\\x1aa1a7cad3f2595aa0251458f6a0009a8ee37af3caa54f939bee61fce69c8d469c467b24e2c2141bcf08a4f7b9d0d91ea36b57315e8943db1422a822d0cf0440	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\xb166db2b2202d49345c7f7dae302e2c6668ecc578505ad53c7ddc27a9e3382c33dd7c02fdff0df4e8597b28039c58f7b7c66a76dfe0733d16974055284d66244bc35dbd6ff7e0e218fc8239686ef9be85711f5257b38eb6ed3e416870784cfcc9a455a797a2158f9c4653aa5e45745d229eaa9875e77ec07ccc1956df0682cd7	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\x4dc4a790937ac128c613b27c8abff0075f0d8f711a6071020fb254f4c10af3c8a4dcb03e0ef0e6a7bcd59ab18385291e8f5f1edadf8679ddd8ab5ed91aadcf06	1584124542000000	0	11000000
3	\\xf8be32fcfa942f145d0550ecc999217eafef010d95b594951fe030210252199c3853747eecd60c3d19b7a51d3657c1018a752dc0a4667c17284dcbf3428d2e6d	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x479f052c5389067a5319e8756bfb8e3ae79b2f0dfb3af72bceafe3ef9ecf87a77c6e68214dbf740bfa570a092e332492d422f953cb5af7f9c503faa77106e167220714a4e920aa04cc4cdc8fe91c76022c63ae596b484a1c8d62d9c9d08005fbc1468526cc027ea1f5ebc3d55b8579d3e5eff6c3adfc9864225444507727f725	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\xc3be358a3ac8aea91517da18a65326cf0773aae0d477014be2a9897d9c68dda6f268d1eb061d074d69ca12a5727003961ed5ce705353aa6ee2bc77a3bf122805	1584124542000000	0	11000000
4	\\x823d560ca5ae4a90a9a69e7bf60522ab787a264cbcadc5a82da9d4536f9cbf54e93fe9b612e2dd6b8e7ae8308807aa4946a77615f0ac08730c3d48766f7d8150	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\xa15ce91a4145dd0f32433bfd540bab400a9e65578d52e3ca0597b3217db130274c9826341df00a93cdc8aaafc66967ec35dddc7eba93e733824d0b62b0e8194cf19a45ef57751d92c9b9748c1e79751d7f774210be72ca80159b8e39616ee81e3f2ddaef2692721532b9c1c62784b81a46c69c3df55284898a6cd8c63de3d08c	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\x16f4a8dfe82338ef4b23bab8fc253dd5e20dcb59cb82a3618e43d69a072a765c68bcf577d7492eda3789b21d69a365a8cf4141e837fd8dcfe2731162e1c90b03	1584124542000000	0	11000000
5	\\xe3fdf5a6f1f973472c480241883541599c62872663e01943883c1fd52f55e763664be60574589435d7cf7e40262701cbcb5aa38d7d1a2df8b63d4d007d071ec9	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x0505ee5f1acc559b0bb41e551d1aefc894c97d200edd46ba92a7cc44af5374f2d7aadebf543dd3675eceb38d728c9b134e9e91302800a0af2b66c764002f420e9296da60fb7fe4d21b4b5c6aa27de90f4dfc101062c33c5109e4e3b7ddf0c6ba87e5fe89957deb96752320e9fdee1d769b7e82025e3b2634c94e0d4a0e1a16b1	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\x57669d08691ab53a7dde30158159a29c08dd127f574dc81a84b2074364822ea9ab39bf19c907cab6f6bd79cd5d8069219ca63800aa364638000b3869e61dea04	1584124542000000	0	11000000
6	\\xc9b289aeb3eda68342b90b684c7b9e533d1639cb8bbf2535dc1ae62da20778ca72d13de51eca2c5235469d4d9c3a914626fd15befb75caf0598a165c1c68b953	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x5c9945994705719a944ef7113cea1ff498ff8b30345fa31016c744910b9ad624005691ed3357a5fd77503fcf3b352f6e8f82cedae1c08faab1d023b1bafe48ba193b84648daa31767321dad9ee9d66d7078c51317100827d8a54849e34fd6421939908b4c24507fde5917a9e693239de3e7a9bb3a75c880622a71d849eed026d	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\xbee2ead3509c0805ac3fff14fb58c3dc41618aded23f3cfbc02e3382dfc9f545a3e6e5d4aabfe109f60ae791dd2a4552b213008b589863d4ce2fee1c349fd70f	1584124542000000	0	11000000
7	\\xf14c1a7a3d4f707722fc36053d5151b61ae3909fd0f663d503f526a866fc6a9b94a2bc08415426ed81e1a485e5e8388c736b06d9624b9332ad76b87a0e1d2712	\\xdaca7cdc05a7e781c04ab1e233ca2664bac59caed67e4d00fef43e31f191487a7cb91d8b862d6f9329da670ba79e6aa599de8896a6032249796f50870eae3933	\\x57120d516229df94203ac957bd8a8c07b3a38d7d315d11fc138c3ba617826ff4d35ae37fc292b52a2a02083e843e9d81a5f8840f6f11e756ffafb3d7dd3ab488ba333988d2fb2d3d0b4d4b02c017c31890b022cd18fb37d72e1e23e5cc9b9833006af9c7343ecf7c6e9a8dcf6b0e888545547b3a11bdaae00a35928caaab0e58	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\x4a51ef0c9c51ebb80a6750af653d3076bf48617afd415562b42a4d0a37ce1fb3e4c58c481715f4f6856dc025c2843b6a02a66d6e97f2d51b991f9e2ca4d0070e	1584124542000000	1	2000000
8	\\x350520ffbb831ff91710b66618669bff74c545bd9d53d917b7e0d8c226ac59d5f1543e2dcf985fd172be823956af675c46f1e5e01ea2e5c5bf5f42468f64bbfa	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x76b26ba25d3c1e7f33322144fbb4ee5694c5f11a4e7f6f0ed0d243571efc78032f8ad021d81c9844496a831ec757b3fc38a0c793af54972bb1d38a01d5f07b006d6c7ac45416b884cc76c59ecfed5ff1d3f9322ba490c979cb99e1e6be32040479e4e4965c2c1eed54fae00eda0e91871247dae3389d7839f0776ed2f12e453d	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\x5e00f9439e06aa899d24380d97e1b5b97eb428dff378c8815efb956df429095677045c031cff90ad8f5777c3f6a765417c98f2b8fee2212ebdef76ed0e95920b	1584124542000000	0	11000000
9	\\xceb2492209454f94008bee1b0f4d809e5f836396f79a50b26ceaf3212d0c43c063e8b83c4ff665594eb185552f037f5aac411a25ee7c0a4361dfcf82e90e51c5	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x539c1cc9e91372e8d373f6939178e2566f3970944259ebfc2ede1cb352ce468612cde7a4b99f1fb0286582e66b03a22d89f61c0170f7c00598437982a88b55f8997d4993501bc96b88decc787f9f0dc7238b2199f1df34b3be1a6e567bfacecd7a293fcaeab57c267d4182d494df3fd11f9c588c07ee9296b624c46871672ec6	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\x1a1aeb760e4037918c3838e714cf7d3fdbcef0770f7a6f8787c8ed7f5bd0a9a00ade2f8f21e5dd32e5f59364d07dd7d08f5be9b4888a40cc00a14d69a145ae09	1584124542000000	0	11000000
10	\\x8351a4ef65bfe266ff642393c10a4cffb6748528cdc2fe607e160314665d6efd91089255ecc0867405aef3f7d97f6d864b22438124ba79d29494f2439df5aaaa	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x733acc58f69234a58cc571a15430c447d39f6b1e9c6b2699cdf87caf8226f16d2800be3c9ed11ca8b9b9410227ff9730d3916381959e6b2c60ff425d4966cb52591f721f6c01c53084db6d57a67d0136ddd12bf010fb97062370061511b6f0a8fd16373b2473a61bff4f5f9c6d0fefff815521c8d89ddfb5756c22398495a8dd	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\xea99fce23cec8899cb444d4d9142a7c08c018f7910160b01489f325b91d9d088029d989bd1a793676150095378215bee0e5a5b9887c95b685baa21b48a0e9a06	1584124542000000	0	2000000
11	\\x632929a099c72fde8b3f8f86682ae2d5cdf8fd645068342b491d1aa521ee3bf35337225c6c61ff4312c4eab983507d74482415d66cee4c065d50d977b98676a1	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x685d1aebd2cab0af54a5da8a679c208f6d37d4126f9e1b9cc0581926887f5b8c5ccb844603495c8b5fecf7f5e30d8b9d3ad67fcf116d8b1d1cf593c892c737a51e29045e77db3a00fdaf2120259ef519b72b3c5861f3ff806c0ffea52f141b51edd762293a3f2abfb356161dce663f5fb5472dc9601f1560efa15196728e5c5d	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\x153bf29f347462c72c2d2390726733a8a3a92735dfae0e789fb678ed014ce297187b205bb84901bf915bf8cd2c3e49be134d8fee216cd97cf250b4e3f2978401	1584124542000000	0	11000000
12	\\xd992aa3ec6bd29c170d3fcc91e91d82577c7fe65fda3162558b1c10736683ea1c2f55efc8e79c9e684f5f3eb2550a4c141b472a5a0f41c6cb4db4a66bd6c88c5	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\xc085f590f5c325652872f55c8e4653aa7c245d0ea4f3ab9cb8563fa86b0c3227b2fe22874dc0ce0f051d458b8fbe1661e3bea78f3a35ba22ff5e61b14781b66f007466de7f488e39c5f58176c387db320959274005b6127e963e677951a14e8462872a1d5775cbe34512434f9a360a2850e43ff1809d595f8c64c73539681cca	\\x8c06a696766b847c2cea178bcfcd333435d4a513017df3308d73058c60321db4	\\xc8fa6c24c844e69980ceb672886745a8663d31dfcc37305202289c1bc0d769fcb604709a0164fd221096b7efb5b4e8b116222111f704b3ad8ad1a010f019360a	1584124542000000	0	2000000
13	\\xecacdf2e69a8ee2e19c7a29bc943c8d011268a0a24ca9f3e21753c01bfd47fe7ee2b9fb4581d4c30e285aa0e7cfe12115b428281b53d912a068f65068130c567	\\xa96d1614b62d8a838b7ebee977db7f3d3b7c3630c8d6aee9c96e848c5b4f72200672fb3ffe229bb3c0ca63fda38757550f42170cf04fa8c647342d4d82abee67	\\x18066d277056e3dbb475c587cf35c39d54739b07c989a7d3cbe3b25f57b8e14999dca51493b19376670e7f7aa2a0afc76d7740eee7cb446793cbabbbf7d58da47ac85378d25ff2d8e5f0db025bc159c206dd334c8d2cb6b19e1712a4d090079f24777ea51a5a3f2cdabb722821aa7af562f5e5d82b5e9f1ece9916d95ccb10cc	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\x2e1a8c0fb61a319966b1f93d231e92680af015eb2d0168d0d09ef0fd1d30a0fc53ccd719f2aa276b735eee4de06b4d3c5bc5036bb0dba9fa47c580e2ba2ca20a	1584124544000000	10	1000000
14	\\xde074157cd9d02c4cc4e11754ff867f96456ed0af5245db58f4bb16e9aa9686c0ad7ad484f051488a2fe6e0d069df8ca2e802d1328143e4d73de9aa93ffe9e47	\\x1e5e384e59ac0bdd77b086344af2985d8a5b1d4e58804ec47824d3d37a5927e0cedf43c55ce4051192f089480a1c61e31393185862e4781e563659684ca9d61e	\\x1a50336560bbc7ba5b61e0243ea6ee42745bfa5bf7cda1fc82c2570cd0d4abd5a29f002476e9e89f4be3a83a79a02a68d11a8403fc0b1a81536fe1bb2c59d2ae29a00726ea7c586dd437874b2a2b5478af4bbefdea43e9a24accf2666ebfbda795d34589223944ca7d76fd2aa0bbdf87edd5602a9ed8fe65c913128807e1fc96	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\x451e233ab58b820740bf355cb62b7213985ffee90f3313fd9667f3206785f5d762619fb140462a5bba573b9da77c7da510fc37fa92d40ad03908a590325ddc04	1584124544000000	2	3000000
15	\\xea3efab045c5e9828d08dee7d4a0a871642fee94bb298af1748f1c529227f0655800f8d28055a0207c32172a58e28269b488d5333e2ee72c7cd53934be02b4d9	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x5afeaa9d75790cd0d9169a07b46011993687357ac9d09aa73c981cc1ad81b00f151250bf7e7dce712a6100968e5acbef806de583a7eb3a29560caa8a490639d32cef0ff965282a942c77c70f4c1445f45685042f691863ff2ec5f4a86adf8c1da78ed0e9ae7cddfd99187a92fa904ccb315d8767f95c03ffb5a9097e7c5fa004	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\x73b6d2f5d737015813bdc5ceb1ee79ded762f5f205e21b95270341e6f59b95f6e51991d81bb6f9c86ba67da3c7f42f242837e783c2ca8c89232acd2078ec0105	1584124544000000	0	11000000
16	\\xbf03d2169dd458c679e4d7f0d81de5caebbac9c8427c187c1fe9da48377581159cf221d79d7dd67c21156276a2773e0016a7311cb65be73b9dfdd80e140f4adb	\\xa6576c13e5143d56edc29a8c4917121a1c3917f3436c26f3349de6c226bb96bce029469a4b627b504a3f17d70c4ad7e6c015b4873e98c87238c9b824018f461b	\\x5cb4339ecfaf2d660d56f80a0765efa2bbcf63430b2afbc95eb7ef42a0f566975f27241c6efa36e5910b83244ef82cad2b5e3ff4a8d338a5be505cc00ec2355197f81cac375f37ca1bc7afe0cb546b461d1fc1f8b339d5c641c6799ebd867c7edc7002fa4afbedb7f095d858ab7469c9793ca2a707a3658cad2e7d9cd0b12e1e	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\xb28d3ab7e9a1d235b5eeaeeef3951f28edab259edcc78cbebd9a2a1fac4d3563d3766e7686721ef329bd98f7e3f25d8b2edfcb7cc5be20faa2f4ccceb87b0103	1584124544000000	5	1000000
17	\\x94529840e7ce591646521cf00e0d709bf4542318307492afc8935d6991638ff0d1f145724ad1d4d1b83083314bc7e2fd25b6cad123efc85bc7c8f55cde62b94f	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x09a36c9277ec01a29ef40ea76bb60d0563131b7dd7237bf7b480d9d2acac7f89bca077ac0bce392a62283b6588227f472e27279971e98fe31d205831bfc3c31a43e370becde748d0f3117040ee490fd97bcc9400f6e5e849d0d4a36593ad292a8e65c2e69d7ab9ead7343d48c065d00c3947190d41d529928fdf2aa4ecf9ac8f	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\x6eba7292d04246a91abbbf42546aeeb7e800d6334946bf7ff7b5c1f0222832b662d5d73d099994c0092b68ecedaebda63b90d896c6429cc0e64626793d5a6905	1584124544000000	0	11000000
18	\\xc655a88e8f2cadf3cc7ec42fee373206bff0fbef40b293eda1ab509ffb67355b9ff38bfad9aab124c11f90b7d2b40ff1457bf58dd71c19ad9118883cbe39aaa8	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x01035ae702e16e9c836378a0555c1714fc13526d43c081389c7bc7f08b83018d4554159d4e1dfd99c73f66f2adc219de3e4cccba16b35665bc59c794b6c01616c78f2ecafb4d95a282c6328212e6433fe79188cab57056a9c13d47107d31eb5625339924f490e01282b91e28934c05a22bef6fbcdc62ff3ab03d02f08b814dc7	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\xd5b350736d5d47474043063d3f6b7dccd6094c8eeb80014bd3aa515c2ca353c1c5db4f001752cedc64f1595f5d60ef17272f73c45daf7e8c4d5c350a05e60902	1584124544000000	0	11000000
19	\\xf17cb2a463cc112c56312b250c44a786b8f34d9804368e159abfc6d5dcf6c6facb5da20a029c923a392f74021aaec291e0e6414156a01cbb3fc1fdb074396898	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x19553d53c7dfeafa86e23eacd87e8ede57d7750fca5307dcc83b1aee49fc9dcba27a70a294c4e75d4ede7775f1e352d16fe0673f1eeecf3d652d045415a06fa58b20d5c3f4e3cc444aae3d27a21018ba45cb5b912297b3370e5c563e0ecc540d67885062e7ca3ae3fc78a652a47ad6c68f75cb5852267e6eebff562fcf6b330e	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\x14bbe5d3b1d4fe349e4ae2f72a453517115268841588ba68a9808b1c0cca0f2a23e63c6d27d0bd4059701d06e4db5b4e5762ff1034adb71612ba44a5999dfe03	1584124544000000	0	11000000
20	\\xd2b69f953def6efc355fc9c90354cd01cd1e72afe7c358947d701157e2b8458fd414754a1fa67c08ab0f42a6cb87c45e4a8f0fa93afb5d8ed10428f7791690e2	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x8002dd9304a443b1eb33d11c7a63dae67949087a8bbbb0e381ba23c4985ff498cd3b6d53342589d7e7518422d92959316a93c13847b626ba9d3f85566838f53d0768865744db40c8bfd53260c765b54c80686374f43a5c661e837fc6a0e3b1477b69a143f67afafcede90a8b36a94cdc4b5bba7eb35b0d0d1ffe8084d4d55362	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\xcf7af496f0446677a6a6a4c313e82852c547437faaece881dd3e7436c26120562a7fa1916ef23d7b24b9e5150e8f78418109676ab6c20b5891e5d8960721e504	1584124544000000	0	11000000
21	\\x19ea00eac23aa835f64fae13c3e837572eeeea7b7a7b316b390451711eb947c312a75707853ad435e932325eb204f49ba3922a5ff776b81b8ea65df8b9ef7c40	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x5840096bf1ddb120f2b9797ca33d89dc430409d806c8eb44648dd61766789684fce09254aad26f64747ea6f071bd3ba1101f338036165e571a06d5b02d7e753d489094aa373d69e7d2bd2a25f279de94b58238e0b3eb968e6584f6fe6aea36517883933b41456241ca9a5909ebc187ee459119b6a4ffe6865903ed2248b7185b	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\x92f2d699e0c15c3505195aed01c0059fa482cdb03e68000ab631513ca1ac40c23ab791724e159a7283b4efb3a236a5f3299e7ff737b22ed71cd4209d55dc160b	1584124544000000	0	11000000
22	\\x921ec4037d54de78d334d451d68d6c09bcf518ec8cd2bb93294df08a38962ad1990955b3775f4a8a85582334e3553ec3eadcfe0fa22c7e583f5156fd5ff730c9	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x39a60102e685b6a6633b04d5cacab13a76131d3268ca9362bc996e71e6120b3d6f72a012af9a4c4f1cf6b66a7481aa0a7338117ca1b2b4593621ea2652c593e13ec8b68aeeacd00f13609a13a074e925e3445e30b886c2bfcf13f0dd52989bcac8736fb45849e0c481dd05cc80e330870b99d95407ae640e692231ae1f5c6568	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\xebd122ce53497507e22f77d1f7dc63d064aadeb29424770dbe41c8c5dcdc012dac1e86d2748422bb69ed8f14649bc5d69f1b861cb631135225a5862dca748403	1584124544000000	0	2000000
23	\\x1efcee558d5bb3aba55d6b5cb7e62638aa0c17bbddeb99b3eb9c9997c976362fda0b0f00f5dca05473e6bfdc763b7348655931138386d45b4f9002a798176d16	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x31c964f058e9a7986cfeb513ddda0a5058eedbc4de2eebca4be32c2e1080f2323ebc3f7619fcd80f369ee3fb88460872599d4d6c3ee03af0dba777b657ef124f166dcb19146ad74f07804845097bc1447d4b0f9074ba9f7a16fa9a2345f53820c01fe6c7dbdc632243f6b9b380cbbd62ccab3573d4735bef3984c41bc2efbee2	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\xf9af143a09eaa9290a1b9d9cdaba7df4f25796410aca20388df1aec0022d7ed5544ad0150e7d28a4011a08b5d619e3ff80704f28cccfe8723d73229ece824207	1584124544000000	0	11000000
24	\\xcaa70a990eeba71f90a86379a11b4786176402f80422213a3f1110eafd112262b82e9a7953e4834f58b081783ba4a806b2886a7ce7131359018be96654c433d7	\\x47e5c7c13b7b267f28df1d734a99e45e139c5c22d4abe4219be0d1918eeace6c933a6720f678008c9877548c4aaa3029aff0bd82d7085fac0046405e6202cc62	\\x2d2f7243d46aae23ac5966f69c8c1bf0eb947ff418b4ad53b7f5e852d938f8fc80de8c2cd452cae4a890e4ca47fed4801a7aaf7143f4de5af748e1e4d8eaf3132d4e03e7cf51ae8f40267753b7279802a8503bae5809db5bcd02a701486f61351a9087d87840fd0f1ab2cf17e5cd3262decb04c91786d17717a62fe75e6051c9	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\xc3efb35a1afe82fb5e0a62ee8c30788399cac06fb191aae94f579a00d70d4b8e2df5a2f78f7ed54936e1f159239f030e8cb640abcc4328ed3e3bcc7f7b461805	1584124544000000	0	11000000
25	\\x60407d1b14561de74f9060b2704af8b44d722a300c19131445c4d8e41fca020392f555b071cf889c1ee61c1cfc4590c1925c7d0c55a12185d22610edbd7ae8a1	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x117d07b85f8e96a14a154c094d12c9eaa96fd00f542d1f6db611b339a65bc1ddf1e2b924d171190bb8424087cda7fd28aa09f932764d22b20f5d50a4111f5eb0b74ae511f5207c3c653170608add58c43685f0f50f397dbd66ec97d444935aced35d0a9be39080b89ea4d98470f9a06ec2b61cbbf1ddb465998abeb43cd3c146	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\x62df9c5df67b2e82990dac569ad3a14475d7bed8d6b612182cf2071163a6feaaf37f80f330ce16607af7112f1a9921a0fb82383f11669182214fb341a351550d	1584124544000000	0	2000000
26	\\xa7fead0b1f217abcdd865867ad345bc0842012b37a09bc878639bcb013d6fbd55707775221144a137929b7de252e10e4b58129f5e1c3395b926e9ad13fb57cdd	\\x7668572c927d369ce701c10f7cf48ca67148183b126bc793ff741c54ce60c366e53f166c57a8c2039c894b521ef69e967c724e6a9261e2a424d0c8fbae3736c3	\\x552b17682757c46977ca00b8a1d87d618bcd543f741074f2b1caca3f3e2c7f387bc87d67e51ff2c5eed7b8668d706b606b85f3e16792b2ffdc28153564e52b52978f0525884948ff694171398a92e1c788f24a63e1bb1c2e64e728ac6e4950c150b97db2094f77d3371550ad6f1d30f7d08e36d6b9ae8f9c6ec84666846b0876	\\xc689e130dc274f9e83e031358b9222ffe21834ae3f39f8d2574f28579670e5c8	\\xc7cc65e6cf593e2c8fa0f3c30af1617362467196739628608f945102a2bb7eb73c567876e7bc8cba1cb73ccfd7cdf380a85ef6cb80b54ad067cf702aade07a02	1584124544000000	0	2000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


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

