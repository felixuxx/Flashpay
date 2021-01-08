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
-- Name: auditor_denom_sigs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_denom_sigs (
    auditor_denom_serial bigint NOT NULL,
    auditor_uuid bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    auditor_sig bytea,
    CONSTRAINT auditor_denom_sigs_auditor_sig_check CHECK ((length(auditor_sig) = 64))
);


--
-- Name: TABLE auditor_denom_sigs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denom_sigs IS 'Table with auditor signatures on exchange denomination keys.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_uuid IS 'Identifies the auditor.';


--
-- Name: COLUMN auditor_denom_sigs.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.denominations_serial IS 'Denomination the signature is for.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_sig IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditor_denom_sigs_auditor_denom_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditor_denom_sigs_auditor_denom_serial_seq OWNED BY public.auditor_denom_sigs.auditor_denom_serial;


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
    recoup_loss_frac integer NOT NULL,
    CONSTRAINT auditor_denomination_pending_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
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
-- Name: auditors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditors (
    auditor_uuid bigint NOT NULL,
    auditor_pub bytea NOT NULL,
    auditor_name character varying NOT NULL,
    auditor_url character varying NOT NULL,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT auditors_auditor_pub_check CHECK ((length(auditor_pub) = 32))
);


--
-- Name: TABLE auditors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditors IS 'Table with auditors the exchange uses or has used in the past. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN auditors.auditor_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.auditor_pub IS 'Public key of the auditor.';


--
-- Name: COLUMN auditors.auditor_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.auditor_url IS 'The base URL of the auditor.';


--
-- Name: COLUMN auditors.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.is_active IS 'true if we are currently supporting the use of this auditor.';


--
-- Name: COLUMN auditors.last_change; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditors_auditor_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditors_auditor_uuid_seq OWNED BY public.auditors.auditor_uuid;


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
    master_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
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
    denominations_serial bigint NOT NULL,
    CONSTRAINT denominations_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64)),
    CONSTRAINT denominations_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT denominations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE denominations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denominations IS 'Main denominations table. All the valid denominations the exchange knows about.';


--
-- Name: COLUMN denominations.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.denominations_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.denominations_denominations_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.denominations_denominations_serial_seq OWNED BY public.denominations.denominations_serial;


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
    known_coin_id bigint NOT NULL,
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
-- Name: exchange_sign_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_sign_keys (
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
-- Name: TABLE exchange_sign_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.exchange_sign_keys IS 'Table with master public key signatures on exchange online signing keys.';


--
-- Name: COLUMN exchange_sign_keys.exchange_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.exchange_pub IS 'Public online signing key of the exchange.';


--
-- Name: COLUMN exchange_sign_keys.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.master_sig IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';


--
-- Name: COLUMN exchange_sign_keys.valid_from; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.valid_from IS 'Time when this online signing key will first be used to sign messages.';


--
-- Name: COLUMN exchange_sign_keys.expire_sign; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.expire_sign IS 'Time when this online signing key will no longer be used to sign.';


--
-- Name: COLUMN exchange_sign_keys.expire_legal; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.expire_legal IS 'Time when this online signing key legally expires.';


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.exchange_sign_keys_esk_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.exchange_sign_keys_esk_serial_seq OWNED BY public.exchange_sign_keys.esk_serial;


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    known_coin_id bigint NOT NULL,
    coin_pub bytea NOT NULL,
    denom_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
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
    fulfillment_url character varying,
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

COMMENT ON COLUMN public.merchant_contract_terms.fulfillment_url IS 'also included in contract_terms, but we need it here to SELECT on it during repurchase detection; can be NULL if the contract has no fulfillment URL';


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
    h_post_data bytea NOT NULL,
    pay_deadline bigint NOT NULL,
    creation_time bigint NOT NULL,
    contract_terms bytea NOT NULL,
    CONSTRAINT merchant_orders_claim_token_check CHECK ((length(claim_token) = 16)),
    CONSTRAINT merchant_orders_h_post_data_check CHECK ((length(h_post_data) = 64))
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
-- Name: COLUMN merchant_orders.h_post_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.h_post_data IS 'Hash of the POST request that created this order, for idempotency checks';


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
    buf bytea NOT NULL,
    failed boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE prewire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.prewire IS 'pre-commit data for wire transfers we are about to execute';


--
-- Name: COLUMN prewire.finished; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.finished IS 'set to TRUE once bank confirmed receiving the wire transfer request';


--
-- Name: COLUMN prewire.buf; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.buf IS 'serialized data to send to the bank to execute the wire transfer';


--
-- Name: COLUMN prewire.failed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.failed IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';


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
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    known_coin_id bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: TABLE recoup; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup IS 'Information about recoups that were executed';


--
-- Name: COLUMN recoup.reserve_out_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.reserve_out_serial_id IS 'Identifies the h_blind_ev of the recouped coin.';


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
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    known_coin_id bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: COLUMN recoup_refresh.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.rrc_serial IS 'Identifies the h_blind_ev of the recouped coin (as h_coin_ev).';


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
    old_coin_sig bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    noreveal_index integer NOT NULL,
    old_known_coin_id bigint NOT NULL,
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
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    rrc_serial bigint NOT NULL,
    denominations_serial bigint NOT NULL,
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
-- Name: COLUMN refresh_revealed_coins.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.rrc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refresh_revealed_coins_rrc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refresh_revealed_coins_rrc_serial_seq OWNED BY public.refresh_revealed_coins.rrc_serial;


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys (
    rc bytea NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    rtc_serial bigint NOT NULL,
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
-- Name: COLUMN refresh_transfer_keys.rtc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.rtc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refresh_transfer_keys_rtc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refresh_transfer_keys_rtc_serial_seq OWNED BY public.refresh_transfer_keys.rtc_serial;


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds (
    refund_serial_id bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    merchant_sig bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    known_coin_id bigint NOT NULL,
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
    reserve_uuid bigint NOT NULL,
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
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    receiver_account text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    reserve_uuid bigint NOT NULL,
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
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    sender_account_details text NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL,
    reserve_uuid bigint NOT NULL
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
    denom_sig bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    reserve_uuid bigint NOT NULL,
    denominations_serial bigint NOT NULL,
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
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserves_reserve_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserves_reserve_uuid_seq OWNED BY public.reserves.reserve_uuid;


--
-- Name: signkey_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signkey_revocations (
    signkey_revocations_serial_id bigint NOT NULL,
    esk_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT signkey_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE signkey_revocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.signkey_revocations IS 'remembering which online signing keys have been revoked';


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.signkey_revocations_signkey_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.signkey_revocations_signkey_revocations_serial_id_seq OWNED BY public.signkey_revocations.signkey_revocations_serial_id;


--
-- Name: wire_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_accounts (
    payto_uri character varying NOT NULL,
    master_sig bytea,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT wire_accounts_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_accounts IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN wire_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the exchange.';


--
-- Name: COLUMN wire_accounts.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';


--
-- Name: COLUMN wire_accounts.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.is_active IS 'true if we are currently supporting the use of this account.';


--
-- Name: COLUMN wire_accounts.last_change; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


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
    wire_fee_serial bigint NOT NULL,
    CONSTRAINT wire_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_fee IS 'list of the wire fees of this exchange, by date';


--
-- Name: COLUMN wire_fee.wire_fee_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_fee.wire_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wire_fee_wire_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wire_fee_wire_fee_serial_seq OWNED BY public.wire_fee.wire_fee_serial;


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
-- Name: auditor_denom_sigs auditor_denom_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs ALTER COLUMN auditor_denom_serial SET DEFAULT nextval('public.auditor_denom_sigs_auditor_denom_serial_seq'::regclass);


--
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


--
-- Name: auditors auditor_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors ALTER COLUMN auditor_uuid SET DEFAULT nextval('public.auditors_auditor_uuid_seq'::regclass);


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
-- Name: denominations denominations_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations ALTER COLUMN denominations_serial SET DEFAULT nextval('public.denominations_denominations_serial_seq'::regclass);


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
-- Name: exchange_sign_keys esk_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys ALTER COLUMN esk_serial SET DEFAULT nextval('public.exchange_sign_keys_esk_serial_seq'::regclass);


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
-- Name: refresh_revealed_coins rrc_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins ALTER COLUMN rrc_serial SET DEFAULT nextval('public.refresh_revealed_coins_rrc_serial_seq'::regclass);


--
-- Name: refresh_transfer_keys rtc_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys ALTER COLUMN rtc_serial SET DEFAULT nextval('public.refresh_transfer_keys_rtc_serial_seq'::regclass);


--
-- Name: refunds refund_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds ALTER COLUMN refund_serial_id SET DEFAULT nextval('public.refunds_refund_serial_id_seq'::regclass);


--
-- Name: reserves reserve_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves ALTER COLUMN reserve_uuid SET DEFAULT nextval('public.reserves_reserve_uuid_seq'::regclass);


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
-- Name: signkey_revocations signkey_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations ALTER COLUMN signkey_revocations_serial_id SET DEFAULT nextval('public.signkey_revocations_signkey_revocations_serial_id_seq'::regclass);


--
-- Name: wire_fee wire_fee_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee ALTER COLUMN wire_fee_serial SET DEFAULT nextval('public.wire_fee_wire_fee_serial_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2021-01-08 20:43:26.498492+01	grothoff	{}	{}
exchange-0002	2021-01-08 20:43:26.613171+01	grothoff	{}	{}
merchant-0001	2021-01-08 20:43:26.842378+01	grothoff	{}	{}
auditor-0001	2021-01-08 20:43:26.979713+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-08 20:43:34.514875+01	f	2dbe2db3-05f9-4afe-b03f-5dbe30b45ccc	11	1
2	TESTKUDOS:10	Q7K7Q288BDQPKNK3AYYN8ESYWEB132EM7CSGQ67BZE0R19XPCA2G	2021-01-08 20:43:50.597747+01	f	d38496e3-82f3-4aea-b90a-f380d859215c	2	11
3	TESTKUDOS:100	Joining bonus	2021-01-08 20:43:54.275817+01	f	e89421ef-41ca-4101-8b08-6a9a82a789ea	12	1
4	TESTKUDOS:18	TC9TWQHHYQCBMKQR8Q9D1SZA50GT25ZXYNRDY3Z7V2PE7Z7FXQ6G	2021-01-08 20:43:54.946333+01	f	2940d480-1299-40fd-a698-17d7ce278b7f	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
e6682191-b84e-4c96-986f-260d5822a1b4	TESTKUDOS:10	t	t	f	Q7K7Q288BDQPKNK3AYYN8ESYWEB132EM7CSGQ67BZE0R19XPCA2G	2	11
ed9ed251-b694-450e-ad7f-cac846d674e7	TESTKUDOS:18	t	t	f	TC9TWQHHYQCBMKQR8Q9D1SZA50GT25ZXYNRDY3Z7V2PE7Z7FXQ6G	2	12
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	65	\\xdc75ddcab421fea8b4d8492b39dd54bd08cb6e125411d4c9363c8c12916b4f887304642a617f15991cccf06588a1d7c3a721b52e5dbe17209177734296a38f0a
2	1	26	\\x9b24638551dae9915e2af821e0103c9c86c980b5b845a0b0fef870cf8eebbd613f1e4f8e9244c6f04b574ed9542a371c15e54bc8c0981570021bd4ec5fe61f04
3	1	235	\\xfc4f0a175fbd20d3bab4d65c755c1e9e3020466b2122effb31a631133f3f9870e47bab4d79a4559e0e25cab11cd0c785afc7f5f1b38bcd418db87f3b5e980703
4	1	170	\\xe98e314c8fdacd0a4cf9343ab598579aec57859fa8ad81c54c1d297f21bd98d21fb1e844080e4d96adf58c9d93d9d5f97c80eba5ff3c10f1f291e1e4a1c90706
5	1	150	\\x05126a4df1e6f18bcbd992a58b53b0d709686596cdd88c11dc8e43feac1147fc6128a2d875498e148e466ca6146abddf8b779d110e8be84881710dfc14a1b00a
6	1	334	\\xc3e7b026750801ac52938c6e4ca89b1f1865208a3dc26984cf1deec26891529f159378a58249d06f4db12ec0d48ec7ca03c5721e271e453720c5d9353b401709
7	1	112	\\xb4dcbee481117a070f6750380d4a3be80e477154e39169e18b82903487358932a983f31367b6916f929f2b55d6bf718fae2a6bc18384305f10784481cc9e2402
8	1	351	\\x851198c8a0114310a7050f59ec6b8af29ba3a34de83ee903898cf9cfa7560a3efde8d0f499e6e80a22735f70d2bb3bd49f77277d4cf3246a1406f5dccb4b9109
9	1	88	\\xc9aab202543db11ab7fd584ad4a84b99b3ab9f3c8de342d1c9bc8e7143551e707d5e3f0a6791ae43648b5c48162513c6754fe89ab4901059b87185fe9e615802
10	1	411	\\xf662078803736ee207137b3a1e1ea9ba3fa9f7baf9f7e61a118cb45b13160b246881b2cf3c3aecb56748eb5d1337a06891bf6791608d2ca46e36120fa1e0ce0e
11	1	24	\\xbeec24c25b2d2194a4d6ae9b8ba8a5229ffe9c77e4525039243f7eb8ebd29f64baae1ab3f1c6f0c4f0bbcbffea7f84274c5bfae75005bf34a925e3dc209e7008
12	1	118	\\x72a959e39c1445288fa1d8622abb3b125b93b81cebeb491e60d2809708d1ff7e96895f69a4c181b5872d47236efcb9659c4d58f39003b0d9b22115c5ed5fbf06
13	1	123	\\x4f8b7e69f31f7fc899d53a4616e5bd11dd1fcd46adee03814db581114088f802fbcbc8f53d6cc113463bea2a73d4f3963034ce80a20c21e25cbf8211c19e3f07
14	1	348	\\x900ed1b8001e31a1d1b53b9ddd682e1e9b32580ce68652a5e44598c07aaa2d80aac6709cca987d5297ecc1f9e37ff94a223997c7d6bfdf1d68b643614920ee0f
15	1	226	\\x304cb79d0b74d0c6dcf94b933cf0939184828f399d10ea5d6f4604c226a88380d4c8c75afe155e4b83545355106fa6fd66076d2f4c7b0890198316cd8a25f208
16	1	401	\\x302cbfc8e972c4f85b9a592a3739e9fcf73aa9985ede08b273febb8685cd8bee292d03ac583e48ef5f9fdff7a0fdd9e511d04dd9476efabdeb74626200197703
17	1	211	\\x2b8eaf37ee36f6054c7e05f6eb4ac18a844b7b7bacffd10ec4ec14c303772cc4a0ea160bf5859dbe0312ce9dcf94b12fc43e96573c552ee6aef639e547119e01
18	1	375	\\x34fa5370e0c5309ace53ef5fe2313fd8c3f770f32a5ddff0d6d6b29e1571c731b9dd21ddc80d89910eabf9c45964b8c6948f8d0bbddfc78d1ba6f7a29a7baa0f
19	1	236	\\x6d166209c396083c9f1cb9edf0b079d92eaa0fa09441304cf9668739ad1c936604ce0c525cf1cbbbb080181bbfef3fadd8f8e73957f849ff929db21f72e64608
20	1	86	\\x2249993adfc983f4f881830aba3834f0b4b41a1d2b430eadc0e84a3eb62dfdb53249cf52b8be3ef5a3f7ca2493978ed954785c848d70dfaeb0c91528786b480b
21	1	195	\\xafe9a2d68470f2e3f24e2a1c7aa22010332c3290beb14b9bf68f42e54448a8a36762dff5744343400458c0c0f1a211dc50c3e7269df0074e2697bf2ee7cfd405
22	1	208	\\xda0494b48f912326c307b1332e3f048924d0cb5f159f366c14dbb9ccc3f16e76ee3883a4740f28f38a8cec0ff945e48a7a2112caa7f33d3ae3bba5c633c44f0f
23	1	193	\\x4a4364916db8591a4241339cbc3c5bc688cd6e6f3b5d2c5897845548a239606871a4d5553be5ac0b41caf9d3c1692abb3264d1332dd6c80857cb79222ba76a0c
24	1	91	\\x2793e8c7a3a7e02f7423dc503199172bdf8a36e5e1e7efe0fd72978a0c0b80dbd7853f64a20edc2ac150a4cdeac0d30f8c233339d2179eb121b4fd62aa153305
25	1	408	\\x592c337f49022b21052b32da34ac9706c5029f7f80299db6ccdcd63b96890e3fce838863afa3e21e766174509c124d869b33b5db7a4b4b3bf075ae1bdd6fc50d
26	1	209	\\x1df622e621f978ff007023949944fd90bc40383dc0c1175f1d90dfb62c78c87c03d16ca705cd782a71277c1e4efc9c15472741ece762ddd52fd283a87f22ae0d
27	1	350	\\x3e34e9bd690d569030b73e27a4f180da096db5bcc2ed45a5c4d67421312bd51687c5748f7cf6a65cf17bf1424364cc0559f0067e0cb849c6e6edfa65955cab00
28	1	101	\\x1629c5faa66bdecc93791553e7298c61e424dffa5a717d6cbccd974ff1c8132e7bf8c8a21a379a569de3ad6e3d29b44b031dc8dbf8097960686c62e9e7fa9206
29	1	369	\\xe55ed7872553939de7fdc1292b2369809269024a6c094c5fd0cec3e741b483218162f9c70369bbd83088957a385a3b37a3ca0ff104c28381b272a2f454f5630e
30	1	143	\\xf166c14a0b61873e43f88475b1af3700e289bb074e54f4e66519d27345c610b3fe4c641c0fe9af0288d86444ad4b7f210cb5dfb0f0a1eac44b65cdf9dd21370c
31	1	291	\\x3c69d77f4abb406c62421270bdb126c9efaedfb71c4cabeab7a5cb28da1a7fa42615e218149899ba627a218215c1f791f3024f7fe069820ff2359d401fddfe06
32	1	368	\\x3523222ff761aa5ba055e0980164af4facae61044a2efd24802261c4d54b0e6e9857c51a4a933e90bd26242e4b139f6be3af535a431f6a8a25e3959a62ef780f
34	1	251	\\x6c6684ce9c1117f483da9ef59b4626826c25ab887da896e255770af26ff75a183fd6edb793197d605477da90b6541b7f77b1beee62b41a258a472df4011ea206
33	1	360	\\xdc38181b229277e4c9c4e42ba0ed50e985880f94a4a2927a427fd6c38866e503ba882b1bce680e9eb673531a26baaecf314581197e9cea96b3ed1d9d928cf806
35	1	144	\\xe907f27f367302e803b3f512d70c8f1f2eb241fee936681b64bb3aca6a0e0852a167fe427b6df7b26a96c83d65a1e679e00580f66423e96fcce327e102469101
36	1	413	\\xa7dfdbcef1648fd3d7b37338843082283e388c171c38149d600e6b0b1454b96d8240cb713bd471b9ef73ea03ba79d4bd848003f0f02404c8eb800a51f75adc02
37	1	81	\\xa341f7790885dae49e0b55951fbd1b9590c0f88920b3d4e8f42fa02c4e79e71c5b3d8932b276e063f2fbd81bf910ea5ffab7be51db08dbf0ac4b665fcd70970b
38	1	366	\\x7f1ebf80f2b448b50a7575914012c49c5bf445d306ef4a72347b007f2ca2442051ee855acb4506fb41e1023a83061af6aa4adbe354d800d8207aae180b755308
39	1	102	\\x007c4483b2cb64bfe97b78fc3f997881372095945289b72303f51b24f88d7315e789362e484c28de41ec332cc0a2f34225e50efeac2cc86f6f49ba8832e5b50e
40	1	147	\\x56a031f34ec04519540526a0cf3682abe666711102363bb666b827a6b97c67ecac35854893510d4ae3b4cec86b5dc75097fb0b7e56b5bb8befff0de478002c06
41	1	77	\\x14be9077adc950264fd1de375b6ca4981f479ccd46aa966bf783eb019fa7b97d946c878b4675683f208e6e477c9045b1030f2a6a76591dc3ebf2bb4c967b9b09
42	1	392	\\xc5eb5096b4b24850133765e4c5d0962399117da69a4cd074888d13a42a632c81ce0c10c1e6071b6195e312c45cf6f781fa2a6a78b1778495fa16a06755351a00
43	1	84	\\x429788ec29255c494f5a9fe5d941f26d5c0557f2ac2e73cf68c4b2c3a37ce2c4ca4c8c5ccdca95b257dfebeaf95cacd6c4ebbff2c7b6b8d7f42c76c0183a370f
44	1	62	\\x7c0e305a808de64cf8068e9c383fd7e08065bab6f4d6f6f05fc0384ac4af1be7d7450665ca2f0f595b0ae9162036c39ffb521a5f91dc41fb8bab1891056ec40e
45	1	423	\\xf5af1400b253810871dddc2ab506abfcaffe0eab43b3e6aa9b04093569ad0c367e5b7d4bec9c01baf45ef50e376e470bee117818f9b5695bcec0cdb70ec37f08
46	1	154	\\xf37fb4d89dbab9fe0df63388967e384aca1ca835da6641f8d6c8559fa12e1e134a1fba905b0c75e10d367bec9f387bab797b22d8b3c9b1ea140e004a2a8e1005
47	1	117	\\x8d5e4e835721f2658f0c523c5fc187cb8c90eb576195c8cb5f372f2e5306415c42fdc48cd1ef9fae9314fa400a8747bb8c5fe6ccabb850f80bd23db219a5180c
48	1	200	\\x84a8e6ec23616e9b10f12590f7f1fb6ab81aea42182a3ed2637090740ffd640a3cf1df301237f5867f76f055f82f6944d360b10dcaae4eeab04a25072dbf2e0c
49	1	342	\\xe411dcb84194e9cac6ae75207b284a532d0880ec5a055bbacc64d7a06c2f4d56ce309c0fe57e18b3fd119bd75f7c72c876a46c8556fa5e9e03076a9316971503
50	1	93	\\xcdcbcbc8071c2f9c6801cc193217acf207a36fde8ff10259b747a84219a0c2fe84ab0c7c43b000c481d0e52529b2f80f5b777dbb98815ba8072b3645bf40da03
51	1	192	\\xc0c5e38d938ec5bf585ed98d07ddab9229a73bd6938f20700adabd864b57793bf4973eac8cf06937b903e47dd47995db329c987b7df13a42f914541d0c5c610a
52	1	264	\\x3cebaabec9364171feb557ed3e4e55932748dd3f8b06e34f360388607595ab7cd2e2e641dec921507617d1d6918f50add5a131b7ff6b11dd973135a8da8f510a
53	1	156	\\x8426dbff075fc09d49806d30a13adff9f4fdace40d6fc514f5100c7325a46b4e3781a9a26864c1a57f54b335def7a8b189347142df69a4c2f434ed4613aea10a
54	1	223	\\x188dc629c53d135e8f50c2d0b011e17ad2f98822cf289f2171a50db56a227d7b339daacfbc94848dd38d616d5a7eff686e3fda5f78d112678f5c3597ea4c2e05
55	1	296	\\x2fb7787ea2b0b88709f6c0ab09e632426f84382038977c62351602eea4ee098769a7ad7d74f48f36c9aade8101f0ec3c3a2cca0baa5340f131fd92792dfe3503
56	1	140	\\x9e536c1638ec36b7c1cccd5c75d81a7373af6f9622579c5204f15973ed20eaf72a0934a1e301969ae13ad4515a5a5b191e2cbda21143676fd7029eae4dbfd70d
57	1	257	\\x901e7617e2edb3bfe20ef4765a2844d7be2a17fb4bb795d43802ebfb046174610f7b1509d96c10d0f36ad7d443c9e62b46dfb1589ee56c08148aab3f1f5a450d
58	1	212	\\x1f24973da12fbf9807cb7ecf4ac053cfca5b15c863bd2b52bec77dcc50bccc448419ddae26edce71b3e4409ead0bd3ba15ed53223e624b23f305942ca96c0d0b
59	1	390	\\x7067ee27c97ba8a083be3a312e9759fad842c0cce92dba72a8f58fc7a0f1c326f43c5616047fd03f18454221f3ff27ce07519818a90297eb9d270e5205555406
60	1	353	\\xa6a964d432cef83427a0014f5b16ae643a1b3095ac46da57ded8c6e7693dc5962dea013eeb7862ce0c2281da66448019e08d2100fff867ac43a3a6973b0bfd0e
61	1	313	\\xa8d3926018056bfb3b93ac0c05265d1a9a0a48952d2dda833e2073ff9a80fee5b8ebb3ad62270e08c8da7325e22c7fb51a00db96b0310c6980284876a53b7f0e
62	1	119	\\x725e011df39ddc36cd912df59a8c0401dae582136e3498c1a0a017d6edf7114ea81775bf03b68dd68fb71492fa32a7a9cc5e6888f5e4c16da4954393dd85e10b
63	1	228	\\x8296a4ca8529ab5b5e3f37af3e7498512042f86b66e786b1253f3ee77ff4e559cb3751cdf7dbd384c126257850ea7c5780d2060df8b1bf9547d2c317bdcfbf03
64	1	23	\\x08c2c9fcc55f6862b05e79c3bba10689f8b777a31634bf4db8c3baf2152f18190121fd9559f9d40eb84818ee38468bfbb38568075a045d00579bc24284706c0e
65	1	115	\\xfafea68f27f23cb050de1fc9c58c26cf6ff7050720e5972d616a4d0ab5ba165d6127a47fed5adf0c85ba3aedcd17bdbcd433bc130ff0165db6f6de6a5fd85102
69	1	83	\\x740aae4f711d895d813c7718afbd6967324f525fb97f8c10342c5844cd7b9ca21194a64a81716ec3e42ef4d0de5374b6913baaa3175722d0f6c2559abfef650e
75	1	219	\\x90194ae76e04875f633919ae56030670d28de2e280d77b58c786bd011b1de4b6e75d81e3a5031a8d35eadc608534fc38778e1aab1d6a8b5f408b3a6947b4b209
80	1	198	\\xb0bf09ea238c0715427e077842d01cb2ce38505cce2ef5dbf5489b310c47dc74380d922b7f451749c7902294cc99f93a5bdb25f70a36080f07df3af451fffd0e
86	1	262	\\xa926f37bddd52f405ddabd55c60e4e06ad84314350539ca64cceed436210a028a1064c2d00458a476ddf7215099a9556b7c7bcb0bbbacd0d56841848b9b70a0f
101	1	152	\\x82cc0cf94959106c85fc20a5b8d5a1c1eeeb98437b565509441147226542eaa75d79ad64c2ac7af139bb60444afdfd6e1df3193ed8aaace0fab0529da4c8ab08
108	1	311	\\xc49330f5737129b5729e9de9211cbcc43d2a8e6a5bd0a97da2efaa24e2b9aba2e4fe49c0cdde717f96a03fe69d2df9eb38c2d3cbc32e6e673cc908ef301fae0b
115	1	190	\\x06202a11ab07a167a6dff9a24501cb6f947af937b47b6ee6b70adac433df9336046bf767dea8b6141a95e24f9d7800bbe25b77323c8c994fb0f74ac7fa466308
126	1	165	\\x5fc21da664226aff683ec55e343a086de8d07b00bc9a707a19c9e66fbaa9bf78a842aef56e79eb65e0de125a2cb2dc3cdf27fc173dbdd48622386dea88f3b70c
131	1	302	\\x490d377f8ed700d4402cec1f06239c2536ac87951f489bf77e739ef041f2324309f706e17b7df9776c9b15e6be1e998acb9a46311d005cbf76f182d520441809
135	1	45	\\x7ecd0fc060f11973c6fa8391a0b3a37fd6ab6b0b5682033550c9ab9f57b812afa7614423e8f45142816a0279371cf19d7d8797deb84c3639c53b5915f9c9be04
167	1	371	\\x0eeddc2f4ea0ff27eb7430e5036d916803a2196d7e47e801339edff180e765a7bd939017a7f6e71e58160ad856b79e8b74bbb40202acf2b57c047e98b50e140e
188	1	295	\\x783c01d9ba0ea17da13f066950e51dda34800eab4c1b2768f82febf40109e8fef1cb67deb24889d2b7be734cfc5156dec51b5d1a41e6fc3f985f8ba0e73e2706
214	1	153	\\x4e7b54322c33611c6893100a920b1dc8a897d78e1b9d31edd73d9456f43ad363967c06620e0076245dec8b26cdc1400fe1380ff8ea9ade7ff367b63d6e400200
242	1	388	\\xb9942307e9b85e6f27f1f58e1cadcc16f8c21b4e79e23d22fa5aa60788a6a8d9754d7c86df28887b816494cdba78134c88dcf596d32a128ab48dd3c081d3b20b
266	1	354	\\x285803ee9fa70cd5d83582d905cfebcaa85170941baa3500de8f1e90edcce972aea1516c5f2aafd50b534b2576bdd527239a156d6a5f4872b33a6d6711bc0e0b
282	1	297	\\xf52b53296a550207072f4ef4e076ad1b5835c6ac74e81cb7d7f69fb22f3d1f9f08eeb0878082ed81ad3ef140f1948c7a0a66be7fe6d5c94ce5eac627697f4607
309	1	323	\\x82b60906030c83e6dc06ef448e00800bd3420b9a3a4c765fbebc22014e74e455adbddcf7d6cbb7d5847f0ce1d8031a6d068f2f8ea7fc2a6ede0d8f8f411f7d04
360	1	417	\\x6dcbdd7e9d63d515ca845f8d4e1983057a172aece1abc9289f8e589728510335a5b762050ac1a7884b9628465ec1da25308f0a4f9b556527de168a4032c03e06
395	1	30	\\x28fb3e1d978a9393d744965d1671ac4e20186f60f42b678c352643e10574819c19e6ff560f623212833dfe7a5f04fce1604c0d865f43caea39ba9c206f4f9c0d
68	1	79	\\xce8c23ff8aebfcb74d7ff5d5db7ef856e11161223cbc16b6ae60c3a07b00ee2338e858f227467ee947448eb215dbff3f56c4b989f07486912ec34b0f695db607
74	1	203	\\x1f57cd20399cfe58c14959eef1e141aa633ba5ec86dfcf38b84146c6bb30e9d94c7b658868b42f084210717f5a6c46a08b5e20a5c6a5b8c87e8751b2eb0fdb0d
87	1	92	\\xf566e0e39842b227c057d47f44ec2150ab3ba7e3512681ce0a73449188af6baffa1074dbf5adcb9d2e2bad430c6cae8c4c9f875e9fe84b13364942b465eaf803
96	1	395	\\xa8211fa5835bfb774c90c439addb97f5803e36012fb8bf77478b0a39d2f0f82774cc798e7718482d45436e4ad090508187b5be98dcf73ce6a05ce97524b69609
105	1	10	\\x8dd76365501608056778ace7ab169f13f09819f9977fc57f51b033bc25bd7317c524bf16b5c34d143dcd9104837862e73de773e0dd782810e64717bfc75f9808
113	1	367	\\x0f30740aff122cf44df40b99f7fd8d4339bab1a109342c60275ee2efa3d881b0add7997223487dd6d81aa5097c4b82ebd1e8a2a7891a5b8c28b421dc42e71209
120	1	167	\\x20adc5d56a6e509a230034ca27d80b3d9a8101939e54e1ed768297349f7694e13126a313f5c059aaf0b203789b4d84956e6d8d928e93dc7a15119b26d6765a03
130	1	163	\\x29287ddeec9ebd6b2815e9863e51ca9331e81ccc8b93156361f19c577b60c57cc59a112850e3fe442c0d98a9d4c5875fd1b99c40b0b5bc2a16f6ceba28a6d104
141	1	299	\\x2f7216054f73c3932c583dec935cd863539868d07173a9c9d68cd4adb447265e5262bb01ce1668fa69270987088c7ef92da51188894c39c40612d996c6640e0e
176	1	237	\\x879a112c3ba04758952103a47bcade9fb50b567bc3bb120be157e694b12c638ba278c0ad11eecc8585974a0a4714ae48cae7d7389a2f05b03b1e1f0434413808
200	1	100	\\x9ecb4bd177cfeb4fdcff6fa8b8d42c80c77656f99454763df8024a7a1e9026223b89af6b8393cb9dda66fff1a878de3a217031f6bdce07ed79e9587ada97df0f
224	1	113	\\x63b1a07c2d4d9f69632a312212599b57b4acad92b82d2060bfd39e56fa0c8c47b99b974be94bd0f4ff2b7c346609c19ad43232d4f618af6a279fddaec876ff0b
277	1	67	\\xdf9c34adad4bb86ba814a7dc341b329db28edf2c228373a2644384082dd3ea445bccb046353832123f7eb8ac594ecf6a295b4c4ab291ba98ec70ca1df2a6df02
298	1	134	\\x2170a1c6ade538c91439a810abe615ec059f4f007999db0317c36834c6cd1b9685d50b5a29b6341fa16ffb35a67e2006e915f811b79c5209a6ac0030acfa9706
375	1	384	\\x439941dca6c5caff3cf815eed391eb44eda027d4906b6f5e996b9a9cc8ebb6f89785f9cccb3386c84fb71d93326fdd454c6067730729eef6e51571497ffec409
402	1	314	\\x5843e2d6ac16d9daaaa7cc2e4a528ddbe2ae8e5f17b8e1b273d7f3ac63d8ea7f8b6b35dda0d63aac85d7e30471629081ef7cf82846d1bbc710e259788444fd08
67	1	133	\\x4ce18fddfd0f26f8a806494a0c4bc22be20664c52835844688e97ec673584c3471c241518d3c9429eb1ef30f9d8a7d2e4bbc92077637654fa57c86165f57e400
77	1	344	\\x78475bf56f889ac375e4bef189ac9da67b954a005a07047386916fc86211c10d482e5b5db128de5c4b5f7834375536257c068505525264ccccdc2b0c60c3aa03
82	1	7	\\xd97bed0e247dfe55af1705a41b8144f4a66ec41624affce329ce7e72824dc1a6ae99358ab7f501f18d8a15c8e550b2289a05e87a9500f49ea434689b0b322b0e
93	1	238	\\x0a0480f3f1f2fae15c8070da03203e3cb3a3d37d24215e6db836c49ccf6ead1f51198e7c60ec98d3215695a79192899d8132a1109b5afd9364bf70aa9b7bae0d
99	1	56	\\x7f2d9499f74d59040fd92ad8e83212051310b70a9e0f7926d2d8d59c54610bef9e1245395a06b16d8c09debf06d3303fe5b5a77289c8298eb6f88b876b47df0d
106	1	341	\\xa0835c7e700d46a258a1a785aaceccd36c97b0e1a7754fe8f76ab6459bd127b52ec82956b0bfb02e2418d421a1b44c6f3e29fe68017accdfaa59be9e7403e30c
116	1	8	\\xd4f6fdfcd71cd0c841db484e648a69582801f5df9d955c32d415cd7b9efcc425968d6fd172efe27667ab4bcffb4421e4b3a13074d023367ecb13074723162c0a
125	1	232	\\xf9ba7280d5ab6c2cf1f24bdf8cefe66096f986b87fd9481947f7d9cba96f332f69137974b7521158897f6409f3a2ca72f6fa341936e881a03789d91bc1a7ed01
133	1	177	\\xa5ecd4e41af21d9ab673b8cc572a958cb09acbdbb2b96e5907816be3779892af10377bb73462db057df05b1c178810f49902c11a6a787eeda1d72a3cbaad2202
138	1	292	\\x6fcc31a23929978f5a5640d9e291b72d4f0a40d511c871467ac580b919486eca7ee750cf5ea5c152ffee80a6598634074d47c49cf12aa5a1d323806fa9a95406
190	1	74	\\x2a8382055bfcfe674e85d5f00409d637332573d1053294d4259cc63a7764655f8357c3e2daf2eca2c93b9556e23ff9dd597ba02a08109c5910e34534c965390c
216	1	261	\\xb14fbef07cb5e1e16eeb48681dff8e66882768562363807d92f710addafd3460c9e53eb292215048ddc77a4200d0c5ac96535fecc68dd4f887c0bc182934f90c
284	1	340	\\x67537ba66f77bc9340378df0e2d06dc4b2f0e622e035adcb4833788b71898e30be179f1e7e714648c99e12af5123154b81d502a54114703ed33b319bbfa5780c
324	1	230	\\x2567cf387ed38a916d5513f6dbdb84f4ed4f992777f81f3c27c17e887f4247752c3e872bc24f2d86ca7b7bfce6872e49368a232031b22868ef8dbf2bf65f3d03
382	1	240	\\xf0550e5b1be113bda1100d22e620235f6db1e46df557b8d6fb1a2624627eadb0176f379c5f511d39c433f05e4b32677b3e7f46987634abd9f7d9daa9ce3da603
70	1	331	\\x4b201dcad399fa6878b279621a26d438c347e1cff12ccf8e593f1eff4dd837cf1fd153610994a95a424565f6de07ee880a0a7c45cb79fecc1d309ddaa35f4001
84	1	289	\\x7d53b41a1d4c14876cf13768182cac839f234630b262bbe5ff1ae70fceb70eee4f1e922a0c8cc82b3e4eb2d777aced7bc1f00c198f6ada96f5407672753f340a
92	1	129	\\xc9403281321f4d3745991b38d5a2dbb1e89a49f81e1f04eee6bff3fb3bdc9e804efc115259ad294ec962f9ec4bfff2db91db2d8e413cf30899de504c055b8b02
97	1	206	\\xeef0ffb24800d3e6780e0e9736aee845d1c08ea69f633dc280ee503ab6041b22dfff0b67c66de5ab225859f7ca31c00881ca7f55b8407fc6b9b0c9f504774000
104	1	16	\\x4528baaf288c8046f333a6a643c1215dabb45f73b3d2ade9bba29b6c63446be3c66590e9e658a76f957f14867631315605a527597a013a6d23ac95e5d2396d0b
112	1	216	\\x68d81778bf430416e3f1229d5faa6f17750c11dfa51754550a9487091328c7d2f4227b95c555116406db9b78f847674081df55a153bc6125909601250c875001
119	1	319	\\xe1bea11f752b62751fdf1f5268be03cd50bc9f4edbcad712a3f5f1c1434744a6ba7a43b94f39b1d9e4ba1b75abe00b5533713131aea071816e6dd04bb3647e0f
124	1	258	\\x223cde1d9bbd5e37253d25466bf08cb1d1e221bdef565eb4360d81c9ae5c55b6ad903225caa23bd9329e1b03975758a8bd60409e923be45e5e20c46dd88f940c
129	1	130	\\x4c6324d5471740f1cf56b6a7457806111fa27df0a9dbde75c97c7c472ff1679ce0ce4bff7ec0b3ef2b1d7e69680dad69d7b478ebe15220508ab64015c2691b03
140	1	48	\\x84f6fbfcfac02752c5748c7be5e7bf97012349581849ab752c07937b445b3ce25c67882701e9f2fd470c1706b02904fe142baeac107fcbddf56f49c4f4f65d03
182	1	267	\\x60f872d0532f65993d352f50a52670ae2d62b69d5d6ddaf47b998658dcb19ac09ca50ec8a0b292badf6330db27629790dc65d6153382ac74d3940daa1812b206
209	1	330	\\x3b22b6cc3286f293061c8aff545fded17e4b5af4ab9f3a4ec04613d4f6ea51439b108301aa2702d000bc448e02f09c213d0ee413eed06d71d85db93a791f6408
239	1	178	\\xe576f420b53d99e76e9fc90edaa757d6ab84203d7447e5c2450b96fd1bc952ee5d3db1312ec934925c2277b2dd569b7893ee162ac03dcb7518377c0321b5a60b
269	1	329	\\x6df6f616b7a142935c450aea6d314be0f266a774173f9690ad3bddd92ed8c824ab11ba5b321235463630249303194ed711924832e46e5a61b937621d03d2aa09
317	1	89	\\x93831efdebee751463bc656766d93e12588e91c0c799f67783d794f61f85ae68bd5e05d63ed27d84efd9fa8bf6d5d62f1e1e4dd3d36afc13412d8259dd6ae306
333	1	248	\\x386375db66b80c9eed50473f4870a8bdc99ba4e5c9fe0ba70f9d7fda00098ada90a8efc1cacd61de1f173a19192bfa543cf9fc813cb36629ec63b34af9f9460d
356	1	42	\\x57d3ce6ff481b5df3d005c1efb09514bc97d40a3f07629200b78b4600c3d0dfbf006ba869dc61eb5fc13e96dfe7ba87259c38b5398367a6e42a7c79d187ca303
366	1	416	\\xab75c670fc2a0dfa7998bcc662a58faf9d5d69c26825ad2f0e97f566658d9c3d4ec2dfa29f65af6bf94b375060f0dfd2f009e928f30e8ff0ad751d5cee016700
418	1	421	\\x8422c3fb8a276d0a3bb01273a0934dff311d8b68b7cfc4d44492f297bb133916cedbee10184887cfd8506e8576cd3e94e089b40b9000168f063c4eabf939f506
71	1	265	\\x445d43958c7f4abfe182b77a4637ecb6bac6ab40e44cce2114d81d4c6569ed606d49ec54b01623757b158f90d9ac2b6b903aa38554b5f6b4938510c0833edf05
76	1	381	\\xc5f82dc0f699df8ba9513484b191fdbedef405ab303979ed8d6dbc9cfd6073b1fd23737d918e99be61aedb182666ffff6e391ad7bce7b1a25e8bdbad89b2e908
83	1	339	\\x0f297c225b204b1dd68f61cb49e25245809c613e0b5b7d73b5d7ca61f5b1e5c8e6c5345a2c055977d2fc98b7b72c596d410b6891b2c9a7ebc94a046505c8c504
91	1	336	\\x139bcab53d8587f32aee77ec80d0e8f747bf657da5a98909ce0ae02e4ce1f17fb457d5b39a451191a90042314184913d91015a3ed9241574667565711b21fc02
100	1	268	\\x22d32b1f1f75ef00d32bd2f4419343298a27ee708db09b1a879817b2bdafabfa7579b4a9cb3a73e6190f16aaafce9510ece0b60af26b7292f32e7d7cd3cf3508
107	1	361	\\x13c5f6fbac6b44be7a10676e13d1915f2d9ed5e435b8d015e184c3bfb199a914fa696e10285733cc1f8ca14cddd6e3acd83ca6b315280855dd113d0b1cb2a506
114	1	39	\\x4335a499b3d96b6458a87b0de8cc989f5a2fa5822b0eacd1bbe5024daff8492df57137acb9e8cf4d2209e629f714e3bd869cb7cdd494a95ab155b8747b8b0a05
122	1	179	\\x01ca44cdc6a2f17dc31a8ccc4a958129f39ea83377dc39bc6dd91aea4c444b6d8202340c3a4a28256d147971916088dd5132cc62508039c2e8d2c0b6f0b75201
132	1	241	\\x82466208d62a1b25e070db63992782becb04e3af9ffb3797c277915b10b71d38d2211b6b2ec88211cd59c4ed63ffa3f8fa1dc6dc0cbbbfb613e3d765dff1b90a
139	1	406	\\x57699c255b00f53d56b610fd9ca0f901e87b1441f1b75ec2a6b4a6d28e2fb6f920d41aa572df20e5f316f565134f632f041ffad28adb4179ee6456501f61d401
175	1	164	\\xa03adba1b5315f9374074605ddb8fab8273dd35c6902076d9a57a6e259dfedf303f4405540e34dc6c22bb0545ff8e86aca23d203008f8c5e6946b8bb8ff8590b
201	1	69	\\xce45a4fb2461ec73d1fe4ad195931f71f429381a00d98fefaf82a911641de600477ecb28e46734748ffa8f04db3e58f60af59aadcaf60198e2da11dcdc17f006
228	1	49	\\x20553c7c5cbcaef1a12982c31daf524877bea5bacdcf6a312342438705d7b7502ab66ea2d91fca7bc956053156b2803ebcb3af8fbc47724e635ca555ecfa6c0c
273	1	281	\\xb4ef43510ec192f438ac2c01b8ea56b6656bd7ec521f3d21ecf1784d22a41da52c0666f315b50e66a22916f0f43018ae0a85220143d60b456ca1f935daf0560e
294	1	275	\\x64fbaf8c669c1ebd339c54ecab158569014f9bc6e77dee296a34d915e2572f7fcce854539d7b62500c5ede5fda6ece4240a03f463c45ad98640c42e0eaf5c302
322	1	110	\\x6ea9c9af9ae80956cfe23cc9ef7d3a998e4a54afa06fdfbe6e59b313f868f503538c91240c709804eea199b397ecedcf5b3df9c569c0c7769a44c9fd8b7ab308
399	1	231	\\xc3936bb7096e7b711d112989ef00cf78d00905b9a548988af4d0cd723e0b0ff1bd079e41f2aa0180c57d4dd52164ed4dcc60e158add728fe11da80d5c36bb208
417	1	332	\\x2007668abc94245a026268b4fe3025ea977cb4c09c2c4b7036416155a6cb314b358bcc332f1f257e2bc2ca7edf3f13f24f0cdc819682482faecc365e2cb5c203
73	1	294	\\x98616455a3aa0e37b935ec486b9ab7235d19c017c89e442bd5f91ab7e05b8a79b47e70ad0ed00b12047822fcb084d1987e31df6e76079bc376a5825847d6280f
78	1	283	\\xc405919d7dc7eab48b94038b6f534d332cf1cc5c2d83e8319fbf1297bc41ea3075249663171c428e5c4861d92c58f47452835b5503038b71036b9b0c99bea001
85	1	424	\\xb757049249d68a4a6024d21ed96ad1c0831ce839cfff1766f79c0dece6c25a3217f7bd0d3b22e9edd1db1d1ee6268e84e4f8a76ae0fd49361381fb84334d2b05
89	1	403	\\xa2e862a59535065eaf7d0b5872df444c33197708e54e260bbe1fd7c51009d91e16f16a0f353dc58bcdd04a0be1875eed22134ca3834633be7034f39a082ccd01
94	1	315	\\x8e47786e96e0eec5e8d6091e18a2f7998af9fc4df65488a8969e87141ef87086188498f1a943dd986a3d3eda612e78afcaa903352fbbd4c40e74a6c3b6083b0b
102	1	393	\\x8274375e7a87db04ea1ea92bc8dac1b3a895e19e50f8d043fcd068adf697b0bea9058b670859b68ef45b19b0edc0b9e7faa2f214e09cda82686f68a3ebda9e03
110	1	333	\\x312a1a916f4650cee340407c3d6b7b076f77d73184477e8a9f1587569905698737eef16c5e3b4fd8af3224a9c44d5cbac30c7567fbe14c91537542c4f6d81207
117	1	25	\\x39c996de2a037eae55ca11a7bdfbc50fc682e3eb51346ce82092c77ed9e5551577c1767639b2f53b30a9b1721260f82ee7b442bf4a8405f8c3de0330a3faab0e
123	1	243	\\x014e2399ae0ea50decf3debea12e420fa6cbd27ee3463f19647da72944e7ca51957bc493570416afe127cff7fb04ab7f99dc5592c3ab114f98984d8081f2a706
134	1	352	\\x8c322427e7e648b64efbe20e12a83de16007c1ac3c9f4dde85fc781592856383931d9a3040c5a252a7360c565339314107103f92417e19c4f561291a6f3b9109
142	1	221	\\xab8c66bf98b72acf8a14e4d2aa80f79b8196afe6a4d4a427a8af6a5a51b8bbe698c248ac3df8da7ec381c6f6bce7ee77885d632a8de7d6574c0f52e40b19aa0a
187	1	202	\\x6dd2b5573522b3932b3fa177ff8d983500ba37e9e9922a6d4cf738216c413d4552e69ffaac2e0aa2a22f8033a2d0878e4ab6c240b327868b135d16d9dc82110e
227	1	97	\\x3e5186fecf06b138a2f25ca1e9fe264dacc7c1592cb03da36a8e5f8f337c9d291390dd22d3dedad5666798e13bc5804580aa952701ce2876309d6a8f6c815400
246	1	399	\\xf686163f8758a22c52dac3aea7c0e8611ba3faa2bf1b7ac2f55846f1ff02dbd2c0006a3ad789a594dd01e899172138fdcb86c9438c3b1f61fada651869121700
283	1	266	\\xfa0ca0e8c33707b63c469b42f71f4f6b9dea431759ce09736e556870471998f9f7a22064a15e318d60a6ee23e7e8cf733752f033559cc4416813e6e24aa28304
319	1	168	\\x5dc75f27e7dbbfac30fa1ea2d6bdf6a422e091a18e7e573f5bf7f275b313a0cf1e74e58f9df87b780f40c09a01a5dcfaa05f18cf720ea55dcbedcfe3739b2e03
348	1	141	\\x8addf00f837611c53e28524f9f39f5e2b99acdcc95338b7e81777273c3238779ff25bf2bfc67adfef9646048a49bfc2951b2677b339e4d8eddd442ec6707a205
391	1	104	\\xefd598763ae5279008017bf9d6f5463224b43b94123692011bcff8d2b27bf8f9f908daf2a14f8993a15a6ce7d2501d69543cd38f9265469f29869fd3c8709f0c
424	1	124	\\xdeac649840f84e50ed8c1f5bf508be3570e3b4b7d1ce26c0de2792938e14321cc4afaf7225b4a8f000b7293c1689cc37fff87e5a2855ebb04c983f676867400d
72	1	73	\\x7945b6262a27d4b6834f6b438faba9c2c82a3408c8638f564b423d634f26a23ba86cf0850ed91901e072cbd50b65c69345535ba7027993df91a9c772ddd9fb01
81	1	188	\\xb983bff173c0deeefc5b53a028cd15172e0ea9c29bdb75f05b304f94c5ab4f40f7f16a94b82a45165e2bfa1f5f313d935f672cbbeef5b843735cbb129701240a
90	1	166	\\x416357a886ce59eb838e8811d9c24655e9982cdbdcdb4679050b7793171b44eb310778f47e330a734f208af840d7a2dab0bc8b2b93aea22463367ed394794402
98	1	270	\\xaaef3b1bc68537cc9c3d3e33fb2bfc7a4bb0c600df6d3769f55fdcc8173663f91921ccc377996d6c5da3cc89c8211d04d8692c2d1aebc5e8d0db027ca2a27f05
111	1	249	\\x3b68f61f5ae85f3c151909e600de309e1972c7eaa9e569c299b6d30fd458e455232ceebadd2057677127d4701efdb74785bc8ecbe975e277979bb8a7e18a400b
121	1	38	\\xa9fe4432a7caff9183bb6aff72ead785be9dea09c69b386487c75fcef029694568e149250d1edc49da784b8acab3f9abfa19392f8a75c8f632a34bf09ff8fe0e
128	1	161	\\xc6da51895205128a8e2b0c994199b27d4d4576848b7ec0fbf30f7ecbb26cf696f05b097f0b48ca40a4e60bf03f7fefc5a95e238075b42bca6f0ded9258a5c40a
137	1	234	\\x939292019bfb98348c498dcdcfeaf4bd6022646e3f599ce17f46cf3f96a90a0c5f1aba880f19feb5e6e42de017bfda11c1c61fac342eadca4ebdeb54ee47d50a
170	1	222	\\xbfe44da3dbf525a6e566e768b89899fe35e8e3db87a200323442fc7ba09cb19c49121c6d699a3ec539b731324d8ed6c3857f247f0e72256b4f223a094e372301
197	1	225	\\xf5f2a720b201508b3cbf2c45307ca2866c5e474e937ab2953102fb38e5c8863a1858a4331d0cd8e95f123b4a86f67292574528e6f084489b61bc1dcaf9321001
218	1	78	\\x7fb54dbcf65e91bbb4c48ce18ed22dbde6dcf4645900d51dbf9a6f440d20bbd026884e6a94f92f18ed377038d583e5d9d0fceec35fa27720e1a9b7d0e159c505
278	1	53	\\x7ec8006b2ced2791d80f9774282092c403c04c8c20c36f577a883db733671062aea2be0c2b9c4aa4acdd40dc0534bbe8307f91b19ffc7e43ff61323c60a1b509
347	1	145	\\x268348b23bbc86609bfd10ca929cbb8a26b024a3ebbaa6a37d7d19ef91209b229d00da53d45ae6c8c9b892460f9b743398fbc0cfa8eb6e104158cafeee03d40a
388	1	365	\\xfe4ad4803feace7c010fcf664041b60f5623c3f75d77db49c286305c07d9925a7aacf4aee4e6a9cccf258e747b74a3bee22f55c16ccf3cd501c6927c97d36905
143	1	391	\\x199a316c0c91a3a2da8bf221cf83817630c1f1a4ba2d166a0e4fa149d0f2d1240c42dfcb01d8a48d53400b1dcbb9395034f133191ec55792953a229706f6d802
196	1	151	\\xf2febc8c678e4c34344b1cecdb12c38cb6f1a3488029b51ede075a6b5ea8e1caae7a1ed12afdb9374baca9064ba06b12e70e3e82ac974db5e0248692cc34610d
231	1	35	\\x36eae4a78342ff5a6070aa5fc894ba1771dbb49f5e1449f9789b28854148f450c90bafc121befc4ac007bc403e8d5c522e7e2ab84367f8a503c341e8e58cd00e
272	1	260	\\x4dbd438953342702464120306da764e974c4f8169f0c3f60b8f77a31cb8ea4879d76c78e21418fa3505e6760d47964dd0e2dd0e611a6e03e471075e49adc240f
299	1	346	\\x29f710346c0a7e693d0897d6c0010a46de4727e68b8eb4cb39b6b78a6e09ced1dcfb14ebd11e83b6bde8e6fb402b3c443a3c78f9c5ae86eb56742b2746c7c602
331	1	184	\\x85d6b4595dca06980f95a989f757fb7803e8252a230f604cd41538f7d5e55d28e4798fadc1b4aa9b1883cc4fc4492bd49d5eb8be7c0b2dfafa8cec541674ab09
349	1	139	\\x43c2410054bd927d1244d681ef63655338643969f04643f39a0ed6d4de878d29f4f52a759a102b0f02f29ca92f667a62f599380ab441c38f55bf21ad632bc70a
376	1	21	\\xfe9db4ff237d8ec44da14fda680db77c31a5d4d0acf1996feb33f011a906b9513e7ad1b3c424ba795e422df7fdfa47015a68c2fbb347d64809ae42c056009907
144	1	105	\\xa4defad41cd7c1360c421c56a0109e86e0ab0bb835b1c8fbf4a7b4fe37d7910eaf64975f5723a1248d5b810eaf8bb50fdf39b615ff571c974ddac160b4a02406
172	1	111	\\xc54c7e7bb7e6badf970e0a7b0fb67153b8f9196531e84ddf5154d64571e0460e8d8fba7f2e1b00b6ec2efc7a324f78517e9d312d20f6f8ec7991b964029b400d
204	1	108	\\xe9154f9c29f7d9a29c2810837d861864c8c7e3afc058a2abc31b7b03a57a2f74378fdb06b9d3fccf19987370c7d8e387a943116b3d530f31feba21be5f689108
237	1	176	\\x50c1095a64f9dba513efa66b62452e0f3a772614a8aacafeb453535426cbbea8adb76a7fb0afdeebb6e205ec068e93690447467134f269d571de2bacbc72540c
268	1	17	\\xadb24f57856af3340ede82763d6a1dd734b2828568c147dcfda1b3798aef450f43e58bbc96621ec5fa213d50314d17cb947983f6fb78a764b7787f2093eb9108
291	1	320	\\x0112de0530f16cb3fcaf2f84497c16424a37e2e1add9281c6ed52862852cae494dc00e28c0f5f8bde7771269da27922c67730e97e87bcfd05201aa0bed3fed07
313	1	356	\\xb1c522780a1b4928e059103a496769a75efb8f1a68780a16ac70915870deeef325d91f55151dbbafd4f2fb1722e36f02fd4dedfe496ee704db9f0edcd506d802
345	1	50	\\x7a26148302c4c064eaac6943578c4262ffaa531c719f3fc2db57dfa26871efea191f5b8a84c269e9eac0655980cbae089185884057aed203992078af99b40505
357	1	4	\\x1f7f75e07db93aec33af05402d1205a97a0faf6a143319930bc69bc1adfd052a050f0002f9cc14f4c9686698b324abee14da12633d09724fe1e4549e7950cc0d
394	1	28	\\x3a5299c214647b7e77479bc780f5d01371ba702be3d34d9fd92fe34b2dfc0cf9db5139d98a45864f82bdfa5403daf6c2dc7d96066589340797e4942e190b9300
423	1	312	\\x80fddc2ec028030d01eb7f644f4d991bbd9d77b4fdc1d4407a396d2720c5fc17aad6038fb375688c7a64b9608ff1b667854f37987b3c06806f2424d5dab7600c
145	1	29	\\xa1265082b80ed58335606e1f04703972652504c68aa921971315a97268c74286d0b63fc969f654f90a8a62a0395f11162ab1843f54b81f08ce582cc369f9e40c
192	1	137	\\x630e555848a31a0e674e2f8d671a94ed55d7fdc466b94a745a38fe43763043c3261a3d50d43951256e889aab280652b4bd14a2736291d5388f6a3f42b892c900
215	1	204	\\x1ff6cb5014126369b2214e3c6b8c1e0f47cef2058d794c4e5c68ad14604b92ae35fcaf2711861581d37e744c97d38c2eb7dacaab2e37922ca243454ef4ce0d08
243	1	207	\\x1592f23f8c6b80a9f37c6b1637bd8cfeb077e7690b419bb6ce378d355ff7ebc223c2bb399819cd3348722bae59514302b9cc98c335275666772c9a161ce3180c
276	1	239	\\x703f7f05a00ca0c8f47b30f766e4c12341863e156a5e41f9dbd3c69f476f4b0e0362970b0c5d83dd445d6d7b708fb796af2fbe34fda67458de2a4e3fbac2b00f
305	1	11	\\x0da2ad178ea197269fa83190e3fcd37d0d15700e98e35a0539cf3b7d96fa69be2bc76dc18ce09eb23bd38c9e5021cd8d0b4d4ee706029aeb1c22bc0b959b240d
336	1	227	\\x5fd3113c63be61620595207b259dd80410a6687fdbc5d0fb21b2653dcb22387bfdc63b6f2e171686e555156691b390ba55f8dc370dd5cdc9a9010de11071600f
386	1	327	\\x67baccba31f464bab1db4ae75183c6ef84cace95c8ecc4025265ff538b02e51f80767690f010df4cf1226c3ebdd728e29162a41c1a134f61bdce2e463e4bad03
409	1	149	\\x8209e5f4215403e67341983daab68f8bb42a8b573e0814c7eee17cc77c6f637e75e78660d4c87ea017cdc12372681051f5b8750b7eaa54a2a6f3a0490efd0a07
146	1	127	\\x78e17b7cb3a6fe219f437c11e82b73b544e59967005c0c6774351963e24b9f4ad39aad629dc71611bcabb746e095b7c9e2a5e2ab322d1c6b4c34ea136709a306
186	1	199	\\x4dbfbe25c7e7620285c468cee5e2725f3c11f7da655ec60e8731de64b664c7a1780f818e59cd6f37c97bd71a47ef036e8041e7e7377119f64172f662f7fcd200
213	1	380	\\x31eae47ff9ee3e06ab341561b665d6384361f7eb1b1d7941e5a7ba633448114cd5f26aee2c401be4c02078236a667cf52ad0d41e1f783d8a72b0e69429d1170f
236	1	60	\\x0e50e84bb9ac42b112f9fbc92b84371788cb48005771f3571e7c69a353983fab4242dec5cd6f2bb5049b6d25640cdd5f5f1ca85b4c338ffd1b3ca840db3f7205
279	1	191	\\x7a52f69a83c48445959d18002538c2b98a6a3844fe4827b170ae98f683c54fa9797009d0f8f9b4e028eac233748b4a7eab41e3fdbcb95df016a39e6c39e4ff05
311	1	18	\\x216606829893289901de76b8d1f9ef464a34061693e3dc22b3a5cdcca9ae828b68068eacb77a04627e2d9bf1aca7b9e5a2c94aec5c05b7dd3bdb19d71019850f
325	1	82	\\x3ea48e1a02a08bb6d2467bd13b9914a5d774bfa03d3e68d0a11e4d23a970e3876b116e71a3aa98cc86e58971e4e29477b3d96a6ff20833aa1d538ff55bce6405
344	1	22	\\x4debc1101458b480c49d801a4cdb4a2ca9f0a20bf2923bcaf9d86b0e0da54b3dda68fb0e9cf3752c9e98b6ceb19515cd1dc0956564a71a603bba44123bf2a40a
380	1	298	\\x12c162b9a4b6c7de13eff4335d775b33ec4b88d5be1223c07377effa4e0f9e2f65ecf6a911d55e30b72b1eb5c4d9c8c055032b458c40420f0a00084fb14df70f
407	1	277	\\xacb085cb805f0ec34745d5d6ab82dcf73dcf181286bf3854865943cb4490e257a13b0983bcb2efb325aa187a3bad3cd19537486eaf034f5ed98e5357685c530f
147	1	44	\\x1404a69fc5c62e30ee8e9218ddf5ca492dea67a8f0bebff53b31cc4d6ee7b57c8cdfb2b8531b90871a77f996db57b5888dd9bd5c4fa1270e77f9d8fae52fc303
183	1	256	\\x798387c7f7868d43c058d558a4c93cc2061c00d1ec8317fde7a4a974a33d803c525bdfefaa85825f15c9ae23ee81e3c1038ab2cf8594ab5219b242bdd1b8c603
230	1	272	\\xac00de3446893a6c168c15b280f1ffab710e12a5719c7c2cf671807b9916824630987e1293813f192a9edd388839316c1b07bae0f5c2e1da8cd62fc44ea8f401
250	1	20	\\xec37064d07391b48abe8b040c44e18ec6a33680a413625e1421f5067abf5cfbc776246e049d32e41ed48652b0ea8d208cce50ef1275b1bd02661b1f5adcb4000
261	1	94	\\xbb2c80579deb511b2660bebb406c5567de7ef09a493b2525d047b016189d336ce24dbf68b2c5b9e5d354856ba72c0c6a2bf4f48b9f8cb372bc96f90126afd403
280	1	27	\\x70d609bfe99540f1be79c292661f626070d10e6a6503ba2b131ca3236a1431d8a8d25081a0fb1aeadcffc97766df913c0370acb6f8a41bd9542f681eba748b06
304	1	95	\\x331421bff9f419d6f5ddbb48007283b1d2309face8b45be88cd4e0190b5ee39239d9ed394b32761ba3ad7edec0c3e1f5feaed92c60ad8c81f291acd314934e03
318	1	71	\\x143ae13412b6b588ae89570fd0ae853b1ccc031680e55bd2bf12a78b17271f0af0de4a625891db7f202ae833b311a40a5fc8ff97456e9dd79a4733dea0aaf50d
337	1	181	\\x3ac38d23e0d7381a9d456e93a3bcd3e9a4d2ec5e1b7b4174f386ebc968086740f45c0c59c1f0c072b380ca539d6ec30393481683bc6bdcba12170b58cc3fcd0e
362	1	210	\\x74fcffc9bad6c8156db18e97c44c0155664723a1648403886acb5f5c33903c4f33a927bbd2726988e0e6de5176cb075e64e447638dd50bab9d18e8bf6a38b700
413	1	138	\\xb86eb9d3a2d9ff01830af4813bbecab31bf29c2b60a5627b40a344fd37ec72ba4e5836d1b0273e88b16be0e3820db853425cbc31f6973066d234431e98d28700
148	1	220	\\x7a68ee5f5bc7d6102def4c8e45d7cbc830447bef8932d08cf268401c79246d036c9f326d5de1528f1d301e475d91c479fa5daed4aed78bdef9a3a470d21d8306
194	1	301	\\x15b96d13e91b54c24ec6d4dc80b508528955dda3d0b56360abecc54384f421a0f915398afab008e58e013e86646e22b0f931c7ac121db008dedd11cab24d6401
240	1	273	\\xd915b52a7af4d4b5c316a0fb8a538154a972facc0ce4e4e0603881f9a7b6c798e94b547dbe5a31bd74c9e454bd3c087bab8f9ae742607891bcefc93b95cd3b04
285	1	148	\\xb0e5669bd4347ff14abb56dc11b28334644ea5ec1dcad9000a5faf740cc79e1a3f6b5299764df751f2b03fa07888431bbb174fabc79cbd9f751808e51f32c908
316	1	54	\\xa4ba10faba1aa820f7b7c8b01122d7227be6c7c5802b12db46c16f55db9f56a45207452aeafbab2f82ba52a624058c92675171272be404728f4c98e253d95f07
397	1	14	\\xb1cd5f892a537492a60e107241ee9d9765e559578648be647f8f5f4cd82f7b5b3ea16f5f1b0e131baa1fe459c8c80e1082c3abcab29c1e4d45dcaa07d9424a0d
410	1	19	\\x7e8b7553e071e5d3a82f87ab6cc2d122afc367506c2e4eed5f4fde7f516773421523fe1b90c4358d017e4ae0ebf1f8d972a29ff9be400ccfdec8480870bda607
149	1	6	\\x1e21f788d25535e4570f94449dc53f2c2c1da496a5db6f93583498a634dd55ad59e0f839f4072d5c71e4b9d879ea0dfa017a3a07e611d7f51f29ccc524776402
171	1	254	\\x040465df46cd7b50ca6c0f7d155aa6a35c5b2b8586a8ce302b5c877fd9a38d16e199622f5dd0a88a392a94b8ea5bd55805bfdbccad9e11756bf7be04b9391509
206	1	306	\\xf3bcf61b2cc87042a697d82df060956d072b15c705b404dec5aba7db9da1eded4886ce9faafdff61c071eed8f25917a58e1cdf659096dd0f40bc20f44248f009
245	1	96	\\xa61419ee814116c85c65fff09f06947f7416dfb5ce42473d7722acb41d8381cf53d00a22bef10faf9e20719a3317a41a2ce797270c1a4a88c2adbe1fd45de30a
290	1	253	\\xd8ad13ad0ca44cc5d08a8348c64dac83d3af98c8a1a07147c055f5397733cbd738836c7e30e09224316bfb7deb44d21a8625968b6cb8a83488cd177494cbcb01
315	1	420	\\x420133ccd46b531e19ffb83baba880827bd490ec3ef535356ea1c9f83293a35acaa2461f1d65ffabc8d8c51cee9ddc79e10e501847283f8f8e897cbba13e4901
341	1	377	\\x4f8f343a880aca196ae173c043f802d74c4d4c8f78b7069f9ca25fbfb4113952ed02769110becb5bdff5456e67efe82841d19f15c94783e4ff2ef4420b8ee707
353	1	142	\\xf25c248d6a26319748e89f54a2529b4742d590ae836163c1a8f4132a6695a554260c959bc3608fb95eabff1575720ae2913b007b60d664525c6c009620b95303
369	1	309	\\x1cc64e3d76e063213abcc43b7b10fff06c47a865ba800739605e28692b12ab263b8945cda7dfe2e1cac1b34a3c616a110212a99d9cbfb14e860715bdaab2e801
421	1	355	\\xaa315c2d73bc41431657ae8619129492e20472241e4dbfea90e3f4d18518cab59b57ef6468d754bef268e702a01d042a3fdea2e829bc405b07a4ede21a788409
150	1	155	\\x3862d9afa6b6f360a1f69d928af3f6722339d98880407e1a1a607f8c44f76d7fcacd87cfddd0b5c992ad2c34d3f4cccd770c3cf5485dc22c4c53f28943d7b609
202	1	396	\\x341dd09aebc206966a86c81d48ad9c7ffeeca96428075845eb864063e2526c88817431bbbedf66643e6e75e79636a4037eb7a8f2fedc8b7795d234aed837040e
233	1	245	\\xe0124dbcb5ab24f9c2e3a57f200833e0a1ebbbd5dc1c7ac14681579641415347b7617dd7db2742289f55e875fcba2001740fe9b0dc274481286b1c51f2c64e06
271	1	109	\\x60cb9ca3d3ec8f0b45437d63989de356f1253b4c73b9c48093da1dbd35adfc8811e5e6982a71488b7b6fb4e21514bc01e5e0176cebb49197304ca3b08475230d
307	1	126	\\x964144365f368c71b2f12b7900a40cebcd503fbdd0fc455c8b0a47dfced4a185b4662753c749e6f673617c28238f5c1c6f6150016e579ab601f2233787a04b04
327	1	15	\\x98a5858776db183d0fdb3e1cd804db93fa7c2544dc808b2b7c5ff05c157f60271ded10b7af27175fc9f2c08e89480075fc420b47fd09d7ac63a565bc367a5606
358	1	310	\\xfc24248dcd693f86dbb2f357a596727f3fa5059683ce8eefe0fd9798ac4c3177778f91c541c9ea68e4103207fd7774abc2e0f97baf08c7c0220e08a7ee7bc70c
398	1	347	\\x7e0b15fe6900335844d21ccf11bcccf445451a3ebb6b609780e7cce7182ece70e2e13ac1b5a431eec8782d3a4cb88588223cd2a30172372006096a094d8b6607
151	1	31	\\x606d7ea00056f8e689d7a3e3d1f6078459a6e33bb99a4eda2367783e680755bfbf91f5b4ad30718ca2d5b942ab5d28c705212272cde215bcde83146b7f77910c
191	1	173	\\x55b6421b93b785a63cdfa094e218fbbed8360b670aa4d3c8e8617f6d078493235d407aee569c186d487534766174a302da2ed9dee1c76fb1b0866ee22595bb09
234	1	40	\\x536f51a05789ba926dc7499187646b04db861cd1bbbee035763098b16e57aca0f67039f0db2499954788e2b40a49512fe4ffdaaf2ff4f88a41572cd2d63eb205
254	1	103	\\x32b4defdc2ec7f47e71a447e37d09d8bfcdf0416cf582da362e92f897c8ffb52d126da2e6fe14c819dab1dbf1a6707e55f81847190c5da6c0da2356641303f0d
267	1	32	\\xff71454178aebcf93c8ec0db19c7b44fcc78ad166187f5c8622c90882a0340eb77d73bdb141cdace3c136a4602a70bbede3fafcc533d4f1319bb9dbc2cdf9709
302	1	404	\\xe53fbf5de1a4271707963cdaed33e5a31aa7f98f896868896fe2637a5b83d37cb819693755c6a22f622b5b05e1004842a4db5b51082c7fcfb4da52c76f5b3f03
374	1	402	\\x4aa78d4cd9133b34fa6af49774c34e356f3a620b601c22724eb09bec625d5be3cc90fbbcddb1332745152d4f5d43b420ccd5b3fab6ac0216fa52de23dfac1f04
393	1	418	\\x5bcdb98983bd86bdbab1d99459129668d4c59885a06ee9dc2023b0e106b5a4a866874d194df5376172f8cb501ae3e9fcda4a156a12a22d17a04d81bb1116a90b
153	1	146	\\x2ab9371cd47b87d96274841da5a5768be50ada803a093225c750dd9a88e75387acc9d999268b65b1d38921fa058773050560edd9510247a227eb9de9cef6d605
203	1	183	\\x9a72a569a91c2c66f9f46f65e8199078a9eaaacc7ce8c1a93d460c2a897c74fecc755cfaddbebdf6c8b61296befd88178948d6fd514789eef114beb7e031ca04
244	1	422	\\x9bd544ad10a1c68fccc76cd88e7f9cc003c4991216797bb2f13c463acf15e81bad813d5a713d7f319606c1cc7349f7712a4c054b716d31e2b5a3f5368233b007
263	1	125	\\x8a06fdda06d5f73a86ac18ab4630692f18029ffdd4738dc243f3fc14db20efa3a0e0c3b3a8d86caeaa89eb500618dc7d2df5082013794e7ee7ed463a48c01000
334	1	162	\\x424381e6257989d4f5d078e156502bd96941af964ce065de8cee10c100d4c80ad622918dba04cd67fe8e214e4a2f1392d03907d2d573a49bad7167e1bd505909
363	1	247	\\xd206ef48014f6b98f07f9efd1e4354199c4199279d70e12dd31eb51d5f1ac23f3415fc70bf607b6c11590d2874d20eeb322a318ad9f73d0e4fbff38732f5410b
378	1	185	\\x8e7f85e2ef42794217d43b0501e751c2d524231bf539fcab9751f430e3448a7a45239d7e76d23a2a19936fe521a1eb71032c865d2e54afc5c4f5714adc11d109
392	1	363	\\xcf9b0c64a6bab18ac0154e1293651d19e5d28efbd7169472d053b84222d1f2181f2e18f86a7c3cae871dc70f822766bb4e2945ed2daba0c84ad44d2b60103006
152	1	9	\\x45eae6ad2d9be18d7ce182cafd781d69cab2c930a9e2e573d95aeb0d636c2a194ada7284ce378e8902d1fb0185052fa327b3ceb43c98e7b9d0c8573b84f64006
198	1	373	\\xee41a53167d7a8320b8e16e8e936f3477125172a031b8fb04dfc4e6fa3bec902fddf1ed5319745d59f460ad963c377222141e18ce015896964d9ce2fa90e1b02
232	1	116	\\xdb9ea2698761ca9411cb8d159ec4f165b0ca2e14e0416884b8c0014edd6d68fc863197dd070c906e9e361ce57a591763a0257e518429272a5b6b02305abf8902
262	1	217	\\xb5b5e6aec1603249814a93764f60c9bed025c2a4d12205f77ce12de79a8643f1539e134614154856d4433c7414fe518aae0c6f106aa35780102f284d4dc6c404
310	1	98	\\xd13eade93194f1d03d9035b2d83c3ed69237088f7d614226b679669b2679dbaab01be0531d4a770628ac7e30607047782ac6931a04417195f226fcfb0988e005
329	1	337	\\x3137a78a571540ac0ec92699bf436646638358846d59a821b0c771feb8484db5da8c91a4212dfdefb03f24f46e380f88ef2cd01326704d0b7ba9e0e1094b2606
373	1	322	\\x0f7015fb7a29a2c885b2fd13264629d1ba550891a41e3a8817861751a035d15d3a16ead53c507f48b11cf697f05780605d55eabc459fb2d910d01488fff3d303
415	1	415	\\xee82acc6620c9ba9dcffd6334e7da74cc3aa020c9993e2adc7c936938100542a38b7d2ae3f301b405d645d3776a97248d294faec108e0e57a2b91e0706fdb108
154	1	398	\\xdd01ea564391c4c12021e5812258b7f94dc0448c352e3a414df1850afd2eddfcba6c753558a11b6473520f1622121c827b57b78994ff41e5176072d504c90601
181	1	250	\\x3163101753dc0dc750e055ae4a233ba0dfad3316ad0abe8f5d865f12597726bb10a84dd62110a5040d0b241fdc7d3f7ed88ad44fa22cbb95f597d7cb0ae33808
217	1	197	\\x99c9e2a6e8149647473b28ff10ec7cbc36e47cd2c1a8ebd531f4096df9cce3551e07d9039d47e6b60a4c82e7e65c6e00f7e6325946b7670755aa667a6aa04d01
249	1	400	\\xc22e266c4e54d6433423e2fb1f9348f4d8ce69420a0fae5ef215308f5b94cc94fadc581fc30dea643479a4ca2610bb01588acaf7f19977b4896fd6ef4095bd07
257	1	233	\\x2034a488b30aaeb42329c9acb2ae073ad5dcb8c7b908b74b64a888de574e962505ea551771063a3ab479f55d8e1ef90d01229d3fc723482c37a79f8c83c7e10d
293	1	107	\\x682b0979b108a2f2e806f48ff894dd5b8ba03b2538149796289da16b51409ccdbf467aceaacc4c3060f5ac2bdf3aa8b94ab693a3ffab13f5042597bf3fad0a0e
323	1	414	\\x1b5e0d439915c7d0caa0734ea6f8443591df202f5571680d66c96746025598646c83b1e06cd74241e5a72b719f16102b80c3b0f90d342ad325d1703eacdf2205
340	1	242	\\x873ed5bfdf0d8baa47e3a7098d28489b8fdecb5ceca1b452645a7b8e6a5667ee77fb0a6a78d8e637ac3650bd069db5c496565a926f24db4a02eb2054a00f5308
354	1	328	\\xec77f04838c8685e149707092131977bac8e88d6f6459173e7b6f2f922207d4b81a94009f765822d4183369b70720e93c65f6a0b180e1da657f3dec1ca240e02
383	1	397	\\x08ecb2ed63df01f242c1ca3a0a8c9b0b397bcba89ca82c38575eea4b5f4ca9935a14ee1c6680db86963efc65e107e03435d098796b254bdde8d22d03faac5407
406	1	317	\\x3263c5f707755a2ba753caa7e29f28db93b586b1b6b5be7f8c329494a60e67d198efcca67660622b18803c527450d8fb8b23ee5cad1e3983285cd782f909e90b
419	1	276	\\x8e0a4b517877a9d1fac8aedccb7d3188560d04a6dd532b3001bc71542a1e6a761019c5af2aac3d99fed0c601fcd1d2d6a5c073b84e30b06e8e3ccfe189fd6404
155	1	122	\\xd0359a325732ff9fd4ec671e151a34b67c439f2045a481d514527427a1953ee1fa005e25e462dca2000b2225f929c31a53e4a9ee95031892b699ce71cdce640e
185	1	41	\\xc086daa00473ec5caf2038ce1238df7dd32fbb8051eee7b70923ff86a7dc14bfe0e2cea5b6268276a7f023c1373f35ccb622438b09cc4f7ccbdfc3d7b2b3620e
221	1	68	\\x0388b04754102c135af1f254ff5b97abb2cb67c0c018325ca8402f7f3abf166aba394307766ee5e66fb11628dedb72a5ca68e0053b034915455409c76105e50a
251	1	370	\\x9bd77439e63de129b35ec97ef3775ff669ced199d8c637fd55dfd93334e3aa1db6c938cb2df2c2c1a10c88804e3ef71adf91f08ffa818bb1fadad062062fc902
286	1	246	\\xb8c212b71a7562e86e100be7183fbcd0599640825785e31038f41573ced5d2135eda0ac737c42277a5ca61eb038744fd8440a2e0ee72e23b240d9e99953e150c
332	1	12	\\xdd62d577aa614bf701caee159a5099433cec4cb5f5defd071d48a2a1a713a3c9ad81e3c023910fe35b44abdd288da218d097a8dde1458505b4fd9ff2452a5c0e
412	1	290	\\xdf7237bad4d4ee1f5ea1cfb6dc06d2cf3c026a72ce6dc28e73228830b5f5cc0219d97d64cb0e33667902857d28e66873782261b660389417b8b7911c2e0bac0e
156	1	172	\\x2859bfe9ba21f923ee4d9c322e31524ab762a99bdbc02d435ea77023affaa37c2646db8eb02bd9a29c563acee9d6c693bab06dfe8b7e096d70213f7c5c070403
189	1	372	\\x13005fcb8b014744ea169a6f3f44d027f34f87a2b66852bc62fc39a3ef4281b4448892d3782bfc116ebf0d396c44a23d43077aedd852fc4693b4b604292a3602
220	1	389	\\xb92a4f6ebf8d2400b176b0a882ebc1491ca97d0b248b94b40256176a0e989d8a8dda318787b7f8099874c6ca8362e6cef3a58f0e9cc19120ddfdaab988206f0e
255	1	269	\\xa14de8528719dd6d4c4b46638eee9d1c5582eea8724cad68584deb8a959348b9206977d5a7e9f585773842ea4777e7f7867f3a93ba8db85d311ed6fc8c4ad303
301	1	318	\\xa3e4cc0bdd1e243b7ce4f609e1d9a8a270cedd9846e57bb9fd65a6f3a669122969d98ead49c570c28c461e213686273b7d7392be5e8085b1d0d18b3a608e3b0c
408	1	1	\\x7aba0128044a514c7d5834d0ff814c9d855bc4aa2e3dabe35783ab1c320efde8aabfbdfc16371451fcddc278ad2393720f687e292b42b2b030cdd687f80a8a06
157	1	378	\\x9788c2dcbbe9cb7c544bfa3a78de9abdb582e66e6717843a003dd28e7ac149d87a3f985ecf51cd1a5d0fed1d74df3df3dff0a19d5a78664b398eccc94bf4c109
199	1	307	\\x0268ec57fcdceb1b85d32e3738a8c01ffaa90d30397f7dba4985e104425e36a68775a62b94a9cd6992689ee2480a403a8ad0f3599b88ad8186870113f7e62507
225	1	316	\\x7a47802a22ca60bac780e8ecfb20a4951051dcce34d4e7557be1918eda24f8048b3911ac7a76f4e2832ee1d648eb57c10a694a3da8cb50e55a76de4d33732506
264	1	171	\\x4122d685d1ba36dbbd283267b9a93b07fdfa3ef5833f93f0783cf48ceb1c3ce23848ae9592d2235057b4dc9fe355661a72c75348e93bcc408e82782931251906
281	1	362	\\x8ff47070195e00aa8c9144d25a77a0cfabf90a586078d8568f652ca28e762199bd0eee056fbe7772b63ffbccdd9b476111f9762917b88ac94de178730008bc07
296	1	121	\\x3b7512cacddb1fb39684414fb1936be6ba3834dd59716f263d3c2b6fd5c2e4511abbda10119345883c65f6e460f0c1965b56ba90841b3d2bdc21295c29f0d40a
314	1	132	\\x0445b760a008f73d6bfd08ed1ff3e8d5093e4597892344728e3ed666c264829d72531cde38e08e7dad8bad40b64e0952d20af21d8a712376adfe2cd609cf920d
339	1	385	\\x4051136988833b4451c8c2c089e38ec9cdc9fd86b82f2a4d6fd329f05173ff272225bac7f3910cf7a5d22dfaa82d516638d2ac1088258bdf735d072ffb30e70b
359	1	194	\\xd217eaa1aa8077c514c3ded972b70e7110499eeda6c571640d814be741264f51f9e0e92f46f7c05c806c31327c73f76669de625d26c8721991c0ab1b01b3ca02
401	1	174	\\x84e814c73cef6326249493862ddc7d6bb54e51ff687298fe3d023e74d9d4b835fcca6e183a87e21d942d6eacc685013f31b50e28e49adfd5692f7620ab502f0a
158	1	376	\\x6b93ef123e580c9f59d98c35adea0ee5c565569e5746de2ee0c4024daa854446001ead86c389dfa85b1a59dbf48ed0f3d65f729c50df1c730e50ba0977374e0a
193	1	364	\\x030f627dd7d30394c52e6194f7d1a7861b5ec40e9821c3608f5cb8303c444138dc9169fd3ef557490ccfe3830055f262cac2d8adbba86635adc54b896b72640e
219	1	201	\\x84308cc9ae8fc45210aec4530a33004b7c2c56397ccedfe519d1f2578295351fbbc5601f2391dc77e8507e3c833e378ad3b8bf985094b8f624e8e71f440ae900
265	1	387	\\xede2493be0b843afa08f5066bdb66838fe873c12db9232a27a84e49d462f41b08000ba5238827c8532391ad690a72663e50005892e2757c260056fd8b7d84d09
295	1	128	\\xf2bc389bd1c99fdd819e042ae462bfa3ccfdad44607d0414abcdec94640c095181d3367f9d9421abf62c6d2bf1bcdbf9a80acf4d7574ae0fc5ec16228717330f
330	1	76	\\x1b083a185abfd442bb9fbd5436d649df050992911d8c88a732be0e36fb38fb5013ea9d8e5706d8c3c997f45ce59e1687d62b6a458b9cfe7341fa3d1b1553c70f
346	1	33	\\xa121d657af939d4f0aac15318534c074f8305c7b4156fd112ff2c666344b1216a13645f90ee57584f551cba1aaedef5d81ab6f0d7a25561d3641e48b3ea81500
377	1	374	\\xc090b7b87a9682416002b45f1e8db6d0d8fdcc1bad10a31d93fa77aa40e2d18d99fae821136bc2e9dadbfe50d73fd13f6b1e14528315a7e4490dadfaab6b0c08
420	1	379	\\x79eb80b45180f8ba66c5536491d93441a2ccd978cb09f06345926e4495fc6f302abb20dee4b0e7276238467013f088878f0df49b8636e5f391333783c55c3704
159	1	293	\\x6a8b11f78f9c8897e6e5fddc63157eaa95eacb7dca4da3c53de5ed779af7b4a10fe4c38a02146a6be88efce5bf8a48338c78972f5ed6f293c09b61818cfb9609
178	1	409	\\x94109d7326e8b90f52055a311b2ffd275ac9136427ee4e472add8cf3f7552fed3f26d5c955e6317ec87ec78a6dbfb5371e28db375d285ae953d31e3bb8562901
211	1	305	\\xbeca79cc391aae578430386dd7f2572747df77fd5702825d10a6f8fc0d1e2db8d3a6bd8e6bae62ccbeaeb0ae880d12cb91ac9f42b189d1bb106566cd2db7d20c
248	1	308	\\x8042a56f25e6a8307ab418750cc210eefa667d3df2d9b0a1687bb419ea6cc21a2f9ab26622c51d636b60086c0211734df45a38535a70cda1b3866650ae668602
259	1	218	\\xce9f4533d577aaf425de55fe6299dc8a4e333baf6755012e934197cad6dd15a0a96e3ad05f0b311058bee3512b4b1fb773abc874753107cb62c8d65525f86b01
326	1	285	\\x7cc806d1e438334f5fcf1ee330d807df06fed4d972417e65e86e9f76c9bb936bf95cdf1541eeb58cfe4dc73c6949400e3e752f56cf5081ba4a9b6a6e74f2cd0b
385	1	55	\\xe38cb4d43948f7101f4f15765788e30e78724877bcd0303f3871a02376e64b0319d8f569ff0314ae29dd88e5b3d14baf16dde733270c5c3d40deae64873e4703
403	1	383	\\xfc802fc692af777e975764421c4a5e37a4959a5e989a4370dfe73fafc9ea70027614395606eabe269b864cc777df8e67000480476e49316546d885921397f301
416	1	47	\\x1433f42120d74e2ffafa0eb8263bde20ec26192c691a742e7979c77ab3978c0cfe80b35b4a04bfeee2c49305bc6154370f2e9b0307920f3a460fddb5d74f9c05
160	1	43	\\x8a1b914a352ea19b111052a2c32d2fc4d3bab624731cb64cb2590153e72cfa01ca71103cad6cf1b069d990152d01e29499f767538849f457c139b32642446e0f
169	1	405	\\x152605eea7a655a206859eaf4d826df6751d04b75dd5d8cc3254f054e9eddfe29417f38c9f57367d5f87e1f8037fb45a537e2adfad3c186d72ddf5d50229750a
205	1	286	\\x06a5a28bc0d6209fdff8c0ba7cde4b342983d23da1cb90b321ebef09fe266c691dd29e5fcf4828a8948e57d9d293c1bf26ac141899f37b8e2066e556883ba906
222	1	304	\\xf926e6481ac1c135561267b39079f481a3863fea293d643abe287ab614a6bb805a4dbc47babbf97c4e701a8f06ffd94c259c9084191ce281493e715d1123550e
274	1	46	\\x77ffa16fb87443f68b8a074e6e0d73a538e8c88b20771d3eecafd7ddb8a066b556b97632d472d828c90a9d07e30c3c950f78035e55e95b3036fb65b18267d301
312	1	66	\\x6c68fdbd990cbb33a1a2972cdaa2df0ba95bb6bc5d7172819550dd329a6aeed09ab179feb76eaf19af5b5fc0ef186ddbe2d31683376ea7489c0298a598451d0a
338	1	325	\\x618412bf1afd7aa8cb868dafa256bde5bf64cc0c16328f3425aec1bae77eaae61952370faced1d4a3e1565c36624ed96cf50ee0d394275a2b7f8353c6ae03e0f
351	1	196	\\x4ea4136cb0f13a7e5432cb5fbff658ddd452a57bca81b2525247cfd028a24c8281e91c1d29ee0f8b78b03f7d53a7d8254105989212ea587a79cc0d4e3544d200
361	1	90	\\xec9b3baa94a34ad4348604d3b31304b2850673e9f47e2477b972652ffa8bb4ed30de0eb58add3c22fd851e0b6c6ab4313481b586cceeb69d46804d24a21f4804
372	1	300	\\x5b3efa5d2637aa43ed2f8798c18fb26d07f15f0b5980201f0c905f0fbc01c5d2d5a3e01582dbf8ff864266db0414bd7e8a8c2b6064b9fdab243e550c999c6c0b
384	1	70	\\xa98f3666e6d937df91444f0db9b2039ceba19d2fe90ae047ec8ac7dadb32e028dfff4b9ef12b738f6fc864e3711377c5851c257c4449d09fae3df64a48a9870d
405	1	263	\\x9f6dd0834c95ea8e5776908d6d06f7280abe3f06ed2a0907be76e1ce5c3105042d91b6a585b8a90755474224828eb4d03ef1a439660546547b69ee0414f9a20f
161	1	51	\\x181999fcc722dd5ffd69714f067248d23b6ace901f45c9db5c1071c4dddbfc0a42f7f6bd24c58bfe59f7979662abee134f972ebd567adbcb8014661b12e9da03
180	1	419	\\x1d98cfa7598de25de2d2d43abc2578dfae3d716213a7191bb0d5cd3393e3dbf1ccb4e0e0b7a1d366eccb3d84b0771a0117b06134ad8cbe71f4fcbaa0452e6e07
226	1	106	\\xa700e1d42860fa28448729c7ab187d49ee1c4f68c01c8d03423ca07c9d5de72854dd111aa8f590ea2a93f233bcf1a415e6a101bc6df276bed58268cbf2f1e109
252	1	279	\\x326eb3cc91831a71d60313f75b564a308f3c8118a731c13a2451ff500efa97f2f8a0ffd9149b4d79e002c2ca8f53155264726af8cd7cf88ca40cddd27afaed09
292	1	37	\\x0ae3e6fe28db73223d6b26fb46b8938f061c7cf32405aa92f2b05c658bdcc5633f594881ea23bcc8786d21a5b1db64e6708e19e4456fc9168df7847124117a03
321	1	63	\\xef7c9b2d8644ab4c4293eef35d2c70f3cc7a5732a757184d8543e2dd09dad0e5a7d51cad0a68e67e6dafccc41fc2213fc5c5eaec5ee7b67b5e3815dcc840a304
343	1	321	\\x62107227059b20e2e870b736baaace81fd3d45a04676e1acce2b6277dd2cba326a3dc72438bd649faf22de6a2cf9ef6b4427c4cae9e307c75f070e08b49b7d09
371	1	87	\\x95be4cec117d7f1d0e525b2d876d5e03c5f092987fe97035686db5fa283ebd132c925522eaf9c59cb585c11d5d5227d20bec49d9006110a1765554d277a5e506
404	1	187	\\x9f940e3d13b3dbca8d83f0979a0cda745a0e5f85b677977e294348965ba10537492d210cd033e6efef9d79efcc4ccd67d47a880bdd1433bd086433a05a726e0f
162	1	274	\\x810112a21de6dc07284a45726ee23fde83c55c5bbcbc51631268985971f1794ef135a622c823b29572f9b55c831bd159b4650829494308eb5a6534c255ea4d09
179	1	358	\\xd90d88dd49f8500f878eea973aadebd0b14476b340626718d3272ba5a28e47bfdcd589b683b417ce8e1efbf8dc281ceaf6c5ce0d4050ed252d3d457700fe2302
229	1	182	\\x57d3ab8c3c3da30fb9fa3e0ab099cb13136de00dac38bd046f9c0b2fec5789751534c376a6da3d9c4708ffdbe5038f8976ff5e88b5673eaba9f57909bb64460c
253	1	278	\\x71a10f72579550632e58b4dd55bf0aac1248912419336f3b8391ae5220d0e966e7365dec7f43358906e773bda37e1e693b3f4367fb58a3abbba18f5154086e07
306	1	5	\\x429bad5005e8b9f5867c527e342ec85c276a678726b4e61df6d7e1a72ff5fada841e04690318cfd4875d5bfa115271f0ff09380e7cab47a77e229f8bfb4a8401
328	1	58	\\xf536aa14dfccf67174f49f25542ffadc394a229826cc540d5a3a9ffe0d6ed93a55e286d28b576428b1d256449cd22bdeb0914c6149e421f38aa023da64680609
350	1	160	\\x01d2c9187903dbb62843da38ae3d6f6a89fddb0b291a0f4746009dfa876a5b3b1c9d5debf5bc0cf27a93726a65ad3e61a901bb9422a180b07de581a67a527409
387	1	252	\\xec9d69d3620169b33e185d08784b1f973178885e59d0ec76563b23ff2ef9bbb4fb9e25b743f4affcf49b306b801bc58c359198aafc40e3ec1c754a1ae0240707
163	1	303	\\xe6bfc1ec1bc04a61648aca6e5941659ccd933f71f9f978dfd075f108623b8fedd67d823cce5e6147c5ae368a020713335988fc15607ec4bff2d441b59595da0e
177	1	75	\\x7d7629e077ada96ff91f52d170cfa0f1c9bed7835eed16bba05d76d677fc9f96d4b2d48fa08fbf52bcd69599d2f6192efda14614d6a879d830d345f30598670f
210	1	189	\\x3bf4558a627e7cf60bab5b82417070c2a781da2ddc16b6b2ab32cc88379cd4e9e9ba731510c3b9fd9b5e5117e2eab77e6016d569c776f21157644b12d825a008
241	1	120	\\xdfad035de5cc84c7310e3f015738b5e2a54eb35c011595e606cad9aabb600a3682799078a9a1f49eababa4dd6539382a774ba0133b24599ce58c2f995a709109
260	1	175	\\xb86426785564fac8536719111a917e5c3d46c22082a3341bc234da82766c53d33d3bcab51a12d086341e24e4dd548442d03d23c57b772b4b385af7b1b996f20e
288	1	114	\\x096a5711ecb851af86da80f77a6402f50878a3bcb72c15cf558a0b90376ba002c0e94ca23c8be999b16e635ac2399f96f73f51ea4cdd94032d1e951e25b92301
308	1	59	\\xda645da1b91e8606bcbb5e8b469b934d03e5217a4e27f2bd440178244a170861a28f737db171500edfbe2882a76f53aa15d5b5c317601bbf1e290d32ac055e04
352	1	359	\\xfd317253f969172ba37b8b75f8c03bf5d7f56bcf15d49e7970f0f7c34cdf539c8ab6af0d3e1a83e9e90ecdc1afc02ade8c41532470de34694bf942a7736a3008
370	1	349	\\x50188996fc61adec53e10c19055ad818b291081d9c9dd13c4a5cd38de881d795a922bd9df09567d92a5e97acdc3d7ca8cde4d48beeaa2215e33e8fe8f914320e
381	1	34	\\x3000fea6c082eae6cc1262837be4a1d91c9cc3b3923d9654e3d76f566ea676a80c8a282e387c60f5ed690a14abdcd4b3da432ff64fe275c9063805382c088d0d
164	1	287	\\x9396ee7cc26c83e020b1e86f0ce26f0b38adc7f0d73f5633d8ca3f67101296370c6183984f93435cb7227b603703716f6678532984b16b02129e0899ba5ad905
174	1	326	\\x9f2a00e0df1a94c7ac32055db40a6c20b64afdccb65533d5febf5e75816aa1620efe9e73d007d57684e561b642978555ab77af2d0d84145cc09b25715db8ae0b
208	1	80	\\x70b95b1c949bdd5b839be95fe5a3c22700e5d10f4bf5c17abd34aa1dcac1fc56ef0ece6364226e3c9654f6a3b6754923d2f0f91edf1533446a44614a98c81704
247	1	57	\\xee6756cafd009caefd02b0892715ee5e47ae4831b5fa5ad9e2e2c3ad55b85557e89dd45a6a5707d83849e5177cb695732ea51914a8ab1a09a092e4bb8b8e6709
258	1	394	\\xca570c3eb888257f8405c53aaff55db386eda7350b4f23b492ca6729f1fd484f842179304f1b93e2d156b7abb2148465590c7fceaafea42387b28115a5d0fb0a
287	1	335	\\x194afcbcc480f772290884b6170ffbf4f1c64e615bd18c9b73552874a4e0904cbb0ad1979a5c152408faa14f0c7d7558a54b29924259f80b4fac853b6f6e1e0b
303	1	72	\\xf964ab03f0fef5a17a6b05e0b689594d2790768180bdb924104795f2a7391143eac2a7186ab5f6a989ceaae712ddd152007e6c9dd33b3914e93b6cc144a46a0b
335	1	271	\\x7e4e327887fba6bb3a4479051c718537105773216a0962182679bd020044831fde934baff60691e6217082d8a5bdc40070a89ff06ac9e29a64cbe252550a8302
355	1	410	\\x3264269e77f2d10b7c600a531fff6d365b91867e71a1838b8aef0de59adedc7ba64224891e29e51ba0730f8d9443ff236014de0263891ecbfe70861d855cac06
368	1	412	\\x1d33407b001412ab93da245ebbe08018b0a0ddec9d9fabe42089cd5b01af2212daf41d36ce29d116783b8b35f41633a11cdec67a34c192dd50148611236dca03
396	1	324	\\x4c272eaaad9d08e6b747bc679c951ee92e55823b24d7d3625b4144d41c3da49d20e0af309fc7b46816ee3e12449142d327d5501043c1153d5ae4b381f0eefd00
411	1	169	\\xa7c0b992a1ec8677e8c20e121193cfee079f6e3b329d5fb0ea7de461963b0bffbcc3402c4e369c447013d3c5260d03c9fc182b1b3adca7b6ae28bbee34ad0903
165	1	131	\\xc863caae4432226a2b78133a75bdf5ef2e302410c6fa341f97d537f845e5927fa7370e7631266b714ff4b56adcc920912e1e6b61a4818e69f77d680011eb6607
184	1	36	\\x3c2e49edce699a2f5b044c26f71073342f74c076b9abc54ae9674f1e16f6107d9290b8f565f1821fea56967a7eaddad69cbdd80a2decf0c65130652853562c03
212	1	280	\\x3eb9eb5957213a3c943f1dd8ef9e095486bfe21fe38c39c7d4cd0b6112c79f3d0368462c0749fed717a7fec6f55e2012e3cd4243479a82ed355db7f4204da103
238	1	213	\\xf2b36fc20db8f47fbefa3f7f2bf28f277f7ad5f215d4a0d5217942d9c3276344d4e217dc5109e1e627974f46cc3db156333384907f26a0cd99b5a90f87d6da0f
275	1	99	\\x291bab3ac1c897837b7b277102327952430f1244fa6d38b5d5e255dd36ad2afff482f5dca7db8b68647e59e0895f52c5156ca0068ccddca104b7703df6c7c008
297	1	158	\\xc76efd55ae59afbd055102b36bd592b71faa396e131a76b549b732b6d04732dc1f29f0cbfba2d4839258df7afd216ab09a7ca37b0b751c7878530f2eb97c6b05
320	1	186	\\x4fbd16f4758f02d51c85651fa4fc31b4991d40130cc3409b65a44b2a7c911d9ebbadb6fbbc0502f286a46e85ab2697d3390f666b8476a30d18997b468fc67c00
342	1	136	\\x8b9c8d010a9305f603aa32397c0f7b51d77db45f4e81bb3e432d0d1e961a9969229ae36506d798800bbfa7e93f4e0660b487f286aa175ae887dee0b50fc0ce0c
367	1	255	\\x7a03103f9bc86c2e2201764285b53bbe425d6bc807cc4a0f2ee331b9dddc9ecd2cc488906d6c61b30aba1aedb2e3fac0fb3eafa0705cc9faafef7a9a55055f05
379	1	3	\\x08bea60120ae343f9a437428b8fc67382c3c34ef8d106346b69556ed873faafb723ada84a6fe5fcdc0e24918190f405044da0110c45138a290b4b2e954406d02
389	1	157	\\x8bafac08696e1f81f11084b05d0aa79d5808db3b66142b14837fecdc901cb03fb55f56be563bee013faf82208da4fe50afa91e0344b39e45012e8a01fc453e01
400	1	407	\\x8ebf66f70c2864728753b4b1dd2e5dd5475c69205a06ec94908c93556d80d2584f9641e5992d485cb62d812a852e34f38b3ee06f83a365fb02793fc288e36a0c
422	1	13	\\x48383f6db7c242384dfa7c0a4b019bc4d9bd867166ae3b798c7be66c3916adea42700ec3ec1209814281057b69adf2523ef50acb57798e0a3233a01953ed880c
166	1	338	\\x8bd80009b2e71096ef198f49f2ad3a06ebc7378073bfc11a59bfb4082953ddfe6e16362e23418bc0541a9a1f2817bccae9edb3bff8b7d98a7acaef2e3a989f0a
173	1	159	\\x3f813fb207df9a6ef0e592135f667fff02d7b80e001d9599ac1e61daaf122137d289bffde98221956c63375c68021e692669829c0cb9b80a2c0e856e986a6d01
207	1	229	\\x19830facf6af8d4eaabb8a35dfc7819cc7d910588ab1949118b39c3bedc31f7dfa7516b2f0bf1d9ab665041ac187783d77fd86f700f26cd97483a0d55dde8400
223	1	259	\\x05685be5a9218e5468d1f4d2ed474f3240f628b8b36b0377fd8610292e864047294bb45c87b2ee252fdfced8f08cfb99c1e2dea84fa338c23c1618815b513905
270	1	345	\\xc20cf09ec56e2b1a000f5fc38ceb0812277db5cef3623bbfee3665eac28067a3e288feecb9a5406a33cb5eed6b7294d1c301312dbac4fbd59b220addcdda670e
300	1	135	\\xc7be552bcac747da6e9d9f072e81fd8c1916564e9a571279ee6b2facc54ca739f5248dbc929036e70858b664ea79cd3e2f07f4a8d242c82b19a4be68e70bee03
364	1	244	\\x4bb6a0050f0282c3c0efa77257c83573d2f8fd327ed86b9d78c9eb8dfba308410bd1d0d593e884504e398c0943a6dadf0b13c854844f3a9ecf58bcb6e2517b02
66	1	214	\\x7b7a335fb9697afd0d4305b6c692591222d0e97ff430e7695ffcc3b73a616ea7e6b488d842e79bac1c147f3b68000130287c7430e7f920f1d2966849c1729f00
79	1	282	\\x0e35686e1f89b745832ed0048179e7b09f455bc77f29298340a7cdd8f01db3fc8e430007c4e319ab3d9f7ad9fe3ff626a596862a18d1c62bcb9b121614aedc0c
88	1	61	\\xac01a47c8eaa6b9ff8f4b148fa3076bb4dbcfbce42c5e5d9ab575c18c36e80c0485dc7a7780eab29ac034deb2bd8ef75b6168edc69bb8f51a41d17babba7460a
95	1	357	\\x911b7bd88019190288916d7348e9a78b30a13819ec92de62b365726f39650c0afedc6e66d5225fe8adefa6324cf0582a5ca85815473aa31b3c0a5a5c0e5d7302
103	1	180	\\x12c92761176c4976fc642b6429f9a92a6ea0e485d3e869cdc91157524ce0fa7c74830f7e8c4817034fc95bdf4c7b507707ed1f06083d333e9f28a76931f35a08
109	1	224	\\xea3860f5fc0aa33d241dc89026763832824bd7b7e3650c239099f31bb1026b8554fccf7c83f8d77eae7695329559940db8e668c04d0d6e4261982b456fc55c0a
118	1	343	\\xaf26fbfee7a594ab871f8ebf1b0b2c034236ddbda0741b2d3be9920c3c77862eb6eacb91b5d6bc9301f7ec4970e9a86c885ff51ff0d21b4240d477df6a707c0b
127	1	288	\\x6ef34b16c64ec3ad218e2e2c3017624ebe489a092875c36a9fa938e42597592b8b1cf3dda4ee6102f0560ae8907ca76e2c9efb0bb7c046aebf052413a509f100
136	1	284	\\xa53241d8eaa88b24f1e77d5d658e4291f5f5695c5f899a05fd46da2495933d75e768b92e5a8948576ee1b5e5ea15b3d08c7a27897173f3346c2db80f138e290d
168	1	2	\\xebc99720172e529976f1573e5d32e9dfa2fc934d2ff733ed4b24b793cac4b6311fcf77de63f6a349fd400e444e2920828110c3023dc3b4d4c8320d0cf0a4ed0d
195	1	215	\\x174435cde99837a8d209c6162b8c8ae6e3a01c8b8ad783b61d2a2cad629cece5cc78d95def3c2492762a853b1bff358359ac2b83d5917c6f521df8b0cdb7dc01
235	1	205	\\x82cbaafcacd804b713a3e0b6cca4448bbaf925a5a7cb3980f3b8b68d44a52bb69cdbb5c7f7c685ba52fbc78e679b2371ee547127f542c6695d4f16bcd3508801
256	1	52	\\x79d4fb954f8dbdaeaad320f63767c3972f5e54e4bbe14d32b79e032056950279ce26d6565bf01264f83dd33f0c8db7cb244a557d170c1f00dd2a6cf7818a0103
289	1	386	\\xb5f6b73abfdd840558a28e9d3ef2682e936af7de73452597b8c2cfc9a63369a3030c0148339bc0a920726f269482f9e80d85a5043596748b1e40081f5b666505
365	1	382	\\x7729a24db6fa79549bd08ad508d5688a28896252d5db7ca6376a17314f1d78d25c9f4488b87252de1cf80690e60805d52d0beba0a3e09996e64c06fe3ae41a04
390	1	85	\\x77a18e0ca48dcd1e2fe800c10f43f204144f9c5bf6dc8fc589d3e6dcc5808f47039c88bb4b6526e3124a04138ce3aab24a715ea083d4f6832867cc577630d70f
414	1	64	\\x22e42ddbac9b94df811231b6412dcb364cd6ddb88613243331cde0b2713579e27c040697acbd045f32781ccbe4273acabdadd6271a5f258b5315ed5284856a0c
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, recoup_loss_val, recoup_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	1610135007000000	1617392607000000	1619811807000000	\\xf5da9fc6715d22fb4ecbe90d115e4649e179b786545e7947dc4ffeafa65935d0	\\x636e8323983559910ea6d8760ef4d045a6f30626a30bca88ad6ab3860136e8a289270cb192924ec9bcf408acd5799c39917944285eaa7f70c34fa7cfb5d5f109
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	http://localhost:8081/
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
-- Data for Name: auditors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x307f45d0c6562825935697f5f8d933068f98449e8097ed5054e6a33d81896868	TESTKUDOS Auditor	http://localhost:8083/	t	1610135013000000
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
1	pbkdf2_sha256$216000$uK3bnktMGnTq$HY4c5jC2duBvuSc8cA0yJDukmJBS7Pw9PLxpUnEjqE8=	\N	f	Bank				f	t	2021-01-08 20:43:27.527324+01
3	pbkdf2_sha256$216000$CMyG7LdG5WPJ$eNHvbOWZ1n8/IfT7UMYgGGK2GEKP6XNZaAppJOZaWUg=	\N	f	Tor				f	t	2021-01-08 20:43:27.699062+01
4	pbkdf2_sha256$216000$9C2LJzZBUoEE$hAO+iKgl7SBV+iI23hkjDd4tUwgP44UxH9non/9pwpk=	\N	f	GNUnet				f	t	2021-01-08 20:43:27.780124+01
5	pbkdf2_sha256$216000$w0h3ok7xgGwJ$upw6x+/CqWIwueJfy0s6vDcgapasmjCwe1zsx9xEpBE=	\N	f	Taler				f	t	2021-01-08 20:43:27.862706+01
6	pbkdf2_sha256$216000$IOEF9OT7wfvR$hTqcN4cbX6BGH2DDJ8UivaO8AFfSFsn/Aey4JplAx64=	\N	f	FSF				f	t	2021-01-08 20:43:27.945502+01
7	pbkdf2_sha256$216000$2lvKgZa1SgkY$AfmO27HLVEDZXzjrgP2/Kx71cCn/Z1Zu3Xa8mdHON3s=	\N	f	Tutorial				f	t	2021-01-08 20:43:28.027317+01
8	pbkdf2_sha256$216000$azlqcluNIRnn$Nl1IqZbMpKz3FJVsd3GkuqhCoaEOSKiYx481VAfgEoU=	\N	f	Survey				f	t	2021-01-08 20:43:28.110061+01
9	pbkdf2_sha256$216000$CIk9EnoY5EFa$gWi/g5ICyPnjVp5TPgJrttHxLvxglyz71ftADlB5Slg=	\N	f	42				f	t	2021-01-08 20:43:28.55795+01
10	pbkdf2_sha256$216000$nwPjgDeC1UcG$/g65xKvrMYtGrNXeRHgMChNNc5hH2yc69BD6c52y0iw=	\N	f	43				f	t	2021-01-08 20:43:29.033074+01
2	pbkdf2_sha256$216000$uYKLNodKdo04$IzXAgjZGnCLAdvQ9a7I/jGCYDhtN9hkWnYhNlARKqJs=	\N	f	Exchange				f	t	2021-01-08 20:43:27.617814+01
11	pbkdf2_sha256$216000$842LDGQIIFpp$sWUVEkyWoKdBaSJaLtMu6qpTVtUNBfCpZWuJ75jBjTQ=	\N	f	testuser-5Ipb2pS6				f	t	2021-01-08 20:43:34.416168+01
12	pbkdf2_sha256$216000$nTO6PcAwpBRv$j32Osds7LuE34kGUycqLEMrMBT1Q/365QFZjz1NLa7E=	\N	f	testuser-BNDunpIg				f	t	2021-01-08 20:43:54.192689+01
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

COPY public.denomination_revocations (denom_revocations_serial_id, master_sig, denominations_serial) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x007813a7401eea6882fc36fd5609fa8585baacd40b9d2ced6d903ae3e94462b08f673b9717d6706193f1669aa19ec85efcf93a81d8a940d57af34271f410bae3	\\x00800003f17dac1dbc6812afe8fc2b799407f29c7c87558c755790e2a4c3acf2f1f9ca210392e6791a11592573e4ab6ad2aec69f3aa85af8ee35b3fd16bae41f40a274a1d751582476c3add51ee7a988cd61b4bc71767a2d45ed162e1dce4aec826684669063d401b46d3ee06514c19833f6a490caa967c6b7293074007ffdb8c9eeac9d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x475c1a582ea96c7877e8cfad4bef8b4ad5bdb1b0657b937bf4a3288a40d4a4d92942ef6d9c3618afb4823fb9731d4f7dc7cf60fcd9eca00243fb44eb62e41303	1639755507000000	1640360307000000	1703432307000000	1798040307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	1
\\x098c9e3a013baf08ad35314962f78d22fb0e1a9f90b7f27603868303928a387a8a1cb3a30b3a5ab528759410c4ec3b198e4c5189dec4733e1f6e421137ec1c40	\\x00800003bb89ff7aceb03a78747068d76bbb37ce3d1e1c2f60c601d9be006d12cb90720f0133c9881a786ad5f716a7793c27121f4a3fe754a6343743f921a53758c5c2b20016a113a3f0ed77df12c994f01092f76adc7a6e16c350483cf8e3032b06086f0e68c18977cf92b4da155a0e913628d372675539102fc2a2657ebff6e21840d3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb608dcbe960f0653f6a24f682b3c0274deacda46157be2f5ce2c830e77d4caacd0d14d08c5145f8703ebf8c20a86b4a5a10e8fcea224539affd83a5b82814809	1622225007000000	1622829807000000	1685901807000000	1780509807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	2
\\x0ad87e150be38d645a4e638e67647a838af16d174f909a82171f5c7fb19dc6e7f6a1374709c07b7aa7d745bb3789178a82b7d7138cc55ca11e74936657b46411	\\x00800003cb1dedabd6730f36829eac9c39ced263c195717e0180ec05e7bece10d6561efe38b84e61aee9531a08345c1d2314314bd3531c6e946dcf4989416ce9238c5e162bc90afb75e0eca4e4e3209760911883c9c72029b9bec5424e6f3cf189635c04ed1807bcf8cf70231eb197b1c9103f83c90f18a483def9828d88440be04dffcd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5b3493a4120634d431bd5e0d8a1e652c66ef4dbb452c35b854ed5841a0647dc0d2cf439843e73df17c42d76c41c239bb126b1f9ba9626fc9c1f82367a5bcab0b	1637337507000000	1637942307000000	1701014307000000	1795622307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	3
\\x0b108ae37d399de6a146fb4cf260748f323fb830f66cb2e5da368cb624f56887a85f41cfef20edc95b6b8da1e730c23a9a1546bd7638f5ef1350be231d95adb0	\\x008000039eeaafb2852ff9a4dfd3773b08699de393b12cd06b45cea0d0c2865b31226d3bb5478e88d34742a20905a7f3b92ecf69caf8a9459a75e780de08dedce996646ad7c0af39901d1f68864f98762f97996437ea03dd464cc40c31a0c49245709dd3ec9afd969f4e2c2349237e92ac246a2fe284478ca18c28b8568323b083dfe3a9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6fbbe67282b88c9dee441b5f8f3ca588d152f2c4a384ed17c9ff54c8fa0b1707faec355ab1070ede0e05386ae015dd4797269179522663d1873e52bb8aebb504	1635524007000000	1636128807000000	1699200807000000	1793808807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	4
\\x0ee05a78d17a1277a711ab63b0e296bdb74b700b9d2b9b5dbb685144d5e8c3484c724f881796b78577077aab20fbb50c5b190df40a496068150e5e2f56426447	\\x00800003f3ad8f388f46b813847c075c0e1513f1182a4a8729423bb878c146e46834d9f0b53ad19e00b49323613ad812e9f8ee1f8940a22bead709206027ad3d6217b951cc0e26e63b2fbfc442e5da1c75ea9780ec9b71b0a0b99b64219850c2612523d92fbd7e7935354760746da3cc8a9829c8eaa5c51ddb7dea34599a88949a953f9b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd05178a4b16b4456c736fc055f650d9a24e5957809e5e3efc46c02211a7c5a8067aca1c06156118b600cd9075e90250e80bf1e2b3f630217c235b04e99441c05	1630083507000000	1630688307000000	1693760307000000	1788368307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	5
\\x0f14f33835a784a5f24cab9cdc74c434c20852ec1bc42c85ec863b4ab98f333921bdb4750f7fc0d4c870d8e738742a89654f11c01db19887a1e9e6e13cf15e78	\\x00800003a76ed78c939fa9930631c6879bacc2df6c7603fae39edb3da506a76916451bd27690c6b79d803e4bd5350c6a663ef8770b578fb5113e980615a6fd3c66f8501852eac13d11929cd43dc6c1156902a6f6e88dfdaf7ac3e7e38a66d8d68ce5c7994b5e8448f83350e40f9cc7fff757df5c1352c5cf73850e35087bbf16f19f471f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe6a6c17192c652947efd464b97843d0fdf86b360de11f4c049c7ff516e391e615bc04944011508a862bd639d9d9c0519fe21038d27c2d7fd4ee15c1fb0831d08	1610739507000000	1611344307000000	1674416307000000	1769024307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	6
\\x10ec1022da03d89c773b613098133bde3c1a89fea32b895c168fafad43b523ee8a8688c5c20863237c4a30910ee10e910131ebba63a6cf2471f555599ddadc77	\\x00800003c1840734a7944f05246b0363343b058ce10de888799fdfd5afd6041807625991212c1d369a1d72d7520ebb7381fd63727c750276f0095388c35177d910de6d6d1200713c3cc46f4508d8afc303b14e600b4f397bbf5445c6beb6729eaec9fdad1164baa242dd7f48c37f4ee16ce586a260358d816120b7c4bc0dc872b765eea5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x070ec16910a8766e2c02af9234567b078c48ccce8387a6dd51010a3f25feb57c78c4d65d1f053cd7786392b4cc763255d7255734ce9eda09ff19e43691660609	1617993507000000	1618598307000000	1681670307000000	1776278307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	7
\\x11d42d58240235f1acda28ee6b8e41448977783b2cf3d28eba42a264551b1f39cf665519bd63770ef262210ac6693a8f8fbce2b9a5093bc4cd367513ea429a54	\\x00800003b00c8976b2e20f2c66f895e8bd32de5abc27986e64d60f3213f9ccf0a3fc2fd24bdc92baf44e2343105475026db4cff64c4bd5712a6528ad85ce40b7ea8c0c9564d30d146798eb189b0db15323d12fef5f3bf2f0a1e6ec637a8121e2d6c6ddf80d4362243c4540b8f4fe5ba0ee7372feb6b498d978b52585ec832df00f5f118d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x20f2659ab6cef94d8ee75b274c43fa0bac3b28fe632c0e512655a62aa6ce09247a250268c1101471222e9ef4c4f5a3bb08ba02ed1ca2b3e247b26daa7eaea50e	1620411507000000	1621016307000000	1684088307000000	1778696307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	8
\\x13a482fcbdd11811b134091cbc553119575a23ad52cc5fbe8edfdaa946875e57581869bc57c3f7c6b45a04b4649d59411a63c6af628848d8c6fe3ef379ef7b09	\\x00800003abbb80226ee73f38affca2badb1b5db9326ef4401067097348a8837518f5a7ebf0dd250e23ee2ae512d42f088877cec51a5d98c958b854496b0ab5515d98034e8068a98dc941de28f31c54030949ad1b7c666a112b771cbf6537ff5fe1ea4c0d35f7e0b29764d42f3dd51c4c522644e4f16e0fc6e6d67e5b62327f85ece93fb7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x32cbbb15103ec2e734e9a423cc69384c92001b4a60c4ea377549fdc8f93f2adf94dade98cb4cbe3943732c5eb4ef5d21413b16d1becf684174f92c669428570f	1610739507000000	1611344307000000	1674416307000000	1769024307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	9
\\x14c4312601ec84bded2f71b3932975901f5c3708c5c9a25aa383a0dd601ee3f534b21bf503635168c4cf61eea7bc7596ade17fee75e80fad5082f03fdb86e96c	\\x00800003dda21cd033945751475c09d8c4c949cdd3352a2318a05eb95a115e8031b2c75a253ad99e05c8ac43a1bdd9f00c141f249836037d3f74dd69cbecf5063ecdf7b371dd4295ee84091353936b96450b3728a2166af5ea3b398a227a986673506c1382b8513eeb95adc5636dc4bdeee370d7d5144db64785f1861577a0b503ad6617010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x42a3e4945cd378fd15fbfe6f54eaba1dac5a498ac3a32389610ef8b695b3d5775a90007afe6410f0f9845067dc501d8200ead357cc79a3e73bc5cfb3a5dca203	1619807007000000	1620411807000000	1683483807000000	1778091807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	10
\\x18e4cd474b4eb68bb84e8fb992cc1d9252a11cb5076dfb63097db445ef50b2cec69cf9b28c5820fcb478d570b0281b75c768411cb15382ffca89fc9c257afdc6	\\x00800003b49ea5dd017a224f2f83977444bbb284d61b565843c98a8ba8e87a97605943fa57c1b403cad9426ca231c4ab90fc7c8ed51799d5e40424bcb29b2b76c20a4fc629dab6f3ed184bef933e6547bb0f79f138a14e9447a17d0852348df4453772fd24f737d38b3ba1f9038b1ae0e0c595cdc096495e798efef991233826f6370ff3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9e04f6e5306ad031ffb54410672a19ee480f2646d339a922b42c5590adf535b0c890635411d4f396276c1970f74d9c0775d3f4f67fc6c02631c3c31687337e09	1630083507000000	1630688307000000	1693760307000000	1788368307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	11
\\x18a4fc4a7cdc28bae55d99f3dc2c8a97d24045ffce2f6484a51fb94e1b36a580a9d1c4cf1f7900364e8334997802479648283decada361c15e02acecce18b0e2	\\x00800003d1ff042b5045dfb00025686f545b54055845ab6ac2b36365d012c67e61b9affbcd9e068eaf991926f9fa45f9e04e484b3543a7d9c787699475a4c4eb39749075ca3ff2862fa9fab6055e21719fd8dbeae98875ce4224c3322173b5dd9f365ef175d7afa953314ad908927c199a96bd7e4621ce05eb06ced2b75321f1c2da052d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xba077b5e9c49b01a66cfa77ee36bb4aa37423e27fcfe3805be86232bc0667d5f819180266476257f4bf4dc6a2e77b92d13c8a41925cf43df77e6469e9685da0a	1632501507000000	1633106307000000	1696178307000000	1790786307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	12
\\x1ecce1490110930f9b301e9cf798ba49c216667722cd49b88d9823db1256aa5136d6b1a59e013d7697a93af45611ee99d0e905d87f58d802e9725ad3ecfb5d82	\\x00800003c50879a3663e50f2bd028bb15727fa1ab887089665e0deb5904cd08b886dbac5354c805f53b09fda63cfe9fc4a8241588912d688ade8adf32f90f9f2cbd9df0ebc2a84d283318aa3810a4ca3dd1ccdb80302225777723a891f117c09ba1e7b9a3388f2b4b19ddaab8009ba4294388190f761526f1d930fb3e78e1e56bd497685010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x033bef5cb01a47c75689d237dd9a0b278433e629d0a69c318818759f06dbc2f042fcd7954db9f487f5574b1e4b6f2246d404c300299b288288670cefff96bd0b	1641569007000000	1642173807000000	1705245807000000	1799853807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	13
\\x21544c4523ee9c89767f6254ce0dd9220a6bb971ab7d0dd1dbfe290970b6d4234898a3f3970a2e7bae39899a6665d1e416344a607a75e273e26dfd6efa5ea54a	\\x00800003e2130d122dfd1ba66104d157d0eeb4af1b08bbc7b07af8d6c3cd2a5e6805d134dee1b8f65e008f472f0885142ee8c85d1a02c2c95e145274bf9e3b15ef5a3c6882dcb9cfaa5f95c3223f8c10d5e315b684ae01c10587b03a5e13b4f40e6a549567fac4607bd9c3c8c150506921724c0977163262c5e7f4f3d3c4fd27e90b419b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x776bd69b06a2131c4affc14a42247a34f45da5de5da1af6f6c1340f17d6c14d23e896c54be88ae8ac31aa4177b645d774226bd2bbdd4d27b00aa50bbad48780d	1639151007000000	1639755807000000	1702827807000000	1797435807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	14
\\x255cc2727bc52552c1631882bc4bfc83e7207d0bdf861153ad8688da2d8a3ab3ad0ee975cf64b19665ce07737345b02f12f28d0c5cd3899cfe614c4a46c95f00	\\x00800003d1bc5d1259c2b532a1e6fcce6700542b2a7f080ca4545ca21f5d435bf6895ccf27b37a7ef71e6b33137d72eaa67863c401b0e89f7ceeff90c9582d7ad9e2e9938317375a3d0c52a04b8e1c8eb0a35d812b3b6dff0d430412fc0c65febb524976912f9c805da7ec493e434b3dc197fb4d3a29d87af982124645fdbe80851d29a3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x72117333bc5d695b7dc16cebc35bbb1ea9725cb895fff533db76931cda11d52eb3cb9db8678a2a26b4033bf9ebea30d2ebc0d7db02256bfb643a671ae303030b	1631897007000000	1632501807000000	1695573807000000	1790181807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x27f47687fd9d0d944642865f24e84da567c371660d77ca2c792e8c747ea48fa5aa5bb69cd8b9d11513eb5d4043e4e46495aaa3d1d95bab022b590d88252cb95d	\\x00800003ce01463522b7952951004e309f7c3b344579fa132d9f65733dedee15c01ee0aa074f771b6728395ba27c976dabfefb33570738e64ad609384cd1198d421300bba3b92a40334c03ae09af1a16c6711d84285b6e407d85b66d9da2adb4277426fcc1b3549526ecaad5096f14b4de2260143804eae82395e594b5702320925c093d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x65f804ac2c342e18fc8138dfd0f3693bd46dbadf5073c0f532fb736fccb467fb87ad14df9e80d19933f7c221aee403044cbf215fdfba5b6b9d620e2f1757180d	1619807007000000	1620411807000000	1683483807000000	1778091807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	16
\\x28cc5e9a879fedc78f564d7a504dcb7991aa91221b7d89da824cd199842885b519cd90d46f7615cdb9199c6bf28e132f79b57e57a315b389eaf1c11720830e0d	\\x0080000397174dff45b5cd51817a98b3bad22f0d0ae587314026b21004caa222bfad3fecfd1441afc2678df028a8cce3abc744eca294a227d4dc74565f61321f7def8b1111a6e5e0b9d947cc7c06160d2606559a3310991392c3d185b40a9519e92399f33bf6521ca5695d66a9580f32eff87e238ede7e394776df3711d8e1c4514c5d7b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8025574ac0485a599edbf5cef96e8803d885b47e55ffd70decea59cf29cb6186be361e2c7b7d28ce2b4c956a7dbcd63707cd0644dd8f34b54fb6b960fb219501	1626456507000000	1627061307000000	1690133307000000	1784741307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	17
\\x2ac894433d92116a0baa2a7725fe8e2efc2671f1070e0605550d6a2fcd6129c3b32cbdc1e2c9e214893249877a9720a18bef3ab2e2006b964d53bbc358bd6af4	\\x00800003be177ed855f483a03559b07a350da00a309f3023524c14b0010c420ee2ad2f7721bd1a6a6442d7b40bce34b111de12cb4f399dbd4db2b99fc531ed5f94186109a956ab820e599e59eae675d6654bd1b796788e3be95df3cb34d8c5a69062f3d39c62fcc8601f88cdeb2f15ab14d270632994e3638a1a31b92ffb1b3204c6e3df010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7ea84f6edd37dc180436769f34f263c46745b50044b5a66c752732ca3bd21d8e4ea1867de2c46aa5835210f60d253a5f6abf48cccc6650829bf1e9f9b44c6e0e	1630688007000000	1631292807000000	1694364807000000	1788972807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	18
\\x32885b5e278dc10e8644c57d415751569291149b64a424f33b78f833a1bca5aedf4ea291cea75cc4dc55f3e5eea23c724317cad55cd35631bc3e4985968e6cef	\\x00800003b4be995776aaa59d7bd5ed609de6e8bc704fad5c60eafd4b03a6813f344b5d2e926fe90a24250039df129dfa58831e40f8273d0056d823f4d0ae46c6c61765bf9681aefbc45692379898e431fcf12e1208bb586a7bfaa4684c8290a51a859fb74c42f7426502601b36a6b4f27203ab82ff712f189690e112c26d67874865729d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8a22c2ec066b55fc39c71f4d1d919422591f5551fd83c08f6bbfd464cc1ce21c850f1cda9b9c9f86c07f758996b57b2b0b2d5ed98d63dc98592048d3ab610f06	1640360007000000	1640964807000000	1704036807000000	1798644807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	19
\\x33a0200b14101ca419896f198accb7e77024dfa350429ac9e5fc5e8e017ebd91a271a9083fd5870838ea253898234ab37c9b3407462f6ce3f68119b6ab3a6920	\\x00800003a735693bae0005401542c21298d3f4f44f93705bfd9b6dafba55c3dc318df532e13326372450afce9eb94bf71ba0d734c046ae5a449e225d9fbd8771bc1935e13f9443b58e6389e152525498d82430824b296b0b6391e523f2e5e3bd8aae4cac1d8f13156442e9e64d823d69abf8bd3c3ce8e0c02c6af0914fd398454e375a0b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbdd9e40a4d1ee3be17962a78c5748ec3071603485560685f5fcff28dfc71f286804dcb944f1bcb9def40b974d60555a15de2619679e589eecf9cf6db0bff170c	1640964507000000	1641569307000000	1704641307000000	1799249307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	20
\\x377cddaeed67829cfc0954d82636a4cb7d7b054f9d3538534073db41e543670945fa607fbd4de5a60fc60db9bcc27d7ea97a472e71f4c129de37888b3acf819a	\\x00800003aed29457965e32927d92b6bac08ed7fe58101149b109860c11807609fcdda4aa96c2bf6c465398b74a0ae23138c7428cc26dbdd2a0d5ad2a795fe15a59063821c1557eb385f8f9a3da81d98c60d4ebde341f13e55a847074b03355ebc1fb77161e0c59a49b408c939ca4f38e62422bf2b5e00d0c86de8323d7520640915a5ec9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf2eb7a1bc221ad17d5ba4cc599bae86b0e40173feb6b797edaa8ef3b640cf29015215cfb402e929308f1d5e42b320d20028b96c96efcd90cdab94b2ab1db4f00	1636733007000000	1637337807000000	1700409807000000	1795017807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	21
\\x3bc0777b249b43f9ab66d2c9696a05e639c270967915fc368e72b8a946623a7336d5c5d5678ecdc482ab3cad8aec5f9b72d861b6936a5ec169270d90a9844afb	\\x00800003d6a67f88e3f9c4aa53d3b139e9be9bb48714a5a044b970cc6abcd7125b65ad7d8c6e2df102f8f01bc5d205c83bef9d9ef34428ba68c884bcf0cf1c2ab4f02021f98cff96ea52716319e1f868e09398ee0cb7fe5d66bc554346b9fa4cab9396568bb727156fbb7893c67f4d830f3a536d59fbf02679427b4f3f02c942cf1b5687010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6bafc1bbcc330039774d0005b22a4e26143a2b19ce8911a96b6b0f14159bbb0842b7afd99ba5caff105ab56e649a34fc01250935fbae6851d89f5fc0a55c970a	1633710507000000	1634315307000000	1697387307000000	1791995307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	22
\\x3cc0b81556d6f5b28619fa285383b8b58e23b190d9399af984bfc0c37295f66b2e0cdbe31ad307df5f4431d72698474d8467ca23cec2443d64cfdb9c05508946	\\x00800003a33cbb9e9f8993af0cc346031aeffee84bc08e9ef2a86901f063743ab1edd130cdec81b09cf50e790aec1dd98ee208859946be94f24869ca78c3d674b604ecc22de614b4eeee77286a3a1648e589d9015a1eb6d81db78c3081a423a338e90db882d2e6dd979c3db1cfe18502d8d8817a11f1dc446882dc1ef2c6f76b59875a61010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x62ef666578f5bf973cce09ea30b2ecab3a65072f632033970b7307b629e68323ed383b2197b8995424b0f5a4c8dc9af6832a3e129d6a1d4a0dc39b6892fb3405	1616180007000000	1616784807000000	1679856807000000	1774464807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	23
\\x4088b4fc9079bcf9db3c89bdf362e0480115fa9d9280f354f4d384120c8fead0e644530bc167e646a11f6a6229180077251ab842d0e83a51e14e91a68f170406	\\x00800003abd6d884371b91ae48919a0af2ce1856def36a378c5c2e313a6c2243403e6d38483dcb5d1416b819d85f0bb1a600ca16b415227390288e398d65bc9fee65c2a42ddd8c17540176148ceaf9a9474663545857b271f545ff178388e4a61a24b718d2aa211841f349e96492534bbd3f26a69480835ae6076eb46ec2f712fc0b24f7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc21dbc1d555f163d0060314175cb37defbdc22899f9f36d446584933cbfcb86722e35a52ed223ac938986364eaea294050ff92ada2b0f3d5685620866385ce09	1611948507000000	1612553307000000	1675625307000000	1770233307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	24
\\x4acc69779b9ef71dab94c07366d5b71fe9a805b9be0d238091cf2e18bc07cde3cfb144c6f55ef81e93ec061971b161a7ef33661d35c3cd8243c6b9f6cbc39a29	\\x00800003c42d4dd36d97e385ff5ccdc3ca0d823c053731e14d1ef7fc1ad792bee16d4d66437a15a5692d70630604f6303da7af5ff5c55f094f3c5653f77109bd1326e3ae05001e8cdf34f9a63749df189261a185fc797e48c6a1dfe6e756a9253cece4a167c53f730d80e002b214312937f72cd575223cdad24d2010fbc4945d18f6d415010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1f60ecb9a0692d92e9a89dec57332c59861d84c6bb80b8c016cc30648a39d1326f795164b44117d9054274bc172134e16573cf8d968fa4587b76a7ae9b5b6305	1620411507000000	1621016307000000	1684088307000000	1778696307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	25
\\x4c8c0f28cb4034c9245ca454a4410fc04ffe1344e1b5c7a76f8230f34ce4cd17f62e53ea01134fe1043230e3bf0a0b0b17954076a7692997882cb5a144ecadd1	\\x00800003caabaffaffc2df41cf8d93170d28d2ae274f3cdee3bfd25fca331ef9854be4111f57cc200dfb4c95f7982ddc153b663429206f89c2dd3d442f194d5be93c7930e5ba00311b942d19f79d302132090269745ddbdd02f605dc808844d719f48b9ef2862d79e1cc572b288dad788f7d6a66204a914847b3a4270f6408a07b19e4bf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x33e4f6ab96502097c0a07314a881a6af2cf1cb00b4afdfa69aa126f866366d7ca224893a488ba59f735c8b28141c83084168cbb3e31688b7c858628587eb7b03	1610135007000000	1610739807000000	1673811807000000	1768419807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	26
\\x5860d5d37ae41061846417858283914cf549311cb96d3b149ab4f0835a425ad87afdf1bd78f4fbd1618add93d6d52876863b51e7cbbe2e6cf36d05f1255b1285	\\x0080000393228ec70e76e644cb4786c008584e39ac197578ac1c05dbc870efead989c22f48c35cbd5b45bc0f4c1ea4ce915e049568c153bb5453e86fe830f2ba228c3aee7998fa27cd7cb906b631b1f1b425a9d5b2b15db0c8488c2f53abc1c5843ee4860dfdf92c3165b05f7aa892a2ff3a281a0e81fc8ad7ebb07ab66a6c9fee21951f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbe33ce3c0559a0707b908a2f27101879ef5b3cc08a26283ff4f645545069e01b7f2f32b3ad7a91dad627096f965f17ae04f8276fb4a94408c5ba821ea8d1b106	1627665507000000	1628270307000000	1691342307000000	1785950307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	27
\\x5a08fabd52849051280edfbab1e137bff6940c29e376ec84ba0a608d5c594a4091a7194a59c49a27efd37546e55196eefc23cb7ba3b97eaadaefa8f15f3c7453	\\x00800003ae960a8eeb678394465fcb552999e295aba127fd0c97f405fcdac558f44fdaf44e9877393469f9b79f05975df65d1500b16b5b843d5a7c4e726c3f71520b1fabcc7e4359a9371556f18c0dba619d38f58cccdf34a5720713af1c150ceaee0330dd1730b0e29edf90616dee0721c7dee7e4d76838aea2f3476640ba3c8974e743010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5aabb99ce74d561488fb7931bbc8944b7f0cf73786d4c2d6531ce53c9351782291480f9dbb916c55c098ae06c92aa6b6019ee823a2a11fd75d092c1d8745720b	1639151007000000	1639755807000000	1702827807000000	1797435807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	28
\\x5a1057fe299258252b193683cd7025e11f03bdef3e005cbc29a1df878581b7128f6bee86df722e5d87fb99ef006c74ac6fc26c4d547387f3f14b6b747e3447ae	\\x00800003b8d1159f514b71e08720adb7e90fbe70412d2111a2599d784b6e4fea164253121814b57d4db19e6412022a00fb7235cdeea07fb4aa5b27286facd8571c115bc7ba7a18363d26e213b9c44f2dc4966839be7a5a9a2407c204ea4c6bcd04043b6d5433e59bed5ed2d4d000fee923e75c0f0aaa00dc07ff5dbfe1b6cc4cea9197db010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2ecf60afffb4bd89fba4243ae80018e5785da55f6d64e044515263f9018c35afb121f8c36b448dc0b47e08ccac97e24b32f245a3a140f096e6e22a9c4c350402	1610739507000000	1611344307000000	1674416307000000	1769024307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	29
\\x5bd4be3df66271883a2250036422b2e43899f081435db57ffa71f459f73fe2fb4d34ab4ea274edb5a89db2f5a818533735e51f4bd01bb2a2dd1e8a5806cb53dc	\\x008000039f61c1e321633fc1afb2e26d59b436a00413e421fe161e6379bfa4de6720eba7c3ad8d6a7332a3312b6a36115c838105a1a7181abae259bc79326161cfe8ca096d71aff700d9bc0d4dc750dedf96f39f576a4936de4910a869f3b9ae90671417b7af3eaf659da6b4cf650d942afecaa85512332bb08b7b092808d50e76c736e3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa2192691064a6930e9b46403374c24847d39ed1f2649a791484fa68f792fe98de3d644d7d7a46b094fb0983280e4b535659a46c8cfb3b73f8cd5a1407c9a1204	1639151007000000	1639755807000000	1702827807000000	1797435807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	30
\\x5d44268f95199eab847f0218edae0a4ddc254944681ee652f45b6c7817d7a34157de19b3345c1f27fd6f3a54d69839ac804c1c3ed64a4626c5487856ec5bbc55	\\x00800003adef4357ee909da6fb6e9b71a48d5200835535ca756bcc8e39190833cc8458c08405b1cb31b9e9c0551cf5c1ccf25d5a1d2c7a612e1d544732317c1b1f0456f16e310def2c7e7009011b0525986d1b49b7e2adf41bc25121acc607b58c508d555034526f664a02bd04cc9b6966d07e04da393a7977615a551dba8f8253805583010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1f263db2673b315f036d388e128da57bb85a74c6f4fb07208f363cd137cbdf417ca87e2a2a5abc43d383c63011a5fa38e207840bab50caebe9f8d08f6bdf070a	1611344007000000	1611948807000000	1675020807000000	1769628807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	31
\\x60d06b8fb3e21909a8af2e1d43a3f2725673e4156e5fae34ce75a0afcdf80c360468de55db2a7baf6791b4cc42a9e574b2ff471b3e705cd45ea6ad6fcaca9baa	\\x00800003c14babfa904fbc30b01e1544ea5b32c5ae9f472fe63e1b9451c4a5d0a7cf673264d4c88e2ba67da27dd5e821f8bd15dc18815c31490d1528c2aae2480248150e2e1d2c7f8ebbbb56903530f5afea3a82492946b465e651dbfcff9da72185f92e1627da1171240cd61471279f581bfb5854e89d5e7319fa4d62714142833b1277010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xdccfab73a38af275a5e58978e574c32c9e741dec1938ed33f5f8e88e7f0807d9b0c9112709697df77ddeec1d2fd5e9820ff0e7a788c7e5c08df96a3242bef307	1626456507000000	1627061307000000	1690133307000000	1784741307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	32
\\x61ecee2424413941414ade15638d24fb9cf3c120398d885bf125c21e3589e98f874ae74278596987c2ba67e544992278b6b2f170efd926eb9fdd0d2b733071ef	\\x00800003a47bad6a7ed8784857b3680611ad943a03a807a2ff3919008c349a93573cf58051195ec1bb9a276653ab9abecd0b979b39b308b9ebbdff0eff5c5c6a47d8ef3c2bedb5b2cbd7deaa35fd25e33c2de89a72fe70f9da5ab44a7d8e569ddf1027aa8dc38fb91d8e3709541747d76461cfaf2be150c5878042adfbc4793d8d29f43b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8420925ea7c0229ae8dd12502a9237586e7a35c8a7eae34ffc3e4ad0bbbde0fcf1892da70865d564e93918a6ca4687329c94bf04d835645387ac9a898b33870a	1634315007000000	1634919807000000	1697991807000000	1792599807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	33
\\x6570394e651045e38d3fe83270e1c9114afceee6d84fb7bd3a0799878f828d72370cfffaf3a505adcd276419056c27b394b0f34eb2595e91a8fac3db0756bccd	\\x00800003c2b39c40d274cfc91ceab3bdfb51945942ddd65f3c87f54060e3cb5482ee986a88938cd491688d32a5306d0822a8674526cec8baf82cd4c81a5355e0ef2933a663889c46817104049e53aefda9be36357a2a62831352cf8f8fa48890e58e55594d1d704570c5926fb3369ddf885a42a03da9d07758ee5cdace837ab66d203e37010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5532760c46dd17fcba0486c04f527e25446e9110f191fdcd6177b539c4c8cc1bb17f32b3d92ad2f6401e6c3df628841c2f363f634ce37178d7ad5c75d45dbc09	1637337507000000	1637942307000000	1701014307000000	1795622307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	34
\\x74c0c8c865464b8aae4535ee0e4c8ef84c859fd7bab1fa535b9340a42073b5dc6178d76ef786174e4f8126eeb75b2b98af8c435097615d89627beb05bd05ccac	\\x00800003bcaf4c2a593f86f13657fbb5ef895783452dd572f3934f0064945651d460c7c229e59fb3d0b4ed2ea11c7eaeee11eff14036f16bc234cb1a1d0feeea89a29dbdf96cc96e598e1b0610e6a22a42cde214384ded9ef90b4dd8ebd9dabe953e98b19899f5ddce7744e588e34139159caf00202061224a3329329e00b14807f56591010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x4eb207c7d503a9835f43ee93cf84345770d906b8df894464ee1bd558e02b75d2575196bbf608dd039af7f51d0cc64ce2837b8083d9004c720da52bacab9ed10e	1634315007000000	1634919807000000	1697991807000000	1792599807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	35
\\x749c74b247b0ae73fd9d4282fd52c4e828830d9dc109509a38dd205dfc8028a2b1d60814a2076c1adfccf898dd61600fde666ad22028b8b03368f03ff4dec4a4	\\x00800003c9807de87572c9b9f027d839ab29cbc5ebc4f0a0b601fddbb9823042c68e44217ec7083004c8edc6260f3e0406652f858c1600c2d88694e73ccd7aa0fcc31d683fdc8feec7b9af0ad0d4a4a1b42f682e3c9f36e5f05a0e58406b178568e2b884fb13d9839985c9aaf028f51ac8e4fca9a38563c8e773635881cf792514a2e447010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8f3032088d6aa7b9a61a0c36a4a177832a1f6adebdd41c20f2a24fb262dc0b0b0707597cd1f4200310fbfec7a5cf582f778c194d5e391856415482021623d504	1624038507000000	1624643307000000	1687715307000000	1782323307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	36
\\x76b4bd22786c3de605f64f7bc8384a25a6f15c52ec1eb84366164a85de6b1ee6a7830ede2ff68e25aae653f4ffc87b5aa6bf6a10f31d8fc991569c08d264098c	\\x00800003df0bb13632fba1f43b2a66bc0949386cbe7ad697f2afa1d547d06e803547a28052fb3d00d870091d645c5429ae6d70e62858176da7f4a94ccf10b7ff4801cd91b9d4a279ef4c616f47efcfa4d10316491f8c07f7d4aa6127d34841c24b9f24f64f4a1a9797481f43c4315de7ede198f81f256d1003cd4a90719c0e063db22c53010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5e0a9545525f0b1f34f0169d152c4158ae0ca3fa0496a1060be58772ab95fa882c4d926f0b5950dc77c2518b3e3d4384172f3753ffcc7f8728d25c76c834a009	1628874507000000	1629479307000000	1692551307000000	1787159307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	37
\\x7684b5debdbe2f4d54de043d2645c08cb410e3c5ada558603bd9c5a62b89b0bc6afa35653dc50f27c7c58378adcb06bfcc362e3adc13bb1c31fce8803b6f65d0	\\x00800003b8bdfa0951525245a58c5bea7bdec154916fd15254db49d983834ff77061f9a1c9e29253c6f4e7cb5c21a12f6819a1adffeabd4f177034f7e7533b6b102beb7efda31996a25de3a2e1d4fb7ee2bc550fbaa2ddf9494ea464294a6d959117d91114422345cbe6ec0d689979130064f5431029b890d193c8f8b82f8ddd7df3ed21010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x36c081fa5b62a1495db5db81bcbffd53b89172809914d438974e67c4e2546b3cbf6906e7be4d307c7972cb71b51ea2ae930e0acedc4f5715bab3ab4421526b0b	1620411507000000	1621016307000000	1684088307000000	1778696307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	38
\\x7cc08a109e1bf6a229c0d0b1666ac368609ff0fd3c78ecf324706cfc37eb68160a70f1f10872fba95c098a4fd4124b7882522777692cc5619225176d4c557c39	\\x00800003c0d22d1980e1fb2f510c750e4f13d58020745a002164f05e0febf8dd4be87dd67a8dc530b4a06b151ac547ad35a41d6fe715f326ea5507841f056c602a16c021759ce59b018b957d25cfc1049234b4c535f9e9276e83e8aab050872eee505262cb94ea3c97cd3fa2becbd6a2617e35c7c52182a8e9c4d09c0c542716427773fd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x25dd8f06c83b945d89c2a75c422a76dd826fd180b2231348c98f94aa80be9e48bf9dc9868f8fdfd1d3cef90be12c02c166d1a93a6e829f2683ce70b4ad907a05	1620411507000000	1621016307000000	1684088307000000	1778696307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	39
\\x7e2c380f357d28ff2fe406e52250934102f88dbc19fe9de2124ff53c796515c57af91cfd7d1d373214d0bcac63c5a2eb5dc33681ded530e2a58e63160ab13bdd	\\x00800003d0d538b9991aa992f7add1688f34413a048f91c22f220e54dee99018f3ce15cd117fa96b4f7f4b9e6d87c60720cecfe4f233915a08e073af4d4b6fe604d1b206fedec3873a3b9b23fed17e046cfdf238f95b160ebb6ad34e2652dbff0f883472a793f9a74a429b3972d76f9abdb50131c948e66255927d9aeccfd88a78bf87d1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3163b676740ad1efde9cb8ec31dcca6879dda2364db5dd14ed20197df4f4a2b0dac193b0b9ddfa61184c0b614b10277260abefc7f126b3ddbb1285860f430c08	1632501507000000	1633106307000000	1696178307000000	1790786307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	40
\\x82cc1f5f7e131bc6aee8bc32734e6c91fe12991927d275bd281e36ea2d336bbba875d2031c88d04478310a99a1087ceaa59f018c2b8cbedcd10ddf338ec41fb0	\\x008000039900a51088eba454678fb17b9e118ca78f30df434a8a95377be21455f4b798f36b1ae5da6bc734c36be2ffd83e7592846154557eaa10452f4ce691c25a12fb53f930b69e615e0db9261289443c6e37cea968120b754ec046650de099ac529f2df89b846b089026532a88f00a96dcd37aff7108ef29f4fdae44b1777c397125ff010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x97eaa5e7a2e79e9ea61f60b2610213af387a3bec08fe7d665a21a110653256716b0bb9d9b5dafbf5438b2f60c73d65028f37da396c25334d0b9796fa055ca108	1623434007000000	1624038807000000	1687110807000000	1781718807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	41
\\x89b40b35d43ad6554e67b1d16cf3142f57296cb8e4b8318a568205690bc169aa5a2e5f4987e5105346cd032a255da16565515debf11a9a882e160cf888aceebc	\\x00800003b96e21c268179e2d1e2c3c268ca609625fcf675f7d04a8a2485eb1ea33893246d23595c3ed63cb0e1197c3ef3b6185b48cd90cfadf60c79f0179c349800fb9d20e3e55d5f9e22133c3b0fdc000563ad6264de3e7591d761dd184761cad705d0757f6eb4cedda22e5613366075af26e695185649526540ce58df255acc2a5d345010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe19c191cc58b02ca7cea4e95bf7519ecf5cd3ac7e60bb94d6bce238966952ddf61b94d1c7f7ef7ab9094a6fc6e3446ba7a33726bb4dcfc309199f1cd96c43f0a	1634919507000000	1635524307000000	1698596307000000	1793204307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	42
\\x891c062b93ff8a6a0ef5f79633e7120dd20530a32c4a507dcd53a848fff36cdf042757a3709a89bb49813018bd6a997cbefa330b2b726e2ed9af9b2f52a11dd5	\\x00800003c2c0cdef7f580f8078c8e3f941aaf42b595ed8b1d00a0fd69ba06612bbeecc2e85edcc2014e739ffff3f9a385b2d43d9e677dc94238cf727dc627439c68d114630079f4e24472f3462cb04fa307f3b67e15f44da3ce280ccdeb81cb3fd9d492f427d531bacbc8044959ed7190ec4d9513a05792bc90247a9d83c108cefd35205010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc318c0525fe35e7914e8a4fe54e5ecfe6a21c78254854e3ea9fcd9f684977fda0e342f2eeb742ea59bf859412d6798f1b6c94067b12dd411278c8987a112f302	1611948507000000	1612553307000000	1675625307000000	1770233307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	43
\\x8e148b2ab97ea376be0a9a4ee566f84302f2b5972dcbeb4f2efdeaa8ca7ece9c9186af1b56c9e32f0708a5ae3ca4e488e0a8c28e8d9047e0c9455608d03206d1	\\x00800003b5e69738a14e1f58f269106b65edfa7660c800e9dbecb5ccac0deaf3894d63a750803d5fb6f917e5ecebba441c6722e49f09ea9adbacd79fef94017008904e237275347dbb370cbb4674b1fc019e766252cfa69b738af150ad98b8d8b0af3bed1216e3693f1edd59cb3cfbd663ede005d17c9eec7b4b46599f6274405daa5641010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc225a17ab84d8d3c0929b133d722e218a8ae7dff99099a074a3b57ee14fb0bf10aad0bd14358cccdab14bfcc787f17d129efbb77d04b56f665166fa8c0b9ba00	1610739507000000	1611344307000000	1674416307000000	1769024307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	44
\\x8ed8dff67e215a61263538724a4f35f8320853c4a601e9f0064fe485fdded702087b76007d2ede1f14f7897f8d114f719dc6fae43326a2232271449ffea562cf	\\x00800003ce54c0662b713d5fc8d1e5a9382013e3ddd0aafa5978249f4d114d5dfd245f01d32ce2f62fbde9733beefe6c11a8998c3b3ef2c7c60dd49b262b8f1eda6d96522f70005af6888203e5a93721dd1b9e50b6e3a7b6c0119ee38cf3e73a3f95a8fe3736a181dd8e6d1e69b9920cebd6a3b4fd1fca81c33742cf5d82bc13050c7ce9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb0bdf4dfe43fc6abc55667523d5ffd8c04fc54736073e0af19bbceb39119c5c10637d4dd6db22f4cc79f26df4f4b91a7554daf9b0032b1a7ecbf97379516aa0b	1622225007000000	1622829807000000	1685901807000000	1780509807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	45
\\x8ff0abe540f7986aace12c06d031161b8f7ac489e4ece3a07567498956f01bc91d0ce056525bc65b0d1aeebcf520991944fe9cc3a733f82fbfc10f2a2bbed5f3	\\x00800003b9be13a58615dee438f9ba72c168806174b2bd732ff0560a4956eaefbbc20175dcbbbe5ff953d956ef40e4e3c371b0e41883634b56168d09e46b8a8e178f1c61d73c83010ffe4bb58c2811a235bad5adb729e79c7f4c55e029539dcea87969dc64b00e0c050d321ddefbc73eaa00c520fe3188d18b03ff2f1249bc2764efc735010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x90d4bc24b24734059bf4dc6915bf302e327fabe90cdb3aee0ab33414e08ee85d50c4eb73f049cef361724b74606879cf243cc8e90be02ca2bf92307926693700	1626456507000000	1627061307000000	1690133307000000	1784741307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	46
\\x9110c18ee9b86b2f0a010f5cbd234d20233db49cccb875f593719ebbd71beae92d1973f4768ca30055c21e3c1e77e885df2cf53311dae81c46582dc04cb6ce97	\\x00800003a5416a34a8c877b7232c6e2feed9eabdfe44bfdb59109842037f3fb855700bfc3b03b5b062a2cda3f4d8085676271e4563e5007796baef71ed15d8ddf3cfef9fe8a8f13c26d8afdf19e24d08cea6b0070e6651c6a96893ec1b974d23721b8da805f9dcb3faeaf675b1aa7ffe3d93762d1ba04433a4f8d0dfbd289e4cf930331d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe55ddcd258b3c7aa2dc0fec28d000b99ba7305ef9efa8503cb3b7542f2ec6f4ac4efe680f2ab1900222406b26b5ea9bf20239d8750c376200a947b8994848500	1640964507000000	1641569307000000	1704641307000000	1799249307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	47
\\x9348911e0d4ca964238a22ea2705a38e4bdacfebc9d1a6db59663c4df40f68a8d758e786b37de6a833399e390e6520f8dc09e49c7b0c9143c005737610cbba62	\\x00800003d804e147999990fdf2b988ab632b2d3d28a3a4e9a1d5537545f3a4a75196377b4321f996845da816f7ee3c3586a4099ab007ddcdefb1001fd59b6b457879e46548d1ee27dd17fa0547246a61d9fd2df5fdbef58bee6dbd673e1d770cc56e1a6c7c9f4aa108716f2a0f7a56b695a0e9617f22b72b1a8ee93562af6a6773bc3e1d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfe5fa9086c5f92e12446e99303f8ff8f0e710b56c97a300f215affb4b2a486789bed4a000895adae818df067ae00d30eed933906150becef6766aef1393e5a02	1622225007000000	1622829807000000	1685901807000000	1780509807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	48
\\x93bc3f4ba42c8b3bb4e857722d2a094c8e7db1845bdf4d71f49218eddf5866ae286845349b3a3c175c4aceadfae3869135259dc0ac7da0f6bb33966403583632	\\x00800003b72f32f89493cf3bc8006fc089e1fc0b96f75e90e0b27bcbf3d3b32e35d94b2e0e0c9700af06c78f1e3b6bb569ce8586c46c698b0c780f92010f0b8ff66b19cfee1eb7505ba8934a597dfb3c70e48291a69a97cdb62461bee027532a838e9368aa057e920cb38b2b1938e05cd99b0f93eec4b60ad7922bb74e046ce49f5ad599010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd6d1171684720927d24aa53449dff04dba22827bf2b2fbee8b6ff4f9e8936c5da7a95067aae6c3b2f85459f61db43055741c4cb673be3b383a0be1f7a494390a	1637337507000000	1637942307000000	1701014307000000	1795622307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	49
\\x9754df835a90aa9c7d588ba0d81a5553036a27c49ff6baa08352b529f0870bffa9ef4390bf051d68a120612d0b960592b1444c3c1592fd67adbb5e23ce148bd0	\\x00800003cc394b0a9eba2014695494856fcb5ca78df4d2e077254a986f0e29206eff8291f97dad0ef97c148bfdc235c6b7bde0bd483dbb40f86ef6a4daaf53208c8723514314ad1d1552c7c4ce6c917585bcf72273a80c426c91069f6d5a09aa9247ed4e984867574d527770a4f4a6b84cdd8db2c2c891d959058a9b90cfc0b51e071edb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb97983772d603de462d49b6c4d988a8e5295cf4c04e8061275d0466a14635508d974528874f642b062689ebaf45166261f99b8c44964ae6e5d4b3b08036fba0d	1633710507000000	1634315307000000	1697387307000000	1791995307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	50
\\x98c032f1a201e05722b27af76e6fbc7eb89d55f27aa97d05ceb72d4f242b9811b995e522f2a4f8b9b5bdda1daff8a2bc7a79d0002e93e35b8af63dacf2e748ad	\\x0080000398cd981c02b40fdeb817f775c00158b3f63c8d0e4330e8501b78389a3811adfeaad4cd37dc88f2af8092ff39f974f81ce0766907fd9ba56af916df2648e764dff3bbd70f0866fdd2a8fe75b9811765ef905e1086d07602b21f69caf4a28d722fa4c6c0b1fc8e9f5b52105fbf56e96abe5d424bac3a4a335c4f06cb6fd85d6f6f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xdad2b41112aa9893d1176e29022ee5d56549aa03d6cb157b35dca209b3dcefaf19dd7fcbb8cd576bbf1a5d12dbbbc17c4e1bd5b7d33086da24b016bd036ed60e	1611344007000000	1611948807000000	1675020807000000	1769628807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	51
\\x9f58732bbd894773b8668295da12c167f1b711d133180cd795d271fa5adbdbd3ba25fab8e266333ad54cf7c5ca9940b69ed4cf0924db352229a78cf9d41a3e7e	\\x00800003dadd70202b0f0d5e804f7ebb8912a37fb09bef4769cf8ee6f2f3c89543b3448820e00540acddc8797126031798c99bd731e1787604dae4b9000d7858600245c5d5c644f9c8cad82146987bb5aa8aabe26762f2929130f1ca72eb554a239879e2c4ae1089d306eda5db7523c585568d23f3d80605c5108b10eb3126043daf0883010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x05d0a50da1fd3b655cb0af579a12050392cdce0f18414399dcbaa8ca2690131cd7f7ab4bbf282812235226fd21ef4d6e4d8d019611b396677a728ef03a009502	1625852007000000	1626456807000000	1689528807000000	1784136807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	52
\\xa260d637487a6bba6e2d87b41b2c9bb0e65c535cdadf6b7ac4388bdb393d33927ece8e462446f06970d7b2d25073b34ec0e640f2805b9cb87322474af3e374b9	\\x00800003c03f04c458dc90b6c26e658f75de894c724c5523cc146c9cf5148ce404099afc25db9e202083740391f274ae3f6403573b61623ff3074234cf85f2941fb48018ac05f4f90a02662f0cb82ee333782990893640dd4517d736c4ec5b07a1e09e5ba4532a39618fe3d86ea2aa314a7b4a006a861b50851903267b033d87b16333ef010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa1d5b4c98ca91531220da9fa642b5d22ba61fc8e6afd8e280fac4585955bb08f53c928edb143c2630380e397d495b2c621f8d1012ec8fddd4db9ba164e41e706	1627665507000000	1628270307000000	1691342307000000	1785950307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	53
\\xa49880febe32ae4696413cbf222d5bdb49cd64c8c0365f8fe3184d2d7ec8593891bb0ac52fd5a2cc033e10110b76f51d5c037f5d4f6d93b9fea7c5194b439f51	\\x00800003bb45300de9d996ade1517e3917c53b3f9074e3f77d4c387b54d182305a9a34fda6e3dd2ea9187dcd0bb9464ddc23087e40a2e7335330eec5054666f6f9148ddb3545b02ba45c28610e08ee9005d2db8c94d33521b0d9469bc61c24e90dd1e1bd6d5e2e437b3da37ab47e9c7b9f77ffb9e657f58ee763cf18cd259272d6dd26fd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x74da1d702349c8dea030df7298afa37c6e0dc7f602b99f4fdc888ecb5b72d2c98e360a8b783fa570e84531edb4c06d816faeb5811b6315c8d81ee27bb5c34003	1630688007000000	1631292807000000	1694364807000000	1788972807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	54
\\xa944562a858381c9280e189cb7f61fcc211bf05f902f666a499d2051e6edba53581ff818f681055ed2174a1bceb4d61d29846123771187c8e61ae0582938cbf6	\\x00800003d86ee44a20390f697cbc1fa7f684eaddd228d8c0d65fb671de7200b0c177be1f20176f61fd7c900970f52d0f247d53845a8f0580c1637ff627143ea3fa4e27e86dd380ea7beeb086047543052b8d6cff3cdf9109108cf5b303d78d21a448a466236dc33183862aa5316e09f9840cc72dcf2092530804c9e2f28cd79de583fa07010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3232e472326ebb344b9c058fce9dc8d228083175acf2fa5a0af13629f5b6e2c7a01ec2f0dfd8cf5825441c43d2c62b4c50647af0f6aa76ff3c6e3988bcafc30d	1637942007000000	1638546807000000	1701618807000000	1796226807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	55
\\xac743057cc049f5b1f89f091d7e8bc3a26cd5e2c8b937115110902cb9eb3c3de74a9b98a76c7ef1c90f5a1b7891bd07b47d2e23120bd102bed43e333c48d4e92	\\x00800003e81cd676d580cbc5a3c7b5eb4183e03562eeb04907d5adb332a16386002b0e15463d416b32261d56bde73e4fe7d58cc0e314347aa64274178d7e8fbc7f4cbe8631709fd33f8b21ac888a582da068ece1d4844af00594faed18993c755ade3868e739888d5bf1e9271e7eff5dc001b94d39739017f9e04ccc8d2037b716f34169010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7e0da8d6d22af6c0b94ce077e5bcb128819c32f0aa6e1c592d4a6d5150acc6fc17ebbf60d8cd3c7de7d1f2cf03fb93f333519e4b8945ad7753739608e6a8fd0b	1619202507000000	1619807307000000	1682879307000000	1777487307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	56
\\xad9c4132f912726d70e6b0cf1dba6fa002f6a6afec88af33cd4eff4ebe424f2d0d734177c2804cff0e26b30db54f6b8f14945a5f1a60069c9a451de99e206ea1	\\x00800003ca390df30ec39f0b21733cb033c0001ce10d7af2c6af44ab882017c018b8e3a338767a1816b6e9118f88167110a32c0115a3eaf8a065950ef293fc6ef52a055ac78deb13e9977b19debf6ce8dd26d39d597f80a21a099b7bdf33130f9654b0a24f4fdabaa02b12d6a27c07267fa68bc847980cf1a253c43e5ddf0e7ce8a842b3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5b9e8a299de51d06459261f4f43e2ba5cf64d3feca9599364ee08886a76a17a5e15663c925380e7056f5c2d8e46506f9eb88acdfd4e258c17f9608613928bc01	1636128507000000	1636733307000000	1699805307000000	1794413307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	57
\\xae6c0477f804d080d82a24c6edc6bc30ddfd71fa5b76dfc947c00a031901f35fb1179a2c4df40f2fce1687e88df18afea7389fb338d47b5a34c509590f4a7b58	\\x00800003d4e9793026a63cd2e15a327b5c0788cb55e13b634db887588bf6d3a9e2902d8c4f3a004bbc3092a5425eeac025f4859d546da237b6cf188326b65459265a020a9484df896fb84d155cbead617effc9211fb4a2dc301e5cb6274725a97af76da007f594e2680151716f6456e9a333a22a9559c2246c70ababa02a0750a30bc0df010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa037c60fe14df48d429abe0a137927f9d5fa1a8c44b104e5f6d43eb2033aa6b4f17d326c4c1c31b58945ae35f760f0f041865c77adeaee1ab60be96bf753ed00	1632501507000000	1633106307000000	1696178307000000	1790786307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	58
\\xb29050b45c6ecde9a62728f842d572df82aaa29d7b52ffd2e74af19a9a4cdad353f98620fddcf9f7f6d29c8accde1966cc6e388cc1cf5eabbd673f6998d16595	\\x008000039e5e9349e672638478b21c31616fb0d1de2117b99e9662be3a77d4c8aa8cf6a09c0e882ebc21a9bed699c030175d872d59ee82367283c660cb5438a84e1c976c279800b90678d4e4722c1b87dbeeb2f481094b33ff73ee4be39c2fceeda14ec0b75f65f2f7f11a186b54516a85476da21b4942574db025e830803005a4007441010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf26e33423836c2c9fa218df5603cfe5978580054d967cccd4ed0fb43451335ccf42ae2af576d2411a0ba7cbd5f0ecfd04d32421faf249e6bb37255843c8f180a	1630688007000000	1631292807000000	1694364807000000	1788972807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	59
\\xb48896dbf203dd20645c1edd38c63a7112c26c48ad2588519f98d9135dbd69e7129b5685c6fd78491fb7597b1c26c71fc963fd61bbec6e180b6e5cd2de65e491	\\x00800003b3475631bccd8d85103c007ce0bbe69f3bb4d5bac6af5abcd6fb28a89e70c633aa0a6f88ca6337dee1a1bb25048c8e75dc55357621d916551e37525c9db8187b9e44e8d3c7239682088818445ff04f15a14e2dc1d30137dc5bf7e4918529ec1f14bc16c2c5bc86e0cdd4d6d31b334ec23c03e1d10a635d7faa66c9fc74ad9ba1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2637f47b4e4fad5c7ac29fb862a67f4e4ce2a6e23fd79089f5afe12476db88cfcf3a7a548b6cc12ed9117e2f4285b34644cfb6323bd971e5cfb6ec273e2da403	1640964507000000	1641569307000000	1704641307000000	1799249307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	60
\\xb418656910ed7f4b18228624dd66ab46d5d13c4fd936d3543853589754611bb0f21739340c316e55cf0258eef2759fa67d63821e625a388656a61caa480a9a7b	\\x00800003c24cb7cbcff9366cde31fb665294c77a956eb5306ef52d310e505d64570f3a5419de146adc52437649229d9a35b163d9da59f361ee0f89169c470d9f40ffe170835da6ae956c657d57cae8a4800aa3ec7ecb0111b22c181bb4e406156cde9d30a3445de0dac50bd04ee1b7862245a9b825a09e398a5a71d7f9949d1817c93919010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x17f5d0107a04fcd780d61c553f316b591ad616604083f93439467f54899d7d6f1422bdad211c5595531212fffccdb9b3de3ae15f08e54eca6c7fa7db5bd98e06	1617993507000000	1618598307000000	1681670307000000	1776278307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	61
\\xb5b08d2e09dc47571e017525bce800be6d250a219c4eead3e62db1e31f842fab06328083a528ce62f63efb12dcaa857a934e41f83693b0bb3256e28d2403c525	\\x00800003db514b3915cec3dc9096c7feeb69732fb4f75e7680498812def7f38514aeeab64f93f75566d874428d1fbc5be63d3f6c3dd0a5277d252b21e546015b00fb22347e93b5a0a0ff9cee874cfda08bc481aca6c0e0d6476585843f993f604bc1b504a53a8c13292f14ffdeb180ebbbc34b9490572b023088c91a9d1903c0a2f2ae4d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xab145161bc79f48fb4d40a74c94e05d7cc08f96516c62e9f2015d2a3b1e54701ad6cb7a94d960ac951f43aa1f110c4eed94022bfee4b69aa1a2567b53b25aa0e	1614971007000000	1615575807000000	1678647807000000	1773255807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	62
\\xb6e0e6de2b5c356246727b3976ef208ce3cf231e1f86b20a8d9e68a2c2dead2fcdde2e6f34224def95d57d25533b1b8fd9d6308f9b02b4c0918017d1af856d4f	\\x00800003be9670820ab816fa796a72fbcada39ad5f17949105ec401c09195bc37ab452143c855b1476474a257fcbdbc3c3b81483f2f921d3c826825a989c8e3bdbc35d4551f281a1420e9015665f08a1c4543004c0b72689c4555d95915ff193dbc3ccfdc7bc487d6e035997f68c38b996a8458015ad78d1edeb6a8aae93d5e680cecde5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x33420bf20d319cc5af572b23fe25c96fbcdbeaf6afbdaa243cc850618de43220ef82644862d1f809641c2d420266d008032002d953ec1f04feffac5d292d0b0e	1631292507000000	1631897307000000	1694969307000000	1789577307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	63
\\xb774eed2c196a0b5e4dad8ffdc49fb4f3dbf69e0a64d074ca5bb2c6c855a9dd979b7cee4567f5875773a5294ef0f1ecd5c96db2fc9f18dad92af8a7329a0b57d	\\x00800003e498d13f1fc4d53e5aece7373992a8d809a13c12400b2d498f78b6551ed3060a4c576195389abe444a956ace13ee2a55a1d4e11ae2170a6b1cbdba019aaead5ff935ffaa69e7a1b79bade524f702452cf0819562112541d64dc0e08c1aaffa65337fe06b6bdee907792c8068b98c9bd4c4be8db7289c06c6cd251329d6cb6efd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x578c05238f1c4afcc46473d103da2ac5254ec96495652c1409d03a57767b152b23938c574d194556ec0ce481303b03423fd0ece0bd92a1b84824f94c2ce3410d	1640360007000000	1640964807000000	1704036807000000	1798644807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	64
\\xb868359292a53bc5451c83f8af50c9395732eead4317c81fd02dd5a170aa96c22fe881be3f247d8231f8840e757b55d33bd2bac665693898874c493000496aa4	\\x00800003ab29cbbfbfe28974394fc4377bf4695afa96d621ee4a7f0ee6984695f1a6754cf15def2c0bada2c5cc6be73457c6721045ef5db2824db04608fb06eb230544e3758dd88daa34a16792310e4f50e641351239cf75c5a48fc29408ed3b897222459235e86de613712c25b3db03a0200a83a9c4a73391dc4baa1891d008eea215c9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xcb37053f5445de663798f0008475b93394635313d014b83bf2ebc393b524afb69a7341764e8665e2cdf0d6552b0aec9e53a38fefd802747aaa1161353b10a508	1610135007000000	1610739807000000	1673811807000000	1768419807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	65
\\xb940998ba5597f668d5889f9d778db5372e9e2bf0a5bd45040f1f7839d7cdf6986eae4a7dfd50db4f62ec49004f334ae5f31e2afb8fd31ef380e2a1495f0cf3a	\\x00800003baf97b5c3a19c8b4a4154122fd09e381cf1cd57ad520f729bdea864b291e78ba76a2ded8b70775a8950a785c700cc97ec420efca0c29a5951f30a4e85fb3147851ee0736afb075032b9deb625b9c5552db7b063b0ef4cb8f13ad9bd2fc975a35e1ce0d2b0cc8a9a5927a3b52287bd928daa7023099b83ed93831cad296b3e7e3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb6d0448978ee44ca40ce5033a979f6f8a45ee20308d4ff63fa2cfa180b76e4a4a683d458c8a5a64a8e16c2fa0bc7ee7894b8f01355234994090aa1461fa1a105	1630083507000000	1630688307000000	1693760307000000	1788368307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	66
\\xb958942c235c3c0332d4f2aa101e0a17b94d4f5015e7d582362eb3f12675416191689ca9b49c971d28bfa775ece77fe554bc0324b6c4231c3dfc27aef9c502fd	\\x00800003b678ee086c47836041c100654261bc9e8cc38a6b4e381162eeeff923dc97095da3278cc5c5cfc6e8146cec4b32040996e20f6890b8f60a0e8175d6518162ef5afbbc3a39d54f806ea6e2884fbae1afc6fb4281aee4dd4d33b0a69b4624595e072fb60f35d0a54461c359d66adfcc9b6c8f89b5009b9e99a53150e9bb7e6d7197010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x43aa50a80b1b473505d545565e3461c9ab56a83acbdbf81a2ff579f7c281cef729a8350b821ef0e7cf5b97cc85ddfc26118b6a1650d3e121779512b60c61840d	1627665507000000	1628270307000000	1691342307000000	1785950307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	67
\\xb96c42f2055f841b66a9d203cc123315d66dba8ddf6faee9b07d59049eadf3c6d2cee5564e23ad5be3853555d2689464a71febd5e6bb23c25f2520cac5462e72	\\x00800003aab19dff8f0d8da4632610617684dec93dc438f6a497c4c20afc3c1678f04d8cd8ba7741d3ffa3d075e933ffa79a858db90c66388b7ff3b0c4cd86934e446f7b21d61c2cf38e0336003294a6dab843c9c9efc490284d3b7461ac0e8b321692f94d269da0f92da760c4cd9353ff0da9ab32bef9585824e667e504171d8411e981010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb438dbafc8ec6903035e4a1d49b22ef3f6dcf7f2f51238622346c265e3bb8d6c870cd7f0e78e1b7f504412069d291738aae053b908be0cd268260b7a176d2d04	1624038507000000	1624643307000000	1687715307000000	1782323307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	68
\\xbd68bdce6533373f01d142d910f22cedac34d1181a1bb69c468ff29add9c54ebf82a366d282c2eeed85be90406ea376b239104338490c9ac0b491d72b85655d4	\\x00800003f74a0e7a381ec2318d336c8a43390f3615a4d85113b4c08c3598e182f5a8e856f4a1fecd7e12ad04fc3c02b7ef95c94859c4dab558c92f0b136c8c54167c3f299e77b76164ff2acefd02409c9d4093f3984bdbbbb9cbca92084060666f9767ab3db6fcca38798e50fd3508ed30bdca81f071197004373ac064aeaed72a052065010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x27e0b139cf96ad7b2d4585aecc21957b1a1bed59b06fe5947c6a9f809844bef93dee887405e99c624a753835c4533c1edf908ac7d1c76a27b57e6795da01090e	1631292507000000	1631897307000000	1694969307000000	1789577307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	69
\\xbe341784bf3ae0d3a11c99da61c6beceb765c14798b4c7bc3dc14b7063506bb89c8ec431fd9f684fa9262e99b15d753128da5c0581ee91642db7a7891be9bd82	\\x00800003bc6f0175af0fc27b2d28bf6df06a27412ec0dde7f85cfc929860b6f507e48d6d91ff1e3dd3e6cad3ea80c0db12f49e0de74fa8afb4e4f351d4d46281c2288bcf6d41af4b77c4145350abbc2610d935bf33fbf7233f9275b8e0788402ad0448a51ec03c7035d334d67f23c4d8d249dd8317c311dd95ae91a38dd6181f061a0983010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x72608a344e3bf94842f69ed29434d199526d856d2082ec32865114eda6d78aade33596af23f66673c0fd60f845782881ae99a09097c750cf450bd6cad6d28300	1637942007000000	1638546807000000	1701618807000000	1796226807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	70
\\xc010adec3265038552d4716ab9f72b1697eb36be630e603199e5178a88561d5acd61d7708d1d6ca6e5baa864dafde4c83e721f2b3be97399a4661068f19b584a	\\x00800003bc2450c096a1f62e714f7a94f09349f1a1832d57d6d938ea8a88fd021d6e0e750f28d82df32c59966ea95e5bbbd798716a7f440fa1786a3d1af9920276feb3a3697a7cb41e2ec4ff6314d412c25686e784d0e403d45a2c3fa8d3ec646c3d371984b8e441ced90765527f8d23ef0a6fbfb0cdc9169923a0da42dbfe1b22cef239010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9b0acf521bfc121d41b77e08219911083d64a7aa71eea489c399611c8ae31e1b09713ea3bc1330ed613a6e7bf623f9651bffeebc7ab2a5d113333f5292fd970e	1631292507000000	1631897307000000	1694969307000000	1789577307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	71
\\xc2ec0baad72f1a69a3ff6250b9e5cd1778ff73c220019741d84fcc33ffe1317163d82b900c441b0b5b85ad91977732a1b8ebab643526f2035a1a2c1ad44caf77	\\x00800003f4df4a30034204eb60b4160be36ef7becf38aa2ba89e6eae27fb3f1ce7df0e7107c08386fe42fea1572bb00ce9e65f3b47455cf3981d5b7c698080448728a8a5960612b8477107049b7c2aeb9314074e4fd6ac74d394205ffc8ededcade5a811ed82dd1fe015b94cc463c8d542c9aff87de632cf7621365aca10ac24e026cdbd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe7405b6b6185c7ec892dc613a3a38539298034d5aaf1c6dd564b1174638ec479757e2ec5f0d565eb908d4ee2a4b082b90a6d962b9bdba68a71b774f24d749a0d	1630083507000000	1630688307000000	1693760307000000	1788368307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	72
\\xc2244ea4456d70b9e861b22e5d27866a1e8a07708477876ff37ae9a940535c52bb37af82dd3f90c12dc9616bcc23df635aebea30c0c60151b9890d9b5e6b5c55	\\x00800003b0e8d7d62e58bffa7917b45ee25378e7ff50feb0782a2fd774d1f1962da918723accec9c6af28626b8b2cd2bb63faa7ee2056493f10c5ebc0c3473a7f88b7cd4f826a4daaf4b790dca9128a653ed3c357a2a4ede31075bba779f9bc1b0d951a9e0035246dcdd59e13d5b85a081a8a9ffc09e460ccc2bcf287f98e58adb9611c5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2c2608d53c0505601a8e66b4073525f5f88ac9a1013cf765db7d251a0352d1e999edc64f83b71b329a83accc4e62d0602d5414aaf28c440fb4f21b6814847f01	1616784507000000	1617389307000000	1680461307000000	1775069307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	73
\\xc3f48bb687e9ae90d027a2a8b66bb7ed85d10de4afdbf92cd0e9578a7d21e239622b28368abdaee0d459deb3908b95533859399acb85674d80ce9cd462c9242f	\\x008000039c5888a9a1e770cc1164ea31d3ae2b81abb68ef5fd802775d63ce262e2f6b277f3e7cf817028d156bc7ed3c058e022c4a67b824668211785d24f5cf8ddf814535c0452e96c18c79bc002ec312b7d6a1771b2c3832ec19e2597b745271e62f666e8cd9af3ade08d1a85fb8147095e88f87acd8a61b5dfe0563ddc4e4a8c205c93010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfc8c0d9d16f591a9ada5c61aec877b7fc2c2506cac03bf6fd93712d17acb8b5cb215662de43e378569dcee18bc9ab2746b4abfcc8d75a4fd8bf1566533f72502	1622829507000000	1623434307000000	1686506307000000	1781114307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	74
\\xc634c6302dce47e8d56d3b14ccca97ca6b303b7a807a757dd2c9754dbf74abe966ffa34abdc99e69d4b6cc462dcb8b7a10d6e56126cd7d4ddb6856659246fbc6	\\x008000039b90dc5e39f7a60403769899eb18b94ea10cc2a67555a07a89b9ee47cb49763ea6958ab7045156ddaaa6be5545c2f066605ebe1d51ad37091da24311d5ee9ad8b1382511470eba6bad7234148faa1d9ec95099ab9cfa348c3a290fa85719db2212fb9ea33a8a7a3bff8fe152a9776acf881014c47554532727070075701f3611010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x175435f79931c5bf568d3a75c4b8d0861fe7ba0c7eb116498cff2bd36f724670a8299e9d9914b240179d350eda1a0c78dacd99d30d389ad57d5e0c7a48ad5b03	1612553007000000	1613157807000000	1676229807000000	1770837807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	75
\\xc7d0684d39f40309467afb4f40a1e3d1dbc07919eecf643d64b0df5934d91467496cc76e10da3efd26e93291d3aa5211eac7926b8a6d23f17281b949a8f680fb	\\x00800003c43f085c4bff72250a0cfe4d8f7c7e75613abc9eab61f45ffd0ef822b113dffd19910c1a8a6bddd28b5978a9597924ce0a8fd83515df3e91623600415aaf60c961b5bf6abcada157e23ecd55271731cfe1619310772acf0007196f8a276a788d2f5dc14dbd3966b48ed53ae525ac76b73d12045712340561af6ae4c620cb2a17010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x4733689857505d4a636e97ce23278d65ea1d2cebc11ddcca9962235a0b82ec9a26dde2cb0046865988f2a92933597fe912f689a6eb1d169071fe09dafe48f907	1631897007000000	1632501807000000	1695573807000000	1790181807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	76
\\xcd9c2fcba2b87a23465ea03e1389e1dadc52169f18c37c35db852d632f9e7a854a7404a8214ba355955bfbbd8bb2a601195e668f233f9d7bdab974edbbdbc758	\\x00800003cf41ff31f042d62e4895b9b95770a87038c4a3de8d6a2050da3d1803c0ecc5d7857b49225c1abc6b88101030d73806ff8ef66b5b796660f87e435cfe5b8f0c3fb21019e28108b0a7b7c1a781f823324b6d4c12a633bb36ae89cd3613181426f7f69a9521580f2dd199f7a7b18b43e873a5e3d167e782afa7aeb918087093e863010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x12dee010858b9fd81f17fff3dee37ccb62007218661e2548e68232b7f56684bb577f11a66f162f71c138c3575ec3b08468d4847a58cf7997037a4ef51f5a8f03	1614971007000000	1615575807000000	1678647807000000	1773255807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	77
\\xcfe40e4a5214272877334cdcaea831419aa3043644c5234db1a6cac875264db46d5283918fc2e34f32ae76f1274fd9c8c583f4d760c99ce1084ce4da8387129d	\\x00800003de34697056d6869eb75c10ddc432b0bd14ab106d7885e87866175c2e60e4de9dfb40cad4fe745af645389501d8a27453de2f764097114daebc0f3fa823023cd30f074183d915ac1711939f98ed86979bf76d53b9b3178006910badb2c63582561c7810eae228570e7b21bdf9a51a63d3eebae7a38005a9e24347d151921e36b3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6a966a8483c98fb8a1288660827c49800bc4d333254fe170cee5c5a816600658577b2040faf26681eb8f487a2d19386d14a336ded53bd22dddd101207b00ac09	1634919507000000	1635524307000000	1698596307000000	1793204307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	78
\\xd38c0a5d748fc8a0849a59cf66d5e8f2f3f45fb3912eebe93900be16b38e775e13b2f2127d64135814fca75a46cfd84ce108af3c89456ae2cd22664e6a29c631	\\x008000039d3f95ac8181037dda79a21f20be5c4d8ba979574390760fe021f53aacfa161b9765669a4b5d615ced72a2633cb44a2743941b681041f79e6515f15bdbaa941386f3f5b0b5c84aa7ac4f0e2d04c30ae8abb7e80467ac6d102962da797a8b7732910661501d9323f7015347a82bbf83c908ad2021a557139f72589303e36ef425010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7763c7b31c62a7bb65fd621a204f62bd7461dc58696226cd98e73b727f236fecb7ace8d24145342ee3e0d4580e92abbcd0e5ec8c3eec2a84115379e3a7b73f0f	1616784507000000	1617389307000000	1680461307000000	1775069307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	79
\\xd764f8d406a4434a414412d966c459cf663907b291cd4f6f552ba9074e7799ab9f759a7eb21b263dca9b6518c212eec25aaa0c63b4752e1b2be8f46fff90648c	\\x00800003bb30dea40cde67c4d3eb3fa954b612206793af8f2749b73aa7d05b7b7e268b5eb1cb95adf3c08047113c692808d0ab9d406eb600dd108076bde595c05b5d338dfb050c9d60d190edf36bc58b200c64d289c6d580541d88e11a49adda1fbf2196c027fcfea861a5e6d5473e52fef0435e789d57d8e646fd010865b103ceaf5b5b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xae41de838b0e43a02e217dd310a1f0095ebb71af0af73034737fee797f03bc8be9d97381dcede184ce5ead5d529b502839795657a6057575c2bf5ad6bfd9a302	1623434007000000	1624038807000000	1687110807000000	1781718807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	80
\\xdb8c2500ece717f9987ba8fa0b9fd05cf90a6b974ad7456abda88a65cfae84c609b04131d6b477f02501e0ca0f9874ed1a355d30c446703976158b6ab62d734a	\\x00800003cdf6a76d58c05d88eca75ae67ea328c61f2faf364e75ac449c99bc50b09d24073137008d4ab3e5651908ad550ad3af8de72278fc70dbb3f6e27bded754d35d531359dd42e984ebaa7e4fe7ea091301f25648d637b563cdbeae736a9356f397d23738bb9a373abcae468e1e2083c9cafdc15b05684d0622b5d447a84b56d4318b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd3a5d648a34a11b89575e88b0c855b54cedf5d985b8f3910b1e17271cc0b0524157caa4493d8564fc03d44808391ee1074c65e5697f5b66b75e7be95cf68f60e	1614366507000000	1614971307000000	1678043307000000	1772651307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	81
\\xdc1c7fd530c561e21ba31e81aca2c36a92e16cdc40f1aa25faab1702fb8c369c7f4215f5d6d0570e76e9b140c653997645773917bb399275304ea727c91d1918	\\x00800003c3765bb4b415ad28528962850319dd8dff853b198e83ebbb030ebe0a09214a2a14cead49726e728c1cd5353f428e3fdf53ec93b24ee5b7cc33e9847d79156c7ab1e62fbed7042e17f5e66ed14485fd464847e9016b7ea11f7ef1df6f0a420bc4ae6dedf439df092014f29e1943d44acf9ad226f3303a3b4cf8bba0a8f4801f57010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7e9a99ea71b2af503bcf1c5b269defd084d05270d24ebca7ae9adafd33f94ab3f681c5274babae533fe21a0302d95d629814380903b7f6f4c32e2fbd07e01e0d	1632501507000000	1633106307000000	1696178307000000	1790786307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	82
\\xdedc21a266b814c9b77764e05c6cfbbfa275502a796a525bbd954eb5e3a1a532fbee0e410a3e7d95e48645dd621be7f0b86e267ea4fabd6109361482b3ee73c0	\\x00800003a72775bf20d4c271d2d6e52ed811b0417a5983a9758b82487ff8b5f3cd097a6760a97b39b8ff5772db47426ae9afd3808fefe61981bb84eea7fe72eac7bc55fff45a95f682d9b4dbf77833476acb14305cc0e34129c3ec24976d39bebd7c15fa61a2c9c061c71b1808b5a39cdc90aed0bdbdf5e245db08e387e54e9e1af5777d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa9b6321908bb995c044f0badd9dca3777ac38510393713c0b38546330727fccd965b97597942abaaa732424cd1eee182c7bf93c25240b963ecfc163955e72e00	1616784507000000	1617389307000000	1680461307000000	1775069307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	83
\\xdf78e67586fdac1bbdce09792f9965a504279cda739d84ff7d9099740a2c32f2006915c1b6e907d99b83238e528268ac62c58c68404757b93ad3721b6b1ef4cf	\\x00800003db60dd5a4745f8780542b48e09f8ca9aaae59bff64795ffa7730c9b653ea7f90c5976063dec3a2bd3f906fefa805684e4d95758f949578956604179693bbe2a30a1acfdd915c5a379ff94ee39da8b11378767b339cc72b8f003ae502919707f8edf897cdaaac1817a3e4b4af3d54e394d9ff68c58c541b13a20cfab5adc3ac6b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x54eaf9aa9e7ea1615a540f67caf5eb8d7abb29d22c1e28b341701b1079a24e1e5e037752bbc9901fe80cd0fbde937ade85ad808c2f3064246b7b6bf8de2a9e00	1614971007000000	1615575807000000	1678647807000000	1773255807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	84
\\xe1e48864b754dedf7a1d107bb6b38772729076bbacb5fe8633577369ea45e2c73beb581a49e5b75aa0eb61a6db574646c6d547275f7ffde72974408a92ffacf6	\\x00800003c5a586d71870676aea3595fcdad271bf57c17c1251fb6a4af30e438f30c8d4ab8a7518f6183e1bf4cc6dd94d236310ed999a8e69492feea6808a16e013233c22f848d597cf0b2489c48641ddd9b45d0ce5e908700ed80bed73034ca3d14469fb214519b36e71853683a13c47747bf7fd644d58cdd3d308906cd667970aa61be7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xdbd3e8b8ad3f6f85b42ab76bdf0784291154b4894721379eb8e7591d4fca415554e82fa0b55161fcfc7388f250537ac9d1c920b1d125174d88bc22b108ca8e0e	1637942007000000	1638546807000000	1701618807000000	1796226807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	85
\\xe44cfac368dbe37e1395b00bde21e0a61b8f9e61065ec5786b0a4efa9b6690f9d1a74509285fdad734235230d63753d45f954cb12da19362d8278670a5f7b4ef	\\x00800003ccf09b23aee29e8ce0ad32ce88a7d3033367948d6fb8b59b6f67d467e0702e812b7c7fd7247563f7e1001974adb47b280fbbadf4278405112d4a8aa8db33e1fb7d4deae3fcc47629c8a309257574fbbc399d55bc362f867ebf9dcc99d01cc6a1388d2379a66ab9e84fcfd0a4da2bd03e0a4049b44f3f34272b083a1eea253e65010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa9099997f3540e686d01f42d5bc6d34139ea5904c7328f83a71bf381a550f65e1ccc795261b8ec8ffe000d279920e942ab0123b7abec7164144ebab802c3cc03	1613157507000000	1613762307000000	1676834307000000	1771442307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	86
\\xe450c4722df68f54b5ef90388f338674aab94375b5a4dafa238c2034232608a966501e6bea7e491efed71bf6a22f523d83574a77fa0e29bdc084927f5c635b3b	\\x00800003e1e370df3da80de4fc43399faeccdb77538ace3d2251a1fcbeb08b85ce97ce75ee7ef8acb844dbe28db4fdb0fc03230afd651c99045c1f429cd4b76fa2743eecb11b6ab878d2fddf96075b2e55206856520cdee297f504ab7f8ec239bd27694b1e57abd2ebf350fdbcbffc42609b4229f5af037ba24ad91a32eaed653c1da995010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa110cd774136c8289a9ff759ec28e9db19adc6ea4a8954cfc9b9dd115566b95e9992578c2ff8d397230879a5dba25ff45eca252547256418b88c2457d0406409	1636128507000000	1636733307000000	1699805307000000	1794413307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	87
\\xe534db7af571b88ebc2cd4d43cc9df2f23e95d7232d08fcc84c1a2dd1a875103baeb23c2fe7de54c31ba79371b3ed3e395db6ac0bea9ca4b3e9de2ea53882b11	\\x00800003cc29a9a5c0a51cc1a861994dc6e1dc759339ac7602e68c9d0f6cd38d624f82dc444d3e669829934dfa655ccce433916729cc7fcc1e02d5c95f2efabd3cd2752c88be248cd50b3f2026a04d2bd98ba7ed28614fbca0c40ce6d42ad00ff7e9202beba52ad71eb4a50200e53d6a4c7d233cd0f1f2e9935e16c9e00f164ce87055c3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf10501f77a80a79cafcd059fbf2f1295450b1b778b813f712fb503099c212f4a7974660e6d5fd36ae6b2f30c9ff26f08a3ee7df12bc374f5d950babd4a24f608	1612553007000000	1613157807000000	1676229807000000	1770837807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	88
\\xe804af5dad9196a45af28302b5ff04ea3ded186c04ba1c2f21eac05c02e3ba1d55715a14f8db7aafb6175b087095b30d957c6403837b16e96c31371107862f68	\\x00800003aa83c0b87a57552621ec11e1a20e67302243dbff9ce495078e2d5fec3e939249919fe0412ac433efc79de6d90545c53793b2e207242d98d89fbebf486bea91b88eba41b22ac75862638490032d8ec19b965fe930a2a45eac58c393e8d6c9c6b2cc7b9978e63242b1b5bf5dec668b6e2b328ae3d938d928094d9bce27fb9871ad010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x72ffe56806b48db73a7c624a3380d96fac9b0821f84efd4e241f5e6ae4d9e203fa78cc03b0eb197d51a8aec93b5b73861dbf9479e24046b9906147eddf5ae200	1630688007000000	1631292807000000	1694364807000000	1788972807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	89
\\xec80206003bea01dcc39c24c66cc56383f681d33c6aca30fd3eead9396680092ce895a08bc9d96e2d909309f3426efc193dddbf4e216431ad82881e4f44028ee	\\x00800003da2834edb5c9599dfed6501c352a7759c8a2e72eda8a040369169583d144dd2c626ae0ee11613782f3cc9e99f37b156e08af2da12218e65fde2fe789ff3d7820f6328ed7cab0b103747499cb4866ee8b18083eebfbf108536c467ab0c89dc7dc012eba8da76427aa9bda9ad4c88816381febc86da296e1b2bdb7a4371922a0af010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8f304e597ea6f979dd2d9bb953efa977e6bcc0673bf30c4796e1f9bcb0df629eed2135fc5750527ff071f3a4751728a85ff5f1daaf44fb3ac782fe1c9e601f05	1635524007000000	1636128807000000	1699200807000000	1793808807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	90
\\xf140569c04b1f9050954c574c6d28e2d31621a94707ed7f2cc801d90e84b16860d5db329328c2e092c4f3abe85edc6052a34ad457fa1073f77b2e032656b6f3a	\\x00800003b03005e4aa6c98835d57d62aad1a23e0027063f36f37830072e56c8f8be3305005b3e11d76d4ad429f9e13871238498dff915e08ad6392f6ca5b4cf016f9b5e3c102c7877af2231fe6291fc8dfce881d4e0cf74f87deab54eea2207288e21b2d9e30b298ece58cf0d76021488c83b5dc1f9dea1c23f4304f3149314057f74775010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd175b2147f2df0bdf25f26f9725f486661bd72f7edaa22a8d060b6251401f9653233d0f082a37baddc283f123fba4c11f0b620649c1a2c66015724915a187c0f	1613762007000000	1614366807000000	1677438807000000	1772046807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	91
\\xf1388f6e56e3ee6b742780a1e5683a1b1fb5998688a4adfe5ce6a673d47ed78651889694d9da836128012abbcc81141c42b4883e33e8e7fe675084c45db5267b	\\x008000039c0d205bbaab4fad0802b3fccc3a65bb394e4169b7b28890637632f3231d1ce7c6eda9d8355a50e30f3cf5f611a9b3d5216a0cea616749e8fc10f6839ac7020e7981b34892fd9500767cd505cff50dbe66ee5086537e3198fef6036644ac9a30319aed01e17546f30977f1961ab184780fc3cabb0af58d564f7d8c0752e47947010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xef84ef2df39f6c8389bcd5a128c3660a05a7ae9c6c226aace99c1644b0b98b773ede8bbf510bd00ea10cdb222a6b355f42d7dce35559db6d348858ca2999ad0e	1617993507000000	1618598307000000	1681670307000000	1776278307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	92
\\xf17042919dc66f2d4f28f87b8eb3d929b75f3c4bf4dae8a255c6ec28ae32dfc9051b82913f4be0f627b3a60fc4a107f0e3189eb746f6e115bfd279f43cda0c00	\\x00800003c5391a495d53428ad0b044d2eff07822c6501c9017651f3f1ed26087f5018b71c1990e947fde3df01f7bd5348eddedfdd1518d2172aa6071fd37c29cb5e3b47360b191be3218c0e1d239401bb0fc3fea0b914c023aeefcd08131882c346ac0c6bea2b0e84aa5e9d1cb4249b1164489982c165755d68c101327b28acaac7c6273010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8e93ccec4f8a6665fa8718d376dfe89a46d2815be173fe0d709aa6612ab787416db30afa77b02e4d5127cc12364c771795644a88384022d2a1aea722fdf2a001	1615575507000000	1616180307000000	1679252307000000	1773860307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	93
\\xf1f056a7e4928ae5642373d0a56980085528afc425b9b87eaec70a7c77a42c4e2f64e13879126de8a598b2ae4ec62690e3a1b167c01f02f622a0ca8edc900d88	\\x00800003b55bc62d33620bb5b123a6bbd190a0d2c550a7f74fbdda99db5427d95e1ec18c4e6eac247fbd2cf9cf84ae69f4ab12e4c0267cf3d9b842e82fa58f72ad125691aaf308f1ceb25e1a314e5fe5768ca8f3f5ae32f539f2b71d51c67c0a6c732924c69c0a4b83d7eea7699b071c3ceaab04c3ccd615c33e8ef7fba207208cff7245010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0194bf14aa498fd518f12acc686535cbf0898121d4ebebb0b0bd4b7bc9795633afcbc0a3fece68d7f8d158cbc874f23654437c6bafccd6f1129e5554cd78080a	1625852007000000	1626456807000000	1689528807000000	1784136807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	94
\\xf2bc4400d457d4c3e451a39381bc61f1bdda3b3416988e65aafb0bbe69f963f459013b48ae70e8dab82e4949fd10625d45f9cbd07a793aab28939aff52c561bb	\\x00800003d1f5882db3cd1b9c781b64d0324b184c249a34e675316594ee98393e6c2a94acdcf8d895c9ccecba059f3b9b90073298e4c3055b990f07fdc82ac0338545c207a3275edab78247befb2a089e8b001d590049e08aef62ebde364f139b40fc8cc75360ffc724eccd22e8cedb1ed680888af39a5c40f3c02d9db586f01b69f6dfa9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x11afd9cbe432bc959172da33528462b5bc6d0b891246a04b75cfd9991b7ffffaf42be895b238dec624efd41d754dbbef72cb12eeb9812d91a9a414534cfd320e	1630083507000000	1630688307000000	1693760307000000	1788368307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	95
\\xf358f389409ae0b7b2fdb9813214ed8f5c4fd4403f1d3a1236dcd3d00b59f4fd9c1545635d468da3b4474f7c0f9bbd2497eb95c15ec39205b0afd585aba1ccc9	\\x00800003b48d94e7afff033826f7b60b06fe485749777e9eeebdbd5d2e411f29831a4a71b576316c9b605fd3c07ade861cf2d62081fa62b7e12e25f6550fbb56f4165492afeb9a33c0ed03c29f2065203b30bd24565909ed8099d2fa91b0d4f32023008be891e092bd464dabe295a801ae606dc841ac3867119f6e9d24b4e4a5f47ccacd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb6f01b425b4ad2aa057ed8075c511ba1be167c3c4ce7ddb40fe0cabb687993f4ebd52ac4e6f11e7647aef21a95be83258c348d19033f4be5e89d325d8f81f80a	1634919507000000	1635524307000000	1698596307000000	1793204307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	96
\\xf438190fc313fa1db99dfb8070799f3bdc232d3732c014259a38798decc4c9c199550fb13b76e332891eecf06ef5cf26352a2bcfe5d179f16af5140d198c1950	\\x00800003bb63258a186f1375d72b216fd2798ca5762697890de113e95c7bdb0359fb3f324d6f3e2d7607b12e5bed89e705faff322036b9eb36ec21a2a5caf918749e821ed3c2ab4db13506fe0ad91a4da6a428424d38bb1aac6843c01f88a41a3c6b8dcebc0a16b40336a2e555c4cb55e835a8d307d2e7a5010f703b0c567a610bcece81010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x570e96df9b547121790aff456cfe22ad8f5228714599057f77641dcbe06e1c52420e8e42eea13cca4a56c7a0409d05e66e64739a8a68b2cf20b9f03d0ac66c00	1625247507000000	1625852307000000	1688924307000000	1783532307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	97
\\xf7b415fe32d782c83d8633cb4a9861de9a4f31a256e239eb512603fbd85080062bb8ce5072b7651b46988fef22417cc09cf4f9afccea015ef3cdf87d6e0fa509	\\x00800003da1241d7bc4c04c80e892b26359a70958ab7cfd6d7679ecf5278534d4707180990de1d42eefca45836aebf202dede248091a20d615a94cd5542976368fd43fedc5a61ae9924c295aa5494b97cad915c0c16715f18516dcfb37fa6d572dd9cfcebe5ab687df8a040c5bae735aa0015cfe2af90f5572cbd601565b3f8c81b05c3f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb61c17230f113b0e35e5b6922b50fffe70b6a4db1f30e0fbf3e692b33df3b5353bf63950de9f1bba7f30e66ad717a2479a209d0754d355d5c2697341bbbf4e0c	1630083507000000	1630688307000000	1693760307000000	1788368307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	98
\\xf8e45512bde86551ae2516b680f73848546de37a0e97b99fdac517442b326ff3bc254ba3932730f3ffdd7a1562ef0f7156f626a39a249f3fb5e114d1c17b9365	\\x00800003cca99f4ba3bdcad3e5e69a65d4923b8bd52ecbab60efaa98d78112c157471268cca9656bb2a1e1d193e925e9e301d95a8c9a9e4e00b8d25202679fd9de941595e275c2db24943c3f69cb575340b33bb9f730f9129ba62e7862c3a06bb38e271b849abcccfbcd1545c0b40ec9bbce3b50c0ed4837069dae2b9d8014f068838cf5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xcdc20632c1d02085fd84b1d704c01a148111bb1f4eaf6da2c2f6a25203462c068c79edb49b05e42b503a0eb53963fbfa7901bd4a241ae08546b58ea69eb41908	1627061007000000	1627665807000000	1690737807000000	1785345807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	99
\\xf85454a12fd197236bc5c4e8c057622c7a7a7f40c7d9e887b47216faca42786b2c3bb0dec512d86e10c6f70b77ea6fd968057030d7dda2c5123b2218e8427347	\\x00800003a1e85c922d8a46912db0f80405a0bae55527eac1c95df9732741220cdabcd00fd3a9d3c631d352bb0cc5f9d30e060805236cc7530e0314d1501ec68b22a838870cc1e8196cf81849b6861470cf864ed4db57dbb26c042fe2d7d405cbf2f8cc8e6b89540328a2f3a24f75a9cdd734ab93d299c6588631ea2b788011dba6541ddf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x70bd4140c18a4d76c2c0c37ebab278c4bcf92cbec7a87cfc2cf996062a885e464f7406430634e8b22a4d44ca4e807f4d95f8242f9e56cb946c88d8c185c49305	1623434007000000	1624038807000000	1687110807000000	1781718807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	100
\\xf8b0426f24755ea6680bea7a3b0fc55836c14273fdf0f172f91bd33861ae8c567437656f6c1cf7d6316d9849b2f664bf86e05a3174b46733e370b3b6bddb5001	\\x00800003fd06360a8e564f2183bdcb1f717676cf4ae62e0b620b9ca39b31711e0cd0cfdf9e33c99467fadc05a3df69de80ad224ae6c496601420f93d6b2e45ae0c700d2b56118f94d4ff59e8a091e1d621cc148ee7213daf496abee9de9320f0d54de8eb0b95b61f0404fc09aa33d77e98aec1c7f9eaeb18223276ba9a3bab545d3a8a2d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xaa0b81b7ec3b9d91886e86125371dbfc177874a00492f15eb5d9e2bdf1b0a68ecb4e097f0cc021ec3ccf0272608c72c8a781a4e360bdabe57b23d91d752e6a01	1613762007000000	1614366807000000	1677438807000000	1772046807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	101
\\xf9e895a999279f5b9d629c108341a06b4a5f9ddcf0978a43f2108254a0e29f29e306735db45ec81142b9b282ccc61ea07eb09ff710ed01778d8e19811ff328ab	\\x00800003af85c7878fb0f7b835eb19b07fc07a9b5dee07d156a7a6bf12b50cdc736b950ba117687859f3760cea98ab42061d3f67d920a9013ced4d9e25b79629861ec31f882f18ec289bb5919043f3ffdf371442c0bfa6541c6e5cbba878dcac59a0572585708563c6d143530c00f430a23a7ca70842b6d8169998fa44f41fdc1e6801f5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x71f94c0b90eabc7d985d85df750902bee20dccb44c08be7bdc2b1a1a991f9b33b0384cc54278089e1c949851a2176a7630a3ae7942f634d281f90bf078e13f0e	1614366507000000	1614971307000000	1678043307000000	1772651307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	102
\\xfabc01d1f97ad7dda14ce93be3381b8e71bdafd61fd71c83e4c5f7da5038e9a07d7059a1bb5efd0e636a2bed1c47d0d552bb764407a6b35a365078b183226bb9	\\x008000039fc0756f64b580477632099c3c5be4cc2984d433cdcfcb3fa221df513ba81ab2428095d984f366368f17a29bdfa6bc4e312a62080359f3a8eef9122ad92b1ac7d9ef7ac6d374ca587fe5c88e0f06ee0427235dac59ed72fe289f3922c4e273432c01638fd5e49c2f11b302c61b313fa28a20d6d252074e2a1c00530ccc67b3f3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8446e332dc79ded42f4c65315dfe7a85bdd81769a8aa861fda40705d518687aee69d74afe39b89996d95949eea989c42d048d2e1515aa822f09bc6b79f53790d	1641569007000000	1642173807000000	1705245807000000	1799853807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	103
\\xfc24095f4b1cf789e6fb0db298dad199054c9ad70ed5642d91ed2445a0e6172fb8462c4b3b233a5eb4f02bad41765c317a11a31b97671203b576fb80ef99fcd0	\\x00800003e7acdcd5b4ab21299e498fcaddc80e3b52d7aef8d3ccb8486f85095531aba50be8ac47a1bc58fe11c978b2c502f76ddc54d93d05b0a6d3159fc27b21bbe7d6691cd474ac71aaa7954e79ae04c69b00d26186d934e5e7f4e53a2efe3e1bafc39c8f7574569ca31471d872417dc001f34a734aac874cb90b62e75d0758a79fe09b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd2b932a9d78e5fa291ce1af57025b03a3b759a6ffa3091d2ad2e1be618143eea4059935d67757edd621ba6cb0302ef95f060d97ace7cd4394e3791f95b67180e	1638546507000000	1639151307000000	1702223307000000	1796831307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	104
\\xfd7c3b75e23785c398d6b68d1af7ef4150ce9eefc723f36e5b92cc31865244f150119919ebf66d1903df32fffdeb4380f73a0558256233e325a5d3fb61fbe3f1	\\x00800003e06de18d49b6d163f72ee671407bf386667f494ba21182af5773d9c1d7646de1930517cda95622917b22b8d93f4e7b1ddc7dd7ef2e1eb0012fb03d8d688d92cf3dca6b5354c0d2f861ce5a20bf087af2d177a16aec8e1ace0fca1e40f32eaf8f52ffbf80defc58a7b0d562e47a4c35d539a38052b74897f58cc38c5c27f2cad9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe12af4069abf6adf459b135770c4df12a6801f311cae81587830a386e2bab3df25a0e19b932ab3ee42a7e2bb8caa13a05e22d0f8dfa529eec3e157af9554b002	1610135007000000	1610739807000000	1673811807000000	1768419807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	105
\\x0141755d3e51ebd2169883442565610ee2887fd709d54775e20970169d475c5033548ca7aa089bf850c7a5198e4fd58435d03f1e843822759e2c362bea1c2d50	\\x00800003c8daaab0933329d079ef9c86e2066111979f2c17e47783d246e2984bf10296cb44ff24681fe973dce3ff7657aa1f786acc4ce324190d92a0e3513a133a0686a09bf492741a1eb207b28ca48d0e373bef8e7d1075a52ed8ee09be7453d001c92051477b2c9def2b11a7d388681a881e4a9d7500c61b912f87a0a42a94342842ed010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x576266ddd89a7658586849c05934766a69841bf95deb4959ba39c7411c577a6e1e193d11fed408cd555995dfc404f505dc81b27581c9b5778ea05196200ee603	1625247507000000	1625852307000000	1688924307000000	1783532307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	106
\\x03619b2342a949fe6e8fb625bebd5e8ce9aaca3a2cff73106b99814d1a90ab7ae7bf4e7e353965896fdac333d135ddc3ccb826aca7920ff4681a2aacd1ff891e	\\x00800003b0300e8aef6a854bc3fdfef42c6d831853a1da6038272d2031d7b623ac47d90750805aad3fd681b115133b545174fd402d67de117b80ae8c8c74ec2260cda656dbc02ec7aaf72df0081692220386b37469b37ed5279ea91da5a0f36b598e843605f4a44c99324060f627f61b5bb41f2bb231a35dbba28adb5b4a7c8e8533c923010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5a074f2761a562f8fb84672eca1f1b6057f007db0f13c82ac570e8c50fc45deece10a8155bc28fa66250e4bea74d2e5add4425b079c8b982c7f0d8b2a0c3e80a	1628874507000000	1629479307000000	1692551307000000	1787159307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	107
\\x05adf0eb2fc28c41d36e8e0213dce2b4fc47f7fa12782cf5b9b843100d38d5a53ec1980fd619d47f845eacc8e9b9a84a77f35759858e85d328db2a0fa317dc4a	\\x00800003cbaf0251c9b4768b2f5aa8d3336eda4ba4ededefb2b3358ab1fd2d7ef4c851cf7584bf1373dc66a7da001fcc56f95cc134027750b0b724bd15ecedfaadd3a4907ba80c5eb025040db2a0c9d4963eb3058bc47d04f09261cf224904eee35c3f827703711481c5e04e7a9f189ce7dd70eb03dca1800a961ce90656154007622665010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf28703d51d3a02985ea55f3ecfe9359a54e475f32de106a3762b16c42c102413fdcb193c1d509551130aef13e1e0965f772f181abecebb9213d0bcbc5aa7c406	1625247507000000	1625852307000000	1688924307000000	1783532307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	108
\\x081985b19c804ff4c2603147b32efe194a52143c6c8d64d6adc86585ab5780443e08acb1119a777dd46378dabad1bcb4eb675751a4ccca95e7d0b64c829f2301	\\x00800003bcc2f9639c87f7dfe613e1c9a52df72f03af43d9bc4c33a2a3d35b792ebd575933bee3b17793e3711fd310c6d861bd76c4a96225b771f9baacd385397e05dcf88dfc38d98d089e7833d71c21b94ba45f537cf891b863f76b0aa9913db596fb7f83f04f420a80a303cfe51b573d2b2c0fd957ba9707ea1dd2d8ff1df8b883c2ef010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x57287c5ac5d338f6e8295b713a8c7649f0dd4c684c114c50e6f189e2ca7497c55f8c5c3871ab6ef8e286af813ec28488f7d1e124abce449e0af4e4f398b7e704	1626456507000000	1627061307000000	1690133307000000	1784741307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	109
\\x08591b38981d5065592b4b16540d52def8ba308f91a58516298a6e0ef674ed1002ce54108129eabd592801acffee01174bee63401e4c2622f0b6ddcbb2d0d13d	\\x00800003c207b114fda88dbaebcbdbddd540bdfa40206360e9cec6d994a1db5c3a3b86a1243dd72e8ca4c10ed606723559e2e8be70d03b6c45d035b7d5fb5680c25e92473c13d24960ac2aef022802247ab8d82183b5e26d53d8e4b7462a66e2efa0e3dc632fcca144d6bf8a99ba33d6759f24f949160bbc1c8f0b2547f6b2950bc6c8b1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x01c50e2973adee98d063f923de07fe1d95d32110ffcfc618b4a568947c0af6468b8fc18fcf3ff4cc1058babe03867904dab0c21ea1a4600e67d606c67748330f	1631292507000000	1631897307000000	1694969307000000	1789577307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	110
\\x09a59acc9491b96670e5434306e3c317d6ccd5a18cd4d98d0416727018efd5bc61d8ab8e89acb90762837f7361f69a97590e61bea2d0f55ffb15a55b1e639814	\\x00800003b82e0081377cabbf5b1b37626fcbcc2a7a4793403a8b15ff27346a42213cc771af5783d939582d863487f49ee93d11f4ea7a1f6c1ae4b9d4692b569ddf7751dd3cd4ec94919bc0fcdb810d81568a5c789688b034d55528b683ebbb49887f2317343422bdadd62fe0a3ccbe0906efabfece574b97a70ce994c37b237fc533dd8d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1fb4d93f15dd3c41546a7000fd9d424e97f4ac29c57b79b6b1949b8d6cdd828cbce975e74a7fb3833fe9159333673b7674694327cdbd734668900fd1375c7e08	1624643007000000	1625247807000000	1688319807000000	1782927807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	111
\\x09f536c7dde9f6d8a0d833ca3a10f0a72ae1868886837a18d005bb74cb6addfebba6e491c4516f94e9b8770065b54d9222173813e34866d3d93bf5d70ac9ebdf	\\x00800003c5cc57cea890fc28da415f80d84dc6d9ec5a5d56571d9725ac3745243111f50116711efdad908da60262de0e3bc34f6f29f1c76b5b15806c2f7c00b901462c6ef9506f8a5b7420b618c1bdcbc985a14455606312ee077ab5de86faf6f2870812e6d566380efa9ba2b1ea8358a9d68e74b27825032e8c1dbf031a405a425260a7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xee1fa45253a8612a773a72ee58b6f0361749a4f6360b50007aae39839da29893074ab7a233a7967bf212ef8b6850c4e63a4bf955248168e3e99aafe06ef79d0b	1612553007000000	1613157807000000	1676229807000000	1770837807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	112
\\x0a45729d2f5f5ffc19b36f63ef2319ba290caed405dde4045d45b7e9808454da3d95709c2e13f6575da299d92d376abfe8c101ebaff23e9a3b8b9692dda34e03	\\x00800003c96ef99038485dc30b75637dfbe992464ba2ccd075f62eb8137485cbfc2b1a81b564119743c843c2c585e23aca547fffb890c8d4c40ddf9f09c82963c612528d0e52f464af065d91dab98bc1726e72a4e50b2f1cba2d8e53b266d73952351ca9555830171e89ca8366bc11348a7d72cac6852a6e2babb3c41199b8bb6ddf746d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5ae83112c7fe06162febdcfcebb5d4891af9e1a89c94c49ba70edb83f6ba2bc4d34bbf522e93ca0f07270ef95441785b2f52b7e45d64e0c40403e6320cd41703	1636733007000000	1637337807000000	1700409807000000	1795017807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	113
\\x0f6d2b94afafee70628f5b1500b7078d604adde4ce2f99f0ff23751bb30421c6f969a08eb01c1514242805f81a7ef94ba59dcc0d4d475d17cb396baed34d238b	\\x00800003d8d195cf561046270b92ad6455f84555ed673dc40da5f0153a9098ff4936a1268a74fc628e412f2dd60570a9a36b65221aee6cd38bf3f7576869806fbaefe761877044e9ca4f081a9e180b5bd15d9c480c21a75eb8f5a798a5718a1407591f52947660040efb03baf8b6bea5cb67f9a51d38537a239772ccfb11f21632e1d6c3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xda62e74476e3d71524c2862edbff2dfd5ecd0e60be4a51e102b9ca30a01247b4cdb271a74dd701487d3b0c9690c237e9a1ff24c8accdac3f3b5286c62a860503	1628270007000000	1628874807000000	1691946807000000	1786554807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	114
\\x0fbd81e70ae15aaabbb880dfb12e17212e95197d7687b9f252bb366a1e8383e14d16851d9921658132d3678f193bc5a96c41b17241f11a05847698a6248839f0	\\x00800003cb7dac2a41a05be8802ce2ae92225a9d057ccab82589e7158fe69cc50ac1899c7914d777039aa051cc40d2940d8839c86a7f4a54f38bf5cb1215e3e9abc0c0b9566e54c0ca9e8335ad83f319236b55d4bd5a5a2518fbba4302e56ed886b4c07eb4da64def1e17ba734ccc550d6a977f1120c782bdfa6a69899354150fdfe5da9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0bf211d894004c533920412a11875476d1ea272c9c593fc6e77b97a6140ba2370a99f3253af74120a8aed54d422e942b7f7ecc4cf6e5813cde94d79c75264800	1616784507000000	1617389307000000	1680461307000000	1775069307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	115
\\x11e1443522f84ab5f151304055c16036be2bdce80df281d76c970abe86828bd86520a07437c5460067283660c8016f526bbb598b2faee50f56e6959b436e28c3	\\x00800003c1ee0b50ea099538ab9a3cefd17bf67d37fcc7bf09d7844685b42dcde31bb981c6a2cf69f38a78c531ac026de2c4b2239c253187b713fbfc0a3bda5321fdb5c58e0c14024cc9ca6bb4976ec57f35af23331292c7a80e9c57bb2d8c07265fbf09cb7e7395eb7e51ea2421285f40c354cd947eff9e0fca2c0de5f0d4430690db5d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x70815a45c69d6b782f83ae45baaacfe7216c68a43db1abf9e3a82a4e242a782f12d5405832ca8903e1243ea82e1bb975256c1758f05f0c5b7548c5472632df05	1632501507000000	1633106307000000	1696178307000000	1790786307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	116
\\x12897956c080d8de1865c3ec9d0811b233c9038ac43e5c96be4fd88c9446c12f0137095a37b4e82cedcbe45c43e6c61be12b2bc9c8a15212f2bc470d4004e5b0	\\x00800003a9be732c5661358f2dfe6dac53b7cd5c871c36d5dd77c4a80fcf5559f17e46e204f279d5fc0ea879e8f3b5e173e355beb626c03b2214fc82760b61fa7e78ea2268fb6f7cb1b7358e12dbf901532b6d4f3aeddd08fb37c63fb9c70ad971c34c9171a68ce92e7133c5e5873a33db9cdedfa205fdfa0d8ec92e8d72a08f35c38f55010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5f16ad7ac288376858cb295b7fd3a2f80410600fd783a5177d6ca680ac8ce587f91fb3067c89f04b1e1e9baf44c9685f35f363dc1f2515681d74a40615b0bb0a	1614971007000000	1615575807000000	1678647807000000	1773255807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	117
\\x139dae4d287bb72d704188214738f0e448f65d1a7d0bd5e5128f0790d229f20d4b5e1368db4f9983e613ef77c38caa697f3c5d2eb1e1c4a35dae0891fd27bb0a	\\x00800003b1373a8adb477c097d088a1a8375f1125de8d1d9e54de4af35aa932204625b06cf9d5f6684aa3795b53dc58ff2662f913f394a49b508ed6a089e4f4fa1a6c4f157fd400851d4462c553357b0935f837ad26087772a366cf7248b2b258eb27d1e42d3570aa194efb3515907d7d3ac2a2bf12636277e117577b1b6687ad4aed5d1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x81c93f30b9af819c824135fe4e1b670424ddea4f35ac1145fa04b8c35dc5f51ba0a81625070b89366c97d114753a377f30954e9a674e19d8ba324542ee190807	1613157507000000	1613762307000000	1676834307000000	1771442307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	118
\\x148555869d446cc24556ef525eed6a8f39d49748f3ee21af629991214e5f94546d8f9da0fad95479d6f9e11f977af822594e2fef44ed7a133b88c66ed363774d	\\x00800003c2b123ed4726be2b5771e0511e233c84100538daa3e34004ce84aa109b76423294eaf3e74827a263e9f2568b713d56d4d8f6cd784b9c525b8f7e89f801f170d19e4c9f255bc4ec41bcdc9e5de4170bfa93db4d8286b49d553fb81da8b49894975613874717bc9c58335493c0689f3f8dd8ae73e1fe86fac0e8b47ba7582344b1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xcd8b765397d1d4c2b84e23e02d34fc53e0f45f9642b785b14a26dd5a86da5ebcfa2eacbcee803019fd3190a34c196f9c054663b637b7ac438b5948b63f49db0c	1616180007000000	1616784807000000	1679856807000000	1774464807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	119
\\x1a856d345fcb77c0b7601e7afe2386b74e4e481179b2d46836099c0f8396b9c796444f6451cc900699de5a706bcc33746c9fb859991c388b4b97379304e0d9a2	\\x00800003aeb50fbedd1e312d6940d66eb8306f220eecbb5fe31211a942cc59a16e641956f317299ba94a86b198e3c99753d12ff23e5f88469ae7e3c068205cf833ab91595a331a0835a23770d675525921efeaac0ded1d5b93c4bdc5d13b2061a76460f8c7351c17d03cf81e01d1e44ecdbbafea12830a82ad17264fb6dd68126963a0b5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa8c8e3485ea95643f826fd467f35d222ab0b86905e79fc0a93ceed92a2351ac199fb3b2fdd35815227181cae5157a8453e6f777dc2abcbec78170b44fdefea0e	1637942007000000	1638546807000000	1701618807000000	1796226807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	120
\\x1cd53de341604c4f9c101bd1b103916e9c70b0881d7acc031bfca7237bc6452e641f9c94c1054fa8d9e631259ef3eed6c446457baeb33f14265df9f7977774d6	\\x00800003bb4144ccaf89ab67980651d54ec5fbf6bc74e84deb640d1638e0b8e8149c9d47032f4e09aec85da6306d84332a1f10a50349da77ca24bb03d986afb7537fbf324967146dbb0314ef5fe78e8ad7a94d377d9d3e10b4a2ab0e872ef3bb4aa8fb5307e59b13df970cd7994c989893df17e09ec30a17cc901af1a7ec6ea44b5f932b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb812987d0d80d8468d8fa0c871887b232de9c5904f4b0bb03356dda01d12fe92ac276c4cf224c2dd22938d5b47340c0f342301196ec0264ba26eaabf176a7e0b	1629479007000000	1630083807000000	1693155807000000	1787763807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	121
\\x25f93684e02fbf5098dc7878dfc8b6270e9e16ececa9c61a1fdef26c44dfe01226b91eb804a22794184054174f0db7d42ff8aa54c75a4d8e250af62b8fb8e2bd	\\x00800003cfa28c0ed6c2825b288442fa32106a5dd7eedd6f3c09ba17e8f84265c63b06f951c2b652de638c3e77d3763d57aaf3b2a63fe4905f3693b732bdb8501ef2f4ca8ccd81fa5997a846c858443149f09128a9c6b54d3db8adbbb1e8284f265f73079bd80c6b5a7f172df7045bcf92587a147c3c30c41c99c2fe76702ea1aebff171010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6256d5c97415bed223621f9b961de4c7fe28a031b40767cda84ce18599b5d5eac19f4dd427f3af9e43d596c11f2f37345b20be9588da79a5b7c8029fcd275c0e	1610739507000000	1611344307000000	1674416307000000	1769024307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	122
\\x2825a1759ccb30d68eae0a37b48e902b4bbad5681e9fa52a3d1d0376390a6dc5c472f56d092b5767e059c841f6bc1f29917f8f8326db6161347b4a1400d3ed7d	\\x00800003ae0ef8f543bde43edf88e9e797c2298f1250558305cf578f943d3fc5d822970c85ab72eab7f0bfa03a7c5bb2c44501ffd2ed7261219e196e322a7a861de6c9c5fbe5ad5a4123979b95d81ebf04f3f1ecd4e00245f9a01984e57c57cee1a2fa38fc8a5f61ce6cb2541c70a2a5eb37b6242af3e4b2ec99dc49e1357bdbc39c110f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x17f29dbd4f0aac6006af7f65d4df9fcf8504436dda4e9b7dc8a28c3eee505a71f955f86886ac51584d9ca12df46e3ca5933f45dbd977c47bea935843b966720b	1612553007000000	1613157807000000	1676229807000000	1770837807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	123
\\x2aedbf674c677f63dd99784ec5a948ce4e9144356bec5f745b2ff443a73cd49395caaaf5119177f340438b159f2779cd8d764779a512f04fb761d8513b27f136	\\x00800003b7fe24a5c09db5d8fbde7683d0ea69b7aa846f3bb1a2bd26b01db340f8fa42131f3603fa8c3cd7b17d3091ba8aee25e6872c21ed1c8eaadb66f63e337b417d5b3cc86bd12257e8a6f95b1d705f1a44d12315a4515f8fdb1039feb6202248dcc0dba64038ff6ca2fb3ef2518af2b23958932b1d0d0bbfc1209d357217a4abe75f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x147b046ebfc3365313775dd0a6c025b9f0cceb082b55d9a2c5ea6482a93a50e63fe673086e4642baa800b42cb1411d91252371e207c38aaeab79ac42a2221c09	1641569007000000	1642173807000000	1705245807000000	1799853807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	124
\\x2a4ded4cf59d10dc504b386a8c0565d1b1e1fabb3cc57543cc7700bcb7899297f20a4d69abac370febd88197ada98df7d40a40c370afd9f469da343772422bde	\\x00800003a009d33e35b8a72e310be7f9cddae49055370f1d7802da2effed9ae75c3fb1d5f5c96829eb01cbc1b5aa5a2f92872a8cc9d427ce9e23a4eeefc7adc73c2646be146e37a8dc72bee63efdfbae9266d7f8d330dcc9093fdab3d53bd70c3dae1435f9243d16e359d102d5148404731b33e66806ba531cdaf2b463744049b5e3ffaf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x656733a550605194fa85af8b94758fc3d0a139438673db9015f32a770474930deec26a37a228f3909ecd14536525f6f155efec7d87c93e9db877cadcaf5aeb05	1625852007000000	1626456807000000	1689528807000000	1784136807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	125
\\x2c9547d5580d53758ab97fbdadc4068aa663839f141e36bbc6b22e37a41e7d6c2cd5974784198deaae38369dd712fd0dc0139ac63a96fa93e2709222c74ccb59	\\x00800003aab8b8bcc45cef410460bf7454a7e5b96e9e5a4890ab4575a981465cf9d7578e9362f604855d85df0aa6a3fd450f9bfc247a54bbd429ebaa6a5bf57d8191507d0a347613c87da018a547f3736a2da8d4a9de9393ffdff1a4f49868f03f8b6f4baa39e2259cbbe385a7b25a4059c278c95d5887dd550bf1785e78ba48db06c745010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xac90f8f9fe6505c190647fd95ebbea73a0b037a7790d3a3c52e5abe884a606f35a04702ca56a72c3e87d50f9f24117a81d2c4eaf570cce98cad33581d3904802	1630083507000000	1630688307000000	1693760307000000	1788368307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	126
\\x33590e1746000a6912799907b42003e7256559be51fbefac3790d90e55b0675c4e82c0a13c2a10a95a13a3af1052a2c61346622e72cef74fb1d548375347ca01	\\x00800003b32bcfeb3a349cc4ea4466cf5907f2e5c24c4e9383f80986474f36da26183fae54bfba8d5b666af76d6640237650f8b7c162a891f228826854dee65f917ee7675f8a9a25f5c10098c69d82e2fdb33c1193d6a0eb3507a1608509699a59aa237d98952f148534225e34e61b2efd84e8a37f7a59ca5317e80349fa0238c64751cf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbda86c9c75784c534aba3919cef1e00556d2590008f7a98cf111a9726b4a7d243cb9a241203e79fc9af48517ba33e166f73847998335b1cc4655ac056064a804	1610135007000000	1610739807000000	1673811807000000	1768419807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	127
\\x33a9606c525bf3837e47c35d22fa0e499dcdba4fee874ae1a75f0f1e098a9cf108145979e8956c46d0bcb397919c6f8a556f66ac4a6c17daffe9924316ba5dcb	\\x00800003b0f96469d75359e7cd41512cf3f5c618d11e175abfd612fcc2a365133acc15fdfc2781e8bf3e6eaa0536a8d711ef972d4c58ad441c6fc9f357ac532239a21ecdc29c79cdc07576b73b55ce7e626d6be21b68a6c860d9424796ba5c17cfd19d98093ad2315dc2dc4e53f3f23e24170b4ac1a55ecddf5e32b1b87d0d52df2b7a33010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xecfce1297e2cedce5ae4271c63c1f04e7a33f4d0690b74317c9af37f2e4698745e516c62443cd9e45c473628129fe774615104a05a33853076845e27332e0905	1628874507000000	1629479307000000	1692551307000000	1787159307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	128
\\x344d07860d79384b8b6c231d53dd1659461d1e7f570653f5ac836eed009a5b5db44732bb1c9921d153dc0bf726804fd23d7295a0b02be7a9910cabc1b953348f	\\x00800003cdb2d6f5697e672c15ff5a4675bf1943e9bcef93d20b17d0aec4305860738fef5b735ea0260424ece426df310d4396a35ed31faaa509ec062b86bc87dc5b9e3ea688444b0eac72b6d61a515e67f4150f499a92763dd00fe7cd7e0964bf2aba8b94b50f15d4fd39306bd943e6cb292f6fd2089a09c0205cc5158fca0f821241e7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfaa347656bce85978b198ce7c02f82fda0cd21082d24f874b6c3ca728220d7205a87413fcacc9dab846a92036c5bb4ab7d48ffc0c6fdec72b8f81566d264920e	1618598007000000	1619202807000000	1682274807000000	1776882807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	129
\\x39e93ffe5dc9c5416164adce6379de69d709cac744a455c4886dc1a839d16935d7641a78d83797261c7ddc4aea28c9c38ccf8b0318581c5ff82f9538b0627c9f	\\x008000039a0b460304524d3b9e7236a272af39bff2be5095e798c0e950a1d2725963b0651a311be73588d7fe5c839a6c940233bb4e2e32433910ce1d816d889d2b83b74991eea43df5c372ceda02542b66009b7eff5a5b40f82b06138906eeaf1f98e84e79126e0fc2658e2296cd539f3d6e8de1c8dbb17e658e023b99e90252ebf90d8b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7689b729f79a6ae8f9f1a6ac72a3e5a917e99439b63845075dc8689c87387c438207e69cfe2e032825738ad81cd4a9fb4011fe249b34d62f124b030dd2c9eb08	1621620507000000	1622225307000000	1685297307000000	1779905307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	130
\\x3bfd570eee8815f9bb133988d769a92cba6742534759ae6e7c7287e36f45fbca838c91b9ff26fdd45d808c8458a489efb53e75fb8fa52307679eb6e3d4056782	\\x00800003d0e0dad1c902f1a7dd44f93af350846bc36b5a13a6e22a8b1d6d8408da9278d06bab8b675e0921dd8a6739c18656fa5fbd1506f14251eaed9d7a3799ac329021c3ce67e2c1a48eb23b43aac1225d453f4410862cff995122b4f8ddde362740d49e1844ef5fd52de628718b91a0ce603f932c02367a6860196546dc043089d303010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x90c800faaa3cf79370ad4f376e40ebab606edba6b091bb2f3933f6bb40894ea269f355619fc19527d13be757045cd150e55a84f50573b04f60616a66d597d107	1611344007000000	1611948807000000	1675020807000000	1769628807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	131
\\x3cd9522101832d9af5090b6865ee73d27e3a17ab98173723ee40da4c2b04341845b637b41ddad0d8b378976c0a23657c56a569480980ee5ead4e6b99e75df3f3	\\x00800003a6ba3b6b5cce02fb3549145e521f5836ab645f2e97f3bdb0755d89c6b33b1234557b8a9317d0aa71ab35d525e585e22b470485ee21b0749fbea2259077349196020f5f48f17e3860a880bc909bdba2e91124fe7c5f2d4153409e94ff8a939bc5427718580542efb39887eaeec27d17459d7006bd9a32fc5c879873d35fa3f62f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x35c7fa44c802299b45418eee5b573762bc001fd6dda6b5e61f3dbf6ab9de86ce02d47efdca47ddf60782c5897a98b26d839c746cb7e46de21db442a96505d300	1630688007000000	1631292807000000	1694364807000000	1788972807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	132
\\x419dc984ad3015fc52977905cce7b8a55857efc539cf052ccdc813bb1fa43a969847ff334e9d97a6acd0b67e41852cac139154a6e02a1b31d97a3efc5dc76c2b	\\x00800003adfd7f96aa9948ea9cf205d7210cc1131e7b317b1cfa397025dca4c2c79f4acf1365c26b268a7a755a8d274a49235785d0e1a152f1a545974745357371de528aa2c57a0b9d88cf3ae71bd0a65558ce534f878d54c31d353821389931c6ec0b4bf9bcc27d5d54b7a98a6b13e0aa0d423c0181a8f7f76cdce14dc9cf871ff70033010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x45370c1b43ad7b1acb5e08dca2845c9a862a70e4cd23f44512b0a2fb17c8127fa19a443c9ec67a04bf181effdd41c485c792f09494bff9d8db018f5cbda6c604	1616180007000000	1616784807000000	1679856807000000	1774464807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	133
\\x470dc0007575db1263f1e871c4c8f3cccdf5063cf907bc034fd1481075fad4e166f7ea13864baedb85548838860b53c7a813f6781829a3f94d0d37c19e2f4bef	\\x00800003cf433c3d4a3690ea3bcbb6c72b7a81a8f35084d8bdd228d8462cdf265286f1c405c99c028aa6d737a41f5655e4a5c35f987fae0456235805ffab5428b8484bb83439de51646fe6c55ec3ed3e4be9facfeaf08034b0cea20435a97e3459fe3300ac8887da94dcf2c64ae76efa66d21076a9733c4ad78b47cfabfce9a8bbec4c5d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x827a42c228841e7eafcc6e96cf5338b1121a04bcc63f3d9f51042599d3f1c6a76a06717ef801ac76852e682c042de9c5daf5d5579630a14fdf6fb2839aa6870e	1630083507000000	1630688307000000	1693760307000000	1788368307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	134
\\x483139b0ddcf63ae9e3f2504e4ac2e46ef6aec2efe04961dcada3bc9700f52a8cbc7c03269547c6e46c6a821c38dc4064d968493295341bb196f26894efa4ffb	\\x008000039d6349299d2f123a5102aec4dea8b4990bc772fda1076dd94abe115cdeeb6793f2bd42feecb50a1ace989968700e9edec7b9b072d9a5142d8b304d59617fbd61b5c46beeadc911eb67347b4047e70348c980716f7e158a6e1f3a76c540603dce62427a2c7bda571b371c956e2c678f7a084a48daa5a502eb5d546681909a8235010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x04eeeb59f0d8cd9a6bd80b5825e26a9573216f51918e5b0d9f2bfe9a2f699d08aa3df6bfdac085202eea65db33ab5e645d0aab0706274bf9bfbed7cb937f280f	1629479007000000	1630083807000000	1693155807000000	1787763807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	135
\\x4869328f6d2814b68f203e38ad7e4b245452acc8b89e5035b4c3e714c9a3bfa98132a0b0567eb4094315a6f20ca7df8db11b9fccbdb4ce3e0f21906e02ba7252	\\x00800003c68714b02b416a770f80500c68b0ecae92afb78a3bca37c607bcef35fda56cd67a61503e046e5f7f987a2e3f5c873956fc4486590897d3fe64d71c9291f2204d6347faa667d247d34c194df315d428b285b989e156979319fb54b2da5c6466e6e07fef0b261733a6934d5a6a74ff807a6812ce930271267beff6ffcdd3b55205010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfece269d3daf226b8e131921b3effad91304d0df1ff2c8a2a0b611dce814a946c573b64a7ccba4863237365de79c86fb0c74c3ff56fc56dfd539f39811d5fc02	1633710507000000	1634315307000000	1697387307000000	1791995307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	136
\\x4a11cfdf3de389599c5f859cac350d920bf248c876eb5d9d6975f171d89452d3597d1871359eeb80dfa6f5943860cbd5928ee4169e53e499295a2fefd115774a	\\x00800003be4a673c029d169f029e36d4dff4da43ec0b5470e7638c5880bc624c8880ac1b961a984f301e2e36f9570164b766c7bf2aaf89cc7ef01f48f7453b14cec1e73adf3a39b3ab4e1abe9ea8dced0253790a798124f1fcb2cd18e948ebe64c13c25d00b3815f787b434eb9692960ee7c00d940bb11cce899ad22b3862b83209276c5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2000f5ebc514c12c327c3275990c09fee21dde8ab759378a13f2436f87eef9131892a67f6187eedae10b9505f74c1b8300c5a6060e60f0699278924069e82601	1624643007000000	1625247807000000	1688319807000000	1782927807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	137
\\x4f4557e9d5c730ccc9b33b4d9f7b99e1f004130f1d84b05b5288aeb4ccefa5161dd129d801314c6e55e260c8c886f44a5a46106e18a1d8e08f87a7b97f0c04a8	\\x00800003b161c79587f7ecb3fe17406e250543575541d15ef8036ed835fb826d1bd12219293be8c29bdef7ae0e546883e6484c18bee66aa53306bdde44e81455620e664188bb9ebb5e3fa72fda7b08eecb845c0e59d14ea1c7c23516ab82e00f4121f3bc96852b77c04a0f5260c42377c4143ebef17bb4f76b928b78d66b628bc23140ef010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc68ec437a8422cb3e01121ef7c029b866b4e4739b18308eac319af3b369dadb8021b1576e15e2223d5c5d3fb5b891bed0cda143818f239fb1a10e230a6be530d	1640360007000000	1640964807000000	1704036807000000	1798644807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	138
\\x4f5943b913c0915defbb52b6720cb97bfe1797f8d11a7e41218990671ef042b55ba997cde07a2aa8feb05ecc5d9442735286adc0210aa92622d663ff4479b56e	\\x00800003c9e749ee100bfc09bb57b27c22882759e45ced504360c53d419577fe5b7ebb50747acf900fd6111d0520ef72e52cf5667e2a80513cc5d6cf188fa5486d2cf996726259f0b62de37831747fb309600938f9c6be488d4bdea1be298e0fd04b54cbed2f6214b49d48f54ce48a391a64a400030cdb019f6a56dd991d958fdea3d3af010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x331188300d71a6d73ea5106b61cee5f71ca00c616c455b0e9924cd150d7abac79639f80cbb4dac4b885354704aae55dbaa32fc8b6f9494b7c7602eee1908f30a	1634315007000000	1634919807000000	1697991807000000	1792599807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	139
\\x50112c23956eb5b8ab59994bd6abe56f48ce73bd3b8f985cf625fcd2e492385214b0ee1dbb2a21d8a3802062ba926fd02ba5ddb8c16a630b63f649e15bbf23cc	\\x00800003aeb2e558f2784df8645caa51953b715a1aa5d6abc816990901ffb89875081ef3e46ed270f6733bdb3006d2e07468a35d672aceb8fc9026aca59e59df0e8d405bb2a3133b13b8d5f30bc1e2cd7fc1aa2955d57613f3ce4ccac6ba48a100672a7d0dd6de3d128bd39703912c5bc4988ed40a1549636e0ba048e5697bba89536929010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa124f8584866ae24b33d3b0b5070f21a3397401316a512f6d5725e3e54f4ebd615f18afb399924582f892339adbf8896cc9c684666d3192ceb068880f681530f	1615575507000000	1616180307000000	1679252307000000	1773860307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	140
\\x540db7e8e96131ba582df2ca40c855a8d777063a127e394718f57cac419a328eb3a7f04f0ebb33856f45790e6a321670eddcb4b8293551ed03c376f06886ef39	\\x00800003d475b577af4f24f7479bc37ac3fca4a278bfaddc8464fae73717c8891e67cd283e42951db3e94ebc3612f3c03149d4396807c9a60f0c5ff2ad6c4ec533992c4e76a2979f1f064dbd3e8ed251b54984006d3c47dab590d0e192adf8ca40ecafe23fbd40bb0389fe43e9d34632d7e5bf1b7d7bc1f701cb51549e0f6d23b3087efd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x4e360a24b1c31fee30b7cba25f2e05c408da254166a6813d17356cbfc17ac1c00d64c23f3289689ffd010419220cf1fb8f5974494772f5a9d61b9f8e1ee1150c	1634315007000000	1634919807000000	1697991807000000	1792599807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	141
\\x55815af580dd32b840502941b1aa69e19f7de55c613b368c612f18492d432c42d55c47765aac83ddc4e36b9b50ebd42aa72a3a180694a6d70a0ec4ab533f5e52	\\x00800003ce1e76ea7a65574d80f45b458b432e80a2ddedfd09a8743e24ff5399b5dcd31afe940e7305f3c21169c8a7d711017a34027b490bd601fa79e71ff1f1898be1cd94d37e6ce98a58207ee6b507bfe21e307c43ed9fd0f874ef7954e9934d93d7abf36a19c2c67e54a8bf40667348699d672a25bf3d9fb70dae93c13f6462f65e0f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbe32cb63127119e9d47c5db543cfa56eb984bad784c0bb0f32021d338d84f72d4d394e69aa9ddf764d3b38182f63f697f5db0bba67fbc4ce648c26672f31bf0c	1634919507000000	1635524307000000	1698596307000000	1793204307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	142
\\x564931d249e3735230814fa63b64f2e135c5dd26d02e4cc155535fabc1b4147477ea62e76c56115fb2250ce6b37083d9cd87ec3e14d17d76ed6d85e058a8f4ed	\\x00800003ab273c4a43322fd03d461398f9831c1f4d20cd9530f12e73e57a52882f2f83ac04276737282beee3fa012bb4221c84b282658e506cb8abea882be932c1438c539b5e0fdc6f9d4ed6eab9a4199b56544398f65fb2ed105f0610e53f80b26b43044784c046c269afddede5c08d615896967f032308a18cd58481784dcff5604dcb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xba9bcf06d3c4df1f5d97d9a722a9f5afee3625bc48a717a02f28bf39ac8881918fce43700097b11f593641bcb984b7c03a7751bf31a38e8eb3a7d846098c2502	1613762007000000	1614366807000000	1677438807000000	1772046807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	143
\\x5f5536f65a2fa39834514c37719140ec13282357f959f3524cb6ca7ddb3e2a79e2129fae5a6ceb7d554f2913f3db7c8be6739f2b93da357485a6eb537166255c	\\x00800003a85734cfc431dac04c1d94472b44a2f69b9c7887424af35f5fd3d21b11f6932a4f4093b2d32b7e74bfd2f8de672c1dad1a0e7230b67d9b62a90a5deac74ce326279c7df28069ddc2a3f36ed1773d5d5f72dc930c1e30f8ee5f246c05f284aaca3bab763f04d6d95cde0dbf9f9b741ea96e79a6650c51d6f3b5053e4b4aaf145b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x71ed880c0c3eb88b9c3e1b5d34157b4aabc8296020407e323220c058789d1ab6b52428a74e21e62361d80cf6041b05ecef101d53a58c122f798e91624ced1d01	1614366507000000	1614971307000000	1678043307000000	1772651307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	144
\\x5fdd73802339712b611f16a21b4e85bd52cf3a2e03bc317bc0adfdffb55012c2d3168f558d78e0b5a51c72845d633f5605a6f474096e8f12702bb5842d9f1b02	\\x00800003bca6bc161f08d7e784aa21c44221e378f09cf25ed20dc45e498b1bd49b6a365fd2040c936f979c080c71f4224d4a74595ca77ee7a7e9a9c65b2eb96500f62cf04c26459978d10a654e99407c242f7b99d71ebf285e9a224a2f68fa8fae674c482cc28b061a0febcb7e9e1fd3d3ffa8029bce3a01b02446a18ebe54444208631f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x99e42b07a07f12b0ee04bd37a19fbe86f1e5dd24dec8e1fc6b7b41a7ba0db48c5c9139d428c38d1b49cd82268091e5deefcaeb31605841c51daa92d332b1df07	1633710507000000	1634315307000000	1697387307000000	1791995307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	145
\\x60415e0a2bdca8124277e7f3f0056fb98fc81429a2e8f69df8a05335a512f20f478975a80867b8ab819a8b4eda13bbb00fa09974b0ab54f6d5f32df9d75a7c06	\\x00800003bb3941ddbfca6db18dcc2db715d09ca5d905d411274a0529d61d3b4c7012d62e2920160f463e4e098de20460b61aed4fbf571de14c032da07ebaba6c1c91a00c29249cbbc17e000ca028e1c1fc0d1cd34ecd114ebf6732e014727b204a994ee5f5e7a856bdc58c10df6c6b306fc34da00e2ed2577b50913398ed4d7d529e2703010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x08472a5573fe7af11bf3abf69142ff819655f64933be942a1bc5cfcf99cf6b3b0c7cf9193f93f43f24f2e3f799a0604c81f8db31271019c899b82d8a945b6d07	1610739507000000	1611344307000000	1674416307000000	1769024307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	146
\\x61c1ab26062867282c80b066304959b3b80309180a431f78f3c0c286f62598c8e9d5e0ce284a4e3436a6f3253a529b4f50ea85dbd71fe7193d925a76045dff9e	\\x00800003c09d03b6b1c26bc2fcf349916033850a36e4c03ea6e64753ae07a8c565b63c485a384887acb329457a688f2c3bcb56c65357d21f56bde821d0e2e921228749703c7c9269684284c9b8d95f62af809cf9757e7cf736d8820744e58eb125fdaa3223f318568d2f210e6ae54ab3dc59da05024f5573a55713e63085a68ff3ba5493010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9293642160d1ca58d4429ceb321eefb479b81e7cb48116f4bd80d100d9b89222881214002a1c968f9701f3790c7aac546f38bf7ee6bc9bd262bd631a35029903	1614971007000000	1615575807000000	1678647807000000	1773255807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	147
\\x6161a45032a02e7e0b9b180db0a57a81db61230d6fdef6c7cb539a6ddca3382de0abfdfb9dbcb759f902f377c97c00785ceadd60a6378560f01299f074335074	\\x00800003aee9a1617b2a87867fdeea9fba8bed97724cb5814ca84f12bf9b6e3a098c0f66f7248a3013fd310df7ff09cbee0722b6e9bdeff66322aac85736be8ffe73bf7dc72d4318be9a52cf12baa88a0e499a59cb7a8916031cd1cca617663490d1b6f735fb4be324f40370fd90a5e7913058d71de05996696e22126e71922faf4e51ef010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7af6cc7f162a82239e11b3a5c4919b0a1921a2c288b242ed51d42efc8f5adae1c1e0387bb251d4186af020aa0cc04a217b59a6f6053bb62eedcd397f70af8305	1628270007000000	1628874807000000	1691946807000000	1786554807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	148
\\x61f9e612798dd2cadbb8517104b9ce8b149c9ca40c119feda3aa583601f551c09e132a9ff72a877adec0701231df21a459a3ea6b0e2464f1e258cbf214f54a91	\\x00800003c4e7edd8653f555bd3371db09016b3cd7b70d55279807b3aae1eec8707a7dd33a07a12a5bef0a6e971957fd30e0e4254e50ec3192529b38c4859dd28f48e7729c75bd851487235c1c15c050eed556f017ba6233be40b4c6986b5c64b6bbb7650b05bdf43a5b12ecf0ad49aaeb5bf2ff9da592c94f6a092a293b7dc7820db96d9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8bbcb731cd4e0fb391f07baba6a673475245cd9b999a54ccd9a91204e3d68694fa530d8c9eb10e77d112e450ad519ec3dafc1dbf9d0ebb306da813283758e30d	1640360007000000	1640964807000000	1704036807000000	1798644807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	149
\\x69498462bfb89bca8176d26d35cbc539df07282ee680d54c94e98ebb14bbb7a7832223646eeea9710bcefd7fb9135f5193b91a3bbc075a28b7b084d6d6da101e	\\x00800003b5b75a5d3c4649f27269b446d574c0582629a1b66c12f1a26438af4a7d06ff361e4a662f891eebda5c093ea064983517b1041947c6f86bb962e56a86aa8d3e05785345932410805f84ede7b60cb73ae068dd2574feb737b110ccdd85df68ea91359e9138083970887ae8f6ff0d5db518197aceca573f4f893e743af5ea138c51010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x30708d4639892493072f79dde74a30374380af42db75e47c55b0bf76226d3516e744f451541a69c42f03223f379d398f542fff6489cc77e7c21ae1a7f175bd0e	1611344007000000	1611948807000000	1675020807000000	1769628807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	150
\\x6a55dcba7f0527886984b4c0095c0f8b02197e8cf49265acbe99be0af40aa12ead7e5161267befa972580234092f37be70f637229707c21cca43e28aa10f668a	\\x00800003d79e89f6a5bda4744f312da3ea5cf5b412020b040bc2138e01479ac893eb5feb504add87b6d07082e2239924df8c7f09cceff9105d84d43a1bae10d71f6cd058641c37dcc6d8a00e280c271e1895b1ae8176e20d6db0856392817c65edb8da49e6870936dfb499b3cd6b36e6a9abae005b6cfbdb123f06413bc2fc13a30aa29b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd8cdc79dc75530b317e8c2335cda090acd1175829ad652b200d8dcc5c78c6dc2291acb27b9afd85f1990f887e2bbfad4dc0e8a5f1a164004e977d8685a177f07	1631897007000000	1632501807000000	1695573807000000	1790181807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	151
\\x6a7d5ba2254566846d3d4c7187815d2b0036e4223503e244ddbe7dcfe78a0542c4c3dc1e440a6f0c38615367982c16f5c82a4748be3f507c192059eea985698a	\\x00800003dd3b0575b9b0ffce50f4c0a681ff4718e721254010e8dda7ca9016e5498fc4cdcc0a6b36dfda648bd342cba376b3eefc4c2fc5bd2ae3c16f4eb2f1c56b205b9cdedd44ea6d1a80acef329cd0c272aca74941a49ab0b4a9f234d0be9211cc76378a197a2737f5dd65bf4f08458778c296bb6badf311bbbf75d062cded013d7dcf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x992e4f5da38efb5e9e523d539573bbd8110dc920a7843ad29a4330a1c440d86d6a8f3e6af0abe4d877a1b4e7b29ea03adae3cdfbde08368368b10e47b335eb0c	1619202507000000	1619807307000000	1682879307000000	1777487307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	152
\\x710d4e5ec8e20ebf6eb164331ccf50e031348fb7672212574890b88670b3113e0ee82f500ac1a33a183608b2e63d9f7eb97a35b272ec0f102fd21b6164a76a4e	\\x00800003ae6d2876dd05aaa1ab218863a4e3506eba76502b3b1c31d1332756bcd7996f785ed850aad6ec4bf87c56544b58e2e6bb328443fd3d05d3f5f9d57081a1dbff7919b72b83b478cde8183b8e90c3d1adc8a456fc5183bbcbd3700f2cb53b447396c2cc7fb553460c11924cc2190b339f0a7b8bdc9171fc8d7cc783330ede8bc707010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x754dc340e3fab807d96bfac6f3fbf065f4a2a56128ec40298ab5b0a64ab5b470f2e2ccd2b7030a53a2598edc4591e80f881cf454a43a18405226d255fd353b00	1634315007000000	1634919807000000	1697991807000000	1792599807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	153
\\x7221dfa6badc6586c3a9d57f9eb1fe8294a229c35513ae60f65adfaebe71c33d7e109d3efefc6131152139f88afe1e2da48f17fb672dcec91d1503c8f8577fac	\\x00800003b9b5ba753ac2f68bee6242954f69d267ab692d48abf1e148ef55577cfa563969b74edada941833b9fa79196e2398390c407970719d6060f67ccc24fda3d53ea9ef8122d3d518c8507ae95a154010a52b671c5d42ee72fd493181ce1e26d01a5b2ef3565d37e6e6810814b558afd453e6b643f46c985fe860161840133dd4f643010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6380a94df6cdacf623a752947998dde81637230eae77ff6590f6e4ae1739abea571025d0e580bd89cf65e9c74f9b2d690685557a6e3a934b51b696710c955a02	1615575507000000	1616180307000000	1679252307000000	1773860307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	154
\\x7409f72c848f21c03b972698d94f97e71fd84ab04929f9f1cc2b6cd8c0de5e59606d736ff2f9766607ef126856eae9f36da12f100575b7a4dcf007b87be61eba	\\x00800003dc4a2e1e0b8cabe4ede7e0ea9347b58a8f71dad76a4f2a7a9b8222c52103792240a4ead3ba13f1bd827b83463c476bd1defe593612179f345af721f425db79fd3bd8ef8dc1ee824fa013a9a191c5aa52efa53667d00d78e283962e7b981398a1713c7b85007669674e885f2b2d36a7e425f245c7a99678ace40591ecb9339709010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x06326cb9ed64856665133ee0c2df7087a773d5055675e5b9c90a1e33cad6f71652286135a3f207cc372d9fde295b586dd9dcb9430dbf819f70cf22ba4c06eb0d	1610739507000000	1611344307000000	1674416307000000	1769024307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	155
\\x75a56fe5bc6f4e2089324e95e24e33b273ef8cd6abafd9132add6692161a8aad5cb7c3f1609bb0382301cc8ddc7e6f4052490953a61d74ddb1fd4109f48326ed	\\x00800003df4f28614053e75232c937b7eca091e97167fc542ac277e3defdd2f0180eef6385a8bf0434d397782a5109313761b15366260394dd35a68c7e7b9e087bc39a551dd5b080841869afa186ae937e3d2d7b17dfa6c99d50958fe80f587bc70cec9c6f799908185b11323cb9c98a0b5a5077c560556ff55cb5b365765abe92c49eff010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6968c4b9303415e58bf0dc90cd33a44ca527f2ca42292ae2a98f83861e536603abf28578ac8eb20a3db6103763faf9a75901ddb7749eecaf33f46731979f480f	1616180007000000	1616784807000000	1679856807000000	1774464807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	156
\\x775dfb21c11726642671b5c5cb68fe02e77ee3d81c650d910e056d8bb53d28eef5c7409b7af0dc046e69b62ead4e53823d5dccfcd9d841073d8eabf24e533b1e	\\x00800003c73b07287d38fc341c982a5618a2f4f6f4f8b5d4a904264d6a7bb7d537ec8f7e3852e4209f97222853beaaa7e5905a101a6dc8a9f372c632229f4ecffb54f8686e4f0745b5fc089384d1dda49079bc5f71c017b4c36f1c29855e4d2543880fc3607ba01ff35dae867b91d2f171504a84c089decacc318246bd46982e6d16d371010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x328fd82d4b0a0dfb5f04fd8504bde1556ccd7679e3b4d277580dcc3ef5974b0fb455a5ad06e467bf359e5d6b741c7bd321dda3643aec64de1737d82887ca680b	1637942007000000	1638546807000000	1701618807000000	1796226807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	157
\\x818d266216d62f0c2d06dd90b6129a2b7691d31f4f4d89ef136195224166c7802200e301620702dbc1d23dfeea8444d7e8ac47b3b9d4783023a6fc9d8cc8f6b2	\\x00800003e887383cc66b5e3f2fc0bee887a411dfa8f095720a327193eabf96ea329eae6a4d64c950b0a7edcb349994f56961d46bc9d0010853709058386a4009dc06d95ab094663562b938a2f8361ab0fa60930afd38041d393e99515413ac0e9e2359f14c6421a73197cb3f9781b840e4381bac4ccb005540f28484a1880cedcd187e37010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0cf92bccc3e70fa986f3e1fbc24d9f8e39aebe82bd7fa59e7f5a41213aaba0fda8bb34cb8cfaefffea07eb5ebd30f2c560bdfd9f6ba1296a52990f83b5df7905	1627061007000000	1627665807000000	1690737807000000	1785345807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	158
\\x8339f0541ccb632f0a8b087d08eea215e770d9aa2650e5f0d650fc1bd9cd8ac2786afe4a87c8b089d17cddfaeed927b19b8213a7b32e3c645e12b1b4fca40ee7	\\x00800003d52c69ff770026d0f9e7a13568e355e26e3a336909f4820d4ddd485faac157cd851d715bb2bf4367924a422c364ca466e7d89ba81f22e179d41cfa58b9f8c9fcb2c697a5d795d910ed663b3e55d040a8d6fd01af7e25039c13933801087315e2b028bceb83db076146a2dbf9c4b3ea005902c638835165f8027e1a55402a8623010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x533de43a6ba4ccb09630445d37f29ce7a25fdcce5e4f177e014863a4ce02252564fd78cce4b781738b6115af9c9001f3a01fedf64262ae2c9ad63deb9225910f	1632501507000000	1633106307000000	1696178307000000	1790786307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	159
\\x8e194943fc92fcff725385c473753108ca9bd19e208c7e13d8646bb7fa2a6685d7087b6cf6a0c6691e55e26eb668d9904c2c6e60d2df86127f7eff46294b714d	\\x00800003c1cb434de282089011b73f0deb3cc813240513099b1c589102a26698f041d81f8f3a23711e29d3547e36522b3e851f500e31225db42246cf89b20bf271f29c3519071f4b37fb24f8aa517ddfbd41ec6081fd3ecbb53dd685c2b304f38bc66038b4b24cac1ab1992a36edcd6d040a1e38320be1467a1607a9b7ba2a6ae1579713010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x129f8a8db68975430c4502c7a9ee3aef46245429977134db50490cd83f0226afdcb61f97f8a4b474bc49c6c22e33c11164f5ebaa3698d7594b9e8c2f16b82607	1634315007000000	1634919807000000	1697991807000000	1792599807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	160
\\x8e5d8c85fd7e41b6121f73944b70762f0c3b48431889e5f506372412bcf41560e26b3b643f0a1fb028866ec98474beec5768fefbce7f2bf0c71a2beb09189e59	\\x00800003cf4f56c2bcf1e1ec0fba11c94ccc2bcd9fed60ed7e9487b402cb5e25d0cf3842ff174e14a951514773ae96cdd496e6145947d4871105fcbf1b9d33c57163b96f438658a89ce1e007e67821f3b3fadaa71acfbea4c43fb7bead378d57e9b7c72076108edadb26dcb0ba6cb63ad36339a4288c0d3f4e055b442a994312a16e2837010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x25e51a530eb45c1597ee542d71f21ef3f26dc6c547d2eebaa3890232f6106e4ac5d78281a5b203fd50367dc6815c821377521575c676ae7cdc5e348dd548f20b	1621620507000000	1622225307000000	1685297307000000	1779905307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	161
\\x8fa5bbf579465203a2914665791b9eca7916117ad6f67dead2088ebff54c8af192c9de7967dc9673471acd0dedec0065109742dddfe89596b8ae7206b71f3b15	\\x00800003e7909cb8c4526482af6777400c179e23e2fb560ee6c68cf9ec7ccd71a7f8c04ab74138766b6cff55e981384e707efc53a01faf1b391282d6f5ef6a9e6086ff2d478496442957e6c01e94fbd1627190868e5b8dce58392cded8a37c25926897d17611b16b1d5cf7b59148b70dd518701f9a957c8b81520e6bc91294e39bf70a21010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe87e0b4c2dd87111df2c9eec153fa0c6d9aff52054feb267fb2862be3e7832ca3bef66a81c3f5aebc08b28c7b8ff6795d35aa14ad72627e12def3042ec74d103	1632501507000000	1633106307000000	1696178307000000	1790786307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	162
\\x92995e64e0928c0fc3f344f7632103617bf353381b1562c64623280ec02cc7c6c835642aa414365c8ba7a816b9a05779b02e401cfa64b9fbf0be2c756cfb37ca	\\x00800003a7570e278beaabf74d4941ee26614fa00d67f2564208ff991f687c1da86fc841bb144cc9453a3f2a71537b6f48c4c36dfe54ef90da45cbf7978089005df9e6f9989ac77ce8da7f4916261af8b8c39e1b07c96d32904b22f7b08875841b472718a5da99b6a288994ebccdbe02e0e85d2f6dc1c83260f89b55d5b6baabfa45ad03010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf68362c6d57c3adc341ed75bf8b749dc2a4160d9ede3c2f650ce1cb0708ad2120bc6943e0abdc8ba69182be0681bf72e44292f1f7f5f9260b10e46c40594a502	1621620507000000	1622225307000000	1685297307000000	1779905307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	163
\\x92c5053b5bc14d43ce0c443ede288f1e489e1beef6326755fb71fb19d7ffdddb134aed12648d7a1dfdcac89ee73e1df1abf3ae83dbbdab9ddc019268c4d2f027	\\x00800003ef0a8e69198458d9ee015b2fd8b830281bc91942b10b7dc7f02fd74a788e813a2927e36e73dd8911815628d456d515a5ce3ea1ccd5c7082ecf990ad25eeee0123c7949fcc11c1763558ac4fe4dd0f035a076c9b026a761c03434fa52ff1a86f328554861683d3b2cc7453c07cec8817ac97bca3842f55d25c4c2dd3a34b1d35b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8cf0a5990ffc7b851ac96f2b5230737b5595dd258893d4816715745d49b62f0092ddb55f5e59d865bacebb255b087f5b09b13121badde4147211299df52a9d09	1622829507000000	1623434307000000	1686506307000000	1781114307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	164
\\x93555ef152f6b9f68be875c0e1adffa49ee9f1e9239419f40a21fd9501602fd1a8d04956bb34e3386c7e52cd458bf496be55b708afff9193ea43091770aa9efa	\\x00800003c2e80449998a982e3b2e6c2662280c67027a6674da459f071324ef94b717c6e39d935ed305aa80cd6e8dd96c61c985702b6dd9c5b34eadb2e6c0f375e50a7d6c271fe9c8b5696b0c75eeea894742cb2ad076cb16402d141454c9a3451066112262f338ff077d193af4d98021f99aa3669c4d42c04442e2b5a3c04d284898104b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd0d14480b33d877233fe0d7f79e940ca1cba5444a6d8ccaed122d86ba1a1a2c46c7e72448aeda8ed45c8dedb23a29594a87a85de65a2abb38fd9a3f4ca2a210f	1621016007000000	1621620807000000	1684692807000000	1779300807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	165
\\x95b1a87e1e8b1f5b988b87a23721f6700bba8c3feebe77011a4d8ab01715a639a08e19c28bad55fefe8ad0fc791ebb08f5483f605b8c15b8b07f54fd57c4db5f	\\x00800003c2434c0a574946fb0e5cd89f89370010f38a5e026d2975a8d3e004f59a82bf0eef3544cd7d1f7b61c018b3abe05929add1863ac16dcb0f5085055d8833b944f688df2caf21811d296c9b9112919cefcb32046c4825ab4b76c35b0c5e833364eadacc9934b277de6cd90bec2b52a44b69a7014e539de0ee148f8a32c16194d6e1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x08b9d5ee97ef3d5c6205fc530b20a0348a9bba9cc33b8659f1e56873c2009f94fac045d2b276bfcf382e1ad6f99be4354e50c91b36a34d4475647323b3476003	1618598007000000	1619202807000000	1682274807000000	1776882807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	166
\\x97dd5cf2088523d8e9cd81c14036ed92937dee012a2c046fd9a8b275e149157954f78eea0da94f85c1d6f11f6e9dfa1be29e0a61ec701b63b8a16e748d15121d	\\x00800003c91e4f68944c02d538295198c4396ef2741c23308503809dd4bc884f616b1933bebe3085258098efa7df8bef2967e6c32be507a33931384cc3edf5f52bab73cc76d98b3df46fac2dc385ee6124c5630e596305e5ebf7ee985bf4057c50a760e4a2dc041999110088ed598741f6a23ea53aa27fa0d463e391950f26833cfaf4a3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb00681ea2dcb02b79ba3bc76895c5984f1480331139974c3bd5961d9700a1fe04e96188e2417aa668fb3d701f79c1467e38c4a035b7ac5dac1fb2474ae546e04	1621016007000000	1621620807000000	1684692807000000	1779300807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	167
\\x97396a0422103b8c19170ff54a69eaeca125c81fd2acdb41d04842c2334993527b5398d2ef6c0d0bb6da489ef109bcf417b015a9c54a9ce2d4f090d56f83a79c	\\x00800003936b8b7d7692b6c05fc93e849bedcbcaf937fe25ae10afe7a8865268023725c6c72749e589911fed5ade63930d8857b5456a6d7c9f220b129c35ca9ee9f29d430154dd0b5f1f6241bed5abecfd28c06e30f8399fc7c49555a5a2d0b968d1b6440ec54d9c9164782aa6c0d6818cddda1fefb76bddd230eff41977f563c93707dd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc5fd566ea2e6f937be09f4e682b2c71e1c03d29e46aa72e1bf82c13e6fadaa319379eab6b4def6eff0a5d35be9fe22a0c6007c1eb2f6647a307375ee2b1a9106	1631292507000000	1631897307000000	1694969307000000	1789577307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	168
\\x98c92c5ca549673ec7f627ad9c7e535d1465fdb3ea291091e7ef160c87b0e7df6d8e6665c211a0f14eca2e2e69ff7bae3e907d05d6e4f803313126d56bd75682	\\x00800003a9a880ec0f486f8976e54b989eff9014f590d296c258a9a6c8e722e60001de0dc27ca4ad25a57516b2dd7b40c54a351a7d222433890a88ddfeb2ab38d5d795e353a1b9ff49a9f324fd5ed4eb53635580df0720ca5bed944fb4d1e05b46a74a7bdf972b41a61ce1062183f86db0864e5e56ae2fd1bb959527f04a3d70e018e913010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1619c89caaa95824486ad4c3bcd7a30fddd3f936745d171b9765e11e21080e7a018045fa623cfbe69bb733c5f608027f6d2af21c7013ac4c2c8b1d1c067d6101	1640360007000000	1640964807000000	1704036807000000	1798644807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	169
\\x99f9569344474036173e7eb188173a5639951e4aeecde647316b35df58a7cb4c9800c3f4ba7a6a0885f9d8002c59749715ef1618ff82ac5ecc930d0e3870b5c2	\\x00800003c84e53e33081a476939cda8ed83f4748626719e1897c373c0cb9f5ad75d87956363414952b956f30176518767e683e3301434fb3b4671798f5362495db2a88028e81239b4de07add7909fd19a5688d884ff3c2c0de71d121527a0ea6966ec0e33dd40c0ff8db5c158c50c7c1b44956205bba8f7f7dd1ee134d3418fd549b05db010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x28d73dd5afc0175dc8a8690c24491f07026ea0ac611dac898657163970da8e89f7b29c54dfdf4d5a0006bc63e4dca908c0440c1655700bc7d0c38d43b4df2f0b	1610135007000000	1610739807000000	1673811807000000	1768419807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	170
\\x9ac5e6c79c506ac824b201d2bb3c542fca9c82a6e8e2640f36afcb9147dd483dcdc35ce524bd21effa48376181082b2bfbdf0db10b0538132f33d38c9d8ffc9f	\\x00800003f16ee3c3016dfb0c0a713729c67934fd0714ee7eb8ba35d5f8b3ba3cdbe4c7fdd807bcba2aaad40dc33b9e3b98cbab3c90142c4f91947ae5dbd261db506f917dbdbfde95df7067983bc198ed90eb2dc829f9bcf5e1ca155cdea5230c84d4422711ce16eb05112842e6cd88f4b2ea82e5bd56d0f6d8bc47ced50aae72e005b27f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x175780918ee3ae69e015bfbf8141bc4c0abe880b45dec4a0fb2e51ce026f94f2109821f8a017093f6e931855153aeae7ddef45e9133dff5f23ccdd0d2ed14f09	1625852007000000	1626456807000000	1689528807000000	1784136807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	171
\\x9a9941fd866ef375cabf32e55b45698a6b8e45bb662b8b4326bf2b1ea000fd5aa798dbad1dc09b7d9aff184cc1dc2491e92abf1c76cd710ada71bdb3a630a4c4	\\x00800003cf6eee29315c535593937aae389921d4ff64aeb0cc3395c270197f0f84c35888032e77bc7e21ae68222f7f302e179b03ed7ade4e143ff6b9aedf677e241e5e3a9774a5494518ccba9b861da78c0a4425efd2ce14fc42ee7c7fbe64b301da588a0c84c26971d08959c77b99c2a89d6839c69f225b66f6394a1159966c72f96045010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb9c7e1b1fc33fc85f9f4981324ccce7333e6f60092ed889bbf4fb0678b17384a873dff2130108f6ff3d12df43f6c8a2d5f913bd05db0088f14ba990f8f200400	1610739507000000	1611344307000000	1674416307000000	1769024307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	172
\\x9b11b992b51cd58bd8b8aaa8a2f0a580556a1f482c919d721b562c728e89c9ce00450101de8838fbe274a1a67351a485121dc7e5483d4e36693c0acbda16b401	\\x00800003b41fe4e51b429586ca7109f8eba6998b8646f1e6d67e623c16f8ffb6790af944a454548c537456a787fe282adcdb686eed702c9ca5f8a8f20cca180e3ed8457c959726aa3fa442216c8684c8d3389bea70b70991140888e4760f8922bab5a77ba927a99225a86fe891e500427e6e213fdec0e72b4e7863aaca73d6cfbea14533010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x92f5b4f1e218d0d6faa897aadf5326c139d5230b02806b74c4efd9ee2ad4a89015c25946dac9e363eb7c71cc3147e53df2dd0dbe01c848bb7a456420a39f0106	1627061007000000	1627665807000000	1690737807000000	1785345807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	173
\\x9b0514cc2995493643cfe05b9025b15093f674da911e1276a09a4ffb156092c5df30d8edb784e355d4056f9583d0271a1f14da3cb82134e09da0c076abd3c216	\\x00800003b4f8284e263e92268c918843215b1bb4ea66d79dbda6c94c241633ec2ea98a04fa7f44b3356f10fefb9dd009ab0c49c6df9664c2529830df186e913442c70fd436f658a9c7eb3f81631014ccc15348692c3299ff7f18be30a71a87523fbec7ef2feaeefb2c14ba5ce3719dc5b3cdf9a0ebf6686500948c43226a41090aefa565010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7a3c8b2a5901f694f109f751786e06aa2361a71e8665848c4969cdf4ddc259155446c160d5ae9d90fe820a9a1ebc14f52827ecc5c0f5fe17a8c1940b9fd9760e	1639151007000000	1639755807000000	1702827807000000	1797435807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	174
\\x9de503e503601616518ab91af51bcbba359fca1f1289eb9634c7beba919e036fd839008fce3ae08a05143804a270752c2a6705a5a759a38e29e75f15e8537a97	\\x008000039eea6015a35f0cf8f53d4beda0c765ec8c204e3604247d33c7a6997419229322b20baece1d4548bd5bae4d2935c2cec95d1345d18883b7a170ec1080f8cbedd6eeedcb5f3bfc3185d44444fe1e280d8461d2244bc0e1a3abdd69b548d94461ce4341f91a77c28f621f81092f8926c9854dd7236a073555d4225548f21e863f5d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfdf3305a39db47686ab3bb1a7162da51c59960c13d9e6eac46478d4d2c43f464e618f1810e77d8d36f03e8d3f46b7aa86fa035c15ac0278f96d7f388c264fb05	1625852007000000	1626456807000000	1689528807000000	1784136807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	175
\\x9ee9e64d55d07458089ff74c5dfaba5aa577e7b7a2170b2729cec321034ef9c0dc0fa460460b2f5ae579d0d4cf93c948882eeac6a1a0f03a0ecf736e4b3d20a9	\\x00800003b7fe9b505d8f9673fe3415cafbd74844fb4304742b723ee6ff32d81c5e57bd101cc3e90fab099cd8e729bd8b728544fff00c181aa31b390f2c2abbb689a4fb808d739e3ec3f87cb8add73ea95215476676808097ce77349d9b75b801344b85e5990e14650fb59395cee31eb129f714692deec15b151c96db09c46d505a87ea5b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbf64844e0ed5f911d3e77bce424a226a72948a03e8ed5a64683a35b26703db1e3f76abc5b31470698e3f6d1b7985ac32b193639dd607609c86e0385a773d2009	1636128507000000	1636733307000000	1699805307000000	1794413307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	176
\\xa02567d095e6d4c9768359a6cf96645f1229f19b400c57121c48e40ca9d7fad693ffc40b20869a5857a37357c730661a53324ae86b4f21a23d3e38df0766a4b1	\\x00800003aaf5e3a57a88f0250a0382c7a80319639f4806a307c777cdaaf8cf45d9b2f247018ea3f231f7464e32302b4d202cea6b01435393bbdb5ad9fd21d83811ea39f358fc17d1212c777c453d22db717651916ac5625f3a96d65531cc25b6e13027f8b24d7a94cba1b142db948d150a7510baaa920aa15d11b880cc7f8529fc2adfb9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x126308cbe314fcf24945f4feae7b6bd559635277521b4f41a386056dd83a8515b95d61affbb576bf34fd03a6bab2ca088e218a892faa1a66e224cb63f7bb770a	1621620507000000	1622225307000000	1685297307000000	1779905307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	177
\\xa025b0bb74c81c01badf07978ea82105b59258dbcca4e176622247c9ed30f8fdf3c4accac0fbc0accc703670ae52e60be5631b3ed9e274b891d184370a25bb8b	\\x00800003cb5da96864f9e11535f55fee4db7558f134028ca1756051021f73faf0d94dc61933903756ef3e9c5bd6d28e5c6e10b76c0ea9ed933e1101cd2250ae73bf5f21f5d0c71d00d2d67fa88aa30736b7c71fb49a2ee20ea853a17b6e4421ed933fb4e3338495abd004470deb12a3a91e336020dfb0e3a10b77784a5f5c43b975cd43b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3e206ed1563d89eb8f8e292270076a84396d1cb3fdff0d6d3a4de0204bde948fae4dc50c6cfb43d7f6da63e7c673c19d63cfa3fd3bbd0b13c6fdfb3341666607	1638546507000000	1639151307000000	1702223307000000	1796831307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	178
\\xa2755b8ddaf5e020f2b7c7aba2933807a7cc09fe2c3f03647a90b935a07214633b815dda2b602909b6dc090e72ff864e71d77b0db86c90087ddc4e0cb6f3ca6b	\\x00800003c8fc7d3949ffc21e14248a153d26232ca9b35c5d1c2580372dbd0dd452f9529105141dd7439d9cc5e1d5ca100f644053e3e902c646c7fda861bb63b315564b6ec96d8f59bc8f809da0f92f8f78259cf96f0d8a027c124eee28c15ec23308a14b0b4e7c608642f1389d050d52961d66af4ecc7cfa2a0ba7d62b187228a1291935010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xae9bb415c1154c2efd62dbacdf06a01aaabd4c74adcfe664a886d0164c83fb882b3821a88e7cbf64ca85a469c447bd47bf39ae5ee1185fc3ac5880c2a8a7ae0f	1621016007000000	1621620807000000	1684692807000000	1779300807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	179
\\xa505bea836415bfdf1d5d4f12ff91f5f1bc79ce18e79ce7bdada86fd4d9605576d21816fa5fff4474015fa28b791ba9aaa17e2612d19ca5481aa8379f796ab8c	\\x00800003d12d8bfd57b7b5683859a920db261f655483af1305b580bcd75af1a5fbf77932f48df3919cf2798c06c58d085fb2d377c4e95687c03fc44f8f3556c202f9f3dbca7fed8f1249e18a53ea8c85c0ea8d72d9c5544a687a2300d10a82e46bad9a5c726b9946a3b06c836d06536a74219c45f60fb5e879db858a1e9a8f062fee01cd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf4d2c508df0ee101097920d6e4e4b2d3688f076a9fcbfbd112ff39266e8bf1e0a12fcbe9591fd443e7ec95d49a0b28dd19ab6044aa15883b52b5b734c2e27a07	1619202507000000	1619807307000000	1682879307000000	1777487307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	180
\\xa69903e305fbf013aadb85b349d4ad13d2e7b2c8d594e58a42a124177e1b102fe40e03a28f55f0ea874555ffec4f6824fd9a0e634036100da3861e48b81e4ede	\\x00800003aeedc1f39fdc2be0598bab4bd916f73ee936f312aa77b387e11547f41d9073c5d331e2dec5b87ea78ff257c5d0fb6b45a9fd53d898233d3bd0585284bebfb26187ee8f94baac41b97fce2013ccd8d96dd297aabd2a6cd4b5652b5217b6c71c8dea3e721cf766b8206ad6b1674c5d44a471244c23fcf5e2b4999a2e8359c2bf37010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9b0af82c877619978779e12a123e1fe672402cbee98ff4041c25e16245e5e1622e03ec42984c757c9888cfe0b9c363e67ab50f51f9991c73dc2937a5a301d207	1633106007000000	1633710807000000	1696782807000000	1791390807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	181
\\xa739b4e8084753a133fa684228f7ecfd63a28319e79bed30ed759d3258ca4f1f0e9e14cd6fe0b7043a56390cab1f282a556cf801ed298cd5a54e62f24fdd0d85	\\x00800003ccfce0475236eec4bab0b2a224da5b508b757067e25abe568fa5c9c7f5fbc4cc5e9563833636cf4ca122c1a86453ea88839e88a5447dbf33b13505e58722b96fcdbd478c34c252439581253a25b5aba18d940ef03041905ab565c01dd1d269020c68e935e252d0c52f92e06b3909ef7329a04c7b75550aa0d5b8f8cacaf9caa3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x609d99fadeeb0d98442ab91e0058daed32bd7f4a20d10d463b2a76c39ef1915c8d1550523de93a7140b5491fed99eca0bf8dea4f145987c66f6b9fb118202401	1628874507000000	1629479307000000	1692551307000000	1787159307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	182
\\xa9490c62203d0a461dee644992a14233b9944c8b032fc98593c715e4564f2d31601a82e6cad5358ad993923d0815852f82603d55eaf9e2ba6d687051e34a4f43	\\x00800003af7f83373fbddff4acb81a89beb1b116cd5ac1200e157c2f5bc957792a6f2ba59473173ba78c5c024f74380bbe0a6959084102bfee256c4727e733043e3dfade09a8f1c2ca80d25a57c545641e391fd86c1890536c2e0f423011be80a41327ad03ad26a4de7059ea3bfd8425ca9660162a3d771f65ca02012f8ac065ddfd9a1d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd6fcc31dc718c183574a9790a435e2841fe4ae1c6d037cfc13d3f17f3c8e3ea9203bbb935c20f829f332483aba70521c63c1352ee3256f5e68a5114786263506	1624038507000000	1624643307000000	1687715307000000	1782323307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	183
\\xae7dbef57b8006ea4ec6f2187f5c719590e876b6e75c732b43e98a584a6ba8a26fd2d982e9e78aeb59eaa904cb4ec5a22dd23dcbf967e345513bb2ff86bc06fc	\\x00800003d28921965b5507155963e76c8bf415fc9875a2a523734534ed32bf397d0e9aaad1cd365687c6822d2ead8c73bd6d9c28ce80b5f38f23bba8163435852731784208511ca3b17028c954b5da794ecfd31f055717a4135eb94ff77bd958bcb48177c9382cd8dc20ba1f770406932abc6bc61737b847280ce9ef52f9b04e3f5aeaed010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3ebc855a0aa072fe32f23e470b17e984d1308e288e592f84efa948734817229851d1bbe63665faad231fddd45ae590bf94896de4e0065c03f682c130a98b2d04	1633106007000000	1633710807000000	1696782807000000	1791390807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	184
\\xb221926c439aeb65b7c266489e578866d3bded8d4a768e60d1311cda58e2491ac06c7cf103aff107ee75d9806438a80f4225ea21e409df16dc58a7239b1ec1d8	\\x00800003c8d36c7e428a4ad4b5102ae3863dcb6d74e80d7400864f20d637a754c6990bde590264ee5f5ab6a24d22816284b7ea23a5748388ceb104ca305ac5a81e991cc98db131d5a39f21d7fbc0e720003df9c52f9ed6edbd30c1bf88b6f6a2357e470b633a735efc3da604318771855876a0e55a7f05c9e7ebc04fd5b6fcf5ed8f19ad010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x78c2b96af908bae01e2f246dda3427db10d4cf2103b77d527528e63631cf4c3b3e317e42c53dd7b81ecc4bd94dae614c415b8e9b0bedba752164e8a043c6f70f	1637337507000000	1637942307000000	1701014307000000	1795622307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	185
\\xb479ef1b0ec463c01c36d3093312b82f85885903ce6479e252c8ae366500e09cb835e124eb8a82199d2761f919a31e5c725fd76433e54c39d20751f14d9c0c78	\\x00800003c0941c999c5de030e64164263935f8fed4e47144437b1f6067d76f0e4669c2d746f7016cebf638a98c280c74539740aa4d7aa98d8eb9ede4257d6b30dbefe741c0a00cdabe989cb4be3348e8c9a2afe97e411318444b773e79227c06cee0c86467d24c6d3d3f481f6a02cfa58c1ac1bc2e289fb3346bb5f5c0cdd961729f2a7d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa3414218b66b7b51d2be97e6dee431e23a855b1729e0c6f6dc29a6216d76b1d6705eecb0be90e2e345ed33488f661fde8b426b5fba9ba8d0d5218d0e5267000b	1631292507000000	1631897307000000	1694969307000000	1789577307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	186
\\xb585ea57accd6748e83c8848e0eaafe676dee39c42d8c9b5d2c033799e8420f7917f6a3122b1420154f490e135656a09e9e9e4f3f06c1b1a1e25e5545ecc0f78	\\x00800003c725d557f494ed9f3fd2d340725a452e9cf40df60f511dbcbcf2c2e3a6016b807d08fd01ab86a2a3dcb9f7567d4fcee62375cb471c9aa4203a025d4b45e102610193b0c2add00c6855079a0efa2a63c1aa8bd2676ba71265dedf98cb48eaf738d4814decc62c7e7519afabf50c0782c95065d79f1f3b72b7fdcd7f685e8b0923010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x856c9246bf03c572c94964cc6eb411c6c4c74f7d5458f8a081ee57187fa14b5dbabbf47718286eac732b5e53c5f2903eb0ac05d64319067d58bedb4c16d3740b	1639755507000000	1640360307000000	1703432307000000	1798040307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	187
\\xb62d640dacd96654cad5cea6771d488bf31d71ea7f92a8c3070a69ff5682776e30136037a0df843d5a5dec2969d1a3d6fc9fd6fe2f9b452942e9998390b6de29	\\x00800003aee198c36df27496e7427f1208b903e06a57f3c43d35e0f3fda0e2746c286c61cf98538af09e2c07c06b1b4762caf7b902adee618e973f41c2f7afa4fb1e11bd148dd590a35a5d710e3fb56d0bd8ac98dc1a2f5cba06522fc3d19e3d38b96cdcdf2524b179e6de3952d3e3923d5da66860050a594b120c266f46dd927bc9e60d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa90a15929813232497b179132c9b21a888a972fc9cf90bba52e3ab6ed06f0d30acde340b7e89f2bb8e2c58d62d994520ef335433835cf8a34343d33ca737ba03	1617993507000000	1618598307000000	1681670307000000	1776278307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	188
\\xb6cd548e52a518c474e6f3663ae6b9d58a27321fd49d659a17a3b26d4f226a6b33f6fe296de83ef43c7809c59c74e4533afa73f6d74632525936b6acd1ca5df4	\\x008000039b264b1a599a64f59556c1debefafbdecf85ffef10ba90f502bf8684cb5683c13ab9122abdbe3a82f67561af015409c4e0afe0d218f17a2984e0b93bb0a37ec2acbe5e0d82d32deea2e4943ca5841dc01e1ec554ea2a2ac90b1c2c901533a344bcebf8e18e05a7d6b9000ebeb396b88f547e388e157739636ac43dee8f2c5f19010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x232dec7b5b0cd7ee236c526df0d1c2efe4713583dd962dd37ca3364dd216fb79c9718f7cbe9a4b763942e29a9fbf267223d45d479dfae7586a1d10dc49b33208	1627061007000000	1627665807000000	1690737807000000	1785345807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	189
\\xb92dab00b81d8c4e501adf07560a18511e46641c706e1a3011510fc0f04504868d9ba2b0def0b47c8802cf013cd885d97a787412fb6fbd66a6965ba53cafd2f3	\\x00800003e7547956ad113f22a3a46acc446b9e5de1393dfdeba4512e2a1615ff368059b1b1f29a3dcbb2dbf0a986121f07893565548ca4e0a0422df69302678283a17cd942899e1528732a98cb545713c76808906b8afc866bc99d78e9a9759032b6a987d25734722b0616ccc1c05889110725e395abe060e79e8485ecffafb9d0c1509d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x48235727a3b3ae22bb43013b19113ce65123dee7b312a92611d70849a3e2773499de475e9f388f3d43242d8ef105d1418076b55e8c5197c24a799d3614dfc20a	1620411507000000	1621016307000000	1684088307000000	1778696307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	190
\\xbbb139b03e953757dcfc20f8a2e1975fc3b9d378c5a011cc25bf446fdf7fb9a5f8a1aead4b0e772b8638672b4158a9e77850cd79b6ec5738982b31c070ea76f6	\\x00800003e1b352f4ba507c7e595b1bb6d8b48e05c4616e28efc04d01e0cec3b7dc01c058a72b6a4b3a509acf262e07f4217ef3a8f4ab0676e76077ea7b5ae08e118624af6270cec032ce81829e6960437dd42a88cabf3b281dbf11d6ca493e3386bb6150fd07d963f8805feab265427387ad782e7d3cdfa61e8c3a783fbb1bf1247955a5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5a417539cba8ef84ad330951e877cb0747baa566b440301bac4234e159e9794e44c0cf904a2abe50fb2eef2b9cb1933e31d74ee5cfadff3c3135ca8fdbda2303	1627665507000000	1628270307000000	1691342307000000	1785950307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	191
\\xc149cd4f345d066c043c07b52c78ca61f07a25419aa05c46a3ebd770434941ab39a11ac7ec3cf61d5c8793605eba809045b82a432967e74b166ef684aaba1e81	\\x00800003bf1e2264c7453eb0ea0fc507d18aac8290c8c72e43c87a34d315fe49e0f568a385df1abeae5359f43760df6f26d7f03a61dd4e297a70bbb2652d2026a641454c4b267c4d79105160ba353ce968f221f424b4270c5fb31f7a0c66e74348652344b6addf8f4d06559d60389614f39d3d33241e8484ff2f318d5617498bd5ad049f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3bf93b9a05421fc5bfacb3468630c484a67a44b31cf9d99826b28cc00c738f6ec2672d1f019b589fc11f0b74899098d40925f5242d43aba806d27ffa1758b605	1614971007000000	1615575807000000	1678647807000000	1773255807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	192
\\xc3797c72375e4272d29c2adbf8fae4665c3f3290cead4f835f89947439f6acbca6c219f08e49cbd650fcef8b6f8065f3258eefa76fcf7cb0ef261f842716b4ab	\\x00800003b87431a4312b4726bae961170dd73b8a9e789e5d9415724b434c640e7676831805a1d0610e952ce337a1992f19ddedc1fc3d81d2ffccf849d22fafc20a0557e3f812188d75764e13802620ce11612b31f9aa54955c3a34be142d27f02f04777ee0e53625b434f75a1c4981c3f303aad11f19c7b7b4690cf9101e1faa31ac262f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfdca4242cd174f3269093386cdabcd54c3442667bdc3d4e77c725dd960a7adbb272e882a49cb79acba924714889f376a39ce7f8e66035b5dcbb2436464b32909	1613157507000000	1613762307000000	1676834307000000	1771442307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	193
\\xc4fdd58d102c918e1e661cd8bf9d039ca7fb0ec1f7bb95c1c8d46ffe78b04238cfcbda813b70e122d8c6490688af75a944831a4d12fb5a852a7b49ec41458e70	\\x00800003c41451f0f66e0ee58fc9159ca79eede58923f62fc537f9dd9ead8c9a6bf93404f25c9ecf1a366528c5eb09a44525a3d569f8fa55f47d64eaee79feea929c0e398841400f3595b424dac6ceda5dddbb234fb680e024753cd51658369d7f63ab6b447322287fa21bdfa5d7011f61fea7406796e34f77c8db7a624a4dee8add6133010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc0e64b8df43e705d0a777fb91ffcacaa2d5bd6384db7919e55fe3a04e0fb7fb7169be4b7f949ba914fcee406c6320cf44daa6f3bb458fd794ae462d31b1e330c	1635524007000000	1636128807000000	1699200807000000	1793808807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	194
\\xc6c9a4c628db1ceecec0b6f912ebfad107f9f9a8513d476f745cc3c97e6f250079cc2c6e941560fdb829aa9576cc62b824505b1c984b4fae9041df1577b9bf32	\\x00800003b5dd737df3e474177f6f2579131c5ea4ccefd03aadbf0cbd5e6d0a92ecdecca984f54c2e8fd2f2cd0f8eb0dbe85822105a6462d0a9b68a77bdcd43ab9b19ed4c83d36a3f3a113600924037744d4cc1e42f13e6764cb0f4fc51ab982127c5589aaa83e06bda3b45c992cb18b5001f3f0a3370007ddc6704ac7779ff91fd4e71cf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe305823fb15de1096cb2a4f712992a6bf69e6e0299ccc0d5cab448e6c4abad6f9adc8e90c46a62dbb870cf36a394d31c3eb610cac610e1e19c6fd92a700f8d0c	1612553007000000	1613157807000000	1676229807000000	1770837807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	195
\\xc7edcca3e8997b4865b9a0be08b9ead5168815040f84b8688e3ac19902a605f59a8f37ebfeb567e0cf89c439ec8ee0e48b8b5c669cccbfc8b1eb0a6d861992e0	\\x00800003e8549bd1f629d1d9ae1c163e3290e1e946a71010e03cb6ddd47244d27228b09dd37fcd6e3114a8975c8d5341509c671d6b6662b87430afb4c04cf575b98377db2809cd021522958dac3c709b3354ce3f5367714e9147ed96e3ea923be776c6f793fc82dba95a6e9f628554306b198f40a683aa59700f743a011bda644e5e04e7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x35a884e4058611554ef5e1ced6df2420a78fc9ac43f0ed3f554782fae2391bc90889cabed752540f43198e0928e3687b40e258ce4c99ce3e77367e993b5e7e04	1634315007000000	1634919807000000	1697991807000000	1792599807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	196
\\xc8091fcde9ec7ef767c17c9f14c09aa2b942f11f0811a25feb8214eec5fa1090727fb46b693217ea51d3341b0dd06d901088ec927e49d526bee866150c04ef72	\\x00800003c17d7387ee53cd667322699cd988058d218038a1644d40db2ad82842f3755d6fd8db1b554085181a7e6a01117e52e7d9a93044e52872e0174b910a5ff29e94c3b27d32e411d61fb00a832b65682fb8bf932afa8fa5bc278af4f75626dafed503f201c7c0befbad00d1a95063046c5005466e74d8bf17e550d9a3610940c62f0f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe6db3b7b44c958e388c3c8c441ca82183c113734af36d963e9fbbddbb76327a99d789b5ec31c2329d6f07c6e2c1ec62572be5bac78dfaf9e2cf80db71fc22b0f	1625247507000000	1625852307000000	1688924307000000	1783532307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	197
\\xc9898093d004bd3b1fcc862241842e3615fab8f9cb690770b63695d015ac5bb6501177cef2839ec91ff918171307641254343c3c47c818d1c2229c07b7b09a2a	\\x00800003c2ef72735325fc97c2790adfe8f3e2d5391a1cb2b09c78d00576822d99294c2368e9b0df2649a1816967ed925cd89df31f5ac08e246201fa26df27d336fa86a5e6dd3eadfe55d794ff8a64c965c8d9fbefdec500d84aaa940bac476577ec2aaab03a7f68a7b4e3275e8b829b82497149cec864b23fcade7607c2ca764013c193010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb06186ad90cf3443d908488cebb66567e1246736bed2b7ce86320f1cfef06286f6cbd833701caedb2df4b9d8f011d7652c61221004db8c5e74a5848863b8c604	1617993507000000	1618598307000000	1681670307000000	1776278307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	198
\\xca39c6695000c0d26aaad222c2faebf696ece522df8d46384634cec34c1f0668deec504bebc9f3d66335506195517410481d29fd202415f75fc321d8de245039	\\x00800003d12e3e1f5317340de125c63c356bd4ad404a6b1cfd2c5f72dee2c04b94e0e59987e5037d1619374b44272d7dab829536579f662fc8d10db2e0377694b8689a0cbf50bc209266c53f96b437e7142265fecbf60eab67c6770db13cb67d8294ad600a869c461a4d16b206242a6952e6f537068b5339ce4a1c0667c73595bef80703010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x4945169a0d8201a9ee13928bd0c5629a0a6967db4fd263b4f2d0a56b738446a9543133a9fbd431f9c828ba75f1a34525e823b64cd7b692403222bbdd1a7a3b01	1624643007000000	1625247807000000	1688319807000000	1782927807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	199
\\xd0adb85098c654097abb53c4ff8428d911a4d6031936051316614c6924802aad7b68698142f7cbdd6d77d3154a1659fefb8fdcc18f1349bf0db9657f03c12959	\\x00800003a5a7f578fed9b1e1ce5c8384a6381a6352660124444ab6971ba404f009b9ff2477caa4b7b0a525def7ba98e58605d2a3785d83e248c3bb43a236d3484c4a437fc70d87fddd31c6dd5aaaa1ca53d1bb97450a467d7720f650e48bb61380eb830e4f7380a4728901f5c9d39d8bbd0a57c46fcefe0e41d1b92e44b21410503f0e91010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x51ad3f5a0b718516ed6f99ae53a52da42e8336b0fb37d1cf4e03e83ce49015a234c7a989850172144164183a44520ec7522d3f0e54129b922fb5f4db7daf310d	1615575507000000	1616180307000000	1679252307000000	1773860307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	200
\\xd441a92164f73c22f6de6aced033fe3f431f959004fca5ed9a8a22588d4e429726bbaca80413c0ce9e7dd101a41aef2dba0eff43d343d6990a91047ee694d39d	\\x00800003bd230f9f9d95d432d0c994504fe39618f0112ea5860918217231a83dc4291dc67aa9557ad9e553072e363b663c7d73b283797c4f194d91ef8ef11194263e14e8edea67f4a4d7de8e25b33167f6f8d25c08b8f5b930af81d8f1f756c5517d83c74cad9c3381f76aca7fae57e34a35cd9f8440c516df0f69722ed4d950eb19123b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x25d6ebd05b50f6d9be7c2bf61c53a0267e506ffceac9a428135bf9e479cd2a225b91cf06421861657646a229b5ad8a32192deefed5336a4e7434f87cd4bb0e0f	1632501507000000	1633106307000000	1696178307000000	1790786307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	201
\\xd6c5cac05589362a4afb6155d37b4d5ba0a34ec99304d1d8148cc5659fe3dbc70d96ff4ae1db94e5f6514be224b6678953e1baffa360853e6a161aabde93ebb7	\\x00800003d73b6171fa1ccf97c347e22f0a1b50ea0e88c52254848f9d8bb25f8c102835ac118094ba9a10c28147dde3a23958401d3ae70e835a864af9e974ffd0df01be0356323366e171bbab3db687eb800da3260c5590bda5ddc4000285ae3e1798030c0054f9c21d77f82a1878f4da3ef6aa5b386693174a3c1090cc38edda421f44c9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0f593b9d222666dd6459b91a22244b366fea27da3019e85029278229de376ef5650afb0b8612a69cfef14b97d403f7003a253253c097b58c13ce1ba2771b9200	1622829507000000	1623434307000000	1686506307000000	1781114307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	202
\\xdb65d3dcaa3493d1287ac4da2d5dd8b84e40b5cb5ecd50ce1d2feac73b206d95bce49b170782e34c82e00643bf0fd97608a7a90f194db6ff709927b5f671a2cf	\\x00800003d678c7f38aeaed7def7529292a32b7b6fb97aaa2ca86c5f97fab41912479e3816ca5f22a1cb1789d089012eec237aabb15c62ed92f4e3b18b9b90b0d1ab4f25f4ac4137e6aad88b335b4a23fda15fd9a4f06570762eb7e3a6eb6dae4550d78021370ce99448f03daaafe0a264322a262e82d7c004972bb01a68303d9a44e5d75010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfafb97f4d4283e8e1258133fb449b118ebf904ecd91bfbd6d5b8dbd9d3376286ec117c4108e87b0a3fa6cc392c1c61828e9653824adf9f84c47dddb43aad7202	1617389007000000	1617993807000000	1681065807000000	1775673807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	203
\\xde8d50b0987fbf52a1555de2a4c5c44ca96f95a6b695ad21e9530a122a346f43955770d26d1ce178f546d37bc2e0e460b9328d71882fba1de8e17f933d93a088	\\x00800003bc9a809fb2a8317fdcce8eccfe0896e36d28bcb8be71c5b1d937cecc14acb8f8539eebf9d399fffbdd07c99ac2c031b4052fb4c608093155ffc9c092185ed6f86a8f050f3978257b2a6db6ee5dd878bbd560c0210c4eb34ff590b11ad7d6b0b6a13304778a4d2f82a817a4881ea4e832aa453f07d6754218f72be0369a2c7349010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x046a40684cec114a22b2e17330bc6c790abeedde2185716074b8afbde7d8c12f23ca44201f7a608c8b0603b1f9eb802f0d4efa73dcc2b7b87537effaf2d49c0a	1628270007000000	1628874807000000	1691946807000000	1786554807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	204
\\xe1e9ed4522189b2c132a603057b451367301bba73ebaba0fa198a2a10c7a15aa057aa86dad0b30cb162512ee2a358d5b7a1cd9e4defda3366f89f71667089959	\\x008000039ebe489cb8278892db50946448d55d97bd5cf14d3d797f6835d8ee756f4809b2e4777da71a1c80fb253e6d570845910b3c29571416fc60807c3d6152c6840fc69ca9d96e27c6819b6b690cce7fc47a7ef65c55d5049b0f2684203a687ea5489c80af5589d063716228bb451a4aa0d6859a8cf9ff0a30c6e067a09d49873dbfd1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x498e599cce3bf91de9b727ce7cd82b4d1a610a4fb19896c8bbe19b7e20a358d57dd3de5472bb125ba73a0ac7fb2078cfa59c74730281d7c622e758c69cc78f09	1634919507000000	1635524307000000	1698596307000000	1793204307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	205
\\xe66587f8aea51a41d9a08b1a242f216cfa1b24dcb1dc0d8cc9511e2698b41c1046d330debfc2cbb78c826444df19478389032b5965e5d671a6d79634668a5d23	\\x00800003dc0274a0846194a20f379c0197bcef60393c987b22c8cf14f6b738e480a31ec6d53d8f439a640b9ff580ad715d4dc503e8c3b219baf0e84b440c349836694d21ebbdd0b3986dcf938ac6f073fd2b3641c08788fb144ef52ff54aea241fc3cb34163d0bf12c05982014b83bb9a411bde9957bd5b423b483361cb923d0aa9c129d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfc63802456f97ba851a463bccedf55dc7e0963599cdead41460c0b049b0f21d6a38e7b587d208c81c7bf7d136cb39c964e0d1d0cfeb0125b9ee9754fe2093300	1619202507000000	1619807307000000	1682879307000000	1777487307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	206
\\xeaa19639ec13fef2b86065f5900ac7f431aad958da88fc9a4bb388e04d2d45df2ab7296fd9e21e32b7ec4c6459beddd3677ad4de4cf439fc45fa62a9b95eb238	\\x00800003e28555187ad71b1dfa3cb50ed22570bac56b01bb8101a41fbc4c5d7a8df63f91f6108a7b549dadaa3d2a6aed9ebb97ff1e4700fedbb72618ee8ce7ab4a67697ab7fab4b7e92e5138bbb6bb94c5fd96052a9f1712620b903215539870a141025df28ca429f4c411a1f09eeb1c9312c188aed8695a7d0bfe956cd59a55b28c7c67010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3b6487d9e16775db689ad5e556e67d2a9adeea703acb25574b821a7c7cae79d2f0e907a65ae948c38abe582caa136bbeef4ea35b523d66f79e4062d35ec28a04	1641569007000000	1642173807000000	1705245807000000	1799853807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	207
\\xea656585c8c0fbf56de8acd5445b74fc76cd8cde408ce38e3b4b48136440b2c8f2b0f28e2415d66ff77eb481a6e210bbfeddfa878065ffe5b082d9c3c1d0e22b	\\x00800003b61cc64f065fdd118aed54fc46d3bcebd997433e031715cec3dc39a4984c48cb47783ec6ec388b9b6d60c9cdcf7e8d0c37acfe3d6b60b90bbe538a9bca72f9e64ba99c2bd4866f093f26aa203c5a6f108f3cdee04a932771c86a9ee4c997d0b70712b6096bc8c02e100c572350ab8a9c982ee514b1c0203dc3fbf451bc316047010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x56728611cc5932191972b6f07bed2e11706ebcf9d14e4d818c08e493e6c12829d71be40ef24b120abdd332fe2529cf11f9773b5071f6026efcf9e0201941ae05	1613157507000000	1613762307000000	1676834307000000	1771442307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	208
\\xeb8189b39352ee4167bf8bd58a17abaf7f56c82771816b73e6e70763d9d92bd7d4021f53084e3f62bc85701894d67279bb0375ba2835e32b3e4fb4f567776d57	\\x00800003d2e2f9b9a17c6f1f9091f6c2eb9b56c346e24120cc3698cd05a64f9e00ebf5a0a1383031210eabaec4596901942e27817566072c8ad3ead07fd689957419a6d7892c7311a64ef19dcdca4a9ede3714c64e064f930841b55bfc117d817c785a772942e4de35953cc32d41dd8338d97c1e01e706c0c03f9a038529529db69c19c1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0d89274a4e47a88d21cb8409316e7cfdb2aee34524c0d818b65cdab884614bac5242235697b98bfb1de4b4ba802153d510e725e8ce0742e8618fc65f65749200	1613762007000000	1614366807000000	1677438807000000	1772046807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	209
\\xedf5e849dc34772a9e16a5a187f80e2437d89ccde9d3e38023e2a028b57c0c767afa3f04cecd091111a685e73671f1a4826610b0566b8c0f6f648d322c953d27	\\x00800003b9821658e704a0da373b71c8deb7e07c6d9cd502e6408c09a3ad779d3d6ca7114701aaca089d075db6bfac868588af3374fd9c773d1d0cebb3dc04747425e06cbcbcf748f74f783379b7b9466996176d3157dc60b8ecfd68c5c7cec90fc2800af4c0cb789ad411428b4d55152f1ff73174f8fe105513bc32df6e6313427c8b69010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd2c718fc730670fe78bd449115d05b096c5ad27f0396ea2868684a51c16bdeca8efb0fd40f92f2f12eef50cab89cada6e0c13fd995e216b1ba8b2c350107eb08	1635524007000000	1636128807000000	1699200807000000	1793808807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	210
\\xef8152a88e6617b3d99a76bd913e60b6228d474e5f9b2c804493e9cdbb92386fed371f5ec80dcbb26c503aa8b04e433ab1f8bf38fe96642bfa974635d74f2ad8	\\x00800003a1238c2a50f14a7e789c92a6243a87af0ff5673a8e1378d337522d6ce8729fd086141d689102134a566923dd08acfc7ae3a28f05cd4ed8a8a4840be17ff57c43f5f7db4eac6da66ae124a196c46f741031699974131eb18128b0fb281fdc8505e2dece29e12ce3c37de46527f8bb56656d2e400116c4037fe68da0eb8d0ac3b9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x168ffb27521ac3cc2558285b9777bb41565af522d7913ad757b854a6e217d5a1def93d136627b2aa66be764ea2fa5856cac57e08d064d68146b2c0d379687c02	1612553007000000	1613157807000000	1676229807000000	1770837807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	211
\\xf381c5e9df0a82217fb71187c56022d45c41a7080da91aefba81c2b9c3e4491e058f40f6a3df7104167ceebbaa0d18a1fbcdacc6b8b02165ee9fe0a55ab2332f	\\x00800003aab91a026e4c4a36552633a06fb232ee7cc044b4286050d209335f1ba848cb6629627d6f5076937f98164fb756492bf3d4c382bd411970522489107305bcfc7f1f5cfba50350d699c32d12fc50120a01d20cd5ba59003b25701aa7675474e3217cc643c12de4f127adbeba46f7593e31d546dcacbb0a8816c10c91735952b347010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb24c4c5ca15dd33fceaeebcd738361010d914848a5e5a8e83d42f42c19da3c09009f785aa5f72f38fb3e3c49d70d4039d34340708c4ff2e44422b25c2bb27d04	1615575507000000	1616180307000000	1679252307000000	1773860307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	212
\\xf339614e20f526c9bb571ae1c60ea1d25c8b5e4bbea7ef6fa8374d3051e7a415aa44760d86b3eab3be824f0a3a3d6af5bbb93d6bbaf394a85feb034794c04614	\\x00800003df8394c6185f0cb720ef4242639ae075b64b0a588fe7c71803d09d05929f2e549b8c8f9592aff719e23def894d8989e73594f33ba6b4c107bd898caf2dee4762ef5ed23bb79dd069870b538e6c12ec93541844301dd536145c4fb2649295744577b983bda7fa8c5af08c4393ad1eea0e90ae67929909db85f000391851b33305010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x51ccaeb5966f3779fd685300e76e9c01226aca0fc8e86074418244363cac097799e2ddd502a756141eb7bccba45fa617efd5b3fdc6ebcbb767f21fd89d884100	1638546507000000	1639151307000000	1702223307000000	1796831307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	213
\\xf52939af15c091e68ed46155691e9dc256f1feaa2fd6689c5de9cc2b3c9a43fe2a8078837cc2ccf7acb254e8d3f6af0258558403cb33e56636caf7e26eb9ce49	\\x00800003dd0a4d6d9f607fc5123414571b2b996a04d2759c21af8a3e57c30d7ac996e203d621039054e3508936772858f0c6542eab9bba1e6e8e3d728aafe17dfb9e9372a5d2a96cf4bb8ca170de48682739f6bea6340b6ffc77525693b46bd1fdae381cdb79bd91f6b78463eca6c89e05acc1d6597bc9431cf97319a869de366a19922f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x13fa75954efae936ecf97f122e46229267ceff201f7cfbbfac76a409e816a1a93374eaaf13132b9de6132ed9edb1fd06db901620e7e83c5b566909848d059a0c	1616784507000000	1617389307000000	1680461307000000	1775069307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	214
\\xfd019d82ccf5cf48b6cbd5042f81421528fc119dc4d8dcd1a265fa52d27ecb12bece0a62ba6e54b82718878f5033e19eef5e4193b7fcbb6cf595ce29c03c66e6	\\x00800003d0a049759a715353ce3f071350333b6ead031854372f1f8584719a12db2d36f410760a849d26865ef727e761c8839d22498c7dae8f4dab7ac1d04f57e524831034c689fb98662fd6391c9311b5798d4479fe4c8bad26169165f404f56b51b94583a36520c23ce23e65985cf5c10689cf6cc9b6ed5aafa97f9a4860355cde24bd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x619f4b6d67426f49b7cee1723d5ebb84e485dc0be9263983e15959d1de96b5dc34ade44f4e620761e34e2d71f8bd4515175ef4a437653971c11f0af5d875c601	1631292507000000	1631897307000000	1694969307000000	1789577307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	215
\\xffc5fecb710daa2b6225152d3ec811d21214fa250a538058b96d8d2b5db2248153b3b295b425ebaffb0f737a985c5f24d8f87312d8d5a3e00fee736cb30e6d58	\\x00800003c224d3b788fca6fbce8e887e17efada887a5740fcef0932a9484007972effd30dfcd7fe04d58ca0fcf7296428ab28d9c499c62f8b254833c52b675bf9be8a609336621e3c5bf12c72e08dbd3750a165d5472519d43463d6aec3a5fce8e77eb67061a0ab68920a389fc6dcfed6ff3d2beb1288ce3f8fe90424b7d9e9cc83a455f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x106ae442315664e4f942fecfc1f3ef0563f2204740c6c53fbadd3774a25977c392d30fe3a98f9325910bbab8636b41665f48d494f7303999828e125bf1e6310f	1620411507000000	1621016307000000	1684088307000000	1778696307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	216
\\x00e2c1730629556e0296e19882a85bad4c177b9b5844d68fccc2b72cf9f5e3bf223d64895698b499fc36fcdbf65e74f8a9ba6abdf6e128bec0c8eac6e6046729	\\x00800003a95a93649eab1acb809137f770e9d2f454088e1b9f97feb45ea9f8593f75d650964e4d2a28de45e1e1e4beca59cb76f965d40b9a9fe0f8901c0e4db2c05638cb110494479dcc6af63be418eccb34925dd5e11f4d7f23363217effdc869df0970d83a4af116780be952487d19d6866e217d2a3b5c2b3b898d74918c9a9e572ea7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x000f9ff51763e59548432469c373cc482c68180f2c1a9fb1d9b9af2e6b46d3d6b23614cba33845c5f7da9217336424a15860e108909ec4102f37ce2bc8f7fc05	1625852007000000	1626456807000000	1689528807000000	1784136807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	217
\\x01963e53f463c8d42919d80b952d6a5361f5bebb8b134d971bb0a24b3ff90bcbdfb0f65aea04c3f0ef2005faf00608cac529cac8b8ffd8d468d763c77b583ea7	\\x00800003e78a3d6ba726f73b675757014094fb08c69defeae365539707c51f52630a21723c7af9ed4895659d77ea24efebd8f2e3d1ccac4ba110f7154b3d956ef3368138eb1827f606b02f733a0b2d1e80d283427ad10cb4d701e1756e892b958231583769e1642b3ece37b4a0df97339dbb740e300fc605510ca3dbd38d9fd237341bb9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6af9efc154aa47c734edfff386092c89df19748241b16942db7710a6fd2e59d8cc549dfe77a256f1f7d66c404b87b8e0ef508d554b17791a02274a8483f44405	1625852007000000	1626456807000000	1689528807000000	1784136807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	218
\\x051a2772f2b375ef37b5a67b32c0effdd884ca30ac6c0db9de9522ba11754bb847476f239fe69668d189d0743373f8f6f4c8959a606afc987ed3b7252cb89523	\\x00800003c039f66db21fa03dcd7be9dd40b152a572e0bbe2620e6afdf47a1fad66993989af35a2b83e2a34cbd3a1490c0a7692cf3d58c158a32f8be90a1337cce69a074cebcf52ac74386193f0ae3afda2aec51b1a641e64f31e93686866198bc1e629ae0e508c98880d4628cd73da37fa82871605892a93464e52bf579de31a96dabcef010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb39dbb9e8f2ee9c3fe1d935e62bcf262e167529b5da5608d72e390aaeb4790fb13da4b539cadc7e2de468aa504f88c657d6a51a2a675aa2847bf0d003066f203	1617389007000000	1617993807000000	1681065807000000	1775673807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	219
\\x06aa334b288d2487e98e460bc639ca6ee787e51d3d26fbe12782b78112242b1cd2464f1d61c95c2b6e06c03d7fffc69b5183a7c02011deaa498a0e35d4b97972	\\x00800003c1fffa1b7aaea14be8dff3d5334ac556c3a6d502b87cfc2adbdd16126ee01de524b49ff50e5e2ceeff964ae4e1f7757f6d1b6a6fd7dce1f60faa1224aff8cab8e0781efcf3c64ab9d2525f721ba5566c93a6a5b640423f5d851154a15e6dec958464de609dcc8468ecdbc4ce01acd8f57db6f3d257c187f351949b355da3b661010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x47ef3b23f735c9ba07f078bc4cc0d97e43ee112a244cde2fff97115ed209f9820ba3cda0e5041d19daa948ab06d3d08d43193f43cf68d5a56002689751850d0f	1610135007000000	1610739807000000	1673811807000000	1768419807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	220
\\x0b7617d6ee4cf7dba0c0c91a4fdefbefd0b81122b9cbb56c5233e7645aa980ce10fc535e7bf8a8d5c406db687ac12200bfe827461a789a1aea6ab3c4055f449e	\\x00800003c2c4024d3f664a922b3674a5266ff7bb89e244152c12e3183f461871a75bbba9ceb4499b7b7496da48884e0aaa97bdc659468d4b093c7fa6fce265bfb08f57b10ce2aba31f04768b8d17d886e6b6963bf232de1368e4741c78525597767f64321fd9142ce79c4227dae82ede44432c2287f1532f55fcc7fe251db0587a955d1f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x808313a421546aa3e6bb4566c9cc24ff5dd06568a81ffc6753ef06cc6b3970b1e57270571376b903575113539ea29a7147c3dfcc811ade4401f2db512e6b7d06	1622225007000000	1622829807000000	1685901807000000	1780509807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	221
\\x11ce82d845dd5fd15770f741e6865cc146a924ab4ba73f91a842a87b3171a8ca4c5e2abe83a94549aa29399de42a3a172b950bf5fd8271d5720bb92c5620a7ff	\\x00800003c1ef46ff63ac395d7c5e30d5af734de1c67decca613d62b3a7a6576a1a93bde6ab7e29641c8a0e2379cdfb48aea5b103479f4546eed2fc77c2efb9c74e6eedd7a0f3b9b34be73ee520990385aca221fdabe6e847577fff45d38af07d99d758b800469bca79d99a57d33969fc265963f317df4e03632745fdaba4e9530388e7ad010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbdf17d914bdba4ae9a5cc3c2e6b15c26087ec330cfbbb6dba20b5f3181c2c92c308eb3e92794521446a6336b4f93815a8b7672a07f3573392c3958ebd7a78a01	1622829507000000	1623434307000000	1686506307000000	1781114307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	222
\\x17aa3f8ff752678956b85c9b334123ed225b03bbeba2ffedeb1446977ed71660af4bfc5a64fe533ce6cc348413239087182e7d2ea94259a7e585c324db371284	\\x008000039d26159e7e1d9bdb6ec8aad73d1de326d265cd55f62ed80556c1a8e74122834bae8315463ec56d94cb23cd0dcc2262a28420d9dc352c66cac09d2facaf5f5a9fdf849b0fda70c3a332a9b09839a0e0128b2bfb27bbb19edf65f05623135b9cfc5203f7c53bf0fa86de28a697aa43a42786ad2c8489c63d183b386a6caeae73e3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa537e4ccf5e068584ae24ad8ee67ebf0929f473c5d605254976ca5da2a3595e2f7e50da21b0b65ea68acd1643ad49d597e4c16d00d2ac5e6ee29b9db5a617902	1616180007000000	1616784807000000	1679856807000000	1774464807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	223
\\x18bee5f63bfb4e6cc0be83299e142350593808a4fa9096139e293c6149eb49b9800b675eab4d7ca24a3e0d6316c0713fec3cb570cf860524ccddc7b3bff089ca	\\x00800003d03dc2dc28a17abeac92604219b46af41c17539c42848fd3c3d1101383e57eed0899dad4c91590d9f6f4f70781919622f713ca565af398312c3cd36c7a21e933cafc084db09a75c3cd939ccd385220b6a70677a60a9621fa5006ea45b36e664c2ec06e1bb88daf3da550f82d39162ff14a1caa35e716db878cf49c3d4586e8ef010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xad88da502c9670b8fc7f0d04e22f2d9d3cac2e7fad9705d62d2395a45dca9156287f9e00b052e046927747821c44c23efcffedd3e3cc1c564ed010bafcfa3b06	1619807007000000	1620411807000000	1683483807000000	1778091807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	224
\\x1dfe8449bf72d39935cfdc8ca3deb3a86c16083cdbe97874e1916494f63fe2b5bc57e4c4aefd8336ec5a54f4efdab32727f6ff930eaa1ff43a29b4d6133ef6b4	\\x00800003af6d9f07249b1e3199c69c3ca291c8d729a9bcec8eda6df206237067288cb42313f465520db96e4da83f70175ca0f03be3c00e392206e2552769ce630e8734049d6bb39ecfcf0826c9f3ecb0e8195ee0be2b461dfc012cae416ffd990833ff7a6f072e28878b48dc2978bf21a7a6939d8a9281bd59ec212609e6b96157ccae37010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc9860b9b62efe872e8fff8b3cbc21923b2d33dfc688b7c2eff9da2f1a309bd06ab2ae7e6407ca04beb41e6680ed1aaefc28dc64888926f4c60005599d6f4fc00	1624643007000000	1625247807000000	1688319807000000	1782927807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	225
\\x1faa05bd618f5d0061e8d047c08688456698daf5922dfdd0e69df316182c17ea41567f348e8e4dea5a51ce9365184b62cf3946d92e3e576031f83a00380e9da9	\\x00800003a8087d0666ffe5f431f30a97797c5b325467985b70ced5f21b17779da2de4972aa1513818e25bcf0660933da1be412dd43e31404cede763ca69966052a2d378bc44a1c775c67f8499533acc6b870471ef74c22294e0a723f4248967ca88b876bfc0edcd2f8938b7cc1376ec0e45c86f0b1d506df7e93950a49b174d5fb94ecc5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x59370cd56be31c4af5a22e814c2c6b8997b5ba8126fc435fba8d127f528e64b7b196ea2335e20f16c891a86f95401fd943ef26ca4eea6665c4d4f16082811d09	1613157507000000	1613762307000000	1676834307000000	1771442307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	226
\\x2072143010a17906dc336c1d4c1776eca4e60963b174de11e002da1efe5250431b36ab2e8f7eb6a12a76b38afc0ba56ba1909cc5d92f83b299525939bcc8388e	\\x00800003d90ee3be80bb60bfe89e0fa5aea8846a363d7436af0df74dbe3f265dbf2e34f5ecf447108bf569c2abfc076957e79d083ddee337412028c50fd6a96f2ae2f8cbedefe8f0691121e8ed96b692d82a999dbcba38852948c092b4a07fa78ae275e7d2096a81b05d6e213a2d0a5bcce8140a530a6e0454ef178272517d7f4c725dbf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xdc5b6b344d0e72c9b76f95f293398f0349bb2f90491d78c72add8f39c4b33354beee8afeae7376383c7ede4f3ba01a71b5203788991a48dd4071571544c7bf08	1633106007000000	1633710807000000	1696782807000000	1791390807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	227
\\x273229210cb2369ca9923d4b7360f4713fdca7d3c02b004c53b143d631e9bb92cd8baeba4e4baaa8e062ec8c11e705285e491da5407fbf94619336f55904a1e3	\\x00800003bcc2e5203d8880f6a193790b7a266524c1e4bedf02bacea83075fd4a2aa420bc5b8624e9dc821bd0c61f35daa7b56ca83f6b21f2f70a514e2eb9d9e44b93fb15d79eb6652e30f88e51abe5a7c380a1f5278cc2ecf8833484cb87c9ad98c1e8456382fa614e638300dac4e1308c388e44b280cf629193eaf991fabbc455b0895b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x02a75543fea755e84bdbf7ebfe0081424a8ee724dcdd228f6230cf94dd2b62c67804ee0801f291af3fecbc3e25c09cbf5f729446b511c284219d6d62bad6f60a	1616784507000000	1617389307000000	1680461307000000	1775069307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	228
\\x32dea6f75baffbb5fe922f8c5bfe02e78d1d525d25f49609e77f3200148d661859ec6311c2e07e33a09d128340caa660d268e0876e17675e280bd537ab4ac3a8	\\x00800003c447726850d1ba928257726e5e01c8062e66e024a759eff67d4644ee514d8bf797a23a45f52ee14969b27c8e1519a094a7c8c5d39c5a920aa4b730e340069e7c149c406e82d381795d8fdaf1eede8a92726b355b33b3c33a82465ecc9737e004c8514c805690a67c25d1532ae925bc96cd61ba58f041efe3aa8d2f926d667535010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7162a2c52de011b49d1a97853c92a3c3d0fea994123adc1ab504be54d39d9eb507830b167263a98f4c52f75bb180133e374214e00e98339ca8b8c99d45bfcf01	1633710507000000	1634315307000000	1697387307000000	1791995307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	229
\\x3742f4aaf02f70d08742314d292f4f1224b4b94f8487ad5f76c9ff1111b5ae6e78ebd6cc297859d9a490983abda1b85b5b9e5fed13c1988d8d6e19733a0c5bc7	\\x00800003ad00b453c33c9b72b97869f134c555c5b4b15041fe852e28e33007a4dfdc3551f098d2a95f56f77fa58adeec109710431683ce89c234d239c3e5cd16f30796d31da75b9bbcd76f2cf74af58a758f8500d494b4df9121cf8dc1b6fa711e4bec837046a923f50a9921d146b9a95c2c27cc8344629f530fcdbee8369dd455372b11010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe3769257a4ea0245d972ef6b9f8ff9fd7be1af78e5739ce2ae029ac50fa9120bd2e598971e16a0f422a10cbdf22d19a83d7a3327623ff88e73f315e223d24d01	1631897007000000	1632501807000000	1695573807000000	1790181807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	230
\\x3adae1a60a7bd39c8cc451ab37fa78e57cbdd51099876fe2a5f9a42c41782cb57e6fa8b279a2786caec55fb855a330c1f290f01cb685b1fedc4121495b74411f	\\x00800003a28a7ca976c3d4b7bf222d2aab1ba97122033cd7e02bd5247b6fbf0ba448ffeabb9667c6c3d80543754f21dbe04e23e0b2ec6924016c6c99a66e9c86f25dba80401fc53fbaee4a405638bb8b5d7be36539b82c36ee80a9848a01046d6a13dd30c1eff1318681fd637c353f0b32f922f0a8feabff310f9191f411851648afe393010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x31e52db9904396ec09f891587b746035bcb95d62229a069103ce0ddbe3d1f782fc88a7ad86163532ac490f3633167a6d0b4eb97e1b2e4d0958b9ba19f77f5909	1639151007000000	1639755807000000	1702827807000000	1797435807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	231
\\x3cf23bd171a7c19dee629c26d42b6a7ad1fa6c1359e19877bc611d4ed4050f9af15d869a007aa6e87839adf6cb9e8e4502bbb5eb31f59d7d82260e1d6b902ff1	\\x00800003bd7f2f306261375cb351265bd1476f63b710c3722ea7d1a782f5c68e2eae2821621ac6a78f6b0b35067eb2fd418949605145bcdbf409ef7ff74b4dd51b14d68606533e72ce4f99094a5190526a5d136dbd08323cdec1767f76281e0669d6cea06cf3e2d286cc60ff18e90097068a93ad7603873fccb2e71458c64c53922c0483010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9fafae19e8f2de44f08a6eea92bd18ab3b539ba9a592c9027a7be7416dab41bd8d84e867257a28adedf446613e681864299cb40df9b7a06fe450d07945ff940f	1621016007000000	1621620807000000	1684692807000000	1779300807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	232
\\x3d561cc345c58a0d064d474e1f50c8dcdd04797bffd9c9eeab73d34092a26bc9b6e9320fff86bb709e872b910677206f69117008e77d4b979a9d1e68c024f291	\\x00800003c8e4ba22f418fb6b0a4fb6fc336906cd4db3f2efa2653351cdd7389d539ce032ecba7e24f8ab2be751dca01fc2f046b5fe626294b5d3806a3471586d20613797a8c6d4e10ebf9590c6e30bed16ad7f9e28415129b703dcf6eaa4ef08e512df88d2df5891c0cb9efebf46934bc2af101d48e1d7570fc91f24a3bbcf0a87b22bb7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbf8a51434a7e77ee46eb9c57c4bb8f81d27c7b579eb89b2d44e53da00a2cd016359158b954ed62d8ff2ea1201e38dfcbafadfc95a336577d0ec63a4d43673404	1625852007000000	1626456807000000	1689528807000000	1784136807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	233
\\x3fcac2bf0aaf97ab8ed179d07ed70b6dff90dec9bbdbca80ebbdafc6b744646e605825ea03e5fffaaca27866fa54beea8d05de76aba1514a9003d717ca301cff	\\x00800003d373ba431f5080eadc7dcad3ae53ef47d36e5635363a1714906a7c5c29d55776145f40dffce557ea1200247d427f096bef799f91be180cdd2a4438466b7173f1d487994910fb6be6caef1a280615f67c32fba3588203299fac17e0e08422535dce0fa1f94b0b306fd855eebb851acd9a52e4856298b368f1edce226c515e21e1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3d1178a34d6ab384e2ef69fb5f74720def2502c9655aa36a7d9b2bb7b711b31d9d8ae97c306c796d2d791f2932816a436d167a15bd62ccbba53d2c2c371c380f	1622225007000000	1622829807000000	1685901807000000	1780509807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	234
\\x3fe611913ad0c58f9d9890b7d7bbb82dfd9a28b6ede7aaa42334d90f44e0deec20914eb04181d37945fd57b58e067214310bbc760cd71c20ae9627a6e70236e8	\\x00800003a8d6d9bf8a13fb36578be668533799ae0a1642c4b78c85e8f5e3dec5a170eaf39c8582499f498f8585e70d33bc29c017c7ba777a33aed41b13b34c369bdfa981350c0c33cd57abe81e72b6da92c1d8dfc0f1af94182031c0a1f1df568bd484e947f0d1f11e533c723c8717a3276cdad0511e1e0ab8aea0e2dd1126b807b4625f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb51ff318782461db17e3e1a24a51d5f6a624dcaab479d53b98f640bd80dc5679ce9c92bafbfc11f417dc3041aaac93700ab04088a04f7353333817461000060c	1610135007000000	1610739807000000	1673811807000000	1768419807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	235
\\x4246defcfd99b8f48c3a73e2b28e9c0937ab38a626d5b7d8611ac5285a60ffbd1fd90ead4d9a8e05f8e8798c7cffc11ecd2fd2bb00ff0a09a0ec89a8f8681986	\\x00800003d7532d328125195022a342a886c2e5942927d6bd5bc81c6ef151b6f8feaca54704ca7aee968c09c2c326b308c06a2b6022fed2454ad3645d4bcefd29c34812ed37b9a1cfd26becfce6f29ef6f12bca526af7200fb9f4054797484314114080ab18ac006ee0c4a081e3ffb839b77b096c2bd037de13f2d8145c74974c0ac66b6d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd2d24b584006c01f5b0a9398b8475b9bc0a1cd582ac51846a0b17f70c4e8090547bbd4705db50c4dd51c5401d38d89e175572ca0c9f644b1c3d63f87dc060e0d	1613157507000000	1613762307000000	1676834307000000	1771442307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	236
\\x43862eb1f8375d1ad0709926969c2584aa1d38eac285a80e8228dced528a21994eeb0302e75af24256f05d12433c3ff60956d61c44c1f364033cbb849e42035e	\\x00800003ad1ffb8d33781e3d7609310d45634e5a5eb7f4927e2fd1235ba9333b1dca7cff5866e7aa9b502ab214af604c693b7b03ae5a87bfd1488f6ade90363599abbd4c81aa2eede535f4410dba6b1bde851cc30aff640c8a29fc6ba8447e47981b6d4de7d671d6addac565789555cdf4ca979938f932589935960bc34eb9772434a44f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x88ea924f2ce662f52f2f5268bd1729ac399cee936d7c68297fe5f14bb0db120c2c340412cdc5c6efed4fb4fbb3bdd5269b3eeb2ef3330425e30acfe93f208b06	1622829507000000	1623434307000000	1686506307000000	1781114307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	237
\\x446a1af10545de9c7a6d51716700164eeda8194ef3d93bbb3eb1cbb7db9242532f72a63235f86ff3d0c5586990d0cf4b479e99690ef4c72bdc37b8b7b4ecca56	\\x00800003b7d3f6d6118c90d526c8bab706c79c15efb7334d0dd0b809b5ac5a1b2ac72ae1ff93bdac17f78cfaf2221749fd2d650ed3e8c92fb932be2caa87d71c93c40abd1a972d702687bfb4cc5f4a58974fe609c91f1ba87438dbe59d32ba6c8708fe01195199bf33f6046465616876d6918aefd8a6ccff65e16c13ab242bf7b4a501fb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd186faeb01277390712fcfc6ba62fa9c9fdc84d01b38308db3940a361fdb099412e5d878219a76e9426424fd498c44812b4769020991dca8e886a54d0791fe08	1618598007000000	1619202807000000	1682274807000000	1776882807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	238
\\x45f29d9057ca6ca21c8bf2cfd427ad6adbd5d5f0f9f64e3f12e6808551c7d967a23f4a595531071af7a2287d8e56852ca742b75315f23f36e169463ed561b791	\\x00800003955763b325f814a3f5d2c9b944b01728a2b403cc9a2a82ccd46c8676bdab9d93740c76cbf436f660111167a1d136bb86caa6ca25ccf86a4d22114df0f2cc029a1b6117919f3da1d9cd2ebce30e0c73d0704bf4c6e5006a2f287e0cb01db2a9d02dff46e5ecacbce9f8b3280022939182a9f6bbbd98e3be2e8cf3811ac51f8743010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x49a49d5ac58af3c198f21da95814663065662e72c2807e5cc7b538165e332ce98f181a85ad3e35db501ba8dfdc6d673c2d2d1899d94ae828dc1e759a8bba740e	1627061007000000	1627665807000000	1690737807000000	1785345807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	239
\\x487e8194ee28218d1ff78f4a139e9536abafdf3f90c1d6202c5c9f51b1de4ac0af7f92960c97b0b4b376318f0f6f7d8466b55897b78600461616cfbc437fb0b1	\\x00800003a6b9232ee54ceccd25013df24f45e6c1555184ef26f24f4cf291e3bee3843a5151ff8b12877b1874e151118499f5b422bcb52c0742038884c9aa8140022d6c610cce78aae6e21c18004b3a22f126b2566606d94836bcc352681028377508fbb02b3668c91a46a2bbc167d118d05fb4b79051cc5a7894f3e8dbb1c256b0f455a7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x769acb41f758f627d98cc7a6996fcfd9f4bcd2ff368f051550ecd25407598789494b4dd3c13df14c090efc599714a78aface2ae22216e02fdc5e303d402a5f0b	1637337507000000	1637942307000000	1701014307000000	1795622307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	240
\\x4a3242ee9c922390b1bdecc094bd29997364cf502ee2426231c96addc52ebb9efc52ce2dc83fcbec47534a1a4143dc00961bcde237df12aae80f5be3b320c839	\\x00800003d76c4d3e2012689dc7d76ef5f70543971f22ee82852937623803fd393228eb822421618dfda6ee21c35df8672a91db26d2a882014e7dee4c6f9461c2e3bd104902d127e07701f4a9f39d2ac81c6d7af6b0fc03077d6547c3e547cfccb344981d072113363cd7a921250d9f254178a823567688554504f2d127d98feae252b18d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8660375aa10e380f9e1b1c19a80c92d0bcf29574e42e2d5464f625542036f0d5a90b84f9dde6c320213e3ad5ca952d99968c94249f1a2d50b285b8ac9e242f0d	1621620507000000	1622225307000000	1685297307000000	1779905307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	241
\\x511a366029f072a02544e4604f7db5855f484e5e5d1791a9a7eefaef5487ccc1e6e9a5bb10ae50de7ee467cb15648672e2873942aa3bf057fc24ef5d09436f6a	\\x00800003d58d8ebb1d2b7eda83edfcf9fd34c032045937231eeacd05f15b8c173bc7ed11279e00b178d1eb111d2903e49bc9f1918b52d016f9313b9f6c3377042087a7078d858f65f3ce1f9598fb675087448f723bc5fb9e096cced05e913fe0ddb1ecfb4b90e82165e848ebabaef02961cf74545e7db4cf187b55e52a8ed2e578725be9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3442318465aea64857141916594c18c039c78dd9a40ef6aff5746020a3fe96561c024e1a6d5cb096565a0461098958d81889cae2a2bfb2aabd20de22a038170c	1633710507000000	1634315307000000	1697387307000000	1791995307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	242
\\x53869051e5c0a04e9d8d058020c18698cb220b432c8598c4d7dcf7891555bab4bcf884636855ff72e686072695a17f63653e7edf10ecd9e340d04f36cfa880f7	\\x00800003e91af04d97d410c7e10a3d91145787f3c9da79ab4409bc2ae16aa11d6e745c09fded4404e9b455e4d84ffe8597b328c2119dfb3b2fefd5d407c269a6ee35de01c29c64b017ea91b9916a9a1a38bebca5d4d9bef6258861a6abe2d466f0a674f5c9d1076a5bc4befe40135f046f724f5168505e011347cdcd5c0d3fe260de4e49010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x317e3f9965167d447bf998f24d7daed7babb787cb2f2e32c26d7f908a228438508ddb3005822944bb7c21e474a1ff0071e6fed83f1445d81f5d5d275b349c10f	1621016007000000	1621620807000000	1684692807000000	1779300807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	243
\\x5352894f5afbc325b8d1d0a3a670f7ff4206b2008842715980aca7a14cacb22b39a0493ce2fec250fbc93215dfb01693c5c2c4b4bfbbbe97e1f3920c760c64d6	\\x00800003c36b30e4006ee13d2194208bd3f9b29f16901f2c65841c5b56ac5adb848e76fb41c37c2837864098bf2892f6f47c13c2533f41003418d88bd6a8ec4347d0d6739180488ced55f8c688977c241115bd4f0a9790e705ba09365241ef7b2a1e91617f5196e51251d5d8594f20b07b54d7bad9ebd60b7f6d5bcda61d237277850529010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xef305e0cfd716dc5e4703e7e7717c159649cacbf8a78ca01ed5966160aaefd156517dd04fd1e3c81430bb9d0204ff59abfcb45164c7f6d735141ac909606d509	1635524007000000	1636128807000000	1699200807000000	1793808807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	244
\\x549a8510fbfa5db6d1bb8c76800774886ed1f3977f47de4766cce240f3785317fe7e9e91532a5915287d474e0f77c2f852812bf370c76634bc71ba481654ed57	\\x00800003ee053ca76bca073cb599b213a13393c93e61eddc81f0110f15dae2c7971884d2dc73397994c2323dcb398be566df6de416ff66ec84a483933c9a74e4d9de615732ddf0014109a5aebbd02042ccb5e40e34dad207754c83d65b9667d65d456f8853f118aaec993a8b31251ceaf6aab2450d467cdb3e36b90f7e7c7ab9b975c34d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9174f8cad4ed49d32f279d21d6cdcd3a35fee827c343b6f51e2d20385de383f6b67dd9ee8172bac140ba7cbf1fba770751884df1d02d37bb84aa03ebfb936403	1625247507000000	1625852307000000	1688924307000000	1783532307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	245
\\x5542ceba417920a026935496a0aeb34b6aa7b2cae08f10e188ebd1cba29358938299ac008a3c682c15d1cb735f27d6abea502662bfb26aa9b74c3193ce94894b	\\x00800003987f87b33898d4a60ef469415b18fd26edc12f301621e9f94158088e081ba3eadc4a2baa1940bd93f0434a342636842d8ede3e4dabb5e99dad581be49a80bcc2e4c4d39092befa4cd0e433b8fe1010d679cf39143a4f1cdf81da2850a83edfcbb27304a5f96879dca6215351c74eeb0c92b73414fc9f07375d24f5d79d5367c9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2729adcca71a0d37e51c613559e89c5c95fd1a1b2c3c7cee01cffca2b6460fe6e98358bdd26207fe00433b098fda00d6b234828535068554d86689497e96170b	1628270007000000	1628874807000000	1691946807000000	1786554807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	246
\\x5a1622dee9e4515bfc87ed61bdcafef08396a34a184d69b8eab36f92ff5d06bda413c72e72b155c7e287915858aa896c0883ed8beb07dec6d95da94a0ae000a4	\\x00800003c4f0286e4a5d70a865be64a3eec9cb005740c73f82696a8a1fa6d3de1f472532dce97846a5ea25698038ccf62083c1f8b4c3141d0e9e370544285f4f369bff408b066aed6a982e9930b8891ab84d58c84556bb277b25732b7c7743cb29e4a3f50ee97dcc820319fe9335e4f14b0dc5cfb63e1ec5a7033ccc9cc0ececffd3a79b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8136db4cd425035f9df8725818faf94ca6c5339634d6a8131de81d493723c6e962d67fd8c1e924aaf3f474a8288ff9f428176e070fde999165351dc8ecef0d0f	1635524007000000	1636128807000000	1699200807000000	1793808807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	247
\\x5ab62ceea88dcca46873e72e78c693dc2471cba7eb10de57c5221cfbcabbe883c3b53dacc75c45818b4780a722bf7ad769191355fd80534b0351294fe908cef5	\\x00800003be03f2d9255e28c05a786b207304e690bee257a5525ae1f814bb870d5ca0268e6b1e129eb008d911f75968dae0a8612f6f124572642b7be4577c636d67131c2b5d403bb1dc311b5f5b9982e3ad483a46e10fdf04e8ff9425cea7875c0abc8ecd6d8f6acfcadc83c839cffe5919a35ea8289e8d139df57eee7ede71d5b1c86bad010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd544991ea762624e9b6a2f7abaf6d86d579db63743557964b6d8f0b9b1bf74ff2e17b64affc93e1fa9933ce00ef9b138c4c91c40b87c3075578303a2d8aecd03	1633106007000000	1633710807000000	1696782807000000	1791390807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	248
\\x5fe66a584524ae1516cbe2bb8d0886c0929652b3e0225557c266812495fc80c0a85f6d4dff6f0cc77ad20c542e3eb4d8a2d994eeff14dc43decc3cbb04b0ab4f	\\x00800003aa0c7b2b6681091f265f892e735be5d5a7a021aa0b77900029bd3c0f620852939b4e57c221801de304d3f427a5e2004c0f5af0945b6a87c1bfd27f58f8e232400b84db961d0e651bd9a08d6a98b06d122c11db849ad2374447e40ab4a4de756c21a5aeff7680a7b9fdb0023ef3ffda622e2957469b118faee6f5524040545815010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7871ca1df75ae751083bf899bdc2131d037e4c8c81d8c73b1d72d83cf249aabe92bc8ddc683d0bb1d23b6756ee765a0a3b990fb17d928d0b24f9bcf098f02208	1619807007000000	1620411807000000	1683483807000000	1778091807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	249
\\x60125b5df333bc4b4a9ccbfe6e306cc93c56f657af7e8cf3c87fae37c32ecf656b2d6cb62e6883053c5f3ab184403b83c63f2e3c659ada6fdb047c6a3810fef7	\\x00800003b7ea91a576d9adea6bd41e99faefcfcb6ac7103157b4383be5812cc79500ebf6bf2450d6d55b91db76a19397837af342e59620ec615c29c614674e5e0c37c6c1a8c53430d13de8017a586f0acc3959771ceab6aba389d3b428564590380c59caa757e220f031d89a4010989df6d17ff84bddf3161f13d07e347276644baac0c3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x51edf2caecb35e9bce70f8fe5929867000188ec1a928cd1b8371587363ccd1e51d95e2efe231d643aaecba74f94229264c2c8d87c2e4656b87b79ea8d04ca606	1624038507000000	1624643307000000	1687715307000000	1782323307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	250
\\x61aa9803a321f06bd7c12d65993ec43472306d8a01b1621463572ac1a3fc89b9c0a22777608d4c9a4704350447aa5ec84edc18ead04da8be6aab67de609fa9e4	\\x00800003ba2e0f1950846a06e68736f9cebd6e3064c488e436349d015e848fbc3220c36256daa19c228fce29a1859f73e9eda5e1685644f9d42d1ce8398fbdb5f1879490424b9d69b8c7ca04785da2b19c426b143578f35339263932f88dbc3e8aa18e5a1db66a36f5b11411d0ad1f2d3ae4420bd5ea9afddc3ebfe87238034d1946fa73010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1136c4979f4f950ac39fa5f4556163a888b8cb593b52e9a4bfeb45d5e7029a3d5f192f606aa81756ae08f001c2d59cd94dbe84219891c98b2a1d225c2167ef09	1614366507000000	1614971307000000	1678043307000000	1772651307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	251
\\x6212102d43ac0b0605b852764e48acbf3742f61a6c6cb7f53be46d799257178d8ff34817402e14604aa5a0a5d0013e8c1c0f7da6812e3a2e918416bf64788056	\\x00800003cab8f2bada8c0fdba4f504a18c2c78b7efd9c3428d8f953105b4d945de00584e6a3db13116886f24ffa18245b2c3345cd80124a3ce37ea006cd47d1db3133b15d57d2d58c50dbb3a1e6cb04e4bf8596db743aaa4fb5db3bd8ec6eb137fbd5624b15c04f020247f699bbb915e6d21aa8ea08b63b1e8a8b32fbfab67e282f1d469010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x4eb8e16c10628afce1de367d5a9a180fffb4827013d445498b74cde8a7a38e8fa6c2e8028b05c74a5eb7dab315eed0b2775f57121c82d6dc9142773deed64101	1637942007000000	1638546807000000	1701618807000000	1796226807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	252
\\x655260cbce97eb20e1a3308ad9dac9f2aea3972f29fe1e4b57c304b2202954c467b1e0a17545a82a3b0a48ed670bc657594c4921b780275804850de0f32cecc5	\\x00800003e5cb2e9df5dc2f9797ec80d8f57eb5572afcd67b05b91e39f5b8a16521b6b2db688d8e076bf5405c95bd82101ac53cf195f962723790716623d01ea9f3ee0490700592c5b4e8cfefcf3a4451c15e12e10e43bf78b5a350958ab6470eb46deda87bb4a4f5dc5000bfca9bde42a2157e955e5d32f166746f2fc3a9b9fed484937d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3e0f883eac7b44bceb90fdd4cdc43b7c9c6ba1d5117f350df4b6e3a9da53c1834bc6d71477bd2845b7d71e938d9e2bb9337b56ebeaa9442320f663d2a11b8404	1628874507000000	1629479307000000	1692551307000000	1787159307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	253
\\x679ad0f5adb89fa781aa5051fa5fc3b407114638200d0b0565bc14ba965ada1dfb981b2975b3e536dae43b356d22c9461fd865d914151c07332ea453d3efa6bf	\\x00800003987468298c2b9ef87630ddf4f86563547e85abd1eca80f6769b273e5caf43899a21b0d3bd1516d59d32c8dfd7dd6758775f68e785e6ba4dc6cfc53a671321e0911fdb7f469db5acffc3f6b404d3390d0dc0a4c139999a3473282d22eaac3bbadae0e6bf610ff31505bbb72d6de7a12568dc953eb17720db5e7e94ac75a448137010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0c94101ba6913f6ec16a5a06d407be1777bde11179fba3049e4c18b4e5d5db45eeb4037ac3ae110ef64d16a6b3f521162624cf88dc0eeba6b3bcb6bf38361c09	1628874507000000	1629479307000000	1692551307000000	1787159307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	254
\\x6a1a18bad926284a87907e347378622751b2685e51862f11773e0cbebfeb137bce7886a955044676474552b8faa452a5a300dcf1b54e0d38c9e2fa254cdc133e	\\x00800003d4e5ebc21326817506dc29c693a5d93e545e9cbf39401f092f6e14115cf67bb7fce673bacb274eaf05b0007e69c228289f37337b9520c5135f73e6ba3625aef03b46d5857c686319320553cd2236348d9cd4116def44d9cd96b01dfc0fb81c7a11e96e22aedb619cab079529ed8399398902a18f6aedc8da8827e0eac347d82b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe9d33ab6456ebfc6a8005c403c344b2c5c91d8dbc619bffbcbb3b8ae1bc3cea9e8799c0eb479ee6968f5a8056bda40cb1248d393e847d17af35265255ffa5c09	1636128507000000	1636733307000000	1699805307000000	1794413307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	255
\\x6e62158dcf16950fd4777bce542435e8cd565bbf335a1b4afc5080466b8d551d3ec1b5fa777683c0aecb07e538c5e47b5bf3f3b2d502eec589cbc7ae2884ab35	\\x00800003b8488d67b8aa9e77ebcf80c155807c30559e49ce64f402f341a8c4529d23aebd1a1dc3076a421f36e16cad3617c2eb468ec4411e9830bd31b722a34ec3c7040ada44b83f79e49532b96941a741d8a060925d4a86bf6900a645be1b9bc9242db206b9275e65ad6c835f13050d7f436060432124c535df723558a260404dd25e67010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb1961df828698df4dfcdd3fe4292a97d6f298e5d5ce9d02879f1af7bafc6a5d73ad61a069d68f4884f05f24bed1cd2caa8c61e12b60fc34e828790adc02f1a02	1624643007000000	1625247807000000	1688319807000000	1782927807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	256
\\x7096d26ec46d6dffa6b941ecbfc2ba6c062b026490d85bc3d524cbfa3c5bc6c59d98a831e2b8e9170055dc1941925ac3597467db2a2a300a650b7d810ba2079f	\\x00800003b56152e967a11c13cc22e54f4b77f455c5ea0a7edf5c705a529a5874b1c815ca238c041cd7cc738cf764719368466348091ee1e373a4074ba59ffc908a59c04b95b67bc291110ffcb4e2e7ba02aa81628db8c0cd63301900af37e180fb5bfb88dc1d227b84c39ef4d5df9af54ac75a74b1129baa0e88972a99957b9a4088ac37010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6a27373f0ecb38ac4b59985652b7a0e6354e19c6288e1ac00ea8ece74c175f75e38da6a437215b68a6ab3f54e2268355a4afd27e0a4698eda49e81114278ad06	1616180007000000	1616784807000000	1679856807000000	1774464807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	257
\\x733aaf8d94d40c1c3625a20915bac84de36ee424bfc7fc21fc0599d723a30d69550411001cf8ed473de4f21429b895bed20e36321e967ac6e2bc44b853546ef3	\\x00800003a79e17dff041962bfe3937ae0ac8e3b5fc8f2b5688a670b3f45d9801605efa79208b9ea1a6362161f68963d28a3cb2a1f29322cfe988c8ac63e68c34cf3d80fafeab690af2a3ae33bc820c6ce22174d3eb967d28198d930891e776715b2940e70cbaea211d4611991680cc03e2a6378f4f7656a64a1e83d2ae32a51be3cf641f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9007e60ab298104cf3f0bcf3c6f081b9ae0bc2a5791217ffb61dba0b1fb68b5ce8bb3d1a77c54a7956296dbb99f07ec72ffc09886b924a34dc0cbca2178cc200	1621016007000000	1621620807000000	1684692807000000	1779300807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	258
\\x7c1ad54bada7469826d43837cae37aef46020ccca605fbe4b30cb28a102417321e9d775369e7cb54ce039aae71e35a7a29532802eb37a1f247a904b6d0b8858c	\\x00800003f57ea10dc44174078ceacfc0377f9372e0886d3add6f8f18d06f17a13c0a7ea0d304f3a00b47e3d0315fe8cf1e874360cc6be5ac3cef70d7f327f4b5bc003b278fd87da2703635b210485f4c6d58f90eb0b9228f9eaa8818937ba89d15888002e5f063d096591834b3c6798d3794bd5580ce2fa8aff707b4a7adb16d99bad567010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6d5a14ea29d98026c97af8aacfd78c9c08168388fdcb75f8d389122e1da829ebfc3f7150766a930db996004946dd5e2ef500f035e5c25e8452692ba14c8b3f0d	1636733007000000	1637337807000000	1700409807000000	1795017807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	259
\\x7e0eb9a638d53ca34446e7e81ce13ec101b7962c69967c0364964d80d116f590823221fefb28042562d2faae84dce73511350e643a1090a5954369181563fbdf	\\x008000039fa1f1977f502ede129d4d7ddcac70bf22f2cbfa59999206b660f036a17fdb70aa83d261e112a6bf0ea2ef9662283948a537c5f619fba51c2c4a03a164f3859ee446de6044e83dc93409578a1afef15cf29a4555d531d1ba4fb7404092e2bb1c41a31f3da3eb203cb8dc20641ae5b4365ae427e964054cafc6b4ac1c9e990ce9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x45ed8c3d0dc7ca0334eecdf418c937c97f7909dcfac2a76301d39b37cebeaebf7ffba9c92f82adade479d58e09e20666ceb7e43a622b7cdab9cec99af880270a	1626456507000000	1627061307000000	1690133307000000	1784741307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	260
\\x82521c46c2d7ddc8c26e595e23d245f854346919c8791307c3efe33ecf27782dd045a0771c548f18454a340f9603e6ad9ff125ae61f4676bfee10d72167ea9bd	\\x008000039819b7d45f0b3ec0e7c16c3f465eaf7e92e59b9c9c380234cd9ff48b628c49f0cdf16a6df0d301cc9e6f63b4e24630c43a294acae0cce53acbaf499f086e34a84c50e9891f9fd32bdabcb36ed0c1c4e5a6199163475cab0080efd9814894a6411053e1fb7aeabee4697698c22a85734ef4c4d96c0f13d4c92c39bd5facf89947010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x696aae44feac5e305679d54d709fd7fa39f565d1ec44ff2bdd5c74370102d473715be743e27270cf46b638394e573861078d90b7bf06e63dd13110d03f743808	1631292507000000	1631897307000000	1694969307000000	1789577307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	261
\\x82fa24de5bf0cfb51f5c101043bf632bec6dcd8d262560b0d4418c9bc66d6f2d8d1c6b3b553a7a62a77c0e7425bbffd5d5e2efa436c0df9110daef69cab508ac	\\x00800003c06d9e6970a8bb0d0370e9c3ade2dbf9c3c248882ce368529aeea06fe9b063ceb73da0bc50b1caaff4a313784bc2e90db7b5ffa586fa35afd4a8c3a64d816b4495249fceee22e56792145768316f0f89deb388e87242371d42e3e6e15f81daf4025fbb52818333c9b0d66e7efc95e785760e3f1de70b6ddae6a549ecdde7efe3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x17e2c6662a9a010b4a2044e0a8aa7e0f8b1b55bfe728b27e947d90a615d98b43b09ba669d477e972e9db1e571f2aafa13018514e2bd1cb7fa7a026dd65c8e30f	1618598007000000	1619202807000000	1682274807000000	1776882807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x83220349de30aac1fb8a975e96ccdbf07b51ee8ce3211602df0762beb0e2511a00f2f593e4a2de09a74c781a1ddc697c840e505da8115706188cbe537652ec6a	\\x00800003b6b1836820a833998451edfd33dc33805db9d8f765f02fa012dca87451247109bd1596d21c6e56876f491dab186e56f027832fc8cc794b86c4461a3b6da65e6663d2e9925ce61bfb305f105e13a77dc3744f819c78fb622362f0b352ec3ff21809b7debb1210bb41ccf0cf0bb3b69e2ac93055ce4c92ee8ae2901295c678bde5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x12117d9308a0eacdd49290d8d220d957b41635626bb00c504f7696e56eb4acfc75de108f040f2581ad244e5d3bb278e9e8cabb9e91bf96e99c1d71da87569c06	1639755507000000	1640360307000000	1703432307000000	1798040307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	263
\\x83cac349fa2163c81bd8a93220afcc35b215628b2d170238ea015e57f378f9d345796aed32135790b62c71339d595127d9b71d2260e318e576f756a22941a54d	\\x00800003b925e9aff10aaed1434b3330689db338cec34d83c3eec175a8608e48f4004517259f3a3c583733e31b510ad704d3b7a8f69bea5f0f26c4bdd43da291fb20a5d010e36161b4483c388296dc90f6f7bcfbf8448d622f839ef2d71ec0a72a284b81af0313179010da1a92c640ff475aa1be41613236a086ec629626d45c19e3954f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8cce56aee0a841d1844c8f412256586caa187b954bd8295e1cceba7d1f119164be87f06700974eee992f4b532ecc34092ffb212170755dd72a2581ae53f8f602	1615575507000000	1616180307000000	1679252307000000	1773860307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	264
\\x83b2f84d7b3d39a2a595c7f6529c9c6bef9453bada3096a3e3b17fcebdd5564e55d6e10ba7a8f7914fdb5ffc90569c617d8a11229fb26759e875b8ac7f007d21	\\x00800003cf4b1c07187fd017b547ba37495123b3df594beeaf696881341a9186eb6631643f66e04eebcff7b3668c44f2bb375ddad8112413683505c542f4977b45e1aa4db12da2ef64f3acb92e60be977be6276c895149cac84102e08ebe120e650ad24d75f40c64d4fbe3b7c9ff2218cfbc8c9a68e4677d2b38877c1188d6cc585724df010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6d97c9a83be256fee95813965ac40b88c22aa505f0476c0362c6300ade279e5440b645af239999fc5c3301a460db65a688c8b4e55abb60292f54b88f0846600a	1617389007000000	1617993807000000	1681065807000000	1775673807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	265
\\x86cec92e94ac0c57edde880809f372bbeb32f8010ceacf1a8827b2b83553cde56a4918042bd6fdc31ae41312b3c2d97c8fda39a4261031672e59dce9fc17b650	\\x00800003ba6241e048010caa820fc5db834ea79ec7f9eb45ed360a6413180fa171b8a775a69787a4c92307262defb14fb574568242e0afc7e77e65750e41bc3e4fc0c0bd311649a692236f645be60accfe5dceb47c7ae3c8c9bd90aff60cf268c4b79f83b755233ffe3d633f15cbf2442d6629d956d735af39c2c9a632c01fcb357e4167010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x362929fed0ff3ecc7ce20508191e71ffd910dff1e7f823dc3697822de5cd8f51ba7612f345732f29eac3c0ab2c4145199b6e3a73d10442928f726a76810a5d0f	1628270007000000	1628874807000000	1691946807000000	1786554807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	266
\\x86ceb9902b324ed1cf04d2c3b542f7ebd00adc3dfc086d075ac49461ae52bbd47e607bce6d8c3db8e0537c0864a0886a056ecc604ff0b81762a34ec71fb6bb7e	\\x00800003ee4f16fb4eed88c06895ff649a0a69d036a56371b8ccc34dfccba0bc91f6d753a11fad00f0c2572fe3d2c17d4374dd94cec42d9eb1717238067ff186f270a0ed5a72594b789fbb3c822593692946008623fac6b1bf1c5a86e607745bbfba11a5136285acd57019ab8ceb7343b44be5ba57507505e4846897542342c8fb38b1ed010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x43f0a2bf2f7b9d16b47c9e0341bcd414bfad3d5403b6a65ea1237f60bacfd117f47200b78c37e9cefe72b7d02e45fefed194bf596df27f3b7c7bd42c2c23d104	1622829507000000	1623434307000000	1686506307000000	1781114307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	267
\\x87e6d99e32784a2a5b76ddb88ba5df58aff5929ed1a4ef4b6ef1363a53c3ac2f01916f842901e9817753172d0ff91fa9328c861f2bdd53e7e365c8eda00dc1a9	\\x00800003c158837b8e05f9635affdcaa78db313ee6807e696c5808e4ad20f0998aa99158da032b8c613d77ad70c983e5988dd4a46ae5312ebda17ce6d2c0c98d1be51fdfc78246fdb87347e622ecb1df212dc2aea26ffdb07707262f2522024ad031d717183d3681c1e3f46fe4f5e64b94c40548ea9540fe8c98918080854bb82f019e1d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7833c1eb7ed575972d750c881ee59fbb6b22d46a60cb1343557ca6bfc28ea08161dbe8ea268410a8726dace9d6a87228bf5889b79d6e2dfe5fcd10b111d0e101	1619202507000000	1619807307000000	1682879307000000	1777487307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	268
\\x8a32280618644cb2943827ddc83c4c552b153105e4114020aabcae55349e61764c9dc86399a8632ca1e659e9069083c9994642f8935f112d1179ffcf8256d124	\\x00800003ac3743e9111d4702fa23886936f48411a95f589c241ccd473f059e7df6c4f2034d39a0b8a88324c57295cd1220df4e84899b470a0e7303312e68c3f0788ed8ee0a1f99917a4c869f430c77e82889a299b4e1b890a1646c7a19837dbe9a4a67ac20071bff288e95f564abb9c41fd7962174a6d9d9d19a761b773d21c716a07683010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb985aa5ca16ff0e82aa16cd94799ce0353f9537b0d9ecfbc43a2d3dc4a1b250da6025fce30090203298c968efc6751c425bf9725676bd90277312cf97284830a	1641569007000000	1642173807000000	1705245807000000	1799853807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	269
\\x8bbaf43ef1fa9b25b04c99a8be88d2f2c29780504e5f2aafbc5668ccf0b3d32dc1f8693fd0e6bad1e39f3d52101b9c8e6f0ee9c07ef13f852cf255ade968bc0d	\\x00800003bba0d2f555c226fb1f6fbd53688f5c46f0cdcc50e7a1528f282d29e4711dae79a071dba9e88aa99f0037019a41c2d55f052826ba3e330d217e5f73d1445cb0048c46e0afa9b7b7e77b8e81d264a71216936a1d7f1de5875f99035b6e23e23353bbfe25b8d8d18ebc87d6924ac192e98b2d16ef370fe2e0b8b8e0de37494010cb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc96fd1eba9330b5ae8ddef6d4849f3c7086980bc1ceb26c6a855b61494e26adf91e290dc89c7d1bbf331854ec1a049a30ee21e9e14852919eaa6d68bc5559200	1619202507000000	1619807307000000	1682879307000000	1777487307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	270
\\x8ebe834834dd62716756987ce9347e01eac8884a65fe6c883ef656314265c6cabf96c0da10fa9053135eb7f78a26743af18ab69bb5532a97e7cb60549c4f2055	\\x00800003e8cde88bc969be2eac041e8a76905bca5218817129f6b31a40d4bc8c586a0e5fa923e06eb4937a4aa0918349263992f8735bb0593de947fd04a5c3208c9e01417d29882dc1742c4a6a538c591df731a818450d9fdcd1a1d922dce25986aa1ca6ae5c2af6667a38c800b4d6969d562b758a11cf73da63b8fa692120073135532f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x80f8e46fc0f7d404adacca7f30a8501119f6e16190e93bce4e01678e7df8c44ebdfc58120f68aa9bf3d758941018b8aeac91719576d83a33b96e086f7d7eda01	1633106007000000	1633710807000000	1696782807000000	1791390807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	271
\\x8ece0c15b3efe0fb4bb21b7aeb2fcc51548b434968c8589b7d94e36bca39fc1389b71fbdd45e484b1a0223847213f5e4f2cc7dfc60bcfbdb8efe6542cf4ea797	\\x00800003d69cd80541acec436ea9b826d093837e616b4ceb45ff717ef93248dd1d9232bab55467968e313b99f9ef4b72e2911e05a2ad72b12c44d627cf9d17bf39c7eff8c750f9062e3f0063a34944d259b9c7e0474c5ddb71192b8b53961aad4e629d9bff3f52f1b887ef088281690cd74e16e20d34f9d78e48c95f2777fd0be52c4925010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8afcf3cd7ccf39e39bcc496b99b2a141d5e5df67ccd16c9fad13122ed7b990ef65bc11ecbab2908e9abb92be35ad4ed03596d59a02d73efd7cbb2f4e2615c302	1629479007000000	1630083807000000	1693155807000000	1787763807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	272
\\x91b635b611e362f8554a04f1c560c6a11f02a1b20f752fcdcf00ef226bab959b3a4bf526417e1eff3a949cee9440c82af014cd7cf647c2be6b2cc2d1af54f9bf	\\x00800003d2deb65b098132af56145afe0818b70ed8970793d5a6ae5e05daae935f7ffcf5085ffc76f422cbb5b34a643ff27daff235169c29f83a3eeb41518a2863c792f304b7b9cd47179f0ebb1c722784f8f43d39e97c22929e450e0cc36236a7cafe32349c4198b8459c61bb7a85b6dee90720a56ca173e6c2c5c3903f65bde05a5b7d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x805c8779f4a82f6feb3717548ceed54531e25ec17f0662339b40660e958ff3bd93a0ff28de588147505c13c24af3bd81863e8fd74b4773404cbad418ee35ed01	1627665507000000	1628270307000000	1691342307000000	1785950307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	273
\\x92e2d4d6077e00775879213b9e92b76a11616216a575762e4230f01b4e2838080693233b6a68396c1e4d57370a4f122f35d051833dc39a001ca75b329e4ee7ef	\\x00800003c5f6c21e02a8162a2718d943205351dbbf2156c4094e6b96424f55796a3b3b2e66cd703e29dcb73427052d90ef1a9ab515458d80dabad006adad31904101f5edabf5bfbe3f82312f1dde8ca79743e0e047c880f4e28f014aecd25dfb9c1dc554a3c5087fc0835eedd7ecff82f98fd437b7f750cc142e6917fbe86b3a602fba57010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x56dfeef966f26fcffd76e1c59f1a51cf74b1e2fa0d997a0a24c2ab5795351a7eef449b404cab4c9ea175727136650983e691c7b8b6bc0651d50963c5d58b7b08	1611948507000000	1612553307000000	1675625307000000	1770233307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	274
\\x92662914d53caa2eb6b987e98b4224842fbc975f05ae5ea75e156a386253b8eaa2c44e6de0e49f658e138efd47c591dd8789861129c21a9c16eb3c84da054416	\\x00800003c5aa504412dfd46044e0375a64a4517cd442db246b4c5ca5c1d876a961d8d4ccc9a7e0853be6c2a2dad2e69ce34ad0737b32c67f9343005b90adbafd2200f18976be76ee9da8ce65595d329a5e818e6bb8b175f03d898cbc3bece646ce55340c164a636fb6b2b8d51ac25d1fa4a59859cd403af4c81f0b1acacee58795bbd0d1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x333cad6f63b4a41bd57c3c9f97c8deb8110e5d5b4c7fc3af42384d6f7a547f24a4d398b3cef1d82450763a77cd501a8f2e9b25d391b3338e6a5c39d76b58ae0d	1629479007000000	1630083807000000	1693155807000000	1787763807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	275
\\x92a2bc66a9a77fa24cbd72fe2b9c75c4c3d66896656563a24dc21fc97502761c1060b07758e05876903aeab2ee9aee89ab6c134b8f6363f13572f7140bb9921b	\\x00800003c122e3d5d9cb34b524c11bf414c12a3e38a27816c21ff74b27d9d422dafb94498711280971095f09c2f1c7251b1647a2594a0f808e4a077c288c7cd8d2f39c0c6ca256172308b471dde573b76daf427af438ce87d23858af464189e6b32bf935fee764f4b41696ae3110bbc651ad7061bd4efc985d8b659421b204bd50d2f739010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x20473399d32c138b75516759822538a4010132d83fbf97a680f0b843f7fe02274c28c9bc8c01b723c8406cae7bd340bcf088967e6367ebdfcd62ce147a351808	1640964507000000	1641569307000000	1704641307000000	1799249307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	276
\\x97a24ec897bcf2551fcd48ca0d791b08593c54a0bf92d7547581c32a27addb34f3922605be9b9b4a58398df6ee773914259db48ba686e8049ddd62c47955f5ea	\\x00800003b3fd1ee13140457694cebbf4077486180a9f202ca8c883d72be6fa737fc8aeb570d566b533b02687208e349ab5252c97a00de7f0708adcced724c44efbfd2180e9d084dee47e9a74315e38f2fd5e91990b02a3761ff228dadc63b43d08037783ee12253ecd5bd007d51860b4a2fea42155517b912c21ae6ab523a7a7ac9f11ef010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x46b8f9dc7fbbd8d0b4cd00e2ba915122e0fca3f32504b7568b65f9a23947e44fe7c612f78db2de357e3d8e6c4fee7fa1007fe51fa8f7b2f623a0eaf24649160f	1639755507000000	1640360307000000	1703432307000000	1798040307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	277
\\x9b3ea1246c99cc364aef9b53dbee526bd1e94ed13f3238bc408b86612b147cc849b2f60bfc6c4dfaeae3f4878ed7c211d0127ea3ded1065783b514774c69757e	\\x00800003da74c36f72080027a60a02ca3b54ceaf68be3a06e1185dcbc44e189da52591e12e97ea8b71ac2629cc3c5cdbd49f5cbd9e10c40925c67f4bd6a97b8cf3baaa3c9c78816450b7d584692100f9f6155a423573ac40b17718b091a32031dcdc8772b17196fbc8352be9fef50f7384abb52cc6360b4236bf1663e60e3b1db3a24149010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x02344355fb837983d994f02922c094db2ed77dcd717768f27f9a31ec3f71a1602103556cd9a6af4299d9bbe0fb4b3591a9dcfb724e6292b92e45869d35ae860d	1638546507000000	1639151307000000	1702223307000000	1796831307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	278
\\x9ca2a95c49f7170b4ad1536eb9573251930048bb386de216692be08856d361e480ee4910ad42b14b9fc053f6dfcbdceb0c9f63da88a6471143b0c2ca5c25f272	\\x00800003b1e3cf9c8ac5f808d4653833961b43b7527dd2c4bc4febfc2d03c8ac0b56dc5c97768a75e6bfbaef8e9a2f42dfcc2f87a0b7d8358bbcedfb83c1c6c0146ecfaaa349ed7975b33b5d2d4cdbbeb37505e24fddf51892d9b4ae38fa2dd943b6196a3d9c4105e9694fb4b28b82a0cf697110c98d5a9818bc619535153a6a31c99d27010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbc019be8822b910ec4a4dec976f49cdb380b350d36ba7589c653f03abf27114355ba6674691036bcfb37e60f4362a6be54a678eef36ffc0bc35051b415d35109	1639151007000000	1639755807000000	1702827807000000	1797435807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	279
\\x9f2627d0d7e4e6d6161c9e922a17569ace69cd3baeb1c2ddc5a516910e9f0a7a15e3bf9777b1123ec0470ad9d7f6ff9173e9cef6a3c3ad9ac851436459509143	\\x00800003d81a5ac3f8f6485b8a440dac81cf6e33c6c9af0a5e92f7d2a49a6e5b9c064b9a0494905932b2d198aa2949f8f525592626813326575f8035f1f3ce20920183adb594c637425c8d5f03a2a3c3d142724cf9b4f99329756a9c502205d68d10166c5e17fde57eaa6698ae0ec31ed11c3de2248c4c9f2a26ca3e0b03382ff452f663010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0a01871856c2b844373d9bb87f4415ec8aa5ff71e48d1a7b292a7f1f5903f93cde1ce86dca66a79d98eb4847cb47495d420324a5ebde4b8a134e9fbc8b63fe0f	1625247507000000	1625852307000000	1688924307000000	1783532307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	280
\\xa03e1f810220b79efab793cc525ad6ebc18c1fdcd07017725aa2bb669a215be9587455829bb6d1433f22c080a4a401e72c04969765258d9cbebd9e6adb6c6c16	\\x00800003c81760c22dc504def7c2228db44f9f125364d6737c16522bf1caa1927fb5493c6fa2fffb21e8237b8a48bd9845118e1f2e2f4a5d050171d1005388d8d43ba82edb38defb45b96d76ff7ca5d4922ded4f7f6dc1887601fd8c98359dd47b517dfdb2bfcc34bcaa0f35c8addedcea278c7662a97dcba1d93e4546fe2f67557c0f23010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x01ec91928b4e277e626dc08e74df875ddf27c77d2b56a6b5dd1d804fabeed08f818ecb51657877b28bf7133c6415990b81a138dae39a6e77ab79af6f48a7f80e	1627061007000000	1627665807000000	1690737807000000	1785345807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	281
\\xa08e45bf63fe7840a34014f0ab278de0a5d5b78f6701751771a1010e7a483d0ebc77a4b89b4b614863b5585946846f30edd540b06c3ce31fa37454347061a9f3	\\x00800003bab9ca5dbabc328e3fe8af21fad7f6e4b55f184e0b96e3adc6d131b1c77c198ccc961e3728a67edd673891519492beb5474222fff12585712b2a18345d677bfb78ddf7b1010ceb404142e685f09af3b79f0ef1cfb4fbf8c1c7fca1cf6af26d2ef332b60c16fd6f43c3f0123072db529ff43e3a7a4149adef0e262bc7b94cde99010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x06da6e2ad83af4ffc3f916682ce7a6a92e062faa501044bb44d21256e00ded3373efce638e762449b2035b4e9d018b4cbf4e95fdf72eef3dac0158ae757b590b	1617389007000000	1617993807000000	1681065807000000	1775673807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	282
\\xa1a60e447adf63f784bc6ef8c424fb30e298e6f3c2c134403a274b1611e230a99fc80d776d8c540b03742540e97d26ca6da492898a0a6729f31ce38c212edda7	\\x00800003dc510ab89c3ed482a0e4df968cec5790ea52cf44f6c65d693126184baab1bfd10e1568ba76651e9dc3f432d7b9a8ff112c67499f11991eb2b73a7cc159204e97bcf1860f651d2452d0c8e165a14715235c1301c421058036813f0c0fe6bfc21a1de64c508f87edfff5213a669d952fb8beeb74c0848eba321377d7cc60af475f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe05b6a335497b8e1d3e7dd85844b1188847c0e9c3b4cf1dcbab4a532d15d6e04eb170913586c39d530ce097bdaa949586491ba893892fd3341fb868cd8d3d90a	1617993507000000	1618598307000000	1681670307000000	1776278307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	283
\\xa14a2b590662e2af1feb28a7df90f565e64876600674269f062fa0d68cbb988f79fee632d4e947e1dafb0381a56cc5a8ffcb2e01caf4b651c5ef04dbbf51444a	\\x00800003b3113fe8090c96359213f3f62d044b8c6716455fd80a40b1141d668fab330a748c137daf6177cf1e2cee8214513557c27f0d03e9c51ba696f4a466001394e9eccecbb5c4f6255e82c21210c938e1abc6fba35d5b654429fb26757511cac6ced1d7aef6832078ac8e5ea679fc51e3e0d58f4cf228e70dbc524d540f275e438e51010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x26be17ad333cc4804d5ccd5148bbadaad4f8593cab10049746a19bd97d46f6a7ff198990c1a0fd7028efaf0f15c8faa351cd8c88a12e1c866fd1695395f09e0e	1621620507000000	1622225307000000	1685297307000000	1779905307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	284
\\xa5c215a8392ea8c9387e809437da1104777d5288ea3b8fa23d9f1243a874f41c1380ff7a0d537d373b99e2b5ecaa25b82518bb78c8cb3a00b476139f66a75cff	\\x00800003ef59f9bf1b2a44870488c40e3486cd70679aa3f2658c4b557f32f3713cdd80be6be3b548d4b991cbfeeeb23de6c86e2e3aa824cc83d87b07246430b18a83e0d0126c8bf528e797e4b02bb23fe94678aa07fd970fc59908b81ae62ddd6ea74fe2c61261370e5ac43cd0767320ed36fca8ff7be9a61919a4930fc8fc090a325121010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xcfcd95b3665661305fb48bda4ad0e53679a47f82adfb88ebcbd7d88c4f7b2b3439785680ee529f776a0c5d6c94154f4b64815fbf894a910d5f9cd591e0a3ec0d	1631897007000000	1632501807000000	1695573807000000	1790181807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	285
\\xa7f23a9d913e500a1ce9d42cf60c572a9fab17041e4f09ac32371d6d3ac8cd2d3f7fdbd211f1a0bc74618f81d7255e75cce1db880ef384dba5d7eeed72afbc15	\\x00800003a718736994d7cd8fa013b348d1625c18a6048f465a309bc0561b21297a138da697b5309992a8bdd43c99a301b972a52ee247213afb92087e362d7e45d865c72915c5f09417fcd0a7d39eaa1f207c593b03d15d203a36a79d6b11ab162f51ae5470fa8c0d59a9b8a38155783d5a6dae0dfa82890df039127d2c3803dfd15d3967010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd02a5785e3da583fe7859a3ac0600126b7d43271277701e2fee3b004413369924c3b8895a0e21a6fae8ef5b79e7f74edf0ed1bd6705420deeebfaa1d1ef9b00d	1624038507000000	1624643307000000	1687715307000000	1782323307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	286
\\xa77ef57f091c769330b4ea090389bbee37658240647ccf09957e1f3d8a59195168539871d28e60b4912d58e430ede8bb5a72ef0bae8a45209b6405d7097132f9	\\x00800003ca88a71ded930f9bf16fb4e38a25c428428d2138778cebafc43a25e697e1f51408f5a62e7bb9ed721cd2371326b6202a82ac121590eed19bf69b527837ebb122bddce862a426ea2b2afdb3d1223f21f2262bfd7447aad0dd5410e3d20cacf01ecff1dd70fd44142ed78fba0790d5307a46d51dcb2088a7a79900dea0ce525cab010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf8bfc4bcf3ee2e82dfe1b940ced16332c9d956ccde3fb1a9a4306e3fe47eb814fecc2299af0f6865e32fa918aaff1a1e563d20a982579bafaff5040c7b144b02	1611948507000000	1612553307000000	1675625307000000	1770233307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	287
\\xabea17b2112eb31d1b815c4a75b0ce116daa355e0666771a9bbc863346f86713ab4525a901d664d282bce7443f99851c310c228c8987266b691e2f840847ca52	\\x00800003d85f5ec71b12ffc57e28bb49de6b6b05a067a4843798f099ccd1e9a27390cd13c8a7bc959aaab08d213f848ae67febe3a06f49164425b07a21cc040bc55bc93adce683a66d5abbbae09705860525e2075397658b18e9b9d078415445a23af040617d5ca36271d38d89cebc7b2e1333fa06bb9e0793c5c8097b9e361988661d9b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd4095e25cecbbd841dddfdfe7b2d2f00e670d296972aa6b9de30188924280e8870f36634b28bad641850f46f07b78c589bb4e55654a712570000bc2e6404e30d	1621016007000000	1621620807000000	1684692807000000	1779300807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	288
\\xacba012474d76389ca11331b290a252effd62e0a7eb40823eaa0012c55e05d442589af8544337966dd4587fbaecaf3273bf05837abb2348bb49dc6a0207def61	\\x00800003df03c0781b46e6b081b2aa6d834ab2e8c9fa1d6d8d237b3dd27fcc5365db596ea6d2561d25f269d504f153a42bdcf5b166ea7e81328bb47eb5bc305624ca4e2ed523659b45c9db10734142d4eab9bdd5692d2bdb133daaeb2bc0b5ccb840880b7b63112cea910760c82fc8b634cebcafabf93162886c83086348ca7788f0f657010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x819b37a309c9618f636982f0de4ab84805174b85f6b5652b9ddf869b90bb308b90ec6ca079220044ba2de8041d4f332dbce729a86a0d1d260d8a5fb319b53a00	1617389007000000	1617993807000000	1681065807000000	1775673807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	289
\\xad2a505fdb74ffee9a2d78f8977e9b93256a06258bc2f0541017e7f1c4ca1d0622aa287a59199077d936e4c2054902c27cfeb60b1633b55e0b8edb3c91f912ae	\\x00800003d34d2f9205bb622783fe7b5d2466a35259555c647a309bfd6ead9445e51ad450493ef3e4f5c2fb44708d8f1c081044073b0ba3d8840f00b50615ffb0d044aae9156c1d4b3d89fa60a6960c578d90e310c5a47fa0967d5ed2d57334726e2866569385ed1d804ea9431413ec5e5caf2c658197125dd429f4bc7d23d12614aad199010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc5011820aa9474c425ca862aae37aeb3b2ecb99282ebfc5d6def472d416da88f983976159d0eac22cb4d1d3e53c1a3ccf3be83c63fc8d714e75fdff8dc216907	1640360007000000	1640964807000000	1704036807000000	1798644807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	290
\\xb1fa514efc801b44113be614bb4c53600388350c7b18343e742b32a295e251cb5a01e7e2b70ab550332f5947e752c60aa671b0d3281bf6caaa76bb1a469ad618	\\x00800003aad5510e81dd7d72e5750fe3fc6fc4bbfe7f70fc9c33fef0eda7419aff8fbd319dea3fc82dc85626d418eff9ffab46c9cb76263e89c4eb625ce60a981fec61af34304928c0a6da032e72c1dde8cb6f70963f87044f7b591229f0c5ded7f3eee2503fe4645185863e274b47e5ef959b603a1d7d9bbde4bb756e64b786b8d2de97010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8dbdd11225f80ddbe82fc981f342ef53081b256bcb042bcfb621c81165d7541663999bfa9a360c2c2a9b3d194c87afb160d0232d54e654d80a8c4af2d93f9d04	1613762007000000	1614366807000000	1677438807000000	1772046807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	291
\\xb5721f47c5f7d1fe0c499ca5df08f620c75a07cb0ef9cc05c0b84d97b847580f6b05ac682124a6b2fecbd255d5be42776a9ef6939b7096c8d86e0d1c4151c648	\\x00800003d557234204ea0ba88592e45636e0e3db8d01e8cfffdc818ec441095975a0f993892390bb162e715498b8aea61024e7ef5ac25968e4f74d5c73808913d3facbbb95ff231facf176396d22173def5e2cdb62f169e103f8846466e8987e7b8492d1a9e31034d4cf87b612b5ad59511bf00b7def6979644e90f93bc7981cfb161629010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc3cec5ff8a68ce248ab97e239d4c7bea49e36e39b42f463b87f5cf8da18d5d100e9640b074568730372d0798b693a8d8eb79e2383398e96a6bb7155ecaed0e0e	1622225007000000	1622829807000000	1685901807000000	1780509807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	292
\\xb982b2fb1564a0cdd03003e03ba058374da408f6a1c6e8ff306b2bbbd9a888bc99a1cda75acf25ae815f519997ba4648f99011d7f07d514c1608bd0898e9f832	\\x00800003e744c5b5f118b777738d8897012879bcaaace716205047950306c54ea77e66561a02ccd8d371254e9cd1d31bae6f276d7bd472e984a9d2e35cfadb3b02c89ea937409e11748514723ddaaad8e64588fc38d7f5ca19d69160a646e8fbe6e214ee40c19aa8ec05a6b3a869a9a589e40b0cecdafc9074d4a78d20136822ee05db37010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xda8e67959b687273ca9c5224cd74de80448e9811067ce6722ad564b0aa672a1cf6e6872f8c2fd18a6d75fcc457d6950f08bccd5e5e6e99cb63ca81b871b1c702	1611344007000000	1611948807000000	1675020807000000	1769628807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	293
\\xb9966a7aa32f21f3a71cc2f61313fa6a2e73c2b50ee8f6425def6c05cd82d2d88aff54ac59fbb74a3ec7c9841a08c0dd3981548c4f492f3bb6940f129f586aa9	\\x00800003b8504141e16c1cecbe12d16591f5d7005325bb0909990da59d7e438fbfdd63139a6cec03aa52e107fef27f2c9da669d0c7e178c001ca8431bb391e2f06b334350e1782fa8fed196579d0028b7e2b1834ee812c8360ac97e48debb0062f17075118f20ca84e74c75d1f4d6c57f73420144c9567b462ba1ebe8c45e9a13fc1a293010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd5d7afc2bb7562fa8fbb1111d5657345b0a2cc4b92539ecfeec04a9be6b769847de3b4ef2045e35cc26c816bcc34eec737b5e50a03232be56d8f7b0ddb4a740c	1617389007000000	1617993807000000	1681065807000000	1775673807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	294
\\xbab6c2a6cf879ab80d39867450d2fefacb85e55ffb9d606eb3d4126b7264b3f541a15012b7399027e59a0ebb612689ea81fa5812b619054392e86907dc96bfba	\\x00800003c9b227387468ffb058f85e9b030aee80d78b6de53f845b62a49c6ebf752c7970399afe209d8bf65ecff47b23b57d25a62bae1835319abb339e667601945e9e82685a20fd5618532d25d82d8e83f875fdabb962194a61a3576995a55ec84128d5bc28ed4c2428ecf80a34e3868f8571589bbaa49b3ebecdce66830f69b9e78afd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc0f364673e3850df6a37c252b1a7179cdb276a2204bddff411ce872b596a3a07711e2439d0cdcf7d617dc3f623cea82375ef4f63880e306bb8030d593245120a	1622829507000000	1623434307000000	1686506307000000	1781114307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	295
\\xbb26d21f339907802f4e5a972e9e6ffb4f5bd151b19f18bcb560512a7357bf7ffe506a6031543b8efe3ded0a364e138737642ca5bcae8ea580a62bc37dfdac20	\\x00800003a8cc2c61586d6463373f1ab7ff51226b1bec940370b15de9d4fe7390cb68beeeaf71eafb63420a78255c5a3594a2dc1c3662a4771c3cb8fcf089400e19ab6757dd251a4321f227924770bcbe00ca80ed65d068b42cd30a43b829029c4b1f01fdfc48f883efa3355fe936ad152702a72dd5f5369302def234a5a04e28be98742f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5041748da181af164d6fed86ec33eb2b9a7704a7d2e36cd76d07182c528997f8dcf162e9a60d7fd4ada291a865c4ad454e2ff6145e47ee6d717c6ba580d5bb07	1615575507000000	1616180307000000	1679252307000000	1773860307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	296
\\xbf9adf5001c4eb3ce1745cd88cb04d617ceb23ac0fb9fa58e40df012f010a49ceb2ec5c645aaa617883d4ed19cdb94f2b4dd3ed0b46c9d2d056f8b8439336515	\\x00800003d3812016ee7c3e145cab94ed863a68dbe4600c52dc46c933a4a72cc71d3917e3c0a5e31f7db37b86d7c21f9e7c3ed4a54d06cb1f1525897015819e602d75ebbd1e9f05c825207cd43225b0ee77861a679f8e7676dd422cacce9a3326c095f0f07661a004c546cd85b8e075d7a8713ef3124f3d3a5707ceab7c7ec6d0f8c5cfad010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1d1fda04dc8bf83eaa3eb4d260b4821304485174a3adbe14ab7b707385b76a92df8f54055f802325970b910e6711de1008e7ba1a998a790f6dbc1af0e18cc70e	1628270007000000	1628874807000000	1691946807000000	1786554807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	297
\\xc05229eb1dd6c618064a5cf9cb2d20f23629e98dfafe5ba572d0a19e6721f13d327a6c5b45f229a0dabf351c8849a71922d341b8673a7ec45373e5312dab9d71	\\x00800003ed355ab73aa68f31225b459e1737f91fe49c02924562b7d2cd532b6845e867eabc4bd688373577b08f4167b2f6af0c88ea06466c3c552bf59b116b449dc37e1d148e58cefe5b7ab5c7e0c4bbcb6665709fb59aea89e8e9b3059dc51ab36d789a407804fcbfd0d548e037f216d74f47bdeebee400d59059901b057e9f14602ef3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x105ef00f0a4623a8d858c9eb2c2be740d67aba6282160ec1db22c34d3ea445dd47bcfd161b8455a3a0ac37e2d448fd3a5c2d55363cbed5a3fc1cec50b2161107	1637337507000000	1637942307000000	1701014307000000	1795622307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	298
\\xc17ea6998af6f319a14806cacd8302239d736c485d8f2e44355144203527f27472f60fdfcc6803d441d945fe066bb16dbc8f974006b353c42c878814985ec020	\\x00800003e210e9fe3164ee5bdae83b5d203c8003649bb249d29a7afbc775841dedc0f731719172cb810e3be0f2de58700ea0eb6f97dfebdeababb554d2dd234665789d87dd663025c471ada5948dfd9ed82ca2466ef1d7e9b9242497f9996fc4e0a16307e3f7e123b0d055bd6f1b5c6f300f3d8e63de71592226b2646e33b7440bb99ba1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x688fe0fcb637cbfbcadc984f40308b392db1f2d53681d8b582055749b0e6fe6752a2633598aacf127d5b724f2ccc81a7cc742baae5c1840c826725a01db6240f	1622225007000000	1622829807000000	1685901807000000	1780509807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	299
\\xc306cadc814aff9caa0be7837257b32253b34a60fe10d6d299a5eb2a100c07daacbd664af0772559a516647016f36ddd7c43355e7838180e61f2cf18eb8ed557	\\x0080000397d9436531ac2a043c39015dbf4404a395d2906b5ebfe3671d7732e99d051eb5b17e6dd76f835e68aa77bd91cf1967f3f25028ebf325ca3711dff5bfe1e862b5a4da21e4d1178710e59d27e222981811b41d2642eddb9df8cc4d4cbffd52a1f99f1d7ebd2e9c18f3770918a1fb9ad9f27ab8d621ef54a08572b0e80d0c289d35010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xaaa85255f2c277d1981c2ae228d038e225011b237fb0c409c3c66e1df38ee8018e1b5c8b35db54ef24a2e044e1410178bbcad97dbb6f8f69de312b7a4f9d540e	1636733007000000	1637337807000000	1700409807000000	1795017807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	300
\\xc6debd657bc90c27138e4b4e56ceaa2a73553bf583ea1e3c7f74e3fac96ab7fab286c7bef6569cc27daa449e86e86130f2e9a10dd378488878a1b0bccb4318cf	\\x00800003c70544cfd54df62bb2645833be3e58b1798c51279732b88bf1699f183c7bf134cb8bd5e34b34d1851a88c142f9a8c73a9f831d8dc4e82cb745e2c4050d730da914b4ec0aff689d60e0598ca658c564cdb4affdb93df0fc441828697c6488a015dfcea1757c6d29aa6761a5bbb699dda04bed3108d5446c863016203fa83138cd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7de4da03166a36630f1f92ed87744dea0c64760260406d1dfbf65c5aa7ce0d19d8daf388d52eebc2f40cd5527448d3f9b3491d12abacf293101d4529dce9d602	1624643007000000	1625247807000000	1688319807000000	1782927807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xc67ed81e22f39c1a38931bdce848d16c5d6af8525d45f9dc1927df92988d00289114ca9561984bd3df374f77d030c393410d31ffc446c105437b92bda89417cb	\\x00800003bac67f07cfd8de6993064463faa5077cdef40759a0c4f48eb8e86e754347f60564745aee16bae1300889e895e161305299a231a859f4baa89596746c12e6a4d9831141e2556a26bedcdcafa345ab1d790959ebcdd6dc4de9b6bfb9c2b18e44195767564716c434a8d3ea44dc72e713062e36f232d5c380931848b5d962e23a8d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x634917786dc94e31f094166eb7d0162d6ab1acb15b96357f32fd9539746a732d84cd508626211fcfdc18a6e0560fb02b83a45d157fa706bd963f5ce934afb60d	1621620507000000	1622225307000000	1685297307000000	1779905307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	302
\\xccd294c6e9c0124c80b99e14e7e575ecefa9d5e594d2002f0ae666f08a41f31fe15da61a170ef34a35bd398d65033d42a00ebe47185d91f1776df95710867272	\\x00800003f26de9e9dfba79c4810c8c2ff6b113c4163a7b4797fcb619246174f031e18bd6a67789433134ca7e90747b07e93197e76f6944631771ea0419d3d8b1a9b4b8b6f4b71fc9b507272c4b6cb9f9ae1a5f395aa1068ed09de34842574db63da080c488088bf7ec4531ff0116725e750ed8b7140fe7cce87ccd9c1c9cba581049b81b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2592142048c14912385786948e57b7097c0c465deaa5a9156b48ceecea89eb9b66d0e27fa0a02db84a7e67ed0adbbc7498c314cb3b1788c7e6902e396e3c4a05	1612553007000000	1613157807000000	1676229807000000	1770837807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	303
\\xcfd6de2613d921368e5236e080b9198980482cd878147540d9565319e0a1ebb18f7edd1f5e7b8a90a207b4dc156db784835e490e3c373b5b19c828831d5bd132	\\x00800003c40c3900bc51289429098ba1cdd4897c090e908dc488594c2376d24cf98ab323bd26d6a925f47f1d006bf681890b7beeb4028c0f4beb07bf5fd110158a665766560ce9ab15680d74238783a49e5c1d972a06287f0e74bad96dd51d23f419f2abb4d35c4487214b1011386cf6c61e28337ac9a1162b6e1d81eff4cc693cb0acb9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2ff8fa473502f52087d2f0a0846e6e5411a91ee180bfb8aaaf0c927f129ff0becc63f52e092490eae04746d2832af02fdb976c73d20398a58b8b8eea13657d00	1635524007000000	1636128807000000	1699200807000000	1793808807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	304
\\xd1ca72e58ac5652eb391065e1cccbd2350f2d889712401c7644e273bb931bb438ea5a23297f0f9f62dc7389255a256b8066d1a9e23503f824f7c7dc3e803be86	\\x00800003cb58248b9eba2a0dcca9b03961ce25dc9490fd7dd0f510265e1e99b7ad0d4a51c943850e67535e7107c580331610e78b96e716521af391539ae5a20733f9831c08b06344b1087244096b881cb6aa6fb233f9791d00cd2ed09f30a0a60fd65c6410f41c361bafae09862625e0fbf017dd4947a3bfac14e5b862098c442114c8c5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x95ccc884f048f4f0de6b92d48081e6f7e06f0603fa769bd1139ffaa5748f0deffe9233a042c87cabf1853f92cc840a27a57a3c211445e92809a8ac6d78b8ec0e	1624643007000000	1625247807000000	1688319807000000	1782927807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xd8ba3aa13f0481c5cc4311518ff89436c681b93bd83ddcfe7c0337cd532d939702d8d6f42d917c427dd18eed384641043729aa016f40dcbc6330d122a6ae1d81	\\x00800003b4b2d661210455ba849a8aab771270ad43658599307e8f63a20c171a5741b5e33765fb9f9eb721c9db50a786b0c5b915b59f9c4a51e4fb2c27436a61834a660a1edf52d35c4645e276f0b842c948f413d519138bd1674611f2d971be4062ee85c399e9b82fc58abbbb566947bf5a52989d8446ae8e0cf36148a70fe4db0715d5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc0b61b87b498ad6019500aff5fb8e4a1f22b63592b38976fbe3efd3b267ea253004c87f9d2f9ec5c89dbdbe18c4f7447d6478e07de8ecccd6647f9fc23877700	1633106007000000	1633710807000000	1696782807000000	1791390807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	306
\\xd9a641de64b710158e7c257f0ea7ebad06967693c32428d943f03a20bcf500f221c9dc49274dc22d49aa86bd9f3d2344c596a77a850e722844366792ba5ea9e5	\\x00800003d90aa3e03934f63aec37bb4eece2d4208aacd267e2afc361b50ff06f0a84898af793f90513d6377a527b085df4b47e48c3a23a7cc00c025cb4704e3a95a853b92d39e1becf742c5c6510cf31b4ccd088867b6d1431ab51c5fa858e0242c0573df25f4eba1ce7a6b78e63e7b0189f34f5b8a4316a79763f25c98741fa6064a977010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf944c90ace877c78d0f06b08bd043261386850409c5a043e189075812f4d2a0c48948a3794a823111b610255a6c239a2349d6ee8e6412a054bc69e721cc65107	1623434007000000	1624038807000000	1687110807000000	1781718807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	307
\\xd92eb06870c90bad57791a9f02964c40024dd46bf162b4f94b365787ef6600921c8160c3c22ccd5a8130212bb7973b9210412ed6a11757bda06ebbe6b64f4cea	\\x00800003a554a9ee781d560afa81c6d6eb8595f5084f4bf0d897a25ff6f534cafa510c77ff8e19228315a3f2d17e92d0ee01eb1cf5070c29e0651128b0e8d601f78067ffd83a6ead5b167153a874215de9533ca74742b7fbe30ec211fcfa98622e7d7c8d4499dec9d516bf4cccc0059a9e417cd062aadcb159acf0db0ce4b496258e420b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0fab129e83644482851e0d5fbfffd9fa1cfe198d9060b3dfa1b16f4c271adc05c02d21a386efb1041cccdf65356bdd7e13af54c8632eebe20c5c5901546a5f04	1638546507000000	1639151307000000	1702223307000000	1796831307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	308
\\xdad2a0d8812377a5af3388141653356d558ae00d5daaa0d9a9bbe60fe556a7bfa1a05f7402c4edfdbd7ac1172c9c002473e692255b0de6a5fdb1ab9ec4a1ba27	\\x00800003a196c374f234ad92f6b6df473892ce9a57f77f4246db964fb555e18c0c49097a52e572248d32c78846bf0f5caddd3178b98caceb55e2a2534431c6ebe85b1743457e8fb35e48c7fb4302ab765a733b07171834f5b130a88868d7b8e88f37065ebf1aa8ea965b1ac4151b75abb4ecac1b23e3d67283a0e7786fe1c7ad755b84ab010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9d896c4e218f9457e866a901ec19a33211fdef31376b5c6c6a1706958ad51b79ea9ec656611a42dd5e6ae15ce8008560238f09a653a5aac61d7a01c1b1a3240a	1636128507000000	1636733307000000	1699805307000000	1794413307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	309
\\xdd3a50260957fdbbd6a0a445f32d42b0ef0718833d8758520abe5356554571dea79c8c9f5f68c72063bfe100d0402809c2b0c5825207314eb0b1d4c750ed91c9	\\x00800003a134ca0edd685cee1d47522259edb7090308e3c56c3f6d161be02c6651bd0d103789918d9b66718cd7b2bb14c65b097d39474fbf15f079496b0ad2cc2495bacb71c7c1c15ed5d44e65cf621cf2dd11dd7bd89326b5a43658b3f38f8e22527d3c5f63f45cb3aa8804ae32885c8d5577413bd82891156e1ca39ad5d3ee8a04bcc9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd792ad3f059ebd97d575a6a2dcb788fcc404eaf0e06fdaea99275ed24f91eea7850aa034dfc3d65477425fbe2367e460fd0b01b6c4ef19cb3342ed71127c0c07	1634919507000000	1635524307000000	1698596307000000	1793204307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	310
\\xe18e2d66b9e45092e121761c77b9bbecce79ce3ee26e5a5a4cca9406a0ebb34b3217386b881815c06c7a61eb21576ed0e84108c82743b7b1b3aeb45b432b4142	\\x00800003ac7bcdbf169db162509cbe773c28ae1ffecc71c55a1c7e86db12f4129db4e283fba7e2ca7030e4c4f07306a200daa376354cf7b23e15d5db440cd10a4861a25a6a366d4c09559b412befcba94f03dc68d02adb03b82c8f6ef745220c2171967ee9eecbfa3383f00f8361628033af4ce08445e3fea4dfb151e943c90ffccf085f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xb14b2df8348989e3c7550c524c4891636f6b2b974e8ed27f6a322bc27c02183e81f94b4a33f0d80f6e78836309f211f81027319f9ec609109f793b8f3af2e202	1619807007000000	1620411807000000	1683483807000000	1778091807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	311
\\xe46ea3fc3951a64bc01b66cc4b6a02c172d248363670efc8555378cb0c43b33a4198d1d5b21b669cecf45019042ea59dfd38dcb7986d157b51bce61be6b235fa	\\x00800003cf9506260229503d75ecb02e388dcc043bc9089fc76e3da583bb8d83f9b54823b36d94d56948c58c665b773ec4c01df03685cb229733a40697569614d64920a6b015c3d6638ebd762c53a52d5b99c46635f440d8295a7692ceabb18efd89233598d4029200d349b7de915a7b86e4f4366e78b02d476e61d375e75bc23772aa3b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6ed10eefc863c5e5c84198d9753cbc4e98d5f0eb17a53666032e01f1f9288dda79ba4f3c7aa044ae52990b18862d2ddcdf59bac601c12003046563a1e462720b	1641569007000000	1642173807000000	1705245807000000	1799853807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	312
\\xe55a8276fed85cd919e72fc3b8b6d1beaee32ca36c1f18adca2377794f69c4c055c0c9afd1fc7e47ccc12b2d3b70c46bf74ceaa2b0e3376eecc8570cd23e5eae	\\x00800003b2e969cd32d07f9975e850e56372dd10648bf06e9a9d7ddf42169bffc74361b92f9d45d0f9fc092ce183a54419e1414434181fbd4509d01aa080c329bfc3ce42bc62c258c1de197b1af290af2bb7157767b8faee19ba458366e7e5984a0b446d22ed4b2776b577a6bb10079f32dd1f65014a29e88fb1bd95a6ec8723080e9cc9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xaa60fe6a3d00b575fbbab95cbcc618e60deac756263bed3a4c98154578d0ad8a3fb3aece67f93d6564d13c580cdbaf5c7e032caed1a63eb6fd8d8f597483a703	1616784507000000	1617389307000000	1680461307000000	1775069307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	313
\\xe686b68fd8038362ee4f164429ebc1dadf6518f46146b1c95d43f53e92621126c34e1d37318b1901101af9f15aa75802ada4b35ef3d8ce628eb3895ffbc86d76	\\x00800003e84fa2fcc6846b4f3fd28208a14f12baea719f0a349d835b2c7e8401e848090e171bcdace02707fc69e4a48b61c241a209e0ec33188220d6120de36bc7a96d6ee9e29824ced8674642b223c056fa4b518c0f38c08e93d9bff1f409064388ef29803af53ac277a71f2d97c987f64ece44f02ef5f799dd14e16b94d9f7b4607175010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2a4ec1ec4bf1a73da238ee5da35e594b24b569a650bd463b40bbaf4d27277051dddf921c202b79c9e9d382e45d7fb584823cba105a3327137fdc54d7ca78260c	1639755507000000	1640360307000000	1703432307000000	1798040307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	314
\\xe69aaccce3835263e9a1d3bbe4a912c0831a1c5d8d390cea58ef1ad60878eaa92569eb144a665461e47b7f429844bf00caed2f28151c8736ea147fb4098ff0dd	\\x00800003c551935b5e7de76f797f05912a42061c758055e8c982656fe6f97972ff3995168f25263e0a09d375399486e247e57a3e1bfd2e453eca5a00c6dc2780ddbdfead60d1f2d14efdf073eeb875a022b9ae46150b8bbe6a7730f5a1e28b313f6c0e720024fda5abf4e218b6e49fe78c041920a63f9b1ac1887d8c9d47436eae841d23010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa9b20750cd30a5ed643d71e420317ebd5d7dd5bd92aa8608aeb022d9492510a1ff2ce0d5f810e5a90f2e5abc3040695ef066f2741d84b1c970653c1324f2c508	1619202507000000	1619807307000000	1682879307000000	1777487307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	315
\\xe776c532838568965fa5ee0e46084828f7b8d810380de30a19762f58cf01d3791f75ae8274cf252d2a789ded4337d439267d0de3820868ac1bb18dc008188ecc	\\x00800003b8de105b35899381c3090bdcfc083d84ea09d235459efc52cc65087c10454bc89d4a1144a1aa0ecf5a72b298dfd9d2de9c4f7fa57e97b99a944f03bf15c413c258902ea8a0c1ab04534560e1a95f054022ef6413532d71b5635be8b438d1639b009fdf6a57eff3d113c7bca5d88043bc7781f33d9fcef436a5c06d045e20b9f1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x91f698f0db1306a4bf1f917b946640e5e25057b7ec580796fd8c39ef283caddfbcb4638e68b8f1454916095f60b76a07c9ff084b3c7d93f5ec177afec4bbc402	1627665507000000	1628270307000000	1691342307000000	1785950307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	316
\\xec4249ef57064fa67adee05edd1cb286300eb6422646158376fffedd9c29cc8b05613763eff70473377e51b7d02eb40d52b8511e7c4d97832245eee5f7c54ad7	\\x00800003a6f6431a1daf7ffb65e87f7f5f64302cacb5d2b7849f0f1eb96b193eae1e0b5dcf9aa72e53fae2973cd16288665581ae06a9d754b6429a0aa0f8fb515711cf63fb6ce6caf5bbac72022dcb85e62c05f0ed828d99a6e5709a3573eca5139f3792998f32978522c26d48ba72758a115fa935ce519df73df35215c95dd64b6f253f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x54388474278266c560522a0774a1b35fa5e218318902fe484ed6aaf3807f15d65e86c8f14f79c81ee38e9c17dd3e9aa95bacbbbb3e5f18a83fa392b09b3f2d04	1639755507000000	1640360307000000	1703432307000000	1798040307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	317
\\xf1527c996b53043e0e6d9176ef5787f51c484a3fea9b0f5982bdc2721a3bd920a85d65f0831c8c415cd075d1965bdaf4c7eb32012570d1d493c10827606dd24b	\\x00800003dd25fa5a1b5537bf1a65accd98127b2d4f0aac1679c91c6c7d7ef18f0b0bdcdd2c245e56d5cfabd1acd5b1237585d6bceddae153866ea6be21fa23ed05c9377ade6e47c6538b3701619c7ea35ae53fcc664db22566eda96218d17c4c3afa0c4ab5919b96996c6df9c0f0858787b2cc5da1450c33aa92eded5750d8bcadd68061010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa55898092962c1cfe085774cf80b556ba4fa15583f6e1c56fdebe4748c82048f58c96d5cd6645b1c06cb42553910662f623d772ee764be126968e94d1cff0504	1629479007000000	1630083807000000	1693155807000000	1787763807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	318
\\xf26699eb87355fd8cfdcac1d42ad0a0661e391473a22307a289314cede939a74aeeabb5ccbab51a010ab4d0c927a0309facfeae72d4bf0a03bada6b868cc23b7	\\x00800003c3a944c1846ceff9b396dc514f4a9504794fbc4cffc7285f81906aaa55dca850e17ce178a96660668014ee8cbdb9481f7fd43d4f68b00531153c145bb9e5468e79d09ed8862c7b26e1350fdd57fe1de2a830ba9955670ad15061b886561c6136e398ec59aaa219a91207243d6c712c5d0f9413e682aadc6b882e0747b750eb27010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1b9d801f312df953a255e377a17e075051014e877760d4c4c5a4d5028ae56d8c2c56945658b4c5c0573f7744a50bc47396c46cb15c6e62c9c60b620c39f1180d	1621016007000000	1621620807000000	1684692807000000	1779300807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	319
\\xf9ea8299e3c765283746dcdd8d3b020279397b165c0563e950fa88cd7c934056ab6366e6d4493dae6cf445009b528b6d4fece5abcadb1b58b89d2169fbd1f2a2	\\x00800003a9fca302976d639d645887f5ed8a447250cada31a7ac6b2d78af84551bba1102a4fb22ab72dc0d10bdf7950f3bcdeb52aa3073ede2e2da3004a5fb0997ee14ce5b312eaeed3c79602fa488a82f69e0c3e43b2b98105f8a994a9c99dee1983ce0642d35bd70e1300fc2af8845847780da5c3c5a7b0bd491193b059f2485dd31dd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2e0b2d8aeea5a403ee4a54169b40a51d15451c96f97a02c88bd5ce696e68cca66f43d7a0fbaa4b0d6aa1ee7ba4028196f2e4d58e7a7275c901cc258ed2b2f90c	1628874507000000	1629479307000000	1692551307000000	1787159307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	320
\\xfbdee5fd880bc73a129b906e652e05d026b7b892766d0c0bc329cd3b7d1f79f638fdd08f5c29594e8a9ac2793b33f01ee363dc33ab28c3c3dec9875d59575d5f	\\x00800003e35eaabe8931f99e96a1c4587de61f21a6ea3523f30225f3ee7a41deba11081f7096496ec499caf31d89cbbd6e95d141c6533b0deac0dfcc9b3a508b20d450573582c54172cb15ef65fbdf831700743c9bd688a7f9521ef203fa40daac45333f0f69ffdcc4fd0bd89a6c0a2c4cdc1e330bd02d1c9a767268ff463b608ef46bfb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6bb7fb27ab7c99e716373cd36c090da6f08817409bd06535a3efac819e5aeea1fb81ecf22f2b1a89cd3e0396fbf9dea1890db06a6c6ed3a36fbdb2940d991107	1633710507000000	1634315307000000	1697387307000000	1791995307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	321
\\xfc925bad594cc833eda947d71d3fa49ca505c8281dca02aea5f8cc3e8ab5204bd69d8deefe935155858ce1738edcbf402cc3ad7956728a5fe88834e56375f586	\\x00800003dc317d1f2ba79d7fed9786cbf25b331a1acb96852da78c0957661d9af36f1ac089d8ddf8625c2d70d721cb6abe76bfbc41c5383111a33a469e7f6779671f45f1cc4ec2563a55c110efd69dd996b481fc9f2efadc4811fb18bdb2199ed4bdacbc5ba8f481f25e33c015cbba019cc9b8a8b7bdab98e00ab6e84f32acaf9c9d84d1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7854d0784b50907eae59a8851566da61f4ec6644fc63f2117fedf351c6de66a6a531c2bddb905a83ddab857dfc4b66d5c45b64f080f4b911d2b947ddb877c407	1636733007000000	1637337807000000	1700409807000000	1795017807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	322
\\xff9e8cc3f0b74632fc81b5ff4a75f8cd850ce247ddb538f3d4dd2f5e51ee1c7f78d1863043f93f2e8b112f32bfa45b035660602821e254530f6a997a28014739	\\x00800003beb62e55a42478f3a6030d43b35787c7079cca69b43d2dbb73522712c9a65c6a5c2c3541d4743c0cf4a420ce2d101be32783bd3e68aa75278d9f8316f0d47c5b7bc1c5557a692f0bc4a6ae22371524058b0dd04361822ff648f9f34827a6d397b42b5ba77a37da9df92ae86e2d713a0b725d186d05c98983b0fffab31ec4bb71010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x47af08b3ba813fff46fe191208d63af1adb5724d92f2e58e34f85cdeeb3089c662ebbf1bff19a66f7eca1acc2bcbac2aa06a41e00273cdb756e602785b9c9d0f	1630688007000000	1631292807000000	1694364807000000	1788972807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	323
\\x008f163e9df342a6916c6acd0469f6216971920c247bc576ef0b3fb23ec5f01961cafd260c127d227dcbf47f75fc65fc984920a5ef55dd17d8fbf964216e5213	\\x00800003ac0590f4b71b0eba16ad674f274266426948a970a888e16f471ddc79a3d112086532164c39500a57ede9fd2e5aa62ae95d590b10e3ab628c03e38917741686026f6072b4677129d9a54c9b0821417bfbf032edb1ab635abb1de634dc92969d8e1d6a34250b9769d44b14db0d8ab80aa6f9692c8e5bbeec7e2acddd10bdac667f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x886c72fe65dc13f866cd5db14d3b90137de7dba997aa86c97bc792c65c6271054846f24db087ba87d781ab382d10a198cb991e94c929b2d47ea818318bee710d	1639151007000000	1639755807000000	1702827807000000	1797435807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	324
\\x013bc4929884c6b30c84d69b8b9ae22b7171fbfdc1c4c671cf7a8f2cdc40007f2b470c3fbf6270dbd1073dcf576ede62200ecb428feab57f2fad9f31287d1980	\\x00800003b3982979366f7f5ff699512f2e9a67e090b9bc7ab8413b10d6f792e6f86a89070f24398b7165b2eb765e8665d332d4ea63fbce2c47c0e98719bca06e064f06860451d53ee185594b72ce6e74eb9483a1a32424d5ca0e79a79a99f45664da5f5656e5361eb6a6247abff4c1941a89a068d07bf46a26c17f360ac9c1a8b0e71a43010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1637ee743c47addbeb6bd89fe2f90ae7d5cca2b36ca8cdecc18d704d87a869f814bfaa64bf08651ebc69233ed6f81c905cf65b721f6af19cb3a064c883147106	1633106007000000	1633710807000000	1696782807000000	1791390807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	325
\\x080fb2b8d614f72e7e82a591bfa5c23252a0dea230d5ca58c52357b4985e2a514524dc7ee16d4924780f0a4f3b5b9c244b6d0a430ef3c328d8bcd48977eeeb08	\\x00800003d57471d2232e1f4f6cb7859eee310eccfc7aacaf1fed8936c37487cd67cb7108934d69bb1152931304a8e0a87413cc76a1a28bb34709492a1316d2160c8605d2ee1f1231d509aae5854c137d836e40e275a87fe6468bdd6b169e4dd243a994a62e5f1c4ade359de94ecf9c20757e866b077e4fdef978f6755aea6e2c0d231279010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x94fe951e9f12e2c31d073f629a805cc6fbfd84fe15e68d58ccb7e0ea64c1a71c6457c873ad153a85bcdd3c381c30fee8c0e0bde71f156d2448cba29f1adf8105	1623434007000000	1624038807000000	1687110807000000	1781718807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	326
\\x0cc70cf98168e873b2e67932be57648dc1e26d76e998262e6c0cc9b551c5f68d2dcd048364ab78f81f95a4b7f43f89556e95ea32e554a25a1c80d277a0870c6d	\\x00800003cc6e01da8a453decbad2ed6836aa21e04bcca21e2dcbd2191be5509dadaca716ca1c092fb570eb25279e89070399db83e471099c71ebc537fffc2ccd81adc5800e4f47f6fc06552a43cde729f0ebdfb195641384ddd08628a34eca2d7c2cd513aee7e9e25a813792b0068e7fad899cd899b2b98986947c1e548cc50d4d5d94b5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf18322113bf4f8971882134415a6b803b52b94682e798750b64986b63566c992da447c3b1d8143f99d681ea002c871a47f9e2b3085c30e1ee10382cc72278804	1637942007000000	1638546807000000	1701618807000000	1796226807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	327
\\x0fd72bd2a7d860be0d9c17e67aa3295994291103e9a5b86879d6ef238fa36e612c8b2510f396f57e2869f15c183dd93b802d15ded38b73f962bce8d203382abb	\\x00800003a931b243158a30c8bb9a291cbe56903d71b2915cc7832ea83d2be7e1340b6f381c56ea46e98900329d3a02afb9267adb4696c7b4149e079122e3a5e7ca09cb37f101543c1a61385f0448d83379bc100b1ad94b7e27d3bd711412bbdaed15912f7a73e4c66a40952a097997eb66d7eb0c35e9175401437b09dfab884127385c5d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5f0814f6e99ea3258496e4653505745d59328ba4d3f72a26aa9030e5d611199818369a764716173927bc3e668888fafbfdf04a1779967092f016486c3792c805	1634919507000000	1635524307000000	1698596307000000	1793204307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	328
\\x16b7ed94bd3a3867d08cbf79e51c99f9d0bd931a2bc671d0e16e2b8ded4576ba92689a007c5dbac4456e3bff24221023ac8fa4d0020639db07e95698fb5c9609	\\x00800003d208e321fc19cbdc26975347bd4c4f7c96920753c716fb08f6138dd36f298cd107fda9fecc8f39204b15f3feb9f02145817fc381b8c78f84bf48fe1c8bd05d4c4b54c15c280e152d004ad6b2c31683a8b97c42b68c0b4a870408fc98f915b41b4fedec1760262846a498c7926f28c46f820b22a79ca933b08197efede36d1cf7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x92bc1313777ef5448712afb576769b2e1413b3bb77fae1f97077e586faaab1e041853c1a27344bb3d8af183e094c30a1e2289d1f7356cefcee6068672d881203	1627061007000000	1627665807000000	1690737807000000	1785345807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	329
\\x206fd3063260b61eadaf0ae56f3c8d42bd1cfe1755876a0c35a9d9186b159f96aac5e38cf4d4fa2e6458aa07957fef62d9e0a8419f71ce99495d6ddabaa17058	\\x00800003c55b7604fe18755250ae729ed0d3fff3c108f87478f24dbffc19e03006256f50c2f6b782cef081f2fe942960cd2de1a592da5bbaa1e53cc67afa3c872d62aafe4e6b4ac4408d4577836053c29ea6d757cd06d990a31239697ff6fe919d33712e7eafb09853d21598420b196a470bec573f784a6b1a9a0bc9ed4265dfd452f3b1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc42ad463a2a992385c20535c138f094373342b1c05c59b4091fee74b97311d07c489e950bfb8bcc441ad2b128e7c16acc44b59846d24b591ebca887b5b56e806	1624643007000000	1625247807000000	1688319807000000	1782927807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	330
\\x2003c0272c681ee34738c252798f364409bbee8cd4a5f82d736bba8e750c6214c95329df65f5a32b0e074ba9b370727415c3b9afe6bf75ccf3c69ce13d4524d3	\\x00800003b5250dae18d3c406c9a4c4467194d793bd82b417a1657cca45ad6667ef505826c084e99f71de31ad01983e3705e853d516656b086971eb170d22c5323ae33d14d3246e9cbf470c720ab7b8b0e13027126b1ae4637faab2706f22941f8fedc0696b25087d8f563ddbce877f9f5076d1c466219f84a691dc1f1c3ad68bdd187f95010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6d03a0ac19b6434bc90a51b0acd46e7d3a9f431bfa95ba4c5950a66ac982ba76535d1aea201870d8fa50febbc2af036d04c5a3b4e63c09bd203462148e379008	1616784507000000	1617389307000000	1680461307000000	1775069307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	331
\\x204f0e91f479d63cf79af3e07e6454c55490f0f98001f7783dc2ee0db3fe841b5bd892a45b4b12c8e3f21431e6e07d87928ff172a372069f629d5964bb5dbac3	\\x00800003c7b77e093ca2790f976b9a90906a7deefc0b3f9978a555e9be6a036e71af0afcac97275ca6c14238c1a9bb5b000efdec497f327df8ce9f276246a1402af01a4cf40c6f38046704e87817dcad7a5ec232c0b4b7445d0e2c8fc203c2b8296a353b072e8b36b49ee4308e8a2368c5eda750be2debe0eb8e7bf222d224bd38a637af010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0bdbeee7b3cdde1ad357a729e6a269c1763cc099751afd05f499560310b64dbdc96a12d5e1176a8d6547f8389f4463273cae7475b3cf595b5e4d61928ad1860c	1640360007000000	1640964807000000	1704036807000000	1798644807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	332
\\x21cb88544cd64c165788e09f1712bddcb20c980157c9acc1930764ec68ca0ba5fc9d8ef31cb563f5cf66e69e7d500e47c2a77263d99b63e4d60b444a9d7b1f5e	\\x00800003a19d417a6ef1002b39d696c281fa4c3d77898bb45402ecb13349b2f237017ac6b4701ad847cd25ab57cf0619240ad8de1bd59c873bb42b5344812f8fb04b6599c08c0210d7770fafdd1675f2d126730e2b1aeff4ffb85140c71819995421b4fd420a425d104f2f80fffae6bb02bbab03246c0df38a4e120284e99e5b3108f273010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xaab1bc277a361591965b4a046540da248f3d70258a6fe41684865011195ef0fad9c74dde6ce6a3bc97805ae4e244f6c51e1251c2968ca768989373c3bcfffa0d	1619807007000000	1620411807000000	1683483807000000	1778091807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	333
\\x25c3469abb3d753a6bbaaf5c1f1b5ab9b865fa9b9a86c72de36e9756e1d6d8c77e1c8ab1bd6787199dbb440d7d33b960095340084a4afb722d1b65af90d204b5	\\x00800003c0e30919f4af9262c8f8cd3fab51343f26b5da042eaa2b8588ad9ea94e155deabcf772b76650620a4296a64a9f968541e22a4b3e4bf395b91e9101fddeff248e19569603dd8a1bacb458b60dc819221a0773817632a05e89a631c8dee45fba693754db9e2ccf6550ae5453a2b5844b90db71d387ca02ad00c7a819a4cdc5c525010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0508eb88aa91dc5b876c8e94e902bf84fa7a48b92069c08654f408ae23f34d96dbb870bb533a847ccba28faa4752018ec4d28200f67324e42d40f07f8f42920e	1611344007000000	1611948807000000	1675020807000000	1769628807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	334
\\x2adfb3969decc9fdc1d3b115624ab1692e3e08abe913c5357ec2556cdf1c1158ab96078e8d70fdb33f633cd5c0eb9c9733a7ea15389c3fb9ea0e5c7fe89ec193	\\x00800003be35664bf7833fb642176c250db90161e869e2026d009c1f82cf134c4484f7293482731d4712aa93ee01efc52fbb437459b7a54486e9673431584efecfd28edd63b1ebf1fcc64fcc6cb3f983cfefc586c249aae8fd59bc8b9600617538481b68115228bfdd3cfbc3826ebe86ff09605fcc73381432699a2b001e37dce84dd6e7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xed6d764ba0cf2c3e453f024e34a83b5cccbebb544b6414108952b2e080a2938191705a1bfafafa833b46df85cc960528ff1d9aa25cffcd97cceb4a01a480880a	1628270007000000	1628874807000000	1691946807000000	1786554807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	335
\\x2b6f0f464a316181214d0bdf7329eba9460b8eda1affd4e9fd13a3ad653f1af8279b8efe5908ac5d1ce5b5f0edc9186cfe93246d4d8317b9f39888e6f36e941e	\\x00800003c60c292e41c019557bea31a1447832d9f0536fdaf876bb162ea7e6054b85a15467954681a2db117c34c7ceb953aa682570290543eb190c54da8a4aa2e4a6d09faa2e9af71d3f8980d158ca5571f3a2c9add62586ecc03fb7988dfec288023ae4c052817316fb91ce804f2a0f7c7bd4acaa9b004c5f2496bea1d9972626c2171f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x81bac49226fe577979b4a5a1339c71c7bcb3bf83bec44bd8ec1d0231674279402ed69299f473119e4b9c845fbbe5ce552c6682f9c54b76f39cb76ff7f095c60f	1618598007000000	1619202807000000	1682274807000000	1776882807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	336
\\x2c53675db09ee93898b766b1f894e70e871bba808bb8493dd0b240e603ecee254423a55e6301cfa3a81af2d1e0c24be7dd9b8cf833d5e5a91e1f9896a5a181d3	\\x00800003b289bb6935e93ab69a6baa62b52115213c838832abd0cc4db20d166dd794b015fb16c528bb1aebdde3559742066e88dc2d0f8fe9a3efcbdd914173e854c7e754771559f6c17664ec96158ba68850257e2720327ae51572c1a5e11f8a8b42e4ed613a4635f16a6746b20fc0b32b4d0cb4cbdfa60d41a0fd8612060cd6070cabb3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3c9063380b9adec0df6e6c5878172c36dcb4e608afbe6f2ed6e928653161e4328b37bb22e254f5288647b3baf9faa8d2ce010475b01c6778f2d84b6911a8d10f	1631897007000000	1632501807000000	1695573807000000	1790181807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	337
\\x2e0b99b9d6be57cbe895577ca2d6ebbae7d95a94bef9aa5bad0e334d156debd196c375b761c0047a84841638c0a35162601add7ea2f5475c28c31f1d78996c1f	\\x00800003be0ffd14614b8090fc4d1a1772d93393534297ca45ec369693a861ff046b016bb2a7bf4de3c3a5d5e105dc82e3e7fbcecd1f3d906b97052cf3fcaaafa886b05c7f3f989d75a3a125c52e3e7b618e009c6f341d5f35ade80fd08cb649a0b4a54206d2bb361d2206cbc0396a357b239a16e73e97091bc16f510276c7fefd93539b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd5dd10989f8625faeadff3f76f8949ef9312ed784b309e889d420c1ec410d0c40848aab9e9af38f8e2c523177a637aaf3b868b27bd6ecde8961ef316de40900d	1611948507000000	1612553307000000	1675625307000000	1770233307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	338
\\x2e3fff21fb32b50a97832ec4dbe3e147a74d53326e49691c13b7922c2fb8398daa8a18741572357643f4c90b75f65cff8a85e2780b81211cd1690e097c7aeb83	\\x00800003ce981bd809c2d2da240b2df8803019f4306d4bbe02c617343541900b6a3cf813707175f92e6e9c5ca14bc4b41af9b66ca31879ccdc26ff5dec5b8cc7ef71c6978b45d73404c3795fb1259b3f71889e3ca7b46ae85e2dc2c2e565eeeab9f1209e586c56755c05d3bde5ca8536265cba2d625724184ef6a784a42024397eb363d7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf386ebd2467891a0a81e3ec2b9383cd8188099613c258d33c7401e25cca8d27b02b424cda86beb34337c559a625ffe98b853931d7e10a573eb5eff0066a6d109	1617993507000000	1618598307000000	1681670307000000	1776278307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	339
\\x2f4f844c62ddcacbc1a978e8728c8385339add595785169cc33529ecc9c7b82c16916f0fe2c6e36bd9d0da4976ef37e5b6ef27b1d7df832de39956a98ab501f9	\\x00800003c8199407965438fff83dc89ffe775292ae3fea14592d8c847c4b02d8faa1f2101c862bea63105dfa4ff55c05fa1dd7c406583ec23bdb91872f180cef91e8e952c61924d93054f98a0bfd4214982586de09485641423dc52250020942a00878125adb155e5ee0b2343cd9da8c04559d4459d90eaa9a0f1ca2dc1ec3fcb2ad9fd7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2165db33a86a778d244d4e9743c4bd67493a1ac560fbfff1d670aa5d71bf9073d6a40fd9ec97bc333becd853e2872eab4e57f520b8ee40ed769a7b864833830a	1628270007000000	1628874807000000	1691946807000000	1786554807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	340
\\x322fad67023870e166b778bd8096915722f596a3c9630a47455f3ae535bda3fc21814664a515d774e54874f3ea1aad15b2bcb53ce0d3413f15f544a2fd3f04de	\\x00800003e7e55eddda2d5e00726345b01e6ef738b715e244e074fd68a381a86376535bef093c9480a6c5f0b2c9ea1eb3fa6da6bd769a7ab3e9c6fe7945c6a9153840221241e916255d238749744ca84dca154528dffdbc126ed8d9f463430e233b6d54b032baf7e97d3e004a18c5535353a5bafe2f136688d1eaf3a75fcbb1a495e570f7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1eb786615bf333a7e1d8f0be5c669eb128f683ecc1f9523c34ec0ffd30cc949569b7db5e14bd61bb9dedf0b74545b3754d3f6acbb7d5b36b16fa5670e596d80a	1619807007000000	1620411807000000	1683483807000000	1778091807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	341
\\x35d7769962c7bcc641a02490a9482f201ba67ccfaf8e74a10a53227c306cbb53f91537402114b067fdc3f7f58285d62b6186bea34ed1e2150003edd3f69f5957	\\x00800003a798fe2631611f278e15aa9f634cd103fb610d0fddfb7471e917455f468b41533c18d4774be9f793f3325d12f010e684af943cf1a0c3464103458bd92537fecebd5e0d2e09a6a33898ad81f5ec9ca8a64662c871c6b707bc514b83e6c54169e8491d0608c238b585999782e1d7165a654c515144efcb39e73a194336adc8ed95010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x82c20746e96fe3d4c3d1576658546014565590b6973c48e94b828e830af70e85d56a3cbfbac8cd1088356666de8cd71c81198bc19e27411b14c13314e06a5307	1615575507000000	1616180307000000	1679252307000000	1773860307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	342
\\x36e76a167e449a807a117fa0dd03efaf002f7bc9418304212f777cd4ed6117deaa8940ff45b8fe404d114f735270971e47109278579884fcf08ce5deb325b09e	\\x00800003a7e0cd3ebdf9ed74df372e3eb1d89d5d86d57982a7780cfc1dc90062a96077876e4d9c04d48e03572372c3b7e784b15678587a692ea83b53ad56b2a5ba732a115a76971b0e14e2c5c61efa778083577dfa024df61307fad57d20efdecc3172a519288fff02e70e0693e10f26033a83b64b2c2c97217683fc076ff63312e792b1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1357d8f004db17cb04d1dcb6ed150fd12a79a4626edd59a2ab0c9199997f85f4a0447a2b26e2ff6f53b9da343328806efc052c97fb23a4222714dceccffc2105	1620411507000000	1621016307000000	1684088307000000	1778696307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	343
\\x37775a375f1abf13c19343ab50edf224e5567d5eb0cb4ac506102d81fcde9ec327131c0ef77d52cc70054cdb4f52612a7b870077ee0b7e37f6fb95273bdc1a1a	\\x00800003c165af27944ed2089f32b3e976355f19cfa35fc0417ac0f1a480da94bee72e8a8ca5238ef1195157e06566b4c3b3151f3f2b6b8ff75a0a182efeb08ac9addce35d720eb341346bd32b4424f22e078955ee586d03108f9e43f53603f31761be6d2b1d8d174c331082f39bcbf0049a669505e79dfa051b727f36a220d55bbe51b5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd2a84d2b56b62dd78cbd1bd9d669200fed600c92c1361953b4fe3c63accd9363ac16185814971e59ab2f9197a16de64d27c37ab423b5a639f647a557976af901	1617389007000000	1617993807000000	1681065807000000	1775673807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	344
\\x3e674dd2317d0e80dc626e71a9e5af103253b956967990d2c8f5bd0c0930cce16dcf430e23bc56d33f0f5979885c59478b9436b24d0c2c76bada6176d1f4d010	\\x00800003c32ad4a37a0dba6af5a31e1dff7d677aac14f0bfa2c82380ff8694ad7afe1b9ec20754c6b06357ec197feae0c423040a9a39b16b942a436b1b32b1946e87a7300fca39a4fe4a0d59dc668b97f92e79dd80c7be02554ae5fe70f6a1f4a7e883e009ddcb492bae6ab5ca1f3a8603ea161f5e72ba9a8a821d569da4514233af191b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5b5943cd5ebf8a99906df88640cb5b39e607f6019b829b81689ced1d155851e7bbd1f543015c2e08ec902f7444a90cd7094e2009d0e83fa1e7fe179bd054f20d	1626456507000000	1627061307000000	1690133307000000	1784741307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	345
\\x3ec7f217f3159e690c7b846264f1d3e10f44a0b7a91752de7f43bee1a85d4e6da47da0d33bd04d8717ceab58709daddc8052fc9cbc00fc56124b0815b3954e85	\\x00800003af14285fe569830ac67fdb59c9c461f3ef3de89aa2e56f7a68652adc01c82434d7df2690988212a5f5ac056340b0c12f5eeaa7344914d31aaa8c7dd9a8abd6815625f2df2309fa64d9daac93c2e306e59f9d27efdb1b09b381fe184662cd6e472ae64fbac291397376b0e5dcb5d4b9f33ecf7db42ba16c3f70c59549cebddc75010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x56dee579d71fa4064706429474227385ca9ba081a12c5d97f174cb6661d88b93ca56e8a01362b6674b577dfdc2dcf875bc1f6bb1fee83a025947ad7c01bc4b03	1629479007000000	1630083807000000	1693155807000000	1787763807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	346
\\x3f9b60582c0bc7399887f2773eeaa916a7e211ee7992d49553516bd1ed33d48107546abe3a40cad77fbc5a8d245f08f45666c88267ad4c004344e9c7e85762ae	\\x00800003ae0c5856ab8e30337aacf50994dc028a204b519653779e255bbc91cbcf86c2ba5d4a3c58b0b3bc2dc241b61a23b7a8915f5100a85e638895b61e2e50ab6e3e8b28eda1f3da983bf3ce322bceee4be33fcee503b28b1aa1f48d4ccea0c831c124779e8766d66e9423ecb1f6ceccb7872785c17fb2e2524a1da1783f88e2884c8b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1e2d3eb96c90274e1e3a4c957ba94783664b67b3f8a971a3928618a43f19b96155c37fe027045b09ab587ea70672bcd8e7d701d706e07bff92f883053ee17409	1639151007000000	1639755807000000	1702827807000000	1797435807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	347
\\x40cbcba4f230846968e1ccee8bda279f38feb1b8846a011d44c9617f9cc242b233ffc87a84c6c405c74a3ad1163ffe3995d2cd99913974b20726b840b19fca97	\\x00800003ba84633fe8f9f454b96a468edbec325c05dd20e4ddd51e6d98b7edb142b1d84147f9a820e12e517921f975e637156b19648cd17a6fdba2f1b6cdca2a0e21b51b2f31d60ca54e98f181117b1b5720d92e09fdbab3e6d14d7f25d4deb9d04c4a7d2f9034584819efce0e36ab128ef5a502b1eb23184c9a2fe4f8383b3b7426d60b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa7e7569085278a05d762044151b853113edc3627071d99e8d253ea2a693445a27c7f000509cadb9ed892d6ecbf83289f9ae63282c8acc60efea635ef26be2001	1613157507000000	1613762307000000	1676834307000000	1771442307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	348
\\x41278591df7481f920975d525b730429eb111cd9a47192bf2d8560f59668f2e6efd477102ad337e7e55108cf7c7df7fc544774637921a5808a01a5704cc220bd	\\x00800003f520a13496aa61d1c942cd6f086a552a020c0f0616ae100f51e4cdc8648b44e5ec8d647a83ff6091d9eb24dafe038d08c56836cd8ffcc6110f48c33fe4495e2f734587fbcf4dad86942c7db154d57c5200ea1484865e5882e86b1834d3729d43d41a78b2fceeb305382e7c80ad2b1292a97662538cb3205bfa6a8c8f7ee0a1e5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x01f4e534e089f95269ab72233c5c02e1b5a42183b958c300b430ff87726251d80c19d179e715e62c268b4f3c8ec69565f411fe0209fb8dc3817ea9dca405dd03	1636733007000000	1637337807000000	1700409807000000	1795017807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	349
\\x42c3ffbaf3be5d595cd423d1ec3e5cab078dac297b5df0a836c4f822a8d351198bec1531e71fd1421d284d0a83b4f145789e28b070740ffab18d709c749a4e52	\\x00800003c24f31a39a48be57b1053132cd1accc216bbdecd322d0fac9adf08e32be9e52e7fc0540e162561a05f6fb8598707bcab4c33c9c3ec4882ba514c1aa88fd61120d64083ef89f1daed0f819cede49d19e288b641e09a7f711a6213650d236182805407ad5caff6932d58a85020c920a51052e5618157a474942363313566c98191010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x86bfbbf8e11bfb242edc94b80110d2db7ed721567479cd975f224f1486ec53f2a48effd2956c0c2a7dbd7b5bc5ff0aedfc879b01d04e6a98502a2d2b187bbb0b	1613762007000000	1614366807000000	1677438807000000	1772046807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	350
\\x43a7fa63396b625e80d61f2c448f5d1a2f7bce40fc85478b3943f8cb60c3df0fb758a1f3714ef57df988e8e80da1cc51dc18c6f61300cd485c480758cc590c74	\\x00800003af9bef78c9c36f30596fa584ef8ce328f43c34519585b2e04fb843d0f908cf1e219092bcf0f2f00ceff5a45251752b3bcdf325e02c5ef017bf925e195dfc314f6b49591c65e8144dd94c293c04c91adb5f01fade3f8b1f1d5b6fee591481f819a8916ef0aa6d7c81ad72c67b4fc1c08130cb11f289cf33eb189f5fee193dd603010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x02f358c49c31810bbb75998e9ce71a0dd721ffbdf141563d21f6a366a7c365e231a0a3486c2932526f98f93dfe7cf77edee9485b36299230e9487d76d04b4c04	1611948507000000	1612553307000000	1675625307000000	1770233307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	351
\\x490329c83c3dd1ef89f78ce491bbb9cd6736a7494e60b508f4c134fbff221f188bf5d2e2816ad0ddc32796879b798ec754eca598460c3e8f0a8a1f1c499b5c7e	\\x00800003c03b9e662234b7abc7b41572908eaf64eb6f546ce129cee1ebd6cc2507b028d7f2f890e0ce593789ef5b203290a06b259aed2062c6b3640efdb11056e89b93f5924517f27be2b780a2377e72455fc256121437ecee06f3d5e6ec0b17663b9ced89dcfa117c31f3e95033f02f025673b9fab2d4038e96d389a187ff39879dd917010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x12cd5757101714a4b5728ce71c75239a7ee1ac1249e2496643b5a1dd7efd84ae8dcd8e3f284a052e6d16f866fc8dbdc0d2b3acad45c095fb91ef86ed32ba3d08	1621620507000000	1622225307000000	1685297307000000	1779905307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	352
\\x595753de42437371b4c60130fb56dee21f6340f33848c57b9a54d1f109e3ba15e301408f67fcc085f44ed22a940efb1cc65e356dd5c0538ee4850ff3c582028e	\\x00800003df1d788bee927a085241435f065fb8437497c8efc9e2f490a10d71f5deda27cf3aa74dc52cf44a6cc44041508038a57eb031c6b9f23d8d1ff54704128357c294b85d56ff2db8ac25161318f51a7b22a2cce2ed57e93a2b9421b556ff7ae31c959924d07d5cbd35040db937a616d5e4e94aa114ad1d62c0a8ce346459ddd8c4d5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x4476f0ffb258560a9e865a393b8a89e3d8dea113739fadbda8cc6cbda54f0fec2e60125544148bc557c83a7b79fd4acccc09900249ca5bc4b0c170623bfd5e0b	1616180007000000	1616784807000000	1679856807000000	1774464807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	353
\\x5b0346800255286c9fe24378214805939eef330c0fdd2689abd07afdf872a488d1ffa7ac2b21dc4358c1223b374dd579ede97a1a4182a4dc5982f54b530feac0	\\x00800003e7f9d60439f474fa43893ff2b3aef9292db15b5cec603ab9ccb50441730031539eee5df8f46c9a649587c1893b82a7e7e5d00e3f331c553514f127b5778c65effc3a9767c49e65636c597aea34d8c760ef28d0d6d916ed603f872c1ac9d3b97c2ac7229573983d555122fb3a5d8f729758eb11f67e72973742ff466d9fa777af010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xeae218d8650c00c3ce03d5d997303542e454854adb2df37b5b803835889509c9ac68d9b2eda2da2a7f3d377bcd62c209d1c5aa4baf9e673ad1a48378903e9a0e	1626456507000000	1627061307000000	1690133307000000	1784741307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	354
\\x5dc360b629a4decfda75b9a0ce3c05b731b03204fa9427b90124d1b0a1d512b0191f86f317b387baf402dfc69e007bcd473b603b2fa99510f322ac96be49819b	\\x00800003d6170154056e8812bde51811679b1bac71b1cf3b13efbcc5ba24117cd5e4ec1ba7cb08d5f2728d166bf53fb45288d8c82a39e2a29a5d4c246c1edc19384b6ed897e7acb51de4a3079c6f6d42d0a251a0f9d2e62c855ccca5e749514db5011d6ef15fa64ac2064ba4a39ae264911e7fddbc5e137d3a38aba67f76b6c451545b5d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe198a60d9ca091d0a3addc244dbe20162120497329d248fe9b41baad0335dfb18b6c75d79940c07e72337cc23af7cf27a021bdc1fb6da827ee586af587bf0d08	1640964507000000	1641569307000000	1704641307000000	1799249307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	355
\\x5d67f218de79642ea0db88622b14711e4ac02e128d54254266f97c5a1a799cab501df9e225c2e18fa85459ae669435adc1daaeed7079a09f400923750a3cfa77	\\x00800003c2d3d9b35fde4929293e8cd428d25fb01672589c231343b72ab07dd002f780ba06cf46120d592aa6151e2c790fbdd418c5cd8c5e4bde3ad31ae85585627270044d8f28a4389b5a183745951e375202aa1d3872b57b5393e56e736324015347fdbe930050f60ca15621ea308f3d46b47e750c48afec5ac14e146931b6dd574f6f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x03535d21e7b29f22cde698f8234e0d7c863f4ebf9556f63fbb86e01ea175f6460df17e1d942dbefdc44a3aac48b02f40e163fb5013d54c7677f30e7cfa785807	1630688007000000	1631292807000000	1694364807000000	1788972807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	356
\\x5edbdba10f0b2f46b415bb30e8bc41d33e0607b48060f195982af7ec14afb78fb47066825bdbf437081aee1e8265f2bdee3993c17d9f4801756a8aeb513571cc	\\x00800003b04472d86593fe2ce04e437e1f97f6b481a07a5c39baf7e2c5e366f9366cc9b4caa488bbe3629c14d1a0187a267cddb11132913f3c630bddef7db2b057d20e14fa3fa51e42444d01a55ca08996c58602b16316f8f15f07e1cbd20021e2143b4c57ad1718ec1122079809eb1c2ce2a2fcdb82ee8b1f5857b16f36ad1b3830e0cf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8e6a9eea2a1592125c13fbb459974e2272574ab019eae10d870de296481da1f82af1ddf3c8ede9082ae05db0eb1cfef8e58e4fc421d3ffc0fef8d78375e94605	1618598007000000	1619202807000000	1682274807000000	1776882807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	357
\\x601b9250319baf448fcc162070d414617c30493a997333d22222c8b6203b04019df31dd2feae97e185ea94e39b6453596e38226f2c68c4e7e36c6ef96714626c	\\x00800003ab13be6f6a46d0e2515ad3572612567ccc7122f76979dc27e94a1138f1f4aa60184760d0b8f042bc4b1f9129adefd924a5267283249a97c3b7b70ba45b2749cd2fe07ccf35580e9a5e1d1d8987e4c04ab97c9c625b1a112c2c2e66dfc3012ee1e6426454bd14f0678bc84fc0f38d87d1e6b29b492668075b08ba1de7feaa6e3d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8f6ad1059f5b504c8065e21a362faef720d0618dba26d5029d924746b6a02a15c1a72e41192577b2dc8ed8362a926808126645e9b0276ce698d062acd411e003	1624038507000000	1624643307000000	1687715307000000	1782323307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	358
\\x60abe19a10992201e8549449557dde68043c4e4f11571adcb0ba85e14883574c4ed3b0ffdfda7a116731ff6c7455dd8ba80088f4c4ea854f8cded40251ef477f	\\x00800003be5a0510250faa8f31e5406c26c0d4d73c75a6014df3ee27879ac8794981ba36c1c40871914f29f4f87c31732046000596ced90b71d45b4962889c9d10b84af220b2cc1e2700ae2229583a68700cc8fe849a1064ee9e1dc8c51de646634fc4633461367720bfc04d18de23e20152d6f540e7e6822897dd2a1a756f9e9bcf2b5d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8b9cf96b3eca240673f1bcc815f3f6c6247abab51b6bedd4316047067d7fd92ff284c7caa011b2b86f301610f6a47a410a259c69a3a93d89915d802f2d28a801	1634315007000000	1634919807000000	1697991807000000	1792599807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	359
\\x62d33c51a477ddceae9f05b4ec062f131c1e4b737826e392f3b7d1f82ec9988acad58f4eb16cdce41a23a9608655e77fa4635b4202e2d1344915dd6044c721d2	\\x00800003b2d65be732185498408d970f28fdaf9c729b16eea981897055c167df49bd570c23243e7f1ebcc8c79a3b13987a5bcf429e173cc8b3d24403854b8db95a1e6e1c1808857409dd404807bc7955ba896f46729febbb41b941c9f4c8e693ac72334b6413ca9a6d48eb94de0bb04f4d161731da9ad13217d4e207741efd9bd0c4e937010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf740b063fd15bfbe4229a8012b5a9259ba341a149d6af7693c2fb4b9b301d49e36fdbaf966a22b70b59caeae941c1d5f0f32071116f43b5f13ede85f5d34b303	1614366507000000	1614971307000000	1678043307000000	1772651307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	360
\\x63e7f031d09676241646b177adfc4bedc95258c93ce9bc29cff20227a5f2f9d27eccf9f6b16468f89145e8b208de9868b4973cd45af6a86c6e2c897ad83c6406	\\x00800003c363d5329027cc50a1c6f27479ca1604f1779ab88a2209c30bb69f2656d4a8f9fe9d39c03e00dd9ea0e1a652ae6ccc73c4f59b2f69825ce3936cbf9de05b3e5e8e6f8773dfa71cf7fec8b9d80e220db3319f00f2930631d6b900297104b2a5435f7f177e74f46384568130f6f6665a25d26178d4c211375a689d1a486c1fbeb5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xba68695b6dc575615267035f9358bb8cfb032757f4c0a5c5dbedfa53dccbdc0996df928d3b50d20dad292c37001e9b8e94f6de09f4dd41be4bfb3ee09ebc9d06	1619807007000000	1620411807000000	1683483807000000	1778091807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	361
\\x63dfbcdbf1d478d01f062a95b0779a75667d5b5f8a39272974689ac1099842d6b5b84c235a4445bc821b67ca1aeca88c1ea00cf5f1d6cb2a7bbc2d92fdd5f796	\\x00800003c0036a9bfdb845678e401e1cdd8d80ee6c95f600fcdf2fd2a8b5ed44faf95549c9daa2d6354ba9dae3c15b0e64c01bca6359c0715dd3d5e21ec721e14c0bbc513e375e38a4666906fefc51f7678af404676670ed80a0f05c0d45dc44659c6c479e9a02552ced02b4086570cd77e2b1906f47bd5a18fd0dfa6b4ab3cd667e4595010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1703694b0885d6b0e0e9b8eeed0d02025dc1b767d6adb0572cbe207a5efe2f3c68047784551e7b65051919fed655dc10f7c10f3876fb5b56cc48d86189fca305	1627665507000000	1628270307000000	1691342307000000	1785950307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	362
\\x671f59d8223734e51e452a5c9456529f46c8af952c39d82ca53d375bfcfa4c431375bd6805b6ff6be3c532146ac2e05d07ae78de1a78fa666a79f83b27772a37	\\x00800003c0f295500ba9c1cc401c4a832c4f9f7de6f000fcccca8cdf079a5eb539b7d7626955e06e6f51a00309b3106223fdf8603dd44a7668e7359a38ac1d088c9f743898acdb30afc79629859f6f994ec78ce3c4964d90b3dceabcc2a0ed971b3e7037def157a757c9921f6322f26db1d00b84bd82b5c6770f9dac0830dbcd8a7bddcb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa7ccbc49c86ed013a37e769a7be1a37196a8f051407ee1ddbed9062b67165ccf092fd21bcc387d1521d6f506a628723c1a1bc7f35c2124091e578db1adf4be0f	1638546507000000	1639151307000000	1702223307000000	1796831307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	363
\\x67e7a41c9a2e3dee2e2e80e06bf38358d7281ff8cb867c7ecb2bb9909bbb9e6bb3e9a3f81223af6c6f3616a795390c3ed61bfaca75fdeac2a318340dca7f4f1c	\\x00800003f341038656a645fb9db857129fb39a7cf2acd5b743d56b36ad83450f9fb1d31f17fb3fa5ba97dc430a2d9e9d5d02bd5e94e35919d0190f6b843390573237eeaf60463d971fbb0b2b2832ba9f56d7c64afd6be080661aa2bbe348588f65973553d34a100a7379aeddf8737e009c0bfa09ddbd9d7bd5069cfa3763e9b888ef754b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x01c565b1e8ebed262a7809e7fd9803fdae01c03b490d5d019b0445c848bda340f4bd7193559a8d29c3184b68e32d7ee6f486c53801202425ec01c6b7c4039c05	1627061007000000	1627665807000000	1690737807000000	1785345807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	364
\\x6ae3e41f032a4974090316d9d55ac31bb08814043086dd3332d558e9a444ef44b243015b614e5047ed60069ac4e8985ea84dfabece9369b94d5ca3bc6ee9995c	\\x00800003dd4caa584810571da929353db99c718817062a3fb0c931bfbd125707e247dedb4f3c0f7c156d0285a90cb6b505cf07ccf08ec1a58bedff4730f83f78f57941871c771d3e759d2512d527353af1886791259e67d5382bb621b2a1e86476bfdb90e5efca978994f510927523e377aac732f9f4461e1a5a8f6fa532c4059cbfe7f1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x626b9815c42032818e1b45a0e9e19795b4f3d3edbf7c3d90e7bec22059ee7e57ff6e7d0014947b45ee48dca87c173bd20e63bfd1da49e730e6dc91ae7f84fd01	1637942007000000	1638546807000000	1701618807000000	1796226807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	365
\\x6acf99d2b020ccfb32c1de896cec679a653fc334a480969cb32b50f87f7d5cb6bc67584603c0f634b97e5a5bfb80526b414c33aa4efe60b077b692bcf609c3dc	\\x00800003ba0a0a996ee90bdc882a7b23e088c2bde16231a9f222268c549fe5b9828624d0cf741829788c9a50a5022d203946a4f983ef0b68dbc75cdc71a22986851f985b5337f3bfa0cee8d1b67d7eae8993be5cf8933e80e2fb98df182ab9f6fff478c512dcae81952791c08050f2899ab0560b6b7313c3732f9af6538fd074944816c5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x07b35fcae48df246c5988fe56bb84d00982708c9b19c565e16a26461b1c253c50b83dcea1a4ff26a55f3c5280b0f20429d689cda24540bfad4ef5cc3076c1b09	1614366507000000	1614971307000000	1678043307000000	1772651307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	366
\\x6e87475dae9075aa4ac49c242a4691229745018b94e7fe97b65f1b727bbd243c4ba1611da19ed7e62a06e617538457e1f2cc26fa4a99ec8f9c5af9dc948b2232	\\x00800003afe03a55a2820e95eb43e6842f35cbb7934aa87918c0c4ed42f6c7189cf7aadc5afd86f1dc10242b6305c4c2623ff94b8bbcadfd0c3749bec767294c07929b5df64f1fad4a36b0b137a8d2cea42083af319eeaa54c42f9b805bc7127cc174748d56b53370083cb2e2305948f0cf3106f7a1cb25bf76f5941f54596646ed0ec41010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7af690908b661f02b2cda86c7ec970b646e71eca0697c44be230a67d10501288a38968a6c813fa6e66da4eca137e5fb688c090725668cd97f3225700139eff0a	1620411507000000	1621016307000000	1684088307000000	1778696307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	367
\\x72dbfc1136f9350b8554e74bbeb40e9c19875afa77c4b95f7a0ed5d3d359045efcfa31b33659d6bc46c56284f72f8b3f653c89034876e080ec0e601ae513e3ed	\\x00800003c7f65d4689f3477739befa1c3fe2fe14d9293b87dff29c3be572b08b0765ff926bff28e5a5968af4311df8a87eb885d3a1a6c571b128d3f32997cb43bb17b12484e45ccf1854a1ee5d0ae0210c04ae98545de9c9358e89c39688117d6f9ebfd1b711c7702b0c4f131c3a4d8af5b4748608e96548460ad113937c70fe2f5634d3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc565184102932046fc267a52e4692a151e0b17ac35f658f4900c37425f422e4475a7617bcc5fbfd40060788edd1e856cec10c7aa6fe23ee3c1668096b05f710a	1613762007000000	1614366807000000	1677438807000000	1772046807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	368
\\x74d30a7dfcdcecf0498ddfe0ad38895c4dec8fbf12c60815bd7228b906e8e2c8f81c0b34b31dcc9b8b3f5e685cf44d4116a98ba215246fc4d93531b31dddbd21	\\x00800003c3627254991097ba32cd609340d35e9a30af7405392dc46e0ec967d9338202b951000a2b6f441e17e62f5d732b2f068c2637d977aaa2015032919697886b24d8f10cea056a58fe0f55ff3651d927a464dcb7a6778770ba2138581cf62dadd2f222b45779ed332093ac09d20c721869d74515b1ddeb309b6d0b702ddd921240a7010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x93ba23946ca02a6d5c09da46a5122fa7a1dbaf0af43b29f5b5d69dea67a89a4892bf9e2966417886ed327dd5a79e2e49597b8e026766d7d20f5407b20ff46c0f	1614366507000000	1614971307000000	1678043307000000	1772651307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	369
\\x757b63a27fc1b389b21c979b2c409788daf946a7607e4a68b2a899fadd2c822b1ed77bca9a1a6207bf0d7a2d96e9223b92deeb73aa1bdc6290f37add05750e41	\\x00800003a99a6b53aa7c4f1f3d2e6b2dac596631323f95f73d054e2649ca612751f102105c6a30688177d2e695441362d47337b90f51d95a6d2985b0bd0ed31eeec7b9b47056892819d9975cfe318de992635ebb7b8873b6888bc8f1252d7da5593fa428e5f500ee6c69805c729fe0619326a2b6c5f56d945380521b34902ef02f2a15f3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6b55375285ab5de7558727efc583c6568bf5c0ccbf8b52b3b9f7fe88d14e34dfa6141d29b458d2584d0cdd6e88ba16cab0620a8cf734d322813a0709889a8b0d	1641569007000000	1642173807000000	1705245807000000	1799853807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	370
\\x7c3b25e625f9c177a1ab3b9929e2eec396c0003f6af496e537a481b3de82aad4a8d8ef48454353378bd54e123dde7a275bbb275ce405a12c37a8d172f2785e22	\\x00800003bca37fd1feaa34a669b9fa83c2508b5faa7c93017c0c693916cc8ad8294c21d51c945a565d20d59246c8a1104d95b69a1bd63afc6551115eb6ec4c109270824644611146cd6872205ae34a7e88b871f1c857232efec418614ff12e2f362741fa78c98f8a057c675ddd1ddb282cd6acd042a2b4223e778ef8f5e92ce6b301eeb5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x87db945ecf23391dcf41efa3c1c094fa694d710ef86bebe29d58d8596a3fd8eba066d238b4db65809b0224a574cee9c341b46513ab6c8cb00c04d776f7f5c60f	1622829507000000	1623434307000000	1686506307000000	1781114307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	371
\\x807b1093b9468641506c040e44b9632b3346555c3b253beb6837ad0179f2cf8573df0afb1bb9fcb77be7a316212f8f13326b75282f2b07fa11d3ce8b326eba1b	\\x00800003d947e26b646241d1dac429a8e54dd6e11986735d2f0e77211757e818dd337809ac34d45fc26ec1428162824cb339201446da0578f33621134c1f622c6ad573839d58698f6c8eee5ceaa4230eb69886aac726c9c9bd482fea69b483eba489f569491db793867de8012db8e125a3c33cb4b8e75c9f61aa4d66d8fd1e4f7250cf75010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x80f0c3d8f77d79e36a4ae8aa9b7c80e5588ae2e9f7a5114ee88dec0b093ae9a0b1751bf5b4efa2df094be28d1fda52d25d24487d545e5e05a8934fbae9d4e60c	1624038507000000	1624643307000000	1687715307000000	1782323307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	372
\\x85df979035460ed4be891595f8bd923c3bf402982a713bd789277a49838ece86f4aa4c862b982113402013a2eda321c08041ca895f8cd2aa7d23970789711b2d	\\x00800003b261d9d701415c098a592f19cc2d8e022629577f4a926e5a23302d2de75318aab350666aed7bfc4a049cc5fac029837c2100c9cd06556e42d23f8410f80f52398c0a7d557e9830e4ae959cae98c58aeb44d229a3425973ac20ef878e8fd067cd6b07361ca8580d05b7dffc59417e7a325b098babf1f94d8490701e5e6d344029010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0d5d13062eb3477f06e424e49aed3c1b8d9102395137a532c949c23b54f6b0168314995454e8ba4c07305ea4c193dcfb6b163592d59aef24b09eda0c5fbf9206	1627665507000000	1628270307000000	1691342307000000	1785950307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	373
\\x86ef4a85dee8b4ce6c28aeec7b00dadfe0a3d7006862eb1798751a07bb203a6737ce5b6c929cbb233106cfdbf69e9d78348711342fedf3b47264ba31a1b3b5ff	\\x00800003bd82b6c4ed792df4dc3ceec64abaa9ab6702d9c3750e0fb677682278ace9e697144bc3dbe1fcb57575615bd5469b913798bd02de505de2b6cc9302cee469740c4fef614a626fa5c575f59bc0b98bb4703b8f4dfa26212495ae4d8b527a9f73e5acfe289bd650ca4d59ad5b5f4c40b59cd20740dfa52a01181a52e337b52afabb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1d68a6ab94a87e3197bd28b6a2b175139e6b229b192bf4e5141d6c61392d7cf03732676c9bc5c2844b3ce1cbec9397b4faf1010e5f4aeb459c6b54d922b4e70b	1637337507000000	1637942307000000	1701014307000000	1795622307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	374
\\x86f70a8ce9536c621707ebee44e92261c3da2142ca5fea740da22d1216b48182268c8b25c577c3fc147f5350a35d07292f2b5e4e245e8e05821864cd6c3b6fa5	\\x00800003c2640b8fbf9d78c5d993c0670595ba10d23a6a28554fd0ded06b8d7e34b50a4f21c139602828f72b6503e50ee85153badfac7dd9f149f1d960f56976aa110417705740a1e38b55da0a243c49213cf2a27499660e76ddde2bdd0ea6e7075155442146c5a37e080bc6dc3edce21e50c8eb4f27768b45a201152aaf77b5fe78e111010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xafe25129b1f9e9f57984f326b484ecab02978de0df4657fb77c8a08813ef16b2650dc6b644f65198d521663e8efcb60cf8a9150ad99dff4d3e4f257bcd00e30b	1613762007000000	1614366807000000	1677438807000000	1772046807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	375
\\x878b1061105519d165f22f914cdcf792232a26380e1e1405dc5b3e3b95847f29f840d8fa53a15204512e62297acb5cae3a5f5c872149a56c2ab6481e44e6c978	\\x00800003b456b45ae6c0a19c1270fec397f2f056cbc23d6717ee55d1a816a4dc6bd78b4329a5c59dfaf59aeb10902e4aac2f98fc63bdce9860c1173c18d44994de8c0e980ad1c34b88f013d20d8fce583aa835023368780d41727863db8a1be4978e1d2250dc6da63119acc4604853a71c4ed0172ef82d308fa0d81a274d6487f9704afb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9dc10d8814714beee79a848bb281f1c111a4bd2f0f2c87fbf1aae1d21f580c3933cbcaac4d8326d047c4eba6c8e31732a998e5fa8b3ea6c9e68039ddfeb0ef03	1611948507000000	1612553307000000	1675625307000000	1770233307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	376
\\x881fcdab1e35867b2f83fdf663b3f2881a2e0e4f9e62ebc61699361ab6dab31ab0d6ba8315688b6461897c37968d7817c0418cd823480d092b97a6897381609f	\\x00800003a8949458901bbeaa36a95342fe048184e32b771e87f80f161a631c33ccbc0668b99eafc178bb1b7bd8a36f7975d3ac48218b0a7f6f80f4532e65b60aa349099b23fd11fa980188a8b0f24c75ba6a72eee422d9f0941e24aa2dd75341ba03fd60ba945534b36a4a46d393f5e7985bb3fd377b56eed17c8f887813e994632463a1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa2dd65ed08954e4df21b7defcca8231c4942ca5f639ac714b04de6eee08996bca32d04575ede6d645e6cf0da26ed939d78f98964577878b8dfe4bbe93403340e	1633710507000000	1634315307000000	1697387307000000	1791995307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	377
\\x88ff7141fa4fefda8965764a3cca32eac102679ca55f91931c901feb5f04eb9630db0257ecdaeedb911fa152e3a1f874749017f8faabe5b4e99354c280d7bd64	\\x00800003d1f794e76c29e4d10371f93410e9a756cd8a58d5d2f0f38c9b7e1a5c3142106b845542716fe9c4459c2ff3a54960ef3ac5f58410debe5cdee9415c262b7d0cc81f143ce58906e3fece84c0f52d043fc6a9b8e057a06c0a5484800038955b6f064951e4bb1b2f03536e0e1b6b227f0799f2fddb10b9402f10cf8c13d1d64ac829010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x128e60daa4225317b1b7e4304b0b822a1b5cd5b4b8c00c126f8b40c84950c953955297791eb6461272afc60e33559d46d652d71bcb69d3cc6e89dfa8c33cf90d	1611344007000000	1611948807000000	1675020807000000	1769628807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	378
\\x89cfc7d50bcb2c61b22e58b291cefd2cb9c7cf64c95ba1f4e7f4351541dd6ecbbb80ab16220f9ef277111c3eadfb9a3f6d8aa68e4338aff799808d9ed03f1830	\\x00800003bccd0f32029399482133a2a30d04a604ec734ceb6e5d745d07224e80fb52dc35527ac3a64a989194d6bef0f3be92aea964698d5681c375be4de3d9fe9623b9213943b2c7dec46a694a90b459721798e6b397b40f79ff5f13b6e88f71d8b96f67e7fe7c1d8e6ee12f56f7188ded1bec70ee1bbdc6b3ca98c07234d99131aa213f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xd57d64e2a7c7cece1c49264488d5ce72d360a77907d7e892a620b2401fb0194f051de25c33a4f39009123b6b5012d5190c3b5e8fab13aa181030eeeca5548d0e	1640964507000000	1641569307000000	1704641307000000	1799249307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	379
\\x8a63897890a6412e99728185f2c180220473e497dfb648c2456bfb46704314e8756be7196d2ca32d2d8502b2d3ff94d163c10ab3cf1e1a0183c82e85028a2e0b	\\x00800003bf827e8dbaa8b18cb9938ad33c0b06921c96ad86087ca8cdc17c55d8953dad4356b73d0ed8226bb84b5930e679bb146139e4955fa7ddc09e0908bf63a385d8126b11376d61ea0f98d08ac77129e54ab5de66d7d056bfeeae4206a6420f10a651a987231458bdf924e329c5d475a7eec438bd9a28c0c137ad31f3086a4d0e5dcf010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5b61131585a156d5bbd1a8cd4d0b5ba7add8b9ca5bc6ea101549027ef8dfb11742701abaa1bd4690b3f099ec326b974d72263ed6f59515bd8e6886d5e254700f	1625247507000000	1625852307000000	1688924307000000	1783532307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	380
\\x9327a5d3edaeb0149cb2aa97756629ae74cbe21b4fa6d6281e4ac6afdec1e7a30be742afd095914f69f38eae528fafc830bbb01874c1483fa1e9ed318a5dced3	\\x00800003f29db37b0b67b37bf36b303f1832a420079bf627f324f07ab63c94874fedc0c5c67adb7e6b76b3298d87564a23e5ac9ab6f3116c6f0b088c2e1cce1da698d4a8edd957e9af61437b6d50bb74305463b92e7ed003b7565764377820eb337611d16f2644c12e11990897ec8c94080d44480b8eab5205c71f0a679a0302f3e496eb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfc85b17dcffd41408d0647ed9f0d66043eedbd65e98e9e8869f72c65c062e7c90d7c29902f9c478d58f4be9f92ff25e101905f99244f66cb040f8e4caf9dcc09	1617389007000000	1617993807000000	1681065807000000	1775673807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	381
\\x9683b11125010826b950d4b1d386fa4fda478ae6b6a2ee5151f8939802f343a746b974383b24f29c138d0f3c14aa4bb89a7014db4c1ae3927cb3752e19bdca8c	\\x00800003cb45df43f8cfa7419a0010c8f78304b027c2565e1f2f6f8298953362d58264a767252fc7418e9d37ede40e64ba944e45c2c84fbe157446d4e33c7f31030491c7ed0323a54883f6b8043b1cebb3e3d6ee248ab79511c50342b1058da12a4868c0228748923954cc3bcec75e9e48e9058f8355bb8ae12d1aeefbe5fb59df5b6b4d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe343b2d93b113cd5123c3d10ad34416d71469a392515603c6eabc96a12ab415cc781e298ae2af0aba3388e26265b2413aa38d4a656be8b306ef632d4573e830e	1636128507000000	1636733307000000	1699805307000000	1794413307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	382
\\x97d395a07eac5b939ba8d4f0f1d8a29ad99599c329aadc0ac8845b38ee68a614cc1c1f397b643d5457856d6e112a45506bec8907ab7e6f6dc4d60ecd93be7f09	\\x00800003d6fa934d3388b292e4ea7302ba2632a3167236c8b69b573f203fda97198584151b8c07472732fcb5db1c5565bcf26d5898483102f093cbfaa97e157dc68df7c49894aa5a8a92370fb76f4a47ad4c9a6008e4b55a5794cf322a9aae49d0be2a116846767b273032986407be480550eb0048c3dc9b4c53c9a0bcfa16a0b6df84c5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc3a97cff64a8eeebd059381a572e8bc3c251408b7edcfee8f871f6237946ce2aba64195765b29f78951810ac127c7f9d3a5d374f5bd111393b1eb9ab3efbdf03	1639755507000000	1640360307000000	1703432307000000	1798040307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	383
\\x9a4f3774623b54f2f5895624bc9a6f2376f0e610fda79421f4b3675f94bb8cb12467955a0e7eaed69736f52fa6f13cb7840afa7fa7d308fee0fc92fcaccb3ce8	\\x00800003c6696ac020cf1657822ae2d4ee31ad598d7f35067a5ca5fce4dcfb44d74aa61175263d5af0cabea00382c3ae346a8b3808427ae9c8525ac459a147ec86b0e4a86ee5829083a397b108f9179934c8eeb87db711c963c15d3b7310ca12ced92e72dbdc2c90fc0503235b8d935f4ee5c9b8e1a420869ffbe953f782d2fc73167d95010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1a9075e2640de0fd72d420468a776b4b850bc8f187f410eb480e741b0b4a811790dfc4f93c013b57147613141357c4d8a4dd33b34c7372a4233069a24f29180e	1636733007000000	1637337807000000	1700409807000000	1795017807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	384
\\x9c1b7fa72760a179a31a4eb5320bb2df4eeaaf6e799ee977d1bf03bb5a3e42c65ac6259e8380252baf41dec821aa8537e14e82f5bbec6ad4e1fcd9a14d3c3e08	\\x00800003aa56f80a038f0e2eb4b2b49c00fdeff65bd5d1068e1ceedc89f1b81ba3fe23145d59bede7a8194bcab11fa268cd28a9a5a0e3f811476517ecd8896e373e340ef94dbcba740b189140463fe95627f432ee2131e52f5dc28bdf81b44e0055580fb122f523fb6dc11c3353bff888512478b1e78c6af7c7acb85be342db2e44c622b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9abe5ea36cda8b5298320eafd8e22de145152512a84a1b0291a702bcea87db6e6ef590ee9d3084dfc97dd366703b816d412d8f0bf1d9e1b1f2a88bf77280200d	1633106007000000	1633710807000000	1696782807000000	1791390807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	385
\\xa3af960178ae99ed258304a7697cf105c5d5e6197c96658e55ad034c718b39549c15776dc42496d9cf07bbb69d8c431651d19041d9d168f148471f2d12477752	\\x00800003b88f1c6317329c24f98cb5b53be2112777998a142d7a7bcc8ee9b2f4f906644773b983a51c32c34fb0d3579831b50c5f3bf691df02f5666e728062a2149d46e3dc3de919170c7c7ce2377cc7ac67d378821734a60d26f54871393cad82ea4303d36be3f324a195fc5ceed590c51582327313a9b4468d1866b2f608b343e87ddd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe4680f9e566ab85014d634be22887211b63262784cfb2b63630a60df5a5063a361849e65a7935520825fde9e7f7f9622b7ef42746618b2126f1d41a9e47c6e07	1629479007000000	1630083807000000	1693155807000000	1787763807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	386
\\xa58bf2dbd2b45b79a63832f38fbdf68062cd4bbb6ac14a59d063e56a3b9f6d4332118e3b8dc4688f694b70e7446ba2fa161b7e298c6cacb8dcdc97c9e64f7e2f	\\x00800003c3b256c28e4aefb4c334178c58272f3f8a24aafd3c095ca4a0a109e69e7ebb149ca95e428e5b379c7c5b5fd4272102c144864dadd49b8e1940e25b61b31c078fee785b16739a7076c4fc93054fc02476b32a59ef78cf171cf2bbf331cb1b8ec10b77abea9eb8964a60c451f2e04fd92de79eeac5aa1ad04291a05973410114b9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3b4bd5e06fec27152540a73028d12fe16b163069b85489e7399613cc495170585c256f78e81c9b360ffa41ee5d825d37e25b914c1da490e17d58f4e1a00d0e0b	1626456507000000	1627061307000000	1690133307000000	1784741307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	387
\\xa75be0ebe78fa716f3b09dea64c7ea9a307638ae203876a0038aba0f9f2b988738e2d1d7b1db4aa51cdbc59e421a2a0f244146d8896948b28f753940f748ae3e	\\x00800003d513a315b1e1c6114999bceb059325044b05ced5699062a3586392f5440113049c981d298aa9ac46f1fdc4c42e38f143bd21e1c47547652f6b863367605a034e6d775d415d79a9c394a103f51298f246255a36cf5488c1a96cc627d5b8467df5d099ca6213693725314f0588015236a65c00504b56498edebd150227e65118ad010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x8673c6e6ae2a85b92cee2aeca655cae6a55a348a22e949cbb414bfce215b1d901a23efdfc6bf1c47bf1ced76426a2636962c02a12326fb30ff27a2fff19d1c02	1640964507000000	1641569307000000	1704641307000000	1799249307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	388
\\xa8bb9a861eb298119e7e170e6bc0e11a51713d99a520f14338b6e2304a7a1f481909536a644e626a2a7d9bb8894ca2e3d725063b09ba6b363e991eadaf543939	\\x00800003adb4ad73e858a7091ff3b9da6d3c5a20283bc22a78094cc51c14239d451c36f1644744194606be50ab4b9b0da0700949e92d6eb4695636d88fb09a4ed363eadb47305ab5aef965ac19408e2fd9cd821ae0d04df15a085ca2441623d4015ab71a722e7578defdc11e46710fc17801d9d75357db42d13fc73fa803d36fee8e2efb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xfc5733ea02b2f9ae5b90a9a1db243f240647ac5a62ae9f8da119f28f4a2c39d3b60e1de9a1e422b7a38a0e5f6f84c1b6ca8ecedd9fbfbc7a8a43d5c2b095c80a	1628874507000000	1629479307000000	1692551307000000	1787159307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	389
\\xab5bc4f4e59c9c8f34e79c70536cacd4b079586385d896ab83ade37347a08cbe58052797719446a137fd308909e40b682f2eba8a7d23e7ce620f67dbb069d7cd	\\x00800003d29e2ec4e88c37f9cb833f66ba0610734b39f282d2f3e3e32a98a405bf26b930d58d83396dec55ab43435825846444454e678978f878d1d4ed582da9357664a1d46f68d17a2226856224f68e1dbe30527dccfe46d6f3cd1590de4e36ef567ab552f698f97256291f831bcf596dc8e9e92c91be5aebdc546740a0567389ad3d0d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9ac88f305c9b823afca116ae5005f4a21009e5f5716dfc1836242dae3f50f833ff043bc624242f57d52245520395a4fe1bfc0dee6f08152cad1dd728c2c32202	1616180007000000	1616784807000000	1679856807000000	1774464807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	390
\\xac03f7001a3092c15e5ce870ea2dd85ae7dff716c597a15cdad74f729eeb6a466e371c3a06a04a91851a3d3da2509adf4dcc48d2074ab2184696e98b94b4344f	\\x00800003bc537817619d6359a4da1f4a3ed18e733dc7ebf1588ac75b05c36a697b4ddd89a5256819ba4bd947a9542f38c86d4bae7e8017d61c6fdc5f007bc1069a46661f8fcbafbb15ab2bbee05d0d33f38f61b22e69cb2e83cfe8b0d8d68ddc7936635ee558965d892069ac8813eff80b7bded9f2d552a438c0581f086c9b44f59f21b1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5afe06a5c4e9987561c524b4200fa4ecba3f5b52c252cd4859d968164360e3154b28689f9b006a50f8b28122c0f7e61459a8604c87d97214c34d2b2348800a07	1610135007000000	1610739807000000	1673811807000000	1768419807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	391
\\xad53bef30a7ead8cfd25f86fb30a088e52fe8b113259f107809fa97def0d49d741811780e2904f401c312a5a26648f38b06f6f6d283afceee1976e59371cdb45	\\x00800003bbd94dc93b9dcbbbf411ada4c3cf99e43da16c057b1aea170fb0ee0abc2a2cb64b4122545fd7dcc8b4a1132cefcc28bbab98c0ea1628a6bfe55544168e3de625cc637258ef72dce1447e3941a47112123bb89bee277a7aee457a6497ab25a6da69c10d857ccb0dc9804a0162761a424747d6a18ec3c86c83aaa5d0583c922a95010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe2613b27027866e2f3d199216eb6b351c530177419c09c80a3397d27624d72396e1bfe433b996431ed72ffde9d54c282d29a59d77f7a5712566b853c9fe3fb0d	1614971007000000	1615575807000000	1678647807000000	1773255807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	392
\\xb3a79f557f6b60070341510bf926c688250df95009e603ced293755ba4fdd186478f13134df0a634da65b175a2d6bcfbed1e35c9e461761ea03253912b68f457	\\x00800003c3b9386d7c1167587949fbda7a3bbf74390a410a1f5f5017ee943a2b5c2b97c5c309c104ef2af25439039cba1d3e0afe68f8da1ab3c7d751d39f60134e765241a8029678f5778bbdd2d2c094c3fe2549d680baf8f96000d71e68cbf45637900b52aad41b62a4ce9b10220423c2d93be4c068145cd30ad89df0496085a5e1ec9f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6d0de993138ad06a103393a0cbaff7d3037facf6844e6c81f3ded19726f3e2ba100801530a2e3444a9b604b851a99c93f8c53267b08f73cd29bc73bba6f94a0e	1619202507000000	1619807307000000	1682879307000000	1777487307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	393
\\xb4bf2605699a5b18fe9b61f3f9e074d9c05aa9821c4aea69f3e0d01d646b942440642ab600a4f0cb44f90cd2eed91e605894e13ac06451fde45d248a938d29d6	\\x00800003c5123a7dd14c97df8ecd326e3c1c4fa336f16a3039129da1eb029ba2e9b56fb933f1b20f6bad79015a07973507ca0a1032bbf1cd90f8daa88d62754ca7d988fabd003951c2a5f49472fbe3cb4a3431e78142735252bc9f8226878e7a410d1d036462af74190b5cd4c15f4e6f14c322e4f917f5b1834be02e70d681b9e3888407010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc4b5889dcd839bee5f0ab9783ce8c91d3682e6e26a756f8dbfd5e48dcda8189873e95b64f6cca78a38d94670f3d84b9e8dce45c19653f60d0c3ac42069ec6906	1625247507000000	1625852307000000	1688924307000000	1783532307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	394
\\xb50bb4d34291e2dc8fae003413c8c1ce229242d5ce085c037c474fd805ada8afaa09f15e3e2dbcbcc4e0f1efff58a30fa703bf4e1018c287633f356efa27ee20	\\x00800003b200451eb9ca30d26a58b0fbd71d76b17d8355dccb8a38c42ec2faf6bc8bbc3c87842459caeb78c2c7e31baa7e90b08694b2413a3de3e3061c147fa2a35379198e70f271c2076a247a0ac114053acba838c6d4b866eca1b9f3fdb5243942dd6474767b13f68c3eb0430e450dbf43bc8754e39a482dc9e2a4d54aea7d40905121010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x0681e411e8668b50ce63c3717191715713f4fb5573732a60611f32b514221e61fbd1e0bc623970e17555384990787660b6a530d7060a4f780a3aa8f966f1f307	1618598007000000	1619202807000000	1682274807000000	1776882807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	395
\\xb633b86d6c0ea2a01fe93ff4cd2eb42ad0ffd78db1bac999b1acf0e7c3b8f95f069fb5a29200c1ed449b2d6691a4bb868f9769fcae42f7c200abef58e1c6301b	\\x00800003b2b8c77280d46077a45bc2d6e554f886e689dc12f63e700d95f0f466b9d8ee468ae8f27fd3cf30c8c884c9a743e7c72dde1d981589e056c9729b8f42fb41e6e3437dc2d3229edfbb801bef3682fbcfd8e03c27e37697e0185bc3f505910b543ac7a893f293c833c214e20ea3ac1baeb23123c511252b2127d8374c6dd1087db5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x92a432cd695999524b1b7c7d959de03138217d06a5a90ef28563187c6ff5d82dc82c86acb3f1b311f1fe9e127038c2e9a2698e574e2808210457985663ed9202	1624038507000000	1624643307000000	1687715307000000	1782323307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	396
\\xb743b506da1f6e2f0f3dee3b0c72ed2ce446109d281e6b5152cc6478e1495f591ec80729cd5761e18147c89cbb02559747e8b4e5f8893c8f73c94cdebe789371	\\x00800003a868f58247906ddb10840fa5537915bb1b47d9eaff074e7882186496355c1a6a84ab4041e4a42b15562fbf45b29ec7ac4d1e2a3a69c65e619b63525007b070318d95fb45db365af2f07258c725441dbf3db563099749268bdb8f2cfd195c05963ddf92f8225e1b9853092169b45d73e9af4e37fb3de62f741595e68284a35bd1010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x2023d2a4ba126cdc35e97b5b61b8defad0e36d83d6844945a9ec0e7225995c369a755c0ac6a844d8a65dec2c9808b56be0b788900b9af92de739983245b9000d	1637337507000000	1637942307000000	1701014307000000	1795622307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	397
\\xc0b7176dfc2f6d8db900b61814a92bbce859334baa5c22188ec08df80c111237b6a9b3645db74037da2687b17940e1508a942431e07e74168810a7ce1a75aa3c	\\x00800003f7154838e2a3da62710b020aaabb7a565cf440b96e8c54a553253642ec6b0b1c09fc0ce50e7f5be188a1a375ebd91ad74e57f6b7aa7c82c330101e2c59c9b8eb8808ef8e946519c106aac50afc4468c35b1e7f9dc9ce79f793f2317d73b0d15dc43302191a25f5a7b431c2bfb065c8b20608f69f9b00a575f76e70edbb8d9fe9010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x7e2699154bd98a0639aa603ef84973e80254c723351254a1e90aff23c288b1fd544f3efcb65f7ded65d6d45d9bcb3cd769db8fce7d5b06473501d47087078204	1611344007000000	1611948807000000	1675020807000000	1769628807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	398
\\xc11baf0e135734a4fdf5326622c9683a6d15cce82a321bd8a9bc186cd8e6f49d9dd11f1011c77aeaa66f58e314cf4ff58b80fd551e603010ba36777f0355a07d	\\x00800003f7ea21044034e276fae61fda3b63ed450fcfa0fd3f4e284c5d6418c29dbc614025dbcc2b43c307dd2fa407f40d4a2b1d8eafb5071e47fc68b5042566ede768838a76ac8b2fb348583fa74e3dd10492c54361bb516b97d2e78e1c5c6f0e974828d1d4b8298f8de030507e0de3f5cf955d11a0e47246866b9d13d61f1748227853010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x361e7f64d668222350d1d597d19620a21e138035994be190825b076e7fa6a34c5d451f835ba56d8f45dfdf35543a8757538501c3d973277e50ccf6d61f6a460a	1641569007000000	1642173807000000	1705245807000000	1799853807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	399
\\xc157b865616fdbbdceab95edbb91e7f3e0f821795d6f4652a8404e8ee55749153bb699437185070de4b4c707d70c6a5fff0c287366d0c85419de6431f2c727d8	\\x00800003d13a36702ef58c78597383556bc973feaf78ae1f7c2c8c78fb326f84e1f671ab1933c37f3425ebe32c12ebc04c42449c250198ca8a776a4bf8c17c73fc109c9102bbc5043c3a3c902a3235527299ced3bf6f7fca4c032c720a4c4bdcb3f104051f7182fccd93eec820ec28387d9843c4007e8099b46a38fc6568eb8bf9562dc5010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x03cb155bb31deec8a56022eca746423312e952aaa606c4d751c1271a087b4c50c9e8e39316615f7addb5d5ccf0ed3e2df11d47a1bfafb54cd0c89b65ee9f2b0e	1638546507000000	1639151307000000	1702223307000000	1796831307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	400
\\xc39b0a48c97fc727dadae96e93dbf2644566182c12f903a622aee20c41d8735ed4878770a8d04b781de34b282528752a4227ba22805d2d7c687590be2b294e51	\\x00800003fb0debb8410b96f1a227578f14e889cc18a5a0f4591a7261e6223635474c83983f0d1c83151d94680fd6b1dc043002a0b5e4872ebae0f5834327932a4e0e992dcde66263ce0dedc81e76e82bb88fd8643d99eb3e1e35ce8022afc48cd702e2d15586730d9a91df56380c60d2aaa8c751798e039fe47cafdda6d1a396a9f49e99010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x3554b0659d8061cc4f982798ad57b991053dbdf9bbb78abb8e0b6ba0a45ed71a24de692f988075d33f79afcaf9bd647cc49f36aed6677f86fee9f025cb561702	1612553007000000	1613157807000000	1676229807000000	1770837807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	401
\\xc433a92574a75c8db53e6510f16916dad0ba70a39e68c4b5fc87ad60c81d61ec318dde0d55d555d994cddc19cf4efd2bd6b796db0ad053befe3e420a1e029c37	\\x00800003b2806a42e1004ed1a181df09a7795e384246d6c55b0e28cb92f396f07318ec7001d357577484d4f99c0310e689b114845542b09dd0a9033016428ae145b5036002f46ecd5adc3fd5cb8ebeb1bb5bdfcc4c96d6b9973a50329b6212e3ec2fa3225851b81e46b127d0513da4e4fe15e431577c8d725955ec2bfb9e6df693756efd010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5b0fd0742029dc3c471eab9bb6a4c96a35ceaa979fa3a3ae9fbc14cc3478dcd150d04e6daa53f609937c95b2dc9248a1f3eb2e53f5ef660871e536c8f3a7f200	1636733007000000	1637337807000000	1700409807000000	1795017807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	402
\\xc48b376b8ef17bfee705316704938699525325f07a524cc32437adade7f489e1a44b3cffc221e066a985b512f64cbbf3139144288ca6f4586fd488d9516c16a3	\\x00800003ca5f73e75c5f4880c6e0a637b97529cc743e32588fbd99ae4761c5020a42979bf648b2741556077952c9a4b73b30eed47a7199758672f75d7b58e7a9cf9f59853c707a3afc6a1d1b4fc0d6e8ba397cb82516564bb054aba8219b1eb104e5a99c6ca3b9b6c35cc16b6f882ed6e2fb5e7e578e1f2205378d1128090d87d316cead010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x10386d5f90d5866d58a6451a1d2ab1f43e1b1df2c1b10bc955e4bf135b80e8cf327392eee000d4cb6d8b7d683e2b6c48d2cccdc030971f6852a7ce688e43ae0d	1618598007000000	1619202807000000	1682274807000000	1776882807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	403
\\xc62b12946474de6ae4b41da5bf7fc781bf1cf36ab63390608c324dba37635aa520336e519247ca0eff248066d370d94277b88209e7371ce4413a922aa0e5e3a7	\\x00800003e298703c98b1a6dcc5ea8d33978bc58d76ea7a643a43794fc35501266c7f2f3be1ef26c89ecd83e713bad36486e44701758ddca0b9cd93f58b9a424867baf5b93c1e5cddfc833467ff8ab17f5dc63d2f66d8bf08bfcc44f73fd513a23c007d61a00d9a9477cec9d0a9a0b5fadfc467a5bd2372ad48081f6711d92147b903bc53010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc4c2d9ff789ef02b9e79ac2b212257b9f16cc9f8ba2bcd518cb0d19c103dbf2dab2a1921be6deff5a06d9c4390ab1e3219e2805bef9875f8b5e9f51e4fcc430d	1629479007000000	1630083807000000	1693155807000000	1787763807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	404
\\xc8c30d7596356dc5be7facd6f4a53ab051e35ac77de1aee9b4ceeeb6dc1da61505e18ebd44acf33924e0dcc55aaca235cba5927b30f786ee8e159b9c186266ff	\\x00800003c6783be54565bf6117f5b586b78e80e9a1ae6dc6d696d9153c135b91a9dc454f8bfceb3ff41df7513ea0f5fafdc144353e3b780948725e8a264889b6ea8031948053c3defd4d2e90086dff1830aefea252d8b6ab919d1c4ee615785b82a0a035f7ea064566f67dcadd32b6a2a9c0842b5a174efbb97002047469a2bb0e88b32d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x4f1e64c662528155f8059d16b989b5aeeba1a7bd4ba52ff8c9de3267609b39e71b5c21c1242e515a057f5726d8400257aa8f758a3474f44346f5483f7fa06403	1623434007000000	1624038807000000	1687110807000000	1781718807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	405
\\xd143a7243fcc50df0fc6d2c6349f6294d34483d6150156d46baa6a2601d693865add8b09774bd6f5ed70b4839af2dc35cb07db83e0d84cade58eee584fb3fa76	\\x00800003c832ac3d590ba5a98ad57faee988a470abc051230f5f71cd25a8d5b3883bc698f77b9ede42cfe48d4645f32573a02cae106caeca7a6bac9d8076c50ea9c1957ae8fb0f7da5b582546e67bd5a09c51716624b376395b84d9c7da08312393c27b7423dcffb90ee2968c65a0304ecc3f0d13aa868e3266fc4ee644919199d49b55f010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9562db4bafd830b1e676d85bdfaff27f8d37704626cacb7e4e3f78dd7488d2cbb211749ecbe7bea9dfc143496e510eec375dd851e73e683f1f6a3e44115a860e	1622225007000000	1622829807000000	1685901807000000	1780509807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	406
\\xd2cb170175aeb0a6c5d42d0f409ebacf8619117ae7fb6d958a57be817a0a19ec634937ba15b037c4fcf8f01c88f90b9fdba6a662b7609f12d02fafa41104794b	\\x00800003d6adeb74ea44c55001adc23fce0ccb50eb5c77dd1e80187226199ccde8a7bc7dc795334b2c3db52244b25ccdcd6ba6847493c8513036f68b15c4f51b5ee60df7209214a6a94e0406e1f9b6e600186fab5186b79ae53563d8f4d2f477e29e3798600d312397d7bf61375440203045b35a46bf2e8a335d746a86ee9ab0d84f53ad010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xa6c5f799cbd2e78a8d76c0635c4adfbed32e7c5a83190e7357de1dd0f84481a2229700fe452e1641df9bb86743bb0f88361792c5a1e7ed2797389840cc307a08	1639755507000000	1640360307000000	1703432307000000	1798040307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	407
\\xd37f4ff9bfd57bb2edeea56773eeb54f59e9b012945f6d9bae3d7389df64d501d8667b01234b58336a314ee518698455b7eefb5e0798a36f87966dca46216590	\\x00800003c37f17727e8388b900b2dfed6ee2277cb3fad09ce61eaf1d84e89ca6bbcb1760a8c0182d48bb8f0f7feb8b4e1c6f971dab45c688666809fd89931303878fc2d6516cf8eb1451cb1791de264f5d05015b999dec467638880d3f2d9e6779ed57b80318d88a6b20b12768713c184923f046bc211f2640b5dc595944b7639982436b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6226982b59a1067ed0519bf3d4ddc335868759a7c82e06fae1eb0dab7db4562c9b41588c7e8e9a1a6674249bed658809d6da16c87f4cdda776a31ff5ad02050f	1613157507000000	1613762307000000	1676834307000000	1771442307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	408
\\xd4ff5c0cd014b8ac885221fadf970be0293ab5eb1cd48780335903b61f18b1a7b2976cb446565fbc18a7e386176997ea6bd5d900df588785929ab9ed67d58137	\\x00800003a20875e54f4aeb0f9190f7b64c38b3f596ee409f951f91effc1915f7454bf5b12210e74aa9ca22131cd47c41ad25bed1eaa4b403d9417a2d3617f0fcf3271de758a90b5c708c9d9c2bb97fb0daf99a50aa57a8c5faac25f7a73b0a6a28164470832eb9b909a93fa6df065abb3ed4c26b5598e49771cb862347b889a98b55bc5b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf688c78d9439fdb6917f2b5f333e9eda7e75dd82838719e2911d8622e3b4f5daee47d790fd445402dd7a3f0e36af44f3645c34fc3e53cba1a21b0a1857e67001	1623434007000000	1624038807000000	1687110807000000	1781718807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	409
\\xd43775fddbf6b060576b2812851764edc4802d6ec1bd0e67cfe12d8015a7da4ab5e4cbaa339d58f61b6d3dc6dd7c9e23b34a8f5614edd9b4a1c286af62e25fc8	\\x00800003d3ed7f499a7c4f7083b98cd49fbfadd38ba7626712ba44a2b0463922dd678399e6b04ce8e4f51d745e844fd4c9ea2cc70de9e33db407e6ad829499f6d70055d35ec5f108e1d34772ef84c358b1794f9a39d8d2b9769f6a722a3871b4a590a020970e0f2e0166090177241bf1c826db7e2cfab253a77fe268950744707718a873010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x39de6a8626574ba5a5d817d27f23e6cdbee638df33d2492497af1ba9d6453ab21199fa7b968a1a19c67a60abf46bdffb7a4833b60fc55d09b8177239cee4cb09	1634919507000000	1635524307000000	1698596307000000	1793204307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	410
\\xd65ff2ffd623b571e5a9aafa62e39b1eb025a2cc4b9d6a9c19866b12ec06ade7dffb47df2e5492ca619775414b0f069f5bec06c287a4316c0c203adbb100a9b8	\\x00800003d649a83d9b6a11f5c078f3da8e3129fbec8ab92ed536e1419391544e5d18f3d48cd9cf153bc043c4388216726c11875346c16b28dc83a267cde64594a4eba2df606febd362609b6a3500745fd71050ad78b6204012e7e879a73ff902ce4d74fdc8f582c2c28f6e1a04e407b3fdd2d10f4e1f6a0550472048219ae39515cdaa7d010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x07fe3d1564acd045a648940ac18cd64f25d5cf5d004fad5970597355ee31c2d8568d1455fa9605617835e66f1a07c458267bb11cb0b7355f25df3dc88fa12f06	1611948507000000	1612553307000000	1675625307000000	1770233307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	411
\\xd813a32717abd37c6f253d00efd85e674ec5f2f3f2c9f6de955a778aa5bde535aaf394cf8e0bbea7376f1e3673d3e273a373ed34402e79ef0910057ca928f27a	\\x00800003d7504afb6bf6a040fa955edfedad8640f5d906956045586a5b48b5e4256f766ad89981e9ea205cfed6a866d8cfb626e18e10b386d704b1335885e02124d9a477710ae668a94393fbca664d78724da15efca54f13b4c47f8dddfbb8427e039e1f234a27e232423574d312a6214d8f1d4a7fcd77b6fe035e8be5574bde2d80c313010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5caffbd1bb2406a4d993233176679a2abae4465ab378b1a7ce1b1fa0d64fdff8360279eb2e04faeb7c4521f8ec46c704ed1ff15c3e35e5a6b90a541beed15d0d	1636128507000000	1636733307000000	1699805307000000	1794413307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	412
\\xd9df0161e5969950945c4dfb3cf3be9a5c8a6b065d7574d89d21b2ed7575a6ca82f2d7c5cdf4d24104a8ab2fbae4a0fb1e0e4077bf6feac55f4c07ed6bfec0b8	\\x00800003ee0fb9594ec30646243c9815df37271cf7022e5fd224c5f3b46a1cea38833b26ca05e61612623f49a588d4b7fe1712a9b724321c92ccf7edeaa40df3f99313a913f7ffb43e2959d2dc7986a4fc8af6e0052618516b88b8b445e2e35de7dd12525957ffd08ed2dedee1bb535c694bbda30638ec5aab56cb87bb2e3dfdf88fefd3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x768516c483a5c2e166c13aec46fc444a51cae51491ee2a2d52644eefc830bd9bb559d8d3724c35ab87a3886e7f0fcf9d12c155bb521ab8f0e83f9d89211b950f	1614366507000000	1614971307000000	1678043307000000	1772651307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	413
\\xdb2f30fe14b33cb5b531560d4dd627758892a74e193bf504697a53ef0dacde1eafa4d05433b7a6ada4ae724a7ab95d24d6e9246ca4d86ade31b9a5b3f66c2263	\\x00800003ca1a434ac86f3dd86407fb698ab9489536bed065ccfbd5c4a08b50d35b1d1e42c241287462b25867eaa10e64b890277df80af3064076b37ceeeb890fccd2f53e0e81fd70e794e91b8fe71a08aacb3c9db4cb317bf86e3af1563d016d90c34b0aa67cc4069bdb3b288068d617feb8da6813d8530b63c3fbc4eada6f497c457043010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xdf0a756108386b336f9ed706c488b7f01664fee3324737702438f1c76a864c5d2ba088a82b3724ec79e57b3512cdcb161252c8b7e1ca464295455a65e00e1d05	1631897007000000	1632501807000000	1695573807000000	1790181807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	414
\\xdc2bb361be275ea7ac2a1b5a5e1e45fb1394dfb5f4ea80657f9ffca1265ac7124143ad81d181ae258a70cdfb0dfaaea9a848fe5760142e8dabc5ca34bd8ffbbe	\\x00800003af753dca8d504b08bb6705c637b79ece535f21612143531f8330a2e5070b4dec1e30a877aa602b5c283976f146e48a44e8a3a63e09b863e4374da6849a113bf04b409b8b830ecda0804a4ddee4821f59e97533ff2663b0a3956cbb0c59c934450602bd37416b8d4891395a9bacd8ffc63d54b17ae634bb349eb3c254e52c7dfb010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xc336f544614529348ea26aa2a9c7ff8e84f545aa73f3667b56f9b03f59b680f8489a289f65bd9117ec6cb131d98ab11f8abbff5e57a55d1783b6a191de99d50a	1640360007000000	1640964807000000	1704036807000000	1798644807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	415
\\xe2238538333069e448fc2e0e33adc0fa16970114e8df4bb1bdc57225f5201cf7c54d39abd98285273c51b9589dd8df2ee95262a6bfa2f345376d857cba41a3f9	\\x00800003e32695b55f5a4b2c8c6cd64fea1be65d44ec25db59d5a1155043ed51533038895218f7de275c23c07dac192e35bb9aba8f8ef586c54d4ec85519f0a9698811f7509c21df756288b09a9ee91b81de6b68692754596f7dc4f5d1e6e323931af4cc525ac481904484950265dec6788559f1b8e1d13c168577756077ab3ddafed959010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x5fd738161a33cdd3ad5cc01cc2707ce1791a23f9f29a0cb02bc503a92aae52c549bc06c2810ef9434e977f1eda5c87187eb26c964c7406ab52cd54945f57650d	1636128507000000	1636733307000000	1699805307000000	1794413307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	416
\\xe7873e10e21f00490795a4ac0115101ccb493fbb10f93023b2cb4aa2feb5a294f1533fc353843d1c6642ec22d0a18d2b51b172d653c752cc3b5c2c967eb398b1	\\x00800003ae20c6b88360d6960a8eec9fc71fb542f0781b69b9181d66e20d7f98f93674bb47e051cb0b159898c4e95c6bf2d12b8c470279364263046a5c14cf4e2d33e8ed54e76959a48289525feca9c4e7a9a38a65e2163c1ffb85807194f4e8efb2d60816c88c3c68d54d5fee7f58185434ec5d36d91073acacf518e88903f937044b6b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xbecd18fa93c9d95e0f06f9f6e015db534d8cd0ea0526bd016f886ad005de1ce67684740d393abc3f45b72f1d613883f293d5d8858b4f52c2028d152788e8680b	1635524007000000	1636128807000000	1699200807000000	1793808807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	417
\\xe9e30954c6253e9691d6c5ee404738080fb2a6b4346373183ff620706ff0f05f8e9f598e1b7ef3c8760f7c60dd4f1ad3a13efb69c474706b9ca6f189edaa139b	\\x00800003ae40978eb1d5494cd3b9811de03c778a64d41301607f3aa5aeba7d17496f54af05e40492a53a69c81237667f8c1ee197703c273115e6cce4d742abfe92e151a004aa039ba424a4a749ad2c93825e51ee44d3ec49d006f62c091f3ccf5302e9b06ef5f97d1f560d3d5d70b01f1f95c6aa56692b303a5912afc0fe42658b38574b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xdae1a2708cfddbf8989d478e34243f46d9bd8ef05424f9d87ce8fab41dff1025778ef7cfd14ae764ca2d5ce7442dbf6598813fbc94a2fd708198b547a6965209	1638546507000000	1639151307000000	1702223307000000	1796831307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	418
\\xebff435f222e9dd04715d80678c2faaf289ec8c49bc9ad9925302d22ba0ccc2213e90570de71f211e884e8753153e171b24eb31a3be1bf0e8ce834599e1cf8ab	\\x00800003e9126731642cd290d655e1f83253bb201aae39f065a13da084847e461e6ac670fd5c99c5280feefde9888b5a9dd39f4d15b052f51702b95ad800821508ec5899e83ee47478294cbc2ca33c988f7c63ae73991625addb9fc26ec2acea0ca2b4efa8dc48c82f63ffd8e34135a7d3afa2c8fb6788747b64fb5c4f1c5c48f5f4d225010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x1dcd3e789e4481ca9ac8ba45a1f3e1ae0e272f28bda5df614ded1219f4c7863739428aeb529121dc45d14d6e2d18681c86dd22a58d049cdf23a7675f081ce406	1623434007000000	1624038807000000	1687110807000000	1781718807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	419
\\xec4753cebe1186a8cb1db32c0b0482529b2254114c3cc49b2e281030f7f81ce1fea4f8176f56537863d4d57cdc90e823ef5fdf95dd984b752a90b60a3ee24a9b	\\x00800003dc697b984a7330d9d7455df934939103e796d48996d5496e2c240945c4bfbc2e139a947e3b36b12b18a1816b212c60b7d6e1248637f2648cdf325e44261a6bf3269da61196c9e40544c20722cf2e64b4bc5a5cda9468cb1567500c25d8b9802ed3fc54f14a4328701b7d22351a2bc20c98497243bb07bd4dcc6f613476f12757010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe1a2f07a749c1da6e3ac4beaa6e81343c66e156f8b12352ee7366207702afe22024216d373bc797959b9f54a295abf836995b1726e2598bd8ddb1ab5ef81d50c	1630688007000000	1631292807000000	1694364807000000	1788972807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	420
\\xed7f49750bcd49289b83c751307970b2c059a148504399b3b403df10b2587bfedb06d8775f260e12fde1e6979a0e942d702b0c84102851a9ea68ebf25c9c5329	\\x00800003a0380558748a7de231332b6337b190bd13ee994216cfaacdff97cb3ca07ffef8794d985f6f440570151027d1d1ddf85d51b46012c1889e38086bb7cd17e1f86dceae14da0c7a3c87d9605ee3c8e816ff7335f4ec852be1011f7def539b8b499fffe77151693c4b67f2f3d4d514e0884d6f755d6f726f66cdebff3ec94222725b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x17933c3c41a6c00a4715074f76d173de4913390e2200b39aa5d3659dba8cbdc448069801b297415101b8e0670e30741dfbdf8007df6ff2952dfddffde307e50f	1640964507000000	1641569307000000	1704641307000000	1799249307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	421
\\xf0038d3d94672a795b3b730b78b1efb471e24547333b3ea61371d26d84dae6559ddbab3af6bb24c1597546cd352a9d6e8c71a2f75980cc9db77ca2f38915c518	\\x00800003ab18ca177d65a9301ff9bb8719bc1bf1050beb0b7d70cc957bdbf90d163d6802aae773d9aaa949ee3f2e65c76fea9d09dd74c88d200766c0f371a0cc0ef768438496e1bae10b45e82d578c97375fdbc28d1d0e3fe54568655a2f372f9035008c58198656900519233dc12276b720c19c75fc06e7cdc198f50980eb2866b05bf3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xe15fa26525d6cb6a3ae9ea3c99f1cf25c45771511bb4a9e6665abcd70e6abf53fb1db42eb5863ed7457ffeeef31eb4146d5aa5bfa3ee24990fa7445b0007f80d	1631897007000000	1632501807000000	1695573807000000	1790181807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	422
\\xf177a4c5f07a8514f3b43ae0adb07f16c40d3673268179e8c5b35c3efddae072acf730d219db0353e8ec5c1e2002c3e3a4e64fd6c161a3b4b9f087f6cb96101e	\\x00800003d87ffef3353ad8f743320332908e3e6563a8544fd36a5bc7ee1cd71b31371640a44ade115dbb85b553a8632036d2dfbea96c01bbf75184acde08a6a9dc92fbca795cc1020c1ca037a6531fc1eaac511a33bd311fe8a30a581f5ea2ba908d6c5ec61d8f60a122fc8425c59973d387d7591c9088832343307e0110c87bb6c7aa4b010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x54941cc9ef667d4b52d208b009e9bb4ad02ac9226727a83a4be620f109b5f6e75160ca2b72b1a8c4d3acb57222847c65e362545530e26d2502cf212641567a08	1614971007000000	1615575807000000	1678647807000000	1773255807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	423
\\xf7076e6e7509fa675b1be8c6bff9d541cfd77b56cdb5f89198583e08aac6e07bc11c1cf93e2136c27e566e6ed946cd93ee6f21f51806573a4873b654185f1dde	\\x00800003aebc3bfdacb436aaf694b26fbe9e5da97c49c21c96c40f3872bd5475f9dbdff8b48366c0472a8d27e7533a958a769e0dcdd0c3fb2386e48eb6a691954973230ed28b52004ff800bbb81c17cca54a6be4c00ad809498c368840b0b8ecce2cc470fda56b4b7c7ebc8da44f4727673188056cfdc68b3cf064ca22b34ec9b7b7a4a3010001	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x12a1efc21499d1e735945a99e642b548d8418a3fec409b9b0a2d386abbcd79351dfd8c92f0a23ff5498fc667a59afbcafb164c9ab74b4dfc4514528fc924880b	1617993507000000	1618598307000000	1681670307000000	1776278307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	1	\\xc247849d1fa0bb00c1a0ad8ee3b15b8030f8df7fbf9cc4f52548794bbdf9a9cf89c3964b6fb2f8d392b13f583080d6c65fd2654b19cea2e309fda714f919efc3	\\x2dcd9752e793194d1854146294c83b18cd941b7edcee806a34c519e65529be6df1cefa8b1e096b3983f1faedb5c93f0645704bde7be1bcc70183aa0604de84b3	1610135033000000	1610135932000000	3	98000000	\\xa7ffe30b37938cee79b3e733de599066a5f99093d38824b3445a35382e0cf795	\\xc89c8d0918d59ea575af9439ffa85cbffd6f0bce1eb40f5783be382b39eef93b	\\xc219ae40dd0fc10f699fde2b37e8d11037930ef5f3fa48fcd728681d4fc285ee7b2649764b7ddd8ef697d134e9b85afbc0d1d21830a6371f9cbb70f45162b509	\\xf5da9fc6715d22fb4ecbe90d115e4649e179b786545e7947dc4ffeafa65935d0	\\x292ebbf60100000060deffdbcc7f000007fff67435560000f90d009ccc7f00007a0d009ccc7f0000600d009ccc7f0000640d009ccc7f0000600b009ccc7f0000
\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	2	\\xa6f3d0a0b7618e8ce7a320f09978f450a63499fc6a122523d099321cc3239b57e56c593f5555a35eb165acf075749508ceec9974ac13cd137c3a0871b08305a6	\\x2dcd9752e793194d1854146294c83b18cd941b7edcee806a34c519e65529be6df1cefa8b1e096b3983f1faedb5c93f0645704bde7be1bcc70183aa0604de84b3	1610135040000000	1610135940000000	6	99000000	\\x0f04ccdfd86d19bb18cf54618fef7b07d1167f5eb13b971c62842c0a78714ddd	\\xc89c8d0918d59ea575af9439ffa85cbffd6f0bce1eb40f5783be382b39eef93b	\\x28a5b8991086fbda8eab4c3b2541f8af75575f4543437dc6b81042cdfc1f420da6a470e67c70faa6489ad6667065afdbb512624380fde2c42f6b42099e2eb10f	\\xf5da9fc6715d22fb4ecbe90d115e4649e179b786545e7947dc4ffeafa65935d0	\\x292ebbf60100000060ae7fdacc7f000007fff67435560000f90d0098cc7f00007a0d0098cc7f0000600d0098cc7f0000640d0098cc7f0000600b0098cc7f0000
\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	3	\\x4bda2931fc38daa8e1e3cb31f421ee8ef903c263f65ddb9152c0336bc973609320b9af292694bac96c56292b341338f612a726a53d463c8434af3ada67b42ba8	\\x2dcd9752e793194d1854146294c83b18cd941b7edcee806a34c519e65529be6df1cefa8b1e096b3983f1faedb5c93f0645704bde7be1bcc70183aa0604de84b3	1610135042000000	1610135942000000	2	99000000	\\x5561c1f3d4672002a7d0ea57e28d2f8297efb0eb8b9f3987c696eff9ae522c71	\\xc89c8d0918d59ea575af9439ffa85cbffd6f0bce1eb40f5783be382b39eef93b	\\xb5da0a30fc836978395eed9d2956dfc3c776765dfa4706c593a92808567e49c7bd2019ae8115f1a0688e2cf4b86e92f5e2e1370b3b44cb2849770adf35f15501	\\xf5da9fc6715d22fb4ecbe90d115e4649e179b786545e7947dc4ffeafa65935d0	\\x292ebbf60100000060deffdbcc7f000007fff674355600004913029ccc7f0000ca12029ccc7f0000b012029ccc7f0000b412029ccc7f0000600d009ccc7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done, known_coin_id) FROM stdin;
1	4	0	1610135032000000	1610135033000000	1610135932000000	1610135932000000	\\xc89c8d0918d59ea575af9439ffa85cbffd6f0bce1eb40f5783be382b39eef93b	\\xc247849d1fa0bb00c1a0ad8ee3b15b8030f8df7fbf9cc4f52548794bbdf9a9cf89c3964b6fb2f8d392b13f583080d6c65fd2654b19cea2e309fda714f919efc3	\\x2dcd9752e793194d1854146294c83b18cd941b7edcee806a34c519e65529be6df1cefa8b1e096b3983f1faedb5c93f0645704bde7be1bcc70183aa0604de84b3	\\xe6752fa9432520bdb0ee04246188c6b0c241fd71de1c81e795c61e7c50935e290807c206cd12e244c978f0c73bd71932c8342984af28dda8be92125f78b76005	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"FD8009V6W94E3RR5P650XVQBS9R7EM2XP36XEYAC4GDYZ76DP0560ACS64P7GG3DDRB4HR72VVQT5CBJN9PV479Z02Y4FSC5JAQENN0"}	f	f	1
2	7	0	1610135040000000	1610135040000000	1610135940000000	1610135940000000	\\xc89c8d0918d59ea575af9439ffa85cbffd6f0bce1eb40f5783be382b39eef93b	\\xa6f3d0a0b7618e8ce7a320f09978f450a63499fc6a122523d099321cc3239b57e56c593f5555a35eb165acf075749508ceec9974ac13cd137c3a0871b08305a6	\\x2dcd9752e793194d1854146294c83b18cd941b7edcee806a34c519e65529be6df1cefa8b1e096b3983f1faedb5c93f0645704bde7be1bcc70183aa0604de84b3	\\x90a7dbabd4f7f8a5580b86d3e450d3fbaf6b8aab47f0095c09961feb11a890dcf1df1dfba6f933c3e82c4b4bfe153ea4ee2f19c1aa7378088b04f3424389aa03	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"FD8009V6W94E3RR5P650XVQBS9R7EM2XP36XEYAC4GDYZ76DP0560ACS64P7GG3DDRB4HR72VVQT5CBJN9PV479Z02Y4FSC5JAQENN0"}	f	f	2
3	3	0	1610135042000000	1610135042000000	1610135942000000	1610135942000000	\\xc89c8d0918d59ea575af9439ffa85cbffd6f0bce1eb40f5783be382b39eef93b	\\x4bda2931fc38daa8e1e3cb31f421ee8ef903c263f65ddb9152c0336bc973609320b9af292694bac96c56292b341338f612a726a53d463c8434af3ada67b42ba8	\\x2dcd9752e793194d1854146294c83b18cd941b7edcee806a34c519e65529be6df1cefa8b1e096b3983f1faedb5c93f0645704bde7be1bcc70183aa0604de84b3	\\x239c02f4ea4cb953b2eeb21cc553171b8b4475241393c787bdff89c53467aa7e0f90a76e38526b36bea609462bc9938efce0866d2a00443ac04016aeb38f1c05	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"FD8009V6W94E3RR5P650XVQBS9R7EM2XP36XEYAC4GDYZ76DP0560ACS64P7GG3DDRB4HR72VVQT5CBJN9PV479Z02Y4FSC5JAQENN0"}	f	f	3
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
1	contenttypes	0001_initial	2021-01-08 20:43:27.2582+01
2	auth	0001_initial	2021-01-08 20:43:27.298312+01
3	app	0001_initial	2021-01-08 20:43:27.339961+01
4	contenttypes	0002_remove_content_type_name	2021-01-08 20:43:27.362943+01
5	auth	0002_alter_permission_name_max_length	2021-01-08 20:43:27.374917+01
6	auth	0003_alter_user_email_max_length	2021-01-08 20:43:27.38255+01
7	auth	0004_alter_user_username_opts	2021-01-08 20:43:27.387957+01
8	auth	0005_alter_user_last_login_null	2021-01-08 20:43:27.393522+01
9	auth	0006_require_contenttypes_0002	2021-01-08 20:43:27.395465+01
10	auth	0007_alter_validators_add_error_messages	2021-01-08 20:43:27.40076+01
11	auth	0008_alter_user_username_max_length	2021-01-08 20:43:27.411388+01
12	auth	0009_alter_user_last_name_max_length	2021-01-08 20:43:27.418648+01
13	auth	0010_alter_group_name_max_length	2021-01-08 20:43:27.431231+01
14	auth	0011_update_proxy_permissions	2021-01-08 20:43:27.440187+01
15	auth	0012_alter_user_first_name_max_length	2021-01-08 20:43:27.447465+01
16	sessions	0001_initial	2021-01-08 20:43:27.452054+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x80bebbbf14dff2d8e49184813b155d0966264c884dcdaae00524c5050db8023e	\\x2486f49d18112dc823b0927828e0bc4620dd7be919d49027d5505a72c6dd475d7e13e11927fc29cd96595a720cb32e6fd97d48756838df9c8ecadae327339e0e	1631906907000000	1639164507000000	1641583707000000
2	\\x6a8be3d70fa08a58e91ef302812de6c60feea29b933e358d34110b9aaaaccbef	\\x827159370dca1063c781cc721977b1aade8455d5dae597b6b37fb9472450746110980cf82023c552c0471b8f78bbd83af0bf3ebb0f4081b219886df89de54606	1617392307000000	1624649907000000	1627069107000000
3	\\x904ae8610c7666fe9af835ad1b9af753efd9695b1d3239b4081a9e23588f2f8a	\\xf78c7f31a5fe17c264c8725f59c177885258219d579f36efc355490c09c980fc9bfabc26b3714d90199d7f4dd6d2703ff2c76339a3a1d5189816dd1ea1688503	1639164207000000	1646421807000000	1648841007000000
4	\\xf5da9fc6715d22fb4ecbe90d115e4649e179b786545e7947dc4ffeafa65935d0	\\x636e8323983559910ea6d8760ef4d045a6f30626a30bca88ad6ab3860136e8a289270cb192924ec9bcf408acd5799c39917944285eaa7f70c34fa7cfb5d5f109	1610135007000000	1617392607000000	1619811807000000
5	\\x9df42631fbe211d13f0173b899d422d0cbf5ae7a910818d92ef80db2b3f127e5	\\x54bf38bcf1c7cd16923683712ec4b420cf076415a56cdb9b2dca18a3e2fa8b09472aa2823ca77d0a1869519c3da137540cd67c56b5683acb15d4936f135b2102	1624649607000000	1631907207000000	1634326407000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\xa7ffe30b37938cee79b3e733de599066a5f99093d38824b3445a35382e0cf795	\\x61271847fbd172f6e897ea6efa7be5533c8dcde26cc270606036a4662ad27ffe4f905d92c19266f3f8f2b9b7f5a9d0340a349c716b572626c6f77387eb8c6213d20fc344b7c4467fbfccd09070fc5db3fbc9db93f83cac3bafa0f1ebb42634bce117d802a43429cc17d449a8d55e3874781e1f928f94c3ca208a127df65ba956	170
2	\\x0f04ccdfd86d19bb18cf54618fef7b07d1167f5eb13b971c62842c0a78714ddd	\\x4359c332253d1864250e28728b74be21496a733380dcca4e24e0cbea283ba9113f838de391fda9dcbfcb9d72d1ac8f104a84b61b9f5cc4f407ba65ac349b61e5cf8e19ad65c5dcbf80b03794f3bd037cac0cb30d2cc64127918f22fdca3b9374555829837d068f08113eaf32bf7af1b13e3d499eda553cd1ff5a6de08f0ca3a0	65
3	\\x5561c1f3d4672002a7d0ea57e28d2f8297efb0eb8b9f3987c696eff9ae522c71	\\x8c9c97084d44bea90702e106bcdbaede0cdc69216a801e7e0477379633886586615c1c9b674b39d299d7774a5fb22f1459c3c6a23d9cf291573c7536d53a9ac32d83e00f8b787e1f1a50a9cb9bad9ac2b189fd4cb9eb865b9962e49a30cef673eea8559719fc526f590d42cfd0e528fe7b83f5c4d9df2a40c698ef00ca5b483f	105
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x2dcd9752e793194d1854146294c83b18cd941b7edcee806a34c519e65529be6df1cefa8b1e096b3983f1faedb5c93f0645704bde7be1bcc70183aa0604de84b3	\\x7b50002766e248e1e305b18a0eeeebca7077505db0cdd7794c241bef9ccdb00a602999312c78406d6e1648e0e2deefa2b172aa6db21d3f00bc47e58592aeead4	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.008-03CFBRYGXFX72	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133353933323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133353933323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2235513653454d51374a43434d5436324d32484839394a31563333365338365659564b51383054484d524d4359434e39395153505a334b5154484346304a5453534746525a4e56444e53345a474348424739464637515244575257305237414736304b4638394352222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30334346425259475846583732222c2274696d657374616d70223a7b22745f6d73223a313631303133353033323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133383633323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252445136573030393156445256304a41303156355334594d513541395a5a3444344e543557425a384350435035415a47344e4447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22533245385432385254504641415844464a47575a5a413257515a59505932594533545430594e573351525732504546455a345847222c226e6f6e6365223a225259354d42465a38425a424e503447325a345a4d454d53504758373045444a3157424d394846544d424646415651324254413030227d	\\xc247849d1fa0bb00c1a0ad8ee3b15b8030f8df7fbf9cc4f52548794bbdf9a9cf89c3964b6fb2f8d392b13f583080d6c65fd2654b19cea2e309fda714f919efc3	1610135032000000	1610138632000000	1610135932000000	t	f	taler://fulfillment-success/thx	
2	1	2021.008-01H44NP860GJP	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133353934303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133353934303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2235513653454d51374a43434d5436324d32484839394a31563333365338365659564b51383054484d524d4359434e39395153505a334b5154484346304a5453534746525a4e56444e53345a474348424739464637515244575257305237414736304b4638394352222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30314834344e50383630474a50222c2274696d657374616d70223a7b22745f6d73223a313631303133353034303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133383634303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252445136573030393156445256304a41303156355334594d513541395a5a3444344e543557425a384350435035415a47344e4447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22533245385432385254504641415844464a47575a5a413257515a59505932594533545430594e573351525732504546455a345847222c226e6f6e6365223a22504758574e41483739375342474e513133475a434d4d453945525041374e4e4d42444259324a36344b3052514a5632514b303247227d	\\xa6f3d0a0b7618e8ce7a320f09978f450a63499fc6a122523d099321cc3239b57e56c593f5555a35eb165acf075749508ceec9974ac13cd137c3a0871b08305a6	1610135040000000	1610138640000000	1610135940000000	t	f	taler://fulfillment-success/thx	
3	1	2021.008-00677NRPGPWPP	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133353934323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133353934323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2235513653454d51374a43434d5436324d32484839394a31563333365338365659564b51383054484d524d4359434e39395153505a334b5154484346304a5453534746525a4e56444e53345a474348424739464637515244575257305237414736304b4638394352222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30303637374e52504750575050222c2274696d657374616d70223a7b22745f6d73223a313631303133353034323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133383634323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252445136573030393156445256304a41303156355334594d513541395a5a3444344e543557425a384350435035415a47344e4447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22533245385432385254504641415844464a47575a5a413257515a59505932594533545430594e573351525732504546455a345847222c226e6f6e6365223a224b455854484230304551414e51474b47584a324246354d433742414b365830534a573752534a46343251505347544556364b5247227d	\\x4bda2931fc38daa8e1e3cb31f421ee8ef903c263f65ddb9152c0336bc973609320b9af292694bac96c56292b341338f612a726a53d463c8434af3ada67b42ba8	1610135042000000	1610138642000000	1610135942000000	t	f	taler://fulfillment-success/thx	
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
1	1	1610135033000000	\\xa7ffe30b37938cee79b3e733de599066a5f99093d38824b3445a35382e0cf795	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	4	\\xc219ae40dd0fc10f699fde2b37e8d11037930ef5f3fa48fcd728681d4fc285ee7b2649764b7ddd8ef697d134e9b85afbc0d1d21830a6371f9cbb70f45162b509	1
2	2	1610135040000000	\\x0f04ccdfd86d19bb18cf54618fef7b07d1167f5eb13b971c62842c0a78714ddd	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	4	\\x28a5b8991086fbda8eab4c3b2541f8af75575f4543437dc6b81042cdfc1f420da6a470e67c70faa6489ad6667065afdbb512624380fde2c42f6b42099e2eb10f	1
3	3	1610135042000000	\\x5561c1f3d4672002a7d0ea57e28d2f8297efb0eb8b9f3987c696eff9ae522c71	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	4	\\xb5da0a30fc836978395eed9d2956dfc3c776765dfa4706c593a92808567e49c7bd2019ae8115f1a0688e2cf4b86e92f5e2e1370b3b44cb2849770adf35f15501	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x80bebbbf14dff2d8e49184813b155d0966264c884dcdaae00524c5050db8023e	1631906907000000	1639164507000000	1641583707000000	\\x2486f49d18112dc823b0927828e0bc4620dd7be919d49027d5505a72c6dd475d7e13e11927fc29cd96595a720cb32e6fd97d48756838df9c8ecadae327339e0e
2	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x6a8be3d70fa08a58e91ef302812de6c60feea29b933e358d34110b9aaaaccbef	1617392307000000	1624649907000000	1627069107000000	\\x827159370dca1063c781cc721977b1aade8455d5dae597b6b37fb9472450746110980cf82023c552c0471b8f78bbd83af0bf3ebb0f4081b219886df89de54606
3	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x904ae8610c7666fe9af835ad1b9af753efd9695b1d3239b4081a9e23588f2f8a	1639164207000000	1646421807000000	1648841007000000	\\xf78c7f31a5fe17c264c8725f59c177885258219d579f36efc355490c09c980fc9bfabc26b3714d90199d7f4dd6d2703ff2c76339a3a1d5189816dd1ea1688503
4	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf5da9fc6715d22fb4ecbe90d115e4649e179b786545e7947dc4ffeafa65935d0	1610135007000000	1617392607000000	1619811807000000	\\x636e8323983559910ea6d8760ef4d045a6f30626a30bca88ad6ab3860136e8a289270cb192924ec9bcf408acd5799c39917944285eaa7f70c34fa7cfb5d5f109
5	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\x9df42631fbe211d13f0173b899d422d0cbf5ae7a910818d92ef80db2b3f127e5	1624649607000000	1631907207000000	1634326407000000	\\x54bf38bcf1c7cd16923683712ec4b420cf076415a56cdb9b2dca18a3e2fa8b09472aa2823ca77d0a1869519c3da137540cd67c56b5683acb15d4936f135b2102
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xc36e6e00090edb8d824a00765c93d4b9549ffc8d25745e2fe8659962abf0255b	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xe223d0cd64d43e6f2948926ff04d607747855de7d2e5aa0d99c2a71377938b54a1d0b2fad7b9e821f54b4c021af998e7b02a101af89c179e467d1ce58d634107
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xc89c8d0918d59ea575af9439ffa85cbffd6f0bce1eb40f5783be382b39eef93b	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x52fecb0a3a5259b5c324aff21be8071c40087fadb17635be5d68c5e1f2fbff9e	1
\.


--
-- Data for Name: merchant_order_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_order_locks (product_serial, total_locked, order_serial) FROM stdin;
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_serial, merchant_serial, order_id, claim_token, h_post_data, pay_deadline, creation_time, contract_terms) FROM stdin;
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
1	\\x5adbe2d9835b76b0e1fff0862f131fb40fbab9ccafe9c2f3155ef0fbac63835766fdc39ca020b6f6fbb99d53447a31f3e0f4d3d8ea747b7f27bbcea347a86a0d	4
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1610135040000000	\\x0f04ccdfd86d19bb18cf54618fef7b07d1167f5eb13b971c62842c0a78714ddd	test refund	6	0
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

COPY public.prewire (prewire_uuid, type, finished, buf, failed) FROM stdin;
\.


--
-- Data for Name: recoup; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup (recoup_uuid, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", known_coin_id, reserve_out_serial_id) FROM stdin;
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", known_coin_id, rrc_serial) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index, old_known_coin_id) FROM stdin;
1	\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	\\xf39e1e8624cff1a3743c076b051d5a186489ca0fc106c62393855f19ed4022c9feceb74a9f4ec793e8198e15cafd25c339c085f1a2b30a4670f5bfc5429dee02	4	0	1	1
2	\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	\\x082381973e2fe620a3fd0636e997d39609986fe6deb58c6bb794752f37af7f30bf53a5cdc16df383d4303c852383e9b80933613e3c60a51fe53e3f267e2c7605	3	0	2	2
3	\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	\\xa20f74ce889eb3bfea111787193e66342bf9730566cb0852954d89da7380d67d30b9256a8b3e6cdf16489750342c533a2655a707a3aca6714f3eea2abf3df708	5	98000000	2	2
4	\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	\\x58f816382050f09a35f8a1b8339748adb9a35ff997cdde0bcb685ca31a142038af6392d8cfc9d1235b34376366e4b658538a08b000d10711fa5a0fa96ec82a09	1	99000000	1	3
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial) FROM stdin;
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	0	\\xd5e8ba2f1bc0de6bd2819881c06f1908e680f262efe954ccc30f7fdd593a4c57846e3f93df4008b3c526d0cb6afc0a0aa1a0bc34f3cbf2e8fe3dfc2b7775b709	\\x7b4f1304e7ba86937a9cf56226d06f545d4ccd250f8aa0584dcef2c35ac2b18c1b94116fc1985605fe97f6e3fb3357fbb84cc551a6e9ef073c1307d95a2cfb53ccef0da2c7a9e24b561e56cd42e4996fc7b977971049bbee6919f15637f3adb67e3b8912d72f3cb9cc8953a2e81082720a4b1efc5e27388a7245d0251ba210da	\\x1765fb3979933448ec2fdf628507deb3e723adb09e3a3181198399fb64520e622e4b495266bfef4a38a620d85c57be5d13b88f16cdb5fd2d66ff46509434a235	\\x08b219afe4b1679e28201b8bdab4a224c42d1beb4d6328699643cba5bba2269cc38e73d6d9c752096ee0d262a56e18cbd1d2b9133a0b3f5da700b47c94ae539cdb75ac7a5127a1904841b5132b6a042194ff5736c85378024ceb6ae9d420d07360d5ce7955c1c3f1c7ad2c1f2c409391f51a3cedec309789a4669cd229d9ed0d	1	127
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	1	\\xfa8d9cdb214750bfdf133f9f6a6b02d329d3ea27659f2ace8a174da51f7548d0f28e711be0cafb0c2de3ed8367a6bdc22d1e51d94be8c4d3bec731fd55f90b02	\\x052ba647cda7833dac5d2ab2dc1563754255bc97a7854d46feb23298ef47f32dee26be3943cff33cef43df807371a63ccb5d0f54c9a01c98c36050cbc4530d958c0f7267357522df1390773dcb7fd320720f947f5a3f64f55ca9b239af5c42e5283b1ae35feda091ecb56a9a98fba5ec878813a0da7ac0f0789bde958dde9d5d	\\xc1ba8fd75cffaf11beef2c13bbd35d7c4ea0140bcd85216abdfc1daed1c8db0deeb8c63aff8cedc2c44fc3da21248caf0bda3117090b64c484a61099c85608d0	\\x9502e960904f9faafcca7f0603e81c018597096c7c8602c1940eccf062344d63d90d7624735f8f77bd1893a5d2f19b5ffb3bca6bc55315af9871524802769203db8f209cb3cd32bb822be5c7890ba5844bf330f2dad4985ca91249d8f359983694f8f25328ee3113f20a78a2d8fd3bbad3fa8c0eea37f35c311ac6b9d35c7927	2	220
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	2	\\x7fa1e5ead06abcd3a886d5ad66fc5a7cab48144e7a9be88e56bb42353ffda685c79b688f178dc47c73e159e6fa1037a0b63aace6bade9f956d473c86fd5c9702	\\x9246dc134ec39d62c7fc824b1b66033e019247469f1f24a816f8d45adae3edc58d0f0bfc54725636072e09ad7bd6978aa2e93e5c513515992bff2054a4456cc4f6b8f9e87a3d5163ecfb8eac1b6c37565f5f1fa8d953283407a793975a09ab60ce5d953f763f9bc5a316594edaca3ad108ff0dbf45379ffa1c1607cdf6c80a71	\\xf1420200b1b7bc0584cab4bb6cc15f8aa986bac04bb23d9b05f18b9696f4ce94946404c588a7872450821ccd63d7c376726c460f0ae3ecdafe8a6bdcf506f50e	\\x48a2cbda963a0a320daf016fd4859538ad7f7cb37f90e4bb18477638b90cbe15a84d05e25192e57cf61c0b26d77dcdb3a97e6218fde7c7e0f0f920497f2eff28dd2344b56ee12e79bb31c830699d2c2b8732c905fab61d3c6200cdff4defe5c061f84885f9ce3b02286b8a70a7b380e96191c41f02d859671cc9cd16f7fd9809	3	26
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	3	\\x03235f7ea57f0524b0116ea36bf6852f5447f31c60defa9b922afedca7ed41bfdb248e2288837111228a930a49ad64f18fc6b78c32845e214e845da20bc54c0e	\\x430b53a9ed459677484c315166f562e010a1762fb5590e2990f1b84c03ace164c4ab60542f95f96851f9f93c6512a04623da9b4855a10240364245682cab3f82fddd266cf7a239a33121e174b0b0a8a7e2248e9bed3b1a81744688c5c7ff47528864110d31a30512b662be434e2cb1ab4042111fe1e10890d2255f370bc8993c	\\xcf16f06d9cd20e6bb490688c2601392d9d47977ae2342ac15b2f1fef2293f57f964c885d763e1225517e2bfef3bd443a4159a4b5d6f68d2f5a5a4104d4492341	\\x8cd48a3d92f2f1c5ed6716ae6dc5f34b32751bf09e443761461959f2c3ce30fab2b5f45786ae32f8be1046fd49a74fa31fb77437338964d80f165ffe1009830230c17f1ff7d80de88a20564ab2d25bd9b0f226a57b30c67c4dc2c5857d1c16fc91337e6eeeabd3a7618f731ca48aebd54b92af35dfdec13d211eab5e1d04df91	4	26
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	4	\\xd33c196e43e576b831028e8c81316230835583c2b8ddf099a5952d6f4295227965cc54b3f704e43eba3e53cd7c7cddd035fa222c4346e171d27f9ba5e9f5390c	\\x2d7c1fa4a4e853a2eb5a868d9f90252583ee249095806d6319d21604e8f3727f615e236c148b9f917a51361cf60b9c60ab53c8664cbe99139b69769a52d57de7e6b6e18463804a808b98d44806222626cff4f20356394af8c46e3e2c57299affcf86411603f0ec9ebfb0cd81624fb6b81eec16dd60ff7176c4579925d0bfe6a2	\\x53e6b51b0d23d90f0c2c4e5a3df91acb74314297e80b91308a11dadbee8c421d54346f1f2db2597fc14bb09ef28ca5638a050012e17342ee87166ea0f559d102	\\x7878905f27cbe820ca1a1f40ea564ee09dd77e554dadf53df6442382823222350571e7af5c26888c120ccae93341e949b00ebc8f2d71a2139da0e723860f3a58ae116ff6f5dee2d4d0a9544127fdacaeeccc3685b6a8a3f1b6e3bd6f526973d091dc4a3f89c35087db30c0f02a79e05e2dee8faf42b296b0e75f0dd0cbd0bf77	5	26
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	5	\\x2a0cd66fc79f6e72d4ba2f593115d0dbbae167fd8c433fc630df5a1baca20ebd6099bcd50a278c00b4a3a828cb977698726bb794ce51eda2a2ec5df0fcb0ba08	\\x469e097eb1663c1ae07d8619fd55ef4ad0f5d3f3e5f2355c440aaf8b52e5e7b5a112dc875c7ef762563fd68483158a0b69a76788739eb46990a76fbe8158716c1f59f3ee9fd515faff09009dd06ae6f9fb6bbb99420cd3c5b048a77bc773abf852dc32cd95bffbe4a8cda51eab1ec041a838f19850dea194b514fb61f2cbc244	\\x8145bebaf4c3453d30756b7893f31add86cc81cfa6a9d2fb550ccecc5c78a5bee2945e75146ad1b6015cf2193342e721f76b93c0f06b084d278bec58d4388ce9	\\x696d368559569a812dbe0b3df348450ed7d7bbb06c960ede9f9e7ed7a60e063faea12021709ce59c80744b627aa15929227b89f9ce230a8f332c19080fc39435d19959659b917493b340676c4e3599b82216959343586774eb5fc85232796a7aef294187a72681578847184d77b742126f8d8f5d120a19bbda3bed839f46936d	6	26
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	6	\\x2fadf2329dea45437d2f3d5f01132ab0a48638de5a387983ccc8a79b988117f11e996a79db33d6c2a937f509505178e672f30b273453e86922253c7b6df8d607	\\x1be94499e83bac28e3f3bdc409f3ec47456069a5e93414f33484c8e21da5685d0d367e2611f172468422c01c8d9d01b0dd753894157abcddf75f54e5be8829cb60c883a8db61ba12c50f1cf1c44a4e2d0090236ddcadbe331f992ae184cbe5ae5b32c768d7729dd784a9f598b3dbf614cfd910a53c266f060c09f1f8cb98590a	\\x2b85852bd5a3e9a34f49b3fc06e9ebd82fc32d6178312b0d42431359698ff20c00c88f608c5d4f2ed6a38be3632938e3f7ab017c9705bf49c39e823ef941332b	\\x4a7ffaa043d8c45e121568422ca1c8b6cfe7b9867189c2323fb0338f18688273356f75c5eb35c4be75a43c2a37b9301fe470b3a6378271006836ba1bfad026a62eea33e4b3595aa8cab4b81b29c34a7add6b29f0b377a40bc0ba0badcd88c35d76b895a0b39b7a81a9889ee4546d675bfd5bbb2220e21f7679ae6c65f205a48d	7	26
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	7	\\xfa9ee398c15f494316c08c7af3cb41aba59ae0b0c73e872a12cc46702791bf40cfccda5ab0e64f58574ba9f4d31aa39b21796d849497aacdc44bed87431d680e	\\x56eb3240d36e2d972bda4d7642dab487583a7d719e28d86996a17ffd909719e3ffe6a2a3b0701b5f8e61ed65f49a7892d9de03de87eb89180b5be2867583c3acea57f03bb44cc8c55d8c5366bd57302fc8bd488eb1933e1b7fa2bc454fa1a0fab5fa6515f3e97df0307dcb31f65d8dd1e0f41293288e1344c5cba7e0527bd955	\\x8d19e32dd711b30bd5857e9702a441f15c27ce2eb2cb654743a26c8ee79b31e6ee15bf0a26bbcd5cfb64072dade34f87ae88e61e28c405954d75c2ac84fabf46	\\xae1b81470a99cfdd3ef3bc4904708a3f3e39564ee760ea2b9c4824a51bd78cb60971f99e8c6e5e06059ae3a8e294682920b61fa8ad20f46ece1ce19a3bde4047f9c9f9b2a4d4c0af2fa4a329a31512c2cc258f6c59bb3fe376e580343322c48f28b8662d42495037fc0b07dff8c6487c5adce4420280b25b0f33dc064c3bc956	8	26
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	8	\\x4f4bd4e5ba3f18d6484766d18ebf7962bdcd65e7dc28f53aca73732a02d9e3d0c7a6a752228ad41d15408378a8e497bed361b5f06a7c5c9a369528592cbed80c	\\xa49d1816748716f828ae25c00c1363385bace4bd9bf66cd2d1da599cf513db4c796fcbb278e807ce07faa268ebfe140756b34a678375b02aa1bc8164c2ab76e46f7ab527c21975151e9c06ed064b7886d6544f38986820c2c424493b5a044889980439a18bc4e47f6b6417e715449e690df145b9cc9d539f23e72b3ecca57ca3	\\xab78ddca77bba9e35d013538014eff98b09890c1e67642ba9b9fd14a16e3c450b6f399edc23bbd06c8c895b90950c4c12c37caa03b42a829e69170c264aeef4b	\\x9e28e202e121ba3aa1ab0b717dbbff4c4de15c202a05daba1139a4d463d2920490badc0d82d6d2601abfb1aa4efc2e12aebbad8b2519b0ad8b3e88689ce956f98745de428931ea66503f2f73c0d1f7e4840d4d65d6469290011776155767f6c46b711e3a4a237dd2ec4dd1d201542c1e778f8ce3bb013c06789cb3e5d5aef0a9	9	26
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	9	\\xe80020573afe849a44fa081ba50186ba673750cd14f1647d1c7d60fec878768be37998f4efee0db13d1a5ac2281f93619e50cd41ddcb4f4882bf5832fdf26601	\\x381ccde16135acb0d2d5db5a4973c5383b923deec48563651f8481817895341783f5f16713220755bc96c6ae400b4804f15d2a95bf350369795ae4b99c7d62b200f3a3dcdd9cee11c2bd9336139213528fd5d06858885b0491f32a49b9f5ca68751e2286a97acd27282ee268536ecb34d91918fd0cbe0397b7accc36644e8048	\\x063fec6d66ca65b1a522e450d05f0ca1dc08e04c2251094d6e965f8e486b0dc6994b05e90c37ba07f64713b6f42bacb4e5a59de11ae743176ca45dc42909cbe5	\\x57a55bca994e34d422e997614916aba7414ea3793ff102ced52440022e6be09394c9716ac6a9c62e3284b99eca40798c923d5119769aa291968fbf66b1f6bd807230f0c5b79893e8d0b728309924e6f881543b148c92a9c072fe27f1960a2f46cc4220a43f16b617a5c02033aa98e703e3461701071cd5d8253ea1b64ff14df9	10	26
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	10	\\x0a7f7002d96e0df6e5e953c636db7c64e8e5a2be6395bac22320c505fbdc90830875976280f08ee03e15c4aa2b70db05b52ef60c00ba137e40fe42dd37c20606	\\x921c701b174e9af9ffbf74eb810a8bdecb25846ab8cefdedda1a5cdae6c52476278b7ea54b41a1eda8c72c9b60464daf8fa026dc583b9f005b6f6cce255fdac449a23fa558412283b2358f2231ffc7ef6e7acbe5354d2ed220db1ab3e5ed5d16f0573abdcc2f2fec0650f6cee4626a15d693272ffdc15b8944c5dceb9d6e1664	\\xfb378451a80a4693ffa6e859c1dc06c04d0e07cc2368a0e70b56fda4cb1699029d7c378c608df84c79575e3995b7fdd1346044101f840881f9a98f688a0e662d	\\x104a856f06d912556f2de9a4af1ac2bd4f714e79146e7233c889545e860f86b4275f2b517514d11d6e65417334766eb278a742388599d289fe89845553de683c7dfad36348e1dce311a00c1716bf2c9a64ebcded61d675fd25890cc506171c0aeb62df544af9d951d6ae97f0d77752cc36ca82dc944c076a372df87a608a6b43	11	235
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	11	\\xe0c4a36c11631320a520e92b780eceb2d7a78cde77aac36750e847f0d2779f33bfaa2203cfc220f8b7b44de5a605ae8ca9bd14f5db01eb07d79187d73c12000c	\\x1ff87e319518bd7dcacfd7f0cd0047f6bfbf2023df804ccc08df0e3d8b001dbb99b209db1eb62f2ac1ab2efe3287dc596400c18aae422f405cccafbd74f84d123f547b4ddf46c91438bbe4150731a0c22de6c0ee387681fd1d4c983d79de595b1d5cf036c9893c1eb549ebb6080b85a6cbc8c087ff939abdc31f62e6f0e7c4da	\\xb8b02a144236a10e6ea16ed544e990c751154d674f903e67eb526ec7b08d39b34a717ebc6ac614657b4b9b2a62049b29c978958ac64e36d46dc5b069e9e5e9bc	\\x4c2b7a47aec50f042d8f39ab125422fa50ac8ca796030c5ed3be9d0e47764b1f199f00dc84c55cd51f4d240a4aef41c51c2d81a11b1d368eacfbbe1ece36318fbd73bcfa0d889ab5936df7a72af8136d8d1430437ad9e06dcefbed7f95b20675130e710b72eb7fb2206498e35a7bb45f07fef157a9125e4ed8407225d7afe07a	12	235
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	0	\\xa916113299125d5990ede432658aa9f5dea6292373a90ec31887cfa0a19f4c5c6f4d089f3c920d1138029ece4a5e1d2df338e8f59a43dba5c5a534b233fb2407	\\x945e10471204e1d0141751e1ad90ba7ab51f44134f61a28ccf965efb4e95c0027803ba84253b9f7090cbadf326019643206ecc48f37d1671e12d0fe583ce4f08300956fe9be22a1f13936859bd2131bcfe869238c57c53d3635bd4757dfe1ab5470990aa53e94c2e98b0dce377654624ab59849f1cf5a1794c125984afbdf9b1	\\x91054bc435d8f2b3d9897f3ccdeb547dd4119d286d9e9dcb9d443aaae6229b10d1d01ad75a6600a9577f6be34c965e498b12efac78cee9b54e10bd4c286f3997	\\x63a1bee51c5ced76634c95e1967fea332917efba6bb4ce551495fe6c6dfd2329d93ef4ac9f60cb533ce9ec9d47aea2051a3cdd658ffb0931bbe11917d0b3c04cee8bcbb40a4c3b7bd28e1697b96f48cae9e5a73077586e3baef008078189eaa289bff09d11b6609297d3e3d3b2f1fb3ca7cb561eee1219f04495a477aa0112e9	13	127
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	1	\\x0a57ddf389c8a2c7aecfeb1620d31e5de6710ebea9b85efb6399a564914ca109a2b095ae22ca0b674bad70c7979a5acb62d1fe4d6223e9b24cfb9aae4d043906	\\x188bc7aae302ac10ae205f0f65f84322c2cf13fc5d74e3e9cc692923b0e246f3dd805eb5737d816e3231dd0e2a2d68d9c390efaa146d24938554b1d5953626e47c45eb1fc697f37f5ed2896a70957e0120d06849474e9d281dc194621e2152d85400e19d3ac1cd04a6b6e4a5324d38c3da26ad3ae2646b84dbad627e43fd2576	\\x4bb8aa0b4b7d33911cf24b35dfc9bf18010a72c05cb970e7ff97ec6a88fc4b944b5f135186e478f08288565227b2d0ae712fb65443fba181c11f5d228dc35bf5	\\xaf31b7249911c796cdd271d7773949ef5858701739a1a49c1e754a49e6bddc40c0c1a4f7e78342f9d8fa553ca1eb921b425d2b6206fd663ea2b0b8bd2d062882c306bd6ace4fe1c831163a15a0b02fdd94ca8aabfb96887e6ce362647e8dfb6675f9a7d187b1aad8b0e9755a479cb510d1cce5544b38f1820674fcdf27452f82	14	26
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	2	\\x625792de0b2516e105616e8d7ec8db1f08a7a3bc727d487d2d09cc79838d8aaff009196f9f5134f17a502ba293a35dd110a0fb1714cd81208f478d96b3006007	\\x80faeb764cbe0a0409760b6584d178f2246d2d99345823fe7b356023459e60c9264c099dbe31241e4e1450f20ad7845251c49ea499abd0a49763817fdebd87f1386db03cd3955a1c85deeeb7ff78ba2af9424320118088df6e52c57a873d2799b31e1204278e3989da3de8604875bc16b4154ce74551a2cc02e48c217c6a58cf	\\x51603057178924dfa0aac646cddbfd68916be76d035c66252daf7ef34301889fc1e92c9798fdf92ad694a90462acb636db378e18517119f9250cf36b093d9ea2	\\x8c2ea15e84d2f001bebbc2c308865cdc84fd96f1868d5d09786e852fb98086962b361dc0b1ae517daa8018717b1b2bf734b8e871fcf274f4882121bb7b2673e78695ebdf64419d66b0394d7f2f9b8b1b045875f634c2298578dcb2bb3644a9e4fa80fb6a0df44f0a48dedffac180f6b798e2f416cb3c4696c1ec5818a1f60d17	15	26
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	3	\\xc64eda05421e1590965f3b27ff24b1decfd3109b8cf4a4acb35313062e38e184b1ab4a431b4e83f4f243fee2ee0b7fb68cec3d36a5ed4a504d7fd874af8e1c0f	\\xbd3d9c56ed5a5785a3166386698b38c252a00b22aede19da540e7286791cf424ef2bcdc79d7ae3e23b522824b95478f41f5530e19dcaca17ad7ec79512f4aee36396eb0cd6b843eff9cf5bf1f14bb628c2225d2ec92ad34306555a847272a71cd327b6fc4231d3f8cdbf6e669db71279cfd6413e2021a7779cf46c79dd9c1fda	\\x00ae1e2bedd1c7e71e10d3b537d1f1cadd1aaf60bb345ec9ab42d42b739ff2c32af49c166417614b938a01d2fccde873a33c2e67ef2f583bd4e82e42d7eb812e	\\x894e42630f69e8a3cf4cb2c35918b2fee5d41f4d941e2f6d660b230f962e8386b29194e36829cbeb429d6426b1531fe15dfe1d1719102c1f7fdfeae1c63b43e86604be1bacfb203dd5301bdf6962d76704ad83635697df8c9d11cf12dce154d13e568edbeaddeda4c735c307b4a21fc0144cb3c7310a3d2cbf48f6aa025463da	16	26
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	4	\\x0dac195bbcddd647616753205ee56702b413b0eaf0229d9bdc026f2eb6db10b35609a9e90c9d51e5935082cebb680c311f15a89340281f441d3186de5fe01907	\\xa6bb7ca7d906f9b4856bc22f7daec306ed6fa0a3e034f9743a5f01b73f4d4606f114c5f11bbe5704e65d3b56ac6740b021d1bcabab11ba4b584156966ca947834eae2c813245cb32f3be1f023961429e94bad37b5c9132f03c60485c835546d3377fe29a00857e02be77bd148b92ac75007e574e3f6dc8c0ad9402e7dcb7f150	\\xd8dfad27a64c0a31eb926c0cd0bb18cd58bd0f33f3e071894f88e480c403df0cc7c1318f17cc0716bd764c8368077497e3273fc22dc5a440e2426ed10db4d0fb	\\x725399e0cff20f412ffd63b96b9e686d207625de1933bf0ddbd79f3d2aec75d93ebd631ada0e964da4e0c24b882ffdfb92f43e97b412f8d4c253a6251eb56f12ff9af9bbd4321c413cdf44d1b047b4d5d42ca2aba12b2aa0a5872fcc38fc7b57210ff8014381b6d196501a74974c15ab9ff4550daa9e92fd4d7b0a1bcf84a66b	17	26
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	5	\\x2d4b9c263bcece300dceff9fb54fcca8ed6ce1a25fd5b3ab897df6f785905cfa55f7518622e94f8eb3410911f0568c9317b3209688c4163bc2eedc51d3086103	\\x5da40e2e6ed2d2f9a02c39c83d3d0d6d990464cfd28b4aa62233149de53d9cfea64215c5281a5600c1c5f017f5aea23bb9c03f6494e9629c5696c66388dba405f72acbd2f281500197474126c37e8fe07ef1bb739157d040045c1301e6bd45783b37a8726c3e64381d78f520816d270f00ad07bcd19bdfe3d3e9a8a1f732f3dc	\\x2f6a19781c8f3149df5d0416334f42edd10c1b90dacdf6e29b88f2282684a64623819f639bcff244c331fd6d336d05f8a84e94ba18711755d94b88d7a9185ed3	\\xab1064c828066b3d2b9eba12d250cc67d433531c1a7e2f941c1a21eee7cd34c3501c1090169ef29169f1760b705c1ac004191704a0dd479dfbee93df000adb604a1dce2ef5344d40ec243d4418017916976d038b6ba2f35f80e73de6bd4cf75dd60c74fa270029e1eb86d9b31e914ee75ca0da6a9dcb0452b59911676ff0e2	18	26
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	6	\\x67264aa5d50ba09ae9f166f0967427725577d5bcc0b6147a5a8042436418bd6154bc23e024832f9c538b63675a5e98599e1e57744a4f90024defec89cb813505	\\xc334cb9109d67cf513782487c9896247315d21f13d536a1ec1fff21e1bed82dd4eab0b1c894c811678fe98236c3f17c2e1a915f4765380459fb03a9ab74e94865e6843c4cde0adea19815fe31ac05973d269e04ae74294b5b26b71ae34a863c30c7a2ccc7a74c2608d3457968ffd7819f3f35b162e4ced9f19cae89a76a33117	\\xd2851803263b7ef91ebdda9938346d0441245570852e2e377bec971f5e310a794464db056a1869497775f09f49cef2c16bd59b2b982cd00f126358d59eb7f6df	\\xa40611a1be0297c0c0261234330e75bcedb6d68678a684a893d5f9c2d55d21aebb7dd7555b089da81ed498c7ff932825f45615b1fd9f34661184ea730686f562707144614c49a4b4610de447cbb7fbe4e141863153f18cdfef1914d613992ae85ea1482b1be8ebf0140ae168f7cc4ab6b63eeeb0619dd75ed14f4a7bf6efa0	19	26
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	7	\\x619cf7efc457c8698f2db05dcbcaa9bd87464c0943fef8fecfee38d93efec44f1a13ac0359c9b09f554ff8df192b0d92bf3bcefde2801c2100a4415d585edd0b	\\xa09723253e74f83cf289198d2e1d279514bd1e73bbe1d8d8a3bed6be27524306534613200b53b5d2a48d4c637e1bc4461819a7459ab1ddf77e4eabfdb28cb75f747a0d6ac1529edc497211d47c39028d49252ef7040d6e141b4148d824d6c07175c17fc69938cadfac4c512e966507088ab0c350ca41e0df6de603a4d5dc3ace	\\xdffe81e21718bcc7f6a35387fe84bdc1d4bbf72fea3ab046cd3c05bf0887761b1c6fc1bd5ae9c4be3b9eda2b6bf2123538e91fbdd6dc0b7c05fa6b14610257eb	\\x6a3c4fa1e49c95e965864934d9b3dcd7e5ea16e329c55f5e238f035f69992eddd105dc22e9ed8105bd6012860dacdad06ee41bba4b373a0144d5e74a6bdbc69740fc753bbb3042d9ca9425f22d1ed3726ecfdeb968b6bc679f66ef58103e4ef09be095c69192fa389bc61a4ec2242e7557d2ca9c384772ea6b2763f59c4405d2	20	26
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	8	\\x8fd292b8c7226aa327237b5e03799a2eb6ffb487ff72f0d4396dfa99333ec79ffec94b95ed01b50d95e7daf2e5f8db2eeb872710c68ee1a515c71ed02dcadf0b	\\x484d05d2d58c20a3565d0373d413fadfdc3dd090aaa7e8caa2dafbed5f469bf1740c7e464c63e84170cd4ce99a91eda4171514cc3db79e2b9ff8ffe07c037753728c582a8b1d7f7170b12f98c30b091aff246211b6462c4f05eff4c9680dddc754db350fc3a341a60441d039f232ac5ecb5e7d6945cc28ca33fa788c751b4a63	\\x6889dfe4aeb4fb159efd3df73e0c679d93d623351bea3aa9fc391d777921893ee8b39b0e7790a66084e8a1da306a9ee2500eeedc05c342f3c048225fa56d0dee	\\x556d50e6da230d812b5bdbd573eddb1d9ebb0e0102f6dffbce0d7f4d7cd9c730d190d30e811e26e68b3b06e39a6c2793831fb10b1022e52f51f0799641b7a0cbf7239fcdac207c7ddc1dfd3446e0b9d17e9d419af07d81e79508cb541b454f39bc1f830bdafcbadfd1672f7502c5d4259a3cf65c51dcd904d8062fb12ad65eb0	21	26
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	9	\\x7adfb6266fef91e6ebe3aa5c39f3ae8c77fd444f6a26ed2231c035a4e86e863928fb9d8f66b34f4eea8d1a0903b179a1e4121a0cb2762af1563b790b5f9f0c06	\\x3aa86258d560924e724081ab20e79d2e77a172a82957cc37a49bb80842ca1890d883ba050bb28c867a6b37e257c50fdd28cbbe4a47b0bf4a891829d78b00bfd7f2e63a4ea19c3ad989a4ece7545e056d6276de3e5598995213515bf76b4405bf1f7b6caae45f785d35c27a5a3df2b4cbce12d5518ef33a3fa7f1c041351e72bf	\\xc8cd0c8deb3b9786161cc503aa824768493be860ca532266e8ad87e9a29acaa95569d2259b6e008d51e700e7718a75d849b0be33453d77346fb88de67bca95ba	\\x34d7419c09a1ec45a61d75434891ed210ccc70ef6360abcfb5f4604d0dabb562fa09d1f5195017ae8f4319b43c6d594afc4ad836df6ea2d6a8d958e095bf275204044075d8d081e53facccf7c94f1a09245bb01ab854d225eb7f41cb7a5d2e8d47a5f2bc0b02cc472b2a49b5a7ca1723f187d0253e475c0a18e86f8797ea4575	22	235
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	10	\\xa9f7d698eae14c46c2114439ad883bf477ffa162de180376ea00069633430ba0f4edcc9f0ca7b2a853e0f751023aac60401ddea21b71fb3807d6fbb291b4fe02	\\xa8653239304f4a7fda7169d03d88c14d0ab8f68197984abee686727b73bcf12bd5d581e6441e36a607174f8ba1302b6b0cb65fd40088045eb7a4eb67a12749af125d8a3986a7ef99922e569bf51697c5f1cfbb37749ece87ca12dba58979355e44c7dc13da213edb0130d9be97a708d682e7798e1abedf918d918e6e511764d2	\\x00a084d12cae810492767447adac919fb4abc0a3911b1d006968f3f0276a418cfd305c32ce8322197879f3cea10a198d22eecc087c5bd579e3f10b3f8936eb11	\\x9239ea5bdaf3a02519d525b72d625eb0cf858f117bf3e3c4bbaf0488fdac32c7e3db5a9325f711d2d59a18bc7b58b41278a6d31ff5f5e13fdda500201520177ca0bac8eb3cc005fb5fbbec459049c86020dfb0a8579fd07d95f1a0c99328c20f780b88a06e5d16966101f447ccbc9fb7f27240462d0c13710022134a167afa10	23	235
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	11	\\xfd9f365d76245d7411383c7c9b7f23a103460e692f7fc36ed2d06bc94f307d15c4e6cd6e46f8cd6f81db6f5d1d6e374cb372d964464ede51b0d59ebbc66fd80e	\\x7dfcd3aded7e627027fa2af7f6a7574b73688c5f25c72a1bc41d86ebd9da387561e1d9f738b5217e2ca506d326c1d0aa71c2b604585bd79d678e4de40ae85f76295dea74ba6714783af1942967978f9e76807b38b43739ae71365f9079e52473c3ae44e4dd9a58ccad4e4aa95b1110e95e601cbe2eeed4aba013f1e8758cbbc9	\\x37431e5d38a61c7009ce6db730d5011455fd212ed4a9f5ee24698d46ff2877d7cf4d0bec147748ae201c0a0728ab31de247e51632adf2e8efdb02c8772e8e2d8	\\x2e0e5b3c01a712bf17589f9efe75ef48d415fb95b86c320a2347608711ed8bfa834a54346fa514f90ce0f95086cfbd0d8be92ec9944a9d3b4e6b9a13607fb1a0aaf96d8c12b86d19c1505675d801295db11c1cbac364206a010773d01afb61169e2f3e404c46284e499b4dccb4362fb5a9e360089e4631037475e0dbd2384acc	24	235
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	0	\\x58c67dae87fd661b1aba8cbd6664c7ca0c31fbf6db0b5d6b3a76bed6620a5bc775157290803c58ed183729436145b1650164548ca171a8dabc8fb0bd0bd9ee05	\\x26ac6ad66b07b3a1324c4f76e10cd47066aa3a69ec6c6ed009f12a549dfb6676a5edbbf792fa2d11d8e629a5ae4cec9b3fbf7aeeb2538372c3ffa4adb1440f95706a8188e53e9170ce6b2ec60df005a506c0a25d00edea8b8326c94c681dbe6b43c15991ff1dc3ef6760eaed30a2f838ee15ce35eb9337fdc78208352d10ad57	\\xb2f77ae9b3212bff3a27905b7e10c1609e019440b6c343e97c996ffd70598ea5d0ab6478ccc9c009bfbc5ebe8b4094df11982779668043c4779763ee6195c647	\\xd1fb66be89b9bfc91ac8be3c19e9dc4de81ba2258571e7548f3323e6272e4e7e60876e8288a5c78aefa258c90a22987d81e3039b518e687e63c0550bd288c4b3cc102f85c6f7032b318a41c78a66238adf67e16cc55072dda497152a53bb166b911f187b8b166e5bbbde658f888c5203d634a1f460512ae7658c436ea45c804e	25	105
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	1	\\x1f08b83bb74a53e1c31bfb9be6103f330dd56b22768af58a3aaf7fbd71f1f691eee0258c7810c3b23d1c588ca80b0b5273214f4ee92cf1c18f9dd3fa530eea05	\\x0da583c33eabeb605f7cce2c7ef5a8e5a9013b7a18cd424790b65d50a7df2ae4c8c809659529bf6639693c43523100ef899fe57eac59d4d64f097a6b9625fc84c37653906222b39fe471ee6dbb3f79204e6279bd2a22f0b1cf72bb0dab269bbf2cb18fb64d874155c6bb02a83f5b5fe71fb7418142915ae736832609751de800	\\x2c009e23cf60b709fdfd71d6ae7d4f75b8d3c25c77d216cea6b33f8ab17ab42748539009c920f97bb0d6d5dc6e20eb5c35890d44217b19357e69e005c1ee61f4	\\x30882ec1cffb73279d193a32c9e7621f83fa61f0833432ff8063a0275fc5f994d91a50e2887f1bca0b213734768b34539beca8fd16e2dd7114cff4d9703a4492949169fd0607a1ce044c350c0fa154025133d964fb1947f25c3db4920490b9a0236480ddda8be5241601cbb564ff1a463fefba6cc712feffd0da11ae377121c3	26	26
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	2	\\xdb8b0a08206a7ba84df4013f649c62acf2a69232abba9df0c9252a69d90424aa62dd9e1a7b09b23f4109d728b8880f1b9db0a60b7b0d70367e0d85947411cf04	\\x94227a3fcee4afb549afebcf6b251dcd75f0c2bbe24c40ec94c306e99bacb35acd04a6b9514b7e7933caf2ac1449df92f808b646de1ee56d8a3d1f1bd6bbdd2a3f5ec97526d7bdea25d405229bd95662b05eaa9426afc109b27f795633227b24d2b73fb1d983c9ed2355701c5494c6c4e6f9b6ad895d28f727e0011ec02e07fa	\\x14eddb99bb657a5655ea7f2d4e39a945b768d36224447537169931b5244ff1930ca71bd6180274629a2adb39d13efa8947e624be02ee9f689907fc1cffa2a2a6	\\xc78c02e2ca1f5a705e3518fb00dc3bbb0daf2ea4a794f636c66c8d484b904bc91c9210f8c65f577680c77b314278f3003dbb55b84f00e9c49083cde3d2249ee5d24429a878eee8da965fc47a66712d3c3b25f41c52a45a0f914e5795670f931127706d3fc607873f49eaec8092046d5983797001a9f73eb3ab3e99d26f6b159f	27	26
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	3	\\x9a0133d60851fc7b3ac4101d9c88973ffebfb8aa90f41a98d8c6951d83a635a742af4093facb9c53b24563586db656209c7dfd77fd0645c77daf6257670f4d08	\\x5303f9ef834424903040b269d0197b0330c04962c1699c01c00dd8795a5ced912575b999a8a636b022e59d8da0706e3b9268c8cec2eb2e952a2be46c379fc9e2682918cbb474f2f98c4bfd8511846e54fed2ed2768b16f62bd668ccf58fbf068be0b2a69806aaee6e22835a914a7a06df01df5441b6fa7d20548269fd82c83b7	\\x1d29850d344e7ff56ce5109697c232cc8085feacee1a7059c385605891f170a41da634dddbf16222763e824b74e140cbf5f4023ec3c49b763db67e78c359bfc9	\\x079fda4ed5f9c8ee9b18b5b1e6a61ffb696e159f4bf8e8908c94bbafd645ecef6c2d2a9e91c48e3d5f0e01a6121c1d876663571aaa07189a621320881a057f461d3a8a1884dd4ef65f30ed27da0a44b4f9355f848ae5bfb037c3cc705d28c8997b7d3276622c51aba73691a29698a1ed9cace1f3f42fb978647dad931369f4bc	28	26
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	4	\\xa09a635c830f7a7991454df04ed0bf6396c2d3466bb837c310776d370a9db80424f18df93f1a09f5aad5b6cf0efb9f6be2d936a3a8239071419516e370847607	\\x80d88f3c62200cff7a117d5bc969a7c9597ac52db9106b320401d8af7f76118a5a2e4b881dfcafe8ee1eddf41e96c218b25d629d15ce9e088a17e6c40ca478e14f5b6b6b56348367df5805cb8e137e2a684f6c6c904df25db1e3b1fad4317a4b695de65090329a9928a69bfdc2f3a5d50e655e98eb8113943df86875394c92a8	\\x382bae75cabb7aac0b00bfd84b315e3af35c823b425c58353a92e7cef94ae9a16ea58688d0fb6a86108b6ff3038d19f844349e81a5e10a215e7f3bdbfaa1f211	\\xc08651f25963b0d4eb8f8c2f821cee9478605d27724290a8928a62e27e671586cc263c6a6deba4d5349a3a601ff56efc02de078a1a475cf6e388d79362b8845366b38be5c9a0ce4cfc2dbd22948fa0507435662f24e9fd184c5c7f8d03602255357d163df325fc43207bff77da610b2aaeee0b926f9f46e9042ba5758508734a	29	26
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	5	\\xa47f097ee81661a7902c6defb79067491728251b7a5e0c4201dd2c03bc947b475d4d00c68c33b149b417dc223d1dcb728545b15972dc45ab51ddd4c9a6e87401	\\x0b8f03d7adf23d374d9151072a5e2c5acd558a944bd298605a60569a664d561587ef6f324a8b22b50338b3721a15c913b5e716d229ea5d7c0dc84e09a339a5a6da1a3b0339567460bba4fae3a87f2b23a19a91fea966043e8322bba64488c63e892eaffd18f26766e4b6f99202120a866a410f6cb083aef11e19ceae2ad79d0d	\\x1c4086da054564cab405189eff5a699950d04c411ea6dad99a1a5b97bf6d174cf7a3a2bce9c96a7ebc9910f6a3e9137a9ee7fd9d85487204e94d72b2d0ecd28f	\\x7bacaf9df7f07b9c25cc2fb3ab9aeda58ff6be5736f5ef1f2f9154cac57bc2decbe53881f99fb2554fe43aeb943735065dc0793e9d0e45dedc083844bd86fca9515d40017f4ae405a84826fd93d9ac754599f6fbba1a355d1f881413d649090d53701b2c41d40f5414032e6963b1d35ca3b3d7deb0f3b4abc9382acc6428333f	30	26
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	6	\\x753b899c5b5379981937a57fd3874601a47647ce50135e789225ecdf209dce218bc8039410523c5fe380ca6c9acdbcf289fe3dd00c9c4b2607bbe62715c5780e	\\x8e15b0d115e5633dda43ee78038ea49252b5fb83065df7a01816df2d104fabd5e5aac75dbb9f908bb95e9c1556903933407d8bb1f591087a23c98ff15b3b6dd6a14c4765c762c4965fd6b178eb8bdeb4065a68b505ed5826b33fd1fbc0e42c856446293f7f7c6b500b2c38375e2469933207149bf4595a898d1500315c6ce48d	\\x470658997e1b7598092f1b0ad2c7ed854f6d6677bd0a9444c66ee497ec887247d2f4c331678a310d8a7f871a6e6ff0a80d2ba2c5acf8ff6e8a5cac5754bfb880	\\x8a7b01dc9714075e8bfed668f3e1fd416b68fa18405ab2d539765b8eb4ba71805bf775f21cb946869aab1e3acc0cf3d17371632171ef23df361b7bfcaba60a0e2d46ef3f99746be44bd74f8a142d7e1fe59ee7b83c87494e53fa134dc5d366c3f08abe56f026f4eea9d5094696e26a49de1103a55f1f6dad262d52d432ec7684	31	26
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	7	\\xf36bbb7cd6f1fb2539233c1991f46ca28dbca8dea1bb9c71631de16a45448c6c1d35e0f55af35e154898350ff909d991619aa1c2219b5785b3efa4aa140d7b02	\\xab7c01d7a32ce9537db91f5557eee7e3cf6f65f739723fec2874998a9e365b46de1281cf1ad3fff62263ea55d5ba2ff764903782fda70a1a632ca4201f6d50d295d27f7fee8bc3bc6d3688589249425abf6eb2ebb55442b4fb36a130e53a6fcde3d4b5a9e5bb242c82389bd7a8612845bda0de567dee4ec6d016b96392f26eae	\\x03e4811ff39f7163d30b583ad49906b0263676a0a5ce0ae492ed0f8a3ed2a8557c2947d606e5b638b9b616b1555cee0c12efeeaed9b089179c7812fc51fb6ce3	\\x2f28e3cf869a4bd90cf7c7a54c658f8460afc6fa6cbc2337a1ee64732b85a71c98b9a782e7a70dca9786299131d466794fca26dffb3d7ab788d487ee0efd6c82e19a23501d12e022adfb1a654ec3adb61a1c4a2e3f8b3fd506e027acd9435fa79863253bd84e93afa6e4235551c37fdbbf0577723099fbd687f93d8b00ee5420	32	26
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	8	\\xf77cfb32122d605c98fdf553a47997fd968ede1e1f67dd079dd3f8a2ebb1c2313c19434c6dbda0d6d2fd1b7b49476f4bde268459a7371062e3e87ceb584bd20c	\\x2f57084ba92184c7932cb188946a956b89ec500b3a1cae470d789c5b2ef3eb838993fa82238f650f301032f1eed4d20a54c2fe9da928ad16add6b7488bb70d05f1ea8cb2e4d867cd92086bf32b219de372d0e4be08aa5e0d550479da5901fb5c39404784ffd981f5db6f3552e844661052ae9513b4a5aa68da1538dff9ffea0c	\\x388445eb18113e5c42787536e41f889e75402db9b9934f0cd0b261b0e1599be1a8c88df371336b8a0a1e846d0f6554b142faecfe8527fe2705dfb9168c16445f	\\x045c16c0ca0c1f4cd88dd69b6a03ca30b6a8904e69bfbad1b81baeb17cb05bf71300e6e024b8bbbf9ce72013879b24908105ca70ba365f8bcdd6618ec59332c5511fd0f56210b5c256b0f44c27dfe307bb786a6c80caebb3984117ab381ddac452b0750393de34c4f3011fba6af7d11e1d22b78225baf4064beb96a5b236f647	33	26
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	9	\\x9a086b1f8e6dce397881c8083d097ac3ed435e119aabc104e147ba8201cf87624d86edb97bcdfdd302fa9b16f744fdbdd6f3b848ad204eb00d88ceabf60c3e0b	\\x155e00d40b7760a5921dd6d2eb05a8946208a3d402a5fca5df69b184276076eba4196667d2aa7474672f2bc11f0fd2ab9d84cac3b8351737b3b464d571fdba261ce8b8aa2166221a493c7dad6b6b1c9dccc286276ab38a82fca0157fa716a3ce4c954a5e318b3ecb934e7af60756b2a4ac4efe4e4902e67c09217eb22455132f	\\xf3d18b0d868785877cacb2a88955a944fe7e0e093ab4362382c50867d778b59aaffe7992f90a5fd956379d946b19539118e638ad9bf41235478bd86c9f50fef1	\\x35832ed95a9f5a3d33306b62156e7108e49e9e5b33b72b3a250af32450b00a26d2b209e7a9f29bd7e44715c3620547d904dd0b1159c86d5a1561989f03b1f5859367f368b4c346ca2be20dff82520bc3c80b68ac91b449f799f7a8d5f6c3fa0aa91242854f3a001211c70182c871a1226ef92bd76d0b966f6a5b929d44724817	34	235
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	10	\\x80bd148e0d61bf975a8dfb7c4d6903badd4250032c919420e369c6ce4cc375af9e1eb09d38f3d43f26bc100aa3a9370e968dde1d377ca8a8c91a9a6ccc727605	\\x1177eecf307be40b7062012e349dc3d0c237f058019409f77ecbf79121482791ff2b40f20a56d73c89844dbf23a49a597a891a35397be60a86eb2522936bee18fa5d6fdb56a0c57f7ed48a1b6b02a0dad7ee957faf8cdb112ecdec708cbfaa8be9cd8ceb5b2ef32c70a07035b2a7e846b79fd18aa30ade01fe4aa50e90be0142	\\x4ca10cea8a4b96ef2bd18d25e9656bce23288ffbf3365c1724e8c3f94378a2b0116c2a2238114d94ee85839f49bf33eac1cbe61227a9f3b03b898c57b3ba0c31	\\x27caa0cfb51ba116c0432150ebb20579261af0444e984f0b12098465e5b1a6be1d50d7e494db52c501efcce5a3e3cf0ecc24dadd4234748db1abaf5e483334a8a1492681c35a0a224ede66b2e8f8de76a6f96885b02f9a2fd03d28f5f55624397d680cf99e6c42d9faa3e3d660ab152007cd52a8d87b1c74ebbf82801d3b58e9	35	235
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	11	\\xa24374550e83334db6237a1976379863051eccd9becc21592b8010ac3f9f51e87742959843141f3ac143d2985d76fbe4f4389ee6c47c429877eff3d5f4a41905	\\x9e080867cd1e6acd65b93a0c4c44d4a6630dcd80542e7fcdd0cdbb44a5bfc5ae1be69e2890cedfdd0e7046bf4c229b893a06d9a31573339ea4bf11c22301b42be3496bf45f9b7335acdac7237176923c59e3f1bcdf3dfdb86b5078ac4f679f55125a52afa95fe36aa72d1d71a1cd32a2336137af0050906233dcf9f52fcf7304	\\x10f7d467cf69762f422e6ba8961c027da6ad0820a5bffd81423c59247cbd992c60a02668ee0c1f01449f4b0d13af1aa1b745e97f6bd23ac3b6ad7f80100c17b8	\\x28834768c7bad9a7569828f6cc47079c1dafd88099ebe6e26bfc75e82fbbdd0385099b49cff30c1c64f092123ea1ebe012ad1c92ef39189ccc164227edc4169ca44ddea7fa446706632bf632eb767c73eafe7d022bf8dd0c65c4cd9566708ca210c03990e67402c102da8d7cbbf13e4be76521c871fd5f8fc7784c3e3a574df5	36	235
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	0	\\xfd31e57905e3b7a27480e867c853ca88417218827f3b18b7c8fb1c1b2b1a7bdbcfbd4411f444cf2f01c14034c21e7539e63ac9df10539998be4c5074302a850c	\\x6281aa561e94d4eb7ca58378f4c6935d2da6319cb4757a3f294befe4eea65dcf5651b3767d6d9465927e75c1ceb81b841a95fd01d867dcc03c88274ffc1a0c5da24cc4cfcede9a87bc22d00c9bc66e69c475f94388ad9788d1674fa66fee0079aa4ee9bc49d3541bd1db3adb1059a1d1efe5516ea0934c0f358fcbca5be3f45f	\\x75b21839cc1d9a8cded6f78397c42062fb3193e7c92f3417c269286d69314865b03e7caea97e4cc080474a88cd740d9def66e403f0ea65868f7920144c24a6e0	\\x0a3c284d6cb57655ddebb310a3261faf8d3b650509914a0a80dfd3d2ccf72194b364742f99e8c1e18c197b87328fafcff36d21bbd09df3a96440dfe24612a7f378afdda1c98bf2483e82fe71b182243e25c2b5048318a4712c1d5dc12928e96b4e21128f5abe2ed817a0c7efb58c3a833fb369017f9e62d090a797e84d57ab4a	37	220
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	1	\\x50f57e609bebded9cb230aad072fe7558d7dc49db42d4c0e8ac34a4b17f0b0a5883b2f5238cbc57302c7344a40a4de80f4fcf6144f9c8b12a21a16f4355f6e01	\\x5b2fb0f18d52f820542bb10187862cde8795ed7f64fa8dd851e2ee14c8b34a4304f7e1ce237f40dad6795053127404a31ccbf84a671c772e69aa90905eb29468e750078f23cb165293ecd6599027e8a53309ad86ab95befdbcfb14e1839e3d79446ac384307eb0f8d18d981de5b1ae9e2f621697429871d3867f5d28b6c69f94	\\x1b19218ef7ccbbc7c5036f0f9fbeabf86648ad9afb1a532905ed0aa55fc98dbf356dfd528c000a0493e1957d9a244b166ae7eb323da1e7a25568da7f1d245a72	\\xb09879e71fdb598017b68802d000451dbef904e5596e7c1939a7f1149686ca19b6a43cee62c139bdb235325c70d4344a54719b6c46fd4a657d465ae0a62d9487ea3076006fe8321688f8907d9b238e4d20ebf0cb5d5bfc8d3afe5b834d8784fe1ae8fefe0dcc55b3d3d9f795f4b74689d4ef6a4f7f4a29d3403b498fdd870b98	38	26
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	2	\\xefdf3eba44634e553ce9ce344fae915170384151f7074e70b0fe7b9e605917c6d83f11f688fb0f2db99f8256b00cd93cee25ba1703a7b2f121e572f6ddf6780b	\\x6dc0c56bf2162ee2dd4d305852350ae1f6abdfc78b10d1d30a4e1c4707dd7a841129456cf5df4f9181ea2b60784c60d3a00be8367fbb02053f355a3f38dcab47f1ea83f33ef3e18b79c3a8420e5ffe1de5189d9289b4958c2c9f39f6e656728403618f9895da9a562583ad1a4afcd7dc1f12c5a99f82039a4e0f933e0d430000	\\xd1158c35da7dae564e6d8d1bf806cf1ba212ab28c1b41dd8390f9a6d8c01e35e76ee538b5bc2cdfc27c73682d7edf5a6710ae6b1871954876ec9648d752de4ab	\\x541c896ff34670cbbb21bd270e1792da32eefdc5bdc12a28534c3a4e140460987b1ff58c584bc512ffcc8d0da5b94364023d792016c736e269a038b3918659d09b32296130884ded7b38b8b31a659b62cb51d1c4974201806468ac3d4751ff1ead6d77affd2222a39d641fcac60a5ef59fb872f6aae983001f4ca1ae0fc6a194	39	26
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	3	\\x4b0622b798d19c6bb5f0b961b92a3bfda0bc5553c562d999863153281f9d2bdb11366d917873275f94b52505294e0ab6cfa06c8d25f81376d6c3deffc0943e0f	\\x3491793459dc05e15cfff0d4c8aaa2776158b289342659bb63493df4c11665f3d09633c4ff4c765ddd1531f58d8e93e3af6542ff20bf1c835322969590fef362ba825e84f8a680bd5e8c79cf4a35ded8778e3f90759d5b3205b7237a31094cece0a42e705617daedc2358fd7d928b69cd7fa789660f8ced53a39155bae8c64ac	\\x44d39a9fa478488063470712eeea123a0a04415eab6476b00a52b911b7ec865140ec5e8e1b77681eb596906238ff9925f5c6ccd33215d515989dbc1b4a894a4a	\\xb10a12f5255f7cbb9d0677f55e8dc6d5905a67e2f8dbc16a02e9ce805d325183807bc741f1bd0fdb9597982a14039e6adc4344f77316835f66f3f44f8985629233865373dd686a11c1f5c2541736a7d36f14148c9b3a13e3afcc6961732314ca23480dc43ec4c33d3bac1f2b45975233f6f0df72239bfcf41ae4917c70061efa	40	26
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	4	\\xdb1a441c83f49e2b5545ef3107fd1b1338503c2b48bc78b130460a59a06c4288afbef08ef652ac9a7a494467f6ca3b7ee6c7f95ee8dbf24d7534bcb53e15f100	\\x1fce43e679899d43ee0f95832a2955e370e4a900f755bdcccded98720027eba4146d059f0d70fe6c4d48012d0f4f6597ee77e8a7dee7119de7a4ad17de2148ec9165395fe87a4b91818677d6a1c78441501db00ced8003538013207d87a81770889af629f667ff5eccb398d67e7c5ed163cde811cfd29f60d5878bfffc743ac1	\\xd0e97e26dabf0a8ddfa2c0914c1f5270fe4217e7677300c98e3f395e4e4f57966689c939a28901ec74f879f93f47a279bd25011241bc3fb550184d26f809ea1b	\\xc80528a1fefdfd51f08ebfa0bbf9b4bcd9f53b113f0a68e17e52d1d166a6a54c6b111a5cb8efdd85e112baca38367504f4ae6d69eaf48fb27cdbfcd249febe13544c2452968ab234eb53fc9213640c9a8e89f320d372a3e7aac075d7e5c5c766895e55ad156c10eeada547ec0f855f72db1b91bc00ef289cdeba9ad56ed7330f	41	26
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	5	\\x62e23bb24285a421c38b966978d09dd5bcdd2270fffb060b4e1a5dc40ba2d5ef2347ac858dbd2000e72bce9aa3b0dc1615a2599c01ee887b12df94a4a4b9fe0e	\\xca307d0c078b372c0dcd0df6be487ad4623f4a80cbddaf7ad036d39ea9c7bd21c8cd7d89137bd5cccbf92cd17d7f9f03613f9bc0cab94cd4b05414d047e54823aa4cae24e334d1841edb1f3292bd7fd6d9fcd333c6e0292ed931f551c6f122abddc23e72ede0457c867754558b9cdb7a9b676d84bd1fbe67508b112e8f3e519e	\\xd506791b703e844bc02e5b9a4817324ad47ca32717fd26a09d6f6717eb9bbe037b5313ea57b667e7bc72b0e67f4c8f9c9780a58ea2097bd5901aa68831f98ce8	\\x9e26d03706707c63237e8163ccc1548709820fde27af689c1c053a215c3778d975e26ea24f8e2049d22bc3a6fb52e1764144e87142a587f68a494578d6391731ba66c63fed2feb88d100a01b9e769a5e18a914bba8e9b09840f8deb5da52744c388c842f6abe0c7a045a7c7038d08ff488c6907d0a022138ff8d730bd3320f6a	42	26
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	6	\\x9e24adb489107c796c3c93ad8e303c12d1e8c1d59fe70c7efe95c5cd79c9f8478fb611a13550c8bdd0ed50076820a116f50ed171bcdae7a0af7469657a7d6103	\\x8f4c7573c597f3b231aa584d4e9b23e1b322ab0386ce926888150fce12a46f56ce6083adfcc7432c487777def8b6e69d86d313c2b2dd4753d1bc403f73c3393a2585c6d09352b8cb3468fad34690146e3aa25b5f17397603722dc3cb0f620976620d851d55361e2dd67d3bb107f013617692bf542ed42ac23560052f48560d99	\\xbdff34c3651b244fa23e23cd8c8b30f67daa5125685d8877f11caa2ebb3cfcde923d68176c8bec418b87a5b983f3749bba24b5643db813f5e4a60ec1a53eff9f	\\x63a38db0f26fb4c8bd64924ebf2b53be823b4dab4e719267b5dbe282b088c23ccb67a42a9b4fe2285ad919345a89b6b5a777d7b5634dcffce69dd2123f817246ee3205ee2a5e1b71293bf87c03baef998559140f374e63d5ecd81d0a79370a6bf80e901d19f58c473a98e5225a1d812a90aeac6ab28f10f035ad593953caffb1	43	26
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	7	\\xeaeccfcf07866c5a766a4af171f0272ddf0aa62876e53fffc2a9b131387ba6d845f8594e056e2bc6c854ee12e8dd814dbe865ff1756e08dd6f5b26b6180b7908	\\xb0553fe0f1ed61d61ed6145a04a7ce6c9af2a558f497ff12ad5b4f2b1eb9f70c8128485adf67340459818c141676e06760d47dda4a406529f2c7eb4361048598cbb88c77a4525f24c7928dfe0bbe841d4a2e783d7a55c5074ff8059a98ef43fbe28b79be0ddefed7673ba0f10e35ea8f319d39f39dcf201a53fc3f95b0701dd9	\\x6390aa7833c56cbd3156382322151c89d81f3d08abb6eca6fb7a6162cac1170d88354f9f89f2d6181c300fd1ac55c447289f7816cb4f472f8e50783770e7d1b9	\\x8adf92a846e11a2875231786349ed1ee31dba87d8a6982e23c5bfcf47b62b5d20dabd6426a74ac9f5e8f4361f51b2a52bda10f6beae8dd1112464ac4ac96d4d342ee901811311a99d81d010b9db2e6b3c30f687e2baed1d50b38fff1a56b3a47b2136627870ef8e836a2a142bf10f665a224b62d05384cfe44073685d5773abd	44	26
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	8	\\xec31335f3fcdaaf8ba90d3a48402baedbc33a7210fd69f0e2b4c49df02f2347ab853d089e2530cf788b6d6f04aba9ab51efe8897830df81e422f470a624bdb0a	\\x9608f7f2af2698e23aba21ddc0dfe5bc23700b6f6ef0e5c81b44aac5e3ec7f42755487dca50b6a1e147013492d6c7fd9461a21ba04cee91acf00115ebf003d8eeb026443371443952a7a4395430c88503273fdda893edbe90cda1e2c9d877277f757ccd4f6ff1ca5732c4b757ca65299831cd273e8e0414ac373041b5dd7765e	\\x2cf4c7528ad93aab6e16bcfe8a41022feb39f29fbc309875e1feacbaa5cb620866d093f03663313245e8b4800e7de58a6d8c9d9d711a5ddc13079591bea5a546	\\x52e6ba5cf5c862182ab229864c643400074b222f8e0632014508950b8d0374f91a37086add016fec9797c1db108d97fe43578462744bf43c084f7223f3edf44e80e36e3f1e5450011f67834038aff83f4be64f347c7c116f55584ebbe357d96443a3204ceadf152136e69df52988c253ea836fd03adfaf6c23061d71ea88c347	45	26
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	9	\\x1b4a7a85db2f49ac5aeea7c0c389a492d175088e832936444ab9749418bc5f3711fc48ee8f644ee682d49fa8d295e099565f0cdc9273cc2fb51e07479a468d0a	\\x414deccbca7b93d627f8e8d9732d37b0452eae4bc5def7d27f51c240a0746688a01f1d8afc9ffd673784ee4f557d0765aad9efede56a4a368838e52fe803f518ffa74cebd03f0bcceca90cfbf79748889735459103a5512c6104f2131747cc67eb3b86d83f516ed6cbfb4fb128869b4ce6f46f42ac9baec1006fb95745a74d58	\\x69bcb24952d6e88d9bc8d664a180c488c290aa37343c88a1d9a1bd3a249cabb82a43f514b49c37a92d8ba54925c7b5f4a02b06de293331f18ea6d106c751f6e9	\\x565ab7e7f68e810c5964c0f51072ab0c8af00c7dc43371fb77284457c14ea7582e8fc2c06f232d2552d4069ae8d5222af05098b5f67b54f4e49f38e4bead2b623929e960635892ec68a190c667f0563eee83782bc32d49072216a7559d7494991f6fc38ef1fba6b03f9d2af0fc11eaec924441d04d77f84e18c164be51aa6d04	46	235
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	10	\\x35c879df32c148f82f03be03e77f13975e837c857ab1988160fb3aeb8d6243f93264e34dfc8ca6a04561c2ef4a9ba29a85afea1e3b5d2536c39d14723e8efa00	\\x9b379db4e1e50edeb4e95f1b9fcfd24249f5fc7dc146147be104c1e1f2f35688b0c0f0d1e16a5cb79f4015cd782f89976b9f82a0b416fb894f0b988dec96f5103d817d344b952216c5d27795572a1c3e3c34ed6114da35c0db7adf41863bf95f66938997fe7d4ba4e64a4c629cee5074ebe2eef2201947961fd883ac31098de4	\\x546b16a2b80583e2584e984cfec5c50b750a33b51e3146e0d578313a974b5fc3afa13f4e5b5588d8023a294a0ffa79bcf359252c58b2df6feaafeaa152ed36e3	\\x3f8e6530c90ae38174337a3e8fee8bce9f8145c2dc78086f281b30f8756b850191d3e9105c5e34ef394e4c3f596b49019df2e92c03a24995f8fa3d93fae76e7daf58fc201f12684d4bdee79cc2e65dea7d4df74d9c96c8f8b422aee17f5fbde07df80684cee455445463b2975cc627a3f63f305d3125fbcacc63ba1209fe3789	47	235
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	11	\\x90958debbd367877741b2ca5fc92302a21e378497b9352ccf475edbedb9a92cf54f7879f64bff20be8aea67f815be9dcf583ff116992b421eedefe6cc4cd1908	\\xa3eb42fbb56e64af88e6ce66a85ff08a61f33a984be8ce1e2e9353889ae6e249565397a23cdfdbf0358d6b21944d76727831dd2bfee0355a3ce118ba31624209584d180807bc06bc65664fdb19a41a1f158d718ac34ae1cb86f82e74cadb89aa0b152504805faf49e94c31d4a9569940de27dce1fadc56b3367465f42b2e2272	\\x9185ba068e89f17f673167227df04ecad0afa8f64828cc54c1d8df56b0161ea97c870a1747ffe08d679e1ded7c641b7175aa52ec0bf3e4c1e6eb63dbad51a1c8	\\x3ca97331a31e5e36f6dc2af5f430bff72cfee21e3ec9a6dba9149eef4476a054c9b1d635d8534667eb414550be49752e14060e38e589a357acf700cdbabd7cf444885b40193d2ea11336027046887a90de254bbe8fecaae1ffafcf1ffbe689bb21ee1d4525a0581c559208f3ac559e7a0bcdafba9bb335a90ea8d886f5d0bf99	48	235
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\xcc3309bae04304d097fc047d8563f3464f389f82c65c1147e897b9edd35e166fbd4a69cbcdf38dd58f999a04eb27bff3e792a4c96aa1d00ebca98b71151c01a0	\\xb118b3976278be2f13a1fce81224bbabe9315e7042a3f82c4295a8a339f4dd0a	\\x83a6695a018a38962014bc378f9526a9323f35fe9d3c0b7a07105147f8c0a8456b9ba1e5f39757b079a98fcff8da1c4c004ef2d39e52a0fa4020c7d5ed0c65dc	1
\\x5b5b8adefa2bf9d043d39f1b08918f9c0649a3dd22aab99a5c7f8486e82ef379eefc7d69e13e2c13ddad48e9d764d42f295ad972d965d7970531d2200b2fabb7	\\x0c43117b9600aac0eeacf935ba3b8a2b6e19ca5770ec11c73010c5c4293de83f	\\x76ffd79bee5482208afa3f1573e40f53b0815f89f9b5f0dab73f2bf5e238300c511b99f5362e3d94690758563642622299c57ed88b76ce948898c23b265b6772	2
\\x3d3cb512d845b0bf240a4cd9f76173c554cb6bcc879fee83dd2b364b73bd57b6c1bd016efa0c2ecd04083ebe0dbf30ad8af97f6234cd8a9448fbbf3f6c35cab4	\\x655812d39a6f3af456037ad331e9ec357149ed36bcff4af1113f52daa07c525a	\\x71bd789bc4fabe14c5d30644d62c98df7ce08551d565aab3c26073a7b4a402ba45bb297a711ef04b54fde33b4dccb6248dcb8076b21c07d2051c861d3ea35b5c	3
\\xeaedbc5d2b4fd844738709e374550370f3ef72e2b11e166b44052ea8b68381cd326f21bf32cc76ce21c82fef1468999c154328c88ba5e41d7770cc14f3b780ef	\\x991c4f61b9e76b2bd99e67732fc9d741b99176346cfadea0941815a6acaba123	\\x22f7cab6a7d2e50e23e0b91cf0da18d4919dad4bf57cbe8c2042a5743d8ae83c7d707cbfbba9fe4098a6c1a41ad3cb18598b460bb8c7fa90af135bfd422d4c5f	4
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac, known_coin_id) FROM stdin;
1	\\xc89c8d0918d59ea575af9439ffa85cbffd6f0bce1eb40f5783be382b39eef93b	\\xbd4f39aad741a335a95cd915fe1e1a4a9d4fd96846c0f85d1ff2ec9686999afbced7f4f6060f5cd81fac9b4c3a7c007cfc1a78d1fef1fdc2adaad0e77478a101	\\xa6f3d0a0b7618e8ce7a320f09978f450a63499fc6a122523d099321cc3239b57e56c593f5555a35eb165acf075749508ceec9974ac13cd137c3a0871b08305a6	1	6	0	2
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\xb9e67b89085b6f69d66357bd543b3ee3961189d43b330b98ebfb8180a7b66285	payto://x-taler-bank/localhost/testuser-5Ipb2pS6	0	1000000	1612554230000000	1830887032000000	1
\\xd313ae5e31f5d8ba4ef845d2d0e7ea2821a117fdf570df0fe7d8ace3fcefedcd	payto://x-taler-bank/localhost/testuser-BNDunpIg	0	1000000	1612554234000000	1830887040000000	2
\.


--
-- Data for Name: reserves_close; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close (close_uuid, execution_date, wtid, receiver_account, amount_val, amount_frac, closing_fee_val, closing_fee_frac, reserve_uuid) FROM stdin;
\.


--
-- Data for Name: reserves_in; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in (reserve_in_serial_id, wire_reference, credit_val, credit_frac, sender_account_details, exchange_account_section, execution_date, reserve_uuid) FROM stdin;
1	2	10	0	payto://x-taler-bank/localhost/testuser-5Ipb2pS6	exchange-account-1	1610135030000000	1
2	4	18	0	payto://x-taler-bank/localhost/testuser-BNDunpIg	exchange-account-1	1610135034000000	2
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\x2187e42d2478fe7da69d6dae34bba251e67cabc957a2a1ad2bbee9a66cb70df1a7f0dfe51f175129690ca57f3068809dfe2cb955140da37e2617bcef8ce8e12d	\\x7c0161fb8bd281cac7e6e41a812b50b248edf89a3953acb086dd511f195a026435393d0c57084eaadb037e62372e7a2dd54ac3291d82942cac8a853bdf6a657dfa66e6a7b2c501f4db9f45a7823425873b04e09cd5db5715489ad0b8dd9b6a7b3e5d8363877689e40a24253baafa72590152fcc929f269949d4d7fb6dc43b0d3	\\x20e276169c75d096693af6a889ad3c9064d7b1997b22f414a1f62a568c43e13db730d6c1aff8877cdf27a1c55d8fce1574d2d7d04496325cbb332dd2f3f36c0d	1610135032000000	8	5000000	1	170
2	\\xab75da892dd30834704cfd15c1621cc88574acac161f1b6936b0d7b7ba104a714b6de5684f4bf2419f6c3d5c7ed15df76ea66730e8280fd1626ac5d5704a2e8d	\\x78bb9b42e932d8dbed1e3275336357bbc6c794e742036d00b8b4ac3ec5941314f139a02812e7277bac356711bd55f414db0da92afa45982c51e1075fb21eae80766820e67d951147f627d6308a6c07145a0a86cf7f605b54abf4bc6ce0cb40cdecf1b7767a567747be400e5cbd24b4cba584036d8ff68edfd0dc272b079d6f91	\\xd8235a830d8f0318392d00dbecb9773d5ccd8898a58289f769c233bf2fa09583b72d7ec2133c99ae78461bfb7834423cfd9e9a334981efa281f9f5b1efc68909	1610135032000000	1	2000000	1	220
3	\\x6a576034fe345b1f1691fcb52fbffe5dc553bb0c7c146a2db24bef3dc6522784b1623a7adb7d946c8aa77cae7baa922daf75198172cdf2aadc4d52581ed5275d	\\x49f5ad90f915c08e915de0ee8054df54e541bc07b39fec5341bec925343b4bbdef27731a9b185e31055a6d5f57e5c857fb8cf45d1c8de319f6747829313cb59b77fe8383f68a4045b5149825ed29244f25b9b3515de486df446950d7f5dbf38f6fe84fcf33bde1a6dd4d72be47b725b4859be86ae781211dfcb6a5afb3e25e98	\\xf81b63e7533513a816e4db5156ea06d47b66787c3ffa15936debfdf6d202b118923b0528a3db7fd1bb78abbc894947a799f3cbd1bae092d8263dbf0b1c83d008	1610135032000000	0	11000000	1	26
4	\\x6b80a1970fb534a85ff3d891d09cff8ffc0b87b902c26cbb388135a6868ed31e8b7c46d7667bbc91128b0207b8275cfd29539985b645ef40d5e628de47cfcd20	\\xca7fc04c807d171563b34a3bc8595b5c121ab87f1c4a2d75834c55a71a91257011f03175e0d8bb697e0e165b3dfaac875b2657ed7ce49dcfa2cf4e8e917921e109906cf96fa3f5ef12961c622b69df0f2c90918cba1570a1a28d2c17a7a0e40d062ad041896e352029bf28648c297a71ce6a59f51d5db47ac0bd5d136b1b3558	\\x4ec645254f7a2071a0a9ce05e41a2f68e3c4b3d5ee9ca17d631333c1b6ff8800c0cb4f8bc7e457d7445b34e9bd1f19cc468dc40195d39c22ea3c0757738ec503	1610135032000000	0	11000000	1	26
5	\\x4c6141d5ea1cf5d634262726e616c7de162f06b9ea1f915c9c9a214e2b94143ae920987fcb4e230937c587d0102dc36bd475c7b6a4154d17af1f2744f65258c0	\\xece6f9ec3f0c6546a746f829d8556fb0e41327539b1ea04e4d7fdd0746960acce89ff1c406c41d3f90d90cc5083e7cbe24e9eb34c5753c1d740503b6455abdc18b3291c1d171c571a3944ff68915260afc85b8470640294c92f4f2b18a4920a3989f814b80c29a9da3f0c5d89c95aaaf0138509dc547cba44def9cecd0a562	\\xf8fc2a12472c68471cb000b9e44ae74b424ea6d4fe8ea0244833bdadd83f965d3f9ccd75f43e802e67e773b12973265c23342211de0d58ec0e80f026fdc8ae02	1610135032000000	0	11000000	1	26
6	\\x815f9a0dd04f196b028b86350120d1dbf869bc4273a605c439b7d948936567a3feea52140896a5daa3fd8144e8dc42b25682b58d57074383f5d3509ecdaf5a6a	\\x470ec29801011ed6b20ca1e58b5d0403ff17f3502c444b95070bdf70907263cc98c38b76cb2dba673a1b659f9d563ad14e8df7527ebf2a5d62441996cd2d076e1955436e19f638c7c5b4967ac2d68e5d38daf9852be0395d8580904e234db2d325d7676ee93f0882d143271ac8d685f7d12d0856fa13c9b804111e4341cb04a5	\\x09f2b8a0b20855715660ccc4cfd7c7e828bad0e68b464ea638f952e3b8b0b1341bab3c719bc9aef8a38d0d94e466680fe3055d0da91741d2713ce3c0952ac606	1610135032000000	0	11000000	1	26
7	\\x5b6b45715f93b82da90e2e430952682218fb0505508fe183c470fa2fed3875302989b39f2eccb571bb976ce5ffe3a8410747af2f2e535b603dda4b353e8fdfb8	\\x1e1a8d9f30a73c36219b843eb18c11f2684a4c3f3780482d5224862cdf05fdc7bfa5053f690a6368c6e7b4d8912b64f3ae308c534f82c8df2b6d2830fbec3dbefeb741f5e4131e8dbcb636fcc31fefde3d6c5f4d0df827779089b7eabf10958b78a9f7a37fdaef975d0b751d6411c7e877acc55422bbf5623c87c97f099ba54a	\\xf9542114a18ea1f22b054ca97f1ec20bf881f0de56866a9bff1b91c9a16a3f2e51d81c279d9a9a20bd7bb0fccd3c84a2bde27a9034c961dd159a2b52e98d6504	1610135032000000	0	11000000	1	26
8	\\x8a5bde2716f93c4f0a10f1aa7f752de4b37f7a2c9e96059eed9beef63ce1188e9b5e7a1952a161c72b2a315ffb98f45c18dc5a012f3d00a307002411098c4f86	\\x9bd196923b9a397641a81b2f178dddf23483cb38279e2e0669de2a20e9ad35a39b236003d0b81a3b6fadf7fc341fef331125f59e6c69c25a9912f3d969e5fd391b47a67ac5a9863b0ff75ef989c49b18d274f4abca04d5b1db9f779b6ff77283bbf2180e34a114273f51352bfe88a3837734bf5e40dc5ba77decb0505e137c42	\\x9736fd0350da423fff147927395a266a1ef2382c41c0fe95a2b54abe02ae8f4bb8dab276d2775ac683a3452fa02a248f6be97c33a569136fdc2f15aa4751ee0e	1610135032000000	0	11000000	1	26
9	\\x3cdccea8d75de3c3ec49d673a1d2b5d88169b198d2c2d9d58093bc9575bad7630e891a05634b09b1de86e9befeb3badf69132607e196d1937d9f99d60363c1e4	\\x3c6551cc656c83cd1383a32e148fcf90908dc2892c83ec1f2bb68d2a1ecc8cf8d9f108f696f19fe357ae58db15a78b09435a7ce76d4eea28ee13a770efd0619cd9fb32600fb591243fd8fe2a63df133687beb173638284f8e5ae573e311d85888f3ad596ee21cf82118a374890c51aa39cd787248306552abf3183e2e148efbf	\\xe3fb75c47d5000bca234b27ab961fd9c85718400e9db06d72a032524f2f44ada6dae77a99c9157de87e8cc1ec615c7732a80a6df87b1fb2b9b085336c4f9da07	1610135032000000	0	11000000	1	26
10	\\x163204efa43967e743ac3ffabbf5e69569799de4e1ba64fc73ce440d77d6116050a8a229587d4498ea19c2d62057f7e9da0a25207f0df6742595b92c0f5380d1	\\x22adb732a34b161909a7974fe93b4379bbefdb646f23c1483b2797df8658d6e5f495aad259fd066c69ee060b603eff2827b0e892f12f89d89e347d22b343567b22209de4ed6181f1b0fb644b3acd462057bae02fb93f49d568ab92040d1a4d71f3b7f71465cb1088e7e413fbf879f8ce7cb67a2469e2f8dc889f333f2674ae6c	\\x5f127cd3d438c866705722d062e247ced4e15e53a3c7e27463faa89d3ff2be6d597dac15326222d12e7f606463f560abd2fe5a414c5653598a3e2b262c84e50a	1610135032000000	0	11000000	1	26
11	\\x556689736cb1ddbede26dc3380d7515349ed3bbfdbebbe93ea5b492b0679e140d0f047ba030ff16fef7074ba1f4bd37efb810684060ca7cd234c269d0a28e358	\\x8891836f7554f6d74ed77d24759981cdbe1e937e2ded560d6c95d12241a148312f51758de9622524776866db04ee37eff6b6cd2af09bcaaf119f86f4671082705dee597413c5fe2a62424f05bf5e3c12d8fa255abadf2e134c9f94f8195102a551513298f4553e773b7023adc5109f0db3a69f19699370df113c21e400fb9c63	\\x90c5a5f47f056c3f612506f9e4c41f7c8eb0cd7c27666a674ba9cc7ea30f77f8e2258d1c65e440164e2a25301343f1d1898b7073eaa6dd7f70c94b19b88ccf02	1610135032000000	0	2000000	1	235
12	\\x68f75b449952d93d161695e3d8535a784fb10a76fc9468f27a0d6e0c4012346e901b8feaa9700e2d9a56916a7b78dccfdc0257d8e2bc569cf2b02bbeffb93d83	\\x4017ec2df869a20d89cb94c6dafbecaa271dab311aa36757d7521b0e0368f7028b7727529b1e216eb7a3e4634f31de4b264895ab1a49cbfc000af1bbd2d405e28cfd25f91784cafa190fcafff77355e63a16f48a48e2c509b071392b9bf3a178ed56ef919af99d5b9c31e2b8d60e9dd69617558f879313be39453d2fd4215d0e	\\xa654b333cee16e3bc8590dcae136333f901e3aea131ce94f04c342d095550dd90f21b1bbfbdd9a666fcdc48650ece60086784524fdd8b8aab15b917f02016009	1610135032000000	0	2000000	1	235
13	\\xdd812872a968f0652d5d8fdbde3851757a40fed50aa92b32366b7ff07ec000c763016b4168179052fc882568e8efe7a5f3145d9cf9fb10bf8251a92d5101fa13	\\x0592b19e4be2e50900c85edb1efe4fd81350a4b553aa4492d5249f7b3360602e4099ce0037f9c6480e7e8eed7f86a37c78c94fc02d902dd8b9e46f8b0df39fb5ae36dbaf46ac6ba8873400c209de7e9d17c834018ac860fbe09001215a41866fc7c63e32a12b34a2ae80bc2139d3ccbe007336a4c7a1dcf30adeae51977e4a05	\\xf1c587b072004e51696380d14d5753f60b12f90b75e705b9013976504ab2a26cfeb250f6e5a2a78a131b018d8ab95fcb066304565eba11ab0af7331e68c2f90d	1610135039000000	10	1000000	2	65
14	\\x11eba954f6acdf9ced0ff9fd99a9946bcaf945dbfe737f390529a6ed501c794f5db5070b530ab43be18b8edc9db83855b2cf75face74affa36dd4ef17343834a	\\x29ffaa17b1c550830595b1273f7fdebcedfc0b9358a2b6f4ccb8efae531f711b6c794d508bb3176fb7d2c30a440178391c6cf32860a035b407647b93ad36945563b2896973ea248ebe9cc3e0e29d3f2be9a03b894b6f04b20aac9a487f482488ae37bce1e59f58efd310c7834702320c1af59d433bb978559407e22f7e0900d5	\\x72da33983f63951f631076652fffe42efc6456301dce7a145cbade9a5bae2f68eabafe7c2f083dfa18ff88de37bd6bc8e1773b30d5050185603ec9bd885b6c05	1610135039000000	5	1000000	2	105
15	\\x670a34b764d91186650ab28596eb11f3fa178c4b0683775e8c36bc3c926d855f707c3ec3929e223fe93ca210e4d88c0a64362495c4e404c029bab0740240016a	\\xabedd45e9720db1fdc7ba361fbfd7314fbb49b736095773e3beeec013fcf388a78b5b3ec7739cdf3e2f49d2bcb80bbed1e3a97954ba24baf3fe11a9c16e96e74e294129a0aa39b65d32f1d4b5f2eb96965e14a9dc071040be1f3df2b113368ce9efe748eacbd0a08be30d5f792a62d001fdeef6f449e88e8616374833c95fe8a	\\xd5633224a4192ca5c2119690b041d3422579720fffede0df576a43f3cc4a824e5c9bc35ea0d414d8678651e59158291b7d6fe366db611d487d7054187b6a1406	1610135039000000	2	3000000	2	127
16	\\x72e32403a9766f9a037ad0da12498bb4b86029521ecc992a69dd74dc479bbbe4678eb690169e83d2a039bdc55a8c49e973193367244ff19eca5c053e8600907d	\\x8f7aba4b4735a27b9ecc28f9cc50cd153d832b918701a18e6baed3ac64de6933f90e16d9825d57943aa9f95cdd4842bae7121df5ff338eb3a495d38894eb63300a91aae037003e2f046aa4850595ce5f015b4e84f1ff5f4f3119108bc2c363fd3f2fd6d5b32b8a7560f1c00b39c9d1bf41b0e26b83148e3b0bd5abfaccfe3596	\\x0ec7d845aa3ea8f3dd82a047afd85d23d9edb5a4baf1d438bd037cc0f577d6cec83b7d33365f5d9d57ba19eb8c539a7561f61498f65faabde880bde7f98a1408	1610135039000000	0	11000000	2	26
17	\\x36e8af0d3ab6e5a2138b0ab5dfe021ec1c566283a5db0ff0e23a0df8d53b79c63a5953ae716eb78ed1eca4b131b2709c56236aac5db33776f88bf13d1825426a	\\x894040b881aef31da87bd4fc318ae679293ee4acd0105fc21fc0e3ff0d1a1abb1bb153a18525c86a2b8eb7aed1f3a5a1db253ceef8ecb1fb6674939e08a59f86a54af2add6fd853ac5402542af75a2a9603f4e641f779e6870c51adaefdb332176a7851c89fcfe857304fdee6915f749d0a073bcd6bf5b5c08acd6b06be67ebc	\\x92bb0f0362da4e8a74f2968ebfa94145c942dfc585d998a56e0e862ec97e789f44f2374eeeb20f81867124f2e722081c8c80d6a5a79dc9e2d43590dd39285a07	1610135039000000	0	11000000	2	26
18	\\xfdca4c1cbd22c2a417cf0931bc6b77ac4ecf796786b01ad4081744729ccafc997c2abe438985fb75368e5cff6c5d12e64beed431f717c569725163ec766025aa	\\xb0c1a5b545e53105f0eb78f187c8274f56b1091d991e247009a2e35135942489e520c8c2a25d29e0de0587e37c382a93faac3471b19f7817a084bec2c71f3055ab8ba21cb9d4c02e8bf691857476aa03e5a5843a5db1d1ca4eb9c3a3000757728f5249eb2b9cb4e8dd2a3d3fc4aa7232c54bee438271ca04116f9749a843daa6	\\xa353deba5c243e86f30389ace3b9502f55d2052974c63fef7816b3c81ac4e44ef297901a4bb9413cd6f93b30e9a666fb2d9ea63ef11015e9f30bf350357bcf00	1610135039000000	0	11000000	2	26
19	\\xd50a737a0b556684651f154b1f15b268421fd0da1580895d1a6b72d90fd00ec33bef52cc69445cb3e62a0a44b8bfd8409de982c1ed86739b100780acc51b31db	\\x4b078a9df950909a767e891df5a121c35b288ee869f80b1385c167af1b48b0e42863c09dcea9dfcdb802ee3e23f7f6f1b4980dc30bc1e499ccfc39c0528ef6cac4b570d5187bf1530f01cb188b6cb043a11aa993c2a17b64df3c0f2dbf1a2da93e5ea8235d00c9fc7bd55c24703684d86de25d6cdf159ad3f0c488f129adf94d	\\xab152ee7f62b2e6ddc94fe6ee7505854cd016ab8db531252615e05b32f778c38c7125733fbbacb5af3fe29dc7f9171218ae391980b05a62c41e0c847dcf2970d	1610135039000000	0	11000000	2	26
20	\\xd4109f475501033b9d147c00f6686d056fec791ce7d15789580778e6aa01e8af4cb79a69d326dae1bc227030ca47ff9cfd52353abd98d46b27a0b23fbb0d8285	\\x172e80e0f236dd54bbdf65bc8734e7b55bba9da6cd73111984044f48aa44e5f74d6d816c3cc63d3945504e065ee68fca6bea94acf38e4c966cd336f33b7a446a625c7130543cc3a33c047c93be2055b5a08a5149f8bc92f40881a692197f4e9731e0a75f5d5e7b92cf4def96697042c0868972c88d15d6afc439419a1ea28685	\\x612646e0b916e5190ee7e2e31d3ba9c5783132ec117c2a923da9f048cb9735a95431e3e6a85a21198aca6d9ab200216aaa20b017d9c109cbe49ff5437c52d106	1610135039000000	0	11000000	2	26
21	\\x29b23a567bdea2fa770143e16294afbb08a17da92d4b353eea58fc27358aaed66857f561008aa50c9b992bdc2faab8e032452e145101e3686cc5508bbbfdc332	\\xae8d5838ccf01e1f632d6830dc2ce077f84d6db135a76d00f2dee7238fd6ed73a34ea47f2e985d6a7ccb0f78aa98b822f470309dad03195611388cc0424a54632a54239bb7e6070d538069e3d05e4aa7a3f057dfe3c31a867850368c55bf8666b9974eedec0083059d53115583184f526fae026dc87586c8f441309871fbfae5	\\x5cc094f9632a6ea48239f704da745a6fe735a9debd8995aa4170d7cab5c1d0799cb23d0cc5a3cebbdf00ff7cfde4f00a8093ff87d9f975ad99b5f19865462c0a	1610135039000000	0	11000000	2	26
22	\\xb9af368bf25c71b1b40a99b76c5c9254070fea3a8f4fc898ca40e37859d37fdfec8ce3fe178fd0f24741060dd061978d7f3e9a013f41510746cc0bb7c9c08ff5	\\x3aad281177c4f5d06927cb35f6805c8ed23fad39a266f592aefd243917b307fa5b9b9b77c7f85b9c30af3936f6f42d34a18128941055fe458c310f86a891feb715e92e143ce7fc9453bc60886ecee0e47ccb5ee169d288c689de641f1da83e2b3bc151cefb799a4d760b235fc54bae3e5bb6abedf91cd6c1bea8725a6048b559	\\xa9c4eab9215360a91423dab80d8fc08009b68c5b345dc44b6efce9366417b5e3db36b955f1116e368042b1e0e8e52428646939b1144ea2ada704e11956dab808	1610135039000000	0	11000000	2	26
23	\\xa068bbb97e9274f9777c0dad52c484fca1b888f76d485419fb5b05c0055e8738d3de8417b9b7f8ff4d6c28c40a4d1fdb64ecbcfe05b72d727db8b410f697a67d	\\x69532e873d11bd17153a93c0c9b4d6e5cd967cc444bbf22de63271bef5d4cb2174357217773841c22db8eaed175e5d9213c9ed6401c671796cf61d9529a435e1224c2e70cc53f7126a6fbd16134bc97ed38f4d8200d50591bbd7e5f454d046f8bac2010d61f0e97b99ad4b77336a09b2826953e29826bf9ea9b16dcc235dd4e1	\\xc8af55bc3d13c75004c5a06533e27ed72e64bd796dadb1a284f86a9e004ca50bdd2ba18f69fcfd3a91c4aa1b0a9637bfad3100e8c5ddc8d1495bc9f49642b80d	1610135040000000	0	11000000	2	26
24	\\xd1d1e00275391d3b0626cb625cf40bdbde5ec741c74eb63a529da3be4ac7cd09cd5f9f2eba0687f3918549a0a99533006ea036854da6776b99a0a7910d3ac13a	\\x1979e845cee76eca39d59f2264bdd2b1d4e60b9cc7fceac9b3fc6d3c6dadec69cbb9f40e8855ccc2715ded1e51b0d61ae8051b214b7d6b688d5575ca9c8106430d875d7e803e319c7c4f2e7d9eaea1c62eee3e3dc07af9fe7a3e4bea7e8b0487029d1108070ac48cfe75d679b44b320496f61948360e2d85c6a3ad8669aeca74	\\x0ea4541a3d33685415b95ad184f04038ffa77084c9334c2c9020b26174073891edc591fdb4dec6ed9768e76ff40989aa561d0123bcb3c85a2292e67379892c00	1610135040000000	0	2000000	2	235
25	\\x067ce69f3fc877ea7730e248ae3d9e57536640efce8b331f0368d228e236b6cbb92664fe930ab0925bace1c74d4644d70be2898e4a816ea7cc692fc6843e7777	\\x9009bb584292d3f6a81c926001414da14b01b4d77f846ab99fe0c92cd1fe0880bd2df60f7656e3eef048c223db21ef9d44b82a52cb5ab6d4e2dd877279adf84063e9b4c601f26ff6dfdb94a13ec20865ae92e953a5ec5d48ba159031e977892b804f337687f4fe40f5b2acd93741e3bd94123c81493faf8e01048bb4ab2a7f93	\\x63d5986e8d7a759fd72046f06bf703149b2cca83688e7112e39b6f66bb4eccae68de5a316ae84171149c2186e9bf932eff6ef93eb420a095a1740ba807e82c0a	1610135040000000	0	2000000	2	235
26	\\x83ed051df0b369661a2a57b612038892de17dc881d14c13504930b1fe2d64fc9ab20daac164805103517172491ef09f2f070c46e2838f421851d5f6097296426	\\x44bde085cfe44b7940bec185bc954c5b7306e3829929acb2714aa037196795889f054dfcb597868257d6cd7622da82c341472ddff21651d4f281776348e8b8db22169b3bd5bb6373eae457f2b13b74cf6611701dd8321a015e55e3246eccd3f1da2ad17b865a35cd2a624a244302b330296cec3f55cdbecdb8a14ab966e860b9	\\xb298ec620be1367fd37c976ab9605c8d704b43d2b38289941734a9a774c3dc783fb32d0236babf6361516d2028a71f079d7595956c19cb4adcd0d5465ab34207	1610135040000000	0	2000000	2	235
\.


--
-- Data for Name: signkey_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.signkey_revocations (signkey_revocations_serial_id, esk_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\xb81540176bd1c17b00f07c3e80b9ba0e50ddcf655761ec8aeafeca96715630bf41357fc284a519bb56758747b41b63d638e61e468cea132f7e4ed8042a980102	t	1610135013000000
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

COPY public.wire_fee (wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig, wire_fee_serial) FROM stdin;
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xe223d0cd64d43e6f2948926ff04d607747855de7d2e5aa0d99c2a71377938b54a1d0b2fad7b9e821f54b4c021af998e7b02a101af89c179e467d1ce58d634107	1
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
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_denom_sigs_auditor_denom_serial_seq', 424, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditors_auditor_uuid_seq', 1, true);


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
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denominations_denominations_serial_seq', 424, true);


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
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.exchange_sign_keys_esk_serial_seq', 5, true);


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

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 5, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 1, true);


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
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_revealed_coins_rrc_serial_seq', 48, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_transfer_keys_rtc_serial_seq', 4, true);


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
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 2, true);


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_fee_wire_fee_serial_seq', 1, true);


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
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_denom_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_denom_serial_key UNIQUE (auditor_denom_serial);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denominations_serial, auditor_uuid);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: auditors auditors_auditor_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors
    ADD CONSTRAINT auditors_auditor_uuid_key UNIQUE (auditor_uuid);


--
-- Name: auditors auditors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors
    ADD CONSTRAINT auditors_pkey PRIMARY KEY (auditor_pub);


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
-- Name: denominations denominations_denominations_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_denominations_serial_key UNIQUE (denominations_serial);


--
-- Name: denominations denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: denomination_revocations denominations_serial_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denominations_serial_pk PRIMARY KEY (denominations_serial);


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
-- Name: exchange_sign_keys exchange_sign_keys_esk_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_esk_serial_key UNIQUE (esk_serial);


--
-- Name: exchange_sign_keys exchange_sign_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_pkey PRIMARY KEY (exchange_pub);


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
-- Name: refresh_revealed_coins refresh_revealed_coins_rrc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (rc);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rtc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rtc_serial_key UNIQUE (rtc_serial);


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
-- Name: reserves reserves_reserve_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves
    ADD CONSTRAINT reserves_reserve_uuid_key UNIQUE (reserve_uuid);


--
-- Name: signkey_revocations signkey_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_pkey PRIMARY KEY (esk_serial);


--
-- Name: signkey_revocations signkey_revocations_signkey_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_signkey_revocations_serial_id_key UNIQUE (signkey_revocations_serial_id);


--
-- Name: wire_accounts wire_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_accounts
    ADD CONSTRAINT wire_accounts_pkey PRIMARY KEY (payto_uri);


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
-- Name: wire_fee wire_fee_wire_fee_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_wire_fee_serial_key UNIQUE (wire_fee_serial);


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
-- Name: prepare_get_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_get_index ON public.prewire USING btree (failed, finished);


--
-- Name: INDEX prepare_get_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prepare_get_index IS 'for wire_prepare_data_get';


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


--
-- Name: INDEX prepare_iteration_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prepare_iteration_index IS 'for gc_prewire';


--
-- Name: refresh_transfer_keys_coin_tpub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_transfer_keys_coin_tpub ON public.refresh_transfer_keys USING btree (rc, transfer_pub);


--
-- Name: INDEX refresh_transfer_keys_coin_tpub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.refresh_transfer_keys_coin_tpub IS 'for get_link (unsure if this helps or hurts for performance as there should be very few transfer public keys per rc, but at least in theory this helps the ORDER BY clause)';


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
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_uuid_fkey FOREIGN KEY (auditor_uuid) REFERENCES public.auditors(auditor_uuid) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


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
-- Name: denomination_revocations denomination_revocations_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: deposits deposits_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: known_coins known_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_exchange_signkeys
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
-- Name: recoup recoup_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: recoup_refresh recoup_refresh_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: recoup_refresh recoup_refresh_rrc_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_rrc_serial_fkey FOREIGN KEY (rrc_serial) REFERENCES public.refresh_revealed_coins(rrc_serial) ON DELETE CASCADE;


--
-- Name: recoup recoup_reserve_out_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_reserve_out_serial_id_fkey FOREIGN KEY (reserve_out_serial_id) REFERENCES public.reserves_out(reserve_out_serial_id) ON DELETE CASCADE;


--
-- Name: refresh_commitments refresh_commitments_old_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_old_known_coin_id_fkey FOREIGN KEY (old_known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


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
-- Name: refunds refunds_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_reserve_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_uuid_fkey FOREIGN KEY (reserve_uuid) REFERENCES public.reserves(reserve_uuid) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_uuid_fkey FOREIGN KEY (reserve_uuid) REFERENCES public.reserves(reserve_uuid) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_reserve_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_uuid_fkey FOREIGN KEY (reserve_uuid) REFERENCES public.reserves(reserve_uuid) ON DELETE CASCADE;


--
-- Name: signkey_revocations signkey_revocations_esk_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_esk_serial_fkey FOREIGN KEY (esk_serial) REFERENCES public.exchange_sign_keys(esk_serial) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

