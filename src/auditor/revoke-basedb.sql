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
exchange-0001	2020-08-29 13:39:21.086186+02	grothoff	{}	{}
auditor-0001	2020-08-29 13:39:25.025108+02	grothoff	{}	{}
merchant-0001	2020-08-29 13:39:25.281399+02	grothoff	{}	{}
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
f	11	+TESTKUDOS:92	11
t	2	+TESTKUDOS:8	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2020-08-29 13:39:28.633126+02	f	5a159b6b-8eb4-4f5b-a230-e1a49070b164	11	1
2	TESTKUDOS:8	TYZ4Z7PEHM23JEJ34Y1YVRMG7HR4GNB32FCVSXHB6FRGMTYR9WPG	2020-08-29 13:39:30.031995+02	f	800d40ff-cdac-4864-a2be-806f37200457	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
4a940c56-771a-4299-a2b0-c946f5f41584	TESTKUDOS:8	t	t	f	TYZ4Z7PEHM23JEJ34Y1YVRMG7HR4GNB32FCVSXHB6FRGMTYR9WPG	2	11
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
\\xd26a60f3aba41cfef9a1ff163e53f04a9ef54c7907b77de61217c5f1a5bfbde9fa52fb6519c237d6ca37d039ca288b79bca8c18ff2bbe84ed26190315d0046cf	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9d4a4c390b9fc3087f64e60f39dd13655e6665c4e1b22f9d9a53a63ae2ff8fcda083eff6690664c07b7a1313551e10cdd5333cd409cfe3d39c737b2d9181e6f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18434981d4c0ce801368e9c87ad206ffaea6d5eb4ecf5832b0cb075b3d475a3db23f53f753ce82670365fb85538f790c05862fc4a1d6d96e42ec63c7e5d4ae35	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599910161000000	1600514961000000	1662982161000000	1694518161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e025f293a728c11b2b6c7cdacf53bc2fc97b31ca67f8861c52ad012f370f3423a2d3f9f4e9b8e125234f5a1078b3374e4bbeeb31a761407900013efa5d9d579	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1600514661000000	1601119461000000	1663586661000000	1695122661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x95ed361a0a4bf66b387ef3f8500b6279e40fddf482b24a01eaa4f0232d4ca928a9ee85d2c7deb34e71f8efd84be91d84067426dde71768ce763b0d84a55b2634	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601119161000000	1601723961000000	1664191161000000	1695727161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1efe10f07643f71c0d247bcb4116fd9d13cad4a4e6238d3e45123c5bb5834847ada31fedab95e84be36d8a5534a6ab85fa5fbf465451c5efddd0576a53bb851	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601723661000000	1602328461000000	1664795661000000	1696331661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9d30e5e7a42ab08d00823809550e0b59e37e2cf82fdd1daf469a5dfb9fe89fbc8701866366db61697cf206b6ec0eb1391dae2044337ba59e2205a191aa4098d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602328161000000	1602932961000000	1665400161000000	1696936161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4eff9f90f62575e5449408593f94a57df0e4925f9a1fa6eb1e9ffd5e232679f77f058b7d89d353eb2ad2c397691bd0e115abbbe956324e581f4195fe757d2537	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602932661000000	1603537461000000	1666004661000000	1697540661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x288ae157f9ef009a95c9fc12cbd27d79f971ec5d0ce6bed65a048c57dd79109ca98d81785eb01b632edce4216c817bbd124e7d8060e55c2188fe8d38ab055501	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1603537161000000	1604141961000000	1666609161000000	1698145161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xba095513419400d29282cbeb21c5b005af507c6c600dc689b79273ef017e046206c1da58f93a958ae6fc16a50307591be915285727b42081ef6932be8fb5b364	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604141661000000	1604746461000000	1667213661000000	1698749661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x852f94956886ae92bc1e40e1ebeac932dd188709d586de879e2ab20b79d41e51bd6d0460f3ff00edf43e0c3eb07d16d0e6cae180856fa00df2e8f6c02b28466b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604746161000000	1605350961000000	1667818161000000	1699354161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb31843f6840381bcb1ab815993f3f68830432533e0b744910d762a43cf73038130c0bc291871d319eea2f5ed0b906f9668892f3e1dad5e15f799e6ab2c5d6919	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605350661000000	1605955461000000	1668422661000000	1699958661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde94300ab1749bd934855dce407e6c8ec819b2c322995e8ca28834892bc12d0967169a58fe28acbbe1d59a3cd043d1ab4f74dcdb1e68491dfaba1091063099f6	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605955161000000	1606559961000000	1669027161000000	1700563161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b0ba8aa127d1476777d6a84b7c0df9bb5f4a85450118972024e22d594885bbc10d86748a9f6f247f63e75db4f76a59dbfee1074c186151f0897406c988df990	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1606559661000000	1607164461000000	1669631661000000	1701167661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf36654d0384f41671fb942dab49af65fc9d591bcdc2797a4314ce736e817835c8df589d425b83e74c1fd2398507722cb2cd69ada5593f54789cc946b9d8be9d5	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607164161000000	1607768961000000	1670236161000000	1701772161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1435d72af49005c553cb496d51460d34543b8ca7790aee0f9699230196533295e104a4563735e5d7def16789e9775e5938a23e716cc9cee23d6f76091c5e5a93	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607768661000000	1608373461000000	1670840661000000	1702376661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf191af1d44b81b547e841bff7554ed20d9d977fb20dd5f630628dac6ff094f589405063d4dd32fa4998b9e511c2b945f9d74a64d04f64c7dcc086cdfead1b1c2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608373161000000	1608977961000000	1671445161000000	1702981161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd345901b89bcaa7b1388d06bd6c1f3c2933a6585505d7ebfefcc2d98c058271193cf9d73ecd3382fa0925af0f3ffa19c631720ef1aef9385db31dac626d6c065	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608977661000000	1609582461000000	1672049661000000	1703585661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b2a45c17cad1c54f6303ebfc1e63f215fd0fe1a41c32baebced8daabe3df63cbbd4fcd0cc5698c0bf8f45274f3f342986ac3fddb1afd39c3cd2ada01367eec4	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1609582161000000	1610186961000000	1672654161000000	1704190161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe0c16142f0585816b6f0ada7287e2e5338d8cb83b7b2fc1d2fedb243cd79371457ad7f2b386abf2802e2de7e734742272ff4a43c40525727c5f303d8a24e99a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610186661000000	1610791461000000	1673258661000000	1704794661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x120d7e1f3aeadc89d20756a9754d8b8cc02d408aa34ec24a8f78e51b8a487886af3585fe9e93b6e107879b172a546a42cebf5667a839b9d9d80276d4792adbb6	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610791161000000	1611395961000000	1673863161000000	1705399161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd10e1d463f8c88035b46938b3c1a3c59081e509a698899676f35a4ad27db463dc3297c77a878448a5a2dc051091f39aa7555fcad1b30c547fbc6dc2707022955	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1611395661000000	1612000461000000	1674467661000000	1706003661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xea060f471c163bdccf7c85e8f903d472ab3b4775326619416d352270ee0e6750e369127d8dab22dbf7d2f440017e719ca109bdf4371717a66d0b1df740181809	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612000161000000	1612604961000000	1675072161000000	1706608161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0bcff3410d167d77115b00b7023b93cd70d156b0e44de2a04499f335aa40600a5b825da6d1392206e260c861a4d3515ec763cebaf3934819a2ee0c62870162ab	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612604661000000	1613209461000000	1675676661000000	1707212661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2792ef1cc440ed3fc70e1fbec4e02c294bd6958504b321f66bbfda6a75ca773000cecde7882d3d8d3ec2e8f8eeb5cebc10afecaded403c372386906685bdcad5	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613209161000000	1613813961000000	1676281161000000	1707817161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x20301225b6422e82b0763fb7b1e754b0196c5e94a6e5c7ec4881647cbe954fe8f83a20d4c65c0cca87c6b35124db1bb10c5ae142f4ee1c1aa7141ade58215e64	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613813661000000	1614418461000000	1676885661000000	1708421661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x34542fa4d876e2b85c0a0b290036d353882a7b00024c759ebeeab9bd9bb8393ab598ca7116f64cbb4154e3234562228f0486818db111cfeb225dbc055e47b9e3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1614418161000000	1615022961000000	1677490161000000	1709026161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55473d1e0cf86fbc88743c379822916dd9d4cb3321ed28bee7d03c329e6956fdc47e1725107477997681cc64fe7b0e448d62fe6b2b3eb0ac9ff583464f8f5ca9	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615022661000000	1615627461000000	1678094661000000	1709630661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e35a3a21e82edb285212ace7c2611aeea869f58d1196040108194febfb8129461cc6b11179ac9f67181965fce248d6327b2b08d642e405b55524ce64fd3346a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615627161000000	1616231961000000	1678699161000000	1710235161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c0c29b995288e55004039f97cb8af443685e3085ff8734cf77e4b32cc43a951bf2457c231fd7905bd2cf15d657e664f676a6bb800b62520b0d22c3931d74305	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616231661000000	1616836461000000	1679303661000000	1710839661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef1e158776872a455c60887b6f70c4c06435bad720796ce95db77a1d0f2f2fb0143b9fa9186504286ab144488642a45d18621c3ab86ec28b01daae8dab562579	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616836161000000	1617440961000000	1679908161000000	1711444161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0868b3b0222078042fa5238b7d781b4733c94d29371b533bf61ee5fbeb03df8ce433a4cc719ffb7dc97554d279f66350857fe70d39d3f2c55586cb3c3eeff951	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1617440661000000	1618045461000000	1680512661000000	1712048661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x75686e251d119a7567c88ad09e7633515961933830da823dd0967fef90f8a17c247a840a0626d304f49427dd9209c481da96d2434ac68c9368cbfd183f8e4d00	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1618045161000000	1618649961000000	1681117161000000	1712653161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8dd395b5ecbd7717d9f8b8244b0d23b9aaa2aa3d785f2c88dbf910b42774d63f907e4c0d2c8c09ef56bc1a12556654c82c497297ce20319826b4b9f1f2d31e04	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcc9f51d094c0d1b607082da14884f2db31b1f7c9d716355a395efb8c87c58d85a076bc81ea763f19e2ba0724c1ae60567dee1ec4e9197219a20c2ecba9092aa8	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x146f6622ca54df31486923db1fc18c2bdafac05337d0b9f4c827011cb7d3852efe19818198f013184b4304337fe29a645408042d3f8796766dcdf38847739315	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599910161000000	1600514961000000	1662982161000000	1694518161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7f26ed2e49ef40ed242712483767510d7036529a0a3b4234a69a5419affb6a7068c24d0e59f12bc5156564d0b2a384aa89d318dc0baec09711ad784bad0fc71e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1600514661000000	1601119461000000	1663586661000000	1695122661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x04a7682e9e458675ce2d88683d48443fabc10da1a2d5a740f2e7f8a0ff3b7e8984a09f395cc995900784c686b24cd253a700660fd5b6a6f433ce5caac4aa747d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601119161000000	1601723961000000	1664191161000000	1695727161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x36d29db266c79a4a9caf6e3aee2d1c0b9782526c87d1048644d8db05057b25c7c17acd3d4eb3524f9f00a730438e84346f2d703938de90ea9159aac44dde09d7	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601723661000000	1602328461000000	1664795661000000	1696331661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8175200ea6d1532c5c91f4251f213559043d0b3ffbf9f91a2fc0141f3375db31025efcd365814305b03ad7118afaabc14825497a34d64405f257ad8750957406	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602328161000000	1602932961000000	1665400161000000	1696936161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd18ce1548d67b0d36149d9045f8495c0ae13f71ea93aa6b4e086ac997f075c5e5d24d36aa9785764787c2589a908d98dc303b852857b8acd92ed79b2487086a2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602932661000000	1603537461000000	1666004661000000	1697540661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9c5accbe532a1b84fa00d58c389c0db2b0864aa4a7f31dae513bd86149c63dfe023dd095bf43976303eb30aeb2d9dea519e90bf7a6660c0784a69e510f702bc9	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1603537161000000	1604141961000000	1666609161000000	1698145161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x45cd8d89bbe2407279df66a6cfe8968d87a3a137d7464ee30b44b3d5f7dd3feb46bd593d2824adcfb95c190810fef3379c9776b7f990a24eb780119faa04a99e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604141661000000	1604746461000000	1667213661000000	1698749661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x37d781630d07ccf6ba40d05a80cc270068a28563c864e8513ba9bad6c8ba3fd521c1c7ab81de2513bc108d2da8fca32738ec40ef00a9b76ea4c91afd5498b601	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604746161000000	1605350961000000	1667818161000000	1699354161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1b87d65869dfd3df8d27c7123462fed20b7fee81b2d47ca55f70e69a843eaac7ce1ce849dc163eb5f89a72efd9349c4f54b6fc93a8709a0f11f2db5f930acee3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605350661000000	1605955461000000	1668422661000000	1699958661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x498097efb0cf2a09d9bf139a148f3e8b932acca3ad5b6700f0ee45d5f630d3c66718570e4f2e075d15a39b69a38453ee3734eaa6cb60d84fb7925fe1ea0438c3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605955161000000	1606559961000000	1669027161000000	1700563161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x492279a51b350715eafc25f33e72a81628d2e374398abdca2c0665c80bb057435593ab5d84e1d8ba79af51bc106307efb2ce4ceda76fe50c5fb22dbf4ec09f69	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1606559661000000	1607164461000000	1669631661000000	1701167661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2ece31d90d63039c3026b8373b21dcb82328264b12a2e937ad16aed386787eb88c83419c5102222e3fabb3437f6e2af26f9e520fbb03f4c973338e6982650bed	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607164161000000	1607768961000000	1670236161000000	1701772161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x10be9fc1e8ef59f66a5cc031fda21733658454b528efd38df1fc4a46ef4d95053bf3eb72f8c20f4c1c364fbdfbd6a280788cee5e0f4641120b5aa3a0ff3769a0	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607768661000000	1608373461000000	1670840661000000	1702376661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x11191ceece79aaa53e325dc0177cf658f64733c252780c9517abed9e117a6ebaf96dc662377b92331945a82987ff76ae354f22b3d9e424c22328cfa099f1cd68	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608373161000000	1608977961000000	1671445161000000	1702981161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa856a8198f9a866ba4684bc8665fb071cfa0654054ab689a44285d364b09d2b82ff26837e4dd09a9f118bfb93a57944020569e5c04350e29a1bc6dcad4cb132c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608977661000000	1609582461000000	1672049661000000	1703585661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7ecf679e86950a0eac4b659e4138b39b7ad9e66ed0a56eae07f98bb2205eab359b3ba043e42c04d339ef7c1beadd3775bf8d6a9b5b85d3a9d14b5c65890d8f31	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1609582161000000	1610186961000000	1672654161000000	1704190161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x28244eba2813bb9cae8a2d4edcf34d18aadb89116efca050f5b1f51be4770a9a2585a5981705eb6d062edb7dca44434499826f83765c7d82092cb8d0a0099b60	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610186661000000	1610791461000000	1673258661000000	1704794661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x74dc815df3c5ecb2c76bf68b16b0e5be8651cda12072a8b3c9ff4b4d1386c6e5a446fabb6ec6dc8c361638030d9d3614da2b896fc24af789aa5a54a71a50244b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610791161000000	1611395961000000	1673863161000000	1705399161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb9463d805dcb922149c1b6129f5c6e17f193bfe9bba36a958e9339464fc7f771a46d9dd5038b23adc5b8acf26f5d0dbacb74bfcdf9fadff13d84bf8f097a3b0b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1611395661000000	1612000461000000	1674467661000000	1706003661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb686f3ffbb837b3e2892a2ad1510e59afc9abcf8ab3c8c978e045a93ae67e94d4680bd9789ef5f8e5dd2c83185df59a69f31fa550c53d89f55d569ca98ad899c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612000161000000	1612604961000000	1675072161000000	1706608161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x01747f7f86868267b1850cd4f3554c423ef7c5346c16bf9b63f4913a85fa8e6b1d9501c2bda811a42ee5198e02b8849a9d2500c44d0f04223021a94f5abb2975	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612604661000000	1613209461000000	1675676661000000	1707212661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa4c2e44b992a7ae76f9d9cb68fc43101f639ffe5beaab9d42ea3365771c7330277d0e72843c65b991d7ff04ed043a839e25007650792049e7513ad4d99d9ea27	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613209161000000	1613813961000000	1676281161000000	1707817161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb0c1360d15fceed27516ae83e0669e6575ae900c419268ea2532392053c669cf9d76c51ead9be79d8a934e4017d39a8aa0ac41a0cddbed5e4881101e72fa7f05	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613813661000000	1614418461000000	1676885661000000	1708421661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe52ef1f47d47a4f0e59ef708cb3c1178b481de720948459677cd2c64e538eb761d0c4a36d4c5a0474554a708592b8779b7062cfb9e90bf9a16e56c37d51e3b5e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1614418161000000	1615022961000000	1677490161000000	1709026161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x64b5debc4be1d701ba6ec976612dd94108d7c4a33a89ad62e726340337862f40fc1a101516c9a0018d9018c59bed32e8794926bd30cfda29bb95183d8b4a0444	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615022661000000	1615627461000000	1678094661000000	1709630661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf19c8c187495315a4ab0d220d2439c723163fbba09d73f966e0c3777d841504a7ab723a6f351f8bd82ca3596f6f34e5741bd7ef991cc78673982a12dfcf610af	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615627161000000	1616231961000000	1678699161000000	1710235161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x05195663587478a224e28c3bdb0c28927c4f5816ff7416525e7007c54ccdff9f8b8d12728467eb1dc517dc0cac745788343cf9d15e0a19e676acebdff68434ff	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616231661000000	1616836461000000	1679303661000000	1710839661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x427c8587553377630d0bf864b3503a81fe4b2d1597e9a8b32c893861fc273107f18cdc7195a41e17ab0d5e0bbf5ff4d466767489efd5eaa1766aa7570a7a3881	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616836161000000	1617440961000000	1679908161000000	1711444161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x252283f676bfc321d5f86cdcde2089dcfeca62f412cb2c97d2018c26d283615229686c09818a280a78aad6668084a03a9d51e8ca129e243b78eeea6c31659bef	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1617440661000000	1618045461000000	1680512661000000	1712048661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3026cfd3acf7b9d5e0716449a1b55b3d0d59b14776570527bd17c708c79d4cfea0c1eebad181dce6c66dd13e2b7b8f6da8d3c100b06a52f0f484f4e1747864c9	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1618045161000000	1618649961000000	1681117161000000	1712653161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9b1f107f719abfce9fd4458fce91376237fd4555cab8dc3bd99b3a54fdd198871e05270db590762f21ea397f81021a87ef5dfa78c447c4f9ac3d4a245457a7c9	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2ee20cd7c4a9957838e3a709c0ccf0e1cec902cd98d6eb2c38e9ef44a8858313cb1ff38ea96487a0a5d485f431e3ccecaae37bce661b3370811cb9092d8be1d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x68e8de755e60985bad709dd7e46a1e7d8677e78c78e687d8ed7eb55fe6a1ad5518fe53894095b5eb2ea1003f958c0d567c41620b5c2f86304bdc1eb62b49e7af	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599910161000000	1600514961000000	1662982161000000	1694518161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x800f789c774f751bc87524032008aaf422a00fc6245fcc9204e5655e35f456ad0f6bf6f72f3c175bc451be41f8729ba5aefddd59adb782d5055bcdb3b432afd4	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1600514661000000	1601119461000000	1663586661000000	1695122661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9d9a55a229ebf64b7cc988f619ff43c1c01b2883a281eadba4f3eae9774a8180eeab69b1c85553c0b08e49043a868ba0aa85ed5cedf4ae6cf19a59b94c0e833	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601119161000000	1601723961000000	1664191161000000	1695727161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2b311db7ce2db2536422e284757e62c4b724f809bb27f112c3254d6043e0aac9cf76e420e3754b06325d48d0f85e45d1c25ff71e7b61bf872881b9b1632ffef	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601723661000000	1602328461000000	1664795661000000	1696331661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33ce22b4d110bbcf7661194f77bac2265a307b0011a928f7e8f402eb82d0bbb8b2dd05f80f070eb4ac50039bf789673320b989d2d7efb35b8f05bdfa92329ab1	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602328161000000	1602932961000000	1665400161000000	1696936161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22f6a24dc24f12bbf873c03629950e4762cf3965d2123dad3816b3da636ef3f66a0f0721bb0cddb7e9a219faa9d1b259c027f6ca9148f289916e27e7617fed10	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602932661000000	1603537461000000	1666004661000000	1697540661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2ced44574d55dbc343a044c17b083c46e4cb9708c0c891bcc85edffa1de2aaf564c753440d22f124a8a768de5aa5ac67ef5112bd77e6b01100a9515e4aeda6da	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1603537161000000	1604141961000000	1666609161000000	1698145161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x302b70f342844778643496dd7badce35a0e9ec62b95d35e9688bb3493119f7ee4134b11700b89e7b09e002c0d2eba3f9206fd11151af9bfea5003cd00c05d0e7	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604141661000000	1604746461000000	1667213661000000	1698749661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3854f0a5ab0b7aa6d94909c7660bb8075392bd1d50f9b40b86b6f692429ad621885b00711891231b19f7f3cd8cb657a4b49083be8d458d83c49db338290f30c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604746161000000	1605350961000000	1667818161000000	1699354161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a0bf5005e02d91c5e1690a796d775bcbecb2aab725d0e87523320f38e1e897f2e404a9e76495c346aa5c70d25c4bf25b441b137b686410f694686b3d45a8190	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605350661000000	1605955461000000	1668422661000000	1699958661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78efea3e56879e07bc6a5259d2ec99e98ab6aecf972c4014b536e81f6055f9827565e904c9b612719d47497a9e6de9accc7aaca64f75d6e0f57fa0f79d8aec9b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605955161000000	1606559961000000	1669027161000000	1700563161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5537c822e89669b78a0c0b5cf157d6082dbffc977572ef854e5b3d60a531b19e8884fe7beffc637fada8f653212d5f1ea916699c1a6e326920b238fd2e9f16d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1606559661000000	1607164461000000	1669631661000000	1701167661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6f1f38365c14de838ece800cc977c26295b04eae45e03442ba8280beffcf184185ec62370cdd348f03eda1fb13b6ad15e604d7e809ae594c03657a94b3f1c56c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607164161000000	1607768961000000	1670236161000000	1701772161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf67f191d77a7ece55343ab0dbaa52d60482d6b70e368fb61ab991e10e914e9197cba7a6c3ecbdfc9324f203e2a4d8c87dc95787832e9f9505d2c3725f4d789b4	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607768661000000	1608373461000000	1670840661000000	1702376661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a92838027e25ebc63d2551066867c4229a6d270d08a5216c671d6b0c7183300267da11efc85e15019a87f126afc2586075cb0257dafee76fc3f675820eb797a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608373161000000	1608977961000000	1671445161000000	1702981161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x635e58bf8ebc5337b7a08179561d44e32b2c93db80bd1da5f72f63ba2c11698e8d6c6da0afac7252d589faad32b94964e2b6a609accc319df3594a0c4025b08d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608977661000000	1609582461000000	1672049661000000	1703585661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2704d0b3db91a4a3e51041cc01285226338a4ddf0de7e7df52a77b0d68185846f12080f0362c7627bdbc49b2ee85f899c962803f71683fafe2f806ef58e65f3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1609582161000000	1610186961000000	1672654161000000	1704190161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x793c895dc1ac6f6d1a78fceb33ae1cfc0bef1ffbfc48bc5e0dd1dcc885f332538a4f9e758f02d3b6539adbc495547e319a18a71e446973b6e7456364b613686e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610186661000000	1610791461000000	1673258661000000	1704794661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d044334ef461df17f4d08034554832d4046ba8ef6b05d70afcd3b677256323874ac90a8bf8edc180bc60202972493f92754ede6b336ef8bb77cde706b9d3dad	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610791161000000	1611395961000000	1673863161000000	1705399161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98026410da4c1934769ee370c591e8931c3a0253554cb8a431083814d023cce16aedbb2fcef20ac136dd5bc3c4c582289a00c52eca862cfad6a78006731a36d0	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1611395661000000	1612000461000000	1674467661000000	1706003661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x228604224bac98ed23ca1f3df07b5b6d93718e0ad8f566a19da87fc205963e28cf0e02571642ce7c9b26cf599ee3e21014f43df4adf41afd65ea0e37e6b44f76	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612000161000000	1612604961000000	1675072161000000	1706608161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd31e03c08bd0738b0276c6ca6b43157f9c6ee7d5d431de2db526228a58b6ebab255f5c1b8411e94a5e03ed9d71a0db60a5024871f65878d6523f9b4f90b97a18	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612604661000000	1613209461000000	1675676661000000	1707212661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0d6055a00f2386f3a1cf944eb2687934b7d316962317b86f6ec4039ff276b5c754374e99f0d70a40b1cb2873440f686a96fc6f7dc6bddbf5f1689dca5157fdb	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613209161000000	1613813961000000	1676281161000000	1707817161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2057bf766829901ed69499e2ff6480d4534c2714ff94e9085edec237cb48b3311d023c35be4e94cc57ec50896d7d95f3c9afabccf95c5979eebfc156940fd387	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613813661000000	1614418461000000	1676885661000000	1708421661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d7421dee4918033a606860c8548a975a0eaf0fda76450b8b7bc2de4b39da32e3f489871ffb7e20ca008215c0361aaf1a31d81e67d3fdc8c06369bcc10ddcf54	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1614418161000000	1615022961000000	1677490161000000	1709026161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f5ffe2d739a00d597a1c3d5641696e971acb485d020f949e8d8f973729a03e6a61dbe5d189dcac2d8280412aae5f8d90d2f1ca43a304c033a9ce74225ac8dcd	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615022661000000	1615627461000000	1678094661000000	1709630661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x68a83739848eb2f8738432ae8529822c4fe558a194f3569885d1dc0315c88d676d6d4299df11da1535db4e3152f6183c376dd5795214a47f9a7818630028aa7a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615627161000000	1616231961000000	1678699161000000	1710235161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d48631b4e129f6f3ff39a552917cdadccdb8140fb76443ebe0992973150daa6c89f4731937aabc11faf7135f2276a65039b8d1cc663809166fd779e90d55351	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616231661000000	1616836461000000	1679303661000000	1710839661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x09662e79d569b2c234ffa7e2fdfb670f322d7629e1e4c1d3b8578dab88a2ae8c3e501363e05e260408d11c6084bb925821699670e9f4d505f498a16f31402306	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616836161000000	1617440961000000	1679908161000000	1711444161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c58ce8cc8ec2e6da73946ee85e01478b533f22f3afeb980632854781daf0f2d01d1205a8e57302b4a98817cc67c7a3f42ca42ffa103ec685e62ce04d1babbce	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1617440661000000	1618045461000000	1680512661000000	1712048661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ec311fac1d52499be8cc5a557f2544a01df5e4ea33a134f8dd521e5c4657c614bfabb5539926da9203729cc5ceff99cf9bb74938db8abb6d8e7b2dfb6c38591	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1618045161000000	1618649961000000	1681117161000000	1712653161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1226f28ec4932672f53bc81acc1fa43897720591dc42b1b060629491b7182d54f8f63afc39c8ec4adb8e89ef32a497e0537d5e166b5ca9df13bfd42fd3e9bdf	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7e58726bee0066edfa1a63f6c76594a5bddde68c07b4b5d22413c311420acfeb9a2c98081783e56cb8c998c985c57a6961a87e2494465117e3d24375778afb7d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x116f8c16ace1f91cb6001916dfe11a8c52f38561363a885b30c27deca1d3010ef460f8dd17e5056c5739f4b68899e968996a0a347fabf3bdfb31bbda786761db	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599910161000000	1600514961000000	1662982161000000	1694518161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f537eaf91a4056ae2927aa1bfcc0b66a949c01ef3ba3418abde9bbbbbbb4283db98dda32a28a41f31a239754b6bc5d2bcd8a57ebd7c666f241cca0bbae583ea	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1600514661000000	1601119461000000	1663586661000000	1695122661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe3f7a4b4113de1e961b5a1cb3a9d3fc1b7f4e3bc7f507eaa21a832f60dc32f8ef358ef9e3391c73bbc0fd51c5c84a6bd5014869b031aa1f1d4975296860259b6	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601119161000000	1601723961000000	1664191161000000	1695727161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdc3dc11c84eec3cb8fa410f4d8511a9153879e05f26403e6f1da18917788991bceaea8fd872e968bfc25c283807464fe4ebeb74f3d0ae61b736e4a822b9310ff	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601723661000000	1602328461000000	1664795661000000	1696331661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3bc02b76a4ee3134e5ee6790303fc8f5259bf575a0ab89611058eadfa9727827ab8fc6c8d8bd77b39cc306af683fec29c663dc47626bd93f3852392e37548468	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602328161000000	1602932961000000	1665400161000000	1696936161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xecf9411449d1f233c76ba856b652dd813ba613accf543c87f130d59d8a7a67e49d6df84c2155e35a79f44bf069737918e40a93f939854d12ff7cb42b1ab97e05	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602932661000000	1603537461000000	1666004661000000	1697540661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7d0ce4b3a8e36acf09030f8c342551efeb218bf90d686818268b504ed3b192d7fce3f0269c91ed9810fe32338f1237f1660ed2ea22d84c1e615af870ef539867	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1603537161000000	1604141961000000	1666609161000000	1698145161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8143dab7cf410f4f6a97b962485e8d91c874fd0f75df471f89933167dc9d6f5fbb364cb05b71be7210dde373c056ec96ce3e6177f76968fac395e659285c184b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604141661000000	1604746461000000	1667213661000000	1698749661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6cdbe04ca4a3b5cf80ee5d1eab930f5c820e28c024b4a3989a0fc299ebaeb3e0e6b172a00c14e29d096e450ce1a258b628a13aea2aaed86ef8767d6837a9086e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604746161000000	1605350961000000	1667818161000000	1699354161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xea340f4efbd05d076d8742f4d3b62b840be9af707a150a633c16733a17f6290fc922cda7f3d811901899c09e1e896047489460d1f83570d4aea4f6e60714cb92	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605350661000000	1605955461000000	1668422661000000	1699958661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd7c7a74ac1d3f3e920f13092e8db227f9e9e227b26483559d787d424ebd849c128fe9992138e6b49a372a39593bd560601b706cca993be029e7d89088c54214a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605955161000000	1606559961000000	1669027161000000	1700563161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfdb9f2aea6f7f02e080d090a3399d12e840e720a095a06eba482c86c40475c50baa7bb46a407b0298bfcb66163f6b2341f6fe209228c90ffa0251a85450c2da3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1606559661000000	1607164461000000	1669631661000000	1701167661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3bb249a2b6b6f7f4389bad71de053127310de9d02bf27a82f82e0d4e3e8fd8beee4af08e4453a4f4bf6af06c93f7a21deb8978a3ba6318ced039f80ccda8eac6	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607164161000000	1607768961000000	1670236161000000	1701772161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8b776e12d5c1c006b77221f5e035f72dce2780f128d50eae2dd79ae2f2707d98f093fb1ebb18ea566347311504e0bc9bbd9a0cb84d1938b23682bf6f4b8f4c16	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607768661000000	1608373461000000	1670840661000000	1702376661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x01be2ba78dd1e5f597a40571b9b6701b686d28c5a7726e3721fd9b8283c896f419f3b7abd8d272a889ab0b3bf78a399db2c5d6e93563b7ba8966d49588221df8	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608373161000000	1608977961000000	1671445161000000	1702981161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x192e4efc93e62e6c9ef774b0720c2c8230d82dbd0340a2e9e0c32cd7cf497b9bdd44e35de27222c37c28b52bb49f99272684648ef6f011c29413c8e18cb040f4	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608977661000000	1609582461000000	1672049661000000	1703585661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d72131cf7e98e794516c6e28896aae1f53ec363e8593a9c3fe7047843b62a5734246fcd69adbaeb8748692dc5964ea4d6a0ff34b155ffc9cb1a7e8a00c80edc	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1609582161000000	1610186961000000	1672654161000000	1704190161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x22916b6d69bd59e0d41e0fc72b41aaa9ab36d649f53914474841692de017768e9234c27d86f0dec95040500f16a1f1670c761896594c3cb3f493569698603f7b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610186661000000	1610791461000000	1673258661000000	1704794661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf24d4f1ca1d2351a769e06b9afc0e88d3083c10afbe59767896c8679fa819b72cdc3ceb217827bb6845e9f15ef06204f3d2dd9b8f6f5ea94bf7f0121727c288b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610791161000000	1611395961000000	1673863161000000	1705399161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ffec0912108d109205b6f4407ed659f9addf0f849d602f1bd376065aefeec045a782622b1969899de03ef4f6c74cf4f7c58682385cee01807e2774dc7be8584	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1611395661000000	1612000461000000	1674467661000000	1706003661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8212881c068b515d0561e5dc4f5774093fc0423dfe644102ea06a24470750e33bb7617a5c1e2223d8a66195da7f32fbc41a129a3441975ca414f5d0a6e5cb816	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612000161000000	1612604961000000	1675072161000000	1706608161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x41db7ccbf3706b9c608bb09893360bd85c75c9ae7416124b133c552976344f2e68396e9c74999e71e3db543525a1b623c29f4ba4d7ab67ae0f9ed4e52477ad82	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612604661000000	1613209461000000	1675676661000000	1707212661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a56b1dee4b8760bd485841cda3def04c23250baf653487c5478d4b8ea9833202f957ca4eb3cb1ae9485dc3cf50d6a1f489a85b4ea38bcc9576440c1d678eb4f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613209161000000	1613813961000000	1676281161000000	1707817161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaa43e33bc77662e78f269f2a405bc555de46cb80497c3e56597463982a9790c702da542edc59c349ce690277e79e77296e7524ce3ab01233b91e79c0c36e64ed	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613813661000000	1614418461000000	1676885661000000	1708421661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6038d2dda732816dc95dd88affdbc81f7187b5372878024bedf0dceb415dfadde0fa7e28ae042a4571fe6a38fb667fa0de72989c7d6478852defb5b85cd8b11a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1614418161000000	1615022961000000	1677490161000000	1709026161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xedd45c77590345309a6af39c440d714ea252be876853d00904b63f39f6a08bc2a08c82d7b3581d2affdc82b994dde48e2e54cdd550ec4895a0221df23bcb13b0	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615022661000000	1615627461000000	1678094661000000	1709630661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2dc503ae00806d03c0127073965a37ffa0cbb5b51b44ba8681af6ed58a1bfefd1117606f4e3450a7e72d50fe582dbd4a549987d0cb2f76e5c37d3e068d2050db	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615627161000000	1616231961000000	1678699161000000	1710235161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2cb8b30d59d2ae5a9e8efde1fe047b0c83115e4f10034442d3d438670a6187b1bf352ce0dd529742b9ef5dbae700bc197f7bbc2e3b5b5410e6605aa0cdad334e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616231661000000	1616836461000000	1679303661000000	1710839661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4449c17170fb3fcc3e500e7f58ae5500cffd46add48057c7547d7c8005090963443f904d1177f0576343dba0096ee343ab96ab22cfcd94f6a34fad32dbc2fd02	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616836161000000	1617440961000000	1679908161000000	1711444161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x07602a64d7a6f129fa895365cb7e41ceda081be23587c0b834eb401ecea3ca2ae27ab24dad391a016f9f842501f69541d16ab695b3fcd514c9f73be2a8279651	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1617440661000000	1618045461000000	1680512661000000	1712048661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0916f2a3ce2ce32dbf4ce1c03986b73abb47ca7d9d55f8b83c2073e970715ca1830ac81bead4bbd826c3333671bbba9c874ed4724bcf04956f335ae09c57add6	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1618045161000000	1618649961000000	1681117161000000	1712653161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b468e9a59d54f59c4f77077fa1c46298dbbe8670b5b5c123fb363db01317a0350760769c36dedc61c2ef65f86288e837c725b3f9ed18990e0288db11bbd81ed	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf42a51d8dd9912fba994d9f2caf271f57a5b6b91d07bee206e49c0f464069b78eba55d8b8d7d8f7be94a28bdb0ad7218455e7625a4dd2b95a69fca498758e1ba	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d666c0d1858267e73ef6da6820fb287197b38134417154cf2449bb1c66e345e313eda1e5802fb1bbb535903e2f96838c3d4567ef3c78fa10293a94085107afc	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599910161000000	1600514961000000	1662982161000000	1694518161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6bd51d8493f1e7ff3702f44ad3545308375955be177417166634079132ebf46ff406be4cfcb2f7099b76832e61b45bd753c8f5525c711b4f08f9a3de1a738b8e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1600514661000000	1601119461000000	1663586661000000	1695122661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7f2b952349e4215050c6e5d7f7c3a83e47c3d0dcbcf6e92279f9892a8a30d579895cd793d5210bd68e5bcac7f4504ac43a7b8493a019de74f2d67a10974433cb	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601119161000000	1601723961000000	1664191161000000	1695727161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa8b9a7ff96ba29e985a0e9a13458174aeeaeb37388106bf9fec16ebddb5c5d6b70c83e32fa0c32bae7127914c8842279e9857fcfe07faccdfe7287bede441133	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601723661000000	1602328461000000	1664795661000000	1696331661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3e4ff94a03df8140d9763d34240d64aec1d6eb9b431d956622c7aa8ccd549561d011fdba1098fcf0552ba34ef228136e7710eaae6c66c9cdbd3894cd9639a6ca	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602328161000000	1602932961000000	1665400161000000	1696936161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa5e4848e79874db172e0bac5f61a7fa77a9c683c28356f08ed5ccc0c9390d55390b9947797af17a38b99c6ec9402cd9b12240a09a703095f95f115e64c4b03b5	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602932661000000	1603537461000000	1666004661000000	1697540661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2aa1254fc8eacc34f1e824d6518d20186e015c459ebc5daf400e75aadd0eb332bf9269709d56be6786338b960e233e9637a78712ec8cd9a3df4c419a7fcdbf72	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1603537161000000	1604141961000000	1666609161000000	1698145161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf74021133cfe96fc9645f1b04155007571785db9b9dfecd6dc41def971f58c641cb9ea2973d962c5f2bfb268de24e546900b29b9a68213f40b00ad397a9e7fb4	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604141661000000	1604746461000000	1667213661000000	1698749661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x019e9cd38bb3801cf545b73e8986ca8fddb8fc02f13fee7f54db36a8b1e02aaafa8bfa14bdc807e07ca1672ba3583e11672de11fc0a1f6d397ac9c1211e259e8	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604746161000000	1605350961000000	1667818161000000	1699354161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x50cfa43cffe67639760ae25b09fe7cf6abb1d3c2fdced624f81cae62334f7277d97b795513e722c320b17b5749497295cc1a0564567961457741008df0ba8664	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605350661000000	1605955461000000	1668422661000000	1699958661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaadf560c792b907caa787c4a0a7d3af605d02b9ec83c9cefff18b71c6877fc866d4aafd0cd616360b59c401c12249c73a8e46313eec906a6455fec596f42179f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605955161000000	1606559961000000	1669027161000000	1700563161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc07d1de4cc57969cd2be953086cca1b7c65d5f9419563835bc8447b673b797de817b7aa89d1adbd8d55113370f75eba8de757f9a184e96660c04a384a1081243	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1606559661000000	1607164461000000	1669631661000000	1701167661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x75079a83146840c633fab33417b30bab75319667ebf3cf01b618f4649d07ab086a02c011d15aafd05f6092f963a3aafd8713316fcf9e6a35bc89005a29504262	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607164161000000	1607768961000000	1670236161000000	1701772161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47c2647fc02bc29bacce68891c6691bcc97692ad5b2fd6f671719880a3192417d50a2c908df1ae28dca2f97a0953d28c7c87567c07e4a00156925d0ce37f08e4	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607768661000000	1608373461000000	1670840661000000	1702376661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xee451ebb3c720803906433db9ce91df715280fbb17a42f62e5aa287c759113f57e58b47dce6a3976ead8ff265732ead63fd2e87eef70981bce171b8a71d15dbe	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608373161000000	1608977961000000	1671445161000000	1702981161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa07e9a4f76f96c2d5c0abd206b44f7bfa2732381a741c51dddf8521a64a64783806c1f3607918bb9dd62660275d7adfc41d53cc530e924d2f7cb5944f5c99fe8	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608977661000000	1609582461000000	1672049661000000	1703585661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb4e39d228e67453f7d3833c2ee8bbdcedb4daeedac147ae456166e8710b730383f3161fd266e0fb88ef7d9b4d0510752aa39da35e8e6e3329ca1faf119ac0b4b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1609582161000000	1610186961000000	1672654161000000	1704190161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x17e2804f3bbd8f1ce7019f11613a0c2b25aae424a3d537273250d19f0d4b41d12d14add3006298f19916b810af9aaa8ca7df30b242829847fda2ee67a5ce8bd1	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610186661000000	1610791461000000	1673258661000000	1704794661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d4a37ac265b611d5c5fd8aa3865f7030c008df33b5750411fb3a329bdec98ff601cf5f3ce54f4d6f51b0f24f3f61a3957d8598c93e9dace8e3418514d4861c3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610791161000000	1611395961000000	1673863161000000	1705399161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf512346a37b139c9faf118f8ff9529d50922bfa3cd5bc404cb377fe3aca0b086029444d2284e38dc7838a4c5181af3ddc42c70427962143dda66407c71dfdf95	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1611395661000000	1612000461000000	1674467661000000	1706003661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x91f04e090bf5e84fa4f1d69dcc4d399fc81bd555065c81b1e40880c107f9a7eaa8cffdca306856cbbd90644939f660398af1787a66b1a2284d706a73dde017fc	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612000161000000	1612604961000000	1675072161000000	1706608161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb0d7311b3d7bbe9281af724ab20c4a3f15ce64b5b48b36e95b5da33822526aec5fbe5a51f42d786767103b9a51b545b83fbb1050231171d0f0ff8d3a06150528	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612604661000000	1613209461000000	1675676661000000	1707212661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x540c1266e475294bd4c99225634cbc6beb471bbeb0ee60a5c27090d9e98cf8aaf11aefb51a85c44ed87627edc921733c6b6a078c12ff9cf06df3b8d91b77c066	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613209161000000	1613813961000000	1676281161000000	1707817161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4079cc97404b1bc066208e951f0ebce7ae41646d98e79b1c7c584fac84361a965b2af9d465c5e0df7178416ed6070319dfd217641825dd5572749ec1d809965f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613813661000000	1614418461000000	1676885661000000	1708421661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ea2d2181d79fe53baf70e9bfc05473079849593df0f391354cc4b1a38af8f65fa129eb3c03b95b48e2728a3337970e560912408cf3f1da1ec40dabd50b6cbe6	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1614418161000000	1615022961000000	1677490161000000	1709026161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcb8d73720c46b3574cc53de2e076df8e448a5ab02b1ee50e71023081e8d71b64a8bf982a41ea3b6e5b2dcd1cc60d4a198268445499cb32cae6df1e2e7dee49bf	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615022661000000	1615627461000000	1678094661000000	1709630661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x67d254b6bcc1946f17f87139f08c79951f44d86bf481ad0c716ddb9fb3a25432861cde89fb5f4633b2c8a25f8a88078221d0e884868573e5bcd40e22b29124e2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615627161000000	1616231961000000	1678699161000000	1710235161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0b3c17c8b6435342ec683486fdfc4f86bb982331b2dadc27fe7ad9584294a3571ae426f53e7db37d3ac369650b9ed19e3a8189cb0b3fbd588ab9795b3d57844f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616231661000000	1616836461000000	1679303661000000	1710839661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbe32caf0117413b2bc73bfaffba2fd5e68dd8a506ac2e12a4b09bf6eafd27ae0e3c521d04c9a9b63c04f42741fdcb6272171a0810c07607cb9f745661981551b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616836161000000	1617440961000000	1679908161000000	1711444161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x02e4ada469b6ddb6163b2b38da19e9f2b0271a7806a8b6548ccb20811bfed967ef86f429bab819189b47e265a1bacddd535dd8e02e0fe58b6d97d3b7cb7c6a63	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1617440661000000	1618045461000000	1680512661000000	1712048661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd64b5e87675c4205c3bf6ce18537da9baa615732e2de6ea3d70c2f5af52112762b36f415ed3d17352293ef12df351a746cc2729cf2dcaa2fcf936532a95fed2f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1618045161000000	1618649961000000	1681117161000000	1712653161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd9b1658aa22170a31481fe95e0510fec987c8395597d011641837e8da25f4bf6d7723916b48c853f583cc20401ca9d806ce9f11542e808337ebaf5fcef31666f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x45fb45c9008e4f2a68736633d2d605af6cd924215950a52ead33d669620b114a859e6e86aa4f1838c173d3bf42b276a1424061ace85804716baf5a0d3a7b72e8	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb9b00efc2fcf9adcee34a17fbc4c871276cf2a1f74de2c204841717ae8bc8ac9b0cf0478b5316479c7eed92b06f2d4c2a8cef3660c9639afcea1db204d543f14	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599910161000000	1600514961000000	1662982161000000	1694518161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc2a1cb7562e7660bb8eb6fcaccbdfa7bd50e674f6ab9e93e452b15fc69079a6d710374eb23cf3bedc9309cb9428b049e7fb011251ea0d8acbf091577c7eab9f2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1600514661000000	1601119461000000	1663586661000000	1695122661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x52135e2805160ca6157211b3c35391085595382f0133af98e2b44af1f4235fe06744268e8212424dd0810f88173873b1ee7d7763d618445790b7ee6b59f1c1d0	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601119161000000	1601723961000000	1664191161000000	1695727161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2ec63c81281f562bfe05edc644b6d25eb0fbc56e52a0cc027de5bdf1c63bab4433e4aeb3c8554406a364c4d3e520071122a04053717aac25f1a974152079def8	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601723661000000	1602328461000000	1664795661000000	1696331661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xea525a23fd2ea6cdc5dd9da5e6c6b85e5a4e37b582b020f3b8970ebdc4c2554028e1b27170b2f783012348d148016af50de7081a074bc816692a4f3ac7b71e4f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602328161000000	1602932961000000	1665400161000000	1696936161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xeb242d1ee5bd9ad22acaa0896b75aa7c4f2a3037d4ad994c48aabf00f89b4fbad7e376c968c7b1633dcf65fec9d425341a5547d9115ceceb7be62e1cc0a1a39e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602932661000000	1603537461000000	1666004661000000	1697540661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc4a388d7190e07802376e7b9bdf5659dd9eb7958a3dd286a13cebe3ed35f8ecd211bf1dced8356796da8bc45440637b50076bab08a63b687cfd2c474911c4b63	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1603537161000000	1604141961000000	1666609161000000	1698145161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x20c851a2f1a844ddeb4032811f6442a38bbd74eea41a2a039cefd808bee50b00a62b44b1fe253d72a0ebb07b0128abed72662a284a93475702007ddc23478b94	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604141661000000	1604746461000000	1667213661000000	1698749661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa8cc15e3b5bdff818ed247a3d1434f40db5ccde533ae70a30819af2aa60634ba034a0575700d10126c80e0c8fb2a96290e69469f30fab5b75b82e7e79419203d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604746161000000	1605350961000000	1667818161000000	1699354161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x686a6e6f633992df7e250c900c155bc07483d8cb6f7ba8fc1775a269a86188ecc152cf13b41d197e74000eb34e2d1d1627e8785197c8e9f2d64454ce776f7fba	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605350661000000	1605955461000000	1668422661000000	1699958661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x947b3720314095abbc4277190fd2f39e8c4e7c9f9ed53d458e5320b029b485079a55cb05aa3d4b97f0a49b33026d83a3f1a14db5cd8ff4e86457b198cf98a417	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605955161000000	1606559961000000	1669027161000000	1700563161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7ce7bbdb539732265394d6e51345868ddde292bb810f24a4ad6c57faac79440157a4cbd08366d84746aaa4ccdd7c5950ba91b69a14275927c95a8143b5c16495	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1606559661000000	1607164461000000	1669631661000000	1701167661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9df21e333d989b20872616f9d71e918d53ca41bbc17d15221aee54482aa47071709aa07d3397c6f88250599f696b73d8db1a76cc8a9e263e0a03a8231c773195	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607164161000000	1607768961000000	1670236161000000	1701772161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe9083a5527d86114f28901dd419863b019fd7de2f762d7f9619fe5018ec0d639e658d91b571b95bdf291a277bf895f113d5fe721a192e1dc59a22a71cf20ce4e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607768661000000	1608373461000000	1670840661000000	1702376661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6d06c13c9296334279914e276ebf78d0c210de7e61851f72e603505092ae687c508076f97b5f1b0c473fba06779061a198c05ad1b75dda63f158b680ad2ddc6d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608373161000000	1608977961000000	1671445161000000	1702981161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb4266722ac3da8a5d4ea938e40b697274dfef140983232006897ce528cad652f3fc7f11a8f4f004e805c7448e56476bbdfec7d8fbd44d64d4882cdaa47cae7d6	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608977661000000	1609582461000000	1672049661000000	1703585661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6d9dfbc855a2211bbcf65a0aab18f79cc953f62cafd74e2ef1bea7dfe2839bf6b63762683f82d89871ef0a22c2e6c44642fce836337f474b4fdd26a8d9981cd3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1609582161000000	1610186961000000	1672654161000000	1704190161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1b31e02ea08359c9533a5eadddd63a0ab2295d3535bbfc3f3602be1a776f1886509c5c6ff40ea090a3474716d588af604d079e1b2eac6677a9f57b825a080435	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610186661000000	1610791461000000	1673258661000000	1704794661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdc797c56a17afd517c22b360391ef75071f448430c8d68d072441bb2543a14d9b38ef3cc1568eee39c48512f7389a7effcc0d6f4adf1896c48fbecdb19130373	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610791161000000	1611395961000000	1673863161000000	1705399161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb0c9c5092e00a6a9dd44f54e407ff19ca4177d6a41d9d22ff34eab92c8c1c686249beff9df44e00c97848ebd815703474051a9bdb30e33c3acec102c67e2adb3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1611395661000000	1612000461000000	1674467661000000	1706003661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xef1f74724fc645e8da0d1d39e1da4ee9744210c321497e82594b01d569f390e9d0b7c01a3bc3a427efad31c54992a4e9eb2f98c0a8e94d3b89dba8355bcb4d27	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612000161000000	1612604961000000	1675072161000000	1706608161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe38e6c9792abde4d7f4ab78aa6fdc2c4e84f89450a9494e7f53a893d1edff45c35c5c94b2e29c3d2dbe1f7f3a136058410f0d6e4ee7506e4e1cc37a49818cb2f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612604661000000	1613209461000000	1675676661000000	1707212661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9f63c98014228c28584b30c714d80db0d6001e08fec456fd3af8355b23e3a054296620ab5618038d2773d01b25df8251a4817fc235e0e53b80c22ef15043e1f2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613209161000000	1613813961000000	1676281161000000	1707817161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7e5be8afd1055ad7f4048c1ac5b43d2dbe36f4e4f958c585f6f9997c1099328a31309b511ce8239051be89106f89cb3788507cee0c8be45adf3eff064a2e2dde	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613813661000000	1614418461000000	1676885661000000	1708421661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x391d6b6b8b8228836f12812e94b3f7d3cded4aa8c55857e2ede336be411afd061ecfc204bcb734ff400b078e423bf20062cf893ffc59002189bccf9308e5bcc1	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1614418161000000	1615022961000000	1677490161000000	1709026161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0338289df7da0e515ee0b8d7a94d7069eda39f4a0fb7b053649bdb1116c43ea1544b5cc73d03d3860eb66fa8bebae3793be52d8cc27e58736db702a9dd265edb	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615022661000000	1615627461000000	1678094661000000	1709630661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5ba59df40e41bf871444940d17319c320fce3617aa6710ddfffcd79855625fb4bfc62a2a8992cc224e27691e79d29588013dd8fc8b863d6f9b03c400976d98fb	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615627161000000	1616231961000000	1678699161000000	1710235161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe222299aee8dc3e6e9f1426c7c4f7aaa16453611af32bfe345e0e8190c8a49c31bf8e297d5d5bd240c97c6fdab92008f6ed373dc02134fc390b65c2b5f651d69	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616231661000000	1616836461000000	1679303661000000	1710839661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9aaaa3c0d6e79d937bc088212d9ff587c7f719f91bc2d37393919930d02cd63e6ca8401f63e11fa2408bc1ed26f2b01c8ff06f8ab949da9bcc47c1ad69cf8bc5	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616836161000000	1617440961000000	1679908161000000	1711444161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb57f110fbb07250d093e6693be2088b09802e655e7259196c7346c36a952d607eaa8e7fc7a88000338b99259c152e478e88b459bc29ce7338e38cd965081e29c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1617440661000000	1618045461000000	1680512661000000	1712048661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6add2554c9dde8bc05ef18b6a4cf0750b03a95fcceba04f7efbbc3c257132863b71dfba077c5ff4390fba411bc5b509f01426a76c44a31befd57fa38fcfa6dee	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1618045161000000	1618649961000000	1681117161000000	1712653161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf30730e1a20318c207a00fd62386fe12f8c3c0f0f9fa9df9d3ff251c6a9acab6456c054982c78c785e06e80a9198ce55c6c61b9263d30910e325db1ddfa2bd8	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599910161000000	1600514961000000	1662982161000000	1694518161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x281d36b17b08c25b8133695ec09b73ba05652625344ea7469e60daae8eb30dbc1cd29b88cad209d34ee200dcf501d736a43c43a5180addfa927623cf64bdcc03	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1600514661000000	1601119461000000	1663586661000000	1695122661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x477ecb07d4f8e806bd4a0862b6cc3f5da82280bb85945e211d3b808da89183b76e46935e13cd9e8b0152163d072fbd9ad61c75ad77db108a2f0f5c4b61c17622	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601119161000000	1601723961000000	1664191161000000	1695727161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x84af7412b772af01812915347c560befb544e00e45f269e11ff1512a3efb2e924c65cf2c32ccddcbbf5efce12c7f846d7063036c6e089aad34f629b5ed70c34e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601723661000000	1602328461000000	1664795661000000	1696331661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xed95768edc7b9e5d1024c9e20d9eb7fe65e77d4480aa436bf315253dc18fb23b624ebdbcdf2255ae370bd759d26898c853babf6cb67d3285d69115d69631839f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602328161000000	1602932961000000	1665400161000000	1696936161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8eb69da34ec80cf3ced5b183126db37baa1fc80a30d030644671ecfddfef775df922048e16615813c9b0c75ece12d47eef8b0af67c47ad7f90b2e85a6370de03	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602932661000000	1603537461000000	1666004661000000	1697540661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f50a69a9c5b631a6479bc8231efa87177875f927261933c6316f63474b028a2a8de0c4babb06c8824e30e83379b36062241aa83ff4d1b4a060b41f56b86ea63	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1603537161000000	1604141961000000	1666609161000000	1698145161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ee75302502f635bbc890421c31d37e44bae1e700bb707ab1eb982fe5218c73c2f6c4d5b6966f2768d799d48ac330cab31d846e613635553eebd3679537fcd4c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604141661000000	1604746461000000	1667213661000000	1698749661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0640d6f6f9de708ff777384ffdec5a9fa343b4006485c4e1350c34572f8951b1e26e6ac576ff75cd87c5fd89b6d3f38c2cb91437a4d95e76c479777b34312580	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604746161000000	1605350961000000	1667818161000000	1699354161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x17bd203e2d08bc6f5d1249c9b0f5d88156e92a84946fa769a55175d65f82d401f2f46c0d490138b4c55f9361669f52c9dd5cb1af875d6539c5b5232e97e7bfcf	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605350661000000	1605955461000000	1668422661000000	1699958661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e588e05815f85e81ecb58d23ac1faa9c37d3e711ce9cc0fa4298a0a4e0571f8dde744d775c605af1323e1c652527cf67ecf429304163991774ba894d5ff9a4d	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605955161000000	1606559961000000	1669027161000000	1700563161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4642ec99135868212d28999de2a944de2dfdc7309adbbb8f2d403280b29380b8435d56e7705cfc06caca00fec7c7fe81687ba736ba2d3ff45bbbd6018c772fa	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1606559661000000	1607164461000000	1669631661000000	1701167661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd93efa9a76718bfcb0a737cd3d092ff4a7bc673b6e12d4c3f55f862da332684b81460e51796b7b2f7ab5774fab87023479c71b8d2126c646d01e81d44bd8be42	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607164161000000	1607768961000000	1670236161000000	1701772161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x25f239e4ff11c2ab4942b39f1d1d23d8393999838a634c77e3bb6b3711112f11b71eb2a6840864db76aebc027263915364e6149e06f48a96ea193e8633ac0b43	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607768661000000	1608373461000000	1670840661000000	1702376661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x61bfef24955c4e6c41f556db334287f212a884d5ccd53977dd5d922d8cb62f9585daa3bd0a622820586ba680da9a9fcd1cb9719019812628b39c3b1b15744a71	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608373161000000	1608977961000000	1671445161000000	1702981161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e6d01a6e5010413dcea313c231b59a893cce2c6ffd541a0a094001e3ef40f7839cfde9ffe51a2ebe0dd107b42761e6925d64478edf2c48ba98fdc7eae978197	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608977661000000	1609582461000000	1672049661000000	1703585661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x76fc0639a7d7cfe1f347b8d03ca965da7d5d131f1371c284cf9da3f826fee9c335b8e3f28684b076fa88e3b20326faa38b43dc2f028143972188362ba5918684	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1609582161000000	1610186961000000	1672654161000000	1704190161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x189bf52eb36a63a02979278ec77cb7a9fe8b627adcca8ffbe413a1957ec640977fe076033acb7105b7f16d1406f5079ffe5353a54f92d49673784630a7a6d6bd	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610186661000000	1610791461000000	1673258661000000	1704794661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa207a8fea497def68b1249f9317b1cd4cdd9c66964bfef505e9e0c36ae5884c6ea147ad9fe0a70b302e6a542afbba4d229cccabde48d0e28df9eadbb4cbb9e2c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610791161000000	1611395961000000	1673863161000000	1705399161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd2e99e6bf4578f980ac32d4fbc1ff2b20628c7b9aa8ebfce094feee46dc82f2fb1515a6a26713995b870af4c20aaa70f5d5990267ca3fb8ca694c742adabc752	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1611395661000000	1612000461000000	1674467661000000	1706003661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9f1303d5b399dcc33ef6f378f790cef46dff48358a37ae508cf4359114ab967f8f5ef0a401334cb5e7301d24556fc23ed196ec0500440140a4392d89b554ba5	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612000161000000	1612604961000000	1675072161000000	1706608161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf064e9b23dba79d7baf83c2520c9367452b94f365abd6b3a6e09fd96d97b80ce2aeaf03a9227226cbf102c336e09fb8e78a69af9b1ba681a2d40900b8b46d6a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612604661000000	1613209461000000	1675676661000000	1707212661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa1b81ab876451c4ca92f6a20de41a6bf1d552974fdb21c7b5205e94a8f57d7c902ae6a42ca6cfdf93798806aa0bcce7fabd4e8b90adfe7e628dd5c3507909cca	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613209161000000	1613813961000000	1676281161000000	1707817161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c290b1a3ce694ceb37a42927a8e702bcededf9a94e673774c39a7ba61f9e296015790861812d7d07c3608424c01543e2e53bf7340f5359f0883366b50cdde50	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613813661000000	1614418461000000	1676885661000000	1708421661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a8819f7e95e6fca53c758630b9ae07aed852290a89f8db8e1406c07c67fc0aff435a19d586a1dc1787185f078b63dfd687c42e66799671ffcd19185c5c62061	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1614418161000000	1615022961000000	1677490161000000	1709026161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7eee128fcadd0dae9c5186097ab56c17e232bc93ad07ef8000178c5d82ef62cd881e4ee42ddd575cac6099e0c74b6a92bf6c39475b7958b692a33a91c2eacb1b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615022661000000	1615627461000000	1678094661000000	1709630661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0103300670976eb629adc28e72eb3666ffb468a0dee0eee3bb8a985d66d84b3e8e3f6d6b00c16c231568386aa09e853a0aa9fd0b03799f68a969c7a3d2d7f8a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615627161000000	1616231961000000	1678699161000000	1710235161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x60d0308b36d0522d49c8cddb88eaeaede3e3fee7a40d0269898bfaabf527d73f9b274c955c41593a86c6f0ddf9da090aae64a23f54009de5a5b8f37f2857a66b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616231661000000	1616836461000000	1679303661000000	1710839661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfccd8769f6a9435701f951d89779824cac0fbc9a4eb325834d7edf14230db697bd18f019a091a193843b3b16c0b6dad8ba3f0950426efa98da2b8c6941217522	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616836161000000	1617440961000000	1679908161000000	1711444161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c140752273e4bab84be9fee5107698c709b430cc9f3130493e467da1967cb8b7ac1ee4b180fa29e59d4718879b8d6a48073b870ea0a8dc75a9b5c6695ce8f46	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1617440661000000	1618045461000000	1680512661000000	1712048661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x04089f0cc71cd47e1fc19863848790e16d51636f332cddba06303a93e5f30b7ebafe4076574721538950211602ac4671bc5292795810f5e1c4faf1210b4f4298	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1618045161000000	1618649961000000	1681117161000000	1712653161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0d218fe7bd93f741663d5a204981f7722677d86023b452cd565b26072254b47bc73f2f3b780871348f6ec4f14fa5c7a568b0ba9f39272040afc64ae080882236	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbd2eb128d9751bddb90e755ff1f0db354ba6463165b12490d389a7e20e7f7643163177293d28e1195e3be0ef78763e4aa961e0b3ebc265e789c76e7b64db5c48	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599910161000000	1600514961000000	1662982161000000	1694518161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7e26b1fcbe9f268206eb35ed491cb6f54472369174e702241e8016124ee48fee86e46a4283657ff4a1b9ee80a09d2c0de34aa374908e91e4e11614c395ed69c9	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1600514661000000	1601119461000000	1663586661000000	1695122661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xac64b5220413f56d7f0f24ce9931691c7207fb45a9691716fb0917df4f7b976bd0ce8a4ae3c3b74983e1d639c8564f409abc35e3a0735ea188e8b5d861f45c24	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601119161000000	1601723961000000	1664191161000000	1695727161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd0a5cded497f1a4cbbfc4c1566b8cbb549d74bc85d30dbbc9043ee13294b49703d86c41b14ccf1a2a2bd1439711cb9651ce6482343c6b3ee29f234b2c7883960	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1601723661000000	1602328461000000	1664795661000000	1696331661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe7c6c5b03146ed4ff8ba1be796db0c50ce3602831b5e81e8c423809d1ab263ca5f9ce78128e7d73a3ee1bafce7cb289f5d69a093a3923fecc5fc9d7239e9ad7f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602328161000000	1602932961000000	1665400161000000	1696936161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1a2322083ae7dc324843f0fd4e08bbce9e2771b2dc15b22b8cb8cc864b37b7e907e04149f6e45469d2ed47313a374fa45e087520eb253a9b4891be1d6c8f5af5	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1602932661000000	1603537461000000	1666004661000000	1697540661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbb0aaa8b42724dbebbf296d10a381a848dbf0115884172fcb28f41284d76a61e799b42757f7d100a0c16a744194a282c41b86e22f5362553a0140c79d5e178d9	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1603537161000000	1604141961000000	1666609161000000	1698145161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3e6b4ec480a044f95f02638e16006245df614dcece21ec267bc82dbc945b35879e14a66d46f6f8751817ba63543765cb1e8098ee382e9838e9b7f61c7f5fa6f7	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604141661000000	1604746461000000	1667213661000000	1698749661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x383f56f62f9a95d1ad7a54c4fefa9f3f2328eab190bf99440fad1a4b508d1bc173f90c0e70a094901b74ccd1255c0181e50e3c1c140554189b6197016a87a534	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1604746161000000	1605350961000000	1667818161000000	1699354161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1ba5c5251a0c8383e0d1e764dc7b07bd92ed42a6036c712ac284286ef62accdcdc49c0c71c3c6cf1227d07a07136e9e42d7886280d681e91ffb160e39e35ecac	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605350661000000	1605955461000000	1668422661000000	1699958661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x24adf1a535a51bdb34aa45257cffb2e28efc885ebd263f9a74d09467bb907f23e680c1181a7080abf6d90d5326e6a553297511f7f3a5297202248660931fe19f	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1605955161000000	1606559961000000	1669027161000000	1700563161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1815c5765c64e5ddfdb7152dc06d862c714e33d44a57c44cb0d1fabd3390206c7de170d78f048eb6ed35908d39cfcc5b9cc741925f58f058a9a785e73329498c	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1606559661000000	1607164461000000	1669631661000000	1701167661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6d8969748a5ea2526bd0a19ab932bcec71ebca69e04b9cbdc1f2ce8787882e079c356b704467c06dd1428c6b281e664ede836b18ed604f10db0a3fb736f91108	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607164161000000	1607768961000000	1670236161000000	1701772161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd1c14d0e5d546521382f74699dc36e55d879615ad2da01a9cbedfb07cab73cb37f59f470354590fd2a68b91ddf610a8eacdf5f747a4af5402a874c375347d941	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1607768661000000	1608373461000000	1670840661000000	1702376661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe7196a5e0e9d1c0662ac21f3738377b8f3746851c65ea01f8d440ed4a586b18cab10ce1d685599b605d4f59f3ebbd00e88c454ad78d8f107d326a55742603331	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608373161000000	1608977961000000	1671445161000000	1702981161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb81cde30762132986c471626a283344d74f6ce7181ed8651480c884af86489401b988d4c86704be9bf3232d8baaeecfd63e89de2e7fc098dcb13e85c28a9c6f3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1608977661000000	1609582461000000	1672049661000000	1703585661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9bd44f8db2afebe9b89cdf19db02e31a16225d3a59242a659e8e0560de61571dbe0c4b0502c9405e7f03fedd1fcfb1651997fa8eb2493d0a4950a528e906ed19	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1609582161000000	1610186961000000	1672654161000000	1704190161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb26833f693f61e73e2aecc0dcfedfd942ef363f1d0cd1f457e9ef1b7e41651a84cb47460659509344687445a0bb032d7d18a3a914c64ebd7c6f4d74bacdd4917	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610186661000000	1610791461000000	1673258661000000	1704794661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe2805c992a6381ecaf647429d7f987a8a988c8e48e560d7de9a48188160804a6c4a5d29d0839b8c55c7ee22b6680dae26374799d9b1240c484203503cb7f701a	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1610791161000000	1611395961000000	1673863161000000	1705399161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5c9ca517e205e5f0b56046b367fb73ff6b3b12fdb226f6f5e5e16ecaf43c0a0aec47b0a80d3e996280ec69b031656a20288b37978972e36966a2447da5fe81a2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1611395661000000	1612000461000000	1674467661000000	1706003661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x964cadcac6906454ac33efc53abf453b2c2130362c6f3a26890ca0bc15f339f4a76bd55ea72c87333faf1175b899d0dcbf085c53ae048d0994605a0efb6c666b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612000161000000	1612604961000000	1675072161000000	1706608161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x672e96edf9a7b05aaeffeca14b5d52d0b74594e379af89ac221cd139d3f65cb401d22699ee656d878441ca6334372b160c15b3c9abdbe1fad34f35239ebb6967	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1612604661000000	1613209461000000	1675676661000000	1707212661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8536614db2d830e1798ef5751763255142886988617044b8e4a58132825f690a12b9eb658f8f680abb3e6c77350dd5d3c99e7f7fefa647ff932bb2010f0cf216	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613209161000000	1613813961000000	1676281161000000	1707817161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x79eeab4a84e2ee92814d452297b1f3c4d3fdce75ac72c566beff4283967148880c5718e635e564bb0e48821cb28340517933a6264d6339abeb23c4d7aecb0e81	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1613813661000000	1614418461000000	1676885661000000	1708421661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4c0df72ce7053f14094423de4870c78ffaa688043f5b635f646ff8413770eb89ed9c4a33237702815a0932645e687cfa3d9dfca5bbbdf347f1304736b40a2bc1	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1614418161000000	1615022961000000	1677490161000000	1709026161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf0cce4fb80ef252d7631ac545a786907b5a3ef8553cda4da312ec4a56034b933cc508dbf2a196a8463abd5a98d49114058e23b484a05dc0040a695ee942c28f9	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615022661000000	1615627461000000	1678094661000000	1709630661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2321d84568bc885648f16bcfc9d5fd6836d4d2320675ea7c3150ccd3522078ccf051fc068b084287b31552135f188cff7d9ed7fd4e3d7051a824ba6afccae1ac	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1615627161000000	1616231961000000	1678699161000000	1710235161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa553ff6841729190d25076abba246529e65c640c4f3c4a230a51e57ce852ddc5a7264b87f05e23cd2099fc76e21aa7eec6a8fbd69a6ca3ba0aab906818c75b5e	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616231661000000	1616836461000000	1679303661000000	1710839661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x71a9292ca070667177843bce36d8b2a412193f939773018694306d71e79edfdde3496ce6932a3159f47edb7aec7d74a61ebdb7e6bc821bfbd39307da19b583b7	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1616836161000000	1617440961000000	1679908161000000	1711444161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa98ce4031d5fa5c769c801ec8741ab0376db4856cb06d04b7596c5c551611519ca3bb56fb5d83c8e3757f7defb08154283f8cbc75234eb0341ea938224a5a9c2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1617440661000000	1618045461000000	1680512661000000	1712048661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4b858756065f0c76e3257d1dd6258f64bed5f529b0a47051b4922e95830f6f9172d3e69803db0686640d8449cc541df4fbd5632ab07ced1a8dce611d1179925b	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1618045161000000	1618649961000000	1681117161000000	1712653161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6520a33204d25810bededec09e1e2d904fa239b5c20f8763a1d7032fc9e752f99b229d6721f73985d186cad41b2c5f1db50ac46c100a483b3129e55b2c90bae1	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1599305961000000	1661773161000000	1693309161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1599305661000000	1599910461000000	1662377661000000	1693913661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1598701161000000	1601120361000000	1661773161000000	\\xf04c1a56f0e1a9bda14f99dc8f82cf5aacb968f0e7469b3047bca606ba20f21d	\\xb97f281951b615e4e7efd6c7be7b3252b6d3dabbf27957bce1e921e3ac8ec841a84c669240b426236317786d5210b3fab79a1db285f97fc93358c995eda9b60f
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-08-29 13:39:25.730207+02
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-08-29 13:39:25.912724+02
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-08-29 13:39:25.998142+02
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-08-29 13:39:26.082257+02
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-08-29 13:39:26.164537+02
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-08-29 13:39:26.248612+02
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-08-29 13:39:26.331436+02
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-08-29 13:39:26.813092+02
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-08-29 13:39:27.312092+02
2	pbkdf2_sha256$216000$bkfz0aVrYr4g$gAFoYgJgm76ia5QcxkzjEcy7CxWMOjK4Gvz+F7yTEQk=	\N	f	Exchange				f	t	2020-08-29 13:39:25.825155+02
11	pbkdf2_sha256$216000$Be20gL2YNR0V$fjvJF/s9e55sltaFBSQgdGv8iZJXc3ZZ/SEkA8EqxE4=	\N	f	testuser-dhrp2zur				f	t	2020-08-29 13:39:28.53204+02
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
1	\\x4b468e9a59d54f59c4f77077fa1c46298dbbe8670b5b5c123fb363db01317a0350760769c36dedc61c2ef65f86288e837c725b3f9ed18990e0288db11bbd81ed	\\x0e1a605f49efb35f9ba3fee2e42eae359a294d88d10146bd0378871d9f6f3e2766211c7b27af0b24e3954199d826cb531f25edbec809b1462d8f72ff2ec3e00c
2	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\xb0baf47c16c0afd2cc43c596cedcb18ef78d711d6cbf187ad3f4091209bd86083582b88a68cdd445d91d6e5f061da40d9575a3edf8b9d8aa21a3e51cf3256a05
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x68e8de755e60985bad709dd7e46a1e7d8677e78c78e687d8ed7eb55fe6a1ad5518fe53894095b5eb2ea1003f958c0d567c41620b5c2f86304bdc1eb62b49e7af	\\x00800003e6ddad0fbe599189671535d40ebf0ba8ca1fea80d866bfc2244121b1e4ee781927fdca7547dc63460b87facc4ec02d13c8153693bb7aacf3722dd608ce6915670aea16b4af9de218d9cd775b35fb8738dd2092ef934df5e24a2b37abd9422f08e0645cb1cbbb08b73820dd35c9f4aef49b5e854885dbb3090c2966ad12a36897010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xc55dec1fbbed7c0e4d4db937d03297ccb5ed2c3b0df04e53a93ed339d5267b7c710bbe482962ae3a2d722e03f680d23a24d069c9b233278202f39d9b20dc2d00	1599910161000000	1600514961000000	1662982161000000	1694518161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9d9a55a229ebf64b7cc988f619ff43c1c01b2883a281eadba4f3eae9774a8180eeab69b1c85553c0b08e49043a868ba0aa85ed5cedf4ae6cf19a59b94c0e833	\\x00800003a89e8ff88cb536b2cc00b70596f1804d8f37ffce5c9232db9393118bfcf90dad6ce461d0ac347bb9025d8cb923815144004ca823eb9f3423ff505dbac771708161555f77041a0a3ea26d309a762b79c17d86cf97ebe131bf3f531182d2579434ae216ab094210ea4b228811d153949622567d487874a7e405c65a78b2dc3e887010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x906e52a309907861e3ec08f202fe1773feed03a83fa7dc3120e083d7f56adf1cfc1578fc43537622782785a46730dbb3d82c839c59bdedb03e3b1fd6faaca80d	1601119161000000	1601723961000000	1664191161000000	1695727161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x800f789c774f751bc87524032008aaf422a00fc6245fcc9204e5655e35f456ad0f6bf6f72f3c175bc451be41f8729ba5aefddd59adb782d5055bcdb3b432afd4	\\x00800003ce0d64d67222e3dd1556da7a7f4511c49debed0777aeb5791c379851d3dac77236dd97ff518d6d4d8e789ccf125b7ad2c133ba1eec8cc64a444e6b2d1875d2605270dbcb6b4ac8c91fe385cc8ea4faaffb9695cc537d7685904175413bff2ef275c1903c8b7024d483e362862cd5ae13f32f945d68734b97a3d276b925c9f8a5010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x8c9d297cad6009689515603f2c37bca0a78fdec0d66aaac199cd713342cb2b681d654981a960e8ab8b53103537c41e0d54f8476926a9afc1843c55aea9ffb603	1600514661000000	1601119461000000	1663586661000000	1695122661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2ee20cd7c4a9957838e3a709c0ccf0e1cec902cd98d6eb2c38e9ef44a8858313cb1ff38ea96487a0a5d485f431e3ccecaae37bce661b3370811cb9092d8be1d	\\x00800003e6e73011da3fa49edd55dd11b34d175ce9e35798294bbcdad717ba6c5de654bb5259b7c667af36acc6e4c83c3aad21eb9fc87a2e7c88fb1671e30f7b2c665b7b7492d6b319ed7a6b1f0a61ad47621f7b9dee302db7f7646a3490e709cba49ea00b80b70b9b624f6e7121779e9cf16452dc6210cc5ee40e6f462d33b08a859115010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x413596e7f32e894c9ade89ab7145bdabf56859017288036c20913bf1615a9ac283d8c71bde0daf9b6399a605215d5c4ac5eba47b032efc0620f7d6ec06b5ed0f	1599305661000000	1599910461000000	1662377661000000	1693913661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b1f107f719abfce9fd4458fce91376237fd4555cab8dc3bd99b3a54fdd198871e05270db590762f21ea397f81021a87ef5dfa78c447c4f9ac3d4a245457a7c9	\\x00800003bf787ed4ea3b8c8ff9f586b6ebb299af47d05f35bb36faa999101b9a47b99df253c6f37b0432179e348454f8d59ad730ebd102891fd54b13d5ade9ce8e6980222df9c44a9fca55bb50b8b0c2944d8aa79cb10b50fdce197de228596a14612c363da1a7b091dc441914ee5f4661c82856b39418b6771a1ba63fd7aa1a6e7355e5010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x5499c2f5dc67bf3a408edc7e2a75d12cb892645af3f9ae21c3cd90eec1fd1fc35c573f2aaf8f144ff2aa1b0c158c3890a2b24603ca63d3ac944be3965b3def08	1598701161000000	1599305961000000	1661773161000000	1693309161000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18434981d4c0ce801368e9c87ad206ffaea6d5eb4ecf5832b0cb075b3d475a3db23f53f753ce82670365fb85538f790c05862fc4a1d6d96e42ec63c7e5d4ae35	\\x00800003c2a011f486f34f868c9683127179a735d8d96ef138a606da2bb4403af6223366258d664a5b2320f532e82e84b7c777ae76db6902e25e72f597f7aae5d3d337ba7c1efebf692a3654db18deca619e348378be6033ad6382f704cbb8ae3aa265ce5ad0f413edae833b425054ff14ea59a9b2106d5ab7152cb8f2b65389773efd85010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xd2f2a442d8d8e73c5226b96cbf87988e71a110c370b96ed7a553bf37e289ab41bef8310f557ea111154effae6e319936d68963ac67b4d7b46489bb21799ae508	1599910161000000	1600514961000000	1662982161000000	1694518161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x95ed361a0a4bf66b387ef3f8500b6279e40fddf482b24a01eaa4f0232d4ca928a9ee85d2c7deb34e71f8efd84be91d84067426dde71768ce763b0d84a55b2634	\\x00800003bce8cab6577c8f8aac352dffe3d5099e1778dbc29ef1e57109e40670e8edcc0881ce0fc8f3f1453519d2d4187d987d05e6e27847fcfac3eeb332867b30bbff50654a606787181297e8df2617c7a256bb816df8e397d82ff80fda4f6b21eec3d9ad84ad7e68692d223d638e4e0a170c073ae3cdd75e3cc704cb2790fab0023209010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xa90babebdf83c6e796622904758eadb33dd34f66b32ab56431ffb170d1fe9b5a34b060ddc7d22a29d285fef86668e64fd22e77820c0a4713c02e74507900e709	1601119161000000	1601723961000000	1664191161000000	1695727161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e025f293a728c11b2b6c7cdacf53bc2fc97b31ca67f8861c52ad012f370f3423a2d3f9f4e9b8e125234f5a1078b3374e4bbeeb31a761407900013efa5d9d579	\\x00800003b122f2afe790d01c57914b1f9e3b792ee0614178fad102ee8efb4bfbbe5fe5926c774c47d3f7378c60eb3a07f77e2bb16862c9b0b5305fe538c6ab8ec0232cfafc2b6bf10f3e67a6e469ae83f01bdc088dc0dad1fdb3f4f4a1771c263f935bc5a9d024aa69ca0365082831ed5e2a20bfe314d5aa9e700d7e649a0d7d7560c25f010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x03d64445f507be0a65f9c0d2ac4742211ee601b396052ebd39ea40572a1c4c3b77443ceb68796a7c99ef29570f04f0f4c6db567351fafe1170a9fefb69f0e204	1600514661000000	1601119461000000	1663586661000000	1695122661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9d4a4c390b9fc3087f64e60f39dd13655e6665c4e1b22f9d9a53a63ae2ff8fcda083eff6690664c07b7a1313551e10cdd5333cd409cfe3d39c737b2d9181e6f	\\x00800003d78530d2204cc2194d261b9d6019b98050b3ee79dc39e06193ec2988e48dfc594b32af938460aa4518fab773650143c314104f99c1e865289876e6a303df061c9614952e74e0957857894c2ab857e1cd2cd9da0eb56511935be0d9a9f8a0b874442addb7d769a86fe308232161c0e18cb6493c992244b100a44de4942219b34b010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x39fd23fbf540a2d4add7aad0ee83e42e62e4d1fb72adfba00927783e14777b476e96ec596adb04264bf9624e10759b69e8db96c23941188078d0cde07b31df0a	1599305661000000	1599910461000000	1662377661000000	1693913661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd26a60f3aba41cfef9a1ff163e53f04a9ef54c7907b77de61217c5f1a5bfbde9fa52fb6519c237d6ca37d039ca288b79bca8c18ff2bbe84ed26190315d0046cf	\\x00800003e7bfa53804be992d46c66d776ca2f29a0d099e044bc904a138be9351ef7aceadfc0e29b421869623d9f5b86bd74d78302add491362288c0d7accb467e3b1415061d6f365e5d92f1084da2ef762a93a4855f6f54a69db10080c5755efdca9b92c424a503054efc3a192b8f604d6e540fc50490f4ffaeda13395f2f7522ecfc1d3010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xb7a0b8f88af2bafd484a26c0e80fef1969bca3742aef5ec5c249721367f75e72803370010471248022881c4d2cfc9bec47375c5dd7f735089e8be0f937dda609	1598701161000000	1599305961000000	1661773161000000	1693309161000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d666c0d1858267e73ef6da6820fb287197b38134417154cf2449bb1c66e345e313eda1e5802fb1bbb535903e2f96838c3d4567ef3c78fa10293a94085107afc	\\x00800003b4cc5acc79a50dc4aa4244b299a5767941d5afe57a4572ba0bc119f8fde4cf3323af45d2e499bb3f96c278589303d3e80dafb7909cf562218f99314bcf9e77ec0c75197edacc4d05384d7a7ff1baceaeb20f8c3f5d1a32cc7ec27d6f80d78f50c7e787d8ddb0e391839f39c371ce7d930227ef42db384695a6fbba2e46c34c7f010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xbb70a964c042aa39f411556b1472bf80ca90184a9fd69b2fdb6ad696dbce70879293d1a2f6c9cff0fdf85f904a4b0f89399d044405a52f6d373e5dfcaf14800f	1599910161000000	1600514961000000	1662982161000000	1694518161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7f2b952349e4215050c6e5d7f7c3a83e47c3d0dcbcf6e92279f9892a8a30d579895cd793d5210bd68e5bcac7f4504ac43a7b8493a019de74f2d67a10974433cb	\\x00800003ad21eb122527de1f9957594c840b479599d3dac13b40889ec9c46aafc6933adc66038cff78d0a8fe6aaba97750c912ae31783547fb386ec1961e2bed08e7562481cd8c8e3bb80d65fff271f3ed067920c1c17e03b947318d37c7dc2cebb42a198b3c8b803a7ea86e9b4f4d281e558b80d71102dfb1049fa3b53634ea46138a5b010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x4e145e4d6596216d17f481e48543f92c5962491d66c78fc2c91cd9c035a7e5acaed0442d166c9681b1bcf6469f2c9a093634f48348e7037addf5a91114e0f707	1601119161000000	1601723961000000	1664191161000000	1695727161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6bd51d8493f1e7ff3702f44ad3545308375955be177417166634079132ebf46ff406be4cfcb2f7099b76832e61b45bd753c8f5525c711b4f08f9a3de1a738b8e	\\x00800003cd0e2fe8b1f26c3a461138d60f26abaf233343780a7b94730f063f9e618006a99ea184b99c91485f2f3f75161e1ec6c156e25d9422f1967ca758cef9873546102b41ec4040f8f514f7ec0c607618f37a0631f941fbc558fad0109a592e2696be6fbf1a1cb64ba159ac03e6ef39191fefe1c8317508c2d9997bcdf7a6989fdb11010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x00a42a63fa9cbd67e160788a240352698c4d32b683ab0514389277187cda6dbec5cbba55429e60031027c4da41bd5953466fea2430857e0cf3edd84aabeb2e05	1600514661000000	1601119461000000	1663586661000000	1695122661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf42a51d8dd9912fba994d9f2caf271f57a5b6b91d07bee206e49c0f464069b78eba55d8b8d7d8f7be94a28bdb0ad7218455e7625a4dd2b95a69fca498758e1ba	\\x00800003c59cece5d312102ce1842b56ae25a52c4d416db5d539bf71387a386831d61561b1b6af13a90505f9e01f8051900ff394a281242c2822116be995ba94ddd1b395e40e5d16ada39449ca8f961afb0f248722885627b30a526e4ed587256d0c0c557d5d7c3a4677c422cfc5235ebde7daf99e9c8a32904388380901073437ed41e7010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x6f67bea2f86a99c999de750cdb9496679763dac3c59da18c1bddabfad7f0474b62bc759f7a6b5c328728b968eccb1e6b9084c73868e8b0660bf32201f052dc07	1599305661000000	1599910461000000	1662377661000000	1693913661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b468e9a59d54f59c4f77077fa1c46298dbbe8670b5b5c123fb363db01317a0350760769c36dedc61c2ef65f86288e837c725b3f9ed18990e0288db11bbd81ed	\\x008000039f14a1ad49e9443078bca977e3ac3b4b7f40272af527e50eabf92d5d30656db5a96ba77d5263907c3a08949ccd446ffe22b31452d3425e9978b4bc51bfe5d8cfa36524f59419e289227c1e96e6579eb420e63d9a4850c178c1043d173f04e86408a7d203ccc447cb9dfe0da820882630bce818f9d87014d6052f47dbdca8b465010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x1b3e89337bf583af08fd46c0bbcc14a154c83eb9a46d72419a278e76a44eb692bc68e905a737eb9cef04192ab2c671e172046b5669fab7d4eea33d14bbcb6f0a	1598701161000000	1599305961000000	1661773161000000	1693309161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x116f8c16ace1f91cb6001916dfe11a8c52f38561363a885b30c27deca1d3010ef460f8dd17e5056c5739f4b68899e968996a0a347fabf3bdfb31bbda786761db	\\x00800003a40e44710eb817c8632d04a1011f2eb6b042e7e79d801d8eaa1030fa2cb522f1aac8922f491482702f93291e0afacaf3d2bcdf1adad3e2d54f964b5ad08de831f3f724e4d950710fba55e03109e2a2208c9250933bf700f5fb79a62640b149672e9f2af2f2524f78329e4f567a4379f7f2c780fc441e42f6c582240e14419a3d010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x535ee3183a58bca4d619cf7da045e0437755a11e89e04c95a2849b540259944b3332a2e0cbfa88ff22b87dcba68c8404d7e679307a942661345c5b9e9249310f	1599910161000000	1600514961000000	1662982161000000	1694518161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe3f7a4b4113de1e961b5a1cb3a9d3fc1b7f4e3bc7f507eaa21a832f60dc32f8ef358ef9e3391c73bbc0fd51c5c84a6bd5014869b031aa1f1d4975296860259b6	\\x00800003af8d64937c67862a54542690d0a48e4cc1e2c42058e1f950f480a653623b5c6ca36c5d82a5d59717038ba2603c7d8c666a7d67280ccc4caf5c05951610519647c65b4dd6af7206233088de5ed393ced92d5a42491d6e16a06265998857be26d58d280f1014d46b1e2f1b5a60880cf7f97f90c14edfd64dbf9ebda70f9b09709d010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x316d4d1a021d2f28e57cc139e4b3e9c71a9866bd056acb663af5be7eb940810e8cc8bb70cfc8086c7882df542500407fe6d64c1985fb336052f7668f528bc309	1601119161000000	1601723961000000	1664191161000000	1695727161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f537eaf91a4056ae2927aa1bfcc0b66a949c01ef3ba3418abde9bbbbbbb4283db98dda32a28a41f31a239754b6bc5d2bcd8a57ebd7c666f241cca0bbae583ea	\\x00800003b1400d6e3bdede351585b23be3a1f124f61cd714ef5da4672501776afa6f1219fe3b501dd5126d7c5c8e74642ef89610eda104a450aa62b389f8f2b06b090c5eb6f94c8e852329edc81fad7f631beecab08bac14fee18a7d9583a20f3e24fac279b67af35895935041685fae80bb13b6c9eac938bfdea545b1abfc940955ef01010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x5bb7dc3db74e9783099eae16df8885d5bc30022f0aad6cb8483325c26d4fb05cd2864110ce66f69650281eed69c199b731043d9faaaa80d8d2eefbc7c98e1e05	1600514661000000	1601119461000000	1663586661000000	1695122661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7e58726bee0066edfa1a63f6c76594a5bddde68c07b4b5d22413c311420acfeb9a2c98081783e56cb8c998c985c57a6961a87e2494465117e3d24375778afb7d	\\x00800003e982aabb5f75abc6ea07d672ecdfb9f3801e0b8c21a4c0891ab1fb403f19aa0964b016272ad5ff9ddc2b617faa2004abb4d1293f7e785d27aad543ebeb3291bf717aaf9855ec393f60731ae5c90ffa6efc72b8126d2fe24d61034daf4fff6f40902fd66dccd07c0b91683ccaa9ec5b236097dae7b32c88acc601f2371b099dd7010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x0f8fa8d220cc4d27d81c372f271565e560b709432fe4e26162dbe0443828157fe4f195aa86943f297ff1f22c4f21c791c36bf786cfbffb731dcf5e97748d3a0e	1599305661000000	1599910461000000	1662377661000000	1693913661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd1226f28ec4932672f53bc81acc1fa43897720591dc42b1b060629491b7182d54f8f63afc39c8ec4adb8e89ef32a497e0537d5e166b5ca9df13bfd42fd3e9bdf	\\x00800003c9f613f92e6cfeb2d08fd542af2b8efd32fa9ea4f46c9f0ec37efaf59eb76489741661c4be582f6370f60ea2e21470fe6126b3d901ee8a6d37f84d10f7f3de62148e7f074cdbe895ed7ff8ad8cc9a6adb0f806225f3e824e6bfd9036589d23e120e8a7f5ffd04ee6839d0e4fccdd363195fd29bd22d63214898a423a9f4ac7e5010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x2c3b263e6b92cba263f3ea1a52835e0f6d96b14072c9fb3190b904267306fd3f7291ebe9a06e0e3a2103aabdf5482024eb8d45c087a5bd5fbb1cf3c02f531d02	1598701161000000	1599305961000000	1661773161000000	1693309161000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb9b00efc2fcf9adcee34a17fbc4c871276cf2a1f74de2c204841717ae8bc8ac9b0cf0478b5316479c7eed92b06f2d4c2a8cef3660c9639afcea1db204d543f14	\\x00800003d3879b711f1e8fef547b2dedc3582ac143bd030fc210e7023c660bb8b0a9430362243f0b9bd72045a7848973c776611df0bf56693a72dbb1ea770adbd5bdb98e51468f0b197bf5fb3c306316438c5723fcfc8363bc491251e66b506ade3820068143b8120c2c333603b9bf1bbae5dabd42e2b8a94bb19e6ed5ccff3237cf63bb010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xe0cd79e8f4d82fa4b893edc931409ab65e58a44e5f7e9ea0ade5325bc4959e1ab02504e924f060cd94452bc214f903fd18a308e6c4b388ba40d5fbd3ad0b9205	1599910161000000	1600514961000000	1662982161000000	1694518161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x52135e2805160ca6157211b3c35391085595382f0133af98e2b44af1f4235fe06744268e8212424dd0810f88173873b1ee7d7763d618445790b7ee6b59f1c1d0	\\x00800003b8b8a6a6c1a80b21821b0c4ca53f6de1bdbecd23669a69fbfe3632a6c56f50bd9adbb293e3a1c9d9d655377cded7b6088bdfe6dd7431fbe37dc2b96b7c88753af881eb5a2c62b863011fddfcd9f0d94d8214b95554f13bf841577947b80eabad5ec09bb16a1b181ec7aa3ea501126784c2a84a6658554d890139050862b0614f010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x8760032191295812eba4ab557cfc0628d02a85bf1100592d7cb0f51aceee66d190c0ca4fc2583eb847b8d72d14a0eab16765e800f0efc1eea7dc9437405fbc03	1601119161000000	1601723961000000	1664191161000000	1695727161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc2a1cb7562e7660bb8eb6fcaccbdfa7bd50e674f6ab9e93e452b15fc69079a6d710374eb23cf3bedc9309cb9428b049e7fb011251ea0d8acbf091577c7eab9f2	\\x00800003b1512e00110f29933613bbdd58b7319c3d6781f724b57591a8bab0f9fe5997db0c632fe6a98177a349df00f51c6b01d23362af50f9fdce82284e01489d77744722ca0aacc26b0f4ad4929167da1a203fcd7a4db2b82a48f08e1109c58fd053945b34a40033b48431049b8f775473a8ae0093c2dd36dee36df9dfb46b1414c837010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x60a63dc37cef5fd0c50c354d5c02bb442f23ec158b1cac2d70d3ced7e6fd40aefcaf21c73283e9d427d816e0706b52cffad82094e7cf155e3b4325ef9626560d	1600514661000000	1601119461000000	1663586661000000	1695122661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x45fb45c9008e4f2a68736633d2d605af6cd924215950a52ead33d669620b114a859e6e86aa4f1838c173d3bf42b276a1424061ace85804716baf5a0d3a7b72e8	\\x00800003f47bf0a755693b53abcec7de344c143a57f3c3d3474fcb47fed91665d153ff93adaafb671231c87e5de41667925d48e938787e3e4a771f142b427a992d6a41298f272030173db7249b1b156aff88775d19d3b2e28034f53d6d675f35b21f646e410f0123b981b87e12e1cba54ff0e16584e909f4b8a88c152e1e253af608a0cb010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x52fa27dd5305009574634fbde8974825963ed8e7221a7fb069f10211a3f1a6432bfdd66584b8aab9c9e016d970707b4c93415cf1def5f2dd6c2bfba90d38e708	1599305661000000	1599910461000000	1662377661000000	1693913661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd9b1658aa22170a31481fe95e0510fec987c8395597d011641837e8da25f4bf6d7723916b48c853f583cc20401ca9d806ce9f11542e808337ebaf5fcef31666f	\\x00800003bcad01f5944cf9119894f216d3368bb48acb78aeed3d6ddd141f7fd318cffb9300175a0e73ac2cfe4cbf6ff8aa4c4ca9ae723c74e5807a664042f48c6266d9f15b4547d109196cb85e7ab258fb1f8cfbd5c0e8af66d2e0a96f30216fb79e272e3e9db8dccf22d7a63b2bd2e8688353ef5f050c34baad659fd878f3c5be159c73010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xa3b753aba03b9da5b258d13606a958bdcdf27698f46efcb449cdfa6e2257a9323bb76763582fce60acbb4ab623fc786952d5c210a45555cc6a33a380fd4d8402	1598701161000000	1599305961000000	1661773161000000	1693309161000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbd2eb128d9751bddb90e755ff1f0db354ba6463165b12490d389a7e20e7f7643163177293d28e1195e3be0ef78763e4aa961e0b3ebc265e789c76e7b64db5c48	\\x00800003b2f6bbc7cf80722ec5a2cb05a3a46c64dfd61f5a2c7134e1cce085fe5afcbf6b2863cd6fc7471959ce809b72e1228f11817eada885c988ce5dcadcc761bcce11ea3b1a1597c86a84ecf10722633b6cf7a12e5213ebf15e62401ddd7487f84c64507587d910657b3d7fef86e509191a5dc0cbf98969f178586d902a965e57e37b010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x726f9888a5dc8c62b4cb9d6022ac316b9c84757e13d74bf2764c8081312e9976d8346c9de7a163192fa902b32e316c9f620e096b4382cd460ba4d0d073ae0300	1599910161000000	1600514961000000	1662982161000000	1694518161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xac64b5220413f56d7f0f24ce9931691c7207fb45a9691716fb0917df4f7b976bd0ce8a4ae3c3b74983e1d639c8564f409abc35e3a0735ea188e8b5d861f45c24	\\x008000039a1a53085fb7869d8c71da74cf8baf0bec45f13353133366fcd2b54668eacfd0fece76d374c24de11b2996fdf7613d448c997331275fd75bd8903bd3d1b77e90323fceba95af0ac3b8674d7a121af3fd4673cf32febf4f73fd66d7617941e186572f75e2471d40b262d7bdc1bb5b037e5178bfd794db9a08f64f843dd948243b010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x236c1d804b169f6f5b39167670a88909007af18e62de6db5ad48b3121cdca4245d55df84e2ac0e5bbf56a8bb48da56270ea38c1cb47f2c5d39826dea97dd6004	1601119161000000	1601723961000000	1664191161000000	1695727161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7e26b1fcbe9f268206eb35ed491cb6f54472369174e702241e8016124ee48fee86e46a4283657ff4a1b9ee80a09d2c0de34aa374908e91e4e11614c395ed69c9	\\x00800003c750b7cd6042f87b01c76e93fad6597481d88297bc2ac3c07a49c3e385328c5fb9271567dc52da446864cb00ef7c1896e747e0e12e80dff0de15abd15e5facc1bde6caf97f4f28cc231e757d1f61ba27980cab6a34d2e62973f89e22b95809b0efb3dccd579feb6acc2fec3445457a27be9bbb936d95c2e27276961fcb59aaa1010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x24766ccc9ec0b0bc5f4bbe44489e9160ef370f1760370cc5abcd6f94bb61ed983cd1466c6431cb800c199faedbc5fabec86ced3ed1ddb2486b4d619be0fa6000	1600514661000000	1601119461000000	1663586661000000	1695122661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0d218fe7bd93f741663d5a204981f7722677d86023b452cd565b26072254b47bc73f2f3b780871348f6ec4f14fa5c7a568b0ba9f39272040afc64ae080882236	\\x00800003c8961c47f475782102e81e1c4e1689dfc39ccbed2e3bc36f94e4148b51135b5a7802e3feefbf31fd3bd5e0f0111ff94780b37f30801e56543a44645194e6c049c15190744de13d30ecc951f69b4b0ebdbd0400261342dd10106c73cc84a736d03cf0a52fd5df01fc8a675f7af6057b7d9bed24a05e1392ee369788bd244b8405010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x66a834965b868c450b42421140dbd578d2fc60b17292b6a769cb13e989565c7c494ca952cd5660df136b2c36d79872780bb8d7b5b6a269ef88533870fc625405	1599305661000000	1599910461000000	1662377661000000	1693913661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x008000039e31df7991b298113062b285e0d584be6621c3344b6336c3c9b68b4c92c96a026a70e552f5e6a4a0fc821229a4cd34198fd7e50f97c0484ded8c00893e623244425b9d4174f7f20ba73df60307e3f162b5055fb85cbe8d44c3e25e861ff1dcfcfd4d390c062e9c6133eaa0d5667ba152d36e64da8d050c7e37b6a7d16e7b336b010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xa142db94658be2461dde0e7b0c8d2d37c36bbf25926158a54f03fa55996c25288f6059bdee485f4cad6221f8b05bb52052eae39ff1b11d0b593e76a45083120a	1598701161000000	1599305961000000	1661773161000000	1693309161000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdf30730e1a20318c207a00fd62386fe12f8c3c0f0f9fa9df9d3ff251c6a9acab6456c054982c78c785e06e80a9198ce55c6c61b9263d30910e325db1ddfa2bd8	\\x00800003b453e0a3fb508c396ea269bef33f0e3d5b61a1eb69ec618b808d2f74edc132219654d0b2ed48fef9f098b3848e4774b2a4f5b303ffbc5aa08d3b6040c90ca3b8f6321f96ae5bb26861a69d6c07911c5b06428d65036258d31187e3ba8ffcf008867e8286474075a35ec9deef58a40fdb107dc68795ee2679b27a2076397567a7010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x736d975045da5f1575972d06cf050e247ca7f0b072e2b75622386205abdc64b6f59e57c95add4ff30c04982cdcd69896ec240b3bf16d4d95d126c030ba08a60e	1599910161000000	1600514961000000	1662982161000000	1694518161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x477ecb07d4f8e806bd4a0862b6cc3f5da82280bb85945e211d3b808da89183b76e46935e13cd9e8b0152163d072fbd9ad61c75ad77db108a2f0f5c4b61c17622	\\x00800003cb973885022ef1a1a4c2eece9984309677dc46b039ae798a86f3e673686d76170014f37eec0a1fd324a6f947729dc7c581f063f9caeb87f4d7a7eace45527f67d31a789054ac60402a50385d1bfd6c708ee08dfda75850da6ec7baef1c14fd105dcfaabe1013317c3d4593ae72bd1a2fe85856554a6f84ce8015f38cb3708c51010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x546eed7fa5b2fc1f36073744503398052163d8e99c0bbc25b15f2b30e648019b28ce07e29b288f149c80e0f779085465fef61c6f9368475a0c7ba5de984e6405	1601119161000000	1601723961000000	1664191161000000	1695727161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x281d36b17b08c25b8133695ec09b73ba05652625344ea7469e60daae8eb30dbc1cd29b88cad209d34ee200dcf501d736a43c43a5180addfa927623cf64bdcc03	\\x00800003cd0415d92830d850e6ec2974b50890d435ffab26868fcd4f27e68bfb89c1c3e5f986b2baae190837f125b56071fd1ddb8612010c6c421cf367c562c43be080781747e3a9f25a5cd99cd5f04e034aa559e2a6c3f3142a94ce619d5b93398e5e563abada0d9e39a7a1da88ac682aaefbb793ff74326b63e29f673f79aa27e840ab010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x490d181b466b410911115b42d0ae45af29bb0f0a00218e2b38f91b21474a7d53ae329cc1bd9ac9823c7cf3398600e9a20b9502dddf9ad0424f7cc6c0bc92c807	1600514661000000	1601119461000000	1663586661000000	1695122661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x00800003d95d8369ba6b89e792dcdc573f044c3cdcf6666066c49de3ed46a90f290ea6a151cd387ac00e43c0e8ca87438308c4f5dfdf4cce6d27a7fb2edc89684f54ec5b8421a583c258c21218588efa5eea9dc7a6338782d5c2096232982cd4f8549aff960dcf0f0a67efe3af71d5941e10ba469a8ffab41dfaa3b11eed1aed6343618f010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x4eed3da09b79f7e18cdb22ab799e6f9ff10421c1525599d14eb31e904bfa9d129e2ccdc0b9beb8e04ace3250419d1c7dd8d18b0ee44e830fddb742e03427bb07	1599305661000000	1599910461000000	1662377661000000	1693913661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x00800003c867ed57e08aa1abaa7c8936e0a34bbf5131dfc4d9ee2b558573538b9005a090babe018a6fc88bf1b96c32cbafac68f6afda379e8c6966be260b799b8a9067cb8b82e604629bad5d94989f204dceda09dbc5068f09b1c95c3103e3a5db66ff5ac2a3e7be9e799b16288c6db0ea0d81e6ee05f61fb4498959f2b2596ad7766a61010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xe8ef6f39d221be9f16b9bbbf2abe89d7f5bf53176c6dce9d6134318fe7a93e54c5d79027517a2cc937cb83e9d3437abb6099677996bc8e9c7d613abc368a4d02	1598701161000000	1599305961000000	1661773161000000	1693309161000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x146f6622ca54df31486923db1fc18c2bdafac05337d0b9f4c827011cb7d3852efe19818198f013184b4304337fe29a645408042d3f8796766dcdf38847739315	\\x00800003a00558dafdd6dccf70bcb2211dc51326f78e45eb5c0b3f3ca57deb72caa9690ace49c1dc823b48920675f476a5dbcb58ef4dc126772a90cd9ef5aca6da2f34a69a9ade272e021b2949648979aef63fd8d99260ebc86f3747e1951945d0905be7753241d5ea16f8c81c9daf584ff2fb0810edf9ebef66bd26957dc88ab47d4fcf010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x3fea0354ad152d3c5a4f94d8fe86e7f99edaa1c7ab1ca7a2307bca589a110536161f02b1520c88c54c203b2009dc63b8320b0f839f59a4253bd0acec3874bc04	1599910161000000	1600514961000000	1662982161000000	1694518161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x04a7682e9e458675ce2d88683d48443fabc10da1a2d5a740f2e7f8a0ff3b7e8984a09f395cc995900784c686b24cd253a700660fd5b6a6f433ce5caac4aa747d	\\x00800003ba66a3ea3f67d2bd9378a8c3e5a5482a1106f7e21935aca9568873de398d408777dab8c2c6af5c299693a7678cda7b3cc2bf254fb2a52667cbd957660eda8b3f3b8c234615519d7448f0ff9684de2bb48a1eee87fb3f6681e774bb75a0dbec7df1fa03e536ab6f69e09730681ed34a3a483677279836d9cd902a3dd24d23d403010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xe80ceec3f5c9ca67129ea03dafbb4cdffd66b90965608746f55914b30642cc1ea61142d6e5feba9495cb53a006ff4c0b6f9dc384ab12425ac3a6a670fbc2c20d	1601119161000000	1601723961000000	1664191161000000	1695727161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7f26ed2e49ef40ed242712483767510d7036529a0a3b4234a69a5419affb6a7068c24d0e59f12bc5156564d0b2a384aa89d318dc0baec09711ad784bad0fc71e	\\x008000039e09b038c82f806c785337ee46dedfd1f22ca2baf63b870af627be71c5bc0a99319e50d55a154f7e7c5ae8f31b426418c881568b273ea49f856c59a5fc55931e859d664a4f59773674a4752fed9771fefa104993ebd1e65843142acd71b735ea09c599aa40cea00403b3d9b2dbadb704eb08c6c2881139345baef402424938f5010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x6a9493f11a9466a11bf9884fc15970a04fe53efd6aff7b28b113815355559deb1b30c778e1c469ebd1b5e904fa8fc0e1b6a9a06807c80260d417c2e6148af109	1600514661000000	1601119461000000	1663586661000000	1695122661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcc9f51d094c0d1b607082da14884f2db31b1f7c9d716355a395efb8c87c58d85a076bc81ea763f19e2ba0724c1ae60567dee1ec4e9197219a20c2ecba9092aa8	\\x00800003a8a2c6e92fece02360bea709d272b0c1f6a700bcbc00c5f1a9ef32fade8fdb14b0c6fe107cb7487c7ea191d27748cc7f562419a108d1d9b02bcaab549da6185514b6a2dcc24ecd323a42cd4511a1cd0e16f3713c2be24a5e1a772306c7a9ce8ae40f4453a4059d46c4d306406d56bf40e7b9dec66a7456a0c36f01ba0365386f010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x7c655d836d3600a21d8db09285ef3136b816d76a6454c90f203c3ca312b9a4fedf6c5d3530a9ad7b82ace7d8592916855c5d6eaf11fb37bfe7fb0817c4c6460c	1599305661000000	1599910461000000	1662377661000000	1693913661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8dd395b5ecbd7717d9f8b8244b0d23b9aaa2aa3d785f2c88dbf910b42774d63f907e4c0d2c8c09ef56bc1a12556654c82c497297ce20319826b4b9f1f2d31e04	\\x00800003da4877e42d299859db14fb4430ae0498d548515cc72583ee00e7e9b24d707934d6e98ef1c8b2fecd120db44c68b751a5725ba1a51c94f9a84aad0b4be521d3dd4ca0b41417f59a645065beff8b74520d1cb5f2a47036758b830b30310fede1d450796e33c2900c09306441716c9d95fd43900424039048ef985fb722394f44d9010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x609780bb4c5063212d3eb92b9a6ca38c5b56e17c7562dc5b6b0c32c49b1e610af3590d943d1a835046ef54378416f3675b278eb4ca741999602536340dc41c02	1598701161000000	1599305961000000	1661773161000000	1693309161000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6520a33204d25810bededec09e1e2d904fa239b5c20f8763a1d7032fc9e752f99b229d6721f73985d186cad41b2c5f1db50ac46c100a483b3129e55b2c90bae1	\\x01000003cdbaf104005a4344e9d9b2c355a64ae13e8f1c077edc75ff0594b6abf64c790db3c70268b4e4b359b5805e0c20ed60a593b96ab7c886c80eed99126a9fb17d28a53781a2c327a1d8e0e58e9f07c6683ea88885d0b24f7fa52199fb03eb3002c704f09aa48d5cbc01943ee1e9b9a7dd41fd52259476b6deb3299421021b5c1b608229bb75028f167fcd5ee127c537078fcd4be50762bad489d62afa204c38803a59ff6bc7e4415519410746c5944ddd14abc4e4d2c0146c27c5ac6dc34cd2cc348174892cc3c162e1b2d5b54aa906c765193f19275697afefd30b09620cb496e13e2503244a77ef9aae46b1c5c43bf964f5a316b19a5e8a8cccbc5e2e7cd2a2e7010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x9c6941ee63803ce24af2ce2f1029f50cb35fa9153cd29a083c21cf7cc0359dd3ddc0ea53ea4ab405af5518342d81b61fbab2f762167e74e8083f1bc780d5730e	1598701161000000	1599305961000000	1661773161000000	1693309161000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc2b311db7ce2db2536422e284757e62c4b724f809bb27f112c3254d6043e0aac9cf76e420e3754b06325d48d0f85e45d1c25ff71e7b61bf872881b9b1632ffef	\\x00800003c30d4a7893ec28bf567739228ad912f0641b7b4be274bb1ab010ba855610e305e48481f463c931a8dffab2168eeeb951d64ac15a8d888fbb055a1f69b3d38b5ebab52e1203ad7dce70acfdd431b66f1be295eee074a10f92e18c27af9d15d8c6921bdc72a0e146de98f51f8a47293541e952c4271c7f1edbb816abf78b9dd1a3010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x3e6e8617537459a37f970e3a540187f948ae99805fc3cf8a09cb6dae4e69e519358f2eeafb1f77502ec727e383d4ecbd1a30cae3ae36f7ae903151c88556bd0b	1601723661000000	1602328461000000	1664795661000000	1696331661000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1efe10f07643f71c0d247bcb4116fd9d13cad4a4e6238d3e45123c5bb5834847ada31fedab95e84be36d8a5534a6ab85fa5fbf465451c5efddd0576a53bb851	\\x00800003ac314cae3e4b4c448242ea775058c02578f65182b501b524a170831766f15a9fde7e8d5d71f5da8efb38bf43b4901bf5ecb851a991e7bb75aa32863d496a4042fa20d890a7872b75cae6cae0bc769f90024f3afdf0395beccb40f4dbfe89eadf233e22d5879e475676f5e8b15844e4163fb7097a33abcc40333769bc6ae1cdeb010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x8907755fd50df212ed744bcfb2fce359d51f2ef7c19aa401921d0b3575e606a2b3982874625c597a6eb03dda6ba96287ab7da61dd3176d50d16cae5cd5a53208	1601723661000000	1602328461000000	1664795661000000	1696331661000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa8b9a7ff96ba29e985a0e9a13458174aeeaeb37388106bf9fec16ebddb5c5d6b70c83e32fa0c32bae7127914c8842279e9857fcfe07faccdfe7287bede441133	\\x00800003c2b07b8b0b0e9a6032606ca9579c401848fee896f23706e5efb5f4f0fcc24cef4cee2b12f93ee59428ad69259de609443b684c9f4c78e5e310141079db9a2eef1a527689d3600510297691e0eb9721fbe3be7d27f6258db9089024faf3fa064ee083c1e67ee6b4778a8c486395384592b3965df3a653167e3a0a21d3b456a1ed010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xb7c1c4226fb29bba80449b1fabc8a1d71dcd7d0665c127a839c56e854d7c7f9bd9d883e3ad18128d314a355a4ed353d427e7020a5e0ccdbe879401eaf0c2bf05	1601723661000000	1602328461000000	1664795661000000	1696331661000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdc3dc11c84eec3cb8fa410f4d8511a9153879e05f26403e6f1da18917788991bceaea8fd872e968bfc25c283807464fe4ebeb74f3d0ae61b736e4a822b9310ff	\\x00800003b89efdc49830d780d674d71429864261350e6f28682f864c2335c4a52966a1b87343a8a7a254678253e69b306a1691345787a3d5d8b2e266dbe5cf0b4c8625ef0a2f5e9ddf41b11e3a6770d8ce5adceffd3c37b904dd07f491009ae8ba4868d96c9da3d8addbb66fc5bfe1ed6e97aa17e5258a93b62c1a546cfbb410a5b2d845010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x8000eaf0e9b49e17cbe6150c03be1f12e7b6005f0d1010146e98ef885cbd8fcc1e4a5f47612346c20405b6ef96d8db2961b601171f7a20a1d130ae2affa51c09	1601723661000000	1602328461000000	1664795661000000	1696331661000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2ec63c81281f562bfe05edc644b6d25eb0fbc56e52a0cc027de5bdf1c63bab4433e4aeb3c8554406a364c4d3e520071122a04053717aac25f1a974152079def8	\\x00800003c685fbe7a917e296c33ec4a68f063d58ae86b7cda35bbfc32742460bf07f47e2bde2da6b1b5902fc21b1d0a54a413abfc8f0d328682c91c6d3f6787edee6a210cca93b3d49e49a0e1c0bb1fe60bda2b85a8314d05dda5f8ff7b4d09174a6d9515931c993eb3e45e19e362de7c4d68b4594b4f99f23f6c38600054323fbbd1b77010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x10853ab75212f34139906481f5a63dfd8fd7e39e30202806dd3035461b7abaae0068c28558ac40331835b26950340475563cbd4874dfb90bb6e313026d7a4906	1601723661000000	1602328461000000	1664795661000000	1696331661000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd0a5cded497f1a4cbbfc4c1566b8cbb549d74bc85d30dbbc9043ee13294b49703d86c41b14ccf1a2a2bd1439711cb9651ce6482343c6b3ee29f234b2c7883960	\\x00800003c485eba7c1d6ce32be5d93cea45f42ec9e72742b4ed13693a05630868df0d9ffe72daac3869e6e684ad160bf6929e19783c606fc82e8c37aa2a4887e3edd3831d2339579b7b525d45f5ff0ceb336633683e4d2d872ebe251c0b60307bcdda1d2a27c5d484815e7f69ad51cc6a8f2140f4399dee43e23ed079b82d1af4c9d7e17010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x2c9c45b262b08ff68183b792fdc6f36250b070048f262d0459774d8522b14e282c769e6f9345715ed88282071b390d2e1b1ec3c6d48a2c030618a8ebfc664b09	1601723661000000	1602328461000000	1664795661000000	1696331661000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x84af7412b772af01812915347c560befb544e00e45f269e11ff1512a3efb2e924c65cf2c32ccddcbbf5efce12c7f846d7063036c6e089aad34f629b5ed70c34e	\\x00800003d6487f17bcdec4f10f06da81466d1e844f58f1f8cc614ff8b875461fefd8fa04d1c11f296405238ad2e6c1ab1f68df4cbcf857d2f24187f129d258b35339ccb41e7c89488640413b0af58db37874f7efc40f9154187a8c812dcfa095f21d85b75bd6837952d31162b84783d3e2f2dccd3a44ab979129f4952e8bf12b83c4bebd010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xd97cf8e915400127bb5ec8ca0c4797b4b1e3275e47a1bd20781b68405e655c353c8d6fdaf5f592020ca61f1ad1ba402ebf8c96a62afd54092a215a145eb1db0c	1601723661000000	1602328461000000	1664795661000000	1696331661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x36d29db266c79a4a9caf6e3aee2d1c0b9782526c87d1048644d8db05057b25c7c17acd3d4eb3524f9f00a730438e84346f2d703938de90ea9159aac44dde09d7	\\x00800003a69477592710eca8f4b8b70a8dda9123472681afb5072f70f15d9c857ba69dbfb38adc7e2cb98b65a2c6610ce56c8810419e305b6d73655915cf479298f6a880a68c9beafa2dc38987ce61b8ff3347f631423472027c67d6b10024075334b080ef592c5532734ea76878534f4a0b635ac4bf1f888e6c8b6e73d8397d259f2a25010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xd564c9b1d1611772c2b766c8d74f7d43657139e822b6dfda3d7eb203e39dadffea28706fd666258c4780d6699b953f1b71ee880ab14e1790327e16cbee95db03	1601723661000000	1602328461000000	1664795661000000	1696331661000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\x01000003ecc4b0f981ae4263eba19033279f1a4c68a24ee3828b563268b6dd1f3a2cabd96ced9c5d9a56eccd7e3d72539d3f6053c3a8f8046343f069da748dfaa513c3325fabe2e81e8ded7de409009513430e9b6f08265e0884241835766791254d2c9bcd97d0e8c45acef902eed5f06247ed03ecc7ba0f380cd7e66f0db33dfd8f028d5d885b2592328a340c2b403e870fb234510272d6e573515403d254f273870ed8f400f4b68bcd705b3b5cdb7562d807dc32e454dc6b11f91c91b6acfa670c4b92b93452b12695e3587aa4f918322e1ea68c9f080d66642e09f6badd05fbba3cbc103c6944cb6b925bcfde196ea1878e37108b5539760e9f8a500309ce4c5c3295010001	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x2b234e30b1bf2c171ef0dc3151be6ab21593678218217639e69abf46594a0893807b7c0cba4c36eb7db229c32d5b7a7b06c8981ae41653c6d61ed2e99bd5db06	1599305661000000	1599910461000000	1662377661000000	1693913661000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	1	\\xd2813ad28e551917d1414e6d63a0535c119e0c88fcc9fb4ea5520349821927edf011e6f74aa27e71ad932dea9597b8526535aca66ef2269224e212275c26c4b7	\\x655cea35fab5eddb0226309ddc4dc7113947b7a16ac2494cf9f7a0c170a014079da705351831aef69867f95ca54bacc388e59929d3f355e426b7dd53f4188011	1598701176000000	1598702076000000	0	98000000	\\x501df4e363c6e61d814c6feff52f112343c3d15305aef608257384ba9a4371f6	\\xbbc521d564e1b5cc52677fa3894f858d3ca53f636d13c1a93a28d20e3f35515b	\\x8983581f0dc8d7cd8c6b36cbb1880fda54a8c4e575278007b15500edb4b57d1a16511e98d232c12c523610936bdacf3f9916385688cb4fb7282a0dad512d1903	\\xf04c1a56f0e1a9bda14f99dc8f82cf5aacb968f0e7469b3047bca606ba20f21d	\\x094d3df70100000020bfffee437f0000f31d44f18e550000c90d00d4437f00004a0d00d4437f0000300d00d4437f0000340d00d4437f0000600b00d4437f0000
\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	2	\\x1bc6f0800bfb077546574fc5901295bf613755a5c3d9ce7f3ae02867c3126cdbc48ea1890eb2e3fa5bc8977c9e6397e09e4428ff619a6a173d767ae1a884c127	\\x655cea35fab5eddb0226309ddc4dc7113947b7a16ac2494cf9f7a0c170a014079da705351831aef69867f95ca54bacc388e59929d3f355e426b7dd53f4188011	1599305983000000	1598702082000000	0	1000000	\\x08ec2f41cc18356ae1184d2f2fabc1ae512ad16400ab5d75bd332c0c9bb6be8c	\\xbbc521d564e1b5cc52677fa3894f858d3ca53f636d13c1a93a28d20e3f35515b	\\x99f6f86623d178c27044d064a8d40d4503d0f72a679797424e3fecb3a118a5d735687c1bdd2f663d129e975534ba80bc21433e1ceb9b13bfb10b51beaf0eed07	\\xf04c1a56f0e1a9bda14f99dc8f82cf5aacb968f0e7469b3047bca606ba20f21d	\\x094d3df701000000208f7fcd437f0000f31d44f18e550000c90d00ac437f00004a0d00ac437f0000300d00ac437f0000340d00ac437f0000600b00ac437f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x501df4e363c6e61d814c6feff52f112343c3d15305aef608257384ba9a4371f6	1	0	1598701176000000	1598701176000000	1598702076000000	1598702076000000	\\xbbc521d564e1b5cc52677fa3894f858d3ca53f636d13c1a93a28d20e3f35515b	\\xd2813ad28e551917d1414e6d63a0535c119e0c88fcc9fb4ea5520349821927edf011e6f74aa27e71ad932dea9597b8526535aca66ef2269224e212275c26c4b7	\\x655cea35fab5eddb0226309ddc4dc7113947b7a16ac2494cf9f7a0c170a014079da705351831aef69867f95ca54bacc388e59929d3f355e426b7dd53f4188011	\\xec03b6f337cd16b9b074c4cb8e3344c75ddfeaf04f4f5a6b13c92fc0c4cf7671c4d8181e5c432d52bd749e96b1b48fab21e313266d44c179a8b5cb0e0190b30a	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"SGC4197G6S8NB3DX5D1NBRC8PG7VT2H6SYV7M1877B0H1Y29ZDXR4S604ETQ3Y488PEG7QWQ621VFWQJCSA2PPV9VHYDFA32VHPQBTG"}	f	f
2	\\x08ec2f41cc18356ae1184d2f2fabc1ae512ad16400ab5d75bd332c0c9bb6be8c	0	2000000	1598701182000000	1599305983000000	1598702082000000	1598702082000000	\\xbbc521d564e1b5cc52677fa3894f858d3ca53f636d13c1a93a28d20e3f35515b	\\x1bc6f0800bfb077546574fc5901295bf613755a5c3d9ce7f3ae02867c3126cdbc48ea1890eb2e3fa5bc8977c9e6397e09e4428ff619a6a173d767ae1a884c127	\\x655cea35fab5eddb0226309ddc4dc7113947b7a16ac2494cf9f7a0c170a014079da705351831aef69867f95ca54bacc388e59929d3f355e426b7dd53f4188011	\\x9b50ee5f6fb28a226c28cd706fb101b9786cc88097632c9b3a90210b95251b245f7f8559b178cc4c22758ecba6e07a69f8213d1c67b078640b48f247ff82550c	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"SGC4197G6S8NB3DX5D1NBRC8PG7VT2H6SYV7M1877B0H1Y29ZDXR4S604ETQ3Y488PEG7QWQ621VFWQJCSA2PPV9VHYDFA32VHPQBTG"}	f	f
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
1	contenttypes	0001_initial	2020-08-29 13:39:25.456281+02
2	auth	0001_initial	2020-08-29 13:39:25.481451+02
3	app	0001_initial	2020-08-29 13:39:25.540764+02
4	contenttypes	0002_remove_content_type_name	2020-08-29 13:39:25.56954+02
5	auth	0002_alter_permission_name_max_length	2020-08-29 13:39:25.576813+02
6	auth	0003_alter_user_email_max_length	2020-08-29 13:39:25.583445+02
7	auth	0004_alter_user_username_opts	2020-08-29 13:39:25.590292+02
8	auth	0005_alter_user_last_login_null	2020-08-29 13:39:25.596586+02
9	auth	0006_require_contenttypes_0002	2020-08-29 13:39:25.598253+02
10	auth	0007_alter_validators_add_error_messages	2020-08-29 13:39:25.605602+02
11	auth	0008_alter_user_username_max_length	2020-08-29 13:39:25.618229+02
12	auth	0009_alter_user_last_name_max_length	2020-08-29 13:39:25.624467+02
13	auth	0010_alter_group_name_max_length	2020-08-29 13:39:25.637027+02
14	auth	0011_update_proxy_permissions	2020-08-29 13:39:25.644966+02
15	auth	0012_alter_user_first_name_max_length	2020-08-29 13:39:25.652379+02
16	sessions	0001_initial	2020-08-29 13:39:25.65702+02
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
1	\\xaeb29ed973fc772f09432573349f0accdf7b06085ef01a7fd322b47332d7e132	\\x4b468e9a59d54f59c4f77077fa1c46298dbbe8670b5b5c123fb363db01317a0350760769c36dedc61c2ef65f86288e837c725b3f9ed18990e0288db11bbd81ed	\\x80133cedabdcc5d4ce94e9d172a278e12de0c19d2242f91d5160ba3006a80725ee4293f17674d3f727c4d969f2fa90a321ca62281565a90a166ea4ca14ed88aa3ed0b24c8034ed21bb1f6f80324f617b6579f738c8d8ed2947b32385b4ac195484fb26b156fc9940d1f49639b1ee8e241c1228443804656ad234634aedafbf59
2	\\x501df4e363c6e61d814c6feff52f112343c3d15305aef608257384ba9a4371f6	\\xd9b1658aa22170a31481fe95e0510fec987c8395597d011641837e8da25f4bf6d7723916b48c853f583cc20401ca9d806ce9f11542e808337ebaf5fcef31666f	\\x6785cdf0a762e2aea1a65b688e9d86f6c7818ce4c2afac7f52549bb6cc8d965f9c579ecbed609f061dbd3d3e6297430159356c6225cb05104b41cd84b07db308ebed5f3570110a92cfdc3cb3b96902f200deeb2ba9630b3d934fbd9057e231e36d9a6e327eeb6e527acc46eb157c190f4a612455bb7a5173253082a914c62ddd
3	\\xa7a03b84041e815860bfaec6da0358073048e1f7476ce838ef19bb73202eda98	\\x9b1f107f719abfce9fd4458fce91376237fd4555cab8dc3bd99b3a54fdd198871e05270db590762f21ea397f81021a87ef5dfa78c447c4f9ac3d4a245457a7c9	\\x9619e84cd18501ea9f9eac6815dffa50830b8419d6102f4c61df9ba39ade60f886d31c4c7f6c888e2d19172b14a9f5bd2b3abfd3ee733a627f78d4e5a54f2cb121ab4e59eb1bb478c210b87a31ad1d323684c63cb2b8974f834f8551ee9a41a1e41fb6410f5a740f3a62576227beba324b97fd0c2fd81dacb282aae3f52ec51a
4	\\x017431c4da9f50cbf7e77206c46c422e98174ea4ee23a632cff3d0a05c5e5a33	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x296dd46e7e458079939d9ec2409ff8ca31fd1a63a8fe992c9b466bad579df7851c9bd524f1baa65eab46039f5e2b41f71dd7c929d16a5c0092e288b46dc51b9f785b57df20b15e3d79a5ad159767668d7753f8d9638d5cd78b1dbd2e8a4f3a27546c38a9f7969f8b8a3825db5dab43ddd1a0649abf5fc3c9dbf41e38f1c8d7d4
6	\\x6d3519de0f3fddd5fb0c8891dd156cd5d08e69dae4161a92a293b56acc0eb24e	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x552de36500240303351928ae05a5922244f503ce7f133d1e394ea742db3325f28186241c6aa726758184fd9cc9989eae6493bfb3a776abd2534c85115f71ffa84c558a370991590be04305419c7b060c946574018998c3da78eba28bdfc863457685377d164027bcb3c4647b08ef7a29ba1dd54da2eda13d3933e4aff5d30654
7	\\x7a2b5efb5d9bec0754ec997601fc473fa9c0a44ecf4aa7e9060cde6ce5783c0d	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x83f2720b8fe1bd933d3bf7edf3ce85e0669426f539560abfa038f75a801dc740341337d1e8a23251dfae24f2f1f4dab9b029c19344d33f2492cb3daedc8a088d59c6c0ba63ec6927c249c207b43386d36c967b6203397a0c6c0fe090a798734ff18f26068bc37dd5d27166231b60b5c89dc9237f0f94520268ce9f5104f8b6c7
8	\\x330bfefb5248f2dce5f2e774efeec48dda4e5caa5d6742e55d5dbf5a605546ff	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\xc493b45abf6eddaa8727242faf5e3e3dacfcd8445c9ce0bf916ddc4f83b0c30aa00687467186b30501037aff52974b2a801c994bb54ad5acbd65c3a0d3b68c4caff35ac9d4d1bd1303ae38c1972439255016aa7e2e37752276997f06de92141a46fa7052ea18ab558b5f5024585f461fbec3681541758aa3522536e44e18b8f3
10	\\x07f9a0ca26a0bf10b61ba850ce5ad38091d30f715728ee99c01a3c6c5dc9eded	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x06cbc330738fda4f4ee52a365951fabb19abcf521427bce7e1513b143803751db01f40f7c9e1ee71b4e4f2ec5caa59b0a36872dd274998c6f8b64c577709acd400883d4be7f0880ddb2b8994e025e5f2f2dd3da78ada8f8a438e5ee49c2cd8fb29f5c27675d91fd4a7f9001daa44f37176966bb88a3aa99b0a8f0457183339cb
11	\\xeeebd66c590dacce2f88f96b94ef36eafac81709f0cf4a3031dc23a11c3fb364	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x48c8ac608a731d3c3aec98e988ee7fc8435edaddf8f3ee1f236b75a4ed98a35e4b6ffabe103c88891d4d4b2eabe9210e8f3a094ca2e65c588a5856d4f942bf4ac956d157a7dc03ac2ce5b3f2f074d0e1bcc6cbf20e1b24b4014aeddb80a0bd8df1f39069d966f44d5923f3b244a640aacc0976dbd09236f054ce74465a6325f5
13	\\x31279d348a9c42ee4d05564b8bc1b2b77010f1cc1e1ba861b3165f72c7f30791	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x2c7e68cb2a3084bddb3f7f8e5b311a9a7ec0cd3a7b61c0f0448c24a9b27137b29898c363ec9574835b739dee5d38419b160fe16814454b73f330a54cb854eb47920d91256354b9b46c49c558b2b70ee81b533e9f12467f1da3ca35456c9af82f3ad82602c5c8f9187d467550d209d99c386d82a3b268d1935b702b7d3b5d2f1e
14	\\x5aff84d9d5414577d182dac166eb13022d02e8e59f1be65f4602fee5c5d356ba	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x848cdacd410e121965cf79ac0a0391aad5e1ea108a0c0ad5472399b6c20c731d40f4a0206e269920fd6024a7e82eaaeccc1f43db158d334f430473403b8d9b3e05fe8e0f2120f6d12ad448e9bef8456fa1e784853c67d49b8b4a57f281e1e221c524ff4833c1e507e1ca20967a25ff3e2a9ccb6ec72566a38fecd5bed4d7261f
15	\\x08ec2f41cc18356ae1184d2f2fabc1ae512ad16400ab5d75bd332c0c9bb6be8c	\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\xa3efe2806c16ca09af29a53e48fbe2ce219861df88ecb6f2060e2d5c3673a2f8c07c6caa7b823c96ab1549914a3ab668608f3fcb6ab53318391092a85889687d5199890db90f3f175e03868f99138810289dab00fdb19406d75769e0e9caf027f07f5b5168da81c0ec86d595f7a6837b41df883c1c2378bdffb48e0e7b67a5054525f80790dcd86cbec1794697268b5939be020930aa99900e88749c7e6d612a008cc7062eb6e685ea3910a8992d57df90a392b468d829c596a618e06c1d93de1b4c43f08226e870d785e82d62cd18ac46e2097b4978c4680acd6dd78b725d2279ddca4caa99d40bd5737cd40dada49b66f0e6113c06309e4b8d9376be5b016f
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x655cea35fab5eddb0226309ddc4dc7113947b7a16ac2494cf9f7a0c170a014079da705351831aef69867f95ca54bacc388e59929d3f355e426b7dd53f4188011	\\xcc1840a4f03651558dbd2b4355e188b40fbd0a26cfb67a05073ac110f849fb7b8264c023b571f888459d03df973083b7f2f266542b5b69dc7cd7a862dc6d75ea	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.242-01GFJYA6P3Y3R	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313539383730323037363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313539383730323037363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22434e45454d444654505150585030483636324558524b45373234574d46445831444231344a4b375359594743325735303247335356395235364d4333334251504b314b5a4a51353539455043373237354b344d583757544e57474b424651414b59474338303438222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3234322d303147464a5941365033593352222c2274696d657374616d70223a7b22745f6d73223a313539383730313137363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313539383730343737363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224746314e52363256544250415a4a563835454a3535363146414347485342374d3151454b433144503441355136455a45314e4330227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225146324a334e423457365457524d4b37465948524a4b5735484d594141465633444d395733413954353339305746534e41354447222c226e6f6e6365223a22374459354b445457333756545459364e5a45394b5a37525a5845324b54565048443251314139533251335237443048304d4d4447227d	\\xd2813ad28e551917d1414e6d63a0535c119e0c88fcc9fb4ea5520349821927edf011e6f74aa27e71ad932dea9597b8526535aca66ef2269224e212275c26c4b7	1598701176000000	1598704776000000	1598702076000000	t	f	taler://fulfillment-success/thank+you	
2	1	2020.242-01C3HM2558EEG	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313539383730323038323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313539383730323038323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22434e45454d444654505150585030483636324558524b45373234574d46445831444231344a4b375359594743325735303247335356395235364d4333334251504b314b5a4a51353539455043373237354b344d583757544e57474b424651414b59474338303438222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3234322d30314333484d32353538454547222c2274696d657374616d70223a7b22745f6d73223a313539383730313138323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313539383730343738323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224746314e52363256544250415a4a563835454a3535363146414347485342374d3151454b433144503441355136455a45314e4330227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225146324a334e423457365457524d4b37465948524a4b5735484d594141465633444d395733413954353339305746534e41354447222c226e6f6e6365223a22354e545a4136584b44323252365050395644455a4146534a39394753374452344333445a3330523156463843474d515237375730227d	\\x1bc6f0800bfb077546574fc5901295bf613755a5c3d9ce7f3ae02867c3126cdbc48ea1890eb2e3fa5bc8977c9e6397e09e4428ff619a6a173d767ae1a884c127	1598701182000000	1598704782000000	1598702082000000	t	f	taler://fulfillment-success/thank+you	
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
1	1	1598701176000000	\\x501df4e363c6e61d814c6feff52f112343c3d15305aef608257384ba9a4371f6	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	2	\\x8983581f0dc8d7cd8c6b36cbb1880fda54a8c4e575278007b15500edb4b57d1a16511e98d232c12c523610936bdacf3f9916385688cb4fb7282a0dad512d1903	1
2	2	1599305983000000	\\x08ec2f41cc18356ae1184d2f2fabc1ae512ad16400ab5d75bd332c0c9bb6be8c	http://localhost:8081/	0	2000000	0	1000000	0	1000000	0	1000000	2	\\x99f6f86623d178c27044d064a8d40d4503d0f72a679797424e3fecb3a118a5d735687c1bdd2f663d129e975534ba80bc21433e1ceb9b13bfb10b51beaf0eed07	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\x8ce1ac0ea4a7650df8e25d3487d64e851cf0b2b9b4911a0d7f968a597215ff43	1601120361000000	1603539561000000	1664192361000000	\\x7c00d4e1da564bfb2f0b9115ba21d9bfdc2f9a4dd4b6c16b6019a0f4a3e6fe3376525163a308a97af22e51af5bc79ac9c58d6cefb2c5c6444a60e985f1604d04
2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xf04c1a56f0e1a9bda14f99dc8f82cf5aacb968f0e7469b3047bca606ba20f21d	1598701161000000	1601120361000000	1661773161000000	\\xb97f281951b615e4e7efd6c7be7b3252b6d3dabbf27957bce1e921e3ac8ec841a84c669240b426236317786d5210b3fab79a1db285f97fc93358c995eda9b60f
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\xb4725505613c401b6e50c4921b3f8841648de79335243125de6bf4564642f6136372847a79a725ac0a75bf75169085a9bcc7d497ca5bda855b37a099cf312d06
2	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609455600000000	1640991600000000	0	1000000	0	1000000	\\xda5722d03a8a1136d9285aadd2776a5d154b26eff7f213d47ce064455d87035b1088d272b447b7a63c0fafa38313243a9b40b860bee9f7a6c46c7de23044db0f
3	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640991600000000	1672527600000000	0	1000000	0	1000000	\\xee7fad40172420c098990f0ad7a62c147bc7f1f704083b35496b3ff6a305406663388e831484df639c10666bc456f0d9caa9ceee9953f58a904c26ccd128fa0a
4	\\x83c35c185bd2ecafcb682ba452982f53211cacf40ddd3605b6228b733bee0d58	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1672527600000000	1704063600000000	0	1000000	0	1000000	\\x07a5bb55c780ab45580eb06d6aa699742d5959083939882690f2e44bd7513f8060ef4cb6f03ab08a4f7589cc1a37b429caed74002511f3e25e117e2bb2502609
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xbbc521d564e1b5cc52677fa3894f858d3ca53f636d13c1a93a28d20e3f35515b	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xa94d0232e015466d2322b43a53b581440056679732265551dd8d04ccd1eda1be	1
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
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
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
1	\\xaeb29ed973fc772f09432573349f0accdf7b06085ef01a7fd322b47332d7e132	\\x4f4a0cd6b48bc7a86eeb8237a789f88e994d6b4dc0be7a879ed38efb2b78c84ba56e6c31ac3e85421cd9660dbe5510be0f73244ca8c4dbe86f6615f7afac3402	\\xf45d4a8ad3a853d2052a2f1fc5b65f89e70f71e3ca982c5eb6877fdd5cfd0df7	2	0	1598701174000000	\\x101be00ba433622ed1eef7ebad26e8186f54bdfe979aad83b3a63c259023e1ae38f29fc59117d5ad717bdcb8702029e44970df5f6c8aed438494d82930cd7c2e
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x017431c4da9f50cbf7e77206c46c422e98174ea4ee23a632cff3d0a05c5e5a33	\\x2a0ae9c23fc9d14347e54bef76eb8006b4674eb6fa63c7cc0d92b781cee3f3b3dcb3c0e6583819cd84333262365782abddb41461b2db833edb6456f8b6e03202	\\xf46811695655ff7462387256e92c3c1e16c269543b89c92a33d1ed6bd9712442	0	10000000	1599305981000000	\\x5ae96f52421ccfb8565a2dfe396a2169e102842710c5f8dbca4f766c6e376e6006d0d9c1c73ed9f7159f81edbaa263790c4a9606b83bf36b64e85655ce2eeb3e
2	\\x6d3519de0f3fddd5fb0c8891dd156cd5d08e69dae4161a92a293b56acc0eb24e	\\x9edff1bedb726d3b435def9dd37363904b8d747ba177586a177e1041d1572f82bf9caf1bed6caa351443254cdf4e96b5f4e37994acdcbee8dc68323ef2a4d902	\\x179d7d7e3c0dc0f383dfe9605c033fad162c086a0252ffde668508a91519ac72	0	10000000	1599305981000000	\\x13a703694d97f24ad6f12fd71de78a0ee02242efe15ce4d013467fb7ab657512aead0611a58f6085ab5892a8a25d584c81f974e414b756c0c7ee4b56a480883f
4	\\x7a2b5efb5d9bec0754ec997601fc473fa9c0a44ecf4aa7e9060cde6ce5783c0d	\\x3c002920c15bf6f922b289a797a756a2a62a5b1d58dbbb5471e769fe68bde334cf98bf617196b0a11d0438a59752c2c2eb7dccb6640154177b85f2c45d9f4502	\\x3c2e225c33af3444122c8cb2600f1e42c9b242453003b2c930061f17c6c38d44	0	10000000	1599305981000000	\\x83bc18a0f1f96047efa1521a2b3850d024cfc36f3ba95780a527734410186127bde1e83ac9068a527806be24faa9dd22465df7ad894be07e866f33d696b606b4
5	\\x330bfefb5248f2dce5f2e774efeec48dda4e5caa5d6742e55d5dbf5a605546ff	\\xfffc993d5edfe9fb377fa1ce176238a68f0322fa545a21f495aac14cba5191f54b57150b3bf94a6b9deed61fe6456523072f1688db473e47ab7f671bc262b40a	\\xe53dbe723b6f75ed2eb6967cec175c1b4c4a4b843213e5bc0ddf6165d8f6f454	0	10000000	1599305981000000	\\x452171d67fd39185efbabd261258f5b48d560b10cebf77464bc658ec3073593b716b191091aad3a49e7ae24a18e1eb77c400cc3977679152310f4e04d2391432
6	\\x07f9a0ca26a0bf10b61ba850ce5ad38091d30f715728ee99c01a3c6c5dc9eded	\\x31f10931660fa55773ed2b7454af76a607414006b547c3f297f7fde64ea2f63fa4b61aba00ecdccf93b954420056264539a0c3b12d1c218cfdae84897c953007	\\x3b8bb8deb5ba80c36418a61285fe5903a6d5045169ee627d5cd463731d6dbe42	0	10000000	1599305981000000	\\x6cf8fc54359a36fa18423de92e3d2c3654547dd06df0aa8138e088e9c942a8b234888c0bc4b1f47006cb2afb75ae22841ffa6a55d6a1c6635409fb2b11a2abe3
7	\\xeeebd66c590dacce2f88f96b94ef36eafac81709f0cf4a3031dc23a11c3fb364	\\x72a0547868e42f3d246849637ccaec5befa717708b71c243fb3383ee4b558c2fcd7db824463530bf402407206342af302c1d49d89b80a9460e82107012e3470b	\\xc795c3cc1bb9c4e70c67b26a009e0a042d7478ff3a425a76059f243d2f40e57e	0	10000000	1599305981000000	\\xf57125aeaeccaa5adfbbdc259e8c455b3d9419f79c77d0ffa5e5ac63fb22db23feded0a36951c2abc07dd938b37aad4e72747d28e2113ab6771bbf9dfa57d831
8	\\x31279d348a9c42ee4d05564b8bc1b2b77010f1cc1e1ba861b3165f72c7f30791	\\x6e2355a8d3554165fd644235a754a711a51f43db49117d8cb6b38b4b7fcb9e588c0efed9180bea4ff988f0c6c7fe328e3e88a4d9be64add00ac6c0786c145304	\\x20bb18b79a297554f98dd570ca330e05d1020147884c54f4601f0a79906189b6	0	10000000	1599305981000000	\\xe128e701c82b984f6d13ae0bb48e51da8dd5ef35f45ff9373d7e96072490d66a6ad976a1b4139e8074716ffd72f7adf33e7c76d0f9cff12da8b3ba387dc61c99
9	\\x5aff84d9d5414577d182dac166eb13022d02e8e59f1be65f4602fee5c5d356ba	\\x98cbafc410842721b356051377a3dff4cff54c6c28db10d4fe55f9476692cb01212b52dd53c78015fea07d4e8800eaa623211d3bc29e036ec392c2e72b73a80c	\\x13c67b852a943c60f3ae493129eb2d7ec449821ebcb532b048e2b911bcc2cb82	0	10000000	1599305981000000	\\x3cdfc0a7b81927e3ee622ca7570cec7433214fe492b0d82a1048ce996ac9d79d0268a89e53de89e5d55cabfc56a000820bac53d957f37fc66da002dfd88ac704
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	\\xa7a03b84041e815860bfaec6da0358073048e1f7476ce838ef19bb73202eda98	\\x25fe564245b57369b200e4798dbfd716d2684fba9e65659bd53f1c303fc2d32f5026144b78d399ff8d1fd8bac5dd40945c613b5adc0db83559f68388aa38fe0f	5	0	1
2	\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	\\xa7a03b84041e815860bfaec6da0358073048e1f7476ce838ef19bb73202eda98	\\x204549276f994090331e03ad65eff9026bcfa45e15f0944cd074186b59267a3f54b9b086fb0e76ba35dfeee20b60d4c4afe10d6658372dc21e1fe08659a80006	0	80000000	0
3	\\x601ed8616ce894bf94091886652fb32531bc083b5781d38236d60293552266d33b3b417f8e500ed6bcd222a75bf02df1c07f06104ae7864bce281457e89ae1fb	\\x08ec2f41cc18356ae1184d2f2fabc1ae512ad16400ab5d75bd332c0c9bb6be8c	\\xebaa8f939dcbaef15a34e5cd2b561ca8f4d55cbfa743850200cab1a6d2c6ce9ac56b11036336aca444c1a6c0e317f410e372f0033406965e44b3bedd9dc15c00	0	7000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	0	\\x738477a17c712161c01457ef7e1d378525f169d4bab6b4f4f8b7a9f3682cf26dfed28d281da6db92ce07a47cf52c501b1e1c99cb48b504d47e5af88f20819a0a	\\x7e58726bee0066edfa1a63f6c76594a5bddde68c07b4b5d22413c311420acfeb9a2c98081783e56cb8c998c985c57a6961a87e2494465117e3d24375778afb7d	\\xb1d0d400949c24653e5dbf6ea6e3a64e8d0d594b405a63bfb34bbafbff7f3f81b5cbac0f29c98aeb885c1ac342e7991b29fee8ccc12b62081cdce642762064ed6a2534f2e17c8db2a209a868771f7a5d5ec1479cd892b8bb577eab00391e195f5319d7284ef2a323eea97e3095fb1a30ea863f382b6060b44f28f6cea24940d7	\\xb0c3ceaac1eda0383a13e21ca102cf5924710792993c9a3d519ecbaa0a43df03d85a5461a2bd7072a320c749d8add81bfe7934d2c821d05f71484afdf452f717	\\x1cb84ad8d92c9402a9d1cd8751b908c75f28a73b34d49c8962efafb5c8ba5d1cb44f4c035acca87b56edb7bbd02781ba250273a32d40895019dc1217e424a454aad7bdeaab40ae09acb5275329c6bc78d7dd0372ec90e2eba0013986cbded1e068a248bfa3afdf2d71bc6e6ea41d4b6a064d9ed9e7a6934f4aa9f3a2b54ed07b
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	1	\\x9e6307699b7ce3a3878da534cac07c902b469935b7c0f337e5456b1421906a07b972fd4576f5d3837a25db2ce02fa37bf907ca3bde1b93934c37c619e6067609	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x76ba238863a4458b5dc66de41eb4e1ac854ac962b42291ed8a34e4e4b74542ed4cee15f1cf6618187e72a86d7e0553753e1b4d7e4b1a7d895ff7852395f858b1c30ee17119417593232de2fca30cf1c68217b8b88e479072463b8f3dc77f34e4b6ca01f979deee7bc81a0d485c549168c8f2350163cbca20ff8b4edccb6f413e	\\xf57125aeaeccaa5adfbbdc259e8c455b3d9419f79c77d0ffa5e5ac63fb22db23feded0a36951c2abc07dd938b37aad4e72747d28e2113ab6771bbf9dfa57d831	\\xa5d65d2820af80fb7f3f6fdc6a0f30140da0d2381feb469831ee95acf9259d9a1a1b16a64dfb5a35f7b7119e92e5a066c3bf561293fd2b4d70d77f1c524fdef9b337ba1a8d0e440f579081afd00585787085b9b52a8e3628577820ecc743683e3c15f6702ccf85473d27e01fe9ec962e8086a58fd181f78ab26d33cde4125719
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	2	\\x2fc7dfa70681775b932053084f718b5392765ebc884f9521e9eb8ff32000ec1939347a606432ca1057ea78027be53a3576350aed5fbaba2ded66e410b2983000	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x62ab451ff53f768956e403fe8e02ae05fb2419c94fc021e2e0afc5a64b41e20474752e524170026f9590c7fadddc410608515fbfdec594254e5ad4470bb292bbba5e7f7aa31d923087ea7861a0eb76e1a5657bb61b847d00052418ef8c9a5f31fc514c4cc078d9fd80dc5e0eaf7c388596163a802d0a3f48d63b69f289a90388	\\xe128e701c82b984f6d13ae0bb48e51da8dd5ef35f45ff9373d7e96072490d66a6ad976a1b4139e8074716ffd72f7adf33e7c76d0f9cff12da8b3ba387dc61c99	\\xb1f93993e275e1467536dd1601ea6dab2f6b596b2d22404a2e6e46478034b8630ce69f7db568c4a8e0d0a4ee365ffc911a5d8550727d2cbae8b65c8259eb54829c8727b28be6da311cc321a8ef3ecea36f8ff4dbaff663e2d6a86d19125eb7f6284a36a0b7a245da445f890052f55667ecb60af8e39686c2581c8695197e3d1d
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	3	\\x972b488f08f0ca0808d72e495e3a4f8b849eac0d0c8e7fe633974473300ffa85e1ce1c7edee6c30684fec28573b2ee3fdb479bd3a22ea18b89bcb56e2f275b0c	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\xd671381ba206e27227b09fbb3bbda60ce1c7ee706dc0c5e4ae561f0106f4e3604e6942116bc4708a7d8780054e329b52fc6dae87836882dbcd0368d1ed2c52166a7e3a3873bc14d8153daff8e64bba1dccdc9050d2556a2b4f473eead2ee853cead6ec72cacd2bd1bc08db6baecb51a43db0d3a809ab0ddc18b943514bced429	\\x83bc18a0f1f96047efa1521a2b3850d024cfc36f3ba95780a527734410186127bde1e83ac9068a527806be24faa9dd22465df7ad894be07e866f33d696b606b4	\\x3cda1a634d278a0400b589c81058de5f2768282464c817a4abab394e3c268b0158d8b9daa7e9bc9c9f65f78d1637178a9abdf8c269891a3118a36c533c8b37ba80af2279ba326826be48ab6b8d570e085ed23300ad46bef11095e102605021f69237c49b34d2f4cbca194615253b5edb3610b7753c9a1c1db08ac2bb904d361f
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	4	\\x373572514fad5a73655d1f7c9c3738ecb3a4a36b8d2cf8e87adce23d97e2a86773a69596d9222b50347a6a58978681ec2d72add24e2a8f3ce464916ca2fa7b0b	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x5970960204ff99c23f92c2368cc640699426a1d564ce60421ce248b045223b90aeda05e5fca9a774607de39d142144693195ca6d1a6b58982567ff86766711e7c1ad3c8134551841775ec0af65ac5c983483f75be580b335e27a132641265590906787f85a0d9f2d53e217c575e3fe3e7df14ad97c60739a2de538ef3958ac1e	\\x452171d67fd39185efbabd261258f5b48d560b10cebf77464bc658ec3073593b716b191091aad3a49e7ae24a18e1eb77c400cc3977679152310f4e04d2391432	\\xd00b5a77d86f58ead82b8ac5812c4e29bacfed1f32ec64d52265e4a68738bac1fd49b3dc715393f4034b641cc1e4d9ef0ea6a5239bc3a7e016bf91e31d2ccc20f84b87f888b718a87255853ad038d9e9c834765ab5dc7a2d72e7b144147ad00ec092fd51cf45e310bd43de5b5f459d3aa23ad6cae2912b513b7c71cf70de61bf
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	5	\\x1ac6edba9e20366d924483e36f4f771b01fe4efdac0266e99c3605490ae5c4ff5be8bf8a7aab2b5947aebfc6c392722a3cfe8250d5fdcb4fba06871f3ac3fa06	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x9652dd9663ce929c2da2205dd465dbd630176a840d6449229dd41496e40800bffc31ec35092cfbb6d7d177f5f5a3eb845d66401af5b1f65c56b5e045e567161afa95136da38c55a10f32d4f71bd78ec537eb5439d6c6479dec8bae771249c9ea22187aa096d8fe0e8bb07bef638efe810a06deb9a114e26e186c317bbf604ed8	\\x3cdfc0a7b81927e3ee622ca7570cec7433214fe492b0d82a1048ce996ac9d79d0268a89e53de89e5d55cabfc56a000820bac53d957f37fc66da002dfd88ac704	\\x997a9f30d54ac6d15dc31fbdfc990233d99111c56f8b8ec576feb6f0e269d2fd4664bb78ed046c9cd0b2f5bda9b69372a16c1de7d3c616165dce268ea27369cd91fae5875edf109bab9a058e9c563b03fd3470fbc26167d36c3490faf6e19d6fbc5000ea7ecb1b6f595516671bb8c97dc8239aacd18c9e05445357f2eda8fd89
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	6	\\x8a4b99330c86fb8a625bdd2bafeaa76b926dfa85a1f8a883e896ec879591823eede55388fee76ad29c057cd42f8e4ec9a8192509bbb09d9de8744d17cfbcbd05	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\xb25e1ec5bca836b6902c3d359c7a8856d4a75a02dff8f4809c732b6d095e6b8e11c0be8a402687cd6a1809604bd669b9409af790d5b42c3fb6f5ce3d3c7f4daefc5c2b0f0ad554ffbd1e3957d91307b0a551b9265f0e23dbbd1e9e642c1b8c321b9bd92b89b7cdc5649a61a318ff916b6fbf6b286c5f1d88dcff266c953d99fd	\\x6cf8fc54359a36fa18423de92e3d2c3654547dd06df0aa8138e088e9c942a8b234888c0bc4b1f47006cb2afb75ae22841ffa6a55d6a1c6635409fb2b11a2abe3	\\xbbe384026b9b949176b6ece860bd1e2227a70e20b83396dcb9acd1f0fd5d36e9eeb2794e841676b5d6b5f6eb8adddf4df32180f2e09bfacb327ec409284632ecb623c8e9cac1f232d0246e77e361ffc8fa1140117d472f0b997747625a8079e0b39bc6746d57f88d578d48d74361197f3555b2680f6f6560ddb50081295a7505
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	7	\\xab28e21a130a2c4250f7b4a9572f6d7f7ce31b5da65543710a7dd7bdd09deb541a0b9f3778c861b07d9d92770cd35f71f83e49d8040f063e20656dc981ffad0c	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x443f3c4f1a487765d77c5678f348f7b9e306a20027aca962c639bdecce363565229b94fa2ba923ce910b384541b6efe41a63d2b1d84741f7943776d5c8eb5a50174c0314dc45782d36adc3fb0241f12010d11829f076c84d1f10268d28aedaffde5ffe799a71dc20075d662c72a6dffbaf7d8f1ebf5357d837be4e27a27d0854	\\x13a703694d97f24ad6f12fd71de78a0ee02242efe15ce4d013467fb7ab657512aead0611a58f6085ab5892a8a25d584c81f974e414b756c0c7ee4b56a480883f	\\xa3782decb562baec1b75537299bd613c7bb345301237477bf54767ee665e28e9afea44fd050af7753919451dcd85209b1b152f758160202a1b0e6f6ef2260496c5db34d98b6dae5e4eb510b31e19c88d66d1e27db5e91355e981a65a8153e873a3043eae4cf92ac6865c9244779a66c1b2d4e836151f5e91b5a5b40e319c24d7
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	8	\\x5ce172b729d821b0d624253ee9c04bb971ce7cfa8702be7a4edef569e6a0e6cd306c75debb5d03db4e1b8114af9c6a35163917483818cd96abc4b82c837ba900	\\x340f19543f67c26b178210f814ec96945bd0817af0b4b5bd012d58970d0640b5aab11c624f38139bbc03fce39d1ccdc35c845609d7a18d5926419fb098fbcb9c	\\x9871a48239f2269b4d5ffb89c5c6fb8144ad6bf95b45d1d0c9d479ad429a8085222e455a027c911d62ea0b5952f09af6ccd9ed87db4b6b35cc409ab15a34bf888ab6551dd2da9929c1fcdf7e0a8719ef9c92d52fa8664f84e33820efe8a3788b156405c4e5e09129a9490fe17d7c765b8c0bd9a7ccde9e052f7b83933e8157fd	\\x5ae96f52421ccfb8565a2dfe396a2169e102842710c5f8dbca4f766c6e376e6006d0d9c1c73ed9f7159f81edbaa263790c4a9606b83bf36b64e85655ce2eeb3e	\\xa7bad1dbb2e06110359acdca503e3f35e2d16c07f580325203a2a29880af3765d8c88257f75e17265102367b9eb3a04df35a4a11e50c8ba5f22b04b47281fd8e8a64122fc72ca55dcc7034c4712ded03785b37cde510d311c3441744d44be2562b846810b2aa4553db8f55f27ee2f1db9c9fed9b03cde140553221ff04957f07
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	9	\\xe94122a1a20ddbbc2bd852ec92237d4dae2a1a245403bcfb1fd9077b824590cab339543a1f78104e6e9b5fec58b7934152d22ad57742fbbfeff75fa2aff2e901	\\x0d218fe7bd93f741663d5a204981f7722677d86023b452cd565b26072254b47bc73f2f3b780871348f6ec4f14fa5c7a568b0ba9f39272040afc64ae080882236	\\x19b68f302452ac9298fbba064ee59079c5f42ff54c9870a8c1506e20c6432772759386a814d8c11ba93327860dc3d151a7da3ccc7c741ab52aac5cc3d0847fd38c58cc783b1ac72255e4884fcf7be744c47dffbf50c79e6006a33fd46f63953f42f09d854c03826ea054651ed8009580c6cbcf19723d2d43adfebd1055746061	\\x2655f6eb0ed4970a52718aec524b871dfac114932826359869c0d3459e648056e24ea945e39027b1a34522f80c3037ce46c15f87e845500640c1a04c4f2550d2	\\x08b7f3850460503f344ed1a3a4b50c527d91cf11db04e305ff8d8b15c9639c9b217f32577d57fc334b304267a69c8b89852a8bbd5f7945aca6b65da8dbe9daa74c53f21a2447ddeba0c578bcb910a44fad5d68f87aaee63c8a756bd27a48ec791e87ff077120b99d4e45126f4615508740074ca3f868401e188e389acd1e8060
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	10	\\x4853daa8ecfc324dc1465c2e4e43853e365ab248d9b09a72a7a1c34c3033d5cf06c4ae7c9999767b304aa0d81b84a2ef3965dc501bb6c46ec10865f86b1fb401	\\x0d218fe7bd93f741663d5a204981f7722677d86023b452cd565b26072254b47bc73f2f3b780871348f6ec4f14fa5c7a568b0ba9f39272040afc64ae080882236	\\xb87f7305888f57a1666ff13a46b7435a342aee66530da5372d3413edb6473bad50fdff60dd0694e574ae11423863964f654a75d0a0ac7e6d52dce454167e5cca35af3a7e9fbae5e4ef58837634832865cc4ce20f8a6462bca9373cfe099ce6d4ef0765040ad1ffe1ab4edde85585467e140bc91f8e91b8c528bd41f8739205cc	\\x478964a8a677b642d202d29098ab1233ca8adb30fb840e0096839ceee406ccd261d22af855bf11bf2d997a38d10383fab46ffae582447267db85709551a3c32f	\\x68dd6450ce299812c75a585f02c7bb601131626953834db09bee261447d6b6dc92a91cc660d533fc6bb725f83f1e8d312d1ff4cb36693363ff6181eb7b7396b3ba352f6accea38787e939d51d85f21e10b340cfe2a2e1985b39e2c5ab6d222fbdb77723712a5943312e9806273bd2312ed2bf17b1b000789ea20f4be6e01f2d0
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	11	\\xae2e4e61d647bdb82052266661a39850aa0fc0375c4639337bc5e7430548a19c138a61170c571ec6fbb143e75a38df5d8ce09b8affd5e30c4106657d552acf06	\\x0d218fe7bd93f741663d5a204981f7722677d86023b452cd565b26072254b47bc73f2f3b780871348f6ec4f14fa5c7a568b0ba9f39272040afc64ae080882236	\\x6725e5691d8dc2642f49855398abac948dc9ab3b695095f1a191b54ac6c9a838c20c3a08c1984cb32b71d087253799cbb485cb63445cdda112a6eeb0388c76e55535d2089b2da36b2d937c0ac3b034b9b96e5d4a7603522fa6d25c288df26bb106b07bdf66a4d2ea7c899c6be34b1429c0de3fafa861e5ae41e611b1746c2958	\\xccadd35fe8fd770143929885ade3ff8f31dad31688f5a524b05ff6b9536be28b8ca72849288a6f994b3023c04779fe763bb216be27d09296f288473993e94427	\\x106a0113693b61e7c6510b7c743b46aefe38903a19d296fe2767fac57a5cc1b789de81848da80e42ff1e4cf97a2ff17cbccee7a91833b5ead35977517584952c003d609198fb5194f484cc744b10465c487b90a8323a53b3da5b2e7d6824486285a96ae2e9a9d66b625c3c68706f26057c4b40a38f65c137368741055ec7160e
\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	0	\\xcef8c8e0f7a00ef4b0a444fb144285600548165ea2c8863077a7e7c52bb8a914cf674252567ea6f435a77a2d9fb3f3d4e1fe78822619c00133ba922eb6ae9702	\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\x6e772a35e5818fde27351de7fce3b7be246118fdd3e8d5024bd50a0d34cc3e2681883ce15f90787be671a2cdeca412555b191b966f0d9a27145476246e942d20d6dca075fac128e4e55f3e5daaef58399470924b2c2046e84b002cc38f86e3bce84b5d30430d1e4b822c8edc75703771d04f20333265c24755346414ca81b2a462e8141ffc2fdbe95988b9122964f531f39f87ce390a001a8a8cb71bd5c2239071011c2ba3e1b4d926257e45e2f0d4888e75350db148fce6f293d770a1a46d94e5d1e7103fac8aac7d191f3b846b782a639db5c8025acc814e489c2ef0f8295ef141a4d2486ed28f8c43b9f94854bd010b92f1c7b718876088cf871799db2d40	\\x0b66a1efb0f0cd1268fdfe657b84562ef68c0299236e1c05e8bfa878e8632bbfb6cc8191230ef54ac51223ecb949b36f0e25ea3f575efd91876aeebec8dbf69f	\\x4b2570f91e5862a5e43dea7d4b1bc68595ae8de39ee6efc60eb6b5bb288b54593bc2dd8fc3a089b15549d3de86d117c91f700bb778864879106630a961666c7d5d15d696b59b19ef6f2d86619745dd70231ab4f03a53b5ab9b7c477affe221ec9ac4789a672f0f974dc0d0273a685f22e318fdfbabce5aa5ee6774543fa9b10006c71539ed40eba18ef050d1d94b0e97465b248db970fdcba448d3a12f2e2130656def534838ae677fb986f4184bc3100d5675a02213e872fb1bfc3157ce67905341d71e1a8f58dd908d80b0ee8093858fe72a13baf5330eb2ba157b0e91cc3f698fb8b8dc26929aa2869428ba8f7c7b2ce9f9766473f1d66ff8319acb6c9c77
\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	1	\\x751698db3ec8b3f96e1e145e842179df31221bf77ba7d062563a2b5835e3fefd40a2bfefe159c02284f993cde7441343f03761c9ecf2bf441c4e42e713463504	\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\xeb12bcb4e0cda87dc8411417acdcaeeb28b7b28e7b7b489a3f4da4368dd80429d0e0ab938d50111746ee7e6ac957cb4046734d23ab1660a61e7474c288be686f7c36c1aedd47cae4e65272cf4ae6a0eaa8b0f25bc3928eb750e8146c8badd46a57b47507c8d42278fe05de158e685342e12f0b572384d3d185ab59769db71de3b6b61666e9ba7add9edc5d351305189ff903c5b3d36f26eb06da9d13f44a3087b60cb0ea7ef49ac30ad13850a296158c2e47f8eb3ff02864cb4a8b7c64f942f843b350b2d074419264f1bc3756c8ce537f974e415123fadacd900fb0a4d4a53282716bd1f92b622ba6a47aee35c6934c9629870b5b4f49e029ac3a6457f3eebe	\\x93d08440e7213463f48bcdc44e9afe719fe22bb099bdd9dcb42169e9ce0321e7f6b716a31698edd26182b2d16bfa6be500a4bf66073e8a38ee798163fd39a314	\\x7920ec885c9aa362d9834b00a0b384af81f1163482dc025a02c38d7313b4bf90b3648332d1fe79dd00028e51a2f6ce83a25ee7acd40005788e2db318d1c159187fdfccddd5a0c5356a950a171165a71f42d7cae3a4060b9a0ea0565d686f937effba79dc049e374f4e3cf607e1c9cb52f3b644754eaf568ee7490f53724b819303db479f7a33931222d287b68bdd9bdb17f294807337ac38189d84a0973e9a45b2cecba1f385d54999b9f1015844f40ed575549729a7653c6022bc185c832fb8995a55029720f0a43d94329c0d959290728950ab8654f3c776f50493a3f920b48e4f106fd5252654c45982deff1a8ff39357d615067069cfc2958c1669167e8d
\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	2	\\x269879a74fa4300210382e2397d2f349fa5248d004f3c1eb146c0d4fafac01fe1cd715419b9e014b4157d681354f9c28c220433c2cc3377009706803507be50e	\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\x18e69f0f29194ede81b0dd58f3402f0b2d6071a99071ff51b17de8ba8d70d528bfa9d19e5e00150f49d84fde2a7e35603c707fbbedb360cfd97e6ca606aa1fa84003435b4b4d968afd87407a95daeeed445d243e2b30cf79ad84fef18652217819c71a02147bab4c28adeb83bf3487d4856691fa3668c4db3a13f74018415e183956be971808d58e9bb9cda43247e6d81af84546c2926b7dd22f01f91547d6922f35d84c8516a05646330ce57dd29d66da17e91830a50c60661ea410e9236378d056a481ffc1cffc2c0c21d9d6484061e2080bc23c0357a93703aac7aca0343ba2acfefc7a791e06d2537ce7d2317bf789a90a5753c795316b1fbcf4f6a562f6	\\x08bfea088dd3b8a56a933388bd6e098546eb5241cb8f8bc61a06233f1b344f5e060934f26324b461df9ef51f0b3a9ede63b134d48bf50a25710518c6e2a530af	\\x3d29f386c27390708040951b44ffb0d68f7b9da4e9f9990fd3691b8d7e3b4210c4692b5a9e0f31479dc9a2cfff2ede01a2dbc2ea9d71db00c16ed8fcb2d2a9b99c0dcfc21ea9078a3de58e419a91c040bf946bb9d397df55c88018db4d278f587ddaf907c1e494c3040720c0812ba0500360ba2909deed0357bbdc061f134f7f757b42fe75076e64aedca461483dee7595a579d30efc4c16fc084e4061fa534f4135c4a0cb8f90067cabc4762cd5802e566ffeb52913c0ae2c4435404a657b0d29b271d4573e554d33309d4f24f6870a9292eab0fe82338884dc79f3faf8fee9e6d923faef92fc286ba992cb2dde37b0307094e89129ce7e81647583eb584c97
\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	3	\\xd6c243114e019f9568f0fc5dc8235a94c2b43d99a264c49a505b1ab2d603e7d076fb9127d9b72c2fcc8e630e88a92219b7ee3f981f5f1326ed798fbd3432bd06	\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\x8d2e962cc1aa2f9072927cceddc6f7e14124d913bb6aad4f14825d032f10ac7328bb2cc46c6edd8131d6b9188d6fb097e323b5a903b58ca10113a1b5f20e4123f4f65c101d3b7bdea7e1823674f0316e8e72f399bee464a489db65479cc1813baa592991bc419fd09da6cd1992cfc0423c5093eefd1a4fe1850a1b342ab3b59cfd0d91800c596f89a856704353c28ae19e5b15a8032b94e3121e5c026f038f3f04e262a97f814d2e8ed16a2071a7f797c1202eec7e206094a36069c646c918f0ed2c737e50a5861803abfc5b81acc4fd284cd380abb465608316615c631a88bd1dbec1f372c10700ecc0429ff4641e11eaadf459943c1af40d23a64ab8ad2516	\\xd294a61e829c71f39a53d81531172e26d593c478503178779efc9f8ac4d58164ae27a13c627017252d917f8b4747d417bdbbc1f7743ecbc7a320ac43b50cb886	\\x64a0c9cfb25487e2e0ca8499183acf5b087541db0d4c5f8fbca930009834b92d8e74b599f912c025e040a30be9521bd58ad8c352bbbeb3b68610729fc1ccde33251616bc832c894003147c06bc5572c806b7a835e506080b980335b2c2a536e8ff73264775ac1919ac33ca4768fc36415757660690902fc115d23830cc1e12eb72ded589efa8dbc756caea0d9371e90af9fffd89ef2d5154bc6cb74dcfda1c7dd4cc1467a76d69015e9cd1e902cfd7571218684636709ce946cdd48f0f3740669630fe94d8d8d4ef425d735d245c20a6d073bf15ddc4df0075d512542d9832bf569ffc7f0a0236f23e27004c15c37bdc354d99b7d5b49e1a92de7ed2a202af10
\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	4	\\x3a680ef23db45393ff2fcafb495ec8ca9eee9b50b787381dc6f01fc6c9355604fcda00027366aef93f1ebf12c72d91b1be9bfcd8ac22edc37fa73234a7794e0a	\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\x860382e51d57644833b80e0976ae809b30fb3b5e6554d0d27f41f2f00544a3462f8660d594c50b5f5eb6d22571a121e682714a23a2d3fc8679016ef9a7520700e039a961a5c723c55433eed5ea4e29f1b573d8228a15ced61b7ab0ceaa6eeec1e0b49597dff6f85d6e6d4c984f5b8c6bf6b8ab79477cc9c7ff4ef4187a6fcc23b4cf4caa8468508159d4f3074b7bc861fafc50a6a9192d157bef341bdfc1ab67e0adb7ae5a3fd2eeeb94b853f0a9916e7847514c6c3455507f864ce19da72771214f22de5db82eb153b4ccb47c34068d9ed61d5c9b58e398e7e3bf315ef9cc11842f7e85c62b0434e23355a344492dc26dc64b274a3cfa2a022d49dcd0f39cd1	\\x0bea5bb3aca2fd446a0527ad7c795ce89fe28e36b6962602b27bd85336d165de98c69d271faf205d5d0782545e136609d431f47c62abc794869267547e3eb312	\\x7f1cfab064b6e1570fa9234fe566ab2cefb252f2854726ad6a4a16e12a9a51ce4d635e1347e6c4c3223e5fd1131abe3af41a9e557f08567e48796cb59022fe1c9e42fc1d828c2e8cb3cd22cc2738eae0553b9c7a5ebca18be5a81f9826c1f8afefff5c8eb77b84b50bee2a01a19635e1c7080da1706cf86a08e7f5afaece3c57624c30bb03f9a06c8027ad023b4ea29395445568e990635dc8fd4c01a04255bb990ed5aab6794665cd782c33f57705953ca1c591c83dfcb6911ed745805cc5b4c5d59c8b43a236d83ae6f2e93ba018523dafcadf8c58d6bd6c0d008d07be50c2255cde5704a617e7a0418899b9d613532249b1e72719edb44edd1b80c3c98c64
\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	5	\\x6ccbe11658e4c56b64d501491457ed1afbcc18df1c1c103eab541610de21efd43e958b75fa63643ac1321d38c1f4674dfcb1c18f0ef14dd5d07060fd2d9be602	\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\xd5dbc8c48ea8b400e70bb1306a3cc64a360bff13e6e49bc3e39a34ae63aeee140cf7ad0091863883f2d60715da6124026782309cc22a5a6ac125a825a003d6515ffa57d4750509f960302d0e2032e48943f18a78cdf248cea60cc1effb800df50e78839e44fda8ce63c394b317645532d88bfb8b605c77a05d11eef414248c9764eb1449b7154c3b57c7e536c16c0472ffae193911f7cf20942d5f685c432e2aa9b53d82bbf67abd1f6fe6abd840fd7547a4e617e3ed6b9ab41a61303750981cc743b6f275356fdacf87f6264b28d1247533f662cc277e54b1be80c5d552ded16c5b9281846affb65eb7ac83ee0e912b8a4a0ce4ddab9c5eab9c8a942902cf12	\\xbea4477691ec06f81dbdb2c1180547665d2223b6bd0c06a18e5359b8b26e4fd36cd764b6bb59391e48a0f7b10220448d7a773cdc37d16ec0de286c0124ba84f1	\\x7add9a61254289b44e4fd7d48a904e13a3c76028b86bc86a43bf563fdb362b3ad3ff9fced1391e14b6b153186792e2970534b04e816cb2e379a2e1907314b92741f1ab0827291ea79fbfee8a3ac228f0d194a861f7781f50d130a4479199985665e5f9b4e23e89a5482904493e8ec12418667c67483b383d10c2deb50f1233a0a4ebcc25d1219cac285ac90544269ea88ea86ae9546fc1f9f5813ef98a46819fb2d0b3937f8f41d2aa0cfa9cbb15ccb45f6d7c363d7d517d6039e7faabf808403532d547e09ef198b7089496b91f8b52f8b81ce8a9f7634d9206f6b7befa34b1f2db3f6cf61c66d880428b13b60c34486652c79780a72ecd94ab856204f72d91
\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	6	\\x91b0ed0fd951a05ac28fa85caf37f16cf203684efeabe7004e92d4a9a1e76a405cb7bc1ce00434776b5b9aa838584697701e91ba7effb6646ffdba6be28fde0b	\\xa1611d0cb5c2b5f76446a543cd6c758b114622417d9e15d69ae7cdf9d324564d5d99aaab71644121577ebb63e2a14709d4c9d746e818bb2510f3ac25a013b5bc	\\x792e67ad83fc965bbf2fb711ae52be5948ae016a05b64e5c2b7fba127fb70547ff56dd5d6e7229fddd742bb0ccaa79d5748745f3c55ec48d46da0390782b8c61dc51b8980990f36f50e633a3c6cfcb1b7c840d018010c3790d1dfdc8614ff408373062db14c23bdb458d57ac28595ed8ecd070e91b11f50cbb8c050fa875833ea3cfd24f97a3aa47d7be95446c28eb500a672f639da210f080b9b79088a59fe1a00dc59207cc14e4f7791e06e2b107d29ec8b59793b37b4773dbc7585580d4287f03cbabf035c35abd20e4232799e50a2a0ae6ee242e0c9e39664e1a7bcfc4032c97c9e372cb17ce75b30683dc3c76de98f79aff02b854e57281792143912f74	\\x4f9df9aba439ba041d15a2467803988f9fb9bfee9bb5268542f90dd77457ce2753e6724f4ffa56619e8f09a559aea8d5c8f36c667ef379a30aa9218c74c281db	\\x2bf4c394a90096c670eeafb51b119012033c88a5556ca2a66b908a5acccbe640aeeeb714be68e2dad5d7a30cbd2e3a3fba910bf87de04bb1314cd8b3c66563931db71ea03b12c1c7c2a7a15df032e34369bb9f964ba7b07989fb761372dc235c53865dce75a63b77953064a6ded46d72da9868753af94294253371a1d5594d93c39e52fd903aa554020c886c4815cb0f0f5301e384724d856d02201ec295cb24e0dd0a2fc65c4540eb0d9aa727746e58425a4bdb7eecba39e5a65d8ea5a4e6f30b13fcd7321bba8f25a64423d7374d17e40c15295d2cafa67fe955d9947b7d6a8aec594ea61e2427567254a07e75bdc7312fb497799afd0df7a94a641456c093
\\x601ed8616ce894bf94091886652fb32531bc083b5781d38236d60293552266d33b3b417f8e500ed6bcd222a75bf02df1c07f06104ae7864bce281457e89ae1fb	0	\\x3fdd764d10580e4044321cd2f5c0bc156672fa93fd7606af52c333637ce96175a2b50238884ed67ff5369a7990ddf5b86c675c5a8a7d3d2d87c094429d19b502	\\x0d218fe7bd93f741663d5a204981f7722677d86023b452cd565b26072254b47bc73f2f3b780871348f6ec4f14fa5c7a568b0ba9f39272040afc64ae080882236	\\x65a2b5033fb40a593bb35f8717d144fb71121ddd5391ee96289d7cc886599b15060f7f340ee5de98544a869a5ed8ca6f650887f61db217a935a24d998a1344a0339d38e19ce31024eef3a05e2e10558401d91d87e8ffb248b22d894cd8bf9c84971c779e79983fb8549931795072134a74bc46119a63b239298b5a16bd79a0de	\\xeaff11c6df4c5e5d75cb68d28ecd15b3262ed9d8c1cefcdaaf8a84767c85a13eaf3ed3f0cf1b8087539551172e276e75bafde9cb7aa470075be669e44ab8105e	\\x21ab5e9b64a1c81a37f76c85327fdb757ac0313ed31e6d4f8b57ae9abe9c4068757b15a5b749c6d2e12cd705495595dde16324eaf6542724e02a61890469f6defd2950c45f5653e09ab6872962655e4c03cdd1f997e6bd29b32507f5284b8cca33a92cc1559840dbc6c41a545b7c50345f301946b7b1da6af88765a89b5846e9
\\x601ed8616ce894bf94091886652fb32531bc083b5781d38236d60293552266d33b3b417f8e500ed6bcd222a75bf02df1c07f06104ae7864bce281457e89ae1fb	1	\\xc1cea0fce8e9700ff878c133f3f73793a6fd299dc7e72d24dd2c0a437a53315ecb063d6444eac6f967ac53947422aa23c32829788a6ab54c014d66621ff7e402	\\x0d218fe7bd93f741663d5a204981f7722677d86023b452cd565b26072254b47bc73f2f3b780871348f6ec4f14fa5c7a568b0ba9f39272040afc64ae080882236	\\xba29c990c69d7edf5e54b133e20d5230386fb57381b611c7770b5eb756fdfdbd86f80937f13ad87897b1a0e584fb5944ed3e36eb2020b46c939ad7ef93cdc909471f75d93f001fc200f4f55b69ae47cecf959613ffc34011d6cafe739d1443443e59701e2cc285a8d30d163823c55f61bd559ab7876c3b19e0edb1864c1ae061	\\x7e6d8d2677cf804304b58e37eb812525934878a207fd9d92995879d5b34a867cb4eb1dfb2a78b75703db2590661f39209f1eca4aa0a859a8ef3e839ca0d9184d	\\x02261f03568b21d815ba53042d740d57ba5719e119a4b531a3a42dfe06803f01a94e17cdced45be30ce8da8b18853c2ff343b8ccc96a6f555deb3d1d9811334428d0c34df35a9ed6aec34040a0a7fa9b22fc204e7f85401d8054de06d042b845cef7819c68352b7e7b0e6fd96f59e0a9cab9644ec1d6d2140ac9da8ef7ca0cbc
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x38edc1bbaa66dbda28de9832e62976ab4d884cae59edc53a84c74d4e6f4a6489a54db377a86b298039f900e16e775554d873d4cfc681115b3fbc5882636ae0f7	\\xd4ca9c54b7c34f396fd140122ee17f449d1c2e2e651b5b927e259d15857a6727	\\x3672ed888b737a2957e5cb9783f56d677d301fe4e19d27cc4d190ab05a894ad912f6ef8a4701661774819019ada87ab929582b973adbcf4836c8bce483da8380
\\xf750e9333777c592efe2dcddb8a922101c4552daa2e1015fef92ec05402cd850d6b2b0937f51775e72ec38681d7d3e7b4d83793308997d4cb2bc04633371c691	\\x6d6993d0d2ffd4da3e95cfe505f1e79b26b50b245bad5e0937a06f3e47d2983e	\\x281689a80644e17e3e631c98e0102584629a3d03d30df4087093fd788b73de56428f8eeff4e08c64de17c0e25afe9b51d78f63047f82d94b0b8d739ab288a904
\\x601ed8616ce894bf94091886652fb32531bc083b5781d38236d60293552266d33b3b417f8e500ed6bcd222a75bf02df1c07f06104ae7864bce281457e89ae1fb	\\xdb5ce0bed1557a07a4524965cf1f6b4a3ce729a3f166e0218b56f0e52c550a4e	\\x036ed24f8007cbacb30a7c2b1c4370318ae2a8a4356a38e65a4da873aeeb6c25188a05d286ef7fb5de6de6bbaae122d8cf854341391b8ba8d4487eab0ca11126
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
\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	payto://x-taler-bank/localhost/testuser-dhrp2zur	0	0	1601120374000000	1819453175000000
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
1	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	2	8	0	payto://x-taler-bank/localhost/testuser-dhrp2zur	exchange-account-1	1598701170000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xdfeee46c9869739452b6029ac00628258aaa5c7aa97993b910ae706eaa3eeec66bb2897458812a72e4099c77d9e6e2febc0af0d1f664e8d20e94bafc1b6683fc	\\x9b1f107f719abfce9fd4458fce91376237fd4555cab8dc3bd99b3a54fdd198871e05270db590762f21ea397f81021a87ef5dfa78c447c4f9ac3d4a245457a7c9	\\x0f26d4b88bee11332ab6911a19f1ef20d11efe838a6f82c535a63f8b7abf1371946f683b79a2f156c8bf32b14819d8ae60cefa8307f801446fd05b83095865f050152b637dd7080a3bb2b0e73a796c537e36a4c319e84b398906da63d36fda8da1c3d31816f24dc39a8efdec8e809f29427b6082e04878c27cc0043668ed47c1	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\xdb3d10c63d78bba11a0e81e04437aeece7ecf8ae05bd7c75024347eca41e287c912d8cc1ed1ddf2c1d738e574013b86c30af36f5af499a501bc74adf62a36c09	1598701171000000	5	1000000
2	\\x101be00ba433622ed1eef7ebad26e8186f54bdfe979aad83b3a63c259023e1ae38f29fc59117d5ad717bdcb8702029e44970df5f6c8aed438494d82930cd7c2e	\\x4b468e9a59d54f59c4f77077fa1c46298dbbe8670b5b5c123fb363db01317a0350760769c36dedc61c2ef65f86288e837c725b3f9ed18990e0288db11bbd81ed	\\x3008eccca61d8e5bd65863c40c3cd426b630a05c8fe390b38b204d0005bad1266370fd3d09e99ff1610a918a44e5c79e96b45351fddad5419118b0fa59b648bcb9d429f10d00e9d1b1df647246860424f7344e45bdc8e7fbc45efa3eea79bd370a8f2eb73bd506108feb9e75f2f0a8734b8f023f752020a65cf4cddf2e9d167d	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x80edcd647871c4b63d1f57bdc7fffe00e15dcd9093af3f2e9e079b86ec49217e825cab9f3caf42e01bb9b309e3caa216ac4697a18751b17ebe4bb95abac3670c	1598701171000000	2	3000000
3	\\x3dff4d3cc66e7ef3424cc58a379a25d71f84dd60542d0a08f89af74f45e51f87fff9b6c516cda7e1dd9afebe9a6739662a564902a1f879f75dd351604884595a	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\xc02f8ae3bbe8e93a91f1532c12c7ca6467eceed2edf062b3bc6e380f1ece7137191738ad3d20bea1d3b98938047fcbc4b96158571a807d2fa32343d9b0dfb9ed06fc09c20d7e52a55011ac18ebd754fcf3a74abe94c2258d7f232887e525c15f51531378179ab3b99173c081ec3aaca4edff556a3ab16db086ce08ba5d0fb8ef	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\xd034c5bf28974cf07d186f9bb69e5ad9abde7f540c6b747387380ca27b96423adb50a510784a2954fddca2356d5c2e07bdc3beb2dbfab188512d7ada990d8f0f	1598701171000000	0	11000000
4	\\xe95961dcd1c5f44b849cee7f7e4e23eb91eba920c26bb3e46461eeeb54708939bcae3700d1948d656e07d34c9acb4d591a6e24cba4474f507719c948c2565631	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x6ac3549457a41834f07a0d16f0dd0c0156aa1c9aa9d0790ac592002abdde89fd36cbbdc1b7fbc3814ff66de8296e7dc9c7161d05b13a72817adbcd2387e5aaa69927015871bcf436a37be3d32fa572513fd4bd8feeeb7cc21ab9f0def0cdefac00ce2c4ab634620d2ecc5c9c3e94eb48217a89c329e044f60e6052f0d850c8b9	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x314a2b69086f129e3280054fa8cf0c9f5e7f4ed77e36e441bc72681d4a8bd621023b90d6d8b3e1e51b4fbb6b2f09c58bca6ff4cc5745d1a5c932f2d904d67e09	1598701171000000	0	11000000
5	\\x2a511d17b471273331c925c3dd431c181880e850fcb36542d333850b353fdcbfd1feca93f8aa50c499bf88e86e33011ccaf0b4da067fa07097b125ff54dd4810	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\xa369803b080f8fad13d0f8b4a25275c5c6b51348fb1b1093f4fda69d6a846278d4b659f95ff9d6bbfa34175b72c0391769aa9fe8a98ab8165e6e1aaa73c7c64d9c3fe510098ba225d6016cc4d08d813ee5b52c3bce8e3444c3c18882d9f9bcaae66be74913b0d4bf4133c077d4cecc80eba078fe2b00fdaef8169736234c77e4	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x5cae26b9caa005377500d79b808cb802223db3e1b6e5567253b2e94f51bd00d8b8c76a1d87db15d6beae672a9a29be65827641ffd63d2be999a809ff927acd0a	1598701171000000	0	11000000
6	\\x27756131e01df72fbf80e25af2465936c7d92cc3c6276b9ac2f2b73a6cd3ec980ed9ee8753f15a9602da0a5b897a7f80472499bb94a658140b7049d7f198efe5	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x23855da0220ae5b92f9760fcb9b91b47323fc75624cafc8a2dc6ff815ff1550bcbb7ef8d965b454d74f4550c6b679ab37f5d6e8cbdc7e3fa18316eb4920fb14aad08986b699d0a64c3cbbd89307e4998b93fb70f2f7d92170bd3011c4454f6f0043bd034f6688ab8cce1f4de284f62e2dff2f63db4759dbb804b5fa11e3a9260	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x45af0e9926cc6ea9b120e7ff2aed4c83def7330d3ae4a799b797a423191c62bf42330b4775f336740b4a40ce6035f49d9f32047b9fa397975ef05d31dbcfa708	1598701171000000	0	11000000
7	\\x43e243bff0022cbd4a0d7f5a3551d59181e357bb66eabc113b6c3f992eb28667f4c88877d633ab8b552f91a150b4fd20a798b65b31767923a89c8bae1f2ed75a	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x090d01bdcf1834d95d6e49576f8320876a37a732edf585fb9f85c78c68aacc18d4e0c7d08958cbdab44f90b648ff5af45bfa80ae91c83a3394c75fd37a205068515ddb48cddf350a42c19de0386816d5400a972c4b6f14c1ac364bb91baddb73440cdf5a596363d8848943c53e61b8ba18350ad8942c081ac01e2a0e4d3ec5fa	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x245970a30c42f7573fc16ed24bef0f38544f47b99253deead843172f72beb15ab0dd4a5f53f258e0b0da00c4e5a049058f4f5940d480128cf645b326faf4270a	1598701171000000	0	11000000
8	\\x51873dbbbdf9e770e248c3a9f52426baec0b60db2fe6b22de8a2a282617c354723bb0b5df01a57986116f6b09bd3c3f05482d93a82d5c144fb0d38f095988bc8	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\xb997d2dd30ef8e680ed692391a467964d77ebdeac42f917c257cbb06e9d1150b4bf2a6ee358896ad4cfb56d804179e85901c921f8c09d1a8103ad265ac78fcde50d909b56fae558e8d9dd17aa3d875b9d373a5ed2eba497c2e203055c9e630fec0fcec9bfa073e531a87f77b60bc61b05dc9f796a76af634d16981cff2312b59	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x2a28fd9d4d6e46e564963b31e17e646221a89d01673b459b18d5d0abf07c898555036d57a815746e27833534c95707e57b95c1f2c3642a4f61a98747fea87104	1598701171000000	0	11000000
9	\\xe53af3f755ee53dd77a261a1710aa8a1c3a34dbeb2fca8673ccfc370b82311b1a34eb1eccec5617de6ff7c0863195b677f35e218e60d36d2622d1ee9f37ea909	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\xc65c52d7ce1652c23080c0ac0ab74ba976743c10abb4dea82c8b3deef03f4b3cff197e49183a26ed71305fd10007da0efc4c0f8e23ff621a92b87ac017710e7c1b7c71094046ef812f302fd6a401967e5d66310ca88c4ba17e45f1c64412a03bd7a8e471d1593d6abb16faf54880193c23f908c1de70e39eb765eb7634264b9a	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x76bbcce73cff82ee5813fc3bacb6903aa0e0d63de922305deabbd9556d4c274b9573b0b8fc7e135cc865dd02d2db067282af7339a4b13db6a39c4ca21ad2a40e	1598701171000000	0	11000000
10	\\x4db3dc588b1a1591a71a519c0724714b85d527291f930a2a7e54843150e7e5cbfac75c2b11d565232ee02ec5e3430cc024d966472fdedd87ba28a60ca66dffa3	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x3b1f9907d61feff8d192afc82476d6a3c20ce48090757cad0cceca7291a7ca06c007528b0720b2e4c71ff69d0b6d44db38e1b945689d8918499fee19f502c7b09056990983621935bf62d94d4abfef8a859434674fc9e701c0fe55cb83d18f81081c1e0efbc95607a62897a8f45dd914a32c62de6a094aa23497018f2c72f6b8	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\xf9958cb72a417a918e830c1ec0fe34a91ce6d98ffaaf2e333e18da7db967af60a8cd18b6c5ce6b7374696c9df9842559ba3894e91fb66e317806030293316504	1598701171000000	0	11000000
11	\\xff058305ef6dba7242a1d82b07ac00046442f6c5fdc720235288c6ab841899d35bee564afc4d054021c39831aa6d247b5499029ccba19632937d7b2d50a6bb59	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x5dcab82b9494ef2c67aa8b69302daef93754e2e5adb5a086208d87848438d618cc2e4e8c73c93147084f2e91e45810c541cab14d6fa4e508f587ea0b078af8c15104a9826961cec0f0b4ac90185ee922ea72ebf2e72d13f672967a74210b554424379efeed0aae9f9d7a991dc11e596152b5a9984a43c95f1bd2f89eee07e997	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x0e5b90ba6b416133b5e63fde3ab75272ebe465ea4b2c1975017fac113614a1e250fd87d94c353465994beb2ae7015b964a621078f9123715cf43c50c8621f202	1598701171000000	0	2000000
12	\\x6f2793a3b14032f5d7f36d61fd5ce81cf9e29513858f19f385ac1a50fb6080e8a66c2c31ad16ca52d4ecabb7d541f6397069db1e3a5e7ace2d7cf787f0650a1b	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x898875c9086fb39251f073d976a42cbf8a0944aa7c136e7f595d94b99d694e1020a3528915f63b315e54ac7533d4a9a5c3748f2fde4c9ddb2019a0afcec05f0864c03e394155d151c9bc5cd1581573003bc6b288a3d07e390c5abe9fdc95aadbedc93877f49f32184557a2f9dd10e00f66ce206fca9bd7512e9531c2171317b0	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x039c578c7344086d8f95faf4b22a9dcdacf64f4c80b57d257102a48e0c792f136adcb03c620677e03b019ca00444b14873f4042d3f02c98de808bf44f8160903	1598701171000000	0	2000000
13	\\xf0cfec0d2ec730240d96d53876b1e515c4b5e6810740c3fe5a8be074331d2ede61f3afe9e54f0b237946da53fe449b5d229136c6667e364104f3e672695a6c27	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x53862776960a682ee94d05f2489405ef1108f84a2b7bfd64d42fdd5e88ace22b66be912583911997cd5b5e597f61204f3186f843732b29bcf1850561a733d067a6c8693e4ba332902fefdb67b0d181db8d790ce11f796a5c4c9304faab4c66e4c46d3d175dbd13ec5fc623d7bb07e622bca56eee187ba561a36b2eaaa423a9d0	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\xf2a5996e685f902c50ff041756860470804cb8951bf0a037e3153c580b4e57829429c54abb3235abdd9605041f9c309c2a7f12d05b93c8e54d5d9d9ac3db3106	1598701171000000	0	2000000
14	\\x11a9ba30deb9f13d112b52fc2a9212521a5316df61fc831c24cbb3945045b6ce4af4e461b576bb62246a6b012a2d0a17235f56e3d797809dfafcec18b315b934	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x17f74c621b3c6f362a5b5fed9f7947041e762c74e90f9decd185b112cad3551ea97d42e93c8bf8423043ce46e65148bae5eda35c7b155b7822abc499db3e1b64949fbe25a568c114511e7712d697aef2fc6e9bd591b87f667fb961d846ee3051a053da9fe94f56f9f5585052fcc7ce773f50c62085c8159ce3166931af826254	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x781c80be62ab517c8f7d2b3a4788c18ce98f971bb1ab3105387f480b8c7ea55b239da010cfd19eb6af5b9714cd318fcdfd3e5683ce507d85f8c810a87f2f1304	1598701171000000	0	2000000
15	\\x1fe08eab1c36d2c9d3e7acc4dd26eb2d08519d5267fc8df088683342c02011b64499d1432a0ab10f165adc89ac47bb8e396e452a9e2c57d9ee2f40ab7c94ef9e	\\xd9b1658aa22170a31481fe95e0510fec987c8395597d011641837e8da25f4bf6d7723916b48c853f583cc20401ca9d806ce9f11542e808337ebaf5fcef31666f	\\x84355486e3cd05fa341551299f3634c87295dad1f1e5e178c8e02782ce1219f947619ee544928c23e200b0733bbf2c352bfac3179fc224f1919b7c02eb86311c7e85d5e7c8ac2e2a0cda15e15309fe264e8582fcfa1324a23351bc7a2332e3d8299022916a6edbac3e113a7c7e36e9a4824e052d5d4ad0105bf633389e86389a	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x5a7b791f4b482cf222faa43ea8f4bdc2842839243b3414d108cbec2ddb8f283e524d46d31d86dd2b8a5dedd67e2c49c6386c5a196b038751ea6b31c5c05a320c	1598701175000000	1	2000000
16	\\xdb664ed87b08469ae5ff5bb93038126de12442415bbdda20dcb6596a884ec025dcf6bfae2642d1ddc4c1bceb706d7eaadb7b7c5e828cd20d8acd542d42622ce8	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\xad7e267108f7037351d32ed4595aae04cb51cd502156df076f9c38b29650e5176bb3cc1ae6e64447261723489f478149d770f99d9989cc4a061f4d83f90a98efb79ff02662bd97c927eb99cfbab17d0f08a796d7fc6ad07bb0d5f31f9865eacc397a5f5b261f1c8c5b9e6d9b0db716b4df80afc3ecb7022c2e70c0192dcb8d54	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x428f5c411bf35f0febae8d41162dcfffb90855f98998c5f576a3160ec6a046751b4f9bfceabf4301b2e532ff75e6566ab6201e1067b7f76670abad147b7aad0d	1598701175000000	0	11000000
17	\\x891b437eb7a09047d9e5269124ed05757552c3e48509c3e4f42ec2b66904e4b4e97a491d2ad9ad1f0b07662b62b4395192e69b2ec303af01587ee5de1f2b6560	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x58801d25999c52c889f5854517dcd1f13eb33fd0c6f6716aafaa87cdbcfce6c3a7080cae43847a858c7b91185f4d52fe1f7dc12038777253d34a76e8027bdf7f7309313233f3aa9183cecb73f32d6484dbef17c903913848f17e53ac2e2dc93429f9edb9e1caae215766bfe09becdc6b8c35a763767bb33c39ccc3da7229b2bb	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\xd8ba09143cd043ad30943bbb9ecc62e1e7fe98e3ff4fff306820c7b7d0f6a02b8c11b02f53e9080059366ed86eda17455919dbebaadda24142ccd93490a6f904	1598701175000000	0	11000000
18	\\x7b513da1c82a516238ce367378e86f5847a712cb864ea1b5adc1f1f7f7887b90950800514c6ce0fbb6525ba9700373401be3f20185378890bb63b0e852abc245	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x6d1055b2c451a95076b0968a15d8aaf6905f3832d653f8ed1b6c73d0801bb708e11e8ebe5a95ab98eb7bc777763610930c268e0707587a1d22951389537c090ebc1fae4c506aa79d81206050142bf1fcf524804bba9ced0bdcec9180952e28f4a09d247efb391ef8be3227162fe35f2affe3814030c7ff65bbaf3c3bc43ceaf1	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\xf28b80b5ee25433312904f23e3f6cbde261f2624238863af337cec3dd8bda1b9db0b1ec775e34ec4aaae4d49087695d98f9ac3acfad7edbe4b6a80b82ae01205	1598701175000000	0	11000000
19	\\xca47c13adff21791e73d0fe75c61648654348aa7bc55de06cb770c352496da89236d555cc156165a271c4df88c12b877dd60d0271c81bb8ade10d14735febed0	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x4e9f18bae8f94206beb52bea92567248760678d9cfa9dd9a04403ec9252c2fb95f9cda530153a845986fac3c2c7d1bc39141f0795f3a638a7f4d83e0acc590fc8f5dd0409d4a0d0fb7c5d441c39a853f7f9ed115540d07ff874d05b614c0af333d852193e97229a4d39681ed8cc1f73f8f7b2bb0e521ab894935dfc983e11769	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x57e5b9cad3c990b81eaef027b4d64ae9282bb317279a7c9b4df1d7b562f3fa35dfbd3572679674d1eae2ee04e654b53a7dfec6a7bc8023b6e647d578cd606901	1598701175000000	0	11000000
20	\\x9128b56ba2ae58202c308930ee00395c59ff02f1267c2fecb0628d7e6f081b6e64a5e2c338687418294d7dc083b3022b71925af5b09b9d35b3f866a51be00e65	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x5298090036fd9f43eb5a621977bad07caffced1bd44a18ec6a6183c5fbc3cc6a58aaa3b62ddc84ee0b345f75cacbe8fb2f4a91982862fcb6e723849dcaf491978bdbe08602977a9c3edf0e688bc73c2145c95cea537c5a3be0090dcbdc9a6d62cfcc0d1ea1d78dd8cde585cae6d5c5fff7a92dba0e33b69713c685c2e7d19739	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x981c4dc1d0cfcc61764bb6535cbd6f9f6f30d10125066cc5c4466636ed6f547ffd2b6d8c5c9904052f1c1a5bad1b5718019f283ca546fe848627d055ac736404	1598701175000000	0	11000000
21	\\x65fbe5228c50f22f14e4c538b42fe3d814e87306ac44245091a82d38ff7fd5ff1f950686ef013c7fde0b50c81185d8a34eaa92471a4a2bfbccecb856e2194507	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\xb87b5af0fb8ded66571b398528fdc21f841888ef4ff2b7d65488961cb3c157033d83dc0286454aed605e95a7b30a8e8db280ab3add5d821ce59bf883161e4ff19064a658fc08dcef1a525ad51120260143ce11ba52ddf7c5f627709d538d75b586fcaa519f2e85cf532679d967df3ac7fa3abb5c381a3a66351b558d9c24853d	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x75dbe93f5bb1d47be03d2c9094ff6390c9832a0268e777b6a320f0231a84a9cb070a999df32b30d7bc6f936c4dbfa720a9c3606a167780273b15406d3877940b	1598701175000000	0	11000000
22	\\x0b00e8a4fc48c975e9eb9cd32961c0b424ec70fc36e9037ea41bb8c6ad7bce2b552003505a094b2e45cf26ef92045fb90215994b94f6ceda886490779bd4d7ce	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x53da22fca88d524891d68b5f535481e8d460903dd873df92c4aee743fdc49bf1743701bdcf6d7a08722c736703f0acd485b3ad0fbb417f799f9acf8835fe390ca659ee186c3a1fc0b02181da9a5abf9a7f3447c5af9b06e881f05fdc9e627c07cdedbf596030348ad79e4d5ff71e4ffbd1b21c6971392525d8014f7a9523cb29	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x7fa3d58ba792aa9654b344569fe3c127cb03e190cc015425fa77512c3bf033c99b2733a58c5d183995a1062639ba66bcfcdd63a3dc97c336cf59e1bf4a6db70e	1598701175000000	0	11000000
23	\\xbf6f250222e5f81a27ed787a14220407ce1c1affa9e8fa782636e8a8619974fcdb0f6da2b3da092cdf4349ffbeae39a1e47fdb3ad8ee0c8ff4f4f11d7c1ff94d	\\xbef691280e912809e8af950f95bee947cd5139b99b2894f891d746bf8e307915f6a8f8f1fcd08b3f7f3669ac6db21bb13f8de57aa06cb84c52a4a64cde70c567	\\x3c28f768707b18991fdf8497f04babd0672c4ea15537b3da969d993b3a70157973fc0f6281cccd72b562ff3445de98335d4bca6340660ab2540cce93836a0f1320a454b4f4a8ae8dd4da3e0c3ac550225ce59cdf1bb94cc2242d2c3d789985614ddbf3e59b5b96a0dbfdb9b0d98aa51b557aba59210b32f7157f31e62a5f47c7	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x188a4fa4fd104478ba75819d6f6fe3995b733a323d202b7a433523972909b168c2431bd360041e22904e6587ffe8edd190438417eddd7803e29197ef345ae002	1598701175000000	0	11000000
24	\\xac4177d3f6a83206e16a41ee4306a90ede91ba047beee8c29ef2237f97fd88ccae5e0f607719a384eb233fbed42de4dc64a3a8be47c5ce8d43ea32bbd25e6436	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x9589bfe8a389b081f8e140511549a1e604fd99f1565fb341ab47e3504114c1c2c54985a0594539105a8923feffa810117fedcb1c605e5144acff0917cb79fb07c4824cff84cef6403ca396520a534117922697784481213e3f3758f209bf5f0a312f84b476dd7c35d222caaa6cd8106cba7e1a7c254f772875051db6571f6c98	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\xd0af3ba21915b42254ec852c56092ccc494688eaa1e572e56bdb7cf4c3ac93355a5250ca1171da8d7013e1b0dd66725992f3b3070bca95eb957ad25db3f64505	1598701175000000	0	2000000
25	\\x4c349df592a991931a887739f523cd4d551dbb80c1f0f0f79fba0c31964fc744c301f645581da76a38db4ba44e3fd06a1e91c301bd4df171bbe03534c0b96c00	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x1f2a768e371c428387972f56f00040074de2efb071c1946c0311acc3eff425493bdac02891ad39be9136a5938e91c79c780e5d25e61e7031502ce5a9670fdaa9abd3cfa532a9cedca019fd5f8751c936e304d8aa7f1265472cc1d0d06a58457ca55a61c10258aa14127fdc388f6b72080386e383e267dabfae4fe0e6025263ed	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x56861f81aa65597a01505412bbbad47e53ac48c8be0d4e361a55865c1fcd75251745a98f02d4a9531a48fd316de7bab0cde3df3ab9cb3d7364333c367bc18106	1598701175000000	0	2000000
26	\\x364ff8e07a9600b186f53852f7d9d9925528fc397b5ddca5fa7b4f45d525f48e2470cb408fe27a783fb2531160f09564d513e6aa1d92c1a0dd06d9b7cd4f3802	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x9874389d8a9c3b40b1e2eeb83c4437128aacd54f44c5327d40352402ad1cb6c67b2064d41394360718b364ec416569d2aa07a8c609e0a985e88b4a0d3cc022713484694bfd53122892b55416e486fd8289f605b6140f7e5babb6cbde109955220a2800c695e07ea37ef5c8bcf1e02fb4753b52bcfe7112e352a0f70b32ce7c87	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\xa88b8bd6355d43bf54286f1435f277ac57117ea9b5b05a65efebe9315951beeae8e6f1aa34eb2a8ddd2ea13b5cb3e3cea64218b6bb11050b98ef3f0758d6520a	1598701175000000	0	2000000
27	\\x586a8c18672c2a386b34c00ab9c038134e4652d9afc120d10d8292ae84502f4971e8e32d457ca13eab2f14de465dc0b476f27ca170a0ffed075340fd2cc17727	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x59e3de7c37d23ff219b66b06c33087a60904ff53ef92efa5ac16839bde9fbc1f8e25cbefed5796be0e8695e94cc79301568c1fb73af158d9ddaffdc63b6b866298222ec323b196de0943cef951f7420fa6fb3559c264e40144617d955cb9d2bd1760aad019b38541966b58c49da5eed9bafa5d88abdd30ea83a201a72abab0b6	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x2326e874fcb63e5abedca981d4fe2e22f578e13e51242e0c768985fceb8f8ab2856eb32cb3ef84adb14b07948611bfab9fc83c831611ceac7da8f14336715a08	1598701175000000	0	2000000
28	\\xbb756fc7b1a574d63ba1ee8c0989be3d2b6a3a48a390bddf9e731b5ad462574d87d8cfe13011d6afc9907adf35c60b9c6e9f9b7ac96ee61a36d4ed689235bb99	\\x7693710f6836d4904d718c08590053e2c4f0f8b5c094e30e38523dc87d3ba8741f77214326d93062ac2fe8bd61fafcf76b4291e538d07932cea712a4877f05ed	\\x4d9d4293b60ee0c7f11ccd59c32636a3e0e4498099ff43ad7702bcab8ac7755c1cf300ffc72df57536bbde905ee0bb078cc8d76cd1fb18e5f74dfa116bafbc8f7f81a3083bd7e44ad3956ad777499cc308af8cc4cab84fda37d453aa54885cf4fbe50c49cdc50baf6084470a6a6da2705b06fbdd76c6bb49494affe4e5679be2	\\xd7be4f9ece8d04393a432783ede2903c7048556313d9bcf62b33f10a6bd84f2d	\\x2b7292f10df81f4ae1a8c2a0ca53545df14d92bb0660bf815a32bf7ea533e3573dea695189c345dc5b77a95a1077ec9cb03586c6c4f8ad8bb7c62eb9cb6b0d06	1598701175000000	0	2000000
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

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 2, true);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 2, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 15, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 2, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 4, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 8, true);


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

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 2, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_refund_serial_seq', 1, false);


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

SELECT pg_catalog.setval('public.recoup_recoup_uuid_seq', 1, true);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 9, true);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 3, true);


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

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 28, true);


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

